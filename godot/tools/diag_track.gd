extends SceneTree
## 赛道综合诊断：godot --headless --path . -s res://tools/diag_track.gd
## 检查项：
##   1) 最小转弯半径（< 路宽 7m 时路面内侧会自交打褶 → 视觉「乱」）
##   2) 相邻采样点转角（尖角/折线感）
##   3) 曲率突刺（平滑窗外的原始曲率极大值）
##   4) 起跑线处曲率（应在平直段）
##   5) 路肩弯道区段覆盖率
##   6) 看台/龙门架是否压在路面上

const HALF_W := 7.0

func _init() -> void:
	for def in TrackData.TRACKS:
		_diag(def)
	quit()


func _diag(def: Dictionary) -> void:
	var t := RaceTrack.new()
	t.build(def)
	var n := t.n
	var ds := t.ds

	# --- 1) 转弯半径（用平滑后曲率；curv 是单位切线的转角差近似 → 半径 = ds/|curv|）---
	var min_r := 1e9
	var min_r_i := 0
	for i in n:
		var k := absf(t.curv[i])
		if k > 1e-6:
			var r := ds / k
			if r < min_r:
				min_r = r
				min_r_i = i

	# --- 2) 相邻采样点最大转角（度）---
	var max_turn := 0.0
	var max_turn_i := 0
	for i in n:
		var d := absf(t.ang[(i + 1) % n] - t.ang[i])
		if d > PI:
			d = TAU - d
		if d > max_turn:
			max_turn = d
			max_turn_i = i

	# --- 3) 原始曲率突刺（未平滑）---
	var raw_max := 0.0
	for i in n:
		var a := t.tang[i]
		var b := t.tang[(i + 1) % n]
		raw_max = maxf(raw_max, absf(a.y * b.x - a.x * b.y))

	# --- 4) 起跑线曲率 + 起跑线前后 46m 直道度 ---
	var k_start := absf(t.curv[t.start_idx])
	var behind := 0.0
	var bi := t.start_idx
	while behind < 46.0:
		bi = posmod(bi - 1, n)
		behind += ds
		if absf(t.curv[bi]) > 0.0055:
			break

	# --- 5) 路肩区段覆盖率 ---
	var curb_n := 0
	for i in n:
		if absf(t.curv[i]) > 0.0075:
			curb_n += 1

	# --- 6) 看台落点检查（复刻 _build_stands 的选择逻辑）---
	var tightest := 0
	for i in n:
		if absf(t.curv[i]) > absf(t.curv[tightest]):
			tightest = i
	var idx2 := (tightest + 26) % n
	var dir2 := t.left_v[idx2]
	var p2 := t.pts[idx2] - dir2 * (HALF_W + 10.5)
	var alt := t.pts[idx2] + dir2 * (HALF_W + 10.5)
	var ref := Vector2(0, 30)
	if alt.distance_to(ref) < p2.distance_to(ref):
		p2 = alt
	var stand_d := _dist_to_center(t, p2)

	print("── %s (%s)" % [def["name"], def["id"]])
	print("   长度 %.0fm 采样 %d  间距 %.2fm" % [t.length, n, ds])
	print("   最小转弯半径 %.1fm @%d  %s" % [min_r, min_r_i,
			"⚠️ 小于路宽 7m → 路面自交打褶" if min_r < HALF_W else ""])
	print("   最大相邻转角 %.1f° @%d  %s" % [rad_to_deg(max_turn), max_turn_i,
			"⚠️ 折线感" if rad_to_deg(max_turn) > 8.0 else ""])
	print("   原始曲率突刺 %.5f （平滑阈值 %.5f）" % [raw_max, 0.0075])
	print("   起跑线曲率 %.5f @%d  后方直道 %.0fm" % [k_start, t.start_idx, behind])
	print("   弯道采样占比 %.0f%%" % [100.0 * curb_n / n])
	print("   2 号看台距中心线 %.1fm %s" % [stand_d,
			"⚠️ 压在赛道上" if stand_d < HALF_W + 4.0 else ""])
	print("")


func _dist_to_center(t: RaceTrack, p: Vector2) -> float:
	var best := 1e9
	for i in range(0, t.n, 2):
		best = minf(best, t.pts[i].distance_to(p))
	return best
