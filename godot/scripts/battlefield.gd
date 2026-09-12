class_name RRBattleField
extends Node3D
## 大战场战斗管理器：我方 AI 与敌方 AI 士兵交战（波次歼灭战）。
## 鸭子类型顶替 onfoot 的 npc 位：raycast(from,dir,max_d) 同契约。

signal player_hit(dmg: float)
signal enemy_killed(by_player: bool)
signal wave_started(n: int)
signal over(win: bool, kills: int)

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

var bmap                      # BattleMap
var audio                     # RRAudio
var player_pos := Vector3.ZERO
var player_alive := true
var active := false
var battle_over := false
var win := false
var wave := 1
var kills := 0                # 玩家击杀数
var _enemies_killed := 0      # 全场歼敌数（波次/胜负判定）

var allies: Array = []
var enemies: Array = []       # 含阵亡尸体（波 2 追加到 idx 12..23）

var _t := 0.0
var _snd_budget := 6.0        # AI 枪声限流（每秒 ≤6 次）
var _tr_pool: Array = []
var _im_pool: Array = []
var _tr_i := 0
var _im_i := 0
# 每队一套 MultiMesh（头/躯干/双臂/双腿/枪），人数上限 = 预留容量
var _mm := {}                 # team -> {head, torso, arm, leg, gun}


func setup(bmap_ref, audio_ref) -> void:
	bmap = bmap_ref
	audio = audio_ref
	_setup_fx()
	_setup_army_mm("ally", ALLY_COUNT)
	_setup_army_mm("enemy", ENEMY_WAVE * TOTAL_WAVES)


func start() -> void:
	active = true
	battle_over = false
	win = false
	wave = 1
	kills = 0
	player_alive = true
	allies.clear()
	enemies.clear()
	for i in ALLY_COUNT:
		allies.append(_make_soldier("ally",
				Vector3(-66.0 + 12.0 * i, 0, 78.0 + randf_range(-4, 4))))
	_spawn_wave(1)


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
	# 战败：我方全灭且玩家处于死亡等待
	if army_alive("ally") == 0 and not player_alive:
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
