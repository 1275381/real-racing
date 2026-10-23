class_name HDLobby
extends CanvasLayer
## 烽火地带 —— 大厅（移植 js/fps/lobby.js）：顶栏 LOGO/战绩/每日签到/现金，
## 底部「出发大厅 / 改枪台 / 交易行」三页签 +「G · 练习靶场 · 不耗弹药」
## （实战/练习两个入口一眼可辨：出发 CTA 红橙=消耗极致备弹，靶场入口绿=免费）。
## 键盘主路径：main 在大厅可见时把按键转发给 handle_key()（返回 true=已消费）；
## 数字键 1/2/3 直切页签（页签钮与全部指路文案统一「按 N 进」口径，无「页签 N」字样）。
## 鼠标路径（用户「点击等于装备」）：点击行=直接装备——复用键盘既有确认链收敛，
## 不另起逻辑：出发页当页枪行=选中+装入聚焦槽（未拥有指路按 3），他页行=翻页+选中
## （防跨页误触装错枪）；改枪台左列=装枪/右列=换装（狙击自带镜守卫照拦、未拥有指路
## 不自动跳页）；交易行例外维持只选中（防误购，成交仍走行内「购买」钮）；
## 槽位卡片再点已选卡=设装入目标（与回车等价）。
## 出发页光标模型（单轴，候选枪按 DEPLOY_PAGE 分页）：[主槽0 | 副槽1 | 当页枪行 | 出发钮]，
## ←/→ 页内回绕移动；↑/↓ 端点跨页（↓ 越过出发钮=翻下页回槽位0，↑ 在槽位0=翻上页落到出发钮）。
## 回车：槽=设装入目标 · 枪=已拥有直接装（未拥有提示「按 3 进交易行」）· 出发钮=出发。
## 交易行（页签 3）= 全游戏唯一购买入口 + 仓库去向，四段分区：
## ① 枪械 ② 瞄具 ③ 极致备弹 ④ 仓库·战利品（原仓库页并入，变卖在此成交）：
## ←/→ 跨段 · 段内 ↑↓ 选条目（④段无条目 no-op）· 回车/「购买」钮成交
## （buy_gun/buy_scope/buy_ammo/sell_all 既有链）；B 循环购弹挡位 30/90/300 ·
## 空格按挡位购弹——分级守卫：只在③区内消费；交易行他段弹指路 hint 后不消费
## （←/→ 可达③区，指路不误导）；出发/改枪台页静默不消费（那两页到不了③区）。
## 改枪台：左列枪/右列瞄具两列——左列回车=一步预安装（自动跳右列选中「第一个已拥有
## 且未装」的镜）；自带 6× 原厂镜的枪（狙击）守卫拦截换装（局内 builtin 优先，
## 预装镜会被静默覆盖=装了白装）；未拥有镜行内「去购买」一键跳交易行②区对应行。
## 操作失败（钱不足等）用底部 show_hint() 提示（不用 HUD toast），提示带金额明细。
## 按 1440×810 设计，_apply_ui_scale 按视口高度整体缩放（全屏大屏不缩字）。
## 2026-10 第四阶段卡片式改版（改进方案第 7 节「卡片式布局、字号放大、鼠标优先」）：
## 页签挪到顶栏大按钮；出发页 = 本局装备卡（耐久条/消音器/备弹）+ 3×2 武器卡 +
## 出发栏（押上金额 / 投保勾选 I / 出发 CTA / 战绩卡）；改枪台中列 = 3D 枪械预览
## （独立世界 SubViewport 转台，可拖动）+ 数据条 + 维修 R / 消音器 V；交易行枪械 4 列
## 卡片。光标模型、确认链与全部键位不变（回归测试按原状态机断言）。
## 2026-10 三角洲式 3D 改版：出发大厅主画面换成 3D 备战机库（hd_lobby_scene.gd：
## 干员持当前配枪站右三分线）——出发页重排为「左列本局装备 + 左下角仓库/交易行
## 面板组（用户点名停靠）+ 底部换枪条 + 右侧出发栏」，中央留给干员；改枪台/交易行
## 两页整页照旧（1/2/3 页签与点击链路零丢失），出发页背景透出机库、其余页不透明。
## 2026-10 战备收拢（用户定案「点进去才能战备战」）：本局装备槽卡/换枪条/速览
## 全部收进战备面板，主画面只留 3D 干员 + 右下角「战备」小贴图（TAB 同链开合）；
## 收起态光标域只剩出发钮（回车=出发），展开态键鼠链与收拢前完全一致。

signal deploy_requested(loadout: Dictionary)
signal range_requested

## 3D 出发大厅场景（新脚本一律 preload，无 class_name——见 hd_lobby_scene.gd 头注）
const LobbyScene := preload("res://scripts/hd_lobby_scene.gd")

const COL_BG := Color(0.03, 0.05, 0.04, 0.95)
const COL_TEXT := Color(0.85, 0.87, 0.82)
const COL_ACCENT := Color(1, 0.7, 0.36)
const COL_OK := Color(0.49, 0.89, 0.66)
const COL_LOW := Color(1.0, 0.48, 0.27)   # 实战消耗警示色（与 HUD.COL_LOW 同值）：出发 CTA 专用
const COL_CARD := Color(0.075, 0.1, 0.085, 0.9)       # 卡片底（第四阶段卡片式改版）
const COL_CARD_SEL := Color(0.13, 0.16, 0.12, 0.96)   # 光标所在卡片底
const TAB_TITLES := ["出发大厅", "改枪台", "交易行"]
const HINT_LIFE := 2.5              # 底部提示默认停留秒数
const DESIGN_H := 810.0             # UI 设计基准高度（1440×810），缩放 = 视口高 / 此值
const DEPLOY_PAGE := 6              # 出发页候选枪每页行数（15 枪=3 页，光标域随页收缩）
const MARKET_SECS := 5              # 交易行段数：0 枪械 / 1 瞄具 / 2 极致备弹 / 3 仓库·战利品 / 4 M14 配件（2026-10；未拥有 M14 时⑤区隐藏但段号保留——posmod 导航空跳无害）

var lobby_visible: bool = false

var _stash: HDStash
var _tab := 0                       # 0 出发大厅 / 1 改枪台 / 2 交易行
var _cur0 := 0                      # 出发页光标（展开态域：2 槽位 + 当页枪行 + 出发钮；收起态只有出发钮）
var _deploy_page := 0               # 出发页候选枪分页索引
var _prep_open := false             # 出发页战备面板开合（右下角「战备」贴图 / TAB 同链）
var _variant_idx := 0               # 天气变体索引（阶段 C：RAID_VARIANTS 键序循环）
var _slot_focus := "primary"        # 出发页「装入目标槽」
var _gun_idx := 0                   # 改枪台左列选中枪
var _scope_idx := 0                 # 改枪台右列选中瞄具（0=机瞄）
var _bench_col := 0                 # 改枪台列：0=枪 1=瞄具
var _ammo_tier := 0                 # 交易行③区购弹挡位索引（HDData.AMMO_TIERS，B 键循环）
var _market_sec := 0                # 交易行当前段：0 枪械 / 1 瞄具 / 2 极致备弹 / 3 仓库·战利品
var _market_gun := 0                # 交易行①区选中枪
var _market_scope := 0              # 交易行②区选中瞄具（0=机瞄行）
var _market_ammo_gun := 0           # 交易行③区购弹对象枪
var _market_m14_mod := 0            # 交易行⑤区选中 M14 配件（2026-10）
var _hint_t := 0.0
var _insure := false                # 出发页「投保」勾选（出发时随 loadout 发给 main 扣费）
## 改枪台 3D 预览（常驻复用的 SubViewport；main 注入枪模工厂）
var gun_preview_provider: Callable = Callable()
var scope_preview_provider: Callable = Callable()   # main 注入：func(kind)->Node3D 单枚镜体
var _thumbs                         # 缩略图渲染器（hd_thumbs.gd；main 注入，headless 下不出图）
var _thumb_wait := {}               # 缩略图键 -> [TextureRect]：图拍好了就地补上，不整页重建
var _glow_tex: GradientTexture2D    # 缩略图背后的柔光底（暗色枪身压在暗卡片上要有衬托）
var _pv_box: SubViewportContainer
var _pv_vp: SubViewport
var _pv_pivot: Node3D
var _pv_cam: Camera3D
var _pv_key := ""
var _pv_yaw := 0.55
var _pv_drag := false
## 3D 出发大厅场景（hd_lobby_scene.gd；main 装配注入）：大厅页显隐/换装联动
var _scene: LobbyScene

var _root: Control
var _bg_rect: ColorRect             # 页面底色：出发页半透明透出 3D 机库，其余页近实心
var _glow_rect: TextureRect         # 顶部暖光晕（同上按页签调强度）
var _pages: Array = []              # 三个页 VBoxContainer（随 TAB_TITLES 自动生成）
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


## 3D 大厅场景注入（main 装配）：此后显隐/页签/换装全部联动它
func attach_scene(s: LobbyScene) -> void:
	_scene = s


func show_lobby() -> void:
	lobby_visible = true
	if _root != null:
		_root.visible = true
	_refresh_all()


func hide_lobby() -> void:
	lobby_visible = false
	if _root != null:
		_root.visible = false
	if _scene != null:
		_scene.set_active(false)   # 对局/靶场里机库视口整层停更（性能红线）


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
		KEY_U:
			# 安全箱扩容只在交易行消费（④ 仓库段标题行有同名按钮）
			if _tab != 2:
				return false
			_buy_secure()
		KEY_B:
			# 分级守卫：B（循环购弹挡位）只在交易行③ 极致备弹区内消费——
			# ③区内=换挡；交易行他段=弹指路 hint 后不消费（←/→ 可达③区，指路不误导）；
			# 其它页签（出发/改枪台，←/→ 到不了③区）静默 return false
			if _tab == 2 and _market_sec == 2:
				_cycle_ammo_tier()
			elif _tab == 2:
				show_hint("按 ←/→ 切到 ③ 极致备弹区再买弹")
				return false
			else:
				return false
		KEY_SPACE:
			# 同 B 分级：空格（按当前挡位购弹）只在③区内消费——守卫后不可能
			# 跨段买错对象（修「①区按空格实际买到③区光标所指枪」的陷阱）
			if _tab == 2 and _market_sec == 2:
				_buy_ammo_for(_market_ammo_gun_id())
			elif _tab == 2:
				show_hint("按 ←/→ 切到 ③ 极致备弹区再买弹")
				return false
			else:
				return false
		KEY_I:
			if _tab != 0:
				return false
			_toggle_insure()
		KEY_TAB:
			# 战备面板开合（右下角「战备」贴图同链）；只在出发页消费
			if _tab != 0:
				return false
			_toggle_prep(not _prep_open)
		KEY_R:
			if _tab != 1:
				return false
			_repair_sel()
		KEY_V:
			# 出发页=天气变体循环（阶段 C）；改枪台=消音器（旧链）
			if _tab == 0:
				_cycle_variant()
			elif _tab == 1:
				_sup_sel()
			else:
				return false
		KEY_N:
			# 弹种循环（阶段 D）：只在交易行③ 极致备弹区消费（给光标所指枪换/购弹种）
			if _tab == 2 and _market_sec == 2:
				_cycle_ammo_kind_for(_market_ammo_gun_id())
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
	# 改枪台预览转台：没在拖就慢转
	if _pv_pivot != null and _pv_box != null and _pv_box.is_inside_tree():
		if not _pv_drag:
			_pv_yaw += dt * 0.35
		_pv_pivot.rotation.y = _pv_yaw
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
	_tab = clampi(i, 0, TAB_TITLES.size() - 1)
	_refresh_all()


## 战备面板开合（TAB / 右下角「战备」贴图 / 面板 ✕ 同链）：开合都把光标归位——
## 收起态光标域只剩出发钮（0 号=出发），展开态 0 号=主武器槽（键盘链与收拢前一致）
func _toggle_prep(open: bool) -> void:
	_prep_open = open
	_cur0 = 0
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
	_bg_rect = bg
	# 顶部暖光晕（卡片式改版：纯色底太平，顶上压一层琥珀渐变出层次）
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(COL_ACCENT.r, COL_ACCENT.g * 0.8, COL_ACCENT.b * 0.5, 0.10))
	gg.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = gg
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow.offset_bottom = 360
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(glow)
	_glow_rect = glow

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	_root.add_child(box)

	# ---- 顶栏：LOGO / 三大页签（鼠标优先，大按钮）/ 每日签到 / 现金 ----
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _bar_style(true))
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	top.add_child(th)
	box.add_child(top)

	var logo_box := VBoxContainer.new()
	logo_box.add_theme_constant_override("separation", -2)
	logo_box.add_child(_mk_label("烽火地带", 28, COL_ACCENT))
	logo_box.add_child(_mk_label("TACTICAL OPERATION · 战术行动", 11, _dim(0.5)))
	th.add_child(logo_box)
	var sp0 := Control.new()
	sp0.custom_minimum_size = Vector2(10, 0)
	th.add_child(sp0)

	_tab_btns.clear()
	for i in TAB_TITLES.size():
		var b := _mk_btn("%d  %s" % [i + 1, TAB_TITLES[i]], 18)
		b.custom_minimum_size = Vector2(150, 46)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		b.pressed.connect(func(): set_tab(idx))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		th.add_child(b)
		_tab_btns.append(b)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp1)

	_daily_btn = _mk_btn("", 15)
	_daily_btn.pressed.connect(_check_in)
	_daily_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_daily_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	th.add_child(_daily_btn)

	var cash_box := VBoxContainer.new()
	cash_box.add_theme_constant_override("separation", -4)
	cash_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cash_cap := _mk_label("现金", 11, _dim(0.5))
	cash_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_box.add_child(cash_cap)
	_cash_label = _mk_label("₵ 0", 28, COL_OK)
	_cash_label.custom_minimum_size = Vector2(170, 0)
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_box.add_child(_cash_label)
	th.add_child(cash_box)

	# ---- 中部：三页签内容（满宽卡片区） ----
	var mid := MarginContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("margin_left", 28)
	mid.add_theme_constant_override("margin_right", 28)
	mid.add_theme_constant_override("margin_top", 16)
	mid.add_theme_constant_override("margin_bottom", 10)
	box.add_child(mid)
	var holder := VBoxContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(holder)
	_pages.clear()
	for i in TAB_TITLES.size():
		var pg := VBoxContainer.new()
		pg.add_theme_constant_override("separation", 10)
		pg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pg.visible = false
		holder.add_child(pg)
		_pages.append(pg)

	# ---- 底栏：战绩速览 + 靶场入口 ----
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _bar_style(false))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	bottom.add_child(bh)
	box.add_child(bottom)
	_record_label = _mk_label("", 13, _dim(0.62))
	_record_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(_record_label)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp2)
	# 靶场入口（与出发 CTA 分流）：绿色=安全免费，文案自曝「练习·不耗弹药」——
	# 用户反馈「出发实战和靶场分不清」，入口语义在两处各自点破
	var rb := _mk_btn("G · 练习靶场 · 不耗弹药", 15)
	_style_btn(rb, false, COL_OK, 16)
	rb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rb.pressed.connect(_fire_range)
	bh.add_child(rb)

	# ---- 底部提示条 ----
	_hint_label = _mk_label("", 16, COL_ACCENT)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.offset_top = -92
	_hint_label.offset_bottom = -64
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


## 行点击统一入口（鼠标）：当页枪行点击=选中+直接装备（等价 _on_equip_pressed：
## 已拥有装入聚焦槽 · 未拥有沿既有链只指路不扣款）；他页行先翻页再选中不自动装备
## （防跨页误触装错枪）；交易行行点击只选中不成交（防误购，见 _on_market_row_input）；
## 槽位卡片（page=-1）例外：再点已选卡=设为装入目标（与回车等价）。
## 参数序：gui_input 信号实参在前，bind 实参在后（同 city_editor._on_field_changed 约定）
func _on_deploy_row_input(event: InputEvent, page: int, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if page < 0:
				if _cur0 == idx:
					_confirm_deploy()          # 槽位卡片：再点已选卡=设装入目标
				else:
					_deploy_select(-1, idx)
			elif page != _deploy_page:
				_deploy_select(page, idx)      # 点他页行：先翻到该页，光标落该行（不自动装备）
			else:
				_on_equip_pressed(page, idx)   # 当页枪行：点击=选中+直接装备（既有「装备」钮链）


## 出发页选中某行（点击行 / 点「已装备」灰钮兜底）：翻到所在页、光标落行
func _deploy_select(page: int, idx: int) -> void:
	if page >= 0:
		_deploy_page = page
	_cur0 = idx
	_refresh_all()


## 行内「装备」钮：先选中该行，再沿既有确认链 _confirm_deploy 收敛
## （已拥有直接装入聚焦槽 · 未拥有提示去交易行），不另起一套逻辑
func _on_equip_pressed(page: int, idx: int) -> void:
	_deploy_select(page, idx)
	_confirm_deploy()


## 改枪台行点击（鼠标）：左列点枪=选中+装入聚焦槽（未拥有沿既有链指路，不扣款）·
## 右列点镜=选中+直接换装（机瞄=卸下 · 未拥有指路 · 狙击自带镜守卫照拦——
## 全部沿 _bench_confirm 既有链收敛，不自动跳页）。交易行同口径例外不适用此页
func _on_bench_row_input(event: InputEvent, col: int, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if col == 1:
				_on_bench_equip_pressed(idx)   # 既有链：先选中该行再确认（守卫/指路同收敛）
			else:
				_bench_col = 0                 # 左列选中该枪，再沿出发页「装备」链装聚焦槽
				_gun_idx = idx
				_equip_gun_global(idx)


## 全局枪表下标 → 出发页（page, idx）坐标后走 _on_equip_pressed 既有链：
## 已拥有装入聚焦槽、未拥有只指路不扣款——改枪台左列点击与出发页「装备」钮一处收敛，
## 不另起第二套装枪逻辑（附带把出发页光标带到该枪：回出发页所见=刚装的枪，语义连续）
func _equip_gun_global(gi: int) -> void:
	_on_equip_pressed(floori(float(gi) / float(DEPLOY_PAGE)), 2 + posmod(gi, DEPLOY_PAGE))


## 改枪台选中右列某行（点「已装」灰钮兜底）
func _bench_select(idx: int) -> void:
	_bench_col = 1
	_scope_idx = idx
	_refresh_all()


## 改枪台行内「换装/卸下」钮：先选中该行，再沿既有确认链 _bench_confirm 收敛
## （已拥有直接装 · 机瞄=卸下 · 未拥有提示去交易行），不另起一套逻辑
func _on_bench_equip_pressed(idx: int) -> void:
	_bench_select(idx)
	_bench_confirm()


# ================= 刷新 =================

func _refresh_all() -> void:
	if _root == null or _stash == null:
		return
	_thumb_wait.clear()   # 旧页面的图位随页面一起释放
	# 常驻 3D 预览先摘下（页面子树整体重建会把它一起释放）
	if _pv_box != null and _pv_box.get_parent() != null:
		_pv_box.get_parent().remove_child(_pv_box)
	# 3D 机库：只在「大厅可见 + 出发页」亮出（改枪台/交易行整页 UI 盖着它，
	# 对局里大厅整体隐藏——盖住/藏住的视口一帧不多画=性能红线）
	if _scene != null:
		_scene.set_active(lobby_visible and _tab == 0)
		_scene.sync_gear()   # 换装/换枪当场换手持枪（键未变零开销）
	# 出发页半透明透出机库主画面，改枪台/交易行近实心保卡片可读
	var dim_bg: bool = _tab != 0
	if _bg_rect != null:
		_bg_rect.color.a = 0.94 if dim_bg else 0.42
	if _glow_rect != null:
		_glow_rect.modulate.a = 1.0 if dim_bg else 0.45
	_render_top()
	for i in _pages.size():
		var pg := _pages[i] as VBoxContainer
		pg.visible = i == _tab
		_clear_children(pg)
		if i == _tab:
			match i:
				0: _render_deploy(pg)
				1: _render_bench(pg)
				2: _render_market(pg)   # ④ 仓库·战利品条并入 market 末尾（原仓库页已除）
	for i in _tab_btns.size():
		var b := _tab_btns[i] as Button
		var act: bool = i == _tab
		_style_btn(b, act, COL_ACCENT if act else _dim(0.4), 20)


func _render_top() -> void:
	var st: Dictionary = _stash.stats
	var raids := maxi(0, int(st.get("raids", 0)))
	_record_label.text = "出击 %d · 撤离 %d · 阵亡 %d · 击杀 %d · 合同 %d" % [
		raids, maxi(0, int(st.get("extracts", 0))),
		maxi(0, int(st.get("deaths", 0))), maxi(0, int(st.get("kills", 0))),
		maxi(0, int(st.get("contracts", 0)))]
	if raids > 0:   # 门槛 C 两个数：撤离率 40–60%、平均局时 12–20 分钟
		var avg := int(st.get("time_total", 0)) / raids
		_record_label.text += " · 撤离率 %d%% · 平均局时 %d:%02d" % [
			int(round(100.0 * float(st.get("extracts", 0)) / float(raids))), avg / 60, avg % 60]
	var can: bool = _stash.can_check_in()
	_daily_btn.text = ("C · 每日签到 +₵%s" % _fmt(HDData.DAILY_REWARD)) if can else "今日已签到"
	_style_btn(_daily_btn, can, COL_ACCENT if can else _dim(0.35))
	if not can:
		_daily_btn.add_theme_color_override("font_color", _dim(0.45))
	_cash_label.text = "₵ " + _fmt(maxi(0, _stash.cash))


# ================= 出发页 =================

## 候选枪总页数（15 枪 / 每页 DEPLOY_PAGE = 3 页）
func _deploy_pages() -> int:
	return int(ceil(float(Guns.GUNS.size()) / float(DEPLOY_PAGE)))


## 当前页候选枪行数（末页不满页取余数）
func _deploy_rows() -> int:
	return mini(DEPLOY_PAGE, Guns.GUNS.size() - _deploy_page * DEPLOY_PAGE)

func _render_deploy(pg: VBoxContainer) -> void:
	_deploy_page = clampi(_deploy_page, 0, _deploy_pages() - 1)
	var rows := _deploy_rows()
	# 光标域：展开态 = 2 槽位 + 当页枪行 + 出发钮（键鼠链与收拢前一致）；
	# 收起态 = 只剩出发钮（posmod 归 0），方向键不游走、回车即出发
	var n := (3 + rows) if _prep_open else 1
	_cur0 = posmod(_cur0, n)

	# —— 三角洲式 3D 版：主画面让给 3D 干员；战备内容收进面板（点「战备」才展开）
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pg.add_child(cols)

	# —— 战备面板（展开态）：本局装备槽卡 + 换枪条 + 速览，占主画面 ——
	if _prep_open:
		cols.add_child(_prep_panel(rows))

	# —— 收起态左下：合同卡（每日 3 张，出发前看目标）+ 仓库/交易行面板组 ——
	if not _prep_open:
		var left := _col(cols, 340)
		var lspace := Control.new()
		lspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(lspace)
		left.add_child(_contracts_card())
		left.add_child(_dock_panel())
		# —— 中：整栏留给 3D 干员 ——
		var midc := VBoxContainer.new()
		midc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(midc)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		midc.add_child(spacer)

	# —— 右：出发（押上 / 保险 / 出发 CTA / 战绩）——
	var right := _col(cols, 316)
	right.add_child(_sec_head("出发", ""))
	var risk_v: int = _stash.carried_value(_stash.loadout)
	var rc := _card(false, Color(COL_LOW.r, COL_LOW.g, COL_LOW.b, 0.45))
	var rv := _card_vbox(rc, 2)
	rv.add_child(_mk_label("本次押上（阵亡/放弃即丢）", 12, _dim(0.6)))
	rv.add_child(_mk_label("₵ " + _fmt(risk_v), 26, COL_LOW))
	var rnote := _mk_label("主副武器 · 瞄具消音器 · 备弹", 11, _dim(0.55))
	rv.add_child(rnote)
	right.add_child(rc)
	right.add_child(_insure_card(risk_v))
	# 天气变体循环钮（阶段 C）：V 同链；夜/雨/雾在局内有视距/掩声/战利品差异
	var vb := _mk_btn("天气：%s ▸" % variant_name(), 15)
	_style_btn(vb, false, COL_ACCENT if _variant_idx != 0 else _dim(0.6), 10)
	vb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	vb.pressed.connect(_cycle_variant)
	right.add_child(vb)
	# 出发钮（实战主 CTA：措辞点明「实战行动」+ 红橙配色与靶场绿色入口分流）
	var di := (2 + rows) if _prep_open else 0
	var dsel := _cur0 == di
	var btn := _mk_btn("出发 · 实战行动", 22)
	btn.custom_minimum_size = Vector2(0, 62)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_btn(btn, true, COL_LOW if dsel else Color(COL_LOW.r, COL_LOW.g, COL_LOW.b, 0.75), 20)
	if dsel:
		var hsb: StyleBoxFlat = btn.get_theme_stylebox("normal").duplicate()
		hsb.bg_color = Color(0.38, 0.14, 0.06, 0.95)
		hsb.set_border_width_all(3)
		btn.add_theme_stylebox_override("normal", hsb)
	btn.pressed.connect(_fire_deploy)
	right.add_child(btn)
	var dnote := _mk_label("25 分钟内撤出 · 实战消耗库存极致备弹", 11, _dim(0.55))
	dnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(dnote)
	right.add_child(_records_card())

	# —— 右下角「战备」小贴图（用户定案：点进去才能战备战）——
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_END
	pg.add_child(trow)
	trow.add_child(_prep_tile())

	var hint := _mk_label("鼠标：点右下角「战备」整备装备 · 点卡片装入 · ◀▶ 翻页   键盘：TAB 战备 · 回车 确认/出发 · I 投保 · V 天气 · 1/2/3 切页签 · G 靶场",
			13, _dim(0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pg.add_child(hint)


## 战备面板（点右下角「战备」贴图 / TAB 展开）：左列本局装备槽卡 + 右侧换枪条
## + 光标所指速览——内容与收拢前左列/中栏一致，只是收进了面板（状态机零改动）
func _prep_panel(rows: int) -> PanelContainer:
	var panel := _card(true, COL_ACCENT.darkened(0.4))
	panel.name = "prep_panel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pv := _card_vbox(panel, 6)
	# 头行：标题 + ✕ 收起（与贴图/TAB 同链）
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(head)
	head.add_child(_mk_label("战备", 24, COL_ACCENT))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hsp)
	var close := _mk_btn("✕ 收起（TAB）", 13)
	_style_btn(close, false, _dim(0.55), 8)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(func(): _toggle_prep(false))
	head.add_child(close)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(body)
	# 左：本局装备（主/副武器槽卡；聚焦槽 = 装入目标）
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(_sec_head("本局装备", "点卡片选装入槽"))
	for i in 2:
		left.add_child(_slot_card(i))
	# 右：选择武器（◀▶ 翻页 + 换枪条 + 光标所指速览）
	var wc := VBoxContainer.new()
	wc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wc.add_theme_constant_override("separation", 8)
	body.add_child(wc)
	var guns: Array = Guns.GUNS
	var owned_n := 0
	for g0 in guns:
		if _stash.guns_owned.has(str(g0["id"])):
			owned_n += 1
	var mh := _sec_head("选择武器", "")
	var pprev := _mk_btn("◀", 15)
	_style_btn(pprev, false, _dim(0.6), 10)
	pprev.pressed.connect(_deploy_flip.bind(-1))
	pprev.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mh.add_child(pprev)
	var pl := _mk_label("第 %d/%d 页 · 已拥有 %d/%d · 点卡装入聚焦槽" % [
			_deploy_page + 1, _deploy_pages(), owned_n, guns.size()], 13, _dim(0.7))
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh.add_child(pl)
	var pnext := _mk_btn("▶", 15)
	_style_btn(pnext, false, _dim(0.6), 10)
	pnext.pressed.connect(_deploy_flip.bind(1))
	pnext.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mh.add_child(pnext)
	wc.add_child(mh)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	wc.add_child(strip)
	var first: int = _deploy_page * DEPLOY_PAGE
	for r in rows:
		strip.add_child(_gun_card_strip(first + r, 2 + r))
	wc.add_child(_gun_brief(_deploy_sel_id()))
	return panel


## 右下角「战备」小贴图（用户定案「点进去才能战备战」）：收起态=入口
## （写当前主武器），展开态=收起钮；TAB 同链
func _prep_tile() -> PanelContainer:
	var pid := str(_stash.loadout.get("primary", ""))
	var pname := "空槽"
	if pid != "":
		pname = String(Guns.gun_by_id(pid).get("name", pid))
	var tile := _card(false, COL_ACCENT)
	tile.name = "prep_tile"
	tile.custom_minimum_size = Vector2(212, 84)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.gui_input.connect(_on_prep_tile_input)
	var tv := _card_vbox(tile, 2)
	var th := HBoxContainer.new()
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(th)
	th.add_child(_mk_label("战备", 20, COL_ACCENT))
	var tsp := Control.new()
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(tsp)
	th.add_child(_mk_label("TAB", 12, _dim(0.5)))
	var sub := "收起面板" if _prep_open else "%s · 点开整备" % pname
	tv.add_child(_mk_label(sub, 12, _dim(0.65)))
	return tile


## 「战备」贴图点击：开合战备面板（与 TAB / 面板 ✕ 同链）
func _on_prep_tile_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_toggle_prep(not _prep_open)


## 出发页翻页（◀/▶ 钮）：光标回到当页第一把枪
func _deploy_flip(d: int) -> void:
	_deploy_page = posmod(_deploy_page + d, _deploy_pages())
	_cur0 = 2
	_refresh_all()


## 主/副武器槽卡（聚焦槽 = 装入目标）：大字枪名 + 瞄具/消音器 + 耐久条 + 备弹
func _slot_card(i: int) -> PanelContainer:
	var key: String = ["primary", "secondary"][i]
	var gid := str(_stash.loadout.get(key, ""))
	var sel := _cur0 == i
	var focus_here := _slot_focus == key
	var card := _card(sel, COL_ACCENT if sel else (COL_OK.darkened(0.35) if focus_here else _dim(0.2)))
	card.custom_minimum_size = Vector2(0, 150)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.gui_input.connect(_on_deploy_row_input.bind(-1, i))
	var vb := _card_vbox(card, 4)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_mk_label(["主武器 · 1", "副武器 · 2"][i], 13, COL_OK))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hsp)
	if focus_here:
		head.add_child(_chip("装入此槽", COL_OK))
	vb.add_child(head)
	if gid == "":
		vb.add_child(_mk_label("空槽", 24, _dim(0.45)))
		var e := _mk_label("阵亡丢枪后留空 · 可单枪出发，选中后从中间装入", 12, _dim(0.55))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(e)
		return card
	var g := Guns.gun_by_id(gid)
	vb.add_child(_mk_label(String(g.get("name", gid)), 24, COL_ACCENT))
	vb.add_child(_gun_thumb(gid, 72))
	var att: Array = []
	var sid := str(_stash.scope_fit.get(gid, "iron"))
	if g.has("builtin_scope"):
		att.append("自带 %.0f× 镜" % float(g["builtin_scope"].get("zoom", 1.0)))
	elif sid != "iron":
		att.append(String(Guns.scope_by_id(sid).get("name", sid)))
	else:
		att.append("机瞄")
	if _stash.suppressed(gid):
		att.append("消音器")
	vb.add_child(_mk_label(" · ".join(PackedStringArray(att)), 14, COL_TEXT))
	vb.add_child(_dur_row(gid))
	vb.add_child(_mk_label("%s %d 发" % [HDData.AMMO_NAME, _stash.ammo_of(gid)], 13, HDData.AMMO_COLOR))
	return card


## 出发页候选枪卡（3D 版底部换枪条）：横排窄卡 = 枪名 / 实物图 / 状态 +
## 「装备」钮；点卡=选中+直接装备（既有链，同 _on_equip_pressed）。
## 竖排大卡的伤害/射速数据条移到左列/速览（数据不再失传，条卡只管快选）
func _gun_card_strip(gi: int, cur_idx: int) -> PanelContainer:
	var g: Dictionary = Guns.GUNS[gi]
	var id2 := str(g["id"])
	var owned: bool = _stash.guns_owned.has(id2)
	var sel := _cur0 == cur_idx
	var card := _card(sel, COL_ACCENT if sel else _dim(0.2))
	card.custom_minimum_size = Vector2(0, 108)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.gui_input.connect(_on_deploy_row_input.bind(_deploy_page, cur_idx))
	var vb := _card_vbox(card, 2)
	vb.add_child(_mk_label(String(g.get("name", id2)), 13,
			COL_TEXT if owned else _dim(0.5)))
	var thumb := _gun_thumb(id2, 40, not owned)
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(thumb)
	var bot := HBoxContainer.new()
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(bot)
	var st := ""
	var stc := COL_OK
	if str(_stash.loadout.get("primary", "")) == id2:
		st = "主武器"
	elif str(_stash.loadout.get("secondary", "")) == id2:
		st = "副武器"
	elif owned:
		st = "已拥有"
	else:
		st = "₵ %s" % _fmt(_to_int(g.get("price", 0)))
		stc = _dim(0.45)
	var stl := _mk_label(st, 11, stc)
	stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bot.add_child(stl)
	if owned:
		bot.add_child(_mk_equip_btn(id2, _deploy_page, cur_idx))
	return card


## 左下角面板组（用户点名停靠）：③交易行 / ④仓库 入口钮 + 资产·安全箱信息条
## + 本局情报 + 最近入库（含一键变卖）。全部动作收敛既有链：入口钮=翻交易行页
## （仓库直落④段，同 _goto_market_scope 先例）、变卖=sell_all——不另起经济逻辑
func _dock_panel() -> PanelContainer:
	var card := _card(false, _dim(0.22))
	var vb := _card_vbox(card, 5)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	var mk := _mk_btn("③ 交易行 · 按 3", 14)
	_style_btn(mk, false, COL_ACCENT, 10)
	mk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mk.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mk.pressed.connect(func(): set_tab(2))
	row.add_child(mk)
	var wk := _mk_btn("④ 仓库 · %d 件" % _stash.items.size(), 14)
	_style_btn(wk, false, COL_OK, 10)
	wk.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wk.pressed.connect(_goto_market_warehouse)
	row.add_child(wk)
	# 信息条（原安全箱卡两行并入）：资产与安全箱一眼可读（ellipsis 防大额撑栏）
	var info := _mk_label("总资产 ₵%s · 安全箱 %d 格（局内 Z 入箱）" % [
			_fmt(_dock_assets()), _stash.secure_slots], 12, COL_OK)
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(info)
	# 本局情报（原情报卡整卡并入面板组，出发前就知道这局会发生什么）
	for ln in [
		["撤离", "主撤离常开 · 大坝 12:00 后 · 付费/拉闸随机"],
		["10:00", "空投（红烟标记）· 守军增援赶来"],
		["对手", "搜刮者 2 队 × 3 人 · 首领 ×2"],
	]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := _mk_label(str(ln[0]), 11, COL_ACCENT)
		k.custom_minimum_size = Vector2(36, 0)
		hb.add_child(k)
		var v := _mk_label(str(ln[1]), 11, _dim(0.6))
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(v)
		vb.add_child(hb)
	# 最近入库条：紧凑文本行 ×2 + 标题行「一键变卖」小钮（既有链）。
	# 首版复用 _loot_cell 格子——其 min 宽 150×2+变卖列 ≈458px 撑爆左栏 340px，
	# 三栏整体右移把出发栏推出屏幕（判图第 2/3 张右栏被裁的根因）；改纯文本行
	# （ellipsis 收宽），全部元素 min 宽收敛回栏内
	var items: Array = _stash.items
	if items.is_empty():
		var empty := _mk_label("仓库空空如也 —— 出发搜刮，活着带回来", 12, _dim(0.5))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(empty)
	else:
		var sum := 0
		for it0 in items:   # it0：内层最近入库行还要用 var it，同名会被解析器拒
			if typeof(it0) == TYPE_DICTIONARY:
				sum += _to_int(it0.get("value", 0))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(head)
		var hl := _mk_label("最近入库 · 共 %d 件 ₵%s" % [items.size(), _fmt(sum)],
				11, _dim(0.6))
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hl)
		var sell := _mk_btn("一键变卖全部", 11)
		_style_btn(sell, true, COL_ACCENT, 8)
		sell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		sell.pressed.connect(_sell_all)
		head.add_child(sell)
		for i in mini(2, items.size()):
			var it: Dictionary = items[items.size() - 1 - i]
			var rcol: Color = HDData.RARITY[clampi(_to_int(it.get("rarity", 0)), 0, 6)]["color"]
			var lrow := HBoxContainer.new()   # lrow：函数头部已有按钮 row，同名会被解析器拒
			lrow.add_theme_constant_override("separation", 6)
			lrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(lrow)
			lrow.add_child(_mk_label(HDData.norm_icon(String(it.get("icon", ""))), 12, rcol))
			var nm := _mk_label(String(it.get("name", "战利品")), 11, rcol)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lrow.add_child(nm)
			lrow.add_child(_mk_label("₵ " + _fmt(_to_int(it.get("value", 0))), 11, COL_OK))
	return card


## 每日合同卡（阶段 A）：今日 3 张进度一目了然——标题 / 进度 / 奖金 / 状态。
## 惰性发放：渲染时 daily_contracts() 首读即按今日种子补发（老档兼容）
func _contracts_card() -> PanelContainer:
	var card := _card(false, _dim(0.22))
	var vb := _card_vbox(card, 3)
	vb.add_child(_mk_label("今日合同 · 完成撤离领赏", 14, Color(0.95, 0.85, 0.4)))
	for ct in _stash.daily_contracts():
		var defc: Dictionary = _stash.contract_def(str(ct["id"]))
		if defc.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(row)
		var goal: int = _to_int(defc["n"])
		var prog: int = _to_int(ct.get("prog", 0))
		var unit := "₵" if str(defc["type"]) == "value" else ""
		var state := "✓ 已领取" if bool(ct.get("paid", false)) else \
				("✓ 完成 · 待撤离" if bool(ct.get("done", false)) else "%d/%d%s" % [prog, goal, unit])
		var t := _mk_label(String(defc["title"]), 12, COL_TEXT if not bool(ct.get("done", false)) else COL_OK)
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(_mk_label("₵%s" % _fmt(_to_int(defc["reward"])), 11, COL_OK))
		row.add_child(_mk_label(state, 11, _dim(0.65)))
		var d := _mk_label(String(defc["desc"]), 10, _dim(0.5))
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vb.add_child(d)
	return card


## 左下角面板组资产数（与交易行④段同口径：仓库物价值 + 现金）
func _dock_assets() -> int:
	var sum := 0
	for it in _stash.items:
		if typeof(it) == TYPE_DICTIONARY:
			sum += _to_int(it.get("value", 0))
	return sum + maxi(0, _stash.cash)


## ④仓库入口钮：翻交易行页并直落④段（既有 _market_sec 光标域，零新链路）
func _goto_market_warehouse() -> void:
	_market_sec = 3
	set_tab(2)


## 武器速览数据条（出发页右栏 / 改枪台选中枪）：伤害 / 射速 / 弹匣 / 射程。
## 右栏 300 宽复用：枪名/弹药行防撑破（ellipsis+autowrap，长名长行折行不撑栏）
func _gun_brief(gid: String) -> PanelContainer:
	var g := Guns.gun_by_id(gid)
	var card := _card(false, _dim(0.16))
	var vb := _card_vbox(card, 6)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gname := _mk_label(String(g.get("name", gid)), 17, COL_ACCENT)
	gname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(gname)
	var owned: bool = _stash.guns_owned.has(gid)
	head.add_child(_mk_label("已拥有" if owned else "₵ " + _fmt(_to_int(g.get("price", 0))),
			14, COL_OK if owned else _dim(0.5)))
	vb.add_child(head)
	var mx := _gun_maxima()
	var cd := float(g.get("cd", 0.0))
	var rate := (1.0 / cd) if cd > 0.0 else 0.0
	var dmg := float(g.get("dmg", 0.0)) * float(g.get("pellets", 1))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(grid)
	for row in [["伤害", dmg / mx["dmg"], "%.0f" % dmg], ["射速", rate / mx["rate"], "%.1f/s" % rate],
			["弹匣", float(g.get("mag", 0)) / mx["mag"], str(g.get("mag", "--"))],
			["射程", float(g.get("range", 0)) / mx["range"], "%sm" % str(g.get("range", "--"))]]:
		grid.add_child(_stat_row(str(row[0]), float(row[1]), str(row[2])))
	var ammo_line := _mk_label("单价 ₵%d/发 · %s 余 %d 发 · 按 3 买弹" % [
			_to_int(HDData.AMMO_PRICE.get(gid, 0)), HDData.AMMO_NAME, _stash.ammo_of(gid)],
			12, HDData.AMMO_COLOR)
	ammo_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 右栏 300 宽防撑破
	ammo_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(ammo_line)
	return card


## 全枪册各项最大值（数据条归一化用）
func _gun_maxima() -> Dictionary:
	var mx := {"dmg": 1.0, "rate": 1.0, "mag": 1.0, "range": 1.0}
	for g in Guns.GUNS:
		var cd := float(g.get("cd", 0.0))
		mx["dmg"] = maxf(mx["dmg"], float(g.get("dmg", 0.0)) * float(g.get("pellets", 1)))
		mx["rate"] = maxf(mx["rate"], (1.0 / cd) if cd > 0.0 else 0.0)
		mx["mag"] = maxf(mx["mag"], float(g.get("mag", 0)))
		mx["range"] = maxf(mx["range"], float(g.get("range", 0)))
	return mx


func _stat_row(name: String, frac: float, val: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := _mk_label(name, 13, _dim(0.6))
	nl.custom_minimum_size = Vector2(34, 0)
	hb.add_child(nl)
	var bar := Bar.new()
	bar.frac = frac
	bar.col = COL_ACCENT
	bar.custom_minimum_size = Vector2(22, 8)   # 只给下限，随卡宽伸展；22=右栏 300 宽双列放得下
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	var vl := _mk_label(val, 13, COL_TEXT)
	vl.custom_minimum_size = Vector2(54, 0)   # 54：单位完整（m/s）不贴卡缘被读成「被裁」
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(vl)
	return hb


## 耐久行：数据条（≥60 绿 / 25–60 黄 / <25 红）+ 百分比
func _dur_row(gid: String) -> HBoxContainer:
	var d: float = _stash.dur_of(gid)
	var col := COL_OK if d >= HDData.DUR_WORN else (COL_ACCENT if d >= HDData.JAM_DUR else COL_LOW)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_mk_label("耐久", 13, _dim(0.6)))
	var bar := Bar.new()
	bar.frac = d / 100.0
	bar.col = col
	bar.custom_minimum_size = Vector2(40, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	hb.add_child(_mk_label("%d%%" % int(d), 13, col))
	return hb


## 保险卡（点击/按 I 勾选）：付押上价值 30%，阵亡每件 50% 概率退回
func _insure_card(risk_v: int) -> PanelContainer:
	var ip: int = _stash.insurance_price(_stash.loadout)
	var affordable: bool = ip > 0 and _stash.cash >= ip
	if not affordable:
		_insure = false
	var card := _card(_insure, COL_OK if _insure else _dim(0.22))
	card.gui_input.connect(_on_insure_input)
	var vb := _card_vbox(card, 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_mk_label("☑" if _insure else "☐", 22, COL_OK if _insure else _dim(0.55)))
	var tl := _mk_label("投保 ₵%s" % _fmt(ip) if ip > 0 else "无需投保", 18,
			COL_OK if _insure else (COL_TEXT if affordable else _dim(0.45)))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tl)
	row.add_child(_chip("按 I", _dim(0.6)))
	vb.add_child(row)
	var sub := "付押上价值的 30% · 阵亡时每件装备 50% 概率退回"
	if risk_v <= 0:
		sub = "只带侦察手枪出发：没有可保的装备"
	elif not affordable:
		sub = "现金不足（需 ₵%s）· 阵亡时每件 50%% 概率退回" % _fmt(ip)
	var sl := _mk_label(sub, 12, _dim(0.55))
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sl)
	return card


func _on_insure_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_toggle_insure()


func _toggle_insure() -> void:
	var ip: int = _stash.insurance_price(_stash.loadout)
	if ip <= 0:
		show_hint("只带侦察手枪出发：没有可保的装备")
		_insure = false
	elif not _insure and _stash.cash < ip:
		show_hint("现金不足：投保需 ₵%s，现有 ₵%s" % [_fmt(ip), _fmt(maxi(0, _stash.cash))])
	else:
		_insure = not _insure
		show_hint(("已投保 · 出发时扣 ₵%s · 阵亡每件 50%% 概率退回" % _fmt(ip)) if _insure
				else "已取消投保")
	_refresh_all()


## 战绩卡（衡量指标：撤离率 40–60%、平均局时 12–20 分钟）
func _records_card() -> PanelContainer:
	var st: Dictionary = _stash.stats
	var raids := maxi(0, int(st.get("raids", 0)))
	var ex := maxi(0, int(st.get("extracts", 0)))
	var avg := int(st.get("time_total", 0)) / raids if raids > 0 else 0
	var card := _card(false, _dim(0.16))
	var vb := _card_vbox(card, 6)
	vb.add_child(_mk_label("战绩", 14, COL_OK))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(grid)
	var cells := [
		["出击", str(raids)], ["撤离", str(ex)], ["阵亡", str(maxi(0, int(st.get("deaths", 0))))],
		["击杀", str(maxi(0, int(st.get("kills", 0))))],
		["撤离率", ("%d%%" % int(round(100.0 * float(ex) / float(raids)))) if raids > 0 else "--"],
		["平均局时", ("%d:%02d" % [avg / 60, avg % 60]) if raids > 0 else "--"],
	]
	for c in cells:
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", -2)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(_mk_label(str(c[1]), 26, COL_TEXT))
		cv.add_child(_mk_label(str(c[0]), 12, _dim(0.5)))
		grid.add_child(cv)
	return card


## 出发页行内「装备」键两态（只发给已拥有枪）：已在主/副任一槽=「已装备」置灰
## （主副不可同枪，点击仅选中该行）· 未装=「装备」装入聚焦槽（_slot_focus）。
## 未拥有枪不出钮——购买统一走交易行（按 3 进），动作收敛到 _confirm_deploy 既有链
func _mk_equip_btn(gid: String, page: int, idx: int) -> Button:
	var b := _mk_btn("装备", 12)
	var in_loadout: bool = str(_stash.loadout.get("primary", "")) == gid \
			or str(_stash.loadout.get("secondary", "")) == gid
	if in_loadout:
		b.text = "已装备"
		_style_btn(b, false, _dim(0.35), 8)   # hpad 8：换枪条窄卡里给中栏 min 让位
		b.pressed.connect(_deploy_select.bind(page, idx))
	else:
		_style_btn(b, true, COL_ACCENT, 8)
		b.pressed.connect(_on_equip_pressed.bind(page, idx))
	return b


## 出发页当前选中枪 id（速览与购弹共用）：槽位=loadout 对应枪 · 枪行=该行枪
## （出发钮位回退主武器——越界会翻到他页枪）
func _deploy_sel_id() -> String:
	var guns: Array = Guns.GUNS
	var rows := _deploy_rows()
	var sel_id := str(_stash.loadout.get("primary", "rifle"))
	if _cur0 == 1 and str(_stash.loadout.get("secondary", "")) != "":
		sel_id = str(_stash.loadout.get("secondary", "pistol"))
	elif _cur0 >= 2 and _cur0 < 2 + rows:
		var gidx: int = _deploy_page * DEPLOY_PAGE + (_cur0 - 2)
		if gidx < guns.size():
			sel_id = str(guns[gidx]["id"])
	return sel_id


## 出发页确认（键盘回车与鼠标再点已选行同收敛于此）：
## 收起态=直接出发（光标域只有出发钮）· 展开态槽=设装入目标 · 枪行=已拥有装入聚焦槽
## （未拥有提示去交易行，不扣款）· 出发钮=出发
func _confirm_deploy() -> void:
	# 收起态「回车即出发」只属于出发页本页（键盘回车/再点已选钮）；改枪台左列
	# 点击也汇入本函数（_equip_gun_global 链）——那边要的是枪行语义（未拥有指路/
	# 已拥有装入聚焦槽），不得开局（战备收拢改造曾把该链劫持成直接开局，回归修复）
	if not _prep_open and _tab == 0:
		_fire_deploy()
		return
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
			# 购买入口已统一迁到交易行：出发页只装已有枪，未拥有不扣款只指路（报键位）
			show_hint("「%s」未拥有 —— 按 3 进交易行购买后再来装备" % \
					String(Guns.gun_by_id(gid).get("name", gid)))
			return
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
	if p == "" or p == s:
		show_hint("主副武器不可相同")
		return
	if not _stash.guns_owned.has(p) or (s != "" and not _stash.guns_owned.has(s)):
		_stash.repair_loadout()      # 丢失的枪不能再带进局
		_refresh_all()
		show_hint("出发配置里有已丢失的枪械，已调整 —— 再确认一次")
		return
	var ins := _insure and _stash.insurance_price(_stash.loadout) > 0 \
			and _stash.cash >= _stash.insurance_price(_stash.loadout)
	hide_lobby()
	deploy_requested.emit({"primary": p, "secondary": s, "insured": ins,
			"variant": variant_key()})


## 出发 payload 组装（阶段 C 抽出：测试不发射信号也能取变体字段）
func _deploy_payload(p: String, s: String, ins: bool) -> Dictionary:
	return {"primary": p, "secondary": s, "insured": ins, "variant": variant_key()}


## 天气变体（阶段 C）：键序循环 + 名称；夜/雨/雾局敌人视距/枪声/战利品有差异
func variant_key() -> String:
	var keys := HDData.RAID_VARIANTS.keys()
	return str(keys[_variant_idx % keys.size()])


func variant_name() -> String:
	var def: Dictionary = HDData.RAID_VARIANTS.get(variant_key(), {})
	return str(def.get("name", "晴朗"))


## V 键/按钮同链：循环切换天气（第 0 位=晴朗缺省）
func _cycle_variant() -> void:
	_variant_idx = (_variant_idx + 1) % HDData.RAID_VARIANTS.size()
	_refresh_all()


func _fire_range() -> void:
	hide_lobby()
	range_requested.emit()


# ================= 仓库去向（原仓库页并入交易行④段） =================

## ④ 仓库·战利品条（由 _render_market 末尾调用）：段标题+紧凑战利品格+总资产/「一键变卖」钮。
## 紧凑格包进定高 ScrollContainer（两行窗口 ~100px）：仓库 deposit 逐件入库无封顶
## （hd_stash.deposit 不裁件，连打两局不卖即 24 件 > BACKPACK_MAX 12），件数超窗竖向
## 滚轮翻看、条高与件数解耦；「仓库 N/12 格」字样原样保留（超格不裁件是现状，不撒谎）
func _render_warehouse_strip(pg: VBoxContainer) -> void:
	var items: Array = _stash.items
	var ware := PanelContainer.new()
	ware.add_theme_stylebox_override("panel",
			_panel_style(_market_sec == 3, COL_ACCENT if _market_sec == 3 else _dim(0.22), 6))
	ware.gui_input.connect(_on_warehouse_input)   # ④段点击=切到仓库段（照③区面板同款）
	pg.add_child(ware)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 4)
	wv.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到面板卡片
	ware.add_child(wv)

	# 标题行：④ 徽章 + 资产/格数 + 变卖钮（回车与钮双入口，变卖链路零丢失）
	var whead := HBoxContainer.new()
	whead.add_theme_constant_override("separation", 12)
	whead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wv.add_child(whead)
	whead.add_child(_mk_sec_title(3, "④ 仓库·战利品"))
	var items_sum := 0
	for it in items:
		if typeof(it) == TYPE_DICTIONARY:
			items_sum += _to_int(it.get("value", 0))
	var wsp := Control.new()
	wsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	whead.add_child(wsp)
	whead.add_child(_mk_label("总资产 ₵%s（含现金） · 仓库 %d/%d 格" % [
			_fmt(items_sum + maxi(0, _stash.cash)), items.size(), HDData.BACKPACK_MAX],
			14, COL_ACCENT))
	# 安全箱扩容（2026-10 带入即风险：阵亡保留格数，2 → 4）
	var up_price: int = _stash.secure_up_price()
	var sbtn := _mk_btn(("U · 安全箱扩容 %d→%d 格 ₵%s" % [_stash.secure_slots,
			_stash.secure_slots + 1, _fmt(up_price)]) if up_price > 0 else
			"安全箱已满 %d 格" % _stash.secure_slots, 14)
	_style_btn(sbtn, up_price > 0, COL_OK if up_price > 0 else _dim(0.3), 14)
	sbtn.pressed.connect(_buy_secure)
	whead.add_child(sbtn)
	var sell := _mk_btn("Enter 一键变卖全部", 14)
	_style_btn(sell, not items.is_empty(), COL_ACCENT if not items.is_empty() else _dim(0.3), 14)
	sell.pressed.connect(_sell_all)
	whead.add_child(sell)

	if items.is_empty():
		var empty := _mk_label("仓库空空如也 —— 出发搜刮，活着带回来", 13, _dim(0.5))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wv.add_child(empty)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 100)   # 两行窗口定高（~44px 格 ×2 + 分隔）
		scroll.custom_maximum_size = Vector2(INF, 100)  # 定高硬顶：条高与件数解耦
		# （x 轴写 INF——custom_maximum_size 的 0 分量是「钳到 0」不是「不限宽」，实测宽会被掐成 0）
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		wv.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)
		for it in items:
			if typeof(it) == TYPE_DICTIONARY:
				var cell := _loot_cell(it)
				cell.gui_input.connect(_on_warehouse_input)   # 点格=切到④段
				grid.add_child(cell)


## ④ 仓库条点击（面板/格共用）：仅把光标切到仓库段（变卖走回车 /「Enter 一键变卖全部」钮）
func _on_warehouse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _market_sec != 3:
			_market_sec = 3
			_refresh_all()


## 品质色边框 + icon + 名称 + 价值 的一格（④段紧凑版 ~44px：单行 icon+名+价，6 列两行窗口）
func _loot_cell(it: Dictionary) -> PanelContainer:
	var rid := clampi(_to_int(it.get("rarity", 0)), 0, 6)
	var rar: Dictionary = HDData.RARITY[rid]
	var rcol: Color = rar["color"]
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(150, 46)
	var sb := _panel_style(false, rcol, 4)
	sb.bg_color = Color(0.05 + rcol.r * 0.1, 0.07 + rcol.g * 0.1, 0.06 + rcol.b * 0.1, 0.8)
	cell.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到格卡片（切④段）
	cell.add_child(hb)
	hb.add_child(_mk_label(HDData.norm_icon(String(it.get("icon", ""))), 16, rcol))
	var nm := _mk_label(String(it.get("name", "战利品")), 13, rcol)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(nm)
	hb.add_child(_mk_label("₵ " + _fmt(_to_int(it.get("value", 0))), 13, COL_OK))
	return cell


func _buy_secure() -> void:
	var price: int = _stash.secure_up_price()
	if price <= 0:
		show_hint("安全箱已扩到上限 %d 格" % _stash.secure_slots)
		return
	if _stash.buy_secure_upgrade():
		show_hint("安全箱扩容到 %d 格（-₵%s）· 阵亡时其中物品保留" % [_stash.secure_slots, _fmt(price)])
	else:
		show_hint("现金不足：安全箱扩容需 ₵%s" % _fmt(price))


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
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pg.add_child(cols)

	# 左列：枪械（↑↓ 选枪，滚动列表）；行尾 tag 显示真实装配状态——自带镜枪=自带 N×
	# （与局内 _scope_for/scope_zoom 的 builtin 优先语义一致）/已装 X 镜/机瞄
	var left := _col(cols, 300)
	left.add_child(_sec_head("枪械", "↑↓ 选枪"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 6)
	scroll.add_child(lv)
	var sel_card: Control = null
	for i in guns.size():
		var g: Dictionary = guns[i]
		var id2 := str(g["id"])
		var owned: bool = _stash.guns_owned.has(id2)
		var tag := "机瞄"
		if g.has("builtin_scope"):
			tag = "自带 %.0f×" % float(g["builtin_scope"].get("zoom", 1.0))
		elif str(_stash.scope_fit.get(id2, "iron")) != "iron":
			var sc := Guns.scope_by_id(str(_stash.scope_fit.get(id2, "")))
			if not sc.is_empty():
				tag = String(sc.get("name", "已装镜"))
		if _stash.suppressed(id2):
			tag += " · 消音"
		var sel := _bench_col == 0 and i == _gun_idx
		var row := _card(sel, COL_ACCENT if sel else (_dim(0.3) if i == _gun_idx else _dim(0.16)), 7)
		row.gui_input.connect(_on_bench_row_input.bind(0, i))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)
		hb.add_child(_gun_thumb(id2, 30, not owned, 70))
		var nl := _mk_label(String(g.get("name", id2)), 15,
				(COL_ACCENT if i == _gun_idx else COL_TEXT) if owned else _dim(0.42))
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(nl)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(sp)
		var tgl := _mk_label(tag if owned else "未拥有", 12, COL_OK if owned else _dim(0.4))
		tgl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(tgl)
		lv.add_child(row)
		if i == _gun_idx:
			sel_card = row
	if sel_card != null:
		scroll.ensure_control_visible.call_deferred(sel_card)

	# 中列：3D 枪械预览（拖动旋转）+ 数据条 + 维护（耐久维修 / 消音器）
	var midc := VBoxContainer.new()
	midc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	midc.add_theme_constant_override("separation", 10)
	cols.add_child(midc)
	var pv_card := _card(false, _dim(0.16), 6)
	pv_card.mouse_default_cursor_shape = Control.CURSOR_ARROW
	pv_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pvv := VBoxContainer.new()
	pvv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv_card.add_child(pvv)
	midc.add_child(pv_card)   # 先进树：预览枪模量包围盒/摆相机都在树内做
	var pvh := HBoxContainer.new()
	pvh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pvv.add_child(pvh)
	pvh.add_child(_mk_label(String(gun.get("name", gun_id)), 22, COL_ACCENT))
	var pvs := Control.new()
	pvs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pvs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pvh.add_child(pvs)
	pvh.add_child(_mk_label("拖动旋转", 12, _dim(0.45)))
	_ensure_preview()
	_pv_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pvv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pvv.add_child(_pv_box)
	_update_preview(gun_id)
	midc.add_child(_gun_brief(gun_id))
	var svc := HBoxContainer.new()
	svc.add_theme_constant_override("separation", 10)
	midc.add_child(svc)
	svc.add_child(_repair_card(gun_id))
	svc.add_child(_sup_card(gun_id))

	# 右列：瞄具（机瞄/五镜），现金常显在标题，钱不足一眼可见
	var right := _col(cols, 380)
	var is_builtin: bool = gun.has("builtin_scope")
	right.add_child(_sec_head("瞄具", "现金 ₵%s" % _fmt(maxi(0, _stash.cash))))
	if is_builtin:
		right.add_child(_mk_label("「%s」自带 %.0f× 原厂镜 · 不可改装" % [
				String(gun.get("name", gun_id)), float(gun["builtin_scope"].get("zoom", 1.0))],
				13, _dim(0.6)))
	for i in entries.size():
		var e: Dictionary = entries[i]
		var sid := str(e["id"])
		var sel2 := _bench_col == 1 and i == _scope_idx
		var row2 := _card(sel2, COL_ACCENT if sel2 else _dim(0.18), 7)
		row2.custom_minimum_size = Vector2(0, 58)
		row2.gui_input.connect(_on_bench_row_input.bind(1, i))
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 8)
		hb2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row2.add_child(hb2)
		hb2.add_child(_scope_thumb(sid, 40, 70))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb2.add_child(tv)
		var unowned_sc: bool = sid != "iron" and not _stash.owns_scope(sid)
		tv.add_child(_mk_label(String(e.get("name", sid)), 16, _dim(0.5) if unowned_sc else COL_TEXT))
		# 自带镜枪的机瞄行=原厂镜在位：默认文案「回车卸下」与守卫拦截矛盾，就地改写
		var desc_txt := String(e.get("desc", ""))
		if is_builtin and sid == "iron":
			desc_txt = "原厂镜在位（默认）"
		var desc := _mk_label(desc_txt, 12, _dim(0.55))
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		desc.custom_minimum_size = Vector2(150, 0)
		tv.add_child(desc)
		var tg := _mk_label(_scope_tag(gun_id, sid, e), 12, _scope_tag_col(gun_id, sid))
		tg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb2.add_child(tg)
		var act := _mk_bench_action(gun_id, e, i)
		act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb2.add_child(act)
		right.add_child(row2)
	right.add_child(_mk_label("已拥有瞄具 %d/%d · 单持：同镜装他枪自动卸下" % [
			_stash.scopes_owned.size(), Guns.SCOPES.size()], 12, _dim(0.5)))

	var hint := _mk_label("鼠标：点枪 / 点镜直接装备 · 拖动预览旋转   键盘：←→ 换列 · ↑↓ 选 · 回车 换装 · R 维修 · V 消音器",
			13, _dim(0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pg.add_child(hint)


## 维修卡：耐久条 + 「R · 维修 ₵N」（满耐久/未拥有置灰）
func _repair_card(gid: String) -> PanelContainer:
	var owned: bool = _stash.guns_owned.has(gid)
	var card := _card(false, _dim(0.16))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := _card_vbox(card, 6)
	vb.add_child(_mk_label("耐久 · 维修", 14, COL_OK))
	if not owned:
		vb.add_child(_mk_label("未拥有", 13, _dim(0.45)))
		return card
	vb.add_child(_dur_row(gid))
	var price: int = _stash.repair_price(gid)
	var b := _mk_btn(("R · 维修 ₵%s" % _fmt(price)) if price > 0 else "耐久已满", 14)
	_style_btn(b, price > 0, COL_ACCENT if price > 0 else _dim(0.3), 14)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_repair_sel)
	vb.add_child(b)
	vb.add_child(_mk_label("低于 60% 变散 · 低于 25% 会卡壳", 11, _dim(0.45)))
	return card


## 消音器卡：未买「V · 购买 ₵1,200」/ 已买「V · 拆下 / 装上」/ 霰弹枪不能装
func _sup_card(gid: String) -> PanelContainer:
	var owned: bool = _stash.guns_owned.has(gid)
	var on: bool = _stash.suppressed(gid)
	var card := _card(on, COL_OK if on else _dim(0.16))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := _card_vbox(card, 6)
	vb.add_child(_mk_label("消音器" + (" · 已装" if on else ""), 14, COL_OK))
	if not _stash.sup_allowed(gid):
		vb.add_child(_mk_label("该枪不能装消音器", 13, _dim(0.45)))
		return card
	if not owned:
		vb.add_child(_mk_label("先在交易行买枪", 13, _dim(0.45)))
		return card
	var bought: bool = _stash.sup_owned.has(gid)
	var b := _mk_btn("V · 拆下" if on else ("V · 装上" if bought else
			"V · 购买 ₵%s" % _fmt(HDData.SUP_PRICE)), 14)
	_style_btn(b, not on, COL_OK if on else COL_ACCENT, 14)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_sup_sel)
	vb.add_child(b)
	vb.add_child(_mk_label("枪声惊动 60→20 m · 伤害 ×0.92 · 随枪丢", 11, _dim(0.45)))
	return card


## 改枪台 R：维修当前选中枪
func _repair_sel() -> void:
	var gid := str(Guns.GUNS[posmod(_gun_idx, Guns.GUNS.size())]["id"])
	var name := String(Guns.gun_by_id(gid).get("name", gid))
	if not _stash.guns_owned.has(gid):
		show_hint("「%s」未拥有" % name)
		return
	var price: int = _stash.repair_price(gid)
	if price <= 0:
		show_hint("「%s」耐久已满" % name)
		return
	if _stash.repair(gid):
		show_hint("已维修「%s」耐久 100%% −₵%s" % [name, _fmt(price)])
	else:
		show_hint("现金不足：维修需 ₵%s，现有 ₵%s" % [_fmt(price), _fmt(maxi(0, _stash.cash))])


## 改枪台 V：消音器 购买 / 拆装（当前选中枪）
func _sup_sel() -> void:
	var gid := str(Guns.GUNS[posmod(_gun_idx, Guns.GUNS.size())]["id"])
	var name := String(Guns.gun_by_id(gid).get("name", gid))
	if not _stash.sup_allowed(gid):
		show_hint("「%s」不能装消音器" % name)
	elif not _stash.guns_owned.has(gid):
		show_hint("「%s」未拥有 —— 按 3 进交易行购买" % name)
	elif _stash.sup_owned.has(gid):
		var on: bool = _stash.toggle_sup(gid)
		show_hint("「%s」消音器已%s" % [name, "装上 · 枪声只惊动 20 m 内" if on else "拆下"])
	elif _stash.buy_sup(gid):
		show_hint("已为「%s」购买并装上消音器 −₵%s" % [name, _fmt(HDData.SUP_PRICE)])
	else:
		show_hint("现金不足：消音器需 ₵%s，现有 ₵%s" % [_fmt(HDData.SUP_PRICE), _fmt(maxi(0, _stash.cash))])


## ---- 改枪台 3D 预览（SubViewport 独立世界：转台灯光 + 当前枪模，拖动旋转）----
## 预览控件常驻复用（_refresh_all 每次重建页面前先摘下来）；枪模按「枪|镜|消音」
## 键缓存，换枪/换镜/装消音器才重建
func _ensure_preview() -> void:
	if _pv_box != null:
		return
	_pv_box = SubViewportContainer.new()
	_pv_box.stretch = true
	_pv_box.custom_minimum_size = Vector2(0, 236)
	_pv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pv_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_pv_box.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_pv_box.gui_input.connect(_on_preview_input)
	_pv_vp = SubViewport.new()
	_pv_vp.own_world_3d = true
	_pv_vp.transparent_bg = true
	_pv_vp.msaa_3d = Viewport.MSAA_4X
	_pv_box.add_child(_pv_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.6)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_pv_vp.add_child(we)
	for ld in [[Vector3(-32, 38, 0), 1.7, Color(1.0, 0.95, 0.88)],
			[Vector3(-12, -140, 0), 0.9, Color(0.75, 0.85, 1.0)],
			[Vector3(-70, 160, 0), 0.35, Color(1, 1, 1)]]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = ld[0]
		dl.light_energy = float(ld[1])
		dl.light_color = ld[2]
		_pv_vp.add_child(dl)
	_pv_pivot = Node3D.new()
	_pv_vp.add_child(_pv_pivot)
	_pv_cam = Camera3D.new()
	_pv_cam.fov = 26.0
	_pv_vp.add_child(_pv_cam)
	_pv_cam.current = true


func _update_preview(gid: String) -> void:
	var key := "%s|%s|%s" % [gid, str(_stash.scope_fit.get(gid, "iron")), str(_stash.suppressed(gid))]
	if key == _pv_key:
		return
	_pv_key = key
	for c in _pv_pivot.get_children():
		_pv_pivot.remove_child(c)
		c.queue_free()
	if not gun_preview_provider.is_valid():
		return
	var gun: Node3D = gun_preview_provider.call(gid)
	if gun == null:
		return
	_pv_pivot.add_child(gun)
	var bb := _aabb_of(gun)
	gun.position = -bb.get_center()
	# 侧视转台：相机在 +X 侧平视枪身，按枪长取距离（横向视场约 50°，留 15% 边）
	var length := maxf(bb.size.z, maxf(bb.size.x, bb.size.y))
	var d := length * 1.2 + 0.2
	var cp := Vector3(d, length * 0.16, 0.0)
	_pv_cam.transform = Transform3D(Basis.looking_at(-cp, Vector3.UP), cp)


func _aabb_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi_v in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY   # 相对 root 的变换（逐级往上乘，不依赖进树）
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var bb: AABB = xf * mi.mesh.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_pv_drag = mb.pressed
	elif event is InputEventMouseMotion and _pv_drag:
		_pv_yaw += (event as InputEventMouseMotion).relative.x * 0.012


## 改枪台右列行内动作：自带镜枪=置灰「原厂镜专属」标签（守卫拦截换装，光标域 1+5 不变）·
## 已装/已机瞄=置灰钮（点击仅选中该行）· 机瞄=「卸下」·
## 已拥有（含装于他枪，单持自动卸下）=「换装」· 未拥有=「去购买」钮
## （一键跳交易行②区对应行 _goto_market_scope——两段式流程两头都有显式按钮衔接）。
## 装配动作收敛到 _bench_confirm 既有链（先选中该行再确认）
func _mk_bench_action(gun_id: String, e: Dictionary, idx: int) -> Control:
	var sid := str(e["id"])
	if Guns.gun_by_id(gun_id).has("builtin_scope"):
		return _mk_label("原厂镜专属", 12, _dim(0.4))   # 局内 builtin 优先，装了会被覆盖
	if sid != "iron" and not _stash.owns_scope(sid):
		var buy := _mk_btn("去购买", 12)
		_style_btn(buy, true, COL_ACCENT, 12)
		buy.pressed.connect(_goto_market_scope.bind(idx))
		return buy
	var b := _mk_btn("换装", 12)
	var fitted: bool = str(_stash.scope_fit.get(gun_id, "iron")) == sid
	if sid == "iron":
		fitted = str(_stash.scope_fit.get(gun_id, "iron")) == "iron"
		b.text = "机瞄" if fitted else "卸下"
	elif fitted:
		b.text = "已装"
	if fitted:
		_style_btn(b, false, _dim(0.35), 12)
		b.pressed.connect(_bench_select.bind(idx))
	else:
		_style_btn(b, true, COL_ACCENT, 12)
		b.pressed.connect(_on_bench_equip_pressed.bind(idx))
	return b


## 瞄具条目右侧状态标签：自带镜枪分流（机瞄行=原厂镜在位 · 已拥有镜行=不可改装——
## 否则与回车守卫直接矛盾）/ 默认 / 已装 / 装于他枪（单持提示）/ 已拥有 / 价格
func _scope_tag(gun_id: String, sid: String, e: Dictionary) -> String:
	if Guns.gun_by_id(gun_id).has("builtin_scope"):
		if sid == "iron":
			return "默认 · 原厂镜"
		if _stash.owns_scope(sid):
			return "原厂镜专属 · 不可改装"
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
	if Guns.gun_by_id(gun_id).has("builtin_scope"):
		return _dim(0.6)   # 自带镜枪整列锁定：文案与守卫同口径
	if sid == "iron":
		return _dim(0.6)
	if str(_stash.scope_fit.get(gun_id, "iron")) == sid:
		return COL_OK
	for gid in _stash.scope_fit.keys():
		if str(gid) != gun_id and str(_stash.scope_fit[gid]) == sid:
			return _dim(0.6)
	if _stash.owns_scope(sid):
		return COL_OK
	return _dim(0.4)   # 未拥有：购买入口在交易行（按 3 进），改枪台行内「去购买」直达


func _bench_confirm() -> void:
	var guns: Array = Guns.GUNS
	_gun_idx = posmod(_gun_idx, guns.size())
	var gun: Dictionary = guns[_gun_idx]
	var gun_id := str(gun["id"])
	if _bench_col == 0:              # 左列=选枪：一步预安装——跳右列自动选镜
		_bench_jump_to_scope()
		return
	if gun.has("builtin_scope"):
		# 狙击守卫（真 bug 修复）：自带 6× 原厂镜在局内被 _scope_for/scope_zoom 的
		# builtin 优先覆盖，预装镜会被静默顶掉——UI 层直接拦截，杜绝「已换装」假成功
		# （保住「狙击自带恒 6×、非狙击枪绝不自带倍率」设计语义；不动 main/hd_stash）
		show_hint("自带 %.0f× 原厂镜 · 瞄具不可改装" % \
				float(gun["builtin_scope"].get("zoom", 1.0)))
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
		# 购买入口已统一迁到交易行（按 3 进）：改枪台只装配已拥有瞄具，不扣款只指路
		show_hint("「%s」未拥有 —— 按 3 进交易行购买后再来装配" % \
				String(entry.get("name", sid)))
		return
	_stash.equip_scope(gun_id, sid)
	show_hint("已换装：%s" % String(entry.get("name", sid)))


## 改枪台左列回车（一步预安装）：跳右列并自动落到「第一个已拥有且未装」的镜
## （无则保持原选中值），再一回车沿 _bench_confirm 成交；
## 自带镜枪不可改装：不跳列，只提示（回车不再是「按了没反应」的静默）
func _bench_jump_to_scope() -> void:
	var guns: Array = Guns.GUNS
	_gun_idx = posmod(_gun_idx, guns.size())
	var gun: Dictionary = guns[_gun_idx]
	if gun.has("builtin_scope"):
		show_hint("自带 %.0f× 原厂镜 · 不可改装" % \
				float(gun["builtin_scope"].get("zoom", 1.0)))
		return
	_bench_col = 1
	var entries := _scope_entries()
	var gid := str(gun["id"])
	for i in entries.size():
		var sid := str(entries[i]["id"])
		if sid != "iron" and _stash.owns_scope(sid) \
				and str(_stash.scope_fit.get(gid, "iron")) != sid:
			_scope_idx = i
			break
	show_hint("↑↓ 选镜 · 回车换装")
	_refresh_all()


## 改枪台未拥有镜「去购买」：一键跳交易行②区该镜行（两列共用 _scope_entries
## 表序，idx 直通），行带光标高亮——两段式流程两头显式衔接
func _goto_market_scope(idx: int) -> void:
	_tab = 2
	_market_sec = 1
	_market_scope = idx
	_refresh_all()


# ================= 交易行页 =================

func _render_market(pg: VBoxContainer) -> void:
	var guns: Array = Guns.GUNS
	_market_gun = posmod(_market_gun, guns.size())
	_market_ammo_gun = posmod(_market_ammo_gun, guns.size())
	var entries := _scope_entries()
	_market_scope = posmod(_market_scope, entries.size())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pg.add_child(cols)

	# ① 枪械区（左，4 列卡片网格）：已拥有置灰「已拥有」· 未拥有「₵N + 购买」钮
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(_mk_sec_title(0, "① 枪械 · %d 把" % guns.size()))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for i in guns.size():
		var mg: Dictionary = guns[i]
		var mid := str(mg["id"])
		var mowned: bool = _stash.guns_owned.has(mid)
		var msel := _market_sec == 0 and i == _market_gun
		var mrow := _card(msel, COL_ACCENT if msel else _dim(0.18), 6)
		mrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mrow.custom_minimum_size = Vector2(0, 100)
		mrow.gui_input.connect(_on_market_row_input.bind(0, i))
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 2)
		mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mrow.add_child(mv)
		mv.add_child(_gun_thumb(mid, 40, mowned))
		var nm := _mk_label(String(mg.get("name", mid)), 14, _dim(0.45) if mowned else COL_TEXT)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mv.add_child(nm)
		var mhb := HBoxContainer.new()
		mhb.add_theme_constant_override("separation", 6)
		mhb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mv.add_child(mhb)
		if mowned:
			mhb.add_child(_mk_label("已拥有", 13, _dim(0.4)))
		else:
			var pl := _mk_label("₵ " + _fmt(_to_int(mg.get("price", 0))), 14, COL_ACCENT)
			pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mhb.add_child(pl)
			mhb.add_child(_mk_market_buy_btn(0, i))
		grid.add_child(mrow)

	# 右列：② 瞄具区 + ③ 极致备弹区 + ⑤ M14 配件
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)

	# ② 瞄具区：机瞄行默认拥有仅展示；五镜已拥有置灰 / 未拥有「购买」
	right.add_child(_mk_sec_title(1, "② 瞄具 · %d 档（多枪通用 · 单持）" % entries.size()))
	for i in entries.size():
		var me: Dictionary = entries[i]
		var msid := str(me["id"])
		var msowned: bool = _stash.owns_scope(msid)
		var mssel := _market_sec == 1 and i == _market_scope
		var msrow := _card(mssel, COL_ACCENT if mssel else _dim(0.18), 4)
		msrow.custom_minimum_size = Vector2(0, 42)
		msrow.gui_input.connect(_on_market_row_input.bind(1, i))
		var mshb := HBoxContainer.new()
		mshb.add_theme_constant_override("separation", 8)
		mshb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		msrow.add_child(mshb)
		mshb.add_child(_scope_thumb(msid, 30, 56))
		mshb.add_child(_mk_label(String(me.get("name", msid)), 15,
				_dim(0.45) if msowned else COL_TEXT))
		var mdesc := _mk_label("默认 · 多枪通用" if msid == "iron" else String(me.get("desc", "")), 12, _dim(0.5))
		mdesc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mdesc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mdesc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mshb.add_child(mdesc)
		if msowned:
			var owl := _mk_label("已拥有", 13, _dim(0.4))
			owl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mshb.add_child(owl)
		else:
			var spl := _mk_label("₵ " + _fmt(_to_int(me.get("price", 0))), 14, COL_ACCENT)
			spl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mshb.add_child(spl)
			mshb.add_child(_mk_market_buy_btn(1, i))
		right.add_child(msrow)

	# ③ 极致备弹区：段内 ↑↓ 选枪（◀/▶ 鼠标同款）· B 换挡 · 空格/「购 N 发」钮成交
	var ammo_id := _market_ammo_gun_id()
	var ag := Guns.gun_by_id(ammo_id)
	var msel3 := _market_sec == 2
	var ammo_panel := _card(msel3, COL_ACCENT if msel3 else _dim(0.18), 8)
	ammo_panel.gui_input.connect(_on_market_ammo_panel_input)
	right.add_child(ammo_panel)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 6)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到面板卡片
	ammo_panel.add_child(av)
	var ahead := HBoxContainer.new()
	ahead.add_theme_constant_override("separation", 6)
	ahead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(ahead)
	# ③ 徽章标题（段序可读性 + 显式化「给哪把枪补弹」）
	ahead.add_child(_mk_sec_title(2, "③ %s —— 给「%s」补弹" % [
			HDData.AMMO_NAME, String(ag.get("name", ammo_id))]))
	var apick := HBoxContainer.new()
	apick.add_theme_constant_override("separation", 8)
	apick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(apick)
	var prev := _mk_btn("◀", 14)
	_style_btn(prev, false, _dim(0.6), 10)
	prev.pressed.connect(_market_ammo_pick.bind(-1))
	apick.add_child(prev)
	var gname := _mk_label(String(ag.get("name", ammo_id)), 16, COL_TEXT)
	gname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apick.add_child(gname)
	var nxt := _mk_btn("▶", 14)
	_style_btn(nxt, false, _dim(0.6), 10)
	nxt.pressed.connect(_market_ammo_pick.bind(1))
	apick.add_child(nxt)
	var each := _to_int(HDData.AMMO_PRICE.get(ammo_id, 0))
	# 挡位指示：挡位序号 + B 键身份亮出——「B 换挡」钮文字本就随挡位刷新
	av.add_child(_mk_label("单价 ₵%d/发 · 余 %d 发 · 挡位 %d/%d · %d 发（B 切换）" % [
			each, _stash.ammo_of(ammo_id), posmod(_ammo_tier, HDData.AMMO_TIERS.size()) + 1,
			HDData.AMMO_TIERS.size(), _ammo_tier_n()], 13, HDData.AMMO_COLOR))
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	arow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(arow)
	var cyc := _mk_btn("B 换挡", 14)
	_style_btn(cyc, false, _dim(0.6), 12)
	cyc.pressed.connect(_cycle_ammo_tier)
	arow.add_child(cyc)
	var tier_n := _ammo_tier_n()
	var buy := _mk_btn("购 %d 发 · ₵%s" % [tier_n, _fmt(tier_n * each)], 14)
	_style_btn(buy, true, HDData.AMMO_COLOR, 14)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.pressed.connect(_buy_ammo_for.bind(ammo_id))
	arow.add_child(buy)
	# 弹种行（阶段 D 接线）：当前枪弹种 + N 换/购循环（未购现场买，已购直接换）
	var ak := _stash.ammo_kind_of(ammo_id)
	var adef: Dictionary = Guns.ammo_by_id(ak)
	var kind_row := HBoxContainer.new()
	kind_row.add_theme_constant_override("separation", 8)
	kind_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(kind_row)
	var klbl := _mk_label("弹种：%s（%s）" % [str(adef["name"]), str(adef["desc"])], 13,
			adef["color"])
	klbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind_row.add_child(klbl)
	var kbtn := _mk_btn("N 换/购弹种 ▸", 13)
	_style_btn(kbtn, false, COL_ACCENT, 10)
	kbtn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	kbtn.pressed.connect(_cycle_ammo_kind_for.bind(ammo_id))
	kind_row.add_child(kbtn)
	# 投掷物三钮（阶段 D）：鼠标点击购件（库存制，满员/没钱提示走 show_hint）
	var trow2 := HBoxContainer.new()
	trow2.add_theme_constant_override("separation", 6)
	trow2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(trow2)
	for tk in ["frag", "smoke", "flash"]:
		var td: Dictionary = HDData.THROWABLES[tk]
		var tb := _mk_btn("%s ₵%s · %d/%d（局内 %s）" % [str(td["name"]), _fmt(_to_int(td["price"])),
				_stash.throwables_of(tk), _to_int(td["max"]),
				str(HDData.THROW_KEYS[tk]).trim_prefix("KEY_")], 12)
		_style_btn(tb, false, COL_OK if _stash.throwables_of(tk) > 0 else _dim(0.5), 8)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var kind0 := str(tk)
		tb.pressed.connect(func():
			if _stash.buy_throwable(kind0):
				show_hint("已购 %s ×1 —— 局内按 %s 投掷" % [str(HDData.THROWABLES[kind0]["name"]),
						str(HDData.THROW_KEYS[kind0]).trim_prefix("KEY_")])
			else:
				var td2: Dictionary = HDData.THROWABLES[kind0]
				show_hint("买不了：%s（满 %d 件或现金不足 ₵%s）" % [str(td2["name"]),
						_to_int(td2["max"]), _fmt(_to_int(td2["price"]))]))
		trow2.add_child(tb)

	# ⑤ M14 专属配件区（2026-10 用户定案：护木/30 发扩容匣——仅拥有 M14 才
	# 显示购买意义；行式布局同②瞄具区：已购置灰 / 未购「购买」）
	var m14_owned: bool = _stash.guns_owned.has("m14")
	if m14_owned:
		right.add_child(_mk_sec_title(4, "⑤ M14 专属配件"))
		var mod_ids: Array = Guns.M14_MODS.keys()
		for i in mod_ids.size():
			var mid2 := str(mod_ids[i])
			var md: Dictionary = Guns.M14_MODS[mid2]
			var mod_on: bool = _stash.m14_mods_on(mid2)
			var m5sel := _market_sec == 4 and i == _market_m14_mod
			var m5row := _card(m5sel, COL_ACCENT if m5sel else _dim(0.18), 4)
			var m5hb := HBoxContainer.new()
			m5hb.add_theme_constant_override("separation", 10)
			m5hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			m5row.add_child(m5hb)
			m5hb.add_child(_mk_label(String(md.get("name", mid2)), 15,
					_dim(0.45) if mod_on else COL_TEXT))
			var m5d := _mk_label(String(md.get("desc", "")), 12, _dim(0.5))
			m5d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			m5d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			m5hb.add_child(m5d)
			if mod_on:
				m5hb.add_child(_mk_label("已装", 13, COL_OK))
			else:
				m5hb.add_child(_mk_label("₵ " + _fmt(_to_int(md.get("price", 0))), 14, COL_ACCENT))
				var m5btn := _mk_btn("购买", 13)
				_style_btn(m5btn, true, COL_ACCENT, 12)
				m5btn.pressed.connect(func():
					if _stash.buy_m14_mod(mid2):
						show_hint("已购买：%s（装备 M14 即生效）" % String(md.get("name", mid2))))
				m5hb.add_child(m5btn)
			right.add_child(m5row)

	# ④ 仓库·战利品条（原仓库页并入，底部通栏）：变卖链路=④段回车+钮双入口，零丢失
	_render_warehouse_strip(pg)

	var hint := _mk_label("鼠标：点「购买」成交   键盘：←→ 跨段 · ↑↓ 段内选 · 回车 成交 · ③ 区 B 换挡 空格 购弹 · U 安全箱扩容",
			13, _dim(0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pg.add_child(hint)


## 交易行段徽章标题（段序可读性增强）：当前段 COL_ACCENT 高亮、其余 COL_OK——
## ←/→ 跨段走到第几段一眼可数（段面板/行高亮是既有段光标可见性，非修隐藏 bug）
func _mk_sec_title(sec: int, text: String) -> Label:
	return _mk_label(text, 15, COL_ACCENT if _market_sec == sec else COL_OK)


## 交易行行内「购买」钮（未拥有条目专用）：先选中该行，再沿 _market_confirm 收敛成交
func _mk_market_buy_btn(sec: int, idx: int) -> Button:
	var b := _mk_btn("购买", 13)
	_style_btn(b, true, COL_ACCENT, 10)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_on_market_buy_pressed.bind(sec, idx))
	return b


## 交易行行点击（鼠标）：一律只选中（sec=0 枪械 / 1 瞄具）；成交统一走行内「购买」钮
## （参数序：gui_input 信号实参在前，bind 实参在后，同 _on_deploy_row_input 约定）
func _on_market_row_input(event: InputEvent, sec: int, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var cur: int = _market_gun if sec == 0 else _market_scope
			if _market_sec != sec or cur != idx:
				_market_sec = sec
				if sec == 0:
					_market_gun = idx
				else:
					_market_scope = idx
				_refresh_all()


## ③ 区面板点击：仅把光标切到极致备弹段（成交走「购 N 发」钮 / 空格）
func _on_market_ammo_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _market_sec != 2:
			_market_sec = 2
			_refresh_all()


## 交易行行内「购买」钮：先选中该行，再沿既有确认链 _market_confirm 收敛成交
func _on_market_buy_pressed(sec: int, idx: int) -> void:
	_market_sec = sec
	if sec == 0:
		_market_gun = idx
	else:
		_market_scope = idx
	_market_confirm()


## ③ 区购弹对象枪 id（GUNS 全表可选，含未拥有——与出发页速览同语义）
func _market_ammo_gun_id() -> String:
	var guns: Array = Guns.GUNS
	return str(guns[posmod(_market_ammo_gun, guns.size())]["id"])


## ③ 区选枪（◀/▶ 钮）：等价段内 ↑↓ 换枪
func _market_ammo_pick(dir: int) -> void:
	_market_sec = 2
	_market_ammo_gun = posmod(_market_ammo_gun + dir, Guns.GUNS.size())
	_refresh_all()


## 交易行确认（键盘回车与鼠标「购买」钮同收敛于此）：全部购买只在此页成交——
## ① 未拥有枪 buy_gun · ② 未拥有镜 buy_scope · ③ 按挡位 buy_ammo ·
## ④ 仓库段=一键变卖全部 sell_all（原仓库页回车链路并入，零丢失）；
## 已拥有幂等提示不扣款（与 stash API 幂等语义一致）
func _market_confirm() -> void:
	var entries := _scope_entries()
	match _market_sec:
		0:
			var guns: Array = Guns.GUNS
			var g: Dictionary = guns[posmod(_market_gun, guns.size())]
			var gid := str(g["id"])
			if _stash.guns_owned.has(gid):
				show_hint("已拥有「%s」—— 无需重复购买" % String(g.get("name", gid)))
				return
			_purchase_gun(gid)
		1:
			var e: Dictionary = entries[posmod(_market_scope, entries.size())]
			var sid := str(e["id"])
			if _stash.owns_scope(sid):
				show_hint("已拥有「%s」—— 无需重复购买" % String(e.get("name", sid)))
				return
			_purchase_scope(sid)
		2:
			_buy_ammo_for(_market_ammo_gun_id())
		3:
			_sell_all()   # 空仓沿用「仓库空空如也」提示；超 12 件整包一次清（deposit 无封顶）


## 购枪成交（唯一入口=交易行①区）：走 stash.buy_gun 既有链，钱不足拦截不扣款
func _purchase_gun(gid: String) -> void:
	var g := Guns.shop_gun_by_id(gid)
	var price := _to_int(g.get("price", 0))
	if not _stash.buy_gun(gid):
		show_hint("现金不足：%s 需 ₵%s，现有 ₵%s —— 回仓库变卖战利品或明日签到" % [
				String(g.get("name", gid)), _fmt(price), _fmt(maxi(0, _stash.cash))])
		return
	show_hint("已购买：%s（余 ₵%s）" % [
			String(g.get("name", gid)), _fmt(maxi(0, _stash.cash))])


## 购瞄具成交（唯一入口=交易行②区）：走 stash.buy_scope 既有链，钱不足拦截不扣款
func _purchase_scope(sid: String) -> void:
	var sc := Guns.scope_by_id(sid)
	if not _stash.buy_scope(sid):
		show_hint("现金不足：%s 需 ₵%s，现有 ₵%s —— 回仓库变卖战利品或明日签到" % [
				String(sc.get("name", sid)), _fmt(_to_int(sc.get("price", 0))),
				_fmt(maxi(0, _stash.cash))])
		return
	show_hint("已购买：%s（余 ₵%s）—— 按 2 进改枪台装配" % [
			String(sc.get("name", sid)), _fmt(maxi(0, _stash.cash))])


## 当前购弹挡位发数（索引越界防御回绕）
func _ammo_tier_n() -> int:
	return int(HDData.AMMO_TIERS[posmod(_ammo_tier, HDData.AMMO_TIERS.size())])


## B 键 /「B 换挡」钮：购弹挡位 30→90→300 循环（③区总价随行刷新）
func _cycle_ammo_tier() -> void:
	_ammo_tier = posmod(_ammo_tier + 1, HDData.AMMO_TIERS.size())
	_refresh_all()


## 空格 /「购 N 发」钮（交易行③区）：按当前挡位给选中枪买极致备弹
## （现金不足拦截提示，照购枪款；键盘入口由 handle_key 分级守卫把关——只在③区内消费）
func _buy_ammo_for(gid: String) -> void:
	if _stash.buy_ammo(gid, _ammo_tier_n()):
		show_hint("已购 %s ×%d 发（₵%s）" % [String(Guns.gun_by_id(gid).get("name", gid)),
				_ammo_tier_n(), _fmt(_ammo_tier_n() * _to_int(HDData.AMMO_PRICE.get(gid, 0)))])
	else:
		show_hint("现金不足 —— %s %d 发需 ₵%s" % [gid, _ammo_tier_n(),
				_fmt(_ammo_tier_n() * _to_int(HDData.AMMO_PRICE.get(gid, 0)))])


## N 键循环该枪弹种（阶段 D）：未购现场买（钱不够提示），已购直接换装
func _cycle_ammo_kind_for(gid: String) -> void:
	var r: Array = _stash.cycle_ammo_kind(gid)
	var adef: Dictionary = Guns.ammo_by_id(str(r[1]))
	if bool(r[0]):
		show_hint("「%s」弹种 → %s（%s）" % [String(Guns.gun_by_id(gid).get("name", gid)),
				str(adef["name"]), str(adef["desc"])])
	else:
		show_hint("%s 需 ₵%s —— 现金不足" % [str(adef["name"]),
				_fmt(_to_int(adef.get("price", 0)))])


# ================= 光标 / 确认 =================

func _move(dh: int, dv: int) -> void:
	match _tab:
		0:
			# 战备收起：光标域只剩出发钮，方向键不游走（回车=出发，见 _confirm_deploy）
			if not _prep_open:
				_cur0 = 0
			else:
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
			if dh != 0:
				_bench_col = 1 - _bench_col
			if dv != 0:
				if _bench_col == 0:
					_gun_idx = posmod(_gun_idx + dv, Guns.GUNS.size())
				else:
					_scope_idx = posmod(_scope_idx + dv, 1 + Guns.SCOPES.size())
		2:
			# 交易行：←/→ 跨段回绕（域 4：0①枪械/1②瞄具/2③备弹/3④仓库）；
			# 段内 ↑↓ 选条目（③ 区条目=购弹对象枪；④ 仓库段无条目 no-op）
			if dh != 0:
				_market_sec = posmod(_market_sec + dh, MARKET_SECS)
			if dv != 0:
				match _market_sec:
					0:
						_market_gun = posmod(_market_gun + dv, Guns.GUNS.size())
					1:
						_market_scope = posmod(_market_scope + dv, _scope_entries().size())
					2:
						_market_ammo_gun = posmod(_market_ammo_gun + dv, Guns.GUNS.size())
					3:
						pass
	_refresh_all()


func _confirm() -> void:
	match _tab:
		0:
			_confirm_deploy()
		1:
			_bench_confirm()
		2:
			_market_confirm()   # ④ 仓库段 case3=sell_all（原仓库页回车链路并入）


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
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(7)
		sb.content_margin_left = hpad
		sb.content_margin_right = hpad
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hov: StyleBoxFlat = b.get_theme_stylebox("hover").duplicate()
	hov.bg_color = hov.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_color_override("font_color", border)
	b.add_theme_color_override("font_hover_color", border)
	b.add_theme_color_override("font_pressed_color", border)


## vpad：上下内容边距（交易行枪械行卡用 3 压行高——14 行+④仓库条一屏放得下；默认 9 沿用旧款）
func _panel_style(sel: bool, border: Color, vpad := 9) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.11, 0.88) if sel else Color(0.06, 0.09, 0.07, 0.62)
	sb.border_color = border
	sb.set_border_width_all(2 if sel else 1)
	sb.set_corner_radius_all(7)
	sb.set_content_margin_all(vpad)
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


# ================= 卡片式改版小工具（第四阶段） =================

## 卡片（第四阶段大厅改版）：圆角面板 + 悬停提亮 + 手型光标；sel = 光标所在（粗描边亮底）
func _card(sel: bool, border: Color, vpad := 10) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD_SEL if sel else COL_CARD
	sb.border_color = border
	sb.set_border_width_all(2 if sel else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(vpad)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	if sel:
		sb.shadow_color = Color(border.r, border.g, border.b, 0.18)
		sb.shadow_size = 8
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_entered.connect(func(): card.self_modulate = Color(1.18, 1.18, 1.14))
	card.mouse_exited.connect(func(): card.self_modulate = Color.WHITE)
	return card


func _card_vbox(card: PanelContainer, sep: int) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", sep)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到卡片本身
	card.add_child(vb)
	return vb


## 定宽列
func _col(parent: Control, w: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(w, 0)
	v.add_theme_constant_override("separation", 10)
	parent.add_child(v)
	return v


## 区块标题：左标题 + 右侧小字说明（之后可继续往里塞按钮）
func _sec_head(title: String, sub: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var t := _mk_label(title, 17, COL_OK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	if sub != "":
		var s := _mk_label(sub, 12, _dim(0.45))
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(s)
	return hb


## 小标签（「装入此槽」/ 键位提示）
func _chip(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.12)
	sb.border_color = Color(col.r, col.g, col.b, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(_mk_label(text, 12, col))
	return p


## 数据条（frac 0..1）
class Bar extends Control:
	var frac := 0.0
	var col := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(frac, 0.0, 1.0), h)), col)


## ---- 卡片实物图（2026-10 用户反馈「需要有图像，提高体验」）----

func set_thumbs(t) -> void:
	_thumbs = t
	if t != null and not t.shot.is_connected(_on_thumb_shot):
		t.shot.connect(_on_thumb_shot)
	if _root != null and lobby_visible:
		_refresh_all()


func _on_thumb_shot(key: String) -> void:
	for r in _thumb_wait.get(key, []):
		if is_instance_valid(r):
			(r as TextureRect).texture = _thumbs.cached(key)
	_thumb_wait.erase(key)


## 枪械实物图：同局内枪模（含所装瞄具/消音器）；dim = 未拥有/已拥有置灰展示
func _gun_thumb(gid: String, min_h: float, dim := false, w := 0.0) -> Control:
	var key := "g|%s|%s|%s" % [gid, str(_stash.scope_fit.get(gid, "iron")), str(_stash.suppressed(gid))]
	var prov := gun_preview_provider
	return _thumb_box(key, func() -> Node3D: return prov.call(gid) if prov.is_valid() else null,
			min_h, dim, w)


## 瞄具实物图（机瞄没有实物：留同宽空位保持行对齐）
func _scope_thumb(sid: String, min_h: float, w: float) -> Control:
	var sc := Guns.scope_by_id(sid)
	if sid == "iron" or sc.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(w, min_h)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return gap
	var kind := str(sc.get("kind", sid))
	var prov := scope_preview_provider
	return _thumb_box("s|" + kind, func() -> Node3D: return prov.call(kind) if prov.is_valid() else null,
			min_h, not _stash.owns_scope(sid), w)


## 图位：柔光底 + 等比居中的实物图；图还没拍好先留位，拍好就地补上
func _thumb_box(key: String, builder: Callable, min_h: float, dim: bool, w: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(w, min_h)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if w > 0.0:
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.55)
		_glow_tex.fill_to = Vector2(1.0, 0.55)
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.9, 0.72, 0.13))
		g.set_color(1, Color(1.0, 0.9, 0.72, 0.0))
		_glow_tex.gradient = g
	var glow := TextureRect.new()
	glow.texture = _glow_tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(glow)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		tr.modulate = Color(0.72, 0.72, 0.72, 0.72)
	var t: Texture2D = _thumbs.tex(key, builder) if _thumbs != null else null
	if t != null:
		tr.texture = t
	elif _thumbs != null:
		if not _thumb_wait.has(key):
			_thumb_wait[key] = []
		(_thumb_wait[key] as Array).append(tr)
	box.add_child(tr)
	return box
