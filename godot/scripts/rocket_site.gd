class_name RocketSite
extends Node3D
## 「RR 快舟」发射状态机（结构与班机乘坐链 airport_traffic._update_ride 同构）：
## idle（立台上）→ countdown（T-10 播报/脐带臂摆开/地灯逐盏）→ ignition（夹持攒势
## 1.2s 后释放）→ climb（垂直爬升 + 重力转弯）→ stage2（MECO 一级分离 + 二级点火）
## → orbit（太空巡航：入轨默认自动导航飞月球，任意行驶键接管手动，F 出舱 EVA，
## V 切自动驾驶，B 快速返场）→ moon_descent（距月面 <400m 自动垂直缓降）
## → moon_landed（F 下舱月面低重力行走）→ moon_liftoff（回船自动起飞离月）
## → orbit 自动导航返航 → descent（发射坪上空 400m 转垂直）→ pad_landed（F 下舱）。
## 乘船全程第三人称追尾视角（见 camera_pose）。防卡死总闸：任何相位 Esc 走
## game.exit_roam 的 rocket 复位链；本类不持久化任何状态。

const PAD_C := Vector2(1700.0, 0.0)        # 发射坪中心（沙漠环线围合中心）
const PAD_TOP := Vector3(1700.0, 2.55, 0.0) # 火箭基座世界位（发射台顶面）
const DOOR_POS := Vector3(1700.0, 2.55, 9.5) # 登船口（发射台南侧平台）
const CLIMB_HEADING := 0.93                # 重力转弯朝向（月方位角 atan2(3500,2600)）
const KARMAN_Y := 3500.0                   # 出大气阈值（与 space_f 混合区间衔接）
const CRUISE_VMAX := 80.0
const MOON_ABOVE := Vector3(5200.0, 5900.0, 2600.0)  # 月面着陆坪上方进近点
const MOON_TOP := Vector3(5200.0, 5600.0, 2600.0)    # 静海基地坪面（= 月心+半径）
const PAD_ABOVE := Vector3(1700.0, 360.0, 0.0)       # 发射坪上空进近点（< 捕获半径 400：
                                                     # 否则自动驾驶绕目标盘旋永不转下降）
const MOON_G := 1.62

var phase := "idle"
var vis: RocketVisual
var game = null                  # game 注入（enter_roam 时；bake 时为 null）
var fm = null                    # FreeroamMap 弱引用（moon_query 总闸）

var t := 0.0                     # 相位计时
var count_t := 0.0               # 倒计时剩余（秒）
var last_sec := -1               # 已播报的整秒（防重复）
var pos := PAD_TOP               # 火箭基座世界坐标
var heading := 0.0
var pitch := PI * 0.5            # 与水平面夹角（PI/2 = 垂直）
var speed := 0.0
var target_speed := 60.0         # 巡航目标速度（W/S 调）
var eva := false                 # 出舱漂浮中（phase 仍为 orbit）
var autopilot := false
var auto_target := Vector3.ZERO  # 自动驾驶目标（月球进近点 / 发射坪进近点）
var auto_kind := ""              # "moon" / "home"
var board_hold := 0.0            # EVA 长按 F 磁力回收计时
var warn_cd := 0.0               # 远离飞船警告节流
var _plasma := false             # 再入等离子尾焰（纯视觉）


func build(map_ref) -> void:
	fm = map_ref
	vis = RocketVisual.new()
	vis.name = "RocketVisual"
	add_child(vis)
	vis.build_site(PAD_TOP - Vector3(0, 2.55, 0), DOOR_POS)
	vis.build_moon(FreeroamMap.MOON_C, FreeroamMap.MOON_R)
	_apply_rocket_transform()


# ===================== 查询接口（game / 测试用） =====================

## 登船口判定（半径 10.0m——对齐 airport_traffic.near_service_door 实测口径）
func near_board_door(p: Vector3) -> bool:
	return p.distance_to(DOOR_POS) < 10.0


## 月面 / 轨道上舱门判定（火箭当前姿态下的南舱门）
func near_airlock(p: Vector3) -> bool:
	return p.distance_to(local_to_world(Vector3(0, 1.6, 5.5))) < 10.0


func rocket_pos() -> Vector3:
	return pos


## 月球淡入淡出协议转发（评审⑨）：game 每帧驱动
func set_moon_fade(f: float) -> void:
	if vis != null:
		vis.set_moon_fade(f)


func rocket_speed() -> float:
	return speed


func rumble_active() -> bool:
	return phase in ["ignition", "countdown"] and count_t < 3.0


func rumble_mag() -> float:
	match phase:
		"ignition":
			return 90.0
		"countdown":
			return clampf((3.0 - count_t) / 3.0, 0.0, 1.0) * 40.0
		"climb":
			return clampf(speed, 0.0, 90.0)
		_:
			return speed * 0.4


func local_to_world(v: Vector3) -> Vector3:
	if vis == null or vis.rocket == null:
		return pos + v
	return vis.rocket.global_transform * v


# ===================== F 交互（挂在 rr_interact 链最前） =====================

## 返回 true = 已消费（链上后续分支与链尾上下车兜底都不再吃这记 F——
## 太空/月面弹「离车辆太远」出戏的问题由此根治）
func handle_interact(g) -> bool:
	if phase == "idle":
		if g.on_foot and near_board_door(g.onfoot.pos):
			_board(g)
			return true
		return false   # 台下随意的 F 留给下车等既有交互
	match phase:
		"countdown":
			# 再按 F = 中止发射：火箭复位台上回 idle，玩家放回登船口步行态
			# （rocket_ride 必须在这里摘掉——否则人挂在已复位的火箭上再也接不上 F）
			reset_launch()
			g.rocket_ride = false
			g.hud.set_plane_panel(false)
			g.on_foot = true
			g.camera.near = 0.02
			g.onfoot.set_gun(g.gun_equipped)
			onfoot_enter_ground(g, DOOR_POS + Vector3(0, 0.2, 2.5), PI)
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			g.hud.set_onfoot(true)
			g.hud.set_health(g.player_hp)
			g.hud.show_center("发射中止", "火箭已复位 · 稍候可重新登乘", 2200)
			return true
		"orbit":
			if g.on_foot:
				# 出舱 EVA / 被月面引力捕获的行走者：近舱门回船，否则提示
				if near_airlock(g.onfoot.pos):
					_board_from_eva(g)
				elif g.hud != null:
					g.hud.show_center("太空出舱中",
							"回舱门边按 F 回船 · 长按 F 磁力牵引回收 · B 快速返场",
							2000)
				return true
			_start_eva(g)
			return true
		"moon_landed":
			if g.on_foot:
				if near_airlock(g.onfoot.pos):
					_board(g)
					_lift_off_moon(g)
				else:
					if g.hud != null:
						g.hud.show_center("月面漫步中",
								"回登船口按 F 回船起飞 · B 快速返场", 2000)
				return true
			_moonwalk(g)
			return true
		"pad_landed":
			_exit_at_pad(g)
			return true
		_:
			# climb / stage2 / 各类 descent / liftoff：飞行中不可离舱
			if g.hud != null:
				g.hud.show_center("飞行阶段", "Esc 退出任务 · B 快速返场", 1400)
			return true
	return false


func _board(g) -> void:
	g.rocket_ride = true
	g.on_foot = false
	if g.onfoot != null:
		g.onfoot.exit()
	g.hud.set_onfoot(false)
	g.hud.set_scope(false)
	g.hud.set_plane_panel(true)
	phase = "countdown"
	count_t = 10.0
	last_sec = -1
	g.hud.show_center("RR 快舟 · 发射准备",
			"再按 F 中止发射 · 点火后自动导航飞往月球", 3200)


func _board_from_eva(g) -> void:
	eva = false
	g.rocket_ride = true
	g.on_foot = false
	if g.onfoot != null:
		g.onfoot.exit()
	g.hud.set_onfoot(false)
	g.hud.set_scope(false)
	g.hud.show_center("已回船", "自动导航继续 · B 快速返场", 1800)


func _start_eva(g) -> void:
	eva = true
	g.rocket_ride = false
	g.on_foot = true
	g.camera.near = 0.02
	g.onfoot.set_gun(g.gun_equipped)
	g.onfoot.enter(local_to_world(Vector3(0, 44.0, 6.0)), heading + PI)
	g.onfoot.gravity_mode = "zero"
	g.onfoot.eva_vel = Vector3.ZERO
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	g.hud.set_onfoot(true)
	g.hud.set_health(g.player_hp)
	g.hud.show_center("太空出舱（失重）",
			"WASD 视线推进 · Space 升 Q 降 · R 制动 · 松手不停 · F 回船", 4200)


func _moonwalk(g) -> void:
	g.rocket_ride = false
	g.on_foot = true
	g.camera.near = 0.02
	g.onfoot.set_gun(g.gun_equipped)
	g.onfoot.enter(local_to_world(Vector3(0, 1.2, 7.0)), heading + PI)
	g.onfoot.gravity_mode = "moon"
	g.onfoot.vy = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	g.hud.set_onfoot(true)
	g.hud.set_health(g.player_hp)
	g.hud.show_center("月面·静海基地（1/6 重力）",
			"空格跳 5.4m 高 · 滞空 5 秒 · 回登船口按 F 起飞返航", 4200)


func _exit_at_pad(g) -> void:
	g.rocket_ride = false
	g.on_foot = true
	g.camera.near = 0.02
	g.onfoot.set_gun(g.gun_equipped)
	onfoot_enter_ground(g, DOOR_POS + Vector3(0, 0.2, 2.5), PI)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	g.hud.set_onfoot(true)
	g.hud.set_health(g.player_hp)
	g.hud.set_plane_panel(false)
	phase = "idle"
	g.hud.show_center("欢迎回到地球", "RR 航天发射场 · 任务完成", 3000)


## 地面态进入 onfoot（gravity_mode 一定为空——enter() 复位清单兜底，评审②）
func onfoot_enter_ground(g, at: Vector3, head: float) -> void:
	g.onfoot.enter(at, head)
	g.onfoot.gravity_mode = ""
	g.onfoot.vy = 0.0
	g.onfoot.eva_vel = Vector3.ZERO


# ===================== V / B =====================

func toggle_autopilot(g) -> void:
	if not phase in ["orbit", "moon_landed"]:
		if g.hud != null:
			g.hud.show_center("当前相位不可自动驾驶", "", 1200)
		return
	if phase == "moon_landed" and not g.on_foot:
		# 月面上：V = 回船起飞返航
		_board(g)
		_lift_off_moon(g)
		autopilot = true
		auto_kind = "home"
		auto_target = PAD_ABOVE
		return
	autopilot = not autopilot
	if autopilot:
		# 目的地：离月球远 → 飞月球；已近月 → 返航
		if pos.distance_to(MOON_TOP) > 1500.0:
			auto_kind = "moon"
			auto_target = MOON_ABOVE
			g.hud.show_center("自动驾驶 · 地月转移", "机头已对准月球 · 任意键接管", 2600)
		else:
			auto_kind = "home"
			auto_target = PAD_ABOVE
			g.hud.show_center("自动驾驶 · 返航", "机头已对准发射场 · 任意键接管", 2600)
	else:
		g.hud.show_center("已恢复手动驾驶", "", 1200)


## B 快速返场：任意相位直接回发射坪边步行态（防卡死兜底捷径）
func quick_return(g) -> void:
	reset_launch()
	g.rocket_ride = false
	if g.on_foot:
		g.onfoot.exit()
	g.on_foot = true
	g.camera.near = 0.02
	g.onfoot.set_gun(g.gun_equipped)
	onfoot_enter_ground(g, DOOR_POS + Vector3(0, 0.2, 2.5), PI)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	g.hud.set_onfoot(true)
	g.hud.set_health(g.player_hp)
	g.hud.set_plane_panel(false)
	g.hud.show_center("快速返场", "已回到 RR 航天发射场", 2400)


# ===================== 复位（防卡死总闸） =====================

func reset_launch() -> void:
	phase = "idle"
	t = 0.0
	count_t = 0.0
	last_sec = -1
	pos = PAD_TOP
	heading = 0.0
	pitch = PI * 0.5
	speed = 0.0
	target_speed = 60.0
	eva = false
	autopilot = false
	auto_kind = ""
	board_hold = 0.0
	warn_cd = 0.0
	_plasma = false
	if vis != null:
		vis.set_throttle(0.0)
		vis.set_arms_open(0.0)
		vis.set_pad_lights(0.0)
		vis.set_smoke(false)
		vis.restore_stage1()
	if fm != null:
		fm.moon_query = false
	_apply_rocket_transform()


# ===================== 主推进 =====================

func _update(h: float) -> void:
	t += h
	match phase:
		"idle":
			return
		"countdown":
			_step_countdown(h)
		"ignition":
			_step_ignition(h)
		"climb":
			_step_climb(h)
		"stage2":
			_step_stage2(h)
		"orbit":
			_step_orbit(h)
		"moon_descent":
			_step_descent(h, MOON_TOP, "moon_landed", true)
		"moon_landed":
			_step_landed(h)
		"moon_liftoff":
			_step_moon_liftoff(h)
		"descent":
			_step_descent(h, PAD_TOP, "pad_landed", false)
		"pad_landed":
			_step_landed(h)
	_apply_rocket_transform()
	# moon_query 总闸：只有太空相位（含 EVA/月面行走）为真——战机/地面一切
	# 时刻为假，飞穿月轴坐标也不会被月面覆写劫持
	if fm != null:
		fm.moon_query = phase in ["stage2", "orbit", "moon_descent",
				"moon_landed", "moon_liftoff"]


func _msg(title: String, sub: String, ms := 2400.0) -> void:
	if game != null and game.hud != null:
		game.hud.show_center(title, sub, ms)


func _step_countdown(h: float) -> void:
	count_t -= h
	# 播报（每整秒大字：10…3、2、1、点火）
	var sec := int(ceil(count_t))
	if sec != last_sec and sec >= 0:
		last_sec = sec
		if game != null and game.hud != null:
			game.hud.countdown(str(sec) if sec > 0 else "点火")
	# T-10~T-6：脐带臂回转摆开（约 2s 动画）+ 坪周地灯逐盏点亮
	var arm_f := clampf((10.0 - count_t - 3.0) / 4.0, 0.0, 1.0)
	vis.set_arms_open(arm_f)
	vis.set_pad_lights(clampf((10.0 - count_t) / 8.5, 0.0, 1.0))
	if count_t <= 0.0:
		phase = "ignition"
		t = 0.0
		vis.set_throttle(1.0)
		vis.set_smoke(true)
		if game != null:
			game.shake = 0.8
		_msg("点火", "RR 快舟 · 主引擎全推力", 1800)


func _step_ignition(h: float) -> void:
	# 夹持攒势 1.2s（尾焰全开 + rumble 拉满），随后 release
	if game != null:
		game.shake = maxf(game.shake, 0.55)
	if t >= 1.2:
		phase = "climb"
		t = 0.0
		speed = 4.0
		heading = CLIMB_HEADING
		pitch = PI * 0.5
		_msg("升空", "重力转弯朝月球方向 · 全城正在目送", 2200)


func _step_climb(h: float) -> void:
	var acc := 7.0 if speed < 200.0 else 4.0
	speed = minf(speed + acc * h, 240.0)
	# 800m 起重力转弯：pitch 从 90° 缓压到 60°（1200m 过渡带）
	var turn := clampf((pos.y - 800.0) / 1200.0, 0.0, 1.0)
	pitch = lerpf(PI * 0.5, PI / 3.0, turn)
	pos += _fwd() * speed * h
	if game != null:
		game.shake = maxf(game.shake, clampf(0.5 - pos.y / 2000.0, 0.06, 0.5))
	if pos.y > 120.0:
		vis.set_smoke(false)
	if pos.y > KARMAN_Y:
		phase = "stage2"
		t = 0.0
		speed = minf(speed, 160.0)
		vis.set_throttle(0.0)
		vis.detach_stage(-_fwd() * 12.0 + Vector3(0, -6.0, 0))
		_msg("MECO · 一级分离", "二级点火 · 准备进入巡航", 2600)


func _step_stage2(h: float) -> void:
	speed = move_toward(speed, target_speed, 30.0 * h)
	vis.set_throttle(0.6)
	pos += _fwd() * speed * h
	if t >= 2.2:
		phase = "orbit"
		t = 0.0
		# 入轨默认自动导航：登乘后不碰任何键也能一路飞到月面（任意行驶键接管）
		autopilot = true
		auto_kind = "moon"
		auto_target = MOON_ABOVE
		_msg("已进入太空 · 自动导航",
				"正飞往月球静海基地 · 任意方向键接管手动 · F 出舱 · B 快速返场", 4200)


func _step_orbit(h: float) -> void:
	# ---- EVA / 月面行走期间：船体泊定，只跑兜底逻辑（评审遗留修复）----
	if game != null and game.on_foot:
		_step_companion(h)
		return
	# ---- 手动巡航（自动驾驶接管时跳过；任意输入立即交还）----
	if autopilot:
		_autopilot_steer(h)
		if Input.is_physical_key_pressed(KEY_W) \
				or Input.is_physical_key_pressed(KEY_S) \
				or Input.is_physical_key_pressed(KEY_A) \
				or Input.is_physical_key_pressed(KEY_D) \
				or Input.is_physical_key_pressed(KEY_UP) \
				or Input.is_physical_key_pressed(KEY_DOWN):
			autopilot = false
			_msg("已恢复手动驾驶", "", 1200)
	else:
		if Input.is_physical_key_pressed(KEY_W):
			target_speed = minf(target_speed + 26.0 * h, CRUISE_VMAX)
		if Input.is_physical_key_pressed(KEY_S):
			target_speed = maxf(target_speed - 26.0 * h, 0.0)
		var turn := 0.0
		if Input.is_physical_key_pressed(KEY_A) \
				or Input.is_physical_key_pressed(KEY_LEFT):
			turn += 1.0
		if Input.is_physical_key_pressed(KEY_D) \
				or Input.is_physical_key_pressed(KEY_RIGHT):
			turn -= 1.0
		heading += turn * 0.85 * h
		var pitch_in := 0.0
		if Input.is_physical_key_pressed(KEY_UP):
			pitch_in -= 1.0
		if Input.is_physical_key_pressed(KEY_DOWN):
			pitch_in += 1.0
		if pitch_in != 0.0:
			pitch = clampf(pitch + pitch_in * 0.6 * h, -0.5, 1.2)
	speed = move_toward(speed, target_speed, 22.0 * h)
	pos += _fwd() * speed * h
	_bounds()
	# 再入等离子尾焰：速度 >60 且已压回大气层（纯视觉）
	var plasma_now := speed > 60.0 and pos.y < 3800.0 and pos.y > 200.0
	if plasma_now != _plasma:
		_plasma = plasma_now
		if plasma_now:
			_msg("再入大气层", "船体表面等离子辉光 · 请欣赏", 2400)
	vis.set_throttle(0.7 if _plasma else clampf(speed / CRUISE_VMAX * 0.3, 0.0, 0.3))
	if game != null and _plasma:
		game.shake = maxf(game.shake, 0.18)
	# 自动/手动着陆触发（进近点必须落在捕获半径内，否则到点不转下降）
	if pos.distance_to(MOON_TOP) < 400.0:
		phase = "moon_descent"
		t = 0.0
		autopilot = false
		_msg("月球自动着陆", "垂直缓降 · 静海基地", 2600)
	elif pos.distance_to(PAD_TOP) < 400.0 and pos.y < 620.0:
		phase = "descent"
		t = 0.0
		autopilot = false
		_msg("发射场自动着陆", "垂直缓降 · 发射坪", 2600)


## 自动驾驶：机头对准目标；到达进近点交由 descent 相位接管。返回是否仍在自动
func _autopilot_steer(h: float) -> bool:
	var to := auto_target - pos
	var want_h := atan2(to.x, to.z)
	heading += clampf(wrapf(want_h - heading, -PI, PI), -0.5, 0.5) * 1.1 * h
	var horiz := Vector2(to.x, to.z).length()
	var want_p := clampf(atan2(to.y, maxf(horiz, 40.0)), -0.5, 1.2)
	pitch += clampf(want_p - pitch, -0.4, 0.4) * 1.2 * h
	target_speed = CRUISE_VMAX if to.length() > 900.0 else 46.0
	return true


## 出舱 / 月面行走时的船上兜底：远离警告 + 长按 F 磁力回收 + 月面引力捕获
func _step_companion(h: float) -> void:
	var of = game.onfoot
	var d: float = of.pos.distance_to(local_to_world(Vector3(0, 44.0, 4.0)))
	warn_cd = maxf(0.0, warn_cd - h)
	if d > 150.0 and warn_cd <= 0.0:
		warn_cd = 5.0
		_msg("⚠ 远离飞船 %d m" % int(d), "长按 F 1 秒 · 磁力牵引回收", 2600)
	# 长按 F 磁力牵引（短按 F 的提示/回船走 handle_interact）
	if Input.is_physical_key_pressed(KEY_F):
		board_hold += h
		if board_hold >= 1.0 and d > 12.0:
			board_hold = 0.0
			of.pos = local_to_world(Vector3(0, 44.0, 8.0))
			of.eva_vel = Vector3.ZERO
			_msg("磁力牵引回收完成", "已拉回舱门边", 2000)
	else:
		board_hold = 0.0
	# EVA 飘近月面：query 自动接管切月面模式（两种手感无缝过渡）
	if of.gravity_mode == "zero" and fm != null:
		var mdx: float = of.pos.x - FreeroamMap.MOON_C.x
		var mdz: float = of.pos.z - FreeroamMap.MOON_C.z
		var md2: float = mdx * mdx + mdz * mdz
		if md2 < FreeroamMap.MOON_R * FreeroamMap.MOON_R:
			var dome: float = FreeroamMap.MOON_C.y \
					+ sqrt(maxf(FreeroamMap.MOON_R * FreeroamMap.MOON_R - md2, 0.0))
			if of.pos.y < dome + 1.2:
				of.gravity_mode = "moon"
				of.vy = 0.0
				of.pos.y = maxf(of.pos.y, dome)
				_msg("已捕获月面引力", "低重力行走模式 · 1/6 g", 2200)


## 垂直缓降（机场 descend/rollout 两段减速写法）：水平对准 + 25→1.5 m/s
func _step_descent(h: float, target: Vector3, next_phase: String, is_moon: bool) -> void:
	pos.x = move_toward(pos.x, target.x, 22.0 * h)
	pos.z = move_toward(pos.z, target.z, 22.0 * h)
	var dy := pos.y - target.y
	var rate: float
	if dy > 60.0:
		rate = 25.0
	else:
		rate = lerpf(1.5, 25.0, clampf((dy - 2.0) / 58.0, 0.0, 1.0))
	var prev_y := pos.y
	pos.y = move_toward(pos.y, target.y, rate * h)
	pitch = move_toward(pitch, PI * 0.5, 0.35 * h)   # 视觉转垂直
	speed = absf(pos.y - prev_y) / h
	vis.set_throttle(0.25 if is_moon else 0.3)
	if absf(pos.y - target.y) < 0.5:
		# 触地（超速硬着陆只弹提示不毁船）
		var v_impact := absf(prev_y - target.y) / h
		pos.y = target.y
		phase = next_phase
		t = 0.0
		pitch = PI * 0.5
		speed = 0.0
		target_speed = 60.0
		vis.set_throttle(0.0)
		if is_moon:
			vis.moon_dust_burst()
			_msg("着陆月球 · 静海基地",
					("F 下舱月面行走 · V 起飞返航 · B 快速返场" if v_impact < 3.0
					else "硬着陆！结构经受住了考验 · F 下舱"), 4200)
		else:
			_msg("返回发射场", "F 下舱 · 欢迎回家", 3600)
		if game != null:
			game.shake = maxf(game.shake, 0.35)


func _step_landed(h: float) -> void:
	# 停在坪上：只维持灯效与月面引力捕获（月面行走也走 _step_companion）
	if game != null and game.on_foot:
		_step_companion(h)


func _lift_off_moon(g) -> void:
	phase = "moon_liftoff"
	t = 0.0
	speed = 3.0
	pitch = PI * 0.5
	vis.set_throttle(1.0)
	g.hud.show_center("月面起飞", "1/6 重力 · 轻松离月", 2200)


func _step_moon_liftoff(h: float) -> void:
	speed = minf(speed + 8.0 * h, 70.0)
	pos += Vector3.UP * speed * h
	# 出口高度必须超过 orbit 相位的月面捕获半径（400m），否则一到巡航就被
	# moon_descent 重新抓住，无限升降循环
	if pos.y > MOON_TOP.y + 460.0:
		phase = "orbit"
		t = 0.0
		target_speed = 60.0
		speed = 40.0
		heading = atan2(PAD_TOP.x - pos.x, PAD_TOP.z - pos.z)
		pitch = 0.25
		autopilot = true
		auto_kind = "home"
		auto_target = PAD_ABOVE
		_msg("回到太空巡航 · 自动导航返航", "任意方向键接管手动 · B 快速返场", 3000)


# ===================== 视觉 / HUD 应用 =====================

## 相机机位（全程第三人称）：点火起外置慢环绕 ~3s 看全箭体与发射场，随后
## 1.8s 平滑并入刚性追尾机位（机头反方向 82m 抬 24m 看向箭体前上方）。
## 机位每帧由公式直接求值——不是 lerp 追逐，高速爬升不会甩尾；追尾俯仰
## 限幅 [-14°, 38°] 保证低空不把镜头压进地面，另以地形高度兜底（月面
## 起飞/着陆瞬间镜头不钻进月壤）。返回 [机位世界坐标, 注视点]
func camera_pose() -> Array:
	# 环绕段计时：点火 1.2s + 爬升段接力（相位切换 t 归零，补 1.2 基数连续转）
	var ot := t if phase == "ignition" else 1.2 + t
	var ang := ot * 0.7 + 0.6
	var orb_c := pos + Vector3(cos(ang) * 130.0, 62.0, sin(ang) * 130.0)
	var orb_l := pos + Vector3(0, 34.0, 0)
	# 刚性追尾：机头反方向后上方；俯仰限幅后 back 永不垂直，look_at 不退化
	var pitch_cam := clampf(pitch, -0.25, 0.66)
	var back := Vector3(cos(pitch_cam) * sin(heading), sin(pitch_cam),
			cos(pitch_cam) * cos(heading))
	var eye := pos - back * 82.0 + Vector3(0, 24.0, 0)
	var look := pos + Vector3(0, 42.0, 0) + back * 24.0   # 注视点抬高：巡航时月球进入画面上半
	if fm != null:
		# 地形兜底：垂直姿态近距离月面/地面时，镜头可能算到表面以下
		var fl: Dictionary = fm.query(pos.x, pos.z, null, pos.y)
		var fy: float = float(fl["height"]) + 8.0
		if eye.y < fy:
			eye.y = fy
	if phase == "ignition" or (phase == "climb" and ot < 3.0):
		return [orb_c, orb_l]
	if phase == "climb" and ot < 4.8:
		# 环绕 → 追尾并轨（两者都是逐帧确定值，直接混合无滞后）
		var k := smoothstep(0.0, 1.0, (ot - 3.0) / 1.8)
		return [orb_c.lerp(eye, k), orb_l.lerp(look, k)]
	return [eye, look]


func _apply_rocket_transform() -> void:
	if vis == null or vis.rocket == null:
		return
	vis.rocket.position = pos
	vis.rocket.rotation = Vector3(PI * 0.5 - pitch, heading, 0.0)


func _fwd() -> Vector3:
	return Vector3(cos(pitch) * sin(heading), sin(pitch), cos(pitch) * cos(heading))


## 太空软边界：y 上限 8000（float32 漂移防护），水平 ±16000（WORLD_LIMIT）
func _bounds() -> void:
	if pos.y > 8000.0:
		pos.y = 8000.0
		pitch = minf(pitch, 0.0)
	pos.x = clampf(pos.x, -FreeroamMap.WORLD_LIMIT, FreeroamMap.WORLD_LIMIT)
	pos.z = clampf(pos.z, -FreeroamMap.WORLD_LIMIT, FreeroamMap.WORLD_LIMIT)
	# 不可钻地：贴各天体表面外推
	if fm != null:
		var q: Dictionary = fm.query(pos.x, pos.z, null, pos.y)
		var floor_y: float = float(q["height"]) + 4.0
		if pos.y < floor_y and floor_y < 4800.0:
			pos.y = floor_y
			pitch = maxf(pitch, 0.0)


## 泛光灯（夜间开）+ 环境维护（game._process 每帧调；与相位机无关）
func update_ambient(night_f: float, _dt: float) -> void:
	if vis == null:
		return
	for sp in vis.floodlights:
		sp.light_energy = lerpf(sp.light_energy,
				2.6 if night_f > 0.45 else 0.0, 0.05)


## 火箭 HUD（复用战机仪表盘通道）
func update_hud(hud, _now_s: float) -> void:
	var hdg := fposmod(540.0 - rad_to_deg(heading), 360.0)
	var vs := 0.0
	if phase in ["climb", "stage2", "moon_liftoff"]:
		vs = speed * sin(pitch)
	elif phase in ["moon_descent", "descent"]:
		vs = -speed
	var thr := 1.0 if phase in ["ignition", "climb"] \
			else clampf(speed / CRUISE_VMAX * 0.5, 0.0, 0.5)
	var rpm := 0.12 + 0.88 * thr if phase in ["ignition", "climb", "stage2"] \
			else clampf(speed / CRUISE_VMAX, 0.0, 1.0) * 0.6
	var landed := phase in ["moon_landed", "pad_landed"]
	hud.update_plane_panel(speed * 3.6, pos.y, vs, hdg,
			PI * 0.5 - pitch, 0.0, thr, rpm, landed)
