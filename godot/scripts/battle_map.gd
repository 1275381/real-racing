class_name BattleMap
extends Node3D
## 大战场独立地图：荒漠战场 500×400m（半场 ±250/±200）。
## 鸭子类型兼容 onfoot 依赖面：obstacles_box + query()（返回 idx/height）。
## 两端沙袋基地（我方蓝旗 z=+165 / 敌方红旗 z=-165），中场掩体，周界石堆封锁。

const ARENA_X := 250.0          # 半场宽（东西）
const ARENA_Z := 200.0          # 半场深（南北）
const ALLY_SPAWN := Vector3(0, 0, 165)
const ENEMY_SPAWN := Vector3(0, 0, -165)

var obstacles_box: Array = []   # OBB {c: Vector2, hx, hz, rot}（onfoot 推出 / 子弹墙体共用）


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912   # 固定种子：掩体布局确定性（探针/截图可复现）
	_build_ground()
	_build_base(ALLY_SPAWN.z, Color(0.35, 0.5, 0.75), "我 方 基 地")
	_build_base(ENEMY_SPAWN.z, Color(0.75, 0.3, 0.25), "敌 军 阵 地")
	_build_cover(rng)
	_build_perimeter()


## 解析地形高度（与视觉网格同函数，O(1)）
func terrain_height(x: float, z: float) -> float:
	return 0.6 * sin(x * 0.021) * cos(z * 0.017)


## onfoot 地面查询（鸭子类型：同 FreeroamMap.query 契约的最小子集；
## hint 初始可为 null，与 FreeroamMap 一致保持无类型）
func query(x: float, z: float, _hint = -1, _vy = -1e9) -> Dictionary:
	return {"idx": 0, "height": terrain_height(x, z)}


# ================= 地面 =================

func _build_ground() -> void:
	# 10m 网格位移地形（与 terrain_height 同函数），带法线
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(ARENA_X * 2.0 / 10.0)
	var nz := int(ARENA_Z * 2.0 / 10.0)
	for gz in nz + 1:
		for gx in nx + 1:
			var x := -ARENA_X + gx * 10.0
			var z := -ARENA_Z + gz * 10.0
			st.set_normal(_terrain_normal(x, z))
			st.add_vertex(Vector3(x, terrain_height(x, z), z))
	for gz in nz:
		for gx in nx:
			var r0 := gz * (nx + 1) + gx
			var r1 := r0 + nx + 1
			st.add_index(r0)
			st.add_index(r1)
			st.add_index(r0 + 1)
			st.add_index(r0 + 1)
			st.add_index(r1)
			st.add_index(r1 + 1)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.53, 0.4)   # 荒漠尘土
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx := (terrain_height(x + e, z) - terrain_height(x - e, z)) / (2.0 * e)
	var hz := (terrain_height(x, z + e) - terrain_height(x, z - e)) / (2.0 * e)
	return Vector3(-hx, 1.0, -hz).normalized()


# ================= 结构物 =================

## 程序化盒体：视觉 + OBB 碰撞登记（pos.y 为离地基准，叠层/车舱用）
func _add_box(size: Vector3, pos: Vector3, rot_y: float, color: Color,
		rough := 0.95) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(pos.x,
			terrain_height(pos.x, pos.z) + pos.y + size.y * 0.5, pos.z)
	mi.rotation.y = rot_y
	add_child(mi)
	obstacles_box.append({
		"c": Vector2(pos.x, pos.z), "hx": size.x * 0.5, "hz": size.z * 0.5,
		"rot": rot_y, "top": terrain_height(pos.x, pos.z) + pos.y + size.y,
	})


## 两端沙袋基地：弧形沙袋墙（留门口）+ 旗杆旗名
func _build_base(z_center: float, flag_color: Color, title: String) -> void:
	var sand := Color(0.72, 0.66, 0.5)
	var dir_sign := signf(z_center)   # 弧线朝向场心
	for k in 11:
		if k == 5:
			continue   # 正中留门口
		var ang := deg_to_rad(-70.0 + k * 14.0)
		var bx := sin(ang) * 16.0
		var bz := z_center - cos(ang) * 16.0 * dir_sign * -1.0
		# 沙袋错缝双层
		_add_box(Vector3(2.6, 0.85, 0.7), Vector3(bx, 0, bz),
				-ang * dir_sign, sand)
		_add_box(Vector3(2.6, 0.85, 0.7),
				Vector3(bx + 0.35, 0.85, bz + 0.2 * dir_sign),
				-ang * dir_sign + 0.06, sand)
	# 旗杆 + 旗名
	var pole_h := 7.0
	var px := 0.0
	var pz := z_center - dir_sign * 6.0
	var pole := BoxMesh.new()
	pole.size = Vector3(0.18, pole_h, 0.18)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.55, 0.55, 0.58)
	pole.material = pmat
	var pole_mi := MeshInstance3D.new()
	pole_mi.mesh = pole
	pole_mi.position = Vector3(px, terrain_height(px, pz) + pole_h * 0.5, pz)
	add_child(pole_mi)
	var flag := Label3D.new()
	flag.text = title
	flag.font_size = 220
	flag.modulate = flag_color
	flag.outline_size = 40
	flag.position = Vector3(px, terrain_height(px, pz) + pole_h + 0.9, pz)
	add_child(flag)


## 中场掩体：水泥墙 / 木箱堆 / 断墙 / 锈蚀车壳（固定种子散布，避开两端基地 60m）
func _build_cover(rng: RandomNumberGenerator) -> void:
	var concrete := Color(0.58, 0.58, 0.56)
	var wood := Color(0.52, 0.38, 0.22)
	var rust := Color(0.36, 0.24, 0.16)
	var placed: Array[Vector2] = []
	for k in 26:
		var pos := Vector2.ZERO
		var ok := false
		for try_i in 24:
			pos = Vector2(rng.randf_range(-190.0, 190.0),
					rng.randf_range(-110.0, 110.0))
			ok = true
			for p in placed:
				if pos.distance_to(p) < 16.0:
					ok = false
					break
			if ok:
				break
		if not ok:
			continue
		placed.append(pos)
		var rot := rng.randf_range(0.0, TAU)
		match rng.randi_range(0, 3):
			0:   # 水泥墙（两面挡弹）
				_add_box(Vector3(4.2, 1.25, 0.5),
						Vector3(pos.x, 0, pos.y), rot, concrete)
			1:   # 木箱堆（1 大 2 小）
				_add_box(Vector3(1.7, 1.7, 1.7),
						Vector3(pos.x, 0, pos.y), rot, wood)
				_add_box(Vector3(1.2, 1.2, 1.2),
						Vector3(pos.x + 1.6, 0, pos.y + 0.5),
						rot + 0.5, wood)
				_add_box(Vector3(1.1, 1.1, 1.1),
						Vector3(pos.x - 1.3, 0, pos.y - 0.6),
						rot - 0.4, wood)
			2:   # 断墙（高墙带整体量感）
				_add_box(Vector3(0.45, 2.6, 5.0),
						Vector3(pos.x, 0, pos.y), rot,
						Color(0.5, 0.47, 0.42))
			3:   # 锈蚀车壳（车身 + 舱盖）
				_add_box(Vector3(2.0, 0.9, 4.4),
						Vector3(pos.x, 0, pos.y), rot, rust)
				_add_box(Vector3(1.7, 0.75, 2.0),
						Vector3(pos.x, 0.9, pos.y - 0.3), rot,
						Color(0.3, 0.2, 0.14))
				# 车壳碰撞抬满全高（舱盖不可穿越）
				obstacles_box[-1]["hx"] = 1.0
				obstacles_box[-2]["hz"] = 2.2


## 周界石堆圈：视觉 + OBB 阻挡出界
func _build_perimeter() -> void:
	var rock := Color(0.44, 0.4, 0.35)
	var step := 14.0
	# 东西两长边
	var cx := -ARENA_X
	while cx <= ARENA_X:
		_add_box(Vector3(step * 0.62, 2.6, 2.8),
				Vector3(cx, 0, -ARENA_Z), 0.15, rock)
		_add_box(Vector3(step * 0.62, 2.6, 2.8),
				Vector3(cx, 0, ARENA_Z), -0.1, rock)
		cx += step
	# 南北两短边
	var cz := -ARENA_Z + step
	while cz < ARENA_Z - step * 0.5:
		_add_box(Vector3(2.8, 2.6, step * 0.62),
				Vector3(-ARENA_X, 0, cz), 0.08, rock)
		_add_box(Vector3(2.8, 2.6, step * 0.62),
				Vector3(ARENA_X, 0, cz), -0.12, rock)
		cz += step
