extends Node3D
## 整场游戏编排：场景装配 / 状态机 / 定步物理 / 相机 / 竞速判定
## （移植自 js/game.js）

enum ST { GARAGE, COUNTDOWN, RACING, PAUSED, FINISHED, ROAM }

const H_STEP := 1.0 / 120.0        # 固定物理步长
const CAM_MODE_NAMES: Array = TrackData.CAM_MODES
const SETTINGS_PATH := "user://rr_settings.cfg"

var state: int = ST.GARAGE
var tracks: Array[RaceTrack] = []
var track: RaceTrack
var track_idx := 0
var env: RREnvironment
var camera: Camera3D
var hud: RRHud
var fx: RREffects
var audio: RRAudio
var freeroam: FreeroamMap   # 漫游大地图（首次进入漫游时生成）

var cars: Array = []               # CarRec 列表
var player: CarRec

var car_model_id := "gt3"
var total_laps := 3
var difficulty := "normal"
var cam_mode := 0
var dual_mode := "top"     # 双组别车的当前模式（accel 加速 / top 极速）
var _del_arm := false      # 删除自定义赛道的二次确认

var sim_time := 0.0
var count_t := 0.0
var lap_num_display := 1
var player_finish_time = null      # float(ms) 或 null
var best_stored = null             # float(ms) 或 null
var shake := 0.0
var _acc := 0.0
const INTRO_DUR := 2.6     # 入场运镜时长（秒）
var _now_s := 0.0
var _rescue_cd := 0.0
var _paused_from: int = ST.RACING
var _garage_angle := 0.0
var _garage: RRGarage
var _avail_models: Array = []
var _hud_tick := 0.0
var _dbg_tick := 0.0
var _standings_tick := 0.0
var _in_steer := 0.0
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_init := false
var _intro_t := 0.0        # 入场运镜剩余时长（开赛 / 进漫游）


class CarRec:
	extends RefCounted
	var veh: Vehicle
	var visual: CarVisual
	var team: Dictionary
	var team_idx := 0
	var ai: AIDriver
	var ai_cruise: AIDriver
	var roll_cur := 0.0
	var pitch_cur := 0.0
	var bob_phase := 0.0
	var finish_time = null
	var best_lap = null
	var last_lap = null
	var lap_stamp := 0.0


func _enter_tree() -> void:
	_register_inputs()


func _ready() -> void:
	_load_settings()

	camera = Camera3D.new()
	camera.fov = 63.0
	camera.near = 0.8
	camera.far = 2800.0
	camera.position = Vector3(0, 6, -14)
	add_child(camera)
	camera.current = true

	# ---- 赛道（全部预构建，切换显隐；含自定义赛道）----
	for def in TrackData.get_tracks():
		var t := RaceTrack.new()
		t.name = "Track_" + def["id"]
		add_child(t)
		t.build(def)
		tracks.append(t)
	track_idx = _saved_track_idx
	track = tracks[track_idx]
	for i in tracks.size():
		tracks[i].visible = false   # 开局在车库，赛道先隐藏

	# ---- 环境 ----
	env = RREnvironment.new()
	add_child(env)
	env.build(tracks)
	env.set_theme(TrackData.get_tracks()[track_idx]["theme"])

	# ---- 环境反射（车漆金属质感）----
	var probe := ReflectionProbe.new()
	probe.size = Vector3(680, 300, 680)
	probe.position = Vector3(0, 70, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.5
	add_child(probe)

	# ---- 车辆 ----
	for i in TrackData.TEAM_ROSTER.size():
		var team: Dictionary = TrackData.TEAM_ROSTER[i]
		var model: String = car_model_id if i == 0 else team["model"]
		var visual := CarVisual.create(model, team["color"], team["accent"])
		add_child(visual)
		var st: Dictionary = TrackData.model_by_id(model).get("stats", {})
		var veh := Vehicle.new(track, {
			"is_player": i == 0,
			"top_speed": st.get("top", 92.0),
			"power": st.get("power", 60.0),
			"grip_scale": st.get("grip", 1.0),
			"brake": st.get("brake", 18.0),
			"accel_cap": st.get("accel", 11.0),
			"no_shift": st.get("no_shift", false),
		})
		var rec := CarRec.new()
		rec.veh = veh
		rec.visual = visual
		rec.team = team
		rec.team_idx = i
		rec.bob_phase = randf() * 10.0
		if i > 0:
			rec.ai = AIDriver.new(veh, track, {"skill": 1.0})
		cars.append(rec)
	player = cars[0]

	# 圈程回调：玩家走完整计时流程，AI 只记录圈速（供结算表）
	# 用绑定了索引的方法 Callable（而非捕获 lambda），避免 veh↔CarRec 循环引用
	for i in cars.size():
		cars[i].veh.on_lap_complete = Callable(self, "_on_lap_for_car").bind(i)

	# ---- 子系统 ----
	fx = RREffects.new()
	add_child(fx)
	hud = RRHud.new()
	add_child(hud)
	hud.build(TrackData.TEAM_ROSTER.map(func(t): return t["color"]))
	hud.init_minimap(track)
	audio = RRAudio.new()
	add_child(audio)

	# ---- 车库（开局直接进车库选车、选比赛）----
	_garage = RRGarage.new()
	add_child(_garage)
	_garage.build()

	_wire_menu()
	_bind_track_selector()
	_update_del_track_btn()
	_bind_car_buttons()

	reset_grid()
	for i in cars.size():
		cars[i].visual.visible = i == 0   # 车库里只展示玩家车
	refresh_menu_best()
	_update_garage_labels()
	hud.show_only("garage")

	# 调试参数（-- 之后传参，等价网页版 URL 参数）：--autostart --laps=N --track=id --roam
	for arg in OS.get_cmdline_user_args():
		if arg == "--autostart" or arg == "--autodrive":
			start_from_garage.call_deferred()
		elif arg == "--roam":
			enter_roam.call_deferred()
		elif arg.begins_with("--laps="):
			total_laps = clampi(arg.get_slice("=", 1).to_int(), 1, 20)
		elif arg.begins_with("--track="):
			var tid := arg.get_slice("=", 1)
			var ti := TrackData.track_index_by_id(tid)
			set_track.call_deferred(ti)

	# 地图编译器「试驾」：直接开编译好的赛道
	if TrackData.pending_track_id != "":
		var pi := TrackData.track_index_by_id(TrackData.pending_track_id)
		TrackData.pending_track_id = ""
		set_track(pi)
		start_from_garage.call_deferred()


## 进入地图编译器
func open_map_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")


## 车库删除按钮：仅自定义赛道可见；二次确认后删除
func _update_del_track_btn() -> void:
	var custom := track_idx >= TrackData.TRACKS.size()
	hud.btn_del_track.visible = custom
	if not custom:
		_del_arm = false
	hud.btn_del_track.text = "再按一次确认删除" if _del_arm else "删除该自定义赛道"
	hud.btn_del_track.modulate = Color(1.0, 0.55, 0.5) if _del_arm else Color.WHITE


func _on_del_track_pressed() -> void:
	if track_idx < TrackData.TRACKS.size():
		return
	if not _del_arm:
		_del_arm = true
		_update_del_track_btn()
		return
	_del_arm = false
	var def: Dictionary = TrackData.get_tracks()[track_idx]
	TrackData.delete_custom_track(def["id"])
	tracks[track_idx].queue_free()
	tracks.remove_at(track_idx)
	track_idx = clampi(track_idx, 0, tracks.size() - 1)
	track = tracks[track_idx]
	reset_grid()
	_bind_track_selector()
	_update_del_track_btn()
	hud.show_center("已删除自定义赛道", "", 1200)


func _unhandled_input(event: InputEvent) -> void:
	# 车库里按住左键拖动 → 旋转展台环视爱车
	if state != ST.GARAGE:
		return
	if event is InputEventMouseButton and event.pressed:
		audio.ensure()   # 用户手势里解锁音频，之后有怠速声浪
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_garage_angle += event.relative.x * 0.008


# ================= 输入 =================

func _register_inputs() -> void:
	var defs := {
		"rr_throttle": [KEY_W, KEY_UP],
		"rr_brake": [KEY_S, KEY_DOWN],
		"rr_left": [KEY_A, KEY_LEFT],
		"rr_right": [KEY_D, KEY_RIGHT],
		"rr_handbrake": [KEY_SPACE],
		"rr_camera": [KEY_C],
		"rr_rescue": [KEY_R],
		"rr_mute": [KEY_M],
		"rr_pause": [KEY_P, KEY_ESCAPE],
		"rr_start": [KEY_ENTER],
		"rr_dual": [KEY_O],
	}
	for action in defs:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)


func _sample_input(dt: float) -> Dictionary:
	var steer_target := 0.0
	if Input.is_action_pressed("rr_left"):
		steer_target += 1.0
	if Input.is_action_pressed("rr_right"):
		steer_target -= 1.0
	var rate := 10.0 if steer_target == 0.0 else Tuning.STEER_RATE
	_in_steer = move_toward(_in_steer, steer_target, rate * dt)
	return {
		"throttle": 1.0 if Input.is_action_pressed("rr_throttle") else 0.0,
		"brake": 1.0 if Input.is_action_pressed("rr_brake") else 0.0,
		"steer": _in_steer,
		"handbrake": Input.is_action_pressed("rr_handbrake"),
	}


# ================= 存档 =================

var _saved_track_idx := 0


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		car_model_id = cf.get_value("settings", "car", "gt3")
		total_laps = cf.get_value("settings", "laps", 3)
		difficulty = cf.get_value("settings", "diff", "normal")
		_saved_track_idx = TrackData.track_index_by_id(cf.get_value("settings", "track", "circuit"))
		if cf.has_section_key("records", "best_lap"):
			var b = cf.get_value("records", "best_lap")
			if b != null and is_finite(float(b)) and float(b) > 0.0:
				best_stored = float(b)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("settings", "car", car_model_id)
	cf.set_value("settings", "laps", total_laps)
	cf.set_value("settings", "diff", difficulty)
	cf.set_value("settings", "track", TrackData.get_tracks()[track_idx]["id"])
	cf.set_value("records", "best_lap", best_stored)
	cf.save(SETTINGS_PATH)


# ================= 车库绑定 =================

func _wire_menu() -> void:
	hud.btn_start.pressed.connect(start_from_garage)
	hud.btn_roam.pressed.connect(enter_roam)
	hud.track_sel.item_selected.connect(func(_i: int):
		set_track(hud.track_sel.selected)
		_update_del_track_btn())
	hud.laps_sel.item_selected.connect(func(_i: int):
		total_laps = hud.laps_sel.get_item_metadata(hud.laps_sel.selected)
		_save_settings())
	hud.diff_sel.item_selected.connect(func(_i: int):
		difficulty = hud.diff_sel.get_item_metadata(hud.diff_sel.selected)
		_save_settings())
	hud.btn_prev_car.pressed.connect(func(): _cycle_car(-1))
	hud.btn_next_car.pressed.connect(func(): _cycle_car(1))
	hud.btn_resume.pressed.connect(toggle_pause)
	hud.btn_restart.pressed.connect(start_race)
	hud.btn_quit_pause.pressed.connect(to_garage)
	hud.btn_again.pressed.connect(start_race)
	hud.btn_quit_results.pressed.connect(to_garage)
	hud.btn_editor.pressed.connect(open_map_editor)
	hud.btn_del_track.pressed.connect(_on_del_track_pressed)


func _bind_track_selector() -> void:
	for def in TrackData.get_tracks():
		hud.track_sel.add_item(def["name"])
	hud.track_sel.select(track_idx)
	hud.laps_sel.clear()
	for v in [2, 3, 5]:
		var idx := hud.laps_sel.item_count
		hud.laps_sel.add_item("%d 圈" % v)
		hud.laps_sel.set_item_metadata(idx, v)
		if v == total_laps:
			hud.laps_sel.select(idx)
	hud.diff_sel.clear()
	for key in ["easy", "normal", "hard"]:
		var idx := hud.diff_sel.item_count
		hud.diff_sel.add_item(TrackData.DIFF_PRESETS[key]["label"])
		hud.diff_sel.set_item_metadata(idx, key)
		if key == difficulty:
			hud.diff_sel.select(idx)
	_update_garage_labels()


func _bind_car_buttons() -> void:
	_avail_models = CarVisual.available_model_ids()
	_update_garage_labels()


func _cycle_car(dir: int) -> void:
	if _avail_models.is_empty():
		return
	var idx := _avail_models.find(car_model_id)
	idx = posmod(idx + dir, _avail_models.size())
	set_car_model(_avail_models[idx])


func refresh_menu_best() -> void:
	hud.set_best_lap_menu(best_stored)


func _update_garage_labels() -> void:
	var car: Dictionary = TrackData.model_by_id(car_model_id)
	var cls: Dictionary = TrackData.CAR_CLASSES.get(car.get("class", "combustion"), {})
	var desc: String = car["desc"] + (" · 组别：%s" % cls["name"] if not cls.is_empty() else "")
	hud.update_car_label(car["name"], desc)
	var def: Dictionary = TrackData.get_tracks()[track_idx]
	hud.update_track_desc(def["name"] + " · " + def["desc"])
	_apply_engine_profile()


## 按玩家车型切组别引擎声纹
func _apply_engine_profile() -> void:
	var car: Dictionary = TrackData.model_by_id(car_model_id)
	if car.has("modes"):
		audio.set_engine_profile("dual")   # 双模车两种模式共用综合声纹
		return
	audio.set_engine_profile(car.get("class", "combustion"))


## 双组别车：O 键在加速模式 / 极速模式之间切换（只改性能数值，声浪不变）
func _toggle_dual_mode() -> void:
	var car: Dictionary = TrackData.model_by_id(car_model_id)
	if not car.has("modes"):
		hud.show_center("本车不支持双模式", "", 800)
		return
	dual_mode = "accel" if dual_mode == "top" else "top"
	var m: Dictionary = car["modes"][dual_mode]
	player.veh.apply_stats(m)
	hud.show_center("⚡ %s" % m["label"], "", 1200)


# ================= 流程 =================

func start_from_garage() -> void:
	audio.ensure()
	start_race()


## 进入自由漫游：首次会同步生成大地图（1~2 秒）
func enter_roam() -> void:
	if state == ST.ROAM:
		return
	audio.ensure()
	hud.show_only("roam")
	if freeroam == null:
		hud.show_center("正在生成城市…", "首次进入需要一点时间", 4000)
		await get_tree().process_frame
		await get_tree().process_frame
		freeroam = FreeroamMap.new()
		add_child(freeroam)
		freeroam.build()
	freeroam.visible = true
	for t in tracks:
		t.visible = false
	env.set_theme("city")
	env.set_race_props_visible(false)
	env.set_fog_range(900.0, 6500.0)   # 大世界：雾距拉远，山海沙漠可见
	env.set_ground_visible(false)      # 全局面让位给漫游分区地面
	state = ST.ROAM
	for i in cars.size():
		cars[i].visual.visible = i == 0
	player.veh.on_lap_complete = Callable()   # 漫游不计圈
	player.veh.track = freeroam               # 物理查询切换到漫游路网
	var spawn := freeroam.get_spawn()
	var spawn_env := OS.get_environment("ROAM_SPAWN")
	if spawn_env != "" and spawn_env.count(",") == 2:
		var parts := spawn_env.split(",")
		spawn = {"pos": Vector3(parts[0].to_float(), 20.0, parts[1].to_float()),
				"heading": parts[2].to_float()}
	player.veh.place_at({"pos": spawn["pos"], "heading": spawn["heading"], "idx": null})
	_in_steer = 0.0
	_cam_init = false
	_intro_t = INTRO_DUR
	hud.init_roam_minimap(freeroam.minimap_tex,
			Vector2(-FreeroamMap.MAP_LIMIT, -FreeroamMap.MAP_LIMIT),
			Vector2(FreeroamMap.MAP_LIMIT, FreeroamMap.MAP_LIMIT))
	hud.set_roam_tach()
	hud.show_center("", "", 0)


func exit_roam() -> void:
	if freeroam != null:
		freeroam.visible = false
	env.set_fog_range(240.0, 1650.0)   # 恢复城市雾距
	env.set_ground_visible(true)
	env.set_race_props_visible(true)
	state = ST.GARAGE
	for i in cars.size():
		cars[i].visual.visible = i == 0
	player.veh.on_lap_complete = Callable(self, "_on_lap_for_car").bind(0)
	reset_grid()
	refresh_menu_best()
	_update_garage_labels()
	hud.show_only("garage")


func start_race() -> void:
	var skills: Array = TrackData.DIFF_PRESETS[difficulty]["skills"]
	# 技能分配：最快的排杆位，玩家末位发车
	var slots := [[1, 0], [2, 1], [3, 2], [0, 3]]   # [carIdx, gridSlot]
	for i in range(1, cars.size()):
		if cars[i].ai != null:
			cars[i].ai.skill = skills[i - 1]
			cars[i].ai.reset()
	for slot in slots:
		var rec: CarRec = cars[slot[0]]
		rec.veh.track = track   # 从漫游返回时把物理查询切回赛道
		rec.veh.place_at(track.grid_pose(slot[1]))
		rec.finish_time = null
		rec.best_lap = null
		rec.last_lap = null
		rec.lap_stamp = 0.0
	for rec in cars:
		rec.visual.visible = true   # 离开车库，全部车回到赛道
	for i in tracks.size():
		tracks[i].visible = i == track_idx
	if freeroam != null:
		freeroam.visible = false
	env.set_race_props_visible(true)
	env.set_theme(TrackData.get_tracks()[track_idx]["theme"])   # 漫游可能改过主题
	player.veh.on_lap_complete = Callable(self, "_on_lap_for_car").bind(0)
	sim_time = 0.0
	player_finish_time = null
	fx.clear_skids()
	count_t = 3.99
	track.set_lamp_stage(0)
	lap_num_display = 1
	state = ST.COUNTDOWN
	_cam_init = false
	_intro_t = INTRO_DUR
	hud.show_only("hud")
	var diff_label: String = TrackData.DIFF_PRESETS[difficulty]["label"]
	hud.show_center("准备…", "%s · %d 圈" % [diff_label, total_laps], 1400)


func toggle_pause() -> void:
	if state == ST.RACING or state == ST.COUNTDOWN:
		_paused_from = state
		state = ST.PAUSED
		hud.show_only("pause")
		hud.show_center("", "", 0)
	elif state == ST.PAUSED:
		state = _paused_from
		hud.show_only("hud")


func to_garage() -> void:
	if state == ST.ROAM:
		exit_roam()
		return
	for rec in cars:
		rec.veh.track = track
	state = ST.GARAGE
	reset_grid()
	for i in cars.size():
		cars[i].visual.visible = i == 0
	refresh_menu_best()
	_update_garage_labels()
	hud.show_only("garage")


func rescue() -> void:
	if _rescue_cd > 0.0:
		return
	_rescue_cd = 1.0
	if state == ST.ROAM:
		var r := freeroam.query_rescue(player.veh.pos.x, player.veh.pos.z)
		player.veh.pos = r["pos"]
		player.veh.heading = r["ang"]
		player.veh.vf = 0.0
		player.veh.vl = 0.0
		player.veh.yaw_rate = 0.0
		player.veh.vy = 0.0
		player.veh.grounded = true
		return
	var p := player.veh
	var pt := track.pts[p.q_idx]
	p.pos = Vector3(pt.x, 0, pt.y)
	p.heading = track.ang[p.q_idx]
	p.vf = 0.0
	p.vl = 0.0
	p.yaw_rate = 0.0


## 漫游地图边界软限位（世界扩展后覆盖山海沙漠四区）
func _roam_bound(v: Vehicle) -> void:
	var lim := 2800.0
	if absf(v.pos.x) > lim:
		v.pos.x = clampf(v.pos.x, -lim, lim)
		v.vf *= 0.96
	if absf(v.pos.z) > lim:
		v.pos.z = clampf(v.pos.z, -lim, lim)
		v.vf *= 0.96


func reset_grid() -> void:
	for i in cars.size():
		cars[i].veh.place_at(track.grid_pose([3, 2, 1, 0][i]))
		_sync_visual(cars[i], 0.016)


# ================= 车型/赛道切换 =================

func set_car_model(id: String) -> void:
	if id == car_model_id:
		return
	car_model_id = id
	_save_settings()
	var rec := player
	rec.visual.queue_free()
	rec.visual = CarVisual.create(id, rec.team["color"], rec.team["accent"])
	add_child(rec.visual)
	# 不同车型有不同 stats：重建车辆物理实例，迁移位置与行驶状态
	var old := rec.veh
	var st: Dictionary = TrackData.model_by_id(id).get("stats", {})
	var veh := Vehicle.new(track, {
		"is_player": true,
		"top_speed": st.get("top", 92.0),
		"power": st.get("power", 60.0),
		"grip_scale": st.get("grip", 1.0),
		"brake": st.get("brake", 18.0),
		"accel_cap": st.get("accel", 11.0),
		"no_shift": st.get("no_shift", false),
	})
	veh.pos = old.pos
	veh.heading = old.heading
	veh.vf = old.vf
	veh.vl = old.vl
	veh.yaw_rate = old.yaw_rate
	veh.q_idx = old.q_idx
	veh.q_prev_idx = old.q_idx
	veh.cont_idx = old.cont_idx
	veh.last_floor = old.last_floor
	veh.laps_done = old.laps_done
	veh.grounded = old.grounded
	veh.on_lap_complete = Callable(self, "_on_lap_for_car").bind(rec.team_idx)
	rec.veh = veh
	rec.ai_cruise = null   # 旧巡航 AI 绑定的是旧车辆实例
	dual_mode = "top"     # 双模车默认极速模式
	_sync_visual(rec, 0.016)
	_update_garage_labels()


func set_track(idx: int) -> void:
	if idx == track_idx or idx < 0 or idx >= tracks.size():
		return
	track_idx = idx
	track = tracks[idx]
	for i in tracks.size():
		tracks[i].visible = (i == idx) and state != ST.GARAGE   # 车库里先不展示赛道
	env.set_theme(TrackData.get_tracks()[idx]["theme"])
	for rec in cars:
		rec.veh.track = track
		if rec.ai != null:
			rec.ai.track = track
		if rec.ai_cruise != null:
			rec.ai_cruise.track = track
	for i in cars.size():
		cars[i].veh.place_at(track.grid_pose([3, 2, 1, 0][i]))
		_sync_visual(cars[i], 0.016)
	fx.clear_skids()
	hud.init_minimap(track)
	_save_settings()
	_update_garage_labels()


# ================= 主帧 =================

func _process(dt_real: float) -> void:
	var dt: float = minf(dt_real, 0.1)
	_now_s += dt
	_rescue_cd = maxf(0.0, _rescue_cd - dt)
	_intro_t = maxf(0.0, _intro_t - dt)
	_handle_hotkeys()

	# 固定步长模拟
	_acc += dt
	var steps := 0
	while _acc >= H_STEP and steps < 10:
		_step_sim(H_STEP)
		_acc -= H_STEP
		steps += 1

	# 视觉同步 & 特效（每渲染帧）
	if state == ST.GARAGE:
		_sync_garage(dt)
	else:
		for rec in cars:
			_sync_visual(rec, dt)
	if state == ST.ROAM:
		_apply_roam_pitch(dt)
		fx.emit_skid(player.veh, (clampf(absf(player.veh.vl) / 8.0, 0.2, 1.0)
				if player.veh.drifting else 0.0))
		fx.surface_effects(player.veh)
	if state == ST.RACING or state == ST.FINISHED:
		for rec in cars:
			var v: Vehicle = rec.veh
			fx.emit_skid(v, (clampf(absf(v.vl) / 8.0, 0.2, 1.0) if v.drifting
					else (0.7 if (v.input_brake > 0.9 and absf(v.vf) > 22.0
					and v.surface == "road") else 0.0)))
			fx.surface_effects(v)
	env.follow_shadow(player.veh.pos)
	env.update_clouds(dt)
	if state == ST.ROAM:
		freeroam.update_signals(_now_s)

	# 音效参数
	var pv := player.veh
	var running := state == ST.RACING or state == ST.FINISHED \
			or state == ST.COUNTDOWN or state == ST.GARAGE or state == ST.ROAM
	var revving := state == ST.COUNTDOWN and pv.input_throttle > 0.0
	audio.update_engine(
		0.12 if state == ST.GARAGE else (0.62 + 0.18 * sin(_now_s * 9.0) if revving else pv.rpm_norm),
		pv.engine_load_smoothed, running and not audio.muted)
	var skid_vol := (clampf(pv.slip_amount * 1.2, 0.0, 1.0)
			* clampf(absf(pv.vf) / 16.0, 0.0, 1.0)) if state in [ST.RACING, ST.ROAM] else 0.0
	audio.update_skid(skid_vol)
	audio.update_wind(clampf(absf(pv.vf) / pv.top_speed, 0.0, 1.0))
	audio.update_rumble(state in [ST.RACING, ST.ROAM] and pv.surface != "road", absf(pv.vf))

	_consume_collisions()
	# 落地冲击（腾空后着陆）
	var land := pv.consume_land_impact()
	if land > 3.0:
		shake = minf(1.0, shake + clampf(land / 18.0, 0.0, 0.6))
		audio.collision(clampf(land / 20.0, 0.05, 0.7))
	_update_camera(dt)
	_update_hud(dt)

	# 调试：RR_DEBUG=1 时每秒打印一次状态（headless 验证用）
	if OS.get_environment("RR_DEBUG") != "":
		_dbg_tick -= dt
		if _dbg_tick <= 0.0:
			_dbg_tick = 1.0
			var parts := PackedStringArray()
			for rec in cars:
				parts.append("%s:%.1fm/s@(%.0f,%.0f,%.1f)%s" % [rec.team["name"].left(2),
						rec.veh.vf, rec.veh.pos.x, rec.veh.pos.z, rec.veh.pos.y,
						"空" if not rec.veh.grounded else ""])
			print("[dbg] t=%.1f state=%s %s" % [sim_time, ST.keys()[state], " ".join(parts)])


func _handle_hotkeys() -> void:
	if Input.is_action_just_pressed("rr_camera"):
		cam_mode = (cam_mode + 1) % CAM_MODE_NAMES.size()
		hud.show_center("镜头：" + CAM_MODE_NAMES[cam_mode], "", 800)
	if Input.is_action_just_pressed("rr_rescue"):
		rescue()
	if Input.is_action_just_pressed("rr_mute"):
		audio.ensure()
		audio.set_muted(not audio.muted)
		hud.show_center("已静音" if audio.muted else "声音开启", "", 700)
	if Input.is_action_just_pressed("rr_pause"):
		if state == ST.ROAM or state == ST.FINISHED:
			to_garage()
		elif state in [ST.RACING, ST.COUNTDOWN, ST.PAUSED]:
			toggle_pause()
	if Input.is_action_just_pressed("rr_start") and state == ST.GARAGE:
		start_from_garage()
	if Input.is_action_just_pressed("rr_dual"):
		_toggle_dual_mode()


func _step_sim(h: float) -> void:
	var s := state
	if s == ST.PAUSED or s == ST.GARAGE:
		return

	if s == ST.COUNTDOWN:
		var prev_t := count_t
		count_t -= h
		var stage := 0
		if count_t > 3.0:
			stage = 0
		elif count_t > 2.0:
			stage = 1
		elif count_t > 1.0:
			stage = 2
		elif count_t > 0.0:
			stage = 3
		else:
			stage = 4
		track.set_lamp_stage(stage)
		if count_t <= 3.0 and prev_t > 3.0:
			hud.countdown("3")
			audio.beep(430, 0.12, 0.22)
		if count_t <= 2.0 and prev_t > 2.0:
			hud.countdown("2")
			audio.beep(430, 0.12, 0.22)
		if count_t <= 1.0 and prev_t > 1.0:
			hud.countdown("1")
			audio.beep(430, 0.12, 0.22)
		if count_t <= 0.0:
			hud.countdown("GO!")
			audio.beep(870, 0.4, 0.26)
			state = ST.RACING
			hud.show_only("hud")
		# 引擎轰鸣但不移动
		var inp_c := _sample_input(h)
		player.veh.input_throttle = inp_c["throttle"]
		player.veh.input_brake = 0.0
		return

	# ROAM：只有玩家车，物理照常（立体物理对路网高度自动生效）
	if s == ST.ROAM:
		var inp_r := _sample_input(h)
		var pin := player.veh
		pin.input_throttle = inp_r["throttle"]
		pin.input_brake = inp_r["brake"]
		pin.input_steer = inp_r["steer"]
		pin.input_handbrake = inp_r["handbrake"]
		freeroam.vehicle_y = pin.pos.y
		pin.step(h)
		_roam_bound(pin)
		sim_time += h
		return

	# RACING / FINISHED 都持续模拟
	if s != ST.RACING and s != ST.FINISHED:
		return

	# 输入
	var inp := _sample_input(h)
	var pin := player.veh
	if pin.finished:
		if player.ai_cruise == null:
			player.ai_cruise = AIDriver.new(pin, track, {})
		player.ai_cruise.cruise()
	else:
		pin.input_throttle = inp["throttle"]
		pin.input_brake = inp["brake"]
		pin.input_steer = inp["steer"]
		pin.input_handbrake = inp["handbrake"]

	# AI 输入 + 橡皮筋
	var others := cars.map(func(c): return c.veh)
	for i in range(1, cars.size()):
		var rec: CarRec = cars[i]
		var gap_idx := rec.veh.cont_idx - player.veh.cont_idx
		var sec_gap := gap_idx * track.ds / 40.0   # 约 40 m/s 平均速度换算成秒
		rec.ai.rubber = -clampf(sec_gap * 0.012, -0.05, 0.06)
		rec.ai.update(h, others)

	# 物理步进
	for rec in cars:
		rec.veh.step(h)
	_resolve_car_collisions()

	# 计时
	sim_time += h
	var tms := sim_time * 1000.0

	# 完赛检测
	for rec in cars:
		if rec.finish_time == null and rec.veh.laps_done >= total_laps:
			rec.finish_time = tms
			if rec.team_idx == 0:
				_on_player_finished()


func _on_lap_for_car(nf: int, idx: int) -> void:
	var r: CarRec = cars[idx]
	if r.team_idx == 0:
		_on_lap_complete(nf)
		return
	var now_ms := sim_time * 1000.0
	r.last_lap = now_ms - r.lap_stamp
	r.lap_stamp = now_ms
	if r.best_lap == null or r.last_lap < r.best_lap:
		r.best_lap = r.last_lap


func _on_lap_complete(nf: int) -> void:
	var lap_ms: float = sim_time * 1000.0 - player.lap_stamp
	player.lap_stamp = sim_time * 1000.0
	player.last_lap = lap_ms
	var is_best := false
	if player.best_lap == null or lap_ms < player.best_lap:
		player.best_lap = lap_ms
		is_best = true
	if best_stored == null or lap_ms < best_stored:
		best_stored = lap_ms
		_save_settings()
	if nf < total_laps:
		var delta_sec = null
		if player.best_lap != null:
			delta_sec = lap_ms / 1000.0 - player.best_lap / 1000.0
		hud.flash_lap(nf, RRUtil.format_delta(delta_sec), is_best)
	lap_num_display = mini(nf + 1, total_laps)


func _on_player_finished() -> void:
	player_finish_time = sim_time * 1000.0
	player.veh.finished = true
	state = ST.FINISHED
	_build_results()
	var pos_num := _player_position()
	var text := "🏆 冠军！" if pos_num == 1 else "以第 %d 名完赛" % pos_num
	# 延迟展示，让玩家先看到冲线
	get_tree().create_timer(0.3).timeout.connect(
		func(): hud.show_center(text, "", 2600))


func _player_position() -> int:
	var positions := compute_positions()
	for i in positions.size():
		if positions[i]["is_player"]:
			return i + 1
	return 4


func compute_positions() -> Array:
	var arr: Array = []
	for c in cars:
		arr.append({
			"name": c.team["name"],
			"idx": c.team_idx,
			"is_player": c.team_idx == 0,
			"prog": c.veh.cont_idx + (100000.0 if c.finish_time != null else 0.0),
			"finish_time": c.finish_time,
			"best_lap": c.best_lap,
		})
	arr.sort_custom(func(a, b): return a["prog"] > b["prog"])
	return arr


func _build_results() -> void:
	var positions := compute_positions()
	var rows: Array = []
	for i in positions.size():
		var p: Dictionary = positions[i]
		rows.append({
			"pos": i + 1,
			"name": p["name"],
			"teamIdx": p["idx"],
			"isPlayer": p["is_player"],
			"time": RRUtil.format_time(p["finish_time"]) if p["finish_time"] != null else "进行中",
			"bestLap": RRUtil.format_time(p["best_lap"]) if p["best_lap"] != null else "--",
		})
	hud.show_results(rows)


func _resolve_car_collisions() -> void:
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			var a: Vehicle = cars[i].veh
			var b: Vehicle = cars[j].veh
			var dx := b.pos.x - a.pos.x
			var dz := b.pos.z - a.pos.z
			var d2 := dx * dx + dz * dz
			var rr_radius := 3.4
			if d2 > rr_radius * rr_radius or d2 < 1e-6:
				continue
			var d := sqrt(d2)
			var nx := dx / d
			var nz := dz / d
			var overlap := rr_radius - d
			a.pos.x -= nx * overlap * 0.5
			a.pos.z -= nz * overlap * 0.5
			b.pos.x += nx * overlap * 0.5
			b.pos.z += nz * overlap * 0.5
			var va := a.world_velocity()
			var vb := b.world_velocity()
			var rel := (vb.x - va.x) * nx + (vb.z - va.z) * nz
			if rel < 0.0:
				var imp := -rel * 0.62
				a.apply_world_impulse(-nx * imp, -nz * imp)
				b.apply_world_impulse(nx * imp, nz * imp)
				var strength := clampf(-rel / 14.0, 0.0, 1.0)
				if strength > 0.08:
					var mid := (a.pos + b.pos) * 0.5
					fx.car_bump(mid)
					var dist := camera.position.distance_to(mid)
					var involving_player := a.is_player or b.is_player
					var vol := strength * (1.0 if involving_player else clampf(1.0 - dist / 70.0, 0.0, 0.6))
					if vol > 0.04:
						audio.collision(vol * 0.9)
					if involving_player:
						shake = minf(1.0, shake + strength * 0.5)


func _consume_collisions() -> void:
	for rec in cars:
		var v: Vehicle = rec.veh
		if v.hit_impulse > 0.0:
			var strength := v.consume_hit()
			fx.wall_sparks(v.pos)
			var dist := camera.position.distance_to(v.pos)
			var vol := strength * (1.0 if v.is_player else clampf(1.0 - dist / 70.0, 0.0, 0.6))
			if vol > 0.05:
				audio.collision(vol)
			if v.is_player:
				shake = minf(1.0, shake + strength * 0.8)


# ================= 视觉同步 =================

func _sync_visual(rec: CarRec, dt: float) -> void:
	var v := rec.veh
	var vis := rec.visual
	vis.position = Vector3(v.pos.x, v.pos.y, v.pos.z)   # y 跟随路面海拔（漫游高架/坡道）
	vis.rotation.y = v.heading

	rec.roll_cur = RRUtil.damp(rec.roll_cur, clampf(v.g_lat * 0.045, -0.09, 0.09), 8.0, dt)
	rec.pitch_cur = RRUtil.damp(rec.pitch_cur, clampf(-v.g_long * 0.035, -0.07, 0.07), 8.0, dt)
	vis.body_pivot.rotation = Vector3(
		vis.body_pivot_rest.x + rec.pitch_cur,
		vis.body_pivot_rest.y,
		vis.body_pivot_rest.z + rec.roll_cur)
	vis.body_pivot.position = vis.body_pivot_rest_pos + Vector3(0, bob_offset(rec, spd_of(v)), 0)

	vis.animate(dt, v.vf, v.steer_vis, v.input_brake > 0.0 or v.input_handbrake)


func spd_of(v: Vehicle) -> float:
	return absf(v.vf)


## 车库状态：玩家车停上旋转展台，其余车隐藏；车身姿态/怠速动画照常
func _sync_garage(dt: float) -> void:
	_garage_angle += dt * 0.3
	if _garage != null and _garage.pivot != null:
		_garage.pivot.rotation.y = _garage_angle
	_sync_visual(player, dt)
	var gp := RRGarage.GARAGE_POS
	player.visual.position = gp + Vector3(0, RRGarage.PLATFORM_TOP, 0)
	player.visual.rotation.y = _garage_angle
	for i in range(1, cars.size()):
		cars[i].visual.visible = false


func bob_offset(rec: CarRec, spd: float) -> float:
	var v := rec.veh
	var bob := sin(_now_s * (5.0 + spd * 0.4) + rec.bob_phase) * minf(spd * 0.0016, 0.011)
	if v.surface == "curb":
		bob += sin(_now_s * 55.0) * 0.012
	elif v.surface == "grass":
		bob += sin(_now_s * 43.0) * 0.02 * minf(spd / 20.0, 1.0)
	return bob


## 漫游：车体贴合路面坡度，腾空时按垂直速度俯仰
func _apply_roam_pitch(dt: float) -> void:
	var v := player.veh
	var pitch: float
	if v.grounded:
		pitch = -atan(clampf(v.ground_slope_along, -0.5, 0.5))
	else:
		pitch = clampf(-v.vy * 0.045, -0.35, 0.22)
	player.visual.rotation.x = RRUtil.damp(player.visual.rotation.x, pitch, 9.0, dt)


# ================= 相机 =================

func _update_camera(dt: float) -> void:
	var pv := player.veh
	var f := pv.forward_dir()
	var spd_ratio := clampf(absf(pv.vf) / pv.top_speed, 0.0, 1.0)
	var want_fov := 63.0

	if state == ST.GARAGE:
		# 固定机位看展台（画面里车偏左，给右侧比赛面板留出视野），展台可拖动旋转
		var gp := RRGarage.GARAGE_POS
		camera.position = gp + Vector3(7.6, 2.9, 6.4)
		camera.look_at(gp + Vector3(2.1, 0.95, -0.9), Vector3.UP)
		camera.fov = RRUtil.damp(camera.fov, 42.0, 3.0, dt)
		_cam_init = false
		return

	if state == ST.FINISHED:
		var t := _now_s * 0.32
		camera.position = Vector3(
			pv.pos.x + cos(t) * 10.5,
			2.9 + sin(t * 0.6) * 0.7,
			pv.pos.z + sin(t) * 10.5)
		camera.look_at(Vector3(pv.pos.x, 0.9, pv.pos.z), Vector3.UP)
		want_fov = 55.0
	else:
		var mode := cam_mode
		if not _cam_init:
			# 车库在 y=-400，直接沿用 camera.position 会让相机从地下 400m
			# 一路 lerp 上来、穿过地面（"相机从地底下照上来"）。这里直接落位。
			_cam_pos = pv.pos - f * 8.2 + Vector3(0, 2.45, 0)
			_cam_look = pv.pos + f * 7.0 + Vector3(0, 1.1, 0)
			_cam_init = true
		if mode == 2:   # 车头盖
			_cam_pos = Vector3(pv.pos.x + f.x * 0.55,
					1.06 + absf(pv.g_lat) * 0.15,
					pv.pos.z + f.z * 0.55)
			_cam_look = pv.pos + f * 26.0
			want_fov = 72.0 + spd_ratio * 12.0
		else:
			var dist := 8.2 if mode == 0 else 5.9
			var height := 2.45 if mode == 0 else 1.95
			var back := pv.pos - f * dist + Vector3(0, height, 0)
			var lam := 1.0 - exp(-(4.6 + spd_ratio * 2.4) * dt)
			_cam_pos = _cam_pos.lerp(back, lam)
			var lead := pv.pos + f * (7.0 + spd_ratio * 6.0) + Vector3(0, 1.1, 0)
			_cam_look = _cam_look.lerp(lead, 1.0 - exp(-7.5 * dt))
			want_fov = 63.0 + spd_ratio * 14.0
		camera.position = _cam_pos
		camera.look_at(_cam_look, Vector3.UP)

		# 入场运镜：从车正上方 40m 俯视缓降到车后追车位。
		# 机位始终在车道正上方（不在楼群里穿行），落点即追车位，交接无跳变。
		if _intro_t > 0.0:
			var s01 := clampf(_intro_t / INTRO_DUR, 0.0, 1.0)
			var e := s01 * s01 * (3.0 - 2.0 * s01)          # smoothstep
			var high := pv.pos + Vector3(0, 40.0, 0) - f * 12.0
			camera.position = _cam_pos.lerp(high, e)
			camera.look_at(_cam_look.lerp(pv.pos + Vector3(0, 0.6, 0), e), Vector3.UP)
			want_fov = lerpf(want_fov, 74.0, e)

	# 抖动（撞击积累 + 草地颠簸）
	var rumble := clampf(absf(pv.vf) * 0.006, 0.0, 0.4) if pv.surface == "grass" else 0.0
	shake = maxf(shake * exp(-3.2 * dt), rumble)
	if shake > 0.002:
		var a := shake * 0.22
		camera.position += Vector3(
			(randf() - 0.5) * a,
			(randf() - 0.5) * a * 0.7,
			(randf() - 0.5) * a)
	camera.fov = RRUtil.damp(camera.fov, want_fov, 4.0, dt)


# ================= HUD =================

func _update_hud(dt: float) -> void:
	if state == ST.GARAGE:
		return
	var pv := player.veh
	var gear_label := str(pv.gear)
	if pv.no_shift:
		gear_label = "D"   # 电驱单速
	if state == ST.RACING and pv.vf < -0.5:
		gear_label = "R"
	elif state == ST.COUNTDOWN:
		gear_label = "N"
	# 仪表盘：档位进程比例 + 功能数字（比赛=本圈时间，漫游=行驶时长）
	var ratio := clampf(absf(pv.vf) / pv.top_speed, 0.0, 1.0)
	var lap_text := "--:--.--"
	if state == ST.RACING or state == ST.FINISHED:
		lap_text = RRUtil.format_time(sim_time * 1000.0 - player.lap_stamp)
	elif state == ST.ROAM:
		lap_text = RRUtil.format_time(sim_time * 1000.0)
	hud.draw_tach(pv.speed_kmh, gear_label, maxf(0.04, pv.rpm_norm), pv.drifting,
			ratio, lap_text)

	if state == ST.ROAM:
		# 漫游：只有转速表 + 整图小地图 + 车辆位置点
		hud.draw_minimap([{
			"x": pv.pos.x, "z": pv.pos.z, "heading": pv.heading,
			"color": TrackData.TEAM_ROSTER[0]["color"], "is_player": true,
		}])
		hud.set_wrong_way(false)
		return

	hud.update_pos(_player_position(), 4)

	_hud_tick -= dt
	if _hud_tick <= 0.0:
		_hud_tick = 0.12
		var current: float = (sim_time * 1000.0 - player.lap_stamp) if state == ST.RACING \
				else (player.last_lap if player.last_lap != null else 0.0)
		hud.update_timing({
			"lap_num": lap_num_display,
			"total_laps": total_laps,
			"current": current,
			"last": player.last_lap,
			"best": player.best_lap,
			"race_time": player_finish_time if player_finish_time != null else sim_time * 1000.0,
		})

	_standings_tick -= dt
	if _standings_tick <= 0.0 and state != ST.PAUSED:
		_standings_tick = 0.6
		var positions := compute_positions()
		if state == ST.RACING or state == ST.COUNTDOWN:
			hud.update_standings(positions.slice(0, 4))
		# 结算页打开期间刷新未完赛 AI 成绩
		if state == ST.FINISHED and cars.any(func(c): return c.finish_time == null):
			_build_results()

	var minimap_cars: Array = []
	for c in cars:
		minimap_cars.append({
			"x": c.veh.pos.x, "z": c.veh.pos.z,
			"heading": c.veh.heading,
			"color": TrackData.TEAM_ROSTER[c.team_idx]["color"],
			"is_player": c.team_idx == 0,
		})
	hud.draw_minimap(minimap_cars)

	hud.set_wrong_way(state == ST.RACING and pv.wrong_way_timer > 1.4)
