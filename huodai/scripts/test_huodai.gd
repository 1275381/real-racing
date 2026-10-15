# 回归：烽火地带（Godot 版）核心链路——签到/开箱/命中/换弹掉匣/搜刮/撤离/死亡/靶场/经济
#       + 实战/靶场语义分流：靶场练习弹免费零消耗（绝不回写库存）+ 暂停菜单模式分化文案
#       + 画质战场回归：开镜倍率语义/靶馆地坪分层/士兵比例/雾密度红线
#       + 交易行页签（唯一购买入口）：页签切换/光标跨段/成交链/出发页·改枪台购买入口回收
#       + 高模顶点红线：MK4 + 步枪册三枪（m4a1/akm/scarh）+ 旧五枪 +
#         机枪册 M250 总顶点 ≥ 8× 低模基线（HDGunLib.POLY_MIN 表）
#       + 持枪（胸前提枪已移除）：出发枪常驻肩射位/无胸前横端/开镜回瞄准位
#       + 红点镜 ADS 瞄准线：镜窗改大（60×45mm）+ 窗中心过屏幕中心——
#         HUD 中心红点必须落进玻璃窗内（用户反馈「准星飞出镜子外」）
#       + 拟真枪声分层回归（用户反馈「现在的枪声不拟真」）：四层合成
#         （click/crack/boom/tail）14 枪流/时长分级/峰值/过零率/每发随机
# 运行：cd huodai && /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s scripts/test_huodai.gd
#      （以 huodai/ 为工作目录跑 -s scripts/test_huodai.gd；仓库根视角旧路径 -s huodai/test_huodai.gd 已废）
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

## 递归收集节点树下全部 Label 文本（暂停菜单文案断言用——菜单标签不设公开 API，遍历只读）
func _menu_labels_text(n: Node) -> String:
	var out := ""
	for c in n.get_children():
		if c is Label:
			out += (c as Label).text + "\n"
		out += _menu_labels_text(c)
	return out

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

	# 10b. 靶场暂停菜单文案（模式分化）：标题「靶场暂停」+「离开靶场」就位，
	#      不出现「行动/战斗/放弃」（用户反馈：靶场哪来的「放弃战斗」）——
	#      须在离场前断言：_back_to_lobby 会把菜单复位回实战文案
	var menu_txt := _menu_labels_text(main.hud._menu)
	check("靶场菜单含「靶场暂停/离开靶场」", menu_txt.contains("靶场暂停")
			and menu_txt.contains("离开靶场"))
	check("靶场菜单无「行动/战斗/放弃」字样", not menu_txt.contains("行动")
			and not menu_txt.contains("战斗") and not menu_txt.contains("放弃"))

	# 10c. 靶场弹药免费（实战/靶场语义分流）：快照库存 → 打空整匣 → 换弹 →
	#      再打数发 → 离场回大厅 → 库存逐发零消耗。练习弹绝不回写库存——
	#      回写=靶场无限刷弹漏洞（经济红线）；弹药 HUD 靶场模式备弹显示 ∞
	var rifle_snap: int = main.stash.ammo_of("rifle")
	var pistol_snap: int = main.stash.ammo_of("pistol")
	check("靶场练习备弹=固定大额（非库存数）",
		main.guns.reserve == main.RANGE_RESERVE
			and main.guns.reserve != rifle_snap,
		"reserve=%d stash=%d" % [main.guns.reserve, rifle_snap])
	for i in main.guns.ammo:
		main.guns.try_fire()
		main.guns.fire_cd = 0.0   # 绕射速间隔：账目回归不考手感
	check("靶场打空整匣", main.guns.ammo == 0, "ammo=%d" % main.guns.ammo)
	main.guns.start_reload()
	for i in 140:
		main.guns.update(0.016)
	check("靶场换弹照常（练习弹补匣）", main.guns.ammo == 30
			and main.guns.reserve == main.RANGE_RESERVE - 30,
		"ammo=%d reserve=%d" % [main.guns.ammo, main.guns.reserve])
	for i in 7:
		main.guns.try_fire()
		main.guns.fire_cd = 0.0
	main._back_to_lobby()
	await frames(10)
	check("靶场离场库存逐发零消耗", main.stash.ammo_of("rifle") == rifle_snap
			and main.stash.ammo_of("pistol") == pistol_snap,
		"rifle=%d/%d pistol=%d/%d" % [main.stash.ammo_of("rifle"), rifle_snap,
			main.stash.ammo_of("pistol"), pistol_snap])
	check("靶场离场回大厅模式复位", main.mode == main.Mode.LOBBY
			and main.lobby.lobby_visible)

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

	# 23. 交易行页签（唯一购买入口）：键盘 3 切入 · ←/→ 跨段回绕（域 4）· 段内 ↑↓ 选条目
	#    （headless 无法点击，购买入口回收用「确认链状态」断言：见 24/25）
	main.lobby.show_lobby()
	check("键盘 3 切交易行页", main.lobby.handle_key(KEY_3)
		and main.lobby._tab == 2)
	check("页签三枚·交易行就位", main.lobby._tab_btns.size() == 3
		and main.lobby.TAB_TITLES == ["出发大厅", "改枪台", "交易行"])
	check("KEY_4 不再消费（删键后落默认 return false）", not main.lobby.handle_key(KEY_4))
	main.lobby._market_sec = 0
	main.lobby.handle_key(KEY_RIGHT)
	check("→ 跨段 0→1", main.lobby._market_sec == 1)
	main.lobby.handle_key(KEY_LEFT)
	check("← 跨段 1→0", main.lobby._market_sec == 0)
	main.lobby.handle_key(KEY_LEFT)
	check("← 回绕跨段到 3（④ 仓库，域 4）", main.lobby._market_sec == 3)
	main.lobby.handle_key(KEY_RIGHT)
	check("→ 回绕跨段回 0（④→①）", main.lobby._market_sec == 0)
	main.lobby._market_gun = 0
	main.lobby.handle_key(KEY_DOWN)
	check("↓ 段内选下把枪", main.lobby._market_gun == 1)
	main.lobby.handle_key(KEY_UP)
	check("↑ 段内选回", main.lobby._market_gun == 0)

	# 24. 出发页购买入口回收：未拥有枪行回车不购不装（现金足额也拦）、B/空格不再消费
	#     （静默不消费——不弹「←→ 切③区」类误导指路，_hint_label 保持空）
	main.stash.cash = 99999
	main.lobby.set_tab(0)
	main.lobby._hint_label.text = ""
	check("出发页不再消费 B/空格", not main.lobby.handle_key(KEY_B)
		and not main.lobby.handle_key(KEY_SPACE))
	check("出发页 B/空格静默无指路（防误导）", main.lobby._hint_label.text == "")
	main.lobby._deploy_page = 1
	main.lobby._cur0 = 2   # 第 2 页首行 = MP5（未拥有：18/19 步只购过 vector/scarh）
	main.lobby.handle_key(KEY_ENTER)
	check("出发页回车不购未拥有枪", not main.stash.owns_gun("mp5")
		and main.stash.cash == 99999
		and str(main.stash.loadout.get("primary")) != "mp5")
	check("出发页未拥有指路报键位（按 3）", main.lobby._hint_label.text.contains("按 3 进交易行"))

	# 25. 交易行成交链：回车购枪/购镜 · B 换挡 · 空格按挡位购弹（changed 联动刷新现金）
	main.lobby.handle_key(KEY_3)
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
	main.lobby._market_sec = 2   # B 段守卫前插：须在③区内 B 才消费（:311 已置 sec=1）
	main.lobby.handle_key(KEY_B)   # 购弹挡位 30→90
	check("B 换挡生效（③ 区内）", main.lobby._ammo_tier == 1)
	main.lobby._market_ammo_gun = 6   # 给 MP5 购弹（单价 ₵4/发 × 90 = ₵360）
	cash0 = main.stash.cash
	var mp5_ammo0: int = main.stash.ammo_of("mp5")
	main.lobby.handle_key(KEY_SPACE)
	check("空格按挡位购弹", main.stash.ammo_of("mp5") == mp5_ammo0 + 90
		and main.stash.cash == cash0 - 360,
		"ammo=%d cash=%d" % [main.stash.ammo_of("mp5"), main.stash.cash])

	# 25b. B/空格段守卫（真陷阱修复）：交易行①区按空格不消费、不买弹，弹指路 hint
	main.lobby._market_sec = 0
	cash0 = main.stash.cash
	mp5_ammo0 = main.stash.ammo_of("mp5")
	check("交易行①区空格不消费且不买弹", not main.lobby.handle_key(KEY_SPACE)
		and main.stash.cash == cash0 and main.stash.ammo_of("mp5") == mp5_ammo0)
	check("交易行他段买弹指路 hint", main.lobby._hint_label.text.contains("③ 极致备弹"))
	main.lobby.set_tab(1)   # 改枪台页：B/空格静默 return false（到不了③区，指路是误导）
	main.lobby._hint_label.text = ""
	check("改枪台页 B/空格静默无指路", not main.lobby.handle_key(KEY_B)
		and not main.lobby.handle_key(KEY_SPACE)
		and main.lobby._hint_label.text == "")

	# 25c. 改枪台：狙击守卫（自带 6× 原厂镜不可改装——防「装了白装+假成功提示」）·
	#      左列回车一步预安装（跳列自动选镜）· 镜链装配+单持迁移 · 去购买一键跳交易行
	main.stash.buy_scope("holo")   # 先拥有：守卫拦的是「装」，不是「没镜可试」
	main.lobby.set_tab(1)
	main.lobby._gun_idx = 4        # GUNS 表序 4 = 狙击步枪（自带 6× 原厂镜）
	main.lobby._bench_col = 1
	main.lobby._scope_idx = 1      # 右列条目序 1 = holo（已拥有未装）
	main.lobby._hint_label.text = ""
	main.lobby._bench_confirm()
	check("狙击枪换装被守卫拦截", str(main.stash.scope_fit.get("sniper", "iron")) != "holo",
		"fit=%s" % str(main.stash.scope_fit.get("sniper", "iron")))
	check("狙击拦截 hint 明示不可改装", main.lobby._hint_label.text.contains("不可改装"))
	check("狙击右列行内 tag 同步守卫（iron=原厂镜/已拥有镜=不可改装）",
		main.lobby._scope_tag("sniper", "iron", {"id": "iron"}) == "默认 · 原厂镜"
		and main.lobby._scope_tag("sniper", "holo", {"id": "holo"}).contains("不可改装"))
	var sn_act = main.lobby._mk_bench_action("sniper", {"id": "holo"}, 1)
	check("狙击行内动作为置灰「原厂镜专属」标签（非可点钮）",
		sn_act is Label and (sn_act as Label).text == "原厂镜专属")
	main.lobby._gun_idx = 2        # M7 战斗步枪（非自带镜）
	main.lobby._bench_col = 0
	main.lobby._bench_confirm()    # 左列回车=一步预安装：跳右列自动选镜
	check("改枪台左列回车跳右列", main.lobby._bench_col == 1)
	check("跳列自动落「第一个已拥有且未装」的镜（holo=右列序 1）",
		main.lobby._scope_idx == 1, "scope_idx=%d" % main.lobby._scope_idx)
	main.lobby._gun_idx = 3        # 一步预安装链路：给霰弹枪装已拥有 holo
	main.lobby._on_bench_equip_pressed(1)
	check("一步预安装 scope_fit 生效", str(main.stash.scope_fit.get("shotgun", "")) == "holo",
		"fit=%s" % str(main.stash.scope_fit.get("shotgun", "")))
	main.lobby._gun_idx = 2        # 同镜装他枪 → 单持自动从霰弹枪卸下
	main.lobby._on_bench_equip_pressed(1)
	check("单持迁移生效", str(main.stash.scope_fit.get("rifle", "")) == "holo"
		and str(main.stash.scope_fit.get("shotgun", "")) == "iron",
		"rifle=%s shotgun=%s" % [str(main.stash.scope_fit.get("rifle", "")),
			str(main.stash.scope_fit.get("shotgun", ""))])
	main.lobby._goto_market_scope(1)   # 未拥有镜「去购买」：一键跳交易行②区该行
	check("去购买跳转三元组（交易行②区该镜行）", main.lobby._tab == 2
		and main.lobby._market_sec == 1 and main.lobby._market_scope == 1)

	# 25d. 交易行④ 仓库·战利品段：种 14 件（超 BACKPACK_MAX=12，deposit 无封顶）→
	#      滚动渲染不炸 → 回车整包一次清 + 加钱 → 空仓沿用「仓库空空如也」提示
	main.stash.items.clear()
	for i in 14:
		main.stash.items.append({"uid": "test_wh_%02d" % i, "name": "测试战利品",
			"icon": "", "rarity": 1, "value": 100})
	main.lobby._market_sec = 3
	main.lobby._refresh_all()   # ④段两行滚动窗口渲染路径（14 件超窗）不炸
	check("④段 14 件滚动渲染", main.lobby._pages[2].get_child_count() > 0)
	cash0 = main.stash.cash
	main.lobby.handle_key(KEY_ENTER)
	check("④段回车一键变卖（超 12 件整包清+加钱）", main.stash.items.is_empty()
		and main.stash.cash == cash0 + 1400,
		"cash=%d" % main.stash.cash)
	main.lobby.handle_key(KEY_ENTER)
	check("空仓回车沿用「仓库空空如也」提示", main.lobby._hint_label.text.contains("仓库空空如也"))

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

	# 29c. 持枪对齐红线（用户反馈「每把枪拿起来都不对齐，只有 MK4 对」）：
	#      全枪册走 _build_gun_visual（含 HOLD_DELTA 出厂平移）后，握把顶锚
	#      （grip_hold 节点位）必须统一落在 MK4 基准 (0,-0.022,-0.0018) ±1.5mm
	#      ——14 把枪在手里共用同一持握点，错位感消除；表值错/工厂改动漂移
	#      都会在这里现形
	var hold_bad: Array = []
	for g_def in Guns.GUNS:
		var h_gid: String = str(g_def["id"])
		var h_root: Node3D = main.guns._build_gun_visual(h_gid)
		var h_grips: Array = h_root.find_children("grip_hold", "Node3D", true, false)
		if h_grips.is_empty() or (h_grips[0] as Node3D).position.distance_to(
				Vector3(0, -0.022, -0.0018)) > 0.0015:
			hold_bad.append("%s@%s" % [h_gid,
				str((h_grips[0] as Node3D).position) if not h_grips.is_empty() else "无grip"])
		h_root.free()
	check("全枪册持握锚统一到 MK4 基准（±1.5mm）", hold_bad.is_empty(),
		str(hold_bad))

	# 29d. 拟真枪声分层回归（用户反馈「现在的枪声不拟真」；锚点：上承 29c
	#      持握锚、下接 30 大坝分区）。枪声已重做为四层合成（click 机械瞬态/
	#      crack 膛口爆裂/boom 低频/tail 混响尾，见 hd_audio.gd 类头），红线：
	#      ① ensure 预生成全 14 枪流（SHOT_TUNE 不得缺枪，缺了只能懒生成兜底）
	#      ② 时长分级 sniper > rifle > pistol 且全部 ≤0.5s
	#      ③ 波形峰值 >0.2（非哑弹：归一后 0.88×gain，最短的枪也远过线）
	#      ④ 过零率 >3× 纯正弦（证明高频 crack 成分在场——只剩 boom 正弦的
	#        回归约 440/s 会当场撞线）
	#      ⑤ play_shot 每发随机：轮换池刚用的播放器 pitch ∈[0.94,1.06]、
	#        音量在基准 ±1.5dB 内（真枪每发都不同）
	var audio = main.guns.audio
	audio.ensure()   # 幂等：已建则跳过；无论冷热路径都保证 14 枪预生成
	var miss_pre: Array = []
	for g_def in Guns.GUNS:
		if not audio._shots.has(str(g_def["id"])):
			miss_pre.append(str(g_def["id"]))
	check("枪声 ensure 预生成全 14 枪流（SHOT_TUNE 不缺枪）", miss_pre.is_empty(),
		str(miss_pre))
	var shot_len := {}
	var shot_peak := {}
	var shot_zcr := {}
	for g_def in Guns.GUNS:
		var a_gid: String = str(g_def["id"])
		var a_wav: AudioStreamWAV = audio._shot_stream(a_gid)
		check("枪声流存在：%s" % a_gid, a_wav != null)
		shot_len[a_gid] = a_wav.get_length()
		# 逐样本解码：峰值（哑弹判定）+ 过零率（高频成分判定）
		var a_bytes: PackedByteArray = a_wav.data
		var a_n := a_bytes.size() / 2
		var a_peak := 0.0
		var a_zcr := 0
		var a_prev := 0.0
		for i in a_n:
			var v := float(a_bytes.decode_s16(i * 2)) / 32768.0
			a_peak = maxf(a_peak, absf(v))
			if i > 0 and (v >= 0.0) != (a_prev >= 0.0):
				a_zcr += 1
			a_prev = v
		shot_peak[a_gid] = a_peak
		shot_zcr[a_gid] = float(a_zcr) / maxf(a_wav.get_length(), 0.001)
	# 纯正弦参照：220Hz 同采样率测过零率（≈440/s）——比实测更防「想当然」
	var sine_n := 2205
	var sine_zcr := 0
	var sine_prev := 0.0
	for i in sine_n:
		var sv := sin(TAU * 220.0 * float(i) / 22050.0)
		if i > 0 and (sv >= 0.0) != (sine_prev >= 0.0):
			sine_zcr += 1
		sine_prev = sv
	var sine_rate := float(sine_zcr) / (float(sine_n) / 22050.0)
	var zcr_bad: Array = []
	var peak_bad: Array = []
	var len_bad: Array = []
	for a_gid in shot_len:
		if float(shot_zcr[a_gid]) < sine_rate * 3.0:
			zcr_bad.append("%s=%.0f/s" % [a_gid, shot_zcr[a_gid]])
		if float(shot_peak[a_gid]) <= 0.2:
			peak_bad.append("%s=%.2f" % [a_gid, shot_peak[a_gid]])
		if float(shot_len[a_gid]) > 0.5:
			len_bad.append("%s=%.3f" % [a_gid, shot_len[a_gid]])
	check("14 枪过零率 >3× 纯正弦 %.0f/s（高频 crack 在场）" % sine_rate,
		zcr_bad.is_empty(), str(zcr_bad))
	check("14 枪波形峰值 >0.2（非哑弹）", peak_bad.is_empty(), str(peak_bad))
	check("14 枪总时长 ≤0.5s", len_bad.is_empty(), str(len_bad))
	check("时长分级 sniper > rifle > pistol",
		float(shot_len["sniper"]) > float(shot_len["rifle"])
			and float(shot_len["rifle"]) > float(shot_len["pistol"]),
		"sniper=%.3f rifle=%.3f pistol=%.3f" % [shot_len["sniper"],
			shot_len["rifle"], shot_len["pistol"]])
	# 每发随机：play_shot 轮走 _idx 前一位播放器——回读那个播放器的
	# pitch_scale / volume_db 落不落在随机域
	var used_idx: int = audio._idx
	audio.play_shot("rifle")
	var used: AudioStreamPlayer = audio._pool[
		(used_idx - 1 + audio._pool.size()) % audio._pool.size()]
	var rifle_gain: float = float(HDAudio.SHOT_TUNE["rifle"]["gain"])
	var base_db: float = linear_to_db(maxf(rifle_gain * 0.9, 0.05))
	check("play_shot 移调落随机域 [0.94,1.06]",
		used.pitch_scale >= 0.94 and used.pitch_scale <= 1.06,
		"pitch=%.3f" % used.pitch_scale)
	check("play_shot 音量抖动 ±1.5dB", absf(used.volume_db - base_db) <= 1.51,
		"db=%.2f base=%.2f" % [used.volume_db, base_db])

	# 29e. 点击=装备（用户「点击等于装备」）：出发页/改枪台行点击不再「只选中」——
	#      合成左键点击直接沿既有确认链收敛：出发页当页枪行=选中+装入聚焦槽
	#      （loadout 变化）、改枪台右列已拥有镜=选中+直接换装（scope_fit 变化）；
	#      交易行例外维持只选中（防误购：现金/拥有数不变）
	main.lobby.set_tab(0)
	main.lobby._slot_focus = "secondary"   # 聚焦副槽：主槽 scarh 应保持不动（断言装入目标槽）
	main.lobby._deploy_page = 0
	main.lobby._cur0 = 0
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.pressed = true
	mb.button_index = MOUSE_BUTTON_LEFT
	main.lobby._on_deploy_row_input(mb, 0, 3)   # 当页枪行序 3 → 表序 1 = 汤姆逊（已拥有未装）
	check("出发页点击行=直接装备（loadout 变化）",
		str(main.stash.loadout.get("secondary")) == "smg"
			and str(main.stash.loadout.get("primary")) == "scarh"
			and main.lobby._cur0 == 3,
		"primary=%s secondary=%s" % [str(main.stash.loadout.get("primary")),
			str(main.stash.loadout.get("secondary"))])
	main.lobby.set_tab(1)
	main.lobby._gun_idx = 2        # M7 战斗步枪（表序 2，非自带镜；当前装 holo=25c 遗留）
	main.lobby._bench_col = 1
	main.lobby._scope_idx = 0
	var mb2: InputEventMouseButton = InputEventMouseButton.new()
	mb2.pressed = true
	mb2.button_index = MOUSE_BUTTON_LEFT
	main.lobby._on_bench_row_input(mb2, 1, 2)   # 右列序 2 = 红点镜（已拥有未装）
	check("改枪台右列点击=直接换装（scope_fit 变化）",
		str(main.stash.scope_fit.get("rifle", "")) == "reddot"
			and main.lobby._bench_col == 1 and main.lobby._scope_idx == 2,
		"fit=%s" % str(main.stash.scope_fit.get("rifle", "")))
	# 还原 rifle 装配回 25c 遗留的 holo：下游 §持枪姿态 的「开镜回瞄准位」断言按
	# top 公式（holo 拓扑）写死，reddot 走「窗中心过屏幕中心」aim_y 公式——
	# 不还原会把本段的状态泄漏进那条几何断言（实测 d=0.026 撞线）
	main.stash.equip_scope("rifle", "holo")
	main.lobby.set_tab(2)
	main.lobby._market_sec = 0
	main.lobby._market_gun = 0
	var cash_m: int = main.stash.cash
	var owned_m: int = main.stash.guns_owned.size()
	var mb3: InputEventMouseButton = InputEventMouseButton.new()
	mb3.pressed = true
	mb3.button_index = MOUSE_BUTTON_LEFT
	main.lobby._on_market_row_input(mb3, 0, 7)   # 表序 7 = P90（未拥有，够钱买——负断言有意义）
	check("交易行行点击只选中不购买（现金/拥有数不变）",
		main.lobby._market_sec == 0 and main.lobby._market_gun == 7
			and not main.stash.owns_gun("p90")
			and main.stash.cash == cash_m and main.stash.guns_owned.size() == owned_m,
		"cash=%d owned=%d" % [main.stash.cash, main.stash.guns_owned.size()])

	# 30. 大坝分区（搜打撤第三区）：装配节点/容器点 13/巡逻点 7/品质权重/矩形分区/
	#     坝体碰撞 wall_hit（前墙 12m·开洞抵背墙 18m·溢流段高位 24m）/幂等/第二撤离
	#     + 四新区连坐（军营/大电/水泥厂/游客中心）：dam_zones 装配/总数 58/31/
	#     障碍 ≥268（实测 279=209+新区 63+新 loot 盒 7）/四区 wall_hit/zone_at 采样
	check("大坝三装配节点挂在 world 下（DAM→BASE→ZONES）", main.world.dam != null
		and main.world.dam_base != null
		and main.world.dam_zones != null
		and main.world.dam.get_parent() == main.world
		and main.world.dam_base.get_parent() == main.world
		and main.world.dam_zones.get_parent() == main.world)
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
	# 四新区总数连坐：容器 51+7=58 / 巡逻 26+5=31（本 session 无头实测钉死）
	check("容器点总数 58（51+四新区 7）", main.world.container_spots.size() == 58,
		"n=%d" % main.world.container_spots.size())
	check("巡逻点总数 31（26+四新区 5）", main.world.patrol_spots.size() == 31,
		"n=%d" % main.world.patrol_spots.size())
	main.world.build()   # 重复 build 幂等（hd_world._built 护栏）：坝区点位不得翻倍
	var dam_box_n2 := 0
	for s_v in main.world.container_spots:
		var s2: Dictionary = s_v
		if str(s2.get("zone")) == "dam":
			dam_box_n2 += 1
	check("重复 build() 幂等（坝区容器点不翻倍）", dam_box_n2 == 13,
		"n=%d" % dam_box_n2)
	check("重复 build() 幂等（新区总数不翻倍：容器 58/巡逻 31）",
		main.world.container_spots.size() == 58
			and main.world.patrol_spots.size() == 31,
		"c=%d p=%d" % [main.world.container_spots.size(),
			main.world.patrol_spots.size()])
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
	check("坝区障碍批量注册（全图 ≥268 条：209+新区 83+新 loot 盒 7=299 实测）",
		main.world.obstacles.size() >= 268,
		"n=%d" % main.world.obstacles.size())
	# 四区 wall_hit 各 1 条（期望值按落成几何钉死、±0.5 容差对齐 :575 先例；
	# 采 样 视 线 逐 一 让 开 中 途 障 碍：军营视线 z=−24 让开披屋 z∈[−19,−14]、
	# 大电 z=−17.5 让开 wreck (95,−20) AABB z∈[−21,−19] 与 loot 盒 (107,−19) 半径、
	# 水泥 z=18 正对最西仓（勿用主楼向采样——先穿主楼名实不符）、
	# 游客 z=40 避开南墙线 42.5 与石阶 z∈[33.9,35.5] 的边界浮点敏感）
	var wh_camp_w: float = main.world.wall_hit(Vector3(-142.0, 1.55, -24.0),
			Vector3(1.0, 0.0, 0.0), 300.0)
	check("军营西围墙 wall_hit ≈11.6m", absf(wh_camp_w - 11.6) < 0.5,
		"d=%.1f" % wh_camp_w)
	var wh_sub_c: float = main.world.wall_hit(Vector3(88.0, 2.0, -17.5),
			Vector3(1.0, 0.0, 0.0), 300.0)
	check("大电主控楼西墙 wall_hit ≈16.0m（中途围栏不注册·桁架柱让开）",
		absf(wh_sub_c - 16.0) < 0.5, "d=%.1f" % wh_sub_c)
	var wh_cem_s: float = main.world.wall_hit(Vector3(-128.0, 2.0, 18.0),
			Vector3(1.0, 0.0, 0.0), 300.0)
	check("水泥厂最西筒仓 wall_hit ≈8.8m", absf(wh_cem_s - 8.8) < 0.5,
		"d=%.1f" % wh_cem_s)
	var wh_vis_w: float = main.world.wall_hit(Vector3(62.0, 1.55, 40.0),
			Vector3(1.0, 0.0, 0.0), 300.0)
	check("游客中心主翼西墙 wall_hit ≈14.0m", absf(wh_vis_w - 14.0) < 0.5,
		"d=%.1f" % wh_vis_w)
	# 四区 zone_at 采样（本 session 无头实测：军营板房主体 wild、大电西院 mid、
	# 水泥厂主体 mid、游客广场 mid——无点落 center/dam 红罩）
	check("四新区 zone_at 采样（军营 wild·大电/水泥/游客 mid）",
		main.world.zone_at(-114.0, -18.0) == "wild"
			and main.world.zone_at(98.0, -20.0) == "mid"
			and main.world.zone_at(-99.0, 26.0) == "mid"
			and main.world.zone_at(84.0, 44.0) == "mid")
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

	# §红点镜瞄准线（准星不飞出镜外）：装 reddot 的枪 ADS 到位后，镜窗中心
	# 须落在相机纵轴上（x/y 各 ±3mm）——旧 AABB 顶公式把整扇窗吊在准星下方
	# 12mm，HUD 正中的红点悬在玻璃窗外上方（用户反馈「准星飞出镜子外」）。
	# 用 vector 换枪重建枪模：rifle 槽 holder 是 §持枪 时按 holo 建的，enter()
	# 同枪 id 复用 holder、换 id 才重读装配瞄具（同 probe_shot 附加验收 6 套路）
	main.stash.buy_scope("reddot")   # 幂等：11 步已购过
	main.stash.equip_scope("vector", "reddot")
	main._start_mission({"primary": "vector", "secondary": "pistol"})
	await frames(8)
	var g_rd: Dictionary = main.guns._guns["primary"]
	check("红点镜挂枪记 aim_y（窗中心 local y）", g_rd.has("aim_y"),
		"keys=%s" % str(g_rd.keys()))
	# 窗顶=全镜最高件不变量：aim_y 应恰等于 AABB 顶 − 半窗高（窗是全镜最高件，
	# _local_aabb 量到的 top 即窗顶——HIDE_ZOOM 与此换算都依赖它）
	check("窗顶=全镜最高件（aim_y 与 AABB 顶恰差半窗高）", g_rd.has("aim_y")
			and absf(float(g_rd["aim_y"]) - (float(g_rd["top"])
					- HDGuns.RD_WIN_H * 0.5)) < 0.0015,
			"aim_y=%.4f top=%.4f" % [float(g_rd.get("aim_y", 0.0)),
					float(g_rd["top"])])
	Input.action_press("hd_scope")
	var rd_ads := false
	for i in 150:
		main.player.update(0.016)
		main.guns.update(0.016)
		if main.player.ads >= 1.0:
			rd_ads = true
			break
	Input.action_release("hd_scope")
	var rd_h: Node3D = g_rd["holder"]
	# 窗中心换到相机空间：枪模是 holder 子节点（整体 ×GUN_SCALE）、窗中心在
	# 枪身局部 (0, aim_y) → 相机系坐标 = holder.position + GUN_SCALE·aim_y
	var wc_y: float = rd_h.position.y + HDGuns.GUN_SCALE * float(g_rd["aim_y"])
	check("红点镜 ADS 窗中心过屏幕中心（相机纵轴 ±3mm）", rd_ads
			and absf(rd_h.position.x) < 0.003 and absf(wc_y) < 0.003,
			"ads=%.2f wc=(%.4f, %.4f)" % [main.player.ads, rd_h.position.x, wc_y])

	print("[huodai] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	main.free()
	quit(0 if fails == 0 else 1)
