class_name HDLoot
extends Node3D
## 烽火地带 —— 战利品（容器生成 / 搜索状态机 / 背包），移植自网页版 js/fps/loot.js：
## 每个容器点生成一个箱体（crate.glb 或程序化箱体）+ 顶部琥珀色未搜指示灯
## （呼吸辉光，15-20m 外靠光点找箱子）；2.2m 内最近未搜容器出「按住 F 搜索」
## 提示，按住 1.8s 开箱 → HDData.roll_loot(world.zone_at(...)) 按分区 roll 品质，
## 背包(12 格)未满入包 emit picked；已搜容器灯灭盖开。
## 驱动链与网页版一致：本模块不监听键盘，interact_held 由上层每帧喂入。
## 2026-10 改进方案第 1/5 节：
##   安全箱 secure（secure_cap 格，阵亡保留，main 按 stash.secure_slots 设）；
##   地面物品 _ground：背包弃件丢在脚下、满包开箱的落选件也落地，F 可再捡；
##   满包开箱 = 新件比背包最便宜的一件值钱就自动交换（旧件落地），否则新件落地
##   ——旧版满包直接把 roll 出的东西销毁。

signal prompt(text: String, progress: float)   # 每帧发（无目标发 ("",0)）
signal picked(item: Dictionary)
signal notice(text: String, color: Color)      # 满包交换/落地等提示（main 转 toast）
signal searched(cls: String, zone: String)     # 玩家搜完一个容器（合同推进用；npc_take 不发）

const SEARCH_TIME := 1.8         # 按住 F 开箱所需秒数
const SEARCH_RADIUS := 2.2       # 进入提示的最近距离（XZ 平面）
const PROGRESS_DROP := 0.9       # 松手后进度每秒回退量（不即时清零）
const LID_TIME := 0.5            # 开盖动画时长
const LID_ANGLE := -1.9          # 盖子后翻角度（rad）
const AMBER := Color(1.0, 0.66, 0.3)   # 未搜指示灯琥珀色
const LAMP_BASE := 1.3           # 指示灯呼吸基准亮度
const LAMP_AMP := 0.6            # 呼吸幅度
const GROUND_R := 1.6            # 地面物品拾取半径（XZ，优先于容器）
const GROUND_TIME := 0.35        # 按住 F 拾取地面物品秒数
const NOTICE_COL := Color(1.0, 0.55, 0.3)

## 容器类型（弹药箱/医疗柜/木箱/行李袋，颜色区分）；size 为占地全尺寸
const TYPES := [
	{"id": "ammo", "name": "弹药箱", "color": Color(0.42, 0.5, 0.3),
		"size": Vector3(1.1, 0.7, 0.7)},
	{"id": "med", "name": "医疗柜", "color": Color(0.78, 0.26, 0.24),
		"size": Vector3(0.9, 1.5, 0.6)},
	{"id": "crate", "name": "木箱", "color": Color(0.62, 0.47, 0.28),
		"size": Vector3(1.0, 1.0, 1.0)},
	{"id": "bag", "name": "行李袋", "color": Color(0.45, 0.52, 0.38),
		"size": Vector3(1.25, 0.55, 0.6)},
	{"id": "safe", "name": "保险箱", "color": Color(0.2, 0.21, 0.23),
		"size": Vector3(0.75, 0.85, 0.62)},
	{"id": "airdrop", "name": "空投箱", "color": Color(0.3, 0.36, 0.24),
		"size": Vector3(1.5, 1.0, 1.0)},
]
## 容器分类 → 外观类型（第三阶段：分类决定掉落，外观让玩家远远认得出）
const CLASS_TYPE := {"weapon": 0, "medical": 1, "crate": 2, "safe": 4, "vault": 4, "airdrop": 5}
const VAULT_LAMP := Color(1.0, 0.3, 0.22)   # 首领保险柜指示灯：红（只出红色及以上）
const AIRDROP_LAMP := Color(0.75, 0.45, 1.0)   # 空投箱指示灯：紫（紫色及以上）
## crate.glb 实测 1.02 见方（原点在底面中心），按类型缩放到 size
const CRATE_PATH := "res://assets/battle/props/crate.glb"
const CRATE_DIM := 1.02

var backpack: Array = []         # {uid,name,rarity,value,icon}
var secure: Array = []           # 安全箱（阵亡保留）
var secure_cap: int = HDData.SECURE_BASE

var _ground: Array = []          # 地面物品 {item, pos, node}
var _ground_i := -1              # 当前提示的地面物品下标

var _containers: Array = []      # {pos,zone,type,searched,root,lid_pivot,lamp,lamp_mat,open_t,phase}
var _active_i := -1              # 当前提示容器下标（-1 无）
var _progress := 0.0
var _t := 0.0
var _world                       # HDWorld（zone_at / obstacles 用）
var _crate_scene: PackedScene
var _body_mat_cache := {}        # 类型 id -> StandardMaterial3D（程序化箱体/盖子共用）
## 第四阶段性能（绘制调用 < 800）：容器的网格/材质全部按类型共享——旧版每个容器
## 各自 duplicate 染色材质、各自一张盖子/灯泡网格、各自一枚灯材质，60 个容器
## 实测吃掉约 360 次绘制调用（渲染器自动实例化要求「同网格同材质」）
var _share := {}                 # 键 -> Mesh / Material
var _lamp_sets := {}             # 灯材质键 -> {"mat", "phase"}（呼吸按 3 个相位组错开）


## 在 world.container_spots 每点生成容器（外观 + 指示灯 + 占位障碍登记）
func build(world) -> void:
	_world = world
	_crate_scene = load(CRATE_PATH) if ResourceLoader.exists(CRATE_PATH) else null
	if _crate_scene == null:
		push_warning("[烽火地带] 容器模型加载失败：%s（暂用程序化箱体）" % CRATE_PATH)
	_spawn_static()


## 容器生成主体（build 与换图 rebuild_map 共用）：点位表 + 首领保险柜
## ——首领表按图分支（world.boss_defs；dam 军火商/坝区指挥官 · space 两名）
func _spawn_static() -> void:
	for spot in _world.container_spots:
		_make_container(spot)
	# 首领保险柜（第四阶段）：不进 world.container_spots（容器点总数契约不变），
	# 由首领守着——要先打赢首领才能安心搜 6 s
	var bosses: Array = HDData.BOSSES
	if _world != null and _world.has_method("boss_defs"):
		bosses = _world.boss_defs()
	for bd in bosses:
		_make_container({"pos": bd["vault"], "zone": bd["zone"], "cls": "vault",
				"boss": str(bd["id"])})


## 换图重建（world.set_map 后由 main 调）：拆旧容器（外观 + 占位障碍）→ 按
## world.container_spots / 首领表重生成（分类 roll 走新图 zone_at 实时裁决）
func rebuild_map() -> void:
	if _world == null:
		return
	for c in _containers:
		(c["root"] as Node3D).queue_free()
		_world.obstacles.erase(c["ob"])
	_containers.clear()
	_spawn_static()
	_active_i = -1
	_ground_i = -1
	_progress = 0.0


func update(dt: float, player_pos: Vector3, interact_held: bool) -> void:
	_t += dt
	_update_search(dt, player_pos, interact_held)
	_update_lids(dt)
	_update_lamps()


## 取走全部背包内容并清空（撤离入库/死亡丢弃共用）
func drain() -> Array:
	var out: Array = backpack.duplicate()
	backpack.clear()
	return out


## 取走安全箱内容并清空（撤离/阵亡都入库）
func drain_secure() -> Array:
	var out: Array = secure.duplicate()
	secure.clear()
	return out


## 当前随身价值（背包 + 安全箱）
func bag_value() -> int:
	var sum := 0
	for it in backpack + secure:
		sum += int(float((it as Dictionary).get("value", 0)))
	return sum


## 背包弃件 / 安全箱取出丢地：from_secure 选列表，idx 越界忽略；落在 at 附近地面
func drop_item(from_secure: bool, idx: int, at: Vector3) -> Dictionary:
	var lst: Array = secure if from_secure else backpack
	if idx < 0 or idx >= lst.size():
		return {}
	var it: Dictionary = lst[idx]
	lst.remove_at(idx)
	_spawn_ground(it, at)
	return it


## 背包 ⇄ 安全箱：目标满则拒绝（false）
func move_secure(from_secure: bool, idx: int) -> bool:
	var src: Array = secure if from_secure else backpack
	var dst: Array = backpack if from_secure else secure
	var cap := HDData.BACKPACK_MAX if from_secure else secure_cap
	if idx < 0 or idx >= src.size() or dst.size() >= cap:
		return false
	dst.append(src[idx])
	src.remove_at(idx)
	return true


## 用掉背包里一件指定物资（按 use 键匹配，取第一件）；没有返回 false
func consume(kind: String) -> bool:
	for i in backpack.size():
		if str((backpack[i] as Dictionary).get("use", "")) == kind:
			backpack.remove_at(i)
			return true
	return false


## 背包里各物资件数 {kind: n}
func use_counts() -> Dictionary:
	var out := {}
	for k in HDData.USE_KEYS:
		out[k] = 0
	for it in backpack:
		var u := str((it as Dictionary).get("use", ""))
		if out.has(u):
			out[u] = int(out[u]) + 1
	return out


## 搜刮者搜走一个容器（第四阶段 AI 搜刮者）：开盖灭灯，返回 roll 出的那件；已搜返回 {}
func npc_take(i: int) -> Dictionary:
	if i < 0 or i >= _containers.size():
		return {}
	var c: Dictionary = _containers[i]
	if bool(c["searched"]):
		return {}
	c["searched"] = true
	c["open_t"] = 0.0001
	(c["lamp"] as MeshInstance3D).visible = false
	if _active_i == i:
		_active_i = -1
		_progress = 0.0
	var pos: Vector3 = c["pos"]
	return HDData.roll_container(String(c["cls"]), String(_world.zone_at(pos.x, pos.z)))


## 空投箱落地（局内事件）：动态容器，重开局时 reset_all 拆掉；返回容器下标
func add_airdrop(pos: Vector3) -> int:
	_make_container({"pos": pos, "zone": String(_world.zone_at(pos.x, pos.z)),
			"cls": "airdrop", "dynamic": true})
	return _containers.size() - 1


## 通用动态容器（阶段 B 锁房开锁后生成；同 add_airdrop 语义：reset_all 会拆走）
func add_container(pos: Vector3, cls: String) -> int:
	_make_container({"pos": pos, "zone": String(_world.zone_at(pos.x, pos.z)),
			"cls": cls, "dynamic": true})
	return _containers.size() - 1


## 按 uid 从背包取出一件（开锁消耗钥匙用；不在背包/安全箱返回 false）
func take_item(uid: String) -> bool:
	for i in backpack.size():
		if str((backpack[i] as Dictionary).get("uid", "")) == uid:
			backpack.remove_at(i)
			return true
	return false


## 背包里最便宜一件的下标（空 -1）
func cheapest_idx() -> int:
	var bi := -1
	var bv := INF
	for i in backpack.size():
		var v := float((backpack[i] as Dictionary).get("value", 0))
		if v < bv:
			bv = v
			bi = i
	return bi


## 重开行动：全部容器回未搜态、关盖、复燃指示灯、清空背包与提示
func reset_all() -> void:
	# 局内动态容器（空投箱）：拆掉外观与占位障碍
	for k in range(_containers.size() - 1, -1, -1):
		var dc: Dictionary = _containers[k]
		if not bool(dc.get("dynamic", false)):
			continue
		(dc["root"] as Node3D).queue_free()
		_world.obstacles.erase(dc["ob"])
		_containers.remove_at(k)
	for c in _containers:
		c["searched"] = false
		c["open_t"] = 0.0
		(c["lid_pivot"] as Node3D).rotation.x = 0.0
		(c["lamp"] as MeshInstance3D).visible = true
	backpack.clear()
	secure.clear()
	for g in _ground:
		(g["node"] as Node3D).queue_free()
	_ground.clear()
	_ground_i = -1
	_active_i = -1
	_progress = 0.0
	prompt.emit("", 0.0)


# ================= 生成 =================

func _make_container(spot: Dictionary) -> void:
	var pos: Vector3 = spot["pos"]
	# 分类按点位确定（同一张图每局一致，玩家能记住「哪里有保险箱」）
	var crng := RandomNumberGenerator.new()
	crng.seed = int(pos.x * 73.0) * 7919 + int(pos.z * 37.0)
	var zone0 := String(_world.zone_at(pos.x, pos.z))
	var cls := String(spot.get("cls", ""))
	if cls == "":
		cls = HDData.pick_weighted(HDData.CLASS_W.get(zone0, HDData.CLASS_W["mid"]), crng)
	var ti: int = CLASS_TYPE.get(cls, 2)
	if cls == "crate" and crng.randf() < 0.4:
		ti = 3   # 杂物箱一部分是行李袋
	var type: Dictionary = TYPES[ti]
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = randf() * TAU
	add_child(root)
	var size: Vector3 = type["size"] * (1.3 if cls == "vault" else 1.0)   # 首领柜大一号
	# —— 箱体：crate.glb 按类型缩放 + 整体染色；失败退化程序化色箱；保险箱单独建模 ——
	if cls == "safe" or cls == "vault":
		_make_safe_body(root, size)
	elif cls == "airdrop":
		_make_airdrop_body(root, size)
	elif _crate_scene != null:
		var body: Node3D = _crate_scene.instantiate()
		body.scale = Vector3(size.x / CRATE_DIM, size.y / CRATE_DIM, size.z / CRATE_DIM)
		root.add_child(body)
		_tint_all(body, type["color"])
	else:
		var bmi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = _type_mat(type)
		bmi.mesh = bm
		bmi.position = Vector3(0.0, size.y * 0.5, 0.0)
		root.add_child(bmi)
	# —— 后铰链盖子（开箱动画动件） ——
	var lid_pivot := Node3D.new()
	lid_pivot.position = Vector3(0.0, size.y, -size.z * 0.5)
	root.add_child(lid_pivot)
	var lid := MeshInstance3D.new()
	var lkey := "lid|%s|%s" % [str(type["id"]), str(size)]
	if not _share.has(lkey):
		var lm := BoxMesh.new()
		lm.size = Vector3(size.x * 0.96, 0.06, size.z * 0.96)
		lm.material = _type_mat(type)
		_share[lkey] = lm
	lid.mesh = _share[lkey]
	lid.position = Vector3(0.0, 0.03, size.z * 0.5)
	lid_pivot.add_child(lid)
	# —— 顶部琥珀色未搜指示灯（emission 小球，呼吸） ——
	var lamp := MeshInstance3D.new()
	if not _share.has("lamp_mesh"):
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 12
		sm.rings = 6
		_share["lamp_mesh"] = sm
	lamp.mesh = _share["lamp_mesh"]
	var lcol: Color = VAULT_LAMP if cls == "vault" else (AIRDROP_LAMP if cls == "airdrop" else AMBER)
	var lk := "lamp|%s|%d" % [lcol.to_html(), _containers.size() % 3]
	if not _lamp_sets.has(lk):
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.16, 0.12, 0.06)
		lmat.emission_enabled = true
		lmat.emission = lcol
		lmat.emission_energy_multiplier = LAMP_BASE
		_lamp_sets[lk] = {"mat": lmat, "phase": float(_containers.size() % 3) * TAU / 3.0}
	var lamp_mat: StandardMaterial3D = _lamp_sets[lk]["mat"]
	lamp.material_override = lamp_mat
	lamp.position = Vector3(0.0, size.y + 0.12, size.z * 0.2)
	root.add_child(lamp)
	# —— 占位障碍登记进 world.obstacles（旋转取保守 AABB） ——
	var yaw := root.rotation.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	var ob := {"cx": pos.x, "cz": pos.z,
		"hx": hx * cs + hz * sn, "hz": hx * sn + hz * cs,
		"top": size.y, "bot": 0.0}
	_world.obstacles.append(ob)
	_containers.append({"pos": pos, "zone": spot["zone"], "type": type, "cls": cls,
		"boss": String(spot.get("boss", "")), "dynamic": bool(spot.get("dynamic", false)), "ob": ob,
		"searched": false, "root": root, "lid_pivot": lid_pivot, "lamp": lamp,
		"lamp_mat": lamp_mat, "open_t": 0.0, "phase": randf() * TAU})


## 空投箱：橄榄绿军用箱 + 深色包角框 + 两道浅色捆扎带 + 侧面白色模板字块
func _make_airdrop_body(root: Node3D, size: Vector3) -> void:
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.36, 0.41, 0.26)
	olive.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.17, 0.14)
	dark.roughness = 0.7
	dark.metallic = 0.4
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.72, 0.68, 0.55)
	band.roughness = 0.9
	var stencil := StandardMaterial3D.new()
	stencil.albedo_color = Color(0.9, 0.9, 0.86)
	stencil.roughness = 0.9
	var parts := [
		[olive, Vector3.ZERO, size],
		# 包角框：上下四条长边
		[dark, Vector3(0, size.y * 0.5 - 0.04, size.z * 0.5 - 0.04), Vector3(size.x + 0.02, 0.09, 0.09)],
		[dark, Vector3(0, size.y * 0.5 - 0.04, -size.z * 0.5 + 0.04), Vector3(size.x + 0.02, 0.09, 0.09)],
		[dark, Vector3(0, -size.y * 0.5 + 0.04, size.z * 0.5 - 0.04), Vector3(size.x + 0.02, 0.09, 0.09)],
		[dark, Vector3(0, -size.y * 0.5 + 0.04, -size.z * 0.5 + 0.04), Vector3(size.x + 0.02, 0.09, 0.09)],
		# 捆扎带 ×2（绕箱一圈）
		[band, Vector3(-size.x * 0.28, 0, 0), Vector3(0.08, size.y + 0.02, size.z + 0.02)],
		[band, Vector3(size.x * 0.28, 0, 0), Vector3(0.08, size.y + 0.02, size.z + 0.02)],
		# 侧面模板字块（两面）
		[stencil, Vector3(0, 0.05, size.z * 0.5 + 0.006), Vector3(size.x * 0.32, size.y * 0.22, 0.01)],
		[stencil, Vector3(0, 0.05, -size.z * 0.5 - 0.006), Vector3(size.x * 0.32, size.y * 0.22, 0.01)],
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[2]
		bm.material = pt[0]
		mi.mesh = bm
		mi.position = Vector3(0.0, size.y * 0.5, 0.0) + pt[1]
		root.add_child(mi)


## 保险箱：深钢箱体 + 前面板凹框 + 密码转盘 + 把手（程序化，不用 crate.glb）
func _make_safe_body(root: Node3D, size: Vector3) -> void:
	if not _share.has("safe_steel"):
		var steel0 := StandardMaterial3D.new()
		steel0.albedo_color = Color(0.2, 0.21, 0.23)
		steel0.metallic = 0.7
		steel0.roughness = 0.45
		_share["safe_steel"] = steel0
		var trim0 := StandardMaterial3D.new()
		trim0.albedo_color = Color(0.55, 0.5, 0.36)
		trim0.metallic = 0.9
		trim0.roughness = 0.3
		_share["safe_trim"] = trim0
	var steel: StandardMaterial3D = _share["safe_steel"]
	var trim: StandardMaterial3D = _share["safe_trim"]
	var parts := [
		["body", steel, size, Vector3(0.0, size.y * 0.5, 0.0), false],
		["door", steel, Vector3(size.x * 0.82, size.y * 0.78, 0.02),
			Vector3(0.0, size.y * 0.5, size.z * 0.5 + 0.01), false],
		["dial", trim, Vector3(0.07, 0.04, 0.0), Vector3(-0.08, size.y * 0.55, size.z * 0.5 + 0.04), true],
		["handle", trim, Vector3(0.04, 0.16, 0.04), Vector3(0.18, size.y * 0.5, size.z * 0.5 + 0.04), false],
	]
	for pt in parts:
		var key := "safe|%s|%s" % [str(pt[0]), str(pt[2])]
		if not _share.has(key):
			var mesh: PrimitiveMesh
			if bool(pt[4]):
				var cm := CylinderMesh.new()
				cm.top_radius = (pt[2] as Vector3).x
				cm.bottom_radius = (pt[2] as Vector3).x
				cm.height = (pt[2] as Vector3).y
				mesh = cm
			else:
				var bm := BoxMesh.new()
				bm.size = pt[2]
				mesh = bm
			mesh.material = pt[1]
			_share[key] = mesh
		var mi := MeshInstance3D.new()
		mi.mesh = _share[key]
		mi.position = pt[3]
		if bool(pt[4]):
			mi.rotation.x = PI * 0.5
		root.add_child(mi)


## 容器整体染色：克隆所有表面材质乘类型色（Wood 不在 TINTABLE，全染才分得清）
func _tint_all(body: Node3D, color: Color) -> void:
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D:
				var key := "tint|%d|%s" % [m.get_instance_id(), color.to_html()]
				if not _share.has(key):
					var t: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
					t.albedo_color = (m as StandardMaterial3D).albedo_color * color
					_share[key] = t
				mi.set_surface_override_material(si, _share[key])


func _type_mat(type: Dictionary) -> StandardMaterial3D:
	var id: String = type["id"]
	if not _body_mat_cache.has(id):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = type["color"]
		mat.roughness = 0.9
		_body_mat_cache[id] = mat
	return _body_mat_cache[id]


# ================= 搜索状态机 =================

func _update_search(dt: float, player_pos: Vector3, interact_held: bool) -> void:
	# 地面物品优先（弃件/落选件就在脚下，比容器近才有意义）
	var gi := -1
	var gd2 := GROUND_R * GROUND_R
	for i in _ground.size():
		var gp: Vector3 = _ground[i]["pos"]
		var gdx := player_pos.x - gp.x
		var gdz := player_pos.z - gp.z
		var g2 := gdx * gdx + gdz * gdz
		if g2 < gd2 and absf(player_pos.y - gp.y) < 2.0:
			gd2 = g2
			gi = i
	if gi >= 0:
		if gi != _ground_i:
			_ground_i = gi
			_active_i = -1
			_progress = 0.0
		var it: Dictionary = _ground[gi]["item"]
		var txt := "按住 F 拾取 %s（₵%d）" % [String(it.get("name", "")), int(float(it.get("value", 0)))]
		if backpack.size() >= HDData.BACKPACK_MAX:
			var ci := cheapest_idx()
			txt = "背包已满 · 按住 F 用 %s 换下 %s" % [String(it.get("name", "")),
					String((backpack[ci] as Dictionary).get("name", ""))]
		if interact_held:
			_progress = minf(_progress + dt / GROUND_TIME, 1.0)
			if _progress >= 1.0:
				_pick_ground(gi)
				return
		else:
			_progress = 0.0
		prompt.emit(txt, _progress)
		return
	if _ground_i >= 0:
		_ground_i = -1
		_progress = 0.0
	# 最近未搜容器（XZ 平面 < SEARCH_RADIUS）
	var best_i := -1
	var best_d2 := SEARCH_RADIUS * SEARCH_RADIUS
	for i in _containers.size():
		var c: Dictionary = _containers[i]
		if bool(c["searched"]):
			continue
		var pos: Vector3 = c["pos"]
		var dx := player_pos.x - pos.x
		var dz := player_pos.z - pos.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_i = i
	if best_i != _active_i:
		_active_i = best_i
		_progress = 0.0
	if best_i < 0:
		prompt.emit("", 0.0)
		return
	var c: Dictionary = _containers[best_i]
	var cc: Dictionary = HDData.CONTAINER_CLASS.get(String(c.get("cls", "crate")), HDData.CONTAINER_CLASS["crate"])
	var stime := float(cc.get("search", SEARCH_TIME))
	if interact_held:
		_progress = minf(_progress + dt / stime, 1.0)
		if _progress >= 1.0:
			_open(best_i, player_pos)
			return
	elif _progress > 0.0:
		_progress = maxf(_progress - dt * PROGRESS_DROP, 0.0)   # 松手回退不即时清零
	prompt.emit("按住 F 搜索 %s" % String(cc["name"]), _progress)


## 开箱：灯灭盖开 → 按分区 roll 一件；背包未满入包 picked；满包则与最便宜
## 一件比价——新件更值钱就交换（旧件落地），否则新件落在箱前地上（可再捡）
func _open(i: int, player_pos: Vector3 = Vector3.INF) -> void:
	var c: Dictionary = _containers[i]
	c["searched"] = true
	c["open_t"] = 0.0001   # 开盖动画启动（_update_lids 接管）
	(c["lamp"] as MeshInstance3D).visible = false
	_active_i = -1
	_progress = 0.0
	var pos: Vector3 = c["pos"]
	var cls := String(c.get("cls", "crate"))
	var zone := String(_world.zone_at(pos.x, pos.z))
	searched.emit(cls, zone)   # 合同推进（玩家路径专属——搜刮者 npc_take 不走 _open）
	var item := HDData.roll_container(cls, zone)
	var drop_at: Vector3 = pos if player_pos == Vector3.INF else player_pos
	# 额外物资（武器箱/医疗箱多出）：有空位进包，没空位落在脚下
	var bonus := HDData.roll_bonus(String(c.get("cls", "crate")))
	if not bonus.is_empty():
		if backpack.size() < HDData.BACKPACK_MAX - 1:
			backpack.append(bonus)
			picked.emit(bonus)
		else:
			_spawn_ground(bonus, drop_at)
			notice.emit("%s 留在脚下（背包快满了）" % String(bonus.get("name", "")), NOTICE_COL)
	if backpack.size() < HDData.BACKPACK_MAX:
		backpack.append(item)
		picked.emit(item)
		return
	var ci := cheapest_idx()
	var old: Dictionary = backpack[ci]
	if float(item.get("value", 0)) > float(old.get("value", 0)):
		backpack[ci] = item
		_spawn_ground(old, drop_at)
		picked.emit(item)
		notice.emit("背包已满 · 换下 %s（₵%d，已丢在脚下）" % [String(old.get("name", "")),
				int(float(old.get("value", 0)))], NOTICE_COL)
	else:
		_spawn_ground(item, drop_at)
		notice.emit("背包已满 · %s（₵%d）不如包里的值钱，留在地上" % [String(item.get("name", "")),
				int(float(item.get("value", 0)))], NOTICE_COL)


## 拾取地面物品：背包有空直接入包；满包与最便宜一件交换（旧件落在原处）
func _pick_ground(gi: int) -> void:
	var g: Dictionary = _ground[gi]
	var it: Dictionary = g["item"]
	var gpos: Vector3 = g["pos"]
	(g["node"] as Node3D).queue_free()
	_ground.remove_at(gi)
	_ground_i = -1
	_progress = 0.0
	if backpack.size() < HDData.BACKPACK_MAX:
		backpack.append(it)
	else:
		var ci := cheapest_idx()
		var old: Dictionary = backpack[ci]
		backpack[ci] = it
		_spawn_ground(old, gpos)
		notice.emit("换下 %s（₵%d，留在地上）" % [String(old.get("name", "")),
				int(float(old.get("value", 0)))], NOTICE_COL)
	picked.emit(it)


## 地面物品外观：帆布小包 + 顶部品质色发光条（远处靠色条认品质）
func _spawn_ground(it: Dictionary, at: Vector3) -> void:
	var p := at
	if _ground.size() > 0:   # 同点多件错开一点，免得叠成一团
		var a := float(_ground.size()) * 2.4
		p += Vector3(cos(a), 0.0, sin(a)) * 0.35
	p.y = _world.ground_height(p.x, p.z, at.y) if _world != null else at.y
	var root := Node3D.new()
	root.position = p
	root.rotation.y = randf() * TAU
	add_child(root)
	var bag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.14, 0.24)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.36, 0.33, 0.24)
	bmat.roughness = 0.95
	bm.material = bmat
	bag.mesh = bm
	bag.position = Vector3(0.0, 0.07, 0.0)
	root.add_child(bag)
	var rid := clampi(int(it.get("rarity", 0)), 0, 6)
	var rcol: Color = HDData.RARITY[rid]["color"]
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.33, 0.02, 0.05)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = rcol * 0.4
	smat.emission_enabled = true
	smat.emission = rcol
	smat.emission_energy_multiplier = 1.6
	sm.material = smat
	strip.mesh = sm
	strip.position = Vector3(0.0, 0.15, 0.0)
	root.add_child(strip)
	_ground.append({"item": it, "pos": p, "node": root})


## 地面物品数（测试/HUD 用）
func ground_count() -> int:
	return _ground.size()


func _update_lids(dt: float) -> void:
	for c in _containers:
		var open_t: float = c["open_t"]
		if open_t <= 0.0 or open_t >= 1.0:
			continue
		open_t = minf(open_t + dt / LID_TIME, 1.0)
		c["open_t"] = open_t
		var k := 1.0 - pow(1.0 - open_t, 3.0)   # easeOutCubic
		(c["lid_pivot"] as Node3D).rotation.x = LID_ANGLE * k


## 未搜指示灯琥珀呼吸（相位错开），已搜的 update 前已 visible=false
func _update_lamps() -> void:
	for lk in _lamp_sets:
		var ls: Dictionary = _lamp_sets[lk]
		(ls["mat"] as StandardMaterial3D).emission_energy_multiplier = LAMP_BASE \
				+ LAMP_AMP * sin(_t * 2.6 + float(ls["phase"]))
