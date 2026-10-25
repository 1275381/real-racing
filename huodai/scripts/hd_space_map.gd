extends Node3D
## 烽火地带 —— 第二张实战地图「航天基地」（hd_space_map.gd）。
## 与零号大坝并存、出发可选、互不连通（hd_world.set_map 原地重建，本文件由
## hd_world 按路径 preload——照 hd_dam_zones.gd 先例，无 class_name）。
##
## —— 布局（坐标系：北 = -Z 中控楼方向、南 = +Z 发射区、东 = +X 工业带、
##    西 = -X 水渠荒野；对位官方拼接图 ref_space/ref_01..14，方位经
##    腾讯官方地图工具 + 游民星空攻略 + timesaver 三方交叉验证）——
## 核心区（几何中心）：围墙院 x∈[-36,36]×z∈[-36,40]——离心机室(西南)/浮力室
##   (西北)/蓝室(东北)/黑室(东南) 四室围合 + 正中四层总裁室塔 + 南侧中心花园
##   下沉广场；仅两条主要通道（北=中控桥、南=员工通道）进入；
## 中控楼（北 x∈[-14,14]×z∈[-92,-70] 三层 + 楼顶天线阵）+ 中控桥（x∈[-4.5,4.5]
##   ×z∈[-70,-36] 跨水道细长桥）＝「守桥人」对枪点；
## 水系：正南水道（z∈[-64,-54] 东西向）+ 西侧纵贯水渠（x∈[-58,-50] 南北向）
##   + 河湾（x∈[-66,-42]×z∈[42,64]）——铁丝网围死、桥/涵洞过人；
## 工业带（东 L 形）：总装主厂房（x∈[58,106]×z∈[-58,-18] 含吊装跨/流水线）
##   + 打印室 + 组装室 + 罐装区（6 立式燃料储罐 + 泵房 + 管廊南引到发射坪）
##   + 水平试车场（长条测试综合体 + 中控室电闸 + 尾门）；
## 宿舍区（西北 3 栋两层宿舍楼 + 中庭水塔 + 西侧停车场＝常开撤离）；
## 发射区（正南围墙院 x∈[-34,34]×z∈[92,140]）：火箭本体（白圆柱 h≈61 灵魂
##   地标，远看可辨）+ 勤务塔 + 发射座 + 垂直总装厂房 + 设备房×2 + 观景坪
##   （12:00 定时撤离）+ 避雷塔×3；图上无机场跑道/铁路（官方图核验：运输靠
##   公路 + 管道廊——北路/桥路/南路/东路四条公路 + 燃料管廊）；
## 外围：荒野戈壁环带（图缘出生投放带，几乎无物资）。
## 地下靶馆与入口房沿用大坝同坐标（hd_world 全局件，两图共享——切换架构
## 二选一里选了「space 图同坐标建造馆体」，靶场照旧从大厅 G 进）。
##
## —— 分区映射（合同/品质/精英/危险横幅零改动照跑）——
## zone_at.center ＝ 核心区围墙院 + 发射工位坪（高价值钥匙房密集区/事件区）；
## zone_at.dam ＝ 东侧工业带（总装/罐装/试车 L 形）+ 北部控制点（中控楼+桥）；
## zone_at.mid ＝ 宿舍区 + 发射区外围 + 水渠/道路廊道；zone_at.wild ＝ 图缘荒野
## （距原点 >135m 环带）。
##
## —— 点位契约（hd_loot/hd_soldiers 消费；zone 串 = zone_at 逐点核对值）——
## 容器 55（center 25 / dam 16 / mid 10 / wild 4，分区权重照 HDData 分区表）；
## 巡逻 32（center 12 / dam 9 / mid 7 / wild 4，每分区 ≥3 成路）；出生 5 处在
## HDData.SPACE_SPAWN_POINTS（图缘荒野，离巡逻点 ≥30m）；撤离五处按
## HDData.SPACE_EXTRACT_*（槽位复用既有 extract 机制）。
## 障碍静态 ≈280 条（{cx,cz,hx,hz,top,bot} 轴对齐契约；铁丝网/管线/细饰件
## 纯视觉不注册——hd_dam.gd:16-17 远景件先例；大件 cast_shadow OFF 先例）。
##
## —— 材质恰 17 枚（对齐 dam 9 / base 15 / zones 15 的份额纪律，零跨文件引用）——
## conc 混凝土 / conc_dark 暗色 / metal 厂房金属墙板 / metal_dark 深钢 /
## yellow 工业黄 / white 火箭白 / red 红件 / glass 玻璃 / pipe 银灰管道 /
## rust 锈橙 / tank 储罐白漆 / water 水 / asphalt 沥青 / plaza 铺装 /
## green 军绿宿舍 / sand 河床沙 / lamp 灯罩自发光。

const PBR := preload("res://scripts/hd_pbr.gd")
const QUIVER_GLB := "res://assets/pbr/models/quiver_tree_02/quiver_tree_02_lod.glb"
const DEAD_TREE_GLB := "res://assets/battle/props/dead_tree.glb"
const BOULDER_GLB := "res://assets/pbr/models/boulder_01/boulder_01_1k.gltf"
const WALL_T := 0.5              # 建筑墙厚（zones 同款）
const GROUND_TOP := 0.03         # 铺装顶面统一标高（与大地错层防 z-fighting）
const DOOR_H := 2.4              # 门洞净高（门楣悬空不注册）
const FENCE_H := 1.3             # 铁丝网高（拦人：top>1.0 挡 AI/玩家，弹道高位直穿）
const RAIL_H := 1.15             # 桥栏高

## 容器点位 55（zone 串 = zone_at 逐点核对；全部落地面 y=0——hd_loot 地面语义）
const SPACE_CONTAINERS := [
	# —— 核心区四室 + 总裁室 + 花园 + 院巷（center 21）——
	{"p": Vector2(-24.0, -21.0), "z": "center"},   # 离心机室主机旁
	{"p": Vector2(-28.0, -13.0), "z": "center"},   # 离心机室西北角
	{"p": Vector2(-16.0, -27.0), "z": "center"},   # 离心机室东南角
	{"p": Vector2(-22.0, 17.0), "z": "center"},    # 浮力室潜池东
	{"p": Vector2(-29.0, 24.0), "z": "center"},    # 浮力室西北角
	{"p": Vector2(-14.0, 11.0), "z": "center"},    # 浮力室东南角
	{"p": Vector2(22.0, 17.0), "z": "center"},     # 蓝室中部
	{"p": Vector2(30.0, 24.0), "z": "center"},     # 蓝室东北角
	{"p": Vector2(14.0, 11.0), "z": "center"},     # 蓝室西南角
	{"p": Vector2(22.0, -21.0), "z": "center"},    # 黑室中部
	{"p": Vector2(30.0, -13.0), "z": "center"},    # 黑室东北角
	{"p": Vector2(14.0, -27.0), "z": "center"},    # 黑室西南角
	{"p": Vector2(0.0, -2.0), "z": "center"},      # 总裁室一层
	{"p": Vector2(-5.0, 3.0), "z": "center"},      # 总裁室西北角
	{"p": Vector2(0.0, 32.0), "z": "center"},      # 中心花园下沉广场
	{"p": Vector2(-20.0, 33.0), "z": "center"},    # 花园西
	{"p": Vector2(20.0, 33.0), "z": "center"},     # 花园东
	{"p": Vector2(-22.0, 0.0), "z": "center"},     # 西巷（离心机/总裁室间）
	{"p": Vector2(22.0, 2.0), "z": "center"},      # 东巷（黑室/总裁室间）
	{"p": Vector2(0.0, -30.0), "z": "center"},     # 南院（离心机/黑室间）
	{"p": Vector2(0.0, 16.0), "z": "center"},      # 北院（浮力室/蓝室间）
	# —— 发射工位坪（center 4）——
	{"p": Vector2(0.0, 122.0), "z": "center"},     # 发射座南侧坪面
	{"p": Vector2(-20.0, 112.0), "z": "center"},   # 垂直总装厂房内
	{"p": Vector2(18.0, 98.0), "z": "center"},     # 东设备房内
	{"p": Vector2(19.0, 134.0), "z": "center"},    # 南设备房内
	# —— 东侧工业带（dam 14）——
	{"p": Vector2(70.0, -46.0), "z": "dam"},       # 主厂房西跨
	{"p": Vector2(88.0, -38.0), "z": "dam"},       # 主厂房中跨（首领把口）
	{"p": Vector2(98.0, -50.0), "z": "dam"},       # 主厂房东跨
	{"p": Vector2(63.0, -24.0), "z": "dam"},       # 主厂房南跨
	{"p": Vector2(94.0, -26.0), "z": "dam"},       # 主厂房东南
	{"p": Vector2(70.0, -4.0), "z": "dam"},        # 打印室内
	{"p": Vector2(78.0, 2.0), "z": "dam"},         # 打印室东南
	{"p": Vector2(100.0, 0.0), "z": "dam"},        # 组装室内
	{"p": Vector2(94.0, 8.0), "z": "dam"},         # 组装室西南
	{"p": Vector2(77.0, 34.0), "z": "dam"},        # 罐装区西排罐间
	{"p": Vector2(91.0, 46.0), "z": "dam"},        # 罐装区南排罐间
	{"p": Vector2(98.0, 40.0), "z": "dam"},        # 罐装区东列罐间
	{"p": Vector2(63.0, 22.5), "z": "dam"},        # 泵房内
	{"p": Vector2(80.0, 78.0), "z": "dam"},        # 试车场厂房内
	# —— 北部控制点（dam 2）——
	{"p": Vector2(0.0, -82.0), "z": "dam"},        # 中控楼指挥厅
	{"p": Vector2(-11.0, -86.0), "z": "dam"},      # 中控楼西侧室
	# —— 宿舍/发射外围/廊道（mid 10）——
	{"p": Vector2(-96.0, -89.0), "z": "mid"},      # 宿舍A楼内（西半间）
	{"p": Vector2(-87.0, -71.0), "z": "mid"},      # 宿舍B楼内（东半间）
	{"p": Vector2(-66.0, -84.0), "z": "mid"},      # 宿舍C楼内（东半间）
	{"p": Vector2(-90.0, -80.0), "z": "mid"},      # 宿舍中庭
	{"p": Vector2(-108.0, -70.0), "z": "mid"},     # 停车场
	{"p": Vector2(0.0, 70.0), "z": "mid"},         # 南路（员工通道廊道）
	{"p": Vector2(-30.0, 66.0), "z": "mid"},       # 发射区外围西
	{"p": Vector2(30.0, 74.0), "z": "mid"},        # 发射区外围东
	{"p": Vector2(50.0, 20.0), "z": "mid"},        # 东路口
	{"p": Vector2(-44.0, 10.0), "z": "mid"},       # 西桥水渠廊道
	# —— 图缘荒野（wild 4）——
	{"p": Vector2(132.0, 46.0), "z": "wild"},      # 东荒野
	{"p": Vector2(-140.0, -16.0), "z": "wild"},    # 西荒野
	{"p": Vector2(-88.0, 124.0), "z": "wild"},     # 西南荒野
	{"p": Vector2(60.0, 130.0), "z": "wild"},      # 东南荒野
]

## 巡逻点 32（zone 串 = zone_at 逐点核对；hd_soldiers 同 zone 过滤成路）
const SPACE_PATROLS := [
	{"p": Vector2(-24.0, -19.0), "z": "center"},   # 离心机室
	{"p": Vector2(-22.0, 13.0), "z": "center"},    # 浮力室
	{"p": Vector2(20.0, 20.0), "z": "center"},     # 蓝室
	{"p": Vector2(22.0, -17.0), "z": "center"},    # 黑室
	{"p": Vector2(-25.0, -3.0), "z": "center"},    # 西巷
	{"p": Vector2(25.0, 0.0), "z": "center"},      # 东巷
	{"p": Vector2(0.0, -26.0), "z": "center"},     # 南院
	{"p": Vector2(0.0, 18.0), "z": "center"},      # 北院
	{"p": Vector2(12.0, 33.0), "z": "center"},     # 中心花园
	{"p": Vector2(-12.0, 33.0), "z": "center"},    # 花园西
	{"p": Vector2(0.0, 106.0), "z": "center"},     # 发射坪北
	{"p": Vector2(-8.0, 122.0), "z": "center"},    # 发射坪西
	{"p": Vector2(70.0, -40.0), "z": "dam"},       # 主厂房西
	{"p": Vector2(92.0, -46.0), "z": "dam"},       # 主厂房东
	{"p": Vector2(75.0, -4.0), "z": "dam"},        # 打印室
	{"p": Vector2(105.0, 3.0), "z": "dam"},        # 组装室
	{"p": Vector2(84.0, 40.0), "z": "dam"},        # 罐装区
	{"p": Vector2(80.0, 70.0), "z": "dam"},        # 试车场
	{"p": Vector2(0.0, -78.0), "z": "dam"},        # 中控楼
	{"p": Vector2(0.0, -50.0), "z": "dam"},        # 中控桥（守桥人）
	{"p": Vector2(64.0, 28.0), "z": "dam"},        # 罐装北路口
	{"p": Vector2(-88.0, -86.0), "z": "mid"},      # 宿舍A
	{"p": Vector2(-88.0, -69.0), "z": "mid"},      # 宿舍B
	{"p": Vector2(-66.0, -82.0), "z": "mid"},      # 宿舍C
	{"p": Vector2(-96.0, -80.0), "z": "mid"},      # 宿舍中庭
	{"p": Vector2(-108.0, -74.0), "z": "mid"},     # 停车场
	{"p": Vector2(0.0, 64.0), "z": "mid"},         # 南路
	{"p": Vector2(-34.0, 62.0), "z": "mid"},       # 发射外围西
	{"p": Vector2(136.0, 40.0), "z": "wild"},      # 东荒野
	{"p": Vector2(-136.0, -24.0), "z": "wild"},    # 西荒野
	{"p": Vector2(-92.0, 118.0), "z": "wild"},     # 西南荒野
	{"p": Vector2(64.0, 132.0), "z": "wild"},      # 东南荒野
]

var _built := false
var _mats := {}                  # 材质表（恰 17 枚）
var _mesh_cache := {}            # 材质 -> {尺寸键 -> BoxMesh}
var _mesh_tank: CylinderMesh     # 立式储罐 r4.2 h11
var _mesh_sphere: SphereMesh     # LOX 球罐/料堆单位球
var _mesh_rocket: CylinderMesh   # 火箭箭体 r3.0 h58
var _mesh_nose: CylinderMesh     # 箭头锥 r3.0→0.35 h5.5
var _mesh_mast: CylinderMesh     # 天线/避雷塔杆 r0.14 h11


func build(root: Node3D) -> void:
	if _built or root == null:
		return
	_built = true
	var w = root   # HDWorld（鸭子类型，hd_dam_zones.gd:103 同款）
	_make_mats()
	_dress_pbr()
	_make_meshes()
	_terrain(w)      # 水道/水渠/河湾 + 四条公路 + 中控桥/西桥 + 燃料管廊
	_core(w)         # 核心区围墙院（四室 + 总裁室 + 中心花园）
	_control(w)      # 中控楼（多层 + 楼顶天线阵）
	_industrial(w)   # 总装主厂房 + 打印室 + 组装室
	_tankfarm(w)     # 罐装区（储罐群 + 泵房）
	_teststand(w)    # 水平试车场（测试综合体 + 中控室电闸 + 尾门）
	_dorm(w)         # 宿舍区（3 栋 + 中庭 + 停车场）
	_launch(w)       # 发射区（火箭 + 勤务塔 + 总装厂房 + 观景坪）
	_wild(w)         # 荒野戈壁环带（乱石/枯树/残骸）
	_register_spots(w)


# ================= 材质与共用网格 =================

var _grime_mats: Array = []   # 挂风化污迹贴花的墙体材质


func _dress_pbr() -> void:
	var plan := {
		"conc": ["concrete", 4.0],
		"conc_dark": ["asphalt", 3.0],
		"metal": ["corrugated", 3.0],
		"metal_dark": ["paint_rust", 1.8],
		"yellow": ["brick", 2.2],
		"white": ["plaster_paint", 3.0],
		"red": ["paint_rust", 2.0],
		"pipe": ["paint_rust", 1.5],
		"rust": ["paint_rust", 1.5],
		"tank": ["paint_rust", 3.0],
		"asphalt": ["asphalt", 4.0],
		"plaza": ["concrete", 3.0],
		"green": ["container", 2.4],
		"sand": ["sand", 3.0],
	}
	for key in plan:
		if _mats.has(key):
			PBR.dress(_mats[key], str(plan[key][0]), float(plan[key][1]))
	for key in ["conc", "white", "metal", "green", "yellow"]:
		if _mats.has(key):
			_grime_mats.append(_mats[key])
	PBR.glass(_mats["glass"])


func _make_mats() -> void:
	_mats["conc"] = _std_mat(Color(0.74, 0.73, 0.70), 0.9, 0.0)
	_mats["conc_dark"] = _std_mat(Color(0.2, 0.21, 0.22), 0.9, 0.0)
	_mats["metal"] = _std_mat(Color(0.55, 0.57, 0.60), 0.55, 0.35)
	_mats["metal_dark"] = _std_mat(Color(0.3, 0.32, 0.36), 0.6, 0.4)
	_mats["yellow"] = _std_mat(Color(0.68, 0.58, 0.36), 0.85, 0.0)
	_mats["white"] = _std_mat(Color(0.87, 0.86, 0.83), 0.7, 0.05)
	_mats["red"] = _std_mat(Color(0.55, 0.18, 0.14), 0.65, 0.2)
	_mats["glass"] = _std_mat(Color(0.16, 0.25, 0.36), 0.15, 0.6)
	_mats["pipe"] = _std_mat(Color(0.62, 0.65, 0.68), 0.4, 0.7)
	_mats["rust"] = _std_mat(Color(0.5, 0.3, 0.18), 1.0, 0.0)
	_mats["tank"] = _std_mat(Color(0.78, 0.79, 0.77), 0.6, 0.15)
	_mats["water"] = _std_mat(Color(0.09, 0.19, 0.27), 0.06, 0.5)
	_mats["asphalt"] = _std_mat(Color(0.16, 0.16, 0.17), 0.9, 0.0)
	_mats["plaza"] = _std_mat(Color(0.5, 0.49, 0.47), 1.0, 0.0)
	_mats["green"] = _std_mat(Color(0.4, 0.42, 0.30), 0.85, 0.0)
	_mats["sand"] = _std_mat(Color(0.52, 0.45, 0.36), 1.0, 0.0)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.9, 0.88, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(0.98, 0.95, 0.85)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp"] = lamp


func _std_mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _make_meshes() -> void:
	_mesh_tank = CylinderMesh.new()
	_mesh_tank.top_radius = 4.2
	_mesh_tank.bottom_radius = 4.2
	_mesh_tank.height = 11.0
	_mesh_tank.radial_segments = 24
	_mesh_tank.rings = 2
	_mesh_sphere = SphereMesh.new()
	_mesh_sphere.radius = 1.0
	_mesh_sphere.height = 2.0
	_mesh_sphere.radial_segments = 16
	_mesh_sphere.rings = 8
	_mesh_rocket = CylinderMesh.new()
	_mesh_rocket.top_radius = 3.0
	_mesh_rocket.bottom_radius = 3.3
	_mesh_rocket.height = 58.0
	_mesh_rocket.radial_segments = 28
	_mesh_rocket.rings = 6
	_mesh_nose = CylinderMesh.new()
	_mesh_nose.top_radius = 0.35
	_mesh_nose.bottom_radius = 3.0
	_mesh_nose.height = 5.5
	_mesh_nose.radial_segments = 28
	_mesh_nose.rings = 4
	_mesh_mast = CylinderMesh.new()
	_mesh_mast.top_radius = 0.12
	_mesh_mast.bottom_radius = 0.16
	_mesh_mast.height = 11.0
	_mesh_mast.radial_segments = 8


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


# ================= 摆放小件 =================

func _place_box(parent: Node3D, x: float, y: float, z: float, w: float, h: float,
		d: float, mat: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(w, h, d, mat)
	mi.position = Vector3(x, y, z)
	if rot != Vector3.ZERO:
		mi.rotation = rot
	parent.add_child(mi)
	# 写实化：大面墙挂风化污迹贴花（雨水流挂 + 墙脚尘土）+ 勒脚/压顶/壁柱
	if rot == Vector3.ZERO and _grime_mats.has(mat):
		PBR.grime_decal(parent, Vector3(x, y, z), Vector3(w, h, d))
		PBR.relief(parent, Vector3(x, y, z), Vector3(w, h, d), mat)
	return mi


## 立式共用圆柱件（储罐/火箭/天线杆），可选缩放与材质覆盖
func _cyl(parent: Node3D, mesh: Mesh, pos: Vector3, mat: StandardMaterial3D,
		scl := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)


func _pile(parent: Node3D, pos: Vector3, scl: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_sphere
	mi.position = pos
	mi.scale = scl
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)


func _obstacle(w, cx: float, cz: float, hx: float, hz: float, top: float,
		bot := 0.0) -> void:
	w.obstacles.append({"cx": cx, "cz": cz, "hx": hx, "hz": hz, "top": top, "bot": bot})


## 铺装地坪（纯地面不注册）：顶面统一 GROUND_TOP 与大地错层
func _pave(w, cx: float, cz: float, sx: float, sz: float) -> void:
	_place_box(w, cx, GROUND_TOP - 0.05, cz, sx, 0.1, sz, _mats["plaza"])


## 沥青路面（带中央虚线）
func _road(w, cx: float, cz: float, sx: float, sz: float) -> void:
	_place_box(w, cx, GROUND_TOP - 0.05, cz, sx, 0.1, sz, _mats["asphalt"])
	var along_x := sx >= sz
	var len := sx if along_x else sz
	var n := int(len / 7.0)
	for k in n:
		var t := (float(k) + 0.5) * 7.0 - len * 0.5
		if along_x:
			_place_box(w, cx + t, GROUND_TOP + 0.012, cz, 3.0, 0.02, 0.3, _mats["conc_dark"])
		else:
			_place_box(w, cx, GROUND_TOP + 0.012, cz + t, 0.3, 0.02, 3.0, _mats["conc_dark"])


## 沿 Z 走向的墙（x 固定）：door 为门洞区间（x 分量 < -900 = 整墙）；
## 门洞上方补楣（悬空 ≥DOOR_H 不挡走人不注册），每段独立注册障碍
func _wall_x(w, x: float, z0: float, z1: float, h: float, mat: StandardMaterial3D,
		door := Vector2(-999.0, -999.0)) -> void:
	if door.x > -900.0:
		var lint_h := h - DOOR_H
		if lint_h > 0.05:
			_place_box(w, x, DOOR_H + lint_h * 0.5, (door.x + door.y) * 0.5,
					WALL_T, lint_h, door.y - door.x, mat)
		for s in [[z0, door.x], [door.y, z1]]:
			if float(s[1]) - float(s[0]) < 0.1:
				continue
			_place_box(w, x, h * 0.5, (float(s[0]) + float(s[1])) * 0.5,
					WALL_T, h, float(s[1]) - float(s[0]), mat)
			_obstacle(w, x, (float(s[0]) + float(s[1])) * 0.5, WALL_T * 0.5,
					(float(s[1]) - float(s[0])) * 0.5, h)
	else:
		_place_box(w, x, h * 0.5, (z0 + z1) * 0.5, WALL_T, h, z1 - z0, mat)
		_obstacle(w, x, (z0 + z1) * 0.5, WALL_T * 0.5, (z1 - z0) * 0.5, h)


## 沿 X 走向的墙（z 固定）：同 _wall_x
func _wall_z(w, z: float, x0: float, x1: float, h: float, mat: StandardMaterial3D,
		door := Vector2(-999.0, -999.0)) -> void:
	if door.x > -900.0:
		var lint_h := h - DOOR_H
		if lint_h > 0.05:
			_place_box(w, (door.x + door.y) * 0.5, DOOR_H + lint_h * 0.5, z,
					door.y - door.x, lint_h, WALL_T, mat)
		for s in [[x0, door.x], [door.y, x1]]:
			if float(s[1]) - float(s[0]) < 0.1:
				continue
			_place_box(w, (float(s[0]) + float(s[1])) * 0.5, h * 0.5, z,
					float(s[1]) - float(s[0]), h, WALL_T, mat)
			_obstacle(w, (float(s[0]) + float(s[1])) * 0.5, z,
					(float(s[1]) - float(s[0])) * 0.5, WALL_T * 0.5, h)
	else:
		_place_box(w, (x0 + x1) * 0.5, h * 0.5, z, x1 - x0, h, WALL_T, mat)
		_obstacle(w, (x0 + x1) * 0.5, z, (x1 - x0) * 0.5, WALL_T * 0.5, h)


## 铁丝网围栏（拦人不拦高位弹道）：竖柱间隔 2.5 + 三道横杆 + 柱顶斜刺丝；
## 整段合并注册 1 条 FENCE_H 障碍（纯视觉网面先例——细件不逐柱注册）
func _fence_run(w, x0: float, z0: float, x1: float, z1: float) -> void:
	var len := Vector2(x1 - x0, z1 - z0).length()
	var n := int(len / 2.5) + 1
	var along_x := absf(x1 - x0) > absf(z1 - z0)
	for k in n:
		var t := float(k) / float(maxi(n - 1, 1))
		var px := lerpf(x0, x1, t)
		var pz := lerpf(z0, z1, t)
		_place_box(w, px, FENCE_H * 0.5, pz, 0.12, FENCE_H, 0.12, _mats["conc_dark"])
		_place_box(w, px, FENCE_H + 0.22, pz + 0.14, 0.05, 0.44, 0.05,
				_mats["conc_dark"], Vector3(0.7 if along_x else 0.0, 0.0,
				0.0 if along_x else 0.7))
	for ry in [0.4, 0.85, 1.2]:
		if along_x:
			_place_box(w, (x0 + x1) * 0.5, ry, z0, len, 0.07, 0.07, _mats["conc_dark"])
		else:
			_place_box(w, x0, ry, (z0 + z1) * 0.5, 0.07, 0.07, len, _mats["conc_dark"])
	_obstacle(w, (x0 + x1) * 0.5, (z0 + z1) * 0.5,
			absf(x1 - x0) * 0.5 + 0.1, absf(z1 - z0) * 0.5 + 0.1, FENCE_H)


## 水面（下沉明渠里的静水板，y=-0.85；两岸混凝土竖壁纯视觉、拦靠围栏）
func _water(w, cx: float, cz: float, sx: float, sz: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(sx, sz)
	pm.material = _mats["water"]
	mi.mesh = pm
	mi.position = Vector3(cx, -0.85, cz)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	# 两岸竖壁（沿长边各一）
	if sx >= sz:
		_place_box(w, cx, -0.45, cz - sz * 0.5 - 0.15, sx, 0.95, 0.3, _mats["conc_dark"])
		_place_box(w, cx, -0.45, cz + sz * 0.5 + 0.15, sx, 0.95, 0.3, _mats["conc_dark"])
	else:
		_place_box(w, cx - sx * 0.5 - 0.15, -0.45, cz, 0.3, 0.95, sz, _mats["conc_dark"])
		_place_box(w, cx + sx * 0.5 + 0.15, -0.45, cz, 0.3, 0.95, sz, _mats["conc_dark"])


## 带栏桥面（中控桥/西桥共用）：沥青面 + 两侧栏杆（拦人 1.15m）+ 水中墩
func _bridge(w, cx: float, cz: float, sx: float, sz: float) -> void:
	_place_box(w, cx, GROUND_TOP - 0.05, cz, sx, 0.14, sz, _mats["asphalt"])
	var along_x := sx >= sz
	for side in [-1.0, 1.0]:
		for k in 8:
			var t := (float(k) + 0.5) / 8.0 - 0.5
			if along_x:
				_place_box(w, cx + t * sx, RAIL_H * 0.5, cz + side * (sz * 0.5 - 0.1),
						0.1, RAIL_H, 0.1, _mats["pipe"])
			else:
				_place_box(w, cx + side * (sx * 0.5 - 0.1), RAIL_H * 0.5, cz + t * sz,
						0.1, RAIL_H, 0.1, _mats["pipe"])
		for ry in [0.5, 1.0]:
			if along_x:
				_place_box(w, cx, ry, cz + side * (sz * 0.5 - 0.1), sx, 0.07, 0.07, _mats["pipe"])
			else:
				_place_box(w, cx + side * (sx * 0.5 - 0.1), ry, cz, 0.07, 0.07, sz, _mats["pipe"])
		if along_x:
			_obstacle(w, cx, cz + side * (sz * 0.5 - 0.1), sx * 0.5, 0.12, RAIL_H)
		else:
			_obstacle(w, cx + side * (sx * 0.5 - 0.1), cz, 0.12, sz * 0.5, RAIL_H)
	# 水中墩（跨中两根，纯视觉沉在水里）
	if along_x:
		for px in [cx - sx * 0.22, cx + sx * 0.22]:
			_place_box(w, px, -0.5, cz, 1.2, 1.4, sz * 0.72, _mats["conc_dark"])
	else:
		for pz in [cz - sz * 0.22, cz + sz * 0.22]:
			_place_box(w, cx, -0.5, pz, sx * 0.72, 1.4, 1.2, _mats["conc_dark"])


## 实拍件点缀（枯树/巨石/箭筒树：GLB 缺失自动跳过）
func _prop_gltf(w, path: String, pos: Vector3, scl: Vector3, yaw: float) -> void:
	var ps: PackedScene = PBR.scene(path)
	if ps == null:
		return
	var inst: Node3D = ps.instantiate()
	inst.position = pos
	inst.scale = scl
	inst.rotation.y = yaw
	w.add_child(inst)


# ================= 水系 / 公路 / 管廊 =================

func _terrain(w) -> void:
	# —— 水道（东西向 z∈[-64,-54]，x∈[-58,44]；东端 x∈[36,44] 留涵洞路口）——
	_water(w, -7.0, -59.0, 100.0, 8.0)
	_fence_run(w, -58.0, -64.0, -6.0, -64.0)    # 北岸西段
	_fence_run(w, 6.0, -64.0, 36.0, -64.0)      # 北岸东段（x∈[-6,6] 桥口让空）
	_fence_run(w, -58.0, -54.0, -6.0, -54.0)    # 南岸西段
	_fence_run(w, 6.0, -54.0, 36.0, -54.0)      # 南岸东段
	# 涵洞路口（东路过渠）：铺装带 + 两侧导流墩
	_place_box(w, 41.0, GROUND_TOP - 0.05, -59.0, 8.0, 0.14, 12.0, _mats["plaza"])
	for side in [-1.0, 1.0]:
		_place_box(w, 44.6, 0.5, -59.0 + side * 6.2, 0.8, 1.0, 1.2, _mats["conc_dark"])
	# —— 西侧纵贯水渠（南北向 x∈[-58,-50]，z∈[-54,42]；z∈[-3,3] 西桥口让空）——
	_water(w, -54.0, -6.0, 7.0, 94.0)
	_fence_run(w, -58.4, -54.0, -58.4, -3.0)
	_fence_run(w, -58.4, 3.0, -58.4, 42.0)
	_fence_run(w, -49.6, -54.0, -49.6, -3.0)
	_fence_run(w, -49.6, 3.0, -49.6, 42.0)
	# —— 河湾（渠南端放宽潭 x∈[-66,-42]×z∈[42,64]）——
	_water(w, -54.0, 53.0, 22.0, 20.0)
	_fence_run(w, -66.4, 42.0, -66.4, 64.0)     # 湾西
	_fence_run(w, -66.4, 64.4, -41.6, 64.4)     # 湾南
	_fence_run(w, -41.6, 42.0, -41.6, 64.0)     # 湾东
	_fence_run(w, -66.0, 41.6, -58.4, 41.6)     # 湾北西连接（渠西壁→湾西）
	_fence_run(w, -49.6, 41.6, -41.6, 41.6)     # 湾北东连接（渠东壁→湾东）
	# —— 中控桥（x∈[-4.5,4.5]×z∈[-70,-36]，跨水道连核心区北门）——
	_bridge(w, 0.0, -53.0, 9.0, 34.0)
	# —— 西桥（x∈[-58,-50]×z∈[-3,3]，跨水渠连西路）——
	_bridge(w, -54.0, 0.0, 8.0, 6.0)
	# —— 四条公路（官方图核验：无跑道/铁路，运输靠公路）——
	_road(w, 0.0, -118.0, 8.0, 48.0)            # 北路：北出生点 → 中控楼北门
	_road(w, 0.0, 66.0, 8.0, 52.0)              # 南路（员工通道）：核心区南门 → 发射区北门
	_road(w, 51.0, 2.0, 14.0, 112.0)            # 东路：涵洞 → 工业带/罐装/试车
	_road(w, -121.0, -109.0, 34.0, 6.0)         # 宿舍路：西北出生点 → 停车场
	# —— 燃料管廊（罐装区 → 发射坪，L 形高架管排 + 支架）——
	for pz in [54.0, 62.0, 70.0, 78.0, 86.0]:
		_place_box(w, 59.5, 0.85, pz, 0.28, 1.7, 0.28, _mats["metal_dark"])
		_obstacle(w, 59.5, pz, 0.2, 0.2, 1.8)
	for px in [38.0, 46.0, 54.0]:
		_place_box(w, px, 0.85, 88.0, 0.28, 1.7, 0.28, _mats["metal_dark"])
		_obstacle(w, px, 88.0, 0.2, 0.2, 1.8)
	for py in [1.28, 1.52, 1.76]:
		_place_box(w, 59.5, py, 70.0, 0.24, 0.24, 36.0, _mats["pipe"])
		_place_box(w, 47.0, py, 88.0, 26.0, 0.24, 0.24, _mats["pipe"])
	_place_box(w, 59.5, 1.52, 88.0, 0.5, 0.5, 0.5, _mats["metal_dark"])   # 弯头


# ================= 核心区（围墙院：四室 + 总裁室 + 中心花园） =================

func _core(w) -> void:
	_pave(w, 0.0, 2.0, 74.0, 78.0)   # 院内硬化地坪
	# —— 围墙（h3.2：北门 x∈[-5,5] 对中控桥、南门 x∈[-4,4] 员工通道）——
	_wall_z(w, -36.0, -36.0, -5.0, 3.2, _mats["conc"])
	_wall_z(w, -36.0, 5.0, 36.0, 3.2, _mats["conc"])
	_wall_z(w, 40.0, -36.0, -4.0, 3.2, _mats["conc"])
	_wall_z(w, 40.0, 4.0, 36.0, 3.2, _mats["conc"])
	_wall_x(w, -36.0, -36.0, 40.0, 3.2, _mats["conc"])
	_wall_x(w, 36.0, -36.0, 40.0, 3.2, _mats["conc"])
	for corner in [[-36.0, -36.0], [36.0, -36.0], [-36.0, 40.0], [36.0, 40.0]]:
		_place_box(w, corner[0], 2.2, corner[1], 1.8, 4.4, 1.8, _mats["conc_dark"])
		_obstacle(w, corner[0], corner[1], 0.9, 0.9, 4.4)
	# 南门外警卫披屋（员工通道把口）
	for wz in [[44.0, 3.0], [42.5, 0.5]]:
		_place_box(w, 9.0, 1.5, wz[0], 4.0, 3.0, wz[1], _mats["conc"])
	_place_box(w, 11.0, 1.5, 43.0, 0.5, 3.0, 5.0, _mats["conc"])
	_obstacle(w, 9.0, 44.0, 2.0, 1.5, 3.0)
	_obstacle(w, 9.0, 42.5, 2.0, 0.25, 3.0)
	_obstacle(w, 11.0, 43.0, 0.25, 2.5, 3.0)
	_core_centrifuge(w)
	_core_buoyancy(w)
	_core_blue(w)
	_core_black(w)
	_core_ceo(w)
	_core_garden(w)
	_core_yard(w)


## 离心机室（西南 x∈[-33,-11]×z∈[-33,-10]，h9 工业试验大厅）
func _core_centrifuge(w) -> void:
	var mat: StandardMaterial3D = _mats["metal"]
	_wall_z(w, -33.0, -33.0, -11.0, 9.0, mat, Vector2(-27.0, -23.0))   # 北墙门洞
	_wall_z(w, -10.0, -33.0, -11.0, 9.0, mat)
	_wall_x(w, -33.0, -33.0, -10.0, 9.0, mat)
	_wall_x(w, -11.0, -33.0, -10.0, 9.0, mat, Vector2(-24.0, -20.0))   # 东墙门洞（朝西巷）
	# 离心机主机：大转子立筒 + 环形护罩 + 顶部传动箱
	_cyl(w, _mesh_tank, Vector3(-25.0, 3.5, -21.0), _mats["metal_dark"],
			Vector3(0.62, 0.64, 0.62))
	_obstacle(w, -25.0, -21.0, 2.7, 2.7, 7.2)
	_place_box(w, -25.0, 7.6, -21.0, 2.2, 1.1, 2.2, _mats["yellow"])
	for k in 8:   # 护罩散热竖筋
		var ang := TAU * float(k) / 8.0 + 0.4
		_place_box(w, -25.0 + cos(ang) * 2.75, 3.5, -21.0 + sin(ang) * 2.75,
				0.3, 6.8, 0.16, _mats["metal_dark"],
				Vector3(0.0, PI * 0.5 - ang, 0.0))
	# 控制台 ×2 + 检修平台 + 管线
	_place_box(w, -30.0, 0.55, -13.0, 1.0, 1.1, 3.4, _mats["conc_dark"])
	_place_box(w, -30.0, 0.55, -29.0, 1.0, 1.1, 3.4, _mats["conc_dark"])
	_obstacle(w, -30.0, -13.0, 0.5, 1.7, 1.1)
	_obstacle(w, -30.0, -29.0, 0.5, 1.7, 1.1)
	_place_box(w, -17.0, 0.75, -31.0, 5.0, 1.5, 2.4, _mats["metal_dark"])
	_obstacle(w, -17.0, -31.0, 2.5, 1.2, 1.5)
	for px in [-28.0, -22.0, -16.0]:
		_place_box(w, px, 5.6, -10.7, 4.6, 0.5, 0.5, _mats["pipe"])
	# 屋顶通风格 ×3 + 单坡檐口线
	for k in 3:
		_place_box(w, -28.0 + 8.0 * float(k), 9.3, -21.0, 2.4, 0.7, 2.4, _mats["metal_dark"])


## 浮力室（西北 x∈[-33,-11]×z∈[9,28]，h8：内有大落差深潜池）
func _core_buoyancy(w) -> void:
	var mat: StandardMaterial3D = _mats["metal"]
	_wall_z(w, 28.0, -33.0, -11.0, 8.0, mat)
	_wall_z(w, 9.0, -33.0, -11.0, 8.0, mat, Vector2(-27.0, -23.0))     # 南墙门洞
	_wall_x(w, -33.0, 9.0, 28.0, 8.0, mat)
	_wall_x(w, -11.0, 9.0, 28.0, 8.0, mat, Vector2(16.0, 20.0))        # 东墙门洞
	# 深潜池：下沉水面板 + 池缘护栏（东南角留梯口）+ 跳台
	_water(w, -22.0, 17.0, 13.0, 10.0)
	for seg in [[-28.5, -16.5, 11.6], [-28.5, -16.5, 23.4]]:
		_place_box(w, (seg[0] + seg[1]) * 0.5, 0.5, seg[2], seg[1] - seg[0], 1.0, 0.14,
				_mats["pipe"])
		_obstacle(w, (seg[0] + seg[1]) * 0.5, seg[2], (seg[1] - seg[0]) * 0.5, 0.1, 1.05)
	_place_box(w, -28.6, 0.5, 17.0, 0.14, 1.0, 11.8, _mats["pipe"])
	_obstacle(w, -28.6, 17.0, 0.1, 5.9, 1.05)
	_place_box(w, -17.0, 0.8, 20.0, 2.6, 0.2, 2.6, _mats["conc_dark"])  # 跳台
	_obstacle(w, -17.0, 20.0, 1.3, 1.3, 0.9)
	# 医疗货架 ×2（深潜池产医疗补给）
	_place_box(w, -31.5, 1.0, 25.5, 1.0, 2.0, 3.2, _mats["white"])
	_place_box(w, -13.0, 1.0, 11.5, 1.0, 2.0, 3.2, _mats["white"])
	_obstacle(w, -31.5, 25.5, 0.5, 1.6, 2.0)
	_obstacle(w, -13.0, 11.5, 0.5, 1.6, 2.0)
	# 二层指挥室挑台（bot=4.0：头顶可过人，高位弹道被挡）
	_place_box(w, -22.0, 4.2, 26.5, 20.0, 0.4, 3.0, _mats["conc_dark"])
	_obstacle(w, -22.0, 26.5, 10.0, 1.5, 4.4, 4.0)


## 蓝室（东北 x∈[11,33]×z∈[9,28]，h8：保险柜 + 下沉平台）
func _core_blue(w) -> void:
	var mat: StandardMaterial3D = _mats["metal"]
	_wall_z(w, 28.0, 11.0, 33.0, 8.0, mat)
	_wall_z(w, 9.0, 11.0, 33.0, 8.0, mat, Vector2(23.0, 27.0))         # 南墙门洞
	_wall_x(w, 11.0, 9.0, 28.0, 8.0, mat, Vector2(16.0, 20.0))         # 西墙门洞（朝东巷）
	_wall_x(w, 33.0, 9.0, 28.0, 8.0, mat)
	# 保险柜双层台阶台（下沉平台：两层 0.35 台阶 + 柜体）
	_place_box(w, 28.0, 0.18, 13.0, 8.0, 0.35, 6.0, _mats["conc_dark"])
	_place_box(w, 28.0, 0.53, 14.5, 5.0, 0.35, 3.0, _mats["conc_dark"])
	_place_box(w, 30.0, 1.35, 13.5, 2.2, 1.7, 1.2, _mats["metal_dark"])
	_obstacle(w, 30.0, 13.5, 1.1, 0.6, 2.2)
	# 服务器机柜列 ×3 + 蓝色玻璃隔断
	for k in 3:
		var mx := 15.0 + 2.2 * float(k)
		_place_box(w, mx, 1.1, 26.0, 1.4, 2.2, 0.9, _mats["conc_dark"])
		_place_box(w, mx, 1.9, 26.5, 1.2, 0.3, 0.06, _mats["glass"])
		_obstacle(w, mx, 26.0, 0.7, 0.45, 2.2)
	_place_box(w, 22.0, 1.6, 9.6, 10.0, 3.2, 0.12, _mats["glass"])


## 黑室（东南 x∈[11,33]×z∈[-33,-10]，h8：航空储物箱 + 左侧楼梯上二层）
func _core_black(w) -> void:
	var mat: StandardMaterial3D = _mats["metal"]
	_wall_z(w, -10.0, 11.0, 33.0, 8.0, mat, Vector2(23.0, 27.0))       # 北墙门洞
	_wall_z(w, -33.0, 11.0, 33.0, 8.0, mat)
	_wall_x(w, 11.0, -33.0, -10.0, 8.0, mat, Vector2(-24.0, -20.0))    # 西墙门洞
	_wall_x(w, 33.0, -33.0, -10.0, 8.0, mat)
	# 航空储物箱 ×3（圆角集装箱语汇：黄/灰/绿）+ 小保险箱
	for k in 3:
		var cx := 30.0
		var cz := -30.0 + 3.2 * float(k)
		_place_box(w, cx, 1.15, cz, 2.4, 2.3, 2.6,
				_mats["yellow"] if k == 0 else (_mats["metal_dark"] if k == 1 else _mats["green"]))
		_place_box(w, cx, 2.45, cz, 2.6, 0.2, 2.8, _mats["conc_dark"])
		_obstacle(w, cx, cz, 1.3, 1.4, 2.5)
	_place_box(w, 14.0, 0.55, -12.5, 1.4, 1.1, 1.0, _mats["metal_dark"])
	_obstacle(w, 14.0, -12.5, 0.7, 0.5, 1.1)
	# 左侧楼梯（视觉踏步贴西墙）+ 二层货架挑台
	for k in 8:
		_place_box(w, 12.6, 0.14 + 0.28 * float(k), -28.0 + 0.7 * float(k),
				2.2, 0.28, 0.7, _mats["conc_dark"])
	_place_box(w, 14.0, 4.2, -14.0, 5.0, 0.4, 8.0, _mats["conc_dark"])
	_obstacle(w, 14.0, -14.0, 2.5, 4.0, 4.4, 4.0)
	# 备件货架 ×2
	for rx in [30.5, 27.0]:
		_place_box(w, rx, 1.0, -14.0, 1.0, 2.0, 4.0, _mats["rust"])
		_obstacle(w, rx, -14.0, 0.5, 2.0, 2.0)


## 总裁室（正中 x∈[-8,8]×z∈[-6,6]，h16 四层悬空塔——全区制高）
func _core_ceo(w) -> void:
	var mat: StandardMaterial3D = _mats["conc"]
	_wall_z(w, -6.0, -8.0, 8.0, 16.0, mat)
	_wall_z(w, 6.0, -8.0, 8.0, 16.0, mat)
	_wall_x(w, -8.0, -6.0, 6.0, 16.0, mat, Vector2(-2.0, 2.0))         # 西门（朝西巷）
	_wall_x(w, 8.0, -6.0, 6.0, 16.0, mat, Vector2(-2.0, 2.0))          # 东门（朝东巷）
	# 四层窗带（每层暗色横带 + 白色窗棂）——「四层悬空」的立面对位
	for k in 4:
		var wy := 2.9 + 3.4 * float(k)
		for fz in [-6.3, 6.3]:
			_place_box(w, 0.0, wy, fz, 14.0, 1.7, 0.14, _mats["conc_dark"])
		for fx in [-8.3, 8.3]:
			_place_box(w, fx, wy, 0.0, 0.14, 1.7, 10.0, _mats["conc_dark"])
	# 顶层层退台 + 屋顶天线 + 四角结构柱
	_place_box(w, 0.0, 16.3, 0.0, 12.0, 0.6, 10.0, _mats["conc_dark"])
	_cyl(w, _mesh_mast, Vector3(0.0, 22.0, 0.0), _mats["pipe"], Vector3(1.2, 1.1, 1.2))
	for corner in [[-6.5, -4.5], [6.5, -4.5], [-6.5, 4.5], [6.5, 4.5]]:
		_place_box(w, corner[0], 8.0, corner[1], 0.7, 16.0, 0.7, mat)
		_obstacle(w, corner[0], corner[1], 0.35, 0.35, 16.0)
	# 大班台 + 会客沙发组
	_place_box(w, 0.0, 0.4, 3.2, 3.2, 0.8, 1.4, _mats["conc_dark"])
	_obstacle(w, 0.0, 3.2, 1.6, 0.7, 0.8)
	for side in [-1.0, 1.0]:
		_place_box(w, side * 4.5, 0.45, -3.4, 1.2, 0.9, 2.6, _mats["green"])


## 中心花园（院南 z∈[28,38] 下沉广场：铺装 + 树池 + 凉亭）
func _core_garden(w) -> void:
	_place_box(w, 0.0, -0.16, 33.0, 66.0, 0.34, 9.0, _mats["plaza"])   # 下沉 0.2 台阶面
	for side in [-1.0, 1.0]:
		_place_box(w, side * 33.0, 0.05, 33.0, 2.0, 0.14, 9.4, _mats["conc_dark"])
	for tp in [[-26.0, 31.0], [-13.0, 35.5], [13.0, 35.5], [26.0, 31.0]]:
		_cyl(w, _mesh_tank, Vector3(tp[0], 0.35, tp[1]), _mats["conc_dark"],
				Vector3(0.42, 0.08, 0.42))
		_prop_gltf(w, QUIVER_GLB, Vector3(tp[0], 0.3, tp[1]), Vector3.ONE * 2.2,
				tp[0] * 0.31)
	# 凉亭（四柱 + 攒尖顶）
	for corner in [[-1.6, -1.6], [1.6, -1.6], [-1.6, 1.6], [1.6, 1.6]]:
		_place_box(w, 6.0 + corner[0], 1.3, 31.0 + corner[1], 0.3, 2.6, 0.3, _mats["white"])
	_place_box(w, 6.0, 2.85, 31.0, 4.6, 0.5, 4.6, _mats["conc_dark"])
	_place_box(w, 6.0, 3.35, 31.0, 3.0, 0.5, 3.0, _mats["white"])
	_obstacle(w, 6.0, 31.0, 2.1, 2.1, 3.1)
	# 花池矮墙 ×4（<1m 只挡低位弹道）
	for gp in [[-16.0, 30.0], [16.0, 30.0], [-16.0, 36.0], [16.0, 36.0]]:
		_place_box(w, gp[0], 0.3, gp[1], 4.0, 0.6, 1.0, _mats["conc"])
		_obstacle(w, gp[0], gp[1], 2.0, 0.5, 0.6)
	for lp in [[-8.0, 36.5], [8.0, 36.5]]:   # 庭院灯 ×2
		_place_box(w, lp[0], 1.6, lp[1], 0.14, 3.2, 0.14, _mats["conc_dark"])
		_place_box(w, lp[0], 3.3, lp[1], 0.5, 0.3, 0.5, _mats["lamp"])


## 院巷陈设（南院集装箱 + 巷内沙袋/油桶——掩体语汇）
func _core_yard(w) -> void:
	# 南院（离心机/黑室间）：航空集装箱 ×2 + 油桶组
	for k in 2:
		var cx := -8.0 + 16.0 * float(k)
		_place_box(w, cx, 1.3, -31.0, 2.46, 2.59, 6.12,
				_mats["green"] if k == 0 else _mats["rust"])
		_obstacle(w, cx, -31.0, 1.3, 3.1, 2.6)
	for k in 3:
		_place_box(w, -1.2 + 0.9 * float(k), 0.46, -13.0, 0.6, 0.92, 0.61, _mats["rust"])
	_obstacle(w, 0.0, -13.0, 1.6, 0.6, 0.95)
	# 北院（浮力室/蓝室间）：沙袋墙 + 检修架
	for k in 5:
		_place_box(w, -3.0 + 1.3 * float(k), 0.35 + 0.35 * float(k % 2), 12.0,
				1.2, 0.6, 0.7, _mats["sand"])
	_obstacle(w, 0.0, 12.0, 3.4, 0.5, 1.0)
	_place_box(w, 6.0, 1.0, 21.0, 2.6, 2.0, 1.4, _mats["metal_dark"])
	_obstacle(w, 6.0, 21.0, 1.3, 0.7, 2.0)
	# 东西巷管线廊（低架管排，纯视觉）
	for px in [-24.0, -18.0, 18.0, 24.0]:
		_place_box(w, px, 0.9, 0.0, 0.2, 0.2, 14.0, _mats["pipe"])


# ================= 中控楼（北部控制点） =================

func _control(w) -> void:
	_pave(w, 0.0, -81.0, 34.0, 28.0)
	var mat: StandardMaterial3D = _mats["conc"]
	_wall_z(w, -92.0, -14.0, 14.0, 13.0, mat, Vector2(-3.0, 3.0))      # 北门（朝北路/出生侧）
	_wall_z(w, -70.0, -14.0, 14.0, 13.0, mat, Vector2(-3.0, 3.0))      # 南门（朝中控桥）
	_wall_x(w, -14.0, -92.0, -70.0, 13.0, mat)
	_wall_x(w, 14.0, -92.0, -70.0, 13.0, mat)
	# 三层窗带（东西立面成排横带 + 竖棂）
	for k in 3:
		var wy := 3.4 + 3.8 * float(k)
		for fx in [-14.3, 14.3]:
			_place_box(w, fx, wy, -81.0, 0.14, 2.2, 18.0, _mats["conc_dark"])
			for j in 5:
				_place_box(w, fx + (0.06 if fx < 0.0 else -0.06), wy, -88.0 + 3.6 * float(j),
						0.06, 2.2, 0.24, _mats["white"])
	# 屋顶女儿墙 + 天线阵（通讯设施：主桅杆 + 双副杆 + 雷达碟）
	_place_box(w, 0.0, 13.3, -81.0, 28.6, 0.6, 22.6, _mats["conc_dark"])
	_place_box(w, 0.0, 16.6, -81.0, 1.0, 6.0, 1.0, _mats["pipe"])
	_obstacle(w, 0.0, -81.0, 0.55, 0.55, 20.0)
	for ax in [-8.0, 8.0]:
		_cyl(w, _mesh_mast, Vector3(ax, 19.0, -86.0), _mats["pipe"],
				Vector3(0.6, 1.6, 0.6))
	_place_box(w, 5.0, 18.0, -76.0, 0.2, 2.6, 2.6, _mats["white"],
			Vector3(0.0, 0.7, 0.5))   # 雷达碟示意
	for wx in [-6.0, 6.0]:
		_place_box(w, wx, 19.4, -86.0, 3.0, 0.08, 0.08, _mats["pipe"])
	# 指挥厅：控制台马蹄形 ×3 合并 + 中层挑台（bot 4.2 头顶通行）
	for k in 3:
		_place_box(w, -6.0 + 6.0 * float(k), 0.55, -89.0, 3.0, 1.1, 1.2, _mats["conc_dark"])
		_place_box(w, -6.0 + 6.0 * float(k), 1.2, -89.4, 3.0, 0.16, 0.3, _mats["glass"])
		_obstacle(w, -6.0 + 6.0 * float(k), -89.0, 1.5, 0.6, 1.1)
	for corner in [[-8.0, -81.0], [8.0, -81.0]]:
		_place_box(w, corner[0], 6.5, corner[1], 0.6, 13.0, 0.6, mat)
		_obstacle(w, corner[0], corner[1], 0.3, 0.3, 13.0)
	_place_box(w, 0.0, 4.4, -74.0, 22.0, 0.4, 3.0, _mats["conc_dark"])
	_obstacle(w, 0.0, -74.0, 11.0, 1.5, 4.6, 4.2)
	# 门口坡道 + 警卫亭（北门外主撤离侧）
	_place_box(w, 0.0, 0.08, -93.4, 7.0, 0.16, 2.8, _mats["conc_dark"])
	_place_box(w, 10.0, 1.4, -95.0, 2.6, 2.8, 2.6, _mats["green"])
	_obstacle(w, 10.0, -95.0, 1.3, 1.3, 2.8)


# ================= 工业区（东侧：总装主厂房 + 打印室 + 组装室） =================

func _industrial(w) -> void:
	_pave(w, 82.0, -20.0, 58.0, 44.0)
	_plant(w)
	_print_shop(w)
	_assembly(w)


## 总装主厂房（x∈[58,106]×z∈[-58,-18]，h12：含吊装跨/流水线）
func _plant(w) -> void:
	var mat: StandardMaterial3D = _mats["metal"]
	# 西墙：双卷帘门 z∈[-50,-42]/[-34,-26]（半开卷帘片 + 红门楣）
	_wall_x(w, 58.0, -58.0, -50.0, 12.0, mat)
	_wall_x(w, 58.0, -42.0, -34.0, 12.0, mat)
	_wall_x(w, 58.0, -26.0, -18.0, 12.0, mat)
	for dz in [-46.0, -30.0]:
		_place_box(w, 58.3, 4.6, dz, 0.24, 6.8, 8.0, mat)
		_place_box(w, 58.2, 3.0, dz, 0.16, 3.4, 7.6, _mats["conc_dark"])
		_place_box(w, 58.5, 8.9, dz, 0.3, 0.6, 8.4, _mats["red"])
		_place_box(w, 58.2, 1.1, dz, 0.1, 2.2, 7.6, _mats["conc_dark"])
	_wall_z(w, -58.0, 58.0, 106.0, 12.0, mat, Vector2(78.0, 86.0))      # 北墙门洞
	_wall_x(w, 106.0, -58.0, -18.0, 12.0, mat, Vector2(-40.0, -36.0))  # 东墙人员门
	_wall_z(w, -18.0, 58.0, 106.0, 12.0, mat, Vector2(76.0, 84.0))     # 南墙门洞（服务巷）
	# 屋顶：双坡 monitor 屋面 + 成排通风器
	for side in [-1.0, 1.0]:
		_place_box(w, 82.0, 12.6, -38.0 + side * 10.0, 48.6, 0.5, 20.0, _mats["metal_dark"],
				Vector3(0.14 * side, 0.0, 0.0))
	_place_box(w, 82.0, 14.0, -38.0, 26.0, 1.6, 10.0, _mats["conc_dark"])
	for k in 5:
		_place_box(w, 64.0 + 9.0 * float(k), 13.2, -30.0, 2.6, 0.8, 2.6, _mats["conc_dark"])
	# 流水线：全线设备基座 ×5（传送带体纯视觉）+ 南跨机床 ×4
	for k in 5:
		var px := 66.0 + 8.0 * float(k)
		_place_box(w, px, 0.65, -49.0, 2.2, 1.3, 2.2, _mats["yellow"])
		_place_box(w, px, 1.36, -49.0, 2.0, 0.14, 6.0, _mats["conc_dark"])
		_obstacle(w, px, -49.0, 1.1, 1.1, 1.3)
	for k in 4:
		var mx := 66.0 + 8.0 * float(k if k < 2 else k + 1)   # 让开 x=82 首领把口
		_place_box(w, mx, 0.9, -24.0, 2.4, 1.8, 1.6, _mats["metal_dark"])
		_obstacle(w, mx, -24.0, 1.2, 0.8, 1.8)
	_place_box(w, 82.0, 1.0, -49.0, 44.0, 0.16, 1.2, _mats["pipe"])
	# 吊装跨：桥式吊车梁 + 四立柱 + 吊钩组（吊装室语汇并入主厂房跨间）
	for corner in [[66.0, -52.0], [66.0, -28.0], [98.0, -52.0], [98.0, -28.0]]:
		_place_box(w, corner[0], 6.0, corner[1], 0.7, 12.0, 0.7, _mats["rust"])
		_obstacle(w, corner[0], corner[1], 0.35, 0.35, 12.0)
	for rz in [-52.0, -28.0]:
		_place_box(w, 82.0, 10.8, rz, 34.0, 0.8, 0.8, _mats["rust"])
	_place_box(w, 82.0, 10.2, -40.0, 1.4, 0.5, 24.0, _mats["rust"])
	_place_box(w, 82.0, 9.2, -40.0, 1.0, 1.6, 1.0, _mats["metal_dark"])
	# 零件架 ×4（北墙根）+ 检修件堆 ×2
	for k in 4:
		var rx := 64.0 + 10.0 * float(k)
		_place_box(w, rx, 1.0, -56.0, 3.0, 2.0, 1.0, _mats["rust"])
		_obstacle(w, rx, -56.0, 1.5, 0.5, 2.0)
	for k in 2:
		_place_box(w, 60.5 + 3.0 * float(k), 0.5, -20.5, 1.6, 1.0, 1.6, _mats["yellow"])
		_obstacle(w, 60.5 + 3.0 * float(k), -20.5, 0.8, 0.8, 1.0)


## 打印室（x∈[58,84]×z∈[-12,6]，h7：3D 打印工坊）
func _print_shop(w) -> void:
	var mat: StandardMaterial3D = _mats["yellow"]
	_wall_x(w, 58.0, -12.0, 6.0, 7.0, mat, Vector2(-6.0, -2.0))        # 西门
	_wall_z(w, -12.0, 58.0, 84.0, 7.0, mat)
	_wall_x(w, 84.0, -12.0, 6.0, 7.0, mat)
	_wall_z(w, 6.0, 58.0, 84.0, 7.0, mat)
	# 大型打印舱 ×3（玻璃罩壳 + 内部成型柱）+ 耗材架 ×2
	for k in 3:
		var px := 63.0 + 8.0 * float(k)
		_place_box(w, px, 1.5, -8.0, 3.2, 3.0, 3.0, _mats["metal_dark"])
		_place_box(w, px, 2.2, -6.4, 2.4, 1.6, 0.1, _mats["glass"])
		_place_box(w, px, 3.2, -8.0, 3.4, 0.5, 3.4, _mats["conc_dark"])
		_obstacle(w, px, -8.0, 1.6, 1.5, 3.3)
	for k in 2:
		_place_box(w, 62.0 + 6.0 * float(k), 1.0, 2.0, 1.0, 2.0, 3.6, _mats["metal_dark"])
		_obstacle(w, 62.0 + 6.0 * float(k), 2.0, 0.5, 1.8, 2.0)
	# 屋顶空调机组 + 排风管
	_place_box(w, 71.0, 7.3, -3.0, 3.0, 0.7, 2.0, _mats["white"])
	_place_box(w, 78.0, 7.4, -3.0, 0.8, 1.0, 0.8, _mats["pipe"])


## 组装室（x∈[88,114]×z∈[-12,12]，h8：部装工位）
func _assembly(w) -> void:
	var mat: StandardMaterial3D = _mats["metal"]
	_wall_x(w, 88.0, -12.0, 12.0, 8.0, mat, Vector2(-2.0, 2.0))        # 西门（朝服务巷）
	_wall_z(w, -12.0, 88.0, 114.0, 8.0, mat)
	_wall_x(w, 114.0, -12.0, 12.0, 8.0, mat)
	_wall_z(w, 12.0, 88.0, 114.0, 8.0, mat)
	# 装配台 ×4（北墙根）+ 部件箱 ×2
	for k in 4:
		var px := 92.0 + 6.0 * float(k)
		_place_box(w, px, 0.5, -9.5, 4.0, 1.0, 1.6, _mats["conc_dark"])
		_place_box(w, px, 1.06, -9.5, 3.4, 0.12, 1.0, _mats["yellow"])
		_obstacle(w, px, -9.5, 2.0, 0.8, 1.0)
	for k in 2:
		_place_box(w, 110.0, 0.7, -2.0 + 4.0 * float(k), 1.8, 1.4, 1.8, _mats["yellow"])
		_obstacle(w, 110.0, -2.0 + 4.0 * float(k), 0.9, 0.9, 1.4)
	# 桁架照明梁 + 屋顶单元
	for k in 3:
		_place_box(w, 101.0, 7.6, -8.0 + 8.0 * float(k), 24.0, 0.4, 0.4, _mats["rust"])
		_place_box(w, 101.0, 7.3, -8.0 + 8.0 * float(k), 3.0, 0.3, 0.6, _mats["lamp"])
	# 东侧场院：运货卡车 + 托盘堆（与东路衔接）
	_place_box(w, 118.5, 1.5, -26.0, 2.2, 1.8, 5.6, _mats["rust"])
	_place_box(w, 121.6, 1.1, -26.0, 1.6, 1.6, 4.6, _mats["green"])
	_obstacle(w, 120.0, -26.0, 2.6, 3.2, 2.4)


# ================= 罐装区（燃料储罐群 + 泵房） =================

func _tankfarm(w) -> void:
	_pave(w, 84.0, 40.0, 50.0, 32.0)
	# 立式储罐 ×6（两排三列 r4.2 h11 + 顶护栏 + 挂梯 + 锈带）
	for tz in [34.0, 46.0]:
		for tx in [70.0, 84.0, 98.0]:
			_cyl(w, _mesh_tank, Vector3(tx, 5.5, tz), _mats["tank"])
			_obstacle(w, tx, tz, 4.2, 4.2, 11.0)
			for k in 10:   # 罐壁竖筋
				var ang := TAU * float(k) / 10.0 + 0.3
				_place_box(w, tx + cos(ang) * 4.25, 5.5, tz + sin(ang) * 4.25,
						0.34, 10.4, 0.16, _mats["conc_dark"],
						Vector3(0.0, PI * 0.5 - ang, 0.0))
			_cyl(w, _mesh_sphere, Vector3(tx, 11.3, tz), _mats["tank"],
					Vector3(4.0, 0.9, 4.0))   # 罐顶弧盖
			_place_box(w, tx + 4.3, 5.0, tz, 0.16, 9.0, 0.7, _mats["rust"])   # 挂梯
			_place_box(w, tx - 2.0, 2.2, tz, 0.5, 3.2, 0.08, _mats["rust"])   # 锈渍流挂
	# 罐间连接管排（南北向跨接，纯视觉）
	for tx in [70.0, 84.0, 98.0]:
		_place_box(w, tx, 2.2, 40.0, 0.34, 0.34, 7.6, _mats["pipe"])
		_place_box(w, tx, 2.2, 40.0, 0.5, 0.5, 0.5, _mats["metal_dark"])
	# 围堰矮墙（h0.8 只挡低位弹道，人可跨）×4
	_place_box(w, 84.0, 0.4, 27.5, 50.0, 0.8, 0.4, _mats["conc"])
	_place_box(w, 84.0, 0.4, 52.5, 50.0, 0.8, 0.4, _mats["conc"])
	_place_box(w, 63.5, 0.4, 40.0, 0.4, 0.8, 25.0, _mats["conc"])
	_place_box(w, 104.5, 0.4, 40.0, 0.4, 0.8, 25.0, _mats["conc"])
	_obstacle(w, 84.0, 27.5, 25.0, 0.2, 0.8)
	_obstacle(w, 84.0, 52.5, 25.0, 0.2, 0.8)
	_obstacle(w, 63.5, 40.0, 0.2, 12.5, 0.8)
	_obstacle(w, 104.5, 40.0, 0.2, 12.5, 0.8)
	# 泵房（x∈[56,70]×z∈[18,24]，h4.5：罐区北口）+ 泵组 ×2
	var mat: StandardMaterial3D = _mats["yellow"]
	_wall_z(w, 24.0, 56.0, 70.0, 4.5, mat)
	_wall_z(w, 18.0, 56.0, 70.0, 4.5, mat)
	_wall_x(w, 56.0, 18.0, 24.0, 4.5, mat)
	_wall_x(w, 70.0, 18.0, 24.0, 4.5, mat, Vector2(21.0, 23.0))        # 东门
	for k in 2:
		var px := 60.5 + 4.5 * float(k)
		_place_box(w, px, 0.8, 21.0, 2.4, 1.6, 1.6, _mats["metal_dark"])
		_place_box(w, px, 1.75, 21.0, 0.4, 0.5, 0.4, _mats["pipe"])
		_obstacle(w, px, 21.0, 1.2, 0.8, 1.8)
	_place_box(w, 63.0, 4.8, 21.0, 14.6, 0.4, 6.6, _mats["conc_dark"])


# ================= 水平试车场（东南长条测试综合体） =================

func _teststand(w) -> void:
	_pave(w, 86.0, 74.0, 44.0, 28.0)
	var mat: StandardMaterial3D = _mats["metal"]
	# 测试主厂房（x∈[66,106]×z∈[62,86]，h11；西/北/东/南四门）
	_wall_x(w, 66.0, 62.0, 72.0, 11.0, mat)                             # 西墙（中控室段）
	_wall_x(w, 66.0, 72.0, 86.0, 11.0, mat, Vector2(72.0, 80.0))        # 西大门 z∈[72,80]
	_wall_z(w, 62.0, 66.0, 106.0, 11.0, mat, Vector2(86.0, 90.0))       # 北门
	_wall_x(w, 106.0, 62.0, 70.0, 11.0, mat)
	_wall_x(w, 106.0, 70.0, 86.0, 11.0, mat, Vector2(70.0, 78.0))       # 东大门 z∈[70,78]
	_place_box(w, 106.4, 6.4, 74.0, 0.24, 8.4, 8.0, mat)
	_place_box(w, 106.3, 4.2, 74.0, 0.16, 4.0, 7.6, _mats["conc_dark"])
	_place_box(w, 106.6, 8.1, 74.0, 0.3, 0.6, 8.4, _mats["red"])
	_wall_z(w, 86.0, 66.0, 106.0, 11.0, mat, Vector2(98.0, 102.0))      # 南墙尾门 x∈[98,102]
	_place_box(w, 100.0, 5.4, 86.4, 4.0, 4.4, 0.24, mat)                # 尾门楣（下拉半开）
	_place_box(w, 100.0, 2.2, 86.3, 3.6, 3.2, 0.12, _mats["conc_dark"])
	_place_box(w, 100.0, 7.2, 86.0, 4.4, 0.7, 0.7, _mats["red"])
	_place_box(w, 100.0, 0.06, 90.0, 4.0, 0.12, 6.0, _mats["plaza"])    # 尾门外撤出坪
	# 中控室（x∈[66,76]×z∈[62,70]：南/东内墙开门，电闸在室内 (70,66)）
	_wall_x(w, 76.0, 62.0, 64.0, 3.4, _mats["conc"])
	_wall_x(w, 76.0, 64.0, 70.0, 3.4, _mats["conc"], Vector2(64.0, 68.0))
	_wall_z(w, 70.0, 66.0, 76.0, 3.4, _mats["conc"], Vector2(68.0, 72.0))
	_place_box(w, 71.0, 4.2, 66.0, 10.6, 0.4, 8.6, _mats["conc_dark"])
	# 试车台：主机试车墩 + 推力偏导器 + 燃料橇 ×2
	_place_box(w, 88.0, 1.4, 74.0, 6.0, 2.8, 4.0, _mats["conc_dark"])
	_obstacle(w, 88.0, 74.0, 3.0, 2.0, 2.8)
	_place_box(w, 88.0, 1.5, 80.5, 6.0, 3.0, 2.2, _mats["rust"], Vector3(0.5, 0.0, 0.0))
	_obstacle(w, 88.0, 80.5, 3.0, 1.3, 3.0)
	for k in 2:
		var px := 96.0
		var pz := 66.0 + 6.0 * float(k)
		_place_box(w, px, 0.9, pz, 2.6, 1.8, 1.6, _mats["metal_dark"])
		_obstacle(w, px, pz, 1.3, 0.8, 1.8)
	# 屋顶：纵向monitor高侧窗 + 排热风筒 ×3
	for side in [-1.0, 1.0]:
		_place_box(w, 86.0, 11.5, 74.0 + side * 9.0, 40.6, 0.4, 8.0, _mats["metal_dark"],
				Vector3(0.0, 0.0, 0.16 * side))
	for k in 3:
		_place_box(w, 74.0 + 12.0 * float(k), 12.2, 74.0, 2.0, 1.4, 2.0, _mats["rust"])
	# 西端消音塔（发动机试车排气消声器：粗圆塔 r2.5 h14）
	_cyl(w, _mesh_tank, Vector3(62.5, 7.0, 78.0), _mats["rust"], Vector3(0.6, 1.27, 0.6))
	_obstacle(w, 62.5, 78.0, 2.5, 2.5, 14.0)
	for k in 6:
		var ang := TAU * float(k) / 6.0
		_place_box(w, 62.5 + cos(ang) * 2.5, 12.5, 78.0 + sin(ang) * 2.5,
				0.7, 2.6, 0.2, _mats["conc_dark"], Vector3(0.0, PI * 0.5 - ang, 0.0))


# ================= 宿舍区（西北：3 栋两层楼 + 中庭 + 停车场） =================

func _dorm(w) -> void:
	_pave(w, -84.0, -78.0, 46.0, 40.0)
	_dorm_building(w, -92.0, -89.0, "A")   # 宿舍A：x∈[-102,-82]×z∈[-94,-84]
	_dorm_building(w, -92.0, -71.0, "B")   # 宿舍B：x∈[-102,-82]×z∈[-76,-66]
	_dorm_building(w, -70.0, -85.0, "C")   # 宿舍C：x∈[-78,-62]×z∈[-90,-80]
	# —— 中庭（A/B 楼间 z∈[-84,-76]）：晾衣绳柱 + 花池 + 水塔 ——
	for k in 3:
		_place_box(w, -96.0 + 6.0 * float(k), 1.1, -80.0, 0.14, 2.2, 0.14, _mats["conc_dark"])
		_place_box(w, -96.0 + 6.0 * float(k), 2.15, -80.0, 2.2, 0.06, 0.06, _mats["white"])
	for gp in [[-98.0, -77.0], [-86.0, -83.0]]:
		_place_box(w, gp[0], 0.3, gp[1], 3.0, 0.6, 1.2, _mats["conc"])
		_obstacle(w, gp[0], gp[1], 1.5, 0.6, 0.6)
	_cyl(w, _mesh_tank, Vector3(-66.0, 4.0, -72.0), _mats["tank"], Vector3(0.7, 0.8, 0.7))
	_place_box(w, -66.0, 8.4, -72.0, 3.2, 0.8, 3.2, _mats["conc_dark"])
	for k in 4:   # 水塔四腿
		var ang := TAU * float(k) / 4.0 + 0.79
		_place_box(w, -66.0 + cos(ang) * 1.8, 2.0, -72.0 + sin(ang) * 1.8,
				0.18, 4.0, 0.18, _mats["metal_dark"])
	_obstacle(w, -66.0, -72.0, 2.2, 2.2, 8.8)
	# —— 停车场（x∈[-120,-106]×z∈[-88,-64]：划线 + 残车 ×3 + 西围栏留门）——
	_pave(w, -113.0, -76.0, 14.0, 24.0)
	for k in 4:
		_place_box(w, -119.0 + 3.4 * float(k), GROUND_TOP + 0.012, -76.0,
				0.16, 0.02, 22.0, _mats["white"])
	for cz in [[-114.0, -84.0], [-110.0, -76.0], [-116.0, -68.0]]:
		_place_box(w, cz[0], 0.7, cz[1], 1.9, 1.3, 4.3, _mats["conc_dark"])
		_place_box(w, cz[0] + 0.9, 1.6, cz[1], 0.8, 0.5, 1.9, _mats["rust"])
		_obstacle(w, cz[0], cz[1], 1.1, 2.2, 1.5)
	_fence_run(w, -120.4, -88.0, -120.4, -78.0)
	_fence_run(w, -120.4, -72.0, -120.4, -64.0)
	for gz in [-78.0, -72.0]:   # 西门双柱（常开撤离口）
		_place_box(w, -120.4, 1.55, gz, 0.3, 3.1, 0.3, _mats["conc_dark"])
	for lp in [[-110.0, -86.0], [-110.0, -66.0]]:   # 场灯 ×2
		_place_box(w, lp[0], 2.3, lp[1], 0.16, 4.6, 0.16, _mats["conc_dark"])
		_place_box(w, lp[0], 4.75, lp[1], 0.7, 0.3, 0.7, _mats["lamp"])


## 两层宿舍楼（20×10 h6.4：南门 + 内隔墙 + 双坡顶 + 二层阳台栏）
func _dorm_building(w, cx: float, cz: float, _tag: String) -> void:
	var mat: StandardMaterial3D = _mats["green"]
	var x0 := cx - 10.0
	var x1 := cx + 10.0
	var z0 := cz - 5.0
	var z1 := cz + 5.0
	var h := 6.4
	_wall_z(w, z0, x0, x1, h, mat)
	_wall_z(w, z1, x0, x1, h, mat)
	_wall_x(w, x0, z0, z1, h, mat)
	_wall_x(w, x1, z0, z1, h, mat, Vector2(cz - 1.0, cz + 1.0))        # 东门（朝院内）
	_place_box(w, x1 + 0.06, 1.75, cz, 0.16, 3.5, 2.4, _mats["white"])
	# 内隔墙（分两户）+ 楼梯踏步（视觉）
	_place_box(w, cx, h * 0.5, cz, WALL_T, h, 9.0, mat)
	_obstacle(w, cx, cz, WALL_T * 0.5, 4.5, h)
	for k in 10:
		_place_box(w, cx - 4.0 + 0.3 * float(k), 0.1 + 0.28 * float(k), z1 - 1.2,
				0.3, 0.28, 1.4, _mats["conc_dark"])
	# 二层窗带（四面）+ 南面阳台栏
	for fz in [z0 - 0.09, z1 + 0.09]:
		_place_box(w, cx, 4.3, fz, 18.0, 1.4, 0.14, _mats["conc_dark"])
		for k in 5:
			_place_box(w, x0 + 2.0 + 3.5 * float(k), 4.3, fz + (0.05 if fz > 0.0 else -0.05),
					0.16, 1.4, 0.1, _mats["white"])
	_place_box(w, cx, 3.35, z1 + 0.7, 18.6, 0.1, 1.0, _mats["conc_dark"])
	# 双坡屋顶 + 脊线 + 山墙封檐
	for side in [-1.0, 1.0]:
		_place_box(w, cx, h + 0.45, cz + side * 2.8, 21.0, 0.24, 6.4, _mats["conc_dark"],
				Vector3(0.22 * side, 0.0, 0.0))
	_place_box(w, cx, h + 0.95, cz, 21.4, 0.4, 1.0, _mats["conc_dark"])


# ================= 发射区（正南：火箭 + 勤务塔 + 总装厂房 + 观景坪） =================

func _launch(w) -> void:
	# —— 围墙院 x∈[-34,34]×z∈[92,140]（北门对接南路、南门图缘）——
	_wall_z(w, 92.0, -34.0, -4.0, 3.0, _mats["conc"])
	_wall_z(w, 92.0, 4.0, 34.0, 3.0, _mats["conc"])
	_wall_z(w, 140.0, -34.0, -4.0, 3.0, _mats["conc"])
	_wall_z(w, 140.0, 4.0, 34.0, 3.0, _mats["conc"])
	_wall_x(w, -34.0, 92.0, 140.0, 3.0, _mats["conc"])
	_wall_x(w, 34.0, 92.0, 140.0, 3.0, _mats["conc"])
	# —— 发射坪（x∈[-12,12]×z∈[104,128]）+ 导流槽 ——
	_pave(w, 0.0, 116.0, 26.0, 26.0)
	_place_box(w, 0.0, 0.02, 126.0, 8.0, 0.06, 4.0, _mats["conc_dark"])   # 导流槽盖板带
	for side in [-1.0, 1.0]:
		_place_box(w, side * 5.4, 0.3, 122.0, 0.6, 0.6, 10.0, _mats["conc_dark"])
		_obstacle(w, side * 5.4, 122.0, 0.3, 5.0, 0.6)
	# —— 火箭本体（灵魂地标：白箭体 r3.0 h58 + 锥头 + 裙座，总高 ≈61）——
	_place_box(w, 0.0, 1.5, 114.0, 8.0, 3.0, 8.0, _mats["conc_dark"])   # 发射座
	_obstacle(w, 0.0, 114.0, 4.0, 4.0, 3.0)
	var rk := MeshInstance3D.new()
	rk.mesh = _mesh_rocket
	rk.position = Vector3(0.0, 32.0, 114.0)
	rk.set_surface_override_material(0, _mats["white"])
	rk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 大件不投影先例
	w.add_child(rk)
	var nose := MeshInstance3D.new()
	nose.mesh = _mesh_nose
	nose.position = Vector3(0.0, 63.75, 114.0)
	nose.set_surface_override_material(0, _mats["white"])
	nose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(nose)
	for band_y in [22.0, 44.0, 56.0]:   # 级间段暗带 + 逃逸塔基座
		_cyl(w, _mesh_rocket, Vector3(0.0, band_y, 114.0), _mats["conc_dark"],
				Vector3(1.02, 0.012, 1.02))
	_cyl(w, _mesh_rocket, Vector3(0.0, 4.1, 114.0), _mats["conc_dark"],
			Vector3(1.1, 0.05, 1.1))   # 发动机裙
	for k in 4:   # 尾部稳定翼
		var ang := TAU * float(k) / 4.0 + PI * 0.25
		_place_box(w, cos(ang) * 3.6, 4.6, 114.0 + sin(ang) * 3.6,
				0.3, 3.2, 2.6, _mats["white"], Vector3(0.0, PI * 0.5 - ang, 0.0))
	_obstacle(w, 0.0, 114.0, 3.5, 3.5, 65.0, 3.0)
	# —— 勤务塔（x=7：格构桁架 h50 + 摆杆 ×2 连箭体）——
	for corner in [[-1.3, -1.3], [1.3, -1.3], [-1.3, 1.3], [1.3, 1.3]]:
		_place_box(w, 7.0 + corner[0], 25.0, 114.0 + corner[1], 0.45, 50.0, 0.45,
				_mats["rust"])
	for k in 6:   # 塔身横撑层
		var ly := 4.0 + 8.0 * float(k)
		_place_box(w, 7.0, ly, 114.0 - 1.3, 2.9, 0.25, 0.25, _mats["rust"])
		_place_box(w, 7.0, ly, 114.0 + 1.3, 2.9, 0.25, 0.25, _mats["rust"])
		_place_box(w, 7.0 - 1.3, ly, 114.0, 0.25, 0.25, 2.9, _mats["rust"])
		_place_box(w, 7.0 + 1.3, ly, 114.0, 0.25, 0.25, 2.9, _mats["rust"])
	for arm in [[28.0], [44.0]]:
		_place_box(w, 4.4, arm[0], 114.0, 3.6, 0.5, 0.9, _mats["pipe"])
		_place_box(w, 4.4, arm[0] + 1.6, 114.0, 0.9, 2.8, 0.9, _mats["conc_dark"])
	_cyl(w, _mesh_mast, Vector3(7.0, 52.5, 114.0), _mats["red"], Vector3(0.5, 0.5, 0.5))
	_obstacle(w, 7.0, 114.0, 1.7, 1.7, 52.0)
	# —— 垂直总装厂房（x∈[-32,-14]×z∈[98,124]，h22 高体量）——
	var vb: StandardMaterial3D = _mats["metal"]
	_wall_x(w, -32.0, 98.0, 124.0, 22.0, vb)
	_wall_z(w, 98.0, -32.0, -14.0, 22.0, vb, Vector2(-26.0, -20.0))     # 北门
	_wall_z(w, 124.0, -32.0, -14.0, 22.0, vb)
	_wall_x(w, -14.0, 98.0, 124.0, 22.0, vb, Vector2(106.0, 116.0))    # 东大门（朝发射坪）
	_place_box(w, -14.3, 9.4, 111.0, 0.24, 15.2, 10.0, vb)
	_place_box(w, -14.2, 6.0, 111.0, 0.16, 6.0, 9.6, _mats["conc_dark"])
	_place_box(w, -14.5, 12.4, 111.0, 0.3, 0.8, 10.4, _mats["red"])
	for k in 5:   # 垂直条纹（总装厂房语汇）
		_place_box(w, -32.3, 11.0, 101.0 + 5.0 * float(k), 0.14, 20.0, 1.6, _mats["white"])
	_place_box(w, -23.0, 22.4, 111.0, 18.6, 0.8, 26.6, _mats["conc_dark"])
	_place_box(w, -19.0, 6.0, 104.0, 6.0, 1.2, 6.0, _mats["metal_dark"])  # 级段平台
	_obstacle(w, -19.0, 104.0, 3.0, 3.0, 1.2)
	_place_box(w, -19.0, 6.0, 118.0, 6.0, 1.2, 6.0, _mats["metal_dark"])
	_obstacle(w, -19.0, 118.0, 3.0, 3.0, 1.2)
	# —— 设备房 ×2（E1 东北 z∈[94,103]、E2 东南 z∈[130,138]）——
	for ez in [[98.5, 94.0, 103.0], [134.0, 130.0, 138.0]]:
		var cz0: float = ez[0]
		_wall_z(w, ez[2], 10.0, 26.0, 5.0, _mats["conc"])
		_wall_z(w, ez[1], 10.0, 17.0, 5.0, _mats["conc"], Vector2(17.0, 19.0))
		_wall_z(w, ez[1], 19.0, 26.0, 5.0, _mats["conc"])
		_wall_x(w, 10.0, ez[1], ez[2], 5.0, _mats["conc"])
		_wall_x(w, 26.0, ez[1], ez[2], 5.0, _mats["conc"])
		_place_box(w, 18.0, 5.3, cz0, 16.6, 0.6, 9.6, _mats["conc_dark"])
		_place_box(w, 22.0, 0.8, cz0, 2.6, 1.6, 2.0, _mats["metal_dark"])
		_obstacle(w, 22.0, cz0, 1.3, 1.0, 1.6)
	# —— 液氧/煤油球罐 ×2（柱腿支撑）+ 消防水塔 ——
	for sp in [[22.0, 118.0], [28.0, 124.0]]:
		_cyl(w, _mesh_sphere, Vector3(sp[0], 5.0, sp[1]), _mats["white"], Vector3(3.0, 3.0, 3.0))
		for k in 4:
			var ang := TAU * float(k) / 4.0 + 0.79
			_place_box(w, sp[0] + cos(ang) * 2.2, 1.75, sp[1] + sin(ang) * 2.2,
					0.22, 3.5, 0.22, _mats["metal_dark"])
		_obstacle(w, sp[0], sp[1], 2.9, 2.9, 8.0)
	_cyl(w, _mesh_tank, Vector3(-24.0, 6.0, 132.0), _mats["tank"], Vector3(0.9, 1.1, 0.9))
	_place_box(w, -24.0, 12.2, 132.0, 5.4, 0.8, 5.4, _mats["conc_dark"])
	_obstacle(w, -24.0, 132.0, 3.0, 3.0, 12.6)
	# —— 避雷塔 ×3（图缘细高桅 + 顶红航标灯）——
	for tp in [[-28.0, 136.0], [30.0, 134.0], [-8.0, 96.0]]:
		_cyl(w, _mesh_mast, Vector3(tp[0], 16.0, tp[1]), _mats["pipe"],
				Vector3(1.0, 2.9, 1.0))
		for k in 3:
			var ang2 := TAU * float(k) / 3.0
			_place_box(w, tp[0] + cos(ang2) * 0.5, 28.0 + 1.4 * float(k),
					tp[1] + sin(ang2) * 0.5, 0.9, 0.08, 0.08, _mats["pipe"],
					Vector3(0.0, -ang2, 0.0))
		_place_box(w, tp[0], 30.5, tp[1], 0.3, 0.3, 0.3, _mats["red"])
		_obstacle(w, tp[0], tp[1], 0.4, 0.4, 30.5)
	# —— 观景坪（x∈[-52,-40]×z∈[106,122]：高台停机坪 = 12:00 定时撤离）——
	_place_box(w, -46.0, 0.28, 114.0, 13.0, 0.56, 17.0, _mats["plaza"])
	for side in [-1.0, 1.0]:
		_place_box(w, -46.0, 0.42, 114.0 + side * 8.7, 13.4, 0.28, 0.28, _mats["conc_dark"])
	_cyl(w, _mesh_sphere, Vector3(-46.0, 0.66, 114.0), _mats["white"],
			Vector3(4.4, 0.35, 4.4))   # 停机坪圆环标
	for k in 4:
		var ang3 := TAU * float(k) / 4.0 + 0.79
		_place_box(w, -46.0 + cos(ang3) * 5.4, 1.1, 114.0 + sin(ang3) * 5.4,
				0.14, 2.2, 0.14, _mats["conc_dark"])
	_place_box(w, -40.8, 1.9, 109.0, 0.1, 1.6, 0.1, _mats["pipe"])   # 风向袋杆
	_place_box(w, -40.4, 2.5, 109.0, 0.7, 0.3, 0.24, _mats["red"])
	_place_box(w, -50.5, 0.9, 118.5, 1.6, 1.4, 1.6, _mats["metal_dark"])
	_obstacle(w, -50.5, 118.5, 0.8, 0.8, 1.6)
	_place_box(w, -50.5, 0.9, 109.5, 1.6, 1.4, 1.6, _mats["metal_dark"])
	_obstacle(w, -50.5, 109.5, 0.8, 0.8, 1.6)


# ================= 外围荒野（戈壁环带：乱石 / 枯树 / 残骸） =================

func _wild(w) -> void:
	# 乱石堆 ×6（荒野 POI：巨石 + 碎石裙，注册大石）
	for rc in [[130.0, 52.0], [-134.0, -30.0], [-90.0, 120.0], [66.0, 134.0],
			[-120.0, 76.0], [118.0, -104.0]]:
		var bp := PBR.scene(BOULDER_GLB)
		if bp != null:
			var inst: Node3D = bp.instantiate()
			inst.position = Vector3(rc[0], 0.0, rc[1])
			inst.scale = Vector3.ONE * 1.7
			inst.rotation.y = rc[0] * 0.61 + rc[1] * 0.13
			w.add_child(inst)
		else:
			_pile(w, Vector3(rc[0], 0.9, rc[1]), Vector3(3.4, 1.9, 3.0), _mats["sand"])
		_pile(w, Vector3(rc[0] + 2.6, 0.4, rc[1] + 1.4), Vector3(1.7, 0.9, 1.6), _mats["sand"])
		_pile(w, Vector3(rc[0] - 2.2, 0.35, rc[1] - 1.8), Vector3(1.4, 0.75, 1.4), _mats["sand"])
		_obstacle(w, rc[0], rc[1], 2.6, 2.2, 2.0)
	# 荒野枯树 ×6（实拍 GLB；树干挡人 chx/chz 0.35——hd_world 枯树先例）
	for tp in [[142.0, 60.0], [-128.0, -60.0], [-70.0, 138.0], [96.0, 126.0],
			[-138.0, 110.0], [122.0, 118.0]]:
		_prop_gltf(w, DEAD_TREE_GLB, Vector3(tp[0], 0.0, tp[1]), Vector3.ONE,
				tp[0] * 0.7 + tp[1] * 0.3)
		_obstacle(w, tp[0], tp[1], 0.35, 0.35, 4.0)
	# 东路残骸车队 ×2（运输靠公路的痕迹语汇）
	for wv in [[52.0, -12.0], [55.0, 22.0]]:
		_place_box(w, wv[0], 0.7, wv[1], 1.9, 1.3, 4.3, _mats["conc_dark"])
		_place_box(w, wv[0] - 0.9, 1.5, wv[1], 1.6, 1.0, 1.8, _mats["rust"])
		_obstacle(w, wv[0], wv[1], 1.1, 2.2, 1.6)
	# 西南干河床（河湾下游痕迹：沙色带 + 卵石）
	_place_box(w, -54.0, 0.02, 76.0, 16.0, 0.05, 24.0, _mats["sand"])
	for k in 7:
		var gx := -60.0 + 12.0 * float(k % 3)
		var gz := 66.0 + 4.0 * float(k)
		_pile(w, Vector3(gx, 0.16, gz), Vector3(0.5, 0.3, 0.5), _mats["sand"])


# ================= 点位登记 =================

## 容器 55 + 巡逻 32（格式对齐 hd_dam_zones.gd:1347；pos 全部落地面 y=0）
func _register_spots(w) -> void:
	for c in SPACE_CONTAINERS:
		var v: Vector2 = c["p"]
		w.container_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": c["z"]})
	for p in SPACE_PATROLS:
		var v: Vector2 = p["p"]
		w.patrol_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": p["z"]})
