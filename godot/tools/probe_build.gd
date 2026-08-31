extends SceneTree
## 只建图不跑物理，用于快速验证地图生成改动：
##   godot --headless --path . -s res://tools/probe_build.gd
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var m := FreeroamMap.new()
	m.build()
	print("total_ms=%d roads=%d samples=%d" % [Time.get_ticks_msec() - t0, m.roads.size(), m.n])
	quit()
