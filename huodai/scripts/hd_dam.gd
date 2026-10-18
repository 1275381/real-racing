class_name HDDam
extends Node3D
## 大坝主体（北缘地标的硬结构层）——契约 A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/W 全套：
## A 坝基实体（兼廊道背墙）→ B 下游台阶面（中央 60m 断开）→ C 溢流坝段（涂鸦载体）
## → D 坝顶路面+女儿墙 → E 坝顶栏杆 → F 扶壁肋柱×16（竖向贴面，参考图扶壁柱节奏；
## 第 2 轮观感返工：原斜置板下端出挑 4.55m 压住廊道前空、近景把涂鸦环遮成碎片）
## → G 坝顶红龙门吊×4+塔吊×2（远景天际线，含长臂吊）→ H 地面红门吊×2（坝底记忆点）
## → I 泄洪大圆柱管 3 组×2 根（贴坡阵列）→ J 坝面排水细管 ×4
## → K 溢洪道闸墩排 → L 坝面红色涂鸦圆环（参考图最醒目记忆点，环被竖条带打断）
## → M 坝底廊道层（3 开洞可走进，容器①②③在洞内）→ N 中层廊道窗带
## → O 西端取水塔×2 → W 服务街道条。工业区（厂房/集装箱/工地/卡车/棕榈/山体/点位）
## 归 HDDamBase（坝底匠），本文件零跨文件材质引用（恰 7 枚，全部本文件自建：
## concrete / concrete_dark / steel_red / pipe / graffiti / void 洞龛黑 / paint 白漆）。
## 装配契约：build(root) 由 HDWorld.build() 末调用（root 即 HDWorld，DAM 先 BASE 后）——
## 视觉 root.add_child，碰撞 root.obstacles.append（{cx,cz,hx,hz,top,bot}，
## hd_loot.gd:141-143 同款）。碰撞只给可玩区与墙体（①-⑥⑩⑪，共 29 条），
## 坝顶远景件/斜置扶壁垛/窗带/泄洪管不注册（性能红线既定取舍）。
## 旋转惯例（仅泄洪管保留）：坡面与水平夹 atan(7.8/6)=52.43°，Godot rotation.x
## 从竖直轴起算，贴坡管 rotation.x = -(PI/2 - 52.43°) = -0.6557 rad（上端朝北埋入坝体）。

const PBR := preload("res://scripts/hd_pbr.gd")   # 美术写实化：CC0 实拍 PBR 贴图（缺失自动回退纯色）
const SLOPE_ANG := 0.9151          # atan(7.8/6)：台阶坡面与水平夹角 52.43°
const FIN_TILT := 0.6557           # PI/2 - SLOPE_ANG：泄洪管贴坡绕 x 的转角（从竖直轴起算）
const TOP_Y := 52.0                # 坝顶高程（路面块 y44.2→52，路面板铺其上）
const STEP_H := 7.8                # 台阶每级升高（4 级 y13→44.2）
const STEP_D := 6.0                # 台阶每级进深（front 逐级 -114/-120/-126/-132）

## 泄洪大管 x 位（第 2 轮全组收西段：扶壁垛跨中点，与垛中心距 9 > r3.2+垛半厚
## 0.75 零相交；对位目标图管群集中坝面左侧贴坡而下）
const PIPE_XS := [-131.0, -113.0, -95.0, -77.0, -59.0, -41.0]
## 泄洪管箍环沿管轴的位置参数（中心 ±18/±6，每根 4 道）
const COLLAR_TS := [-18.0, -6.0, 6.0, 18.0]
## 排水细管 x 位（C 面竖直贴挂）
const DRAIN_XS := [-20.0, -10.0, 10.0, 20.0]
## 涂鸦滴泪条相对环心 x 偏移（下端统一收在 y19，长度随环底弧走）
const DRIP_DXS := [-11.0, -9.0, -7.5, 7.5, 9.0, 11.0]
## 溢洪道闸墩 x 位（-25.8 起步距 8.6 共 7 墩）
const PIER_COUNT := 7
const PIER_X0 := -25.8
const PIER_STEP := 8.6
## 廊道暗门片 x 位（柱廊 20m 跨的 bay 中心，避开 3 个开洞 -30/10/50，
## 西端 -145 补 1 片凑 12；面板 6 宽距柱面 ≥2.3m 不相碰）
const PANEL_XS := [-145.0, -130.0, -110.0, -90.0, -70.0, -50.0,
	-10.0, 30.0, 70.0, 90.0, 110.0, 130.0]
## 中央段窗片 x 位（窗距 8m，避环底 y18 压在 y15~17.5）
const CWIN_XS := [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]

var _built := false
## —— 恰 9 枚材质（契约：dam 9 枚零跨文件引用，厂房黄/集装箱红等归 base）——
var _mat_concrete: StandardMaterial3D        # 坝体主混凝土（三平面NoiseTexture 竖向流挂）
var _mat_concrete_dark: StandardMaterial3D   # 暗色件：路面/窗片/暗门片/积垢条/闸墩/缝线
var _mat_steel_red: StandardMaterial3D       # 红钢件：门吊/塔吊/洞口红闸框（metallic 0.3）
var _mat_pipe: StandardMaterial3D            # 泄洪管/栏杆（亮银钢 metallic 0.6）
var _mat_collar: StandardMaterial3D          # 管箍环（比管身更亮一档）
var _mat_graffiti: StandardMaterial3D        # 涂鸦红（无透明，环+X 斜杠+滴泪）
var _mat_void: StandardMaterial3D            # 开洞洞龛近黑背板/管口湿渍（albedo 0.12）
var _mat_paint: StandardMaterial3D           # 白漆件：街道虚线/肩块喷涂字块
var _mat_rust: StandardMaterial3D            # 锈渍：女儿墙竖挂/管根锈带/洞沿锈痕
## —— 共用网格（全模块唯一 mesh 仅 9 种：盒件共用单位盒 + 实例 scale 定尺寸）——
var _mesh_box: BoxMesh                       # 单位盒：约 380 处盒件循环共用
var _mesh_post: CylinderMesh                 # 栏杆柱 r0.12 h1.1 seg6（×100 共用）
var _mesh_col: CylinderMesh                 # 廊道柱 r0.5 h12.9 seg24（×15 共用）
var _mesh_pipe: CylinderMesh                 # 泄洪大管 r3.2 h55 seg32（×6 共用，出口短管缩放复用）
var _mesh_collar: TorusMesh                  # 管箍环（×24 共用）
var _mesh_drain: CylinderMesh                # 排水细管 r0.3 h30 seg8（×4 共用）
var _mesh_graffiti: TorusMesh                # 涂鸦圆环 R12 管 0.9（×1，实例 scale.y=0.12 压扁）
var _mesh_dome: SphereMesh                   # 取水塔穹顶 r9（×2 共用，实例 scale.y=0.5 压扁）
var _mesh_tower: CylinderMesh                # 取水塔身 r9 h30 seg24（×2 共用）


## 装配入口（root 即 HDWorld）：视觉 add_child(root)，障碍 root.obstacles.append
func build(root) -> void:
	if _built:
		return
	_built = true
	_make_mats()
	_dress_pbr()
	_make_meshes()
	_base(root)            # A 坝基实体
	_steps(root)           # B 下游台阶面
	_overflow(root)        # C 溢流坝段
	_top_road(root)        # D 坝顶路面+女儿墙
	_railing(root)         # E 坝顶栏杆
	_fins(root)            # F 扶壁垛阵列
	_cranes_top(root)      # G 坝顶红龙门吊×4+塔吊×2
	_cranes_ground(root)   # H 地面红门吊×2
	_pipes(root)           # I 泄洪大圆柱管
	_drains(root)          # J 坝面排水细管
	_gates(root)           # K 溢洪道闸墩排
	_graffiti(root)        # L 坝面红色涂鸦圆环
	_corridor(root)        # M 坝底廊道层
	_window_band(root)     # N 中层廊道窗带
	_towers(root)          # O 西端取水塔×2
	_street(root)          # W 服务街道条
	_shoulder(root)        # 东坝头肩块（右岸接入山体）
	_apron_wall(root)      # 坝顶后方第二层坝肩墙（远景天际线双层化）
	_seams(root)           # 施工缝线（水平对齐 STEP_H / 竖向对齐垛中线）
	_rust_stains(root)     # 女儿墙下沿锈挂条


## 美术写实化：坝体换实拍混凝土（模板浇筑的层状纹，正对应大坝分层浇筑），
## 红门吊/管道换带锈旧漆钢板；贴图缺失时 dress() 不动材质，保持原纯色版
func _dress_pbr() -> void:
	PBR.dress(_mat_concrete, "concrete", 5.0)
	PBR.dress(_mat_concrete_dark, "concrete", 5.0)
	PBR.dress(_mat_steel_red, "paint_rust", 2.0)
	# 泄洪管/箍环：风化灰漆钢管（原纯白金属在实拍天空下读成白塑料管；
	# 设计色压到中灰，免得旧漆贴图把它刷成米白）
	_mat_pipe.albedo_color = Color(0.5, 0.52, 0.53)
	PBR.dress(_mat_pipe, "paint_rust", 3.0)
	_mat_collar.albedo_color = Color(0.4, 0.41, 0.42)
	PBR.dress(_mat_collar, "paint_rust", 2.0)


func _make_mats() -> void:
	# 主混凝土：三平面投影 + 各向异性 uv1_scale——纵向频率低 8 倍（0.05 vs 0.006）
	# 噪点沿世界 Y 被拉伸成天然竖向流挂，破第 1 轮「肋柱与 300m 墙面同频雪花纹」
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.02
	n.fractal_octaves = 4
	n.seed = 20261011
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.48, 0.45))   # 渍纹暗斑（加深：流挂对比可见）
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	_mat_concrete = StandardMaterial3D.new()
	# 清水混凝土（第 2 轮 0.75→0.68：压一点给流挂留对比度）
	_mat_concrete.albedo_color = Color(0.68, 0.66, 0.62)
	_mat_concrete.albedo_texture = tex
	_mat_concrete.uv1_triplanar = true
	_mat_concrete.uv1_scale = Vector3(0.05, 0.006, 0.05)
	# 第 4 轮判图 #9：背光坝面读成均匀死灰板——rough 0.95→0.86 给一点
	# 环境反射（天光在混凝土面上的冷灰反光），配竖水渍条破均色
	_mat_concrete.roughness = 0.86
	_mat_concrete_dark = StandardMaterial3D.new()
	_mat_concrete_dark.albedo_color = Color(0.48, 0.47, 0.45)
	_mat_concrete_dark.roughness = 0.95
	_mat_steel_red = StandardMaterial3D.new()
	_mat_steel_red.albedo_color = Color(0.52, 0.07, 0.05)
	_mat_steel_red.metallic = 0.3
	_mat_steel_red.roughness = 0.45
	_mat_pipe = StandardMaterial3D.new()
	# 亮银钢（第 3 轮 metallic 0.15→0.6 / rough 0.85→0.35：目标管面银灰金属光泽、
	# 明暗分明；第 2 轮哑光是矫枉过正）
	_mat_pipe.albedo_color = Color(0.62, 0.62, 0.6)
	_mat_pipe.metallic = 0.6
	_mat_pipe.roughness = 0.35
	_mat_collar = StandardMaterial3D.new()
	_mat_collar.albedo_color = Color(0.72, 0.72, 0.7)   # 箍环比管身更亮一档
	_mat_collar.metallic = 0.65
	_mat_collar.roughness = 0.3
	_mat_graffiti = StandardMaterial3D.new()
	# 风化砖红旧漆（第 2 轮降饱和 0.75,0.06,0.05→0.58,0.1,0.08 + 粗糙化）
	_mat_graffiti.albedo_color = Color(0.58, 0.1, 0.08)
	_mat_graffiti.roughness = 0.9
	_mat_void = StandardMaterial3D.new()
	_mat_void.albedo_color = Color(0.12, 0.12, 0.12)   # 开洞洞龛近黑（目标图黑洞门孔）
	_mat_void.roughness = 1.0
	_mat_paint = StandardMaterial3D.new()
	_mat_paint.albedo_color = Color(0.88, 0.87, 0.83)  # 白漆：街道虚线/肩块喷涂块
	_mat_paint.roughness = 0.8
	_mat_rust = StandardMaterial3D.new()
	_mat_rust.albedo_color = Color(0.42, 0.22, 0.12)   # 锈渍（评审 #13）
	_mat_rust.roughness = 1.0


func _make_meshes() -> void:
	_mesh_box = BoxMesh.new()
	_mesh_box.size = Vector3.ONE   # BoxMesh 默认 2m 见方，压回单位盒配合实例 scale
	_mesh_post = CylinderMesh.new()
	_mesh_post.top_radius = 0.12
	_mesh_post.bottom_radius = 0.12
	_mesh_post.height = 1.1
	_mesh_post.radial_segments = 6
	_mesh_col = CylinderMesh.new()
	_mesh_col.top_radius = 0.5
	_mesh_col.bottom_radius = 0.5
	_mesh_col.height = 12.9
	_mesh_col.radial_segments = 24
	_mesh_pipe = CylinderMesh.new()
	_mesh_pipe.top_radius = 3.2
	_mesh_pipe.bottom_radius = 3.2
	_mesh_pipe.height = 55.0
	_mesh_pipe.radial_segments = 32
	_mesh_collar = TorusMesh.new()
	_mesh_collar.inner_radius = 3.1
	_mesh_collar.outer_radius = 4.6
	_mesh_collar.rings = 24
	_mesh_collar.ring_segments = 8
	_mesh_drain = CylinderMesh.new()
	_mesh_drain.top_radius = 0.3
	_mesh_drain.bottom_radius = 0.3
	_mesh_drain.height = 30.0
	_mesh_drain.radial_segments = 8
	_mesh_graffiti = TorusMesh.new()
	_mesh_graffiti.inner_radius = 11.1
	_mesh_graffiti.outer_radius = 12.9
	_mesh_graffiti.rings = 48
	_mesh_graffiti.ring_segments = 8
	_mesh_dome = SphereMesh.new()
	_mesh_dome.radius = 9.0
	_mesh_dome.height = 18.0
	_mesh_dome.radial_segments = 24
	_mesh_dome.rings = 12
	_mesh_tower = CylinderMesh.new()
	_mesh_tower.top_radius = 9.0
	_mesh_tower.bottom_radius = 9.0
	_mesh_tower.height = 30.0
	_mesh_tower.radial_segments = 24
	_mesh_tower.rings = 1


## 摆盒：共用单位 BoxMesh + 实例 scale 定尺寸（网格构成红线：唯一 mesh 数收敛）
## 2026-10 性能：摆件一律不投影（spawn 朝坝阴影 pass 是 16→36 帧元凶之一；
## 130~280m 远景阴影本就看不清，坝体明暗靠面朝向+AO 表达足够）
func _box(root, size: Vector3, pos: Vector3, mat: StandardMaterial3D,
		rot_x := 0.0, rot_z := 0.0, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_box
	mi.scale = size
	mi.position = pos
	mi.rotation = Vector3(rot_x, rot_y, rot_z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_surface_override_material(0, mat)
	root.add_child(mi)
	return mi


## 摆共用网格件（圆柱/环/球），可选 rot.x 与实例缩放（出口短管/穹顶压扁用）
func _inst(root, mesh: Mesh, pos: Vector3, mat: StandardMaterial3D,
		rot_x := 0.0, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.x = rot_x
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_surface_override_material(0, mat)
	root.add_child(mi)
	return mi


## 注册轴对齐碰撞（契约 {cx,cz,hx,hz,top,bot}，wall_hit/obstacles_near 同源消费）
func _ob(root, cx: float, cz: float, hx: float, hz: float, top: float, bot := 0.0) -> void:
	root.obstacles.append({"cx": cx, "cz": cz, "hx": hx, "hz": hz,
		"top": top, "bot": bot})


# ================= A 坝基实体 =================

## 300×13×30 实体（z∈[-148,-118]，y0→13）；前立面 z=-118 即廊道 3 开洞的洞底
func _base(root) -> void:
	_box(root, Vector3(300.0, 13.0, 30.0), Vector3(0.0, 6.5, -133.0), _mat_concrete)
	_ob(root, 0.0, -133.0, 150.0, 15.0, 13.0)


# ================= B 下游台阶面 =================

## 4 级×西/东段（西 x∈[-150,-30] 东 x∈[30,150]，中央 60m 断开让位溢流段）；
## 每级高 7.8 进深 6（与扶壁垛贴坡同一条 52.43° 坡线），front 逐级 -114/-120/-126/-132；
## 坝顶块 y44.2→52 与 C 连成坝顶路（碰撞 top53 按契约 ③，与路面顶差 1m 在 wall_hit 容差内）
func _steps(root) -> void:
	for sx in [-90.0, 90.0]:
		for i in 4:
			var front: float = -114.0 - STEP_D * float(i)
			var bot: float = 13.0 + STEP_H * float(i)
			_box(root, Vector3(120.0, STEP_H, STEP_D),
					Vector3(sx, bot + STEP_H * 0.5, front - STEP_D * 0.5), _mat_concrete)
			# 级前脸上缘积垢横带（目标图阶沿深色污线，凸 0.12 消共面）
			_box(root, Vector3(120.0, 0.3, 0.35),
					Vector3(sx, bot + STEP_H - 0.15, front + 0.12), _mat_concrete_dark)
			_ob(root, sx, front - STEP_D * 0.5, 60.0, STEP_D * 0.5,
					bot + STEP_H, bot)
		_box(root, Vector3(120.0, STEP_H, 10.0), Vector3(sx, 48.1, -143.0), _mat_concrete)
		# 坝顶块下沿口积垢带
		_box(root, Vector3(120.0, 0.3, 0.35), Vector3(sx, 44.05, -137.9),
				_mat_concrete_dark)
		_ob(root, sx, -143.0, 60.0, 5.0, 53.0, 44.2)


# ================= C 溢流坝段 =================

## 60×39×24（x∈[-30,30]，y13→52，front z=-124 竖直面）——涂鸦环/排水管/闸墩的载体
func _overflow(root) -> void:
	_box(root, Vector3(60.0, 39.0, 24.0), Vector3(0.0, 32.5, -136.0), _mat_concrete)
	_ob(root, 0.0, -136.0, 30.0, 12.0, 53.0, 13.0)


# ================= D 坝顶路面 + 女儿墙 =================

## 路面板 300×0.15×8（z∈[-147,-139]，暗色）+ 女儿墙 ×2（z=-138.4/-147.6，
## 栏杆柱立其顶）；纯远景不注册碰撞
func _top_road(root) -> void:
	_box(root, Vector3(300.0, 0.15, 8.0), Vector3(0.0, 52.07, -143.0), _mat_concrete_dark)
	for pz in [-138.4, -147.6]:
		_box(root, Vector3(300.0, 1.0, 0.4), Vector3(0.0, 52.5, pz), _mat_concrete)


# ================= E 坝顶栏杆 =================

## 柱距 6m ×100（-147→147 每侧 50 根，同 Mesh 复用）+ 扁钢轨 ×6（每侧三道，
## 第 3 轮加中横杆 + 柱/杆 0.08→0.12——ref 机位 280m 外仍读作栏杆线）
func _railing(root) -> void:
	for pz in [-138.4, -147.6]:
		for k in 50:
			var px: float = -147.0 + 6.0 * float(k)
			_inst(root, _mesh_post, Vector3(px, 53.55, pz), _mat_pipe)
		for ry in [53.45, 53.74, 54.02]:
			_box(root, Vector3(296.0, 0.12, 0.12), Vector3(0.0, ry, pz), _mat_pipe)


# ================= F 扶壁肋柱阵列 ×16 =================

## 竖向贴面肋柱（第 2 轮观感返工）：1.5 厚×39 高×2 深，y13（廊道顶）→52（坝顶），
## 中心 z=-122.9 → 背面 -123.9 嵌入 C 面 0.1 消共面、前脸 -121.9 凸出 2.1m（契约 ≤2m 口径）；
## 柱距 18m（x_k=-140+18k 共 16 榀）保持参考图扶壁柱节奏；环被柱带打断原样保留
## （x=-14/4 两柱竖向切过涂鸦环弧）。与泄洪管 x 向距 ≥5.5、与闸墩距 ≥3.2、
## 与排水管距 ≥2 零相交；无碰撞（凸出 ≤2.1m，坡体/溢流段 AABB 兜底）。
## 西端两柱（x=-140/-122）落取水塔体内被吞（塔 18 见方罩住）——远景 150m 外不显，维持 16 榀节奏。
## 第 3 轮梳齿：偶数榀上延 3.5m（高 42.5、y 心 33.75）凸出坝顶路面成锯齿剪影——
## 目标坝顶最易识别的轮廓特征。第 4 轮：跳过 k=7/8 两榀（x=-14/+4 恰切涂鸦环），
## 环带让空 36m——目标环完整醒目不被柱切断
func _fins(root) -> void:
	for k in 16:
		if k == 7 or k == 8:
			continue
		var xk: float = -140.0 + 18.0 * float(k)
		if k % 2 == 0:
			_box(root, Vector3(1.5, 42.5, 2.0), Vector3(xk, 33.75, -122.9), _mat_concrete)
		else:
			_box(root, Vector3(1.5, 39.0, 2.0), Vector3(xk, 32.5, -122.9), _mat_concrete)


# ================= G/H 红龙门吊与塔吊 =================

## 门吊生成器：双腿 + 主梁 + 小车（红钢）；近景（地面门吊）加吊缆+吊钩。
## 第 3 轮：主梁 16→22m 拉大跨读作「门」；地面版加双横撑 + 梁上双小车盒
## （目标坝踵 15m 桁架门形，腿高由调用方给 13）
func _gantry(root, base: Vector3, leg_h: float, with_hook: bool) -> void:
	for sx in [-7.0, 7.0]:
		_box(root, Vector3(1.6, leg_h, 1.6), base + Vector3(sx, leg_h * 0.5, 0.0),
				_mat_steel_red)
	_box(root, Vector3(22.0, 0.9, 1.4), base + Vector3(0.0, leg_h + 0.45, 0.0),
			_mat_steel_red)
	_box(root, Vector3(2.2, 1.4, 1.8), base + Vector3(2.0, leg_h + 0.1, 0.0),
			_mat_steel_red)
	if with_hook:
		# 双横撑（桁架门形）+ 梁上双小车 + 吊缆吊钩
		for hy in [leg_h * 0.4, leg_h * 0.72]:
			_box(root, Vector3(14.0, 0.5, 0.8), base + Vector3(0.0, hy, 0.0),
					_mat_steel_red)
		for cx in [-4.0, 4.0]:
			_box(root, Vector3(2.0, 1.0, 1.4), base + Vector3(cx, leg_h + 0.95, 0.0),
					_mat_concrete_dark)
		var top: float = leg_h - 0.6
		_box(root, Vector3(0.12, 2.2, 0.12), base + Vector3(2.0, top - 1.1, 0.0),
				_mat_pipe)
		_box(root, Vector3(0.45, 0.5, 0.45), base + Vector3(2.0, top - 2.45, 0.0),
				_mat_concrete_dark)


## 塔吊：塔身+驾驶室（暗色）+起重臂+配重+双吊索吊钩（远景天际线）。
## 第 3 轮：桅 16→26m、臂参数化（默认 34，长臂吊传 40），150m 外读作清晰剪影
func _tower_crane(root, base: Vector3, arm_len := 34.0) -> void:
	_box(root, Vector3(2.2, 26.0, 2.2), base + Vector3(0.0, 13.0, 0.0), _mat_steel_red)
	_box(root, Vector3(2.8, 2.2, 2.8), base + Vector3(0.0, 25.1, 0.0), _mat_concrete_dark)
	_box(root, Vector3(arm_len, 0.8, 1.2),
			base + Vector3(arm_len * 0.5 - 8.0, 26.4, 0.0), _mat_steel_red)
	_box(root, Vector3(2.0, 1.8, 2.4), base + Vector3(-8.0, 25.3, 0.0), _mat_concrete_dark)
	# 双吊索 + 吊钩小盒（臂前段下挂）
	for sx in [8.0, 16.0]:
		_box(root, Vector3(0.08, 6.0, 0.08), base + Vector3(sx, 23.1, 0.0), _mat_pipe)
		_box(root, Vector3(0.4, 0.45, 0.4), base + Vector3(sx, 19.8, 0.0),
				_mat_concrete_dark)


## 坝顶红龙门吊×4（x=-75/-40/55/132）+ 塔吊×1（x=-5 臂34）+ 长臂吊×1（x=30 臂40，
## 对位目标图最顶那台），y52 起 z=-143，纯远景无碰撞；腿 9→12（ref 机位 140m 外
## 剪影可读）
func _cranes_top(root) -> void:
	for gx in [-75.0, -40.0, 55.0, 132.0]:
		_gantry(root, Vector3(gx, 52.0, -143.0), 12.0, false)
	_tower_crane(root, Vector3(-5.0, 52.0, -143.0))
	_tower_crane(root, Vector3(30.0, 52.0, -143.0), 40.0)


## 地面红门吊×2 @(-18,-106)/(22,-106)（廊道前广场记忆点）：
## 复用门吊生成器落 y0，腿 8→13（对位目标坝踵 15m 桁架门吊），只注册腿碰撞
## （2 条/台，梁 y13.9+ 可穿行）
func _cranes_ground(root) -> void:
	for gx in [-18.0, 22.0]:
		_gantry(root, Vector3(gx, 0.0, -106.0), 13.0, true)
		for sx in [-7.0, 7.0]:
			_ob(root, gx + sx, -106.0, 0.8, 0.8, 13.0)


# ================= I 泄洪大圆柱管 =================

## 3 组×2 根：r3.2 长 55 贴坡（rot.x=-FIN_TILT），根端 y8 出坝、顶端 y51.6 没入坝顶；
## 每根 4 道箍环（TorusMesh 同转角）；第 3 轮管群收西段后，出口短管 ×2 随迁
## (-63.5/-56.5, 8.5, -101.5) 与 -59 管根端交汇成汇流 manifold。无碰撞（近景结构件让走位）
func _pipes(root) -> void:
	var dir := Vector3(0.0, cos(SLOPE_ANG), -sin(SLOPE_ANG))
	for px in PIPE_XS:
		var c := Vector3(px, 29.8, -122.9)
		_inst(root, _mesh_pipe, c, _mat_pipe, -FIN_TILT)
		for t in COLLAR_TS:
			_inst(root, _mesh_collar, c + dir * float(t), _mat_collar, -FIN_TILT)
		# 管身嵌墙口锈带（评审 #13：管入台阶坡面处锈水沿墙下流——管在 z=-120
		# 处嵌入级2 前脸，锈带贴该前脸 y22.5~27.5）
		_box(root, Vector3(0.8, 5.0, 0.2),
				Vector3(px, 25.0, -119.85), _mat_rust)
	for ox in [-63.5, -56.5]:
		_inst(root, _mesh_pipe, Vector3(ox, 8.5, -101.5), _mat_pipe,
				PI * 0.5, Vector3(1.0, 0.2, 1.0))
		# 管口下深色湿渍带（评审 #20）
		_box(root, Vector3(1.5, 0.06, 3.0), Vector3(ox, 0.045, -100.0), _mat_void)


# ================= J 坝面排水细管 ×4 =================

## r0.3 长 30 垂直贴 C 面（管面 z∈[-123.9,-123.3]），从窗带后方穿环而下
func _drains(root) -> void:
	for dx in DRAIN_XS:
		_inst(root, _mesh_drain, Vector3(dx, 32.5, -123.6), _mat_pipe)


# ================= K 溢洪道闸墩排 =================

## 闸墩 ×7（1.8×12×1.8，定深贴面 z∈[-124,-122.2]）+ 门楣梁 ×2（顶梁坐墩顶/
## 底梁贴 C 面）+ 暗门片 ×6（墩间内退 z=-123.75）；涂鸦环从墩盒内刺过
## （环管面 z∈[-123.91,-123.69] 严格在墩盒内部，约 9% 弧被墩正面遮挡=参考图原样）。
## 第 3 轮去红：闸墩/门楣 _mat_steel_red→_mat_concrete_dark——目标图坝面红只留
## 涂鸦标志与吊机，7 墩+2 梁的大红框架污染退役
func _gates(root) -> void:
	for i in PIER_COUNT:
		var px: float = PIER_X0 + PIER_STEP * float(i)
		_box(root, Vector3(1.8, 12.0, 1.8), Vector3(px, 38.0, -123.1),
				_mat_concrete_dark)
		_ob(root, px, -123.1, 0.9, 0.9, 44.0, 30.0)
	_box(root, Vector3(60.0, 1.2, 1.8), Vector3(0.0, 44.6, -123.1), _mat_concrete_dark)
	_box(root, Vector3(60.0, 1.2, 1.8), Vector3(0.0, 31.4, -123.1), _mat_concrete_dark)
	for gx in [-21.5, -12.9, -4.3, 4.3, 12.9, 21.5]:
		_box(root, Vector3(6.8, 11.0, 0.3), Vector3(gx, 38.0, -123.75),
				_mat_concrete_dark)


# ================= L 坝面红色涂鸦圆环 =================

## 参考图最醒目记忆点：扁圆环（R12 管 0.9，实例 scale.y=0.12 → 环管面
## z∈[-123.91,-123.69]，整圆 y17.1→42.9 贴 C 竖直面）+ X 双斜杠（第 4 轮补
## 第二道反向斜杠，视觉判读目标环内为叉形）+ 滴泪条 ×6
## （下端统一收在 y19，长度随环底弧 0.9~4.7m）
func _graffiti(root) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _mesh_graffiti
	ring.position = Vector3(-4.0, 30.0, -123.8)
	ring.rotation.x = PI * 0.5          # 立环：环面转成全局 XY（朝 ±z）
	ring.scale = Vector3(1.0, 0.12, 1.0)   # 局部 y=管轴 → 压扁成 z 向 0.108 薄片
	ring.set_surface_override_material(0, _mat_graffiti)
	root.add_child(ring)
	_box(root, Vector3(2.2, 17.0, 0.5), Vector3(-4.0, 30.0, -123.8),
			_mat_graffiti, 0.0, PI * 0.25)
	_box(root, Vector3(2.2, 17.0, 0.5), Vector3(-4.0, 30.0, -123.8),
			_mat_graffiti, 0.0, -PI * 0.25)
	for dx in DRIP_DXS:
		var y_arc: float = 30.0 - sqrt(12.9 * 12.9 - dx * dx)
		var drip_top: float = y_arc + 0.4
		var drip_h: float = drip_top - 19.0
		_box(root, Vector3(0.5, drip_h, 0.14),
				Vector3(-4.0 + dx, (drip_top + 19.0) * 0.5, -123.8), _mat_graffiti)


# ================= M 坝底廊道层 =================

## 前墙 4 段（y0→13.1，比顶梁顶面高 0.1 消共面；开洞留空 x=-30/10/50 各 16 宽）+
## 顶梁 300.8×3.5×6.6（y9.5→13；x 向出檐 0.4、前脸 -111.8 出 0.2 成楣带，全消共面）+
## 柱廊柱 ×15（r0.5 h12.9，z=-111.25）+ 柱间横楣通条（第 3 轮拱廊化：细柱+通长楣
## 读成连续拱廊，替代原「栅栏」观感）+ 暗门片 ×12（bay 中心，避 3 开洞）+
## 洞龛近黑背板 ×3（第 3 轮：开洞读成黑洞，对位目标图坝底深黑门孔）。
## 背墙即 A 前立面 z=-118；开洞净高 9.5 可走进，容器①②③在洞内
func _corridor(root) -> void:
	for seg in [[-94.0, 112.0], [-10.0, 24.0], [30.0, 24.0], [104.0, 92.0]]:
		_box(root, Vector3(seg[1], 13.1, 6.0), Vector3(seg[0], 6.55, -115.0),
				_mat_concrete)
		_ob(root, seg[0], -115.0, seg[1] * 0.5, 3.0, 13.0)
	_box(root, Vector3(300.8, 3.5, 6.6), Vector3(0.0, 11.25, -115.1), _mat_concrete)
	# 顶梁下沿积垢横带（第 3 轮，凸出楣带 0.06 消共面）
	_box(root, Vector3(300.8, 0.4, 0.3), Vector3(0.0, 9.3, -111.65),
			_mat_concrete_dark)
	for k in 15:
		var cx: float = -140.0 + 20.0 * float(k)
		_inst(root, _mesh_col, Vector3(cx, 6.45, -111.25), _mat_concrete)
	_box(root, Vector3(300.0, 1.2, 0.3), Vector3(0.0, 10.6, -111.25), _mat_concrete)
	for px in PANEL_XS:
		_box(root, Vector3(6.0, 8.1, 0.3), Vector3(px, 5.25, -111.8),
				_mat_concrete_dark)
	# 洞龛近黑背板 ×3（x=-30/10/50 洞内 z≈-117.3，宽 16=洞宽）+ 两上角斜切块
	# 拼拱缘（评审 #19 拱形洞门）+ 洞口红闸框（两侧 0.4×9 红柱+顶红梁，
	# 第 3 轮恢复目标红框架；闸墩本体保持灰）+ 洞沿锈痕带（评审 #13）
	for hx in [-30.0, 10.0, 50.0]:
		_box(root, Vector3(16.0, 10.0, 0.3), Vector3(hx, 5.0, -117.3), _mat_void)
		_box(root, Vector3(5.0, 1.2, 0.3), Vector3(hx - 5.6, 8.9, -117.15),
				_mat_concrete_dark, 0.0, 0.6)
		_box(root, Vector3(5.0, 1.2, 0.3), Vector3(hx + 5.6, 8.9, -117.15),
				_mat_concrete_dark, 0.0, -0.6)
		for sx in [-8.0, 8.0]:
			_box(root, Vector3(0.4, 9.0, 0.4), Vector3(hx + sx, 4.5, -111.55),
					_mat_steel_red)
		_box(root, Vector3(16.8, 0.5, 0.4), Vector3(hx, 9.75, -111.55),
				_mat_steel_red)
		_box(root, Vector3(10.0, 0.4, 0.12), Vector3(hx, 10.1, -111.68), _mat_rust)


# ================= N 中层廊道窗带 =================

## 肩段（x∈[-138,-36]/[36,138]）背板 102×4.5×1.2 贴 step2 front + 窗片 ×12/侧；
## 中央段取消背板只留 0.2 厚窗片 ×6（z∈[-122.8,-122.6]，y15→17.5 避环底 y18——
## 涂鸦环与排水管全部从窗片后方穿过=正确遮挡）。每窗片下加竖向滴痕条 ×12/侧+6
## （第 3 轮积垢细节）。无碰撞
func _window_band(root) -> void:
	for sx in [-87.0, 87.0]:
		_box(root, Vector3(102.0, 4.5, 1.2), Vector3(sx, 23.25, -119.4),
				_mat_concrete_dark)
		var x0: float = -132.0 if sx < 0.0 else 44.0
		for k in 12:
			var wx: float = x0 + 8.0 * float(k)
			_box(root, Vector3(3.0, 2.5, 0.2), Vector3(wx, 23.25, -118.7),
					_mat_concrete_dark)
			_box(root, Vector3(0.15, 1.5, 0.12), Vector3(wx, 21.25, -118.6),
					_mat_concrete_dark)
	for wx in CWIN_XS:
		_box(root, Vector3(3.0, 2.5, 0.2), Vector3(wx, 16.25, -122.7),
				_mat_concrete_dark)
		_box(root, Vector3(0.15, 1.5, 0.12), Vector3(wx, 14.25, -122.6),
				_mat_concrete_dark)


# ================= O 西端取水塔 ×2 =================

## 圆柱取水塔 ×2（第 3 轮形态返工：方盒→r9 h30 圆柱塔身 + 压扁穹顶，总高 39；
## 对位目标图左前景两座大圆柱取水塔）+ 塔面竖向暗槽 ×4/塔 + 塔间连桥方管；
## 中心距 18.2（塔面间隙 0.2 消共面）；前脸 z=-114 挺出廊道带后景
func _towers(root) -> void:
	for tx in [-138.1, -119.9]:
		_inst(root, _mesh_tower, Vector3(tx, 15.0, -123.0), _mat_concrete)
		_inst(root, _mesh_dome, Vector3(tx, 30.0, -123.0), _mat_concrete,
				0.0, Vector3(1.0, 0.5, 1.0))
		for dx in [-6.3, -2.1, 2.1, 6.3]:
			_box(root, Vector3(1.4, 26.0, 0.35), Vector3(tx + dx, 15.0, -113.85),
					_mat_concrete_dark)
		_ob(root, tx, -123.0, 9.0, 9.0, 39.0)
	_box(root, Vector3(24.0, 1.6, 1.6), Vector3(-129.0, 24.0, -123.0), _mat_pipe)


# ================= W 服务街道条 =================

## 服务街（第 4 轮：直线改 3 段折线弯——直段+rot.y 斜段+直段，目标土路从
## 底中弯向左）+ 0.15 高深色路缘勾轮廓 + 白色虚线中线（弯段不放）
func _street(root) -> void:
	# 直段 1：x[-130,-40] @z-90
	_box(root, Vector3(90.0, 0.05, 9.0), Vector3(-85.0, 0.025, -90.0),
			_mat_concrete_dark)
	for ez in [-94.4, -85.6]:
		_box(root, Vector3(90.0, 0.15, 0.25), Vector3(-85.0, 0.075, ez),
				_mat_void)
	# 弯段：rot.y 0.22 斜置衔接两直段
	_box(root, Vector3(36.0, 0.05, 9.0), Vector3(-30.0, 0.025, -86.0),
			_mat_concrete_dark, 0.0, 0.0, 0.22)
	# 直段 2：x[-14,20] @z-81（东端让位既有单箱 (30,-82.5)）
	_box(root, Vector3(34.0, 0.05, 9.0), Vector3(3.0, 0.025, -81.0),
			_mat_concrete_dark)
	for ez in [-85.4, -76.6]:
		_box(root, Vector3(34.0, 0.15, 0.25), Vector3(3.0, 0.075, ez),
				_mat_void)
	# 白虚线中线：直段 1 ×12 + 直段 2 ×5
	for k in 12:
		var lx: float = -125.0 + 7.0 * float(k)
		_box(root, Vector3(1.8, 0.02, 0.18), Vector3(lx, 0.07, -90.0), _mat_paint)
	for k in 5:
		var lx2: float = -10.0 + 7.0 * float(k)
		_box(root, Vector3(1.8, 0.02, 0.18), Vector3(lx2, 0.07, -81.0), _mat_paint)


## 东坝头肩块（第 3 轮：目标右岸坝体延伸接入山体）——20×40×30 混凝土肩块
## x∈[149.9,169.9]（西端嵌入坝基/台阶端面 0.1 消共面），接入东山脚穹丘；
## 面上白色喷涂块对位目标图右岸白字涂鸦。肩块入碰撞 1 条
func _shoulder(root) -> void:
	_box(root, Vector3(20.0, 40.0, 30.0), Vector3(159.9, 20.0, -133.0), _mat_concrete)
	_ob(root, 159.9, -133.0, 10.0, 15.0, 40.0)
	_box(root, Vector3(6.0, 3.0, 0.3), Vector3(158.0, 24.0, -117.9), _mat_paint)


## 施工缝线（评审 #12：目标坝面有施工缝/模板痕）——细盒 0.06×0.08 贴面出 0.02：
## C 面水平缝对齐 STEP_H 节奏（y20.8/28.6/36.4）+ 竖向缝对齐垛间中线（x=-23/-5/13）；
## 台阶每级前脸竖缝对齐垛中线延伸（西段 -140..-50 / 东段 40..148）
func _seams(root) -> void:
	# 第 4 轮判图 #9：C 面浇筑横缝 0.06→0.13 加粗（中景可读）+ 竖向水渍条×3
	# （避涂鸦环 x∈[−16.9,8.9] 与闸墩占位，放 x=−22/−18/17）
	for sy in [20.8, 28.6, 36.4]:
		_box(root, Vector3(60.0, 0.13, 0.16), Vector3(0.0, sy, -123.94),
				_mat_concrete_dark)
	for sx in [-23.0, -5.0, 13.0]:
		_box(root, Vector3(0.06, 39.0, 0.08), Vector3(sx, 32.5, -123.94),
				_mat_concrete_dark)
	for wx in [-22.0, -18.0, 17.0]:   # C 面垂直水渍条（锈带语言；第 4 轮复测
		# 0.4 宽在 240m overview 仅 1px 读不出——加宽 0.75/0.5 到 2px 可读）
		_box(root, Vector3(0.75, 26.0, 0.12), Vector3(wx, 26.0, -123.88), _mat_rust)
		_box(root, Vector3(0.5, 12.0, 0.12), Vector3(wx, 40.0, -123.88), _mat_rust)
	for seg_x in [-90.0, 90.0]:
		var joints: Array = [-140.0, -122.0, -104.0, -86.0, -68.0, -50.0] \
				if seg_x < 0.0 \
				else [40.0, 58.0, 76.0, 94.0, 112.0, 130.0, 148.0]
		for jx_v in joints:
			var jx: float = jx_v
			for i in 4:
				var front: float = -114.0 - STEP_D * float(i)
				var bot: float = 13.0 + STEP_H * float(i)
				_box(root, Vector3(0.06, STEP_H, 0.08),
						Vector3(jx, bot + STEP_H * 0.5, front + 0.04),
						_mat_concrete_dark)


## 女儿墙下沿锈挂条（评审 #13：水平锈带+竖挂）——每 20m 一条，长度 1.5/2/2.5 交替
func _rust_stains(root) -> void:
	for pz in [-138.14, -147.34]:
		for i in 15:
			var rx: float = -140.0 + 20.0 * float(i)
			var rh: float = 1.5 + 0.5 * float(i % 3)
			_box(root, Vector3(0.3, rh, 0.06),
					Vector3(rx, 52.0 - rh * 0.5, pz), _mat_rust)


## 坝顶后方第二层坝肩墙（第 5 轮体量架构：目标坝顶之后还有一层更高的坝肩
## 结构线延续天际线）——170×14×8 @z=-152、顶 y67，仅西段 x[-150,20]（东段
## 让位山脊主峰）；纯远景不注册碰撞（wall_hit 最深命中 z=-124 不及此）
func _apron_wall(root) -> void:
	_box(root, Vector3(170.0, 14.0, 8.0), Vector3(-65.0, 60.0, -152.0),
			_mat_concrete)
	# 墙顶压顶矮墙 + 三段错落凹口，破单箱平顶
	_box(root, Vector3(60.0, 1.5, 6.0), Vector3(-115.0, 67.75, -152.0),
			_mat_concrete)
	_box(root, Vector3(50.0, 2.5, 6.0), Vector3(-45.0, 68.25, -152.0),
			_mat_concrete)
	_box(root, Vector3(30.0, 1.0, 6.0), Vector3(5.0, 67.5, -152.0),
			_mat_concrete)
