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
	var ok := true
	ok = ok and absf(game.onfoot.current_zoom() - 4.0) < 0.01
	# 卸下 → 机瞄 zoom=1.0
	game._on_scope_pick("thermal", game.gun_equipped)
	print("[sp] 卸下后 kind=%s（期望 iron）" % game._current_scope_kind())
	ok = ok and game._current_scope_kind() == "iron"
	# 红点镜固定 1.5×：滚轮不能把它滚成 5×
	game._on_scope_pick("reddot", game.gun_equipped)
	game.onfoot.scope_lv = 0
	var moved: bool = game.onfoot.cycle_scope_zoom(1)
	await frames(5)
	print("[sp] 红点滚轮 moved=%s zoom=%.1f（期望 false/1.5）" % [moved,
			game.onfoot.current_zoom()])
	ok = ok and not moved and absf(game.onfoot.current_zoom() - 1.5) < 0.01
	# 同一个红点换装到冲锋枪：步枪上的那个被拆下（一镜一枪）
	game._on_scope_pick("reddot", "smg")
	print("[sp] 换装后 fit=%s（期望只在 smg 上）" % str(game.scope_fit))
	ok = ok and str(game.scope_fit.get("smg", "")) == "reddot" \
			and not game.scope_fit.has(game.gun_equipped)
	# 狙击步枪没另装瞄具 = 自带 6× 密位镜（不是机瞄）
	var sn: Dictionary = game.player_scope_for("sniper")
	print("[sp] 狙击枪自带 kind=%s zoom=%.1f（期望 sniper/6.0）" % [
			str(sn.get("kind", "")), float(sn.get("zoom", 0.0))])
	ok = ok and str(sn.get("kind", "")) == "sniper" \
			and absf(float(sn.get("zoom", 0.0)) - 6.0) < 0.01
	# 装 5× 密位镜 → 原生 5×，滚轮切 8×
	game._on_scope_pick("scope5", game.gun_equipped)
	game.onfoot.scope_lv = 0
	await frames(5)
	var z0: float = game.onfoot.current_zoom()
	game.onfoot.cycle_scope_zoom(1)
	await frames(20)
	print("[sp] 5×镜 原生=%.1f 滚轮=%.1f fov=%.0f（期望 5.0/8.0）" % [
			z0, game.onfoot.current_zoom(), game.onfoot.cam.fov])
	ok = ok and game._current_scope_kind() == "sniper" \
			and absf(z0 - 5.0) < 0.01 \
			and absf(game.onfoot.current_zoom() - 8.0) < 0.01
	print("[sp] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
