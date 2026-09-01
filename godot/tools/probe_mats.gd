extends SceneTree
## 材质分布探针（headless 可用）：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy \
##       -s res://tools/probe_mats.gd
## 列出 FreeroamMap 下所有 mesh 节点用的材质与其顶点/实例数，
## 核对 road/walk/rail/deck 材质各自覆盖的几何。

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fm := FreeroamMap.new()
	root.add_child(fm)
	fm.build()
	var stats := {}
	for ch in fm.get_children():
		var key := ""
		var verts := 0
		if ch is MeshInstance3D and ch.mesh != null:
			var mat: Material = ch.material_override
			if mat == null and ch.mesh.get_surface_count() > 0:
				mat = ch.mesh.surface_get_material(0)
			key = _mat_key(mat)
			for s in ch.mesh.get_surface_count():
				var arr: Array = ch.mesh.surface_get_arrays(s)
				verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		elif ch is MultiMeshInstance3D and ch.multimesh.mesh != null:
			var mat2: Material = ch.multimesh.mesh.surface_get_material(0)
			key = _mat_key(mat2) + " ×%d" % ch.multimesh.instance_count
			var arr2: Array = ch.multimesh.mesh.surface_get_arrays(0)
			verts = (arr2[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if key == "":
			continue
		if not stats.has(key):
			stats[key] = {"nodes": 0, "verts": 0}
		stats[key]["nodes"] += 1
		stats[key]["verts"] += verts
	var keys := stats.keys()
	keys.sort()
	for k in keys:
		print("%-40s 节点 %3d  顶点 %7d" % [k, stats[k]["nodes"], stats[k]["verts"]])
	quit()


func _mat_key(mat: Material) -> String:
	if mat == null:
		return "(无材质)"
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var col = sm.get_shader_parameter("albedo")
		var en = sm.get_shader_parameter("over_en")
		var oy = sm.get_shader_parameter("over_y")
		var use_tex = sm.get_shader_parameter("use_tex")
		return "fade albedo=%s over_en=%s over_y=%s tex=%s" % [
				col, en, oy, use_tex]
	if mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		return "std albedo=%s" % std.albedo_color.to_html()
	return mat.get_class()
