# 画面探针（窗口模式，非 headless）：大厅 → 行动出生点 → 中心危险区 → 靶馆 四张截图
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s res://huodai/probe_shot.gd
extends SceneTree

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	var save := "user://huodai_save.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	DirAccess.make_dir_recursive_absolute("res://huodai/out")
	var main = load("res://huodai/main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	root.get_texture().get_image().save_png("res://huodai/out/shot_lobby.png")

	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(50)
	root.get_texture().get_image().save_png("res://huodai/out/shot_mission_spawn.png")

	# 中心危险区：站到 warehouse 附近朝建筑看
	main.player.enter(Vector3(-10.0, 0.0, 30.0))
	main.player.yaw = atan2(10.0, -30.0)
	main.player.pitch = 0.05
	main.player.update(0.016)
	await frames(20)
	root.get_texture().get_image().save_png("res://huodai/out/shot_center.png")

	main._enter_range()
	await frames(40)
	root.get_texture().get_image().save_png("res://huodai/out/shot_range.png")

	print("[probe] 4 张截图完成 → res://huodai/out/")
	main.free()
	quit(0)
