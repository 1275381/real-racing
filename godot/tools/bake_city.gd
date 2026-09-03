extends SceneTree
## 城市烘焙：把当前程序化生成的结果冻结成底板 + 基线指纹。
##   godot --headless --path . -s res://tools/bake_city.gd
## 产出 res://data/city_bake_v1.json：
##   · bld      —— 建筑记录表（编辑器的真正底板，逐栋一条）
##   · 其余字段 —— 路网/掩码/禁建区/地形/桥墩/小地图的指纹，供 golden 断言
## 采样点全存要 1.3MB，不划算；用「计数 + 加权校验和 + 首末点」做指纹，
## 任何一处几何改动都会让校验和变化。

const Bake := preload("res://scripts/bake_city_util.gd")
const OUT := "res://data/city_bake_v1.json"


func _init() -> void:
	var m := FreeroamMap.new()
	m.build()

	var roads := []
	for r in m.roads:
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
		roads.append({
			"n": r.pts.size(), "half_w": r.half_w, "closed": r.closed,
			"elev": r.elevated, "mono": r.mono, "wall": r.wall,
			"xsec": r.xsec_cut, "ax": r.along_x,
			"cx": Bake.csum(xs), "cy": Bake.csum(ys), "cz": Bake.csum(zs),
			"rail_skip": rs, "surf_skip": ss,
			"p0": [snappedf(r.pts[0].x, 0.0001), snappedf(r.pts[0].y, 0.0001),
					snappedf(r.pts[0].z, 0.0001)],
			"pN": [snappedf(r.pts[-1].x, 0.0001), snappedf(r.pts[-1].y, 0.0001),
					snappedf(r.pts[-1].z, 0.0001)],
		})

	var blk_keys := m._block.keys()
	blk_keys.sort_custom(func(a, b): return (a.x * 100000 + a.y) < (b.x * 100000 + b.y))
	var blk_c := []
	for k in blk_keys:
		blk_c.append(float(k.x) * 1.0 + float(k.y) * 3.0)

	var ter_keys := m._terr.keys()
	ter_keys.sort_custom(func(a, b): return (a.x * 100000 + a.y) < (b.x * 100000 + b.y))
	var ter_c := []
	for k in ter_keys:
		ter_c.append(float(k.x) * 1.0 + float(k.y) * 3.0 + float(m._terr[k]) * 11.0)

	var pil := []
	for p in m.pillar_pts:
		pil.append(p.x)
		pil.append(p.y)
		pil.append(p.z)

	# 建筑记录表：底板本体
	var recs: Array = m._gen_buildings()
	var bld := []
	for r in recs:
		var e := {"x": snappedf(r["x"], 0.001), "z": snappedf(r["z"], 0.001),
				"w": snappedf(r["w"], 0.001), "dep": snappedf(r["dep"], 0.001),
				"h": snappedf(r["h"], 0.001),
				"t": [snappedf(r["tint"].r, 0.00001), snappedf(r["tint"].g, 0.00001),
						snappedf(r["tint"].b, 0.00001)]}
		if r.has("sb"):
			e["sb"] = [snappedf(r["sb"]["k"], 0.00001), snappedf(r["sb"]["uh"], 0.001)]
		if r.has("rf"):
			var f: Dictionary = r["rf"]
			e["rf"] = [snappedf(f["mw"], 0.001), snappedf(f["md"], 0.001),
					snappedf(f["mh"], 0.001), snappedf(f["ox"], 0.001),
					snappedf(f["oz"], 0.001)]
		if r.has("ant"):
			e["ant"] = snappedf(r["ant"], 0.001)
		bld.append(e)

	var inst: Dictionary = m._building_instances(recs)
	# PackedByteArray 没有 md5_text；走 base64（C++ 侧，比 GDScript 逐字节快得多）。
	# headless 的 dummy 渲染器可能不保留 ImageTexture 的图像，取不到就留空并提示。
	var mini := ""
	if m.minimap_tex != null:
		var img := m.minimap_tex.get_image()
		if img != null:
			mini = Marshalls.raw_to_base64(img.get_data()).md5_text()
	if mini == "":
		print("[bake] ⚠ headless 取不到小地图图像，本次不含小地图指纹")

	var doc := {
		"v": 1, "seed": 20260830,
		"n": m.n, "roads": roads,
		"blk_n": blk_keys.size(), "blk_c": Bake.csum(blk_c),
		"ter_n": ter_keys.size(), "ter_c": Bake.csum(ter_c),
		"pillar_n": m.pillar_pts.size(), "pillar_c": Bake.csum(pil),
		"bld": bld,
		"bld_boxes": (inst["xfs"] as Array).size(),
		"bld_ants": (inst["ants"] as Array).size(),
		"minimap_md5": mini,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	print("[bake] 路 %d 条 / 采样 %d / 楼 %d 栋 → %d 体块 + %d 天线 / 桥墩 %d"
			% [roads.size(), m.n, bld.size(), doc["bld_boxes"], doc["bld_ants"],
			doc["pillar_n"]])
	print("[bake] 已写出 %s" % OUT)
	quit()
