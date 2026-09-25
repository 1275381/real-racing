extends SceneTree
## 核对每条路都有稳定 id 与 kind，且 id 唯一
func _init() -> void:
	var m := FreeroamMap.new()
	m.build()
	var seen := {}
	var noid := 0
	var counts := {}
	for r in m.roads:
		if r.id == "" or r.kind == "":
			noid += 1
		if seen.has(r.id):
			print("  ✗ id 重复: %s" % r.id)
		seen[r.id] = true
		counts[r.kind] = int(counts.get(r.kind, 0)) + 1
	print("路 %d 条，无 id/kind 的 %d 条" % [m.roads.size(), noid])
	for k in counts:
		print("  kind=%-5s %d 条" % [k, counts[k]])
	var ring := m.road_by_id("ring")
	print("road_by_id(\"ring\") -> %s（半宽 %.1f，闭环 %s，mono %s）"
			% ["找到" if ring != null else "找不到",
			ring.half_w if ring else -1.0, ring.closed if ring else false,
			ring.mono if ring else false])
	quit(1 if noid > 0 or ring == null else 0)
