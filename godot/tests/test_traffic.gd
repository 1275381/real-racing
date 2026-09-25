extends SceneTree
# 交通灯系统验收（统一相位版：freeroam_map 四角灯杆 + NPC 停止线）：
# 1) 相位映射：tl_phase 红/黄/绿/棋盘反相
# 2) 红灯逼近 → 停在停止线前，停稳不动
# 3) 绿灯 → 放行
# 4) 前车排队 → 后车停在前车后方 5m 左右
# 5) 全城 20s 车流无死锁

var game

func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	for i in 10:
		await process_frame
	game.enter_roam()
	for i in 30:
		await process_frame
	var npc = game.npc
	var fm = npc.fm
	# 相位映射断言
	var ok_phase: bool = fm.tl_phase(false, 0, 1.0) == 2 \
			and fm.tl_phase(true, 0, 1.0) == 0 \
			and fm.tl_phase(false, 0, 7.0) == 1 \
			and fm.tl_phase(true, 1, 1.0) == 2 \
			and fm.tl_phase(false, 1, 1.0) == 0 \
			and fm.tl_index(180.0) == 6 and fm.tl_index(0.0) < 0 \
			and fm.tl_index(900.0) < 0
	print("[tl] 相位/索引映射 ok=%s" % ok_phase)
	# 找一条纵向、且所在街有信号灯的网格街（固定 x ∈ 内城灯区）
	var r := -1
	for ri in fm.roads.size():
		var road = fm.roads[ri]
		if road.xsec_cut and not road.along_x and not road.closed \
				and fm.tl_index(road.pts[0].x) >= 0:
			r = ri
			break
	var gi_b: int = fm.tl_index(fm.roads[r].pts[0].x)
	print("[tl] 灯区纵向街 r=%d gi_b=%d" % [r, gi_b])
	# —— 2) 红灯逼近停车（车从 z=110 驶向路口 z=180，停止线 167.5）——
	var a: Dictionary = npc.cars[0]
	place_car(npc, a, r, 110.0, 1.0)
	var gi_a: int = fm.tl_index(180.0)
	var p := (gi_a + gi_b) % 2
	# NS 相位组 = p：把游戏时钟锚进红灯窗口（p=0: [8,15)，p=1: [0.5,7.5)）
	var clock := 8.2 if p == 0 else 15.7
	print("[tl] 路口 p=%d 起始相位 ns=%d ew=%d" % [p,
			fm.tl_phase(false, p, clock), fm.tl_phase(true, p, clock)])
	for i in 5.5 * 60:
		game._now_s = clock   # 强制全局时钟（update_signals 与 npc.sig_t 同源）
		game._step_sim(1.0 / 60.0)
		clock += 1.0 / 60.0
	var za: float = npc._car_coord(a, false)
	var dist_a: float = 180.0 - npc.TL_STOP_OFF - za
	print("[tl] 红灯停车 z=%.2f 距停止线=%.2f（期望 -2.5~2.5）" % [za, dist_a])
	var ok_stop := dist_a > -2.5 and dist_a < 2.5
	# 停稳判定：先让蠕动沉降 2s，再比之后 1s 的位移（时钟锚回红灯窗口，防跨翻绿）
	clock = 9.5 if p == 0 else 17.0
	for i in 2 * 60:
		game._now_s = clock
		game._step_sim(1.0 / 60.0)
		clock += 1.0 / 60.0
	var idx0: float = a["idx"]
	for i in 1 * 60:
		game._now_s = clock
		game._step_sim(1.0 / 60.0)
		clock += 1.0 / 60.0
	var frozen: bool = absf(float(a["idx"]) - idx0) < 0.005
	print("[tl] 停稳不动 frozen=%s（期望 true）" % frozen)
	# —— 3) 绿灯放行 ——
	clock = 0.5 if p == 0 else 8.0
	for i in 3 * 60:
		game._now_s = clock
		game._step_sim(1.0 / 60.0)
		clock += 1.0 / 60.0
	var za2: float = npc._car_coord(a, false)
	print("[tl] 绿灯放行 z=%.2f（期望 > 170）" % za2)
	var ok_go := za2 > 170.0
	# —— 4) 排队：A 红灯停线，B 后方 10m 跟车 ——
	clock = 9.5 if p == 0 else 17.0
	place_car(npc, a, r, 160.0, 1.0)
	var b: Dictionary = npc.cars[1]
	place_car(npc, b, r, 150.0, 1.0)
	b["speed"] = 10.0
	for i in 4 * 60:
		game._now_s = clock
		game._step_sim(1.0 / 60.0)
		clock += 1.0 / 60.0
	var gap: float = npc._car_coord(a, false) - npc._car_coord(b, false)
	print("[tl] 排队 gap=%.2f（期望 4~8.5）" % gap)
	var ok_q := gap > 4.0 and gap < 8.5
	# —— 5) 车流总量：20s 无死锁 ——
	npc.sig_t = 0.5
	var total := 0.0
	var lasts := []
	for c in npc.cars:
		lasts.append(float(c["idx"]))
	for i in 20 * 30:
		game._step_sim(1.0 / 30.0)
		npc.sig_t += 1.0 / 30.0
	for k in npc.cars.size():
		total += absf(float(npc.cars[k]["idx"]) - float(lasts[k])) * float(npc._step.get(npc.cars[k]["r"], 1.3))
	print("[tl] 20s 全城车流总位移=%.0fm（期望 >600）" % total)
	var ok_flow := total > 600.0
	# —— 6) 灯光材质与相位联动（p=0 路口：clock 9 → 组0红 组1绿；clock 1 → 反之）——
	# update_signals 在 _process 里，改时钟后要等一帧
	game._now_s = 9.0
	await process_frame
	await process_frame
	var m0: Dictionary = fm._sig_mats[0]
	var m1: Dictionary = fm._sig_mats[1]
	var ok_sig: bool = m0["r"].emission_energy_multiplier > 2.0 \
			and m0["g"].emission_energy_multiplier < 0.5 \
			and m1["g"].emission_energy_multiplier > 2.0 \
			and m1["r"].emission_energy_multiplier < 0.5
	game._now_s = 1.0
	await process_frame
	await process_frame
	ok_sig = ok_sig and m0["g"].emission_energy_multiplier > 2.0 \
			and m1["r"].emission_energy_multiplier > 2.0
	print("[tl] 灯光-相位联动 ok=%s" % ok_sig)
	var all_ok := ok_phase and ok_stop and frozen and ok_go and ok_q and ok_flow and ok_sig
	print("[tl] %s（phase=%s stop=%s frozen=%s go=%s queue=%s flow=%s sig=%s）" % [
			"PASS" if all_ok else "FAIL", ok_phase, ok_stop, frozen, ok_go,
			ok_q, ok_flow, ok_sig])
	quit(0 if all_ok else 1)


## 把车放到纵向街 r 的指定 z 处（dir=+1 朝 +Z）
func place_car(npc, car: Dictionary, r: int, z: float, dir: float) -> void:
	car["r"] = r
	car["dir"] = dir
	car["speed"] = 14.0
	car["stop_t"] = 0.0
	car["disabled"] = false
	car["hit_cd"] = 0.0
	var step: float = float(npc._step[r])
	car["idx"] = (z + 900.0) / step
	for i in 2:   # 线性校正到目标 z
		var c: float = npc._car_coord(car, false)
		car["idx"] = float(car["idx"]) + (z - c) / step
	npc._place_car(car, 0)
