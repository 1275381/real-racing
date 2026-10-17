class_name HDDamZones
extends Node3D
## 零号大坝四新区（搜打撤「烽火地带」中环补全·已复审规划唯一事实源）——
## 军营（西带 −114,−18）/ 主变电站大电（东带 111,−15）/ 水泥厂（西南带 −99,26）
## / 游客中心（东南带 91,46）。职责切分：坝体硬结构归 hd_dam.gd、坝底陈设归
## hd_dam_base.gd，本文件只做四新区；契约照抄 base：build(root) 带 _built 幂等
## 护栏、视觉 add_child(root)、障碍/点位 append（hd_dam_base.gd:772-778 同款）。
##
## —— 落位表（对 hd_world.gd:83-205 逐点避让核对，规划 where 段口径）——
## 军营 x∈[−138,−98]×z∈[−42,6]：板房 x∈[−130,−98]×z∈[−30,−18]（长条比例）、
##   帐篷区 z∈[−6,4]、东门 x=−98、指挥处披屋 x∈[−136,−130]×z∈[−19,−14]
##   （突出围墙外贴山墙）、短楼A x∈[−127,−119]×z∈[−14,−8]（内院西段）/
##   短楼B x∈[−129,−121]×z∈[−40,−34]（北墙内）；mid 容器 (−96,0)
##   在东门外 2m 保留为 loot 锚点、dead_tree (−95,−40) 距东界 3m、rocks (−110,−60)
##   距北界 18m、wreck (−125,20) 距南界 14m、wild 巡逻 (−140,40) 距披屋西界 4m、
##   wild 容器 (−144,−10) 距披屋西界 8m（卡车停西墙外 (−135.5,−6) 距该点 9m+）。
## 大电 x∈[96,126]×z∈[−32,2]（西段 z∈[−26,−14] 内凹至 x=98.5）：主控楼
##   x∈[104,126]×z∈[−26,−12]、变压器双列 z=−29/−7.5（走廊 z≈−20 让巡逻点 (100,−20)）；
##   让位记录：既有 MID_PROPS wreck (95,−20) 旋转保守 AABB 东缘 ≈97.18，围栏内凹段
##   x=98.5 与之留 1.32m 视觉间隙且围栏不注册碰撞（wreck 低矮不构成新区动线冲突）；
##   dead_tree (130,−20) 距东界 4m、rocks/wreck (118..120,−60) 距南界 28m、
##   mid 容器 (96,0) 已在 hd_world 挪 (104,−4) 入西院。
## 水泥厂 x∈[−122,−76]×z∈[6,46]：筒仓列西北 (−116,10.5/18/25.5)、主楼
##   x∈[−92,−76]×z∈[14,40]、宿舍南缘 z∈[40,46]、垃圾场西南角 z∈[38,46]；
##   mid 巡逻 (−95,30) 原地保留（主楼西墙面 x=−92 距 3m 开敞）、mid 容器 (−84,44)
##   已在 hd_world 挪 (−84,50) 让出宿舍 footprint、dead_tree (−120,50) 距北界 4m、
##   wreck (−125,20) 距西界 3m、mid 容器 (−96,0) 距北界 6m、wild 巡逻 (−140,40)
##   西界外 18m。
## 游客中心 x∈[76,106]×z∈[33,58]：主翼贴北 z∈[33,42.5]（北缩 1.5m 让容器点）、
##   短翼东端南折 x∈[96,106]×z∈[42.5,54]、南广场 x∈[76,96]×z∈[44,54]、停车场
##   z∈[55,58] 压住出生带边界线（z>60 留空）；既有 mid 容器 (84,44) 原地保留=
##   广场北缘锚点（主翼南墙面 42.75 距该点 1.25m、loot 盒缘间隙 ≥0.6m 无嵌墙）、
##   dead_tree (110,40) 距东界 4m、wreck (135,35) 距东界 29m；西侧 x<76 一带
##   实测落 center 红罩（main.gd:327），全部铺装/建筑严格控制在 x≥76。
##
## —— 障碍 83 条（性能红线：只注册可玩区墙体与 ≥1.4m 高实体；判图深化
## 63→82→83：桁架 2→5 榀 +10 柱、变压器 6→8 台、军营两短楼 +8、帐篷 4→6、
## 装载机 +1、岗楼 +1）——
## 军营 35（板房外墙 5 段门洞让空 + 内隔墙 2 + 楼梯侧墙 1 + 围墙 4（北墙让隧道口
##   分 2 段） + 隧道口拱墙 2 + 东门双柱 2 + 帐篷 6 + 指挥处披屋 3 + 卡车 1 +
##   短楼A/B 各 4 + 岗楼 1）；
## 大电 24（主控楼墙 5 段门洞让空 + 变压器 8 台各 1 含基座 AABB + 桁架柱 10 +
##   叉车+变电箱合并 1）；水泥厂 17（主楼墙 5 + 二层平台柱 2 + 筒仓 3 + 宿舍墙 4 +
##   料堆/垃圾山 2 + 装载机 1）；游客中心 7（L 楼墙 6 + 门厅前石阶 1）。
## 不注册语义：铁丝网围栏/旗杆/绝缘子串/招牌/渡槽桁架面/檐下钢柱/碎石过渡带/
## 树池座椅灯杆/电缆沟盖板一律纯视觉——不注册即任意高度弹道直穿，取舍依据
## 「纯视觉薄壁不构成战术掩体」（对照 hd_dam.gd:16-17 远景件不注册先例）。
## 新 loot 盒 7 条由 hd_loot 运行时自动入账（209+83+7=299）。
##
## —— 材质恰 14 枚（对齐 dam 9 / base 15 的份额纪律，零跨文件引用）——
## camo 灰绿板房墙（橄榄灰绿 0.42,0.40,0.30——base『green』厂房甲橄榄同语压暗一档）
## / canvas 帆布白帐篷（base 无此色，新语）/ asphalt 沥青深双坡顶兼近黑洞龛背板
## / concrete 灰白混凝土（主控楼·新工业：免噪点更平整，与坝体老混凝土分语）
## / panel 变压器深灰蓝 / corten 锈橙哑光（桁架·渡槽，与泄洪管亮银错开）
## / silo 筒仓浅灰 / yellow 厂房黄（对齐 base tan 语系）/ porcelain 白绝缘子
## / glass 暗蓝低反玻璃（rough 0.15·metal 0.5，全图唯一镜面语汇）
## / white 白挑檐·旗杆 / dark 深色窗框门楣机柜 / plaza 浅灰铺装 / red 红件
## / siloshade 筒仓竖筋（第 3 轮判图 #3 加的第 15 枚——silo 深一档换筋条可读性）。
## 共用网格：单位盒按尺寸缓存（_box_mesh 同 base 款）+ 筒仓大圆柱/锥顶/旗杆/
## 绝缘子盘 4 张 CylinderMesh + 料堆单位球——细件全走实例 scale。

const PBR := preload("res://scripts/hd_pbr.gd")
const QUIVER_GLB := "res://assets/pbr/models/quiver_tree_02/quiver_tree_02_lod.glb"   # 美术写实化：CC0 实拍 PBR 贴图（缺失自动回退纯色）
const WALL_T := 0.5             # 建筑墙厚（base 厂房同款）
const GROUND_TOP := 0.03        # 新区铺装顶面统一标高：与大地 y0 错层防 z-fighting
## 四新区 loot 点 7（全部落地面 y=0——hd_loot 容器 bot=0 地面语义 + 纯 XZ 搜索；
## zone 串为本 session 无头 zone_at 逐点实测值：roll_loot 走 zone_at 实时裁决，
## 字段与实测一致防 hd_soldiers 同区分组路由与 loot 档位错档）
const ZONE_CONTAINERS := [
	{"p": Vector2(-116.0, -24.0), "z": "wild"},   # 军营板房一层西二开间
	{"p": Vector2(-114.0, 0.0), "z": "wild"},     # 军营板房南门外内院（实测 wild）
	{"p": Vector2(107.0, -19.0), "z": "mid"},     # 大电两列变压器走廊（钉西半 d<112 段）
	{"p": Vector2(100.0, -4.0), "z": "mid"},      # 大电西院
	{"p": Vector2(-86.0, 22.0), "z": "mid"},      # 水泥主楼一层
	{"p": Vector2(-92.0, 43.0), "z": "mid"},      # 水泥宿舍西门外
	{"p": Vector2(80.0, 38.0), "z": "mid"},       # 游客中心门厅室内
]
## 四新区巡逻点 5（zone 串=zone_at 实测；军营一组 wild 一组 mid 各自并入全图
## 同 zone 路网，满足 hd_soldiers 家点+2 邻域成路）
const ZONE_PATROLS := [
	{"p": Vector2(-116.0, -8.0), "z": "wild"},    # 军营内院
	{"p": Vector2(-102.0, -4.0), "z": "mid"},     # 军营东南角东门外（实测 mid）
	{"p": Vector2(108.0, -3.0), "z": "mid"},      # 大电西院
	{"p": Vector2(-100.0, 26.0), "z": "mid"},     # 水泥厂主楼西侧料场
	{"p": Vector2(88.0, 50.0), "z": "mid"},       # 游客南广场
]

var _built := false
var _mats := {}                  # 材质表（恰 14 枚）
var _mesh_cache := {}            # 材质 -> {尺寸键 -> BoxMesh}（同尺寸同材质共用一张网格）
var _mesh_silo: CylinderMesh     # 筒仓直筒 r3.2 h15（卧罐/白罐缩放复用）
var _mesh_cone: CylinderMesh     # 锥顶 r3.2→0.25 h3
var _mesh_pole: CylinderMesh     # 旗杆/天线 r0.09 h8
var _mesh_insulator: CylinderMesh   # 绝缘子盘 r0.16 h0.1（瓷套管=纵向拉长）
var _mesh_pile: SphereMesh       # 料堆/瓦砾单位球


func build(root: Node3D) -> void:
	if _built or root == null:
		return
	_built = true
	var w = root   # HDWorld（鸭子类型，hd_dam_base.gd:200 同款）
	_make_mats()
	_dress_pbr()
	_make_meshes()
	_camp(w)
	_substation(w)
	_cement(w)
	_visitor(w)
	_register_spots(w)


# ================= 材质与共用网格 =================

## 美术写实化：四新区换实拍材质——营房/箱体旧漆铁皮、主变压器与筒仓带锈钢、
## 游客中心与营房墙面风化抹灰、路面沥青、广场混凝土；玻璃/瓷瓶/帆布保留
var _grime_mats: Array = []   # 挂风化污迹贴花的墙体材质


func _dress_pbr() -> void:
	var plan := {
		"camo": ["container", 2.4],
		"asphalt": ["asphalt", 4.0],
		"concrete": ["concrete", 4.0],
		"panel": ["corrugated", 2.5],
		"corten": ["paint_rust", 1.5],
		"silo": ["paint_rust", 3.0],
		"siloshade": ["paint_rust", 3.0],
		"yellow": ["brick", 2.2],
		"white": ["plaster_paint", 3.0],
		"dark": ["paint_rust", 1.5],
		"plaza": ["concrete", 3.0],
		"red": ["paint_rust", 2.0],
	}
	for key in plan:
		if _mats.has(key):
			PBR.dress(_mats[key], str(plan[key][0]), float(plan[key][1]))
	for key in ["white", "yellow", "concrete", "camo", "panel"]:
		if _mats.has(key):
			_grime_mats.append(_mats[key])
	PBR.glass(_mats["glass"])


func _make_mats() -> void:
	# 第 2 轮判图 #8：橄榄灰绿压暗一档+增绿相（首版 0.42,0.40,0.30 被读成沙黄）
	_mats["camo"] = _std_mat(Color(0.37, 0.39, 0.26), 0.85, 0.0)
	_mats["canvas"] = _std_mat(Color(0.86, 0.84, 0.77), 0.95, 0.0)
	_mats["asphalt"] = _std_mat(Color(0.16, 0.16, 0.17), 0.9, 0.0)
	# 新工业灰白：免噪点纹理、更平整——与坝体 _mat_concrete（三平面流挂噪点）分读；
	# 第 3 轮判图 #4：0.72,0.71,0.67 在暖光下读成灰褐/土黄——提亮去黄调纯灰白
	_mats["concrete"] = _std_mat(Color(0.78, 0.78, 0.75), 0.9, 0.0)
	_mats["panel"] = _std_mat(Color(0.34, 0.38, 0.44), 0.7, 0.2)
	# 第 2 轮判图 #4/#5：锈橙明度上调半档+彻底哑光（远景 30-90m 读出锈橙桁架语言）
	_mats["corten"] = _std_mat(Color(0.56, 0.31, 0.18), 1.0, 0.0)
	_mats["silo"] = _std_mat(Color(0.66, 0.66, 0.64), 0.85, 0.0)
	# 第 3 轮判图 #3：筒仓竖筋同色凸条靠光影读不出（75% 置信无筋）——
	# silo 深一档的筋条专用色（第 15 枚，超 ~14 份额 1 枚换可读性）
	_mats["siloshade"] = _std_mat(Color(0.5, 0.5, 0.48), 0.85, 0.0)
	_mats["yellow"] = _std_mat(Color(0.72, 0.62, 0.4), 0.85, 0.0)
	_mats["porcelain"] = _std_mat(Color(0.88, 0.88, 0.86), 0.4, 0.0)
	# 全图唯一镜面语汇：暗蓝低反，晴天反天光读作「玻璃体反光块」——
	# 第 2 轮判图 #3：再压暗半档+metallic 上调，让反射明暗带（天光 vs 环境暗侧）
	# 对比拉开，配合 1.2m 竖梃分格破「整块蓝灰塑料板」
	_mats["glass"] = _std_mat(Color(0.16, 0.25, 0.36), 0.15, 0.6)
	_mats["white"] = _std_mat(Color(0.85, 0.84, 0.8), 0.8, 0.0)
	_mats["dark"] = _std_mat(Color(0.2, 0.21, 0.24), 0.8, 0.0)
	# 第 2 轮判图 #12/#18：铺装压暗一档（首版在过曝下读成贴地色带与沙地硬切）
	_mats["plaza"] = _std_mat(Color(0.52, 0.51, 0.48), 1.0, 0.0)
	_mats["red"] = _std_mat(Color(0.55, 0.18, 0.14), 0.65, 0.2)


func _std_mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _make_meshes() -> void:
	_mesh_silo = CylinderMesh.new()
	_mesh_silo.top_radius = 3.2
	_mesh_silo.bottom_radius = 3.2
	_mesh_silo.height = 15.0
	_mesh_silo.radial_segments = 24
	_mesh_silo.rings = 2
	_mesh_cone = CylinderMesh.new()
	_mesh_cone.top_radius = 0.25
	_mesh_cone.bottom_radius = 3.2
	_mesh_cone.height = 3.0
	_mesh_cone.radial_segments = 24
	_mesh_cone.rings = 4
	_mesh_pole = CylinderMesh.new()
	_mesh_pole.top_radius = 0.09
	_mesh_pole.bottom_radius = 0.11
	_mesh_pole.height = 11.0   # 第 3 轮判图 #9：8→11m——全景天际线读出竖针剪影
	_mesh_pole.radial_segments = 10
	_mesh_insulator = CylinderMesh.new()
	_mesh_insulator.top_radius = 0.22   # 第 2 轮判图 #10：绝缘子盘加大一号
	_mesh_insulator.bottom_radius = 0.22
	_mesh_insulator.height = 0.12
	_mesh_insulator.radial_segments = 10
	_mesh_pile = SphereMesh.new()
	_mesh_pile.radius = 1.0
	_mesh_pile.height = 2.0
	_mesh_pile.radial_segments = 16
	_mesh_pile.rings = 8


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
	# 写实化：大面墙挂风化污迹贴花（雨水流挂 + 墙脚尘土）
	if rot == Vector3.ZERO and _grime_mats.has(mat):
		PBR.grime_decal(parent, Vector3(x, y, z), Vector3(w, h, d))
		# 写实化第三轮：落地墙体加勒脚/压顶/壁柱，破方块盒外形
		PBR.relief(parent, Vector3(x, y, z), Vector3(w, h, d), mat)
	return mi


## 立式共用圆柱件（旗杆/绝缘子/筒仓），可选缩放与材质覆盖
func _cyl(parent: Node3D, mesh: CylinderMesh, pos: Vector3, mat: StandardMaterial3D,
		scl := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)


func _pile(parent: Node3D, pos: Vector3, scl: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_pile
	mi.position = pos
	mi.scale = scl
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)


func _obstacle(w, cx: float, cz: float, hx: float, hz: float, top: float,
		bot := 0.0) -> void:
	w.obstacles.append({"cx": cx, "cz": cz, "hx": hx, "hz": hz, "top": top, "bot": bot})


## 铺装地坪（纯地面不注册）：顶面统一 GROUND_TOP 与大地错层，底 −0.07 埋地
## （hd_dam_base.gd:405 hardstand 同款手法）
func _pave(w, cx: float, cz: float, sx: float, sz: float) -> void:
	_place_box(w, cx, GROUND_TOP - 0.05, cz, sx, 0.1, sz, _mats["plaza"])


# ================= ① 军营（西营房 + 帐篷区） =================

func _camp(w) -> void:
	_pave(w, -114.0, -18.0, 34.0, 49.0)
	# 军营硬化地坪分格+内部散碎石（第 3 轮判图 #8 落地；第 4 轮判图 #3 再校
	# 可读尺度：分格条 0.12→0.34 宽、碎石 0.18→0.4-0.85——130m 外 overview
	# 机位仍可读出「硬化地坪网格」而非平涂）
	for k in 4:
		_place_box(w, -128.0 + 6.5 * float(k), GROUND_TOP + 0.015, -18.0, 0.34,
				0.04, 48.0, _mats["dark"])
	for kz in 6:
		_place_box(w, -114.0, GROUND_TOP + 0.015, -40.0 + 7.0 * float(kz), 33.0,
				0.04, 0.34, _mats["dark"])
	var seed_v := 20261023
	for k in 14:   # 内部散碎石点（LCG 固定序列，加大到 130m 可读尺度）
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var gx := -129.0 + 25.0 * float(seed_v % 1000) / 1000.0
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var gz := -40.5 + 44.0 * float(seed_v % 1000) / 1000.0
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var gs := 0.4 + 0.45 * float(seed_v % 100) / 100.0
		_place_box(w, gx, gs * 0.25, gz, gs, gs * 0.5, gs * 0.72,
				_mats["dark"] if k % 3 == 0 else _mats["silo"],
				Vector3(0.0, 0.6 * float(k % 4), 0.0))
	_camp_barracks(w)
	_camp_huts(w)
	_camp_tower(w)
	_camp_wall(w)
	_camp_tunnel(w)
	_camp_gate(w)
	_camp_tents(w)
	_camp_annex(w)
	_camp_truck(w)
	_camp_props(w)
	_camp_skirt(w)


## 营区聚落组团（第 2 轮判图 #7：单栋长楼+2 帐篷太单薄——紧凑版补两栋 8×6
## 单层小板房错落合围，与长楼/帐篷簇构成「西营房聚落」三簇结构）；
## 每栋北1+南1+西1+东1=4 段障碍（门洞贴端让空），单坡顶+南面板缝条同主楼语汇
func _camp_huts(w) -> void:
	# 短楼A：内院西段 @ x∈[−127,−119]×z∈[−14,−8]——原落位 (−104,−27) 在板房
	# 东延到 x=−98 后整栋嵌进板房东开间（墙障碍切穿房间与楼梯），挪出：距板房
	# 南墙 4m、西围墙 2.9m、北排帐篷 3m、内院巡逻点 (−116,−8) 3m、中门坡道 3.4m
	_camp_hut(w, -123.0, -11.0, true)
	# 短楼B：北围墙内 @ x∈[−129,−121]×z∈[−40,−34]（距隧道口拱缘西端 1m 让空）
	_camp_hut(w, -125.0, -37.0, false)


func _camp_hut(w, cx: float, cz: float, door_west: bool) -> void:
	var n0: int = w.get_child_count()
	var x0 := cx - 4.0
	var x1 := cx + 4.0
	var z0 := cz - 3.0
	var z1 := cz + 3.0
	var h := 3.2
	# 四墙各 1 段：门洞贴端（A 朝西=板房西门动线、B 朝南=内院动线），不增分段
	for wz in [z0 + WALL_T * 0.5, z1 - WALL_T * 0.5]:
		_place_box(w, cx, h * 0.5, wz, 8.0, h, WALL_T, _mats["camo"])
		_obstacle(w, cx, wz, 4.0, WALL_T * 0.5, h)
	for wx in [x0 + WALL_T * 0.5, x1 - WALL_T * 0.5]:
		_place_box(w, wx, h * 0.5, cz, WALL_T, h, 5.0, _mats["camo"])
		_obstacle(w, wx, cz, WALL_T * 0.5, 2.5, h)
	if door_west:
		_place_box(w, x0 + 0.02, 1.7, cz + 2.1, 0.16, 3.4, 1.8, _mats["white"])
	else:
		_place_box(w, cx, 1.7, z1 + 0.02, 1.8, 3.4, 0.16, _mats["white"])
	# 单坡顶（北高南低披水）+ 檐口封板 + 南面板缝条 + 小窗
	_place_box(w, cx, h + 0.15, cz, 8.6, 0.18, 6.6, _mats["asphalt"],
			Vector3(0.18, 0.0, 0.0))
	_place_box(w, cx, h - 0.12, z1 + 0.2, 8.6, 0.3, 0.22, _mats["dark"])
	for k in 3:
		_place_box(w, cx, 0.7 + 0.95 * float(k), z1 + 0.05, 7.2, 0.16, 0.1,
				_mats["camo"])
	_place_box(w, cx + 2.0, 1.8, z1 + 0.06, 1.1, 1.2, 0.12, _mats["panel"])
	# 写实化第四轮：可见层换 Blender 建模版（缺模型保留上面方块版，碰撞不变）
	PBR.swap_building(w, n0, "hut_a" if door_west else "hut_b", Vector3(cx, 0.0, cz),
			[[x0, x1, z0, z1, 0.0, h]])


## 两层岗楼（第 3 轮判图 #7：营区再补 1 座带平台栏杆的岗楼——东门外侧
## (−93,−24) 面向地图中心的制高点哨位，四腿+平台+栏杆+顶棚剪影）
func _camp_tower(w) -> void:
	for sx in [-1.1, 1.1]:
		for sz in [-1.1, 1.1]:
			_place_box(w, -93.0 + sx, 2.5, -24.0 + sz, 0.22, 5.0, 0.22,
					_mats["camo"])
	# 平台 + 四面栏杆 + 小顶棚 + 爬梯（视觉）——塔柱合并 1 条障碍
	_place_box(w, -93.0, 5.15, -24.0, 3.4, 0.3, 3.4, _mats["concrete"])
	for side in [-1.0, 1.0]:
		_place_box(w, -93.0, 5.95, -24.0 + side * 1.65, 3.4, 0.9, 0.08,
				_mats["dark"])
		_place_box(w, -93.0 + side * 1.65, 5.95, -24.0, 0.08, 0.9, 3.4,
				_mats["dark"])
	_place_box(w, -93.0, 6.6, -24.0, 3.9, 0.16, 3.9, _mats["asphalt"])
	for sx in [-1.5, 1.5]:
		for sz in [-1.5, 1.5]:
			_place_box(w, -93.0 + sx, 6.2, -24.0 + sz, 0.12, 0.7, 0.12,
					_mats["dark"])
	_place_box(w, -91.2, 2.5, -24.0, 0.7, 5.0, 0.1, _mats["dark"])
	_obstacle(w, -93.0, -24.0, 1.9, 1.9, 5.0)


## 军营门口细件组（第 4 轮判图 #2 头号缺口：近景零细件——规划「细件只挂
## 四区各 1-2 个焦点面」的军营焦点面=东门内院：沙袋墙+弹药箱堆+木托盘+
## 轮胎+8m 旗杆红旗牌一组；全部 <1.4m 纯视觉不注册）
func _camp_props(w) -> void:
	# 沙袋墙：两排三层错缝（土黄袋+深色袋交替，袋间错位 0.18 砌感）
	for layer in 3:
		var ly := 0.15 + 0.29 * float(layer)
		var n := 6 - layer
		for k in n:
			var kx := -100.2 + 0.58 * float(k) + (0.18 if layer % 2 == 1 else 0.0)
			_place_box(w, kx, ly, -20.6, 0.56, 0.28, 0.36,
					_mats["yellow"] if (k + layer) % 2 == 0 else _mats["dark"],
					Vector3(0.0, 0.04 * float(k % 3), 0.0))
	# 弹药箱堆（板房东角外：三底一顶）
	for k in 3:
		_place_box(w, -100.6 + 0.85 * float(k), 0.28, -31.5, 0.8, 0.55, 0.55,
				_mats["dark"] if k == 1 else _mats["yellow"],
				Vector3(0.0, 0.12 * float(k % 2), 0.0))
	_place_box(w, -101.05, 0.83, -31.5, 0.8, 0.55, 0.55, _mats["yellow"])
	# 木托盘×2 + 叠箱（托盘条板感：面板+双垫脚）
	for tp in [[-104.5, -33.0], [-105.8, -31.6]]:
		_place_box(w, tp[0], 0.1, tp[1], 1.25, 0.16, 1.0, _mats["yellow"])
		for fx in [-0.45, 0.45]:
			_place_box(w, tp[0] + fx, 0.04, tp[1], 0.3, 0.14, 0.85, _mats["dark"])
	_place_box(w, -105.8, 0.5, -31.6, 0.75, 0.7, 0.65, _mats["dark"])
	# 轮胎×3（绝缘子网格压扁，靠沙袋墙散放）
	for tp in [[-99.0, -19.8, 0.0], [-98.4, -21.2, 0.5], [-99.6, -21.0, 1.1]]:
		_cyl(w, _mesh_insulator, Vector3(tp[0], 0.1, tp[1]), _mats["dark"],
				Vector3(2.3, 1.7, 2.3))
	# 8m 旗杆+红旗牌（东门柱旁，面向地图中心可辨）
	_cyl(w, _mesh_pole, Vector3(-97.0, 4.0, -31.5), _mats["white"],
			Vector3(1.0, 8.0 / 11.0, 1.0))
	_place_box(w, -96.5, 7.3, -31.5, 1.0, 0.6, 0.04, _mats["red"])
	# 土色车辙带（第 4 轮判图 #3：东门→板房中门的动线辙印破草地平涂）
	_place_box(w, -105.5, 0.045, -21.5, 2.4, 0.02, 19.0, _mats["plaza"],
			Vector3(0.0, 0.42, 0.0))
	for k in 6:
		var tz := -13.8 - 3.0 * float(k)
		for sx in [-0.75, 0.75]:
			_place_box(w, -105.5 + sx * 0.92, 0.055, tz, 0.34, 0.02, 2.1,
					_mats["dark"], Vector3(0.0, 0.42, 0.0))
## 营地铺装边缘碎石过渡带（第 2 轮判图 #12：铺装与沙地的直线硬切被读成
## 贴地色带穿帮——沿地坪四边摆 LCG 固定序列碎石小盒，打破直线交界）
func _camp_skirt(w) -> void:
	var seed_v := 20261021
	for k in 26:
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var f := float(seed_v % 1000) / 1000.0
		var px := 0.0
		var pz := 0.0
		match k % 4:
			0:      # 西长边外
				px = -131.2 - f * 0.5
				pz = lerpf(-41.0, 5.0, f)
			1:      # 东长边外（东门敞开面）
				px = -96.8 - f * 0.4
				pz = lerpf(-40.0, 4.0, f)
			2:      # 北短边外
				px = lerpf(-129.0, -99.0, f)
				pz = -42.8 - f * 0.5
			_:      # 南短边外
				px = lerpf(-129.0, -99.0, f)
				pz = 6.8 + f * 0.5
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var s := 0.22 + 0.3 * float(seed_v % 100) / 100.0
		_place_box(w, px, s * 0.35, pz, s, s * 0.7, s * 0.8,
				_mats["dark"] if k % 4 == 0 else _mats["silo"],
				Vector3(0.0, 0.5 * float(k % 3), 0.0))


## 两层板房营房：footprint 取规划 landmarks「30×12×7」的长条比例——x 跨保
## where 落位锚（西墙 −130 对 wall_hit 采样、东门 x=−98），z 收 12 深
## （z∈[−30,−18]：北/西/东墙通高整块，南墙 3 门洞让空成 2 大段，东西门洞贴
## 端部=军营外墙 5 段障碍的凑段手法），双坡顶沥青脊线 7m。首版误按 where 段
## 32×24 大饼建过（屋面只盖半跨漏天光，shot_dam_new1 实拍返工）。
func _camp_barracks(w) -> void:
	var n0: int = w.get_child_count()
	var x0 := -130.0
	var x1 := -98.0
	var z0 := -30.0
	var z1 := -18.0
	var h := 6.2
	var mid_z := (z0 + z1) * 0.5
	# —— 外墙（障碍 5 段：北 1 + 南 2 + 西 1 + 东 1，南墙门洞：西门洞贴西端
	#    x∈[−130,−128.2]、中门 x∈[−115.4,−112.9] 2.5 宽、东门洞贴东端 x∈[−99.8,−98]）
	_place_box(w, (x0 + x1) * 0.5, h * 0.5, z0 + WALL_T * 0.5, x1 - x0, h, WALL_T,
			_mats["camo"])
	_obstacle(w, (x0 + x1) * 0.5, z0 + WALL_T * 0.5, (x1 - x0) * 0.5, WALL_T * 0.5, h)
	_place_box(w, x0 + WALL_T * 0.5, h * 0.5, mid_z, WALL_T, h, z1 - z0 - WALL_T * 2.0,
			_mats["camo"])
	_obstacle(w, x0 + WALL_T * 0.5, mid_z, WALL_T * 0.5,
			(z1 - z0 - WALL_T * 2.0) * 0.5, h)
	_place_box(w, x1 - WALL_T * 0.5, h * 0.5, mid_z, WALL_T, h, z1 - z0 - WALL_T * 2.0,
			_mats["camo"])
	_obstacle(w, x1 - WALL_T * 0.5, mid_z, WALL_T * 0.5,
			(z1 - z0 - WALL_T * 2.0) * 0.5, h)
	# 南墙西大段 [−128.2,−115.4] / 东大段 [−112.9,−99.8]（中心与长度按区间直算）
	for seg in [[-121.8, 12.8], [-106.35, 13.1]]:
		_place_box(w, seg[0], 1.7, z1 - WALL_T * 0.5, seg[1], 3.4, WALL_T,
				_mats["camo"])
		_obstacle(w, seg[0], z1 - WALL_T * 0.5, seg[1] * 0.5, WALL_T * 0.5, 3.4)
	# 三门楣（悬空 y≥2.5 不挡走人不注册）+ 白门框 + 门前台阶 + 墙脚散水
	# （第 2 轮判图 #2：门窗框与房前台阶/散水是板房近景焦点件）
	for lint in [[-129.1, 1.8], [-114.15, 2.5], [-98.9, 1.8]]:
		_place_box(w, lint[0], 2.95, z1 - WALL_T * 0.5, lint[1], 0.9, WALL_T,
				_mats["camo"])
		for fz in [lint[0] - lint[1] * 0.5 - 0.1, lint[0] + lint[1] * 0.5 + 0.1]:
			_place_box(w, fz, 1.7, z1 + 0.02, 0.2, 3.4, 0.16, _mats["white"])
		_place_box(w, lint[0], 0.15, z1 + 0.85, lint[1] + 0.6, 0.3, 1.3,
				_mats["concrete"])
	_place_box(w, (x0 + x1) * 0.5, 0.06, z1 + 0.62, x1 - x0 + 0.4, 0.12, 0.9,
			_mats["concrete"])
	# 横向板缝（第 4 轮判图 #6：0.9m/道 6 道在中景读不出分层——按判图口径
	# 加密到 0.5m/道 11 道，asphalt 深缝盒+白端头）
	for fz in [z0 - 0.06, z1 + 0.06]:
		for k in 11:
			var sy := 0.55 + 0.5 * float(k)
			_place_box(w, (x0 + x1) * 0.5, sy, fz, x1 - x0 - 0.6, 0.15, 0.12,
					_mats["asphalt"])
		for ex in [x0 + 0.4, x1 - 0.4]:
			for k in 3:
				_place_box(w, ex, 0.9 + 1.7 * float(k), fz, 0.5, 0.2, 0.16,
						_mats["white"])
	# 中门无障碍坡道（第 3 轮判图 #6：门口补台阶或坡道 1-2 处——斜盒坡道）
	_place_box(w, -114.15, 0.12, z1 + 1.05, 2.9, 0.24, 1.6, _mats["concrete"],
			Vector3(0.148, 0.0, 0.0))
	# —— 内隔墙 2 道（通高分 4 间）+ 楼梯侧墙 1
	for px in [-122.5, -107.5]:
		_place_box(w, px, h * 0.5, mid_z, WALL_T, h, z1 - z0 - WALL_T * 2.0,
				_mats["camo"])
		_obstacle(w, px, mid_z, WALL_T * 0.5, (z1 - z0 - WALL_T * 2.0) * 0.5, h)
	_place_box(w, -103.0, 1.55, -27.7, 9.0, 3.1, 0.24, _mats["camo"])
	_obstacle(w, -103.0, -27.7, 4.5, 0.12, 3.1)
	# 楼梯 14 级 0.3 踏步贴北墙（纯视觉——玩家 y 走 ground_height 平面）
	for k in 14:
		_place_box(w, -106.0 + 0.3 * float(k), 0.11 + 0.22 * float(k), -28.6,
				0.3, 0.22, 1.6, _mats["concrete"])
	# —— 二层楼板三块（楼梯带 z∈[−29.4,−27.6]×x∈[−107.5,−101.8] 让空）+
	#    二层北窗×8 + 南面半开敞走廊栏杆
	for slab in [[-118.5, 22.0, -24.0, 10.8], [-103.0, 9.0, -23.1, 9.0],
			[-100.15, 3.3, -28.5, 1.8]]:
		_place_box(w, slab[0], 3.2, slab[2], slab[1], 0.2, slab[3],
				_mats["concrete"])
	for k in 8:
		_place_box(w, -127.0 + 4.0 * float(k), 4.8, z0 - 0.08, 1.2, 1.4, 0.14,
				_mats["panel"])
	_place_box(w, (x0 + x1) * 0.5, 3.9, z1 - 0.4, x1 - x0 - 1.0, 0.08, 0.1,
			_mats["dark"])
	for k in 6:
		_place_box(w, -126.0 + 5.6 * float(k), 3.6, z1 - 0.4, 0.08, 0.7, 0.08,
				_mats["dark"])
	# —— 双坡屋顶（第 2 轮判图 #6：首版 7.6° 缓坡远读平顶——坡板加厚+大断面
	#    沥青脊压条+东西山墙阶梯三角封檐，屋脊线/人字形双坡双锚点读出）
	for side in [-1.0, 1.0]:
		_place_box(w, (x0 + x1) * 0.5, 6.55, mid_z + side * 3.05, 31.0, 0.3, 6.7,
				_mats["asphalt"], Vector3(0.1326 * side, 0.0, 0.0))
		# 檐口深色封板（坡脚收边，破「墙顶直接接天」；第 3 轮判图 #6：
		# 出挑 0.15——封板外移 z1+0.35 且坡板 6.4→6.7 延到墙皮外）
		var eave_z: float = z1 + 0.35 if side > 0.0 else z0 - 0.35
		_place_box(w, (x0 + x1) * 0.5, 6.02, eave_z, 31.4, 0.35, 0.3, _mats["dark"])
		# 坡面瓦楞线（第 3 轮判图 #6：深色楞线 ×10 沿坡，沥青瓦垄语汇）
		for k in 10:
			var rx: float = x0 + 1.5 + 2.9 * float(k)
			_place_box(w, rx, 6.66, mid_z + side * 3.05, 0.14, 0.1, 6.5,
					_mats["dark"], Vector3(0.1326 * side, 0.0, 0.0))
	_place_box(w, (x0 + x1) * 0.5, 7.1, mid_z, 31.0, 0.4, 0.95, _mats["asphalt"])
	for gx in [x0 + 0.25, x1 - 0.25]:   # 山墙阶梯三角（双坡的判读锚点）
		for k in 5:
			var zl: float = (z1 - z0 + 0.4) * (1.0 - float(k + 1) / 5.0) + 0.35
			_place_box(w, gx, 6.28 + 0.16 * float(k), mid_z, 0.5, 0.16, zl,
					_mats["camo"])
	# 写实化第四轮：可见层换 Blender 建模版（缺模型保留上面方块版，碰撞不变）
	PBR.swap_building(w, n0, "barracks", Vector3(-114.0, 0.0, -24.0),
			[[x0, x1, z0, z1, 0.0, h]])


## 2.2m 混凝土预制板围墙北/南/西三面（北墙中段让隧道口分 2 段注册）；
## 板缝竖条 ×间隔 2.4（凸 0.05 靠光影读缝）
func _camp_wall(w) -> void:
	var wq := -130.15   # 西墙中心（东皮 −129.9 探入板房西墙外皮 −130 共面 0.1 防闪）
	# 北墙 2 段（隧道口 x∈[−119.75,−116.25] 让空）+ 南墙 + 西墙 = 围墙 4 条
	# 北墙 2 段：[−130.4,−119.75] 与 [−116.25,−98]（隧道口 x∈[−119.75,−116.25] 让空）
	for seg in [[-125.08, 10.65], [-107.13, 10.62]]:
		_place_box(w, seg[0], 1.1, -41.75, seg[1], 2.2, 0.5, _mats["concrete"])
		_obstacle(w, seg[0], -41.75, seg[1] * 0.5, 0.25, 2.2)
	_place_box(w, -114.2, 1.1, 5.75, 32.5, 2.2, 0.5, _mats["concrete"])
	_obstacle(w, -114.2, 5.75, 16.25, 0.25, 2.2)
	_place_box(w, wq, 1.1, -18.0, 0.5, 2.2, 48.0, _mats["concrete"])
	_obstacle(w, wq, -18.0, 0.25, 24.0, 2.2)
	# 板缝竖条（同材质凸条：北/南沿 x 每 2.4、西沿 z 每 2.4）
	for k in 14:
		var px := -129.0 + 2.4 * float(k)
		_place_box(w, px, 1.1, -42.05, 0.16, 1.9, 0.1, _mats["concrete"])
		_place_box(w, px - 0.4, 1.1, 6.05, 0.16, 1.9, 0.1, _mats["concrete"])
	for k in 20:
		_place_box(w, -130.55, 1.1, -41.4 + 2.4 * float(k), 0.1, 1.9, 0.16,
				_mats["concrete"])


## 维修隧道口：3.5×3 混凝土拱缘洞门（近黑背板复用 asphalt=hd_dam 洞龛 _mat_void
## 同款语义）+ 红闸框；拱缘墙 2 条注册（门洞净宽 1.8 可进，本轮只做结构不做撤离点）
func _camp_tunnel(w) -> void:
	for seg in [[-119.75, -118.9], [-117.1, -116.25]]:   # 拱缘墙段区间
		var tcx: float = (seg[0] + seg[1]) * 0.5
		_place_box(w, tcx, 1.5, -42.2, 0.85, 3.0, 1.2, _mats["concrete"])
		_obstacle(w, tcx, -42.2, 0.425, 0.6, 3.0)
	_place_box(w, -118.0, 1.5, -42.4, 3.5, 3.0, 0.3, _mats["asphalt"])
	for sz in [-118.9, -117.1]:
		_place_box(w, sz, 1.5, -41.85, 0.35, 3.0, 0.35, _mats["red"])
	_place_box(w, -118.0, 2.95, -41.85, 1.8, 0.35, 0.35, _mats["red"])


## 东门哨位：双混凝土门柱 + 锈橙横桁门楣 + 柱顶警灯小盒（面向地图中心的伏击位）
func _camp_gate(w) -> void:
	for gz in [-28.0, -20.0]:
		_place_box(w, -97.7, 1.75, gz, 0.6, 3.5, 0.6, _mats["concrete"])
		_obstacle(w, -97.7, gz, 0.3, 0.3, 3.5)
		_place_box(w, -97.7, 3.65, gz, 0.35, 0.25, 0.35, _mats["red"])
	_place_box(w, -97.7, 3.9, -24.0, 0.6, 0.8, 8.6, _mats["corten"])


## 帐篷区×6 两排三列（第 2 轮判图 #7：独立成簇 4-6 顶）+ 火堆石圈
func _camp_tents(w) -> void:
	for tz in [-3.0, 1.5]:
		for tx in [-124.0, -117.0, -110.0]:
			_tent(w, tx, tz)
			_obstacle(w, tx, tz, 3.0, 2.0, 2.3)
	_place_box(w, -117.0, 0.11, -1.0, 1.7, 0.22, 1.7, _mats["dark"])
	_place_box(w, -117.0, 0.28, -0.7, 1.2, 0.18, 0.18, _mats["dark"],
			Vector3(0.0, 0.5, 0.0))
	_place_box(w, -116.6, 0.28, -1.3, 1.2, 0.18, 0.18, _mats["dark"],
			Vector3(0.0, -0.4, 0.0))


func _tent(w, x: float, z: float) -> void:
	# 人字坡两斜板（坡角 atan(0.9/2)≈0.423：脊 2.3/檐 1.4）+ 脊盖 + 端头门帘垂片
	for side in [-1.0, 1.0]:
		_place_box(w, x, 1.85, z + side * 1.05, 6.2, 0.12, 2.35, _mats["canvas"],
				Vector3(0.423 * side, 0.0, 0.0))
	_place_box(w, x, 2.32, z, 6.3, 0.1, 0.34, _mats["canvas"])
	_place_box(w, x - 3.06, 0.95, z, 0.12, 1.6, 3.5, _mats["canvas"])
	# 第 2 轮判图 #16：放射状拉绳+地钉小件+底部暗色裙边（接触暗带代 AO）——
	# 第 3 轮判图 #7：0.05 细绳远读不出——加粗 0.09、裙边 0.18
	for k in 8:
		var ang := TAU * float(k) / 8.0 + 0.4
		var gx := x + cos(ang) * 3.4
		var gz := z + sin(ang) * 2.5
		_place_box(w, (x + gx) * 0.5, 1.1, (z + gz) * 0.5, 0.09, 1.7, 0.09,
				_mats["dark"], Vector3(0.0, -ang, 0.62))
		_place_box(w, gx, 0.08, gz, 0.18, 0.16, 0.18, _mats["dark"])
	for side in [-1.0, 1.0]:   # 帐底接触暗带（贴地深色裙边压住悬浮感）
		_place_box(w, x, 0.09, z + side * 1.9, 6.3, 0.18, 0.34, _mats["dark"])


## 临时指挥处披屋 6×5×3.2：贴板房西山墙外（x∈[−136,−130]×z∈[−19,−14]），
## 南墙门洞贴西南角仍凑 3 条障碍；屋顶杆状天线×2
func _camp_annex(w) -> void:
	_place_box(w, -133.0, 1.6, -18.75, 6.0, 3.2, 0.5, _mats["camo"])
	_obstacle(w, -133.0, -18.75, 3.0, 0.25, 3.2)
	_place_box(w, -133.0, 1.6, -14.25, 6.0, 3.2, 0.5, _mats["camo"])
	_obstacle(w, -133.0, -14.25, 3.0, 0.25, 3.2)
	_place_box(w, -135.75, 1.6, -16.5, 0.5, 3.2, 4.5, _mats["camo"])
	_obstacle(w, -135.75, -16.5, 0.25, 2.25, 3.2)
	# 南门洞（x∈[−136,−134]）+ 单坡顶（北高南低披水）+ 天线两根
	_place_box(w, -135.0, 2.95, -14.25, 2.0, 0.5, 0.5, _mats["camo"])
	_place_box(w, -133.0, 3.4, -16.5, 6.6, 0.18, 5.4, _mats["asphalt"],
			Vector3(0.32, 0.0, 0.0))
	for ax in [-134.4, -131.8]:
		_cyl(w, _mesh_pole, Vector3(ax, 3.5 + 2.2, -16.5), _mats["white"],
				Vector3(0.7, 0.55, 0.7))
		_place_box(w, ax, 5.35, -16.5, 1.0, 0.05, 0.05, _mats["dark"])


## 墙外军用卡车（base 卡车 7 盒语言：黄货厢+红车头+6 轮，西墙外 (−135.5,−6)
## 距 wild 容器 (−144,−10) 9.6m 不嵌 loot 盒）
func _camp_truck(w) -> void:
	_place_box(w, -137.4, 1.9, -6.0, 5.2, 2.2, 2.4, _mats["yellow"])
	_place_box(w, -133.9, 1.35, -6.0, 1.8, 2.0, 2.3, _mats["red"])
	for wx in [-139.2, -137.4, -134.3]:
		for sd in [-1.0, 1.0]:
			_place_box(w, wx, 0.45, -6.0 + sd * 1.05, 0.6, 0.9, 0.3, _mats["dark"])
	_obstacle(w, -135.5, -6.0, 3.6, 1.3, 3.0)


# ================= ② 主变电站（大电） =================

func _substation(w) -> void:
	_pave(w, 111.0, -15.0, 30.0, 34.0)
	# 变压器区铺装分格（第 3 轮判图 #8：大电场地平涂——纵横深色分格缝）
	for k in 4:
		_place_box(w, 100.0 + 6.5 * float(k), GROUND_TOP + 0.01, -18.2, 0.12,
				0.02, 21.0, _mats["dark"])
	for kz in 3:
		_place_box(w, 110.0, GROUND_TOP + 0.01, -28.5 + 10.5 * float(kz), 27.0,
				0.02, 0.12, _mats["dark"])
	# 两列变压器间电缆沟盖板带（第 3 轮判图 #5：走廊 10m+ 空读——一条通长
	# 沟盖板定义出「母线走廊」；z=−17.9 让开 loot 盒 (107,−19) 半径，纯视觉不注册）
	_place_box(w, 110.0, GROUND_TOP + 0.02, -17.9, 27.0, 0.08, 1.5, _mats["dark"])
	for k in 9:
		_place_box(w, 97.5 + 2.9 * float(k), GROUND_TOP + 0.06, -17.9, 0.1,
				0.04, 1.5, _mats["concrete"])
	_sub_control(w)
	_sub_transformers(w)
	_sub_gantries(w)
	_sub_fence(w)
	_sub_forklift(w)


## 单层大平顶主控楼 22×12×5：北 1 + 南 2（3m 门洞 x∈[106,109]）+ 西 1 + 东 1
## = 5 段障碍；南窗×5 + 红门楣 + 女儿墙压顶 + 屋顶卧式白罐机组×2 + 楼内机柜列
func _sub_control(w) -> void:
	var n0: int = w.get_child_count()
	var x0 := 104.0
	var x1 := 126.0
	var z0 := -26.0
	var z1 := -12.0
	var h := 5.0
	var mid_z := (z0 + z1) * 0.5
	_place_box(w, (x0 + x1) * 0.5, h * 0.5, z0 + WALL_T * 0.5, x1 - x0, h, WALL_T,
			_mats["concrete"])
	_obstacle(w, (x0 + x1) * 0.5, z0 + WALL_T * 0.5, (x1 - x0) * 0.5, WALL_T * 0.5, h)
	for seg in [[105.0, 2.0], [117.5, 17.0]]:   # 南墙 [104,106]+[109,126]
		_place_box(w, seg[0], h * 0.5, z1 - WALL_T * 0.5, seg[1], h, WALL_T,
				_mats["concrete"])
		_obstacle(w, seg[0], z1 - WALL_T * 0.5, seg[1] * 0.5, WALL_T * 0.5, h)
	for side in [-1.0, 1.0]:
		var wx: float = x0 + WALL_T * 0.5 if side < 0.0 else x1 - WALL_T * 0.5
		_place_box(w, wx, h * 0.5, mid_z, WALL_T, h, z1 - z0 - WALL_T * 2.0,
				_mats["concrete"])
		_obstacle(w, wx, mid_z, WALL_T * 0.5, (z1 - z0 - WALL_T * 2.0) * 0.5, h)
	# 门洞上方补墙 + 红门楣（悬空不注册）
	_place_box(w, 107.5, 4.2, z1 - WALL_T * 0.5, 3.0, 1.6, WALL_T, _mats["concrete"])
	_place_box(w, 107.5, 3.7, z1 + 0.1, 3.2, 0.6, 0.15, _mats["red"])
	# 南窗×5（门洞以东等距；第 2 轮判图 #15：通长深色窗带被读塑料板——
	# 加竖向分格梃×2+中横梃+窗顶反光线（glass 细条），分格明暗带出玻璃感）
	for k in 5:
		var wx := 111.0 + 3.25 * float(k)
		_place_box(w, wx, 2.2, z1 + 0.08, 2.0, 2.4, 0.14, _mats["dark"])
		for mx in [-0.55, 0.55]:
			_place_box(w, wx + mx, 2.2, z1 + 0.14, 0.14, 2.4, 0.06, _mats["white"])
		_place_box(w, wx, 2.2, z1 + 0.14, 2.0, 0.12, 0.06, _mats["white"])
		_place_box(w, wx, 3.32, z1 + 0.12, 1.9, 0.16, 0.05, _mats["glass"])
	# 西立面成排窗带×4 + 北墙高通长窗带（第 3 轮判图 #4：玩家面向的西立面
	# 无窗读成纯方块——补窗带与分格梃，呼应参考图 2-3 层窗）
	for k in 4:
		var wy := -23.0 + 2.8 * float(k)
		_place_box(w, x0 - 0.08, 2.2, wy, 0.14, 2.0, 1.9, _mats["dark"])
		_place_box(w, x0 - 0.14, 2.2, wy, 0.06, 2.0, 0.14, _mats["white"])
		_place_box(w, x0 - 0.12, 3.28, wy, 0.05, 0.16, 1.8, _mats["glass"])
	_place_box(w, (x0 + x1) * 0.5, 4.0, z0 - 0.08, x1 - x0 - 2.0, 1.2, 0.14,
			_mats["dark"])
	for k in 7:
		_place_box(w, 106.0 + 3.0 * float(k), 4.0, z0 - 0.14, 0.14, 1.2, 0.06,
				_mats["white"])
	# 平顶出檐 + 女儿墙压顶圈边
	_place_box(w, (x0 + x1) * 0.5, h + 0.2, mid_z, x1 - x0 + 0.6, 0.4,
			z1 - z0 + 0.6, _mats["concrete"])
	for edge in [[(x0 + x1) * 0.5, z0 + 0.25, x1 - x0, 0.2],
			[(x0 + x1) * 0.5, z1 - 0.25, x1 - x0, 0.2],
			[x0 + 0.25, mid_z, 0.2, z1 - z0],
			[x1 - 0.25, mid_z, 0.2, z1 - z0]]:
		_place_box(w, edge[0], h + 0.55, edge[1], edge[2], 0.3, edge[3],
				_mats["concrete"])
	# 楼内小机房：机柜列×3（深灰盒）+ 顶蓝灰指示点（glass 反光小片）
	for k in 3:
		var mx := 105.6 + 1.5 * float(k)
		_place_box(w, mx, 1.1, -25.0, 1.2, 2.2, 0.7, _mats["dark"])
		_place_box(w, mx, 2.28, -25.0, 0.16, 0.16, 0.05, _mats["glass"])
	# 屋顶两台卧式白罐机组（白罐 cylinder 语义复用 base TANKS 语言）+
	# 立式小水塔（第 3 轮判图 #4：屋顶设备远读不足——塔身+锥顶+四腿剪影）
	for tx in [112.0, 118.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_silo
		mi.rotation.z = PI * 0.5
		mi.scale = Vector3(0.8 / 3.2, 4.0 / 15.0, 0.8 / 3.2)
		mi.position = Vector3(tx, h + 0.4 + 0.8, -21.5)
		mi.set_surface_override_material(0, _mats["white"])
		w.add_child(mi)
	_cyl(w, _mesh_silo, Vector3(122.5, h + 0.4 + 1.6, -22.5), _mats["white"],
			Vector3(0.45, 3.2 / 15.0, 0.45))
	_cyl(w, _mesh_cone, Vector3(122.5, h + 4.0, -22.5), _mats["white"],
			Vector3(0.42, 0.8 / 3.0, 0.42))
	for k in 4:   # 水塔四腿
		var ang := TAU * float(k) / 4.0 + 0.79
		_place_box(w, 122.5 + cos(ang) * 1.05, (h + 0.4) * 0.5, -22.5 + sin(ang) * 1.05,
				0.18, h + 0.4, 0.18, _mats["dark"])
	# 写实化第四轮：可见层换 Blender 建模版（缺模型保留上面方块版，碰撞不变）
	PBR.swap_building(w, n0, "sub_ctrl", Vector3(115.0, 0.0, -19.0),
			[[x0, x1, z0, z1, 0.0, h]])


## 户外变压器阵列×8（第 2 轮判图 #11：双列×4 排读出组团+基座黄黑警示条；
## 北列 z=−29 / 南列 z=−7.5，列间 z≈−20 走廊让巡逻点 (100,−20)；每台=基座
## +深灰蓝本体+两侧散热片棱条×5+顶部瓷套管 4 节叠串（#10），整台含基座注册
func _sub_transformers(w) -> void:
	for tx in [99.0, 106.0, 113.0, 120.0]:
		for tz in [-29.0, -7.5]:
			_transformer(w, tx, tz)
			_obstacle(w, tx, tz, 1.3, 1.6, 2.6)


func _transformer(w, x: float, z: float) -> void:
	_place_box(w, x, 0.15, z, 2.6, 0.3, 3.2, _mats["concrete"])
	_place_box(w, x, 1.45, z, 2.2, 2.3, 2.8, _mats["panel"])
	for side in [-1.0, 1.0]:
		# 散热竖条分片可读（第 3 轮判图 #5：5 连条糊成一片——改 2+3 分片
		# 留 0.34 缝，远读作两片散热器组）
		for k in 5:
			var gap := 0.12 if k == 2 else 0.0
			_place_box(w, x - 0.86 + 0.4 * float(k) + gap, 1.35, z + side * 1.52,
					0.26, 1.9, 0.14, _mats["panel"])
		_place_box(w, x, 1.35, z + side * 1.52, 2.3, 2.1, 0.05, _mats["dark"])
		# 基座黄黑警示条（第 2 轮判图 #11：交替 4 段贴基座两长侧）
		for k in 4:
			_place_box(w, x - 0.9 + 0.6 * float(k), 0.15, z + side * 1.68,
					0.4, 0.34, 0.06, _mats["yellow"] if k % 2 == 0 else _mats["asphalt"])
	for k in 3:   # 顶部瓷套管：4 节小盘叠串加大一号（第 2 轮判图 #10）
		var bx := x - 0.7 + 0.7 * float(k)
		for j in 4:
			_cyl(w, _mesh_insulator, Vector3(bx, 2.72 + 0.26 * float(j), z),
					_mats["porcelain"])


## 门式桁架母线桥×5（第 2 轮判图 #5：2 榀远景剪影密度不足且锈橙被裸山吃掉
## ——榀数 5、杆件全面加粗、锈橙材质已上调半档）。柱对 z=−11/−26.8
## （北柱线从 −25 挪出主控楼 z∈[−26,−12] 体内——原 (121,−25) 柱穿楼，本轮
## 连坐修正）；梁横跨两列变压器上空。只注册 10 柱。
func _sub_gantries(w) -> void:
	for gx in [98.0, 103.5, 109.0, 114.5, 120.0]:
		for gz in [-11.0, -26.8]:
			_place_box(w, gx, 4.5, gz, 0.7, 9.0, 0.7, _mats["corten"])
			_place_box(w, gx, 0.25, gz, 1.1, 0.5, 1.1, _mats["concrete"])
			_obstacle(w, gx, gz, 0.35, 0.35, 9.0)
		_place_box(w, gx, 9.5, -18.9, 0.6, 1.2, 16.6, _mats["corten"])
		_place_box(w, gx, 8.65, -18.9, 0.9, 0.4, 15.8, _mats["corten"])
		# 梁下加劲斜杆×4（远景桁架「X 纹」密度，破工字梁单线剪影）
		for k in 4:
			var vz := -13.5 - 3.4 * float(k)
			_place_box(w, gx, 9.05, vz, 0.35, 1.3, 0.35, _mats["corten"],
					Vector3(0.0, 0.0, 0.8 if k % 2 == 0 else -0.8))
		for sz in [-14.0, -18.9, -23.8]:
			for k in 6:   # 悬垂绝缘子串 6 盘加粗（第 2 轮判图 #10）
				_cyl(w, _mesh_insulator, Vector3(gx, 8.9 - 0.3 * float(k), sz),
						_mats["porcelain"])
		for bx in [-0.45, 0.0, 0.45]:   # 顶相母线三联杆（加粗）
			_place_box(w, gx + bx, 10.15, -18.9, 0.1, 0.1, 16.0, _mats["dark"])
	# 相母线到两列变压器的跳线（第 4 轮判图 #2：大电焦点面细件——沿列三相
	# 通长引下线 y7.9 + 每台中相套管顶竖引线，纯视觉细杆）
	for jz in [-14.0, -18.9, -23.8]:
		_place_box(w, 109.5, 7.9, jz, 25.0, 0.07, 0.07, _mats["dark"])
	for tx in [99.0, 106.0, 113.0, 120.0]:
		for tz in [-29.0, -7.5]:
			for k in 3:
				var jx := float(tx) - 0.7 + 0.7 * float(k)
				_place_box(w, jx, 5.7, tz, 0.06, 4.3, 0.06, _mats["dark"])


## 链节围栏 1.9m（竖柱间隔 2.5 + 三道横杆）：圈地 x∈[96,126]×z∈[−32,2]，
## 西段 z∈[−26,−14] 内凹至 x=98.5 让既有 wreck (95,−20)（AABB 东缘 ≈97.18，
## 留 1.32m 视觉间隙）；西面双开门 z∈[−8,−2] 让空。纯视觉网面不注册碰撞
## （不注册即全弹道直穿——纯视觉网面不构成战术掩体，hd_dam.gd:16-17 先例）
func _sub_fence(w) -> void:
	_fence_run(w, 96.0, -32.0, 126.0, -32.0)
	_fence_run(w, 96.0, 2.0, 126.0, 2.0)
	_fence_run(w, 126.0, -32.0, 126.0, 2.0)
	_fence_run(w, 96.0, -32.0, 96.0, -26.0)
	_fence_run(w, 96.0, -26.0, 98.5, -26.0)
	_fence_run(w, 98.5, -26.0, 98.5, -14.0)   # 内凹段
	_fence_run(w, 96.0, -14.0, 98.5, -14.0)
	_fence_run(w, 96.0, -14.0, 96.0, -8.0)
	_fence_run(w, 96.0, -2.0, 96.0, 2.0)
	for gz in [-8.0, -2.0]:   # 双开网门门框柱
		_place_box(w, 96.0, 1.05, gz, 0.16, 2.1, 0.16, _mats["dark"])


func _fence_run(w, x0: float, z0: float, x1: float, z1: float) -> void:
	var len := Vector2(x1 - x0, z1 - z0).length()
	var n := int(len / 2.5) + 1
	var along_x := absf(x1 - x0) > absf(z1 - z0)
	for k in n:
		var t := float(k) / float(n - 1)
		var px := lerpf(x0, x1, t)
		var pz := lerpf(z0, z1, t)
		# 第 2 轮判图 #17：立柱 0.08→0.14 加粗 + 柱顶斜刺丝两根（围合感成立）
		_place_box(w, px, 0.95, pz, 0.14, 1.9, 0.14, _mats["dark"])
		_place_box(w, px, 2.05, pz + 0.18, 0.05, 0.45, 0.05, _mats["dark"],
				Vector3(0.7 if along_x else 0.0, 0.0, 0.0 if along_x else 0.7))
	for ry in [0.45, 1.05, 1.7]:   # 三道横杆 0.06→0.1
		if along_x:
			_place_box(w, (x0 + x1) * 0.5, ry, z0, len, 0.1, 0.1, _mats["dark"])
		else:
			_place_box(w, x0, ry, (z0 + z1) * 0.5, 0.1, 0.1, len, _mats["dark"])


## 南院叉车+变电箱狙击位：黄叉车货叉抬起 1.6m + 灰变电箱 + 两阶 0.3 踏步坎
## （考证「经叉车上变电站房顶」的紧凑替代）；整组合并 1 条 AABB
func _sub_forklift(w) -> void:
	_place_box(w, 112.0, 0.9, -1.5, 1.8, 1.4, 1.1, _mats["yellow"])
	for sd in [-1.0, 1.0]:
		for wz in [-0.6, 0.6]:
			_place_box(w, 112.0 + sd * 0.75, 0.35, -1.5 + wz, 0.35, 0.7, 0.25,
					_mats["dark"])
	_place_box(w, 112.0, 1.95, -1.5, 0.5, 1.1, 0.5, _mats["dark"])
	for sd in [-1.0, 1.0]:   # 抬起的货叉 + 托盘
		_place_box(w, 113.6, 1.6, -1.5 + sd * 0.35, 1.4, 0.08, 0.12, _mats["panel"])
	_place_box(w, 113.9, 1.45, -1.5, 0.9, 0.12, 0.9, _mats["yellow"])
	_place_box(w, 115.4, 0.8, -1.5, 1.4, 1.6, 1.2, _mats["concrete"])
	for k in 2:   # 箱侧两阶踏步坎（0.3/0.6 二级跳点）
		_place_box(w, 114.1, 0.15 + 0.3 * float(k), -1.5, 0.9, 0.3, 0.5,
				_mats["concrete"])
	_obstacle(w, 113.6, -1.5, 2.6, 1.0, 1.6)


# ================= ③ 水泥厂（筒仓 + 渡槽） =================

func _cement(w) -> void:
	_pave(w, -99.0, 26.0, 46.0, 40.0)
	_cement_silos(w)
	_cement_bridge(w)
	_cement_main(w)
	_cement_dorm(w)
	_cement_yard(w)
	_cement_works(w)


## 仓底作业痕迹（第 2 轮判图 #14：近景杂物密度近乎零——散料锥堆×3 +
## 砂色锥堆×2（第 4 轮判图 #2：判图口径「砂色」改 yellow 系与水泥灰料分读）
## + 托盘组×4 + 一台装载机剪影，水泥厂「在产工厂」语汇）；装载机 ≥1.4m 注册
func _cement_works(w) -> void:
	# 仓列东南散料锥堆（水泥灰白散料，<1.4m 不注册）
	for sp in [[-118.0, 30.0, 2.4, 1.2], [-121.5, 33.5, 1.9, 0.9],
			[-116.0, 34.5, 1.6, 0.8]]:
		_pile(w, Vector3(sp[0], 0.0, sp[1]), Vector3(sp[2], sp[3], sp[2]),
				_mats["silo"])
	# 砂色锥堆×2（第 4 轮判图 #2：筒仓脚下砂色料堆）
	for sp in [[-119.5, 15.5, 2.0, 0.95], [-112.0, 27.5, 1.6, 0.8]]:
		_pile(w, Vector3(sp[0], 0.0, sp[1]), Vector3(sp[2], sp[3], sp[2]),
				_mats["yellow"])
	# 托盘组×4（仓列东侧转运位）
	for tp in [[-112.0, 12.0], [-111.2, 14.0], [-112.5, 16.5], [-110.8, 18.0]]:
		_place_box(w, tp[0], 0.08, tp[1], 1.3, 0.16, 1.0, _mats["yellow"],
				Vector3(0.0, 0.3 * float(tp[1]), 0.0))
		_place_box(w, tp[0] + 0.1, 0.45, tp[1] + 0.15, 0.9, 0.6, 0.7,
				_mats["dark"] if int(tp[1]) % 2 == 0 else _mats["silo"])
	# 装载机剪影（主楼西侧料场：yellow 车体+dark 轮×4+red 驾驶室+corten 铲斗）
	var lx := -107.5
	var lz := 26.0
	_place_box(w, lx, 0.95, lz, 3.0, 1.0, 1.9, _mats["yellow"])
	_place_box(w, lx - 0.6, 1.85, lz, 1.3, 0.9, 1.3, _mats["red"])
	for sd in [-1.0, 1.0]:
		for wx in [-0.9, 0.9]:
			_place_box(w, lx + wx, 0.4, lz + sd * 1.15, 0.7, 0.8, 0.35,
					_mats["dark"])
	_place_box(w, lx + 2.4, 0.95, lz, 1.6, 0.16, 2.2, _mats["corten"],
			Vector3(0.0, 0.0, 0.4))
	_place_box(w, lx + 2.6, 1.35, lz, 0.9, 0.7, 2.0, _mats["corten"])
	_obstacle(w, lx, lz, 2.6, 1.4, 2.3)


## 三联圆柱筒仓×3：r3.2×h15 直筒 + 3m 锥顶（总高 18m=中环第一高度）+
## 竖向筋条×8/仓通高 + 锈渍流挂×4/仓 + 锥底顶圈梁/锥顶盖帽/检修小设备/加粗
## 环形护栏（第 2 轮判图 #1：锥顶剪影首版远读只余细环——圈梁+盖帽+设备
## 三锚点把「15 直筒+3 锥顶」的制高剪影立起来）+ 仓间连廊方管
func _cement_silos(w) -> void:
	for sz in [10.5, 18.0, 25.5]:
		_cyl(w, _mesh_silo, Vector3(-116.0, 7.5, sz), _mats["silo"])
		_cyl(w, _mesh_cone, Vector3(-116.0, 16.5, sz), _mats["silo"])
		_obstacle(w, -116.0, sz, 3.2, 3.2, 18.0)
		for k in 8:   # 竖向筋条×8 通高（第 4 轮判图 #5：加宽 0.45、外凸 0.12
			# ——中景 100m 即可读出竖筋节奏）
			var ang := TAU * float(k) / 8.0 + 0.39
			_place_box(w, -116.0 + cos(ang) * 3.3, 7.5, sz + sin(ang) * 3.3,
					0.45, 15.0, 0.2, _mats["siloshade"],
					Vector3(0.0, PI * 0.5 - ang, 0.0))
		for k in 4:   # 锈渍流挂条（hd_dam 锈带语言；第 2 轮判图 #12：收窄压矮
			# + 三仓相位逐仓错开 0.5rad——首版四宽条在 250m 远景横向粘连被读成
			# 「红色跑道色带」，错相后每行至多一条不成带）
			var rang := TAU * float(k) / 4.0 + 0.8 + float(sz - 10.5) * 0.35
			_place_box(w, -116.0 + cos(rang) * 3.34, 2.4, sz + sin(rang) * 3.34,
					0.32, 4.2, 0.08, _mats["corten"],
					Vector3(0.0, PI * 0.5 - rang, 0.0))
		for k in 8:   # 锥底顶圈梁（8 段 dark 环——锥/筒交界的剪影轮廓线）
			var cang := TAU * float(k) / 8.0
			_place_box(w, -116.0 + cos(cang) * 3.15, 15.05, sz + sin(cang) * 3.15,
					2.5, 0.3, 0.3, _mats["dark"],
					Vector3(0.0, PI * 0.5 - cang, 0.0))
		# 锥顶盖帽 + 检修小设备 + 锥底平台环形护栏（加粗加密两道横杆；
		# 护栏立在锥底顶圈梁平台上 y15.2——首版悬在 y18.5 锥尖上空是错位）
		_cyl(w, _mesh_insulator, Vector3(-116.0, 18.25, sz), _mats["dark"],
				Vector3(2.4, 5.0, 2.4))
		_place_box(w, -115.2, 18.55, sz + 0.4, 1.0, 0.7, 0.8, _mats["white"])
		for k in 8:
			var gang := TAU * float(k) / 8.0
			_place_box(w, -116.0 + cos(gang) * 3.15, 15.6, sz + sin(gang) * 3.15,
					0.1, 0.85, 0.1, _mats["dark"])
			for hy in [15.4, 15.85]:
				_place_box(w, -116.0 + cos(gang + 0.39) * 3.1, hy,
						sz + sin(gang + 0.39) * 3.1, 2.5, 0.09, 0.09,
						_mats["dark"], Vector3(0.0, PI * 0.5 - gang - 0.39, 0.0))
	for bz in [14.25, 21.75]:   # 仓间顶部连廊小方管
		_place_box(w, -116.0, 15.4, bz, 0.8, 0.8, 7.5, _mats["dark"])


## 斜撑渡槽传送带：二层平台 5.5m 爬到中仓顶 15m（倾角按实际几何 ~20°——
## atan(9.5/25.55)）；梯形桁架（上下弦+斜腹杆，锈橙哑光）+ 两端轮罩方盒 +
## 脚下 A 字支腿 2 组（世界坐标独立摆放保持铅垂）
func _cement_bridge(w) -> void:
	var start := Vector3(-88.0, 5.5, 11.75)
	var end := Vector3(-113.0, 15.0, 17.0)
	var flat := Vector3(end.x - start.x, 0.0, end.z - start.z)
	var flen := flat.length()
	var slope := atan2(end.y - start.y, flen)
	var pivot := Node3D.new()
	pivot.position = start
	pivot.rotation.y = atan2(flat.x, flat.z)
	w.add_child(pivot)
	var arm := Node3D.new()
	arm.rotation.x = -slope   # 本地 +z 端抬升
	pivot.add_child(arm)
	var tlen := 27.0
	_place_box(arm, 0.0, 0.0, tlen * 0.5, 0.5, 0.32, tlen, _mats["corten"])
	_place_box(arm, 0.0, 1.5, tlen * 0.5, 0.5, 0.32, tlen, _mats["corten"])
	for k in 14:   # 斜腹杆列（交替八字撑；第 2 轮判图 #12/#4 双读：腹杆 10→14
		# 加密——中景读出镂空桁架网格，而非两条实心红杆粘成「色带」）
		var vz := 0.95 + 1.85 * float(k)
		_place_box(arm, 0.0, 0.75, vz, 0.16, 1.7, 0.16, _mats["corten"],
				Vector3(0.65 if k % 2 == 0 else -0.65, 0.0, 0.0))
	for ez in [0.0, tlen]:   # 两端头轮罩方盒（第 2 轮判图 #4：罩壳压白——
		# 大面积 corten 亮面被读成浅米罩壳，缩一号换 dark，锈橙留给弦杆/腹杆）
		_place_box(arm, 0.0, 0.75, ez, 1.3, 1.3, 1.3, _mats["dark"])
	_place_box(arm, 0.0, 0.75, tlen * 0.5, 1.2, 0.14, tlen, _mats["dark"])
	for frac in [0.31, 0.465, 0.62]:   # 交叉斜撑支腿×3 组（第 4 轮判图 #10：
		# 2 组 0.45 杆在 100m+ 全景读不出剪影——加第三组+杆件 0.55 加粗）
		var top: Vector3 = start + (end - start) * frac
		for sd in [-1.0, 1.0]:
			for cr in [-1.0, 1.0]:   # X 交叉两杆
				_place_box(w, top.x + sd * 0.85, top.y * 0.5, top.z,
						0.55, top.y * 1.06, 0.55, _mats["corten"],
						Vector3(0.0, 0.0, 0.34 * sd * cr))
			_place_box(w, top.x + sd * 0.85, top.y * 0.55, top.z, 0.48, 0.48, 2.3,
					_mats["corten"])
		_place_box(w, top.x, top.y * 0.5, top.z, 3.5, 0.4, 0.4, _mats["corten"])


## 主厂房 16×26 两层黄主楼：北墙 4 卷帘门洞让空成 2 段（西端/东端门洞贴端 +
## 中间双门并排）凑 5 段；二层平台朝北料场 + 外挂钢爬梯两段（公开制高点跳点位）
func _cement_main(w) -> void:
	var n0: int = w.get_child_count()
	var x0 := -92.0
	var x1 := -76.0
	var z0 := 14.0
	var z1 := 40.0
	var h := 10.0
	var mid_z := (z0 + z1) * 0.5
	# 北墙 2 短段（[−89,−87]/[−81,−79] 门墩）+ 门洞上补墙；南/西/东整段
	for seg in [[-88.0, 2.0], [-80.0, 2.0]]:
		_place_box(w, seg[0], h * 0.5, z0 + WALL_T * 0.5, seg[1], h, WALL_T,
				_mats["yellow"])
		_obstacle(w, seg[0], z0 + WALL_T * 0.5, seg[1] * 0.5, WALL_T * 0.5, h)
	for fill in [[-90.5, 3.0], [-84.0, 6.0], [-77.5, 3.0]]:
		_place_box(w, fill[0], 6.65, z0 + WALL_T * 0.5, fill[1], 6.7, WALL_T,
				_mats["yellow"])
	_place_box(w, (x0 + x1) * 0.5, h * 0.5, z1 - WALL_T * 0.5, x1 - x0, h, WALL_T,
			_mats["yellow"])
	_obstacle(w, (x0 + x1) * 0.5, z1 - WALL_T * 0.5, (x1 - x0) * 0.5, WALL_T * 0.5, h)
	for side in [-1.0, 1.0]:
		var wx: float = x0 + WALL_T * 0.5 if side < 0.0 else x1 - WALL_T * 0.5
		_place_box(w, wx, h * 0.5, mid_z, WALL_T, h, z1 - z0 - WALL_T * 2.0,
				_mats["yellow"])
		_obstacle(w, wx, mid_z, WALL_T * 0.5, (z1 - z0 - WALL_T * 2.0) * 0.5, h)
	# 卷帘门×4（红门楣 + 深色半开卷帘片）
	for dx in [-90.5, -85.5, -82.5, -77.5]:
		_place_box(w, dx, 2.95, z0 + 0.1, 3.0, 0.7, 0.15, _mats["red"])
		_place_box(w, dx, 1.1, z0 + 0.12, 2.8, 2.2, 0.1, _mats["dark"])
	# 二层楼板 + 南面横带窗×5 + 平屋顶出檐
	_place_box(w, -84.0, 5.3, 27.25, 15.0, 0.4, 25.0, _mats["concrete"])
	for k in 5:
		_place_box(w, -90.0 + 3.5 * float(k), 7.0, z1 + 0.08, 2.6, 1.8, 0.14,
				_mats["dark"])
	_place_box(w, -84.0, h + 0.2, 27.0, 17.0, 0.4, 27.0, _mats["yellow"])
	# 二层平台 5.5m 朝北料场 + 支撑柱 2（注册）+ 外挂钢爬梯两段（纯视觉）
	_place_box(w, -88.0, 5.3, 12.25, 8.0, 0.4, 3.5, _mats["concrete"])
	_place_box(w, -88.0, 5.55, 10.9, 8.0, 0.1, 0.6, _mats["dark"])
	for px in [-90.8, -85.2]:
		_place_box(w, px, 2.65, 10.9, 0.6, 5.3, 0.6, _mats["concrete"])
		_obstacle(w, px, 10.9, 0.3, 0.3, 5.3)
	for k in 2:
		_place_box(w, -88.0, 1.35 + 2.75 * float(k), 10.42, 0.8, 2.7, 0.1,
				_mats["dark"])
	# 写实化第四轮：可见层换 Blender 建模版（缺模型保留上面方块版，碰撞不变）
	PBR.swap_building(w, n0, "cement_main", Vector3(-84.0, 0.0, 27.0),
			[[x0, x1, z0, z1, 0.0, h]])


## 宿舍小楼 8×6×5：贴主楼南墙外（z∈[40,46]，北墙探入主楼南墙 0.05 防共面）；
## 单门洞朝西贴南端凑 4 段障碍 + 两窗 + 门口小索降平台
func _cement_dorm(w) -> void:
	var n0: int = w.get_child_count()
	var x0 := -90.0
	var x1 := -82.0
	var h := 5.0
	_place_box(w, -86.0, h * 0.5, 40.15, x1 - x0, h, 0.4, _mats["yellow"])
	_obstacle(w, -86.0, 40.15, (x1 - x0) * 0.5, 0.2, h)
	_place_box(w, -86.0, h * 0.5, 45.75, x1 - x0, h, 0.5, _mats["yellow"])
	_obstacle(w, -86.0, 45.75, (x1 - x0) * 0.5, 0.25, h)
	_place_box(w, -89.75, h * 0.5, 42.5, 0.5, h, 4.2, _mats["yellow"])
	_obstacle(w, -89.75, 42.5, 0.25, 2.1, h)
	_place_box(w, -82.25, h * 0.5, 43.25, 0.5, h, 5.0, _mats["yellow"])
	_obstacle(w, -82.25, 43.25, 0.25, 2.5, h)
	# 西门洞（z∈[44.6,46]）补墙 + 门楣 + 南墙两窗 + 单坡顶 + 索降平台
	_place_box(w, -89.75, 4.05, 45.3, 0.5, 1.9, 1.4, _mats["yellow"])
	_place_box(w, -89.75, 3.5, 45.3, 0.5, 0.6, 1.5, _mats["red"])
	for k in 2:
		_place_box(w, -87.5 + 3.0 * float(k), 2.3, 46.05, 1.4, 1.6, 0.12,
				_mats["dark"])
	_place_box(w, -86.0, h + 0.15, 43.1, 8.6, 0.3, 6.4, _mats["asphalt"],
			Vector3(0.0, 0.0, 0.18))
	_place_box(w, -91.2, 0.15, 45.0, 1.9, 0.3, 2.6, _mats["yellow"])
	_place_box(w, -90.5, 2.2, 45.0, 0.06, 4.2, 0.06, _mats["dark"],
			Vector3(0.0, 0.0, 0.5))
	# 写实化第四轮：可见层换 Blender 建模版（缺模型保留上面方块版，碰撞不变）
	PBR.swap_building(w, n0, "cement_dorm", Vector3(-86.0, 0.0, 43.0),
			[[x0, x1, 40.0, 46.0, 0.0, h]])


## 垃圾场（西南角 x∈[−122,−114]×z∈[38,46]）：瓦砾堆×2（大堆注册 1 条）+
## 废钢件杂盒×5 + 报废水泥罐车（卧罐+四轮，corten 锈橙）；纯视觉不放 loot 点
## （该角落 zone_at 落 wild 穷档）
func _cement_yard(w) -> void:
	_pile(w, Vector3(-120.0, 0.0, 41.0), Vector3(2.6, 1.5, 2.1), _mats["dark"])
	_obstacle(w, -120.0, 41.0, 2.6, 2.1, 1.5)
	_pile(w, Vector3(-116.5, 0.0, 44.5), Vector3(1.9, 1.2, 1.7), _mats["dark"])
	for k in 5:
		_place_box(w, -121.5 + 1.4 * float(k), 0.3 + 0.2 * float(k % 3), 43.5,
				0.9, 0.7, 0.8, _mats["corten"] if k % 2 == 0 else _mats["dark"],
				Vector3(0.0, 0.4 * float(k % 4), 0.0))
	# 主楼北料场砂石堆（与垃圾山合计 2 条障碍）
	_pile(w, Vector3(-95.0, 0.0, 9.0), Vector3(3.0, 1.8, 2.2), _mats["silo"])
	_obstacle(w, -95.0, 9.0, 3.0, 2.2, 1.8)
	# 报废水泥罐车：卧罐（筒仓网格缩放复用，轴沿 x）+ 四轮暗盒
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_silo
	mi.rotation.z = PI * 0.5
	mi.scale = Vector3(0.6 / 3.2, 7.0 / 15.0, 0.6 / 3.2)
	mi.position = Vector3(-118.5, 0.85, 44.0)
	mi.set_surface_override_material(0, _mats["corten"])
	w.add_child(mi)
	for wx in [-121.0, -116.0]:
		for sd in [-1.0, 1.0]:
			_place_box(w, wx, 0.4, 44.0 + sd * 1.0, 0.7, 0.8, 0.3, _mats["dark"])


# ================= ④ 游客中心（L 形玻璃楼 + 南广场） =================

func _visitor(w) -> void:
	_visitor_main(w)
	_visitor_plaza(w)
	_visitor_park(w)


## L 形两层：主翼 24×9.5×8 @ x∈[76,100]×z∈[33,42.5] + 门厅西端通高 9.5 +
## 短翼 10×11.5 南折 @ x∈[96,106]×z∈[42.5,54]；一层落地玻璃幕墙 + 竖向白框棂
## + 二层白墙横带窗 + 北侧 3m 深挑檐薄板 + 檐下细钢柱×5；L 楼墙 6 段
func _visitor_main(w) -> void:
	var n0: int = w.get_child_count()
	var x0 := 76.0
	var x1 := 100.0
	var z0 := 33.0
	var z1 := 42.5
	var h1 := 4.2      # 一层玻璃幕墙段高
	var h := 8.0       # 主翼高
	var mid_z := (z0 + z1) * 0.5
	# —— 主翼北墙 / 南墙：一层 glass + 二层 white（各 1 条通高障碍）
	for wz in [z0 + WALL_T * 0.5, z1 - WALL_T * 0.5]:
		_place_box(w, (x0 + x1) * 0.5, h1 * 0.5, wz, x1 - x0, h1, WALL_T,
				_mats["glass"])
		_place_box(w, (x0 + x1) * 0.5, h1 + (h - h1) * 0.5, wz, x1 - x0, h - h1,
				WALL_T, _mats["white"])
		_obstacle(w, (x0 + x1) * 0.5, wz, (x1 - x0) * 0.5, WALL_T * 0.5, h)
	# 幕墙竖向白框棂（第 2 轮判图 #3：间距 2.4→1.2 加密一倍 + 层线横梃通长，
	# 远景分格读出才不糊成「整块蓝灰塑料板」）
	for k in 21:
		var lx := 76.3 + 1.2 * float(k)
		for fz in [z0 - 0.09, z1 + 0.09]:
			_place_box(w, lx, h1 * 0.5, fz, 0.22, h1, 0.16, _mats["white"])
	for fz in [z0 - 0.12, z1 + 0.12]:   # 层线横梃（一层幕墙压顶）
		_place_box(w, (x0 + x1) * 0.5, h1, fz, x1 - x0, 0.4, 0.2, _mats["white"])
	# 二层白墙横带窗 + 分格竖梃（同语汇延伸到二层）
	for fz in [z0 - 0.09, z1 + 0.09]:
		_place_box(w, (x0 + x1) * 0.5, 6.4, fz, x1 - x0 - 1.6, 1.6, 0.14,
				_mats["dark"])
		for k in 11:
			_place_box(w, 77.6 + 2.4 * float(k), 6.4, fz + 0.04, 0.18, 1.6, 0.1,
					_mats["white"])
	# —— 主翼西墙（门厅段通高 9.5）：双开玻璃门洞 z∈[33.5,35.9] 贴北端留 1 段
	_place_box(w, x0 + WALL_T * 0.5, 4.75, 39.2, WALL_T, 9.5, 6.6, _mats["glass"])
	_obstacle(w, x0 + WALL_T * 0.5, 39.2, WALL_T * 0.5, 3.3, 9.5)
	_place_box(w, x0 + WALL_T * 0.5, 6.45, 34.7, WALL_T, 6.1, 2.4, _mats["glass"])
	for gz in [33.5, 35.9]:
		_place_box(w, x0 - 0.08, 1.75, gz, 0.14, 3.5, 0.18, _mats["white"])
	_place_box(w, x0 - 0.06, 4.35, 34.7, 0.1, 0.5, 2.6, _mats["white"])
	# —— 主翼东墙（短翼以北段）
	_place_box(w, x1 - WALL_T * 0.5, h1 * 0.5, mid_z, WALL_T, h1, z1 - z0 - WALL_T,
			_mats["glass"])
	_place_box(w, x1 - WALL_T * 0.5, h1 + (h - h1) * 0.5, mid_z, WALL_T, h - h1,
			z1 - z0 - WALL_T, _mats["white"])
	_obstacle(w, x1 - WALL_T * 0.5, mid_z, WALL_T * 0.5, (z1 - z0 - WALL_T) * 0.5, h)
	# —— 门厅室内中隔展墙（半高，纯视觉）+ 通高段屋顶 9.5 / 主翼屋顶 8
	_place_box(w, 82.0, 1.3, 38.0, 0.3, 2.6, 8.5, _mats["dark"])
	_place_box(w, 79.0, 9.7, 37.75, 6.6, 0.4, 9.9, _mats["white"])
	_place_box(w, 91.0, 8.2, 37.75, 18.6, 0.4, 9.9, _mats["white"])
	_place_box(w, 91.0, 8.45, z0 - 0.15, 18.0, 0.1, 0.3, _mats["dark"])   # 檐口滴水深线
	# —— 屋顶空调机组×3（白盒+风扇圆片，base HVAC 语言）
	for k in 3:
		var hx := 85.0 + 4.0 * float(k)
		_place_box(w, hx, 8.9, 38.5, 1.8, 1.0, 1.4, _mats["white"])
		_cyl(w, _mesh_insulator, Vector3(hx, 9.45, 38.5), _mats["dark"],
				Vector3(3.6, 0.6, 3.6))
	# —— 北侧深挑檐：0.4m 厚白檐板出挑 3m（全图唯一悬挑语言）+ 檐下细钢柱×5
	_place_box(w, 88.0, 8.25, 31.4, 25.6, 0.4, 3.8, _mats["white"])
	for k in 5:
		_place_box(w, 79.4 + 4.4 * float(k), 4.12, 30.4, 0.18, 8.25, 0.18,
				_mats["white"])
	# —— 短翼 10×11.5：东墙/南墙注册；西面玻璃幕墙+门洞（纯视觉面，对照
	#    铁丝网围栏不注册先例——纯视觉薄壁省线性扫描，玩家由广场穿门洞而入）
	_place_box(w, 105.75, h1 * 0.5, 48.4, WALL_T, h1, 11.2, _mats["glass"])
	_place_box(w, 105.75, h1 + (h - h1) * 0.5, 48.4, WALL_T, h - h1, 11.2,
			_mats["white"])
	_obstacle(w, 105.75, 48.4, WALL_T * 0.5, 5.6, h)
	_place_box(w, 101.0, h1 * 0.5, 53.75, 9.6, h1, WALL_T, _mats["glass"])
	_place_box(w, 101.0, h1 + (h - h1) * 0.5, 53.75, 9.6, h - h1, WALL_T,
			_mats["white"])
	_obstacle(w, 101.0, 53.75, 4.8, WALL_T * 0.5, h)
	_place_box(w, 96.25, h1 * 0.5, 48.4, WALL_T, h1, 11.2, _mats["glass"])
	_place_box(w, 96.25, h1 + (h - h1) * 0.5, 48.4, WALL_T, h - h1, 11.2,
			_mats["white"])
	_place_box(w, 101.0, 8.2, 48.4, 10.6, 0.4, 11.9, _mats["white"])
	for k in 4:
		_place_box(w, 96.17, h1 * 0.5, 43.4 + 2.8 * float(k), 0.14, h1, 0.18,
				_mats["white"])
	_place_box(w, 96.17, 1.75, 48.4, 0.1, 3.5, 2.2, _mats["white"])   # 西门洞框
	# 写实化第四轮：Blender 建模版短翼北面补了幕墙（旧版敞口）、西面幕墙只留门洞
	# （旧版纯视觉可穿）——碰撞随可见层补齐，门洞 z∈[47.3,49.5] 照旧通行
	if PBR.swap_building(w, n0, "visitor", Vector3(88.0, 0.0, 43.0),
			[[x0, x1, z0, z1, h1, h], [96.0, 106.0, z1, 54.0, h1, h]]):
		_obstacle(w, 103.0, 42.75, 3.0, WALL_T * 0.5, h)
		_obstacle(w, 96.25, 44.9, WALL_T * 0.5, 2.4, h)
		_obstacle(w, 96.25, 51.75, WALL_T * 0.5, 2.25, h)


## 南广场 + 旗杆×3 + 指示牌×2 + 树池/座椅/灯杆列/圆形拼花（第 2 轮判图 #13：
## 中心区空无一物——补足参考图的广场小品层次）+ 门厅前石阶（障碍 1 条：
## top 0.6 低于玩家推出高度过滤线 hd_player.gd:176，只挡俯射弹道）
func _visitor_plaza(w) -> void:
	_place_box(w, 86.0, GROUND_TOP - 0.05, 49.0, 20.0, 0.1, 10.0, _mats["plaza"])
	for kz in [46.0, 49.0, 52.0]:   # 深色分缝条（浅灰大板+深缝）
		_place_box(w, 86.0, GROUND_TOP + 0.01, kz, 19.4, 0.02, 0.14, _mats["dark"])
	for k in 2:
		_place_box(w, 81.0 + 9.0 * float(k), GROUND_TOP + 0.01, 49.0, 0.14, 0.02,
				9.4, _mats["dark"])
	# 中心圆形双色拼花（红棕外环+深色芯，与浅灰大板拉开铺装层次）
	_cyl(w, _mesh_insulator, Vector3(86.0, 0.06, 49.0), _mats["yellow"],
			Vector3(12.0, 0.6, 12.0))
	_cyl(w, _mesh_insulator, Vector3(86.0, 0.07, 49.0), _mats["dark"],
			Vector3(6.0, 0.6, 6.0))
	for fz in [51.0, 52.5, 54.0]:   # 旗杆×3（第 3 轮判图 #9：南移广场南缘
		# 11m 竖针+顶红旗面——全景天际线 accent 剪影可读）
		_cyl(w, _mesh_pole, Vector3(79.0, 5.5, fz), _mats["white"])
		_place_box(w, 79.6, 10.5, fz, 1.1, 0.6, 0.04, _mats["red"])
	for sign in [[90.0, 53.2], [95.0, 46.5]]:   # 指示牌×2（灰柱+白牌面）
		_place_box(w, sign[0], 1.1, sign[1], 0.12, 2.2, 0.12, _mats["dark"])
		_place_box(w, sign[0], 1.9, sign[1], 1.4, 0.9, 0.08, _mats["white"])
	# 树池×3（concrete 环收边+土面+camo 树冠球+dark 干）+ 座椅×3（面板+背靠+
	# 双座腿）+ 灯杆列×3（4.5m 双灯头；第 4 轮判图 #2 再加宽一档可读尺度）
	for tp in [[80.5, 46.5], [86.0, 52.5], [91.5, 46.5]]:
		_cyl(w, _mesh_insulator, Vector3(tp[0], 0.26, tp[1]), _mats["concrete"],
				Vector3(5.2, 4.4, 5.2))
		_cyl(w, _mesh_insulator, Vector3(tp[0], 0.14, tp[1]), _mats["dark"],
				Vector3(4.4, 1.6, 4.4))
		# 美术写实化：树池种实拍箭筒树（荒漠芦荟树，CC0 扫描减面版，放大到
		# ~3.5m）；缺失时回退原「干 + 树冠球」
		var qt := PBR.scene(QUIVER_GLB)
		if qt != null:
			var tree: Node3D = qt.instantiate()
			tree.position = Vector3(tp[0], 0.3, tp[1])
			tree.scale = Vector3.ONE * 2.4
			tree.rotation.y = tp[0] * 0.37
			w.add_child(tree)
		else:
			_place_box(w, tp[0], 1.05, tp[1], 0.26, 2.1, 0.26, _mats["dark"])
			# 树冠（第 3 轮判图 #11：冠球底缘上收——干冠交接在 y0.75，不再拖地悬浮）
			_pile(w, Vector3(tp[0], 2.55, tp[1]), Vector3(1.7, 1.8, 1.7),
					_mats["camo"])
		_place_box(w, tp[0] + 2.1, 0.36, tp[1] + 0.2, 2.1, 0.14, 0.6,
				_mats["white"])
		_place_box(w, tp[0] + 2.1, 0.78, tp[1] + 0.52, 2.1, 0.74, 0.12,
				_mats["white"])
		for lx in [-0.75, 0.75]:
			_place_box(w, tp[0] + 2.1 + lx, 0.17, tp[1] + 0.2, 0.16, 0.34, 0.5,
					_mats["dark"])
	for lp in [[79.0, 45.5], [86.0, 45.5], [93.0, 45.5]]:   # 北缘灯杆列
		_place_box(w, lp[0], 2.25, lp[1], 0.16, 4.5, 0.16, _mats["dark"])
		_place_box(w, lp[0], 4.6, lp[1], 0.55, 0.3, 0.55, _mats["white"])
		_place_box(w, lp[0], 4.85, lp[1], 0.35, 0.2, 0.35, _mats["glass"])
	# 门厅前两级 0.3 石阶
	_place_box(w, 74.9, 0.15, 34.7, 4.0, 0.3, 1.8, _mats["concrete"])
	_place_box(w, 75.35, 0.45, 34.7, 3.4, 0.3, 1.1, _mats["concrete"])
	_obstacle(w, 74.9, 34.7, 2.0, 0.8, 0.6)


## 后场小停车场：3 划线车位（白线漆条）+ 1 台 wreck 残车（<1.4m 纯视觉）
## + 南缘碎石过渡带（第 2 轮判图 #12：铺装-沙地直线硬切同源处理）
func _visitor_park(w) -> void:
	_place_box(w, 101.0, GROUND_TOP - 0.05, 56.5, 10.0, 0.1, 3.0, _mats["plaza"])
	for k in 4:
		_place_box(w, 97.5 + 2.3 * float(k), GROUND_TOP + 0.01, 56.5, 0.15, 0.02,
				2.8, _mats["white"])
	_place_box(w, 99.0, 0.6, 56.5, 4.0, 1.2, 1.8, _mats["dark"])
	_place_box(w, 99.0, 1.25, 56.5, 1.6, 0.5, 1.6, _mats["panel"])
	for k in 7:   # 停车场南北缘碎石
		var gx := 96.8 + 1.5 * float(k)
		for gz in [55.0, 58.1]:
			_place_box(w, gx + 0.3 * float(k % 3), 0.09, gz, 0.3, 0.18, 0.35,
					_mats["dark"] if k % 3 == 0 else _mats["silo"],
					Vector3(0.0, 0.4 * float(k % 2), 0.0))


# ================= 点位登记 =================

## 新 7 容器 + 5 巡逻（格式对齐 hd_dam_base.gd:772-778；pos 全部落地面 y=0）
func _register_spots(w) -> void:
	for c in ZONE_CONTAINERS:
		var v: Vector2 = c["p"]
		w.container_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": c["z"]})
	for p in ZONE_PATROLS:
		var v: Vector2 = p["p"]
		w.patrol_spots.append({"pos": Vector3(v.x, 0.0, v.y), "zone": p["z"]})
