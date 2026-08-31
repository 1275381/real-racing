extends Node3D
## 地图编译器：3D 赛道编辑器
## - 闭合 Catmull-Rom 控制点编辑（左键加点/选中拖动、右键删点、Ctrl+Z 撤销）
## - 选中点 + 选择轴（X/Y/Z）后滚轮调整该轴坐标（每格 1m，Shift=5m）；未选轴时滚轮缩放
## - 编译：校验（点数/自交/周长）→ 保存 user://custom_tracks/<id>.json → 游戏车库可选
## - 试驾：编译保存后直接开赛

const GRID_EXTENT := 400.0
const GRID_STEP := 20.0
const AXIS_LEN := 300.0
const PICK_RADIUS := 24.0        # 控制点屏幕拾取半径 (px)
const POINT_R := 2.4             # 控制点球半径 (m)
const ROAD_HALF_W := TrackData.ROAD_HALF_W
const WHEEL_STEP := 1.0          # 滚轮每格坐标增量 (m)
const MAX_POINTS := 64

var points: Array[Vector3] = []
var handles: Array[Node3D] = []
var selected := -1
var axis := "x"                  # 滚轮调整的轴
var track_id := ""               # 空 = 未保存的新图
var undo_stack: Array = []

var cam: Camera3D
var cam_yaw := 0.65
var cam_pitch := 0.85
var cam_dist := 420.0
var cam_target := Vector3.ZERO

var _orbiting := false
var _panning := false
var _dragging := false           # 左键拖动选中点
var _preview_mesh: ImmediateMesh
var _grid_mesh: ImmediateMesh
var _sel_label: Label3D

var ui_name: LineEdit
var ui_desc: LineEdit
var ui_theme: OptionButton
var ui_status: RichTextLabel
var ui_axis_btns := {}           # "x"/"y"/"z" -> Button
var open_popup: PopupPanel
var open_list: ItemList


func _ready() -> void:
	_build_world()
	_build_ui()
	_load_default_oval()
	_refresh_preview()


# ============================================================
#  世界搭建：网格 / 三轴 / 相机
# ============================================================

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.15, 0.19)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.85
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = false
	add_child(sun)

	_grid_mesh = ImmediateMesh.new()
	_rebuild_grid()
	var gm := MeshInstance3D.new()
	gm.mesh = _grid_mesh
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.vertex_color_use_as_albedo = true
	gm.material_override = gmat
	add_child(gm)

	_preview_mesh = ImmediateMesh.new()
	var pm := MeshInstance3D.new()
	pm.mesh = _preview_mesh
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.material_override = pmat
	add_child(pm)

	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	_update_camera()


func _rebuild_grid() -> void:
	_grid_mesh.clear_surfaces()
	var c_major := Color(0.32, 0.36, 0.42)
	var c_minor := Color(0.22, 0.25, 0.3)
	_grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var v := GRID_EXTENT
	var k := 0
	while k <= v:
		var col := c_major if k % 100 == 0 else c_minor
		_grid_mesh.surface_set_color(col)
		_grid_mesh.surface_add_vertex(Vector3(-v, 0, k))
		_grid_mesh.surface_set_color(col)
		_grid_mesh.surface_add_vertex(Vector3(v, 0, k))
		_grid_mesh.surface_set_color(col)
		_grid_mesh.surface_add_vertex(Vector3(k, 0, -v))
		_grid_mesh.surface_set_color(col)
		_grid_mesh.surface_add_vertex(Vector3(k, 0, v))
		k += GRID_STEP
	_grid_mesh.surface_end()

	# 三色轴线：X 红（东西）/ Z 蓝（南北）/ Y 绿（高度）
	_grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_grid_mesh.surface_set_color(Color(0.95, 0.25, 0.25))
	_grid_mesh.surface_add_vertex(Vector3(-AXIS_LEN, 0.02, 0))
	_grid_mesh.surface_set_color(Color(0.95, 0.25, 0.25))
	_grid_mesh.surface_add_vertex(Vector3(AXIS_LEN, 0.02, 0))
	_grid_mesh.surface_set_color(Color(0.25, 0.55, 0.95))
	_grid_mesh.surface_add_vertex(Vector3(0, 0.02, -AXIS_LEN))
	_grid_mesh.surface_set_color(Color(0.25, 0.55, 0.95))
	_grid_mesh.surface_add_vertex(Vector3(0, 0.02, AXIS_LEN))
	_grid_mesh.surface_set_color(Color(0.25, 0.85, 0.35))
	_grid_mesh.surface_add_vertex(Vector3(0, 0, 0))
	_grid_mesh.surface_set_color(Color(0.25, 0.85, 0.35))
	_grid_mesh.surface_add_vertex(Vector3(0, 50, 0))
	_grid_mesh.surface_end()

	for a in [["X", Vector3(AXIS_LEN + 14, 0, 0), Color(0.95, 0.35, 0.35)],
			["Z", Vector3(0, 0, AXIS_LEN + 14), Color(0.35, 0.65, 1.0)],
			["Y", Vector3(0, 52, 0), Color(0.35, 0.9, 0.45)]]:
		var lbl := Label3D.new()
		lbl.text = a[0]
		lbl.position = a[1]
		lbl.modulate = a[2]
		lbl.font_size = 220
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		add_child(lbl)


func _update_camera() -> void:
	var cp := cam_pitch
	var dir := Vector3(sin(cam_yaw) * cos(cp), sin(cp), cos(cam_yaw) * cos(cp))
	cam.position = cam_target + dir * cam_dist
	cam.look_at(cam_target, Vector3.UP)


# ============================================================
#  UI
# ============================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var toolbar := PanelContainer.new()
	toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	toolbar.add_child(tb)
	layer.add_child(toolbar)
	for spec in [["新建", _on_new], ["打开", _on_open], ["编译保存", _on_compile],
			["试驾", _on_test_drive], ["删除", _on_delete], ["返回车库", _on_back]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(96, 34)
		b.pressed.connect(spec[1])
		tb.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(spacer)

	# 轴选择：滚轮调整选中点的哪个轴
	var axis_box := HBoxContainer.new()
	axis_box.add_theme_constant_override("separation", 4)
	var axis_hint := _label("滚轮调整轴：", 13, Color(0.6, 0.66, 0.72))
	axis_box.add_child(axis_hint)
	for a in ["x", "y", "z"]:
		var ab := Button.new()
		ab.text = a.to_upper()
		ab.custom_minimum_size = Vector2(44, 34)
		ab.toggle_mode = true
		ab.pressed.connect(func(): set_axis(a))
		axis_box.add_child(ab)
		ui_axis_btns[a] = ab
	tb.add_child(axis_box)

	# 右侧属性面板
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position = Vector2(-330, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.88)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(280, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(_label("地图编译器", 22, Color(0.95, 0.95, 0.98)))
	box.add_child(HSeparator.new())
	box.add_child(_label("名称", 13, Color(0.6, 0.66, 0.72)))
	ui_name = LineEdit.new()
	ui_name.text = "我的赛道"
	box.add_child(ui_name)
	box.add_child(_label("简介", 13, Color(0.6, 0.66, 0.72)))
	ui_desc = LineEdit.new()
	ui_desc.text = "自定义赛道"
	box.add_child(ui_desc)
	box.add_child(_label("主题", 13, Color(0.6, 0.66, 0.72)))
	ui_theme = OptionButton.new()
	for t in ["country  乡野", "city  城市", "desert  沙漠"]:
		ui_theme.add_item(t)
	ui_theme.select(0)
	box.add_child(ui_theme)

	box.add_child(HSeparator.new())
	ui_status = RichTextLabel.new()
	ui_status.bbcode_enabled = true
	ui_status.fit_content = true
	ui_status.custom_minimum_size = Vector2(0, 120)
	box.add_child(ui_status)

	var help := _label("左键加点 / 选中点，拖动移动\n右键点删除 · Ctrl+Z 撤销\n选中点 + X/Y/Z 选轴，滚轮调坐标\n（Shift=5m）未选轴滚轮=缩放\n右键拖旋转视角 · 中键平移", 12, Color(0.55, 0.6, 0.66))
	box.add_child(help)

	# 打开弹层
	open_popup = PopupPanel.new()
	open_popup.size = Vector2(320, 300)
	var ov := VBoxContainer.new()
	open_popup.add_child(ov)
	ov.add_child(_label("打开自定义赛道", 16, Color.WHITE))
	open_list = ItemList.new()
	open_list.custom_minimum_size = Vector2(290, 200)
	open_list.item_selected.connect(func(i: int): _on_open_pick(i))
	ov.add_child(open_list)
	set_axis("x")   # UI 就绪后再设默认轴（会刷新状态区）


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func set_axis(a: String) -> void:
	axis = a
	for k in ui_axis_btns:
		(ui_axis_btns[k] as Button).button_pressed = k == a
	_refresh_status()


func _refresh_status() -> void:
	if points.is_empty():
		ui_status.text = "[color=#9aa2ad]空场景：左键地面添加控制点[/color]"
		return
	var res: Dictionary = TrackData.validate_track(points)
	var lines := "控制点 %d · 周长 %dm\n" % [points.size(), int(res["length"])]
	if res["ok"]:
		lines += "[color=#6fcf7f]校验通过，可编译保存[/color]"
	else:
		for e in res["errors"]:
			lines += "[color=#e8695f]✗ %s[/color]\n" % e
	if selected >= 0:
		var p: Vector3 = points[selected]
		lines += "\n选中点 %d：[color=#7fc4ff]X %.1f · Y %.1f · Z %.1f[/color]\n滚轮沿 [%s] 轴调整" % [
				selected, p.x, p.y, p.z, axis.to_upper()]
	ui_status.text = lines


# ============================================================
#  控制点操作
# ============================================================

func _push_undo() -> void:
	undo_stack.append(points.duplicate())
	if undo_stack.size() > 60:
		undo_stack.pop_front()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	points = undo_stack.pop_back()
	selected = mini(selected, points.size() - 1)
	_rebuild_handles()
	_refresh_preview()
	_refresh_status()


func _add_point(at: Vector3) -> void:
	_push_undo()
	var insert_at := points.size()
	if selected >= 0:
		insert_at = selected + 1   # 追加在选中点之后，便于顺时针续画
	points.insert(insert_at, at)
	selected = insert_at
	_rebuild_handles()
	_refresh_preview()
	_refresh_status()


func _delete_point(i: int) -> void:
	if i < 0 or i >= points.size() or points.size() <= 4:
		return
	_push_undo()
	points.remove_at(i)
	selected = -1
	_rebuild_handles()
	_refresh_preview()
	_refresh_status()


func _move_selected(to: Vector3) -> void:
	if selected < 0:
		return
	points[selected] = to
	handles[selected].position = to
	_refresh_preview()
	_refresh_status()


func _nudge_selected(axis_char: String, dir: float) -> void:
	if selected < 0:
		return
	var p := points[selected]
	var step := WHEEL_STEP * (5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	match axis_char:
		"x": p.x = clampf(p.x + dir * step, -GRID_EXTENT, GRID_EXTENT)
		"y": p.y = clampf(p.y + dir * step, 0.0, 50.0)
		"z": p.z = clampf(p.z + dir * step, -GRID_EXTENT, GRID_EXTENT)
	points[selected] = p
	handles[selected].position = p
	_update_sel_label()
	_refresh_preview()
	_refresh_status()


func _rebuild_handles() -> void:
	for h in handles:
		h.queue_free()
	handles.clear()
	if selected >= points.size():
		selected = -1
	_sel_label = null
	for i in points.size():
		_make_handle(i)
	_update_sel_label()


func _make_handle(i: int) -> void:
	var h := Node3D.new()
	h.position = points[i]
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = POINT_R
	s.height = POINT_R * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.55, 0.25) if i == selected else Color(0.92, 0.92, 0.95)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.35
	s.material = mat
	m.mesh = s
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(m)
	add_child(h)
	handles.append(h)
	if i == selected:
		_update_sel_label()


func _update_sel_label() -> void:
	if _sel_label != null:
		_sel_label.queue_free()
		_sel_label = null
	if selected < 0:
		return
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.modulate = Color(0.5, 0.77, 1.0)
	l.outline_size = 8
	l.position = points[selected] + Vector3(0, 6, 0)
	l.text = "X %.1f  Y %.1f  Z %.1f" % [points[selected].x, points[selected].y, points[selected].z]
	add_child(l)
	_sel_label = l


# ============================================================
#  预览绘制
# ============================================================

func _refresh_preview() -> void:
	_preview_mesh.clear_surfaces()
	if points.size() < 3:
		return
	var dense := TrackData.sample_closed_spline(points, 10)

	# 路面半透明带（按路宽）
	var w := ROAD_HALF_W
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in dense.size():
		var j := (i + 1) % dense.size()
		var a: Vector3 = dense[i]
		var b: Vector3 = dense[j]
		var ta := (dense[(i + 1) % dense.size()] - dense[(i - 1 + dense.size()) % dense.size()])
		var tb := (dense[(j + 1) % dense.size()] - dense[(j - 1 + dense.size()) % dense.size()])
		var la := Vector3(-ta.z, 0, ta.x).normalized() * w
		var lb := Vector3(-tb.z, 0, tb.x).normalized() * w
		var c1 := Color(0.45, 0.55, 0.68, 0.30)
		_preview_mesh.surface_set_color(c1)
		_preview_mesh.surface_add_vertex(a + la)
		_preview_mesh.surface_set_color(c1)
		_preview_mesh.surface_add_vertex(b + lb)
		_preview_mesh.surface_set_color(c1)
		_preview_mesh.surface_add_vertex(a - la)
		_preview_mesh.surface_set_color(c1)
		_preview_mesh.surface_add_vertex(b + lb)
		_preview_mesh.surface_set_color(c1)
		_preview_mesh.surface_add_vertex(a - la)
		_preview_mesh.surface_set_color(c1)
		_preview_mesh.surface_add_vertex(b - lb)
	_preview_mesh.surface_end()

	# 中心线
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in dense.size() + 1:
		_preview_mesh.surface_set_color(Color(0.98, 0.85, 0.35, 0.95))
		_preview_mesh.surface_add_vertex(dense[i % dense.size()] + Vector3(0, 0.15, 0))
	_preview_mesh.surface_end()

	# 方向箭头
	var step := maxi(3, dense.size() / maxi(points.size() * 2, 8))
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(0, dense.size(), step):
		var a: Vector3 = dense[i]
		var tv: Vector3 = (dense[(i + 1) % dense.size()] - dense[(i - 1 + dense.size()) % dense.size()]).normalized()
		var lat := Vector3(-tv.z, 0, tv.x)
		var tip := a + tv * 4.0 + Vector3(0, 0.2, 0)
		_preview_mesh.surface_set_color(Color(0.98, 0.85, 0.35))
		_preview_mesh.surface_add_vertex(a - tv * 2.0 + lat * 2.4 + Vector3(0, 0.2, 0))
		_preview_mesh.surface_set_color(Color(0.98, 0.85, 0.35))
		_preview_mesh.surface_add_vertex(tip)
		_preview_mesh.surface_set_color(Color(0.98, 0.85, 0.35))
		_preview_mesh.surface_add_vertex(a - tv * 2.0 - lat * 2.4 + Vector3(0, 0.2, 0))
		_preview_mesh.surface_set_color(Color(0.98, 0.85, 0.35))
		_preview_mesh.surface_add_vertex(tip)
	_preview_mesh.surface_end()


# ============================================================
#  输入
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_X:
				set_axis("x")
			KEY_Y:
				set_axis("y")
			KEY_Z:
				if event.ctrl_pressed:
					_undo()
				else:
					set_axis("z")
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = true
			MOUSE_BUTTON_MIDDLE:
				_panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_on_wheel(1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_on_wheel(-1.0)
			MOUSE_BUTTON_LEFT:
				_on_left_click(event)
	elif event is InputEventMouseButton and not event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = false
			MOUSE_BUTTON_MIDDLE:
				_panning = false
			MOUSE_BUTTON_LEFT:
				if _dragging:
					_dragging = false
	elif event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		if _orbiting:
			cam_yaw -= rel.x * 0.006
			cam_pitch = clampf(cam_pitch + rel.y * 0.005, 0.12, 1.45)
			_update_camera()
		elif _panning:
			var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
			var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
			cam_target += (-right * rel.x + fwd * rel.y) * cam_dist * 0.0011
			_update_camera()
		elif _dragging and selected >= 0:
			var hit := _ground_hit(event.position, points[selected].y)
			if hit != Vector3.INF:
				_move_selected(Vector3(hit.x, points[selected].y, hit.z))


func _on_left_click(event: InputEventMouseButton) -> void:
	var pick := _pick_handle(event.position)
	if pick >= 0:
		selected = pick
		_rebuild_handles()
		_refresh_status()
		_dragging = true
		return
	# 点击地面加点（y 取当前轴为 y 时的高度 0）
	var hit := _ground_hit(event.position, 0.0)
	if hit != Vector3.INF:
		_add_point(hit)


## 屏幕空间拾取控制点
func _pick_handle(mouse: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for i in handles.size():
		var wp: Vector3 = handles[i].position + Vector3(0, POINT_R, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	return best


## 射线与水平面 y=plane_y 的交点
func _ground_hit(mouse: Vector2, plane_y: float) -> Vector3:
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if absf(dir.y) < 1e-5:
		return Vector3.INF
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	var hit := origin + dir * t
	return Vector3(clampf(hit.x, -GRID_EXTENT, GRID_EXTENT), plane_y,
			clampf(hit.z, -GRID_EXTENT, GRID_EXTENT))


func _on_wheel(dir: float) -> void:
	if selected >= 0:
		_nudge_selected(axis, dir)
	else:
		cam_dist = clampf(cam_dist * (1.0 - dir * 0.1), 12.0, 900.0)
		_update_camera()


# ============================================================
#  工具栏动作
# ============================================================

func _on_new() -> void:
	_load_default_oval()


func _load_default_oval() -> void:
	points.clear()
	selected = -1
	undo_stack.clear()
	for k in 10:
		var a := TAU * float(k) / 10.0
		points.append(Vector3(cos(a) * 160.0, 0.0, sin(a) * 110.0))
	track_id = ""
	ui_name.text = "我的赛道"
	ui_desc.text = "自定义赛道"
	ui_theme.select(0)
	_rebuild_handles()
	_refresh_preview()
	_refresh_status()


func _on_open() -> void:
	open_list.clear()
	var customs: Array = TrackData.list_custom_tracks()
	for d in customs:
		open_list.add_item("%s  (%dm)" % [d["name"], 0])
	open_list.set_meta("defs", customs)
	if customs.is_empty():
		open_list.add_item("（还没有自定义赛道）")
		open_list.set_item_disabled(open_list.item_count - 1, true)
	open_popup.popup_centered()


func _on_open_pick(i: int) -> void:
	var defs: Array = open_list.get_meta("defs", [])
	if i >= defs.size():
		return
	var def: Dictionary = defs[i]
	points.clear()
	for p in def["points"]:
		points.append(p)
	track_id = def["id"]
	ui_name.text = def["name"]
	ui_desc.text = def["desc"]
	ui_theme.select(maxi(0, ["country", "city", "desert"].find(def["theme"])))
	selected = -1
	undo_stack.clear()
	_rebuild_handles()
	_refresh_preview()
	_refresh_status()
	open_popup.hide()


func _cur_def() -> Dictionary:
	return {
		"id": track_id,
		"name": ui_name.text.strip_edges(),
		"desc": ui_desc.text.strip_edges(),
		"theme": ["country", "city", "desert"][ui_theme.selected],
		"points": points,
	}


func _on_compile() -> void:
	var res: Dictionary = TrackData.validate_track(points)
	if not res["ok"]:
		var errs := ""
		for e in res["errors"]:
			errs += e + "；"
		ui_status.text = "[color=#e8695f]✗ 编译失败：%s[/color]\n控制点 %d · 周长 %dm" % [
				errs, points.size(), int(res["length"])]
		return
	var def := _cur_def()
	if def["id"] == "":
		def["id"] = "custom_%s_%04d" % [def["name"].md5_text().substr(0, 6),
				randi() % 10000]
		track_id = def["id"]
	if TrackData.save_custom_track(def):
		ui_status.text = "[color=#6fcf7f]✓ 编译成功：已保存 %s.json\n周长 %dm · %d 个控制点\n车库赛道列表即可选择，或点「试驾」[/color]" % [
				track_id, int(res["length"]), points.size()]
	else:
		ui_status.text = "[color=#e8695f]✗ 编译失败：文件写入失败[/color]"


func _on_test_drive() -> void:
	var res: Dictionary = TrackData.validate_track(points)
	if not res["ok"]:
		ui_status.text = "[color=#e8695f]校验未通过，无法试驾（先编译保存）[/color]"
		return
	_on_compile()
	if track_id == "":
		return
	TrackData.pending_track_id = track_id
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_delete() -> void:
	if track_id == "":
		ui_status.text = "[color=#e8695f]当前不是已保存的自定义赛道[/color]"
		return
	TrackData.delete_custom_track(track_id)
	track_id = ""
	ui_status.text = "[color=#6fcf7f]已删除。已载入编辑器的点位仍在，可改后重新编译。[/color]"


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
