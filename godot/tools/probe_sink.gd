extends SceneTree
## 找「车会陷进路面」的位置：某点同时被多条路的面宽覆盖，
## 而 query 在车站在高层时仍返回更低的那一层 → 车被压到低层，视觉上陷进高层路面。
func _init() -> void:
	var m := FreeroamMap.new()
	m.build()
	var bad := {}
	var samples := []
	for ri in m.roads.size():
		var road: FreeroamMap.Road = m.roads[ri]
		for i in range(0, road.pts.size(), 6):
			var p := road.pts[i]
			# 该点是否还被别的路覆盖，且更高
			var top := p.y
			var top_r := ri
			for rj in m.roads.size():
				if rj == ri:
					continue
				var o: FreeroamMap.Road = m.roads[rj]
				var key := Vector2i(int(p.x / FreeroamMap.CELL), int(p.z / FreeroamMap.CELL))
				var hit := false
				for cx in range(-1, 2):
					for cz in range(-1, 2):
						var k2 := Vector2i(key.x + cx, key.y + cz)
						if not o.grid.has(k2):
							continue
						for j in o.grid[k2]:
							var q := o.pts[j]
							# 开放路端点之外没有路面，不能算「覆盖」
							if not o.closed and (j <= 1 or j >= o.pts.size() - 3):
								var ei: int = 0 if j <= 1 else o.pts.size() - 1
								var ep := o.pts[ei]
								var tv := Vector2(sin(o.ang[ei]), cos(o.ang[ei]))
								var lon: float = (p.x - ep.x) * tv.x + (p.z - ep.z) * tv.y
								if (lon < 0.0 if ei == 0 else lon > 0.0):
									continue
							if Vector2(q.x - p.x, q.z - p.z).length() < o.half_w - 0.5:
								if q.y > top + 0.15:
									top = q.y
									top_r = rj
								hit = true
								break
						if hit:
							break
					if hit:
						break
			if top_r == ri:
				continue
			# 车站在高层时，query 是否仍返回低层
			m.vehicle_y = top
			var qq := m.query(p.x, p.z, null)
			var drop: float = top - float(qq["height"])
			if drop > 0.3:
				var k := "road%d 被 road%d 压" % [int(qq["road"]), top_r]
				bad[k] = int(bad.get(k, 0)) + 1
				if samples.size() < 8:
					samples.append("  (%.0f, %.0f) 高层 road%d@%.2f，query 给 road%d@%.2f，车下沉 %.2fm"
							% [p.x, p.z, top_r, top, int(qq["road"]),
							float(qq["height"]), drop])
	print("=== 会把车压到低层的位置 ===")
	if bad.is_empty():
		print("  无")
	for k in bad:
		print("  %-28s %d 处" % [k, bad[k]])
	for s in samples:
		print(s)
	quit()
