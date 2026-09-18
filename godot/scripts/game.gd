extends Node3D
## 整场游戏编排：场景装配 / 状态机 / 定步物理 / 相机 / 竞速判定
## （移植自 js/game.js）

enum ST { GARAGE, COUNTDOWN, RACING, PAUSED, FINISHED, ROAM, BATTLE }

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
var _hood_h := -1.0     # 车头盖视角锚高（按各车模型实际高度缓存，换车重算）
var dual_mode := "top"     # 双组别车的当前模式（accel 加速 / top 极速）
var _del_arm := false      # 删除自定义赛道的二次确认
var _rec_lap := []         # 走线录制：本圈样本 [{b, lat, hit}]
var _rec_tick := 0
var _input_clear := false   # 窗口失焦后封锁行驶输入，直到玩家重新按键（防丢键卡死）

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
		# 玩家车吃配件加成（每车独立）；AI 恒原厂数值
		if i == 0:
			st = _effective_stats(model, st)
		var veh := Vehicle.new(track, {
			"is_player": i == 0,
			"top_speed": st.get("top", 92.0),
			"power": st.get("power", 60.0),
			"grip_scale": st.get("grip", 1.0),
			"brake": st.get("brake", 18.0),
			"accel_cap": st.get("accel", 11.0),
			"no_shift": st.get("no_shift", false),
			"inertia_drift": TrackData.model_by_id(model).get("inertia_drift", false),
		})
		if i == 0:
			veh.drift_tire = _player_drift_hold()
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
	_apply_garage_display()
	day_cycle = DayCycle.new()
	add_child(day_cycle)
	day_cycle.setup(env, camera)
	_ensure_headlight()
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


## 走线录制：比赛模式每 3 帧采一个玩家样本（桶=赛道进度，lat=横向偏移，hit=撞墙）。
## 必须在碰撞消费之前调用 —— 撞墙帧的 hit_impulse 尚未被清零。
func _record_player_line() -> void:
	if state != ST.RACING:
		return
	_rec_tick += 1
	if _rec_tick % 3 != 0:
		return
	var pv := player.veh
	var trk_n := float(track.n)
	if trk_n <= 0.0:
		return
	var b := wrapi(int(round(pv.cont_idx / trk_n * float(RRLearnedLines.BUCKETS))),
			0, int(RRLearnedLines.BUCKETS))
	var hit := pv.hit_impulse > 0.015 or absf(pv.lat_off) > track.wall_lat - 0.3
	_rec_lap.append({"b": b, "lat": pv.lat_off, "hit": hit})


## 玩家过线：提交本圈样本进学习线（多圈自动融合 + 撞墙段绕开）
func _commit_player_lap() -> void:
	if _rec_lap.is_empty():
		return
	RRLearnedLines.record_lap(track.track_id, _rec_lap)
	_rec_lap.clear()


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


func _notification(what: int) -> void:
	# 失焦期间松开的键 Godot 收不到 keyup —— 键状态会永久卡在「按下」，
	# 表现为松手后车仍自动加速。失焦时封锁行驶输入并释放全部动作。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_input_clear = true
		for a in ["rr_throttle", "rr_brake", "rr_left", "rr_right", "rr_handbrake"]:
			Input.action_release(a)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		pass   # 恢复由 _input 里玩家真实按键触发


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_input_clear = false   # 玩家重新按键 → 解除封锁


func _unhandled_input(event: InputEvent) -> void:
	# 步行模式：鼠标相对位移 → 视角（鼠标已捕获）
	if on_foot and onfoot != null and event is InputEventMouseMotion \
			and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		onfoot.add_look(event.relative)
		return
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
		"rr_mute": [KEY_N],
		"rr_scope": [KEY_M],
		"rr_gun1": [KEY_1], "rr_gun2": [KEY_2], "rr_gun3": [KEY_3],
		"rr_gun4": [KEY_4], "rr_gun5": [KEY_5],
		"rr_pause": [KEY_P, KEY_ESCAPE],
		"rr_start": [KEY_ENTER],
		"rr_dual": [KEY_O],
		"rr_interact": [KEY_F],
		"rr_bomb": [KEY_SPACE],        # 大战场飞行投弹（驾车时仍为手刹）
		"rr_debug": [KEY_I, KEY_F3],   # macOS 上 F3 会被 Mission Control 吃掉
	}
	for action in defs:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	# 步行开火动作：鼠标左键
	if not InputMap.has_action("rr_fire"):
		InputMap.add_action("rr_fire")
		var fire_ev := InputEventMouseButton.new()
		fire_ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("rr_fire", fire_ev)


func _sample_input(dt: float) -> Dictionary:
	# 行驶输入直接采样物理键状态：action 状态机会被系统 echo 事件在
	# release 后重新拉起（长按 W 连发），或因失焦丢 keyup 卡死——
	# 两者都表现为「松手仍加速」。物理键状态不受这两种情况影响。
	var blocked := _input_clear
	var thr := false
	var brk := false
	var st_l := false
	var st_r := false
	var hb := false
	if not blocked:
		thr = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
		brk = Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		st_l = Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
		st_r = Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		hb = Input.is_physical_key_pressed(KEY_SPACE)
	var steer_target := 0.0
	if st_l:
		steer_target += 1.0
	if st_r:
		steer_target -= 1.0
	var rate := 10.0 if steer_target == 0.0 else Tuning.STEER_RATE
	_in_steer = move_toward(_in_steer, steer_target, rate * dt)
	return {
		"throttle": 1.0 if thr else 0.0,
		"brake": 1.0 if brk else 0.0,
		"steer": _in_steer,
		"handbrake": hb,
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
		coins = cf.get_value("settings", "coins", 0)
		npc_solid = cf.get_value("settings", "npc_solid", true)
		guns_owned = cf.get_value("guns", "owned", ["pistol"])
		gun_equipped = cf.get_value("guns", "equipped", "pistol")
		ammo_type = cf.get_value("guns", "ammo_type", "standard")
		battle_kills_total = cf.get_value("battle", "kills", 0)
		battle_wins = cf.get_value("battle", "wins", 0)
		plane_mode = cf.get_value("settings", "plane", false)
		parts_owned = cf.get_value("parts", "owned", {})
		parts_equipped = cf.get_value("parts", "equipped", {})
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
	cf.set_value("settings", "coins", coins)
	cf.set_value("settings", "npc_solid", npc_solid)
	cf.set_value("guns", "owned", guns_owned)
	cf.set_value("guns", "equipped", gun_equipped)
	cf.set_value("guns", "ammo_type", ammo_type)
	cf.set_value("battle", "kills", battle_kills_total)
	cf.set_value("battle", "wins", battle_wins)
	cf.set_value("settings", "plane", plane_mode)
	cf.set_value("parts", "owned", parts_owned)
	cf.set_value("parts", "equipped", parts_equipped)
	cf.set_value("records", "best_lap", best_stored)
	cf.save(SETTINGS_PATH)


# ================= 配件店 =================

var coins := 0                     # 金币：完赛按名次奖励，配件店消费
var parts_owned := {}              # model_id → Array[已购配件 id]
var parts_equipped := {}           # model_id → {slot: opt_id}
var shop_open := false             # 配件店界面开着（漫游中冻结车辆）
var npc: NpcTraffic                # 漫游 NPC：交通车 + 行人 + 警察
var npc_solid := true              # NPC 车与玩家实体碰撞（车库开关）
var onfoot: OnFoot                 # 下车人模式（第一人称持枪）
var on_foot := false               # 是否处于步行状态
var guns_owned: Array = ["pistol"] # 已购枪械（全局，数字键 1~N 直选）
var gun_equipped := "pistol"       # 当前手持枪械
var ammo_type := "standard"        # 弹药类型（弹药店购买/切换）
var gunshop_open := false          # 枪械店界面开着
var gunshop_from_roam := false
var player_hp := 100.0             # 步行状态血量（警车/直升机开枪扣血）
var _no_dmg_t := 0.0               # 未受击计时（6 秒后缓慢回血）

# ================= 大战场模式 =================

var bmap: BattleMap                # 独立战场地图（荒漠 500×400m）
var bf: RRBattleField              # 战斗管理器（两军 AI 士兵）
var battle_kills_total := 0        # 累计击杀（存档）
var battle_wins := 0               # 累计胜场（存档）
var _battle_respawn_t := 0.0       # 阵亡重生倒计时（>0 = 死亡等待）
var _battle_prev_theme := "country"  # 进场前主题（退场恢复）
var flying := false                # 玩家驾驶我方战机中
var _plane_was_down := false       # 我方战机被击落（重生提示用）

# ================= 漫游战机（车库可选，仅限自由漫游） =================

var plane_mode := false            # 车库选中战机（漫游专用，不能参赛）
var rplane := {}                   # 漫游战机状态 {pos,heading,pitch,roll,speed,throttle,landed,hint}
var roam_plane_vis: Node3D         # 战机模型（车库展示 + 漫游飞行同用）
var airport_traffic: AirportTraffic  # 机场氛围（客机起降 + 登机人流）
var _roam_vs := 0.0                # 升降率平滑（仪表）
var airliner_ride := false         # 正在乘班机飞行
var wheel_ride := false            # 正在乘摩天轮（第一人称观景）
var _wheel_gi := 0                 # 所乘吊舱序号
var cargo_state := "ready"         # 货运任务：ready 备货 / escape 逃脱中 / rewarded 已结算
var _cargo_last_day := 0           # 货物补充的日期标记
var cargo_heist := "none"          # 劫案流程：none / chase 追赶 / flee 逃脱中
var day_cycle: DayCycle            # 昼夜 + 天气
var _headlight: SpotLight3D        # 玩家车头灯（夜色自动点亮）


## 车型是否为惯性漂移车（漂移胎分区只对它们开放）
func _is_drift_model(model_id: String) -> bool:
	return TrackData.model_by_id(model_id).get("inertia_drift", false)


## 某车的装备表（缺省全原厂）
func _equipped(model_id: String) -> Dictionary:
	if not parts_equipped.has(model_id):
		parts_equipped[model_id] = {}
	return parts_equipped[model_id]


## 某车的已购配件集合（原厂件永远视为已拥有）
func _owned(model_id: String) -> Array:
	if not parts_owned.has(model_id):
		parts_owned[model_id] = []
	return parts_owned[model_id]


func _part_owned(model_id: String, opt_id: String) -> bool:
	return opt_id == "stock" or opt_id == "none" or _owned(model_id).has(opt_id)


## 基础 stats 叠加已装备配件（*_mul 乘 / *_add 加），返回可喂给 apply_stats 的字典
func _effective_stats(model_id: String, base: Dictionary) -> Dictionary:
	var st := base.duplicate()
	for slot in TrackData.PART_SLOTS:
		var sid: String = slot["id"]
		var eq: Dictionary = _equipped(model_id)
		if not eq.has(sid):
			continue
		var opt: Dictionary = TrackData.part_option(sid, eq[sid])
		for k in opt["stats"]:
			var val = opt["stats"][k]
			if k.ends_with("_mul"):
				st[k.trim_suffix("_mul")] = st.get(k.trim_suffix("_mul"), 1.0) * val
			elif k.ends_with("_add"):
				st[k.trim_suffix("_add")] = st.get(k.trim_suffix("_add"), 0.0) + val
			elif k == "drift_hold":
				pass   # 漂移胎滑移系数不经 stats，set_part 里直接写 veh.drift_tire
	return st


## 玩家车当前漂移胎滑移系数（未装=1.0）
func _player_drift_hold() -> float:
	var eq: Dictionary = _equipped(car_model_id)
	if eq.has("drift"):
		return TrackData.part_option("drift", eq["drift"]).get("stats", {}).get("drift_hold", 1.0)
	return 1.0


## 把当前配件效果热应用到玩家车（商店里买/换装立即生效）
func _apply_player_parts() -> void:
	var pv := player.veh
	var m: Dictionary = TrackData.model_by_id(car_model_id)
	var base: Dictionary = m.get("stats", {})
	if m.has("modes"):
		base = m["modes"][dual_mode]
	pv.apply_stats(_effective_stats(car_model_id, base))
	pv.drift_tire = _player_drift_hold()


func buy_part(slot: String, opt_id: String) -> bool:
	var opt: Dictionary = TrackData.part_option(slot, opt_id)
	if _part_owned(car_model_id, opt_id):
		equip_part(slot, opt_id)
		return true
	if coins < opt["price"]:
		return false
	coins -= opt["price"]
	_owned(car_model_id).append(opt_id)
	equip_part(slot, opt_id)
	_save_settings()
	return true


func equip_part(slot: String, opt_id: String) -> void:
	if not _part_owned(car_model_id, opt_id):
		return
	_equipped(car_model_id)[slot] = opt_id
	_save_settings()
	_apply_player_parts()


# ================= 枪械店 =================

func _gun_owned(gun_id: String) -> bool:
	return guns_owned.has(gun_id)


func buy_gun(gun_id: String) -> bool:
	if _gun_owned(gun_id):
		equip_gun(gun_id)
		return true
	var g: Dictionary = Guns.gun_by_id(gun_id)
	if coins < g["price"]:
		return false
	coins -= g["price"]
	guns_owned.append(gun_id)
	equip_gun(gun_id)
	_save_settings()
	return true


func equip_gun(gun_id: String) -> void:
	if not _gun_owned(gun_id):
		return
	if not guns_owned.has(gun_id):
		guns_owned.append(gun_id)
	gun_equipped = gun_id
	_save_settings()
	if onfoot != null:
		onfoot.set_gun(gun_id)


func open_gunshop() -> void:
	if state != ST.GARAGE and state != ST.ROAM:
		return
	gunshop_from_roam = state == ST.ROAM
	gunshop_open = gunshop_from_roam
	_refresh_gunshop_ui()
	hud.show_only("gunshop")


func close_gunshop() -> void:
	gunshop_open = false
	hud.set_shop_hint(false)
	if on_foot:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.show_only("roam" if gunshop_from_roam else "garage")


func _refresh_gunshop_ui() -> void:
	hud.refresh_gunshop(coins, guns_owned, gun_equipped, ammo_type)


# ================= 大战场模式 =================

## 进入大战场：独立荒漠地图，持枪步行参战（波次歼灭战 12 v 12）
func enter_battle() -> void:
	if state != ST.GARAGE:
		return
	audio.ensure()
	_battle_prev_theme = env._cur_theme
	hud.show_only("battle")
	for t in tracks:
		t.visible = false
	if freeroam != null:
		freeroam.visible = false
	if npc != null:
		npc.set_active(false)
	env.set_theme("desert")
	env.set_race_props_visible(false)
	env.set_fog_range(260.0, 900.0)   # 战场近雾：荒漠沙尘氛围
	env.set_ground_visible(true)      # 战场边界之外由全局面兜底地平
	fx.clear_skids()
	state = ST.BATTLE
	if bmap == null:
		bmap = BattleMap.new()
		add_child(bmap)
	bmap.visible = true
	if bf == null:
		bf = RRBattleField.new()
		add_child(bf)
		bf.setup(bmap, audio)
		bf.player_hit.connect(_on_bf_player_hit)
		bf.enemy_killed.connect(_on_bf_enemy_killed)
		bf.wave_started.connect(_on_bf_wave)
		bf.over.connect(_on_bf_over)
		bf.plane_down.connect(_on_bf_plane_down)
		bf.explosion_at.connect(_on_bf_explosion)
	if onfoot == null:
		onfoot = OnFoot.new()
		add_child(onfoot)
		onfoot.setup(bmap, bf, audio, camera)   # bmap/bf 顶替 freeroam/npc 位
		onfoot.set_ammo_type(ammo_type)
		onfoot.shoot_hit.connect(_on_foot_shot)
		onfoot.reload_done.connect(func(): audio.play_reload())
	# 战场内无载具：直接步行入场
	on_foot = false
	flying = false
	_plane_was_down = false
	onfoot.exit()
	player.visual.visible = false
	_in_steer = 0.0
	_cam_init = false
	_intro_t = 0.0
	_battle_respawn_t = 0.0
	player_hp = 100.0
	bf.start()
	_battle_enter_foot()
	hud.set_battle_top(bf.army_alive("ally"), bf.army_alive("enemy"),
			bf.wave, bf.kills, "战机 %d/%d" % [int(bf.ally_plane["hp"]),
			bf.PLANE_BOMBS])
	hud.set_board_hint(false)
	hud.show_center("大 战 场", "全歼 %d 名敌军即获胜 · C 滑铲 · F 登机轰炸"
			% (bf.ENEMY_WAVE * bf.TOTAL_WAVES), 3500)


## 战场步行入场（无载具版上下车切换）；at = Vector3.ZERO 时用基地出生点
func _battle_enter_foot(at: Vector3 = Vector3.ZERO) -> void:
	on_foot = true
	camera.near = 0.02   # 步行第一人称：贴脸枪模不被近裁剪面裁掉
	onfoot.set_gun(gun_equipped)
	var spawn := at
	if spawn == Vector3.ZERO:
		spawn = BattleMap.ALLY_SPAWN \
				+ Vector3(randf_range(-8.0, 8.0), 0, randf_range(-4.0, 4.0))
	onfoot.enter(spawn, PI)   # 朝北（-Z，敌军方向）
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.set_onfoot(true)
	hud.set_health(player_hp)
	hud.set_gun_name(Guns.gun_by_id(gun_equipped)["name"])
	hud.set_scope(false)


## 登上我方战机
func _board_plane() -> void:
	flying = true
	bf.player_flying = true
	on_foot = false
	onfoot.exit()
	hud.set_onfoot(false)
	hud.set_scope(false)
	hud.set_board_hint(false)
	hud.show_center("起飞",
			"W/S 油门 · A/D 或 ←/→ 转弯 · ↑ 推杆 ↓ 拉起 · 空格 投弹 · 落地减速后 F 下机",
			4000)


## 落地状态下机
func _exit_plane() -> void:
	var p: Dictionary = bf.ally_plane
	var alt: float = p["pos"].y - bf.bmap.terrain_height(p["pos"].x, p["pos"].z)
	if not p["landed"] or alt > 5.0:
		hud.show_center("无法下机", "先关油门贴地减速（S 键）", 1600)
		return
	flying = false
	bf.player_flying = false
	_battle_enter_foot(Vector3(p["pos"]) + Vector3(5.0, 0, 3.0))


## 退出战场回车库（恢复环境与界面）
func exit_battle() -> void:
	if bf != null:
		bf.active = false
		bf.player_flying = false
	if bmap != null:
		bmap.visible = false
	_battle_respawn_t = 0.0
	flying = false
	if on_foot:
		on_foot = false
		onfoot.exit()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		hud.set_onfoot(false)
		hud.set_scope(false)
	env.set_theme(_battle_prev_theme)
	env.set_race_props_visible(true)
	env.set_fog_range(240.0, 1650.0)
	state = ST.GARAGE
	for i in cars.size():
		cars[i].visual.visible = i == 0
	refresh_menu_best()
	_update_garage_labels()
	hud.show_only("garage")
	hud.show_center("", "", 0)


## 登上班机：起飞巡航至对面机场，落地自动下机
func _airliner_board(from_i: int) -> void:
	if not airport_traffic.begin_ride(from_i):
		return
	on_foot = false
	onfoot.exit()
	hud.set_onfoot(false)
	hud.set_scope(false)
	airliner_ride = true
	hud.show_center("登机 · 飞往" + airport_traffic.ride_dest_name(),
			"巡航约 1 分钟 · 落地后自动下机", 3500)


func _on_bf_player_hit(dmg: float) -> void:
	if not on_foot or _battle_respawn_t > 0.0:
		return
	player_hp = maxf(0.0, player_hp - dmg)
	_no_dmg_t = 0.0
	hud.damage_flash()
	hud.set_health(player_hp)
	if player_hp <= 0.0:
		_battle_downed()


func _battle_downed() -> void:
	coins = maxi(0, coins - 100)
	_save_settings()
	_battle_respawn_t = 3.0
	bf.player_alive = false
	onfoot.exit()
	hud.set_onfoot(false)
	hud.show_center("阵 亡", "医疗费 -100 金币 · 3 秒后基地重生", 3000)


func _on_bf_enemy_killed(by_player: bool) -> void:
	if by_player:
		coins += 50
		battle_kills_total += 1
		_save_settings()
	hud.set_battle_top(bf.army_alive("ally"), bf.army_alive("enemy"),
			bf.wave, bf.kills)


func _on_bf_wave(n: int) -> void:
	hud.set_battle_top(bf.army_alive("ally"), bf.army_alive("enemy"),
			bf.wave, bf.kills)
	if n > 1:
		hud.show_center("敌军第 %d 波增援！" % n, "顶住进攻", 2500)
		audio.beep(220, 0.3, 0.25)


func _on_bf_over(did_win: bool, _kills: int) -> void:
	if did_win:
		battle_wins += 1
		coins += 1500
		hud.show_center("胜　利", "敌军全歼 · 奖励 +1500 金币", 8000)
		audio.beep(870, 0.4, 0.26)
	else:
		coins += 200
		hud.show_center("战　败", "我方全军覆没 · 补给 +200 金币 · 按 Enter 返回", 8000)
		audio.beep(180, 0.5, 0.25)
	_save_settings()


func _on_bf_plane_down(enemy: bool, by_player: bool) -> void:
	if enemy:
		if by_player:
			coins += 200
			battle_kills_total += 1
			_save_settings()
			hud.show_center("击落敌机！", "奖励 +200 金币", 2500)
		else:
			hud.show_center("敌机坠毁", "", 1500)
	else:
		_plane_was_down = true
		hud.show_center("我方战机被击落",
				"%.0f 秒后基地补充新机" % bf.ALLY_PLANE_RESPAWN, 2500)


func _on_bf_explosion(pos: Vector3) -> void:
	var d: float = pos.distance_to(camera.position)
	if d < 180.0:
		shake = minf(1.0, shake + clampf(1.0 - d / 180.0, 0.12, 0.7))
		audio.collision(clampf(0.85 - d / 220.0, 0.2, 0.7))


func _on_gun_equip(gun_id: String) -> void:
	if _gun_owned(gun_id):
		equip_gun(gun_id)
		_refresh_gunshop_ui()
		return
	var g: Dictionary = Guns.gun_by_id(gun_id)
	if not buy_gun(gun_id):
		hud.show_center("金币不足", "还差 %d 金币" % (g["price"] - coins), 1500)
		return
	_refresh_gunshop_ui()


## 购买/使用弹药类型
func _on_ammo_equip(ammo_id: String) -> void:
	var a: Dictionary = Guns.ammo_by_id(ammo_id)
	if ammo_type == ammo_id:
		return
	if not guns_owned.has(ammo_id):
		if coins < a["price"]:
			hud.show_center("金币不足", "还差 %d 金币" % (a["price"] - coins), 1500)
			return
		coins -= a["price"]
		guns_owned.append(ammo_id)
		_save_settings()
	ammo_type = ammo_id
	_save_settings()
	if onfoot != null:
		onfoot.set_ammo_type(ammo_id)
	_refresh_gunshop_ui()


# ================= 车库绑定 =================

func _wire_menu() -> void:
	hud.btn_start.pressed.connect(start_from_garage)
	hud.btn_roam.pressed.connect(enter_roam)
	hud.btn_battle.pressed.connect(enter_battle)
	hud.btn_plane.pressed.connect(_toggle_plane_mode)
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
	hud.set_npc_solid_label(npc_solid)
	hud.btn_shop.pressed.connect(open_shop)
	hud.btn_carinfo.pressed.connect(open_carinfo)
	hud.btn_npc_solid.pressed.connect(func():
		npc_solid = not npc_solid
		if npc != null:
			npc.solid = npc_solid
		hud.set_npc_solid_label(npc_solid)
		_save_settings())
	hud.shop_equip.connect(_on_shop_equip)
	hud.shop_back.connect(close_shop)
	hud.btn_gunshop.pressed.connect(open_gunshop)
	hud.gun_equip.connect(_on_gun_equip)
	hud.ammo_equip.connect(_on_ammo_equip)
	hud.gunshop_back.connect(close_gunshop)


# ================= 配件店 / 车辆数据 =================

var shop_from_roam := false        # 从漫游实体店进入（关闭时回到漫游）
var _near_shop := false            # 漫游中是否在配件店门口


func open_shop() -> void:
	if state != ST.GARAGE and state != ST.ROAM:
		return
	gunshop_open = false
	shop_from_roam = state == ST.ROAM
	shop_open = shop_from_roam
	if shop_open and on_foot:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_shop_ui()
	hud.show_only("shop")


func open_carinfo() -> void:
	if state != ST.GARAGE:
		return
	hud.refresh_carinfo(_carinfo_header(), _carinfo_text())
	hud.show_only("carinfo")


func close_shop() -> void:
	shop_open = false
	hud.set_shop_hint(false)
	if on_foot:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)   # 步行中关店 → 回到锁定视角
	hud.show_only("roam" if shop_from_roam else "garage")


func _on_shop_equip(slot: String, opt_id: String) -> void:
	if _part_owned(car_model_id, opt_id):
		equip_part(slot, opt_id)
	else:
		var opt: Dictionary = TrackData.part_option(slot, opt_id)
		if not buy_part(slot, opt_id):
			hud.show_center("金币不足", "还差 %d 金币" % (opt["price"] - coins), 1500)
			return
	_refresh_shop_ui()


func _refresh_shop_ui() -> void:
	var m: Dictionary = TrackData.model_by_id(car_model_id)
	hud.refresh_shop(m["name"], coins, _equipped(car_model_id),
			_owned(car_model_id), _is_drift_model(car_model_id))


func _carinfo_header() -> String:
	return "当前车辆：%s" % TrackData.model_by_id(car_model_id)["name"]


## 车辆数据明细：基础（原厂）→ 当前（含配件），▲配件增益 ▼配件减益
func _carinfo_text() -> String:
	var m: Dictionary = TrackData.model_by_id(car_model_id)
	var base: Dictionary = m.get("stats", {})
	if m.has("modes"):
		base = m["modes"][dual_mode]
	var cur: Dictionary = _effective_stats(car_model_id, base)
	var lines := [
		"马力    %d → %d %s" % [roundi(base.get("power", 0) * 10.0),
			roundi(cur.get("power", 0) * 10.0), _arrow(cur.power, base.power)],
		"极速    %d km/h → %d km/h %s" % [roundi(base.get("top", 0) * 3.6),
			roundi(cur.get("top", 0) * 3.6), _arrow(cur.top, base.top)],
		"牵引    %.1f → %.1f m/s² %s" % [base.get("accel", 0.0),
			cur.get("accel", 0.0), _arrow(cur.accel, base.accel)],
		"抓地    %d%% → %d%% %s" % [roundi(base.get("grip", 1.0) * 100.0),
			roundi(cur.get("grip", 1.0) * 100.0), _arrow(cur.grip, base.grip)],
		"制动    %.1f → %.1f m/s² %s" % [base.get("brake", 0.0),
			cur.get("brake", 0.0), _arrow(cur.brake, base.brake)],
	]
	# 配件清单
	var eq: Dictionary = _equipped(car_model_id)
	var eq_lines := []
	for slot in TrackData.PART_SLOTS:
		var sid: String = slot["id"]
		if _is_drift_model(car_model_id) or sid != "drift":
			var oid: String = eq.get(sid, "stock" if sid != "drift" else "none")
			eq_lines.append("%s：%s" % [slot["name"], TrackData.part_option(sid, oid)["name"]])
	lines.append("")
	lines.append_array(eq_lines)
	return "\n".join(lines)


func _arrow(cur: float, base: float) -> String:
	if cur > base + 0.001:
		return "▲"
	if cur < base - 0.001:
		return "▼"
	return ""


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
	var tdesc: String = def["name"] + " · " + def["desc"]
	if def.has("fixed_laps"):
		tdesc += " · 单圈制"
		hud.set_laps_locked(true, def["fixed_laps"])
	else:
		hud.set_laps_locked(false, total_laps)
	hud.update_track_desc(tdesc)
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
	player.veh.apply_stats(_effective_stats(car_model_id, m))   # 配件加成同样作用于双模
	player.veh.drift_tire = _player_drift_hold()
	hud.show_center("⚡ %s" % m["label"], "", 1200)


# ================= 流程 =================

func start_from_garage() -> void:
	if plane_mode:
		hud.show_center("战机不能参赛", "战机仅限自由漫游 · 按自由漫游出发", 1800)
		return
	audio.ensure()
	start_race()


# ================= 漫游战机（车库/漫游） =================

## 夜色车头灯（挂在车模前部，随车型重建）
func _ensure_headlight() -> void:
	if _headlight != null and is_instance_valid(_headlight):
		return
	_headlight = SpotLight3D.new()
	_headlight.light_color = Color(1.0, 0.93, 0.78)
	_headlight.light_energy = 6.0
	_headlight.spot_range = 55.0
	_headlight.spot_angle = 38.0
	_headlight.position = Vector3(0, 0.75, 1.6)
	_headlight.rotation.x = -0.12
	player.visual.add_child(_headlight)


## 车库「漫游战机」开关
func _toggle_plane_mode() -> void:
	plane_mode = not plane_mode
	_save_settings()
	_apply_garage_display()


## 车库展示与按钮状态（战机模式：展台摆战机、禁比赛/配件/车辆数据）
func _apply_garage_display() -> void:
	if roam_plane_vis == null:
		roam_plane_vis = PlaneVisual.create("gold")
		add_child(roam_plane_vis)
	hud.btn_plane.text = "漫游战机：开" if plane_mode else "漫游战机：关"
	if plane_mode and state == ST.GARAGE:
		player.visual.visible = false
		roam_plane_vis.visible = true
		var gp := RRGarage.GARAGE_POS
		roam_plane_vis.position = gp + Vector3(0, RRGarage.PLATFORM_TOP + 1.1, 0)
		hud.btn_start.disabled = true
		hud.btn_start.text = "战机不能参赛"
		hud.btn_shop.disabled = true
		hud.btn_carinfo.disabled = true
		hud.btn_roam.text = "驾 机 漫 游"
	else:
		roam_plane_vis.visible = false
		if state == ST.GARAGE:
			player.visual.visible = true
		hud.btn_start.disabled = false
		hud.btn_start.text = "开 始 比 赛"
		hud.btn_shop.disabled = false
		hud.btn_carinfo.disabled = false
		hud.btn_roam.text = "自 由 漫 游"
	var car: Dictionary = TrackData.model_by_id(car_model_id)
	var info: Dictionary = TrackData.AIRCRAFT
	if plane_mode:
		hud.update_car_label(info["name"], info["desc"])
	else:
		var cls: Dictionary = TrackData.CAR_CLASSES.get(
				car.get("class", "combustion"), {})
		hud.update_car_label(car["name"], car["desc"]
				+ (" · 组别：%s" % cls["name"] if not cls.is_empty() else ""))


## 漫游战机状态复位（进场时摆在广场北侧路面）
func _roam_plane_reset() -> void:
	rplane = {
		"pos": Vector3.ZERO, "heading": PI, "pitch": 0.0, "roll": 0.0,
		"speed": 0.0, "throttle": 0.0, "landed": true, "hint": -1,
	}
	# 城市机场停机坪出发（跑道正对，推油门即起飞）
	var o: Vector2 = FreeroamMap.AIRPORT_POS
	var fwd := Vector2(sin(FreeroamMap.AIRPORT_HEADING),
			cos(FreeroamMap.AIRPORT_HEADING))
	var right := Vector2(cos(FreeroamMap.AIRPORT_HEADING),
			-sin(FreeroamMap.AIRPORT_HEADING))
	var apron: Vector2 = o + fwd * (-180.0) + right * 190.0
	var q: Dictionary = freeroam.query(apron.x, apron.y, -1)
	rplane["pos"] = Vector3(apron.x, float(q["height"]) + 1.15, apron.y)
	rplane["heading"] = FreeroamMap.AIRPORT_HEADING
	rplane["ground"] = float(q["height"]) + 3.5
	if roam_plane_vis == null:
		roam_plane_vis = PlaneVisual.create("gold")
		add_child(roam_plane_vis)
	roam_plane_vis.visible = true
	_roam_plane_sync()


func _roam_plane_sync() -> void:
	roam_plane_vis.position = rplane["pos"]
	roam_plane_vis.rotation = Vector3(-float(rplane["pitch"]),
			float(rplane["heading"]), float(rplane["roll"]))
	roam_plane_vis.set_throttle(float(rplane["throttle"]))
	roam_plane_vis.set_gear(rplane["landed"])


## 漫游飞行物理（与大战场同款街机模型；W/S 油门 · A/D 或 ←/→ 转向 · ↑推杆 ↓拉起）
func _roam_plane_step(dt: float) -> void:
	if rplane.is_empty():
		return
	var p := rplane
	var prev_y: float = float(p["pos"].y)
	if p["landed"]:
		p["throttle"] = 0.0
		if Input.is_physical_key_pressed(KEY_W):
			p["throttle"] = 1.0
		if p["throttle"] > 0.9:
			p["landed"] = false
			p["speed"] = 28.0
		else:
			p["speed"] = 0.0
			_roam_plane_sync()
			return
	else:
		if Input.is_physical_key_pressed(KEY_W):
			p["throttle"] = minf(1.0, float(p["throttle"]) + 0.55 * dt)
		if Input.is_physical_key_pressed(KEY_S):
			p["throttle"] = maxf(0.0, float(p["throttle"]) - 0.55 * dt)
	# 转向 + 压杆
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_A) \
			or Input.is_physical_key_pressed(KEY_LEFT):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_RIGHT):
		turn -= 1.0
	p["heading"] = float(p["heading"]) + turn * 1.05 * dt
	p["roll"] = lerpf(float(p["roll"]), -turn * 0.55, 1.0 - exp(-5.0 * dt))
	# 俯仰：↑ 推杆低头 / ↓ 拉杆爬升
	var pitch_in := 0.0
	if Input.is_physical_key_pressed(KEY_UP):
		pitch_in -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		pitch_in += 1.0
	if pitch_in != 0.0:
		p["pitch"] = clampf(float(p["pitch"]) + pitch_in * 0.9 * dt,
				-0.55, 0.6)
	else:
		p["pitch"] = move_toward(float(p["pitch"]), 0.0, 0.35 * dt)
	# 速度：油门目标（怠速滑行 16 → 可减到落地线以下）+ 爬升掉速
	var target_spd := 16.0 + 69.0 * float(p["throttle"]) \
			- sin(float(p["pitch"])) * 14.0
	p["speed"] = clampf(move_toward(float(p["speed"]), target_spd,
			20.0 * dt), 12.0, 93.0)
	# 位移
	var fwd := Vector3(sin(float(p["heading"])), 0, cos(float(p["heading"])))
	p["pos"] = Vector3(p["pos"]) \
			+ fwd * float(p["speed"]) * cos(float(p["pitch"])) * dt
	p["pos"] = Vector3(p["pos"]) \
			+ Vector3(0, sin(float(p["pitch"])), 0) * float(p["speed"]) * dt
	p["pos"] = Vector3(clampf(p["pos"].x, -FreeroamMap.WORLD_LIMIT,
			FreeroamMap.WORLD_LIMIT), p["pos"].y,
			clampf(p["pos"].z, -FreeroamMap.WORLD_LIMIT,
			FreeroamMap.WORLD_LIMIT))
	# 地面高度 + 最低高度钳制
	var q: Dictionary = freeroam.query(p["pos"].x, p["pos"].z, p["hint"], p["pos"].y)
	p["hint"] = q["idx"]
	var ground: float = float(q["height"]) + 3.5
	p["ground"] = ground
	if p["pos"].y < ground:
		p["pos"] = Vector3(p["pos"].x, ground, p["pos"].z)
		p["pitch"] = maxf(float(p["pitch"]), 0.0)
	p["landed"] = p["pos"].y - ground < 0.6 and float(p["speed"]) < 18.0
	if p["landed"]:
		p["speed"] = maxf(0.0, float(p["speed"]) - 26.0 * dt)
	# 低空楼体粗碰撞（<26m 时从 OBB 推出）
	if p["pos"].y - ground < 26.0:
		for ob in freeroam.obstacles_box:
			var dx: float = p["pos"].x - ob["c"].x
			var dz: float = p["pos"].z - ob["c"].y
			if dx * dx + dz * dz > 8100.0:
				continue
			var ca: float = cos(ob["rot"])
			var sa: float = sin(ob["rot"])
			var lx: float = ca * dx + sa * dz
			var lz: float = -sa * dx + ca * dz
			var px: float = ob["hx"] + 2.0 - absf(lx)
			var pz: float = ob["hz"] + 2.0 - absf(lz)
			if px > 0.0 and pz > 0.0:
				if px < pz:
					lx = signf(lx) * (ob["hx"] + 2.0)
				else:
					lz = signf(lz) * (ob["hz"] + 2.0)
				p["pos"] = Vector3(ob["c"].x + ca * lx - sa * lz,
						p["pos"].y, ob["c"].y + sa * lx + ca * lz)
	_roam_vs = lerpf(_roam_vs, (float(p["pos"].y) - prev_y) / dt,
			1.0 - exp(-6.0 * dt))
	_roam_plane_sync()


## 登机/下机（漫游）
func _roam_board_plane() -> void:
	on_foot = false
	onfoot.exit()
	hud.set_onfoot(false)
	hud.set_scope(false)
	hud.show_center("起飞",
			"W/S 油门 · A/D 或 ←/→ 转弯 · ↑ 推杆 ↓ 拉起 · F 落地后下机", 3500)


func _roam_exit_plane() -> void:
	var alt: float = float(rplane["pos"].y) - float(rplane["ground"])
	if not rplane["landed"] or alt > 5.0:
		hud.show_center("无法下机", "先关油门贴地减速（S 键）", 1600)
		return
	var side := Vector3(sin(float(rplane["heading"]) + PI * 0.5), 0,
			cos(float(rplane["heading"]) + PI * 0.5))
	on_foot = true
	camera.near = 0.02
	onfoot.set_gun(gun_equipped)
	onfoot.enter(Vector3(rplane["pos"]) + side * 5.0, float(rplane["heading"]))
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.set_onfoot(true)
	hud.set_health(player_hp)


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
	# 雾终点必须落在相机远裁剪面（2800）之内，否则远景在雾还没浓起来时
	# 就被硬裁掉，地平线是一条硬边
	env.set_fog_range(700.0, 2700.0)
	fx.clear_skids()                   # 上一场比赛的胎痕不该铺到城市街道上
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
	freeroam.reset_garage()   # 卷帘门落回：出生在车库内，踩油门顶门出发
	_in_steer = 0.0
	_cam_init = false
	_intro_t = 0.0   # 漫游直达：不要入场运镜，出生即车库内追尾视角，油门就走出门
	hud.init_roam_minimap(freeroam.minimap_tex,
			Vector2(-FreeroamMap.MAP_LIMIT, -FreeroamMap.MAP_LIMIT),
			Vector2(FreeroamMap.MAP_LIMIT, FreeroamMap.MAP_LIMIT))
	hud.set_map_marker(FreeroamMap.SHOP_POS.x, FreeroamMap.SHOP_POS.y, "店")
	hud.add_map_marker(FreeroamMap.GUNSHOP_POS.x, FreeroamMap.GUNSHOP_POS.y, "枪")
	hud.set_roam_tach()
	# NPC 交通 + 行人 + 警察
	if npc == null:
		npc = NpcTraffic.new()
		add_child(npc)
		npc.setup(freeroam, hud)
		npc.busted.connect(_on_npc_busted)
		npc.heli_fire.connect(func(): shake = maxf(shake, 0.5))
		npc.police_shot.connect(_on_police_shot)
	npc.solid = npc_solid
	npc.set_active(true)
	if onfoot == null:
		onfoot = OnFoot.new()
		add_child(onfoot)
		onfoot.setup(freeroam, npc, audio, camera)
		onfoot.set_ammo_type(ammo_type)
		onfoot.shoot_hit.connect(_on_foot_shot)
		onfoot.reload_done.connect(func(): pass)
		onfoot.reload_done.connect(func(): audio.play_reload())
	# 开局在车内（清除可能的步行残留）
	on_foot = false
	if onfoot != null:
		onfoot.exit()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hud.set_onfoot(false)
	hud.show_center("", "", 0)
	# 机场氛围：客机起降 + 登机人流（含远方城市机场）
	if airport_traffic == null:
		airport_traffic = AirportTraffic.new()
		add_child(airport_traffic)
		airport_traffic.setup([
			{"origin": FreeroamMap.AIRPORT_POS, "heading": FreeroamMap.AIRPORT_HEADING},
			{"origin": FreeroamMap.FAR_CITY_POS + Vector2(760.0, -620.0),
					"heading": FreeroamMap.FAR_CITY_HEADING},
		], freeroam)
	airport_traffic.set_process(true)
	hud.add_map_marker(FreeroamMap.AIRPORT_POS.x, FreeroamMap.AIRPORT_POS.y, "机")
	# 战机模式：机场停机坪出发（W 推油门起飞）
	if plane_mode:
		_roam_plane_reset()
		player.visual.visible = false
		hud.set_plane_panel(true)
		hud.show_center("漫游战机",
				"W 推油门起飞 · A/D 或 ←/→ 转弯 · ↑ 推杆 ↓ 拉起 · F 落地后下机",
				4000)
	else:
		hud.set_plane_panel(false)


## 地标交互（摩天轮乘坐 / 电视塔观景电梯）——返回 true 表示 F 已消费
func _landmark_interact() -> bool:
	if not on_foot or freeroam == null:
		return false
	if wheel_ride:
		wheel_ride = false
		onfoot.enter(freeroam.wheel_board_pos() + Vector3(0, 0.1, 0),
				onfoot.yaw)
		hud.set_board_hint(false)
		hud.show_center("已下摩天轮", "", 1200)
		return true
	var p := onfoot.pos
	# 电视塔底 → 观景电梯上塔（基座半宽 23，站在基座边即可按）
	if p.y < 50.0 and Vector2(p.x - 90, p.z - 90).length() < 30.0:
		onfoot.enter(freeroam.tower_deck_pos(), onfoot.yaw)
		hud.show_center("云顶之针 · 观景台", "166m 塔顶环视全城 · 再按 F 下塔",
				2400)
		return true
	# 塔顶 → 下塔
	if p.y > 100.0 and Vector2(p.x - 90, p.z - 90).length() < 20.0:
		onfoot.enter(freeroam.tower_base_pos(), onfoot.yaw)
		hud.show_center("已返回地面", "", 1200)
		return true
	# 摩天轮登舱
	if p.distance_to(freeroam.wheel_board_pos()) < 14.0:
		_wheel_gi = freeroam.lowest_gondola()
		wheel_ride = true
		onfoot.pos = freeroam.gondola_seat(_wheel_gi)
		hud.show_center("湖畔之眼 · 摩天轮", "全景观光中 · 按 F 随时下轮", 2400)
		return true
	return false


func _toggle_on_foot() -> void:
	var v := player.veh
	if not on_foot:
		if absf(v.vf) > 2.0:
			hud.show_center("先停车再下车", "", 900)
			return
		on_foot = true
		camera.near = 0.02   # 步行第一人称：贴脸的枪模不被近裁剪面裁掉
		onfoot.set_gun(gun_equipped)
		v.input_throttle = 0.0
		v.input_brake = 1.0
		v.vf = 0.0
		var side := Vector3(cos(v.heading), 0, -sin(v.heading))
		onfoot.enter(v.pos + side * 2.2, v.heading)
		player.visual.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		hud.set_onfoot(true)
		hud.show_center("", "", 0)
	else:
		if onfoot.pos.distance_to(v.pos) > 3.5:
			hud.show_center("离车辆太远", "", 900)
			return
		_enter_car_from_foot()


func _enter_car_from_foot() -> void:
	on_foot = false
	onfoot.exit()
	camera.near = 0.8   # 恢复驾车相机近面
	player.visual.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hud.set_onfoot(false)
	hud.set_scope(false)


func _select_gun(gun_id: String) -> void:
	if not _gun_owned(gun_id) or gun_equipped == gun_id:
		return
	gun_equipped = gun_id
	_save_settings()
	onfoot.set_gun(gun_id)
	hud.set_gun_name(Guns.gun_by_id(gun_id)["name"])


func _on_foot_shot(kind: String, idx: int, point: Vector3, dmg: float = 20.0) -> void:
	if OS.get_environment("RR_DBG_SHOT") != "":
		print("[shotdbg] 命中 kind=%s idx=%d dmg=%.0f" % [kind, idx, dmg])
	if state == ST.BATTLE and bf != null:
		bf.player_shot(kind, idx, dmg)
		return
	if kind == "ped":
		npc.kill_ped(idx)
	elif kind == "traffic":
		npc.damage_traffic(idx, dmg)
	elif kind == "police":
		npc.damage_police(idx, dmg)


func _on_police_shot(dmg: float) -> void:
	if not on_foot:
		return
	player_hp = maxf(0.0, player_hp - dmg)
	_no_dmg_t = 0.0
	hud.damage_flash()
	hud.set_health(player_hp)
	if player_hp <= 0.0:
		_downed_on_foot()


func _downed_on_foot() -> void:
	coins = maxi(0, coins - 300)
	_save_settings()
	player_hp = 100.0
	_enter_car_from_foot()
	# 车辆拖回最近道路并清除通缉
	if npc != null:
		npc._clear_wanted()
		hud.set_wanted(false, 0.0)
	var rq: Dictionary = freeroam.query_rescue(player.veh.pos.x, player.veh.pos.z)
	player.veh.place_at({"pos": rq["pos"], "heading": rq["ang"], "idx": null})
	_sync_visual(player, 0.016)
	hud.show_center("重伤被捕", "医疗费 -300 金币", 3000)


func _on_npc_busted(fine: int) -> void:
	coins = maxi(0, coins - fine)
	_save_settings()
	hud.show_center("被警察逮捕", "罚金 -%d 金币（现有 %d）" % [fine, coins], 3000)


func exit_roam() -> void:
	player.visual.rotation.x = 0.0   # 漫游里写过车身俯仰角，不复位会一直歪着
	fx.clear_skids()
	if freeroam != null:
		freeroam.visible = false
	if npc != null:
		npc.set_active(false)
		hud.set_wanted(false, 0.0)
	if on_foot:
		on_foot = false
		onfoot.exit()
		player.visual.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		hud.set_onfoot(false)
	if gunshop_open:
		gunshop_open = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if plane_mode:
		if roam_plane_vis != null:
			roam_plane_vis.visible = false
		hud.set_plane_panel(false)
		rplane.clear()
	if airliner_ride:
		airliner_ride = false
		if airport_traffic != null:
			airport_traffic.abort_ride()
	if airport_traffic != null:
		airport_traffic.set_process(false)
	audio.set_pursuit_audio(false, 999.0, false, 999.0)   # 警笛/旋翼停止
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
	total_laps = TrackData.get_tracks()[track_idx].get("fixed_laps", total_laps)
	var skills: Array = TrackData.DIFF_PRESETS[difficulty]["skills"]
	# 技能分配：最快的排杆位，玩家末位发车
	var slots := [[1, 0], [2, 1], [3, 2], [0, 3]]   # [carIdx, gridSlot]
	for i in range(1, cars.size()):
		if cars[i].ai != null:
			cars[i].ai.skill = skills[i - 1]
			# 轻松模式：AI 不学玩家走线，用自己的简单路线（中线 + 弯心切弯）
			cars[i].ai.set_learned(difficulty != "easy")
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
	_rec_lap.clear()
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
	_hood_h = -1.0   # 模型高度变了，车头盖锚高下帧重算
	var rec := player
	rec.visual.queue_free()
	rec.visual = CarVisual.create(id, rec.team["color"], rec.team["accent"])
	add_child(rec.visual)
	if _headlight != null:
		_headlight = null
		_ensure_headlight()
	# 不同车型有不同 stats：重建车辆物理实例，迁移位置与行驶状态
	# 玩家车吃自己名下配件的加成
	var old := rec.veh
	var st: Dictionary = _effective_stats(id, TrackData.model_by_id(id).get("stats", {}))
	var veh := Vehicle.new(track, {
		"is_player": true,
		"top_speed": st.get("top", 92.0),
		"power": st.get("power", 60.0),
		"grip_scale": st.get("grip", 1.0),
		"brake": st.get("brake", 18.0),
		"accel_cap": st.get("accel", 11.0),
		"no_shift": st.get("no_shift", false),
		"inertia_drift": TrackData.model_by_id(id).get("inertia_drift", false),
	})
	veh.drift_tire = _player_drift_hold()
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
	# 战场里阴影跟随步行玩家/战机（车藏在别处）
	if state == ST.BATTLE and bf != null and flying:
		env.follow_shadow(bf.ally_plane["pos"])
	else:
		env.follow_shadow(onfoot.pos if state == ST.BATTLE else player.veh.pos)
	# 昼夜 + 天气推进（所有模式共享同一片天；车库初始页算室内，
	# 天气在背后照常演变但不渲染——雨雪粒子/灰化/浓雾不进初始画面）
	if day_cycle != null:
		env.underground = camera.position.y < -2.0
		day_cycle.indoor = state == ST.GARAGE
		day_cycle.advance(dt)
		day_cycle.apply(env)
		if _headlight != null and is_instance_valid(_headlight):
			_headlight.visible = day_cycle.night_f > 0.4 \
					and not on_foot and state != ST.GARAGE
		hud.update_clock(day_cycle.clock_text(), day_cycle.phase_text(),
				day_cycle.weather_text())
		hud.set_clock_visible(state != ST.GARAGE)
		if day_cycle.day_index > _cargo_last_day:
			_cargo_last_day = day_cycle.day_index
			if cargo_state != "escape" and airport_traffic != null:
				airport_traffic.respawn_cargo()
				cargo_state = "ready"
	env.update_clouds(dt)
	if state == ST.ROAM:
		freeroam.update_signals(_now_s)
		freeroam.update_landmarks(dt)
		freeroam.resolve_obstacles(player.veh)   # 楼房/桥墩碰撞（路边无空气墙）

	# 音效参数
	var pv := player.veh
	var running := state == ST.RACING or state == ST.FINISHED \
			or state == ST.COUNTDOWN or state == ST.GARAGE or state == ST.ROAM
	var revving := state == ST.COUNTDOWN and pv.input_throttle > 0.0
	var rpm_feed: float = pv.rpm_norm + (0.12 if pv.nitro_active
			and pv.nitro > 0.0 else 0.0)
	audio.update_engine(
		0.12 if state == ST.GARAGE else (0.62 + 0.18 * sin(_now_s * 9.0) if revving else rpm_feed),
		pv.engine_load_smoothed, running and not audio.muted)
	var skid_vol := (clampf(pv.slip_amount * 1.2, 0.0, 1.0)
			* clampf(absf(pv.vf) / 16.0, 0.0, 1.0)) if state in [ST.RACING, ST.ROAM] else 0.0
	audio.update_skid(skid_vol)
	audio.update_wind(clampf(absf(pv.vf) / pv.top_speed, 0.0, 1.0))
	# 漫游战机：风噪按空速（车引擎保持怠速不干扰）
	if state == ST.ROAM and plane_mode and not on_foot and not rplane.is_empty():
		audio.update_wind(clampf(float(rplane["speed"]) / 93.0, 0.0, 1.0))
	audio.update_rumble(state in [ST.RACING, ST.ROAM] and pv.surface != "road", absf(pv.vf))

	_record_player_line()
	_consume_collisions()
	# 落地冲击（腾空后着陆）
	var land := pv.consume_land_impact()
	if land > 3.0:
		shake = minf(1.0, shake + clampf(land / 18.0, 0.0, 0.6))
		audio.collision(clampf(land / 20.0, 0.05, 0.7))
	_update_camera(dt)
	_update_hud(dt)
	# 漫游战机仪表盘逐帧刷新
	if state == ST.ROAM and plane_mode and not on_foot and not rplane.is_empty():
		var hdg := fposmod(540.0 - rad_to_deg(float(rplane["heading"])), 360.0)
		var rpm_n := 0.12 + 0.88 * float(rplane["throttle"]) \
				if not rplane["landed"] else 0.0
		hud.update_plane_panel(float(rplane["speed"]) * 3.6,
				float(rplane["pos"].y), _roam_vs, hdg,
				float(rplane["pitch"]), float(rplane["roll"]),
				float(rplane["throttle"]), rpm_n, rplane["landed"])

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
	# 左键开门：下车后靠近关闭的门，左键开门（同时屏蔽枪击）
	if on_foot and state == ST.ROAM and freeroam != null \
			and freeroam.doors.size() > 0 \
			and freeroam.nearest_closed_door(onfoot.pos, 4.5) >= 0 \
			and Input.is_action_just_pressed("rr_fire"):
		freeroam.open_door(freeroam.nearest_closed_door(onfoot.pos, 4.5))
	if Input.is_action_just_pressed("rr_debug"):
		hud.toggle_debug()
	if Input.is_action_just_pressed("rr_camera"):
		if on_foot and onfoot != null \
				and (state == ST.ROAM or state == ST.BATTLE):
			onfoot.try_slide()   # 步行时 C = 滑铲
		else:
			cam_mode = (cam_mode + 1) % CAM_MODE_NAMES.size()
			hud.show_center("镜头：" + CAM_MODE_NAMES[cam_mode], "", 800)
	if Input.is_action_just_pressed("rr_rescue") and state != ST.BATTLE \
			and not (plane_mode and state == ST.ROAM and not on_foot):
		rescue()
	if Input.is_action_just_pressed("rr_scope") and on_foot \
			and (state == ST.ROAM or state == ST.BATTLE):
		onfoot.toggle_scope()
		hud.set_scope(onfoot.scoped)
	if Input.is_action_just_pressed("rr_mute"):
		audio.ensure()
		audio.set_muted(not audio.muted)
		hud.show_center("已静音" if audio.muted else "声音开启", "", 700)
	if Input.is_action_just_pressed("rr_pause"):
		if state == ST.ROAM and shop_open:
			close_shop()   # 漫游店里 Esc/P 先关店，不直接回车库
		elif state == ST.ROAM and gunshop_open:
			close_gunshop()
		elif state == ST.ROAM or state == ST.FINISHED:
			to_garage()
		elif state == ST.BATTLE:
			exit_battle()
		elif state in [ST.RACING, ST.COUNTDOWN, ST.PAUSED]:
			toggle_pause()
	if Input.is_action_just_pressed("rr_interact") and state == ST.ROAM \
			and not shop_open and not gunshop_open:
		# 班机舱门优先：站在航站楼旁的班机舱门边即登机
		var airliner_i: int = -1
		if on_foot and airport_traffic != null:
			airliner_i = airport_traffic.near_service_door(onfoot.pos)
		if airliner_i >= 0:
			_airliner_board(airliner_i)
		elif _landmark_interact():
			pass
		else:
			_toggle_on_foot()
	if state == ST.BATTLE and Input.is_action_just_pressed("rr_interact"):
		if flying:
			_exit_plane()
		elif bf != null and bf.ally_plane["alive"] \
				and bf.ally_plane["landed"] \
				and onfoot.pos.distance_to(bf.ally_plane["pos"]) < 8.0:
			_board_plane()
	if state == ST.BATTLE and flying \
			and Input.is_action_just_pressed("rr_bomb"):
		if not bf.player_drop_bomb():
			hud.show_center("没有炸弹了", "回基地落地补给", 1200)
	# 货运劫案：地面靠近停机货机接取 / 飞行中靠近货舱夺货
	if state == ST.ROAM and airport_traffic != null \
			and Input.is_action_just_pressed("rr_interact") \
			and not shop_open and not gunshop_open:
		if on_foot and airport_traffic.cargo_mission == "parked" \
				and onfoot.pos.distance_to(airport_traffic.cargo_plane_pos) < 15.0:
			airport_traffic.begin_cargo_mission()
			cargo_heist = "chase"
			hud.show_center("任务接取", "货机正在起飞 · 驾驶战机追上它夺走货物", 3500)
		elif not on_foot and airport_traffic.near_cargo_hold(
				player.veh.pos) \
				and airport_traffic.cargo_mission in ["cruise", "takeoff"]:
			airport_traffic.steal_cargo()
			cargo_heist = "flee"
			cargo_state = "escape"
			if npc != null:
				npc.trigger_wanted()
				npc.escalate()
			hud.show_center("货物到手！", "大量警察出动 · 飞远甩掉通缉", 3500)
	# 漫游战机：F 登机/下机（站在班机舱门边时优先登班机，不重复触发）
	if state == ST.ROAM and plane_mode \
			and Input.is_action_just_pressed("rr_interact") \
			and not shop_open and not gunshop_open \
			and not (on_foot and airport_traffic != null \
			and airport_traffic.near_service_door(onfoot.pos) >= 0):
		if on_foot:
			if rplane.get("landed", false) and not rplane.is_empty() \
					and onfoot.pos.distance_to(rplane["pos"]) < 9.0:
				_roam_board_plane()
		else:
			_roam_exit_plane()
	if on_foot and (state == ST.ROAM or state == ST.BATTLE):
		for gi in 5:
			if Input.is_action_just_pressed("rr_gun%d" % [gi + 1]):
				var avail: Array = Guns.GUNS.filter(func(g): return _gun_owned(g["id"]))
				if gi < avail.size():
					_select_gun(avail[gi]["id"])
	if Input.is_action_just_pressed("rr_start") and state == ST.GARAGE:
		start_from_garage()
	if state == ST.BATTLE and bf != null and bf.battle_over \
			and Input.is_action_just_pressed("rr_start"):
		exit_battle()   # 战斗结束：Enter 返回车库
	if state == ST.ROAM and not shop_open and not gunshop_open:
		var d_parts: float = Vector2(player.veh.pos.x - FreeroamMap.SHOP_DOOR.x,
				player.veh.pos.z - FreeroamMap.SHOP_DOOR.y).length()
		var d_guns: float = Vector2(player.veh.pos.x - FreeroamMap.GUNSHOP_DOOR.x,
				player.veh.pos.z - FreeroamMap.GUNSHOP_DOOR.y).length()
		_near_shop = d_parts < 14.0
		var near_guns := d_guns < 14.0
		hud.set_shop_hint(_near_shop, "按 Enter 进入配件店")
		hud.set_gunshop_hint(near_guns)
		if _near_shop and Input.is_action_just_pressed("rr_start"):
			open_shop()   # 漫游实体配件店：走近按 Enter 进店
		elif near_guns and Input.is_action_just_pressed("rr_start"):
			open_gunshop()   # 漫游实体枪械店：走近按 Enter 进店
	if Input.is_action_just_pressed("rr_throttle") and state == ST.GARAGE:
		enter_roam()   # 车库里按 W/↑：直接从卷帘门车库出发漫游
	if Input.is_action_just_pressed("rr_dual"):
		_toggle_dual_mode()


## 车头盖视角锚高：按当前车模「车体」网格的实际顶高自适应（车顶 + 0.12m），
## 结果缓存到换车为止。只统计纵向 >2m 的网格——贴影/装饰零厚面（z≈0）
## 和车轮（z<1m）不算。兜底 1.32m（模型缺失/未进树时）
func _hood_anchor_height() -> float:
	if _hood_h > 0.0:
		return _hood_h
	var top := 1.2
	var vis: CarVisual = player.visual
	if vis != null and vis.is_inside_tree():
		var inv := vis.global_transform.affine_inverse()
		for mi in vis.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var ab: AABB = inv * m.global_transform * m.get_aabb()
			if ab.size.z < 2.0:
				continue
			top = maxf(top, ab.position.y + ab.size.y)
	_hood_h = top + 0.12
	return _hood_h


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
		player.veh.nitro_active = false
		return

	# ROAM：只有玩家车，物理照常（立体物理对路网高度自动生效）
	if s == ST.ROAM:
		if shop_open or gunshop_open:
			return   # 店里：冻结，买完继续
		var pin := player.veh
		if airliner_ride and airport_traffic != null:
			# 乘班机中：班机照常飞，玩家无实体；到达后自动下机
			airport_traffic._update_ride(h)
			npc.player_pos = airport_traffic.ride_pos
			npc.player_speed = 0.0
			npc.player_on_foot = false
			if airport_traffic.ride_phase == "arrived":
				airliner_ride = false
				var di: int = 1 - airport_traffic.ride_from_i
				on_foot = true
				camera.near = 0.02
				onfoot.set_gun(gun_equipped)
				onfoot.enter(airport_traffic.service_door_pos(di)
						+ Vector3(6.0, 0, 0), PI)
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				hud.set_onfoot(true)
				hud.set_health(player_hp)
				hud.set_gun_name(Guns.gun_by_id(gun_equipped)["name"])
				hud.show_center("已抵达 " + airport_traffic.ride_names[di],
						"", 2500)
		elif plane_mode and not on_foot and not rplane.is_empty():
			# 漫游战机：飞行物理，车辆冻结（位置同步给 NPC/警察逻辑）
			_roam_plane_step(h)
			pin.pos = rplane["pos"]
			pin.heading = rplane["heading"]
			pin.vf = rplane["speed"]
			npc.player_pos = pin.pos
			npc.player_vel = Vector3(sin(rplane["heading"]), 0,
					cos(rplane["heading"])) * float(rplane["speed"])
			npc.player_speed = float(rplane["speed"])
			npc.player_on_foot = false
		elif on_foot:
			# 步行：第一人称移动/射击，车辆冻结在原地
			if wheel_ride and freeroam != null:
				# 摩天轮观景：人物贴吊舱座位，鼠标视角照常（不走路）
				onfoot.pos = freeroam.gondola_seat(_wheel_gi)
				onfoot.move_speed = 0.0
			else:
				onfoot.update(h)
			npc.player_pos = onfoot.pos
			npc.player_vel = Vector3(sin(onfoot.yaw), 0, cos(onfoot.yaw)) * onfoot.move_speed
			npc.player_speed = onfoot.move_speed
			npc.player_on_foot = true
			_no_dmg_t += h
			if _no_dmg_t > 6.0:
				player_hp = minf(100.0, player_hp + 5.0 * h)
			hud.set_health(player_hp)
			hud.set_ammo(onfoot.ammo, onfoot.reloading, Guns.gun_by_id(gun_equipped)["name"])
			hud.set_scope(onfoot.scoped)
			# 地标交互提示（摩天轮 / 电视塔观景电梯）
			var lm_hint := ""
			if wheel_ride:
				lm_hint = "F 下摩天轮"
			elif onfoot.pos.y > 100.0 and Vector2(onfoot.pos.x - 90,
					onfoot.pos.z - 90).length() < 20.0:
				lm_hint = "F 乘电梯下塔"
			elif Vector2(onfoot.pos.x - 90,
					onfoot.pos.z - 90).length() < 14.0:
				lm_hint = "F 观景电梯上云顶"
			elif freeroam != null and onfoot.pos.distance_to(
					freeroam.wheel_board_pos()) < 14.0:
				lm_hint = "F 乘坐摩天轮"
			hud.set_board_hint(lm_hint != "", lm_hint)
		else:
			hud.set_board_hint(false)
			var inp_r := _sample_input(h)
			pin.input_throttle = inp_r["throttle"]
			pin.input_brake = inp_r["brake"]
			pin.input_steer = inp_r["steer"]
			pin.input_handbrake = inp_r["handbrake"]
			pin.nitro_active = Input.is_physical_key_pressed(KEY_SHIFT)
			pin.weather_grip = day_cycle.grip_mul() if day_cycle != null else 1.0
			freeroam.vehicle_y = pin.pos.y
			freeroam.step_garage(h, pin.pos, inp_r["throttle"] > 0.1)
			pin.step(h)
			_roam_bound(pin)
			npc.player_on_foot = false
		# 机场氛围（客机起降 + 登机人流 + 班机补充）+ 门动画 + 货运任务
		if airport_traffic != null:
			airport_traffic._t += h
			airport_traffic.tick(h)
			airport_traffic.update_cargo_mission(h)
			for ap in airport_traffic.airports:
				for pl in ap["planes"]:
					airport_traffic._update_plane(ap, pl, h)
				airport_traffic._update_walkers(ap, h)
		freeroam.update_doors(h, onfoot.pos if on_foot else pin.pos)
		if on_foot:
			onfoot.fire_block = freeroam.nearest_closed_door(
					onfoot.pos, 4.5) >= 0
		# 货运任务：车辆驶入货仓夺货 → 大量警察 → 逃脱领赏
		if cargo_state == "ready" and airport_traffic != null \
				and airport_traffic.cargo_in_hold(pin.pos):
			cargo_state = "escape"
			airport_traffic.take_cargo()
			if npc != null:
				npc.trigger_wanted()
				npc.escalate()
			hud.show_center("货物到手！", "大量警察正在赶来 · 甩掉他们领取报酬",
					4000)
		elif cargo_state == "escape" and npc != null and not npc.wanted \
				and npc.police.is_empty():
			cargo_state = "rewarded"
			coins += 5000
			_save_settings()
			hud.show_center("成功脱身！", "货物报酬 +5000 金币", 4000)
			for ap in airport_traffic.airports:
				for p in ap["planes"]:
					airport_traffic._update_plane(ap, p, h)
				airport_traffic._update_walkers(ap, h)
		# NPC 交通/行人/警察
		if npc != null and npc.active:
			if not on_foot:
				npc.player_pos = pin.pos
				npc.player_vel = Vector3(
						sin(pin.heading) * pin.vf + cos(pin.heading) * pin.vl, 0.0,
						cos(pin.heading) * pin.vf - sin(pin.heading) * pin.vl)
				npc.player_speed = absf(pin.vf)
			npc.update(h)
			# 警笛 + 直升机旋翼音（随距离衰减）
			audio.set_pursuit_audio(npc.wanted and npc.min_police_dist < 400.0,
					npc.min_police_dist, npc.heli_active and npc.heli_dist < 350.0,
					npc.heli_dist)
		# 镜头震动（直升机开火，步行时也生效）
		if shake > 0.002 and on_foot:
			var a2 := shake * 0.2
			camera.position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * a2
		shake = maxf(shake * exp(-3.2 * h), 0.0)
		sim_time += h
		return

	# BATTLE：大战场（步行持枪/驾驶战机 + 两军 AI 士兵交战）
	if s == ST.BATTLE:
		if bf == null or bmap == null:
			return
		if _battle_respawn_t > 0.0:
			# 死亡等待：战场继续打，玩家 3 秒后基地重生
			_battle_respawn_t = _battle_respawn_t - h
			bf.update(h)
			if _battle_respawn_t <= 0.0:
				player_hp = 100.0
				bf.player_alive = true
				flying = false
				bf.player_flying = false
				_battle_enter_foot()
				hud.show_center("", "", 0)
			sim_time += h
			return
		if bf.battle_over:
			sim_time += h
			return
		bf.player_alive = true
		if flying:
			bf.update_player_plane(h)
			var pl: Dictionary = bf.ally_plane
			bf.player_pos = Vector3(pl["pos"])
			# 停机坪补给：落地靠基地自动修机补弹
			var near_base: bool = Vector2(pl["pos"].x, pl["pos"].z) \
					.distance_to(Vector2(BattleMap.ALLY_SPAWN.x,
					BattleMap.ALLY_SPAWN.z)) < 40.0
			if pl["landed"] and near_base \
					and (float(pl["hp"]) < bf.PLANE_HP
					or int(pl["bombs"]) < bf.PLANE_BOMBS):
				pl["hp"] = bf.PLANE_HP
				pl["bombs"] = bf.PLANE_BOMBS
				hud.show_center("补给完成", "战机修复 · 弹药装满", 1500)
		else:
			bf.player_pos = onfoot.pos
			onfoot.update(h)
			# 靠近停机坪战机 → 登机提示
			var near_plane: bool = bf.ally_plane["alive"] \
					and bf.ally_plane["landed"] \
					and onfoot.pos.distance_to(bf.ally_plane["pos"]) < 8.0
			hud.set_board_hint(near_plane, "按 F 登机")
		bf.update(h)
		_no_dmg_t += h
		if _no_dmg_t > 6.0 and not flying:
			player_hp = minf(100.0, player_hp + 5.0 * h)
			hud.set_health(player_hp)
		# 顶栏（含战机状态）
		var plane_txt := "战机 ✖" if not bf.ally_plane["alive"] \
				else "战机 %d" % int(bf.ally_plane["hp"])
		if flying:
			plane_txt = "战机 %d · 弹 %d" % [int(bf.ally_plane["hp"]),
					int(bf.ally_plane["bombs"])]
		hud.set_battle_top(bf.army_alive("ally"), bf.army_alive("enemy"),
				bf.wave, bf.kills, plane_txt)
		if not flying:
			hud.set_ammo(onfoot.ammo, onfoot.reloading,
					Guns.gun_by_id(gun_equipped)["name"])
			hud.set_scope(onfoot.scoped)
		# 我方新机就位提示
		if _plane_was_down and bf.ally_plane["alive"] and not flying:
			_plane_was_down = false
			hud.show_center("我方新战机已就位", "回基地按 F 登机", 2200)
		if shake > 0.002:
			var a3 := shake * 0.2
			camera.position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * a3
		shake = maxf(shake * exp(-3.2 * h), 0.0)
		sim_time += h
		return

	# RACING / FINISHED 都持续模拟
	if s != ST.RACING and s != ST.FINISHED:
		return

	# 输入
	var inp := _sample_input(h)
	player.veh.nitro_active = Input.is_physical_key_pressed(KEY_SHIFT)
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

	# 物理步进（雨/雪天气抓地对全部车辆生效）
	var w_grip: float = day_cycle.grip_mul() if day_cycle != null else 1.0
	for rec in cars:
		rec.veh.weather_grip = w_grip
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
		_commit_player_lap()   # 先把刚跑完的这圈提交给 AI 学习线
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
	# 完赛金币：名次越好越多（漫游无奖励，这里只在比赛状态触发）
	var reward: int = TrackData.RACE_REWARDS[mini(pos_num - 1, TrackData.RACE_REWARDS.size() - 1)]
	coins += reward
	_save_settings()
	var text := "🏆 冠军！" if pos_num == 1 else "以第 %d 名完赛" % pos_num
	# 延迟展示，让玩家先看到冲线
	get_tree().create_timer(0.3).timeout.connect(
		func(): hud.show_center(text, "金币 +%d（现有 %d）" % [reward, coins], 2600))


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
	if plane_mode and roam_plane_vis != null:
		# 战机摆上展台（车模隐藏），与展台同速旋转
		player.visual.visible = false
		roam_plane_vis.visible = true
		roam_plane_vis.position = gp + Vector3(0,
				RRGarage.PLATFORM_TOP + 1.1, 0)
		roam_plane_vis.rotation.y = _garage_angle + PI
		roam_plane_vis.set_throttle(0.05)   # 尾焰怠速微光
		roam_plane_vis.set_gear(true)
	else:
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

	# 大战场飞行：战机后上方追尾相机
	if state == ST.BATTLE and flying and bf != null:
		var pl: Dictionary = bf.ally_plane
		var pfwd := Vector3(sin(float(pl["heading"])), 0,
				cos(float(pl["heading"])))
		var want := Vector3(pl["pos"]) - pfwd * 17.0 + Vector3(0, 7.0, 0)
		camera.position = camera.position.lerp(want, 1.0 - exp(-5.0 * dt))
		camera.look_at(Vector3(pl["pos"]) + pfwd * 14.0
				+ Vector3(0, 2.0, 0), Vector3.UP)
		camera.fov = RRUtil.damp(camera.fov,
				66.0 + float(pl["speed"]) * 0.14, 3.0, dt)
		return

	# 班机载客飞行：追逐班机
	if state == ST.ROAM and airliner_ride and airport_traffic != null:
		var afwd := Vector3(sin(airport_traffic.ride_heading), 0,
				cos(airport_traffic.ride_heading))
		camera.position = camera.position.lerp(
				airport_traffic.ride_pos - afwd * 30.0 + Vector3(0, 12.0, 0),
				1.0 - exp(-3.0 * dt))
		camera.look_at(airport_traffic.ride_pos + Vector3(0, 3.0, 0), Vector3.UP)
		camera.fov = RRUtil.damp(camera.fov, 60.0, 2.0, dt)
		return

	# 漫游战机：同款追尾相机
	if state == ST.ROAM and plane_mode and not on_foot and not rplane.is_empty():
		var rfwd := Vector3(sin(float(rplane["heading"])), 0,
				cos(float(rplane["heading"])))
		var rwant := Vector3(rplane["pos"]) - rfwd * 17.0 + Vector3(0, 7.0, 0)
		camera.position = camera.position.lerp(rwant, 1.0 - exp(-5.0 * dt))
		camera.look_at(Vector3(rplane["pos"]) + rfwd * 14.0
				+ Vector3(0, 2.0, 0), Vector3.UP)
		camera.fov = RRUtil.damp(camera.fov,
				66.0 + float(rplane["speed"]) * 0.14, 3.0, dt)
		return

	# 摩天轮吊舱第一人称：位置贴座位，视角交给 onfoot 的鼠标 yaw/pitch
	if state == ST.ROAM and wheel_ride and onfoot != null:
		camera.position = onfoot.pos + Vector3(0, 1.35, 0)
		camera.rotation = Vector3(onfoot.pitch, onfoot.yaw + PI, 0)
		camera.fov = RRUtil.damp(camera.fov, 68.0, 2.0, dt)
		return
	# 下车人模式：相机完全交给 onfoot（第一人称），这里不做任何覆盖
	if on_foot and onfoot != null:
		return

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
		# 半径收到 8.2（原 10.5 会钻进看台），高度跟随车辆海拔（原为绝对值，
		# 带高差的自定义赛道上相机会落到路面下方几十米）
		camera.position = Vector3(
			pv.pos.x + cos(t) * 8.2,
			pv.pos.y + 2.9 + sin(t * 0.6) * 0.7,
			pv.pos.z + sin(t) * 8.2)
		camera.look_at(Vector3(pv.pos.x, pv.pos.y + 0.9, pv.pos.z), Vector3.UP)
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
			# 锚高按各车模型实际顶高自适应（比车顶再高 0.12m）——
			# 原来写死 1.02m，比多数车模的机盖/座舱还低，车头盖视角整个
			# 埋进车壳里穿模挡视野。高度跟着车走，开上高架/盘山也不掉层
			_cam_pos = Vector3(pv.pos.x + f.x * 0.55,
					pv.pos.y + _hood_anchor_height() + absf(pv.g_lat) * 0.15,
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
		# 兜底：相机不得低于车辆所在路面（高架/盘山上尤其重要）
		var cam_p := _cam_pos
		# 高度限位：不得低于车所在路面；车钻到高架桥下时，相机也必须压到
		# 桥底以下 —— 否则相机留在桥外，箱梁底板正好把车整个挡住
		# 只做「不得低于所在路面」这一条限位。桥体不再挪相机 ——
		# 逼近桥底时反复收放会让视距忽远忽近，改由桥体自己淡出（见
		# freeroam_map._fade_material）。
		cam_p.y = maxf(cam_p.y, pv.pos.y + 0.9)
		# 楼体遮挡：从车位向目标机位步进，取最后一个不在楼里的比例。
		# 楼是 MultiMesh / 独立 MeshInstance，都没有碰撞体，用占位网格查询。
		# 原来 8.2m 吊臂在窄街里转弯时整个钻进沿街楼。
		# 遮挡不再挪相机：逼近桥底/沿街楼时反复收放会让视距忽远忽近。
		# 改成让挡住的那部分桥体与楼体自己淡出（见 freeroam_map 的
		# _fade_material 与 _building_material 里的抖动丢弃）。
		camera.position = cam_p
		camera.look_at(_cam_look, Vector3.UP)

		# 入场运镜：从车正上方 40m 俯视缓降到车后追车位。
		# 机位始终在车道正上方（不在楼群里穿行），落点即追车位，交接无跳变。
		if _intro_t > 0.0:
			var s01 := clampf(_intro_t / INTRO_DUR, 0.0, 1.0)
			var e := s01 * s01 * (3.0 - 2.0 * s01)          # smoothstep
			var high := pv.pos + Vector3(0, 40.0, 0) - f * 12.0
			camera.position = cam_p.lerp(high, e)
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
	if pv.nitro_active and pv.nitro > 0.0:
		want_fov += 7.0   # 氮气推进感
	camera.fov = RRUtil.damp(camera.fov, want_fov, 4.0, dt)
	# 把相机/车位/车头方向写给桥体与楼体的遮挡淡出着色器
	if state == ST.ROAM and freeroam != null:
		freeroam.update_occluder_fade(camera.position, pv.pos + Vector3(0, 0.7, 0),
				Vector2(sin(pv.heading), cos(pv.heading)))
	if hud.debug_visible():
		_update_debug_text()


## F3 调试信息：截图即可精确定位问题位置
func _update_debug_text() -> void:
	var v := player.veh
	var lines := [
		"车  (%.1f, %.2f, %.1f)  朝向 %.2f  速度 %.1f km/h" % [
				v.pos.x, v.pos.y, v.pos.z, v.heading, absf(v.vf) * 3.6],
		"相机 (%.1f, %.2f, %.1f)  相对车高 %+.2f  模式 %d  FOV %.0f" % [
				camera.position.x, camera.position.y, camera.position.z,
				camera.position.y - v.pos.y, cam_mode, camera.fov],
		"表面 %s  贴地 %s  gear %d" % [v.surface, v.grounded, v.gear],
	]
	if state == ST.ROAM and freeroam != null:
		freeroam.vehicle_y = v.pos.y
		var q := freeroam.query(v.pos.x, v.pos.z, null)
		var ri: int = int(q["road"])
		var kind := "?"
		if ri >= 0:
			var rd: FreeroamMap.Road = freeroam.roads[ri]
			kind = ("网格街" if ri < FreeroamMap.GRID_COORDS.size() * 2
					else ("高架" if rd.elevated else "城外公路"))
		lines.append("路 road%d(%s) 路面高 %.2f 车离路面 %+.2f 横向 %+.2f 软墙 %.2f 表面 %s" % [
				ri, kind, float(q["height"]), v.pos.y - float(q["height"]),
				float(q["lat_off"]), float(q["wall"]), q["surf"]])
		# 同点所有「面宽之内」的候选路，用来看是不是选错了层
		var cands := ""
		for rj in freeroam.roads.size():
			var rd2: FreeroamMap.Road = freeroam.roads[rj]
			var key := Vector2i(int(v.pos.x / FreeroamMap.CELL), int(v.pos.z / FreeroamMap.CELL))
			for cx in range(-1, 2):
				for cz in range(-1, 2):
					var k2 := Vector2i(key.x + cx, key.y + cz)
					if not rd2.grid.has(k2):
						continue
					for ii in rd2.grid[k2]:
						var pp := rd2.pts[ii]
						if Vector2(pp.x - v.pos.x, pp.z - v.pos.z).length() < rd2.half_w:
							cands += "  road%d@%.2f" % [rj, pp.y]
							cx = 9
							cz = 9
							break
					if cx == 9:
						break
				if cx == 9:
					break
		lines.append("同点候选:" + (cands if cands != "" else " 无"))
		lines.append("地形高 %.2f" % freeroam.terrain_height(v.pos.x, v.pos.z))
	hud.set_debug("\n".join(lines))


# ================= HUD =================

func _update_hud(dt: float) -> void:
	if state == ST.GARAGE:
		return
	if state == ST.BATTLE:
		return   # 战场 HUD（顶栏/准星/血条弹药）在 _step_sim 里直更
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
	var lap_label := "本圈"
	if state == ST.RACING or state == ST.FINISHED:
		lap_text = RRUtil.format_time(sim_time * 1000.0 - player.lap_stamp)
	elif state == ST.ROAM:
		lap_text = RRUtil.format_time(sim_time * 1000.0)
		lap_label = "行驶"
	hud.draw_tach(pv.speed_kmh, gear_label, maxf(0.04, pv.rpm_norm), pv.drifting,
			ratio, lap_text, lap_label, pv.nitro / 100.0)

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
