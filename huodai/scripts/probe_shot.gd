# 画面探针（窗口模式出图，headless 兼容跑断言）：大厅 → 行动出生点 → 远景士兵
# → 中心危险区 → 靶馆——五张基础截图 + 附加验收：开镜渐晕 → 红点镜大窗两连拍
# （shot_reddot_hip 腰射大窗造型 / shot_reddot_ads 开镜红点居窗）→ 换弹手部 →
# 汤姆逊腰射 → 九把新枪逐把腰射（shot_gun_mp5/p90/uzi/vector/m4a1/akm/scarh/mk4/m250.png）→
# 双槽切枪串色验收（shot_slot_switch.png）→ 大厅弹药行特写（只读）→
# 大厅三页整页（shot_page_depart 出发大厅 / shot_page_bench 改枪台·选中枪+已拥有未装镜
# 让「换装」钮可见 / shot_page_market 交易行四段分区全貌）→
# 改枪台去购买跳转+当前装配摘要图证（shot_bench.png）→ 交易行四段全景（shot_market.png）→
# 交易行未拥有枪购买特写（shot_market_buy.png）→ 交易行④ 仓库·战利品段图证
# （shot_market_warehouse.png：段选中态+两行滚动窗口+「Enter 一键变卖全部」钮）→
# 大坝分区四连拍
# （shot_dam_far 坝全景剪影 / shot_dam_base 坝底工业区街景 / shot_dam_graffiti 涂鸦环近景
# / shot_dam_ref 对位相机主图——后撤高机位纯净全景（无 HUD/枪模）：山脊+坝面
# +下幅工业区（厂房/集装箱/白罐/烟柱/棕榈），对位目标图四层构图）→
# 四新区五连拍（shot_dam_overview 后撤高机位全图纯净全景 + shot_dam_new1..4
# 军营/大电/水泥厂/游客中心走位近中景，与 barracks/substation/cement/visitor
# 参考图逐张对照形状语言）→
# 实战/靶场入口可辨（shot_entries 出发大厅整页：红橙实战 CTA 与绿色靶场入口同框）+
# 靶场暂停菜单（shot_range_menu：靶场暂停/离开靶场，模式分化文案图证）
# （共 40 张：31 处 shot() 调用 + 逐枪美照循环 9 把——旧注释「29/31/33/35 张」为误计，按实拍数订正；
#  腰射/换弹手部/逐枪美照/切枪/探头各段姿势即肩射位——胸前提枪已移除）
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
## 拍照前强制收菜单（2026-10 shot_gun_mk4 被暂停层糊住的事故）；
## keep_menu=true 例外：拍的就是暂停菜单本身（shot_range_menu）
func shot(path: String, keep_menu := false) -> void:
	if not keep_menu and _m != null and _m.hud != null and _m.hud.menu_visible:
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

	# ---- 大厅三页整页截图（三页签改造图证）：出发大厅 / 改枪台 / 交易行 ----
	shot("res://out/shot_page_depart.png")   # 默认页=出发大厅（槽位卡+候选枪分页+速览）
	# ---- 实战/靶场入口可辨图证：出发大厅整页——红橙「出发 · 实战行动」CTA
	#      （含消耗提示行）与底栏绿色「G · 练习靶场 · 不耗弹药」入口同框
	shot("res://out/shot_entries.png")
	if not main.stash.scopes_owned.has("reddot"):
		main.stash.scopes_owned.append("reddot")   # 摆拍已拥有未装瞄具（收尾还原真实存档）
	# 光标先落位再 set_tab（set_tab 即重渲染；摆拍后赋值则画面停在旧帧——set_tab
	# 是唯一重渲染入口，无 show_lobby 兜底）
	main.lobby._gun_idx = 2    # 改枪台：选中 M7 + 光标落红点镜行（「换装」钮可见）
	main.lobby._bench_col = 1
	main.lobby._scope_idx = 2  # 右列条目序 2 = 红点镜（已拥有未装）
	main.lobby.set_tab(1)
	await frames(8)
	shot("res://out/shot_page_bench.png")
	main.lobby.set_tab(2)      # 交易行：① 枪械 ② 瞄具 ③ 备弹 ④ 仓库条 四段分区全貌
	await frames(8)
	shot("res://out/shot_page_market.png")
	main.lobby.set_tab(0)
	main.lobby.hide_lobby()

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

	# ---- shot_dam_overview：后撤高机位全图纯净全景（无 HUD/枪模，:198-211 协议）——
	#      高机位瞄 (0,8,-40)、FOV 55：四层构图=坝脊+坝顶吊机天际线 → 中环四 accent
	#      （西南筒仓三连/正东桁架/正西板房/东南玻璃体+旗杆）→ 中心巷道/集装箱带
	#      → 前景戈壁；军营在西侧入画、坝后山脊东北主峰对角呼应。
	#      机位迭代史：首版 cam(-118,58,118) 与筒仓列（沿 z 布列）近乎轴向对视，
	#      三连剪影前后互挡只读出 2 座——东移 22m 到 (-96,58,116) 斜读三连
	#      （机位迭代先例 :171-174）；yaw=atan2(96,-156)≈2.5899、
	#      pitch=atan2(-50,183.2)≈-0.2667（python3 复算）
	main.player.enter(Vector3(-96.0, 0.0, 116.0))
	main.player.dead = true
	main.player.cam.position = Vector3(-96.0, 58.0, 116.0)
	main.player.cam.rotation = Vector3(-0.2667, 2.5899 + PI, 0)
	main.player.cam.fov = 55.0
	var hud_ov: bool = main.hud.visible
	main.hud.visible = false
	var holder_ov := {}
	for slot_v in main.guns._guns:
		var g_ov: Dictionary = main.guns._guns[slot_v]
		holder_ov[slot_v] = g_ov["holder"].visible
		g_ov["holder"].visible = false
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(6)
	shot("res://out/shot_dam_overview.png")
	main.player.dead = false
	main.player.cam.fov = main.player.BASE_FOV
	main.hud.visible = hud_ov
	for slot_v in holder_ov:
		main.guns._guns[slot_v]["holder"].visible = holder_ov[slot_v]

	# ---- 四新区走位近中景（冻结摆拍 :139-149 协议：dead=true 冻玩家 update、
	#      cam 手动定格、player.pos 挪 (90,0,-30) 熄红罩；四处站位实测均 mid）。
	#      机位允许实拍迭代（:171-174 先例），以参考图同构为准：
	#      new1 军营——东门外 (−96,4) 朝西北瞄板房南面（三门洞+双坡脊，对位
	#      barracks.jpg U 形营地营房视角；视线左偏 20° 把帐篷×2+火堆收进左前景）
	#      机位迭代史：首版 (−100,−8) 朝正西北板房立面完整但帐篷在机位身后
	#      缺营地语汇——东门位 (−96,4) 朝 (−118,5.5,−19) 复拍（实测 mid 无红罩）
	main.player.enter(Vector3(-96.0, 0.0, 4.0))
	main.player.dead = true
	main.player.cam.position = Vector3(-96.0, 1.55, 4.0)
	main.player.cam.rotation = Vector3(0.1236, -2.378 + PI, 0)
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_dam_new1.png")
	main.player.dead = false
	#      new2 大电——围栏东南角外 (92,6) 朝西北瞄 (110,3,−20)（机位迭代史：
	#      首版 (90,−14) 朝 +X 只见主控楼西立面无窗纯方块+1 台变压器——判图
	#      3 轮连报；斜穿视角同框收南列变压器+桁架列+主控楼南窗带，实测 mid）
	main.player.enter(Vector3(92.0, 0.0, 6.0))
	main.player.dead = true
	main.player.cam.position = Vector3(92.0, 1.55, 6.0)
	main.player.cam.rotation = Vector3(0.0459, 2.539 + PI, 0)
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_dam_new2.png")
	main.player.dead = false
	#      new3 水泥厂——主楼东北料场 (−82,8) 朝西南瞄筒仓列（三连直筒+锥顶+
	#      渡槽斜线+主楼北面卷帘门，对位 cement.jpg 筒仓群+斜撑渡槽；原候选
	#      (−68,32) 实测落 center 红罩、(−70,40) 视线先穿主楼，均弃用）
	main.player.enter(Vector3(-82.0, 0.0, 8.0))
	main.player.dead = true
	main.player.cam.position = Vector3(-82.0, 1.55, 8.0)
	main.player.cam.rotation = Vector3(0.226, -1.192 + PI, 0)
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_dam_new3.png")
	main.player.dead = false
	#      new4 游客中心——西侧 (70,46) 朝 +X 瞄门厅+南广场（通高玻璃门厅+石阶+
	#      旗杆列+二层白墙横带窗，对位 visitor.jpg L 形玻璃楼前广场视角）
	main.player.enter(Vector3(70.0, 0.0, 46.0))
	main.player.dead = true
	main.player.cam.position = Vector3(70.0, 1.55, 46.0)
	main.player.cam.rotation = Vector3(0.1507, 1.695 + PI, 0)
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_dam_new4.png")
	main.player.dead = false

	main._enter_range()
	await frames(40)
	shot("res://out/shot_range.png")

	# ---- 靶场暂停菜单（模式分化图证）：进靶场按 Esc 开菜单截整屏——
	#      「靶场暂停」标题 +「1 重开靶场 / 2 离开靶场（回大厅）」两项，
	#      无「行动/战斗/放弃」字样；keep_menu 直拍（不收菜单护栏）
	main.paused = true
	main.hud.show_menu()
	await frames(4)
	shot("res://out/shot_range_menu.png", true)
	check("靶场菜单标题就位", main.hud._menu_title.text == "靶场暂停",
		"title=%s" % main.hud._menu_title.text)
	main.hud.hide_menu()
	main.paused = false

	# ---- 附加验收 6：shot_ads —— 靶场装红点镜开镜，专验渐晕「边上与四角
	# 暗度一致、无重叠更黑」。开镜动作 hd_scope 实际绑定鼠标右键
	# （main._register_inputs），探针用 action_press 直推动作层，不依赖物理键
	if not main.stash.scopes_owned.has("reddot"):
		main.stash.scopes_owned.append("reddot")   # 冷启动仓库无镜：先拥有再装配（幂等防重复）
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

	# ---- 附加验收 6b：shot_reddot_hip / shot_reddot_ads —— 红点镜大窗两连拍：
	# 腰射看 60×45mm 大窗造型（底托/窄边/投射器/风偏塔比例跟进）；开镜到位看
	# HUD 中心红点落进玻璃窗内居中（ADS 摆位已改「窗中心过屏幕中心」）
	await wait_until(func(): return main.player.ads <= 0.01)   # 彻底收镜再拍腰射
	await frames(2)
	shot("res://out/shot_reddot_hip.png")
	Input.action_press("hd_scope")
	check("大窗开镜到位 ads=1", await wait_until(func(): return main.player.ads >= 1.0))
	await frames(4)
	shot("res://out/shot_reddot_ads.png")
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

	# ---- 附加验收 9~17：九把新枪逐把腰射（shot_gun_<id>.png）——
	# 探针直拥不走现金（guns_owned.append），不污染经济断言；
	# 设主武器再进靶场截腰射照，验收员按 features 清单逐张判造型
	for gid in ["mp5", "p90", "uzi", "vector", "m4a1", "akm", "scarh", "mk4", "m250"]:
		if not main.stash.guns_owned.has(gid):
			main.stash.guns_owned.append(gid)
		main.stash.loadout = {"primary": gid, "secondary": "pistol"}
		main._enter_range()
		await frames(40)
		main.player.recoil_pitch = 0.0
		main.player.recoil_yaw = 0.0
		await frames(2)
		shot("res://out/shot_gun_%s.png" % gid)

	# ---- 附加验收 18：shot_slot_switch —— 双槽串色验收（黄壳回归红线）：
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

	# ---- 附加验收 19：shot_ammo_shop —— 大厅出发页弹药行特写（极致备弹经济）：
	# 光标落当页第一把候选枪行 → 侧栏速览联动，金色「极致备弹 余 N 发 · 买弹按 3 进交易行」
	# 只读行（购买入口在交易行③区：B 换挡 / 空格 /「购 N 发」钮在③区内生效，见下几张）
	main.stash.cash = 20000   # 摆拍现金（收尾还原真实存档）
	check("弹药经济首读送满额礼物", main.stash.ammo_of("mp5") == int(HDData.RESERVE["mp5"]),
		"mp5=%d" % main.stash.ammo_of("mp5"))
	main.lobby.set_tab(0)
	main.lobby._cur0 = 2   # 光标落当页第一把候选枪行（速览随动显示该枪弹药行）
	main.lobby.show_lobby()
	await frames(8)
	shot("res://out/shot_ammo_shop.png")
	main.lobby.hide_lobby()

	# ---- 附加验收 20：shot_bench —— 改枪台页全景（去购买跳转 + 当前装配摘要图证）：
	# 选中 M7（表序 2，非自带镜枪），右列 6 档瞄具逐行核对——未拥有者
	# （全息/3.5×/5×/热成像）=「去购买」钮（一键跳交易行②区，见 _goto_market_scope）；
	# 已拥有且已装的红点镜=「已装」置灰、机瞄=「卸下」（装配功能保留）；右列底部
	# 「当前装配」摘要面板（枪名+当前镜+已拥有 n/5+单持说明）；顶栏现金 ₵20,000 同框
	main.stash.cash = 20000   # 摆拍现金（收尾还原真实存档）
	main.lobby.set_tab(1)     # 新页签：0 出发大厅 / 1 改枪台 / 2 交易行
	main.lobby._gun_idx = 2   # M7 战斗步枪（附加验收 6 已给 rifle 装红点）
	main.lobby.show_lobby()
	await frames(8)
	shot("res://out/shot_bench.png")
	main.lobby.hide_lobby()

	# ---- 附加验收 21：shot_market —— 交易行页全景（全游戏唯一购买入口）：
	# 四段分区同框——① 枪械全表（未拥有「₵N+购买」/已拥有置灰）· ② 瞄具 6 档
	# · ③ 极致备弹（③ 徽章标题 + 挡位指示 + 选枪 + B 换挡 + 购 N 发）
	# · ④ 仓库·战利品条（底部通栏，冷启动空仓态）+ 顶栏现金 ₵20,000
	if main.stash.guns_owned.has("mp5"):
		main.stash.guns_owned.erase("mp5")   # 摆拍未拥有态（前面枪照段落已把 MP5 直拥）
	main.lobby.set_tab(2)        # 交易行=新页签 2
	main.lobby.show_lobby()
	await frames(8)
	shot("res://out/shot_market.png")

	# ---- 附加验收 22：shot_market_buy —— 特写：光标选中未拥有枪（MP5 ₵1,200），
	# 行高亮 + 行内「购买」钮高亮；只选中不确认，不实际成交
	main.lobby._market_sec = 0
	main.lobby._market_gun = 6   # GUNS 表序 6 = MP5
	main.lobby.set_tab(2)        # 同页签重刷，光标落 MP5 行
	await frames(8)
	shot("res://out/shot_market_buy.png")

	# ---- 附加验收 23：shot_market_warehouse —— 交易行④ 仓库·战利品段图证：
	# 种 3 件战利品 → 光标切④段（段面板高亮）· 两行滚动窗口（件数超窗竖向滚轮翻看）
	# · 总资产/「仓库 N/12 格」脚注 +「Enter 一键变卖全部」钮
	main.stash.items.append({"uid": "probe_wh_a", "name": "军用电池", "icon": "电源",
		"rarity": 2, "value": 620})
	main.stash.items.append({"uid": "probe_wh_b", "name": "机密文件", "icon": "机密",
		"rarity": 5, "value": 4200})
	main.stash.items.append({"uid": "probe_wh_c", "name": "金条", "icon": "贵金属",
		"rarity": 4, "value": 3100})
	main.lobby._market_sec = 3
	main.lobby.set_tab(2)        # 重刷，④段面板高亮 + 仓库条就位
	await frames(8)
	shot("res://out/shot_market_warehouse.png")
	main.lobby.hide_lobby()

	# ---- 附加验收 26：shot_lean —— 右探头（E）：地平线左高右低 + 相机右移
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(20)
	Input.action_press("hd_lean_right")
	await frames(14)
	check("探头截图帧 lean_cur>0.9", main.player.lean_cur > 0.9,
		"lean=%.2f" % main.player.lean_cur)
	shot("res://out/shot_lean.png")
	Input.action_release("hd_lean_right")
	await frames(4)

	print("[probe] 探针完成：实存 %d/40 张 → res://out/  （断言 %d 项 / 失败 %d）" % [shots_saved, checks, fails])
	# 收尾还原真实存档：探针内装配瞄具触发过 stash.save()，不能留在用户档里
	var gp := ProjectSettings.globalize_path(save)
	DirAccess.remove_absolute(gp)
	if save_bak != "":
		DirAccess.rename_absolute(save_bak, gp)
	main.free()
	quit(0)
