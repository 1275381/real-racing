extends RefCounted
## 烽火地带 PBR 材质工具（美术写实化第一轮）：把代码场景里的纯色 / 噪声材质
## 「穿」上 Poly Haven CC0 实拍贴图（颜色 + 法线 + ARM 打包：AO/粗糙/金属），
## 世界坐标三平面投影——方块大小不一也按真实米数平铺，不拉伸不接缝。
##
## 用法：const PBR := preload("res://scripts/hd_pbr.gd")；PBR.dress(mat, "concrete")
## （按路径 preload、不注册 class_name：新 class_name 在另一台电脑的旧类缓存里
## 会让整个工程编不过，见 godot/scripts/loading_screen.gd 顶注）。
##
## 贴图走 Git LFS：另一台电脑没 git lfs pull 时文件是指针、导入失败——
## maps() 取不到就返回空，dress() 返回 false 且不改材质，画面回退到原纯色版，
## 绝不因缺资源崩游戏。

const TEX_DIR := "res://assets/pbr/tex/"

## kind → 贴图组。mode：tint = 中性贴图按原设计色着色（保持设计亮度）；
## natural = 贴图自带颜色（沙地/岩石），只按设计色的亮度调明暗。
## m = 贴图一个周期覆盖的真实米数；lum = 颜色贴图平均亮度（离线量得，做亮度补偿）
const KINDS := {
	"concrete": {"set": "concrete_layers_02", "m": 4.0, "mode": "tint", "lum": 0.48},
	"stucco": {"set": "cracked_concrete_wall", "m": 3.0, "mode": "tint", "lum": 0.689},
	"plaster": {"set": "beige_wall_001", "m": 2.0, "mode": "tint", "lum": 0.558},
	"corrugated": {"set": "corrugated_iron", "m": 2.5, "mode": "tint", "lum": 0.692},
	"container": {"set": "container_side", "diff": "container_side_gray_diff_1k.jpg",
			"m": 2.4, "mode": "tint", "lum": 0.4575},
	"paint_rust": {"set": "rusty_metal_02", "m": 2.0, "mode": "tint", "lum": 0.572},
	"steel_plate": {"set": "metal_plate", "m": 1.2, "mode": "natural", "lum": 0.199},
	"asphalt": {"set": "asphalt_02", "m": 4.0, "mode": "tint", "lum": 0.351},
	"sand": {"set": "gravelly_sand", "m": 2.5, "mode": "natural", "lum": 0.453},
	"rock": {"dir": "res://assets/pbr/models/boulder_01/textures/", "set": "boulder_01",
			"m": 3.0, "mode": "natural", "lum": 0.374},
	"bark": {"set": "bark_brown_02", "m": 1.5, "mode": "natural", "lum": 0.338},
	"brick": {"set": "brick_4", "m": 2.0, "mode": "tint", "lum": 0.459},
	"plaster_paint": {"set": "painted_plaster_wall", "m": 2.5, "mode": "tint", "lum": 0.644},
}

## 真实反照率系数：见 dress() 注释
const ALBEDO_REAL := 0.78

static var _cache := {}
static var _scenes := {}


## 取一组贴图 {diff, nor, arm}；任一缺失返回 {}（调用方保留原材质）
static func maps(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var k: Dictionary = KINDS.get(kind, {})
	var out := {}
	if not k.is_empty():
		var s: String = k["set"]
		var dir: String = k.get("dir", TEX_DIR + s + "/")
		var paths := {
			"diff": dir + str(k.get("diff", s + "_diff_1k.jpg")),
			"nor": dir + s + "_nor_gl_1k.jpg",
			"arm": dir + s + "_arm_1k.jpg",
		}
		for key in paths:
			var p: String = paths[key]
			var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
			if t == null:
				push_warning("[烽火地带] PBR 贴图缺失：%s（另一台电脑请 git lfs pull 后用编辑器导入）" % p)
				out = {}
				break
			out[key] = t
	_cache[kind] = out
	return out


## 给材质穿上 PBR 贴图。原 albedo_color 作为设计色：tint 模式按贴图平均亮度
## 补偿（整体明暗与原设计一致），natural 模式只取其亮度。meters<=0 用默认周期。
## 返回是否成功（贴图缺失 = false，材质原样不动）
static func dress(m: StandardMaterial3D, kind: String, meters := 0.0,
		normal_strength := 1.0) -> bool:
	var tx := maps(kind)
	if tx.is_empty() or m == null:
		return false
	var k: Dictionary = KINDS[kind]
	var tint: Color = m.albedo_color
	var lum: float = float(k["lum"])
	# 原设计色是在「纯色环境光、无全局光照」下调亮过的（混凝土 0.68 这类），
	# 换成实拍天空 + SDFGI 后整体发白——乘 ALBEDO_REAL 回到真实反照率区间
	if str(k["mode"]) == "tint":
		var g0 := ALBEDO_REAL / lum
		m.albedo_color = Color(minf(tint.r * g0, 2.0), minf(tint.g * g0, 2.0),
				minf(tint.b * g0, 2.0), tint.a)
	else:
		var tl := tint.get_luminance()
		var g := clampf(tl / lum * ALBEDO_REAL, 0.5, 1.4)
		m.albedo_color = Color(g, g, g, tint.a)
	m.albedo_texture = tx["diff"]
	m.normal_enabled = true
	m.normal_texture = tx["nor"]
	m.normal_scale = normal_strength
	m.ao_enabled = true
	m.ao_texture = tx["arm"]
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_light_affect = 0.4
	m.roughness_texture = tx["arm"]
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0
	m.metallic_texture = tx["arm"]
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.metallic = 1.0
	var period: float = meters if meters > 0.0 else float(k["m"])
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / period
	m.uv1_offset = Vector3.ZERO
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return true


## 新建一个已穿好贴图的材质（设计色 c）；贴图缺失时返回同色纯色材质
static func make(kind: String, c: Color, meters := 0.0, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	dress(m, kind, meters)
	return m


## 实拍/建模场景加载缓存（路径空或缺失返回 null，调用方回退原几何）。
## 首次加载时把叶片类材质（带透明的）统一改 alpha 剪切 + 双面：导出的
## 羽叶是半透明混合，远看会和天空排序错乱、近看发虚
static func scene(path: String) -> PackedScene:
	if path == "":
		return null
	if not _scenes.has(path):
		var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
		if ps == null:
			push_warning("[烽火地带] 模型缺失：%s（另一台电脑请 git lfs pull，暂用原几何）" % path)
		else:
			var probe: Node = ps.instantiate()
			for n in probe.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (n as MeshInstance3D).mesh
				for si in mesh.get_surface_count():
					var m := mesh.surface_get_material(si) as StandardMaterial3D
					if m != null and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						m.alpha_scissor_threshold = 0.5
						m.cull_mode = BaseMaterial3D.CULL_DISABLED
			probe.free()
		_scenes[path] = ps
	return _scenes[path]


## 场景里所有网格及其相对根的变换（给 MultiMesh 批量散布用）
static func meshes_of(ps: PackedScene) -> Array:
	var out := []
	var root: Node3D = ps.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var t := Transform3D()
		var q: Node = mi
		while q != root and q != null:
			if q is Node3D:
				t = (q as Node3D).transform * t
			q = q.get_parent()
		out.append({"mesh": mi.mesh, "xf": t})
	root.free()
	return out


## 写实玻璃：镀膜反射玻璃（幕墙/窗带）。原「暗蓝 metallic 0.6」在实拍
## 天空下读成蓝色塑料板；改成镜面暗玻璃后由 HDRI/SDFGI 反射出天与周边建筑
static func glass(m: StandardMaterial3D) -> void:
	# 镀膜幕墙玻璃：中灰蓝 + 全金属反射——正对时也能映出约 1/3 的天空与
	# 周边建筑（纯暗色镜面只在掠射角反光，正面读成一块黑板）
	m.albedo_color = Color(0.3, 0.36, 0.4)
	m.metallic = 1.0
	m.roughness = 0.05


static var _grime: Array = []


## 风化污迹贴图（程序生成，3 种变体）：墙顶滴水暗边 + 往下的雨水流挂竖条 +
## 墙脚泛起的沙土带，透明底。每张对应约 6 m 墙宽（长墙分段贴，条纹宽度才真实）
static func grime_tex(variant: int) -> Texture2D:
	if _grime.is_empty():
		for k in 3:
			_grime.append(_make_grime(20261017 + k * 97))
	return _grime[variant % _grime.size()]


static func _make_grime(seed_v: int) -> Texture2D:
	var w := 384
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.11
	var n2 := FastNoiseLite.new()
	n2.seed = seed_v + 3
	n2.frequency = 0.025
	var n3 := FastNoiseLite.new()
	n3.seed = seed_v + 5
	n3.frequency = 0.03
	for x in w:
		var col := clampf(n.get_noise_1d(float(x)) * 2.0 + 0.25, 0.0, 1.0)
		var length := 0.18 + 0.7 * clampf(n2.get_noise_1d(float(x)) + 0.5, 0.0, 1.0)
		for y in h:
			var v := float(y) / float(h)
			var a := 0.0
			if v < 0.035:
				a = 0.55   # 墙顶滴水暗边
			if v < length:
				a = maxf(a, col * pow(1.0 - v / length, 1.3) * 0.95)
			var foot := clampf((v - 0.84) / 0.16, 0.0, 1.0)   # 墙脚沙土带
			var foot_a := foot * foot * (0.55 + 0.3 * n3.get_noise_2d(float(x), float(y)))
			a *= 0.8 + 0.2 * n3.get_noise_2d(float(x) * 3.0, float(y) * 0.3)
			var c := Color(0.16, 0.14, 0.11, clampf(a, 0.0, 1.0))
			if foot_a > a:
				c = Color(0.46, 0.37, 0.25, clampf(foot_a, 0.0, 1.0))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 给一面墙（轴对齐盒：中心 c、尺寸 s）挂风化污迹贴花：只给「像墙」的盒
## （高 ≥2.5m、长 ≥3m、厚 ≤0.8m），沿墙面法线投影、两面都染；长墙按 ≤6m
## 分段、段间换变体。返回是否挂了
static func grime_decal(parent: Node3D, c: Vector3, s: Vector3) -> bool:
	var along_x := s.x >= s.z
	var length := s.x if along_x else s.z
	var thick := s.z if along_x else s.x
	if s.y < 2.5 or length < 3.0 or thick > 0.8:
		return false
	# 贴花沿本地 -Y 投影、纹理 V 沿本地 Z：绕 X 转 90° 让投影轴 = 墙法线、
	# 纹理竖向朝下（贴图第 0 行 = 墙顶）
	var basis := Basis(Vector3.RIGHT, PI * 0.5)
	var axis := Vector3.RIGHT
	if not along_x:
		basis = Basis(Vector3.UP, PI * 0.5) * basis
		axis = Vector3(0, 0, -1)
	var segs := int(ceil(length / 6.0))
	var seg_len := length / float(segs)
	for k in segs:
		var d := Decal.new()
		d.texture_albedo = grime_tex(int(absf(c.x * 3.0 + c.z * 7.0)) + k)
		d.size = Vector3(seg_len, thick + 0.6, s.y)
		d.normal_fade = 0.0
		d.upper_fade = 0.05
		d.lower_fade = 0.05
		d.cull_mask = 1
		var off := (float(k) + 0.5) * seg_len - length * 0.5
		d.transform = Transform3D(basis, c + axis * off)
		parent.add_child(d)
	return true


static var _trim: StandardMaterial3D
static var _plinth: StandardMaterial3D


## 收边材质（压顶/勒脚共用的混凝土，两档明度）
static func trim_mat(dark := false) -> StandardMaterial3D:
	if _trim == null:
		_trim = make("concrete", Color(0.58, 0.58, 0.56), 2.5)
		_plinth = make("concrete", Color(0.42, 0.41, 0.39), 2.0)
	return _plinth if dark else _trim


## 墙体浮雕（写实化第三轮：破「方块盒子」外形）。对落地的「像墙」的盒
## （高 ≥2.5m、长 ≥3m、厚 ≤0.8m）加：
##   勒脚——墙脚 0.6m 高混凝土基座，两面各外凸 5cm（墙不再直插沙地）；
##   压顶——墙顶 0.12m 混凝土压顶，两面各外挑 7cm（顶边有线脚）；
##   壁柱——两端 + 每 ~6m 一根 0.3m 宽结构柱，两面各外凸 10cm（转角成角柱）。
## 纯视觉，不登记碰撞（凸出 ≤10cm，不影响掩体与弹道判定）
static func relief(parent: Node3D, c: Vector3, s: Vector3, wall_mat: Material) -> bool:
	var along_x := s.x >= s.z
	var length := s.x if along_x else s.z
	var thick := s.z if along_x else s.x
	var bottom := c.y - s.y * 0.5
	if s.y < 2.5 or length < 3.0 or thick > 0.8 or bottom > 0.25:
		return false
	var top := c.y + s.y * 0.5
	var dims := func(l: float, h: float, t: float) -> Vector3:
		return Vector3(l, h, t) if along_x else Vector3(t, h, l)
	var axis := Vector3.RIGHT if along_x else Vector3(0, 0, 1)
	_trim_box(parent, Vector3(c.x, bottom + 0.3, c.z), dims.call(length + 0.02, 0.6, thick + 0.1),
			trim_mat(true))
	_trim_box(parent, Vector3(c.x, top + 0.06, c.z), dims.call(length + 0.1, 0.12, thick + 0.14),
			trim_mat())
	var n := maxi(1, int(round(length / 6.0)))
	for k in n + 1:
		var off := -length * 0.5 + 0.15 + (length - 0.3) * float(k) / float(n)
		_trim_box(parent, Vector3(c.x, c.y, c.z) + axis * off,
				dims.call(0.3, s.y, thick + 0.2), wall_mat)
	return true


static func _trim_box(parent: Node3D, p: Vector3, size: Vector3, m: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = p
	parent.add_child(mi)


# ================= Blender 建模建筑（美术写实化第四轮） =================

const BLDG_DIR := "res://assets/pbr/models/buildings/"
static var _named := {}


## 按 Blender 导出的材质名还原材质（tools/blender/bldg_kit.py 命名约定）：
##   pbr_<kind>_<r>_<g>_<b>_<周期×10> → make()（世界三平面 PBR，与代码场景同一套贴图）
##   plain_<r>_<g>_<b>_<粗糙>_<金属>  → 纯色；glass → 镀膜玻璃；lamp → 暖光灯罩
## 不认识的名字返回 null（保留导入材质）
static func named_mat(nm: String) -> Material:
	if _named.has(nm):
		return _named[nm]
	var m: Material = null
	var p := nm.split("_")
	var pct := func(i: int) -> float: return float(p[i].to_int()) / 100.0
	if nm == "glass":
		var g := StandardMaterial3D.new()
		glass(g)
		m = g
	elif nm == "lamp":
		var l := StandardMaterial3D.new()
		l.albedo_color = Color(1.0, 0.95, 0.84)
		l.emission_enabled = true
		l.emission = Color(1.0, 0.86, 0.62)
		l.emission_energy_multiplier = 1.5
		m = l
	elif nm.begins_with("pbr_") and p.size() >= 6:
		var n := p.size()
		var kind := "_".join(p.slice(1, n - 4))
		m = make(kind, Color(pct.call(n - 4), pct.call(n - 3), pct.call(n - 2)),
				float(p[n - 1].to_int()) / 10.0)
	elif nm.begins_with("plain_") and p.size() == 6:
		var s := StandardMaterial3D.new()
		s.albedo_color = Color(pct.call(1), pct.call(2), pct.call(3))
		s.roughness = pct.call(4)
		s.metallic = pct.call(5)
		m = s
	_named[nm] = m
	return m


## 给导入的建筑场景逐面换上按名还原的材质（surface override，不改共享资源）
static func apply_named(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			if src == null:
				continue
			var m := named_mat(src.resource_name)
			if m != null:
				mi.set_surface_override_material(si, m)


## 代码方块版建筑 → Blender 建模版：parent 下 [n0, 末尾) 是刚建好的旧可见层
## （墙/顶/门窗/贴花/浮雕），模型可用时整段释放、在 origin 摆上模型；
## 碰撞（obstacles）与点位由调用方照旧登记，不受影响。
## grime：[[x0, x1, z0, z1, y0, y1], …] 外墙风化贴花范围。
## 模型缺失（另一台电脑没 git lfs pull）返回 false，旧版原样保留
static func swap_building(parent: Node3D, n0: int, glb: String, origin: Vector3,
		grime: Array = []) -> bool:
	var ps := scene(BLDG_DIR + glb + ".glb")
	if ps == null:
		return false
	var olds: Array[Node] = []
	for i in range(n0, parent.get_child_count()):
		olds.append(parent.get_child(i))
	for n in olds:
		parent.remove_child(n)
		n.free()
	var inst: Node3D = ps.instantiate()
	inst.name = "bldg_" + glb
	inst.position = origin
	apply_named(inst)
	parent.add_child(inst)
	for g in grime:
		var r: Array = g
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var y0: float = r[4]
		var y1: float = r[5]
		var cy := (y0 + y1) * 0.5
		var hy := y1 - y0
		for wz in [z0 + 0.25, z1 - 0.25]:
			grime_decal(parent, Vector3((x0 + x1) * 0.5, cy, wz), Vector3(x1 - x0, hy, 0.5))
		for wx in [x0 + 0.25, x1 - 0.25]:
			grime_decal(parent, Vector3(wx, cy, (z0 + z1) * 0.5), Vector3(0.5, hy, z1 - z0))
	return true
