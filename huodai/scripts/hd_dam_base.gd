class_name HDDamBase
extends Node3D
## 坝底工业区陈设（搜打撤「烽火地带」大坝分区·软景层）——
## 厂房×3（甲橄榄 26×9×14 / 乙黄 18×6×12 / 丙泵站 10×5×8：四墙 0.5 厚围合、
## 南墙 4m 门洞 + 红门楣 + 平顶出檐 + 屋面瓦棱 ×8 + 白灰 HVAC 阵列带风扇圆片 +
## 南墙分窗 ×4/段白框 + 甲厂钢结构雨棚 + 屋顶伪装网 ×2 + 乙厂东墙卧式黄罐）/
## 集装箱堆场（红/蓝灰/锈橙/白/灰五色轮转、竖向波纹凸条，7 组「2 底 + 2 顶」
## = 28 箱铺 x[-70,-15] + 单箱×2，长轴=x + 端门片）/
## 工地（围挡板 43 块圈 36×20、南墙留双门，砂堆×2，挖机粗模 7 盒，卷材 3+2+1，
## 轮胎辙印 ×3）/
## 卡车×4（长轴=x 顺泊，车头红货厢黄 + 6 轮 seg10）/ 自卸车×1（货斗翘起）/
## 白罐×3（卧式圆柱，对位目标图东侧白色储罐区）/ 棕榈×18（弯干环箍 +
## 12 片三段折线羽叶 + 冠球）/
## 山体（岩棕三平面噪点：东脚×2 + 西嘴 + 远山 + 坝后山脊 ×4 错位叠置，
## 主峰 (95,-205) 顶 72 挂灌木丛 ×28）/
## 烟柱×3（10 球 LCG 抖动递升至 ~25m，上段渐隐浓黑）/
## 工业区硬地衔接 200×29 一块（压花深暖沙棕）+ 服务街辙印。坝区容器点 13 + 巡逻点 7。
## 职责切分（建造计划 contracts）：坝体硬结构（坝基/台阶/廊道/扶壁垛/涂鸦/
## 闸门排/取水塔…）归 hd_dam.gd（HDDam），本文件只做坝底陈设与软景。
## 入口 build(root)：root 即 HDWorld——视觉 add_child(root)，障碍与点位
## root.obstacles / root.container_spots / root.patrol_spots append
## （hd_loot.gd:141-143 先例）；由 hd_world.build() 末装配，先 HDDam 后本件。
## 碰撞登记 45 条（只给可玩区与墙体，棕榈/烟柱/山体/灌木/挖机臂不注册）：
## 厂房墙 15 + 集装箱堆 7 组+单箱 2 = 9 + 围挡 6 + 砂堆 2 + 挖机 1 + 卷材 1
## + 卡车 4 + 自卸车 1 + 白罐 3 + 乙厂卧罐 1 + 东山脚 2。
## 材质恰 15 枚（tan/green/red/white/leaf/smoke/smoke2/rock/bush/blue/corten/
## track/lot/gray/net），与 hd_dam.gd 9 枚合计=24，零跨文件引用。

const PBR := preload("res://scripts/hd_pbr.gd")
const TRUCK_GLB := "res://assets/pbr/models/truck/truck.glb"
const PALM_GLB := "res://assets/pbr/models/palm/palm.glb"   # Blender 建模写实棕榈（make_palm.py）
const SHRUB_GLB := "res://assets/pbr/models/shrub_04/shrub_04_lod.glb"   # 实拍灌木（减面版）   # 美术写实化：CC0 实拍 PBR 贴图（缺失自动回退纯色）
const WALL_T := 0.5             # 厂房墙厚
const HOARD_T := 0.12           # 围挡板厚
const HOARD_H := 2.2            # 围挡板高
const TRUNK_H := 6.0            # 棕榈干基准高（逐株 y 向缩放出 5.2~7.0m）
const SEG_LEN := 1.1            # 棕榈羽叶折线段长（3 段拼 3.3m 一叶）
const CBOX := Vector3(6.06, 2.59, 2.44)   # 集装箱 长×高×宽（20ft，长轴=x）
const CSTACK_DZ := 3.2          # 堆场底箱 z 向错位半距（2 底 z 向 ±3.2，计划口径）
const DAM_ZONE := "dam"

## 集装箱混色轮转表（红/蓝灰/锈橙/白/灰，对位目标图箱场混色）
const BOX_TINTS := ["red", "blue", "corten", "white", "gray"]

## 厂房×3（建造计划 P）：footprint 外沿 / 南门洞 x 区间 / 屋顶机组阵列点位
const FACTORIES := [
	{   # 甲 · 绿厂房（装配车间）@ (28,-95)：足迹 x[15,41]×z[-102,-88]
		"mat": "green", "x0": 15.0, "x1": 41.0, "z0": -102.0, "z1": -88.0,
		"h": 9.0, "door0": 26.0, "door1": 30.0,
		"hvac": [Vector2(22, -98), Vector2(28, -98), Vector2(34, -98),
			Vector2(22, -92), Vector2(28, -92), Vector2(34, -92)],
		"hvac_sz": Vector3(1.8, 1.0, 1.4),
	},
	{   # 乙 · 黄厂房（机修间）@ (62,-94)：足迹 x[53,71]×z[-100,-88]，门对卡车2 装货位
		"mat": "tan", "x0": 53.0, "x1": 71.0, "z0": -100.0, "z1": -88.0,
		"h": 6.0, "door0": 58.0, "door1": 62.0,
		"hvac": [Vector2(56, -94), Vector2(60, -94), Vector2(64, -94), Vector2(68, -94)],
		"hvac_sz": Vector3(1.6, 0.9, 1.2),
	},
	{   # 丙 · 黄泵站 @ (-6,-96)：足迹 x[-11,-1]×z[-100,-92]，南门 x[-7.5,-4.5]（计划口径）
		"mat": "tan", "x0": -11.0, "x1": -1.0, "z0": -100.0, "z1": -92.0,
		"h": 5.0, "door0": -7.5, "door1": -4.5,
		"hvac": [Vector2(-8.5, -96), Vector2(-3.5, -96)],
		"hvac_sz": Vector3(1.4, 0.8, 1.1),
	},
]

## 集装箱堆场（第 4 轮扩容：3 堆→7 组铺满 x[-70,-15]，每组 2 底 z±3.2 +
## 2 顶压双列 +0.3 偏移 = 30 箱，对位目标图左中 20+ 箱大堆场）；组位避开
## 容器点⑤(-82,-98.5)/(-40.5,-99)/(-32,-87) 与巡逻点 (-48,-101.5)（裕量 ≥0.6m
## 推挤半径口径，python 复核）+ 2 单箱，长轴全=x
const YARD_STACKS := [
	Vector2(-62.0, -96.5), Vector2(-54.0, -90.0), Vector2(-46.0, -96.5),
	Vector2(-38.0, -90.0), Vector2(-30.0, -96.5), Vector2(-22.0, -90.0),
	Vector2(-14.0, -96.5),
]
const YARD_SINGLES := [Vector2(30.0, -82.5), Vector2(70.0, -82.5)]

## 砂堆×2（建造计划 R）：砂堆1 缩 r2.0——原 r5 压扁穹面在 loot⑤(-82,-98.5) 处
## 高 3.12m 会埋掉评审勘误后的修正点位（本 session python3 复算），r2.0 后
## ⑤ 距穹缘 0.5m、搜箱站位裕量 0.6m ≥ 推挤半径 0.4
const SAND_PILES := [
	{"p": Vector2(-82.0, -96.0), "r": 2.0, "h": 1.5},
	{"p": Vector2(-63.0, -102.0), "r": 5.0, "h": 3.6},
]

## 卷材×6（3+2+1 立式钢卷金字塔，轴向沿 x）
const COILS := [
	Vector3(-89.7, 0.8, -100.0), Vector3(-88.0, 0.8, -100.0), Vector3(-86.3, 0.8, -100.0),
	Vector3(-88.85, 2.4, -100.0), Vector3(-87.15, 2.4, -100.0), Vector3(-88.0, 4.0, -100.0),
]

## 卡车×4（建造计划 S + 白天密度补齐）：长轴=x 顺泊；hz 按计划口径 1.2 / 1.5，
## 新增两台泊集装箱场东端 (-38,-83) 与白罐区西侧 (86,-84)（对位目标图车列）
const TRUCKS := [Vector2(-52.0, -90.0), Vector2(60.0, -81.0),
	Vector2(-38.0, -83.0), Vector2(86.0, -84.0)]
const TRUCK_HZ := [1.2, 1.5, 1.2, 1.2]
const WHEEL_DX := [-2.4, -1.2, 2.9]   # 轮位（相对车心 x）：后双轴 + 前轴

## 白罐×3（白天密度：目标图右下白色卧式储罐群）——卧轴沿 x，r1.5 长 7.5，
## 靠东山脚穹丘前 Open 场地（102,-101/-97.5/-94），避第二撤离环（93,-94 r3）
const TANKS := [Vector2(102.0, -101.0), Vector2(102.0, -97.5), Vector2(102.0, -94.0)]
const TANK_R := 1.5
const TANK_LEN := 7.5

## 自卸车×1（白天密度：目标图工地出口土方车）——车尾货斗翘起卸料姿态，
## 泊工地南墙外 (-88,-83)，让开双门（x[-84,-80]/[-68,-64]）与围挡段
const DUMPER := Vector2(-88.0, -83.0)

## 棕榈×18（建造计划 T + 白天密度补齐）：街带 z=-86 十三株 + 撤离广场三株
## + 硬地南缘两株（对位目标图厂房间散植棕榈）
const PALM_XZ := [
	Vector2(-110.0, -86.0), Vector2(-96.0, -86.0), Vector2(-82.0, -86.0),
	Vector2(-70.0, -86.0), Vector2(-54.0, -86.0), Vector2(-12.0, -86.0),
	Vector2(8.0, -86.0), Vector2(22.0, -86.0), Vector2(36.0, -86.0),
	Vector2(48.0, -86.0), Vector2(64.0, -86.0), Vector2(80.0, -86.0),
	Vector2(-120.0, -86.0),
	Vector2(90.0, -91.0), Vector2(96.0, -91.0), Vector2(93.0, -89.5),
	Vector2(44.0, -80.0), Vector2(86.0, -80.0),
]

## 山体（建造计划 U + 第 4 轮山脊化）：单椭球「穹顶」读作建筑——拆 4 球错位
## 叠置山脊并整体东移（x+40~130，落 ref 机位画面右 70-90% 方位），坝正后方
## (x≈35) 压低到顶 40<坝顶+10；全体岩棕 rock 材质（三平面高频噪点破光滑）
const HILLS := [
	{"p": Vector3(126.0, 0.0, -102.0), "s": Vector3(31.2, 18.2, 23.4)},   # 东脚山1
	{"p": Vector3(108.0, 0.0, -116.0), "s": Vector3(21.6, 18.2, 16.2)},   # 东脚山2
	{"p": Vector3(-146.0, 0.0, -116.0), "s": Vector3(16.8, 9.8, 12.6)},   # 西嘴
	{"p": Vector3(-110.0, 0.0, -190.0), "s": Vector3(40.0, 30.0, 32.0)},  # 远山·坝后西
	{"p": Vector3(35.0, 0.0, -205.0), "s": Vector3(45.0, 40.0, 38.0)},    # 脊1·坝后低位
	{"p": Vector3(60.0, 0.0, -195.0), "s": Vector3(55.0, 58.0, 45.0)},    # 脊2
	{"p": Vector3(95.0, 0.0, -205.0), "s": Vector3(60.0, 72.0, 48.0)},    # 脊3·主峰
	{"p": Vector3(130.0, 0.0, -190.0), "s": Vector3(50.0, 52.0, 40.0)},   # 脊4
]

## 主峰（脊3）灌木丛 ×28（第 3 轮：目标岩山带深绿灌木点）——LCG 伪随机固定
## 序列撒椭球上半球面（嵌入 0.3），深橄榄小半球 r0.6~1.4
const SHRUB_HOST := {"p": Vector3(95.0, 0.0, -205.0), "s": Vector3(54.0, 66.0, 42.0)}
const SHRUB_N := 28
const SHRUB_SEED := 20261012

## 烟柱×3（第 4 轮破规则球串：10 球递升顶 ~25m，每球 LCG 随机 xz 偏移 ±0.6、
## 上段 4 球换 alpha0.25 渐隐材质）——对位目标图右侧厂后显眼黑烟；
## 首柱挂坝前廊道口 (28,-107)（ref/base 机位可见），第三柱按评审位 (100,-108)
const SMOKES := [Vector3(28.0, 0.0, -107.0), Vector3(-5.0, 54.0, -143.0),
	Vector3(100.0, 0.0, -108.0)]
const PUFF_N := 10
const PUFF_R0 := 1.3
const PUFF_DR := 0.3
const PUFF_H0 := 1.8
const PUFF_DH := 2.6
const PUFF_DX := 1.2
const PUFF_FADE := 6   # ≥ 此序号的球换渐隐材质
const PUFF_SEED := 20261014

## 甲厂北侧钢结构雨棚（第 3 轮：白柱×8 + 顶板，对位目标图厂房右翼）
const CANOPY := {"x0": 15.5, "x1": 40.5, "z": -104.5, "h": 4.5, "n": 8}

## 乙厂东墙卧式黄罐（第 3 轮：r2.5 l7 轴沿 x + 两道红箍，碰撞 1 条）
const EAST_TANK := Vector2(74.5, -94.0)
const EAST_TANK_R := 2.5
const EAST_TANK_LEN := 7.0

## 工地轮胎辙印 ×3（第 4 轮：加宽 0.6 + 第三道，成排车辙阴影）
const TRACKS := [-93.0, -96.0, -99.0]
const TRACK_LEN := 30.0

## 坝区可搜容器 13（建造计划 gameplay：全部 zone="dam"，∈[10,14]）
const DAM_CONTAINERS := [
	Vector2(-30.0, -115.0), Vector2(10.0, -115.0), Vector2(50.0, -115.0),
	Vector2(-70.0, -92.5), Vector2(-82.0, -98.5), Vector2(-40.5, -99.0),
	Vector2(-32.0, -87.0), Vector2(-6.0, -95.0), Vector2(28.0, -98.0),
	Vector2(35.0, -91.0), Vector2(62.0, -97.0), Vector2(74.0, -88.5), Vector2(94.0, -97.0),
]

## 坝区巡逻点 7（建造计划 gameplay：全部 zone="dam"，∈[6,8]；坐标均为评审修正后值）
const DAM_PATROLS := [
	Vector2(-76.0, -86.0), Vector2(-48.0, -101.5), Vector2(-14.0, -99.0),
	Vector2(28.0, -86.0), Vector2(62.0, -77.0), Vector2(100.0, -85.0), Vector2(-30.0, -104.0),
]

var _built := false
var _mats := {}                  # 材质表（恰 15 枚，见 _make_mats）
var _box_tint_i := 0             # 集装箱混色轮转游标（跨堆连续=自然混色）
var _mesh_cache := {}            # 材质 -> {尺寸键 -> BoxMesh}（同尺寸同材质共用一张网格）
var _hill_mesh: SphereMesh       # 单位球：砂堆专用（tan；山体走 _rock_mesh 岩棕）
var _smoke_mesh: SphereMesh      # 单位球：烟团（smoke 半透明）
var _coil_mesh: CylinderMesh
var _tank_mesh: CylinderMesh
var _wheel_mesh: CylinderMesh
var _trunk_mesh: CylinderMesh
var _rock_mesh: SphereMesh      # 岩棕椭球山（rock）
var _bush_mesh: SphereMesh      # 深橄榄小半球灌木（bush）
var _crown_mesh: SphereMesh     # 棕榈冠球（bush 共用材质，独立网格 r0.45）
var _fan_mesh: CylinderMesh     # HVAC 顶风扇圆片（bush 共用材质）
var _ring_mesh: CylinderMesh    # 棕榈干环箍（corten 共用材质 r0.26 h0.15）
var _frond_seg_mesh: BoxMesh    # 棕榈羽叶折线段（leaf，3 段拼一叶）


func build(root: Node3D) -> void:
	if _built or root == null:
		return
	_built = true
	var w = root   # HDWorld（鸭子类型：obstacles/点位容器动态访问，hd_loot.gd 同款）
	_make_mats()
	_dress_pbr()
	_make_meshes()
	_build_hardstand(w)
	_build_factories(w)
	_build_canopy(w)
	_build_east_tank(w)
	_build_container_yard(w)
	_build_site(w)
	_build_trucks(w)
	_build_dumper(w)
	_build_tanks(w)
	_build_palms(w)
	_build_hills(w)
	_build_smoke(w)
	_register_spots(w)


# ================= 材质与共用网格 =================

## 材质恰 15 枚（BASE 侧份额）：tan 戈壁黄 / green 厂房甲橄榄土黄 / red 氧化红
## （门楣·车头·驾驶室·箍带）/ white 白罐·HVAC·雨棚柱·箱 / leaf 棕榈叶 /
## smoke 浓黑烟下段 / smoke2 烟上段渐隐 / rock 岩棕三平面噪点山体 /
## bush 深橄榄灌木·风扇片 / blue 集装箱蓝灰·窗带 / corten 锈橙·干环箍 /
## track 深棕辙印 / gray 灰箱 / net 伪装网半透明 / lot 硬地压花（评审 #11 压暗）
## 美术写实化：坝底工业区换实拍材质——厂房波纹铁皮、白罐/红门架带锈旧漆、
## 山体岩石、场地砾沙；植物/烟/伪装网保留原材质
var _grime_mats: Array = []   # 挂风化污迹贴花的墙体材质


func _dress_pbr() -> void:
	var plan := {
		"tan": ["paint_rust", 2.0],
		"hill": ["sand", 3.0],
		"green": ["corrugated", 2.5],
		"red": ["paint_rust", 2.0],
		"white": ["paint_rust", 2.5],
		"rock": ["rock", 4.0],
		"blue": ["container", 2.4],
		"corten": ["paint_rust", 1.5],
		"track": ["sand", 2.5],
		"gray": ["concrete", 4.0],
		"lot": ["sand", 3.0],
	}
	for key in plan:
		if _mats.has(key):
			PBR.dress(_mats[key], str(plan[key][0]), float(plan[key][1]))
	for key in ["green", "gray", "tan"]:
		if _mats.has(key):
			_grime_mats.append(_mats[key])


func _make_mats() -> void:
	_mats["tan"] = _std_mat(Color(0.72, 0.62, 0.4), 1.0, 0.0)
	# 写实化拆材质：tan 原本山体/车厢/轮胎/树干/围挡共用一张——换实拍贴图后
	# 各要各的：山体砾沙、车厢围挡旧漆铁皮、轮胎黑橡胶、树干保持纯色
	_mats["hill"] = _std_mat(Color(0.72, 0.62, 0.4), 1.0, 0.0)
	_mats["trunk"] = _std_mat(Color(0.72, 0.62, 0.4), 1.0, 0.0)
	_mats["tyre"] = _std_mat(Color(0.07, 0.07, 0.075), 0.92, 0.0)
	_mats["green"] = _std_mat(Color(0.45, 0.42, 0.33), 0.85, 0.0)
	_mats["red"] = _std_mat(Color(0.55, 0.18, 0.14), 0.65, 0.2)
	_mats["white"] = _std_mat(Color(0.85, 0.84, 0.8), 0.8, 0.0)
	_mats["leaf"] = _std_mat(Color(0.2, 0.32, 0.14), 1.0, 0.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.15, 0.14, 0.13, 0.5)   # 浓黑烟下段
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 1.0
	_mats["smoke"] = sm
	var sm2 := StandardMaterial3D.new()
	sm2.albedo_color = Color(0.15, 0.14, 0.13, 0.25)   # 烟上段渐隐（评审 #18）
	sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm2.roughness = 1.0
	_mats["smoke2"] = sm2
	# 岩棕三平面高频噪点（评审 #15：破单位球光滑塑料感）
	var rn := FastNoiseLite.new()
	rn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rn.frequency = 0.15
	rn.fractal_octaves = 4
	rn.seed = 20261015
	var rtex := NoiseTexture2D.new()
	rtex.width = 512
	rtex.height = 512
	rtex.seamless = true
	rtex.noise = rn
	var rramp := Gradient.new()
	rramp.set_color(0, Color(0.45, 0.35, 0.26))
	rramp.set_color(1, Color(1.0, 1.0, 1.0))
	rtex.color_ramp = rramp
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.6, 0.46, 0.32)
	rock.albedo_texture = rtex
	rock.uv1_triplanar = true
	rock.uv1_scale = Vector3(0.4, 0.4, 0.4)
	rock.roughness = 1.0
	_mats["rock"] = rock
	_mats["bush"] = _std_mat(Color(0.25, 0.3, 0.18), 1.0, 0.0)
	_mats["blue"] = _std_mat(Color(0.25, 0.34, 0.42), 0.85, 0.0)
	_mats["corten"] = _std_mat(Color(0.5, 0.28, 0.16), 0.9, 0.0)
	_mats["track"] = _std_mat(Color(0.4, 0.34, 0.24), 1.0, 0.0)
	_mats["gray"] = _std_mat(Color(0.6, 0.6, 0.58), 0.85, 0.0)
	var net := StandardMaterial3D.new()
	net.albedo_color = Color(0.3, 0.36, 0.2, 0.55)   # 伪装网半透明橄榄（评审 #17）
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.roughness = 1.0
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["net"] = net
	# 硬地压花（评审 #11 压暗：亮米白→深一档暖沙棕）
	var gn := FastNoiseLite.new()
	gn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gn.frequency = 0.02
	gn.fractal_octaves = 4
	gn.seed = 20261012
	var gtex := NoiseTexture2D.new()
	gtex.width = 512
	gtex.height = 512
	gtex.seamless = true
	gtex.noise = gn
	var gramp := Gradient.new()
	gramp.set_color(0, Color(0.68, 0.62, 0.5))
	gramp.set_color(1, Color(1.0, 1.0, 1.0))
	gtex.color_ramp = gramp
	var lot := StandardMaterial3D.new()
	lot.albedo_color = Color(0.56, 0.47, 0.3)
	lot.albedo_texture = gtex
	lot.uv1_scale = Vector3(48.0, 7.0, 1.0)
	lot.roughness = 1.0
	_mats["lot"] = lot


func _std_mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## 复用件网格一次建好：山/烟共用单位球（材质不同各一张），细杆/轮/卷/叶/干各一张；
## 盒件走 _box_mesh 尺寸缓存（围挡三种定长、集装箱体与门片、厂房墙…全量复用）
func _make_meshes() -> void:
	_hill_mesh = SphereMesh.new()
	_hill_mesh.radius = 1.0
	_hill_mesh.height = 2.0
	_hill_mesh.radial_segments = 24
	_hill_mesh.rings = 12
	_hill_mesh.material = _mats["hill"]
	_smoke_mesh = SphereMesh.new()
	_smoke_mesh.radius = 1.0
	_smoke_mesh.height = 2.0
	_smoke_mesh.radial_segments = 16
	_smoke_mesh.rings = 8
	_smoke_mesh.material = _mats["smoke"]
	_coil_mesh = CylinderMesh.new()
	_coil_mesh.top_radius = 0.8
	_coil_mesh.bottom_radius = 0.8
	_coil_mesh.height = 1.1
	_coil_mesh.radial_segments = 24
	_coil_mesh.rings = 1
	_coil_mesh.material = _mats["tan"]
	_tank_mesh = CylinderMesh.new()
	_tank_mesh.top_radius = TANK_R
	_tank_mesh.bottom_radius = TANK_R
	_tank_mesh.height = TANK_LEN
	_tank_mesh.radial_segments = 16
	_tank_mesh.rings = 1
	_tank_mesh.material = _mats["white"]
	_rock_mesh = SphereMesh.new()
	_rock_mesh.radius = 1.0
	_rock_mesh.height = 2.0
	_rock_mesh.radial_segments = 24
	_rock_mesh.rings = 12
	_rock_mesh.material = _mats["rock"]
	_bush_mesh = SphereMesh.new()
	_bush_mesh.radius = 1.0
	_bush_mesh.height = 2.0
	_bush_mesh.radial_segments = 12
	_bush_mesh.rings = 6
	_bush_mesh.material = _mats["bush"]
	_crown_mesh = SphereMesh.new()
	_crown_mesh.radius = 0.45
	_crown_mesh.height = 0.9
	_crown_mesh.radial_segments = 12
	_crown_mesh.rings = 6
	_crown_mesh.material = _mats["bush"]
	_fan_mesh = CylinderMesh.new()
	_fan_mesh.top_radius = 0.5
	_fan_mesh.bottom_radius = 0.5
	_fan_mesh.height = 0.05
	_fan_mesh.radial_segments = 12
	_fan_mesh.rings = 1
	_fan_mesh.material = _mats["bush"]
	_ring_mesh = CylinderMesh.new()
	_ring_mesh.top_radius = 0.26
	_ring_mesh.bottom_radius = 0.26
	_ring_mesh.height = 0.15
	_ring_mesh.radial_segments = 8
	_ring_mesh.rings = 1
	_ring_mesh.material = _mats["corten"]
	_wheel_mesh = CylinderMesh.new()
	_wheel_mesh.top_radius = 0.45
	_wheel_mesh.bottom_radius = 0.45
	_wheel_mesh.height = 0.3
	_wheel_mesh.radial_segments = 10
	_wheel_mesh.rings = 1
	_wheel_mesh.material = _mats["tyre"]
	_trunk_mesh = CylinderMesh.new()
	_trunk_mesh.top_radius = 0.13
	_trunk_mesh.bottom_radius = 0.22
	_trunk_mesh.height = TRUNK_H
	_trunk_mesh.radial_segments = 8
	_trunk_mesh.rings = 1
	_trunk_mesh.material = _mats["trunk"]
	_frond_seg_mesh = BoxMesh.new()
	_frond_seg_mesh.size = Vector3(SEG_LEN, 0.05, 0.45)
	_frond_seg_mesh.material = _mats["leaf"]


func _box_mesh(w: float, h: float, d: float, mat: StandardMaterial3D) -> BoxMesh:
	if not _mesh_cache.has(mat):
		_mesh_cache[mat] = {}
	var per: Dictionary = _mesh_cache[mat]
	var key := "%s_%s_%s" % [w, h, d]
	if not per.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, d)
		bm.material = mat
		per[key] = bm
	return per[key]


# ================= 装配 =================

## 工业区硬地衔接：整片压实场地 x[-95,105]×z[-107,-78]，顶面 y0.03——
## 与大地 y0、服务街道条顶 y0.05（hd_dam.gd W 件）全错层无共面；
## 底面 -0.07 埋地（hd_world.gd:524 靶馆地坪同款手法），不注册碰撞（纯地面）。
## 第 3 轮换 lot 压花材质（棕黄噪点破单色）+ 工地内深色轮胎辙印 ×2
func _build_hardstand(w) -> void:
	_place_box(w, 5.0, -0.02, -92.5, 200.0, 0.1, 29.0, _mats["lot"])
	for tz in TRACKS:
		_place_box(w, -77.0, 0.045, tz, TRACK_LEN, 0.02, 0.6, _mats["track"])


## 厂房×3：四墙围合（南墙 4m 门洞）+ 红门楣压净高 + 平顶出檐 + 屋顶机组阵列；
## 碰撞只登记四墙 5 段/栋（门洞让空），门楣悬空 y≥h-1.2 不挡走人不注册
func _build_factories(w) -> void:
	for f in FACTORIES:
		var mat: StandardMaterial3D = _mats[f["mat"]]
		var x0: float = f["x0"]
		var x1: float = f["x1"]
		var z0: float = f["z0"]
		var z1: float = f["z1"]
		var fh: float = f["h"]
		var d0: float = f["door0"]
		var d1: float = f["door1"]
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		var fx := x1 - x0
		var fz := z1 - z0
		# 北墙 / 南墙两段（门洞让空）/ 西墙 / 东墙（侧墙嵌在纵横墙内口之间）
		_place_box(w, cx, fh * 0.5, z0 + WALL_T * 0.5, fx, fh, WALL_T, mat)
		_place_box(w, (x0 + d0) * 0.5, fh * 0.5, z1 - WALL_T * 0.5, d0 - x0, fh, WALL_T, mat)
		_place_box(w, (d1 + x1) * 0.5, fh * 0.5, z1 - WALL_T * 0.5, x1 - d1, fh, WALL_T, mat)
		_place_box(w, x0 + WALL_T * 0.5, fh * 0.5, cz, WALL_T, fh, fz - WALL_T * 2.0, mat)
		_place_box(w, x1 - WALL_T * 0.5, fh * 0.5, cz, WALL_T, fh, fz - WALL_T * 2.0, mat)
		# 平顶（四周出檐 0.3）+ 红门楣（门洞净高压到 h-1.2）
		_place_box(w, cx, fh + 0.2, cz, fx + 0.6, 0.4, fz + 0.6, mat)
		_place_box(w, (d0 + d1) * 0.5, fh - 0.6, z1 - WALL_T * 0.5, d1 - d0, 1.2, WALL_T,
				_mats["red"])
		# 南墙分窗 ×4/段（第 4 轮：白框底板 + 蓝灰窗扇，替通条）
		for seg_x in [[x0 + 0.3, d0 - 0.3], [d1 + 0.3, x1 - 0.3]]:
			var wlen: float = seg_x[1] - seg_x[0]
			if wlen <= 1.5:
				continue
			var seg_c: float = (seg_x[0] + seg_x[1]) * 0.5
			_place_box(w, seg_c, 2.2, z1 + 0.32, wlen, 1.5, 0.1, _mats["white"])
			for k in 4:
				var wx: float = seg_x[0] + wlen * (float(k) + 0.5) / 4.0
				_place_box(w, wx, 2.2, z1 + 0.36, wlen * 0.2, 1.2, 0.1,
						_mats["blue"])
		# 屋面竖向瓦棱 ×8（第 4 轮：浅色彩钢棱条）
		for k in 8:
			var rx: float = x0 + fx * (float(k) + 0.5) / 8.0
			_place_box(w, rx, fh + 0.47, cz, 0.35, 0.14, fz + 0.4, _mats["white"])
		# 屋顶空调机组阵列（第 3 轮红→白灰 + 顶面深色风扇圆片，坐屋面 y=fh+0.4）
		var hsz: Vector3 = f["hvac_sz"]
		for hp in f["hvac"]:
			var hv: Vector2 = hp
			_place_box(w, hv.x, fh + 0.4 + hsz.y * 0.5, hv.y, hsz.x, hsz.y, hsz.z,
					_mats["white"])
			var fan := MeshInstance3D.new()
			fan.mesh = _fan_mesh
			fan.position = Vector3(hv.x, fh + 0.4 + hsz.y + 0.03, hv.y)
			w.add_child(fan)
		# 甲厂屋顶伪装网 ×2 + 竖撑杆（评审 #17：半透明橄榄网面）
		if x0 == 15.0:
			for nz in [-99.5, -94.5]:
				_place_box(w, 24.0, 10.1, nz, 20.0, 0.06, 8.0, _mats["net"],
						Vector3(0.0, 0.0, 0.06))
			_place_box(w, 24.0, 10.15, -97.0, 1.2, 1.4, 20.0, _mats["white"])
		# 碰撞：四墙 5 段（建造计划⑦，三栋共 15 段）
		_obstacle(w, cx, z0 + WALL_T * 0.5, fx * 0.5, WALL_T * 0.5, fh)
		_obstacle(w, (x0 + d0) * 0.5, z1 - WALL_T * 0.5, (d0 - x0) * 0.5, WALL_T * 0.5, fh)
		_obstacle(w, (d1 + x1) * 0.5, z1 - WALL_T * 0.5, (x1 - d1) * 0.5, WALL_T * 0.5, fh)
		_obstacle(w, x0 + WALL_T * 0.5, cz, WALL_T * 0.5, (fz - WALL_T * 2.0) * 0.5, fh)
		_obstacle(w, x1 - WALL_T * 0.5, cz, WALL_T * 0.5, (fz - WALL_T * 2.0) * 0.5, fh)


## 甲厂北侧钢结构雨棚（第 3 轮：白柱×8 单排 + 挑檐顶板，对位目标图厂房右翼；
## 软景不注册碰撞）
func _build_canopy(w) -> void:
	var x0: float = CANOPY["x0"]
	var x1: float = CANOPY["x1"]
	var cz: float = CANOPY["z"]
	var ch: float = CANOPY["h"]
	var n: int = CANOPY["n"]
	for k in n:
		var px: float = x0 + (x1 - x0) * float(k) / float(n - 1)
		_place_box(w, px, ch * 0.5, cz, 0.3, ch, 0.3, _mats["white"])
	_place_box(w, (x0 + x1) * 0.5, ch + 0.15, cz + 0.9,
			x1 - x0 + 1.0, 0.3, 3.2, _mats["white"])


## 乙厂东墙卧式黄罐（第 3 轮：r2.5 l7 轴沿 x + 两道红箍带；碰撞 1 条；
## material_override 盖白罐网格的 white 材质为 tan 黄）
func _build_east_tank(w) -> void:
	var p: Vector2 = EAST_TANK
	var mi := MeshInstance3D.new()
	mi.mesh = _tank_mesh
	mi.material_override = _mats["tan"]
	mi.rotation.z = PI / 2.0
	mi.scale = Vector3(EAST_TANK_R / TANK_R, EAST_TANK_LEN / TANK_LEN,
			EAST_TANK_R / TANK_R)
	mi.position = Vector3(p.x, EAST_TANK_R, p.y)
	w.add_child(mi)
	for hx in [-2.0, 2.0]:
		_place_box(w, p.x + hx, EAST_TANK_R, p.y, 0.5, 0.8,
				EAST_TANK_R * 2.0 + 0.2, _mats["red"])
	_obstacle(w, p.x, p.y, EAST_TANK_LEN * 0.5, EAST_TANK_R, EAST_TANK_R * 2.0)


## 集装箱堆场：箱体 + 两端门片（外探 6cm 消共面）+ 两长侧竖向波纹凸条 ×5/侧
## （红/蓝灰/锈橙/白/灰轮转混色）；7 组=每 2 底 + 2 顶（双列各压 1 顶 +0.3 偏移）
## + 2 单箱 = 30 箱；碰撞 7 组 + 2 单箱 = 9 条
func _build_container_yard(w) -> void:
	for s in YARD_STACKS:
		var sv: Vector2 = s
		_container(w, sv.x, 0.0, sv.y - CSTACK_DZ)
		_container(w, sv.x, 0.0, sv.y + CSTACK_DZ)
		_container(w, sv.x, CBOX.y, sv.y - CSTACK_DZ + 0.3)
		_container(w, sv.x, CBOX.y, sv.y + CSTACK_DZ - 0.3)
		_obstacle(w, sv.x, sv.y, CBOX.x * 0.5, CSTACK_DZ + CBOX.z * 0.5, CBOX.y * 2.0)
	for p in YARD_SINGLES:
		var pv: Vector2 = p
		_container(w, pv.x, 0.0, pv.y)
		_obstacle(w, pv.x, pv.y, CBOX.x * 0.5, CBOX.z * 0.5, CBOX.y)


## 单箱装配：tint 空串时按 BOX_TINTS 轮转取色（跨堆连续游标=自然混色）
func _container(w, x: float, y0: float, z: float, tint := "") -> void:
	var key: String = tint if tint != "" else BOX_TINTS[_box_tint_i % BOX_TINTS.size()]
	_box_tint_i += 1
	var bm: StandardMaterial3D = _mats[key]
	var cy := y0 + CBOX.y * 0.5
	_place_box(w, x, cy, z, CBOX.x, CBOX.y, CBOX.z, bm)
	for side in [-1.0, 1.0]:
		_place_box(w, x + side * (CBOX.x * 0.5 + 0.02), cy, z,
				0.08, CBOX.y - 0.2, CBOX.z - 0.1, bm)
		for k in 5:
			var rx: float = x - 2.2 + 1.1 * float(k)
			_place_box(w, rx, y0 + 1.3, z + side * (CBOX.z * 0.5 + 0.03),
					0.1, 2.4, 0.06, bm)


## 工地：围挡 43 块圈 36×20（北 15×2.4 / 南 4×2.5+5×2.4+3×2.0，双门
## x[-84,-80]/[-68,-64] 让空 / 东西 8×2.5）+ 砂堆×2 + 挖机 7 盒 + 卷材 3+2+1；
## 碰撞 6+2+1+1（建造计划⑨）
func _build_site(w) -> void:
	_hoard_run_x(w, -94.0, -108.0, 15, 2.4)
	_hoard_run_x(w, -94.0, -88.0, 4, 2.5)
	_hoard_run_x(w, -80.0, -88.0, 5, 2.4)
	_hoard_run_x(w, -64.0, -88.0, 3, 2.0)
	_hoard_run_z(w, -94.0, -108.0, 8, 2.5)
	_hoard_run_z(w, -58.0, -108.0, 8, 2.5)
	_obstacle(w, -76.0, -108.0, 18.0, 0.1, HOARD_H)
	_obstacle(w, -89.0, -88.0, 5.0, 0.1, HOARD_H)
	_obstacle(w, -74.0, -88.0, 6.0, 0.1, HOARD_H)
	_obstacle(w, -61.0, -88.0, 3.0, 0.1, HOARD_H)
	_obstacle(w, -94.0, -98.0, 0.1, 10.0, HOARD_H)
	_obstacle(w, -58.0, -98.0, 0.1, 10.0, HOARD_H)
	_piles(w)
	_excavator(w)
	_coils(w)


func _hoard_run_x(w, x0: float, z: float, n: int, pw: float) -> void:
	for i in n:
		var px: float = x0 + pw * 0.5 + pw * float(i)
		_place_box(w, px, HOARD_H * 0.5, z, pw, HOARD_H, HOARD_T, _mats["tan"])


func _hoard_run_z(w, x: float, z0: float, n: int, pw: float) -> void:
	for i in n:
		var pz: float = z0 + pw * 0.5 + pw * float(i)
		_place_box(w, x, HOARD_H * 0.5, pz, HOARD_T, HOARD_H, pw, _mats["tan"])


func _piles(w) -> void:
	for p in SAND_PILES:
		var pv: Vector2 = p["p"]
		var r: float = p["r"]
		var ph: float = p["h"]
		var mi := MeshInstance3D.new()
		mi.mesh = _hill_mesh                      # 单位球复用：半轴 (r, h/2, r) 压扁穹丘
		mi.position = Vector3(pv.x, 0.0, pv.y)
		mi.scale = Vector3(r, ph * 0.5, r)
		w.add_child(mi)
		_obstacle(w, pv.x, pv.y, r, r, ph)


## 挖机粗模 7 盒：双履带 + 车体 + 红驾驶室 + 动臂/斗杆/铲斗（rot.z 折臂）；
## 碰撞只围底盘 1 条（建造计划⑨），前伸臂件悬空不注册
func _excavator(w) -> void:
	_place_box(w, -72.2, 0.5, -97.15, 3.6, 1.0, 1.0, _mats["tan"])
	_place_box(w, -72.2, 0.5, -94.85, 3.6, 1.0, 1.0, _mats["tan"])
	_place_box(w, -72.8, 1.55, -96.0, 2.4, 1.1, 1.9, _mats["tan"])
	_place_box(w, -71.6, 1.8, -96.0, 1.5, 1.6, 1.4, _mats["red"])
	_place_box(w, -70.0, 2.5, -96.0, 3.2, 0.45, 0.5, _mats["tan"], Vector3(0.0, 0.0, 0.55))
	_place_box(w, -67.6, 2.85, -96.0, 1.9, 0.35, 0.4, _mats["tan"], Vector3(0.0, 0.0, -0.9))
	_place_box(w, -66.4, 1.75, -96.0, 0.95, 0.75, 0.95, _mats["tan"], Vector3(0.0, 0.0, -0.3))
	_obstacle(w, -72.2, -96.0, 3.6, 1.9, 2.6)


func _coils(w) -> void:
	for c in COILS:
		var cv: Vector3 = c
		var mi := MeshInstance3D.new()
		mi.mesh = _coil_mesh
		mi.position = cv
		mi.rotation.z = PI / 2.0                  # 轴向沿 x 的立式钢卷
		w.add_child(mi)
	_obstacle(w, -88.0, -100.0, 2.5, 0.85, 4.8)


## 卡车×4：货厢（tan）+ 平头车头（红）+ 6 轮（seg10 共网，rot.x=90° 轴向沿 z）；
## 碰撞按计划定死 AABB：卡车1 x[-56,-48]×z[-91.2,-88.8]、卡车2 x[56,64]×z[-82.5,-79.5]，
## 新增卡车3/4 同款生成器顺泊（-38,-83）/(86,-84)
func _build_trucks(w) -> void:
	# 美术写实化：Blender 建模的厢式货车（huodai/tools/blender/make_truck.py，
	# 贴 CC0 实拍贴图）替代方块拼装；占地与车头朝向和原版一致（长 7.0m、
	# 车头 +X），碰撞 _obstacle 不变。模型缺失（未拉 LFS）回退原方块车
	var truck: PackedScene = load(TRUCK_GLB) if ResourceLoader.exists(TRUCK_GLB) else null
	for ti in TRUCKS.size():
		var tv: Vector2 = TRUCKS[ti]
		var hz: float = TRUCK_HZ[ti]
		if truck != null:
			var t: Node3D = truck.instantiate()
			t.position = Vector3(tv.x, 0.0, tv.y)
			w.add_child(t)
			_obstacle(w, tv.x, tv.y, 4.0, hz, 3.0)
			continue
		_place_box(w, tv.x - 0.4, 1.9, tv.y, 5.2, 2.2, 2.4, _mats["tan"])
		_place_box(w, tv.x + 3.1, 1.35, tv.y, 1.8, 2.0, 2.3, _mats["red"])
		for wdx_v in WHEEL_DX:
			var wdx: float = wdx_v
			for sd in [-1.0, 1.0]:
				var mi := MeshInstance3D.new()
				mi.mesh = _wheel_mesh
				mi.rotation.x = PI / 2.0
				mi.position = Vector3(tv.x + wdx, 0.45, tv.y + sd * 1.05)
				w.add_child(mi)
		_obstacle(w, tv.x, tv.y, 4.0, hz, 3.0)


## 白罐×3：卧式圆柱（rot.z=90° 轴向沿 x，罐轴离地 TANK_R）+ 各 1 条 AABB 碰撞
## （白天密度件：对位目标图东侧白色储罐群，避第二撤离环 r3 与东山脚障碍矩形）
func _build_tanks(w) -> void:
	for tp in TANKS:
		var tv: Vector2 = tp
		var mi := MeshInstance3D.new()
		mi.mesh = _tank_mesh
		mi.rotation.z = PI / 2.0
		mi.position = Vector3(tv.x, TANK_R, tv.y)
		w.add_child(mi)
		_obstacle(w, tv.x, tv.y, TANK_LEN * 0.5, TANK_R, TANK_R * 2.0)


## 自卸车×1：底盘 + 翘起货斗（rot.z=-0.28 尾部朝 -x 抬起=卸料姿态）+ 红车头
## + 6 轮（_wheel_mesh 共网复用）；碰撞只围整车 1 条（白天密度件）
func _build_dumper(w) -> void:
	var p: Vector2 = DUMPER
	_place_box(w, p.x, 0.9, p.y, 4.4, 0.6, 2.2, _mats["tan"])
	_place_box(w, p.x - 1.2, 2.0, p.y, 3.4, 1.0, 2.2, _mats["tan"],
			Vector3(0.0, 0.0, -0.28))
	_place_box(w, p.x + 2.1, 1.5, p.y, 1.4, 1.6, 2.1, _mats["red"])
	for wdx_v in WHEEL_DX:
		var wdx: float = wdx_v
		for sd in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = _wheel_mesh
			mi.rotation.x = PI / 2.0
			mi.position = Vector3(p.x + wdx, 0.45, p.y + sd * 1.0)
			w.add_child(mi)
	_obstacle(w, p.x, p.y, 3.0, 1.3, 3.0)


## 棕榈×18：弯干（基部摆根 rot.z 倾角）+ 顶端 6 片扁叶放射（YXZ 欧拉
## (0, yaw, -0.5) 先垂后转，共网复用）；不注册碰撞（软景，计划口径）
func _build_palms(w) -> void:
	# 美术写实化：Blender 建模棕榈（叶痕环弯干 + 拱垂羽叶 + 枯叶裙，树皮实拍贴图）
	# 替代方块拼装；株高/倾斜沿用原逐株参数，朝向随机。模型缺失回退原拼装
	var palm := PBR.scene(PALM_GLB)
	if palm != null:
		for i in PALM_XZ.size():
			var pv: Vector2 = PALM_XZ[i]
			var ph := 5.2 + 0.45 * float(i % 5)
			var lean := 0.05 + 0.03 * float((i * 3) % 4)
			if i % 2 == 1:
				lean = -lean
			var pivot := Node3D.new()
			pivot.position = Vector3(pv.x, 0.0, pv.y)
			pivot.rotation.z = lean
			w.add_child(pivot)
			var t: Node3D = palm.instantiate()
			var k := ph / 6.0
			t.scale = Vector3(0.9 + 0.1 * k, k, 0.9 + 0.1 * k)
			t.rotation.y = float(i) * 2.17
			pivot.add_child(t)
		return
	for i in PALM_XZ.size():
		var pv: Vector2 = PALM_XZ[i]
		var ph := 5.2 + 0.45 * float(i % 5)       # 5.2~7.0m（计划「高 5-7」）
		var lean := 0.05 + 0.03 * float((i * 3) % 4)
		if i % 2 == 1:
			lean = -lean
		var pivot := Node3D.new()
		pivot.position = Vector3(pv.x, 0.0, pv.y)
		pivot.rotation.z = lean
		w.add_child(pivot)
		var trunk := MeshInstance3D.new()
		trunk.mesh = _trunk_mesh
		trunk.scale = Vector3(1.0, ph / TRUNK_H, 1.0)
		trunk.position = Vector3(0.0, ph * 0.5, 0.0)
		pivot.add_child(trunk)
		# 干环箍 ×6（第 4 轮：环纹破光杆）
		for k in 6:
			var ring := MeshInstance3D.new()
			ring.mesh = _ring_mesh
			ring.position = Vector3(0.0, ph * (0.25 + 0.12 * float(k)), 0.0)
			pivot.add_child(ring)
		# 12 片放射羽叶：每叶 3 段折线盒（第 4 轮：外段逐级下垂 0.35→0.7→0.95，
		# 破平直「风车/扫帚」感，远景读作拱垂羽叶）
		for k in 12:
			var yaw := TAU * float(k) / 12.0 + 0.26
			var dirh := Vector3(cos(yaw), 0.0, -sin(yaw))
			var seg_pos := Vector3(0.0, ph - 0.43, 0.0)
			var ang := 0.0
			for seg in 3:
				ang -= 0.35 + 0.175 * float(seg)
				seg_pos = seg_pos + dirh * (SEG_LEN * cos(ang)) \
						+ Vector3(0.0, SEG_LEN * sin(ang), 0.0)
				var frond := MeshInstance3D.new()
				frond.mesh = _frond_seg_mesh
				frond.rotation = Vector3(0.0, yaw, ang)
				frond.position = seg_pos
				pivot.add_child(frond)
		# 冠球遮杆叶接缝（第 3 轮）
		var crown := MeshInstance3D.new()
		crown.mesh = _crown_mesh
		crown.position = Vector3(0.0, ph - 0.35, 0.0)
		pivot.add_child(crown)


## 山体×5：单位球半轴缩放（远景地标，不逐面碰撞），第 3 轮全体换岩棕 rock 网格；
## 只注册东山脚 2 条保守围合（建造计划⑫）+ 主山上撒 28 丛深橄榄灌木半球。
## 第 2 轮判图 #19：近山三座的山-沙交界是椭球赤道切线（直线硬接缝）——
## 山脚周圈撒 LCG 固定序列碎石+灌木过渡带，打破直线交界
func _build_hills(w) -> void:
	for hl in HILLS:
		var mi := MeshInstance3D.new()
		mi.mesh = _rock_mesh
		mi.position = hl["p"]
		mi.scale = hl["s"]
		w.add_child(mi)
	_obstacle(w, 126.0, -104.0, 20.0, 12.0, 16.0)
	_obstacle(w, 110.0, -114.0, 12.0, 6.0, 9.0)
	_build_shrubs(w)
	_build_hill_skirts(w)


## 山脚过渡带：近山（东脚×2+西嘴；远山/坝后山脊不值当）赤道圈外 1~4m 环带
## 撒碎石小球 ×10 + 灌木小半球 ×6/座——固定 LCG 幂等，不注册碰撞（<1.4m）
func _build_hill_skirts(w) -> void:
	var seed_v := 20261022
	for host in [HILLS[0], HILLS[1], HILLS[2]]:
		var hp: Vector3 = host["p"]
		var hs: Vector3 = host["s"]
		for k in 16:
			seed_v = (seed_v * 1103515245 + 12345) % 2147483648
			var th := TAU * (float(seed_v % 1000) / 1000.0 + float(k) / 16.0)
			seed_v = (seed_v * 1103515245 + 12345) % 2147483648
			var rr := 1.03 + 0.05 * float(seed_v % 100) / 100.0   # 赤道外 3~8%
			var px: float = hp.x + hs.x * rr * cos(th)
			var pz: float = hp.z + hs.z * rr * sin(th)
			seed_v = (seed_v * 1103515245 + 12345) % 2147483648
			if k % 8 < 5:   # 碎石小球（rock 网格缩小实例）
				var rs := 0.35 + 0.55 * float(seed_v % 100) / 100.0
				var mi := MeshInstance3D.new()
				mi.mesh = _rock_mesh
				mi.position = Vector3(px, 0.0, pz)
				mi.scale = Vector3(rs, rs * 0.7, rs)
				w.add_child(mi)
			else:           # 灌木小半球
				var bs := 0.5 + 0.4 * float(seed_v % 100) / 100.0
				_bush_at(w, Vector3(px, 0.0, pz), bs, float(seed_v % 628) / 100.0)


## 一丛灌木：实拍扫描灌木（0.58m 宽的低矮荒漠灌丛，按原半球半径放大到
## 同等占地）；缺失时回退原深橄榄半球
func _bush_at(w, p: Vector3, r: float, yaw: float) -> void:
	var shrub := PBR.scene(SHRUB_GLB)
	if shrub != null:
		var t: Node3D = shrub.instantiate()
		var k := r * 3.4
		t.scale = Vector3(k, k * 1.25, k)
		t.position = p
		t.rotation.y = yaw
		w.add_child(t)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _bush_mesh
	mi.position = p
	mi.scale = Vector3(r, r, r)
	w.add_child(mi)


## 主峰灌木丛（SHRUB_HOST=脊3）：LCG 伪随机固定序列（幂等），上半球面采样
## 嵌入椭球（0.9 缩已内嵌），r0.6~1.4 小半球
func _build_shrubs(w) -> void:
	var hp: Vector3 = SHRUB_HOST["p"]
	var hs: Vector3 = SHRUB_HOST["s"]
	var seed_v: int = SHRUB_SEED
	for i in SHRUB_N:
		seed_v = (int(seed_v) * 1103515245 + 12345) % 2147483648
		var th := TAU * float(seed_v % 1000) / 1000.0
		seed_v = (int(seed_v) * 1103515245 + 12345) % 2147483648
		var ph := 0.35 + 1.2 * float(seed_v % 1000) / 1000.0   # 仰角 20°~89°（上半球）
		var sx: float = hp.x + hs.x * sin(ph) * cos(th)
		var sy: float = hp.y + hs.y * cos(ph) - 0.3
		var sz: float = hp.z + hs.z * sin(ph) * sin(th)
		seed_v = (int(seed_v) * 1103515245 + 12345) % 2147483648
		var r := 0.6 + 0.8 * float(seed_v % 1000) / 1000.0
		_bush_at(w, Vector3(sx, sy, sz), r, th * 3.0)


## 烟柱×3：10 球递升叠片（第 4 轮：每球 LCG 随机 xz 偏移 ±0.6 破「等距球串」、
## 上段 4 球 material_override 换 smoke2 渐隐；顶 ~25m；无粒子系统零每帧开销）；
## 不注册碰撞
func _build_smoke(w) -> void:
	var seed_v: int = PUFF_SEED
	for s in SMOKES:
		var bp: Vector3 = s
		for k in PUFF_N:
			seed_v = (int(seed_v) * 1103515245 + 12345) % 2147483648
			var jx := (float(seed_v % 1000) / 1000.0 - 0.5) * 1.2
			seed_v = (int(seed_v) * 1103515245 + 12345) % 2147483648
			var jz := (float(seed_v % 1000) / 1000.0 - 0.5) * 1.2
			var mi := MeshInstance3D.new()
			mi.mesh = _smoke_mesh
			mi.position = bp + Vector3(PUFF_DX * float(k) + jx,
					PUFF_H0 + PUFF_DH * float(k), 0.3 * float(k) + jz)
			var r: float = PUFF_R0 + PUFF_DR * float(k)
			mi.scale = Vector3(r, r, r)
			if k >= PUFF_FADE:
				mi.material_override = _mats["smoke2"]
			w.add_child(mi)


## 坝区点位登记（main.gd:63/70 在 world.build() 后消费，时序已核实）：
## 容器 13 + 巡逻 7，全部 zone="dam"（hd_world.gd:229-235 同款字典格式）
func _register_spots(w) -> void:
	for p in DAM_CONTAINERS:
		var v: Vector2 = p
		w.container_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": DAM_ZONE})
	for p in DAM_PATROLS:
		var v: Vector2 = p
		w.patrol_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": DAM_ZONE})


# ================= 摆放小件 =================

func _place_box(parent: Node3D, x: float, y: float, z: float, w: float, h: float,
		d: float, mat: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(w, h, d, mat)
	mi.position = Vector3(x, y, z)
	if rot != Vector3.ZERO:
		mi.rotation = rot
	parent.add_child(mi)
	# 写实化：大面墙挂风化污迹贴花（雨水流挂 + 墙脚尘土）
	if rot == Vector3.ZERO and _grime_mats.has(mat):
		PBR.grime_decal(parent, Vector3(x, y, z), Vector3(w, h, d))
	return mi


func _obstacle(w, cx: float, cz: float, hx: float, hz: float, top: float,
		bot := 0.0) -> void:
	w.obstacles.append({"cx": cx, "cz": cz, "hx": hx, "hz": hz, "top": top, "bot": bot})
