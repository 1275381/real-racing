class_name NpcTraffic
extends Node3D
## 自由漫游 NPC：交通车辆（运动学巡航）+ 人行道行人（MultiMesh）+ 警察追捕。
## 性能优先：NPC 车与行人都不走全物理，只有位置推进 + 与玩家的圆形互推。

signal ped_hit              # 撞到行人（触发警察）
signal car_hit             # 实体模式下撞击 NPC 车（触发警察）
signal busted(fine: int)   # 被警察逮捕（game 扣罚金）
signal heli_fire           # 武装直升机开火（game 做镜头震动）
signal police_shot(dmg: float)   # 警察向步行玩家开枪（game 扣血）

const CAR_COUNT := 20
const POLICE_COUNT := 4
const POLICE_MAX := 6
const POLICE_TOP_SPEED := 62.0   # 警车极速硬上限（~223km/h）：无论玩家开多快都不超越
const PED_TARGET := 220
const SEDAN_COLORS := [
	Color("#d8d9dd"), Color("#b8bcc4"), Color("#23262c"), Color("#7d1f1f"),
	Color("#1f4f8a"), Color("#c9b26b"), Color("#3f7a4a"), Color("#e0e2e6"),
]
const PED_CLOTHES := [
	Color("#c33a2f"), Color("#2f5ac3"), Color("#3f7a4a"), Color("#d9a13b"),
	Color("#777d86"), Color("#8a5fb0"), Color("#e0e2e6"), Color("#33383f"),
]
const PED_SKIN := [
	Color("#e8b48c"), Color("#c98e63"), Color("#8a5a3a"), Color("#f0c9a2"),
]
const PED_PANTS := [
	Color("#2c3038"), Color("#3a4a63"), Color("#4a3a2c"), Color("#26292e"),
]
const PED_HAIR := [
	Color("#191410"), Color("#2e2117"), Color("#4a3a20"), Color("#6b4a2a"),
	Color("#b8a880"), Color("#8a8f96"), Color("#d8d4cc"),
]
const POLICE_FINE := 200

var fm                     # FreeroamMap
var hud                    # RRHud（通缉指示）
var solid := true          # NPC 车与玩家是否实体碰撞（车库开关）
var active := false

var cars: Array = []       # {r, idx, dir, speed, stop_t, hit_cd, pos, hp, disabled}
var peds: Array = []       # {origin, axis, off, dir, range, speed, dodge, dodge_sign, knock_t, phase, dead, pos}
var police: Array = []     # {vis, light_r, light_b, pos, speed, hp, last_idx, last, stuck}
var wanted := false
var player_on_foot := false
var escalated := false
var heli_fire_interval := 5.5
var police_respawn_cd := 0.0
var heli_active := false
var heli_dist := 999.0
var min_police_dist := 999.0
var heli_vis: Node3D
var heli_rotor: Node3D
var heli_spot: SpotLight3D
var heli_tracer: MeshInstance3D
var heli_angle := 0.0
var heli_fire_t := 0.0
var heli_q_t := 0.0
var heli_ground := 0.0
var _wanted_t := 0.0
var _esc_t := 0.0
var _bust_t := 0.0
var _t := 0.0
var _step := {}            # 道路采样间距缓存
var player_pos := Vector3.ZERO
var player_vel := Vector3.ZERO
var player_speed := 0.0
var _ped_mm_head: MultiMeshInstance3D
var _ped_mm_hair: MultiMeshInstance3D
var _ped_mm_skirt: MultiMeshInstance3D
var _ped_mm_torso: MultiMeshInstance3D
var _ped_mm_arm: MultiMeshInstance3D
var _ped_mm_leg: MultiMeshInstance3D
var _traffic_body: MultiMesh
var _traffic_wheel: MultiMesh


## 进入漫游时构建（freeroam 已 build）
func setup(freeroam, hud_ref) -> void:
	fm = freeroam
	hud = hud_ref
	for r in fm.roads.size():
		var pts: PackedVector3Array = fm.roads[r].pts
		if pts.size() >= 2:
			_step[r] = maxf(pts[0].distance_to(pts[1]), 0.5)
	_build_cars()
	_build_pedestrians()


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		_clear_wanted()
		hud.set_wanted(false, 0.0)


func set_solid(on: bool) -> void:
	solid = on


# ================= 交通车辆 =================

func _build_cars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260905
	# 低多边形民用车（车身+座舱 一体，轮组独立深色）——不是跑车模型
	var body_st := SurfaceTool.new()
	body_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := BoxMesh.new()
	body.size = Vector3(1.78, 0.52, 4.35)
	body_st.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)))
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.6, 0.5, 2.05)
	body_st.append_from(cabin, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.03, -0.28)))
	var body_mm := MultiMesh.new()
	body_mm.transform_format = MultiMesh.TRANSFORM_3D
	body_mm.use_colors = true
	body_mm.mesh = body_st.commit()
	body_mm.instance_count = CAR_COUNT   # 必须先分配实例数，否则 set_instance_transform 全部无效
	var wheel_st := SurfaceTool.new()
	wheel_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.31
	wheel.bottom_radius = 0.31
	wheel.height = 0.24
	var roll := Basis.from_euler(Vector3(0, 0, PI * 0.5))
	for wx in [-0.82, 0.82]:
		for wz in [-1.38, 1.38]:
			wheel_st.append_from(wheel, 0, Transform3D(roll, Vector3(wx, 0.31, wz)))
	var wheel_mm := MultiMesh.new()
	wheel_mm.transform_format = MultiMesh.TRANSFORM_3D
	wheel_mm.mesh = wheel_st.commit()
	wheel_mm.instance_count = CAR_COUNT
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.13, 0.13, 0.15)
	wheel_mm.mesh.surface_set_material(0, wmat)
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	body_mm.mesh.surface_set_material(0, bmat)
	var bmmi := MultiMeshInstance3D.new()
	bmmi.multimesh = body_mm
	bmmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(bmmi)
	var wmmi := MultiMeshInstance3D.new()
	wmmi.multimesh = wheel_mm
	wmmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(wmmi)
	_traffic_body = body_mm
	_traffic_wheel = wheel_mm
	for i in CAR_COUNT:
		var r := rng.randi_range(0, fm.roads.size() - 1)
		var pts: PackedVector3Array = fm.roads[r].pts
		body_mm.set_instance_color(i, SEDAN_COLORS[rng.randi_range(0, SEDAN_COLORS.size() - 1)])
		cars.append({
			"r": r, "idx": rng.randf_range(0.0, pts.size() - 2.0),
			"dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"speed": rng.randf_range(8.0, 14.0), "stop_t": 0.0, "hit_cd": 0.0,
			"hp": 4.0, "disabled": false,
		})
		_place_car(cars[i], true)


func _place_car(car: Dictionary, i: int, silent := false) -> void:
	var pts: PackedVector3Array = fm.roads[car["r"]].pts
	var i0 := clampi(int(floor(car["idx"])), 0, pts.size() - 2)
	var f: float = clampf(car["idx"] - float(i0), 0.0, 1.0)
	var p: Vector3 = pts[i0].lerp(pts[i0 + 1], f)
	var dir_f: float = car["dir"]
	var tv: Vector3 = (pts[i0 + 1] - pts[i0]).normalized() * dir_f
	var right := Vector2(tv.z, -tv.x)   # 行进方向右侧（靠右行驶）
	var pos := Vector3(p.x + right.x * 3.0, p.y, p.z + right.y * 3.0)
	var yaw := atan2(tv.x, tv.y)
	var xf := Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), pos)
	_traffic_body.set_instance_transform(i, xf)
	_traffic_wheel.set_instance_transform(i, xf)
	car["pos"] = pos


func _respawn_car_near_player(car: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for attempt in 12:
		var r := rng.randi_range(0, fm.roads.size() - 1)
		var pts: PackedVector3Array = fm.roads[r].pts
		var idx := rng.randf_range(0.0, pts.size() - 2.0)
		var p: Vector3 = pts[int(idx)]
		var d := Vector2(p.x - player_pos.x, p.z - player_pos.z).length()
		if d > 150.0 and d < 420.0:
			car["r"] = r
			car["idx"] = idx
			car["dir"] = 1.0 if rng.randf() < 0.5 else -1.0
			return


# ================= 行人 =================

func _build_pedestrians() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var spots := []   # {origin: Vector3, axis: Vector2, range: float}
	# 网格街人行道：中心线外 9.1m，交叉路口 13m 内跳过，两侧交替
	for r in fm.roads.size():
		var road = fm.roads[r]
		if not road.xsec_cut:
			continue
		var pts: PackedVector3Array = road.pts
		var k := maxi(1, roundi(14.0 / _step.get(r, 1.3)))
		var side := 1.0
		for i in range(0, pts.size(), k):
			var p := pts[i]
			var near_xing := false
			for c in FreeroamMap.GRID_COORDS:
				# 沿街轴向坐标：横街（along_x）随 x 变化，纵街随 z 变化
				var along: float = p.x if road.along_x else p.z
				if absf(along - c) < 13.0:
					near_xing = true
					break
			if near_xing:
				continue
			var l: Vector2 = road.left[i]
			var origin := Vector3(p.x + l.x * 9.1 * side, 0.23, p.z + l.y * 9.1 * side)
			var axis := Vector2(-l.y, l.x)   # 沿街方向
			spots.append({"origin": origin, "axis": axis, "range": 26.0})
			side = -side
	# 中心广场/配件店周边加密
	for i in 20:
		var a := rng.randf() * TAU
		var d := 16.0 + rng.randf() * 34.0
		var origin := Vector3(FreeroamMap.SHOP_POS.x + sin(a) * d, 0.05,
				FreeroamMap.SHOP_POS.y + cos(a) * d)
		var axis := Vector2(sin(a + PI * 0.5), cos(a + PI * 0.5))
		spots.append({"origin": origin, "axis": axis, "range": 22.0})
	while spots.size() > PED_TARGET:
		spots.remove_at(rng.randi_range(0, spots.size() - 1))
	# MultiMesh 完整人形：头 + 头发 + 身体 + 双臂 + 双腿 + 裙（每人 7 实例）
	# 圆柱四肢/锥形躯干替代方块，肤色头发/上衣/裤子/裙独立配色
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.125
	hair_mesh.height = 0.13
	var torso_mesh := CylinderMesh.new()
	torso_mesh.top_radius = 0.19
	torso_mesh.bottom_radius = 0.155
	torso_mesh.height = 0.62
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.065
	arm_mesh.bottom_radius = 0.055
	arm_mesh.height = 0.52
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.095
	leg_mesh.bottom_radius = 0.075
	leg_mesh.height = 0.82
	var skirt_mesh := CylinderMesh.new()
	skirt_mesh.top_radius = 0.17
	skirt_mesh.bottom_radius = 0.30
	skirt_mesh.height = 0.58
	_ped_mm_head = _make_ped_mm(head_mesh, spots.size())
	_ped_mm_hair = _make_ped_mm(hair_mesh, spots.size())
	_ped_mm_torso = _make_ped_mm(torso_mesh, spots.size())
	_ped_mm_arm = _make_ped_mm(arm_mesh, spots.size() * 2)
	_ped_mm_leg = _make_ped_mm(leg_mesh, spots.size() * 2)
	_ped_mm_skirt = _make_ped_mm(skirt_mesh, spots.size())
	var skirts: Array[bool] = []
	for s_i in spots.size():
		var shirt: Color = PED_CLOTHES[rng.randi_range(0, PED_CLOTHES.size() - 1)]
		var pants_c: Color = PED_PANTS[rng.randi_range(0, PED_PANTS.size() - 1)]
		var skin: Color = PED_SKIN[rng.randi_range(0, PED_SKIN.size() - 1)]
		var hair_c: Color = PED_HAIR[rng.randi_range(0, PED_HAIR.size() - 1)]
		var skirt: bool = rng.randf() < 0.35
		var skirt_c: Color = PED_CLOTHES[rng.randi_range(0, PED_CLOTHES.size() - 1)]
		_ped_mm_torso.multimesh.set_instance_color(s_i, shirt)
		_ped_mm_head.multimesh.set_instance_color(s_i, skin)
		_ped_mm_hair.multimesh.set_instance_color(s_i, hair_c)
		_ped_mm_arm.multimesh.set_instance_color(s_i * 2, shirt)
		_ped_mm_arm.multimesh.set_instance_color(s_i * 2 + 1, shirt)
		_ped_mm_leg.multimesh.set_instance_color(s_i * 2, pants_c)
		_ped_mm_leg.multimesh.set_instance_color(s_i * 2 + 1, pants_c)
		_ped_mm_skirt.multimesh.set_instance_color(s_i,
				skirt_c if skirt else Color(0, 0, 0, 0))
		skirts.append(skirt)
	for s in spots:
		peds.append({
			"origin": s["origin"], "axis": s["axis"],
			"off": rng.randf_range(-s["range"], s["range"]),
			"dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"range": s["range"], "speed": rng.randf_range(1.2, 1.6),
			"dodge": 0.0, "dodge_sign": 1.0, "knock_t": 0.0,
			"phase": rng.randf() * TAU, "dead": false, "pos": Vector3.ZERO,
			"skirt": skirts[peds.size()],
		})


func _make_ped_mm(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# ================= 警察 =================

func trigger_wanted() -> void:
	if wanted:
		return
	wanted = true
	_esc_t = 0.0
	_bust_t = 0.0
	for i in POLICE_COUNT:
		var ang := float(i) / float(POLICE_COUNT) * TAU + randf() * 0.5
		var px := player_pos.x + sin(ang) * 80.0
		var pz := player_pos.z + cos(ang) * 80.0
		var q: Dictionary = fm.query(px, pz, null, player_pos.y)
		var vis := CarVisual.create("gt3", Color(0.95, 0.95, 0.97), Color(0.08, 0.1, 0.14))
		add_child(vis)
		# 车顶红蓝警灯
		var light_r := _make_light(Color(1, 0.1, 0.1), vis, -0.22)
		var light_b := _make_light(Color(0.15, 0.3, 1), vis, 0.22)
		police.append({"vis": vis, "light_r": light_r, "light_b": light_b,
				"pos": Vector3(px, q["height"], pz), "speed": 24.0, "hp": 5.0,
				"last_idx": null, "last": Vector3.ZERO, "stuck": 0.0, "fire_cd": 0.0})
	_build_heli()
	hud.set_wanted(true, 0.0)


## 武装直升机：机体 + 主旋翼/尾桨 + 探照灯，盘旋在玩家上空定期开火
func _build_heli() -> void:
	heli_active = true
	heli_vis = Node3D.new()
	add_child(heli_vis)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.16, 0.30)
	var mid := StandardMaterial3D.new()
	mid.albedo_color = Color(0.16, 0.24, 0.42)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.75, 0.9, 0.7)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var add_box := func(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = pos
		heli_vis.add_child(mi)
		return mi
	add_box.call(Vector3(1.7, 1.5, 4.4), Vector3(0, 0, 0.4), mid)          # 机身
	add_box.call(Vector3(1.4, 1.0, 1.5), Vector3(0, 0.1, 1.9), glass)      # 座舱玻璃
	add_box.call(Vector3(0.34, 0.34, 3.6), Vector3(0, 0.35, -3.6), dark)   # 尾梁
	add_box.call(Vector3(0.12, 1.3, 0.9), Vector3(0, 0.9, -5.1), dark)     # 尾翼
	add_box.call(Vector3(0.1, 0.55, 0.16), Vector3(0.15, -1.0, -5.15), dark)  # 尾桨
	add_box.call(Vector3(0.12, 0.1, 3.2), Vector3(-0.8, -0.95, 0.3), dark)  # 橇
	add_box.call(Vector3(0.12, 0.1, 3.2), Vector3(0.8, -0.95, 0.3), dark)
	# 主旋翼（双叶十字，快速旋转）
	heli_rotor = Node3D.new()
	heli_rotor.position = Vector3(0, 1.05, 0.2)
	heli_vis.add_child(heli_rotor)
	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.14, 0.15, 0.18)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for blade_rot in [0.0, PI * 0.5]:
		var blade := BoxMesh.new()
		blade.size = Vector3(0.34, 0.05, 9.2)
		blade.material = rotor_mat
		var bmi := MeshInstance3D.new()
		bmi.mesh = blade
		bmi.rotation.y = blade_rot
		heli_rotor.add_child(bmi)
	# 探照灯（锥形光束打向玩家）
	heli_spot = SpotLight3D.new()
	heli_spot.spot_range = 55.0
	heli_spot.spot_angle = 16.0
	heli_spot.light_energy = 4.0
	heli_spot.light_color = Color(1.0, 0.97, 0.85)
	heli_spot.shadow_enabled = false
	heli_vis.add_child(heli_spot)
	# 开火曳光条（开火时短暂显示）
	heli_tracer = MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.08, 0.08, 1.0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 0.85, 0.3)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.75, 0.2)
	tmat.emission_energy_multiplier = 3.0
	tm.material = tmat
	heli_tracer.mesh = tm
	heli_tracer.visible = false
	add_child(heli_tracer)
	heli_angle = randf() * TAU
	heli_fire_t = 3.0


func _update_heli(dt: float) -> void:
	heli_angle += 0.5 * dt
	var radius := 26.0 + 7.0 * sin(_t * 0.3)
	var px := player_pos.x + sin(heli_angle) * radius
	var pz := player_pos.z + cos(heli_angle) * radius
	# 地面高度查询限频 0.4s（query 带空 hint 是全量扫描，每帧跑会拖垮帧率）
	heli_q_t += dt
	if heli_q_t > 0.4:
		heli_q_t = 0.0
		var q: Dictionary = fm.query(px, pz, null, player_pos.y)
		heli_ground = maxf(float(q["height"]), player_pos.y)
	heli_vis.position = Vector3(px, maxf(heli_ground + 26.0, player_pos.y + 24.0), pz)
	# 机头沿盘旋切线方向
	heli_vis.rotation.y = heli_angle + PI * 0.5
	heli_rotor.rotation.y += 42.0 * dt
	# 探照灯瞄准玩家
	heli_spot.look_at_from_position(heli_spot.global_position,
			Vector3(player_pos.x, player_pos.y + 0.8, player_pos.z), Vector3(1, 0, 0))
	heli_dist = heli_vis.position.distance_to(player_pos)
	# 开火：每 5.5 秒一轮 4 连发，曳光条指向玩家 + 信号给 game 做镜头震动
	heli_fire_t += dt
	if heli_fire_t > heli_fire_interval:
		var burst := fmod(heli_fire_t - heli_fire_interval, 0.12) < 0.05
		if heli_fire_t > heli_fire_interval + 0.5:
			heli_fire_t = 0.0
			heli_fire.emit()
			if player_on_foot:
				police_shot.emit(8.0)
		heli_tracer.visible = burst and heli_fire_t < 6.0
		if heli_tracer.visible:
			var from := heli_vis.global_position + Vector3(0, -1.2, 0)
			var to := player_pos + Vector3(0, 0.7, 0)
			var mid := (from + to) * 0.5
			var lenv := from.distance_to(to)
			heli_tracer.global_position = mid
			heli_tracer.look_at_from_position(mid, to, Vector3(1, 0, 0))
			heli_tracer.scale = Vector3(1, 1, lenv)
	else:
		heli_tracer.visible = false


func _make_light(col: Color, vis: Node3D, x_off: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.4
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.12, 0.24)
	box.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(x_off, 1.32, 0.05)
	vis.add_child(mi)
	return mi


func _clear_wanted() -> void:
	wanted = false
	_esc_t = 0.0
	_bust_t = 0.0
	heli_active = false
	heli_dist = 999.0
	min_police_dist = 999.0
	if heli_tracer != null:
		heli_tracer.visible = false
	for u in police:
		if u["vis"] != null and is_instance_valid(u["vis"]):
			u["vis"].queue_free()
	police.clear()
	if heli_vis != null and is_instance_valid(heli_vis):
		heli_vis.queue_free()


# ================= 每帧更新 =================

func update(dt: float) -> void:
	if not active:
		return
	_t += dt
	for i in cars.size():
		_update_car(cars[i], dt, i)
	_update_peds(dt)
	if wanted:
		_update_police(dt)
		_wanted_t += dt
		# _update_police 内可能本帧已逃脱/被捕（wanted 置 false），
		# 此时不能再回写「通缉中」横幅——否则字幕逃脱后永远残留
		if wanted:
			hud.set_wanted(true, _esc_t / 6.0)


func _update_car(car: Dictionary, dt: float, i: int) -> void:
	car["hit_cd"] = maxf(0.0, car["hit_cd"] - dt)
	var pts: PackedVector3Array = fm.roads[car["r"]].pts
	if car["stop_t"] > 0.0:
		car["stop_t"] -= dt
	else:
		car["idx"] += car["dir"] * car["speed"] * dt / float(_step.get(car["r"], 1.3))
	if car["idx"] > pts.size() - 1.5 or car["idx"] < -0.5:
		if fm.roads[car["r"]].closed:
			car["idx"] = posmod(car["idx"], float(pts.size() - 1))
		else:
			_respawn_car_near_player(car)
	var cpos: Vector3 = car["pos"]
	# LOD：250m 外只推进弧长不写变换（保持原姿态，远处看不出）
	if Vector2(cpos.x - player_pos.x, cpos.z - player_pos.z).length_squared() \
			> 250.0 * 250.0:
		return
	_place_car(car, i)
	# 与玩家实体碰撞：互推 + 被撞靠边停 3 秒
	if solid:
		var d := Vector2(cpos.x - player_pos.x, cpos.z - player_pos.z)
		var dist := d.length()
		if dist < 2.3 and dist > 0.01:
			var n := d / dist
			var push := 2.3 - dist
			player_pos.x += n.x * push * 0.6
			player_pos.z += n.y * push * 0.6
			cpos.x -= n.x * push * 0.4
			cpos.z -= n.y * push * 0.4
			car["pos"] = cpos
			_place_car(car, i)
			if car["hit_cd"] <= 0.0 and player_speed > 3.0:
				car["stop_t"] = 3.0   # 被撞后靠边停一会儿
				car["hit_cd"] = 1.0
				car_hit.emit()
				trigger_wanted()


func _update_peds(dt: float) -> void:
	var i := 0
	for ped in peds:
		if ped["knock_t"] > 0.0:
			ped["knock_t"] -= dt
		elif not ped["dead"]:
			ped["off"] += ped["dir"] * ped["speed"] * dt
			if absf(ped["off"]) > ped["range"]:
				ped["dir"] = -ped["dir"]
		# 躲车：玩家车接近且正在逼近 → 向行进路径外侧快步避让
		var axis: Vector2 = ped["axis"]
		var off: float = ped["off"]
		var base: Vector3 = ped["origin"] + Vector3(axis.x, 0, axis.y) * off
		ped["pos"] = Vector3(base.x, float(ped["origin"].y), base.z)
		var to_p := Vector2(base.x - player_pos.x, base.z - player_pos.z)
		var dist := to_p.length()
		var dodge: float = ped["dodge"]
		if ped["knock_t"] <= 0.0 and not ped["dead"] and dist < 9.0 and dist > 0.1:
			var vn := Vector2(player_vel.x, player_vel.z)
			if vn.length() > 2.0 and vn.normalized().dot(to_p / dist) > 0.4:
				var perp := Vector2(-vn.y, vn.x).normalized()
				ped["dodge_sign"] = signf(perp.dot(to_p / dist))
				dodge = move_toward(dodge, 1.8 * ped["dodge_sign"], dt * 3.0)
			else:
				dodge = move_toward(dodge, 0.0, dt * 2.0)
		else:
			dodge = move_toward(dodge, 0.0, dt * 2.0)
		ped["dodge"] = dodge
		# 撞到行人判定（廉价距离门合并进同一轮）
		var hit: bool = player_speed > 4.0 and ped["knock_t"] <= 0.0 \
				and base.distance_to(player_pos) < 1.5
		if hit:
			ped["knock_t"] = 2.5
			ped_hit.emit()
			trigger_wanted()
		# LOD：150m 内才写 6 个部件变换（远处保持姿态，肉眼不可辨）
		if to_p.length_squared() > 110.0 * 110.0:
			i += 1
			continue
		var dir_f: float = ped["dir"]
		var walk_dir := axis * dir_f
		var yaw := atan2(walk_dir.x, walk_dir.y)
		var dodge_v := Vector2(dodge, 0).rotated(atan2(axis.x, axis.y))
		var pos := Vector2(base.x, base.z) + dodge_v
		var walking: bool = ped["knock_t"] <= 0.0
		var phase: float = float(ped["phase"])
		var swing := sin(_t * 8.0 + phase) * 0.45 if walking else 0.0
		var bob := absf(sin(_t * 8.0 + phase)) * 0.04 if walking else 0.0
		# 根变换：位置 + 朝向（被撞倒地 → 绕 X 翻倒贴地）
		var root_pos := Vector3(pos.x, float(ped["origin"].y) + bob, pos.y)
		var root_rot := Vector3(PI * 0.5, yaw, 0) if not walking \
				else Vector3(0, yaw, tilt_sway(_t, phase))
		var root := Transform3D(Basis.from_euler(root_rot), root_pos)
		# 各部件：root × 肩/髋枢轴 × 摆动 × 偏移
		var hip_l := Transform3D(Basis.from_euler(Vector3(swing, 0, 0)), Vector3(-0.11, 0.83, 0))
		var hip_r := Transform3D(Basis.from_euler(Vector3(-swing, 0, 0)), Vector3(0.11, 0.83, 0))
		var sh_l := Transform3D(Basis.from_euler(Vector3(-swing * 0.7, 0, 0)), Vector3(-0.27, 1.40, 0))
		var sh_r := Transform3D(Basis.from_euler(Vector3(swing * 0.7, 0, 0)), Vector3(0.27, 1.40, 0))
		var leg_off := Transform3D(Basis.IDENTITY, Vector3(0, -0.41, 0))
		var arm_off := Transform3D(Basis.IDENTITY, Vector3(0, -0.26, 0))
		var mm_t: MultiMesh = _ped_mm_torso.multimesh
		var mm_h: MultiMesh = _ped_mm_head.multimesh
		var mm_a: MultiMesh = _ped_mm_arm.multimesh
		var mm_l: MultiMesh = _ped_mm_leg.multimesh
		mm_t.set_instance_transform(i, root * Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0)))
		mm_h.set_instance_transform(i, root * Transform3D(Basis.IDENTITY, Vector3(0, 1.58, 0)))
		_ped_mm_hair.multimesh.set_instance_transform(i,
				root * Transform3D(Basis.IDENTITY, Vector3(0, 1.67, 0)))
		var skirt_on: bool = ped.get("skirt", false)
		var sk := Transform3D(
				Basis.from_scale(Vector3.ONE
				* (1.0 if skirt_on else 0.001)),
				Vector3(0, 0.62, 0) if skirt_on else Vector3(0, -50, 0))
		_ped_mm_skirt.multimesh.set_instance_transform(i, root * sk)
		mm_a.set_instance_transform(i * 2, root * sh_l * arm_off)
		mm_a.set_instance_transform(i * 2 + 1, root * sh_r * arm_off)
		mm_l.set_instance_transform(i * 2, root * hip_l * leg_off)
		mm_l.set_instance_transform(i * 2 + 1, root * hip_r * leg_off)
		i += 1


func tilt_sway(t: float, phase: float) -> float:
	return sin(t * 9.0 + phase) * 0.06


func _update_police(dt: float) -> void:
	var min_d := INF
	_update_heli(dt)
	for u in police:
		var pos: Vector3 = u["pos"]
		var to_p := player_pos - pos
		to_p.y = 0.0
		var d := to_p.length()
		min_d = minf(min_d, d)
		# 追击动力：加速 16 m/s²，极速 165km/h 起步；随玩家车速水涨船高
		# （玩家车速 +2），但有硬上限 ~223km/h——顶配车直线全油门即可拉开。
		# 近身 20m 内收到「玩家速度 +6」，同样不破上限
		var chase_top: float = minf(maxf(46.0, player_speed + 2.0),
				POLICE_TOP_SPEED)
		u["speed"] = minf(float(u["speed"]) + 16.0 * dt, chase_top)
		if d < 20.0:
			u["speed"] = minf(float(u["speed"]),
					minf(player_speed + 6.0, POLICE_TOP_SPEED))
		var spd: float = u["speed"]
		if d > 2.0:
			pos += to_p / d * spd * dt
		var q: Dictionary = fm.query(pos.x, pos.z, u["last_idx"], pos.y)
		u["last_idx"] = q["idx"]
		pos.y = q["height"]
		# 与玩家恒为实体：互推 + 逮捕计时
		if d < 2.4 and d > 0.01:
			var n := to_p / d
			player_pos.x -= n.x * (2.4 - d) * 0.5
			player_pos.z -= n.y * (2.4 - d) * 0.5
			pos.x += n.x * (2.4 - d) * 0.5
			pos.z += n.y * (2.4 - d) * 0.5
		if not player_on_foot and d < 3.5 and player_speed < 3.0:
			_bust_t += dt
		# 步行玩家：60m 内警车开枪还击
		if player_on_foot and d < 60.0:
			u["fire_cd"] = maxf(0.0, float(u.get("fire_cd", 0.0)) - dt)
			if float(u["fire_cd"]) <= 0.0:
				u["fire_cd"] = 1.2
				var dmg := randf_range(6.0, 10.0)
				police_shot.emit(dmg)
		u["pos"] = pos
		var vis: Node3D = u["vis"]
		vis.position = pos
		# 车头指向行驶方向（原来误用被清零的 to_p.y，恒朝东西向=原地平移）
		vis.rotation.y = atan2(to_p.x, to_p.z)
		# 警灯交替闪烁
		var blink := int(_wanted_t * 4.0) % 2 == 0
		(u["light_r"] as MeshInstance3D).visible = blink
		(u["light_b"] as MeshInstance3D).visible = not blink
		# 卡死自救：按「速度 <1.5 m/s 持续 3 秒」判定 —— 原来按每帧位移 <1m
		# 判定，而 26 m/s 每帧只走 0.43m，正常追击也被误判成卡死无限重置
		var moved := (pos - (u["last"] as Vector3)).length()
		var spd_now := moved / maxf(dt, 0.001)
		u["stuck"] = 0.0 if spd_now > 1.5 else float(u["stuck"]) + dt
		u["last"] = pos
		if float(u["stuck"]) > 3.0 and d < 120.0:
			var ang := randf() * TAU
			u["pos"] = Vector3(player_pos.x + sin(ang) * 60.0, pos.y,
					player_pos.z + cos(ang) * 60.0)
			u["stuck"] = 0.0
	# 警车已全部清空（逃脱/脱离后）：不再驱动通缉横幅——否则空表 min_d=INF
	# 恒大于 180m，会把「通缉中」字幕重新刷出来（逃脱后字幕残留的根因）
	if police.is_empty():
		min_police_dist = 400.0
		return
	min_police_dist = min_d   # 每帧更新（供音效距离衰减），不受摆脱分支 return 影响
	# 被捕：贴身且玩家近乎停下，持续 1.5 秒
	if _bust_t > 1.5:
		_clear_wanted()
		hud.set_wanted(false, 0.0)
		busted.emit(POLICE_FINE)
		return
	# 摆脱：所有警车 >180m 持续 6 秒
	if min_d > 180.0:
		_esc_t += dt
		if _esc_t > 6.0:
			_clear_wanted()
			hud.set_wanted(false, 0.0)
			return
	else:
		_esc_t = 0.0
	hud.set_wanted(true, clampf(_esc_t / 6.0, 0.0, 1.0))
	min_police_dist = min_d


# ================= 射击命中（onfoot 步枪） =================

## 步枪射线：返回最近的命中 {"type": "ped"/"traffic"/"police"/"wall", "i", "point", "d"}
func raycast(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var best := {"type": "", "i": -1, "d": max_d, "point": from + dir * max_d}
	# 行人（胸口高度，半径 0.5）
	for i in peds.size():
		if peds[i].get("dead", false):
			continue
		var c: Vector3 = peds[i]["pos"] + Vector3(0, 1.05, 0)
		var t: float = (c - from).dot(dir)
		if t < 0.5 or t > best["d"]:
			continue
		var perp: float = (c - from - dir * t).length()
		if perp < 0.55:
			best = {"type": "ped", "i": i, "d": t, "point": from + dir * t}
	# 交通轿车（半径 1.45）
	for i in cars.size():
		if cars[i].get("disabled", false):
			continue
		var c: Vector3 = cars[i]["pos"] + Vector3(0, 0.6, 0)
		var t: float = (c - from).dot(dir)
		if t < 1.0 or t > best["d"]:
			continue
		var perp: float = (c - from - dir * t).length()
		if perp < 1.45:
			best = {"type": "traffic", "i": i, "d": t, "point": from + dir * t}
	# 警车（半径 1.45）
	for i in police.size():
		var c: Vector3 = police[i]["pos"] + Vector3(0, 0.6, 0)
		var t: float = (c - from).dot(dir)
		if t < 1.0 or t > best["d"]:
			continue
		var perp: float = (c - from - dir * t).length()
		if perp < 1.45:
			best = {"type": "police", "i": i, "d": t, "point": from + dir * t}
	# 楼房阻挡：沿射线 3m 步进检查点是否在 OBB 内
	var t2 := 2.0
	while t2 < best["d"]:
		var p: Vector3 = from + dir * t2
		for ob in fm.obstacles_box:
			var dx: float = p.x - ob["c"].x
			var dz: float = p.z - ob["c"].y
			if dx * dx + dz * dz > 8100.0:
				continue
			if p.y > 40.0:
				continue
			var ca: float = cos(ob["rot"])
			var sa: float = sin(ob["rot"])
			var lx: float = ca * dx + sa * dz
			var lz: float = -sa * dx + ca * dz
			if absf(lx) <= ob["hx"] and absf(lz) <= ob["hz"]:
				best = {"type": "wall", "i": -1, "d": t2, "point": p}
				t2 = best["d"] + 1.0
				break
		t2 += 3.0
	return best


## 步枪击杀行人（倒地不起）
func kill_ped(i: int) -> void:
	if i < 0 or i >= peds.size():
		return
	peds[i]["dead"] = true
	peds[i]["knock_t"] = 1.0e9
	trigger_wanted()


## 步枪伤害交通轿车：4 发打停（永久趴窝）
func damage_traffic(i: int, dmg: float) -> void:
	if i < 0 or i >= cars.size():
		return
	cars[i]["hp"] = float(cars[i]["hp"]) - dmg
	if cars[i]["hp"] <= 0.0 and not cars[i]["disabled"]:
		cars[i]["disabled"] = true
		cars[i]["stop_t"] = 1.0e9
	trigger_wanted()


## 步枪伤害警车：5 发击毁 → 通缉升级（补充至 6 台 + 直升机加速开火）
func damage_police(i: int, dmg: float) -> void:
	if i < 0 or i >= police.size():
		return
	police[i]["hp"] = float(police[i]["hp"]) - dmg
	if float(police[i]["hp"]) <= 0.0:
		var u: Dictionary = police[i]
		if u["vis"] != null and is_instance_valid(u["vis"]):
			u["vis"].queue_free()
		police.remove_at(i)
		escalate()


## 通缉升级：目标警车 4→6、直升机开火间隔 5.5→3.5s，立即补齐缺口
func escalate() -> void:
	if not wanted:
		trigger_wanted()
	escalated = true
	heli_fire_interval = 3.5
	while police.size() < POLICE_MAX:
		var ang := randf() * TAU
		var px := player_pos.x + sin(ang) * 60.0
		var pz := player_pos.z + cos(ang) * 60.0
		var q: Dictionary = fm.query(px, pz, null, player_pos.y)
		var vis := CarVisual.create("gt3", Color(0.95, 0.95, 0.97), Color(0.08, 0.1, 0.14))
		add_child(vis)
		var light_r := _make_light(Color(1, 0.1, 0.1), vis, -0.22)
		var light_b := _make_light(Color(0.15, 0.3, 1), vis, 0.22)
		police.append({"vis": vis, "light_r": light_r, "light_b": light_b,
				"pos": Vector3(px, q["height"], pz), "speed": 30.0, "hp": 5.0,
				"last_idx": null, "last": Vector3.ZERO, "stuck": 0.0, "fire_cd": 0.0})


## 交通车是否已趴窝（射线排除）
