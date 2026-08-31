class_name FreeroamMap
extends Node3D
## 自由漫游大地图：约 2.4km × 2.4km 的城市
## - 密集网格街道（11×11 → 约 120 个十字路口，红绿灯/斑马线）
## - 高架环线（10m）+ 两条高架快速路（14m）+ 8 条匝道（可驾驶爬升）
## - 约 800 栋楼宇（MultiMesh 实例）
## 查询接口鸭子类型兼容 RaceTrack（query/n/ds/start_idx/wall_lat），
## 额外返回 height（路面海拔）/ slope（沿切线坡度）/ wall（该路软墙限位），
## 多层立交按「车当前高度最接近」迟滞选择所在层。

const SAMPLE_DS := 1.5
const CELL := 40.0
const TENSION := 0.55
const MAP_LIMIT := 2800.0   # 漫游世界半径：城市核心 + 北山地 / 西海岸 / 东沙漠 / 南郊野

# 网格街道坐标（11 条 × 11 条 → 121 个十字路口）
const GRID_COORDS := [-900.0, -720.0, -540.0, -360.0, -180.0, 0.0, 180.0, 360.0, 540.0, 720.0, 900.0]
const GRID_HALF_W := 8.0
const RING_ELEV := 10.0
const CROSS_ELEV := 14.0
const STREET_Y_STEP := 0.08   # 相邻街错高步距：路口两层路面至少差半步，避免 z-fighting

var roads: Array[Road] = []
var n := 0                 # 采样总数（vehicle 进度计算用）
var ds := SAMPLE_DS
var start_idx := 0
var wall_lat := 9.0
var minimap_tex: ImageTexture
var vehicle_y := 0.0       # 由 game 每帧写入（高度选层迟滞用）

var _sig_mats: Array = []  # [{"r": mat, "y": mat, "g": mat}] × 2 组
var _block := {}           # 24m 网格：距任意道路中心线过近的建筑禁建区（预计算）

class Road:
	var pts := PackedVector3Array()       # 中心线（y = 路面海拔）
	var left := PackedVector2Array()      # 左向量 XZ
	var ang := PackedFloat32Array()
	var slope := PackedFloat32Array()     # dy/ds（沿切线）
	var half_w := 8.0
	var closed := false                   # 闭环（仅环线）；开放路不可首尾相连
	var elevated := false
	var wall := 10.0
	var grid := {}                        # Vector2i -> PackedInt32Array
	var rail_skip := []                  # 护栏修剪掩码（并线段，i -> bool）
	var surf_skip := []                  # 路面修剪掩码（与同层路面共面重叠段，如高架十字交叉）


func _init() -> void:
	name = "FreeroamMap"
	visible = false


# ============================================================
#  路网数据
# ============================================================

func build() -> void:
	var t0 := Time.get_ticks_msec()
	_make_grid_roads()
	_make_ring()
	_make_cross_highways()
	_make_ramps()
	_make_outskirts_roads()
	print("[map] 路网采样 %d 点 %dms" % [n, Time.get_ticks_msec() - t0])
	_mark_road_blocks()
	_build_road_meshes()
	print("[map] 路面网格 %dms" % [Time.get_ticks_msec() - t0])
	_build_zones()
	print("[map] 区域场景 %dms" % [Time.get_ticks_msec() - t0])
	_build_intersections()
	print("[map] 路口 %dms" % [Time.get_ticks_msec() - t0])
	_place_buildings()
	print("[map] 建筑 %dms" % [Time.get_ticks_msec() - t0])
	_build_minimap()
	print("[map] 完成 %dms" % [Time.get_ticks_msec() - t0])


func _make_road(cps: Array, ys: Array, closed: bool, half_w: float, elevated: bool) -> Road:
	var road := Road.new()
	road.half_w = half_w
	road.closed = closed
	road.elevated = elevated
	road.wall = (half_w + 0.15) if elevated else (half_w + 2.6)
	var m := cps.size()

	# 密集采样（闭式 / 开式 Catmull-Rom，与 race_track 同一套公式）
	var dense := PackedVector2Array()
	if m == 2:
		dense.append(cps[0])
		dense.append(cps[1])
	else:
		var seg_count := m if closed else m - 1
		dense.resize(seg_count * 20)
		for i in seg_count:
			var i0 := (i - 1 + m) % m if closed else maxi(i - 1, 0)
			var i3 := (i + 2) % m if closed else mini(i + 2, m - 1)
			var p0: Vector2 = cps[i0]
			var p1: Vector2 = cps[i]
			var p2: Vector2 = cps[(i + 1) % m]
			var p3: Vector2 = cps[i3]
			var v0 := (p2 - p0) * TENSION
			var v1 := (p3 - p1) * TENSION
			for k in 20:
				var t := float(k) / 20.0
				var t2 := t * t
				var t3 := t2 * t
				dense[i * 20 + k] = (
					(2.0 * p1 - 2.0 * p2 + v0 + v1) * t3
					+ (3.0 * p2 - 3.0 * p1 - 2.0 * v0 - v1) * t2
					+ v0 * t + p1)
		if not closed:
			dense.append(cps[m - 1])   # 开放曲线必须精确落在末端控制点（匝道接驳）

	# 弧长均匀重采样
	var seg_total := dense.size() if closed else dense.size() - 1
	var total := 0.0
	for i in seg_total:
		total += dense[i].distance_to(dense[(i + 1) % dense.size()])
	var cnt := maxi(roundi(total / SAMPLE_DS), 2)
	road.pts.resize(cnt)
	road.left.resize(cnt)
	road.ang.resize(cnt)
	road.slope.resize(cnt)
	var j := 0
	var seg_start := 0.0
	var seg_end: float = dense[0].distance_to(dense[1 % dense.size()])
	for i in cnt:
		var target := total * float(i) / float(cnt - 1) if not closed else total * float(i) / float(cnt)
		while seg_end < target and j < seg_total - 1:
			j += 1
			seg_start = seg_end
			seg_end = seg_start + dense[j].distance_to(dense[(j + 1) % dense.size()])
		var seg_len := maxf(seg_end - seg_start, 1e-6)
		var f := clampf((target - seg_start) / seg_len, 0.0, 1.0)
		var pt := dense[j].lerp(dense[(j + 1) % dense.size()], f)

		# 海拔：闭环取常值；开放路按控制点参数分段线性插值
		var y: float
		if closed or ys.size() == 1:
			y = ys[0]
		else:
			var t_frac := float(i) / float(cnt - 1)
			var cf := t_frac * float(ys.size() - 1)
			var ci := mini(int(cf), ys.size() - 2)
			y = lerpf(ys[ci], ys[ci + 1], clampf(cf - float(ci), 0.0, 1.0))
		road.pts[i] = Vector3(pt.x, y, pt.y)

	for i in cnt:
		# 开放路末点沿用前一段切线：回卷取 pts[0] 会让末点朝向反转 180°
		var ia: int = i if (closed or i < cnt - 1) else i - 1
		var a := road.pts[ia]
		var b := road.pts[(ia + 1) % cnt]
		var tv := Vector2(b.x - a.x, b.z - a.z).normalized()
		road.ang[i] = atan2(tv.x, tv.y)
		road.left[i] = Vector2(tv.y, -tv.x)
	for i in cnt:
		var y0: float = road.pts[(i - 1 + cnt) % cnt].y if closed else road.pts[maxi(i - 1, 0)].y
		var y2: float = road.pts[(i + 1) % cnt].y if closed else road.pts[mini(i + 1, cnt - 1)].y
		road.slope[i] = clampf((y2 - y0) / (2.0 * SAMPLE_DS), -0.5, 0.5)

	# 空间网格
	for i in range(0, cnt, 2):
		var key := Vector2i(int(road.pts[i].x / CELL), int(road.pts[i].z / CELL))
		if not road.grid.has(key):
			road.grid[key] = PackedInt32Array()
		road.grid[key].append(i)

	roads.append(road)
	n += cnt
	return road


## 每条街独立高度（垂直街 k：0.03+k·STEP；水平街再错半步）。
## 22 条街两两不等高：原来 k%3 只有 3 档，121 个路口里 41 个两层路面完全共面，
## 深度冲突让路面虚线持续狂闪；其余路口 0.012m 错高也只够撑到 ~250m 外。
func _street_h(k: int, horizontal: bool) -> float:
	return 0.03 + (float(k) + (0.5 if horizontal else 0.0)) * STREET_Y_STEP


func _make_grid_roads() -> void:
	for k in GRID_COORDS.size():
		var c: float = GRID_COORDS[k]
		_make_road([Vector2(c, -900.0), Vector2(c, 900.0)],
				[_street_h(k, false)], false, GRID_HALF_W, false)
		_make_road([Vector2(-900.0, c), Vector2(900.0, c)],
				[_street_h(k, true)], false, GRID_HALF_W, false)


func _make_ring() -> void:
	var s := 700.0
	var c := 150.0
	var cps := [
		Vector2(-s + c, -s), Vector2(s - c, -s), Vector2(s, -s + c),
		Vector2(s, s - c), Vector2(s - c, s), Vector2(-s + c, s),
		Vector2(-s, s - c), Vector2(-s, -s + c),
	]
	_make_road(cps, [RING_ELEV], true, 10.0, true)


func _make_cross_highways() -> void:
	# 东西 / 南北高架快速路（与环线立交：14m vs 10m）
	_make_road([Vector2(-900.0, 0.0), Vector2(900.0, 0.0)], [CROSS_ELEV], false, 10.0, true)
	_make_road([Vector2(0.0, -900.0), Vector2(0.0, 900.0)], [CROSS_ELEV], false, 10.0, true)


func _make_ramps() -> void:
	var ring := roads[22]   # 网格 22 条之后紧接环线
	var rn := ring.pts.size()
	# 4 条环线匝道：东北/西北/东南/西南
	for d in [[1.0, 1.0], [-1.0, 1.0], [1.0, -1.0], [-1.0, -1.0]]:
		# 找到该对角方向上最接近 45° 的环线采样
		var bi := 0
		var best := -1e9
		for i in range(0, rn, 4):
			var p := ring.pts[i]
			var dot := (signf(d[0]) * p.x + signf(d[1]) * p.z) \
					/ maxf(Vector2(p.x, p.z).length(), 1.0)
			if dot > best:
				best = dot
				bi = i
		var rp := ring.pts[bi]
		var rtan := Vector2(sin(ring.ang[bi]), cos(ring.ang[bi]))
		var outward := Vector2(rp.x, rp.z).normalized()   # 径向单位向量（注意 rp.y 是高度）
		# 地面端：就近的网格街道交点（内圈 540），入口沿街道后退 30m 保证精确接驳
		var g := Vector2(signf(d[0]) * 540.0, signf(d[1]) * 540.0)
		var on_x := absf(rp.x) > absf(rp.y)   # 退沿 X → 匝道口贴水平街
		# 入口段抬高 0.20：匝道贴着街面起步，不叠面（叠面会深度打架闪烁）
		var g_y := _street_h(8, on_x) + 0.20
		var crown_y := maxf(_street_h(8, false), _street_h(8, true)) + 0.20
		var street_back := Vector2(-signf(d[0]), 0.0) if absf(rp.x) > absf(rp.y) \
				else Vector2(0.0, -signf(d[1]))
		# 并线尾段：沿环线外侧平行（径向偏 16.5 = 环半宽10 + 0.5缝 + 匝道半宽6），
		# 边对边衔接不叠面 —— 原来尾段压在环线中心线上，两条虚线深度冲突狂闪
		var merge_c := Vector2(rp.x, rp.y) + outward * 16.5
		var cps := [
			g + street_back * 30.0,
			g,
			g.lerp(Vector2(rp.x, rp.y), 0.55) + outward * 26.0,
			Vector2(rp.x, rp.y) - rtan * 80.0 + outward * 20.0,
			merge_c - rtan * 30.0,
			merge_c + rtan * 10.0,
		]
		_make_road(cps, [g_y, crown_y, 5.0, 8.5, RING_ELEV, RING_ELEV],
				false, 6.0, true)
	# 4 条快速路匝道（东西向 2 条 + 南北向 2 条）
	for sx in [-1.0, 1.0]:
		var hx: float = 560.0 * sx
		# 起点与主线边对边（主线南侧 10.5m = 半宽10 + 0.5缝），不叠面
		_make_road([
			Vector2(hx - 150.0 * sx, -10.5), Vector2(hx - 40.0 * sx, -10.5),
			Vector2(hx + 60.0 * sx, -16.0), Vector2(hx + 150.0 * sx, -170.0),
			Vector2(hx + 150.0 * sx, -320.0),
		], [CROSS_ELEV, CROSS_ELEV, 10.0, 1.5, 0.03], false, 6.0, true)
	for sz in [-1.0, 1.0]:
		var hz: float = 560.0 * sz
		# 起点与主线边对边（主线东侧 10.5m = 半宽10 + 0.5缝），不叠面
		_make_road([
			Vector2(10.5, hz - 150.0 * sz), Vector2(10.5, hz - 40.0 * sz),
			Vector2(16.0, hz + 60.0 * sz), Vector2(170.0, hz + 150.0 * sz),
			Vector2(320.0, hz + 150.0 * sz),
		], [CROSS_ELEV, CROSS_ELEV, 10.0, 1.5, 0.03], false, 6.0, true)


## 城市外的四大区域路网：北盘山 / 西海岸 / 东沙漠 / 南郊野
func _make_outskirts_roads() -> void:
	# ---- 北：盘山公路（发夹爬升至 72m 山顶脊线，另一侧俯冲回城市东北角）----
	_make_road([
		Vector2(0, -900), Vector2(30, -1080), Vector2(-70, -1260), Vector2(90, -1400),
		Vector2(-90, -1560), Vector2(130, -1700), Vector2(-40, -1860), Vector2(-180, -2000),
		Vector2(-60, -2140), Vector2(120, -2240), Vector2(300, -2300), Vector2(470, -2320),
		Vector2(640, -2280), Vector2(790, -2180), Vector2(850, -2000), Vector2(790, -1820),
		Vector2(880, -1660), Vector2(830, -1500), Vector2(920, -1340), Vector2(870, -1180),
		Vector2(900, -1020), Vector2(900, -900),
	], [0.1, 1.5, 5.0, 10.0, 16.0, 23.0, 30.0, 38.0, 47.0, 56.0, 65.0, 72.0,
		70.0, 60.0, 48.0, 38.0, 28.0, 19.0, 11.0, 5.0, 1.0, 0.1], false, 7.0, false)

	# ---- 西：海岸大道（西侧是海）+ 城市联络线 ----
	_make_road([
		Vector2(-1040, -1150), Vector2(-1020, -800), Vector2(-1060, -400),
		Vector2(-1020, 0), Vector2(-1060, 400), Vector2(-1020, 800), Vector2(-1040, 1150),
	], [0.03], false, 8.0, false)
	_make_road([Vector2(-900, -540), Vector2(-1020, -540)], [0.03], false, 6.0, false)
	_make_road([Vector2(-900, 540), Vector2(-1020, 540)], [0.03], false, 6.0, false)
	_make_road([Vector2(-1040, -1150), Vector2(-880, -1150), Vector2(-300, -1140),
			Vector2(0, -1010), Vector2(0, -900)], [0.03], false, 6.0, false)
	_make_road([Vector2(-1040, 1150), Vector2(-880, 1150), Vector2(-300, 1140),
			Vector2(-150, 1020), Vector2(-150, 900)], [0.03], false, 6.0, false)

	# ---- 东：沙漠环线（沙丘缓起伏，峰谷 3~9m）----
	_make_road([
		Vector2(900, -540), Vector2(1150, -560), Vector2(1450, -460),
		Vector2(1800, -560), Vector2(2100, -420), Vector2(2350, -150),
		Vector2(2400, 150), Vector2(2250, 480), Vector2(1950, 560), Vector2(1650, 460),
		Vector2(1350, 560), Vector2(1100, 480), Vector2(900, 540),
	], [0.03, 2.0, 5.0, 3.0, 7.0, 4.0, 8.0, 5.0, 9.0, 4.0, 7.0, 3.0, 0.03], false, 8.0, false)

	# ---- 南：郊野线 ----
	_make_road([Vector2(0, 900), Vector2(0, 1150), Vector2(-120, 1400),
			Vector2(-80, 1700), Vector2(120, 1900), Vector2(400, 2000)],
			[0.03], false, 7.0, false)
	_make_road([Vector2(-540, 900), Vector2(-540, 1250), Vector2(-420, 1500)],
			[0.03], false, 6.0, false)


## 出生点：x=180 的南北向街道，朝 +Z（北）
func get_spawn() -> Dictionary:
	return {"pos": Vector3(180.0, _street_h(6, false), -540.0), "heading": 0.0}


## 复位到最近道路中心
func query_rescue(x: float, z: float) -> Dictionary:
	vehicle_y = 0.0   # 复位优先回到地面层
	var q := query(x, z, null)
	var p := _global_pt(q["idx"])
	return {"pos": Vector3(p.x, p.y + 0.2, p.z), "ang": q["ang"]}


func _global_pt(gidx: int) -> Vector3:
	var r := gidx / 100000
	var i := gidx % 100000
	if r < 0 or r >= roads.size() or i >= roads[r].pts.size():
		return Vector3.ZERO
	return roads[r].pts[i]


# ============================================================
#  查询（鸭子类型兼容 RaceTrack）
# ============================================================

var _scratch := {"idx": 0, "lat_off": 0.0, "ang": 0.0, "surf": "road", "dist_sq": 0.0,
		"height": 0.0, "slope": 0.0, "wall": 9.0, "road": 0}


func query(x: float, z: float, hint) -> Dictionary:
	var hint_road := -1
	var hint_i := -1
	if hint != null:
		hint_road = int(hint) / 100000
		hint_i = int(hint) % 100000
	var best_road := -1
	var best_i := 0
	var best_cost := INF
	var best_d2 := INF
	var road_cost := {}          # 每条候选路的代价（用于重叠区域取最宽软墙）
	for r in roads.size():
		var road := roads[r]
		var bi := -1
		var bd2 := INF
		if r == hint_road and hint_i >= 0 and hint_i < road.pts.size():
			for o in range(-30, 31):
				var i := posmod(hint_i + o, road.pts.size())
				var dx := road.pts[i].x - x
				var dz := road.pts[i].z - z
				var d2 := dx * dx + dz * dz
				if d2 < bd2:
					bd2 = d2
					bi = i
		else:
			var rr := int(ceil((road.half_w + 14.0) / CELL))
			var gx := int(x / CELL)
			var gz := int(z / CELL)
			for cxi in range(gx - rr, gx + rr + 1):
				for czi in range(gz - rr, gz + rr + 1):
					var key := Vector2i(cxi, czi)
					if not road.grid.has(key):
						continue
					for i in road.grid[key]:
						var dx := road.pts[i].x - x
						var dz := road.pts[i].z - z
						var d2 := dx * dx + dz * dz
						if d2 < bd2:
							bd2 = d2
							bi = i
		if bi < 0:
			continue
		var cost := sqrt(bd2) + absf(road.pts[bi].y - vehicle_y) * 6.0   # 高度迟滞
		if r == hint_road:
			cost -= 2.0   # 当前路粘性，避免并线/重叠处来回跳层
		road_cost[r] = cost
		if cost < best_cost:
			best_cost = cost
			best_road = r
			best_i = bi
			best_d2 = bd2

	if best_road < 0 or best_d2 > pow(roads[best_road].half_w + 16.0, 2.0):
		# 路网外：草地
		_scratch["idx"] = 0
		_scratch["lat_off"] = 999.0
		_scratch["surf"] = "grass"
		_scratch["height"] = 0.0
		_scratch["slope"] = 0.0
		_scratch["wall"] = 10000.0
		_scratch["dist_sq"] = best_d2
		return _scratch

	# 重叠路段（匝道口/并线段/路口）取相近候选中最宽的软墙，消除隐形墙
	var wall := roads[best_road].wall
	for r in road_cost:
		if r == best_road:
			continue
		if road_cost[r] < best_cost + 4.0:
			wall = maxf(wall, roads[r].wall)

	var road := roads[best_road]
	var p := road.pts[best_i]
	var l := road.left[best_i]
	var lat := (x - p.x) * l.x + (z - p.z) * l.y
	var al := absf(lat)
	_scratch["idx"] = best_road * 100000 + best_i
	_scratch["road"] = best_road
	_scratch["lat_off"] = lat
	_scratch["ang"] = road.ang[best_i]
	_scratch["height"] = p.y
	_scratch["slope"] = road.slope[best_i]
	_scratch["wall"] = wall
	_scratch["surf"] = "grass" if al > road.half_w + 1.2 \
			else ("curb" if al > road.half_w else "road")
	return _scratch


func is_clear_of_roads(x: float, z: float, clearance: float) -> bool:
	for road in roads:
		var rr := int(ceil((road.half_w + clearance) / CELL))
		var gx := int(x / CELL)
		var gz := int(z / CELL)
		for cxi in range(gx - rr, gx + rr + 1):
			for czi in range(gz - rr, gz + rr + 1):
				var key := Vector2i(cxi, czi)
				if not road.grid.has(key):
					continue
				for i in road.grid[key]:
					var dx := road.pts[i].x - x
					var dz := road.pts[i].z - z
					if dx * dx + dz * dz < clearance * clearance:
						return false
	return true


func update_signals(t: float) -> void:
	if _sig_mats.is_empty():
		return
	var cycle := fmod(t, 15.0)
	for g in 2:
		var local := fmod(cycle + 7.5 * float(g), 15.0)
		var green := local < 6.5
		var yellow := local >= 6.5 and local < 8.0
		var m: Dictionary = _sig_mats[g]
		(m["r"] as StandardMaterial3D).emission_energy_multiplier = 2.4 if (not green and not yellow) else 0.12
		(m["y"] as StandardMaterial3D).emission_energy_multiplier = 2.4 if yellow else 0.12
		(m["g"] as StandardMaterial3D).emission_energy_multiplier = 2.4 if green else 0.12


# ============================================================
#  网格生成
# ============================================================

var _v_pos := PackedVector3Array()
var _v_nrm := PackedVector3Array()
var _v_col := PackedColorArray()
var _v_uv := PackedVector2Array()


## 追加一个双三角四边形（Godot 正面为顺时针绕向：a,c,b / a,d,c）。
## 直写 Packed 数组、不经过中间容器 —— 本文件要生成数十万顶点，性能敏感
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color,
		uv_a := Vector2.ZERO, uv_b := Vector2.ZERO, uv_c := Vector2.ZERO, uv_d := Vector2.ZERO) -> void:
	_v_pos.append(a)
	_v_pos.append(c)
	_v_pos.append(b)
	_v_pos.append(a)
	_v_pos.append(d)
	_v_pos.append(c)
	for i in 6:
		_v_nrm.append(nrm)
		_v_col.append(col)
	_v_uv.append(uv_a)
	_v_uv.append(uv_c)
	_v_uv.append(uv_b)
	_v_uv.append(uv_a)
	_v_uv.append(uv_d)
	_v_uv.append(uv_c)


func _flush(mat: Material, cast_shadow := false) -> void:
	if _v_pos.is_empty():
		return
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


## 预计算护栏修剪掩码：高架采样点若与「同层」的其它高架路面过近
## （匝道并入主线段），该段不建护栏 —— 避免护栏横穿桥面
func _mark_rail_skips() -> void:
	for road in roads:
		if not road.elevated:
			continue
		road.rail_skip.resize(road.pts.size())
		for i in road.pts.size():
			var skip := false
			var p := road.pts[i]
			for other in roads:
				if other == road or not other.elevated:
					continue
				var gap: float = road.half_w + other.half_w + 0.8
				var rr := int(ceil(gap / CELL)) + 1
				var gx := int(p.x / CELL)
				var gz := int(p.z / CELL)
				for cxi in range(gx - rr, gx + rr + 1):
					var done := false
					for czi in range(gz - rr, gz + rr + 1):
						var key := Vector2i(cxi, czi)
						if not other.grid.has(key):
							continue
						for j in other.grid[key]:
							var q := other.pts[j]
							var dxz := Vector2(q.x - p.x, q.z - p.z).length()
							if dxz < gap and absf(q.y - p.y) < 2.5:
								skip = true
								done = true
								break
						if done:
							break
				road.rail_skip[i] = skip


## 预计算路面裁剪掩码：与「同层」路面共面重叠的采样段跳过路面四边形
## （如两条高架十字交叉：交叉块由主路面覆盖，副路虚线止于边缘，不再深度打架）
func _mark_surf_skips() -> void:
	for ri in roads.size():
		var road: Road = roads[ri]
		if not road.elevated:
			continue
		road.surf_skip.resize(road.pts.size())
		for i in road.pts.size():
			var skip := false
			var p: Vector3 = road.pts[i]
			for oi in roads.size():
				var other: Road = roads[oi]
				if oi == ri or not other.elevated:
					continue
				# 等宽路口（如两高架十字交叉）双方都在对方面内：只裁索引大的一方，
				# 否则两边都裁会出洞；窄路并入宽路时自然只裁窄路
				var wider: bool = other.half_w > road.half_w \
						or (absf(other.half_w - road.half_w) < 0.01 and oi < ri)
				if not wider:
					continue
				var gap: float = other.half_w - 1.0
				if gap <= 0.0:
					continue
				var rr := int(ceil(gap / CELL)) + 1
				var gx := int(p.x / CELL)
				var gz := int(p.z / CELL)
				for cxi in range(gx - rr, gx + rr + 1):
					var done := false
					for czi in range(gz - rr, gz + rr + 1):
						var key := Vector2i(cxi, czi)
						if not other.grid.has(key):
							continue
						for j in other.grid[key]:
							var q := other.pts[j]
							var dxz := Vector2(q.x - p.x, q.z - p.z).length()
							if dxz < gap and absf(q.y - p.y) < 0.1:
								skip = true
								done = true
								break
						if done:
							break
					if done:
						break
			road.surf_skip[i] = skip


func _build_road_meshes() -> void:
	_mark_rail_skips()
	_mark_surf_skips()
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_texture = RRTextures.asphalt()
	road_mat.roughness = 0.92
	road_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var walk_mat := StandardMaterial3D.new()
	walk_mat.albedo_color = Color("#787e88")
	walk_mat.roughness = 0.9
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color("#c9ced4")
	rail_mat.metallic = 0.0
	rail_mat.roughness = 0.85
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for road in roads:
		var cnt := road.pts.size()
		var rep := maxf(1.0, roundf(cnt * SAMPLE_DS / 16.0))
		# 开放路只到 cnt-1：原来 (i+1)%cnt 会把末点接回起点，
		# 多铺一条与整条街完全共面的整长路面 —— 深度打架，虚线狂闪
		for i in (cnt if road.closed else cnt - 1):
			var j := (i + 1) % cnt
			var pi := road.pts[i]
			var pj := road.pts[j]
			var li := road.left[i]
			var lj := road.left[j]
			var w := road.half_w
			var u0 := float(i) / float(cnt) * rep
			var u1 := float(i + 1) / float(cnt) * rep
			# 主路面（同层共面重叠段跳过：由覆盖路面的沥青接管，如高架十字交叉）
			if road.surf_skip.size() != cnt or not (road.surf_skip[i] or road.surf_skip[j]):
				_quad(
					pi + Vector3(-li.x * w, 0, -li.y * w),
					pj + Vector3(-lj.x * w, 0, -lj.y * w),
					pj + Vector3(lj.x * w, 0, lj.y * w),
					pi + Vector3(li.x * w, 0, li.y * w),
					Vector3.UP, Color.WHITE,
					Vector2(0, u0), Vector2(0, u1), Vector2(1, u1), Vector2(1, u0))
			if not road.elevated:
				# 路缘人行道（略高于路面）
				for side in [-1.0, 1.0]:
					var a := pi + Vector3(li.x * side * (w + 0.06), 0.05, li.y * side * (w + 0.06))
					var b := pj + Vector3(lj.x * side * (w + 0.06), 0.05, lj.y * side * (w + 0.06))
					var c := pj + Vector3(lj.x * side * (w + 2.2), 0.05, lj.y * side * (w + 2.2))
					var d := pi + Vector3(li.x * side * (w + 2.2), 0.05, li.y * side * (w + 2.2))
					_quad(a, b, c, d, Vector3.UP, Color.WHITE)
			else:
				# 高架防撞墙：0.55m 高实体墙（内壁 + 顶面 + 外壁），哑光混凝土
				for side in [-1.0, 1.0]:
					if road.rail_skip[i] or road.rail_skip[j]:
						continue   # 并入主线段：不建墙，避免护栏横穿桥面
					var oi: float = (w + 0.10) * side
					var oo: float = (w + 0.45) * side
					var a := pi + Vector3(li.x * oi, 0.05, li.y * oi)
					var b := pj + Vector3(lj.x * oi, 0.05, lj.y * oi)
					var a2 := pi + Vector3(li.x * oo, 0.05, li.y * oo)
					var b2 := pj + Vector3(lj.x * oo, 0.05, lj.y * oo)
					var ai := a + Vector3(0, 0.55, 0)
					var bi := b + Vector3(0, 0.55, 0)
					var ao := a2 + Vector3(0, 0.55, 0)
					var bo := b2 + Vector3(0, 0.55, 0)
					var n_in := Vector3(-li.x * side, 0, -li.y * side)
					var n_out := Vector3(li.x * side, 0, li.y * side)
					_quad(a, b, bi, ai, n_in, rail_mat.albedo_color)
					_quad(a2, b2, bo, ao, n_out, rail_mat.albedo_color)
					_quad(ai, bi, bo, ao, Vector3.UP, rail_mat.albedo_color)
	_flush(road_mat)
	_flush(walk_mat)
	_flush(rail_mat)

	# 高架桥墩（每 ~45m 一根，从地面顶到桥面）
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 1.1
	pillar_mesh.bottom_radius = 1.5
	pillar_mesh.height = 1.0
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color("#8f959c")
	pillar_mat.roughness = 0.85
	pillar_mesh.material = pillar_mat
	var pillar_list: Array[Transform3D] = []
	for road in roads:
		if not road.elevated:
			continue
		var cnt := road.pts.size()
		var step := maxi(1, roundi(45.0 / SAMPLE_DS))
		for i in range(0, cnt, step):
			var p := road.pts[i]
			if p.y < 1.5:
				continue
			pillar_list.append(Transform3D(
					Basis.from_scale(Vector3(1, p.y, 1)), Vector3(p.x, p.y / 2.0, p.z)))
	if not pillar_list.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pillar_mesh
		mm.instance_count = pillar_list.size()
		for i in pillar_list.size():
			mm.set_instance_transform(i, pillar_list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


## 四大区域地面与景观：顶点色大网格（城市/草地/沙漠/山地/沙滩同一层，无深度冲突）
func _build_zones() -> void:
	_build_zone_ground()
	# 海面（独立光泽层，驶入即浅水漫过轮组）
	var ocean := StandardMaterial3D.new()
	ocean.albedo_color = Color(0.1, 0.33, 0.56)
	ocean.metallic = 0.35
	ocean.roughness = 0.12
	_ground_plane(3520, 9600, null, Color.WHITE, 1.0, Vector2(-2840, 0.02), 0.02, ocean)
	_mountains()
	_desert_props()


## 单张大网格地面：顶点按世界坐标着色分区（城市灰/草地绿/沙漠黄/山地深绿/沙滩米）
func _build_zone_ground() -> void:
	# 分块生成：GL Compatibility 下非索引网格会被转 16 位索引绘制，
	# 单 mesh 超 65536 顶点的部分静默丢失 —— 每块独立成 mesh 规避
	# EXT 覆盖到雾距之外（玩家最远 ±2800 + 雾 6500）：地面尽头不可见，
	# 否则地面外露出天空球下半球的灰白带（"天变灰"的来源）
	const EXT := 8000.0
	const CELLS := 320
	const BLOCK := 16
	var cell := EXT * 2.0 / CELLS
	var rng := RRUtil.Mulberry.new(4242)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for bz in CELLS / BLOCK:
		for bx in CELLS / BLOCK:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for iz in BLOCK:
				for ix in BLOCK:
					var gx: int = bx * BLOCK + ix
					var gz: int = bz * BLOCK + iz
					var x0 := -EXT + gx * cell
					var z0 := -EXT + gz * cell
					var c00 := _zone_color(x0, z0, rng)
					var c10 := _zone_color(x0 + cell, z0, rng)
					var c01 := _zone_color(x0, z0 + cell, rng)
					var c11 := _zone_color(x0 + cell, z0 + cell, rng)
					var p00 := Vector3(x0, 0, z0)
					var p10 := Vector3(x0 + cell, 0, z0)
					var p01 := Vector3(x0, 0, z0 + cell)
					var p11 := Vector3(x0 + cell, 0, z0 + cell)
					for tri in [[p00, c00, p10, c10, p11, c11], [p00, c00, p11, c11, p01, c01]]:
						st.set_normal(Vector3.UP)
						st.set_color(tri[1])
						st.add_vertex(tri[0])
						st.set_normal(Vector3.UP)
						st.set_color(tri[3])
						st.add_vertex(tri[2])
						st.set_normal(Vector3.UP)
						st.set_color(tri[5])
						st.add_vertex(tri[4])
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)


## 区域配色：海 / 沙滩 / 沙漠 / 山地 / 城市水泥 / 草地（+ 噪声抖动）
func _zone_color(x: float, z: float, rng: RRUtil.Mulberry) -> Color:
	var n := (rng.next() - 0.5) * 0.06
	var c: Color
	if x < -1080.0:
		c = Color(0.10, 0.33, 0.56)      # 海
	elif x < -980.0:
		c = Color(0.85, 0.78, 0.60)      # 沙滩
	elif x > 950.0:
		c = Color(0.80, 0.68, 0.44)      # 沙漠
	elif z < -1080.0:
		c = Color(0.28, 0.40, 0.26)      # 山地
	elif absf(x) < 950.0 and absf(z) < 950.0:
		c = Color(0.44, 0.46, 0.49)      # 城市水泥（中灰防过曝）
	else:
		c = Color(0.42, 0.55, 0.33)      # 草地
	return Color(clampf(c.r + n, 0, 1), clampf(c.g + n, 0, 1), clampf(c.b + n, 0, 1))


## 区域地面平面（y 为绝对高度；at 为平面中心 XZ）
## 区域地面平面（y 为绝对高度；at 为平面中心 XZ）
func _ground_plane(sx: float, sz: float, tex: Texture2D, tint: Color, uv_scale: float,
		at: Vector2, y := 0.004, mat: Material = null) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(sx, sz)
	var m: Material
	if mat != null:
		m = mat
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = tex
		sm.albedo_color = tint
		sm.roughness = 1.0
		sm.uv1_scale = Vector3(uv_scale, uv_scale, 1)
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = sm
	plane.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(at.x, y, at.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## 北山地雪峰群：灰色锥体 + 白色雪顶（避开所有道路）
func _mountains() -> void:
	var rng := RRUtil.Mulberry.new(777)
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.001
	body_mesh.bottom_radius = 1.0
	body_mesh.height = 1.0
	body_mesh.radial_segments = 9
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.42, 0.44, 0.47)
	body_mat.roughness = 1.0
	body_mesh.material = body_mat
	var snow_mesh := CylinderMesh.new()
	snow_mesh.top_radius = 0.001
	snow_mesh.bottom_radius = 1.0
	snow_mesh.height = 1.0
	snow_mesh.radial_segments = 9
	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.93, 0.95, 0.97)
	snow_mat.roughness = 0.9
	snow_mesh.material = snow_mat

	var bodies: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	var placed := 0
	var guard := 0
	while placed < 14 and guard < 500:
		guard += 1
		var x := -1700.0 + rng.next() * 3500.0
		var z := -1250.0 - rng.next() * 1450.0
		var radius := 150.0 + rng.next() * 170.0
		if not is_clear_of_roads(x, z, radius + 100.0):
			continue
		var h := radius * (0.5 + rng.next() * 0.4)
		bodies.append(Transform3D(Basis.from_scale(Vector3(radius, h, radius)),
				Vector3(x, h * 0.5, z)))
		var sh := h * 0.3
		caps.append(Transform3D(Basis.from_scale(Vector3(radius * 0.4, sh, radius * 0.4)),
				Vector3(x, h * 0.85 + sh * 0.5, z)))
		placed += 1
	for pack in [[body_mesh, bodies], [snow_mesh, caps]]:
		if pack[1].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pack[0]
		mm.instance_count = pack[1].size()
		for i in pack[1].size():
			mm.set_instance_transform(i, pack[1][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)


## 东沙漠道具：仙人掌群 + 红岩平顶山（避开道路）
func _desert_props() -> void:
	var rng := RRUtil.Mulberry.new(888)
	var cac_mat := StandardMaterial3D.new()
	cac_mat.albedo_color = Color(0.32, 0.5, 0.24)
	cac_mat.roughness = 0.9
	var cactus_geos: Array[CylinderMesh] = []
	var cactus_locals: Array[Transform3D] = []
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.38
	trunk.height = 2.8
	trunk.radial_segments = 8
	trunk.material = cac_mat
	cactus_geos.append(trunk)
	cactus_locals.append(Transform3D(Basis(), Vector3(0, 1.4, 0)))
	var a1 := CylinderMesh.new()
	a1.top_radius = 0.18
	a1.bottom_radius = 0.2
	a1.height = 1.2
	a1.radial_segments = 7
	a1.material = cac_mat
	cactus_geos.append(a1)
	cactus_locals.append(Transform3D(Basis(Quaternion(Vector3(0, 0, 1), 0.9)), Vector3(0.55, 2.05, 0)))
	var a2 := CylinderMesh.new()
	a2.top_radius = 0.18
	a2.bottom_radius = 0.2
	a2.height = 1.0
	a2.radial_segments = 7
	a2.material = cac_mat
	cactus_geos.append(a2)
	cactus_locals.append(Transform3D(Basis(Quaternion(Vector3(0, 0, 1), -1.1)), Vector3(-0.5, 2.35, 0)))

	var cacti_mms: Array[MultiMesh] = []
	for gi in cactus_geos.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cactus_geos[gi]
		mm.instance_count = 90
		cacti_mms.append(mm)
	var cac_placed := 0
	var cac_guard := 0
	while cac_placed < 90 and cac_guard < 900:
		cac_guard += 1
		var x := 1150.0 + rng.next() * 1550.0
		var z := -1900.0 + rng.next() * 3800.0
		if not is_clear_of_roads(x, z, 14.0):
			continue
		var sc := 0.8 + rng.next() * 1.2
		var base := Transform3D(
				Basis(Quaternion(Vector3.UP, rng.next() * 6.28)).scaled(
						Vector3(sc, sc * (0.85 + rng.next() * 0.5), sc)),
				Vector3(x, 0, z))
		for gi in cacti_mms.size():
			cacti_mms[gi].set_instance_transform(cac_placed, base * cactus_locals[gi])
		cac_placed += 1
	for gi in cacti_mms.size():
		cacti_mms[gi].visible_instance_count = cac_placed
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = cacti_mms[gi]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)

	# 红岩平顶山
	var mesa_mat := StandardMaterial3D.new()
	mesa_mat.albedo_color = Color(0.69, 0.44, 0.28)
	mesa_mat.roughness = 1.0
	var mesa_geo := CylinderMesh.new()
	mesa_geo.top_radius = 0.62
	mesa_geo.bottom_radius = 1.0
	mesa_geo.height = 1.0
	mesa_geo.radial_segments = 8
	mesa_geo.material = mesa_mat
	var mesas: Array[Transform3D] = []
	var mesa_guard := 0
	while mesas.size() < 8 and mesa_guard < 200:
		mesa_guard += 1
		var x := 1350.0 + rng.next() * 1250.0
		var z := -1600.0 + rng.next() * 3200.0
		if not is_clear_of_roads(x, z, 170.0):
			continue
		var h := 38.0 + rng.next() * 50.0
		mesas.append(Transform3D(
				Basis(Quaternion(Vector3.UP, rng.next() * 3.0)).scaled(
						Vector3(110.0 + rng.next() * 120.0, h, 110.0 + rng.next() * 120.0)),
				Vector3(x, h * 0.42, z)))
	if not mesas.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesa_geo
		mm.instance_count = mesas.size()
		for i in mesas.size():
			mm.set_instance_transform(i, mesas[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)


## 十字路口：斑马线 + 红绿灯
func _build_intersections() -> void:
	# 斑马线（每个路口 4 条）
	var zebra_mat := StandardMaterial3D.new()
	zebra_mat.albedo_texture = RRTextures.zebra()
	zebra_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zebra_mat.roughness = 0.9
	var zebra_mesh := PlaneMesh.new()
	zebra_mesh.size = Vector2(GRID_HALF_W * 2.0 - 1.0, 1.9)
	zebra_mesh.material = zebra_mat
	var zebra_list: Array[Transform3D] = []
	for cx in GRID_COORDS:
		for cz in GRID_COORDS:
			var y := _street_y(cx, cz) + 0.014
			var off := GRID_HALF_W + 1.9
			for app in 4:
				var xf := Transform3D()
				match app:
					0: xf = Transform3D(Basis.from_euler(Vector3(0, 0, 0)), Vector3(cx, y, cz + off))
					1: xf = Transform3D(Basis.from_euler(Vector3(0, 0, 0)), Vector3(cx, y, cz - off))
					2: xf = Transform3D(Basis.from_euler(Vector3(0, PI / 2, 0)), Vector3(cx + off, y, cz))
					3: xf = Transform3D(Basis.from_euler(Vector3(0, PI / 2, 0)), Vector3(cx - off, y, cz))
				zebra_list.append(xf)
	var zmm := MultiMesh.new()
	zmm.transform_format = MultiMesh.TRANSFORM_3D
	zmm.mesh = zebra_mesh
	zmm.instance_count = zebra_list.size()
	for i in zebra_list.size():
		zmm.set_instance_transform(i, zebra_list[i])
	var zmmi := MultiMeshInstance3D.new()
	zmmi.multimesh = zmm
	add_child(zmmi)

	# 红绿灯：内圈 6×6 路口，按奇偶分两组对相位
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.12
	pole_mesh.bottom_radius = 0.16
	pole_mesh.height = 6.0
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color("#2c3138")
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.45
	pole_mesh.material = pole_mat
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.14, 0.14, 5.2)
	arm_mesh.material = pole_mat
	var house_mesh := BoxMesh.new()
	house_mesh.size = Vector3(0.34, 1.0, 0.3)
	var house_mat := StandardMaterial3D.new()
	house_mat.albedo_color = Color("#181c22")
	house_mesh.material = house_mat

	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.13
	lamp_mesh.height = 0.26
	var pole_list: Array[Transform3D] = []
	var arm_list: Array[Transform3D] = []
	var house_list: Array[Transform3D] = []
	var lamp_lists := {}
	for gi in 2:
		for cname in ["r", "y", "g"]:
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color("#111111")
			lm.emission_enabled = true
			match cname:
				"r": lm.emission = Color(1.0, 0.12, 0.1)
				"y": lm.emission = Color(1.0, 0.75, 0.1)
				"g": lm.emission = Color(0.15, 1.0, 0.25)
			lm.emission_energy_multiplier = 0.12
			var key := "%d_%s" % [gi, cname]
			lamp_lists[key] = {"mat": lm, "list": []}
			_sig_mats.resize(2)
			if _sig_mats[gi] == null:
				_sig_mats[gi] = {}
			_sig_mats[gi][cname] = lm

	var inner: Array = []
	for cx in GRID_COORDS:
		if absf(cx) >= 541.0 or absf(cx) < 1.0:
			continue
		inner.append(cx)
	for ix in inner.size():
		var cx: float = inner[ix]
		for iz in inner.size():
			var cz: float = inner[iz]
			var group := (ix + iz) % 2
			for corner in [Vector2(1, 1), Vector2(-1, -1)]:
				var px: float = cx + corner.x * (GRID_HALF_W + 2.4)
				var pz: float = cz + corner.y * (GRID_HALF_W + 2.4)
				var dir := Vector2(cx - px, cz - pz).normalized()
				var yaw := atan2(dir.x, dir.y)
				pole_list.append(Transform3D(Basis(), Vector3(px, 3.0, pz)))
				arm_list.append(Transform3D(
						Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(1, 1, 1)),
						Vector3(px, 5.75, pz)) * Transform3D(Basis(), Vector3(0, 0, 2.6)))
				house_list.append(Transform3D(
						Basis.from_euler(Vector3(0, yaw, 0)),
						Vector3(px, 5.35, pz) + Vector3(dir.x, 0, dir.y) * 4.9))
				var heights := [5.75, 5.35, 4.95]
				for ci in ["r", "y", "g"].size():
					var cname: String = ["r", "y", "g"][ci]
					var lxf := Transform3D(Basis(), Vector3(px, heights[ci], pz)
							+ Vector3(dir.x, 0, dir.y) * 4.9)
					var lkey := "%d_%s" % [group, cname]
					var linfo: Dictionary = lamp_lists[lkey]
					var larr: Array = linfo["list"]
					larr.append(lxf)

	for pack in [["pole", pole_mesh, pole_list], ["arm", arm_mesh, arm_list],
			["house", house_mesh, house_list]]:
		if pack[2].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pack[1]
		mm.instance_count = pack[2].size()
		for i in pack[2].size():
			mm.set_instance_transform(i, pack[2][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	for key in lamp_lists:
		var info: Dictionary = lamp_lists[key]
		if info["list"].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = lamp_mesh
		mm.instance_count = info["list"].size()
		for i in info["list"].size():
			mm.set_instance_transform(i, info["list"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _street_y(cx: float, cz: float) -> float:
	var kx := GRID_COORDS.find(cx)
	var kz := GRID_COORDS.find(cz)
	return maxf(_street_h(kx, false), _street_h(kz, true)) + 0.012


## 预计算建筑禁建区位图：所有道路样本周边 2 格（24m 格）标记为不可摆放
func _mark_road_blocks() -> void:
	for road in roads:
		for i in range(0, road.pts.size(), 4):
			var p := road.pts[i]
			var cx := int(p.x / 24.0)
			var cz := int(p.z / 24.0)
			for ox in range(-2, 3):
				for oz in range(-2, 3):
					_block[Vector2i(cx + ox, cz + oz)] = true


## 建筑群：约 800 栋，市中心高、外围矮，避让路网
func _place_buildings() -> void:
	var rng := RRUtil.Mulberry.new(20260830)
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3.ONE
	var bmat := StandardMaterial3D.new()
	bmat.albedo_texture = RRTextures.building()
	bmat.albedo_color = Color.WHITE
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.8
	bmesh.material = bmat

	var placed: Array[Transform3D] = []
	var colors: Array[Color] = []
	var occupancy := {}
	var guard := 0
	while placed.size() < 820 and guard < 40000:
		guard += 1
		var x := rng.range(-1080.0, 1080.0)
		var z := rng.range(-1080.0, 1080.0)
		if absf(x) < 150.0 and absf(z) < 150.0:
			continue   # 中心广场留空
		var cell := Vector2i(int(x / 70.0), int(z / 70.0))
		if occupancy.has(cell):
			continue
		if _block.has(Vector2i(int(x / 24.0), int(z / 24.0))):
			continue   # 距道路过近
		occupancy[cell] = true
		var d := maxf(absf(x), absf(z))
		var h: float
		if d < 420.0:
			h = rng.range(18.0, 62.0)
		elif d < 750.0:
			h = rng.range(9.0, 26.0)
		else:
			h = rng.range(5.0, 15.0)
		var w := rng.range(11.0, 22.0)
		var dep := rng.range(11.0, 22.0)
		var basis := Basis(Quaternion(Vector3.UP, rng.range(0.0, PI))) \
				.scaled(Vector3(w, h, dep))
		placed.append(Transform3D(basis, Vector3(x, h / 2.0, z)))
		var tint := 0.72 + rng.next() * 0.28
		colors.append(Color(tint, tint, tint * (0.96 + rng.next() * 0.08)))

	if placed.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bmesh
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


## 小地图贴图：整张路网俯视图（高架更亮，山海沙漠分区底色）
func _build_minimap() -> void:
	var size := 600
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.045, 0.055, 0.08))
	# 分区底色：西海 / 东沙漠 / 北山地 / 城市核心
	_fill_zone(img, size, -2800, -1080, -2800, 2800, Color(0.1, 0.28, 0.5))
	_fill_zone(img, size, 1080, 2800, -2100, 2100, Color(0.66, 0.55, 0.35))
	_fill_zone(img, size, -2800, 2800, -2800, -1080, Color(0.16, 0.26, 0.18))
	_fill_zone(img, size, -950, 950, -950, 950, Color(0.2, 0.22, 0.26))
	var scale := float(size) / (MAP_LIMIT * 2.0)
	for road in roads:
		var col := Color(0.62, 0.66, 0.72) if road.elevated else Color(0.30, 0.33, 0.38)
		var r := maxi(1, int(road.half_w * scale))
		var i := 0
		while i < road.pts.size():
			var p := road.pts[i]
			var px := int((p.x + MAP_LIMIT) * scale)
			var pz := int((p.z + MAP_LIMIT) * scale)
			img.fill_rect(
					Rect2i(clampi(px - r, 0, size - 1), clampi(pz - r, 0, size - 1),
							r * 2, r * 2), col)
			i += 4
	minimap_tex = ImageTexture.create_from_image(img)


## 世界坐标矩形 → 小地图像素填充
func _fill_zone(img: Image, size: int, x0: float, x1: float, z0: float, z1: float,
		col: Color) -> void:
	var s := float(size) / (MAP_LIMIT * 2.0)
	var px0 := clampi(int((x0 + MAP_LIMIT) * s), 0, size - 1)
	var px1 := clampi(int((x1 + MAP_LIMIT) * s), 0, size - 1)
	var pz0 := clampi(int((z0 + MAP_LIMIT) * s), 0, size - 1)
	var pz1 := clampi(int((z1 + MAP_LIMIT) * s), 0, size - 1)
	img.fill_rect(Rect2i(px0, pz0, maxi(px1 - px0, 1), maxi(pz1 - pz0, 1)), col)
