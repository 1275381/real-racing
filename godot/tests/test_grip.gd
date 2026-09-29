# 回归：前握把购买/切换/倍率下发
extends SceneTree
var game
func frames(n: int) -> void:
	for i in n:
		await process_frame

func frames0(n: int) -> void:
	for i in n:
		await process_frame
func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe.cfg")
	var cfg_path: String = OS.get_user_data_dir() + "/rr_settings_probe.cfg"
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(10)
	game.enter_roam()
	await frames(30)
	print("[gp] 初始 grip=%s mul=%.2f/%.2f（期望 none/1.0）" % [game.grip_id,
			game.onfoot.grip_recoil_mul, game.onfoot.grip_ads_mul])
	# 没钱买：拒
	game.coins = 100
	game._on_grip_pick("vertical")
	print("[gp] 没钱 grip=%s coins=%d（期望 none/100）" % [game.grip_id, game.coins])
	# 有钱买垂直握把
	game.coins = 2000
	game._on_grip_pick("vertical")
	print("[gp] 购后 grip=%s mul=%.2f/%.2f coins=%d（期望 vertical/0.55/1.25/500）" % [
			game.grip_id, game.onfoot.grip_recoil_mul,
			game.onfoot.grip_ads_mul, game.coins])
	# 切换直角（已购免费）
	game._on_grip_pick("angle")
	print("[gp] 切换 grip=%s mul=%.2f/%.2f coins=%d（期望 angle/0.75/1.4/500）" % [
			game.grip_id, game.onfoot.grip_recoil_mul,
			game.onfoot.grip_ads_mul, game.coins])
	# 握把模型：垂直握把时 SMG 枪模应比无握把多 4 个子节点（安装座+柱+2纹）
	print("[gp] --- 握把模型验证 ---")
	game.onfoot.grip_id = "none"
	game.onfoot.set_gun("smg")
	await frames0(5)
	var base_n: int = game.onfoot._gun_holder.get_child(0).get_child_count()
	game.onfoot.grip_id = "vertical"
	game.onfoot.set_gun("smg")
	await frames0(5)
	var grip_n: int = game.onfoot._gun_holder.get_child(0).get_child_count()
	print("[gp] grip_id 状态=%s" % game.onfoot.grip_id)
	print("[gp] SMG 枪模子节点 无握把=%d 垂直握把=%d（期望差 ≥4）" % [base_n, grip_n])
	# 开镜速度实测：数帧数（scoped=true 才有过渡目标 1.0）
	game.onfoot.scoped = true
	game.onfoot._ads = 0.0
	var ads_frames := 0
	while game.onfoot._ads < 0.99 and ads_frames < 200:
		game.onfoot.update(1.0 / 60.0)
		ads_frames += 1
	print("[gp] 开镜过渡帧数=%d（ads_mul=1.4，期望 <15）" % ads_frames)
	var ok: bool = game.grip_id == "angle" \
			and absf(game.onfoot.grip_recoil_mul - 0.75) < 0.01 \
			and absf(game.onfoot.grip_ads_mul - 1.4) < 0.01 \
			and game.coins == 500 and grip_n - base_n >= 4
	print("[gp] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
