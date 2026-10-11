class_name HDDamBase
extends Node3D
## 坝底工业区陈设（搜打撤「烽火地带」大坝分区·软景层）——
## 厂房×3（甲绿 26×9×14 / 乙黄 18×6×12 / 丙泵站 10×5×8：四墙 0.5 厚围合、
## 南墙 4m 门洞 + 红门楣 + 平顶出檐 + 屋顶空调机组阵列）/ 集装箱堆场
## （3 堆「2 底 z 向 ±3.2 + 1 顶压北列」+ 单箱×2，全部长轴=x + 端门片）/
## 工地（围挡板 43 块圈 36×20、南墙留双门，砂堆×2，挖机粗模 7 盒，卷材 3+2+1）/
## 卡车×2（长轴=x 顺泊，车头红货厢黄 + 6 轮 seg10）/ 棕榈×12（弯干 + 放射叶）/
## 山体×5（单位球缩放椭球：东脚×2 + 西嘴 + 坝后衬山×2）/ 烟柱×2（三球递升）/
## 工业区硬地衔接 200×29 一块。坝区容器点 13 + 巡逻点 7（zone="dam"）。
## 职责切分（建造计划 contracts）：坝体硬结构（坝基/台阶/廊道/扶壁垛/涂鸦/
## 闸门排/取水塔…）归 hd_dam.gd（HDDam），本文件只做坝底陈设与软景。
## 入口 build(root)：root 即 HDWorld——视觉 add_child(root)，障碍与点位
## root.obstacles / root.container_spots / root.patrol_spots append
## （hd_loot.gd:141-143 先例）；由 hd_world.build() 末装配，先 HDDam 后本件。
## 碰撞登记 34 条（只给可玩区与墙体，棕榈/烟柱/衬山/挖机臂不注册）：
## 厂房墙 15 + 集装箱堆 5 + 围挡 6 + 砂堆 2 + 挖机 1 + 卷材 1 + 卡车 2 + 东山脚 2。
## 材质恰 5 枚（tan/green/red/leaf/smoke），与 hd_dam.gd 5 枚合计=10，零跨文件引用。

const WALL_T := 0.5             # 厂房墙厚
const HOARD_T := 0.12           # 围挡板厚
const HOARD_H := 2.2            # 围挡板高
const TRUNK_H := 6.0            # 棕榈干基准高（逐株 y 向缩放出 5.2~7.0m）
const CBOX := Vector3(6.06, 2.59, 2.44)   # 集装箱 长×高×宽（20ft，长轴=x）
const CSTACK_DZ := 3.2          # 堆场底箱 z 向错位半距（2 底 z 向 ±3.2，计划口径）
const DAM_ZONE := "dam"

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

## 集装箱堆场（建造计划 Q）：3 堆（2 底 z 向 ±3.2 + 1 顶压北列）+ 2 单箱，长轴全=x
const YARD_STACKS := [Vector2(-46.0, -95.0), Vector2(-38.0, -90.0), Vector2(-53.0, -100.0)]
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

## 卡车×2（建造计划 S）：长轴=x 顺泊；hz 按计划口径 1.2 / 1.5
const TRUCKS := [Vector2(-52.0, -90.0), Vector2(60.0, -81.0)]
const TRUCK_HZ := [1.2, 1.5]
const WHEEL_DX := [-2.4, -1.2, 2.9]   # 轮位（相对车心 x）：后双轴 + 前轴

## 棕榈×12（建造计划 T）：街带 z=-86 九株 + 撤离广场三株
const PALM_XZ := [
	Vector2(-110.0, -86.0), Vector2(-96.0, -86.0), Vector2(-82.0, -86.0),
	Vector2(-54.0, -86.0), Vector2(-12.0, -86.0), Vector2(8.0, -86.0),
	Vector2(22.0, -86.0), Vector2(48.0, -86.0), Vector2(80.0, -86.0),
	Vector2(90.0, -91.0), Vector2(96.0, -91.0), Vector2(93.0, -89.5),
]

## 山体×5（建造计划 U）：单位球按半轴缩放（中心贴地，下半球入地成穹丘）；
## 半轴取计划复算口径：山1(31.2,18.2,23.4)、山2(21.6,18.2,16.2)
const HILLS := [
	{"p": Vector3(126.0, 0.0, -102.0), "s": Vector3(31.2, 18.2, 23.4)},   # 东脚山1
	{"p": Vector3(108.0, 0.0, -116.0), "s": Vector3(21.6, 18.2, 16.2)},   # 东脚山2
	{"p": Vector3(-146.0, 0.0, -116.0), "s": Vector3(16.8, 9.8, 12.6)},   # 西嘴
	{"p": Vector3(-60.0, 0.0, -162.0), "s": Vector3(48.0, 28.0, 36.0)},   # 衬山·坝后西
	{"p": Vector3(50.0, 0.0, -165.0), "s": Vector3(55.2, 32.2, 41.4)},    # 衬山·坝后东
]

## 烟柱×2（建造计划 V）：三球递升（基点 + 2/5.5/9m，半径 1.7/2.1/2.5，风向 +x+z 漂移）
const SMOKES := [Vector3(45.0, 0.0, -87.0), Vector3(-5.0, 54.0, -143.0)]
const PUFF_R := [1.7, 2.1, 2.5]

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
var _mats := {}                  # 材质表（恰 5 枚，见 _make_mats）
var _mesh_cache := {}            # 材质 -> {尺寸键 -> BoxMesh}（同尺寸同材质共用一张网格）
var _hill_mesh: SphereMesh       # 单位球：山体与砂堆共用（tan）
var _smoke_mesh: SphereMesh      # 单位球：烟团（smoke 半透明）
var _coil_mesh: CylinderMesh
var _wheel_mesh: CylinderMesh
var _trunk_mesh: CylinderMesh
var _frond_mesh: BoxMesh


func build(root: Node3D) -> void:
	if _built or root == null:
		return
	_built = true
	var w = root   # HDWorld（鸭子类型：obstacles/点位容器动态访问，hd_loot.gd 同款）
	_make_mats()
	_make_meshes()
	_build_hardstand(w)
	_build_factories(w)
	_build_container_yard(w)
	_build_site(w)
	_build_trucks(w)
	_build_palms(w)
	_build_hills(w)
	_build_smoke(w)
	_register_spots(w)


# ================= 材质与共用网格 =================

## 材质恰 5 枚（BASE 侧份额）：tan 戈壁黄 / green 厂房甲工业绿 /
## red 氧化红（箱·机组·门楣·车头·驾驶室）/ leaf 棕榈叶 / smoke 灰黑半透明
func _make_mats() -> void:
	_mats["tan"] = _std_mat(Color(0.72, 0.62, 0.4), 1.0, 0.0)
	_mats["green"] = _std_mat(Color(0.33, 0.43, 0.3), 0.85, 0.0)
	_mats["red"] = _std_mat(Color(0.55, 0.18, 0.14), 0.65, 0.2)
	_mats["leaf"] = _std_mat(Color(0.27, 0.4, 0.19), 1.0, 0.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.3, 0.29, 0.28, 0.35)   # alpha0.35（计划口径）
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 1.0
	_mats["smoke"] = sm


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
	_hill_mesh.material = _mats["tan"]
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
	_wheel_mesh = CylinderMesh.new()
	_wheel_mesh.top_radius = 0.45
	_wheel_mesh.bottom_radius = 0.45
	_wheel_mesh.height = 0.3
	_wheel_mesh.radial_segments = 10
	_wheel_mesh.rings = 1
	_wheel_mesh.material = _mats["tan"]
	_trunk_mesh = CylinderMesh.new()
	_trunk_mesh.top_radius = 0.13
	_trunk_mesh.bottom_radius = 0.22
	_trunk_mesh.height = TRUNK_H
	_trunk_mesh.radial_segments = 8
	_trunk_mesh.rings = 1
	_trunk_mesh.material = _mats["tan"]
	_frond_mesh = BoxMesh.new()
	_frond_mesh.size = Vector3(2.6, 0.05, 0.45)
	_frond_mesh.material = _mats["leaf"]


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
## 底面 -0.07 埋地（hd_world.gd:524 靶馆地坪同手法），不注册碰撞（纯地面）
func _build_hardstand(w) -> void:
	_place_box(w, 5.0, -0.02, -92.5, 200.0, 0.1, 29.0, _mats["tan"])


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
		# 屋顶空调机组阵列（红点缀，坐屋面 y=fh+0.4）
		var hsz: Vector3 = f["hvac_sz"]
		for hp in f["hvac"]:
			var hv: Vector2 = hp
			_place_box(w, hv.x, fh + 0.4 + hsz.y * 0.5, hv.y, hsz.x, hsz.y, hsz.z,
					_mats["red"])
		# 碰撞：四墙 5 段（建造计划⑦，三栋共 15 段）
		_obstacle(w, cx, z0 + WALL_T * 0.5, fx * 0.5, WALL_T * 0.5, fh)
		_obstacle(w, (x0 + d0) * 0.5, z1 - WALL_T * 0.5, (d0 - x0) * 0.5, WALL_T * 0.5, fh)
		_obstacle(w, (d1 + x1) * 0.5, z1 - WALL_T * 0.5, (x1 - d1) * 0.5, WALL_T * 0.5, fh)
		_obstacle(w, x0 + WALL_T * 0.5, cz, WALL_T * 0.5, (fz - WALL_T * 2.0) * 0.5, fh)
		_obstacle(w, x1 - WALL_T * 0.5, cz, WALL_T * 0.5, (fz - WALL_T * 2.0) * 0.5, fh)


## 集装箱堆场：箱体 + 两端门片（外探 6cm 消共面）；堆=底箱 z 向 ±3.2 两列 +
## 顶箱压北列（计划「1 顶」落柱式——两底列净距 3.96m 跨中悬顶会浮空，复算改压柱，
## 足迹 AABB 与计划复算值一致）；碰撞 3 堆 + 2 单箱 = 5 条（建造计划⑧）
func _build_container_yard(w) -> void:
	for s in YARD_STACKS:
		var sv: Vector2 = s
		_container(w, sv.x, 0.0, sv.y - CSTACK_DZ)
		_container(w, sv.x, 0.0, sv.y + CSTACK_DZ)
		_container(w, sv.x, CBOX.y, sv.y - CSTACK_DZ)
		_obstacle(w, sv.x, sv.y, CBOX.x * 0.5, CSTACK_DZ + CBOX.z * 0.5, CBOX.y * 2.0)
	for p in YARD_SINGLES:
		var pv: Vector2 = p
		_container(w, pv.x, 0.0, pv.y)
		_obstacle(w, pv.x, pv.y, CBOX.x * 0.5, CBOX.z * 0.5, CBOX.y)


func _container(w, x: float, y0: float, z: float) -> void:
	var cy := y0 + CBOX.y * 0.5
	_place_box(w, x, cy, z, CBOX.x, CBOX.y, CBOX.z, _mats["red"])
	for side in [-1.0, 1.0]:
		_place_box(w, x + side * (CBOX.x * 0.5 + 0.02), cy, z,
				0.08, CBOX.y - 0.2, CBOX.z - 0.1, _mats["red"])


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


## 卡车×2：货厢（tan）+ 平头车头（红）+ 6 轮（seg10 共网，rot.x=90° 轴向沿 z）；
## 碰撞按计划定死 AABB：卡车1 x[-56,-48]×z[-91.2,-88.8]、卡车2 x[56,64]×z[-82.5,-79.5]
func _build_trucks(w) -> void:
	for ti in TRUCKS.size():
		var tv: Vector2 = TRUCKS[ti]
		var hz: float = TRUCK_HZ[ti]
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


## 棕榈×12：弯干（基部摆根 rot.z 倾角）+ 顶端 6 片扁叶放射（YXZ 欧拉
## (0, yaw, -0.5) 先垂后转，共网 72 摆）；不注册碰撞（软景，计划口径）
func _build_palms(w) -> void:
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
		for k in 6:
			var frond := MeshInstance3D.new()
			frond.mesh = _frond_mesh
			var yaw := TAU * float(k) / 6.0 + 0.26
			frond.rotation = Vector3(0.0, yaw, -0.5)
			var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
			frond.position = Vector3(0.0, ph - 0.43, 0.0) + dir * 1.05
			pivot.add_child(frond)


## 山体×5：单位球半轴缩放（远景地标，不逐面碰撞）；只注册东山脚 2 条
## 保守围合（建造计划⑫：{126,-104,20,12,top16} + {110,-114,12,6,top9}）
func _build_hills(w) -> void:
	for hl in HILLS:
		var mi := MeshInstance3D.new()
		mi.mesh = _hill_mesh
		mi.position = hl["p"]
		mi.scale = hl["s"]
		w.add_child(mi)
	_obstacle(w, 126.0, -104.0, 20.0, 12.0, 16.0)
	_obstacle(w, 110.0, -114.0, 12.0, 6.0, 9.0)


## 烟柱×2：三球递升叠片（半透明 smoke，无粒子系统零每帧开销）；不注册碰撞
func _build_smoke(w) -> void:
	for s in SMOKES:
		var bp: Vector3 = s
		for k in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = _smoke_mesh
			mi.position = bp + Vector3(0.4 * float(k), 2.0 + 3.5 * float(k), 0.3 * float(k))
			var r: float = PUFF_R[k]
			mi.scale = Vector3(r, r, r)
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
	return mi


func _obstacle(w, cx: float, cz: float, hx: float, hz: float, top: float,
		bot := 0.0) -> void:
	w.obstacles.append({"cx": cx, "cz": cz, "hx": hx, "hz": hz, "top": top, "bot": bot})
