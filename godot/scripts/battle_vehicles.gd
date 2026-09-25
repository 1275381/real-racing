extends Node3D
## 大战场载具：主战坦克 / 步兵战车 / 武装直升机（双方各一套，被毁 45 秒后在本方基地重生）。
## 没人开的载具由 AI 驾驶：地面车在当前区域据点外 30~50m 架位、炮塔自动索敌、
## 碾压敌兵；直升机在区域上空盘旋扫射、火箭打载具。玩家就近按 F 上车：
## 地面车 W/S 前后、A/D 转向；直升机 W/S 前后、A/D 转向、空格升 / Shift 降；
## 鼠标瞄准，左键主武器、右键副武器。伤害统一走 bf（RRBattleField）。
## （按路径 preload，不注册 class_name）

signal player_vehicle_destroyed

const RESPAWN := 45.0
## 伤害来源编码：载具 k 记作 SRC_VEH - k（与士兵序号 >=0、玩家 -1 区分）
const SRC_VEH := -100

const TYPES := {
	"tank": {"name": "主战坦克", "hp": 1300.0, "speed": 12.0, "rev": 5.0, "turn": 0.85,
		"tur_rate": 1.2, "radius": 3.2, "height": 2.4, "armor": 0.02, "eye": 2.2,
		"main": {"kind": "shell", "name": "坦克炮", "cd": 3.6, "dmg": 170.0, "vdmg": 320.0,
			"r": 5.5, "speed": 170.0, "range": 190.0},
		"sec": {"kind": "mg", "name": "同轴机枪", "cd": 0.1, "dmg": [8.0, 12.0], "range": 95.0,
			"spread": 0.03}},
	"ifv": {"name": "步兵战车", "hp": 800.0, "speed": 16.0, "rev": 6.0, "turn": 1.15,
		"tur_rate": 2.0, "radius": 2.7, "height": 2.6, "armor": 0.08, "eye": 2.5,
		"main": {"kind": "cannon", "name": "机炮", "cd": 0.3, "dmg": 34.0, "vdmg": 48.0,
			"r": 2.2, "speed": 190.0, "range": 140.0},
		"sec": {}},
	"heli": {"name": "武装直升机", "hp": 520.0, "speed": 32.0, "rev": 12.0, "turn": 1.3,
		"tur_rate": 3.0, "radius": 4.0, "height": 2.2, "armor": 0.35, "eye": 0.0,
		"main": {"kind": "mg", "name": "航炮", "cd": 0.1, "dmg": [10.0, 15.0], "range": 150.0,
			"spread": 0.025},
		"sec": {"kind": "rockets", "name": "火箭巢", "cd": 7.0, "n": 4, "dmg": 110.0,
			"vdmg": 130.0, "r": 5.0, "speed": 95.0, "range": 160.0}},
}
const ORDER := ["tank", "ifv", "heli"]

var bf                          # RRBattleField
var vehicles: Array = []
var player_v := -1              # 玩家所在载具（-1 = 步行）
var aim_yaw := 0.0              # 玩家瞄准方向（世界）
var aim_pitch := 0.0
var aim_point := Vector3.ZERO   # 准星落点（武器朝这里打）
var _t := 0.0


func setup(bf_ref) -> void:
	bf = bf_ref


func start() -> void:
	for v in vehicles:
		(v["vis"]["root"] as Node3D).queue_free()
	vehicles.clear()
	player_v = -1
	for team in ["atk", "def"]:
		for k in ORDER.size():
			var type: String = ORDER[k]
			var v := {"type": type, "team": team, "slot": k, "hp": 0.0, "dead": true,
					"respawn_t": 0.0, "pos": Vector3.ZERO, "yaw": 0.0, "tur_yaw": 0.0,
					"tur_pitch": 0.0, "speed": 0.0, "vy": 0.0, "main_cd": 0.0, "sec_cd": 0.0,
					"sec_n": 0, "tgt": {}, "tgt_t": 0.0, "goal": Vector3.ZERO, "goal_t": 0.0,
					"block_t": 0.0, "rev_t": 0.0, "last_hit_by": -2, "orbit": randf() * TAU,
					"spotted": true}
			v["vis"] = _build_vis(type, team == bf.player_team)
			vehicles.append(v)
			_respawn(v)


func hide_all() -> void:
	for v in vehicles:
		(v["vis"]["root"] as Node3D).visible = false


func type_def(v: Dictionary) -> Dictionary:
	return TYPES[v["type"]]


func display_name(k: int) -> String:
	var v: Dictionary = vehicles[k]
	return ("我方" if v["team"] == bf.player_team else "敌方") + str(type_def(v)["name"])


## 本方基地旁的车位（地面车在基地两侧，直升机在后方）
func _spawn_pos(v: Dictionary) -> Vector3:
	var base: Vector3 = bf.atk_base() if v["team"] == "atk" else bf.def_base()
	var back := 1.0 if v["team"] == "atk" else -1.0
	var off := Vector3(-20.0, 0, 6.0 * back)
	if v["type"] == "ifv":
		off = Vector3(20.0, 0, 6.0 * back)
	elif v["type"] == "heli":
		off = Vector3(0.0, 0, 22.0 * back)
	var p: Vector3 = base + off
	var np: Vector2 = bf.bmap.push_out(p.x, p.z, float(type_def(v)["radius"]))
	return Vector3(np.x, bf.bmap.terrain_height(np.x, np.y), np.y)


func _respawn(v: Dictionary) -> void:
	v["pos"] = _spawn_pos(v)
	v["hp"] = float(type_def(v)["hp"])
	v["dead"] = false
	v["speed"] = 0.0
	v["vy"] = 0.0
	v["yaw"] = PI if v["team"] == "atk" else 0.0
	v["tur_yaw"] = v["yaw"]
	v["tur_pitch"] = 0.0
	v["goal_t"] = 0.0
	v["tgt"] = {}
	v["last_hit_by"] = -2
	(v["vis"]["root"] as Node3D).visible = true
	_sync_vis(v)


# ================= 主更新 =================

func update(dt: float) -> void:
	_t += dt
	for k in vehicles.size():
		var v: Dictionary = vehicles[k]
		if v["dead"]:
			v["respawn_t"] = float(v["respawn_t"]) - dt
			if float(v["respawn_t"]) <= 0.0 and not bf.battle_over:
				_respawn(v)
			continue
		v["main_cd"] = maxf(0.0, float(v["main_cd"]) - dt)
		v["sec_cd"] = maxf(0.0, float(v["sec_cd"]) - dt)
		if k == player_v:
			_player_drive(k, v, dt)
		elif v["type"] == "heli":
			_ai_heli(k, v, dt)
		else:
			_ai_ground(k, v, dt)
		if v["type"] != "heli":
			_ground_physics(k, v, dt)
		_sync_vis(v)


## 地面车：挡墙推出 / 贴地 / 车与车推开 / 碾压敌兵
func _ground_physics(k: int, v: Dictionary, dt: float) -> void:
	var td := type_def(v)
	var r: float = td["radius"]
	var p: Vector3 = v["pos"]
	var fwd := Vector3(sin(v["yaw"]), 0, cos(v["yaw"]))
	var want := p + fwd * float(v["speed"]) * dt
	want.x = clampf(want.x, -236.0, 236.0)
	want.z = clampf(want.z, -186.0, 186.0)
	var np: Vector2 = bf.bmap.push_out(want.x, want.z, r)
	var moved := Vector2(np.x - p.x, np.y - p.z).length()
	if absf(float(v["speed"])) * dt > 0.02 and moved < absf(float(v["speed"])) * dt * 0.3:
		v["block_t"] = float(v["block_t"]) + dt
	else:
		v["block_t"] = maxf(0.0, float(v["block_t"]) - dt)
	for o in vehicles:
		if o == v or o["dead"] or o["type"] == "heli":
			continue
		var dv := Vector2(np.x - o["pos"].x, np.y - o["pos"].z)
		var d := dv.length()
		var rr: float = r + float(type_def(o)["radius"])
		if d < rr and d > 0.01:
			np += dv / d * (rr - d)
	v["pos"] = Vector3(np.x, bf.bmap.terrain_height(np.x, np.y), np.y)
	# 碾压：车速 >4m/s 撞上敌兵直接压死，友军被挤开
	if absf(float(v["speed"])) > 4.0:
		var src: int = -1 if k == player_v else SRC_VEH - k
		for j in bf.soldiers.size():
			var s: Dictionary = bf.soldiers[j]
			if s["dead"]:
				continue
			var ds := Vector2(s["pos"].x - np.x, s["pos"].z - np.y).length()
			if ds < r * 0.9:
				if s["team"] != v["team"]:
					bf.damage_soldier_ext(j, 500.0, src, "碾压")
				else:
					var push := Vector2(s["pos"].x - np.x, s["pos"].z - np.y).normalized() * (r - ds)
					s["pos"] = s["pos"] + Vector3(push.x, 0, push.y)


# ================= AI =================

## 目标：[kind, idx]；kind = soldier / player / vehicle
func _find_target(k: int, v: Dictionary, max_d: float, want_vehicle: bool) -> Dictionary:
	var p: Vector3 = v["pos"]
	var best := {}
	var bd := max_d
	if want_vehicle:
		for j in vehicles.size():
			var o: Dictionary = vehicles[j]
			if j == k or o["dead"] or o["team"] == v["team"]:
				continue
			if v["type"] == "tank" and o["type"] == "heli":
				continue   # 坦克炮不打直升机（防空交给步战车机炮 / 直升机）
			var d: float = p.distance_to(o["pos"])
			if d < bd:
				bd = d
				best = {"kind": "vehicle", "i": j}
		if not best.is_empty():
			return best
	for j in bf.soldiers.size():
		var s: Dictionary = bf.soldiers[j]
		if s["dead"] or s["team"] == v["team"]:
			continue
		var d2: float = p.distance_to(s["pos"])
		if d2 < bd:
			bd = d2
			best = {"kind": "soldier", "i": j}
	if bf.player_alive and bf.player_team != v["team"] and player_v < 0:
		var d3: float = p.distance_to(bf.player_pos)
		if d3 < bd:
			best = {"kind": "player", "i": -1}
	return best


func _target_pos(t: Dictionary) -> Vector3:
	match str(t.get("kind", "")):
		"vehicle":
			var o: Dictionary = vehicles[t["i"]]
			if o["dead"]:
				return Vector3.INF
			return o["pos"] + Vector3(0, float(type_def(o)["height"]) * 0.5, 0)
		"soldier":
			var s: Dictionary = bf.soldiers[t["i"]]
			if s["dead"]:
				return Vector3.INF
			return s["pos"] + Vector3(0, 1.1, 0)
		"player":
			if not bf.player_alive or player_v >= 0:
				return Vector3.INF
			return bf.player_pos + Vector3(0, 1.2, 0)
	return Vector3.INF


## 地面车 AI：到据点外围架位 → 转车身开过去 → 炮塔追目标开火；被卡倒车换向
func _ai_ground(k: int, v: Dictionary, dt: float) -> void:
	var td := type_def(v)
	v["goal_t"] = float(v["goal_t"]) - dt
	if float(v["goal_t"]) <= 0.0:
		v["goal_t"] = randf_range(14.0, 24.0)
		v["goal"] = _overwatch_spot(v)
	# 目标（0.6s 一次）：坦克优先打车
	v["tgt_t"] = float(v["tgt_t"]) - dt
	if float(v["tgt_t"]) <= 0.0:
		v["tgt_t"] = 0.6
		v["tgt"] = _find_target(k, v, float(td["main"]["range"]), v["type"] == "tank")
		if v["tgt"].is_empty() and v["type"] == "tank":
			v["tgt"] = _find_target(k, v, float(td["main"]["range"]), false)
	# 行驶
	var p: Vector3 = v["pos"]
	var to_g: Vector3 = v["goal"] - p
	var gd := Vector2(to_g.x, to_g.z).length()
	var want_spd := 0.0
	var turn := 0.0
	if float(v["rev_t"]) > 0.0:
		v["rev_t"] = float(v["rev_t"]) - dt
		want_spd = -float(td["rev"])
		turn = 1.0
	elif gd > 6.0:
		var err := wrapf(atan2(to_g.x, to_g.z) - float(v["yaw"]), -PI, PI)
		turn = clampf(err * 2.0, -1.0, 1.0)
		want_spd = float(td["speed"]) * (1.0 if absf(err) < 0.6 else 0.3)
		if gd < 20.0:
			want_spd *= gd / 20.0
	if float(v["block_t"]) > 1.2:
		v["block_t"] = 0.0
		v["rev_t"] = randf_range(1.2, 2.0)
	v["yaw"] = float(v["yaw"]) + turn * float(td["turn"]) * dt
	v["speed"] = move_toward(float(v["speed"]), want_spd, 8.0 * dt)
	_ai_turret(k, v, dt)


## 架位：本方一侧、据点外 45~70m（攻方在南、守方在北）：离步兵火箭远一点
func _overwatch_spot(v: Dictionary) -> Vector3:
	var bm = bf.bmap
	if bf.sector >= bf.pts.size():
		return v["pos"]
	var pi := randi() % 2
	var c: Vector3 = bm.point_pos(bf.sector, pi)
	var side := 1.0 if v["team"] == "atk" else -1.0
	var ang := randf_range(-0.8, 0.8)
	var r := randf_range(45.0, 70.0)
	var g := c + Vector3(sin(ang) * r, 0, cos(ang) * r * side)
	var np: Vector2 = bm.push_out(clampf(g.x, -225.0, 225.0), clampf(g.z, -175.0, 175.0),
			float(type_def(v)["radius"]))
	return Vector3(np.x, 0, np.y)


## 炮塔：转向目标，对准后开火（主武器 + 坦克同轴机枪扫步兵）
func _ai_turret(k: int, v: Dictionary, dt: float) -> void:
	var td := type_def(v)
	var tp := _target_pos(v["tgt"])
	if tp == Vector3.INF:
		v["tgt"] = {}
		v["tur_yaw"] = lerp_angle(float(v["tur_yaw"]), float(v["yaw"]), 1.0 - exp(-1.5 * dt))
		return
	var eye: Vector3 = v["pos"] + Vector3(0, float(td["eye"]), 0)
	var to: Vector3 = tp - eye
	var want_yaw := atan2(to.x, to.z)
	var dy := wrapf(want_yaw - float(v["tur_yaw"]), -PI, PI)
	v["tur_yaw"] = float(v["tur_yaw"]) + clampf(dy, -float(td["tur_rate"]) * dt,
			float(td["tur_rate"]) * dt)
	v["tur_pitch"] = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.25, 0.5)
	if absf(dy) > 0.06:
		return
	var dist := to.length()
	if not _los(eye, tp):
		return
	var dir := _barrel_dir(v)
	var main: Dictionary = td["main"]
	if float(v["main_cd"]) <= 0.0 and dist < float(main["range"]):
		v["main_cd"] = float(main["cd"]) * randf_range(1.0, 1.4)
		_fire(k, v, main, dir.lerp(to.normalized(), 0.85).normalized(), SRC_VEH - k)
	var sec: Dictionary = td["sec"]
	if not sec.is_empty() and sec["kind"] == "mg" and float(v["sec_cd"]) <= 0.0 \
			and v["tgt"].get("kind", "") != "vehicle" and dist < float(sec["range"]):
		v["sec_cd"] = float(sec["cd"])
		_fire(k, v, sec, to.normalized(), SRC_VEH - k)


## 直升机 AI：绕当前区域盘旋（35~45m 高），航炮扫步兵，火箭打载具
func _ai_heli(k: int, v: Dictionary, dt: float) -> void:
	var td := type_def(v)
	var bm = bf.bmap
	var si: int = mini(bf.sector, bm.SECTORS.size() - 1)
	var mid: Vector3 = (bm.point_pos(si, 0) + bm.point_pos(si, 1)) * 0.5
	v["orbit"] = float(v["orbit"]) + 0.18 * dt
	var side := 1.0 if v["team"] == "atk" else -1.0
	var goal := mid + Vector3(cos(v["orbit"]) * 75.0, 0, sin(v["orbit"]) * 45.0 + 25.0 * side)
	var p: Vector3 = v["pos"]
	var to := goal - p
	var err := wrapf(atan2(to.x, to.z) - float(v["yaw"]), -PI, PI)
	v["yaw"] = float(v["yaw"]) + clampf(err, -1.0, 1.0) * float(td["turn"]) * dt
	v["speed"] = move_toward(float(v["speed"]), float(td["speed"]) * 0.7, 6.0 * dt)
	var alt: float = bm.terrain_height(p.x, p.z) + 46.0 + sin(_t * 0.5 + k) * 5.0
	var fwd := Vector3(sin(v["yaw"]), 0, cos(v["yaw"]))
	p += fwd * float(v["speed"]) * dt
	p.y = lerpf(p.y, alt, 1.0 - exp(-0.8 * dt))
	p.x = clampf(p.x, -240.0, 240.0)
	p.z = clampf(p.z, -190.0, 190.0)
	v["pos"] = p
	v["tgt_t"] = float(v["tgt_t"]) - dt
	if float(v["tgt_t"]) <= 0.0:
		v["tgt_t"] = 0.7
		v["tgt"] = _find_target(k, v, 140.0, false)
		v["vtgt"] = _find_target(k, v, 150.0, true)
	var tp := _target_pos(v["tgt"])
	if tp != Vector3.INF:
		var aim := (tp - p).normalized()
		v["tur_yaw"] = atan2(aim.x, aim.z)
		v["tur_pitch"] = asin(clampf(aim.y, -1.0, 1.0))
		# 航炮只在机头前方 70° 内开火
		if absf(wrapf(v["tur_yaw"] - v["yaw"], -PI, PI)) < 1.2 and float(v["main_cd"]) <= 0.0:
			v["main_cd"] = float(td["main"]["cd"]) * randf_range(1.0, 2.2)
			_fire(k, v, td["main"], aim, SRC_VEH - k)
	var vt: Dictionary = v.get("vtgt", {})
	var vp := _target_pos(vt)
	if vp != Vector3.INF and vt.get("kind", "") == "vehicle" and float(v["sec_cd"]) <= 0.0:
		v["sec_cd"] = float(td["sec"]["cd"])
		v["sec_n"] = int(td["sec"]["n"])
		v["sec_aim"] = vp
	if int(v["sec_n"]) > 0 and float(v["sec_cd"]) < float(td["sec"]["cd"]) - 0.15 * (int(td["sec"]["n"]) - int(v["sec_n"]) + 1):
		v["sec_n"] = int(v["sec_n"]) - 1
		var a2: Vector3 = (Vector3(v.get("sec_aim", p)) - p).normalized()
		_fire(k, v, td["sec"], (a2 + Vector3(randf() - 0.5, 0, randf() - 0.5) * 0.04).normalized(),
				SRC_VEH - k)


# ================= 玩家驾驶 =================

func add_look(rel: Vector2) -> void:
	aim_yaw -= rel.x * 0.0023
	aim_pitch = clampf(aim_pitch - rel.y * 0.0023, -0.6, 0.7)


func nearest_enterable(at: Vector3, team: String) -> int:
	var best := -1
	var bd := 7.0
	for k in vehicles.size():
		var v: Dictionary = vehicles[k]
		if v["dead"] or v["team"] != team:
			continue
		var d := Vector2(v["pos"].x - at.x, v["pos"].z - at.z).length() \
				- float(type_def(v)["radius"])
		if v["type"] == "heli" and v["pos"].y - bf.bmap.terrain_height(v["pos"].x, v["pos"].z) > 6.0:
			continue   # 飞在天上的直升机上不去
		if d < bd:
			bd = d
			best = k
	return best


func player_enter(k: int) -> void:
	player_v = k
	var v: Dictionary = vehicles[k]
	aim_yaw = v["yaw"]
	aim_pitch = 0.05
	v["speed"] = 0.0 if v["type"] != "heli" else v["speed"]
	if v["type"] == "heli" and v["pos"].y < bf.bmap.terrain_height(v["pos"].x, v["pos"].z) + 1.0:
		v["pos"] = v["pos"] + Vector3(0, 1.0, 0)


## 下车：返回下车点；直升机离地太高下不去（返回 INF）
func player_exit() -> Vector3:
	if player_v < 0:
		return Vector3.INF
	var v: Dictionary = vehicles[player_v]
	var g: float = bf.bmap.terrain_height(v["pos"].x, v["pos"].z)
	if v["type"] == "heli" and v["pos"].y - g > 4.0:
		return Vector3.INF
	var side := Vector3(cos(v["yaw"]), 0, -sin(v["yaw"]))
	var ex: Vector3 = v["pos"] + side * (float(type_def(v)["radius"]) + 1.5)
	var np: Vector2 = bf.bmap.push_out(ex.x, ex.z, 0.6)
	player_v = -1
	v["speed"] = 0.0
	v["goal_t"] = 0.0
	return Vector3(np.x, bf.bmap.terrain_height(np.x, np.y), np.y)


func player_vehicle() -> Dictionary:
	return {} if player_v < 0 else vehicles[player_v]


func _player_drive(k: int, v: Dictionary, dt: float) -> void:
	var td := type_def(v)
	var thr := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		thr += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		thr -= 1.0
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_D):
		turn -= 1.0
	v["yaw"] = float(v["yaw"]) + turn * float(td["turn"]) * dt
	var want := float(td["speed"]) * thr if thr >= 0.0 else float(td["rev"]) * thr
	v["speed"] = move_toward(float(v["speed"]), want, (9.0 if v["type"] != "heli" else 12.0) * dt)
	if v["type"] == "heli":
		var p: Vector3 = v["pos"]
		var up := 0.0
		if Input.is_physical_key_pressed(KEY_SPACE):
			up += 1.0
		if Input.is_physical_key_pressed(KEY_SHIFT):
			up -= 1.0
		v["vy"] = move_toward(float(v["vy"]), up * 9.0, 14.0 * dt)
		p += Vector3(sin(v["yaw"]), 0, cos(v["yaw"])) * float(v["speed"]) * dt
		p.y += float(v["vy"]) * dt
		var g: float = bf.bmap.terrain_height(p.x, p.z)
		p.y = clampf(p.y, g + 0.6, g + 95.0)
		p.x = clampf(p.x, -240.0, 240.0)
		p.z = clampf(p.z, -190.0, 190.0)
		v["pos"] = p
	# 炮塔 / 机炮跟随准星
	var eye: Vector3 = v["pos"] + Vector3(0, float(td["eye"]), 0)
	var to := aim_point - eye
	var want_yaw := atan2(to.x, to.z)
	if v["type"] == "heli":
		v["tur_yaw"] = want_yaw
	else:
		var dy := wrapf(want_yaw - float(v["tur_yaw"]), -PI, PI)
		v["tur_yaw"] = float(v["tur_yaw"]) + clampf(dy, -float(td["tur_rate"]) * dt,
				float(td["tur_rate"]) * dt)
	v["tur_pitch"] = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.35, 0.6)
	var main: Dictionary = td["main"]
	if Input.is_action_pressed("rr_fire") and float(v["main_cd"]) <= 0.0:
		v["main_cd"] = float(main["cd"])
		_fire(k, v, main, _barrel_dir(v) if v["type"] != "heli" else to.normalized(), -1)
	var sec: Dictionary = td["sec"]
	if not sec.is_empty() and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if sec["kind"] == "mg" and float(v["sec_cd"]) <= 0.0:
			v["sec_cd"] = float(sec["cd"])
			_fire(k, v, sec, to.normalized(), -1)
		elif sec["kind"] == "rockets" and float(v["sec_cd"]) <= 0.0:
			v["sec_cd"] = float(sec["cd"])
			v["sec_n"] = int(sec["n"])
			v["sec_aim"] = aim_point
	if v["type"] == "heli" and int(v["sec_n"]) > 0 \
			and float(v["sec_cd"]) < float(sec["cd"]) - 0.15 * (int(sec["n"]) - int(v["sec_n"]) + 1):
		v["sec_n"] = int(v["sec_n"]) - 1
		var a2: Vector3 = (Vector3(v["sec_aim"]) - v["pos"]).normalized()
		_fire(k, v, sec, (a2 + Vector3(randf() - 0.5, 0, randf() - 0.5) * 0.03).normalized(), -1)


## 第三人称相机：沿瞄准方向后上方
func camera_pose() -> Array:
	var v: Dictionary = vehicles[player_v]
	var heli: bool = v["type"] == "heli"
	var pivot: Vector3 = v["pos"] + Vector3(0, 1.2 if heli else 3.0, 0)
	var dir := Vector3(sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch),
			cos(aim_yaw) * cos(aim_pitch))
	var dist := 17.0 if heli else 10.5
	var cam := pivot - dir * dist + Vector3(0, 3.2 if heli else 2.2, 0)
	var g: float = bf.bmap.terrain_height(cam.x, cam.z) + 0.8
	cam.y = maxf(cam.y, g)
	return [cam, pivot + dir * 40.0]


## 准星落点：相机中心射线打到的第一个墙/地面/敌人（武器朝它开火）
func update_aim(cam: Camera3D) -> void:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var best := 300.0
	var wd: float = bf.bmap.ray_wall(from, dir, best)
	best = minf(best, wd)
	var t := 4.0
	while t < best:
		var p := from + dir * t
		if p.y < bf.bmap.terrain_height(p.x, p.z):
			best = t
			break
		t += 4.0
	aim_point = from + dir * best


# ================= 开火 =================

func _barrel_dir(v: Dictionary) -> Vector3:
	var ty: float = v["tur_yaw"]
	var tp: float = v["tur_pitch"]
	return Vector3(sin(ty) * cos(tp), sin(tp), cos(ty) * cos(tp))


func _muzzle(v: Dictionary, dir: Vector3) -> Vector3:
	var td := type_def(v)
	match str(v["type"]):
		"tank":
			return v["pos"] + Vector3(0, 1.9, 0) + dir * 5.4
		"ifv":
			return v["pos"] + Vector3(0, 2.6, 0) + dir * 3.2
	return v["pos"] + Vector3(0, -1.0, 0) + dir * 3.0


func _fire(k: int, v: Dictionary, w: Dictionary, dir: Vector3, src: int) -> void:
	var from := _muzzle(v, dir)
	match str(w["kind"]):
		"mg":
			var sp: float = w.get("spread", 0.02)
			var d := (dir + Vector3(randf() - 0.5, (randf() - 0.5) * 0.6, randf() - 0.5) * sp).normalized()
			bf.hitscan(from, d, float(w["range"]), randf_range(w["dmg"][0], w["dmg"][1]),
					v["team"], src, str(w["name"]), from, k)
		"shell", "cannon", "rockets":
			var spread := 0.004 if w["kind"] == "shell" else 0.012
			var d2 := (dir + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * spread).normalized()
			bf.spawn_projectile(w["kind"], from, d2 * float(w["speed"]), v["team"], src,
					float(w["dmg"]), float(w["vdmg"]), float(w["r"]), str(w["name"]), k)
			if w["kind"] == "shell" and v["pos"].distance_to(bf.player_pos) < 120.0:
				bf.explosion_at.emit(from)   # 开炮震动 / 声音


func _los(from: Vector3, to: Vector3) -> bool:
	var d := from.distance_to(to)
	return bf.bmap.ray_wall(from, (to - from) / maxf(d, 0.01), d - 1.0) == INF


# ================= 受伤 / 命中测试 =================

## 载具受伤（dmg 已含装甲系数）；src 同 bf 约定
func damage(k: int, dmg: float, src: int, weapon: String) -> bool:
	var v: Dictionary = vehicles[k]
	if v["dead"]:
		return false
	v["hp"] = float(v["hp"]) - dmg
	v["last_hit_by"] = src
	if k == player_v:
		bf.player_last_hit_by = src   # 车毁人亡时播报击杀者
	if float(v["hp"]) > 0.0:
		return false
	v["dead"] = true
	v["respawn_t"] = RESPAWN
	v["speed"] = 0.0
	(v["vis"]["root"] as Node3D).visible = false
	bf.vehicle_destroyed(k, src, weapon)
	var had_player := k == player_v
	if had_player:
		player_v = -1
	# 殉爆：波及周围（不分敌我）
	bf.explode_raw(v["pos"] + Vector3(0, 1.0, 0), 7.0, 90.0, 0.0, "", src, "殉爆")
	if had_player:
		player_vehicle_destroyed.emit()
	return true


## 射线对载具包围盒（按车长轴旋转的 OBB + 高度）
func ray_hit(from: Vector3, dir: Vector3, max_d: float, skip: int) -> Array:
	var best_d := max_d
	var best_k := -1
	for k in vehicles.size():
		var v: Dictionary = vehicles[k]
		if v["dead"] or k == skip:
			continue
		var td := type_def(v)
		var r: float = td["radius"]
		var c: Vector3 = v["pos"] + Vector3(0, float(td["height"]) * 0.5
				if v["type"] != "heli" else 0.0, 0)
		var t: float = (c - from).dot(dir)
		if t < 0.5 or t > best_d:
			continue
		var off: Vector3 = c - from - dir * t
		if Vector2(off.x, off.z).length() < r * 0.85 and absf(off.y) < float(td["height"]) * 0.6:
			best_d = t
			best_k = k
	return [best_k, best_d]


## 点是否在某辆（非本队）载具体内：火箭/炮弹近炸
func hit_test(p: Vector3, team: String, skip: int) -> int:
	for k in vehicles.size():
		var v: Dictionary = vehicles[k]
		if v["dead"] or k == skip or v["team"] == team:
			continue
		var td := type_def(v)
		var c: Vector3 = v["pos"] + Vector3(0, float(td["height"]) * 0.5 if v["type"] != "heli" else 0.0, 0)
		var prox := 1.0 if v["type"] != "heli" else 3.0   # 直升机近炸引信
		if Vector2(p.x - c.x, p.z - c.z).length() < float(td["radius"]) * 0.9 + prox \
				and absf(p.y - c.y) < float(td["height"]) * 0.7 + prox:
			return k
	return -1


## 爆炸波及载具
func explosion(pos: Vector3, radius: float, vdmg: float, team: String, src: int,
		weapon: String) -> void:
	for k in vehicles.size():
		var v: Dictionary = vehicles[k]
		if v["dead"] or (team != "" and v["team"] == team):
			continue
		var d: float = maxf(0.0, pos.distance_to(v["pos"]) - float(type_def(v)["radius"]))
		if d <= radius:
			var destroyed := damage(k, vdmg * (1.0 - d / radius * 0.5), src, weapon)
			if src == -1:
				bf.hitmark.emit(destroyed, false)


# ================= 模型 =================

func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, emit := false) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.75
	mat.metallic = 0.2
	if emit:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.4
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3, col: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.8
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## 程序化载具模型（前向 +Z）。友军橄榄绿 + 蓝色识别灯，敌军沙褐 + 红色识别灯
func _build_vis(type: String, friendly: bool) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var body := Color(0.4, 0.45, 0.34) if friendly else Color(0.5, 0.41, 0.3)
	var dark := body.darkened(0.45)
	var tag := Color(0.3, 0.6, 1.0) if friendly else Color(1.0, 0.28, 0.2)
	var tur := Node3D.new()
	var barrel := Node3D.new()
	var rotor: Node3D = null
	var trotor: Node3D = null
	match type:
		"tank":
			_box(root, Vector3(3.4, 1.1, 6.8), Vector3(0, 0.95, 0), body)
			_box(root, Vector3(3.0, 0.5, 1.4), Vector3(0, 1.25, 3.0), body.darkened(0.1))
			for sx in [-1.75, 1.75]:
				_box(root, Vector3(0.75, 1.05, 7.1), Vector3(sx, 0.55, 0), dark)
			tur.position = Vector3(0, 1.5, -0.3)
			root.add_child(tur)
			_box(tur, Vector3(2.5, 0.85, 3.1), Vector3(0, 0.42, 0), body)
			_box(tur, Vector3(0.3, 0.22, 0.3), Vector3(0.6, 1.0, -0.5), tag, true)
			barrel.position = Vector3(0, 0.45, 1.4)
			tur.add_child(barrel)
			_cyl(barrel, 0.13, 4.2, Vector3(0, 0, 2.1), Vector3(PI * 0.5, 0, 0), dark)
		"ifv":
			_box(root, Vector3(2.9, 1.5, 6.0), Vector3(0, 1.25, 0), body)
			_box(root, Vector3(2.7, 0.6, 1.2), Vector3(0, 1.7, 2.6), body.darkened(0.1))
			for wx in [-1.5, 1.5]:
				for wz in [-2.2, -0.75, 0.75, 2.2]:
					_cyl(root, 0.55, 0.4, Vector3(wx, 0.55, wz), Vector3(0, 0, PI * 0.5), dark)
			tur.position = Vector3(0, 2.0, -0.2)
			root.add_child(tur)
			_box(tur, Vector3(1.5, 0.6, 1.7), Vector3(0, 0.3, 0), body)
			_box(tur, Vector3(0.28, 0.2, 0.28), Vector3(-0.4, 0.7, -0.4), tag, true)
			barrel.position = Vector3(0, 0.35, 0.8)
			tur.add_child(barrel)
			_cyl(barrel, 0.06, 2.4, Vector3(0, 0, 1.2), Vector3(PI * 0.5, 0, 0), dark)
		"heli":
			_box(root, Vector3(1.6, 1.6, 4.6), Vector3(0, 0, 0), body)
			_box(root, Vector3(1.3, 1.1, 1.6), Vector3(0, -0.1, 2.9), body.darkened(0.15))
			_box(root, Vector3(0.45, 0.45, 5.2), Vector3(0, 0.3, -4.6), body)
			_box(root, Vector3(0.12, 1.4, 1.0), Vector3(0, 0.9, -7.0), body)
			_box(root, Vector3(3.8, 0.12, 0.8), Vector3(0, -0.2, 0.2), dark)
			for px in [-1.8, 1.8]:
				_cyl(root, 0.22, 1.3, Vector3(px, -0.45, 0.3), Vector3(PI * 0.5, 0, 0), dark)
			for sx in [-0.7, 0.7]:
				_box(root, Vector3(0.1, 0.9, 0.1), Vector3(sx, -1.1, 0), dark)
				_box(root, Vector3(0.12, 0.08, 3.2), Vector3(sx, -1.55, 0), dark)
			_box(root, Vector3(0.28, 0.2, 0.28), Vector3(0, 0.95, -1.0), tag, true)
			rotor = Node3D.new()
			rotor.position = Vector3(0, 1.1, 0)
			root.add_child(rotor)
			_box(rotor, Vector3(12.0, 0.05, 0.35), Vector3.ZERO, Color(0.12, 0.12, 0.13))
			_box(rotor, Vector3(0.35, 0.05, 12.0), Vector3.ZERO, Color(0.12, 0.12, 0.13))
			trotor = Node3D.new()
			trotor.position = Vector3(0.2, 0.9, -7.0)
			root.add_child(trotor)
			_box(trotor, Vector3(0.05, 1.8, 0.2), Vector3.ZERO, Color(0.12, 0.12, 0.13))
			tur.position = Vector3(0, -0.9, 2.8)
			root.add_child(tur)
			_box(tur, Vector3(0.3, 0.3, 0.6), Vector3(0, 0, 0.3), dark)
	return {"root": root, "tur": tur, "barrel": barrel, "rotor": rotor, "trotor": trotor}


func _sync_vis(v: Dictionary) -> void:
	var vis: Dictionary = v["vis"]
	var root: Node3D = vis["root"]
	root.position = v["pos"]
	if v["type"] == "heli":
		var tilt := clampf(float(v["speed"]) / 40.0, -0.3, 0.35)
		root.rotation = Vector3(tilt, float(v["yaw"]), 0.0)
		(vis["rotor"] as Node3D).rotation.y = _t * 22.0
		(vis["trotor"] as Node3D).rotation.x = _t * 30.0
		(vis["tur"] as Node3D).rotation = Vector3(-float(v["tur_pitch"]),
				wrapf(float(v["tur_yaw"]) - float(v["yaw"]), -PI, PI), 0)
	else:
		# 车身贴地起伏：按车头/车尾地形高差取俯仰
		var fwd := Vector3(sin(v["yaw"]), 0, cos(v["yaw"]))
		var hf: float = bf.bmap.terrain_height(v["pos"].x + fwd.x * 3.0, v["pos"].z + fwd.z * 3.0)
		var hb: float = bf.bmap.terrain_height(v["pos"].x - fwd.x * 3.0, v["pos"].z - fwd.z * 3.0)
		root.rotation = Vector3(-atan2(hf - hb, 6.0), float(v["yaw"]), 0.0)
		(vis["tur"] as Node3D).rotation.y = wrapf(float(v["tur_yaw"]) - float(v["yaw"]), -PI, PI)
		(vis["barrel"] as Node3D).rotation.x = -float(v["tur_pitch"])
