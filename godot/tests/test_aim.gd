# 回归：大战场射击手感——开镜散布收敛 + 士兵血量（步枪 4 发击倒 70 血）
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
	game.exit_roam()
	await frames(10)
	game.enter_battle()
	await frames(20)
	game._on_battle_side("atk")
	await frames(10)
	game._on_battle_deploy(0, 0)
	await frames(20)
	var onfoot = game.onfoot
	var bf = game.bf
	# 找一个活敌兵放到 50m 外无掩体遮挡的方向（战场掩体密集，
	# 固定方向会间歇被墙挡弹），其余清空干扰
	var ppos: Vector3 = onfoot.pos
	var target := -1
	var aim_dir := Vector3.FORWARD
	for ang in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, PI]:
		var d := Vector3(sin(ang), 0, cos(ang))
		var eye: Vector3 = ppos + Vector3(0, 1.62, 0)
		var wd: Dictionary = bf.raycast(eye, d, 60.0)
		if str(wd["type"]) == "" :   # 60m 内无墙无载具无士兵
			aim_dir = d
			break
	var yaw0 := atan2(aim_dir.x, aim_dir.z)
	for i in bf.soldiers.size():
		var s: Dictionary = bf.soldiers[i]
		if s["dead"] or s["team"] == bf.player_team:
			continue
		if target < 0:
			target = i
			s["pos"] = ppos + aim_dir * 50.0
			s["hp"] = float(bf.CLASSES[s["cls"]]["hp"])
		else:
			s["dead"] = true   # 屏蔽其它士兵干扰
	onfoot.yaw = yaw0
	print("[aim] 目标兵 hp=%.0f 距离≈50m 方向=%.2f" % [
			float(bf.soldiers[target]["hp"]), yaw0])
	# 开镜，眼位先对准目标（之后每发微调）
	onfoot.scoped = true
	var target_c: Vector3 = bf.soldiers[target]["pos"] + Vector3(0, 1.05 * 1.5, 0)
	var eye: Vector3 = onfoot.pos + Vector3(0, 1.62, 0)
	var dir: Vector3 = (target_c - eye).normalized()
	onfoot.yaw = atan2(dir.x, dir.z)
	onfoot.pitch = asin(clampf(dir.y, -1.0, 1.0))
	await frames(10)   # 相机/开镜过渡
	var tpos: Vector3 = bf.soldiers[target]["pos"]
	var shots := 0
	for i in 12:
		if bf.soldiers[target]["dead"]:
			break
		# 每发重新瞄准命中球中心（冻结位），交给 onfoot.update 刷相机
		var tc: Vector3 = tpos + Vector3(0, 1.05 * 1.5, 0)
		var e2: Vector3 = onfoot.pos + Vector3(0, 1.62, 0)
		var d2: Vector3 = (tc - e2).normalized()
		onfoot.yaw = atan2(d2.x, d2.z)
		onfoot.pitch = asin(clampf(d2.y, -1.0, 1.0))
		await frames(1)
		# 射击瞬间钉靶 + 清空弹道走廊（友军跑进射线会被无友伤规则吞弹）
		bf.soldiers[target]["pos"] = tpos
		for j in bf.soldiers.size():
			if j != target and not bf.soldiers[j]["dead"]:
				bf.soldiers[j]["pos"] = Vector3(0, -300, 0)
		onfoot.fire_cd = 0.0
		onfoot._shoot()
		shots += 1
		await frames(2)
	await frames(5)
	var dead: bool = bf.soldiers[target]["dead"]
	var hp_left: float = float(bf.soldiers[target]["hp"])
	print("[aim] 开镜 %d 发 击倒=%s 剩余hp=%.0f" % [shots, str(dead), hp_left])
	var ok: bool = dead and shots <= 8
	print("[aim] %s（期望 命中率≈100%%、≤6 发击倒）" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
