class_name HDLobby
extends CanvasLayer
## 烽火地带 —— 大厅（移植 js/fps/lobby.js）：顶栏 LOGO/战绩/每日签到/现金，
## 底部「1 出发 / 2 仓库 / 3 改枪台」三页签 +「G 去靶场」。
## 键盘主路径：main 在大厅可见时把按键转发给 handle_key()（返回 true=已消费）。
## 鼠标路径：行点击=选中光标，再点已选行=确认（与回车等价），购买/换装全程可点。
## 出发页光标模型（单轴，候选枪按 DEPLOY_PAGE 分页）：[主槽0 | 副槽1 | 当页枪行 | 出发钮]，
## ←/→ 页内回绕移动；↑/↓ 端点跨页（↓ 越过出发钮=翻下页回槽位0，↑ 在槽位0=翻上页落到出发钮）。
## 回车：槽=设装入目标 · 枪=未拥有先购后装/已拥有直接装 · 出发钮=出发。
## 极致备弹（金色行）：B 循环购买挡位 30/90/300 发 · 空格按挡位购买（余量=stash 库存，
## 首读送满额礼物）；鼠标路径同款两按钮（B 换挡 / 购 N 发）。
## 操作失败（钱不足等）用底部 show_hint() 提示（不用 HUD toast），提示带金额明细。
## 按 1440×810 设计，_apply_ui_scale 按视口高度整体缩放（全屏大屏不缩字）。

signal deploy_requested(loadout: Dictionary)
signal range_requested

const COL_BG := Color(0.03, 0.05, 0.04, 0.95)
const COL_TEXT := Color(0.85, 0.87, 0.82)
const COL_ACCENT := Color(1, 0.7, 0.36)
const COL_OK := Color(0.49, 0.89, 0.66)
const TAB_TITLES := ["1 · 出发", "2 · 仓库", "3 · 改枪台"]
const HINT_LIFE := 2.5              # 底部提示默认停留秒数
const DESIGN_H := 810.0             # UI 设计基准高度（1440×810），缩放 = 视口高 / 此值
const DEPLOY_PAGE := 6              # 出发页候选枪每页行数（12 枪=2 页，光标域随页收缩）

var lobby_visible: bool = false

var _stash: HDStash
var _tab := 0                       # 0 出发 / 1 仓库 / 2 改枪台
var _cur0 := 0                      # 出发页光标（当页行数域：2 槽位 + 当页枪行 + 出发钮）
var _deploy_page := 0               # 出发页候选枪分页索引
var _slot_focus := "primary"        # 出发页「装入目标槽」
var _gun_idx := 0                   # 改枪台左列选中枪
var _scope_idx := 0                 # 改枪台右列选中瞄具（0=机瞄）
var _bench_col := 0                 # 改枪台列：0=枪 1=瞄具
var _ammo_tier := 0                 # 出发页购弹挡位索引（HDData.AMMO_TIERS，B 键循环）
var _hint_t := 0.0

var _root: Control
var _pages: Array = []              # 三个页 VBoxContainer
var _tab_btns: Array = []
var _record_label: Label
var _daily_btn: Button
var _cash_label: Label
var _hint_label: Label


func _init() -> void:
	layer = 20


func _ready() -> void:
	if _root == null:
		_build()
	_refresh_all()


## 连 stash.changed 刷新（可在进树前后任意时机调用）
func setup(stash) -> void:
	_stash = stash
	if stash != null and not stash.changed.is_connected(_refresh_all):
		stash.changed.connect(_refresh_all)
	if _root != null:
		_refresh_all()


func show_lobby() -> void:
	lobby_visible = true
	if _root != null:
		_root.visible = true
	_refresh_all()


func hide_lobby() -> void:
	lobby_visible = false
	if _root != null:
		_root.visible = false


## 大厅可见时的按键入口；返回 true = 已消费
func handle_key(code: int) -> bool:
	if not lobby_visible:
		return false
	match code:
		KEY_1:
			set_tab(0)
		KEY_2:
			set_tab(1)
		KEY_3:
			set_tab(2)
		KEY_C:
			_check_in()
		KEY_G:
			_fire_range()
		KEY_B:
			# 出发页专用：循环极致备弹购买挡位（鼠标点「B 换挡」钮同款）
			if _tab == 0:
				_cycle_ammo_tier()
			else:
				return false
		KEY_SPACE:
			# 出发页专用：按当前挡位给选中枪购极致备弹（鼠标点「购 N 发」钮同款）
			if _tab == 0:
				_buy_ammo_sel()
			else:
				return false
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		KEY_LEFT:
			_move(-1, 0)
		KEY_RIGHT:
			_move(1, 0)
		KEY_UP:
			_move(0, -1)
		KEY_DOWN:
			_move(0, 1)
		_:
			return false
	return true


func _process(dt: float) -> void:
	if _hint_label != null and _hint_t > 0.0:
		_hint_t = maxf(0.0, _hint_t - dt)
		_hint_label.modulate.a = clampf(_hint_t / 0.4, 0.0, 1.0)
		if _hint_t <= 0.0:
			_hint_label.text = ""


## 底部提示条（操作失败/成功反馈，默认 2.5 秒）
func show_hint(text: String, dur: float = HINT_LIFE) -> void:
	if _hint_label == null:
		return
	_hint_label.text = text
	_hint_label.modulate.a = 1.0
	_hint_t = maxf(0.1, dur)


func set_tab(i: int) -> void:
	_tab = clampi(i, 0, 2)
	_refresh_all()


# ================= 构建 =================

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = HDData.ui_theme()   # 中文字体链设为 default_font，全部 Label/Button 继承
	_root.visible = false
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(box)

	# ---- 顶栏：LOGO / 战绩 / 每日签到 / 现金 ----
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _bar_style(true))
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 26)
	top.add_child(th)
	box.add_child(top)

	var logo_box := VBoxContainer.new()
	logo_box.add_theme_constant_override("separation", 0)
	logo_box.add_child(_mk_label("烽火地带", 22, COL_ACCENT))
	logo_box.add_child(_mk_label("TACTICAL OPERATION · 战术行动", 10, _dim(0.5)))
	th.add_child(logo_box)

	_record_label = _mk_label("", 13, _dim(0.72))
	_record_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(_record_label)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp1)

	_daily_btn = _mk_btn("", 13)
	_daily_btn.pressed.connect(_check_in)
	_daily_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(_daily_btn)

	_cash_label = _mk_label("₵ 0", 22, COL_OK)
	_cash_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cash_label.custom_minimum_size = Vector2(150, 0)
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	th.add_child(_cash_label)

	# ---- 中部面板：三页签内容 ----
	var mid := CenterContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(mid)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _page_panel_style())
	mid.add_child(panel)
	var holder := VBoxContainer.new()
	holder.custom_minimum_size = Vector2(980, 430)
	panel.add_child(holder)
	_pages.clear()
	for i in 3:
		var pg := VBoxContainer.new()
		pg.add_theme_constant_override("separation", 10)
		pg.visible = false
		holder.add_child(pg)
		_pages.append(pg)

	# ---- 底栏：页签 + 靶场入口 ----
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _bar_style(false))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bottom.add_child(bh)
	box.add_child(bottom)

	_tab_btns.clear()
	for i in 3:
		var b := _mk_btn(TAB_TITLES[i], 14)
		var idx := i
		b.pressed.connect(func(): set_tab(idx))
		bh.add_child(b)
		_tab_btns.append(b)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp2)
	var rb := _mk_btn("G · 去靶场", 13)
	rb.pressed.connect(_fire_range)
	bh.add_child(rb)

	# ---- 底部提示条 ----
	_hint_label = _mk_label("", 14, COL_ACCENT)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.offset_top = -92
	_hint_label.offset_bottom = -66
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint_label)

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
	if vp == null or _root == null:
		return
	var vs := vp.get_visible_rect().size
	if vs.y <= 0.0:
		return
	var s := clampf(vs.y / DESIGN_H, 0.5, 4.0)
	scale = Vector2(s, s)
	_root.offset_right = vs.x / s - vs.x
	_root.offset_bottom = vs.y / s - vs.y


## 行点击统一入口（鼠标购买链）：未选中=选中该行（光标跟着走）；
## 已选中=确认（与回车等价：槽=设装入目标 · 枪=未拥有先购后装 · 出发钮=出发）。
## page = 候选枪所在分页（槽位卡片绑 -1：不随翻页）；点他页行先翻页再选中。
## 参数序：gui_input 信号实参在前，bind 实参在后（同 city_editor._on_field_changed 约定）
func _on_deploy_row_input(event: InputEvent, page: int, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if page >= 0 and page != _deploy_page:
				_deploy_page = page   # 点的是他页行：先翻到该页，光标落该行
				_cur0 = idx
				_refresh_all()
			elif _cur0 == idx:
				_confirm_deploy()
			else:
				_cur0 = idx
				_refresh_all()


## 改枪台行点击：col=0 左列选枪 / col=1 右列瞄具；再点已选行=确认（同回车）
func _on_bench_row_input(event: InputEvent, col: int, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var cur: int = _gun_idx if col == 0 else _scope_idx
			if _bench_col == col and cur == idx:
				_bench_confirm()
			else:
				_bench_col = col
				if col == 0:
					_gun_idx = idx
				else:
					_scope_idx = idx
				_refresh_all()


# ================= 刷新 =================

func _refresh_all() -> void:
	if _root == null or _stash == null:
		return
	_render_top()
	for i in _pages.size():
		var pg := _pages[i] as VBoxContainer
		pg.visible = i == _tab
		_clear_children(pg)
		if i == _tab:
			match i:
				0: _render_deploy(pg)
				1: _render_stash(pg)
				2: _render_bench(pg)
	for i in _tab_btns.size():
		var b := _tab_btns[i] as Button
		var act: bool = i == _tab
		_style_btn(b, act, COL_ACCENT if act else _dim(0.35))


func _render_top() -> void:
	var st: Dictionary = _stash.stats
	_record_label.text = "出击 %d · 撤离 %d · 阵亡 %d · 击杀 %d" % [
		maxi(0, int(st.get("raids", 0))), maxi(0, int(st.get("extracts", 0))),
		maxi(0, int(st.get("deaths", 0))), maxi(0, int(st.get("kills", 0)))]
	var can: bool = _stash.can_check_in()
	_daily_btn.text = ("C · 每日签到 +₵%s" % _fmt(HDData.DAILY_REWARD)) if can else "今日已签到"
	_style_btn(_daily_btn, can, COL_ACCENT if can else _dim(0.35))
	if not can:
		_daily_btn.add_theme_color_override("font_color", _dim(0.45))
	_cash_label.text = "₵ " + _fmt(maxi(0, _stash.cash))


# ================= 出发页 =================

## 候选枪总页数（12 枪 / 每页 DEPLOY_PAGE = 2 页）
func _deploy_pages() -> int:
	return int(ceil(float(Guns.GUNS.size()) / float(DEPLOY_PAGE)))


## 当前页候选枪行数（末页不满页取余数）
func _deploy_rows() -> int:
	return mini(DEPLOY_PAGE, Guns.GUNS.size() - _deploy_page * DEPLOY_PAGE)

func _render_deploy(pg: VBoxContainer) -> void:
	var guns: Array = Guns.GUNS
	_deploy_page = clampi(_deploy_page, 0, _deploy_pages() - 1)
	var rows := _deploy_rows()
	var n := 3 + rows          # 光标域：2 槽位 + 当页枪行 + 出发钮
	_cur0 = posmod(_cur0, n)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	pg.add_child(cols)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_stretch_ratio = 2.4
	main.add_theme_constant_override("separation", 10)
	cols.add_child(main)

	# 主/副武器槽（聚焦槽 = 装入目标）
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 12)
	main.add_child(slots)
	var slot_defs := [["primary", "主武器 · 1"], ["secondary", "副武器 · 2"]]
	for i in 2:
		var key: String = slot_defs[i][0]
		var gid := str(_stash.loadout.get(key, "rifle"))
		var g := Guns.gun_by_id(gid)
		var sel := _cur0 == i
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",
				_panel_style(sel, COL_ACCENT if sel else _dim(0.25)))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到卡片本身
		card.add_child(vb)
		var focus_here := _slot_focus == key
		vb.add_child(_mk_label(("「装入此槽」· " if focus_here else "") + str(slot_defs[i][1]),
				11, COL_OK))
		card.gui_input.connect(_on_deploy_row_input.bind(-1, i))
		vb.add_child(_mk_label(String(g.get("name", gid)), 18, COL_ACCENT))
		vb.add_child(_mk_label(String(g.get("desc", "")), 12, _dim(0.6)))
		slots.add_child(card)

	# 候选枪列表（只画当前页；未拥有显示价格，回车/再点行即购买）
	var owned_n := 0
	for g0 in guns:
		if _stash.guns_owned.has(str(g0["id"])):
			owned_n += 1
	main.add_child(_mk_label("候选枪（已拥有 %d/%d）· 第 %d/%d 页" % [
			owned_n, guns.size(), _deploy_page + 1, _deploy_pages()], 11, COL_OK))
	var first: int = _deploy_page * DEPLOY_PAGE
	for r in rows:
		var g2: Dictionary = guns[first + r]
		var id2 := str(g2["id"])
		var owned: bool = _stash.guns_owned.has(id2)
		var sel2 := _cur0 == 2 + r
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel",
				_panel_style(sel2, COL_ACCENT if sel2 else _dim(0.22)))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到行卡片
		row.add_child(hb)
		hb.add_child(_mk_label(String(g2.get("name", id2)), 15, COL_TEXT if owned else _dim(0.55)))
		var desc := _mk_label(String(g2.get("desc", "")), 12, _dim(0.6))
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(desc)
		var price := _to_int(g2.get("price", 0))
		hb.add_child(_mk_label("已拥有" if owned else "₵ " + _fmt(price),
				13, COL_OK if owned else COL_ACCENT))
		row.gui_input.connect(_on_deploy_row_input.bind(_deploy_page, 2 + r))
		main.add_child(row)

	# 出发钮
	var di := 2 + rows
	var dsel := _cur0 == di
	var btn := _mk_btn("出  发", 17)
	_style_btn(btn, dsel, COL_ACCENT if dsel else _dim(0.5), 60)
	btn.pressed.connect(_fire_deploy)
	var bwrap := CenterContainer.new()
	bwrap.add_child(btn)
	main.add_child(bwrap)
	var hint := _mk_label("←/→ 选择 · ↑↓ 跨页 · 回车/点击行 确认（未拥有枪直接购买） · B 换挡 空格 购极致备弹 · G 靶场 · 1/2/3 切页签",
			12, _dim(0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(hint)

	# 右侧：光标所指武器速览（枪行光标要换算回全局枪表下标）
	var sel_id := _deploy_sel_id()
	var sg := Guns.gun_by_id(sel_id)
	var owned_sel: bool = _stash.guns_owned.has(sel_id)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	cols.add_child(side)
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _panel_style(false, _dim(0.2)))
	side.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 4)
	info.add_child(iv)
	iv.add_child(_mk_label(String(sg.get("name", sel_id)), 16, COL_ACCENT))
	var cd := float(sg.get("cd", 0.0))
	var rate := (1.0 / cd) if cd > 0.0 else 0.0
	iv.add_child(_mk_label("伤害 %s · 射速 %.1f/s" % [str(sg.get("dmg", "--")), rate],
			12, COL_TEXT))
	iv.add_child(_mk_label("弹匣 %s · 射程 %sm · 单价 ₵%d/发" % [
			str(sg.get("mag", "--")), str(sg.get("range", "--")),
			_to_int(HDData.AMMO_PRICE.get(sel_id, 0))], 12, COL_TEXT))
	var price2 := _to_int(sg.get("price", 0))
	iv.add_child(_mk_label("身价：" + ("已拥有" if owned_sel else "₵ " + _fmt(price2)),
			12, COL_OK))
	# 极致备弹行（金色标识）：余量来自 stash 库存（首读缺键即送满额礼物）；
	# 购买挡位 B 键循环 / 空格购买（键盘），「B 换挡」「购 N 发」按钮（鼠标）
	var ammo_n: int = _stash.ammo_of(sel_id)
	iv.add_child(_mk_label("%s 余 %d 发 / 满额 %d 发" % [HDData.AMMO_NAME, ammo_n,
			_to_int(HDData.RESERVE.get(sel_id, 0))], 13, HDData.AMMO_COLOR))
	var tier_n: int = _ammo_tier_n()
	var ammo_row := HBoxContainer.new()
	ammo_row.add_theme_constant_override("separation", 6)
	iv.add_child(ammo_row)
	var cyc := _mk_btn("B 换挡", 12)
	_style_btn(cyc, false, _dim(0.6), 10)
	cyc.pressed.connect(_cycle_ammo_tier)
	ammo_row.add_child(cyc)
	var buy := _mk_btn("购 %d 发 · ₵%s" % [tier_n, _fmt(tier_n * _to_int(
			HDData.AMMO_PRICE.get(sel_id, 0)))], 12)
	_style_btn(buy, true, HDData.AMMO_COLOR, 12)
	buy.pressed.connect(_buy_ammo_sel)
	ammo_row.add_child(buy)


## 出发页当前选中枪 id（速览与购弹共用）：槽位=loadout 对应枪 · 枪行=该行枪
## （出发钮位回退主武器——越界会翻到他页枪）
func _deploy_sel_id() -> String:
	var guns: Array = Guns.GUNS
	var rows := _deploy_rows()
	var sel_id := str(_stash.loadout.get("primary", "rifle"))
	if _cur0 == 1:
		sel_id = str(_stash.loadout.get("secondary", "pistol"))
	elif _cur0 >= 2 and _cur0 < 2 + rows:
		var gidx: int = _deploy_page * DEPLOY_PAGE + (_cur0 - 2)
		if gidx < guns.size():
			sel_id = str(guns[gidx]["id"])
	return sel_id


## 当前购买挡位发数（索引越界防御回绕）
func _ammo_tier_n() -> int:
	return int(HDData.AMMO_TIERS[posmod(_ammo_tier, HDData.AMMO_TIERS.size())])


## B 键 /「B 换挡」钮：购买挡位 30→90→300 循环（总价随行实时刷新）
func _cycle_ammo_tier() -> void:
	_ammo_tier = posmod(_ammo_tier + 1, HDData.AMMO_TIERS.size())
	_refresh_all()


## 空格 /「购 N 发」钮：按当前挡位给选中枪买极致备弹（现金不足拦截提示，照购枪款）
func _buy_ammo_sel() -> void:
	var sel_id := _deploy_sel_id()
	var n := _ammo_tier_n()
	var each := _to_int(HDData.AMMO_PRICE.get(sel_id, 0))
	var total := n * each
	if not _stash.buy_ammo(sel_id, n):
		show_hint("现金不足：%s ×%d 发需 ₵%s，现有 ₵%s —— 回仓库变卖战利品或明日签到" % [
				HDData.AMMO_NAME, n, _fmt(total), _fmt(maxi(0, _stash.cash))])
		return
	show_hint("已购 %s ×%d 发 −₵%s（余 ₵%s）" % [
			HDData.AMMO_NAME, n, _fmt(total), _fmt(maxi(0, _stash.cash))])


## 出发页确认（键盘回车与鼠标再点已选行同收敛于此）：
## 槽=设装入目标 · 枪行=未拥有先 buy_gun 再装入（钱不够拦截不扣款）· 出发钮=出发
func _confirm_deploy() -> void:
	var guns: Array = Guns.GUNS
	var rows := _deploy_rows()
	if _cur0 <= 1:
		_slot_focus = "primary" if _cur0 == 0 else "secondary"
		_refresh_all()
		return
	if _cur0 >= 2 and _cur0 < 2 + rows:
		var gi: int = _deploy_page * DEPLOY_PAGE + (_cur0 - 2)
		var gid := str(guns[gi]["id"])
		if not _stash.guns_owned.has(gid):
			var g := Guns.shop_gun_by_id(gid)
			var price := _to_int(g.get("price", 0))
			if not _stash.buy_gun(gid):
				show_hint("现金不足：%s 需 ₵%s，现有 ₵%s —— 回仓库变卖战利品或明日签到" % [
						String(g.get("name", gid)), _fmt(price),
						_fmt(maxi(0, _stash.cash))])
				return
			show_hint("已购买：%s（余 ₵%s）" % [
					String(g.get("name", gid)), _fmt(maxi(0, _stash.cash))])
		_load_gun(gid)
		return
	_fire_deploy()


## 把候选枪装入聚焦槽（主副不可同枪；装完自动跳另一槽）
func _load_gun(id: String) -> void:
	if not _stash.guns_owned.has(id):
		show_hint("尚未拥有该枪械")
		return
	var other := "secondary" if _slot_focus == "primary" else "primary"
	if str(_stash.loadout.get(other, "")) == id:
		show_hint("主副武器不可相同")
		return
	var p := id if _slot_focus == "primary" else str(_stash.loadout.get("primary", "rifle"))
	var s := id if _slot_focus == "secondary" else str(_stash.loadout.get("secondary", "pistol"))
	_stash.loadout = {"primary": p, "secondary": s}
	_stash.save()
	_stash.changed.emit()        # HDStash 无 set_loadout 契约：大厅代发
	_slot_focus = other


func _fire_deploy() -> void:
	var p := str(_stash.loadout.get("primary", ""))
	var s := str(_stash.loadout.get("secondary", ""))
	if p == "" or s == "" or p == s:
		show_hint("主副武器不可相同")
		return
	hide_lobby()
	deploy_requested.emit({"primary": p, "secondary": s})


func _fire_range() -> void:
	hide_lobby()
	range_requested.emit()


# ================= 仓库页 =================

func _render_stash(pg: VBoxContainer) -> void:
	var items: Array = _stash.items
	if items.is_empty():
		var empty := _mk_label("仓库空空如也 —— 出发搜刮，活着带回来", 15, _dim(0.6))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pg.add_child(empty)
	else:
		var grid := GridContainer.new()
		grid.columns = 7
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pg.add_child(grid)
		for it in items:
			if typeof(it) == TYPE_DICTIONARY:
				grid.add_child(_loot_cell(it))

	var items_sum := 0
	for it2 in items:
		if typeof(it2) == TYPE_DICTIONARY:
			items_sum += _to_int(it2.get("value", 0))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	pg.add_child(foot)
	foot.add_child(_mk_label("总资产 ₵%s（含现金） · 仓库 %d/%d 格" % [
			_fmt(items_sum + maxi(0, _stash.cash)), items.size(), HDData.BACKPACK_MAX],
			14, COL_ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var sell := _mk_btn("Enter 一键变卖全部", 13)
	_style_btn(sell, not items.is_empty(), COL_ACCENT if not items.is_empty() else _dim(0.3))
	sell.pressed.connect(_sell_all)
	foot.add_child(sell)
	var hint := _mk_label("回车 一键变卖 · 品质越高越值钱", 12, _dim(0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pg.add_child(hint)


## 品质色边框 + icon + 名称 + 价值 的一格
func _loot_cell(it: Dictionary) -> PanelContainer:
	var rid := clampi(_to_int(it.get("rarity", 0)), 0, 6)
	var rar: Dictionary = HDData.RARITY[rid]
	var rcol: Color = rar["color"]
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(118, 92)
	var sb := _panel_style(false, rcol)
	sb.bg_color = Color(0.05 + rcol.r * 0.1, 0.07 + rcol.g * 0.1, 0.06 + rcol.b * 0.1, 0.8)
	cell.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	cell.add_child(vb)
	var icon := _mk_label(HDData.norm_icon(String(it.get("icon", ""))), 22, rcol)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(icon)
	var nm := _mk_label(String(it.get("name", "战利品")), 11, rcol)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var val := _mk_label("₵ " + _fmt(_to_int(it.get("value", 0))), 12, COL_OK)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(val)
	return cell


func _sell_all() -> void:
	if _stash.items.is_empty():
		show_hint("仓库空空如也 —— 出发搜刮，活着带回来")
		return
	var n := _stash.items.size()
	var sum := _stash.sell_all()
	show_hint("一键变卖 %d 件 +₵%s" % [n, _fmt(sum)])


# ================= 改枪台页 =================

## 右列条目：机瞄 + 五镜（Guns.SCOPES 表序）
func _scope_entries() -> Array:
	var out: Array = [{"id": "iron", "name": "机瞄",
			"desc": "恢复默认机械瞄具 · 回车卸下", "price": 0}]
	for sc in Guns.SCOPES:
		out.append(sc)
	return out


func _render_bench(pg: VBoxContainer) -> void:
	var guns: Array = Guns.GUNS
	_gun_idx = posmod(_gun_idx, guns.size())
	var gun: Dictionary = guns[_gun_idx]
	var gun_id := str(gun["id"])
	var entries := _scope_entries()
	_scope_idx = posmod(_scope_idx, entries.size())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	pg.add_child(cols)

	# 左列：枪械（↑↓ 选枪）
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(_mk_label("枪械（↑↓ 选枪）", 12, COL_OK))
	for i in guns.size():
		var g: Dictionary = guns[i]
		var id2 := str(g["id"])
		var tag := "机瞄"
		if g.has("builtin_scope"):
			tag = "自带 %.0f×" % float(g["builtin_scope"].get("zoom", 1.0))
		elif str(_stash.scope_fit.get(id2, "iron")) != "iron":
			var sc := Guns.scope_by_id(str(_stash.scope_fit.get(id2, "")))
			if not sc.is_empty():
				tag = String(sc.get("name", "已装镜"))
		var sel := _bench_col == 0 and i == _gun_idx
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel",
				_panel_style(sel, COL_ACCENT if sel else _dim(0.22)))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到行卡片
		row.add_child(hb)
		hb.add_child(_mk_label(String(g.get("name", id2)), 14, COL_TEXT))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 弹性占位不截胡点击
		hb.add_child(sp)
		hb.add_child(_mk_label(tag, 12, COL_OK))
		row.gui_input.connect(_on_bench_row_input.bind(0, i))
		left.add_child(row)

	# 右列：瞄具列表（机瞄/五镜），现金常显在标题，钱不足一眼可见
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	var title := "瞄具 —— 为「%s」选配（现金 ₵%s）" % [
			String(gun.get("name", gun_id)), _fmt(maxi(0, _stash.cash))]
	if gun.has("builtin_scope"):
		title += "（自带 6× 密位镜）"
	right.add_child(_mk_label(title, 12, COL_OK))
	for i in entries.size():
		var e: Dictionary = entries[i]
		var sid := str(e["id"])
		var sel2 := _bench_col == 1 and i == _scope_idx
		var row2 := PanelContainer.new()
		row2.add_theme_stylebox_override("panel",
				_panel_style(sel2, COL_ACCENT if sel2 else _dim(0.22)))
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 10)
		hb2.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到行卡片
		row2.add_child(hb2)
		hb2.add_child(_mk_label(String(e.get("name", sid)), 14, COL_TEXT))
		var desc := _mk_label(String(e.get("desc", "")), 12, _dim(0.6))
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb2.add_child(desc)
		hb2.add_child(_mk_label(_scope_tag(gun_id, sid, e), 12, _scope_tag_col(gun_id, sid)))
		row2.gui_input.connect(_on_bench_row_input.bind(1, i))
		right.add_child(row2)

	var hint := _mk_label("←→ 换列 · ↑↓ 选项 · 回车/点击行 购买·换装·卸下（瞄具单持：同镜装他枪自动卸下）",
			12, _dim(0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pg.add_child(hint)


## 瞄具条目右侧状态标签：默认 / 已装 / 装于他枪（单持提示）/ 已拥有 / 价格
func _scope_tag(gun_id: String, sid: String, e: Dictionary) -> String:
	if sid == "iron":
		return "默认 · 卸下"
	if str(_stash.scope_fit.get(gun_id, "iron")) == sid:
		return "● 已装"
	for gid in _stash.scope_fit.keys():
		if str(gid) != gun_id and str(_stash.scope_fit[gid]) == sid:
			var gname := str(gid)
			for g in Guns.GUNS:
				if str(g["id"]) == str(gid):
					gname = String(g.get("name", gname))
			return "装于 " + gname
	if _stash.owns_scope(sid):
		return "已拥有 · 回车换装"
	return "₵ " + _fmt(_to_int(e.get("price", 0)))


func _scope_tag_col(gun_id: String, sid: String) -> Color:
	if sid == "iron":
		return _dim(0.6)
	if str(_stash.scope_fit.get(gun_id, "iron")) == sid:
		return COL_OK
	for gid in _stash.scope_fit.keys():
		if str(gid) != gun_id and str(_stash.scope_fit[gid]) == sid:
			return _dim(0.6)
	if _stash.owns_scope(sid):
		return COL_OK
	return COL_ACCENT


func _bench_confirm() -> void:
	var guns: Array = Guns.GUNS
	_gun_idx = posmod(_gun_idx, guns.size())
	var gun: Dictionary = guns[_gun_idx]
	var gun_id := str(gun["id"])
	if _bench_col == 0:              # 左列=选枪，右侧联动
		_refresh_all()
		return
	var entries := _scope_entries()
	_scope_idx = posmod(_scope_idx, entries.size())
	var entry: Dictionary = entries[_scope_idx]
	var sid := str(entry["id"])
	if sid == "iron":
		_stash.equip_scope(gun_id, "iron")
		show_hint("已卸下瞄具 —— 恢复机瞄")
		return
	if str(_stash.scope_fit.get(gun_id, "iron")) == sid:
		show_hint("该瞄具已装在此枪上")
		return
	if not _stash.owns_scope(sid):
		if not _stash.buy_scope(sid):
			show_hint("现金不足：%s 需 ₵%s，现有 ₵%s —— 回仓库变卖战利品或明日签到" % [
					String(entry.get("name", sid)),
					_fmt(_to_int(entry.get("price", 0))), _fmt(maxi(0, _stash.cash))])
			return
		_stash.equip_scope(gun_id, sid)
		show_hint("已购买并装配：%s（余 ₵%s）" % [
				String(entry.get("name", sid)), _fmt(maxi(0, _stash.cash))])
		return
	_stash.equip_scope(gun_id, sid)
	show_hint("已换装：%s" % String(entry.get("name", sid)))


# ================= 光标 / 确认 =================

func _move(dh: int, dv: int) -> void:
	match _tab:
		0:
			# ←/→ 页内回绕；↑/↓ 单步行进、端点跨页：↓ 越过出发钮翻下页回槽位0，
			# ↑ 在槽位0 翻上页落到出发钮位（回绕成环）
			var rows := _deploy_rows()
			var n := 3 + rows
			if dv > 0:
				if _cur0 + 1 >= n:
					_deploy_page = posmod(_deploy_page + 1, _deploy_pages())
					_cur0 = 0
				else:
					_cur0 += 1
			elif dv < 0:
				if _cur0 - 1 < 0:
					_deploy_page = posmod(_deploy_page - 1, _deploy_pages())
					_cur0 = 2 + _deploy_rows()
				else:
					_cur0 -= 1
			else:
				_cur0 = posmod(_cur0 + dh, n)
		1:
			return                  # 仓库页无网格光标
		2:
			if dh != 0:
				_bench_col = 1 - _bench_col
			if dv != 0:
				if _bench_col == 0:
					_gun_idx = posmod(_gun_idx + dv, Guns.GUNS.size())
				else:
					_scope_idx = posmod(_scope_idx + dv, 1 + Guns.SCOPES.size())
	_refresh_all()


func _confirm() -> void:
	match _tab:
		0:
			_confirm_deploy()
		1:
			_sell_all()
		2:
			_bench_confirm()


func _check_in() -> void:
	var got := _stash.check_in()
	if got > 0:
		show_hint("签到成功 +₵%s —— 明天再来" % _fmt(got))
	else:
		show_hint("今天已经签到过了 —— 明天再来")


# ================= UI 小工具 =================

func _clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _mk_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _mk_btn(txt: String, fsize: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fsize)
	return b


func _style_btn(b: Button, active: bool, border: Color, hpad := 22) -> void:
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.17, 0.13, 0.06, 0.9) if active else Color(0.07, 0.1, 0.08, 0.85)
		sb.border_color = border
		sb.set_border_width_all(2 if active else 1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(8)
		sb.content_margin_left = hpad
		sb.content_margin_right = hpad
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", border)
	b.add_theme_color_override("font_hover_color", border)
	b.add_theme_color_override("font_pressed_color", border)


func _panel_style(sel: bool, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.11, 0.88) if sel else Color(0.06, 0.09, 0.07, 0.62)
	sb.border_color = border
	sb.set_border_width_all(2 if sel else 1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(9)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


func _bar_style(top: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.06, 0.92)
	sb.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.3)
	if top:
		sb.border_width_bottom = 1
	else:
		sb.border_width_top = 1
	sb.set_content_margin_all(10)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	return sb


func _page_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.05, 0.86)
	sb.border_color = Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 0.22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(18)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	return sb


func _dim(a: float) -> Color:
	return Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, a)


static func _to_int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return int(round(float(v)))
		TYPE_STRING:
			return int(round(float(str(v))))
	return 0


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
