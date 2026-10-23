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
## 四新区件（军营/大电/水泥厂/游客中心）同由路径 preload：新 class_name
## HDDamZones 在 --headless -s 回归下同样不进全局类名缓存，走路径最稳
const HDDAM_ZONES_SCRIPT := preload("res://scripts/hd_dam_zones.gd")
const BATCH := preload("res://scripts/hd_batch.gd")
const PBR := preload("res://scripts/hd_pbr.gd")   # 美术写实化：CC0 实拍 PBR 贴图（缺失自动回退纯色）
## 实拍 HDRI 天空（Poly Haven kloofendal_43d_clear_puresky，CC0）：天空本身 +
## 环境光 + 反射都取它；Git LFS 没拉到时回退物理天空（另一台电脑不崩）
const SKY_HDRI := "res://assets/pbr/hdri/kloofendal_43d_clear_puresky_2k.hdr"
## HDRI 里太阳的方位（离线量得：等距柱状图 u=0.600 v=0.262 → 仰角 42.9°）：
## 主光按它摆，影子方向与天空里的太阳一致
const HDRI_SUN_ROT := Vector3(-42.9, -35.9, 0.0)
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
## 美术写实化：这些道具换成 Poly Haven 实拍扫描级模型（CC0）。按原包围盒等比
## 塞进去——碰撞、点位、掩体尺寸全不变；模型缺失（另一台电脑没拉 LFS）回退原 GLB
const PH_SWAP := {
	"barrel": "res://assets/pbr/models/Barrel_01/Barrel_01_1k.gltf",
	"crate": "res://assets/pbr/models/wooden_crate_01/wooden_crate_01_1k.gltf",
	"rocks": "res://assets/pbr/models/boulder_01/boulder_01_1k.gltf",
	"covered_car": "res://assets/pbr/models/covered_car/covered_car_1k.gltf",
}
const PH_TYRE := "res://assets/pbr/models/old_tyre/old_tyre_1k.gltf"
const PH_JERRYCAN := "res://assets/pbr/models/metal_jerrycan/metal_jerrycan_1k.gltf"
## 道具 GLB 内材质名 → PBR 贴图类（木头/麻袋/帆布/树皮没有对应实拍贴图，保留原样）
const PROP_PBR := {"Plaster": "stucco", "Concrete": "concrete", "Paint": "paint_rust",
		"TankPaint": "paint_rust", "Rust": "paint_rust", "Metal": "paint_rust", "Rock": "rock",
		"Bark": "bark"}
## 地表点缀（实拍减面版）：枯枝丛 + 低矮灌丛，散布在中环/荒野空地
const GROUND_COVER := [
	{"path": "res://assets/pbr/models/dry_branches_medium_01/dry_branches_medium_01_lod.glb",
		"n": 150, "smin": 0.8, "smax": 1.35, "sy": 1.0},
	{"path": "res://assets/pbr/models/shrub_04/shrub_04_lod.glb",
		"n": 110, "smin": 1.8, "smax": 3.2, "sy": 1.25},
]
const COVER_CHUNK := 50.0          # 散布分块边长（分块才能按距离裁剪/切 LOD）
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
const HALL_FIRE_DZ := 11.0        # 射击线距馆心（+Z 侧）
const HALL_TRAP_T := 0.6          # 尽端挡弹墙厚度（-Z 端）
const HALL_FLOOR_Y := -6.94       # 地下馆地坪（2026-10 用户定案「靶场做在地下」）：馆顶 -1.94，地表 0 之下 1.94m 覆土；地表入口房在馆北 (120,154)，阶梯坡道下行

## 地下入口几何常量（_build_entrance 与 ground_height 分层共用）
const HALL_RAMP_X0 := 116.0       # 坡道/连廊西缘
const HALL_RAMP_X1 := 124.0       # 坡道/连廊东缘（8m 宽）
const HALL_RAMP_Z0 := 147.0       # 坡道底端（接地下连廊）
const HALL_RAMP_Z1 := 157.0       # 坡道顶端（入口房地坪面）
const HALL_HOUSE_Z0 := 147.0      # 入口房南墙
const HALL_HOUSE_Z1 := 161.0      # 入口房北墙
const HALL_TUNNEL_Z0 := 143.0     # 地下连廊北端（接馆 +Z 墙门洞）

## 撤离信标（绿色发光柱 + 地面绿环）
const EXTRACT_BEACON_H := 2.6

## set_indoor 前后对比（进靶馆：雾拉近/环境光压暗/漏进来的夕阳压弱）
## 雾密度红线：指数雾 exp(-d·dist)——第 3 轮 0.003→0.005：0.004 档下
## 150m 透射 ~55%（原 0.002 为 74%）、士兵赭红军装在浅暖霾中仍读作深色剪影
## （问题②结论复核仍守），>120m 才显著衰减换远山大气层次（评审 #9）
const FOG_MAX := 0.005              # 远景可见性红线
## 对照优化第 5 轮教训：0.004 在 204m 对位机位上累积 ~80% 雾遮蔽，把扶壁垛/泄洪管
## 全洗没（评审「缺扶壁垛」实为看不见）。目标图是晴朗白天——压到 0.0012：
## 200m 处透射 ~79%，大坝剪影清晰可辨，120m 内几乎无感。
## 第 3 轮判图 #1：0.0012×90m+ 仍把中环剪影糊掉——再降一档到 0.0008；
## 第 4 轮判图 #7：中远景仍灰霾、山脊白化断层——终值 0.0005（400m 透射 ~82%，
## 近中景 ≈0 衰减、远山仅留薄大气层；真「近0/中0.3/远0.6 分层」在 Godot 指数
## 雾模型内不可参数化——本值为程序化可达的最近似，配合体积雾压低实现分层感）
const OUTDOOR_FOG := 0.0005         # 晴天：中环剪影层干净（对照目标图）
## INDOOR_FOG 刻意压在红线内一格：fog_density 引擎侧按 float32 存储，
## 0.003 会舍入成 0.003000000026… 反超 double 红线（回归 15 踩过）；0.0029 双保险
const INDOOR_FOG := 0.0029          # 靶馆 22m 靶道只留薄雾感（原 0.02 把靶子糊成剪影）
## 第 3 轮判图 #1：环境光提亮半档（0.45→0.58）——上轮 −0.4EV 后暗面发灰，
## 提环境光比提曝光更保高光不炸
const OUTDOOR_AMB := 0.58
const INDOOR_AMB := 0.55
const OUTDOOR_SUN := 1.7
const INDOOR_SUN := 0.25

## 可搜刮容器锚点（x/z 手工排布贴障碍摆：中心 18 / 过渡 11 / 荒野 9 + 坝区 13
## 由 HDDamBase 追加 + 四新区 7 由 HDDamZones 追加 = 58；原 mid/wild 落在大坝
## 矩形内的 6 点已迁入坝区表；四新区轮两点微调：(96,0)→(104,−4) 挪入大电西院
## 当航空储物箱锚点（实测 mid）、(−84,44)→(−84,50) 让水泥厂宿舍 footprint
## （d=97.5 实测 mid）；(84,44) 原地保留=游客中心南广场北缘锚点（实测 mid））
const CONTAINER_XZ := {
	"center": [
		Vector2(-18, -32), Vector2(-30, -30), Vector2(-46, -44), Vector2(-24, -52),
		Vector2(-10, -44), Vector2(10, -50), Vector2(24, -40), Vector2(34, -20),
		Vector2(26, -12), Vector2(13, -19), Vector2(2, -6), Vector2(-8, 2),
		Vector2(-18, 10), Vector2(-4, 22), Vector2(10, 30), Vector2(-24, -12),
		Vector2(18, 6), Vector2(-34, 22),
	],
	"mid": [
		Vector2(0, 92), Vector2(44, 84), Vector2(84, 44), Vector2(104, -4),
		Vector2(84, -44), Vector2(-84, -44), Vector2(-96, 0), Vector2(-84, 50),
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
var spawn_pos := Vector3(-138.0, 0.0, 138.0)   # 本局出生点（main 每局从 HDData.SPAWN_POINTS 随机取）
var extract_pos: Vector3 = HDData.EXTRACT_POS  # 主撤离点（绿信标）
var extract2_pos: Vector3 = HDData.DAM_EXTRACT_POS   # 第二撤离点（大坝撤离广场，信标同款）
var paid_pos: Vector3 = HDData.PAID_EXTRACT_POS      # 付费撤离（金色信标）
var lever_ext_pos: Vector3 = HDData.LEVER_EXTRACT_POS   # 拉闸撤离（蓝色信标）
var tunnel_pos: Vector3 = HDData.TUNNEL_EXTRACT_POS   # 军营北隧道撤离（绿信标常开，阶段 B）
var _extract_vis := {}            # id -> {mats:[StandardMaterial3D], light, col, nodes}
var _lever_handle: Node3D         # 电闸手柄（拉下后转角）
var dam: Node3D                   # 大坝硬结构（HDDam 实例：坝体/廊道/涂鸦/闸门排，视觉挂本类）
var dam_base: Node3D              # 坝底工业区（HDDamBase 实例：厂房/堆场/工地 + 坝区点位）
var batch_stats := {}             # 静态合批结果 {merged, meshes}（性能探针/测试读）
var dam_zones: Node3D             # 四新区（HDDamZones 实例：军营/大电/水泥厂/游客中心 + 新点位）

var _built := false
var _prop_scenes := {}            # name -> PackedScene | null（load 缓存）
var _ph_scenes := {}              # path -> PackedScene | null（实拍模型缓存）
var _fallback_mats := {}          # name -> StandardMaterial3D（兜底盒共用）
var _sun: DirectionalLight3D
var _env: Environment
var _indoor := false            # 靶馆室内氛围态（set_indoor）
var _variant := "clear"         # 当前天气变体（apply_variant；晴朗缺省）
var _var_def: Dictionary = {}   # 变体参数（RAID_VARIANTS 条目）
var _rain: GPUParticles3D       # 雨粒子（跟玩家，rain 变体可见）
var _hdri_on := false   # 实拍 HDRI 天空是否加载成功（失败回退物理天空 + 噪声云带）


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
	_scatter_decor()
	_build_hall()
	_build_entrance()
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
	# 四新区最后装配（DAM→BASE→ZONES 次序：中环四区陈设在坝体/坝底之后，
	# 障碍与点位 append 顺序不影响 wall_hit/搜索语义，只保证节点树层级稳定）
	dam_zones = HDDAM_ZONES_SCRIPT.new()
	add_child(dam_zones)
	dam_zones.build(self)
	# 撤离信标 ×4：主撤离（东侧绿标）+ 大坝广场（定时开放）+ 付费（金）+ 拉闸（蓝）；
	# 开放状态由 main 每局按规则切（set_extract_state）
	_extract_vis["main"] = _build_extract(extract_pos, Color(0.25, 1.0, 0.45))
	_extract_vis["dam"] = _build_extract(extract2_pos, Color(0.25, 1.0, 0.45))
	_extract_vis["paid"] = _build_extract(paid_pos, Color(1.0, 0.78, 0.25))
	_extract_vis["lever"] = _build_extract(lever_ext_pos, Color(0.3, 0.7, 1.0))
	_extract_vis["tunnel"] = _build_extract(tunnel_pos, Color(0.25, 1.0, 0.45))
	_build_lever(HDData.LEVER_POS)
	# 地表植被最后撒：大坝/四新区的障碍物都已登记，才能避开建筑
	_scatter_ground_cover()
	# 静态陈设合批（第四阶段性能门槛 D：出生点绘制调用 < 800）——必须最后做：
	# 之前的装配/PBR 换皮都要先落定
	batch_stats = BATCH.run(self)


## 进靶馆模式：雾拉近/环境光稍暗/夕阳压弱（室内氛围）；回大厅/行动恢复。
## 集成者用 has_method("set_indoor") 探测调用。户外值随天气变体乘数走（阶段 C）。
func set_indoor(on: bool) -> void:
	if _env == null:
		return
	_indoor = on
	_apply_atmos()


## 应用昼夜/天气变体（阶段 C）：HDData.RAID_VARIANTS[id]——太阳能量/色/俯角、
## 环境光、雾密度乘户外常量；雨变体挂雨粒子（update_rain 每帧跟玩家）。
## 未知 id 回落晴朗。室内（靶馆）优先保持室内氛围，变体乘数在出馆时生效。
func apply_variant(id: String) -> void:
	_variant = id
	_var_def = HDData.RAID_VARIANTS.get(id, {}) if HDData.RAID_VARIANTS.has(id) else {}
	_apply_atmos()
	if _rain != null:
		_rain.visible = bool(_var_def.get("rain", false)) and not _indoor


## 大气三件套统一落点：indoor 用室内常量；户外 = OUTDOOR_* × 变体乘数
func _apply_atmos() -> void:
	if _env == null:
		return
	if _indoor:
		_env.fog_density = INDOOR_FOG
		_env.ambient_light_energy = INDOOR_AMB
		if _sun != null:
			_sun.light_energy = INDOOR_SUN
		return
	var fog_m := float(_var_def.get("fog", 1.0))
	var amb_m := float(_var_def.get("amb", 1.0))
	var sun_m := float(_var_def.get("sun", 1.0))
	_env.fog_density = OUTDOOR_FOG * fog_m
	_env.ambient_light_energy = OUTDOOR_AMB * amb_m
	if _sun != null:
		_sun.light_energy = OUTDOOR_SUN * sun_m
		if _var_def.has("sun_color"):
			_sun.light_color = _var_def["sun_color"]
		else:
			_sun.light_color = Color(1.0, 0.96, 0.9)
		if _var_def.has("sun_rot_x"):
			_sun.rotation_degrees = Vector3(float(_var_def["sun_rot_x"]),
					_sun.rotation_degrees.y, 0.0)
		else:
			_sun.rotation_degrees = Vector3(-40.0, _sun.rotation_degrees.y, 0.0)


## 雨粒子跟玩家（main._process 调）：发射盒罩住玩家周围 26m，进馆隐藏
func update_rain(player_pos: Vector3) -> void:
	if _rain == null or not _rain.visible:
		return
	_rain.position = Vector3(player_pos.x, player_pos.y + 12.0, player_pos.z)


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


## 全部撤离点定义（2026-10 第三阶段：主 / 大坝定时 / 付费 / 拉闸）
func extract_defs() -> Array:
	return [
		{"id": "main", "pos": extract_pos, "name": "撤离"},
		{"id": "dam", "pos": extract2_pos, "name": "大坝撤离"},
		{"id": "paid", "pos": paid_pos, "name": "付费撤离"},
		{"id": "lever", "pos": lever_ext_pos, "name": "拉闸撤离"},
		{"id": "tunnel", "pos": tunnel_pos, "name": "隧道撤离"},
	]


## 撤离信标状态：open 原色常亮 / closed 暗红（本局有但尚未开放）/ off 全灭（本局不开）
func set_extract_state(id: String, state: String) -> void:
	if not _extract_vis.has(id):
		return
	var v: Dictionary = _extract_vis[id]
	var col: Color = v["col"]
	var on := state != "off"
	for n in v["nodes"]:
		(n as Node3D).visible = on
	if not on:
		return
	var c := col if state == "open" else Color(0.75, 0.18, 0.12)
	for m in v["mats"]:
		var sm := m as StandardMaterial3D
		sm.emission = c
		sm.albedo_color = c * 0.2
	var lt := v["light"] as OmniLight3D
	lt.light_color = c
	lt.light_energy = 2.4 if state == "open" else 0.8


## 电闸手柄：拉下（pulled）后向下转 100°
func set_lever_pulled(pulled: bool) -> void:
	if _lever_handle != null:
		_lever_handle.rotation.z = deg_to_rad(100.0) if pulled else 0.0   # 朝屋内扳下


## 是否在靶馆矩形内（含墙体）
func in_hall(x: float, z: float) -> bool:
	var c := HDData.HALL_CENTER
	return absf(x - c.x) <= HALL_HX and absf(z - c.z) <= HALL_HZ


## 是否处于地图外独立空间（旧 e515451 靶馆外迁语义）：靶馆已回归地图地下，
## 地图钳制在图内全程安全；保留函数（玩家行走仍调用）但恒 false——
## 地下馆在图内，钳制不会误拽
func in_separate_space(p: Vector3) -> bool:
	return false


## 是否处于地下域（靶馆/连廊，y 低于馆顶 -1.94）：HDPlayer.update 的地图
## 边界钳制对地下域无需豁免（馆体在图内），保留函数供Walking 语义判断
func in_underground(p: Vector3) -> bool:
	return p.y < HALL_FLOOR_Y + HALL_H - 0.5


## 地面高度（分层采样）：地表 0 / 入口房地坪 0.06 / 阶梯坡道线性下行 /
## 地下连廊与馆内地坪 HALL_FLOOR_Y。分层契约：
## - 坡道/连廊无条件返回（唯一进出通道，且都在入口房/覆土结构内部）
## - 馆体矩形带 y_hint 守卫：地表行走（y_hint ≥ 馆顶）不受脚下的馆影响
##   ——否则地表玩家走到馆上方会被拽进地下
func ground_height(x: float, z: float, y_hint := 100.0) -> float:
	# 阶梯坡道（入口房内开洞，南向下行）：z 157→147 线性 0.06→-6.88
	if x >= HALL_RAMP_X0 and x <= HALL_RAMP_X1 \
			and z >= HALL_RAMP_Z0 and z <= HALL_RAMP_Z1:
		return 0.06 - (HALL_RAMP_Z1 - z) * ((0.06 - HALL_FLOOR_Y)
				/ (HALL_RAMP_Z1 - HALL_RAMP_Z0))
	# 地下连廊（坡道底→馆 +Z 门洞，覆土之下）
	if x >= HALL_RAMP_X0 and x <= HALL_RAMP_X1 \
			and z >= HALL_TUNNEL_Z0 and z < HALL_RAMP_Z0:
		return HALL_FLOOR_Y
	# 入口房地坪（坡道开洞之外的房内地板）
	if x >= HALL_RAMP_X0 - 4.0 and x <= HALL_RAMP_X1 + 4.0 \
			and z >= HALL_HOUSE_Z0 and z <= HALL_HOUSE_Z1:
		return 0.06
	# 馆体矩形：仅地下域生效
	if in_hall(x, z):
		if y_hint < HALL_FLOOR_Y + HALL_H - 0.5:
			return HALL_FLOOR_Y
		return 0.0
	return 0.0


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
	var hdri: Texture2D = load(SKY_HDRI) if ResourceLoader.exists(SKY_HDRI) else null
	_hdri_on = hdri != null
	if _hdri_on:
		_sun.rotation_degrees = HDRI_SUN_ROT
	_sun.shadow_enabled = true
	# 2026-10 性能定案（用户要求 ≥55 帧）：spawn 朝坝 16→36 帧的元凶是阴影
	# 渲染——300m 阴影距离 + 默认 4096 贴图让上千坝体分件全量进 shadow pass。
	# 三刀：①阴影距离 300→160（坝顶远景阴影本就看不清，明暗由 AOsuffice）
	# ②blur 1.0→0.6（贴图带宽减负）③PSSM 斜切 2 段（默认 4 段对大静态场景
	# 过度细分）；阴影视觉质量靠 bias/opacity 维持，判图以截图回归兜底
	_sun.directional_shadow_max_distance = 160.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.shadow_bias = 0.06
	_sun.shadow_blur = 0.6
	_sun.shadow_opacity = 0.9
	# 阴影贴图 4096→2048（ProjectSettings 只能启动前改——main.gd _ready 里
	# 通过 project_settings 无效，改在 project.godot；此处兜底再设一次）
	add_child(_sun)
	# —— 冷天光补光（第 5 轮双色温架构）：从主阳反向的半空铺冷蓝天光，
	#    阴影面偏蓝、受光面偏暖——无阴影、低能量，只做暗部染色
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.72, 0.92)
	fill.light_energy = 0.32
	fill.rotation_degrees = Vector3(-38.0, 155.0, 0.0)
	fill.shadow_enabled = false
	fill.visible = not _hdri_on   # HDRI 天空下天光来自真实环境光，假补光会把阴影洗蓝
	add_child(fill)
	# —— 雨粒子（阶段 C 雨天变体）：细长雨丝盒发射 26×22×26 罩玩家（update_rain
	#    跟人）、重力下坠；晴朗/夜晚/浓雾不显示——构建一次按变体切可见
	_rain = GPUParticles3D.new()
	_rain.amount = 420
	_rain.lifetime = 1.1
	_rain.visibility_aabb = AABB(Vector3(-14.0, -13.0, -14.0), Vector3(28.0, 26.0, 28.0))
	var rmat := ParticleProcessMaterial.new()
	rmat.direction = Vector3(0.06, -1.0, 0.03)
	rmat.spread = 4.0
	rmat.initial_velocity_min = 17.0
	rmat.initial_velocity_max = 21.0
	rmat.gravity = Vector3(0.0, -6.0, 0.0)
	rmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rmat.emission_box_extents = Vector3(13.0, 11.0, 13.0)
	_rain.process_material = rmat
	var rq := QuadMesh.new()
	rq.size = Vector2(0.012, 0.55)
	rq.material = StandardMaterial3D.new()
	(rq.material as StandardMaterial3D).albedo_color = Color(0.65, 0.72, 0.8, 0.42)
	(rq.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	(rq.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_rain.draw_pass_1 = rq
	_rain.visible = false
	add_child(_rain)

	# —— 物理大气散射天空（第 3 轮判图 #1：上轮 turbidity 6 把天读成死板灰蓝
	#    一块——回落到 3.5 保地平过渡带，同时瑞利 2.5 拉开天顶饱和蓝↔地平微暖
	#    的连续渐变，配 ground_color 暖一档）——
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.5    # 瑞利散射：天顶饱和蓝→地平暖白的连续渐变
	sky_mat.mie_coefficient = 0.008       # 米氏散射：太阳方向光晕
	sky_mat.mie_eccentricity = 0.75
	sky_mat.turbidity = 3.5               # 干燥晴天：宽渐变带但不发灰
	sky_mat.ground_color = Color(0.55, 0.47, 0.36)   # 地平暖沙色衔接大地（物理天空单色地面）
	sky_mat.energy_multiplier = 1.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	if _hdri_on:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri
		pano.energy_multiplier = 1.0
		sky.sky_material = pano
		sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# 曝光迭代史：第 2 轮判图 #18 过曝死白降 0.4EV（1.1→0.83）；第 3 轮判图 #1
	# 反馈整体偏暗发灰——回调到 −0.22EV（0.92），配环境光提亮半档，保高光不炸
	env.tonemap_exposure = 0.92
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = OUTDOOR_FOG
	# 冷蓝大气透视（对照目标图：远山偏蓝、天空保持蓝天不被雾染）——
	# 原暖霾色 + fog_sky_affect 0.08 是第 5 轮「米色洗白」的元凶之一
	env.fog_light_color = Color(0.72, 0.78, 0.88)
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.57, 0.5)
	env.ambient_light_energy = OUTDOOR_AMB
	if _hdri_on:
		# 写实化：环境光/反射取实拍天空（不再是一块固定米色），
		# SDFGI 实时全局光照——墙角、门洞、厂房内部按真实遮挡变暗，
		# 地面暖沙色反弹到墙面（代码场景无需烘焙，Forward+ 可用）
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 1.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_energy = 1.0
		env.sdfgi_bounce_feedback = 0.5
		env.tonemap_exposure = 0.85
	env.ssao_enabled = true          # 垛间凹槽/洞龛深色竖条纹（评审 #8）
	env.ssao_intensity = 2.6         # 第 2 轮判图 #18：上调补接触阴影（帐篷/设备底部悬浮感）
	env.ssil_enabled = true          # 屏幕空间间接光：暗面暖沙色反弹（第 5 轮架构）
	env.ssil_intensity = 0.6
	# 体积雾：只留低密度冷白前向散射做坝脚纵深（0.012 暖沙色曾把全帧洗成米色）；
	# 第 4 轮判图 #7：0.004×160m 在中景叠出「灰霾」且远山白化断层——密度减半、
	# 深度推远到 260m：近景≈0、中景薄散射、远山保轮廓（分层感的另一半）
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0018
	env.volumetric_fog_albedo = Color(0.88, 0.92, 1.0)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 260.0
	# 调色分级（第 5 轮架构）：饱和/对比一键对位「暖沙色高饱和」（评审 #6 终解）
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.18
	if _hdri_on:
		# 写实化：去掉「高饱和」调色（实拍贴图自带真实色彩，再 +18% 饱和就是卡通感）
		env.adjustment_contrast = 1.0
		env.adjustment_saturation = 1.0
	env.glow_enabled = true          # 信标/灯板泛光
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.05
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# —— 全图大盒反射探针（第 3 轮判图 #2：玻璃幕墙 metallic 材质在纯 ambient
	#    环境下是死色——一个大范围 ONCE 烘焙探针让 sky 渐变进玻璃/金属反射，
	#    一次性烘焙零每帧开销；游客中心幕墙「上半幅映天色」由它兑现）——
	var probe := ReflectionProbe.new()
	probe.size = Vector3(320.0, 120.0, 320.0)
	probe.position = Vector3(0.0, 60.0, 0.0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.8
	probe.box_projection = true
	add_child(probe)
	if not _hdri_on:
		_build_clouds()   # 噪声云带只给物理天空兜底用；实拍天空自带真实云


## 高空云带 ×3（评审 #7 丝缕白云的工程内替代：ProceduralSkyMaterial 无
## sky_cover 属性——4.7 运行时报 Invalid assignment 曾致回归挂死，见上）。
## unshaded 半透明噪声 PlaneMesh 平铺高空：cast_shadow OFF 不投地面影，
## 距 ref 相机 250~350m 经暖霾（fog 0.004）衰减成淡丝缕，正对目标图
## 左上/中上天区；远高于山脊顶 72 与塔吊顶 80，不遮挡
const CLOUD_BANDS := [
	{"y": 155.0, "x": 10.0, "z": -170.0, "w": 420.0, "d": 60.0},
	{"y": 175.0, "x": -90.0, "z": -240.0, "w": 520.0, "d": 80.0},
	{"y": 165.0, "x": 130.0, "z": -210.0, "w": 380.0, "d": 55.0},
	# 第 3 轮判图 #11：第 4 条低空近侧带（y120,z+40）在 new1 低机位读出水平
	# 拉伸贴片——抬升并挪到坝后中景纵深位（y145/z-100），拉伸读法消失
	{"y": 145.0, "x": -20.0, "z": -100.0, "w": 300.0, "d": 46.0},
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
	cramp.set_color(1, Color(1.0, 1.0, 1.0, 0.92))   # 第 2 轮判图 #20：云可读性上调
	ctex.color_ramp = cramp
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = ctex
	cm.albedo_color = Color(0.98, 0.98, 1.0, 0.95)
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
	mat.albedo_color = Color(0.52, 0.45, 0.35)   # 浅沙色戈壁（第 2 轮判图 #18：
	# 0.6,0.52,0.4 过曝死白——压暗一档防「白模」感，乘噪点后仍读浅沙）
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(7.0, 7.0, 1.0)   # 低频大尺度斑块破纯色（第 2 轮 20→7）
	mat.roughness = 1.0
	mat.metallic_specular = 0.0   # 干燥地面不反射天空
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.material = mat
	var sand := PBR.maps("sand")
	if not sand.is_empty():
		# 写实化：实拍砾沙 PBR（颜色/法线/ARM）。两种尺度叠加 + 60m 大斑块明暗，
		# 打散 2.5m 周期的重复感；原噪声图降级为大斑块遮罩
		var sm := ShaderMaterial.new()
		sm.shader = _ground_shader()
		sm.set_shader_parameter("albedo_tex", sand["diff"])
		sm.set_shader_parameter("normal_tex", sand["nor"])
		sm.set_shader_parameter("arm_tex", sand["arm"])
		sm.set_shader_parameter("macro_tex", tex)
		plane.material = sm
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	add_child(mi)


## 地表着色器：世界 XZ 平铺（与 PlaneMesh 的 UV/切线同向，法线贴图方向正确）
func _ground_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 2.6;
uniform float macro_m = 70.0;
uniform vec3 tint = vec3(1.02, 0.98, 0.92);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wpos.xz / tile_m;
	vec2 uv2 = wpos.xz / (tile_m * 3.3) + vec2(0.37, 0.71);
	float far = smoothstep(12.0, 70.0, length(VERTEX));
	vec3 a1 = texture(albedo_tex, uv).rgb;
	vec3 a2 = texture(albedo_tex, uv2).rgb;
	float macro = texture(macro_tex, wpos.xz / macro_m).r;
	ALBEDO = mix(a1, a1 * 0.5 + a2 * 0.5, far) * tint * mix(0.82, 1.1, macro);
	vec3 arm = texture(arm_tex, uv).rgb;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = mix(arm.g, 0.95, far);
	METALLIC = 0.0;
	SPECULAR = 0.35;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = mix(1.2, 0.4, far);
}
"""
	return sh


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
	# 残骸里每隔一辆换成盖布旧车（同尺寸车位：1.8×1.4×4.4 m），工业区更有生活痕迹
	var swap_name := name
	if name == "wreck" and int(absf(x * 7.0 + z * 3.0)) % 2 == 0:
		swap_name = "covered_car"
	var ph: PackedScene = _ph_scene(str(PH_SWAP.get(swap_name, "")))
	if ph != null:
		node = Node3D.new()
		node.position = Vector3(x, y_off, z)
		node.rotation.y = rot_y
		node.scale = scl
		if name == "rocks":
			# 原岩堆是 13.6m 长条：三块巨石沿长轴错落拼出同样的轮廓
			_fit_into(node, ph.instantiate(), Vector3(4.6, 2.2, 3.3), Vector3(-4.5, 0, 0.2), 0.4)
			_fit_into(node, ph.instantiate(), Vector3(4.2, 1.7, 3.0), Vector3(0.2, 0, -0.3), 2.1)
			_fit_into(node, ph.instantiate(), Vector3(4.6, 2.0, 3.2), Vector3(4.4, 0, 0.1), 4.0)
		else:
			_fit_into(node, ph.instantiate(), dims, Vector3.ZERO, 0.0)
		add_child(node)
	elif ps != null:
		node = ps.instantiate()
		node.position = Vector3(x, y_off, z)
		node.rotation.y = rot_y
		node.scale = scl
		_dress_prop(node, name, tint)
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
## 地表植被点缀：只撒在中环/荒野空地（避开障碍物外扩 1.5m、出生点、撤离点、
## 靶馆入口），固定种子可复现；按 50m 分块建 MultiMesh，120m 外淡出
func _scatter_ground_cover() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261017
	var keep_out: Array = [spawn_pos, extract_pos, extract2_pos, paid_pos, lever_ext_pos, tunnel_pos,
			Vector3(120.0, 0.0, 154.0)]
	keep_out.append_array(HDData.SPAWN_POINTS)
	for spec in GROUND_COVER:
		var ps := PBR.scene(str(spec["path"]))
		if ps == null:
			continue
		var parts: Array = PBR.meshes_of(ps)
		var chunks := {}   # Vector2i -> Array[Transform3D]
		var placed := 0
		var tries := 0
		while placed < int(spec["n"]) and tries < int(spec["n"]) * 12:
			tries += 1
			var x := rng.randf_range(-BOUND + 4.0, BOUND - 4.0)
			var z := rng.randf_range(-BOUND + 4.0, BOUND - 4.0)
			var zone := zone_at(x, z)
			if zone != "mid" and zone != "wild":
				continue
			var ok := true
			for kp in keep_out:
				if Vector2(x - kp.x, z - kp.z).length() < 7.0:
					ok = false
					break
			if ok:
				for ob in obstacles:
					if absf(x - float(ob["cx"])) < float(ob["hx"]) + 1.5 \
							and absf(z - float(ob["cz"])) < float(ob["hz"]) + 1.5 \
							and float(ob["top"]) < 30.0:
						ok = false
						break
			if not ok:
				continue
			var sc := rng.randf_range(float(spec["smin"]), float(spec["smax"]))
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
					.scaled(Vector3(sc, sc * float(spec["sy"]), sc)), Vector3(x, 0.0, z))
			var key := Vector2i(int(floor(x / COVER_CHUNK)), int(floor(z / COVER_CHUNK)))
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(xf)
			placed += 1
		for key in chunks:
			var xfs: Array = chunks[key]
			for part in parts:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = part["mesh"]
				mm.instance_count = xfs.size()
				for i in xfs.size():
					mm.set_instance_transform(i, (xfs[i] as Transform3D) * (part["xf"] as Transform3D))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.visibility_range_end = 120.0
				mmi.visibility_range_end_margin = 15.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				add_child(mmi)


## 写实化小件点缀（纯装饰、不登记碰撞）：每辆残骸/盖布车旁一只旧轮胎，
## 每隔一个木箱放一个铁油壶——生活痕迹，不改任何掩体与点位
func _scatter_decor() -> void:
	var tyre := _ph_scene(PH_TYRE)
	var can := _ph_scene(PH_JERRYCAN)
	var k := 0
	for list in [CENTER_PROPS, MID_PROPS, WILD_PROPS]:
		for e in list:
			var n: String = e["n"]
			var r: float = float(e.get("r", 0.0))
			var off := Vector3.ZERO
			var ps: PackedScene = null
			var size := 0.75
			if n == "wreck" and tyre != null:
				off = Vector3(1.7, 0.0, -1.2)
				ps = tyre
			elif n == "crate" and can != null and k % 2 == 0:
				off = Vector3(0.9, 0.0, 0.5)
				ps = can
				size = 0.5
			if n == "crate":
				k += 1
			if ps == null:
				continue
			var holder := Node3D.new()
			holder.position = Vector3(float(e["x"]), 0.0, float(e["z"])) \
					+ off.rotated(Vector3.UP, r)
			add_child(holder)
			_fit_into(holder, ps.instantiate(), Vector3.ONE * size, Vector3.ZERO,
					r + 0.7 + float(k) * 1.3)


## 实拍模型（gltf）加载缓存；路径空或加载失败返回 null（调用方回退原 GLB）
func _ph_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if not _ph_scenes.has(path):
		_ph_scenes[path] = load(path) if ResourceLoader.exists(path) else null
		if _ph_scenes[path] == null:
			push_warning("[烽火地带] 实拍模型缺失：%s（另一台电脑请 git lfs pull，暂用原模型）" % path)
	return _ph_scenes[path]


## 把模型等比缩放进 box（宽×高×深）里：底面贴地、XZ 居中于 offset，绕 Y 转 yaw
func _fit_into(parent: Node3D, inst: Node3D, box: Vector3, offset: Vector3,
		yaw: float) -> void:
	var bb := _local_aabb(inst)
	var sz := bb.size
	var k := minf(box.y / maxf(sz.y, 0.001),
			minf(box.x / maxf(sz.x, 0.001), box.z / maxf(sz.z, 0.001)))
	var pivot := Node3D.new()
	pivot.position = offset
	pivot.rotation.y = yaw
	parent.add_child(pivot)
	var c := bb.get_center()
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-c.x * k, -bb.position.y * k, -c.z * k)
	pivot.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 子网格在 root 本地空间的合并包围盒（不依赖入树）
func _local_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null:
			continue
		var t := Transform3D()
		var q: Node = m
		while q != root and q != null:
			if q is Node3D:
				t = (q as Node3D).transform * t
			q = q.get_parent()
		var a: AABB = t * m.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## 道具材质写实化：按材质名换实拍 PBR（集装箱漆面用中性铁皮按原色着色），
## 同时乘上摆放色 tint；贴图缺失时退回原来的纯乘色逻辑
func _dress_prop(node: Node3D, name: String, tint: Color) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if not (m is StandardMaterial3D):
				continue
			var sm := m as StandardMaterial3D
			var kind: String = str(PROP_PBR.get(sm.resource_name, ""))
			if name == "container" and sm.resource_name == "Paint":
				kind = "container"
			if name in ["barn", "warehouse"] and sm.resource_name == "Paint":
				kind = "corrugated"
			var t: StandardMaterial3D = sm.duplicate()
			if sm.resource_name in TINTABLE:
				t.albedo_color = sm.albedo_color * tint
			var dressed := kind != "" and PBR.dress(t, kind)
			if dressed or sm.resource_name in TINTABLE and tint != Color.WHITE:
				mi.set_surface_override_material(si, t)


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
func _build_extract(p: Vector3, col: Color = Color(0.25, 1.0, 0.45)) -> Dictionary:
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = EXTRACT_BEACON_H
	pole.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = col * 0.2
	pm.emission_enabled = true
	pm.emission = col
	pm.emission_energy_multiplier = 2.2
	cm.material = pm
	pole.position = p + Vector3(1.6, EXTRACT_BEACON_H * 0.5, 1.2)
	add_child(pole)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position = p + Vector3(1.6, EXTRACT_BEACON_H + 0.3, 1.2)
	add_child(light)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	var rm := StandardMaterial3D.new()
	rm.albedo_color = col * 0.25
	rm.emission_enabled = true
	rm.emission = col
	rm.emission_energy_multiplier = 1.1
	tm.material = rm
	ring.mesh = tm
	ring.position = p + Vector3(0.0, 0.06, 0.0)
	add_child(ring)
	pole.set_meta("no_batch", true)   # 局内按开关改色/显隐：不进静态合批
	ring.set_meta("no_batch", true)
	return {"mats": [pm, rm], "light": light, "col": col, "nodes": [pole, light, ring]}


## 电闸（变电站主控楼内东墙）：配电箱 + 黄黑警示框 + 手柄（拉下后转角，set_lever_pulled）
func _build_lever(p: Vector3) -> void:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.9, 0.6)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.32, 0.35, 0.3)
	bmat.roughness = 0.6
	bmat.metallic = 0.5
	bm.material = bmat
	box.mesh = bm
	box.position = Vector3(p.x + 0.8, 1.35, p.z)
	add_child(box)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.02, 1.0, 0.7)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.9, 0.72, 0.1)
	fmat.emission_enabled = true
	fmat.emission = Color(0.9, 0.72, 0.1)
	fmat.emission_energy_multiplier = 0.4
	fm.material = fmat
	frame.mesh = fm
	frame.position = Vector3(p.x + 0.9, 1.35, p.z)
	add_child(frame)
	_lever_handle = Node3D.new()
	_lever_handle.set_meta("no_batch", true)   # 拉闸时转动：不进静态合批
	_lever_handle.position = Vector3(p.x + 0.68, 1.45, p.z)
	add_child(_lever_handle)
	var hm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 0.36
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.75, 0.12, 0.08)
	cm.material = hmat
	hm.mesh = cm
	hm.position = Vector3(0.0, 0.18, 0.0)
	_lever_handle.add_child(hm)

# ================= 室内靶馆 =================

## 混凝土封闭壳 44×5×30：地坪/吊顶/四面墙（+Z 墙留门洞）/顶部成排灯板/
## 射击位隔断墙 ×3 / 黄黑警示条 / 车道编号 5/6/7 / 尽端挡弹墙；
## 壳体全部注册 obstacles（挡子弹与走人；完全封闭——独立空间只靠传送进出）。
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

	# 地坪 / 吊顶：地坪顶面 = HALL_FLOOR_Y（-6.94，地下埋深）；吊顶保持
	# 馆内净高 HALL_H，吊顶之上覆土 1.94m 到地表
	_hall_box(cx, HALL_FLOOR_Y - 0.15, cz, HALL_HX * 2.0, 0.3, HALL_HZ * 2.0, mat_concrete)
	_hall_box(cx, HALL_FLOOR_Y + HALL_H + 0.15, cz,
			HALL_HX * 2.0, 0.3, HALL_HZ * 2.0, mat_concrete)
	# 吊顶障碍（top/bot 过滤）：地下玩家被挡在馆内、地表玩家/子弹从覆土上走不下来
	_add_obstacle(cx, cz, HALL_HX, HALL_HZ,
			HALL_FLOOR_Y + HALL_H + 0.3, HALL_FLOOR_Y + HALL_H)
	# -Z 尽端挡弹墙（整面，靶道最深 22m + 缓冲；底部落在地坪上）
	_hall_box(cx, HALL_FLOOR_Y + HALL_H * 0.5, cz - HALL_HZ + HALL_TRAP_T * 0.5,
			HALL_HX * 2.0, HALL_H, HALL_TRAP_T, mat_trap)
	_add_obstacle(cx, cz - HALL_HZ + HALL_TRAP_T * 0.5, HALL_HX, HALL_TRAP_T * 0.5,
			HALL_FLOOR_Y + HALL_H, HALL_FLOOR_Y - 0.3)
	# +Z 墙（射击线后方）：中央门洞 x∈[116,124] 接地下连廊（坡道从入口房
	# 下行到此）——2026-10 靶馆入地，门洞恢复；两段墙各 18m
	var seg := (HALL_HX * 2.0 - 8.0) * 0.5
	for side in [-1.0, 1.0]:
		var wx: float = cx + side * (HALL_HX - seg * 0.5)
		_hall_box(wx, HALL_FLOOR_Y + HALL_H * 0.5, cz + HALL_HZ - HALL_WALL_T * 0.5,
				seg, HALL_H, HALL_WALL_T, mat_concrete)
		_add_obstacle(wx, cz + HALL_HZ - HALL_WALL_T * 0.5, seg * 0.5,
				HALL_WALL_T * 0.5, HALL_FLOOR_Y + HALL_H, HALL_FLOOR_Y - 0.3)
	# 西墙 / 东墙
	for side in [-1.0, 1.0]:
		var wz := cz
		_hall_box(cx + side * (HALL_HX - HALL_WALL_T * 0.5), HALL_FLOOR_Y + HALL_H * 0.5,
				wz, HALL_WALL_T, HALL_H, HALL_HZ * 2.0, mat_concrete)
		_add_obstacle(cx + side * (HALL_HX - HALL_WALL_T * 0.5), wz,
				HALL_WALL_T * 0.5, HALL_HZ, HALL_FLOOR_Y + HALL_H, HALL_FLOOR_Y - 0.3)

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
		_add_obstacle(dxz, cz + HALL_FIRE_DZ, 0.1, 3.0, HALL_FLOOR_Y + 1.2,
				HALL_FLOOR_Y - 0.1)

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


## 地下靶馆地表入口（2026-10 用户定案「靶场做在地下」）：入口房 16×14
## （x∈[112,128] z∈[147,161]，北墙门洞朝撤离点大道）+ 房内阶梯坡道开洞
## （x∈[116,124] 南向下行 10m 落差 6.94m）+ 地下连廊（z∈[143,147] 接馆
## +Z 门洞）。地表不空白：房子+绿信标是东南角地标；阶梯=ground_height
## 线性坡（行走贴地自然下行），坡道/连廊都在结构体内部（围墙+顶板包死，
## 不会从地表误坠）。
func _build_entrance() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.51, 0.49)
	mat.roughness = 0.95
	var mat_dark := StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.2, 0.21, 0.22)
	mat_dark.roughness = 0.9
	var wall_h := 3.5
	var top_y := 0.06 + wall_h

	# 入口房地坪：坡道开洞（x 116..124）之外三块板
	_hall_box(114.0, 0.06 - 0.15, 154.0, 4.0, 0.3, 14.0, mat)
	_hall_box(126.0, 0.06 - 0.15, 154.0, 4.0, 0.3, 14.0, mat)
	_hall_box(120.0, 0.06 - 0.15, 159.0, 16.0, 0.3, 4.0, mat)
	# 房顶（含坡道段上方——坡道在房体内部下行，顶板包死防坠）
	_hall_box(120.0, top_y + 0.25, 154.0, 16.0, 0.5, 14.0, mat)
	_add_obstacle(120.0, 154.0, 8.0, 7.0, top_y + 0.5, top_y)
	# 北墙（门洞 x∈[117,123] 朝大道）两段 + 门楣
	for side in [-1.0, 1.0]:
		var nx: float = 120.0 + side * (5.0 + 3.0)
		_hall_box(nx, 0.06 + wall_h * 0.5, 161.0, 5.0, wall_h, 0.5, mat)
		_add_obstacle(nx, 161.0, 2.5, 0.25, top_y, -0.1)
	_hall_box(120.0, top_y - 0.35, 161.0, 6.0, 0.7, 0.5, mat)
	# 南墙（坡道开洞 x∈[116,124] 之上两段，墙脚落在坡道侧墙上沿）
	for side in [-1.0, 1.0]:
		var sx: float = 120.0 + side * 6.0
		_hall_box(sx, 0.06 + wall_h * 0.5, 147.0, 4.0, wall_h, 0.5, mat)
		_add_obstacle(sx, 147.0, 2.0, 0.25, top_y, -0.1)
	_hall_box(120.0, top_y - 0.35, 147.0, 8.0, 0.7, 0.5, mat)
	# 西墙 / 东墙
	for side in [-1.0, 1.0]:
		var wx: float = 120.0 + side * 8.0
		_hall_box(wx, 0.06 + wall_h * 0.5, 154.0, 0.5, wall_h, 14.0, mat)
		_add_obstacle(wx, 154.0, 0.25, 7.0, top_y, -0.1)
	# 阶梯坡道（10 级踏步，每级 1m 深 × 0.7m 高——与 ground_height 坡道
	# 线性（落差 7.0/10m）对齐；踏步体从坡底 -7.1 实心填到各级踏面）
	for k in 10:
		var step_top: float = 0.06 - 0.7 * (float(k) + 1.0)
		var step_h: float = step_top - (-7.1)
		_hall_box(120.0, -7.1 + step_h * 0.5, 156.5 - float(k),
				8.0, step_h, 1.0, mat)
		if k % 2 == 0:
			_hall_box(120.0, step_top + 0.011, 156.5 - float(k),
					8.0, 0.02, 0.9, mat_dark)   # 踏面防滑暗条
	# 坡道侧墙（开洞两沿，从坡底到房内地坪）
	for side in [-1.0, 1.0]:
		var rx: float = 120.0 + side * 4.25
		_hall_box(rx, -3.52, 152.0, 0.5, 7.16, 10.0, mat)
		_add_obstacle(rx, 152.0, 0.25, 5.0, 0.06, -7.1)
	# 地下连廊（坡道底→馆门洞）：两侧墙 + 顶板
	for side in [-1.0, 1.0]:
		var tx: float = 120.0 + side * 4.25
		_hall_box(tx, -4.2, 145.0, 0.5, 5.66, 4.0, mat)
		_add_obstacle(tx, 145.0, 0.25, 2.0, -1.44, -7.1)
	_hall_box(120.0, -1.69, 145.0, 8.0, 0.5, 4.0, mat)
	_add_obstacle(120.0, 145.0, 4.0, 2.0, -1.44, -1.94)
	# 入口房内照明 + 坡道中段照明 + 门头绿信标（东南角地标）
	var hl := OmniLight3D.new()
	hl.light_color = Color(1.0, 0.96, 0.88)
	hl.light_energy = 1.1
	hl.omni_range = 12.0
	hl.position = Vector3(120.0, 2.8, 154.0)
	add_child(hl)
	var rl := OmniLight3D.new()
	rl.light_color = Color(0.95, 0.93, 0.85)
	rl.light_energy = 0.9
	rl.omni_range = 14.0
	rl.position = Vector3(120.0, -1.2, 152.0)
	add_child(rl)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.08, 0.28, 0.13)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(0.25, 0.9, 0.42)
	beacon_mat.emission_energy_multiplier = 1.2
	_hall_box(120.0, top_y - 0.1, 160.7, 4.0, 0.2, 0.2, beacon_mat)


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
