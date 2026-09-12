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
	_build_village(rng)
	_build_trenches(rng)
	_build_cover(rng)
	_build_craters(rng)
	_build_dead_trees(rng)
	_build_perimeter()
	_build_watchtowers()
	_build_depots(rng)


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


## 纯视觉盒体（不参与碰撞/子弹）
func _add_vis_box(size: Vector3, pos: Vector3, rot_y: float,
		color: Color, rough := 0.95) -> void:
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


## 中场废墟村落：残墙断壁的土房框 + 瓦砾，战斗焦点区
func _build_village(rng: RandomNumberGenerator) -> void:
	var wall_a := Color(0.54, 0.49, 0.41)
	var wall_b := Color(0.34, 0.3, 0.26)
	var rubble := Color(0.42, 0.39, 0.34)
	for h in 7:
		var cx := -70.0 + (h % 4) * 44.0 + rng.randf_range(-9.0, 9.0)
		var cz := -34.0 + (h / 4) * 62.0 + rng.randf_range(-9.0, 9.0)
		var rot := rng.randf_range(-0.4, 0.4)
		var col := wall_a if rng.randf() < 0.6 else wall_b
		var w := rng.randf_range(5.0, 7.5)
		var d := rng.randf_range(4.0, 6.0)
		# 房框：前后墙留门洞（各分两段），侧墙完整但高低不齐
		var gap := w * 0.22
		var seg := (w - gap) * 0.5
		var fz := cz - d * 0.5
		var bz := cz + d * 0.5
		_add_box(Vector3(seg, rng.randf_range(1.7, 2.7), 0.45),
				Vector3(cx - (gap * 0.5 + seg * 0.5), 0, fz), rot, col)
		_add_box(Vector3(seg, rng.randf_range(1.4, 2.4), 0.45),
				Vector3(cx + (gap * 0.5 + seg * 0.5), 0, fz), rot, col)
		_add_box(Vector3(w, rng.randf_range(1.9, 2.9), 0.45),
				Vector3(cx, 0, bz), rot, col)
		_add_box(Vector3(0.45, rng.randf_range(1.5, 2.5), d),
				Vector3(cx - w * 0.5, 0, cz), rot, col)
		if rng.randf() < 0.6:
			_add_box(Vector3(0.4, rng.randf_range(1.0, 1.8), d * 0.6),
					Vector3(cx + w * 0.5, 0, cz), rot, col)
		# 瓦砾堆
		for r in 3:
			_add_vis_box(Vector3(rng.randf_range(0.8, 1.6), 0.35,
					rng.randf_range(0.8, 1.6)),
					Vector3(cx + rng.randf_range(-w, w), 0,
					cz + rng.randf_range(-d, d)),
					rng.randf_range(0.0, TAU), rubble)


## 战壕沙袋线：中场景深上的长条双层沙袋 + 弹药箱
func _build_trenches(rng: RandomNumberGenerator) -> void:
	var sand := Color(0.72, 0.66, 0.5)
	var ammo_c := Color(0.3, 0.42, 0.3)
	for t in 4:
		var cx := rng.randf_range(-140.0, 140.0)
		var cz := rng.randf_range(-70.0, 70.0)
		var rot := rng.randf_range(-0.3, 0.3)
		var length := rng.randf_range(11.0, 20.0)
		var n := int(length / 2.8)
		for k in n:
			var ox := (float(k) - float(n - 1) * 0.5) * 2.8
			var off := Vector2(sin(rot), cos(rot)) * ox
			_add_box(Vector3(2.6, 0.85, 0.8),
					Vector3(cx + off.x, 0, cz + off.y), rot, sand)
			_add_box(Vector3(2.6, 0.85, 0.8),
					Vector3(cx + off.x + 0.3, 0.85, cz + off.y + 0.15),
					rot + 0.05, sand)
		# 壕尾弹药箱
		_add_box(Vector3(1.1, 0.7, 0.7),
				Vector3(cx - sin(rot) * (length * 0.5 + 1.4), 0,
				cz - cos(rot) * (length * 0.5 + 1.4)), rot, ammo_c)


## 炸弹坑：深色扁圆盘 + 土脊（纯视觉，遍地都是）
func _build_craters(rng: RandomNumberGenerator) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.2, 0.16)
	mat.roughness = 1.0
	mesh.material = mat
	for k in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var x := rng.randf_range(-200.0, 200.0)
		var z := rng.randf_range(-160.0, 160.0)
		var r := rng.randf_range(1.6, 4.2)
		mi.scale = Vector3(r, 0.12, r)
		mi.position = Vector3(x, terrain_height(x, z) + 0.02, z)
		add_child(mi)
		# 环形土脊（四段浅色土块）
		var ridge := Color(0.55, 0.48, 0.38)
		for j in 4:
			var ang := float(j) * TAU / 4.0 + 0.4
			_add_vis_box(Vector3(1.2, 0.3, 0.5),
					Vector3(x + cos(ang) * r * 1.05, 0,
					z + sin(ang) * r * 1.05), -ang + PI * 0.5, ridge)


## 焦黑枯树：细干 + 两根斜枝（干参与碰撞，枝纯视觉）
func _build_dead_trees(rng: RandomNumberGenerator) -> void:
	var bark := Color(0.22, 0.18, 0.15)
	for t in 10:
		var x := rng.randf_range(-220.0, 220.0)
		var z := rng.randf_range(-170.0, 170.0)
		if absf(z) > 150.0 and absf(x) < 30.0:
			continue   # 别挡基地门口
		var h := rng.randf_range(3.2, 5.2)
		_add_box(Vector3(0.34, h, 0.34), Vector3(x, 0, z),
				rng.randf_range(0.0, TAU), bark)
		var rot := rng.randf_range(0.0, TAU)
		_add_vis_box(Vector3(0.18, 1.8, 0.18),
				Vector3(x, h * 0.62, z), rot, bark)
		_add_vis_box(Vector3(0.14, 1.3, 0.14),
				Vector3(x, h * 0.8, z), rot + 2.2, bark)


## 瞭望塔：两端基地各一座（四腿 + 顶台 + 顶棚）
func _build_watchtowers() -> void:
	for side in 2:
		var z := ALLY_SPAWN.z - 18.0 if side == 0 else ENEMY_SPAWN.z + 18.0
		var x := 26.0 if side == 0 else -26.0
		var leg_h := 5.2
		var leg_c := Color(0.35, 0.3, 0.24)
		for lx in [-1.1, 1.1]:
			for lz in [-1.1, 1.1]:
				_add_box(Vector3(0.3, leg_h, 0.3),
						Vector3(x + lx, 0, z + lz), 0.0, leg_c)
		_add_box(Vector3(3.0, 0.28, 3.0),
				Vector3(x, leg_h, z), 0.0, Color(0.42, 0.36, 0.28))
		_add_box(Vector3(3.4, 0.2, 3.4),
				Vector3(x, leg_h + 1.5, z), 0.0, Color(0.36, 0.31, 0.25))
		for lx in [-1.55, 1.55]:
			_add_box(Vector3(0.16, 1.5, 3.4),
					Vector3(x + lx, leg_h + 0.75, z), 0.0, leg_c)


## 基地旁补给堆：弹药箱垛 + 油桶
func _build_depots(rng: RandomNumberGenerator) -> void:
	var crate := Color(0.34, 0.44, 0.32)
	var barrel := Color(0.45, 0.38, 0.2)
	for side in 2:
		var z := ALLY_SPAWN.z - 10.0 if side == 0 else ENEMY_SPAWN.z + 10.0
		var x := -24.0 if side == 0 else 24.0
		for k in 4:
			var ox := float(k % 2) * 1.2
			var oy := float(k / 2) * 0.72
			_add_box(Vector3(1.1, 0.68, 0.75),
					Vector3(x + ox, oy, z), 0.12, crate)
		for k in 3:
			_add_box(Vector3(0.72, 0.95, 0.72),
					Vector3(x + 3.2 + float(k % 2) * 0.85, 0,
					z + float(k / 2) * 0.9 + rng.randf_range(-0.1, 0.1)),
					rng.randf_range(0.0, TAU), barrel)


## 中场掩体：水泥墙 / 木箱堆 / 断墙 / 锈蚀车壳（固定种子散布，避开两端基地 60m）
func _build_cover(rng: RandomNumberGenerator) -> void:
	var concrete := Color(0.58, 0.58, 0.56)
	var wood := Color(0.52, 0.38, 0.22)
	var rust := Color(0.36, 0.24, 0.16)
	var placed: Array[Vector2] = []
	for k in 38:
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
