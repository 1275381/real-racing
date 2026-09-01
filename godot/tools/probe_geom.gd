extends SceneTree
const RING_Y := 10.0
## 几何体检：环线曲率 / 盘山公路离地 / 城郊楼压街 / 匝道与主线重叠
func _init() -> void:
	var m := FreeroamMap.new()
	m.build()
	var grid_n := 22

	# --- 环线曲率：转角是否折成尖角 ---
	var ring: FreeroamMap.Road = m.roads[grid_n]
	var n := ring.pts.size()
	var worst := 1e9
	var worst_at := Vector2.ZERO
	for i in n:
		var a := ring.pts[(i - 4 + n) % n]
		var b := ring.pts[i]
		var c := ring.pts[(i + 4) % n]
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		var v2 := Vector2(c.x - b.x, c.z - b.z)
		if v1.length() < 0.01 or v2.length() < 0.01:
			continue
		var dth: float = absf(v1.angle_to(v2))
		if dth < 1e-5:
			continue
		var r: float = v1.length() / dth      # 近似曲率半径
		if r < worst:
			worst = r
			worst_at = Vector2(b.x, b.z)
	print("环线最小曲率半径 = %.1fm （半宽 %.1f，小于半宽即路面内缘自我折叠）@(%.0f,%.0f)"
			% [worst, ring.half_w, worst_at.x, worst_at.y])

	# --- 盘山公路离地 ---
	var mtn: FreeroamMap.Road = null
	for r in range(grid_n, m.roads.size()):
		if m.roads[r].elevated:
			continue
		var hi := 0.0
		for p in m.roads[r].pts:
			hi = maxf(hi, p.y)
		if hi > 30.0:
			mtn = m.roads[r]
			break
	if mtn != null:
		var above := 0
		var maxh := 0.0
		for p in mtn.pts:
			if p.y > 3.0:
				above += 1
			maxh = maxf(maxh, p.y)
		# 用地形高程场核对路面离地净高（应当很小 —— 路是切在山脊上的）
		var worst_gap := 0.0
		var gap_at := Vector2.ZERO
		for p2 in mtn.pts:
			var g := p2.y - m._terrain_h(p2.x, p2.z)
			if g > worst_gap:
				worst_gap = g
				gap_at = Vector2(p2.x, p2.z)
		print("盘山公路：%d/%d 个采样海拔 >3m（共 %.0fm，最高 %.1fm）；"
				% [above, mtn.pts.size(), above * FreeroamMap.SAMPLE_DS, maxh]
				+ "路面到地形的最大净高 = %.1fm @(%.0f,%.0f)" % [worst_gap, gap_at.x, gap_at.y])

	# --- 匝道与主线是否仍有同高重叠 ---
	var over := 0
	for a in range(grid_n, m.roads.size()):
		for b in range(a + 1, m.roads.size()):
			var ra: FreeroamMap.Road = m.roads[a]
			var rb: FreeroamMap.Road = m.roads[b]
			if not (ra.elevated and rb.elevated):
				continue
			var lim: float = ra.half_w + rb.half_w - 1.0
			for i in range(0, ra.pts.size(), 4):
				var p := ra.pts[i]
				var key := Vector2i(int(p.x / FreeroamMap.CELL), int(p.z / FreeroamMap.CELL))
				var done := false
				for cx2 in range(-1, 2):
					for cz2 in range(-1, 2):
						var k2 := Vector2i(key.x + cx2, key.y + cz2)
						if not rb.grid.has(k2):
							continue
						for j in rb.grid[k2]:
							var q := rb.pts[j]
							if absf(q.y - p.y) < 0.25 and Vector2(q.x - p.x, q.z - p.z).length() < lim:
								over += 1
								print("  同高重叠: road%d × road%d @(%.0f,%.0f) y=%.2f 间距=%.1f 限=%.1f"
										% [a, b, p.x, p.z, p.y,
										Vector2(q.x - p.x, q.z - p.z).length(), lim])
								done = true
								break
						if done: break
					if done: break
				if done: break
	print("高架之间仍存在同高重叠的路对数 = %d" % over)

	# --- 环线包络与最大无支撑跨度 ---
	var mx := 0.0
	for p2 in ring.pts:
		mx = maxf(mx, maxf(absf(p2.x), absf(p2.z)))
	print("环线包络 max|x|,|z| = %.1f（±720 是网格街，需要 >11m 余量）" % mx)
	var pil := m.pillar_pts
	print("  桥墩实例=%d" % pil.size())
	var near_ring := []
	for j in pil.size():
		if absf(pil[j].y - RING_Y) < 2.0:
			near_ring.append(Vector2(pil[j].x, pil[j].z))
	print("  环线高度附近的柱子 = %d 根" % near_ring.size())
	var gap_max := 0.0
	var at := Vector2.ZERO
	for i in range(0, n, 4):
		var p3 := ring.pts[i]
		var best := 1e9
		for o2 in near_ring:
			best = minf(best, (o2 - Vector2(p3.x, p3.z)).length())
		if best > gap_max:
			gap_max = best
			at = Vector2(p3.x, p3.z)
	print("环线上任一点到最近桥墩的最大距离 = %.0fm （即最大无支撑半跨）@(%.0f,%.0f)"
			% [gap_max, at.x, at.y])
	quit()
