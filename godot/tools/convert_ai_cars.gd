extends SceneTree
## 离线转换：把 AI 生成的整块网格车模按几何特征拆出 4 个车轮，
## 生成带 HubXX/WheelXX/BodyPivot 骨架的场景，接入 CarVisual 常规 GLB 管线
## （车轮滚动/转向动画即自动联动）。
## 用法：Godot --headless --path . -s tools/convert_ai_cars.gd
## 转换一次性完成；之后 TrackData 直接指向生成的 .scn（yaw/scale 已烘焙，无需再配）。

const JOBS := [
	{"glb": "res://assets/cars/car_tripo_a.glb", "out": "res://assets/cars/car_tripo_a_rig.scn", "yaw_deg": 180.0, "scale": 4.6},
	{"glb": "res://assets/cars/car_tripo_b.glb", "out": "res://assets/cars/car_tripo_b_rig.scn", "yaw_deg": -90.0, "scale": 4.6},
	{"glb": "res://assets/cars/car_tripo_c.glb", "out": "res://assets/cars/car_tripo_c_rig.scn", "yaw_deg": -90.0, "scale": 4.6},
]

const NY := 128      # y 网格数（0..1.024 m，格 0.008）
const NU := 220      # |z| 网格数（0..1.76 m，格 0.008）

# 个别被车身严实包裹、自动检测失败的车轮：人工按同轴前轮几何 + 霍夫轴向位置指定。
# 键 = "模型文件/轮位"，c 为拆分后坐标系（车头 +Z、原点地面中心）下的轮毂中心。
const WHEEL_OVERRIDES := {
	"car_tripo_a.glb/RL": {"c": Vector3(0.71, 0.35, -1.567), "r": 0.35, "w": 0.42},
	"car_tripo_a.glb/RR": {"c": Vector3(-0.71, 0.35, -1.567), "r": 0.35, "w": 0.42},
	"car_tripo_b.glb/RL": {"c": Vector3(0.82, 0.30, -1.37), "r": 0.30, "w": 0.35},
	"car_tripo_b.glb/RR": {"c": Vector3(-0.82, 0.30, -1.37), "r": 0.30, "w": 0.35},
}

func _initialize() -> void:
	var failed := 0
	for job in JOBS:
		print("\n===== ", job["glb"], " =====")
		if not _convert(job):
			failed += 1
			print("[convert] FAIL")
	print("\n[convert] 全部完成，失败 ", failed)
	quit(1 if failed > 0 else 0)


func _convert(job: Dictionary) -> bool:
	var packed: PackedScene = load(job["glb"])
	if packed == null:
		return false
	var root := packed.instantiate()
	var mi := _find_mesh(root)
	if mi == null:
		return false

	# ---- 收集全部表面，烘焙 yaw + scale，落到“地面中心”原点（车头 +Z）----
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idxs := PackedInt32Array()
	var basis := Basis(Vector3.UP, deg_to_rad(float(job["yaw_deg"]))) \
			.scaled(Vector3.ONE * float(job["scale"]))
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(sv)
		if arr[Mesh.ARRAY_NORMAL] != null:
			norms.append_array(arr[Mesh.ARRAY_NORMAL])
		else:
			norms.resize(verts.size())
		if arr[Mesh.ARRAY_TEX_UV] != null:
			uvs.append_array(arr[Mesh.ARRAY_TEX_UV])
		else:
			uvs.resize(verts.size())
		var si = arr[Mesh.ARRAY_INDEX]
		if si == null or si.is_empty():
			for i in sv.size():
				idxs.append(base + i)
		else:
			for i in si.size():
				idxs.append(base + si[i])
	for i in verts.size():
		verts[i] = basis * verts[i]
		if i < norms.size():
			norms[i] = (basis * norms[i]).normalized()
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var off := Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	for i in verts.size():
		verts[i] += off
	aabb.position += off
	var H := aabb.size.y
	var L := aabb.size.z
	print("[convert] 顶点 %d 三角 %d 车身 %.2f×%.2f×%.2f m" % [verts.size(), idxs.size() / 3,
			aabb.size.x, H, L])

	# ---- 定位四个车轮（轴线沿 X 的圆柱：胎触地 → 轴高 = 半径）----
	# 单趟预筛：按象限建立 (y, |z|) 占用网格与顶点列表
	var grids := [
		[{"cells": PackedInt32Array(), "u_max": L / 2.0}, {"cells": PackedInt32Array(), "u_max": L / 2.0}],
		[{"cells": PackedInt32Array(), "u_max": L / 2.0}, {"cells": PackedInt32Array(), "u_max": L / 2.0}],
		[[PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()],
			[PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()],
			[PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()],
			[PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]],
	]
	for gi in 4:
		grids[gi / 2][gi % 2]["cells"].resize(NY * NU)
	for i in verts.size():
		var v := verts[i]
		if v.y >= 1.024:
			continue
		var yb := int(v.y * 125.0)
		var ub := int(absf(v.z) * 125.0)
		if ub >= NU:
			continue
		var qi := (0 if v.z >= 0.0 else 1) * 2 + (0 if v.x >= 0.0 else 1)
		var cells: PackedInt32Array = grids[qi / 2][qi % 2]["cells"]
		cells[ub * NY + yb] += 1
		var n := norms[i] if i < norms.size() else Vector3.ZERO
		var pv: Array = grids[2][qi]
		pv[0].append(v.y)
		pv[1].append(absf(v.z))
		pv[2].append(v.x)
		pv[3].append(n.y)
		pv[4].append(n.z)
		pv[5].append(n.x)

	var wheels := {}   # "FL" -> {c: Vector3, r, w}
	for key in ["FL", "FR", "RL", "RR"]:
		var w := _detect_wheel(grids, verts, norms, key)
		if w.is_empty():
			w = WHEEL_OVERRIDES.get(job["glb"].get_file() + "/" + key, {})
			if not w.is_empty():
				print("[convert] %s 使用人工覆盖: 中心=%s 半径=%.2f 胎宽=%.2f" % [
						key, w["c"], w["r"], w["w"]])
		if w.is_empty():
			print("[convert] FAIL 未定位到车轮 ", key)
			return false
		wheels[key] = w
		print("[convert] %s 中心=(%.2f, %.2f, %.2f) 半径=%.2f 胎宽=%.2f" % [key,
				w["c"].x, w["c"].y, w["c"].z, w["r"], w["w"]])

	# ---- 三角形分配：三顶点都落在轮圆柱内 → 轮；否则车身 ----
	var parts := {"body": PackedInt32Array()}
	for key in wheels:
		parts[key] = PackedInt32Array()
	for f in idxs.size() / 3:
		var assigned := "body"
		for key in wheels:
			var w: Dictionary = wheels[key]
			var c: Vector3 = w["c"]
			var inside := true
			for vi in [idxs[f * 3], idxs[f * 3 + 1], idxs[f * 3 + 2]]:
				var p := verts[vi]
				var dyz := Vector2(p.y - c.y, p.z - c.z).length()
				if dyz > w["r"] * 1.05 or absf(p.x - c.x) > w["w"] * 0.62:
					inside = false
					break
			if inside:
				assigned = key
				break
		parts[assigned].append(f)

	for key in wheels:
		if parts[key].size() < 30:
			print("[convert] FAIL 车轮 ", key, " 三角形过少: ", parts[key].size())
			return false
	var wheel_stats := PackedStringArray()
	for key in ["FL", "FR", "RL", "RR"]:
		wheel_stats.append("%s:%d" % [key, parts[key].size() / 3])
	print("[convert] 分配 车身 %d | 轮 %s" % [parts["body"].size() / 3,
			" ".join(wheel_stats)])

	# ---- 材质（原贴图材质，嵌入场景）----
	var src_mat := mi.get_active_material(0)
	var mat := (src_mat.duplicate() if src_mat != null else StandardMaterial3D.new())
	mat.resource_path = ""

	# ---- 组装场景：BodyPivot → Body + Hub→Wheel→轮网格 ----
	var scene_root := Node3D.new()
	scene_root.name = "root"
	var bp := Node3D.new()
	bp.name = "BodyPivot"
	scene_root.add_child(bp)
	var body_mi := MeshInstance3D.new()
	body_mi.name = "Body"
	body_mi.mesh = _build_mesh(verts, norms, uvs, idxs, parts["body"], Vector3.ZERO, mat)
	bp.add_child(body_mi)
	for key in ["FL", "FR", "RL", "RR"]:
		var w: Dictionary = wheels[key]
		var hub := Node3D.new()
		hub.name = "Hub" + key
		hub.position = w["c"]
		scene_root.add_child(hub)
		var spin := Node3D.new()
		spin.name = "Wheel" + key
		hub.add_child(spin)
		var wmi := MeshInstance3D.new()
		wmi.name = "WheelMesh" + key
		wmi.mesh = _build_mesh(verts, norms, uvs, idxs, parts[key], w["c"], mat)
		spin.add_child(wmi)

	# pack() 只保存 owner 指向根的节点：程序化创建的树必须手动设置 owner
	var own_stack := [scene_root]
	while not own_stack.is_empty():
		var n: Node = own_stack.pop_back()
		for c in n.get_children():
			c.owner = scene_root
			own_stack.push_back(c)

	var ps := PackedScene.new()
	ps.pack(scene_root)
	var err := ResourceSaver.save(ps, job["out"])
	if err != OK:
		print("[convert] FAIL 保存失败: ", error_string(err))
		return false
	print("[convert] 已保存 ", job["out"])
	return true


## 车轮定位：霍夫扫描 (y,|z|) 占用网格得到候选圆心，再利用法线特征锁定胎面——
## 胎面顶点法线在 (y,u) 截面内沿半径向外且无横向分量。
## 被车身包裹的后轮法线被平滑，严格阈值失败时自动放宽重试。
func _detect_wheel(grids: Array, verts: PackedVector3Array, norms: PackedVector3Array,
		key: String) -> Dictionary:
	var sx := 1.0 if key.ends_with("L") else -1.0    # gt3 约定 FL=+X
	var sz := 1.0 if key.begins_with("F") else -1.0  # u = |z|
	var g: Dictionary = grids[0 if sz > 0 else 1][0 if sx > 0 else 1]
	var cells: PackedInt32Array = g["cells"]
	var L2: float = g["u_max"]
	# ---- 霍夫粗扫：得分最高的圆（圆心高度=半径，过地面切点）----
	var best_s := 0
	var r_h := 0.0
	var u_h := 0.0
	var r := 0.19
	while r <= 0.48:
		var u := 0.35
		while u <= L2:
			var s := _ring_score(cells, r, u)
			if s > best_s:
				best_s = s
				r_h = r
				u_h = u
			u += 0.025
		r += 0.01
	if best_s < 400:
		print("[convert] DBG 霍夫无峰 ", key, " best=", best_s)
		return {}
	# ---- 两档法线阈值：严格优先，失败放宽重试 ----
	var res := {}
	for fp in [[0.6, 0.4], [0.42, 0.55]]:
		res = _find_tread(grids, key, r_h, u_h, sz, fp[0], fp[1])
		if not res.is_empty():
			break
	if res.is_empty():
		print("[convert] DBG 未找到整圆簇 ", key)
		return {}
	var r_out: float = res["r"]
	var u_c: float = res["u"]
	var sb_found: int = res["sb"]
	var d_lo: float = res["d_lo"]
	var d_bw: float = res["d_bw"]
	var tread: Array = res["tread"]
	var pv: Array = res["pv"]
	var ys: PackedFloat32Array = pv[0]
	var us: PackedFloat32Array = pv[1]

	# ---- 胎宽/横向位置：胎壁顶点（法线近横向）的 x 分布取双峰间距 ----
	var xs := PackedFloat32Array()
	for i in ys.size():
		if absf(pv[5][i]) < 0.55:
			continue
		var dyw: float = ys[i] - r_out
		var duw: float = us[i] - u_c
		var dw := sqrt(dyw * dyw + duw * duw)
		if dw > r_out * 0.7 and dw < r_out * 1.03:
			xs.append(pv[2][i])
	var cx: float
	var w: float
	if xs.size() >= 40:
		xs.sort()
		var x_lo := xs[0]
		var x_hi := xs[xs.size() - 1]
		var nb := 48
		var bw := (x_hi - x_lo) / nb
		if bw > 0.0:
			var hc := PackedInt32Array()
			hc.resize(nb)
			for x in xs:
				hc[clampi(int((x - x_lo) / bw), 0, nb - 1)] += 1
			var p1 := 0
			for i in nb:
				if hc[i] > hc[p1]:
					p1 = i
			var p2 := -1
			var p2v := 0
			for i in nb:
				if absi(i - p1) >= 4 and hc[i] >= hc[p1] * 3 / 10 and hc[i] > p2v:
					p2 = i
					p2v = hc[i]
			if p2 >= 0:
				cx = (x_lo + (p1 + 0.5) * bw + x_lo + (p2 + 0.5) * bw) * 0.5
				w = absf(p2 - p1) * bw
	# 兜底：胎面壳层顶点的 x 分位宽度
	if w <= 0.0:
		xs.clear()
		for t in tread:
			if t[3] >= d_lo + sb_found * d_bw and t[3] < d_lo + (sb_found + 4) * d_bw:
				xs.append(t[2])
		if xs.size() < 40:
			print("[convert] DBG 胎面顶点不足 ", key, " n=", xs.size())
			return {}
		xs.sort()
		cx = xs[xs.size() / 2]
		w = xs[int(xs.size() * 0.98)] - xs[int(xs.size() * 0.02)]
	if r_out < 0.18 or r_out > 0.52:
		print("[convert] DBG 半径越界 ", key, " r_out=", r_out)
		return {}
	if w < 0.12 or w > 0.55:
		print("[convert] DBG 胎宽异常 ", key, " w=", w)
		return {}
	if OS.get_environment("WHEEL_DBG") != "":
		print("[convert] DBG %s → 胎面 r=%.3f u=%.3f w=%.2f cx=%.2f" % [
				key, r_out, u_c, w, cx])
	return {"c": Vector3(cx, r_out, u_c * sz), "r": r_out, "w": w}


## 在霍夫圆心邻域收集法线径向朝外的顶点，按径向簇 + 角度覆盖度锁定胎面圆
func _find_tread(grids: Array, key: String, r_h: float, u_h: float, sz: float,
		radial_min: float, nx_max: float) -> Dictionary:
	var bins := 48
	var d_lo := 0.3 * r_h
	var d_hi := minf(2.2 * r_h, 0.62)
	var d_bw := (d_hi - d_lo) / bins
	var dh := PackedInt32Array()
	dh.resize(bins)
	var tread := []            # [y, u, x, d]
	var sx := 1.0 if key.ends_with("L") else -1.0
	var qi := (0 if sz > 0 else 1) * 2 + (0 if sx > 0 else 1)
	var pv: Array = grids[2][qi]
	var ys: PackedFloat32Array = pv[0]
	var us: PackedFloat32Array = pv[1]
	for i in ys.size():
		var dy: float = ys[i] - r_h
		var du: float = us[i] - u_h
		var d := sqrt(dy * dy + du * du)
		if d < d_lo or d > d_hi:
			continue
		if absf(pv[5][i]) > nx_max:       # 排除横向面（胎壁/车身侧面）
			continue
		var radial: float = (pv[3][i] * dy + pv[4][i] * sz * du) / d
		if radial < radial_min:           # 法线非径向朝外 → 非胎面
			continue
		tread.append([ys[i], us[i], pv[2][i], d])
		dh[clampi(int((d - d_lo) / d_bw), 0, bins - 1)] += 1
	if tread.is_empty():
		return {}
	if OS.get_environment("WHEEL_DBG") != "":
		var hs := ""
		for c in dh:
			hs += "%5d" % c
		print("[convert] DBG %s 径向(%.2f/%.2f) %.2f~%.2f: %s" % [
				key, radial_min, nx_max, d_lo, d_hi, hs])
	# ---- 径向簇分割：从最外侧簇向内找第一个“整圆”簇 = 胎面 ----
	# （胎面覆盖完整圆周；轮眉/扰流弧只在上方半圈，角度覆盖度低 → 向内回退）
	var dmax := 0
	for c in dh:
		dmax = maxi(dmax, c)
	var min_c := maxi(8, dmax * 12 / 100)
	var r_out := 0.0
	var u_c := 0.0
	var sb_found := 0
	var b_hi := bins
	while b_hi > 0:
		while b_hi > 0 and dh[b_hi - 1] < min_c:
			b_hi -= 1
		if b_hi <= 0:
			break
		var b_lo := b_hi
		while b_lo > 0 and dh[b_lo - 1] >= min_c:
			b_lo -= 1
		var sd := 0.0
		var su := 0.0
		var cnt := 0
		for t in tread:
			if t[3] >= d_lo + b_lo * d_bw and t[3] < d_lo + b_hi * d_bw:
				sd += t[0]
				su += t[1]
				cnt += 1
		if cnt >= maxi(200, tread.size() / 20):
			var cr := sd / cnt
			var cu := su / cnt
			var sect := PackedInt32Array()
			sect.resize(12)
			for t in tread:
				if t[3] >= d_lo + b_lo * d_bw and t[3] < d_lo + b_hi * d_bw:
					sect[int((atan2(t[1] - cu, t[0] - cr) + PI) / (TAU / 12.0)) % 12] += 1
			var covered := 0
			for s2 in sect:
				if s2 >= cnt / 20:
					covered += 1
			if covered >= 9:
				r_out = cr
				u_c = cu
				sb_found = b_lo
				if OS.get_environment("WHEEL_DBG") != "":
					print("[convert] DBG %s 簇 bins %d..%d 覆盖 %d/12 ✓" % [
							key, b_lo, b_hi, covered])
				break
			# 合并簇：按子壳从外向内细扫；每个子壳做迭代圆拟合
			# （霍夫圆心有偏移时，环带均值中心逐轮向真实圆心收敛）
			var found := false
			var sb := b_hi - 4
			while sb >= b_lo and not found:
				var irc: float = d_lo + (sb + 2) * d_bw
				var icy: float = r_h
				var icu: float = u_h
				var band := []
				for it in 3:
					band.clear()
					for t in tread:
						var dd: float = t[3] if it == 0 \
								else sqrt((t[0] - icy) * (t[0] - icy) + (t[1] - icu) * (t[1] - icu))
						if absf(dd - irc) < 0.022:
							band.append(t)
					if band.size() < 150:
						break
					var s2y := 0.0
					var s2u := 0.0
					var s2d := 0.0
					for t in band:
						s2y += t[0]
						s2u += t[1]
						s2d += sqrt((t[0] - icy) * (t[0] - icy) + (t[1] - icu) * (t[1] - icu))
					icy = s2y / band.size()
					icu = s2u / band.size()
					irc = s2d / band.size()
				if band.size() < 250:
					sb -= 1
					continue
				var sect2 := PackedInt32Array()
				sect2.resize(12)
				for t in band:
					sect2[int((atan2(t[1] - icu, t[0] - icy) + PI) / (TAU / 12.0)) % 12] += 1
				var cov2 := 0
				for s3 in sect2:
					if s3 >= band.size() / 20:
						cov2 += 1
				if cov2 >= 8:
					r_out = irc
					u_c = icu
					sb_found = sb
					found = true
					if OS.get_environment("WHEEL_DBG") != "":
						print("[convert] DBG %s 子壳 bins %d..%d 覆盖 %d/12 ✓ r=%.3f u=%.3f" % [
								key, sb, sb + 4, cov2, irc, icu])
				sb -= 1
			if found:
				break
		b_hi = b_lo
	if r_out <= 0.0:
		return {}
	return {"r": r_out, "u": u_c, "sb": sb_found, "tread": tread, "pv": pv,
			"bins": bins, "d_lo": d_lo, "d_bw": d_bw}




func _ring_score(cells: PackedInt32Array, r: float, u_c: float) -> int:
	var s := 0
	var steps := 90
	for i in steps:
		var th := TAU * float(i) / float(steps)
		var yb := int((r + r * sin(th)) * 125.0)          # y 网格 0.008m
		var ub := int((u_c + r * cos(th)) * 125.0)
		if yb < 0 or yb >= NY or ub < 0 or ub >= NU:
			continue
		for dy in [-1, 0, 1]:
			var yy: int = yb + dy
			if yy < 0 or yy >= NY:
				continue
			for du in [-1, 0, 1]:
				var uu: int = ub + du
				if uu >= 0 and uu < NU:
					s += cells[uu * NY + yy]
	return s


## 用原顶点池的子集重建网格（wheel_center 非零时把几何平移到轮毂局部系）
func _build_mesh(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, idxs: PackedInt32Array, faces: PackedInt32Array,
		wheel_center: Vector3, mat: Material) -> ArrayMesh:
	var remap := {}
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ou := PackedVector2Array()
	var oi := PackedInt32Array()
	for fi in faces.size():
		for k in 3:
			var src := idxs[faces[fi] * 3 + k]
			if not remap.has(src):
				remap[src] = ov.size()
				ov.append(verts[src] - wheel_center)
				if src < norms.size():
					on.append(norms[src])
				if src < uvs.size():
					ou.append(uvs[src])
			oi.append(remap[src])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_INDEX] = oi
	if on.size() == ov.size():
		arrays[Mesh.ARRAY_NORMAL] = on
	if ou.size() == ov.size():
		arrays[Mesh.ARRAY_TEX_UV] = ou
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, mat)
	m.resource_path = ""
	return m


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null
