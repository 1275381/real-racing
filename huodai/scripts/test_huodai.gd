# 回归：烽火地带（Godot 版）核心链路——签到/开箱/命中/换弹掉匣/搜刮/撤离/死亡/靶场/经济
#       + 画质战场回归：开镜倍率语义/靶馆地坪分层/士兵比例/雾密度红线
#       + 交易行页签（唯一购买入口）：页签切换/光标跨段/成交链/出发页·改枪台购买入口回收
#       + 高模顶点红线：MK4 + 步枪册三枪（m4a1/akm/scarh）+ 旧五枪 +
#         机枪册 M250 总顶点 ≥ 8× 低模基线（HDGunLib.POLY_MIN 表）
#       + 持枪（胸前提枪已移除）：出发枪常驻肩射位/无胸前横端/开镜回瞄准位
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s huodai/test_huodai.gd
extends SceneTree

const GUN_LIB := preload("res://scripts/hd_gunlib.gd")   # 高模工具库（路径引用，不走全局类名缓存）

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

	# 16. 新枪账本：八把新枪逐把出发进场——满弹 + 备弹=stash 首局礼物满额 + 后坐表落位
	#     （RECOIL 缺键会吃 [0.4,0.2,0.25] 兜底，后坐爆炸；旧语义「每局免费满备弹」
	#     已改弹药经济：首次进弹药经济一次性送满额，此后只买不送）
	for gid in ["mp5", "p90", "uzi", "vector", "m4a1", "akm", "scarh", "m250"]:
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

	# 23. 交易行页签（唯一购买入口）：键盘 4 切入 · ←/→ 跨段回绕 · 段内 ↑↓ 选条目
	#    （headless 无法点击，购买入口回收用「确认链状态」断言：见 24/25）
	main.lobby.show_lobby()
	check("键盘 4 切交易行页", main.lobby.handle_key(KEY_4)
		and main.lobby._tab == 3)
	check("页签四枚·交易行就位", main.lobby._tab_btns.size() == 4
		and str(main.lobby.TAB_TITLES[3]) == "4 · 交易行")
	main.lobby._market_sec = 0
	main.lobby.handle_key(KEY_RIGHT)
	check("→ 跨段 0→1", main.lobby._market_sec == 1)
	main.lobby.handle_key(KEY_LEFT)
	check("← 跨段 1→0", main.lobby._market_sec == 0)
	main.lobby.handle_key(KEY_LEFT)
	check("← 回绕跨段到 2", main.lobby._market_sec == 2)
	main.lobby.handle_key(KEY_RIGHT)
	check("→ 回绕跨段回 0", main.lobby._market_sec == 0)
	main.lobby._market_gun = 0
	main.lobby.handle_key(KEY_DOWN)
	check("↓ 段内选下把枪", main.lobby._market_gun == 1)
	main.lobby.handle_key(KEY_UP)
	check("↑ 段内选回", main.lobby._market_gun == 0)

	# 24. 出发页购买入口回收：未拥有枪行回车不购不装（现金足额也拦）、B/空格不再消费
	main.stash.cash = 99999
	main.lobby.set_tab(0)
	check("出发页不再消费 B/空格", not main.lobby.handle_key(KEY_B)
		and not main.lobby.handle_key(KEY_SPACE))
	main.lobby._deploy_page = 1
	main.lobby._cur0 = 2   # 第 2 页首行 = MP5（未拥有：18/19 步只购过 vector/scarh）
	main.lobby.handle_key(KEY_ENTER)
	check("出发页回车不购未拥有枪", not main.stash.owns_gun("mp5")
		and main.stash.cash == 99999
		and str(main.stash.loadout.get("primary")) != "mp5")

	# 25. 交易行成交链：回车购枪/购镜 · B 换挡 · 空格按挡位购弹（changed 联动刷新现金）
	main.lobby.handle_key(KEY_4)
	main.lobby._market_sec = 0
	main.lobby._market_gun = 6   # GUNS 表序 6 = MP5 ₵1200（未拥有）
	var cash0: int = main.stash.cash
	main.lobby.handle_key(KEY_ENTER)
	check("交易行回车购枪", main.stash.owns_gun("mp5")
		and main.stash.cash == cash0 - 1200, "cash=%d" % main.stash.cash)
	main.lobby._market_sec = 1
	main.lobby._market_scope = 3   # 交易行②区条目序 3 = 3.5× 光学镜 ₵1800（未拥有）
	cash0 = main.stash.cash
	main.lobby.handle_key(KEY_ENTER)
	check("交易行回车购镜", main.stash.owns_scope("optic35")
		and main.stash.cash == cash0 - 1800, "cash=%d" % main.stash.cash)
	main.lobby.handle_key(KEY_B)   # 购弹挡位 30→90
	check("B 换挡生效（交易行页）", main.lobby._ammo_tier == 1)
	main.lobby._market_sec = 2
	main.lobby._market_ammo_gun = 6   # 给 MP5 购弹（单价 ₵4/发 × 90 = ₵360）
	cash0 = main.stash.cash
	var mp5_ammo0: int = main.stash.ammo_of("mp5")
	main.lobby.handle_key(KEY_SPACE)
	check("空格按挡位购弹", main.stash.ammo_of("mp5") == mp5_ammo0 + 90
		and main.stash.cash == cash0 - 360,
		"ammo=%d cash=%d" % [main.stash.ammo_of("mp5"), main.stash.cash])

	# 26. 高模顶点红线：HDGunLib 重建后的 MK4 枪身根总顶点 ≥ 8× 低模基线
	#     （只数枪身 _smg_build 产物，不含 _finish_gun 镜体件；POLY_MIN 表
	#     随每把枪高模改造逐把入表——后续枪的门槛都进这张表）
	var mk4_root: Node3D = HDGuns._smg_build("mk4")
	var mk4_verts: int = GUN_LIB.count_vertices(mk4_root)
	check("MK4 高模顶点 ≥ POLY_MIN（8× 基线）",
		mk4_verts >= int(GUN_LIB.POLY_MIN["mk4"]),
		"verts=%d min=%d base=%d" % [mk4_verts, int(GUN_LIB.POLY_MIN["mk4"]),
			int(GUN_LIB.POLY_BASE["mk4"])])
	mk4_root.free()

	# 27. 高模顶点红线：步枪册三枪（hd_gun_ar.gd 高模重建）逐把枪身根总顶点
	#     ≥ 8× 低模基线（走 hd_guns._ar_build 分发入口，含 mag_stanag/
	#     mag_banana/mag_wide 独立命名弹匣节点；POLY_MIN/POLY_BASE 见
	#     HDGunLib——门槛与 mk4 同口径 = 盒×24 + 柱×57 的 8 倍）
	for gid in ["m4a1", "akm", "scarh"]:
		var ar_root: Node3D = HDGuns._ar_build(gid)
		var ar_verts: int = GUN_LIB.count_vertices(ar_root)
		check("步枪 %s 高模顶点 ≥ POLY_MIN（8× 基线）" % gid,
			ar_verts >= int(GUN_LIB.POLY_MIN[gid]),
			"verts=%d min=%d base=%d" % [ar_verts, int(GUN_LIB.POLY_MIN[gid]),
				int(GUN_LIB.POLY_BASE[gid])])
		# 弹匣节点契约：三把枪的静置真匣必须是独立命名节点（换弹手沿
		# mag_of 锚点跟随，匣形由枪身件表达——show=false 见 _ar_mag_of）
		var mag_node: Node = ar_root.find_child("mag_*", true, false)
		check("步枪 %s 独立命名弹匣节点在根下" % gid, mag_node != null,
			"node=%s" % (str(mag_node.name) if mag_node != null else "无"))
		ar_root.free()

	# 28. 高模顶点红线：旧五枪（pistol/smg/rifle/shotgun/sniper，原
	#     _build_gun_visual 内联 BoxMesh 分支高模重建）逐把枪身根总顶点
	#     ≥ 8× 低模基线（走 _old5_build 分发入口，只数枪身、不含
	#     _finish_gun 镜体件——口径同 #26/#27；弹匣走 hd_guns 缺省
	#     动画匣契约，无 mag_of 覆盖，故无独立命名弹匣断言）
	for gid in ["pistol", "smg", "rifle", "shotgun", "sniper"]:
		var o5_root: Node3D = HDGuns._old5_build(gid)
		var o5_verts: int = GUN_LIB.count_vertices(o5_root)
		check("旧五枪 %s 高模顶点 ≥ POLY_MIN（8× 基线）" % gid,
			o5_verts >= int(GUN_LIB.POLY_MIN[gid]),
			"verts=%d min=%d base=%d" % [o5_verts, int(GUN_LIB.POLY_MIN[gid]),
				int(GUN_LIB.POLY_BASE[gid])])
		o5_root.free()

	# 29. 高模顶点红线：冲锋枪册四枪（mp5/p90/uzi/vector，HDGunLib 高模重建）
	#     逐把枪身根总顶点 ≥ 8× 低模基线（走 _smg_build 分发入口，口径同
	#     #26/#27/#28；mp5/p90 的静置真匣是独立命名弹匣节点（mag_curved/
	#     mag_top，mag_of show=false）；uzi/vector 匣插握把、由动画匣表达
	#     （show=true）故无静置建模件、无节点断言）
	for gid in ["mp5", "p90", "uzi", "vector"]:
		var smg_root: Node3D = HDGuns._smg_build(gid)
		var smg_verts: int = GUN_LIB.count_vertices(smg_root)
		check("冲锋枪 %s 高模顶点 ≥ POLY_MIN（8× 基线）" % gid,
			smg_verts >= int(GUN_LIB.POLY_MIN[gid]),
			"verts=%d min=%d base=%d" % [smg_verts, int(GUN_LIB.POLY_MIN[gid]),
				int(GUN_LIB.POLY_BASE[gid])])
		if not bool(HDGuns._smg_mag_of(gid)["show"]):
			var mag_node: Node = smg_root.find_child("mag_*", true, false)
			check("冲锋枪 %s 独立命名弹匣节点在根下" % gid, mag_node != null,
				"node=%s" % (str(mag_node.name) if mag_node != null else "无"))
		smg_root.free()

	# 29b. 高模顶点红线：机枪册 M250（m250，hd_gun_lmg.gd 高模重建）枪身根
	#      总顶点 ≥ 8× 低模基线（走 _lmg_build 分发入口，口径同 #26/#27/#29；
	#      75 发弹链袋是独立命名弹匣节点 mag_pouch、动画匣隐 show=false，
	#      契约同 MK4「匣形由枪身件表达」先例）
	var lmg_root: Node3D = HDGuns._lmg_build("m250")
	var lmg_verts: int = GUN_LIB.count_vertices(lmg_root)
	check("M250 高模顶点 ≥ POLY_MIN（8× 基线）",
		lmg_verts >= int(GUN_LIB.POLY_MIN["m250"]),
		"verts=%d min=%d base=%d" % [lmg_verts, int(GUN_LIB.POLY_MIN["m250"]),
			int(GUN_LIB.POLY_BASE["m250"])])
	var lmg_mag: Node = lmg_root.find_child("mag_*", true, false)
	check("M250 独立命名弹链袋节点在根下", lmg_mag != null
		and str(lmg_mag.name) == "mag_pouch",
		"node=%s" % (str(lmg_mag.name) if lmg_mag != null else "无"))
	check("M250 动画匣隐（弹链袋由枪身件表达）",
		not bool(HDGuns._lmg_mag_of("m250")["show"]))
	lmg_root.free()

	# 30. 大坝分区（搜打撤第三区）：装配节点/容器点 13/巡逻点 7/品质权重/矩形分区/
	#     坝体碰撞 wall_hit（前墙 12m·开洞抵背墙 18m·溢流段高位 24m）/幂等/第二撤离
	check("大坝两装配节点挂在 world 下", main.world.dam != null
		and main.world.dam_base != null
		and main.world.dam.get_parent() == main.world
		and main.world.dam_base.get_parent() == main.world)
	var dam_box_n := 0
	for s_v in main.world.container_spots:
		var s: Dictionary = s_v
		if str(s.get("zone")) == "dam":
			dam_box_n += 1
	check("坝区容器点位 13（红线 ∈[10,14]）", dam_box_n == 13, "n=%d" % dam_box_n)
	var dam_pt_n := 0
	for s_v in main.world.patrol_spots:
		var s: Dictionary = s_v
		if str(s.get("zone")) == "dam":
			dam_pt_n += 1
	check("坝区巡逻点 7（红线 ∈[6,8]）", dam_pt_n == 7, "n=%d" % dam_pt_n)
	main.world.build()   # 重复 build 幂等（hd_world._built 护栏）：坝区点位不得翻倍
	var dam_box_n2 := 0
	for s_v in main.world.container_spots:
		var s2: Dictionary = s_v
		if str(s2.get("zone")) == "dam":
			dam_box_n2 += 1
	check("重复 build() 幂等（坝区容器点不翻倍）", dam_box_n2 == 13,
		"n=%d" % dam_box_n2)
	var dam_w: Array = HDData.RARITY_W["dam"]
	var dam_w_sum := 0
	for x in dam_w:
		dam_w_sum += int(x)
	check("坝区品质权重入表且和=100", dam_w_sum == 100, "sum=%d" % dam_w_sum)
	check("zone_at 大坝矩形裁决（坝内 dam·中心/过渡不受蚀）",
		main.world.zone_at(28.0, -95.0) == "dam"
		and main.world.zone_at(93.0, -94.0) == "dam"
		and main.world.zone_at(0.0, 0.0) == "center"
		and main.world.zone_at(96.0, 0.0) == "mid")
	var ex_l: Array = main.world.extract_list()
	check("第二撤离点入列（93,-94）", ex_l.size() == 2
		and (ex_l[1] as Vector3).distance_to(HDData.DAM_EXTRACT_POS) < 0.01,
		"n=%d" % ex_l.size())
	var wh_wall: float = main.world.wall_hit(Vector3(0.0, 2.0, -100.0),
		Vector3(0.0, 0.0, -1.0), 300.0)
	check("坝体碰撞 wall_hit·廊道前墙 12m", absf(wh_wall - 12.0) < 0.5,
		"d=%.1f" % wh_wall)
	var wh_hole: float = main.world.wall_hit(Vector3(10.0, 4.0, -100.0),
		Vector3(0.0, 0.0, -1.0), 300.0)
	check("坝体碰撞 wall_hit·开洞穿入抵坝基背墙 18m", absf(wh_hole - 18.0) < 0.5,
		"d=%.1f" % wh_hole)
	var wh_ov: float = main.world.wall_hit(Vector3(-4.0, 30.0, -100.0),
		Vector3(0.0, 0.0, -1.0), 300.0)   # x=-4 避开 x=0 闸墩（墩盒 y30 处 22.2m 先挡）
	check("坝体碰撞 wall_hit·溢流段高位 24m", absf(wh_ov - 24.0) < 0.5,
		"d=%.1f" % wh_ov)
	check("坝区障碍批量注册（全图 ≥140 条）", main.world.obstacles.size() >= 140,
		"n=%d" % main.world.obstacles.size())
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	main.player.enter(main.world.extract2_pos)
	main._bag_value = 100.0
	main._extract_t = 4.95
	await frames(10)
	check("第二撤离点读条撤出 WIN（大坝广场）", main.hud.result_visible
		and main.stash.stats["extracts"] == 2,
		"extracts=%d" % main.stash.stats["extracts"])

	# §探头（Q/E 左右）：按住右探头 → 相机侧移+侧滚到位；松开回中；左同理对称
	var cam0: Vector3 = main.player.cam.global_position
	Input.action_press("hd_lean_right")
	for i in 12:
		main.player.update(0.05)
	var dlean: Vector3 = main.player.cam.global_position - cam0
	var lat_r: float = Vector2(dlean.x, dlean.z).length()
	check("右探头到位（lean_cur≈+1，侧移 ≥0.35m）",
		main.player.lean_cur > 0.9 and lat_r > 0.35,
		"lean=%.2f lat=%.2fm" % [main.player.lean_cur, lat_r])
	check("右探头侧滚（z≈-11°，头右歪）",
		absf(rad_to_deg(main.player.cam.rotation.z) + 11.0) < 1.5,
		"z=%.1f°" % rad_to_deg(main.player.cam.rotation.z))
	Input.action_release("hd_lean_right")
	for i in 12:
		main.player.update(0.05)
	check("松开探头回中", absf(main.player.lean_cur) < 0.05
		and absf(main.player.cam.rotation.z) < 0.001,
		"lean=%.2f" % main.player.lean_cur)
	Input.action_press("hd_lean_left")
	for i in 12:
		main.player.update(0.05)
	check("左探头对称（lean_cur≈-1，z≈+11°）",
		main.player.lean_cur < -0.9 and rad_to_deg(main.player.cam.rotation.z) > 9.0,
		"lean=%.2f z=%.1f°" % [main.player.lean_cur,
			rad_to_deg(main.player.cam.rotation.z)])
	Input.action_release("hd_lean_left")
	main.player.update(0.05)

	# §持枪姿态（胸前提枪已移除）：出发后枪常驻肩射位（GUN_HIP 锚点），
	# 无胸前横端/横晃/双手——开镜对位照常
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(8)
	var c_h: Node3D = main.guns._guns["primary"]["holder"]
	check("出发后枪在肩射位（GUN_HIP 锚点）", c_h.position.distance_to(
		Vector3(0.26, -0.22, -0.55)) < 0.02,
		"pos=%s" % str(c_h.position))
	check("无胸前横置（滚转 ≈3°）", absf(c_h.rotation_degrees.z - 3.0) < 1.0,
		"z=%.1f°" % c_h.rotation_degrees.z)
	# 开镜：枪回 ADS 瞄准位（枪顶 AABB 对准星正下方，onfoot 同款）
	Input.action_press("hd_scope")
	var ads_ok := false
	for i in 150:
		main.player.update(0.016)
		main.guns.update(0.016)
		if main.player.ads >= 0.99:
			ads_ok = true
			break
	Input.action_release("hd_scope")
	var hip_expect := Vector3(
			-HDGuns.GUN_SCALE * float(main.guns._guns["primary"]["cx"]),
			-0.012 - HDGuns.GUN_SCALE * float(main.guns._guns["primary"]["top"]),
			HDGuns.GUN_ADS_Z)
	check("开镜后枪回瞄准位", ads_ok
		and c_h.position.distance_to(hip_expect) < 0.01,
		"d=%.3f" % c_h.position.distance_to(hip_expect))

	print("[huodai] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	main.free()
	quit(0 if fails == 0 else 1)
