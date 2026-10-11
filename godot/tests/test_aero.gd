# 回归：aiaero「风刃」——程序化空力套件 + 主动尾翼状态机 + downforce 物理钩子
# 断言用可整除步长 dt=0.005：22 步=0.11s 恰走展开半程、24 步=0.12s 恰走
# 气动刹车全程（move_toward 线性插值，60Hz 下 0.11s 不可整除会必挂）
extends SceneTree

const DT := 0.005

var game
var ok_all := true


func frames(n: int) -> void:
	for i in n:
		await process_frame


func check(cond: bool, label: String) -> void:
	print("[aero] %s ... %s" % [label, "OK" if cond else "FAIL"])
	if not cond:
		ok_all = false


func wing_rise(vis: CarVisual) -> float:
	return vis.wing_pivot.position.y - vis._wing_rest_y


func wing_aoa(vis: CarVisual) -> float:
	return vis.wing_blade.rotation.x - vis._wing_rest_rx


## 无限平直路桩：柏油、零坡、无墙——让极速收敛只由动力-风阻平衡决定
class StubTrack:
	extends RefCounted
	var n := 4
	var start_idx := 0
	var closed := true
	var wall_lat := 1.0e9   # q.get 的默认值表达式会被急切求值，必须存在

	func query(_x: float, _z: float, _hint, _vy: float = -1.0e9) -> Dictionary:
		return {"idx": 0, "lat_off": 0.0, "ang": 0.0, "surf": "road",
				"height": 0.0, "slope": 0.0, "wall": 1.0e9}


func _initialize() -> void:
	OS.set_environment("RR_SETTINGS_PATH", "user://rr_settings_probe_aero.cfg")
	# 清残留：上一个探针留下的存档不该决定本次结果
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"user://rr_settings_probe_aero.cfg"))
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(10)
	# 开机即自动 enter_roam（车库展台就是初始页，game.gd _ready 的
	# enter_roam.call_deferred）：先退回车库再测，否则后续显式 enter_roam
	# 会因 state 已是 ROAM 提前返回、ROAM_SPAWN 不生效
	game.exit_roam()
	await frames(10)

	# ---- ⑥ 之一：CAR_MODELS 零影响 + aiaero 条目必填字段 ----
	var aiaero: Dictionary = TrackData.model_by_id("aiaero")
	check(aiaero["id"] == "aiaero", "条目存在（model_by_id 未回退 CAR_MODELS[0]）")
	check(aiaero.has("desc") and aiaero.has("price") and aiaero["price"] == 12000,
			"desc/price 字段齐全（车库两处文案直键访问 desc）")
	check(String(aiaero["desc"]).contains("收藏价 12000 金币"), "售价文案并入 desc")
	for m in TrackData.CAR_MODELS:
		if m["id"] == "aiaero":
			continue
		check(not m.get("stats", {}).has("downforce") and not m.has("aero")
				and not m.has("downforce"), "旧车 %s 无 downforce/aero 键" % m["id"])

	# ---- ① 切到 aiaero：套件节点与物理钩子 ----
	game.set_car_model("aiaero")
	var vis: CarVisual = game.player.visual
	check(vis.find_child("WingPivot", true, false) != null, "WingPivot 节点可寻址")
	check(vis.find_child("WingBlade", true, false) != null, "WingBlade 节点可寻址")
	check(vis.wing_pivot != null and vis.wing_blade != null, "wing 缓存成员非空")
	check(absf(game.player.veh.downforce - 0.14) < 1e-6, "物理实例 downforce=0.14")
	var spl: MeshInstance3D = vis.find_child("AeroSplitter", true, false)
	var mat: BaseMaterial3D = spl.get_active_material(0)
	check(not mat.clearcoat_enabled and absf(mat.roughness - 0.55) < 0.01,
			"碳黑件保持哑光（clearcoat 关 / roughness 0.55）")

	# ---- ② 静止 + 低速（<80km/h）：尾翼贴平收敛 ----
	vis.animate(1.0 / 60.0, 0.0, 0.0, false)
	for i in 30:
		vis.animate(1.0 / 60.0, 60.0 / 3.6, 0.0, false)
	check(wing_rise(vis) < 0.005, "低速支柱升幅 <5mm（实测 %.4fm）" % wing_rise(vis))
	check(wing_aoa(vis) < deg_to_rad(3.0),
			"低速迎角 <3°（实测 %.2f°）" % rad_to_deg(wing_aoa(vis)))

	# ---- ④ 确定性单元断言（直接驱动 vis.animate）----
	for i in 22:   # 0.11s = 展开全程 0.22s 的恰好半程
		vis.animate(DT, 200.0 / 3.6, 0.0, false)
	check(absf(vis._wing_t - 0.5) < 0.02,
			"0.11s 恰走半程 _wing_t=0.5（实测 %.4f）" % vis._wing_t)
	for i in 22:   # 再 0.11s 全展开
		vis.animate(DT, 200.0 / 3.6, 0.0, false)
	check(absf(vis._wing_t - 1.0) < 0.001, "0.22s 全展开 _wing_t=1.0")
	check(absf(wing_rise(vis) - 0.13) < 0.001, "全展开升幅 13cm（实测 %.3fm）" % wing_rise(vis))
	check(absf(rad_to_deg(wing_aoa(vis)) - 32.1) < 1.5,
			"全展开迎角 ≈32°（实测 %.1f°）" % rad_to_deg(wing_aoa(vis)))
	# 急刹空气制动：100km/h > brake_kmh 60，0.12s 恰走全程
	for i in 24:
		vis.animate(DT, 100.0 / 3.6, 0.0, true)
	check(absf(vis._wing_ab - 1.0) < 0.001, "0.12s 气动刹车 _wing_ab=1.0")
	var ab_contrib: float = vis.wing_blade.rotation.x - vis._wing_rest_rx \
			- vis._wing_t * 0.56
	check(absf(ab_contrib - 0.50) < 0.01,
			"气动刹车迎角增量 ≈29°（实测 %.1f°）" % rad_to_deg(ab_contrib))
	# 低速（<wing_kmh 且 <brake_kmh）急刹不抬也不立翼
	vis._wing_t = 0.0
	vis._wing_ab = 0.0
	for i in 24:
		vis.animate(DT, 30.0 / 3.6, 0.0, true)
	check(vis._wing_ab == 0.0, "30km/h 急刹不触发气动刹车")
	for i in 50:   # 0.25s：展开(0.22s)与气动刹车(0.12s)都收敛完
		vis.animate(DT, 30.0 / 3.6, 0.0, false)
	check(vis._wing_t == 0.0 and vis._wing_ab == 0.0
			and absf(wing_rise(vis)) < 0.0005 and absf(wing_aoa(vis)) < 0.0005,
			"0.25s 回收敛位（升幅/迎角归零）")

	# ---- ⑤ 物理：downforce 只加抓地、不动极速 ----
	# 无限平直路桩（无墙无弯）：真实赛道 300s 会蹭墙卡停，证不了极速收敛
	var trk := StubTrack.new()
	var pose := {"pos": Vector3.ZERO, "heading": 0.0}
	var base := {
		"is_player": true, "top_speed": 102.0, "power": 67.0,
		"grip_scale": 1.04, "brake": 19.5, "accel_cap": 13.2,
	}
	var va := Vehicle.new(trk, base)
	var vb_opts: Dictionary = base.duplicate()
	vb_opts["downforce"] = 0.14
	var vb := Vehicle.new(trk, vb_opts)
	check(va.downforce == 0.0 and absf(vb.downforce - 0.14) < 1e-6, "_init 读入 downforce")
	va.apply_stats({"downforce": 0.14})   # 配件热应用走 apply_stats，键必须保留
	check(absf(va.downforce - 0.14) < 1e-6, "apply_stats 保留 downforce 键")
	va.apply_stats({"downforce": 0.0})
	check(va.drag_k2 == vb.drag_k2, "drag_k2 相同 %.8f（极速不受影响）" % va.drag_k2)
	va.place_at(pose)
	vb.place_at(pose)
	va.input_throttle = 1.0
	vb.input_throttle = 1.0
	for i in 60:   # 起步 1s 全油门
		va.step(1.0 / 60.0)
		vb.step(1.0 / 60.0)
	var d1 := absf(va.vf - vb.vf)
	check(d1 < 0.05, "起步 1s |Δvf|=%.4f < 0.05（不可用相等断言）" % d1)
	for i in 17940:   # 续满 300s：极速平衡处收敛
		va.step(1.0 / 60.0)
		vb.step(1.0 / 60.0)
	var d300 := absf(va.vf - vb.vf)
	check(d300 < 0.01, "300s |Δvf|=%.5f < 0.01（va=%.4f vb=%.4f m/s）" % [d300, va.vf, vb.vf])
	check(va.vf > 90.0 and vb.vf > 90.0,
			"双车均到动力-风阻平衡极速（va=%.4f vb=%.4f）" % [va.vf, vb.vf])

	# ---- ③ 集成链路：漫游真开 12s，尾翼随真车速升起 ----
	# set_car_model 已在车库态完成（开场即退出过漫游）——漫游中切车会把重建的
	# Vehicle 绑回赛道 track（set_car_model 不重绑 freeroam），物理查询就错网了
	OS.set_environment("ROAM_SPAWN", "0,20,0")   # 直接出生在 x=0 南北向街道上
	game.npc_solid = false   # 排除 NPC 随机碰撞的偶然减速
	game.enter_roam()
	await frames(30)
	check(game.state == 5, "漫游状态（state=5 ROAM）")
	var ew := InputEventKey.new()
	ew.physical_keycode = KEY_W
	ew.pressed = true
	Input.parse_input_event(ew)
	Input.flush_buffered_events()
	# 纯紧循环（阈值断言禁混 process_frame）；尾翼状态在最快时刻采样——
	# 展开有 0.22s 滞后，速度爬升段即可取到全展开
	var best_kmh := 0.0
	var best_rise := 0.0
	var best_aoa := 0.0
	for i in 12 * 60:
		game._now_s += 1.0 / 60.0
		game._step_sim(1.0 / 60.0)
		game._sync_visual(game.player, 1.0 / 60.0)   # 视觉同步在渲染帧才跑，手动补
		var k_now: float = absf(game.player.veh.vf) * 3.6
		if k_now > best_kmh:
			best_kmh = k_now
			best_rise = wing_rise(vis)
			best_aoa = rad_to_deg(wing_aoa(vis))
	check(best_kmh > 90.0, "12s 全油门 kmh=%.1f > 90" % best_kmh)
	check(best_rise > 0.08, "支柱升幅 >8cm（实测 %.3fm）" % best_rise)
	check(best_aoa > 10.0, "迎角 >10°（实测 %.1f°）" % best_aoa)
	var er := InputEventKey.new()
	er.physical_keycode = KEY_W
	er.pressed = false
	Input.parse_input_event(er)
	Input.flush_buffered_events()
	game.exit_roam()
	await frames(10)

	# ---- ⑥ 之二：切回 gt3 尾翼节点与 downforce 全清 ----
	game.set_car_model("gt3")
	var vis_gt3: CarVisual = game.player.visual
	check(vis_gt3.find_child("WingPivot", true, false) == null
			and vis_gt3.find_child("WingBlade", true, false) == null,
			"gt3 视觉无 WingPivot/WingBlade")
	check(vis_gt3.wing_pivot == null and vis_gt3.wing_blade == null, "gt3 wing 缓存为空")
	check(game.player.veh.downforce == 0.0, "gt3 downforce=0（零影响）")
	for i in 10:   # 旧车 animate 整段跳过不炸
		vis_gt3.animate(1.0 / 60.0, 200.0 / 3.6, 0.0, true)

	print("[aero] %s" % ("PASS" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)
