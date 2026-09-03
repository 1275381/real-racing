extends SceneTree
## 分区表合一的验收：
##   1. zone_at() 必须与合并前那段 if-else 在大量随机点上逐点一致
##   2. 小地图上的分区底色必须与 3D 分区同源（历史上这两处不同步过）
##   godot --headless --path . -s res://tests/test_city_zone.gd

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[test] %s %s %s" % ["✓" if ok else "✗", name, detail])


## 合并前的原始判定，逐字保留作为预言机
func legacy_id(x: float, z: float) -> String:
	if x < -1080.0:
		return "sea"
	elif x < -980.0:
		return "beach"
	elif x > 950.0:
		return "desert"
	elif z < -1080.0:
		return "mount"
	elif absf(x) < 950.0 and absf(z) < 950.0:
		return "city"
	return "grass"


func _init() -> void:
	var m := FreeroamMap.new()
	m.build()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260904

	# ---- 1. zone_at 对比原始 if-else ----
	var bad := 0
	var first := ""
	for i in 4000:
		var x := rng.randf_range(-2800.0, 2800.0)
		var z := rng.randf_range(-2800.0, 2800.0)
		var got: String = m.zone_at(x, z)["id"]
		var want := legacy_id(x, z)
		if got != want:
			bad += 1
			if first == "":
				first = "(%.0f,%.0f) 得 %s 期望 %s" % [x, z, got, want]
	check("zone_at 与合并前判定一致（4000 点）", bad == 0,
			"不符 %d 点 %s" % [bad, first])

	# ---- 2. 边界值：分区阈值上必须精确落在正确一侧 ----
	var edges := [[-1080.1, 0.0, "sea"], [-1079.9, 0.0, "beach"],
			[-980.1, 0.0, "beach"], [-979.9, 0.0, "grass"],
			[950.1, 0.0, "desert"], [949.9, 0.0, "city"],
			[0.0, -1080.1, "mount"], [0.0, -1079.9, "grass"],
			[949.9, 949.9, "city"], [950.1, 949.9, "desert"]]
	var ebad := 0
	for e in edges:
		if m.zone_at(e[0], e[1])["id"] != e[2]:
			ebad += 1
			print("    ✗ 边界 (%.1f,%.1f) 得 %s 期望 %s"
					% [e[0], e[1], m.zone_at(e[0], e[1])["id"], e[2]])
	check("分区阈值边界（10 个临界点）", ebad == 0)

	# ---- 3. 小地图底色与 3D 分区同源 ----
	var img: Image = null
	if m.minimap_tex != null:
		img = m.minimap_tex.get_image()
	if img == null:
		print("[test] - 小地图比对跳过（headless 取不到图像）")
	else:
		var size := img.get_width()
		var scale := float(size) / (FreeroamMap.MAP_LIMIT * 2.0)
		var mbad := 0
		var mfirst := ""
		var tried := 0
		for i in 20000:
			if tried >= 1500:
				break
			var x := rng.randf_range(-2700.0, 2700.0)
			var z := rng.randf_range(-2700.0, 2700.0)
			# 避开路网：小地图上路会盖住分区底色
			if not m.is_clear_of_roads(x, z, 60.0):
				continue
			tried += 1
			# 小地图 600px 覆盖 5600m ≈ 9.3m/像素：离分区边界不足一个像素的点
			# 会落进另一侧的像素，那是量化而非不同步，排除掉
			var near_edge := false
			for zn in FreeroamMap.ZONES:
				var r = zn["rect"]
				if r == null:
					continue
				for v in [r[0], r[1]]:
					if absf(x - float(v)) < 12.0:
						near_edge = true
				for v2 in [r[2], r[3]]:
					if absf(z - float(v2)) < 12.0:
						near_edge = true
			if near_edge:
				tried -= 1
				continue
			var px := clampi(int((x + FreeroamMap.MAP_LIMIT) * scale), 0, size - 1)
			var pz := clampi(int((z + FreeroamMap.MAP_LIMIT) * scale), 0, size - 1)
			var got := img.get_pixel(px, pz)
			var want: Color = m.zone_at(x, z)["mini"]
			if absf(got.r - want.r) > 0.01 or absf(got.g - want.g) > 0.01 \
					or absf(got.b - want.b) > 0.01:
				mbad += 1
				if mfirst == "":
					mfirst = "(%.0f,%.0f) %s 图上 %.2f/%.2f/%.2f 期望 %.2f/%.2f/%.2f" % [
							x, z, m.zone_at(x, z)["id"], got.r, got.g, got.b,
							want.r, want.g, want.b]
		check("小地图分区与 3D 同源（%d 个避开路网的点）" % tried, mbad == 0,
				"不符 %d 点 %s" % [mbad, mfirst])

	print("[test] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
