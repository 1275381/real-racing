class_name OnFoot
extends Node3D
## 自由漫游下车人模式：第一人称持枪步行 + 射击（左键开枪+自动三倍开镜）。
## 角色碰撞复用楼房 OBB 推出；地面高度走 freeroam query。

signal shoot_hit(kind: String, idx: int, point: Vector3, dmg: float)
signal reload_done

const WALK := 6.0
const RUN := 11.5
const MAG := 30
const RELOAD_TIME := 1.5
const RANGE := 250.0
const FIRE_CD := 0.13
const SCOPE_DIV := 3.0
const SLIDE_SPEED := 14.0    # 滑铲起速（平方衰减到步行速）
const SLIDE_TIME := 0.7
const SLIDE_CD := 1.2        # 滑铲冷却（含铲行时间）
const EYE_H := 1.58
const EYE_H_SLIDE := 0.92

var fm
var npc                   # NpcTraffic（射线目标）
var audio                 # RRAudio（枪声/换弹）
var cam: Camera3D         # 游戏第一人称相机（game 传入）
var active := false
var pos := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var health := 100.0
var ammo := MAG
var reloading := 0.0
var fire_cd := 0.0
var scoped := false      # 三倍镜开关（M 键切换，开火不再联动）
var move_speed := 0.0
var slide_t := 0.0       # 剩余滑铲时间（>0 = 铲行中）
var fire_block := false  # 门旁屏蔽开枪（左键留给开门）
var slide_cd := 0.0      # 滑铲冷却
var slide_dir := Vector3.ZERO
var _eye_h := EYE_H
var _last_idx = null
var _bob_t := 0.0
var _gun_id := "pistol"
var _g: Dictionary = Guns.gun_by_id("pistol")
var gun_ammo := {}        # gun_id → 当前弹匣余量
var ammo_mul := 1.0       # 弹药类型伤害倍率（弹药店）
var _ammo_color := Color(1.0, 0.8, 0.35)
var _mag_mesh: MeshInstance3D       # 枪上弹匣（换弹时脱落/滑入）
var _falling_mag: MeshInstance3D    # 掉落中的弹匣（世界空间）
var _falling_vel := Vector3.ZERO
var _falling := false
var _reload_off := Vector3.ZERO     # 换弹动画的枪体偏移/倾斜
var _reload_rot := Vector3.ZERO
var _base_fov := 63.0
var _gun_holder: Node3D
var _ads := 0.0                      # 开镜过渡 0=腰射 1=瞄准位
const GUN_HIP_POS := Vector3(0.26, -0.22, -0.55)
const GUN_ADS_POS := Vector3(0.09, -0.075, -0.45)
const GUN_HIP_ROT := Vector3(2.5, 4.0, 3.0)
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_t := 0.0
var _tr_pool: Array = []   # 曳光弹对象池 {mi, t}
var _tr_i := 0
var _im_pool: Array = []   # 命中火花对象池 {mi, t}
var _im_i := 0
var _identity := Transform3D()


func enter(p: Vector3, head: float) -> void:
	active = true
	visible = true
	pos = p
	yaw = head
	pitch = 0.0
	health = 100.0
	ammo = _g.get("mag", 12)
	reloading = 0.0
	scoped = false
	if cam != null:
		cam.fov = _base_fov


func exit() -> void:
	active = false
	scoped = false
	slide_t = 0.0
	slide_cd = 0.0
	_eye_h = EYE_H
	# 枪模挂在相机上：离场必须隐藏（战场飞行等 near 面小的相机会放 giant 块）
	if _gun_holder != null:
		_gun_holder.visible = false
	if _flash != null:
		_flash.visible = false
	if _flash_mesh != null:
		_flash_mesh.visible = false
	if _falling_mag != null:
		_falling_mag.visible = false
	if cam != null:
		cam.fov = _base_fov


## C 滑铲：移动中按下沿面朝方向急冲 0.7s，镜头压低 + FOV 拉开（冷却 1.2s）
func try_slide() -> void:
	if not active or slide_cd > 0.0 or slide_t > 0.0:
		return
	if move_speed < 0.5:
		return   # 需在移动中才能铲
	slide_t = SLIDE_TIME
	slide_cd = SLIDE_TIME + SLIDE_CD
	slide_dir = Vector3(sin(yaw), 0, cos(yaw))


## 装备指定枪械：换枪模 + 换数值 + 换弹匣（切枪自动满弹）
func set_gun(gun_id: String) -> void:
	_gun_id = gun_id
	_g = Guns.gun_by_id(gun_id)
	reloading = 0.0
	_falling = false
	if _falling_mag != null:
		_falling_mag.visible = false
	if gun_ammo.has(gun_id):
		ammo = int(gun_ammo[gun_id])
	else:
		ammo = _g.get("mag", 12)
		gun_ammo[gun_id] = ammo
	# 重建枪模：整个旧枪架释放（含手臂），避免相机上堆积
	if _gun_holder != null:
		_gun_holder.queue_free()
	mount_gun(_build_gun_visual(gun_id))


## 程序化低多边形枪模（rifle 用 SCAR GLB，其余按种类拼装）
func _build_gun_visual(gun_id: String) -> Node3D:
	if gun_id == "rifle":
		var glb: Node3D = load("res://assets/cars/gun_rifle.glb").instantiate()
		for mi in glb.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var bm2 := m.mesh.surface_get_material(s)
				if bm2 is StandardMaterial3D:
					var dup: StandardMaterial3D = bm2.duplicate()
					dup.no_depth_test = true
					dup.render_priority = 10
					m.set_surface_override_material(s, dup)
		return glb
	var root := Node3D.new()
	# 视模型材质一律关深度测试：下车点贴着车时枪模不会被车身吞掉
	# 微自发光：开镜镜片视野/暗处枪模都清晰可读
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
			mat: Material) -> void:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = pos
		mi.rotation_degrees = rot_deg
		root.add_child(mi)
	match gun_id:
		"pistol":
			add_box.call(Vector3(0.06, 0.1, 0.3), Vector3(0, 0.04, -0.04), Vector3.ZERO, dark)
			add_box.call(Vector3(0.05, 0.15, 0.08), Vector3(0, -0.08, 0.06), Vector3(3, 0, 0), dark)
		"smg":
			add_box.call(Vector3(0.07, 0.11, 0.44), Vector3(0, 0, -0.05), Vector3.ZERO, dark)
			add_box.call(Vector3(0.05, 0.22, 0.06), Vector3(0, -0.13, 0.04), Vector3(0, 0, 0), dark)
			add_box.call(Vector3(0.05, 0.07, 0.2), Vector3(0, 0.03, -0.32), Vector3.ZERO, steel)
		"shotgun":
			add_box.call(Vector3(0.075, 0.09, 0.85), Vector3(0, 0.03, -0.15), Vector3.ZERO, wood)
			add_box.call(Vector3(0.06, 0.07, 0.5), Vector3(0, -0.04, -0.35), Vector3.ZERO, dark)
			add_box.call(Vector3(0.05, 0.14, 0.1), Vector3(0, -0.06, 0.18), Vector3(-6, 0, 0), wood)
		"sniper":
			add_box.call(Vector3(0.06, 0.09, 1.0), Vector3(0, 0.03, -0.12), Vector3.ZERO, steel)
			add_box.call(Vector3(0.08, 0.13, 0.26), Vector3(0, 0.14, -0.08), Vector3.ZERO, dark)
			add_box.call(Vector3(0.05, 0.17, 0.09), Vector3(0, -0.09, 0.15), Vector3(-5, 0, 0), dark)
	return root


## 挂第一人称枪（相机子节点），rotation.y=-90 使枪口朝前偏左
func setup(freeroam, npc_ref, audio_ref, camera: Camera3D) -> void:
	fm = freeroam
	npc = npc_ref
	audio = audio_ref
	cam = camera
	_setup_fx()
	# 掉落弹匣（换弹动画：旧弹匣从枪上脱落坠地）
	var fm_mesh := BoxMesh.new()
	fm_mesh.size = Vector3(0.055, 0.17, 0.09)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.18, 0.22)
	fm_mesh.material = fmat
	_falling_mag = MeshInstance3D.new()
	_falling_mag.mesh = fm_mesh
	_falling_mag.visible = false
	add_child(_falling_mag)
	# 占位用程序化手枪：每次下车 game 都会 set_gun(当前装备) 重建枪模，
	# 这里若装步枪会在进漫游时同步加载 60MB 的 SCAR GLB（约 0.4s）再立刻丢掉
	set_gun("pistol")

## 曳光弹与命中火花的对象池
func _setup_fx() -> void:
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 0.9, 0.5)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.8, 0.35)
	tmat.emission_energy_multiplier = 4.0
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(0.025, 0.025, 1.0)
	tmesh.material = tmat
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = tmesh
		mi.visible = false
		add_child(mi)
		_tr_pool.append({"mi": mi, "t": 0.0})
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


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var slot: Dictionary = _tr_pool[_tr_i]
	_tr_i = (_tr_i + 1) % _tr_pool.size()
	var mi: MeshInstance3D = slot["mi"]
	var mid := (from + to) * 0.5
	mi.global_position = mid
	mi.look_at_from_position(mid, to, Vector3.UP)
	mi.scale = Vector3(1, 1, from.distance_to(to))
	mi.visible = true
	slot["t"] = 0.18


func _spawn_impact(p: Vector3) -> void:
	var slot: Dictionary = _im_pool[_im_i]
	_im_i = (_im_i + 1) % _im_pool.size()
	slot["mi"].global_position = p
	slot["mi"].visible = true
	slot["t"] = 0.24


func _tick_fx(dt: float) -> void:
	# 掉落弹匣：重力下坠 + 落地静止
	if _falling_mag != null and _falling_mag.visible:
		_falling_vel.y -= 9.8 * dt
		_falling_mag.position += _falling_vel * dt
		_falling_mag.rotation_degrees.z += 140.0 * dt
	for s in _tr_pool:
		if float(s["t"]) > 0.0:
			s["t"] = float(s["t"]) - dt
			if float(s["t"]) <= 0.0:
				s["mi"].visible = false
	for s in _im_pool:
		if float(s["t"]) > 0.0:
			s["t"] = float(s["t"]) - dt
			if float(s["t"]) <= 0.0:
				s["mi"].visible = false


func mount_gun(gun: Node3D) -> void:
	_gun_holder = Node3D.new()
	# 锚点抬到视锥内：原点在相机上时枪/手臂的 y 偏移会落到画面底边
	# 之外，平视时整把枪都在屏幕外（HUD 再一挡就"看不到枪"）
	_gun_holder.position = Vector3(0.26, -0.22, -0.55)
	_gun_holder.rotation_degrees = Vector3(2.5, 4.0, 3.0)
	cam.add_child(_gun_holder)
	gun.scale = Vector3.ONE * 0.62
	_gun_holder.add_child(gun)
	# 枪上弹匣（换弹动画：脱落/滑入用）
	var mag_mesh := BoxMesh.new()
	mag_mesh.size = Vector3(0.055, 0.17, 0.09)
	var mag_mat := StandardMaterial3D.new()
	mag_mat.albedo_color = Color(0.16, 0.18, 0.22)
	mag_mat.no_depth_test = true
	mag_mat.render_priority = 10
	mag_mesh.material = mag_mat
	_mag_mesh = MeshInstance3D.new()
	_mag_mesh.mesh = mag_mesh
	_mag_mesh.position = Vector3(0.02, -0.14, -0.16)
	_gun_holder.add_child(_mag_mesh)
	# 枪口火光：小发光片 + 瞬时点光
	_flash_mesh = MeshInstance3D.new()
	var fm_mesh := SphereMesh.new()
	fm_mesh.radius = 0.045
	fm_mesh.height = 0.09
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.8, 0.3)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.7, 0.2)
	fmat.emission_energy_multiplier = 6.0
	fm_mesh.material = fmat
	_flash_mesh.mesh = fm_mesh
	_flash_mesh.visible = false
	_gun_holder.add_child(_flash_mesh)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.35)
	_flash.light_energy = 3.0
	_flash.omni_range = 6.0
	_flash.visible = false
	cam.add_child(_flash)


## 鼠标视角（game 转发已捕获的鼠标相对位移）
func add_look(rel: Vector2) -> void:
	yaw -= rel.x * 0.0023
	pitch = clampf(pitch - rel.y * 0.0023, -1.35, 1.35)


func take_damage(dmg: float) -> void:
	health = maxf(0.0, health - dmg)


func update(dt: float) -> void:
	if not active:
		return
	_tick_fx(dt)
	fire_cd = maxf(0.0, fire_cd - dt)
	_bob_t += dt * (2.2 if move_speed > 0.1 else 0.8)
	# 换弹动画：枪体下倾 → 旧弹匣脱落坠地 → 新弹匣滑入 → 回位
	if reloading > 0.0:
		reloading -= dt
		var total: float = _g.get("reload", 1.5)
		var prog: float = clampf(1.0 - reloading / maxf(total, 0.01), 0.0, 1.0)
		var dip := sin(prog * PI)
		_reload_off = Vector3(0.03 * dip, -0.09 * dip, 0.05 * dip)
		_reload_rot = Vector3(4.0 * dip, 0, 26.0 * dip)
		# 28%~60%：旧弹匣脱落坠地（世界空间，重力+前抛）
		if prog > 0.28 and prog < 0.60:
			_mag_mesh.visible = false
			if not _falling:
				_falling = true
				_falling_mag.global_position = cam.global_position * 						Transform3D(Basis.IDENTITY, Vector3.ZERO) * \
						Transform3D(Basis.IDENTITY, Vector3(0.02, -0.1, -0.3)) if false \
						else cam.to_global(Vector3(0.02, -0.16, -0.3))
				_falling_vel = cam.global_transform.basis.z * 0.8 + Vector3(0, -0.4, 0)
				_falling_mag.visible = true
		elif prog >= 0.60:
			_mag_mesh.visible = true
			_falling = false
		if reloading <= 0.0:
			reloading = 0.0
			ammo = _g.get("mag", 12)
			reload_done.emit()
	else:
		_reload_off = Vector3.ZERO
		_reload_rot = Vector3.ZERO
		_mag_mesh.visible = true
		_falling = false
	# 移动（C 滑铲：沿启动时朝向急冲，平方衰减；铲行中不接受转向输入）
	slide_cd = maxf(0.0, slide_cd - dt)
	var mf := 0.0
	var ms := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		mf += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		mf -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		ms += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		ms -= 1.0
	if slide_t > 0.0:
		slide_t -= dt
		var k := clampf(slide_t / SLIDE_TIME, 0.0, 1.0)
		var spd := WALK + (SLIDE_SPEED - WALK) * k * k
		pos += slide_dir * spd * dt
		move_speed = spd
	elif mf != 0.0 or ms != 0.0:
		var run := Input.is_physical_key_pressed(KEY_SHIFT)
		move_speed = (RUN if run else WALK) * clampf(Vector2(mf, ms).length(), 0.0, 1.0)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var dir := (fwd * mf + right * ms).normalized()
		pos += dir * move_speed * dt
	else:
		move_speed = 0.0
	# 楼房 OBB 推出（半径 0.5）。带 bot 的障碍（高处栏杆等）只在其
	# 高度区间生效：行人在其下方可正常通行
	for ob in fm.obstacles_box:
		if ob.get("off", false):
			continue
		if ob.has("top") and pos.y > float(ob["top"]) - 1.0:
			continue
		if ob.has("bot") and pos.y + 1.6 < float(ob["bot"]):
			continue
		var dx: float = pos.x - ob["c"].x
		var dz: float = pos.z - ob["c"].y
		if dx * dx + dz * dz > 40.0 * 40.0:
			continue
		var ca: float = cos(ob["rot"])
		var sa: float = sin(ob["rot"])
		var lx: float = ca * dx + sa * dz
		var lz: float = -sa * dx + ca * dz
		var cx := clampf(lx, -ob["hx"], ob["hx"])
		var cz := clampf(lz, -ob["hz"], ob["hz"])
		var ddx := lx - cx
		var ddz := lz - cz
		var d2 := ddx * ddx + ddz * ddz
		if d2 > 0.25:
			continue
		var d := sqrt(d2)
		if d > 0.001:
			pos.x += (ddx / d) * (0.5 - d) * ca - (ddz / d) * (0.5 - d) * sa
			pos.z += (ddx / d) * (0.5 - d) * sa + (ddz / d) * (0.5 - d) * ca
	# 地面
	var q: Dictionary = fm.query(pos.x, pos.z, _last_idx, pos.y)
	_last_idx = q["idx"]
	pos.y = q["height"]
	# 地图边界（飞抵远方城市后，按远城范围放行）
	var lim := FreeroamMap.MAP_LIMIT
	if fm != null and fm.has_method("far_city_contains") 			and fm.far_city_contains(pos.x, pos.z):
		lim = FreeroamMap.WORLD_LIMIT
	pos.x = clampf(pos.x, -lim, lim)
	pos.z = clampf(pos.z, -lim, lim)
	# 射击（左键按住 = 开枪 + 自动三倍开镜）
	if Input.is_action_pressed("rr_fire") and not fire_block \
			and fire_cd <= 0.0 and reloading <= 0.0:
		if ammo > 0:
			_shoot()
		else:
			_start_reload()
	# 相机：第一人称 + 走路轻微点头 + 滑铲压低视线 + 开镜 FOV
	var eye_target := EYE_H_SLIDE if slide_t > 0.0 else EYE_H
	_eye_h = lerpf(_eye_h, eye_target, 1.0 - exp(-14.0 * dt))
	var bob := sin(_bob_t) * 0.02 * minf(move_speed, 1.0)
	cam.position = pos + Vector3(0, _eye_h + bob, 0)
	cam.rotation = Vector3(pitch, yaw + PI, 0)   # Godot 相机前向 = -(sin,cos)，需加 PI 对齐位移约定
	var scope_div: float = _g.get("scope_div", 1.0) if scoped else 1.0
	var target_fov: float = _base_fov / maxf(scope_div, 1.0)
	if slide_t > 0.0 and not scoped:
		target_fov += 10.0   # 滑铲速度感
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - exp(-14.0 * dt))
	# 开镜 = 枪模收到屏幕中心瞄准位（不再整体隐藏，镜内可见枪身）；
	# 腰射回到持枪位
	_ads = move_toward(_ads, 1.0 if scoped else 0.0, dt * 5.0)
	_gun_holder.visible = true
	_gun_holder.position = GUN_HIP_POS.lerp(GUN_ADS_POS, _ads)
	_gun_holder.rotation_degrees = GUN_HIP_ROT.lerp(Vector3(1.5, 2.0, 0), _ads)
	# 枪口火光衰减
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			_flash.visible = false
			_flash_mesh.visible = false


func _start_reload() -> void:
	if reloading > 0.0 or ammo >= _g.get("mag", 12):
		return
	reloading = _g.get("reload", 1.5)
	audio.play_reload()


func _shoot() -> void:
	ammo -= 1
	fire_cd = _g.get("cd", 0.13)
	# 枪口火光（发光片贴枪口 + 瞬时点光）
	_flash_t = 0.05
	_flash.visible = true
	_flash.position = Vector3(0.2, -0.08, -0.85)
	_flash_mesh.visible = true
	_flash_mesh.position = Vector3(0.02, 0.06, -0.62)
	# 射线（每条弹丸独立判定）
	var from: Vector3 = cam.global_position
	var base_dir: Vector3 = -cam.global_transform.basis.z
	var spread: float = _g.get("spread", 0.0)
	var pellets: int = _g.get("pellets", 1)
	var range: float = _g.get("range", 250.0)
	var dmg: float = _g.get("dmg", 20.0) * ammo_mul
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	for p in pellets:
		var jitter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * spread * 2.0
		var pdir := (base_dir + right * jitter.x + up * jitter.y).normalized()
		var hit: Dictionary = npc.raycast(from, pdir, range)
		var end: Vector3 = from + pdir * range if hit["type"] == "" \
				else Vector3(hit["point"])
		_spawn_tracer(muzzle_world(), end)
		if hit["type"] != "":
			_spawn_impact(end)
			shoot_hit.emit(hit["type"], hit["i"], end, dmg)
	audio.play_shot()


## 枪口世界坐标
func muzzle_world() -> Vector3:
	return cam.global_transform * Vector3(0.02, 0.06, -0.62)


## 装备弹药类型（伤害倍率 + 曳光/火花颜色）
func set_ammo_type(ammo_id: String) -> void:
	var a: Dictionary = Guns.ammo_by_id(ammo_id)
	ammo_mul = a.get("dmg_mul", 1.0)
	_ammo_color = a.get("color", Color(1.0, 0.8, 0.35))
	for s in _tr_pool:
		(s["mi"].mesh as BoxMesh).material.set("emission", _ammo_color)
		(s["mi"].mesh as BoxMesh).material.set("albedo_color", _ammo_color)
	for s in _im_pool:
		(s["mi"].mesh as SphereMesh).material.set("emission", _ammo_color)
		(s["mi"].mesh as SphereMesh).material.set("albedo_color", _ammo_color)


## 三倍镜开关（M 键）
func toggle_scope() -> void:
	scoped = not scoped
