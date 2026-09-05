class_name NpcTraffic
extends Node3D
## 自由漫游 NPC：交通车辆（运动学巡航）+ 人行道行人（MultiMesh）+ 警察追捕。
## 性能优先：NPC 车与行人都不走全物理，只有位置推进 + 与玩家的圆形互推。

signal ped_hit              # 撞到行人（触发警察）
signal car_hit             # 实体模式下撞击 NPC 车（触发警察）
signal busted(fine: int)   # 被警察逮捕（game 扣罚金）

const CAR_COUNT := 20
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
const POLICE_FINE := 200

var fm                     # FreeroamMap
var hud                    # RRHud（通缉指示）
var solid := true          # NPC 车与玩家是否实体碰撞（车库开关）
var active := false

var cars: Array = []       # {vis, r, idx, dir, speed, stop_t, hit_cd}
var peds: Array = []       # {origin, axis, off, dir, range, speed, dodge: float, dodge_sign, knock_t, phase}
var police: Array = []     # {vis, light_r, light_b, pos, last_idx, last: Vector3, stuck: float}
var wanted := false
var _wanted_t := 0.0
var _esc_t := 0.0
var _bust_t := 0.0
var _t := 0.0
var _step := {}            # 道路采样间距缓存
var player_pos := Vector3.ZERO
var player_vel := Vector3.ZERO
var player_speed := 0.0
var _ped_mm_head: MultiMeshInstance3D
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
	# MultiMesh 完整人形：头 + 身体 + 双臂 + 双腿（每人 6 个实例）
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.42, 0.62, 0.24)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.11, 0.52, 0.13)
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.15, 0.82, 0.17)
	_ped_mm_head = _make_ped_mm(head_mesh, spots.size())
	_ped_mm_torso = _make_ped_mm(torso_mesh, spots.size())
	_ped_mm_arm = _make_ped_mm(arm_mesh, spots.size() * 2)
	_ped_mm_leg = _make_ped_mm(leg_mesh, spots.size() * 2)
	for s_i in spots.size():
		var shirt: Color = PED_CLOTHES[rng.randi_range(0, PED_CLOTHES.size() - 1)]
		var pants_c: Color = PED_PANTS[rng.randi_range(0, PED_PANTS.size() - 1)]
		var skin: Color = PED_SKIN[rng.randi_range(0, PED_SKIN.size() - 1)]
		_ped_mm_torso.multimesh.set_instance_color(s_i, shirt)
		_ped_mm_head.multimesh.set_instance_color(s_i, skin)
		_ped_mm_arm.multimesh.set_instance_color(s_i * 2, shirt)
		_ped_mm_arm.multimesh.set_instance_color(s_i * 2 + 1, shirt)
		_ped_mm_leg.multimesh.set_instance_color(s_i * 2, pants_c)
		_ped_mm_leg.multimesh.set_instance_color(s_i * 2 + 1, pants_c)
	for s in spots:
		peds.append({
			"origin": s["origin"], "axis": s["axis"],
			"off": rng.randf_range(-s["range"], s["range"]),
			"dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"range": s["range"], "speed": rng.randf_range(1.2, 1.6),
			"dodge": 0.0, "dodge_sign": 1.0, "knock_t": 0.0,
			"phase": rng.randf() * TAU,
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
	for i in 2:
		var ang := randf() * TAU
		var px := player_pos.x + sin(ang) * 80.0
		var pz := player_pos.z + cos(ang) * 80.0
		var q: Dictionary = fm.query(px, pz, null, player_pos.y)
		var vis := CarVisual.create("gt3", Color(0.95, 0.95, 0.97), Color(0.08, 0.1, 0.14))
		add_child(vis)
		# 车顶红蓝警灯
		var light_r := _make_light(Color(1, 0.1, 0.1), vis, -0.22)
		var light_b := _make_light(Color(0.15, 0.3, 1), vis, 0.22)
		police.append({"vis": vis, "light_r": light_r, "light_b": light_b,
				"pos": Vector3(px, q["height"], pz), "last_idx": null,
				"last": Vector3.ZERO, "stuck": 0.0})
	hud.set_wanted(true, 0.0)


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
	for u in police:
		u["vis"].queue_free()
	police.clear()


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
	_place_car(car, i)
	# 与玩家实体碰撞：互推 + 被撞靠边停 3 秒
	if solid:
		var cpos: Vector3 = car["pos"]
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
		else:
			ped["off"] += ped["dir"] * ped["speed"] * dt
			if absf(ped["off"]) > ped["range"]:
				ped["dir"] = -ped["dir"]
		# 躲车：玩家车接近且正在逼近 → 向行进路径外侧快步避让
		var axis: Vector2 = ped["axis"]
		var off: float = ped["off"]
		var base: Vector3 = ped["origin"] + Vector3(axis.x, 0, axis.y) * off
		var to_p := Vector2(base.x - player_pos.x, base.z - player_pos.z)
		var dist := to_p.length()
		var dodge: float = ped["dodge"]
		if ped["knock_t"] <= 0.0 and dist < 9.0 and dist > 0.1:
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
		mm_a.set_instance_transform(i * 2, root * sh_l * arm_off)
		mm_a.set_instance_transform(i * 2 + 1, root * sh_r * arm_off)
		mm_l.set_instance_transform(i * 2, root * hip_l * leg_off)
		mm_l.set_instance_transform(i * 2 + 1, root * hip_r * leg_off)
		i += 1
	# 撞到行人判定
	if player_speed > 4.0:
		for ped in peds:
			if ped["knock_t"] > 0.0:
				continue
			var axis2: Vector2 = ped["axis"]
			var base2: Vector3 = ped["origin"] + Vector3(axis2.x, 0, axis2.y) * float(ped["off"])
			if base2.distance_to(player_pos) < 1.5:
				ped["knock_t"] = 2.5
				ped_hit.emit()
				trigger_wanted()
				break


func tilt_sway(t: float, phase: float) -> float:
	return sin(t * 9.0 + phase) * 0.06


func _update_police(dt: float) -> void:
	var min_d := INF
	for u in police:
		var pos: Vector3 = u["pos"]
		var to_p := player_pos - pos
		to_p.y = 0.0
		var d := to_p.length()
		min_d = minf(min_d, d)
		var spd := 26.0 if d > 60.0 else 20.0
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
		if d < 3.5 and player_speed < 3.0:
			_bust_t += dt
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
