# 画面探针（窗口模式，非 headless）：大厅 → 行动出生点 → 远景士兵 → 中心危险区 → 靶馆
# 五张基础截图 + 附加验收：开镜渐晕 → 换弹手部 → 汤姆逊腰射 → 七把新枪逐把腰射
# （shot_gun_mp5/p90/uzi/vector/m4a1/akm/scarh.png）→ 大厅弹药行特写（共 16 张）
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s res://scripts/probe_shot.gd
extends SceneTree

var checks: int = 0     # 附加验收断言计数（软断言：只记档打印，不中断后续截图）
var fails: int = 0
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
	root.get_texture().get_image().save_png("res://out/shot_lobby.png")

	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(50)
	root.get_texture().get_image().save_png("res://out/shot_mission_spawn.png")

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
	root.get_texture().get_image().save_png("res://out/shot_far_soldier.png")

	# 中心危险区：站到 warehouse 附近朝建筑看
	main.player.enter(Vector3(-10.0, 0.0, 30.0))
	main.player.yaw = atan2(10.0, -30.0)
	main.player.pitch = 0.05
	main.player.update(0.016)
	await frames(20)
	root.get_texture().get_image().save_png("res://out/shot_center.png")

	main._enter_range()
	await frames(40)
	root.get_texture().get_image().save_png("res://out/shot_range.png")

	# ---- 附加验收 6：shot_ads —— 靶场装红点镜开镜，专验渐晕「边上与四角
	# 暗度一致、无重叠更黑」。开镜动作 hd_scope 实际绑定鼠标右键
	# （main._register_inputs），探针用 action_press 直推动作层，不依赖物理键
	main.stash.scopes_owned.append("reddot")   # 冷启动仓库无镜：先拥有再装配
	main.stash.equip_scope("rifle", "reddot")
	Input.action_press("hd_scope")
	check("开镜过渡到位 ads=1", await wait_until(func(): return main.player.ads >= 1.0))
	check("开镜覆盖层已显示", main.hud._scope_ov.visible)
	await frames(4)
	root.get_texture().get_image().save_png("res://out/shot_ads.png")
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
	root.get_texture().get_image().save_png("res://out/shot_reload_hand.png")
	check("换弹正常收尾", await wait_until(func(): return main.guns.reloading <= 0.0))

	# ---- 附加验收 8：shot_smg —— 主武器换冲锋枪再进靶场，腰射截汤姆逊
	# 造型（木托/护木）；rifle 的 M7 侧面轮廓看 shot_mission_spawn.png 即可
	main.stash.loadout = {"primary": "smg", "secondary": "pistol"}
	main._enter_range()
	await frames(40)
	main.player.recoil_pitch = 0.0
	main.player.recoil_yaw = 0.0
	await frames(2)
	root.get_texture().get_image().save_png("res://out/shot_smg.png")

	# ---- 附加验收 9~15：七把新枪逐把腰射（shot_gun_<id>.png）——
	# 探针直拥不走现金（guns_owned.append），不污染经济断言；
	# 设主武器再进靶场截腰射照，验收员按 features 清单逐张判造型
	for gid in ["mp5", "p90", "uzi", "vector", "m4a1", "akm", "scarh"]:
		if not main.stash.guns_owned.has(gid):
			main.stash.guns_owned.append(gid)
		main.stash.loadout = {"primary": gid, "secondary": "pistol"}
		main._enter_range()
		await frames(40)
		main.player.recoil_pitch = 0.0
		main.player.recoil_yaw = 0.0
		await frames(2)
		root.get_texture().get_image().save_png("res://out/shot_gun_%s.png" % gid)

	# ---- 附加验收 16：shot_ammo_shop —— 大厅出发页弹药行特写（极致备弹经济）：
	# 光标落当页第一把候选枪行 → 侧栏速览联动，金色「极致备弹 余 N 发」行与
	# 购买挡位按钮（B 换挡 / 购 30 发·₵X）同框可见
	main.stash.cash = 20000   # 摆拍现金（收尾还原真实存档）
	check("弹药经济首读送满额礼物", main.stash.ammo_of("mp5") == int(HDData.RESERVE["mp5"]),
		"mp5=%d" % main.stash.ammo_of("mp5"))
	main.lobby.set_tab(0)
	main.lobby._cur0 = 2   # 光标落当页第一把候选枪行（速览随动显示该枪弹药行）
	main.lobby.show_lobby()
	await frames(8)
	root.get_texture().get_image().save_png("res://out/shot_ammo_shop.png")
	main.lobby.hide_lobby()

	print("[probe] 16 张截图完成 → res://out/  （断言 %d 项 / 失败 %d）" % [checks, fails])
	# 收尾还原真实存档：探针内装配瞄具触发过 stash.save()，不能留在用户档里
	var gp := ProjectSettings.globalize_path(save)
	DirAccess.remove_absolute(gp)
	if save_bak != "":
		DirAccess.rename_absolute(save_bak, gp)
	main.free()
	quit(0)
