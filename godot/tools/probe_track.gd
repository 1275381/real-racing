extends SceneTree
## 赛道几何探针：godot --headless -s res://tools/probe_track.gd

func _init() -> void:
	for ti in TrackData.TRACKS.size():
		var def: Dictionary = TrackData.TRACKS[ti]
		var t := RaceTrack.new()
		t.build(def)
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in t.pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var g := t.grid_pose(0)
		print("%s: n=%d len=%.0f bounds=(%.0f,%.0f)..(%.0f,%.0f) start_idx=%d start=(%.0f,%.0f) grid0=(%.0f,%.0f)" % [
			def["id"], t.n, t.length, lo.x, lo.y, hi.x, hi.y,
			t.start_idx, t.pts[t.start_idx].x, t.pts[t.start_idx].y,
			(g["pos"] as Vector3).x, (g["pos"] as Vector3).z])
	quit()   # 注意：保持在循环外，否则只输出第一条
