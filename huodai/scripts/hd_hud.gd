class_name HDHud
extends CanvasLayer
## 烽火地带 —— 对局内 HUD / 开镜覆盖 / 暂停菜单 / 结算页（移植 js/fps/hud.js 大厅组分区）。
## 全 Control + 自定义 _draw，零外部资源：HDData.ui_theme 系统中文字体链 + 字号/颜色 override，
## 军事暗色调。按 1440×810 设计，_apply_ui_scale 按视口高度整体缩放（全屏大屏不缩字）。
## 结构：_raid（对局层，set_raid_visible 开关）→ toast → 暂停菜单 → 结算页。
## 暂停菜单/结算页按键自处理（_input），通过 menu_* / result_* 信号通知 main；
## process_mode=ALWAYS：main 若用 get_tree().paused 暂停，菜单键仍可响应。

signal menu_restart
signal menu_range
signal menu_abort
signal result_restart
signal result_lobby

const COL_TEXT := Color(0.85, 0.87, 0.82)
const COL_ACCENT := Color(1, 0.7, 0.36)
const COL_OK := Color(0.49, 0.89, 0.66)
const COL_LOW := Color(1.0, 0.48, 0.27)
const COL_LOSE := Color(1.0, 0.35, 0.25)
const SEG_N := 10                   # 血条段数
const TOAST_MAX := 3                # toast 队列上限
const TOAST_LIFE := 3.2
const DESIGN_H := 810.0             # UI 设计基准高度（1440×810），缩放 = 视口高 / 此值

var menu_visible: bool = false
var result_visible: bool = false

var _base: Control
var _raid: Control
var _center: CenterLayer
var _scope_ov: ScopeOverlay
var _danger_vg: EdgeVignette
var _danger_panel: Control
var _ammo_label: Label
var _health_num: Label
var _segs: Array = []
var _bag_label: Label
var _bag_pips: HBoxContainer
var _bag_cap := -1
var _pip_nodes: Array = []
var _score_label: Label
var _score_seen := false
var _extract_panel: Control
var _extract_label: Label
var _extract_bar: ProgressBar
var _toast_box: VBoxContainer
var _toasts: Array = []             # [{node, t, dur}]
var _menu: Control
var _result: Control
var _result_title: Label
var _result_rank: Label
var _result_stats: Label
var _ads_on := false                # true = 开镜（准星隐藏 + 覆盖层）
var _pulse_t := 0.0


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if _base == null:
		setup()


## 构建全部界面层（幂等；对局 HUD 初始隐藏）
func setup() -> void:
	if _base != null:
		return
	_base = Control.new()
	_base.set_anchors_preset(Control.PRESET_FULL_RECT)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.theme = HDData.ui_theme()   # 中文字体链设为 default_font，全部 Label/Button 继承
	add_child(_base)

	# ---- 对局层（默认隐藏） ----
	_raid = Control.new()
	_raid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raid.visible = false
	_base.add_child(_raid)

	# 危险区红边渐晕（最底）
	_danger_vg = EdgeVignette.new()
	_danger_vg.visible = false
	_raid.add_child(_danger_vg)

	# 撤离读条（底部中）
	_extract_panel = PanelContainer.new()
	var esb := _sb_flat(Color(0.02, 0.05, 0.03, 0.75), Color(COL_OK.r, COL_OK.g, COL_OK.b, 0.6), 1)
	esb.set_content_margin_all(8)
	_extract_panel.add_theme_stylebox_override("panel", esb)
	_extract_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_extract_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_extract_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_extract_panel.offset_left = -170
	_extract_panel.offset_top = -172
	_extract_panel.offset_right = 170
	_extract_panel.offset_bottom = -122
	_extract_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extract_panel.visible = false
	_raid.add_child(_extract_panel)
	var evb := VBoxContainer.new()
	evb.add_theme_constant_override("separation", 4)
	_extract_panel.add_child(evb)
	_extract_label = _mk_label("撤离中 0%", 13, COL_OK)
	_extract_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evb.add_child(_extract_label)
	_extract_bar = ProgressBar.new()
	_extract_bar.min_value = 0.0
	_extract_bar.max_value = 1.0
	_extract_bar.value = 0.0
	_extract_bar.show_percentage = false
	_extract_bar.custom_minimum_size = Vector2(320, 8)
	_extract_bar.add_theme_stylebox_override("background",
			_sb_flat(Color(0.1, 0.14, 0.11, 0.9), Color(0, 0, 0, 0), 0))
	_extract_bar.add_theme_stylebox_override("fill",
			_sb_flat(Color(COL_OK.r, COL_OK.g, COL_OK.b, 0.9), Color(0, 0, 0, 0), 0))
	evb.add_child(_extract_bar)

	# 右下弹药
	_ammo_label = _mk_label("30 / 150", 34, COL_TEXT)
	_ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo_label.offset_left = -300
	_ammo_label.offset_top = -108
	_ammo_label.offset_right = -26
	_ammo_label.offset_bottom = -56
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_raid.add_child(_ammo_label)

	# 左下背包格
	var bag_box := VBoxContainer.new()
	bag_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bag_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bag_box.offset_left = 24
	bag_box.offset_top = -152
	bag_box.offset_right = 280
	bag_box.offset_bottom = -102
	bag_box.add_theme_constant_override("separation", 4)
	bag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raid.add_child(bag_box)
	_bag_label = _mk_label("背包 0/12", 12, COL_TEXT)
	bag_box.add_child(_bag_label)
	_bag_pips = HBoxContainer.new()
	_bag_pips.add_theme_constant_override("separation", 3)
	_bag_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_box.add_child(_bag_pips)

	# 左下血条（分段色条）+ 数字
	var hh := VBoxContainer.new()
	hh.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hh.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hh.offset_left = 24
	hh.offset_top = -96
	hh.offset_right = 340
	hh.offset_bottom = -24
	hh.add_theme_constant_override("separation", 4)
	hh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raid.add_child(hh)
	_health_num = _mk_label("100", 20, COL_TEXT)
	hh.add_child(_health_num)
	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 3)
	seg_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_child(seg_row)
	_segs.clear()
	for i in SEG_N:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(26, 10)
		seg.color = Color(0.14, 0.18, 0.15, 0.9)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg_row.add_child(seg)
		_segs.append(seg)

	# 右上靶场计分（set_score 后常显）
	_score_label = _mk_label("得分 0 · 最佳 0", 15, COL_TEXT)
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_score_label.offset_left = -340
	_score_label.offset_top = 88
	_score_label.offset_right = -24
	_score_label.offset_bottom = 114
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.visible = false
	_raid.add_child(_score_label)

	# 危险横幅（顶部中，红边渐晕已建）
	_danger_panel = PanelContainer.new()
	var dsb := _sb_flat(Color(0.36, 0.07, 0.03, 0.62), Color(1.0, 0.45, 0.25, 0.8), 1)
	dsb.content_margin_left = 26
	dsb.content_margin_right = 26
	dsb.content_margin_top = 5
	dsb.content_margin_bottom = 5
	_danger_panel.add_theme_stylebox_override("panel", dsb)
	_danger_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_danger_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_danger_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_panel.visible = false
	_raid.add_child(_danger_panel)
	var db := _mk_label("! 高危战区", 15, Color(1.0, 0.6, 0.42))
	_danger_panel.add_child(db)

	# 中心层：准星 / 命中标记 / 交互提示
	_center = CenterLayer.new()
	_raid.add_child(_center)

	# 开镜覆盖层（最上，压过中心层）
	_scope_ov = ScopeOverlay.new()
	_scope_ov.visible = false
	_raid.add_child(_scope_ov)

	# ---- toast 队列（顶中，盖在大厅之上也要可见） ----
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.offset_top = 84
	_toast_box.offset_bottom = 240
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.add_child(_toast_box)

	# ---- Esc 暂停菜单 ----
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	var mdim := ColorRect.new()
	mdim.color = Color(0.02, 0.04, 0.03, 0.78)
	mdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(mdim)
	var mc := CenterContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(mc)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mc.add_child(mv)
	var mt := _mk_label("行动暂停", 26, COL_ACCENT)
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mt)
	var msub := _mk_label("PAUSED · 战术行动中断", 12, _dim(0.55))
	msub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(msub)
	for line in ["1 · 重开行动", "2 · 重开靶场", "3 · 放弃行动（回大厅）"]:
		var row := _mk_label(line, 17, COL_TEXT)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mv.add_child(row)
	var mesc := _mk_label("Esc 恢复战斗", 12, _dim(0.55))
	mesc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mesc)
	_base.add_child(_menu)

	# ---- 结算页 ----
	_result = Control.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.visible = false
	var rdim := ColorRect.new()
	rdim.color = Color(0.02, 0.04, 0.03, 0.85)
	rdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(rdim)
	var rc := CenterContainer.new()
	rc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(rc)
	var rpanel := PanelContainer.new()
	var psb := _sb_flat(Color(0.04, 0.07, 0.05, 0.96), Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.6), 1)
	psb.set_content_margin_all(26)
	psb.content_margin_left = 64
	psb.content_margin_right = 64
	rpanel.add_theme_stylebox_override("panel", psb)
	rc.add_child(rpanel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rpanel.add_child(rv)
	_result_title = _mk_label("撤离成功", 30, COL_OK)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_result_title)
	_result_rank = _mk_label("S", 54, COL_ACCENT)
	_result_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_result_rank)
	_result_stats = _mk_label("", 15, COL_TEXT)
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_result_stats)
	var rhint := _mk_label("R 再来一局 · Enter 回大厅", 13, _dim(0.55))
	rhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rhint)
	_base.add_child(_result)

	# ---- 分辨率自适应：按视口高度整体缩放，窗口尺寸变化实时跟进 ----
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_apply_ui_scale):
		vp.size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()


## 全屏/大屏自适应（问题③）：UI 全按 1440×810 设计，缩放 = 视口高 / DESIGN_H。
## CanvasLayer.scale 缩放后布局空间变为 视口/scale：根 Control 用 offset 把自身
## 补到 视口/scale 尺寸，缩放回屏幕恰好铺满 —— 居中/贴边锚点照常正确。
func _apply_ui_scale() -> void:
	var vp := get_viewport()
	if vp == null or _base == null:
		return
	var vs := vp.get_visible_rect().size
	if vs.y <= 0.0:
		return
	var s := clampf(vs.y / DESIGN_H, 0.5, 4.0)
	scale = Vector2(s, s)
	_base.offset_right = vs.x / s - vs.x
	_base.offset_bottom = vs.y / s - vs.y


# ================= 对局 HUD 状态 =================

func set_raid_visible(on: bool) -> void:
	if _raid == null:
		setup()
	_raid.visible = on
	_scope_ov.visible = on and _ads_on
	_score_label.visible = on and _score_seen


func set_ammo(cur: int, reserve: int) -> void:
	if _ammo_label == null:
		setup()
	_ammo_label.text = "%d / %d" % [cur, reserve]
	_ammo_label.add_theme_color_override("font_color", COL_LOW if cur <= 8 else COL_TEXT)


func set_health(hp: float, max_hp: float) -> void:
	if _health_num == null:
		setup()
	var mx := maxf(max_hp, 1.0)
	var pct := clampf(hp / mx, 0.0, 1.0)
	_health_num.text = str(int(ceil(maxf(hp, 0.0))))
	var col := COL_OK
	if pct <= 0.3:
		col = Color(0.78, 0.29, 0.24)
	elif pct <= 0.6:
		col = COL_ACCENT
	var filled := int(round(pct * float(_segs.size())))
	for i in _segs.size():
		var seg := _segs[i] as ColorRect
		seg.color = col if i < filled else Color(0.14, 0.18, 0.15, 0.9)


func set_backpack(n: int, cap: int) -> void:
	if _bag_pips == null:
		setup()
	var c := maxi(1, cap)
	var nn := maxi(0, n)
	if c != _bag_cap:                # 容量变化才重建格点
		_bag_cap = c
		for p in _bag_pips.get_children():
			_bag_pips.remove_child(p)
			p.queue_free()
		_pip_nodes.clear()
		for i in c:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(10, 10)
			pip.color = Color(0.14, 0.18, 0.15, 0.9)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bag_pips.add_child(pip)
			_pip_nodes.append(pip)
	for i in _pip_nodes.size():
		var pip2 := _pip_nodes[i] as ColorRect
		pip2.color = Color(1.0, 0.7, 0.36, 0.95) if i < nn else Color(0.14, 0.18, 0.15, 0.9)
	_bag_label.text = "背包 %d/%d" % [nn, c]


## 开镜覆盖层：kind 画分划，on 开关；on=true 时准星隐藏（ads>0.5 由 main 判定）
func set_scope(kind: String, zoom: float, on: bool) -> void:
	_ads_on = on
	if _scope_ov == null or _center == null:
		setup()
	_scope_ov.set_scope(kind, zoom)
	_scope_ov.visible = on and _raid.visible
	_center.ads_on = on
	_center.queue_redraw()


## 顶部中短命消息（队列最多叠 3 条）
func toast(text: String, color: Color = Color(1, 1, 1)) -> void:
	if _toast_box == null:
		setup()
	var p := PanelContainer.new()
	var sb := _sb_flat(Color(0.02, 0.05, 0.03, 0.8), Color(color.r, color.g, color.b, 0.65), 1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _mk_label(text, 14, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_box.add_child(p)
	_toasts.append({"node": p, "t": TOAST_LIFE, "dur": TOAST_LIFE})
	while _toasts.size() > TOAST_MAX:
		var old: Dictionary = _toasts.pop_front()
		var oldn := old["node"] as Control
		_toast_box.remove_child(oldn)
		oldn.queue_free()


## 「! 高危战区」红横幅 + 屏幕红边渐晕（警示符用「!」：默认字体链对 ⚠ 类符号不保稳）
func set_danger(on: bool) -> void:
	if _danger_panel == null:
		setup()
	_danger_panel.visible = on
	_danger_vg.visible = on
	_danger_panel.modulate.a = 1.0
	_pulse_t = 0.0


## 撤离读条：t <= 0 隐藏
func set_extract(t: float, need: float) -> void:
	if _extract_panel == null:
		setup()
	if t <= 0.0:
		_extract_panel.visible = false
		return
	_extract_panel.visible = true
	var k := 0.0
	if need > 0.0:
		k = clampf(t / need, 0.0, 1.0)
	_extract_bar.value = k
	_extract_label.text = "撤离中 %d%%" % int(round(k * 100.0))


## 准星旁 X 命中标记（kill 红 head 黄）
func hitmark(head: bool, kill: bool) -> void:
	if _center == null:
		setup()
	_center.hit_kill = kill
	_center.hit_head = head and not kill
	_center.hit_dur = 0.42 if kill else 0.24
	_center.hit_t = _center.hit_dur
	_center.queue_redraw()


## 准星下方交互提示 + 进度圈（progress < 0 只显示文字；text 为空整体隐藏）
func set_prompt(text: String, progress: float) -> void:
	if _center == null:
		setup()
	_center.prompt_text = text
	_center.prompt_prog = progress
	_center.queue_redraw()


## 靶场计分（右上角）
func set_score(score: int, best: int) -> void:
	if _score_label == null:
		setup()
	_score_label.text = "得分 %d · 最佳 %d" % [score, best]
	_score_label.visible = true
	_score_seen = true


## 计分条只属于靶场：行动模式显式关掉（_score_seen 一并复位）
func set_score_visible(on: bool) -> void:
	if _score_label == null:
		setup()
	_score_seen = on
	_score_label.visible = on


# ================= 暂停菜单 =================

func show_menu() -> void:
	if _menu == null:
		setup()
	menu_visible = true
	_menu.visible = true


func hide_menu() -> void:
	menu_visible = false
	if _menu != null:
		_menu.visible = false


# ================= 结算页 =================

## s 含 {kills, value, time_sec, rank}；rank 缺省按 value 分 S/A/B/C
func show_result(win: bool, s: Dictionary) -> void:
	if _result == null:
		setup()
	var kills := maxi(0, int(s.get("kills", 0)))
	var value := float(s.get("value", 0.0))
	var tsec := maxf(0.0, float(s.get("time_sec", 0.0)))
	var rank := str(s.get("rank", ""))
	if rank == "":
		rank = _rank_for(value)
	var mm := int(floor(tsec / 60.0))
	var ss := int(tsec) - mm * 60
	_result_title.text = "撤离成功" if win else "行动失败"
	_result_title.add_theme_color_override("font_color", COL_OK if win else COL_LOSE)
	_result_rank.text = rank
	_result_stats.text = "击杀 %d\n带出价值 ₵%s\n用时 %d:%02d" % [
		kills, _fmt(int(round(value))), mm, ss]
	hide_menu()
	result_visible = true
	_result.visible = true


func hide_result() -> void:
	result_visible = false
	if _result != null:
		_result.visible = false


## 按带出价值评级（show_result 未传 rank 时的兜底阈值）
static func _rank_for(v: float) -> String:
	if v >= 100000.0:
		return "S"
	if v >= 30000.0:
		return "A"
	if v >= 8000.0:
		return "B"
	return "C"


# ================= 按键（菜单/结算自处理） =================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := k.keycode
	if menu_visible:
		match code:
			KEY_1:
				hide_menu()
				menu_restart.emit()
			KEY_2:
				hide_menu()
				menu_range.emit()
			KEY_3:
				hide_menu()
				menu_abort.emit()
			KEY_ESCAPE:
				hide_menu()
			_:
				return
		get_viewport().set_input_as_handled()
	elif result_visible:
		match code:
			KEY_R:
				result_restart.emit()
			KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
				result_lobby.emit()
			_:
				return
		get_viewport().set_input_as_handled()


# ================= 每帧衰减 =================

func _process(dt: float) -> void:
	if _center != null and _center.hit_t > 0.0:
		_center.hit_t = maxf(0.0, _center.hit_t - dt)
		_center.queue_redraw()
	if _danger_panel != null and _danger_panel.visible:
		_pulse_t += dt
		_danger_panel.modulate.a = 0.72 + 0.28 * absf(sin(_pulse_t * 4.0))
	var i := _toasts.size() - 1
	while i >= 0:
		var rec: Dictionary = _toasts[i]
		rec["t"] = float(rec["t"]) - dt
		var left := float(rec["t"])
		var node := rec["node"] as Control
		node.modulate.a = clampf(left / 0.4, 0.0, 1.0)
		if left <= 0.0:
			_toasts.remove_at(i)
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
		i -= 1


# ================= UI 小工具 =================

func _mk_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _sb_flat(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(3)
	return sb


func _dim(a: float) -> Color:
	return Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, a)


## 金额千分位格式化：1234567 -> "1,234,567"
static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# ================= 自定义绘制控件 =================

## 屏幕中心层：四短线十字准星（开镜隐藏）+ X 命中标记 + 交互进度圈/文字
class CenterLayer extends Control:
	const COL_CROSS := Color(0.85, 1.0, 0.92, 0.95)
	const COL_ACCENT := Color(1, 0.7, 0.36)
	const COL_TEXT := Color(0.85, 0.87, 0.82)

	var ads_on := false           # true = 开镜，准星隐藏
	var hit_t := 0.0              # 命中标记剩余寿命
	var hit_dur := 0.24
	var hit_kill := false
	var hit_head := false
	var prompt_text := ""         # 空 = 不显示
	var prompt_prog := -1.0       # <0 = 只显示文字不画圈

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		if not ads_on:
			var gap := 6.0
			var ln := 9.0
			draw_line(c + Vector2(gap, 0), c + Vector2(gap + ln, 0), COL_CROSS, 2.0)
			draw_line(c - Vector2(gap, 0), c - Vector2(gap + ln, 0), COL_CROSS, 2.0)
			draw_line(c + Vector2(0, gap), c + Vector2(0, gap + ln), COL_CROSS, 2.0)
			draw_line(c - Vector2(0, gap), c - Vector2(0, gap + ln), COL_CROSS, 2.0)
			draw_circle(c, 1.6, COL_CROSS)
		if hit_t > 0.0:
			var a := clampf(hit_t / maxf(hit_dur, 0.01), 0.0, 1.0)
			var col := Color(1, 1, 1, a)
			if hit_kill:
				col = Color(1.0, 0.35, 0.25, a)
			elif hit_head:
				col = Color(1.0, 0.82, 0.34, a)
			for i in 4:
				var dir := Vector2.RIGHT.rotated(PI * 0.25 + float(i) * PI * 0.5)
				draw_line(c + dir * 7.0, c + dir * 14.0, col, 2.0)
		if prompt_text != "":
			var f := get_theme_default_font()
			if f != null:
				if prompt_prog >= 0.0:
					draw_arc(c + Vector2(0, 46), 12.0, -PI * 0.5,
							-PI * 0.5 + TAU * clampf(prompt_prog, 0.0, 1.0),
							26, COL_ACCENT, 3.0)
				draw_string(f, c + Vector2(-170, 88), prompt_text,
						HORIZONTAL_ALIGNMENT_CENTER, 340, 14, COL_TEXT)


## 开镜覆盖层：全屏暗角 + 按 kind 画分划
class ScopeOverlay extends Control:
	const COL_RETICLE := Color(0.92, 0.96, 0.86, 0.95)
	const COL_RED := Color(1.0, 0.3, 0.2)
	const COL_GREEN := Color(0.4, 1.0, 0.62)

	var kind := "iron"
	var zoom := 1.0

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_scope(k: String, z: float) -> void:
		kind = k
		zoom = z
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"reddot":
				_vignette(0.55)
				draw_arc(c, 26.0, 0.0, TAU, 40, Color(COL_RED.r, COL_RED.g, COL_RED.b, 0.85), 1.5)
				draw_circle(c, 2.6, COL_RED)
			"holo":
				_vignette(0.55)
				draw_rect(Rect2(c - Vector2(48, 36), Vector2(96, 72)),
						Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 0.4), false, 1.6)
				draw_circle(c, 2.2, COL_GREEN)
				draw_line(c + Vector2(48, 0), c + Vector2(60, 0),
						Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 0.5), 1.2)
			"optic":
				_vignette(0.62)
				_mil_cross(c, COL_RETICLE, 150.0, 34.0)
			"sniper":
				_vignette(0.85)
				_mil_cross(c, COL_RETICLE, 220.0, 46.0)
			"thermal":
				draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.85, 0.45, 0.12))
				_vignette(0.6)
				_mil_cross(c, COL_RETICLE, 120.0, 28.0)
			_:
				_vignette(0.35)   # iron：只暗角轻微
		if zoom > 1.51:
			var f := get_theme_default_font()
			if f != null:
				draw_string(f, c + Vector2(-70, -180), "%.1f×" % zoom,
						HORIZONTAL_ALIGNMENT_CENTER, 140, 15,
						Color(0.92, 0.96, 0.86, 0.9))

	## 密位十字：中心留 gap，四向伸出 reach，带密位短杆
	func _mil_cross(c: Vector2, col: Color, reach: float, gap: float) -> void:
		draw_line(c + Vector2(0, gap), c + Vector2(0, reach), col, 1.6)
		draw_line(c - Vector2(0, gap), c - Vector2(0, reach), col, 1.6)
		draw_line(c + Vector2(gap, 0), c + Vector2(reach, 0), col, 1.6)
		draw_line(c - Vector2(gap, 0), c - Vector2(reach, 0), col, 1.6)
		for i in range(1, 5):
			var d := gap + (reach - gap) * 0.2 * float(i)
			draw_line(c + Vector2(-4, d), c + Vector2(4, d), col, 1.3)
			draw_line(c + Vector2(-4, -d), c + Vector2(4, -d), col, 1.3)
			draw_line(c + Vector2(d, -4), c + Vector2(d, 4), col, 1.3)
			draw_line(c + Vector2(-d, -4), c + Vector2(-d, 4), col, 1.3)

	## 无渐变贴图的暗角近似：由外向内叠 8 圈边带，逐圈加深
	func _vignette(strength: float) -> void:
		var s := size
		var th := 30.0
		for i in 8:
			var a: float = strength * (0.06 + 0.05 * float(i))
			var off := float(i) * th
			var inner := float(i + 1) * th
			draw_rect(Rect2(0, off, s.x, th), Color(0, 0, 0, a))
			draw_rect(Rect2(0, s.y - inner, s.x, th), Color(0, 0, 0, a))
			draw_rect(Rect2(off, 0, th, s.y), Color(0, 0, 0, a))
			draw_rect(Rect2(s.x - inner, 0, th, s.y), Color(0, 0, 0, a))


## 屏幕边缘红渐晕（危险区警示；可见性由宿主控制）
class EdgeVignette extends Control:
	const TINT := Color(0.78, 0.16, 0.08)

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		var th := 44.0
		for i in 4:
			var a := 0.05 + 0.05 * float(i)
			var off := float(i) * th
			var inner := float(i + 1) * th
			draw_rect(Rect2(0, off, s.x, th), Color(TINT.r, TINT.g, TINT.b, a))
			draw_rect(Rect2(0, s.y - inner, s.x, th), Color(TINT.r, TINT.g, TINT.b, a))
			draw_rect(Rect2(off, 0, th, s.y), Color(TINT.r, TINT.g, TINT.b, a))
			draw_rect(Rect2(s.x - inner, 0, th, s.y), Color(TINT.r, TINT.g, TINT.b, a))
