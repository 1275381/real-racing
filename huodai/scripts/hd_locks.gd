extends Node
## 烽火地带 —— 钥匙锁房系统（2026-10「更好玩」阶段 B）
## 三间上锁小屋（军火库/档案室/军营武器室，HDData.LOCKS 表）：混凝土房 + 钢门 +
## 红锁灯；玩家持对应钥匙按 F 开锁（消耗钥匙、门上滑、锁灯变绿、房内容器生成）。
## 钥匙不入商店：每局按种子在随机容器点位旁刷（60%/把，HDData.KEY_SPAWN_P），
## 地面拾取进背包（紫档 ₵800，带走可变卖——不用也是货）。
## 无 class_name（-s 测试/探针跑法不刷新全局类缓存，一律 preload——照 airdrop 先例）。

signal unlocked(lock_id: String)               # 开锁（main 生成房内容器 + 播报）
signal prompt(text: String, progress: float)   # 与 hd_loot.prompt 同款（无目标发 ("",0)）

const WALL_H := 3.0
const WALL_T := 0.3
const ROOM_HALF := 2.0
const DOOR_W := 1.6
const DOOR_H := 2.6

var _world                           # HDWorld（obstacles 追加/移除）
var _loot                            # HDLoot（背包查钥匙/消耗）
var _states := {}                    # id -> {def, door, lamp_mat, obs, opened, open_t}
var _prev_press := false             # F 边沿检测（开锁瞬时动作，不按住读条）

func setup(world, loot) -> void:
	_world = world
	_loot = loot
	for def in HDData.LOCKS:
		_build_room(def)

func reset_all() -> void:
	for id in _states:
		var st: Dictionary = _states[id]
		st["opened"] = false
		st["open_t"] = 0.0
		(st["door"] as Node3D).position.y = DOOR_H * 0.5 + 0.05
		var lm: StandardMaterial3D = st["lamp_mat"]
		lm.emission = Color(1.0, 0.16, 0.1)
		lm.albedo_color = Color(0.55, 0.1, 0.08)
		if not _world.obstacles.has(st["obs"]):
			_world.obstacles.append(st["obs"])


## 朝向基向量：facing = 门面法线方向（门开在哪面墙）；side = 门墙走向
static func _axes(facing: String) -> Array:
	match facing:
		"E":
			return [Vector2(1, 0), Vector2(0, 1)]    # [f, s]
		"W":
			return [Vector2(-1, 0), Vector2(0, 1)]
		"S":
			return [Vector2(0, 1), Vector2(1, 0)]
		_:
			return [Vector2(0, -1), Vector2(1, 0)]   # N

func _build_room(def: Dictionary) -> void:
	var cx: float = float(def["cx"])
	var cz: float = float(def["cz"])
	var axes: Array = _axes(str(def["door_facing"]))
	var f: Vector2 = axes[0]   # 门面法线（世界系）
	var s: Vector2 = axes[1]   # 门墙走向（世界系）
	var root := Node3D.new()
	root.position = Vector3(cx, 0.0, cz)
	add_child(root)
	var conc := _mats_conc(root)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.24, 0.27, 0.3)
	steel.metallic = 0.6
	steel.roughness = 0.45
	# 地坪 + 顶板（薄板不注册障碍——玩家无垂直位移）
	_box(root, 0.0, 0.03, 0.0, ROOM_HALF * 2.0 + 0.4, 0.08, ROOM_HALF * 2.0 + 0.4, conc)
	_box(root, 0.0, WALL_H + 0.16, 0.0, ROOM_HALF * 2.0 + 0.6, 0.28, ROOM_HALF * 2.0 + 0.6, conc)
	# 背墙（门面正对面，长边沿 s 走向）
	_seg_wall(root, -f * ROOM_HALF, s, ROOM_HALF * 2.0 + WALL_T)
	# 双侧墙（长边沿 f 走向）
	_seg_wall(root, s * ROOM_HALF, f, ROOM_HALF * 2.0 + WALL_T)
	_seg_wall(root, -s * ROOM_HALF, f, ROOM_HALF * 2.0 + WALL_T)
	# 门面：左右门垛（各盖住 角→门缘 的 1.2m 段）+ 中间钢门（薄边朝 f）
	var jlen := ROOM_HALF * 2.0 - DOOR_W   # 2.4m：两垛均分各 1.2
	_seg_wall(root, f * ROOM_HALF + s * (DOOR_W * 0.5 + jlen * 0.25), s, jlen * 0.5 + WALL_T)
	_seg_wall(root, f * ROOM_HALF - s * (DOOR_W * 0.5 + jlen * 0.25), s, jlen * 0.5 + WALL_T)
	var door := _box(root, f.x * ROOM_HALF, DOOR_H * 0.5 + 0.05, f.y * ROOM_HALF,
			WALL_T if f.x != 0.0 else DOOR_W, DOOR_H,
			DOOR_W if f.x != 0.0 else WALL_T, steel)
	var obs := {"cx": cx + f.x * ROOM_HALF, "cz": cz + f.y * ROOM_HALF,
		"hx": 0.15 if f.x != 0.0 else DOOR_W * 0.5,
		"hz": DOOR_W * 0.5 if f.x != 0.0 else 0.15, "top": 2.6, "bot": 0.0}
	_world.obstacles.append(obs)
	# 锁灯：门楣中央小红灯（开锁变绿）
	var lm := StandardMaterial3D.new()
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.16, 0.1)
	lm.albedo_color = Color(0.55, 0.1, 0.08)
	_box(root, f.x * ROOM_HALF, DOOR_H + 0.24, f.y * ROOM_HALF, 0.34, 0.12, 0.12, lm)
	_states[str(def["id"])] = {"def": def, "door": door, "lamp_mat": lm, "obs": obs,
		"opened": false, "open_t": 0.0}


## 沿 dir 走向、中心在 local (lx,lz) 的墙段（local = 房心系；dir 为世界系单位轴）
func _seg_wall(root: Node3D, c: Vector2, dir: Vector2, length: float) -> void:
	var w := length if dir.x != 0.0 else WALL_T
	var d := WALL_T if dir.x != 0.0 else length
	_box(root, c.x, WALL_H * 0.5, c.y, w, WALL_H, d, _mats_conc(root))
	var def: Dictionary = _room_def_of(root)
	_world.obstacles.append({"cx": float(def["cx"]) + c.x, "cz": float(def["cz"]) + c.y,
		"hx": w * 0.5, "hz": d * 0.5, "top": WALL_H, "bot": 0.0})


## 每局钥匙刷新（种子 LCG 确定性）：每把 60% 概率，落点 = 随机容器点位旁
## 0.75m（容器点位保证可达，不落进楼体/围墙）；返回 [{item, pos}]
func roll_key_drops(seed: int, spots: Array) -> Array:
	var out: Array = []
	if spots.is_empty():
		return out
	var s := seed
	for def in HDData.LOCKS:
		s = 1103515245 * s + 12345
		if absi(s) % 1000 >= int(HDData.KEY_SPAWN_P * 1000.0):
			continue
		s = 1103515245 * s + 12345
		var spot: Dictionary = spots[absi(s) % spots.size()]
		var p: Vector3 = spot["pos"]
		s = 1103515245 * s + 12345
		var ang := TAU * float(absi(s) % 1000) / 1000.0
		var pos := Vector3(p.x + cos(ang) * 0.75, p.y, p.z + sin(ang) * 0.75)
		var id := str(def["id"])
		out.append({
			"item": {"uid": "key_%s_%d" % [id, seed], "name": str(def["key"]),
				"icon": "钥匙", "rarity": 3, "value": HDData.KEY_VALUE, "key": id},
			"pos": pos,
		})
	return out


func update(_dt: float, player_pos: Vector3, pressed: bool) -> void:
	var edge := pressed and not _prev_press
	_prev_press = pressed
	for id in _states:
		var st0: Dictionary = _states[id]
		if bool(st0["opened"]) and float(st0["open_t"]) < 1.0:
			st0["open_t"] = minf(1.0, float(st0["open_t"]) + _dt * 1.8)
			(st0["door"] as Node3D).position.y = DOOR_H * 0.5 + 0.05 + 2.35 * float(st0["open_t"])
	# 最近未开锁的门（半径内）
	var best: Dictionary = {}
	var best_d := HDData.LOCK_PROMPT_R
	for id2 in _states:
		var st: Dictionary = _states[id2]
		if bool(st["opened"]):
			continue
		var def: Dictionary = st["def"]
		var dd := Vector2(player_pos.x - float(def["cx"]), player_pos.z - float(def["cz"])).length()
		if dd < best_d:
			best_d = dd
			best = st
	if best.is_empty():
		prompt.emit("", 0.0)
		return
	var def2: Dictionary = best["def"]
	var key_uid := _key_uid(str(def2["id"]))
	if key_uid != "":
		prompt.emit("按 F 用 %s 开启 %s" % [str(def2["key"]), str(def2["room"])], 0.0)
		if edge:
			_open(str(def2["id"]), key_uid)
	else:
		prompt.emit("%s 上锁了 —— 需要 %s（局内容器旁可能刷）" % [str(def2["room"]), str(def2["key"])], 0.0)


## 背包里对应钥匙的 uid（"" = 没带）
func _key_uid(lock_id: String) -> String:
	for it in _loot.backpack:
		if str((it as Dictionary).get("key", "")) == lock_id:
			return str((it as Dictionary).get("uid", ""))
	return ""


func _open(id: String, key_uid: String) -> void:
	var st: Dictionary = _states[id]
	st["opened"] = true
	st["open_t"] = 0.0
	_loot.take_item(key_uid)          # 钥匙消耗
	_world.obstacles.erase(st["obs"]) # 门障碍移除（可入）
	var lm: StandardMaterial3D = st["lamp_mat"]
	lm.emission = Color(0.2, 1.0, 0.4)
	lm.albedo_color = Color(0.1, 0.5, 0.2)
	unlocked.emit(id)


func _box(parent: Node3D, x: float, y: float, z: float, w: float, h: float,
		d: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.set_surface_override_material(0, mat)
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi


## 每房共享一份混凝土材质（root.meta 存）：防一房多墙多份材质
func _mats_conc(root: Node3D) -> StandardMaterial3D:
	if root.has_meta("conc"):
		return root.get_meta("conc") as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.44, 0.42)
	m.roughness = 0.92
	root.set_meta("conc", m)
	return m

func _room_def_of(root: Node3D) -> Dictionary:
	for def in HDData.LOCKS:
		if absf(float(def["cx"]) - root.position.x) < 0.01 \
				and absf(float(def["cz"]) - root.position.z) < 0.01:
			return def
	return {"cx": root.position.x, "cz": root.position.z}
