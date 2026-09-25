class_name RRBattleField
extends Node3D
## 大战场（攻防推进，参考三角洲「全面战场」）：进攻方 24 人按顺序夺取 3 个区域
## （每区 A/B 两据点），兵力（重生票数）耗尽即失败；防守方守住即胜。
## 士兵分突击/工程/支援/侦察四个兵种。鸭子类型顶替 onfoot 的 npc 位：
## raycast(from,dir,max_d) 同契约；player_shot(kind,idx,dmg) 结算玩家命中。

signal player_hit(dmg: float, from: Vector3)
signal killed(info: Dictionary)        # 击杀播报：见 _report_kill
signal hitmark(kill: bool, head: bool) # 玩家命中反馈
signal point_changed(si: int, pi: int, owner: String)
signal sector_captured(si: int)
signal over(atk_win: bool)
signal explosion_at(pos: Vector3)

const TEAM_SIZE := 24
const ATK_TICKETS := 150
const SECTOR_BONUS := 40          # 每夺下一个区域补充的进攻方兵力
const CAPTURE_TIME := 18.0        # 一人占领所需秒数（人数优势最多 ×3）
const RESPAWN_AI := 9.0
const AI_TICK := 1.0 / 60.0       # 士兵 AI 定步（与物理 120Hz 解耦）
const HEAD_MUL := 2.0

## 兵种：生命/移速/主武器数值（AI 与玩家共用一套定义；gun 为玩家枪械 id）
const CLASSES := [
	{"id": "assault", "name": "突击", "hp": 100.0, "speed": 7.6,
		"dmg": [7.0, 11.0], "cd": 0.11, "burst": 4, "range": 75.0, "acc": 0.05,
		"gun": "rifle", "gadget": "grenade", "gadget_name": "手雷", "gadget_cd": 12.0},
	{"id": "engineer", "name": "工程", "hp": 100.0, "speed": 7.6,
		"dmg": [6.0, 9.0], "cd": 0.08, "burst": 6, "range": 55.0, "acc": 0.06,
		"gun": "smg", "gadget": "rpg", "gadget_name": "火箭筒", "gadget_cd": 14.0},
	{"id": "support", "name": "支援", "hp": 115.0, "speed": 6.6,
		"dmg": [7.0, 10.0], "cd": 0.09, "burst": 9, "range": 80.0, "acc": 0.07,
		"gun": "lmg", "gadget": "medkit", "gadget_name": "医疗包", "gadget_cd": 20.0},
	{"id": "recon", "name": "侦察", "hp": 90.0, "speed": 7.2,
		"dmg": [38.0, 52.0], "cd": 1.5, "burst": 1, "range": 150.0, "acc": 0.012,
		"gun": "sniper", "gadget": "scan", "gadget_name": "侦察信标", "gadget_cd": 25.0},
]
const BattleVehicles := preload("res://scripts/battle_vehicles.gd")
const TracerPool := preload("res://scripts/tracer_pool.gd")
## 两队呼号分开（同名会让击杀播报分不清是哪边的人）
const CALLSIGNS := {
	"atk": ["猎鹰", "山猫", "黑曜", "北风", "赤狐", "雷鸣"],
	"def": ["夜枭", "磐石", "疾风", "铁砧", "苍狼", "寒霜"],
}

var bmap                          # BattleMap
var audio                         # RRAudio

var active := false
var battle_over := false
var atk_win := false
var player_team := "atk"          # 玩家阵营：atk 进攻 / def 防守
var player_pos := Vector3.ZERO
var player_alive := false
var player_cls := 0
var player_stats := {"kills": 0, "deaths": 0, "score": 0}

var sector := 0                   # 当前争夺区域（0..2）；=3 表示进攻方已全部拿下
var tickets := ATK_TICKETS
var pts: Array = []               # [sector][point] -> {owner, prog(0守..1攻), atk_n, def_n}
var soldiers: Array = []          # 两队 48 人（死亡后原地复用重生）

var _t := 0.0
var _ai_acc := 0.0
var _cap_acc := 0.0
var _snd_budget := 6.0
var _tracers                      # 曳光弹（tracer_pool.gd）
var _im_pool: Array = []
var _im_i := 0
var _ex_pool: Array = []
var _ex_i := 0
var _mm := {}                     # team -> MultiMesh 部件
var projectiles: Array = []       # 手雷/火箭/炮弹 {kind, vis, pos, vel, t, team, src, dmg, vdmg, r, weapon}
var veh                           # 载具（battle_vehicles.gd）


func setup(bmap_ref, audio_ref) -> void:
	bmap = bmap_ref
	audio = audio_ref
	_setup_fx()
	_setup_explosions()
	_setup_army_mm("atk")
	_setup_army_mm("def")
	veh = BattleVehicles.new()
	add_child(veh)
	veh.setup(self)


# ================= 开局 =================

func start(side: String) -> void:
	active = true
	battle_over = false
	atk_win = false
	player_team = side
	player_alive = false
	player_stats = {"kills": 0, "deaths": 0, "score": 0}
	sector = 0
	tickets = ATK_TICKETS
	_clear_projectiles()
	pts.clear()
	for si in bmap.SECTORS.size():
		var row: Array = []
		for pi in 2:
			row.append({"owner": "def", "prog": 0.0, "atk_n": 0, "def_n": 0})
		pts.append(row)
	soldiers.clear()
	for team in ["atk", "def"]:
		for slot in TEAM_SIZE:
			# 玩家那一队少一个 AI（玩家顶位），保持 24 v 24
			if team == player_team and slot == TEAM_SIZE - 1:
				continue
			var s := _make_soldier(team, slot)
			_respawn(s)
			soldiers.append(s)
	_apply_team_colors()
	_refresh_point_colors()
	veh.start()


func _make_soldier(team: String, slot: int) -> Dictionary:
	var cls: int = [0, 0, 0, 1, 1, 2, 2, 3][slot % 8]   # 突击多、侦察少
	return {
		"team": team, "slot": slot, "cls": cls,
		"name": "%s-%02d" % [CALLSIGNS[team][slot % 6], slot + 1],
		"pos": Vector3.ZERO, "yaw": 0.0, "hp": 100.0, "dead": true,
		"respawn_t": 0.0, "tgt_i": -1, "tgt_player": false,
		"fire_cd": randf_range(0.5, 1.5), "burst": 0, "mag": 30, "reload_t": 0.0,
		"los_ok": false, "los_t": randf_range(0.0, 0.4), "tgt_t": randf_range(0.0, 0.5),
		"strafe_t": 0.0, "strafe_dir": 1.0, "phase": randf() * TAU, "moving": false,
		"goal": Vector3.ZERO, "goal_t": 0.0, "nade_cd": randf_range(8.0, 20.0),
		"kills": 0, "deaths": 0, "score": 0, "spotted_t": 0.0, "last_hit_by": -1,
		"block_t": 0.0, "detour_t": 0.0, "detour_dir": Vector2.ZERO, "pose_n": 0,
		"rpg_cd": randf_range(4.0, 10.0), "aa_t": 0.0,
	}


# ================= 据点 / 区域 =================

## 进攻方当前前进基地：第 1 区打之前在集结地，之后移到上一个区域后方
func atk_base() -> Vector3:
	if sector <= 0:
		return bmap.ATK_HQ
	var prev: Array = bmap.SECTORS[mini(sector, bmap.SECTORS.size()) - 1]["pts"]
	var mid: Vector2 = (prev[0] + prev[1]) * 0.5
	return Vector3(mid.x, 0, mid.y + 24.0)


## 防守方出兵点：当前区域据点后方约 45m（原来放在下一区域后面，
## 援兵要跑 100m+，第 2 区 40 秒就被拿下）；最后一区退守总部
func def_base() -> Vector3:
	if sector >= bmap.SECTORS.size() - 1:
		return bmap.DEF_HQ
	var cur: Array = bmap.SECTORS[sector]["pts"]
	var mid: Vector2 = (cur[0] + cur[1]) * 0.5
	return Vector3(mid.x, 0, mid.y - 45.0)


## 某阵营当前可选出生点：[{label, pos}]（基地 + 本方占有且未被争夺的据点）
func spawn_options(team: String) -> Array:
	var out: Array = [{"label": "前进基地" if team == "atk" else "防守阵地",
			"pos": atk_base() if team == "atk" else def_base()}]
	# 只有进攻方能在已占据点出生（三角洲同款）：防守方若能在据点里无限刷新，
	# 进攻方永远进不了圈
	if team == "atk" and sector < pts.size():
		for pi in 2:
			var p: Dictionary = pts[sector][pi]
			var enemy_n: int = p["def_n"] if team == "atk" else p["atk_n"]
			if p["owner"] == team and enemy_n == 0:
				out.append({"label": "据点 %d%s" % [sector + 1, "AB"[pi]],
						"pos": bmap.point_pos(sector, pi)})
	return out


func _update_capture(dt: float) -> void:
	if sector >= pts.size():
		return
	for pi in 2:
		var p: Dictionary = pts[sector][pi]
		var c: Vector3 = bmap.point_pos(sector, pi)
		var an := 0
		var dn := 0
		for s in soldiers:
			if s["dead"]:
				continue
			if Vector2(s["pos"].x - c.x, s["pos"].z - c.z).length() < bmap.POINT_R:
				if s["team"] == "atk":
					an += 1
				else:
					dn += 1
		if player_counts() and Vector2(player_pos.x - c.x, player_pos.z - c.z).length() \
				< bmap.POINT_R:
			if player_team == "atk":
				an += 1
			else:
				dn += 1
		p["atk_n"] = an
		p["def_n"] = dn
		var rate := dt / CAPTURE_TIME
		var prog: float = p["prog"]
		if an > dn:
			prog += rate * minf(float(an - dn), 3.0)
		elif dn > an:
			prog -= rate * minf(float(dn - an), 3.0)
		elif an == 0:
			# 没人在圈里：进度慢慢回落到当前归属
			prog = move_toward(prog, 1.0 if p["owner"] == "atk" else 0.0, dt / 30.0)
		prog = clampf(prog, 0.0, 1.0)
		p["prog"] = prog
		var new_owner: String = p["owner"]
		if prog >= 1.0:
			new_owner = "atk"
		elif prog <= 0.0:
			new_owner = "def"
		if new_owner != p["owner"]:
			p["owner"] = new_owner
			_award_capture(sector, pi, new_owner)
			point_changed.emit(sector, pi, new_owner)
			_refresh_point_colors()
	if pts[sector][0]["owner"] == "atk" and pts[sector][1]["owner"] == "atk":
		var done := sector
		sector += 1
		tickets += SECTOR_BONUS
		for s in soldiers:
			s["goal_t"] = 0.0   # 立即换目标
		sector_captured.emit(done)
		_refresh_point_colors()
		if sector >= pts.size():
			_finish(true)


## 夺点奖励：圈内的占领方每人 +200 分
func _award_capture(si: int, pi: int, owner: String) -> void:
	var c: Vector3 = bmap.point_pos(si, pi)
	for s in soldiers:
		if not s["dead"] and s["team"] == owner \
				and Vector2(s["pos"].x - c.x, s["pos"].z - c.z).length() < bmap.POINT_R:
			s["score"] = int(s["score"]) + 200
	if player_alive and player_team == owner \
			and Vector2(player_pos.x - c.x, player_pos.z - c.z).length() < bmap.POINT_R:
		player_stats["score"] = int(player_stats["score"]) + 200


func _refresh_point_colors() -> void:
	for si in pts.size():
		for pi in 2:
			var owner: String = pts[si][pi]["owner"]
			var friendly: bool = owner == player_team
			var col := Color(0.3, 0.6, 1.0) if friendly else Color(0.95, 0.3, 0.25)
			if si < sector:
				col = Color(0.3, 0.6, 1.0) if player_team == "atk" else Color(0.95, 0.3, 0.25)
			elif si > sector:
				col = Color(0.55, 0.55, 0.55)   # 未开放区域：灰
			bmap.set_point_color(si, pi, col, si == sector)


## 玩家是否计入占点：步行或开地面车算，飞在天上的直升机不算
func player_counts() -> bool:
	if not player_alive:
		return false
	var pv: Dictionary = veh.player_vehicle()
	return pv.is_empty() or pv["type"] != "heli"


## 玩家当前站在哪个据点圈里（-1 = 不在）
func player_point() -> int:
	if not player_counts() or sector >= pts.size():
		return -1
	for pi in 2:
		var c: Vector3 = bmap.point_pos(sector, pi)
		if Vector2(player_pos.x - c.x, player_pos.z - c.z).length() < bmap.POINT_R:
			return pi
	return -1


# ================= 主更新 =================

func update(dt: float) -> void:
	_t += dt
	_snd_budget = minf(_snd_budget + dt * 6.0, 6.0)
	_tick_fx(dt)
	_tick_explosions(dt)
	_update_projectiles(dt)
	if not active or battle_over:
		return
	veh.update(dt)
	_cap_acc += dt
	if _cap_acc >= 0.1:
		_update_capture(_cap_acc)
		_cap_acc = 0.0
	_ai_acc += dt
	var steps := 0
	while _ai_acc >= AI_TICK and steps < 3:
		_ai_acc -= AI_TICK
		steps += 1
		for i in soldiers.size():
			_update_soldier(i, AI_TICK)
	if not battle_over and tickets <= 0 and sector < pts.size():
		# 兵力耗尽：场上已无存活进攻方（含玩家）即判负
		var alive := player_alive and player_team == "atk"
		for s in soldiers:
			if s["team"] == "atk" and not s["dead"]:
				alive = true
				break
		if not alive:
			_finish(false)


func _finish(did_atk_win: bool) -> void:
	battle_over = true
	atk_win = did_atk_win
	over.emit(atk_win)


func count_alive(team: String) -> int:
	var n := 0
	for s in soldiers:
		if s["team"] == team and not s["dead"]:
			n += 1
	if player_alive and player_team == team:
		n += 1
	return n


# ================= 士兵 AI =================

func _update_soldier(i: int, dt: float) -> void:
	var s: Dictionary = soldiers[i]
	s["spotted_t"] = maxf(0.0, float(s["spotted_t"]) - dt)
	if s["dead"]:
		s["respawn_t"] = float(s["respawn_t"]) - dt
		if float(s["respawn_t"]) <= 0.0 and (s["team"] == "def" or tickets > 0):
			if s["team"] == "atk":
				tickets -= 1
			_respawn(s)
			_write_pose(s)
		return
	var cd: Dictionary = CLASSES[s["cls"]]
	# 目标（错峰 0.5s）：最近的敌人，可含玩家
	s["tgt_t"] = float(s["tgt_t"]) - dt
	if float(s["tgt_t"]) <= 0.0:
		s["tgt_t"] = randf_range(0.45, 0.65)
		_pick_target(i, s, float(cd["range"]) * 1.25)
	# 目标点（据点任务）
	s["goal_t"] = float(s["goal_t"]) - dt
	if float(s["goal_t"]) <= 0.0:
		_pick_goal(s)
	var t_pos := Vector3.ZERO
	var has_t := false
	if s["tgt_player"] and player_alive:
		t_pos = player_pos + Vector3(0, 1.2, 0)
		has_t = true
	elif int(s["tgt_i"]) >= 0 and not soldiers[s["tgt_i"]]["dead"]:
		t_pos = soldiers[s["tgt_i"]]["pos"] + Vector3(0, 1.2, 0)
		has_t = true
	var dist := INF
	if has_t:
		var to_t: Vector3 = t_pos - s["pos"]
		dist = Vector2(to_t.x, to_t.z).length()
		s["los_t"] = float(s["los_t"]) - dt
		if float(s["los_t"]) <= 0.0:
			s["los_t"] = 0.4
			s["los_ok"] = _los(s["pos"] + Vector3(0, 1.5, 0), t_pos)
	var engaged: bool = has_t and s["los_ok"] and dist < float(cd["range"])
	# 走位：交火中近距侧移 / 远距缓进；否则奔向任务点
	var move := Vector2.ZERO
	var to_g: Vector3 = s["goal"] - s["pos"]
	var gd := Vector2(to_g.x, to_g.z).length()
	var gdir := Vector2(to_g.x, to_g.z) / maxf(gd, 0.01)
	var face := gdir
	if engaged:
		var tdir := Vector2(t_pos.x - s["pos"].x, t_pos.z - s["pos"].z) / maxf(dist, 0.01)
		face = tdir
		if dist < 22.0:
			s["strafe_t"] = float(s["strafe_t"]) - dt
			if float(s["strafe_t"]) <= 0.0:
				s["strafe_t"] = randf_range(1.5, 3.5)
				s["strafe_dir"] = -float(s["strafe_dir"])
			move = Vector2(-tdir.y, tdir.x) * float(s["strafe_dir"])
		elif gd > 3.0 and s["team"] == "atk" and s["cls"] != 3:
			move = gdir * 0.55   # 边打边压
	elif gd > 2.0:
		move = gdir
	_apply_move(s, move, face, float(cd["speed"]), dt)
	# 离玩家远的士兵每 3 个 tick 才写一次姿态（MultiMesh 写入是 AI 的大头开销）
	s["pose_n"] = int(s["pose_n"]) + 1
	if int(s["pose_n"]) >= 3 or s["pos"].distance_squared_to(player_pos) < 100.0 * 100.0:
		s["pose_n"] = 0
		_write_pose(s)
	_anti_vehicle(i, s, dt, engaged)
	if engaged:
		_try_fire(i, s, t_pos, dist, dt)
		# 突击兵：中距离对着扎堆的目标扔手雷
		s["nade_cd"] = float(s["nade_cd"]) - dt
		if s["cls"] == 0 and float(s["nade_cd"]) <= 0.0 and dist > 12.0 and dist < 32.0:
			s["nade_cd"] = randf_range(18.0, 30.0)
			_ai_grenade(i, s, t_pos)


## 反载具：工程兵 70m 内有视线就打火箭（带提前量）；
## 其他兵种手头没步兵目标时拿枪打低空直升机
func _anti_vehicle(i: int, s: Dictionary, dt: float, engaged: bool) -> void:
	s["rpg_cd"] = float(s["rpg_cd"]) - dt
	s["aa_t"] = float(s["aa_t"]) - dt
	if s["cls"] == 1 and float(s["rpg_cd"]) <= 0.0:
		s["rpg_cd"] = 1.0
		var k: int = _nearest_enemy_vehicle(s, 55.0, false, true)
		if k >= 0:
			var v: Dictionary = veh.vehicles[k]
			var eye: Vector3 = s["pos"] + Vector3(0, 1.5, 0)
			var tgt: Vector3 = v["pos"] + Vector3(0, 1.2, 0)
			var lead: Vector3 = Vector3(sin(v["yaw"]), 0, cos(v["yaw"])) * float(v["speed"]) \
					* eye.distance_to(tgt) / 75.0
			tgt += lead
			if _los(eye, tgt):
				s["rpg_cd"] = randf_range(20.0, 30.0)
				s["yaw"] = atan2(tgt.x - eye.x, tgt.z - eye.z)
				spawn_projectile("rocket", eye + (tgt - eye).normalized() * 0.8,
						(tgt - eye).normalized() * 75.0, s["team"], i, 120.0, 260.0, 4.5,
						"火箭筒", -1)
		return
	if not engaged and float(s["aa_t"]) <= 0.0:
		s["aa_t"] = randf_range(0.3, 0.6)
		var k2: int = _nearest_enemy_vehicle(s, 70.0, true)
		if k2 >= 0:
			var v2: Dictionary = veh.vehicles[k2]
			var eye2: Vector3 = s["pos"] + Vector3(0, 1.45, 0)
			var d2: Vector3 = (v2["pos"] - eye2).normalized()
			d2 = (d2 + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.08).normalized()
			s["yaw"] = atan2(d2.x, d2.z)
			s["spotted_t"] = 2.0
			hitscan(eye2, d2, 80.0, randf_range(7.0, 10.0), s["team"], i,
					CLASSES[s["cls"]]["gun"], eye2, -1)


## heli_only：只找直升机（对空）；ground_only：只找地面车（火箭打不中直升机）
func _nearest_enemy_vehicle(s: Dictionary, max_d: float, heli_only := false,
		ground_only := false) -> int:
	var best := -1
	var bd := max_d
	for k in veh.vehicles.size():
		var v: Dictionary = veh.vehicles[k]
		if v["dead"] or v["team"] == s["team"] or (heli_only and v["type"] != "heli") \
				or (ground_only and v["type"] == "heli"):
			continue
		var d: float = s["pos"].distance_to(v["pos"])
		if d < bd:
			bd = d
			best = k
	return best


func _pick_target(i: int, s: Dictionary, max_d: float) -> void:
	var bd := max_d * max_d
	var best := -1
	var sp := Vector2(s["pos"].x, s["pos"].z)
	for j in soldiers.size():
		var f: Dictionary = soldiers[j]
		if f["dead"] or f["team"] == s["team"]:
			continue
		var d2 := sp.distance_squared_to(Vector2(f["pos"].x, f["pos"].z))
		if d2 < bd:
			bd = d2
			best = j
	s["tgt_i"] = best
	s["tgt_player"] = false
	if player_alive and player_team != s["team"] and veh.player_v < 0:
		var pd2 := sp.distance_squared_to(Vector2(player_pos.x, player_pos.z))
		if pd2 < bd:
			s["tgt_i"] = -1
			s["tgt_player"] = true
	s["los_t"] = 0.0   # 换目标立即测视线


## 任务点：进攻方冲据点圈；防守方在据点周围布防，被争夺时回援圈内；侦察兵退后架枪
func _pick_goal(s: Dictionary) -> void:
	s["goal_t"] = randf_range(6.0, 10.0)
	if sector >= pts.size():
		s["goal"] = bmap.DEF_HQ
		return
	var pi: int = int(s["slot"]) % 2
	var p: Dictionary = pts[sector][pi]
	var other: Dictionary = pts[sector][1 - pi]
	var c: Vector3 = bmap.point_pos(sector, pi)
	if s["team"] == "atk":
		if p["owner"] == "atk" and other["owner"] != "atk":
			pi = 1 - pi   # 本点已拿下：支援另一个点
			c = bmap.point_pos(sector, pi)
		var r := randf_range(2.0, 8.0) if s["cls"] != 3 else randf_range(35.0, 55.0)
		var ang := randf() * TAU
		if s["cls"] == 3:
			ang = randf_range(-0.6, 0.6)   # 侦察兵在据点南侧（进攻方来向）远处架枪
		s["goal"] = c + Vector3(sin(ang) * r, 0, cos(ang) * r)
	else:
		# 本点被争夺或已失守：收进圈内夺回；否则在周围布防
		var contested: bool = int(p["atk_n"]) > 0 or p["owner"] == "atk"
		var r2 := randf_range(2.0, 9.0) if contested else randf_range(6.0, 18.0)
		var ang2 := randf() * TAU
		if s["cls"] == 3:
			r2 = randf_range(30.0, 50.0)
			ang2 = PI + randf_range(-0.6, 0.6)   # 据点北侧（防守方后方）
		s["goal"] = c + Vector3(sin(ang2) * r2, 0, cos(ang2) * r2)
	var g: Vector3 = s["goal"]
	s["goal"] = Vector3(clampf(g.x, -236.0, 236.0), 0, clampf(g.z, -186.0, 186.0))


func _respawn(s: Dictionary) -> void:
	var opts := spawn_options(s["team"])
	var o: Dictionary = opts[randi() % opts.size()]
	var p: Vector3 = o["pos"]
	var jitter := Vector2(randf_range(-14.0, 14.0), randf_range(-6.0, 6.0))
	if o["label"].begins_with("据点"):
		jitter = Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	var np: Vector2 = bmap.push_out(p.x + jitter.x, p.z + jitter.y, 0.6)
	s["pos"] = Vector3(np.x, bmap.terrain_height(np.x, np.y), np.y)
	s["dead"] = false
	s["hp"] = float(CLASSES[s["cls"]]["hp"])
	s["mag"] = 30
	s["reload_t"] = 0.0
	s["tgt_i"] = -1
	s["tgt_player"] = false
	s["goal_t"] = 0.0
	s["yaw"] = PI if s["team"] == "atk" else 0.0


func _apply_move(s: Dictionary, move: Vector2, face: Vector2, speed: float, dt: float) -> void:
	var vel := move * speed
	# 同队间隔（只看附近几人，廉价推挤）
	var sp := Vector2(s["pos"].x, s["pos"].z)
	for o in soldiers:
		if o["dead"] or o["team"] != s["team"] or o["slot"] == s["slot"]:
			continue
		var dv: Vector2 = sp - Vector2(o["pos"].x, o["pos"].z)
		var d := dv.length()
		if d > 0.01 and d < 2.2:
			vel += dv / d * (2.2 - d) * 2.5
	# 绕行：被墙挡住时沿垂直方向横移一阵（没有寻路，房子/集装箱靠这个绕开）
	if float(s["detour_t"]) > 0.0:
		s["detour_t"] = float(s["detour_t"]) - dt
		var dm: Vector2 = s["detour_dir"]
		vel = dm * speed
	var want_step := vel.length() * dt
	var np := sp + vel * dt
	np.x = clampf(np.x, -236.0, 236.0)
	np.y = clampf(np.y, -186.0, 186.0)
	np = bmap.push_out(np.x, np.y, 0.4)
	# 卡墙判定：想走却只走出不到 30%，累计 0.4s 就开始绕
	if want_step > 0.02 and np.distance_to(sp) < want_step * 0.3:
		s["block_t"] = float(s["block_t"]) + dt
		if float(s["block_t"]) > 0.4 and float(s["detour_t"]) <= 0.0:
			s["block_t"] = 0.0
			var side := 1.0 if randf() < 0.5 else -1.0
			s["detour_dir"] = Vector2(-move.y, move.x).normalized() * side \
					if move.length_squared() > 0.01 else Vector2(side, 0)
			s["detour_t"] = randf_range(0.8, 1.6)
	else:
		s["block_t"] = maxf(0.0, float(s["block_t"]) - dt)
	s["pos"] = Vector3(np.x, bmap.terrain_height(np.x, np.y), np.y)
	s["moving"] = move.length_squared() > 0.01
	if face.length_squared() > 0.0001:
		var want := atan2(face.x, face.y)
		s["yaw"] = lerp_angle(float(s["yaw"]), want, 1.0 - exp(-10.0 * dt))


# ================= 开火 / 弹道 =================

func _try_fire(i: int, s: Dictionary, t_pos: Vector3, dist: float, dt: float) -> void:
	var cd: Dictionary = CLASSES[s["cls"]]
	s["fire_cd"] = float(s["fire_cd"]) - dt
	if float(s["fire_cd"]) > 0.0:
		return
	if float(s["reload_t"]) > 0.0:
		s["reload_t"] = float(s["reload_t"]) - dt
		return
	if int(s["mag"]) <= 0:
		s["reload_t"] = 2.2
		s["mag"] = 30
		return
	if int(s["burst"]) <= 0:
		s["burst"] = cd["burst"]
	s["burst"] = int(s["burst"]) - 1
	s["mag"] = int(s["mag"]) - 1
	s["fire_cd"] = float(cd["cd"]) if int(s["burst"]) > 0 else randf_range(0.7, 1.4)
	if s["cls"] == 3:
		s["fire_cd"] = randf_range(1.4, 2.4)
	s["spotted_t"] = 2.0   # 开火暴露在敌方小地图上
	var eye: Vector3 = s["pos"] + Vector3(0, 1.45, 0)
	var dir := (t_pos - eye).normalized()
	var acc: float = cd["acc"] * (1.0 + dist / 60.0)
	dir = (dir + Vector3(randf() - 0.5, (randf() - 0.5) * 0.5, randf() - 0.5) * acc).normalized()
	var muzzle: Vector3 = s["pos"] + Vector3(sin(s["yaw"]) * 0.5, 1.38, cos(s["yaw"]) * 0.5)
	hitscan(eye, dir, float(cd["range"]) + 20.0, randf_range(cd["dmg"][0], cd["dmg"][1]),
			s["team"], i, CLASSES[s["cls"]]["gun"], muzzle, -1)
	var pd: float = s["pos"].distance_to(player_pos)
	if _snd_budget >= 1.0 and pd < 150.0:
		_snd_budget -= 1.0
		audio.play_police_shot(pd)


## 通用即时弹道：命中射线上最近的敌方士兵 / 步行玩家 / 敌方载具 / 墙体。
## src：士兵序号 >=0 / 玩家 -1 / 载具 SRC_VEH-k；skip_v = 开火载具自身
func hitscan(from: Vector3, dir: Vector3, max_d: float, dmg: float, team: String, src: int,
		weapon: String, tracer_from: Vector3, skip_v: int) -> void:
	var best_d := max_d
	var best_j := -1
	var kind := ""
	for j in soldiers.size():
		var f: Dictionary = soldiers[j]
		if f["dead"] or f["team"] == team:
			continue
		var c: Vector3 = f["pos"] + Vector3(0, 1.1, 0)
		var t: float = (c - from).dot(dir)
		if t < 0.5 or t > best_d:
			continue
		if (c - from - dir * t).length() < 0.55:
			best_d = t
			best_j = j
			kind = "soldier"
	if player_alive and player_team != team and veh.player_v < 0:
		var c2: Vector3 = player_pos + Vector3(0, 1.2, 0)
		var t2: float = (c2 - from).dot(dir)
		if t2 > 0.5 and t2 < best_d and (c2 - from - dir * t2).length() < 0.55:
			best_d = t2
			kind = "player"
	var vh: Array = veh.ray_hit(from, dir, best_d, skip_v)
	if int(vh[0]) >= 0 and veh.vehicles[vh[0]]["team"] != team:
		best_d = vh[1]
		best_j = vh[0]
		kind = "vehicle"
	var wall_d := _wall_dist(from, dir, best_d)
	if wall_d < best_d:
		best_d = wall_d
		kind = "wall"
	var end := from + dir * best_d
	_spawn_tracer(tracer_from, end, kind != "")
	match kind:
		"soldier":
			_damage_soldier(best_j, dmg, src, false, weapon)
		"player":
			player_hit.emit(dmg, from)
			player_last_hit_by = src
		"vehicle":
			var v: Dictionary = veh.vehicles[best_j]
			var destroyed: bool = veh.damage(best_j, dmg * float(veh.type_def(v)["armor"]), src, weapon)
			if src == -1:
				hitmark.emit(destroyed, false)
			if best_j == veh.player_v:
				player_last_hit_by = src


var player_last_hit_by := -1      # 最近一次打中玩家（或玩家载具）的来源（阵亡播报用）


## 射线到第一堵墙的距离（最远 max_d，没有则 INF）
func _wall_dist(from: Vector3, dir: Vector3, max_d: float) -> float:
	var d: float = bmap.ray_wall(from, dir, max_d)
	return d if d < max_d else INF


func _los(from: Vector3, to: Vector3) -> bool:
	var d := from.distance_to(to)
	if d < 0.5:
		return true
	return _wall_dist(from, (to - from) / d, d - 0.5) == INF


## 士兵受伤；src = 攻击者士兵序号（-1 = 玩家，-2 = 爆炸无主）
func _damage_soldier(j: int, dmg: float, src: int, head: bool, weapon: String) -> void:
	var s: Dictionary = soldiers[j]
	if s["dead"]:
		return
	s["hp"] = float(s["hp"]) - dmg
	s["last_hit_by"] = src
	if float(s["hp"]) > 0.0:
		return
	s["dead"] = true
	s["moving"] = false
	s["deaths"] = int(s["deaths"]) + 1
	s["respawn_t"] = RESPAWN_AI
	_write_pose(s)
	var info := {"victim": s["name"], "victim_team": s["team"], "weapon": weapon,
			"head": head, "by_player": src == -1, "player_died": false,
			"victim_cls": s["cls"]}
	_credit_kill(info, src, 150 if head else 100)
	killed.emit(info)


## 击杀归属：填 killer/killer_team 并给击杀者记分（玩家 / 士兵 / 载具）
func _credit_kill(info: Dictionary, src: int, pts_gain: int) -> void:
	info["killer"] = ""
	info["killer_team"] = ""
	if src == -1:
		info["killer"] = "你"
		info["killer_team"] = player_team
		info["by_player"] = true
		player_stats["kills"] = int(player_stats["kills"]) + 1
		player_stats["score"] = int(player_stats["score"]) + pts_gain
	elif src >= 0 and src < soldiers.size():
		var k: Dictionary = soldiers[src]
		info["killer"] = k["name"]
		info["killer_team"] = k["team"]
		info["killer_cls"] = k["cls"]
		k["kills"] = int(k["kills"]) + 1
		k["score"] = int(k["score"]) + pts_gain
	elif src <= BattleVehicles.SRC_VEH:
		var vk: int = BattleVehicles.SRC_VEH - src
		if vk < veh.vehicles.size():
			info["killer"] = veh.display_name(vk)
			info["killer_team"] = veh.vehicles[vk]["team"]


func damage_soldier_ext(j: int, dmg: float, src: int, weapon: String) -> void:
	_damage_soldier(j, dmg, src, false, weapon)


## 载具被毁播报（battle_vehicles 调）
func vehicle_destroyed(k: int, src: int, weapon: String) -> void:
	var v: Dictionary = veh.vehicles[k]
	var info := {"victim": veh.display_name(k), "victim_team": v["team"], "weapon": weapon,
			"head": false, "by_player": false, "player_died": false, "vehicle": true}
	_credit_kill(info, src, 300)
	killed.emit(info)


## 玩家阵亡（game 侧判定血量归零后调用）
func report_player_death() -> void:
	player_alive = false
	player_stats["deaths"] = int(player_stats["deaths"]) + 1
	if player_team == "atk":
		tickets -= 1
	var src := player_last_hit_by
	var info := {"victim": "你", "victim_team": player_team, "weapon": "",
			"head": false, "by_player": false, "player_died": true, "victim_cls": player_cls}
	if src != -1:
		_credit_kill(info, src, 100)
		if info.has("killer_cls"):
			info["weapon"] = CLASSES[info["killer_cls"]]["gun"]
	info["by_player"] = false
	info["player_died"] = true
	player_last_hit_by = -1
	killed.emit(info)


## 玩家部署（game 侧选好兵种与出生点后调用）
func player_deploy(cls: int, at: Vector3) -> void:
	player_cls = cls
	player_alive = true
	player_pos = at
	player_last_hit_by = -1


## 玩家子弹结算（game._on_foot_shot 转发）
func player_shot(kind: String, idx: int, dmg: float) -> void:
	if battle_over or idx < 0:
		return
	if kind != "vehicle" and idx >= soldiers.size():
		return
	if kind == "vehicle":
		if idx < veh.vehicles.size() and veh.vehicles[idx]["team"] != player_team:
			var v: Dictionary = veh.vehicles[idx]
			var destroyed: bool = veh.damage(idx, dmg * float(veh.type_def(v)["armor"]), -1,
					CLASSES[player_cls]["gun"])
			hitmark.emit(destroyed, false)
		return
	if kind != "soldier" and kind != "soldier_head":
		return
	var s: Dictionary = soldiers[idx]
	if s["team"] == player_team or s["dead"]:
		return   # 无友伤（子弹已被队友挡下）
	var head := kind == "soldier_head"
	_damage_soldier(idx, dmg * (HEAD_MUL if head else 1.0), -1, head,
			CLASSES[player_cls]["gun"])
	hitmark.emit(s["dead"], head)


## onfoot 子弹射线（同 npc.raycast 契约）：士兵躯干/头部 + 墙体
func raycast(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var best := {"type": "", "i": -1, "d": max_d, "point": from + dir * max_d}
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["dead"]:
			continue
		var hc: Vector3 = s["pos"] + Vector3(0, 1.6, 0)
		var th: float = (hc - from).dot(dir)
		if th > 0.5 and th < best["d"] and (hc - from - dir * th).length() < 0.2:
			best = {"type": "soldier_head", "i": i, "d": th, "point": from + dir * th}
			continue
		var c: Vector3 = s["pos"] + Vector3(0, 1.05, 0)
		var t: float = (c - from).dot(dir)
		if t > 0.5 and t < best["d"] and (c - from - dir * t).length() < 0.5:
			best = {"type": "soldier", "i": i, "d": t, "point": from + dir * t}
	var vh: Array = veh.ray_hit(from, dir, best["d"], veh.player_v)
	if int(vh[0]) >= 0:
		best = {"type": "vehicle", "i": vh[0], "d": vh[1], "point": from + dir * float(vh[1])}
	var wd := _wall_dist(from, dir, best["d"])
	if wd < best["d"]:
		best = {"type": "wall", "i": -1, "d": wd, "point": from + dir * wd}
	return best


# ================= 道具：手雷 / 火箭弹 / 医疗包 / 侦察信标 =================

func _make_proj_vis(rocket: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if rocket:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.09
		cm.height = 0.8
		mi.mesh = cm
		mat.albedo_color = Color(0.3, 0.34, 0.28)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.15)
		mat.emission_energy_multiplier = 0.6
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		mi.mesh = sm
		mat.albedo_color = Color(0.22, 0.28, 0.2)
	mi.material_override = mat
	add_child(mi)
	return mi


## src：-1 玩家，>=0 士兵序号
func throw_grenade(from: Vector3, dir: Vector3, team: String, src: int) -> void:
	spawn_projectile("grenade", from, dir * 19.0 + Vector3(0, 4.5, 0), team, src,
			110.0, 60.0, 7.0, "手雷", -1)


func fire_rocket(from: Vector3, dir: Vector3, team: String, src: int) -> void:
	spawn_projectile("rocket", from, dir * 75.0, team, src, 120.0, 260.0, 4.5, "火箭筒", -1)


## 通用投射物：grenade 抛物线 + 引信；rocket / rockets / shell / cannon 直飞触发。
## dmg 对人、vdmg 对载具、r 爆炸半径；skip_v = 发射载具（不炸自己）
func spawn_projectile(kind: String, from: Vector3, vel: Vector3, team: String, src: int,
		dmg: float, vdmg: float, r: float, weapon: String, skip_v: int) -> void:
	var vis: MeshInstance3D
	if kind == "grenade":
		vis = _make_proj_vis(false)
	elif kind == "rocket" or kind == "rockets":
		vis = _make_proj_vis(true)
	else:
		vis = _make_shell_vis(kind == "shell")
	projectiles.append({"kind": kind, "vis": vis, "pos": from, "vel": vel,
			"t": 1.8 if kind == "grenade" and src >= 0 else (2.2 if kind == "grenade" else 3.5),
			"team": team, "src": src, "dmg": dmg, "vdmg": vdmg, "r": r, "weapon": weapon,
			"skip_v": skip_v})


func _make_shell_vis(big: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 1.2) if big else Vector3(0.07, 0.07, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 3.0
	bm.material = mat
	mi.mesh = bm
	add_child(mi)
	return mi


## 医疗包：自己回满 + 周围 12m 队友 +60
func use_medkit(at: Vector3, team: String) -> int:
	var n := 0
	for s in soldiers:
		if not s["dead"] and s["team"] == team and s["pos"].distance_to(at) < 12.0:
			s["hp"] = minf(float(CLASSES[s["cls"]]["hp"]), float(s["hp"]) + 60.0)
			n += 1
	return n


## 侦察信标：70m 内敌人在小地图上暴露 10 秒
func use_scan(at: Vector3, team: String) -> int:
	var n := 0
	for s in soldiers:
		if not s["dead"] and s["team"] != team and s["pos"].distance_to(at) < 70.0:
			s["spotted_t"] = 10.0
			n += 1
	return n


func _ai_grenade(i: int, s: Dictionary, t_pos: Vector3) -> void:
	var from: Vector3 = s["pos"] + Vector3(0, 1.5, 0)
	var flat := Vector3(t_pos.x - from.x, 0, t_pos.z - from.z)
	var d := flat.length()
	# 按落点距离给水平速度（飞行约 1.1s），稍带误差
	var dir := flat / maxf(d, 0.01)
	spawn_projectile("grenade", from, dir * (d / 1.1) * randf_range(0.85, 1.1)
			+ Vector3(0, 5.5, 0), s["team"], i, 110.0, 60.0, 7.0, "手雷", -1)


func _update_projectiles(dt: float) -> void:
	for k in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[k]
		var v: Vector3 = p["vel"]
		var pos: Vector3 = p["pos"]
		var boom := false
		if p["kind"] == "grenade":
			v.y -= 15.0 * dt
			var np := pos + v * dt
			var gy: float = bmap.terrain_height(np.x, np.z) + 0.1
			if np.y < gy:
				np.y = gy
				v = Vector3(v.x * 0.45, -v.y * 0.3, v.z * 0.45)   # 落地弹跳
			if bmap.solid_at(np):
				v = Vector3(-v.x * 0.4, v.y, -v.z * 0.4)
				np = pos
			pos = np
			p["t"] = float(p["t"]) - dt
			boom = float(p["t"]) <= 0.0
		else:
			if p["kind"] == "shell":
				v.y -= 2.0 * dt
			var np2 := pos + v * dt
			p["t"] = float(p["t"]) - dt
			# 这一步走过的线段上有墙：炸在墙面
			var seg := np2 - pos
			var sl := seg.length()
			var wd: float = bmap.ray_wall(pos, seg / maxf(sl, 0.001), sl) if sl > 0.001 else INF
			if wd < INF:
				np2 = pos + seg / sl * wd
				boom = true
			pos = np2
			if not boom:
				boom = float(p["t"]) <= 0.0 or np2.y < bmap.terrain_height(np2.x, np2.z) + 0.2
			if not boom and veh.hit_test(np2, p["team"], int(p["skip_v"])) >= 0:
				boom = true
			if not boom:
				for s in soldiers:
					if not s["dead"] and s["team"] != p["team"] \
							and (s["pos"] + Vector3(0, 1.0, 0)).distance_to(np2) < 1.0:
						boom = true
						break
			if not boom and player_alive and player_team != p["team"] and veh.player_v < 0 \
					and (player_pos + Vector3(0, 1.0, 0)).distance_to(np2) < 1.0:
				boom = true
		p["vel"] = v
		p["pos"] = pos
		var vis: MeshInstance3D = p["vis"]
		vis.position = pos
		if p["kind"] != "grenade" and v.length_squared() > 0.01:
			vis.look_at(pos + v, Vector3.UP)
			if p["kind"] == "rocket" or p["kind"] == "rockets":
				vis.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		if boom:
			vis.queue_free()
			projectiles.remove_at(k)
			explode_raw(pos, float(p["r"]), float(p["dmg"]), float(p["vdmg"]), p["team"],
					int(p["src"]), str(p["weapon"]))


func _clear_projectiles() -> void:
	for p in projectiles:
		(p["vis"] as Node).queue_free()
	projectiles.clear()


## 爆炸：半径内按距离衰减伤害，不伤友军（team="" 不分敌我，如载具殉爆）；
## 玩家被自己的手雷炸到照样扣血；vdmg 为对载具伤害
func explode_raw(pos: Vector3, radius: float, dmg: float, vdmg: float, team: String, src: int,
		weapon: String) -> void:
	var slot: Dictionary = _ex_pool[_ex_i]
	_ex_i = (_ex_i + 1) % _ex_pool.size()
	slot["mi"].global_position = pos
	slot["light"].global_position = pos + Vector3(0, 1.5, 0)
	slot["mi"].scale = Vector3.ONE * (radius * 0.25)
	slot["mi"].visible = true
	slot["light"].visible = true
	slot["t"] = 0.45
	slot["radius"] = radius
	for j in soldiers.size():
		var s: Dictionary = soldiers[j]
		if s["dead"] or (team != "" and s["team"] == team):
			continue
		var d: float = s["pos"].distance_to(pos)
		if d <= radius:
			_damage_soldier(j, dmg * (1.0 - d / radius * 0.6), src, false, weapon)
			if src == -1:
				hitmark.emit(s["dead"], false)
	if player_alive and veh.player_v < 0:
		var pd := player_pos.distance_to(pos)
		if pd <= radius and (team != player_team or src == -1 or team == ""):
			player_hit.emit(dmg * (1.0 - pd / radius * 0.6) * 0.8, pos)
			if src != -1:
				player_last_hit_by = src
	if vdmg > 0.0:
		veh.explosion(pos, radius, vdmg, team, src, weapon)
	explosion_at.emit(pos)


# ================= 渲染：每队 MultiMesh（头盔/头/躯干/四肢/枪） =================

func _setup_army_mm(team: String) -> void:
	var count := TEAM_SIZE
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.135
	helmet_mesh.height = 0.17
	var torso_mesh := CylinderMesh.new()
	torso_mesh.top_radius = 0.2
	torso_mesh.bottom_radius = 0.16
	torso_mesh.height = 0.62
	var ua_mesh := CylinderMesh.new()
	ua_mesh.top_radius = 0.07
	ua_mesh.bottom_radius = 0.062
	ua_mesh.height = 0.26
	var fa_mesh := CylinderMesh.new()
	fa_mesh.top_radius = 0.058
	fa_mesh.bottom_radius = 0.05
	fa_mesh.height = 0.26
	var th_mesh := CylinderMesh.new()
	th_mesh.top_radius = 0.1
	th_mesh.bottom_radius = 0.088
	th_mesh.height = 0.44
	var ca_mesh := CylinderMesh.new()
	ca_mesh.top_radius = 0.085
	ca_mesh.bottom_radius = 0.06
	ca_mesh.height = 0.44
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.08, 0.1, 0.72)
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.34, 0.4, 0.18)
	_mm[team] = {
		"head": _make_mm(head_mesh, count), "helmet": _make_mm(helmet_mesh, count),
		"torso": _make_mm(torso_mesh, count), "pack": _make_mm(pack_mesh, count),
		"ua": _make_mm(ua_mesh, count * 2), "fa": _make_mm(fa_mesh, count * 2),
		"th": _make_mm(th_mesh, count * 2), "ca": _make_mm(ca_mesh, count * 2),
		"gun": _make_mm(gun_mesh, count),
	}
	# 开局前全部藏到地下（未占用的槽位也不显示）
	for k in _mm[team]:
		var mmi: MultiMeshInstance3D = _mm[team][k]
		for n in mmi.multimesh.instance_count:
			mmi.multimesh.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * 0.001),
					Vector3(0, -50, 0)))


## 队服按「相对玩家」上色：友军蓝、敌军红（玩家可选任一阵营）
func _apply_team_colors() -> void:
	for team in ["atk", "def"]:
		var friendly: bool = team == player_team
		var uniform := Color(0.28, 0.4, 0.58) if friendly else Color(0.55, 0.24, 0.2)
		var helmet := Color(0.2, 0.28, 0.42) if friendly else Color(0.34, 0.16, 0.13)
		var mm: Dictionary = _mm[team]
		for i in TEAM_SIZE:
			mm["torso"].multimesh.set_instance_color(i, uniform)
			mm["pack"].multimesh.set_instance_color(i, uniform.darkened(0.35))
			mm["head"].multimesh.set_instance_color(i, Color(0.85, 0.68, 0.55))
			mm["helmet"].multimesh.set_instance_color(i, helmet)
			mm["gun"].multimesh.set_instance_color(i, Color(0.12, 0.12, 0.13))
			for k in 2:
				mm["ua"].multimesh.set_instance_color(i * 2 + k, uniform)
				mm["fa"].multimesh.set_instance_color(i * 2 + k, Color(0.85, 0.68, 0.55))
				mm["th"].multimesh.set_instance_color(i * 2 + k, Color(0.2, 0.22, 0.26))
				mm["ca"].multimesh.set_instance_color(i * 2 + k, Color(0.2, 0.22, 0.26))


func _make_mm(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _write_pose(s: Dictionary) -> void:
	var i: int = s["slot"]
	var mm: Dictionary = _mm[s["team"]]
	var dead: bool = s["dead"]
	var yaw: float = s["yaw"]
	var ph: float = _t * 9.0 + float(s["phase"])
	var bob: float = absf(sin(ph)) * 0.04 if s["moving"] else 0.0
	var swing := sin(ph) * 0.45 if s["moving"] else 0.0
	var root := Transform3D(Basis.from_euler(Vector3(PI * 0.5, yaw, 0)
			if dead else Vector3(0, yaw, 0)), s["pos"] + Vector3(0, bob, 0))
	mm["torso"].multimesh.set_instance_transform(i, root * Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0)))
	mm["pack"].multimesh.set_instance_transform(i, root * Transform3D(Basis.IDENTITY, Vector3(0, 1.15, -0.22)))
	mm["head"].multimesh.set_instance_transform(i, root * Transform3D(Basis.IDENTITY, Vector3(0, 1.58, 0)))
	mm["helmet"].multimesh.set_instance_transform(i, root * Transform3D(Basis.IDENTITY, Vector3(0, 1.65, 0)))
	if dead:
		mm["ua"].multimesh.set_instance_transform(i * 2, root *
				Transform3D(Basis.from_euler(Vector3(0, 0, 1.2)), Vector3(-0.3, 1.15, 0)))
		mm["fa"].multimesh.set_instance_transform(i * 2, root *
				Transform3D(Basis.from_euler(Vector3(0, 0, 1.7)), Vector3(-0.48, 0.95, 0)))
		mm["ua"].multimesh.set_instance_transform(i * 2 + 1, root *
				Transform3D(Basis.from_euler(Vector3(0, 0, -1.2)), Vector3(0.3, 1.15, 0)))
		mm["fa"].multimesh.set_instance_transform(i * 2 + 1, root *
				Transform3D(Basis.from_euler(Vector3(0, 0, -1.7)), Vector3(0.48, 0.95, 0)))
		mm["th"].multimesh.set_instance_transform(i * 2, root *
				Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0.2)), Vector3(-0.11, 0.42, 0)))
		mm["ca"].multimesh.set_instance_transform(i * 2, root *
				Transform3D(Basis.from_euler(Vector3(0.5, 0, 0.2)), Vector3(-0.16, 0.1, 0.1)))
		mm["th"].multimesh.set_instance_transform(i * 2 + 1, root *
				Transform3D(Basis.from_euler(Vector3(0.2, 0, -0.2)), Vector3(0.11, 0.42, 0)))
		mm["ca"].multimesh.set_instance_transform(i * 2 + 1, root *
				Transform3D(Basis.from_euler(Vector3(-0.4, 0, -0.2)), Vector3(0.2, 0.12, -0.08)))
		mm["gun"].multimesh.set_instance_transform(i, root *
				Transform3D(Basis.IDENTITY, Vector3(0.5, 0.1, 0.3)))
		return
	var aim := Basis.from_euler(Vector3(-1.25, 0, 0))
	var aim_fa := Basis.from_euler(Vector3(-1.45, 0, 0))
	mm["ua"].multimesh.set_instance_transform(i * 2, root * Transform3D(aim, Vector3(-0.14, 1.32, 0.12)))
	mm["fa"].multimesh.set_instance_transform(i * 2, root * Transform3D(aim_fa, Vector3(-0.1, 1.3, 0.34)))
	mm["ua"].multimesh.set_instance_transform(i * 2 + 1, root * Transform3D(aim, Vector3(0.14, 1.32, 0.12)))
	mm["fa"].multimesh.set_instance_transform(i * 2 + 1, root * Transform3D(aim_fa, Vector3(0.1, 1.3, 0.34)))
	var hip_l := Transform3D(Basis.from_euler(Vector3(swing, 0, 0)), Vector3(-0.11, 0.83, 0))
	var hip_r := Transform3D(Basis.from_euler(Vector3(-swing, 0, 0)), Vector3(0.11, 0.83, 0))
	var walk_k := 1.0 if s["moving"] else 0.0
	var knee_l := maxf(0.0, -cos(ph)) * 0.8 * walk_k + 0.1
	var knee_r := maxf(0.0, cos(ph)) * 0.8 * walk_k + 0.1
	var off := Transform3D(Basis.IDENTITY, Vector3(0, -0.22, 0))
	var knee_pl := Transform3D(Basis.from_euler(Vector3(knee_l, 0, 0)), Vector3(0, -0.44, 0))
	var knee_pr := Transform3D(Basis.from_euler(Vector3(knee_r, 0, 0)), Vector3(0, -0.44, 0))
	mm["th"].multimesh.set_instance_transform(i * 2, root * hip_l * off)
	mm["ca"].multimesh.set_instance_transform(i * 2, root * hip_l * knee_pl * off)
	mm["th"].multimesh.set_instance_transform(i * 2 + 1, root * hip_r * off)
	mm["ca"].multimesh.set_instance_transform(i * 2 + 1, root * hip_r * knee_pr * off)
	var glen := 1.25 if s["cls"] == 3 else (0.85 if s["cls"] == 2 else 1.0)   # 狙击枪长、机枪粗
	mm["gun"].multimesh.set_instance_transform(i, root *
			Transform3D(Basis.from_euler(Vector3(-1.35, 0, 0)).scaled(Vector3(1, 1, glen)),
			Vector3(0, 1.32, 0.32)))


# ================= 曳光 / 火花 / 爆炸对象池 =================

func _setup_fx() -> void:
	_tracers = TracerPool.new()
	add_child(_tracers)
	_tracers.setup(48, Color(1.0, 0.8, 0.4), 4.0, 0.03)
	_tracers.on_arrive = _spawn_impact   # 火花等曳光飞到才出
	var imat := StandardMaterial3D.new()
	imat.albedo_color = Color(1.0, 0.75, 0.3)
	imat.emission_enabled = true
	imat.emission = Color(1.0, 0.6, 0.2)
	imat.emission_energy_multiplier = 3.0
	var imesh := SphereMesh.new()
	imesh.radius = 0.05
	imesh.height = 0.1
	imesh.material = imat
	for i in 24:
		var mi := MeshInstance3D.new()
		mi.mesh = imesh
		mi.visible = false
		add_child(mi)
		_im_pool.append({"mi": mi, "t": 0.0})


func _spawn_tracer(from: Vector3, to: Vector3, impact: bool) -> void:
	# 离玩家很远的曳光不画（省节点更新）；火花自己也按距离剔除
	if from.distance_to(player_pos) > 220.0 and to.distance_to(player_pos) > 220.0:
		if impact:
			_spawn_impact(to)
		return
	_tracers.spawn(from, to, impact)


func _spawn_impact(p: Vector3) -> void:
	if p.distance_to(player_pos) > 160.0:
		return
	var slot: Dictionary = _im_pool[_im_i]
	_im_i = (_im_i + 1) % _im_pool.size()
	slot["mi"].global_position = p
	slot["mi"].visible = true
	slot["t"] = 0.22


func _setup_explosions() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 3.5
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.material = mat
	for i in 8:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visible = false
		add_child(mi)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.2)
		light.light_energy = 8.0
		light.omni_range = 26.0
		light.visible = false
		add_child(light)
		_ex_pool.append({"mi": mi, "light": light, "t": 0.0, "radius": 5.0})


func _tick_explosions(dt: float) -> void:
	for slot in _ex_pool:
		if float(slot["t"]) <= 0.0:
			continue
		slot["t"] = float(slot["t"]) - dt
		var k: float = 1.0 - clampf(float(slot["t"]) / 0.45, 0.0, 1.0)
		(slot["mi"] as MeshInstance3D).scale = Vector3.ONE * (float(slot["radius"]) * (0.25 + 0.75 * k))
		if float(slot["t"]) <= 0.0:
			slot["mi"].visible = false
			slot["light"].visible = false


func _tick_fx(dt: float) -> void:
	_tracers.tick(dt)
	for s in _im_pool:
		if float(s["t"]) > 0.0:
			s["t"] = float(s["t"]) - dt
			if float(s["t"]) <= 0.0:
				s["mi"].visible = false


## 计分板数据：两队按得分排序 [{name, cls, kills, deaths, score, me}]
func scoreboard(team: String) -> Array:
	var rows: Array = []
	for s in soldiers:
		if s["team"] == team:
			rows.append({"name": s["name"], "cls": s["cls"], "kills": s["kills"],
					"deaths": s["deaths"], "score": s["score"], "me": false})
	if team == player_team:
		rows.append({"name": "你", "cls": player_cls, "kills": player_stats["kills"],
				"deaths": player_stats["deaths"], "score": player_stats["score"], "me": true})
	rows.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	return rows
