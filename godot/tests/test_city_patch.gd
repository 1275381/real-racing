extends SceneTree
## 补丁层语义：空补丁 = 底板原样；删/改/增各自只动该动的；
## 找不到宿主的补丁要被报出来而不是静默丢弃；存档 JSON 往返不丢字段。
##   godot --headless --path . -s res://tests/test_city_patch.gd

const CityData := preload("res://scripts/city_data.gd")

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[test] %s %s %s" % ["✓" if ok else "✗", name, detail])


func _init() -> void:
	var base: Array = CityData.base_buildings()
	check("底板可加载", base.size() > 1000, "%d 栋" % base.size())
	if base.is_empty():
		quit(1)
		return

	# ---- 空补丁 = 原样 ----
	var r0: Dictionary = CityData.apply_patches(base, CityData.default_def())
	var same := (r0["recs"] as Array).size() == base.size() and (r0["orphans"] as Array).is_empty()
	for i in base.size():
		var a: Dictionary = base[i]
		var b: Dictionary = r0["recs"][i]
		if a["id"] != b["id"] or absf(a["x"] - b["x"]) > 1e-9 or absf(a["h"] - b["h"]) > 1e-9:
			same = false
			break
	check("空补丁 = 底板原样", same)

	var vid: String = base[100]["id"]
	var vh: float = base[100]["h"]
	var vx: float = base[100]["x"]

	# ---- 删 ----
	var d1 := CityData.default_def()
	d1["dels"] = [vid]
	var r1: Dictionary = CityData.apply_patches(base, d1)
	var gone := true
	for r in r1["recs"]:
		if r["id"] == vid:
			gone = false
	check("删除只少一栋", (r1["recs"] as Array).size() == base.size() - 1 and gone)

	# ---- 改：只动脏字段，其余保持底板值 ----
	var d2 := CityData.default_def()
	d2["edits"] = [{"id": vid, "f": {"h": 999.0}}]
	var r2: Dictionary = CityData.apply_patches(base, d2)
	var hit: Dictionary = {}
	for r in r2["recs"]:
		if r["id"] == vid:
			hit = r
	check("改只动脏字段",
			not hit.is_empty() and absf(hit["h"] - 999.0) < 1e-9
			and absf(hit["x"] - vx) < 1e-9,
			"h=%.1f（底板 %.1f）x 保持=%s" % [hit.get("h", -1), vh,
			absf(hit.get("x", -1e9) - vx) < 1e-9])
	check("改不影响别的楼", (r2["recs"] as Array).size() == base.size())

	# ---- 增 ----
	var d3 := CityData.default_def()
	d3["adds"] = [{"id": "bld/user/1", "f": {"x": 300.0, "z": 300.0, "h": 55.0,
			"w": 20.0, "dep": 20.0}}]
	var r3: Dictionary = CityData.apply_patches(base, d3)
	var added: Dictionary = {}
	for r in r3["recs"]:
		if r["id"] == "bld/user/1":
			added = r
	check("新增一栋", (r3["recs"] as Array).size() == base.size() + 1
			and not added.is_empty() and absf(added["h"] - 55.0) < 1e-9)

	# ---- 孤儿补丁必须报出来 ----
	var d4 := CityData.default_def()
	d4["dels"] = ["bld/blk/ns99/ew99/c0"]
	d4["edits"] = [{"id": "bld/nope", "f": {"h": 1.0}}]
	var r4: Dictionary = CityData.apply_patches(base, d4)
	check("孤儿补丁被报出（不静默丢弃）", (r4["orphans"] as Array).size() == 2
			and (r4["recs"] as Array).size() == base.size(),
			"%d 条" % (r4["orphans"] as Array).size())

	# ---- 存档 JSON 往返：已知键规范化 + 未知键保留 ----
	var def := CityData.default_def()
	def["id"] = "t_patch"
	def["name"] = "往返测试"
	def["edits"] = [{"id": vid, "f": {"h": 88.0, "tint": [0.9, 0.1, 0.2]}}]
	def["dels"] = ["bld/sub/7"]
	def["future_key"] = {"keep": 42}     # 底板升级到 v2 时的未知键
	CityData.save_custom_map(def)
	var back: Dictionary = CityData.map_by_id("t_patch")
	check("存档往返 · 编辑保留", (back["edits"] as Array).size() == 1
			and String(back["edits"][0]["id"]) == vid)
	check("存档往返 · 删除保留", (back["dels"] as Array).size() == 1)
	check("存档往返 · 未知键不丢", back.has("future_key")
			and int(back["future_key"]["keep"]) == 42)

	# 往返后的补丁仍能正确应用（tint 是数组，要能解回 Color）
	var r5: Dictionary = CityData.apply_patches(base, back)
	var h5: Dictionary = {}
	for r in r5["recs"]:
		if r["id"] == vid:
			h5 = r
	check("往返后补丁仍生效", not h5.is_empty() and absf(h5["h"] - 88.0) < 1e-9
			and h5["tint"] is Color and absf(h5["tint"].r - 0.9) < 1e-4)

	CityData.delete_custom_map("t_patch")
	check("删存档", CityData.map_by_id("t_patch")["id"] == CityData.DEFAULT_ID)

	print("[test] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
