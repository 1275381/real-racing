# 回归：击杀播报距离 / 载具左右出生位 / 枪械后坐力与回落
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
	var bf = game.bf
	var onfoot = game.onfoot
	# 1) 击杀播报距离：杀两个不同距离的敌兵，检查 feed 快照
	var ppos: Vector3 = onfoot.pos
	var kills: Array = []
	bf.killed.connect(func(info): kills.append(info))
	var d12 := -1
	var d45 := -1
	for want_d in [12.0, 45.0]:
		for j in bf.soldiers.size():
			var s: Dictionary = bf.soldiers[j]
			if not s["dead"] and s["team"] != bf.player_team:
				s["pos"] = ppos + Vector3(0, 0, want_d)
				bf.damage_soldier_ext(j, 999.0, -1, "test")
				break
	for k in kills:
		if absf(float(k.get("dist", 0)) - 12.0) < 2.0:
			d12 = float(k["dist"])
		if absf(float(k.get("dist", 0)) - 45.0) < 2.0:
			d45 = float(k["dist"])
	print("[rc] 12m杀 dist=%.1f 45m杀 dist=%.1f（期望各≈12/45）" % [d12, d45])
	# 2) 载具左右位
	for k in bf.veh.vehicles.size():
		var v: Dictionary = bf.veh.vehicles[k]
		if v["team"] == bf.player_team and (v["type"] == "heli" or v["type"] == "jet"):
			print("[rc] %s 出生位 x=%.0f（期望 左-24/右+24）" % [v["type"], float(v["pos"].x)])
	# 3) 后坐力：连射 5 发 pitch 累计
	var p0: float = onfoot.pitch
	onfoot.fire_cd = 0.0
	for i in 5:
		onfoot._shoot()
		onfoot.fire_cd = 0.0
	print("[rc] 5发后 recoil_pitch=%.4f rad（期望 >0.01，后坐力减半后）cam 上顶生效" % onfoot.recoil_pitch)
	# 停火 1s 回落
	for i in 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	print("[rc] 停火1s后 recoil_pitch=%.4f（期望回落 <0.01）" % onfoot.recoil_pitch)
	quit(0)
