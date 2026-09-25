# 回归：赛车场高速高架查询 / 赛道连接道路面 / 导航可达 / 赛道周长
extends SceneTree
func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	for i in 10:
		await process_frame
	game.enter_roam()
	for i in 30:
		await process_frame
	var fm = game.freeroam
	var rd = fm.roads[42]
	var mid: Vector3 = rd.pts[int(rd.pts.size() * 0.45)]
	# query 返回共享字典引用，必须 duplicate 快照后再比较
	var q1: Dictionary = fm.query(mid.x, mid.z, null, 10.0).duplicate()
	var tri := -1
	for ri in fm.roads.size():
		var rd2 = fm.roads[ri]
		if not rd2.closed:
			continue
		var zm := -9e9
		for p0 in rd2.pts:
			zm = maxf(zm, p0.z)
		if zm > 2000.0 and absf(rd2.pts[0].x) < 2000.0 \
				and absf(rd2.pts[0].z) > 2000.0:
			tri = ri
			break
	print("[rw3] 赛道 r=%d" % tri)
	# 赛道东直道：直接取赛道自身采样点（控制点连线不等于样条路径）
	var trd = fm.roads[tri]
	var tp: Vector3 = trd.pts[int(trd.pts.size() * 0.1)]
	var q2: Dictionary = fm.query(tp.x, tp.z, null, 0.0).duplicate()
	print("[rw3] q2 采样点=(%.1f, %.1f) surf=%s" % [tp.x, tp.z, str(q2["surf"])])
	var q3: Dictionary = fm.query(800.0, 2380.0, null, 0.0).duplicate()
	var q4: Dictionary = fm.query(180.0, 950.0, null, 0.0).duplicate()
	print("[rw3] q1 h=%.4f lat=%.4f surf=%s road=%s idx=%s" % [float(q1["height"]),
			float(q1["lat_off"]), str(q1["surf"]), str(q1["road"]), str(q1["idx"])])
	print("[rw3] mid=(%.4f, %.4f)" % [mid.x, mid.z])
	var route: PackedVector2Array = fm.nav_route(Vector2(198, -520),
			Vector2(716, 2432))
	var total := 0.0
	for i in range(1, route.size()):
		total += route[i - 1].distance_to(route[i])
	var tr: PackedVector3Array = fm.roads[tri].pts
	var peri := 0.0
	for i in tr.size():
		peri += tr[i].distance_to(tr[(i + 1) % tr.size()])
	print("[rw3] route=%d total=%.0f peri=%.0f" % [route.size(), total, peri])
	var ok: bool = float(q1["height"]) > 9.0 and float(q1["lat_off"]) < 10.0 \
			and str(q1["surf"]) == "road" and str(q2["surf"]) == "road" \
			and str(q3["surf"]) == "road" and str(q4["surf"]) == "road" \
			and route.size() > 8 and total > 3500.0 and peri > 1200.0
	print("[rw3] 逐项 q1h=%s q1lat=%s q1s=%s q2s=%s q3s=%s q4s=%s route=%s total=%s peri=%s" % [
			str(float(q1["height"]) > 9.0), str(float(q1["lat_off"]) < 10.0),
			str(str(q1["surf"]) == "road"), str(str(q2["surf"]) == "road"),
			str(str(q3["surf"]) == "road"), str(str(q4["surf"]) == "road"),
			str(route.size() > 8), str(total > 3500.0), str(peri > 1200.0)])
	print("[rw3] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
