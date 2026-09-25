class_name BattleMap
extends Node3D
## 大战场地图（攻防推进，参考三角洲「全面战场」）：荒漠 500×400m（半场 ±250/±200）。
## 进攻方从南（+Z）向北推进，依次夺取 3 个区域，每区 A/B 两个据点；
## 防守方总部在最北。鸭子类型兼容 onfoot 依赖面：query() / obstacles_near()。

const ARENA_X := 250.0          # 半场宽（东西）
const ARENA_Z := 200.0          # 半场深（南北）
const ATK_HQ := Vector3(0, 0, 180)    # 进攻方总部（初始出生）
const DEF_HQ := Vector3(0, 0, -184)   # 防守方总部
const POINT_R := 12.0           # 据点占领半径

## 三个区域：名称 + A/B 据点坐标（XZ）。顺序即进攻顺序
const SECTORS := [
	{"name": "村落", "pts": [Vector2(-95, 72), Vector2(88, 58)]},
	{"name": "油库", "pts": [Vector2(-82, -26), Vector2(96, -40)]},
	{"name": "指挥所", "pts": [Vector2(-46, -126), Vector2(74, -134)]},
]

var obstacles_box: Array = []   # OBB {c: Vector2, hx, hz, rot, top}（onfoot 推出 / 子弹墙体共用）
var _flags: Array = []          # [sector][point] -> StandardMaterial3D（旗面，按归属改色）
var _rings: Array = []          # [sector][point] -> StandardMaterial3D（地面占领圈）


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260926   # 固定种子：掩体布局确定性（探针/截图可复现）
	_build_ground()
	_build_hq(ATK_HQ.z, Color(0.3, 0.5, 0.85), "进 攻 方 集 结 地")
	_build_hq(DEF_HQ.z, Color(0.85, 0.3, 0.25), "防 守 方 总 部")
	_build_sector_village(rng)
	_build_sector_depot(rng)
	_build_sector_command(rng)
	for si in SECTORS.size():
		_flags.append([])
		_rings.append([])
		for pi in 2:
			_build_point(si, pi)
	_build_cover(rng)
	_build_craters(rng)
	_build_dead_trees(rng)
	_build_perimeter()


## 解析地形高度（与视觉网格同函数，O(1)）
func terrain_height(x: float, z: float) -> float:
	return 0.6 * sin(x * 0.021) * cos(z * 0.017)


## onfoot 地面查询（鸭子类型：同 FreeroamMap.query 契约的最小子集）
func query(x: float, z: float, _hint = -1, _vy = -1e9) -> Dictionary:
	return {"idx": 0, "height": terrain_height(x, z)}


func point_pos(si: int, pi: int) -> Vector3:
	var p: Vector2 = SECTORS[si]["pts"][pi]
	return Vector3(p.x, terrain_height(p.x, p.y), p.y)


## 据点归属变化时改旗色/地圈色（col.a 当占领圈亮度）
func set_point_color(si: int, pi: int, col: Color, active: bool) -> void:
	var f: StandardMaterial3D = _flags[si][pi]
	f.albedo_color = col
	f.emission = col * 0.5
	var r: StandardMaterial3D = _rings[si][pi]
	r.albedo_color = Color(col.r, col.g, col.b, 0.55 if active else 0.18)


# ================= 障碍物空间格（同 FreeroamMap.obstacles_near） =================

const OBS_CELL := 48.0
const OBS_MARGIN := 4.0
var _obs_grid := {}
var _obs_grid_n := -1


func obstacles_near(x: float, z: float) -> Array:
	if _obs_grid_n != obstacles_box.size():
		_obs_grid = {}
		_obs_grid_n = obstacles_box.size()
		for oi in obstacles_box.size():
			var ob: Dictionary = obstacles_box[oi]
			ob["i"] = oi   # 射线去重用
			var c: Vector2 = ob["c"]
			var rad: float = Vector2(float(ob["hx"]), float(ob["hz"])).length() + OBS_MARGIN
			for gx in range(floori((c.x - rad) / OBS_CELL), floori((c.x + rad) / OBS_CELL) + 1):
				for gz in range(floori((c.y - rad) / OBS_CELL), floori((c.y + rad) / OBS_CELL) + 1):
					var k := Vector2i(gx, gz)
					if not _obs_grid.has(k):
						_obs_grid[k] = []
					_obs_grid[k].append(ob)
	return _obs_grid.get(Vector2i(floori(x / OBS_CELL), floori(z / OBS_CELL)), [])


## 点是否在某个障碍物（含高度）里——子弹/视线步进用
func solid_at(p: Vector3) -> bool:
	for ob in obstacles_near(p.x, p.z):
		if p.y > float(ob["top"]):
			continue
		var dx: float = p.x - ob["c"].x
		var dz: float = p.z - ob["c"].y
		var ca: float = cos(ob["rot"])
		var sa: float = sin(ob["rot"])
		if absf(ca * dx + sa * dz) <= ob["hx"] and absf(-sa * dx + ca * dz) <= ob["hz"]:
			return true
	return false


## 射线到第一个障碍物的距离（没有则 INF）：沿射线收集途经格子的障碍物去重，
## 逐个做 2D 板层求交 + 高度判定。原来按 1.5m 步进采样点，既慢（每条射线
## 上百次格子查询）又会漏掉 0.45m 厚的墙
func ray_wall(from: Vector3, dir: Vector3, max_d: float) -> float:
	var flat := Vector2(dir.x, dir.z)
	var fl := flat.length()
	var seen := {}
	var best := INF
	var steps := int(max_d * fl / (OBS_CELL * 0.4)) + 1
	for k in steps + 1:
		var t := minf(max_d, float(k) * OBS_CELL * 0.4 / maxf(fl, 0.001))
		var p := from + dir * t
		for ob in obstacles_near(p.x, p.z):
			var id: int = ob["i"]
			if seen.has(id):
				continue
			seen[id] = true
			var d := _ray_obb(from, dir, ob, minf(best, max_d))
			if d < best:
				best = d
		if t >= max_d:
			break
	return best


func _ray_obb(from: Vector3, dir: Vector3, ob: Dictionary, max_d: float) -> float:
	var ca: float = cos(ob["rot"])
	var sa: float = sin(ob["rot"])
	var ox: float = from.x - ob["c"].x
	var oz: float = from.z - ob["c"].y
	var lx: float = ca * ox + sa * oz
	var lz: float = -sa * ox + ca * oz
	var dx: float = ca * dir.x + sa * dir.z
	var dz: float = -sa * dir.x + ca * dir.z
	var t0 := 0.0
	var t1 := max_d
	for axis in 2:
		var o: float = lx if axis == 0 else lz
		var d: float = dx if axis == 0 else dz
		var h: float = ob["hx"] if axis == 0 else ob["hz"]
		if absf(d) < 1e-6:
			if absf(o) > h:
				return INF
			continue
		var ta := (-h - o) / d
		var tb := (h - o) / d
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return INF
	# 高度：进出点里较低的一个不高于障碍物顶即算命中（矮墙可从上方射过）
	var y := minf(from.y + dir.y * t0, from.y + dir.y * t1)
	if y > float(ob["top"]):
		return INF
	return t0


## 圆（半径 r）从障碍物中推出，返回新 XZ
func push_out(x: float, z: float, r: float) -> Vector2:
	var np := Vector2(x, z)
	for ob in obstacles_near(x, z):
		var dx: float = np.x - ob["c"].x
		var dz: float = np.y - ob["c"].y
		var ca: float = cos(ob["rot"])
		var sa: float = sin(ob["rot"])
		var lx: float = ca * dx + sa * dz
		var lz: float = -sa * dx + ca * dz
		var px: float = ob["hx"] + r - absf(lx)
		var pz: float = ob["hz"] + r - absf(lz)
		if px > 0.0 and pz > 0.0:
			if px < pz:
				lx = signf(lx) * (ob["hx"] + r)
			else:
				lz = signf(lz) * (ob["hz"] + r)
			np = Vector2(ob["c"].x + ca * lx - sa * lz, ob["c"].y + sa * lx + ca * lz)
	return np


# ================= 地面 =================

func _build_ground() -> void:
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


# ================= 构件 =================

## 程序化盒体：视觉 + OBB 碰撞登记（pos.y 为离地基准，叠层用）
func _add_box(size: Vector3, pos: Vector3, rot_y: float, color: Color,
		rough := 0.95) -> void:
	_add_vis_box(size, pos, rot_y, color, rough)
	obstacles_box.append({
		"c": Vector2(pos.x, pos.z), "hx": size.x * 0.5, "hz": size.z * 0.5,
		"rot": rot_y, "top": terrain_height(pos.x, pos.z) + pos.y + size.y,
	})


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


## 圆柱（油罐/雷达座）：视觉 + 外接方形碰撞
func _add_cyl(r: float, h: float, pos: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 20
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.metallic = 0.3
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(pos.x, terrain_height(pos.x, pos.z) + pos.y + h * 0.5, pos.z)
	add_child(mi)
	obstacles_box.append({"c": Vector2(pos.x, pos.z), "hx": r * 0.9, "hz": r * 0.9,
			"rot": 0.0, "top": terrain_height(pos.x, pos.z) + pos.y + h})


## 带门洞的房子（四面墙 + 平顶可选），rot 绕 Y
func _add_house(c: Vector2, w: float, d: float, h: float, rot: float, col: Color,
		roof := true, door_sides := [0]) -> void:
	var t := 0.45
	var fwd := Vector2(sin(rot), cos(rot))      # 局部 +Z
	var right := Vector2(cos(rot), -sin(rot))   # 局部 +X
	var walls := [
		[Vector2(0, -d * 0.5), w, true],   # 0 前墙（-Z）
		[Vector2(0, d * 0.5), w, true],    # 1 后墙
		[Vector2(-w * 0.5, 0), d, false],  # 2 左墙
		[Vector2(w * 0.5, 0), d, false],   # 3 右墙
	]
	for wi in 4:
		var off: Vector2 = walls[wi][0]
		var ln: float = walls[wi][1]
		var along_x: bool = walls[wi][2]
		var wc: Vector2 = c + right * off.x + fwd * off.y
		if wi in door_sides:
			var gap := 1.8
			var seg := (ln - gap) * 0.5
			for sgn in [-1.0, 1.0]:
				var so: float = sgn * (gap * 0.5 + seg * 0.5)
				var sc: Vector2 = wc + (right if along_x else fwd) * so
				var sz := Vector3(seg, h, t) if along_x else Vector3(t, h, seg)
				_add_box(sz, Vector3(sc.x, 0, sc.y), rot, col)
		else:
			var sz2 := Vector3(ln, h, t) if along_x else Vector3(t, h, ln)
			_add_box(sz2, Vector3(wc.x, 0, wc.y), rot, col)
	if roof:
		_add_vis_box(Vector3(w + 0.4, 0.25, d + 0.4), Vector3(c.x, h, c.y), rot,
				col.darkened(0.25))


## 沙袋短墙（双层错缝）
func _add_sandbags(c: Vector2, rot: float, n: int) -> void:
	var sand := Color(0.72, 0.66, 0.5)
	var dirv := Vector2(cos(rot), -sin(rot))
	for k in n:
		var ox := (float(k) - float(n - 1) * 0.5) * 2.5
		var p := c + dirv * ox
		_add_box(Vector3(2.5, 0.8, 0.75), Vector3(p.x, 0, p.y), rot, sand)
		_add_box(Vector3(2.5, 0.8, 0.75), Vector3(p.x + dirv.x * 0.4, 0.8, p.y + dirv.y * 0.4),
				rot + 0.04, sand)


func _add_container(c: Vector2, rot: float, col: Color, stack := 1) -> void:
	for s in stack:
		_add_box(Vector3(2.5, 2.6, 6.1), Vector3(c.x, s * 2.6, c.y), rot, col, 0.6)


# ================= 总部 =================

func _build_hq(z_center: float, flag_color: Color, title: String) -> void:
	var dir_sign := signf(z_center)
	for k in 11:
		if k == 4 or k == 5 or k == 6:
			continue   # 正中留宽门口（载具可出）
		var ang := deg_to_rad(-70.0 + k * 14.0)
		var bx := sin(ang) * 22.0
		var bz := z_center + cos(ang) * 22.0 * -dir_sign
		_add_box(Vector3(3.4, 1.1, 0.8), Vector3(bx, 0, bz), -ang * dir_sign,
				Color(0.72, 0.66, 0.5))
	# 帐篷 + 物资
	for k in 3:
		var tx := -30.0 + k * 30.0
		var tz := z_center + dir_sign * 8.0
		_add_box(Vector3(6.0, 2.6, 4.0), Vector3(tx, 0, tz), 0.0,
				Color(0.42, 0.44, 0.34))
	var pole := BoxMesh.new()
	pole.size = Vector3(0.18, 8.0, 0.18)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.55, 0.55, 0.58)
	pole.material = pmat
	var pz := z_center + dir_sign * 2.0
	var pole_mi := MeshInstance3D.new()
	pole_mi.mesh = pole
	pole_mi.position = Vector3(0, terrain_height(0, pz) + 4.0, pz)
	add_child(pole_mi)
	for side in [1.0, -1.0]:
		var flag := Label3D.new()
		flag.text = title
		flag.font_size = 200
		flag.modulate = flag_color
		flag.outline_size = 40
		flag.double_sided = false
		flag.position = Vector3(0, terrain_height(0, pz) + 9.0, pz + side * 0.1)
		flag.rotation.y = 0.0 if side > 0.0 else PI
		add_child(flag)


# ================= 三个区域的据点场景 =================

## 区域 1 · 村落：A 点土房群 + 院墙；B 点农场围院 + 谷仓
func _build_sector_village(rng: RandomNumberGenerator) -> void:
	var wall_a := Color(0.56, 0.5, 0.42)
	var wall_b := Color(0.4, 0.35, 0.29)
	var a: Vector2 = SECTORS[0]["pts"][0]
	var houses := [Vector2(-16, -10), Vector2(15, -12), Vector2(-18, 14), Vector2(17, 13),
			Vector2(0, 24), Vector2(-32, 0)]
	for i in houses.size():
		var hc: Vector2 = a + houses[i]
		_add_house(hc, rng.randf_range(6.0, 8.0), rng.randf_range(5.0, 7.0),
				rng.randf_range(2.8, 3.4), rng.randf_range(-0.25, 0.25),
				wall_a if i % 2 == 0 else wall_b, rng.randf() < 0.6, [i % 4, (i + 2) % 4])
	_add_sandbags(a + Vector2(0, 8), 0.0, 3)
	_add_sandbags(a + Vector2(-6, -4), PI * 0.5, 2)
	var b: Vector2 = SECTORS[0]["pts"][1]
	# 围院（四角留口）
	for s in [[Vector2(0, -20), 0.0, 30.0], [Vector2(0, 20), 0.0, 30.0],
			[Vector2(-20, 0), PI * 0.5, 30.0], [Vector2(20, 0), PI * 0.5, 30.0]]:
		var sc: Vector2 = b + s[0]
		var rot: float = s[1]
		var ln: float = s[2]
		var dirv := Vector2(cos(rot), -sin(rot))
		for sg in [-1.0, 1.0]:
			var p: Vector2 = sc + dirv * sg * ln * 0.3
			_add_box(Vector3(ln * 0.38, 2.2, 0.5), Vector3(p.x, 0, p.y), rot, wall_a)
	_add_house(b + Vector2(-8, -6), 12.0, 8.0, 4.8, 0.0, Color(0.5, 0.3, 0.22), true, [0, 1])
	_add_house(b + Vector2(9, 8), 6.0, 5.0, 3.0, 0.1, wall_b, true, [2])
	_add_box(Vector3(1.6, 1.6, 1.6), Vector3(b.x + 6, 0, b.y - 8), 0.3, Color(0.52, 0.38, 0.22))
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(b.x + 7.6, 0, b.y - 7), 0.7, Color(0.52, 0.38, 0.22))
	_add_sandbags(b + Vector2(2, 2), 0.3, 2)


## 区域 2 · 油库：A 点储油罐区 + 管廊；B 点仓库 + 集装箱堆场
func _build_sector_depot(rng: RandomNumberGenerator) -> void:
	var a: Vector2 = SECTORS[1]["pts"][0]
	for t in [Vector2(-14, -12), Vector2(14, -12), Vector2(-14, 13), Vector2(15, 12)]:
		var tc: Vector2 = a + t
		_add_cyl(5.0, rng.randf_range(6.0, 8.0), Vector3(tc.x, 0, tc.y), Color(0.78, 0.76, 0.7))
	_add_box(Vector3(30.0, 0.6, 0.6), Vector3(a.x, 3.2, a.y), 0.0, Color(0.4, 0.42, 0.44))
	_add_box(Vector3(0.6, 0.6, 26.0), Vector3(a.x, 3.2, a.y), 0.0, Color(0.4, 0.42, 0.44))
	_add_sandbags(a + Vector2(0, 5), 0.0, 2)
	_add_sandbags(a + Vector2(-5, -3), PI * 0.5, 2)
	var b: Vector2 = SECTORS[1]["pts"][1]
	_add_house(b + Vector2(0, -16), 22.0, 12.0, 6.5, 0.0, Color(0.5, 0.52, 0.5), true, [1, 2])
	var cols := [Color(0.62, 0.22, 0.16), Color(0.16, 0.36, 0.52), Color(0.72, 0.52, 0.16),
			Color(0.3, 0.44, 0.28)]
	for k in 6:
		var cc: Vector2 = b + Vector2(-18.0 + float(k % 3) * 18.0, 6.0 + float(k / 3) * 12.0) \
				+ Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		_add_container(cc, rng.randf_range(-0.2, 0.2) + (PI * 0.5 if k % 2 == 0 else 0.0),
				cols[k % cols.size()], 2 if k == 1 or k == 4 else 1)


## 区域 3 · 指挥所：A 点混凝土掩体群 + 战壕；B 点雷达站 + 通讯楼
func _build_sector_command(rng: RandomNumberGenerator) -> void:
	var concrete := Color(0.58, 0.58, 0.56)
	var a: Vector2 = SECTORS[2]["pts"][0]
	_add_house(a + Vector2(0, -12), 14.0, 9.0, 3.2, 0.0, concrete, true, [0, 1])
	_add_house(a + Vector2(-18, 6), 8.0, 7.0, 3.0, 0.3, concrete, true, [3])
	for k in 5:
		var ang := float(k) / 5.0 * TAU
		_add_sandbags(a + Vector2(cos(ang), sin(ang)) * 9.0, ang + PI * 0.5, 2)
	var b: Vector2 = SECTORS[2]["pts"][1]
	_add_cyl(2.2, 3.0, Vector3(b.x + 10, 0, b.y - 6), concrete)
	var dish := CylinderMesh.new()
	dish.top_radius = 4.0
	dish.bottom_radius = 0.3
	dish.height = 1.4
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.85, 0.86, 0.88)
	dish.material = dmat
	var dmi := MeshInstance3D.new()
	dmi.mesh = dish
	dmi.position = Vector3(b.x + 10, terrain_height(b.x + 10, b.y - 6) + 4.2, b.y - 6)
	dmi.rotation.x = 0.5
	add_child(dmi)
	_add_house(b + Vector2(-10, 4), 10.0, 10.0, 7.0, 0.0, Color(0.46, 0.48, 0.52), true, [0, 3])
	_add_sandbags(b + Vector2(4, 8), 0.0, 3)
	_add_box(Vector3(4.2, 1.25, 0.5), Vector3(b.x - 2, 0, b.y - 8), 0.2, concrete)


## 据点：旗杆 + 可改色旗面 + 地面占领圈 + 字母标
func _build_point(si: int, pi: int) -> void:
	var p := point_pos(si, pi)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.09
	pole.height = 7.0
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.7, 0.7, 0.72)
	pole.material = pmat
	var pmi := MeshInstance3D.new()
	pmi.mesh = pole
	pmi.position = p + Vector3(0, 3.5, 0)
	add_child(pmi)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.85, 0.3, 0.25)
	fm.emission_enabled = true
	fm.emission = Color(0.4, 0.15, 0.12)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flag := BoxMesh.new()
	flag.size = Vector3(2.2, 1.3, 0.05)
	flag.material = fm
	var fmi := MeshInstance3D.new()
	fmi.mesh = flag
	fmi.position = p + Vector3(1.15, 6.2, 0)
	add_child(fmi)
	_flags[si].append(fm)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.85, 0.3, 0.25, 0.2)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := TorusMesh.new()
	ring.inner_radius = POINT_R - 0.35
	ring.outer_radius = POINT_R
	ring.rings = 48
	ring.material = rm
	var rmi := MeshInstance3D.new()
	rmi.mesh = ring
	rmi.position = p + Vector3(0, 0.08, 0)
	rmi.scale = Vector3(1, 0.05, 1)
	add_child(rmi)
	_rings[si].append(rm)
	var lb := Label3D.new()
	lb.text = "%d%s" % [si + 1, "AB"[pi]]
	lb.font_size = 180
	lb.outline_size = 36
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position = p + Vector3(0, 8.2, 0)
	add_child(lb)


# ================= 散布掩体 / 装饰 =================

func _near_point(p: Vector2, r: float) -> bool:
	for s in SECTORS:
		for q in s["pts"]:
			if p.distance_to(q) < r:
				return true
	if absf(p.y - ATK_HQ.z) < 34.0 or absf(p.y - DEF_HQ.z) < 30.0:
		return true
	return false


## 区域之间的无人区掩体：水泥墙 / 木箱堆 / 断墙 / 锈蚀车壳 / 沙袋
func _build_cover(rng: RandomNumberGenerator) -> void:
	var concrete := Color(0.58, 0.58, 0.56)
	var wood := Color(0.52, 0.38, 0.22)
	var rust := Color(0.36, 0.24, 0.16)
	var placed: Array[Vector2] = []
	for k in 60:
		var pos := Vector2.ZERO
		var ok := false
		for try_i in 24:
			pos = Vector2(rng.randf_range(-220.0, 220.0), rng.randf_range(-165.0, 150.0))
			ok = not _near_point(pos, 26.0)
			for p in placed:
				if pos.distance_to(p) < 15.0:
					ok = false
					break
			if ok:
				break
		if not ok:
			continue
		placed.append(pos)
		var rot := rng.randf_range(0.0, TAU)
		match rng.randi_range(0, 4):
			0:
				_add_box(Vector3(4.2, 1.25, 0.5), Vector3(pos.x, 0, pos.y), rot, concrete)
			1:
				_add_box(Vector3(1.7, 1.7, 1.7), Vector3(pos.x, 0, pos.y), rot, wood)
				_add_box(Vector3(1.2, 1.2, 1.2), Vector3(pos.x + 1.6, 0, pos.y + 0.5), rot + 0.5, wood)
			2:
				_add_box(Vector3(0.45, 2.6, 5.0), Vector3(pos.x, 0, pos.y), rot, Color(0.5, 0.47, 0.42))
			3:
				_add_box(Vector3(2.0, 1.5, 4.4), Vector3(pos.x, 0, pos.y), rot, rust)
			4:
				_add_sandbags(pos, rot, 3)


func _build_craters(rng: RandomNumberGenerator) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.2, 0.16)
	mat.roughness = 1.0
	mesh.material = mat
	for k in 22:
		var x := rng.randf_range(-220.0, 220.0)
		var z := rng.randf_range(-170.0, 160.0)
		var r := rng.randf_range(1.6, 4.2)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = Vector3(r, 0.12, r)
		mi.position = Vector3(x, terrain_height(x, z) + 0.02, z)
		add_child(mi)


func _build_dead_trees(rng: RandomNumberGenerator) -> void:
	var bark := Color(0.22, 0.18, 0.15)
	for t in 14:
		var x := rng.randf_range(-230.0, 230.0)
		var z := rng.randf_range(-175.0, 170.0)
		if _near_point(Vector2(x, z), 18.0):
			continue
		var h := rng.randf_range(3.2, 5.2)
		_add_box(Vector3(0.34, h, 0.34), Vector3(x, 0, z), rng.randf_range(0.0, TAU), bark)
		var rot := rng.randf_range(0.0, TAU)
		_add_vis_box(Vector3(0.18, 1.8, 0.18), Vector3(x, h * 0.62, z), rot, bark)


## 周界石墙：连续封闭（原来石块间留 5m 缺口，人能走出场外）
func _build_perimeter() -> void:
	var rock := Color(0.44, 0.4, 0.35)
	var step := 12.0
	var cx := -ARENA_X
	while cx <= ARENA_X:
		_add_box(Vector3(step + 0.5, 2.8, 2.8), Vector3(cx, 0, -ARENA_Z), 0.0, rock)
		_add_box(Vector3(step + 0.5, 2.8, 2.8), Vector3(cx, 0, ARENA_Z), 0.0, rock)
		cx += step
	var cz := -ARENA_Z
	while cz <= ARENA_Z:
		_add_box(Vector3(2.8, 2.8, step + 0.5), Vector3(-ARENA_X, 0, cz), 0.0, rock)
		_add_box(Vector3(2.8, 2.8, step + 0.5), Vector3(ARENA_X, 0, cz), 0.0, rock)
		cz += step
