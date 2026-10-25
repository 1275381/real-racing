# 画面探针（窗口模式出图，headless 兼容跑断言）：大厅 → 行动出生点 → 远景士兵
# → 中心危险区 → 靶馆——五张基础截图 + 附加验收：开镜渐晕 → 红点镜大窗两连拍
# （shot_reddot_hip 腰射大窗造型 / shot_reddot_ads 开镜红点居窗）→ 换弹手部 →
# 汤姆逊腰射 → 十三把新枪逐把腰射（shot_gun_mp5/p90/uzi/vector/m4a1/akm/scarh/
# mk4/m250/mp7/m14/asval/k416.png）→
# 双槽切枪串色验收（shot_slot_switch.png）→ 大厅弹药行特写（只读）→
# 大厅三页整页（shot_page_depart 出发大厅 / shot_page_bench 改枪台·选中枪+已拥有未装镜
# 让「换装」钮可见 / shot_page_market 交易行四段分区全貌）→
# 改枪台去购买跳转+当前装配摘要图证（shot_bench.png）→ 交易行四段全景（shot_market.png）→
# 交易行未拥有枪购买特写（shot_market_buy.png）→ 交易行④ 仓库·战利品段图证
# （shot_market_warehouse.png：段选中态+两行滚动窗口+「Enter 一键变卖全部」钮）→
# 点击=装备两图证（shot_click_equip 出发页合成左键点击装枪后整页：行内「已装备」置灰钮
# +副槽卡换枪 / shot_click_bench 改枪台合成左键点击换镜后整页：「已装」钮+当前装配摘要）→
# 三角洲式 3D 出发大厅三连拍（shot_lobby_scene 默认大厅全景：3D 机库+干员持当前配枪
# / shot_lobby_scene_market 左下面板组战利品入库态 / shot_lobby_scene_swap
# 换主武器后干员手持变化对比）→
# 大坝分区四连拍
# （shot_dam_far 坝全景剪影 / shot_dam_base 坝底工业区街景 / shot_dam_graffiti 涂鸦环近景
# / shot_dam_ref 对位相机主图——后撤高机位纯净全景（无 HUD/枪模）：山脊+坝面
# +下幅工业区（厂房/集装箱/白罐/烟柱/棕榈），对位目标图四层构图）→
# 四新区五连拍（shot_dam_overview 后撤高机位全图纯净全景 + shot_dam_new1..4
# 军营/大电/水泥厂/游客中心走位近中景，与 barracks/substation/cement/visitor
# 参考图逐张对照形状语言）→
# 实战/靶场入口可辨（shot_entries 出发大厅整页：红橙实战 CTA 与绿色靶场入口同框）+
# 靶场暂停菜单（shot_range_menu：靶场暂停/离开靶场，模式分化文案图证）
# + 贴掩体枪模可读两连拍（shot_gun_cover_all mp7 贴靶场隔断墙 /
# shot_gun_cover_glass rifle 贴同墙——诊断定罪普通掩体即触发、全图无低可达
# 透明掩体，B 按方换枪不换掩体；站位照 /tmp/probe_split.gd 场景 A）
# → 贴掩体位姿矩阵十二场景（2026-10 第三轮「补光域隔离」根治回归，诊断 v1/v6
# 矩阵固化：shot_cover_hip 腰射基线·pair / shot_cover_ads_t04 ADS 0.40 冻结档
# ·pair / shot_cover_ads_full ADS 1.0·pair / shot_cover_lean_l·lean_r 探头 /
# shot_cover_fire_ads 开火火光帧 / shot_cover_reload_mid 换弹 0.55·pair /
# shot_cover_glass_ads 幕墙对照 / shot_cover_strafe_s06 真横移第 6 帧 /
# shot_cover_m250_ads 长枪 ADS / shot_gun_m14_cover 商店枪 M14 贴墙 /
# shot_gun_asval_cover 商店枪 AS Val 贴墙 / shot_gun_k416_cover 商店枪
# K416 贴墙——①②③⑦⑪⑫⑬ 各带 _b 图，两组 a/b 隐枪差分取稳定交集判裂，
# 修后门槛全部「稳定完整（大域 1）」；
# m14 贴掩体 pair 直接回应「注意枪身分裂」：一体成型+独立视口下掩体帧枪体必须完整）
# （共 85 张：55 处 shot() 调用（其中 8 处 pair 各出 a/_b 双图；
# 逐枪美照/scope 两组循环随迭代展开 19+6 张）+
# 逐枪美照循环 19 把（全量在册：十四把新枪 + 旧五枪，2026-10 判图补图；
# K416/AN-94 并册追加）+ scope 瞄具系列 6 张（2026-10 判图补图）
# + 矩阵段 20 张（含 pair 的 _b 图）+ 3D 大厅三连拍 3 张——旧注释
# 「29/31/33/35/40/43/45/59/70/73/76/79 张」随图集扩充滚动订正；
#  腰射/换弹手部/逐枪美照/切枪/探头各段姿势即肩射位——胸前提枪已移除）
# 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s res://scripts/probe_shot.gd
# headless 下（集成门槛跑法）无渲染目标：跳过保存只跑断言，进程照常 quit 不挂起
# 墙钟看门狗 300s（健康全程 ≈92s）：卡死自行还原存档 quit(1)，不留无输出 124 强杀
# 存档自愈：启动时若见 .probe_bak（上次被强杀未还原）先复位再备份，防真实档被顶掉
extends SceneTree

var checks: int = 0     # 附加验收断言计数（软断言：只记档打印，不中断后续截图）
var fails: int = 0
var shots_saved: int = 0   # 实存截图数（headless 下跳过保存，只跑断言链）
var save_bak := ""      # 非空 = 探针前有真实存档，收尾还原（探针装瞄具会触发 save()）
var _m                  # main 引用（shot() 收暂停菜单护栏用，_initialize 里赋值）
var _done := false      # 收尾旗：看门狗据此不误杀正常收尾
const WATCHDOG_SEC := 300.0   # 全程墙钟上限（健康全程 ≈92s，5 倍冗余）——
                              # 卡死时自行收尾还原存档并 quit(1)，不留给
                              # harness 超时强杀（强杀会孤儿化 probe_bak，
                              # 2026-10-18 10:04 实证）

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
## keep_menu=true 例外：拍的就是暂停菜单本身（shot_range_menu）。
## pair=true（2026-10 位姿矩阵回归锁）：拍 a 后隐全部 viewmodel 渲 2 帧拍
## b 再恢复——两组 a/b 差分取稳定交集判裂（stable_split）。visible 切换
## 帧内【禁止】驱动 player/guns update：位姿前进会把「枪+光晕位移」伪报
## 成裂（诊断 v4 事故），pair 全程只 await 渲染帧、零 update 调用
func shot(path: String, keep_menu := false, pair := false) -> void:
	if not keep_menu and _m != null and _m.hud != null and _m.hud.menu_visible:
		_m.hud.hide_menu()
	if pair:
		await _shot_pair(path)
		return
	if root.get_texture() == null:
		print("[probe] 跳过截图 %s（headless 无渲染目标）" % path)
		return
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("[probe] 跳过截图 %s（headless 渲染目标无图像）" % path)
		return
	img.save_png(path)
	shots_saved += 1


## 隐/显全部 viewmodel（两槽枪架 + 换弹手 + 掉落匣替身——后两者与枪架
## 父子不同但同属枪域，留着会在 b 图里污染差分域），返回原态列表供恢复
func _vm_set_vis(vis: bool) -> Array:
	var olds: Array = []
	if _m == null:
		return olds
	for slot_v in _m.guns._guns:
		var h: Node3D = _m.guns._guns[slot_v]["holder"]
		olds.append([h, h.visible])
		h.visible = vis
	if _m.guns._hand != null:
		var hd_v: Node3D = _m.guns._hand
		olds.append([hd_v, hd_v.visible])
		hd_v.visible = vis
	if _m.guns._falling_mag != null:
		var fm_v: MeshInstance3D = _m.guns._falling_mag
		olds.append([fm_v, fm_v.visible])
		fm_v.visible = vis
	return olds


func _vm_restore(olds: Array) -> void:
	for e_v in olds:
		var e: Array = e_v
		(e[0] as Node3D).visible = bool(e[1])


## 位姿冻结的一组 a/b（a 已由调用方拍好）：隐枪 → 渲 2 帧拍 b → 恢复。
## 照诊断 /tmp/probe_iso2.gd ab() 协议；渲染帧期间零驱动（防位姿前进伪报）
func _ab_once() -> Image:
	var olds := _vm_set_vis(false)
	await frames(2)
	var ib: Image = null
	if root.get_texture() != null:
		ib = root.get_texture().get_image()
	_vm_restore(olds)
	await frames(2)
	return ib


## 差分掩码（降采样 2x，iso2 同参数 thr=0.08：RGB 差和阈值）——2026-10
## 判图收敛降阈值：材质收敛把枪身压暗后，暗部枪像素 vs 馆内灰墙的色差
## 落到 0.08~0.15 区间，0.15 阈值把同一把枪的差分域拦腰断成两块、BFS
## 误报「稳定判裂」（贴墙三案 pair 全中）；0.08 让枪域连通，SSAO 帧间
## 噪声幅度低于 0.08 且仍被两组 a/b 稳定交集滤掉，判据语义不变
func _diff_mask(ia: Image, ib: Image, thr := 0.08) -> Dictionary:
	var sw := ia.get_width() / 2
	var sh := ia.get_height() / 2
	var mask := PackedByteArray()
	mask.resize(sw * sh)
	for y in sh:
		for x in sw:
			var ca := ia.get_pixel(x * 2, y * 2)
			var cb := ib.get_pixel(x * 2, y * 2)
			var d: float = absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			mask[y * sw + x] = 1 if d > thr else 0
	return {"mask": mask, "sw": sw, "sh": sh}


## 连通域 BFS（4 邻接；≥400 像素算「大域」——枪身尺度，SSAO 碎噪到不了）
func _bfs(mask: PackedByteArray, sw: int, sh: int) -> Dictionary:
	var label := PackedInt32Array()
	label.resize(sw * sh)
	var sizes := {}
	var cur := 0
	var stack: Array = []
	for i0 in sw * sh:
		if mask[i0] == 1 and label[i0] == 0:
			cur += 1
			var sz := 0
			stack.clear()
			stack.append(i0)
			label[i0] = cur
			while not stack.is_empty():
				var q: int = stack.pop_back()
				var qx := q % sw
				sz += 1
				if qx > 0 and mask[q - 1] == 1 and label[q - 1] == 0:
					label[q - 1] = cur
					stack.append(q - 1)
				if qx < sw - 1 and mask[q + 1] == 1 and label[q + 1] == 0:
					label[q + 1] = cur
					stack.append(q + 1)
				if q - sw >= 0 and mask[q - sw] == 1 and label[q - sw] == 0:
					label[q - sw] = cur
					stack.append(q - sw)
				if q + sw < sw * sh and mask[q + sw] == 1 and label[q + sw] == 0:
					label[q + sw] = cur
					stack.append(q + sw)
			sizes[cur] = sz
	var big: Array = []
	for k in sizes:
		if sizes[k] >= 400:
			big.append(sizes[k])
	big.sort()
	big.reverse()
	return {"n": big.size(), "sizes": big}


## pair 模式主体：a 图=主图落盘 + b 图落盘供肉眼复核；两组差分取稳定交集
## （SSAO 帧间噪声两组相位不同、交集滤掉；真几何边界两次一致、保留），
## 大域 ≥2 =「稳定裂」——对照诊断 E8 判据「稳定完整（大域 1）」
func _shot_pair(path: String) -> void:
	if root.get_texture() == null:
		print("[probe] 跳过 pair %s（headless 无渲染目标）" % path)
		return
	var ia1: Image = root.get_texture().get_image()
	if ia1 == null:
		return
	# 枪域剪影：vm 独立视口清屏透明，alpha 就是枪模真实轮廓（拍 a 的同帧取）
	var va: Image = null
	if _m != null and _m.player.vm_viewport != null:
		va = _m.player.vm_viewport.get_texture().get_image()
	var tag: String = path.get_file().get_basename()
	ia1.save_png(path)
	shots_saved += 1
	var ib1 := await _ab_once()
	if ib1 != null:
		ib1.save_png(path.replace(".png", "_b.png"))
		shots_saved += 1
	var m1: Dictionary = _diff_mask(ia1, ib1) if ib1 != null else {}
	# 组2：位姿不变再来一组（SSAO 换相位），只算差分不落盘
	var ia2: Image = root.get_texture().get_image()
	var ib2 := await _ab_once()
	var m2: Dictionary = _diff_mask(ia2, ib2) if (ia2 != null and ib2 != null) else {}
	if m1.is_empty() or m2.is_empty():
		print("[probe] 跳过判裂 %s（headless 渲染目标无图像）" % tag)
		return
	var mx: PackedByteArray = m1["mask"]
	var my: PackedByteArray = m2["mask"]
	var inter := mx.duplicate()
	for i in mx.size():
		inter[i] = 1 if (mx[i] == 1 and my[i] == 1) else 0
	# 差分只认枪剪影（外扩 2 像素）以内：写实枪模金属高光的辉光光晕会在枪周围
	# 地面/墙面上抬亮度 0.03/通道，0.08 阈值把整片地板圈进差分、再被灯带切成
	# 几块——2026-10 MP7 ADS 0.40 帧「稳定判裂 [34238,2217,912,548]」实为光晕
	# 误报（肉眼与剪影都是完整一把枪）。剪影外的差分一律不计
	if va != null:
		var sw: int = m1["sw"]
		var sh: int = m1["sh"]
		var vw := va.get_width()
		var vh := va.get_height()
		for y in sh:
			for x in sw:
				var i2 := y * sw + x
				if inter[i2] == 0:
					continue
				var hit := false
				for oy in [-2, 0, 2]:
					for ox in [-2, 0, 2]:
						var px := clampi(int(float(x * 2 + ox) * vw / (sw * 2.0)), 0, vw - 1)
						var py := clampi(int(float(y * 2 + oy) * vh / (sh * 2.0)), 0, vh - 1)
						if va.get_pixel(px, py).a > 0.05:
							hit = true
							break
					if hit:
						break
				if not hit:
					inter[i2] = 0
	var res := _bfs(inter, m1["sw"], m1["sh"])
	var split: bool = res["n"] >= 2
	var msg: String
	if split:
		msg = "*** 稳定判裂 sizes=%s（看 _b.png 复核）***" % str(res["sizes"])
	else:
		msg = "稳定完整（大域 %d sizes=%s）" % [res["n"], str(res["sizes"])]
	check("pair 判裂 %s" % tag, not split, msg)


## 手动冻结摆枪到任意 ads 档（复刻 /tmp/probe_iso2.gd set_ads 与
## hd_guns.gd update 的摆位公式；不驱动 update=位姿严格冻结）——
## ADS 过渡中档（0.40~0.70）是 vm_fill 亮斑最活跃档，冻结法才能停在档内
func _set_ads_mx(a: float) -> void:
	var g: Dictionary = _m.guns._cur_gun()
	var holder: Node3D = g["holder"]
	_m.guns._ads = a
	_m.player.ads = a
	var ads_pos := Vector3(-HDGuns.GUN_SCALE * float(g["cx"]),
			-0.012 - HDGuns.GUN_SCALE * float(g["top"]), HDGuns.GUN_ADS_Z)
	if g.has("aim_y"):
		ads_pos = Vector3(0.0, -HDGuns.GUN_SCALE * float(g["aim_y"]),
				HDGuns.GUN_ADS_Z)
	holder.position = HDGuns.GUN_HIP_POS.lerp(ads_pos, a)
	holder.rotation_degrees = HDGuns.GUN_HIP_ROT.lerp(Vector3.ZERO, a)


## 手动驱动一帧（main 主循环已冻结：玩家+枪 update 各一步，照诊断
## /tmp/probe_matrix.gd drive() 协议——探头/ADS/换弹/横移的真 update 链）
func drive(n: int) -> void:
	for i in n:
		_m.player.update(0.016)
		_m.guns.update(0.016)
		await process_frame

## 墙钟看门狗（2026-10-18 10:04 卡死案）：探针健康全程 ≈92s，超过
## WATCHDOG_SEC 仍未收尾即认定卡死——打诊断行、还原存档、quit(1)。
## 让 harness 侧看到的是「有诊断的快速失败」而非「无输出的 124 强杀」
## （强杀走不到收尾还原，probe_bak 孤儿化，二次强杀顶掉真实存档）
func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + int(WATCHDOG_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(5.0).timeout
		if _done:
			return
	if _done:
		return
	print("[probe] 看门狗超时（%.0fs 未跑完）——强制收尾还原存档" % WATCHDOG_SEC)
	_restore_save()
	quit(1)


## 收尾存档还原（正常收尾与看门狗共用）：删摆拍档、探针前真实档还位
func _restore_save() -> void:
	var gp := ProjectSettings.globalize_path("user://huodai_save.json")
	if FileAccess.file_exists(gp):
		DirAccess.remove_absolute(gp)
	if save_bak != "":
		DirAccess.rename_absolute(save_bak, gp)


func _initialize() -> void:
	_watchdog()
	var save := "user://huodai_save.json"
	var gp0 := ProjectSettings.globalize_path(save)
	# 自愈（2026-10-18 10:04 harness 超时强杀实证）：bak 在 = 上一次探针没走
	# 收尾还原就死了，bak 里才是探针前真实档、当前文件可能是摆拍档——先复位
	# 再备份，否则连续两次强杀会把真实存档永久顶掉
	if FileAccess.file_exists(gp0 + ".probe_bak"):
		if FileAccess.file_exists(gp0):
			DirAccess.remove_absolute(gp0)
		DirAccess.rename_absolute(gp0 + ".probe_bak", gp0)
	if FileAccess.file_exists(save):
		save_bak = gp0 + ".probe_bak"
		if FileAccess.file_exists(save_bak):
			DirAccess.remove_absolute(save_bak)
		DirAccess.rename_absolute(gp0, save_bak)
	DirAccess.make_dir_recursive_absolute("res://out")
	var main = load("res://main.tscn").instantiate()
	_m = main
	root.add_child(main)
	print("[probe] 探针启动：存档已备份、main.tscn 已入树（卡死排查锚点）")
	await frames(30)
	main.stash.tutorial_done = true   # 摆拍不要首局引导卡遮左上角（新档默认会弹；stash 在 main 就绪后才有）
	# 大厅卡片实物图（2026-10）：离屏拍的枪械缩略图要真出图（headless 不出图，跳过）
	if DisplayServer.get_name() != "headless":
		var p_gid := str(main.stash.loadout.get("primary", "rifle"))
		var p_key := "g|%s|%s|%s" % [p_gid, str(main.stash.scope_fit.get(p_gid, "iron")),
				str(main.stash.suppressed(p_gid))]
		var got := await wait_until(func(): return main.lobby._thumbs.cached(p_key) != null, 600)
		check("大厅枪械实物图已出图（%s）" % p_gid, got)
		await frames(120)   # 其余卡片的图排队拍完再截大厅
	shot("res://out/shot_lobby.png")

	# ---- 大厅三页整页截图（三页签改造图证）：出发大厅 / 改枪台 / 交易行 ----
	shot("res://out/shot_page_depart.png")   # 默认页=出发大厅（收起态：3D 干员+出发栏+右下角「战备」贴图）
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
	# ---- 三角洲式 3D 出发大厅三连拍（2026-10 大厅改造图证）：默认大厅全景
	#      （3D 备战机库 + 干员持当前配枪 + 仓库/交易行面板组停靠左下角）→
	#      左下面板组带战利品入库态（「打开交易行面板停左下角」）→ 换一把主
	#      武器后干员手持变化对比（同机位，枪形随 loadout 重建）。
	#      摆拍改动（loadout/仓库件）拍完即还原——后续靶场段按 guns.enter(
	#      stash.loadout) 进场，配置被摆拍顶掉会把「两发后余弹 28」跑成别的枪
	var lo0: Dictionary = main.stash.loadout.duplicate()
	var items0: int = main.stash.items.size()
	await frames(8)
	shot("res://out/shot_lobby_scene.png")
	main.stash.items.append({"uid": "probe_lobby_a", "name": "军用电池", "icon": "电源",
		"rarity": 2, "value": 620})
	main.stash.items.append({"uid": "probe_lobby_b", "name": "机密文件", "icon": "机密",
		"rarity": 5, "value": 4200})
	main.lobby.set_tab(0)   # 重刷：左下面板组亮出入库条（④仓库 N 件 + 战利品格 + 变卖钮）
	await frames(8)
	shot("res://out/shot_lobby_scene_market.png")
	# ---- 战备面板展开态（2026-10 战备收拢图证）：点右下角「战备」/TAB 才展开
	#      本局装备槽卡 + 换枪条 + 速览；拍完收起还原主画面
	main.lobby._toggle_prep(true)
	await frames(8)
	shot("res://out/shot_lobby_prep.png")
	main.lobby._toggle_prep(false)
	await frames(2)
	var swap_gid := "scarh" if str(main.stash.loadout.get("primary", "")) != "scarh" else "m4a1"
	if not main.stash.guns_owned.has(swap_gid):
		main.stash.guns_owned.append(swap_gid)   # 摆拍直拥（收尾还原真实存档）
	main.lobby._slot_focus = "primary"
	main.lobby._load_gun(swap_gid)   # 换一把主武器：画面里的人当场换手持枪
	check("大厅换枪手持已重建（%s）" % swap_gid,
		main.lobby_scene.held_gun_id == swap_gid,
		"held=%s" % main.lobby_scene.held_gun_id)
	await frames(8)
	shot("res://out/shot_lobby_scene_swap.png")
	# ---- 合同卡图证（2026-10「更好玩」阶段 A）：出发页收起态左下列出今日
	#      3 张合同（标题/进度/奖金/状态）——出发前看目标
	main.lobby.set_tab(0)
	main.lobby._toggle_prep(false)
	await frames(8)
	shot("res://out/shot_contracts.png")
	# 还原摆拍：loadout 回原配置、两件摆拍战利品摘除（guns_owned 直拥件不摘
	# ——逐枪美照段落本就幂等 append，收尾存档还原兜底）
	main.stash.loadout = lo0
	while main.stash.items.size() > items0:
		main.stash.items.remove_at(main.stash.items.size() - 1)
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

	# ---- 第二张图「航天基地」切换五连拍（2026-10）：切图 → 俯视全景 + 代表区域
	#      特写×3（火箭灵魂地标/核心区五室/工业带）+ 切回 dam 一张 sanity。
	#      换图链与 main._start_mission 同款：world.set_map + locks/loot/soldiers 复位
	#      （同一 world 实例原地重建）；机位协议照 dam 段冻结摆拍（dead=true 冻
	#      玩家 update、cam 手动定格、player.pos 挪 mid 区熄红罩——space 的 center/
	#      dam 分区=核心区+发射坪/工业带+中控楼，站位都在 mid）。
	main._raid_live = false   # 摆拍换图不算放弃行动（不丢装备）
	main.world.set_map("space")
	main.locks.apply_map("space")
	main.loot.rebuild_map()
	main.soldiers.rebuild()
	await frames(30)
	check("切图 space 挂载（航天整图在 world 下）",
		main.world.map_id == "space" and main.world.space_map != null
			and main.world.space_map.get_parent() == main.world,
		"map=%s" % main.world.map_id)

	# shot_space_overview：西北高机位 (-120,62,-30) 朝东南瞄 (0,10,80)——
	# 核心区围墙院居中、工业带右侧、正南火箭（61m 白箭体）中远景入画、
	# 北路/中控楼近景；yaw=atan2(120,110)=0.830、pitch=atan2(-52,162.8)=-0.309
	main.player.enter(Vector3(-120.0, 0.0, -30.0))
	main.player.dead = true
	main.player.cam.position = Vector3(-120.0, 62.0, -30.0)
	main.player.cam.rotation = Vector3(-0.309, 0.830 + PI, 0)
	main.player.cam.fov = 55.0
	var hud_sp: bool = main.hud.visible
	main.hud.visible = false
	var holder_sp := {}
	for slot_v in main.guns._guns:
		var g_sp: Dictionary = main.guns._guns[slot_v]
		holder_sp[slot_v] = g_sp["holder"].visible
		g_sp["holder"].visible = false
	main.player.pos = Vector3(0.0, 0.0, 58.0)
	await frames(8)
	shot("res://out/shot_space_overview.png")
	main.player.dead = false
	main.player.cam.fov = main.player.BASE_FOV
	main.hud.visible = hud_sp
	for slot_v in holder_sp:
		main.guns._guns[slot_v]["holder"].visible = holder_sp[slot_v]

	# shot_space_1：火箭灵魂地标特写——南路 (0,58) 朝正南仰看发射坪：
	# 火箭全高（发射座+白箭体+锥头+勤务塔摆杆）+ 发射坪导流槽前景
	main.player.enter(Vector3(0.0, 0.0, 58.0))
	main.player.dead = true
	main.player.cam.position = Vector3(0.0, 1.55, 58.0)
	main.player.cam.rotation = Vector3(0.538, PI, 0)
	main.player.pos = Vector3(0.0, 0.0, 58.0)
	await frames(8)
	shot("res://out/shot_space_1.png")
	main.player.dead = false

	# shot_space_2：核心区五室——南路 (0,50) 朝正北看围墙南门+中心花园+
	# 总裁室四层塔（左右浮力室/黑室山墙）
	main.player.enter(Vector3(0.0, 0.0, 50.0))
	main.player.dead = true
	main.player.cam.position = Vector3(0.0, 1.55, 50.0)
	main.player.cam.rotation = Vector3(0.128, PI + PI, 0)
	main.player.pos = Vector3(0.0, 0.0, 50.0)
	await frames(8)
	shot("res://out/shot_space_2.png")
	main.player.dead = false

	# shot_space_3：东侧工业带——东路 (48,-30) 朝东南瞄总装主厂房西立面
	# （双卷帘门+monitor 屋面+吊装跨），打印室/管廊入画
	main.player.enter(Vector3(48.0, 0.0, -30.0))
	main.player.dead = true
	main.player.cam.position = Vector3(48.0, 1.55, -30.0)
	main.player.cam.rotation = Vector3(0.183, 1.796 + PI, 0)
	main.player.pos = Vector3(48.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_space_3.png")
	main.player.dead = false

	# shot_space_4：北部控制点——北路 (0,-104) 朝正南看中控楼（三层窗带+
	# 楼顶天线阵）+ 中控桥跨水道（守桥人对枪点）
	main.player.enter(Vector3(0.0, 0.0, -104.0))
	main.player.dead = true
	main.player.cam.position = Vector3(0.0, 1.55, -104.0)
	main.player.cam.rotation = Vector3(0.146, PI, 0)
	main.player.pos = Vector3(0.0, 0.0, -104.0)
	await frames(8)
	shot("res://out/shot_space_4.png")
	main.player.dead = false

	# 切回 dam sanity：完整复位链走一遍再拍一张坝全景（与 shot_dam_overview 同机位）
	main.world.set_map("dam")
	main.locks.apply_map("dam")
	main.loot.rebuild_map()
	main.soldiers.rebuild()
	await frames(20)
	check("切回 dam 往返（坝三件重挂+锁房三间）",
		main.world.map_id == "dam" and main.world.dam != null
			and main.world.dam_base != null and main.world.dam_zones != null
			and main.world.space_map == null and main.locks._states.size() == 3)
	main.player.enter(Vector3(-96.0, 0.0, 116.0))
	main.player.dead = true
	main.player.cam.position = Vector3(-96.0, 58.0, 116.0)
	main.player.cam.rotation = Vector3(-0.2667, 2.5899 + PI, 0)
	main.player.cam.fov = 55.0
	var hud_bd: bool = main.hud.visible
	main.hud.visible = false
	var holder_bd := {}
	for slot_v in main.guns._guns:
		var g_bd: Dictionary = main.guns._guns[slot_v]
		holder_bd[slot_v] = g_bd["holder"].visible
		g_bd["holder"].visible = false
	main.player.pos = Vector3(90.0, 0.0, -30.0)
	await frames(8)
	shot("res://out/shot_space_back_dam.png")
	main.player.dead = false
	main.player.cam.fov = main.player.BASE_FOV
	main.hud.visible = hud_bd
	for slot_v in holder_bd:
		main.guns._guns[slot_v]["holder"].visible = holder_bd[slot_v]

	# 摆拍局不是真实对局：先置「已结算」再转靶场——2026-10 起局内转靶场 = 放弃
	# 行动视同阵亡（丢主副武器），不置位会把 rifle 丢掉、主槽退成侦察手枪
	# （下文「两发后余弹 28」读到手枪 12 发匣 → ammo=10 的根因）
	main._raid_live = false
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

	# ---- 附加验收 9~18：十九把在册枪逐把腰射（shot_gun_<id>.png）——
	# 探针直拥不走现金（guns_owned.append），不污染经济断言；
	# 设主武器再进靶场截腰射照，验收员按 features 清单逐张判造型。
	# 2026-10 判图补图：循环从十把新枪扩到全量在册（旧五枪
	# pistol/smg/rifle/shotgun/sniper 并入 + 商店枪 M14/AS Val 并册——此前枪照
	# 缺图无法验收）；2026-10 商店枪 K416 并册追加；2026-10 商店枪 AN-94
	# 并册追加（S12 微光赛季超点射新枪）
	for gid in ["mp5", "p90", "uzi", "vector", "m4a1", "akm", "scarh", "mk4",
			"m250", "mp7", "m14", "asval", "k416", "an94", "pistol", "smg",
			"rifle", "shotgun", "sniper"]:
		if not main.stash.guns_owned.has(gid):
			main.stash.guns_owned.append(gid)
		main.stash.loadout = {"primary": gid, "secondary": "pistol"}
		main._enter_range()
		await frames(40)
		main.player.recoil_pitch = 0.0
		main.player.recoil_yaw = 0.0
		await frames(2)
		shot("res://out/shot_gun_%s.png" % gid)

	# ---- 附加验收 18a：shot_scope_* 瞄具装枪图证六连拍（2026-10 判图
	# 补图：scope 系列此前整组缺图）——六种瞄具风格各一张 ADS 到位特写：
	# iron 机瞄（rifle）/ reddot 红点（rifle）/ holo 全息（rifle）/
	# optic 3.5×（rifle）/ sniper 自带密位镜（sniper 原厂，不装镜）/
	# thermal 热成像（sniper 挂镜）。装备→重挂（照 shot_ads 段拆旧挂新
	# 链）→ 开镜到位 → 拍 → 收镜
	for sc in [
			["iron", "rifle"], ["reddot", "rifle"], ["holo", "rifle"],
			["optic", "rifle"], ["sniper", "sniper"], ["thermal", "sniper"]]:
		var s_kind: String = sc[0]
		var s_gun: String = sc[1]
		# 先切 loadout 进场（_mount_slot 按 _slots id 造枪——不切枪会把
		# 镜装到上一把枪的槽位上，首拍全成 sniper 即此误）
		main.stash.loadout = {"primary": s_gun, "secondary": "pistol"}
		main._enter_range()
		await frames(20)
		if not main.stash.scopes_owned.has(s_kind):
			main.stash.scopes_owned.append(s_kind)
		if s_kind != "sniper":
			main.stash.equip_scope(s_gun, s_kind)
		else:
			main.stash.equip_scope(s_gun, "iron")   # 原厂镜枪：镜层走 builtin
		# 装镜不重挂：scope_provider 只在 _mount_slot 建枪模时读——
		# 装镜后拆旧挂新（照 shot_ads 段重挂链）
		var old_sc: Dictionary = main.guns._guns["primary"]
		var oldh: Node3D = old_sc["holder"]
		oldh.visible = false
		oldh.queue_free()
		(old_sc["flash"] as OmniLight3D).queue_free()
		main.guns._guns.erase("primary")
		main.guns._mount_slot("primary")
		main.guns._equip("primary")
		Input.action_press("hd_scope")
		check("scope %s 开镜到位" % s_kind,
			await wait_until(func(): return main.player.ads >= 1.0))
		await frames(4)
		shot("res://out/shot_scope_%s.png" % s_kind)
		Input.action_release("hd_scope")
		await wait_until(func(): return main.player.ads <= 0.4)
	# scope 段收尾：恢复 mp7 在枪（下段 shot_gun_cover_all 依赖「逐枪循环
	# 收尾正是 mp7」的摆位前提）；镜装配不还原（收尾存档还原兜底）
	main.stash.loadout = {"primary": "mp7", "secondary": "pistol"}
	main._enter_range()
	await frames(20)

	# ---- 附加验收 18b：shot_gun_cover_all / shot_gun_cover_glass —— 贴掩体
	# 枪模可读性图证（2026-10「贴掩体枪身分裂/吞枪」复发回归）：站位=地下
	# 靶馆射击位隔断墙（2026-10 判图迁移：HALL_CENTER=(120,130) 入地后地坪
	# -6.94，此前 598 地表机位实拍只剩天空雾——隔断墙 x=121.06 面 ±X、高
	# 1.2m，贴墙 0.64m）——cam(121.70,-5.39,143.0) yaw=PI 面 -Z 射击线；
	# set_indoor(true) 手动切馆内雾/环境光（冻结主循环后位置判定不跑）；
	# set_process(false) 冻结主循环防相机追尾 + 收 HUD。
	# A=shot_gun_cover_all：mp7 贴普通掩体（逐枪美照循环收尾正是 mp7 在
	# 枪上，直接摆位）。
	# B=shot_gun_cover_glass：按诊断定罪换枪不换掩体——B=rifle 贴同一面
	# 普通混凝土隔断墙（微自发光效力对照枪）。修复后两图枪身全段应均匀
	# 可读、无「前亮后黑两截」。
	main.set_process(false)
	var hud_cv: bool = main.hud.visible
	main.hud.visible = false
	main.world.set_indoor(true)
	main.player.cam.position = Vector3(121.70, -5.39, 145.0)
	main.player.cam.rotation = Vector3(-0.12, PI, 0)
	await frames(6)
	shot("res://out/shot_gun_cover_all.png")
	# B：换 rifle 重新进场贴同墙（loadout 换枪走 guns.enter 同槽换 id 重建链）
	main.set_process(true)
	main.stash.loadout = {"primary": "rifle", "secondary": "pistol"}
	main._enter_range()
	await frames(20)
	main.set_process(false)
	main.world.set_indoor(true)
	main.player.cam.position = Vector3(121.70, -5.39, 145.0)
	main.player.cam.rotation = Vector3(-0.12, PI, 0)
	await frames(6)
	shot("res://out/shot_gun_cover_glass.png")
	main.set_process(true)
	main.hud.visible = hud_cv
	main.world.set_indoor(false)

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

	# ---- 附加验收 24：shot_click_equip —— 「点击=装备」图证（出发页）：合成左键点击
	# 当页已拥有未装枪行 → 行高亮 + 行内钮转「已装备」置灰 + 副槽卡换枪
	# （等价 _on_equip_pressed 既有链；_slot_focus 指副槽，主槽 mk4 保持不动）
	main.lobby.show_lobby()
	main.lobby.set_tab(0)
	main.lobby._slot_focus = "secondary"
	main.lobby._deploy_page = 0
	main.lobby._cur0 = 0
	if not main.stash.guns_owned.has("rifle"):
		main.stash.guns_owned.append("rifle")   # 摆拍护栏：默认五枪已含，幂等
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.pressed = true
	mb.button_index = MOUSE_BUTTON_LEFT
	main.lobby._on_deploy_row_input(mb, 0, 4)   # 当页枪行序 4 → 表序 2 = M7 步枪
	await frames(8)
	shot("res://out/shot_click_equip.png")
	main.lobby.hide_lobby()

	# ---- 附加验收 25：shot_click_bench —— 「点击=装备」图证（改枪台）：合成左键点击
	# 右列已拥有未装镜行 → 行内钮转「已装」置灰 +「● 已装」tag + 底部「当前装配」摘要同步
	# （等价 _on_bench_equip_pressed 既有链：选中+换装一步到位）
	if not main.stash.scopes_owned.has("holo"):
		main.stash.scopes_owned.append("holo")   # 摆拍已拥有（收尾还原真实存档）
	main.lobby._gun_idx = 2     # M7 步枪（非自带镜，当前装红点=附加验收 6）
	main.lobby._bench_col = 1
	main.lobby._scope_idx = 0
	main.lobby.set_tab(1)
	main.lobby.show_lobby()
	var mb2: InputEventMouseButton = InputEventMouseButton.new()
	mb2.pressed = true
	mb2.button_index = MOUSE_BUTTON_LEFT
	main.lobby._on_bench_row_input(mb2, 1, 1)   # 右列序 1 = 全息镜（已拥有未装）
	await frames(8)
	shot("res://out/shot_click_bench.png")
	main.lobby.hide_lobby()

	# ---- 附加验收 26：shot_lean —— 右探头（E）：地平线左高右低 + 相机右移
	main._start_mission({"primary": "rifle", "secondary": "pistol"})
	await frames(20)
	Input.action_press("hd_lean_right")
	# 等到位再判（2026-10 改进方案第 8 节：修偶发失败 lean_cur 0.70 < 0.9）——
	# 旧版固定等 14 帧：主循环按真实帧时长推进 lean（6/s），高帧率机器 14 帧
	# 只有 0.1 s、lean 才 0.6–0.7。改成按条件等（上限 2 s，到不了照样判失败）
	for i in 240:
		if main.player.lean_cur > 0.9:
			break
		await frames(1)
	await frames(2)
	check("探头截图帧 lean_cur>0.9", main.player.lean_cur > 0.9,
		"lean=%.2f" % main.player.lean_cur)
	shot("res://out/shot_lean.png")
	Input.action_release("hd_lean_right")
	await frames(4)

	# ---- 附加验收 27：贴掩体「枪分裂」位姿矩阵（2026-10 第三轮根治回归，
	#      诊断 v1/v6 矩阵固化进本探针）——机位=坝底集装箱正贴（诊断实证
	#      触发面：枪口入掩体 0.4~0.7m × ADS 进出过渡 × 贴墙横移）+ 游客
	#      中心幕墙对照（2026-10 判图迁移：正贴机位由坝底集装箱位迁靶馆
	#      隔断墙 x=598.94——旧位掩体已随靶馆 (600,600) 迁移消失、背景穿帮）。
	#      协议：main.set_process(false) 冻结主循环 + 士兵
	#      挪出场外 + HUD 收起，位姿全部探针手动驱动（drive/_set_ads_mx）；
	#      ①②③⑦ 走 shot(pair)：两组 a/b 隐枪差分取稳定交集（stable_split，
	#      滤 SSAO 帧间噪声；visible 切换帧内零驱动防位姿前进伪报），其余
	#      单张图证。修后门槛：pair 全部「稳定完整（大域 1）」。
	main.stash.guns_owned.append("mp7")   # 摆拍直拥（幂等；收尾还原真实存档）
	main.stash.loadout = {"primary": "mp7", "secondary": "pistol"}
	main.set_process(false)   # 冻结主循环：防士兵 AI/红罩/相机追尾干扰（诊断协议）
	var hud_mx: bool = main.hud.visible
	main.hud.visible = false
	main._start_mission({"primary": "mp7", "secondary": "pistol"})
	await frames(8)
	for i in main.soldiers.soldiers.size():
		var sm: Dictionary = main.soldiers.soldiers[i]
		sm["pos"] = Vector3(0, 300, float(i) * 3.0)   # 挪出场外（iso2 协议）
		sm["engaged"] = false
		sm["moving"] = false
		sm["state"] = "combat"
		main.soldiers._write_pose(i)
	# 靶馆隔断墙正贴机位（2026-10 判图迁移：旧坝底位/598 地表位在靶馆
	# 入地后均已无掩体、实拍只剩天空雾——机位迁入地下馆贴 x=121.06 面
	# ±X 隔断墙、贴墙 0.64m，眼高地坪 -6.94+1.55，同 shot_gun_cover 段
	# 站位）：pos.y 交给 update 压回地坪、此后每场景重写 pos/yaw/pitch
	main.world.set_indoor(true)
	main.player.pos = Vector3(121.70, 1.55, 145.0)
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	await frames(4)
	# ① 腰射正贴（基线，pair）——pair 调用必须 await：shot(pair) 内部有
	#    隐枪/恢复的渲染帧等待，不 await 会与后续 _set_ads_mx/shot 并发交错
	#    （a 图抓到别的 pair 的隐枪帧、b 图抓到更早的腰射帧——2026-10 首跑
	#    ②③ 全空画面的根因）；非 pair 的 shot 保持同步调用零改动
	await shot("res://out/shot_cover_hip.png", false, true)
	# ② ADS 0.40 档（vm_fill 亮斑最活跃档，诊断 v6 裂档带中心）：手动冻结
	#    摆枪、零驱动停档（pair）——drive 会把 _ads 收走，冻结法才能停档内
	_set_ads_mx(0.40)
	await frames(2)
	await shot("res://out/shot_cover_ads_t04.png", false, true)
	# ③ ADS 1.0 正贴（pair，仍冻结摆法）
	_set_ads_mx(1.0)
	await frames(2)
	await shot("res://out/shot_cover_ads_full.png", false, true)
	# ④⑤ 探头（Q/E 按住真 update 链到 |lean_cur|>0.9；枪姿回腰射）
	_set_ads_mx(0.0)
	await drive(2)
	Input.action_press("hd_lean_left")
	await drive(16)
	check("矩阵左探头到位", main.player.lean_cur <= -0.9,
		"lean=%.2f" % main.player.lean_cur)
	shot("res://out/shot_cover_lean_l.png")
	Input.action_release("hd_lean_left")
	await drive(4)
	Input.action_press("hd_lean_right")
	await drive(16)
	check("矩阵右探头到位", main.player.lean_cur >= 0.9,
		"lean=%.2f" % main.player.lean_cur)
	shot("res://out/shot_cover_lean_r.png")
	Input.action_release("hd_lean_right")
	await drive(4)
	# ⑥ ADS 1.0 开火 1 帧（枪口火光 + vm_fill 同框；真 update 链开镜）
	Input.action_press("hd_scope")
	for i in 60:
		await drive(1)
		if main.player.ads >= 0.99:
			break
	main.guns.fire_cd = 0.0
	main.guns.try_fire()
	await drive(1)
	shot("res://out/shot_cover_fire_ads.png")
	Input.action_release("hd_scope")
	await drive(20)
	# ⑦ 换弹中段 prog≈0.55（旧匣脱手落地+手托新匣+枪体 26° 侧倾，pair）：
	#    R 边沿触发后 drive 逐帧推进（主循环已冻结，探针手动驱动）
	Input.action_press("hd_reload")
	await drive(1)
	Input.action_release("hd_reload")
	var rl_total: float = maxf(float(main.guns._g.get("reload", 1.5)), 0.01)
	for i in 200:
		await drive(1)
		if main.guns.reloading > 0.0 \
				and 1.0 - main.guns.reloading / rl_total >= 0.55:
			break
	var rl_prog: float = 1.0 - main.guns.reloading / rl_total
	check("换弹中段 prog≈0.55", main.guns.reloading > 0.0
		and absf(rl_prog - 0.55) < 0.06, "prog=%.2f" % rl_prog)
	await shot("res://out/shot_cover_reload_mid.png", false, true)
	for i in 200:   # 走完换弹再进下一场景（防弹匣/手部姿态泄漏进⑧）
		await drive(1)
		if main.guns.reloading <= 0.0:
			break
	# ⑧ 游客中心幕墙对照（诊断「透明掩体」位——实测材质不透明 metallic，
	#    普通触发面同验；冻结摆法）
	main.world.set_indoor(false)   # 幕墙=户外位：切回户外氛围
	main.player.pos = Vector3(88.0, 1.55, 43.15)
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	_set_ads_mx(1.0)
	await frames(2)
	shot("res://out/shot_cover_glass_ads.png")
	# ⑨ 真横移第 6 帧（ads=1.0 真链按住开镜，每帧 pos.x+=0.05 掩体缘扫过
	#    枪身——诊断「真移动 ADS 连拍」协议的固化第 6 帧）
	Input.action_press("hd_scope")
	for i in 60:
		await drive(1)
		if main.player.ads >= 0.99:
			break
	main.world.set_indoor(true)
	main.player.pos = Vector3(121.70, 1.55, 145.0)   # 回正贴机位再横移
	main.player.yaw = PI
	main.player.pitch = 0.0
	await drive(2)
	for i in 6:
		main.player.pos.x += 0.05   # 沿视线横向（x 向）扫过墙缘
		await drive(1)
	shot("res://out/shot_cover_strafe_s06.png")
	Input.action_release("hd_scope")
	await drive(20)
	# ⑩ m250 ADS 1.0（最长枪近剪裁/变换链抽查）：换枪重进 MISSION——
	#    guns.enter 同槽换 id 重建链，顺带在重建路径上复核 vm_fill 隔离在位
	main.stash.guns_owned.append("m250")   # 幂等直拥
	main.stash.loadout = {"primary": "m250", "secondary": "pistol"}
	main._start_mission({"primary": "m250", "secondary": "pistol"})
	await frames(8)
	for i in main.soldiers.soldiers.size():
		var sm2: Dictionary = main.soldiers.soldiers[i]
		sm2["pos"] = Vector3(0, 300, float(i) * 3.0)
		sm2["engaged"] = false
		sm2["moving"] = false
		sm2["state"] = "combat"
		main.soldiers._write_pose(i)
	main.player.pos = Vector3(121.70, 1.55, 145.0)
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	_set_ads_mx(1.0)
	await frames(2)
	shot("res://out/shot_cover_m250_ads.png")
	# ⑪ m14 ADS 1.0 正贴（2026-10 商店枪 M14 并册「注意枪身分裂」验收）：
	#    一体成型 unibody + vm 独立视口下掩体帧枪体必须完整——走 pair 判裂
	#    （两组 a/b 隐枪差分取稳定交集，大域 ≥2 = 稳定裂即 FAIL）；换枪重进
	#    MISSION 走 guns.enter 同槽换 id 重建链，顺带复核新枪挂载公共链
	main.stash.guns_owned.append("m14")   # 幂等直拥（收尾还原真实存档）
	main.stash.loadout = {"primary": "m14", "secondary": "pistol"}
	main._start_mission({"primary": "m14", "secondary": "pistol"})
	await frames(8)
	for i in main.soldiers.soldiers.size():
		var sm3: Dictionary = main.soldiers.soldiers[i]
		sm3["pos"] = Vector3(0, 300, float(i) * 3.0)   # 挪出场外（iso2 协议）
		sm3["engaged"] = false
		sm3["moving"] = false
		sm3["state"] = "combat"
		main.soldiers._write_pose(i)
	main.player.pos = Vector3(121.70, 1.55, 145.0)
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	_set_ads_mx(1.0)
	await frames(2)
	await shot("res://out/shot_gun_m14_cover.png", false, true)
	# ⑫ asval ADS 1.0 正贴（2026-10 商店枪 AS Val 并册「注意枪身分裂」验收）：
	#    一体成型 unibody + vm 独立视口下掩体帧枪体必须完整——一体消音管
	#    占全枪一半的长枪最考验掩体帧完整性，走 pair 判裂（两组 a/b 隐枪
	#    差分取稳定交集，大域 ≥2 = 稳定裂即 FAIL）；换枪重进 MISSION 走
	#    guns.enter 同槽换 id 重建链，顺带复核新枪挂载公共链
	main.stash.guns_owned.append("asval")   # 幂等直拥（收尾还原真实存档）
	main.stash.loadout = {"primary": "asval", "secondary": "pistol"}
	main._start_mission({"primary": "asval", "secondary": "pistol"})
	await frames(8)
	for i in main.soldiers.soldiers.size():
		var sm4: Dictionary = main.soldiers.soldiers[i]
		sm4["pos"] = Vector3(0, 300, float(i) * 3.0)   # 挪出场外（iso2 协议）
		sm4["engaged"] = false
		sm4["moving"] = false
		sm4["state"] = "combat"
		main.soldiers._write_pose(i)
	main.player.pos = Vector3(121.70, 1.55, 145.0)
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	_set_ads_mx(1.0)
	await frames(2)
	await shot("res://out/shot_gun_asval_cover.png", false, true)
	# ⑬ k416 ADS 1.0 正贴（2026-10 商店枪 K416 并册「验分裂」验收，照 m14/
	#    asval pair 模式）：一体成型 unibody + vm 独立视口下掩体帧枪体必须
	#    完整——走 pair 判裂（两组 a/b 隐枪差分取稳定交集，大域 ≥2 = 稳定裂
	#    即 FAIL）；换枪重进 MISSION 走 guns.enter 同槽换 id 重建链，顺带复核
	#    新枪挂载公共链
	main.stash.guns_owned.append("k416")   # 幂等直拥（收尾还原真实存档）
	main.stash.loadout = {"primary": "k416", "secondary": "pistol"}
	main._start_mission({"primary": "k416", "secondary": "pistol"})
	await frames(8)
	for i in main.soldiers.soldiers.size():
		var sm5: Dictionary = main.soldiers.soldiers[i]
		sm5["pos"] = Vector3(0, 300, float(i) * 3.0)   # 挪出场外（iso2 协议）
		sm5["engaged"] = false
		sm5["moving"] = false
		sm5["state"] = "combat"
		main.soldiers._write_pose(i)
	main.player.pos = Vector3(121.70, 1.55, 145.0)
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	_set_ads_mx(1.0)
	await frames(2)
	await shot("res://out/shot_gun_k416_cover.png", false, true)
	# ⑭ an94 ADS 1.0 正贴（2026-10 商店枪 AN-94 并册「验分裂」验收，照 m14/
	#     asval/k416 pair 模式）：一体成型 unibody + vm 独立视口下掩体帧枪体
	#     必须完整——大型双室制退器 + 星形表尺 + 右倾弧匣的识别件密度最高，
	#     最考验合并网格的掩体帧完整性，走 pair 判裂（两组 a/b 隐枪差分取
	#     稳定交集，大域 ≥2 = 稳定裂即 FAIL）；换枪重进 MISSION 走 guns.enter
	#     同槽换 id 重建链，顺带复核新枪挂载公共链
	main.stash.guns_owned.append("an94")   # 幂等直拥（收尾还原真实存档）
	main.stash.loadout = {"primary": "an94", "secondary": "pistol"}
	main._start_mission({"primary": "an94", "secondary": "pistol"})
	await frames(8)
	for i in main.soldiers.soldiers.size():
		var sm6: Dictionary = main.soldiers.soldiers[i]
		sm6["pos"] = Vector3(0, 300, float(i) * 3.0)   # 挪出场外（iso2 协议）
		sm6["engaged"] = false
		sm6["moving"] = false
		sm6["state"] = "combat"
		main.soldiers._write_pose(i)
	main.player.pos = Vector3(121.70, 1.55, 145.0)
	main.player.yaw = PI
	main.player.pitch = 0.0
	main.player.update(0.016)
	_set_ads_mx(1.0)
	await frames(2)
	await shot("res://out/shot_gun_an94_cover.png", false, true)
	main.world.set_indoor(false)   # 矩阵段收尾：恢复户外氛围
	# ---- 钥匙锁房图证（「更好玩」阶段 B）：军火库上锁红门 → 持钥匙 F 开锁
	#      （绿灯 + 门滑升 + 房内 safe/武器箱生成）
	main.player.pos = Vector3(-40.2, 1.55, -47.0)
	main.player.yaw = -PI / 2.0   # 面向 -x（军火库门朝 E；距房心 2.8m 交互半径内）
	main.player.pitch = -0.05
	main.player.update(0.016)
	await frames(6)
	await shot("res://out/shot_lock_door.png")
	main.loot.backpack.append({"uid": "key_probe", "name": "军火库钥匙",
		"icon": "钥匙", "rarity": 3, "value": 800, "key": "armory"})
	main.locks.update(0.016, main.player.pos, false)
	main.locks.update(0.016, main.player.pos, true)   # F 边沿开锁
	await frames(40)   # 门滑升 + 房内容器生成
	check("探针开锁成功（armory opened）", bool(main.locks._states["armory"]["opened"]))
	await shot("res://out/shot_lock_open.png")
	main.locks.reset_all()   # 还原上锁态（下一局照常重锁）
	# ---- 天气变体三连拍（「更好玩」阶段 C）：夜晚/雨天/浓雾玩家视角（雨含粒子）
	main.player.pos = Vector3(-24.0, 1.55, -36.0)   # 西仓库门前（沙袋+集装箱巷道视野）
	main.player.yaw = PI * 0.75
	main.player.pitch = -0.04
	main.player.update(0.016)
	for v_id in ["night", "rain", "fog"]:
		main.world.apply_variant(v_id)
		await frames(10)
		await shot("res://out/shot_variant_%s.png" % v_id)
	main.world.apply_variant("clear")
	await frames(4)
	# ---- 投掷物图证（「更好玩」阶段 D）：破片雷爆点 + 烟雾弹烟球
	main.player.yaw = PI / 2.0
	main.player.pitch = -0.12
	main.player.update(0.016)
	main.stash.throwables["frag"] = 3
	main.stash.throwables["smoke"] = 2
	main._route_key(KEY_7)
	for i in 26:
		main.thrower.update(0.06)   # ~1.6s：落地起爆火球展开中
	await frames(4)
	await shot("res://out/shot_throw_frag.png")
	main._route_key(KEY_8)
	for i in 26:
		main.thrower.update(0.06)
	await frames(4)
	await shot("res://out/shot_throw_smoke.png")
	main.thrower.reset_all()
	main.hud.flash_screen(0.0)
	# ---- 开局简报卡组图证（2026-10-24 用户定案）：右上角撤离/合同/风险小卡
	main.hud.show_briefing(main._briefing_cards())
	await frames(6)
	await shot("res://out/shot_briefing.png")
	main.hud.show_briefing([])
	# 矩阵段收尾：恢复主循环与 HUD（之后只剩探针收尾打印与存档还原）
	main.set_process(true)
	main.hud.visible = hud_mx

	print("[probe] 探针完成：实存 %d/85 张 → res://out/  （断言 %d 项 / 失败 %d）" % [shots_saved, checks, fails])
	# 收尾还原真实存档：探针内装配瞄具触发过 stash.save()，不能留在用户档里
	# （与看门狗强制收尾共用 _restore_save）
	_done = true
	_restore_save()
	main.free()
	quit(0)
