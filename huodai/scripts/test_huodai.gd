# 回归：烽火地带（Godot 版）核心链路——签到/开箱/命中/换弹掉匣/搜刮/撤离/死亡/靶场/经济
#       + 画质战场回归：开镜倍率语义/靶馆地坪分层/士兵比例/雾密度红线
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

	# 4. 出发进行动：装 primary/secondary、满弹 + 备弹按 stash 装填（首局=满额礼物 150）
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(30)
	check("进入 MISSION", main.mode == main.Mode.MISSION)
	check("大厅已隐藏", not main.lobby.lobby_visible)
	check("步枪满弹·备弹=stash（首局礼物 150）",
		main.guns.ammo == 30 and main.guns.reserve == 150
			and main.guns.reserve == main.stash.ammo_of("rifle"),
		"ammo=%d reserve=%d stash=%d" % [main.guns.ammo, main.guns.reserve,
			main.stash.ammo_of("rifle")])
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
	#    （备弹语义已改极致备弹经济：stash 库存 150 → 换弹取 min(缺口,备弹)）
	main.guns.ammo = 10
	main.guns.start_reload()
	var had_progress: bool = main.guns.reloading > 0.0
	for i in 140:
		main.guns.update(0.016)
	check("换弹进度启动", had_progress)
	check("换弹完成回满扣备弹", main.guns.ammo == 30 and main.guns.reserve == 130,
		"ammo=%d reserve=%d（补缺口 20 发，150-20=130，局内 reserve 不再免费）" % [main.guns.ammo, main.guns.reserve])

	# 6b. 极致备弹账目：实打 5 发 → 换弹 → reserve 精确 -5（买多少用多少的核心语义）
	for i in 5:
		main.guns.try_fire()
		main.guns.fire_cd = 0.0   # 绕射速间隔：账目回归不考手感
	check("实打 5 发余弹 25", main.guns.ammo == 25,
		"ammo=%d" % main.guns.ammo)
	main.guns.start_reload()
	for i in 140:
		main.guns.update(0.016)
	check("换弹后备弹精确 -5", main.guns.ammo == 30 and main.guns.reserve == 125,
		"ammo=%d reserve=%d（130-5=125）" % [main.guns.ammo, main.guns.reserve])

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
	check("撤离回收备弹入 stash（=局末 reserve）",
		main.stash.ammo_of("rifle") == 125 and main.stash.ammo_of("pistol") == 60
			and main.stash.ammo_of("rifle") == main.guns.reserve,
		"rifle=%d pistol=%d guns.reserve=%d" % [main.stash.ammo_of("rifle"),
			main.stash.ammo_of("pistol"), main.guns.reserve])

	# 9. 死亡：重开一局后打空血 → LOSE + 丢包（备弹不丢——弹药非战利品）
	main._restart_current()
	await frames(10)
	main.player.hit(9999.0)
	check("阵亡结算 LOSE", main.hud.result_visible and main.stash.stats["deaths"] == 1)
	check("死亡丢背包", main.loot.backpack.is_empty())
	check("死亡备弹照常保留", main.stash.ammo_of("rifle") == 125
			and main.stash.ammo_of("pistol") == 60,
		"rifle=%d pistol=%d" % [main.stash.ammo_of("rifle"),
			main.stash.ammo_of("pistol")])

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

	# 12. 开镜倍率语义（问题①回归）：突击步枪不自带倍率——装配镜生效/
	# 未装镜=机瞄 iron 1.0 / 狙击原厂镜恒 6.0
	main.stash.buy_scope("reddot")   # 幂等：已拥有直接 true，不依赖第 11 步分支
	main.stash.equip_scope("rifle", "reddot")
	var sc_rd: Dictionary = main._scope_for("rifle")
	check("装红点后 _scope_for 1.5", str(sc_rd.get("kind", "")) == "reddot"
		and absf(float(sc_rd.get("zoom", 0.0)) - 1.5) < 0.01,
		"kind=%s zoom=%.2f" % [str(sc_rd.get("kind")), float(sc_rd.get("zoom", 0.0))])
	main.stash.equip_scope("rifle", "iron")
	var sc_ir: Dictionary = main._scope_for("rifle")
	check("卸镜回机瞄 iron 1.0", str(sc_ir.get("kind", "")) == "iron"
		and absf(float(sc_ir.get("zoom", 0.0)) - 1.0) < 0.01,
		"kind=%s zoom=%.2f" % [str(sc_ir.get("kind")), float(sc_ir.get("zoom", 0.0))])
	var sc_sn: Dictionary = main._scope_for("sniper")
	check("狙击自带恒 6.0", str(sc_sn.get("kind", "")) == "sniper"
		and absf(float(sc_sn.get("zoom", 0.0)) - 6.0) < 0.01,
		"kind=%s zoom=%.2f" % [str(sc_sn.get("kind")), float(sc_sn.get("zoom", 0.0))])

	# 13. 靶馆地坪分层（问题⑦回归）：馆内 0.06 / 馆外 0，玩家出生贴地坪
	check("馆内地坪 0.06", absf(main.world.ground_height(
		HDData.HALL_CENTER.x, HDData.HALL_CENTER.z) - 0.06) < 0.001)
	check("馆外大地 0.0", absf(main.world.ground_height(0.0, 0.0)) < 0.001)
	check("射位出生贴地坪", absf(main.player.pos.y
		- main.world.ground_height(main.player.pos.x, main.player.pos.z)) < 0.001,
		"pos.y=%.3f" % main.player.pos.y)

	# 14. 士兵比例（问题④回归）：大战场遗产 1.5 已收敛，防回退
	check("士兵 scale 常量 ≤ 1.2", HDSoldiers.SOLDIER_SCALE <= 1.2,
		"SOLDIER_SCALE=%.2f" % HDSoldiers.SOLDIER_SCALE)

	# 15. 雾密度红线（问题②回归）：FOG_MAX 注释"远景可见性红线"，室内外都不得越线
	check("雾常量 ≤ 远景可见性红线", HDWorld.OUTDOOR_FOG <= HDWorld.FOG_MAX
		and HDWorld.INDOOR_FOG <= HDWorld.FOG_MAX)
	check("当前环境雾密度 ≤ 红线", main.world._env.fog_density <= HDWorld.FOG_MAX,
		"density=%.4f" % main.world._env.fog_density)

	# 16. 新枪账本：七把新枪逐把出发进场——满弹 + 备弹=stash 首局礼物满额 + 后坐表落位
	#     （RECOIL 缺键会吃 [0.4,0.2,0.25] 兜底，后坐爆炸；旧语义「每局免费满备弹」
	#     已改弹药经济：首次进弹药经济一次性送满额，此后只买不送）
	for gid in ["mp5", "p90", "uzi", "vector", "m4a1", "akm", "scarh"]:
		var gi: Dictionary = Guns.gun_by_id(gid)
		main._start_mission({"primary": gid, "secondary": "pistol"})
		await frames(8)
		check("新枪 %s 满弹·备弹=stash 礼物满额" % gid,
			main.guns.ammo == int(gi.get("mag", 0))
				and main.guns.reserve == int(HDData.RESERVE.get(gid, -1))
				and main.guns.reserve == main.stash.ammo_of(gid),
			"ammo=%d reserve=%d stash=%d" % [main.guns.ammo, main.guns.reserve,
				main.stash.ammo_of(gid)])
		check("新枪 %s 后坐表落位" % gid, (HDGuns.RECOIL as Dictionary).has(gid))

	# 17. 默认拥有集：恰旧五枪（新枪不白送——GUNS 扩到 12 后的经济红线）
	check("默认拥有恰旧五枪",
		main.stash.guns_owned == ["pistol", "smg", "rifle", "shotgun", "sniper"],
		str(main.stash.guns_owned))

	# 18. 购买与拦截：现金不足不扣款；足额扣款入拥有集；存档往返；已拥有幂等
	main.stash.cash = 100
	check("现金不足购枪拦截", main.stash.buy_gun("vector") == false
		and main.stash.cash == 100 and not main.stash.owns_gun("vector"))
	main.stash.cash = 1800
	check("足额购枪扣款", main.stash.buy_gun("vector") == true
		and main.stash.cash == 0 and main.stash.owns_gun("vector"))
	var st2 := HDStash.new()
	check("购枪存档往返", st2.guns_owned.has("vector"))
	check("已拥有购枪幂等不扣款", main.stash.buy_gun("vector") == true
		and main.stash.cash == 0)

	# 19. 未拥有不可装备：大厅 _load_gun 拦截；买后可装（键盘与点击共用此路径）
	main.stash.guns_owned.erase("scarh")
	main.stash.loadout = {"primary": "rifle", "secondary": "pistol"}
	main.lobby._slot_focus = "primary"
	main.lobby._load_gun("scarh")
	check("未拥有装备拦截", str(main.stash.loadout.get("primary")) == "rifle",
		"primary=%s" % str(main.stash.loadout.get("primary")))
	main.stash.cash = 2400
	main.stash.buy_gun("scarh")
	main.lobby._load_gun("scarh")
	check("买后可装备", str(main.stash.loadout.get("primary")) == "scarh",
		"primary=%s" % str(main.stash.loadout.get("primary")))

	# 20. 极致备弹经济：买弹扣款/不足拦截 + 存档往返（rifle 单价 ₵6/发）
	main.stash.cash = 100
	check("现金不足购弹拦截", main.stash.buy_ammo("rifle", 30) == false
		and main.stash.cash == 100 and main.stash.ammo_of("rifle") == 125)
	main.stash.cash = 200
	check("足额购弹扣款加弹", main.stash.buy_ammo("rifle", 30) == true
		and main.stash.cash == 20 and main.stash.ammo_of("rifle") == 155,
		"cash=%d ammo=%d（125+30=155）" % [main.stash.cash, main.stash.ammo_of("rifle")])
	var st3 := HDStash.new()
	check("购弹存档往返", st3.ammo_inv.get("rifle", -1) == 155)

	# 21. 首次礼物只送一次：抹键后首读=满额礼物；改小再读不再回礼
	main.stash.ammo_inv.erase("vector")
	check("首次入账送满额礼物", main.stash.ammo_of("vector") == 125)
	main.stash.set_ammo("vector", 10)
	check("礼物只送一次", main.stash.ammo_of("vector") == 10)

	# 22. 弹尽拒换弹：备弹 0 出发 → reserve==stash(0)，start_reload 不进换弹动画
	main.stash.set_ammo("vector", 0)
	main._start_mission({"primary": "vector", "secondary": "pistol"})
	await frames(8)
	check("出发 reserve==stash（0）", main.guns.reserve == 0
			and main.guns.reserve == main.stash.ammo_of("vector"),
		"reserve=%d stash=%d" % [main.guns.reserve, main.stash.ammo_of("vector")])
	main.guns.ammo = 5
	main.guns.start_reload()
	check("reserve=0 换弹被拒", main.guns.reloading == 0.0,
		"reloading=%.2f" % main.guns.reloading)

	print("[huodai] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	main.free()
	quit(0 if fails == 0 else 1)
