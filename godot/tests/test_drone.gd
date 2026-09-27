# 回归：工程兵巡飞弹全链路——发射 → 飞机规则操控 → 撞敌自爆
extends SceneTree
var game
func frames(n: int) -> void:
	for i in n:
		await process_frame
func step_s(sec: float) -> void:
	for i in int(sec * 60.0):
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
		if i % 60 == 0:
			await frames(1)
func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(10)
	game.enter_roam()
	await frames(30)
	game.exit_roam()
	await frames(10)
	game.enter_battle()
	await frames(20)
	game._on_battle_side("atk")
	await frames(10)
	game._on_battle_deploy(1, 0)   # 工程兵
	await frames(20)
	var bf = game.bf
	print("[dr] 部署 cls=%s gadget=%s（期望 1/drone）" % [game._battle_cls,
			bf.CLASSES[1]["gadget"]])
	# 清 CD、朝敌兵发射
	game._gadget_cd = 0.0
	# 找一个 60m 外的活敌兵，把它钉在玩家正前方
	var ppos: Vector3 = game.onfoot.pos
	var tgt := -1
	for j in bf.soldiers.size():
		var s: Dictionary = bf.soldiers[j]
		if not s["dead"] and s["team"] != bf.player_team:
			if tgt < 0:
				tgt = j
				s["pos"] = ppos + Vector3(0, 0, 60.0)
			else:
				s["dead"] = true
	# 扫一个 40m 无遮挡方向（战场掩体会提前挡爆弹体），敌兵放该方向 30m
	var aim_dir := Vector3.FORWARD
	var eye: Vector3 = game.onfoot.pos + Vector3(0, 1.62, 0)
	for ang in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, PI]:
		var d := Vector3(sin(ang), 0, cos(ang))
		var wd: Dictionary = bf.raycast(eye, d, 40.0)
		if str(wd["type"]) == "":
			aim_dir = d
			break
	bf.soldiers[tgt]["pos"] = ppos + aim_dir * 10.0
	game.onfoot.yaw = atan2(aim_dir.x, aim_dir.z)
	game.onfoot.pitch = 0.0
	await frames(3)
	game._battle_gadget()
	print("[dr] 发射后 drone.active=%s（期望 true）" % [
			str(not bf.player_drone.is_empty())])
	# 操控 2.5s：按住 W（油门），弹体飞向 60m 外敌兵
	var ew := InputEventKey.new()
	ew.physical_keycode = KEY_W
	ew.pressed = true
	Input.parse_input_event(ew)
	Input.flush_buffered_events()
	var p0: Vector3 = bf.player_drone["pos"]
	var flew := 0.0
	var cam_ok := false
	# 逐步推进直到撞击；每帧把靶兵钉回弹道（AI 会跑动）
	var aim_yaw := atan2(aim_dir.x, aim_dir.z)
	for i in 6 * 60:
		game._now_s += 1.0 / 60.0
		if not bf.player_drone.is_empty():
			bf.soldiers[tgt]["pos"] = ppos + aim_dir * 10.0
		game._step_sim(1.0 / 60.0)
		flew += 1.0 / 60.0
		if i == 15 and not bf.player_drone.is_empty():
			print("[dr] 0.25s 位移=%.1fm input_block=%s（期望 >3/true）" % [
					Vector3(bf.player_drone["pos"]).distance_to(p0),
					game.onfoot.input_block])
			print("[dr] 相机距弹体=%.1fm（期望 <9 追尾位）" % [
					game.camera.global_position.distance_to(
					Vector3(bf.player_drone["pos"]))])
		if bf.player_drone.is_empty():
			break
	var dead: bool = tgt >= 0 and bf.soldiers[tgt]["dead"]
	print("[dr] 撞击爆炸 drone已回收=%s 目标兵击倒=%s" % [
			str(bf.player_drone.is_empty()), str(dead)])
	var ok: bool = dead and bf.player_drone.is_empty() \
			and not game.onfoot.input_block and flew < 2.5
	print("[dr] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
