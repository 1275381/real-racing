# 画面探针（窗口模式出图，headless 兼容跑断言）：大厅 → 行动出生点 → 远景士兵
# → 中心危险区 → 靶馆——五张基础截图 + 附加验收：开镜渐晕 → 换弹手部 →
# 胸前提枪姿态（shot_carry 胸前横端+双手 / shot_carry_sway 横晃反相位错位）→
# 汤姆逊腰射 → 八把新枪逐把腰射（shot_gun_mp5/p90/uzi/vector/m4a1/akm/scarh/mk4.png）→
# 双槽切枪串色验收（shot_slot_switch.png）→ 大厅弹药行特写（只读）→
# 改枪台无购买入口图证（shot_bench.png）→ 交易行全景（shot_market.png）→
# 交易行未拥有枪购买特写（shot_market_buy.png）→ 大坝分区四连拍
# （shot_dam_far 坝全景剪影 / shot_dam_base 坝底工业区街景 / shot_dam_graffiti 涂鸦环近景
# / shot_dam_ref 对位相机主图——后撤高机位纯净全景（无 HUD/枪模）：山脊+坝面
# +下幅工业区（厂房/集装箱/白罐/烟柱/棕榈），对位目标图四层构图）
# （共 28 张；腰射/换弹手部/逐枪美照/切枪/探头各段用 guns.carry_override=0
# 锁存肩射位摆拍（fire_pose），拍完恢复 -1——既有构图不被胸前姿态改变）
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s res://scripts/probe_shot.gd
# headless 下（集成门槛跑法）无渲染目标：跳过保存只跑断言，进程照常 quit 不挂起
extends SceneTree

var checks: int = 0     # 附加验收断言计数（软断言：只记档打印，不中断后续截图）
var fails: int = 0
var shots_saved: int = 0   # 实存截图数（headless 下跳过保存，只跑断言链）
var save_bak := ""      # 非空 = 探针前有真实存档，收尾还原（探针装瞄具会触发 save()）
var _m                  # main 引用（shot() 收暂停菜单护栏用，_initialize 里赋值）

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
## 窗口模式照常出图。另：窗口失焦会触发 main 的自动暂停菜单罩住画面——
## 拍照前强制收菜单（2026-10 shot_gun_mk4 被暂停层糊住的事故）
func shot(path: String) -> void:
	if _m != null and _m.hud != null and _m.hud.menu_visible:
		_m.hud.hide_menu()
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
	_m = main
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

	# ---- 大坝分区四连拍（远景剪影 / 坝底工业区街景 / 涂鸦环近景 / 对位相机主图） ----
	# 第 3 轮验收协议：center/dam 站位会触发「! 高危战区」红罩铺满全幅（base 图
	# 满幅粉格纹污染色彩判断）——统一「冻结摆拍」法：dead=true 冻结玩家 update
	# （hd_player.gd:79 死亡早退），相机手动定格原街景位，player.pos 搬到
	# (90,0,-30)（d=95 zone=mid → main._step_mission 下一帧 set_danger(false)），
	# 红罩熄灭后截图，拍完即恢复。四图色彩全部纯净。
	# shot_dam_far：北区出生带 (0,40) 面北望坝全景——坝顶 y52 在 158m 外，
	# 抬头 0.15 把 y13~52 坝体+坝顶门吊天际线收进画幅（剪影验收）
	main.player.enter(Vector3(0.0, 0.0, 40.0))
	main.player.yaw = PI          # 面朝 -Z（北）
	main.player.pitch = 0.15
	main.player.update(0.016)
	main.player.dead = true
	main.player.cam.position = Vector3(0.0, 1.55, 40.0)
	main.player.cam.rotation = Vector3(0.15, PI + PI, 0)
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_dam_far.png")
	main.player.dead = false

	# shot_dam_base：坝底工业区街景——(10,-90) 站服务街条上、棕榈 (8,-86) 退到相机
	# 背后（首版 (10,-82) 树干正卡开洞2 视线，实拍返工），正对廊道开洞2（x∈[2,18]）：
	# 22m 外洞内 loot 容器②指示灯、柱廊、右前红门吊腿同框（视线 x=10 与丙泵站
	# x≤-1/甲厂房 x≥15 全让位）
	main.player.enter(Vector3(10.0, 0.0, -90.0))
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	main.player.dead = true
	main.player.cam.position = Vector3(10.0, 1.55, -90.0)
	main.player.cam.rotation = Vector3(0.0, PI + PI, 0)
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_dam_base.png")
	main.player.dead = false

	# shot_dam_graffiti：涂鸦环近景——(-24,0,-90) 站服务街、侧 20m 瞄准环心
	# （yaw=atan2(20,-33.8)≈2.608，pitch=atan(28.4/39.3)≈0.625，正 pitch=抬头
	# hd_player.gd:76 同号）。视线越廊道墙顶（y17.5>13.1）后环可见下界 y≈19.3：
	# 斜杠全长（y21.5~38.5）+环中上弧+滴泪条（y19~23）全部入画，两根廊道柱
	# （x=-20/-40）左右框景=参考图「环被竖条带打断」原样；丙泵站/棕榈全出画。
	# 机位迭代史：(-4,-100) 街面版下界 y≈24.2 环下弧被吞 → (-4,-84) 越泵站顶但
	# 泵站黄墙占满下幅 → 侧站此位（python3 视线复算三版择优）
	main.player.enter(Vector3(-24.0, 0.0, -90.0))
	main.player.yaw = 2.608
	main.player.pitch = 0.625
	main.player.update(0.016)
	main.player.dead = true
	main.player.cam.position = Vector3(-24.0, 1.55, -90.0)
	main.player.cam.rotation = Vector3(0.625, 2.608 + PI, 0)
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_dam_graffiti.png")
	main.player.dead = false

	# ---- shot_dam_ref：对位相机主图（第 6 轮机位回收：撤销第 5 轮的 204m 后撤——
	# 雾 0.004×204m≈80% 遮蔽把四层构图全洗没了。回到近位 cam(16,26,6) 瞄
	# (0,16,-110)：yaw=atan2(-16,-116)≈-2.995、pitch=atan2(-10,116.9)≈-0.0855、
	# FOV 58，距离 ~117m，坝体（高 ~40m×宽 ~200m）占画面高约 80%、宽幅裁切同目标图）
	main.player.enter(Vector3(16.0, 0.0, 6.0))
	main.player.yaw = -2.995
	main.player.pitch = -0.0855
	main.player.update(0.016)
	main.player.dead = true
	main.player.cam.position = Vector3(16.0, 26.0, 6.0)
	main.player.cam.rotation = Vector3(-0.0855, -2.995 + PI, 0)
	main.player.cam.fov = 58.0
	var hud0: bool = main.hud.visible
	main.hud.visible = false
	var holder_vis := {}
	for slot_v in main.guns._guns:
		var g: Dictionary = main.guns._guns[slot_v]
		holder_vis[slot_v] = g["holder"].visible
		g["holder"].visible = false
	await frames(6)
	shot("res://out/shot_dam_ref.png")
	main.player.dead = false
	main.player.cam.fov = main.player.BASE_FOV
	main.hud.visible = hud0
	for slot_v in holder_vis:
		main.guns._guns[slot_v]["holder"].visible = holder_vis[slot_v]

	main._enter_range()
	await frames(40)
	shot("res://out/shot_range.png")

	# ---- 附加验收 6：shot_ads —— 靶场装红点镜开镜，专验渐晕「边上与四角
	# 暗度一致、无重叠更黑」。开镜动作 hd_scope 实际绑定鼠标右键
	# （main._register_inputs），探针用 action_press 直推动作层，不依赖物理键
	main.stash.scopes_owned.append("reddot")   # 冷启动仓库无镜：先拥有再装配
	main.stash.equip_scope("rifle", "reddot")
	# 装镜不重挂：scope_provider 只在 _mount_slot 建枪模时读，enter() 同槽同枪
	# 复用 holder（重建条件=换枪 id）——装配后手动拆旧挂新（照 enter 的重建
	# 套路：先隐身防同帧叠影 → queue_free 枪模/火光 → 重挂 → 重装槽位），
	# shot_ads.png 才真正拍得到红点镜 3D 镜体（玻璃窗/窗内红点/底座）
	var old_rd: Dictionary = main.guns._guns["primary"]
	var old_holder: Node3D = old_rd["holder"]
	old_holder.visible = false
	old_holder.queue_free()
	(old_rd["flash"] as OmniLight3D).queue_free()
	main.guns._guns.erase("primary")
	main.guns._mount_slot("primary")
	main.guns._equip("primary")
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
	main.guns.carry_override = 0.0   # fire_pose 摆拍锁存：换弹手部构图与胸前姿态解耦（拍完恢复）
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
	main.guns.carry_override = -1.0   # 解除摆拍锁存——下面的胸前美照走真实姿态

	# ---- 附加验收 7b：shot_carry / shot_carry_sway —— 胸前提枪（三角洲式
	# 松弛持枪）：静置等 carry_w→1，枪横端胸前 + 双手可见（左手托护木/右手
	# 握把）；再把 bob 相位拨到反侧截横晃另一相（与前者错位可见）。摆拍手段：
	# 直接写 player._bob_t（横晃 sin 的相位源），不碰姿态系统本身
	check("静置回胸前 carry_w≈1", await wait_until(
			func(): return main.guns.carry_w >= 0.99))
	check("胸前双手可见", main.guns._hand_l != null and main.guns._hand_l.visible
		and main.guns._hand_r != null and main.guns._hand_r.visible)
	var c_hold: Node3D = main.guns._guns["primary"]["holder"]
	var rz: float = c_hold.rotation_degrees.z
	check("胸前枪根滚转 70~90°（横置）", rz > 70.0 and rz < 90.0, "z=%.1f°" % rz)
	main.player._bob_t = PI   # sin(π·0.5)=+1 → 横晃右极
	await frames(3)
	var cx1: float = c_hold.position.x
	shot("res://out/shot_carry.png")
	main.player._bob_t = PI * 3.0   # sin(3π·0.5)=-1 → 横晃左极（反相位）
	await frames(3)
	var cx2: float = c_hold.position.x
	shot("res://out/shot_carry_sway.png")
	check("横晃两相反向错位 |Δx|>0.01", absf(cx2 - cx1) > 0.01,
		"x1=%.3f x2=%.3f" % [cx1, cx2])

	# ---- 附加验收 8：shot_smg —— 主武器换冲锋枪再进靶场，腰射截汤姆逊
	# 造型（木托/护木）；rifle 的 M7 侧面轮廓看 shot_mission_spawn.png 即可
	main.guns.carry_override = 0.0   # fire_pose 摆拍：腰射造型照不引入胸前姿态（逐枪美照同）
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
	main.guns.carry_override = -1.0   # 逐枪美照段落结束，解除 fire_pose 摆拍锁存

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

	# ---- 附加验收 26：shot_lean —— 右探头（E）：地平线左高右低 + 相机右移
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(20)
	main.guns.carry_override = 0.0   # fire_pose 摆拍：探头验收看相机偏移，枪位维持肩射
	Input.action_press("hd_lean_right")
	await frames(14)
	check("探头截图帧 lean_cur>0.9", main.player.lean_cur > 0.9,
		"lean=%.2f" % main.player.lean_cur)
	shot("res://out/shot_lean.png")
	Input.action_release("hd_lean_right")
	await frames(4)
	main.guns.carry_override = -1.0   # 解除摆拍锁存

	print("[probe] 探针完成：实存 %d/28 张 → res://out/  （断言 %d 项 / 失败 %d）" % [shots_saved, checks, fails])
	# 收尾还原真实存档：探针内装配瞄具触发过 stash.save()，不能留在用户档里
	var gp := ProjectSettings.globalize_path(save)
	DirAccess.remove_absolute(gp)
	if save_bak != "":
		DirAccess.rename_absolute(save_bak, gp)
	main.free()
	quit(0)
