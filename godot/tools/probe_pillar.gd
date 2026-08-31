extends SceneTree
## 桥墩落点体检：把真实生成的每根桥墩取出来，对「所有」道路做冲突检测。
##   godot --headless --path . -s res://tools/probe_pillar.gd

const R_PILLAR := 1.5     # 桥墩底半径

func _init() -> void:
	var map := FreeroamMap.new()
	map.build()

	# 找到桥墩 MultiMesh
	var pillars: MultiMesh = null
	for c in map.get_children():
		if c is MultiMeshInstance3D and c.multimesh.mesh is CylinderMesh:
			var cm: CylinderMesh = c.multimesh.mesh
			if absf(cm.bottom_radius - 1.5) < 0.01:
				pillars = c.multimesh
				break
	if pillars == null:
		print("未找到桥墩 MultiMesh")
		quit()
		return
	print("桥墩总数 = %d" % pillars.instance_count)

	var grid_n := 22
	var kinds := {}
	var samples := []
	for i in pillars.instance_count:
		var xf := pillars.get_instance_transform(i)
		var px: float = xf.origin.x
		var pz: float = xf.origin.z
		var top: float = xf.origin.y * 2.0        # 缩放后总高 = 中心 y × 2
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
						# 桥墩从地面 0 长到 top；只要该路面高度落在这个区间就是穿模
						if q.y < top - 0.5 and q.y > -1.0:
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
