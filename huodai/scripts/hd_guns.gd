class_name HDGuns
extends Node3D
## 烽火地带枪械：双槽（primary/secondary）程序化拼枪 + ADS + 换弹（弹匣三段
## 掉落动画 + 程序化手套拔匣/插匣跟随）+ hitscan 结算。
## 输入动作名由 main 注册，本模块只读："hd_fire"/"hd_scope"/"hd_slot1"/
## "hd_slot2"/"hd_reload"。
## 枪模挂载（2026-10 架构定案）：不再挂主相机渲染进主世界，而是挂
## player.vm_cam——own_world_3d 独立视口（HDPlayer._build_vm 装配），vm 世界
## 零场景几何，枪与掩体的深度交互物理消失（贴掩体枪管穿墙叠画成两截、
## 透明掩体 transparent pass 整层盖枪，两条「分裂」病因同根除）。vm 相机
## 每帧同步主相机 transform/FOV（HDPlayer.sync_vm），故 holder 在 vm 世界
## 的 to_global 数值 == 主世界坐标——曳光起点/掉匣落点/换弹手锚全部零改动。
## 射线结算仍走主相机（player.cam.global_position/-basis.z），命中特效
## （曳光池/火花/掉落弹匣）留在主世界照常与世界交互。

signal fired
signal reloaded
signal jammed      # 耐久过低卡壳（第四阶段：枪械耐久）
signal hit_enemy(kind: String, idx: int, point: Vector3, dmg: float, head: bool)


const GUN_HIP_POS := Vector3(0.26, -0.22, -0.55)   # 腰射枪架位（onfoot 同款）
# ADS 沿轴端面视图收敛（2026-10 判图「贴掩体开镜枪模塌缩成小黑条」）：
# 物理深度下沿枪轴只能看到枪尾端面（几何事实），-0.45→-0.38 让端面投影
# 放大 ~18%、端面细节可辨；只动枪-相机距离这一个观感参数，握把锚对齐
# 体系（HOLD_DELTA）与镜窗对齐（aim_y）零改动
const GUN_ADS_Z := -0.38
const GUN_HIP_ROT := Vector3(2.5, 4.0, 3.0)
const GUN_SCALE := 0.62
const MAG_POS := Vector3(0.02, -0.14, -0.16)       # 枪上弹匣位（枪架局部）
const MUZZLE_OFF := Vector3(0.02, 0.06, -0.62)     # 枪口点（枪架局部，火光同位）
const HEADSHOT_MUL := 2.0                          # 爆头伤害倍率
const ADS_SPREAD := 0.1                            # 开镜散布倍率（onfoot 惯例）
const ADS_SPEED := 5.0
const MAG_REST_T := 4.0                            # 落地弹匣停留秒数（之后渐隐回收）
const HIDE_ZOOM := 3.0                             # 开镜倍率≥3 且到位 → 藏枪模
const RD_WIN_W := 0.06     # 红点镜玻璃窗宽（枪身局部 m）——无框反射式大窗
const RD_WIN_H := 0.045    # 红点镜玻璃窗高：窗顶=全镜最高件（_local_aabb 顶即窗顶）
const FIRE_GATE := 1e-6    # 开火门残差容差（秒）：60·cd 为整数帧的枪（如 vector
                           # 0.05=3 帧）IEEE 双精度 3f 与 cd 差 ~1e-18，曾把节拍
                           # 多推 1 帧（1200rpm 掉到 900）；容差远小于任何非整除
                           # 余量（最小 ~0.008），只吸收残差不偷跑
const BURST_SOFT_SHOTS := 2   # 射速档案（cd_profile）枪按压内「前两发」判定数：
                              # 超点射对射窗口（AN-94 现实 2 发点射管）
const BURST_SOFT_MUL := 0.35  # 超点射前两发后坐乘数（AN-94 延迟后坐的真实弹道
                              # 特征：钢制内机匣在聚合物外壳内后坐吸掉对射冲量，
                              # 扣扳机打出的头两发垂直跳动极小——三角洲爆料
                              # 「前两发射速极快、后坐力极低」同源）

## 换弹手部动画（reload 进度 prog 关键帧，照 _reload_off/_reload_rot 的插值
## 模式，不引入新状态机）：0.15-0.30 手入画伸匣 → 0.30-0.55 握匣下拉拔出
## → 0.55-0.75 托新匣上抬 → 0.75-0.85 对准插入拍合 → 0.85-0.97 离场回位。
## 偏移均为枪架局部（锚定枪上弹匣节点，to_global 转世界跟随枪体倾斜）
const HAND_IN_T := 0.15                            # 手开始入画伸向弹匣
const HAND_GRIP_T := 0.30                          # 到达弹匣（开始握匣下拉）
const HAND_OUT_T := 0.55                           # 旧匣拔出脱手（与掉落窗口对齐）
const HAND_NEW_T := 0.75                           # 新匣托举到弹匣井正下
const HAND_SEAT_T := 0.85                          # 插入拍合（与新匣滑入终点同步）
const HAND_HIDE_T := 0.97                          # 末段提前隐手（先于换弹结束）
const HAND_ENTRY_OFF := Vector3(0.06, -0.30, 0.14) # 入画起点（弹匣位右下、画面外）
const HAND_GRIP_OFF := Vector3(0.0, -0.055, 0.03)  # 握匣点（匣中偏下偏后）
const HAND_PULL_OFF := Vector3(0.015, -0.24, 0.10) # 拔出终点（向下抽出再甩开）
const HAND_HOLD_OFF := Vector3(0.0, -0.095, 0.03)  # 托新匣掌心（匣底正下）

## 胸前提枪姿态（已按用户要求整体移除：枪常驻肩射位，无胸前横端/横晃/双手）

## 每发后坐力（度）：[基础上抬, 连发累增系数, 水平漂移幅度]（onfoot 同表）。
## 2026-10 扩充七枪：vector 最柔（Super V 卖点）/ akm·scarh 大后坐（7.62 世界观）；
## mk4 同 mp5 档（4.6×30 低后坐轻弹，缺键会吃 [0.4,0.2,0.25] 兜底后坐爆炸）；
## m250 机枪（6.8×51 弹链）：机枪更沉档（比 lmg 略收——重枪管+消音器压制）；
## m14 全自动 DMR（7.62 NATO，2026-10-19 用户定案改全自动 730rpm）：高单发
## 后坐最沉档、水平漂移最窄
const RECOIL := {
	"pistol": [0.22, 0.14, 0.08],
	"smg": [0.13, 0.06, 0.09],
	"rifle": [0.17, 0.09, 0.10],
	"shotgun": [0.9, 0.0, 0.32],
	"sniper": [1.3, 0.0, 0.2],
	"lmg": [0.20, 0.08, 0.14],
	"uzi": [0.15, 0.07, 0.11],
	"mp5": [0.12, 0.05, 0.07],
	"p90": [0.11, 0.05, 0.08],
	"vector": [0.09, 0.03, 0.08],
	"m4a1": [0.16, 0.08, 0.09],
	"akm": [0.24, 0.12, 0.14],
	"scarh": [0.26, 0.13, 0.12],
	"mk4": [0.12, 0.05, 0.08],
	"m250": [0.16, 0.06, 0.10],
	"mp7": [0.10, 0.05, 0.07],
	# m14 大口径全自动（7.62 NATO DMR 高单发，2026-10-19 定案 730rpm）：
	# 单发推力比 scarh 更沉、水平漂移收窄（连发累增温和，精度优先）
	"m14": [0.30, 0.10, 0.06],
	# asval 亚音速重弹（9×39 低膛压 + 一体消音器，2026-10 定案 972rpm 连发
	# 快）：单发后坐温和（重弹比 5.56 沉、低膛压抵消——比 m4a1 略沉一档）、
	# 连发累增中等、水平漂移窄（消音特种枪精度定位）
	"asval": [0.18, 0.07, 0.08],
	# k416 5.56 步枪档（HK416 高射速 880rpm，2026-10 定案）：单发后坐 m4a1
	# 同族略沉一档（气体短行程活塞系统比直吹稳）、连发累增同 5.56 档、
	# 水平漂移窄（高射速枪横漂放大就压不住）
	"k416": [0.17, 0.08, 0.09],
	# an94 超点射 5.45 步枪（2026-10 商店枪，S12 微光赛季）：延迟后坐机制档
	# ——按压前两发由 try_fire 的 BURST_SOFT_MUL 软乘数吃掉大半垂直跳动
	# （带 cd_profile 才触发，真实弹道特征=后坐延迟到对射之后），基表给稳态
	# 600rpm 档：单发推力 5.45 轻弹 + 3.85kg 重枪体（比 k416 略沉）、连发
	# 累增温和、水平漂移窄（前两发高精度是本枪卖点）
	"an94": [0.19, 0.06, 0.09],
	# sr25 7.62 半自动 DMR（2026-10 商店枪，群星赛季）：单发推力全枪册
	# 最沉一档（7.62 NATO 重弹 + dmg 50 单发重击——比 m14 [0.30] 更沉，
	# 仅次于狙击栓动）；半自动 tap 门单发结算、无连发累增（累增系数只在
	# 按住连发时消费，auto=false 枪实际不触达）；水平漂移最窄同 m14
	# （DMR 精度定位，重枪体 + 浮置护木吸振）
	"sr25": [0.32, 0.10, 0.06],
}

var player           # HDPlayer（鸭子类型：读 cam/dead，写 recoil_pitch/recoil_yaw/ads/zoom）
var world            # 世界（鸭子类型：wall_hit / ground_height）
var audio            # HDAudio（play_shot/play_reload）
var tracers          # TracerPool 实例（main 创建传入，本模块 setup+tick）
var soldiers = null  # HDSoldiers 实例（main 注入）：raycast 用它的 battlefield 契约
var targets = null   # HDTargets 实例（main 注入）：命中时直接调 targets.on_hit(i) 倒靶计分
var scope_provider: Callable   # main 注入 func(gun_id)->Dictionary{"kind","zoom"}
var reserve_provider: Callable # main 注入 func(gun_id)->int：备弹弹药源（极致备弹经济，stash 库存）

var cur_id: String = ""
var ammo: int = 0
var reserve: int = 0
var reloading: float = 0.0

var _slots := {}        # "primary"/"secondary" -> {"id","ammo","reserve"}
var _cur_slot := ""
var _guns := {}         # slot -> {"id","holder","mag","show_mag","flash","flash_mesh","top","cx"}
var _g := {}            # 当前枪数值（Guns.gun_by_id）
var fire_cd := 0.0
var _aiming := false
var _ads := 0.0
var _reload_off := Vector3.ZERO     # 换弹动画的枪体偏移/倾斜
var _reload_rot := Vector3.ZERO
var _falling_mag: MeshInstance3D    # 掉落弹匣替身（主世界空间——落地后要与地面交互，留在主世界；queue_free 惰性重建）
var _hand: Node3D                   # 换弹手部替身（vm 相机子节点，与枪架同级同世界，仅换弹可见）
var _falling_vel := Vector3.ZERO
var _mag_scale := Vector3.ONE   # 掉落匣替身按枪种弹匣尺寸的缩放（渐隐时保持比例）
var _falling := false
var _mag_landed := false
var _mag_rest_t := 0.0
var _flash_t := 0.0
var _im_pool: Array = []   # 命中火花对象池 {mi, t}
var _im_i := 0
var _slot1_prev := false   # 切枪/换弹键边沿检测（只按 is_action_pressed）
var _slot2_prev := false
var _reload_prev := false
var _fire_prev := false    # 开火键边沿检测：半自动/栓动（表 auto=false）只认
                           # tap 边沿开火——按住不连发（假半自动根治）
var _press_shots := 0      # 本次扳机按压内已发数（cd_profile 射速档案的档位
                           # 索引；松开扳机/切枪/换弹归零——超点射「再按又是
                           # 新的一对」；不带档案的枪不消费此计数，零行为变化）
var _trig_delay := 0.0     # 扳机蓄力剩余秒（表 trigger_delay>0 的枪——M250 弹链
                           # 机枪 0.5s：按下先蓄力再出第一发，松开/切枪复位重蓄）
var _burst_left := 0       # 三连发剩余发数（表 burst>0 的枪——MK4：点一下边沿
                           # 起一个点射，打完为止；换弹/没弹/切枪中止，按住不重复）
var _burst_cd_ov := 0.0    # 配件覆写的轮内间隔秒（SR25 套件 burst_cd_to；0=无覆写）
var _kit_gap_ov := 0.0     # 配件覆写的轮间锁秒（SR25 套件 burst_gap_to；0=无覆写）
var _kit_cd_ov := 0.0      # 配件覆写的全自动节拍秒（SR25 套件 cd_to；0=无覆写）
var _kit_burst_mode := false  # SR25 套件开火模式（false=全自动缺省 / true=三连发，
                              # B 键切换——2026-10-26 用户三次定案）
var _burst_gap := 0.0      # 轮间锁剩余秒（表 burst_gap：点射打完后的强制间隔——
                           # 三角洲 MK4 实测 ~100ms，锁内起不了新点射）


func setup(player, world, audio, tracers) -> void:
	self.player = player
	self.world = world
	self.audio = audio
	self.tracers = tracers
	_setup_fx()
	_ensure_falling_mag()


## 进场：按 loadout 建两把枪模（常驻相机下，切枪只切可见性不重建）、装 primary。
## 弹匣仍免费给满；备弹不再免费送——改由弹药源（main 注入 reserve_provider →
## stash 极致备弹库存）提供，未注入回 0；局终 main 用 slot_snapshots() 回收
func enter(loadout: Dictionary) -> void:
	_save_cur()
	_slots = {}
	_cur_slot = ""
	cur_id = ""
	_g = {}
	ammo = 0
	reserve = 0
	reloading = 0.0
	fire_cd = 0.0
	_press_shots = 0   # 进场清零按压计数（cd_profile 射速档案档位）
	_trig_delay = 0.0  # 进场清零扳机蓄力（trigger_delay）
	_burst_left = 0    # 进场清零三连发计数（burst）
	_burst_gap = 0.0   # 进场清零轮间锁（burst_gap）
	_ads = 0.0
	_aiming = false
	_reload_off = Vector3.ZERO
	_reload_rot = Vector3.ZERO
	_falling = false
	_mag_landed = false
	_hide_hand()
	if tracers != null:
		tracers.hide_all()
	for s in _im_pool:
		s["t"] = 0.0
		s["mi"].visible = false
	if _falling_mag != null:
		_falling_mag.visible = false
	for slot in ["primary", "secondary"]:
		var gid: String = str(loadout.get(slot, ""))
		if gid == "":
			continue
		var gi: Dictionary = Guns.gun_by_id(gid)
		# M14 扩容匣进场直接按 30 满弹（_m14_mod 查 cur_id 之外还要认 gid——
		# 进场时 cur_id 还没设，这里直接查 provider）
		var cap0 := int(gi.get("mag", 12))
		if gid == "m14" and _m14_mod("extmag"):
			cap0 = 30
		# SR25 全自动套件 45 发专用长匣（2026-10-27 用户报告「开局只装 25 发」
		# 根因：cap0 只认 M14 扩容匣，套件 mag_to 没进进场装填——同样按 gid
		# 直查 provider，cur_id 此时未设）
		if gid == "sr25" and _m14_mod("fullauto"):
			cap0 = int(Guns.SR25_MODS["fullauto"]["mag_to"])
		_slots[slot] = {"id": gid, "ammo": cap0,
				"reserve": _reserve_for_gun(gid)}
		# 同槽换了枪才重建枪模；同枪复用已有 holder（重复进场不堆积）。
		# 旧枪模释放前先隐身：queue_free 到帧末才生效，不隐身会同帧新旧两把
		# 枪模叠影一帧（切枪链上唯一的实存渲染缺陷，2026-10 黄壳排查中修掉）
		if _guns.has(slot) and (str(_guns[slot]["id"]) != gid \
				or bool(_guns[slot].get("sup", false)) != _sup_on(gid)):
			var old: Dictionary = _guns[slot]
			var old_holder: Node3D = old["holder"]
			old_holder.visible = false
			old_holder.queue_free()
			(old["flash"] as OmniLight3D).queue_free()
			(old["flash_env"] as OmniLight3D).queue_free()   # 主世界镜像灯随旧枪一并释放
			_guns.erase(slot)
		if not _guns.has(slot):
			_mount_slot(slot)
	_equip("primary")
	if _slots.is_empty():
		for k in _guns:
			var g0: Dictionary = _guns[k]
			(g0["holder"] as Node3D).visible = false


func update(dt: float) -> void:
	_tick_fx(dt)
	if player == null or player.dead or player.cam == null:
		return
	# 本帧相机摆位先钉进 vm 相机（幂等，同帧重复同步零代价）：try_fire 的
	# 曳光起点 muzzle_world、掉匣落点全靠「holder.to_global=主世界坐标」
	# 这条不变量，而它成立的唯一前提是 vm 相机 transform == 主相机 transform
	if player.has_method("sync_vm"):
		player.sync_vm()
	# 追赶式冷却：不 clamp 到 0、允许负结转（try_fire 里 += cd 配对）——
	# 逐帧减法 + 帧门曾把实际射速压到 ceil(60·cd) 帧的离散档（60fps 下全册
	# 只剩九档射速、多枪撞档），结转后晚过门多等的帧量在下一发补回，长程
	# 射速收敛到表值 1/cd。闲置不攒盈余（松手/换弹/没弹 clamp，见开火门处）
	fire_cd -= dt
	var slot_before := _cur_slot
	# R 换弹 / Digit1·Digit2 切枪：边沿检测（只按 is_action_pressed，onfoot 同款读法）
	var r_now := Input.is_action_pressed("hd_reload")
	if r_now and not _reload_prev:
		start_reload()
	_reload_prev = r_now
	var s1_now := Input.is_action_pressed("hd_slot1")
	if s1_now and not _slot1_prev:
		_equip("primary")
	_slot1_prev = s1_now
	var s2_now := Input.is_action_pressed("hd_slot2")
	if s2_now and not _slot2_prev:
		_equip("secondary")
	_slot2_prev = s2_now
	# 开火门（置于此、先于切枪 return：切枪当帧不丢拍——_equip 已把
	# cur_id/_g/ammo 全部换就绪，开火只读这些；弹匣/摆位才留给下一帧）：
	# 全自动 = 按住连发；半自动/栓动（表 auto=false）只认 tap 边沿开火，
	# 按住不连发。没弹自动换弹。门带 FIRE_GATE 残差容差；闲置（不可触发/
	# 换弹/没弹）时冷却 clamp 归零——松手重置节拍，负盈余不攒出偷跑
	var fire_pressed := Input.is_action_pressed("hd_fire")
	if not fire_pressed:
		_press_shots = 0   # 松开扳机：按压计数复位（cd_profile 档位回零——
		                   # 再按又是一对新的超点射；不带档案的枪无感）
		_trig_delay = 0.0  # 松开同时放弃蓄力：再按重新蓄满（M250 0.5s）
	var fire_tap := fire_pressed and not _fire_prev
	_fire_prev = fire_pressed
	# SR25 全自动套件（SR25_MODS.fullauto，2026-10-26 用户定案）：覆写 auto/burst
	# ——装上后 auto=true 按住连发 + burst=2（扳机每起新边沿补一个两发点射）；
	# 未装 = 原厂半自动（auto=false 走 tap 门，burst=0 无点射）
	var sr25_kit := cur_id == "sr25" and _m14_mod("fullauto")
	var auto_now := bool(_g.get("auto", true)) or (sr25_kit and bool(Guns.SR25_MODS["fullauto"]["auto_to"]))
	var fire_ok := fire_pressed if auto_now else fire_tap
	# 三连发（表 burst，2026-10-25 MK4 用户定案）：点一下边沿起一个 N 发点射，
	# 打完为止（松手不打断——点射一旦扣出就完成）；按住不重复、点射中再点无效。
	# 轮间锁（burst_gap，三角洲实测 0.1s：单轮内 ~1200rpm 0.05s 间隔、打完后约
	# 100ms 才能点下一轮——面板 800rpm 即含间隔的平均值）：锁内起不了新点射。
	# 全自动解锁走配件（m14_mods_provider 注入 autobarrel——存储链与 M14 同源）
	var burst_n := int(_g.get("burst", 0))
	if sr25_kit and _kit_burst_mode:
		burst_n = int(Guns.SR25_MODS["fullauto"]["burst_to"])
		_burst_cd_ov = float(Guns.SR25_MODS["fullauto"]["burst_cd_to"])
		_kit_gap_ov = float(Guns.SR25_MODS["fullauto"]["burst_gap_to"])
	else:
		_burst_cd_ov = 0.0
		_kit_gap_ov = 0.0
	_kit_cd_ov = float(Guns.SR25_MODS["fullauto"]["cd_to"]) if sr25_kit else 0.0
	if _burst_gap > 0.0:
		_burst_gap = maxf(0.0, _burst_gap - dt)
	if burst_n > 0:
		var mod_auto := str(cur_id) == "mk4" and m14_mods_provider != null \
				and bool(m14_mods_provider.call("autobarrel"))
		if sr25_kit:
			# SR25 套件三连发模式（B 切换）：MK4 式——边沿起三发、打完为止、
			# 轮间锁内不起射；先压 fire_ok=false（auto 缺省真值会漏成按住
			# 连发——MK4 改造同款坑）；全自动模式下本分支不进（burst_n=0）
			fire_ok = false
			if fire_tap and _burst_left <= 0 and _burst_gap <= 0.0:
				_burst_left = burst_n
			if _burst_left > 0:
				fire_ok = true
		elif mod_auto:
			fire_ok = fire_pressed   # 全自动枪管：按住连发（burst 字段让位）
		else:
			fire_ok = false   # 三连发原厂：按住不连发（点射由内部计数驱动）
			if fire_tap and _burst_left <= 0 and _burst_gap <= 0.0:
				_burst_left = burst_n   # 锁清零帧才可起新点射（严格 >0 都锁）
			if _burst_left > 0:
				fire_ok = true
	# 扳机蓄力（表 trigger_delay，2026-10-24 M250 用户定案 0.5s）：按下边沿起蓄，
	# 蓄满前不出弹；全自动蓄力结束后连发节拍照旧（cd 路径零改动）。完成判据带
	# FIRE_GATE 残差容差——浮点逐帧递减的尾差不算额外一帧延迟（射速门同套路）
	var trig_d := float(_g.get("trigger_delay", 0.0))
	if fire_tap and trig_d > 0.0:
		_trig_delay = trig_d
	if _trig_delay > 0.0:
		_trig_delay = maxf(0.0, _trig_delay - dt)
		if _trig_delay > FIRE_GATE:
			fire_ok = false   # 蓄力中——当帧不出弹（蓄满帧即放行开火）
	if fire_ok and fire_cd <= FIRE_GATE and reloading <= 0.0:
		if ammo > 0:
			try_fire()
		else:
			start_reload()
	elif not fire_ok or reloading > 0.0 or ammo <= 0:
		fire_cd = maxf(fire_cd, 0.0)
	if _cur_slot != slot_before:
		return   # 本帧切了枪：弹匣/摆位留给下一帧，别去摆旧枪
	var g := _cur_gun()
	if g.is_empty() or cur_id == "":
		return
	# ADS：按住右键开镜；进度与倍率每帧写给玩家（FOV=75/zoom 在玩家侧算）
	# 开镜速度 ×配件 ads_mul（M14 战术护木 +25%——_mod_muls）
	_aiming = Input.is_action_pressed("hd_scope")
	_ads = move_toward(_ads, 1.0 if _aiming else 0.0,
			dt * ADS_SPEED * _mod_muls().y)
	player.ads = _ads
	player.zoom = current_zoom()
	# 换弹动画：枪体下倾 → 0.25~0.55 旧匣脱落坠地（手跟到脱离点甩开）
	# → 0.55~0.85 新匣滑入（0.55~0.75 手托匣上抬 / 0.75~0.85 手压拍合）→ 手离场
	var mag: MeshInstance3D = g["mag"]
	var show_mag: bool = g["show_mag"]
	var mag_pos: Vector3 = g.get("mag_pos", MAG_POS)   # 新枪弹匣位（缺省=旧五枪值）
	if reloading > 0.0:
		reloading -= dt
		var total: float = float(_g.get("reload", 1.5))
		var prog: float = clampf(1.0 - reloading / maxf(total, 0.01), 0.0, 1.0)
		var dip := sin(prog * PI)
		_reload_off = Vector3(0.03 * dip, -0.09 * dip, 0.05 * dip)
		_reload_rot = Vector3(4.0 * dip, 0.0, 26.0 * dip)
		if prog >= 0.25 and prog < 0.55:
			mag.visible = false
			if not _falling:
				_falling = true
				_drop_mag()
		elif prog >= 0.55 and prog < 0.85:
			# 新匣从下方滑入（插到 0.85 正好归位）
			var k := clampf((prog - 0.55) / 0.30, 0.0, 1.0)
			mag.visible = show_mag
			mag.position = mag_pos + Vector3(0.0, -0.12 * (1.0 - k), 0.0)
		else:
			mag.visible = show_mag
			mag.position = mag_pos
			_falling = false
		if reloading <= 0.0:
			reloading = 0.0
			var mag_n: int = _mag_cap()
			var taken: int = mini(mag_n - ammo, reserve)
			ammo += taken
			reserve -= taken
			mag.visible = show_mag
			mag.position = mag_pos
			_hide_hand()
			reloaded.emit()
		else:
			_update_reload_hand(prog)
	else:
		_hide_hand()
		_reload_off = Vector3.ZERO
		_reload_rot = Vector3.ZERO
		mag.visible = show_mag
		mag.position = mag_pos
		_falling = false
	# 枪架摆位：肩射腰射位 ↔ 瞄准位（胸前提枪机制已按用户要求整体移除）。
	# 开镜 lerp 终点默认枪顶 AABB 对准星正下方（onfoot 同款）；3× 以上
	# 高倍镜开镜到位后隐藏枪模（镜筒贴脸挡屏，FOV 一缩还会放大数倍）。
	# 红点镜例外：改按 aim_y（挂枪时记的镜窗中心 local y）让窗中心过屏幕
	# 中心——HUD 红点画在屏幕正中，旧 AABB 顶公式把整扇窗吊在准星下方
	# 12mm，红点悬在玻璃窗外上方＝用户反馈「准星飞出镜子外」；窗中心在
	# 枪身局部 x=0，x 终点随之归零。其它镜/机瞄不记 aim_y，摆位零改动
	var holder: Node3D = g["holder"]
	holder.visible = not (_aiming and _ads > 0.9 and current_zoom() >= HIDE_ZOOM)
	var ads_pos := Vector3(-GUN_SCALE * float(g["cx"]),
			-0.012 - GUN_SCALE * float(g["top"]), GUN_ADS_Z)
	if g.has("aim_y"):
		ads_pos = Vector3(0.0, -GUN_SCALE * float(g["aim_y"]), GUN_ADS_Z)
	holder.position = GUN_HIP_POS.lerp(ads_pos, _ads) + _reload_off
	holder.rotation_degrees = GUN_HIP_ROT.lerp(Vector3.ZERO, _ads) + _reload_rot
	# 枪口火光衰减
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			var flash: OmniLight3D = g["flash"]
			var flash_mesh: MeshInstance3D = g["flash_mesh"]
			flash.visible = false
			flash_mesh.visible = false
			(g["flash_env"] as OmniLight3D).visible = false   # 主世界镜像闪光同灭


## 开一发：弹数/射线/曳光/伤害结算/后坐力/火光/枪声（按住自动连发）
## 射速档案取值（2026-10 AN-94 超点射机制，纯增量）：本次按压已打
## _press_shots 发，则下一发冷却 = cd_profile 第 mini(_press_shots-1, 末位)
## 位（越界取末值）；无档案 = 单 cd（原路径，其余 18 把枪行为逐字不变）。
## 按压计数在 update（松开扳机）/_equip（切枪）/start_reload（换弹）归零
func _cd_after_shot() -> float:
	var prof: Array = _g.get("cd_profile", [])
	if not prof.is_empty():
		return float(prof[mini(_press_shots - 1, prof.size() - 1)])
	if _burst_left > 0:
		if _burst_cd_ov > 0.0:
			return _burst_cd_ov   # 配件覆写轮内间隔（SR25 套件 1069rpm）
		return float(_g.get("burst_cd", 0.05))   # 点射轮内间隔（缺省 1200rpm；三角洲 MK4 实测）
	if _kit_cd_ov > 0.0:
		return _kit_cd_ov   # SR25 套件全自动模式节拍覆写（cd_to=1069rpm）
	return float(_g.get("cd", 0.13))


func try_fire() -> void:
	if cur_id == "" or reloading > 0.0 or fire_cd > 0.0 or ammo <= 0:
		return
	if player == null or player.dead or player.cam == null:
		return
	# 卡壳：耐久低于 JAM_DUR 每发 JAM_P 概率打不响（不耗弹，JAM_TIME 后才能再扣）
	if _dur() < HDData.JAM_DUR and randf() < HDData.JAM_P:
		fire_cd = HDData.JAM_TIME
		if audio != null and audio.has_method("play_click"):
			audio.play_click()
		jammed.emit()
		return
	# 结转式重置：+= 而非 =——进门前晚到的帧量（fire_cd 为负）在此补回，
	# 长程实际射速收敛到表值 1/cd（帧量化丢的拍逐发找平；闲置期已被
	# update 的 clamp 归零，不会把松手攒的负值结转成爆发）。
	# 间隔取值走射速档案 _cd_after_shot：cd_profile 枪按压内第 k 发之后
	# 取 prof[min(k-1, 末位)]（AN-94 [0.0333,0.1]：首对 1800rpm、之后
	# 600rpm）；无档案 = 单 cd 原路径逐字不变（其余 18 把枪零变化）。
	# 档案枪按压首发额外出掉「门前 -=dt 负结转」（update 先减后过门的
	# 固有提前量：它让全枪册每一按的首个间隔都少 1 帧）——超点射首对
	# 间隔是机制签名，必须对表 0.0333s=2 帧不漂；无档案枪不吃此吸收，
	# 首发提前量原样保留（既有手感零变化）
	ammo -= 1
	_press_shots += 1
	if _burst_left > 0:
		_burst_left -= 1   # 三连发计数（没弹换弹会中止：下方清零）
		if _burst_left <= 0:
			# 点射打完 → 轮间锁（burst_gap，三角洲实测 ~100ms；cd 是轮内间隔
			# 1200rpm=0.05s，两者不是一回事）；SR25 套件三连发模式走覆写值
			_burst_gap = _kit_gap_ov if _kit_gap_ov > 0.0 \
					else float(_g.get("burst_gap", 0.0))
		if ammo <= 0:
			_burst_left = 0
	if _press_shots == 1 and not (_g.get("cd_profile", []) as Array).is_empty():
		fire_cd = maxf(fire_cd, 0.0)
	fire_cd += _cd_after_shot()
	var g := _cur_gun()
	if not g.is_empty():
		# 枪口火光：发光片贴枪口 + 瞬时点光（onfoot 同款 0.05s）；点光同位：
		# 枪架与点光同为 vm 相机子节点，holder.transform 把枪口点转到相机局部
		# （胸前/肩射/开镜各姿态都与发光片同位）。vm 相机每帧同步主相机，
		# 同一相机局部坐标写到主相机下的 flash_env（主世界镜像灯）就是同一
		# 世界位置——枪侧被 vm 灯照、墙面被主世界灯照，观感与旧「单灯双照」一致
		var flash: OmniLight3D = g["flash"]
		var flash_mesh: MeshInstance3D = g["flash_mesh"]
		var moff: Vector3 = g["muzzle_off"]   # 每槽枪口点（持枪平移随动）
		_flash_t = 0.05
		# 火光能量/尺寸按枪分档：改枪台消音器（sup）几乎无火光；asval 自带
		# 一体消音器分支（写法照 _finish_gun 的 mp7/m14 先例，按枪 id 短路）
		# ——亚音速弹 + 粗管消声器实际抑制枪口焰：能量减半（3.0→1.5）、
		# 火光 mesh 缩小（1.0→0.5），介于普通枪与改枪台消音（0.5/0.35）
		# 之间；既有枪数值零改动
		var sup_on := bool(g.get("sup", false))
		var flash_e := 0.5 if sup_on else 3.0   # 消音器：几乎无火光
		var flash_s := 0.35 if sup_on else 1.0
		if cur_id == "asval" and not sup_on:
			flash_e = 1.5    # 自带一体消音器：枪口焰能量减半
			flash_s = 0.5    # 火光 mesh 缩小一档
		flash.light_energy = flash_e
		flash_mesh.scale = Vector3.ONE * flash_s
		flash.visible = true
		flash.position = (g["holder"] as Node3D).transform * moff
		flash_mesh.visible = true
		flash_mesh.position = moff
		var flash_env: OmniLight3D = g["flash_env"]
		flash_env.light_energy = flash.light_energy
		flash_env.visible = true
		flash_env.position = flash.position   # 同相机局部坐标=同世界位置（sync_vm 不变量）
	# 射线：相机 from、-Z 前向、右/上基向量抖动 spread（每颗弹丸独立判定）
	var from: Vector3 = player.cam.global_position
	var base_dir: Vector3 = -player.cam.global_transform.basis.z
	var wear_mul := _dur_mul()
	var spread: float = float(_g.get("spread", 0.0)) * lerpf(1.0, ADS_SPREAD, _ads) * wear_mul
	var pellets: int = int(_g.get("pellets", 1))
	var max_r: float = float(_g.get("range", 250.0))
	var dmg: float = float(_g.get("dmg", 20.0))
	var sup := _sup_on(cur_id)
	if sup:
		dmg *= HDData.SUP_DMG_MUL
	var right: Vector3 = player.cam.global_transform.basis.x
	var up: Vector3 = player.cam.global_transform.basis.y
	for p in pellets:
		var jitter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * spread * 2.0
		var pdir := (base_dir + right * jitter.x + up * jitter.y).normalized()
		var h := raycast_all(from, pdir, max_r)
		var kind := str(h.get("type", ""))
		var end: Vector3 = from + pdir * max_r if kind == "" else Vector3(h["point"])
		if tracers != null:
			tracers.spawn(muzzle_world(), end, kind != "")
		if kind == "soldier_head" or kind == "soldier":
			# 伤害在此结算：爆头 ×2
			var head := kind == "soldier_head"
			var hd: float = dmg * (HEADSHOT_MUL if head else 1.0)
			hit_enemy.emit(kind, int(h["i"]), end, hd, head)
		elif kind == "target" and targets != null:
			targets.on_hit(int(h["i"]))
		# 墙/落空：只画曳光+火花（tracer on_arrive 出火花）
	fired.emit()
	# 后坐力：视角上顶 + 水平随机漂移；开镜幅度 6 折（onfoot 公式照抄）；
	# 整体 ×配件 recoil_mul（M14 战术护木 -45%——_mod_muls）。
	# 超点射真实弹道特征（2026-10 AN-94 引入）：带射速档案（cd_profile）的枪
	# 按压内前 BURST_SOFT_SHOTS 发后坐再乘 BURST_SOFT_MUL——延迟后坐让对射
	# 几乎无感（内机匣在聚合物外壳内后坐吸收冲量）；其余枪/超点射之后不触发
	var rc: Array = RECOIL.get(cur_id, [0.4, 0.2, 0.25])
	var base: float = (0.6 if _aiming else 1.0) * wear_mul
	# SR25 全自动套件制退补偿（recoil_mul_to，两轴同乘——1069rpm 射速转换的
	# 配套；半自动原厂不受影响）
	if cur_id == "sr25" and _m14_mod("fullauto"):
		base *= float(Guns.SR25_MODS["fullauto"]["recoil_mul_to"])
	var hmul: float = base * _mod_muls().x   # 水平漂移乘数（通用握把 recoil_mul）
	var vmul: float = base * _vy_mul()       # 垂直上顶乘数（共振前握把 vy_mul 专属）
	if not (_g.get("cd_profile", []) as Array).is_empty() \
			and _press_shots <= BURST_SOFT_SHOTS:
		hmul *= BURST_SOFT_MUL
		vmul *= BURST_SOFT_MUL
	player.recoil_pitch += deg_to_rad(rc[0] + rc[1] * player.recoil_pitch * 57.3 * 0.5) * vmul
	player.recoil_yaw += deg_to_rad(randf_range(-rc[2], rc[2])) * hmul
	player.recoil_cool = 0.0
	if audio != null:
		if sup and audio.has_method("play_shot_sup"):
			audio.play_shot_sup(cur_id)
		else:
			audio.play_shot(cur_id)


## R 键手动换弹（弹匣未满、有备弹、不在换弹中才生效；极致备弹经济下
## reserve=0 即弹尽粮绝——拒绝换弹不进动画）
func start_reload() -> void:
	if cur_id == "" or reloading > 0.0:
		return
	if ammo >= _mag_cap() or reserve <= 0:
		return
	# M14 30 发扩容匣：长匣换弹 +0.4s（stash 解锁态经 m14_mods_provider 读）
	var extra: float = 0.4 if (cur_id == "m14" and _m14_mod("extmag")) else 0.0
	reloading = float(_g.get("reload", 1.5)) + extra
	_press_shots = 0   # 换弹归零按压计数（cd_profile 档位回零——AN-94 超点射）
	_burst_left = 0    # 换弹中止三连发点射（MK4：装填完要重新扣扳机）
	_burst_gap = 0.0   # 换弹清轮间锁
	if audio != null:
		audio.play_reload()


## 当前枪弹匣容量：GUNS 表 mag 基准；M14 装 extmag 扩 30（2026-10 用户定案
## 「装特有的三十发弹匣」——解锁态由 main 注入 m14_mods_provider，探针裸
## 调时未注入 = 原弹容，行为不变）
## SR25 套件 B 键切换开火模式：返回新模式（"auto"/"burst"），未装套件返回 ""
func toggle_fire_mode() -> String:
	if not (cur_id == "sr25" and _m14_mod("fullauto")):
		return ""
	_kit_burst_mode = not _kit_burst_mode
	_burst_left = 0   # 切模式中止进行中的点射
	_burst_gap = 0.0
	return "burst" if _kit_burst_mode else "auto"


func _mag_cap() -> int:
	var cap := int(_g.get("mag", 12))
	if cur_id == "m14" and _m14_mod("extmag"):
		cap = 30
	# SR25 全自动套件：弹匣自动换 45 发专用长匣（2026-10-26 用户定案）
	if cur_id == "sr25" and _m14_mod("fullauto"):
		cap = int(Guns.SR25_MODS["fullauto"]["mag_to"])
	return cap


## M14 配件解锁查询（main 注入 stash 查询闭包；未注入 = false 原版行为）
var m14_mods_provider: Callable = Callable()
var grip_muls_provider: Callable = Callable()
var grip_vy_provider: Callable = Callable()   # 垂直后坐乘数（共振前握把 vy_mul）
## 第四阶段：耐久（func(gun_id)->0..100，含本局磨损）/ 消音器（func(gun_id)->bool）；
## 未注入 = 全新无消音（探针/测试裸调行为不变）
var dur_provider: Callable = Callable()
var sup_provider: Callable = Callable()
const SUP_LEN := 0.17      # 消音器长（枪架局部 m）：枪口点前移这么多
const SUP_R := 0.021


func _dur() -> float:
	if dur_provider.is_valid():
		return float(dur_provider.call(cur_id))
	return 100.0


## 磨损倍率：耐久 ≥ DUR_WORN 为 1；往下线性涨到耐久 0 时 1 + DUR_WORN_MUL
func _dur_mul() -> float:
	var d := _dur()
	if d >= HDData.DUR_WORN:
		return 1.0
	return 1.0 + HDData.DUR_WORN_MUL * (HDData.DUR_WORN - d) / HDData.DUR_WORN


func _sup_on(gid: String) -> bool:
	return sup_provider.is_valid() and bool(sup_provider.call(gid))


## 消音器圆筒（沿 -Z；k = 尺寸倍率：枪架局部 1.0 / 枪身局部 1/GUN_SCALE）
func _make_sup_can(k: float) -> MeshInstance3D:
	var can := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = SUP_R * k
	cyl.bottom_radius = SUP_R * k
	cyl.height = SUP_LEN * k
	cyl.radial_segments = 14
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.07, 0.07, 0.075)
	cm.roughness = 0.55
	cm.metallic = 0.6
	cyl.material = cm
	can.mesh = cyl
	can.rotation_degrees = Vector3(90, 0, 0)
	return can


## 枪口点（枪身局部）：全部网格顶点里最靠前（-Z）的 2.5 cm 截面取 x/y 均值——
## 写实枪模各枪长短不一，按几何量出来；按枪 id 缓存（换镜不影响枪管）
var _muzzle_cache := {}

func _muzzle_point(gun: Node3D) -> Vector3:
	var key := str(gun.get_meta("gun_id", gun.name))
	if _muzzle_cache.has(key):
		return _muzzle_cache[key]
	var pts := PackedVector3Array()
	var inv := gun.global_transform.affine_inverse() if gun.is_inside_tree() else Transform3D.IDENTITY
	for mi_v in gun.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D
		if gun.is_inside_tree():
			xf = inv * mi.global_transform
		else:
			xf = Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != gun:
				if n is Node3D:
					xf = (n as Node3D).transform * xf
				n = n.get_parent()
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				pts.append(xf * v)
	var out := MUZZLE_OFF / GUN_SCALE
	if not pts.is_empty():
		var mz := INF
		for v in pts:
			mz = minf(mz, v.z)
		var sx := 0.0
		var sy := 0.0
		var n2 := 0
		for v in pts:
			if v.z < mz + 0.025:
				sx += v.x
				sy += v.y
				n2 += 1
		out = Vector3(sx / n2, sy / n2, mz)
	_muzzle_cache[key] = out
	return out


## 大厅缩略图：单独一枚瞄具（同局内镜体：写实 optic_<kind>.glb + 程序化玻璃/
## 红点件），kind = Guns.SCOPES 的 kind（holo/reddot/optic/sniper/thermal）
func build_scope_preview(kind: String) -> Node3D:
	var root := Node3D.new()
	_scope_visual(root, kind, 0.0, 0.0, -0.08)
	return root


## 大厅改枪台 3D 预览：同局内枪模（含所装瞄具）+ 消音器（枪身局部尺寸）
func build_preview(gid: String) -> Node3D:
	var gun := _build_gun_visual(gid)
	gun.set_meta("gun_id", gid)
	if _sup_on(gid):
		var can := _make_sup_can(1.0 / GUN_SCALE)
		can.position = _muzzle_point(gun) + Vector3(0, 0, (-SUP_LEN * 0.5 + 0.012) / GUN_SCALE)
		gun.add_child(can)
	return gun

func _m14_mod(mid: String) -> bool:
	if m14_mods_provider.is_valid():
		return bool(m14_mods_provider.call(mid))
	return false


## 当前枪的配件乘数 (recoil_mul, ads_mul)：M14 装 foregrip 护木 = 垂直前握把
## 档（后坐 -45% / 开镜速 +25%，GRIPS 表 vertical）；其它枪/未装 = 1.0
func _mod_muls() -> Vector2:
	var v := Vector2.ONE
	if cur_id == "m14" and _m14_mod("foregrip"):
		v = Vector2(0.55, 1.25)
	# 通用前握把（GRIPS 表，stash grip_muls 经 main 注入——2026-10-27 接活，
	# 此前 provider 悬空纯数据）：后坐/开镜乘数叠乘（未装 = ONE 零变化）
	if grip_muls_provider != null and grip_muls_provider.is_valid():
		var gm: Vector2 = grip_muls_provider.call(cur_id)
		v = Vector2(v.x * gm.x, v.y * gm.y)
	return v


## 垂直后坐专用乘数（共振前握把 vy_mul 只压 pitch 上顶，水平漂移走
## _mod_muls().x）——M14 战术护木对两轴都生效照旧叠乘
func _vy_mul() -> float:
	var m := 0.55 if (cur_id == "m14" and _m14_mod("foregrip")) else 1.0
	if grip_vy_provider != null and grip_vy_provider.is_valid():
		m *= float(grip_vy_provider.call(cur_id))
	return m


## 备弹弹药源：main 注入的 reserve_provider（stash 极致备弹库存）；
## 未注入（探针/测试裸调 enter）回 0——备弹不再免费给
func _reserve_for_gun(gid: String) -> int:
	if reserve_provider != null and reserve_provider.is_valid():
		return maxi(0, int(reserve_provider.call(gid)))
	return 0


## 各槽余弹快照 {slot: {"id","ammo","reserve"}}（先回写当前槽——换弹中/结束都
## 取最新值）——main 局终（撤离/死亡/放弃）按此把剩余备弹回收进 stash
func slot_snapshots() -> Dictionary:
	_save_cur()
	var out := {}
	for slot in _slots.keys():
		var s: Dictionary = _slots[slot]
		out[slot] = {"id": str(s["id"]), "ammo": int(s["ammo"]),
				"reserve": int(s["reserve"])}
	return out


## 切到另一槽位（Digit1/Digit2 直选走 _equip）
func switch_slot() -> void:
	if _cur_slot == "primary":
		_equip("secondary")
	else:
		_equip("primary")


## 汇聚命中取最近：墙 / 士兵（可选，未注入则跳过）/ 靶子（同），
## 返回统一契约 {"type","i","d","point"}；type=="" = 全落空（point=远端点）。
## world.wall_hit 鸭子类型：HDWorld 返回命中距离（float，无墙 = max_d），
## 兼容直接返回命中字典的实现
func raycast_all(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var best := {"type": "", "i": -1, "d": max_d, "point": from + dir * max_d}
	var cands: Array = []
	if world != null:
		var wres: Variant = world.wall_hit(from, dir, max_d)
		if wres is float or wres is int:
			var wd := float(wres)
			if wd < max_d:
				cands.append({"type": "wall", "i": -1, "d": wd,
						"point": from + dir * wd})
		elif wres is Dictionary:
			cands.append(wres)
	if soldiers != null:
		cands.append(soldiers.raycast(from, dir, max_d))
	if targets != null:
		cands.append(targets.raycast(from, dir, max_d))
	for c in cands:
		if not (c is Dictionary):
			continue
		var h: Dictionary = c
		var kind := str(h.get("type", ""))
		if kind == "":
			continue
		var d_hit: float = float(h.get("d", max_d))
		if d_hit < float(best["d"]):
			best = {"type": kind, "i": int(h.get("i", -1)), "d": d_hit,
					"point": Vector3(h.get("point", from + dir * d_hit))}
	return best


## 当前开镜倍率：没按右键 = 1.0（FOV 不变）；机瞄恒 1.0（问题①：突击步枪
## 等非狙击枪不自带倍率）；倍率只来自改枪台装配的瞄具或狙击原厂镜
func current_zoom() -> float:
	if not _aiming or cur_id == "":
		return 1.0
	var sc: Dictionary = _scope_info_for(cur_id)
	return maxf(float(sc.get("zoom", 1.0)), 1.0)


## 枪口世界坐标：当前枪架局部的枪口点，与枪口火光同位。
## holder 在 vm 世界，但 vm 相机每帧同步主相机（HDPlayer.sync_vm 不变量），
## to_global 的数值 == 主世界坐标——曳光起点（主世界 TracerPool.spawn 消费）
## 因此零改动；数学与旧「holder 挂主相机」逐位一致
func muzzle_world() -> Vector3:
	var g := _cur_gun()
	if not g.is_empty():
		var holder: Node3D = g["holder"]
		return holder.to_global(g["muzzle_off"])
	if player != null and player.cam != null:
		return player.cam.global_transform * Vector3(0.26, -0.16, -1.1)
	return Vector3.ZERO


## ---------------- 内部：槽位与枪模 ----------------


## 当前槽位的枪架信息包（无枪 = 空字典）
func _cur_gun() -> Dictionary:
	if _guns.has(_cur_slot):
		return _guns[_cur_slot]
	return {}


## 切槽/进场前把当前余弹回写槽位（否则切回来满弹作弊）
func _save_cur() -> void:
	if _cur_slot != "" and _slots.has(_cur_slot):
		_slots[_cur_slot]["ammo"] = ammo
		_slots[_cur_slot]["reserve"] = reserve


func _equip(slot: String) -> void:
	if not _slots.has(slot) or _cur_slot == slot:
		return
	_save_cur()
	_cur_slot = slot
	var s: Dictionary = _slots[slot]
	cur_id = str(s["id"])
	_g = Guns.gun_by_id(cur_id)
	ammo = int(s["ammo"])
	reserve = int(s["reserve"])
	reloading = 0.0
	# 切枪不继承上一把枪的剩余冷却（此前 _equip 只清 reloading 不清
	# fire_cd：狙击开一枪立刻切枪，新枪按住要等旧枪 ~1.2s 冷却走完才首发）
	fire_cd = 0.0
	_press_shots = 0   # 切枪归零按压计数（换枪再按又是新的一对超点射）
	_trig_delay = 0.0  # 切枪放弃蓄力：新枪按下重新蓄（不继承旧枪进度）
	_burst_left = 0    # 切枪中止点射（新枪按自己的节奏来）
	_burst_gap = 0.0   # 切枪清轮间锁
	_kit_burst_mode = false   # 切枪回全自动缺省（别的枪没有模式态）
	_falling = false
	_mag_landed = false
	_hide_hand()
	if _falling_mag != null:
		_falling_mag.visible = false
	# 只显示当前槽位枪模
	for k in _guns:
		var gi: Dictionary = _guns[k]
		var holder: Node3D = gi["holder"]
		var flash: OmniLight3D = gi["flash"]
		var flash_mesh: MeshInstance3D = gi["flash_mesh"]
		holder.visible = k == slot
		flash.visible = false
		flash_mesh.visible = false
		(gi["flash_env"] as OmniLight3D).visible = false


## 挂一把枪（vm 相机子节点）：holder 锚点 + AABB 量枪顶 + 弹匣块 + 枪口火光
## （枪模整体在 own_world_3d 独立视口渲染——「为什么」见本文件头注与
## HDPlayer._build_vm；本函数的三处挂载点 holder/flash/换弹手全在 vm 世界，
## 射线/掉匣/火花等世界结算件一个不迁，见 _drop_mag/_spawn_impact）
func _mount_slot(slot: String) -> void:
	if player == null or player.cam == null or player.vm_cam == null:
		return
	var gid: String = str(_slots[slot]["id"])
	# 持枪对齐随动（枪架局部 = 枪身 Δ × GUN_SCALE）：弹匣锚/枪口火光/曳光
	# 三处消费同一 hold_off，与 _build_gun_visual 的枪身平移保持同源
	var hold_off: Vector3 = _hold_delta(gid) * GUN_SCALE
	var gun := _build_gun_visual(gid)
	gun.set_meta("gun_id", gid)
	var sup := _sup_on(gid)
	var holder := Node3D.new()
	# 锚点抬到视锥内（onfoot：原点在相机上时枪会落到画面底边之外）
	holder.position = GUN_HIP_POS
	holder.rotation_degrees = GUN_HIP_ROT
	# 挂 vm 相机（独立世界）：主相机与 vm 相机每帧 transform 一致（sync_vm），
	# 同一局部摆位渲染出的屏幕落点与旧「挂主相机」逐像素等价，而 vm 世界
	# 没有任何掩体几何——枪管「穿墙」从根上不存在
	player.vm_cam.add_child(holder)
	gun.scale = Vector3.ONE * GUN_SCALE
	holder.add_child(gun)
	# 量枪模包围盒：开镜时把枪顶（机瞄/瞄具）正好放到准星正下方
	var bb := _local_aabb(gun)
	var top := 0.085
	var cx := 0.0
	if bb.size != Vector3.ZERO:
		top = bb.end.y
		cx = bb.get_center().x
	# 枪上弹匣（换弹动画：脱落/滑入用）：全枪册按枪匠 mag_of 契约覆盖
	# 位/尺寸/显隐（P90 顶匣隐动画匣、UZI/Vector 匣入握把、旧五枪静置
	# 真匣建模件+动画匣隐）——缺省键用 MAG_POS/通用盒/true 兜底
	var mag_size := Vector3(0.055, 0.17, 0.09)
	var mag_pos := MAG_POS
	var show_mag := true   # 全程序化拼枪：弹匣块一律显示（拔匣/插匣动画各枪可见）
	var ov: Dictionary = _mag_override(gid)
	if ov.has("size"):
		mag_size = ov["size"]
	if ov.has("pos"):
		mag_pos = ov["pos"]
	if ov.has("show"):
		show_mag = bool(ov["show"])
	mag_pos += hold_off   # 持枪平移随动：静置真匣/换弹手锚与平移后的弹匣井对齐
	var mag_box := BoxMesh.new()
	mag_box.size = mag_size
	# 动画匣材质收敛（2026-10 判图「发光白面」三轮终审）：动画匣是纯功能
	# 件（换弹动画方块），show=true 时（uzi/vector）顶面承全部顶向光
	# （vm_sun+vm_fill 近距+ambient 叠加），lit 材质 alb 压到 0.05 仍有
	# 近距光斑——改 UNSHADED 恒定暗灰：不参与光照=永不受光翻白。
	# 注意高光属性名是 metallic_specular（曾误写 specular 导致 _mount_slot
	# 每次抛错中断、火光/vm_fill/枪架包全没建——教训保留在此）
	var mag_mat := StandardMaterial3D.new()
	mag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mag_mat.albedo_color = Color(0.08, 0.085, 0.095)
	mag_mat.no_depth_test = true
	mag_mat.render_priority = 10
	mag_box.material = mag_mat
	var mag := MeshInstance3D.new()
	mag.mesh = mag_box
	mag.position = mag_pos
	holder.add_child(mag)
	mag.visible = show_mag
	# 枪口火光：小发光片 + 瞬时点光
	var fm := SphereMesh.new()
	fm.radius = 0.045
	fm.height = 0.09
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.8, 0.3)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.7, 0.2)
	fmat.emission_energy_multiplier = 6.0
	fm.material = fmat
	var flash_mesh := MeshInstance3D.new()
	flash_mesh.mesh = fm
	flash_mesh.visible = false
	flash_mesh.position = MUZZLE_OFF + hold_off   # 枪口随枪平移（枪架局部）
	holder.add_child(flash_mesh)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.35)
	flash.light_energy = 3.0
	flash.omni_range = 6.0
	flash.visible = false
	# 闪光灯随枪迁入 vm 世界：只照枪（vm 世界零几何，灯打不出别的）。
	# 主世界墙面本被开火闪光照亮的观感由下面的镜像灯承接——玩法契约零回退
	player.vm_cam.add_child(flash)
	# 主世界镜像闪光（flash_env）：同相机局部坐标=同世界位置（sync_vm 把两
	# 相机钉成同一 transform），开火帧同步点亮、0.05s 同灭。与 vm_fill 亮斑
	# 案不冲突：那是常亮补光随枪扫动（每帧都亮），这盏只在开火 0.05s 闪现、
	# 语义就是「开火照亮身边」，照墙正是它的本职
	var flash_env := OmniLight3D.new()
	flash_env.name = "flash_env"
	flash_env.light_color = flash.light_color
	flash_env.light_energy = flash.light_energy
	flash_env.omni_range = flash.omni_range
	flash_env.visible = false
	player.cam.add_child(flash_env)
	# viewmodel 补光（2026-10「贴掩体枪身分裂」复发主修，公共链一次修全部枪）：
	# 老的深度吞枪（4f79b10 修的「贴墙枪被深度测试吞掉」）并没有复发——
	# no_depth_test+render_priority10 防线完好，a/b 隐枪差分实测枪模几何全程
	# 完整画出；真因是贴掩体挡掉直射阳光后（707c2f1 光照架构 sun 1.7 vs
	# ambient 0.58、ACES 0.92，直射/环境光比偏大），枪身只剩弱环境光，暗色
	# 段亮度塌到 0-5，读作「前亮后黑两截、被吞」。给枪架挂一盏 viewmodel
	# 专用 OmniLight3D（FPS 标准做法）：挂 holder 原点随枪摆、range 0.9m 只
	# 罩枪模、不开阴影（近距硬阴影会斑驳糊墙）——贴掩体失直射光时保全枪册
	# 可读。四路枪册+旧五枪全走 _mount_slot 此链，不必逐枪打补丁。
	# 第三轮（3562cd3 补光引出新症的根治）：补光只照枪不照墙——3562cd3 解决
	# 了「暗部亮度塌陷」，但 range 0.9m 同时罩住 0.4~0.7m 外的掩体面：贴掩体
	# 时墙上打出大亮斑，ADS 进出/贴墙横移时亮斑随枪扫动、明暗直线分界扫过
	# 视野，读作「枪分成两截」（四枪同档同图案、E8 隐灯即消失的一票定罪；
	# 深度/透明/排序/几何经逐表面审计+全动态矩阵实证全部无病，不动）。
	# 修法 = 补光域隔离：light_cull_mask 收到 render layer 2，挂枪后把 holder
	# 子树全部 MeshInstance3D 并入层 2（见下）。与老防线的关系：4f79b10 材质
	# 防线零改动照常生效（层位与材质的深度测试/优先级互不相干），主相机
	# cull_mask 全开层 2 照常渲染、太阳/环境光 cull 全开枪身照常受光——
	# 三层防线从此各司其职：材质防吞枪、补光保可读、层位防亮斑扫墙。
	var vm_fill := OmniLight3D.new()
	vm_fill.name = "vm_fill"
	vm_fill.light_energy = 0.6
	vm_fill.omni_range = 0.9
	vm_fill.shadow_enabled = false
	vm_fill.light_cull_mask = 1 << 1   # 只作用 render layer 2：掩体面不再被打出亮斑
	holder.add_child(vm_fill)
	# 第四轮（本次架构根治）：枪模整体迁入 own_world_3d 独立视口后，前三层
	# 补丁的病因全部失去载体——vm 世界没有掩体，无「挡直射光塌暗」也无
	# 「补光扫亮墙面」。vm_fill 随 holder 迁入 vm 世界继续照枪；cull_mask
	# 层 2 与枪模入层 2 原样保留（29f/29f+ 回归锁在，且防未来往 vm 世界误
	# 挂世界件时补光漏照）——防线不拆，只是不再被考验
	# 补光域隔离的另一半：枪域全体入层 2（光源 cull mask 按 render layer 匹配，
	# 与节点父子无关）——枪身/镜体/动画匣/枪口火光片一个不漏，vm_fill 照得到
	# 才有意义；_mount_slot 是四路枪册公共链，primary/secondary 天然全覆盖
	for mi_v in holder.find_children("*", "MeshInstance3D", true, false):
		(mi_v as MeshInstance3D).layers |= 1 << 1
	# 消音器：枪口点外接一节哑光黑圆筒（枪架局部沿 -Z），火光/曳光起点前移到筒口
	var muzzle := MUZZLE_OFF + hold_off
	if sup:
		# 消音器挂在枪模真实枪口（最前端截面中心，各枪长短不一；通用 MUZZLE_OFF
		# 只是火光近似点）；筒口成为新的火光/曳光起点
		var mp: Vector3 = _muzzle_point(gun) * GUN_SCALE
		var can := _make_sup_can(1.0)
		can.position = mp + Vector3(0, 0, -SUP_LEN * 0.5 + 0.012)
		can.layers |= 1 << 1
		holder.add_child(can)
		muzzle = mp + Vector3(0, 0, -SUP_LEN)
		flash_mesh.position = muzzle
	var g_pack := {"id": gid, "holder": holder, "mag": mag, "show_mag": show_mag,
			"mag_pos": mag_pos, "mag_size": mag_size, "sup": sup,
			"muzzle_off": muzzle,
			"flash": flash, "flash_env": flash_env, "flash_mesh": flash_mesh,
			"top": top, "cx": cx}
	# 红点镜瞄准线：镜体工厂（_scope_visual reddot 分支）把窗中心 local y 写
	# 进枪模 meta，这里记进枪架信息包 aim_y——update() 的 ADS 终点据此改按
	# 「窗中心过屏幕中心」摆位，HUD 正中的红点分划才落进玻璃窗内。其它瞄具
	# kind 不写 meta、不记此键，沿用枪顶 AABB 公式零改动
	if gun.has_meta("rd_aim_y"):
		# +Δy：meta 是平移前的枪身局部 y（_scope_visual 在平移前写），
		# 补上 HOLD_DELTA 的 y 分量才是平移后窗中心的真实 local y
		g_pack["aim_y"] = float(gun.get_meta("rd_aim_y")) + _hold_delta(gid).y
	_guns[slot] = g_pack


## 全枪册弹匣参数（枪匠契约 mag_of）：返回 {"pos","size","show"} 子集；
## 未知 id 返回空字典——_mount_slot 用 MAG_POS/通用盒/true 兜底。
## 弹匣节点约定：动画弹匣永远是 holder 子节点；「真弹匣形状」由 size/show
## 控制动画匣、由枪身建模件表达静置外形（P90 顶匣/汤姆逊盒匣/手枪匣入握把/
## 霰弹管供弹无盒匣）
func _mag_override(gid: String) -> Dictionary:
	var d: Dictionary = {}
	if _smg_has(gid):
		d = _smg_mag_of(gid)
	elif _ar_has(gid):
		d = _ar_mag_of(gid)
	elif _lmg_has(gid):
		d = _lmg_mag_of(gid)
	elif _old5_has(gid):
		d = _old5_mag_of(gid)
	# 写实枪模弹匣真实位置与程序化版不同时，换弹手锚/掉匣起点跟模型走
	# （mag_hand = 枪身局部握匣点，表内口径 ×GUN_SCALE）
	if _bl_ready(gid) and BL_GUNS[gid].has("mag_hand"):
		d = d.duplicate()
		d["pos"] = Vector3(BL_GUNS[gid]["mag_hand"]) * GUN_SCALE
	return d


## 程序化枪模分发：四路枪册分别到枪身工厂（只造枪身根 Node3D）——冲锋枪册
## _smg_build / 步枪册 _ar_build / 机枪册 _lmg_build / 旧五枪 _old5_build
## （HDGunLib 高模重建，见文件尾「旧五枪高模重建」段；原内联 BoxMesh 直角
## 拼装已整体迁出）。
## 弹匣动画节点/枪口火光仍由 _mount_slot 统一挂、镜体由 _finish_gun 统一挂
## （瞄具挂点常量原样保留，换弹手部锚点与换弹三段时间轴零改动）
func _build_gun_visual(gun_id: String) -> Node3D:
	var root: Node3D
	if _smg_has(gun_id):
		root = _finish_gun(_smg_build(gun_id), gun_id,
				_smg_scope_anchor(gun_id))
	elif _ar_has(gun_id):
		root = _finish_gun(_ar_build(gun_id), gun_id,
				_ar_scope_anchor(gun_id))
	elif _lmg_has(gun_id):
		root = _finish_gun(_lmg_build(gun_id), gun_id,
				_lmg_scope_anchor(gun_id))
	elif _old5_has(gun_id):
		root = _finish_gun(_old5_build(gun_id), gun_id,
				_old5_scope_anchor(gun_id))
	else:
		# 兜底（大战场 lmg 等未列枪）：空枪身 + 默认机瞄位（原行为等值）
		root = _finish_gun(Node3D.new(), gun_id, Vector3(0.085, -0.1, -0.5))
	# 持枪对齐：枪身+镜体整体平移 Δ（见 HOLD_DELTA 表头注释）——握把顶锚
	# 统一落 MK4 基准；镜体随枪同移（scope_anchor 语义不变），AABB 与 ADS
	# 摆位自动含 Δ，枪架局部三锚在 _mount_slot/try_fire 按 Δ×GUN_SCALE 随动
	var d := _hold_delta(gun_id)
	if d != Vector3.ZERO:
		for c in root.get_children():
			(c as Node3D).position += d
	# 一体成型（2026-10 用户定案「重新建模」）：全部零件合并为单 unibody
	# 网格——分件树序绘制的运动接缝被读作「建模分裂」，合并后物理上无件可裂；
	# Δ 平移在合并前完成（烘焙进网格变换），命名锚点由合并器保留。
	# HD_NO_MERGE 环境变量非空 = 跳过合并（A/B 隔离开关：同一探针分别带/
	# 不带该变量各跑一遍，同帧位对比合并前后观感——白环/白球/弹匣浅灰
	# 三疑点排查用；缺省照常合并）
	if OS.get_environment("HD_NO_MERGE") == "":
		GUN_LIB.merge_unibody(root)
	return root


## 枪顶瞄具模型统一收尾：装上的瞄具优先（iron=机瞄片）；狙击自带密位镜，
## 仅装热成像时在镜后加挂热成像单元（onfoot 分支照搬）。
## anchor = (my, mz, fz) 机瞄/镜座挂点（枪身局部）：旧五枪沿用原分支常量、
## 新枪来自枪匠文件 scope_anchor；狙击分支不用 anchor（自带镜例外）
func _finish_gun(root: Node3D, gun_id: String, anchor: Vector3) -> Node3D:
	if root.has_meta("scope_anchor"):   # 写实枪模按自身导轨/安装面重给镜座锚
		anchor = root.get_meta("scope_anchor")
	var sc: Dictionary = _scope_info_for(gun_id)
	var s_kind: String = str(sc.get("kind", "iron"))
	if gun_id == "sniper":
		if s_kind == "thermal":
			_scope_visual(root, "thermal", 0.12, 0.05, -0.3)
	elif s_kind == "iron" and (root.has_meta("real_sights") or PH_GUNS.has(gun_id)
			and root.find_child(str(PH_GUNS[gun_id]["keep"][0]), true, false) != null):
		# 实拍枪自带真实机瞄（准星/照门是模型的一部分），不再叠旧版机瞄片——
		# 叠上去会在枪顶悬一块黑方块；模型缺失回退程序化枪时照常挂
		pass
	elif (gun_id == "mp7" or gun_id == "m14" or gun_id == "asval"
			or gun_id == "k416" or gun_id == "an94" or gun_id == "sr25") \
			and s_kind == "iron":
		# mp7 未装镜不叠 iron 兜底机瞄片：前后机瞄已由枪匠考证建模件承担
		# （竖向护翼圆顶准星 + 亮环觇孔照门，见 _smg_mp7 ④）——首轮判图
		# iron 后照门横条（0.05×0.022 暗块悬浮轨上、无自发光渲染成黑板）
		# 正压在觇孔上读成「无特征纯黑大盒」，故 iron 时跳过；装镜走下方
		# else 照常挂镜体，其余枪分支零改动
		# m14 同例（2026-10 并册）：「大麦粒」柱状准星 + 导轨式照门座带
		# 规正轮/觇孔板为考证建模件（_ar_m14 ⑦⑧），叠 iron 兜底片会悬浮
		# 在枪顶与真实照门叠影
		# asval 同例（2026-10 商店枪）：消音管前抱箍柱形准星（两侧半圆
		# 护翼）+ 机匣前缘凸起座 U 型缺口照门为考证建模件（_ar_asval ③④，
		# 超长瞄准基线），叠 iron 兜底片会与真实照门叠影
		# k416 同例（2026-10 商店枪）：导气座折叠准星 + 轨上折叠觇孔照门为
		# 考证建模件（_ar_k416 ③），叠 iron 兜底片会与真实照门叠影
		# an94 同例（2026-10 商店枪）：制退器后准星座柱形准星（双护耳）+
		# 回转式星形觇孔表尺（五角盘 5 觇孔）为考证建模件（_ar_an94 ③④，
		# 本枪最强识别件），叠 iron 兜底片会悬浮壳顶与星形表尺叠影
		# sr25 同例（2026-10 商店枪）：护木前端折叠立式准星 + 机匣尾轨上
		# 折叠觇孔照门为考证建模件（_ar_sr25 ④，ref_04 特写），叠 iron
		# 兜底片会与真实照门叠影（原厂不带瞄准镜——2026-10-26 用户定案，
		# 改装镜走通用 else 路径）
		pass
	# sr25（2026-10-26 用户定案原厂不带镜——自带 2.5-8 倍镜已从 _ar_sr25 拆除）：
	# iron 走上方建模机瞄分支（不叠兜底片）；改装镜（reddot/holo/optic/thermal）
	# 落到下方 else 通用挂载——2026-10-27 修复：旧版此处有 sr25 pass 分支把
	# 改装镜整段吞掉，开镜只剩 HUD 分划点、无框镜体全无（全枪开镜审计实锤）
	else:
		_scope_visual(root, s_kind, anchor.x, anchor.y, anchor.z)
	return root


## 枪顶瞄具模型：按已装备瞄具风格装镜（iron=机瞄准星片）。
## HUD 分划由别的模块画，这里只管 3D 镜体（onfoot._scope_visual 简化移植）
func _scope_visual(parent: Node3D, kind: String, top_y: float, mid_z: float,
		front_z: float) -> void:
	var mk := func(c: Color, glow := 0.0) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.no_depth_test = true
		m.render_priority = 10
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		return m
	var dk: StandardMaterial3D = mk.call(Color(0.13, 0.14, 0.16))
	var st: StandardMaterial3D = mk.call(Color(0.36, 0.39, 0.44))
	var gm: StandardMaterial3D = mk.call(Color(0.15, 0.55, 0.75), 1.4)
	# 无框红点镜专用：淡青透明玻璃（alpha 0.2 / 双面 / 近镜面反射）+ 自发光红点
	var gl: StandardMaterial3D = mk.call(Color(0.7, 0.95, 0.95, 0.2))
	gl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gl.cull_mode = BaseMaterial3D.CULL_DISABLED
	gl.roughness = 0.05
	gl.metallic = 0.0
	var rd: StandardMaterial3D = mk.call(Color(1.0, 0.16, 0.1), 5.0)
	var box := func(sz: Vector3, pos: Vector3, m: StandardMaterial3D) -> void:
		var bm := BoxMesh.new()
		bm.size = sz
		bm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = pos
		parent.add_child(mi)
	var cyl := func(r: float, h: float, pos: Vector3,
			m: StandardMaterial3D) -> void:
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 10
		cm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.rotation_degrees = Vector3(90, 0, 0)
		mi.position = pos
		parent.add_child(mi)
	# 写实化第五轮：Blender 建模瞄具（tools/blender/guns/optic_*.py，原点 = 镜座
	# 安装面中心，尺寸按枪模同档放大）。红点镜只换镜体，玻璃片/内投影红点/
	# aim_y 仍走下方代码；模型缺失回退原方块版
	var om := _optic_model(kind)
	if om != null:
		om.position = Vector3(0, top_y, mid_z)
		parent.add_child(om)
		if kind != "reddot":
			return
	match kind:
		"holo":
			# 全息镜：方框视窗 + 底座
			box.call(Vector3(0.07, 0.014, 0.014), Vector3(0, top_y + 0.07,
					mid_z - 0.04), dk)
			box.call(Vector3(0.012, 0.06, 0.012), Vector3(-0.034,
					top_y + 0.04, mid_z - 0.04), dk)
			box.call(Vector3(0.012, 0.06, 0.012), Vector3(0.034, top_y + 0.04,
					mid_z - 0.04), dk)
			box.call(Vector3(0.05, 0.018, 0.05), Vector3(0, top_y + 0.02,
					mid_z - 0.04), dk)
		"reddot":
			# 红点镜：大窗无框反射式（FastFire 形态放大窗）——玻璃窗 60×45mm
			# （用户反馈整镜改大：旧 30×24mm 小窗容差太小，瞄准线稍偏红点就
			# 飞出窗外），底托/窄边/投射器/风偏塔按比例跟进。窗顶仍是全镜
			# 最高件（_local_aabb 量顶与 aim_y 换算都依赖这一不变量）；窗中心
			# local y 写进枪模 meta 供 _mount_slot 记 aim_y——ADS 时窗中心过
			# 屏幕中心，HUD 中心红点正落在玻璃窗内（旧裸圆筒+悬浮红点已删）
			# 窗几何（相对镜座挂点 top_y）：底托上沿 24mm 起窗，窗沿 y 24~69mm
			var win_cy := top_y + 0.024 + RD_WIN_H * 0.5   # 窗中心=瞄准线锚点
			var win_z := mid_z - 0.058   # 玻璃面 z（窗变大后略前移，少遮后景）
			if om == null:
				# 导轨适配座：矮盒两层叠出倒角（上层四向缩进），y 0~14mm，随窗加宽
				box.call(Vector3(0.052, 0.007, 0.075), Vector3(0, top_y + 0.0035,
						mid_z - 0.03), dk)
				box.call(Vector3(0.044, 0.007, 0.064), Vector3(0, top_y + 0.0105,
						mid_z - 0.03), dk)
				# 镜体底托：下匣（玻璃下沿插入），y 14~24mm
				box.call(Vector3(0.04, 0.01, 0.064), Vector3(0, top_y + 0.019,
						mid_z - 0.03), dk)
				# 内红点投射器：玻璃后方暗色盒（底托上露头）+ 右侧风偏调节塔
				box.call(Vector3(0.016, 0.012, 0.02), Vector3(0, top_y + 0.026,
						mid_z - 0.032), dk)
				box.call(Vector3(0.008, 0.008, 0.014), Vector3(0.026, top_y + 0.02,
						mid_z - 0.028), dk)
				# 两侧窄边：2.5mm 竖条夹持玻璃左右沿（「无框」仅存的框），比窗顶
				# 矮 2mm——窗顶保持全镜最高（AABB 顶=窗顶的换算前提）
				box.call(Vector3(0.0025, RD_WIN_H - 0.002, 0.008), Vector3(-0.0313,
						win_cy - 0.001, win_z), dk)
				box.call(Vector3(0.0025, RD_WIN_H - 0.002, 0.008), Vector3(0.0313,
						win_cy - 0.001, win_z), dk)
			# 玻璃窗：单片平玻璃 60×45×2mm，淡青透明双面——窗顶即 sight top
			# （全镜无任何件高于玻璃）
			box.call(Vector3(RD_WIN_W, RD_WIN_H, 0.002), Vector3(0, win_cy,
					win_z), gl)
			# 内投影红点：5mm 自发光红球嵌在玻璃面中心（窗中心=瞄准线，
			# ADS 后与 HUD 分划点/屏幕准星三点一线），随窗稍放大
			var dot := SphereMesh.new()
			dot.radius = 0.0025
			dot.height = 0.005
			dot.radial_segments = 8
			dot.rings = 4
			dot.material = rd
			var dot_mi := MeshInstance3D.new()
			dot_mi.mesh = dot
			dot_mi.position = Vector3(0, win_cy, win_z)
			parent.add_child(dot_mi)
			# 窗中心 local y 写 meta：_mount_slot 据此记 aim_y（只 reddot 写）
			parent.set_meta("rd_aim_y", win_cy)
		"optic":
			# 3.5× 光学镜：镜身 + 大物镜 + 双固定座
			cyl.call(0.03, 0.15, Vector3(0, top_y + 0.06, mid_z - 0.12), dk)
			cyl.call(0.038, 0.03, Vector3(0, top_y + 0.06, mid_z - 0.21), st)
			box.call(Vector3(0.02, 0.045, 0.03), Vector3(0, top_y + 0.025,
					mid_z - 0.1), dk)
			box.call(Vector3(0.02, 0.045, 0.03), Vector3(0, top_y + 0.025,
					mid_z - 0.17), dk)
		"sniper":
			# 5× 密位镜：长镜身 + 大物镜 + 目镜 + 双固定座
			cyl.call(0.037, 0.2, Vector3(0, top_y + 0.065, mid_z - 0.12), dk)
			cyl.call(0.048, 0.035, Vector3(0, top_y + 0.065, mid_z - 0.23), st)
			cyl.call(0.028, 0.06, Vector3(0, top_y + 0.065, mid_z), st)
			box.call(Vector3(0.02, 0.05, 0.03), Vector3(0, top_y + 0.025,
					mid_z - 0.08), dk)
			box.call(Vector3(0.02, 0.05, 0.03), Vector3(0, top_y + 0.025,
					mid_z - 0.18), dk)
		"thermal":
			# 热成像镜：方形镜体 + 前端传感窗（发光）+ 侧向按键组
			box.call(Vector3(0.075, 0.095, 0.2), Vector3(0, top_y + 0.07,
					mid_z - 0.08), dk)
			box.call(Vector3(0.058, 0.05, 0.018), Vector3(0, top_y + 0.07,
					mid_z - 0.19), gm)
			box.call(Vector3(0.03, 0.05, 0.04), Vector3(0.048, top_y + 0.05,
					mid_z), dk)
		_:
			# 机瞄：前准星片 + 后照门
			box.call(Vector3(0.012, 0.05, 0.012), Vector3(0, top_y + 0.025,
					front_z), dk)
			box.call(Vector3(0.05, 0.022, 0.022), Vector3(0, top_y + 0.03,
					mid_z + 0.08), dk)


## 当前枪的瞄具信息：main 的 scope_provider 优先；未装镜回退枪自带
## builtin_scope（狙击原厂镜）；都没有 = 显式机瞄 iron/1.0——
## 非狙击枪绝不自带倍率（问题①：FOV 与分划只在装了镜时才允许缩放）
func _scope_info_for(gun_id: String) -> Dictionary:
	var sc := {}
	if scope_provider != null and scope_provider.is_valid():
		sc = scope_provider.call(gun_id)
	if sc.is_empty():
		var gi: Dictionary = Guns.gun_by_id(gun_id)
		if gi.has("builtin_scope"):
			sc = gi["builtin_scope"]
	if sc.is_empty():
		sc = {"kind": "iron", "zoom": 1.0}   # 机瞄兜底：无镜无倍率
	return sc


## 子网格在 gun 本地空间的合并包围盒（不依赖是否已入场景树）
func _local_aabb(gun: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var t := Transform3D()
		var p: Node = m
		while p != gun and p != null:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		var a: AABB = t * m.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## ---------------- 内部：弹匣掉落 / 火花 / 特效节拍 ----------------


## 曳光弹配置（main 建池传入）+ 命中火花对象池（onfoot 同款）
func _setup_fx() -> void:
	if tracers == null:
		return
	tracers.setup(24, Color(1.0, 0.8, 0.4), 4.0, 0.02)
	tracers.on_arrive = _spawn_impact   # 火花等曳光飞到才出
	if tracers.get_parent() == null:
		add_child(tracers)
	var imat := StandardMaterial3D.new()
	imat.albedo_color = Color(1.0, 0.75, 0.3)
	imat.emission_enabled = true
	imat.emission = Color(1.0, 0.6, 0.2)
	imat.emission_energy_multiplier = 3.0
	var imesh := SphereMesh.new()
	imesh.radius = 0.05
	imesh.height = 0.1
	imesh.material = imat
	for i in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = imesh
		mi.visible = false
		add_child(mi)
		_im_pool.append({"mi": mi, "t": 0.0})


func _spawn_impact(p: Vector3) -> void:
	var slot: Dictionary = _im_pool[_im_i]
	_im_i = (_im_i + 1) % _im_pool.size()
	slot["mi"].global_position = p
	slot["mi"].visible = true
	slot["t"] = 0.24


## 旧弹匣脱匣：从枪身弹匣井（手部拔匣的脱离点）转入主世界空间下坠，
## 初速 = 枪前向 0.8 + 向下 0.4。
## 世界空间件去留审计：掉落匣要落地贴地（world.ground_height）并留在战场
## 4s——留主世界（本节点子节点）；起跳点用 holder.to_global 取「主世界坐标」
## （sync_vm 不变量：vm 世界的 to_global 数值=主世界坐标），与动画匣无缝衔接
func _drop_mag() -> void:
	_ensure_falling_mag()
	var g := _cur_gun()
	var mag_pos: Vector3 = MAG_POS
	var mag_size: Vector3 = Vector3(0.055, 0.17, 0.09)
	if not g.is_empty():
		mag_pos = g.get("mag_pos", MAG_POS)
		mag_size = g.get("mag_size", mag_size)
		# 弹匣井下方一点脱手：与世界空间掉落替身衔接手部拔匣动画
		_falling_mag.global_position = (g["holder"] as Node3D).to_global(
				mag_pos + Vector3(0.0, -0.06, 0.0))
	else:
		_falling_mag.global_position = player.cam.to_global(Vector3(0.02, -0.16, -0.3))
	# 相机 -Z = 枪口方向（basis.z 朝身后，取负才是前抛）
	_falling_vel = -player.cam.global_transform.basis.z * 0.8 + Vector3(0, -0.4, 0)
	# 掉落匣替身按该枪真实弹匣尺寸近似缩放（基准盒 0.055×0.17×0.09）
	_mag_scale = Vector3(mag_size.x / 0.055, mag_size.y / 0.17, mag_size.z / 0.09)
	_falling_mag.scale = _mag_scale
	_falling_mag.visible = true
	_mag_landed = false


## 掉落弹匣替身：queue_free 后惰性重建（每次换弹一颗，不常驻浪费）
func _ensure_falling_mag() -> void:
	if _falling_mag != null:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.055, 0.17, 0.09)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.22)
	box.material = mat
	_falling_mag = MeshInstance3D.new()
	_falling_mag.mesh = box
	_falling_mag.visible = false
	# 层 2 位保留（29f+ 回归口径一致）：补光已随枪迁入 vm 世界、照不到主世
	# 界的它，落地后由主世界日光/ambient/枪口闪光镜像灯（flash_env）照明
	_falling_mag.layers |= 1 << 1
	add_child(_falling_mag)


## 换弹手部替身：暗色战术手套低模（护腕 + 掌 + 四指各两节 + 拇指两节，
## BoxMesh 拼装），挂 vm 相机下与枪架同级同世界；材质关深度测试同枪模；
## 懒重建（同掉落弹匣思路），仅换弹期间可见
func _ensure_hand() -> void:
	if _hand != null or player == null or player.vm_cam == null:
		return
	_hand = _build_hand()
	player.vm_cam.add_child(_hand)


## 手套构造（不入树、默认隐身）：暗色战术手套低模（护腕 + 掌 + 四指各两节
## + 拇指两节，BoxMesh 拼装），材质关深度测试同枪模——换弹手（_hand）专用
func _build_hand() -> Node3D:
	var hand := Node3D.new()
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.15, 0.16, 0.18)
	glove.roughness = 0.85
	glove.no_depth_test = true
	glove.render_priority = 10
	glove.emission_enabled = true
	glove.emission = Color(0.19, 0.2, 0.22)
	glove.emission_energy_multiplier = 0.55
	var cuff := StandardMaterial3D.new()
	cuff.albedo_color = Color(0.1, 0.11, 0.13)
	cuff.roughness = 0.9
	cuff.no_depth_test = true
	cuff.render_priority = 10
	cuff.emission_enabled = true
	cuff.emission = Color(0.13, 0.14, 0.16)
	cuff.emission_energy_multiplier = 0.55
	var add := func(sz: Vector3, pos: Vector3, rot_deg: Vector3,
			mat: Material) -> void:
		var bm := BoxMesh.new()
		bm.size = sz
		bm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = pos
		mi.rotation_degrees = rot_deg
		mi.layers |= 1 << 1   # 入补光层 2（与枪模同层）：vm_fill 只照层 2，换弹手才被照到
		hand.add_child(mi)
	# 手部局部坐标：四指朝 -Z 伸展、拇指在 +X 侧；握匣姿态的整体转角
	# 由 _update_reload_hand 按 prog 控制
	add.call(Vector3(0.085, 0.05, 0.055), Vector3(0, -0.006, 0.095), Vector3.ZERO, cuff)
	add.call(Vector3(0.07, 0.04, 0.05), Vector3(0, 0.0, 0.05), Vector3.ZERO, glove)
	add.call(Vector3(0.072, 0.026, 0.09), Vector3(0, 0.0, -0.012), Vector3.ZERO, glove)
	# 四指：食指到小指各两节 [x 偏移, 近节长, 末节长]，指节微勾（握匣姿态）
	var fingers: Array = [[0.027, 0.043, 0.03], [0.009, 0.045, 0.032],
			[-0.009, 0.042, 0.03], [-0.027, 0.034, 0.026]]
	for f in fingers:
		var fx: float = float(f[0])
		var l1: float = float(f[1])
		var l2: float = float(f[2])
		add.call(Vector3(0.016, 0.02, l1), Vector3(fx, -0.002, -0.057 - l1 * 0.5),
				Vector3(12, 0, 0), glove)
		add.call(Vector3(0.0145, 0.018, l2), Vector3(fx, 0.01, -0.055 - l1 - l2 * 0.5),
				Vector3(34, 0, 0), glove)
	# 拇指：自掌侧斜前包扣两节
	add.call(Vector3(0.019, 0.02, 0.048), Vector3(0.043, 0.008, -0.03),
			Vector3(0, 25, 12), glove)
	add.call(Vector3(0.016, 0.018, 0.032), Vector3(0.026, 0.018, -0.068),
			Vector3(0, 48, 20), glove)
	hand.visible = false
	return hand


func _hide_hand() -> void:
	if _hand != null:
		_hand.visible = false



## 换弹手部动画：按换弹进度 prog 分五段插值（照 _reload_off/_reload_rot 的
## 关键帧模式，不引入新状态机）。锚点取枪上弹匣节点（to_global 转世界坐标，
## 位移偏移为枪架局部），枪体换弹下探/倾斜时手自动跟随；
## ≥3× 开镜到位藏枪时手同步隐藏（不悬空）
func _update_reload_hand(prog: float) -> void:
	_ensure_hand()
	if _hand == null:
		return
	var g := _cur_gun()
	if g.is_empty():
		_hide_hand()
		return
	var holder: Node3D = g["holder"]
	if not holder.visible:
		_hide_hand()
		return
	var mag: MeshInstance3D = g["mag"]
	var hand_off: Vector3
	var hand_rot: Vector3
	if prog < HAND_GRIP_T:
		# 入画：从画面右下伸向弹匣（0.15 前保持隐藏，只在画面外摆位）
		var k := clampf((prog - HAND_IN_T) / (HAND_GRIP_T - HAND_IN_T), 0.0, 1.0)
		hand_off = HAND_ENTRY_OFF.lerp(HAND_GRIP_OFF, k)
		hand_rot = Vector3(8.0, -10.0, 6.0).lerp(Vector3(2.0, 0.0, 2.0), k)
	elif prog < HAND_OUT_T:
		# 握匣下拉拔出：跟旧匣一起向下抽（旧匣 0.25 起转世界空间坠地），
		# 末段手腕外翻甩开
		var k := clampf((prog - HAND_GRIP_T) / (HAND_OUT_T - HAND_GRIP_T), 0.0, 1.0)
		hand_off = HAND_GRIP_OFF.lerp(HAND_PULL_OFF, k)
		hand_rot = Vector3(2.0, 0.0, 2.0).lerp(Vector3(-14.0, 0.0, -12.0), k)
	elif prog < HAND_NEW_T:
		# 弃旧取新：从画面下方把新匣托举上抬到弹匣井正下（与新匣滑入同步）
		var k := clampf((prog - HAND_OUT_T) / (HAND_NEW_T - HAND_OUT_T), 0.0, 1.0)
		hand_off = HAND_PULL_OFF.lerp(HAND_HOLD_OFF, k)
		hand_rot = Vector3(-14.0, 0.0, -12.0).lerp(Vector3(4.0, 0.0, 2.0), k)
	elif prog < HAND_SEAT_T:
		# 对准弹匣井插入拍合：掌心贴匣底跟压到位
		var k := clampf((prog - HAND_NEW_T) / (HAND_SEAT_T - HAND_NEW_T), 0.0, 1.0)
		hand_off = HAND_HOLD_OFF.lerp(HAND_GRIP_OFF + Vector3(0.0, -0.015, 0.01), k)
		hand_rot = Vector3(4.0, 0.0, 2.0)
	else:
		# 离场回位：向下收回画面外（0.97 提前隐手，先于换弹结束）
		var k := clampf((prog - HAND_SEAT_T) / (HAND_HIDE_T - HAND_SEAT_T), 0.0, 1.0)
		hand_off = (HAND_GRIP_OFF + Vector3(0.0, -0.015, 0.01)).lerp(HAND_ENTRY_OFF, k)
		hand_rot = Vector3(4.0, 0.0, 2.0).lerp(Vector3(8.0, -10.0, 6.0), k)
	_hand.visible = prog >= HAND_IN_T and prog < HAND_HIDE_T
	_hand.global_position = mag.to_global(hand_off)
	_hand.rotation_degrees = hand_rot


func _tick_fx(dt: float) -> void:
	if tracers != null:
		tracers.tick(dt)
	for s in _im_pool:
		if float(s["t"]) > 0.0:
			s["t"] = float(s["t"]) - dt
			if float(s["t"]) <= 0.0:
				s["mi"].visible = false
	# 掉落弹匣：重力下坠 + 前抛 + 旋转，落地贴地停住，4s 后缩隐并回收
	if _falling_mag != null and _falling_mag.visible:
		if not _mag_landed:
			_falling_vel.y -= 9.8 * dt
			_falling_mag.position += _falling_vel * dt
			_falling_mag.rotation_degrees.z += 140.0 * dt
			if world != null:
				var gy: float = float(world.ground_height(
						_falling_mag.global_position.x,
						_falling_mag.global_position.z))
				if _falling_mag.global_position.y <= gy + 0.05:
					_falling_mag.global_position.y = gy + 0.05
					_mag_landed = true
					_mag_rest_t = MAG_REST_T
		else:
			_mag_rest_t -= dt
			if _mag_rest_t < 0.5:
				# 渐隐：末 0.5s 缩小到消失（材质不动，免引透明管线；
				# 乘 _mag_scale 保持该枪弹匣长宽比，不闪变通用盒）
				var k := clampf(_mag_rest_t / 0.5, 0.0, 1.0)
				_falling_mag.scale = _mag_scale * maxf(k, 0.01)
			if _mag_rest_t <= 0.0:
				_falling_mag.queue_free()
				_falling_mag = null
				_mag_landed = false
				_falling = false
	# 手部兜底：非换弹帧（死亡/切枪/进场重置）强制隐藏，防手套悬空残留
	if _hand != null and _hand.visible:
		if reloading <= 0.0 or player == null or player.dead:
			_hand.visible = false

## ================= 枪匠·七枪程序化模型（原独立文件并入） =================
## 原并行交付为 hd_gun_smg.gd / hd_gun_ar.gd 两份独立脚本，但回归门槛的执行
## 快照只携带 git 跟踪文件——未跟踪新文件在门槛侧不存在，class_name 全局名
## （要等编辑器重扫类缓存）与 preload 路径引用都会编译失败（两次 420s 挂起的
## 根因）。并入本文件（git 已跟踪）后：零新文件、零全局名依赖、零类缓存依赖。
## 导出契约不变：has/build/mag_of/scope_anchor 四函数语义与签名逐字保留，
## 仅加 _smg_/_ar_ 前缀防与旧五枪装配链重名。几何/材质数值未动一字。
## 高模工具库（倒角盒/螺纹枪管/圆护木/环件/握把/弧匣）：路径 preload 引用，
## 不走裸全局名（新文件 + class_name 全局名曾两次挂门槛——见本段头注释）；
## 材质走传参注入，_smg_mats 工厂仍是唯一材质出处。
## 步枪册三枪（m4a1/akm/scarh）高模几何体在 hd_gun_ar.gd（AR_LIB 路径
## preload，_ar_build 签名逐字不变只转发）——同 hd_gunlib 先例：新文件必须
## 随收尾提交入库，否则门槛快照 preload 会失(FILE)
const GUN_LIB := preload("res://scripts/hd_gunlib.gd")
const AR_LIB := preload("res://scripts/hd_gun_ar.gd")
const LMG_LIB := preload("res://scripts/hd_gun_lmg.gd")   # 机枪册几何体（同 AR_LIB 先例：新文件必须随收尾提交入库）

## 持枪对齐（2026-10 用户反馈「每把枪拿起来都不对齐，只有 MK4 对」）：各枪匠
## 建模时握把顶锚（GUN_LIB.grip 的 pos，枪身局部）落点五花八门——z 从 -0.044
## （MP5）到 +0.130（汤姆逊）散布 17cm，而枪架锚 GUN_HIP_POS 全枪册共用，
## 握把离锚点越远枪在手里的前后/高低错位越大。修法：_build_gun_visual 出厂时
## 把枪身全部子节点平移 Δ，让每把枪的握把顶锚统一落到 MK4 基准
## (0, -0.022, -0.0018)（用户认可的唯一样板，故 mk4 条目为零向量）。
## Δ = 基准 − 各枪握把顶锚（枪身局部；各枪匠工厂原坐标零改动）。
## 枪架局部消费的三处锚随动（×GUN_SCALE 换算）：_mount_slot 弹匣锚 /
## 枪口火光与曳光（MUZZLE_OFF → 每槽 muzzle_off）/ 红点镜 aim_y（枪身局部
## 直接加 Δy）。AABB（_local_aabb 量子节点）自动含 Δ，ADS 摆位自洽。
const HOLD_DELTA := {
	"mk4": Vector3.ZERO,
	"mp5": Vector3(0, -0.0028, 0.0421),
	"p90": Vector3(0, 0.0274, -0.0464),
	"uzi": Vector3(0, 0.0023, -0.0692),
	"vector": Vector3(0, -0.0021, -0.0035),
	"m4a1": Vector3(0, 0.0087, -0.0718),
	"akm": Vector3(0, -0.0055, -0.1008),
	"scarh": Vector3(0, 0.0081, -0.0623),
	"m250": Vector3(0, 0.0280, -0.0718),
	# mp7 精算：Δ = MK4 基准 (0,-0.022,-0.0018) − _smg_mp7 握把顶锚
	# grip(pos=(0,-0.042,0.028)) = (0, -0.022+0.042, -0.0018-0.028)
	"mp7": Vector3(0, 0.020, -0.0298),
	# m14 精算：Δ = MK4 基准 (0,-0.022,-0.0018) − _ar_m14 握把顶锚
	# grip(pos=(0,-0.028,0.155)) = (0, -0.022+0.028, -0.0018-0.155)
	"m14": Vector3(0, 0.006, -0.1568),
	# asval 精算：Δ = MK4 基准 (0,-0.022,-0.0018) − _ar_asval 握把顶锚
	# grip(pos=(0,-0.028,0.075)) = (0, -0.022+0.028, -0.0018-0.075)
	"asval": Vector3(0, 0.006, -0.0768),
	# k416 精算：Δ = MK4 基准 (0,-0.022,-0.0018) − _ar_k416 握把顶锚
	# grip(pos=(0,-0.030,0.075)) = (0, -0.022+0.030, -0.0018-0.075)
	"k416": Vector3(0, 0.008, -0.0768),
	# an94 精算：Δ = MK4 基准 (0,-0.022,-0.0018) − _ar_an94 握把顶锚
	# grip(pos=(0,-0.030,0.075)) = (0, -0.022+0.030, -0.0018-0.075)
	"an94": Vector3(0, 0.008, -0.0768),
	# sr25 精算：Δ = MK4 基准 (0,-0.022,-0.0018) − _ar_sr25 握把顶锚
	# grip(pos=(0,-0.030,0.075)) = (0, -0.022+0.030, -0.0018-0.075)
	# （AR 式握把与 k416/an94 同锚）
	"sr25": Vector3(0, 0.008, -0.0768),
	"pistol": Vector3(0, -0.0263, -0.0348),
	"smg": Vector3(0, 0.0190, -0.1321),
	"rifle": Vector3(0, 0.0090, -0.0690),
	"shotgun": Vector3(0, -0.0244, -0.1224),
	"sniper": Vector3(0, -0.0346, -0.0837),
}


## 持枪平移量（未知枪/兜底 = 零向量，行为同旧）
static func _hold_delta(gid: String) -> Vector3:
	if HOLD_DELTA.has(gid):
		return HOLD_DELTA[gid]
	return Vector3.ZERO

const SMG_IDS := ["mp5", "p90", "uzi", "vector", "mk4", "mp7"]


## 是否冲锋枪册枪型（_build_gun_visual 分发用）
static func _smg_has(id: String) -> bool:
	return SMG_IDS.has(id)


## 统一入口：只造「枪身根」（Node3D + 若干 MeshInstance3D 子节点）。
## 未知 id 返回空 Node3D（防御不崩）
static func _smg_build(id: String) -> Node3D:
	var bl := _bl_gun(id)
	if bl != null:
		return bl
	match id:
		"mp5":
			return _smg_mp5()
		"p90":
			return _smg_p90()
		"uzi":
			return _smg_uzi()
		"vector":
			return _smg_vector()
		"mk4":
			return _smg_mk4()
		"mp7":
			return _smg_mp7()
	return Node3D.new()


## 弹匣动画节点覆盖（hd_guns 枪架局部坐标 = 枪身局部 × GUN_SCALE≈0.62 换算）：
## pos=拔匣/插匣/掉匣锚点（换弹手沿 mag.to_global 链自动跟随）、
## size=动画盒尺寸、show=动画盒是否显示；缺省键由 hd_guns 用
## MAG_POS/通用盒/true 兜底。静置弹匣外形（弯月匣/顶匣）由枪身建模件表达。
static func _smg_mag_of(id: String) -> Dictionary:
	match id:
		"mp5":
			## 弯月匣是枪身建模件（mag_curved 三段斜接弧），动画匣隐、
			## 手锚弹匣井正下（直盒无法表达 9mm 下弯弧线，照 P90 顶匣先例）
			return {"pos": Vector3(0.02, -0.13, -0.13),
					"size": Vector3(0.048, 0.17, 0.075), "show": false}
		"p90":
			## 顶匣是枪身建模件（mag_top），动画匣隐、换弹手锚自动到顶部
			return {"pos": Vector3(0.02, 0.06, -0.06),
					"size": Vector3(0.05, 0.05, 0.30), "show": false}
		"uzi":
			## 匣插手枪握把内：x 对中握把中轴（0.02 偏移会让匣挂出握把侧），
			## y 下移到匣顶恰贴机匣底起垂（防 no_depth_test 动画盒上段
			## 叠画进机匣面——握把与匣同色 maggrey 弱化嵌入接缝）
			return {"pos": Vector3(0.0, -0.115, 0.05),
					"size": Vector3(0.045, 0.20, 0.07), "show": not _bl_ready(id)}
		"vector":
			## 匣入大后倾斜握把：同上对中+贴机匣底（竖直动画匣 vs 斜握把
			## 的小错位为低模已知取舍）
			return {"pos": Vector3(0.0, -0.105, 0.01),
					"size": Vector3(0.05, 0.18, 0.07), "show": not _bl_ready(id)}
		"mk4":
			## 4.6×30 直弹匣（微弧）：真匣是枪身建模件（mag_straight 独立命名
			## 节点 + HDGunLib.curved_mag 三段 7° 微弧），动画匣隐（同 MP5/P90
			## 「匣形由枪身件表达」先例）；pos/size 保留 = 换弹手锚与掉匣
			## 替身缩放沿用原值（契约机制不变，只切 show）
			## 2026-10 对位修正：匣顶中心 z -0.075→-0.115 前移 40mm 对中弹匣井
			## （井心 z=-0.115，原匣顶后缘越井后缘 36.5mm、扳机埋匣），与
			## mag_straight 建模件同步
			return {"pos": Vector3(0.0, -0.135, -0.115),
					"size": Vector3(0.042, 0.2, 0.068), "show": false}
		"mp7":
			## 4.6×30 半透明短直匣（微前倾）：真匣是枪身建模件（mag_pdw 独立
			## 命名节点 + curved_mag 直匣 + 浅灰刻度条/圆点观察窗，匣体从握把
			## 底板下方出露、6° 前倾），动画匣隐（同 MK4「匣形由枪身件表达」
			## 先例）；pos=换弹手锚（握把下段沿匣抓握点，枪身局部
			## (0,-0.23,0.052)×0.62）、size=掉匣替身缩放基准（=匣外形参数）
			return {"pos": Vector3(0.0, -0.143, 0.032),
					"size": Vector3(0.034, 0.195, 0.054), "show": false}
	return {}


## 机瞄/镜座挂点 (my, mz, fz)（枪身局部，喂 hd_guns._scope_visual；
## my 对齐各枪最高件下沿附近——开镜 AABB 量顶不悬空）
static func _smg_scope_anchor(id: String) -> Vector3:
	match id:
		"mp5":
			## 机匣顶 0.059 / 照门鼓顶 0.095，视线贴机匣顶面
			return Vector3(0.06, -0.04, -0.40)
		"p90":
			## 顶匣顶 0.099 / 原厂镜骑匣尾上方
			return Vector3(0.10, 0.02, -0.12)
		"uzi":
			## 机匣顶 0.068 / 准星护圈耳顶 0.108
			return Vector3(0.07, -0.02, -0.18)
		"vector":
			## 顶轨齿顶 0.089 / 尾部质量块顶 0.118
			return Vector3(0.09, -0.04, -0.14)
		"mk4":
			## 全长顶轨齿顶 0.077 / 后折叠照门片顶 0.10
			return Vector3(0.075, -0.10, -0.42)
		"mp7":
			## 分段顶轨齿顶 0.056 / 机匣中后段（拉机柄槽后）/ 轨前准星座
			return Vector3(0.054, -0.05, -0.268)
	return Vector3(0.085, -0.1, -0.5)


## 黑克勒-科赫 MP5A2（9×19mm，约800rpm）——考证特征逐条（HDGunLib 高模重建：
## 顶点 798 → ≈9.6k，≥8× 红线见 HDGunLib.POLY_MIN["mp5"]；按 90/柱 真基线
## 996 复核 = 7968 亦过）：
## ① 纤细黑色机匣：全枪册最窄（宽 0.048）的管状长方机匣，贯通全枪
##    （倒角盒 s12——直角棱线消除、棱线高光顺滑）
## ② 弯月形 30 发弹匣：mag_curved 独立命名节点 + curved_mag 三段 14° 累进
##    （竖直段→14°→28°，弧向前，9mm 标志曲线、弧度小于 AKM；s8 倒角段面
##    ——弯月匣是本枪主角件）
## ③ A2 固定聚合物枪托：黑色实心托、侧影后段下斜三角 + 贴腮垫 + 托底
##    吊环槽（与汤姆逊木托颜色+质感双区分）
## ④ 圆筒形 clamshell 护木：tube 圆管开筒（seg48、内衬探出露壁厚）+
##    双肋环 torus + 前端准星护圈座环 torus——本作唯一圆护木冲锋枪
##    （汤姆逊横方木 / Vector 方轨）
## ⑤ 鼓式转轮照门：底座 + 横置圆柱小鼓（高分段封闭柱）+ 左侧调节钮 +
##    环形准星座（双柱+顶梁+准星柱，落座环上）
## ⑥ 短圆柱枪口帽（三瓣式固定帽）：开筒帽（内衬亮钢膛）+ 前挡环/后螺纹
##    肩双 torus——帽肩读作三瓣螺纹座、枪管微出
## ⑦ 机匣左侧 45° 斜置小拉机柄（凸块+柄杆）+ 拉机柄槽暗条 + 右侧抛壳窗
##    亮钢板
static func _smg_mp5() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var blued: StandardMaterial3D = mats["blued"]
	var steel: StandardMaterial3D = mats["steel"]
	var polymer: StandardMaterial3D = mats["polymer"]
	# ① 机匣主管（宽 0.048 全册最窄）+ 机匣尾封（接托）——倒角盒
	GUN_LIB.chamfer_box(root, blued, Vector3(0.048, 0.078, 0.34),
			Vector3(0, 0.02, -0.04), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, blued, Vector3(0.046, 0.07, 0.05),
			Vector3(0, 0.015, 0.15), Vector3.ZERO, 0.002, 6)
	# ④ 圆筒 clamshell 护木（seg48 开筒 + 内衬露壁厚；外径 0.074 同旧模
	#    r0.037）+ 双肋环（torus 凸环，环顶 0.0405 同旧模 r0.039+凸量）
	GUN_LIB.tube(root, polymer, 0.17, 0.074, Vector3(0, 0.02, -0.295),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 48)
	GUN_LIB.torus_ring(root, polymer, 0.0345, 0.0405, Vector3(0, 0.02, -0.25),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, polymer, 0.0345, 0.0405, Vector3(0, 0.02, -0.335),
			Vector3(90, 0, 0))
	# ⑤ 护木前端准星护圈座环（torus——「环形准星座」的环，双柱落环上）
	GUN_LIB.torus_ring(root, polymer, 0.034, 0.041, Vector3(0, 0.02, -0.363),
			Vector3(90, 0, 0))
	# ⑥ 枪管微出（高分段封闭柱，口径 0.022 同旧模 r0.011）+ 三瓣式固定帽
	#    （外径 0.032 开筒内衬亮钢膛 + 前挡环/后螺纹肩双 torus）
	GUN_LIB.barrel(root, steel, 0.05, 0.022, Vector3(0, 0.02, -0.415),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.tube(root, blued, 0.04, 0.032, Vector3(0, 0.02, -0.405),
			Vector3(90, 0, 0), 0.003, 0, steel, 3, 32)
	GUN_LIB.torus_ring(root, steel, 0.013, 0.018, Vector3(0, 0.02, -0.422),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, steel, 0.0135, 0.0185, Vector3(0, 0.02, -0.389),
			Vector3(90, 0, 0))
	# ③ A2 固定聚合物托：上段平接机匣 → 下斜段（后端下垂的三角侧影）→
	#    托底板 + 贴腮垫 + 托底吊环槽
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.044, 0.062, 0.09),
			Vector3(0, 0.028, 0.175), Vector3.ZERO, 0.0025, 6)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.042, 0.105, 0.12),
			Vector3(0, -0.012, 0.24), Vector3(12, 0, 0), 0.003, 8)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.046, 0.11, 0.014),
			Vector3(0, -0.052, 0.295), Vector3.ZERO, 0.0015, 4)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.04, 0.01, 0.075),
			Vector3(0, 0.062, 0.185), Vector3.ZERO, 0.001, 3)
	GUN_LIB.chamfer_box(root, blued, Vector3(0.03, 0.004, 0.012),
			Vector3(0, -0.109, 0.24), Vector3.ZERO, 0.0008, 2)
	# 后握把（护圈正后方、后倾 18°——真实 MP5 握把角）：grip() 顶锚=旋转
	# 支点，旧 _add_grip 中心锚迁移用矢量式（含 z）：pos = 旧盒心
	# (0,-0.062,-0.03) + Rx(-18°)·(0,0.045,0) = (0, -0.0192, -0.0439)
	GUN_LIB.grip(root, polymer, 0.09, Vector3(0, -0.0192, -0.0439), 18.0,
			0.036, 0.052, steel)
	GUN_LIB.chamfer_box(root, blued, Vector3(0.01, 0.008, 0.07),
			Vector3(0, -0.118, -0.055), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.026, 0.008),
			Vector3(0, -0.098, -0.045), Vector3.ZERO, 0.001, 4)
	# ② 弹匣井（机匣底前缘）+ 弯月匣（独立命名节点 mag_curved：curved_mag
	# 三段 14° 累进、s8 倒角段面，弧线向前弯——竖直段→14°→28°）
	GUN_LIB.chamfer_box(root, blued, Vector3(0.04, 0.04, 0.11),
			Vector3(0, -0.04, -0.155), Vector3.ZERO, 0.002, 6)
	var mag_c := Node3D.new()
	mag_c.name = "mag_curved"
	mag_c.position = Vector3(0, -0.0625, -0.155)   # 段1中心落旧位 (0,-0.105,-0.155)
	root.add_child(mag_c)
	GUN_LIB.curved_mag(mag_c, blued, Vector3(0.05, 0.255, 0.108), 14.0, 3, 8)
	# ⑤ 鼓式转轮照门：底座 + 横置圆柱小鼓（高分段封闭柱）+ 左侧调节钮
	GUN_LIB.chamfer_box(root, blued, Vector3(0.026, 0.018, 0.045),
			Vector3(0, 0.068, 0.075), Vector3.ZERO, 0.0012, 4)
	GUN_LIB.barrel(root, blued, 0.024, 0.034, Vector3(0, 0.078, 0.075),
			Vector3(0, 0, 90), 0, 24)
	GUN_LIB.barrel(root, steel, 0.014, 0.012, Vector3(-0.019, 0.078, 0.075),
			Vector3(0, 0, 90), 0, 16)
	# ⑤ 环形准星座（落护木前端座环上：双柱 + 顶梁 + 准星柱）
	GUN_LIB.chamfer_box(root, blued, Vector3(0.007, 0.036, 0.01),
			Vector3(0.015, 0.062, -0.36), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, blued, Vector3(0.007, 0.036, 0.01),
			Vector3(-0.015, 0.062, -0.36), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, blued, Vector3(0.037, 0.007, 0.01),
			Vector3(0, 0.0825, -0.36), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.02, 0.005),
			Vector3(0, 0.0715, -0.36), Vector3.ZERO, 0.0008, 4)
	# ⑤ 右侧抛壳窗亮钢板（MP5 抛壳口）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.024, 0.07),
			Vector3(0.0255, 0.028, -0.02), Vector3.ZERO, 0.0008, 3)
	# ⑦ 机匣左侧 45° 斜置拉机柄（凸块 + 柄杆，x 负 = 左侧）+ 拉机柄槽暗条
	GUN_LIB.chamfer_box(root, steel, Vector3(0.016, 0.014, 0.02),
			Vector3(-0.03, 0.048, -0.03), Vector3(0, 0, 45), 0.001, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.012, 0.009, 0.035),
			Vector3(-0.036, 0.042, -0.075), Vector3(0, 0, 45), 0.001, 4)
	GUN_LIB.chamfer_box(root, blued, Vector3(0.004, 0.008, 0.09),
			Vector3(-0.0245, 0.045, -0.055), Vector3.ZERO, 0.0008, 2)
	return root


## FN P90（5.7×28mm PDW）——考证特征逐条（HDGunLib 高模重建：顶点 555 →
## ≈6.9k，≥8× 红线见 HDGunLib.POLY_MIN["p90"]；按 90/柱 真基线 654 复核
## = 5232 亦过）：
## ① 无托布局：全长最短（枪身 0.48），机匣与弹匣后置、无枪托、尾部圆滑收
##    （外壳四段全倒角盒 s8——流线圆角壳体）
## ② 顶置 50 发长弹匣：mag_top 独立命名节点（主匣 s8 + 顶冠条 + 前斜头 +
##    尾收头 + 两侧纵槽——浅灰烟色、与壳等宽，独一份的顶匣侧影）
## ③ 原厂一体白光镜：弧形方镜体 + 发光观瞄窗 + torus 镜框环 + 弧形顶盖
##    ——仅外观件，开镜倍率仍只认装配瞄具（工程纪律）
## ④ 双握把孔：枪管下中段的开孔前握把（高分段竖柱 + 前脸指槽×3 + 孔环）+
##    后手枪握把 + 孔环
## ⑤ 流线聚合物外壳：三段收张圆角大盒身 + 壳体侧缝线×2 + 尾部胶垫、
##    无外露弹匣井/无外露拉机柄
## ⑥ 枪口短筒形消焰器（开筒内衬亮钢膛 + 前挡环/后螺纹肩双 torus），枪管
##    几乎全长包在壳内（低轴线）
## ⑦ 浅灰白主色 + 黑色握把孔的强对比配色（全枪册唯一浅色枪）
static func _smg_p90() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var light: StandardMaterial3D = mats["light"]
	var dark: StandardMaterial3D = mats["dark"]
	var smoke: StandardMaterial3D = mats["smoke"]
	var steel: StandardMaterial3D = mats["steel"]
	var glass: StandardMaterial3D = mats["glass"]
	# ⑤ 外壳三段：前收段 → 主体段 → 尾段；尾块斜转圆滑收（无托尾部）——倒角盒
	GUN_LIB.chamfer_box(root, light, Vector3(0.062, 0.085, 0.11),
			Vector3(0, 0.0, -0.185), Vector3.ZERO, 0.003, 8)
	GUN_LIB.chamfer_box(root, light, Vector3(0.07, 0.115, 0.17),
			Vector3(0, 0.012, -0.045), Vector3.ZERO, 0.0035, 8)
	GUN_LIB.chamfer_box(root, light, Vector3(0.066, 0.1, 0.14),
			Vector3(0, 0.018, 0.11), Vector3.ZERO, 0.003, 8)
	GUN_LIB.chamfer_box(root, light, Vector3(0.055, 0.08, 0.06),
			Vector3(0, 0.012, 0.195), Vector3(10, 0, 0), 0.003, 8)
	# ⑤ 壳体左右侧缝线（上下壳合缝）+ 尾部橡胶垫
	GUN_LIB.chamfer_box(root, dark, Vector3(0.002, 0.012, 0.36),
			Vector3(0.0362, 0.014, -0.05), Vector3.ZERO, 0.0008, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.002, 0.012, 0.36),
			Vector3(-0.0362, 0.014, -0.05), Vector3.ZERO, 0.0008, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.054, 0.086, 0.012),
			Vector3(0, 0.014, 0.232), Vector3(10, 0, 0), 0.0015, 4)
	# ② 顶置 50 发长弹匣（独立命名节点 mag_top：主匣 + 顶冠条 + 前斜头 +
	#    尾收头 + 两侧纵槽；与壳体的深色接缝线挂壳体侧）
	var mag_t := Node3D.new()
	mag_t.name = "mag_top"
	root.add_child(mag_t)
	GUN_LIB.chamfer_box(mag_t, smoke, Vector3(0.068, 0.042, 0.40),
			Vector3(0, 0.078, -0.06), Vector3.ZERO, 0.003, 8)
	GUN_LIB.chamfer_box(mag_t, smoke, Vector3(0.05, 0.008, 0.38),
			Vector3(0, 0.095, -0.06), Vector3.ZERO, 0.0015, 4)
	GUN_LIB.chamfer_box(mag_t, smoke, Vector3(0.06, 0.036, 0.03),
			Vector3(0, 0.078, -0.255), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(mag_t, smoke, Vector3(0.062, 0.038, 0.04),
			Vector3(0, 0.078, 0.135), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(mag_t, dark, Vector3(0.004, 0.026, 0.36),
			Vector3(0.035, 0.078, -0.06), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(mag_t, dark, Vector3(0.004, 0.026, 0.36),
			Vector3(-0.035, 0.078, -0.06), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.07, 0.006, 0.40),
			Vector3(0, 0.058, -0.06), Vector3.ZERO, 0.001, 3)
	# ③ 原厂一体白光镜：方镜体 + 发光观瞄窗 + torus 镜框环 + 弧形顶盖
	GUN_LIB.chamfer_box(root, dark, Vector3(0.052, 0.034, 0.11),
			Vector3(0, 0.116, 0.10), Vector3.ZERO, 0.0025, 6)
	GUN_LIB.chamfer_box(root, glass, Vector3(0.04, 0.026, 0.012),
			Vector3(0, 0.117, 0.043), Vector3.ZERO, 0.001, 3)
	GUN_LIB.torus_ring(root, dark, 0.014, 0.019, Vector3(0, 0.117, 0.043),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, dark, Vector3(0.046, 0.012, 0.12),
			Vector3(0, 0.138, 0.10), Vector3(-6, 0, 0), 0.0015, 4)
	# ④ 前握把孔：开孔竖圆柱（高分段封闭柱，径 0.042 同旧模 r0.021）+
	#    前脸指槽×3 + 孔环（黑色）
	GUN_LIB.barrel(root, dark, 0.075, 0.042, Vector3(0, -0.05, -0.155),
			Vector3.ZERO, 0, 24)
	for i in 3:
		GUN_LIB.chamfer_box(root, dark, Vector3(0.012, 0.004, 0.005),
				Vector3(0, -0.03 - 0.014 * float(i), -0.1745), Vector3.ZERO,
				0.0008, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.056, 0.016, 0.062),
			Vector3(0, -0.052, -0.155), Vector3.ZERO, 0.002, 6)
	# ④ 后手枪握把 + 孔环（后倾 15°——真实 P90 近垂直略后掠）：grip() 顶锚
	#    迁移：pos = 旧盒心 (0,-0.088,0.055) + Rx(-15°)·(0,0.04,0)
	#    = (0, -0.0494, 0.0446)
	GUN_LIB.grip(root, dark, 0.08, Vector3(0, -0.0494, 0.0446), 15.0,
			0.05, 0.05, steel)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.058, 0.018, 0.06),
			Vector3(0, -0.055, 0.055), Vector3.ZERO, 0.002, 6)
	# 扳机 + 护圈（双握把孔之间）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.075, -0.03), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.01, 0.008, 0.05),
			Vector3(0, -0.095, -0.025), Vector3.ZERO, 0.001, 4)
	# ⑥ 枪管（低轴线、几乎全长包壳内；口径 0.02 同旧模 r0.01）+ 枪口短筒
	#    消焰器（外径 0.028 开筒内衬亮钢膛 + 后螺纹肩/前挡环双 torus）
	GUN_LIB.barrel(root, steel, 0.06, 0.02, Vector3(0, -0.02, -0.21),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.torus_ring(root, steel, 0.008, 0.012, Vector3(0, -0.02, -0.222),
			Vector3(90, 0, 0))
	GUN_LIB.tube(root, dark, 0.05, 0.028, Vector3(0, -0.02, -0.245),
			Vector3(90, 0, 0), 0.003, 0, steel, 3, 32)
	GUN_LIB.torus_ring(root, steel, 0.012, 0.017, Vector3(0, -0.02, -0.268),
			Vector3(90, 0, 0))
	return root


## IMI 乌兹（9×19mm）——考证特征逐条（HDGunLib 高模重建：顶点 507 → ≈6.8k，
## ≥8× 红线见 HDGunLib.POLY_MIN["uzi"]；按 90/柱 真基线 606 复核 = 4848 亦过）：
## ① 方盒机匣：矩形上下等宽单盒、全枪册最「方」的轮廓（无阶梯无护木；
##    倒角盒 s12——「方中带圆」，棱线圆滑但轮廓仍是方正单盒）+ 顶部枪机
##    运槽亮钢条 + 侧缝线×2
## ② 弹匣插在手枪握把内：长直匣从握把底垂直下垂（动画匣对中握把中轴
##    show=true，握把与匣同色表达「匣在握把内」——静置匣不另建模件）
## ③ 金属折叠托：铰链块 + 双铰链销 torus + 两根高分段细钢杆 + 端部小板托
##    + 端板胶垫（展开于机匣后）
## ④ 极短紧凑：机匣前端直接出短枪管（前管螺帽 torus + 枪口螺纹环×2 外露）、
##    无护木、无木件、全黑
## ⑤ 机匣上方后段的圆柱拉机柄钮（顶部圆钮凸起，开筒帽顶封）
## ⑥ 握把前缘弧形握把保险凸块（斜置弧块）
## ⑦ 前准星柱带护圈双耳 + 机匣尾片状照门（座+片）+ 弹匣卡笋钮
static func _smg_uzi() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var dark: StandardMaterial3D = mats["dark"]
	var maggrey: StandardMaterial3D = mats["maggrey"]
	var steel: StandardMaterial3D = mats["steel"]
	# ① 方盒机匣（上下等宽，「方中带圆」倒角 s12）+ 顶部枪机运槽亮钢条
	#    + 左右壳缝线
	GUN_LIB.chamfer_box(root, dark, Vector3(0.058, 0.096, 0.26),
			Vector3(0, 0.02, -0.02), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.02, 0.006, 0.20),
			Vector3(0, 0.0705, -0.03), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.002, 0.05, 0.24),
			Vector3(0.0292, 0.02, -0.02), Vector3.ZERO, 0.0008, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.002, 0.05, 0.24),
			Vector3(-0.0292, 0.02, -0.02), Vector3.ZERO, 0.0008, 2)
	# ④ 前管螺帽（torus 环顶 0.02 同旧模 r0.02，裹口径 0.024 枪管）+
	#    短枪管（螺纹环×2——枪口螺纹外露）
	GUN_LIB.torus_ring(root, steel, 0.011, 0.02, Vector3(0, 0.025, -0.155),
			Vector3(90, 0, 0))
	GUN_LIB.barrel(root, dark, 0.08, 0.024, Vector3(0, 0.025, -0.20),
			Vector3(90, 0, 0), 2, 32)
	# ⑤ 机匣顶后段圆柱拉机柄钮（2026-10 二轮判图「错位拉机柄杆」：
	#    旧 rot=ZERO 管体直立悬空读作错位钢杆——躺平沿枪管向、dark 同
	#    机匣顶；开筒帽顶封、内衬探下藏进机匣）
	GUN_LIB.tube(root, dark, 0.022, 0.03, Vector3(0, 0.079, 0.04),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	# ⑦ 前准星座 + 护圈双耳 + 准星柱（机匣前上）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.026, 0.02, 0.018),
			Vector3(0, 0.078, -0.135), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.007, 0.03, 0.009),
			Vector3(0.014, 0.093, -0.135), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.007, 0.03, 0.009),
			Vector3(-0.014, 0.093, -0.135), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.022, 0.005),
			Vector3(0, 0.095, -0.135), Vector3.ZERO, 0.0008, 3)
	# ⑦ 机匣尾片状照门（座 + 照门片）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.012, 0.014),
			Vector3(0, 0.074, 0.095), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.006, 0.014, 0.006),
			Vector3(0, 0.086, 0.095), Vector3.ZERO, 0.0008, 3)
	# ② 握把（后倾 15°、中轴对齐动画匣 z=0.081、与匣同色 maggrey——匣嵌
	#    握把段无色差）：grip() 顶锚迁移：pos = 旧盒心 (0,-0.075,0.081) +
	#    Rx(-15°)·(0,0.0525,0) = (0, -0.0243, 0.0674)
	GUN_LIB.grip(root, maggrey, 0.105, Vector3(0, -0.0243, 0.0674), 15.0,
			0.044, 0.052, steel, 4)
	# ⑥ 握把前缘弧形握把保险凸块（斜置弧块）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.038, 0.045, 0.022),
			Vector3(0, -0.052, 0.03), Vector3(18, 0, 0), 0.0015, 4)
	# 扳机 + 护圈（握把前方、弹匣前缘；护圈前弯补条圈出护圈前缘）+ 弹匣卡笋钮
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.065, -0.012), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.01, 0.008, 0.06),
			Vector3(0, -0.092, -0.005), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.01, 0.006, 0.02),
			Vector3(0, -0.086, -0.037), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.012, 0.01, 0.016),
			Vector3(0, -0.028, 0.048), Vector3.ZERO, 0.0008, 2)
	# ③ 金属折叠托：铰链块 + 双铰链销 torus + 两根高分段细钢杆 + 端部小板托
	#    + 端板胶垫（展开于机匣后）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.05, 0.045, 0.02),
			Vector3(0, 0.03, 0.12), Vector3.ZERO, 0.0015, 4)
	GUN_LIB.torus_ring(root, steel, 0.0035, 0.0085, Vector3(0.026, 0.03, 0.12),
			Vector3(0, 0, 90))
	GUN_LIB.torus_ring(root, steel, 0.0035, 0.0085, Vector3(-0.026, 0.03, 0.12),
			Vector3(0, 0, 90))
	GUN_LIB.barrel(root, dark, 0.185, 0.007, Vector3(0.023, 0.028, 0.215),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.barrel(root, dark, 0.185, 0.007, Vector3(-0.023, 0.028, 0.215),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.054, 0.072, 0.012),
			Vector3(0, 0.018, 0.31), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.048, 0.06, 0.008),
			Vector3(0, 0.018, 0.318), Vector3.ZERO, 0.0015, 4)
	return root


## KRISS Vector 冲锋枪（.45 ACP，约1200rpm）——考证特征逐条（HDGunLib 高模
## 重建：顶点 690 → ≈8.1k，≥8× 红线见 HDGunLib.POLY_MIN["vector"]；按 90/柱
## 真基线 756 复核 = 6048 亦过）：
## ① 折线形机匣侧影：前低后高两段折线（低护木段 → 斜面过渡块 → 高机匣段，
##    Super V 系统外观签名、枪册独一份——四段全倒角盒 s8/s6，折线棱圆滑）
## ② 大后倾角手枪握把居中：弹匣斜插入握把（动画匣对中握把、握把与匣同色；
##    grip() 指棱钢条提层次）
## ③ 全长顶部皮卡汀尼轨：连续楔齿从机匣尾铺到护木（倒角基条 + 倒角齿×8）
## ④ 机匣尾部上凸块（后坐质量块外形）高出顶轨 + 前斜肩
## ⑤ 侧折黑色方盒聚合物托 + 折叠铰链凸块 + 托底板 + 贴腮垫
## ⑥ 低枪管线：枪管贴护木下缘（螺纹环×3 外露）+ 短消焰器（开筒内衬亮钢
##    膛 + 纵槽×2 + 前挡环 torus）
## ⑦ 纯黑聚合物配色（与 P90 浅色、MP5 深黑蓝各拉开一档）
static func _smg_vector() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var polymer: StandardMaterial3D = mats["polymer"]
	var dark: StandardMaterial3D = mats["dark"]
	var maggrey: StandardMaterial3D = mats["maggrey"]
	var steel: StandardMaterial3D = mats["steel"]
	# ① 折线三段：低护木段 → 斜面过渡块（前低后高，Super V 折线签名）→
	#    中段 → 高机匣段——倒角盒
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.056, 0.058, 0.16),
			Vector3(0, 0.002, -0.20), Vector3.ZERO, 0.003, 8)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.056, 0.05, 0.05),
			Vector3(0, 0.005, -0.115), Vector3(-18, 0, 0), 0.0025, 6)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.06, 0.072, 0.13),
			Vector3(0, 0.014, -0.045), Vector3.ZERO, 0.003, 8)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.062, 0.082, 0.15),
			Vector3(0, 0.024, 0.10), Vector3.ZERO, 0.003, 8)
	# ③ 全长顶轨基条 + 连续楔齿×8（从护木前端铺到机匣尾）——倒角齿
	GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.015, 0.44),
			Vector3(0, 0.0745, -0.09), Vector3.ZERO, 0.0015, 6)
	for i in 8:
		GUN_LIB.chamfer_box(root, dark, Vector3(0.032, 0.006, 0.02),
				Vector3(0, 0.0855, -0.29 + float(i) * 0.057), Vector3.ZERO,
				0.001, 4)
	# ④ 尾部上凸质量块（顶 0.118 高出轨顶 0.082）+ 前斜肩
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.05, 0.05, 0.1),
			Vector3(0, 0.093, 0.095), Vector3.ZERO, 0.003, 8)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.048, 0.04, 0.05),
			Vector3(0, 0.085, 0.03), Vector3(-20, 0, 0), 0.002, 6)
	# ⑤ 侧折方盒聚合物托 + 折叠铰链凸块 + 托底板 + 贴腮垫
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.048, 0.068, 0.125),
			Vector3(0, 0.018, 0.235), Vector3.ZERO, 0.003, 8)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.054, 0.028, 0.03),
			Vector3(0, 0.03, 0.175), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.05, 0.075, 0.012),
			Vector3(0, 0.012, 0.30), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.04, 0.02, 0.10),
			Vector3(0, 0.055, 0.24), Vector3.ZERO, 0.0015, 4)
	# ② 大后倾握把（后倾 25° 居中对中动画匣、与匣同色——真实 Vector 陡握把
	#    角）：grip() 顶锚迁移：pos = 旧盒心 (0,-0.072,0.026) +
	#    Rx(-25°)·(0,0.0575,0) = (0, -0.0199, 0.0017)
	GUN_LIB.grip(root, maggrey, 0.115, Vector3(0, -0.0199, 0.0017), 25.0,
			0.048, 0.058, steel)
	# 扳机 + 护圈
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.06, -0.055), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.01, 0.008, 0.055),
			Vector3(0, -0.085, -0.05), Vector3.ZERO, 0.001, 4)
	# ⑥ 低枪管线：枪管贴护木下缘（口径 0.022 同旧模 r0.011、螺纹环×3 外露）
	#    + 短消焰器（外径 0.03 同旧模 r0.015、开筒内衬亮钢膛 + 两侧纵槽 +
	#    前挡环 torus——枪口轴线贴握持线）
	GUN_LIB.barrel(root, dark, 0.09, 0.022, Vector3(0, -0.002, -0.335),
			Vector3(90, 0, 0), 3, 24)
	GUN_LIB.tube(root, dark, 0.045, 0.03, Vector3(0, -0.002, -0.40),
			Vector3(90, 0, 0), 0.0035, 0, steel, 3, 32)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.004, 0.03),
			Vector3(-0.0145, -0.002, -0.40), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.004, 0.03),
			Vector3(0.0145, -0.002, -0.40), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.torus_ring(root, steel, 0.013, 0.019, Vector3(0, -0.002, -0.42),
			Vector3(90, 0, 0))
	# 轨首准星（座+柱）+ 质量块前照门（座+片）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.018, 0.022, 0.016),
			Vector3(0, 0.096, -0.30), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.018, 0.005),
			Vector3(0, 0.104, -0.30), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.028, 0.014, 0.018),
			Vector3(0, 0.096, 0.0), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.006, 0.012, 0.006),
			Vector3(0, 0.108, 0.0), Vector3.ZERO, 0.0008, 3)
	return root


## MK4 冲锋枪（4.6×30mm AR 式 PDW，按用户参考图逐特征建模，HDGunLib 高模
## 重建——顶点 1380 → ≈14.4k，≥8× 红线见 HDGunLib.POLY_MIN["mk4"]）：
## ① 全黑配色：黑聚合物机匣/护木/托 + 黑钢轨件/缓冲管 + 亮钢小件提层次
##    （机匣/托体全部倒角盒——直角棱线消除、棱线高光顺滑）
## ② 全长顶部导轨：单根轨基从机匣尾直通护木头 + 连续楔齿×9（倒角齿）
## ③ M-LOK 开槽护木：圆管开筒 tube（尾封前开、内衬探出露壁厚）+ 左右各 4 条
##    + 底面 3 条负形暗槽（全册唯一「开槽」语言）
## ④ 前后折叠准星/照门：轨上小基座 + 立柱（前护耳双柱 + 准星柱 / 后照门片）
## ⑤ 机匣抛壳窗（右侧亮钢板）+ 尾部 T 形拉机柄（AR 家族惯例）
## ⑥ 缓冲管 + 可调支臂托：开筒缓冲管（前锁环/后调节环双 torus）+ 铰链块 +
##    下斜调节支臂（细件）+ 托体/贴腮板 + 橡胶托底板 + 侧调节圆钮（torus 侧钮）
## ⑦ 手枪式握把（指棱细条高模握把，后倾 20°）+ 40 发直弹匣微弧
##    （mag_straight 独立命名节点 + curved_mag 三段，mag_of show=false）
## ⑧ 枪管（36 段高分段 + 枪口螺纹环×3）+ 短消焰器（开筒 + 两侧纵槽 + 前挡环）
static func _smg_mk4() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var polymer: StandardMaterial3D = mats["polymer"]
	var dark: StandardMaterial3D = mats["dark"]
	var steel: StandardMaterial3D = mats["steel"]
	var maggrey: StandardMaterial3D = mats["maggrey"]
	# ① AR 式分体机匣：上机匣平顶（=② 轨座）+ 下机匣（弹匣井/握把座）——倒角盒
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.055, 0.06, 0.30),
			Vector3(0, 0.028, -0.09), Vector3.ZERO, 0.0035, 12)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.05, 0.05, 0.20),
			Vector3(0, -0.02, -0.04), Vector3.ZERO, 0.003, 12)
	# ② 全长顶轨：轨基（z -0.52..0.14 一根直通）+ 连续楔齿×9（倒角齿）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.028, 0.012, 0.66),
			Vector3(0, 0.064, -0.19), Vector3.ZERO, 0.0015, 12)
	for i in 9:
		GUN_LIB.chamfer_box(root, dark, Vector3(0.031, 0.006, 0.016),
				Vector3(0, 0.074, -0.50 + 0.075 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ③ M-LOK 开槽护木：圆管开筒（壁厚断面露 4mm）+ 左右各 4 条 + 底面 3 条暗槽
	#    尾端嵌入上机匣 4cm（z 至 -0.20，机匣前缘 -0.24）——原平口对接在 -0.24
	#    露缝（用户反馈「前后段不重叠」）；接缝加过渡环盖截面突变
	GUN_LIB.tube(root, polymer, 0.36, 0.056, Vector3(0, 0.022, -0.38),
			Vector3(90, 0, 0), 0.004, 4, dark, 4, 48)
	GUN_LIB.torus_ring(root, polymer, 0.006, 0.062,
			Vector3(0, 0.024, -0.238), Vector3(90, 0, 0))
	# ⑤ 全自动枪管配件件（2026-10-25 MK4_MODS.autobarrel，环境变量与 M14 配件
	#    同源）：重型长枪管（原枪管位加粗前伸）+ 鸟笼消焰器——命名节点供断言
	if OS.get_environment("HD_M14_MODS").contains("autobarrel"):
		var ab := Node3D.new()
		ab.name = "mk4_autobarrel"
		root.add_child(ab)
		GUN_LIB.barrel(ab, dark, 0.012, 0.24, Vector3(0, 0.022, -0.60),
				Vector3(90, 0, 0), 0, 10)
		GUN_LIB.tube(ab, dark, 0.07, 0.026, Vector3(0, 0.022, -0.745),
				Vector3(90, 0, 0), 0.003, 3, steel, 3, 10)
		for si in 4:   # 鸟笼排气槽（亮钢短柱读「孔」）
			GUN_LIB.barrel(ab, steel, 0.0135, 0.005,
					Vector3(0.0, 0.022 + 0.006 * (1 if si % 2 == 0 else -1), -0.72 - 0.012 * float(si % 2)),
					Vector3(90, 0, 0), 0, 4)
	# ④ 前折叠准星（轨前：基座 + 护耳双柱 + 准星柱）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.02, 0.012, 0.026),
			Vector3(0, 0.074, -0.50), Vector3.ZERO, 0.001, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.006, 0.022, 0.008),
			Vector3(-0.009, 0.088, -0.50), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.006, 0.022, 0.008),
			Vector3(0.009, 0.088, -0.50), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.018, 0.005),
			Vector3(0, 0.086, -0.50), Vector3.ZERO, 0.0008, 3)
	# ④ 后折叠照门（轨尾：基座 + 照门片）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.024, 0.012, 0.028),
			Vector3(0, 0.074, 0.11), Vector3.ZERO, 0.001, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.02, 0.008),
			Vector3(0, 0.09, 0.11), Vector3.ZERO, 0.0008, 3)
	# ⑤ 抛壳窗（右侧亮钢板）+ 尾部 T 形拉机柄（双翼）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.026, 0.075),
			Vector3(0.0285, 0.03, -0.06), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.034, 0.009, 0.02),
			Vector3(0, 0.062, 0.13), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.012, 0.006, 0.012),
			Vector3(0.017, 0.062, 0.13), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.012, 0.006, 0.012),
			Vector3(-0.017, 0.062, 0.13), Vector3.ZERO, 0.0008, 3)
	# ⑥ 缓冲管（开筒 + 前锁环/后调节环双 torus）+ 铰链块 + 可调支臂（下斜细件）
	#    + 托体/贴腮板 + 橡胶托底板 + 侧调节圆钮（torus 侧钮，环面 ⊥ X）
	# 缓冲管尾端开放（cap_tail=false，2026-10 三轮判图「MK4 银环」终审：
	# 尾盖圆盘正对沿轴视角且 dark 材质仍渲 0.4+——开放后只剩内衬尾盖
	# 暗面（凸出 2mm）+管口环，端面异物消失）
	GUN_LIB.tube(root, dark, 0.17, 0.036, Vector3(0, 0.014, 0.155),
			Vector3(90, 0, 0), 0.005, 0, null, 3, 32, 0.05, false)
	# 后调节环 dark（2026-10 二轮判图「MK4 银环」：steel 弧带在顶灯直射
	# 下读作亮银环异物——换 dark 与缓冲管/前锁环同色隐入）
	GUN_LIB.torus_ring(root, dark, 0.017, 0.021, Vector3(0, 0.014, 0.215),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, steel, 0.017, 0.021, Vector3(0, 0.014, 0.215),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.046, 0.032, 0.03),
			Vector3(0, 0.016, 0.245), Vector3.ZERO, 0.002, 4)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.012, 0.13),
			Vector3(0, -0.045, 0.30), Vector3(-16, 0, 0), 0.0012, 4)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.044, 0.07, 0.13),
			Vector3(0, 0.005, 0.31), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.04, 0.02, 0.11),
			Vector3(0, 0.05, 0.31), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.05, 0.095, 0.016),
			Vector3(0, -0.005, 0.38), Vector3.ZERO, 0.002, 6)
	GUN_LIB.torus_ring(root, steel, 0.005, 0.0115, Vector3(0.026, -0.005, 0.27),
			Vector3(0, 0, 90))
	# ⑦ 弹匣井（挂合同直匣）+ 后握把（指棱高模握把、后倾 20°）+
	#    护圈/扳机/快慢机/空挂杆
	GUN_LIB.chamfer_box(root, polymer, Vector3(0.05, 0.07, 0.075),
			Vector3(0, -0.062, -0.115), Vector3.ZERO, 0.0025, 6)
	# ⑦ 后握把（指棱高模握把、后倾 20°）——grip() 顶锚=旋转支点，旧
	#    _add_grip 中心锚=旋转支点，迁移用矢量式（含 z！）：pos = 旧盒心 +
	#    Rx(−20°)·(0, 0.049, 0) = (0, -0.068+0.046, 0.015-0.0168)
	#    ≈ (0, -0.022, -0.0018)——8 角点与旧模偏差 ≤0.06mm（已矩阵精算）；
	#    只改 y 不改 z 会沿杆后移 16.8mm
	GUN_LIB.grip(root, polymer, 0.098, Vector3(0, -0.022, -0.0018), 20.0,
			0.038, 0.054, steel)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.01, 0.006, 0.07),
			Vector3(0, -0.088, -0.06), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.022, 0.008),
			Vector3(0, -0.075, -0.065), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.006, 0.012, 0.026),
			Vector3(0.027, -0.008, 0.0), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.01, 0.008, 0.03),
			Vector3(0.028, -0.03, -0.085), Vector3.ZERO, 0.0008, 3)
	# ⑦ 直弹匣微弧（独立命名节点 mag_straight：原点=匣顶中心，动画匣锚
	#    (0,-0.135,-0.115) 的匣顶 -0.035——7° 三段微弧，弧向前；
	#    2026-10 前移 40mm 对中弹匣井（井心 z=-0.115），与动画匣锚同步）
	var mag := Node3D.new()
	mag.name = "mag_straight"
	mag.position = Vector3(0, -0.035, -0.115)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, maggrey, Vector3(0.042, 0.2, 0.068), 7.0, 3, 3)
	# ⑧ 枪管（36 段高分段 + 螺纹环×3 紧贴消焰器后）+ 短消焰器
	#    （开筒内衬亮钢膛 + 两侧纵槽提示 + 前挡环）
	GUN_LIB.barrel(root, dark, 0.10, 0.024, Vector3(0, 0.028, -0.60),
			Vector3(90, 0, 0), 3, 36)
	GUN_LIB.tube(root, dark, 0.05, 0.032, Vector3(0, 0.028, -0.665),
			Vector3(90, 0, 0), 0.003, 0, steel, 3, 32)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.004, 0.03),
			Vector3(-0.0145, 0.028, -0.665), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.004, 0.03),
			Vector3(0.0145, 0.028, -0.665), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.torus_ring(root, steel, 0.014, 0.019, Vector3(0, 0.028, -0.688),
			Vector3(90, 0, 0))
	return root


## H&K MP7 PDW（4.6×30mm，约950rpm）——考证特征逐条（HDGunLib 高模件拼装，
## 按 MP7A1 参考图逐特征对照；紧凑方正、体量小于 MK4：枪身 z -0.371~+0.258
## ≈0.63，MK4 的 57%——真枪收托仅约 41.5cm；顶点红线见 HDGunLib.POLY_MIN
## ["mp7"]，构成式清点见 POLY_BASE 注。2026-10 二轮判图返工：导轨前段补齐
## 楔齿（并修正首轮前齿 z 反向飞出轨基的「薄翅」bug）、照门座缩 1/3 开觇孔、
## 抛壳窗改暗腔+亮缘、金属去蓝/聚合物提亮、前准星竖向护翼圆顶柱、弹匣单列
## 观察孔+30 刻度线+托弹板、拉机柄扁平耳片、减重孔椭圆化、托板薄板大镂空、
## 前握把收腰竖纹）：
## ① 整体布局：紧凑方正直列式 PDW、形似放大手枪——弹匣插中空握把而非机匣
##    （握把=弹匣井、匣从握把底板下出露并 6° 前倾），重心在握把正上方
## ② 机匣两层结构：上半金属机匣壳（左右两排椭圆减重孔=负形暗件，孔四角
##    圆角=孔高一半）+ 下半聚合物外壳，交接线平直贯穿全枪（左右缝线暗条）
## ③ 顶部导轨：分段式 Picatinny——前 4 后 3 楔齿两段、中段下凹露拉机柄
##    滑动槽（暗槽板），双耳拉机柄扁平矩形耳片平贴槽尾（非往复、射击不随动）
## ④ 机瞄：轨前后各一座低矮折叠机械瞄具——前柱状准星（竖向护翼+圆顶柱）
##    / 后小照门座亮环觇孔（torus 圆孔），放倒后与导轨齐平（建模展开态）
## ⑤ 枪托：细长单杆伸缩滑轨（主导杆+下导杆双柱）从机匣尾拉出，末端薄板
##    肩托（厚 7mm）+ 大镂空孔（孔面积≈板面一半）+ 铰链销双 torus（可上翻）
## ⑥ 抛壳窗：机匣右侧前部方形开口（暗腔+亮缘倒角一圈）+ 左侧光面（无开窗件）
## ⑦ 扳机护圈与控制件：护圈前伸与握把围成大环形，弹匣卡笋横穿护圈前下角
##    （HK 标志性布局），快慢机居握把上方两侧带红白射击指示点
## ⑧ 枪口：短枪管外露于护木前（轴线 y=0.018 贴握持线）+ 枪口螺纹环 +
##    小圆柱消焰器/枪口罩（开筒内衬亮钢膛 + 前挡环）
## ⑨ 前握把：护木下方垂直前握把（展开态、上下两段收腰）+ 竖向刻纹
## ⑩ 握把刻纹与模印：握把侧面三道竖向刻纹条 + 根部浅灰 MP7A1 模印条
## ⑪ 半透明弹匣：窄长矩形截面短匣（烟灰半透明 38%）+ 单列圆点观察孔 +
##    『30』刻度线 + 匣内托弹板轮廓（匣形=枪身独立命名节点 mag_pdw）
## ⑫ 侧面附件与刻字：机匣左右下侧短 Picatinny 导轨（各 3 齿）+ Cal.4.6
##    mm×30 / HK MP7A1 模印浅灰条 + 红白安全指示小旗标
## ⑬ 使用痕迹：仅顶轨棱边一条银灰磨损条 + 枪口前挡环/准星柱磨损色，不整面做旧
static func _smg_mp7() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var mp7body: StandardMaterial3D = mats["mp7body"]
	var mp7metal: StandardMaterial3D = mats["mp7metal"]
	var mp7rail: StandardMaterial3D = mats["mp7rail"]
	var mp7mag: StandardMaterial3D = mats["mp7mag"]
	var mp7mark: StandardMaterial3D = mats["mp7mark"]
	var mp7red: StandardMaterial3D = mats["mp7red"]
	var mp7dark: StandardMaterial3D = mats["mp7dark"]
	var mp7wear: StandardMaterial3D = mats["mp7wear"]
	# ①② 机匣两层：金属上半壳（减重孔载体）+ 前斜面鼻（放大手枪的前脸）
	#    + 聚合物下半壳——倒角盒，交接线=左右缝线暗条平直贯穿
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.052, 0.046, 0.34),
			Vector3(0, 0.02, -0.09), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.048, 0.034, 0.06),
			Vector3(0, 0.006, -0.283), Vector3(-18, 0, 0), 0.0025, 10)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.056, 0.054, 0.30),
			Vector3(0, -0.028, -0.055), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.002, 0.004, 0.29),
			Vector3(0.0284, -0.001, -0.05), Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.002, 0.004, 0.29),
			Vector3(-0.0284, -0.001, -0.05), Vector3.ZERO, 0.0006, 6)
	# ② 减重/散热孔：上壳后半左右两排 ×4 列椭圆孔（负形暗件；倒角取孔高
	#    一半 5mm——四角圆成圆角长孔，非直角矩形）
	for i in 4:
		GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.002, 0.01, 0.016),
				Vector3(0.0258, 0.03, -0.042 + 0.038 * float(i)), Vector3.ZERO,
				0.005, 6)
		GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.002, 0.01, 0.016),
				Vector3(0.0258, 0.013, -0.042 + 0.038 * float(i)), Vector3.ZERO,
				0.005, 6)
		GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.002, 0.01, 0.016),
				Vector3(-0.0258, 0.03, -0.042 + 0.038 * float(i)), Vector3.ZERO,
				0.005, 6)
		GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.002, 0.01, 0.016),
				Vector3(-0.0258, 0.013, -0.042 + 0.038 * float(i)), Vector3.ZERO,
				0.005, 6)
	# ③ 分段顶轨：轨基一根直通（z -0.28..0.08）+ 前段楔齿×14 / 后段×3
	#    （四轮判图：前段「准星基座往后到拉机柄槽之前」仍读出约 40% 光板
	#    ——齿列从 -0.262 满铺贯通到槽板前沿 -0.122，肋距 10mm；齿高按
	#    导轨宽 26mm 的 1/5 ≈ 5mm）+ 中段下凹槽板
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.026, 0.008, 0.36),
			Vector3(0, 0.048, -0.1), Vector3.ZERO, 0.0015, 12)
	for i in 14:
		GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.021, 0.005, 0.006),
				Vector3(0, 0.0545, -0.262 + 0.01 * float(i)), Vector3.ZERO,
				0.0005, 6)
	for i in 3:
		GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.021, 0.002, 0.006),
				Vector3(0, 0.053, -0.006 + 0.015 * float(i)), Vector3.ZERO,
				0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.02, 0.003, 0.09),
			Vector3(0, 0.0522, -0.07), Vector3.ZERO, 0.0006, 6)
	# ③ 非往复拉机柄双耳（MP5 式耳柄）：扁平矩形耳片 12×6mm、贴导轨中段
	#    下凹槽两侧、不随枪托杆（三轮判图：首轮误把铰链销圆环读成拉机柄，
	#    销已改细圆柱；耳片加大居槽两侧）
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.005, 0.006, 0.012),
			Vector3(0.013, 0.0535, -0.07), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.005, 0.006, 0.012),
			Vector3(-0.013, 0.0535, -0.07), Vector3.ZERO, 0.0005, 6)
	# ④ 前折叠准星（轨前端：基座 + 两侧竖向护翼 + 圆顶柱状准星——竖圆柱
	#    + 顶圆环收头；柱改深灰金属与全枪统一，磨损色只留顶环）
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.016, 0.006, 0.022),
			Vector3(0, 0.057, -0.268), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.0035, 0.022, 0.007),
			Vector3(0.0055, 0.068, -0.268), Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.0035, 0.022, 0.007),
			Vector3(-0.0055, 0.068, -0.268), Vector3.ZERO, 0.0006, 6)
	GUN_LIB.barrel(root, mp7metal, 0.016, 0.004, Vector3(0, 0.068, -0.268),
			Vector3(0, 0, 0), 0, 12)
	GUN_LIB.torus_ring(root, mp7wear, 0.002, 0.0035, Vector3(0, 0.0755, -0.268),
			Vector3.ZERO, 12, 8)
	# ④ 后折叠觇孔照门（导轨后位、枪托杆接口前方——五轮判图：基座收窄
	#    1/3、两柱间觇孔开大贴 ref_6 低矮折叠轮廓：底座 10×4×25mm、双立
	#    柱、觇孔环内径 5mm 降位贴近基座）
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.01, 0.004, 0.025),
			Vector3(0, 0.056, 0.068), Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.003, 0.014, 0.008),
			Vector3(0.006, 0.065, 0.068), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.003, 0.014, 0.008),
			Vector3(-0.006, 0.065, 0.068), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.torus_ring(root, mp7rail, 0.0025, 0.0055, Vector3(0, 0.072, 0.068),
			Vector3(90, 0, 0), 12, 8)
	# ⑤ 枪托：低剖面铰链块 + 细长单杆滑轨（主导杆 + 下导杆双柱）+ 伸缩调节钮
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.028, 0.016, 0.016),
			Vector3(0, 0.016, 0.098), Vector3.ZERO, 0.0012, 8)
	GUN_LIB.barrel(root, mp7metal, 0.15, 0.011, Vector3(0, 0.024, 0.178),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.barrel(root, mp7metal, 0.11, 0.007, Vector3(0, 0.01, 0.165),
			Vector3(90, 0, 0), 0, 16)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.02, 0.01, 0.03),
			Vector3(0, 0.024, 0.206), Vector3.ZERO, 0.001, 6)
	# ⑤ 薄板肩托（厚 7mm）+ 大镂空孔×3（孔面积≈板面一半）+ 托板顶垫
	#    + 折叠销双细圆柱（X 轴向小销——首轮 torus 圆环被读成拉机柄圆片）
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.048, 0.082, 0.007),
			Vector3(0, 0.006, 0.252), Vector3.ZERO, 0.001, 12)
	GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.024, 0.014, 0.011),
			Vector3(0, 0.022, 0.252), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.024, 0.028, 0.011),
			Vector3(-0.009, -0.014, 0.252), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.024, 0.028, 0.011),
			Vector3(0.009, -0.014, 0.252), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.052, 0.01, 0.014),
			Vector3(0, 0.05, 0.252), Vector3.ZERO, 0.001, 6)
	GUN_LIB.barrel(root, mp7metal, 0.012, 0.004, Vector3(0.017, 0.024, 0.094),
			Vector3(0, 0, 90), 0, 8)
	GUN_LIB.barrel(root, mp7metal, 0.012, 0.004, Vector3(-0.017, 0.024, 0.094),
			Vector3(0, 0, 90), 0, 8)
	# ⑥ 抛壳窗（机匣右侧面前部：椭圆孔排往前、弹匣井正前方 z≈-0.10——
	#    五轮判图指认位；2026-10 判图修复「右侧无抛壳窗」：原 20×30mm
	#    齐平贴面腰射视角读不出——加大到 24×34mm 且外凸 5mm 出机匣面
	#    （外腔盒=明暗对比载体），窗沿亮缘收窄；左侧光面=无开窗件）
	GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.006, 0.034, 0.024),
			Vector3(0.0272, 0.018, -0.095), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.002, 0.0015, 0.028),
			Vector3(0.0286, 0.0383, -0.095), Vector3.ZERO, 0.0004, 6)
	GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.002, 0.0015, 0.028),
			Vector3(0.0286, 0.0023, -0.095), Vector3.ZERO, 0.0004, 6)
	GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.002, 0.0035, 0.0015),
			Vector3(0.0286, 0.0203, -0.0808), Vector3.ZERO, 0.0004, 6)
	GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.002, 0.0035, 0.0015),
			Vector3(0.0286, 0.0203, -0.1092), Vector3.ZERO, 0.0004, 6)
	# ⑦ 扳机护圈（前伸大环形）+ 弹匣卡笋横穿前下角（HK 标志性布局；卡笋
	#    外露横条按真枪为聚合物件——三轮判图高光发白已改碳黑）+ 扳机
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.008, 0.006, 0.086),
			Vector3(0, -0.112, -0.004), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.008, 0.054, 0.006),
			Vector3(0, -0.082, -0.045), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.022, 0.006, 0.01),
			Vector3(0, -0.106, -0.04), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.01, 0.009, 0.008),
			Vector3(0.016, -0.106, -0.04), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.01, 0.009, 0.008),
			Vector3(-0.016, -0.106, -0.04), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.007, 0.022, 0.007),
			Vector3(0, -0.092, 0.004), Vector3.ZERO, 0.0008, 6)
	# ⑦ 快慢机/保险旋钮（机匣两侧、握把上方）+ 红白射击指示点（白点加大
	#    与红点并列——首轮白点过小不可辨）
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.005, 0.014, 0.01),
			Vector3(0.0288, -0.012, 0.03), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.005, 0.014, 0.01),
			Vector3(-0.0288, -0.012, 0.03), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7red, Vector3(0.006, 0.0045, 0.0035),
			Vector3(0.0297, -0.007, 0.03), Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(root, mp7red, Vector3(0.006, 0.0045, 0.0035),
			Vector3(-0.0297, -0.007, 0.03), Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(root, mp7mark, Vector3(0.006, 0.0045, 0.0035),
			Vector3(0.0297, -0.016, 0.03), Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(root, mp7mark, Vector3(0.006, 0.0045, 0.0035),
			Vector3(-0.0297, -0.016, 0.03), Vector3.ZERO, 0.0006, 6)
	# ⑧ 枪管（36 段高分段 + 枪口螺纹环外露）+ 小圆柱消焰器/枪口罩——
	#    口径 1.3 倍管径（26mm）、长 25mm；筒色并入深灰金属区间（五轮
	#    判图：压回 #2E3134–#3A3D40），与枪管区分靠径差+端部纵槽×3
	GUN_LIB.barrel(root, mp7metal, 0.075, 0.02, Vector3(0, 0.018, -0.313),
			Vector3(90, 0, 0), 1, 36)
	GUN_LIB.tube(root, mp7metal, 0.025, 0.026, Vector3(0, 0.018, -0.352),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 32)
	for s in [Vector3(0.0122, 0.018, 0.0), Vector3(0.0, 0.0302, 0.0),
			Vector3(-0.0122, 0.018, 0.0)]:
		GUN_LIB.chamfer_box(root, mp7dark, Vector3(0.002, 0.003, 0.018),
				Vector3(s.x, s.y, -0.352), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.torus_ring(root, mp7wear, 0.0105, 0.014, Vector3(0, 0.018, -0.363),
			Vector3(90, 0, 0), 16, 10)
	# ⑨ 前下壳底面（2026-10 用户定案「不用前握把」：旧垂直前握把整段
	#    拆除——两段收腰柱/连接凸缘/底帽/防滑刻纹全删，前下壳底面只留
	#    一条 MP7A2 式下挂导轨细基条（单件光条不刻齿，干净不乱））
	GUN_LIB.chamfer_box(root, mp7body, Vector3(0.024, 0.005, 0.13),
			Vector3(0, -0.0575, -0.17), Vector3.ZERO, 0.001, 6)
	# ⑩ 中空直握把（内腔即弹匣井；grip 顶锚=(0,-0.042,0.028)，HOLD_DELTA
	#    据此精算——见表注）+ 侧面竖向刻纹×3 对 + 根部 MP7A1 模印条
	var grp: Node3D = GUN_LIB.grip(root, mp7body, 0.095,
			Vector3(0, -0.042, 0.028), 12.0, 0.04, 0.056, mp7metal, 3)
	for i in 3:
		GUN_LIB.chamfer_box(grp, mp7dark, Vector3(0.002, 0.032, 0.005),
				Vector3(0.0205, -0.03, -0.017 + 0.013 * float(i)),
				Vector3.ZERO, 0.0006, 6)
		GUN_LIB.chamfer_box(grp, mp7dark, Vector3(0.002, 0.032, 0.005),
				Vector3(-0.0205, -0.03, -0.017 + 0.013 * float(i)),
				Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(grp, mp7mark, Vector3(0.0025, 0.01, 0.02),
			Vector3(0.0231, -0.0965, 0), Vector3.ZERO, 0.0006, 6)
	# ⑪ 不透明短直匣（独立命名节点 mag_pdw：原点=匣顶中心，匣体从握把底板
	#    下方出露、6° 前倾；curved_mag 直匣——2026-10 用户定案弹匣不透明
	#    黑聚合物，观察孔/『30』刻度白条随透匣一并拆除，匣面只留干净壳体）
	var mag := Node3D.new()
	mag.name = "mag_pdw"
	mag.position = Vector3(0, -0.132, 0.042)
	mag.rotation_degrees = Vector3(6, 0, 0)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, mp7mag, Vector3(0.034, 0.195, 0.054), 0.0, 1, 6)
	# 底板封住匣壳最底端（碳黑不透明盖板盖住 curved_mag 自带透明底板的
	# 凸缘——五轮判图：黑底板悬匣中+下方拖 8-10% 半透明裙边穿帮；
	# 2026-10 判图修复「底板凸角」：不透明板缩到与匣壳同 footprint
	# （0.036×0.058）并加高到 16mm 完全吞掉透明凸缘，凸角不再露边）
	GUN_LIB.chamfer_box(mag, mp7body, Vector3(0.036, 0.016, 0.058),
			Vector3(0, -0.206, 0.0), Vector3.ZERO, 0.001, 6)
	# （观察孔/『30』刻度白条已随透匣定案一并拆除——不透明黑匣上白件
	# 只会读作贴纸，真不透明匣面无孔）
	# ⑫ 侧面刻字（Cal.4.6mm×30 / HK MP7A1 浅灰模印——五轮判图「可见范围
	#    均无」：细条凸出 1.3mm 读不出，加厚到 2mm 凸 1.5mm、加高加长成
	#    浮雕字带）+ 红白安全指示小旗标（右下壳后段、快慢机后方）
	GUN_LIB.chamfer_box(root, mp7mark, Vector3(0.002, 0.006, 0.05),
			Vector3(0.0289, -0.014, 0.05), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7mark, Vector3(0.002, 0.004, 0.03),
			Vector3(0.0289, -0.023, 0.05), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7mark, Vector3(0.002, 0.006, 0.05),
			Vector3(-0.0289, -0.014, 0.05), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7mark, Vector3(0.002, 0.004, 0.03),
			Vector3(-0.0289, -0.023, 0.05), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7red, Vector3(0.001, 0.006, 0.008),
			Vector3(0.0288, -0.03, 0.062), Vector3.ZERO, 0.0005, 6)
	GUN_LIB.chamfer_box(root, mp7mark, Vector3(0.001, 0.006, 0.008),
			Vector3(0.0288, -0.03, 0.071), Vector3.ZERO, 0.0005, 6)
	# ⑫ 侧导轨（机匣左右下侧短 Picatinny：三轮判图指认「红白指示下方」——
	#    移到机匣后段下缘 z -0.055..0.015、轨长 70mm + 楔齿×6，挂战术灯/
	#    激光；首轮轨在前部护木段被读作缺失）
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.006, 0.007, 0.07),
			Vector3(0.0292, -0.036, -0.02), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, mp7metal, Vector3(0.006, 0.007, 0.07),
			Vector3(-0.0292, -0.036, -0.02), Vector3.ZERO, 0.0008, 6)
	for i in 6:
		GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.007, 0.003, 0.008),
				Vector3(0.0299, -0.036, -0.0475 + 0.011 * float(i)), Vector3.ZERO,
				0.0005, 6)
		GUN_LIB.chamfer_box(root, mp7rail, Vector3(0.007, 0.003, 0.008),
				Vector3(-0.0299, -0.036, -0.0475 + 0.011 * float(i)), Vector3.ZERO,
				0.0005, 6)
	# ⑬ 使用痕迹：仅导轨棱边一条银灰磨损条（枪口端面挡环已用磨损色）
	GUN_LIB.chamfer_box(root, mp7wear, Vector3(0.002, 0.0015, 0.05),
			Vector3(0.0138, 0.0548, -0.19), Vector3.ZERO, 0.0005, 6)
	return root


## ---------------- 内部：材质工厂与拼装闭包 ----------------


## 材质工厂：dark/steel 照 hd_guns.gd:475-509 参数原样抄（关深度测试防
## 贴墙吞枪 + render_priority 10 + 微自发光保暗处可读）；另扩冲锋枪册
## 专用色（深黑蓝 MP5 / 哑光聚合物 Vector / 匣灰对齐动画盒 / P90 浅灰白
## 与烟灰顶匣 / 发光观瞄窗）；2026-10 再扩 MP7 专用八色（出厂全黑战术
## 涂装：碳黑聚合物/深灰金属/轨齿提亮/烟灰半透明弹匣/刻度浅灰白/红白
## 指示暗红/刻槽负形深黑/棱边磨损银灰）
static func _smg_mats() -> Dictionary:
	# glow 缺省 0.42（2026-10 判图收敛：0.55 微自发光 + 顶灯/vm_sun 直射
	# 在 ACES 下把深色面整片翻白——「白盘/发光白面/串色」判图案；0.42 仍
	# 高于 MP7 锁线 0.3，暗处可读三件套不回退）
	var mk := func(c: Color, e: Color, rough := 0.55, glow := 0.42) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic_specular = 0.1   # 镜面压档（端面/倒角棱白亮最后来源）
		m.no_depth_test = true
		m.render_priority = 10
		m.emission_enabled = true
		m.emission = e
		m.emission_energy_multiplier = glow
		return m
	# MP7 弹匣专用（2026-10 用户定案「弹夹不要透明」）：不透明近黑聚合物
	# （旧烟灰半透明 35% 版废弃——用户不要透匣，观察孔/刻度白条一并拆除）
	# glow 0.35 同三件套第三件（曾随 90cc58b 归 0，贴掩体亮度塌 0-5）
	var mp7mag: StandardMaterial3D = mk.call(Color(0.085, 0.088, 0.096),
			Color(0.095, 0.098, 0.105), 0.85, 0.35)
	return {
		"dark": mk.call(Color(0.10, 0.11, 0.125), Color(0.125, 0.14, 0.155)),
		"blued": mk.call(Color(0.08, 0.088, 0.12), Color(0.095, 0.11, 0.15)),
		# steel 收敛（2026-10 判图「银环/串色」）：alb 0.35→0.26、emission
		# 同步压档——亮钢仍比 blued/dark 亮一档提层次，顶灯直射不再翻白
		"steel": mk.call(Color(0.115, 0.125, 0.14), Color(0.12, 0.13, 0.145)),
		"polymer": mk.call(Color(0.10, 0.105, 0.115), Color(0.12, 0.125, 0.135), 0.85),
		"maggrey": mk.call(Color(0.07, 0.078, 0.10), Color(0.08, 0.088, 0.115)),
		# light/smoke 收敛（同判图案：浅灰大面翻白）
		"light": mk.call(Color(0.30, 0.30, 0.28), Color(0.24, 0.24, 0.22)),
		"smoke": mk.call(Color(0.26, 0.27, 0.255), Color(0.21, 0.215, 0.20)),
		"glass": mk.call(Color(0.15, 0.55, 0.75), Color(0.15, 0.55, 0.75), 0.3, 1.4),
		# ---- MP7 专用色（2026-10 三轮判图修正：金属件自发光 0.55+高光在
		#      打光下读成 #A8B0BE 亮银蓝——albedo 压深到 #2E3134、自发光降
		#      0.3、roughness 提 0.6；磨损银灰 #5B5D5F 仅留轨棱与枪口端）----
		#      mp7body 碳黑 #17171A / mp7metal 深灰金属 #2E3134 /
		#      mp7rail 轨齿亮灰 #494A4C / mp7mag 半透明匣 #3E4045×35% /
		#      mp7mark 刻度 #B8B8B8 / mp7red 暗红 #B32020 /
		#      mp7dark 刻槽 #101010 / mp7wear 磨损 #5B5D5F）----
		#      （2026-10「金属蓝白串色」判图修复曾把全系 glow 显式归 0
		#      （6d193b5 引入归 0、90cc58b 把匣 0.15 也归 0）——归 0 后贴
		#      掩体挡直射阳光，碳黑枪身只剩弱环境光、亮度塌 0-5 读作「被
		#      吞」，丢掉 4f79b10 三件套第三件「微自发光保暗处可读」。现
		#      恢复 0.35~0.45：emission 色沿用各材质原色（非旧缺省发光色）
		#      且量级低于旧串色版 0.55——只保暗处可读，不复发「蓝白发光件」）
		"mp7body": mk.call(Color(0.07, 0.07, 0.08), Color(0.08, 0.08, 0.09), 0.85, 0.4),
		"mp7metal": mk.call(Color(0.13, 0.14, 0.15), Color(0.145, 0.155, 0.165), 0.65, 0.35),
		"mp7rail": mk.call(Color(0.15, 0.153, 0.158), Color(0.165, 0.168, 0.172), 0.6, 0.4),
		"mp7mag": mp7mag,
		"mp7mark": mk.call(Color(0.45, 0.45, 0.45), Color(0.38, 0.38, 0.38), 0.6, 0.35),
		"mp7red": mk.call(Color(0.702, 0.125, 0.125), Color(0.6, 0.11, 0.11), 0.6, 0.35),
		"mp7dark": mk.call(Color(0.063, 0.063, 0.063), Color(0.07, 0.07, 0.07), 0.8, 0.4),
		"mp7wear": mk.call(Color(0.19, 0.194, 0.198), Color(0.21, 0.214, 0.218), 0.5, 0.35),
	}


## 拼装闭包对（照 hd_guns.gd:510-534 模式，闭包捕获 root）：
## box=盒件（尺寸/位置/欧拉角/材质）、cyl=圆件（rz=顶半径/底半径/高）
static func _smg_rig(root: Node3D) -> Dictionary:
	var add_box := func(size: Vector3, pos: Vector3, rot_deg: Vector3,
			mat: Material) -> MeshInstance3D:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = pos
		mi.rotation_degrees = rot_deg
		root.add_child(mi)
		return mi
	var add_cyl := func(rz: Vector3, pos: Vector3, rot_deg: Vector3,
			mat: Material) -> MeshInstance3D:
		var cm := CylinderMesh.new()
		cm.top_radius = rz.x
		cm.bottom_radius = rz.y
		cm.height = rz.z
		cm.radial_segments = 10
		cm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.position = pos
		mi.rotation_degrees = rot_deg
		root.add_child(mi)
		return mi
	return {"box": add_box, "cyl": add_cyl}


## 挂到指定父节点的盒件（枪身静置弹匣件用：独立命名节点下再拼 mesh，
## 便于探针/后续定位——弹匣形状件不与枪身散装 mesh 混淆）
static func _smg_box_at(parent: Node3D, size: Vector3, pos: Vector3,
		rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## 手枪式后握把统一工厂（旧五枪/冲锋枪册/步枪册三段共用，倾角方向只在此
## 定义一处）：机匣后下方、扳机护圈正后那只握把——枪口朝 -Z 时下端朝
## +Z（玩家侧）后倾 tilt_deg（真实步枪手枪握把基准 15-25°）。内部落成
## rot.x = -tilt_deg：绕 +X 正转会把下端甩向 -Z（枪口侧）前倾，正是旧版
## 十二枪集体「向前倾」的方向根因。逐把只传 pos/材质/倾角/截面（缺省截面
## = 标准握把长宽比 0.038×0.098×0.054）
static func _add_grip(parent: Node3D, pos: Vector3, mat: Material,
		tilt_deg: float = 20.0, size: Vector3 = Vector3(0.038, 0.098, 0.054)) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = Vector3(-tilt_deg, 0, 0)
	parent.add_child(mi)
	return mi

const AR_IDS := ["m4a1", "akm", "scarh", "m14", "asval", "k416", "an94", "sr25"]
# m14（2026-10 商店枪 M14 射手步枪）：官方考证 DMR 并入步枪册——几何体在
# hd_gun_ar.gd _ar_m14（HDGunLib 高模件，枪体量比 SCAR-H 更长）
# asval（2026-10 商店枪 AS Val 特种突击步枪）：官方考证 9×39mm 亚音速一体
# 消音枪并入步枪册——几何体在 hd_gun_ar.gd _ar_asval（HDGunLib 高模件，
# 一体消音管约占全枪一半长）
# k416（2026-10 商店枪 K416 突击步枪）：官方考证 HK416 风格 5.56 突击步枪
# 并入步枪册——几何体在 hd_gun_ar.gd _ar_k416（HDGunLib 高模件，全长顶轨 +
# 两节肋条散热套筒护木 + 鸟笼消焰器）
# an94（2026-10 商店枪 AN-94 突击步枪）：S12 微光赛季新枪并入步枪册——几何
# 体在 hd_gun_ar.gd _ar_an94（HDGunLib 高模件，大型双室制退器 + 回转星形
# 觇孔表尺 + 右倾 AK-74 弧匣 + 侧折骨架托；超点射机制见 guns.cd_profile）
# sr25（2026-10 商店枪 SR25 射手步枪）：群星赛季新枪并入步枪册——几何体在
# hd_gun_ar.gd _ar_sr25（HDGunLib 高模件，KAC 浮置肋条护木 + 大直径战术
# 消音器 + 伸缩精准枪托；半自动 tap 门见 guns.gd auto=false）


## id 是否属于步枪册（_build_gun_visual 的分发判据）
static func _ar_has(id: String) -> bool:
	return AR_IDS.has(id)


## 统一入口：按 id 拼一把枪身根；未知 id 返回空 Node3D（防御不崩）。
## 高模重建后几何体在 hd_gun_ar.gd（AR_LIB.build，HDGunLib 工具件拼装）——
## 本签名逐字不动（_build_gun_visual / test_huodai 顶点红线断言都走此处），
## 材质仍由 _ar_mats 传参注入（新文件零材质创建）
static func _ar_build(id: String) -> Node3D:
	var bl := _bl_gun(id)
	if bl != null:
		return bl
	var mats := _ar_mats()
	# M14 专属配件解锁态随材质包传给枪匠（视觉件挂装；静态工厂无法读实例
	# provider——用 OS 环境变量 HD_M14_MODS 由 main/探针写入，缺省=原版）
	if id == "m14":
		var mods_env := OS.get_environment("HD_M14_MODS")
		mats["_m14_mods"] = {
			"foregrip": mods_env.contains("foregrip"),
			"extmag": mods_env.contains("extmag"),
		}
	return AR_LIB.build(id, mats)


## 弹匣动画节点覆盖（hd_guns 枪架局部坐标 = 枪身局部 × GUN_SCALE≈0.62 换算）：
## 返回 {"pos": Vector3, "size": Vector3, "show": bool}，缺省键由 hd_guns 用
## MAG_POS / 通用盒 0.055×0.17×0.09 / true 兜底。枪身上的弹匣井已按各 id 的
## 合同弹匣落点（÷0.62 反推）建模，动画匣顶恰好插进井口。
static func _ar_mag_of(id: String) -> Dictionary:
	match id:
		"akm":
			# 特征② 大弧度弯月 30 发匣（「山羊角」）：真匣是枪身建模件
			# （hd_gun_ar.gd mag_banana 独立命名节点 + HDGunLib.curved_mag
			# 四段 12° 弧，弧向前），动画匣隐（同 MP5/P90/MK4「匣形由枪身
			# 件表达」先例）；pos/size 保留 = 换弹手锚与掉匣替身缩放沿用
			# 原值（契约机制不变，只切 show）
			return {"pos": Vector3(0.02, -0.13, -0.15),
					"size": Vector3(0.05, 0.19, 0.08), "show": false}
		"scarh":
			# 特征⑤ 宽直体 20 发 7.62 匣：真匣是枪身建模件（mag_wide 独立
			# 命名节点 + curved_mag 三段 4° 微弧），动画匣隐；pos/size 保留
			return {"pos": Vector3(0.02, -0.13, -0.16),
					"size": Vector3(0.058, 0.20, 0.095), "show": false}
		"m4a1":
			# 特征⑦ 微弯梯形 STANAG 30 发直匣（弧度远小于 AKM）：真匣是
			# 枪身建模件（mag_stanag 独立命名节点 + curved_mag 三段 5°
			# 微弧），动画匣隐；pos/size = 原缺省兜底值 MAG_POS/通用盒
			# 逐字保留（原走 _ → {} 缺省分支，现显式化后仅 show 翻转）
			return {"pos": Vector3(0.02, -0.14, -0.16),
					"size": Vector3(0.055, 0.17, 0.09), "show": false}
		"m14":
			# 特征⑩ 黑色磷化 20 发钢直匣微前倾：真匣是枪身建模件（mag_dmr
			# 独立命名节点 + curved_mag 三段 5° 微弧），动画匣隐（照 scarh
			# 「匣形由枪身件表达」先例）；pos=换弹手锚（枪身局部匣中
			# (0,-0.095,-0.085)+Δ(0,0.006,-0.1568) 后 ×0.62 ≈ (0,-0.055,-0.150)）、
			# size=匣外形（掉匣替身缩放基准，同 scarh 口径用枪身局部原值）
			return {"pos": Vector3(0.0, -0.055, -0.150),
					"size": Vector3(0.042, 0.15, 0.072), "show": false}
		"asval":
			# 特征⑧ 40 发聚合物长弧匣（用户定案 40 发，匣体等比拉长）：真匣
			# 是枪身建模件（mag_val 独立命名节点 + curved_mag 四段 6° 微弧 +
			# 加密横肋），动画匣隐（照 scarh「匣形由枪身件表达」先例）；
			# pos=换弹手锚（枪身局部匣中段 (0,-0.19,-0.098)+Δ(0,0.006,-0.0768)
			# 后 ×0.62 ≈ (0,-0.114,-0.118)）、size=匣外形（掉匣替身缩放基准，
			# 同 m14 口径用枪身局部原值）
			return {"pos": Vector3(0.0, -0.114, -0.118),
					"size": Vector3(0.048, 0.245, 0.082), "show": false}
		"k416":
			# 特征⑧ STANAG 微弯聚合物 30 发匣（横向筋条刻度）：真匣是枪身
			# 建模件（mag_k416 独立命名节点 + curved_mag 三段 5° 微弧 + 横肋
			# ×3），动画匣隐（照 m4a1「匣形由枪身件表达」先例）；pos=换弹手锚
			# （枪身局部匣中 (0,-0.1455,-0.163)+Δ(0,0.008,-0.0768) 后 ×0.62
			# ≈ (0,-0.085,-0.149)）、size=匣外形（掉匣替身缩放基准，同 m14
			# 口径用枪身局部原值）
			return {"pos": Vector3(0.0, -0.085, -0.149),
					"size": Vector3(0.05, 0.175, 0.09), "show": false}
		"an94":
			# 特征⑥ AK-74 式 30 发弧匣明显向右倾斜 ~10°（机匣左侧布置复进簧
			# 让位——第二识别特征，文字资料为准）：真匣是枪身建模件
			# （mag_an94 独立命名节点整体绕 Z 转 10° + curved_mag 四段 13° 弧
			# 弧向前 + 横肋×3），动画匣隐（照 m4a1「匣形由枪身件表达」先例）；
			# pos=换弹手锚（枪身局部匣中段 (0.016,-0.146,-0.124)——x 分量 =
			# 右倾 sin10°×匣半长 0.09、z 含弧向前偏、+Δ(0,0.008,-0.0768) 后
			# ×0.62 ≈ (0.010,-0.086,-0.124)）、size=匣外形（掉匣替身缩放基准，
			# 同 m14 口径用枪身局部原值）
			return {"pos": Vector3(0.010, -0.086, -0.124),
					"size": Vector3(0.048, 0.18, 0.076), "show": false}
		"sr25":
			# 特征⑦ 20 发 7.62 直-微弧弹匣（平直略带弧度、侧面加强筋×3）：
			# 真匣是枪身建模件（mag_sr25 独立命名节点 + curved_mag 三段 4°
			# 微弧 + 横筋×3），动画匣隐（照 k416「匣形由枪身件表达」先例）；
			# pos=换弹手锚（枪身局部匣中段 (0,-0.1255,-0.149)+Δ(0,0.008,
			# -0.0768) 后 ×0.62 ≈ (0,-0.073,-0.138)）、size=匣外形（掉匣替身
			# 缩放基准，同 m14/k416 口径用枪身局部原值）
			return {"pos": Vector3(0.0, -0.073, -0.138),
					"size": Vector3(0.048, 0.155, 0.078), "show": false}
	return {}


## 机瞄/镜座挂点 (my, mz, fz)（枪身局部，喂 hd_guns._scope_visual）：
## my 按各枪最高件给值（M4A1 提把顶 / AKM 准星翼 / SCAR 顶轨齿尖），
## 数值为计划 interfaces 定的初值，截图验收时可整体微调
static func _ar_scope_anchor(id: String) -> Vector3:
	match id:
		"m4a1":
			return Vector3(0.085, -0.06, -0.38)
		"akm":
			return Vector3(0.07, -0.04, -0.40)
		"scarh":
			return Vector3(0.09, -0.08, -0.45)
		"m14":
			# 机匣顶 0.076 / 照门觇孔板顶 0.110——镜座挂机匣中段（真实
			# 准星/照门为建模件，iron 不叠兜底机瞄片，见 _finish_gun）
			return Vector3(0.08, -0.05, -0.40)
		"asval":
			# (my, mz, fz) = 镜座安装面高 0.08（防尘盖顶 0.078）/ 镜体中心
			# z -0.04（机匣中后段）/ 前准星 z -0.52——前柱准星与 U 型缺口
			# 照门均为建模件（考证超长瞄准基线），iron 不叠兜底机瞄片，
			# 见 _finish_gun
			return Vector3(0.08, -0.04, -0.52)
		"k416":
			# (my, mz, fz) = 镜座安装面高 0.083（全长顶轨楔齿尖）/ 镜体中心
			# z -0.06（机匣中段）/ 前准星 z -0.49（导气座折叠准星）——折叠
			# 准星 + 折叠照门均为建模件（ref_01 机匣顶部红点镜挂点），iron
			# 不叠兜底机瞄片，见 _finish_gun
			return Vector3(0.083, -0.06, -0.49)
		"an94":
			# (my, mz, fz) = 镜座安装面高 0.068（聚合物外壳顶面上沿——原型无
			# 皮卡汀尼顶轨，瞄具走左置侧导轨，本作挂点统一放壳顶平台，星形
			# 表尺在更后位 0.045 让位）/ 镜体中心 z -0.06（机匣中段）/ 前准星
			# z -0.558（制退器后准星座柱）——柱形准星 + 星形转盘觇孔均为考证
			# 建模件，iron 不叠兜底机瞄片，见 _finish_gun
			return Vector3(0.068, -0.06, -0.558)
		"sr25":
			# (my, mz, fz) = 镜座安装面高 0.083（全长顶轨楔齿尖，k416 同值）/
			# 镜体中心 z -0.06（机匣中段）/ 前准星 z -0.48（护木前端折叠立式
			# 准星）——折叠准星 + 尾部轨上折叠觇孔照门均为建模件（ref_04 特
			# 写），iron 不叠兜底机瞄片，见 _finish_gun
			return Vector3(0.083, -0.06, -0.48)
	return Vector3(0.085, -0.1, -0.42)   # 兜底 = M7 机瞄位


## ---------------- 内部：步枪册材质工厂（三枪高模几何在 hd_gun_ar.gd） ----------------


## 材质工厂：dark/wood/steel/fde/walnut 五种参数照抄 hd_guns.gd 的
## _build_gun_visual 材质段（一律 no_depth_test + render_priority 10 +
## 微自发光保暗处可读）；另加本文件新枪专用三种：polymer 纯黑聚合物（M4A1
## 全黑件）/ blued 深灰蓝钢（AKM 冲压机匣）/ bakelite 橙棕电木（AKM 握把）；
## 再加 M14 射手步枪专用五色（m14walnut/m14fg/m14steel/m14black/m14dark，
## 官方考证配色分区，见函数内 m14 段注释）
static func _ar_mats() -> Dictionary:
	# 2026-10 判图收敛：glow 0.55→0.42（顶灯/vm_sun 直射下深色面整片翻白
	# ——「白盘/发光白面/串色」案，同 _smg_mats 头注）；steel/fde/walnut
	# 压档——亮钢不再银白、FDE/胡桃木保色深一档，层次关系不变
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.11, 0.125)
	dark.metallic_specular = 0.1
	dark.no_depth_test = true
	dark.render_priority = 10
	dark.emission_enabled = true
	dark.emission = Color(0.125, 0.14, 0.155)
	dark.emission_energy_multiplier = 0.32
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.10, 0.072, 0.048)
	wood.metallic_specular = 0.1
	wood.no_depth_test = true
	wood.render_priority = 10
	wood.emission_enabled = true
	wood.emission = Color(0.09, 0.06, 0.035)
	wood.emission_energy_multiplier = 0.32
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.115, 0.125, 0.14)
	steel.metallic_specular = 0.1
	steel.no_depth_test = true
	steel.render_priority = 10
	steel.emission_enabled = true
	steel.emission = Color(0.12, 0.13, 0.145)
	steel.emission_energy_multiplier = 0.32
	var fde := StandardMaterial3D.new()   # 沙 tan FDE（SCAR-H 机匣/托体，色近 M7）
	fde.albedo_color = Color(0.30, 0.25, 0.175)
	fde.metallic_specular = 0.1
	fde.no_depth_test = true
	fde.render_priority = 10
	fde.emission_enabled = true
	fde.emission = Color(0.23, 0.195, 0.13)
	fde.emission_energy_multiplier = 0.32
	var walnut := StandardMaterial3D.new()   # 胡桃木（AKM 木质三件套）
	walnut.albedo_color = Color(0.10, 0.072, 0.048)
	walnut.roughness = 0.85
	walnut.metallic_specular = 0.1
	walnut.no_depth_test = true
	walnut.render_priority = 10
	walnut.emission_enabled = true
	walnut.emission = Color(0.09, 0.062, 0.043)
	walnut.emission_energy_multiplier = 0.32
	var polymer := StandardMaterial3D.new()   # 纯黑聚合物（M4A1 全黑主体）
	polymer.albedo_color = Color(0.07, 0.075, 0.085)
	polymer.roughness = 0.85
	polymer.metallic_specular = 0.1
	polymer.no_depth_test = true
	polymer.render_priority = 10
	polymer.emission_enabled = true
	polymer.emission = Color(0.1, 0.105, 0.115)
	polymer.emission_energy_multiplier = 0.32
	var blued := StandardMaterial3D.new()   # 深灰蓝钢（AKM 冲压机匣/枪管）
	blued.albedo_color = Color(0.15, 0.16, 0.185)
	blued.metallic_specular = 0.1
	blued.no_depth_test = true
	blued.render_priority = 10
	blued.emission_enabled = true
	blued.emission = Color(0.185, 0.195, 0.22)
	blued.emission_energy_multiplier = 0.32
	var bakelite := StandardMaterial3D.new()   # 橙棕电木（AKM 下置握把）
	bakelite.albedo_color = Color(0.37, 0.20, 0.095)
	bakelite.roughness = 0.8
	bakelite.metallic_specular = 0.1
	bakelite.no_depth_test = true
	bakelite.render_priority = 10
	bakelite.emission_enabled = true
	bakelite.emission = Color(0.28, 0.155, 0.078)
	bakelite.emission_energy_multiplier = 0.32
	# ---- M14 射手步枪专用五色（2026-10 商店枪，官方考证配色分区；mk 闭包
	#      照 _smg_mats/_lmg_mats 先例，glow 0.32 同本工厂家族口径）----
	#      m14walnut 胡桃木托 #6B4A32（emission=木纹暗部 #4E3524）/
	#      m14fg 玻纤棕护木 #7A5C43 / m14steel 磷化深灰钢 #3A3D40 /
	#      m14black 近黑细节件 #1F2124（消焰器/弹匣/照门）/ m14dark 哑光黑
	#      小件 #26282B（背带环/快慢机/扳机，roughness 0.9 哑光）
	#      roughness 口径对齐本工厂老八色（全部不设=1.0 全粗糙）：m14steel
	#      首轮判图自查曾设 0.5 半光泽——机匣后端面/护圈底梁正对镜头+vm_fill
	#      的面宽镜面高光整面爆白（读作「白色异物」），提回 0.95 消 specular；
	#      emission 同步收回家族比例 ≈1.1× albedo（首版 #5C6065=1.59× 抬底亮，
	#      「棱线高光」意图降为微提，端面不再发白）
	var mk14 := func(c: Color, e: Color, rough := 0.95) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic_specular = 0.1
		m.no_depth_test = true
		m.render_priority = 10
		m.emission_enabled = true
		m.emission = e
		m.emission_energy_multiplier = 0.32
		return m
	# 注：Callable.call() 回 Variant——这里必须显式注类型（:= 推断自 Variant
	# 会被「warning treated as error」拦下，见 _smg_mats 的 mp7mag 先例）
	var m14walnut: StandardMaterial3D = mk14.call(Color(0.42, 0.29, 0.196),
			Color(0.306, 0.208, 0.141), 0.8)
	var m14fg: StandardMaterial3D = mk14.call(Color(0.478, 0.361, 0.263),
			Color(0.34, 0.26, 0.19), 0.75)
	var m14steel: StandardMaterial3D = mk14.call(Color(0.227, 0.239, 0.251),
			Color(0.25, 0.262, 0.276), 0.95)
	var m14black: StandardMaterial3D = mk14.call(Color(0.122, 0.129, 0.141),
			Color(0.15, 0.16, 0.175), 0.6)
	var m14dark: StandardMaterial3D = mk14.call(Color(0.149, 0.157, 0.169),
			Color(0.17, 0.18, 0.195), 0.9)
	# ---- AS Val 特种突击步枪专用五色（2026-10 商店枪，官方考证配色；mk14
	#      闭包同参复用——glow 0.32 家族口径，暗处可读三件套不缺）----
	#      vsteel 黑色磷化钢 #1B1D1F（机匣/消音器/枪托骨架，rough 0.95 消
	#      端面镜面爆白——同 m14steel 教训）/ vpolym 哑光碳黑聚合物 #26282A
	#      （握把/弹匣/胶垫，rough 0.85 哑光）/ vplum 老化梅棕 #4A342B
	#      （护木锥罩，考证「黑或老化梅棕」取梅棕招牌色）/ vwear 冷灰磨损
	#      #6E7378（棱边露金属/滑动游标）/ vcover 防尘盖磨损高光 #3A3D40
	#      （旧枪面盖板）
	var vsteel: StandardMaterial3D = mk14.call(Color(0.106, 0.114, 0.122),
			Color(0.118, 0.126, 0.134), 0.95)
	var vpolym: StandardMaterial3D = mk14.call(Color(0.149, 0.157, 0.165),
			Color(0.165, 0.174, 0.183), 0.85)
	var vplum: StandardMaterial3D = mk14.call(Color(0.290, 0.204, 0.169),
			Color(0.32, 0.224, 0.186), 0.8)
	var vwear: StandardMaterial3D = mk14.call(Color(0.431, 0.451, 0.471),
			Color(0.474, 0.496, 0.518), 0.6)
	var vcover: StandardMaterial3D = mk14.call(Color(0.227, 0.239, 0.251),
			Color(0.25, 0.262, 0.276), 0.95)
	# ---- K416 突击步枪专用白刻字色（2026-10 商店枪，官方考证特征⑥：机匣
	#      侧面白色刻字厂标 AMET + 编号刻印；mk14 闭包同参复用）——近白灰
	#      #9DA2A8，黑枪身上读「白色激光刻印」、不刺眼
	var kmark: StandardMaterial3D = mk14.call(Color(0.616, 0.635, 0.659),
			Color(0.678, 0.698, 0.722), 0.6)
	return {"dark": dark, "steel": steel, "wood": wood, "fde": fde,
			"walnut": walnut, "polymer": polymer, "blued": blued,
			"bakelite": bakelite, "m14walnut": m14walnut, "m14fg": m14fg,
			"m14steel": m14steel, "m14black": m14black, "m14dark": m14dark,
			"vsteel": vsteel, "vpolym": vpolym, "vplum": vplum,
			"vwear": vwear, "vcover": vcover, "kmark": kmark}


## ================= 枪匠·机枪册（m250，SIG XM250 体系） =================
## 6.8×51mm 弹链机枪：几何体在 hd_gun_lmg.gd（LMG_LIB 路径 preload，不走裸
## 全局名——同 hd_gunlib/hd_gun_ar 先例：新文件必须随收尾提交入库，否则门槛
## 快照 preload 会失(FILE)）；材质走 _lmg_mats 工厂传参注入（新文件零材质
## 创建）。弹链袋/镜座挂点契约与步枪册同口径：_lmg_mag_of 动画匣隐（弹链袋
## mag_pouch 独立命名节点表达静置外形）、_lmg_scope_anchor 顶轨挂点。
## BATTLE_GUNS 的 lmg（大战场兵种配发枪）不在本册、原链路零改动。

const LMG_IDS := ["m250"]


## id 是否属于机枪册（_build_gun_visual 分发用）
static func _lmg_has(id: String) -> bool:
	return LMG_IDS.has(id)


## 统一入口：按 id 拼一把枪身根；未知 id 返回空 Node3D（防御不崩）。
## 高模重建后几何体在 hd_gun_lmg.gd（LMG_LIB.build，HDGunLib 工具件拼装）——
## 签名同 _ar_build 口径（_build_gun_visual / test_huodai 顶点红线断言都走
## 此处），材质仍由 _lmg_mats 传参注入（新文件零材质创建）
static func _lmg_build(id: String) -> Node3D:
	var bl := _bl_gun(id)
	if bl != null:
		return bl
	return LMG_LIB.build(id, _lmg_mats())


## 弹匣动画节点覆盖（hd_guns 枪架局部坐标 = 枪身局部 × GUN_SCALE≈0.62 换算）：
## 75 发软式弹链袋是枪身建模件（hd_gun_lmg.gd mag_pouch 独立命名节点 +
## 倒角盒堆叠软袋质感），动画匣隐（同 MK4/AR 三枪「匣形由枪身件表达」先例，
## 方形软袋也无直盒可替）；pos=袋中段（换弹手抓握锚，袋顶枪身局部
## y -0.053 ×0.62 ≈ -0.033 对齐锚顶）、size=袋外形 ×0.62（掉匣替身缩放基准）
static func _lmg_mag_of(id: String) -> Dictionary:
	match id:
		"m250":
			return {"pos": Vector3(0.0, -0.125, -0.053),
					"size": Vector3(0.049, 0.095, 0.066), "show": false}
	return {}


## 机瞄/镜座挂点 (my, mz, fz)（枪身局部，喂 hd_guns._scope_visual）：
## my 对齐各枪最高件下沿附近——开镜 AABB 量顶不悬空（mk4 口径）
static func _lmg_scope_anchor(id: String) -> Vector3:
	match id:
		"m250":
			## 顶轨齿顶 0.083 / 机匣中后段（供弹盖后）/ 护木前段——裸顶轨
			## （考证清单⑬：XM157 整体省略，镜座挂点照 mk4 写法）
			return Vector3(0.08, -0.12, -0.5)
	return Vector3(0.085, -0.1, -0.5)


## 机枪册材质工厂：M250 专用 FDE 沙黄配色分区（照 _smg_mats 的 mk 闭包抄——
## no_depth_test 防贴墙吞枪 + render_priority 10 + 微自发光保暗处可读）：
## fde 沙黄主体 #B09A68（机匣/护木/枪托/握把）/ supp 消音器沙棕 #8F7452 /
## dark 近黑件 #232323（枪管/导气箍/两脚架/供弹盖/抛壳盖/锁环/拉机柄）/
## steel 亮钢 #C9C9C9（内六角螺丝/缓冲筒等亮色点缀）/ canvas 弹链袋卡其
## #C2A878 / webbing 织带插扣深棕 #4A3F30 / brass 黄铜弹链 #B08D3E（唯一暖金）
static func _lmg_mats() -> Dictionary:
	var mk := func(c: Color, e: Color, rough := 0.55, glow := 0.42) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic_specular = 0.1
		m.no_depth_test = true
		m.render_priority = 10
		m.emission_enabled = true
		m.emission = e
		m.emission_energy_multiplier = glow
		return m
	# 2026-10 判图收敛：「发光白面」主源 = fde 0.69/steel 0.788/canvas 0.761
	# 大面在顶灯+vm_sun 直射下整片翻白——全部压档，glow 0.55→0.42；黄铜
	# 点缀 0.69→0.58 保金色不刺眼
	return {
		"fde": mk.call(Color(0.20, 0.175, 0.12), Color(0.125, 0.11, 0.075), 0.7, 0.42),
		"supp": mk.call(Color(0.19, 0.155, 0.11), Color(0.115, 0.09, 0.065), 0.6, 0.42),
		"dark": mk.call(Color(0.105, 0.105, 0.107), Color(0.13, 0.13, 0.132), 0.55, 0.42),
		"steel": mk.call(Color(0.10, 0.10, 0.105), Color(0.08, 0.08, 0.085), 0.5, 0.42),
		"canvas": mk.call(Color(0.23, 0.20, 0.15), Color(0.135, 0.12, 0.085), 0.9, 0.42),
		"webbing": mk.call(Color(0.17, 0.15, 0.115), Color(0.13, 0.115, 0.09), 0.9, 0.42),
		"brass": mk.call(Color(0.23, 0.185, 0.085), Color(0.185, 0.15, 0.068), 0.3, 0.3),
	}


## ================= 枪匠·旧五枪高模重建（HDGunLib） =================
## pistol/smg/rifle/shotgun/sniper：原 _build_gun_visual 内联 BoxMesh 直角
## 拼装整体升级为工具库高模件（倒角盒/高分段枪管/开筒护木/环件/指棱握把）。
## 契约零改动：本段只造枪身根——镜体仍由 _finish_gun 统一挂（挂点常量见
## _old5_scope_anchor，逐字保留原分支值）、动画弹匣/掉匣替身/火光仍由
## _mount_slot 统一挂、换弹手部锚点与换弹三段时间轴原样保留。
## 顶点红线：HDGunLib.POLY_MIN 五把（= 8× POLY_BASE，基线为 git HEAD 旧模
## 机械清点，构成式见 POLY_BASE 注）。材质走 _old5_mats 工厂传参注入
## （GUN_LIB 见上方枪匠段头，路径 preload、不走裸全局名）。
## 弹匣契约（2026-10 二轮观感修复）：_old5_mag_of 五把全覆盖、动画匣一律
## show=false——静置真匣由枪身建模件表达：smg=mag_thompson（curved_mag 4°
## 弧+钢底板）/ rifle=mag_m7（5° 弧）/ sniper=mag_internal（匣体+钢底板）/
## pistol=匣入握把（握把底钢垫板两层台阶）/ shotgun=管供弹无盒匣（类型正确）；
## pos=换弹手锚（静置匣握持点）、size=掉匣替身缩放基准（枪架局部 = 枪身 ×0.62）。

const OLD5_IDS := ["pistol", "smg", "rifle", "shotgun", "sniper"]


## id 是否属于旧五枪（_build_gun_visual 分发用）
static func _old5_has(id: String) -> bool:
	return OLD5_IDS.has(id)


## 实拍枪模（Poly Haven CC0）：keep = 要保留的网格（文件里还有另一款握把的
## 整枪、散放弹匣、子弹，一律剔除）；模型原生枪口朝 +X、枪托朝 -X
const PH_GUNS := {
	"pistol": {"path": "res://assets/pbr/models/service_pistol/service_pistol_2k.gltf",
		"keep": ["service_pistol_pistol_a", "service_pistol_slide_a",
				"service_pistol_hammer_a", "service_pistol_trigger_a"],
		# 握把顶（虎口位）：扳机后方、套筒底下（模型原生坐标，离线量网格得出）
		"grip": Vector3(-0.012, 0.036, 0.0)},
	"sniper": {"path": "res://assets/pbr/models/bolt_action_rifle_7_62/bolt_action_rifle_7_62_2k.gltf",
		"keep": ["bolt_action_rifle_7_62", "bolt_action_rifle_7_62_scope",
				"bolt_action_rifle_7_62_wrap", "bolt_action_rifle_7_62_bolt_a",
				"bolt_action_rifle_7_62_trigger"],
		# 栓动步枪无手枪握把：持握点 = 扳机后方枪托腕部顶面
		"grip": Vector3(-0.33, 0.012, 0.0)},
}


## Blender 写实枪（美术写实化第五轮，tools/blender/make_gun.py + guns/<id>.py）：
## 真实尺寸建模、Cycles 烘焙 AO/棱边磨损/倒角法线后，导出时已等比缩放平移到
## 本枪程序化枪身局部（握把点对 grip、全长对原长）——这里只补命名锚点：
## grip = 程序化 grip_hold 位置（HOLD_DELTA 照旧推到 MK4 基准）、
## mag = 程序化静置弹匣节点名与位置（合并器保留空锚点，测试按名找）。
## 模型缺失（另一台电脑没 git lfs pull）返回 null → 走原程序化枪身
const BL_GUN_DIR := "res://assets/pbr/models/guns/"
const BL_GUNS := {
	# anchor = 镜座锚 (安装面高 y, 镜体中心 z, 准星 z)：AK 无顶导轨，按导气管
	# 导轨式前置红点（UltiMAK 式）落在上护木顶面
	"akm": {"grip": Vector3(0.0, -0.0165, 0.099),
		"mag": ["mag_banana", Vector3(0.0, -0.035, -0.17)],
		"anchor": Vector3(0.088, -0.36, -0.62)},
	# P90 TR：无机瞄，镜座锚 = 顶导轨；弹匣平躺枪顶导轨罩下
	"p90": {"grip": Vector3(0.0, -0.0494, 0.0446),
		"mag": ["mag_top", Vector3(0.0, 0.026, 0.06)], "mag_hand": Vector3(0.0, 0.04, 0.06),
		"anchor": Vector3(0.0586, -0.073, -0.1785)},
	"vector": {"grip": Vector3(0.0, -0.0199, 0.0017),
		"mag": ["mag_vector", Vector3(0.0, -0.077, -0.096)], "mag_hand": Vector3(0.0, -0.11, -0.096),
		"anchor": Vector3(0.0896, -0.135, -0.299)},
	# 汤姆逊 M1928A1：无导轨，镜座锚 = 机匣顶；真弹匣在扳机护圈正前（比程序化版靠后 16cm）
	"smg": {"grip": Vector3(0.0, -0.041, 0.1303),
		"mag": ["mag_thompson", Vector3(0.0, -0.109, 0.006)], "mag_hand": Vector3(0.0, -0.13, 0.006),
		"anchor": Vector3(0.0365, 0.03, -0.337)},
	# MP5A2：镜座锚 = 机匣顶（爪式座位）；30 发弯匣比程序化版靠前 7cm
	"mp5": {"grip": Vector3(0.0, -0.0192, -0.0439),
		"mag": ["mag_curved", Vector3(0.0, -0.108, -0.261)], "mag_hand": Vector3(0.0, -0.13, -0.27),
		"anchor": Vector3(0.066, -0.13, -0.447)},
	# MP7A1：弹匣插在握把里，握把居中——整枪比程序化版靠后 13cm
	"mp7": {"grip": Vector3(0.0, -0.042, 0.028),
		"mag": ["mag_pdw", Vector3(0.0, -0.183, 0.014)], "mag_hand": Vector3(0.0, -0.19, 0.014),
		"anchor": Vector3(0.028, -0.015, -0.153)},
	# UZI：无导轨，镜座锚 = 顶盖（照门与拉机钮之间）；32 发弹匣插在握把里
	"uzi": {"grip": Vector3(0.0, -0.0243, 0.0674),
		"mag": ["mag_uzi", Vector3(0.0, -0.156, 0.049)], "mag_hand": Vector3(0.0, -0.165, 0.049),
		"anchor": Vector3(0.034, 0.038, -0.133)},
	# M14：无导轨，镜座锚 = 机匣顶（照门之前）；20 发匣在扳机护圈正前（程序化表
	# 原值多叠了一次 Δ，换弹手锚改按模型真实位置）
	# mods = 专属配件可换部件 {配件名: [装上时挂的部件, 未装时挂的部件]}（同目录
	# <部件>.glb，与本体同坐标同倍率导出，原点叠放即对位）：扩容匣换 30 发长匣、
	# 战术护木加挂下导轨 + 垂直前握把
	"m14": {"grip": Vector3(0.0, -0.028, 0.155),
		"mag": ["mag_dmr", Vector3(0.0, -0.12, -0.024)], "mag_hand": Vector3(0.0, -0.13, -0.024),
		"anchor": Vector3(0.006, -0.06, -0.646),
		"mods": {"extmag": ["m14_mag30", "m14_mag20"], "foregrip": ["m14_foregrip", ""]}},
	# M7 = XM7 / SIG MCX-SPEAR：全长顶导轨，镜座锚取机匣段中部
	"rifle": {"grip": Vector3(0.0, -0.031, 0.0672),
		"mag": ["mag_m7", Vector3(0.0, -0.062, -0.15)],
		"anchor": Vector3(0.0627, -0.077, -0.599)},
	# 雷明顿 870：管式供弹无弹匣；无导轨，镜座锚 = 机匣顶
	"shotgun": {"grip": Vector3(0.0, 0.0024, 0.1206),
		"anchor": Vector3(0.028, -0.04, -0.574)},
	# 下列四把全长顶导轨：镜座锚取上机匣前段（真枪装红点/倍镜的常规位），
	# 不取导轨正中（那会把镜挂到护木前端）
	"m4a1": {"grip": Vector3(0.0, -0.0307, 0.07),
		"mag": ["mag_stanag", Vector3(0.0, -0.12, -0.14)], "mag_hand": Vector3(0.0, -0.14, -0.14),
		"anchor": Vector3(0.0574, -0.1, -0.5538)},
	# MK4 = SIG MPX 式 9mm 冲锋枪（虚构型号，短消音器 + 折叠骨架托）
	"mk4": {"grip": Vector3(0.0, -0.022, -0.0018),
		"mag": ["mag_straight", Vector3(0.0, -0.12, -0.183)], "mag_hand": Vector3(0.0, -0.14, -0.183),
		"anchor": Vector3(0.0692, -0.14, -0.4842)},
	"scarh": {"grip": Vector3(0.0, -0.0301, 0.0605),
		"mag": ["mag_wide", Vector3(0.0, -0.12, -0.15)], "mag_hand": Vector3(0.0, -0.14, -0.15),
		"anchor": Vector3(0.0731, -0.09, -0.5375)},
	# XM250：弹链袋挂机匣左下（与程序化 mag_pouch 位差 ≤1cm，锚点沿用）
	"m250": {"grip": Vector3(0.0, -0.05, 0.07),
		"mag": ["mag_pouch", Vector3(0.0, -0.053, -0.085)],
		"anchor": Vector3(0.0579, -0.1, -0.5097)},
}
## 枪模在 vm 独立视口里只有一盏相机平行光 + 补光：烘焙贴图按真实反照率做，
## 再加一档贴图自发光保暗处可读（程序化枪材质工厂同理，0.32~0.42）
const BL_GUN_GLOW := 0.3


static func _bl_gun(id: String) -> Node3D:
	# HD_NO_BL 非空 = 强制程序化枪身（A/B 对照开关，同 HD_NO_MERGE 用法）
	if not BL_GUNS.has(id) or OS.get_environment("HD_NO_BL") != "":
		return null
	var path := BL_GUN_DIR + id + ".glb"
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("[烽火地带] 写实枪模缺失：%s（另一台电脑请 git lfs pull，暂用程序化枪模）" % path)
		return null
	var spec: Dictionary = BL_GUNS[id]
	var root := Node3D.new()
	# 模型挂在 pivot 下：HOLD_DELTA 只平移 root 的直接子节点（须为 Node3D）
	var pivot := Node3D.new()
	pivot.name = "model"
	root.add_child(pivot)
	var model: Node3D = ps.instantiate()
	pivot.add_child(model)
	_bl_dress(model)
	# 专属配件部件：解锁态读 HD_M14_MODS（静态工厂读不到实例 provider，与程序化
	# M14 同一通道，main._sync_m14_mods_env 进局前写入）
	if spec.has("mods"):
		var on := OS.get_environment("HD_M14_MODS")
		for mid in spec["mods"]:
			var pick: String = spec["mods"][mid][0 if on.contains(str(mid)) else 1]
			if pick == "":
				continue
			var pp := BL_GUN_DIR + pick + ".glb"
			var part_ps: PackedScene = load(pp) if ResourceLoader.exists(pp) else null
			if part_ps == null:
				push_warning("[烽火地带] 写实枪配件缺失：%s" % pp)
				continue
			var part: Node3D = part_ps.instantiate()
			pivot.add_child(part)
			_bl_dress(part)
	var anchor := Node3D.new()
	anchor.name = "grip_hold"
	anchor.position = spec["grip"]
	root.add_child(anchor)
	if spec.has("mag"):
		var mg := Node3D.new()
		mg.name = str(spec["mag"][0])
		mg.position = spec["mag"][1]
		root.add_child(mg)
	# 模型自带真实机瞄（准星/照门/护耳），_finish_gun 不再叠旧版机瞄片
	root.set_meta("real_sights", true)
	if spec.has("anchor"):
		root.set_meta("scope_anchor", spec["anchor"])
	return root


## 写实枪模/瞄具材质：逐面覆盖（合并器取覆盖材质）——各向异性过滤、
## render_priority 10（29f 防线）、贴图乘法自发光保 vm 世界暗处可读
static func _bl_dress(model: Node) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m3.mesh.get_surface_count():
			var sm = m3.mesh.surface_get_material(si)
			if sm is StandardMaterial3D:
				var d: StandardMaterial3D = (sm as StandardMaterial3D).duplicate()
				d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				d.render_priority = 10
				d.emission_enabled = true
				d.emission = Color(1, 1, 1)
				d.emission_texture = d.albedo_texture
				# 乘法：发光 = 贴图 × 能量（缺省 ADD 是「白色 + 贴图」，整把枪泛白）
				d.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				d.emission_energy_multiplier = BL_GUN_GLOW
				m3.set_surface_override_material(si, d)


## 写实枪模可用（登记在册且文件已导入）——动画匣显隐等静态表据此切换：
## 模型自带弹匣时动画盒隐藏，缺模型回退程序化枪时照旧显示
static func _bl_ready(id: String) -> bool:
	return BL_GUNS.has(id) and OS.get_environment("HD_NO_BL") == "" \
			and ResourceLoader.exists(BL_GUN_DIR + id + ".glb")


## 写实瞄具模型（holo/reddot/optic/sniper/thermal → optic_<kind>.glb），材质同写实枪
static func _optic_model(kind: String) -> Node3D:
	var path := BL_GUN_DIR + "optic_" + kind + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var wrap := Node3D.new()
	wrap.name = "optic"
	var model: Node3D = ps.instantiate()
	wrap.add_child(model)
	_bl_dress(model)
	return wrap


## 造实拍枪身根：先造一遍原程序化枪身量出长度与持握锚（grip_hold），实拍
## 模型等比缩到同样长度，再平移到「实拍握把顶 = 原持握锚」——之后
## _build_gun_visual 的 HOLD_DELTA 照常把持握锚推到 MK4 基准，腰射位、
## 换弹手锚、开镜对位全部沿用原数据链。
## 实拍模型保留深度测试：枪模已在独立视口（own_world_3d）里，不会被墙吞；
## 旧枪的关深度测试写法套在真实模型上会让机匣内部件透到表面
static func _ph_gun(id: String) -> Node3D:
	var spec: Dictionary = PH_GUNS[id]
	var path: String = spec["path"]
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("[烽火地带] 实拍枪模缺失：%s（另一台电脑请 git lfs pull，暂用程序化枪模）" % path)
		return null
	var model: Node3D = ps.instantiate()
	var keep: Array = spec["keep"]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not keep.has(str(mi.name)):
			mi.get_parent().remove_child(mi)
			mi.free()
	var old: Node3D = _old5_build_legacy(id)
	var target := _aabb_in(old, old)
	var old_grip := target.get_center()
	var gh: Node = old.find_child("grip_hold", true, false)
	if gh is Node3D:
		old_grip = _pos_in(gh as Node3D, old)
	old.free()
	var root := Node3D.new()
	var pivot := Node3D.new()
	pivot.rotation.y = PI * 0.5   # +X 枪口 → -Z（枪身局部前方）
	root.add_child(pivot)
	pivot.add_child(model)
	var bb := _aabb_in(root, root)
	var k := target.size.z / maxf(bb.size.z, 0.001)
	pivot.scale = Vector3.ONE * k
	var grip_now: Vector3 = pivot.transform * Vector3(spec["grip"])
	pivot.position += old_grip - grip_now
	# 持握锚：与程序化枪同名同语义（测试 29c、换弹手都按它对齐）
	var anchor := Node3D.new()
	anchor.name = "grip_hold"
	anchor.position = old_grip
	root.add_child(anchor)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m3.mesh.get_surface_count():
			var sm = m3.mesh.surface_get_material(si)
			if sm is StandardMaterial3D:
				var d: StandardMaterial3D = (sm as StandardMaterial3D).duplicate()
				d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				m3.set_surface_override_material(si, d)
	return root


## 原程序化旧五枪（实拍模型的尺寸基准，也是模型缺失时的回退）
static func _old5_build_legacy(id: String) -> Node3D:
	match id:
		"pistol":
			return _old5_pistol()
		"sniper":
			return _old5_sniper()
	return Node3D.new()


## 节点原点在 space 节点空间的位置（沿父链累乘局部变换，不依赖入树）
static func _pos_in(n: Node3D, space: Node3D) -> Vector3:
	var t := Transform3D()
	var q: Node = n
	while q != space and q != null:
		if q is Node3D:
			t = (q as Node3D).transform * t
		q = q.get_parent()
	return t.origin


## 子网格在 space 节点空间的合并包围盒（静态版，不依赖入树）
static func _aabb_in(root: Node3D, space: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null:
			continue
		var t := Transform3D()
		var q: Node = m
		while q != space and q != null:
			if q is Node3D:
				t = (q as Node3D).transform * t
			q = q.get_parent()
		var a: AABB = t * m.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## 统一入口：按 id 造旧五枪枪身根；未知 id 返回空 Node3D（防御不崩）
static func _old5_build(id: String) -> Node3D:
	# 美术写实化：手枪/狙击换 Poly Haven 实拍扫描模型（CC0）；模型缺失
	# （另一台电脑没 git lfs pull）返回 null → 走下方原程序化枪身
	if PH_GUNS.has(id):
		var real := _ph_gun(id)
		if real != null:
			return real
	var bl := _bl_gun(id)
	if bl != null:
		return bl
	match id:
		"pistol":
			return _old5_pistol()
		"smg":
			return _old5_smg()
		"rifle":
			return _old5_rifle()
		"shotgun":
			return _old5_shotgun()
		"sniper":
			return _old5_sniper()
	return Node3D.new()


## 机瞄/镜座挂点 (my, mz, fz)（枪身局部，喂 hd_guns._scope_visual）——
## 五个向量 = 原内联分支 return 值逐字保留（瞄具挂点契约）
static func _old5_scope_anchor(id: String) -> Vector3:
	match id:
		"pistol":
			return Vector3(0.10, -0.04, -0.2)
		"smg":
			return Vector3(0.06, -0.04, -0.4)
		"rifle":
			return Vector3(0.085, -0.1, -0.42)
		"shotgun":
			return Vector3(0.095, -0.16, -0.38)
		"sniper":
			return Vector3(0.085, -0.1, -0.5)
	return Vector3(0.085, -0.1, -0.5)


## 弹匣动画节点覆盖（枪匠契约 mag_of，枪架局部坐标 = 枪身局部 × GUN_SCALE
## ≈0.62 换算）：五把动画匣一律隐（静置真匣由枪身建模件表达——汤姆逊盒匣/
## M7 弯匣/狙击内匣是独立命名节点、手枪匣入握把只露钢底板、霰弹管供弹无盒匣，
## 通用大动画盒不再出现在任何一支旧枪上）；pos=换弹手拔匣/插匣锚（静置匣
## 握持点）、size=掉匣替身缩放基准（=静置匣外形 × 0.62）
static func _old5_mag_of(id: String) -> Dictionary:
	match id:
		"pistol":
			# 匣插握把内（握把底 gun-local (0,-0.100,0.067) × 0.62）：
			# 座内不可见、握把底钢垫板即「匣底板」细节，动画匣隐
			return {"pos": Vector3(0.0, -0.062, 0.042),
					"size": Vector3(0.028, 0.068, 0.038), "show": false}
		"smg":
			# .45 盒式弹匣（枪身建模件 mag_thompson，curved_mag 4° 微弧）：
			# 匣身 gun-local 0.040×0.13×0.068，手锚=匣中下段握持点
			return {"pos": Vector3(0.0, -0.081, -0.096),
					"size": Vector3(0.025, 0.081, 0.042), "show": false}
		"rifle":
			# STANAG 微弯匣（枪身建模件 mag_m7，curved_mag 5° 微弧）：
			# 匣身 gun-local 0.046×0.14×0.078，手锚=匣中下段握持点
			return {"pos": Vector3(0.0, -0.084, -0.093),
					"size": Vector3(0.029, 0.087, 0.048), "show": false}
		"shotgun":
			# 管供弹无盒匣（类型正确性）：动画匣隐、无静置匣件；
			# 手锚=受弹口（机身底前 z -0.06），掉匣替身缩为携弹盒尺度
			return {"pos": Vector3(0.0, -0.003, -0.037),
					"size": Vector3(0.026, 0.025, 0.056), "show": false}
		"sniper":
			# 内置供弹匣（枪身建模件 mag_internal：匣体+钢底板微凸）：
			# 手锚=匣底握持点
			return {"pos": Vector3(0.0, -0.025, -0.012),
					"size": Vector3(0.032, 0.035, 0.059), "show": false}
	return {}


## 旧五枪材质工厂：五色参数照抄原 _build_gun_visual 材质段（关深度测试
## 防贴墙吞枪 + render_priority 10 + 微自发光保暗处可读）；rough=-1 =
## 不设 roughness（保持引擎默认，与原材质段逐字同参）
static func _old5_mats() -> Dictionary:
	# 2026-10 判图收敛：glow 0.55→0.42、steel/fde 压档（翻白/串色案，
	# 同 _ar_mats 头注；汤姆逊亮钢弹匣/枪机白块即 steel 直射翻白）
	var mk := func(c: Color, e: Color, rough := -1.0) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		if rough >= 0.0:
			m.roughness = rough
		m.metallic_specular = 0.1
		m.no_depth_test = true
		m.render_priority = 10
		m.emission_enabled = true
		m.emission = e
		m.emission_energy_multiplier = 0.32
		return m
	return {
		"dark": mk.call(Color(0.10, 0.11, 0.125), Color(0.125, 0.14, 0.155)),
		# wood/walnut 二轮收敛（判图「SMG 橙木托串色/霰弹枪发光白面」：
		# 0.45/0.38 橙棕直射翻白且色偏橙——压到深胡桃棕档）
		"wood": mk.call(Color(0.10, 0.072, 0.048), Color(0.075, 0.055, 0.037)),
		"steel": mk.call(Color(0.115, 0.125, 0.14), Color(0.12, 0.13, 0.145)),
		"fde": mk.call(Color(0.30, 0.25, 0.175), Color(0.25, 0.21, 0.145)),
		"walnut": mk.call(Color(0.10, 0.072, 0.048), Color(0.075, 0.055, 0.037), 0.85),
	}


## 侦察手枪（.45 半自动）——旧模特征全保留 + 高模细化：大滑套（尾部两侧
## 防滑竖纹×3 对）/枪管口冒/抛壳窗（右亮钢）/前后机械瞄具/后倾击锤/
## 滑套-握把框架过渡段/指棱握把（后倾 18°，匣入握把：底缘钢垫板两层台阶）
static func _old5_pistol() -> Node3D:
	var root := Node3D.new()
	var mats := _old5_mats()
	var steel: StandardMaterial3D = mats["steel"]
	var dark: StandardMaterial3D = mats["dark"]
	# 滑套（s10 倒角：直角棱线消除、棱线高光顺滑）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.055, 0.075, 0.30),
			Vector3(0, 0.045, -0.06), Vector3.ZERO, 0.003, 10)
	# 滑套尾部防滑竖纹×3 对（两侧嵌钢细条）
	for i in 3:
		GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.05, 0.008),
				Vector3(-0.0295, 0.045, 0.02 + 0.028 * float(i)), Vector3.ZERO,
				0.0006, 2)
		GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.05, 0.008),
				Vector3(0.0295, 0.045, 0.02 + 0.028 * float(i)), Vector3.ZERO,
				0.0006, 2)
	# 枪管口冒 + 抛壳窗（右侧亮钢片）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.03, 0.05),
			Vector3(0, 0.055, -0.21), Vector3.ZERO, 0.0015, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.022, 0.06),
			Vector3(0.0285, 0.05, -0.05), Vector3.ZERO, 0.0008, 3)
	# 前准星 + 后照门（滑套顶面前后）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.006, 0.012, 0.02),
			Vector3(0, 0.088, -0.19), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.018, 0.012, 0.02),
			Vector3(0, 0.089, 0.06), Vector3.ZERO, 0.0008, 3)
	# 框架过渡段（滑套下缘-握把顶的枪身嵌块）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.046, 0.028, 0.14),
			Vector3(0, -0.005, 0.02), Vector3.ZERO, 0.002, 4)
	# 击锤（后倾 14°）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.024, 0.026, 0.035),
			Vector3(0, 0.092, 0.075), Vector3(-14, 0, 0), 0.001, 3)
	# 后握把（指棱高模握把、后倾 18°、钢指棱提层次）——grip() 顶锚=旋转
	# 支点，旧 _add_grip 中心锚=旋转支点，迁移用矢量式（含 z！）：
	# pos = 旧盒心 + Rx(−18°)·(0, 0.055, 0) = (0, -0.048+0.0523, 0.05-0.0170)
	# = (0, 0.0043, 0.033)——8 角点与旧模偏差 ≤0.01mm（矩阵精算）
	var grp: Node3D = GUN_LIB.grip(root, dark, 0.11, Vector3(0, 0.0043, 0.033),
			18.0, 0.05, 0.07, steel)
	# 匣底板细节（.45 匣入握把：钢底板微凸于握把底，两层台阶读作可卸匣——
	# 随握把 -18° 同倾，挂在 grip 根节点下）
	GUN_LIB.chamfer_box(grp, steel, Vector3(0.062, 0.014, 0.088),
			Vector3(0, -0.117, 0), Vector3.ZERO, 0.001, 3)
	return root


## 汤姆逊 M1A1（.45 ACP）——考证特征全保留 + 高模细化：蓝钢机匣（倒角带
## 加宽 0.010 直棱消除 + 顶面运槽盖板/右抛壳窗/左尾缝线/前箍钢带破面）/
## 横向木护木/前竖握把/木质固定枪托（下斜托体+钢托底板）+ .45 盒式弹匣
## （mag_thompson 独立命名节点，4° 弧+钢底板）/右侧拉机柄带球钮/平直枪口/
## 固定觇孔照门/护耳前准星（木件全 walnut 色不变）
static func _old5_smg() -> Node3D:
	var root := Node3D.new()
	var mats := _old5_mats()
	var dark: StandardMaterial3D = mats["dark"]
	var steel: StandardMaterial3D = mats["steel"]
	var walnut: StandardMaterial3D = mats["walnut"]
	# 蓝钢机匣（s12 主倒角盒，倒角 10mm=机匣高 11.8%——3× 放大是清晰过渡
	# 倒角面，不是单条高光亮线；顶缘亮线=倒角面上的顺滑高光）+ 下机匣/弹匣井
	GUN_LIB.chamfer_box(root, dark, Vector3(0.06, 0.085, 0.36),
			Vector3(0, 0.025, -0.01), Vector3.ZERO, 0.010, 12)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.05, 0.05, 0.16),
			Vector3(0, -0.055, 0.03), Vector3.ZERO, 0.006, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.052, 0.05, 0.09),
			Vector3(0, -0.04, -0.155), Vector3.ZERO, 0.006, 6)
	# 机匣破面细节（打破大平面直棱）：顶面枪机运槽钢盖板（亮钢嵌面，凸 5mm）+
	# 右侧抛壳窗亮钢 + 左尾侧竖缝线 + 前箍钢带（机匣-木护木过渡）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.028, 0.008, 0.19),
			Vector3(0, 0.0705, -0.02), Vector3.ZERO, 0.0012, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.022, 0.055),
			Vector3(0.0305, 0.028, -0.06), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.003, 0.06, 0.005),
			Vector3(-0.031, 0.025, 0.1), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.062, 0.09, 0.012),
			Vector3(0, 0.02, -0.185), Vector3.ZERO, 0.0015, 3)
	# .45 盒式弹匣（独立命名节点 mag_thompson：原点=匣顶中心、curved_mag
	# 向下生长——4° 三段微弧 + 钢底板，亮钢与蓝钢机匣分层；匣顶 7mm 藏进
	# 弹匣井防接缝）
	var mag := Node3D.new()
	mag.name = "mag_thompson"
	mag.position = Vector3(0, -0.058, -0.155)
	root.add_child(mag)
	# 弹匣 dark（2026-10 二轮判图「SMG 银白弹匣」：steel 直射渲染 0.6+
	# 读作银白——近黑钢与蓝钢机匣分层保留）
	# 弹匣 dark（四刀压暗后 dark 渲 ~0.3 暗部级别；_old5_mats 无 blued 键）
	GUN_LIB.curved_mag(mag, dark, Vector3(0.04, 0.13, 0.068), 4.0, 3, 3)
	# 枪管（36 段高分段 + 枪口端螺纹环×2 作枪管箍）+ 平直枪口帽
	GUN_LIB.barrel(root, steel, 0.26, 0.034, Vector3(0, 0.03, -0.31),
			Vector3(90, 0, 0), 2, 36)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.024, 0.024, 0.03),
			Vector3(0, 0.03, -0.45), Vector3.ZERO, 0.0012, 4)
	# 前准星（基座 + 护耳双柱 + 准星柱，骑枪管上）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.026, 0.014, 0.02),
			Vector3(0, 0.054, -0.42), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.02, 0.005),
			Vector3(-0.01, 0.069, -0.42), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.005, 0.02, 0.005),
			Vector3(0.01, 0.069, -0.42), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.018, 0.005),
			Vector3(0, 0.066, -0.42), Vector3.ZERO, 0.0006, 2)
	# 固定觇孔照门（基座 + 照门片，机匣尾上）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.028, 0.022, 0.02),
			Vector3(0, 0.078, 0.06), Vector3.ZERO, 0.001, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.016, 0.006),
			Vector3(0, 0.088, 0.06), Vector3.ZERO, 0.0006, 2)
	# 右侧拉机柄（柄杆 + 球钮）+ 左侧弹匣卡笋
	GUN_LIB.chamfer_box(root, steel, Vector3(0.014, 0.016, 0.05),
			Vector3(0.038, 0.03, 0.05), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.02, 0.02, 0.02),
			Vector3(0.038, 0.03, 0.078), Vector3.ZERO, 0.001, 2)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.012, 0.012, 0.025),
			Vector3(-0.036, -0.005, 0.07), Vector3.ZERO, 0.0008, 3)
	# 横向木护木（walnut s10）+ 前竖握把（walnut s8 + 底垫）
	GUN_LIB.chamfer_box(root, walnut, Vector3(0.058, 0.062, 0.24),
			Vector3(0, -0.005, -0.27), Vector3.ZERO, 0.003, 10)
	GUN_LIB.chamfer_box(root, walnut, Vector3(0.034, 0.095, 0.048),
			Vector3(0, -0.09, -0.31), Vector3.ZERO, 0.002, 8)
	GUN_LIB.chamfer_box(root, walnut, Vector3(0.04, 0.012, 0.054),
			Vector3(0, -0.14, -0.31), Vector3.ZERO, 0.001, 3)
	# 扳机护圈 + 扳机
	GUN_LIB.chamfer_box(root, dark, Vector3(0.012, 0.01, 0.065),
			Vector3(0, -0.083, 0.03), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.028, 0.008),
			Vector3(0, -0.07, 0.045), Vector3.ZERO, 0.0008, 3)
	# 后握把（指棱高模握把、后倾 20°）——grip() 顶锚=旋转支点，旧
	# _add_grip 中心锚=旋转支点，迁移用矢量式（含 z！）：pos = 旧盒心
	# + Rx(−20°)·(0, 0.0575, 0) = (0, -0.095+0.054, 0.15-0.0197)
	# = (0, -0.0410, 0.1303)——8 角点与旧模偏差 ≤0.05mm（矩阵精算）
	GUN_LIB.grip(root, walnut, 0.115, Vector3(0, -0.0410, 0.1303), 20.0,
			0.046, 0.11)
	# 木质固定枪托（下斜 5°）+ 钢托底板——2026-10 判图「枪托衔接断缝」：
	# 托体 z 0.30→0.27 前移（托头 0.165 嵌入机匣尾 0.17 内 5mm，walnut 与
	# 机匣握把同色区互嵌读作一体托颈），托底板随行 0.405→0.375
	GUN_LIB.chamfer_box(root, walnut, Vector3(0.052, 0.095, 0.21),
			Vector3(0, -0.095, 0.27), Vector3(-5, 0, 0), 0.003, 10)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.056, 0.1, 0.014),
			Vector3(0, -0.115, 0.375), Vector3.ZERO, 0.0015, 6)
	return root


## M7 战斗步枪（XM7 / SIG MCX Spear 体系）——考证特征全保留 + 高模细化：
## FDE 大机匣（上/下/弹匣井全倒角盒）/全长顶轨（轨基 + 楔齿×8）/
## M-LOK 开槽圆护木（开筒 + 左右 4 + 底 3 负形槽板）/重枪管 + 大消焰器
## 双挡环/左折叠拉机柄/Magpul SL-M 式伸缩托（缓冲管 + 贴腮板 + 调节柄）/
## STANAG 微弯匣（mag_m7 独立命名节点）
static func _old5_rifle() -> Node3D:
	var root := Node3D.new()
	var mats := _old5_mats()
	var fde: StandardMaterial3D = mats["fde"]
	var dark: StandardMaterial3D = mats["dark"]
	var steel: StandardMaterial3D = mats["steel"]
	# FDE 大机匣：上机匣 + 下机匣 + 弹匣井（全倒角盒）
	GUN_LIB.chamfer_box(root, fde, Vector3(0.062, 0.075, 0.3),
			Vector3(0, 0.035, -0.01), Vector3.ZERO, 0.0035, 12)
	GUN_LIB.chamfer_box(root, fde, Vector3(0.055, 0.055, 0.17),
			Vector3(0, -0.02, 0.015), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, fde, Vector3(0.05, 0.045, 0.09),
			Vector3(0, -0.045, -0.15), Vector3.ZERO, 0.0025, 6)
	# STANAG 微弯匣（独立命名节点 mag_m7：原点=匣顶中心、curved_mag 向下
	# 生长——5° 三段微弧 + 底板，匣身 dark 聚合物与 FDE 机匣分层；匣顶
	# 5mm 藏进弹匣井防接缝）
	var mag := Node3D.new()
	mag.name = "mag_m7"
	mag.position = Vector3(0, -0.062, -0.15)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, dark, Vector3(0.046, 0.14, 0.078), 5.0, 3, 3)
	# 全长顶轨：轨基（s12）+ 连续楔齿×8（钢）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.028, 0.016, 0.56),
			Vector3(0, 0.078, -0.13), Vector3.ZERO, 0.0015, 12)
	for i in 8:
		GUN_LIB.chamfer_box(root, steel, Vector3(0.031, 0.006, 0.014),
				Vector3(0, 0.089, 0.12 - 0.065 * float(i)), Vector3.ZERO,
				0.001, 5)
	# M-LOK 开槽圆护木：开筒（尾封前开 + 内衬探出露壁厚）+ 左右 4 + 底 3 槽板
	GUN_LIB.tube(root, fde, 0.30, 0.070, Vector3(0, 0.02, -0.31),
			Vector3(90, 0, 0), 0.004, 4, dark, 4, 48)
	# 重枪管（36 段）+ 大消焰器（开筒内衬亮钢膛）+ 双挡环
	GUN_LIB.barrel(root, dark, 0.20, 0.030, Vector3(0, 0.03, -0.56),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.tube(root, dark, 0.09, 0.048, Vector3(0, 0.03, -0.705),
			Vector3(90, 0, 0), 0.003, 0, steel, 3, 32)
	GUN_LIB.torus_ring(root, steel, 0.019, 0.028, Vector3(0, 0.03, -0.675),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, steel, 0.019, 0.028, Vector3(0, 0.03, -0.735),
			Vector3(90, 0, 0))
	# 导气座 + 抛壳窗（右亮钢）+ 左折叠拉机柄（柄 + 头）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.022, 0.03, 0.035),
			Vector3(0, 0.055, -0.475), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.024, 0.07),
			Vector3(0.032, 0.04, -0.05), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.016, 0.02, 0.055),
			Vector3(-0.039, 0.045, 0.03), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.02, 0.02, 0.02),
			Vector3(-0.039, 0.045, 0.06), Vector3.ZERO, 0.001, 2)
	# 后握把（指棱高模握把、后倾 22°、钢指棱）——grip() 顶锚=旋转支点，
	# 旧 _add_grip 中心锚=旋转支点，迁移用矢量式（含 z！）：
	# pos = 旧盒心 + Rx(−22°)·(0, 0.0475, 0) = (0, -0.075+0.044, 0.085-0.0178)
	# = (0, -0.0310, 0.0672)——8 角点与旧模偏差 ≤0.05mm（矩阵精算）
	GUN_LIB.grip(root, dark, 0.095, Vector3(0, -0.0310, 0.0672), 22.0,
			0.038, 0.052, steel)
	# 扳机护圈 + 扳机
	GUN_LIB.chamfer_box(root, dark, Vector3(0.012, 0.008, 0.06),
			Vector3(0, -0.052, 0.02), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.043, 0.03), Vector3.ZERO, 0.0008, 3)
	# 伸缩托：缓冲管座 + 缓冲管开筒 + 托体（FDE）+ 贴腮板 + 橡胶托底板
	# + 侧调节柄 + 下调节楔
	GUN_LIB.chamfer_box(root, dark, Vector3(0.048, 0.065, 0.05),
			Vector3(0, 0.015, 0.165), Vector3.ZERO, 0.002, 6)
	GUN_LIB.tube(root, dark, 0.12, 0.034, Vector3(0, 0.012, 0.225),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	GUN_LIB.chamfer_box(root, fde, Vector3(0.042, 0.055, 0.15),
			Vector3(0, 0.01, 0.26), Vector3.ZERO, 0.0025, 10)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.018, 0.1),
			Vector3(0, 0.048, 0.27), Vector3.ZERO, 0.0012, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.05, 0.09, 0.028),
			Vector3(0, 0.002, 0.345), Vector3.ZERO, 0.0018, 6)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.012, 0.018, 0.028),
			Vector3(0.029, -0.02, 0.3), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.028, 0.018, 0.04),
			Vector3(0, -0.03, 0.3), Vector3.ZERO, 0.001, 3)
	return root


## 泵动霰弹（12 号）——旧模特征全保留 + 高模细化：木机身-木托-木泵托
## （整枪木色语言不变）/钢枪管 + 暗色弹管双管感/前后双钢管夹/顶部肋条 +
## 珠准星/泵动条纹×3/后托腕下斜握把。管供弹无盒匣（mag_of 动画匣隐、
## 无静置匣件——盒匣挂管供弹武器是类型错误）
static func _old5_shotgun() -> Node3D:
	var root := Node3D.new()
	var mats := _old5_mats()
	var wood: StandardMaterial3D = mats["wood"]
	var steel: StandardMaterial3D = mats["steel"]
	var dark: StandardMaterial3D = mats["dark"]
	# 木机身（机匣段：旧模整枪木色，机身-枪托连体语言保留）
	GUN_LIB.chamfer_box(root, wood, Vector3(0.058, 0.07, 0.22),
			Vector3(0, 0.04, -0.04), Vector3.ZERO, 0.003, 10)
	# 枪管（36 段 + 枪口箍纹环）+ 弹管（开筒，管尾藏机身内）
	# 枪管 dark（2026-10 二轮判图「霰弹枪发光白面」：steel 长管顶面直射
	# +镜面读作白亮长条——发黑钢管语义）
	GUN_LIB.barrel(root, dark, 0.50, 0.056, Vector3(0, 0.06, -0.35),
			Vector3(90, 0, 0), 1, 36)
	GUN_LIB.tube(root, dark, 0.44, 0.044, Vector3(0, -0.005, -0.34),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 32)
	# 双管夹（前后各一：连接枪管-弹管，环顶贴枪管底）
	GUN_LIB.torus_ring(root, steel, 0.0235, 0.037, Vector3(0, -0.005, -0.24),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, steel, 0.0235, 0.038, Vector3(0, -0.005, -0.515),
			Vector3(90, 0, 0))
	# 泵动前托（木）+ 泵动条纹×3（嵌暗色环纹）
	GUN_LIB.chamfer_box(root, wood, Vector3(0.06, 0.055, 0.15),
			Vector3(0, -0.005, -0.35), Vector3.ZERO, 0.0025, 8)
	for i in 3:
		GUN_LIB.chamfer_box(root, dark, Vector3(0.062, 0.057, 0.014),
				Vector3(0, -0.005, -0.405 + 0.055 * float(i)), Vector3.ZERO,
				0.0008, 2)
	# 顶部肋条（骑枪管背）+ 珠准星 + 后照门
	GUN_LIB.chamfer_box(root, steel, Vector3(0.02, 0.006, 0.4),
			Vector3(0, 0.092, -0.35), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.008, 0.014, 0.008),
			Vector3(0, 0.099, -0.535), Vector3.ZERO, 0.0008, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.02, 0.012, 0.014),
			Vector3(0, 0.082, 0.02), Vector3.ZERO, 0.0008, 3)
	# 抛壳口（右侧亮钢）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.02, 0.06),
			Vector3(0.03, 0.045, -0.02), Vector3.ZERO, 0.0008, 3)
	# 后托腕（指棱握把、后倾 15°）——grip() 顶锚=旋转支点，旧
	# _add_grip 中心锚=旋转支点，迁移用矢量式（含 z！）：
	# pos = 旧盒心 + Rx(−15°)·(0, 0.075, 0) = (0, -0.07+0.0724, 0.14-0.0194)
	# = (0, 0.0024, 0.1206)——8 角点与旧模偏差 ≤0.05mm（矩阵精算）
	GUN_LIB.grip(root, wood, 0.15, Vector3(0, 0.0024, 0.1206), 15.0,
			0.055, 0.10)
	# 枪托（木，下斜 5°）+ 橡胶托底板
	GUN_LIB.chamfer_box(root, wood, Vector3(0.048, 0.08, 0.30),
			Vector3(0, -0.015, 0.21), Vector3(-5, 0, 0), 0.0028, 10)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.052, 0.095, 0.016),
			Vector3(0, -0.05, 0.355), Vector3.ZERO, 0.0012, 6)
	return root


## 栓动狙击（M24 体系）——旧模特征全保留 + 高模细化：钢机匣（长钢身侧影
## 保留，尾段盖托腕顶）/木前托坐管/自带 6× 密位镜（镜体=枪身件：主筒+
## 物镜罩+目镜筒+前后环+双镜环镜座）/内置供弹匣（mag_internal：匣体+钢
## 底板微凸）/枪机球柄/木托+抬腮板/橡胶托底板
static func _old5_sniper() -> Node3D:
	var root := Node3D.new()
	var mats := _old5_mats()
	var dark: StandardMaterial3D = mats["dark"]
	var wood: StandardMaterial3D = mats["wood"]
	# 钢机匣（s12，尾段延伸到托腕——旧模长钢身侧影保留）+ 木前托（坐管）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.055, 0.075, 0.46),
			Vector3(0, 0.035, -0.10), Vector3.ZERO, 0.0035, 12)
	GUN_LIB.chamfer_box(root, wood, Vector3(0.05, 0.06, 0.32),
			Vector3(0, 0.005, -0.41), Vector3.ZERO, 0.0028, 8)
	# 内置供弹匣（独立命名节点 mag_internal：暗色匣体 + 钢底板微凸，
	# 匣顶 1mm 藏进机匣底——栓动枪「几乎不露匣」的低剖面）
	var mag := Node3D.new()
	mag.name = "mag_internal"
	root.add_child(mag)
	GUN_LIB.chamfer_box(mag, dark, Vector3(0.044, 0.045, 0.085),
			Vector3(0, -0.024, -0.02), Vector3.ZERO, 0.002, 4)
	GUN_LIB.chamfer_box(mag, dark, Vector3(0.052, 0.012, 0.095),
			Vector3(0, -0.049, -0.02), Vector3.ZERO, 0.001, 3)
	# 枪管（36 段重管 + 枪口螺纹环×2）
	GUN_LIB.barrel(root, dark, 0.48, 0.044, Vector3(0, 0.038, -0.72),
			Vector3(90, 0, 0), 2, 36)
	# 自带密位镜（镜体=枪身件，_finish_gun 的 sniper 分支不重复装镜）：
	# 主镜筒开筒 + 物镜罩（前环露亮钢口）+ 目镜筒 + 眼杯环 + 双镜环 + 双镜柱
	GUN_LIB.tube(root, dark, 0.20, 0.070, Vector3(0, 0.105, -0.30),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 32)
	GUN_LIB.tube(root, dark, 0.06, 0.090, Vector3(0, 0.105, -0.405),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, dark, 0.041, 0.048, Vector3(0, 0.105, -0.435),
			Vector3(90, 0, 0))
	GUN_LIB.tube(root, dark, 0.10, 0.056, Vector3(0, 0.105, -0.20),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, dark, 0.024, 0.030, Vector3(0, 0.105, -0.152),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, dark, 0.033, 0.041, Vector3(0, 0.105, -0.24),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, dark, 0.033, 0.041, Vector3(0, 0.105, -0.36),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, dark, Vector3(0.016, 0.03, 0.02),
			Vector3(0, 0.07, -0.24), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.016, 0.03, 0.02),
			Vector3(0, 0.07, -0.36), Vector3.ZERO, 0.0008, 3)
	# 枪机球柄（右后：柄杆贴机匣右面 + 球头）+ 抛壳口（右亮钢）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.014, 0.014, 0.10),
			Vector3(0.034, 0.045, 0.04), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.02, 0.02, 0.02),
			Vector3(0.034, 0.045, 0.095), Vector3.ZERO, 0.001, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.004, 0.024, 0.07),
			Vector3(0.0285, 0.04, -0.02), Vector3.ZERO, 0.0008, 3)
	# 后托腕（指棱高模握把、后倾 15°）——grip() 顶锚=旋转支点，旧
	# _add_grip 中心锚=旋转支点，迁移用矢量式（含 z！）：
	# pos = 旧盒心 + Rx(−15°)·(0, 0.07, 0) = (0, -0.055+0.0676, 0.10-0.0181)
	# = (0, 0.0126, 0.0819)——8 角点与旧模偏差 ≤0.03mm（矩阵精算）
	GUN_LIB.grip(root, dark, 0.14, Vector3(0, 0.0126, 0.0819), 15.0,
			0.05, 0.09)
	# 枪托（木，微下斜 3°）+ 抬腮板 + 橡胶托底板
	GUN_LIB.chamfer_box(root, wood, Vector3(0.05, 0.10, 0.34),
			Vector3(0, -0.045, 0.30), Vector3(-3, 0, 0), 0.003, 10)
	GUN_LIB.chamfer_box(root, wood, Vector3(0.045, 0.05, 0.12),
			Vector3(0, 0.015, 0.40), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.054, 0.11, 0.014),
			Vector3(0, -0.036, 0.47), Vector3(-3, 0, 0), 0.0012, 6)
	return root

