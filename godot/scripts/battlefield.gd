class_name RRBattleField
extends Node3D
## 大战场战斗管理器：我方 AI 与敌方 AI 士兵交战（波次歼灭战）。
## 鸭子类型顶替 onfoot 的 npc 位：raycast(from,dir,max_d) 同契约。

signal player_hit(dmg: float)
signal enemy_killed(by_player: bool)
signal wave_started(n: int)
signal over(win: bool, kills: int)
signal plane_down(enemy: bool, by_player: bool)
signal explosion_at(pos: Vector3)

const ALLY_COUNT := 12
const ENEMY_WAVE := 12
const TOTAL_WAVES := 2
const SOLDIER_HP := 36.0
const SHOT_DMG := 9.0
const ENGAGE_DIST := 28.0     # 走位切换距离
const FIRE_RANGE := 70.0
const ARENA_X := 238.0        # 士兵活动钳制（略小于地图周界）
const ARENA_Z := 188.0
const MAG := 30

const PLANE_HP := 40.0        # 战机生命（步兵轻武器/爆炸扣血）
const PLANE_BOMBS := 4        # 载弹量（回基地补给）
const BOMB_RADIUS := 16.0     # 炸弹杀伤半径
const BOMB_DMG := 55.0
const PLANE_MIN_ALT := 3.5    # 最低飞行高度（贴地钳制，不做坠机）
const PLANE_ALT_MAX := 120.0
const PLANE_SPEED_MIN := 28.0
const PLANE_SPEED_MAX := 85.0
const PLANE_TURN := 1.05      # 转弯角速度 rad/s
const PLANE_PITCH_RATE := 0.9
const ENEMY_PLANE_N := 2
const PLANE_RESPAWN := 30.0   # 敌机重生秒数
const ALLY_PLANE_RESPAWN := 25.0

var bmap                      # BattleMap
var audio                     # RRAudio
var player_pos := Vector3.ZERO
var player_alive := true
var player_flying := false    # 玩家正在驾驶我方战机（game 侧同步）
var active := false
var battle_over := false
var win := false
var wave := 1
var kills := 0                # 玩家击杀数
var _enemies_killed := 0      # 全场歼敌数（波次/胜负判定）

var allies: Array = []
var enemies: Array = []       # 含阵亡尸体（波 2 追加到 idx 12..23）
var ally_plane := {}          # 我方战机（玩家驾驶）：{pos, heading, ...}
var enemy_planes: Array = []  # 敌机 ×2（盘旋/扫射/投弹）
var bombs: Array = []         # 空中落弹 {vis, pos, vel, by_player}

var _t := 0.0
var _snd_budget := 6.0        # AI 枪声限流（每秒 ≤6 次）
var _tr_pool: Array = []
var _im_pool: Array = []
var _tr_i := 0
var _im_i := 0
var _ex_pool: Array = []      # 爆炸视觉池 {mi, light, t}
var _ex_i := 0
# 每队一套 MultiMesh（头/躯干/双臂/双腿/枪），人数上限 = 预留容量
var _mm := {}                 # team -> {head, torso, arm, leg, gun}


func setup(bmap_ref, audio_ref) -> void:
	bmap = bmap_ref
	audio = audio_ref
	_setup_fx()
	_setup_explosions()
	_setup_army_mm("ally", ALLY_COUNT)
	_setup_army_mm("enemy", ENEMY_WAVE * TOTAL_WAVES)
	# 战机模型建一次，start() 复位
	ally_plane = _make_plane(false, Vector3(18.0, 0.0, 150.0), PI)
	enemy_planes.clear()
	for i in ENEMY_PLANE_N:
		enemy_planes.append(_make_plane(true,
				Vector3(-160.0 + 320.0 * i, 45.0, -150.0), 0.0))


## ================= 战机 =================

func _make_plane(enemy: bool, pos: Vector3, heading: float) -> Dictionary:
	return {
		"enemy": enemy, "vis": _build_plane_vis(enemy),
		"pos": pos, "heading": heading, "pitch": 0.0, "roll": 0.0,
		"speed": 0.0, "throttle": 0.0, "hp": PLANE_HP, "bombs": PLANE_BOMBS,
		"alive": false, "respawn_t": 0.0, "landed": true,
		"orbit_ang": randf() * TAU, "orbit_alt": randf_range(38.0, 52.0),
		"strafe_t": randf_range(6.0, 12.0), "burst_n": 0, "burst_t": 0.0,
		"bomb_t": randf_range(18.0, 30.0), "strafe_tgt": Vector3.ZERO,
	}


func _build_plane_vis(enemy: bool) -> Node3D:
	var root := Node3D.new()
	var body := Color(0.47, 0.56, 0.68) if not enemy else Color(0.5, 0.27, 0.21)
	var wing := Color(0.4, 0.48, 0.58) if not enemy else Color(0.42, 0.23, 0.18)
	var dark := Color(0.16, 0.17, 0.19)
	var add_box := func(size: Vector3, p: Vector3, c: Color) -> void:
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.roughness = 0.6
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = p
		root.add_child(mi)
	add_box.call(Vector3(1.1, 1.0, 5.6), Vector3(0, 0, 0), body)       # 机身
	add_box.call(Vector3(0.55, 0.5, 0.4), Vector3(0, 0, 3.0), dark)    # 螺旋桨座
	add_box.call(Vector3(7.2, 0.14, 1.5), Vector3(0, 0.22, 0.4), wing) # 主翼
	add_box.call(Vector3(2.6, 0.12, 0.9), Vector3(0, 0.28, -2.4), wing)
	add_box.call(Vector3(0.12, 1.1, 0.9), Vector3(0, 0.7, -2.4), body) # 垂尾
	add_box.call(Vector3(0.7, 0.45, 1.2), Vector3(0, 0.6, 0.8), dark)  # 座舱
	root.visible = false
	add_child(root)
	return root


func _sync_plane_vis(p: Dictionary) -> void:
	var vis: Node3D = p["vis"]
	vis.visible = p["alive"]
	vis.position = p["pos"]
	# 前向 = (sin h, 0, cos h)；rotation.x 正 = 低头，故爬升取负
	vis.rotation = Vector3(-float(p["pitch"]), float(p["heading"]),
			float(p["roll"]))


## 玩家战机：W/S 油门 · A/D 转弯 · ↑/↓ 俯仰（原始物理键采样）
func update_player_plane(dt: float) -> void:
	var p := ally_plane
	if not p["alive"]:
		return
	if p["landed"]:
		# 停机：油门拉满起飞
		p["throttle"] = 0.0
		if Input.is_physical_key_pressed(KEY_W):
			p["throttle"] = 1.0
		if p["throttle"] > 0.9:
			p["landed"] = false
			p["speed"] = PLANE_SPEED_MIN
		else:
			p["speed"] = 0.0
			_sync_plane_vis(p)
			return
	else:
		if Input.is_physical_key_pressed(KEY_W):
			p["throttle"] = minf(1.0, float(p["throttle"]) + 0.55 * dt)
		if Input.is_physical_key_pressed(KEY_S):
			p["throttle"] = maxf(0.0, float(p["throttle"]) - 0.55 * dt)
	# 转向 + 侧倾（A/D 与 ←/→ 等效）
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_A) \
			or Input.is_physical_key_pressed(KEY_LEFT):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_RIGHT):
		turn -= 1.0
	p["heading"] = float(p["heading"]) + turn * PLANE_TURN * dt
	p["roll"] = lerpf(float(p["roll"]), turn * 0.55, 1.0 - exp(-5.0 * dt))
	# 俯仰：↑ 拉起 ↓ 俯冲，无输入缓慢回平
	var pitch_in := 0.0
	if Input.is_physical_key_pressed(KEY_UP):
		pitch_in += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		pitch_in -= 1.0
	if pitch_in != 0.0:
		p["pitch"] = clampf(float(p["pitch"]) + pitch_in * PLANE_PITCH_RATE * dt,
				-0.55, 0.6)
	else:
		p["pitch"] = move_toward(float(p["pitch"]), 0.0, 0.35 * dt)
	# 速度：油门目标 + 爬升掉速
	var target_spd := PLANE_SPEED_MIN \
			+ (PLANE_SPEED_MAX - PLANE_SPEED_MIN) * float(p["throttle"])
	target_spd -= sin(float(p["pitch"])) * 14.0
	p["speed"] = clampf(move_toward(float(p["speed"]), target_spd,
			20.0 * dt), 12.0, PLANE_SPEED_MAX + 8.0)
	# 位移（前向 = (sin h, 0, cos h)）
	var fwd := Vector3(sin(float(p["heading"])), 0,
			cos(float(p["heading"])))
	p["pos"] = Vector3(p["pos"]) \
			+ fwd * float(p["speed"]) * cos(float(p["pitch"])) * dt
	p["pos"] = Vector3(p["pos"]) \
			+ Vector3(0, sin(float(p["pitch"])), 0) * float(p["speed"]) * dt
	# 高度钳制
	var ground: float = bmap.terrain_height(p["pos"].x, p["pos"].z) \
			+ PLANE_MIN_ALT
	if p["pos"].y < ground:
		p["pos"] = Vector3(p["pos"].x, ground, p["pos"].z)
		p["pitch"] = maxf(float(p["pitch"]), 0.0)
	p["pos"] = Vector3(clampf(p["pos"].x, -260.0, 260.0),
			minf(p["pos"].y, PLANE_ALT_MAX),
			clampf(p["pos"].z, -260.0, 260.0))
	# 落地判定：贴地且低速
	var alt: float = p["pos"].y - bmap.terrain_height(p["pos"].x, p["pos"].z)
	p["landed"] = alt < PLANE_MIN_ALT + 0.6 and p["speed"] < 14.0
	if p["landed"]:
		p["speed"] = maxf(0.0, float(p["speed"]) - 26.0 * dt)
	_sync_plane_vis(p)


func player_drop_bomb() -> bool:
	var p := ally_plane
	if not p["alive"] or p["landed"] or int(p["bombs"]) <= 0:
		return false
	p["bombs"] = int(p["bombs"]) - 1
	var fwd := Vector3(sin(float(p["heading"])), 0, cos(float(p["heading"])))
	_drop_bomb(Vector3(p["pos"]) - Vector3(0, 1.8, 0),
			fwd * float(p["speed"]), true)
	return true


func _drop_bomb(pos: Vector3, vel: Vector3, by_player: bool) -> void:
	var vis := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.16
	mesh.height = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	mesh.material = mat
	vis.mesh = mesh
	vis.position = pos
	add_child(vis)
	bombs.append({"vis": vis, "pos": pos, "vel": vel,
			"by_player": by_player})


func _update_bombs(dt: float) -> void:
	for i in range(bombs.size() - 1, -1, -1):
		var b: Dictionary = bombs[i]
		var v: Vector3 = b["vel"]
		v.y -= 15.0 * dt
		b["vel"] = v
		b["pos"] = Vector3(b["pos"]) + v * dt
		var vis: MeshInstance3D = b["vis"]
		vis.position = b["pos"]
		vis.look_at(b["pos"] + v.normalized(), Vector3.UP)
		var ground: float = bmap.terrain_height(b["pos"].x, b["pos"].z) + 0.4
		if b["pos"].y <= ground:
			vis.queue_free()
			_explode(Vector3(b["pos"].x, ground, b["pos"].z),
					BOMB_RADIUS, BOMB_DMG, b["by_player"])
			bombs.remove_at(i)


func _explode(pos: Vector3, radius: float, dmg: float, by_player: bool) -> void:
	# 视觉：发光球扩到半径 + 灰烟 + 点光
	var slot: Dictionary = _ex_pool[_ex_i]
	_ex_i = (_ex_i + 1) % _ex_pool.size()
	slot["mi"].global_position = pos
	slot["light"].global_position = pos + Vector3(0, 1.5, 0)
	slot["mi"].scale = Vector3.ONE * (radius * 0.25)
	slot["mi"].visible = true
	slot["light"].visible = true
	slot["t"] = 0.45
	slot["radius"] = radius
	# 伤害：两军士兵 + 敌机 + 步行玩家（距离内一视同仁）
	for team_i in 2:
		var arr: Array = enemies if team_i == 0 else allies
		for s in arr:
			if s["dead"]:
				continue
			if s["pos"].distance_to(pos) <= radius:
				_damage_soldier(s, dmg, by_player and s["team"] == "enemy")
	for ep in enemy_planes:
		if ep["alive"] and Vector3(ep["pos"]).distance_to(pos) <= radius + 4.0:
			_damage_plane(ep, dmg, by_player)
	if player_alive and not player_flying \
			and player_pos.distance_to(pos) <= radius:
		player_hit.emit(dmg * 0.8)
	explosion_at.emit(pos)


func _damage_plane(p: Dictionary, dmg: float, by_player: bool) -> void:
	if not p["alive"]:
		return
	p["hp"] = float(p["hp"]) - dmg
	if float(p["hp"]) > 0.0:
		return
	p["alive"] = false
	p["respawn_t"] = PLANE_RESPAWN if p["enemy"] else ALLY_PLANE_RESPAWN
	_explode(Vector3(p["pos"]), 10.0, 20.0, false)
	plane_down.emit(p["enemy"], by_player)


## 敌机 AI：绕场盘旋 → 掠过时扫射我方 → 过顶投弹（落点带散布）
func _update_enemy_plane(p: Dictionary, dt: float) -> void:
	if not p["alive"]:
		p["respawn_t"] = float(p["respawn_t"]) - dt
		if p["respawn_t"] <= 0.0:
			p["alive"] = true
			p["hp"] = PLANE_HP
			p["bombs"] = PLANE_BOMBS
			p["speed"] = 55.0
			p["throttle"] = 0.8
			p["landed"] = false
			p["pos"] = Vector3(randf_range(-160.0, 160.0), 50.0, -180.0)
		return
	p["orbit_ang"] = float(p["orbit_ang"]) + 0.09 * dt
	var tgt := Vector3(cos(float(p["orbit_ang"])) * 150.0,
			float(p["orbit_alt"]) + sin(_t * 0.4) * 6.0,
			sin(float(p["orbit_ang"])) * 120.0)
	# 扫射窗口：接近我方集群 → 朝集群俯冲开火
	p["strafe_t"] = float(p["strafe_t"]) - dt
	var cluster := _nearest_cluster(allies)
	var d_cluster: float = (Vector2(p["pos"].x, p["pos"].z)
			.distance_to(Vector2(cluster.x, cluster.z)))
	if p["burst_n"] > 0:
		p["burst_t"] = float(p["burst_t"]) - dt
		if float(p["burst_t"]) <= 0.0:
			p["burst_n"] = int(p["burst_n"]) - 1
			p["burst_t"] = 0.11
			_plane_strafe_shot(p, cluster)
	elif p["strafe_t"] <= 0.0 and d_cluster < 130.0:
		p["burst_n"] = 6
		p["burst_t"] = 0.0
		p["strafe_t"] = randf_range(7.0, 13.0)
	# 投弹：过顶（水平距集群 <26m）且装填好
	p["bomb_t"] = float(p["bomb_t"]) - dt
	if p["bomb_t"] <= 0.0 and int(p["bombs"]) > 0 and d_cluster < 26.0:
		p["bombs"] = int(p["bombs"]) - 1
		p["bomb_t"] = randf_range(22.0, 36.0)
		var miss := Vector3(randf_range(-14.0, 14.0), 0,
				randf_range(-14.0, 14.0))
		var fwd := Vector3(sin(float(p["heading"])), 0,
				cos(float(p["heading"])))
		_drop_bomb(Vector3(p["pos"]) - Vector3(0, 1.8, 0),
				fwd * float(p["speed"]) * 0.8, false)
	# 朝目标点转向/升降
	var to_t := tgt - Vector3(p["pos"])
	var want_h := atan2(to_t.x, to_t.z)
	var dh := wrapf(want_h - float(p["heading"]), -PI, PI)
	p["heading"] = float(p["heading"]) + clampf(dh, -1.0, 1.0) * PLANE_TURN * dt
	p["roll"] = lerpf(float(p["roll"]), clampf(dh, -1.0, 1.0) * 0.55,
			1.0 - exp(-4.0 * dt))
	var want_pitch := clampf((tgt.y - p["pos"].y) * 0.03, -0.4, 0.4)
	p["pitch"] = lerpf(float(p["pitch"]), want_pitch, 1.0 - exp(-2.0 * dt))
	p["speed"] = 55.0
	var fwd := Vector3(sin(float(p["heading"])), 0, cos(float(p["heading"])))
	p["pos"] = Vector3(p["pos"]) \
			+ fwd * float(p["speed"]) * cos(float(p["pitch"])) * dt
	p["pos"] = Vector3(p["pos"]) \
			+ Vector3(0, sin(float(p["pitch"])), 0) * float(p["speed"]) * dt
	var ground: float = bmap.terrain_height(p["pos"].x, p["pos"].z) + 26.0
	p["pos"] = Vector3(p["pos"].x, maxf(p["pos"].y, ground), p["pos"].z)
	_sync_plane_vis(p)


func _nearest_cluster(arr: Array) -> Vector3:
	# 我方存活士兵的质心（简单代表性目标点）
	var acc := Vector3.ZERO
	var n := 0
	for s in arr:
		if not s["dead"]:
			acc += s["pos"]
			n += 1
	if n == 0:
		return Vector3(ally_plane["pos"].x, 0, ally_plane["pos"].z)
	return acc / float(n)


func _plane_strafe_shot(p: Dictionary, cluster: Vector3) -> void:
	# 朝集群内随机目标开火：士兵 60% 命中；玩家步行也在打击范围
	var muzz := Vector3(p["pos"])
	if player_alive and not player_flying and randf() < 0.3 \
			and player_pos.distance_to(cluster) < 30.0:
		_spawn_tracer(muzz, player_pos + Vector3(0, 1.2, 0))
		if randf() < 0.5:
			player_hit.emit(randf_range(4.0, 8.0))
		return
	var cands: Array = []
	for s in allies:
		if not s["dead"] and s["pos"].distance_to(cluster) < 30.0:
			cands.append(s)
	if cands.is_empty():
		_spawn_tracer(muzz, cluster + Vector3(0, 0.5, 0))
		return
	var tgt: Dictionary = cands[randi() % cands.size()]
	var aim: Vector3 = tgt["pos"] + Vector3(randf_range(-1.5, 1.5),
			1.0, randf_range(-1.5, 1.5))
	_spawn_tracer(muzz, aim)
	if randf() < 0.55:
		_damage_soldier(tgt, randf_range(5.0, 9.0), false)


func _update_flak(dt: float) -> void:
	# 玩家低空飞行时敌兵对空开火（概率命中，扣战机血）
	if not player_flying or not ally_plane["alive"]:
		return
	if ally_plane["pos"].y - bmap.terrain_height(
			ally_plane["pos"].x, ally_plane["pos"].z) > 46.0:
		return
	for s in enemies:
		if s["dead"] or s["fire_cd"] > 0.0:
			continue
		var d: float = s["pos"].distance_to(ally_plane["pos"])
		if d > 95.0:
			continue
		s["fire_cd"] = randf_range(1.0, 1.8)
		_spawn_tracer(s["pos"] + Vector3(0, 1.45, 0),
				ally_plane["pos"] + Vector3(randf_range(-2.5, 2.5),
				randf_range(-2.0, 2.0), randf_range(-2.5, 2.5)))
		if randf() < 0.32:
			_damage_plane(ally_plane, randf_range(1.5, 3.0), false)
		if _snd_budget >= 1.0 and d < 140.0:
			_snd_budget -= 1.0
			audio.play_police_shot(d)
		break   # 每帧至多一名敌兵对空射击


## 玩家子弹可命中敌机
func _raycast_planes(from: Vector3, dir: Vector3, best: Dictionary) -> Dictionary:
	for ep in enemy_planes:
		if not ep["alive"]:
			continue
		var t: float = (Vector3(ep["pos"]) - from).dot(dir)
		if t < 1.0 or t > best["d"]:
			continue
		if (Vector3(ep["pos"]) - from - dir * t).length() < 2.8:
			best = {"type": "eplane", "i": enemy_planes.find(ep), "d": t,
					"point": from + dir * t}
	return best


func start() -> void:
	active = true
	battle_over = false
	win = false
	wave = 1
	kills = 0
	player_alive = true
	player_flying = false
	allies.clear()
	enemies.clear()
	for i in ALLY_COUNT:
		allies.append(_make_soldier("ally",
				Vector3(-66.0 + 12.0 * i, 0, 78.0 + randf_range(-4, 4))))
	_spawn_wave(1)
	# 战机复位：我方停机坪待命，敌机全部到场
	for b in bombs:
		b["vis"].queue_free()
	bombs.clear()
	ally_plane["pos"] = Vector3(18.0, bmap.terrain_height(18.0, 150.0) + 1.2,
			150.0)
	ally_plane["heading"] = PI   # 机头朝北（敌军方向）
	ally_plane["pitch"] = 0.0
	ally_plane["roll"] = 0.0
	ally_plane["speed"] = 0.0
	ally_plane["throttle"] = 0.0
	ally_plane["hp"] = PLANE_HP
	ally_plane["bombs"] = PLANE_BOMBS
	ally_plane["alive"] = true
	ally_plane["landed"] = true
	for i in enemy_planes.size():
		var ep: Dictionary = enemy_planes[i]
		ep["alive"] = true
		ep["hp"] = PLANE_HP
		ep["bombs"] = PLANE_BOMBS
		ep["landed"] = false
		ep["speed"] = 55.0
		ep["throttle"] = 0.8
		ep["orbit_ang"] = PI * i
		ep["pos"] = Vector3(cos(ep["orbit_ang"]) * 150.0,
				float(ep["orbit_alt"]), sin(ep["orbit_ang"]) * 120.0 - 40.0)
		_sync_plane_vis(ep)
	_sync_plane_vis(ally_plane)


## ================= 士兵 =================

func _make_soldier(team: String, pos: Vector3) -> Dictionary:
	return {
		"team": team, "pos": pos, "yaw": 0.0, "hp": SOLDIER_HP,
		"dead": false, "posed": false,
		"tgt_i": -1, "tgt_player": false,
		"fire_cd": randf_range(0.5, 1.5), "burst": 0,
		"mag": MAG, "reload_t": 0.0,
		"los_ok": false, "los_t": randf_range(0.0, 0.4),
		"tgt_t": randf_range(0.0, 0.5),
		"strafe_t": 0.0, "strafe_dir": 1.0,
		"speed": randf_range(5.5, 8.5),
		"phase": randf() * TAU, "moving": false,
	}


func _spawn_wave(n: int) -> void:
	wave = n
	var z0 := -78.0 if n == 1 else -130.0
	for i in ENEMY_WAVE:
		enemies.append(_make_soldier("enemy",
				Vector3(-66.0 + 12.0 * i, 0, z0 - randf_range(0, 12))))
	wave_started.emit(n)


func army_alive(team: String) -> int:
	var arr: Array = allies if team == "ally" else enemies
	var n := 0
	for s in arr:
		if not s["dead"]:
			n += 1
	return n


# ================= 主更新 =================

func update(dt: float) -> void:
	_t += dt
	_snd_budget = minf(_snd_budget + dt * 6.0, 6.0)
	_tick_fx(dt)
	_tick_explosions(dt)
	_update_bombs(dt)
	for ep in enemy_planes:
		_update_enemy_plane(ep, dt)
	if not player_flying:
		_sync_plane_vis(ally_plane)   # 停机/玩家未登机时同步停机坪姿态
	_update_flak(dt)
	if not active:
		return
	if battle_over:
		return
	for s in allies:
		_update_soldier(s, dt, true)
	for i in enemies.size():
		_update_soldier(enemies[i], dt, false)
	# 波次推进：本波全灭 → 下一波增援；全部歼灭 → 胜利
	if army_alive("enemy") == 0:
		var next_wave: int = wave + 1
		if next_wave <= TOTAL_WAVES and enemies.size() < ENEMY_WAVE * next_wave:
			_spawn_wave(next_wave)
		else:
			_finish(true)
		return
	# 战败：我方全灭且玩家处于死亡等待（飞行中不算失去战斗力）
	if army_alive("ally") == 0 and not player_alive and not player_flying:
		_finish(false)


func _finish(did_win: bool) -> void:
	battle_over = true
	win = did_win
	over.emit(win, kills)


func _update_soldier(s: Dictionary, dt: float, is_ally: bool) -> void:
	if s["dead"]:
		return
	# 目标选择（错峰）：敌兵可锁定玩家
	s["tgt_t"] = float(s["tgt_t"]) - dt
	var tgt: Dictionary = {}
	var foes: Array = enemies if is_ally else allies
	if float(s["tgt_t"]) <= 0.0:
		s["tgt_t"] = randf_range(0.5, 0.7)
		var bd := INF
		var best_i := -1
		for i in foes.size():
			var f: Dictionary = foes[i]
			if f["dead"]:
				continue
			var d2: float = (Vector2(f["pos"].x, f["pos"].z)
					- Vector2(s["pos"].x, s["pos"].z)).length_squared()
			if d2 < bd:
				bd = d2
				best_i = i
		s["tgt_i"] = best_i
		s["tgt_player"] = false
		if not is_ally and player_alive:
			var pd: float = s["pos"].distance_to(player_pos)
			if best_i < 0 or pd * pd < bd:
				s["tgt_i"] = -1
				s["tgt_player"] = true
	# 目标坐标（胸口）
	var t_pos: Vector3
	if s["tgt_player"]:
		t_pos = player_pos + Vector3(0, 1.2, 0)
	elif s["tgt_i"] >= 0 and not foes[s["tgt_i"]]["dead"]:
		t_pos = foes[s["tgt_i"]]["pos"] + Vector3(0, 1.2, 0)
	else:
		t_pos = Vector3.ZERO
		_stop_move(s)
		return
	var to_t: Vector3 = t_pos - s["pos"]
	var dist := Vector2(to_t.x, to_t.z).length()
	# 视线（错峰 0.4s）
	s["los_t"] = float(s["los_t"]) - dt
	if float(s["los_t"]) <= 0.0:
		s["los_t"] = 0.4
		s["los_ok"] = _los(s["pos"] + Vector3(0, 1.5, 0), t_pos)
	# 走位：远则推进；近则侧移；无视线则压进
	var move := Vector2.ZERO
	if dist > ENGAGE_DIST or not s["los_ok"]:
		if dist > 0.5:
			move = Vector2(to_t.x, to_t.z) / maxf(dist, 0.01)
	else:
		s["strafe_t"] = float(s["strafe_t"]) - dt
		if float(s["strafe_t"]) <= 0.0:
			s["strafe_t"] = randf_range(2.0, 4.0)
			s["strafe_dir"] = -float(s["strafe_dir"])
		var fwd := Vector2(to_t.x, to_t.z) / maxf(dist, 0.01)
		move = Vector2(-fwd.y, fwd.x) * float(s["strafe_dir"])
	_apply_move(s, move, dt)
	_write_pose(s)
	# 开火
	_try_fire(s, is_ally, t_pos, dist, dt)


func _stop_move(s: Dictionary) -> void:
	s["moving"] = false
	_write_pose(s)


func _apply_move(s: Dictionary, move: Vector2, dt: float) -> void:
	var vel := move * float(s["speed"])
	# 队友间隔（廉价推挤）
	var arr: Array = allies if s["team"] == "ally" else enemies
	for o in arr:
		if o == s or o["dead"]:
			continue
		var dv: Vector2 = Vector2(s["pos"].x - o["pos"].x,
				s["pos"].z - o["pos"].z)
		var d := dv.length()
		if d > 0.01 and d < 2.5:
			vel += dv / d * (2.5 - d) * 2.0
	var np := Vector2(s["pos"].x, s["pos"].z) + vel * dt
	np.x = clampf(np.x, -ARENA_X, ARENA_X)
	np.y = clampf(np.y, -ARENA_Z, ARENA_Z)
	s["pos"] = Vector3(np.x, bmap.terrain_height(np.x, np.y), np.y)
	# OBB 推出
	for ob in bmap.obstacles_box:
		var dx: float = np.x - ob["c"].x
		var dz: float = np.y - ob["c"].y
		if dx * dx + dz * dz > 8100.0:
			continue
		var ca: float = cos(ob["rot"])
		var sa: float = sin(ob["rot"])
		var lx: float = ca * dx + sa * dz
		var lz: float = -sa * dx + ca * dz
		var px: float = ob["hx"] + 0.4 - absf(lx)
		var pz: float = ob["hz"] + 0.4 - absf(lz)
		if px > 0.0 and pz > 0.0:
			if px < pz:
				lx = signf(lx) * (ob["hx"] + 0.4)
			else:
				lz = signf(lz) * (ob["hz"] + 0.4)
			np.x = ob["c"].x + ca * lx - sa * lz
			np.y = ob["c"].y + sa * lx + ca * lz
			s["pos"] = Vector3(np.x,
					bmap.terrain_height(np.x, np.y), np.y)
	if move.length_squared() > 0.01:
		s["yaw"] = atan2(move.x, move.y)
		s["moving"] = true
	else:
		s["moving"] = false


# ================= 开火 =================

func _try_fire(s: Dictionary, is_ally: bool, t_pos: Vector3,
		dist: float, dt: float) -> void:
	s["fire_cd"] = float(s["fire_cd"]) - dt
	if float(s["fire_cd"]) > 0.0:
		return
	if s["reload_t"] > 0.0:
		s["reload_t"] = float(s["reload_t"]) - dt
		return
	if s["mag"] <= 0:
		s["reload_t"] = 2.0
		s["mag"] = MAG
		return
	if not s["los_ok"] or dist > FIRE_RANGE:
		return
	if s["burst"] <= 0:
		s["burst"] = 3
	# 打出一发
	s["burst"] = int(s["burst"]) - 1
	s["mag"] = int(s["mag"]) - 1
	s["fire_cd"] = 0.12 if int(s["burst"]) > 0 else randf_range(0.9, 1.6)
	var eye: Vector3 = s["pos"] + Vector3(0, 1.45, 0)
	var dir := (t_pos - eye).normalized()
	dir += Vector3(randf() - 0.5, (randf() - 0.5) * 0.5, randf() - 0.5) * 0.06
	dir = dir.normalized()
	_ballistic_shot(s, eye, dir, is_ally)


## AI 弹道：球形命中（敌我士兵 / 玩家）+ 墙体步进，最近者结算
func _ballistic_shot(s: Dictionary, eye: Vector3, dir: Vector3,
		is_ally: bool) -> void:
	var max_d := FIRE_RANGE + 20.0
	var best_d := max_d
	var best_kind := ""
	var best_i := -1
	var foes: Array = enemies if is_ally else allies
	for i in foes.size():
		var f: Dictionary = foes[i]
		if f["dead"]:
			continue
		var c: Vector3 = f["pos"] + Vector3(0, 1.1, 0)
		var t: float = (c - eye).dot(dir)
		if t < 0.5 or t > best_d:
			continue
		if (c - eye - dir * t).length() < 0.55:
			best_d = t
			best_kind = "enemy" if is_ally else "ally"
			best_i = i
	# 敌兵可命中玩家
	if not is_ally and player_alive:
		var c: Vector3 = player_pos + Vector3(0, 1.2, 0)
		var t: float = (c - eye).dot(dir)
		if t > 0.5 and t < best_d \
				and (c - eye - dir * t).length() < 0.55:
			best_d = t
			best_kind = "player"
	# 墙体步进
	var t2 := 2.0
	while t2 < best_d:
		var p: Vector3 = eye + dir * t2
		for ob in bmap.obstacles_box:
			var dx: float = p.x - ob["c"].x
			var dz: float = p.z - ob["c"].y
			if dx * dx + dz * dz > 8100.0:
				continue
			if p.y > ob["top"]:
				continue
			var ca: float = cos(ob["rot"])
			var sa: float = sin(ob["rot"])
			var lx: float = ca * dx + sa * dz
			var lz: float = -sa * dx + ca * dz
			if absf(lx) <= ob["hx"] and absf(lz) <= ob["hz"]:
				best_d = t2
				best_kind = "wall"
				t2 = best_d + 1.0
				break
		t2 += 3.0
	var end := eye + dir * best_d
	var muzzle: Vector3 = s["pos"] + Vector3(sin(s["yaw"]) * 0.5, 1.38,
			cos(s["yaw"]) * 0.5)
	_spawn_tracer(muzzle, end)
	match best_kind:
		"enemy", "ally":
			_spawn_impact(end)
			_damage_soldier(foes[best_i], randf_range(5.0, 10.0), false)
		"player":
			_spawn_impact(end)
			player_hit.emit(randf_range(5.0, 10.0))
		"wall":
			_spawn_impact(end)
	# 枪声限流：距玩家 <140m 才出声
	var pd: float = s["pos"].distance_to(player_pos)
	if _snd_budget >= 1.0 and pd < 140.0:
		_snd_budget -= 1.0
		audio.play_police_shot(pd)


func _damage_soldier(s: Dictionary, dmg: float, by_player: bool) -> void:
	if s["dead"]:
		return
	s["hp"] = float(s["hp"]) - dmg
	if float(s["hp"]) > 0.0:
		return
	s["dead"] = true
	s["moving"] = false
	if s["team"] == "enemy":
		_enemies_killed += 1
		enemy_killed.emit(by_player)
	_write_pose(s)


## 玩家子弹结算（game._on_foot_shot 转发）
func player_shot(kind: String, idx: int, dmg: float) -> void:
	if battle_over:
		return
	if kind == "enemy":
		var s: Dictionary = enemies[idx]
		var was_alive: bool = not s["dead"]
		_damage_soldier(s, dmg, true)
		if was_alive and s["dead"]:
			kills += 1
	elif kind == "eplane":
		var ep: Dictionary = enemy_planes[idx]
		if ep["alive"]:
			_damage_plane(ep, dmg, true)
	# "ally"：无友伤（子弹已被挡下）


## onfoot 子弹射线（同 npc.raycast 契约）
func raycast(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var best := {"type": "", "i": -1, "d": max_d, "point": from + dir * max_d}
	for team_i in 2:
		var arr: Array = enemies if team_i == 0 else allies
		var kind: String = "enemy" if team_i == 0 else "ally"
		for i in arr.size():
			if arr[i]["dead"]:
				continue
			var c: Vector3 = arr[i]["pos"] + Vector3(0, 1.1, 0)
			var t: float = (c - from).dot(dir)
			if t < 0.5 or t > best["d"]:
				continue
			if (c - from - dir * t).length() < 0.55:
				best = {"type": kind, "i": i, "d": t,
						"point": from + dir * t}
	best = _raycast_planes(from, dir, best)
	# 墙体步进（含 top 高度：可越过矮掩体）
	var t2 := 2.0
	while t2 < best["d"]:
		var p: Vector3 = from + dir * t2
		for ob in bmap.obstacles_box:
			var dx: float = p.x - ob["c"].x
			var dz: float = p.z - ob["c"].y
			if dx * dx + dz * dz > 8100.0:
				continue
			if p.y > ob["top"]:
				continue
			var ca: float = cos(ob["rot"])
			var sa: float = sin(ob["rot"])
			var lx: float = ca * dx + sa * dz
			var lz: float = -sa * dx + ca * dz
			if absf(lx) <= ob["hx"] and absf(lz) <= ob["hz"]:
				best = {"type": "wall", "i": -1, "d": t2, "point": p}
				t2 = best["d"] + 1.0
				break
		t2 += 3.0
	return best


## 视线判定：步进测 OBB（含 top）
func _los(from: Vector3, to: Vector3) -> bool:
	var dir := to - from
	var dist := dir.length()
	if dist < 0.5:
		return true
	dir = dir / dist
	var t := 2.0
	while t < dist:
		var p: Vector3 = from + dir * t
		for ob in bmap.obstacles_box:
			var dx: float = p.x - ob["c"].x
			var dz: float = p.z - ob["c"].y
			if dx * dx + dz * dz > 8100.0:
				continue
			if p.y > ob["top"]:
				continue
			var ca: float = cos(ob["rot"])
			var sa: float = sin(ob["rot"])
			var lx: float = ca * dx + sa * dz
			var lz: float = -sa * dx + ca * dz
			if absf(lx) <= ob["hx"] and absf(lz) <= ob["hz"]:
				return false
		t += 3.0
	return true


# ================= 士兵渲染（每队 MultiMesh：头/躯干/双臂/双腿/枪） =================

func _setup_army_mm(team: String, count: int) -> void:
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.44, 0.62, 0.26)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.11, 0.5, 0.12)
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.15, 0.82, 0.17)
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.08, 0.1, 0.72)
	_mm[team] = {
		"head": _make_mm(head_mesh, count),
		"torso": _make_mm(torso_mesh, count),
		"arm": _make_mm(arm_mesh, count * 2),
		"leg": _make_mm(leg_mesh, count * 2),
		"gun": _make_mm(gun_mesh, count),
	}
	# 队服配色
	var uniform: Color = Color(0.3, 0.42, 0.6) if team == "ally" \
			else Color(0.55, 0.22, 0.18)
	var helmet: Color = Color(0.22, 0.3, 0.44) if team == "ally" \
			else Color(0.35, 0.15, 0.12)
	var mm: Dictionary = _mm[team]
	for i in count:
		mm["torso"].multimesh.set_instance_color(i, uniform)
		mm["head"].multimesh.set_instance_color(i, Color(0.85, 0.68, 0.55))
		mm["arm"].multimesh.set_instance_color(i * 2, uniform)
		mm["arm"].multimesh.set_instance_color(i * 2 + 1, uniform)
		mm["leg"].multimesh.set_instance_color(i * 2, Color(0.2, 0.22, 0.26))
		mm["leg"].multimesh.set_instance_color(i * 2 + 1,
				Color(0.2, 0.22, 0.26))
		mm["gun"].multimesh.set_instance_color(i, Color(0.12, 0.12, 0.13))


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
	var arr: Array = allies if s["team"] == "ally" else enemies
	var i := arr.find(s)
	if i < 0:
		return
	var mm: Dictionary = _mm[s["team"]]
	var dead: bool = s["dead"]
	var yaw: float = s["yaw"]
	var bob: float = absf(sin(_t * 9.0 + float(s["phase"]))) * 0.04 \
			if s["moving"] else 0.0
	var swing := sin(_t * 9.0 + float(s["phase"])) * 0.45 if s["moving"] \
			else 0.0
	var root_pos: Vector3 = s["pos"] + Vector3(0, bob, 0)
	# 阵亡：绕 X 翻倒贴地（只写一次）
	var root := Transform3D(Basis.from_euler(Vector3(PI * 0.5, yaw, 0)
			if dead else Vector3(0, yaw, 0)), root_pos)
	mm["torso"].multimesh.set_instance_transform(i,
			root * Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0)))
	mm["head"].multimesh.set_instance_transform(i,
			root * Transform3D(Basis.IDENTITY, Vector3(0, 1.58, 0)))
	if dead:
		# 倒地：四肢摊开、枪落地
		mm["arm"].multimesh.set_instance_transform(i * 2, root *
				Transform3D(Basis.from_euler(Vector3(0, 0, 1.2)),
				Vector3(-0.3, 1.15, 0)))
		mm["arm"].multimesh.set_instance_transform(i * 2 + 1, root *
				Transform3D(Basis.from_euler(Vector3(0, 0, -1.2)),
				Vector3(0.3, 1.15, 0)))
		mm["leg"].multimesh.set_instance_transform(i * 2, root *
				Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0.2)),
				Vector3(-0.11, 0.42, 0)))
		mm["leg"].multimesh.set_instance_transform(i * 2 + 1, root *
				Transform3D(Basis.from_euler(Vector3(0.2, 0, -0.2)),
				Vector3(0.11, 0.42, 0)))
		mm["gun"].multimesh.set_instance_transform(i, root *
				Transform3D(Basis.IDENTITY, Vector3(0.5, 0.1, 0.3)))
		return
	# 持枪双臂前伸 + 摆腿
	var aim := Basis.from_euler(Vector3(-1.25, 0, 0))
	mm["arm"].multimesh.set_instance_transform(i * 2, root *
			Transform3D(aim, Vector3(-0.14, 1.32, 0.18)))
	mm["arm"].multimesh.set_instance_transform(i * 2 + 1, root *
			Transform3D(aim, Vector3(0.14, 1.32, 0.18)))
	var hip_l := Transform3D(Basis.from_euler(Vector3(swing, 0, 0)),
			Vector3(-0.11, 0.83, 0))
	var hip_r := Transform3D(Basis.from_euler(Vector3(-swing, 0, 0)),
			Vector3(0.11, 0.83, 0))
	var leg_off := Transform3D(Basis.IDENTITY, Vector3(0, -0.41, 0))
	mm["leg"].multimesh.set_instance_transform(i * 2, root * hip_l * leg_off)
	mm["leg"].multimesh.set_instance_transform(i * 2 + 1, root * hip_r * leg_off)
	# 枪贴胸前（双臂之间前指）
	mm["gun"].multimesh.set_instance_transform(i, root *
			Transform3D(Basis.from_euler(Vector3(-1.35, 0, 0)),
			Vector3(0, 1.32, 0.32)))


# ================= 曳光 / 火花对象池 =================

func _setup_fx() -> void:
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 0.85, 0.45)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.75, 0.3)
	tmat.emission_energy_multiplier = 4.0
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(0.025, 0.025, 1.0)
	tmesh.material = tmat
	for i in 24:
		var mi := MeshInstance3D.new()
		mi.mesh = tmesh
		mi.visible = false
		add_child(mi)
		_tr_pool.append({"mi": mi, "t": 0.0})
	var imat := StandardMaterial3D.new()
	imat.albedo_color = Color(1.0, 0.75, 0.3)
	imat.emission_enabled = true
	imat.emission = Color(1.0, 0.6, 0.2)
	imat.emission_energy_multiplier = 3.0
	var imesh := SphereMesh.new()
	imesh.radius = 0.05
	imesh.height = 0.1
	imesh.material = imat
	for i in 16:
		var mi := MeshInstance3D.new()
		mi.mesh = imesh
		mi.visible = false
		add_child(mi)
		_im_pool.append({"mi": mi, "t": 0.0})


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var slot: Dictionary = _tr_pool[_tr_i]
	_tr_i = (_tr_i + 1) % _tr_pool.size()
	var mi: MeshInstance3D = slot["mi"]
	var mid := (from + to) * 0.5
	mi.global_position = mid
	mi.look_at_from_position(mid, to, Vector3.UP)
	mi.scale = Vector3(1, 1, from.distance_to(to))
	mi.visible = true
	slot["t"] = 0.18


func _spawn_impact(p: Vector3) -> void:
	var slot: Dictionary = _im_pool[_im_i]
	_im_i = (_im_i + 1) % _im_pool.size()
	slot["mi"].global_position = p
	slot["mi"].visible = true
	slot["t"] = 0.24


## 爆炸视觉池：发光扩爆球 + 瞬时点光
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
	for i in 5:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visible = false
		add_child(mi)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.2)
		light.light_energy = 8.0
		light.omni_range = 30.0
		light.visible = false
		add_child(light)
		_ex_pool.append({"mi": mi, "light": light, "t": 0.0, "radius": 10.0})


func _tick_explosions(dt: float) -> void:
	for slot in _ex_pool:
		if float(slot["t"]) <= 0.0:
			continue
		slot["t"] = float(slot["t"]) - dt
		var k: float = 1.0 - clampf(float(slot["t"]) / 0.45, 0.0, 1.0)
		var mi: MeshInstance3D = slot["mi"]
		mi.scale = Vector3.ONE * (float(slot["radius"]) * (0.25 + 0.75 * k))
		if float(slot["t"]) <= 0.0:
			mi.visible = false
			slot["light"].visible = false


func _tick_fx(dt: float) -> void:
	for s in _tr_pool:
		if float(s["t"]) > 0.0:
			s["t"] = float(s["t"]) - dt
			if float(s["t"]) <= 0.0:
				s["mi"].visible = false
	for s in _im_pool:
		if float(s["t"]) > 0.0:
			s["t"] = float(s["t"]) - dt
			if float(s["t"]) <= 0.0:
				s["mi"].visible = false
