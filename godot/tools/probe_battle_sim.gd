## 大战场平衡模拟（无玩家，AI 对 AI）：每 30 秒打印区域/兵力/据点/击杀，最多 20 分钟
##   godot --headless --path . -s res://tools/probe_battle_sim.gd
extends SceneTree
func _initialize() -> void:
	var bmap := BattleMap.new()
	root.add_child(bmap)
	var bf := RRBattleField.new()
	root.add_child(bf)
	bf.setup(bmap, _FakeAudio.new())
	await process_frame
	bf.start("atk")
	var kills := {"atk": 0, "def": 0}
	bf.killed.connect(func(info): kills[str(info.get("killer_team", "?"))] = kills.get(str(info.get("killer_team", "?")), 0) + 1)
	bf.sector_captured.connect(func(si): print("[sim] t=%.0fs 区域 %d 攻陷 tickets=%d" % [bf._t, si + 1, bf.tickets]))
	var t_us := 0
	var n := 0
	var dt := 1.0 / 60.0
	for f in 60 * 60 * 20:
		var t0 := Time.get_ticks_usec()
		bf.update(dt)
		t_us += Time.get_ticks_usec() - t0
		n += 1
		if f % (60 * 30) == 0:
			var s := ""
			if bf.sector < bf.pts.size():
				for pi in 2:
					var p: Dictionary = bf.pts[bf.sector][pi]
					s += " %s:%s %.2f(%d/%d)" % ["AB"[pi], p["owner"], p["prog"], p["atk_n"], p["def_n"]]
			print("[sim] t=%3.0fs 区域=%d 兵力=%d 存活 攻%d/守%d 击杀 攻%d 守%d%s" % [bf._t, bf.sector + 1, bf.tickets,
					bf.count_alive("atk"), bf.count_alive("def"), kills["atk"], kills["def"], s])
		if bf.battle_over:
			print("[sim] 结束 t=%.0fs 进攻方%s" % [bf._t, "胜" if bf.atk_win else "败"])
			break
	print("[sim] 平均 update %.0f us" % [float(t_us) / n])
	quit()

class _FakeAudio:
	extends RefCounted
	func play_police_shot(_d): pass
