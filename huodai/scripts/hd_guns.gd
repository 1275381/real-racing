class_name HDGuns
extends Node3D
## 烽火地带枪械：双槽（primary/secondary）程序化拼枪 + ADS + 换弹（弹匣三段
## 掉落动画 + 程序化手套拔匣/插匣跟随）+ hitscan 结算。母本 onfoot.gd：枪模挂
## 相机（no_depth_test 材质防车身吞枪）、mount 用枪模 AABB 对准星正下方、曳光池。
## 输入动作名由 main 注册，本模块只读："hd_fire"/"hd_scope"/"hd_slot1"/
## "hd_slot2"/"hd_reload"。

signal fired
signal reloaded
signal hit_enemy(kind: String, idx: int, point: Vector3, dmg: float, head: bool)


const GUN_HIP_POS := Vector3(0.26, -0.22, -0.55)   # 腰射枪架位（onfoot 同款）
const GUN_ADS_Z := -0.45
const GUN_HIP_ROT := Vector3(2.5, 4.0, 3.0)
const GUN_SCALE := 0.62
const MAG_POS := Vector3(0.02, -0.14, -0.16)       # 枪上弹匣位（枪架局部）
const MUZZLE_OFF := Vector3(0.02, 0.06, -0.62)     # 枪口点（枪架局部，火光同位）
const HEADSHOT_MUL := 2.0                          # 爆头伤害倍率
const ADS_SPREAD := 0.1                            # 开镜散布倍率（onfoot 惯例）
const ADS_SPEED := 5.0
const MAG_REST_T := 4.0                            # 落地弹匣停留秒数（之后渐隐回收）
const HIDE_ZOOM := 3.0                             # 开镜倍率≥3 且到位 → 藏枪模

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

## 每发后坐力（度）：[基础上抬, 连发累增系数, 水平漂移幅度]（onfoot 同表）。
## 2026-10 扩充七枪：vector 最柔（Super V 卖点）/ akm·scarh 大后坐（7.62 世界观）；
## mk4 同 mp5 档（4.6×30 低后坐轻弹，缺键会吃 [0.4,0.2,0.25] 兜底后坐爆炸）
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
var _falling_mag: MeshInstance3D    # 掉落弹匣替身（世界空间，落地后 queue_free 惰性重建）
var _hand: Node3D                   # 换弹手部替身（相机子节点，与枪架同级，仅换弹可见）
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
		_slots[slot] = {"id": gid, "ammo": int(gi.get("mag", 12)),
				"reserve": _reserve_for_gun(gid)}
		# 同槽换了枪才重建枪模；同枪复用已有 holder（重复进场不堆积）。
		# 旧枪模释放前先隐身：queue_free 到帧末才生效，不隐身会同帧新旧两把
		# 枪模叠影一帧（切枪链上唯一的实存渲染缺陷，2026-10 黄壳排查中修掉）
		if _guns.has(slot) and str(_guns[slot]["id"]) != gid:
			var old: Dictionary = _guns[slot]
			var old_holder: Node3D = old["holder"]
			old_holder.visible = false
			old_holder.queue_free()
			(old["flash"] as OmniLight3D).queue_free()
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
	fire_cd = maxf(0.0, fire_cd - dt)
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
	if _cur_slot != slot_before:
		return   # 本帧切了枪：弹匣/摆位留给下一帧，别去摆旧枪
	var g := _cur_gun()
	if g.is_empty() or cur_id == "":
		return
	# ADS：按住右键开镜；进度与倍率每帧写给玩家（FOV=75/zoom 在玩家侧算）
	_aiming = Input.is_action_pressed("hd_scope")
	_ads = move_toward(_ads, 1.0 if _aiming else 0.0, dt * ADS_SPEED)
	player.ads = _ads
	player.zoom = current_zoom()
	# 开火（按住 = 全自动连发）：没弹自动换
	if Input.is_action_pressed("hd_fire") and fire_cd <= 0.0 and reloading <= 0.0:
		if ammo > 0:
			try_fire()
		else:
			start_reload()
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
			var mag_n: int = int(_g.get("mag", 12))
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
	# 枪架摆位：腰射位 ↔ 瞄准位（枪顶 AABB 对准星正下方，onfoot 同款）；
	# 3× 以上高倍镜开镜到位后隐藏枪模（镜筒贴脸挡屏，FOV 一缩还会放大数倍）
	var holder: Node3D = g["holder"]
	holder.visible = not (_aiming and _ads > 0.9 and current_zoom() >= HIDE_ZOOM)
	var ads_pos := Vector3(-GUN_SCALE * float(g["cx"]),
			-0.012 - GUN_SCALE * float(g["top"]), GUN_ADS_Z)
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


## 开一发：弹数/射线/曳光/伤害结算/后坐力/火光/枪声（按住自动连发）
func try_fire() -> void:
	if cur_id == "" or reloading > 0.0 or fire_cd > 0.0 or ammo <= 0:
		return
	if player == null or player.dead or player.cam == null:
		return
	ammo -= 1
	fire_cd = float(_g.get("cd", 0.13))
	var g := _cur_gun()
	if not g.is_empty():
		# 枪口火光：发光片贴枪口 + 瞬时点光（onfoot 同款 0.05s）
		var flash: OmniLight3D = g["flash"]
		var flash_mesh: MeshInstance3D = g["flash_mesh"]
		_flash_t = 0.05
		flash.visible = true
		flash.position = Vector3(0.2, -0.08, -0.85)
		flash_mesh.visible = true
		flash_mesh.position = MUZZLE_OFF
	# 射线：相机 from、-Z 前向、右/上基向量抖动 spread（每颗弹丸独立判定）
	var from: Vector3 = player.cam.global_position
	var base_dir: Vector3 = -player.cam.global_transform.basis.z
	var spread: float = float(_g.get("spread", 0.0)) * lerpf(1.0, ADS_SPREAD, _ads)
	var pellets: int = int(_g.get("pellets", 1))
	var max_r: float = float(_g.get("range", 250.0))
	var dmg: float = float(_g.get("dmg", 20.0))
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
	# 后坐力：视角上顶 + 水平随机漂移；开镜幅度 6 折（onfoot 公式照抄）
	var rc: Array = RECOIL.get(cur_id, [0.4, 0.2, 0.25])
	var mul: float = 0.6 if _aiming else 1.0
	player.recoil_pitch += deg_to_rad(rc[0] + rc[1] * player.recoil_pitch * 57.3 * 0.5) * mul
	player.recoil_yaw += deg_to_rad(randf_range(-rc[2], rc[2])) * mul
	player.recoil_cool = 0.0
	if audio != null:
		audio.play_shot(cur_id)


## R 键手动换弹（弹匣未满、有备弹、不在换弹中才生效；极致备弹经济下
## reserve=0 即弹尽粮绝——拒绝换弹不进动画）
func start_reload() -> void:
	if cur_id == "" or reloading > 0.0:
		return
	if ammo >= int(_g.get("mag", 12)) or reserve <= 0:
		return
	reloading = float(_g.get("reload", 1.5))
	if audio != null:
		audio.play_reload()


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


## 枪口世界坐标：当前枪架（相机子节点）局部的枪口点，与枪口火光同位
func muzzle_world() -> Vector3:
	var g := _cur_gun()
	if not g.is_empty():
		var holder: Node3D = g["holder"]
		return holder.to_global(MUZZLE_OFF)
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


## 挂一把枪（相机子节点）：holder 锚点 + AABB 量枪顶 + 弹匣块 + 枪口火光
func _mount_slot(slot: String) -> void:
	if player == null or player.cam == null:
		return
	var gid: String = str(_slots[slot]["id"])
	var gun := _build_gun_visual(gid)
	var holder := Node3D.new()
	# 锚点抬到视锥内（onfoot：原点在相机上时枪会落到画面底边之外）
	holder.position = GUN_HIP_POS
	holder.rotation_degrees = GUN_HIP_ROT
	player.cam.add_child(holder)
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
	var mag_box := BoxMesh.new()
	mag_box.size = mag_size
	var mag_mat := StandardMaterial3D.new()
	mag_mat.albedo_color = Color(0.16, 0.18, 0.22)
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
	holder.add_child(flash_mesh)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.35)
	flash.light_energy = 3.0
	flash.omni_range = 6.0
	flash.visible = false
	player.cam.add_child(flash)
	_guns[slot] = {"id": gid, "holder": holder, "mag": mag, "show_mag": show_mag,
			"mag_pos": mag_pos, "mag_size": mag_size,
			"flash": flash, "flash_mesh": flash_mesh, "top": top, "cx": cx}


## 全枪册弹匣参数（枪匠契约 mag_of）：返回 {"pos","size","show"} 子集；
## 未知 id 返回空字典——_mount_slot 用 MAG_POS/通用盒/true 兜底。
## 弹匣节点约定：动画弹匣永远是 holder 子节点；「真弹匣形状」由 size/show
## 控制动画匣、由枪身建模件表达静置外形（P90 顶匣/汤姆逊盒匣/手枪匣入握把/
## 霰弹管供弹无盒匣）
func _mag_override(gid: String) -> Dictionary:
	if _smg_has(gid):
		return _smg_mag_of(gid)
	if _ar_has(gid):
		return _ar_mag_of(gid)
	if _old5_has(gid):
		return _old5_mag_of(gid)
	return {}


## 程序化枪模分发：三路枪册分别到枪身工厂（只造枪身根 Node3D）——冲锋枪册
## _smg_build / 步枪册 _ar_build / 旧五枪 _old5_build（HDGunLib 高模重建，
## 见文件尾「旧五枪高模重建」段；原内联 BoxMesh 直角拼装已整体迁出）。
## 弹匣动画节点/枪口火光仍由 _mount_slot 统一挂、镜体由 _finish_gun 统一挂
## （瞄具挂点常量原样保留，换弹手部锚点与换弹三段时间轴零改动）
func _build_gun_visual(gun_id: String) -> Node3D:
	if _smg_has(gun_id):
		return _finish_gun(_smg_build(gun_id), gun_id,
				_smg_scope_anchor(gun_id))
	if _ar_has(gun_id):
		return _finish_gun(_ar_build(gun_id), gun_id,
				_ar_scope_anchor(gun_id))
	if _old5_has(gun_id):
		return _finish_gun(_old5_build(gun_id), gun_id,
				_old5_scope_anchor(gun_id))
	# 兜底（大战场 lmg 等未列枪）：空枪身 + 默认机瞄位（原行为等值）
	return _finish_gun(Node3D.new(), gun_id, Vector3(0.085, -0.1, -0.5))


## 枪顶瞄具模型统一收尾：装上的瞄具优先（iron=机瞄片）；狙击自带密位镜，
## 仅装热成像时在镜后加挂热成像单元（onfoot 分支照搬）。
## anchor = (my, mz, fz) 机瞄/镜座挂点（枪身局部）：旧五枪沿用原分支常量、
## 新枪来自枪匠文件 scope_anchor；狙击分支不用 anchor（自带镜例外）
func _finish_gun(root: Node3D, gun_id: String, anchor: Vector3) -> Node3D:
	var sc: Dictionary = _scope_info_for(gun_id)
	var s_kind: String = str(sc.get("kind", "iron"))
	if gun_id == "sniper":
		if s_kind == "thermal":
			_scope_visual(root, "thermal", 0.12, 0.05, -0.3)
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
			# 红点镜：短圆筒 + 底座
			cyl.call(0.024, 0.07, Vector3(0, top_y + 0.05, mid_z - 0.06), dk)
			box.call(Vector3(0.045, 0.03, 0.07), Vector3(0, top_y + 0.02,
					mid_z - 0.04), dk)
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


## 旧弹匣脱匣：从枪身弹匣井（手部拔匣的脱离点）转入世界空间下坠，
## 初速 = 枪前向 0.8 + 向下 0.4
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
	add_child(_falling_mag)


## 换弹手部替身：暗色战术手套低模（护腕 + 掌 + 四指各两节 + 拇指两节，
## BoxMesh 拼装），挂相机下与枪架同级；材质关深度测试同枪模；
## 懒重建（同掉落弹匣思路），仅换弹期间可见
func _ensure_hand() -> void:
	if _hand != null or player == null or player.cam == null:
		return
	var hand := Node3D.new()
	player.cam.add_child(hand)
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
	_hand = hand


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

const SMG_IDS := ["mp5", "p90", "uzi", "vector", "mk4"]


## 是否冲锋枪册枪型（_build_gun_visual 分发用）
static func _smg_has(id: String) -> bool:
	return SMG_IDS.has(id)


## 统一入口：只造「枪身根」（Node3D + 若干 MeshInstance3D 子节点）。
## 未知 id 返回空 Node3D（防御不崩）
static func _smg_build(id: String) -> Node3D:
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
					"size": Vector3(0.045, 0.20, 0.07), "show": true}
		"vector":
			## 匣入大后倾斜握把：同上对中+贴机匣底（竖直动画匣 vs 斜握把
			## 的小错位为低模已知取舍）
			return {"pos": Vector3(0.0, -0.105, 0.01),
					"size": Vector3(0.05, 0.18, 0.07), "show": true}
		"mk4":
			## 4.6×30 直弹匣（微弧）：真匣是枪身建模件（mag_straight 独立命名
			## 节点 + HDGunLib.curved_mag 三段 7° 微弧），动画匣隐（同 MP5/P90
			## 「匣形由枪身件表达」先例）；pos/size 保留 = 换弹手锚与掉匣
			## 替身缩放沿用原值（契约机制不变，只切 show）
			return {"pos": Vector3(0.0, -0.135, -0.075),
					"size": Vector3(0.042, 0.2, 0.068), "show": false}
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
	# ⑤ 机匣顶后段圆柱拉机柄钮（开筒：帽顶封、内衬探下藏进机匣）
	GUN_LIB.tube(root, steel, 0.022, 0.03, Vector3(0, 0.079, 0.04),
			Vector3.ZERO, 0.004, 0, null, 3, 32)
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
	GUN_LIB.barrel(root, steel, 0.185, 0.007, Vector3(0.023, 0.028, 0.215),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.barrel(root, steel, 0.185, 0.007, Vector3(-0.023, 0.028, 0.215),
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
	GUN_LIB.tube(root, polymer, 0.32, 0.056, Vector3(0, 0.022, -0.40),
			Vector3(90, 0, 0), 0.004, 4, dark, 4, 48)
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
	GUN_LIB.tube(root, dark, 0.17, 0.036, Vector3(0, 0.014, 0.155),
			Vector3(90, 0, 0), 0.005, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, dark, 0.016, 0.021, Vector3(0, 0.014, 0.085),
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
	#    (0,-0.135,-0.075) 的匣顶 -0.035——7° 三段微弧，弧向前）
	var mag := Node3D.new()
	mag.name = "mag_straight"
	mag.position = Vector3(0, -0.035, -0.075)
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


## ---------------- 内部：材质工厂与拼装闭包 ----------------


## 材质工厂：dark/steel 照 hd_guns.gd:475-509 参数原样抄（关深度测试防
## 贴墙吞枪 + render_priority 10 + 微自发光保暗处可读）；另扩冲锋枪册
## 专用色（深黑蓝 MP5 / 哑光聚合物 Vector / 匣灰对齐动画盒 / P90 浅灰白
## 与烟灰顶匣 / 发光观瞄窗）
static func _smg_mats() -> Dictionary:
	var mk := func(c: Color, e: Color, rough := 0.55, glow := 0.55) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.no_depth_test = true
		m.render_priority = 10
		m.emission_enabled = true
		m.emission = e
		m.emission_energy_multiplier = glow
		return m
	return {
		"dark": mk.call(Color(0.13, 0.14, 0.16), Color(0.16, 0.18, 0.2)),
		"blued": mk.call(Color(0.10, 0.11, 0.15), Color(0.12, 0.14, 0.19)),
		"steel": mk.call(Color(0.35, 0.38, 0.42), Color(0.4, 0.44, 0.5)),
		"polymer": mk.call(Color(0.15, 0.155, 0.17), Color(0.18, 0.19, 0.21), 0.85),
		"maggrey": mk.call(Color(0.16, 0.18, 0.22), Color(0.19, 0.21, 0.25)),
		"light": mk.call(Color(0.62, 0.62, 0.58), Color(0.5, 0.5, 0.46)),
		"smoke": mk.call(Color(0.52, 0.53, 0.50), Color(0.42, 0.43, 0.4)),
		"glass": mk.call(Color(0.15, 0.55, 0.75), Color(0.15, 0.55, 0.75), 0.3, 1.4),
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

const AR_IDS := ["m4a1", "akm", "scarh"]


## id 是否属于步枪册（_build_gun_visual 的分发判据）
static func _ar_has(id: String) -> bool:
	return AR_IDS.has(id)


## 统一入口：按 id 拼一把枪身根；未知 id 返回空 Node3D（防御不崩）。
## 高模重建后几何体在 hd_gun_ar.gd（AR_LIB.build，HDGunLib 工具件拼装）——
## 本签名逐字不动（_build_gun_visual / test_huodai 顶点红线断言都走此处），
## 材质仍由 _ar_mats 传参注入（新文件零材质创建）
static func _ar_build(id: String) -> Node3D:
	return AR_LIB.build(id, _ar_mats())


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
	return Vector3(0.085, -0.1, -0.42)   # 兜底 = M7 机瞄位


## ---------------- 内部：步枪册材质工厂（三枪高模几何在 hd_gun_ar.gd） ----------------


## 材质工厂：dark/wood/steel/fde/walnut 五种参数照抄 hd_guns.gd 的
## _build_gun_visual 材质段（一律 no_depth_test + render_priority 10 +
## 微自发光保暗处可读）；另加本文件新枪专用三种：polymer 纯黑聚合物（M4A1
## 全黑件）/ blued 深灰蓝钢（AKM 冲压机匣）/ bakelite 橙棕电木（AKM 握把）
static func _ar_mats() -> Dictionary:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.14, 0.16)
	dark.no_depth_test = true
	dark.render_priority = 10
	dark.emission_enabled = true
	dark.emission = Color(0.16, 0.18, 0.2)
	dark.emission_energy_multiplier = 0.55
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.18)
	wood.no_depth_test = true
	wood.render_priority = 10
	wood.emission_enabled = true
	wood.emission = Color(0.3, 0.2, 0.12)
	wood.emission_energy_multiplier = 0.55
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.35, 0.38, 0.42)
	steel.no_depth_test = true
	steel.render_priority = 10
	steel.emission_enabled = true
	steel.emission = Color(0.4, 0.44, 0.5)
	steel.emission_energy_multiplier = 0.55
	var fde := StandardMaterial3D.new()   # 沙 tan FDE（SCAR-H 机匣/托体，色近 M7）
	fde.albedo_color = Color(0.56, 0.46, 0.32)
	fde.no_depth_test = true
	fde.render_priority = 10
	fde.emission_enabled = true
	fde.emission = Color(0.42, 0.35, 0.24)
	fde.emission_energy_multiplier = 0.55
	var walnut := StandardMaterial3D.new()   # 胡桃木（AKM 木质三件套）
	walnut.albedo_color = Color(0.42, 0.26, 0.14)
	walnut.roughness = 0.85
	walnut.no_depth_test = true
	walnut.render_priority = 10
	walnut.emission_enabled = true
	walnut.emission = Color(0.3, 0.19, 0.1)
	walnut.emission_energy_multiplier = 0.55
	var polymer := StandardMaterial3D.new()   # 纯黑聚合物（M4A1 全黑主体）
	polymer.albedo_color = Color(0.07, 0.075, 0.085)
	polymer.roughness = 0.85
	polymer.no_depth_test = true
	polymer.render_priority = 10
	polymer.emission_enabled = true
	polymer.emission = Color(0.1, 0.105, 0.115)
	polymer.emission_energy_multiplier = 0.55
	var blued := StandardMaterial3D.new()   # 深灰蓝钢（AKM 冲压机匣/枪管）
	blued.albedo_color = Color(0.2, 0.21, 0.24)
	blued.no_depth_test = true
	blued.render_priority = 10
	blued.emission_enabled = true
	blued.emission = Color(0.24, 0.25, 0.28)
	blued.emission_energy_multiplier = 0.55
	var bakelite := StandardMaterial3D.new()   # 橙棕电木（AKM 下置握把）
	bakelite.albedo_color = Color(0.48, 0.26, 0.12)
	bakelite.roughness = 0.8
	bakelite.no_depth_test = true
	bakelite.render_priority = 10
	bakelite.emission_enabled = true
	bakelite.emission = Color(0.36, 0.2, 0.1)
	bakelite.emission_energy_multiplier = 0.55
	return {"dark": dark, "steel": steel, "wood": wood, "fde": fde,
			"walnut": walnut, "polymer": polymer, "blued": blued,
			"bakelite": bakelite}


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


## 统一入口：按 id 造旧五枪枪身根；未知 id 返回空 Node3D（防御不崩）
static func _old5_build(id: String) -> Node3D:
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
	var mk := func(c: Color, e: Color, rough := -1.0) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		if rough >= 0.0:
			m.roughness = rough
		m.no_depth_test = true
		m.render_priority = 10
		m.emission_enabled = true
		m.emission = e
		m.emission_energy_multiplier = 0.55
		return m
	return {
		"dark": mk.call(Color(0.13, 0.14, 0.16), Color(0.16, 0.18, 0.2)),
		"wood": mk.call(Color(0.45, 0.3, 0.18), Color(0.3, 0.2, 0.12)),
		"steel": mk.call(Color(0.35, 0.38, 0.42), Color(0.4, 0.44, 0.5)),
		"fde": mk.call(Color(0.56, 0.46, 0.32), Color(0.42, 0.35, 0.24)),
		"walnut": mk.call(Color(0.42, 0.26, 0.14), Color(0.3, 0.19, 0.1), 0.85),
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
	GUN_LIB.curved_mag(mag, steel, Vector3(0.04, 0.13, 0.068), 4.0, 3, 3)
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
	# 木质固定枪托（下斜 5°）+ 钢托底板
	GUN_LIB.chamfer_box(root, walnut, Vector3(0.052, 0.095, 0.21),
			Vector3(0, -0.095, 0.30), Vector3(-5, 0, 0), 0.003, 10)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.056, 0.1, 0.014),
			Vector3(0, -0.115, 0.405), Vector3.ZERO, 0.0015, 6)
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
	GUN_LIB.barrel(root, steel, 0.50, 0.056, Vector3(0, 0.06, -0.35),
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
	var steel: StandardMaterial3D = mats["steel"]
	var dark: StandardMaterial3D = mats["dark"]
	var wood: StandardMaterial3D = mats["wood"]
	# 钢机匣（s12，尾段延伸到托腕——旧模长钢身侧影保留）+ 木前托（坐管）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.055, 0.075, 0.46),
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
	GUN_LIB.chamfer_box(mag, steel, Vector3(0.052, 0.012, 0.095),
			Vector3(0, -0.049, -0.02), Vector3.ZERO, 0.001, 3)
	# 枪管（36 段重管 + 枪口螺纹环×2）
	GUN_LIB.barrel(root, dark, 0.48, 0.044, Vector3(0, 0.038, -0.72),
			Vector3(90, 0, 0), 2, 36)
	# 自带密位镜（镜体=枪身件，_finish_gun 的 sniper 分支不重复装镜）：
	# 主镜筒开筒 + 物镜罩（前环露亮钢口）+ 目镜筒 + 眼杯环 + 双镜环 + 双镜柱
	GUN_LIB.tube(root, dark, 0.20, 0.070, Vector3(0, 0.105, -0.30),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 32)
	GUN_LIB.tube(root, steel, 0.06, 0.090, Vector3(0, 0.105, -0.405),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, steel, 0.041, 0.048, Vector3(0, 0.105, -0.435),
			Vector3(90, 0, 0))
	GUN_LIB.tube(root, steel, 0.10, 0.056, Vector3(0, 0.105, -0.20),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, steel, 0.024, 0.030, Vector3(0, 0.105, -0.152),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, steel, 0.033, 0.041, Vector3(0, 0.105, -0.24),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, steel, 0.033, 0.041, Vector3(0, 0.105, -0.36),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, steel, Vector3(0.016, 0.03, 0.02),
			Vector3(0, 0.07, -0.24), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.016, 0.03, 0.02),
			Vector3(0, 0.07, -0.36), Vector3.ZERO, 0.0008, 3)
	# 枪机球柄（右后：柄杆贴机匣右面 + 球头）+ 抛壳口（右亮钢）
	GUN_LIB.chamfer_box(root, steel, Vector3(0.014, 0.014, 0.10),
			Vector3(0.034, 0.045, 0.04), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.02, 0.02, 0.02),
			Vector3(0.034, 0.045, 0.095), Vector3.ZERO, 0.001, 2)
	GUN_LIB.chamfer_box(root, steel, Vector3(0.004, 0.024, 0.07),
			Vector3(0.0285, 0.04, -0.02), Vector3.ZERO, 0.0008, 3)
	# 后托腕（指棱高模握把、后倾 15°）——grip() 顶锚=旋转支点，旧
	# _add_grip 中心锚=旋转支点，迁移用矢量式（含 z！）：
	# pos = 旧盒心 + Rx(−15°)·(0, 0.07, 0) = (0, -0.055+0.0676, 0.10-0.0181)
	# = (0, 0.0126, 0.0819)——8 角点与旧模偏差 ≤0.03mm（矩阵精算）
	GUN_LIB.grip(root, steel, 0.14, Vector3(0, 0.0126, 0.0819), 15.0,
			0.05, 0.09)
	# 枪托（木，微下斜 3°）+ 抬腮板 + 橡胶托底板
	GUN_LIB.chamfer_box(root, wood, Vector3(0.05, 0.10, 0.34),
			Vector3(0, -0.045, 0.30), Vector3(-3, 0, 0), 0.003, 10)
	GUN_LIB.chamfer_box(root, wood, Vector3(0.045, 0.05, 0.12),
			Vector3(0, 0.015, 0.40), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.054, 0.11, 0.014),
			Vector3(0, -0.036, 0.47), Vector3(-3, 0, 0), 0.0012, 6)
	return root
