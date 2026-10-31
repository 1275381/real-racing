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
	var spawn_fails := 0
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
			spawn_fails += 1
		print("[perf] %s %s %.1f ms（%.0f fps）绘制调用 %d 图元 %d" % ["FAIL" if bad else "OK  ",
				sp[0], ms, 1000.0 / ms, dc, RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	# 靶场 2.0 复测（2026-10-31）：馆体拉深 225 + 玻璃隔断/横梁/灯组/立柱/
	# 道具后站射击位看靶道纵深（最重视角）——25m 与 200m 两档，红线 ≥55 帧
	# （2026-10-18 用户定案「至少 55 帧」，同口径：热身 30 帧再测 90 帧）
	m._raid_live = false
	m._enter_range()
	for i in 30:
		await process_frame
	for d in [25, 200]:
		m.targets.set_range_dist(float(d))
		for i in 30:
			await process_frame
		var t0r := Time.get_ticks_usec()
		var dcr := 0
		for i in 90:
			await process_frame
			dcr = maxi(dcr, RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var msr := float(Time.get_ticks_usec() - t0r) / 90.0 / 1000.0
		var fpsr := 1000.0 / msr
		var badr: bool = fpsr < 55.0
		if badr:
			fails += 1
		print("[perf] %s 靶场%dm %.1f ms（%.0f fps）绘制调用 %d 图元 %d" % [
				"FAIL" if badr else "OK  ", d, msr, fpsr, dcr,
				RenderingServer.get_rendering_info(
						RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	m.mode = m.Mode.MISSION   # 复位（_enter_range 置 RANGE）
	print("[perf] 合批 %s · 出生点门槛 < %d：%s · 靶场 ≥55 帧红线含在上面 fails（帧率受后台 Godot 实例压低，DC 为准）" % [str(m.world.batch_stats), GATE_DC,
			"全部通过" if fails == 0 else "出生点 %d 处超标 / 共 %d 处" % [spawn_fails, fails]])
	m._raid_live = false
	if had:
		DirAccess.copy_absolute(bak, gp)
		DirAccess.remove_absolute(bak)
	quit(0 if fails == 0 else 1)
