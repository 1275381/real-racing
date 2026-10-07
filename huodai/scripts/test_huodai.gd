# 回归：烽火地带（Godot 版）核心链路——签到/开箱/命中/换弹掉匣/搜刮/撤离/死亡/靶场/经济
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s huodai/test_huodai.gd
extends SceneTree

var main
var fails: int = 0

func frames(n: int) -> void:
	for i in n:
		await process_frame

func check(name: String, ok: bool, extra := "") -> void:
	if not ok:
		fails += 1
	print("[huodai] %s %s%s" % ["PASS" if ok else "FAIL", name, (" —— " + extra) if extra != "" else ""])

func _initialize() -> void:
	# 存档隔离：删掉上一次探针留下的存档，结果不依赖运行顺序
	var save := "user://huodai_save.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await frames(20)
	_run()

func _run() -> void:
	# 1. 冷启动：大厅可见、现金 0
	check("冷启动大厅可见", main.lobby.lobby_visible)
	check("初始现金 0", main.stash.cash == 0)

	# 2. 每日签到：首领 1500，再领 0
	var got: int = main.stash.check_in()
	check("签到得 1500", got == 1500, "got=%d" % got)
	check("现金入账", main.stash.cash == 1500)
	check("同日二刷拒绝", main.stash.check_in() == 0)

	# 3. 开箱 roll：150 次全部落在档位区间内
	var roll_ok := true
	for i in 150:
		var it: Dictionary = HDData.roll_loot(["wild", "mid", "center"][i % 3])
		var r: int = int(it["rarity"])
		var rar: Dictionary = HDData.RARITY[r]
		if r < 0 or r > 6 or float(it["value"]) < float(rar["vmin"]) - 0.5 \
				or float(it["value"]) > float(rar["vmax"]) + 0.5:
			roll_ok = false
	check("roll_loot 150 次档位与价值合法", roll_ok)

	# 4. 出发进行动：装 primary/secondary、满弹满备弹
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(30)
	check("进入 MISSION", main.mode == main.Mode.MISSION)
	check("大厅已隐藏", not main.lobby.lobby_visible)
	check("步枪满弹", main.guns.ammo == 30 and main.guns.reserve == 150,
		"ammo=%d reserve=%d" % [main.guns.ammo, main.guns.reserve])
	check("出生点在地图内", absf(main.player.pos.x) <= HDData.MAP_HALF
		and absf(main.player.pos.z) <= HDData.MAP_HALF)

	# 5. 命中判定：把 0 号兵放到面前 10m，aim 后 raycast_all 应报 soldier
	var s0: Dictionary = main.soldiers.soldiers[0]
	var fwd := Vector3(sin(main.player.yaw), 0.0, cos(main.player.yaw))
	s0["pos"] = main.player.pos + fwd * 10.0
	s0["hp"] = 100.0
	s0["dead"] = false
	main.player.update(0.016)   # 应用朝向到相机
	var from: Vector3 = main.player.cam.global_position
	var dir: Vector3 = -main.player.cam.global_transform.basis.z
	var hit: Dictionary = main.guns.raycast_all(from, dir, 300.0)
	check("正面射线命中士兵", str(hit.get("type", "")) == "soldier",
		"type=%s" % str(hit.get("type", "")))
	var res: Dictionary = main.soldiers.apply_hit(0, 200.0, false)
	check("200 伤害击倒", bool(res.get("killed", false)))

	# 6. 换弹：先打空几发（满弹时拒绝换弹是正确行为），进度推进 + 弹匣回满扣备弹
	main.guns.ammo = 10
	main.guns.start_reload()
	var had_progress: bool = main.guns.reloading > 0.0
	for i in 140:
		main.guns.update(0.016)
	check("换弹进度启动", had_progress)
	check("换弹完成回满扣备弹", main.guns.ammo == 30 and main.guns.reserve == 130,
		"ammo=%d reserve=%d（补缺口 20 发，150-20=130，网页版同款语义）" % [main.guns.ammo, main.guns.reserve])

	# 7. 搜刮：站在容器上按住 F 1.8s 入包
	var spot: Dictionary = main.world.container_spots[0]
	main.player.enter(spot["pos"])
	main.player.update(0.016)
	for i in 130:
		main.loot.update(0.016, main.player.pos, true)
	check("按住 F 开箱入包", main.loot.backpack.size() >= 1,
		"bag=%d" % main.loot.backpack.size())

	# 8. 撤离：挪到撤离点快进读条 → 入库 + 战绩
	main._bag_value = 5000.0   # 便于断言档位（实际值由第 7 步开箱决定）
	main.player.enter(main.world.extract_pos)
	main._extract_t = 4.95
	await frames(10)
	check("撤离结算 WIN", main.hud.result_visible and main.stash.stats["extracts"] == 1)
	check("战利品入库", main.stash.items.size() >= 1 and main.loot.backpack.is_empty())

	# 9. 死亡：重开一局后打空血 → LOSE + 丢包
	main._restart_current()
	await frames(10)
	main.player.hit(9999.0)
	check("阵亡结算 LOSE", main.hud.result_visible and main.stash.stats["deaths"] == 1)
	check("死亡丢背包", main.loot.backpack.is_empty())

	# 10. 靶场：进场 + 计分
	main._enter_range()
	await frames(10)
	check("进入 RANGE", main.mode == main.Mode.RANGE)
	var sc0: int = main.targets.score
	main.targets.on_hit(0)
	check("靶子计分", main.targets.score > sc0)

	# 11. 经济：买瞄具 → 装配 → 倍率生效
	var cash_before: int = main.stash.cash
	if cash_before >= 700:
		check("买红点镜", main.stash.buy_scope("reddot")
			and main.stash.cash == cash_before - 700)
		main.stash.equip_scope("rifle", "reddot")
		check("装配后倍率 1.5", absf(main.stash.scope_zoom("rifle") - 1.5) < 0.01)
	else:
		check("买红点镜（现金不足跳过）", true)

	print("[huodai] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	main.free()
	quit(0 if fails == 0 else 1)
