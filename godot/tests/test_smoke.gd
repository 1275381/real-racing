# 全模式冒烟：漫游驾驶/步行/比赛/大战场/战机/班机/存档，收集状态与报错
extends SceneTree

func frames(n: int) -> void:
	for i in n:
		await process_frame

func step_s(sec: float) -> void:
	for i in int(sec * 60.0):
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
		if i % 60 == 0:
			await frames(1)

func press_key(kc: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = kc
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await frames(3)
	var e2 := InputEventKey.new()
	e2.physical_keycode = kc
	e2.pressed = false
	Input.parse_input_event(e2)
	Input.flush_buffered_events()
	await frames(3)

var game

func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	# 探针共用一份隔离存档：起跑前清掉，免得上一个探针留下的状态
	# （如冒烟测试持久化的 plane=true）让本探针的结果取决于运行顺序
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rr_settings_probe.cfg"))
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(10)
	print("[sm] === 1. 漫游出生")
	game.enter_roam()
	await frames(30)
	print("[sm] state=%s 车位=%s" % [game.state, game.player.veh.pos])
	var ew := InputEventKey.new()
	ew.physical_keycode = KEY_W
	ew.pressed = true
	Input.parse_input_event(ew)
	Input.flush_buffered_events()
	print("[sm] === 2. 出库驾驶 8s")
	for i in 8 * 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
		if i % 60 == 0:
			await frames(1)
	print("[sm] 车位=%s v=%.0fkm/h" % [game.player.veh.pos,
			game.player.veh.vf * 3.6])
	var er := InputEventKey.new()
	er.physical_keycode = KEY_W
	er.pressed = false
	Input.parse_input_event(er)
	Input.flush_buffered_events()
	print("[sm] === 3. 停车 → 步行 → 回车")
	for i in 3 * 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	await press_key(KEY_F)
	await frames(20)
	print("[sm] on_foot=%s（期望 true）" % game.on_foot)
	await frames(30)
	await press_key(KEY_F)
	await frames(20)
	print("[sm] 回车 on_foot=%s（期望 false）" % game.on_foot)
	print("[sm] === 4. 比赛 20s")
	game.exit_roam()
	await frames(10)
	game.start_from_garage()
	await frames(10)
	print("[sm] state=%s（期望 1 倒计时）" % game.state)
	await step_s(20.0)
	print("[sm] 比赛 sim_time=%.0f" % game.sim_time)
	game.exit_roam()
	await frames(10)
	print("[sm] 退赛 state=%s（期望 0）" % game.state)
	print("[sm] === 5. 大战场 10s")
	game.enter_battle()
	await frames(20)
	print("[sm] state=%s 敌军=%d 我方=%d" % [game.state,
			game.bf.army_alive("enemy"), game.bf.army_alive("ally")])
	await step_s(10.0)
	game.exit_battle()
	await frames(10)
	print("[sm] 退场 state=%s（期望 0）" % game.state)
	print("[sm] === 6. 战机模式")
	game._toggle_plane_mode()
	game.enter_roam()
	await frames(30)
	print("[sm] plane_mode=%s" % game.plane_mode)
	game._roam_board_plane()
	await frames(10)
	await step_s(2.0)
	game.exit_roam()
	await frames(10)
	print("[sm] === 7. 机场班机")
	game.enter_roam()
	await frames(30)
	if game.airport_traffic != null:
		var ok: bool = game.airport_traffic.begin_ride(0)
		await step_s(3.0)
		game.airport_traffic.abort_ride()
		print("[sm] 班机 begin/abort=%s" % ok)
	game.exit_roam()
	await frames(10)
	print("[sm] === 冒烟结束（全程无 SCRIPT ERROR 即通过）")
	quit(0)
