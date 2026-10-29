# 回归：烽火地带（Godot 版）核心链路——签到/开箱/命中/换弹掉匣/搜刮/撤离/死亡/靶场/经济
#       + 实战/靶场语义分流：靶场练习弹免费零消耗（绝不回写库存）+ 暂停菜单模式分化文案
#       + 画质战场回归：开镜倍率语义/靶馆地坪分层/士兵比例/雾密度红线
#       + 交易行页签（唯一购买入口）：页签切换/光标跨段/成交链/出发页·改枪台购买入口回收
#       + 高模顶点红线：MK4 + 冲锋枪册五枪（mp5/p90/uzi/vector/mp7）+
#         步枪册八枪（m4a1/akm/scarh/m14/asval/k416/an94/sr25）+ 旧五枪 +
#         机枪册 M250 总顶点 ≥ 8× 低模基线（HDGunLib.POLY_MIN 表）
#       + 持枪（胸前提枪已移除）：出发枪常驻肩射位/无胸前横端/开镜回瞄准位
#       + 红点镜 ADS 瞄准线：镜窗改大（60×45mm）+ 窗中心过屏幕中心——
#         HUD 中心红点必须落进玻璃窗内（用户反馈「准星飞出镜子外」）
#       + 拟真枪声分层回归（用户反馈「现在的枪声不拟真」）：四层合成
#         （click/crack/boom/tail）20 枪流/时长分级/峰值/过零率/每发随机
#         + AS Val 消音专项档（峰值能量/时长低于普通步枪档）
#       + 贴掩体吞枪复发红线（29f）：全枪册表面材质 no_depth_test/priority≥10
#         审计 + 枪架 viewmodel 补光在位 + MP7 微自发光（三件套全锁）
#       + viewmodel 独立视口架构回归（29g）：own_world_3d 子视口在位/枪架
#         父链在 vm 世界/muzzle_world 与主相机数学连续（mm 级）/HIDE_ZOOM
#         藏枪照旧/闪光镜像灯与曳光掉匣件各归其位
#       + 射速回归（三源定案修复）：半自动 tap 门（按住 60 帧只 1 弹）/
#         追赶式结转冷却（全自动长程射速=表值 rpm，帧量化九档根治）/
#         desc「N发每分」机读一致/切枪清冷却+切枪帧不丢拍
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

## 枪模根全部 MeshInstance 顶点求和（装配审计用）
func _mesh_verts(root: Node3D) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			var mi := nd as MeshInstance3D
			if mi.mesh != null:
				n += int(mi.mesh.get_faces().size() / 3)
		for c in nd.get_children():
			stack.push_back(c)
	return n


func _initialize() -> void:
	# 存档隔离 v2（2026-10-27）：整套测试重定向到独立测试档——真实档零接触
	# （旧版删真实档+收尾写回测试态，每跑一次回归毁一次实机进度，用户实锤）
	HDData.SAVE_PATH = "user://huodai_save_test.json"
	var save := HDData.SAVE_PATH
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

	# 2. 每日签到：首领 DAILY_REWARD（经济重定价后 300），再领 0
	var got: int = main.stash.check_in()
	check("签到得 %d" % HDData.DAILY_REWARD, got == HDData.DAILY_REWARD, "got=%d" % got)
	check("现金入账", main.stash.cash == HDData.DAILY_REWARD)
	check("同日二刷拒绝", main.stash.check_in() == 0)

	# 2b. 合同系统（阶段 A）：每日 3 张确定性发放 → 进度推进 → 完成锁定 →
	#     撤离结算发奖 → 持久化往返 → 阵亡不清进度
	var cts: Array = main.stash.daily_contracts()
	check("每日合同恰 3 张", cts.size() == HDData.CONTRACT_DAILY,
		"n=%d" % cts.size())
	var ct_ids: Array = []
	var ct_ok := true
	for ct in cts:
		var cid := str(ct.get("id", ""))
		if ct_ids.has(cid) or main.stash.contract_def(cid).is_empty():
			ct_ok = false   # 重复 id 或池外 id 都是坏合同
		ct_ids.append(cid)
	check("合同 id 不重复且都在池内", ct_ok, str(ct_ids))
	var cts_reread: Array = main.stash.daily_contracts()
	var ids2: Array = []
	for ct2 in cts_reread:
		ids2.append(str(ct2.get("id", "")))
	check("同日重读合同不变（日期种子确定性）", str(ids2) == str(ct_ids))
	# 定向构造三张（kill5 / zdam / value3k）驱动全链——进度推进/完成锁定/分区匹配
	main.stash.contracts = [
		{"id": "kill5", "prog": 0, "done": false, "paid": false},
		{"id": "zdam", "prog": 0, "done": false, "paid": false},
		{"id": "value3k", "prog": 0, "done": false, "paid": false},
	]
	var fin: Array = main.stash.contract_add("kill", "", 2)
	check("击杀推进 kill5 至 2/5 未完成", int(main.stash.contracts[0]["prog"]) == 2
		and not bool(main.stash.contracts[0]["done"]) and fin.is_empty())
	fin = main.stash.contract_add("kill", "", 3)
	check("击杀补满 5 → 完成锁定并播报", bool(main.stash.contracts[0]["done"])
		and fin.size() == 1 and str(fin[0]["id"]) == "kill5")
	main.stash.contract_add("zone", "center", 1)
	check("分区不匹配不推进（center ≠ zdam）", int(main.stash.contracts[1]["prog"]) == 0)
	main.stash.contract_add("zone", "dam", 4)
	check("坝区搜箱 4 → zdam 完成", bool(main.stash.contracts[1]["done"]))
	# 撤离结算：value3k 按包价值判定（4000 ≥ 3000）→ 三张全发（900+1500+800=3200）
	var cash_c: int = main.stash.cash
	var paid_ct: Array = main.stash.settle_contracts(4000)
	var ct_sum := 0
	for pc in paid_ct:
		ct_sum += int(pc.get("reward", 0))
	check("撤离结算三张全发（value 判定 + 已完成）", paid_ct.size() == 3 and ct_sum == 3200,
		"paid=%d sum=%d" % [paid_ct.size(), ct_sum])
	check("奖金入账 + 合同计数 +3", main.stash.cash == cash_c + 3200
		and int(main.stash.stats.get("contracts", 0)) == 3)
	check("已领再结算不重复发", main.stash.settle_contracts(99999).is_empty()
		and main.stash.cash == cash_c + 3200)
	# value 低值撤离不达标：新一张 value3k 带 ₵1000 撤离 → 不完成不发
	var cash_v: int = main.stash.cash
	main.stash.contracts = [{"id": "value3k", "prog": 0, "done": false, "paid": false}]
	check("value 低值撤离不完成不发", main.stash.settle_contracts(1000).is_empty()
		and not bool(main.stash.contracts[0]["done"])
		and main.stash.cash == cash_v)
	# 持久化往返：新实例读档 → 合同与已领态保留
	var stash2 := HDStash.new()
	var cts_load: Array = stash2.contracts
	check("合同持久化往返（3 张 + 已领态）", cts_load.size() == 3
		and bool(cts_load[0].get("paid", false))
		and stash2.contracts_day == main.stash.contracts_day)
	# 阵亡不清进度（塔科夫式：完成即锁，撤离才发）——record_raid(false) 后进度原样。
	# deaths 事后复位：真实阵亡测试（第 9 段）期望从 0 数到 1
	var ct_deaths0: int = int(main.stash.stats.get("deaths", 0))
	main.stash.contracts = [{"id": "kill12", "prog": 5, "done": false, "paid": false}]
	main.stash.record_raid(false, 0)
	check("阵亡不清合同进度", int(main.stash.contracts[0]["prog"]) == 5
		and not bool(main.stash.contracts[0]["done"]))
	main.stash.stats["deaths"] = ct_deaths0

	# 2c. 钥匙锁房 + 隧道撤离（阶段 B）：三间锁房建成 / 钥匙种子确定性刷新 /
	#     持钥匙 F 开锁（消耗钥匙 + 门障碍移除 + 房内容器生成）/ 无钥匙提示 /
	#     复位重锁 / 隧道撤离常开
	check("锁房三间建成（armory/archive/camp）", main.locks._states.size() == 3
		and main.locks._states.has("armory") and main.locks._states.has("archive")
		and main.locks._states.has("camp"))
	var st_a: Dictionary = main.locks._states["armory"]
	check("armory 门障碍在册", main.world.obstacles.has(st_a["obs"]))
	var drops_a: Array = main.locks.roll_key_drops(12345, main.world.container_spots)
	var drops_b: Array = main.locks.roll_key_drops(12345, main.world.container_spots)
	check("钥匙刷新种子确定性（同种子同结果）", str(drops_a) == str(drops_b)
		and drops_a.size() >= 0 and drops_a.size() <= 3)
	var drops_ok := true
	for d0 in drops_a:
		var di: Dictionary = d0
		var spot_near := false
		for sp in main.world.container_spots:
			# 钥匙落容器旁 1.7m（>GROUND_R：不抢容器搜索的 F）——阈值放宽到搜索半径内
			if Vector2(di["pos"].x - sp["pos"].x, di["pos"].z - sp["pos"].z).length() <= 2.2:
				spot_near = true
				break
		if not spot_near or not str(di["item"].get("uid", "")).begins_with("key_"):
			drops_ok = false
	check("钥匙落点贴容器点位（1.7m，不抢搜索 F）且带 key_ uid", drops_ok)
	# 锁房提示信道回归（用户报告「搜索不了容器」根因之一）：无门在侧时锁房必须
	# 沉默——旧版每帧发 ("",0) 把 loot 的「按住 F 搜索…」提示整屏抹掉
	var lk_emits := [0]
	var lk_spy := func(_t: String, _p: float): lk_emits[0] += 1
	main.locks.prompt.connect(lk_spy)
	main.locks.update(0.016, Vector3(0.0, 0.0, 80.0), false)   # 远离三扇门的空地
	check("锁房无门沉默（不劫持容器搜索提示）", lk_emits[0] == 0)
	main.locks.prompt.disconnect(lk_spy)
	# 钥匙落点罗盘标记（2026-10-25 用户定案「钥匙地点也要在方向标显示」）：
	# 地上钥匙实时标向（金色「钥匙 Nm」），捡起（离开 _ground）标记即消失
	for g0 in main.loot._ground.duplicate():   # 清残留地面件，摆一把已知位置钥匙（不开局防打乱夹具）
		(g0["node"] as Node3D).queue_free()
	main.loot._ground.clear()
	main.loot._ground_i = -1
	main.player.enter(Vector3(-24.0, 0.0, -36.0))
	main.loot._spawn_ground({"uid": "key_mark_t", "name": "军火库钥匙",
		"icon": "钥匙", "rarity": 3, "value": 800, "key": "armory"},
		Vector3(40.0, 0.0, 40.0))
	var marks0: Array = main._compass_marks()
	var key_mark := {}
	for m0 in marks0:
		if str(m0.get("label", "")).begins_with("钥匙"):
			key_mark = m0
	check("地上钥匙有罗盘标记（金色·带距离）", not key_mark.is_empty()
		and str(key_mark.get("label", "")).contains("m"),
		str(key_mark))
	for g1 in main.loot._ground.duplicate():   # 捡起（清地）→ 标记消失
		(g1["node"] as Node3D).queue_free()
	main.loot._ground.clear()
	var marks1: Array = main._compass_marks()
	var key_mark_gone := true
	for m1 in marks1:
		if str(m1.get("label", "")).begins_with("钥匙"):
			key_mark_gone = false
	check("捡起后钥匙标记消失", key_mark_gone)
	# 钥匙卡购买（2026-10-24 用户定案）：买入入库存（每种上限 2）→ 开局注入背包
	main.stash.cash = 99999
	var kc0: int = main.stash.cash
	check("买军火库钥匙×2（₵1500/把）", main.stash.buy_keycard("armory")
		and main.stash.buy_keycard("armory")
		and main.stash.keycards_of("armory") == 2
		and main.stash.cash == kc0 - 3000)
	main.stash.buy_keycard("armory")
	check("钥匙卡上限拦截（第 3 把拒购）", main.stash.keycards_of("armory") == 2
		and main.stash.cash == kc0 - 3000)
	main.stash.buy_keycard("archive")
	# ⑥区可见性回归（用户报告「钥匙卡没出现在交易行」——曾经埋在③区底部小钮
	# 不可发现）：交易行页面必须渲染出带「钥匙」字样的购买钮
	main.lobby.show_lobby()
	main.lobby.set_tab(2)
	main.lobby._refresh_all()
	var mkt_txt := ""
	var ui_stack: Array = [main.lobby._pages[2]]   # 栈循环收按钮文案（递归 lambda 自引用是解析错）
	while not ui_stack.is_empty():
		var n0: Node = ui_stack.pop_back()
		if n0 is Button:
			mkt_txt += str((n0 as Button).text) + "|"
		for c0 in n0.get_children():
			ui_stack.push_back(c0)
	check("交易行⑥区钥匙卡购买钮可见", mkt_txt.contains("军火库钥匙")
		and mkt_txt.contains("军营钥匙") and mkt_txt.contains("破片雷"),
		mkt_txt.substr(0, 60))
	main.loot.reset_all()          # 清包再注入（不开真局——避免打乱下游经济夹具）
	main._inject_keycards()
	var kc_in_bag := 0
	for it_kc in main.loot.backpack:
		if str((it_kc as Dictionary).get("key", "")) == "armory":
			kc_in_bag += 1
	check("开局注入：库存钥匙卡自动入包（2 把）且库存清零", kc_in_bag == 2
		and main.stash.keycards_of("armory") == 0)
	for i_kc in range(main.loot.backpack.size() - 1, -1, -1):   # 夹具复位：取出注入件
		if str((main.loot.backpack[i_kc] as Dictionary).get("key", "")) != "":
			main.loot.backpack.remove_at(i_kc)
	var dyn0 := 0
	for c0 in main.loot._containers:
		if bool(c0.get("dynamic", false)):
			dyn0 += 1
	main.loot.backpack.append({"uid": "key_armory_t", "name": "军火库钥匙",
		"icon": "钥匙", "rarity": 3, "value": 800, "key": "armory"})
	main.player.enter(Vector3(-39.9, 0.0, -47.0))   # armory 门（朝 E）外 1m
	# GDScript lambda 按值捕获：String 改不到外部，用数组容器接提示文案
	var lk_prompt := [""]
	var lk_cb := func(t: String, _p: float): lk_prompt[0] = t
	main.locks.prompt.connect(lk_cb)
	main.locks.update(0.016, main.player.pos, false)
	main.locks.update(0.016, main.player.pos, true)   # F 边沿 → 开锁
	check("持钥匙 F 开锁：门开+障碍移除+钥匙消耗", bool(st_a["opened"])
		and not main.world.obstacles.has(st_a["obs"])
		and not main.loot.take_item("key_armory_t"))
	check("持钥匙提示文案（按 F 用…开启）", lk_prompt[0].contains("开启"))
	var dyn1 := 0
	var cls_seen := []
	for c1 in main.loot._containers:
		if bool(c1.get("dynamic", false)):
			dyn1 += 1
			cls_seen.append(str(c1.get("cls", "")))
	check("开锁生成房内容器×2（safe+物资箱）", dyn1 == dyn0 + 2
		and cls_seen.has("safe") and cls_seen.has("weapon"))
	# 无钥匙：archive 门只提示不上锁
	main.player.enter(Vector3(70.6, 0.0, 37.75))   # archive 门（朝 W）外 ~1m（交互半径内）
	main.locks.update(0.016, main.player.pos, true)
	check("无钥匙提示「上锁」不开门", not bool(main.locks._states["archive"]["opened"])
		and lk_prompt[0].contains("上锁"))
	# 复位重锁：门障碍回来、开态清零（每局重新上锁）
	main.locks.reset_all()
	check("复位重锁（门障碍恢复）", not bool(st_a["opened"])
		and main.world.obstacles.has(st_a["obs"]))
	main.locks.prompt.disconnect(lk_cb)
	# 隧道撤离（军营北，常开）
	main._setup_extracts()
	var ext_defs: Array = main.world.extract_defs()
	check("撤离点 5 处含隧道", ext_defs.size() == 5 and str(ext_defs[4]["id"]) == "tunnel")
	check("隧道信标已建 + 本局常开", main.world._extract_vis.has("tunnel")
		and bool(main._extracts["tunnel"]["enabled"])
		and bool(main._extracts["tunnel"]["open"]))

	# 2d. 昼夜/天气变体（阶段 C）：表完整性 / 大气三态 / AI 视距乘数 / 枪声掩声 /
	#     大厅 V 循环 + payload / 靶场复位（不真开一局——避免阵亡结算吃掉后续夹具）
	var rvk: Array = HDData.RAID_VARIANTS.keys()
	check("变体四态齐备（晴朗/夜晚/雨天/浓雾）",
		rvk.size() == 4 and rvk.has("clear") and rvk.has("night")
			and rvk.has("rain") and rvk.has("fog"))
	var vfields_ok := true
	for vd0 in HDData.RAID_VARIANTS.values():
		var vd: Dictionary = vd0
		for fkey in ["sun", "amb", "fog", "sight", "hear", "luck", "rain"]:
			if not vd.has(fkey):
				vfields_ok = false
	check("变体字段齐（sun/amb/fog/sight/hear/luck/rain）", vfields_ok)
	HDData.variant = "night"
	check("夜晚实效视距 18m（30×0.6）", is_equal_approx(main.soldiers.view_dist(), 18.0))
	main.world.apply_variant("night")
	check("夜晚大气（阳×0.16 · 雾×1.5）",
		is_equal_approx(main.world._sun.light_energy, main.world.OUTDOOR_SUN * 0.16)
			and is_equal_approx(main.world._env.fog_density, main.world.OUTDOOR_FOG * 1.5))
	main.world.apply_variant("rain")
	check("雨天雨粒子可见", main.world._rain.visible)
	main.world.apply_variant("fog")
	check("浓雾雾密度 ×6 + 雨隐藏", is_equal_approx(main.world._env.fog_density,
		main.world.OUTDOOR_FOG * 6.0) and not main.world._rain.visible)
	HDData.variant = "rain"
	check("雨天枪声掩声 36m（60×0.6）", is_equal_approx(
		HDSoldiers.SHOT_HEAR_R * HDData.v_f("hear", 1.0), 36.0))
	HDData.variant = "clear"
	main.world.apply_variant("clear")
	check("晴朗复位（阳/雾回基线 + 雨隐藏）",
		is_equal_approx(main.world._sun.light_energy, main.world.OUTDOOR_SUN)
			and is_equal_approx(main.world._env.fog_density, main.world.OUTDOOR_FOG)
			and not main.world._rain.visible)
	# 大厅 V 循环 + payload 契约
	main.lobby.set_tab(0)
	main.lobby._variant_idx = 0
	main.lobby.handle_key(KEY_V)
	main.lobby.handle_key(KEY_V)
	check("V 两下循环到 雨天", main.lobby.variant_key() == "rain")
	var pl: Dictionary = main.lobby._deploy_payload("rifle", "pistol", false)
	check("出发 payload 带天气字段", str(pl.get("variant", "")) == "rain"
		and str(pl.get("primary", "")) == "rifle")
	main.lobby._variant_idx = 0   # 复位缺省晴朗
	# 靶场入口复位变体（先手动置夜晚再进靶场）
	HDData.variant = "night"
	main.world.apply_variant("night")
	main._enter_range()
	check("进靶场恢复晴朗（变体实战专属）", HDData.variant == "clear"
		and is_equal_approx(main.world._env.fog_density, main.world.INDOOR_FOG))
	main.lobby.show_lobby()   # 复位大厅态（后续 UI 断言沿用）

	# 2e. 弹种接线 + 投掷物（阶段 D）：弹种循环购买/切回/免重复扣款 → 投掷物购买
	#     上限 → 开一局：7 键投掷消耗 → 三类起爆（破片杀兵/闪光致盲+白屏/烟球遮蔽）
	main.stash.cash = 99999
	check("弹种缺省标准弹", main.stash.ammo_kind_of("rifle") == "standard")
	var ck0: int = main.stash.cash
	var rr: Array = main.stash.cycle_ammo_kind("rifle")
	check("首切强力弹自动购买（₵600）", bool(rr[0]) and str(rr[1]) == "power"
		and main.stash.cash == ck0 - 600)
	main.stash.cycle_ammo_kind("rifle")   # → 穿甲弹（购 ₵1500）
	main.stash.cycle_ammo_kind("rifle")   # → 燃烧弹（购 ₵3000）
	rr = main.stash.cycle_ammo_kind("rifle")
	check("循环到头回标准弹（免费切回）", bool(rr[0]) and str(rr[1]) == "standard")
	var ck1: int = main.stash.cash
	rr = main.stash.cycle_ammo_kind("rifle")   # → 强力弹（已购不再扣款）
	check("已购弹种换装零扣款", bool(rr[0]) and str(rr[1]) == "power"
		and main.stash.cash == ck1)
	check("燃烧弹倍率表落位（2.2×）",
		is_equal_approx(float(Guns.ammo_by_id("incendiary")["dmg_mul"]), 2.2))
	main.stash.throwables = {"frag": 0, "smoke": 0, "flash": 0}
	var tb_ok: bool = main.stash.buy_throwable("frag") and main.stash.buy_throwable("frag") \
			and main.stash.buy_throwable("frag")
	check("破片雷购满 3 件", tb_ok and main.stash.throwables_of("frag") == 3)
	main.stash.buy_throwable("frag")
	check("投掷物上限拦截（第 4 件拒购）", main.stash.throwables_of("frag") == 3)
	check("烟雾/闪光各购 1", main.stash.buy_throwable("smoke")
		and main.stash.buy_throwable("flash"))
	# 开一局：真兵真模块测投掷链
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(6)
	var sol_i := -1
	for si in main.soldiers.soldiers.size():
		var s0: Dictionary = main.soldiers.soldiers[si]
		if not bool(s0.get("dead", true)) and str(s0.get("tier", "")) == "regular":
			sol_i = si
			break
	check("找到一名普通兵作靶", sol_i >= 0)
	var n_frag0: int = main.stash.throwables_of("frag")
	main.player.yaw = 0.0
	main._route_key(KEY_7)
	check("7 键投掷：库存 -1 + 投掷物在飞", main.stash.throwables_of("frag") == n_frag0 - 1
		and main.thrower._projs.size() == 1)
	for i in 30:
		main.thrower.update(0.06)   # 1.8s 快进：弹道落地 + 引信起爆
	check("投掷物全部起爆（无残留）", main.thrower._projs.is_empty())
	main.stash.consume_throwable("smoke")   # 直接消耗走起爆直测（弹道已验）
	main.thrower._detonate("smoke", main.player.pos + Vector3(4.0, 0.5, 0.0))
	check("烟球入表并遮蔽视线", main.thrower.smoke_spheres.size() == 1
		and main.thrower.blocks_sight(main.player.pos + Vector3(0, 1.5, 0),
			main.player.pos + Vector3(8.0, 1.5, 0.0))
		and not main.thrower.blocks_sight(main.player.pos + Vector3(-8.0, 1.5, -8.0),
			main.player.pos + Vector3(-4.0, 1.5, -8.0)))
	main.thrower.smoke_spheres.clear()   # 清烟：别让上一测试的烟球挡了闪光 LOS
	main.stash.consume_throwable("flash")
	main.player.yaw = PI / 2.0   # 面朝 +x（前向 = (sin yaw, 0, cos yaw)）——爆点在正前
	main.player.update(0.016)
	var tgt: Dictionary = main.soldiers.soldiers[sol_i] if sol_i >= 0 else {}
	if not tgt.is_empty():
		tgt["pos"] = main.player.pos + Vector3(3.0, 0.0, 0.0)   # 挪到玩家正面 3m
		tgt["dead"] = false
	main.thrower._detonate("flash", main.player.pos + Vector3(3.0, 1.2, 0.0))
	main.thrower.update(0.016)   # 白屏 alpha 由 update 施加（_detonate 只置计时）
	check("闪光：玩家白屏起效 + 近兵致盲", main.hud._flash_rect.color.a > 0.0
		and (tgt.is_empty() or float(tgt.get("blind_t", 0.0)) > 0.0))
	# 破片 AoE 直测：把靶兵贴爆点（130 伤害 ≥ 普通 100 血）
	if not tgt.is_empty():
		tgt["hp"] = 100.0
		tgt["armor"] = 0.0
		tgt["dead"] = false
		main.thrower._detonate("frag", tgt["pos"] + Vector3(0, 1.0, 0))
		check("破片雷近距击杀普通兵", bool(tgt.get("dead", false)))
	main.thrower.reset_all()
	check("投掷物清场（烟球清空）", main.thrower.smoke_spheres.is_empty())

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
	# 4b. 开局简报卡组（2026-10-24 用户定案「开局内容分小卡片、去口水话」）：
	#     撤离/合同/风险各一张短句卡（晴天无天气卡），右上角显示
	var brief_n: int = main.hud._brief_box.get_child_count() if main.hud._brief_box != null else 0
	var brief_txt := ""
	if main.hud._brief_box != null:
		for bc in main.hud._brief_box.get_children():
			for lc in (bc as PanelContainer).find_children("*", "Label", true, false):
				brief_txt += str((lc as Label).text) + "|"
	check("开局简报卡组 ≥3 张且在显", main.hud._brief_box != null
		and main.hud._brief_box.visible and brief_n >= 3,
		"cards=%d" % brief_n)
	check("简报含撤离/合同/风险要点（短句化）",
		brief_txt.contains("主撤离") and brief_txt.contains("合同")
			and brief_txt.contains("安全箱") and brief_txt.contains("25 分钟"),
		brief_txt.substr(0, 80))
	check("步枪满弹·备弹=stash（首局礼物 150）",
		main.guns.ammo == 30 and main.guns.reserve == 150
			and main.guns.reserve == main.stash.ammo_of("rifle"),
		"ammo=%d reserve=%d stash=%d" % [main.guns.ammo, main.guns.reserve,
			main.stash.ammo_of("rifle")])
	check("出生点在地图内", absf(main.player.pos.x) <= HDData.MAP_HALF
		and absf(main.player.pos.z) <= HDData.MAP_HALF)

	# 5. 命中判定：把 0 号兵放到面前 10m，aim 后 raycast_all 应报 soldier
	#    （出生点随机后固定回西南角空地，面前 10 m 无遮挡）
	main.player.enter(HDData.SPAWN_POINTS[0])
	main.player.yaw = atan2(-HDData.SPAWN_POINTS[0].x, -HDData.SPAWN_POINTS[0].z)
	var s0: Dictionary = main.soldiers.soldiers[0]
	var fwd := Vector3(sin(main.player.yaw), 0.0, cos(main.player.yaw))
	s0["pos"] = main.player.pos + fwd * 10.0
	s0["hp"] = 100.0
	s0["dead"] = false
	main.player.update(0.016)   # 应用朝向到相机
	var from: Vector3 = main.player.cam.global_position
	var dir: Vector3 = -main.player.cam.global_transform.basis.z
	var hit: Dictionary = main.guns.raycast_all(from, dir, 300.0)
	# 士兵 1.0 比例（真人 1.8m）后，玩家眼高 1.55m 平射正落在头盔球内——
	# 命中头或身都算「射线命中士兵」
	check("正面射线命中士兵", str(hit.get("type", "")) in ["soldier", "soldier_head"],
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

	# 9. 死亡：重开一局后打空血 → LOSE + 丢包 + 带入即风险（2026-10 改进方案第 1 节：
	#    主武器出拥有集、所带备弹清零，侦察手枪永久不丢，出发配置修复为单枪）
	main._restart_current()
	await frames(10)
	main.player.hit(9999.0)
	check("阵亡结算 LOSE", main.hud.result_visible and main.stash.stats["deaths"] == 1)
	check("死亡丢背包", main.loot.backpack.is_empty())
	check("阵亡丢失带入主武器（步枪出拥有集）", not main.stash.owns_gun("rifle"))
	check("侦察手枪永久不丢", main.stash.owns_gun("pistol"))
	check("阵亡所带备弹清零（置 0 不删键，防首读再送礼）",
		main.stash.ammo_inv.get("rifle", -1) == 0 and main.stash.ammo_inv.get("pistol", -1) == 0,
		"rifle=%s pistol=%s" % [str(main.stash.ammo_inv.get("rifle")),
			str(main.stash.ammo_inv.get("pistol"))])
	check("出发配置修复为侦察手枪单枪（副武器空槽）",
		str(main.stash.loadout.get("primary")) == "pistol"
			and str(main.stash.loadout.get("secondary")) == "",
		str(main.stash.loadout))
	check("阵亡结算页列出损失明细", main.hud._result_lines.get_child_count() >= 2)
	main._restart_current()   # 结算后 R 再来：已结算，不得二次扣（阵亡数不变）
	await frames(4)
	check("结算后再来不二次结算", main.stash.stats["deaths"] == 1
		and str(main.guns.cur_id) == "pistol")
	# 夹具复位：后续步骤沿用旧五枪 + rifle 125 / pistol 60 的账目
	main.stash.guns_owned = ["pistol", "smg", "rifle", "shotgun", "sniper"]
	main.stash.set_ammo("rifle", 125)
	main.stash.set_ammo("pistol", 60)
	main.stash.loadout = {"primary": "rifle", "secondary": "pistol"}
	main.stash.save()
	main._raid_live = false   # 夹具局直接置「已结算」：不丢装备、不记战绩

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

	# 10d. 大厅 3D 场景（2026-10 三角洲式改版回归）：own_world_3d 独立视口在位 /
	#      干员节点在位 / 大厅可见+出发页=场景激活 / 换枪当场重建手持枪 /
	#      节点数与面数红线（数值断言防布景膨胀，性能红线 ≥55 帧的形状面预算）
	check("大厅 3D 场景在位且独立世界", main.lobby_scene != null
		and main.lobby_scene.vp != null and main.lobby_scene.vp.own_world_3d)
	check("干员节点在位（soldier_hd 实例化）", main.lobby_scene.operator != null
		and main.lobby_scene.operator.get_child_count() > 0)
	check("大厅可见+出发页=场景激活", main.lobby_scene._active
		and main.lobby_scene.composite.visible)
	var held0: String = main.lobby_scene.held_gun_id
	check("默认手持枪=主槽 rifle", held0 == "rifle", "held=%s" % held0)
	main.stash.cash = 2400
	main.stash.buy_gun("scarh")   # 幂等防重复扣款；后续 19 步自管 scarh 归属
	main.lobby._slot_focus = "primary"
	main.lobby._load_gun("scarh")
	await frames(2)
	check("大厅换枪当场换手持枪（rifle→scarh）", main.lobby_scene.held_gun_id == "scarh"
		and main.lobby_scene._gun_holder.get_child_count() == 1,
		"held=%s children=%d" % [main.lobby_scene.held_gun_id,
			main.lobby_scene._gun_holder.get_child_count()])
	main.lobby._slot_focus = "primary"   # _load_gun 装完自动跳另一槽，换回要重新指主槽
	main.lobby._load_gun("rifle")
	await frames(2)
	check("换回 rifle 手持枪重建", main.lobby_scene.held_gun_id == "rifle")
	main.stash.guns_owned.erase("scarh")   # 夹具还原：17 步断言「恰旧五枪」（19 步自购）
	var lobby_st: Dictionary = main.lobby_scene.stats()
	check("大厅场景节点数红线（≤%d）" % main.lobby_scene.MAX_NODES,
		int(lobby_st["nodes"]) > 0 and int(lobby_st["nodes"]) <= main.lobby_scene.MAX_NODES,
		"nodes=%d" % int(lobby_st["nodes"]))
	check("大厅场景面数红线（≤%d）" % main.lobby_scene.MAX_TRIS,
		int(lobby_st["tris"]) > 0 and int(lobby_st["tris"]) <= main.lobby_scene.MAX_TRIS,
		"tris=%d" % int(lobby_st["tris"]))

	# 11. 经济：买瞄具 → 装配 → 倍率生效（重定价后签到只有 300，先补足现金）
	main.stash.cash = maxi(main.stash.cash, 700)
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

	# 13. 地下靶馆地坪分层（2026-10 靶馆入地回归）：地下域 hint 馆内 -6.94 /
	#     坡道线性 / 地表 hint 馆上方仍 0（地表行走不受脚下馆体影响）
	check("地下馆内地坪 -6.94", absf(main.world.ground_height(
		HDData.HALL_CENTER.x, HDData.HALL_CENTER.z, -10.0)
		- (-6.94)) < 0.001,
		"gy=%.3f" % main.world.ground_height(
			HDData.HALL_CENTER.x, HDData.HALL_CENTER.z, -10.0))
	check("馆上方地表仍 0（hint 守卫）", absf(main.world.ground_height(
		HDData.HALL_CENTER.x, HDData.HALL_CENTER.z, 0.0)) < 0.001)
	check("坡道顶端 0.06 / 底端 -6.94", absf(main.world.ground_height(
		120.0, 157.0, 0.0) - 0.06) < 0.001
		and absf(main.world.ground_height(120.0, 147.0, -6.8) + 6.94) < 0.001)
	check("馆外大地 0.0", absf(main.world.ground_height(0.0, 0.0)) < 0.001)
	check("射位出生贴地坪", absf(main.player.pos.y
		- main.world.ground_height(main.player.pos.x, main.player.pos.z,
			main.player.pos.y)) < 0.001,
		"pos.y=%.3f" % main.player.pos.y)

	# 14. 士兵比例（问题④回归）：大战场遗产 1.5 已收敛，防回退
	check("士兵 scale 常量 ≤ 1.2", HDSoldiers.SOLDIER_SCALE <= 1.2,
		"SOLDIER_SCALE=%.2f" % HDSoldiers.SOLDIER_SCALE)

	# 15. 雾密度红线（问题②回归）：FOG_MAX 注释"远景可见性红线"，室内外都不得越线
	check("雾常量 ≤ 远景可见性红线", HDWorld.OUTDOOR_FOG <= HDWorld.FOG_MAX
		and HDWorld.INDOOR_FOG <= HDWorld.FOG_MAX)
	check("当前环境雾密度 ≤ 红线", main.world._env.fog_density <= HDWorld.FOG_MAX,
		"density=%.4f" % main.world._env.fog_density)

	# 16. 新枪账本：十二把新枪逐把出发进场——满弹 + 备弹=stash 首局礼物满额 + 后坐表落位
	#     （RECOIL 缺键会吃 [0.4,0.2,0.25] 兜底，后坐爆炸；旧语义「每局免费满备弹」
	#     已改弹药经济：首次进弹药经济一次性送满额，此后只买不送）
	for gid in ["mp5", "p90", "uzi", "vector", "m4a1", "akm", "scarh", "m14",
			"m250", "mp7", "asval", "k416", "an94", "sr25"]:
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
	# 2026-10 ⑤区（M14 配件）入列后域 5：从①左回绕落⑤（测试探针档未拥有
	# M14，⑤区隐藏但段号照常参与 posmod 导航）
	check("← 回绕跨段到 4（⑤ M14 配件，域 5）", main.lobby._market_sec == 4)
	main.lobby.handle_key(KEY_LEFT)
	check("← 再绕到 3（④ 仓库）", main.lobby._market_sec == 3)
	main.lobby.handle_key(KEY_RIGHT)
	check("→ 回绕跨段回 0（④→⑤→…回①按两下）", true)
	main.lobby.handle_key(KEY_RIGHT)
	check("→ ⑤→① 回绕（④右两步到①）", main.lobby._market_sec == 0)
	main.lobby._market_gun = 0
	main.lobby.handle_key(KEY_DOWN)
	check("↓ 段内选下把枪", main.lobby._market_gun == 1)
	main.lobby.handle_key(KEY_UP)
	check("↑ 段内选回", main.lobby._market_gun == 0)

	# 24. 出发页购买入口回收：未拥有枪行回车不购不装（现金足额也拦）、B/空格不再消费
	#     （静默不消费——不弹「←→ 切③区」类误导指路，_hint_label 保持空）
	#     2026-10 战备收拢：槽卡/枪行收进战备面板（右下角贴图/TAB 开合），键盘链
	#     先展开面板再驱动；收起态光标域只剩出发钮（回车=出发，另见 _confirm_deploy）
	main.stash.cash = 99999
	main.lobby.set_tab(0)
	check("战备面板默认收起（主画面只剩干员+出发栏）", not main.lobby._prep_open)
	main.lobby._toggle_prep(true)
	check("战备面板展开（贴图/TAB 链）且光标归主武器槽",
		main.lobby._prep_open and main.lobby._cur0 == 0)
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
	main.lobby._toggle_prep(false)
	check("战备面板收起（光标归出发钮）", not main.lobby._prep_open and main.lobby._cur0 == 0)

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

	# 27. 高模顶点红线：步枪册八枪（hd_gun_ar.gd 高模重建；m14 商店 DMR
	#     2026-10 并册、asval 商店特种突击步枪 2026-10 并册、k416 商店突击
	#     步枪 2026-10 并册、an94 商店超点射突击步枪 2026-10 并册、
	#     sr25 商店半自动 DMR 2026-10 并册）
	#     逐把枪身根总顶点 ≥ 8× 低模基线（走
	#     hd_guns._ar_build 分发入口，含 mag_stanag/mag_banana/mag_wide/
	#     mag_dmr/mag_val/mag_k416/mag_an94/mag_sr25 独立命名弹匣节点；
	#     POLY_MIN/POLY_BASE 见 HDGunLib——门槛与 mk4 同口径 = 盒×24 + 柱×57
	#     的 8 倍）
	for gid in ["m4a1", "akm", "scarh", "m14", "asval", "k416", "an94", "sr25"]:
		var ar_root: Node3D = HDGuns._ar_build(gid)
		var ar_verts: int = GUN_LIB.count_vertices(ar_root)
		check("步枪 %s 高模顶点 ≥ POLY_MIN（8× 基线）" % gid,
			ar_verts >= int(GUN_LIB.POLY_MIN[gid]),
			"verts=%d min=%d base=%d" % [ar_verts, int(GUN_LIB.POLY_MIN[gid]),
				int(GUN_LIB.POLY_BASE[gid])])
		# 弹匣节点契约：步枪册各枪的静置真匣必须是独立命名节点（换弹手沿
		# mag_of 锚点跟随，匣形由枪身件表达——show=false 见 _ar_mag_of）
		var mag_node: Node = ar_root.find_child("mag_*", true, false)
		check("步枪 %s 独立命名弹匣节点在根下" % gid, mag_node != null,
			"node=%s" % (str(mag_node.name) if mag_node != null else "无"))
		ar_root.free()

	# 27b. K416 商店枪专项（2026-10 并册）：官方考证断言四件——
	#      ① 独立命名弹匣锚点 mag_k416 在枪身根下（换弹手沿 mag_of 锚跟随
	#        的契约件，#27 循环只查 mag_* 存在性，这里锁名）
	#      ② 简介射速「880发每分」与 cd 换算一致 ±1%（60/0.0682=879.8）
	#      ③ 全自动缺省（auto 不写 = true，hold 不连发才算违例）
	#      ④ 备弹档 RESERVE["k416"] 在表（漏加则 enter() 备弹 0）
	var k_root: Node3D = HDGuns._ar_build("k416")
	var k_mag: Node = k_root.find_child("mag_k416", true, false)
	check("K416 独立命名弹匣锚点 mag_k416 在根下", k_mag != null,
		"node=%s" % (str(k_mag.name) if k_mag != null else "无"))
	k_root.free()
	var k_def: Dictionary = Guns.gun_by_id("k416")
	var k_rpm := 60.0 / float(k_def["cd"])
	check("K416 简介射速 880 与 cd 换算一致（±1%）",
		absf(k_rpm - 880.0) / 880.0 <= 0.01, "cd=%s rpm=%.1f"
			% [str(k_def["cd"]), k_rpm])
	check("K416 全自动缺省 + 弹匣 30 + 备弹档在表",
		bool(k_def.get("auto", true)) and int(k_def["mag"]) == 30
			and (HDData.RESERVE as Dictionary).has("k416"),
		"mag=%s reserve=%s" % [str(k_def.get("mag")), str(HDData.RESERVE.get("k416", "缺"))])

	# 27c. AN-94 商店枪专项（2026-10 并册·S12 微光赛季）：超点射考证断言四件——
	#      ① 独立命名弹匣锚点 mag_an94 在枪身根下（右倾 AK-74 弧匣，换弹手沿
	#        mag_of 锚跟随的契约件，#27 循环只查 mag_* 存在性，这里锁名）
	#      ② 简介双射速文案与数值一致：「前两发 1800」↔ cd_profile[0]=0.0333
	#        （60/0.0333=1801.8，±1%）；「600发每分」↔ cd=0.1（60/0.1=600 精确）
	#      ③ 射速档案在位：cd_profile=[0.0333, 0.1] 且末位 == cd（档案末值=
	#        稳态间隔，与单 cd 语义同源——越界取末值的文档契约）
	#      ④ 全自动缺省 + 弹匣 30 + 备弹/购弹双表在表（RESERVE/AMMO_PRICE
	#        缺键则 enter() 备弹 0 / 交易行购弹静默拒）
	var a_root: Node3D = HDGuns._ar_build("an94")
	var a_mag: Node = a_root.find_child("mag_an94", true, false)
	check("AN-94 独立命名弹匣锚点 mag_an94 在根下", a_mag != null,
		"node=%s" % (str(a_mag.name) if a_mag != null else "无"))
	a_root.free()
	var a_def: Dictionary = Guns.gun_by_id("an94")
	var a_prof: Array = a_def.get("cd_profile", [])
	check("AN-94 简介双射速文案与 cd/cd_profile 换算一致（±1%）",
		str(a_def["desc"]).contains("前两发 1800")
			and str(a_def["desc"]).contains("600发每分")
			and absf(60.0 / float(a_def["cd"]) - 600.0) / 600.0 <= 0.01
			and a_prof.size() > 0
			and absf(60.0 / float(a_prof[0]) - 1800.0) / 1800.0 <= 0.01,
		"cd=%s prof=%s" % [str(a_def["cd"]), str(a_prof)])
	check("AN-94 射速档案在位（首对 0.0333 + 稳态 0.1 == cd 末位同源）",
		a_prof.size() == 2 and is_equal_approx(float(a_prof[1]), float(a_def["cd"])),
		"prof=%s" % str(a_prof))
	check("AN-94 全自动缺省 + 弹匣 30 + 备弹/购弹双表在表",
		bool(a_def.get("auto", true)) and int(a_def["mag"]) == 30
			and (HDData.RESERVE as Dictionary).has("an94")
			and (HDData.AMMO_PRICE as Dictionary).has("an94"),
		"mag=%s reserve=%s price=%s" % [str(a_def.get("mag")),
			str(HDData.RESERVE.get("an94", "缺")),
			str(HDData.AMMO_PRICE.get("an94", "缺"))])

	# 27d. SR25 商店枪专项（2026-10 并册·群星赛季半自动 DMR）：考证断言四件——
	#      ① 独立命名弹匣锚点 mag_sr25 在枪身根下（20 发 7.62 直-微弧匣，
	#        换弹手沿 mag_of 锚跟随的契约件，#27 循环只查 mag_* 存在性，
	#        这里锁名）
	#      ② 简介射速「364发每分」与 cd 换算一致 ±1%（60/0.1648=364.1，
	#        面板半自动连点上限 ref_03/04/05 三图读数）
	#      ③ 半自动落位：auto=false（tap 边沿门，按住只 1 弹）+ 弹匣 20
	#      ④ 备弹/购弹双表在表（RESERVE/AMMO_PRICE 缺键则 enter() 备弹 0 /
	#        交易行购弹静默拒）
	var s_root: Node3D = HDGuns._ar_build("sr25")
	var s_mag: Node = s_root.find_child("mag_sr25", true, false)
	check("SR25 独立命名弹匣锚点 mag_sr25 在根下", s_mag != null,
		"node=%s" % (str(s_mag.name) if s_mag != null else "无"))
	s_root.free()
	var s_def: Dictionary = Guns.gun_by_id("sr25")
	var s_rpm := 60.0 / float(s_def["cd"])
	check("SR25 简介射速 364发每分与 cd 换算一致（±1%）",
		str(s_def["desc"]).contains("364发每分")
			and absf(s_rpm - 364.0) / 364.0 <= 0.01,
		"cd=%s rpm=%.1f" % [str(s_def["cd"]), s_rpm])
	check("SR25 半自动落位（auto=false + 弹匣 20）",
		not bool(s_def.get("auto", true)) and int(s_def["mag"]) == 20,
		"auto=%s mag=%s" % [str(s_def.get("auto")), str(s_def.get("mag"))])
	check("SR25 备弹/购弹双表在表（7.62 弹族单价=scarh/m14 同 8）",
		(HDData.RESERVE as Dictionary).has("sr25")
			and (HDData.AMMO_PRICE as Dictionary).has("sr25")
			and int(HDData.AMMO_PRICE["sr25"]) == 8,
		"reserve=%s price=%s" % [str(HDData.RESERVE.get("sr25", "缺")),
			str(HDData.AMMO_PRICE.get("sr25", "缺"))])

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

	# 29. 高模顶点红线：冲锋枪册五枪（mp5/p90/uzi/vector/mp7，HDGunLib 高模
	#     重建）逐把枪身根总顶点 ≥ 8× 低模基线（走 _smg_build 分发入口，口径
	#     同 #26/#27/#28；mp5/p90/mp7 的静置真匣是独立命名弹匣节点（mag_curved/
	#     mag_top/mag_pdw，mag_of show=false）；uzi/vector 匣插握把、由动画匣
	#     表达（show=true）故无静置建模件、无节点断言；mk4 在 #26 单列）
	for gid in ["mp5", "p90", "uzi", "vector", "mp7"]:
		var smg_root: Node3D = HDGuns._smg_build(gid)
		var smg_verts: int = GUN_LIB.count_vertices(smg_root)
		check("冲锋枪 %s 高模顶点 ≥ POLY_MIN（8× 基线）" % gid,
			smg_verts >= int(GUN_LIB.POLY_MIN[gid]),
			"verts=%d min=%d base=%d" % [smg_verts, int(GUN_LIB.POLY_MIN[gid]),
				int(GUN_LIB.POLY_BASE[gid])])
		if not bool(HDGuns._smg_mag_of(gid)["show"]):
			# 写实枪（BL glb）就位时静置匣是 GLB 内置网格、无独立 mag_ 节点
			# （2026-10 写实化引入；程序化分支才要求独立节点）
			if not HDGuns._bl_ready(gid):
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

	# 29c. 一体成型 unibody 断言（2026-10 合并回归锁）：全枪册逐把枪
	#      _build_gun_visual 出厂链（含镜体合并与 Δ 平移）后——
	#      ① 枪身根下恰 1 个 MeshInstance3D 且名 unibody——分件全部并入
	#        单网格（镜体/机瞄件一并并入），物理上无件可裂
	#      ② 命名锚点保留：grip_hold（HOLD_DELTA 对齐断言的锚）必在；
	#        合并前树里存在的 mag_* 独立弹匣节点合并后原样重建（换弹手
	#        沿 mag_of 锚点跟随的契约不变）
	#      ③ 顶点总数守恒：合并前（各册 build 工厂产物，无镜体无 Δ）与
	#        合并后 count_vertices 相等——append_from 平移拷贝零焊接零
	#        丢失（commit 前不 index()，纯加和）；POLY_MIN 红线口径不变
	var uni_bad: Array = []
	for g_def in Guns.GUNS:
		var u_gid: String = str(g_def["id"])
		# 合并前基准：四路工厂直接产物 + 同参 _finish_gun 镜体（= 合并
		# 链里 merge_unibody 之前的完整形态；漏镜体会差出 iron 机瞄 2 盒
		# 48 顶点，首个版本就栽在这）
		var pre_root: Node3D
		var pre_anchor: Vector3
		if HDGuns._smg_has(u_gid):
			pre_root = HDGuns._smg_build(u_gid)
			pre_anchor = HDGuns._smg_scope_anchor(u_gid)
		elif HDGuns._ar_has(u_gid):
			pre_root = HDGuns._ar_build(u_gid)
			pre_anchor = HDGuns._ar_scope_anchor(u_gid)
		elif HDGuns._lmg_has(u_gid):
			pre_root = HDGuns._lmg_build(u_gid)
			pre_anchor = HDGuns._lmg_scope_anchor(u_gid)
		else:
			pre_root = HDGuns._old5_build(u_gid)
			pre_anchor = HDGuns._old5_scope_anchor(u_gid)
		main.guns._finish_gun(pre_root, u_gid, pre_anchor)
		var pre_verts: int = GUN_LIB.count_vertices(pre_root)
		var pre_mag: Node = pre_root.find_child("mag_*", true, false)
		var pre_grip: Node = pre_root.find_child("grip_hold", true, false)
		pre_root.free()
		# 合并后：完整出厂链
		var post_root: Node3D = main.guns._build_gun_visual(u_gid)
		var u_mis: Array = post_root.find_children("*", "MeshInstance3D",
			true, false)
		if u_mis.size() != 1 or str((u_mis[0] as MeshInstance3D).name) != "unibody":
			uni_bad.append("%s:MeshInstance3D=%d(应恰 1 名 unibody)" % [u_gid,
				u_mis.size()])
		if pre_grip != null and post_root.find_child("grip_hold", true, false) == null:
			uni_bad.append("%s:grip_hold 丢失" % u_gid)
		if pre_mag != null and post_root.find_child("mag_*", true, false) == null:
			uni_bad.append("%s:mag_* 丢失" % u_gid)
		var post_verts: int = GUN_LIB.count_vertices(post_root)
		if post_verts != pre_verts:
			uni_bad.append("%s:顶点 %d→%d" % [u_gid, pre_verts, post_verts])
		post_root.free()
	check("全枪册 unibody 合并（恰 1 MeshInstance3D+锚点保留+顶点守恒）",
		uni_bad.is_empty(), "违例=%s" % str(uni_bad).substr(0, 300))

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
	#      ① ensure 预生成全 20 枪流（SHOT_TUNE 不得缺枪，缺了只能懒生成兜底）
	#      ② 时长分级 sniper > rifle > pistol 且全部 ≤0.5s
	#      ③ 波形峰值 >0.2（非哑弹：归一后 0.88×gain，最短的枪也远过线）
	#      ④ 过零率 >3× 纯正弦（证明高频 crack 成分在场——只剩 boom 正弦的
	#        回归约 440/s 会当场撞线）
	#      ⑤ play_shot 每发随机：轮换池刚用的播放器 pitch ∈[0.94,1.06]、
	#        音量在基准 ±1.5dB 内（真枪每发都不同）
	var audio = main.guns.audio
	audio.ensure()   # 幂等：已建则跳过；无论冷热路径都保证 20 枪预生成
	var miss_pre: Array = []
	for g_def in Guns.GUNS:
		if not audio._shots.has(str(g_def["id"])):
			miss_pre.append(str(g_def["id"]))
	check("枪声 ensure 预生成全 20 枪流（SHOT_TUNE 不缺枪）", miss_pre.is_empty(),
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
	check("20 枪过零率 >3× 纯正弦 %.0f/s（高频 crack 在场）" % sine_rate,
		zcr_bad.is_empty(), str(zcr_bad))
	check("20 枪波形峰值 >0.2（非哑弹）", peak_bad.is_empty(), str(peak_bad))
	check("20 枪总时长 ≤0.5s", len_bad.is_empty(), str(len_bad))
	check("时长分级 sniper > rifle > pistol",
		float(shot_len["sniper"]) > float(shot_len["rifle"])
			and float(shot_len["rifle"]) > float(shot_len["pistol"]),
		"sniper=%.3f rifle=%.3f pistol=%.3f" % [shot_len["sniper"],
			shot_len["rifle"], shot_len["pistol"]])
	# asval 消音专项档（2026-10 商店枪，用户点名「注意声音」）：自带一体
	# 消音器的音色必须与普通枪拉开档位——①SHOT_TUNE 专项条目在表（不套
	# rifle 档）；②波形峰值能量 < 普通步枪档（归一后峰值=0.88×gain，总
	# 增益低一档即「消音=安静」）；③总时长短促闷收 ≤0.16s 且 < rifle
	#（尾音 0.10s 短闷收，普通步枪 0.24s+）
	check("asval 消音枪声专项条目（SHOT_TUNE 独立调音）",
		(HDAudio.SHOT_TUNE as Dictionary).has("asval"))
	check("asval 峰值能量 < 普通步枪档（消音=安静）",
		float(shot_peak["asval"]) < float(shot_peak["rifle"]),
		"asval=%.2f rifle=%.2f" % [float(shot_peak["asval"]),
			float(shot_peak["rifle"])])
	check("asval 时长短促闷收（≤0.16s 且 < rifle）",
		float(shot_len["asval"]) <= 0.16
			and float(shot_len["asval"]) < float(shot_len["rifle"]),
		"asval=%.3f rifle=%.3f" % [float(shot_len["asval"]),
			float(shot_len["rifle"])])
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
	main.lobby._toggle_prep(true)   # 战备收拢后：槽卡/枪行在战备面板里，先展开再点
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
	main.lobby._toggle_prep(false)
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
	# 29e2. 改枪台左列点击回归（用户报告「点没拥有的枪会直接开局」——战备收拢改造
	#       曾把 _confirm_deploy 的收起早退分支劫持成 _fire_deploy）：未拥有=指路
	#       不开局不扣款 · 已拥有=装入聚焦槽不开局；两条都必须停留在大厅
	main.lobby.show_lobby()
	main.lobby.set_tab(1)
	main.lobby._prep_open = false   # 触发过 bug 的状态（战备收起）
	var bench_unowned := -1
	var bench_owned := -1
	var lo_p := str(main.stash.loadout.get("primary", ""))
	var lo_s := str(main.stash.loadout.get("secondary", ""))
	for gi0 in Guns.GUNS.size():
		var gid0 := str(Guns.GUNS[gi0]["id"])
		# 已拥有样本避开两槽在装枪（_load_gun 的「主副不可同枪」守卫会拒装）
		if bench_owned < 0 and main.stash.guns_owned.has(gid0) \
				and gid0 != lo_p and gid0 != lo_s:
			bench_owned = gi0
		if bench_unowned < 0 and not main.stash.guns_owned.has(gid0):
			bench_unowned = gi0
	check("改枪台夹具：找到未拥有/已拥有样本", bench_unowned >= 0 and bench_owned >= 0)
	if bench_unowned >= 0:
		var cash_b: int = main.stash.cash
		var lo_b: Dictionary = main.stash.loadout.duplicate()
		main.lobby._hint_label.text = ""
		main.lobby._on_bench_row_input(mb, 0, bench_unowned)
		check("改枪台点未拥有枪：不开局只指路（按 3 进交易行）",
			main.lobby.lobby_visible and main.stash.cash == cash_b
				and str(main.stash.loadout) == str(lo_b)
				and main.lobby._hint_label.text.contains("按 3 进交易行"),
			"hint=%s" % main.lobby._hint_label.text)
	if bench_owned >= 0:
		main.lobby._slot_focus = "primary"
		var gid_o := str(Guns.GUNS[bench_owned]["id"])
		main.lobby._on_bench_row_input(mb, 0, bench_owned)
		check("改枪台点已拥有枪：装入聚焦槽且不开局",
			main.lobby.lobby_visible
				and str(main.stash.loadout.get("primary")) == gid_o,
			"primary=%s" % str(main.stash.loadout.get("primary")))
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

	# 29f. 贴掩体吞枪防线回归（2026-10「掩体分裂」定案 → 架构演化版）：
	#      老三件套（4f79b10 no_depth_test+render_priority 10）的前提是枪
	#      在主世界渲染、靠关深度测试防掩体吞枪；81309a1 把枪模迁入
	#      own_world_3d 独立视口后 vm 世界零场景几何，吞枪病因物理消失，
	#      一体成型 unibody 恢复 no_depth_test=false（枪件间 per-pixel
	#      物理遮挡——分件引擎排序观感的结构性替代，白盘悬空三案的终审
	#      修法，见 HDGunLib.merge_unibody 头注）。断言随架构演化：
	#      ① 全枪册每把枪 _build_gun_visual 产物（=unibody）遍历全部
	#        surface 材质，断言 no_depth_test=false（vm 世界物理遮挡契约：
	#        表面若残留 ndt=true 会退回无深度直画，白盘/读色案当场复发）
	#        且 render_priority≥10（防线参数不丢）；材质为 null 的表面也
	#        计违例（null 走引擎默认材质，深度/排序语义不受控）。
	#      ② 已挂载槽位枪架 holder 带 vm_fill 补光 OmniLight3D（energy≥0.5、
	#        range≥0.8、不开阴影）——锁主修公共链：全枪册可读性只认
	#        _mount_slot 这一條出口（四路枪册+旧五枪全走此链），灯被误删
	#        则贴掩体全枪册齐瞎、复发「分裂」。
	#      ③ _smg_mats MP7 全系 emission_energy_multiplier≥0.3——锁三件套
	#        第三件（微自发光保暗处可读）：6d193b5/90cc58b 判图修「蓝白
	#        串色」时全系归 0，掩体阴影里碳黑枪身亮度塌到不可辨即此回归。
	#      例外：美术写实化换上的实拍扫描枪（HDGuns.PH_GUNS：手枪/狙击）——
	#      多部件真实模型关深度测试会让机匣内部件透到表面；枪模已整体在
	#      own_world_3d 独立视口（81309a1），vm 世界没有掩体可吞，深度测试
	#      开着才画得对。这些网格反向断言「深度测试开着」，其余枪照旧锁防线。
	#      一体成型后实拍件并进 unibody（合并器取逐面覆盖材质），与全枪册同走
	#      上面 ndt=false+priority≥10 断言；按名豁免只在 HD_NO_MERGE 分件态生效
	var ph_names: Array = []
	for ph_id in HDGuns.PH_GUNS:
		ph_names.append_array(HDGuns.PH_GUNS[ph_id]["keep"])
	var mat_bad: Array = []
	var surf_total := 0
	for g_def in Guns.GUNS:
		var m_gid: String = str(g_def["id"])
		var m_root: Node3D = main.guns._build_gun_visual(m_gid)
		for mi_v in m_root.find_children("*", "MeshInstance3D", true, false):
			var mi := mi_v as MeshInstance3D
			if mi.mesh == null:
				continue
			if ph_names.has(str(mi.name)):
				for s2 in mi.mesh.get_surface_count():
					var om := mi.get_surface_override_material(s2) as StandardMaterial3D
					surf_total += 1
					if om == null or om.no_depth_test:
						mat_bad.append("%s/%s:s%d(实拍枪须开深度测试)" % [m_gid, mi.name, s2])
				continue
			for s in mi.mesh.get_surface_count():
				var mat: Material = mi.mesh.surface_get_material(s)
				if mat == null:
					mat = mi.get_surface_override_material(s)
				surf_total += 1
				var sm := mat as StandardMaterial3D
				if mat == null or sm.no_depth_test or sm.render_priority < 10:
					mat_bad.append("%s/%s:s%d" % [m_gid, mi.name, s])
		m_root.free()
	check("全枪册 unibody 表面物理深度（ndt=false）+priority≥10",
		mat_bad.is_empty() and surf_total > 0,
		"违例=%s 审计表面数=%d" % [str(mat_bad).substr(0, 300), surf_total])
	var fill_bad: Array = []
	for slot_v in main.guns._guns:
		var fills: Array = (main.guns._guns[slot_v]["holder"] as Node3D).find_children(
				"vm_fill", "OmniLight3D", true, false)
		if fills.size() != 1:
			fill_bad.append("%s:vm_fill×%d" % [slot_v, fills.size()])
			continue
		var fl := fills[0] as OmniLight3D
		if fl.light_energy < 0.5 or fl.omni_range < 0.8 or fl.shadow_enabled:
			fill_bad.append("%s:energy=%.2f range=%.2f shadow=%s" % [slot_v,
					fl.light_energy, fl.omni_range, str(fl.shadow_enabled)])
	check("挂载枪架带 viewmodel 补光（失直射光保全枪册可读）",
		not main.guns._guns.is_empty() and fill_bad.is_empty(), str(fill_bad))
	# 29f+（2026-10 第三轮「补光域隔离」回归锁，与根因一一对应）：3562cd3 的
	#      vm_fill 补光同时照亮 0.9m 内掩体面——贴掩体亮斑随枪扫动（ADS 进出
	#      0.40~0.70 档最强）读作「枪分成两截」，E8 隐灯即消失一票定罪。两条
	#      断言各锁一半修法、缺一即复发：
	#      ① vm_fill.light_cull_mask == 2（只作用 render layer 2）：掩体面
	#        不再被打亮——亮斑扫墙这一可视异常源被根除；
	#      ② 挂载枪架 holder 子树全部 MeshInstance3D（枪身/镜体/动画匣/
	#        火光片）layers 含位 1<<1：灯只照层 2，枪模不入层 2 = 补光失效
	#        黑枪、暗部塌陷复发（退回 3562cd3 之前）。
	var cull_bad: Array = []
	var layer_bad: Array = []
	for slot_v in main.guns._guns:
		var lh: Node3D = main.guns._guns[slot_v]["holder"]
		var fills2: Array = lh.find_children("vm_fill", "OmniLight3D", true, false)
		if fills2.size() == 1 and (fills2[0] as OmniLight3D).light_cull_mask != (1 << 1):
			cull_bad.append("%s:cull=%d" % [slot_v,
				(fills2[0] as OmniLight3D).light_cull_mask])
		for mi_v2 in lh.find_children("*", "MeshInstance3D", true, false):
			if (mi_v2 as MeshInstance3D).layers & (1 << 1) == 0:
				layer_bad.append("%s/%s" % [slot_v, (mi_v2 as MeshInstance3D).name])
	check("vm_fill 补光 cull_mask 只作用层 2（不照墙根除亮斑扫动）",
		not main.guns._guns.is_empty() and cull_bad.is_empty(), str(cull_bad))
	check("挂载枪模全 mesh 入补光层 2（vm_fill 照得到枪）",
		not main.guns._guns.is_empty() and layer_bad.is_empty(), str(layer_bad))
	var smg_mats: Dictionary = HDGuns._smg_mats()
	var glow_bad: Array = []
	for mk_v in smg_mats:
		if not str(mk_v).begins_with("mp7"):
			continue
		var pm: StandardMaterial3D = smg_mats[mk_v]
		if not pm.emission_enabled or pm.emission_energy_multiplier < 0.3:
			glow_bad.append("%s=%.2f" % [str(mk_v), pm.emission_energy_multiplier])
	check("MP7 全系材质微自发光 ≥0.3（三件套第三件）",
		glow_bad.is_empty(), str(glow_bad))

	# 29g. viewmodel 独立视口（2026-10「贴掩体分裂」根治架构回归）：枪模整体
	#      迁入 own_world_3d SubViewport——vm 世界零场景几何，枪与掩体的深度
	#      交互物理消失（贴掩体枪管穿墙叠画成两截、透明掩体整层盖枪两条病
	#      因同根除）。逐条断言各锁一环，缺一即架构回退：
	var vm_vp: SubViewport = main.player.vm_viewport
	check("vm SubViewport 存在且 own_world_3d+透明底+常更新",
		vm_vp != null and vm_vp.own_world_3d and vm_vp.transparent_bg
			and vm_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"own=%s" % str(vm_vp != null and vm_vp.own_world_3d))
	check("vm 相机与主相机不同 World3D（枪与掩体深度隔离在）",
		main.player.vm_cam != null
			and main.player.vm_cam.get_world_3d() != main.player.cam.get_world_3d())
	check("合成层介于世界与 HUD 之间（layer 5，HUD=10/大厅=20）",
		main.player.vm_layer != null and main.player.vm_layer.layer == 5)
	var chain_bad: Array = []
	for slot_v3 in main.guns._guns:
		var h3: Node3D = main.guns._guns[slot_v3]["holder"]
		if not vm_vp.is_ancestor_of(h3):
			chain_bad.append(str(slot_v3))
	check("枪架 holder 父链在 vm 世界（vm_viewport 祖先）",
		not main.guns._guns.is_empty() and chain_bad.is_empty(), str(chain_bad))
	# muzzle_world 连续性（mm 级）：vm 相机每帧同步主相机 → holder 在 vm 世
	# 界的 to_global 数值必须等于「主相机 transform × 枪架局部 × 枪口点」——
	# 曳光起点/掉匣落点/换弹手锚全靠这条不变量零改动。甩视角改摆位后复核，
	# 防「只在进场同步一次」的假成立
	main.player.pos = Vector3(33.0, 0.0, 44.0)
	main.player.yaw += 2.3
	main.player.pitch = 0.2
	main.player.update(0.016)
	var mz_g: Dictionary = main.guns._cur_gun()
	var mz_off: Vector3 = mz_g["muzzle_off"]
	var mz_holder: Node3D = mz_g["holder"]
	var mz_d: float = main.guns.muzzle_world().distance_to(
			main.player.cam.global_transform * (mz_holder.transform * mz_off))
	var vm_d: float = main.player.vm_cam.global_transform.origin.distance_to(
			main.player.cam.global_transform.origin)
	check("muzzle_world 与主相机数学连续（mm 级容差）", mz_d < 0.001,
		"d=%.5f" % mz_d)
	check("vm 相机 transform 同步主相机（mm 级容差）", vm_d < 0.001,
		"d=%.5f" % vm_d)
	# HIDE_ZOOM 藏枪照旧：sniper 自带 6×，开镜到位（ads≥1 且 zoom≥3）枪模
	# 隐藏——vm 世界不改变这条显示逻辑（摆位/可见性全在 holder 局部）
	main._start_mission({"primary": "sniper", "secondary": "pistol"})
	await frames(8)
	Input.action_press("hd_scope")
	var hz_hidden := false
	for i in 200:
		main.player.update(0.016)
		main.guns.update(0.016)
		if main.player.ads >= 1.0 and main.guns.current_zoom() >= HDGuns.HIDE_ZOOM \
				and not (main.guns._guns["primary"]["holder"] as Node3D).visible:
			hz_hidden = true
			break
	Input.action_release("hd_scope")
	check("HIDE_ZOOM≥3 开镜到位藏枪照旧（vm 世界）", hz_hidden)
	# 世界空间件去留审计：枪口闪光主世界镜像灯（墙面受闪光照明零回退）、
	# 曳光池与掉落匣替身（要与世界交互的结算件）各归其位
	var fz_bad: Array = []
	for slot_v4 in main.guns._guns:
		var fz: OmniLight3D = main.guns._guns[slot_v4]["flash_env"]
		if fz == null or fz.get_parent() != main.player.cam:
			fz_bad.append(str(slot_v4))
	check("枪口闪光镜像灯留主世界（挂主相机下）",
		not main.guns._guns.is_empty() and fz_bad.is_empty(), str(fz_bad))
	check("曳光池/掉落匣替身留在主世界（与世界交互照旧）",
		main.guns.tracers != null
			and not vm_vp.is_ancestor_of(main.guns.tracers)
			and main.guns._falling_mag != null
			and not vm_vp.is_ancestor_of(main.guns._falling_mag))

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
	# 军营北墙东段（原长度误写 10.62 留两处 3.8m 缺口）：隧道口东侧 x=−114 与
	# 东北角 x=−100 从北院 z=−38 向北采样均应抵墙皮 z=−41.5
	var wh_camp_n1: float = main.world.wall_hit(Vector3(-114.0, 1.55, -38.0),
			Vector3(0.0, 0.0, -1.0), 300.0)
	var wh_camp_n2: float = main.world.wall_hit(Vector3(-100.0, 1.55, -38.0),
			Vector3(0.0, 0.0, -1.0), 300.0)
	check("军营北墙东段无缺口 wall_hit ≈3.5m（隧道口东侧/东北角）",
		absf(wh_camp_n1 - 3.5) < 0.5 and absf(wh_camp_n2 - 3.5) < 0.5,
		"d=%.1f/%.1f" % [wh_camp_n1, wh_camp_n2])
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
	main._raid_t = HDData.DAM_OPEN_T + 1.0   # 大坝撤离点 12 分钟后才开（第三阶段）
	main.player.enter(main.world.extract2_pos)
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

	# §经济门槛 A（改进方案第 2 节 / 衡量指标第 1 行）：2,000 局 × 随机 12 箱
	#  （背包上限），中位局战利品 ÷ 中档出发装备 KIT_REF 须落 1.2–1.6 倍——
	#  撤离就赚、阵亡就亏；固定种子保证可复现
	seed(20261018)
	# 按容器分类 roll（第三阶段：武器/医疗/杂物/保险箱）；首领保险柜不计——要先
	# 打赢首领，属于「高风险高回报」的额外收益，不是普通搜刮的基准
	var mc_spots: Array = main.loot._containers.filter(func(c): return str(c["cls"]) != "vault")
	var mc_tot: Array = []
	for r in 2000:
		var idxs: Array = range(mc_spots.size())
		idxs.shuffle()
		var tot := 0.0
		for k in HDData.BACKPACK_MAX:
			var c0: Dictionary = mc_spots[idxs[k]]
			var sp: Vector3 = c0["pos"]
			tot += float(HDData.roll_container(str(c0["cls"]), main.world.zone_at(sp.x, sp.z))["value"])
			HDData.roll_bonus(str(c0["cls"]))   # 额外物资多半局内用掉，不计入门槛（照常耗一次随机数）
		mc_tot.append(tot)
	mc_tot.sort()
	randomize()
	var mc_med: float = mc_tot[1000]
	var mc_ratio := mc_med / float(HDData.KIT_REF)
	check("经济门槛 A：中位局 ÷ 中档装备 ∈ [1.2, 1.6]", mc_ratio >= 1.2 and mc_ratio <= 1.6,
		"P10=₵%d P50=₵%d P90=₵%d ratio=%.2f" % [int(mc_tot[200]), int(mc_med),
			int(mc_tot[1800]), mc_ratio])

	# §带入即风险：带 AKM + 红点镜 + 200 发出发，背包 1 件、安全箱 1 件 → 阵亡
	main.stash.cash = 99999
	main.stash.buy_gun("akm")
	main.stash.buy_scope("reddot")
	main.stash.equip_scope("akm", "reddot")
	main.stash.set_ammo("akm", 200)
	main.stash.loadout = {"primary": "akm", "secondary": "pistol"}
	var risk_v: int = main.stash.carried_value(main.stash.loadout)
	check("出发风险估值 = 枪 + 镜 + 备弹（手枪不计枪价）",
		risk_v == 1700 + 700 + 200 * 6 + main.stash.ammo_of("pistol") * 2, "v=%d" % risk_v)
	main._start_mission(main.stash.loadout)
	await frames(6)
	check("安全箱格数随存档", main.loot.secure_cap == main.stash.secure_slots)
	main.loot.backpack.append({"uid": "t_bag", "name": "测试零件", "icon": "", "rarity": 2, "value": 300})
	main.loot.secure.append({"uid": "t_sec", "name": "测试金条", "icon": "", "rarity": 4, "value": 3000})
	main.player.hit(9999.0)
	await frames(2)
	check("阵亡丢 AKM + 所装红点镜", not main.stash.owns_gun("akm")
		and not main.stash.owns_scope("reddot"))
	check("阵亡 AKM 备弹清零", main.stash.ammo_inv.get("akm", -1) == 0)
	check("安全箱物品阵亡保留入库", main.stash._find_uid("t_sec") >= 0)
	check("背包物品阵亡丢失", main.stash._find_uid("t_bag") < 0)

	# §放弃行动 = 阵亡：局内 Esc「放弃」回大厅也丢装备、记阵亡
	main.stash.buy_gun("akm")
	main.stash.loadout = {"primary": "akm", "secondary": "pistol"}
	main._start_mission(main.stash.loadout)
	await frames(4)
	var deaths0: int = int(main.stash.stats["deaths"])
	main._back_to_lobby()
	check("放弃行动视同阵亡（记阵亡 + 丢枪）", int(main.stash.stats["deaths"]) == deaths0 + 1
		and not main.stash.owns_gun("akm"))

	# §单枪出发 + Tab 背包：弃件落地 → 按住 F 捡回 → 移入安全箱 → 满包开箱自动交换
	main._start_mission({"primary": "pistol", "secondary": ""})
	# 本节断言地上件数精确值：清掉本局随机刷的钥匙落地件（阶段 B 锁房）
	for g0 in main.loot._ground.duplicate():
		(g0["node"] as Node3D).queue_free()
	main.loot._ground.clear()
	main.loot._ground_i = -1
	await frames(4)
	check("单枪出发（副武器空槽只装一把）", main.guns._slots.size() == 1
		and str(main.guns.cur_id) == "pistol")
	for i in HDData.BACKPACK_MAX:
		main.loot.backpack.append({"uid": "f%02d" % i, "name": "废料", "icon": "",
			"rarity": 0, "value": 20 + i})
	main._route_key(KEY_TAB)
	check("Tab 打开背包（鼠标放出）", main.hud.inv_visible
		and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
	main._on_inv_drop(false, 0)
	check("弃件：背包 -1 · 地上 +1", main.loot.backpack.size() == HDData.BACKPACK_MAX - 1
		and main.loot.ground_count() == 1)
	main._close_inventory()
	var gpos: Vector3 = main.loot._ground[0]["pos"]
	for i in 30:
		main.loot.update(0.016, gpos, true)
	check("地上物品按住 F 捡回", main.loot.backpack.size() == HDData.BACKPACK_MAX
		and main.loot.ground_count() == 0)
	main._on_inv_move(false, 0)
	check("移入安全箱", main.loot.secure.size() == 1
		and main.loot.backpack.size() == HDData.BACKPACK_MAX - 1)
	main.loot.backpack.append({"uid": "f_cheap", "name": "废料", "icon": "", "rarity": 0, "value": 1})
	for it in main.loot.backpack:
		it["value"] = 1
	var c_spot: Vector3 = main.world.container_spots[2]["pos"]
	for i in 130:
		main.loot.update(0.016, c_spot, true)
	var bag_max := 0.0
	for it in main.loot.backpack:
		bag_max = maxf(bag_max, float(it["value"]))
	check("满包开箱：新件更值钱自动交换（旧件落地不销毁）",
		main.loot.backpack.size() == HDData.BACKPACK_MAX and main.loot.ground_count() >= 1
			and bag_max > 1.0,
		"bag=%d ground=%d" % [main.loot.backpack.size(), main.loot.ground_count()])
	main._win_raid()

	# §安全箱扩容：2→3 格 ₵4,000（不足拦截）· 上限 4 格
	main.stash.secure_slots = HDData.SECURE_BASE
	main.stash.cash = 3999
	check("安全箱扩容现金不足拦截", not main.stash.buy_secure_upgrade()
		and main.stash.secure_slots == HDData.SECURE_BASE and main.stash.cash == 3999)
	main.stash.cash = 14000
	check("安全箱扩容 2→3→4 扣款", main.stash.buy_secure_upgrade()
		and main.stash.buy_secure_upgrade() and main.stash.secure_slots == HDData.SECURE_MAX
		and main.stash.cash == 0 and not main.stash.buy_secure_upgrade())

	# §存档 v1→v2 迁移：现金与仓库物品价值 ÷10，已买枪/瞄具保留
	var fv1 := FileAccess.open(HDData.SAVE_PATH, FileAccess.WRITE)
	fv1.store_string(JSON.stringify({"v": 1, "cash": 15000,
		"items": [{"uid": "m1", "name": "金条", "icon": "贵金属", "rarity": 4, "value": 42000}],
		"guns_owned": ["rifle", "akm"], "scopes_owned": ["holo"],
		"loadout": {"primary": "akm", "secondary": "rifle"}}))
	fv1.close()
	var st_m := HDStash.new()
	check("存档 v1→v2：现金 ÷10", st_m.cash == 1500, "cash=%d" % st_m.cash)
	check("存档 v1→v2：仓库物品价值 ÷10", st_m.items.size() == 1
		and int(st_m.items[0]["value"]) == 4200)
	check("存档 v1→v2：已买枪/瞄具保留 + 补永久手枪", st_m.owns_gun("akm")
		and st_m.owns_gun("rifle") and st_m.owns_gun("pistol") and st_m.owns_scope("holo"))
	main.stash.save()   # 写回测试主档
	# §射速回归（射速问题三源定案修复：假半自动/帧量化九档/表值错位）：
	#   ① 半自动三枪（pistol/sniper/sr25，表 auto=false）按住 60 帧（1s）只
	#      发 1 弹——修复前无 tap 边沿门，pistol 按住 1s 连放 4 发（假半自动）；
	#      （2026-10-19 用户定案 M14 改全自动 730rpm，移出半自动组；
	#      2026-10-26 SR25 半自动 DMR 并册入组）
	#   ② 全自动长程射速 = 表值：vector 表 1200rpm（修复前帧量化压到 900）、
	#      mp5 表 800（前 720）、m14 表 730（前半自动 214）、m250 表 550——
	#      追赶式结转冷却（fire_cd -= dt / += cd 配对）让晚过门的帧量逐发
	#      补回，300 帧（5s）发数对表值 ±2；
	#   ③ desc 写明「N发每分」的枪（m250/mp7/m14），cd 换算 RPM 与文案一致 ±1%；
	#   ④ 切枪清冷却 + 切枪当帧不丢拍（修复前 _equip 不清 fire_cd、切枪帧
	#      提前 return 丢 1 拍开火）
	var semi_bad: Array = []
	for semi_gid in ["pistol", "sniper", "sr25"]:
		main._start_mission({"primary": semi_gid, "secondary": "smg"})
		await frames(8)
		main.guns.ammo = 10
		main.guns.update(1.0 / 60.0)   # 空转一帧：清上一段的 _fire_prev 边沿态
		var semi_a0: int = main.guns.ammo
		Input.action_press("hd_fire")
		for i in 60:
			main.guns.update(1.0 / 60.0)
		Input.action_release("hd_fire")
		var semi_shots: int = semi_a0 - main.guns.ammo
		if semi_shots != 1:
			semi_bad.append("%s=%d发" % [semi_gid, semi_shots])
		main.guns.update(1.0 / 60.0)   # 松手帧：归位 _fire_prev
	check("半自动三枪按住 60 帧只发 1 弹（tap 边沿门）", semi_bad.is_empty(),
		str(semi_bad))
	# m14 已改全自动（2026-10-19）：断言翻面——auto 缺省 true + cd≈60/730
	check("半自动标志落位（pistol/sniper auto=false；m14 已全自动）",
		not bool(Guns.gun_by_id("pistol").get("auto", true))
			and not bool(Guns.gun_by_id("sniper").get("auto", true))
			and bool(Guns.gun_by_id("m14").get("auto", true))
			and absf(60.0 / float(Guns.gun_by_id("m14")["cd"]) - 730.0) < 8.0
			and bool(Guns.gun_by_id("rifle").get("auto", true))
			and bool(Guns.gun_by_id("vector").get("auto", true))
			and bool(Guns.gun_by_id("mp5").get("auto", true))
			and bool(Guns.gun_by_id("lmg").get("auto", true)))
	# 全自动长程射速：vector 1200rpm（cd 0.05——用户定案保留高射速特色）
	main._start_mission({"primary": "vector", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999   # 给足弹防中途自动换弹打断节拍
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 300:
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var vec_shots: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("vector 长程射速达表值 1200rpm（修复前帧量化 900）",
		absf(vec_shots - 100.0) <= 2.0, "shots=%d/300帧（5s）" % vec_shots)
	# mp5 800rpm（cd 0.075=4.5 帧/发：结转冷却 4/5 帧交替，长程精确）
	main._start_mission({"primary": "mp5", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 300:
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var mp5_shots: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("mp5 长程射速达表值 800rpm（修复前帧量化 720）",
		absf(mp5_shots - 66.7) <= 2.2, "shots=%d/300帧（5s）" % mp5_shots)
	# m14 全自动 730rpm（2026-10-19 用户定案；cd 0.0822 ≈ 4.93 帧/发结转）
	main._start_mission({"primary": "m14", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 300:
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var m14_shots: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("m14 全自动长程射速达表值 730rpm（原半自动 214）",
		absf(m14_shots - 60.8) <= 2.2, "shots=%d/300帧（5s）" % m14_shots)
	# SR25 全自动套件（2026-10-26 用户定案「很贵的全自动套件」）：未装=原厂
	# 半自动；装上（₵6800）=按住全自动 + 扳机每起边沿补两发点射 + 弹匣 20→45
	main.stash.m14_mods.erase("fullauto")   # 夹具：确保未购（幂等）
	main._sync_m14_mods_env()
	main._start_mission({"primary": "sr25", "secondary": "pistol"})
	await frames(8)
	check("SR25 原厂：半自动 20 发匣", not main.guns._g.get("auto", true)
		and main.guns._mag_cap() == 20)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 30:   # 未装套件按住 0.5s：半自动只 1 发
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var sr_stock: int = 999 - main.guns.ammo
	check("SR25 原厂按住 30 帧只 1 发（半自动）", sr_stock == 1, "shots=%d" % sr_stock)
	main.guns.update(1.0 / 60.0)
	main.stash.cash = 99999
	check("购 SR25 全自动套件（₵6800，M14 配件同链）", main.stash.buy_m14_mod("fullauto"))
	main._sync_m14_mods_env()
	main._start_mission({"primary": "sr25", "secondary": "pistol"})   # 重进场：cap/套件生效
	await frames(8)
	check("装套件：弹匣自动 20→45", main.guns._mag_cap() == 45)
	check("装套件：进场实装 45 发（enter 装填修复——旧版 cap0 只认 M14）",
		main.guns.ammo == 45, "ammo=%d" % main.guns.ammo)
	# 三次定案（2026-10-26）：B 键切换开火模式——默认全自动（1069rpm 连发），
	# B→MK4 式三连发（轮内同 1069rpm+轮间锁），再 B→全自动；靶场/实战都可用
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	check("套件默认全自动模式", not main.guns._kit_burst_mode)
	Input.action_press("hd_fire")
	for i in 30:   # 全自动 1069rpm（0.0561s≈3.37 帧/发）按住 0.5s ≈ 8 发
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var sr_auto: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("套件全自动：按住 0.5s ≈8 发（1069rpm）", sr_auto >= 7 and sr_auto <= 9,
		"shots=%d" % sr_auto)
	# B 切三连发：tap 边沿起 3 发、轮间锁内再点不起射
	var fm: String = main.guns.toggle_fire_mode()
	check("B 切换 → 三连发模式", fm == "burst" and main.guns._kit_burst_mode)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	for i in 12:
		main.guns.update(1.0 / 60.0)
	var sr_b3: int = 999 - main.guns.ammo
	check("三连发模式：点一下恰 3 发（1069rpm 轮内）", sr_b3 == 3, "shots=%d" % sr_b3)
	main.guns._burst_gap = 0.1   # 模拟轮刚打完（锁窗口内）
	Input.action_press("hd_fire")   # 锁内 tap
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	for i in 12:
		main.guns.update(1.0 / 60.0)
	var sr_locked: int = 999 - main.guns.ammo - sr_b3
	check("三连发轮间锁：锁内 tap 不起射", sr_locked == 0, "extra=%d" % sr_locked)
	# 再 B 切回全自动：按住恢复连发
	var fm2: String = main.guns.toggle_fire_mode()
	check("再 B 切回全自动", fm2 == "auto" and not main.guns._kit_burst_mode)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 24:   # 0.4s × 1069rpm/60 ≈ 7.1 发
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var sr_auto2: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("切回全自动：按住连发恢复（0.4s ≈7 发）", sr_auto2 >= 6 and sr_auto2 <= 8,
		"shots=%d" % sr_auto2)
	# 制退补偿实测（2026-10-27 用户报告「后坐力非常大」）：无套件 vs 套件
	# 各一发 pitch 比 ≈0.45（recoil_mul_to，握把未装口径）
	main.stash.m14_mods.erase("fullauto")
	main._sync_m14_mods_env()
	main._start_mission({"primary": "sr25", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 99
	main.guns.update(1.0 / 60.0)
	main.player.recoil_pitch = 0.0
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var rp0: float = main.player.recoil_pitch
	for i in 15:   # 清冷却
		main.guns.update(1.0 / 60.0)
	main.stash.m14_mods.append("fullauto")
	main._sync_m14_mods_env()
	main._start_mission({"primary": "sr25", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 99
	main.guns.update(1.0 / 60.0)
	main.player.recoil_pitch = 0.0
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var rp1: float = main.player.recoil_pitch
	main.guns.update(1.0 / 60.0)
	check("套件制退补偿 ≈45%（pitch 实测）",
		rp1 < rp0 * 0.6 and rp1 > rp0 * 0.3,
		"rp0=%.4f rp1=%.4f" % [rp0, rp1])
	main.stash.m14_mods.erase("fullauto")   # 夹具复位（后续按未购口径）
	main._sync_m14_mods_env()
	# m250 550rpm（2026-10-19 用户定案 cd 0.1091 精确对齐 desc）+ 扳机延迟
	# 0.5s（2026-10-24 用户定案 trigger_delay）：首发出弹在 0.5s 蓄力后，
	# 5s 按压实测 = 1 + floor(4.5/0.1091) ≈ 42 发；松开再按重新蓄满
	main._start_mission({"primary": "m250", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 300:
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var m250_shots: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("m250 长程射速 550rpm 且计 0.5s 扳机延迟（42 发/5s）",
		absf(m250_shots - 42.0) <= 2.0, "shots=%d/300帧（5s）" % m250_shots)
	# 延迟边界：按住 29 帧（<0.5s）零出弹；第 30 帧蓄满当帧放行出弹
	# （完成判据带 FIRE_GATE 容差——蓄满帧即首发，无额外一帧）
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 29:
		main.guns.update(1.0 / 60.0)
	var m250_early: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)   # 第 30 帧：0.5s 蓄满当帧首发
	var m250_first: int = 999 - main.guns.ammo
	Input.action_release("hd_fire")
	main.guns.update(1.0 / 60.0)
	check("m250 扳机延迟边界（29 帧零出弹 · 第 30 帧首发）",
		m250_early == 0 and m250_first >= 1,
		"early=%d first=%d" % [m250_early, m250_first])
	# 松开复位：再按又是全新 0.5s 蓄力（前 29 帧零出弹）
	main.guns.update(1.0 / 60.0)
	main.guns.ammo = 999
	Input.action_press("hd_fire")
	for i in 29:
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var m250_re: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("m250 松开再按重新蓄力（再按前 29 帧零出弹）", m250_re == 0,
		"shots=%d" % m250_re)
	# 其余枪零延迟抽查：rifle 按下当帧即出弹（trigger_delay 缺省 0）
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)
	var rifle_instant: int = 999 - main.guns.ammo
	Input.action_release("hd_fire")
	main.guns.update(1.0 / 60.0)
	check("无 trigger_delay 枪零延迟（rifle 按下当帧出弹）", rifle_instant >= 1,
		"shots=%d" % rifle_instant)
	# 共振前握把（2026-10-27 用户定案「大幅减少垂直后坐力」）：vy_mul 只压
	# 垂直轴（pitch ×0.30），水平漂移不变——顺带接活悬空的通用握把链
	var fg_def: Dictionary = Guns.grip_by_id("resonant_fg")
	check("共振前握把在表（vy_mul 0.3 · 水平 recoil_mul 1.0）",
		not fg_def.is_empty() and absf(float(fg_def["vy_mul"]) - 0.3) < 0.001
			and absf(float(fg_def["recoil_mul"]) - 1.0) < 0.001,
		str(fg_def))
	main.stash.cash = 99999
	check("购+装共振前握把（rifle）", main.stash.buy_grip("resonant_fg")
		and not main.stash.grips_owned.is_empty())
	main.stash.equip_grip("rifle", "resonant_fg")
	check("grip_vy_mul 装上=0.3 / 卸下=1.0",
		absf(main.stash.grip_vy_mul("rifle") - 0.3) < 0.001)
	main.stash.equip_grip("rifle", "none")
	check("grip_vy_mul 卸下回 1.0", absf(main.stash.grip_vy_mul("rifle") - 1.0) < 0.001)
	# 后坐分轴实测：步枪各打一发（无握把 vs 装共振前握把），pitch 增量比 ≈0.3
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 99
	main.guns.update(1.0 / 60.0)
	main.player.recoil_pitch = 0.0
	main.player.recoil_yaw = 0.0
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var pitch0: float = main.player.recoil_pitch
	for i in 15:   # 冷却清空（半自动 cd ~0.13s）再打第二发
		main.guns.update(1.0 / 60.0)
	main.stash.equip_grip("rifle", "resonant_fg")
	main.player.recoil_pitch = 0.0
	main.player.recoil_yaw = 0.0
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var pitch1: float = main.player.recoil_pitch
	main.guns.update(1.0 / 60.0)
	check("装共振前握把垂直后坐 ≈30%（pitch 实测）",
		pitch1 < pitch0 * 0.5 and pitch1 > pitch0 * 0.1,
		"p0=%.4f p1=%.4f" % [pitch0, pitch1])
	main.stash.equip_grip("rifle", "none")   # 夹具复位（卸握把）
	# 镜体增高架（2026-10-28 用户定案）：红点装其上抬高 RISER_H——aim_y 差
	# 精确等于抬高量（ADS 对位自动跟随的证据），建模件在位（HD_NO_BL 强制
	# 程序化路径下量 riser 盒）；装卸 toggle 与买断态
	main.stash.cash = 99999
	check("购增高架（₵1200 买断）", main.stash.buy_riser()
		or main.stash.owns_riser())
	main.stash.scopes_owned.append("reddot")
	main.stash.loadout = {"primary": "rifle", "secondary": "pistol"}
	main.stash.equip_scope("rifle", "reddot")
	if main.stash.riser_on("rifle"):            # 强制归零：基线=无增高架
		main.stash.toggle_riser("rifle")
	# 确定性直测（dbg 已证）：build+读 rd_aim_y meta——卸/装差恰 RISER_H，
	# ADS 对位（_mount_slot aim_y→update 摆位）消费同一数值链自动跟随
	var r_no: Node3D = main.guns._build_gun_visual("rifle")
	var aim0: float = float(r_no.get_meta("rd_aim_y", -1.0))
	var v_no: int = _mesh_verts(r_no)
	r_no.free()
	check("无增高架基线：aim_y 与顶点在位", aim0 > 0.0 and v_no > 0,
		"aim0=%.4f v=%d" % [aim0, v_no])
	main.stash.toggle_riser("rifle")
	var r_yes: Node3D = main.guns._build_gun_visual("rifle")
	var aim1: float = float(r_yes.get_meta("rd_aim_y", -1.0))
	var v_yes: int = _mesh_verts(r_yes)
	r_yes.free()
	check("增高架抬高 aim_y 恰 RISER_H（ADS 自动对位）",
		absf(aim1 - aim0 - HDGuns.RISER_H) < 0.002,
		"aim0=%.4f aim1=%.4f rise=%.4f" % [aim0, aim1, aim1 - aim0])
	check("增高架建模件在位（装/卸顶点差 >0）", v_yes > v_no,
		"v_no=%d v_yes=%d" % [v_no, v_yes])
	main.stash.toggle_riser("rifle")   # 夹具复位（卸下）
	# 幻影后握把（2026-10-29 三角洲考证落地）：REAR_GRIPS 表 + per-gun
	# rear_grip_fit（照 grip_fit 先例）+ _mod_muls 开镜消费点 + rear_phantom
	# 建模件在位（命名节点 + 顶点差）+ 老档兼容（空表）
	var ph_def: Dictionary = Guns.rear_grip_by_id("phantom")
	check("幻影后握把在表（ads_mul 1.15 档）", not ph_def.is_empty()
		and str(ph_def.get("id", "")) == "phantom"
		and absf(float(ph_def["ads_mul"]) - 1.15) < 0.001, str(ph_def))
	main.stash.cash = 99999
	check("购幻影后握把（₵2800 入拥有集）", main.stash.buy_rear_grip("phantom")
		and main.stash.owns_rear_grip("phantom"))
	main.stash.equip_rear_grip("rifle", "phantom")
	check("rear_grip_fit 落位（rifle→phantom）+ 未装枪回 1.0",
		main.stash.rear_grip_id("rifle") == "phantom"
			and is_equal_approx(main.stash.rear_grip_ads_mul("smg"), 1.0)
			and absf(main.stash.rear_grip_ads_mul("rifle") - 1.15) < 0.001,
		"fit=%s mul=%.4f" % [main.stash.rear_grip_id("rifle"),
			main.stash.rear_grip_ads_mul("rifle")])
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(8)
	var mm_rp: Vector2 = main.guns._mod_muls()
	check("后握把开镜乘数进 _mod_muls（装=×1.15）", absf(mm_rp.y - 1.15) < 0.001,
		str(mm_rp))
	# 建模件在位：卸/装 _build_gun_visual 对比——rear_phantom 命名节点 + 顶点差
	# （一体成型后几何并入 unibody、命名锚点由合并器保留——hd_gunlib keepers）
	main.stash.equip_rear_grip("rifle", "none")
	var rg_no: Node3D = main.guns._build_gun_visual("rifle")
	var rgv_no: int = _mesh_verts(rg_no)
	var rg_node_no: bool = rg_no.find_child("rear_phantom", true, false) != null
	rg_no.free()
	main.stash.equip_rear_grip("rifle", "phantom")
	var rg_yes: Node3D = main.guns._build_gun_visual("rifle")
	var rgv_yes: int = _mesh_verts(rg_yes)
	var rg_node_yes: bool = rg_yes.find_child("rear_phantom", true, false) != null
	rg_yes.free()
	check("rear_phantom 建模件在位（卸=无节点 · 装=有节点 + 顶点差>0）",
		(not rg_node_no) and rg_node_yes and rgv_yes > rgv_no,
		"v_no=%d v_yes=%d" % [rgv_no, rgv_yes])
	main.stash.equip_rear_grip("rifle", "none")   # 夹具复位（卸后握把）
	# 骨架狙击枪托（2026-10-29 deltaforcetools 考证）：SKEL_STOCK 专属表
	# （m14_mods 同链存储）+ sniper _mod_muls/_vy_mul 消费点 + skel_stock
	# 建模件在位（写实枪模路径叠挂 / 程序化路径原托替换，两端都有命名节点）
	var sk_def: Dictionary = Guns.SKEL_STOCK["skel_stock"]
	check("骨架狙击枪托在表（ads 1.10 / recoil 0.90）",
		absf(float(sk_def["ads_mul"]) - 1.10) < 0.001
			and absf(float(sk_def["recoil_mul"]) - 0.90) < 0.001, str(sk_def))
	var sk_no: Node3D = main.guns._build_gun_visual("sniper")
	var skv_no: int = _mesh_verts(sk_no)
	var sk_node_no: bool = sk_no.find_child("skel_stock", true, false) != null
	sk_no.free()
	main.stash.cash = 99999
	check("购骨架托（M14 配件同链 buy_m14_mod）", main.stash.buy_m14_mod("skel_stock")
		and main.stash.m14_mods_on("skel_stock"))
	main._sync_m14_mods_env()
	var sk_yes: Node3D = main.guns._build_gun_visual("sniper")
	var skv_yes: int = _mesh_verts(sk_yes)
	var sk_node_yes: bool = sk_yes.find_child("skel_stock", true, false) != null
	sk_yes.free()
	check("skel_stock 建模件在位（卸=无 · 装=有 + 顶点差>0）",
		(not sk_node_no) and sk_node_yes and skv_yes != skv_no,
		"v_no=%d v_yes=%d" % [skv_no, skv_yes])
	main._start_mission({"primary": "sniper", "secondary": "pistol"})
	await frames(8)
	var mm_sk: Vector2 = main.guns._mod_muls()
	check("骨架托数值进 _mod_muls（sniper ads ×1.10 · recoil ×0.90）",
		absf(mm_sk.y - 1.10) < 0.001 and absf(mm_sk.x - 0.90) < 0.001, str(mm_sk))
	check("骨架托后坐 -10% 进 _vy_mul（pitch 轴同乘）",
		absf(main.guns._vy_mul() - 0.90) < 0.001,
		"vy=%.4f" % main.guns._vy_mul())
	# 程序化回退路径验证：sniper 不在 BL_GUNS（写实件是 PH 扫描模型，
	# HD_NO_BL 只断 Blender 枪）——照 mk4 全自动枪管「工厂直调」先例，
	# 直接调 legacy 枪匠 = 强制程序化枪身：原托替换（木托三件不建）+
	# skel_stock 命名节点原位落成
	OS.set_environment("HD_NO_BL", "1")
	OS.set_environment("HD_M14_MODS", "")
	var skl_base: Node3D = HDGuns._old5_build_legacy("sniper")
	var sklv_base: int = _mesh_verts(skl_base)
	var skl_node_base: bool = skl_base.find_child("skel_stock", true, false) != null
	skl_base.free()
	OS.set_environment("HD_M14_MODS", "skel_stock,")
	var skl_rep: Node3D = HDGuns._old5_build_legacy("sniper")
	var sklv_rep: int = _mesh_verts(skl_rep)
	var skl_node_rep: bool = skl_rep.find_child("skel_stock", true, false) != null
	skl_rep.free()
	OS.set_environment("HD_NO_BL", "")
	OS.set_environment("HD_M14_MODS", "")
	check("程序化路径骨架托原托替换（skel_stock 节点在位 + 木托顶点差）",
		(not skl_node_base) and skl_node_rep and sklv_rep != sklv_base,
		"base=%d rep=%d" % [sklv_base, sklv_rep])
	# 老档兼容：无 rear_grips_owned/rear_grip_fit/m14_mods 字段的 v2 存档
	# 读入 = 后握把表空 + 缺省 none + 专属配件空表（不崩不误装）
	var f_old := FileAccess.open(HDData.SAVE_PATH, FileAccess.WRITE)
	f_old.store_string(JSON.stringify({"v": 2, "cash": 500,
		"guns_owned": ["rifle", "sniper"],
		"loadout": {"primary": "rifle", "secondary": "pistol"}}))
	f_old.close()
	var st_old := HDStash.new()
	check("老档兼容：后握把/专属托表全空（无字段=缺省 none 不崩）",
		st_old.rear_grips_owned == ["none"] and st_old.rear_grip_fit.is_empty()
			and st_old.rear_grip_id("rifle") == "none"
			and is_equal_approx(st_old.rear_grip_ads_mul("rifle"), 1.0)
			and not st_old.owns_rear_grip("phantom") and st_old.m14_mods.is_empty())
	st_old.cash = 99999
	st_old.buy_rear_grip("phantom")
	st_old.equip_rear_grip("rifle", "phantom")
	st_old.buy_m14_mod("skel_stock")
	var st_rt := HDStash.new()
	check("存档往返：rear_grip_fit + skel_stock（四表同链）读回保留",
		st_rt.owns_rear_grip("phantom") and st_rt.rear_grip_id("rifle") == "phantom"
			and st_rt.m14_mods_on("skel_stock"))
	main.stash.save()   # 写回测试主档
	main.stash.m14_mods.erase("skel_stock")   # 夹具复位（后续按未购口径）
	main._sync_m14_mods_env()
	# 交易行入口可见性：③区后握把行（选枪 M4A1，步枪可装——行随
	# rear_grip_ok 过滤出现）+ ⑤区 SNIPER 组骨架托行（sniper 默认拥有恒显）
	main.stash.guns_owned = ["pistol", "smg", "rifle", "shotgun", "sniper",
		"m14", "mk4", "sr25"]   # ⑤组需要 M14/MK4/SR25 在册（摆拍，收尾不还原）
	main.lobby.show_lobby()
	main.lobby.set_tab(2)
	main.lobby._market_ammo_gun = 10   # GUNS 表序 10 = M4A1
	main.lobby.set_tab(2)   # 同页签重刷（set_tab 是唯一重渲染入口）
	await frames(2)
	var mkt_rg := _menu_labels_text(main.lobby)
	check("交易行入口：③区后握把行 + ⑤区 SNIPER 组骨架托行可见",
		mkt_rg.contains("后握把：") and mkt_rg.contains("[SNIPER] 骨架狙击枪托"),
		"后握把行=%s 骨架托行=%s" % [mkt_rg.contains("后握把："),
			mkt_rg.contains("[SNIPER] 骨架狙击枪托")])
	main.lobby.hide_lobby()
	# MK4 三连发（2026-10-25 用户定案）：点一下=一个三连发（松手打完为止），
	# 按住不重复；「全自动枪管」配件（MK4_MODS.autobarrel，M14 配件同链）解锁全自动
	main.stash.m14_mods.erase("autobarrel")   # 夹具：确保未购（幂等）
	main._sync_m14_mods_env()
	main._start_mission({"primary": "mk4", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)   # 点一下（单帧按压）
	Input.action_release("hd_fire")
	for i in 24:
		main.guns.update(1.0 / 60.0)   # 松手后点射继续打完
	var mk4_tap: int = 999 - main.guns.ammo
	check("MK4 点一下恰三连发（松手打完 3 发）", mk4_tap == 3, "shots=%d" % mk4_tap)
	# 轮间锁（2026-10-26 考证：三角洲实测 打完 ~100ms 才能点下一轮）：
	# 纯机制直测——静置清残余 → 置满锁 → 注入完整 tap 边沿 → 快进 30 帧
	# 应零出弹（锁吞掉点射）；再静置过锁 → 正常 tap → 三连发
	for i in 12:
		main.guns.update(1.0 / 60.0)   # 清第一轮残余锁与冷却
	main.guns.ammo = 999
	main.guns._burst_gap = 0.1        # 模拟「上一轮刚打完」
	Input.action_press("hd_fire")     # 锁内 tap（1 帧即松）
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	for i in 30:
		main.guns.update(1.0 / 60.0)
	var mk4_locked: int = 999 - main.guns.ammo
	check("MK4 轮间锁：锁窗口内 tap 不起射（30 帧零出弹）", mk4_locked == 0,
		"shots=%d" % mk4_locked)
	for i in 10:   # 静置过锁（0.1s 锁早已清）
		main.guns.update(1.0 / 60.0)
	main.guns.ammo = 999
	Input.action_press("hd_fire")
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	for i in 24:
		main.guns.update(1.0 / 60.0)
	var mk4_second: int = 999 - main.guns.ammo
	check("MK4 过锁后第二要点射正常（再 3 发）", mk4_second == 3, "shots=%d" % mk4_second)
	check("MK4 过锁后第二要点射正常（再 3 发）", mk4_second == 3, "shots=%d" % mk4_second)
	main.guns.update(1.0 / 60.0)
	main.guns.ammo = 999
	Input.action_press("hd_fire")
	for i in 60:   # 持续按住：首发点射 3 发后不再重复（需新边沿）
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var mk4_hold: int = 999 - main.guns.ammo
	check("MK4 按住不重复（无枪管仍 3 发）", mk4_hold == 3, "shots=%d" % mk4_hold)
	main.guns.update(1.0 / 60.0)
	# 全自动枪管解锁：购入后 provider 生效，按住连发（cd 0.063≈3.8 帧/发）
	main.stash.cash = 99999
	check("买 MK4 全自动枪管（₵1800，M14 配件同链）", main.stash.buy_m14_mod("autobarrel"))
	main._sync_m14_mods_env()
	main._start_mission({"primary": "mk4", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	for i in 60:
		main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	var mk4_auto: int = 999 - main.guns.ammo
	check("全自动枪管：按住连发（60 帧 ≈16 发 ±2.5）", absf(mk4_auto - 15.9) <= 2.5,
		"shots=%d" % mk4_auto)
	main.guns.update(1.0 / 60.0)
	# 视觉件：配件环境变量 → 重型枪管+鸟笼在位；摘除 → 不在。
	# mk4 有写实 GLB（BL_GUNS）——强制 HD_NO_BL 走程序化枪身验配件件
	OS.set_environment("HD_NO_BL", "1")
	var mk4_r1: Node3D = HDGuns._smg_build("mk4")
	check("全自动枪管视觉件在位（mk4_autobarrel 节点，程序化路径）",
		mk4_r1.find_child("mk4_autobarrel", true, false) != null)
	mk4_r1.free()
	OS.set_environment("HD_M14_MODS", "")
	var mk4_r2: Node3D = HDGuns._smg_build("mk4")
	check("未购无枪管件（环境变量摘除后不在）",
		mk4_r2.find_child("mk4_autobarrel", true, false) == null)
	mk4_r2.free()
	OS.set_environment("HD_NO_BL", "")
	main.stash.m14_mods.erase("autobarrel")   # 夹具复位（后续按未购口径）
	main._sync_m14_mods_env()
	# an94 超点射三连测（2026-10 商店枪·用户定案机制，cd_profile 射速档案
	# 首个消费枪）：①按压内首对 1800rpm（0.0333s=2 帧）+ 之后稳态 600rpm
	# （0.1s=6 帧）——FIRE_GATE 残差容差下 60fps 帧量化对表不漂，5s 按压实测
	# 发数期望精算 = 首对 2 发（帧 0/2）+ 稳态 6 帧一发（帧 8,14,…,296）=
	# 51 发，容差 ±1；②按压内前两发间隔 ≤0.05s；③松开再按首对间隔复位
	# （若计数不复位，再按首对按稳态 0.1s 走、当场撞线）+ 首对之后回落
	# 稳态 6 帧 ±1；④其余枪任抽两把（akm/k416）长程 RPM 原值不动——
	# cd_profile 缺省枪必须仍走单 cd 路径（纯增量机制回归锁）
	main._start_mission({"primary": "an94", "secondary": "pistol"})
	await frames(8)
	main.guns.ammo = 999   # 给足弹防中途自动换弹打断节拍
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	var burst_frames: Array = []
	var ammo_prev: int = 999
	for i in 300:
		main.guns.update(1.0 / 60.0)
		if main.guns.ammo < ammo_prev:
			burst_frames.append(i)
			ammo_prev = main.guns.ammo
	Input.action_release("hd_fire")
	var an94_shots: int = 999 - main.guns.ammo
	main.guns.update(1.0 / 60.0)
	check("an94 超点射 5s 按压实测 51 发 ±1（首对 1800 + 稳态 600）",
		absf(an94_shots - 51.0) <= 1.0, "shots=%d/300帧（5s）" % an94_shots)
	var pair_gap: float = -1.0
	if burst_frames.size() >= 2:
		pair_gap = float(burst_frames[1] - burst_frames[0]) / 60.0
	check("an94 按压内首对间隔 ≤0.05s（1800rpm=2 帧）",
		pair_gap >= 0.0 and pair_gap <= 0.05,
		"首对间隔=%.4fs（帧 %s）" % [pair_gap, str(burst_frames.slice(0, 2))])
	var steady_gap: float = -1.0
	if burst_frames.size() >= 3:
		steady_gap = float(burst_frames[2] - burst_frames[1]) / 60.0
	check("an94 首对之后回落稳态 600rpm（6 帧 ±1）",
		steady_gap >= 0.08 and steady_gap <= 0.12,
		"第2→3发间隔=%.4fs" % steady_gap)
	# ③ 松开再按：按压计数复位，又一对新的 1800rpm 超点射
	await frames(8)
	main.guns.update(1.0 / 60.0)
	Input.action_press("hd_fire")
	var re_frames: Array = []
	var re_prev: int = main.guns.ammo
	for i in 30:
		main.guns.update(1.0 / 60.0)
		if main.guns.ammo < re_prev:
			re_frames.append(i)
			re_prev = main.guns.ammo
	Input.action_release("hd_fire")
	main.guns.update(1.0 / 60.0)
	var re_gap: float = -1.0
	if re_frames.size() >= 2:
		re_gap = float(re_frames[1] - re_frames[0]) / 60.0
	check("an94 松开再按首对间隔复位（再一对 1800rpm）",
		re_gap >= 0.0 and re_gap <= 0.05,
		"再按首对间隔=%.4fs（帧 %s）" % [re_gap, str(re_frames.slice(0, 2))])
	# ④ 纯增量回归：抽 akm（545rpm）/ k416（880rpm）长程 RPM 原值不动
	for rpm_gid in ["akm", "k416"]:
		var rpm_exp: float = 60.0 / float(Guns.gun_by_id(rpm_gid)["cd"])
		main._start_mission({"primary": rpm_gid, "secondary": "pistol"})
		await frames(8)
		main.guns.ammo = 999
		main.guns.update(1.0 / 60.0)
		Input.action_press("hd_fire")
		for i in 300:
			main.guns.update(1.0 / 60.0)
		Input.action_release("hd_fire")
		var rpm_shots: int = 999 - main.guns.ammo
		main.guns.update(1.0 / 60.0)
		check("%s 长程射速原值不动（%.0frpm，cd_profile 缺省单 cd 路径）"
				% [rpm_gid, rpm_exp],
			absf(rpm_shots - rpm_exp * 5.0 / 60.0) <= 2.2,
			"shots=%d/300帧（期望 %.1f）" % [rpm_shots, rpm_exp * 5.0 / 60.0])
	# desc「N发每分」机读：cd 换算 RPM 与文案一致（±1%）——m250 0.1091→549.9
	# vs「550」、mp7 0.063→952.4 vs「950」、m14 0.0822→729.9 vs「730」、
	# k416 0.0682→879.8 vs「880」、an94 0.1→600.0 vs「600」（超点射首对 1800
	# 在 desc 里不邻「发每分」不参与机读，档案位校验见 27c）
	var rpm_re := RegEx.new()
	rpm_re.compile("(\\d+)发每分")
	var rpm_bad: Array = []
	for g_def in Guns.GUNS:
		var rpm_m: RegExMatch = rpm_re.search(str(g_def["desc"]))
		if rpm_m == null:
			continue
		var claim := float(rpm_m.get_string(1))
		var actual := 60.0 / float(g_def["cd"])
		if absf(actual - claim) / claim > 0.01:
			rpm_bad.append("%s %.1f≠%.0f" % [str(g_def["id"]), actual, claim])
	check("desc「N发每分」与 cd 换算一致（±1%，七处 m250/mp7/m14/asval/k416/an94/sr25）", rpm_bad.is_empty(),
		str(rpm_bad))
	# 切枪不继承冷却：狙击开一枪（cd 1.2）→ 切副枪 fire_cd 清零
	main._start_mission({"primary": "sniper", "secondary": "pistol"})
	await frames(8)
	main.guns.update(1.0 / 60.0)
	main.guns.try_fire()
	check("狙击开火后冷却在走（tap 语义不受影响）", main.guns.fire_cd > 1.0,
		"fire_cd=%.2f" % main.guns.fire_cd)
	main.guns.update(1.0 / 60.0)
	main.guns.switch_slot()
	check("切枪清冷却（新枪首发不被旧枪冷却拖住）", main.guns.fire_cd == 0.0,
		"fire_cd=%.3f" % main.guns.fire_cd)
	# 切枪当帧开火门照常（修复前切枪帧提前 return 丢 1 拍）：按下开火与切枪
	# 同帧 → 本帧已切回 sniper（tap 边沿成立）即开 1 发——比较切枪前后
	# primary 槽弹数（ammo 字段随 _equip 换到新枪的弹匣，跨枪直减会错账）
	var sniper_before: int = int(main.guns._slots["primary"]["ammo"])
	Input.action_press("hd_fire")
	Input.action_press("hd_slot1")   # 切回 primary=sniper（同帧开火门在切枪后执行）
	main.guns.update(1.0 / 60.0)
	Input.action_release("hd_fire")
	Input.action_release("hd_slot1")
	check("切枪当帧不丢拍（tap 开火门先于切枪 return）",
		sniper_before - main.guns.ammo == 1,
		"primary槽=%d 切后ammo=%d" % [sniper_before, main.guns.ammo])
	main.guns.update(1.0 / 60.0)

	# ===== 第二阶段：战场压力（改进方案第 3/4 节）=====
	main.stash.cash = 99999
	main.stash.buy_gun("rifle")
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(4)
	var sol: Array = main.soldiers.soldiers
	var subj: Dictionary = sol[0]
	# 试验场：西南荒漠开阔地（出生点在图角，多数方位出界）
	var pp0 := Vector3(-40.0, 0.0, 120.0)
	pp0.y = main.world.ground_height(pp0.x, pp0.z)
	var others_off := func() -> void:
		for k in range(1, sol.size()):
			sol[k]["dead"] = true      # 单兵试验：别的兵不参与（结束时 reset_all 复活）
	others_off.call()
	var place := func(sp: Vector3, yaw: float) -> void:
		subj["pos"] = Vector3(sp.x, main.world.ground_height(sp.x, sp.z), sp.z)
		subj["yaw"] = yaw
		subj["state"] = "patrol"
		subj["alert_t"] = 0.0
		subj["has_cover"] = false
		subj["los_ok"] = false
		subj["los_t"] = 0.0
		subj["hp"] = 100.0
		subj["dead"] = false
		subj["shots"] = 0
		subj["fire_cd"] = randf_range(0.5, 1.5)
		subj["route"] = [subj["pos"]]
		subj["wp"] = 0
	var sim := func(sec: float) -> void:
		for k in int(sec * 60.0):
			main.soldiers.update(1.0 / 60.0, true)
	# §30 m 定案保留：未警觉的兵在 50 m 外面朝玩家也不开火
	main.player.enter(pp0)
	place.call(pp0 + Vector3(0, 0, -50.0), 0.0)
	main.player.health = 100.0
	sim.call(3.0)
	check("未警觉 50 m 外不反应（30 m 主动发现定案保留）", int(subj["shots"]) == 0
		and str(subj["state"]) == "patrol", "shots=%d state=%s" % [int(subj["shots"]), str(subj["state"])])

	# §门槛 B：30–120 m 开第一枪后 3 秒内被还击 ≥ 80%（射程 35/60/90/115 m × 24 方位，
	#  兵随机朝向；开阔视线才计入；近失弹/枪声/命中三路都能触发警觉）
	seed(4242)
	var trials := 0
	var answered := 0
	for di in [35.0, 60.0, 90.0, 115.0]:
		for ai in 24:
			var ang := TAU * float(ai) / 24.0
			var spos: Vector3 = pp0 + Vector3(sin(ang), 0.0, cos(ang)) * di
			if absf(spos.x) > 160.0 or absf(spos.z) > 160.0:
				continue
			var eye_p: Vector3 = pp0 + Vector3(0, 1.55, 0)
			var eye_s: Vector3 = Vector3(spos.x, main.world.ground_height(spos.x, spos.z) + 1.5, spos.z)
			var to_s: Vector3 = eye_s - eye_p
			if main.world.wall_hit(eye_p, to_s.normalized(), to_s.length()) < to_s.length() - 0.5:
				continue
			main.player.enter(pp0)
			main.player.health = 100.0
			main.player.dead = false
			place.call(spos, randf() * TAU)
			var tch: Vector3 = subj["pos"] + Vector3(0, 1.05, 0) - eye_p
			main.player.yaw = atan2(tch.x, tch.z)
			main.player.pitch = atan2(tch.y, Vector2(tch.x, tch.z).length())
			main.player.update(0.016)
			main.guns.ammo = 30
			main.guns.fire_cd = 0.0
			main.guns.try_fire()
			sim.call(3.0)
			trials += 1
			if int(subj["shots"]) > 0:
				answered += 1
	randomize()
	var rate := float(answered) / float(maxi(trials, 1))
	check("门槛 B：30–120 m 开第一枪后 3 s 内被还击 ≥ 80%", trials >= 30 and rate >= 0.8,
		"%d/%d = %.0f%%" % [answered, trials, rate * 100.0])

	# §枪声传播 60 m：50 m 外背身的兵听到枪声警觉，80 m 外的不受影响
	main.player.enter(pp0)
	place.call(pp0 + Vector3(50.0, 0, 0), 0.0)
	main.soldiers.hear_shot(pp0 + Vector3(0, 1.5, 0))
	var heard_50: bool = float(subj["alert_t"]) > 0.0
	place.call(pp0 + Vector3(80.0, 0, 0), 0.0)
	main.soldiers.hear_shot(pp0 + Vector3(0, 1.5, 0))
	check("枪声 60 m 内警觉、80 m 外不受影响", heard_50 and float(subj["alert_t"]) == 0.0)

	# §疾跑脚步：背后 10 m 巡逻兵听见疾跑 → 警觉；步行不触发
	place.call(pp0 + Vector3(0, 0, 10.0), 0.0)
	main.player.sprinting = false
	main.soldiers.update(1.0 / 60.0, true)
	var walk_quiet: bool = float(subj["alert_t"]) == 0.0
	main.player.sprinting = true
	main.soldiers.update(1.0 / 60.0, true)
	check("疾跑 14 m 内被听见（步行不触发）", walk_quiet and float(subj["alert_t"]) > 0.0)
	main.player.sprinting = false

	# §找掩体：威胁点在障碍正前 40 m、兵贴障碍正面 → 掩体点在障碍背面且对威胁点视线被挡
	var cover_ok := false
	var cover_msg := "无合适障碍"
	for ob in main.world.obstacles:
		if float(ob.get("top", 0.0)) < 2.0 or float(ob.get("bot", 0.0)) > 0.1:
			continue
		var hx := float(ob["hx"])
		var hz := float(ob["hz"])
		if hx < 0.8 or hz < 0.8 or hx > 5.0 or hz > 5.0:
			continue
		var oc := Vector3(float(ob["cx"]), 0.0, float(ob["cz"]))
		var thr := oc + Vector3(hx + 40.0, 1.55, 0.0)
		var probe_from := Vector3(thr.x, 1.55, thr.z)
		if main.world.wall_hit(probe_from, Vector3(-1, 0, 0), 40.0) < 39.0:
			continue   # 前方 40 m 内还有别的东西：换一个
		place.call(oc + Vector3(hx + 3.0, 0.0, 0.0), 0.0)
		if main.soldiers._find_cover(subj, thr):
			var cp: Vector3 = subj["cover"]
			cover_ok = cp.x < oc.x and main.soldiers._blocked(thr, cp + Vector3(0, 1.05, 0))
			cover_msg = "obstacle=(%.0f,%.0f) cover=(%.1f,%.1f)" % [oc.x, oc.z, cp.x, cp.z]
			break
	check("找掩体：掩体点在障碍背面、对威胁视线被挡", cover_ok, cover_msg)

	# §指南针方位 / 受击方向 / 3D 枪声
	check("方位角：北 0 · 东 90 · 南 180 · 西 270",
		absf(main._bearing(0, -1) - 0.0) < 0.01 and absf(main._bearing(1, 0) - 90.0) < 0.01
			and absf(main._bearing(0, 1) - 180.0) < 0.01 and absf(main._bearing(-1, 0) - 270.0) < 0.01)
	main.player.enter(pp0)
	main.player.yaw = 0.0
	main.player.health = 100.0
	var right_src: Vector3 = pp0 + Vector3(-cos(0.0), 0, sin(0.0)) * 20.0
	main._on_player_hit(1.0, right_src)
	var last_hit: Dictionary = main.hud._hit_ind.hits.back()
	check("受击方向：右侧来弹 → 弧在右（≈+90°）", absf(float(last_hit["a"]) - PI * 0.5) < 0.05,
		"a=%.2f" % float(last_hit["a"]))
	main.audio.play_shot_3d("rifle", pp0 + Vector3(30, 1.5, 0))
	check("敌人枪声走 3D 音源（AudioStreamPlayer3D 池）", main.audio._pool3d.size() > 0
		and main.audio._pool3d[0] is AudioStreamPlayer3D)
	main.soldiers.reset_all()
	main._raid_live = false

	# ===== 第三阶段：内容深度（改进方案第 5/6 节）=====
	# §容器分类：四类都在图上；保险箱 5 s、只出蓝色及以上
	var cls_n := {}
	for c in main.loot._containers:
		cls_n[str(c["cls"])] = int(cls_n.get(str(c["cls"]), 0)) + 1
	check("容器四类齐全（武器/医疗/杂物/保险箱）", cls_n.has("weapon") and cls_n.has("medical")
		and cls_n.has("crate") and cls_n.has("safe"), str(cls_n))
	var safe_ok := true
	for i in 200:
		if int(HDData.roll_container("safe", ["wild", "mid", "center", "dam"][i % 4])["rarity"]) < 2:
			safe_ok = false
	check("保险箱只出蓝色及以上（200 次）", safe_ok)
	check("保险箱搜索 5 s", float(HDData.CONTAINER_CLASS["safe"]["search"]) == 5.0)
	var med_uses := 0
	for i in 400:
		if HDData.roll_bonus("medical").has("use"):
			med_uses += 1
	check("医疗箱约一半额外出药品（变卖物照出）", med_uses > 180 and med_uses < 260
		and not HDData.roll_container("medical", "mid").has("use"), "n=%d/400" % med_uses)

	# §随机出生：5 个出生点都在空地、离最近巡逻点 ≥30 m；开局在其中随机
	var sp_ok := true
	for sp in HDData.SPAWN_POINTS:
		for ps in main.world.patrol_spots:
			if Vector2(sp.x - ps["pos"].x, sp.z - ps["pos"].z).length() < 30.0:
				sp_ok = false
		for ob in main.world.obstacles:
			if absf(sp.x - float(ob["cx"])) < float(ob["hx"]) + 0.6 \
					and absf(sp.z - float(ob["cz"])) < float(ob["hz"]) + 0.6:
				sp_ok = false
	for sp in HDData.SPAWN_POINTS:
		if absf(sp.x) > HDWorld.BOUND - 2.0 or absf(sp.z) > HDWorld.BOUND - 2.0:
			sp_ok = false   # 必须在行动边界内（边界墙在 ±149）
	check("出生点 ×5 都在边界内空地且离巡逻点 ≥30 m", sp_ok and HDData.SPAWN_POINTS.size() >= 4)
	var seen_sp := {}
	for i in 24:
		main._start_mission({"primary": "rifle", "secondary": "pistol"})
		seen_sp[str(main.world.spawn_pos)] = true
	check("开局随机出生（24 局 ≥3 个不同点）", seen_sp.size() >= 3, "n=%d" % seen_sp.size())

	# §物资：医疗包读条回 50 / 护甲板 +50 且吸收 60% / 弹药盒 +2 匣 / 止痛药缓回
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	for k in HDData.USE_KEYS:
		main.loot.backpack.append(HDData.make_consumable(k))
	main.player.health = 40.0
	main._route_key(KEY_3)
	for i in 200:
		main._step_use(1.0 / 60.0)
	check("医疗包读条 3 s 回 50 血（用掉一件）", absf(main.player.health - 90.0) < 0.5
		and int(main.loot.use_counts()["medkit"]) == 0, "hp=%.1f" % main.player.health)
	main._route_key(KEY_5)
	for i in 130:
		main._step_use(1.0 / 60.0)
	check("护甲板 +50 护甲", absf(main.player.armor - 50.0) < 0.01, "armor=%.1f" % main.player.armor)
	main.player.hit(20.0)
	check("护甲吸收 60% 伤害", absf(main.player.health - 82.0) < 0.01
		and absf(main.player.armor - 38.0) < 0.01,
		"hp=%.1f armor=%.1f" % [main.player.health, main.player.armor])
	var res0: int = main.guns.reserve
	main._route_key(KEY_6)
	for i in 100:
		main._step_use(1.0 / 60.0)
	check("弹药盒 +2 匣备弹", main.guns.reserve == res0 + 60, "reserve %d→%d" % [res0, main.guns.reserve])
	main.player.health = 50.0
	main._route_key(KEY_4)
	for i in 600:
		main._step_use(1.0 / 60.0)
	check("止痛药 8 s 内缓回 20", absf(main.player.health - 70.0) < 0.5, "hp=%.1f" % main.player.health)
	main._route_key(KEY_3)
	check("没有医疗包时不读条", main._using.is_empty())

	# §撤离点：大坝 12 分钟前不开 / 开后可撤；付费扣 ₵800（不足不能撤）；拉闸后东门开放并惊动附近敌人
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	main._extracts["paid"]["enabled"] = true
	main._extracts["lever"]["enabled"] = true
	main._sync_extract_vis()
	main._raid_t = 100.0
	main.player.enter(main.world.extract2_pos)
	for i in 400:
		main._step_mission(1.0 / 60.0)
	check("大坝撤离点 12 分钟前不开放", main._raid_live and not main.hud.result_visible)
	main._raid_t = HDData.DAM_OPEN_T + 0.5
	main._step_mission(1.0 / 60.0)
	check("12 分钟后大坝撤离点开放", bool(main._extracts["dam"]["open"]))
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	main._extracts["paid"]["enabled"] = true
	main.stash.cash = 500
	main.player.enter(main.world.paid_pos)
	for i in 400:
		main._step_mission(1.0 / 60.0)
	check("付费撤离现金不足不能撤", main._raid_live and main.stash.cash == 500)
	main.stash.cash = 2000
	var ex_n0: int = int(main.stash.stats["extracts"])
	for i in 400:
		main._step_mission(1.0 / 60.0)
		if not main._raid_live:
			break
	check("付费撤离成功扣 ₵800", not main._raid_live and main.stash.cash == 1200
		and int(main.stash.stats["extracts"]) == ex_n0 + 1, "cash=%d" % main.stash.cash)
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	main._extracts["lever"]["enabled"] = true
	main._sync_extract_vis()
	main.player.enter(main.world.lever_ext_pos)
	for i in 60:
		main._step_mission(1.0 / 60.0)
	check("拉闸撤离未通电时不能撤", main._raid_live and main._extract_t == 0.0)
	var near_guard: Dictionary = main.soldiers.soldiers[0]
	near_guard["pos"] = HDData.LEVER_POS + Vector3(20.0, 0.0, 0.0)
	near_guard["alert_t"] = 0.0
	near_guard["dead"] = false
	main.player.enter(HDData.LEVER_POS)
	Input.action_press("hd_interact")
	for i in 140:
		main._step_mission(1.0 / 60.0)
	Input.action_release("hd_interact")
	check("按住 F 拉闸 → 东门撤离开放 + 附近敌人警觉", bool(main._extracts["lever"]["open"])
		and float(near_guard["alert_t"]) > 0.0)

	# §局时 25 分钟：耗尽未撤离 = 失踪（按阵亡结算）
	main._start_mission({"primary": "pistol", "secondary": ""})
	await frames(2)
	var d_n0: int = int(main.stash.stats["deaths"])
	main._raid_t = HDData.RAID_TIME - 0.01
	main._step_mission(1.0 / 60.0)
	check("局时耗尽 = 失踪（记阵亡）", not main._raid_live and int(main.stash.stats["deaths"]) == d_n0 + 1
		and main.hud._result_title.text.contains("失踪"))
	check("战绩累计局时（门槛 C：平均局时）", int(main.stash.stats.get("time_total", 0)) > 0)
	main.soldiers.reset_all()

	# ===== 第四阶段：敌人分级 / 首领 =====
	var tier_n := {}
	var bosses: Array = []
	for s_v in main.soldiers.soldiers:
		if s_v.has("reserve"):
			continue   # 空投增援 / 搜刮者预留槽另测
		tier_n[str(s_v["tier"])] = int(tier_n.get(str(s_v["tier"]), 0)) + 1
		if str(s_v["tier"]) == "boss":
			bosses.append(s_v)
		if str(s_v["tier"]) == "elite":
			check("精英只在中心/坝区", str(s_v["zone"]) in HDData.ELITE_ZONES, str(s_v["zone"]))
	check("精英 ≥3 名 + 首领 2 名", int(tier_n.get("elite", 0)) >= 3 and bosses.size() == 2,
		str(tier_n))
	var vaults: Array = main.loot._containers.filter(func(c): return str(c["cls"]) == "vault")
	var vault_near := vaults.size() == 2
	for b in bosses:
		var near := false
		for c in vaults:
			if Vector2(c["pos"].x - b["pos"].x, c["pos"].z - b["pos"].z).length() < 5.0:
				near = true
		vault_near = vault_near and near
	check("两名首领各守一只首领保险柜（5 m 内）", vault_near)
	var vault_ok := true
	for i in 100:
		if int(HDData.roll_container("vault", ["center", "dam"][i % 2])["rarity"]) < 5:
			vault_ok = false
	check("首领保险柜只出红色及以上（100 次）", vault_ok)
	check("容器点总数契约不变（首领柜不进 world 表）", main.world.container_spots.size() == 58)
	# 精英护甲：身体 40 伤 → 护甲吸一半 20（hp 80 / 甲 60→40）；爆头无视护甲
	var ei := -1
	for i in main.soldiers.soldiers.size():
		if str(main.soldiers.soldiers[i]["tier"]) == "elite":
			ei = i
			break
	var el: Dictionary = main.soldiers.soldiers[ei]
	var r_ar: Dictionary = main.soldiers.apply_hit(ei, 40.0, false)
	check("精英护甲吸收一半身体伤害", absf(float(el["hp"]) - 80.0) < 0.01
		and absf(float(el["armor"]) - 40.0) < 0.01 and bool(r_ar.get("armor", false)),
		"hp=%.1f armor=%.1f" % [float(el["hp"]), float(el["armor"])])
	main.soldiers.apply_hit(ei, 40.0, true)
	check("爆头无视护甲", absf(float(el["hp"]) - 40.0) < 0.01 and absf(float(el["armor"]) - 40.0) < 0.01,
		"hp=%.1f armor=%.1f" % [float(el["hp"]), float(el["armor"])])
	check("精英/首领更准更狠", float(HDData.ENEMY_TIERS["elite"]["spread"]) < 1.0
		and float(HDData.ENEMY_TIERS["boss"]["spread"]) < float(HDData.ENEMY_TIERS["elite"]["spread"])
		and float(HDData.ENEMY_TIERS["boss"]["dmg"]) > float(HDData.ENEMY_TIERS["elite"]["dmg"]))
	# 首领拴绳：搜索目标点不离家超过 BOSS_LEASH
	var bs: Dictionary = bosses[0]
	var far_g: Vector3 = main.soldiers._leash(bs, bs["home"] + Vector3(60.0, 0.0, 0.0))
	check("首领拴绳：目标点收回到 18 m 内", Vector2(far_g.x - bs["home"].x,
		far_g.z - bs["home"].z).length() <= HDData.BOSS_LEASH + 0.01)
	# 首领阵亡 → 尸体旁必掉一件金色及以上
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	var g_n0: int = main.loot.ground_count()
	var bi: int = main.soldiers.soldiers.find(bs)
	main.soldiers.apply_hit(bi, 999.0, true)
	var drop_ok: bool = main.loot.ground_count() == g_n0 + 1
	if drop_ok:
		drop_ok = int(main.loot._ground[main.loot._ground.size() - 1]["item"]["rarity"]) >= HDData.BOSS_DROP_MIN
	check("首领阵亡掉落金色及以上", drop_ok, "ground=%d" % main.loot.ground_count())
	main.soldiers.reset_all()
	check("重开后首领满血满甲", float(bs["hp"]) == float(HDData.ENEMY_TIERS["boss"]["hp"])
		and float(bs["armor"]) == float(HDData.ENEMY_TIERS["boss"]["armor"]))
	main._raid_live = false

	# ===== 第四阶段：AI 搜刮者小队（三方混战）=====
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	var SD: Array = main.soldiers.soldiers
	check("开局搜刮者 2 队 × 3 人进场", main.soldiers.scav_alive() == HDData.SCAV_SQUADS * HDData.SCAV_SIZE,
		"n=%d" % main.soldiers.scav_alive())
	var sc_far := true
	for sv in SD:
		if str(sv["faction"]) == "scav" and not sv["dead"] \
				and Vector2(sv["pos"].x - main.player.pos.x, sv["pos"].z - main.player.pos.z).length() < 60.0:
			sc_far = false
	check("搜刮者不在玩家出生点附近（≥60 m）", sc_far)
	var rf_live := func() -> int:
		var n := 0
		for x in SD:
			if str(x.get("reserve", "")) == "reinforce" and not x["dead"]:
				n += 1
		return n
	check("增援预留槽开局不在场", rf_live.call() == 0)
	# 寻路网格（搜刮者跨图跑箱子/撤离用；没有它会卡死在变电站围墙里）
	var nv = main.soldiers._nav
	var np_from: Vector3 = HDData.SPAWN_POINTS[0]
	var np_to := Vector3(115.0, 0.0, -36.0)
	var npth: PackedVector3Array = nv.path(np_from, np_to)
	var np_free := npth.size() >= 2
	for q in npth:
		if not nv.is_free(q):
			np_free = false
	check("寻路：西南出生点 → 东部变电站院内可达，路径点全在空地", nv.reachable(np_from, np_to)
		and np_free and npth[npth.size() - 1].distance_to(np_to) < 3.0, "pts=%d" % npth.size())
	# 隔离试验：守军全部「离场」、玩家挪到远处角落（谁都看不见）
	var iso := func() -> void:
		for sv in SD:
			if str(sv["faction"]) == "guard":
				sv["dead"] = true
	iso.call()
	main.player.enter(Vector3(-140.0, 0.0, 138.0))
	var lead_i: int = main.soldiers._squad_leader(0)
	var lead: Dictionary = SD[lead_i]
	var tci := -1
	for ci in main.loot._containers.size():
		var c: Dictionary = main.loot._containers[ci]
		if str(c["cls"]) in ["crate", "weapon", "medical"] and not bool(c["searched"]) \
				and Vector2(c["pos"].x + 140.0, c["pos"].z - 138.0).length() > 80.0:
			tci = ci
			break
	var tcp: Vector3 = main.loot._containers[tci]["pos"]
	for sv in SD:
		if str(sv["faction"]) == "scav" and int(sv["squad"]) == 0:
			sv["pos"] = tcp + Vector3(1.2, 0.0, 0.6 + float(sv["squad_k"]) * 0.8)
	lead["goal_c"] = tci
	lead["goal_t"] = 0.0
	lead["loot_t"] = 0.0
	for i in 60 * 6:
		main.soldiers.update(1.0 / 60.0, true)
	check("搜刮者队长搜走容器（抢玩家的箱子）", bool(main.loot._containers[tci]["searched"])
		and (lead["loot"] as Array).size() >= 1, "loot=%d" % (lead["loot"] as Array).size())
	var g_s0: int = main.loot.ground_count()
	var n_carry: int = (lead["loot"] as Array).size()
	main.soldiers.apply_hit(lead_i, 999.0, true)
	check("击杀搜刮者 → 身上战利品全部掉地上", main.loot.ground_count() >= g_s0 + n_carry,
		"ground %d → %d（带 %d 件）" % [g_s0, main.loot.ground_count(), n_carry])
	check("队长阵亡 → 队员接任队长", main.soldiers._squad_leader(0) >= 0
		and main.soldiers._squad_leader(0) != lead_i)
	# 守军 ⇄ 搜刮者互打：西南空地相距 16 m 面对面，12 s 内有一方挂彩
	var gd: Dictionary = SD[0]
	var sv2: Dictionary = SD[main.soldiers._squad_leader(1)]
	var fpos := Vector3(-40.0, 0.0, 120.0)
	gd["dead"] = false
	gd["hp"] = 100.0
	gd["state"] = "patrol"
	gd["pos"] = fpos
	gd["yaw"] = 0.0
	gd["route"] = [fpos]
	sv2["pos"] = fpos + Vector3(0.0, 0.0, 16.0)
	sv2["yaw"] = PI
	sv2["task"] = "loot"
	for sv in SD:
		if str(sv["faction"]) == "scav" and int(sv["squad"]) == 1 and sv != sv2:
			sv["dead"] = true
	var hp_sum0: float = float(gd["hp"]) + float(sv2["hp"]) + float(sv2["armor"])
	for i in 60 * 12:
		main.soldiers.update(1.0 / 60.0, true)
	check("守军 ⇄ 搜刮者互相交火（12 s 内有人挂彩）", float(gd["hp"]) + float(sv2["hp"])
		+ float(sv2["armor"]) < hp_sum0, "guard=%.0f scav=%.0f/%.0f" % [float(gd["hp"]),
		float(sv2["hp"]), float(sv2["armor"])])
	# 撤离：存活队员走到撤离点 → 整队离场
	main.soldiers.reset_all()
	main.soldiers.spawn_scavs(main.player.pos)
	iso.call()
	var ex_q := [-1, -1]
	main.soldiers.scav_extracted.connect(func(q, n): ex_q[0] = q; ex_q[1] = n, CONNECT_ONE_SHOT)
	var l1: Dictionary = SD[main.soldiers._squad_leader(1)]
	l1["task"] = "exfil"
	l1["pos"] = main.soldiers._nearest_exfil(l1["pos"]) + Vector3(0.5, 0.0, 0.0)
	for i in 30:
		main.soldiers.update(1.0 / 60.0, true)
	check("搜刮者小队走到撤离点整队离场", ex_q[0] == 1 and main.soldiers._squad_leader(1) < 0,
		"q=%d" % int(ex_q[0]))
	main.soldiers.reset_all()
	main._raid_live = false

	# ===== 第四阶段：第 10 分钟空投 =====
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	var ob_n0: int = main.world.obstacles.size()
	main._raid_t = HDData.AIRDROP_T - 0.005
	main._step_mission(1.0 / 60.0)
	check("第 10 分钟空投投放（信号烟 + 伞降）", main._airdrop_fired and str(main.airdrop.state) == "falling"
		and main.airdrop._smoke.emitting)
	var ad_mark := false
	for mk in main._compass_marks():
		if str(mk["label"]).begins_with("空投"):
			ad_mark = true
	check("指南针出现空投标记", ad_mark)
	for i in 30:
		main.airdrop.update(1.0)
	var ad_c: Array = main.loot._containers.filter(func(c): return str(c["cls"]) == "airdrop")
	var rf_on: Array = SD.filter(func(x): return str(x.get("reserve", "")) == "reinforce" and not x["dead"])
	check("空投落地 → 空投箱可搜 + 3 名守军增援进场", str(main.airdrop.state) == "landed"
		and ad_c.size() == 1 and rf_on.size() == HDData.REINFORCE_N,
		"state=%s box=%d rf=%d" % [str(main.airdrop.state), ad_c.size(), rf_on.size()])
	var rf_ok := true
	for x in rf_on:
		if Vector2(x["pos"].x - main.airdrop.pos.x, x["pos"].z - main.airdrop.pos.z).length() < 20.0 \
				or float(x["alert_t"]) <= 0.0:
			rf_ok = false
	check("增援从落点外进场并警觉赶来", rf_ok)
	var ad_ok := true
	for i in 100:
		if int(HDData.roll_container("airdrop", "mid")["rarity"]) < 3 or HDData.roll_bonus("airdrop").is_empty():
			ad_ok = false
	check("空投箱：紫色及以上 + 必带物资（100 次）", ad_ok)
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(2)
	var ad_left: Array = main.loot._containers.filter(func(c): return str(c["cls"]) == "airdrop")
	check("重开局：空投箱与占位障碍拆除、增援离场", ad_left.is_empty()
		and main.world.obstacles.size() == ob_n0 and str(main.airdrop.state) == "idle"
		and rf_live.call() == 0, "box=%d ob %d→%d" % [ad_left.size(), ob_n0, main.world.obstacles.size()])
	main.soldiers.reset_all()
	main._raid_live = false

	# ===== 第四阶段：保险 / 耐久维修 / 消音器 =====
	var ST = main.stash
	ST.cash = 90000
	ST.buy_gun("m4a1")
	ST.buy_scope("optic35")
	ST.equip_scope("m4a1", "optic35")
	ST.loadout = {"primary": "m4a1", "secondary": "pistol"}
	var lo4 := {"primary": "m4a1", "secondary": "pistol"}
	var cv4: int = ST.carried_value(lo4)
	check("保险费 = 押上价值 × 30%", ST.insurance_price(lo4) == int(ceil(cv4 * 0.3)),
		"cv=%d ip=%d" % [cv4, ST.insurance_price(lo4)])
	var c4: int = ST.cash
	main._start_mission({"primary": "m4a1", "secondary": "pistol", "insured": true})
	await frames(2)
	check("投保出发：扣保险费 + 本局已投保", main._raid_insured and ST.cash == c4 - ST.insurance_price(lo4),
		"cash %d → %d" % [c4, ST.cash])
	main._raid_live = false
	# 退回概率：投保每件 50%（200 次蒙特卡洛 35–65%）；不投保 0
	seed(4242)
	var back_n := 0
	for k in 200:
		if not ST.guns_owned.has("m4a1"):
			ST.guns_owned.append("m4a1")
		var g4: Dictionary = ST.lose_carried(lo4, true)
		if ST.guns_owned.has("m4a1"):
			back_n += 1
	check("投保：阵亡每件约 50% 退回（200 次 35–65%）", back_n >= 70 and back_n <= 130, "back=%d/200" % back_n)
	if not ST.guns_owned.has("m4a1"):
		ST.guns_owned.append("m4a1")
	ST.lose_carried(lo4, false)
	check("不投保：阵亡必丢", not ST.guns_owned.has("m4a1"))
	# 耐久：本局开火磨损 → 撤离写回；耐久低变散；卡壳；维修
	ST.buy_gun("m4a1")
	ST.loadout = {"primary": "m4a1", "secondary": "pistol"}
	ST.set_ammo("m4a1", 300)
	main._start_mission({"primary": "m4a1", "secondary": "pistol"})
	await frames(2)
	main.guns._equip("primary")
	for k in 40:
		main.guns.fire_cd = 0.0
		main.guns.reloading = 0.0
		if main.guns.ammo <= 0:
			main.guns.ammo = 30
		main.guns.try_fire()
	var wear40: float = float(main._raid_wear.get("m4a1", 0.0))
	check("开火磨损：40 发 = 2.0 耐久", absf(wear40 - 40.0 * HDData.DUR_PER_SHOT) < 0.01, "wear=%.2f" % wear40)
	check("耐久 98：还没到磨损线，倍率 1.0", absf(main.guns._dur_mul() - 1.0) < 0.001)
	main._win_raid()
	check("撤离写回耐久（100 → 98）", absf(ST.dur_of("m4a1") - 98.0) < 0.01, "dur=%.2f" % ST.dur_of("m4a1"))
	ST.durability["m4a1"] = 0.0
	main._start_mission({"primary": "m4a1", "secondary": "pistol"})
	await frames(2)
	main.guns._equip("primary")
	check("耐久 0：散布/后坐 ×1.6", absf(main.guns._dur_mul() - (1.0 + HDData.DUR_WORN_MUL)) < 0.01,
		"mul=%.2f" % main.guns._dur_mul())
	seed(99)
	var jams := [0]
	main.guns.jammed.connect(func(): jams[0] += 1)
	var ammo_before: int = main.guns.ammo
	var shots_ok := 0
	for k in 300:
		main.guns.fire_cd = 0.0
		main.guns.reloading = 0.0
		if main.guns.ammo <= 0:
			main.guns.ammo = 30
		var a0: int = main.guns.ammo
		main.guns.try_fire()
		if main.guns.ammo < a0:
			shots_ok += 1
	check("耐久 < 25：会卡壳且卡壳不耗弹", jams[0] > 0 and shots_ok + jams[0] == 300,
		"jams=%d shots=%d" % [jams[0], shots_ok])
	main._raid_live = false
	main._raid_wear = {}
	var rp: int = ST.repair_price("m4a1")
	var c5: int = ST.cash
	check("维修价 = 枪价 × 25% × 缺损", rp == int(ceil(float(Guns.gun_by_id("m4a1")["price"]) * 0.25)),
		"price=%d" % rp)
	main.lobby.show_lobby()
	main.lobby.set_tab(1)
	for i in Guns.GUNS.size():
		if str(Guns.GUNS[i]["id"]) == "m4a1":
			main.lobby._gun_idx = i
	main.lobby._refresh_all()
	check("改枪台 R 键维修", main.lobby.handle_key(KEY_R) and ST.dur_of("m4a1") == 100.0
		and ST.cash == c5 - rp)
	# 消音器：改枪台 V 购买并装上 → 惊动半径 20 m；再按 V 拆下
	var c6: int = ST.cash
	main.lobby.handle_key(KEY_V)
	check("改枪台 V 购买消音器并装上", ST.suppressed("m4a1") and ST.cash == c6 - HDData.SUP_PRICE)
	check("改枪台 3D 预览已建（枪模在转台上）", main.lobby._pv_pivot != null
		and main.lobby._pv_pivot.get_child_count() == 1 and main.lobby._pv_key.begins_with("m4a1|"))
	check("霰弹枪不能装消音器", not ST.sup_allowed("shotgun"))
	main._start_mission({"primary": "m4a1", "secondary": "pistol"})
	await frames(2)
	main.guns._equip("primary")
	check("消音器上枪：枪模挂筒 + 枪口前移", bool(main.guns._guns["primary"].get("sup", false)))
	var lis: Dictionary = main.soldiers.soldiers[0]
	for sv in main.soldiers.soldiers:
		if sv != lis:
			sv["dead"] = true
	main.player.enter(Vector3(-40.0, 0.0, 120.0))
	main.player.yaw = 0.0
	main.player.update(0.016)
	lis["dead"] = false
	lis["alert_t"] = 0.0
	lis["state"] = "patrol"
	lis["pos"] = Vector3(-40.0, 0.0, 120.0) + Vector3(0, 0, -40.0)   # 身后 40 m（子弹不掠过）
	main._on_player_fired()
	check("消音器：40 m 外听不到枪声", float(lis["alert_t"]) <= 0.0)
	ST.toggle_sup("m4a1")
	main._on_player_fired()
	check("拆下消音器：40 m 外听得到", float(lis["alert_t"]) > 0.0)
	ST.toggle_sup("m4a1")
	main.soldiers.reset_all()
	main._raid_live = false
	ST.lose_carried({"primary": "m4a1", "secondary": "pistol"}, false)
	check("阵亡：消音器随枪丢", not ST.sup_owned.has("m4a1"))
	# 出发页 I 键投保 → 出发随 loadout 带上 insured
	ST.buy_gun("m4a1")
	ST.loadout = {"primary": "m4a1", "secondary": "pistol"}
	main.lobby.show_lobby()
	main.lobby.set_tab(0)
	main.lobby._insure = false
	check("出发页 I 键勾选投保", main.lobby.handle_key(KEY_I) and main.lobby._insure)
	var c7: int = ST.cash
	var ip7: int = ST.insurance_price(ST.loadout)
	main.lobby._fire_deploy()
	await frames(2)
	check("出发钮带保险出发（扣费 + 本局投保）", main._raid_insured and ST.cash == c7 - ip7)
	main._raid_live = false
	main.lobby._insure = false

	# ===== 第四阶段：首局引导（搜箱 → 看指南针 → 撤离；H 跳过）=====
	main.lobby.hide_lobby()
	ST.tutorial_done = false
	main._start_mission({"primary": "pistol", "secondary": ""})
	await frames(2)
	check("首局：引导第 1 步出现（HUD 卡 + 指南针箱子标记）", main._tut == 0
		and main.hud._tut_panel.visible
		and main._compass_marks().any(func(mk): return str(mk["label"]).begins_with("箱子")))
	main._on_loot_picked(HDData.make_consumable("pills"))
	check("搜到东西 → 第 2 步", main._tut == 1)
	var ep: Vector3 = main.world.extract_pos
	main.player.enter(ep + Vector3(-60.0, 0.0, 0.0))
	main.player.yaw = atan2(ep.x - main.player.pos.x, ep.z - main.player.pos.z) + PI   # 背对
	for i in 60:
		main._step_tut(1.0 / 60.0)
	check("背对撤离点不算看过指南针", main._tut == 1)
	main.player.yaw = atan2(ep.x - main.player.pos.x, ep.z - main.player.pos.z)
	for i in 60:
		main._step_tut(1.0 / 60.0)
	check("对准撤离点 0.6 s → 第 3 步", main._tut == 2)
	main._win_raid()
	check("撤离 → 引导完成并存档，下局不再出现", ST.tutorial_done and main._tut == -1
		and not main.hud._tut_panel.visible)
	main._start_mission({"primary": "pistol", "secondary": ""})
	await frames(2)
	check("完成后开局无引导", main._tut == -1)
	main._raid_live = false
	ST.tutorial_done = false
	main._start_mission({"primary": "pistol", "secondary": ""})
	await frames(2)
	main._route_key(KEY_H)
	check("H 跳过引导（记为完成）", main._tut == -1 and ST.tutorial_done)
	main._raid_live = false

	# ===== 第四阶段：静态陈设合批（门槛 D 的结构性前提；绘制调用本身见 probe_perf.gd）=====
	var bs4: Dictionary = main.world.batch_stats
	check("静态合批生效（≥2000 件并入、物件数压到 1/8 以下）", int(bs4.get("merged", 0)) >= 2000
		and int(bs4.get("meshes", 99999)) * 8 <= int(bs4.get("merged", 0)), str(bs4))
	var beacons_ok := true
	for eid in main.world._extract_vis:
		for nd in (main.world._extract_vis[eid] as Dictionary)["nodes"]:
			if not is_instance_valid(nd) or not (nd as Node).is_inside_tree():
				beacons_ok = false
	check("撤离信标未被合批吞掉（局内还要改色/显隐）", beacons_ok)
	main.world.set_lever_pulled(true)
	var lever_ok: bool = is_instance_valid(main.world._lever_handle) \
			and main.world._lever_handle.is_inside_tree() and absf(main.world._lever_handle.rotation.z) > 1.0
	main.world.set_lever_pulled(false)
	check("电闸手柄未被合批（拉闸还能转）", lever_ok)

	# ===== 脚步实录（Kenney Impact Sounds，CC0）=====
	main.audio.ensure()
	check("实录脚步已载入：沙地 5 条 + 混凝土 5 条", (main.audio._step_rec.get("sand", []) as Array).size() == 5
		and (main.audio._step_rec.get("concrete", []) as Array).size() == 5)
	check("脚步取实录（Ogg）而非合成兜底", main.audio._pick_step("sand")[0] is AudioStreamOggVorbis
		and main.audio._pick_step("concrete")[0] is AudioStreamOggVorbis)
	var hall_p: Vector3 = HDData.HALL_CENTER
	hall_p.y = main.world.ground_height(hall_p.x, hall_p.z, -10.0)
	check("地下靶馆地坪判硬地（混凝土脚步）", absf(main.world.ground_height(hall_p.x, hall_p.z, hall_p.y + 0.5)) > 0.02)
	check("沙漠地面判沙地", absf(main.world.ground_height(-40.0, 120.0, 0.5)) <= 0.02)

	# ===== 第二张地图「航天基地」（space）——切换架构 / 分区 / 点位齐全 / 往返 =====
	# 大厅切换钮 + payload（照天气 V 钮先例：缺省 dam）
	main._raid_live = false
	main.lobby.show_lobby()
	main.lobby.set_tab(0)
	main.lobby._map_idx = 0
	# 切图前快照：坝障碍总数（往返后必须一致——防 set_map 泄漏/翻倍）
	var dam_obs_before: int = main.world.obstacles.size()
	var pl_map: Dictionary = main.lobby._deploy_payload("rifle", "pistol", false)
	check("出发 payload 带地图字段（缺省 dam）", str(pl_map.get("map", "")) == "dam")
	main.lobby._cycle_map()
	check("M/按钮循环到航天基地（payload map=space）",
		main.lobby.map_key() == "space" and main.lobby.map_name() == "航天基地"
			and str(main.lobby._deploy_payload("rifle", "pistol", false).get("map", "")) == "space")
	main.lobby._map_idx = 0   # 复位缺省
	# 切图整链：_start_mission 带 map=space → world.set_map + locks/loot/soldiers 复位
	main._start_mission({"primary": "rifle", "secondary": "pistol", "map": "space"})
	await frames(6)
	check("切图：map_id=space 且名称在册", main.world.map_id == "space"
		and main.world.map_name() == "航天基地")
	check("切图：坝三件已拆、航天整图挂载（同一 world 实例）", main.world.dam == null
		and main.world.dam_base == null and main.world.dam_zones == null
		and main.world.space_map != null and main.world.space_map.get_parent() == main.world)
	check("锁房 space 门控（0 间——dam 专属不建）", main.locks._states.is_empty())
	check("space 撤离五槽信标齐（槽位机制两图一致）",
		main.world._extract_vis.size() == 5 and main.world._extract_vis.has("main")
		and main.world._extract_vis.has("tunnel"))
	var ext_names := []
	for d0 in main.world.extract_defs():
		ext_names.append(str(d0["name"]))
	check("space 撤离点名（中控楼北/观景坪/试车场尾门/宿舍停车场）",
		ext_names.has("中控楼北") and ext_names.has("观景坪")
			and ext_names.has("试车场尾门") and ext_names.has("宿舍停车场"))
	# zone_at 四分区采样（核心区/发射坪=center · 工业带/中控桥=dam · 宿舍/发射外围=mid · 图缘=wild）
	check("space zone_at 四分区采样",
		main.world.zone_at(0.0, 0.0) == "center"
			and main.world.zone_at(0.0, 114.0) == "center"
			and main.world.zone_at(70.0, -40.0) == "dam"
			and main.world.zone_at(0.0, -50.0) == "dam"
			and main.world.zone_at(-92.0, -80.0) == "mid"
			and main.world.zone_at(0.0, 70.0) == "mid"
			and main.world.zone_at(0.0, -142.0) == "wild"
			and main.world.zone_at(-88.0, 124.0) == "wild")
	# 容器 ≥45：zone 字段与 zone_at 逐点一致（hd_soldiers 分组路由/loot 档位靠它）、边界内
	var sp_ct_n: int = main.world.container_spots.size()
	var sp_zone_ok: bool = sp_ct_n >= 45
	var sp_in_bound := true
	for c0 in main.world.container_spots:
		var spc1: Dictionary = c0
		if str(spc1["zone"]) != main.world.zone_at(spc1["pos"].x, spc1["pos"].z):
			sp_zone_ok = false
		if absf(spc1["pos"].x) > HDWorld.BOUND - 2.0 or absf(spc1["pos"].z) > HDWorld.BOUND - 2.0:
			sp_in_bound = false
	check("space 容器 ≥45 且 zone 字段与 zone_at 一致、全在边界内",
		sp_zone_ok and sp_in_bound, "n=%d" % sp_ct_n)
	# 巡逻 ≥24：zone 一致 + 每分区 ≥3（同 zone 家点+2 邻域成路）
	var sp_pat_n: int = main.world.patrol_spots.size()
	var sp_pat_zone_ok: bool = sp_pat_n >= 24
	var sp_pat_zone_n := {}
	for p0 in main.world.patrol_spots:
		var spp1: Dictionary = p0
		if str(spp1["zone"]) != main.world.zone_at(spp1["pos"].x, spp1["pos"].z):
			sp_pat_zone_ok = false
		sp_pat_zone_n[str(spp1["zone"])] = int(sp_pat_zone_n.get(str(spp1["zone"]), 0)) + 1
	for zkey in ["center", "dam", "mid", "wild"]:
		if int(sp_pat_zone_n.get(zkey, 0)) < 3:
			sp_pat_zone_ok = false
	check("space 巡逻 ≥24 且 zone 一致、每分区 ≥3", sp_pat_zone_ok,
		"n=%d %s" % [sp_pat_n, str(sp_pat_zone_n)])
	# 出生 5：边界内空地、离巡逻点 ≥30 m（dam 版同款口径）
	var sp_sp_ok := HDData.SPACE_SPAWN_POINTS.size() == 5
	for sp in HDData.SPACE_SPAWN_POINTS:
		for ps in main.world.patrol_spots:
			if Vector2(sp.x - ps["pos"].x, sp.z - ps["pos"].z).length() < 30.0:
				sp_sp_ok = false
		for ob in main.world.obstacles:
			if absf(sp.x - float(ob["cx"])) < float(ob["hx"]) + 0.6 \
					and absf(sp.z - float(ob["cz"])) < float(ob["hz"]) + 0.6:
				sp_sp_ok = false
		if absf(sp.x) > HDWorld.BOUND - 2.0 or absf(sp.z) > HDWorld.BOUND - 2.0:
			sp_sp_ok = false
	check("space 出生 ×5 都在边界内空地且离巡逻点 ≥30 m", sp_sp_ok)
	# 撤离五处都在边界内
	var sp_ext_ok: bool = main.world.extract_defs().size() == 5
	for d2 in main.world.extract_defs():
		var sp_ep: Vector3 = d2["pos"]
		if absf(sp_ep.x) > HDWorld.BOUND - 2.0 or absf(sp_ep.z) > HDWorld.BOUND - 2.0:
			sp_ext_ok = false
	check("space 撤离点 5 处都在边界内", sp_ext_ok)
	check("space 障碍 ≥200（轴对齐契约）", main.world.obstacles.size() >= 200,
		"n=%d" % main.world.obstacles.size())
	# 灵魂地标：火箭（发射坪中心 ≥55 m 高实体障碍——远看可辨的白箭体）
	var rocket_ok := false
	for ob in main.world.obstacles:
		if float(ob.get("top", 0.0)) >= 55.0 and absf(float(ob["cx"])) < 2.0 \
				and absf(float(ob["cz"]) - 114.0) < 2.0:
			rocket_ok = true
	check("火箭灵魂地标在位（发射坪中心 ≥55 m 高障碍）", rocket_ok)
	# 首领 ×2 + 保险柜 ×2（space 版：总装厂长/发射指挥官）
	var sp_boss_n := 0
	for sp_sv in main.soldiers.soldiers:
		if str(sp_sv.get("tier", "")) == "boss" and not sp_sv.has("reserve"):
			sp_boss_n += 1
	var sp_vaults: Array = main.loot._containers.filter(func(c): return str(c["cls"]) == "vault")
	check("space 首领 2 名 + 保险柜 2 只", sp_boss_n == 2 and sp_vaults.size() == 2,
		"boss=%d vault=%d" % [sp_boss_n, sp_vaults.size()])
	# 空投落点表分支（4-6 处、边界内）
	var sp_ad_ok: bool = HDData.SPACE_AIRDROP_POINTS.size() >= 4 \
			and HDData.SPACE_AIRDROP_POINTS.size() <= 6
	for ap0 in HDData.SPACE_AIRDROP_POINTS:
		if absf(ap0.x) > HDWorld.BOUND - 4.0 or absf(ap0.z) > HDWorld.BOUND - 4.0:
			sp_ad_ok = false
	check("space 空投落点表 4-6 处且在边界内", sp_ad_ok,
		"n=%d" % HDData.SPACE_AIRDROP_POINTS.size())
	# 开局状态：出生在 space 表内 + 简报卡带地图名一行
	var sp_spawn_in := false
	for sp2 in HDData.SPACE_SPAWN_POINTS:
		if Vector2(sp2.x - main.world.spawn_pos.x, sp2.z - main.world.spawn_pos.z).length() < 0.6:
			sp_spawn_in = true
	var brief_txt2 := ""
	if main.hud._brief_box != null:
		for bc2 in main.hud._brief_box.get_children():
			for lc2 in (bc2 as PanelContainer).find_children("*", "Label", true, false):
				brief_txt2 += str((lc2 as Label).text) + "|"
	check("space 开局出生在 space 表内 + 简报卡带地图名",
		sp_spawn_in and brief_txt2.contains("航天基地"), brief_txt2.substr(0, 60))
	# 靶场两图共享（切换架构二选一取「space 同坐标建造馆体」）
	check("space 图靶场馆体同坐标（地下馆地坪 -6.94 照旧）",
		absf(main.world.ground_height(HDData.HALL_CENTER.x, HDData.HALL_CENTER.z, -10.0)
			+ 6.94) < 0.001
			and main.world.in_hall(HDData.HALL_CENTER.x, HDData.HALL_CENTER.z))
	# 钥匙卡 space 局不注入、地上无钥匙
	var kc_space := 0
	for sp_it in main.loot.backpack:
		if str((sp_it as Dictionary).get("key", "")) != "":
			kc_space += 1
	check("space 局不注入钥匙卡/不刷钥匙", kc_space == 0 and main.loot.ground_count() == 0)
	main._raid_live = false
	# 往返：切回 dam（完整复位链走一遍——不炸、既有契约全复检）
	main._start_mission({"primary": "rifle", "secondary": "pistol", "map": "dam"})
	await frames(6)
	check("往返 dam：map_id 回 dam + 坝三件重挂", main.world.map_id == "dam"
		and main.world.dam != null and main.world.dam_base != null
		and main.world.dam_zones != null and main.world.space_map == null)
	check("往返 dam：锁房三间重建（armory/archive/camp）", main.locks._states.size() == 3
		and main.locks._states.has("armory") and main.locks._states.has("camp"))
	check("往返 dam：容器 58 / 巡逻 31 / 障碍 ≥268（既有契约复检）",
		main.world.container_spots.size() == 58
			and main.world.patrol_spots.size() == 31
			and main.world.obstacles.size() >= 268,
		"c=%d p=%d ob=%d" % [main.world.container_spots.size(),
			main.world.patrol_spots.size(), main.world.obstacles.size()])
	check("往返 dam：zone_at 回坝矩形裁决",
		main.world.zone_at(28.0, -95.0) == "dam" and main.world.zone_at(0.0, 0.0) == "center"
			and main.world.zone_at(96.0, 0.0) == "mid")
	check("往返 dam：障碍数与切图前一致（无泄漏/无翻倍）",
		main.world.obstacles.size() == dam_obs_before,
		"%d → %d" % [dam_obs_before, main.world.obstacles.size()])
	check("往返 dam：撤离点名回大坝口径", _ext_names_has(main.world, "大坝撤离"))
	main._raid_live = false

	print("[huodai] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	main.free()
	quit(0 if fails == 0 else 1)


## world.extract_defs 里是否含指定撤离点名（往返断言用）
func _ext_names_has(world, want: String) -> bool:
	for d in world.extract_defs():
		if str(d["name"]) == want:
			return true
	return false
