class_name HDWorld
extends Node3D
## 烽火地带 —— 世界装配（大地/光照/掩体/边界/撤离点/室内靶馆），一次性 build()。
## 移植自网页版 js/fps/layout.js（分区/摆位/撤离信标）+ rangeHall.js（室内靶馆）：
## 中心危险区（warehouse/house 核心建筑 + 集装箱/木箱/油桶/沙袋集群掩体）
## → 过渡带 → 荒野环带（dead_tree/rocks/tent/wreck 稀疏 POI）；
## 东北角室内靶馆（混凝土封闭壳 44×5×30：射击线在馆心 +Z 侧 11m、面朝 -Z，
## 靶道沿 -Z 延伸 10/16/22m，挡弹墙在最远端，入口门洞开在 +Z 墙）。
## 障碍契约：obstacles 元素 {cx,cz,hx,hz,top,bot}（onfoot push_out 同款轴对齐
## AABB，top/bot 显式给出；wall_hit 的 2D 线段-AABB + 高度过滤同源）。

const PROP_DIR := "res://assets/battle/props/"
## 大坝两件走路径 preload 不走全局类名缓存：--headless -s 回归不刷新
## global_script_class_cache.cfg，新 class_name（HDDam/HDDamBase）按名解析会
## 报「Identifier not found」→ hd_world 编译失败 → 回归 _run 访问 null 挂死
## （test_huodai.gd:9 GUN_LIB / main.gd:50 tracer_pool 同款先例）
const HDDAM_SCRIPT := preload("res://scripts/hd_dam.gd")
const HDDAM_BASE_SCRIPT := preload("res://scripts/hd_dam_base.gd")
const GROUND_SIZE := 300.0        # 大地平面边长（隐形边界墙收在地面之内）
const BOUND := 148.0              # 可行动边界半宽（地面 300 见方内收 2m）
const WILD_R := 112.0             # 荒野带下限（网页版 layout.js ZONE_BANDS.wildR）
const NEAR_R := 4.0               # obstacles_near 查询外扩半径
const TINTABLE := ["Paint", "Plaster", "Concrete", "TankPaint", "Canvas"]

## GLB 道具实测包围盒 W×H×D（原点在底面中心；js/fps/layout.js PROP_DIMS 同源）
const PROP_DIMS := {
	"barn": Vector3(12.7, 7.17, 8.74),
	"barrel": Vector3(0.6, 0.91, 0.61),
	"barrier": Vector3(4.16, 1.25, 0.75),
	"bunker": Vector3(14.1, 3.7, 9.58),
	"container": Vector3(2.46, 2.59, 6.12),
	"crate": Vector3(1.02, 1.02, 1.02),
	"dead_tree": Vector3(1.04, 4.88, 2.0),
	"fuel_tank": Vector3(11.98, 8.12, 10.16),
	"house": Vector3(7.1, 3.6, 6.92),
	"rocks": Vector3(13.6, 2.22, 3.29),
	"sandbags": Vector3(2.52, 1.61, 0.78),
	"tent": Vector3(6.3, 2.69, 4.31),
	"warehouse": Vector3(22.8, 8.2, 12.83),
	"wreck": Vector3(1.88, 1.44, 4.3),
}
## GLB 失败时的兜底盒底色（贴合各道具材质气质）
const FALLBACK_COLOR := {
	"barrel": Color(0.44, 0.49, 0.53), "container": Color(0.48, 0.42, 0.35),
	"crate": Color(0.61, 0.49, 0.31), "dead_tree": Color(0.37, 0.29, 0.22),
	"house": Color(0.69, 0.63, 0.52), "rocks": Color(0.49, 0.45, 0.41),
	"sandbags": Color(0.61, 0.56, 0.42), "tent": Color(0.56, 0.54, 0.47),
	"warehouse": Color(0.54, 0.52, 0.47), "wreck": Color(0.42, 0.37, 0.34),
}

## 靶馆壳体（44 宽 ×5 高 ×30 深，混凝土封闭；射击线在馆心 +Z 侧）
const HALL_HX := 22.0
const HALL_HZ := 15.0
const HALL_H := 5.0
const HALL_WALL_T := 0.5          # 墙厚
const HALL_DOOR_W := 4.0          # +Z 墙门洞宽（射击线后方进出）
const HALL_FIRE_DZ := 11.0        # 射击线距馆心（+Z 侧）
const HALL_TRAP_T := 0.6          # 尽端挡弹墙厚度（-Z 端）
const HALL_FLOOR_Y := 0.06        # 馆内地坪高度：与大地 y=0 错开 6cm，根治共面 z-fighting 乱闪

## 撤离信标（绿色发光柱 + 地面绿环）
const EXTRACT_BEACON_H := 2.6

## set_indoor 前后对比（进靶馆：雾拉近/环境光压暗/漏进来的夕阳压弱）
## 雾密度红线：指数雾 exp(-d·dist)——第 3 轮 0.003→0.005：0.004 档下
## 150m 透射 ~55%（原 0.002 为 74%）、士兵赭红军装在浅暖霾中仍读作深色剪影
## （问题②结论复核仍守），>120m 才显著衰减换远山大气层次（评审 #9）
const FOG_MAX := 0.005              # 远景可见性红线
const OUTDOOR_FOG := 0.004          # 150m 处雾感 ~45%，远山 130-160m 变浅偏蓝紫
## INDOOR_FOG 刻意压在红线内一格：fog_density 引擎侧按 float32 存储，
## 0.003 会舍入成 0.003000000026… 反超 double 红线（回归 15 踩过）；0.0029 双保险
const INDOOR_FOG := 0.0029          # 靶馆 22m 靶道只留薄雾感（原 0.02 把靶子糊成剪影）
const OUTDOOR_AMB := 0.45
const INDOOR_AMB := 0.55
const OUTDOOR_SUN := 1.7
const INDOOR_SUN := 0.25

## 可搜刮容器锚点（x/z 手工排布贴障碍摆：中心 18 / 过渡 11 / 荒野 9 + 坝区 13
## 由 HDDamBase 追加 = 51；原 mid/wild 落在大坝矩形内的 6 点已迁入坝区表）
const CONTAINER_XZ := {
	"center": [
		Vector2(-18, -32), Vector2(-30, -30), Vector2(-46, -44), Vector2(-24, -52),
		Vector2(-10, -44), Vector2(10, -50), Vector2(24, -40), Vector2(34, -20),
		Vector2(26, -12), Vector2(13, -19), Vector2(2, -6), Vector2(-8, 2),
		Vector2(-18, 10), Vector2(-4, 22), Vector2(10, 30), Vector2(-24, -12),
		Vector2(18, 6), Vector2(-34, 22),
	],
	"mid": [
		Vector2(0, 92), Vector2(44, 84), Vector2(84, 44), Vector2(96, 0),
		Vector2(84, -44), Vector2(-84, -44), Vector2(-96, 0), Vector2(-84, 44),
		Vector2(-44, 84), Vector2(60, -66), Vector2(-60, 70),
	],
	"wild": [
		Vector2(-130, 60), Vector2(-144, -10), Vector2(-120, -80),
		Vector2(140, -70), Vector2(144, 10), Vector2(60, 140), Vector2(0, 146),
		Vector2(-70, 130), Vector2(-140, 110),
	],
}

## 巡逻点（中心 10 / 过渡 4 / 荒野 5 + 坝区 7 由 HDDamBase 追加 = 26；
## 原荒野 3 点落在坝区带内已删，路线由 HDSoldiers 同 zone 过滤锁定分区内互连）
const PATROL_XZ := {
	"center": [
		Vector2(-20, -30), Vector2(10, -40), Vector2(30, -10), Vector2(0, -13),
		Vector2(-10, 15), Vector2(20, 20), Vector2(-30, 5), Vector2(15, -55),
		Vector2(-15, -55), Vector2(33, -40),
	],
	"mid": [Vector2(0, 100), Vector2(100, -20), Vector2(-95, 30), Vector2(-60, -80)],
	"wild": [
		Vector2(-140, 40), Vector2(144, -30), Vector2(120, 60), Vector2(40, 144),
		Vector2(-140, 95),
	],
}

## 中心危险区摆位表（js/fps/layout.js 巷道坐标移植；n/x/z 必填，
## r=朝向 t=染色 y=叠层离地 s=均匀缩放 chx/chz=碰撞覆盖半宽，枯树只挡树干）
const CENTER_PROPS := [
	# —— 西侧军火库（仓库为核心建筑 + 集装箱弹列 + 门前沙袋） ——
	{"n": "warehouse", "x": -24.0, "z": -44.0},
	{"n": "container", "x": -39.0, "z": -45.0, "r": 1.57, "t": Color(0.35, 0.44, 0.31)},
	{"n": "container", "x": -39.0, "z": -39.0, "r": 1.55, "t": Color(0.54, 0.29, 0.27)},
	{"n": "container", "x": -8.5, "z": -48.0, "r": -1.57, "t": Color(0.25, 0.44, 0.56)},
	{"n": "crate", "x": -16.0, "z": -38.5, "r": 0.25},
	{"n": "crate", "x": -15.2, "z": -37.6, "r": -0.3},
	{"n": "barrel", "x": -33.0, "z": -37.0},
	{"n": "barrel", "x": -32.2, "z": -36.2},
	{"n": "sandbags", "x": -24.0, "z": -36.4, "r": 0.04},
	{"n": "wreck", "x": -8.0, "z": -52.0, "r": -1.1},
	# —— 核心巷道（集装箱巷道 + 沙袋 + 油桶群 + 残骸） ——
	{"n": "container", "x": -3.5, "z": -6.5, "r": 0.12, "t": Color(0.29, 0.43, 0.56)},
	{"n": "container", "x": -3.5, "z": -6.5, "r": 0.02, "y": 2.59, "t": Color(0.49, 0.35, 0.27)},
	{"n": "container", "x": -3.8, "z": 0.2, "r": -0.06, "t": Color(0.43, 0.42, 0.35)},
	{"n": "container", "x": 3.5, "z": -14.2, "r": 1.62, "t": Color(0.56, 0.29, 0.24)},
	{"n": "container", "x": 14.5, "z": -8.5, "r": -1.55, "t": Color(0.25, 0.48, 0.38)},
	{"n": "sandbags", "x": 8.5, "z": -1.5},
	{"n": "sandbags", "x": 11.5, "z": -16.5, "r": 1.25},
	{"n": "sandbags", "x": -7.5, "z": -17.5, "r": 0.55},
	{"n": "sandbags", "x": 5.0, "z": -21.0, "r": -0.15},
	{"n": "sandbags", "x": -9.0, "z": -3.0, "r": 1.35},
	{"n": "barrel", "x": 19.5, "z": -11.5},
	{"n": "barrel", "x": 20.3, "z": -12.3},
	{"n": "barrel", "x": 19.1, "z": -13.0},
	{"n": "barrel", "x": -5.5, "z": -20.5},
	{"n": "barrel", "x": -6.4, "z": -21.2},
	{"n": "barrel", "x": 8.0, "z": -6.2},
	{"n": "barrel", "x": 17.0, "z": -3.0},
	{"n": "barrel", "x": 16.4, "z": -3.8},
	{"n": "crate", "x": 6.8, "z": -4.6, "r": 0.25},
	{"n": "crate", "x": 6.8, "z": -4.6, "r": -0.15, "y": 1.02},
	{"n": "crate", "x": 12.0, "z": -11.2, "r": 0.5},
	{"n": "crate", "x": -1.5, "z": 3.5, "r": -0.4, "s": 0.9},
	{"n": "wreck", "x": 21.5, "z": -3.0, "r": 0.75},
	{"n": "wreck", "x": -9.5, "z": -13.5, "r": -0.55},
	# —— 东北小屋据点（house 为副核心建筑 + 帐篷营地散件） ——
	{"n": "house", "x": 32.0, "z": -32.5, "r": 0.06, "t": Color(0.78, 0.7, 0.58)},
	{"n": "tent", "x": 40.5, "z": -29.5, "r": -0.45},
	{"n": "crate", "x": 29.0, "z": -27.6, "r": 0.35},
	{"n": "barrel", "x": 36.2, "z": -26.4},
	{"n": "barrel", "x": 35.6, "z": -25.6},
	{"n": "sandbags", "x": 27.0, "z": -30.5, "r": 1.5},
	{"n": "wreck", "x": 38.5, "z": -37.5, "r": 2.2},
	{"n": "dead_tree", "x": 44.5, "z": -35.0, "r": 0.9, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": 26.5, "z": -38.5, "r": 2.6, "chx": 0.35, "chz": 0.35},
	# —— 南侧散件（巡逻掩体，避免开阔地一眼望穿） ——
	{"n": "container", "x": -26.0, "z": 20.0, "r": 0.1, "t": Color(0.29, 0.43, 0.56)},
	{"n": "sandbags", "x": -14.0, "z": 8.0, "r": 0.4},
	{"n": "crate", "x": -20.0, "z": 14.0, "r": 0.2},
	{"n": "barrel", "x": -19.0, "z": 15.0},
	{"n": "crate", "x": 12.0, "z": 24.0, "r": 0.1},
	{"n": "barrel", "x": 13.0, "z": 24.6},
	{"n": "sandbags", "x": 2.0, "z": 34.0, "r": 0.2},
]

## 过渡带散布（少量地标掩体；原 (0,-105) 枯树落坝区带内迁至西端 (-118,-106)）
const MID_PROPS := [
	{"n": "dead_tree", "x": 90.0, "z": 60.0, "r": 1.8, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": -95.0, "z": -40.0, "r": 3.4, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": -118.0, "z": -106.0, "r": 0.5, "chx": 0.35, "chz": 0.35},
	{"n": "rocks", "x": 40.0, "z": 95.0, "r": 4.3},
	{"n": "rocks", "x": -20.0, "z": 100.0, "r": 3.1},
	{"n": "wreck", "x": 95.0, "z": -20.0, "r": 1.6},
	{"n": "wreck", "x": -50.0, "z": 90.0, "r": 0.13},
]

## 荒野环带 POI（枯树/乱石/帐篷/残骸稀疏散布，全部分布在 d>112；原 5 件落在
## 坝区带/坝后山体内已删或外迁：dead_tree (-90,-120)→(-96,-76)、rocks (70,-120)→(118,-60)）
const WILD_PROPS := [
	{"n": "dead_tree", "x": -120.0, "z": 50.0, "r": 0.8, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": -135.0, "z": -30.0, "r": 0.3, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": -96.0, "z": -76.0, "r": 2.6, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": 60.0, "z": 120.0, "r": 0.6, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": -60.0, "z": 140.0, "r": 1.4, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": 130.0, "z": -20.0, "r": 5.3, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": -30.0, "z": 120.0, "r": 2.9, "chx": 0.35, "chz": 0.35},
	{"n": "dead_tree", "x": 110.0, "z": 40.0, "r": 0.25, "chx": 0.35, "chz": 0.35},
	{"n": "rocks", "x": -110.0, "z": -60.0, "r": 5.3},
	{"n": "rocks", "x": 118.0, "z": -60.0, "r": 0.5},
	{"n": "rocks", "x": -70.0, "z": 110.0, "r": 2.6},
	{"n": "wreck", "x": 120.0, "z": -60.0, "r": 1.5},
	{"n": "wreck", "x": -125.0, "z": 20.0, "r": 0.2},
	{"n": "wreck", "x": 135.0, "z": 35.0, "r": 1.35},
]

var obstacles: Array = []         # {cx,cz,hx,hz,top,bot}（onfoot push_out 契约）
var container_spots: Array = []   # {pos: Vector3, zone: String}（HDLoot 据此生成）
var patrol_spots: Array = []      # {pos: Vector3, zone: String}（AI 巡逻锚点）
var spawn_pos := Vector3(-138.0, 0.0, 138.0)   # 行动出生点（西南角，离中心远）
var extract_pos: Vector3 = HDData.EXTRACT_POS  # 主撤离点（绿信标）
var extract2_pos: Vector3 = HDData.DAM_EXTRACT_POS   # 第二撤离点（大坝撤离广场，信标同款）
var dam: Node3D                   # 大坝硬结构（HDDam 实例：坝体/廊道/涂鸦/闸门排，视觉挂本类）
var dam_base: Node3D              # 坝底工业区（HDDamBase 实例：厂房/堆场/工地 + 坝区点位）

var _built := false
var _prop_scenes := {}            # name -> PackedScene | null（load 缓存）
var _fallback_mats := {}          # name -> StandardMaterial3D（兜底盒共用）
var _sun: DirectionalLight3D
var _env: Environment


func build() -> void:
	if _built:
		return
	_built = true
	_build_env()
	_build_ground()
	_build_boundary()
	for e in CENTER_PROPS:
		_place_prop(e)
	for e in MID_PROPS:
		_place_prop(e)
	for e in WILD_PROPS:
		_place_prop(e)
	_build_hall()
	for zone in CONTAINER_XZ:
		for p in CONTAINER_XZ[zone]:
			var v: Vector2 = p
			container_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": zone})
	for zone in PATROL_XZ:
		for p in PATROL_XZ[zone]:
			var v: Vector2 = p
			patrol_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": zone})
	# 大坝分区（北缘地标，坝轴线东西向）：硬结构 HDDam 先装配、坝底陈设 HDDamBase 后
	# （建造计划契约 DAM 先 BASE 后）；两件自带 _built 幂等护栏，重复 build() 不翻倍。
	# 视觉 add_child(self)，障碍/容器点/巡逻点由两件 append 进本类容器
	# （hd_loot.gd:141-143 同款鸭子注入），随后 main.gd loot/soldiers build 消费
	dam = HDDAM_SCRIPT.new()
	add_child(dam)
	dam.build(self)
	dam_base = HDDAM_BASE_SCRIPT.new()
	add_child(dam_base)
	dam_base.build(self)
	# 撤离信标 ×2：主撤离（东侧绿标）+ 大坝广场第二撤离（93,-94），参数化复用同一生成器
	_build_extract(extract_pos)
	_build_extract(extract2_pos)


## 进靶馆模式：雾拉近/环境光稍暗/夕阳压弱（室内氛围）；回大厅/行动恢复。
## 集成者用 has_method("set_indoor") 探测调用。
func set_indoor(on: bool) -> void:
	if _env == null:
		return
	_env.fog_density = INDOOR_FOG if on else OUTDOOR_FOG
	_env.ambient_light_energy = INDOOR_AMB if on else OUTDOOR_AMB
	if _sun != null:
		_sun.light_energy = INDOOR_SUN if on else OUTDOOR_SUN


## 分区：距原点 d<=80 中心危险区 / d>112 荒野 / 其间过渡（HDData.DANGER_R 同源）；
## 大坝矩形分支优先于 wild 裁决（矩形西北角距原点 >112 仍判 dam，防坝区点漏进荒野表）
func zone_at(x: float, z: float) -> String:
	var d := Vector2(x, z).length()
	if d <= HDData.DANGER_R:
		return "center"
	if x >= -130.0 and x <= 105.0 and z >= -118.0 and z <= -84.0:
		return "dam"
	if d > WILD_R:
		return "wild"
	return "mid"


## 撤离点列表（主撤离 + 大坝广场第二撤离）：main._step_mission 取最近点判定读条，
## 开局/离场逻辑不改——圈内距离判定与单点语义一致（test 断言 size==2）
func extract_list() -> Array:
	return [extract_pos, extract2_pos]


## 是否在靶馆矩形内（含墙体）
func in_hall(x: float, z: float) -> bool:
	var c := HDData.HALL_CENTER
	return absf(x - c.x) <= HALL_HX and absf(z - c.z) <= HALL_HZ


## 馆内地坪 HALL_FLOOR_Y（0.06）/ 馆外大地 0.0：两层地面错开 6cm，
## 根治馆内地板与大地面 y=0 共面 z-fighting 乱闪（问题⑦）；
## 门洞处 6cm 台阶保留（第一人称感知极小）
func ground_height(x: float, z: float) -> float:
	return HALL_FLOOR_Y if in_hall(x, z) else 0.0


## 附近障碍子集（onfoot push_out 每帧调用，线性扫 + 外扩矩形快筛）
func obstacles_near(x: float, z: float) -> Array:
	var arr: Array = []
	for ob in obstacles:
		if absf(x - float(ob["cx"])) > float(ob["hx"]) + NEAR_R:
			continue
		if absf(z - float(ob["cz"])) > float(ob["hz"]) + NEAR_R:
			continue
		arr.append(ob)
	return arr


## 射线对全部障碍做 2D(xz) 线段-AABB 相交 + 高度过滤，返回命中距离（无墙 = max_d）
func wall_hit(from: Vector3, dir: Vector3, max_d: float) -> float:
	var best := max_d
	for ob in obstacles:
		var d := _ray_aabb(from, dir, ob, best)
		if d < best:
			best = d
	return best


# ================= 环境与大地 =================

## 白天光照架构 v2（第 5 轮架构级重做）——四层渲染体系对位目标图实拍观感：
## ① PhysicalSkyMaterial 物理大气散射天空（瑞利/米氏：天顶饱和蓝连续渐变到
##    地平暖白、太阳方向自然光晕——替换三色渐变插值的 ProceduralSky 塑料感）；
## ② 双色温打光：暖主阳 (-40,25) + 冷天光补光 (无阴影反向)——阴影偏冷蓝、
##    受光面偏暖的电影级对比；
## ③ 全局间接光 SSIL（暗面获得周围暖沙色反弹，混凝土读作实体而非平涂）+
##    SSAO（垛间凹槽竖条纹）；
## ④ 体积雾（低密度暖色前向散射：坝脚与远区大气纵深、逆光发亮）+ 普通指数雾
##    （远山变浅）+ 调色分级（饱和 1.18/对比 1.06——评审「暖沙色调高饱和」直接解）
func _build_env() -> void:
	# —— 暖主阳（唯一投影光源，天空太阳绑定此节点方向） ——
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.96, 0.9)   # 正午偏暖白（强日照）
	_sun.light_energy = OUTDOOR_SUN
	_sun.rotation_degrees = Vector3(-40.0, 25.0, 0.0)   # 中午偏斜：阴影落画面左侧
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 300.0   # 坝距 ref 相机 130~280m，120 会全落阴影距离外
	_sun.shadow_bias = 0.06
	_sun.shadow_blur = 1.0
	_sun.shadow_opacity = 0.9
	add_child(_sun)
	# —— 冷天光补光（第 5 轮双色温架构）：从主阳反向的半空铺冷蓝天光，
	#    阴影面偏蓝、受光面偏暖——无阴影、低能量，只做暗部染色
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.72, 0.92)
	fill.light_energy = 0.32
	fill.rotation_degrees = Vector3(-38.0, 155.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)

	# —— 物理大气散射天空 ——
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.0    # 瑞利散射：天顶饱和蓝→地平暖白的连续渐变
	sky_mat.mie_coefficient = 0.008       # 米氏散射：太阳方向光晕
	sky_mat.mie_eccentricity = 0.75
	sky_mat.turbidity = 4.0               # 干燥霾天（沙漠大坝空气通透但非纯净）
	sky_mat.ground_color = Color(0.5, 0.44, 0.35)   # 地平暖沙色衔接大地（物理天空单色地面）
	sky_mat.energy_multiplier = 1.05
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = OUTDOOR_FOG
	# 暖霾色：远山变浅偏蓝紫靠密度（150m 透射 ~55%）+ 体积雾纵深共同实现
	env.fog_light_color = Color(0.80, 0.74, 0.64)
	env.fog_sky_affect = 0.08
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.57, 0.5)
	env.ambient_light_energy = OUTDOOR_AMB
	env.ssao_enabled = true          # 垛间凹槽/洞龛深色竖条纹（评审 #8）
	env.ssao_intensity = 2.2
	env.ssil_enabled = true          # 屏幕空间间接光：暗面暖沙色反弹（第 5 轮架构）
	env.ssil_intensity = 0.6
	# 体积雾（第 5 轮架构）：低密度暖色前向散射——坝脚雾霭与逆光发亮的大气纵深
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(1.0, 0.86, 0.72)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 160.0
	# 调色分级（第 5 轮架构）：饱和/对比一键对位「暖沙色高饱和」（评审 #6 终解）
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.18
	env.glow_enabled = true          # 信标/灯板泛光
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.05
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_build_clouds()


## 高空云带 ×3（评审 #7 丝缕白云的工程内替代：ProceduralSkyMaterial 无
## sky_cover 属性——4.7 运行时报 Invalid assignment 曾致回归挂死，见上）。
## unshaded 半透明噪声 PlaneMesh 平铺高空：cast_shadow OFF 不投地面影，
## 距 ref 相机 250~350m 经暖霾（fog 0.004）衰减成淡丝缕，正对目标图
## 左上/中上天区；远高于山脊顶 72 与塔吊顶 80，不遮挡
const CLOUD_BANDS := [
	{"y": 155.0, "x": 10.0, "z": -170.0, "w": 420.0, "d": 60.0},
	{"y": 175.0, "x": -90.0, "z": -240.0, "w": 520.0, "d": 80.0},
	{"y": 165.0, "x": 130.0, "z": -210.0, "w": 380.0, "d": 55.0},
]

func _build_clouds() -> void:
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cn.frequency = 0.008
	cn.fractal_octaves = 4
	cn.seed = 20261013
	var ctex := NoiseTexture2D.new()
	ctex.width = 512
	ctex.height = 512
	ctex.seamless = true
	ctex.noise = cn
	var cramp := Gradient.new()
	cramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	cramp.set_color(1, Color(1.0, 1.0, 1.0, 0.85))
	ctex.color_ramp = cramp
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = ctex
	cm.albedo_color = Color(0.98, 0.98, 1.0, 0.9)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for cb in CLOUD_BANDS:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(cb["w"], cb["d"])
		pm.material = cm
		mi.mesh = pm
		mi.position = Vector3(cb["x"], cb["y"], cb["z"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## 大地平面：300×300 浅色戈壁滩 + 程序化细噪点（battle_map.gd 同款 NoiseTexture2D）
## 白天对位提亮：目标图地面是日照下的浅沙色，albedo 乘噪点后约原色
func _build_ground() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.02
	n.fractal_octaves = 4
	n.seed = 20261006
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.68, 0.63, 0.53))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.52, 0.4)   # 浅沙色戈壁（乘噪点后约原色）
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(7.0, 7.0, 1.0)   # 低频大尺度斑块破纯色（第 2 轮 20→7）
	mat.roughness = 1.0
	mat.metallic_specular = 0.0   # 干燥地面不反射天空
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	add_child(mi)


# ================= 边界与登记 =================

## 地图边界四面隐形高墙（只登记 obstacles，无视觉）
func _build_boundary() -> void:
	_add_obstacle(0.0, -(BOUND + 1.0), BOUND + 2.0, 1.0, 40.0)
	_add_obstacle(0.0, BOUND + 1.0, BOUND + 2.0, 1.0, 40.0)
	_add_obstacle(-(BOUND + 1.0), 0.0, 1.0, BOUND + 2.0, 40.0)
	_add_obstacle(BOUND + 1.0, 0.0, 1.0, BOUND + 2.0, 40.0)


func _add_obstacle(cx: float, cz: float, hx: float, hz: float,
		top := 40.0, bot := 0.0) -> void:
	obstacles.append({"cx": cx, "cz": cz, "hx": hx, "hz": hz, "top": top, "bot": bot})


## 摆一个道具条目（摆位表 Dictionary → 实例 + 保守 AABB 登记）
func _place_prop(e: Dictionary) -> void:
	var scl := Vector3.ONE
	if e.has("s"):
		var s := float(e["s"])
		scl = Vector3(s, s, s)
	_prop_place(String(e["n"]), float(e["x"]), float(e["z"]), float(e.get("r", 0.0)),
			scl, e.get("t", Color.WHITE), float(e.get("y", 0.0)),
			float(e.get("chx", -1.0)), float(e.get("chz", -1.0)))


## 摆一个 Blender 道具：贴地、绕 Y 旋转、缩放；GLB 失败退化同尺寸兜底盒。
## chx/chz>=0 时碰撞用覆盖值（枯树只挡树干）；朝向旋转的道具取保守 AABB。
func _prop_place(name: String, x: float, z: float, rot_y: float, scl: Vector3,
		tint := Color.WHITE, y_off := 0.0, col_hx := -1.0, col_hz := -1.0) -> Node3D:
	var dims: Vector3 = PROP_DIMS[name]
	var node: Node3D
	var ps: PackedScene = _prop_scene(name)
	if ps != null:
		node = ps.instantiate()
		node.position = Vector3(x, y_off, z)
		node.rotation.y = rot_y
		node.scale = scl
		if tint != Color.WHITE:
			_tint(node, tint)
		add_child(node)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(dims.x * scl.x, dims.y * scl.y, dims.z * scl.z)
		bm.material = _fallback_mat(name)
		mi.mesh = bm
		mi.position = Vector3(x, y_off + dims.y * 0.5 * scl.y, z)
		mi.rotation.y = rot_y
		add_child(mi)
		node = mi
	# 碰撞：默认全包围盒，朝向取保守 AABB（注册进 obstacles）
	var hx := dims.x * 0.5 * scl.x
	var hz := dims.z * 0.5 * scl.z
	if col_hx >= 0.0:
		hx = col_hx
	if col_hz >= 0.0:
		hz = col_hz
	var c := absf(cos(rot_y))
	var s := absf(sin(rot_y))
	_add_obstacle(x, z, hx * c + hz * s, hx * s + hz * c, y_off + dims.y * scl.y, y_off)
	return node


## GLB 预载缓存（battlefield.gd 存在性检查同款：load 失败退化兜底盒不炸）
func _prop_scene(name: String) -> PackedScene:
	if not _prop_scenes.has(name):
		var path: String = PROP_DIR + name + ".glb"
		_prop_scenes[name] = load(path) if ResourceLoader.exists(path) else null
		if _prop_scenes[name] == null:
			push_warning("[烽火地带] 道具模型加载失败：%s（暂用盒子代替）" % path)
	return _prop_scenes[name]


## 可染色材质（Paint/Plaster/Concrete/TankPaint/Canvas）克隆后乘色（battle_map 同款）
func _tint(node: Node3D, tint: Color) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D and (m as StandardMaterial3D).resource_name in TINTABLE:
				var t: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				t.albedo_color = (m as StandardMaterial3D).albedo_color * tint
				mi.set_surface_override_material(si, t)


func _fallback_mat(name: String) -> StandardMaterial3D:
	if not _fallback_mats.has(name):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FALLBACK_COLOR.get(name, Color(0.54, 0.51, 0.45))
		mat.roughness = 0.95
		_fallback_mats[name] = mat
	return _fallback_mats[name]


# ================= 撤离点 =================

## 撤离信标（参数化点位，主撤离/大坝第二撤离复用）：绿色发光柱 + 地面绿环 + 绿光点光
func _build_extract(p: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = EXTRACT_BEACON_H
	pole.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.05, 0.2, 0.09)
	pm.emission_enabled = true
	pm.emission = Color(0.25, 1.0, 0.45)
	pm.emission_energy_multiplier = 2.2
	cm.material = pm
	pole.position = p + Vector3(1.6, EXTRACT_BEACON_H * 0.5, 1.2)
	add_child(pole)
	var light := OmniLight3D.new()
	light.light_color = Color(0.35, 1.0, 0.5)
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position = p + Vector3(1.6, EXTRACT_BEACON_H + 0.3, 1.2)
	add_child(light)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.08, 0.28, 0.13)
	rm.emission_enabled = true
	rm.emission = Color(0.25, 0.9, 0.42)
	rm.emission_energy_multiplier = 1.1
	tm.material = rm
	ring.mesh = tm
	ring.position = p + Vector3(0.0, 0.06, 0.0)
	add_child(ring)


# ================= 室内靶馆 =================

## 混凝土封闭壳 44×5×30：地坪/吊顶/四面墙（+Z 墙留门洞）/顶部成排灯板/
## 射击位隔断墙 ×3 / 黄黑警示条 / 车道编号 5/6/7 / 尽端挡弹墙；
## 壳体全部注册 obstacles（挡子弹与走人，仅门洞可进出）。
func _build_hall() -> void:
	var c := HDData.HALL_CENTER
	var cx := c.x
	var cz := c.z
	var mat_concrete := StandardMaterial3D.new()
	mat_concrete.albedo_color = Color(0.56, 0.55, 0.53)
	mat_concrete.roughness = 0.95
	var mat_trap := StandardMaterial3D.new()
	mat_trap.albedo_color = Color(0.18, 0.19, 0.2)   # 尽端挡弹墙：深色橡胶缓弹板
	mat_trap.roughness = 0.9

	# 地坪 / 吊顶：地坪顶面 = HALL_FLOOR_Y（0.06，与 ground_height 一致），
	# 与大地 y=0 错层根治共面闪烁；吊顶跟抬保持馆内净高 HALL_H
	_hall_box(cx, HALL_FLOOR_Y - 0.15, cz, HALL_HX * 2.0, 0.3, HALL_HZ * 2.0, mat_concrete)
	_hall_box(cx, HALL_FLOOR_Y + HALL_H + 0.15, cz,
			HALL_HX * 2.0, 0.3, HALL_HZ * 2.0, mat_concrete)
	# -Z 尽端挡弹墙（整面，靶道最深 22m + 缓冲；底部落在地坪上）
	_hall_box(cx, HALL_FLOOR_Y + HALL_H * 0.5, cz - HALL_HZ + HALL_TRAP_T * 0.5,
			HALL_HX * 2.0, HALL_H, HALL_TRAP_T, mat_trap)
	_add_obstacle(cx, cz - HALL_HZ + HALL_TRAP_T * 0.5, HALL_HX, HALL_TRAP_T * 0.5,
			HALL_FLOOR_Y + HALL_H)
	# +Z 墙（射击线后方）：中央留 HALL_DOOR_W 门洞，两段各 20m
	var seg := (HALL_HX * 2.0 - HALL_DOOR_W) * 0.5
	for side in [-1.0, 1.0]:
		var wx: float = cx + side * (HALL_HX - seg * 0.5)
		_hall_box(wx, HALL_FLOOR_Y + HALL_H * 0.5, cz + HALL_HZ - HALL_WALL_T * 0.5,
				seg, HALL_H, HALL_WALL_T, mat_concrete)
		_add_obstacle(wx, cz + HALL_HZ - HALL_WALL_T * 0.5, seg * 0.5,
				HALL_WALL_T * 0.5, HALL_FLOOR_Y + HALL_H)
	# 西墙 / 东墙
	for side in [-1.0, 1.0]:
		var wz := cz
		_hall_box(cx + side * (HALL_HX - HALL_WALL_T * 0.5), HALL_FLOOR_Y + HALL_H * 0.5,
				wz, HALL_WALL_T, HALL_H, HALL_HZ * 2.0, mat_concrete)
		_add_obstacle(cx + side * (HALL_HX - HALL_WALL_T * 0.5), wz,
				HALL_WALL_T * 0.5, HALL_HZ, HALL_FLOOR_Y + HALL_H)

	# 顶部成排发光灯板（3 排 ×5 列）+ 3 盏暖白点光（室内人工照明）
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.9, 0.88, 0.8)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(0.98, 0.95, 0.85)
	lamp_mat.emission_energy_multiplier = 2.0
	for pz in [cz - 8.0, cz, cz + 8.0]:
		for k in 5:
			var px := cx - 15.0 + float(k) * 7.5
			_hall_box(px, HALL_FLOOR_Y + HALL_H - 0.1, pz, 4.2, 0.1, 0.62, lamp_mat)
	for lp in [Vector3(cx - 8.0, HALL_FLOOR_Y + HALL_H - 0.6, cz),
			Vector3(cx + 8.0, HALL_FLOOR_Y + HALL_H - 0.6, cz),
			Vector3(cx, HALL_FLOOR_Y + HALL_H - 0.6, cz - 8.0)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.96, 0.88)
		l.light_energy = 1.2
		l.omni_range = 24.0
		l.position = lp
		add_child(l)

	# 射击位隔断墙 ×3（射击线两侧分道 + 西端封头），下实混凝土 1.2m 高（底部落在地坪上）
	for dx in [-3.0, -1.0, 1.0]:
		var dxz: float = cx + dx
		_hall_box(dxz, HALL_FLOOR_Y + 0.6, cz + HALL_FIRE_DZ, 0.12, 1.2, 6.0, mat_concrete)
		_add_obstacle(dxz, cz + HALL_FIRE_DZ, 0.1, 3.0, HALL_FLOOR_Y + 1.2)

	# 射击线黄黑警示条（双色交替 BoxMesh 拼一条横带，铺在地坪上方 2cm 防共面闪烁）
	var hy := HALL_FLOOR_Y + 0.02
	for k in 20:
		var sx := cx - 19.0 + float(k) * 2.0
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.78, 0.6, 0.12) if k % 2 == 0 else Color(0.12, 0.12, 0.12)
		bm.roughness = 0.85
		_hall_box(sx, hy, cz + HALL_FIRE_DZ - 1.0, 2.0, 0.02, 0.4, bm)

	# 墙面车道编号 5/6/7（挡弹墙内面，面朝 +Z 射手）
	for i in 3:
		var num := Label3D.new()
		num.text = "%d" % (5 + i)
		num.font_size = 320
		num.pixel_size = 0.004
		num.modulate = Color(0.93, 0.9, 0.8)
		num.outline_size = 16
		num.position = Vector3(cx - 2.0 + float(i) * 2.0, HALL_FLOOR_Y + 3.2,
				cz - HALL_HZ + HALL_TRAP_T + 0.05)
		add_child(num)


## 靶馆构件盒体（纯视觉，不登记 obstacles——由调用方按需登记）
func _hall_box(x: float, y: float, z: float, w: float, h: float, d: float,
		mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(x, y, z)
	add_child(mi)


# ================= 射线 =================

## 射线 vs 单个障碍：2D(xz) 平板求交 + 高度过滤（矮障碍可从上方射过），
## 无命中返回传入的 lim（调用方层层收紧取最近墙）
func _ray_aabb(from: Vector3, dir: Vector3, ob: Dictionary, lim: float) -> float:
	var t0 := 0.0
	var t1 := lim
	var ox := from.x - float(ob["cx"])
	var oz := from.z - float(ob["cz"])
	# X 轴平板
	if absf(dir.x) < 0.000001:
		if absf(ox) > float(ob["hx"]):
			return lim
	else:
		var tax := (-float(ob["hx"]) - ox) / dir.x
		var tbx := (float(ob["hx"]) - ox) / dir.x
		if tax > tbx:
			var tx := tax
			tax = tbx
			tbx = tx
		t0 = maxf(t0, tax)
		t1 = minf(t1, tbx)
		if t0 > t1:
			return lim
	# Z 轴平板
	if absf(dir.z) < 0.000001:
		if absf(oz) > float(ob["hz"]):
			return lim
	else:
		var taz := (-float(ob["hz"]) - oz) / dir.z
		var tbz := (float(ob["hz"]) - oz) / dir.z
		if taz > tbz:
			var tz := taz
			taz = tbz
			tbz = tz
		t0 = maxf(t0, taz)
		t1 = minf(t1, tbz)
		if t0 > t1:
			return lim
	# 高度过滤：弹道在 [t0,t1] 的 y 区间与障碍 [bot,top] 无交集则穿过
	var top: float = float(ob.get("top", 1000.0))
	var bot: float = float(ob.get("bot", 0.0))
	var ya := from.y + dir.y * t0
	var yb := from.y + dir.y * t1
	if minf(ya, yb) > top or maxf(ya, yb) < bot:
		return lim
	return maxf(t0, 0.0)
