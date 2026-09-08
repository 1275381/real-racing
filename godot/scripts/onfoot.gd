class_name OnFoot
extends Node3D
## 自由漫游下车人模式：第一人称持枪步行 + 射击（左键开枪+自动三倍开镜）。
## 角色碰撞复用楼房 OBB 推出；地面高度走 freeroam query。

signal shoot_hit(kind: String, idx: int, point: Vector3)
signal reload_done

const WALK := 4.5
const RUN := 8.5
const MAG := 30
const RELOAD_TIME := 1.5
const RANGE := 250.0
const FIRE_CD := 0.13
const SCOPE_DIV := 3.0

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
var aiming := false       # 左键按住 = 射击 + 三倍开镜
var move_speed := 0.0
var _last_idx = null
var _bob_t := 0.0
var _base_fov := 63.0
var _gun_holder: Node3D
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_t := 0.0
var _dbg := 0
var _identity := Transform3D()


func enter(p: Vector3, head: float) -> void:
	active = true
	visible = true
	pos = p
	yaw = head
	pitch = 0.0
	health = 100.0
	ammo = MAG
	reloading = 0.0
	if cam != null:
		cam.fov = _base_fov


func exit() -> void:
	active = false
	aiming = false
	if cam != null:
		cam.fov = _base_fov


## 挂第一人称枪（相机子节点），rotation.y=-90 使枪口朝前偏左
func setup(freeroam, npc_ref, audio_ref, camera: Camera3D) -> void:
	fm = freeroam
	npc = npc_ref
	audio = audio_ref
	cam = camera
	# 枪模型（顶部自带三倍镜，ADS 时镜筒对准屏幕中心）
	var gun: Node3D = load("res://assets/cars/gun_rifle.glb").instantiate()
	mount_gun(gun)


func mount_gun(gun: Node3D) -> void:
	_gun_holder = Node3D.new()
	cam.add_child(_gun_holder)
	gun.rotation_degrees = Vector3(0, -90, 0)
	gun.scale = Vector3.ONE * 0.55
	_gun_holder.add_child(gun)
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
	fire_cd = maxf(0.0, fire_cd - dt)
	_bob_t += dt * (2.2 if move_speed > 0.1 else 0.8)
	# 换弹
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			reloading = 0.0
			ammo = MAG
			reload_done.emit()
	# 移动
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
	var run := Input.is_physical_key_pressed(KEY_SHIFT)
	move_speed = (RUN if run else WALK) * clampf(Vector2(mf, ms).length(), 0.0, 1.0)
	if mf != 0.0 or ms != 0.0:
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var dir := (fwd * mf + right * ms).normalized()
		pos += dir * move_speed * dt
	# 楼房 OBB 推出（半径 0.5）
	for ob in fm.obstacles_box:
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
	# 地图边界
	pos.x = clampf(pos.x, -FreeroamMap.MAP_LIMIT, FreeroamMap.MAP_LIMIT)
	pos.z = clampf(pos.z, -FreeroamMap.MAP_LIMIT, FreeroamMap.MAP_LIMIT)
	# 射击（左键按住 = 开枪 + 自动三倍开镜）
	aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if aiming and fire_cd <= 0.0 and reloading <= 0.0:
		if ammo > 0:
			_shoot()
		else:
			_start_reload()
	if reloading > 0.0 or ammo == 0:
		aiming = aiming and false
	# 相机：第一人称 + 走路轻微点头 + 开镜 FOV
	var bob := sin(_bob_t) * 0.02 * minf(move_speed, 1.0)
	cam.position = pos + Vector3(0, 1.58 + bob, 0)
	cam.rotation = Vector3(pitch, yaw + PI, 0)   # Godot 相机前向 = -(sin,cos)，需加 PI 对齐位移约定
	var target_fov := _base_fov / SCOPE_DIV if aiming else _base_fov
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - exp(-14.0 * dt))
	# 枪位：腰射（右下）↔ 开镜（镜筒对准屏幕中心）
	var target := Vector3(0.0, -0.152, -0.32) if aiming else Vector3(0.18, -0.10, -0.35)
	_gun_holder.position = _gun_holder.position.lerp(target, 1.0 - exp(-16.0 * dt))
	# 枪口火光衰减
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			_flash.visible = false
			_flash_mesh.visible = false


func _start_reload() -> void:
	if reloading > 0.0 or ammo >= MAG:
		return
	reloading = RELOAD_TIME
	audio.play_reload()


func _shoot() -> void:
	ammo -= 1
	fire_cd = FIRE_CD
	# 枪口火光（发光片贴枪口 + 瞬时点光）
	_flash_t = 0.05
	_flash.visible = true
	_flash.position = Vector3(0.2, -0.08, -0.85)
	_flash_mesh.visible = true
	_flash_mesh.position = Vector3(0.02, 0.06, -0.62)
	# 射线
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_transform.basis.z
	var hit: Dictionary = npc.raycast(from, dir, RANGE)
	if _dbg < 4:
		_dbg += 1
		print("[shot-dbg] from=%s dir=%s 命中=%s d=%.1f" % [from, dir, hit["type"], hit["d"]])
	if hit["type"] != "":
		shoot_hit.emit(hit["type"], hit["i"], hit["point"])
	audio.play_shot()
