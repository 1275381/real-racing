class_name HDPlayer
extends Node3D
## 烽火地带玩家：第一人称移动/视角/血量（母本 onfoot.gd 模式：pos 变量 +
## 楼房 OBB 推出，不用物理引擎）。相机是本节点子节点、由 update 摆位；
## 后坐力（recoil_pitch/recoil_yaw）与开镜（ads/zoom）由 HDGuns 每发/每帧写入，
## 本模块只负责回落与 FOV 应用。

signal died

const WALK := 3.0
const RUN := 6.5
const CROUCH_MUL := 0.45        # 蹲行移速倍率（蹲 0.45×）
const EYE_H := 1.55
const EYE_H_CROUCH := 0.95
const PUSH_R := 0.5             # 障碍推出半径（onfoot 同款）
const BASE_FOV := 75.0
const RECOIL_FALL := 45.0       # 停火 0.25s 后每秒回落角度（度）
const RECOIL_YAW_FALL := 10.0   # 水平漂移回落速度（度）
const RECOIL_MAX := 6.0         # 后坐上顶上限（度，防打天花板）

var cam: Camera3D
var pos := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var health := 100.0
var dead := false
var recoil_pitch := 0.0   # HDGuns 每发写入（视角上顶，rad）
var recoil_yaw := 0.0     # HDGuns 每发写入（水平漂移，rad）
var recoil_cool := 0.0    # 停火计时：HDGuns 开火清零，>0.25s 开始回落
var ads := 0.0            # HDGuns 每帧写入（开镜过渡 0..1）
var zoom := 1.0           # HDGuns 每帧写入（当前倍率，FOV=75/zoom）
var sprinting := false
var crouching := false

var _world                # 烽火地带世界（鸭子类型：obstacles_near/ground_height）
var _eye_h := EYE_H
var _speed := 0.0
var _bob_t := 0.0


func setup(world) -> void:
	_world = world
	# 相机构造时 new：near 压到 0.02 保枪模贴脸不穿帮，far 600 覆盖全图
	cam = Camera3D.new()
	cam.near = 0.02
	cam.far = 600.0
	cam.fov = BASE_FOV
	cam.current = true
	add_child(cam)


## 进场/重生：满血、清后坐与开镜状态、摆位到出生点
func enter(spawn: Vector3) -> void:
	pos = spawn
	health = 100.0
	dead = false
	recoil_pitch = 0.0
	recoil_yaw = 0.0
	recoil_cool = 0.0
	ads = 0.0
	zoom = 1.0
	sprinting = false
	crouching = false
	pitch = 0.0
	_eye_h = EYE_H
	_speed = 0.0
	if cam != null:
		cam.position = pos + Vector3(0, EYE_H, 0)
		cam.rotation = Vector3(pitch, yaw + PI, 0)
		cam.fov = BASE_FOV


## 鼠标视角（main 转发已捕获的鼠标相对位移）：0.0023 灵敏度，pitch ±1.35
func add_look(rel: Vector2) -> void:
	yaw -= rel.x * 0.0023
	pitch = clampf(pitch - rel.y * 0.0023, -1.35, 1.35)


func update(dt: float) -> void:
	if dead or cam == null:
		return
	_bob_t += dt * (2.2 if _speed > 0.1 else 0.8)
	# 蹲（C 按住）：压眼高 + 减速；疾跑（Shift）只在移动且不蹲时生效
	crouching = Input.is_physical_key_pressed(KEY_C)
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
	var moving := mf != 0.0 or ms != 0.0
	sprinting = Input.is_physical_key_pressed(KEY_SHIFT) and moving \
			and not crouching
	if moving:
		# 常态步行 3.0 / Shift 疾跑 6.5 / 蹲再乘 0.45；斜向不超速
		var spd := (RUN if sprinting else WALK) \
				* (CROUCH_MUL if crouching else 1.0)
		_speed = spd * clampf(Vector2(mf, ms).length(), 0.0, 1.0)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		# 屏幕右 = 前向 × 上。onfoot 踩过的坑：写成 (cos,0,-sin) 是屏幕左
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		var dir := (fwd * mf + right * ms).normalized()
		pos += dir * _speed * dt
	else:
		_speed = 0.0
	if _world != null:
		_push_out_obstacles()
		pos.y = _world.ground_height(pos.x, pos.z)
	# 图边界（HDData：340m 见方）
	pos.x = clampf(pos.x, -HDData.MAP_HALF, HDData.MAP_HALF)
	pos.z = clampf(pos.z, -HDData.MAP_HALF, HDData.MAP_HALF)
	# 相机：眼高（蹲 0.95）+ 走动轻微点头
	var eye_target := EYE_H_CROUCH if crouching else EYE_H
	_eye_h = lerpf(_eye_h, eye_target, 1.0 - exp(-14.0 * dt))
	var bob := sin(_bob_t) * 0.02 * minf(_speed, 1.0)
	cam.position = pos + Vector3(0, _eye_h + bob, 0)
	# 后坐回落：停火 0.25s 后每秒 45° 压回，水平漂移同步归零，上限 6°
	recoil_cool += dt
	if recoil_cool > 0.25:
		recoil_pitch = maxf(0.0, recoil_pitch - deg_to_rad(RECOIL_FALL) * dt)
		recoil_yaw = move_toward(recoil_yaw, 0.0, deg_to_rad(RECOIL_YAW_FALL) * dt)
	recoil_pitch = minf(recoil_pitch, deg_to_rad(RECOIL_MAX))
	cam.rotation = Vector3(pitch + recoil_pitch, yaw + recoil_yaw + PI, 0)
	cam.fov = lerpf(cam.fov, BASE_FOV / maxf(zoom, 1.0), 1.0 - exp(-14.0 * dt))


func eye_pos() -> Vector3:
	return cam.global_position


## 中弹：血量扣减，归零判死（died 只发一次）
func hit(dmg: float) -> void:
	if dead:
		return
	health = maxf(0.0, health - dmg)
	if health <= 0.0:
		dead = true
		died.emit()


## 障碍推出（onfoot 的 OBB push_out：半径 0.5，含 top/bot 高度过滤——
## 高处栏杆等带 bot 的障碍只在其高度区间生效，脚下可正常通行）。
## 障碍字典鸭子类型：HDWorld 给 {cx,cz,hx,hz,top,bot}（轴对齐无旋转），
## 兼容 onfoot 式 {c:Vector2, rot}——缺 rot 按轴对齐（ca=1/sa=0 退化）
func _push_out_obstacles() -> void:
	for ob in _world.obstacles_near(pos.x, pos.z):
		if ob.get("off", false):
			continue
		if ob.has("top") and pos.y > float(ob["top"]) - 1.0:
			continue
		if ob.has("bot") and pos.y + 1.6 < float(ob["bot"]):
			continue
		var ox: float = ob["c"].x if ob.has("c") else float(ob["cx"])
		var oz: float = ob["c"].y if ob.has("c") else float(ob["cz"])
		var rot: float = float(ob["rot"]) if ob.has("rot") else 0.0
		var dx: float = pos.x - ox
		var dz: float = pos.z - oz
		if dx * dx + dz * dz > 40.0 * 40.0:
			continue
		var ca: float = cos(rot)
		var sa: float = sin(rot)
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
			pos.x += (ddx / d) * (PUSH_R - d) * ca - (ddz / d) * (PUSH_R - d) * sa
			pos.z += (ddx / d) * (PUSH_R - d) * sa + (ddz / d) * (PUSH_R - d) * ca
