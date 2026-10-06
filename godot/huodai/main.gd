class_name HuoDaiMain
extends Node3D
## 烽火地带（Godot 版）主装配与模式状态机 —— 网页版 fps.html 的移植
## 模式：LOBBY 大厅（出发/仓库/改枪台/签到）→ MISSION 行动（搜刮→撤离）→ RANGE 靶馆
## 全部节点代码装配（工程约定：无 .tscn 拼场景）；模块间鸭子类型注入，契约见 hd_data.gd

enum Mode { LOBBY, MISSION, RANGE }

var mode: int = Mode.LOBBY
var paused: bool = false

var stash: HDStash
var world: HDWorld
var targets: HDTargets
var player: HDPlayer
var guns: HDGuns
var soldiers: HDSoldiers
var loot: HDLoot
var hud: HDHud
var lobby: HDLobby
var audio: HDAudio
var tracers   # TracerPool（无 class_name，preload）

var _kills: int = 0
var _raid_t: float = 0.0
var _bag_value: float = 0.0
var _extract_t: float = 0.0

func _ready() -> void:
	_register_inputs()
	randomize()

	audio = HDAudio.new()
	add_child(audio)

	world = HDWorld.new()
	add_child(world)
	world.build()

	targets = HDTargets.new()
	add_child(targets)
	targets.build(HDData.HALL_CENTER)

	player = HDPlayer.new()
	add_child(player)
	player.setup(world)
	player.enter(world.spawn_pos)
	player.died.connect(_on_player_died)

	tracers = preload("res://scripts/tracer_pool.gd").new()

	guns = HDGuns.new()
	add_child(guns)
	guns.setup(player, world, audio, tracers)
	guns.soldiers = null      # 士兵 build 后注入（避免 build 前引用空转）
	guns.targets = targets
	guns.scope_provider = _scope_for
	guns.hit_enemy.connect(_on_hit_enemy)

	soldiers = HDSoldiers.new()
	add_child(soldiers)
	soldiers.build(world, player, audio)
	soldiers.player_hit.connect(func(dmg: float): player.hit(dmg))
	soldiers.killed.connect(_on_soldier_killed)
	guns.soldiers = soldiers

	loot = HDLoot.new()
	add_child(loot)
	loot.build(world)
	loot.picked.connect(_on_loot_picked)
	loot.full_warn.connect(func(): hud.toast("背包已满 —— 先撤离或弃件", Color(1.0, 0.55, 0.3)))
	loot.prompt.connect(func(text: String, prog: float): hud.set_prompt(text, prog))

	hud = HDHud.new()
	add_child(hud)
	hud.setup()
	hud.menu_restart.connect(func(): _restart_current())
	hud.menu_range.connect(func(): _enter_range())
	hud.menu_abort.connect(_back_to_lobby)
	hud.result_restart.connect(func(): _restart_current())
	hud.result_lobby.connect(_back_to_lobby)

	stash = HDStash.new()
	lobby = HDLobby.new()
	add_child(lobby)
	lobby.setup(stash)
	lobby.deploy_requested.connect(_start_mission)
	lobby.range_requested.connect(_enter_range)

	lobby.show_lobby()
	_apply_mode_visuals()

## ---- 输入注册（hd_ 前缀，不与赛车工程 rr_ 冲突） ----
func _register_inputs() -> void:
	var defs := {
		"hd_fire": [],
		"hd_scope": [],
		"hd_slot1": [KEY_1], "hd_slot2": [KEY_2],
		"hd_reload": [KEY_R], "hd_interact": [KEY_F],
	}
	for action in defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("hd_fire"):
		pass
	var fire_ev := InputEventMouseButton.new()
	fire_ev.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("hd_fire", fire_ev)
	var scope_ev := InputEventMouseButton.new()
	scope_ev.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("hd_scope", scope_ev)

## ---- 瞄具注入链（对齐 onfoot.scope_provider 约定） ----
func _scope_for(gun_id: String) -> Dictionary:
	if gun_id == "sniper":
		return {"kind": "sniper", "zoom": 6.0}
	var fit: String = str(stash.scope_fit.get(gun_id, "iron"))
	if fit != "iron" and stash.owns_scope(fit):
		var sc: Dictionary = Guns.scope_by_id(fit)
		if not sc.is_empty():
			return {"kind": str(sc.get("kind", "iron")), "zoom": float(sc.get("zoom", 1.0))}
	return {"kind": "iron", "zoom": 1.0}

## ---- 模式流转 ----
func _start_mission(loadout: Dictionary) -> void:
	mode = Mode.MISSION
	_kills = 0
	_raid_t = 0.0
	_bag_value = 0.0
	_extract_t = 0.0
	paused = false
	soldiers.reset_all()
	loot.reset_all()
	targets.reset_all()
	player.enter(world.spawn_pos)
	# 面朝地图中心（出生在西南角，前向 = (sin yaw, 0, cos yaw) → yaw = atan2(dx, dz)）
	var to_c := Vector3(-world.spawn_pos.x, 0.0, -world.spawn_pos.z)
	if to_c.length() > 0.01:
		player.yaw = atan2(to_c.x, to_c.z)
		player.pitch = 0.0
	guns.enter(loadout)
	lobby.hide_lobby()
	hud.hide_result()
	hud.set_raid_visible(true)
	hud.set_score_visible(false)   # 计分条只属于靶场
	hud.set_danger(false)
	hud.set_extract(0.0, 1.0)
	hud.toast("搜刮变卖物 —— 集齐后前往绿标撤离点", Color(0.49, 0.89, 0.66))
	_apply_mode_visuals()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _enter_range() -> void:
	mode = Mode.RANGE
	paused = false
	soldiers.reset_all()
	loot.reset_all()
	targets.reset_all()
	var lane := HDData.HALL_CENTER + Vector3(0.0, 0.0, 11.0)   # 中间射位（馆内射击线，-Z 朝靶道）
	player.enter(lane)
	player.yaw = PI          # 面朝 -Z 靶道
	player.pitch = 0.0
	guns.enter(stash.loadout)
	lobby.hide_lobby()
	hud.hide_result()
	hud.set_raid_visible(true)
	hud.set_score_visible(true)
	hud.set_score(targets.score, targets.best)
	hud.set_danger(false)
	hud.set_extract(0.0, 1.0)
	_apply_mode_visuals()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _back_to_lobby() -> void:
	mode = Mode.LOBBY
	paused = false
	hud.set_raid_visible(false)
	hud.hide_result()
	hud.hide_menu()
	hud.set_danger(false)
	hud.set_extract(0.0, 1.0)
	lobby.show_lobby()
	_apply_mode_visuals()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _restart_current() -> void:
	if mode == Mode.RANGE:
		_enter_range()
	else:
		_start_mission(stash.loadout)

## 靶馆氛围：进 RANGE 时收雾收紧些（室内感由世界侧灯光承担，这里只做节奏差异）
func _apply_mode_visuals() -> void:
	var indoor := mode == Mode.RANGE
	if world.has_method("set_indoor"):
		world.set_indoor(indoor)

## ---- 结算 ----
func _on_player_died() -> void:
	if mode != Mode.MISSION:
		return
	var lost := loot.drain()
	stash.record_raid(false, _kills)
	hud.set_raid_visible(false)
	hud.show_result(false, {
		"kills": _kills, "value": _bag_value,
		"time_sec": _raid_t, "rank": _rank_of(_bag_value),
		"lost": lost.size(),
	})
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _win_raid() -> void:
	var bag := loot.drain()
	var n := stash.deposit(bag)
	stash.record_raid(true, _kills)
	hud.set_raid_visible(false)
	hud.show_result(true, {
		"kills": _kills, "value": _bag_value, "deposited": n,
		"time_sec": _raid_t, "rank": _rank_of(_bag_value),
	})
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _rank_of(v: float) -> String:
	if v >= 300000.0:
		return "S"
	if v >= 100000.0:
		return "A"
	if v >= 30000.0:
		return "B"
	return "C"

func _on_hit_enemy(kind: String, idx: int, point: Vector3, dmg: float, head: bool) -> void:
	var res: Dictionary = soldiers.apply_hit(idx, dmg, head)
	hud.hitmark(head, bool(res.get("killed", false)))
	audio.play_hit()

func _on_soldier_killed(info: Dictionary) -> void:
	_kills += 1
	var dist: float = float(info.get("dist", 0.0))
	hud.toast("击杀 · %dm" % int(dist), Color(1.0, 0.7, 0.36))

func _on_loot_picked(item: Dictionary) -> void:
	_bag_value += float(item.get("value", 0.0))
	hud.set_backpack(loot.backpack.size(), HDData.BACKPACK_MAX)
	var col: Color = HDData.RARITY[int(item.get("rarity", 0))]["color"]
	hud.toast("拾取 %s %s +₵%d" % [item.get("icon", ""), item.get("name", ""), int(item.get("value", 0))], col)

## ---- 每帧 ----
func _process(delta: float) -> void:
	# HUD 的 Esc 关菜单不发信号（自处理按键）：这里同步恢复对局
	if paused and not hud.menu_visible and not hud.result_visible:
		paused = false
		if mode != Mode.LOBBY:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var dt: float = minf(delta, 0.05)
	if lobby.lobby_visible:
		player.update(0.0)   # 大厅盖场：世界静止，只摆相机（dt=0 不移动）
		return   # 经济 UI 全在 CanvasLayer
	if hud.result_visible:
		return   # 结算页冻结战场
	if hud.menu_visible:
		return   # 暂停菜单
	if mode == Mode.MISSION:
		_step_mission(dt)
	elif mode == Mode.RANGE:
		_step_range(dt)

func _step_mission(dt: float) -> void:
	_raid_t += dt
	player.update(dt)
	guns.update(dt)
	soldiers.update(dt, true)
	loot.update(dt, player.pos, Input.is_action_pressed("hd_interact"))
	targets.update(dt)
	# 危险区横幅
	hud.set_danger(world.zone_at(player.pos.x, player.pos.z) == "center")
	# 弹药/血量/背包同步
	hud.set_ammo(guns.ammo, guns.reserve)
	hud.set_health(player.health, 100.0)
	hud.set_backpack(loot.backpack.size(), HDData.BACKPACK_MAX)
	# 开镜分划
	var sc: Dictionary = _scope_for(guns.cur_id)
	hud.set_scope(str(sc.get("kind", "iron")), float(sc.get("zoom", 1.0)), player.ads > 0.5)
	# 撤离读条
	var d := player.pos.distance_to(world.extract_pos)
	if d <= HDData.EXTRACT_R:
		_extract_t += dt
		if _extract_t >= HDData.EXTRACT_HOLD:
			_extract_t = 0.0
			_win_raid()
			return
	else:
		_extract_t = maxf(0.0, _extract_t - dt * 2.0)
	hud.set_extract(_extract_t, HDData.EXTRACT_HOLD)

func _step_range(dt: float) -> void:
	player.update(dt)
	guns.update(dt)
	targets.update(dt)
	hud.set_ammo(guns.ammo, guns.reserve)
	hud.set_health(player.health, 100.0)
	hud.set_score(targets.score, targets.best)
	var sc: Dictionary = _scope_for(guns.cur_id)
	hud.set_scope(str(sc.get("kind", "iron")), float(sc.get("zoom", 1.0)), player.ads > 0.5)

## ---- 输入分发 ----
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player.add_look(event.relative)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_route_key((event as InputEventKey).keycode)

func _route_key(code: int) -> void:
	# 结算页：R 再来 / Enter 回大厅
	if hud.result_visible:
		if code == KEY_R:
			_restart_current()
		elif code == KEY_ENTER:
			_back_to_lobby()
		return
	# 暂停菜单：1/2/3
	if hud.menu_visible:
		if code == KEY_1:
			hud.menu_restart.emit()
		elif code == KEY_2:
			hud.menu_range.emit()
		elif code == KEY_3:
			hud.menu_abort.emit()
		elif code == KEY_ESCAPE:
			hud.hide_menu()
			paused = false
			if mode != Mode.LOBBY:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	# 大厅：全部转发给 lobby
	if lobby.lobby_visible:
		lobby.handle_key(code)
		return
	# 对局内：Esc 菜单
	if code == KEY_ESCAPE:
		paused = true
		hud.show_menu()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
