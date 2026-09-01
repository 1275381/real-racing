extends SceneTree
## 低空桥体体检：高架路面降到接近地面时，箱梁 + 防撞墙会横在街道上挡视线/挡路
func _init() -> void:
	var m := FreeroamMap.new()
	m.build()
	var grid_n := 22
	var bins := {}
	var samples := []
	for ri in range(grid_n, m.roads.size()):
		var road: FreeroamMap.Road = m.roads[ri]
		if not road.elevated:
			continue
		for i in range(0, road.pts.size(), 2):
			var p := road.pts[i]
			if p.y < 0.5 or p.y > 5.0:
				continue           # 只关心「贴地~5m」这段桥体
			# 是否压在网格街（含人行道 11m）上
			var on_street := false
			for c in FreeroamMap.GRID_COORDS:
				if absf(p.x - c) < 11.0 or absf(p.z - c) < 11.0:
					on_street = true
					break
			var key := ("压街道" if on_street else "空地") + ("（<2.5m）" if p.y < 2.5 else "（2.5~5m）")
			bins[key] = int(bins.get(key, 0)) + 1
			if on_street and samples.size() < 8:
				samples.append("  road%d 采样 %d 在 (%.0f, y=%.2f, %.0f)：桥体底 %.2f、墙顶 %.2f"
						% [ri, i, p.x, p.y, p.z, p.y - 0.7, p.y + 0.6])
	print("=== 贴地桥体分布（每 3m 一个采样）===")
	for k in bins:
		print("  %-16s %d 个采样 ≈ %.0fm" % [k, bins[k], bins[k] * 3.0])
	for s in samples:
		print(s)
	quit()
