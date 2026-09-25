extends Control
## 大战场界面（参考三角洲「全面战场」）：顶部目标栏（区域 / A·B 据点 / 兵力）、
## 据点占领进度、战场小地图、击杀播报、命中标记、受击方向、计分板（Tab）、
## 阵营选择与部署界面（兵种 + 出生点）。数据直接读 RRBattleField。
## （按路径 preload，不注册 class_name：见 loading_screen.gd 顶注）

signal side_chosen(side: String)
signal deploy_requested(cls: int, spawn_i: int)

const FRIEND := Color(0.35, 0.65, 1.0)
const ENEMY := Color(0.95, 0.32, 0.26)
const NEUTRAL := Color(0.6, 0.6, 0.6)
const PANEL_BG := Color(0.04, 0.05, 0.08, 0.78)
const MAP_W := 230.0
const MAP_H := 184.0

var bf                           # RRBattleField
var player_yaw := 0.0
var scoreboard_on := false
var _feed: Array = []            # [{text_parts, t}]
var _hit_t := 0.0
var _hit_kill := false
var _hit_head := false
var _dmg_dirs: Array = []        # [{pos, t}]
var _banner := ""
var _banner_sub := ""
var _banner_t := 0.0
var _gadget_txt := ""
var _gadget_ready := 1.0         # 0..1 冷却进度

# ---- 部署界面 ----
var _deploy: Control
var _side_box: Control
var _cls_box: Control
var _cls_btns: Array = []
var _spawn_box: VBoxContainer
var _deploy_btn: Button
var _deploy_hint: Label
var _sel_cls := 0
var _sel_spawn := 0
var _spawn_opts: Array = []
var respawn_wait := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 挂在 HUD CanvasLayer 下、不在 _root 主题树里：必须自带中文字体主题，
	# 否则回退字体缺「敌」等简体字，击杀播报/计分板出方框
	var th := Theme.new()
	th.default_font = RRFont.get_font()
	th.default_font_size = 16
	theme = th


func setup(bf_ref) -> void:
	bf = bf_ref
	_build_deploy()


func _process(dt: float) -> void:
	_hit_t = maxf(0.0, _hit_t - dt)
	_banner_t = maxf(0.0, _banner_t - dt)
	for f in _feed:
		f["t"] = float(f["t"]) - dt
	_feed = _feed.filter(func(f): return float(f["t"]) > 0.0)
	for d in _dmg_dirs:
		d["t"] = float(d["t"]) - dt
	_dmg_dirs = _dmg_dirs.filter(func(d): return float(d["t"]) > 0.0)
	if respawn_wait > 0.0:
		respawn_wait = maxf(0.0, respawn_wait - dt)
		_update_deploy_btn()
	if visible:
		queue_redraw()


# ================= 事件入口（game 调） =================

func add_kill(info: Dictionary) -> void:
	var kt: String = info.get("killer_team", "")
	var vt: String = info.get("victim_team", "")
	var mine: String = bf.player_team
	var wname := _weapon_name(str(info.get("weapon", "")))
	_feed.push_front({"killer": str(info.get("killer", "")),
			"kcol": FRIEND if kt == mine else ENEMY,
			"victim": str(info.get("victim", "")),
			"vcol": FRIEND if vt == mine else ENEMY,
			"weapon": wname + (" · 爆头" if info.get("head", false) else ""),
			"me": info.get("by_player", false) or info.get("player_died", false),
			"t": 6.0})
	if _feed.size() > 6:
		_feed.resize(6)


func hitmark(kill: bool, head: bool) -> void:
	_hit_t = 0.28 if kill else 0.16
	_hit_kill = kill
	_hit_head = head


func damage_from(pos: Vector3) -> void:
	_dmg_dirs.append({"pos": pos, "t": 1.3})


func banner(text: String, sub: String, sec := 3.0) -> void:
	_banner = text
	_banner_sub = sub
	_banner_t = sec


func set_gadget(text: String, ready_k: float) -> void:
	_gadget_txt = text
	_gadget_ready = ready_k


static func _weapon_name(id: String) -> String:
	match id:
		"rifle":
			return "突击步枪"
		"smg":
			return "冲锋枪"
		"lmg":
			return "轻机枪"
		"sniper":
			return "狙击步枪"
		"":
			return ""
	return id


# ================= 绘制 =================

func _draw() -> void:
	if bf == null or not bf.active:
		return
	var sz := size
	var font := get_theme_default_font()
	_draw_objectives(sz, font)
	_draw_capture(sz, font)
	_draw_minimap(sz, font)
	_draw_feed(sz, font)
	if bf.player_alive and not _deploy.visible:
		_draw_hitmark(sz)
		if bf.veh.player_v >= 0:
			_draw_vehicle(sz, font)
		else:
			_draw_dmg_dirs(sz)
			_draw_gadget(sz, font)
			_draw_enter_hint(sz, font)
	if _banner_t > 0.0:
		var a := clampf(_banner_t / 0.4, 0.0, 1.0)
		draw_string(font, Vector2(0, sz.y * 0.32), _banner, HORIZONTAL_ALIGNMENT_CENTER,
				sz.x, 40, Color(1, 0.9, 0.5, a))
		draw_string(font, Vector2(0, sz.y * 0.32 + 34), _banner_sub,
				HORIZONTAL_ALIGNMENT_CENTER, sz.x, 18, Color(1, 1, 1, 0.85 * a))
	if scoreboard_on or bf.battle_over:
		_draw_scoreboard(sz, font)


func _team_col(owner: String) -> Color:
	return FRIEND if owner == bf.player_team else ENEMY


## 顶部目标栏：[进攻方兵力]  第 N 区 · 名称  [A] [B]  [防守方]
func _draw_objectives(sz: Vector2, font: Font) -> void:
	var y := 42.0
	var cx := sz.x * 0.5
	draw_rect(Rect2(cx - 250, y - 4, 500, 58), PANEL_BG)
	var si: int = mini(bf.sector, bf.pts.size() - 1)
	var sname: String = bf.bmap.SECTORS[si]["name"]
	var title := "第 %d / %d 区 · %s" % [si + 1, bf.pts.size(), sname]
	if bf.sector >= bf.pts.size():
		title = "全部区域已攻陷"
	draw_string(font, Vector2(cx - 250, y + 14), title, HORIZONTAL_ALIGNMENT_CENTER, 500, 15,
			Color(0.95, 0.95, 0.95))
	# 左：进攻方兵力；右：防守方
	var atk_col := _team_col("atk")
	var def_col := _team_col("def")
	draw_string(font, Vector2(cx - 240, y + 14), "进攻方", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, atk_col)
	draw_string(font, Vector2(cx - 240, y + 44), str(maxi(bf.tickets, 0)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, atk_col)
	draw_string(font, Vector2(cx + 140, y + 14), "防守方", HORIZONTAL_ALIGNMENT_RIGHT, 100, 13, def_col)
	draw_string(font, Vector2(cx + 140, y + 44), "%d 人" % bf.count_alive("def"),
			HORIZONTAL_ALIGNMENT_RIGHT, 100, 20, def_col)
	# A / B 据点方块（填充 = 进攻方占领进度）
	if bf.sector < bf.pts.size():
		for pi in 2:
			var p: Dictionary = bf.pts[bf.sector][pi]
			var bx := cx - 62 + pi * 70
			var r := Rect2(bx, y + 20, 54, 30)
			draw_rect(r, Color(0.1, 0.1, 0.12, 0.9))
			var prog: float = p["prog"]
			draw_rect(Rect2(bx, y + 20, 54 * prog, 30), atk_col * Color(1, 1, 1, 0.85))
			draw_rect(Rect2(bx + 54 * prog, y + 20, 54 * (1.0 - prog), 30),
					def_col * Color(1, 1, 1, 0.55))
			var contested: bool = int(p["atk_n"]) > 0 and int(p["def_n"]) > 0
			draw_rect(r, Color(1, 0.85, 0.3) if contested else Color(1, 1, 1, 0.5), false, 2.0)
			draw_string(font, Vector2(bx, y + 42), "AB"[pi], HORIZONTAL_ALIGNMENT_CENTER, 54, 20,
					Color.WHITE)


## 站在据点里：占领进度条
func _draw_capture(sz: Vector2, font: Font) -> void:
	var pi: int = bf.player_point()
	if pi < 0:
		return
	var p: Dictionary = bf.pts[bf.sector][pi]
	var mine: String = bf.player_team
	var an: int = p["atk_n"]
	var dn: int = p["def_n"]
	var txt := ""
	if an > 0 and dn > 0 and an == dn:
		txt = "据点争夺中"
	elif (mine == "atk" and an > dn and p["owner"] != "atk") \
			or (mine == "def" and dn > an and float(p["prog"]) > 0.0):
		txt = "正在占领 %d%s" % [bf.sector + 1, "AB"[pi]]
	elif p["owner"] == mine:
		txt = "据点 %d%s 已控制" % [bf.sector + 1, "AB"[pi]]
	else:
		txt = "敌方优势 · 需要增援"
	var k: float = p["prog"] if mine == "atk" else 1.0 - float(p["prog"])
	var w := 300.0
	var x := sz.x * 0.5 - w * 0.5
	var y := sz.y * 0.68
	draw_string(font, Vector2(x, y - 8), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 17, Color.WHITE)
	draw_rect(Rect2(x, y, w, 8), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(x, y, w * k, 8), FRIEND)
	draw_string(font, Vector2(x, y + 26), "我方 %d  ·  敌方 %d" % [
			an if mine == "atk" else dn, dn if mine == "atk" else an],
			HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1, 1, 1, 0.8))


func _w2m(p: Vector3, org: Vector2) -> Vector2:
	return org + Vector2((p.x + bf.bmap.ARENA_X) / (bf.bmap.ARENA_X * 2.0) * MAP_W,
			(p.z + bf.bmap.ARENA_Z) / (bf.bmap.ARENA_Z * 2.0) * MAP_H)


## 战场小地图（北 = -Z 在上）：据点 / 两个基地 / 友军 / 被发现的敌人 / 自己
func _draw_minimap(sz: Vector2, font: Font) -> void:
	var org := Vector2(sz.x - MAP_W - 14, 14)
	draw_rect(Rect2(org, Vector2(MAP_W, MAP_H)), Color(0.18, 0.15, 0.11, 0.82))
	draw_rect(Rect2(org, Vector2(MAP_W, MAP_H)), Color(1, 1, 1, 0.35), false, 1.0)
	for si in bf.pts.size():
		for pi in 2:
			var c: Vector3 = bf.bmap.point_pos(si, pi)
			var mp := _w2m(c, org)
			var col := _team_col(bf.pts[si][pi]["owner"])
			if si > bf.sector:
				col = NEUTRAL
			var rr := 7.0 if si == bf.sector else 5.0
			draw_circle(mp, rr, col * Color(1, 1, 1, 0.9))
			draw_string(font, mp + Vector2(-6, 4), "AB"[pi], HORIZONTAL_ALIGNMENT_CENTER, 12, 10,
					Color.WHITE)
	var ab: Vector3 = bf.atk_base()
	var db: Vector3 = bf.def_base()
	draw_rect(Rect2(_w2m(ab, org) - Vector2(4, 4), Vector2(8, 8)), _team_col("atk"))
	draw_rect(Rect2(_w2m(db, org) - Vector2(4, 4), Vector2(8, 8)), _team_col("def"))
	# 载具：方块 + 类型字（敌方载具动静大，始终可见）
	for v in bf.veh.vehicles:
		if v["dead"]:
			continue
		var vp := _w2m(v["pos"], org)
		var vc := FRIEND if v["team"] == bf.player_team else ENEMY
		draw_rect(Rect2(vp - Vector2(5, 5), Vector2(10, 10)), vc)
		draw_string(font, vp + Vector2(-5, 4), {"tank": "坦", "ifv": "车", "heli": "机"}[v["type"]],
				HORIZONTAL_ALIGNMENT_CENTER, 10, 8, Color.WHITE)
	for s in bf.soldiers:
		if s["dead"]:
			continue
		var friendly: bool = s["team"] == bf.player_team
		if not friendly and float(s["spotted_t"]) <= 0.0:
			continue
		draw_circle(_w2m(s["pos"], org), 2.2, FRIEND if friendly else ENEMY)
	if bf.player_alive:
		var pp := _w2m(bf.player_pos, org)
		var fwd := Vector2(sin(player_yaw), cos(player_yaw))
		var rt := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([pp + fwd * 7.0, pp - fwd * 4.0 + rt * 4.0,
				pp - fwd * 4.0 - rt * 4.0]), Color(1.0, 0.85, 0.25))


## 击杀播报（右侧，小地图下方）
func _draw_feed(sz: Vector2, font: Font) -> void:
	var x := sz.x - 14.0
	var y := 14.0 + MAP_H + 24.0
	for f in _feed:
		var a := clampf(float(f["t"]) / 0.6, 0.0, 1.0)
		var parts := [[str(f["killer"]), f["kcol"]], ["  " + str(f["weapon"]) + "  ",
				Color(0.85, 0.85, 0.85)], [str(f["victim"]), f["vcol"]]]
		if str(f["killer"]) == "":
			parts = [["阵亡  ", Color(0.85, 0.85, 0.85)], [str(f["victim"]), f["vcol"]]]
		var total := 0.0
		for pr in parts:
			total += font.get_string_size(pr[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var bx := x - total - 12.0
		draw_rect(Rect2(bx, y - 15, total + 12, 21),
				Color(0.6, 0.45, 0.1, 0.55 * a) if f["me"] else Color(0, 0, 0, 0.45 * a))
		var cx := bx + 6.0
		for pr in parts:
			var c: Color = pr[1]
			draw_string(font, Vector2(cx, y), pr[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Color(c.r, c.g, c.b, a))
			cx += font.get_string_size(pr[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		y += 24.0


func _draw_hitmark(sz: Vector2) -> void:
	if _hit_t <= 0.0:
		return
	var c := sz * 0.5
	var col := Color(1.0, 0.2, 0.15) if _hit_kill else (Color(1.0, 0.85, 0.3) if _hit_head
			else Color.WHITE)
	var r1 := 6.0
	var r2 := 13.0 if _hit_kill else 11.0
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var n: Vector2 = d.normalized()
		draw_line(c + n * r1, c + n * r2, col, 2.5)


## 受击方向：屏幕中心外一圈红色弧，指向伤害来源
func _draw_dmg_dirs(sz: Vector2) -> void:
	var c := sz * 0.5
	for d in _dmg_dirs:
		var to: Vector3 = d["pos"] - bf.player_pos
		var ang_world := atan2(to.x, to.z)
		var rel := wrapf(ang_world - player_yaw, -PI, PI)
		# 屏幕：正前方在上
		var ang := -PI * 0.5 - rel
		var a := clampf(float(d["t"]) / 0.5, 0.0, 1.0)
		draw_arc(c, 90.0, ang - 0.35, ang + 0.35, 16, Color(1.0, 0.15, 0.1, 0.75 * a), 6.0)


func _draw_gadget(sz: Vector2, font: Font) -> void:
	if _gadget_txt == "":
		return
	var x := sz.x - 250.0
	var y := sz.y - 78.0
	var ready := _gadget_ready >= 1.0
	draw_rect(Rect2(x, y, 230, 22), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(x, y, 230 * _gadget_ready, 22),
			Color(0.3, 0.7, 0.35, 0.6) if ready else Color(0.5, 0.5, 0.5, 0.45))
	draw_string(font, Vector2(x + 8, y + 16), "G  " + _gadget_txt + ("" if ready else "  冷却中"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## 驾驶载具：准星 + 底部面板（车名/耐久/主副武器装填）
func _draw_vehicle(sz: Vector2, font: Font) -> void:
	var v: Dictionary = bf.veh.vehicles[bf.veh.player_v]
	var td: Dictionary = bf.veh.type_def(v)
	var c := sz * 0.5
	draw_arc(c, 18.0, 0, TAU, 32, Color(1, 1, 1, 0.85), 1.5)
	draw_circle(c, 2.0, Color(1, 1, 1, 0.9))
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + d * 22.0, c + d * 30.0, Color(1, 1, 1, 0.8), 2.0)
	var w := 380.0
	var x := sz.x * 0.5 - w * 0.5
	var y := sz.y - 104.0
	draw_rect(Rect2(x, y, w, 78), PANEL_BG)
	var hp_k := clampf(float(v["hp"]) / float(td["hp"]), 0.0, 1.0)
	draw_string(font, Vector2(x + 12, y + 20), "%s   耐久 %d" % [td["name"], int(v["hp"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_rect(Rect2(x + 12, y + 28, w - 24, 8), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(x + 12, y + 28, (w - 24) * hp_k, 8),
			Color(0.35, 0.85, 0.35) if hp_k > 0.35 else Color(0.95, 0.3, 0.2))
	var wy := y + 56.0
	for wi in 2:
		var wd: Dictionary = td["main"] if wi == 0 else td["sec"]
		if wd.is_empty():
			continue
		var cd_left: float = v["main_cd"] if wi == 0 else v["sec_cd"]
		var k := 1.0 - clampf(cd_left / float(wd["cd"]), 0.0, 1.0)
		var wx := x + 12 + wi * (w * 0.5)
		draw_string(font, Vector2(wx, wy), ("左键 " if wi == 0 else "右键 ") + str(wd["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.9))
		draw_rect(Rect2(wx, wy + 6, w * 0.5 - 30, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(wx, wy + 6, (w * 0.5 - 30) * k, 5),
				Color(1.0, 0.8, 0.3) if k >= 1.0 else Color(0.6, 0.6, 0.6))
	draw_string(font, Vector2(x, y - 8), "F 下车", HORIZONTAL_ALIGNMENT_CENTER, w, 13,
			Color(1, 1, 1, 0.7))


## 步行靠近本方载具：F 上车提示
func _draw_enter_hint(sz: Vector2, font: Font) -> void:
	var k: int = bf.veh.nearest_enterable(bf.player_pos, bf.player_team)
	if k < 0:
		return
	var name: String = bf.veh.type_def(bf.veh.vehicles[k])["name"]
	draw_string(font, Vector2(0, sz.y * 0.6), "按 F 驾驶 " + name, HORIZONTAL_ALIGNMENT_CENTER,
			sz.x, 20, Color(1.0, 0.9, 0.4))


## 计分板（Tab 按住 / 战斗结束常驻）
func _draw_scoreboard(sz: Vector2, font: Font) -> void:
	var w := 820.0
	var h := 470.0
	var org := Vector2(sz.x * 0.5 - w * 0.5, sz.y * 0.5 - h * 0.5 + 20)
	draw_rect(Rect2(org, Vector2(w, h)), Color(0.03, 0.04, 0.06, 0.88))
	var head := "计分板"
	if bf.battle_over:
		var won: bool = (bf.atk_win and bf.player_team == "atk") \
				or (not bf.atk_win and bf.player_team == "def")
		head = ("胜  利" if won else "失  败") + "   ·   " + \
				("进攻方攻陷全部区域" if bf.atk_win else "进攻方兵力耗尽") + "   ·   Enter 返回车库"
	draw_string(font, org + Vector2(0, 32), head, HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color.WHITE)
	for col_i in 2:
		var team: String = bf.player_team if col_i == 0 else ("def" if bf.player_team == "atk" else "atk")
		var cx := org.x + 16.0 + col_i * (w * 0.5)
		var tc := FRIEND if col_i == 0 else ENEMY
		draw_string(font, Vector2(cx, org.y + 66), ("我方 · " if col_i == 0 else "敌方 · ")
				+ ("进攻" if team == "atk" else "防守"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tc)
		draw_string(font, Vector2(cx + 200, org.y + 66), "击杀  阵亡   得分",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.8))
		var rows: Array = bf.scoreboard(team)
		for r in mini(rows.size(), 16):
			var row: Dictionary = rows[r]
			var ry := org.y + 92 + r * 22
			if row["me"]:
				draw_rect(Rect2(cx - 6, ry - 15, w * 0.5 - 20, 20), Color(0.7, 0.55, 0.15, 0.4))
			var cls_name: String = bf.CLASSES[int(row["cls"])]["name"]
			draw_string(font, Vector2(cx, ry), "%s  [%s]" % [row["name"], cls_name],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			draw_string(font, Vector2(cx + 200, ry), "%3d   %3d   %5d" % [row["kills"],
					row["deaths"], row["score"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Color(0.9, 0.9, 0.9))


# ================= 部署界面 =================

func _build_deploy() -> void:
	_deploy = Control.new()
	_deploy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deploy.mouse_filter = Control.MOUSE_FILTER_STOP
	_deploy.visible = false
	add_child(_deploy)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deploy.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deploy.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	# 阵营选择
	_side_box = VBoxContainer.new()
	_side_box.add_theme_constant_override("separation", 10)
	col.add_child(_side_box)
	var st := _label("选择阵营", 30)
	_side_box.add_child(st)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 20)
	_side_box.add_child(srow)
	for side in [["atk", "进 攻 方", "兵力有限 · 依次夺下 3 个区域的 A/B 据点"],
			["def", "防 守 方", "守住据点 · 耗尽进攻方兵力即胜"]]:
		var b := Button.new()
		b.text = "%s\n%s" % [side[1], side[2]]
		b.custom_minimum_size = Vector2(300, 110)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): side_chosen.emit(side[0]))
		srow.add_child(b)
	# 兵种
	_cls_box = VBoxContainer.new()
	_cls_box.add_theme_constant_override("separation", 12)
	col.add_child(_cls_box)
	_cls_box.add_child(_label("选择兵种", 26))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 12)
	_cls_box.add_child(crow)
	for ci in 4:
		var cd: Dictionary = RRBattleField.CLASSES[ci]
		var b2 := Button.new()
		b2.toggle_mode = true
		b2.text = "%s\n%s\n道具：%s\n生命 %d" % [cd["name"], _weapon_name(cd["gun"]),
				cd["gadget_name"], int(cd["hp"])]
		b2.custom_minimum_size = Vector2(150, 118)
		b2.add_theme_font_size_override("font_size", 16)
		b2.pressed.connect(func(): _select_cls(ci))
		crow.add_child(b2)
		_cls_btns.append(b2)
	_cls_box.add_child(_label("出生点", 20))
	_spawn_box = VBoxContainer.new()
	_spawn_box.add_theme_constant_override("separation", 6)
	_cls_box.add_child(_spawn_box)
	_deploy_btn = Button.new()
	_deploy_btn.text = "部 署（空格）"
	_deploy_btn.custom_minimum_size = Vector2(0, 52)
	_deploy_btn.add_theme_font_size_override("font_size", 22)
	_deploy_btn.pressed.connect(try_deploy)
	_cls_box.add_child(_deploy_btn)
	_deploy_hint = _label("", 15)
	_cls_box.add_child(_deploy_hint)
	_select_cls(0)


func _label(t: String, size_px: int) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	return l


func _select_cls(ci: int) -> void:
	_sel_cls = ci
	for i in _cls_btns.size():
		(_cls_btns[i] as Button).button_pressed = i == ci


## 打开部署界面：need_side=首次进场先选阵营；wait=重生倒计时秒
func open_deploy(need_side: bool, wait: float) -> void:
	_deploy.visible = true
	_side_box.visible = need_side
	_cls_box.visible = not need_side
	respawn_wait = wait
	if not need_side:
		refresh_spawns()
	_update_deploy_btn()


func close_deploy() -> void:
	_deploy.visible = false


func deploy_open() -> bool:
	return _deploy.visible


func refresh_spawns() -> void:
	for c in _spawn_box.get_children():
		c.queue_free()
	_spawn_opts = bf.spawn_options(bf.player_team)
	_sel_spawn = clampi(_sel_spawn, 0, _spawn_opts.size() - 1)
	for i in _spawn_opts.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = i == _sel_spawn
		b.text = _spawn_opts[i]["label"]
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			_sel_spawn = i
			for j in _spawn_box.get_child_count():
				(_spawn_box.get_child(j) as Button).button_pressed = j == i)
		_spawn_box.add_child(b)


func _update_deploy_btn() -> void:
	if _deploy_btn == null:
		return
	var no_tickets: bool = bf != null and bf.player_team == "atk" and bf.tickets <= 0
	_deploy_btn.disabled = respawn_wait > 0.0 or no_tickets
	if no_tickets:
		_deploy_hint.text = "进攻方兵力已耗尽"
	elif respawn_wait > 0.0:
		_deploy_hint.text = "%.0f 秒后可部署" % ceilf(respawn_wait)
	else:
		_deploy_hint.text = "点击出生点切换 · 1-4 切换兵种"


func try_deploy() -> void:
	if not _deploy.visible or not _cls_box.visible or _deploy_btn.disabled:
		return
	deploy_requested.emit(_sel_cls, _sel_spawn)


func spawn_pos(i: int) -> Vector3:
	if _spawn_opts.is_empty():
		_spawn_opts = bf.spawn_options(bf.player_team)
	return _spawn_opts[clampi(i, 0, _spawn_opts.size() - 1)]["pos"]


func select_cls_key(ci: int) -> void:
	if _deploy.visible and _cls_box.visible:
		_select_cls(ci)
