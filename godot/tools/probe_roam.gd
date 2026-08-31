extends SceneTree
## 漫游地图与立体物理探针：godot --headless -s res://tools/probe_roam.gd

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var map := FreeroamMap.new()
	map.build()
	print("build_ms=%d roads=%d samples=%d" % [Time.get_ticks_msec() - t0, map.roads.size(), map.n])

	# --- 查询：地面街道 ---
	map.vehicle_y = 0.0
	var q := map.query(180.0, -540.0, null)
	print("street: surf=%s height=%.3f slope=%.3f wall=%.1f" % [q["surf"], q["height"], q["slope"], q["wall"]])

	# --- 查询：立交选层（x=0,z=0 处地面街道与 N-S 高架重叠）---
	map.vehicle_y = 0.0
	q = map.query(0.0, 0.0, null)
	print("crossing@ground: height=%.2f (期望~0)" % float(q["height"]))
	map.vehicle_y = 14.0
	q = map.query(0.0, 0.0, null)
	print("crossing@bridge: height=%.2f (期望~14)" % float(q["height"]))

	# --- 物理：地面街道直线全油门 20 秒（极速验证）---
	var veh := Vehicle.new(map, {"is_player": true})
	veh.place_at({"pos": Vector3(180, 0.03, -700), "heading": 0.0, "idx": null})
	var h := 1.0 / 120.0
	print("  [veh] top_speed=%.1f power=%.1f" % [veh.top_speed, veh.power])
	for i in int(20.0 / h):
		map.vehicle_y = veh.pos.y
		veh.input_throttle = 1.0
		veh.step(h)
		if i % int(4.0 / h) == 0:
			print("  t=%2ds vf=%.1f drive=%.2f decel=%.2f curve=%.2f g=%s surf=%s" %
					[i / 120, veh.vf, veh.dbg_drive, veh.dbg_decel, veh.dbg_curve,
					veh.grounded, veh.surface])
	print("street-drive: vf=%.1fm/s (%.0fkm/h) y=%.2f grounded=%s pos=(%.0f, %.0f)" %
			[veh.vf, veh.vf * 3.6, veh.pos.y, veh.grounded, veh.pos.x, veh.pos.z])

	# --- 空气墙回归：匝道口外的宽街道上（横向 7m > 匝道半宽 6m）应取街道宽墙 ---
	var ramp2: FreeroamMap.Road = null
	for r in range(23, map.roads.size()):
		if map.roads[r].pts[0].y < 0.5 and map.roads[r].pts[map.roads[r].pts.size() - 1].y > 5.0:
			ramp2 = map.roads[r]
			break
	if ramp2 != null:
		var g := ramp2.pts[1]
		var a := ramp2.ang[1]
		var left := Vector2(cos(a), -sin(a))
		map.vehicle_y = g.y
		var qw := map.query(g.x + left.x * 7.0, g.z + left.y * 7.0, null)
		print("ramp-mouth wall=%.2f (期望 >=10.6，旧版为 6.15 隐形墙) surf=%s" % [float(qw["wall"]), qw["surf"]])

	# --- 物理：匝道爬升到高架环线 ---
	# 找环线（roads[22]）上西北 45° 附近的匝道起点，从地面端开上去
	var ramp: FreeroamMap.Road = null
	for r in range(23, map.roads.size()):
		if map.roads[r].pts[0].y < 0.5 and map.roads[r].pts[map.roads[r].pts.size() - 1].y > 5.0:
			ramp = map.roads[r]
			break
	if ramp != null:
		var start := ramp.pts[0]
		var next := ramp.pts[8]
		var heading := atan2(next.x - start.x, next.z - start.z)
		veh.place_at({"pos": start + Vector3(0, 0.05, 0), "heading": heading, "idx": null})
		var max_y := 0.0
		var airborne_frames := 0
		var ri := 0
		var ramp_ds: float = FreeroamMap.SAMPLE_DS
		for i in int(30.0 / h):
			map.vehicle_y = veh.pos.y
			veh.input_throttle = 1.0
			# 简单追踪转向：瞄准前方 25m 的匝道采样点
			var win := 40
			var bi := ri
			var bd := 1e9
			for o in range(-win, win + 1):
				var ii := posmod(ri + o, ramp.pts.size())
				var dx := ramp.pts[ii].x - veh.pos.x
				var dz := ramp.pts[ii].z - veh.pos.z
				var dd := dx * dx + dz * dz
				if dd < bd:
					bd = dd
					bi = ii
			ri = bi
			var tgt := ramp.pts[(ri + int(25.0 / ramp_ds)) % ramp.pts.size()]
			var desired := atan2(tgt.x - veh.pos.x, tgt.z - veh.pos.z)
			var err := RRUtil.wrap_angle(desired - veh.heading)
			veh.input_steer = clampf(err * 3.0 - veh.yaw_rate * 0.12, -1.0, 1.0)
			veh.step(h)
			max_y = maxf(max_y, veh.pos.y)
			if not veh.grounded:
				airborne_frames += 1
		print("ramp-climb: y_end=%.2f max_y=%.2f grounded=%s airborne_frames=%d vf=%.1f pos=(%.0f,%.0f)" %
				[veh.pos.y, max_y, veh.grounded, airborne_frames, veh.vf, veh.pos.x, veh.pos.z])
	else:
		print("ramp-climb: 未找到匝道")

	# --- 物理：高架桥面行驶（直接放上去）---
	# 先把选层高度复位到桥面：place_at 会按 vehicle_y 选层，
	# 沿用上一用例结束时的 9.88m 会选到别的层，车一放上去就在路肩上
	map.vehicle_y = 14.0
	veh.input_steer = 0.0   # place_at 不重置输入，匝道用例最后留着转向量会让车转出桥面
	veh.place_at({"pos": Vector3(3.0, 14.0, -300.0), "heading": 0.0, "idx": null})
	veh.input_throttle = 1.0
	for i in int(6.0 / h):
		map.vehicle_y = veh.pos.y
		veh.input_throttle = 1.0
		veh.step(h)
	print("bridge-drive: y=%.2f grounded=%s vf=%.1f surf=%s pos=(%.0f,%.0f)" %
			[veh.pos.y, veh.grounded, veh.vf, veh.surface, veh.pos.x, veh.pos.z])

	# --- 小地图纹理 ---
	print("minimap_tex=", map.minimap_tex != null)

	# --- 空中出生落桥场景（复现 ROAM_SPAWN 路径）---
	veh.place_at({"pos": Vector3(0, 20, 300), "heading": 0.0, "idx": null})
	map.vehicle_y = 20.0
	for i in int(3.0 / h):
		map.vehicle_y = veh.pos.y
		veh.input_throttle = 0.0
		veh.step(h)
		if i % 15 == 0:
			print("  fall t=%.2f pos=(%.1f,%.2f,%.1f) vf=%.2f grounded=%s" %
					[i * h, veh.pos.x, veh.pos.y, veh.pos.z, veh.vf, veh.grounded])
	quit()
