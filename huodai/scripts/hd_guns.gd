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
## 2026-10 扩充七枪：vector 最柔（Super V 卖点）/ akm·scarh 大后坐（7.62 世界观）
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
}

var player           # HDPlayer（鸭子类型：读 cam/dead，写 recoil_pitch/recoil_yaw/ads/zoom）
var world            # 世界（鸭子类型：wall_hit / ground_height）
var audio            # HDAudio（play_shot/play_reload）
var tracers          # TracerPool 实例（main 创建传入，本模块 setup+tick）
var soldiers = null  # HDSoldiers 实例（main 注入）：raycast 用它的 battlefield 契约
var targets = null   # HDTargets 实例（main 注入）：命中时直接调 targets.on_hit(i) 倒靶计分
var scope_provider: Callable   # main 注入 func(gun_id)->Dictionary{"kind","zoom"}

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


## 进场：按 loadout 建两把枪模（常驻相机下，切枪只切可见性不重建）、
## 装 primary、满弹满备弹
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
				"reserve": int(HDData.RESERVE.get(gid, 0))}
		# 同槽换了枪才重建枪模；同枪复用已有 holder（重复进场不堆积）
		if _guns.has(slot) and str(_guns[slot]["id"]) != gid:
			var old: Dictionary = _guns[slot]
			(old["holder"] as Node3D).queue_free()
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


## R 键手动换弹（弹匣未满、有备弹、不在换弹中才生效）
func start_reload() -> void:
	if cur_id == "" or reloading > 0.0:
		return
	if ammo >= int(_g.get("mag", 12)) or reserve <= 0:
		return
	reloading = float(_g.get("reload", 1.5))
	if audio != null:
		audio.play_reload()


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
	# 枪上弹匣（换弹动画：脱落/滑入用）：旧五枪通用深灰盒常显；
	# 新枪按枪匠 mag_of 契约覆盖 位/尺寸/显隐（P90 顶匣隐动画匣、
	# UZI/Vector 匣入握把）——缺省键用 MAG_POS/通用盒/true 兜底
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


## 新枪弹匣参数（枪匠契约 mag_of）：返回 {"pos","size","show"} 子集；
## 旧五枪/未知 id 返回空字典——_mount_slot 用 MAG_POS/通用盒/true 兜底。
## 弹匣节点约定：动画弹匣永远是 holder 子节点（新枪不自带），
## 新枪「真弹匣形状」由 size/show 控制动画匣、由枪身建模件表达静置外形（P90 顶匣）
func _mag_override(gid: String) -> Dictionary:
	if _smg_has(gid):
		return _smg_mag_of(gid)
	if _ar_has(gid):
		return _ar_mag_of(gid)
	return {}


## 程序化低多边形枪模（全程序化拼装、外形互相可辨；rifle=M7 战斗步枪 /
## smg=汤姆逊 M1A1 按 2026-10 联网考证的真实外观特征重拼，见各分支注释；
## 2026-10 扩充七枪分发到下方枪匠静态段（_smg_*/_ar_*）——它们只造枪身根，
## 弹匣动画节点/火光/瞄具镜体仍由本文件统一挂，旧五枪装配链零改动）
func _build_gun_visual(gun_id: String) -> Node3D:
	if _smg_has(gun_id):
		return _finish_gun(_smg_build(gun_id), gun_id,
				_smg_scope_anchor(gun_id))
	if _ar_has(gun_id):
		return _finish_gun(_ar_build(gun_id), gun_id,
				_ar_scope_anchor(gun_id))
	var root := Node3D.new()
	# 视模型材质一律关深度测试（贴墙时枪模不被吞）；微自发光保暗处可读
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
	var fde := StandardMaterial3D.new()   # M7 沙色 FDE/coyote tan 涂装（XM7 辨识色）
	fde.albedo_color = Color(0.56, 0.46, 0.32)
	fde.no_depth_test = true
	fde.render_priority = 10
	fde.emission_enabled = true
	fde.emission = Color(0.42, 0.35, 0.24)
	fde.emission_energy_multiplier = 0.55
	var walnut := StandardMaterial3D.new()   # 汤姆逊胡桃木（棕木 albedo + 哑光粗糙）
	walnut.albedo_color = Color(0.42, 0.26, 0.14)
	walnut.roughness = 0.85
	walnut.no_depth_test = true
	walnut.render_priority = 10
	walnut.emission_enabled = true
	walnut.emission = Color(0.3, 0.19, 0.1)
	walnut.emission_energy_multiplier = 0.55
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
	var _cyl := func(rz: Vector3, pos: Vector3, rot_deg: Vector3,
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
	match gun_id:
		"pistol":
			# 半自动手枪：滑套 + 枪管口 + 击锤 + 双手握把
			add_box.call(Vector3(0.055, 0.075, 0.30), Vector3(0, 0.045, -0.06), Vector3.ZERO, steel)
			add_box.call(Vector3(0.03, 0.03, 0.05), Vector3(0, 0.055, -0.21), Vector3.ZERO, dark)
			add_box.call(Vector3(0.05, 0.11, 0.07), Vector3(0, -0.05, 0.05), Vector3(8, 0, 0), dark)
			add_box.call(Vector3(0.03, 0.03, 0.04), Vector3(0, 0.09, 0.07), Vector3(-14, 0, 0), steel)
			return _finish_gun(root, gun_id, Vector3(0.10, -0.04, -0.2))
		"smg":
			# 汤姆逊 M1A1（考证特征）：蓝钢机匣 + 木质固定枪托（握腕下斜+托底板）
			# + 木质横向护木 + 前竖握把 + .45 盒式弹匣 + 右侧拉机柄
			# + 平直枪口（M1A1 无 Cutts 补偿器/无消音器）+ 固定觇孔照门
			add_box.call(Vector3(0.06, 0.085, 0.36), Vector3(0, 0.025, -0.01), Vector3.ZERO, dark)
			add_box.call(Vector3(0.05, 0.05, 0.16), Vector3(0, -0.055, 0.03), Vector3.ZERO, dark)
			add_box.call(Vector3(0.052, 0.05, 0.09), Vector3(0, -0.04, -0.155), Vector3.ZERO, dark)
			_cyl.call(Vector3(0.017, 0.017, 0.26), Vector3(0, 0.03, -0.31), Vector3(90, 0, 0), steel)
			add_box.call(Vector3(0.024, 0.024, 0.03), Vector3(0, 0.03, -0.45), Vector3.ZERO, dark)
			add_box.call(Vector3(0.008, 0.03, 0.01), Vector3(0, 0.062, -0.42), Vector3.ZERO, steel)
			add_box.call(Vector3(0.028, 0.022, 0.02), Vector3(0, 0.078, 0.06), Vector3.ZERO, dark)
			add_box.call(Vector3(0.016, 0.018, 0.05), Vector3(0.038, 0.03, 0.05), Vector3.ZERO, steel)
			add_box.call(Vector3(0.012, 0.012, 0.025), Vector3(-0.036, -0.005, 0.07), Vector3.ZERO, steel)
			add_box.call(Vector3(0.058, 0.062, 0.24), Vector3(0, -0.005, -0.27), Vector3.ZERO, walnut)
			add_box.call(Vector3(0.034, 0.095, 0.048), Vector3(0, -0.09, -0.31), Vector3.ZERO, walnut)
			add_box.call(Vector3(0.012, 0.01, 0.065), Vector3(0, -0.083, 0.03), Vector3.ZERO, dark)
			add_box.call(Vector3(0.008, 0.028, 0.008), Vector3(0, -0.07, 0.045), Vector3.ZERO, steel)
			add_box.call(Vector3(0.046, 0.115, 0.11), Vector3(0, -0.095, 0.15), Vector3(18, 0, 0), walnut)
			add_box.call(Vector3(0.052, 0.095, 0.21), Vector3(0, -0.095, 0.30), Vector3(-5, 0, 0), walnut)
			add_box.call(Vector3(0.056, 0.1, 0.014), Vector3(0, -0.115, 0.405), Vector3.ZERO, dark)
			return _finish_gun(root, gun_id, Vector3(0.06, -0.04, -0.4))
		"rifle":
			# M7 战斗步枪（XM7 / SIG MCX Spear 体系，考证特征）：FDE 涂装大机匣
			# + 全长顶部皮轨（横向楔齿）+ M-LOK 开槽长护木 + 左侧折叠拉机柄
			# + 大尺寸消焰器筒（双挡环）+ Magpul SL-M 式伸缩枪托（贴腮板+调节柄）
			add_box.call(Vector3(0.062, 0.075, 0.3), Vector3(0, 0.035, -0.01), Vector3.ZERO, fde)
			add_box.call(Vector3(0.055, 0.055, 0.17), Vector3(0, -0.02, 0.015), Vector3.ZERO, fde)
			add_box.call(Vector3(0.05, 0.045, 0.09), Vector3(0, -0.045, -0.15), Vector3.ZERO, fde)
			add_box.call(Vector3(0.028, 0.016, 0.56), Vector3(0, 0.078, -0.13), Vector3.ZERO, dark)
			for i in 6:
				add_box.call(Vector3(0.031, 0.006, 0.014),
						Vector3(0, 0.089, 0.1 - float(i) * 0.08), Vector3.ZERO, steel)
			add_box.call(Vector3(0.056, 0.072, 0.3), Vector3(0, 0.02, -0.31), Vector3.ZERO, fde)
			for i in 4:
				add_box.call(Vector3(0.006, 0.022, 0.05),
						Vector3(-0.0295, 0.02, -0.2 - float(i) * 0.07), Vector3.ZERO, dark)
				add_box.call(Vector3(0.006, 0.022, 0.05),
						Vector3(0.0295, 0.02, -0.2 - float(i) * 0.07), Vector3.ZERO, dark)
			_cyl.call(Vector3(0.015, 0.015, 0.2), Vector3(0, 0.03, -0.56), Vector3(90, 0, 0), dark)
			_cyl.call(Vector3(0.024, 0.024, 0.09), Vector3(0, 0.03, -0.705), Vector3(90, 0, 0), dark)
			_cyl.call(Vector3(0.027, 0.027, 0.016), Vector3(0, 0.03, -0.68), Vector3(90, 0, 0), steel)
			_cyl.call(Vector3(0.027, 0.027, 0.016), Vector3(0, 0.03, -0.73), Vector3(90, 0, 0), steel)
			add_box.call(Vector3(0.022, 0.03, 0.035), Vector3(0, 0.055, -0.475), Vector3.ZERO, dark)
			add_box.call(Vector3(0.016, 0.02, 0.055), Vector3(-0.039, 0.045, 0.03), Vector3.ZERO, steel)
			add_box.call(Vector3(0.004, 0.02, 0.06), Vector3(0.032, 0.04, -0.03), Vector3.ZERO, dark)
			add_box.call(Vector3(0.038, 0.095, 0.052), Vector3(0, -0.075, 0.085), Vector3(22, 0, 0), dark)
			add_box.call(Vector3(0.012, 0.008, 0.06), Vector3(0, -0.052, 0.02), Vector3.ZERO, dark)
			add_box.call(Vector3(0.008, 0.024, 0.008), Vector3(0, -0.043, 0.03), Vector3.ZERO, steel)
			add_box.call(Vector3(0.048, 0.065, 0.05), Vector3(0, 0.015, 0.165), Vector3.ZERO, dark)
			add_box.call(Vector3(0.042, 0.055, 0.15), Vector3(0, 0.01, 0.26), Vector3.ZERO, fde)
			add_box.call(Vector3(0.03, 0.018, 0.1), Vector3(0, 0.048, 0.27), Vector3.ZERO, dark)
			add_box.call(Vector3(0.05, 0.09, 0.028), Vector3(0, 0.002, 0.345), Vector3.ZERO, dark)
			add_box.call(Vector3(0.028, 0.018, 0.04), Vector3(0, -0.03, 0.3), Vector3.ZERO, dark)
			return _finish_gun(root, gun_id, Vector3(0.085, -0.1, -0.42))
		"shotgun":
			# 泵动霰弹：木托 + 双管感 + 泵动前托 + 弹管
			add_box.call(Vector3(0.07, 0.09, 0.80), Vector3(0, 0.025, -0.16), Vector3.ZERO, wood)
			_cyl.call(Vector3(0.028, 0.028, 0.52), Vector3(0, 0.055, -0.36), Vector3(90, 0, 0), steel)
			_cyl.call(Vector3(0.022, 0.022, 0.42), Vector3(0, -0.005, -0.34), Vector3(90, 0, 0), dark)
			add_box.call(Vector3(0.06, 0.06, 0.14), Vector3(0, -0.02, -0.36), Vector3.ZERO, wood)
			add_box.call(Vector3(0.055, 0.15, 0.10), Vector3(0, -0.07, 0.14), Vector3(-8, 0, 0), wood)
			return _finish_gun(root, gun_id, Vector3(0.095, -0.16, -0.38))
		"sniper":
			# 栓动狙击：长枪管 + 大瞄准镜（物镜/目镜双径）+ 枪机拉柄 + 枪托
			add_box.call(Vector3(0.055, 0.085, 0.72), Vector3(0, 0.03, -0.14), Vector3.ZERO, steel)
			_cyl.call(Vector3(0.022, 0.022, 0.50), Vector3(0, 0.038, -0.72), Vector3(90, 0, 0), dark)
			# 瞄准镜：大物镜 + 目镜 + 镜身（自带密位镜外观）
			_cyl.call(Vector3(0.035, 0.035, 0.20), Vector3(0, 0.105, -0.30), Vector3(90, 0, 0), dark)
			_cyl.call(Vector3(0.045, 0.045, 0.05), Vector3(0, 0.105, -0.40), Vector3(90, 0, 0), steel)
			_cyl.call(Vector3(0.028, 0.028, 0.10), Vector3(0, 0.105, -0.20), Vector3(90, 0, 0), steel)
			add_box.call(Vector3(0.02, 0.045, 0.02), Vector3(0, 0.07, -0.24), Vector3.ZERO, steel)
			add_box.call(Vector3(0.02, 0.045, 0.02), Vector3(0, 0.07, -0.36), Vector3.ZERO, steel)
			add_box.call(Vector3(0.05, 0.14, 0.09), Vector3(0, -0.055, 0.10), Vector3(-4, 0, 0), steel)
			add_box.call(Vector3(0.016, 0.016, 0.10), Vector3(0.05, 0.045, 0.04), Vector3(0, 0, -24), steel)
			add_box.call(Vector3(0.05, 0.10, 0.34), Vector3(0, -0.045, 0.30), Vector3(-3, 0, 0), wood)
			add_box.call(Vector3(0.045, 0.05, 0.12), Vector3(0, 0.015, 0.40), Vector3.ZERO, wood)
			return _finish_gun(root, gun_id, Vector3(0.085, -0.1, -0.5))
	# 兜底（大战场 lmg 等未列枪）：空枪身 + 默认机瞄位（原行为等值）
	return _finish_gun(root, gun_id, Vector3(0.085, -0.1, -0.5))


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
const SMG_IDS := ["mp5", "p90", "uzi", "vector"]


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
	return Vector3(0.085, -0.1, -0.5)


## 黑克勒-科赫 MP5A2（9×19mm，约800rpm）——考证特征逐条：
## ① 纤细黑色机匣：全枪册最窄（宽 0.048）的管状长方机匣，贯通全枪
## ② 弯月形 30 发弹匣：mag_curved 三段斜接盒拼下弯弧线（弧向前，9mm
##    标志曲线、弧度小于 AKM）
## ③ A2 固定聚合物枪托：黑色实心托、侧影后段下斜三角（与汤姆逊木托
##    颜色+质感双区分）
## ④ 圆筒形 clamshell 护木：圆截面短筒+双肋环——本作唯一圆护木冲锋枪
##    （汤姆逊横方木 / Vector 方轨）
## ⑤ 鼓式转轮照门：机匣尾上方横置圆柱小鼓 + 环形准星座（双柱+顶梁）
## ⑥ 短圆柱枪口帽（三瓣式固定帽，枪管微出）
## ⑦ 机匣左侧 45° 斜置小拉机柄凸块
static func _smg_mp5() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var blued: StandardMaterial3D = mats["blued"]
	var steel: StandardMaterial3D = mats["steel"]
	var polymer: StandardMaterial3D = mats["polymer"]
	var rig := _smg_rig(root)
	var add_box: Callable = rig["box"]
	var add_cyl: Callable = rig["cyl"]
	# ① 机匣主管（宽 0.048 全册最窄）+ 机匣尾封（接托）
	add_box.call(Vector3(0.048, 0.078, 0.34), Vector3(0, 0.02, -0.04), Vector3.ZERO, blued)
	add_box.call(Vector3(0.046, 0.07, 0.05), Vector3(0, 0.015, 0.15), Vector3.ZERO, blued)
	# ④ 圆筒 clamshell 护木 + 双肋环（圆截面区别于方护木）
	add_cyl.call(Vector3(0.037, 0.037, 0.17), Vector3(0, 0.02, -0.295), Vector3(90, 0, 0), polymer)
	add_cyl.call(Vector3(0.039, 0.039, 0.018), Vector3(0, 0.02, -0.25), Vector3(90, 0, 0), polymer)
	add_cyl.call(Vector3(0.039, 0.039, 0.018), Vector3(0, 0.02, -0.335), Vector3(90, 0, 0), polymer)
	# ⑥ 枪管微出 + 短圆柱枪口帽（三瓣式固定帽）
	add_cyl.call(Vector3(0.011, 0.011, 0.05), Vector3(0, 0.02, -0.415), Vector3(90, 0, 0), steel)
	add_cyl.call(Vector3(0.016, 0.016, 0.04), Vector3(0, 0.02, -0.405), Vector3(90, 0, 0), blued)
	# ③ A2 固定聚合物托：上段平接机匣 → 下斜段（后端下垂的三角侧影）→ 托底板
	add_box.call(Vector3(0.044, 0.062, 0.09), Vector3(0, 0.028, 0.175), Vector3.ZERO, polymer)
	add_box.call(Vector3(0.042, 0.105, 0.12), Vector3(0, -0.012, 0.24), Vector3(12, 0, 0), polymer)
	add_box.call(Vector3(0.046, 0.11, 0.014), Vector3(0, -0.052, 0.295), Vector3.ZERO, polymer)
	# 握把（正角倾斜随旧枪家族惯例）+ 扳机护圈 + 扳机
	add_box.call(Vector3(0.036, 0.09, 0.052), Vector3(0, -0.062, -0.03), Vector3(15, 0, 0), polymer)
	add_box.call(Vector3(0.01, 0.008, 0.07), Vector3(0, -0.118, -0.055), Vector3.ZERO, blued)
	add_box.call(Vector3(0.008, 0.026, 0.008), Vector3(0, -0.098, -0.045), Vector3.ZERO, steel)
	# ② 弹匣井（机匣底前缘）+ 弯月匣三段（独立命名节点 mag_curved：
	# 竖直段 → 14° → 28° 斜接，弧线向前弯）
	var mag_c := Node3D.new()
	mag_c.name = "mag_curved"
	root.add_child(mag_c)
	add_box.call(Vector3(0.04, 0.04, 0.11), Vector3(0, -0.04, -0.155), Vector3.ZERO, blued)
	_smg_box_at(mag_c, Vector3(0.05, 0.095, 0.108), Vector3(0, -0.105, -0.155), Vector3.ZERO, blued)
	_smg_box_at(mag_c, Vector3(0.05, 0.095, 0.108), Vector3(0, -0.19, -0.175), Vector3(14, 0, 0), blued)
	_smg_box_at(mag_c, Vector3(0.05, 0.09, 0.108), Vector3(0, -0.265, -0.215), Vector3(28, 0, 0), blued)
	# ⑤ 鼓式转轮照门：底座 + 横置圆柱小鼓（机匣尾上方）
	add_box.call(Vector3(0.026, 0.018, 0.045), Vector3(0, 0.068, 0.075), Vector3.ZERO, blued)
	add_cyl.call(Vector3(0.017, 0.017, 0.024), Vector3(0, 0.078, 0.075), Vector3(0, 0, 90), blued)
	# ⑤ 环形准星座（护木前端：双柱 + 顶梁 + 准星柱）
	add_box.call(Vector3(0.007, 0.028, 0.01), Vector3(0.015, 0.07, -0.36), Vector3.ZERO, blued)
	add_box.call(Vector3(0.007, 0.028, 0.01), Vector3(-0.015, 0.07, -0.36), Vector3.ZERO, blued)
	add_box.call(Vector3(0.037, 0.007, 0.01), Vector3(0, 0.086, -0.36), Vector3.ZERO, blued)
	add_box.call(Vector3(0.005, 0.018, 0.005), Vector3(0, 0.072, -0.36), Vector3.ZERO, steel)
	# ⑦ 机匣左侧 45° 斜置拉机柄（凸块 + 柄杆，x 负 = 左侧）
	add_box.call(Vector3(0.016, 0.014, 0.02), Vector3(-0.03, 0.048, -0.03), Vector3(0, 0, 45), steel)
	add_box.call(Vector3(0.012, 0.009, 0.035), Vector3(-0.036, 0.042, -0.075), Vector3(0, 0, 45), steel)
	return root


## FN P90（5.7×28mm PDW）——考证特征逐条：
## ① 无托布局：全长最短（枪身 0.48），机匣与弹匣后置、无枪托、尾部圆滑收
## ② 顶置 50 发长弹匣：mag_top 沿枪管上方全长的扁匣、浅灰塑料色、
##    与枪身等宽（独一份的顶匣侧影）
## ③ 原厂一体白光镜：弹匣后上方的弧形方镜体 + 发光观瞄窗——仅外观件，
##    开镜倍率仍只认装配瞄具（工程纪律）
## ④ 双握把孔：枪管下中段的开孔前握把（竖圆柱+孔环）+ 后手枪握把
## ⑤ 流线聚合物外壳：三段收张圆角大盒身、无外露弹匣井/无外露拉机柄
## ⑥ 枪口短筒形消焰器，枪管几乎全长包在壳内（低轴线）
## ⑦ 浅灰白主色 + 黑色握把孔的强对比配色（全枪册唯一浅色枪）
static func _smg_p90() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var light: StandardMaterial3D = mats["light"]
	var dark: StandardMaterial3D = mats["dark"]
	var smoke: StandardMaterial3D = mats["smoke"]
	var steel: StandardMaterial3D = mats["steel"]
	var glass: StandardMaterial3D = mats["glass"]
	var rig := _smg_rig(root)
	var add_box: Callable = rig["box"]
	var add_cyl: Callable = rig["cyl"]
	# ⑤ 外壳三段：前收段 → 主体段 → 尾段；尾块斜转圆滑收（无托尾部）
	add_box.call(Vector3(0.062, 0.085, 0.11), Vector3(0, 0.0, -0.185), Vector3.ZERO, light)
	add_box.call(Vector3(0.07, 0.115, 0.17), Vector3(0, 0.012, -0.045), Vector3.ZERO, light)
	add_box.call(Vector3(0.066, 0.1, 0.14), Vector3(0, 0.018, 0.11), Vector3.ZERO, light)
	add_box.call(Vector3(0.055, 0.08, 0.06), Vector3(0, 0.012, 0.195), Vector3(10, 0, 0), light)
	# ② 顶置 50 发长弹匣（独立命名节点 mag_top：浅灰扁匣沿顶全长、与壳等宽）
	# + 与壳体的深色接缝线 + 两侧纵槽
	var mag_t := Node3D.new()
	mag_t.name = "mag_top"
	root.add_child(mag_t)
	_smg_box_at(mag_t, Vector3(0.068, 0.042, 0.40), Vector3(0, 0.078, -0.06), Vector3.ZERO, smoke)
	add_box.call(Vector3(0.07, 0.006, 0.40), Vector3(0, 0.058, -0.06), Vector3.ZERO, dark)
	_smg_box_at(mag_t, Vector3(0.004, 0.026, 0.36), Vector3(0.035, 0.078, -0.06), Vector3.ZERO, dark)
	_smg_box_at(mag_t, Vector3(0.004, 0.026, 0.36), Vector3(-0.035, 0.078, -0.06), Vector3.ZERO, dark)
	# ③ 原厂一体白光镜：方镜体 + 发光观瞄窗 + 弧形顶盖（骑在匣尾上方）
	add_box.call(Vector3(0.052, 0.034, 0.11), Vector3(0, 0.116, 0.10), Vector3.ZERO, dark)
	add_box.call(Vector3(0.04, 0.026, 0.012), Vector3(0, 0.117, 0.043), Vector3.ZERO, glass)
	add_box.call(Vector3(0.046, 0.012, 0.12), Vector3(0, 0.138, 0.10), Vector3(-6, 0, 0), dark)
	# ④ 前握把孔：开孔竖圆柱 + 孔环（枪管下中段、黑色）
	add_cyl.call(Vector3(0.021, 0.021, 0.075), Vector3(0, -0.05, -0.155), Vector3.ZERO, dark)
	add_box.call(Vector3(0.056, 0.016, 0.062), Vector3(0, -0.052, -0.155), Vector3.ZERO, dark)
	# ④ 后手枪握把 + 孔环（竖直，P90 握把近垂直）
	add_box.call(Vector3(0.05, 0.08, 0.05), Vector3(0, -0.088, 0.055), Vector3.ZERO, dark)
	add_box.call(Vector3(0.058, 0.018, 0.06), Vector3(0, -0.055, 0.055), Vector3.ZERO, dark)
	# 扳机 + 护圈（双握把孔之间）
	add_box.call(Vector3(0.008, 0.024, 0.008), Vector3(0, -0.075, -0.03), Vector3.ZERO, steel)
	add_box.call(Vector3(0.01, 0.008, 0.05), Vector3(0, -0.095, -0.025), Vector3.ZERO, dark)
	# ⑥ 枪管（低轴线、几乎全长包壳内）+ 枪口短筒消焰器
	add_cyl.call(Vector3(0.01, 0.01, 0.06), Vector3(0, -0.02, -0.21), Vector3(90, 0, 0), steel)
	add_cyl.call(Vector3(0.014, 0.014, 0.05), Vector3(0, -0.02, -0.245), Vector3(90, 0, 0), dark)
	return root


## IMI 乌兹（9×19mm）——考证特征逐条：
## ① 方盒机匣：矩形上下等宽单盒、全枪册最「方」的轮廓（无阶梯无护木）
## ② 弹匣插在手枪握把内：长直匣从握把底垂直下垂（动画匣对中握把中轴，
##    握把与匣同色表达「匣在握把内」）
## ③ 金属折叠托：两根细钢杆 + 端部小板托展开于机匣后
## ④ 极短紧凑：机匣前端直接出短枪管、无护木、无木件、全黑
## ⑤ 机匣上方后段的圆柱拉机柄钮（顶部圆钮凸起）
## ⑥ 握把前缘弧形握把保险凸块（斜置弧块）
## ⑦ 前准星柱带护圈双耳 + 机匣尾片状照门
static func _smg_uzi() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var dark: StandardMaterial3D = mats["dark"]
	var maggrey: StandardMaterial3D = mats["maggrey"]
	var steel: StandardMaterial3D = mats["steel"]
	var rig := _smg_rig(root)
	var add_box: Callable = rig["box"]
	var add_cyl: Callable = rig["cyl"]
	# ① 方盒机匣（上下等宽）+ 前管螺帽 + ④ 短枪管（机匣前端直接出）
	add_box.call(Vector3(0.058, 0.096, 0.26), Vector3(0, 0.02, -0.02), Vector3.ZERO, dark)
	add_cyl.call(Vector3(0.02, 0.02, 0.03), Vector3(0, 0.025, -0.155), Vector3(90, 0, 0), steel)
	add_cyl.call(Vector3(0.012, 0.012, 0.08), Vector3(0, 0.025, -0.20), Vector3(90, 0, 0), dark)
	# ⑤ 机匣顶后段圆柱拉机柄钮（顶部圆钮凸起）
	add_cyl.call(Vector3(0.015, 0.015, 0.022), Vector3(0, 0.079, 0.04), Vector3.ZERO, steel)
	# ⑦ 前准星座 + 护圈双耳 + 准星柱（机匣前上）
	add_box.call(Vector3(0.026, 0.02, 0.018), Vector3(0, 0.078, -0.135), Vector3.ZERO, dark)
	add_box.call(Vector3(0.007, 0.03, 0.009), Vector3(0.014, 0.093, -0.135), Vector3.ZERO, dark)
	add_box.call(Vector3(0.007, 0.03, 0.009), Vector3(-0.014, 0.093, -0.135), Vector3.ZERO, dark)
	add_box.call(Vector3(0.005, 0.022, 0.005), Vector3(0, 0.095, -0.135), Vector3.ZERO, steel)
	# ⑦ 机匣尾片状照门
	add_box.call(Vector3(0.03, 0.012, 0.01), Vector3(0, 0.074, 0.095), Vector3.ZERO, dark)
	# ② 握把（中轴对齐动画匣 z=0.081、与匣同色 maggrey——匣嵌握把段无色差）
	add_box.call(Vector3(0.044, 0.105, 0.052), Vector3(0, -0.075, 0.081), Vector3(8, 0, 0), maggrey)
	# ⑥ 握把前缘弧形握把保险凸块（斜置弧块）
	add_box.call(Vector3(0.038, 0.045, 0.022), Vector3(0, -0.052, 0.03), Vector3(18, 0, 0), dark)
	# 扳机 + 护圈（握把前方、弹匣前缘）
	add_box.call(Vector3(0.008, 0.024, 0.008), Vector3(0, -0.065, -0.012), Vector3.ZERO, steel)
	add_box.call(Vector3(0.01, 0.008, 0.06), Vector3(0, -0.092, -0.005), Vector3.ZERO, dark)
	# ③ 金属折叠托：铰链块 + 两根细钢杆 + 端部小板托（展开于机匣后）
	add_box.call(Vector3(0.05, 0.045, 0.02), Vector3(0, 0.03, 0.12), Vector3.ZERO, dark)
	add_box.call(Vector3(0.007, 0.007, 0.185), Vector3(0.023, 0.028, 0.215), Vector3.ZERO, steel)
	add_box.call(Vector3(0.007, 0.007, 0.185), Vector3(-0.023, 0.028, 0.215), Vector3.ZERO, steel)
	add_box.call(Vector3(0.054, 0.072, 0.012), Vector3(0, 0.018, 0.31), Vector3.ZERO, dark)
	return root


## KRISS Vector 冲锋枪（.45 ACP，约1200rpm）——考证特征逐条：
## ① 折线形机匣侧影：前低后高两段折线（低护木段 → 斜面过渡块 → 高机匣段，
##    Super V 系统外观签名、枪册独一份）
## ② 大后倾角手枪握把居中：弹匣斜插入握把（动画匣对中握把、握把与匣同色）
## ③ 全长顶部皮卡汀尼轨：连续楔齿从机匣尾铺到护木（基条 + 8 齿）
## ④ 机匣尾部上凸块（后坐质量块外形）高出顶轨 + 前斜肩
## ⑤ 侧折黑色方盒聚合物托 + 折叠铰链凸块 + 托底板
## ⑥ 短圆护木 + 低枪管线（枪口轴线贴握持线）+ 短消焰器
## ⑦ 纯黑聚合物配色（与 P90 浅色、MP5 深黑蓝各拉开一档）
static func _smg_vector() -> Node3D:
	var root := Node3D.new()
	var mats := _smg_mats()
	var polymer: StandardMaterial3D = mats["polymer"]
	var dark: StandardMaterial3D = mats["dark"]
	var maggrey: StandardMaterial3D = mats["maggrey"]
	var steel: StandardMaterial3D = mats["steel"]
	var rig := _smg_rig(root)
	var add_box: Callable = rig["box"]
	var add_cyl: Callable = rig["cyl"]
	# ① 折线三段：低护木段 → 斜面过渡块（前低后高）→ 中段 → 高机匣段
	add_box.call(Vector3(0.056, 0.058, 0.16), Vector3(0, 0.002, -0.20), Vector3.ZERO, polymer)
	add_box.call(Vector3(0.056, 0.05, 0.05), Vector3(0, 0.005, -0.115), Vector3(-18, 0, 0), polymer)
	add_box.call(Vector3(0.06, 0.072, 0.13), Vector3(0, 0.014, -0.045), Vector3.ZERO, polymer)
	add_box.call(Vector3(0.062, 0.082, 0.15), Vector3(0, 0.024, 0.10), Vector3.ZERO, polymer)
	# ③ 全长顶轨基条 + 连续楔齿×8（从护木前端铺到机匣尾）
	add_box.call(Vector3(0.03, 0.015, 0.44), Vector3(0, 0.0745, -0.09), Vector3.ZERO, dark)
	for i in 8:
		add_box.call(Vector3(0.032, 0.006, 0.02),
				Vector3(0, 0.0855, -0.29 + float(i) * 0.057), Vector3.ZERO, dark)
	# ④ 尾部上凸质量块（顶 0.118 高出轨顶 0.082）+ 前斜肩
	add_box.call(Vector3(0.05, 0.05, 0.1), Vector3(0, 0.093, 0.095), Vector3.ZERO, polymer)
	add_box.call(Vector3(0.048, 0.04, 0.05), Vector3(0, 0.085, 0.03), Vector3(-20, 0, 0), polymer)
	# ⑤ 侧折方盒聚合物托 + 折叠铰链凸块 + 托底板
	add_box.call(Vector3(0.048, 0.068, 0.125), Vector3(0, 0.018, 0.235), Vector3.ZERO, polymer)
	add_box.call(Vector3(0.054, 0.028, 0.03), Vector3(0, 0.03, 0.175), Vector3.ZERO, dark)
	add_box.call(Vector3(0.05, 0.075, 0.012), Vector3(0, 0.012, 0.30), Vector3.ZERO, dark)
	# ② 大后倾握把（26° 居中对中动画匣、与匣同色）+ 扳机 + 护圈
	add_box.call(Vector3(0.048, 0.115, 0.058), Vector3(0, -0.072, 0.026), Vector3(26, 0, 0), maggrey)
	add_box.call(Vector3(0.008, 0.024, 0.008), Vector3(0, -0.06, -0.055), Vector3.ZERO, steel)
	add_box.call(Vector3(0.01, 0.008, 0.055), Vector3(0, -0.085, -0.05), Vector3.ZERO, dark)
	# ⑥ 低枪管线：枪管贴护木下缘 + 短消焰器（枪口轴线贴握持线）
	add_cyl.call(Vector3(0.011, 0.011, 0.09), Vector3(0, -0.002, -0.335), Vector3(90, 0, 0), dark)
	add_cyl.call(Vector3(0.015, 0.015, 0.045), Vector3(0, -0.002, -0.40), Vector3(90, 0, 0), dark)
	# 轨首准星（座+柱）+ 质量块前照门
	add_box.call(Vector3(0.018, 0.022, 0.016), Vector3(0, 0.096, -0.30), Vector3.ZERO, dark)
	add_box.call(Vector3(0.005, 0.018, 0.005), Vector3(0, 0.104, -0.30), Vector3.ZERO, steel)
	add_box.call(Vector3(0.028, 0.014, 0.018), Vector3(0, 0.096, 0.0), Vector3.ZERO, dark)
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

const AR_IDS := ["m4a1", "akm", "scarh"]


## id 是否属于步枪册（_build_gun_visual 的分发判据）
static func _ar_has(id: String) -> bool:
	return AR_IDS.has(id)


## 统一入口：按 id 拼一把枪身根；未知 id 返回空 Node3D（防御不崩）
static func _ar_build(id: String) -> Node3D:
	var root := Node3D.new()
	var mats := _ar_mats()
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
	match id:
		"m4a1":
			_ar_m4a1(add_box, add_cyl, mats)
		"akm":
			_ar_akm(add_box, add_cyl, mats)
		"scarh":
			_ar_scarh(add_box, add_cyl, mats)
		_:
			pass   # 未知 id：不落任何部件，返回空枪身根
	return root


## 弹匣动画节点覆盖（hd_guns 枪架局部坐标 = 枪身局部 × GUN_SCALE≈0.62 换算）：
## 返回 {"pos": Vector3, "size": Vector3, "show": bool}，缺省键由 hd_guns 用
## MAG_POS / 通用盒 0.055×0.17×0.09 / true 兜底。枪身上的弹匣井已按各 id 的
## 合同弹匣落点（÷0.62 反推）建模，动画匣顶恰好插进井口。
static func _ar_mag_of(id: String) -> Dictionary:
	match id:
		"akm":
			# 特征② 大弧度弯月 30 发匣（「山羊角」）：高匣身 + 前倾位
			# （弧度在低模上以加高匣身近似，掉落匣替身同尺寸）
			return {"pos": Vector3(0.02, -0.13, -0.15),
					"size": Vector3(0.05, 0.19, 0.08), "show": true}
		"scarh":
			# 特征⑤ 宽直体 20 发 7.62 匣：比 STANAG 更宽厚、近直
			return {"pos": Vector3(0.02, -0.13, -0.16),
					"size": Vector3(0.058, 0.20, 0.095), "show": true}
		_:
			# 特征⑦（M4A1）微弯梯形 STANAG 30 发直匣（弧度远小于 AKM）：
			# 走 hd_guns 缺省（MAG_POS + 通用盒 + show），空字典交兜底
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


## ---------------- 内部：材质工厂与三枪拼装 ----------------


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


## M4A1 突击步枪（柯尔特 M4A1 卡宾，5.56×45mm，平顶机匣）考证特征逐条落件：
## ①全黑配色：黑机匣/黑护木/黑托（polymer 主体 + 近黑金属细节，与 M7 的 FDE
##   沙色形成枪册最大色差）
## ②平顶机匣 + 可拆卸拱形提把（带后照门）：最强辨识件，装在顶轨上
## ③6 段伸缩聚合物托：圆柱缓冲管 + 侧面斜切梯形托体
## ④三角形准星座：枪管前上方三角收顶块 + 准星柱/双护耳（M16 系血脉）
## ⑤圆形截面护木、双环散热感（对照 M7 的 M-LOK 方护木）
## ⑥A2 鸟笼消焰器：圆柱带纵槽口（短，非 M7 的长消音筒）
## ⑦微弯梯形 STANAG 30 发直匣（弧度远小于 AKM）——弹匣节点走 hd_guns 缺省
## ⑧顶部皮轨楔齿（提把座前后可见）+ 尾部 T 形拉机柄
static func _ar_m4a1(add_box: Callable, add_cyl: Callable,
		mats: Dictionary) -> void:
	var blk: StandardMaterial3D = mats["polymer"]   # ① 纯黑聚合物主体
	var met: StandardMaterial3D = mats["dark"]      # ① 近黑金属细节
	var stl: StandardMaterial3D = mats["steel"]     # ① 亮钢小件提层次
	# ① 平顶机匣上体 + 下机匣（上体顶面就是②的平顶轨座）
	add_box.call(Vector3(0.055, 0.065, 0.28), Vector3(0, 0.03, -0.01), Vector3.ZERO, blk)
	add_box.call(Vector3(0.05, 0.05, 0.18), Vector3(0, -0.02, 0.01), Vector3.ZERO, blk)
	# ② 拱形提把：拱梁 + 前后支腿 + 提把顶后照门座 + 侧风偏钮（顶 0.090 ≈ my）
	add_box.call(Vector3(0.05, 0.012, 0.115), Vector3(0, 0.084, 0.045), Vector3.ZERO, met)
	add_box.call(Vector3(0.046, 0.03, 0.014), Vector3(0, 0.066, -0.005), Vector3.ZERO, met)
	add_box.call(Vector3(0.046, 0.028, 0.014), Vector3(0, 0.066, 0.095), Vector3.ZERO, met)
	add_box.call(Vector3(0.016, 0.014, 0.012), Vector3(0, 0.096, 0.07), Vector3.ZERO, met)
	add_box.call(Vector3(0.01, 0.012, 0.012), Vector3(0.031, 0.084, 0.07), Vector3.ZERO, met)
	# ⑧ 平顶皮轨：轨基 + 连续楔齿（提把座前后齿段均可见）
	add_box.call(Vector3(0.028, 0.014, 0.27), Vector3(0, 0.067, -0.01), Vector3.ZERO, met)
	for i in 5:
		add_box.call(Vector3(0.031, 0.006, 0.016),
				Vector3(0, 0.077, -0.125 + 0.06 * float(i)), Vector3.ZERO, met)
	# ⑧ 尾部 T 形拉机柄凸块（区别于 AKM 右侧大柄 / MP5 左置小柄）
	add_box.call(Vector3(0.034, 0.009, 0.02), Vector3(0, 0.064, 0.128), Vector3.ZERO, met)
	# ③ 伸缩托：圆柱缓冲管 + 托体 + 侧面斜切楔（梯形侧影）+ 托底板 + 释放钮
	add_cyl.call(Vector3(0.019, 0.019, 0.17), Vector3(0, 0.012, 0.215), Vector3(90, 0, 0), blk)
	add_box.call(Vector3(0.046, 0.08, 0.13), Vector3(0, -0.008, 0.28), Vector3.ZERO, blk)
	add_box.call(Vector3(0.04, 0.05, 0.12), Vector3(0, -0.043, 0.285), Vector3(12, 0, 0), blk)
	add_box.call(Vector3(0.05, 0.096, 0.02), Vector3(0, -0.022, 0.345), Vector3.ZERO, met)
	add_box.call(Vector3(0.012, 0.018, 0.028), Vector3(0.029, -0.02, 0.3), Vector3.ZERO, met)
	# ⑤ 圆护木：主圆筒（圆截面）+ 三道散热环 + 尾部 delta 环（双环散热感）
	add_cyl.call(Vector3(0.027, 0.027, 0.28), Vector3(0, 0.02, -0.3), Vector3(90, 0, 0), blk)
	for i in 3:
		add_cyl.call(Vector3(0.0295, 0.0295, 0.018),
				Vector3(0, 0.02, -0.21 - 0.09 * float(i)), Vector3(90, 0, 0), met)
	add_cyl.call(Vector3(0.031, 0.031, 0.024), Vector3(0, 0.02, -0.155), Vector3(90, 0, 0), met)
	# ④ 三角形准星座：宽基座 + 收顶窄段（三角收顶）+ 双护耳，骑在枪管前上方
	add_box.call(Vector3(0.032, 0.028, 0.03), Vector3(0, 0.052, -0.455), Vector3.ZERO, met)
	add_box.call(Vector3(0.02, 0.022, 0.024), Vector3(0, 0.077, -0.455), Vector3.ZERO, met)
	add_box.call(Vector3(0.006, 0.02, 0.022), Vector3(-0.014, 0.072, -0.455), Vector3.ZERO, met)
	add_box.call(Vector3(0.006, 0.02, 0.022), Vector3(0.014, 0.072, -0.455), Vector3.ZERO, met)
	# ⑥ 枪管 + A2 鸟笼消焰器：短筒 + 两侧纵槽口提示 + 前环（短于 M7 消音筒）
	add_cyl.call(Vector3(0.012, 0.012, 0.19), Vector3(0, 0.03, -0.535), Vector3(90, 0, 0), met)
	add_cyl.call(Vector3(0.0145, 0.0145, 0.058), Vector3(0, 0.03, -0.655), Vector3(90, 0, 0), met)
	add_box.call(Vector3(0.005, 0.004, 0.034), Vector3(-0.0125, 0.03, -0.655), Vector3.ZERO, stl)
	add_box.call(Vector3(0.005, 0.004, 0.034), Vector3(0.0125, 0.03, -0.655), Vector3.ZERO, stl)
	add_cyl.call(Vector3(0.016, 0.016, 0.008), Vector3(0, 0.03, -0.68), Vector3(90, 0, 0), stl)
	# ⑦ 弹匣井（挂 hd_guns 缺省 STANAG 直匣：井口 y 顶 -0.092 对缺省匣顶 -0.089）
	add_box.call(Vector3(0.052, 0.092, 0.09), Vector3(0, -0.046, -0.16), Vector3.ZERO, blk)
	# 握把 / 护圈 / 扳机 / 前助推器（右后侧圆钮）/ 抛壳口防挡板
	add_box.call(Vector3(0.036, 0.088, 0.05), Vector3(0, -0.072, 0.085), Vector3(20, 0, 0), blk)
	add_box.call(Vector3(0.012, 0.008, 0.06), Vector3(0, -0.052, 0.03), Vector3.ZERO, met)
	add_box.call(Vector3(0.008, 0.024, 0.008), Vector3(0, -0.043, 0.035), Vector3.ZERO, stl)
	add_cyl.call(Vector3(0.011, 0.011, 0.022), Vector3(0.031, 0.038, 0.06), Vector3(0, 0, 90), met)
	add_box.call(Vector3(0.008, 0.022, 0.02), Vector3(0.029, 0.028, 0.015), Vector3.ZERO, met)


## AKM 突击步枪（7.62×39mm，冲压机匣）考证特征逐条落件：
## ①木质三件套：斜切贴腮枪托 + 上护木（包住导气管的通条状木段）+ 下护木，
##   胡桃木色（walnut 材质）
## ②大弧度弯月 30 发弹匣（7.62 弧度比 MP5 更大更前倾，「山羊角」）——mag_of 覆盖
## ③斜切枪口制退器：前端斜面切口（AKM 独有标志，AK-47 没有）
## ④冲压机匣 + 前凸弹匣井小盒，侧面铆钉点缀
## ⑤右侧大型长杆拉机柄凸出（区别于 MP5 左置小柄 / M4 尾部 T 柄）
## ⑥气块上的准星座带两翼护圈（骑在枪管上方）
## ⑦深灰钢机匣 + 木色件双色分明（与汤姆逊同为「木+钢」但布局不同：上护木是
##   枪管上方通条状木段，下护木独立于机匣前）
## ⑧小而直的下置握把（bakelite 橙棕色调）
static func _ar_akm(add_box: Callable, add_cyl: Callable,
		mats: Dictionary) -> void:
	var rcv: StandardMaterial3D = mats["blued"]    # ⑦ 深灰冲压钢机匣
	var wln: StandardMaterial3D = mats["walnut"]   # ① 胡桃木三件套
	var met: StandardMaterial3D = mats["dark"]     # 深色金属件
	var stl: StandardMaterial3D = mats["steel"]    # 亮钢小件（机匣盖/铆钉/拉机柄）
	var bkl: StandardMaterial3D = mats["bakelite"] # ⑧ 橙棕电木握把
	# ④ 冲压机匣 + 稍亮机匣盖（分层）+ 前凸弹匣井小盒 + 侧面铆钉（左右各 3 颗）
	add_box.call(Vector3(0.05, 0.075, 0.34), Vector3(0, 0.02, 0.0), Vector3.ZERO, rcv)
	add_box.call(Vector3(0.044, 0.022, 0.30), Vector3(0, 0.064, 0.0), Vector3.ZERO, stl)
	add_box.call(Vector3(0.052, 0.08, 0.07), Vector3(0, -0.055, -0.18), Vector3.ZERO, rcv)
	for i in 3:
		add_box.call(Vector3(0.004, 0.006, 0.006),
				Vector3(-0.026, 0.032, -0.13 + 0.1 * float(i)), Vector3.ZERO, stl)
		add_box.call(Vector3(0.004, 0.006, 0.006),
				Vector3(0.026, 0.032, -0.13 + 0.1 * float(i)), Vector3.ZERO, stl)
	# ① 下护木（带左右掌肚）+ 上护木（枪管上方通条状木段，包住导气管）
	add_box.call(Vector3(0.052, 0.052, 0.20), Vector3(0, -0.005, -0.27), Vector3.ZERO, wln)
	add_box.call(Vector3(0.006, 0.028, 0.09), Vector3(-0.0285, -0.014, -0.29), Vector3.ZERO, wln)
	add_box.call(Vector3(0.006, 0.028, 0.09), Vector3(0.0285, -0.014, -0.29), Vector3.ZERO, wln)
	add_box.call(Vector3(0.038, 0.032, 0.17), Vector3(0, 0.058, -0.28), Vector3.ZERO, wln)
	# ① 斜切贴腮枪托：托体（下斜贴腮线）+ 斜切钢托底板
	add_box.call(Vector3(0.042, 0.085, 0.25), Vector3(0, -0.045, 0.285), Vector3(-6, 0, 0), wln)
	add_box.call(Vector3(0.048, 0.105, 0.016), Vector3(0, -0.062, 0.395), Vector3(12, 0, 0), met)
	# ⑦ 表尺座 + 表尺板（机匣前上方的曲射照门，与木件分色）
	add_box.call(Vector3(0.034, 0.02, 0.03), Vector3(0, 0.055, -0.19), Vector3.ZERO, rcv)
	add_box.call(Vector3(0.03, 0.012, 0.055), Vector3(0, 0.069, -0.205), Vector3.ZERO, stl)
	# ⑥ 导气系统：枪管 + 气块 + 导气管外露段 + 准星柱 + 两翼护圈（骑在枪管上方）
	add_cyl.call(Vector3(0.011, 0.011, 0.17), Vector3(0, 0.03, -0.53), Vector3(90, 0, 0), rcv)
	add_box.call(Vector3(0.03, 0.036, 0.03), Vector3(0, 0.048, -0.44), Vector3.ZERO, rcv)
	add_cyl.call(Vector3(0.008, 0.008, 0.06), Vector3(0, 0.058, -0.395), Vector3(90, 0, 0), stl)
	add_box.call(Vector3(0.01, 0.022, 0.01), Vector3(0, 0.072, -0.44), Vector3.ZERO, stl)
	add_box.call(Vector3(0.005, 0.022, 0.022), Vector3(-0.014, 0.072, -0.44), Vector3.ZERO, stl)
	add_box.call(Vector3(0.005, 0.022, 0.022), Vector3(0.014, 0.072, -0.44), Vector3.ZERO, stl)
	# ③ 斜切枪口制退器：短筒 + 前端斜面楔块（斜切口朝前上，AKM 独有）
	add_cyl.call(Vector3(0.014, 0.014, 0.045), Vector3(0, 0.03, -0.62), Vector3(90, 0, 0), rcv)
	add_box.call(Vector3(0.024, 0.028, 0.02), Vector3(0, 0.036, -0.653), Vector3(20, 0, 0), rcv)
	# ⑤ 右侧大型长杆拉机柄（凸出机匣右侧面，z 在表尺座后方）
	add_box.call(Vector3(0.03, 0.018, 0.036), Vector3(0.039, 0.042, 0.03), Vector3.ZERO, stl)
	# ⑧ 小而直的下置握把（bakelite 橙棕）+ 右侧快慢机柄 + 护圈/扳机
	add_box.call(Vector3(0.03, 0.08, 0.042), Vector3(0, -0.055, 0.11), Vector3(14, 0, 0), bkl)
	add_box.call(Vector3(0.004, 0.012, 0.032), Vector3(0.027, 0.008, 0.05), Vector3.ZERO, stl)
	add_box.call(Vector3(0.012, 0.006, 0.06), Vector3(0, -0.05, 0.03), Vector3.ZERO, rcv)
	add_box.call(Vector3(0.008, 0.022, 0.008), Vector3(0, -0.045, 0.035), Vector3.ZERO, stl)


## SCAR-H 战斗步枪（FN SCAR-H Mk17，7.62×51mm NATO）考证特征逐条落件：
## ①沙tan(FDE)细长机匣：色近 M7 但轮廓细长（0.05 宽 × 0.44 长，长径比更大）
## ②全长一体顶轨：从机匣尾直通护木头的单根轨基 + 连续楔齿（无分段感）
## ③大尺寸侧折聚合物托：方盒托体 + 上方贴腮板 + 折叠钮凸块（对照 M7 小伸缩托）
## ④细长枪管 + 长护木（约占全枪一半）：左右各带一小段辅助轨块
## ⑤宽直体 20 发 7.62 弹匣：比 STANAG 宽厚、近直——mag_of 覆盖
## ⑥短鸟笼消焰器（对照 M7 的长双挡环消音筒）
## ⑦直托贴腮：枪托上沿（贴腮板顶）与顶轨齿尖近乎齐平的狙击感直线侧影
static func _ar_scarh(add_box: Callable, add_cyl: Callable,
		mats: Dictionary) -> void:
	var fde: StandardMaterial3D = mats["fde"]   # ① 沙 tan 细长机匣/托体
	var met: StandardMaterial3D = mats["dark"]  # 黑色轨齿/握把
	var stl: StandardMaterial3D = mats["steel"] # 亮钢小件
	# ① 细长一体机匣 + 下机匣（比 M7 的 0.062×0.075×0.30 明显瘦长）
	add_box.call(Vector3(0.05, 0.068, 0.44), Vector3(0, 0.024, -0.12), Vector3.ZERO, fde)
	add_box.call(Vector3(0.046, 0.05, 0.18), Vector3(0, -0.035, 0.05), Vector3.ZERO, fde)
	# ② 全长一体顶轨：单根轨基（机匣尾 z 0.23 直通护木前 z -0.51）+ 连续楔齿
	add_box.call(Vector3(0.026, 0.016, 0.74), Vector3(0, 0.066, -0.14), Vector3.ZERO, met)
	for i in 9:
		add_box.call(Vector3(0.029, 0.006, 0.016),
				Vector3(0, 0.077, -0.48 + 0.085 * float(i)), Vector3.ZERO, met)
	# ④ 长护木（0.32，约占全长一半）+ 左右辅助轨块 + 细长枪管 + 护木前导气座
	add_box.call(Vector3(0.048, 0.064, 0.32), Vector3(0, 0.026, -0.36), Vector3.ZERO, fde)
	add_box.call(Vector3(0.007, 0.028, 0.12), Vector3(-0.0285, 0.012, -0.36), Vector3.ZERO, met)
	add_box.call(Vector3(0.007, 0.028, 0.12), Vector3(0.0285, 0.012, -0.36), Vector3.ZERO, met)
	add_cyl.call(Vector3(0.011, 0.011, 0.16), Vector3(0, 0.028, -0.6), Vector3(90, 0, 0), met)
	add_box.call(Vector3(0.024, 0.026, 0.024), Vector3(0, 0.042, -0.505), Vector3.ZERO, met)
	# ⑥ 短鸟笼消焰器：短筒 + 两侧纵槽口提示 + 后挡环（短于 M7 消音筒）
	add_cyl.call(Vector3(0.015, 0.015, 0.055), Vector3(0, 0.028, -0.675), Vector3(90, 0, 0), met)
	add_box.call(Vector3(0.005, 0.004, 0.03), Vector3(-0.013, 0.028, -0.675), Vector3.ZERO, stl)
	add_box.call(Vector3(0.005, 0.004, 0.03), Vector3(0.013, 0.028, -0.675), Vector3.ZERO, stl)
	add_cyl.call(Vector3(0.0165, 0.0165, 0.01), Vector3(0, 0.028, -0.652), Vector3(90, 0, 0), stl)
	# ③ 大侧折托：贴腮板（⑦ 顶 0.080 与轨齿顶齐平）+ 方盒托体 + 托底板 +
	# 折叠钮凸块 + 铰链轴 + 托底斜楔（「大方托」，与 M7 的 Magpul 小托对照）
	add_box.call(Vector3(0.042, 0.026, 0.24), Vector3(0, 0.067, 0.28), Vector3.ZERO, fde)
	add_box.call(Vector3(0.046, 0.085, 0.19), Vector3(0, -0.005, 0.30), Vector3.ZERO, fde)
	add_box.call(Vector3(0.052, 0.105, 0.018), Vector3(0, -0.012, 0.40), Vector3.ZERO, met)
	add_box.call(Vector3(0.014, 0.026, 0.03), Vector3(0.032, 0.02, 0.225), Vector3.ZERO, met)
	add_cyl.call(Vector3(0.012, 0.012, 0.05), Vector3(0.03, 0.005, 0.19), Vector3(0, 0, 90), stl)
	add_box.call(Vector3(0.04, 0.042, 0.11), Vector3(0, -0.052, 0.33), Vector3(10, 0, 0), fde)
	# ⑤ 宽弹匣井（挂 mag_of 宽直匣：井口 y 顶 -0.0075 对合同匣顶 -0.049）
	add_box.call(Vector3(0.056, 0.075, 0.085), Vector3(0, -0.045, -0.19), Vector3.ZERO, fde)
	# 握把 / 护圈 / 扳机 / 前置左侧拉机柄（SCAR 位于护木后上左）
	add_box.call(Vector3(0.036, 0.085, 0.05), Vector3(0, -0.07, 0.075), Vector3(18, 0, 0), met)
	add_box.call(Vector3(0.012, 0.006, 0.055), Vector3(0, -0.052, 0.015), Vector3.ZERO, met)
	add_box.call(Vector3(0.008, 0.02, 0.008), Vector3(0, -0.045, 0.02), Vector3.ZERO, stl)
	add_box.call(Vector3(0.022, 0.012, 0.028), Vector3(-0.034, 0.03, -0.3), Vector3.ZERO, met)
