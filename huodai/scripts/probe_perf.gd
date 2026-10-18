extends SceneTree
## 烽火地带 —— 帧率/绘制调用探针（改进方案第 8 节门槛 D：出生点绘制调用 < 800）。
## 五个随机出生点各面朝地图中心 + 中心危险区 + 大坝，各取 90 帧里的最大绘制调用、
## 平均帧时间；出生点超 800 记失败。窗口模式跑（headless 没有渲染统计）：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s res://scripts/probe_perf.gd
## 存档先备份、跑完还原（进局会改存档）

const GATE_DC := 800

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var gp := ProjectSettings.globalize_path(HDData.SAVE_PATH)
	var bak := gp + ".perf_bak"
	var had := FileAccess.file_exists(gp)
	if had:
		DirAccess.copy_absolute(gp, bak)
	root.size = Vector2i(1440, 810)
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 30:
		await process_frame
	m.stash.tutorial_done = true
	m._start_mission(m.stash.loadout)
	for i in 60:
		await process_frame
	var spots: Array = []
	for k in HDData.SPAWN_POINTS.size():
		spots.append(["出生点%d" % k, HDData.SPAWN_POINTS[k], Vector3.ZERO, true])
	spots.append(["中心", Vector3(0, 0, 30), Vector3(0, 0, -30), false])
	spots.append(["大坝", Vector3(0, 0, -60), Vector3(0, 0, -120), false])
	var fails := 0
	for sp in spots:
		var p: Vector3 = sp[1]
		var at: Vector3 = sp[2]
		m.player.enter(p)
		m.player.yaw = atan2(at.x - p.x, at.z - p.z)
		m.player.pitch = 0.0
		for i in 30:
			await process_frame
		var t0 := Time.get_ticks_usec()
		var dc := 0
		for i in 90:
			await process_frame
			dc = maxi(dc, RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var ms := float(Time.get_ticks_usec() - t0) / 90.0 / 1000.0
		var bad: bool = bool(sp[3]) and dc >= GATE_DC
		if bad:
			fails += 1
		print("[perf] %s %s %.1f ms（%.0f fps）绘制调用 %d 图元 %d" % ["FAIL" if bad else "OK  ",
				sp[0], ms, 1000.0 / ms, dc, RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	print("[perf] 合批 %s · 出生点门槛 < %d：%s" % [str(m.world.batch_stats), GATE_DC,
			"全部通过" if fails == 0 else "%d 处超标" % fails])
	m._raid_live = false
	if had:
		DirAccess.copy_absolute(bak, gp)
		DirAccess.remove_absolute(bak)
	quit(0 if fails == 0 else 1)
