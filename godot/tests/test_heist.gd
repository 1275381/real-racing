# 回归：截机任务全链路（未接不触发 → F 接取 → 追赶夺货 → 警察）
# 注意：不手动调 _step_sim——game._process 自带 120Hz 固定步长累加器，
# 手动步进会双重推进导致时序漂移。全部用自然帧等待。
extends SceneTree

var game

func frames(n: int) -> void:
	for i in n:
		await process_frame

func wait_s(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame

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

func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(10)
	game.enter_roam()
	await frames(30)
	var at = game.airport_traffic
	var v = game.player.veh
	# 1) 未接任务驶入货仓 → 不触发警察
	var hw: Vector3 = at.cargo_hold_world
	v.place_at({"pos": Vector3(hw.x, maxf(hw.y, 1.3), hw.z),
			"heading": 0.0, "idx": null})
	await wait_s(1.5)
	print("[hs] 未接任务驶入货仓 wanted=%s（期望 false）" % game.npc.wanted)
	# 退出货仓区让提示复位
	v.place_at({"pos": Vector3(hw.x, maxf(hw.y, 1.3), hw.z + 60.0),
			"heading": 0.0, "idx": null})
	await wait_s(0.5)
	# 2) F 接取（步行到货机旁）
	game._toggle_on_foot()
	game.onfoot.enter(Vector3(at.cargo_plane_pos.x,
			at.cargo_plane_pos.y + 1.0, at.cargo_plane_pos.z - 10.0), 0.0)
	await frames(10)
	await press_key(KEY_F)
	print("[hs] 接取 mission=%s chase=%s（期望 taxi/chase）" % [
			at.cargo_mission, game.cargo_heist])
	# 3) 驾车贴住货舱（每帧吸附 hold）直至夺货触发
	game.on_foot = false
	game.onfoot.exit()
	await frames(5)
	var got := false
	for i in 900:
		var h2: Vector3 = at.cargo_hold_world
		v.place_at({"pos": Vector3(h2.x, maxf(h2.y, 1.3), h2.z),
				"heading": 0.0, "idx": null})
		await process_frame
		if game.cargo_state == "escape":
			got = true
			break
	print("[hs] 夺货触发=%s wanted=%s（期望 true/true）" % [got,
			game.npc.wanted])
	print("[hs] %s" % ("PASS" if got and game.npc.wanted else "FAIL"))
	quit(0 if got and game.npc.wanted else 1)
