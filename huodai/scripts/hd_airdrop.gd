extends Node3D
## 烽火地带 —— 局内事件：空投（2026-10 改进方案第 6 节「第 10 分钟空投：烟雾信号 +
## 附近敌人增援」）。main 在局时到 AIRDROP_T 时 trigger(落点)：
##   落点立刻冒红色信号烟（远处 200 m 外就能看到烟柱）→ 空投箱挂降落伞从 80 m 伞降
##   （约 18 s）→ 落地后变成可搜的空投箱（HDLoot.add_airdrop：搜 4 s、紫色及以上 +
##   必带一件护甲板/医疗包/弹药盒）+ 召唤守军增援（HDSoldiers.call_reinforcements）
## 无 class_name（新脚本一律 preload，见记忆 godot-new-class-name-preload）

signal landed(pos: Vector3)

const SMOKE_AFTER := 120.0       # 落地后信号烟再冒这么久
const SWAY := 0.35               # 伞降左右摆幅（弧度）

var state := "idle"              # idle / falling / landed
var pos := Vector3.ZERO          # 落点（地面）
var _world
var _loot
var _soldiers
var _fall: Node3D                # 伞 + 箱（下落中的外观）
var _smoke: GPUParticles3D
var _t := 0.0
var _smoke_t := 0.0


func setup(world, loot, soldiers) -> void:
	_world = world
	_loot = loot
	_soldiers = soldiers
	_build_fall()
	_build_smoke()
	reset()


## 重开局：收起一切
func reset() -> void:
	state = "idle"
	_t = 0.0
	_smoke_t = 0.0
	_fall.visible = false
	_smoke.emitting = false
	_smoke.visible = false


## 投放：落点冒烟 + 箱子从 AIRDROP_H 开始伞降
func trigger(at: Vector3) -> void:
	pos = Vector3(at.x, _world.ground_height(at.x, at.z), at.z)
	state = "falling"
	_t = 0.0
	_fall.position = pos + Vector3(0.0, HDData.AIRDROP_H, 0.0)
	_fall.visible = true
	_smoke.position = pos + Vector3(2.5, 0.1, 1.5)
	_smoke.visible = true
	_smoke.emitting = true
	_smoke_t = 0.0


## 下落高度（地面以上米数；未投放返回 -1）
func height() -> float:
	if state != "falling":
		return -1.0
	return _fall.position.y - pos.y


func update(dt: float) -> void:
	if state == "idle":
		return
	_t += dt
	if state == "falling":
		_fall.position.y -= HDData.AIRDROP_FALL * dt
		_fall.rotation.z = sin(_t * 0.9) * SWAY * 0.25
		_fall.rotation.x = cos(_t * 0.7) * SWAY * 0.2
		if _fall.position.y <= pos.y + 0.02:
			_land()
	elif state == "landed":
		_smoke_t += dt
		if _smoke_t >= SMOKE_AFTER and _smoke.emitting:
			_smoke.emitting = false


func _land() -> void:
	state = "landed"
	_fall.visible = false
	_smoke_t = 0.0
	if _loot != null:
		_loot.add_airdrop(pos)
	if _soldiers != null:
		_soldiers.call_reinforcements(pos)
	landed.emit(pos)


# ================= 外观 =================

## 伞降外观：橄榄绿箱 + 橙白半球伞 + 4 根伞绳（下落时整体轻摆）
func _build_fall() -> void:
	_fall = Node3D.new()
	add_child(_fall)
	var crate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 1.0, 1.0)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.3, 0.36, 0.24)
	cm.roughness = 0.85
	bm.material = cm
	crate.mesh = bm
	crate.position = Vector3(0.0, 0.5, 0.0)
	_fall.add_child(crate)
	var chute := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.2
	sm.height = 1.9
	sm.is_hemisphere = true
	sm.radial_segments = 16
	sm.rings = 6
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.95, 0.5, 0.18)
	pm.roughness = 0.9
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.material = pm
	chute.mesh = sm
	chute.position = Vector3(0.0, 7.0, 0.0)
	_fall.add_child(chute)
	var cord_m := StandardMaterial3D.new()
	cord_m.albedo_color = Color(0.85, 0.85, 0.8)
	for k in 4:
		var a := PI * 0.25 + float(k) * PI * 0.5
		var top := Vector3(cos(a) * 2.9, 7.0, sin(a) * 2.9)
		var bot := Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.4)
		var cord := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = top.distance_to(bot)
		cyl.radial_segments = 4
		cyl.material = cord_m
		cord.mesh = cyl
		# 圆柱默认沿 +Y：用弧转四元数把 +Y 转到「箱角 → 伞缘」方向
		cord.transform = Transform3D(Basis(Quaternion(Vector3.UP, (top - bot).normalized())),
				(top + bot) * 0.5)
		_fall.add_child(cord)


## 红色信号烟：GPU 粒子公告板（径向渐变软边贴图），上升 + 侧风飘散 + 越飘越大越淡。
## 不用 CPUParticles3D：世界坐标公告板模式下它在发射点多画一块黑色圆片（探针实测，
## 停发射、粒子全死后仍在，且不受材质色影响）
func _build_smoke() -> void:
	_smoke = GPUParticles3D.new()
	_smoke.amount = 160
	_smoke.lifetime = 13.0
	_smoke.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 4.2
	pm.initial_velocity_max = 5.4
	pm.gravity = Vector3(0.9, 0.2, 0.35)   # 侧风 + 热烟上浮
	pm.damping_min = 0.22
	pm.damping_max = 0.32
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	pm.scale_min = 1.0
	pm.scale_max = 1.5
	var sc := Curve.new()
	sc.max_value = 8.0
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(0.2, 3.0))
	sc.add_point(Vector2(1.0, 7.5))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	# 信号烟：根部浓艳红橙 → 高处褪成淡粉灰并散开（远处 200 m 认得出一根红柱）
	var g := Gradient.new()
	g.set_color(0, Color(0.98, 0.18, 0.08, 1.0))
	g.set_color(1, Color(0.72, 0.5, 0.46, 0.0))
	g.add_point(0.25, Color(0.94, 0.26, 0.14, 0.9))
	g.add_point(0.65, Color(0.85, 0.42, 0.34, 0.45))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_smoke.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 1))
	tg.set_color(1, Color(1, 1, 1, 0))
	tg.add_point(0.45, Color(1, 1, 1, 0.75))   # 软边但芯子实：叠起来是一团烟而不是光点
	tex.gradient = tg
	mat.albedo_texture = tex
	quad.material = mat
	_smoke.draw_pass_1 = quad
	_smoke.visibility_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 80, 80))
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 烟不投影（否则地上一块黑斑）
	add_child(_smoke)
