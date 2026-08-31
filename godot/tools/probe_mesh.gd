extends SceneTree
## 赛道网格探针：检查每个 MeshInstance3D 的表面/顶点/AABB

func _init() -> void:
	var def: Dictionary = TrackData.TRACKS[0]
	var t := RaceTrack.new()
	t.build(def)
	for child in t.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mesh := mi.mesh
			if mesh == null:
				print("%s: <null mesh>" % mi.name)
				continue
			var vcount := 0
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				vcount += verts.size()
			var aabb := mi.get_aabb()
			print("%s (%s): surfaces=%d verts=%d aabb_pos=%s aabb_size=%s visible=%s" % [
				mi.name, mesh.get_class(), mesh.get_surface_count(), vcount,
				aabb.position, aabb.size, mi.visible])
	quit()
