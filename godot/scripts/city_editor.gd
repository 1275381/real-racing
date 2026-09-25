extends Node3D
## 城市地图编辑器：打开真实的漫游城市，逐栋点选建筑并拖动 / 改参数 / 删除 / 新增。
##
## 与赛道编辑器（map_editor.gd）分开两个场景：那边的数据模型是一条闭合样条，
## 这边是一组分层元素，硬塞进同一个文件只会两边都难改。相机轨道、屏幕拾取、
## 射线打地面这几段骨架从那边搬过来并修掉了几个既有 bug（见文件末注释）。
##
## 存的是补丁层（只记改动过的字段），底板是 res://data/city_bake_v1.json。
##
## 操作：左键选/拖 · 右键转视角 · 中键平移 · 滚轮缩放（选中时按当前轴微调）
##       X/Y/Z 切轴 · Tab 俯视/透视 · Delete 删除 · Ctrl+Z/Ctrl+Shift+Z 撤销重做

const CityData := preload("res://scripts/city_data.gd")

const PICK_CELL := 40.0        # 拾取用空间哈希格边长，与 FreeroamMap.CELL 同量纲
const UNDO_MAX := 200
const NUDGE := 1.0             # 滚轮微调步长（Shift ×5）

# ---- 相机 ----
var cam: Camera3D
var cam_yaw := 0.9
var cam_pitch := 0.85
var cam_dist := 260.0
var cam_target := Vector3(180.0, 0.0, -420.0)
var ortho := false
var ortho_size := 420.0
var orbiting := false
var panning := false

# ---- 世界与文档 ----
var map: FreeroamMap
var doc: Dictionary = {}
var recs: Array = []                  # 当前建筑记录（map.bld_recs 同一份）
var by_id: Dictionary = {}            # id -> recs 下标
var hash_grid: Dictionary = {}        # Vector2i -> Array[int]
var dirty := false

# ---- 选择与拖动 ----
var sel := -1
var dragging := false
var drag_from := Vector2.ZERO
var axis := "x"

# ---- 撤销 / 重做 ----
var undo_stack: Array = []
var redo_stack: Array = []

# ---- UI ----
var ui_layer: CanvasLayer
var ui_name: LineEdit
var ui_status: RichTextLabel
var ui_axis_btns := {}
var ui_fields := {}                   # 字段名 -> SpinBox
var ui_tint: ColorPickerButton
var ui_panel: PanelContainer
var ui_hide_bld: CheckBox
var ui_jump: OptionButton
var open_popup: PopupPanel
var open_list: ItemList
var btn_del: Button
var _del_arm := false

# ---- 选中高亮（一个 ImmediateMesh 画线框，不改实例色）----
# 楼体着色器把实例色 alpha 当类型标记用（1=落地 0.5=退台 0=素面块），
# 改颜色会破坏渲染，所以高亮必须另画几何
var hl_mesh: ImmediateMesh
var hl_mat: StandardMaterial3D

const JUMPS := [
	["市中心", Vector3(0, 0, 0)], ["出生点", Vector3(180, 0, -540)],
	["环线东北", Vector3(620, 0, -620)], ["北山地", Vector3(300, 0, -1800)],
	["西海岸", Vector3(-1020, 0, 0)], ["东沙漠", Vector3(1600, 0, 0)],
	["南郊野", Vector3(0, 0, 1400)],
]


func _ready() -> void:
	doc = CityData.default_def()
	var want := CityData.pending_map_id
	if want != "" and want != CityData.DEFAULT_ID:
		doc = CityData.map_by_id(want)
	CityData.pending_map_id = ""

	map = FreeroamMap.new()
	add_child(map)
	map.build(doc)
	map.visible = true
	# 编辑器里没人每帧写相机/车位，遮挡淡出的通道二会把原点 15m 内、
	# 高于 1.6m 的几何全 discard —— 两条高架快速路正好在 (0,0) 交叉
	map.disable_occluder_fade()

	_setup_env()
	_setup_camera()
	_setup_highlight()
	_build_ui()
	_reindex()
	_refresh_status()


func _setup_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.85
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.shadow_enabled = false
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.86)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.5
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	_update_camera()


func _update_camera() -> void:
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ortho_size
		cam.position = cam_target + Vector3(0, 1500.0, 0.01)
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.position = cam_target + Vector3(
				sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch),
				cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	cam.look_at(cam_target, Vector3.UP)


func _setup_highlight() -> void:
	hl_mesh = ImmediateMesh.new()
	hl_mat = StandardMaterial3D.new()
	hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hl_mat.vertex_color_use_as_albedo = true
	hl_mat.no_depth_test = true
	hl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = hl_mesh
	mi.material_override = hl_mat
	add_child(mi)


# ============================================================
#  索引与拾取
# ============================================================

func _reindex() -> void:
	recs = map.bld_recs
	by_id.clear()
	hash_grid.clear()
	for i in recs.size():
		var r: Dictionary = recs[i]
		by_id[r["id"]] = i
		var hw: float = float(r["w"]) * 0.5
		var hd: float = float(r["dep"]) * 0.5
		var x0 := int(floor((float(r["x"]) - hw) / PICK_CELL))
		var x1 := int(floor((float(r["x"]) + hw) / PICK_CELL))
		var z0 := int(floor((float(r["z"]) - hd) / PICK_CELL))
		var z1 := int(floor((float(r["z"]) + hd) / PICK_CELL))
		for gx in range(x0, x1 + 1):
			for gz in range(z0, z1 + 1):
				var k := Vector2i(gx, gz)
				if not hash_grid.has(k):
					hash_grid[k] = []
				hash_grid[k].append(i)


## 射线与建筑包围盒求交，返回进入距离；未命中返回 -1
func _ray_box(o: Vector3, d: Vector3, r: Dictionary) -> float:
	var hw: float = float(r["w"]) * 0.5
	var hd: float = float(r["dep"]) * 0.5
	var lo := Vector3(float(r["x"]) - hw, 0.0, float(r["z"]) - hd)
	var hi := Vector3(float(r["x"]) + hw, float(r["h"]), float(r["z"]) + hd)
	var tmin := -1e9
	var tmax := 1e9
	for a in 3:
		if absf(d[a]) < 1e-9:
			if o[a] < lo[a] or o[a] > hi[a]:
				return -1.0
			continue
		var t1 := (lo[a] - o[a]) / d[a]
		var t2 := (hi[a] - o[a]) / d[a]
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return maxf(tmin, 0.0)


## 沿射线步进取候选格，再逐个精确测包围盒。
## 屏幕空间全扫（赛道编辑器那套）在这里语义就是错的 —— 它按中心点算距离，
## 一栋 30m 宽的楼得点中心才选得中。
func _pick(mouse: Vector2) -> int:
	if ui_hide_bld != null and ui_hide_bld.button_pressed:
		return -1
	var o := cam.project_ray_origin(mouse)
	var d := cam.project_ray_normal(mouse)
	var best := -1
	var best_t := 1e9
	var seen := {}
	var t := 0.0
	while t < 7000.0:
		var p := o + d * t
		var k := Vector2i(int(floor(p.x / PICK_CELL)), int(floor(p.z / PICK_CELL)))
		for ox in [-1, 0, 1]:
			for oz in [-1, 0, 1]:
				var kk := Vector2i(k.x + ox, k.y + oz)
				if seen.has(kk) or not hash_grid.has(kk):
					continue
				seen[kk] = true
				for i in hash_grid[kk]:
					var ht := _ray_box(o, d, recs[i])
					if ht >= 0.0 and ht < best_t:
						best_t = ht
						best = i
		t += PICK_CELL * 0.5
	return best


func _ground_hit(mouse: Vector2, plane_y: float) -> Vector3:
	var o := cam.project_ray_origin(mouse)
	var d := cam.project_ray_normal(mouse)
	if absf(d.y) < 1e-6:
		return Vector3.INF
	var t := (plane_y - o.y) / d.y
	if t < 0.0:
		return Vector3.INF
	var p := o + d * t
	# 钳制到世界范围而不是赛道编辑器那个写死的 ±400（城市是 ±2800）
	var lim := FreeroamMap.MAP_LIMIT
	return Vector3(clampf(p.x, -lim, lim), plane_y, clampf(p.z, -lim, lim))


# ============================================================
#  命令（唯一的写入口）
# ============================================================

## 所有 UI 路径都构造命令再走这里。这样「撤销之后 MultiMesh / 空间哈希 /
## 属性面板忘了同步」这类 bug 从结构上被排除，而不是靠每处记得调刷新。
func _apply(cmd: Dictionary, forward: bool) -> void:
	if String(cmd["op"]) == "batch":
		var cs: Array = cmd["cmds"]
		for i in cs.size():
			# 撤销时逆序回放，否则「先删后增」这类组合会错位
			_apply_one(cs[i if forward else cs.size() - 1 - i], forward)
	else:
		_apply_one(cmd, forward)
	map.refresh_buildings(recs)
	_reindex()
	dirty = true


func _apply_one(cmd: Dictionary, forward: bool) -> void:
	var op := String(cmd["op"])
	match op:
		"set":
			var i: int = by_id.get(cmd["id"], -1)
			if i >= 0:
				recs[i][cmd["field"]] = cmd["to"] if forward else cmd["from"]
		"del":
			if forward:
				var i2: int = by_id.get(cmd["id"], -1)
				if i2 >= 0:
					recs.remove_at(i2)
			else:
				recs.insert(mini(int(cmd["at"]), recs.size()), cmd["elem"].duplicate(true))
		"add":
			if forward:
				recs.insert(mini(int(cmd["at"]), recs.size()), cmd["elem"].duplicate(true))
			else:
				var i3: int = by_id.get(cmd["id"], -1)
				if i3 >= 0:
					recs.remove_at(i3)


func _push(cmd: Dictionary) -> void:
	_apply(cmd, true)
	undo_stack.append(cmd)
	if undo_stack.size() > UNDO_MAX:
		undo_stack.pop_front()
	redo_stack.clear()
	_sync_panel()
	_refresh_status()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var cmd: Dictionary = undo_stack.pop_back()
	_apply(cmd, false)
	redo_stack.append(cmd)
	_after_history(cmd)


func _redo() -> void:
	if redo_stack.is_empty():
		return
	var cmd: Dictionary = redo_stack.pop_back()
	_apply(cmd, true)
	undo_stack.append(cmd)
	_after_history(cmd)


func _after_history(cmd: Dictionary) -> void:
	sel = by_id.get(cmd.get("id", ""), -1)
	_sync_panel()
	_refresh_status()
	_draw_highlight()


# ============================================================
#  输入
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_X:
				_set_axis("x")
			KEY_Y:
				_set_axis("y")
			KEY_Z:
				if event.ctrl_pressed or event.meta_pressed:
					if event.shift_pressed:
						_redo()
					else:
						_undo()
				else:
					_set_axis("z")
			KEY_TAB:
				ortho = not ortho
				_update_camera()
			KEY_DELETE, KEY_BACKSPACE:
				_delete_selected()
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				orbiting = true
			MOUSE_BUTTON_MIDDLE:
				panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_on_wheel(1.0, event.shift_pressed)
			MOUSE_BUTTON_WHEEL_DOWN:
				_on_wheel(-1.0, event.shift_pressed)
			MOUSE_BUTTON_LEFT:
				_on_left_down(event.position)
	elif event is InputEventMouseButton and not event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				orbiting = false
			MOUSE_BUTTON_MIDDLE:
				panning = false
			MOUSE_BUTTON_LEFT:
				_on_left_up()
	elif event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		if orbiting and not ortho:
			cam_yaw -= rel.x * 0.006
			cam_pitch = clampf(cam_pitch + rel.y * 0.005, 0.12, 1.45)
			_update_camera()
		elif panning:
			var sc: float = (ortho_size if ortho else cam_dist) * 0.0016
			var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
			var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
			cam_target += (-right * rel.x + fwd * rel.y) * sc
			_update_camera()
		elif dragging and sel >= 0:
			var hit := _ground_hit(event.position, 0.0)
			if hit != Vector3.INF:
				recs[sel]["x"] = hit.x
				recs[sel]["z"] = hit.z
				map.refresh_buildings(recs)
				_draw_highlight()
				_sync_panel()


func _on_left_down(pos: Vector2) -> void:
	var p := _pick(pos)
	if p < 0:
		sel = -1
		_draw_highlight()
		_sync_panel()
		return
	sel = p
	# 拖动只在按下那一刻拾取一次，之后每帧只是射线打地面；
	# 起点记在这里，抬手时合成一条 move 命令 —— 这样「拖动不进撤销栈」
	# 不是靠补一个 push_undo 调用，而是结构上不可能漏
	drag_from = Vector2(float(recs[p]["x"]), float(recs[p]["z"]))
	dragging = true
	_draw_highlight()
	_sync_panel()


func _on_left_up() -> void:
	if not dragging or sel < 0:
		dragging = false
		return
	dragging = false
	var now := Vector2(float(recs[sel]["x"]), float(recs[sel]["z"]))
	if now.distance_to(drag_from) < 0.01:
		return
	var rid: String = recs[sel]["id"]
	# 先还原成起点，再走命令：一次拖动合成一条 batch，Ctrl+Z 一下就撤销整次拖动
	recs[sel]["x"] = drag_from.x
	recs[sel]["z"] = drag_from.y
	_push({"op": "batch", "id": rid, "cmds": [
			{"op": "set", "id": rid, "field": "x", "from": drag_from.x, "to": now.x},
			{"op": "set", "id": rid, "field": "z", "from": drag_from.y, "to": now.y}]})


func _on_wheel(dir: float, fast: bool) -> void:
	if sel >= 0 and axis != "":
		var step := NUDGE * (5.0 if fast else 1.0) * dir
		var f: String = {"x": "x", "y": "h", "z": "z"}[axis]
		var cur: float = float(recs[sel][f])
		var nv: float = cur + step
		if f == "h":
			nv = clampf(nv, 3.0, 240.0)
		var rid: String = recs[sel]["id"]
		_push({"op": "set", "id": rid, "field": f, "from": cur, "to": nv})
		return
	if ortho:
		ortho_size = clampf(ortho_size * (0.88 if dir > 0 else 1.14), 40.0, 5600.0)
	else:
		cam_dist = clampf(cam_dist * (0.88 if dir > 0 else 1.14), 12.0, 4000.0)
	_update_camera()


func _set_axis(a: String) -> void:
	axis = a
	for k in ui_axis_btns:
		ui_axis_btns[k].button_pressed = (k == a)


func _delete_selected() -> void:
	if sel < 0:
		return
	var r: Dictionary = recs[sel]
	_push({"op": "del", "id": r["id"], "at": sel, "elem": r.duplicate(true)})
	sel = -1
	_draw_highlight()
	_sync_panel()


func _add_building() -> void:
	var c := cam_target
	var rec := {"id": "bld/user/%d" % (Time.get_ticks_msec() % 1000000),
			"x": c.x, "z": c.z, "w": 20.0, "dep": 20.0, "h": 30.0,
			"tint": Color(0.78, 0.80, 0.84, 1.0)}
	_push({"op": "add", "id": rec["id"], "at": recs.size(),
			"elem": rec})
	sel = by_id.get(rec["id"], -1)
	_draw_highlight()
	_sync_panel()


# ============================================================
#  高亮
# ============================================================

func _draw_highlight() -> void:
	hl_mesh.clear_surfaces()
	if sel < 0 or sel >= recs.size():
		return
	var r: Dictionary = recs[sel]
	var hw: float = float(r["w"]) * 0.5 + 0.3
	var hd: float = float(r["dep"]) * 0.5 + 0.3
	var cx: float = float(r["x"])
	var cz: float = float(r["z"])
	var y1: float = float(r["h"]) + 0.3
	var col := Color(1.0, 0.85, 0.2)
	hl_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	hl_mesh.surface_set_color(col)
	var c := [Vector3(cx - hw, 0, cz - hd), Vector3(cx + hw, 0, cz - hd),
			Vector3(cx + hw, 0, cz + hd), Vector3(cx - hw, 0, cz + hd)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		hl_mesh.surface_add_vertex(a)
		hl_mesh.surface_add_vertex(b)
		hl_mesh.surface_add_vertex(a + Vector3(0, y1, 0))
		hl_mesh.surface_add_vertex(b + Vector3(0, y1, 0))
		hl_mesh.surface_add_vertex(a)
		hl_mesh.surface_add_vertex(a + Vector3(0, y1, 0))
	hl_mesh.surface_end()


# ============================================================
#  UI
# ============================================================

func _label(t: String, size := 15, col := Color(0.85, 0.88, 0.93)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.93)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	return sb


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	# ---- 顶部工具栏 ----
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_box())
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.position = Vector2(12, 10)
	ui_layer.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)
	for spec in [["新建", _on_new], ["打开", _on_open], ["保存", _on_save],
			["加一栋", _add_building], ["试驾", _on_test_drive], ["返回", _on_back]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	for a in ["x", "y", "z"]:
		var ab := Button.new()
		ab.text = a.to_upper()
		ab.toggle_mode = true
		ab.button_pressed = (a == axis)
		ab.pressed.connect(_set_axis.bind(a))
		ui_axis_btns[a] = ab
		bar.add_child(ab)
	bar.add_child(VSeparator.new())
	ui_hide_bld = CheckBox.new()
	ui_hide_bld.text = "隐藏建筑"
	ui_hide_bld.toggled.connect(func(on):
		if map.bld_mmi != null:
			map.bld_mmi.visible = not on
		if map.ant_mmi != null:
			map.ant_mmi.visible = not on)
	bar.add_child(ui_hide_bld)
	ui_jump = OptionButton.new()
	for j in JUMPS:
		ui_jump.add_item(j[0])
	ui_jump.item_selected.connect(func(i):
		cam_target = JUMPS[i][1]
		_update_camera())
	bar.add_child(ui_jump)

	# ---- 右侧属性面板 ----
	ui_panel = PanelContainer.new()
	ui_panel.add_theme_stylebox_override("panel", _panel_box())
	ui_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ui_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui_panel.position = Vector2(-16, 10)
	ui_layer.add_child(ui_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(250, 0)
	box.add_theme_constant_override("separation", 5)
	ui_panel.add_child(box)

	box.add_child(_label("城市名", 14, Color(0.6, 0.66, 0.74)))
	ui_name = LineEdit.new()
	ui_name.text = String(doc.get("name", "我的城市"))
	ui_name.text_changed.connect(func(_t): dirty = true)
	box.add_child(ui_name)

	box.add_child(HSeparator.new())
	box.add_child(_label("选中建筑", 14, Color(0.6, 0.66, 0.74)))
	for f in [["x", "东西 X"], ["z", "南北 Z"], ["w", "宽 W"],
			["dep", "进深 D"], ["h", "高 H"]]:
		var row := HBoxContainer.new()
		row.add_child(_label(f[1], 14))
		var sp := SpinBox.new()
		sp.min_value = -2800.0
		sp.max_value = 2800.0
		sp.step = 0.5
		sp.custom_minimum_size = Vector2(110, 0)
		sp.value_changed.connect(_on_field_changed.bind(f[0]))
		row.add_child(sp)
		ui_fields[f[0]] = sp
		box.add_child(row)
	var trow := HBoxContainer.new()
	trow.add_child(_label("颜色", 14))
	ui_tint = ColorPickerButton.new()
	ui_tint.custom_minimum_size = Vector2(110, 26)
	ui_tint.color_changed.connect(_on_tint_changed)
	trow.add_child(ui_tint)
	box.add_child(trow)
	btn_del = Button.new()
	btn_del.text = "删除这一栋（Delete）"
	btn_del.pressed.connect(_delete_selected)
	box.add_child(btn_del)

	box.add_child(HSeparator.new())
	ui_status = RichTextLabel.new()
	ui_status.bbcode_enabled = true
	ui_status.fit_content = true
	ui_status.custom_minimum_size = Vector2(250, 96)
	box.add_child(ui_status)

	var help := _label("左键选/拖 · 右键转 · 中键平移 · 滚轮缩放"
			+ "\n选中时滚轮按 X/Y/Z 轴微调（Shift ×5）"
			+ "\nTab 俯视/透视 · Delete 删除 · Ctrl+Z 撤销", 13,
			Color(0.55, 0.6, 0.68))
	ui_layer.add_child(help)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.position = Vector2(16, -66)

	# ---- 打开存档的浮层 ----
	open_popup = PopupPanel.new()
	open_list = ItemList.new()
	open_list.custom_minimum_size = Vector2(380, 300)
	open_list.item_activated.connect(_on_open_pick)
	open_popup.add_child(open_list)
	ui_layer.add_child(open_popup)   # 赛道编辑器漏了这一步，「打开」根本弹不出来

	_sync_panel()


func _sync_panel() -> void:
	var on := sel >= 0 and sel < recs.size()
	for f in ui_fields:
		ui_fields[f].editable = on
	ui_tint.disabled = not on
	btn_del.disabled = not on
	if not on:
		return
	var r: Dictionary = recs[sel]
	for f in ui_fields:
		ui_fields[f].set_block_signals(true)
		ui_fields[f].value = float(r[f])
		ui_fields[f].set_block_signals(false)
	ui_tint.set_block_signals(true)
	ui_tint.color = r["tint"]
	ui_tint.set_block_signals(false)


func _on_field_changed(v: float, field: String) -> void:
	if sel < 0:
		return
	var cur: float = float(recs[sel][field])
	if absf(cur - v) < 1e-6:
		return
	_push({"op": "set", "id": recs[sel]["id"], "field": field, "from": cur, "to": v})
	_draw_highlight()


func _on_tint_changed(c: Color) -> void:
	if sel < 0:
		return
	_push({"op": "set", "id": recs[sel]["id"], "field": "tint",
			"from": recs[sel]["tint"], "to": Color(c.r, c.g, c.b, 1.0)})


func _refresh_status() -> void:
	if ui_status == null:
		return
	var lines := []
	lines.append("[color=#9aa2ad]楼 %d 栋 · 改动 %d 步%s[/color]"
			% [recs.size(), undo_stack.size(), "  [color=#e8c05f]未保存[/color]"
			if dirty else ""])
	if sel >= 0 and sel < recs.size():
		lines.append("[color=#6fcf7f]%s[/color]" % recs[sel]["id"])
	if not map.orphans.is_empty():
		lines.append("[color=#e8695f]⚠ %d 条编辑失效（底板变过）[/color]"
				% map.orphans.size())
	ui_status.text = "\n".join(lines)


# ============================================================
#  存档 / 试驾
# ============================================================

## 把当前记录与底板逐字段比对，只写出差集
func _collect_doc() -> Dictionary:
	var base: Array = CityData.base_buildings()
	var bmap := {}
	for b in base:
		bmap[b["id"]] = b
	var out := doc.duplicate(true)
	out["name"] = ui_name.text.strip_edges()
	if String(out.get("id", "")) in ["", CityData.DEFAULT_ID]:
		out["id"] = CityData.new_id(out["name"])
	var edits := []
	var adds := []
	var seen := {}
	for r in recs:
		seen[r["id"]] = true
		if not bmap.has(r["id"]):
			var f := {}
			for k in r:
				if k != "id":
					f[k] = CityData.encode_field(k, r[k])
			adds.append({"id": r["id"], "f": f})
			continue
		var b: Dictionary = bmap[r["id"]]
		var dirty_f := {}
		for k in r:
			if k == "id":
				continue
			if not b.has(k) or not _same(b[k], r[k]):
				dirty_f[k] = CityData.encode_field(k, r[k])
		if not dirty_f.is_empty():
			edits.append({"id": r["id"], "f": dirty_f})
	var dels := []
	for b in base:
		if not seen.has(b["id"]):
			dels.append(b["id"])
	out["edits"] = edits
	out["adds"] = adds
	out["dels"] = dels
	return out


func _same(a, b) -> bool:
	if a is float and b is float:
		return absf(a - b) < 0.0005
	if a is Color and b is Color:
		return absf(a.r - b.r) < 0.0005 and absf(a.g - b.g) < 0.0005 \
				and absf(a.b - b.b) < 0.0005
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	return a == b


func _on_save() -> void:
	doc = _collect_doc()
	if CityData.save_custom_map(doc):
		dirty = false
		_refresh_status()
		print("[city] 已保存 %s（改 %d / 增 %d / 删 %d）"
				% [doc["id"], (doc["edits"] as Array).size(),
				(doc["adds"] as Array).size(), (doc["dels"] as Array).size()])


func _on_new() -> void:
	doc = CityData.default_def()
	doc["id"] = ""
	ui_name.text = "我的城市"
	undo_stack.clear()
	redo_stack.clear()
	sel = -1
	dirty = false
	map.build(CityData.default_def())
	map.disable_occluder_fade()
	_reindex()
	_draw_highlight()
	_sync_panel()
	_refresh_status()


func _on_open() -> void:
	open_list.clear()
	var customs: Array = CityData.list_custom_maps()
	for d in customs:
		open_list.add_item("%s   (改 %d / 增 %d / 删 %d)"
				% [d["name"], (d.get("edits", []) as Array).size(),
				(d.get("adds", []) as Array).size(),
				(d.get("dels", []) as Array).size()])
	open_list.set_meta("defs", customs)
	if customs.is_empty():
		open_list.add_item("（还没有自定义城市）")
	open_popup.popup_centered(Vector2i(420, 340))


func _on_open_pick(idx: int) -> void:
	var defs: Array = open_list.get_meta("defs", [])
	if idx < 0 or idx >= defs.size():
		return
	doc = defs[idx]
	ui_name.text = String(doc.get("name", ""))
	undo_stack.clear()
	redo_stack.clear()
	sel = -1
	dirty = false
	map.build(doc)
	map.disable_occluder_fade()
	_reindex()
	_draw_highlight()
	_sync_panel()
	_refresh_status()
	open_popup.hide()


func _on_test_drive() -> void:
	_on_save()
	if String(doc.get("id", "")) == "":
		return
	CityData.pending_map_id = doc["id"]
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_back() -> void:
	if dirty and not _del_arm:
		# 项目里零 ConfirmationDialog 使用，沿用 game.gd 的按钮二次确认模式
		_del_arm = true
		_refresh_status()
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")
