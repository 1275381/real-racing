extends SceneTree
## 路网交叉体检：列出所有道路两两相交处的高差，找出「重叠在一起」的交叉。
##   godot --headless --path . -s res://tools/probe_cross.gd

const NEAR := 3.0        # XZ 距离小于此值视为同一交叉点
const CLEAR := 4.5       # 立体交叉的最小净空（车高约 1.4m + 桥面厚度）

func _init() -> void:
	var m := FreeroamMap.new()
	m.build()
	var kinds := {}
	var bad := []
	var seen := {}
	for a in m.roads.size():
		for b in range(a + 1, m.roads.size()):
			var ra: FreeroamMap.Road = m.roads[a]
			var rb: FreeroamMap.Road = m.roads[b]
			for i in range(0, ra.pts.size(), 2):
				var p := ra.pts[i]
				var key := Vector2i(int(p.x / 24.0), int(p.z / 24.0))
				var found := false
				for cx in range(-1, 2):
					for cz in range(-1, 2):
						var k2 := Vector2i(key.x + cx, key.y + cz)
						if not rb.grid.has(k2):
							continue
						for j in rb.grid[k2]:
							var q := rb.pts[j]
							if Vector2(q.x - p.x, q.z - p.z).length() > NEAR:
								continue
							var ck := "%d-%d-%d-%d" % [a, b, int(p.x / 60.0), int(p.z / 60.0)]
							if seen.has(ck):
								continue
							seen[ck] = true
							var dy: float = absf(q.y - p.y)
							var tag := ""
							if dy < 0.25:
								tag = "共面/贴面"
							elif dy < CLEAR:
								tag = "高差不足"
							else:
								continue
							var ta: String = FreeroamMap.KIND_LABEL.get(ra.kind, "?")
							var tb: String = FreeroamMap.KIND_LABEL.get(rb.kind, "?")
							var kk := "%s×%s %s" % [ta, tb, tag]
							kinds[kk] = int(kinds.get(kk, 0)) + 1
							if bad.size() < 14:
								bad.append("  road%d(%s y=%.2f) × road%d(%s y=%.2f) @(%.0f,%.0f) Δy=%.2f %s"
										% [a, ta, p.y, b, tb, q.y, p.x, p.z, dy, tag])
							found = true
							break
						if found:
							break
					if found:
						break
	print("=== 交叉体检（Δy < %.1fm 才列出）===" % CLEAR)
	for k in kinds:
		print("  %-28s %d 处" % [k, kinds[k]])
	print("--- 样例 ---")
	for line in bad:
		print(line)
	quit()
