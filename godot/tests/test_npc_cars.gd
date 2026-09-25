# 回归：NPC 车辆车轮联动（按位移滚动）与双闪状态机
# 注意：灯色/轮变换的视觉回读在 headless 下不可测（Dummy 渲染服务器），
# 视觉走窗口截图；本探针只验证逻辑量。
extends SceneTree

func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	for i in 10:
		await process_frame
	game.enter_roam()
	for i in 30:
		await process_frame
	var npc = game.npc
	var car: Dictionary = npc.cars[0]
	car["speed"] = 12.0
	car["stop_t"] = 0.0
	var roll0: float = car["roll"]
	for i in 3 * 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	var roll_d: float = absf(float(car["roll"]) - roll0)
	print("[np] 轮转 Δroll=%.1f rad（期望 >8）" % roll_d)
	# 双闪状态机：stop_t>0 → _refresh_lights 的 hazard 分支
	npc.cars[1]["stop_t"] = 3.0
	npc._t = 0.1
	npc._refresh_lights(true)
	print("[np] 双闪刷新无报错（stop_t=%.1f）" % float(npc.cars[1]["stop_t"]))
	quit(0 if roll_d > 8.0 else 1)
