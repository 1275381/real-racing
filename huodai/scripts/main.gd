class_name HuoDaiMain
extends Node3D
## 烽火地带（Godot 版）主装配与模式状态机 —— 网页版 fps.html 的移植
## 模式：LOBBY 大厅（出发/仓库/改枪台/交易行/签到）→ MISSION 行动（搜刮→撤离）→ RANGE 靶馆
## 全部节点代码装配（工程约定：无 .tscn 拼场景）；模块间鸭子类型注入，契约见 hd_data.gd

enum Mode { LOBBY, MISSION, RANGE }

## 靶场练习备弹（虚拟弹药）：每枪固定大额，与 stash 库存完全无关——
## 取 9999 而非 999 是为了让单次练习会话几乎不可能打空（HUD 显示 ∞，
## 若内部真耗尽会「显示 ∞ 却拒绝换弹」自相矛盾）；离场/重开一律丢弃，
## 绝不回写库存（回写=靶场无限刷弹漏洞，经济红线）
const RANGE_RESERVE := 9999

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
var airdrop   # 空投事件（hd_airdrop.gd，无 class_name，preload）

var _kills: int = 0
var _raid_t: float = 0.0
var _extract_t: float = 0.0
## 带入即风险（2026-10）：局内且未结算 = 放弃/重开视同阵亡；结算后置 false
## （结算页 R/Enter 再走 _restart_current/_back_to_lobby 不会二次结算）
var _raid_live := false
var _raid_loadout: Dictionary = {}   # 本局实际带进来的主副武器（阵亡按它丢）
var _step_acc := 0.0                 # 玩家脚步：累计步行距离（够一步就响一声）
var _last_ppos := Vector3.ZERO
## 第三阶段（改进方案第 5/6 节）：撤离点开放状态 / 拉闸进度 / 物资使用 / 局时提醒
var _extracts := {}                  # id -> {"enabled": bool, "open": bool}
var _lever_t := 0.0
var _using := {}                     # 正在使用的物资 {kind, t, dur}
var _regen_left := 0.0               # 止痛药待缓回血量
var _warned := {}                    # 局时提醒（已提示的剩余秒档）
var _airdrop_fired := false          # 本局空投已投放
var _raid_wear := {}                 # 本局各枪磨损（开火发数 × DUR_PER_SHOT，局终写回 stash）
var _raid_insured := false           # 本局出发时投了保
var _tut := -1                       # 首局引导步骤：-1 关 / 0 搜箱 / 1 看指南针 / 2 撤离
var _tut_face_t := 0.0               # 第 2 步：对准撤离点的持续秒数
const TUT_TEXT := [
	"搜一个箱子：走到亮着琥珀色小灯的箱子旁，按住 F 搜索（指南针上「箱子」标记指路）",
	"看指南针：顶部指南针上的绿色标记是撤离点——转身，让它对准正中",
	"去撤离：跟着指南针走进绿色光柱，站满 5 秒读条就带着战利品回家",
]

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
	guns.reserve_provider = _reserve_for
	# M14 专属配件解锁态（2026-10）：查询闭包 + 环境变量（静态工厂视觉件用）
	guns.m14_mods_provider = func(mid: String): return stash.m14_mods_on(mid)
	guns.hit_enemy.connect(_on_hit_enemy)
	guns.fired.connect(_on_player_fired)
	# 第四阶段：耐久（库存耐久 − 本局磨损）/ 消音器（stash 按枪查）/ 卡壳播报
	guns.dur_provider = func(gid: String) -> float:
		return stash.dur_of(gid) - float(_raid_wear.get(gid, 0.0))
	guns.sup_provider = func(gid: String) -> bool: return stash.suppressed(gid)
	guns.jammed.connect(func(): hud.feed("卡壳！%s 耐久 %d%% —— 回大厅改枪台维修" % [
		str(Guns.gun_by_id(guns.cur_id).get("name", guns.cur_id)),
		int(stash.dur_of(guns.cur_id) - float(_raid_wear.get(guns.cur_id, 0.0)))],
		Color(1.0, 0.48, 0.27)))

	soldiers = HDSoldiers.new()
	add_child(soldiers)
	soldiers.build(world, player, audio)
	soldiers.player_hit.connect(_on_player_hit)
	soldiers.killed.connect(_on_soldier_killed)
	guns.soldiers = soldiers

	loot = HDLoot.new()
	add_child(loot)
	loot.build(world)
	loot.picked.connect(_on_loot_picked)
	loot.notice.connect(func(text: String, col: Color): hud.feed(text, col))
	loot.prompt.connect(func(text: String, prog: float): hud.set_prompt(text, prog))
	soldiers.set_loot(loot)
	soldiers.dropped.connect(_on_soldier_dropped)
	soldiers.scav_extracted.connect(_on_scav_extracted)

	airdrop = preload("res://scripts/hd_airdrop.gd").new()
	add_child(airdrop)
	airdrop.setup(world, loot, soldiers)
	airdrop.landed.connect(_on_airdrop_landed)

	hud = HDHud.new()
	add_child(hud)
	hud.setup()
	hud.menu_restart.connect(func(): _restart_current())
	hud.menu_range.connect(func(): _enter_range())
	hud.menu_abort.connect(_back_to_lobby)
	hud.result_restart.connect(func(): _restart_current())
	hud.result_lobby.connect(_back_to_lobby)
	hud.inv_close.connect(_close_inventory)
	hud.inv_use.connect(_on_inv_use)
	hud.inv_drop.connect(_on_inv_drop)
	hud.inv_move.connect(_on_inv_move)

	stash = HDStash.new()
	_sync_m14_mods_env()   # stash 建好后才有解锁态（之前调会读空 stash 报脚本错）
	lobby = HDLobby.new()
	add_child(lobby)
	lobby.setup(stash)
	lobby.gun_preview_provider = func(gid: String) -> Node3D: return guns.build_preview(gid)
	# 大厅卡片实物图（离屏拍局内同一套枪模/镜体，见 hd_thumbs.gd）
	var thumbs = preload("res://scripts/hd_thumbs.gd").new()
	add_child(thumbs)
	lobby.scope_preview_provider = func(kind: String) -> Node3D: return guns.build_scope_preview(kind)
	lobby.set_thumbs(thumbs)
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
		"hd_lean_left": [KEY_Q], "hd_lean_right": [KEY_E],
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
## 语义（问题①）：狙击枪自带 6× 原厂镜；其余枪倍率只来自改枪台装配的瞄具，
## 未装镜（""/iron/旧存档脏值）一律回机瞄 1.0×——分划与 FOV 都不得自带缩放
func _scope_for(gun_id: String) -> Dictionary:
	if gun_id == "sniper":
		return {"kind": "sniper", "zoom": 6.0}
	var fit: String = str(stash.scope_fit.get(gun_id, "iron"))
	if fit != "iron" and fit != "" and stash.owns_scope(fit):
		var sc: Dictionary = Guns.scope_by_id(fit)
		if not sc.is_empty():
			return {"kind": str(sc.get("kind", "iron")), "zoom": float(sc.get("zoom", 1.0))}
	return {"kind": "iron", "zoom": 1.0}

## ---- 极致备弹弹药源（对齐 scope_provider 注入约定）----
## 实战（MISSION）：备弹取 stash 库存（首读缺键 = 一次性送满额礼物），局终回收；
## 靶场（RANGE）：发固定大额练习弹，与库存零往来——打掉的弹不扣库存，
## 剩余的也绝不回写（否则靶场变成无限刷弹机）。mode 在 guns.enter 前已就位
func _reserve_for(gun_id: String) -> int:
	if mode == Mode.RANGE:
		return RANGE_RESERVE
	return stash.ammo_of(gun_id)

## M14 专属配件解锁态 → 环境变量（静态枪匠工厂 _ar_build 读它挂视觉件；
## stash.changed 时刷新——购买配件后下次建枪即带件）
func _sync_m14_mods_env() -> void:
	if stash == null:
		return
	var env := ""
	for mid in stash.m14_mods:
		env += str(mid) + ","
	OS.set_environment("HD_M14_MODS", env)

## 撤离回收：把两把枪剩余备弹写回库存并存档（「买多少就用多少」）。
## 阵亡/放弃不走这里——所带备弹随装备一起丢（stash.lose_carried 清零）
func _reclaim_ammo() -> void:
	var snap := guns.slot_snapshots()
	for slot in snap.keys():
		var s: Dictionary = snap[slot]
		stash.set_ammo(str(s["id"]), int(s["reserve"]))

## ---- 模式流转 ----
func _start_mission(loadout: Dictionary) -> void:
	mode = Mode.MISSION
	_kills = 0
	_raid_t = 0.0
	_extract_t = 0.0
	paused = false
	_raid_live = true
	_raid_loadout = loadout.duplicate()
	_raid_wear = {}
	# 保险（出发页勾选）：按所带装备价值 30% 预付；现金不够就不保
	_raid_insured = false
	if bool(loadout.get("insured", false)):
		var ip: int = stash.insurance_price(loadout)
		if ip > 0 and stash.cash >= ip:
			stash.cash -= ip
			stash.save()
			stash.changed.emit()
			_raid_insured = true
	soldiers.reset_all()
	loot.reset_all()
	loot.secure_cap = stash.secure_slots
	hud.hide_inventory()
	targets.reset_all()
	# 随机出生（5 处地图边缘，改进方案第 6 节）
	var sp: Vector3 = HDData.SPAWN_POINTS[randi() % HDData.SPAWN_POINTS.size()]
	world.spawn_pos = Vector3(sp.x, world.ground_height(sp.x, sp.z), sp.z)
	player.enter(world.spawn_pos)
	_setup_extracts()
	# 首局引导（从没完成过才出现）
	_tut = -1 if stash.tutorial_done else 0
	_tut_face_t = 0.0
	_sync_tut()
	# AI 搜刮者小队：从玩家以外的出生点进图；空投复位
	soldiers.spawn_scavs(world.spawn_pos)
	airdrop.reset()
	_airdrop_fired = false
	_using = {}
	_regen_left = 0.0
	_warned = {}
	_last_ppos = player.pos
	_step_acc = 0.0
	# 面朝地图中心（出生在西南角，前向 = (sin yaw, 0, cos yaw) → yaw = atan2(dx, dz)）
	var to_c := Vector3(-world.spawn_pos.x, 0.0, -world.spawn_pos.z)
	if to_c.length() > 0.01:
		player.yaw = atan2(to_c.x, to_c.z)
		player.pitch = 0.0
	_sync_m14_mods_env()   # 枪模重建前刷配件视觉态（进局/进靶场两路都过这）
	guns.enter(loadout)
	lobby.hide_lobby()
	hud.hide_result()
	hud.set_menu_mode("mission")   # 暂停菜单/弹药 HUD 按模式分化：实战=行动暂停+真实备弹数
	hud.set_raid_visible(true)
	hud.set_score_visible(false)   # 计分条只属于靶场
	hud.set_danger(false)
	hud.set_extract(0.0, 1.0)
	hud.set_backpack(0, HDData.BACKPACK_MAX, 0, loot.secure_cap)
	var open_txt := "本局撤离：主撤离 · 大坝（12 分钟后）"
	if bool(_extracts["paid"]["enabled"]):
		open_txt += " · 付费（₵%d）" % HDData.PAID_PRICE
	if bool(_extracts["lever"]["enabled"]):
		open_txt += " · 拉闸（先去变电站拉电闸）"
	hud.toast(open_txt + " —— 25 分钟内撤出", Color(0.49, 0.89, 0.66))
	hud.toast("阵亡丢失随身装备与背包 · 贵重小件放进安全箱（Tab）", Color(1.0, 0.7, 0.36))
	_apply_mode_visuals()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _enter_range() -> void:
	# 从实战转靶场（暂停菜单「2 重开靶场」）= 放弃行动，视同阵亡（装备与背包丢失）；
	# 靶场练习弹另发、与库存无关
	_abandon_if_live()
	hud.hide_inventory()
	mode = Mode.RANGE
	paused = false
	soldiers.reset_all()
	loot.reset_all()
	targets.reset_all()
	airdrop.reset()
	var lane := HDData.HALL_CENTER + Vector3(0.0, 0.0, 11.0)   # 中间射位（馆内射击线，-Z 朝靶道）
	# 出生 y 贴地下馆地坪（-6.94）：带地下域 hint 采样（默认 hint 会返回地表 0）
	lane.y = world.ground_height(lane.x, lane.z, -10.0)
	player.enter(lane)
	player.yaw = PI          # 面朝 -Z 靶道
	player.pitch = 0.0
	_sync_m14_mods_env()   # 靶场枪模重建前同步（见 _start_mission 同注）
	guns.enter(stash.loadout)
	lobby.hide_lobby()
	hud.hide_result()
	hud.set_menu_mode("range")    # 暂停菜单/弹药 HUD 按模式分化：靶场=靶场暂停+备弹 ∞
	hud.set_raid_visible(true)
	hud.set_score_visible(true)
	hud.set_score(targets.score, targets.best)
	hud.set_danger(false)
	hud.set_extract(0.0, 1.0)
	# 进场即点破语义：靶场是练习、弹药免费，与实战消耗分清（用户反馈「分不清」）
	hud.toast("靶场练习 · 弹药免费不耗库存", Color(0.49, 0.89, 0.66))
	_apply_mode_visuals()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _back_to_lobby() -> void:
	# 放弃回大厅 = 视同阵亡（局内未结算时）；结算页回大厅已结算过，不再处理；
	# 靶场离场绝不回收——练习弹是虚拟弹药，回写库存=靶场无限刷弹漏洞
	_abandon_if_live()
	hud.hide_inventory()
	mode = Mode.LOBBY
	paused = false
	hud.set_raid_visible(false)
	hud.hide_result()
	hud.set_menu_mode("mission")   # 复位默认（实战文案）：菜单只在对局内出现
	hud.hide_menu()
	hud.set_danger(false)
	hud.set_extract(0.0, 1.0)
	lobby.show_lobby()
	_apply_mode_visuals()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _restart_current() -> void:
	# 局内重开 = 放弃当局，视同阵亡（之后按修复后的出发配置重开）；
	# 靶场重开不回收——练习弹与库存无关，直接重发一轮满额
	_abandon_if_live()
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

## 行动失败（阵亡/放弃）：背包丢失、安全箱入库、带进局的装备丢失（侦察手枪
## 除外）、记一次阵亡。返回结算明细供结算页/提示用
func _lose_raid() -> Dictionary:
	_raid_live = false
	_reclaim_ammo()   # 先按实际剩余备弹记账（保险退回的是真剩下的那些发数）
	_apply_wear()
	var bag_v := 0
	var bag := loot.drain()
	for it in bag:
		bag_v += int(float((it as Dictionary).get("value", 0)))
	var kept := loot.drain_secure()
	var kept_v := 0
	for it in kept:
		kept_v += int(float((it as Dictionary).get("value", 0)))
	stash.deposit(kept)
	var gear: Dictionary = stash.lose_carried(_raid_loadout, _raid_insured)
	stash.record_raid(false, _kills, _raid_t)
	hud.hide_inventory()
	return {"gear": gear, "bag_n": bag.size(), "bag_v": bag_v,
		"kept_n": kept.size(), "kept_v": kept_v}

## 局内未结算时的放弃/重开/转靶场：视同阵亡，顶部提示损失
func _abandon_if_live() -> void:
	if mode != Mode.MISSION or not _raid_live:
		return
	var r := _lose_raid()
	hud.toast("放弃行动（视同阵亡）· " + _gear_text(r["gear"]), Color(1.0, 0.35, 0.25))

## 本局磨损写回库存耐久（撤离/阵亡/放弃都结算；丢掉的枪耐久随枪清掉）
func _apply_wear() -> void:
	for gid in _raid_wear.keys():
		stash.wear(str(gid), float(_raid_wear[gid]))
	_raid_wear = {}

## 「M4A1、3.5× 光学镜、备弹 300 发（₵5,400）」
func _gear_text(g: Dictionary) -> String:
	var parts: Array = []
	parts.append_array(g.get("guns", []))
	parts.append_array(g.get("scopes", []))
	if int(g.get("sups", 0)) > 0:
		parts.append("消音器 ×%d" % int(g["sups"]))
	if int(g.get("ammo", 0)) > 0:
		parts.append("备弹 %d 发" % int(g["ammo"]))
	if parts.is_empty():
		return "随身无装备损失"
	return "丢失 %s（₵%s）" % ["、".join(PackedStringArray(parts)),
		HDHud._fmt(int(g.get("value", 0)))]

func _on_player_died() -> void:
	_fail_raid("行动失败")

## 局时耗尽未撤离 = 失踪（MIA），按阵亡结算
func _mia() -> void:
	_fail_raid("行动超时 · 失踪")

func _fail_raid(title: String) -> void:
	if mode != Mode.MISSION or not _raid_live:
		return
	_using = {}
	var r := _lose_raid()
	hud.set_raid_visible(false)
	var lines: Array = [[_gear_text(r["gear"]), HDHud.COL_LOSE]]
	var back: Array = (r["gear"] as Dictionary).get("back", [])
	if not back.is_empty():
		lines.append(["保险退回：%s（₵%s）" % ["、".join(PackedStringArray(back)),
			HDHud._fmt(int(r["gear"].get("back_value", 0)))], HDHud.COL_OK])
	elif _raid_insured:
		lines.append(["已投保 · 这次运气不好，一件也没退回", HDHud.COL_LOSE])
	lines.append(["背包丢失 %d 件（₵%s）" % [int(r["bag_n"]), HDHud._fmt(int(r["bag_v"]))],
		HDHud.COL_LOSE])
	if int(r["kept_n"]) > 0:
		lines.append(["安全箱保住 %d 件（₵%s）· 已入仓库" % [int(r["kept_n"]),
			HDHud._fmt(int(r["kept_v"]))], HDHud.COL_OK])
	hud.show_result(false, {
		"kills": _kills, "value": 0.0, "title": title,
		"time_sec": _raid_t, "rank": "—", "lines": lines,
	})
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _win_raid(via: String = "main") -> void:
	_raid_live = false
	if _tut >= 0:
		_tut_finish("新手引导完成 —— 第一次活着撤出来了")
	_using = {}
	hud.hide_inventory()
	var value := float(loot.bag_value())
	var bag := loot.drain()
	bag.append_array(loot.drain_secure())
	var n := stash.deposit(bag)
	_reclaim_ammo()   # 撤离：战利品入库 + 剩余备弹写回库存
	_apply_wear()
	stash.record_raid(true, _kills, _raid_t)
	hud.set_raid_visible(false)
	var lines: Array = []
	if via == "paid":
		lines.append(["付费撤离 · 已付 ₵%s" % HDHud._fmt(HDData.PAID_PRICE), HDHud.COL_ACCENT])
	hud.show_result(true, {
		"kills": _kills, "value": value, "deposited": n,
		"time_sec": _raid_t, "rank": _rank_of(value), "lines": lines,
	})
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## 评级阈值随经济重定价 ÷10（中位局约 ₵7,400）
func _rank_of(v: float) -> String:
	if v >= 30000.0:
		return "S"
	if v >= 10000.0:
		return "A"
	if v >= 3000.0:
		return "B"
	return "C"

func _on_hit_enemy(kind: String, idx: int, point: Vector3, dmg: float, head: bool) -> void:
	var res: Dictionary = soldiers.apply_hit(idx, dmg, head)
	hud.hitmark(head, bool(res.get("killed", false)), bool(res.get("armor", false)))
	audio.play_hit()

func _on_soldier_killed(info: Dictionary) -> void:
	_kills += 1
	var dist: float = float(info.get("dist", 0.0))
	var tier := str(info.get("tier", "regular"))
	if tier == "boss":
		hud.feed("击杀首领 %s · %dm · 尸体旁有贵重掉落" % [str(info.get("name", "")), int(dist)],
				Color(1.0, 0.4, 0.3))
	elif tier == "elite":
		hud.feed("击杀精英 · %dm" % int(dist), Color(0.6, 0.78, 1.0))
	elif tier == "scav":
		hud.feed("击杀搜刮者 · %dm · 搜他的尸体" % int(dist), Color(0.62, 0.8, 0.45))
	else:
		hud.feed("击杀 · %dm" % int(dist), Color(1.0, 0.7, 0.36))

## 搜刮者/首领阵亡掉落：摆在尸体旁地上（谁打死的都掉——捡漏也算）
func _on_soldier_dropped(items: Array, at: Vector3) -> void:
	for it in items:
		loot._spawn_ground(it, at)

func _on_scav_extracted(_squad: int, n_items: int) -> void:
	if mode == Mode.MISSION and _raid_live:
		hud.feed("一支搜刮者小队已撤离（带走 %d 件）" % n_items, Color(0.62, 0.8, 0.45))

## 空投落地：提示 + 增援已由 airdrop 模块召唤
func _on_airdrop_landed(at: Vector3) -> void:
	if mode == Mode.MISSION and _raid_live:
		hud.feed("空投已落地 · 守军增援正在赶往落点", Color(0.75, 0.45, 1.0))

## 敌弹命中：扣血 + 受击方向弧（来袭方向相对视线：0 正前、+ 右侧）
func _on_player_hit(dmg: float, from: Vector3) -> void:
	player.hit(dmg)
	var to := from - player.pos
	var fwd := Vector2(sin(player.yaw), cos(player.yaw))
	var right := Vector2(-cos(player.yaw), sin(player.yaw))
	var t2 := Vector2(to.x, to.z)
	hud.hit_from(atan2(t2.dot(right), t2.dot(fwd)))

## 玩家开枪：枪声传播，60 m 内的敌人警觉（改进方案第 3 节；靶场不传播）
func _on_player_fired() -> void:
	if mode == Mode.MISSION and _raid_live:
		_raid_wear[guns.cur_id] = float(_raid_wear.get(guns.cur_id, 0.0)) + HDData.DUR_PER_SHOT
		# 消音器：惊动半径 60 → 20 m
		var hr: float = HDData.SUP_HEAR_R if stash.suppressed(guns.cur_id) else HDSoldiers.SHOT_HEAR_R
		soldiers.hear_shot(player.pos + Vector3(0.0, 1.5, 0.0), hr)
		# 远处听不到枪声的兵：子弹从身边飞过也会警觉（破空声）
		soldiers.hear_bullet(player.cam.global_position, -player.cam.global_transform.basis.z)

## 方位角（度，北 = -Z 为 0、顺时针，东 = +X 为 90）
static func _bearing(dx: float, dz: float) -> float:
	return fposmod(rad_to_deg(atan2(dx, -dz)), 360.0)

## ---- 首局引导（第四阶段，改进方案第 7 节：搜箱 → 看指南针 → 撤离，三步完成；H 跳过）----
func _sync_tut() -> void:
	hud.set_tutorial(_tut, TUT_TEXT.size(), str(TUT_TEXT[_tut]) if _tut >= 0 else "")

func _tut_advance(from: int) -> void:
	if _tut != from:
		return
	_tut += 1
	_tut_face_t = 0.0
	if _tut >= TUT_TEXT.size():
		_tut_finish("新手引导完成 —— 之后每局自己来")
		return
	hud.feed("引导 %d/%d 完成" % [_tut, TUT_TEXT.size()], HDHud.COL_OK)
	_sync_tut()

func _tut_finish(msg: String) -> void:
	_tut = -1
	stash.tutorial_done = true
	stash.save()
	_sync_tut()
	hud.feed(msg, HDHud.COL_OK)

## 第 2 步：面向最近一个已开放撤离点（方位差 < 12° 持续 0.6 s）
func _step_tut(dt: float) -> void:
	if _tut != 1:
		return
	var best := INF
	var want := 0.0
	for def in world.extract_defs():
		var e: Dictionary = _extracts.get(str(def["id"]), {})
		if not bool(e.get("enabled", false)) or not bool(e.get("open", false)):
			continue
		var ep: Vector3 = def["pos"]
		var d := Vector2(ep.x - player.pos.x, ep.z - player.pos.z).length()
		if d < best:
			best = d
			want = _bearing(ep.x - player.pos.x, ep.z - player.pos.z)
	var face := _bearing(sin(player.yaw), cos(player.yaw))
	var diff := absf(fposmod(want - face + 180.0, 360.0) - 180.0)
	_tut_face_t = _tut_face_t + dt if diff < 12.0 else 0.0
	if _tut_face_t >= 0.6:
		_tut_advance(1)

func _on_loot_picked(item: Dictionary) -> void:
	_tut_advance(0)
	hud.set_backpack(loot.backpack.size(), HDData.BACKPACK_MAX, loot.secure.size(), loot.secure_cap)
	var col: Color = HDData.RARITY[int(item.get("rarity", 0))]["color"]
	hud.feed("拾取 %s %s +₵%d" % [item.get("icon", ""), item.get("name", ""), int(item.get("value", 0))], col)

## ---- Tab 背包（2026-10 改进方案第 5 节：弃件 / 安全箱）----
## 打开时世界照常运转（敌人照打），玩家原地不动、不能开火——整理背包是有风险的
func _open_inventory() -> void:
	hud.set_prompt("", 0.0)
	hud.show_inventory(loot.backpack, loot.secure, loot.secure_cap)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_inventory() -> void:
	hud.hide_inventory()
	if mode == Mode.MISSION and not hud.result_visible and not hud.menu_visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_inv_drop(from_secure: bool, idx: int) -> void:
	var fwd := Vector3(sin(player.yaw), 0.0, cos(player.yaw))
	var it: Dictionary = loot.drop_item(from_secure, idx, player.pos + fwd * 0.7)
	if not it.is_empty():
		hud.toast("丢弃 %s（₵%d）· 走近按住 F 可捡回" % [String(it.get("name", "")),
			int(float(it.get("value", 0)))], Color(0.85, 0.87, 0.82))
	_refresh_bag_hud()

func _on_inv_move(from_secure: bool, idx: int) -> void:
	if not loot.move_secure(from_secure, idx):
		hud.toast("背包已满" if from_secure else "安全箱已满（大厅交易行可扩容）",
			Color(1.0, 0.55, 0.3))
	_refresh_bag_hud()

func _refresh_bag_hud() -> void:
	hud.set_backpack(loot.backpack.size(), HDData.BACKPACK_MAX, loot.secure.size(), loot.secure_cap)
	if hud.inv_visible:
		hud.refresh_inventory(loot.backpack, loot.secure, loot.secure_cap)

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
	if mode == Mode.MISSION and hud.inv_visible:
		_step_world_only(dt)   # 背包打开：世界照常，玩家不动
		return
	if mode == Mode.MISSION:
		_step_mission(dt)
	elif mode == Mode.RANGE:
		_step_range(dt)

func _step_mission(dt: float) -> void:
	_raid_t += dt
	if _tick_raid_clock():
		return
	player.update(dt)
	if _using.is_empty():
		guns.update(dt)          # 使用物资时收枪：不能开火/换弹
	soldiers.update(dt, true)
	loot.update(dt, player.pos, Input.is_action_pressed("hd_interact"))
	targets.update(dt)
	airdrop.update(dt)
	_step_lever(dt)
	_step_tut(dt)
	_step_use(dt)
	hud.set_armor(player.armor)
	hud.set_uses(loot.use_counts())
	# 危险区横幅（中心与大坝同为高危红区；坝兵横幅走玩家 zone_at 实时裁决）
	var pz: String = world.zone_at(player.pos.x, player.pos.z)
	hud.set_danger(pz == "center" or pz == "dam")
	# 弹药/血量/背包同步
	hud.set_ammo(guns.ammo, guns.reserve)
	hud.set_health(player.health, 100.0)
	hud.set_backpack(loot.backpack.size(), HDData.BACKPACK_MAX, loot.secure.size(), loot.secure_cap)
	# 开镜分划
	var sc: Dictionary = _scope_for(guns.cur_id)
	hud.set_scope(str(sc.get("kind", "iron")), float(sc.get("zoom", 1.0)), player.ads > 0.5)
	hud.set_compass(_bearing(sin(player.yaw), cos(player.yaw)), _compass_marks())
	# 玩家脚步（2D 轻声）：每走一步响一声，疾跑更响更密、蹲走几乎无声
	var mv := Vector2(player.pos.x - _last_ppos.x, player.pos.z - _last_ppos.z).length()
	_last_ppos = player.pos
	if mv < 1.0:   # 传送（进场/探针摆位）不算步子
		_step_acc += mv
		var stride := 2.0 if player.sprinting else 1.5
		if _step_acc >= stride:
			_step_acc = 0.0
			audio.play_step(0.12 if player.crouching else (0.6 if player.sprinting else 0.32))
	# 撤离读条：只在本局启用且已开放的撤离点（主 / 大坝 12:00 后 / 付费 / 拉闸后）
	# 取最近点，圈内累计/离圈回退；付费撤离现金不足不读条
	var d := HDData.EXTRACT_R + 1.0
	var best_id := ""
	for def in world.extract_defs():
		var eid := str(def["id"])
		var e: Dictionary = _extracts.get(eid, {})
		if not bool(e.get("enabled", false)) or not bool(e.get("open", false)):
			continue
		var dd := player.pos.distance_to(def["pos"])
		if dd < d:
			d = dd
			best_id = eid
	if d <= HDData.EXTRACT_R and best_id == "paid" and stash.cash < HDData.PAID_PRICE:
		hud.set_prompt("付费撤离需 ₵%s —— 现金不足" % HDHud._fmt(HDData.PAID_PRICE), -1.0)
		_extract_t = maxf(0.0, _extract_t - dt * 2.0)
	elif d <= HDData.EXTRACT_R:
		_extract_t += dt
		if _extract_t >= HDData.EXTRACT_HOLD:
			_extract_t = 0.0
			if best_id == "paid":
				stash.cash -= HDData.PAID_PRICE
				stash.save()
				stash.changed.emit()
			_win_raid(best_id)
			return
	else:
		_extract_t = maxf(0.0, _extract_t - dt * 2.0)
	hud.set_extract(_extract_t, HDData.EXTRACT_HOLD)

## 背包打开时：敌人与靶子照常推进、局时照走；玩家/枪/搜刮/撤离读条暂停
func _step_world_only(dt: float) -> void:
	_raid_t += dt
	if _tick_raid_clock():
		return
	player.update(0.0)
	soldiers.update(dt, true)
	targets.update(dt)
	airdrop.update(dt)
	hud.set_health(player.health, 100.0)
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

## ---- 第三阶段：局时 / 撤离点 / 电闸 / 物资 ----

## 局时：剩余时间上 HUD；剩 5 分钟、1 分钟各提醒一次；耗尽 = 失踪。返回 true = 本帧已结算
func _tick_raid_clock() -> bool:
	var left := HDData.RAID_TIME - _raid_t
	hud.set_raid_timer(left)
	for w in [300, 60]:
		if left <= float(w) and not _warned.has(w):
			_warned[w] = true
			hud.toast("撤离窗口还剩 %d 分钟 —— 超时未撤出 = 失踪" % (w / 60), Color(1.0, 0.35, 0.25))
	if left <= 0.0:
		_mia()
		return true
	# 第 10 分钟空投：随机落点冒红烟，约 18 s 后伞降落地
	if not _airdrop_fired and _raid_t >= HDData.AIRDROP_T:
		_airdrop_fired = true
		var ap: Vector3 = HDData.AIRDROP_POINTS[randi() % HDData.AIRDROP_POINTS.size()]
		airdrop.trigger(ap)
		var dir_names := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
		var bdeg := _bearing(ap.x - player.pos.x, ap.z - player.pos.z)
		hud.toast("空投已投放 · %s方向 %dm · 红色烟雾标记落点（紫色及以上 + 物资）" % [
			dir_names[int(round(bdeg / 45.0)) % 8],
			int(Vector2(ap.x - player.pos.x, ap.z - player.pos.z).length())], Color(0.75, 0.45, 1.0))
	# 大坝撤离点 12 分钟后开放
	var dam: Dictionary = _extracts.get("dam", {})
	if bool(dam.get("enabled", false)) and not bool(dam.get("open", false)) \
			and _raid_t >= HDData.DAM_OPEN_T:
		dam["open"] = true
		_sync_extract_vis()
		hud.toast("大坝撤离点已开放", Color(0.49, 0.89, 0.66))
	return false

## 每局撤离点：主撤离常开；大坝定时；付费 / 拉闸各按概率启用（每局组合不同）
func _setup_extracts() -> void:
	_extracts = {
		"main": {"enabled": true, "open": true},
		"dam": {"enabled": true, "open": false},
		"paid": {"enabled": randf() < float(HDData.EXTRACT_ODDS["paid"]), "open": true},
		"lever": {"enabled": randf() < float(HDData.EXTRACT_ODDS["lever"]), "open": false},
	}
	_lever_t = 0.0
	world.set_lever_pulled(false)
	_sync_extract_vis()

func _sync_extract_vis() -> void:
	for eid in _extracts:
		var e: Dictionary = _extracts[eid]
		var st := "off"
		if bool(e["enabled"]):
			st = "open" if bool(e["open"]) else "closed"
		world.set_extract_state(str(eid), st)

## 电闸：启用拉闸撤离的局，进变电站主控楼按住 F 2 s 拉下 → 东门撤离点开放，
## 动静惊动 80 m 内敌人
func _step_lever(dt: float) -> void:
	var lev: Dictionary = _extracts.get("lever", {})
	if not bool(lev.get("enabled", false)) or bool(lev.get("open", false)):
		return
	var lp := HDData.LEVER_POS
	if Vector2(player.pos.x - lp.x, player.pos.z - lp.z).length() > 1.6:
		_lever_t = 0.0
		return
	if Input.is_action_pressed("hd_interact"):
		_lever_t += dt
		if _lever_t >= HDData.LEVER_HOLD:
			_pull_lever()
			return
	else:
		_lever_t = maxf(0.0, _lever_t - dt)
	hud.set_prompt("按住 F 拉闸 —— 打开变电站东门撤离（动静很大）", _lever_t / HDData.LEVER_HOLD)

func _pull_lever() -> void:
	_extracts["lever"]["open"] = true
	_lever_t = 0.0
	world.set_lever_pulled(true)
	_sync_extract_vis()
	soldiers.hear_shot(HDData.LEVER_POS + Vector3(0.0, 1.5, 0.0), HDData.LEVER_ALERT_R)
	hud.set_prompt("", 0.0)
	hud.toast("电闸已拉下 · 变电站东门撤离点开放 —— 附近敌人被惊动了", Color(0.3, 0.7, 1.0))

## 指南针标记：本局启用的撤离点（开放 / 未开放倒计时 / 付费价 / 待拉闸）+ 电闸位置
func _compass_marks() -> Array:
	var marks: Array = []
	for def in world.extract_defs():
		var eid := str(def["id"])
		var e: Dictionary = _extracts.get(eid, {})
		if not bool(e.get("enabled", false)):
			continue
		var ep: Vector3 = def["pos"]
		var dx := ep.x - player.pos.x
		var dz := ep.z - player.pos.z
		var dist := int(Vector2(dx, dz).length())
		var col := Color(0.49, 0.89, 0.66)
		var label := "%s %dm" % [str(def["name"]), dist]
		if eid == "paid":
			col = Color(1.0, 0.78, 0.25)
			label = "付费 ₵%d · %dm" % [HDData.PAID_PRICE, dist]
		elif eid == "lever":
			col = Color(0.3, 0.7, 1.0)
		if not bool(e.get("open", false)):
			col = Color(0.62, 0.62, 0.62)
			if eid == "dam":
				var wait := maxf(0.0, HDData.DAM_OPEN_T - _raid_t)
				label = "大坝 %d:%02d 后开放" % [int(wait) / 60, int(wait) % 60]
			elif eid == "lever":
				label = "拉闸撤离 · 未通电"
		marks.append({"bearing": _bearing(dx, dz), "label": label, "color": col})
	var lev: Dictionary = _extracts.get("lever", {})
	if bool(lev.get("enabled", false)) and not bool(lev.get("open", false)):
		var lp := HDData.LEVER_POS
		marks.append({"bearing": _bearing(lp.x - player.pos.x, lp.z - player.pos.z),
			"label": "电闸 %dm" % int(Vector2(lp.x - player.pos.x, lp.z - player.pos.z).length()),
			"color": Color(0.3, 0.7, 1.0)})
	# 首局引导第 1 步：最近一个未搜容器
	if _tut == 0:
		var bd := INF
		var bp := Vector3.ZERO
		for c in loot._containers:
			if bool(c["searched"]) or str(c["cls"]) == "vault":
				continue
			var cp: Vector3 = c["pos"]
			var dd := Vector2(cp.x - player.pos.x, cp.z - player.pos.z).length()
			if dd < bd:
				bd = dd
				bp = cp
		if bd < INF:
			marks.append({"bearing": _bearing(bp.x - player.pos.x, bp.z - player.pos.z),
				"label": "箱子 %dm" % int(bd), "color": Color(1.0, 0.66, 0.3)})
	# 空投（投放后到搜空前）：紫色标记 + 距离
	if airdrop != null and str(airdrop.state) != "idle" and not _airdrop_looted():
		var adp: Vector3 = airdrop.pos
		marks.append({"bearing": _bearing(adp.x - player.pos.x, adp.z - player.pos.z),
			"label": "空投 %dm" % int(Vector2(adp.x - player.pos.x, adp.z - player.pos.z).length()),
			"color": Color(0.75, 0.45, 1.0)})
	return marks

func _airdrop_looted() -> bool:
	for c in loot._containers:
		if str(c["cls"]) == "airdrop":
			return bool(c["searched"])
	return false

## 用物资（3/4/5/6 或背包「使用」）：读条期间收枪；医疗包满血/护甲满拒用
func _use_item(kind: String) -> void:
	if not _using.is_empty() or player.dead or not _raid_live:
		return
	var c: Dictionary = HDData.CONSUMABLES.get(kind, {})
	if c.is_empty():
		return
	if int(loot.use_counts().get(kind, 0)) <= 0:
		hud.feed("背包里没有%s" % str(c["name"]), Color(0.85, 0.87, 0.82))
		return
	if kind == "medkit" and player.health >= 100.0:
		hud.feed("血量已满", Color(0.85, 0.87, 0.82))
		return
	if kind == "plate" and player.armor >= HDData.ARMOR_MAX:
		hud.feed("护甲已满", Color(0.85, 0.87, 0.82))
		return
	_using = {"kind": kind, "t": 0.0, "dur": float(c["use_t"])}

func _step_use(dt: float) -> void:
	if _regen_left > 0.0:
		var r := minf(_regen_left, HDData.PILLS_HEAL / HDData.PILLS_TIME * dt)
		player.heal(r)
		_regen_left -= r
	if _using.is_empty():
		return
	_using["t"] = float(_using["t"]) + dt
	var kind := str(_using["kind"])
	var c: Dictionary = HDData.CONSUMABLES[kind]
	hud.set_prompt("使用%s…" % str(c["name"]), float(_using["t"]) / float(_using["dur"]))
	if float(_using["t"]) < float(_using["dur"]):
		return
	_using = {}
	hud.set_prompt("", 0.0)
	if not loot.consume(kind):
		return
	match kind:
		"medkit":
			player.heal(HDData.MEDKIT_HEAL)
		"pills":
			_regen_left += HDData.PILLS_HEAL
		"plate":
			player.armor = minf(HDData.ARMOR_MAX, player.armor + HDData.PLATE_ARMOR)
		"ammo":
			var mag := int(Guns.gun_by_id(guns.cur_id).get("mag", 30))
			guns.reserve += mag * HDData.AMMO_BOX_MAGS
	hud.feed("用掉 %s" % str(c["name"]), HDData.RARITY[int(c["rarity"])]["color"])
	_refresh_bag_hud()

func _on_inv_use(from_secure: bool, idx: int) -> void:
	var lst: Array = loot.secure if from_secure else loot.backpack
	if idx < 0 or idx >= lst.size():
		return
	var kind := str((lst[idx] as Dictionary).get("use", ""))
	if kind == "":
		hud.feed("这件不能用 —— 只能带出去卖", Color(0.85, 0.87, 0.82))
		return
	if from_secure:
		hud.feed("先把它从安全箱取回背包再用", Color(0.85, 0.87, 0.82))
		return
	_close_inventory()
	_use_item(kind)

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
	# 暂停菜单：1/2/3（按模式分化——实战 2=重开靶场 3=放弃行动；
	# 靶场 2=离开靶场回大厅、3 不存在；HUD._input 已先处理并标记消费，
	# 此处是与 HUD 同口径的兜底分发）
	if hud.menu_visible:
		if code == KEY_1:
			hud.menu_restart.emit()
		elif code == KEY_2:
			if mode == Mode.RANGE:
				hud.menu_abort.emit()
			else:
				hud.menu_range.emit()
		elif code == KEY_3 and mode != Mode.RANGE:
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
	# 对局内：Tab 背包（只在实战；打开后的按键由 HUD 自处理并消费）
	if code == KEY_TAB and mode == Mode.MISSION:
		_open_inventory()
		return
	if code == KEY_H and mode == Mode.MISSION and _tut >= 0:
		_tut_finish("已跳过新手引导")
		return
	# 对局内：3/4/5/6 用医疗包 / 止痛药 / 护甲板 / 弹药盒
	if mode == Mode.MISSION and code >= KEY_3 and code <= KEY_6:
		_use_item(str(HDData.USE_KEYS[code - KEY_3]))
		return
	# 对局内：Esc 菜单
	if code == KEY_ESCAPE:
		paused = true
		hud.show_menu()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
