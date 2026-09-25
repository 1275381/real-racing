extends SceneTree
## 城市基线冻结：断言当前生成结果与 res://data/city_bake_v1.json 逐项一致。
##   godot --headless --path . -s res://tests/test_city_golden.gd
## 这是后续所有改造的「许可证」——每一期改完都必须全绿，否则就是漂移了。
## 浮点用 1e-6 容差：烘焙经过 JSON 文本往返，会有 ~1e-10 的表示噪声，
## 而 1e-6（微米级）远小于任何有意义的几何改动。

const Bake := preload("res://scripts/bake_city_util.gd")
const BAKE := "res://data/city_bake_v1.json"
const EPS := 1e-6

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[test] %s %s %s" % ["✓" if ok else "✗", name, detail])


func near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


## 烘焙时对建筑字段做过 snappedf（压体积，毫米级），比对前按同样精度量化，
## 这样断言仍是精确的而不是"放宽的"
func nearq(a: float, b, q: float) -> bool:
	return absf(snappedf(a, q) - float(b)) <= EPS


func _init() -> void:
	var g = JSON.parse_string(FileAccess.get_file_as_string(BAKE))
	if g == null:
		print("[test] ✗ 读不到烘焙底板 %s（先跑 tools/bake_city.gd）" % BAKE)
		quit(1)
		return

	var m := FreeroamMap.new()
	m.build()

	check("采样总数", m.n == int(g["n"]), "n=%d" % m.n)
	check("道路条数", m.roads.size() == (g["roads"] as Array).size(),
			"%d 条" % m.roads.size())

	# ---- 逐条道路：几何指纹 + 全部派生标志 + 两张裁剪掩码 ----
	var road_bad := 0
	var first_bad := ""
	for i in mini(m.roads.size(), (g["roads"] as Array).size()):
		var r: FreeroamMap.Road = m.roads[i]
		var e: Dictionary = g["roads"][i]
		var xs := []
		var ys := []
		var zs := []
		for p in r.pts:
			xs.append(p.x)
			ys.append(p.y)
			zs.append(p.z)
		var rs := 0
		for b in r.rail_skip:
			if b:
				rs += 1
		var ss := 0
		for b in r.surf_skip:
			if b:
				ss += 1
		var ok: bool = (r.pts.size() == int(e["n"])
				and near(r.half_w, e["half_w"]) and r.closed == e["closed"]
				and r.elevated == e["elev"] and r.mono == e["mono"]
				and near(r.wall, e["wall"]) and r.xsec_cut == e["xsec"]
				and r.along_x == e["ax"]
				and near(Bake.csum(xs), e["cx"])
				and near(Bake.csum(ys), e["cy"])
				and near(Bake.csum(zs), e["cz"])
				and rs == int(e["rail_skip"]) and ss == int(e["surf_skip"]))
		if not ok:
			road_bad += 1
			if first_bad == "":
				first_bad = "road%d" % i
	check("道路几何/标志/裁剪掩码", road_bad == 0,
			"不符 %d 条 %s" % [road_bad, first_bad])

	# ---- 禁建区 / 地形高程场 ----
	check("禁建区格数", m._block.size() == int(g["blk_n"]), "%d 格" % m._block.size())
	check("地形高程格数", m._terr.size() == int(g["ter_n"]), "%d 格" % m._terr.size())

	# ---- 桥墩 ----
	var pil := []
	for p in m.pillar_pts:
		pil.append(p.x)
		pil.append(p.y)
		pil.append(p.z)
	check("桥墩数量", m.pillar_pts.size() == int(g["pillar_n"]),
			"%d 根" % m.pillar_pts.size())
	check("桥墩位置校验和", near(Bake.csum(pil), g["pillar_c"]))

	# ---- 建筑：逐栋逐字段（这是编辑器底板本体，必须精确）----
	var recs: Array = m._gen_buildings()
	var gb: Array = g["bld"]
	check("建筑栋数", recs.size() == gb.size(), "%d 栋" % recs.size())
	var bad := 0
	var bad_at := -1
	for i in mini(recs.size(), gb.size()):
		var r: Dictionary = recs[i]
		var e: Dictionary = gb[i]
		var ok: bool = (String(r["id"]) == String(e["id"])
				and nearq(r["x"], e["x"], 0.001) and nearq(r["z"], e["z"], 0.001)
				and nearq(r["w"], e["w"], 0.001) and nearq(r["dep"], e["dep"], 0.001)
				and nearq(r["h"], e["h"], 0.001)
				and nearq(r["tint"].r, e["t"][0], 0.00001)
				and nearq(r["tint"].g, e["t"][1], 0.00001)
				and nearq(r["tint"].b, e["t"][2], 0.00001)
				and r.has("sb") == e.has("sb") and r.has("rf") == e.has("rf")
				and r.has("ant") == e.has("ant"))
		if ok and r.has("sb"):
			ok = (nearq(r["sb"]["k"], e["sb"][0], 0.00001)
					and nearq(r["sb"]["uh"], e["sb"][1], 0.001))
		if ok and r.has("rf"):
			var f: Dictionary = r["rf"]
			ok = (nearq(f["mw"], e["rf"][0], 0.001) and nearq(f["md"], e["rf"][1], 0.001)
					and nearq(f["mh"], e["rf"][2], 0.001)
					and nearq(f["ox"], e["rf"][3], 0.001)
					and nearq(f["oz"], e["rf"][4], 0.001))
		if ok and r.has("ant"):
			ok = nearq(r["ant"], e["ant"], 0.001)
		if not ok:
			bad += 1
			if bad_at < 0:
				bad_at = i
	check("建筑逐栋逐字段（含稳定 id）", bad == 0,
			"不符 %d 栋，首个 #%d" % [bad, bad_at])
	var ids := {}
	var dup := 0
	for r in recs:
		if ids.has(r["id"]):
			dup += 1
		ids[r["id"]] = true
	check("建筑 id 唯一", dup == 0, "重复 %d 个" % dup)

	# ---- 建筑记录 → 实例的展开 ----
	var inst: Dictionary = m._building_instances(recs)
	check("展开体块数", (inst["xfs"] as Array).size() == int(g["bld_boxes"]),
			"%d 个" % (inst["xfs"] as Array).size())
	check("展开天线数", (inst["ants"] as Array).size() == int(g["bld_ants"]),
			"%d 根" % (inst["ants"] as Array).size())

	# ---- 小地图（3D 分区与小地图分区必须同源，历史上出过不同步的 bug）----
	var mini_md5 := ""
	if m.minimap_tex != null:
		var img := m.minimap_tex.get_image()
		if img != null:
			mini_md5 = Marshalls.raw_to_base64(img.get_data()).md5_text()
	if String(g["minimap_md5"]) == "" or mini_md5 == "":
		print("[test] - 小地图指纹跳过（headless 取不到图像）")
	else:
		check("小地图图像指纹", mini_md5 == String(g["minimap_md5"]))

	print("[test] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
