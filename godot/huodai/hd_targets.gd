class_name HDTargets
extends Node3D
## 烽火地带 —— 室内靶馆靶道（3 条 ×2 靶），移植自网页版 js/fps/targets.js：
## 射击线在馆心 +Z 侧（玩家站位 hall_center + (x∈{-2,0,2}, 0, +11)，面朝 -Z），
## 靶道沿 -Z 延伸，三道靶距射击线 10/16/22m，挡弹墙在最远端（HDWorld 建馆）。
## 每道 2 靶：固定立靶 + 摆动靶（绕吊点 ±30° 正弦摆）；靶 = 立杆 + 半身靶板
## （躯干方块 + 头圆，躯干白圈红心）；命中倒靶（rotation.x 后仰倒下）、按距离
## 计分 25/50/75，1.9s 后自动立起。倒地途中/倒地靶 raycast 不判定。

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
const POST_H := 1.05                    # 立杆高（吊点/铰点高度）
const MIN_HIT_D := 0.1                  # 贴脸忽略（与网页版 t>0.1 同源）
## 靶板命中盒（pivot 本地：覆盖躯干 0.5×0.62 + 头圆 r0.10 的保守 AABB）
const HIT_C := Vector3(0.0, -0.42, 0.0)
const HIT_H := Vector3(0.3, 0.44, 0.07)

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
	for lane in 3:
		var dist: float = LANE_DIST[lane]
		var fire_z := hall_center.z + FIRE_DZ - dist
		_make_target(hall_center.x + LANE_DX[lane] + FIXED_DX, fire_z, lane, false)
		_make_target(hall_center.x + LANE_DX[lane] + SWING_DX, fire_z, lane, true)


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
		var oy := from.y - (root.position.y + POST_H)
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
func _make_target(x: float, z: float, lane: int, swing: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, 0.0, z)
	add_child(root)
	# 立杆
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.05
	pm.height = POST_H
	pm.material = _m_post
	post.mesh = pm
	post.position = Vector3(0.0, POST_H * 0.5, 0.0)
	root.add_child(post)
	# 吊点（摆动绕 Z / 倒靶绕 X 都作用在 pivot 上）
	var piv := Node3D.new()
	piv.position = Vector3(0.0, POST_H, 0.0)
	root.add_child(piv)
	# 躯干方块（板挂在吊点下方，面朝 ±Z 射手）
	var torso := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.62, 0.05)
	bm.material = _m_board
	torso.mesh = bm
	torso.position = Vector3(0.0, -0.31, 0.0)
	piv.add_child(torso)
	# 头圆（圆片）
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.1
	hm.bottom_radius = 0.1
	hm.height = 0.05
	hm.material = _m_board
	head.mesh = hm
	head.rotation.x = PI * 0.5
	head.position = Vector3(0.0, -0.7, 0.0)
	piv.add_child(head)
	# 白圈 + 红心（躯干正面）
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.1
	rm.outer_radius = 0.135
	rm.material = _m_ring
	ring.mesh = rm
	ring.position = Vector3(0.0, -0.31, 0.04)
	piv.add_child(ring)
	var heart := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.045
	dm.bottom_radius = 0.045
	dm.height = 0.02
	dm.material = _m_heart
	heart.mesh = dm
	heart.rotation.x = PI * 0.5
	heart.position = Vector3(0.0, -0.31, 0.058)
	piv.add_child(heart)
	_targets.append({"root": root, "pivot": piv, "lane": lane, "swing": swing,
		"period": float(SWING_PERIOD[lane % SWING_PERIOD.size()]),
		"phase0": randf() * TAU, "phase": 0.0,
		"alive": true, "down_t": -1.0, "rise_t": -1.0})
