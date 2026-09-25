extends SceneTree
## 城市编辑器实拍：加载编辑器场景、可选地模拟一次点选与拖动，出图。
##   RR_PICK="x,y" 在该屏幕坐标点一下  RR_DRAG="dx,dy" 再拖这么多像素
##   godot --path . --audio-driver Dummy -s res://tools/probe_editor.gd
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/out")
	var ed: Node = load("res://scenes/city_editor.tscn").instantiate()
	root.add_child(ed)
	for i in 90:
		await process_frame

	var pick := OS.get_environment("RR_PICK")
	if pick.count(",") == 1:
		var p := pick.split(",")
		var mp := Vector2(p[0].to_float(), p[1].to_float())
		var hit: int = ed._pick(mp)
		print("拾取 (%.0f,%.0f) -> %s" % [mp.x, mp.y,
				("#%d %s" % [hit, ed.recs[hit]["id"]]) if hit >= 0 else "未命中"])
		if hit >= 0:
			ed._on_left_down(mp)
			var drag := OS.get_environment("RR_DRAG")
			if drag.count(",") == 1:
				var d := drag.split(",")
				var ev := InputEventMouseMotion.new()
				ev.position = mp + Vector2(d[0].to_float(), d[1].to_float())
				ev.relative = Vector2(d[0].to_float(), d[1].to_float())
				ed._unhandled_input(ev)
				ed._on_left_up()
				var ax: float = ed.recs[ed.sel]["x"]
				var az: float = ed.recs[ed.sel]["z"]
				print("拖动后 x=%.1f z=%.1f，撤销栈 %d 步" % [ax, az, ed.undo_stack.size()])
				for _f in 3:
					await process_frame
				ed._undo()
				var ux: float = ed.recs[ed.sel]["x"] if ed.sel >= 0 else 0.0
				var uz: float = ed.recs[ed.sel]["z"] if ed.sel >= 0 else 0.0
				print("撤销一次后 x=%.1f z=%.1f，栈 %d 步（应回到拖动前）"
						% [ux, uz, ed.undo_stack.size()])
				for _f2 in 3:
					await process_frame
				ed._redo()
				print("重做后 x=%.1f z=%.1f" % [ed.recs[ed.sel]["x"], ed.recs[ed.sel]["z"]])
				# 再验删除 + 撤销
				for _f3 in 3:
					await process_frame
				var n0: int = ed.recs.size()
				ed._delete_selected()
				var n1: int = ed.recs.size()
				for _f4 in 3:
					await process_frame
				ed._undo()
				print("删除 %d→%d，撤销后 %d（应回到 %d）"
						% [n0, n1, ed.recs.size(), n0])
			for i in 20:
				await process_frame

	# 核对：选中记录的位置上，MultiMesh 里到底有没有对应实例
	if ed.sel >= 0:
		var r: Dictionary = ed.recs[ed.sel]
		print("选中记录 id=%s x=%.1f z=%.1f h=%.1f w=%.1f"
				% [r["id"], r["x"], r["z"], r["h"], r["w"]])
		var mm: MultiMesh = ed.map.bld_mmi.multimesh
		var hit := -1
		var near := 1e9
		for i in mm.instance_count:
			var o: Vector3 = mm.get_instance_transform(i).origin
			var d: float = Vector2(o.x - float(r["x"]), o.z - float(r["z"])).length()
			if d < near:
				near = d
				hit = i
		print("MultiMesh 实例数 %d；离该位置最近的实例 #%d 距离 %.2fm"
				% [mm.instance_count, hit, near])
		print("  该实例 origin=%v scale=%v"
				% [mm.get_instance_transform(hit).origin,
				mm.get_instance_transform(hit).basis.get_scale()])

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/out/shot_editor.png")
	print("楼 %d 栋，已出图" % ed.recs.size())
	quit()
