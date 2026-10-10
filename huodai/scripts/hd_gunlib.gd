class_name HDGunLib
extends RefCounted
## 高顶点枪械建模工具库：把 BoxMesh 直角方块枪升级成圆弧精细枪的公用几何件厂。
## 消费端（hd_guns.gd 枪匠段 / test_huodai.gd）一律 preload 路径引用本文件、
## 不走裸全局名（新文件 + class_name 全局名曾两次挂回归门槛——见 hd_guns.gd
## 枪匠段头注释）；材质全部由调用方传参注入（本库零材质工厂，沿用 hd_guns
## 的 _smg_mats / _build_gun_visual 材质段，不复制不 import）。
##
## 顶点量级速查（公式口径；运行时以 count_vertices 实测为准）：
##   chamfer_box = 6·seg²+2（SurfaceTool.index() 同属性顶点去重后）
##   CylinderMesh = (rings+2)·(seg+1) + 盖数×(seg+2)【已对 Godot 源码验证：
##     primitive_meshes.cpp CylinderMesh::create_mesh_array = 侧壁 (rings+2)
##     行×(seg+1) 列 + 每盖 (seg+1) 环圈 + 1 盖心】。rings 显式置 1：双盖
##     5·seg+7 / 单盖 4·seg+5 / 无盖 3·(seg+1)；rings 缺省=4（官方类文档）：
##     双盖 8·seg+10（seg=10 → 90 顶/柱，低模 _smg_rig 柱的真顶点）
##   TorusMesh = (rings+1)·(ring_seg+1)（源码 num_points 直证，36×18 → 703）
##   组合件：grip ≈ 378 / barrel(3 螺纹) ≈ 2296 / tube(4 槽) ≈ 1522 /
##   curved_mag(3 段) = 224

## 每枪最低顶点门槛 = 8 × POLY_BASE（低模基线）——逐把高模改造完入表，
## test_huodai.gd 构枪后用 count_vertices 实测断言
## （mk4=11040 / m4a1=10128 / akm=6552 / scarh=7200 /
##   mp5=6384 / p90=4440 / uzi=4056 / vector=5520 /
##   pistol=768 / smg=3336 / rifle=7584 / shotgun=1488 / sniper=3168 旧五枪）
const POLY_MIN := {"mk4": 11040, "m4a1": 10128, "akm": 6552, "scarh": 7200,
		"mp5": 6384, "p90": 4440, "uzi": 4056, "vector": 5520,
		"pistol": 768, "smg": 3336, "rifle": 7584, "shotgun": 1488,
		"sniper": 3168}

## 低模基线：改造前（git HEAD）机械清点，口径全表统一 = 盒×24 + 柱×57
## （CylinderMesh radial_segments=10、rings=1 双盖；_add_grip 内部自建 1 盒
## 挂枪根，运行时 count_vertices 会数到它，必须入基线；for 循环体逐语句
## 展开——循环体内每行 add_* 都要乘次数）：
##   mk4 = 48 盒（直排 27 + 循环展开 20 = 楔齿×9 + 侧槽 4×2 + 底槽×3 +
##     _add_grip 1，评审逐行确权）+ 4 柱（缓冲管/枪管/消焰器/前挡环）= 1380
##   m4a1 = 29 盒（直排 23 + 楔齿循环 5 + _add_grip 1）+ 10 柱（缓冲管/护木/
##     散热环×3/delta 环/枪管/消焰器/前环/助推器钮）= 29×24+10×57 = 1266
##   akm = 27 盒（直排 20 + 铆钉循环 3×2 + _add_grip 1）+ 3 柱（枪管/导气管/
##     制退器筒）= 27×24+3×57 = 819
##   scarh = 28 盒（直排 18 + 楔齿循环 9 + _add_grip 1）+ 4 柱（枪管/消焰器/
##     后挡环/铰链轴）= 28×24+4×57 = 900
##   mp5 = 19 盒（直排 15 + 弯月匣 _smg_box_at 3 + _add_grip 1）+ 6 柱
##     （护木/肋环×2/枪管/枪口帽/照门鼓）= 19×24+6×57 = 798
##   p90 = 16 盒（直排 12 + 顶匣 _smg_box_at 3 + _add_grip 1）+ 3 柱
##     （前握把柱/枪管/消焰器）= 16×24+3×57 = 555
##   uzi = 14 盒（直排 13 + _add_grip 1）+ 3 柱（前管螺帽/枪管/拉机柄钮）
##     = 14×24+3×57 = 507
##   vector = 24 盒（直排 15 + 楔齿循环 8 + _add_grip 1）+ 2 柱（枪管/消焰器）
##     = 24×24+2×57 = 690
##   pistol = 4 盒×24 = 96（滑套/枪口/握把 _add_grip 自建盒/击锤，0 柱）
##   smg    = 15 盒×24 + 1 柱×57 = 417（柱=枪管）
##   rifle  = 30 盒×24 + 4 柱×57 = 948（轨齿×6 + M-LOK 侧槽 4×2 循环展开；
##            柱=枪管/消焰器/双挡环）
##   shotgun= 3 盒×24 + 2 柱×57 = 186（柱=枪管/弹管）
##   sniper = 7 盒×24 + 4 柱×57 = 396（柱=枪管+自带镜物镜/物镜罩/目镜三筒）
## 若 CylinderMesh rings 吃 4.7 默认 4 则柱顶点翻倍 → 门槛更松（红线只紧不松）。
## 【2026-10 源码复核】rings 缺省确为 4（官方类文档）→ 柱实际 90 顶/根
## （= 8·seg+10，见头部公式）；冲锋枪册 mp5/p90/uzi/vector 四把已按 90/柱
## 真基线复核仍 ≥8×：996×8=7968 ≤ 9572 / 654×8=5232 ≤ 6905 / 606×8=4848 ≤
## 6824 / 756×8=6048 ≤ 8075（mk4 同口径 8×1512=12096 ≤ 14410 亦过）；
## 旧五枪同口径复核全过：smg 450×8=3600 ≤ 5701 / rifle 1080×8=8640 ≤ 9841 /
## shotgun 252×8=2016 ≤ 5054 / sniper 528×8=4224 ≤ 8223 / pistol 0 柱不变
const POLY_BASE := {"mk4": 1380, "m4a1": 1266, "akm": 819, "scarh": 900,
		"mp5": 798, "p90": 555, "uzi": 507, "vector": 690,
		"pistol": 96, "smg": 417, "rifle": 948, "shotgun": 186,
		"sniper": 396}

## 分段旋钮（顶点量级的唯一来源；SEG_TUBE ≥ 32 = 圆护木圆滑红线）
const SEG_CHAMFER := 6      # 倒角盒每面网格默认分段
const SEG_DETAIL := 3       # 小件默认分段（准星/扳机/槽板/弹匣段）
const SEG_BARREL := 36      # 枪管默认径向分段
const SEG_TUBE := 48        # 圆护木/套筒默认径向分段（≥32）
const TORUS_RINGS := 36     # 环件主圈分段
const TORUS_SEG := 18       # 环件管圈分段

## 六面基架：n=外法线 / t1·t2=面内两轴（t1×t2=n）。Godot 正面=顺时针环绕，
## 三角形按 p00→p01→p11 / p00→p11→p10 出（t1 右 t2 上视角的顺时针）
const _FACE_AXES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


## ---------------- 对账工具 ----------------


## 统计 root（含自身）子树所有 MeshInstance3D 的 0 号面顶点和——
## test_huodai 顶点红线断言与改造前后顶点对账共用
static func count_vertices(root: Node) -> int:
	var total := 0
	if root is MeshInstance3D:
		total += _mesh_verts((root as MeshInstance3D).mesh)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		total += _mesh_verts((mi as MeshInstance3D).mesh)
	return total


## 单 mesh 顶点数（无面/无顶点数组 = 0）
static func _mesh_verts(m: Mesh) -> int:
	if m == null or m.get_surface_count() == 0:
		return 0
	var arrs: Array = m.surface_get_arrays(0)
	if arrs.is_empty():
		return 0
	var v: Variant = arrs[Mesh.ARRAY_VERTEX]
	if v == null:
		return 0
	return (v as PackedVector3Array).size()


## ---------------- 基础件 ----------------


## 倒角方块：外盒表面每面 seg×seg 网格采样（cosine 间距向四边棱线加密），
## 每点先向内盒（半边长各收 chamfer）收拢、再沿径向推出 chamfer——
## 平面区严格贴原盒面、12 条棱变四分之一圆柱、8 角变球面：直角棱线消除、
## 法线全平滑。顶点 = 6·seg²+2 / 三角 = 12·seg²。
## chamfer<0 = 自动（最小边×0.18，钳 0.8~4mm）
static func chamfer_box(parent: Node3D, mat: Material, size: Vector3,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO,
		chamfer: float = -1.0, seg: int = SEG_CHAMFER) -> MeshInstance3D:
	var half := size * 0.5
	var c := chamfer
	if c < 0.0:
		c = clampf(minf(size.x, minf(size.y, size.z)) * 0.18, 0.0008, 0.004)
	var hi := Vector3(maxf(half.x - c, 0.0004), maxf(half.y - c, 0.0004),
			maxf(half.z - c, 0.0004))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axes in _FACE_AXES:
		var n: Vector3 = axes[0]
		var t1: Vector3 = axes[1]
		var t2: Vector3 = axes[2]
		var hn := _axis_half(n, half)   # 面沿法线的半边长
		var h1 := _axis_half(t1, half)  # 面沿 t1 的半边长
		var h2 := _axis_half(t2, half)  # 面沿 t2 的半边长
		var grid: Array = []
		for i in seg + 1:
			var u: float = -cos(PI * float(i) / float(seg))
			var col: Array = []
			for j in seg + 1:
				var v: float = -cos(PI * float(j) / float(seg))
				var q: Vector3 = n * hn + t1 * (u * h1) + t2 * (v * h2)
				var inn := Vector3(clampf(q.x, -hi.x, hi.x),
						clampf(q.y, -hi.y, hi.y), clampf(q.z, -hi.z, hi.z))
				var dn := (q - inn).normalized()
				col.append([inn + dn * c, dn])
			grid.append(col)
		for i in seg:
			for j in seg:
				_push_tri(st, grid[i][j], grid[i][j + 1], grid[i + 1][j + 1])
				_push_tri(st, grid[i][j], grid[i + 1][j + 1], grid[i + 1][j])
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## 单轴单位向量的半边长取值（axis 是 ±单轴单位向量）
static func _axis_half(axis: Vector3, half: Vector3) -> float:
	return absf(axis.x) * half.x + absf(axis.y) * half.y + absf(axis.z) * half.z


## 推一个三角形（各顶点 [位置, 法线]；Godot 正面 = 顺时针环绕）
static func _push_tri(st: SurfaceTool, a: Array, b: Array, c2: Array) -> void:
	for p in [a, b, c2]:
		st.set_normal(p[1])
		st.add_vertex(p[0])


## 圆护木/枪管套筒：外筒（径向 seg ≥32、尾端封盖、枪口端开放）+ 内衬筒
## （向枪口端探出 6mm，开放端见壁厚断面 = 「壁感」）+ 可选 M-LOK 槽板
## （左右各 slots 条 + 底面 3 条嵌面暗板，负形槽暗示照 MK4 旧模槽块语言；
## 板长 slot_len 默认 50mm、自动钳 ≤45% 筒长——短筒开槽不会长过筒身）。
## 顶点 = 外筒 4·seg+5 + 内筒 5·seg+7（slots=0 到此为止）；slots>0 时再
## 加槽板 (2·slots+3)×6·slot_seg²+2（左右条与底面 3 条都在 if slots>0 门内）。
## 本地轴 Y、rot_deg 默认 (90,0,0) 躺平沿枪管（本地 −Y = 枪口向）
static func tube(parent: Node3D, mat: Material, length: float, outer_d: float,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3(90, 0, 0),
		wall: float = 0.004, slots: int = 0, slot_mat: Material = null,
		slot_seg: int = 4, seg: int = SEG_TUBE,
		slot_len: float = 0.05) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = rot_deg
	parent.add_child(root)
	var r_out := outer_d * 0.5
	var r_in := maxf(r_out - wall, r_out * 0.4)
	# 外筒：尾端（本地 +Y，挂枪后朝玩家侧）封盖、枪口端开放
	var outer := CylinderMesh.new()
	outer.top_radius = r_out
	outer.bottom_radius = r_out
	outer.height = length
	outer.radial_segments = seg
	outer.rings = 1
	outer.cap_top = true
	outer.cap_bottom = false
	outer.material = mat
	var om := MeshInstance3D.new()
	om.mesh = outer
	root.add_child(om)
	# 内衬筒：中心向枪口端偏 3mm、加长 6mm——枪口端探出露壁厚
	var inner := CylinderMesh.new()
	inner.top_radius = r_in
	inner.bottom_radius = r_in
	inner.height = length + 0.006
	inner.radial_segments = seg
	inner.rings = 1
	inner.material = slot_mat if slot_mat != null else mat
	var im := MeshInstance3D.new()
	im.mesh = inner
	im.position = Vector3(0, -0.003, 0)
	root.add_child(im)
	# M-LOK 槽板：左右各 slots 条（本地 ±X）+ 底面 3 条（本地 +Z =
	# 世界下方——rot(90,0,0) 后本地 Z 翻到世界 −Y）。板长 slot_len
	# 自动钳 ≤45% 筒长：短筒（如消焰器 L=0.05）开槽不会长过筒身
	if slots > 0:
		var sm: Material = slot_mat if slot_mat != null else mat
		var sl := clampf(slot_len, 0.006, length * 0.45)
		var pitch := length / float(slots + 1)
		for i in slots:
			var yy := -length * 0.5 + pitch * float(i + 1)
			chamfer_box(root, sm, Vector3(0.003, sl, 0.014),
					Vector3(-r_out * 0.985, yy, 0), Vector3.ZERO, 0.0008, slot_seg)
			chamfer_box(root, sm, Vector3(0.003, sl, 0.014),
					Vector3(r_out * 0.985, yy, 0), Vector3.ZERO, 0.0008, slot_seg)
		for i in 3:
			var yb := -length * 0.5 + (length / 4.0) * float(i + 1)
			chamfer_box(root, sm, Vector3(0.014, sl, 0.003),
					Vector3(0, yb, r_out * 0.985), Vector3.ZERO, 0.0008, slot_seg)
	return root


## 高分段枪管 + 枪口螺纹环（TorusMesh ×threads：自枪口端 35mm 起每 8mm 一道，
## 环截面半嵌管壁、凸起 2.5mm 读作螺纹/枪管螺帽）。
## 顶点 = (5·seg+7) + threads × (TORUS_RINGS+1)·(TORUS_SEG+1)。
## 本地轴 Y、rot_deg 默认 (90,0,0)，本地 −Y = 枪口向
static func barrel(parent: Node3D, mat: Material, length: float,
		caliber: float, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3(90, 0, 0), threads: int = 3,
		seg: int = SEG_BARREL) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = rot_deg
	parent.add_child(root)
	var cm := CylinderMesh.new()
	cm.top_radius = caliber * 0.5
	cm.bottom_radius = caliber * 0.5
	cm.height = length
	cm.radial_segments = seg
	cm.rings = 1
	cm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	root.add_child(mi)
	var r := caliber * 0.5
	for i in threads:
		var y := -length * 0.5 + 0.035 - 0.008 * float(i)
		torus_ring(root, mat, r - 0.001, r + 0.0025, Vector3(0, y, 0))
	return root


## 环件（TorusMesh）：inner/outer = 环心到环管内/外缘半径，圈密度
## rings×ring_seg（默认 36×18 → (37)·(19) = 703 顶点）。本地环面 XZ、
## 穿孔轴 Y——与筒件同 rot_deg 即同轴叠装
static func torus_ring(parent: Node3D, mat: Material, inner_r: float,
		outer_r: float, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, rings: int = TORUS_RINGS,
		ring_seg: int = TORUS_SEG) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = outer_r
	tm.rings = rings
	tm.ring_segments = ring_seg
	tm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## ---------------- 组合件 ----------------


## 手枪式握把（高模版 _add_grip，倾角符号约定一致 rot.x = −tilt_deg）：
## 倒角盒本体 + 顶缘外扩垫片 + 前脸指棱细条×ridges（指槽暗示）+ 底板。
## 顶点 ≈ (6·6²+2) + 26 + ridges×26 + 56 = 378（ridges=3）。
## pos = 握把【顶锚点】兼旋转支点（rot.x=−tilt 绕 pos 转，本体 local 中心
## (0,−height/2,0)）——与 _add_grip 的【中心锚】（盒心在 pos、绕盒心转）
## 不同口径！从 _add_grip 迁移坐标必须用矢量式（含 z 分量，只改 y 会让
## 握把沿杆后滑 (height/2)·sin(tilt)、20°/0.098 高 ≈16.8mm）：
##   pos = 旧盒心 + Rx(−tilt)·(0, height/2, 0)
##   即 pos.y = 旧盒心.y + height/2·cos(tilt)；pos.z = 旧盒心.z − height/2·sin(tilt)
## （MK4 样板踩过的坑；现存 12 处 _add_grip 调用点——旧五枪 5 + 冲锋枪册
## 4 + 步枪册 3——升模迁移时同样适用，样板会被三路枪匠复制）
static func grip(parent: Node3D, mat: Material, height: float,
		pos: Vector3, tilt_deg: float = 20.0, width: float = 0.038,
		depth: float = 0.054, ridge_mat: Material = null,
		ridges: int = 3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = Vector3(-tilt_deg, 0, 0)
	parent.add_child(root)
	chamfer_box(root, mat, Vector3(width, height, depth),
			Vector3(0, -height * 0.5, 0), Vector3.ZERO, -1.0, 6)
	chamfer_box(root, mat, Vector3(width * 1.08, 0.008, depth * 1.08),
			Vector3(0, -0.004, 0), Vector3.ZERO, 0.001, 2)
	var rm: Material = ridge_mat if ridge_mat != null else mat
	for i in ridges:
		chamfer_box(root, rm, Vector3(width * 0.8, 0.005, 0.005),
				Vector3(0, -height * 0.35 - float(i) * 0.017, -depth * 0.5),
				Vector3.ZERO, 0.001, 2)
	chamfer_box(root, mat, Vector3(width * 1.1, 0.01, depth * 1.15),
			Vector3(0, -height - 0.003, 0), Vector3.ZERO, 0.0015, 3)
	return root


## 弧形弹匣：分段倒角盒沿弧线排布（每段累进 bend_deg、段心沿切线下行，
## 弧向前 = 世界 −Z，与 MP5 弯月匣同向）+ 底盖板。顶点 = (segments+1)×(6·seg²+2)。
## 弹匣契约：调用方先建独立命名节点（如 mag_straight）作 parent 传入——
## 形件不与枪身散件混淆、换弹手沿该节点跟随（契约不变）
static func curved_mag(parent: Node3D, mat: Material, size: Vector3,
		bend_deg: float = 12.0, segments: int = 3,
		seg: int = SEG_DETAIL) -> Node3D:
	var step := size.y / float(segments)
	var center := Vector3(0, -step * 0.5, 0)
	for i in segments:
		if i > 0:
			var a := deg_to_rad(bend_deg * (float(i) - 0.5))
			center += Vector3(0.0, -cos(a), -sin(a)) * step
		chamfer_box(parent, mat, Vector3(size.x, step + 0.012, size.z),
				center, Vector3(bend_deg * float(i), 0, 0), 0.0015, seg)
	var a_end := deg_to_rad(bend_deg * float(segments - 1))
	var base_c := center + Vector3(0.0, -cos(a_end), -sin(a_end)) \
			* (step * 0.5 + 0.004)
	chamfer_box(parent, mat, Vector3(size.x + 0.004, 0.012, size.z + 0.008),
			base_c, Vector3(bend_deg * float(segments - 1), 0, 0), 0.0015, seg)
	return parent
