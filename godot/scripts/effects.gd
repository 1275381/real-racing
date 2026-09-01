class_name RREffects
extends Node3D
## 持久胎痕（ImmediateMesh 增量写入，写满后清空重来）+ 轮胎烟雾/草地尘土/碰撞火花
## （移植自 js/effects.js 的核心行为）

const MAX_MARKS := 2400        # 胎痕四边形上限（环形写满后整体清空）
const MARK_W := 0.24

var _skid_mesh: ImmediateMesh
var _skid_mi: MeshInstance3D
var _skid_count := 0
var _last_pos := {}            # veh -> {Vector2 左后轮位置, Vector2 右后轮位置, bool ok}

var _spark: CPUParticles3D
var _pools := {}   # veh -> {"smoke": CPUParticles3D, "dust": CPUParticles3D}


func _ready() -> void:
	_skid_mesh = ImmediateMesh.new()
	_skid_mi = MeshInstance3D.new()
	_skid_mi.mesh = _skid_mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # 胎痕为程序化三角形，双面可见
	_skid_mi.material_override = mat
	_skid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_skid_mi)

	_spark = _make_sparks()
	add_child(_spark)


## 每物理帧调用：strength>0 时在该车两条后轮轨迹上续写胎痕
func emit_skid(veh: Vehicle, strength: float) -> void:
	var rec: Dictionary = _last_pos.get(veh, {})
	var rear := -1.44
	for side in [-0.84, 0.84]:
		var key := "l" if side < 0 else "r"
		var s := sin(veh.heading)
		var c := cos(veh.heading)
		var wp := Vector2(
				veh.pos.x + s * rear + c * side,
				veh.pos.z + c * rear - s * side)
		if strength <= 0.0 or veh.surface != "road":
			rec[key] = null
			continue
		var prev = rec.get(key)
		if prev != null and prev.distance_to(wp) > 0.35:
			_add_mark(prev, wp, strength, veh.pos.y + 0.045)
			rec[key] = wp
		elif prev == null:
			rec[key] = wp
	_last_pos[veh] = rec


func _add_mark(a: Vector2, b: Vector2, strength: float, y: float) -> void:
	if _skid_count >= MAX_MARKS:
		_skid_mesh.clear_surfaces()
		_skid_count = 0
	if _skid_count == 0:
		_skid_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var dir := (b - a).normalized()
	var side := Vector2(dir.y, -dir.x) * MARK_W
	var pa := a + side
	var pb := a - side
	var pc := b - side
	var pd := b + side
	var col := Color(0.05, 0.05, 0.06, 0.55 * strength)
	_skid_mesh.surface_set_color(col)
	for tri in [[pa, pb, pc], [pa, pc, pd]]:
		for v in tri:
			_skid_mesh.surface_add_vertex(Vector3(v.x, y, v.y))
	_skid_count += 1


func clear_skids() -> void:
	_skid_mesh.clear_surfaces()
	_skid_count = 0
	_last_pos.clear()


## 轮胎烟雾 + 离地尘土（每帧根据车况更新）
func surface_effects(veh: Vehicle) -> void:
	var smoke := _pool_get(veh, "smoke")
	var dust := _pool_get(veh, "dust")
	var drifting := veh.drifting and absf(veh.vf) > 6.0 and veh.surface == "road"
	smoke.emitting = drifting
	smoke.global_position = _rear_world(veh, 0.0)
	var dusty := veh.surface != "road" and absf(veh.vf) > 5.0
	dust.emitting = dusty
	dust.global_position = _rear_world(veh, 0.0)
	if dusty:
		var base := Color(0.55, 0.5, 0.4)
		match veh.surface:
			"grass":
				base = Color(0.45, 0.5, 0.3)
			"curb":
				base = Color(0.6, 0.58, 0.55)
		dust.color = base


func _rear_world(veh: Vehicle, side: float) -> Vector3:
	var s := sin(veh.heading)
	var c := cos(veh.heading)
	# 高度必须跟着车走：写死 0.25 时，高架上漂移的烟尘会掉到桥下的地面街道
	return Vector3(veh.pos.x + s * -1.7 + c * side, veh.pos.y + 0.25,
			veh.pos.z + c * -1.7 - s * side)


func _pool_get(veh: Vehicle, kind: String) -> CPUParticles3D:
	var rec: Dictionary = _pools.get(veh, {})
	if not rec.has(kind):
		var p: CPUParticles3D
		if kind == "smoke":
			p = _make_smoke()
		else:
			p = _make_dust()
		add_child(p)
		rec[kind] = p
		_pools[veh] = rec
	return rec[kind]


func car_bump(pos: Vector3) -> void:
	_burst(pos, Color(1.0, 0.85, 0.4), 14, 5.0)


func wall_sparks(pos: Vector3) -> void:
	_burst(Vector3(pos.x, 0.3, pos.z), Color(1.0, 0.7, 0.25), 22, 7.0)


func _burst(pos: Vector3, color: Color, count: int, speed: float) -> void:
	_spark.global_position = pos
	_spark.color = color
	_spark.amount = count
	_spark.initial_velocity_min = speed * 0.5
	_spark.initial_velocity_max = speed
	_spark.restart()
	_spark.emitting = true


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.8
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.8
	p.color = Color(0.75, 0.75, 0.78, 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	return p


func _make_dust() -> CPUParticles3D:
	var p := _make_smoke()
	p.amount = 18
	p.lifetime = 0.9
	p.color = Color(0.55, 0.5, 0.4, 0.45)
	p.scale_amount_max = 1.2
	return p


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22
	p.lifetime = 0.45
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.gravity = Vector3(0, -18.0, 0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.09
	p.color = Color(1.0, 0.75, 0.3)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.8, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.7, 0.3)
	mat.emission_energy_multiplier = 2.0
	mesh.material = mat
	p.mesh = mesh
	return p
