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
var ride_names := ["城市机场", "远城机场"]
var fm = null                   # freeroam 引用（注册坡道/货仓铺装）
var cargo_pos := Vector3.ZERO   # 货仓取货点
var cargo_crates: Node3D = null
var cargo_crates_mission: Node3D = null   # 货运任务货箱
var cargo_ramp_base := Vector2.ZERO   # 坡道接地端（探针/导航用）
var cargo_ramp_up := Vector2.ZERO     # 上坡方向（水平单位向量）

# ---- 货运劫案任务 ----
var cargo_mission := "idle"        # idle 停机待命 / taxi 滑行 / takeoff 起飞爬升 / cruise 巡航 / stolen 已被劫 / leave 离场 / cooldown 冷却
var cargo_mission_t := 0.0
var cargo_plane_pos := Vector3.ZERO
var cargo_plane_heading := 0.0
var cargo_plane_pitch := 0.0
var cargo_plane_speed := 0.0
var cargo_plane_vis: Node3D = null
var cargo_taken := false           # 货物已被夺走

# ---- 班机载客（F 登机 → 起飞 → 巡航 → 降落 → 下机）----
var ride_active := false
var ride_from_i := 0
var ride_phase := "idle"       # taxi/roll/rotate/climb/cruise/descend/rollout/arrived
var ride_t := 0.0
var ride_pos := Vector3.ZERO
var ride_heading := 0.0
var ride_pitch := 0.0
var ride_speed := 0.0
var ride_vis: Node3D = null
var ride_gear: Node3D = null
var ride_wps: Array = []           # 载客滑行航路点


func setup(spots: Array, fm_ref = null) -> void:
	fm = fm_ref
	_build_cargo_mission_plane(spots[0]["origin"])
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
			var pl: Dictionary = _make_plane(ap, i)
			pl["gear"] = (pl["vis"] as Node3D).find_child("gear", true, false)
			ap["planes"].append(pl)
		var svis: Node3D = _build_airliner(Color(0.93, 0.94, 0.96),
				Color(0.16, 0.34, 0.6))
		ap["service"] = {"vis": svis, "pos": Vector3.ZERO,
				"heading": heading + PI * 0.5,
				"gear": svis.find_child("gear", true, false)}
		ap["service"]["vis"].visible = true
		add_child(ap["service"]["vis"])
		ap["service"]["pos"] = _gate_pos(ap, 3)
		ap["service"]["vis"].position = ap["service"]["pos"]
		ap["service"]["vis"].rotation.y = ap["service"]["heading"]
		ap["mm"] = _setup_walkers_mm(ap, WALKERS_PER_AIRPORT)
		for i in WALKERS_PER_AIRPORT:
			ap["walkers"].append(_make_walker(ap, i))
		airports.append(ap)
	_build_cargo_plane(spots[0]["origin"], float(spots[0]["heading"]))


## 货运任务：客机停在停机坪，后舱门坡道放平，车辆可驶入货仓夺货
func _build_cargo_plane(origin: Vector2, airport_heading: float) -> void:
	var ph := airport_heading + PI   # 机尾朝停机坪开阔侧
	print("[cp] fm非空=", fm != null, " pads=", fm.road_pads.size() if fm != null else -1)
	var axis := Vector2(sin(ph), cos(ph))          # 机头方向
	var rear_dir := -axis
	var rear := origin + rear_dir * 14.0            # 机尾位置
	var pos := Vector3(origin.x, 0.1, origin.y)
	var vis := _build_airliner(Color(0.75, 0.72, 0.62),
			Color(0.85, 0.6, 0.1))
	vis.position = Vector3(pos.x, 0.1, pos.z)
	vis.rotation.y = ph
	add_child(vis)
	# 尾部舱门坡道（斜板到底）
	var ramp := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(5.6, 0.3, 13.4)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.45, 0.44, 0.4)
	rmat.roughness = 0.85
	rm.material = rmat
	ramp.mesh = rm
	var rc: Vector2 = rear + rear_dir * 5.5
	var slope := atan2(2.5, 11.0)
	ramp.position = Vector3(rc.x, 1.25, rc.y)
	ramp.rotation.y = ph + PI
	ramp.rotation.x = -slope * signf(cos(ph)) if absf(cos(ph)) > 0.01 \
			else -slope
	add_child(ramp)
	# 货仓内货箱
	var crates := Node3D.new()
	crates.name = "cargo_crates"
	add_child(crates)
	cargo_crates_mission = crates
	var cc: Vector2 = rear - rear_dir * 4.0
	cargo_ramp_base = Vector2(rc.x, rc.y)
	cargo_ramp_up = -rear_dir
	cargo_pos = Vector3(cc.x, 2.55, cc.y)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.72, 0.5, 0.16)
	for ci in 4:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := 1.3 - ci * 0.12
		bm.size = Vector3(s, 1.1, s)
		bm.material = cm
		box.mesh = bm
		box.position = Vector3(cc.x + (ci % 2) * 1.4 - 0.7, 2.75 + (ci / 2) * 1.15,
				cc.y + (ci / 2) * 1.2 - 0.6)
		crates.add_child(box)
	cargo_crates = crates
	# 坡道 + 货仓铺装（线性坡度 pad：y→y2）
	if fm != null:
		var fwd2 := Vector2(sin(ph + PI), cos(ph + PI))   # 坡道沿机尾方向
		fm.road_pads.append({"c": Vector2(rc.x, rc.y), "fx": fwd2.x,
				"fz": fwd2.y, "hf": 8.2, "hl": 3.2, "y": 2.6, "y2": 0.1})
		var hc: Vector2 = rear - rear_dir * 5.0
		fm.road_pads.append({"c": Vector2(hc.x, hc.y), "fx": fwd2.x,
				"fz": fwd2.y, "hf": 5.0, "hl": 3.2, "y": 2.6, "y2": 2.6})


## 车辆是否在货仓内（水平距离 + 舱内高度频段）
func cargo_in_hold(pos: Vector3) -> bool:
	if cargo_taken:
		return false
	var hd: float = Vector2(pos.x - cargo_pos.x, pos.z - cargo_pos.z).length()
	return hd < 6.5 and pos.y > 1.0 and pos.y < 5.0


## 取走货物（货箱消失）
func take_cargo() -> void:
	cargo_taken = true
	if cargo_crates != null:
		cargo_crates.visible = false


## 新的一天：货物补充
func respawn_cargo() -> void:
	cargo_taken = false
	if cargo_crates != null:
		cargo_crates.visible = true


## 每帧维护：班机被调走后 30 秒自动补充新班机
func tick(dt: float) -> void:
	for ap in airports:
		var s: Dictionary = ap["service"]
		if s.get("vis") != null:
			continue
		s["respawn"] = float(s.get("respawn", 0.0)) + dt
		if float(s["respawn"]) < 30.0:
			continue
		s["vis"] = _build_airliner(Color(0.93, 0.94, 0.96),
				Color(0.16, 0.34, 0.6))
		s["vis"].visible = true
		add_child(s["vis"])
		s["gear"] = (s["vis"] as Node3D).find_child("gear", true, false)
		s["pos"] = _gate_pos(ap, 3)
		s["heading"] = float(ap["heading"]) + PI * 0.5
		s["vis"].position = s["pos"]
		s["vis"].rotation.y = s["heading"]
		s["respawn"] = 0.0


func update(dt: float) -> void:
	_t += dt
	for ap in airports:
		for p in ap["planes"]:
			_update_plane(ap, p, dt)
		_update_walkers(ap, dt)
	if ride_active:
		_update_ride(dt)


## 班机舱门世界坐标（登机判定点）
func service_door_pos(ap_i: int) -> Vector3:
	var ap: Dictionary = airports[ap_i]
	var s: Dictionary = ap["service"]
	var right := Vector2(cos(float(s["heading"])), -sin(float(s["heading"])))
	var d: Vector2 = right * -4.5   # 舱门在机身左侧（朝航站楼一侧）
	return Vector3(s["pos"].x + d.x, float(s["pos"].y) - 0.6,
			s["pos"].z + d.y)


## 玩家是否站在某座机场的班机舱门旁（返回机场序号，-1 = 否）
func near_service_door(player_pos: Vector3) -> int:
	for i in airports.size():
		if ride_active:
			return -1
		var d: float = service_door_pos(i).distance_to(player_pos)
		if d < 10.0:
			return i
	return -1


func ride_dest_name() -> String:
	return ride_names[1 - ride_from_i]


## 开始载客飞行：班机从本场滑出起飞，巡航至对面机场降落靠桥
func begin_ride(from_i: int) -> bool:
	if ride_active or airports.is_empty():
		return false
	var ap: Dictionary = airports[from_i]
	var s: Dictionary = ap["service"]
	ride_active = true
	ride_from_i = from_i
	ride_phase = "taxi"
	ride_t = 7.0
	ride_pos = Vector3(s["pos"])
	ride_heading = float(s["heading"])
	ride_pitch = 0.0
	ride_speed = 0.0
	ride_wps = []
	ride_vis = s["vis"]
	ride_gear = s.get("gear")
	ap["service"] = {"vis": null, "pos": Vector3.ZERO, "heading": 0.0}
	return true


## 中途放弃行程：班机复位回本场停机位
func abort_ride() -> void:
	ride_active = false
	ride_phase = "idle"
	ride_wps = []
	if ride_gear != null:
		ride_gear.visible = true
	if ride_vis != null:
		ride_vis.visible = false
	var ap: Dictionary = airports[ride_from_i]
	ap["service"] = {"vis": null, "pos": _gate_pos(ap, 3),
			"heading": float(ap["heading"]) + PI * 0.5}
	ride_vis = null


func _update_ride(dt: float) -> void:
	ride_t = float(ride_t) - dt
	var dest_i: int = 1 - ride_from_i
	var dest: Dictionary = airports[dest_i]
	var dest_gate: Vector3 = _gate_pos(dest, 3)
	var dest_th := _threshold_pos(dest)
	var fwd := Vector2(sin(ride_heading), cos(ride_heading))
	match ride_phase:
		"taxi":
			var ap_o: Dictionary = airports[ride_from_i]
			if ride_wps.is_empty():
				ride_wps = _taxi_waypoints(ap_o, 3)
			var tgt: Vector3 = ride_wps[0]
			var to_t := Vector2(tgt.x - ride_pos.x, tgt.z - ride_pos.z)
			ride_speed = 18.0
			if to_t.length() < 16.0:
				ride_wps.pop_front()
				if ride_wps.is_empty():
					ride_pos = Vector3(tgt.x, ride_pos.y, tgt.z)
					ride_heading = float(ap_o["heading"])
					ride_phase = "roll"
			else:
				var want := atan2(to_t.x, to_t.y)
				ride_heading += clampf(wrapf(want - ride_heading, -PI, PI),
						-0.5, 0.5) * 1.4 * dt
				ride_pos += Vector3(sin(ride_heading), 0,
						cos(ride_heading)) * ride_speed * dt
		"roll":
			ride_speed = float(ride_speed) + PLANE_ACCEL * dt
			ride_pos += Vector3(fwd.x, 0, fwd.y) * ride_speed * dt
			if ride_speed > ROTATE_SPEED:
				ride_phase = "rotate"
		"rotate":
			ride_speed = float(ride_speed) + PLANE_ACCEL * dt
			ride_pitch = minf(ride_pitch + 0.12 * dt, 0.2)
			ride_pos += Vector3(fwd.x, 0, fwd.y) * ride_speed * dt
			ride_pos.y += sin(ride_pitch) * ride_speed * dt
			if ride_pos.y > float(airports[ride_from_i]["base_y"]) + 80.0:
				ride_phase = "cruise"
		"cruise":
			ride_speed = move_toward(ride_speed, 150.0, 6.0 * dt)
			ride_pos.y = move_toward(ride_pos.y,
					float(dest["base_y"]) + 260.0, 22.0 * dt)
			var to_d := Vector2(dest_th.x - ride_pos.x, dest_th.z - ride_pos.z)
			var want_h := atan2(to_d.x, to_d.y)
			var dh := wrapf(want_h - ride_heading, -PI, PI)
			ride_heading += clampf(dh, -0.5, 0.5) * 1.2 * dt
			ride_pos += Vector3(sin(ride_heading), 0, cos(ride_heading)) \
					* ride_speed * dt
			if to_d.length() < 2600.0:
				ride_phase = "descend"
		"descend":
			ride_speed = move_toward(ride_speed, 78.0, 5.0 * dt)
			var to_d2 := Vector2(dest_th.x - ride_pos.x, dest_th.z - ride_pos.z)
			var want_h2 := atan2(to_d2.x, to_d2.y)
			ride_heading += clampf(wrapf(want_h2 - ride_heading, -PI, PI),
					-0.5, 0.5) * 1.2 * dt
			ride_pitch = lerpf(ride_pitch, -0.05, 1.0 - exp(-2.0 * dt))
			ride_pos += Vector3(sin(ride_heading), 0, cos(ride_heading)) \
					* ride_speed * dt
			var ground_y: float = float(dest["base_y"]) + 2.6
			ride_pos.y = maxf(ride_pos.y - 14.0 * dt, ground_y)
			if ride_pos.y <= ground_y + 0.05 and to_d2.length() < 700.0:
				ride_pitch = 0.0
				ride_phase = "rollout"
				ride_t = 6.0
		"rollout":
			# 降落滑跑后转向停机位滑行，到位即靠桥
			ride_speed = move_toward(ride_speed, 9.0, 9.0 * dt)
			var to_gate := Vector2(dest_gate.x - ride_pos.x,
					dest_gate.z - ride_pos.z)
			if to_gate.length() < 25.0 or ride_t < -14.0:
				ride_speed = 0.0
				ride_pos = Vector3(dest_gate.x, ride_pos.y, dest_gate.z)
				ride_heading = float(dest["heading"]) + PI * 0.5
				ride_phase = "arrived"
				ride_active = false
				# 班机停靠对面机场，成为该机场的常驻班机（供返程）
				dest["service"] = {"vis": ride_vis, "pos": ride_pos,
						"heading": ride_heading}
			else:
				var want := atan2(to_gate.x, to_gate.y)
				ride_heading += clampf(wrapf(want - ride_heading, -PI, PI),
						-0.6, 0.6) * 1.5 * dt
				ride_pos += Vector3(sin(ride_heading), 0,
						cos(ride_heading)) * ride_speed * dt
	# 应用到班机模型 + 起落架收放
	if ride_vis != null:
		ride_vis.position = ride_pos
		ride_vis.rotation = Vector3(-ride_pitch, ride_heading, 0.0)
	if ride_gear != null:
		var gear_down := ride_phase in ["taxi", "roll", "descend", "rollout",
				"arrived"]
		ride_gear.visible = gear_down


func _ground_y(origin: Vector2) -> float:
	var parent = get_parent()
	if parent != null and parent.has_method("terrain_height"):
		return float(parent.terrain_height(origin.x, origin.y))
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


## 滑行航路点：停机位正后方上滑行道 → 跑道 1/4 处对正点（世界坐标，依次走）
func _taxi_waypoints(ap: Dictionary, gate_i: int) -> Array:
	var o: Vector2 = ap["origin"]
	var fwd: Vector2 = ap["fwd"]
	var right: Vector2 = ap["right"]
	var by: float = float(ap["base_y"])
	var gate_station := -80.0 + gate_i * 90.0
	var wps: Array = []
	for pt in [Vector2(gate_station, 120.0), Vector2(-350.0, 0.0)]:
		var w: Vector2 = o + fwd * pt.x + right * pt.y
		wps.append(Vector3(w.x, by + 2.6, w.y))
	return wps


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
				p["wps"] = []
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
	# 起落架：地面段放下，抬轮后收起，下降段再放出
	if p.get("gear") != null:
		var st := String(p["state"])
		p["gear"].visible = st in ["board", "taxi", "roll", "descend"]


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
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
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
			# 已"登机"：隐藏。head/torso 单实例（下标 idx），arm/leg 左右
			# 两实例（idx*2 / idx*2+1）——此前一律按 idx*2 系写入，
			# 行人过半就把 head/torso 越界刷屏
			mm["head"].multimesh.set_instance_transform(idx,
					Transform3D(Basis.from_scale(Vector3.ONE * 0.0001),
					Vector3(0, -50, 0)))
			mm["torso"].multimesh.set_instance_transform(idx,
					Transform3D(Basis.from_scale(Vector3.ONE * 0.0001),
					Vector3(0, -50, 0)))
			for key in ["arm", "leg"]:
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
	# 起落架（"gear" 组：地面放下 / 空中收起）
	var gear := Node3D.new()
	gear.name = "gear"
	root.add_child(gear)
	for g in [Vector3(0, -1.9, 10.0), Vector3(-2.2, -1.9, -1.0),
			Vector3(2.2, -1.9, -1.0)]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.3, 1.6, 0.3)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = dark
		lm.material = lmat
		leg.mesh = lm
		leg.position = g
		gear.add_child(leg)
		var wheel := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.55, 0.55, 0.55)
		wheel.mesh = wm
		wheel.position = g + Vector3(0, -0.9, 0)
		gear.add_child(wheel)
	return root


## ================= 货运劫案任务 =================

const CARGO_CRUISE_SPD := 16.0     # 货机巡航速度（慢速 ~58km/h，任何载具都能追上）
const CARGO_STEAL_DIST := 32.0     # 夺货判定距离（战机货仓 < 32m）

var cargo_hold_world := Vector3.ZERO   # 货舱世界坐标（夺货判定点）
var cargo_label: Label3D = null


func _build_cargo_mission_plane(origin: Vector2) -> void:
	var ph := -0.35 + PI
	var vis := _build_airliner(Color(0.82, 0.78, 0.68), Color(0.85, 0.55, 0.1))
	vis.visible = true
	add_child(vis)
	cargo_plane_vis = vis
	cargo_plane_pos = Vector3(origin.x + 24.0, 0.1, origin.y - 320.0)
	cargo_plane_heading = -0.35 + PI * 0.5
	cargo_mission = "parked"
	var lb := Label3D.new()
	lb.text = "货 运"
	lb.modulate = Color(1.0, 0.75, 0.2)
	lb.outline_size = 44
	lb.position = Vector3(0, 9.0, 0)
	vis.add_child(lb)
	_sync_cargo_vis()


## F 交互接取：货机开始滑行起飞
func begin_cargo_mission() -> bool:
	if cargo_mission != "parked":
		return false
	cargo_mission = "taxi"
	cargo_mission_t = 0.0
	cargo_plane_pos = Vector3(-1876.0, 0.1, -720.0)
	cargo_plane_heading = -0.35
	cargo_plane_speed = 0.0
	cargo_plane_pitch = 0.0
	return true


func _sync_cargo_vis() -> void:
	if cargo_plane_vis == null:
		return
	cargo_plane_vis.visible = cargo_mission != "gone"
	cargo_plane_vis.position = cargo_plane_pos
	cargo_plane_vis.rotation = Vector3(-cargo_plane_pitch,
			cargo_plane_heading, 0.0)


## 每帧推进货运任务状态机
func update_cargo_mission(dt: float) -> void:
	match cargo_mission:
		"parked":
			return
		"taxi":
			cargo_plane_speed = minf(cargo_plane_speed + 2.5 * dt, CARGO_CRUISE_SPD)
			var fwd := Vector2(sin(cargo_plane_heading), cos(cargo_plane_heading))
			cargo_plane_pos += Vector3(fwd.x, 0, fwd.y) * cargo_plane_speed * dt
			if cargo_plane_speed >= 14.0:
				cargo_mission = "takeoff"
				cargo_plane_pitch = 0.16
		"takeoff":
			cargo_plane_speed = minf(cargo_plane_speed + 1.5 * dt, CARGO_CRUISE_SPD)
			var fwd2 := Vector2(sin(cargo_plane_heading), cos(cargo_plane_heading))
			cargo_plane_pos += Vector3(fwd2.x, 0, fwd2.y) * cargo_plane_speed * dt
			cargo_plane_pos.y += sin(0.16) * cargo_plane_speed * dt
			cargo_plane_pitch = move_toward(cargo_plane_pitch, 0.13, 0.08 * dt)
			if cargo_plane_pos.y > 25.0:
				cargo_mission = "cruise"
		"cruise":
			var fwd3 := Vector2(sin(cargo_plane_heading), cos(cargo_plane_heading))
			cargo_plane_pos += Vector3(fwd3.x, 0, fwd3.y) * cargo_plane_speed * dt
			cargo_plane_pos.y = move_toward(cargo_plane_pos.y, 18.0, 2.0 * dt)
			if cargo_plane_pos.length() > 9000.0:
				cargo_mission = "gone"
				cargo_mission_t = 30.0
		"gone":
			cargo_mission_t -= dt
			if cargo_mission_t <= 0.0:
				cargo_mission = "parked"
				cargo_plane_pos = Vector3(-1876.0, 0.1, -720.0)
				cargo_plane_heading = -0.35 + PI * 0.5
				cargo_plane_speed = 0.0
	# 货舱世界坐标（机身后段货门）
	var back := Vector2(sin(cargo_plane_heading + PI), cos(cargo_plane_heading + PI))
	cargo_hold_world = cargo_plane_pos \
			+ Vector3(back.x, 0, back.y) * 12.0 + Vector3(0, -1.2, 0)
	_sync_cargo_vis()


## 战机是否靠近货舱（夺货判定）
func near_cargo_hold(plane_pos: Vector3) -> bool:
	if cargo_mission != "cruise" and cargo_mission != "takeoff":
		return false
	return plane_pos.distance_to(cargo_hold_world) < 32.0


## 夺走货物
func steal_cargo() -> void:
	if cargo_crates_mission != null:
		cargo_crates_mission.visible = false
	cargo_mission = "cruise"
