class_name RREnvironment
extends Node3D
## 天空、光照、地形、树木、远山、云、岩石；set_theme 切换城市/沙漠/乡野外观
## （移植自 js/environment.js）

const SUN_DIR := Vector3(0.52, 0.46, 0.72)
var _sun_dir := SUN_DIR.normalized()

# 全地图统一蓝天：顶 #2f63b8 → 中 #6fa3dc → 地平线 #cfe3f3，雾色随地平线保证过渡自然
const SKY_TOP := Color("#2f63b8")
const SKY_MID := Color("#6fa3dc")
const SKY_BOT := Color("#a9cfec")   # 地平线偏蓝而非灰白（雾色同源联动）

const THEMES := {
	"country": {
		"sky_top": SKY_TOP, "sky_mid": SKY_MID, "sky_bot": SKY_BOT,
		"fog": SKY_BOT, "fog_near": 320.0, "fog_far": 2200.0,
		"mtn": Color("#7d93a8"), "ambient": Color("#bfd7ef"), "ground": 0.55,
	},
	"city": {
		"sky_top": SKY_TOP, "sky_mid": SKY_MID, "sky_bot": SKY_BOT,
		"fog": SKY_BOT, "fog_near": 240.0, "fog_far": 1650.0,
		"mtn": Color("#69707a"), "ambient": Color("#c4cdd6"), "ground": 0.55,
	},
	"desert": {
		"sky_top": SKY_TOP, "sky_mid": SKY_MID, "sky_bot": SKY_BOT,
		"fog": SKY_BOT, "fog_near": 300.0, "fog_far": 2000.0,
		"mtn": Color("#b06f48"), "ambient": Color("#dce6f2"), "ground": 0.6,
	},
}

var sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _env: Environment
var _ground: MeshInstance3D
var _ground_mats := {}
var _mtn_mat: StandardMaterial3D
var _mtn_mmi: MultiMeshInstance3D
var _mesa_mat: StandardMaterial3D
var _trees: Array[Node3D] = []
var _buildings: Node3D
var _desert_props: Node3D
var _clouds: Array[Sprite3D] = []
var _rng := RRUtil.Mulberry.new(2024)


func build(tracks: Array[RaceTrack]) -> void:
	# ---- 天空穹顶 ----
	_sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
// 天空球不参与深度雾（render_mode 缺省会被 4200m 外的深度雾糊成雾色）
shader_type spatial;
render_mode cull_front, unshaded, fog_disabled;

uniform vec3 top_color : source_color = vec3(0.184, 0.388, 0.722);
uniform vec3 mid_color : source_color = vec3(0.525, 0.682, 0.871);
uniform vec3 bot_color : source_color = vec3(0.875, 0.914, 0.933);
uniform vec3 sun_dir = vec3(0.52, 0.42, 0.74);
uniform vec3 sun_color : source_color = vec3(1.0, 0.945, 0.839);

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	float h = clamp(v_dir.y, -1.0, 1.0);
	vec3 col;
	if (h > 0.12) {
		col = mix(mid_color, top_color, pow((h - 0.12) / 0.88, 0.72));
	} else {
		col = mix(bot_color, mid_color, clamp((h + 0.06) / 0.18, 0.0, 1.0));
	}
	float sd = max(dot(normalize(v_dir), normalize(sun_dir)), 0.0);
	col += sun_color * (pow(sd, 900.0) * 1.15 + pow(sd, 26.0) * 0.16);
	ALBEDO = col;
}
"""
	_sky_mat.shader = sh
	_sky_mat.set_shader_parameter("sun_dir", Vector3(0.52, 0.42, 0.74))
	var sky := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 4200.0
	sphere.height = 8400.0
	sphere.radial_segments = 32
	sphere.rings = 16
	sphere.material = _sky_mat
	sky.mesh = sphere
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)

	# ---- 光照 ----
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#fff2dd")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 800.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.0
	sun.shadow_opacity = 0.68   # 阴影柔和化：阴影里保留散射光，路面不会黑成一团
	add_child(sun)

	# ---- 环境雾 / 环境光 / 色调映射（网页版为 ACES，Godot 默认 Linear 会过曝）----
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_sky_affect = 0.0   # 深度雾不遮天空：4200m 天空球远超雾终点，否则整片天被雾色糊白
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	# ---- 地面（三种主题材质）----
	for theme_name in ["country", "city", "desert"]:
		var m := StandardMaterial3D.new()
		match theme_name:
			"country":
				m.albedo_texture = RRTextures.grass()
				m.albedo_color = Color("#bfcfb2")
			"city":
				m.albedo_texture = RRTextures.concrete()
			"desert":
				m.albedo_texture = RRTextures.sand()
		m.roughness = 1.0
		m.uv1_scale = Vector3(150, 150, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_ground_mats[theme_name] = m
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6500, 6500)
	plane.material = _ground_mats["country"]
	_ground.mesh = plane
	_ground.position.y = -0.15
	add_child(_ground)

	# ---- 远山剪影 ----
	# 半径 1250~1800 只够作为赛道背景；漫游城市延伸到 ±1080、可行驶到 1250m，
	# 高架环线会直接插进山体 —— 漫游时整组隐藏（见 set_race_props_visible）
	_mtn_mat = StandardMaterial3D.new()
	_mtn_mat.albedo_color = Color("#7d93a8")
	_mtn_mat.roughness = 1.0
	_mtn_mmi = _multi_mesh(_cone_mesh(1.0, 1.0, 7, _mtn_mat), 14, false)
	var mtn := _mtn_mmi.multimesh
	for i in 14:
		var a := float(i) / 14.0 * PI * 2.0 + _rng.next() * 0.4
		var r := 1250.0 + _rng.next() * 550.0
		var hgt := 150.0 + _rng.next() * 190.0
		var sx := 280.0 + _rng.next() * 320.0
		var sz := 280.0 + _rng.next() * 320.0
		var pos := Vector3(cos(a) * r, hgt * 0.28 - 18.0, sin(a) * r)
		var q := Quaternion(Vector3.UP, _rng.next() * 3.0)
		mtn.set_instance_transform(i, Transform3D(
			Basis(q).scaled(Vector3(sx, hgt, sz)), pos))

	# ---- 树木（避开所有赛道）----
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color("#6e4a2c")
	trunk_mat.roughness = 0.95
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color.WHITE
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 0.9
	var trunk_geo := CylinderMesh.new()
	trunk_geo.top_radius = 0.42
	trunk_geo.bottom_radius = 0.62
	trunk_geo.height = 3.4
	trunk_geo.radial_segments = 6
	trunk_geo.material = trunk_mat
	var leaf_geo := CylinderMesh.new()
	leaf_geo.top_radius = 0.001
	leaf_geo.bottom_radius = 2.9
	leaf_geo.height = 7.6
	leaf_geo.radial_segments = 8
	leaf_geo.material = leaf_mat
	var COUNT := 190
	var trunks_mmi := _multi_mesh(trunk_geo, COUNT, false)
	var leaves_mmi := _multi_mesh(leaf_geo, COUNT, false)   # 消融实验：不用实例颜色
	var trunks := trunks_mmi.multimesh
	var leaves := leaves_mmi.multimesh
	var placed := 0
	var guard := 0
	while placed < COUNT and guard < 6000:
		guard += 1
		var x := -750.0 + _rng.next() * 1500.0
		var z := -800.0 + _rng.next() * 1550.0
		if not _clear_of_all(tracks, x, z, 16.0):
			continue
		var sc := 0.75 + _rng.next() * 0.85
		var basis := Basis(Quaternion(Vector3.UP, _rng.next() * 6.28)).scaled(
				Vector3(sc, sc * (0.9 + _rng.next() * 0.5), sc))
		var xf := Transform3D(basis, Vector3(x, 0, z))
		trunks.set_instance_transform(placed, xf)
		leaves.set_instance_transform(placed, xf)
		placed += 1
	trunks.visible_instance_count = placed
	leaves.visible_instance_count = placed
	_trees = [trunks_mmi, leaves_mmi]

	# ---- 岩石点缀 ----
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color("#8d8d88")
	rock_mat.roughness = 1.0
	var rock_geo := SphereMesh.new()
	rock_geo.radius = 1.15
	rock_geo.height = 2.3
	rock_geo.radial_segments = 6
	rock_geo.rings = 3
	rock_geo.material = rock_mat
	var rocks_mmi := _multi_mesh(rock_geo, 42, true)
	_rocks_mmi = rocks_mmi
	var rocks := rocks_mmi.multimesh
	for i in 42:
		var x := 0.0
		var z := 0.0
		var tries := 0
		while true:
			x = -700.0 + _rng.next() * 1400.0
			z = -760.0 + _rng.next() * 1470.0
			tries += 1
			if _clear_of_all(tracks, x, z, 13.0) or tries >= 50:
				break
		var sc := Vector3(0.6 + _rng.next() * 1.8, 0.5 + _rng.next() * 1.1, 0.6 + _rng.next() * 1.8)
		var axis := Vector3(_rng.next() * 2.0 - 1.0, 1.0, _rng.next() * 2.0 - 1.0).normalized()
		var xf := Transform3D(Basis(Quaternion(axis, _rng.next() * 3.0)).scaled(sc),
				Vector3(x, sc.y * 0.3, z))
		rocks.set_instance_transform(i, xf)

	# ---- 城市楼宇（沿 city 赛道走廊）----
	_buildings = Node3D.new()
	_buildings.visible = false
	add_child(_buildings)
	var b_tex := RRTextures.building()
	for trk in tracks:
		if trk.theme != "city":
			continue
		var step: int = maxi(5, roundi(trk.n / 42.0))
		var placed_b := 0
		var guard_b := 0
		while placed_b < 84 and guard_b < 400:
			guard_b += 1
			var i := posmod(guard_b * step, trk.n)
			var side := 1.0 if guard_b % 2 == 0 else -1.0
			var off := 17.0 + _rng.next() * 30.0
			var x: float = trk.pts[i].x - trk.left_v[i].x * off * side
			var z: float = trk.pts[i].y - trk.left_v[i].y * off * side
			if not _clear_of_all(tracks, x, z, 13.0):
				continue
			var w := 9.0 + _rng.next() * 11.0
			var d := 9.0 + _rng.next() * 11.0
			var h := 9.0 + pow(_rng.next(), 1.6) * 34.0
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(w, h, d)
			var bmat := StandardMaterial3D.new()
			bmat.albedo_texture = b_tex
			bmat.roughness = 0.85
			var tint: Color = [Color(1, 1, 1), Color("#c9ccd2"), Color("#aeb2a8")][placed_b % 3]
			bmat.albedo_color = tint
			bm.material = bmat
			b.mesh = bm
			b.position = Vector3(x, h / 2.0, z)
			b.rotation.y = _rng.next() * PI
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_buildings.add_child(b)
			placed_b += 1

	# ---- 沙漠道具：三针仙人掌 + 红岩平顶山 ----
	_desert_props = Node3D.new()
	_desert_props.visible = false
	add_child(_desert_props)
	var cac_mat := StandardMaterial3D.new()
	cac_mat.albedo_color = Color("#4e7c3a")
	cac_mat.roughness = 0.9
	var cac_geos: Array[CylinderMesh] = []
	var cac_locals: Array[Transform3D] = []
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.38
	trunk.height = 2.8
	trunk.radial_segments = 8
	trunk.material = cac_mat
	cac_geos.append(trunk)
	cac_locals.append(Transform3D(Basis(), Vector3(0, 1.4, 0)))
	var a1 := CylinderMesh.new()
	a1.top_radius = 0.18
	a1.bottom_radius = 0.2
	a1.height = 1.2
	a1.radial_segments = 7
	a1.material = cac_mat
	cac_geos.append(a1)
	cac_locals.append(Transform3D(Basis(Quaternion(Vector3(0, 0, 1), 0.9)), Vector3(0.55, 2.05, 0)))
	var a2 := CylinderMesh.new()
	a2.top_radius = 0.18
	a2.bottom_radius = 0.2
	a2.height = 1.0
	a2.radial_segments = 7
	a2.material = cac_mat
	cac_geos.append(a2)
	cac_locals.append(Transform3D(Basis(Quaternion(Vector3(0, 0, 1), -1.1)), Vector3(-0.5, 2.35, 0)))
	var cacti_mms: Array[MultiMesh] = []
	for gi in cac_geos.size():
		var cac_mmi := _multi_mesh(cac_geos[gi], 46, true)
		cac_mmi.reparent(_desert_props)   # 挂进主题容器，跟随 set_theme 显隐
		cacti_mms.append(cac_mmi.multimesh)
	for i in 46:
		var x := 0.0
		var z := 0.0
		var tries := 0
		while true:
			x = -700.0 + _rng.next() * 1400.0
			z = -760.0 + _rng.next() * 1470.0
			tries += 1
			if _clear_of_all(tracks, x, z, 14.0) or tries >= 50:
				break
		var sc := 0.7 + _rng.next() * 1.1
		var base := Transform3D(
				Basis(Quaternion(Vector3.UP, _rng.next() * 6.28)).scaled(
						Vector3(sc, sc * (0.85 + _rng.next() * 0.5), sc)),
				Vector3(x, 0, z))
		for gi in cacti_mms.size():
			cacti_mms[gi].set_instance_transform(i, base * cac_locals[gi])

	_mesa_mat = StandardMaterial3D.new()
	_mesa_mat.albedo_color = Color("#b06f48")
	_mesa_mat.roughness = 1.0
	var mesa_geo := CylinderMesh.new()
	mesa_geo.top_radius = 0.62
	mesa_geo.bottom_radius = 1.0
	mesa_geo.height = 1.0
	mesa_geo.radial_segments = 8
	mesa_geo.material = _mesa_mat
	var mesa_mmi := _multi_mesh(mesa_geo, 12, false)
	mesa_mmi.reparent(_desert_props)   # 同上：原挂在根节点下，城市/乡野主题里也常驻可见
	var mesas := mesa_mmi.multimesh
	for i in 12:
		var a := float(i) / 12.0 * PI * 2.0 + _rng.next() * 0.5
		var r := 620.0 + _rng.next() * 320.0
		var hgt := 42.0 + _rng.next() * 60.0
		var sc := Vector3(120.0 + _rng.next() * 160.0, hgt, 120.0 + _rng.next() * 160.0)
		var xf := Transform3D(
				Basis(Quaternion(Vector3.UP, _rng.next() * 3.0)).scaled(sc),
				Vector3(cos(a) * r, hgt * 0.42, sin(a) * r))
		mesas.set_instance_transform(i, xf)

	# ---- 云朵 ----
	for i in 14:
		var sp := Sprite3D.new()
		sp.texture = RRTextures.cloud()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.transparent = true
		sp.shaded = false
		sp.modulate = Color(1, 1, 1, 0.62)
		sp.pixel_size = 1.4 + _rng.next() * 0.6
		sp.position = Vector3(-1600.0 + _rng.next() * 3200.0,
				360.0 + _rng.next() * 260.0, -1600.0 + _rng.next() * 3200.0)
		sp.set_meta("speed", 1.5 + _rng.next() * 2.5)
		add_child(sp)
		_clouds.append(sp)


func _cone_mesh(radius: float, height: float, segments: int, mat: Material) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.001
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.material = mat
	return m


func _multi_mesh(geo: Mesh, count: int, with_colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = with_colors
	mm.mesh = geo
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	return mmi


func _clear_of_all(tracks: Array[RaceTrack], x: float, z: float, d: float) -> bool:
	for t in tracks:
		if not t.is_clear_of_road(x, z, d):
			return false
	return true


var _rocks_mmi: MultiMeshInstance3D
var _race_props_on := true   # false 时隐藏比赛专用道具（漫游模式用）
var _cur_theme := "country"


## 漫游模式：隐藏比赛赛道走廊楼宇与岩石（避免与漫游城市重叠）
func set_race_props_visible(v: bool) -> void:
	_race_props_on = v
	_buildings.visible = v and _cur_theme == "city"
	if _rocks_mmi != null:
		_rocks_mmi.visible = v
	if _mtn_mmi != null:
		_mtn_mmi.visible = v   # 远山环在漫游城市范围内，留着必穿模


## 全局地面显隐（自由漫游用自己的分区地面，隐藏全局面避免深度冲突）
func set_ground_visible(v: bool) -> void:
	if _ground != null:
		_ground.visible = v


## 大世界雾距调整（自由漫游用：世界扩大后默认雾距会吞掉远景）
func set_fog_range(near: float, far: float) -> void:
	_env.fog_depth_begin = near
	_env.fog_depth_end = far


func set_theme(name: String) -> void:
	var t: Dictionary = THEMES.get(name, THEMES["country"])
	_cur_theme = name
	var ground_mesh := _ground.mesh as PlaneMesh
	ground_mesh.material = _ground_mats[name]
	_sky_mat.set_shader_parameter("top_color", t["sky_top"])
	_sky_mat.set_shader_parameter("mid_color", t["sky_mid"])
	_sky_mat.set_shader_parameter("bot_color", t["sky_bot"])
	_env.fog_light_color = t["fog"]
	_env.fog_depth_begin = t["fog_near"]
	_env.fog_depth_end = t["fog_far"]
	_env.ambient_light_color = t["ambient"]
	_env.ambient_light_energy = 0.65
	_mtn_mat.albedo_color = t["mtn"]
	_mesa_mat.albedo_color = Color("#b06f48") if name == "desert" else Color("#8a7a68")
	for tree_node in _trees:
		tree_node.visible = name == "country"
	_buildings.visible = (name == "city") and _race_props_on
	_rocks_mmi.visible = _race_props_on
	_desert_props.visible = name == "desert"


## 阴影相机跟随玩家（保证阴影分辨率集中在玩家周围）
func follow_shadow(target_pos: Vector3) -> void:
	# 按 shadow-texel 尺寸对齐：消除光源逐帧爬行导致的路面阴影抖动
	var snap_size := sun.directional_shadow_max_distance * 2.0 / 2048.0
	var snapped := Vector3(
		roundf(target_pos.x / snap_size) * snap_size,
		target_pos.y,
		roundf(target_pos.z / snap_size) * snap_size
	)
	sun.position = snapped + _sun_dir * 230.0
	sun.look_at(snapped, Vector3.UP)


func update_clouds(dt: float) -> void:
	for c in _clouds:
		c.position.x += float(c.get_meta("speed")) * dt
		if c.position.x > 1800.0:
			c.position.x = -1800.0
