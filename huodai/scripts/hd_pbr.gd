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
