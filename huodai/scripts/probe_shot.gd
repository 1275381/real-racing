# 画面探针（窗口模式，非 headless）：大厅 → 行动出生点 → 远景士兵 → 中心危险区 → 靶馆 五张截图
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s res://scripts/probe_shot.gd
extends SceneTree

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	var save := "user://huodai_save.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	DirAccess.make_dir_recursive_absolute("res://out")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	root.get_texture().get_image().save_png("res://out/shot_lobby.png")

	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(50)
	root.get_texture().get_image().save_png("res://out/shot_mission_spawn.png")

	# 远景验收（问题②）：0 号兵瞬移到玩家前方 100m 面朝玩家——
	# 轻雾下"远处可见人形"的证据图。state=combat + last_known=自身：
	# 100m 超出交战视距不会开火/转向，站桩摆拍
	var pfwd := Vector3(sin(main.player.yaw), 0.0, cos(main.player.yaw))
	var far: Vector3 = main.player.pos + pfwd * 100.0   # main 鸭子链无类型：显式 Vector3
	var s0: Dictionary = main.soldiers.soldiers[0]
	s0["pos"] = Vector3(far.x, main.world.ground_height(far.x, far.z), far.z)
	s0["last_known"] = s0["pos"]
	s0["yaw"] = atan2(main.player.pos.x - far.x, main.player.pos.z - far.z)
	s0["moving"] = false
	s0["engaged"] = false
	s0["state"] = "combat"
	main.soldiers._write_pose(0)
	await frames(8)
	root.get_texture().get_image().save_png("res://out/shot_far_soldier.png")

	# 中心危险区：站到 warehouse 附近朝建筑看
	main.player.enter(Vector3(-10.0, 0.0, 30.0))
	main.player.yaw = atan2(10.0, -30.0)
	main.player.pitch = 0.05
	main.player.update(0.016)
	await frames(20)
	root.get_texture().get_image().save_png("res://out/shot_center.png")

	main._enter_range()
	await frames(40)
	root.get_texture().get_image().save_png("res://out/shot_range.png")

	print("[probe] 5 张截图完成 → res://out/")
	main.free()
	quit(0)
