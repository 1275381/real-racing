class_name HDGuns
extends Node3D
## 烽火地带枪械：双槽（primary/secondary）程序化拼枪 + ADS + 换弹（含弹匣
## 掉落三段动画）+ hitscan 结算。母本 onfoot.gd：枪模挂相机（no_depth_test
## 材质防车身吞枪）、mount 用枪模 AABB 把瞄准位对到准星正下方、曳光+火花池。
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

## 每发后坐力（度）：[基础上抬, 连发累增系数, 水平漂移幅度]（onfoot 同表）
const RECOIL := {
	"pistol": [0.22, 0.14, 0.08],
	"smg": [0.13, 0.06, 0.09],
	"rifle": [0.17, 0.09, 0.10],
	"shotgun": [0.9, 0.0, 0.32],
	"sniper": [1.3, 0.0, 0.2],
	"lmg": [0.20, 0.08, 0.14],
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
var _falling_vel := Vector3.ZERO
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
	# 换弹动画：枪体下倾 → 0.25~0.55 旧匣脱落坠地 → 0.55~0.85 新匣滑入 → 回位
	var mag: MeshInstance3D = g["mag"]
	var show_mag: bool = g["show_mag"]
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
			mag.position = MAG_POS + Vector3(0.0, -0.12 * (1.0 - k), 0.0)
		else:
			mag.visible = show_mag
			mag.position = MAG_POS
			_falling = false
		if reloading <= 0.0:
			reloading = 0.0
			var mag_n: int = int(_g.get("mag", 12))
			var taken: int = mini(mag_n - ammo, reserve)
			ammo += taken
			reserve -= taken
			mag.visible = show_mag
			mag.position = MAG_POS
			reloaded.emit()
	else:
		_reload_off = Vector3.ZERO
		_reload_rot = Vector3.ZERO
		mag.visible = show_mag
		mag.position = MAG_POS
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


## 当前开镜倍率：没按右键 = 1.0（FOV 不变）；机瞄 1.0；装镜取镜 zoom
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
	# 枪上弹匣（换弹动画：脱落/滑入用）
	var mag_box := BoxMesh.new()
	mag_box.size = Vector3(0.055, 0.17, 0.09)
	var mag_mat := StandardMaterial3D.new()
	mag_mat.albedo_color = Color(0.16, 0.18, 0.22)
	mag_mat.no_depth_test = true
	mag_mat.render_priority = 10
	mag_box.material = mag_mat
	var mag := MeshInstance3D.new()
	mag.mesh = mag_box
	mag.position = MAG_POS
	holder.add_child(mag)
	var show_mag := gid != "rifle"   # GLB 步枪自带弹匣：程序化块不显示（否则悬空）
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
			"flash": flash, "flash_mesh": flash_mesh, "top": top, "cx": cx}


## 程序化低多边形枪模（rifle 用 SCAR GLB，其余按种类拼装、外形互相可辨）
func _build_gun_visual(gun_id: String) -> Node3D:
	if gun_id == "rifle":
		# 存在性检查后加载真步枪 GLB（照 onfoot：转 180° + 材质复制关深度测试）
		var res: Resource = load("res://assets/cars/gun_rifle.glb")
		if res is PackedScene:
			var glb: Node3D = (res as PackedScene).instantiate()
			# SCAR 模型枪头朝本地 +Z：转 180° 让枪口对准屏幕前方
			glb.rotation.y = PI
			for mi in glb.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				for s in m.mesh.get_surface_count():
					var bm2 := m.mesh.surface_get_material(s)
					if bm2 is StandardMaterial3D:
						var dup: StandardMaterial3D = bm2.duplicate()
						dup.no_depth_test = true
						dup.render_priority = 10
						m.set_surface_override_material(s, dup)
			var sc_r: Dictionary = _scope_info_for(gun_id)
			_scope_visual(glb, str(sc_r.get("kind", "iron")), 0.085, 0.1, -0.5)
			return glb
		# GLB 缺失也不返回空：落到下面的程序化拼装，保证 5 把必可建
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
		"smg":
			# 微冲：短机匣 + 消音器 + 侧折托 + 下垂弹匣 + 顶部导轨
			add_box.call(Vector3(0.07, 0.10, 0.40), Vector3(0, 0, -0.05), Vector3.ZERO, dark)
			_cyl.call(Vector3(0.022, 0.022, 0.22), Vector3(0, 0.012, -0.34), Vector3(90, 0, 0), steel)
			add_box.call(Vector3(0.045, 0.03, 0.16), Vector3(0, 0.068, -0.05), Vector3.ZERO, steel)
			add_box.call(Vector3(0.045, 0.17, 0.05), Vector3(0, -0.12, 0.0), Vector3(6, 0, 0), dark)
			add_box.call(Vector3(0.05, 0.06, 0.18), Vector3(0, -0.02, 0.16), Vector3.ZERO, dark)
			add_box.call(Vector3(0.02, 0.05, 0.05), Vector3(0, -0.07, -0.16), Vector3.ZERO, steel)
		"rifle":
			# 备用突击步枪（GLB 缺失时）：长机匣 + 护木 + 直弹匣 + 枪托
			add_box.call(Vector3(0.06, 0.09, 0.55), Vector3(0, 0.02, -0.08), Vector3.ZERO, dark)
			_cyl.call(Vector3(0.02, 0.02, 0.30), Vector3(0, 0.03, -0.48), Vector3(90, 0, 0), steel)
			add_box.call(Vector3(0.05, 0.05, 0.22), Vector3(0, 0.015, -0.38), Vector3.ZERO, dark)
			add_box.call(Vector3(0.045, 0.16, 0.07), Vector3(0, -0.11, -0.04), Vector3(12, 0, 0), steel)
			add_box.call(Vector3(0.05, 0.10, 0.24), Vector3(0, -0.04, 0.24), Vector3(-4, 0, 0), dark)
			add_box.call(Vector3(0.04, 0.07, 0.05), Vector3(0, -0.07, 0.08), Vector3.ZERO, steel)
		"shotgun":
			# 泵动霰弹：木托 + 双管感 + 泵动前托 + 弹管
			add_box.call(Vector3(0.07, 0.09, 0.80), Vector3(0, 0.025, -0.16), Vector3.ZERO, wood)
			_cyl.call(Vector3(0.028, 0.028, 0.52), Vector3(0, 0.055, -0.36), Vector3(90, 0, 0), steel)
			_cyl.call(Vector3(0.022, 0.022, 0.42), Vector3(0, -0.005, -0.34), Vector3(90, 0, 0), dark)
			add_box.call(Vector3(0.06, 0.06, 0.14), Vector3(0, -0.02, -0.36), Vector3.ZERO, wood)
			add_box.call(Vector3(0.055, 0.15, 0.10), Vector3(0, -0.07, 0.14), Vector3(-8, 0, 0), wood)
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
	# 枪顶瞄具模型：装上的瞄具优先（iron=机瞄片）；狙击自带密位镜，
	# 仅装热成像时在镜后加挂热成像单元（onfoot 分支照搬）
	var sc: Dictionary = _scope_info_for(gun_id)
	var s_kind: String = str(sc.get("kind", "iron"))
	if gun_id == "sniper":
		if s_kind == "thermal":
			_scope_visual(root, "thermal", 0.12, 0.05, -0.3)
	else:
		var my := 0.085
		var mz := -0.1
		var fz := -0.5
		match gun_id:
			"pistol": my = 0.10; mz = -0.04; fz = -0.2
			"smg": my = 0.075; mz = -0.05; fz = -0.2
			"rifle": my = 0.09; mz = -0.1; fz = -0.45
			"shotgun": my = 0.095; mz = -0.16; fz = -0.38
		_scope_visual(root, s_kind, my, mz, fz)
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
## builtin_scope（狙击原厂镜），再没有 = 机瞄
func _scope_info_for(gun_id: String) -> Dictionary:
	var sc := {}
	if scope_provider != null and scope_provider.is_valid():
		sc = scope_provider.call(gun_id)
	if sc.is_empty():
		var gi: Dictionary = Guns.gun_by_id(gun_id)
		if gi.has("builtin_scope"):
			sc = gi["builtin_scope"]
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


## 旧弹匣脱匣：从枪身弹匣位落到世界空间，初速 = 枪前向 0.8 + 向下 0.4
func _drop_mag() -> void:
	_ensure_falling_mag()
	_falling_mag.global_position = player.cam.to_global(Vector3(0.02, -0.16, -0.3))
	# 相机 -Z = 枪口方向（basis.z 朝身后，取负才是前抛）
	_falling_vel = -player.cam.global_transform.basis.z * 0.8 + Vector3(0, -0.4, 0)
	_falling_mag.scale = Vector3.ONE
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
				# 渐隐：末 0.5s 缩小到消失（材质不动，免引透明管线）
				var k := clampf(_mag_rest_t / 0.5, 0.0, 1.0)
				_falling_mag.scale = Vector3.ONE * maxf(k, 0.01)
			if _mag_rest_t <= 0.0:
				_falling_mag.queue_free()
				_falling_mag = null
				_mag_landed = false
				_falling = false
