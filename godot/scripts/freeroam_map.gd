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
const CROSS_ELEV := 14.0      # 南北快速路
const CROSS_ELEV_EW := 19.0   # 东西快速路：与南北在 (0,0) 立体交叉，净空 5m
                              # （原来两条都是 14m，在 (0,0) 完全同高，
                              #   surf_skip 裁掉一条后合成一个平面十字 —— 不是立交）
const STREET_Y := 0.03        # 网格街统一标高：路口靠拼块拼接，不再靠错高避让

# 建筑排布
const BLOCK_CELL := 12.0     # 禁建区位图格边长
const TERR_CELL := 50.0      # 地形高程场格边长（与区域地面网格同步）
const BLK_FRONT := 13.0      # 楼正面距街道中心线：街半宽 8 + 人行道 2.2 + 退让 2.8
const BLK_DEEP_MIN := 14.0
const BLK_DEEP_MAX := 22.0
const BLK_CORNER := 35.0     # ≈ BLK_FRONT + BLK_DEEP_MAX：转角楼与沿街排不重叠

var roads: Array[Road] = []
var n := 0                 # 采样总数（vehicle 进度计算用）
var ds := SAMPLE_DS
var start_idx := 0
var wall_lat := 9.0
var minimap_tex: ImageTexture
var vehicle_y := 0.0       # 由 game 每帧写入（高度选层迟滞用）

var _sig_mats: Array = []  # [{"r": mat, "y": mat, "g": mat}] × 2 组
var _block := {}           # 24m 网格：距任意道路中心线过近的建筑禁建区（预计算）
var _terr := {}            # 50m 网格：地形高程场（盘山公路下方的山脊）
var _bld := {}             # 12m 网格：楼体顶高（相机避让查询用）
var pillar_pts := PackedVector3Array()   # 桥墩 (x, 柱顶高, z)，供体检探针核对
                                         # （headless 的 dummy 渲染器不保存
                                         #   MultiMesh 缓冲，读不回实例变换）

class Road:
	var pts := PackedVector3Array()       # 中心线（y = 路面海拔）
	var left := PackedVector2Array()      # 左向量 XZ
	var ang := PackedFloat32Array()
	var slope := PackedFloat32Array()     # dy/ds（沿切线）
	var half_w := 8.0
	var closed := false                   # 闭环（仅环线）；开放路不可首尾相连
	var xsec_cut := false                 # 网格街：路口方块内不铺面（由路口拼块接管）
	var along_x := false                  # 沿 X 走（水平街）
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


## 网格街统一标高。旧版让 22 条街两两错高（0.03~0.87）来躲深度冲突，代价是
## 121 个路口全变成 0.04~0.84m 的台阶，城市西东两侧差了将近一米。
## 现在改成：路口方块内两条街的路面都不铺，由 _build_intersections 的路口
## 拼块精确填满（边界正好是 ±GRID_HALF_W），既不重叠也不留缝，全程同一高度。
func _street_h(_k: int, _horizontal: bool) -> float:
	return STREET_Y


func _make_grid_roads() -> void:
	for k in GRID_COORDS.size():
		var c: float = GRID_COORDS[k]
		var rv := _make_road([Vector2(c, -900.0), Vector2(c, 900.0)],
				[STREET_Y], false, GRID_HALF_W, false)
		rv.xsec_cut = true
		var rh := _make_road([Vector2(-900.0, c), Vector2(900.0, c)],
				[STREET_Y], false, GRID_HALF_W, false)
		rh.xsec_cut = true
		rh.along_x = true


func _make_ring() -> void:
	# 圆角矩形用密控制点直接画出来。
	# 原来只给 8 个角点走 Catmull-Rom：转角段弧长只有 212m 而切线长达 690m，
	# 曲率半径被压到 4.5m（小于半宽 10），路面内缘自我折叠；
	# 直边同时被外鼓 20.6m 到 ±720.6，正好压在 GRID_COORDS 的 ±720 街道上，
	# 桥墩全部放不下 —— 八段各约 300m 桥面凭空悬着。
	var s := 700.0
	var r := 150.0
	var k := s - r
	var seg_start := [Vector2(-k, -s), Vector2(s, -k), Vector2(k, s), Vector2(-s, k)]
	var seg_end := [Vector2(k, -s), Vector2(s, k), Vector2(-k, s), Vector2(-s, -k)]
	var arc_c := [Vector2(k, -k), Vector2(k, k), Vector2(-k, k), Vector2(-k, -k)]
	var arc_a0 := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var cps := []
	for q in 4:
		for i in 22:                       # 直边每 50m 一个控制点
			cps.append((seg_start[q] as Vector2).lerp(seg_end[q], float(i) / 22.0))
		for i in 6:                        # 圆角每 15° 一个控制点
			var th: float = arc_a0[q] + PI * 0.5 * float(i) / 6.0
			cps.append(arc_c[q] + Vector2(cos(th), sin(th)) * r)
	_make_road(cps, [RING_ELEV], true, 10.0, true)


func _make_cross_highways() -> void:
	# 东西 19m / 南北 14m / 环线 10m —— 三层互不同高，才是立交
	_make_road([Vector2(-900.0, 0.0), Vector2(900.0, 0.0)], [CROSS_ELEV_EW], false, 10.0, true)
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
		# rp 是 Vector3：rp.y 是高度，环线的 XZ 坐标必须取 (rp.x, rp.z)。
		# 原来除 outward 外的几处都误写成 Vector2(rp.x, rp.y)，等于把汇入点
		# 当成 z=10 的位置 —— 4 条匝道全部拐向错误方位、终点悬在半空，
		# 根本没接上环线（车开上去会冲出路面卡死）。
		var rxz := Vector2(rp.x, rp.z)
		var rtan := Vector2(sin(ring.ang[bi]), cos(ring.ang[bi]))
		var outward := rxz.normalized()   # 径向单位向量
		# 地面端：就近的网格街道交点（内圈 540），入口沿街道后退 30m 保证精确接驳
		var g := Vector2(signf(d[0]) * 540.0, signf(d[1]) * 540.0)
		var on_x := absf(rp.x) > absf(rp.z)   # 退沿 X → 匝道口贴水平街
		# 入口段抬高 0.20：匝道贴着街面起步，不叠面（叠面会深度打架闪烁）
		var g_y := _street_h(8, on_x) + 0.20
		var crown_y := maxf(_street_h(8, false), _street_h(8, true)) + 0.20
		var street_back := Vector2(-signf(d[0]), 0.0) if on_x \
				else Vector2(0.0, -signf(d[1]))
		# 并线尾段：沿环线外侧平行。名义 16.5 = 环半宽10 + 0.5缝 + 匝道半宽6，
		# 但样条会把实际间距拉回到 14.8m（< 半宽和 16）造成同高重叠，
		# 留 2m 余量取 18.5。
		var merge_c := rxz + outward * 18.5
		var cps := [
			g + street_back * 30.0,
			g,
			g.lerp(rxz, 0.55) + outward * 26.0,
			rxz - rtan * 80.0 + outward * 20.0,
			merge_c - rtan * 30.0,
			merge_c + rtan * 10.0,
		]
		_make_road(cps, [g_y, crown_y, 5.0, 8.5, RING_ELEV, RING_ELEV],
				false, 6.0, true)
	# 4 条快速路匝道（东西向 2 条 + 南北向 2 条）
	for sx in [-1.0, 1.0]:
		var hx: float = 560.0 * sx
		# 起点与主线边对边：主线半宽 10 + 0.5 缝 + 匝道半宽 6 = 16.5。
		# 原来写 10.5 漏算了匝道自身半宽，匝道桥面与主线桥面同高重叠 5.5m、
		# 长约 130m —— 两层路面完全共面，surf_skip 也裁不掉。
		# 控制点在 z 上必须单调远离主线、步长渐增。原来 (hx+60sx,-16) 之后
		# 直接跳到 (hx+150sx,-170)，z 跨度 154m 把切线撑爆，样条为迎合它先
		# 反向甩回 z=-1.7 —— 匝道钻进主线桥面正下方，最小净空只剩 0.11m。
		# 尾段 x 收到 ±640：停在 ±710 会压上 ±720 网格街，停在 ±690 又会贴到
		# 环线直边（x=±700）—— 下坡途中恰好经过 y=10，与环线同高重叠。
		_make_road([
			Vector2(hx - 150.0 * sx, -16.5), Vector2(hx - 40.0 * sx, -16.5),
			Vector2(hx + 40.0 * sx, -30.0), Vector2(hx + 75.0 * sx, -80.0),
			Vector2(hx + 80.0 * sx, -190.0), Vector2(hx + 80.0 * sx, -349.5),
		], [CROSS_ELEV_EW, CROSS_ELEV_EW, 17.0, 13.0, 4.0, STREET_Y],
				false, 6.0, true)
	for sz in [-1.0, 1.0]:
		var hz: float = 560.0 * sz
		# 同上：16.5 = 主线半宽 10 + 0.5 缝 + 匝道半宽 6
		_make_road([
			Vector2(16.5, hz - 150.0 * sz), Vector2(16.5, hz - 40.0 * sz),
			Vector2(30.0, hz + 40.0 * sz), Vector2(80.0, hz + 75.0 * sz),
			Vector2(190.0, hz + 80.0 * sz), Vector2(349.5, hz + 80.0 * sz),
		], [CROSS_ELEV, CROSS_ELEV, 12.5, 9.0, 3.0, STREET_Y], false, 6.0, true)


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
	var gidx: int = q["idx"]
	if gidx < 0:
		gidx = _nearest_sample(x, z)   # 超出所有道路搜索半径时全局兜底
	var r := gidx / 100000
	var i := gidx % 100000
	var p := roads[r].pts[i]
	return {"pos": Vector3(p.x, p.y + 0.2, p.z), "ang": roads[r].ang[i]}


## 全局最近采样（粗扫，只在复位兜底时调用）
func _nearest_sample(x: float, z: float) -> int:
	var best := 0
	var bd := INF
	for r in roads.size():
		var pts := roads[r].pts
		for i in range(0, pts.size(), 8):
			var dx := pts[i].x - x
			var dz := pts[i].z - z
			var d := dx * dx + dz * dz
			if d < bd:
				bd = d
				best = r * 100000 + i
	return best


func _global_pt(gidx: int) -> Vector3:
	if gidx < 0:
		return Vector3.ZERO
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
	var best_dist := INF
	var road_cost := {}          # 每条候选路的代价（用于重叠区域取最宽软墙）
	var road_bi := {}            # 每条候选路的最近采样（软墙抑制用）
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
		# 开放路端点之外：把纵向过冲重重计入距离。原来只看到最近采样的
		# 直线距离，驶出断头高架后最近采样仍是端点，车会沿用桥面高度
		# 在空中平地行驶 20 多米才掉下去。
		var dist := sqrt(bd2)
		if not road.closed and (bi == 0 or bi == road.pts.size() - 1):
			var tv := Vector2(sin(road.ang[bi]), cos(road.ang[bi]))
			var lon: float = (x - road.pts[bi].x) * tv.x + (z - road.pts[bi].z) * tv.y
			var over: float = (-lon) if bi == 0 else lon
			if over > 0.0:
				dist += over * 10.0
		var cost := dist + absf(road.pts[bi].y - vehicle_y) * 6.0   # 高度迟滞
		if r == hint_road:
			cost -= 2.0   # 当前路粘性，避免并线/重叠处来回跳层
		road_cost[r] = cost
		road_bi[r] = bi
		if cost < best_cost:
			best_cost = cost
			best_road = r
			best_i = bi
			best_dist = dist

	if best_road < 0 or best_dist > roads[best_road].half_w + 16.0:
		# 路网外：草地。idx 保留「最近的那条路」，找不到任何路才用 -1。
		# 原来硬写 0，而 0 恰好是 road0 的第 0 个采样（x=-900,z=-900 那条街
		# 的起点）：按 R 复位会被瞬移到地图西南角，hint 也会一直给 road0
		# 加粘性，越野时物理一直挂在那条街上。
		_scratch["idx"] = (best_road * 100000 + best_i) if best_road >= 0 else -1
		_scratch["road"] = best_road
		_scratch["lat_off"] = 999.0
		_scratch["ang"] = roads[best_road].ang[best_i] if best_road >= 0 else 0.0
		_scratch["surf"] = "grass"
		_scratch["height"] = 0.0
		_scratch["slope"] = 0.0
		_scratch["wall"] = 10000.0
		_scratch["dist_sq"] = best_dist * best_dist
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
	# 软墙抑制：只要车还在另一条同层邻近道路的走廊之内，就不该被推。
	# 贴着软墙过十字路口时 hint 粘性会让车穿过后仍挂在横街上，横街的
	# 横向轴于是变成一道纵向栅栏，把车正面撞停（实测 +22.6 → -6.3 m/s）。
	if al > wall:
		for rr2 in road_cost:
			if rr2 == best_road or road_cost[rr2] > best_cost + 12.0:
				continue
			var o: Road = roads[rr2]
			var oi: int = road_bi[rr2]
			var op := o.pts[oi]
			if absf(op.y - p.y) > 3.0:
				continue
			var ol := o.left[oi]
			if absf((x - op.x) * ol.x + (z - op.z) * ol.y) <= o.wall:
				wall = al + 2.0
				break
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


## 该段落在路口方块外的参数区间（0..1）。段长 1.5m 远小于方块 16m，
## 所以最多只会跨过一条边界，单趟扫描即可。返回 x>=y 表示整段都在方块内。
func _xsec_span(a: float, b: float, half: float) -> Vector2:
	var lo := minf(a, b)
	var hi := maxf(a, b)
	for c in GRID_COORDS:
		var c0: float = c - half
		var c1: float = c + half
		if hi <= c0 or lo >= c1:
			continue
		if lo >= c0 and hi <= c1:
			return Vector2(1.0, 0.0)
		if lo < c0:
			hi = minf(hi, c0)
		else:
			lo = maxf(lo, c1)
	var d := b - a
	if absf(d) < 1e-6:
		return Vector2(0.0, 1.0)
	var f0 := (lo - a) / d
	var f1 := (hi - a) / d
	return Vector2(minf(f0, f1), maxf(f0, f1))


## 桥体四边形暂存（与路面不同材质，需单独 flush）
var _d_pos := PackedVector3Array()
var _d_nrm := PackedVector3Array()


func _deck_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		_d_pos.append(v)
		_d_nrm.append(nrm)


func _flush_deck(mat: Material) -> void:
	if _d_pos.is_empty():
		return
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _d_pos
	arrays[Mesh.ARRAY_NORMAL] = _d_nrm
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	_d_pos = PackedVector3Array()
	_d_nrm = PackedVector3Array()


func _build_road_meshes() -> void:
	_mark_rail_skips()
	_mark_surf_skips()
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_texture = RRTextures.asphalt()
	road_mat.roughness = 0.92
	road_mat.metallic_specular = 0.08   # 沥青只留一点点反光
	road_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var walk_mat := StandardMaterial3D.new()
	walk_mat.albedo_color = Color("#787e88")
	walk_mat.roughness = 0.9
	walk_mat.metallic_specular = 0.0
	# 桥体（箱梁底板 + 腹板）：路面四边形是单面的，站在桥下抬头看是空的 ——
	# 必须补出底面与侧面，否则高架就是一张飘着的纸
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color("#9aa0a8")
	deck_mat.roughness = 0.9
	deck_mat.metallic_specular = 0.0
	deck_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
			# 网格街在路口处裁剪：路面裁到 ±GRID_HALF_W，人行道裁到 ±(GRID_HALF_W+2.2)，
			# 空出来的方块与四个转角由 _build_intersections 精确填上。
			# 两者裁剪边界不同，否则两条街的人行道会在转角互相叠面。
			var sp_r := Vector2(0.0, 1.0)
			var sp_w := Vector2(0.0, 1.0)
			if road.xsec_cut:
				var sa: float = pi.x if road.along_x else pi.z
				var sb: float = pj.x if road.along_x else pj.z
				sp_r = _xsec_span(sa, sb, GRID_HALF_W)
				sp_w = _xsec_span(sa, sb, GRID_HALF_W + 2.2)
			# 主路面（同层共面重叠段跳过：由覆盖路面的沥青接管，如高架十字交叉）
			if sp_r.x < sp_r.y and (road.surf_skip.size() != cnt
					or not (road.surf_skip[i] or road.surf_skip[j])):
				var ra := pi.lerp(pj, sp_r.x)
				var rb := pi.lerp(pj, sp_r.y)
				var rla := li.lerp(lj, sp_r.x)
				var rlb := li.lerp(lj, sp_r.y)
				var ru0 := lerpf(u0, u1, sp_r.x)
				var ru1 := lerpf(u0, u1, sp_r.y)
				_quad(
					ra + Vector3(-rla.x * w, 0, -rla.y * w),
					rb + Vector3(-rlb.x * w, 0, -rlb.y * w),
					rb + Vector3(rlb.x * w, 0, rlb.y * w),
					ra + Vector3(rla.x * w, 0, rla.y * w),
					Vector3.UP, Color.WHITE,
					Vector2(0, ru0), Vector2(0, ru1), Vector2(1, ru1), Vector2(1, ru0))
			if road.elevated and (road.surf_skip.size() != cnt
					or not (road.surf_skip[i] or road.surf_skip[j])):
				# 箱梁：底板（朝下）+ 两侧腹板，厚 0.7m，稍宽于路面
				var dt := 0.7
				var eo := w + 0.45
				var s0 := pi + Vector3(-li.x * eo, -dt, -li.y * eo)
				var s1 := pj + Vector3(-lj.x * eo, -dt, -lj.y * eo)
				var s2 := pj + Vector3(lj.x * eo, -dt, lj.y * eo)
				var s3 := pi + Vector3(li.x * eo, -dt, li.y * eo)
				_deck_quad(s3, s2, s1, s0, Vector3.DOWN)
				for side in [-1.0, 1.0]:
					var o: float = eo * side
					var t0 := pi + Vector3(li.x * o, 0.05, li.y * o)
					var t1 := pj + Vector3(lj.x * o, 0.05, lj.y * o)
					var b0 := pi + Vector3(li.x * o, -dt, li.y * o)
					var b1 := pj + Vector3(lj.x * o, -dt, lj.y * o)
					_deck_quad(b0, b1, t1, t0, Vector3(li.x * side, 0, li.y * side))
			if not road.elevated:
				# 路缘人行道（略高于路面）
				if sp_w.x < sp_w.y:
					var wa := pi.lerp(pj, sp_w.x)
					var wb := pi.lerp(pj, sp_w.y)
					var wla := li.lerp(lj, sp_w.x)
					var wlb := li.lerp(lj, sp_w.y)
					for side in [-1.0, 1.0]:
						var a := wa + Vector3(wla.x * side * (w + 0.06), 0.05,
								wla.y * side * (w + 0.06))
						var b := wb + Vector3(wlb.x * side * (w + 0.06), 0.05,
								wlb.y * side * (w + 0.06))
						var c := wb + Vector3(wlb.x * side * (w + 2.2), 0.05,
								wlb.y * side * (w + 2.2))
						var d := wa + Vector3(wla.x * side * (w + 2.2), 0.05,
								wla.y * side * (w + 2.2))
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
	_flush_deck(deck_mat)

	# 高架桥墩（每 ~45m 一根，从地面顶到桥面）
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 1.1
	pillar_mesh.bottom_radius = 1.5
	pillar_mesh.height = 1.0
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color("#8f959c")
	pillar_mat.roughness = 0.85
	pillar_mesh.material = pillar_mat
	# 桥墩：优先桥下中央单柱；正下方是马路时改成门式墩（两侧立柱 + 横梁），
	# 两侧也让不开才沿桥前后挪，最后才放弃。
	# 原来完全不做检查，桥墩会立在路口正中、也会穿过下层桥面；
	# 而只做「被占就跳过」又会让两条正压在街道上方的快速路一根柱子都不剩。
	var pillar_list: Array[Transform3D] = []
	var beam_list: Array[Transform3D] = []
	for road in roads:
		if not road.elevated:
			continue
		var cnt := road.pts.size()
		var step := maxi(1, roundi(45.0 / SAMPLE_DS))
		for i in range(0, cnt, step):
			var idx := i
			var placed := false
			for tries in 10:
				var p := road.pts[idx]
				if p.y >= 1.5:
					if not _pillar_blocked(road, p):
						pillar_list.append(Transform3D(Basis.from_scale(Vector3(1, p.y, 1)),
								Vector3(p.x, p.y * 0.5, p.z)))
						pillar_pts.append(Vector3(p.x, p.y, p.z))
						placed = true
						break
					# 门式墩：立柱退到桥面外侧 1.6m，柱顶收到横梁底下
					var lat := road.left[idx]
					var off := road.half_w + 1.6
					var pa := p + Vector3(lat.x * off, 0.0, lat.y * off)
					var pb := p - Vector3(lat.x * off, 0.0, lat.y * off)
					if not _pillar_blocked(road, pa) and not _pillar_blocked(road, pb):
						var ch := p.y - 1.0
						for c in [pa, pb]:
							pillar_list.append(Transform3D(Basis.from_scale(Vector3(1, ch, 1)),
									Vector3(c.x, ch * 0.5, c.z)))
							pillar_pts.append(Vector3(c.x, ch, c.z))
						# 横梁：沿横向跨过桥面，藏在桥底
						var bx := Vector3(lat.x, 0, lat.y) * (off * 2.0 + 1.4)
						var bz := Vector3(-lat.y, 0, lat.x) * 1.8
						beam_list.append(Transform3D(Basis(bx, Vector3(0, 1.0, 0), bz),
								Vector3(p.x, p.y - 0.6, p.z)))
						placed = true
						break
				idx = mini(idx + 3, cnt - 1)
			if not placed:
				continue
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
	if not beam_list.is_empty():
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3.ONE
		beam_mesh.material = pillar_mat
		var bmm := MultiMesh.new()
		bmm.transform_format = MultiMesh.TRANSFORM_3D
		bmm.mesh = beam_mesh
		bmm.instance_count = beam_list.size()
		for i in beam_list.size():
			bmm.set_instance_transform(i, beam_list[i])
		var bmmi := MultiMeshInstance3D.new()
		bmmi.multimesh = bmm
		add_child(bmmi)
	print("[map] 桥墩 %d 根（含门式墩）+ 横梁 %d 道" % [pillar_list.size(), beam_list.size()])


## 四大区域地面与景观：顶点色大网格（城市/草地/沙漠/山地/沙滩同一层，无深度冲突）
## 桥墩落点是否被占：地面街道（含人行道 11m）或它要穿过的更低一层桥面
func _pillar_blocked(road: Road, p: Vector3) -> bool:
	for c in GRID_COORDS:
		if absf(p.x - c) < 11.0 or absf(p.z - c) < 11.0:
			return true
	for other in roads:
		if other == road or not other.elevated:
			continue
		var gap: float = other.half_w + 2.0
		var rr := int(ceil(gap / CELL)) + 1
		var gx := int(p.x / CELL)
		var gz := int(p.z / CELL)
		for cxi in range(gx - rr, gx + rr + 1):
			for czi in range(gz - rr, gz + rr + 1):
				var key := Vector2i(cxi, czi)
				if not other.grid.has(key):
					continue
				for j in other.grid[key]:
					var q := other.pts[j]
					if q.y < p.y - 1.0 and Vector2(q.x - p.x, q.z - p.z).length() < gap:
						return true
	return false


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
## 地形高程场：把「非高架但明显离地」的道路（北盘山公路爬到 72m）
## 压成一道山脊。否则那 3.5km 路面就悬在 y=0 的平板上空，下面既没有
## 山体也没有桥墩 —— 一条飘在平原上的空中缎带。
func _build_terrain_field() -> void:
	const OUTER := 220.0
	for road in roads:
		if road.elevated:
			continue
		var peak := 0.0
		for p in road.pts:
			peak = maxf(peak, p.y)
		if peak < 3.0:
			continue
		var inner: float = road.half_w + 4.0
		var rc := int(ceil(OUTER / TERR_CELL))
		for i in range(0, road.pts.size(), 6):
			var p := road.pts[i]
			if p.y < 1.0:
				continue
			var base: float = p.y - 2.0       # 略低于路面，路像切在山脊上
			var cx := int(round(p.x / TERR_CELL))
			var cz := int(round(p.z / TERR_CELL))
			for ox in range(-rc, rc + 1):
				for oz in range(-rc, rc + 1):
					var key := Vector2i(cx + ox, cz + oz)
					var d := Vector2(float(key.x) * TERR_CELL - p.x,
							float(key.y) * TERR_CELL - p.z).length()
					if d > OUTER:
						continue
					var h: float = base
					if d > inner:
						h = base * (0.5 + 0.5 * cos(PI * (d - inner) / (OUTER - inner)))
					if h > float(_terr.get(key, 0.0)):
						_terr[key] = h


func _terrain_h(x: float, z: float) -> float:
	return float(_terr.get(Vector2i(int(round(x / TERR_CELL)),
			int(round(z / TERR_CELL))), 0.0))


func _build_zone_ground() -> void:
	_build_terrain_field()
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
	mat.metallic_specular = 0.0   # 同上：干地面不反天空，否则俯视一片亮蓝
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
					var p00 := Vector3(x0, _terrain_h(x0, z0), z0)
					var p10 := Vector3(x0 + cell, _terrain_h(x0 + cell, z0), z0)
					var p01 := Vector3(x0, _terrain_h(x0, z0 + cell), z0 + cell)
					var p11 := Vector3(x0 + cell, _terrain_h(x0 + cell, z0 + cell), z0 + cell)
					for tri in [[p00, c00, p10, c10, p11, c11], [p00, c00, p11, c11, p01, c01]]:
						# 法线按实际三角形算，山脊才有明暗；全 UP 会把山坡打成平地
						var nrm: Vector3 = (tri[2] - tri[0]).cross(tri[4] - tri[0])
						nrm = nrm.normalized() if nrm.length() > 1e-6 else Vector3.UP
						if nrm.y < 0.0:
							nrm = -nrm
						for kk in [0, 2, 4]:
							st.set_normal(nrm)
							st.set_color(tri[kk + 1])
							st.add_vertex(tri[kk])
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
		# 雪顶必须贴着岩体锥面：底半径 = 覆盖高度比例 × 山体底半径，顶点与山顶
		# 重合（只高出 1% 做成薄壳）。原来底半径 0.4r、锥尖还高出 15%，
		# 白锥比该高度处的岩体宽 2.7 倍 —— 整圈裙边悬在半空、尖端戳出山顶。
		var cf := 0.30
		var sh: float = (cf + 0.02) * h
		var sr: float = (cf + 0.01) * radius
		caps.append(Transform3D(Basis.from_scale(Vector3(sr, sh, sr)),
				Vector3(x, h * 1.01 - sh * 0.5, z)))
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
	# ---- 路口铺装：16×16m 拼块，边界正好接上两条街被裁掉的地方 ----
	# 中间不画车道线（真实路口就是这样），四角补人行道转角。
	# 全部与街面同高（STREET_Y / +0.05），既不重叠也不留缝。
	var hw := GRID_HALF_W
	var wk := hw + 2.2
	for cx in GRID_COORDS:
		for cz in GRID_COORDS:
			_quad(Vector3(cx - hw, STREET_Y, cz - hw), Vector3(cx - hw, STREET_Y, cz + hw),
					Vector3(cx + hw, STREET_Y, cz + hw), Vector3(cx + hw, STREET_Y, cz - hw),
					Vector3.UP, Color.WHITE,
					Vector2(0, 0), Vector2(0, 2), Vector2(2, 2), Vector2(2, 0))
	var xsec_mat := StandardMaterial3D.new()
	xsec_mat.albedo_texture = RRTextures.asphalt_plain()
	xsec_mat.roughness = 0.92
	xsec_mat.metallic_specular = 0.08
	xsec_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_flush(xsec_mat)

	for cx in GRID_COORDS:
		for cz in GRID_COORDS:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var x0: float = cx + minf(sx * hw, sx * wk)
					var x1: float = cx + maxf(sx * hw, sx * wk)
					var z0: float = cz + minf(sz * hw, sz * wk)
					var z1: float = cz + maxf(sz * hw, sz * wk)
					var yy := STREET_Y + 0.05
					_quad(Vector3(x0, yy, z0), Vector3(x0, yy, z1),
							Vector3(x1, yy, z1), Vector3(x1, yy, z0),
							Vector3.UP, Color.WHITE)
	var corner_mat := StandardMaterial3D.new()
	corner_mat.albedo_color = Color("#787e88")
	corner_mat.roughness = 0.9
	corner_mat.metallic_specular = 0.0
	_flush(corner_mat)

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
	# 灯壳厚 0.16：原来 0.30 厚而灯泡半径只有 0.13，三颗灯球被完全封在
	# 不透明壳体内部，路口信号永远看不出颜色
	house_mesh.size = Vector3(0.36, 1.05, 0.16)
	var house_mat := StandardMaterial3D.new()
	house_mat.albedo_color = Color("#181c22")
	house_mesh.material = house_mat

	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.15
	lamp_mesh.height = 0.30
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
			var group0 := (ix + iz) % 2
			# 同一路口的两根灯必须反相，否则南北与东西同时绿灯
			for ci2 in 2:
				var corner: Vector2 = [Vector2(1, 1), Vector2(-1, -1)][ci2]
				var group := (group0 + ci2) % 2
				# 退到 11.0m：街道软墙允许车开到 half_w+2.6=10.6m，
				# 原来灯杆立在 10.4m，车直接从灯杆里穿过去
				var px: float = cx + corner.x * (GRID_HALF_W + 3.0)
				var pz: float = cz + corner.y * (GRID_HALF_W + 3.0)
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


## 预计算建筑禁建区（12m 格）：只标记非网格道路 —— 高架环线 / 快速路 / 匝道
## 留 16m 余量（楼不能贴到桥面和桥墩），城外公路留 7m。
## 网格街道不入表：沿街楼按街区边界精确排布（BLK_FRONT），比位图掩码准得多。
## 旧版对「所有」道路各标 ±2 格 × 24m ≈ 60m，而街距只有 180m，
## 楼全被推到街区正中，沿街两侧空荡荡 —— 城市不像城市的主因。
func _mark_road_blocks() -> void:
	var grid_roads := GRID_COORDS.size() * 2   # 前 22 条是网格街道
	for ri in range(grid_roads, roads.size()):
		var road: Road = roads[ri]
		var rad: float = road.half_w + (16.0 if road.elevated else 7.0)
		var rc := int(ceil(rad / BLOCK_CELL))
		for i in range(0, road.pts.size(), 4):
			var p := road.pts[i]
			var cx := int(floor(p.x / BLOCK_CELL))
			var cz := int(floor(p.z / BLOCK_CELL))
			for ox in range(-rc, rc + 1):
				for oz in range(-rc, rc + 1):
					_block[Vector2i(cx + ox, cz + oz)] = true


## 楼体着色器：UV 按「实际米数」取，窗格不随楼体缩放
## （旧版整张贴图铺满一个面，62m 高塔上每扇窗有 8m 高）。
## 首层商铺带与屋顶女儿墙用高度切色实现，不加几何 —— 屋顶盖板与楼顶面
## 共面正是 z-fighting 的经典形状。
## 实例色的 alpha 当作类型标记：1=落地楼体，0.5=退台叠加体，0=素面块（设备房）。
func _building_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;

uniform sampler2D wall_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile_m = vec2(9.6, 13.6);    // 一张贴图覆盖的实际米数（4 开间 2.4m × 4 层 3.4m）
uniform vec3 roof_color : source_color = vec3(0.30, 0.31, 0.33);
uniform vec3 podium_color : source_color = vec3(0.19, 0.21, 0.25);
uniform float podium_h = 4.6;
uniform float parapet_h = 1.2;

varying vec3 v_tint;
varying float v_kind;   // 实例类型（见上）
varying float v_face;   // >0.5 为水平面（屋顶 / 底面）
varying float v_up;     // 距该体块底面的高度（米）
varying float v_hgt;    // 该体块总高（米）

void vertex() {
	// MultiMesh 每实例的缩放：从 MODEL_MATRIX 各列长度取（朝向严格正交，无剪切）
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz),
			length(MODEL_MATRIX[1].xyz),
			length(MODEL_MATRIX[2].xyz));
	vec3 p = VERTEX * sc;
	vec3 n = abs(NORMAL);
	v_hgt = sc.y;
	v_up = p.y + sc.y * 0.5;
	if (n.y > 0.5) {
		v_face = 1.0;
		UV = p.xz / 6.0;
	} else {
		v_face = 0.0;
		// 按实例世界坐标错开整开间：否则整条街的窗格同相位，一眼是复制粘贴
		float ph = fract(sin(dot(vec2(MODEL_MATRIX[3].x, MODEL_MATRIX[3].z),
				vec2(12.9898, 78.233))) * 43758.545);
		UV = vec2(((n.x > 0.5) ? p.z : p.x) / tile_m.x + floor(ph * 4.0) * 0.25,
				-v_up / tile_m.y);
	}
	v_tint = COLOR.rgb;
	v_kind = COLOR.a;
}

void fragment() {
	vec3 c;
	if (v_face > 0.5) {
		c = roof_color;
	} else if (v_kind < 0.25) {
		c = v_tint;                                          // 素面设备房
	} else if (v_kind > 0.75 && v_hgt > 11.0 && v_up < podium_h) {
		// 首层商铺：整面玻璃 + 竖框 + 上下压边（比一整片灰墙像街道得多）
		float bay = fract(UV.x * tile_m.x / 3.2);
		float band = v_up / podium_h;
		float frame = max(max(step(0.90, bay), step(bay, 0.10)),
				max(step(0.90, band), step(band, 0.09)));
		c = mix(vec3(0.12, 0.15, 0.19), podium_color * (1.7 + 0.6 * v_tint.r), frame);
	} else if (v_hgt > 9.0 && v_hgt - v_up < parapet_h) {
		c = roof_color * 1.5;                                // 屋顶女儿墙
	} else if (v_up < 0.9) {
		c = roof_color * 1.15;                               // 墙裙：楼体压住地面，不像悬浮
	} else {
		c = texture(wall_tex, UV).rgb * v_tint;
	}
	ALBEDO = c;
	ROUGHNESS = 0.86;
	SPECULAR = 0.14;   // 天空反射源下掠射角高光会把整面墙打成荧光蓝，压住
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("wall_tex", RRTextures.building_wall())
	return m


## 建筑群：沿街区四边成排（正面退到人行道后 2.8m）+ 四角角楼 + 街区内低层填充
## + 城郊散点；高层带退台、屋顶设备房与天线。朝向与街道网格严格正交
## （旧版 rng.range(0, PI) 随机转，楼歪着站，而且 Basis.scaled 是先转后按世界轴
## 缩放，非 90° 倍数时盒子会被剪切成平行六面体）。
func _place_buildings() -> void:
	var rng := RRUtil.Mulberry.new(20260830)
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var ants: Array[Transform3D] = []

	# 冷玻璃 / 暖混凝土 / 深灰石材 / 浅色面砖 / 灰绿
	var palette := [
		Color(0.78, 0.80, 0.84), Color(0.83, 0.79, 0.73),
		Color(0.55, 0.58, 0.63), Color(0.88, 0.88, 0.90),
		Color(0.64, 0.69, 0.71),
	]

	var buildable := func(cx: float, cz: float, hw: float, hd: float) -> bool:
		if absf(cx) < 150.0 and absf(cz) < 150.0:
			return false                       # 中心广场留空
		# 楼脚不能越过人行道外缘（街半宽 8 + 人行道 2.2）。
		# 沿街排本身就退到 13m，只有城郊散点会撞上这条 —— 原来它只用
		# absf(sx) < 905 挡外圈街道，而街道人行道外缘在 910.2m，楼直接骑上去
		for c in GRID_COORDS:
			if absf(cx - c) - hw < 10.5 or absf(cz - c) - hd < 10.5:
				return false
		for ox in [-hw, 0.0, hw]:
			for oz in [-hd, 0.0, hd]:
				if _block.has(Vector2i(int(floor((cx + ox) / BLOCK_CELL)),
						int(floor((cz + oz) / BLOCK_CELL)))):
					return false
		return true

	# 市中心高、外围矮
	var zone_h := func(x: float, z: float) -> float:
		var d := maxf(absf(x), absf(z))
		if d < 260.0:
			return rng.range(52.0, 104.0)
		elif d < 480.0:
			return rng.range(28.0, 62.0)
		elif d < 700.0:
			return rng.range(16.0, 38.0)
		elif d < 900.0:
			return rng.range(10.0, 24.0)
		return rng.range(7.0, 16.0)

	# 放一栋：主体 →（退台）→（屋顶设备房）→（天线）
	var put := func(cx: float, cz: float, w: float, dep: float, h: float) -> void:
		if not buildable.call(cx, cz, w * 0.5, dep * 0.5):
			return
		var tint: Color = palette[mini(int(rng.next() * palette.size()), palette.size() - 1)]
		var j := rng.range(-0.05, 0.05)
		tint = Color(clampf(tint.r + j, 0, 1), clampf(tint.g + j, 0, 1),
				clampf(tint.b + j, 0, 1), 1.0)
		xfs.append(Transform3D(Basis.from_scale(Vector3(w, h, dep)),
				Vector3(cx, h * 0.5, cz)))
		cols.append(tint)
		# 记进占位网格，供相机避让查询（楼是 MultiMesh，没有碰撞体）
		var bx0 := int(floor((cx - w * 0.5) / BLOCK_CELL))
		var bx1 := int(floor((cx + w * 0.5) / BLOCK_CELL))
		var bz0 := int(floor((cz - dep * 0.5) / BLOCK_CELL))
		var bz1 := int(floor((cz + dep * 0.5) / BLOCK_CELL))
		for gx2 in range(bx0, bx1 + 1):
			for gz2 in range(bz0, bz1 + 1):
				var bk := Vector2i(gx2, gz2)
				if h > float(_bld.get(bk, 0.0)):
					_bld[bk] = h
		var top := h
		var tw := w
		var td := dep
		# 退台收分：天际线才有层次
		if h > 52.0 and rng.next() < 0.72:
			var k := rng.range(0.58, 0.78)
			var uh := h * rng.range(0.20, 0.42)
			tw = w * k
			td = dep * k
			# 底面埋进主体 0.5m，不与主体顶面共面
			xfs.append(Transform3D(Basis.from_scale(Vector3(tw, uh, td)),
					Vector3(cx, h + uh * 0.5 - 0.5, cz)))
			cols.append(Color(tint.r, tint.g, tint.b, 0.5))
			top = h + uh - 0.5
		# 屋顶设备房
		if top > 16.0 and rng.next() < 0.5:
			var mw := minf(rng.range(4.0, 9.0), tw * 0.5)
			var md := minf(rng.range(4.0, 9.0), td * 0.5)
			var mh := rng.range(2.4, 4.2)
			var ox := rng.range(-1.0, 1.0) * maxf(tw * 0.5 - mw * 0.5 - 0.8, 0.0)
			var oz := rng.range(-1.0, 1.0) * maxf(td * 0.5 - md * 0.5 - 0.8, 0.0)
			xfs.append(Transform3D(Basis.from_scale(Vector3(mw, mh, md)),
					Vector3(cx + ox, top + mh * 0.5 - 0.5, cz + oz)))
			cols.append(Color(0.55, 0.56, 0.58, 0.0))
		# 天线：只给最高的那批
		if top > 78.0 and rng.next() < 0.65:
			var ah := rng.range(9.0, 24.0)
			ants.append(Transform3D(Basis.from_scale(Vector3(1.0, ah, 1.0)),
					Vector3(cx, top + ah * 0.5, cz)))

	# ---- 逐街区排布（11 条街 → 10×10 个 180m 街区）----
	for bi in GRID_COORDS.size() - 1:
		for bj in GRID_COORDS.size() - 1:
			var x0: float = GRID_COORDS[bi]
			var x1: float = GRID_COORDS[bi + 1]
			var z0: float = GRID_COORDS[bj]
			var z1: float = GRID_COORDS[bj + 1]

			# 四角角楼：转角有楼，街道才闭合
			for c in 4:
				var dcx := rng.range(17.0, 22.0)
				var dcz := rng.range(17.0, 22.0)
				var ccx: float = (x0 + BLK_FRONT + dcx * 0.5) if (c == 0 or c == 3) \
						else (x1 - BLK_FRONT - dcx * 0.5)
				var ccz: float = (z0 + BLK_FRONT + dcz * 0.5) if (c == 0 or c == 1) \
						else (z1 - BLK_FRONT - dcz * 0.5)
				var ch: float = zone_h.call(ccx, ccz)
				put.call(ccx, ccz, dcx, dcz, ch * rng.range(0.80, 1.25))

			# 四条沿街排（同一排高度相近，真实街道就是这样）
			for e in 4:
				var horiz := e < 2
				var run_a: float = (x0 + BLK_CORNER) if horiz else (z0 + BLK_CORNER)
				var run_b: float = (x1 - BLK_CORNER) if horiz else (z1 - BLK_CORNER)
				var mid_x: float = (x0 + x1) * 0.5 if horiz else \
						((x0 + BLK_FRONT + 18.0) if e == 2 else (x1 - BLK_FRONT - 18.0))
				var mid_z: float = (((z0 + BLK_FRONT + 18.0) if e == 0 \
						else (z1 - BLK_FRONT - 18.0)) if horiz else (z0 + z1) * 0.5)
				var base_h: float = zone_h.call(mid_x, mid_z)
				var cur := run_a
				while cur < run_b - 12.0:
					var w := minf(rng.range(12.0, 30.0), run_b - cur)
					if w < 12.0:
						break
					var dep := rng.range(BLK_DEEP_MIN, BLK_DEEP_MAX)
					var bx: float
					var bz: float
					if horiz:
						bx = cur + w * 0.5
						bz = (z0 + BLK_FRONT + dep * 0.5) if e == 0 \
								else (z1 - BLK_FRONT - dep * 0.5)
					else:
						bz = cur + w * 0.5
						bx = (x0 + BLK_FRONT + dep * 0.5) if e == 2 \
								else (x1 - BLK_FRONT - dep * 0.5)
					var hh: float = base_h * rng.range(0.72, 1.32)
					if maxf(absf(bx), absf(bz)) < 300.0 and rng.next() < 0.10:
						hh *= 1.45          # 市中心偶尔冒一根超高
					put.call(bx, bz, w if horiz else dep, dep if horiz else w,
							minf(hh, 165.0))
					cur += w + rng.range(0.8, 4.5)

			# 街区内部低层填充（留出与沿街排的间距）
			var lo_x := x0 + BLK_CORNER + 18.0
			var hi_x := x1 - BLK_CORNER - 18.0
			var lo_z := z0 + BLK_CORNER + 18.0
			var hi_z := z1 - BLK_CORNER - 18.0
			if hi_x > lo_x and hi_z > lo_z:
				for k in int(rng.range(0.0, 2.6)):
					put.call(rng.range(lo_x, hi_x), rng.range(lo_z, hi_z),
							rng.range(12.0, 24.0), rng.range(12.0, 24.0),
							rng.range(7.0, 15.0))

	# ---- 城郊散点（网格外 900~1080 环带）----
	var occ := {}
	for guard in 2600:
		var sx := rng.range(-1080.0, 1080.0)
		var sz := rng.range(-1080.0, 1080.0)
		if absf(sx) < 905.0 and absf(sz) < 905.0:
			continue
		var cell := Vector2i(int(floor(sx / 56.0)), int(floor(sz / 56.0)))
		if occ.has(cell):
			continue
		occ[cell] = true
		put.call(sx, sz, rng.range(11.0, 20.0), rng.range(11.0, 20.0),
				rng.range(6.0, 15.0))

	if xfs.is_empty():
		return
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3.ONE
	bmesh.material = _building_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bmesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	print("[map] 楼 %d 体块（含退台/设备房）+ %d 天线" % [xfs.size(), ants.size()])

	if ants.is_empty():
		return
	var amesh := CylinderMesh.new()
	amesh.top_radius = 0.12
	amesh.bottom_radius = 0.30
	amesh.height = 1.0
	amesh.radial_segments = 6
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color("#3a3e44")
	amat.roughness = 0.7
	amesh.material = amat
	var amm := MultiMesh.new()
	amm.transform_format = MultiMesh.TRANSFORM_3D
	amm.mesh = amesh
	amm.instance_count = ants.size()
	for i in ants.size():
		amm.set_instance_transform(i, ants[i])
	var ammi := MultiMeshInstance3D.new()
	ammi.multimesh = amm
	ammi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ammi)


## 小地图贴图：整张路网俯视图（高架更亮，山海沙漠分区底色）
## 该点的楼体顶高（相机避让用）；无楼返回 0
func building_top(x: float, z: float) -> float:
	return float(_bld.get(Vector2i(int(floor(x / BLOCK_CELL)),
			int(floor(z / BLOCK_CELL))), 0.0))


func _build_minimap() -> void:
	var size := 600
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.17, 0.23, 0.15))   # 底色 = 草地（与 _zone_color 的兜底一致）
	# 分区底色的叠放顺序必须与 _zone_color 的判定优先级一致
	# （海 > 沙滩 > 沙漠 > 山地 > 城市），阈值也要对齐。
	# 原来先画海再用「整条北带」的山地盖上去，西北角世界里是海、
	# 小地图却是山地；东沙漠的阈值也写成 1080（实际是 950）。
	_fill_zone(img, size, -2800, 2800, -2800, -1080, Color(0.16, 0.26, 0.18))   # 北山地
	_fill_zone(img, size, 950, 2800, -2800, 2800, Color(0.66, 0.55, 0.35))      # 东沙漠
	_fill_zone(img, size, -1080, -980, -2800, 2800, Color(0.72, 0.66, 0.50))    # 西沙滩
	_fill_zone(img, size, -2800, -1080, -2800, 2800, Color(0.1, 0.28, 0.5))     # 西海
	_fill_zone(img, size, -950, 950, -950, 950, Color(0.2, 0.22, 0.26))         # 城市核心
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
