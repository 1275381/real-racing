class_name HDSoldiers
extends Node3D
## 烽火地带敌兵 —— 网页版 js/fps/enemies.js 状态机的 Godot 移植：
## patrol 巡逻（沿巡逻点环形走）→ combat 交战（站定/小侧移 + 点射）→
## search 搜索最后目击点 → 超时回巡逻；死亡不重生（撤离玩法的损失感）。
## 加载/配色/命中球/点射节奏照抄 battlefield.gd（见各常量注）；
## 视距视锥/受击还击/死亡淡出对齐网页版 enemies.js。
## 契约（main.gd 装配）：build(world, player, audio) / update(dt, raid_active) /
## raycast / apply_hit / reset_all / alive_count / soldiers / player_hit / killed / all_dead。

signal player_hit(dmg: float)    # 敌弹命中玩家（main 接到 player.hit）
signal killed(info: Dictionary)  # {i, dist} 击杀播报（dist = 玩家到目标的水平距离）
signal all_dead()                # 全灭（只发一次）

const TracerPool := preload("res://scripts/tracer_pool.gd")

## 士兵模型与大战场共用；load 而非 preload：模型走 Git LFS，另一台电脑没拉到真文件
## 时 preload 会让脚本编译失败（battlefield.gd:43-46 同款兜底），失败退化胶囊人
const SOLDIER_PATH := "res://assets/battle/soldier.glb"
const SOLDIER_SCALE := 1.1                 # 模型/命中球统一放大倍率：1.95m 略压玩家（1.55m 眼高）
                                           # 有压迫感但不畸形；1.5 是大战场遗产（AI 2.65m vs 玩家 1.55m）
const UNIFORM_COL := Color(0.7, 0.5, 0.4)  # 敌军赭红：军装（battlefield._apply_team_colors）
const GEAR_COL := Color(0.48, 0.41, 0.33)  # 敌军赭红：装具
const UNIFORM_EMISSION := 0.18             # 军装/装具微自发光：远景从雾里提对比（问题②，宁少勿假）

const AI_TICK := 1.0 / 60.0     # AI 定步（battlefield.gd:22，与渲染帧解耦）
const ENEMY_HP := 100.0
const PATROL_SPEED := 3.0       # 巡逻步行
const SEARCH_SPEED_MUL := 0.62  # 搜索小跑（enemies.js SEARCH_SPEED_MUL）
const ENGAGE_SPEED_MUL := 0.45  # 交战移速 ×0.45（小侧移，battlefield/enemies.js 同款）

const VIEW_DIST := 55.0         # 索敌视距（进战后 ENGAGE_DIST）
const ENGAGE_DIST := 70.0       # 进战视距 = 敌弹射程
const FOV_COS := 0.5736         # cos(55°)：视锥 110° 半角（背身看不见）
const LOS_RECHECK := 0.4        # 视线复测周期（battlefield.gd:388）
const LOSE_TIME := 6.0          # 玩家离开视距 6s 转 search
const SEARCH_TIME := 14.0       # 搜索超时回巡逻（enemies.js SEARCH_TIME）
const SEARCH_PICK_T := 3.0      # 搜索目标点换选周期（秒）
const SEARCH_WANDER := 9.0      # 搜索目标点在最后目击点附近的游走半径（米）

const BURST_MIN := 3            # 点射发数 3-5
const BURST_MAX := 5
const FIRE_CD := 0.13           # 点射内发弹间隔（rifle cd，guns.gd）
const BURST_PAUSE_MIN := 1.1    # 点射间歇（battlefield.gd:607 同款）
const BURST_PAUSE_MAX := 2.2
const MAG_SIZE := 30            # rifle 弹匣
const RELOAD_T := 2.2
const SPREAD_BASE := 0.03       # 基础散布 + 距离/60 × 0.05
const SPREAD_PER_M := 0.05 / 60.0
const SPRINT_SPREAD_MUL := 1.4  # 玩家疾跑散布再放大
const SPRINT_SPEED := 8.0       # move_speed ≥ 此值视为疾跑（onfoot 步 6 / 跑 11.5）
const RIFLE_DMG := 20.0         # guns.gd rifle 单发伤害
const AI_DMG_MUL := 0.55        # AI 削弱（对齐网页版 -45%）
const HIT_R := 0.5              # 玩家命中球半径
const EYE_H := 1.5              # 敌弹出发点/视线高度（pos + 1.5）
const CHEST_Y := 1.05           # 玩家胸口：瞄准点 + 命中球心
# 枪口（GLB 模型单位）：battlefield.gd:48 的 1.5× 实测值 ÷1.5 换算回模型单位，
# 使用处乘 SOLDIER_SCALE——改比例常量枪口曳光不脱靶
const MUZZLE_LOCAL := Vector3(-0.08, 1.0, 0.633)

const SEP_DIST := 2.2           # 同队推挤（battlefield.gd:559-560）
const SEP_PUSH := 2.5
const MOVE_R := 0.4             # push_out 半径（battlefield._apply_move）
const MAP_EDGE := 165.0   # 不出地图 ±(MAP_HALF-5)，HDData.MAP_HALF=170
const DEATH_HOLD := 8.0         # 倒地停留后淡出
const FADE_TIME := 1.0

var soldiers: Array = []   # battlefield 风格 Dictionary 数组 {pos,yaw,hp,dead,state,moving,engaged,...}
var _world                 # HDWorld（鸭子）：patrol_spots/obstacles_near/ground_height/wall_hit
var _player                # HDPlayer（鸭子）：pos（可选 dead/health/move_speed 走 get() 探测）
var _audio                 # HDAudio（鸭子）：play_shot("rifle")
var _bodies: Array = []    # 每兵一个模型槽 {node,ap,mesh,mats,anim,fading,faded}
var _tracers               # 曳光池（自己持有，敌弹橙色）
var _ai_acc := 0.0
var _all_dead_sent := false


## 装配：世界/玩家/声音引用 + 模型槽位 + 曳光池；巡逻点全部点各 1 兵
func build(world, player, audio) -> void:
	_world = world
	_player = player
	_audio = audio
	_tracers = TracerPool.new()
	add_child(_tracers)
	_tracers.setup(32, Color(1.0, 0.55, 0.35), 4.0, 0.03)
	var scene: PackedScene = load(SOLDIER_PATH) if ResourceLoader.exists(SOLDIER_PATH) else null
	if scene == null:
		push_warning("[烽火地带] 士兵模型加载失败：%s —— 暂用胶囊人代替" % SOLDIER_PATH)
	soldiers.clear()
	var spots: Array = _world.patrol_spots
	for k in spots.size():
		var spot: Dictionary = spots[k]
		var sp: Vector3 = spot["pos"]
		var home := Vector3(sp.x, _ground_y(sp.x, sp.z), sp.z)
		# 路线 = 家门口 + 最近的 2 个巡逻点（没有寻路，卡墙靠绕行兜底）
		var others: Array = []
		for j in spots.size():
			if j == k:
				continue
			var op: Vector3 = spots[j]["pos"]
			others.append({"p": op, "d": Vector2(op.x - home.x, op.z - home.z).length_squared()})
		others.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
		var route: Array = [home]
		for j in mini(2, others.size()):
			route.append(others[j]["p"])
		var wi := 1 if route.size() > 1 else 0
		var wp: Vector3 = route[wi]
		soldiers.append({
			"slot": k,
			"pos": home, "yaw": atan2(wp.x - home.x, wp.z - home.z), "hp": ENEMY_HP,
			"dead": false, "state": "patrol", "moving": false, "engaged": false,
			"zone": str(spot.get("zone", "mid")),
			"home": home, "route": route, "wp": wi,
			"fire_cd": randf_range(0.5, 1.5), "burst": 0, "mag": MAG_SIZE, "reload_t": 0.0,
			"los_ok": false, "los_t": randf_range(0.0, 0.4), "lost_t": 0.0,
			"last_known": home, "search_t": 0.0, "search_pick_t": 0.0, "search_goal": home,
			"strafe_t": 0.0, "strafe_dir": 1.0,
			"block_t": 0.0, "detour_t": 0.0, "detour_dir": Vector2.ZERO,
			"death_t": 0.0,
		})
		_bodies.append(_make_body(scene))


func update(dt: float, raid_active: bool) -> void:
	if _tracers != null:
		_tracers.tick(dt)
	_ai_acc += dt
	var steps := 0
	while _ai_acc >= AI_TICK and steps < 3:
		_ai_acc -= AI_TICK
		steps += 1
		for i in soldiers.size():
			_update_soldier(i, AI_TICK, raid_active)
	_tick_deaths(dt)


## 玩家子弹射线（battlefield.raycast 同契约）：士兵头/胸命中球，死兵不挡弹。
## 只判士兵：墙体命中由持 world 的调用方合成（wall_hit 距离更近则吞弹）
func raycast(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var best := {"type": "", "i": -1, "d": max_d, "point": from + dir * max_d}
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["dead"]:
			continue
		# 命中球半径同步 SOLDIER_SCALE（模型放大后按原半径判会「看着打中没判定」）
		var hc: Vector3 = s["pos"] + Vector3(0, 1.65 * SOLDIER_SCALE, 0)   # 头盔中心
		var th: float = (hc - from).dot(dir)
		if th > 0.5 and th < best["d"] and (hc - from - dir * th).length() < 0.2 * SOLDIER_SCALE:
			best = {"type": "soldier_head", "i": i, "d": th, "point": from + dir * th}
			continue
		var c: Vector3 = s["pos"] + Vector3(0, 1.05 * SOLDIER_SCALE, 0)    # 胸口
		var t: float = (c - from).dot(dir)
		if t > 0.5 and t < best["d"] and (c - from - dir * t).length() < 0.5 * SOLDIER_SCALE:
			best = {"type": "soldier", "i": i, "d": t, "point": from + dir * t}
	return best


## 玩家子弹结算（爆头 ×2 已在 guns 侧乘好）；打死了发 death 动画 + killed 播报
func apply_hit(i: int, dmg: float, head: bool) -> Dictionary:
	if i < 0 or i >= soldiers.size():
		return {"killed": false}
	var s: Dictionary = soldiers[i]
	if s["dead"]:
		return {"killed": false}
	s["hp"] = float(s["hp"]) - dmg
	if float(s["hp"]) > 0.0:
		_agro(s)   # 受击即还击：立即转向玩家并进入交战
		return {"killed": false}
	s["dead"] = true
	s["state"] = "dead"
	s["moving"] = false
	s["engaged"] = false
	s["death_t"] = 0.0
	_write_pose(i)
	var pp: Vector3 = _ppos()
	var dist: float = Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length()
	killed.emit({"i": i, "dist": dist})
	if soldiers.size() > 0 and alive_count() == 0 and not _all_dead_sent:
		_all_dead_sent = true
		all_dead.emit()
	return {"killed": true}


## 重开一局：全员重生于各自巡逻点（局内死亡不复活，重开是例外）
func reset_all() -> void:
	_all_dead_sent = false
	if _tracers != null:
		_tracers.hide_all()
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		var home: Vector3 = s["home"]
		s["pos"] = Vector3(home.x, _ground_y(home.x, home.z), home.z)
		var route: Array = s["route"]
		s["wp"] = 1 if route.size() > 1 else 0
		var fw: Vector3 = route[int(s["wp"])]
		s["yaw"] = atan2(fw.x - s["pos"].x, fw.z - s["pos"].z)
		s["hp"] = ENEMY_HP
		s["dead"] = false
		s["state"] = "patrol"
		s["moving"] = false
		s["engaged"] = false
		s["fire_cd"] = randf_range(0.5, 1.5)
		s["burst"] = 0
		s["mag"] = MAG_SIZE
		s["reload_t"] = 0.0
		s["los_ok"] = false
		s["los_t"] = randf_range(0.0, 0.4)
		s["lost_t"] = 0.0
		s["last_known"] = s["pos"]
		s["search_t"] = 0.0
		s["search_pick_t"] = 0.0
		s["search_goal"] = s["pos"]
		s["death_t"] = 0.0
		s["block_t"] = 0.0
		s["detour_t"] = 0.0
		# 上局淡出过的材质复原
		var b: Dictionary = _bodies[i]
		b["fading"] = false
		b["faded"] = false
		for m in b["mats"]:
			var sm: StandardMaterial3D = m
			sm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			sm.albedo_color.a = 1.0
		_write_pose(i)


func alive_count() -> int:
	var n := 0
	for s in soldiers:
		if not s["dead"]:
			n += 1
	return n


# ================= 士兵 AI（1/60 定步） =================

func _update_soldier(i: int, dt: float, raid_active: bool) -> void:
	var s: Dictionary = soldiers[i]
	if s["dead"]:
		return   # 死亡表现（death 动画已定格，淡出）走 _tick_deaths
	# 视线/可见性复测（错峰 0.4s；非行动期一律视为丢失：大厅/靶场不索敌不开火）
	if raid_active:
		s["los_t"] = float(s["los_t"]) - dt
		if float(s["los_t"]) <= 0.0:
			s["los_t"] = LOS_RECHECK
			s["los_ok"] = _can_see_player(s)
	else:
		s["los_ok"] = false
	var state: String = s["state"]
	var dist := _pdist(s)
	var engaged := false
	if state == "combat":
		if not _player_alive():
			_to_search(s)
		else:
			if s["los_ok"] and dist < ENGAGE_DIST:
				engaged = true
				s["lost_t"] = 0.0
				s["last_known"] = _peye()
			else:
				s["lost_t"] = float(s["lost_t"]) + dt
			if engaged:
				_combat_move(s, dist, dt)   # 站定/小侧移，面向玩家
			else:
				_move_toward(s, s["last_known"], PATROL_SPEED * ENGAGE_SPEED_MUL, dt)
			if float(s["lost_t"]) > LOSE_TIME:
				_to_search(s)
	elif state == "search":
		if s["los_ok"]:
			_to_combat(s)
			engaged = true
		else:
			s["search_t"] = float(s["search_t"]) - dt
			s["search_pick_t"] = float(s["search_pick_t"]) - dt
			if float(s["search_pick_t"]) <= 0.0:
				_pick_search_goal(s)
			if _move_toward(s, s["search_goal"], PATROL_SPEED * SEARCH_SPEED_MUL, dt) \
					or float(s["search_t"]) <= 0.0:
				_to_patrol(s)
	else:
		if s["los_ok"]:
			_to_combat(s)
			engaged = true
		else:
			_patrol_move(s, dt)
	s["engaged"] = engaged
	_write_pose(i)
	if engaged:
		_try_fire(s, dt, dist)


func _to_combat(s: Dictionary) -> void:
	s["state"] = "combat"
	s["los_ok"] = true
	s["lost_t"] = 0.0
	s["last_known"] = _peye()


func _to_search(s: Dictionary) -> void:
	s["state"] = "search"
	s["engaged"] = false
	s["search_t"] = SEARCH_TIME
	s["search_pick_t"] = 0.0
	_pick_search_goal(s)


## 搜索目标点：在最后目击点附近随机游走（周期由 search_pick_t 控制），不出地图
func _pick_search_goal(s: Dictionary) -> void:
	s["search_pick_t"] = SEARCH_PICK_T
	var lk: Vector3 = s["last_known"]
	var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * SEARCH_WANDER
	var g := lk + off
	g.x = clampf(g.x, -MAP_EDGE, MAP_EDGE)
	g.z = clampf(g.z, -MAP_EDGE, MAP_EDGE)
	g.y = 0.0
	s["search_goal"] = g


func _to_patrol(s: Dictionary) -> void:
	s["state"] = "patrol"
	s["engaged"] = false
	# 回最近的巡逻点接着走
	var route: Array = s["route"]
	var bi := 0
	var bd := INF
	for k in route.size():
		var wp: Vector3 = route[k]
		var d := Vector2(wp.x - s["pos"].x, wp.z - s["pos"].z).length_squared()
		if d < bd:
			bd = d
			bi = k
	s["wp"] = bi


## 受击即还击：立即（不 lerp）转向玩家并进入交战，最后目击点同步为玩家眼位
func _agro(s: Dictionary) -> void:
	var pe: Vector3 = _peye()
	s["state"] = "combat"
	s["los_ok"] = true
	s["los_t"] = LOS_RECHECK
	s["lost_t"] = 0.0
	s["last_known"] = pe
	s["yaw"] = atan2(pe.x - s["pos"].x, pe.z - s["pos"].z)


## 索敌：视距（巡逻 55 / 进战 70）+ 视锥 110° + wall_hit 未挡
func _can_see_player(s: Dictionary) -> bool:
	if not _player_alive():
		return false
	var se: Vector3 = s["pos"] + Vector3(0, EYE_H, 0)
	var pe: Vector3 = _peye()
	var to: Vector3 = pe - se
	var dist := Vector2(to.x, to.z).length()
	var vd: float = ENGAGE_DIST if str(s["state"]) == "combat" else VIEW_DIST
	if dist > vd:
		return false
	if dist > 0.5:   # 视锥：面朝基 (sin yaw, cos yaw)，背身 110° 外看不见
		var dir2 := Vector2(to.x, to.z) / dist
		var fwd := Vector2(sin(float(s["yaw"])), cos(float(s["yaw"])))
		if fwd.dot(dir2) < FOV_COS:
			return false
	return not _blocked(se, pe)


## 巡逻：沿巡逻点环形走
func _patrol_move(s: Dictionary, dt: float) -> void:
	var route: Array = s["route"]
	if route.is_empty():
		s["moving"] = false
		return
	var wi := int(s["wp"]) % route.size()
	if _move_toward(s, route[wi], PATROL_SPEED, dt):
		s["wp"] = (wi + 1) % route.size()


## 交战走位：近距小侧移 / 远距站定（契约：站定/小侧移），始终面向玩家
func _combat_move(s: Dictionary, dist: float, dt: float) -> void:
	var to_p: Vector3 = _ppos() - s["pos"]
	var tdir := Vector2(to_p.x, to_p.z) / maxf(Vector2(to_p.x, to_p.z).length(), 0.01)
	var move := Vector2.ZERO
	if dist < 22.0:
		s["strafe_t"] = float(s["strafe_t"]) - dt
		if float(s["strafe_t"]) <= 0.0:
			s["strafe_t"] = randf_range(1.5, 3.5)
			s["strafe_dir"] = -float(s["strafe_dir"])
		move = Vector2(-tdir.y, tdir.x) * float(s["strafe_dir"])
	_apply_move(s, move, tdir, PATROL_SPEED * ENGAGE_SPEED_MUL, dt)


## 朝目标点走（XZ），到点返回 true
func _move_toward(s: Dictionary, goal: Vector3, speed: float, dt: float) -> bool:
	var to: Vector3 = goal - s["pos"]
	var d := Vector2(to.x, to.z).length()
	if d < 1.2:
		s["moving"] = false
		return true
	var dir2 := Vector2(to.x, to.z) / d
	_apply_move(s, dir2, dir2, speed, dt)
	return false


## 移动执行（battlefield._apply_move 同款）：同队推挤 + 卡墙绕行 + 障碍推出 + 贴地
func _apply_move(s: Dictionary, move: Vector2, face: Vector2, speed: float, dt: float) -> void:
	var vel := move * speed
	# 同队间隔（全场一伙，防止叠成一坨）
	var sp := Vector2(s["pos"].x, s["pos"].z)
	for o in soldiers:
		if o["dead"] or o["slot"] == s["slot"]:
			continue
		var dv: Vector2 = sp - Vector2(o["pos"].x, o["pos"].z)
		var d := dv.length()
		if d > 0.01 and d < SEP_DIST:
			vel += dv / d * (SEP_DIST - d) * SEP_PUSH
	# 绕行：被墙挡住时沿垂直方向横移一阵
	if float(s["detour_t"]) > 0.0:
		s["detour_t"] = float(s["detour_t"]) - dt
		vel = Vector2(s["detour_dir"]) * speed
	var want_step := vel.length() * dt
	var np := sp + vel * dt
	np.x = clampf(np.x, -MAP_EDGE, MAP_EDGE)
	np.y = clampf(np.y, -MAP_EDGE, MAP_EDGE)
	np = _push_out(np, MOVE_R)
	# 卡墙判定：想走却只走出不到 30%，累计 0.4s 就开始绕（battlefield.gd:571-581）
	if want_step > 0.02 and np.distance_to(sp) < want_step * 0.3:
		s["block_t"] = float(s["block_t"]) + dt
		if float(s["block_t"]) > 0.4 and float(s["detour_t"]) <= 0.0:
			s["block_t"] = 0.0
			var side := 1.0 if randf() < 0.5 else -1.0
			s["detour_dir"] = Vector2(-move.y, move.x).normalized() * side \
					if move.length_squared() > 0.01 else Vector2(side, 0)
			s["detour_t"] = randf_range(0.8, 1.6)
	else:
		s["block_t"] = maxf(0.0, float(s["block_t"]) - dt)
	s["pos"] = Vector3(np.x, _ground_y(np.x, np.y), np.y)
	s["moving"] = move.length_squared() > 0.01
	if face.length_squared() > 0.0001:
		var want := atan2(face.x, face.y)
		s["yaw"] = lerp_angle(float(s["yaw"]), want, 1.0 - exp(-10.0 * dt))


## 圆（半径 r）从障碍物中推出（onfoot.push_out 同款；HDWorld 障碍为轴对齐 {cx,cz,hx,hz,top,bot}）
func _push_out(np: Vector2, r: float) -> Vector2:
	for ob in _world.obstacles_near(np.x, np.y):
		if ob.has("top") and 0.0 > float(ob["top"]) - 1.0:
			continue
		if ob.has("bot") and 1.6 < float(ob["bot"]):
			continue
		var cx: float = float(ob["cx"])
		var cz: float = float(ob["cz"])
		var dx: float = np.x - cx
		var dz: float = np.y - cz
		var px: float = float(ob["hx"]) + r - absf(dx)
		var pz: float = float(ob["hz"]) + r - absf(dz)
		if px > 0.0 and pz > 0.0:
			if px < pz:
				np.x = cx + signf(dx) * (float(ob["hx"]) + r)
			else:
				np.y = cz + signf(dz) * (float(ob["hz"]) + r)
	return np


# ================= 开火：点射 + 距离精度衰减 =================

func _try_fire(s: Dictionary, dt: float, dist: float) -> void:
	s["fire_cd"] = float(s["fire_cd"]) - dt
	if float(s["fire_cd"]) > 0.0:
		return
	if float(s["reload_t"]) > 0.0:
		s["reload_t"] = float(s["reload_t"]) - dt
		return
	if int(s["mag"]) <= 0:
		s["reload_t"] = RELOAD_T
		s["mag"] = MAG_SIZE
		return
	if int(s["burst"]) <= 0:
		s["burst"] = randi_range(BURST_MIN, BURST_MAX)
	s["burst"] = int(s["burst"]) - 1
	s["mag"] = int(s["mag"]) - 1
	s["fire_cd"] = FIRE_CD if int(s["burst"]) > 0 else randf_range(BURST_PAUSE_MIN, BURST_PAUSE_MAX)
	# 弹道：from = pos+(0,1.5,0)，朝玩家胸口 + 散布抖动（基础 0.03 + 距离/60×0.05，疾跑 ×1.4）
	var eye: Vector3 = s["pos"] + Vector3(0, EYE_H, 0)
	var aim: Vector3 = _ppos() + Vector3(0, CHEST_Y, 0)
	var dir: Vector3 = (aim - eye).normalized()
	var spread: float = SPREAD_BASE + dist * SPREAD_PER_M
	if _player_sprinting():
		spread *= SPRINT_SPREAD_MUL
	dir = (dir + Vector3(randf() - 0.5, (randf() - 0.5) * 0.5, randf() - 0.5) * spread).normalized()
	# 命中判定：射程内 + 未被墙挡 + 射线与玩家命中球（r=0.5 @ 胸口）相交
	var pc: Vector3 = _ppos() + Vector3(0, CHEST_Y, 0)
	var hit := false
	var end_d: float = ENGAGE_DIST
	var t: float = (pc - eye).dot(dir)
	if t > 0.5 and t < ENGAGE_DIST and (pc - eye - dir * t).length() < HIT_R:
		var wd: float = _world.wall_hit(eye, dir, t - 0.2)
		if wd >= t - 0.2:
			hit = true
			end_d = t
	if not hit:
		var wd2: float = _world.wall_hit(eye, dir, end_d)
		if wd2 < end_d:
			end_d = wd2
	var muzzle: Vector3 = s["pos"] + Basis(Vector3.UP, float(s["yaw"])) \
			* (MUZZLE_LOCAL * SOLDIER_SCALE)
	_tracers.spawn(muzzle, eye + dir * end_d, hit)
	_audio.play_shot("rifle")
	if hit:
		# 伤害 = rifle 20 × 0.55 × 距离衰减（贴脸 1.0 → 70m 0.6）
		var fade: float = 1.0 - 0.4 * clampf(dist / ENGAGE_DIST, 0.0, 1.0)
		player_hit.emit(RIFLE_DMG * AI_DMG_MUL * fade)


# ================= 渲染：士兵模型（骨骼动画 / 胶囊兜底） =================

## 单兵模型槽：GLB 实例化（scale = SOLDIER_SCALE）；材质逐兵 duplicate 上敌军赭红——
## 死亡淡出只影响自己（网页版每兵独立加载 GLB 的材质天然隔离，这里用 duplicate 等价）
func _make_body(scene: PackedScene) -> Dictionary:
	var node: Node3D
	var ap: AnimationPlayer = null
	var mi: MeshInstance3D = null
	if scene != null:
		node = scene.instantiate()
		node.scale = Vector3.ONE * SOLDIER_SCALE
		var apl: Array = node.find_children("*", "AnimationPlayer", true, false)
		if not apl.is_empty():
			ap = apl[0]
		var mil: Array = node.find_children("*", "MeshInstance3D", true, false)
		if not mil.is_empty():
			mi = mil[0]
	else:
		node = Node3D.new()
	if mi == null:
		mi = MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 1.75
		mi.mesh = cap
		mi.position = Vector3(0, 0.875, 0)
		node.add_child(mi)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.visible = false
	add_child(node)
	var mats: Array = []
	if ap != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		var src: Mesh = mi.mesh
		for si in src.get_surface_count():
			var m: Material = src.surface_get_material(si)
			if m is StandardMaterial3D:
				var t: StandardMaterial3D = m.duplicate()
				if t.resource_name == "Uniform":
					t.albedo_color = UNIFORM_COL
					_emissive(t)   # 远景可见性：暖雾里赭红会隐身，微自发光提对比
				elif t.resource_name == "Gear":
					t.albedo_color = GEAR_COL
					_emissive(t)
				mi.set_surface_override_material(si, t)
				mats.append(t)
	if mats.is_empty():
		# 胶囊人替身：整体赭红
		var fb := StandardMaterial3D.new()
		fb.albedo_color = UNIFORM_COL
		_emissive(fb)
		mi.material_override = fb
		mats.append(fb)
	return {"node": node, "ap": ap, "mesh": mi, "mats": mats, "anim": "",
			"fading": false, "faded": false}


## 军装/装具微自发光（UNIFORM_EMISSION）：远景把人形从雾与暗部里提出来；
## emission 跟随 albedo 同色，只加能量不加色相（问题②，宁少勿假）
func _emissive(m: StandardMaterial3D) -> void:
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = UNIFORM_EMISSION


## 同步模型位置朝向 + 按状态切动画：death / 移动交火 walk / 移动 run / 原地交火 aim / idle
func _write_pose(i: int) -> void:
	var s: Dictionary = soldiers[i]
	var b: Dictionary = _bodies[i]
	var node: Node3D = b["node"]
	node.visible = true
	node.position = s["pos"]
	node.rotation = Vector3(0, float(s["yaw"]), 0)
	var want := "idle"
	if s["dead"]:
		want = "death"
	elif s["moving"]:
		want = "walk" if s["engaged"] else "run"
	elif s["engaged"]:
		want = "aim"
	var ap: AnimationPlayer = b["ap"]
	if ap == null:   # 胶囊人替身：阵亡放倒
		node.rotation.x = PI * 0.5 if s["dead"] else 0.0
	elif want != b["anim"]:
		b["anim"] = want
		ap.play(want, 0.18)
		if want == "run":
			ap.speed_scale = PATROL_SPEED / 6.5
		else:
			ap.speed_scale = 1.0


## 死亡表现：倒地 8s 后材质透明渐隐，隐没后不再出现（不重生）
func _tick_deaths(dt: float) -> void:
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if not s["dead"]:
			continue
		s["death_t"] = float(s["death_t"]) + dt
		var b: Dictionary = _bodies[i]
		if bool(b["faded"]) or float(s["death_t"]) < DEATH_HOLD:
			continue
		var k: float = clampf((float(s["death_t"]) - DEATH_HOLD) / FADE_TIME, 0.0, 1.0)
		if k >= 1.0:
			b["faded"] = true
			var node: Node3D = b["node"]
			node.visible = false
			continue
		if not bool(b["fading"]):
			b["fading"] = true
			for m in b["mats"]:
				var sm0: StandardMaterial3D = m
				sm0.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for m in b["mats"]:
			var sm: StandardMaterial3D = m
			sm.albedo_color.a = 1.0 - k


# ================= 玩家/世界鸭子访问 =================

func _ppos() -> Vector3:
	return _player.pos   # 契约保证存在


## 玩家眼位：稳妥起见一律 pos + 1.55（契约建议，不依赖 eye_pos 的存在）
func _peye() -> Vector3:
	return _ppos() + Vector3(0, 1.55, 0)


func _pdist(s: Dictionary) -> float:
	var pp: Vector3 = _ppos()
	return Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length()


## 玩家存活（鸭子字段探测，缺失视为存活）：dead 优先，退回 health
func _player_alive() -> bool:
	var d = _player.get("dead")
	if d != null and bool(d):
		return false
	var h = _player.get("health")
	if h != null and float(h) <= 0.0:
		return false
	return true


## 玩家疾跑：move_speed ≥ 8（onfoot WALK 6 / RUN 11.5 之间），敌弹散布 ×1.4
func _player_sprinting() -> bool:
	var ms = _player.get("move_speed")
	return ms != null and float(ms) >= SPRINT_SPEED


## 视线遮挡：对目标方向的 wall_hit 距离 < 剩余距离 = 被挡（契约约定）
func _blocked(from: Vector3, to: Vector3) -> bool:
	var d := from.distance_to(to)
	if d < 0.5:
		return false
	var wd: float = _world.wall_hit(from, (to - from) / d, d - 0.5)
	return wd < d - 0.5


func _ground_y(x: float, z: float) -> float:
	var v = _world.ground_height(x, z)
	return 0.0 if v == null else float(v)
