# 回归：火箭发射场全链——场地与接入 / moon_query 总闸 / 登乘发射入轨 /
# EVA 失重 / 月球降落与月面低重力行走 / B 快速返场 / 四断点 exit_roam 复位。
# 步进模式参照 test_villa / test_aero 既有写法（手动 _step_sim，不依赖渲染帧）。
extends SceneTree

var game
var fm: FreeroamMap
var rs                          # RocketSite（弱类型：直取字段）
var ok_all := true


func frames(n: int) -> void:
	for i in n:
		await process_frame


func check(cond: bool, label: String) -> void:
	print("[rk] %s ... %s" % [label, "OK" if cond else "FAIL"])
	if not cond:
		ok_all = false


func step_sim(sec: float) -> void:
	var n := int(round(sec * 60.0))
	for i in n:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)


## 渲染帧侧逻辑（space_f / far 滞回 / 月球淡入在 _process）补跑若干拍
func step_proc(n: int) -> void:
	for i in n:
		game._process(1.0 / 60.0)


func press_f() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func release_f() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## 完整一记按键（默认 F）：封掉真实 _process → 按下并同步跑热键链 →
## 隔帧松开（同帧 press+release 会被输入系统丢弃）→ 解封。
## 不封 _process 的话，await 期间引擎真实帧会把 still-just_pressed 的动作
## 再消费一次（headless 下帧戳不推进），刚登上的火箭会被同一记 F 中止掉
func tap_key(code: int) -> void:
	game.set_process(false)
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	game._handle_hotkeys()
	await frames(1)
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = code
	ev2.pressed = false
	Input.parse_input_event(ev2)
	Input.flush_buffered_events()
	game.set_process(true)


func tap_f() -> void:
	await tap_key(KEY_F)


func reset_state_clean() -> void:
	# 洗回干净态：玩家车内、火箭 idle、步行重力清空
	game.rocket_ride = false
	game.on_foot = false
	if game.onfoot != null:
		game.onfoot.exit()
		game.onfoot.gravity_mode = ""
	rs.reset_launch()
	fm.moon_query = false
	game.env.space_f = 0.0
	game.camera.far = 2800.0
	game._moon_fade = 0.0


func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe_rocket.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"user://rr_settings_probe_rocket.cfg"))
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(12)
	fm = game.freeroam
	rs = fm.rocket_site
	game.npc_solid = false

	# ================= ① 场地与接入 =================
	check(rs != null, "发射场状态机随地图创建")
	check(fm.rocket_probe.size() == 4, "headless 断言锚点 4 个（台顶/舱门/塔顶/月面坪）")
	var q_pad: Dictionary = fm.query(1700.0, 0.0, null, 0.5)
	check(absf(float(q_pad["height"]) - 0.5) < 0.05 and q_pad["surf"] == "road",
			"发射坪铺装：高度 0.5 且按道路计（%s / %s）" % [str(q_pad["height"]),
			str(q_pad["surf"])])
	var has_access := false
	for r in fm.roads:
		if r.id == "out/rocket_site":
			has_access = true
	check(has_access, "接入路 out/rocket_site 进路网（导航图自动收录）")
	var q_road: Dictionary = fm.query(1685.0, 300.0, null, 2.0)
	check(q_road["road"] >= 0 and q_road["surf"] in ["road", "curb"],
			"接入路可行驶（surf=%s）" % str(q_road["surf"]))
	var poi_hit := false
	for poi in game.hud.nav_pois():
		if poi["label"] == "火箭发射场" and (poi["pos"] as Vector2).distance_to(
				Vector2(1700, 0)) < 1.0:
			poi_hit = true
	check(poi_hit, "大地图 POI「火箭发射场」在 (1700,0)")

	# ================= ② moon_query 总闸（评审③：战机不被劫持） =================
	var q_plain: Dictionary = fm.query(5200.0, 2600.0, null, 5000.0)
	check(absf(float(q_plain["height"])) < 0.5,
			"moon_query=false：月轴上空 query 返回地形高（%.2f，非月面）"
			% float(q_plain["height"]))
	fm.moon_query = true
	var q_moon: Dictionary = fm.query(5200.0, 2600.0, null, 5600.0)
	check(absf(float(q_moon["height"]) - 5600.0) < 0.5,
			"moon_query=true：着陆坪平底 5600（%.2f）" % float(q_moon["height"]))
	var q_dome: Dictionary = fm.query(5500.0, 2600.0, null, 5500.0)
	check(absf(float(q_dome["height"]) - (5000.0 + sqrt(360000.0 - 90000.0))) < 0.5,
			"月面穹面公式 y=月心+sqrt(r²-d²)（%.2f）" % float(q_dome["height"]))
	fm.moon_query = false

	# ================= ③ 登乘 → 发射 → 入轨 =================
	# 车停上发射坪，下车走到登船口
	game.player.veh.pos = Vector3(1700.0, 2.0, 26.0)
	game.player.veh.heading = 0.0
	game._toggle_on_foot()
	game.onfoot.pos = Vector3(1700.0, 2.55, 9.5)
	check(rs.near_board_door(game.onfoot.pos), "登船口 10m 判定生效")
	var car_pos: Vector3 = game.player.veh.pos
	# 战机双触发场景（评审④b）：plane_mode + 舱外停着落地战机，F 只登火箭
	game.plane_mode = true
	game.rplane = {"pos": Vector3(1700.0, 2.0, 18.0), "heading": 0.0,
			"pitch": 0.0, "roll": 0.0, "speed": 0.0, "throttle": 0.0,
			"landed": true, "hint": 0}
	await tap_f()
	check(game.rocket_ride and rs.phase == "countdown",
			"F 登乘：进入倒计时（plane_mode 下无双触发）")
	check(game.hud._center_label.text != "无法下机",
			"无「无法下机」横幅（战机 F 块守卫生效）")
	game.plane_mode = false
	game.rplane.clear()
	# 倒计时中再按 F = 中止（玩家应被放回登船口步行态，战机块不得拽人）
	await tap_f()
	check(rs.phase == "idle" and not game.rocket_ride and game.on_foot,
			"倒计时 F 中止发射（phase=%s ride=%s foot=%s）" % [rs.phase,
			game.rocket_ride, game.on_foot])
	# 重新登乘走完整链
	game.on_foot = true
	game.onfoot.pos = Vector3(1700.0, 2.55, 9.5)
	await tap_f()
	check(game.rocket_ride and rs.phase == "countdown", "重新登乘")
	step_sim(11.5)   # 倒计时 10s + 点火 1.2s
	check(rs.phase == "climb", "点火后进入爬升（%s）" % rs.phase)
	check(game.player.veh.pos.distance_to(car_pos) < 0.05,
			"乘船期间玩家车冻结在发射坪（%.2fm）"
			% game.player.veh.pos.distance_to(car_pos))
	step_sim(34.0)   # 爬升约 30s 至 KARMAN 3500
	check(rs.phase in ["stage2", "orbit"], "越卡门线入轨（%s）" % rs.phase)
	check(rs.pos.y > 3400.0, "轨道高度 >3400（%.0f）" % rs.pos.y)
	check(fm.moon_query, "moon_query 总闸随太空相位置位")
	step_proc(30)
	check(game.camera.far > 8000.0, "space_f>0.5：far 抬 9000（%.0f）" % game.camera.far)
	check(game.env.space_f > 0.5, "env.space_f 已混合（%.2f）" % game.env.space_f)

	# ================= ④ EVA 失重 =================
	rs.handle_interact(game)
	check(game.on_foot and game.onfoot.gravity_mode == "zero" and not game.rocket_ride,
			"F 出舱：EVA 失重模式")
	var eva_start: Vector3 = game.onfoot.pos
	step_sim(1.5)
	check(game.onfoot.pos.distance_to(eva_start) < 0.05,
			"无输入纯惯性：松手漂在原地（%.3fm）" % game.onfoot.pos.distance_to(eva_start))
	check(rs.phase == "orbit" and not game.rocket_ride, "出舱后状态机仍在轨推进（EVA 兜底不停摆）")
	# 磁力牵引回收：飘远 + 长按 F 1s
	game.onfoot.pos = rs.local_to_world(Vector3(0, 44.0, 180.0))
	press_f()
	step_sim(1.4)
	release_f()
	await frames(2)   # 让 just_pressed 的帧戳过期：headless 下物理帧不走，
	#                  同帧戳的陈旧 F 会在之后任何热键调用里重触交互链
	check(game.onfoot.pos.distance_to(rs.local_to_world(Vector3(0, 44.0, 8.0))) < 30.0,
			"长按 F 磁力牵引回收（距船 %.0fm）"
			% game.onfoot.pos.distance_to(rs.local_to_world(Vector3(0, 44.0, 8.0))))
	# 评审②回归：enter() 复位清单清 gravity_mode
	game.onfoot.enter(Vector3(1700.0, 0.6, 20.0), 0.0)
	check(game.onfoot.gravity_mode == "", "enter() 复位 gravity_mode（地面跳跃回归正常）")
	game.on_foot = false
	game.onfoot.exit()

	# ================= ⑤ 月球降落 + 月面行走 =================
	game.rocket_ride = true
	rs.phase = "orbit"
	rs.pos = Vector3(5200.0, 5950.0, 2600.0)   # 距月面坪 350m，触发自动着陆
	rs.heading = 0.0
	rs.pitch = 0.0
	rs.speed = 40.0
	rs.target_speed = 40.0
	step_sim(40.0)
	check(rs.phase == "moon_landed", "自动垂直缓降着陆月球（%s）" % rs.phase)
	check(absf(rs.pos.y - 5600.0) < 0.6, "落在静海基地坪面（%.2f）" % rs.pos.y)
	# 月面行走
	rs.handle_interact(game)
	check(game.on_foot and game.onfoot.gravity_mode == "moon",
			"F 下舱：月面低重力行走")
	step_sim(2.0)   # 从舷梯落地站稳，再起跳
	var ground_y: float = game.onfoot.pos.y
	press_space()
	var peak := ground_y
	for i in int(6.0 * 60):
		step_sim(1.0 / 60.0)
		peak = maxf(peak, game.onfoot.pos.y)
	release_space()
	check(peak - ground_y > 3.0 and peak - ground_y < 7.5,
			"月跳高约 3.6~6m（实测 %.2fm）" % (peak - ground_y))
	check(absf(game.onfoot.pos.y - ground_y) < 0.15, "落回坪面（无伤，y 偏差 %.2f）"
			% absf(game.onfoot.pos.y - ground_y))
	check(fm.moon_query, "月面行走期间 moon_query 保持（query 贴合走月面高度）")
	# 回船起飞（舱门边 F：回船并自动起飞离月）
	game.onfoot.pos = rs.local_to_world(Vector3(0, 1.6, 5.5))
	game.on_foot = true
	rs.handle_interact(game)
	check(not game.on_foot and game.rocket_ride and rs.phase == "moon_liftoff",
			"舱门边 F 回船并起飞离月（%s）" % rs.phase)
	step_sim(12.0)
	check(rs.phase == "orbit" and rs.pos.y > 6050.0,
			"升出月面捕获半径回巡航（%s y=%.0f）" % [rs.phase, rs.pos.y])

	# ================= ⑥ B 快速返场（防卡死兜底捷径） =================
	await frames(1)   # 冲掉可能的陈旧动作帧戳
	await tap_key(KEY_B)
	check(rs.phase == "idle" and not game.rocket_ride and game.on_foot,
			"B 直接落回发射坪边步行态（phase=%s ride=%s foot=%s）" % [rs.phase,
			game.rocket_ride, game.on_foot])
	check(game.onfoot.gravity_mode == "", "返场后重力模式为地球")
	for i in 6:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
	step_proc(6)
	check(game.camera.far == 2800.0 and game.env.space_f < 0.01 and not fm.moon_query,
			"返场后太空层全复位（far=%.0f space_f=%.2f moon_query=%s）"
			% [game.camera.far, game.env.space_f, str(fm.moon_query)])

	# ================= ⑦ 四断点 exit_roam 复位（红线回归） =================
	await _test_exit_reset("climb")
	await _test_exit_reset("orbit")
	await _test_exit_reset("eva")
	await _test_exit_reset("moon_landed")

	print("[rk] %s" % ("PASS" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)


func press_space() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func release_space() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _test_exit_reset(scenario: String) -> void:
	# 复位干净起步
	reset_state_clean()
	game.on_foot = false
	if game.onfoot != null:
		game.onfoot.exit()
	game.rocket_ride = true
	match scenario:
		"climb":
			rs.phase = "climb"
			rs.pos = Vector3(1700.0, 800.0, 0.0)
			rs.pitch = PI * 0.45
			rs.speed = 90.0
		"orbit":
			rs.phase = "orbit"
			rs.pos = Vector3(2500.0, 4200.0, 800.0)
			rs.pitch = 0.1
			rs.speed = 60.0
		"eva":
			rs.phase = "orbit"
			rs.pos = Vector3(2400.0, 4100.0, 800.0)
			rs.speed = 0.0
			game.rocket_ride = false
			game.on_foot = true
			game.onfoot.enter(rs.local_to_world(Vector3(0, 44.0, 6.0)), 0.0)
			game.onfoot.gravity_mode = "zero"
		"moon_landed":
			rs.phase = "moon_landed"
			rs.pos = Vector3(5200.0, 5600.0, 2600.0)
			rs.pitch = PI * 0.5
			rs.speed = 0.0
			game.rocket_ride = false
			game.on_foot = true
			game.onfoot.enter(rs.local_to_world(Vector3(0, 1.2, 7.0)), 0.0)
			game.onfoot.gravity_mode = "moon"
			game.onfoot.vy = 2.0
	step_sim(0.5)   # 让 _update 维护一次 moon_query / 姿态
	game.exit_roam()
	await frames(6)
	var ok: bool = not game.rocket_ride and rs.phase == "idle" \
			and not fm.moon_query and game.camera.far == 2800.0 \
			and game.env.space_f < 0.01 and game._moon_fade < 0.01 \
			and game.onfoot.gravity_mode == "" and game.onfoot.vy == 0.0 \
			and game.onfoot.eva_vel == Vector3.ZERO \
			and absf(rs.pos.y - 2.55) < 0.1
	check(ok, "exit_roam@" + scenario + "：火箭/月闸/太空层/重力模式全复位（phase="
			+ rs.phase + " q=" + str(fm.moon_query) + " far="
			+ str(game.camera.far) + " sf=" + str(game.env.space_f)
			+ " g=" + game.onfoot.gravity_mode + "）")
	# 回漫游继续下一断点
	game.enter_roam()
	await frames(8)
	rs = fm.rocket_site if fm.rocket_site != null else rs
	rs.game = game
