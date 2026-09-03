extends SceneTree
## 端到端：编辑器存档 → pending_map_id → 主场景进漫游 → 城市真的变了。
## 顺带验证 enter_roam 的缓存失效（换存档必须重建，否则看到旧城）。
##   godot --headless --path . -s res://tests/test_e2e_city.gd

const CityData := preload("res://scripts/city_data.gd")

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[e2e] %s %s %s" % ["✓" if ok else "✗", name, detail])


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var base: Array = CityData.base_buildings()
	var n0 := base.size()
	var victim: String = base[500]["id"]

	# 造一张：删一栋 + 把另一栋拉高到 200
	var tall: String = base[600]["id"]
	var def := CityData.default_def()
	def["id"] = "e2e_city"
	def["name"] = "端到端城市"
	def["dels"] = [victim]
	def["edits"] = [{"id": tall, "f": {"h": 200.0}}]
	check("存档写盘", CityData.save_custom_map(def))

	CityData.pending_map_id = "e2e_city"
	var g: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	for i in 240:
		await process_frame

	check("已进入漫游", g.state == 5, "state=%d" % g.state)
	var fm = g.freeroam
	check("城市已生成", fm != null)
	if fm != null:
		check("楼数少一栋", fm.bld_recs.size() == n0 - 1,
				"%d（底板 %d）" % [fm.bld_recs.size(), n0])
		var found := false
		var h := 0.0
		for r in fm.bld_recs:
			if r["id"] == victim:
				found = true
			if r["id"] == tall:
				h = float(r["h"])
		check("被删的那栋不在了", not found, victim)
		check("被改的那栋高度生效", absf(h - 200.0) < 1e-6, "h=%.1f" % h)
		check("无孤儿补丁", fm.orphans.is_empty(),
				"%d 条" % fm.orphans.size())
		check("存档 id 已记录（换存档才会重建）", g.roam_city_id == "e2e_city",
				g.roam_city_id)

	CityData.delete_custom_map("e2e_city")
	print("[e2e] %s（失败 %d 项）" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
