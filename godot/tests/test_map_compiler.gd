extends SceneTree
## 地图编译器单测：校验器 / JSON roundtrip / 带高度赛道查询

var fails := 0

func check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[test] %s %s %s" % ["✓" if ok else "✗", name, detail])

func oval(points: int, rx: float, rz: float, y_fn := Callable()) -> Array:
	var out := []
	for k in points:
		var a := TAU * float(k) / points
		var y := 0.0
		if y_fn.is_valid():
			y = y_fn.call(a)
		out.append(Vector3(cos(a) * rx, y, sin(a) * rz))
	return out

func _initialize() -> void:
	# 1) 合法赛道通过
	var ok_def := oval(12, 200, 140)
	var r1: Dictionary = TrackData.validate_track(ok_def)
	check("合法赛道通过校验", r1["ok"], str(r1["errors"]))
	check("周长统计合理", r1["length"] > 800.0 and r1["length"] < 2000.0,
			"len=%d" % int(r1["length"]))
	# 2) 点数不足
	var r2: Dictionary = TrackData.validate_track(oval(4, 100, 80))
	check("点数不足被拒绝", not r2["ok"])
	# 3) 自交（8 字形）被拒绝
	var fig8 := []
	for k in 12:
		var a := TAU * float(k) / 12
		fig8.append(Vector3(sin(a) * 200, 0, sin(2 * a) * 120))
	var r3: Dictionary = TrackData.validate_track(fig8)
	check("8字自交被拒绝", not r3["ok"], str(r3["errors"]))
	# 4) JSON roundtrip
	var def := {"id": "custom_test01", "name": "测试赛道", "desc": "单测",
			"theme": "desert", "points": oval(10, 150, 110,
			func(a: float): return 8.0 + 6.0 * sin(a))}
	check("保存成功", TrackData.save_custom_track(def))
	TrackData.reload_custom_tracks()
	var merged: Array = TrackData.get_tracks()
	var found := {}
	for t in merged:
		if t["id"] == "custom_test01":
			found = t
	check("合并列表包含自定义赛道", not found.is_empty(),
			"内置%d+自定义%d" % [TrackData.TRACKS.size(), merged.size() - TrackData.TRACKS.size()])
	check("roundtrip 点数一致", not found.is_empty() and found["points"].size() == 10)
	if not found.is_empty():
		check("roundtrip 高度保留", absf(found["points"][2].y - def["points"][2].y) < 0.001,
				"y=%.2f" % found["points"][2].y)
		check("roundtrip 主题/名称", found["theme"] == "desert" and found["name"] == "测试赛道")
	# 5) 带高度赛道：构建后 query 高度/坡度
	var trk := RaceTrack.new()
	root.add_child(trk)
	trk.build(found)
	check("带高度赛道构建成功", trk.n >= 700, "n=%d" % trk.n)
	var hmax := -1e9
	var hmin := 1e9
	for h in trk.heights:
		hmax = maxf(hmax, h)
		hmin = minf(hmin, h)
	check("高度随控制点起伏", hmax > 12.0 and hmin < 4.0, "h∈[%.1f, %.1f]" % [hmin, hmax])
	var q: Dictionary = trk.query(trk.pts[trk.n / 4].x, trk.pts[trk.n / 4].y, null)
	check("query 返回真实高度", absf(q["height"] - trk.heights[trk.n / 4]) < 0.01,
			"q=%.2f" % q["height"])
	check("query 返回坡度", absf(q["slope"]) > 0.001 or trk.slope[trk.n / 4] == 0.0)
	var gp: Dictionary = trk.grid_pose(0)
	check("发车位带高度", absf(gp["pos"].y - trk.heights[gp["idx"]]) < 0.01)
	# 6) 清理
	TrackData.delete_custom_track("custom_test01")
	print("[test] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
