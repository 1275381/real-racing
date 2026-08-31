class_name RaceTrack
extends Node3D
## 赛道：闭样条 -> 均匀弧长采样 -> 路面/标线/红白路肩/护栏/龙门架/看台
## （移植自 js/track.js，几何布局与物理查询语义保持一致）

const UP := Vector3.UP
const TENSION := 0.55          # three.js CatmullRomCurve3 'catmullrom' 张力
const _SEG_SAMPLES := 24       # 每个样条段的密集采样数（用于弧长重采样）

var theme := "country"
var half_w := TrackData.ROAD_HALF_W
var wall_lat := TrackData.ROAD_HALF_W + 2.05   # 软墙限位（护栏内侧）

var pts := PackedVector2Array()        # 中心线采样点 (x, z)
var heights := PackedFloat32Array()    # 各采样点路面高度（自定义赛道起伏）
var slope := PackedFloat32Array()      # 沿切线坡度 dy/ds
var tang := PackedVector2Array()       # 单位切线
var left_v := PackedVector2Array()     # 左向量（three: UP × tangent）
var ang := PackedFloat32Array()        # atan2(t.x, t.z)
var curv := PackedFloat32Array()       # 平滑后带符号曲率
var n := 0                             # 采样数
var length := 0.0
var ds := 0.0                          # 相邻采样点弧长间距

var start_idx := 0
var straight_behind := 46.0

var _grid := {}                        # 空间网格：Vector2i -> PackedInt32Array
var _cell := 48.0
var _lamp_mats: Array[StandardMaterial3D] = []

# 运行时查询复用的结果对象（等价 js 的 _scratch）
var _scratch := {"idx": 0, "lat_off": 0.0, "ang": 0.0, "surf": "road", "dist_sq": 0.0,
		"height": 0.0, "slope": 0.0, "wall": 0.0}

func build(def: Dictionary) -> void:
	theme = def.get("theme", "country")
	var cps: Array = def["points"]
	var m := cps.size()

	# ---- 闭式 Catmull-Rom 密集采样（支持 Vector2=平地 / Vector3=带高度，3D 弧长）----
	var dense := TrackData.sample_closed_spline(cps, _SEG_SAMPLES)

	# ---- 累计弧长 -> 均匀重采样 ----
	var cum := PackedFloat32Array()
	cum.resize(dense.size() + 1)
	cum[0] = 0.0
	for i in dense.size():
		cum[i + 1] = cum[i] + dense[i].distance_to(dense[(i + 1) % dense.size()])
	length = cum[cum.size() - 1]
	n = maxi(700, roundi(length / 1.3))   # 约 1.3m 一个采样
	ds = length / n

	pts.resize(n)
	heights.resize(n)
	tang.resize(n)
	left_v.resize(n)
	ang.resize(n)
	var j := 0
	for i in n:
		var target := length * float(i) / n
		while j < dense.size() - 1 and cum[j + 1] < target:
			j += 1
		var seg_len := maxf(cum[j + 1] - cum[j], 1e-6)
		var f := clampf((target - cum[j]) / seg_len, 0.0, 1.0)
		var p3 := dense[j].lerp(dense[(j + 1) % dense.size()], f)
		pts[i] = Vector2(p3.x, p3.z)
		heights[i] = p3.y

	for i in n:
		var tv := (pts[(i + 1) % n] - pts[i]).normalized()
		tang[i] = tv
		left_v[i] = Vector2(tv.y, -tv.x)     # three: UP × t = (t.z, 0, -t.x)
		ang[i] = atan2(tv.x, tv.y)

	# ---- 沿切线坡度（车辆上下坡 / 坡顶腾空用）----
	slope.resize(n)
	for i in n:
		slope[i] = (heights[(i + 1) % n] - heights[(i - 1 + n) % n]) / (2.0 * ds)

	# ---- 带符号曲率（平滑窗）----
	var raw_k := PackedFloat32Array()
	raw_k.resize(n)
	for i in n:
		var a := tang[i]
		var b := tang[(i + 1) % n]
		raw_k[i] = a.y * b.x - a.x * b.y
	var w := 9
	curv.resize(n)
	for i in n:
		var s := 0.0
		for d in range(-w, w + 1):
			s += raw_k[(i + d + n) % n]
		curv[i] = s / float(2 * w + 1)

	_build_spatial_grid()
	_find_start_line()
	_build_all_meshes()


func _build_spatial_grid() -> void:
	_grid.clear()
	for i in range(0, n, 2):
		var key := Vector2i(int(pts[i].x / _cell), int(pts[i].y / _cell))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)


func _near_indices(x: float, z: float, r: float) -> Array:
	var out: Array = []
	var gx := int(x / _cell)
	var gz := int(z / _cell)
	var big_r := int(ceil(r / _cell))
	for i in range(-big_r, big_r + 1):
		for d in range(-big_r, big_r + 1):
			var key := Vector2i(gx + i, gz + d)
			if _grid.has(key):
				out.append_array(_grid[key])
	return out


func is_clear_of_road(x: float, z: float, min_dist: float) -> bool:
	var cand := _near_indices(x, z, min_dist + 10.0)
	var d2min := min_dist * min_dist
	for i in cand:
		var dx := pts[i].x - x
		var dz := pts[i].y - z
		if dx * dx + dz * dz < d2min:
			return false
	return true


## 查找最长的平直段作为起跑区
func _find_start_line() -> void:
	var thr := 0.0055
	var best_len := 0
	var best_start := 0
	var run := 0
	var run_start := 0
	for i in n * 2:
		var k := absf(curv[i % n])
		if k < thr:
			if run == 0:
				run_start = i
			run += 1
			if run > best_len:
				best_len = run
				best_start = run_start
		else:
			run = 0
	if best_len < 50:   # 兜底：全赛道扫描曲率最小的窗口（保证起跑线落在最平的路段）
		var win := maxi(35, roundi(46.0 / ds))   # 窗口大小 = 发车区所需采样数
		var best_k_sum := 1e9
		best_start = 0
		for i in n:
			var s := 0.0
			for d in range(win):
				s += absf(curv[(i + d) % n])
			if s < best_k_sum:
				best_k_sum = s
				best_start = i
		best_len = win
	start_idx = (best_start + int(best_len * 0.42)) % n
	straight_behind = minf(best_len - best_len * 0.42, 46.0)


func ahead_idx(idx: int, meters: float) -> int:
	return posmod(idx + roundi(meters / ds), n)


## 发车位：startIdx 后方两列错开
func grid_pose(slot: int) -> Dictionary:
	var back_d := 7.0 + slot * 5.0
	var bi := ahead_idx(start_idx, -back_d)
	var side := -1.0 if slot % 2 == 0 else 1.0
	var p := pts[bi]
	var l := left_v[bi]
	return {
		"pos": Vector3(p.x + l.x * 2.9 * side, heights[bi], p.y + l.y * 2.9 * side),
		"heading": ang[bi],
		"idx": bi,
	}


## 运行时查询：最近采样点索引 / 横向偏移 / 路面类型。hint 传上次索引可局部搜索
func query(x: float, z: float, hint) -> Dictionary:
	var bi := 0
	var bd := INF
	if hint == null:
		for i in n:
			var dx := pts[i].x - x
			var dz := pts[i].y - z
			var d := dx * dx + dz * dz
			if d < bd:
				bd = d
				bi = i
	else:
		var win := 46
		var h: int = hint
		for o in range(-win, win + 1):
			var i := posmod(h + o, n)
			var dx := pts[i].x - x
			var dz := pts[i].y - z
			var d := dx * dx + dz * dz
			if d < bd:
				bd = d
				bi = i
	var p := pts[bi]
	var l := left_v[bi]
	var lat := (x - p.x) * l.x + (z - p.y) * l.y
	var al := absf(lat)
	_scratch["idx"] = bi
	_scratch["lat_off"] = lat
	_scratch["ang"] = ang[bi]
	_scratch["dist_sq"] = bd
	_scratch["surf"] = "grass" if al > half_w + 1.42 \
			else ("curb" if al > half_w - 0.35 else "road")
	_scratch["height"] = heights[bi]
	_scratch["slope"] = slope[bi]
	_scratch["wall"] = wall_lat
	return _scratch


# ============================================================
#  几何构建
# ============================================================

var _v_pos := PackedVector3Array()
var _v_nrm := PackedVector3Array()
var _v_col := PackedColorArray()
var _v_uv := PackedVector2Array()


## 追加一个双三角四边形（角点按 a-b-c-d 环绕；nrm 为面法向）。
## 注意：Godot 正面为顺时针绕向（与 three.js 相反），三角形按 a,c,b / a,d,c 发出
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color,
		uv_a := Vector2.ZERO, uv_b := Vector2.ZERO, uv_c := Vector2.ZERO, uv_d := Vector2.ZERO) -> void:
	for tri in [[a, c, b, uv_a, uv_c, uv_b], [a, d, c, uv_a, uv_d, uv_c]]:
		_v_pos.append(tri[0])
		_v_pos.append(tri[1])
		_v_pos.append(tri[2])
		_v_nrm.append(nrm)
		_v_nrm.append(nrm)
		_v_nrm.append(nrm)
		_v_col.append(col)
		_v_col.append(col)
		_v_col.append(col)
		_v_uv.append(tri[3])
		_v_uv.append(tri[4])
		_v_uv.append(tri[5])


func _p(v: Vector2, y: float) -> Vector3:
	return Vector3(v.x, y, v.y)


## 采样点 i 的世界坐标（y = 路面高度 + off），网格构建随地形起伏
func _gy(i: int, off: float) -> Vector3:
	return Vector3(pts[i].x, heights[i] + off, pts[i].y)


func _flush(mat: Material, cast_shadow := false) -> MeshInstance3D:
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v_pos
	arrays[Mesh.ARRAY_NORMAL] = _v_nrm
	arrays[Mesh.ARRAY_COLOR] = _v_col
	arrays[Mesh.ARRAY_TEX_UV] = _v_uv
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_v_pos = PackedVector3Array()
	_v_nrm = PackedVector3Array()
	_v_col = PackedColorArray()
	_v_uv = PackedVector2Array()
	return mi


func _build_all_meshes() -> void:
	_build_apron()
	_build_road_meshes()
	_build_rails()
	_build_gantry()
	_build_stands()


## 砂石路肩带
func _build_apron() -> void:
	var apron_col: Color = {"country": Color("#9a8a6a"), "city": Color("#8e9496"),
			"desert": Color("#cbb18a")}.get(theme, Color("#9a8a6a"))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = apron_col
	mat.roughness = 1.0
	for side in [-1.0, 1.0]:
		for i in n:
			var j := (i + 1) % n
			var wi := left_v[i]
			var wj := left_v[j]
			var a := _gy(i, 0.015) - Vector3(wi.x * side * (half_w + 3.4), 0, wi.y * side * (half_w + 3.4))
			var b := _gy(i, 0.015) - Vector3(wi.x * side * (half_w + 0.05), 0, wi.y * side * (half_w + 0.05))
			var c := _gy(j, 0.015) - Vector3(wj.x * side * (half_w + 0.05), 0, wj.y * side * (half_w + 0.05))
			var d := _gy(j, 0.015) - Vector3(wj.x * side * (half_w + 3.4), 0, wj.y * side * (half_w + 3.4))
			if side > 0:
				_quad(a, d, c, b, UP, apron_col)
			else:
				_quad(b, c, d, a, UP, apron_col)
	_flush(mat)


## 主路面（沥青含标线纹理）、红白路肩、起跑线
func _build_road_meshes() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = RRTextures.asphalt()
	mat.roughness = 0.92
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var rep := maxf(1.0, roundf(length / 16.0))   # 纹理重复次数，保证首尾无缝
	for i in n:
		var j := (i + 1) % n
		var pi := _gy(i, 0.03)
		var pj := _gy(j, 0.03)
		var li := left_v[i] * half_w
		var lj := left_v[j] * half_w
		var u0 := float(i) / n * rep
		var u1 := float(i + 1) / n * rep
		_quad(pi - Vector3(li.x, 0, li.y), pj - Vector3(lj.x, 0, lj.y),
				pj + Vector3(lj.x, 0, lj.y), pi + Vector3(li.x, 0, li.y), UP, Color.WHITE,
				Vector2(0, u0), Vector2(0, u1), Vector2(1, u1), Vector2(1, u0))
	_flush(mat)

	# 红白路肩：按曲率挑出弯道区段（每 4 个样本换一次颜色）
	var seg_w := 4
	var ranges: Array = []
	var st := -1
	for i in n:
		if absf(curv[i]) > 0.0075:
			if st < 0:
				st = i
		elif st >= 0:
			if i - st > 8:
				ranges.append([st, i])
			st = -1
	if st >= 0 and not ranges.is_empty() and (ranges[0][0] + n) - st > 8 and ranges[0][0] < 8:
		ranges[0][0] = st - n
	elif st >= 0 and n - st > 8:
		ranges.append([st, st + 20])

	var red := Color("#d23a2e")
	var white := Color("#eceff2")
	var curb_mat := StandardMaterial3D.new()
	curb_mat.vertex_color_use_as_albedo = true
	curb_mat.roughness = 0.65
	for rng in ranges:
		var s0: int = rng[0]
		var s1: int = rng[1]
		var seg_count := s1 - s0
		for side in [-1.0, 1.0]:
			for q in seg_count:
				var i := posmod(s0 + q, n)
				var i2 := posmod(s0 + q + 1, n)
				var col := red if int(q / float(seg_w)) % 2 == 0 else white
				var ai := _gy(i, 0.055) + Vector3(left_v[i].x * side * (half_w + 0.12), 0, left_v[i].y * side * (half_w + 0.12))
				var bi := _gy(i, 0.055) + Vector3(left_v[i].x * side * (half_w + 1.32), 0, left_v[i].y * side * (half_w + 1.32))
				var bj := _gy(i2, 0.055) + Vector3(left_v[i2].x * side * (half_w + 1.32), 0, left_v[i2].y * side * (half_w + 1.32))
				var aj := _gy(i2, 0.055) + Vector3(left_v[i2].x * side * (half_w + 0.12), 0, left_v[i2].y * side * (half_w + 0.12))
				if side > 0:
					_quad(bi, ai, aj, bj, UP, col)
				else:
					_quad(ai, bi, bj, aj, UP, col)
	_flush(curb_mat)

	# 起跑线格子
	var sp := pts[start_idx]
	var line := Node3D.new()
	line.position = Vector3(sp.x, heights[start_idx], sp.y)
	line.rotation.y = ang[start_idx]
	var ck := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_w * 2.0, 2.6)
	var ck_mat := StandardMaterial3D.new()
	ck_mat.albedo_texture = RRTextures.checker(roundi(half_w / 0.7), 2)
	ck_mat.roughness = 0.9
	plane.material = ck_mat
	ck.mesh = plane
	ck.position.y = 0.06
	line.add_child(ck)
	add_child(line)


## 护栏（连续钢带 + 立柱）
func _build_rails() -> void:
	var off := half_w + 2.35
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color("#b9bec5")
	rail_mat.metallic = 0.78
	rail_mat.roughness = 0.34
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		for i in n:
			var j := (i + 1) % n
			var bi := _gy(i, 0) - Vector3(left_v[i].x * off * side, 0, left_v[i].y * off * side)
			var bj := _gy(j, 0) - Vector3(left_v[j].x * off * side, 0, left_v[j].y * off * side)
			var a := bi + Vector3(0, 0.30, 0)
			var b := bj + Vector3(0, 0.30, 0)
			var c := bj + Vector3(0, 0.62, 0)
			var d := bi + Vector3(0, 0.62, 0)
			var nrm: Vector2 = -left_v[i] * side
			_quad(a, b, c, d, Vector3(nrm.x, 0, nrm.y).normalized(), rail_mat.albedo_color)
	_flush(rail_mat)

	# 立柱
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, 0.68, 0.16)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color("#7c828a")
	post_mat.metallic = 0.6
	post_mat.roughness = 0.5
	post_mesh.material = post_mat
	var step := 7
	var per_side := int(ceil(n / float(step)))
	var count := per_side * 2
	if count > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = post_mesh
		mm.instance_count = count
		var k := 0
		for side in [-1.0, 1.0]:
			for i in range(0, n, step):
				var xf := Transform3D(Basis.from_euler(Vector3(0, ang[i], 0)),
						_gy(i, 0.34) - Vector3(left_v[i].x * off * side, 0, left_v[i].y * off * side))
				mm.set_instance_transform(k, xf)
				k += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)


## 起点龙门架 + 信号灯 + 横幅
func _build_gantry() -> void:
	var sp := pts[start_idx]
	var a := ang[start_idx]
	var g := Node3D.new()
	g.position = Vector3(sp.x, heights[start_idx], sp.y)
	g.rotation.y = a
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#2b3038")
	steel.metallic = 0.7
	steel.roughness = 0.4
	var span_x := half_w + 3.2
	for sx in [-span_x, span_x]:
		var pil := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.36
		cyl.height = 7.2
		cyl.material = steel
		pil.mesh = cyl
		pil.position = Vector3(sx, 3.6, 0)
		pil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(pil)
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(span_x * 2.0 + 1.0, 1.3, 1.6)
	box.material = steel
	beam.mesh = box
	beam.position = Vector3(0, 7.4, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(beam)

	var frame := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(span_x * 2.0 - 1.0, 2.1, 0.1)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color("#10141f")
	fbox.material = fmat
	frame.mesh = fbox
	frame.position = Vector3(0, 6.2, -0.12)
	g.add_child(frame)

	# 横幅文字（Label3D 替代 canvas 纹理，直接用系统中文字体）
	var banner := Label3D.new()
	banner.text = "REAL RACING · 极速争锋"
	banner.font = RRFont.get_font()
	banner.font_size = 150
	banner.pixel_size = 0.0075
	banner.modulate = Color("#ffffff")
	banner.outline_size = 0
	banner.double_sided = true
	banner.position = Vector3(0, 6.2, -0.05)
	banner.rotation.y = PI   # 正面朝向来车方向
	g.add_child(banner)

	_lamp_mats.clear()
	for k in range(-1, 2):
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color("#131313")
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.125, 0.125)
		lm.emission_energy_multiplier = 0.0
		var lamp := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.34
		sph.height = 0.68
		sph.material = lm
		lamp.mesh = sph
		lamp.position = Vector3(k * 1.5, 6.3, -0.2)
		g.add_child(lamp)
		_lamp_mats.append(lm)
	add_child(g)


## 信号灯：0 灭 / 1..3 红灯逐亮 / 4 绿灯起步
func set_lamp_stage(stage: int) -> void:
	for i in 3:
		var m := _lamp_mats[i]
		if stage >= 4:
			m.emission = Color(0.153, 0.851, 0.298)
			m.emission_energy_multiplier = 2.6
		else:
			m.emission = Color(1.0, 0.125, 0.125)
			m.emission_energy_multiplier = 2.4 if stage > i else 0.0


## 看台
func _build_stands() -> void:
	# 1 号看台：起跑线一侧（沿行进方向另一侧），正对起跑线
	var dir := Vector2(-tang[start_idx].y, tang[start_idx].x)   # right = tang × UP
	var p1 := pts[start_idx] - dir * (half_w + 12.5)
	add_child(_make_stand(p1, heights[start_idx],
			atan2(pts[start_idx].x - p1.x, pts[start_idx].y - p1.y)))
	# 2 号看台：发夹弯外侧
	var tightest := 0
	for i in n:
		if absf(curv[i]) > absf(curv[tightest]):
			tightest = i
	var idx2 := (tightest + 26) % n
	var dir2 := left_v[idx2]
	var p2 := pts[idx2] - dir2 * (half_w + 10.5)
	var alt := pts[idx2] + dir2 * (half_w + 10.5)
	var ref := Vector2(0, 30)
	if alt.distance_to(ref) < p2.distance_to(ref):
		p2 = alt
	add_child(_make_stand(p2, heights[idx2],
			atan2(pts[idx2].x - p2.x, pts[idx2].y - p2.y)))


func _make_stand(pos: Vector2, ground_y: float, rot_y: float) -> Node3D:
	var grp := Node3D.new()
	grp.position = Vector3(pos.x, ground_y, pos.y)
	grp.rotation.y = rot_y
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color("#b9b4ac")
	conc.roughness = 0.9
	# 三层阶梯
	for t in 3:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(44, 1.6 + t * 1.2, 3.4)
		bm.material = conc
		b.mesh = bm
		b.position = Vector3(0, (1.6 + t * 1.2) / 2.0, -t * 3.2)
		grp.add_child(b)
	# 观众墙（面向本地 +Z，即赛道方向）
	var cw := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(43.5, 6)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_texture = RRTextures.crowd()
	qmat.roughness = 1.0
	qm.material = qmat
	cw.mesh = qm
	cw.rotation.x = PI / 2   # PlaneMesh 朝 +Y，转半圈立起来朝 +Z
	cw.position = Vector3(0, 3.4, 1.73)
	grp.add_child(cw)
	# 顶棚
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(46, 0.5, 11)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("#d8dde2")
	rmat.metallic = 0.4
	rmat.roughness = 0.5
	rm.material = rmat
	roof.mesh = rm
	roof.position = Vector3(0, 8.6, -4.4)
	roof.rotation.x = 0.09
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	grp.add_child(roof)
	for px in [-21.0, 21.0]:
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.22
		pm.bottom_radius = 0.22
		pm.height = 8.4
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color("#777d84")
		pmat.metallic = 0.6
		pmat.roughness = 0.4
		pm.material = pmat
		pole.mesh = pm
		pole.position = Vector3(px, 4.2, -8.6)
		grp.add_child(pole)
	return grp
