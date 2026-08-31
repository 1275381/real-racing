extends SceneTree
## 匝道爬升诊断：打印车在匝道口每秒的状态
func _init() -> void:
	var map := FreeroamMap.new()
	map.build()
	var ramp: FreeroamMap.Road = null
	var ri0 := -1
	for r in range(23, map.roads.size()):
		var rr: FreeroamMap.Road = map.roads[r]
		if rr.pts[0].y < 0.5 and rr.pts[rr.pts.size() - 1].y > 5.0:
			ramp = rr
			ri0 = r
			break
	if ramp == null:
		print("未找到匝道")
		quit()
		return
	print("匝道 road%d: 起点=(%.1f,%.2f,%.1f) 终点=(%.1f,%.2f,%.1f) half_w=%.1f wall=%.2f n=%d"
			% [ri0, ramp.pts[0].x, ramp.pts[0].y, ramp.pts[0].z,
			ramp.pts[ramp.pts.size()-1].x, ramp.pts[ramp.pts.size()-1].y,
			ramp.pts[ramp.pts.size()-1].z, ramp.half_w, ramp.wall, ramp.pts.size()])
	for k in [0, 5, 10, 20, 40, 80]:
		if k >= ramp.pts.size():
			break
		var p := ramp.pts[k]
		map.vehicle_y = p.y
		var q := map.query(p.x, p.z, null)
		print("  样本%3d 位置(%.1f,%.2f,%.1f) 坡度=%.3f → query surf=%s h=%.2f wall=%.2f"
				% [k, p.x, p.y, p.z, ramp.slope[k], q["surf"], q["height"], q["wall"]])
	var veh := Vehicle.new(map, {"is_player": true})
	var start := ramp.pts[0]
	var nxt := ramp.pts[8]
	veh.place_at({"pos": start + Vector3(0, 0.05, 0),
			"heading": atan2(nxt.x - start.x, nxt.z - start.z), "idx": null})
	var h := 1.0 / 120.0
	for i in int(8.0 / h):
		map.vehicle_y = veh.pos.y
		veh.input_throttle = 1.0
		veh.step(h)
		if i % 120 == 0:
			print("  t=%ds pos=(%.1f,%.2f,%.1f) vf=%.2f grounded=%s surf=%s drive=%.2f decel=%.2f"
					% [i / 120, veh.pos.x, veh.pos.y, veh.pos.z, veh.vf, veh.grounded,
					veh.surface, veh.dbg_drive, veh.dbg_decel])
	quit()
