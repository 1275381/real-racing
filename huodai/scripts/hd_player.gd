class_name HDPlayer
extends Node3D
## 烽火地带玩家：第一人称移动/视角/血量（母本 onfoot.gd 模式：pos 变量 +
## 楼房 OBB 推出，不用物理引擎）。相机是本节点子节点、由 update 摆位；
## 后坐力（recoil_pitch/recoil_yaw）与开镜（ads/zoom）由 HDGuns 每发/每帧写入，
## 本模块只负责回落与 FOV 应用。
## 枪模视口：本模块还负责 viewmodel 独立视口（_build_vm）——枪模由 HDGuns
## 挂到 vm_cam（own_world_3d 独立世界）而非主相机，每帧 sync_vm 把主相机
## transform/FOV 钉进 vm 相机：投影一致=枪的屏幕落点与旧「挂主相机」逐像素
## 等价，而 vm 世界零场景几何，枪与掩体的深度交互物理消失（贴掩体「分裂」
## 与透明掩体盖枪两条病因同根除，见 HDGuns/HDPlayer 双头注释）。

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
const LEAN_OFF := 0.42          # 探头侧移量（米：Q/E 左右探头）
const LEAN_ROLL := 11.0         # 探头侧滚（度：头跟着歪，地平线反向倾斜）
const LEAN_SPEED := 6.0         # 探头过渡速率（1/秒，≈0.17s 到位）
const LEAN_EYE_DROP := 0.05     # 探头时眼高微降（米：侧身压肩）

## —— viewmodel 独立视口常量 ——
## VM_LAYER=5 的层序契约：3D 世界 < 5 枪模合成层 < 10 HUD < 20 大厅——
## 枪永远压在世界之上（旧「挂相机」的本意），又永远被 HUD 分划/大厅盖住
const VM_LAYER := 5
## vm 专属定向光能量：恒定档（介于主世界室外 1.7 与室内 0.25 之间）——
## 枪可读性从此不依赖站位遮阳，这正是「不再一味补光、让分裂物理不可能」
## 之后光照侧的收口：独立世界没有遮挡，一盏恒光 + vm_fill 就处处可读
const VM_SUN_ENERGY := 1.05

var cam: Camera3D
var vm_viewport: SubViewport   # 枪模独立视口（own_world_3d：独立 World3D）
var vm_cam: Camera3D           # vm 世界相机：每帧同步主相机 transform/FOV
var vm_layer: CanvasLayer      # 合成层：全屏 TextureRect 直贴 vm 画面
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
var lean := 0.0            # 探头目标（-1 左 / 0 中 / +1 右，Q/E 按住）
var lean_cur := 0.0        # 探头平滑值（向 lean 过渡；相机侧移/侧滚都吃它）

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
	_build_vm()


## —— viewmodel 独立视口装配（架构定案见类头与 HDGuns 头注）——
## 为什么是 own_world_3d SubViewport：枪「分裂」从来不是枪本身裂——枪一直
## 是一体渲染的，裂的是枪与场景的深度交互：贴掩体时枪管穿透薄墙，穿出段
## 被 no_depth_test 叠画在墙上读成两截；透明掩体（玻璃）在 transparent pass
## 整层盖过枪模。独立 World3D 里没有任何场景几何，这两条病因物理消失——
## 用户定案「不要一味补光，必须让枪物理上不可能分裂」的兑现。
## 合成链：vm_viewport（transparent_bg 清屏透明）→ vm_layer(5) 全屏
## TextureRect——探针/窗口截图拍根视口必拍到合成结果。
func _build_vm() -> void:
	var main_vp := get_viewport()
	vm_viewport = SubViewport.new()
	vm_viewport.own_world_3d = true   # 独立 World3D：零场景几何=分裂物理不可能
	vm_viewport.transparent_bg = true   # 清屏透明：枪像素叠加在世界画面之上
	vm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# MSAA 对齐主视口：枪的边缘抗锯齿与世界一致，合成不露「两层采样感」
	vm_viewport.msaa_3d = main_vp.msaa_3d
	vm_viewport.size = main_vp.size
	add_child(vm_viewport)
	# vm 相机：transform/fov/near/far 每帧同步主相机（sync_vm）——投影矩阵
	# 一致，holder 局部摆位渲染出的屏幕落点与旧「挂主相机」完全等价，
	# ADS/开镜 FOV 缩放与 HIDE_ZOOM 藏枪逻辑零改动
	vm_cam = Camera3D.new()
	vm_cam.near = cam.near
	vm_cam.far = cam.far
	vm_cam.fov = BASE_FOV
	vm_cam.current = true
	vm_viewport.add_child(vm_cam)
	# vm 专属光照（定案：不做雾——枪贴相机，雾贡献可忽略；set_indoor 的
	# 室内/室外雾切换只属于主世界）：
	# 一盏跟随相机的暖定向光（挂 vm_cam 下=相对枪方向恒定，可读性不随
	# 站位/朝向塌陷——补光三连补丁要解决的「暗部塌陷」从此无载体）+
	# 中性 ambient；阴影关（vm 世界无几何，无影可投）。
	# 调色/泛光与主世界同参（ACES 0.92 / contrast 1.06 / saturation 1.18 /
	# glow 0.5）：枪像素走同一条渲染管线，合成进画面不显「贴片感」。
	var vm_env := Environment.new()
	vm_env.background_mode = Environment.BG_COLOR
	vm_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	vm_env.tonemap_exposure = 0.92
	vm_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	vm_env.ambient_light_color = Color(0.6, 0.57, 0.5)   # 中性暖灰，同主世界 ambient 色
	vm_env.ambient_light_energy = 0.58                   # 同 HDWorld.OUTDOOR_AMB 档
	vm_env.adjustment_enabled = true
	vm_env.adjustment_brightness = 1.0
	vm_env.adjustment_contrast = 1.06
	vm_env.adjustment_saturation = 1.18
	vm_env.glow_enabled = true          # 枪口火光片的泛光观感与世界一致
	vm_env.glow_intensity = 0.5
	vm_env.glow_hdr_threshold = 1.05
	var vm_we := WorldEnvironment.new()
	vm_we.environment = vm_env
	vm_viewport.add_child(vm_we)
	var vm_sun := DirectionalLight3D.new()
	vm_sun.light_color = Color(1.0, 0.96, 0.9)   # 同主世界太阳暖白
	vm_sun.light_energy = VM_SUN_ENERGY
	# 挂 vm_cam 下：transform 随相机走（跟随相机），相对枪的受光方向恒定
	vm_sun.rotation_degrees = Vector3(-40.0, 25.0, 0.0)
	vm_sun.shadow_enabled = false
	vm_cam.add_child(vm_sun)
	# 合成层：全屏 TextureRect 直贴 vm 画面。mouse_filter 必须 IGNORE——
	# 否则整屏 Control 以 STOP 吃掉鼠标位移事件，_unhandled_input 的视角
	# 链当场锁死（全屏 UI 吃输入是本方案唯一的交互陷阱）
	vm_layer = CanvasLayer.new()
	vm_layer.layer = VM_LAYER
	add_child(vm_layer)
	var rect := TextureRect.new()
	rect.texture = vm_viewport.get_texture()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_layer.add_child(rect)
	# resize 跟随：子视口尺寸钉住主视口，合成恒 1:1 不拉伸不裁切
	main_vp.size_changed.connect(func() -> void:
		if vm_viewport != null and main_vp != null:
			vm_viewport.size = main_vp.size
	)


## vm 相机同步：transform/FOV/裁剪面逐帧拷贝主相机。这条不变量是全链
## 「数学不变」的地基——vm 相机 transform == 主相机 transform 时，holder
## 在 vm 世界的 to_global 数值 == 主世界坐标（曳光起点 muzzle_world、掉匣
## 落点 _drop_mag、换弹手锚 mag.to_global 全部零改动照旧成立）
func sync_vm() -> void:
	if cam == null or vm_cam == null:
		return
	vm_cam.global_transform = cam.global_transform
	vm_cam.fov = cam.fov
	vm_cam.near = cam.near
	vm_cam.far = cam.far


## 渲染发生在全部 _process 之后：这里兜底同步，保证主循环不跑 update 的
## 帧（大厅/暂停/探针 set_process(false) 冻结摆拍直改 cam）vm 相机也钉住
## 主相机最新摆位——探针截图协议（冻结后直改 cam.position/rotation 再拍）
## 因此零改动照跑
func _process(_delta: float) -> void:
	sync_vm()


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
	lean = 0.0
	lean_cur = 0.0
	pitch = 0.0
	_eye_h = EYE_H
	_speed = 0.0
	if cam != null:
		cam.position = pos + Vector3(0, EYE_H, 0)
		cam.rotation = Vector3(pitch, yaw + PI, 0)
		cam.fov = BASE_FOV
		sync_vm()   # 出生摆位即刻进 vm 相机：首帧渲染不等 _process 兜底


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
	# 探头（Q/E 按住，疾跑时收头）：目标 ±1，lean_cur 平滑过渡（≈0.17s）
	var lean_t := 0.0
	if not sprinting:
		if Input.is_action_pressed("hd_lean_left"):
			lean_t -= 1.0
		if Input.is_action_pressed("hd_lean_right"):
			lean_t += 1.0
	lean = lean_t
	lean_cur = move_toward(lean_cur, lean_t, LEAN_SPEED * dt)
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
		pos.y = _world.ground_height(pos.x, pos.z, pos.y)
	# 图边界（HDData：340m 见方）。地图外独立空间（靶馆，e515451 迁 (600,600)）
	# 必须豁免：钳制曾把馆内出生的玩家每帧拽回地图角 (170,·,170)、相机跟飞
	# ——靶馆室内景永远看不见（复验「幽灵活影+黑屏」的根因，诊断 diag 实证
	# 出生第 0 帧即被拽走）。馆体是封闭空间（四墙=障碍推出），独立空间内
	# 不跑地图钳制也出不了世界；实战出生在图内，钳制照常兜底防走出图
	var in_separate: bool = _world != null \
			and _world.has_method("in_separate_space") \
			and _world.in_separate_space(pos)
	if not in_separate:
		pos.x = clampf(pos.x, -HDData.MAP_HALF, HDData.MAP_HALF)
		pos.z = clampf(pos.z, -HDData.MAP_HALF, HDData.MAP_HALF)
	# 相机：眼高（蹲 0.95）+ 走动轻微点头
	var eye_target := EYE_H_CROUCH if crouching else EYE_H
	_eye_h = lerpf(_eye_h, eye_target, 1.0 - exp(-14.0 * dt))
	var bob := sin(_bob_t) * 0.02 * minf(_speed, 1.0)
	# 相机：眼高（蹲 0.95）+ 走动轻微点头 + 探头侧移/压肩（沿屏幕右向量）
	var lean_right := Vector3(-cos(yaw), 0, sin(yaw))
	cam.position = pos + Vector3(0, _eye_h + bob - absf(lean_cur) * LEAN_EYE_DROP, 0) \
			+ lean_right * (lean_cur * LEAN_OFF)
	# 后坐回落：停火 0.25s 后每秒 45° 压回，水平漂移同步归零，上限 6°
	recoil_cool += dt
	if recoil_cool > 0.25:
		recoil_pitch = maxf(0.0, recoil_pitch - deg_to_rad(RECOIL_FALL) * dt)
		recoil_yaw = move_toward(recoil_yaw, 0.0, deg_to_rad(RECOIL_YAW_FALL) * dt)
	recoil_pitch = minf(recoil_pitch, deg_to_rad(RECOIL_MAX))
	# 侧滚符号：右探头头向右歪 = 绕 +Z 负转（+Y 倒向 +X），地平线在视野里左高右低
	cam.rotation = Vector3(pitch + recoil_pitch, yaw + recoil_yaw + PI,
			-deg_to_rad(LEAN_ROLL) * lean_cur)
	cam.fov = lerpf(cam.fov, BASE_FOV / maxf(zoom, 1.0), 1.0 - exp(-14.0 * dt))
	# 摆位落定即同步 vm 相机：main 同帧随后就跑 guns.update（try_fire 的
	# 曳光起点/掉匣落点读 holder.to_global），不等引擎 _process 兜底，
	# 快速甩视角也不出一帧滞后
	sync_vm()


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
