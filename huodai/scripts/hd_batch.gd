extends RefCounted
## 烽火地带 —— 静态陈设合批（2026-10 改进方案第 8 节「同网格同材质合并，目标出生点
## 绘制调用低于 800」）。
## 病因：大坝/坝底/四新区由上千个代码方块拼成，_mesh_cache 按「材质 × 尺寸」各一张
## BoxMesh——同材质不同尺寸就是不同网格，渲染器的自动实例化合不到一起，每个
## 「网格 × 材质」组合在主绘制 + 深度预通道 + 两段阴影里各占一次绘制调用。
## 做法：world.build() 末尾把静态子树里的叶子 MeshInstance3D 按
## 「材质 × 投影开关 × 渲染层 × 48 m 地块」分组，几何烘焙进一张合并网格（SurfaceTool
## append_from 带变换），原节点删除——一组只剩一次绘制；按地块切开保住视锥剔除。
## 不碰：带脚本/有子节点/有蒙皮/半透明混合/逐实例可视距离或覆盖层的网格、
## 顶点数过大的模型（自己就是一次绘制，合并还丢自动 LOD），以及自身或祖先带
## no_batch 元数据的节点（撤离信标/电闸这类局内会改的件）。
## 无 class_name（新脚本一律 preload）

const CELL := 4096.0
const MAX_VERTS := 4000
const BLDG_VERTS := 16000
const FLAT_H := 0.35

## 合批 root 子树；返回 {"merged": 被合并节点数, "meshes": 生成的合并网格数}
static func run(root: Node3D) -> Dictionary:
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	var groups := {}
	var victims: Array = []
	var all_mi: Array = root.find_children("*", "MeshInstance3D", true, false)
	# 网格被几个节点共用：多实例的大模型（沙袋/卡车/石块）渲染器本来就自动实例化，
	# 不拆；只有一份的多材质建筑才值得按材质拆进合并网格
	var uses := {}
	for n in all_mi:
		var m0 := (n as MeshInstance3D).mesh
		if m0 != null:
			uses[m0.get_instance_id()] = int(uses.get(m0.get_instance_id(), 0)) + 1
	for n in all_mi:
		var mi := n as MeshInstance3D
		if not _eligible(mi, root, int(uses.get(mi.mesh.get_instance_id() if mi.mesh else 0, 0))):
			continue
		var xf: Transform3D = (inv * mi.global_transform) if root.is_inside_tree() else _rel_xform(mi, root)
		var parts: Array = []
		var ok := true
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			if mat == null or _is_blend(mat):
				ok = false
				break
			parts.append([si, mat])
		if not ok:
			continue
		var c := xf.origin
		var cell := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
		if mi.mesh is ArrayMesh:
			cell = Vector2i(9999, 9999)   # 多材质建筑：全图按材质合一张（顶点总量小，剔除粒度无所谓）
		# 贴地薄件（铺装/路缘/车辙/标线，高 < FLAT_H）的影子看不见：并进不投影组，
		# 省掉两段阴影贴图里的绘制
		var shadow := mi.cast_shadow
		if (xf * mi.mesh.get_aabb()).size.y < FLAT_H:
			shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for p in parts:
			var mat2: Material = p[1]
			var key := "%d|%d|%d|%d,%d" % [mat2.get_instance_id(), int(shadow), mi.layers,
					cell.x, cell.y]
			if not groups.has(key):
				groups[key] = {"mat": mat2, "shadow": shadow, "layers": mi.layers, "items": []}
			(groups[key]["items"] as Array).append([mi.mesh, int(p[0]), xf])
		victims.append(mi)
	var made := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var st := SurfaceTool.new()
		for it in g["items"]:
			st.append_from(it[0], int(it[1]), it[2])
		var am: ArrayMesh = st.commit()
		if am == null or am.get_surface_count() == 0:
			continue
		am.surface_set_material(0, g["mat"])
		var out := MeshInstance3D.new()
		out.name = "batch_%d" % made
		out.mesh = am
		out.cast_shadow = g["shadow"]
		out.layers = g["layers"]
		root.add_child(out)
		made += 1
	for mi in victims:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	return {"merged": victims.size(), "meshes": made}


static func _eligible(mi: MeshInstance3D, root: Node3D, uses: int = 1) -> bool:
	if mi.mesh == null or not mi.visible or mi.get_script() != null:
		return false
	if mi.get_child_count() > 0 or mi.skin != null:
		return false
	if mi.material_overlay != null or mi.transparency > 0.0 or mi.visibility_range_end > 0.0:
		return false
	if mi.mesh is ArrayMesh:
		var am := mi.mesh as ArrayMesh
		if am.get_blend_shape_count() > 0:
			return false
		var nv := 0
		for si in am.get_surface_count():
			nv += am.surface_get_array_len(si)
		if nv > MAX_VERTS:
			# 大模型：只拆「独一份 + 多材质」的建筑（≤ BLDG_VERTS）
			if uses > 1 or am.get_surface_count() < 3 or nv > BLDG_VERTS:
				return false
	elif not (mi.mesh is PrimitiveMesh):
		return false
	var p: Node = mi
	while p != null:
		if p.has_meta("no_batch"):
			return false
		if p is Node3D and not (p as Node3D).visible:
			return false
		if p == root:
			break
		p = p.get_parent()
	return true


static func _is_blend(mat: Material) -> bool:
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		return bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				or bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	return mat is ShaderMaterial   # 自定义着色器（可能依赖模型空间/顶点色）不动


static func _rel_xform(mi: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
