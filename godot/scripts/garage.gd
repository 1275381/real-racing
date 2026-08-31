class_name RRGarage
extends Node3D
## 车库展示场景：封闭展厅 + 旋转展台 + 顶灯，玩家车停在展台上供挑选
## 位于赛道世界下方 400m 的独立空间，不影响赛道渲染

const GARAGE_POS := Vector3(0, -400, 0)
const PLATFORM_TOP := 0.35
const ROOM_HALF := 13.0

var pivot: Node3D          # 展台旋转枢轴（平台 + 车随其转动）


func build() -> void:
	position = GARAGE_POS

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color("#272d38")
	wall_mat.roughness = 0.85
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#2b313c")
	floor_mat.metallic = 0.35
	floor_mat.roughness = 0.35

	# 地板
	var floor_mi := _box(Vector3(ROOM_HALF * 2.0, 0.5, ROOM_HALF * 2.0),
			Vector3(0, -0.25, 0), floor_mat)
	floor_mi.name = "Floor"
	# 四面墙 + 天花板（天花板投阴影，挡住外部阳光）
	for w in [
		[Vector3(0, 3, -ROOM_HALF), Vector3(ROOM_HALF * 2.0, 6, 0.5)],
		[Vector3(0, 3, ROOM_HALF), Vector3(ROOM_HALF * 2.0, 6, 0.5)],
		[Vector3(-ROOM_HALF, 3, 0), Vector3(0.5, 6, ROOM_HALF * 2.0)],
		[Vector3(ROOM_HALF, 3, 0), Vector3(0.5, 6, ROOM_HALF * 2.0)],
	]:
		var mi := _box(w[1], w[0], wall_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ceiling := _box(Vector3(ROOM_HALF * 2.0, 0.5, ROOM_HALF * 2.0),
			Vector3(0, 6.25, 0), wall_mat)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# 天花板灯带（自发光）
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color("#dfe8ff")
	strip_mat.emission_enabled = true
	strip_mat.emission = Color("#dfe8ff")
	strip_mat.emission_energy_multiplier = 2.6
	for sx in [-3.5, 3.5]:
		_box(Vector3(9.0, 0.08, 0.7), Vector3(sx, 5.9, 0), strip_mat)
	# 后墙装饰灯线
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color("#ff7a1a")
	line_mat.emission_enabled = true
	line_mat.emission = Color("#ff7a1a")
	line_mat.emission_energy_multiplier = 1.6
	_box(Vector3(20.0, 0.08, 0.06), Vector3(0, 4.4, -ROOM_HALF + 0.3), line_mat)

	# 后墙标语
	var sign := Label3D.new()
	sign.text = "GARAGE"
	sign.font = RRFont.get_font()
	sign.font_size = 200
	sign.pixel_size = 0.008
	sign.modulate = Color("#39445a")
	sign.outline_size = 0
	sign.position = Vector3(0, 3.4, -ROOM_HALF + 0.35)
	add_child(sign)
	var sign2 := Label3D.new()
	sign2.text = "极速争锋 · REAL RACING"
	sign2.font = RRFont.get_font()
	sign2.font_size = 64
	sign2.pixel_size = 0.008
	sign2.modulate = Color("#8a94a8")
	sign2.outline_size = 0
	sign2.position = Vector3(0, 2.0, -ROOM_HALF + 0.35)
	add_child(sign2)

	# 旋转展台
	pivot = Node3D.new()
	pivot.position = Vector3(0, 0, 0)
	add_child(pivot)
	var plat := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.6
	cyl.bottom_radius = 3.8
	cyl.height = PLATFORM_TOP
	var plat_mat := StandardMaterial3D.new()
	plat_mat.albedo_color = Color("#232730")
	plat_mat.metallic = 0.65
	plat_mat.roughness = 0.3
	cyl.material = plat_mat
	plat.mesh = cyl
	plat.position.y = PLATFORM_TOP / 2.0
	plat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(plat)
	# 发光环
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 3.72
	ring_mesh.bottom_radius = 3.72
	ring_mesh.height = 0.07
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("#35c8ff")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("#35c8ff")
	ring_mat.emission_energy_multiplier = 2.2
	ring_mesh.material = ring_mat
	ring.mesh = ring_mesh
	ring.position.y = 0.06
	pivot.add_child(ring)

	# 灯光：两盏顶灯斜打在车上 + 中央补光照明整个展厅
	for sx in [-3.2, 3.2]:
		var spot := SpotLight3D.new()
		spot.light_color = Color("#fff2dd")
		spot.light_energy = 18.0
		spot.spot_range = 26.0
		spot.spot_angle = 62.0
		spot.spot_attenuation = 1.2
		add_child(spot)
		spot.position = Vector3(sx, 5.6, sx * 0.4)
		spot.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.light_color = Color("#dfe6f2")
	fill.light_energy = 2.6
	fill.omni_range = 34.0
	fill.position = Vector3(0, 4.6, 0)
	add_child(fill)
	var warm := OmniLight3D.new()
	warm.light_color = Color("#cfdcff")
	warm.light_energy = 1.4
	warm.omni_range = 22.0
	warm.position = Vector3(0, 4.4, 5.0)
	add_child(warm)

	# 角落点缀：轮胎堆 + 工具柜
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color("#17181a")
	tire_mat.roughness = 0.95
	for stack_pos in [Vector3(-8.5, 0, -9.5), Vector3(-7.2, 0, -10.8)]:
		for tier in 3:
			var tire := MeshInstance3D.new()
			var tc := CylinderMesh.new()
			tc.top_radius = 0.66
			tc.bottom_radius = 0.66
			tc.height = 0.38
			tc.radial_segments = 18
			tc.material = tire_mat
			tire.mesh = tc
			tire.position = stack_pos + Vector3(0, 0.19 + tier * 0.38, 0)
			add_child(tire)
	var cab_mat := StandardMaterial3D.new()
	cab_mat.albedo_color = Color("#b0432e")
	cab_mat.roughness = 0.6
	cab_mat.metallic = 0.3
	_box(Vector3(3.2, 1.5, 1.0), Vector3(8.5, 0.75, -10.5), cab_mat)
	_box(Vector3(3.2, 0.06, 1.1), Vector3(8.5, 1.53, -10.5),
			StandardMaterial3D.new())

	# 车漆反射
	var probe := ReflectionProbe.new()
	probe.size = Vector3(24, 7, 24)
	probe.position = Vector3(0, 3.2, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.55
	add_child(probe)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
