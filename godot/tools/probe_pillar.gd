extends SceneTree
## 桥墩落点体检：把真实生成的每根桥墩取出来，对「所有」道路做冲突检测。
##   godot --headless --path . -s res://tools/probe_pillar.gd

const R_PILLAR := 1.5     # 桥墩底半径

func _init() -> void:
	var map := FreeroamMap.new()
	map.build()

	# 直接读地图记录的桥墩表：headless 下 MultiMesh 缓冲读不回来
	var pillars := map.pillar_pts
	print("桥墩总数 = %d" % pillars.size())

	var grid_n := 22
	var kinds := {}
	var samples := []
	for i in pillars.size():
		var px: float = pillars[i].x
		var pz: float = pillars[i].z
		var top: float = pillars[i].y
		for ri in map.roads.size():
			var road: FreeroamMap.Road = map.roads[ri]
			# 桥墩自己那条路不算
			var lim: float = road.half_w + R_PILLAR
			var hit := false
			var hy := 0.0
			var rr := int(ceil(lim / FreeroamMap.CELL)) + 1
			var gx := int(px / FreeroamMap.CELL)
			var gz := int(pz / FreeroamMap.CELL)
			for cxi in range(gx - rr, gx + rr + 1):
				for czi in range(gz - rr, gz + rr + 1):
					var key := Vector2i(cxi, czi)
					if not road.grid.has(key):
						continue
					for j in road.grid[key]:
						var q := road.pts[j]
						if Vector2(q.x - px, q.z - pz).length() >= lim:
							continue
						# 桥墩从地面 0 长到 top；路面落在柱身内即穿模。
						# 阈值 1.5m 用来排除「这根柱子自己撑的那条路」——
						# 中央墩柱顶=桥面、门式墩柱顶=桥面-1
						if q.y < top - 1.5 and q.y > -1.0:
							hit = true
							hy = q.y
							break
					if hit:
						break
				if hit:
					break
			if hit:
				var t := ("网格街" if ri < grid_n else
						("高架" if road.elevated else "城外公路"))
				kinds[t] = int(kinds.get(t, 0)) + 1
				if samples.size() < 12:
					samples.append("  桥墩(%.0f, 顶%.1f, %.0f) 压在 road%d(%s, 面高%.2f, 半宽%.1f) 上"
							% [px, top, pz, ri, t, hy, road.half_w])
				break
	print("=== 压到可行驶路面的桥墩 ===")
	if kinds.is_empty():
		print("  无")
	for k in kinds:
		print("  %-10s %d 根" % [k, kinds[k]])
	for s in samples:
		print(s)
	quit()
