# 回归：湖畔别墅全动线——地下楼梯/隧道/军械室/上行楼梯/电梯 1F→2F→3F
extends SceneTree
var game
func frames(n: int) -> void:
	for i in n:
		await process_frame
func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(10)
	game.enter_roam()
	await frames(30)
	var fm = game.freeroam
	# 出库下车
	for i in 4 * 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	game._toggle_on_foot()
	await frames(10)
	# 1) 车库楼梯斜坡：逐段沿坡下行（模拟走楼梯）
	for st in 7:
		game.onfoot.enter(Vector3(202.0 + st * 1.0,
				0.2 - st * 0.55, -509.5), PI * 0.5)
		for i in 6:
			game._now_s += 1.0 / 60.0
			game._step_sim(1.0 / 60.0)
	var y_tunnel: float = game.onfoot.pos.y
	print("[v3] 楼梯下行走后 y=%.2f（期望 ≈-3.2）" % y_tunnel)
	# 2) 隧道可行走（走到尽头）
	game.onfoot.enter(Vector3(208.0, -3.1, -502.0), PI)
	for i in 30:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	var p_tunnel: Vector3 = game.onfoot.pos
	print("[v3] 隧道站位=%s y=%.2f（期望 y≈-3.2 不坠落）" % [str(p_tunnel), p_tunnel.y])
	# 3) 军械室站位（地下室中央）
	game.onfoot.enter(Vector3(207.0, -3.1, -492.0), 0.0)
	for i in 20:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	print("[v3] 军械室 y=%.2f" % game.onfoot.pos.y)
	# 4) 上行楼梯回一层（逐段上坡）
	for st in 9:
		game.onfoot.enter(Vector3(200.0 + st * 1.0,
				-3.1 + st * 0.42, -488.0), PI * 0.5)
		for i in 6:
			game._now_s += 1.0 / 60.0
			game._step_sim(1.0 / 60.0)
	print("[v3] 上楼梯后 y=%.2f（期望 ≈0.13 一层）" % game.onfoot.pos.y)
	# 5) 电梯：走到井内 F 上二层 → 等 3s 到达 → 再 F 到三层
	game.onfoot.enter(Vector3(float(fm.VILLA_ELEV.x) - 1.5, 0.2,
			float(fm.VILLA_ELEV.y)), 0.0)
	for i in 10:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	# 模拟 F（直接调 _landmark_interact）
	game._landmark_interact()
	print("[v3] F后 elev_ride=%s target=%.2f（期望 true/3.6）" % [game.elev_ride,
			game._elev_target])
	for i in 3 * 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
		await frames(1)
	print("[v3] 乘梯后 y=%.2f（期望 ≈3.6 二层）elev_ride=%s" % [
			game.onfoot.pos.y, game.elev_ride])
	game._landmark_interact()
	for i in 3 * 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
		await frames(1)
	print("[v3] 二层→三层 y=%.2f（期望 ≈7.0）" % game.onfoot.pos.y)
	# 6) 楼梯开口地表挖洞：y≈0 的白色城市地表曾整块横在下行楼梯半程
	#    （走得到、看不见）。遍历地图网格数据，地平高度层（|y|<0.05）内
	#    不得有三角形质心落进两个开口（矩形按洞边内缩 0.3m；台阶顶面
	#    y≈0.18、地板剖切边 0.01..0.13 都在地平带外/洞边外，不误报）
	var holes := [Rect2(202.05, -510.95, 5.9, 2.9), Rect2(206.8, -493.2, 3.4, 2.9)]
	var stack: Array = [fm]
	var bad := 0
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		if not (nd is MeshInstance3D):
			continue
		var mm: Mesh = (nd as MeshInstance3D).mesh
		if mm == null or mm.get_surface_count() == 0:
			continue
		var xf: Transform3D = (nd as MeshInstance3D).global_transform
		for si in mm.get_surface_count():
			var va: Array = mm.surface_get_arrays(si)
			if va.is_empty() or va[Mesh.ARRAY_VERTEX] == null:
				continue
			var vs: PackedVector3Array = va[Mesh.ARRAY_VERTEX]
			var ia_raw = va[Mesh.ARRAY_INDEX]
			var ia: PackedInt32Array = ia_raw if ia_raw != null else PackedInt32Array()
			var tri_n: int = (vs.size() / 3) if ia.is_empty() else (ia.size() / 3)
			for t3 in tri_n:
				var i0: int = t3 * 3 if ia.is_empty() else ia[t3 * 3]
				var i1: int = t3 * 3 + 1 if ia.is_empty() else ia[t3 * 3 + 1]
				var i2: int = t3 * 3 + 2 if ia.is_empty() else ia[t3 * 3 + 2]
				var a3: Vector3 = xf * vs[i0]
				var b3: Vector3 = xf * vs[i1]
				var c3: Vector3 = xf * vs[i2]
				if maxf(a3.y, maxf(b3.y, c3.y)) > 0.05 \
						or minf(a3.y, minf(b3.y, c3.y)) < -0.05:
					continue
				var cen := Vector2((a3.x + b3.x + c3.x) / 3.0,
						(a3.z + b3.z + c3.z) / 3.0)
				for hh in holes:
					if hh.has_point(cen):
						bad += 1
						if bad <= 12:
							print("[v3] bad 三角形 cen=(%.1f,%.1f) y=%.2f..%.2f %s" % [
									cen.x, cen.y, minf(a3.y, minf(b3.y, c3.y)),
									maxf(a3.y, maxf(b3.y, c3.y)),
									String(nd.get_path())])
	print("[v3] 楼梯开口地表洞 bad=%d（期望 0）" % bad)
	var ok: bool = absf(y_tunnel - (-3.2)) < 0.6 \
			and absf(game.onfoot.pos.y - 7.0) < 0.6 and bad == 0
	print("[v3] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
