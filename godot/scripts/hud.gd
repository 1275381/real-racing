class_name RRHud
extends CanvasLayer
## HUD 与车库：转速表 / 小地图 / 计时面板 / 排位榜 / 倒计时 / 逆行警告 /
## 车库（选车 + 选比赛）/ 暂停 / 结算（移植自 js/hud.js 的信息结构）

# 顶部居中三行：时钟（y=8，漫游/比赛/大战场都显示）→ 模式提示 / 战况条 → 通缉
const TOP_ROW2_Y := 42.0
const TOP_ROW3_Y := 80.0
const ROAM_HINT := "自由漫游"
const ROAM_HINT_GARAGE := "自由漫游 · 出生卷帘门车库 · 踩油门顶门驶出"

var team_colors: Array = []

# --- 车库控件（game.gd 直接绑定） ---
var track_sel: OptionButton
var laps_sel: OptionButton
var diff_sel: OptionButton
var btn_start: Button
var btn_roam: Button
var btn_prev_car: Button
var btn_next_car: Button
var garage_best: Label
var track_desc: Label
var car_name_label: Label
var car_desc_label: Label

# --- 暂停/结算 ---
var btn_resume: Button
var btn_restart: Button
var btn_quit_pause: Button
var btn_again: Button
var btn_quit_results: Button
var btn_editor: Button
var btn_city: Button
var btn_del_track: Button
var btn_shop: Button
var btn_carinfo: Button
var btn_npc_solid: Button
var btn_gunshop: Button
var btn_battle: Button
var btn_plane: Button
var results_grid: GridContainer

# --- 大战场 ---
var battle_lbl_ally: Label
var battle_lbl_enemy: Label
var battle_lbl_kill: Label
var battle_lbl_plane: Label
var board_hint: Label

# --- 配件店 / 车辆数据 ---
signal shop_equip(slot: String, opt_id: String)
signal shop_back
signal gun_equip(gun_id: String)
signal gunshop_back
signal ammo_equip(ammo_id: String)
var gunshop_rows := {}      # gun_id -> Button
var _ammo_rows := {}        # ammo_id -> Button
var _gunshop_coins: Label
var shop_car_label: Label
var shop_coins_label: Label
var _carinfo_car_label: Label
var _shop_rows := {}        # "slot|opt" -> {btn: Button, note: Label}
var _shop_slot_boxes := {}  # slot -> VBoxContainer（漂移胎分区按车型显隐）
var info_rows: Label        # 车辆数据明细文本
var shop_hint_label: Label  # 漫游商店进入提示
var gunshop_hint_label: Label  # 漫游枪械店进入提示
var wanted_label: Label     # 通缉指示（警察追捕）
var _roam_hint: Label       # 漫游顶部提示（车库内给出库操作，出库后只留模式名）
var wanted_on := false
var wanted_progress := 0.0
var _wanted_blink_t := 0.0
var gun_overlay: Control       # 步行 HUD：准星/三倍镜遮罩/血条/弹药
var _gun_scope := false
var _gun_hp := 100.0
var _gun_ammo := 30
var _gun_reload := 0.0
var _gun_name := ""
var _dmg_flash_t := 0.0
var _dmg_rect: ColorRect

var _root: Control
var _screens := {}          # name -> Control
var _tach: TachWidget
var _minimap: MinimapWidget
var _plane_panel: PlanePanelWidget
var _plane_panel_on := false   # 战机仪表盘开关（漫游战机模式）
var _clock_label: Label        # 时钟/相位/天气（游戏中显示）
var _timing_labels := {}
var _standings_box: VBoxContainer
var _center_label: Label
var _center_sub: Label
var _center_timer := 0.0
var _lap_flash: Label
var _lap_flash_timer := 0.0
var _wrong_way: Label
var _pos_label: Label
var _dbg: Label            # F3 调试信息（截图定位问题用）


func build(colors: Array) -> void:
	team_colors = colors
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = RRFont.get_font()
	theme.default_font_size = 16
	_root.theme = theme
	add_child(_root)

	# 调试信息层：F3 开关。常驻最上层，任何模式都能看。
	_dbg = Label.new()
	_dbg.visible = false         # I / F3 开关（默认关：它每帧要扫一遍全路网）
	_dbg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dbg.position = Vector2(16, 210)
	_dbg.add_theme_font_size_override("font_size", 15)
	_dbg.add_theme_color_override("font_color", Color(0.85, 1.0, 0.7))
	_dbg.add_theme_constant_override("outline_size", 6)
	_dbg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_root.add_child(_dbg)

	_build_timing_panel()
	_minimap = MinimapWidget.new()
	_minimap.position = Vector2(-250, 12)
	_minimap.size = Vector2(238, 190)
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.visible = false
	_root.add_child(_minimap)
	_build_standings()
	_tach = TachWidget.new()
	_tach.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tach.position = Vector2(-320, -108)   # 底部中央，整体在屏内留 8px 边距
	_tach.size = Vector2(640, 100)
	_tach.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tach.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tach.visible = false
	_root.add_child(_tach)
	_build_center_labels()
	_build_garage()
	_build_shop()
	_build_gunshop()
	_build_carinfo()
	_build_roam_hud()
	_build_battle_hud()
	_build_pause()
	_build_results()
	_build_wanted()
	_build_gun_overlay()
	_build_plane_panel()
	_build_clock()
	show_only("garage")


func _process(dt: float) -> void:
	if _center_timer > 0.0:
		_center_timer -= dt
		if _center_timer <= 0.0:
			_center_label.visible = false
			_center_sub.visible = false
	if _lap_flash_timer > 0.0:
		_lap_flash_timer -= dt
		if _lap_flash_timer <= 0.0:
			_lap_flash.visible = false
	if _dmg_flash_t > 0.0:
		_dmg_flash_t -= dt
		_dmg_rect.visible = _dmg_flash_t > 0.0
		_dmg_rect.modulate.a = clampf(_dmg_flash_t / 0.25, 0.0, 1.0) * 0.45
	_process_gun(dt)
	if wanted_on:
		_wanted_blink_t += dt
		wanted_label.modulate.a = 0.55 + 0.45 * absf(sin(_wanted_blink_t * 6.0))
		var pct := int(wanted_progress * 10.0) * 10   # 10% 一档，避免每帧重排文字
		var txt := "通缉中 · 甩开警察！（距离 180m 以上持续 6 秒）"
		if pct > 0:
			txt += "  摆脱中 %d%%" % pct
		if txt != wanted_label.text:
			wanted_label.text = txt


## 通缉指示（npc_traffic 驱动）
func set_wanted(on: bool, progress: float) -> void:
	wanted_on = on
	wanted_progress = progress
	wanted_label.visible = on
	_wanted_blink_t = 0.0


## 调试信息（F3）
func toggle_debug() -> bool:
	_dbg.visible = not _dbg.visible
	return _dbg.visible


func debug_visible() -> bool:
	return _dbg != null and _dbg.visible


func set_debug(text: String) -> void:
	if _dbg != null:
		_dbg.text = text


func show_only(name: String) -> void:
	for k in _screens:
		_screens[k].visible = k == name
	var show_flight := name == "hud" or name == "roam"
	_tach.visible = show_flight and not _plane_panel_on
	_minimap.visible = show_flight
	_plane_panel.visible = _plane_panel_on and name == "roam"


# ================= 计时面板 =================

func _build_timing_panel() -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.72)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var defs := [
		["lap", "第 1/3 圈", 22, Color(1, 1, 1)],
		["current", "本圈 0:00.000", 17, Color(0.85, 0.9, 0.95)],
		["last", "上圈 --:--.---", 14, Color(0.65, 0.7, 0.75)],
		["best", "最快 --:--.---", 14, Color(0.98, 0.75, 0.25)],
		["race", "总时 0:00.000", 14, Color(0.65, 0.7, 0.75)],
	]
	for d in defs:
		var l := Label.new()
		l.text = d[1]
		l.add_theme_font_size_override("font_size", d[2])
		l.add_theme_color_override("font_color", d[3])
		box.add_child(l)
		_timing_labels[d[0]] = l
	var hud_screen := Control.new()
	hud_screen.name = "hud"
	hud_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_screen.add_child(panel)
	_root.add_child(hud_screen)
	_screens["hud"] = hud_screen


func _build_standings() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(-250, 212)
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.custom_minimum_size = Vector2(238, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standings_box = box
	_screens["hud"].add_child(box)
	for i in 4:
		var l := Label.new()
		l.text = ""
		var ls := LabelSettings.new()
		ls.font = RRFont.get_font()
		ls.font_size = 16
		ls.font_color = Color.WHITE
		ls.outline_size = 4
		ls.outline_color = Color(0, 0, 0, 0.7)
		l.label_settings = ls
		box.add_child(l)


func update_timing(data: Dictionary) -> void:
	_timing_labels["lap"].text = "第 %d/%d 圈" % [data["lap_num"], data["total_laps"]]
	_timing_labels["current"].text = "本圈 " + RRUtil.format_time(data["current"])
	_timing_labels["last"].text = "上圈 " + RRUtil.format_time(data["last"])
	_timing_labels["best"].text = "最快 " + RRUtil.format_time(data["best"])
	_timing_labels["race"].text = "总时 " + RRUtil.format_time(data["race_time"])


func update_standings(positions: Array) -> void:
	for i in 4:
		var l := _standings_box.get_child(i) as Label
		if i >= positions.size():
			l.text = ""
			continue
		var p: Dictionary = positions[i]
		var ls := l.label_settings as LabelSettings
		ls.font_color = team_colors[p["idx"]]
		var suffix := ""
		if p.get("best_lap") != null:
			suffix = "  " + RRUtil.format_time(p["best_lap"])
		elif p.get("finish_time") != null:
			suffix = "  " + RRUtil.format_time(p["finish_time"])
		l.text = "P%d %s%s" % [i + 1, p["name"], suffix]


	# 漫游模式：转速表不显示名次角标
func set_roam_tach() -> void:
	pass   # 仪表统一为底部横条样式，漫游无需特殊化


func update_pos(_pos_num: int, _total: int) -> void:
	pass   # 名次显示已移至左上角实时排名面板


# ================= 中央提示 =================

func _build_center_labels() -> void:
	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 96)
	_center_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_center_label.add_theme_constant_override("outline_size", 14)
	_center_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_label.visible = false
	_center_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center_label)   # 挂根容器：任意屏幕（比赛/漫游）下都显示

	_center_sub = Label.new()
	_center_sub.set_anchors_preset(Control.PRESET_CENTER)
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_sub.add_theme_font_size_override("font_size", 22)
	_center_sub.add_theme_constant_override("outline_size", 8)
	_center_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_center_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_sub.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_sub.visible = false
	_center_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center_sub)

	_lap_flash = Label.new()
	_lap_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lap_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lap_flash.add_theme_font_size_override("font_size", 34)
	_lap_flash.add_theme_constant_override("outline_size", 10)
	_lap_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_lap_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lap_flash.position.y += 90
	_lap_flash.visible = false
	_lap_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screens["hud"].add_child(_lap_flash)

	_wrong_way = Label.new()
	_wrong_way.set_anchors_preset(Control.PRESET_CENTER)
	_wrong_way.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrong_way.text = "⛔ 逆 行"
	_wrong_way.add_theme_font_size_override("font_size", 52)
	_wrong_way.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	_wrong_way.add_theme_constant_override("outline_size", 12)
	_wrong_way.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_wrong_way.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wrong_way.grow_vertical = Control.GROW_DIRECTION_BOTH
	_wrong_way.position.y -= 150
	_wrong_way.visible = false
	_wrong_way.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screens["hud"].add_child(_wrong_way)


func show_center(text: String, sub: String, ms: float, _style := "") -> void:
	_center_label.text = text
	_center_label.visible = text != ""
	_center_sub.text = sub
	_center_sub.visible = sub != ""
	_center_sub.position.y = _center_label.position.y + 70
	_center_timer = ms / 1000.0


func countdown(text: String) -> void:
	show_center(text, "", 900)


func flash_lap(lap_num: int, delta_str: String, is_best: bool) -> void:
	var text := "第 %d 圈" % lap_num
	if is_best:
		text += " ★ 最快圈"
	elif delta_str != "":
		text += "  " + delta_str
	_lap_flash.text = text
	_lap_flash.visible = true
	_lap_flash.add_theme_color_override("font_color",
			Color(0.98, 0.75, 0.25) if is_best else Color(1, 1, 1))
	_lap_flash_timer = 2.0


func set_wrong_way(on: bool) -> void:
	_wrong_way.visible = on


# ================= 转速表 =================

class TachWidget:
	extends Control
	var speed_kmh := 0.0
	var gear_label := "1"
	var rpm := 0.1
	var drifting := false
	var speed_ratio := 0.0          # 全程速度进程（0..1），驱动档位进程指针
	var lap_text := "--:--.--"      # 右侧功能数字：本圈时间 / 漫游行驶时长
	var lap_label := "本圈"
	var nitro := 1.0                # 氮气储量 0..1

	func _draw() -> void:
		var font := RRFont.get_font()
		var w := size.x
		var h := size.y
		# 背板
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.03, 0.05, 0.09, 0.5)
		bg.set_corner_radius_all(10)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		# ---- 档位进程轨道 + 倒三角指针（速度数字上方）----
		var track_y := 16.0
		var tr_l := 190.0
		var tr_r := w - 210.0
		for g in 7:
			var gx := lerpf(tr_l, tr_r, g / 6.0)
			var lit := speed_ratio >= g / 6.0 - 0.001
			draw_rect(Rect2(gx - 1.5, track_y - 5, 3, 10),
					Color(1.0, 0.78, 0.3, 0.95) if lit else Color(0.4, 0.45, 0.5, 0.5))
		var px := lerpf(tr_l, tr_r, clampf(speed_ratio, 0.0, 1.0))
		draw_colored_polygon(PackedVector2Array([
			Vector2(px - 8, track_y - 5), Vector2(px + 8, track_y - 5),
			Vector2(px, track_y + 6)
		]), Color(1, 1, 1, 0.95))
		# ---- 档位 ----
		draw_string(font, Vector2(40, h * 0.58), gear_label,
				HORIZONTAL_ALIGNMENT_CENTER, 60, 44, Color(1.0, 0.78, 0.3))
		draw_string(font, Vector2(40, h * 0.58 + 20), "GEAR",
				HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(0.6, 0.66, 0.72))
		# ---- 速度大字（数码管橙，漂移转红）----
		var spd := str(int(round(speed_kmh)))
		var spd_col := Color(1.0, 0.45, 0.3) if drifting else Color(1.0, 0.72, 0.28)
		draw_string(font, Vector2(w * 0.5 - 140, h * 0.58), spd,
				HORIZONTAL_ALIGNMENT_CENTER, 180, 56, spd_col)
		draw_string(font, Vector2(w * 0.5 - 140, h * 0.58 + 20), "km/h",
				HORIZONTAL_ALIGNMENT_CENTER, 180, 12, Color(0.6, 0.66, 0.72))
		# ---- 氮气条（速度下方，蓝）----
		var nx := w * 0.5 - 90.0
		var ny := h - 12.0
		draw_rect(Rect2(nx - 2, ny - 2, 184, 10), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(nx, ny, 180.0 * clampf(nitro, 0.0, 1.0), 6),
				Color(0.3, 0.75, 1.0))
		draw_string(font, Vector2(nx - 44, ny + 8), "NOS",
				HORIZONTAL_ALIGNMENT_LEFT, 40, 11, Color(0.45, 0.8, 1.0))
		# ---- 右侧功能数字：本圈时间 ----
		draw_string(font, Vector2(w - 170, h * 0.4), lap_text,
				HORIZONTAL_ALIGNMENT_CENTER, 144, 21, Color(0.9, 0.93, 0.97))
		draw_string(font, Vector2(w - 170, h * 0.4 + 18), lap_label,
				HORIZONTAL_ALIGNMENT_CENTER, 144, 11, Color(0.6, 0.66, 0.72))
		if drifting:
			draw_string(font, Vector2(w - 170, h * 0.4 + 40), "DRIFT",
					HORIZONTAL_ALIGNMENT_CENTER, 144, 13, Color(1.0, 0.4, 0.3))


func draw_tach(speed: float, gear_label: String, rpm_norm: float, drifting: bool,
		speed_ratio: float, lap_text: String, lap_label := "本圈",
		nitro := 1.0) -> void:
	_tach.speed_kmh = speed
	_tach.gear_label = gear_label
	_tach.rpm = rpm_norm
	_tach.drifting = drifting
	_tach.speed_ratio = speed_ratio
	_tach.lap_text = lap_text
	_tach.lap_label = lap_label
	_tach.nitro = nitro
	_tach.queue_redraw()


# ================= 战机仪表盘 =================

class PlanePanelWidget:
	extends Control
	var spd_kmh := 0.0        # 空速 km/h
	var alt_m := 0.0          # 气压高度 m
	var vs_ms := 0.0          # 升降率 m/s（平滑）
	var hdg_deg := 0.0        # 航向 0..360（0=北）
	var pitch_rad := 0.0      # 俯仰（+抬头）
	var roll_rad := 0.0       # 滚转（+左倾）
	var throttle := 0.0
	var rpm := 0.0            # 转速规范化
	var landed := true

	var _vs_disp := 0.0

	func _draw() -> void:
		var font := RRFont.get_font()
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.04, 0.05, 0.08, 0.78)
		bg.set_corner_radius_all(12)
		bg.border_color = Color(0.35, 0.4, 0.46, 0.8)
		bg.set_border_width_all(2)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		_vs_disp = lerpf(_vs_disp, vs_ms, 0.15)
		# ---- 四连圆表 ----
		var r := 52.0
		var cy := size.y * 0.46
		var xs := [r + 26.0, r * 3.0 + 42.0, r * 5.0 + 58.0, r * 7.0 + 74.0]
		_draw_asi(font, xs[0], cy, r)
		_draw_attitude(font, xs[1], cy, r)
		_draw_alt(font, xs[2], cy, r)
		_draw_vsi(font, xs[3], cy, r)
		# ---- 右侧数字区 ----
		var dx := size.x - 208.0
		var compass := "N" if hdg_deg < 22.5 or hdg_deg >= 337.5 else (
				"E" if hdg_deg < 112.5 else ("S" if hdg_deg < 202.5 else "W"))
		draw_string(font, Vector2(dx, 34), "HDG %3d° %s" % [int(hdg_deg), compass],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.97, 1.0))
		# 油门条
		draw_string(font, Vector2(dx, 62), "THR", HORIZONTAL_ALIGNMENT_LEFT,
				-1, 14, Color(0.62, 0.68, 0.75))
		draw_rect(Rect2(dx + 42, 48, 130, 12), Color(0.12, 0.14, 0.18))
		draw_rect(Rect2(dx + 42, 48, 130.0 * clampf(throttle, 0.0, 1.0), 12),
				Color(1.0, 0.72, 0.28))
		# 转速条
		draw_string(font, Vector2(dx, 92), "RPM", HORIZONTAL_ALIGNMENT_LEFT,
				-1, 14, Color(0.62, 0.68, 0.75))
		draw_rect(Rect2(dx + 42, 78, 130, 12), Color(0.12, 0.14, 0.18))
		var rpm_c := Color(0.45, 0.85, 0.45) if rpm < 0.9 else Color(0.95, 0.4, 0.3)
		draw_rect(Rect2(dx + 42, 78, 130.0 * clampf(rpm, 0.0, 1.0), 12), rpm_c)
		draw_string(font, Vector2(dx + 42, 108), "%d r/min" % int(rpm * 2700.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.68, 0.75))
		# 状态灯
		var st := "GND 地面" if landed else "AIR 空中"
		var st_c := Color(0.55, 0.85, 1.0) if not landed else Color(0.6, 0.66, 0.72)
		draw_circle(Vector2(dx + 8, 132), 5, st_c)
		draw_string(font, Vector2(dx + 20, 137), st, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 15, st_c)

	func _dial_base(c: Vector2, r: float, label: String) -> void:
		var font := RRFont.get_font()
		draw_circle(c, r + 5, Color(0.16, 0.18, 0.22))
		draw_circle(c, r, Color(0.07, 0.08, 0.11))
		draw_arc(c, r, 0, TAU, 48, Color(0.45, 0.5, 0.56), 2.0)
		draw_string(font, c + Vector2(-r, r + 16), label,
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, Color(0.62, 0.68, 0.75))

	func _needle(c: Vector2, ang: float, len: float, col: Color,
			width := 3.0) -> void:
		draw_line(c, c + Vector2(sin(ang), -cos(ang)) * len, col, width)

	## 空速表：0–300 km/h，绿弧 60–260
	func _draw_asi(font: Font, x: float, y: float, r: float) -> void:
		var c := Vector2(x, y)
		_dial_base(c, r, "空速 km/h")
		var a0 := deg_to_rad(-120.0)
		var a1 := deg_to_rad(120.0)
		for v in range(0, 301, 50):
			var t := float(v) / 300.0
			var ang := lerpf(a0, a1, t)
			_needle(c, ang, r - 12.0, Color(0.7, 0.75, 0.82), 2.0)
		draw_arc(c, r - 6.0, a0 + deg_to_rad(72.0), a1 - deg_to_rad(48.0),
				24, Color(0.4, 0.9, 0.5, 0.8), 4.0)
		var na := lerpf(a0, a1, clampf(spd_kmh / 300.0, 0.0, 1.0))
		_needle(c, na, r - 16.0, Color(1.0, 0.85, 0.3), 3.5)
		draw_circle(c, 4, Color(0.8, 0.84, 0.9))
		draw_string(font, c + Vector2(-r, -r * 0.25), "%d" % int(spd_kmh),
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, Color(0.95, 0.97, 1.0))

	## 姿态仪：天地线随滚转旋转/俯仰平移 + 俯仰梯（裁剪进表盘）+ 固定机翼标
	func _draw_attitude(font: Font, x: float, y: float, r: float) -> void:
		var c := Vector2(x, y)
		_dial_base(c, r, "姿态")
		var up := Vector2(sin(roll_rad), -cos(roll_rad))       # 机头上方向
		var rt := _perp(up)
		var shift := -pitch_to_px(r)
		var steps := 14
		for i in range(-steps, steps + 1):
			var mid := c + up * (float(i) / steps * r * 2.4 + shift)
			var pitch_deg := i * (180.0 / steps)
			var is_sky := up.dot(mid - c) > 0.0
			var col := Color(0.6, 0.82, 1.0, 0.9) if is_sky \
					else Color(0.95, 0.65, 0.3, 0.9)
			var major := int(absf(pitch_deg)) % 45 == 0
			var half := 26.0 if major else 13.0
			for s in [-1.0, 1.0]:
				var a: Vector2 = mid + rt * (half * float(s))
				var b: Vector2 = mid + rt * (half * float(s) * 0.45)
				if not _seg_in_circle(a, b, c, r - 4.0).is_empty():
					draw_line(a, b, col, 1.8)
			if major:
				var tp := mid + rt * (half + 5.0)
				if up.dot(tp - c) < r - 8.0:
					draw_string(font, tp - Vector2(8, -4),
							str(int(absf(pitch_deg))),
							HORIZONTAL_ALIGNMENT_CENTER, 20, 9, col)
		# 天地线（0°，横贯表盘）
		var hmid := c + up * shift
		var seg := _clip_seg_circle(hmid - rt * (r + 8.0),
				hmid + rt * (r + 8.0), c, r - 4.0)
		if seg.size() == 2:
			draw_line(seg[0], seg[1], Color(0.95, 0.97, 1.0, 0.95), 2.2)
		# 固定机翼标（W 形）
		var wc := Color(1.0, 0.62, 0.15)
		draw_line(c + Vector2(-30, 0), c + Vector2(-10, 0), wc, 3.0)
		draw_line(c + Vector2(10, 0), c + Vector2(30, 0), wc, 3.0)
		draw_line(c + Vector2(0, 0), c + Vector2(0, 7), wc, 3.0)
		draw_circle(c, 2.5, wc)

	## 线段裁剪进圆：返回圆内端点数组（空 = 完全在圆外）
	func _clip_seg_circle(a: Vector2, b: Vector2, c: Vector2,
			r: float) -> Array:
		var d := b - a
		var f := a - c
		var aa := d.dot(d)
		if aa == 0.0:
			return []
		var bb := 2.0 * f.dot(d)
		var cc := f.dot(f) - r * r
		var disc := bb * bb - 4.0 * aa * cc
		if disc < 0.0:
			return []
		var sq := sqrt(disc)
		var lo := maxf((-bb - sq) / (2.0 * aa), 0.0)
		var hi := minf((-bb + sq) / (2.0 * aa), 1.0)
		if lo > hi:
			return []
		return [a + d * lo, a + d * hi]

	func _seg_in_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array:
		return _clip_seg_circle(a, b, c, r)

	func pitch_to_px(r: float) -> float:
		return clampf(pitch_rad, -0.6, 0.6) * r * 1.4

	func _perp(v: Vector2) -> Vector2:
		return Vector2(-v.y, v.x)

	## 高度表：一圈 1000m + 数字
	func _draw_alt(font: Font, x: float, y: float, r: float) -> void:
		var c := Vector2(x, y)
		_dial_base(c, r, "高度 m")
		for v in range(0, 10):
			var ang := deg_to_rad(-120.0 + 240.0 * v / 10.0)
			_needle(c, ang, r - 12.0, Color(0.7, 0.75, 0.82), 2.0)
		var t := fmod(alt_m, 1000.0) / 1000.0
		_needle(c, lerpf(deg_to_rad(-120.0), deg_to_rad(120.0), t),
				r - 16.0, Color(1.0, 0.85, 0.3), 3.5)
		draw_circle(c, 4, Color(0.8, 0.84, 0.9))
		draw_string(font, c + Vector2(-r, -r * 0.25), "%d" % int(alt_m),
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, Color(0.95, 0.97, 1.0))

	## 升降率：-20..+20 m/s，0 在正上
	func _draw_vsi(font: Font, x: float, y: float, r: float) -> void:
		var c := Vector2(x, y)
		_dial_base(c, r, "升降 m/s")
		for v in [-20.0, -10.0, 0.0, 10.0, 20.0]:
			var ang := deg_to_rad(180.0 * (v / 20.0))
			_needle(c, ang, r - 12.0, Color(0.7, 0.75, 0.82) if v != 0.0
					else Color(0.4, 0.9, 0.5), 2.0)
		var na := deg_to_rad(180.0 * (clampf(_vs_disp, -20.0, 20.0) / 20.0))
		_needle(c, na, r - 16.0, Color(1.0, 0.85, 0.3), 3.5)
		draw_circle(c, 4, Color(0.8, 0.84, 0.9))
		draw_string(font, c + Vector2(-r, -r * 0.25), "%+.1f" % _vs_disp,
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, Color(0.95, 0.97, 1.0))


func _build_plane_panel() -> void:
	_plane_panel = PlanePanelWidget.new()
	_plane_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_plane_panel.position = Vector2(-360, -218)
	_plane_panel.size = Vector2(720, 190)
	_plane_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plane_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_plane_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plane_panel.visible = false
	_root.add_child(_plane_panel)


func update_plane_panel(spd: float, alt: float, vs: float, hdg: float,
		pitch: float, roll: float, thr: float, rpm_n: float,
		is_landed: bool) -> void:
	_plane_panel.spd_kmh = spd
	_plane_panel.alt_m = alt
	_plane_panel.vs_ms = vs
	_plane_panel.hdg_deg = hdg
	_plane_panel.pitch_rad = pitch
	_plane_panel.roll_rad = roll
	_plane_panel.throttle = thr
	_plane_panel.rpm = rpm_n
	_plane_panel.landed = is_landed
	_plane_panel.queue_redraw()


func set_plane_panel(on: bool) -> void:
	_plane_panel_on = on
	# 立即按当前屏状态应用可见性（show_only 只在切屏时刷）
	var roam_visible: bool = _screens.has("roam") and _screens["roam"].visible
	_plane_panel.visible = on and roam_visible
	_tach.visible = roam_visible and not on   # 与转速表互斥


## 时钟：时刻 + 相位 + 天气
func _build_clock() -> void:
	_clock_label = Label.new()
	_clock_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_clock_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clock_label.position.y = 8.0
	_clock_label.add_theme_font_size_override("font_size", 20)
	_clock_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_clock_label.add_theme_color_override("font_outline_color",
			Color(0, 0, 0, 0.75))
	_clock_label.add_theme_constant_override("outline_size", 5)
	_clock_label.visible = false
	_root.add_child(_clock_label)


## 漫游顶部提示：车库内显示出库操作，出库后只留模式名（原来全程挂着「踩油门顶门驶出」）
func set_roam_in_garage(in_garage: bool) -> void:
	var t := ROAM_HINT_GARAGE if in_garage else ROAM_HINT
	if _roam_hint != null and _roam_hint.text != t:
		_roam_hint.text = t


func update_clock(time_str: String, phase: String, weather_str: String) -> void:
	var txt := "%s  ·  %s  ·  %s" % [time_str, phase, weather_str]
	if _clock_label.text != txt:
		_clock_label.text = txt


func set_clock_visible(on: bool) -> void:
	_clock_label.visible = on


# ================= 小地图 =================

class MinimapWidget:
	extends Control
	var _pts := PackedVector2Array()
	var _transformed := PackedVector2Array()
	var _cars: Array = []
	var _has_track := false
	var _map_lo := Vector2.ZERO
	var _map_scale := 1.0
	var _map_off := Vector2.ZERO
	var _tex: Texture2D
	var _wmin := Vector2.ZERO
	var _wmax := Vector2.ZERO
	var _route := PackedVector2Array()
	var _dest := Vector2(-9e9, -9e9)
	var _line_w := 3.0

	func set_track(track: RaceTrack) -> void:
		_pts = track.pts
		_has_track = true
		_tex = null
		_transformed = PackedVector2Array()   # 触发重算
		queue_redraw()

	func set_map_texture(tex: Texture2D, wmin: Vector2, wmax: Vector2) -> void:
		_tex = tex
		_wmin = wmin
		_wmax = wmax
		_has_track = false
		queue_redraw()

	func set_cars(cars: Array) -> void:
		_cars = cars
		queue_redraw()

	func set_route(pts: PackedVector2Array, line_w := 3.0) -> void:
		_route = pts
		_line_w = line_w
		queue_redraw()

	func set_dest(p: Vector2) -> void:
		_dest = p
		queue_redraw()

	## 屏幕局部坐标 → 世界 XZ（仅地图纹理模式有效）
	func local_to_world(lp: Vector2) -> Vector2:
		var n := lp / size
		return _wmin + n * (_wmax - _wmin)

	var markers: Array = []   # 固定地标 [{"x","z","label"}]（配件店/枪械店）

	func set_marker(x: float, z: float, label: String) -> void:
		markers = [{"x": x, "z": z, "label": label}]
		queue_redraw()

	func add_marker(x: float, z: float, label: String) -> void:
		markers.append({"x": x, "z": z, "label": label})
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_transformed = PackedVector2Array()
			queue_redraw()

	func _recompute() -> void:
		if not _has_track or _pts.is_empty() or size.x < 8:
			return
		var lo := _pts[0]
		var hi := _pts[0]
		for p in _pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var span := hi - lo
		_map_lo = lo
		_map_scale = minf((size.x - 16.0) / maxf(span.x, 1.0), (size.y - 16.0) / maxf(span.y, 1.0))
		_map_off = (size - span * _map_scale) / 2.0
		_transformed = PackedVector2Array()
		_transformed.resize(_pts.size())
		for i in _pts.size():
			_transformed[i] = (_pts[i] - lo) * _map_scale + _map_off

	func _map(p: Vector2) -> Vector2:
		if _tex != null:
			var n := (p - _wmin) / (_wmax - _wmin)
			return Vector2(n.x * size.x, n.y * size.y)
		return (p - _map_lo) * _map_scale + _map_off

	func _draw() -> void:
		if _tex != null:
			draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
		if _route.size() > 1:
			var rp := PackedVector2Array()
			for p in _route:
				rp.append(_map(p))
			draw_polyline(rp, Color(0.25, 0.7, 1.0, 0.95), _line_w, true)
		if _dest.x > -8e8:
			var dp := _map(_dest)
			draw_circle(dp, _line_w + 4.0, Color(1.0, 0.25, 0.2, 0.9))
			draw_circle(dp, _line_w + 1.5, Color(1, 1, 1))
		elif _has_track:
			if _transformed.is_empty():
				_recompute()
			if not _transformed.is_empty():
				draw_polyline(_transformed, Color(0.75, 0.78, 0.82, 0.9), 3.0, true)
		for car in _cars:
			var sp := _map(Vector2(car["x"], car["z"]))
			var col: Color = car["color"]
			if car["is_player"]:
				draw_circle(sp, 6.0, Color(1, 1, 1))
				draw_circle(sp, 4.5, col)
				var h: float = car["heading"]
				draw_line(sp, sp + Vector2(sin(h), cos(h)) * 10.0, Color(1, 1, 1), 2.0)
			else:
				draw_circle(sp, 4.0, Color(0, 0, 0, 0.5))
				draw_circle(sp, 3.4, col)
		for marker in markers:
			var mp := _map(Vector2(marker["x"], marker["z"]))
			var ms := 7.0
			draw_rect(Rect2(mp - Vector2(ms, ms), Vector2(ms * 2.0, ms * 2.0)),
					Color(0.12, 0.12, 0.14, 0.9))
			draw_rect(Rect2(mp - Vector2(ms - 1.5, ms - 1.5), Vector2((ms - 1.5) * 2.0,
					(ms - 1.5) * 2.0)), Color(1.0, 0.82, 0.25))
			draw_string(ThemeDB.fallback_font, mp + Vector2(ms + 2.0, 5.0),
					str(marker["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(1.0, 0.86, 0.4))


func init_minimap(track: RaceTrack) -> void:
	_minimap.set_track(track)


func init_roam_minimap(tex: Texture2D, wmin: Vector2, wmax: Vector2) -> void:
	_minimap.set_map_texture(tex, wmin, wmax)


func draw_minimap(cars: Array) -> void:
	_minimap.set_cars(cars)


## 漫游小地图固定地标（配件店）
func set_map_marker(x: float, z: float, label: String) -> void:
	_minimap.set_marker(x, z, label)


## 追加小地图地标（不替换已有标记）
func add_map_marker(x: float, z: float, label: String) -> void:
	_minimap.add_marker(x, z, label)


# ================= 大地图（自由漫游导航） =================

var _map_screen: Control
var _bigmap: MinimapWidget
var _map_hint: Label
var on_map_pick: Callable          # 点击地图设目的地：Callable(world: Vector2)
var on_map_poi: Callable           # 点地标按钮：Callable(poi: Dictionary)

func _build_map_screen() -> void:
	_map_screen = Control.new()
	_map_screen.name = "bigmap"
	_map_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_screen.visible = false
	_root.add_child(_map_screen)
	var vs := _map_screen.get_viewport_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_screen.add_child(bg)
	var title := Label.new()
	title.text = "自由漫游地图"
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_map_screen.add_child(title)
	# 中央大地图（可点击设目的地）
	_bigmap = MinimapWidget.new()
	_bigmap.position = Vector2((vs.x - 740.0) * 0.5, 56.0)
	_bigmap.size = Vector2(740.0, minf(vs.y - 100.0, 740.0))
	_bigmap.mouse_filter = Control.MOUSE_FILTER_STOP
	_bigmap.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT \
				and on_map_pick.is_valid():
			on_map_pick.call(_bigmap.local_to_world(ev.position)))
	_map_screen.add_child(_bigmap)
	# 右侧地标/设施按钮列
	var panel := PanelContainer.new()
	panel.position = Vector2(vs.x - 268.0, 56.0)
	panel.custom_minimum_size = Vector2(248, 500)
	_map_screen.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(230, 490)
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(214, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	var cap := Label.new()
	cap.text = "目的地"
	cap.add_theme_font_size_override("font_size", 20)
	vbox.add_child(cap)
	for poi: Dictionary in nav_pois():
		var b := Button.new()
		b.text = str(poi["label"])
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func():
			if on_map_poi.is_valid():
				on_map_poi.call(poi))
		vbox.add_child(b)
	# 底部操作提示
	_map_hint = Label.new()
	_map_hint.text = "左键点击地图设目的地 · 点右侧地标直接开始导航 · O 开/关自动导航 · Esc 关闭"
	_map_hint.position = Vector2(24.0, vs.y - 34.0)
	_map_hint.add_theme_font_size_override("font_size", 18)
	_map_hint.add_theme_color_override("font_outline_color",
			Color(0, 0, 0, 0.75))
	_map_hint.add_theme_constant_override("outline_size", 6)
	_map_screen.add_child(_map_hint)


func nav_pois() -> Array:
	return [
		{"label": "配件店", "pos": Vector2(34, 34)},
		{"label": "枪械店", "pos": Vector2(-46, 46)},
		{"label": "车库", "pos": Vector2(198, -505)},
		{"label": "机 场", "pos": Vector2(-1161, -94)},
		{"label": "截机任务 货机", "pos": Vector2(-1476, -570)},
		{"label": "云顶之针 电视塔", "pos": Vector2(90, 116)},
		{"label": "双辉双子塔", "pos": Vector2(450, 116)},
		{"label": "云湖体育馆", "pos": Vector2(-450, -30)},
		{"label": "湖畔之眼 摩天轮", "pos": Vector2(-630, 476)},
		{"label": "文笔塔", "pos": Vector2(630, -424)},
		{"label": "天环中心", "pos": Vector2(-90, 476)},
		{"label": "环球百货", "pos": Vector2(270, -60)},
		{"label": "国际赛车场", "pos": Vector2(716, 2432)},
	]


func open_map_screen(cars: Array) -> void:
	if _map_screen == null:
		_build_map_screen()
		_bigmap.set_map_texture(_minimap._tex, _minimap._wmin, _minimap._wmax)
	_bigmap.set_cars(cars)
	_map_screen.visible = true


func close_map_screen() -> void:
	if _map_screen != null:
		_map_screen.visible = false


func map_screen_visible() -> bool:
	return _map_screen != null and _map_screen.visible


func map_set_route(pts: PackedVector2Array) -> void:
	if _bigmap != null:
		_bigmap.set_route(pts, 5.0)
	_minimap.set_route(pts, 3.0)


func map_set_dest(p: Vector2) -> void:
	if _bigmap != null:
		_bigmap.set_dest(p)
	_minimap.set_dest(p)


func map_clear_nav() -> void:
	if _bigmap != null:
		_bigmap.set_route(PackedVector2Array())
		_bigmap.set_dest(Vector2(-9e9, -9e9))
	_minimap.set_route(PackedVector2Array())
	_minimap.set_dest(Vector2(-9e9, -9e9))


# ================= 车库（选车 + 选比赛） =================

func _build_garage() -> void:
	var screen := Control.new()
	screen.name = "garage"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(screen)
	_screens["garage"] = screen

	# 顶部标题
	var title := Label.new()
	title.text = "🏁 极速争锋 REAL RACING"
	title.position = Vector2(18, 12)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	screen.add_child(title)

	# ---- 右侧：选择比赛面板 ----
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position = Vector2(-370, 0)
	screen.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(box)

	var race_title := Label.new()
	race_title.text = "选择比赛"
	race_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_title.add_theme_font_size_override("font_size", 26)
	box.add_child(race_title)
	box.add_child(HSeparator.new())

	track_sel = _add_row(box, "赛道")
	track_desc = Label.new()
	track_desc.text = ""
	track_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	track_desc.add_theme_font_size_override("font_size", 13)
	track_desc.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
	box.add_child(track_desc)

	btn_del_track = Button.new()
	btn_del_track.text = "删除该自定义赛道"
	btn_del_track.custom_minimum_size = Vector2(0, 30)
	btn_del_track.add_theme_font_size_override("font_size", 13)
	btn_del_track.visible = false
	box.add_child(btn_del_track)

	laps_sel = _add_row(box, "圈数")
	for v in ["2", "3", "5"]:
		laps_sel.add_item(v + " 圈", int(v))
	laps_sel.select(1)
	diff_sel = _add_row(box, "AI 强度")
	diff_sel.add_item("轻松")
	diff_sel.add_item("标准")
	diff_sel.add_item("硬核")
	diff_sel.select(1)

	garage_best = Label.new()
	garage_best.text = ""
	garage_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	garage_best.add_theme_font_size_override("font_size", 15)
	garage_best.add_theme_color_override("font_color", Color(0.98, 0.75, 0.25))
	box.add_child(garage_best)

	btn_start = Button.new()
	btn_start.text = "开 始 比 赛"
	btn_start.custom_minimum_size = Vector2(0, 52)
	btn_start.add_theme_font_size_override("font_size", 24)
	box.add_child(btn_start)

	btn_roam = Button.new()
	btn_roam.text = "自 由 漫 游"
	btn_roam.custom_minimum_size = Vector2(0, 40)
	btn_roam.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_roam)

	btn_battle = Button.new()
	btn_battle.text = "大 战 场"
	btn_battle.custom_minimum_size = Vector2(0, 40)
	btn_battle.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_battle)

	btn_plane = Button.new()
	btn_plane.text = "漫 游 战 机"
	btn_plane.custom_minimum_size = Vector2(0, 40)
	btn_plane.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_plane)

	btn_shop = Button.new()
	btn_shop.text = "配 件 店"
	btn_shop.custom_minimum_size = Vector2(0, 40)
	btn_shop.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_shop)

	btn_gunshop = Button.new()
	btn_gunshop.text = "枪 械 店"
	btn_gunshop.custom_minimum_size = Vector2(0, 40)
	btn_gunshop.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_gunshop)

	btn_carinfo = Button.new()
	btn_carinfo.text = "车 辆 数 据"
	btn_carinfo.custom_minimum_size = Vector2(0, 40)
	btn_carinfo.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_carinfo)

	btn_npc_solid = Button.new()
	btn_npc_solid.text = "NPC 碰撞：开"
	btn_npc_solid.custom_minimum_size = Vector2(0, 40)
	btn_npc_solid.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_npc_solid)

	btn_editor = Button.new()
	btn_editor.text = "地 图 编 译 器"
	btn_editor.custom_minimum_size = Vector2(0, 40)
	btn_editor.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_editor)
	btn_city = Button.new()
	btn_city.text = "城 市 编 辑 器"
	btn_city.custom_minimum_size = Vector2(0, 40)
	btn_city.add_theme_font_size_override("font_size", 18)
	box.add_child(btn_city)

	var hint := Label.new()
	hint.text = "W/↑ 油门 · S/↓ 刹车 · A D/← → 转向 · 空格 手刹漂移\nC 切换镜头 · R 回到赛道 · P/Esc 暂停 · M 静音\n车库菜单按 W/↑ 直接出发：出生在卷帘门车库，踩油门顶门驶出"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.66))
	box.add_child(hint)

	# ---- 底部：车型展示条 ----
	var car_bar := PanelContainer.new()
	car_bar.add_theme_stylebox_override("panel", _panel_stylebox())
	car_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	car_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	car_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	car_bar.position.y = -24
	screen.add_child(car_bar)

	var car_box := HBoxContainer.new()
	car_box.add_theme_constant_override("separation", 18)
	car_bar.add_child(car_box)

	btn_prev_car = Button.new()
	btn_prev_car.text = "◀"
	btn_prev_car.custom_minimum_size = Vector2(56, 56)
	btn_prev_car.add_theme_font_size_override("font_size", 26)
	car_box.add_child(btn_prev_car)

	var car_box_mid := VBoxContainer.new()
	car_box_mid.add_theme_constant_override("separation", 0)
	car_box_mid.custom_minimum_size = Vector2(240, 0)
	car_name_label = Label.new()
	car_name_label.text = ""
	car_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_name_label.add_theme_font_size_override("font_size", 24)
	car_box_mid.add_child(car_name_label)
	car_desc_label = Label.new()
	car_desc_label.text = ""
	car_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_desc_label.add_theme_font_size_override("font_size", 13)
	car_desc_label.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
	car_box_mid.add_child(car_desc_label)
	car_box.add_child(car_box_mid)

	btn_next_car = Button.new()
	btn_next_car.text = "▶"
	btn_next_car.custom_minimum_size = Vector2(56, 56)
	btn_next_car.add_theme_font_size_override("font_size", 26)
	car_box.add_child(btn_next_car)

	# ---- 左下角操作提示 ----
	var drag_hint := Label.new()
	drag_hint.text = "按住鼠标左键拖动 · 环视爱车"
	drag_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	drag_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	drag_hint.position = Vector2(18, -20)
	drag_hint.add_theme_font_size_override("font_size", 14)
	drag_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.76))
	drag_hint.add_theme_constant_override("outline_size", 6)
	drag_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	screen.add_child(drag_hint)


func _add_row(box: VBoxContainer, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(96, 0)
	lab.add_theme_font_size_override("font_size", 17)
	row.add_child(lab)
	var sel := OptionButton.new()
	sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sel)
	box.add_child(row)
	return sel


func set_best_lap_menu(ms) -> void:
	if ms != null and is_finite(ms):
		garage_best.text = "本作最快圈：" + RRUtil.format_time(ms)
	else:
		garage_best.text = "本作最快圈：暂无纪录"


## 配件店界面：三分区（发动机/轮胎/漂移胎）选项行 + 返回
## 状态由 game.refresh_shop(...) 驱动；选项点击发 shop_equip(slot, opt)
func _build_shop() -> void:
	var screen := Control.new()
	screen.name = "shop"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(screen)
	_screens["shop"] = screen

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(430, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "配 件 店"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	shop_car_label = Label.new()
	shop_car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_car_label.add_theme_font_size_override("font_size", 16)
	shop_car_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	box.add_child(shop_car_label)

	shop_coins_label = Label.new()
	shop_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_coins_label.add_theme_font_size_override("font_size", 17)
	shop_coins_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	box.add_child(shop_coins_label)

	for slot in TrackData.PART_SLOTS:
		var sid: String = slot["id"]
		var sec := VBoxContainer.new()
		sec.add_theme_constant_override("separation", 4)
		box.add_child(sec)
		_shop_slot_boxes[sid] = sec
		var head := Label.new()
		head.text = "【%s】" % slot["name"]
		head.add_theme_font_size_override("font_size", 16)
		head.add_theme_color_override("font_color", Color(0.98, 0.75, 0.25))
		sec.add_child(head)
		for opt in TrackData.PART_OPTIONS[sid]:
			var oid: String = opt["id"]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			sec.add_child(row)
			var name_lab := Label.new()
			name_lab.text = "%s · %s" % [opt["name"], opt["desc"]]
			name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lab.add_theme_font_size_override("font_size", 14)
			name_lab.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
			row.add_child(name_lab)
			var b := Button.new()
			b.custom_minimum_size = Vector2(96, 30)
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(func(): shop_equip.emit(sid, oid))
			row.add_child(b)
			_shop_rows["%s|%s" % [sid, oid]] = {"btn": b, "note": name_lab}

	var back := Button.new()
	back.text = "返 回 车 库"
	back.custom_minimum_size = Vector2(0, 42)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(func(): shop_back.emit())
	box.add_child(back)


## 刷新配件店各行状态（owned/equipped/价格/余额），漂移胎分区按车型显隐
func refresh_shop(car_name: String, coins: int, equipped: Dictionary, owned: Array,
		is_drift_car: bool) -> void:
	shop_car_label.text = "当前车辆：" + car_name
	shop_coins_label.text = "金币：%d" % coins
	for slot in TrackData.PART_SLOTS:
		var sid: String = slot["id"]
		var sec: VBoxContainer = _shop_slot_boxes[sid]
		sec.visible = is_drift_car or not slot.get("drift_only", false)
		if sec.visible:
			continue
	for slot in TrackData.PART_SLOTS:
		var sid2: String = slot["id"]
		if not (_shop_slot_boxes[sid2] as VBoxContainer).visible:
			continue
		var eq_id: String = equipped.get(sid2, "stock" if sid2 != "drift" else "none")
		for opt in TrackData.PART_OPTIONS[sid2]:
			var oid: String = opt["id"]
			var info: Dictionary = _shop_rows["%s|%s" % [sid2, oid]]
			var b: Button = info["btn"]
			var is_eq := eq_id == oid
			var owned_here: bool = oid == "stock" or oid == "none" or owned.has(oid)
			if is_eq:
				b.text = "已装备"
				b.disabled = true
			elif owned_here:
				b.text = "装 备"
				b.disabled = false
			else:
				b.text = "%d 金币" % opt["price"]
				b.disabled = coins < opt["price"]
			info["note"].add_theme_color_override("font_color",
					Color(0.55, 1.0, 0.55) if is_eq else Color(0.8, 0.84, 0.9))


## 枪械店界面：枪械列表（已装备/装备/价格）+ 金币 + 返回
func _build_gunshop() -> void:
	var screen := Control.new()
	screen.name = "gunshop"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(screen)
	_screens["gunshop"] = screen

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "枪 械 店"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	_gunshop_coins = Label.new()
	_gunshop_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gunshop_coins.add_theme_font_size_override("font_size", 17)
	_gunshop_coins.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	box.add_child(_gunshop_coins)

	for g in Guns.GUNS:
		var gid: String = g["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var name_lab := Label.new()
		name_lab.text = "%s · %s" % [g["name"], g["desc"]]
		name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lab.add_theme_font_size_override("font_size", 14)
		name_lab.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
		row.add_child(name_lab)
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 30)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): gun_equip.emit(gid))
		row.add_child(b)
		gunshop_rows[gid] = {"btn": b, "note": name_lab}

	var ammo_head := Label.new()
	ammo_head.text = "【弹　药】"
	ammo_head.add_theme_font_size_override("font_size", 16)
	ammo_head.add_theme_color_override("font_color", Color(0.98, 0.75, 0.25))
	box.add_child(ammo_head)
	for a in Guns.AMMO:
		var aid: String = a["id"]
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 8)
		box.add_child(arow)
		var alab := Label.new()
		alab.text = "%s · %s" % [a["name"], a["desc"]]
		alab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		alab.add_theme_font_size_override("font_size", 14)
		alab.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
		arow.add_child(alab)
		var ab := Button.new()
		ab.custom_minimum_size = Vector2(110, 30)
		ab.add_theme_font_size_override("font_size", 14)
		ab.pressed.connect(func(): ammo_equip.emit(aid))
		arow.add_child(ab)
		_ammo_rows[aid] = {"btn": ab, "note": alab}

	var back := Button.new()
	back.text = "返 回 车 库"
	back.custom_minimum_size = Vector2(0, 42)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(func(): gunshop_back.emit())
	box.add_child(back)


## 刷新枪械店各行状态（枪械 + 弹药）
func refresh_gunshop(coins: int, owned: Array, equipped: String,
		ammo_type: String) -> void:
	_gunshop_coins.text = "金币：%d" % coins
	for g in Guns.GUNS:
		var gid: String = g["id"]
		var info: Dictionary = gunshop_rows[gid]
		var b: Button = info["btn"]
		var is_eq: bool = equipped == gid
		var is_owned: bool = owned.has(gid)
		if is_eq:
			b.text = "已装备"
			b.disabled = true
		elif is_owned:
			b.text = "装 备"
			b.disabled = false
		else:
			b.text = "%d 金币" % Guns.gun_by_id(gid)["price"]
			b.disabled = coins < Guns.gun_by_id(gid)["price"]
		info["note"].add_theme_color_override("font_color",
				Color(0.55, 1.0, 0.55) if is_eq else Color(0.8, 0.84, 0.9))
	for a in Guns.AMMO:
		var aid: String = a["id"]
		var info: Dictionary = _ammo_rows[aid]
		var b: Button = info["btn"]
		var is_eq2: bool = ammo_type == aid
		var is_owned2: bool = aid == "standard" or owned.has(aid)
		if is_eq2:
			b.text = "使用中"
			b.disabled = true
		elif is_owned2:
			b.text = "使 用"
			b.disabled = false
		else:
			b.text = "%d 金币" % Guns.ammo_by_id(aid)["price"]
			b.disabled = coins < Guns.ammo_by_id(aid)["price"]
		info["note"].add_theme_color_override("font_color",
				Color(0.55, 1.0, 0.55) if is_eq2 else Color(0.8, 0.84, 0.9))


## 车辆数据界面：马力/极速/牵引/抓地/制动（基础 → 当前，配件加成标注）
func _build_carinfo() -> void:
	var screen := Control.new()
	screen.name = "carinfo"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(screen)
	_screens["carinfo"] = screen

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(430, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "车 辆 数 据"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var car_lab := Label.new()
	car_lab.name = "CarinfoCar"
	car_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_lab.add_theme_font_size_override("font_size", 16)
	car_lab.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	box.add_child(car_lab)
	_carinfo_car_label = car_lab

	info_rows = Label.new()
	info_rows.text = ""
	info_rows.add_theme_font_size_override("font_size", 16)
	box.add_child(info_rows)

	var back := Button.new()
	back.text = "返 回 车 库"
	back.custom_minimum_size = Vector2(0, 42)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(func(): shop_back.emit())
	box.add_child(back)


## 刷新车辆数据文本（text 由 game.gd 组好：含基础→当前与颜色标注）
func refresh_carinfo(car_name: String, text: String) -> void:
	_carinfo_car_label.text = car_name
	info_rows.text = text


func update_car_label(car_name: String, car_dsc: String) -> void:
	car_name_label.text = car_name
	car_desc_label.text = car_dsc


## 单圈制赛道：圈数选择禁用并显示固定圈数
func set_laps_locked(locked: bool, laps: int) -> void:
	laps_sel.disabled = locked
	if locked:
		laps_sel.clear()
		laps_sel.add_item("%d 圈（单圈制）" % laps, laps)
		laps_sel.select(0)


func update_track_desc(text: String) -> void:
	track_desc.text = text


# ================= 漫游 HUD =================

func _build_roam_hud() -> void:
	var screen := Control.new()
	screen.name = "roam"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(screen)
	_screens["roam"] = screen

	var hint := Label.new()
	hint.text = ROAM_HINT_GARAGE
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y = TOP_ROW2_Y   # 时钟占第一行，提示放第二行（原来 y=14 与时钟 y=8 叠字）
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_constant_override("outline_size", 8)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	screen.add_child(hint)
	_roam_hint = hint

	var keys := Label.new()
	keys.text = "F 上/下车 · 左键 开枪 · 右键 开/关镜 · C 滑铲/切镜头 · Esc 回车库 · R 复位 · N 静音"
	keys.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys.position = Vector2(18, -20)
	keys.add_theme_font_size_override("font_size", 15)
	keys.add_theme_color_override("font_color", Color(0.75, 0.8, 0.86))
	keys.add_theme_constant_override("outline_size", 6)
	keys.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	screen.add_child(keys)

	shop_hint_label = Label.new()
	shop_hint_label.text = "按 Enter 进入配件店"
	shop_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	shop_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	shop_hint_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	shop_hint_label.position.y = 110
	shop_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_hint_label.add_theme_font_size_override("font_size", 22)
	shop_hint_label.add_theme_constant_override("outline_size", 8)
	shop_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	shop_hint_label.visible = false
	screen.add_child(shop_hint_label)

	gunshop_hint_label = Label.new()
	gunshop_hint_label.text = "按 Enter 进入枪械店"
	gunshop_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	gunshop_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gunshop_hint_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	gunshop_hint_label.position.y = 110
	gunshop_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gunshop_hint_label.add_theme_font_size_override("font_size", 22)
	gunshop_hint_label.add_theme_constant_override("outline_size", 8)
	gunshop_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	gunshop_hint_label.visible = false
	screen.add_child(gunshop_hint_label)


## 漫游靠近商店时显示进入提示（text 可区分配件店/枪械店）
func set_shop_hint(on: bool, text: String = "按 Enter 进入配件店") -> void:
	shop_hint_label.text = text
	shop_hint_label.visible = on


## 漫游靠近枪械店时显示进入提示
func set_gunshop_hint(on: bool) -> void:
	gunshop_hint_label.visible = on


## 通缉指示标签
func _build_wanted() -> void:
	wanted_label = Label.new()
	wanted_label.text = "通缉中 · 甩开警察！"
	wanted_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wanted_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wanted_label.position.y = TOP_ROW3_Y
	wanted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wanted_label.add_theme_font_size_override("font_size", 24)
	wanted_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	wanted_label.add_theme_constant_override("outline_size", 8)
	wanted_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	wanted_label.visible = false
	_root.add_child(wanted_label)


## 车库 NPC 碰撞开关按钮文字
func set_npc_solid_label(on: bool) -> void:
	btn_npc_solid.text = "NPC 碰撞：%s" % ("开" if on else "关")


# ================= 暂停 =================

func _panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.94)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	return sb


## 大战场顶栏：我方兵力 ｜ 敌军兵力·波次 ｜ 玩家击杀
func _build_battle_hud() -> void:
	var screen := Control.new()
	screen.name = "battle"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.04, 0.05, 0.08, 0.72)
	bs.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("panel", bs)
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = TOP_ROW2_Y   # 同漫游提示：让出第一行给时钟
	bar.visible = false           # 攻防推进版目标栏由 battle_hud.gd 绘制，旧战况条停用
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	battle_lbl_ally = Label.new()
	battle_lbl_ally.add_theme_font_size_override("font_size", 20)
	battle_lbl_ally.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
	battle_lbl_enemy = Label.new()
	battle_lbl_enemy.add_theme_font_size_override("font_size", 20)
	battle_lbl_enemy.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	battle_lbl_kill = Label.new()
	battle_lbl_kill.add_theme_font_size_override("font_size", 20)
	battle_lbl_kill.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	battle_lbl_plane = Label.new()
	battle_lbl_plane.add_theme_font_size_override("font_size", 20)
	battle_lbl_plane.add_theme_color_override("font_color", Color(0.55, 0.9, 0.95))
	row.add_child(battle_lbl_ally)
	row.add_child(battle_lbl_enemy)
	row.add_child(battle_lbl_kill)
	row.add_child(battle_lbl_plane)
	bar.add_child(row)
	screen.add_child(bar)
	# 登机提示（底部中央）
	board_hint = Label.new()
	board_hint.text = "按 F 登机"
	board_hint.add_theme_font_size_override("font_size", 19)
	board_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	board_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	board_hint.position.y = -84.0
	board_hint.visible = false
	screen.add_child(board_hint)
	_screens["battle"] = screen
	_root.add_child(screen)


func set_battle_top(allies: int, enemies: int, wave: int, kills: int,
		plane_txt: String = "") -> void:
	battle_lbl_ally.text = "我方 %d" % allies
	battle_lbl_enemy.text = "敌军 %d · 第 %d 波" % [enemies, wave]
	battle_lbl_kill.text = "击杀 %d" % kills
	battle_lbl_plane.text = plane_txt


func set_board_hint(on: bool, text: String = "按 F 登机") -> void:
	board_hint.text = text
	board_hint.visible = on


func _build_pause() -> void:
	var screen := Control.new()
	screen.name = "pause"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(screen)
	_screens["pause"] = screen
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(300, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	btn_resume = _add_button(box, "继续比赛")
	btn_restart = _add_button(box, "重新开始")
	btn_quit_pause = _add_button(box, "回到车库")


func _add_button(box: VBoxContainer, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 19)
	box.add_child(b)
	return b


# ================= 结算 =================

func _build_results() -> void:
	var screen := Control.new()
	screen.name = "results"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(screen)
	_screens["results"] = screen
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "比赛结算"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	results_grid = GridContainer.new()
	results_grid.columns = 4
	results_grid.add_theme_constant_override("h_separation", 26)
	results_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(results_grid)
	btn_again = _add_button(box, "再来一局")
	btn_quit_results = _add_button(box, "回到车库")


func show_results(rows: Array) -> void:
	for c in results_grid.get_children():
		c.free()   # 立即移除旧行（本函数不在信号回调中执行）
	var headers := ["名次", "车手", "总时间", "最快圈"]
	for h in headers:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		results_grid.add_child(l)
	for r in rows:
		var pos_l := Label.new()
		pos_l.text = "P%d" % r["pos"]
		if r["isPlayer"]:
			pos_l.add_theme_color_override("font_color", Color(0.98, 0.75, 0.25))
		results_grid.add_child(pos_l)
		var name_l := Label.new()
		name_l.text = r["name"]
		var ls := LabelSettings.new()
		ls.font = RRFont.get_font()
		ls.font_color = team_colors[r["teamIdx"]]
		name_l.label_settings = ls
		results_grid.add_child(name_l)
		var time_l := Label.new()
		time_l.text = r["time"]
		results_grid.add_child(time_l)
		var best_l := Label.new()
		best_l.text = r["bestLap"]
		results_grid.add_child(best_l)


func hide_loading() -> void:
	pass   # Godot 版无加载遮罩，保留接口兼容


## 步行模式 HUD：准星/三倍镜遮罩 + 血条 + 弹药
func _build_gun_overlay() -> void:
	gun_overlay = Control.new()
	gun_overlay.name = "GunHud"
	gun_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	gun_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gun_overlay.draw.connect(_draw_gun_overlay.bind(gun_overlay))
	_root.add_child(gun_overlay)
	_dmg_rect = ColorRect.new()
	_dmg_rect.color = Color(0.8, 0.05, 0.05)
	_dmg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_rect.visible = false
	_root.add_child(_dmg_rect)
	gun_overlay.visible = false


func _draw_gun_overlay(cv: Control) -> void:
	var sz: Vector2 = cv.size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	if _gun_scope:
		# 三倍镜：只有黑色镜框边圈 + 十字线 + 红点，视野不再压暗
		var r := minf(sz.x, sz.y) * 0.42
		cv.draw_arc(Vector2(cx, cy), r, 0, TAU, 64, Color(0.05, 0.05, 0.06), 10.0)
		cv.draw_line(Vector2(cx - r, cy), Vector2(cx + r, cy), Color(0.08, 0.09, 0.1, 0.85), 2.0)
		cv.draw_line(Vector2(cx, cy - r), Vector2(cx, cy + r), Color(0.08, 0.09, 0.1, 0.85), 2.0)
		cv.draw_circle(Vector2(cx, cy), 2.5, Color(0.9, 0.15, 0.1))
	else:
		# 腰射准星：四段短线 + 中点
		cv.draw_circle(Vector2(cx, cy), 2.0, Color(1, 1, 1, 0.9))
		for d in [Vector2(-10, 0), Vector2(10, 0), Vector2(0, -10), Vector2(0, 10)]:
			cv.draw_line(Vector2(cx, cy) + d * 0.6, Vector2(cx, cy) + d, Color(1, 1, 1, 0.85), 2.0)
	# 血条（左下）
	var bw := 190.0
	var bh := 12.0
	var bx := 20.0
	var by := sz.y - 34.0
	cv.draw_rect(Rect2(bx - 2, by - 2, bw + 4, bh + 4), Color(0, 0, 0, 0.55))
	var ratio := clampf(_gun_hp / 100.0, 0.0, 1.0)
	var col := Color(0.35, 0.9, 0.3) if ratio > 0.35 else Color(0.95, 0.25, 0.2)
	cv.draw_rect(Rect2(bx, by, bw * ratio, bh), col)
	cv.draw_string(ThemeDB.fallback_font, Vector2(bx, by - 6), "生命",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.92, 0.95))
	# 弹药（右下）
	var ammo_txt := "换弹中…" if _gun_reload > 0.0 else "%d / ∞" % _gun_ammo
	if _gun_name != "":
		ammo_txt = _gun_name + "  " + ammo_txt
	# 右对齐贴右边：原来固定从 sz.x-130 起画，枪名一长（「突击步枪 30 / ∞」）就出屏
	cv.draw_string(ThemeDB.fallback_font, Vector2(sz.x - 420.0, sz.y - 40.0),
			ammo_txt, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 20, Color(1.0, 0.85, 0.35))


func _process_gun(dt: float) -> void:
	if _gun_reload > 0.0:
		_gun_reload = maxf(0.0, _gun_reload - dt)
	if gun_overlay.visible:
		gun_overlay.queue_redraw()


func set_onfoot(on: bool) -> void:
	gun_overlay.visible = on
	if not on:
		_gun_scope = false


func set_scope(on: bool) -> void:
	_gun_scope = on
	gun_overlay.queue_redraw()


func set_health(hp: float) -> void:
	_gun_hp = hp
	gun_overlay.queue_redraw()


## 步行 HUD 枪名
func set_gun_name(name: String) -> void:
	_gun_name = name
	gun_overlay.queue_redraw()


func set_ammo(ammo: int, reloading: float, gun_name: String = "") -> void:
	_gun_ammo = ammo
	_gun_reload = reloading
	_gun_name = gun_name
	gun_overlay.queue_redraw()


func damage_flash() -> void:
	_dmg_flash_t = 0.25
