extends SceneTree
## 端到端：编辑器产出的带高度赛道 → 主游戏加载 → 开赛

func _initialize() -> void:
	# 1) 模拟编辑器编译保存（带高度起伏的椭圆）
	var pts := []
	for k in 12:
		var a := TAU * float(k) / 12
		pts.append(Vector3(cos(a) * 190.0, 6.0 + 5.0 * sin(a * 2.0), sin(a) * 130.0))
	var def := {"id": "custom_e2e01", "name": "起伏试驾", "desc": "e2e",
			"theme": "country", "points": pts}
	var v: Dictionary = TrackData.validate_track(def["points"])
	print("[e2e] 校验: ok=%s len=%d" % [v["ok"], int(v["length"])])
	TrackData.save_custom_track(def)

	# 2) 编辑器试驾：设置 pending 后进主场景
	TrackData.pending_track_id = "custom_e2e01"
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	for i in 10:
		await process_frame
	print("[e2e] 赛道总数=%d (内置7+自定义1=8)" % game.tracks.size())
	print("[e2e] 状态=%s (期望直接开赛 COUNTDOWN/RACING)" % game.ST.keys()[game.state])
	var cur: RaceTrack = game.track
	print("[e2e] 当前赛道=%s" % cur.name)
	# 3) 跑 8 秒（跳过倒计时），检查车辆贴坡（y > 0）
	game.count_t = 0.01
	for i in 960:
		await process_frame
	var ai_y := 0.0
	for c in game.cars:
		ai_y = maxf(ai_y, c.veh.pos.y)
	var p: Vehicle = game.player.veh
	print("[e2e] 玩家: vf=%.1f y=%.2f | AI 最高 y=%.2f" % [p.vf, p.pos.y, ai_y])
	print("[e2e] %s" % ["PASS" if ai_y > 0.5 else "FAIL（AI 没上坡）"])
	# 清理
	TrackData.delete_custom_track("custom_e2e01")
	quit(0)
