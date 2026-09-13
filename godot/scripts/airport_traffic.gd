class_name AirportTraffic
extends Node3D
## 机场繁忙氛围：客机登机→滑行→起飞爬升循环 + 航站楼→舷梯的登机人流。
## 纯氛围实体（不进路网、不参与战斗），每个机场独立循环。

const PLANE_ACCEL := 3.4       # 起飞滑跑加速度 m/s²
const ROTATE_SPEED := 72.0     # 抬轮速度 m/s
const CLIMB_SPEED := 118.0     # 爬升段速度
const PLANES_PER_AIRPORT := 3  # 同时循环的客机数
const WALKERS_PER_AIRPORT := 8 # 登机人流数

var airports: Array = []
var _t := 0.0


func setup(spots: Array) -> void:
	for s in spots:
		var origin: Vector2 = s["origin"]
		var heading: float = float(s["heading"])
		var fwd := Vector2(sin(heading), cos(heading))
		var right := Vector2(cos(heading), -sin(heading))
		var base_y := _ground_y(origin) + 0.1
		var ap := {
			"origin": origin, "heading": heading,
			"fwd": fwd, "right": right, "base_y": base_y,
			"planes": [], "mm": {}, "walkers": [], "gate_i": 0,
		}
		for i in PLANES_PER_AIRPORT:
			ap["planes"].append(_make_plane(ap, i))
		ap["mm"] = _setup_walkers_mm(ap, WALKERS_PER_AIRPORT)
		for i in WALKERS_PER_AIRPORT:
			ap["walkers"].append(_make_walker(ap, i))
		airports.append(ap)


func update(dt: float) -> void:
	_t += dt
	for ap in airports:
		for p in ap["planes"]:
			_update_plane(ap, p, dt)
		_update_walkers(ap, dt)


func _ground_y(origin: Vector2) -> float:
	var fm = get_parent()
	if fm != null and fm.has_method("terrain_height"):
		return float(fm.terrain_height(origin.x, origin.y))
	return 0.0


## ================= 客机（登机→滑行→起飞→爬升→循环） =================

func _make_plane(ap: Dictionary, i: int) -> Dictionary:
	var vis := _build_airliner(Color(0.92, 0.93, 0.95),
			[Color(0.75, 0.2, 0.16), Color(0.16, 0.34, 0.6),
			Color(0.95, 0.62, 0.1)][i % 3])
	vis.visible = false
	add_child(vis)
	return {
		"vis": vis, "pos": Vector3.ZERO, "heading": float(ap["heading"]),
		"pitch": 0.0, "speed": 0.0, "gate_i": i,
		"state": "board", "t": 4.0 + i * 9.0,
	}


func _gate_pos(ap: Dictionary, gate_i: int) -> Vector3:
	# 停机位：航站楼前一字排开
	var by: float = ap["base_y"]
	var o: Vector2 = ap["origin"]
	var right: Vector2 = ap["right"]
	var fwd: Vector2 = ap["fwd"]
	var g: Vector2 = o + right * (300.0 + 60.0) + fwd * (-80.0 + gate_i * 90.0)
	return Vector3(g.x, by + 2.6, g.y)


func _threshold_pos(ap: Dictionary) -> Vector3:
	# 跑道端头
	var o: Vector2 = ap["origin"]
	var fwd: Vector2 = ap["fwd"]
	var t: Vector2 = o - fwd * 600.0
	return Vector3(t.x, float(ap["base_y"]) + 2.6, t.y)


func _update_plane(ap: Dictionary, p: Dictionary, dt: float) -> void:
	p["t"] = float(p["t"]) - dt
	match String(p["state"]):
		"board":
			p["pos"] = _gate_pos(ap, int(p["gate_i"]))
			p["heading"] = float(ap["heading"]) + PI * 0.5   # 机头朝航站楼
			p["pitch"] = 0.0
			if p["t"] <= 0.0:
				p["state"] = "taxi"
				p["t"] = 7.0
		"taxi":
			# 停机位 → 跑道端头直线滑行
			var tgt := _threshold_pos(ap)
			p["pos"] = p["pos"].lerp(tgt, 1.0 - exp(-0.5 * dt))
			p["heading"] = float(ap["heading"])
			if p["t"] <= 0.0:
				p["pos"] = tgt
				p["state"] = "roll"
		"roll":
			p["speed"] = float(p["speed"]) + PLANE_ACCEL * dt
			var fwd := Vector2(sin(float(p["heading"])), cos(float(p["heading"])))
			p["pos"] += Vector3(fwd.x, 0, fwd.y) * float(p["speed"]) * dt
			if float(p["speed"]) > ROTATE_SPEED:
				p["state"] = "rotate"
		"rotate":
			p["speed"] = float(p["speed"]) + PLANE_ACCEL * dt
			p["pitch"] = minf(float(p["pitch"]) + 0.12 * dt, 0.2)
			var fwd := Vector2(sin(float(p["heading"])), cos(float(p["heading"])))
			p["pos"] += Vector3(fwd.x, 0, fwd.y) * float(p["speed"]) * dt
			p["pos"].y += sin(float(p["pitch"])) * float(p["speed"]) * dt
			if float(p["pos"].y) > float(ap["base_y"]) + 60.0:
				p["state"] = "climb"
		"climb":
			p["speed"] = move_toward(float(p["speed"]), CLIMB_SPEED, 4.0 * dt)
			var fwd := Vector2(sin(float(p["heading"])), cos(float(p["heading"])))
			p["pos"] += Vector3(fwd.x, 0, fwd.y) * float(p["speed"]) * dt
			p["pos"].y += sin(float(p["pitch"])) * float(p["speed"]) * dt
		"gone":
			p["vis"].visible = false
			if p["t"] <= 0.0:
				p["gate_i"] = (int(p["gate_i"]) + 1) % PLANES_PER_AIRPORT
				p["state"] = "board"
				p["t"] = randf_range(6.0, 14.0)
				p["speed"] = 0.0
				p["pitch"] = 0.0
	if String(p["state"]) == "climb" \
			and Vector3(p["pos"]).length() > 7000.0:
		p["state"] = "gone"
		p["t"] = randf_range(10.0, 22.0)
	var vis: Node3D = p["vis"]
	vis.visible = String(p["state"]) != "gone"
	vis.position = p["pos"]
	vis.rotation = Vector3(-float(p["pitch"]), float(p["heading"]), 0.0)


## ================= 登机人流（航站楼 → 停机位客机） =================

func _make_walker(ap: Dictionary, i: int) -> Dictionary:
	return {
		"t": randf(), "i": i, "wait": 0.0,
		"gate_i": i % PLANES_PER_AIRPORT,
		"speed": randf_range(1.1, 1.6),
	}


func _setup_walkers_mm(ap: Dictionary, count: int) -> Dictionary:
	# 人形 6 部件 MultiMesh（同城市行人配方）
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.42, 0.62, 0.24)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.11, 0.52, 0.13)
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.15, 0.82, 0.17)
	var mm := {
		"head": _make_mm(head_mesh, count),
		"torso": _make_mm(torso_mesh, count),
		"arm": _make_mm(arm_mesh, count * 2),
		"leg": _make_mm(leg_mesh, count * 2),
	}
	for i in count:
		var shirt := Color(0.5 + randf() * 0.4, 0.5, 0.55 + randf() * 0.3)
		mm["torso"].multimesh.set_instance_color(i, shirt)
		mm["head"].multimesh.set_instance_color(i, Color(0.85, 0.68, 0.55))
		mm["arm"].multimesh.set_instance_color(i * 2, shirt)
		mm["arm"].multimesh.set_instance_color(i * 2 + 1, shirt)
		mm["leg"].multimesh.set_instance_color(i * 2, Color(0.25, 0.28, 0.34))
		mm["leg"].multimesh.set_instance_color(i * 2 + 1,
				Color(0.25, 0.28, 0.34))
	return mm


func _update_walkers(ap: Dictionary, dt: float) -> void:
	# 从航站楼门口走到各自停机位舷梯，到门后隐身（视为登机），稍后重来
	var term: Vector3 = _gate_pos(ap, 0) \
			+ Vector3(ap["right"].x, 0, ap["right"].y) * 90.0
	term.y = float(ap["base_y"])
	for w in ap["walkers"]:
		var gate: Vector3 = _gate_pos(ap, int(w["gate_i"]))
		var start := term + Vector3(float(w["i"]) * 1.4 - 5.0, 0, 0)
		var target := gate + Vector3(0, -1.4, 0) \
				+ Vector3(sin(float(w["i"]) * 2.1) * 3.0, 0,
				cos(float(w["i"]) * 1.7) * 3.0)
		w["t"] = float(w["t"]) + dt * float(w["speed"]) / 90.0
		var k: float = fmod(float(w["t"]), 1.4)
		var mm: Dictionary = ap["mm"]
		var idx: int = ap["walkers"].find(w)
		if k > 1.0:
			# 已"登机"：隐藏
			for key in ["head", "torso", "arm", "leg"]:
				mm[key].multimesh.set_instance_transform(idx * 2,
						Transform3D(Basis.from_scale(Vector3.ONE * 0.0001),
						Vector3(0, -50, 0)))
				mm[key].multimesh.set_instance_transform(idx * 2 + 1,
						Transform3D(Basis.from_scale(Vector3.ONE * 0.0001),
						Vector3(0, -50, 0)))
			continue
		var pos: Vector3 = start.lerp(target, k)
		var walk_dir := (target - start).normalized()
		var yaw := atan2(walk_dir.x, walk_dir.z)
		var swing := sin(_t * 8.0 + float(w["i"]) * 1.3) * 0.4
		var root := Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), pos)
		var mm2: Dictionary = mm
		mm2["torso"].multimesh.set_instance_transform(idx,
				root * Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0)))
		mm2["head"].multimesh.set_instance_transform(idx,
				root * Transform3D(Basis.IDENTITY, Vector3(0, 1.58, 0)))
		var sh := Transform3D(Basis.from_euler(Vector3(-swing * 0.6, 0, 0)),
				Vector3(-0.27, 1.4, 0))
		var sh2 := Transform3D(Basis.from_euler(Vector3(swing * 0.6, 0, 0)),
				Vector3(0.27, 1.4, 0))
		var arm_off := Transform3D(Basis.IDENTITY, Vector3(0, -0.26, 0))
		mm2["arm"].multimesh.set_instance_transform(idx * 2, root * sh * arm_off)
		mm2["arm"].multimesh.set_instance_transform(idx * 2 + 1,
				root * sh2 * arm_off)
		var hip := Transform3D(Basis.from_euler(Vector3(swing, 0, 0)),
				Vector3(-0.11, 0.83, 0))
		var hip2 := Transform3D(Basis.from_euler(Vector3(-swing, 0, 0)),
				Vector3(0.11, 0.83, 0))
		var leg_off := Transform3D(Basis.IDENTITY, Vector3(0, -0.41, 0))
		mm2["leg"].multimesh.set_instance_transform(idx * 2, root * hip * leg_off)
		mm2["leg"].multimesh.set_instance_transform(idx * 2 + 1,
				root * hip2 * leg_off)


func _make_mm(mesh: Mesh, count: int) -> MultiMeshInstance3D:
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


## ================= 客机模型（窄体双发喷气客机） =================

func _build_airliner(body: Color, tail: Color) -> Node3D:
	var root := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var glass := Color(0.25, 0.42, 0.55)
	var add_box := func(size: Vector3, p: Vector3, c: Color,
			rot := Vector3.ZERO) -> void:
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.roughness = 0.5
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = p
		mi.rotation = rot
		root.add_child(mi)
	# 机身（机头 +Z）
	add_box.call(Vector3(3.1, 3.3, 24.0), Vector3(0, 0, 0), body)
	add_box.call(Vector3(1.6, 1.7, 3.4), Vector3(0, 0.35, 13.2), body)   # 鼻锥
	add_box.call(Vector3(2.4, 1.0, 2.6), Vector3(0, 1.4, 11.4), glass)   # 驾驶舱
	# 主翼（后掠）
	add_box.call(Vector3(13.0, 0.36, 4.6), Vector3(-7.4, -0.7, -1.0), body,
			Vector3(0, -0.42, 0))
	add_box.call(Vector3(13.0, 0.36, 4.6), Vector3(7.4, -0.7, -1.0), body,
			Vector3(0, 0.42, 0))
	# 发动机短舱 ×2
	add_box.call(Vector3(1.7, 1.7, 4.2), Vector3(-4.6, -1.9, 1.4), dark)
	add_box.call(Vector3(1.7, 1.7, 4.2), Vector3(4.6, -1.9, 1.4), dark)
	# 尾翼：水平尾翼 + 垂尾（航司涂装色）
	add_box.call(Vector3(9.0, 0.24, 2.8), Vector3(0, 0.6, -11.0), body)
	add_box.call(Vector3(0.3, 5.2, 3.6), Vector3(0, 2.9, -11.2), tail)
	# 起落架
	for g in [Vector3(0, -1.9, 10.0), Vector3(-2.2, -1.9, -1.0),
			Vector3(2.2, -1.9, -1.0)]:
		add_box.call(Vector3(0.3, 1.6, 0.3), g, dark)
		add_box.call(Vector3(0.55, 0.55, 0.55), g + Vector3(0, -0.9, 0), dark)
	return root
