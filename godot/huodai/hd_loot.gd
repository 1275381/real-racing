class_name HDLoot
extends Node3D
## 烽火地带 —— 战利品（容器生成 / 搜索状态机 / 背包），移植自网页版 js/fps/loot.js：
## 每个容器点生成一个箱体（crate.glb 或程序化箱体）+ 顶部琥珀色未搜指示灯
## （呼吸辉光，15-20m 外靠光点找箱子）；2.2m 内最近未搜容器出「按住 F 搜索」
## 提示，按住 1.8s 开箱 → HDData.roll_loot(world.zone_at(...)) 按分区 roll 品质，
## 背包(12 格)未满入包 emit picked，满则 emit full_warn；已搜容器灯灭盖开。
## 驱动链与网页版一致：本模块不监听键盘，interact_held 由上层每帧喂入。

signal prompt(text: String, progress: float)   # 每帧发（无目标发 ("",0)）
signal picked(item: Dictionary)
signal full_warn()

const SEARCH_TIME := 1.8         # 按住 F 开箱所需秒数
const SEARCH_RADIUS := 2.2       # 进入提示的最近距离（XZ 平面）
const PROGRESS_DROP := 0.9       # 松手后进度每秒回退量（不即时清零）
const LID_TIME := 0.5            # 开盖动画时长
const LID_ANGLE := -1.9          # 盖子后翻角度（rad）
const AMBER := Color(1.0, 0.66, 0.3)   # 未搜指示灯琥珀色
const LAMP_BASE := 1.3           # 指示灯呼吸基准亮度
const LAMP_AMP := 0.6            # 呼吸幅度

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
]
## crate.glb 实测 1.02 见方（原点在底面中心），按类型缩放到 size
const CRATE_PATH := "res://assets/battle/props/crate.glb"
const CRATE_DIM := 1.02

var backpack: Array = []         # {uid,name,rarity,value,icon}

var _containers: Array = []      # {pos,zone,type,searched,root,lid_pivot,lamp,lamp_mat,open_t,phase}
var _active_i := -1              # 当前提示容器下标（-1 无）
var _progress := 0.0
var _t := 0.0
var _world                       # HDWorld（zone_at / obstacles 用）
var _crate_scene: PackedScene
var _body_mat_cache := {}        # 类型 id -> StandardMaterial3D（程序化箱体/盖子共用）


## 在 world.container_spots 每点生成容器（外观 + 指示灯 + 占位障碍登记）
func build(world) -> void:
	_world = world
	_crate_scene = load(CRATE_PATH) if ResourceLoader.exists(CRATE_PATH) else null
	if _crate_scene == null:
		push_warning("[烽火地带] 容器模型加载失败：%s（暂用程序化箱体）" % CRATE_PATH)
	for spot in world.container_spots:
		_make_container(spot)


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


## 重开行动：全部容器回未搜态、关盖、复燃指示灯、清空背包与提示
func reset_all() -> void:
	for c in _containers:
		c["searched"] = false
		c["open_t"] = 0.0
		(c["lid_pivot"] as Node3D).rotation.x = 0.0
		(c["lamp"] as MeshInstance3D).visible = true
	backpack.clear()
	_active_i = -1
	_progress = 0.0
	prompt.emit("", 0.0)


# ================= 生成 =================

func _make_container(spot: Dictionary) -> void:
	var type: Dictionary = TYPES[randi() % TYPES.size()]
	var pos: Vector3 = spot["pos"]
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = randf() * TAU
	add_child(root)
	var size: Vector3 = type["size"]
	# —— 箱体：crate.glb 按类型缩放 + 整体染色；失败退化程序化色箱 ——
	if _crate_scene != null:
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
	var lm := BoxMesh.new()
	lm.size = Vector3(size.x * 0.96, 0.06, size.z * 0.96)
	lm.material = _type_mat(type)
	lid.mesh = lm
	lid.position = Vector3(0.0, 0.03, size.z * 0.5)
	lid_pivot.add_child(lid)
	# —— 顶部琥珀色未搜指示灯（emission 小球，呼吸） ——
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	lamp.mesh = sm
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.16, 0.12, 0.06)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = AMBER
	lamp_mat.emission_energy_multiplier = LAMP_BASE
	sm.material = lamp_mat
	lamp.position = Vector3(0.0, size.y + 0.12, size.z * 0.2)
	root.add_child(lamp)
	# —— 占位障碍登记进 world.obstacles（旋转取保守 AABB） ——
	var yaw := root.rotation.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	_world.obstacles.append({"cx": pos.x, "cz": pos.z,
		"hx": hx * cs + hz * sn, "hz": hx * sn + hz * cs,
		"top": size.y, "bot": 0.0})
	_containers.append({"pos": pos, "zone": spot["zone"], "type": type,
		"searched": false, "root": root, "lid_pivot": lid_pivot, "lamp": lamp,
		"lamp_mat": lamp_mat, "open_t": 0.0, "phase": randf() * TAU})


## 容器整体染色：克隆所有表面材质乘类型色（Wood 不在 TINTABLE，全染才分得清）
func _tint_all(body: Node3D, color: Color) -> void:
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D:
				var t: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				t.albedo_color = (m as StandardMaterial3D).albedo_color * color
				mi.set_surface_override_material(si, t)


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
	var type: Dictionary = c["type"]
	if interact_held:
		_progress = minf(_progress + dt / SEARCH_TIME, 1.0)
		if _progress >= 1.0:
			_open(best_i)
			return
	elif _progress > 0.0:
		_progress = maxf(_progress - dt * PROGRESS_DROP, 0.0)   # 松手回退不即时清零
	prompt.emit("按住 F 搜索 %s" % String(type["name"]), _progress)


## 开箱：灯灭盖开 → 按分区 roll 一件；背包未满入包 picked，满则 full_warn
func _open(i: int) -> void:
	var c: Dictionary = _containers[i]
	c["searched"] = true
	c["open_t"] = 0.0001   # 开盖动画启动（_update_lids 接管）
	(c["lamp"] as MeshInstance3D).visible = false
	_active_i = -1
	_progress = 0.0
	var pos: Vector3 = c["pos"]
	var item := HDData.roll_loot(String(_world.zone_at(pos.x, pos.z)))
	if backpack.size() < HDData.BACKPACK_MAX:
		backpack.append(item)
		picked.emit(item)
	else:
		full_warn.emit()


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
	for c in _containers:
		if bool(c["searched"]):
			continue
		var mat: StandardMaterial3D = c["lamp_mat"]
		mat.emission_energy_multiplier = LAMP_BASE \
				+ LAMP_AMP * sin(_t * 2.6 + float(c["phase"]))
