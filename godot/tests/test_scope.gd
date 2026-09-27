# 回归：瞄具商店购买/安装/卸下 + 开镜倍率与热成像档位
extends SceneTree
var game
func frames(n: int) -> void:
	for i in n:
		await process_frame
func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	# 清探针存档：每次从零开始（瞄具持久化是特性，但测试要确定起点）
	var cfg_path: String = OS.get_user_data_dir() + "/rr_settings_probe.cfg"
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)
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
	print("[sp] 未装瞄具 kind=%s（期望 iron）" % game._current_scope_kind())
	# 购买热成像（coins 给足）→ 自动安装到突击步枪
	game.coins = 20000
	game._on_scope_pick("thermal", game.gun_equipped)
	print("[sp] 购后 owned=%s fit=%s kind=%s（期望 thermal→thermal/thermal）" % [
			str(game.scopes_owned), str(game.scope_fit), game._current_scope_kind()])
	# 开镜倍率 = 4×（热成像）
	game.onfoot.scoped = true
	game.onfoot.scope_lv = 0
	await frames(20)
	print("[sp] 开镜 zoom=%.1f fov=%.0f（期望 4.0/≈16）" % [
			game.onfoot.current_zoom(), game.onfoot.cam.fov])
	# 滚轮切 5× 档：热成像保持 4×
	game.onfoot.cycle_scope_zoom(1)
	await frames(20)
	print("[sp] 滚轮后 zoom=%.1f（热成像保持 4.0）" % game.onfoot.current_zoom())
	game.onfoot.cycle_scope_zoom(-1)
	# 卸下 → 机瞄 zoom=1.0×scope_div
	game._on_scope_pick("thermal", game.gun_equipped)
	print("[sp] 卸下后 kind=%s（期望 iron）" % game._current_scope_kind())
	# 装 5× 密位镜 → 滚轮切 5× 生效
	game._on_scope_pick("scope5", game.gun_equipped)
	game.onfoot.cycle_scope_zoom(1)
	await frames(20)
	print("[sp] 5×镜滚轮 zoom=%.1f fov=%.0f（期望 5.0/≈13）" % [
			game.onfoot.current_zoom(), game.onfoot.cam.fov])
	var ok: bool = game._current_scope_kind() == "sniper" \
			and absf(game.onfoot.current_zoom() - 5.0) < 0.01
	print("[sp] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
