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
signal inv_close
signal inv_drop(from_secure: bool, idx: int)
signal inv_move(from_secure: bool, idx: int)
signal inv_use(from_secure: bool, idx: int)

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
var inv_visible: bool = false

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
var _uses_label: Label
var _armor_row: HBoxContainer
var _armor_segs: Array = []
var _timer_label: Label
var _bag_cap := -1
var _pip_nodes: Array = []
var _score_label: Label
var _score_seen := false
var _extract_panel: Control
var _extract_label: Label
var _extract_bar: ProgressBar
var _toast_box: VBoxContainer
var _toasts: Array = []             # [{node, t, dur}]
var _compass: CompassBar
var _hit_ind: HitIndicator
var _feed_box: VBoxContainer
var _feeds: Array = []              # [{node, t}] 右侧信息流（击杀/拾取/背包）
const FEED_MAX := 5
const FEED_LIFE := 5.0
var _menu: Control
var _menu_title: Label
var _menu_sub: Label
var _menu_rows: Array = []               # 三行选项 Label（靶场模式末行隐藏）
var _menu_esc: Label
var _menu_kind := "mission"              # 菜单模式：mission 实战 / range 靶场（main 在模式流转处同步）
var _result: Control
var _result_title: Label
var _result_rank: Label
var _result_stats: Label
var _result_lines: VBoxContainer
var _inv: Control
var _inv_title: Label
var _inv_grid: GridContainer
var _inv_sec_label: Label
var _inv_sec_row: HBoxContainer
var _inv_detail: Label
var _inv_move_btn: Button
var _inv_bag: Array = []
var _inv_sec: Array = []
var _inv_cap := 2
var _inv_sel := 0
var _inv_sel_secure := false
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
	# 物资快捷键（第三阶段）：3 医疗包 · 4 止痛药 · 5 护甲板 · 6 弹药盒
	_uses_label = _mk_label("", 12, COL_TEXT)
	bag_box.add_child(_uses_label)
	bag_box.offset_top = -176

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
	# 护甲条（蓝，有护甲才显示）
	_armor_row = HBoxContainer.new()
	_armor_row.add_theme_constant_override("separation", 3)
	_armor_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_armor_row.visible = false
	hh.add_child(_armor_row)
	_armor_segs.clear()
	for i in SEG_N:
		var aseg := ColorRect.new()
		aseg.custom_minimum_size = Vector2(26, 5)
		aseg.color = Color(0.14, 0.18, 0.15, 0.9)
		aseg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_armor_row.add_child(aseg)
		_armor_segs.append(aseg)
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

	# 右上局时（第三阶段：25 分钟撤离窗口）
	_timer_label = _mk_label("", 18, COL_TEXT)
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timer_label.offset_left = -300
	_timer_label.offset_right = -24
	_timer_label.offset_top = 14
	_timer_label.offset_bottom = 40
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_raid.add_child(_timer_label)

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
	_danger_panel.offset_top = 70     # 让出顶部指南针（含撤离点距离字）
	_danger_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_danger_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_panel.visible = false
	_raid.add_child(_danger_panel)
	var db := _mk_label("! 高危战区", 15, Color(1.0, 0.6, 0.42))
	_danger_panel.add_child(db)

	# 中心层：准星 / 命中标记 / 交互提示
	_center = CenterLayer.new()
	_raid.add_child(_center)

	# 2026-10 改进方案第 4 节：顶部指南针（方位刻度 + 撤离点方位与距离）、
	# 受击方向弧、右侧信息流（击杀 / 拾取 / 背包变化）
	_compass = CompassBar.new()
	_raid.add_child(_compass)
	_hit_ind = HitIndicator.new()
	_raid.add_child(_hit_ind)
	_feed_box = VBoxContainer.new()
	_feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed_box.offset_left = -420
	_feed_box.offset_right = -24
	_feed_box.offset_top = 128
	_feed_box.offset_bottom = 330
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.add_theme_constant_override("separation", 3)
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raid.add_child(_feed_box)

	# 开镜覆盖层（最上，压过中心层）
	_scope_ov = ScopeOverlay.new()
	_scope_ov.visible = false
	_raid.add_child(_scope_ov)

	# ---- toast 队列（顶中，盖在大厅之上也要可见） ----
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.offset_top = 104       # 指南针 6–64 + 高危横幅 70–96 之下
	_toast_box.offset_bottom = 260
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.add_child(_toast_box)

	# ---- Esc 暂停菜单（文案按 _menu_kind 分化，见 set_menu_mode） ----
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
	_menu_title = _mk_label("行动暂停", 26, COL_ACCENT)
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_menu_title)
	_menu_sub = _mk_label("PAUSED · 战术行动中断", 12, _dim(0.55))
	_menu_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_menu_sub)
	_menu_rows.clear()
	for i in 3:
		var row := _mk_label("", 17, COL_TEXT)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mv.add_child(row)
		_menu_rows.append(row)
	_menu_esc = _mk_label("Esc 恢复战斗 · 游戏内 Q/E 左右探头", 12, _dim(0.55))
	_menu_esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_menu_esc)
	_base.add_child(_menu)
	_apply_menu_texts()

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
	_result_lines = VBoxContainer.new()
	_result_lines.add_theme_constant_override("separation", 4)
	rv.add_child(_result_lines)
	var rhint := _mk_label("R 再来一局 · Enter 回大厅", 13, _dim(0.55))
	rhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rhint)
	_base.add_child(_result)

	_build_inventory()

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
	# 靶场模式备弹显示 ∞：练习弹是固定大额虚拟弹药、与库存无关——
	# 显示真实数字（如 9999）反而像库存余量，跟「免费」语义打架
	if _menu_kind == "range":
		_ammo_label.text = "%d / ∞" % cur
	else:
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


func set_backpack(n: int, cap: int, sn: int = -1, scap: int = 0) -> void:
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
	if scap > 0:
		_bag_label.text += " · 安全箱 %d/%d · Tab 整理" % [maxi(0, sn), scap]


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


## 局时剩余（秒）：剩 5 分钟转橙、1 分钟转红；负数/靶场隐藏
func set_raid_timer(left: float) -> void:
	if _timer_label == null:
		setup()
	if left < 0.0 or _menu_kind == "range":
		_timer_label.text = ""
		return
	var t := int(ceil(left))
	_timer_label.text = "撤离窗口 %d:%02d" % [t / 60, t % 60]
	var col := COL_TEXT
	if left <= 60.0:
		col = COL_LOSE
	elif left <= 300.0:
		col = COL_ACCENT
	_timer_label.add_theme_color_override("font_color", col)


## 护甲条（0 隐藏）
func set_armor(a: float) -> void:
	if _armor_row == null:
		setup()
	_armor_row.visible = a > 0.5
	var filled := int(round(clampf(a / HDData.ARMOR_MAX, 0.0, 1.0) * float(_armor_segs.size())))
	for i in _armor_segs.size():
		(_armor_segs[i] as ColorRect).color = Color(0.35, 0.65, 1.0) if i < filled else Color(0.14, 0.18, 0.15, 0.9)


## 物资件数快捷栏
func set_uses(counts: Dictionary) -> void:
	if _uses_label == null:
		setup()
	var parts: Array = []
	for i in HDData.USE_KEYS.size():
		var k: String = HDData.USE_KEYS[i]
		parts.append("%d %s×%d" % [i + 3, str(HDData.CONSUMABLES[k]["name"]), int(counts.get(k, 0))])
	_uses_label.text = " · ".join(PackedStringArray(parts))


## 指南针：heading 玩家朝向方位角（度，北 0 顺时针）；markers [{bearing, label, color}]
func set_compass(heading: float, markers: Array) -> void:
	if _compass == null:
		setup()
	_compass.heading = heading
	_compass.markers = markers
	_compass.queue_redraw()


## 受击方向：rel 为来袭方向相对视线的角度（弧度，0 = 正前、+ = 右侧）
func hit_from(rel: float) -> void:
	if _hit_ind == null:
		setup()
	_hit_ind.hits.append({"a": rel, "t": HitIndicator.LIFE})
	while _hit_ind.hits.size() > 6:
		_hit_ind.hits.pop_front()
	_hit_ind.queue_redraw()


## 右侧信息流：击杀/拾取/背包类消息（最多 5 条，5 s 淡出），与顶部 toast 分流
func feed(text: String, color: Color = Color(1, 1, 1)) -> void:
	if _feed_box == null:
		setup()
	var p := PanelContainer.new()
	var sb := _sb_flat(Color(0.02, 0.05, 0.03, 0.62), Color(color.r, color.g, color.b, 0.0), 0)
	sb.border_width_right = 3
	sb.border_color = Color(color.r, color.g, color.b, 0.85)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var l := _mk_label(text, 13, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(l)
	_feed_box.add_child(p)
	_feeds.append({"node": p, "t": FEED_LIFE})
	while _feeds.size() > FEED_MAX:
		var old: Dictionary = _feeds.pop_front()
		var on := old["node"] as Control
		_feed_box.remove_child(on)
		on.queue_free()


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

## 模式感知（main 在 _start_mission/_enter_range/_back_to_lobby 同步）：
## mission=「行动暂停」三选项照旧；range=「靶场暂停」两选项——靶场里不出现
## 「行动/战斗/放弃」字样（用户反馈：靶场哪来的「放弃战斗」），2=离开靶场回大厅
func set_menu_mode(kind: String) -> void:
	_menu_kind = "range" if kind == "range" else "mission"
	_apply_menu_texts()

## 按 _menu_kind 刷菜单文案（setup 建完标签与 set_menu_mode 都走这里；
## 靶场两行：第三行隐藏而非重建——标签常驻只换字）
func _apply_menu_texts() -> void:
	if _menu_title == null:
		return
	var rows: Array = []
	if _menu_kind == "range":
		_menu_title.text = "靶场暂停"
		_menu_sub.text = "PAUSED · 靶场练习中断"
		rows = ["1 · 重开靶场", "2 · 离开靶场（回大厅）"]
		_menu_esc.text = "Esc 恢复练习 · 游戏内 Q/E 左右探头"
	else:
		_menu_title.text = "行动暂停"
		_menu_sub.text = "PAUSED · 离开行动将丢失随身装备与背包（安全箱保留）"
		rows = ["1 · 重开行动（视同阵亡）", "2 · 重开靶场（视同阵亡）", "3 · 放弃行动（视同阵亡 · 回大厅）"]
		_menu_esc.text = "Esc 恢复战斗 · 游戏内 Q/E 左右探头"
	for i in _menu_rows.size():
		var row := _menu_rows[i] as Label
		row.text = str(rows[i]) if i < rows.size() else ""
		row.visible = i < rows.size()

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
	_result_title.text = str(s.get("title", "撤离成功" if win else "行动失败"))
	_result_title.add_theme_color_override("font_color", COL_OK if win else COL_LOSE)
	_result_rank.text = rank
	if win:
		_result_stats.text = "击杀 %d\n带出价值 ₵%s\n用时 %d:%02d" % [
			kills, _fmt(int(round(value))), mm, ss]
	else:
		_result_stats.text = "击杀 %d\n用时 %d:%02d" % [kills, mm, ss]
	# 附加明细行（阵亡损失 / 安全箱保住等）：[[文字, 颜色], ...]
	for ch in _result_lines.get_children():
		_result_lines.remove_child(ch)
		ch.queue_free()
	for ln in s.get("lines", []):
		var row := _mk_label(str(ln[0]), 14, ln[1] if ln.size() > 1 else COL_TEXT)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_result_lines.add_child(row)
	hide_menu()
	result_visible = true
	_result.visible = true


func hide_result() -> void:
	result_visible = false
	if _result != null:
		_result.visible = false


## 按带出价值评级（show_result 未传 rank 时的兜底阈值；经济重定价后 ÷10）
static func _rank_for(v: float) -> String:
	if v >= 10000.0:
		return "S"
	if v >= 3000.0:
		return "A"
	if v >= 800.0:
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
	if inv_visible:
		match code:
			KEY_TAB, KEY_ESCAPE:
				inv_close.emit()
			KEY_X:
				_inv_act_drop()
			KEY_Z:
				_inv_act_move()
			KEY_U:
				_inv_act_use()
			KEY_LEFT:
				_inv_step(-1, 0)
			KEY_RIGHT:
				_inv_step(1, 0)
			KEY_UP:
				_inv_step(0, -1)
			KEY_DOWN:
				_inv_step(0, 1)
			_:
				return
		get_viewport().set_input_as_handled()
	elif menu_visible:
		match code:
			KEY_1:
				hide_menu()
				menu_restart.emit()
			KEY_2:
				hide_menu()
				# 模式分化：靶场菜单 2=离开靶场（回大厅）；实战 2=重开靶场
				if _menu_kind == "range":
					menu_abort.emit()
				else:
					menu_range.emit()
			KEY_3:
				# 靶场菜单只有两项：3 不消费不动作（main._route_key 兜底同口径）
				if _menu_kind == "range":
					return
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


# ================= Tab 背包 =================

## 背包面板：12 格背包（4×3）+ 安全箱行 + 选中详情 + 丢弃/移入安全箱按钮。
## 鼠标点格选中、按钮执行；键盘 ←→↑↓ 选 · X 丢弃 · Z 移入/取出安全箱 · Tab/Esc 关
func _build_inventory() -> void:
	_inv = Control.new()
	_inv.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inv.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.03, 0.55)   # 半透：世界仍在跑，看得见周围
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inv.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv.add_child(cc)
	var panel := PanelContainer.new()
	var psb := _sb_flat(Color(0.04, 0.07, 0.05, 0.94), Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.55), 1)
	psb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", psb)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_inv_title = _mk_label("背包", 18, COL_ACCENT)
	v.add_child(_inv_title)
	v.add_child(_mk_label("阵亡丢失背包与随身装备 · 安全箱里的物品阵亡保留 · 整理时敌人不会停手", 12, _dim(0.55)))
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 4
	_inv_grid.add_theme_constant_override("h_separation", 6)
	_inv_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(_inv_grid)
	_inv_sec_label = _mk_label("安全箱", 14, COL_OK)
	v.add_child(_inv_sec_label)
	_inv_sec_row = HBoxContainer.new()
	_inv_sec_row.add_theme_constant_override("separation", 6)
	v.add_child(_inv_sec_row)
	_inv_detail = _mk_label("", 13, COL_TEXT)
	v.add_child(_inv_detail)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)
	var bdrop := _inv_btn("X · 丢到地上")
	bdrop.pressed.connect(_inv_act_drop)
	btns.add_child(bdrop)
	_inv_move_btn = _inv_btn("Z · 放入安全箱")
	_inv_move_btn.pressed.connect(_inv_act_move)
	btns.add_child(_inv_move_btn)
	var buse := _inv_btn("U · 使用")
	buse.pressed.connect(_inv_act_use)
	btns.add_child(buse)
	var bclose := _inv_btn("Tab · 关闭")
	bclose.pressed.connect(func(): inv_close.emit())
	btns.add_child(bclose)
	_base.add_child(_inv)


func _inv_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", COL_TEXT)
	var sb := _sb_flat(Color(0.08, 0.12, 0.09, 0.95), Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.6), 1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	return b


func show_inventory(bag: Array, sec: Array, cap: int) -> void:
	if _inv == null:
		setup()
	inv_visible = true
	_inv.visible = true
	_inv_sel = 0
	_inv_sel_secure = false
	refresh_inventory(bag, sec, cap)


func hide_inventory() -> void:
	inv_visible = false
	if _inv != null:
		_inv.visible = false


func refresh_inventory(bag: Array, sec: Array, cap: int) -> void:
	_inv_bag = bag
	_inv_sec = sec
	_inv_cap = cap
	var lst: Array = _inv_sec if _inv_sel_secure else _inv_bag
	if lst.is_empty():
		# 当前一侧空了：落到另一侧
		_inv_sel_secure = not _inv_sel_secure and not _inv_sec.is_empty()
		lst = _inv_sec if _inv_sel_secure else _inv_bag
	_inv_sel = clampi(_inv_sel, 0, maxi(0, lst.size() - 1))
	var bag_v := 0
	for it in bag:
		bag_v += int(float((it as Dictionary).get("value", 0)))
	var sec_v := 0
	for it in sec:
		sec_v += int(float((it as Dictionary).get("value", 0)))
	_inv_title.text = "背包 %d/%d · ₵%s" % [bag.size(), HDData.BACKPACK_MAX, _fmt(bag_v)]
	_inv_sec_label.text = "安全箱 %d/%d · ₵%s（阵亡保留）" % [sec.size(), cap, _fmt(sec_v)]
	for ch in _inv_grid.get_children():
		_inv_grid.remove_child(ch)
		ch.queue_free()
	for i in HDData.BACKPACK_MAX:
		var it: Dictionary = bag[i] if i < bag.size() else {}
		_inv_grid.add_child(_inv_cell(it, false, i))
	for ch in _inv_sec_row.get_children():
		_inv_sec_row.remove_child(ch)
		ch.queue_free()
	for i in cap:
		var it2: Dictionary = sec[i] if i < sec.size() else {}
		_inv_sec_row.add_child(_inv_cell(it2, true, i))
	var cur: Dictionary = {}
	if _inv_sel < lst.size():
		cur = lst[_inv_sel]
	if cur.is_empty():
		_inv_detail.text = "背包空空 —— 搜箱子去"
	else:
		var rid := clampi(int(cur.get("rarity", 0)), 0, 6)
		_inv_detail.text = "%s · %s · ₵%s" % [String(cur.get("name", "")),
				String(HDData.RARITY[rid]["name"]), _fmt(int(float(cur.get("value", 0))))]
		_inv_detail.add_theme_color_override("font_color", HDData.RARITY[rid]["color"])
	_inv_move_btn.text = "Z · 取回背包" if _inv_sel_secure else "Z · 放入安全箱"


func _inv_cell(it: Dictionary, secure: bool, idx: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(150, 50)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	var sel := secure == _inv_sel_secure and idx == _inv_sel and not it.is_empty()
	var col := _dim(0.18)
	if not it.is_empty():
		col = HDData.RARITY[clampi(int(it.get("rarity", 0)), 0, 6)]["color"]
	var sb := _sb_flat(Color(0.05 + col.r * 0.08, 0.07 + col.g * 0.08, 0.06 + col.b * 0.08, 0.9),
			COL_ACCENT if sel else Color(col.r, col.g, col.b, 0.7), 3 if sel else 1)
	sb.set_content_margin_all(5)
	cell.add_theme_stylebox_override("panel", sb)
	var hb := VBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 0)
	cell.add_child(hb)
	if it.is_empty():
		hb.add_child(_mk_label("（空）" if not secure else "（空 · 保险格）", 11, _dim(0.3)))
	else:
		var nm := _mk_label("%s %s" % [HDData.norm_icon(String(it.get("icon", ""))), String(it.get("name", ""))], 12, col)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(138, 0)
		hb.add_child(nm)
		hb.add_child(_mk_label("₵" + _fmt(int(float(it.get("value", 0)))), 11, COL_OK))
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_inv_sel_secure = secure
				_inv_sel = idx
				refresh_inventory(_inv_bag, _inv_sec, _inv_cap))
	return cell


func _inv_act_drop() -> void:
	var lst: Array = _inv_sec if _inv_sel_secure else _inv_bag
	if _inv_sel < lst.size():
		inv_drop.emit(_inv_sel_secure, _inv_sel)


func _inv_act_use() -> void:
	var lst: Array = _inv_sec if _inv_sel_secure else _inv_bag
	if _inv_sel < lst.size():
		inv_use.emit(_inv_sel_secure, _inv_sel)


func _inv_act_move() -> void:
	var lst: Array = _inv_sec if _inv_sel_secure else _inv_bag
	if _inv_sel < lst.size():
		inv_move.emit(_inv_sel_secure, _inv_sel)


## 键盘选格：背包 4 列网格内移动；↓ 出最后一行进安全箱行，↑ 回网格
func _inv_step(dx: int, dy: int) -> void:
	if _inv_sel_secure:
		if dy < 0:
			_inv_sel_secure = false
			_inv_sel = clampi(_inv_bag.size() - 1, 0, HDData.BACKPACK_MAX - 1)
		else:
			_inv_sel = clampi(_inv_sel + dx, 0, maxi(0, _inv_sec.size() - 1))
	else:
		var n := _inv_sel + dx + dy * 4
		if dy > 0 and n >= _inv_bag.size() and not _inv_sec.is_empty():
			_inv_sel_secure = true
			_inv_sel = 0
		else:
			_inv_sel = clampi(n, 0, maxi(0, _inv_bag.size() - 1))
	refresh_inventory(_inv_bag, _inv_sec, _inv_cap)


# ================= 每帧衰减 =================

func _process(dt: float) -> void:
	if _center != null and _center.hit_t > 0.0:
		_center.hit_t = maxf(0.0, _center.hit_t - dt)
		_center.queue_redraw()
	if _danger_panel != null and _danger_panel.visible:
		_pulse_t += dt
		_danger_panel.modulate.a = 0.72 + 0.28 * absf(sin(_pulse_t * 4.0))
	if _hit_ind != null and not _hit_ind.hits.is_empty():
		for h in _hit_ind.hits:
			h["t"] = float(h["t"]) - dt
		_hit_ind.hits = _hit_ind.hits.filter(func(h): return float(h["t"]) > 0.0)
		_hit_ind.queue_redraw()
	var fi := _feeds.size() - 1
	while fi >= 0:
		var fr: Dictionary = _feeds[fi]
		fr["t"] = float(fr["t"]) - dt
		var fnode := fr["node"] as Control
		fnode.modulate.a = clampf(float(fr["t"]) / 0.6, 0.0, 1.0)
		if float(fr["t"]) <= 0.0:
			_feeds.remove_at(fi)
			if fnode.get_parent() != null:
				fnode.get_parent().remove_child(fnode)
			fnode.queue_free()
		fi -= 1
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


## 开镜覆盖层：按 kind 画分划（渐晕已按用户要求整体移除）
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
				# 无框红点镜：镜体已无环框 → 分划只留中心红点（旧 26px 红圈
				# 是「镜环示形」，与无框窗冲突删除；点径 2.6→3.2 保开镜可见性，
				# 2026-10 镜窗改大 60×45mm 后随窗微调至 4.0——别夸张，留观察余量）
				draw_circle(c, 4.0, COL_RED)
			"holo":
				draw_rect(Rect2(c - Vector2(48, 36), Vector2(96, 72)),
						Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 0.4), false, 1.6)
				draw_circle(c, 2.2, COL_GREEN)
				draw_line(c + Vector2(48, 0), c + Vector2(60, 0),
						Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 0.5), 1.2)
			"optic":
				_mil_cross(c, COL_RETICLE, 150.0, 34.0)
			"sniper":
				_mil_cross(c, COL_RETICLE, 220.0, 46.0)
			"thermal":
				draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.85, 0.45, 0.12))
				_mil_cross(c, COL_RETICLE, 120.0, 28.0)
			_:
				pass   # iron：无覆盖层（渐晕已按用户要求移除）
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



## 屏幕边缘红渐晕（危险区警示；可见性由宿主控制）
class EdgeVignette extends Control:
	## 危险区边缘红晕：屏幕中心透明、四角柔和渐红（径向 smoothstep）。
	## 原实现是四圈实心矩形且越往里越不透明——画面上读成一圈硬边红框，像渲染故障
	const TINT := Color(0.78, 0.16, 0.08)

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cr := ColorRect.new()
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.78, 0.16, 0.08, 1.0);
uniform float strength = 0.45;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p * vec2(0.92, 1.0));
	COLOR = vec4(tint.rgb, smoothstep(0.78, 1.42, d) * strength);
}
"""
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("tint", TINT)
		cr.material = sm
		add_child(cr)



## 顶部指南针（2026-10 改进方案第 4 节）：560 px 宽、视野 ±60°；每 5° 小刻度、
## 15° 中刻度、45° 方位字（北/东北…），中央朝向读数；撤离点等标记按方位角落在
## 刻度带上（超出视野贴边显示箭头），下挂距离
class CompassBar extends Control:
	const W := 560.0
	const H := 40.0
	const SPAN := 60.0                  # 半视野（度）
	const NAMES := {0: "北", 45: "东北", 90: "东", 135: "东南", 180: "南", 225: "西南", 270: "西", 315: "西北"}
	var heading := 0.0
	var markers: Array = []             # [{bearing, label, color}]

	func _init() -> void:
		set_anchors_preset(Control.PRESET_CENTER_TOP)
		offset_left = -W * 0.5
		offset_right = W * 0.5
		offset_top = 6
		offset_bottom = 6 + H + 18
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _wrap(d: float) -> float:
		return fposmod(d + 180.0, 360.0) - 180.0

	func _draw() -> void:
		var f := get_theme_default_font()
		var px := W / (SPAN * 2.0)
		var cx := W * 0.5
		draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.05, 0.03, 0.45))
		var base := int(floor((heading - SPAN) / 5.0)) * 5
		var a := base
		while a <= heading + SPAN + 5:
			var d := _wrap(float(a) - heading)
			if absf(d) <= SPAN:
				var x := cx + d * px
				var deg := posmod(a, 360)
				var fade := 1.0 - absf(d) / SPAN * 0.6
				if deg % 45 == 0:
					draw_line(Vector2(x, H - 12), Vector2(x, H), Color(1, 1, 1, 0.9 * fade), 2.0)
					if f != null:
						var nm: String = NAMES.get(deg, str(deg))
						var col := Color(1.0, 0.7, 0.36, fade) if deg == 0 else Color(0.85, 0.87, 0.82, fade)
						var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
						draw_string(f, Vector2(x - tw * 0.5, 17), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
				elif deg % 15 == 0:
					draw_line(Vector2(x, H - 9), Vector2(x, H), Color(1, 1, 1, 0.7 * fade), 1.5)
					if f != null:
						var ns := str(deg)
						var tw2 := f.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
						draw_string(f, Vector2(x - tw2 * 0.5, 15), ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.87, 0.82, 0.55 * fade))
				else:
					draw_line(Vector2(x, H - 5), Vector2(x, H), Color(1, 1, 1, 0.45 * fade), 1.0)
			a += 5
		# 中央朝向指针 + 读数
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, H + 7), Vector2(cx + 6, H + 7), Vector2(cx, H + 1)]), Color(1.0, 0.7, 0.36))
		# 标记（撤离点等）
		for m in markers:
			var md := _wrap(float(m["bearing"]) - heading)
			var col2: Color = m.get("color", Color(0.49, 0.89, 0.66))
			var x2 := cx + clampf(md, -SPAN, SPAN) * px
			if absf(md) <= SPAN:
				draw_colored_polygon(PackedVector2Array([Vector2(x2 - 7, H - 22), Vector2(x2 + 7, H - 22), Vector2(x2, H - 12)]), col2)
			else:
				var sgn := signf(md)
				draw_colored_polygon(PackedVector2Array([Vector2(x2 - sgn * 2, H - 26), Vector2(x2 - sgn * 2, H - 10), Vector2(x2 + sgn * 9, H - 18)]), col2)
			if f != null:
				var lbl := str(m.get("label", ""))
				var tw3 := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				var lx := clampf(x2 - tw3 * 0.5, 0.0, W - tw3)
				draw_string(f, Vector2(lx, H + 16), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col2)


## 受击方向弧：准星外圈 120 px 半径的红色弧段，指向来袭方向（相对视线），1.4 s 淡出
class HitIndicator extends Control:
	const LIFE := 1.4
	const R := 120.0
	var hits: Array = []                # [{a, t}]

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		for h in hits:
			var k := clampf(float(h["t"]) / LIFE, 0.0, 1.0)
			# 屏幕坐标：0 = 正上（前方），顺时针为正（右侧）
			var ang := float(h["a"]) - PI * 0.5
			draw_arc(c, R, ang - 0.32, ang + 0.32, 18, Color(1.0, 0.18, 0.12, 0.85 * k), 7.0, true)
			var tip := c + Vector2(cos(ang), sin(ang)) * (R + 14.0)
			var l := c + Vector2(cos(ang - 0.09), sin(ang - 0.09)) * (R + 4.0)
			var r := c + Vector2(cos(ang + 0.09), sin(ang + 0.09)) * (R + 4.0)
			draw_colored_polygon(PackedVector2Array([l, tip, r]), Color(1.0, 0.18, 0.12, 0.85 * k))
