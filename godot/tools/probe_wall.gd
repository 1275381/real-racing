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
	quit()
