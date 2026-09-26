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

## Blender 生成的场景道具（tools/blender/make_battle_props.py）。碰撞仍按原盒子登记，
## 模型只负责外观：尺寸与盒子对齐（原点在底面中心、正面朝 +Z）
## 运行时按路径 load（不用 preload：模型走 Git LFS，没拉到真文件时 preload 会让脚本
## 编译失败、整个游戏起不来；load 失败的道具退化成同尺寸贴图盒子）
const PROP_DIR := "res://assets/battle/props/"
## 每个道具的原始外形尺寸（宽 x / 高 y / 深 z）：替身盒子与房屋缩放都用它
const PROP_DIMS := {
	"house": Vector3(7.0, 3.1, 6.0), "barn": Vector3(12.0, 4.8, 8.0),
	"bunker": Vector3(14.0, 3.2, 9.0), "warehouse": Vector3(22.0, 6.5, 12.0),
	"sandbags": Vector3(2.5, 1.6, 0.75), "container": Vector3(2.44, 2.59, 6.06),
	"fuel_tank": Vector3(10.0, 7.8, 10.0), "barrier": Vector3(4.2, 1.25, 0.5),
	"crate": Vector3(1.0, 1.0, 1.0), "barrel": Vector3(0.6, 0.9, 0.6),
	"wreck": Vector3(2.0, 1.5, 4.4), "rocks": Vector3(13.4, 2.8, 2.8),
	"tent": Vector3(6.0, 2.6, 4.0), "dead_tree": Vector3(0.34, 4.2, 0.34),
}
var _prop_scenes := {}          # 名字 → PackedScene（加载失败存 null，只警告一次）
var missing: Array = []         # 加载失败的模型 [{path, why}]（进场时上屏提示）
## 可按实例染色的材质（贴图是灰阶/浅色，乘底色）
const TINTABLE := ["Paint", "Plaster", "Concrete", "TankPaint"]

var obstacles_box: Array = []   # OBB {c: Vector2, hx, hz, rot, top}（onfoot 推出 / 子弹墙体共用）
var _tint_cache := {}
var _box_mats := {}             # 颜色 → 带颗粒贴图的三平面材质（剩下的盒子用）
var _grit: NoiseTexture2D
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


## 模型加载失败的原因诊断（给另一台电脑上的人看得懂的一句话）：
## LFS 指针没下真文件 / 没导入 / 导入了但这个 Godot 版本加载不了
static func asset_diagnosis(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "文件不存在：先在这台电脑的项目目录 git pull"
	var head := f.get_buffer(40).get_string_from_ascii()
	f.close()
	if head.begins_with("version https://git-lfs"):
		return "只有 Git LFS 指针、没下载到真模型：在项目目录运行 git lfs install 和 git lfs pull"
	if not head.begins_with("glTF"):
		return "模型文件已损坏：删掉后重新 git lfs pull"
	var imp := FileAccess.open(path + ".import", FileAccess.READ)
	if imp == null:
		return "缺少 .import 文件：git pull 不完整"
	var dest := ""
	for line in imp.get_as_text().split("\n"):
		if line.begins_with("path=") or line.begins_with("path."):
			dest = line.get_slice("\"", 1)
			break
	imp.close()
	if dest == "" or not FileAccess.file_exists(dest):
		return "还没导入：用 Godot 编辑器打开项目，等右下角导入进度走完再运行"
	return "已导入但加载失败（这台 Godot %s，模型按 4.7 导出）：在编辑器文件系统里右键 assets/battle → 重新导入" \
			% Engine.get_version_info()["string"]


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

## 共用颗粒贴图（可平铺 fbm 噪声）：地面 / 剩余盒体用世界坐标三平面贴，不随尺寸拉伸
func _grit_tex() -> NoiseTexture2D:
	if _grit == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012
		n.fractal_octaves = 5
		n.seed = 20260926
		_grit = NoiseTexture2D.new()
		_grit.width = 512
		_grit.height = 512
		_grit.seamless = true
		_grit.noise = n
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.72, 0.72, 0.72))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		_grit.color_ramp = ramp
	return _grit


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
	mat.albedo_color = Color(0.74, 0.63, 0.47)   # 荒漠尘土（乘颗粒贴图后约原色）
	mat.albedo_texture = _grit_tex()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.06, 0.06, 0.06)
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

## 只登记碰撞（外观由模型负责）
func _col(size: Vector3, pos: Vector3, rot_y: float) -> void:
	obstacles_box.append({
		"c": Vector2(pos.x, pos.z), "hx": size.x * 0.5, "hz": size.z * 0.5,
		"rot": rot_y, "top": terrain_height(pos.x, pos.z) + pos.y + size.y,
	})


## 程序化盒体：视觉 + OBB 碰撞登记（pos.y 为离地基准，叠层用）
func _add_box(size: Vector3, pos: Vector3, rot_y: float, color: Color,
		rough := 0.95) -> void:
	_add_vis_box(size, pos, rot_y, color, rough)
	_col(size, pos, rot_y)


## 纯视觉盒体（不参与碰撞/子弹）：带颗粒贴图的世界三平面材质，按颜色共用
func _add_vis_box(size: Vector3, pos: Vector3, rot_y: float,
		color: Color, rough := 0.95) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _box_mat(color, rough)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(pos.x,
			terrain_height(pos.x, pos.z) + pos.y + size.y * 0.5, pos.z)
	mi.rotation.y = rot_y
	add_child(mi)


func _box_mat(color: Color, rough: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), rough]
	if not _box_mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color * 1.2
		mat.albedo_texture = _grit_tex()
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
		mat.roughness = rough
		_box_mats[key] = mat
	return _box_mats[key]


## 摆一个 Blender 道具：贴地（+y_off）、绕 Y 旋转、缩放；tint 乘到可染色材质上
func _prop(name: String, x: float, z: float, rot_y: float, scl := Vector3.ONE,
		tint := Color.WHITE, y_off := 0.0) -> Node3D:
	if not _prop_scenes.has(name):
		var path: String = PROP_DIR + name + ".glb"
		_prop_scenes[name] = load(path) if ResourceLoader.exists(path) else null
		if _prop_scenes[name] == null:
			var why := asset_diagnosis(path)
			missing.append({"path": path, "why": why})
			push_warning("[大战场] 道具模型加载失败：%s —— %s（暂用盒子代替）" % [path, why])
	var ps: PackedScene = _prop_scenes[name]
	if ps == null:
		var dims: Vector3 = PROP_DIMS[name]
		var fb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = dims
		bm.material = _box_mat(Color(0.62, 0.55, 0.45) * tint, 0.95)
		fb.mesh = bm
		fb.position = Vector3(x, terrain_height(x, z) + y_off + dims.y * 0.5 * scl.y, z)
		fb.rotation.y = rot_y
		fb.scale = scl
		add_child(fb)
		return fb
	var n: Node3D = ps.instantiate()
	n.position = Vector3(x, terrain_height(x, z) + y_off, z)
	n.rotation.y = rot_y
	n.scale = scl
	if tint != Color.WHITE:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m3: MeshInstance3D = mi
			for si in m3.mesh.get_surface_count():
				var m: Material = m3.mesh.surface_get_material(si)
				if m is StandardMaterial3D and m.resource_name in TINTABLE:
					m3.set_surface_override_material(si, _tinted(m, tint))
	add_child(n)
	return n


func _tinted(m: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [m.get_instance_id(), tint.to_html()]
	if not _tint_cache.has(key):
		var t: StandardMaterial3D = m.duplicate()
		t.albedo_color = Color(m.albedo_color.r * tint.r, m.albedo_color.g * tint.g,
				m.albedo_color.b * tint.b)
		_tint_cache[key] = t
	return _tint_cache[key]


## 储油罐：模型 + 外接方形碰撞
func _add_tank(r: float, h: float, pos: Vector3) -> void:
	_prop("fuel_tank", pos.x, pos.z, 0.0, Vector3(r / 5.0, h / 7.0, r / 5.0))
	obstacles_box.append({"c": Vector2(pos.x, pos.z), "hx": r * 0.9, "hz": r * 0.9,
			"rot": 0.0, "top": terrain_height(pos.x, pos.z) + pos.y + h})


## 圆柱（雷达座等）：视觉 + 外接方形碰撞
func _add_cyl(r: float, h: float, pos: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 20
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color * 1.2
	mat.albedo_texture = _grit_tex()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	mat.roughness = 0.7
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(pos.x, terrain_height(pos.x, pos.z) + pos.y + h * 0.5, pos.z)
	add_child(mi)
	obstacles_box.append({"c": Vector2(pos.x, pos.z), "hx": r * 0.9, "hz": r * 0.9,
			"rot": 0.0, "top": terrain_height(pos.x, pos.z) + pos.y + h})


## 房屋：外观用 Blender 模型（model = house/barn/bunker/warehouse，按占地缩放），
## 碰撞仍是四面墙 + 门洞。door_axis 0 = 门在前后墙，1 = 门在左右墙（模型转 90°）
func _add_house(c: Vector2, w: float, d: float, h: float, rot: float, tint: Color,
		model := "house", door_axis := 0) -> void:
	var t := 0.45
	var fwd := Vector2(sin(rot), cos(rot))      # 局部 +Z
	var right := Vector2(cos(rot), -sin(rot))   # 局部 +X
	var door_sides := [0, 1] if door_axis == 0 else [2, 3]
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
				_col(Vector3(seg, h, t) if along_x else Vector3(t, h, seg), Vector3(sc.x, 0, sc.y), rot)
		else:
			_col(Vector3(ln, h, t) if along_x else Vector3(t, h, ln), Vector3(wc.x, 0, wc.y), rot)
	var dim: Vector3 = PROP_DIMS[model]
	if door_axis == 0:
		_prop(model, c.x, c.y, rot, Vector3(w / dim.x, h / dim.y, d / dim.z), tint)
	else:
		_prop(model, c.x, c.y, rot + PI * 0.5, Vector3(d / dim.x, h / dim.y, w / dim.z), tint)


## 沙袋墙：每段 2.5m 一个模型（逐袋堆叠），碰撞同原来的双层盒
func _add_sandbags(c: Vector2, rot: float, n: int) -> void:
	var dirv := Vector2(cos(rot), -sin(rot))
	for k in n:
		var ox := (float(k) - float(n - 1) * 0.5) * 2.5
		var p := c + dirv * ox
		_col(Vector3(2.5, 1.6, 0.75), Vector3(p.x, 0, p.y), rot)
		_prop("sandbags", p.x, p.y, rot)


func _add_container(c: Vector2, rot: float, col: Color, stack := 1) -> void:
	for s2 in stack:
		_col(Vector3(2.5, 2.6, 6.1), Vector3(c.x, s2 * 2.6, c.y), rot)
		_prop("container", c.x, c.y, rot, Vector3(2.5 / 2.44, 1.0, 6.1 / 6.06),
				col * 1.4, s2 * 2.6)


func _add_crate(size: float, x: float, z: float, rot: float) -> void:
	_col(Vector3(size, size, size), Vector3(x, 0, z), rot)
	_prop("crate", x, z, rot, Vector3.ONE * size)


## 油桶堆（纯装饰 + 一个外接碰撞）
func _add_barrels(c: Vector2, n: int, rng: RandomNumberGenerator) -> void:
	var cols := [Color(0.45, 0.55, 0.4), Color(0.7, 0.3, 0.2), Color(0.3, 0.45, 0.65)]
	for k in n:
		var p := c + Vector2(float(k % 3) * 0.68, float(k / 3) * 0.68) \
				+ Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08))
		_prop("barrel", p.x, p.y, rng.randf_range(0.0, TAU), Vector3.ONE,
				cols[rng.randi() % cols.size()])
	_col(Vector3(2.1, 0.9, 2.1), Vector3(c.x + 0.68, 0, c.y + 0.68 * float((n - 1) / 3) * 0.5), 0.0)


# ================= 总部 =================

func _build_hq(z_center: float, flag_color: Color, title: String) -> void:
	var dir_sign := signf(z_center)
	for k in 11:
		if k == 4 or k == 5 or k == 6:
			continue   # 正中留宽门口（载具可出）
		var ang := deg_to_rad(-70.0 + k * 14.0)
		var bx := sin(ang) * 22.0
		var bz := z_center + cos(ang) * 22.0 * -dir_sign
		_col(Vector3(3.4, 1.1, 0.8), Vector3(bx, 0, bz), -ang * dir_sign)
		_prop("sandbags", bx, bz, -ang * dir_sign, Vector3(3.4 / 2.5, 1.1 / 1.6, 0.8 / 0.75))
	# 帐篷 + 物资
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(z_center))
	for k in 3:
		var tx := -30.0 + k * 30.0
		var tz := z_center + dir_sign * 8.0
		_col(Vector3(6.0, 2.6, 4.0), Vector3(tx, 0, tz), 0.0)
		_prop("tent", tx, tz, 0.0 if dir_sign < 0.0 else PI)
	_add_crate(1.2, -14.0, z_center + dir_sign * 10.0, 0.2)
	_add_crate(1.0, -12.6, z_center + dir_sign * 10.4, 0.6)
	_add_barrels(Vector2(12.0, z_center + dir_sign * 9.0), 5, rng)
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

## 区域 1 · 村落：A 点土房群；B 点农场围院 + 谷仓
func _build_sector_village(rng: RandomNumberGenerator) -> void:
	var wall_a := Color(1.0, 1.0, 1.0)          # 土坯本色
	var wall_b := Color(0.82, 0.78, 0.74)       # 旧墙发暗
	var a: Vector2 = SECTORS[0]["pts"][0]
	var houses := [Vector2(-16, -10), Vector2(15, -12), Vector2(-18, 14), Vector2(17, 13),
			Vector2(0, 24), Vector2(-32, 0)]
	for i in houses.size():
		var hc: Vector2 = a + houses[i]
		_add_house(hc, rng.randf_range(6.0, 8.0), rng.randf_range(5.0, 7.0),
				rng.randf_range(2.8, 3.4), rng.randf_range(-0.25, 0.25),
				wall_a if i % 2 == 0 else wall_b, "house", i % 2)
		rng.randf()   # 保留原来「有无屋顶」那次抽签，布局随机序列不变
	_add_sandbags(a + Vector2(0, 8), 0.0, 3)
	_add_sandbags(a + Vector2(-6, -4), PI * 0.5, 2)
	_add_barrels(a + Vector2(6, -2), 4, rng)
	var b: Vector2 = SECTORS[0]["pts"][1]
	# 围院土墙（四角留口）
	for s2 in [[Vector2(0, -20), 0.0, 30.0], [Vector2(0, 20), 0.0, 30.0],
			[Vector2(-20, 0), PI * 0.5, 30.0], [Vector2(20, 0), PI * 0.5, 30.0]]:
		var sc: Vector2 = b + s2[0]
		var rot: float = s2[1]
		var ln: float = s2[2]
		var dirv := Vector2(cos(rot), -sin(rot))
		for sg in [-1.0, 1.0]:
			var p: Vector2 = sc + dirv * sg * ln * 0.3
			_add_box(Vector3(ln * 0.38, 2.2, 0.5), Vector3(p.x, 0, p.y), rot, Color(0.62, 0.53, 0.41))
	_add_house(b + Vector2(-8, -6), 12.0, 8.0, 4.8, 0.0, Color(0.95, 0.62, 0.5), "barn", 0)
	_add_house(b + Vector2(9, 8), 6.0, 5.0, 3.0, 0.1, wall_b, "house", 1)
	_add_crate(1.6, b.x + 6, b.y - 8, 0.3)
	_add_crate(1.2, b.x + 7.6, b.y - 7, 0.7)
	_add_sandbags(b + Vector2(2, 2), 0.3, 2)


## 区域 2 · 油库：A 点储油罐区 + 管廊；B 点仓库 + 集装箱堆场
func _build_sector_depot(rng: RandomNumberGenerator) -> void:
	var a: Vector2 = SECTORS[1]["pts"][0]
	for t2 in [Vector2(-14, -12), Vector2(14, -12), Vector2(-14, 13), Vector2(15, 12)]:
		var tc: Vector2 = a + t2
		_add_tank(5.0, rng.randf_range(6.0, 8.0), Vector3(tc.x, 0, tc.y))
	_add_box(Vector3(30.0, 0.6, 0.6), Vector3(a.x, 3.2, a.y), 0.0, Color(0.4, 0.42, 0.44), 0.5)
	_add_box(Vector3(0.6, 0.6, 26.0), Vector3(a.x, 3.2, a.y), 0.0, Color(0.4, 0.42, 0.44), 0.5)
	for px in [-9.0, 9.0]:   # 管廊支架
		_add_vis_box(Vector3(0.3, 3.2, 0.3), Vector3(a.x + px, 0, a.y), 0.0, Color(0.35, 0.36, 0.38))
	_add_sandbags(a + Vector2(0, 5), 0.0, 2)
	_add_sandbags(a + Vector2(-5, -3), PI * 0.5, 2)
	_add_barrels(a + Vector2(4, -4), 6, rng)
	var b: Vector2 = SECTORS[1]["pts"][1]
	_add_house(b + Vector2(0, -16), 22.0, 12.0, 6.5, 0.0, Color(0.72, 0.76, 0.74), "warehouse", 0)
	var cols := [Color(0.62, 0.22, 0.16), Color(0.16, 0.36, 0.52), Color(0.72, 0.52, 0.16),
			Color(0.3, 0.44, 0.28)]
	for k in 6:
		var cc: Vector2 = b + Vector2(-18.0 + float(k % 3) * 18.0, 6.0 + float(k / 3) * 12.0) \
				+ Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		_add_container(cc, rng.randf_range(-0.2, 0.2) + (PI * 0.5 if k % 2 == 0 else 0.0),
				cols[k % cols.size()], 2 if k == 1 or k == 4 else 1)


## 区域 3 · 指挥所：A 点混凝土掩体群 + 沙袋环；B 点雷达站 + 通讯楼
func _build_sector_command(rng: RandomNumberGenerator) -> void:
	var concrete := Color(0.58, 0.58, 0.56)
	var a: Vector2 = SECTORS[2]["pts"][0]
	_add_house(a + Vector2(0, -12), 14.0, 9.0, 3.2, 0.0, Color.WHITE, "bunker", 0)
	_add_house(a + Vector2(-18, 6), 8.0, 7.0, 3.0, 0.3, Color(0.92, 0.92, 0.9), "bunker", 1)
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
	dmat.metallic = 0.4
	dmat.roughness = 0.4
	dish.material = dmat
	var dmi := MeshInstance3D.new()
	dmi.mesh = dish
	dmi.position = Vector3(b.x + 10, terrain_height(b.x + 10, b.y - 6) + 4.2, b.y - 6)
	dmi.rotation.x = 0.5
	add_child(dmi)
	_add_house(b + Vector2(-10, 4), 10.0, 10.0, 7.0, 0.0, Color(0.86, 0.9, 0.98), "bunker", 0)
	_add_sandbags(b + Vector2(4, 8), 0.0, 3)
	_col(Vector3(4.2, 1.25, 0.5), Vector3(b.x - 2, 0, b.y - 8), 0.2)
	_prop("barrier", b.x - 2, b.y - 8, 0.2)


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


## 区域之间的无人区掩体：防爆墙 / 木箱堆 / 断墙 / 烧毁车辆 / 沙袋
func _build_cover(rng: RandomNumberGenerator) -> void:
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
				_col(Vector3(4.2, 1.25, 0.5), Vector3(pos.x, 0, pos.y), rot)
				_prop("barrier", pos.x, pos.y, rot)
			1:
				_add_crate(1.7, pos.x, pos.y, rot)
				_add_crate(1.2, pos.x + 1.6, pos.y + 0.5, rot + 0.5)
			2:
				_add_box(Vector3(0.45, 2.6, 5.0), Vector3(pos.x, 0, pos.y), rot, Color(0.6, 0.52, 0.42))
			3:
				_col(Vector3(2.0, 1.5, 4.4), Vector3(pos.x, 0, pos.y), rot)
				_prop("wreck", pos.x, pos.y, rot)
			4:
				_add_sandbags(pos, rot, 3)


func _build_craters(rng: RandomNumberGenerator) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.25, 0.2)
	mat.albedo_texture = _grit_tex()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
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
	for t2 in 14:
		var x := rng.randf_range(-230.0, 230.0)
		var z := rng.randf_range(-175.0, 170.0)
		if _near_point(Vector2(x, z), 18.0):
			continue
		var h := rng.randf_range(3.2, 5.2)
		var rot0 := rng.randf_range(0.0, TAU)
		_col(Vector3(0.34, h, 0.34), Vector3(x, 0, z), rot0)
		var rot := rng.randf_range(0.0, TAU)
		_prop("dead_tree", x, z, rot, Vector3(1.0, h / 4.2, 1.0))


## 周界石墙：连续封闭（碰撞按段盒子，外观为乱石）
func _build_perimeter() -> void:
	var step := 12.0
	var sx := (step + 0.5) / 13.4
	var cx := -ARENA_X
	while cx <= ARENA_X:
		for z in [-ARENA_Z, ARENA_Z]:
			_col(Vector3(step + 0.5, 2.8, 2.8), Vector3(cx, 0, z), 0.0)
			_prop("rocks", cx, z, 0.0 if z < 0.0 else PI, Vector3(sx, 1.0, 1.0))
		cx += step
	var cz := -ARENA_Z
	while cz <= ARENA_Z:
		for x in [-ARENA_X, ARENA_X]:
			_col(Vector3(2.8, 2.8, step + 0.5), Vector3(x, 0, cz), 0.0)
			_prop("rocks", x, cz, PI * 0.5 if x < 0.0 else -PI * 0.5, Vector3(sx, 1.0, 1.0))
		cz += step
