# 画面探针（窗口模式出图，headless 兼容跑断言）：大厅 → 行动出生点 → 远景士兵
# → 中心危险区 → 靶馆——五张基础截图 + 附加验收：开镜渐晕 → 换弹手部 → 汤姆逊腰射
# → 八把新枪逐把腰射（shot_gun_mp5/p90/uzi/vector/m4a1/akm/scarh/mk4.png）→
# 双槽切枪串色验收（shot_slot_switch.png）→ 大厅弹药行特写（只读）→
# 改枪台无购买入口图证（shot_bench.png）→ 交易行全景（shot_market.png）→
# 交易行未拥有枪购买特写（shot_market_buy.png）（共 21 张）
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s res://scripts/probe_shot.gd
# headless 下（集成门槛跑法）无渲染目标：跳过保存只跑断言，进程照常 quit 不挂起
extends SceneTree

var checks: int = 0     # 附加验收断言计数（软断言：只记档打印，不中断后续截图）
var fails: int = 0
var shots_saved: int = 0   # 实存截图数（headless 下跳过保存，只跑断言链）
var save_bak := ""      # 非空 = 探针前有真实存档，收尾还原（探针装瞄具会触发 save()）

func frames(n: int) -> void:
	for i in n:
		await process_frame

## 软断言（参照 test_huodai.check）：PASS/FAIL 打进日志，失败不停探针
func check(name: String, ok: bool, extra := "") -> void:
	checks += 1
	if not ok:
		fails += 1
	print("[probe] %s %s%s" % ["PASS" if ok else "FAIL", name,
			(" —— " + extra) if extra != "" else ""])

## 等状态成立：pred 每帧一查，上限 max_frames 帧；返回最终是否成立
func wait_until(pred: Callable, max_frames: int = 300) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await process_frame
	return pred.call()

## 截图统一出口：headless（无渲染目标）下 get_image() 返回 null——
## 直接对 null 调 save_png 会抛脚本错误断掉 _initialize 协程，quit() 永远
## 到不了 = 进程挂起（2026-10 门槛 124 排查根因）。此处跳过保存只打日志，
## 窗口模式照常出图
func shot(path: String) -> void:
	if root.get_texture() == null:
		print("[probe] 跳过截图 %s（headless 无渲染目标）" % path)
		return
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("[probe] 跳过截图 %s（headless 渲染目标无图像）" % path)
		return
	img.save_png(path)
	shots_saved += 1

func _initialize() -> void:
	var save := "user://huodai_save.json"
	if FileAccess.file_exists(save):
		save_bak = ProjectSettings.globalize_path(save) + ".probe_bak"
		if FileAccess.file_exists(save_bak):
			DirAccess.remove_absolute(save_bak)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(save), save_bak)
	DirAccess.make_dir_recursive_absolute("res://out")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	shot("res://out/shot_lobby.png")

	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(50)
	shot("res://out/shot_mission_spawn.png")

	# 远景验收（问题②）：0 号兵瞬移到玩家前方 100m 面朝玩家——
	# 轻雾下"远处可见人形"的证据图。state=combat + last_known=自身：
	# 100m 超出交战视距不会开火/转向，站桩摆拍
	var pfwd := Vector3(sin(main.player.yaw), 0.0, cos(main.player.yaw))
	var far: Vector3 = main.player.pos + pfwd * 100.0   # main 鸭子链无类型：显式 Vector3
	var s0: Dictionary = main.soldiers.soldiers[0]
	s0["pos"] = Vector3(far.x, main.world.ground_height(far.x, far.z), far.z)
	s0["last_known"] = s0["pos"]
	s0["yaw"] = atan2(main.player.pos.x - far.x, main.player.pos.z - far.z)
	s0["moving"] = false
	s0["engaged"] = false
	s0["state"] = "combat"
	main.soldiers._write_pose(0)
	await frames(8)
	shot("res://out/shot_far_soldier.png")

	# 中心危险区：站到 warehouse 附近朝建筑看
	main.player.enter(Vector3(-10.0, 0.0, 30.0))
	main.player.yaw = atan2(10.0, -30.0)
	main.player.pitch = 0.05
	main.player.update(0.016)
	await frames(20)
	shot("res://out/shot_center.png")

	main._enter_range()
	await frames(40)
	shot("res://out/shot_range.png")

	# ---- 附加验收 6：shot_ads —— 靶场装红点镜开镜，专验渐晕「边上与四角
	# 暗度一致、无重叠更黑」。开镜动作 hd_scope 实际绑定鼠标右键
	# （main._register_inputs），探针用 action_press 直推动作层，不依赖物理键
	main.stash.scopes_owned.append("reddot")   # 冷启动仓库无镜：先拥有再装配
	main.stash.equip_scope("rifle", "reddot")
	Input.action_press("hd_scope")
	check("开镜过渡到位 ads=1", await wait_until(func(): return main.player.ads >= 1.0))
	check("开镜覆盖层已显示", main.hud._scope_ov.visible)
	await frames(4)
	shot("res://out/shot_ads.png")
	Input.action_release("hd_scope")
	await wait_until(func(): return main.player.ads <= 0.4)   # 收镜，别污染下张

	# ---- 附加验收 7：shot_reload_hand —— 打两发按 R，换弹中段截图。
	# rifle 换弹全长 1.5s：剩约 0.95~0.4s 处于「旧匣已落/新匣将入、枪体
	# 下沉倾斜」的中段（换弹手部 + 弹匣动画都在画面里）
	main.guns.try_fire()
	await wait_until(func(): return main.guns.fire_cd <= 0.0)   # 等射速间隔
	main.guns.try_fire()
	check("两发后余弹 28", main.guns.ammo == 28, "ammo=%d" % main.guns.ammo)
	Input.action_press("hd_reload")
	await frames(2)
	Input.action_release("hd_reload")
	check("换弹已启动", await wait_until(func(): return main.guns.reloading > 0.0))
	check("走到换弹中段", await wait_until(func(): return main.guns.reloading <= 0.95))
	check("截图帧仍在换弹", main.guns.reloading > 0.0)
	main.player.recoil_pitch = 0.0   # 摆平两发后坐，画面聚焦手部
	main.player.recoil_yaw = 0.0
	await frames(1)
	shot("res://out/shot_reload_hand.png")
	check("换弹正常收尾", await wait_until(func(): return main.guns.reloading <= 0.0))

	# ---- 附加验收 8：shot_smg —— 主武器换冲锋枪再进靶场，腰射截汤姆逊
	# 造型（木托/护木）；rifle 的 M7 侧面轮廓看 shot_mission_spawn.png 即可
	main.stash.loadout = {"primary": "smg", "secondary": "pistol"}
	main._enter_range()
	await frames(40)
	main.player.recoil_pitch = 0.0
	main.player.recoil_yaw = 0.0
	await frames(2)
	shot("res://out/shot_smg.png")

	# ---- 附加验收 9~16：八把新枪逐把腰射（shot_gun_<id>.png）——
	# 探针直拥不走现金（guns_owned.append），不污染经济断言；
	# 设主武器再进靶场截腰射照，验收员按 features 清单逐张判造型
	for gid in ["mp5", "p90", "uzi", "vector", "m4a1", "akm", "scarh", "mk4"]:
		if not main.stash.guns_owned.has(gid):
			main.stash.guns_owned.append(gid)
		main.stash.loadout = {"primary": gid, "secondary": "pistol"}
		main._enter_range()
		await frames(40)
		main.player.recoil_pitch = 0.0
		main.player.recoil_yaw = 0.0
		await frames(2)
		shot("res://out/shot_gun_%s.png" % gid)

	# ---- 附加验收 17：shot_slot_switch —— 双槽串色验收（黄壳回归红线）：
	# 主=MK4（全黑）+ 副=汤姆逊（蓝钢+木）两把异枪同局共存，切到副武器截
	# 汤姆逊——配合上张 shot_gun_mk4.png 证明两把枪颜色/轮廓各自独立
	main.stash.loadout = {"primary": "mk4", "secondary": "smg"}
	main._enter_range()
	await frames(40)
	check("双槽枪模 id 独立", str(main.guns._guns["primary"]["id"]) == "mk4"
		and str(main.guns._guns["secondary"]["id"]) == "smg")
	main.guns._equip("secondary")
	await frames(4)
	check("切槽后 cur_id=smg", main.guns.cur_id == "smg",
		"cur_id=%s" % main.guns.cur_id)
	main.player.recoil_pitch = 0.0
	main.player.recoil_yaw = 0.0
	await frames(2)
	shot("res://out/shot_slot_switch.png")

	# ---- 附加验收 18：shot_ammo_shop —— 大厅出发页弹药行特写（极致备弹经济）：
	# 光标落当页第一把候选枪行 → 侧栏速览联动，金色「极致备弹 余 N 发」只读行
	# （购买入口已迁交易行③区：B 换挡 / 空格 /「购 N 发」钮在页签 4 生效，见下两张）
	main.stash.cash = 20000   # 摆拍现金（收尾还原真实存档）
	check("弹药经济首读送满额礼物", main.stash.ammo_of("mp5") == int(HDData.RESERVE["mp5"]),
		"mp5=%d" % main.stash.ammo_of("mp5"))
	main.lobby.set_tab(0)
	main.lobby._cur0 = 2   # 光标落当页第一把候选枪行（速览随动显示该枪弹药行）
	main.lobby.show_lobby()
	await frames(8)
	shot("res://out/shot_ammo_shop.png")
	main.lobby.hide_lobby()

	# ---- 附加验收 19：shot_bench —— 改枪台页全景（购买入口回收图证）：
	# 选中 M7（表序 2，非自带镜枪），右列 6 档瞄具逐行核对——未拥有者
	# （全息/3.5×/5×/热成像）只有置灰「交易行有售」标签、无任何钮；已拥有且已装
	# 的红点镜=「已装」置灰、机瞄=「卸下」（装配功能保留，非购买）；顶栏现金
	# ₵20,000 同框——有钱也无购买入口可点
	main.stash.cash = 20000   # 摆拍现金（收尾还原真实存档）
	main.lobby.set_tab(2)
	main.lobby._gun_idx = 2   # M7 战斗步枪（附加验收 6 已给 rifle 装红点）
	main.lobby.show_lobby()
	await frames(8)
	shot("res://out/shot_bench.png")
	main.lobby.hide_lobby()

	# ---- 附加验收 20：shot_market —— 交易行页全景（全游戏唯一购买入口）：
	# 三段分区同框——① 枪械全表（未拥有「₵N+购买」/已拥有置灰）· ② 瞄具 6 档
	# · ③ 极致备弹（选枪 + B 换挡 + 购 N 发）+ 顶栏现金 ₵20,000
	if main.stash.guns_owned.has("mp5"):
		main.stash.guns_owned.erase("mp5")   # 摆拍未拥有态（前面枪照段落已把 MP5 直拥）
	main.lobby.set_tab(3)
	main.lobby.show_lobby()
	await frames(8)
	shot("res://out/shot_market.png")

	# ---- 附加验收 21：shot_market_buy —— 特写：光标选中未拥有枪（MP5 ₵1,200），
	# 行高亮 + 行内「购买」钮高亮；只选中不确认，不实际成交
	main.lobby._market_sec = 0
	main.lobby._market_gun = 6   # GUNS 表序 6 = MP5
	main.lobby.set_tab(3)        # 同页签重刷，光标落 MP5 行
	await frames(8)
	shot("res://out/shot_market_buy.png")
	main.lobby.hide_lobby()

	print("[probe] 探针完成：实存 %d/21 张 → res://out/  （断言 %d 项 / 失败 %d）" % [shots_saved, checks, fails])
	# 收尾还原真实存档：探针内装配瞄具触发过 stash.save()，不能留在用户档里
	var gp := ProjectSettings.globalize_path(save)
	DirAccess.remove_absolute(gp)
	if save_bak != "":
		DirAccess.rename_absolute(save_bak, gp)
	main.free()
	quit(0)
