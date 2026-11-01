class_name HDTargets
extends Node3D
## 烽火地带 —— 室内靶馆靶道（3 条 ×2 靶）。
## 2026-10-31 靶场 2.0（用户四连需求）：① 假人带血量（DUMMY_HP=100，打空
## 才倒、自动立起时回满血——不再一打就倒）；② 移动靶四模式可调（G 键循环
## 慢/中/快/随机——随机=每 1~2.2s 随机换移速）；③ 靶距三道统一可调
## 1~200m（T/Y 键 ±5m，分值=靶距米数）；④ 馆体拉深 210m 配合远距靶道。
## 移动靶=左右平移（2026-10-31 用户定案「平移不是摆动」）：滑轨式横移
## ±0.95m、比固定靶后退 3.5m（同 z 错开——相邻道平移假人永不互穿），
## 底座圆盘随假人同移（滑车观感）+ 脚下钢轨视觉件。
## 假人=人形训练假人（头/躯干/双臂/腿+底座，胸口靶环保留计分视觉锚），
## 站馆内地坪（root.y = 馆心 + HALL_FLOOR_Y）；倒靶绕脚底后仰；
## 倒地途中/倒地不判定。

signal score_changed(score: int)
signal dummy_hit(hp_left: float, killed: bool)   # 命中反馈（main 接 hitmark/播报）

const LANE_DX := [-2.0, 0.0, 2.0]       # 三条射击位横向间距
const FIRE_DZ := 11.0                   # 射击线在馆心 +Z 侧的距离
const FIXED_DX := -0.6                  # 固定靶在道内左偏
const SWING_DX := 0.6                   # 移动靶滑轨中心在道内右偏
const SWING_AMP := 0.95                 # 移动靶左右平移半幅（m，滑轨全长 1.9m）
const SWING_DEPTH := 3.5                # 移动靶比固定靶后退（m，同 z 错开防互穿）
const AUTO_RISE := 1.9                  # 倒靶 1.9s 后自动立起
const FALL_TIME := 0.28                 # 倒下动画时长
const RISE_TIME := 0.3                  # 立起动画时长
const POST_H := 0.0                     # 假人 pivot=脚底（旧立杆吊点已废）
const MIN_HIT_D := 0.1                  # 贴脸忽略（与网页版 t>0.1 同源）
## 假人命中盒（pivot 本地=脚底原点：覆盖腿到头全身 1.55m 的保守 AABB，
## 躯干/头为主——2026-10-31 假人改版随假人全身重新标定）
const HIT_C := Vector3(0.0, 0.85, 0.0)
const HIT_H := Vector3(0.26, 0.72, 0.12)
## 血量 / 靶距 / 移动（2026-10-31 需求 ①②③；2026-11-01 平板控制升级）
const DUMMY_HP := 100.0                 # 用户定案「至少 100 血」
const DIST_MIN := 1.0                   # 固定靶距下限（m）
const DIST_MAX := 200.0                 # 固定靶距上限（m）——馆深 210m 的内界
const DIST_STEP := 5.0                  # T/Y 每按一次 ±5m
const DIST_DEF := 25.0                  # 默认靶距
const MOVER_PRESETS := [25.0, 50.0, 75.0]   # 移动靶三档靶距（平板按钮，用户定案）
const SWING_MODE_NAMES := ["慢速", "中速", "快速", "随机"]
const SWING_MODE_PERIOD := [3.4, 2.0, 1.0]   # 模式 0/1/2 平移周期（s）；3=随机

var score: int = 0
var best: int = 0
var range_dist := DIST_DEF              # 当前固定靶距（三道统一）
var mover_dist := 25.0                  # 当前移动靶距（三档预设，独立于固定靶）
var swing_mode := 1                     # 0 慢 / 1 中 / 2 快 / 3 随机
var tablet_pos := Vector3.ZERO          # 射击台平板世界坐标（近距交互判定）

var _hall_c: Vector3 = Vector3.ZERO
var _targets: Array = []   # {root,pivot,lane,swing,dist,ph,r_per,r_t,hp,alive,down_t,rise_t}
var _rails: Array = []     # 移动靶钢轨（随移动靶距重摆）
var _tablet: MeshInstance3D
var _m_post: StandardMaterial3D
var _m_board: StandardMaterial3D
var _m_ring: StandardMaterial3D
var _m_heart: StandardMaterial3D


func build(hall_center: Vector3) -> void:
	for tg in _targets:
		(tg["root"] as Node3D).queue_free()
	_targets.clear()
	for r in _rails:
		(r as Node3D).queue_free()
	_rails.clear()
	score = 0
	_hall_c = hall_center
	_ensure_mats()
	var fixed_z := _hall_c.z + FIRE_DZ - range_dist
	var mover_z := _hall_c.z + FIRE_DZ - mover_dist - SWING_DEPTH
	for lane in 3:
		var floor_y: float = _hall_c.y + HDData.HALL_FLOOR_Y
		_make_target(_hall_c.x + LANE_DX[lane] + FIXED_DX, floor_y, fixed_z, lane, false)
		_make_target(_hall_c.x + LANE_DX[lane] + SWING_DX, floor_y, mover_z, lane, true)
		# 移动靶钢轨（平移视觉锚：长 2.8m 低轨，贴地 3cm）
		var rail := MeshInstance3D.new()
		var rm2 := BoxMesh.new()
		rm2.size = Vector3(SWING_AMP * 2.0 + 0.9, 0.06, 0.12)
		rm2.material = _m_post
		rail.mesh = rm2
		rail.position = Vector3(_hall_c.x + LANE_DX[lane] + SWING_DX,
				floor_y + 0.03, mover_z)
		add_child(rail)
		_rails.append(rail)
	# 射击台控制平板（2026-11-01：中射位台面，近距按 F 开控制面板）
	tablet_pos = Vector3(_hall_c.x + LANE_DX[1], _hall_c.y + HDData.HALL_FLOOR_Y + 1.03,
			_hall_c.z + FIRE_DZ - 1.0)
	_build_tablet()


## 射击台平板近距判定（站中射位台边即可开面板）
func pad_near(p: Vector3) -> bool:
	return Vector2(p.x - tablet_pos.x, p.z - tablet_pos.z).length() <= 1.8


## 调固定靶距（三道统一 1~200m）：重摆固定假人 + 立起回满血（移动靶不动）
func set_range_dist(d: float) -> bool:
	var nd := clampf(d, DIST_MIN, DIST_MAX)
	if is_equal_approx(nd, range_dist):
		return false
	range_dist = nd
	var z_t := _hall_c.z + FIRE_DZ - range_dist
	for tg in _targets:
		if not bool(tg["swing"]):
			(tg["root"] as Node3D).position.z = z_t
			tg["dist"] = range_dist
			_revive(tg)
	return true


## 调移动靶距（滑条 1~200m 任意调，25/50/75 是平板快捷档）：重摆移动
## 假人与钢轨 + 回满血
func set_mover_dist(d: float) -> bool:
	var nd := clampf(d, DIST_MIN, DIST_MAX)
	if is_equal_approx(nd, mover_dist):
		return false
	mover_dist = nd
	var z_t := _hall_c.z + FIRE_DZ - mover_dist - SWING_DEPTH
	for tg in _targets:
		if bool(tg["swing"]):
			(tg["root"] as Node3D).position.z = z_t
			tg["dist"] = mover_dist
			_revive(tg)
	for r in _rails:
		(r as Node3D).position.z = z_t
	return true


## 摆动模式四档循环（G 键）：慢 → 中 → 快 → 随机 → 慢
func cycle_swing_mode() -> void:
	swing_mode = (swing_mode + 1) % SWING_MODE_NAMES.size()


func update(dt: float) -> void:
	for tg in _targets:
		var piv: Node3D = tg["pivot"]
		# 移动靶：左右平移（滑轨式 ±SWING_AMP，alive 才移，倒下即停）；
		# 移速由 swing_mode 决定，随机模式 _swing_period 内随机换档——
		# sin 相位累积制：换速率时位置连续不瞬移
		if bool(tg["swing"]) and bool(tg["alive"]):
			var per := _swing_period(tg, dt)
			tg["ph"] = float(tg["ph"]) + dt * TAU / maxf(per, 0.2)
			piv.position.x = SWING_AMP * sin(float(tg["ph"]))
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
					tg["hp"] = DUMMY_HP   # 立起=新假人，血量回满
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
		# 世界 → pivot 本地（root 平移 + pivot 横移量；移动靶无旋转——平移制）
		var ox := from.x - (root.position.x + piv.position.x)
		var oy := from.y - (root.position.y + POST_H)
		var oz := from.z - root.position.z
		var lo := Vector3(ox, oy, oz)
		var ld := dir
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


## 命中扣血（血量制）：打空才倒，倒靶计分=该假人自己的靶距米数
## （固定靶 range_dist / 移动靶 mover_dist 各计各的）；未倒发
## dummy_hit(hp,false) 供 hitmark，打空发 (0,true)
func on_hit(i: int, dmg: float = 20.0) -> void:
	if i < 0 or i >= _targets.size():
		return
	var tg: Dictionary = _targets[i]
	if not bool(tg["alive"]):
		return
	tg["hp"] = maxf(0.0, float(tg["hp"]) - dmg)
	if float(tg["hp"]) > 0.0:
		dummy_hit.emit(float(tg["hp"]), false)
		return
	tg["alive"] = false
	tg["down_t"] = 0.0
	tg["rise_t"] = -1.0
	score += int(round(float(tg.get("dist", range_dist))))
	if score > best:
		best = score
	score_changed.emit(score)
	dummy_hit.emit(0.0, true)


## 重置全场：计分清零 + 全部立起回满血（best 保留为纪录）
func reset_all() -> void:
	score = 0
	score_changed.emit(score)
	for tg in _targets:
		_revive(tg)


# ================= 内部 =================

func _revive(tg: Dictionary) -> void:
	tg["alive"] = true
	tg["down_t"] = -1.0
	tg["rise_t"] = -1.0
	tg["hp"] = DUMMY_HP
	(tg["pivot"] as Node3D).rotation = Vector3.ZERO


## 平移周期：定档模式查表；随机模式每 1.0~2.2s 在 0.7~3.4s 重抽
## （速度阶跃、位置连续——换速率不动 sin 相位，不瞬移）
func _swing_period(tg: Dictionary, dt: float) -> float:
	if swing_mode < SWING_MODE_PERIOD.size():
		return SWING_MODE_PERIOD[swing_mode]
	tg["r_t"] = float(tg["r_t"]) - dt
	if float(tg["r_t"]) <= 0.0:
		tg["r_per"] = randf_range(0.7, 3.4)
		tg["r_t"] = randf_range(1.0, 2.2)
	return maxf(float(tg["r_per"]), 0.2)


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


## 单个假人：底座 + pivot（脚底）+ 全身件（同 2026-10-31 人形建模）
func _make_target(x: float, floor_y: float, z: float, lane: int, swing: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, floor_y, z)
	add_child(root)
	# pivot=脚底（倒靶绕脚后仰；移动靶 pivot.position.x 沿轨平移）
	var piv := Node3D.new()
	piv.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(piv)
	# 底座圆盘挂在 pivot 下（随假人左右平移=滑车观感；倒靶时随整体绕脚翻）
	var base := MeshInstance3D.new()
	var bm0 := CylinderMesh.new()
	bm0.top_radius = 0.2
	bm0.bottom_radius = 0.24
	bm0.height = 0.05
	bm0.material = _m_post
	base.mesh = bm0
	base.position = Vector3(0.0, -0.025, 0.0)
	piv.add_child(base)
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
		"dist": (mover_dist if swing else range_dist),
		"ph": randf() * TAU, "r_per": 2.0, "r_t": 1.0, "hp": DUMMY_HP,
		"alive": true, "down_t": -1.0, "rise_t": -1.0})


## 射击台平板（视觉件）：深灰外壳 + 青绿发光屏，斜立面向 +Z 射手
func _build_tablet() -> void:
	if _tablet != null:
		_tablet.queue_free()
	var t := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.30, 0.02, 0.21)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.12, 0.13, 0.14)
	shell.roughness = 0.5
	tm.material = shell
	t.mesh = tm
	t.rotation.x = 0.42
	t.position = tablet_pos
	add_child(t)
	_tablet = t
	var scr := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.26, 0.008, 0.17)
	var scrmat := StandardMaterial3D.new()
	scrmat.albedo_color = Color(0.1, 0.3, 0.28)
	scrmat.emission_enabled = true
	scrmat.emission = Color(0.3, 0.9, 0.8)
	scrmat.emission_energy_multiplier = 0.9
	sm.material = scrmat
	scr.mesh = sm
	scr.position = Vector3(0.0, 0.013, 0.0)
	t.add_child(scr)
