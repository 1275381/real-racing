class_name AIDriver
extends RefCounted
## AI 车手：前瞻追踪中心线 + 按前方曲率限速 + 避让 + 橡皮筋
## （移植自 js/opponents.js）

var veh: Vehicle
var track               # RaceTrack（AI 仅用于比赛模式）
var skill := 1.0                # 抓地/动力/限速整体系数
var base_lane := 0.0            # 常用走线横向偏移
var rubber := 0.0               # 由 Game 注入 -0.06..+0.08
var lane_offset := 0.0
var target_lane := 0.0
var stuck_timer := 0.0
var reverse_timer := 0.0


func _init(v: Vehicle, trk, opts: Dictionary = {}) -> void:
	veh = v
	track = trk
	skill = opts.get("skill", 1.0)
	base_lane = opts.get("base_lane", 0.0)
	lane_offset = base_lane
	target_lane = base_lane


## 新一局开始时清空跨局残留状态
func reset() -> void:
	stuck_timer = 0.0
	reverse_timer = 0.0
	lane_offset = base_lane
	target_lane = base_lane
	rubber = 0.0


func update(dt: float, others: Array) -> void:
	var v := veh
	var trk = track

	# 卡死自救：倒车 1.2 秒再继续
	if reverse_timer > 0.0:
		reverse_timer -= dt
		v.input_throttle = 0.0
		v.input_brake = 1.0
		v.input_steer = -signf(v.vl if v.vl != 0.0 else 1.0)
		if reverse_timer <= 0.0:
			stuck_timer = 0.0
		return
	if absf(v.vf) < 0.8 and v.input_throttle > 0.5:
		stuck_timer += dt
		if stuck_timer > 2.2:
			reverse_timer = 1.15
			return
	else:
		stuck_timer = maxf(0.0, stuck_timer - dt)

	# ---- 目标点：前瞻 + 变线偏移 ----
	var la := 6.0 + absf(v.vf) * 0.55
	var ti: int = trk.ahead_idx(v.q_idx if v.q_idx != null else 0, la)
	# 平滑变换走线（超越时横移）
	lane_offset = RRUtil.damp(lane_offset, target_lane, 1.4, dt)
	var tp: Vector2 = trk.pts[ti]
	var tl: Vector2 = trk.left_v[ti]
	var tx := tp.x + tl.x * (lane_offset + base_lane)
	var tz := tp.y + tl.y * (lane_offset + base_lane)

	var desired := atan2(tx - v.pos.x, tz - v.pos.z)
	var err := RRUtil.wrap_angle(desired - v.heading)
	v.input_steer = clampf(err * 3.0 - v.yaw_rate * 0.12, -1.0, 1.0)

	# ---- 前方曲率 → 允许速度（含刹车距离约束）----
	var v_allow := v.top_speed
	var mu_a := 10.2 * skill
	for j in range(0, 64, 3):
		var idx: int = trk.ahead_idx(v.q_idx if v.q_idx != null else 0, 8.0 + j * 3.0)
		var k := maxf(absf(trk.curv[idx]), 1e-5)
		var vc := sqrt(mu_a / k) + 2.5
		var d := 8.0 + j * 3.0
		var allowed := sqrt(vc * vc + 2.0 * 17.0 * d)
		v_allow = minf(v_allow, allowed)
	v_allow *= skill * (1.0 + rubber)
	v_allow = minf(v_allow, v.top_speed * skill * (1.0 + rubber))

	# ---- 油门 / 刹车 ----
	var dv := v_allow - v.vf
	if dv > 1.5:
		v.input_throttle = clampf(dv / 8.0, 0.35, 1.0)
		v.input_brake = 0.0
	elif dv < -2.0:
		v.input_throttle = 0.0
		v.input_brake = clampf(-dv / 9.0, 0.25, 1.0)
	else:
		v.input_throttle = 0.4
		v.input_brake = 0.0

	# ---- 简单避让：前车太近则变线并收油 ----
	if not others.is_empty():
		var dodged := false
		for o in others:
			if o == v:
				continue
			var dx: float = o.pos.x - v.pos.x
			var dz: float = o.pos.z - v.pos.z
			var s := sin(v.heading)
			var c := cos(v.heading)
			var fwd_d := dx * s + dz * c
			var lat_d := dx * c - dz * (-s)      # dot with left vector (c,-s)
			if fwd_d > 0.0 and fwd_d < 11.0 and absf(lat_d) < 3.4 \
					and o.speed_kmh < v.speed_kmh + 12.0:
				target_lane = clampf((-1.0 if lat_d > 0.0 else 1.0) * 3.2, -5.0, 5.0)
				if fwd_d < 5.5:
					v.input_throttle *= 0.4
				dodged = true
				break
		if not dodged and absf(lane_offset) > 0.2:
			# 无威胁后缓回本线路
			target_lane = 0.0

	v.input_handbrake = false


## 完赛后的巡航自动驾驶
func cruise() -> void:
	var v := veh
	var trk = track
	var ti: int = trk.ahead_idx(v.q_idx if v.q_idx != null else 0, 10.0 + absf(v.vf) * 0.5)
	var tp: Vector2 = trk.pts[ti]
	var desired := atan2(tp.x - v.pos.x, tp.y - v.pos.z)
	var err := RRUtil.wrap_angle(desired - v.heading)
	v.input_steer = clampf(err * 2.6, -1.0, 1.0)
	v.input_throttle = 0.45 if v.vf < 12.0 else 0.0
	v.input_brake = 0.35 if v.vf > 18.0 else 0.0
