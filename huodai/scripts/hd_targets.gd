class_name HDTargets
extends Node3D
## 烽火地带 —— 室内靶馆靶道（3 条 ×2 靶）。
## 2026-10-31 用户定案改版：靶 = 人形训练假人（头/躯干/双臂/腿 + 底座，胸口
## 靶环保留计分视觉锚），站在馆内地坪上（root.y = 馆心 + HALL_FLOOR_Y——旧版
## root.y=0 悬在馆内地坪上方 6.94m，即用户报告「靶在靶场上面」的根因）。
## 倒靶改绕脚底后仰（pivot 落到脚底 y=0），摆动靶绕脚 ±30°（不倒翁式）。
## 射击线在馆心 +Z 侧（+11），三道靶距 10/16/22m；命中假人躯干/头 AABB、
## 按距离计分 25/50/75，1.9s 后自动立起；倒地途中/倒地不判定。

signal score_changed(score: int)

const LANE_DIST := [10.0, 16.0, 22.0]   # 三道靶距射击线（m）
const LANE_SCORE := [25, 50, 75]        # 按距离计分
const LANE_DX := [-2.0, 0.0, 2.0]       # 三条射击位横向间距
const FIRE_DZ := 11.0                   # 射击线在馆心 +Z 侧的距离
const FIXED_DX := -0.6                  # 固定靶在道内左偏
const SWING_DX := 0.6                   # 摆动靶在道内右偏
const SWING_DEG := 30.0                 # 摆动靶 ±30°
const SWING_PERIOD := [1.6, 2.0, 2.4]   # 摆动周期（按道错开）
const AUTO_RISE := 1.9                  # 倒靶 1.9s 后自动立起
const FALL_TIME := 0.28                 # 倒下动画时长
const RISE_TIME := 0.3                  # 立起动画时长
const POST_H := 0.0                     # 假人 pivot=脚底（旧立杆吊点已废）
const MIN_HIT_D := 0.1                  # 贴脸忽略（与网页版 t>0.1 同源）
## 假人命中盒（pivot 本地=脚底原点：覆盖腿到头全身 1.55m 的保守 AABB，
## 躯干/头为主——2026-10-31 假人改版随假人全身重新标定）
const HIT_C := Vector3(0.0, 0.85, 0.0)
const HIT_H := Vector3(0.26, 0.72, 0.12)

var score: int = 0
var best: int = 0

var _targets: Array = []   # {root,pivot,lane,swing,period,phase0,phase,alive,down_t,rise_t}
var _m_post: StandardMaterial3D
var _m_board: StandardMaterial3D
var _m_ring: StandardMaterial3D
var _m_heart: StandardMaterial3D


## 馆内 3 条靶道：每道固定立靶 + 摆动靶各一（共 6 靶）
func build(hall_center: Vector3) -> void:
	for tg in _targets:
		(tg["root"] as Node3D).queue_free()
	_targets.clear()
	score = 0
	_ensure_mats()
	# 假人站馆内地坪（2026-10-31 修「靶在靶场上面」：旧版 root.y=馆心 y=0，
	# 悬空 6.94m；现在 y=馆心 + HALL_FLOOR_Y，与玩家射击线同一地面）
	for lane in 3:
		var dist: float = LANE_DIST[lane]
		var fire_z := hall_center.z + FIRE_DZ - dist
		_make_target(hall_center.x + LANE_DX[lane] + FIXED_DX,
				hall_center.y + HDData.HALL_FLOOR_Y, fire_z, lane, false)
		_make_target(hall_center.x + LANE_DX[lane] + SWING_DX,
				hall_center.y + HDData.HALL_FLOOR_Y, fire_z, lane, true)


func update(dt: float) -> void:
	for tg in _targets:
		var piv: Node3D = tg["pivot"]
		# 摆动靶：绕吊点正弦 ±30°（alive 才摆，倒下即停）
		if bool(tg["swing"]) and bool(tg["alive"]):
			tg["phase"] = float(tg["phase"]) + dt
			piv.rotation.z = deg_to_rad(SWING_DEG) * sin(
					TAU * float(tg["phase"]) / float(tg["period"]) + float(tg["phase0"]))
		# 倒下 / 自动立起动画（rotation.x 后仰倒）
		if not bool(tg["alive"]):
			if float(tg["down_t"]) >= 0.0:
				tg["down_t"] = float(tg["down_t"]) + dt
				var kf := minf(float(tg["down_t"]) / FALL_TIME, 1.0)
				piv.rotation.x = -PI * 0.5 * kf
				if float(tg["down_t"]) >= AUTO_RISE + FALL_TIME:
					tg["down_t"] = -1.0
					tg["rise_t"] = 0.0
			elif float(tg["rise_t"]) >= 0.0:
				tg["rise_t"] = float(tg["rise_t"]) + dt
				var kr := minf(float(tg["rise_t"]) / RISE_TIME, 1.0)
				piv.rotation.x = -PI * 0.5 * (1.0 - kr)
				if kr >= 1.0:
					tg["rise_t"] = -1.0
					tg["alive"] = true
					piv.rotation.x = 0.0


## 射线命中（与士兵 raycast 同风格）：{"type":"target","i":i,"d":d,"point":...}
## 或 {"type":"","d":max_d,...}；倒地途中/倒地靶不判定
func raycast(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var best_d := max_d
	var best_i := -1
	for i in _targets.size():
		var tg: Dictionary = _targets[i]
		if not bool(tg["alive"]):
			continue
		var root: Node3D = tg["root"]
		var piv: Node3D = tg["pivot"]
		# 世界 → pivot 本地（吊点平移 + 绕 Z 反旋转，摆动角即 rotation.z）
		var ang := piv.rotation.z
		var cs := cos(ang)
		var sn := sin(ang)
		var ox := from.x - root.position.x
		var oy := from.y - (root.position.y + piv.position.y)
		var oz := from.z - root.position.z
		var lo := Vector3(cs * ox + sn * oy, -sn * ox + cs * oy, oz)
		var ld := Vector3(cs * dir.x + sn * dir.y, -sn * dir.x + cs * dir.y, dir.z)
		# 对命中 AABB（中心 HIT_C 半 HIT_H）做平板求交
		var t0 := 0.0
		var t1 := best_d
		var hit := true
		for ax in 3:
			var o: float = lo[ax]
			var d: float = ld[ax]
			var c: float = HIT_C[ax]
			var h: float = HIT_H[ax]
			if absf(d) < 0.000001:
				if absf(o - c) > h:
					hit = false
					break
				continue
			var ta := (c - h - o) / d
			var tb := (c + h - o) / d
			if ta > tb:
				var tt := ta
				ta = tb
				tb = tt
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				hit = false
				break
		if not hit or t0 <= MIN_HIT_D or t0 >= best_d:
			continue
		best_d = t0
		best_i = i
	if best_i < 0:
		return {"type": "", "d": max_d, "point": from + dir * max_d}
	return {"type": "target", "i": best_i, "d": best_d, "point": from + dir * best_d}


## 命中倒靶 + 按距离计分（1.9s 后 update 里自动立起）
func on_hit(i: int) -> void:
	if i < 0 or i >= _targets.size():
		return
	var tg: Dictionary = _targets[i]
	if not bool(tg["alive"]):
		return
	tg["alive"] = false
	tg["down_t"] = 0.0
	tg["rise_t"] = -1.0
	score += int(LANE_SCORE[int(tg["lane"])])
	if score > best:
		best = score
	score_changed.emit(score)


## 重置全场：计分清零 + 全部立起（best 保留为纪录）
func reset_all() -> void:
	score = 0
	score_changed.emit(score)
	for tg in _targets:
		tg["alive"] = true
		tg["down_t"] = -1.0
		tg["rise_t"] = -1.0
		tg["phase"] = 0.0
		(tg["pivot"] as Node3D).rotation = Vector3.ZERO


# ================= 内部：建靶 =================

func _ensure_mats() -> void:
	if _m_post != null:
		return
	_m_post = StandardMaterial3D.new()
	_m_post.albedo_color = Color(0.29, 0.29, 0.27)   # 钢杆
	_m_post.roughness = 0.7
	_m_post.metallic = 0.3
	_m_board = StandardMaterial3D.new()
	_m_board.albedo_color = Color(0.85, 0.79, 0.64)  # 做旧米黄靶纸
	_m_board.roughness = 0.85
	_m_ring = StandardMaterial3D.new()
	_m_ring.albedo_color = Color(0.95, 0.94, 0.9)    # 白圈
	_m_ring.roughness = 0.6
	_m_heart = StandardMaterial3D.new()
	_m_heart.albedo_color = Color(0.76, 0.23, 0.18)  # 红心
	_m_heart.roughness = 0.6


## 单个靶：立杆 + 吊点 pivot + 半身靶板（躯干方块/头圆/白圈/红心）
func _make_target(x: float, floor_y: float, z: float, lane: int, swing: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, floor_y, z)
	add_child(root)
	# 底座圆盘（假人站稳 + 倒靶旋转的视觉承接）
	var base := MeshInstance3D.new()
	var bm0 := CylinderMesh.new()
	bm0.top_radius = 0.2
	bm0.bottom_radius = 0.24
	bm0.height = 0.05
	bm0.material = _m_post
	base.mesh = bm0
	base.position = Vector3(0.0, 0.025, 0.0)
	root.add_child(base)
	# pivot=脚底（2026-10-31 假人改版：倒靶绕脚后仰、摆动绕脚不倒翁摆）
	var piv := Node3D.new()
	piv.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(piv)
	var m_body: StandardMaterial3D = _m_board   # 假人本体：做旧米黄
	var m_joint: StandardMaterial3D = _m_post    # 关节/腿：深灰
	# 双腿（0.04→0.62）
	for lx in [-0.065, 0.065]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.09, 0.58, 0.1)
		lm.material = m_joint
		leg.mesh = lm
		leg.position = Vector3(lx, 0.33, 0.0)
		piv.add_child(leg)
	# 骨盆（0.62→0.76）
	var pelvis := MeshInstance3D.new()
	var pm2 := BoxMesh.new()
	pm2.size = Vector3(0.3, 0.14, 0.16)
	pm2.material = m_body
	pelvis.mesh = pm2
	pelvis.position = Vector3(0.0, 0.69, 0.0)
	piv.add_child(pelvis)
	# 躯干（0.76→1.28，上宽下窄两段拼）
	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.34, 0.4, 0.15)
	tm.material = m_body
	torso.mesh = tm
	torso.position = Vector3(0.0, 0.97, 0.0)
	piv.add_child(torso)
	var chest := MeshInstance3D.new()
	var cm2 := BoxMesh.new()
	cm2.size = Vector3(0.42, 0.14, 0.15)
	cm2.material = m_body
	chest.mesh = cm2
	chest.position = Vector3(0.0, 1.22, 0.0)
	piv.add_child(chest)
	# 双臂垂放（肩块下挂）
	for ax in [-0.245, 0.245]:
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.07, 0.46, 0.08)
		am.material = m_body
		arm.mesh = am
		arm.position = Vector3(ax, 0.95, 0.0)
		piv.add_child(arm)
	# 颈（1.28→1.38）
	var neck := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.03
	nm.bottom_radius = 0.035
	nm.height = 0.1
	nm.material = m_joint
	neck.mesh = nm
	neck.position = Vector3(0.0, 1.33, 0.0)
	piv.add_child(neck)
	# 头（球，中心 1.46）
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.095
	hm.height = 0.19
	hm.material = m_body
	head.mesh = hm
	head.position = Vector3(0.0, 1.46, 0.0)
	piv.add_child(head)
	# 胸口靶环 + 红心（计分视觉锚，贴胸前 z+）
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.085
	rm.outer_radius = 0.115
	rm.material = _m_ring
	ring.mesh = rm
	ring.position = Vector3(0.0, 1.0, 0.085)
	piv.add_child(ring)
	var heart := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.038
	dm.bottom_radius = 0.038
	dm.height = 0.02
	dm.material = _m_heart
	heart.mesh = dm
	heart.rotation.x = PI * 0.5
	heart.position = Vector3(0.0, 1.0, 0.095)
	piv.add_child(heart)
	_targets.append({"root": root, "pivot": piv, "lane": lane, "swing": swing,
		"period": float(SWING_PERIOD[lane % SWING_PERIOD.size()]),
		"phase0": randf() * TAU, "phase": 0.0,
		"alive": true, "down_t": -1.0, "rise_t": -1.0})
