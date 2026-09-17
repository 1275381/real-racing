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

const FADE_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_tex = 0.0;
uniform vec3 albedo : source_color = vec3(0.6, 0.63, 0.66);
uniform float rough = 0.9;
uniform vec3 cam_w = vec3(0.0);
uniform vec3 plr_w = vec3(0.0);
uniform vec2 plr_dir = vec2(0.0, 1.0);  // 车头方向（XZ 单位向量）
uniform float fade_r = 5.5;     // 淡出半径（米）
uniform float over_en = 0.0;    // 1.0 = 高架类材质（主线桥面/箱梁/护栏/墩/梁）：启用前向走廊
uniform float over_y = 1.6;     // 通道二高度阈值（米，相对 plr_w）：护栏 0.9 / 其余高架类 0.3 / 路面类 1.6
uniform float over_r = 15.0;    // 头顶高架淡出：车周近距半径（米）
uniform float over_w = 14.5;    // 头顶高架淡出：前向走廊半宽（米）
uniform float over_len = 150.0; // 头顶高架淡出：前向走廊长度（米）

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fade = 0.0;
	// 通道一：只淡出「挡在相机与车之间、且不低于车所在高度」的片元。
	// 高度条件很关键：否则车正后方的路面自己会被打出洞。
	if (v_world.y > plr_w.y - 0.3) {
		vec3 d = plr_w - cam_w;
		float L = length(d);
		if (L > 0.5) {
			vec3 dir = d / L;
			float t = dot(v_world - cam_w, dir);
			if (t > 0.15 && t < L - 0.6) {
				float perp = length((v_world - cam_w) - dir * t);
				fade = 1.0 - smoothstep(fade_r * 0.45, fade_r, perp);
			}
		}
	}
	// 通道二：车顶上方的高架。通道一管不到它 —— 车在地面时高架横在
	// 前上方 7m+，到相机-车视线的垂距远超 fade_r，但它挡的是前方视野。
	// 分档（over_en/over_y）：路面类材质（地面街/匝道/拼块）只镂车周近距、
	// 阈值高 —— 前向走廊会把匝道自身的前方爬坡路面镂掉（60m 外坡道面
	// 已高于车 3m）；高架类材质（主线桥面/箱梁/护栏/墩/梁）永远不是
	// 「车脚下要开的路」，启用走廊 —— 车在匝道上时前方主线箱梁只比
	// 车高 1m，路面档 +1.6 够不着。护栏单独 +0.9：自身护栏顶（路面
	// +0.55）不镂，前方主线护栏（高差 ≥1.8m）镂。
	if (v_world.y > plr_w.y + over_y) {
		vec2 rel = v_world.xz - plr_w.xz;
		float f_near = 1.0 - smoothstep(over_r * 0.45, over_r, length(rel));
		// 走廊全镂区（0.75×over_w ≈ 10.9m）必须罩住桥面外缘（半宽10+梁0.45），
		// 否则桥两侧留一条只镂一半的边带，透视收缩后远看像「远处恢复实心」。
		vec2 dir = normalize(plr_dir);
		float fwd = dot(rel, dir);
		float lat = abs(dot(rel, vec2(-dir.y, dir.x)));
		float f_corr = over_en
				* (1.0 - smoothstep(over_w * 0.75, over_w, lat))
				* (1.0 - smoothstep(over_len * 0.75, over_len, max(fwd, 0.0)))
				// 原为 step(-6.0, fwd)：车后 6m 处一条随转向扫动的锐利切边
				* smoothstep(-10.0, -4.0, fwd);
		fade = max(fade, max(f_near, f_corr));
	}
	if (fade > 0.02) {
		vec2 fp = mod(FRAGCOORD.xy, 4.0);
		int bi = int(fp.y) * 4 + int(fp.x);
		float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
				3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if (fade > (m[bi] + 0.5) / 16.0) {
			discard;
		}
	}
	ALBEDO = mix(albedo, texture(tex, UV).rgb * albedo, use_tex);
	ROUGHNESS = rough;
	SPECULAR = 0.08;
}
"""


const BLK_FRONT := 13.0      # 楼正面距街道中心线：街半宽 8 + 人行道 2.2 + 退让 2.8
const BLK_DEEP_MIN := 14.0
const BLK_DEEP_MAX := 22.0
const BLK_CORNER := 35.0     # ≈ BLK_FRONT + BLK_DEEP_MAX：转角楼与沿街排不重叠

var roads: Array[Road] = []
var n := 0                 # 采样总数（vehicle 进度计算用）
var ds := SAMPLE_DS
var start_idx := 0
var wall_lat := 9.0
var soft_walls_enabled := false   # 自由漫游：路边软墙关闭（越野自由）
var closed := true                # 漫游路网视为闭环（vehicle 开线判定用不到，占位兼容）
var _obst_hit := 0.0              # 本帧障碍撞击强度（供音效/震屏消费）
var minimap_tex: ImageTexture
var vehicle_y := 0.0       # 由 game 每帧写入（高度选层迟滞用）

# —— 卷帘门车库（漫游出生点）：x=180 街东侧、z=-540 街北侧的沿街地块，
# 西门洞正对 x=180 街；楼体不压任何路面（南缘距 z=-540 街中心 13m）——
const GAR_C := Vector2(198.5, -520.0)   # 车库中心（= 楼底层的中心）

# —— 配件店（自由漫游可进入购买）：中心广场 (34,34)，西门洞/店门朝路口 ——
const SHOP_POS := Vector2(34.0, 34.0)       # 配件店建筑中心（小地图标记用）
const SHOP_DOOR := Vector2(21.0, 34.0)      # 店门口（进入判定点）

# —— 枪械店（独立建筑，广场另一角）——
const GUNSHOP_POS := Vector2(-46.0, 46.0)   # 枪械店建筑中心（小地图「枪」标记用）

# ---- 机场与远方城市 ----
const AIRPORT_POS := Vector2(-1900.0, -400.0)   # 城市机场（西郊平地，避开沙漠岩山）
const AIRPORT_HEADING := -0.35                   # 跑道朝向（弧度）
const FAR_CITY_POS := Vector2(8200.0, 6600.0)    # 远方城市中心（只飞得到）
const FAR_CITY_HEADING := 0.75
const FAR_CITY_HALF := 1050.0                    # 远城半径（边界钳制用）
const WORLD_LIMIT := 16000.0                     # 战机可达世界边界

## 铺装区（机场坪面/远城街道）：query 回退时表面按道路计算，不再当草地减速
var road_pads: Array = []

## 门系统：leaves 为叶片节点（含铰链/滑轨动画），obs_i 指向 obstacles_box 的门板碰撞
var doors: Array = []
var doors_player_pos := Vector3.ZERO
const GUNSHOP_DOOR := Vector2(-33.0, 46.0)  # 店门口（进入判定点，朝东）
const GUNSHOP_W := 20.0
const GUNSHOP_D := 14.0
const GUNSHOP_H := 8.0
const SHOP_W := 20.0
const SHOP_D := 14.0
const SHOP_H := 8.0
const GAR_W := 16.0
const GAR_D := 14.0
const GAR_H := 5.5
const GAR_DOOR_H := 4.6                 # 门洞净高
const GAR_DOOR_HW := 4.0                # 门洞半宽（z 向 8m 通畅）
var _door_panel: MeshInstance3D         # 卷帘门板（升起 = 底边收进门楣）
var _door_base_y := 0.0
var _door_open := 0.0                   # 0=落下 1=全开
var _door_piece := {}                   # 门体碰撞块（关门时才在 obstacles_box 里）

var _sig_mats: Array = []  # [{"r": mat, "y": mat, "g": mat}] × 2 组
var _block := {}           # 24m 网格：距任意道路中心线过近的建筑禁建区（预计算）
var obstacles_box := []    # 楼房碰撞体 [{c: Vector2, hx, hz, rot}]（含旋转的 OBB）
var _terr := {}            # 50m 网格：地形高程场（盘山公路下方的山脊）
var _fade_shader: Shader
var _fade_mats: Array = []   # 需要每帧写入相机/车位的遮挡淡出材质
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
	var mono := false                     # 等高主线高架（环线/快速路）：桥面单独材质走淡出走廊档
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
	_build_airport(AIRPORT_POS, AIRPORT_HEADING)
	_build_far_city()
	print("[map] 路网采样 %d 点 %dms" % [n, Time.get_ticks_msec() - t0])
	_mark_road_blocks()
	_build_road_meshes()
	print("[map] 路面网格 %dms" % [Time.get_ticks_msec() - t0])
	_build_merge_fills()
	_build_zones()
	print("[map] 区域场景 %dms" % [Time.get_ticks_msec() - t0])
	_build_intersections()
	print("[map] 路口 %dms" % [Time.get_ticks_msec() - t0])
	_place_buildings()
	print("[map] 建筑 %dms" % [Time.get_ticks_msec() - t0])
	_make_garage()
	_make_parts_shop()
	_make_gunshop()
	_build_minimap()
	print("[map] 完成 %dms" % [Time.get_ticks_msec() - t0])


func _make_road(cps: Array, ys: Array, closed: bool, half_w: float, elevated: bool) -> Road:
	var road := Road.new()
	road.half_w = half_w
	road.closed = closed
	road.elevated = elevated
	# 等高主线高架（环线/两条快速路）：桥面与匝道/地面街分材质 —— 匝道
	# 桥面是「车要开上去的路」，不能进前向走廊；主线桥面是遮挡物，要进。
	road.mono = elevated and (closed or ys.size() == 1)
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
		# 并线尾段：沿环线外侧平行。样条会把标称间距拉回约 2m（实测 18.5 名义
		# 只剩 14.8 实际，< 半宽和 16 仍同高重叠闪烁）—— 标称取 20.5，
		# 实际 ≈16.8 > 16，边对边不叠面。
		var merge_c := rxz + outward * 20.5
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
	# 接到 x=-180 那条街，而不是 x=0 —— 盘山公路正是从 (0,-900) 起步，
	# 原来两条路在那里重合约 100m 且高差 0.6m，车开过去会陷进路面
	_make_road([Vector2(-1040, -1150), Vector2(-880, -1150), Vector2(-300, -1140),
			Vector2(-180, -1010), Vector2(-180, -900)], [0.03], false, 6.0, false)
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


## 出生点：卷帘门车库内（x=180 街东侧），车头朝西正对门洞——
## 菜单按 W/↑ 或点「自由漫游」进来后，踩油门顶开卷帘门即出发
func get_spawn() -> Dictionary:
	return {"pos": Vector3(GAR_C.x, _street_h(6, false), GAR_C.y),
			"heading": -PI * 0.5}


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


func query(x: float, z: float, hint, vy: float = -1.0e9) -> Dictionary:
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
		# 注意 road.grid 只索引偶数下标采样，bi 取不到 cnt-1 ——
		# 判据必须放宽到「靠近任一端」，纵向过冲再按真实端点算
		if not road.closed and (bi <= 1 or bi >= road.pts.size() - 2):
			var ei: int = 0 if bi <= 1 else road.pts.size() - 1
			var ep := road.pts[ei]
			var tv := Vector2(sin(road.ang[ei]), cos(road.ang[ei]))
			var lon: float = (x - ep.x) * tv.x + (z - ep.z) * tv.y
			var over: float = (-lon) if ei == 0 else lon
			if over > 0.0:
				dist += over * 10.0
		var vyy: float = vy if vy > -1.0e8 else vehicle_y
		var cost := dist + absf(road.pts[bi].y - vyy) * 6.0   # 高度迟滞
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
		# 越野高度必须取地形高程：地面网格已按 _terr 抬起（盘山一带到 72m），
		# 这里再返回 0 的话车会从山体内部穿过去，进入某条路的判定范围时
		# 又被一帧抬升几十米
		_scratch["height"] = terrain_height(x, z)
		# 铺装区覆写（机场坪面/远城街道/地下车库地坪/货机坡道）：草地按道路计
		# 多层重叠时取面积最小（最具体）的一层；vy 差 3m 以上不匹配（地下/地表互不误判）
		var best_pad = null
		var best_area := INF
		var best_hgt := INF
		for pad in road_pads:
			var pdx: float = x - (pad["c"] as Vector2).x
			var pdz: float = z - (pad["c"] as Vector2).y
			var pla: float = pdx * float(pad["fx"]) + pdz * float(pad["fz"])
			var pll: float = pdx * float(pad["fz"]) - pdz * float(pad["fx"])
			if absf(pla) > float(pad["hf"]) or absf(pll) > float(pad["hl"]):
				continue
			var hgt: float = float(pad["y"])
			if pad.has("y2"):
				var tt: float = clampf((pla / float(pad["hf"]) + 1.0) * 0.5,
						0.0, 1.0)
				hgt = lerpf(float(pad["y"]), float(pad["y2"]), tt)
			if vy > -1.0e8 and absf(vy - hgt) > 3.0:
				continue   # 车辆高度与该层差太多（地下/地表/空中互不误判）
			var area: float = float(pad["hf"]) * float(pad["hl"])
			if area < best_area:
				best_area = area
				best_pad = pad
				best_hgt = hgt
		if best_pad != null:
			_scratch["surf"] = "road"
			_scratch["height"] = best_hgt
			_scratch["lat_off"] = 0.0
			_scratch["wall"] = 100000.0   # 铺装区无软墙
		# 返回必须在草地区块内部：曾经缩进掉到区块外，把后面的整段
		# 道路分支变成死代码——桥面高度/路面坡度/道路朝向全部失效，
		# 所有道路查询都回落到预置默认值（高度 0），高架与坡道全废
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
	# 软墙抑制：best_road 会推挤，但车其实还在另一条「同标高」邻近道路的
	# 走廊之内 —— 这时改用那条路来报（换参照系），而不是把 wall 放宽。
	# 贴着软墙过十字路口时 hint 粘性会让车穿过后仍挂在横街上，横街的
	# 横向轴于是变成一道纵向栅栏，把车正面撞停（实测 +22.6 → -6.3 m/s）。
	#
	# 两个关键约束：
	# · 高度阈值必须收到车身量级（0.6m）。放宽到 3m 会把环线护栏一起关掉 ——
	#   4 条环线匝道从环线正下方仅 0.9~2.4m 处穿过，会被误判为「同层」。
	# · 只换参照系、不放宽 wall。原来写 wall = al + 2.0 是无上限值，
	#   抑制失效那一帧会把车横向瞬移好几米。
	if al > wall:
		for rr2 in road_cost:
			if rr2 == best_road or road_cost[rr2] > best_cost + 12.0:
				continue
			var o: Road = roads[rr2]
			var oi: int = road_bi[rr2]
			var op := o.pts[oi]
			if absf(op.y - p.y) > 0.6:
				continue
			var ol := o.left[oi]
			var olat: float = (x - op.x) * ol.x + (z - op.z) * ol.y
			if absf(olat) <= o.wall:
				best_road = rr2
				best_i = oi
				road = o
				p = op
				l = ol
				lat = olat
				al = absf(olat)
				break
	_scratch["idx"] = best_road * 100000 + best_i
	_scratch["road"] = best_road
	_scratch["lat_off"] = lat
	_scratch["ang"] = road.ang[best_i]
	_scratch["height"] = p.y
	_scratch["slope"] = road.slope[best_i]
	if not soft_walls_enabled:
		wall = 100000.0   # 自由漫游：路边无空气墙
	_scratch["wall"] = wall
	_scratch["surf"] = "grass" if al > road.half_w + 1.2 \
			else ("curb" if al > road.half_w else "road")
	# 铺装区覆写（机场坪面/远城街道/地下车库地坪）：草地按道路计
	if _scratch["surf"] == "grass":
		for pad in road_pads:
			var pdx: float = x - (pad["c"] as Vector2).x
			var pdz: float = z - (pad["c"] as Vector2).y
			if vy > -1.0e8 and absf(vy - float(pad["y"])) > 3.0:
				continue   # 车辆高度与该铺装层差太多（地下/地表互不误判）
			var pla: float = pdx * float(pad["fx"]) + pdz * float(pad["fz"])
			var pll: float = pdx * float(pad["fz"]) - pdz * float(pad["fx"])
			if absf(pla) <= float(pad["hf"]) and absf(pll) <= float(pad["hl"]):
				_scratch["surf"] = "road"
				_scratch["height"] = float(pad["y"])
				_scratch["lat_off"] = 0.0
				_scratch["wall"] = 100000.0
				break
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


## 自由漫游障碍碰撞：车辆圆 vs 楼房 OBB / 高架桥墩圆柱。
## 推出障碍并按法向速度反弹（撞强置 hit_impulse 驱动音效/震屏）
func resolve_obstacles(v: Vehicle) -> void:
	_obst_hit = 0.0   # 每帧重置：hit_impulse 只反映「本帧」的新撞击
	var r := 1.5
	# 楼房 OBB（粗过滤：中心距 < 楼对角 + 车半径）
	for ob in obstacles_box:
		var dx: float = v.pos.x - ob["c"].x
		var dz: float = v.pos.z - ob["c"].y
		if dx * dx + dz * dz > 90.0 * 90.0:
			continue
		var ca: float = cos(ob["rot"])
		var sa: float = sin(ob["rot"])
		var lx: float = ca * dx + sa * dz
		var lz: float = -sa * dx + ca * dz
		var cx := clampf(lx, -ob["hx"], ob["hx"])
		var cz := clampf(lz, -ob["hz"], ob["hz"])
		var ddx := lx - cx
		var ddz := lz - cz
		var d2 := ddx * ddx + ddz * ddz
		if d2 > r * r:
			continue
		var d := sqrt(d2)
		var n_lx: float
		var n_lz: float
		if d > 0.001:
			n_lx = ddx / d
			n_lz = ddz / d
		else:   # 车心在楼内：沿最浅轴推出
			var px: float = ob["hx"] - absf(lx)
			var pz: float = ob["hz"] - absf(lz)
			if px < pz:
				n_lx = signf(lx) if lx != 0.0 else 1.0
				n_lz = 0.0
			else:
				n_lx = 0.0
				n_lz = signf(lz) if lz != 0.0 else 1.0
			d = maxf(d, 0.01)
		var wx: float = ca * n_lx - sa * n_lz
		var wz: float = sa * n_lx + ca * n_lz
		var push: float = r - d
		v.pos.x += wx * push
		v.pos.z += wz * push
		_obstacle_bounce(v, wx, wz)
	# 高架桥墩（pillar_pts 已含门式墩双柱）。
	# 高度判定：车在柱顶以上（桥面上开车）时柱子在脚下，不参与碰撞——
	# 原来纯 2D 圆柱判定，桥面行驶压过桥墩正上方会被当成撞柱推停
	for pp in pillar_pts:
		if v.pos.y > pp.y - 1.0:
			continue
		var dx: float = v.pos.x - pp.x
		var dz: float = v.pos.z - pp.z
		var rr: float = 1.5 + r
		var d2 := dx * dx + dz * dz
		if d2 > rr * rr or d2 < 1e-6:
			continue
		var d := sqrt(d2)
		var nx := dx / d
		var nz := dz / d
		var push := rr - d
		v.pos.x += nx * push
		v.pos.z += nz * push
		_obstacle_bounce(v, nx, nz)
	v.hit_impulse = maxf(v.hit_impulse, _obst_hit)


func _obstacle_bounce(v: Vehicle, nx: float, nz: float) -> void:
	var s := sin(v.heading)
	var c := cos(v.heading)
	var vx: float = s * v.vf + c * v.vl
	var vz: float = c * v.vf - s * v.vl
	var vn := vx * nx + vz * nz
	if vn >= 0.0:
		return
	vx -= nx * vn * 0.3   # 30% 回弹：撞一下弹开，不反复撞击
	vz -= nz * vn * 0.3
	v.vf = vx * s + vz * c
	v.vl = vx * c - vz * s
	# 只有明显的撞击（法向 closing > 2m/s）才记为撞墙反馈，
	# 顶住/轻蹭不触发音效震屏 —— 否则贴着障碍会持续震动不停
	if absf(vn) > 2.0:
		_obst_hit = maxf(_obst_hit, minf(absf(vn) / 13.0, 1.0))


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
var _u_pos := PackedVector3Array()
var _u_nrm := PackedVector3Array()
var _u_col := PackedColorArray()
var _u_uv := PackedVector2Array()
var _d_pos := PackedVector3Array()
var _d_nrm := PackedVector3Array()
var _e_pos := PackedVector3Array()   # 匝道箱梁：不进前向走廊
var _e_nrm := PackedVector3Array()


func _mono_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2) -> void:
	_u_pos.append(a)
	_u_pos.append(c)
	_u_pos.append(b)
	_u_pos.append(a)
	_u_pos.append(d)
	_u_pos.append(c)
	for i in 6:
		_u_nrm.append(nrm)
		_u_col.append(Color.WHITE)
	_u_uv.append(uv_a)
	_u_uv.append(uv_c)
	_u_uv.append(uv_b)
	_u_uv.append(uv_a)
	_u_uv.append(uv_d)
	_u_uv.append(uv_c)


func _flush_mono(mat: Material) -> void:
	if _u_pos.is_empty():
		return
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _u_pos
	arrays[Mesh.ARRAY_NORMAL] = _u_nrm
	arrays[Mesh.ARRAY_COLOR] = _u_col
	arrays[Mesh.ARRAY_TEX_UV] = _u_uv
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	add_child(mi)
	_u_pos = PackedVector3Array()
	_u_nrm = PackedVector3Array()
	_u_col = PackedColorArray()
	_u_uv = PackedVector2Array()


## 遮挡淡出材质：挡在「相机 → 车」之间、且不低于车高的片元按 4×4 有序抖动
## 逐步丢弃。用 discard 而不是半透明，是为了留在不透明管线里、深度正确，
## 避免整块路面/桥体进透明队列后自相排序错乱。
## 所有可能挡住车的表面都必须用它 —— 沥青路面本身也会挡（车在匝道上、
## 环线就在头顶 1.8m 时，相机已经在环线上方，环线路面横在中间）。


func _deck_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3,
		hi := true) -> void:
	# hi = 主线高架（环线 / 快速路）；匝道单独一批，否则前向走廊会把车
	# 自己正要开上去的那段匝道的箱梁抹掉
	for v in [a, c, b, a, d, c]:
		if hi:
			_d_pos.append(v)
			_d_nrm.append(nrm)
		else:
			_e_pos.append(v)
			_e_nrm.append(nrm)


func _flush_deck(mat: Material, hi := true) -> void:
	var pos := _d_pos if hi else _e_pos
	var nrm := _d_nrm if hi else _e_nrm
	if pos.is_empty():
		return
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	if hi:
		_d_pos = PackedVector3Array()
		_d_nrm = PackedVector3Array()
	else:
		_e_pos = PackedVector3Array()
		_e_nrm = PackedVector3Array()


## 遮挡淡出材质：挡在「相机 → 车」之间、且不低于车高的片元按 4×4 有序抖动
## 逐步丢弃。用 discard 而不是半透明，是为了留在不透明管线里、深度正确，
## 避免整块路面/桥体进透明队列后自相排序错乱。
## 所有可能挡住车的表面都必须用它 —— 沥青路面本身也会挡（车在匝道上、
## 环线就在头顶 1.8m 时，相机已经在环线上方，环线路面横在中间）。
func _fade_material(col: Color, tex: Texture2D = null, rough := 0.9,
		over_en := false, over_y := 1.6) -> ShaderMaterial:
	if _fade_shader == null:
		_fade_shader = Shader.new()
		_fade_shader.code = FADE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _fade_shader
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("over_en", 1.0 if over_en else 0.0)
	m.set_shader_parameter("over_y", over_y)
	if tex != null:
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("use_tex", 1.0)
	_fade_mats.append(m)
	return m


## 每帧由 game 写入相机与车的世界坐标、车头方向（XZ 单位向量）
func update_occluder_fade(cam_pos: Vector3, plr_pos: Vector3,
		plr_dir := Vector2(0.0, 1.0)) -> void:
	for m in _fade_mats:
		(m as ShaderMaterial).set_shader_parameter("cam_w", cam_pos)
		(m as ShaderMaterial).set_shader_parameter("plr_w", plr_pos)
		(m as ShaderMaterial).set_shader_parameter("plr_dir", plr_dir)


func _build_road_meshes() -> void:
	_mark_rail_skips()
	_mark_surf_skips()
	# 淡出分档（见 FADE_SHADER 通道二）：
	#   路面类（over_en=0, +1.6）：地面街 / 匝道 / 城外公路路面 —— 匝道前方
	#     爬坡路面是「车要开的路」，绝不能进前向走廊；
	#   主线桥面（+0.3）：环线 / 快速路桥面 —— 是遮挡物，车在地面或匝道上
	#     时它横在前上方，必须低阈值 + 走廊（车在匝道上时它只比车高 1m）；
	#   箱梁 / 桥墩 / 门式墩横梁（+0.3）：同上，匝道自身箱梁因高差 <1m 不触发；
	#   护栏（+0.9）：自身护栏顶 = 路面+0.55，不镂；前方主线护栏高差 ≥1.8m，镂。
	# 护栏颜色用沥青贴图：历史上护栏 quads 一直混在路面批里呈深灰色，
	# 用户从未见过「白色护栏」；按设计色 #c9ced4 渲染会显得沿路一圈突兀的
	# 白条（用户要求去掉）。这里保持与旧观感一致，仅保留独立材质与淡出档。
	# 注：人行道 / 护栏必须各自单独 flush —— 原来 _quad 共用一套累积数组，
	# 循环后连续 _flush(road/walk/rail) 只有第一个拿到几何，人行道和护栏
	# 全混进了路面 mesh（walk/rail 材质从未生效，护栏还因此走错淡出档）。
	var road_mat := _fade_material(Color.WHITE, RRTextures.asphalt(), 0.92)
	var hi_mat := _fade_material(Color.WHITE, RRTextures.asphalt(), 0.92, true, 0.3)
	var walk_mat := _fade_material(Color("#787e88"))
	# 桥体（箱梁底板 + 腹板）：路面四边形是单面的，站在桥下抬头看是空的 ——
	# 必须补出底面与侧面，否则高架就是一张飘着的纸。
	# 但桥体一旦挡在相机与车之间，车就看不见了。这里不动相机（挪相机会
	# 让视距忽远忽近），改成让挡住的那部分桥体自己淡出。
	# 主线（mono）与匝道两套：匝道是「车脚下正在开的路」，不能进前向走廊
	var deck_mat := _fade_material(Color("#9aa0a8"), null, 0.9, true, 0.3)
	var deck_lo_mat := _fade_material(Color("#9aa0a8"), null, 0.9, false, 1.6)
	# 护栏用纯沥青色。原来挂 asphalt() 贴图，但护栏 quad 一个 UV 都没写，
	# 全是 (0,0)，实际只采到贴图角上一个 texel —— 等价于纯色，白挂一张图
	var rail_mat := _fade_material(Color("#33353a"), null, 0.92, true, 0.9)
	var rail_lo_mat := _fade_material(Color("#33353a"), null, 0.92, false, 1.6)

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
			# 网格街在路口处裁剪：路面裁到 ±GRID_HALF_W，
			# 空出来的方块与四个转角由 _build_intersections 精确填上。
			var sp_r := Vector2(0.0, 1.0)
			if road.xsec_cut:
				var sa: float = pi.x if road.along_x else pi.z
				var sb: float = pj.x if road.along_x else pj.z
				sp_r = _xsec_span(sa, sb, GRID_HALF_W)
			# 主路面（同层共面重叠段跳过：由覆盖路面的沥青接管，如高架十字交叉）
			if sp_r.x < sp_r.y and (road.surf_skip.size() != cnt
					or not (road.surf_skip[i] or road.surf_skip[j])):
				var ra := pi.lerp(pj, sp_r.x)
				var rb := pi.lerp(pj, sp_r.y)
				var rla := li.lerp(lj, sp_r.x)
				var rlb := li.lerp(lj, sp_r.y)
				var ru0 := lerpf(u0, u1, sp_r.x)
				var ru1 := lerpf(u0, u1, sp_r.y)
				if road.mono:
					_mono_quad(
						ra + Vector3(-rla.x * w, 0, -rla.y * w),
						rb + Vector3(-rlb.x * w, 0, -rlb.y * w),
						rb + Vector3(rlb.x * w, 0, rlb.y * w),
						ra + Vector3(rla.x * w, 0, rla.y * w),
						Vector3.UP,
						Vector2(0, ru0), Vector2(0, ru1), Vector2(1, ru1), Vector2(1, ru0))
				else:
					_quad(
						ra + Vector3(-rla.x * w, 0, -rla.y * w),
						rb + Vector3(-rlb.x * w, 0, -rlb.y * w),
						rb + Vector3(rlb.x * w, 0, rlb.y * w),
						ra + Vector3(rla.x * w, 0, rla.y * w),
						Vector3.UP, Color.WHITE,
						Vector2(0, ru0), Vector2(0, ru1), Vector2(1, ru1), Vector2(1, ru0))
			# 离地不足 2m 的桥段不建箱梁：那里等于平地路，底板既无意义
			# 又会在视线高度横出一片白板
			if road.elevated and minf(pi.y, pj.y) > 2.0 \
					and (road.surf_skip.size() != cnt
					or not (road.surf_skip[i] or road.surf_skip[j])):
				# 箱梁：底板（朝下）+ 两侧腹板，厚 0.7m，稍宽于路面
				var dt := 0.7
				var eo := w + 0.45
				var s0 := pi + Vector3(-li.x * eo, -dt, -li.y * eo)
				var s1 := pj + Vector3(-lj.x * eo, -dt, -lj.y * eo)
				var s2 := pj + Vector3(lj.x * eo, -dt, lj.y * eo)
				var s3 := pi + Vector3(li.x * eo, -dt, li.y * eo)
				_deck_quad(s3, s2, s1, s0, Vector3.DOWN, road.mono)
				for side in [-1.0, 1.0]:
					var o: float = eo * side
					var t0 := pi + Vector3(li.x * o, 0.05, li.y * o)
					var t1 := pj + Vector3(lj.x * o, 0.05, lj.y * o)
					var b0 := pi + Vector3(li.x * o, -dt, li.y * o)
					var b1 := pj + Vector3(lj.x * o, -dt, lj.y * o)
					_deck_quad(b0, b1, t1, t0, Vector3(li.x * side, 0, li.y * side),
							road.mono)
	_flush(road_mat)
	_flush_mono(hi_mat)
	_flush_deck(deck_mat, true)
	_flush_deck(deck_lo_mat, false)

	# 高架防撞墙：0.55m 高实体墙（内壁 + 顶面 + 外壁），哑光混凝土。
	# 单独一遍循环、单独 flush —— 原来护栏与人行道混进路面批，
	# rail/walk 材质的 flush 拿到空数组从未生效（护栏色错、淡出档也错）。
	for road in roads:
		if not road.elevated or not road.mono:
			continue
		var rc := road.pts.size()
		for i in (rc if road.closed else rc - 1):
			var j := (i + 1) % rc
			var pi := road.pts[i]
			var pj := road.pts[j]
			var li := road.left[i]
			var lj := road.left[j]
			var w := road.half_w
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
				_quad(a, b, bi, ai, n_in, Color.WHITE)
				_quad(a2, b2, bo, ao, n_out, Color.WHITE)
				_quad(ai, bi, bo, ao, Vector3.UP, Color.WHITE)
	_flush(rail_mat)

	# 同上，但只建匝道的护栏 —— 匝道护栏不进前向走廊。
	# 单独一遍循环、单独 flush —— 原来护栏与人行道混进路面批，
	# rail/walk 材质的 flush 拿到空数组从未生效（护栏色错、淡出档也错）。
	for road in roads:
		if not road.elevated or road.mono:
			continue
		var rc := road.pts.size()
		for i in (rc if road.closed else rc - 1):
			var j := (i + 1) % rc
			var pi := road.pts[i]
			var pj := road.pts[j]
			var li := road.left[i]
			var lj := road.left[j]
			var w := road.half_w
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
				_quad(a, b, bi, ai, n_in, Color.WHITE)
				_quad(a2, b2, bo, ao, n_out, Color.WHITE)
				_quad(ai, bi, bo, ao, Vector3.UP, Color.WHITE)
	_flush(rail_lo_mat)

	# 路缘人行道（略高于路面，非高架路才有）：单独一批，原因同上。
	# 网格街的人行道裁到 ±(GRID_HALF_W+2.2)，与路面裁剪边界不同，
	# 否则两条街的人行道会在转角互相叠面。
	for road in roads:
		if road.elevated:
			continue
		var wc := road.pts.size()
		for i in (wc if road.closed else wc - 1):
			var j := (i + 1) % wc
			var pi := road.pts[i]
			var pj := road.pts[j]
			var li := road.left[i]
			var lj := road.left[j]
			var w := road.half_w
			var sp_w := Vector2(0.0, 1.0)
			if road.xsec_cut:
				var sa: float = pi.x if road.along_x else pi.z
				var sb: float = pj.x if road.along_x else pj.z
				sp_w = _xsec_span(sa, sb, GRID_HALF_W + 2.2)
			if sp_w.x >= sp_w.y:
				continue
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
	_flush(walk_mat)

	# 高架桥墩（每 ~45m 一根，从地面顶到桥面）
	var pillar_mat := _fade_material(Color("#8f959c"), null, 0.85, true, 0.3)
	var pillar_lo_mat := _fade_material(Color("#8f959c"), null, 0.85, false, 1.6)
	# 桥墩：优先桥下中央单柱；正下方是马路时改成门式墩（两侧立柱 + 横梁），
	# 两侧也让不开才沿桥前后挪，最后才放弃。
	# 原来完全不做检查，桥墩会立在路口正中、也会穿过下层桥面；
	# 而只做「被占就跳过」又会让两条正压在街道上方的快速路一根柱子都不剩。
	var pillar_list: Array[Transform3D] = []
	var beam_list: Array[Transform3D] = []
	var pillar_lo: Array[Transform3D] = []
	var beam_lo: Array[Transform3D] = []
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
					var plist: Array[Transform3D] = pillar_list if road.mono else pillar_lo
					var blist: Array[Transform3D] = beam_list if road.mono else beam_lo
					if not _pillar_blocked(road, p):
						# 柱顶收进桥面下方 0.9m（藏在箱梁里）：原来顶到路面标高，
						# 竖曲率凸段/采样间隙会把柱头戳出桥面，车直接撞柱卡死
						var ph: float = p.y - 0.9
						plist.append(Transform3D(Basis.from_scale(Vector3(1, ph, 1)),
								Vector3(p.x, ph * 0.5, p.z)))
						pillar_pts.append(Vector3(p.x, ph, p.z))
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
							plist.append(Transform3D(Basis.from_scale(Vector3(1, ch, 1)),
									Vector3(c.x, ch * 0.5, c.z)))
							pillar_pts.append(Vector3(c.x, ch, c.z))
						# 横梁：沿横向跨过桥面，藏在桥底
						var bx := Vector3(lat.x, 0, lat.y) * (off * 2.0 + 1.4)
						var bz := Vector3(-lat.y, 0, lat.x) * 1.8
						blist.append(Transform3D(Basis(bx, Vector3(0, 1.0, 0), bz),
								Vector3(p.x, p.y - 0.6, p.z)))
						placed = true
						break
				idx = mini(idx + 3, cnt - 1)
			if not placed:
				continue
	# 主线与匝道各一批：匝道的墩/梁不进前向走廊，否则车爬匝道时
	# 前方自己的桥墩会被抹掉，桥面变成没有柱子的悬空带
	for pack in [[pillar_list, pillar_mat], [pillar_lo, pillar_lo_mat]]:
		var plist: Array = pack[0]
		if plist.is_empty():
			continue
		var pm := CylinderMesh.new()
		pm.top_radius = 1.1
		pm.bottom_radius = 1.5
		pm.height = 1.0
		pm.material = pack[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pm
		mm.instance_count = plist.size()
		for i in plist.size():
			mm.set_instance_transform(i, plist[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	for pack in [[beam_list, pillar_mat], [beam_lo, pillar_lo_mat]]:
		var blist: Array = pack[0]
		if blist.is_empty():
			continue
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3.ONE
		beam_mesh.material = pack[1]
		var bmm := MultiMesh.new()
		bmm.transform_format = MultiMesh.TRANSFORM_3D
		bmm.mesh = beam_mesh
		bmm.instance_count = blist.size()
		for i in blist.size():
			bmm.set_instance_transform(i, blist[i])
		var bmmi := MultiMeshInstance3D.new()
		bmmi.multimesh = bmm
		add_child(bmmi)
	print("[map] 桥墩 %d 根（主线 %d + 匝道 %d，含门式墩）+ 横梁 %d 道"
			% [pillar_list.size() + pillar_lo.size(), pillar_list.size(),
			pillar_lo.size(), beam_list.size() + beam_lo.size()])


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
	# 机场平地（西郊）从海里挖开：整块水面盖过机场时，坪面/跑道只高出水面
	# 8~12cm，中远距离深度精度不够，机场一带的路面会与水面闪烁。
	# 豁口矩形比 _zone_color 的机场草地矩形四边各外扩 30m，水线内永远
	# 压着草地色海床，不会露出蓝色旱地。
	var ocean := StandardMaterial3D.new()
	ocean.albedo_color = Color(0.1, 0.33, 0.56)
	ocean.metallic = 0.35
	ocean.roughness = 0.12
	_ground_plane(2220, 9600, null, Color.WHITE, 1.0, Vector2(-3490, 0.02), 0.02, ocean)
	_ground_plane(1300, 4290, null, Color.WHITE, 1.0, Vector2(-1730, 2655.0), 0.02, ocean)
	_ground_plane(1300, 3530, null, Color.WHITE, 1.0, Vector2(-1730, -3035.0), 0.02, ocean)
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


## 地形高程（双线性插值，与 _build_zone_ground 建出的可见网格一致）。
## _terrain_h 是「取最近格」，只适合建面顶点（顶点正好落在格心）；
## 物理查询落在格与格之间，必须插值，否则地板是 50m 的台阶。
## ================= 机场与远方城市 =================

## 机场：跑道/滑行道/停机坪/航站楼/塔台（center=机场中心，heading=跑道朝向）
func _build_airport(center: Vector2, heading: float) -> void:
	var base_y := terrain_height(center.x, center.y) + 0.04
	var fwd := Vector2(sin(heading), cos(heading))
	var right := Vector2(cos(heading), -sin(heading))
	var put := func(px: float, pz: float, sx: float, sz: float, sy: float,
			mat: Material, col := Color.WHITE, y_off := 0.0) -> void:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(sx, maxf(sy, 0.05), sz)
		mesh.material = mat
		mi.mesh = mesh
		mi.position = Vector3(px, base_y + y_off + sy * 0.5, pz)
		mi.rotation.y = heading     # 局部 +X 对齐跑道方向
		add_child(mi)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = RRTextures.asphalt_plain()
	asphalt.roughness = 0.94
	var conc := StandardMaterial3D.new()
	conc.albedo_texture = RRTextures.concrete()
	conc.roughness = 0.92
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.93, 0.95)
	white.roughness = 0.8
	var to_local := func(lx: float, ly: float) -> Vector2:
		return center + fwd * lx + right * ly
	# 停机坪整体垫层（跑道 + 联络道范围）
	var pad_c: Vector2 = to_local.call(0.0, 60.0)
	put.call(pad_c.x, pad_c.y, 1500.0, 400.0, 0.06, conc)
	road_pads.append({"c": pad_c, "fx": fwd.x, "fz": fwd.y,
			"hf": 750.0, "hl": 200.0, "y": base_y + 0.06})
	# 跑道 1300×46
	var rw_c: Vector2 = to_local.call(0.0, 0.0)
	put.call(rw_c.x, rw_c.y, 1300.0, 46.0, 0.09, asphalt)
	# 跑道中线虚线
	for k in 26:
		var lx := -624.0 + k * 48.0
		var mc: Vector2 = to_local.call(lx, 0.0)
		put.call(mc.x, mc.y, 22.0, 1.1, 0.105, white, Color.WHITE, 0.005)
	# 两端斑马线
	for end_i in 2:
		var ex := -640.0 if end_i == 0 else 640.0
		for k in 6:
			var sc: Vector2 = to_local.call(ex, -15.0 + k * 6.0)
			put.call(sc.x, sc.y, 30.0, 2.2, 0.105, white, Color.WHITE, 0.005)
	# 平行滑行道 + 3 条联络道
	var tw_c: Vector2 = to_local.call(0.0, 120.0)
	put.call(tw_c.x, tw_c.y, 1200.0, 24.0, 0.08, asphalt)
	for k in 3:
		var lx := -420.0 + k * 420.0
		var cc: Vector2 = to_local.call(lx, 60.0)
		put.call(cc.x, cc.y, 24.0, 130.0, 0.08, asphalt)
	# 停机坪（航站楼前；东缘收到 fwd 140，避免与货运车道重叠共面闪烁）
	var ap_c: Vector2 = to_local.call(-30.0, 243.0)
	put.call(ap_c.x, ap_c.y, 340.0, 214.0, 0.08, conc)
	# 航站楼：可走入大厅——地面/屋顶/墙体段（陆侧主入口 + 空侧 4 个登机口）
	var term: Vector2 = to_local.call(60.0, 372.0)
	var tint := Node3D.new()
	tint.position = Vector3(term.x, base_y, term.y)
	tint.rotation.y = heading
	add_child(tint)
	var tbox := func(px: float, py: float, pz: float, sx: float, sy: float,
			sz: float, c: Color) -> void:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(sx, sy, sz)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.roughness = 0.85
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(px, py, pz)
		tint.add_child(mi)
	var panel_col := Color(0.58, 0.6, 0.66)
	var dark_col := Color(0.16, 0.18, 0.22)
	# 地面（浅色地砖）与屋顶
	tbox.call(60.0, 0.1, 12.0, 300.0, 0.2, 52.0, Color(0.72, 0.7, 0.68))
	tbox.call(60.0, 16.0, 12.0, 300.0, 0.6, 52.0, dark_col)
	# 后墙（陆侧 lat+26）：主入口开口 fwd -10..+10
	tbox.call(-80.0, 8.0, 26.0, 130.0, 16.0, 0.8, panel_col)
	tbox.call(80.0, 8.0, 26.0, 130.0, 16.0, 0.8, panel_col)
	tbox.call(0.0, 13.0, 26.0, 20.0, 6.0, 0.8, panel_col)
	# 前墙（空侧 lat-26）：4 个登机口开口各宽 12（中心 fwd -105/-35/35/105）
	var gate_x := [-105.0, -35.0, 35.0, 105.0]
	var segs := [[-150.0, -111.0], [-99.0, -29.0], [-23.0, 29.0],
			[41.0, 111.0], [117.0, 150.0]]
	for sg in segs:
		var mid: float = (sg[0] + sg[1]) * 0.5
		var ln: float = sg[1] - sg[0]
		tbox.call(mid, 8.0, -26.0, ln, 16.0, 0.8, panel_col)
	for gx in gate_x:
		tbox.call(gx, 13.0, -26.0, 12.0, 6.0, 0.8, panel_col)
		var glabel := Label3D.new()
		glabel.text = "登机口 %d" % (gate_x.find(gx) + 1)
		glabel.font_size = 220
		glabel.modulate = Color(0.35, 0.65, 1.0)
		glabel.outline_size = 40
		glabel.position = Vector3(gx, 11.2, -24.6)
		tint.add_child(glabel)
	# 端墙 fwd ±150
	tbox.call(-150.0, 8.0, 0.0, 0.8, 16.0, 52.0, panel_col)
	# ---- 门：主入口双开玻璃门（左键）+ 4 登机口自动滑门 ----
	var glass_m := StandardMaterial3D.new()
	glass_m.albedo_color = Color(0.62, 0.8, 0.9, 0.4)
	glass_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_m.roughness = 0.08
	glass_m.metallic = 0.2
	var frame_m := StandardMaterial3D.new()
	frame_m.albedo_color = Color(0.3, 0.34, 0.4)
	# 主入口（陆侧 lat+26，宽 18）：双开玻璃门
	var main_d: Vector2 = to_local.call(0.0, 26.0)
	add_door(Vector3(main_d.x, base_y + 0.1, main_d.y), heading + PI * 0.5,
			18.0, 5.0, "swing", 2, glass_m)
	# 登机口自动滑门 ×4（空侧 lat-26，宽 10）
	for gx in gate_x:
		var gd: Vector2 = to_local.call(gx, -26.0)
		add_door(Vector3(gd.x, base_y + 0.1, gd.y), heading + PI * 0.5, 10.0,
				4.5, "slide", 2, glass_m)
	tbox.call(150.0, 8.0, 0.0, 0.8, 16.0, 52.0, panel_col)
	# ---- 内饰 ----
	for ci in 3:
		var cx2: float = -90.0 + ci * 90.0
		tbox.call(cx2, 1.0, 12.0, 12.0, 2.0, 2.4, Color(0.3, 0.26, 0.2))
		tbox.call(cx2, 3.4, 14.2, 12.0, 3.4, 0.4, Color(0.45, 0.5, 0.56))
		var clabel := Label3D.new()
		clabel.text = "值机 %d" % (ci + 1)
		clabel.font_size = 160
		clabel.modulate = Color(1.0, 0.85, 0.4)
		clabel.outline_size = 30
		clabel.position = Vector3(cx2, 5.6, 14.4)
		tint.add_child(clabel)
	tbox.call(60.0, 9.0, -18.0, 18.0, 5.0, 0.4, dark_col)
	var board := Label3D.new()
	board.text = "远城  09:30  登机\n远城  11:10  值机\n远城  14:20  值机"
	board.font_size = 130
	board.modulate = Color(1.0, 0.85, 0.4)
	board.outline_size = 20
	board.position = Vector3(60.0, 9.0, -19.8)
	tint.add_child(board)
	for si in 6:
		tbox.call(-120.0 + si * 45.0, 0.45, -8.0, 4.0, 0.5, 0.7,
				Color(0.2, 0.3, 0.45))
	for px in [-120.0, -40.0, 40.0, 120.0]:
		for pz in [-10.0, 10.0]:
			tbox.call(px, 8.0, pz, 1.2, 16.0, 1.2, Color(0.55, 0.57, 0.6))
	for lx in [-112.0, -38.0, 38.0, 112.0]:
		tbox.call(lx, 15.6, 0.0, 2.0, 0.15, 24.0, Color(0.95, 0.97, 1.0))
	for li in 6:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.92, 0.94, 1.0)
		lamp.light_energy = 1.6
		lamp.omni_range = 90.0
		lamp.position = Vector3(-125.0 + li * 50.0, 12.0, 0.0)
		tint.add_child(lamp)
	# ---- 航站楼碰撞：墙体段（开口可通行）----
	var w2 := func(lx: float, ly: float, ln: float, th: float) -> void:
		var wpos: Vector2 = to_local.call(lx, ly)
		obstacles_box.append({"c": wpos, "hx": ln * 0.5, "hz": th * 0.5,
				"rot": heading})
	w2.call(-80.0, 26.0, 130.0, 0.8)
	w2.call(80.0, 26.0, 130.0, 0.8)
	for sg in segs:
		var mid2: float = (sg[0] + sg[1]) * 0.5
		w2.call(mid2, -26.0, sg[1] - sg[0], 0.8)
	w2.call(-150.0, 0.0, 0.8, 52.0)
	w2.call(150.0, 0.0, 0.8, 52.0)
	for px in [-120.0, -40.0, 40.0, 120.0]:
		for pz in [-10.0, 10.0]:
			var pp: Vector2 = to_local.call(px, pz)
			obstacles_box.append({"c": pp, "hx": 0.6, "hz": 0.6, "rot": 0.0,
					"top": base_y + 16.0})
	for ci in 3:
		var cw: Vector2 = to_local.call(-90.0 + ci * 90.0, 12.0)
		obstacles_box.append({"c": cw, "hx": 6.0, "hz": 1.2, "rot": heading})
	# 塔台（细高 + 顶盘）
	var twr: Vector2 = to_local.call(-190.0, 350.0)
	var tower := MeshInstance3D.new()
	var tmesh2 := BoxMesh.new()
	tmesh2.size = Vector3(9.0, 34.0, 9.0)
	tower.mesh = tmesh2
	tower.position = Vector3(twr.x, base_y + 17.0, twr.y)
	add_child(tower)
	var cab := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(16.0, 5.0, 16.0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.25, 0.4, 0.5)
	cmat.roughness = 0.2
	cmesh.material = cmat
	cab.mesh = cmesh
	cab.position = Vector3(twr.x, base_y + 36.0, twr.y)
	add_child(cab)
	obstacles_box.append({"c": twr, "hx": 4.5, "hz": 4.5, "rot": 0.0,
			"top": base_y + 34.0})
	_build_airport_access(center, heading)


## 航站楼地面通道：连接公路 + 航站楼回车环道 + 地下停车库（入口/出口坡道下到 -7m）
func _build_airport_access(center: Vector2, heading: float) -> void:
	# 此前本函数无参、内部写死主机场坐标——远城机场构建时又把整套接入道路
	# （回车环道/连接公路/货运车道/地下车库）在主机场原位重复建了一遍，
	# 两份同高网格完全共面，机场一带所有路面持续闪烁。
	var base_y := terrain_height(center.x, center.y) + 0.04
	var fwd := Vector2(sin(heading), cos(heading))
	var right := Vector2(cos(heading), -sin(heading))
	var lp := func(lx: float, ly: float) -> Vector2:
		return center + fwd * lx + right * ly
	var loop_y := terrain_height(center.x, center.y) + 0.14
	# ---- 航站楼回车环道（闭合路，紧贴航站楼背面）----
	var loop := [lp.call(-180.0, 415.0), lp.call(300.0, 415.0),
			lp.call(300.0, 433.0), lp.call(-180.0, 433.0)]
	_make_road(loop, [loop_y, loop_y, loop_y, loop_y], true, 6.5, false)
	# ---- 连接公路：最近主路采样点 → 环道西角 ----
	var best := INF
	var bp := Vector2.ZERO
	var by := 0.0
	for road in roads:
		if road.elevated:
			continue
		for pt in road.pts:
			var d: float = Vector2(pt.x, pt.z).distance_to(
					lp.call(-180.0, 415.0))
			if d < best:
				best = d
				bp = Vector2(pt.x, pt.z)
				by = pt.y
	# 最近路网点太远（远城机场周边没有路网）就不拉连接线，
	# 否则会从 6km 外的城市拉一条野路横穿地图
	if best < 400.0:
		var c_mid: Vector2 = bp.lerp(lp.call(-180.0, 415.0), 0.55) \
				+ Vector2(0.0, 60.0)
		_make_road([bp, c_mid, lp.call(-180.0, 415.0)],
				[by, loop_y, loop_y], false, 6.5, false)
	# ---- 货运坪面车道：末端以缓坡爬升至货仓地板高度（与尾门坡道衔接）----
	_make_road([lp.call(300.0, 415.0), lp.call(250.0, 300.0),
			lp.call(180.0, 150.0), lp.call(19.5, 0.0)],
			[loop_y, loop_y, loop_y, 2.55], false, 9.0, false)
	# ---- 地下车库：入口坡道 → 地下环路 → 出口坡道（降到 -6.8m）----
	var ug_y := -6.8
	_make_road([lp.call(300.0, 433.0), lp.call(352.0, 452.0),
			lp.call(400.0, 430.0)],
			[loop_y, loop_y - 3.2, ug_y], false, 6.0, false)
	var ug_loop := [lp.call(400.0, 430.0), lp.call(400.0, 260.0),
			lp.call(120.0, 230.0), lp.call(-60.0, 330.0),
			lp.call(-60.0, 433.0)]
	_make_road(ug_loop, [ug_y, ug_y, ug_y, ug_y, ug_y], true, 7.0, false)
	_make_road([lp.call(-60.0, 433.0), lp.call(-110.0, 452.0),
			lp.call(-150.0, 430.0)],
			[ug_y, loop_y - 3.4, loop_y], false, 6.0, false)
	# 车库整层地坪铺装（vy 门控：只在地下高度命中）
	var gc: Vector2 = lp.call(240.0, 320.0)
	var gright := right
	road_pads.append({"c": gc, "fx": gright.x, "fz": gright.y,
			"hf": 150.0, "hl": 185.0, "y": ug_y})
	# ---- 地下车库视觉：墙面 / 顶板 / 照明 / P 标记 / 车位线 ----
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.32, 0.34, 0.38)
	wall_mat.roughness = 0.9
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.1, 0.11, 0.13)
	dark_mat.roughness = 1.0
	var wall_box := func(a: Vector2, b: Vector2, h: float,
			th := 1.2) -> void:
		var mid: Vector2 = (a + b) * 0.5
		var d: Vector2 = b - a
		var ln: float = d.length()
		var ang: float = atan2(d.x, d.y)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(th, h, ln)
		mesh.material = wall_mat
		mi.mesh = mesh
		mi.position = Vector3(mid.x, base_y - h * 0.5, mid.y)
		mi.rotation.y = ang
		add_child(mi)
	# 地下环路外墙（环路中心线外扩 9.6m ≈ 软墙位置）
	var outer_a: Vector2 = lp.call(409.6, 439.6)
	var outer_b: Vector2 = lp.call(409.6, 250.4)
	var outer_c: Vector2 = lp.call(129.6, 220.4)
	var outer_d: Vector2 = lp.call(-69.6, 320.4)
	var outer_e: Vector2 = lp.call(-69.6, 442.6)
	wall_box.call(outer_a, outer_b, 12.0)
	wall_box.call(outer_b, outer_c, 12.0)
	wall_box.call(outer_c, outer_d, 12.0)
	wall_box.call(outer_d, outer_e, 12.0)
	wall_box.call(outer_e, outer_a, 12.0)
	# 顶板（地下空间上方的深色天花板）
	var ce := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(520.0, 0.5, 260.0)
	cm.material = dark_mat
	ce.mesh = cm
	var cc: Vector2 = lp.call(170.0, 330.0)
	ce.position = Vector3(cc.x, base_y - 1.2, cc.y)
	add_child(ce)
	# 地坪板（深色，路面网格之外的地面）
	var fl := MeshInstance3D.new()
	var flm := BoxMesh.new()
	flm.size = Vector3(300.0, 0.3, 270.0)
	flm.material = dark_mat
	fl.mesh = flm
	var fc: Vector2 = lp.call(300.0, 325.0)
	fl.position = Vector3(fc.x, base_y - 7.05, fc.y)
	add_child(fl)
	# 照明：环路沿线 6 盏顶灯 + 灯带
	for li in 6:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.85, 0.9, 1.0)
		lamp.light_energy = 2.2
		lamp.omni_range = 60.0
		var la: Vector2 = lp.call(360.0 - float(li) * 110.0, 335.0)
		lamp.position = Vector3(la.x, base_y - 2.6, la.y)
		add_child(lamp)
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(6.0, 0.12, 1.4)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.95, 0.97, 1.0)
		smat.emission_enabled = true
		smat.emission = Color(0.85, 0.92, 1.0)
		smat.emission_energy_multiplier = 2.0
		sm.material = smat
		strip.mesh = sm
		strip.position = Vector3(la.x, base_y - 2.2, la.y)
		add_child(strip)
	# 入口 P 标记 + 车位线
	var pmark := Label3D.new()
	pmark.text = "P 停车"
	pmark.font_size = 200
	pmark.modulate = Color(0.4, 0.75, 1.0)
	pmark.outline_size = 36
	var pe: Vector2 = lp.call(376.0, 470.0)
	pmark.position = Vector3(pe.x, base_y + 6.0, pe.y)
	add_child(pmark)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.9, 0.92, 0.95)
	for li in 5:
		var lm := MeshInstance3D.new()
		var lmesh := BoxMesh.new()
		lmesh.size = Vector3(0.25, 0.02, 6.0)
		lmesh.material = line_mat
		lm.mesh = lmesh
		var lpos: Vector2 = lp.call(120.0 + li * 40.0, 244.0)
		lm.position = Vector3(lpos.x, ug_y + 0.04, lpos.y)
		add_child(lm)


## 远方城市：街网 + 楼群 + 自己的机场（只能驾机抵达）
func _build_far_city() -> void:
	var c := FAR_CITY_POS
	var base_y := terrain_height(c.x, c.y) + 0.04
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = RRTextures.asphalt_plain()
	asphalt.roughness = 0.94
	# 街网：7 纵 7 横（±520 范围）
	for k in 7:
		var off := -520.0 + k * 173.0
		var vmi := MeshInstance3D.new()
		var vm := BoxMesh.new()
		vm.size = Vector3(14.0, 0.06, 1040.0)
		vm.material = asphalt
		vmi.mesh = vm
		vmi.position = Vector3(c.x + off, base_y + 0.03, c.y)
		add_child(vmi)
		var hmi := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(1040.0, 0.06, 14.0)
		hm.material = asphalt
		hmi.mesh = hm
		hmi.position = Vector3(c.x, base_y + 0.03, c.y + off)
		add_child(hmi)
		road_pads.append({"c": Vector2(c.x + off, c.y), "fx": 0.0, "fz": 1.0,
				"hf": 520.0, "hl": 7.0, "y": base_y + 0.06})
		road_pads.append({"c": Vector2(c.x, c.y + off), "fx": 1.0, "fz": 0.0,
				"hf": 520.0, "hl": 7.0, "y": base_y + 0.06})
	# 楼群：每街区 2~4 栋（贴纹理，登记碰撞）
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var obs: Array = []
	for bx in 6:
		for bz in 6:
			var bc := Vector2(c.x - 433.0 + bx * 173.0 + 86.5,
					c.y - 433.0 + bz * 173.0 + 86.5)
			for k in rng.randi_range(2, 4):
				var h := rng.randf_range(10.0, 42.0)
				var w := rng.randf_range(16.0, 34.0)
				var d := rng.randf_range(16.0, 34.0)
				var ox := bc.x + rng.randf_range(-30.0, 30.0)
				var oz := bc.y + rng.randf_range(-30.0, 30.0)
				xfs.append(Transform3D(Basis.from_scale(Vector3(w, h, d)),
						Vector3(ox, base_y + h * 0.5, oz)))
				cols.append(Color(0.75, 0.78, 0.82))
				obs.append({"c": Vector2(ox, oz), "hx": w * 0.5,
						"hz": d * 0.5, "rot": 0.0, "top": base_y + h})
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
	add_child(mmi)
	obstacles_box.append_array(obs)
	# 远城机场
	_build_airport(c + Vector2(760.0, -620.0), FAR_CITY_HEADING)


## ================= 门系统 =================

## 加一扇门：swing=铰链门（左键开），slide=自动滑门（靠近开）
## center=门洞中心（地面），heading=门面法线朝向，width=门洞总宽
func add_door(center: Vector3, heading: float, width: float, height: float,
		kind: String, leaves: int, mat: Material) -> void:
	var right := Vector2(cos(heading), -sin(heading))
	var rv := Vector3(right.x, 0, right.y)
	var leaf_w := width / float(leaves)
	var door := {"center": center, "heading": heading, "width": width,
			"kind": kind, "open": false, "t": 0.0, "leaves": [],
			"auto": kind == "slide", "close_t": 0.0}
	for i in leaves:
		var hinge_off := -width * 0.5 + float(i) * leaf_w
		var hinge := Node3D.new()
		hinge.position = center + rv * hinge_off + Vector3(0, 0, 0)
		add_child(hinge)
		var panel := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(leaf_w - 0.12, height - 0.1, 0.12)
		mesh.material = mat
		panel.mesh = mesh
		if kind == "slide":
			panel.position = Vector3(0, height * 0.5, 0)
		else:
			panel.position = Vector3(rv.x * leaf_w * 0.5,
					height * 0.5, rv.z * leaf_w * 0.5)
		hinge.add_child(panel)
		door["leaves"].append({"hinge": hinge, "panel": panel,
				"base": hinge.position, "rv": rv, "lw": leaf_w})
	# 门板碰撞（关：占满门洞；开：缩成薄条不挡路）
	var obs := {"c": Vector2(center.x, center.z), "hx": width * 0.5,
			"hz": 0.2, "rot": heading}
	obstacles_box.append(obs)
	door["obs"] = obs
	doors.append(door)


## 每帧更新门动画（pos=步行玩家位置）
func update_doors(dt: float, pos: Vector3) -> void:
	doors_player_pos = pos
	for d in doors:
		var near: bool = Vector2(pos.x, pos.z).distance_to(
				Vector2(d["center"].x, d["center"].z)) < 4.0
		var target := 0.0
		if d["kind"] == "slide":
			target = 1.0 if near else 0.0
		else:
			if d["open"]:
				target = 1.0
				if not near:
					d["close_t"] = float(d.get("close_t")) - dt
					if float(d["close_t"]) <= 0.0:
						d["open"] = false
						target = 0.0
		var spd := 3.2 if d["kind"] == "slide" else 2.4
		d["t"] = move_toward(float(d["t"]), target, spd * dt)
		var t: float = d["t"]
		var w: float = float(d["width"])
		for li in (d["leaves"] as Array).size():
			var leaf: Dictionary = d["leaves"][li]
			var hinge: Node3D = leaf["hinge"]
			if d["kind"] == "slide":
				var dir_s := 1.0 if li % 2 == 0 else -1.0
				hinge.position = Vector3(leaf["base"]) + \
						Vector3(leaf["rv"].x, 0, leaf["rv"].y) * \
						(dir_s * t * (w * 0.5))
			else:
				var dir_s := 1.0 if li % 2 == 0 else -1.0
				hinge.rotation.y = -dir_s * t * 1.9
		# 门板碰撞随开合变化：开过半即标记 off（步行推开不再阻挡）
		var obs: Dictionary = d["obs"]
		obs["hx"] = w * 0.5 * (1.0 - t) + 0.15 * t
		obs["off"] = t > 0.6


## 最近的未开门（左键交互用；返回 door 序号，-1 = 无）
func nearest_closed_door(pos: Vector3, max_d: float) -> int:
	for i in doors.size():
		var d: Dictionary = doors[i]
		if d["kind"] != "swing" or d["open"]:
			continue
		if Vector2(pos.x, pos.z).distance_to(
				Vector2(d["center"].x, d["center"].z)) < max_d:
			return i
	return -1


func open_door(i: int) -> void:
	if i >= 0 and i < doors.size():
		doors[i]["open"] = true
		doors[i]["close_t"] = 8.0


## 远城区域判定（onfoot 边界钳制用：在远城内不按主城半径收边）
func far_city_contains(x: float, z: float) -> bool:
	return absf(x - FAR_CITY_POS.x) < FAR_CITY_HALF 			and absf(z - FAR_CITY_POS.y) < FAR_CITY_HALF


func terrain_height(x: float, z: float) -> float:
	if _terr.is_empty():
		return 0.0
	var fx := x / TERR_CELL
	var fz := z / TERR_CELL
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := float(_terr.get(Vector2i(ix, iz), 0.0))
	var h10 := float(_terr.get(Vector2i(ix + 1, iz), 0.0))
	var h01 := float(_terr.get(Vector2i(ix, iz + 1), 0.0))
	var h11 := float(_terr.get(Vector2i(ix + 1, iz + 1), 0.0))
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


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
	if x > -2350.0 and x < -1000.0 and z > -1240.0 and z < 480.0:
		c = Color(0.42, 0.55, 0.33)      # 机场平地（西郊旱地，海面在此挖开）
	elif x < -1080.0:
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


## 并线缝隙垫层：匝道与主线边对边并行之间的空隙（~3m）铺同色沥青，
## 消除「两路之间露出地面」的观感问题；材质用纯沥青底色（无标线纹理）
func _build_merge_fills() -> void:
	var asph := StandardMaterial3D.new()
	asph.albedo_color = Color("#33353a")
	asph.roughness = 0.92
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for ri in range(25, 33):
		if ri >= roads.size():
			continue
		var ramp: Road = roads[ri]
		if not ramp.elevated:
			continue
		# 找主线：距匝道尾段最近的高架
		var tp: Vector3 = ramp.pts[ramp.pts.size() - 1]
		var main_i := -1
		var main_d := 1e9
		var mid: Vector3 = ramp.pts[maxi(0, ramp.pts.size() - 25)]
		for oi in roads.size():
			if oi == ri or not roads[oi].elevated:
				continue
			var near: Vector3 = _nearest_on_road(roads[oi], mid.x, mid.z)
			var d := Vector2(near.x - mid.x, near.z - mid.z).length()
			if d < main_d:
				main_d = d
				main_i = oi
		if main_i < 0:
			continue
		var main: Road = roads[main_i]
		# 沿匝道尾段逐采样对铺连接带（匝道内缘 → 主线内缘，y+0.04 防叠面）
		var i0: int = maxi(0, ramp.pts.size() - 70)
		var prev_main: Vector3 = Vector3.INF
		var prev_edge: Vector3 = Vector3.INF
		for i in range(i0, ramp.pts.size()):
			var pa: Vector3 = ramp.pts[i]
			var lr: Vector2 = ramp.left[i % ramp.left.size()]
			var ma: Vector3 = _nearest_on_road(main, pa.x, pa.z)
			var dist: float = Vector2(pa.x - ma.x, pa.z - ma.z).length()
			if dist > ramp.half_w + main.half_w + 6.0:
				prev_main = Vector3.INF
				prev_edge = Vector3.INF
				continue
			if Vector2(ma.x - pa.x, ma.z - pa.z).length() > ramp.half_w + main.half_w + 6.0:
				continue
			# 匝道靠主线一侧的边缘（取距主线近者）
			var rc1 := pa + Vector3(lr.x * (ramp.half_w - 0.15), 0.04, lr.y * (ramp.half_w - 0.15))
			var rc2 := pa - Vector3(lr.x * (ramp.half_w - 0.15), 0.04, lr.y * (ramp.half_w - 0.15))
			var edge_r := rc1 if rc1.distance_to(ma) < rc2.distance_to(ma) else rc2
			var ml: Vector2 = main.left[i % main.left.size()] if i < main.left.size() else main.left[0]
			var mc1 := ma + Vector3(ml.x * (main.half_w - 0.4), 0.04, ml.y * (main.half_w - 0.4))
			var mc2 := ma - Vector3(ml.x * (main.half_w - 0.4), 0.04, ml.y * (main.half_w - 0.4))
			var edge_m := mc1 if mc1.distance_to(edge_r) < mc2.distance_to(edge_r) else mc2
			if prev_main != Vector3.INF:
				st.set_color(Color.WHITE); st.add_vertex(prev_edge)
				st.set_color(Color.WHITE); st.add_vertex(edge_m)
				st.set_color(Color.WHITE); st.add_vertex(edge_r)
				st.set_color(Color.WHITE); st.add_vertex(prev_edge)
				st.set_color(Color.WHITE); st.add_vertex(prev_main)
				st.set_color(Color.WHITE); st.add_vertex(edge_m)
				quads += 2
			prev_main = ma
			prev_edge = edge_r
			prev_edge = edge_m
			prev_main = Vector3(ma.x, ma.y, ma.z)
	if quads > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat2 := StandardMaterial3D.new()
		mat2.albedo_color = Color("#33353a")
		mat2.roughness = 0.92
		mi.material_override = mat2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	print("[map] 并线垫层 %d 段" % quads)


## 道路上距 (x,z) 最近的中心线采样点
func _nearest_on_road(road: Road, x: float, z: float) -> Vector3:
	var bd := 1e9
	var bp: Vector3 = road.pts[0]
	var rr := int(ceil((road.half_w + 40.0) / CELL)) + 1
	var gx := int(x / CELL)
	var gz := int(z / CELL)
	for cxi in range(gx - rr, gx + rr + 1):
		for czi in range(gz - rr, gz + rr + 1):
			var key := Vector2i(cxi, czi)
			if not road.grid.has(key):
				continue
			for i in road.grid[key]:
				var p := road.pts[i]
				var d := Vector2(p.x - x, p.z - z).length_squared()
				if d < bd:
					bd = d
					bp = p
	return bp


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
	var xsec_mat := _fade_material(Color.WHITE, RRTextures.asphalt_plain(), 0.92)
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
	var corner_mat := _fade_material(Color("#787e88"))
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
uniform vec3 cam_w = vec3(0.0);      // 遮挡淡出：相机世界坐标
uniform vec3 plr_w = vec3(0.0);      // 遮挡淡出：车世界坐标
uniform float fade_r = 5.5;

varying vec3 v_tint;
varying float v_kind;   // 实例类型（见上）
varying float v_face;   // >0.5 为水平面（屋顶 / 底面）
varying float v_up;     // 距该体块底面的高度（米）
varying float v_hgt;    // 该体块总高（米）
varying vec3 v_wpos;    // 世界坐标（遮挡淡出用）

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
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 挡在相机与车之间的楼体按有序抖动丢弃，车才不会被沿街楼吃掉。
	// 用淡出而不是把相机拉近 —— 后者会让视距忽远忽近。
	vec3 fd = plr_w - cam_w;
	float fl = length(fd);
	if (fl > 0.5 && v_wpos.y > plr_w.y - 0.3) {
		vec3 fdir = fd / fl;
		float ft = dot(v_wpos - cam_w, fdir);
		if (ft > 0.15 && ft < fl - 0.6) {
			float fperp = length((v_wpos - cam_w) - fdir * ft);
			float ff = 1.0 - smoothstep(fade_r * 0.45, fade_r, fperp);
			if (ff > 0.02) {
				vec2 fpx = mod(FRAGCOORD.xy, 4.0);
				int fbi = int(fpx.y) * 4 + int(fpx.x);
				float fm[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
						3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
				if (ff > (fm[fbi] + 0.5) / 16.0) {
					discard;
				}
			}
		}
	}
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
	_fade_mats.append(m)          # 楼体也参与遮挡淡出，每帧写入相机/车位
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
		if absf(cx - GAR_C.x) < GAR_W * 0.5 + hw + 1.0 \
				and absf(cz - GAR_C.y) < GAR_D * 0.5 + hd + 1.0:
			return false                       # 卷帘门车库保留地
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
		# 楼房碰撞体（轴对齐 OBB，供漫游车辆撞墙反馈）
		obstacles_box.append({"c": Vector2(cx, cz), "hx": w * 0.5, "hz": dep * 0.5, "rot": 0.0})
		var tint: Color = palette[mini(int(rng.next() * palette.size()), palette.size() - 1)]
		var j := rng.range(-0.05, 0.05)
		tint = Color(clampf(tint.r + j, 0, 1), clampf(tint.g + j, 0, 1),
				clampf(tint.b + j, 0, 1), 1.0)
		xfs.append(Transform3D(Basis.from_scale(Vector3(w, h, dep)),
				Vector3(cx, h * 0.5, cz)))
		cols.append(tint)
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


## 卷帘门车库：出生点建筑，西门洞（8m 宽 × 4.6m 高）正对 x=180 街。
## 墙体碰撞按门洞分块（障碍碰撞是 2D 推出，门楣/屋顶不给碰撞）；
## 卷帘门贴图 + 升起动画，门体碰撞随门落下/升起挂摘。
func _make_garage() -> void:
	var y := STREET_Y
	var cx := GAR_C.x
	var cz := GAR_C.y
	# ---- 楼体（复用建筑 shader，随遮挡走廊一起淡出）----
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var tint := Color(0.80, 0.81, 0.83, 0.5)   # a<0.25 走素面，a≈0.5 走墙砖纹理
	var wall_h := GAR_H
	var put_box := func(px: float, pz: float, sx: float, sy: float, sz: float,
			col: Color, base_y: float = -1.0) -> void:
		var by := y if base_y < 0.0 else base_y   # 盒底标高（默认贴地）
		xfs.append(Transform3D(Basis.from_scale(Vector3(sx, sy, sz)),
				Vector3(px, by + sy * 0.5, pz)))
		cols.append(col)
	# 北墙 / 南墙（z=±(GAR_D/2-0.3)）
	put_box.call(cx, cz - GAR_D * 0.5 + 0.3, GAR_W, wall_h, 0.6, tint)
	put_box.call(cx, cz + GAR_D * 0.5 - 0.3, GAR_W, wall_h, 0.6, tint)
	# 东墙（封死）
	put_box.call(cx + GAR_W * 0.5 - 0.3, cz, 0.6, wall_h, GAR_D - 1.2, tint)
	# 西墙门洞两侧余段（门洞 z ∈ [cz-4, cz+4]）
	put_box.call(cx - GAR_W * 0.5 + 0.3, cz - GAR_DOOR_HW - 1.35, 0.6, wall_h, 2.7, tint)
	put_box.call(cx - GAR_W * 0.5 + 0.3, cz + GAR_DOOR_HW + 1.35, 0.6, wall_h, 2.7, tint)
	# 门楣（门洞上方 0.9m）+ 平屋顶（都架在高处）
	put_box.call(cx - GAR_W * 0.5 + 0.3, cz, 0.6, 0.9, GAR_DOOR_HW * 2.0, tint,
			y + GAR_DOOR_H)
	put_box.call(cx, cz, GAR_W + 0.6, 0.3, GAR_D + 0.6, Color(0.5, 0.52, 0.55, 0.0),
			y + GAR_H - 0.3)
	# ---- 塔楼主体：车库就是这栋楼的底层（嵌在楼里），从屋顶直接长上去 ----
	# 主层：与车库外墙齐平（16×14），高 33m；退台层再收 0.72 竖 9.5m
	put_box.call(cx, cz, GAR_W, 33.0, GAR_D, Color(0.74, 0.76, 0.79, 0.5),
			y + GAR_H + 0.03)
	put_box.call(cx, cz, GAR_W * 0.72, 9.5, GAR_D * 0.72, Color(0.78, 0.80, 0.83, 0.5),
			y + GAR_H + 33.0)
	# 塔楼不占碰撞：障碍推出是 2D（无高度），整栋 footprint 的碰撞体会把门洞
	# 一起封死；地面周界就是车库墙的分块碰撞，车永远够不到高层
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
	# ---- 墙体碰撞（分块留门洞；无高度判定，门楣/屋顶不参与）----
	obstacles_box.append({"c": Vector2(cx, cz - GAR_D * 0.5 + 0.3),
			"hx": GAR_W * 0.5, "hz": 0.3, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx, cz + GAR_D * 0.5 - 0.3),
			"hx": GAR_W * 0.5, "hz": 0.3, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx + GAR_W * 0.5 - 0.3, cz),
			"hx": 0.3, "hz": GAR_D * 0.5 - 0.6, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx - GAR_W * 0.5 + 0.3,
			cz - GAR_DOOR_HW - 1.35), "hx": 0.3, "hz": 1.35, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx - GAR_W * 0.5 + 0.3,
			cz + GAR_DOOR_HW + 1.35), "hx": 0.3, "hz": 1.35, "rot": 0.0})
	# ---- 卷帘门板 + 门体碰撞 ----
	var dm := BoxMesh.new()
	dm.size = Vector3(0.3, GAR_DOOR_H, GAR_DOOR_HW * 2.0 + 0.2)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_texture = RRTextures.roll_door()
	dmat.roughness = 0.55
	dmat.metallic = 0.25
	dm.material = dmat
	_door_panel = MeshInstance3D.new()
	_door_panel.mesh = dm
	_door_base_y = y
	_door_panel.position = Vector3(cx - GAR_W * 0.5 + 0.3, y + GAR_DOOR_H * 0.5, cz)
	add_child(_door_panel)
	_door_piece = {"c": Vector2(cx - GAR_W * 0.5 + 0.3, cz),
			"hx": 0.2, "hz": GAR_DOOR_HW, "rot": 0.0}
	obstacles_box.append(_door_piece)


## 车库卷帘门：油门状态下 40m 内升起，或贴近门洞 6.5m（从外面回来）自动开；
## 离开范围落回。升起 0.7s，开过一半即摘掉门体碰撞。
func step_garage(dt: float, plr: Vector3, thr: bool) -> void:
	if _door_panel == null:
		return
	var dx := plr.x - (GAR_C.x - GAR_W * 0.5 + 0.3)
	var dz := plr.z - GAR_C.y
	var dd := sqrt(dx * dx + dz * dz)
	var target := 1.0 if ((thr and dd < 40.0) or dd < 6.5) else 0.0
	if _door_open == target:
		return
	_door_open = move_toward(_door_open, target, dt / 0.7)
	var h := maxf(GAR_DOOR_H * (1.0 - _door_open), 0.15)
	_door_panel.scale.y = h / GAR_DOOR_H
	_door_panel.position.y = _door_base_y + GAR_DOOR_H - h * 0.5
	var blocking := _door_open < 0.55
	var has_piece: bool = obstacles_box.has(_door_piece)
	if blocking and not has_piece:
		obstacles_box.append(_door_piece)
	elif not blocking and has_piece:
		obstacles_box.erase(_door_piece)


## 中心广场配件店：实体建筑（玻璃门脸 + 招牌），整栋 OBB 碰撞；
## 距店门 14m 内可在漫游中按 Enter 进店购买（game.gd 判定）
func _make_parts_shop() -> void:
	var y := STREET_Y
	var cx := SHOP_POS.x
	var cz := SHOP_POS.y
	# 楼体（建筑 shader，随遮挡走廊淡出）：四面墙 + 平顶
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var put_box := func(px: float, pz: float, sx: float, sy: float, sz: float,
			col: Color, base_y: float = -1.0) -> void:
		var by := y if base_y < 0.0 else base_y
		xfs.append(Transform3D(Basis.from_scale(Vector3(sx, sy, sz)),
				Vector3(px, by + sy * 0.5, pz)))
		cols.append(col)
	var tint := Color(0.85, 0.78, 0.62, 0.5)   # 暖黄面砖（商店感）
	var wall_h := SHOP_H
	put_box.call(cx, cz - SHOP_D * 0.5 + 0.3, SHOP_W, wall_h, 0.6, tint)   # 北墙
	put_box.call(cx, cz + SHOP_D * 0.5 - 0.3, SHOP_W, wall_h, 0.6, tint)   # 南墙
	put_box.call(cx + SHOP_W * 0.5 - 0.3, cz, 0.6, wall_h, SHOP_D - 1.2, tint)  # 东墙
	# 西墙（店门面）：门洞 z∈[cz-3, cz+3]，两侧余段 + 门楣
	put_box.call(cx - SHOP_W * 0.5 + 0.3, cz - 4.5, 0.6, wall_h, 3.0, tint)
	put_box.call(cx - SHOP_W * 0.5 + 0.3, cz + 4.5, 0.6, wall_h, 3.0, tint)
	put_box.call(cx - SHOP_W * 0.5 + 0.3, cz, 0.6, 1.4, 6.0,
			Color(0.12, 0.15, 0.19, 0.0), y + wall_h - 1.4)
	put_box.call(cx, cz, SHOP_W + 0.6, 0.3, SHOP_D + 0.6,
			Color(0.5, 0.52, 0.55, 0.0), y + SHOP_H - 0.3)   # 平屋顶
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
	# 墙体碰撞（整栋实心 + 西门凹进的门斗不留碰撞——进店靠走近按键，无需进门洞）
	obstacles_box.append({"c": Vector2(cx, cz - SHOP_D * 0.5 + 0.3),
			"hx": SHOP_W * 0.5, "hz": 0.3, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx, cz + SHOP_D * 0.5 - 0.3),
			"hx": SHOP_W * 0.5, "hz": 0.3, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx + SHOP_W * 0.5 - 0.3, cz),
			"hx": 0.3, "hz": SHOP_D * 0.5, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx - SHOP_W * 0.5 + 0.3, cz - 4.5),
			"hx": 0.3, "hz": 1.5, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx - SHOP_W * 0.5 + 0.3, cz + 4.5),
			"hx": 0.3, "hz": 1.5, "rot": 0.0})
	# 招牌
	var sign := Label3D.new()
	sign.text = "配 件 店"
	sign.font_size = 460
	sign.pixel_size = 0.01
	sign.modulate = Color(1.0, 0.82, 0.25)
	sign.outline_size = 48
	sign.outline_modulate = Color(0.1, 0.1, 0.12)
	sign.position = Vector3(cx - SHOP_W * 0.5 - 0.4, y + SHOP_H - 1.2, cz)
	sign.rotation_degrees.y = -90.0
	add_child(sign)
	# 店内地板
	var fl := MeshInstance3D.new()
	var flm := BoxMesh.new()
	flm.size = Vector3(SHOP_W - 0.8, 0.08, SHOP_D - 0.8)
	var flm_mat := StandardMaterial3D.new()
	flm_mat.albedo_color = Color(0.42, 0.36, 0.3)
	flm_mat.roughness = 0.7
	flm.material = flm_mat
	fl.mesh = flm
	fl.position = Vector3(cx, y + 0.04, cz)
	add_child(fl)
	# 西门木门（左键开启）
	add_door(Vector3(cx - SHOP_W * 0.5 + 0.3, y, cz), -PI * 0.5, 5.6, 3.4,
			"swing", 1, StandardMaterial3D.new())
	_furnish_parts_shop(cx, cz, y)


## 配件店内饰：柜台 / 货架商品 / 轮胎堆 / 顶灯
func _furnish_parts_shop(cx: float, cz: float, y: float) -> void:
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var put := func(px: float, py: float, pz: float, sx: float, sy: float,
			sz: float, c: Color) -> void:
		xfs.append(Transform3D(Basis.from_scale(Vector3(sx, sy, sz)),
				Vector3(px, py + sy * 0.5, pz)))
		cols.append(c)
	var wood := Color(0.3, 0.24, 0.18)
	var counter_c := Color(0.52, 0.55, 0.6)
	# 柜台 + 台面
	put.call(cx + 4.0, y + 0.55, cz, 6.0, 1.1, 1.2, wood)
	put.call(cx + 4.0, y + 1.18, cz, 6.4, 0.1, 1.4, counter_c)
	# 沿北墙货架 ×3 + 商品
	for sh in 3:
		var sx := cx - 5.0 + sh * 5.0
		put.call(sx, y + 1.2, cz - 5.9, 4.6, 2.4, 0.8, Color(0.36, 0.4, 0.46))
		var rng := RandomNumberGenerator.new()
		rng.seed = 3400 + sh
		for gi in 6:
			var gc := Color(rng.randf_range(0.5, 0.95), rng.randf_range(0.35, 0.7),
					rng.randf_range(0.2, 0.5))
			put.call(sx - 1.6 + (gi % 3) * 1.6, y + 0.9 + (gi / 3) * 0.75,
					cz - 5.9, 0.7, 0.4, 0.5, gc)
	# 东墙货架
	put.call(cx + 8.9, y + 1.2, cz + 2.0, 0.8, 2.4, 5.0, Color(0.36, 0.4, 0.46))
	for gi in 4:
		put.call(cx + 8.9, y + 0.9 + (gi % 2) * 0.75, cz + 0.6 + (gi / 2) * 2.2,
				0.5, 0.4, 0.8, Color(0.6, 0.5, 0.3))
	# 轮胎堆 ×2（进门左侧）
	for ts in 2:
		for k in 3:
			var tire := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.38
			tm.bottom_radius = 0.38
			tm.height = 0.24
			var tmat := StandardMaterial3D.new()
			tmat.albedo_color = Color(0.12, 0.12, 0.13)
			tm.material = tmat
			tire.mesh = tm
			tire.position = Vector3(cx - 6.8, y + 0.14 + k * 0.26,
					cz - 2.0 + ts * 2.4)
			add_child(tire)
	# 顶灯 ×2 + 灯板
	for li in 2:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.95, 0.85)
		lamp.light_energy = 1.5
		lamp.omni_range = 18.0
		lamp.position = Vector3(cx - 3.0 + li * 7.0, y + 6.6, cz)
		add_child(lamp)
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(2.4, 0.08, 1.2)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.98, 0.98, 1.0)
		pmat.emission_enabled = true
		pmat.emission = Color(1.0, 0.97, 0.9)
		pmat.emission_energy_multiplier = 1.6
		pm.material = pmat
		panel.mesh = pm
		panel.position = Vector3(cx - 3.0 + li * 7.0, y + 7.2, cz)
		add_child(panel)
	# 家具碰撞：柜台 / 货架
	obstacles_box.append({"c": Vector2(cx + 4.0, cz), "hx": 3.0, "hz": 0.6,
			"rot": 0.0})
	for sh in 3:
		obstacles_box.append({"c": Vector2(cx - 5.0 + sh * 5.0, cz - 5.9),
				"hx": 2.3, "hz": 0.4, "rot": 0.0})
	# 内饰 MultiMesh
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
	add_child(mmi)


## 枪械店内饰：玻璃展柜 / 武器墙架 / 海报 / 顶灯
func _furnish_gunshop(cx: float, cz: float, y: float) -> void:
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var put := func(px: float, py: float, pz: float, sx: float, sy: float,
			sz: float, c: Color) -> void:
		xfs.append(Transform3D(Basis.from_scale(Vector3(sx, sy, sz)),
				Vector3(px, py + sy * 0.5, pz)))
		cols.append(c)
	var dark := Color(0.14, 0.15, 0.17)
	# 玻璃展柜 ×2（柜台 + 玻璃罩 + 展品）
	for gi in 2:
		var gz := cz - 3.0 + gi * 6.0
		put.call(cx + 1.0, y + 0.45, gz, 4.6, 0.9, 1.2, dark)
		for k in 3:
			put.call(cx - 0.2 + k * 1.2, y + 0.92, gz - 0.2 + k * 0.16,
					0.9, 0.12, 0.14, Color(0.35, 0.37, 0.4))
	# 武器墙架（北墙）
	put.call(cx + 1.0, y + 2.0, cz - 6.45, 8.0, 2.6, 0.16, dark)
	for k in 5:
		put.call(cx - 2.6 + k * 1.8, y + 2.2, cz - 6.32, 0.16, 0.9, 0.12,
				Color(0.4, 0.42, 0.46))
	# 东墙海报
	put.call(cx + 9.4, y + 4.2, cz, 0.1, 1.7, 1.3, Color(0.5, 0.16, 0.14))
	put.call(cx + 9.3, y + 4.2, cz, 0.06, 1.5, 1.1, Color(0.85, 0.8, 0.7))
	# 玻璃罩（透明，单独 MeshInstance）
	for gi in 2:
		var glass := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(4.6, 0.5, 1.2)
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.6, 0.8, 0.9, 0.25)
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.roughness = 0.1
		gm.material = gmat
		glass.mesh = gm
		glass.position = Vector3(cx + 1.0, y + 1.2, cz - 3.0 + gi * 6.0)
		add_child(glass)
	# 顶灯 ×2 + 灯带
	for li in 2:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.9, 0.95, 1.0)
		lamp.light_energy = 1.5
		lamp.omni_range = 18.0
		lamp.position = Vector3(cx - 2.0 + li * 6.0, y + 6.6, cz)
		add_child(lamp)
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(2.2, 0.08, 1.2)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.9, 0.96, 1.0)
		pmat.emission_enabled = true
		pmat.emission = Color(0.8, 0.92, 1.0)
		pmat.emission_energy_multiplier = 1.5
		pm.material = pmat
		panel.mesh = pm
		panel.position = Vector3(cx - 2.0 + li * 6.0, y + 7.2, cz)
		add_child(panel)
	# 家具碰撞：展柜 ×2
	for gi in 2:
		obstacles_box.append({"c": Vector2(cx + 1.0, cz - 3.0 + gi * 6.0),
				"hx": 2.3, "hz": 0.6, "rot": 0.0})
	# 内饰 MultiMesh
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
	add_child(mmi)


## 枪械店：独立建筑（深蓝灰 + 金色「枪 械 店」招牌），东门洞朝广场中心
func _make_gunshop() -> void:
	var y := STREET_Y
	var cx := GUNSHOP_POS.x
	var cz := GUNSHOP_POS.y
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var put_box := func(px: float, pz: float, sx: float, sy: float, sz: float,
			col: Color, base_y: float = -1.0) -> void:
		var by := y if base_y < 0.0 else base_y
		xfs.append(Transform3D(Basis.from_scale(Vector3(sx, sy, sz)),
				Vector3(px, by + sy * 0.5, pz)))
		cols.append(col)
	var tint := Color(0.52, 0.58, 0.68, 0.5)   # 蓝灰面砖
	var wall_h := GUNSHOP_H
	# 北墙 / 南墙
	put_box.call(cx, cz - GUNSHOP_D * 0.5 + 0.3, GUNSHOP_W, wall_h, 0.6, tint)
	put_box.call(cx, cz + GUNSHOP_D * 0.5 - 0.3, GUNSHOP_W, wall_h, 0.6, tint)
	# 西墙（封死）
	put_box.call(cx - GUNSHOP_W * 0.5 + 0.3, cz, 0.6, wall_h, GUNSHOP_D - 1.2, tint)
	# 东墙（门洞 z ∈ [cz-3, cz+3]，两侧余段 + 门楣）
	put_box.call(cx + GUNSHOP_W * 0.5 - 0.3, cz - 4.5, 0.6, wall_h, 3.0, tint)
	put_box.call(cx + GUNSHOP_W * 0.5 - 0.3, cz + 4.5, 0.6, wall_h, 3.0, tint)
	put_box.call(cx + GUNSHOP_W * 0.5 - 0.3, cz, 0.6, 1.4, 6.0,
			Color(0.12, 0.15, 0.19, 0.0), y + wall_h - 1.4)
	# 平屋顶
	put_box.call(cx, cz, GUNSHOP_W + 0.6, 0.3, GUNSHOP_D + 0.6,
			Color(0.5, 0.52, 0.55, 0.0), y + SHOP_H - 0.3)
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
	# 碰撞（实心，进店靠走近按键）
	obstacles_box.append({"c": Vector2(cx, cz - GUNSHOP_D * 0.5 + 0.3),
			"hx": GUNSHOP_W * 0.5, "hz": 0.3, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx, cz + GUNSHOP_D * 0.5 - 0.3),
			"hx": GUNSHOP_W * 0.5, "hz": 0.3, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx - GUNSHOP_W * 0.5 + 0.3, cz),
			"hx": 0.3, "hz": GUNSHOP_D * 0.5, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx + GUNSHOP_W * 0.5 - 0.3, cz - 4.5),
			"hx": 0.3, "hz": 1.5, "rot": 0.0})
	obstacles_box.append({"c": Vector2(cx + GUNSHOP_W * 0.5 - 0.3, cz + 4.5),
			"hx": 0.3, "hz": 1.5, "rot": 0.0})
	# 招牌
	var sign := Label3D.new()
	sign.text = "枪 械 店"
	sign.font_size = 460
	sign.pixel_size = 0.01
	sign.modulate = Color(1.0, 0.82, 0.25)
	sign.outline_size = 48
	sign.outline_modulate = Color(0.1, 0.1, 0.12)
	sign.position = Vector3(cx + GUNSHOP_W * 0.5 + 0.4, y + GUNSHOP_H - 1.2, cz)
	sign.rotation_degrees.y = 90.0
	add_child(sign)
	# 店内地板
	var fl2 := MeshInstance3D.new()
	var flm2 := BoxMesh.new()
	flm2.size = Vector3(GUNSHOP_W - 0.8, 0.08, GUNSHOP_D - 0.8)
	var flm2_mat := StandardMaterial3D.new()
	flm2_mat.albedo_color = Color(0.24, 0.27, 0.33)
	flm2_mat.roughness = 0.6
	flm2.material = flm2_mat
	fl2.mesh = flm2
	fl2.position = Vector3(cx, y + 0.04, cz)
	add_child(fl2)
	# 西门木门（深色）
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.35, 0.22, 0.14)
	door_mat.roughness = 0.6
	add_door(Vector3(cx + GUNSHOP_W * 0.5 - 0.3, y, cz), PI * 0.5, 5.6, 3.4,
			"swing", 1, door_mat)
	_furnish_gunshop(cx, cz, y)


## 每次进漫游把卷帘门落回原位（出生在车库内，踩油门顶门出发）
func reset_garage() -> void:
	if _door_panel == null:
		return
	_door_open = 0.0
	_door_panel.scale.y = 1.0
	_door_panel.position.y = _door_base_y + GAR_DOOR_H * 0.5
	if not obstacles_box.has(_door_piece):
		obstacles_box.append(_door_piece)


## 小地图贴图：整张路网俯视图（高架更亮，山海沙漠分区底色）
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
	_fill_zone(img, size, -2350, -1000, -1240, 480, Color(0.17, 0.23, 0.15))    # 机场平地（西海挖开）
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
