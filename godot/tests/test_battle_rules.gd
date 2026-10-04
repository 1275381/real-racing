# 回归：大战场规则一致性——守方兵力池攻守对称 / 防弹衣退场退还 / 退场血量复位 / 血条满格值
extends SceneTree
var game
var fails := 0
func frames(n: int) -> void:
	for i in n:
		await process_frame
func check(name: String, ok: bool, detail := "") -> void:
	print("[br] %s %s %s" % ["✓" if ok else "✗", name, detail])
	if not ok:
		fails += 1
func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe_br.cfg")
	var cfg_path: String = OS.get_user_data_dir() + "/rr_settings_probe_br.cfg"
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(10)
	game.enter_roam()
	await frames(30)
	game.exit_roam()
	await frames(10)

	# ---- 1) 玩家守方：阵亡扣守方兵力；守方兵力耗尽 → 进攻方胜（原来只在玩家进攻时判）----
	game.enter_battle()
	await frames(20)
	game._on_battle_side("def")
	await frames(10)
	game._on_battle_deploy(0, 0)
	await frames(10)
	var bf = game.bf
	var d0: int = bf.def_tickets
	game.player_hp = 1.0
	game._on_bf_player_hit(50.0, Vector3.ZERO)
	await frames(2)
	check("守方玩家阵亡扣守方兵力", bf.def_tickets == d0 - 1, "%d → %d" % [d0, bf.def_tickets])
	var won := [null]
	bf.over.connect(func(atk_win: bool): won[0] = atk_win)
	var c0: int = game.coins
	bf.def_tickets = 0
	await frames(5)
	check("守方兵力耗尽即判进攻方胜", bf.battle_over and won[0] == true,
			"over=%s atk_win=%s" % [bf.battle_over, won[0]])
	check("零得分不发结算奖励（防挂机刷金币）", game.coins == c0,
			"coins %d → %d" % [c0, game.coins])
	game.exit_battle()
	await frames(10)
	check("退场血量复位 100", is_equal_approx(game.player_hp, 100.0), "hp=%.0f" % game.player_hp)

	# ---- 2) 防弹衣：部署扣 1 件；没挨打活着退场退回库存 ----
	game.armor_stock = 2
	game.enter_battle()
	await frames(20)
	game._on_battle_side("atk")
	await frames(10)
	game._on_battle_deploy(0, 0)
	await frames(10)
	check("部署穿甲扣库存", game.armor_stock == 1 and game.player_armor >= 50.0,
			"stock=%d armor=%.0f" % [game.armor_stock, game.player_armor])
	check("血条满格值 = 兵种血量", is_equal_approx(game.hud._gun_hp_max, game._battle_max_hp),
			"max=%.0f cls=%.0f" % [game.hud._gun_hp_max, game._battle_max_hp])
	# 有得分的胜利：500 + 得分（封顶 +1000）
	bf = game.bf
	bf.player_stats["score"] = 400
	var c1: int = game.coins
	bf._finish(true)
	await frames(2)
	check("胜利结算 = 500 + 得分", game.coins == c1 + 900, "coins +%d" % (game.coins - c1))
	game.exit_battle()
	await frames(5)
	check("完好防弹衣退场退回", game.armor_stock == 2, "stock=%d" % game.armor_stock)
	check("退场血条满格值复位 100", is_equal_approx(game.hud._gun_hp_max, 100.0))

	# ---- 3) T 切弹药不再瞬间满弹匣（gun_ammo 按真实余量回写）----
	game.enter_battle()
	await frames(20)
	game._on_battle_side("atk")
	await frames(10)
	game._on_battle_deploy(0, 0)   # 突击兵 rifle
	await frames(10)
	bf = game.bf
	game.guns_owned = ["pistol", "rifle", "standard", "power"]
	game.ammo_type = "standard"
	game._battle_cycle_ammo()
	await frames(2)
	game.onfoot.ammo = 5
	game.onfoot.gun_ammo["rifle"] = 5
	game._battle_cycle_ammo()   # 切回 standard：重建枪模必须按余量恢复
	await frames(2)
	check("T 切弹药不回满弹匣", game.onfoot.ammo == 5, "ammo=%d" % game.onfoot.ammo)

	# ---- 4) 结算后 G 道具无效（堵朝冻结 AI 人堆扔雷刷金币）----
	bf._clear_projectiles()
	bf.battle_over = true
	bf.player_alive = true
	game.on_foot = true
	game.player_hp = 100.0
	game._gadget_cd = 0.0
	game._battle_gadget()
	check("结算后道具无效", bf.projectiles.is_empty(),
			"projectiles=%d" % bf.projectiles.size())
	game.exit_battle()
	await frames(5)

	# ---- 5) 操控巡飞弹中退场：drone 清理、重部署状态复位 ----
	game.enter_battle()
	await frames(20)
	game._on_battle_side("atk")
	await frames(10)
	game._on_battle_deploy(1, 0)   # 工程兵（巡飞弹）
	await frames(10)
	bf = game.bf
	bf.launch_drone(bf.player_pos + Vector3(0, 2, 1), Vector3(0, 0, 1), bf.player_team)
	await frames(2)
	check("巡飞弹已发射", not bf.player_drone.is_empty())
	game.exit_battle()
	await frames(5)
	check("退场清理巡飞弹", bf.player_drone.is_empty())
	game.enter_battle()
	await frames(20)
	game._on_battle_side("atk")
	await frames(10)
	game._on_battle_deploy(0, 0)
	await frames(2)
	check("重部署 input_block 复位", game.onfoot.input_block == false)
	check("重部署 fire_block 复位", game.onfoot.fire_block == false)
	game.exit_battle()
	await frames(5)

	print("[br] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)
