extends SceneTree
## 幽灵墙复现：贴着软墙沿街直行穿过若干路口，记录速度突变
func _init() -> void:
	var map := FreeroamMap.new()
	map.build()
	var veh := Vehicle.new(map, {"is_player": true})
	# 垂直街 x=180，贴到软墙内侧 10.4m（wall=10.6）
	veh.place_at({"pos": Vector3(180.0 + 10.4, 0.03, -500.0), "heading": 0.0, "idx": null})
	var h := 1.0 / 120.0
	var prev := 0.0
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var events := []
	for i in int(30.0 / h):
		map.vehicle_y = veh.pos.y
		veh.input_throttle = 1.0
		veh.input_steer = 0.0
		veh.step(h)
		var d := veh.vf - prev
		if d < -1.0 and events.size() < 10:
			events.append("  t=%.2fs 位置(%.1f,%.1f) vf %.1f→%.1f (Δ%.1f) lat=%.2f surf=%s"
					% [i * h, veh.pos.x, veh.pos.z, prev, veh.vf, d,
					veh.lat_off if "lat_off" in veh else 0.0, veh.surface])
		if d < worst:
			worst = d
			worst_at = veh.pos
		prev = veh.vf
	print("单帧最大减速 = %.2f m/s @(%.0f,%.0f)  末速=%.1f m/s 末位置=(%.0f,%.0f)"
			% [worst, worst_at.x, worst_at.z, veh.vf, veh.pos.x, veh.pos.z])
	for e in events:
		print(e)

	# --- 回归：高架护栏不能被「下方地面街道」抑制掉 ---
	# 南北快速路 x=0、y=14，正下方就是网格街 x=0、y=0.03
	var veh2 := Vehicle.new(map, {"is_player": true})
	map.vehicle_y = 14.0
	veh2.input_steer = 0.0
	veh2.place_at({"pos": Vector3(0.0, 14.0, -300.0), "heading": 0.0, "idx": null})
	var max_lat := 0.0
	var min_y := 99.0
	for i in int(12.0 / h):
		map.vehicle_y = veh2.pos.y
		veh2.input_throttle = 1.0
		veh2.input_steer = 0.85          # 一直往右打死，撞护栏
		veh2.step(h)
		max_lat = maxf(max_lat, absf(veh2.pos.x))
		min_y = minf(min_y, veh2.pos.y)
	print("高架护栏回归：横向最远 %.2fm（桥半宽 10，软墙 10.15）最低 y=%.2f 末位置=(%.1f,%.1f,%.1f)"
			% [max_lat, min_y, veh2.pos.x, veh2.pos.y, veh2.pos.z])

	# --- 回归：驶出断头高架应当及时坠落 ---
	var veh3 := Vehicle.new(map, {"is_player": true})
	map.vehicle_y = 14.0
	veh3.input_steer = 0.0
	veh3.place_at({"pos": Vector3(0.0, 14.0, 780.0), "heading": 0.0, "idx": null})
	var fell_at := 0.0
	for i in int(10.0 / h):
		map.vehicle_y = veh3.pos.y
		veh3.input_throttle = 1.0
		veh3.input_steer = 0.0
		veh3.step(h)
		if fell_at == 0.0 and veh3.pos.y < 13.0:
			fell_at = veh3.pos.z
	print("断头桥回归：路端 z=900，开始下落于 z=%.1f（含自由落体行程）末 y=%.1f"
			% [fell_at, veh3.pos.y])
	# 直接查地图：路面在多远处消失
	var lost := 0.0
	for k in 60:
		var zz := 898.0 + float(k) * 0.5
		map.vehicle_y = 14.0
		var qq := map.query(0.0, zz, null)
		if float(qq["height"]) < 13.0:
			lost = zz
			break
	print("  地图查询：桥面高度在 z=%.1f 处消失（过冲 %.1fm）" % [lost, lost - 900.0])
	quit()
