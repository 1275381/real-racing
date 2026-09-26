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
	# 找一个活敌兵放到玩家前方 50m（平地），其余清空干扰
	var ppos: Vector3 = onfoot.pos
	var target := -1
	for i in bf.soldiers.size():
		var s: Dictionary = bf.soldiers[i]
		if s["dead"] or s["team"] == bf.player_team:
			continue
		if target < 0:
			target = i
			s["pos"] = ppos + Vector3(sin(onfoot.yaw), 0, cos(onfoot.yaw)) * 50.0
			s["hp"] = float(bf.CLASSES[s["cls"]]["hp"])
		else:
			s["dead"] = true   # 屏蔽其它士兵干扰
	print("[aim] 目标兵 hp=%.0f 距离≈50m" % float(bf.soldiers[target]["hp"]))
	# 开镜 + 眼位对准目标胸口
	onfoot.scoped = true
	var target_c: Vector3 = bf.soldiers[target]["pos"] + Vector3(0, 1.05, 0)
	var eye: Vector3 = onfoot.pos + Vector3(0, 1.62, 0)
	var dir: Vector3 = (target_c - eye).normalized()
	onfoot.yaw = atan2(dir.x, dir.z)
	onfoot.pitch = asin(clampf(dir.y, -1.0, 1.0))
	await frames(10)   # 相机/开镜过渡
	# 开镜连射直到击倒（最多 12 发）
	var shots := 0
	var hits := 0
	var hit_conn := func(kind: String, idx: int, point: Vector3, dmg: float):
		pass
	onfoot.shoot_hit.connect(func(kind, idx, point, dmg): hits += 1)
	for i in 12:
		if bf.soldiers[target]["dead"]:
			break
		# 每帧追踪瞄准（模拟玩家跟枪）
		var tc: Vector3 = bf.soldiers[target]["pos"] + Vector3(0, 1.05, 0)
		var e2: Vector3 = onfoot.pos + Vector3(0, 1.62, 0)
		var d2: Vector3 = (tc - e2).normalized()
		onfoot.yaw = atan2(d2.x, d2.z)
		onfoot.pitch = asin(clampf(d2.y, -1.0, 1.0))
		await frames(1)
		onfoot.fire_cd = 0.0
		onfoot._shoot()
		shots += 1
		await frames(2)
	await frames(5)
	var dead: bool = bf.soldiers[target]["dead"]
	var hp_left: float = float(bf.soldiers[target]["hp"])
	print("[aim] 开镜 %d 发 命中 %d 击倒=%s 剩余hp=%.0f" % [shots, hits,
			str(dead), hp_left])
	var ok := dead and shots <= 6
	print("[aim] %s（期望 命中率≈100%、≤6 发击倒）" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
