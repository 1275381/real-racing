class_name Vehicle
extends RefCounted
## 车辆动力学（街机拟真折中）：
## 前向/侧向速度分离，转向按运动学目标横摆 + 漂移辅助混合，
## 抓地衰减侧滑；路面摩擦系数随柏油/路肩/草地变化；护栏为软墙反弹。
## （逐行移植自 js/physics.js）

const GEAR_KMH := [0.0, 40.0, 76.0, 114.0, 154.0, 198.0, 246.0, 288.0]   # 各档下限(km/h)，末档边界须低于实际极速，否则换挡切断会在边界振荡
const WHEELBASE := 2.62

var track               # RaceTrack 或 FreeroamMap（鸭子类型：query/n/ds/start_idx/...）
var is_player := false
var grip_scale := 1.0             # AI 技能同时缩放动力与抓地
var top_speed := 92.0             # m/s（硬顶 ~331km/h，空气阻力下实际极速 ≈ 300km/h）
var power := 60.0                 # 低速最大加速度基准（实际受抓地牵引上限约束）
var brake_power := 18.0           # 制动减速度基准 (m/s²)
var accel_cap := 11.0             # 牵引上限 (m/s²)：抓地能给的起步加速度
var no_shift := false             # 电驱单速变速箱：无换挡切断，起步线性猛
var drag_k2 := 7.5e-4             # 空气阻力二次项系数（按极速标定：极速处风阻=牵引上限）

var pos := Vector3.ZERO
var heading := 0.0
var vf := 0.0                     # 车头方向速度
var vl := 0.0                     # 左向速度
var yaw_rate := 0.0
var steer_vis := 0.0
var wheel_spin_angle := 0.0

var input_throttle := 0.0
var input_brake := 0.0
var input_steer := 0.0
var input_handbrake := false

var surface := "road"
var q_idx = null                  # int 或 null
var lat_off := 0.0
var seg_ang := 0.0
var drifting := false
var slip_amount := 0.0
var hit_impulse := 0.0            # >0 表示本步撞墙强度
var g_long := 0.0
var g_lat := 0.0
var _vf_prev := 0.0
var engine_load_smoothed := 0.0

# 圈程与进度（连续索引计数）
var q_prev_idx = null
var cont_idx := 0.0
var last_floor := 0
var laps_done := 0
var on_lap_complete: Callable = Callable()
var finished := false
var wrong_way_timer := 0.0

var gear := 1
var rpm_norm := 0.12
var shift_timer := 0.0
var speed_kmh := 0.0

# 立体物理：垂直速度 / 接地状态 / 落地冲击 / 当前坡度沿行进方向的分量
var vy := 0.0
var grounded := true
var land_impact := 0.0
var ground_slope_along := 0.0
var dbg_drive := 0.0      # 调试：上一步的驱动力/阻力
var dbg_decel := 0.0
var dbg_curve := 0.0


func _init(trk, opts: Dictionary = {}) -> void:
	track = trk
	is_player = opts.get("is_player", false)
	grip_scale = opts.get("grip_scale", 1.0)
	top_speed = opts.get("top_speed", 92.0)
	power = opts.get("power", 60.0)
	brake_power = opts.get("brake", 18.0)
	accel_cap = opts.get("accel_cap", 11.0)
	no_shift = opts.get("no_shift", false)
	_recalc_drag()


## 运行时套用一组性能数值（双模车的模式切换）：
## top 极速 / power 功率 / accel 牵引上限 / grip 抓地倍率 / brake 制动
func apply_stats(st: Dictionary) -> void:
	top_speed = st.get("top", top_speed)
	power = st.get("power", power)
	accel_cap = st.get("accel", accel_cap)
	grip_scale = st.get("grip", grip_scale)
	brake_power = st.get("brake", brake_power)
	_recalc_drag()


## 风阻按极速标定：牵引上限与风阻在 top_speed 处平衡 → 极速严格等于 stats
func _recalc_drag() -> void:
	drag_k2 = maxf((grip_scale * accel_cap - 0.09 * top_speed) / (top_speed * top_speed), 3.0e-4)


func place_at(pose: Dictionary) -> void:
	pos = pose["pos"]
	heading = pose["heading"]
	vf = 0.0
	vl = 0.0
	yaw_rate = 0.0
	q_idx = pose.get("idx")
	q_prev_idx = q_idx
	if q_idx != null:
		cont_idx = float(q_idx) - track.start_idx   # 位于起跑线后方 => 负值
		if cont_idx < -track.n / 2.0:
			cont_idx += track.n
	last_floor = int(floor(cont_idx / track.n))
	laps_done = 0            # 重置圈数，否则再来一局会立刻“完赛”
	wrong_way_timer = 0.0
	gear = 1
	rpm_norm = 0.12
	shift_timer = 0.0
	drifting = false
	hit_impulse = 0.0
	finished = false
	vy = 0.0
	grounded = true
	land_impact = 0.0


func step(dt: float) -> void:
	var trk = track
	var q: Dictionary = trk.query(pos.x, pos.z, q_idx)
	var tn: int = trk.n
	q_idx = q["idx"]
	lat_off = q["lat_off"]
	seg_ang = q["ang"]
	surface = q["surf"]

	# 立体物理输入：路面海拔 + 沿行进方向的坡度分量
	var ground_y: float = q.get("height", 0.0)
	ground_slope_along = q.get("slope", 0.0) * cos(heading - seg_ang)

	var spd := absf(vf)
	var surf_grip: float = {"road": 1.0, "curb": 0.92, "grass": 0.46}[surface]
	var grip := surf_grip * grip_scale * Tuning.GRIP_MUL
	var drag_mul: float = {"road": 1.0, "curb": 1.08, "grass": 3.6}[surface]

	# ---- 转向：运动学目标 + 漂移辅助 ----
	var eff_max := Tuning.STEER_MAX / (1.0 + pow(spd / Tuning.STEER_FALLOFF_SPEED,
			Tuning.STEER_FALLOFF_POW) * Tuning.STEER_FALLOFF_STR)
	var delta := input_steer * eff_max
	var yaw_t := (vf * tan(delta)) / WHEELBASE
	steer_vis = RRUtil.damp(steer_vis, delta, 12.0, dt)

	var slip_abs := absf(vl)
	var drift_blend := clampf((slip_abs - Tuning.DRIFT_THRESH) / 6.0, 0.0, 1.0)
	# 滑移态：运动学走线大幅让位给转向维持的甩尾姿态（纯转向即可起漂并保持）
	yaw_t = yaw_t * (1.0 - drift_blend * 0.80) + drift_blend * input_steer * 1.9
	yaw_rate = RRUtil.damp(yaw_rate, yaw_t, Tuning.YAW_RESPONSE, dt)
	heading += yaw_rate * dt

	# ---- 纵向 ----
	var thr_eff := input_throttle * 0.15 if shift_timer > 0.0 else input_throttle
	var traction_cap := grip * accel_cap   # 牵引上限：起步加速度（每车 stats）
	var drive := 0.0
	var reverse_intent := input_brake > 0.0 and vf < 0.6 \
			and input_throttle == 0.0 and not finished
	if input_throttle > 0.0 and vf >= -0.5 and grounded:
		var curve := maxf(0.0, 1.0 - pow(clampf(vf / top_speed, 0.0, 1.0), 2.2))
		drive = minf(power * thr_eff * curve, traction_cap)
		dbg_curve = curve
	elif reverse_intent:
		drive = -minf(6.2, traction_cap * 0.55)
	dbg_drive = drive

	var decel := 0.0
	if grounded and input_brake > 0.0 and not reverse_intent and absf(vf) > 0.3:
		decel += brake_power * grip * input_brake   # ≈1.8g 上限：制动有力但不瞬停
	if grounded and input_handbrake and absf(vf) > 0.3:
		decel += 3.8
	# 倒车中踩油门：先强力刹停，速度回正后上面的前进驱动自动接管
	if input_throttle > 0.0 and vf < -0.5:
		decel += 22.0 * grip
	var passive_drag := (0.09 * spd + drag_k2 * spd * spd) * drag_mul * (2.2 if input_handbrake else 1.0)
	decel += passive_drag
	dbg_decel = decel

	var new_vf := vf + drive * dt
	# 阻力只作用于现有运动方向
	var sgn := signf(new_vf)
	new_vf -= sgn * minf(absf(new_vf) / dt, decel) * dt
	# 重力沿坡分量：爬坡减速 / 下坡加速
	new_vf -= 9.8 * ground_slope_along * dt
	# 低速回正死区
	if absf(new_vf) < 0.14 and input_throttle == 0.0 and not reverse_intent:
		new_vf *= 0.5
	vf = new_vf
	vf = clampf(vf, -11.0, top_speed)

	# ---- 车身旋转把前向动量泄入侧向（滑移根源）----
	var eps := clampf(yaw_rate * dt, -0.16, 0.16)
	var cs := cos(eps)
	var sn := sin(eps)
	var rvf := vf * cs + vl * sn
	var rvl := vl * cs - vf * sn
	vf = rvf
	vl = rvl

	# 轮胎横向抓地（腾空时几乎无抓地）。
	# 未起漂（|vl| < 阈值）：速度矢量完全吸附车头方向 → 转弯抓地走线、零侧滑；
	# 起漂后（手刹触发，|vl| ≥ 阈值）：抓地回收降至 30% + 漂移辅助，滑移得以保持。
	var grip_rate := Tuning.GRIP_RATE * grip * (0.05 if not grounded else 1.0) \
			* (0.30 if input_handbrake else 1.0)
	if grounded and absf(vl) < Tuning.DRIFT_THRESH and not input_handbrake:
		var spd_total := sqrt(vf * vf + vl * vl)
		vf = (signf(vf) if vf != 0.0 else 1.0) * spd_total
		vl = 0.0
	else:
		vl *= exp(-grip_rate * dt)

	drifting = absf(vl) > 3.0 or (input_handbrake and spd > 9.0)
	slip_amount = RRUtil.damp(slip_amount, clampf(absf(vl) / 9.0, 0.0, 1.0), 6.0, dt)

	# ---- 世界系位移 ----
	var s := sin(heading)
	var c := cos(heading)
	var vx := s * vf + c * vl
	var vz := c * vf - s * vl
	pos.x += vx * dt
	pos.z += vz * dt

	# g 值平滑（视觉重心转移用）
	g_long = RRUtil.damp(g_long, (vf - _vf_prev) / dt / 9.81, 6.0, dt)
	g_lat = RRUtil.damp(g_lat, (yaw_rate * vf) / 9.81, 6.0, dt)
	_vf_prev = vf

	# ---- 软墙 ----
	var wall: float = q.get("wall", trk.wall_lat)
	if absf(lat_off) > wall:
		var side := signf(lat_off)
		var la := cos(q["ang"])
		var lb := -sin(q["ang"])       # 该段左向量(x,z)
		var excess := absf(lat_off) - wall
		pos.x -= la * side * excess
		pos.z -= lb * side * excess
		var world_lat_vel := vx * la + vz * lb
		if world_lat_vel * side > 0.0:
			hit_impulse = minf(1.0, absf(world_lat_vel) / 13.0)
			# 反射向内并损耗切向速度
			var tx := sin(q["ang"])
			var tz := cos(q["ang"])
			var tang_v := vx * tx + vz * tz
			tang_v *= maxf(0.62, 1.0 - absf(world_lat_vel) * 0.018)
			var lat_back := -world_lat_vel * 0.28
			var nvx := tx * tang_v + la * lat_back
			var nvz := tz * tang_v + lb * lat_back
			vf = nvx * s + nvz * c
			vl = nvx * c - nvz * s
			vx = nvx
			vz = nvz

	# ---- 进度 / 圈数 ----
	if q_prev_idx != null:
		var d := fposmod(float(q["idx"]) - float(q_prev_idx) + tn / 2.0, float(tn)) - tn / 2.0
		if absf(d) < tn / 4.0:
			cont_idx += d
		# 逆行检测
		var fwd_dot := s * sin(q["ang"]) + c * cos(q["ang"])
		if spd > 3.0 and fwd_dot < -0.25:
			wrong_way_timer += dt
		else:
			wrong_way_timer = maxf(0.0, wrong_way_timer - dt * 2.0)
		var nf := int(floor(cont_idx / tn))
		if nf > last_floor and nf >= 1:
			last_floor = nf
			laps_done = nf
			if on_lap_complete.is_valid() and not finished:
				on_lap_complete.call(nf)
	q_prev_idx = q["idx"]

	# ---- 垂直：贴地跟随 / 坡顶腾空 / 重力落地 ----
	var ground_vy: float = ground_slope_along * vf   # 路面随车移动的竖直变化率
	if grounded:
		if pos.y > ground_y + 0.4 or ground_vy < vy - 7.0:
			grounded = false        # 地面突然下沉（坡顶/断口）→ 转入腾空
		else:
			pos.y = ground_y
			vy = ground_vy
	if not grounded:
		vy -= 26.0 * dt             # 街机重力（略强于真实 G，飞跃节奏更好）
		pos.y += vy * dt
		if pos.y <= ground_y:
			land_impact = maxf(land_impact, -vy)
			pos.y = ground_y
			vy = 0.0
			grounded = true

	_update_drivetrain(dt)


func _update_drivetrain(dt: float) -> void:
	shift_timer = maxf(0.0, shift_timer - dt)
	speed_kmh = absf(vf) * 3.6
	var v := speed_kmh
	# 换挡（带回差）：升挡按即时边界，降挡需低于当前档下限的 94%，
	# 否则换挡切断会让车速在档位边界振荡、永远无法越过（极速被锁死在边界上）
	var g := gear
	if no_shift:
		g = 1   # 电驱单速：无换挡
	else:
		while g < GEAR_KMH.size() and v >= GEAR_KMH[g]:
			g += 1
		while g > 1 and v < GEAR_KMH[g - 1] * 0.94:
			g -= 1
		g = clampi(g, 1, GEAR_KMH.size())
		if g != gear and shift_timer == 0.0:
			gear = g
			shift_timer = 0.13
	var lo: float
	var hi: float
	if no_shift:
		lo = 0.0
		hi = top_speed * 3.6   # 电驱：音调跟随全速域车速，0→极速连续爬升
	else:
		lo = GEAR_KMH[gear - 1] if gear - 1 < GEAR_KMH.size() else 0.0
		hi = GEAR_KMH[gear] if gear < GEAR_KMH.size() else 300.0
	var frac := clampf((v - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
	var target_rpm := 0.10 if (v < 1.0 and input_throttle == 0.0) \
			else clampf(0.16 + frac * 0.84 + input_throttle * 0.05, 0.0, 1.0)
	if no_shift and v >= 1.0:
		# 电驱特性：音调随全速域车速爬升，油门再叠加瞬态加成（即踩即起，松油即落）
		target_rpm = clampf(0.16 + frac * 0.84 + input_throttle * 0.35, 0.1, 1.0)
	rpm_norm = RRUtil.damp(rpm_norm, target_rpm, 8.0, dt)
	engine_load_smoothed = RRUtil.damp(engine_load_smoothed,
			input_throttle * 0.7 + clampf(g_long * 9.81 / 13.0, 0.0, 0.5), 5.0, dt)


## 外部冲量（车对车碰撞）
func apply_world_impulse(ix: float, iz: float) -> void:
	var s := sin(heading)
	var c := cos(heading)
	vf += ix * s + iz * c
	vl += ix * c - iz * s


func world_velocity() -> Vector3:
	var s := sin(heading)
	var c := cos(heading)
	return Vector3(s * vf + c * vl, 0, c * vf - s * vl)


func forward_dir() -> Vector3:
	return Vector3(sin(heading), 0, cos(heading))


func consume_hit() -> float:
	var h := hit_impulse
	hit_impulse = 0.0
	return h


func consume_land_impact() -> float:
	var li := land_impact
	land_impact = 0.0
	return li
