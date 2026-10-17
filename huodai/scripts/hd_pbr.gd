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
}

## 真实反照率系数：见 dress() 注释
const ALBEDO_REAL := 0.78

static var _cache := {}


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
