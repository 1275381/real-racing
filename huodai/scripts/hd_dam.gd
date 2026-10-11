class_name HDDam
extends Node3D
## 大坝主体（北缘地标的硬结构层）——契约 A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/W 全套：
## A 坝基实体（兼廊道背墙）→ B 下游台阶面（中央 60m 断开）→ C 溢流坝段（涂鸦载体）
## → D 坝顶路面+女儿墙 → E 坝顶栏杆 → F 扶壁肋柱×16（竖向贴面，参考图扶壁柱节奏；
## 第 2 轮观感返工：原斜置板下端出挑 4.55m 压住廊道前空、近景把涂鸦环遮成碎片）
## → G 坝顶红龙门吊×2+塔吊×1（远景天际线）→ H 地面红门吊×2（坝底记忆点）
## → I 泄洪大圆柱管 3 组×2 根（贴坡阵列）→ J 坝面排水细管 ×4
## → K 溢洪道闸墩排 → L 坝面红色涂鸦圆环（参考图最醒目记忆点，环被竖条带打断）
## → M 坝底廊道层（3 开洞可走进，容器①②③在洞内）→ N 中层廊道窗带
## → O 西端取水塔×2 → W 服务街道条。工业区（厂房/集装箱/工地/卡车/棕榈/山体/点位）
## 归 HDDamBase（坝底匠），本文件零跨文件材质引用（恰 5 枚，全部本文件自建）。
## 装配契约：build(root) 由 HDWorld.build() 末调用（root 即 HDWorld，DAM 先 BASE 后）——
## 视觉 root.add_child，碰撞 root.obstacles.append（{cx,cz,hx,hz,top,bot}，
## hd_loot.gd:141-143 同款）。碰撞只给可玩区与墙体（①-⑥⑩⑪，共 29 条），
## 坝顶远景件/斜置扶壁垛/窗带/泄洪管不注册（性能红线既定取舍）。
## 旋转惯例（仅泄洪管保留）：坡面与水平夹 atan(7.8/6)=52.43°，Godot rotation.x
## 从竖直轴起算，贴坡管 rotation.x = -(PI/2 - 52.43°) = -0.6557 rad（上端朝北埋入坝体）。

const SLOPE_ANG := 0.9151          # atan(7.8/6)：台阶坡面与水平夹角 52.43°
const FIN_TILT := 0.6557           # PI/2 - SLOPE_ANG：泄洪管贴坡绕 x 的转角（从竖直轴起算）
const TOP_Y := 52.0                # 坝顶高程（路面块 y44.2→52，路面板铺其上）
const STEP_H := 7.8                # 台阶每级升高（4 级 y13→44.2）
const STEP_D := 6.0                # 台阶每级进深（front 逐级 -114/-120/-126/-132）

## 泄洪大管 x 位（扶壁垛跨中点 ±3.5；与垛中心距 5.5 > r3.2+垛半厚0.75 零相交）
const PIPE_XS := [-98.5, -91.5, -80.5, -73.5, 63.5, 70.5]
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
## —— 恰 5 枚材质（契约：dam 5 枚零跨文件引用，厂房黄/集装箱红等归 base）——
var _mat_concrete: StandardMaterial3D        # 坝体主混凝土（NoiseTexture2D 渍纹）
var _mat_concrete_dark: StandardMaterial3D   # 暗色件：路面/窗片/暗门片
var _mat_steel_red: StandardMaterial3D       # 红钢件：门吊/闸墩（metallic 0.3）
var _mat_pipe: StandardMaterial3D            # 泄洪管/栏杆（metallic 0.55）
var _mat_graffiti: StandardMaterial3D        # 涂鸦红（无透明，环+斜杠+滴泪）
## —— 共用网格（全模块唯一 mesh 仅 8 种：盒件共用单位盒 + 实例 scale 定尺寸）——
var _mesh_box: BoxMesh                       # 单位盒：约 230 处盒件循环共用
var _mesh_post: CylinderMesh                 # 栏杆柱 r0.08 h1.1 seg6（×100 共用）
var _mesh_col: CylinderMesh                  # 廊道柱 r0.7 h12.9 seg24（×15 共用）
var _mesh_pipe: CylinderMesh                 # 泄洪大管 r3.2 h55 seg32（×6 共用，出口短管缩放复用）
var _mesh_collar: TorusMesh                  # 管箍环（×24 共用）
var _mesh_drain: CylinderMesh                # 排水细管 r0.3 h30 seg8（×4 共用）
var _mesh_graffiti: TorusMesh                # 涂鸦圆环 R12 管 0.9（×1，实例 scale.y=0.12 压扁）
var _mesh_dome: SphereMesh                   # 取水塔穹顶 r9（×2 共用，实例 scale.y=0.5 压扁）


## 装配入口（root 即 HDWorld）：视觉 add_child(root)，障碍 root.obstacles.append
func build(root) -> void:
	if _built:
		return
	_built = true
	_make_mats()
	_make_meshes()
	_base(root)            # A 坝基实体
	_steps(root)           # B 下游台阶面
	_overflow(root)        # C 溢流坝段
	_top_road(root)        # D 坝顶路面+女儿墙
	_railing(root)         # E 坝顶栏杆
	_fins(root)            # F 扶壁垛阵列
	_cranes_top(root)      # G 坝顶红龙门吊×2+塔吊×1
	_cranes_ground(root)   # H 地面红门吊×2
	_pipes(root)           # I 泄洪大圆柱管
	_drains(root)          # J 坝面排水细管
	_gates(root)           # K 溢洪道闸墩排
	_graffiti(root)        # L 坝面红色涂鸦圆环
	_corridor(root)        # M 坝底廊道层
	_window_band(root)     # N 中层廊道窗带
	_towers(root)          # O 西端取水塔×2
	_street(root)          # W 服务街道条


func _make_mats() -> void:
	# 主混凝土：albedo 乘 512² 无缝噪点（渍纹），hd_world.gd:343-360 大地同款先例
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
	ramp.set_color(0, Color(0.52, 0.5, 0.46))   # 渍纹暗斑
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	_mat_concrete = StandardMaterial3D.new()
	_mat_concrete.albedo_color = Color(0.6, 0.58, 0.55)
	_mat_concrete.albedo_texture = tex
	_mat_concrete.uv1_scale = Vector3(10.0, 10.0, 1.0)
	_mat_concrete.roughness = 0.95
	_mat_concrete_dark = StandardMaterial3D.new()
	_mat_concrete_dark.albedo_color = Color(0.38, 0.37, 0.35)
	_mat_concrete_dark.roughness = 0.95
	_mat_steel_red = StandardMaterial3D.new()
	_mat_steel_red.albedo_color = Color(0.52, 0.07, 0.05)
	_mat_steel_red.metallic = 0.3
	_mat_steel_red.roughness = 0.45
	_mat_pipe = StandardMaterial3D.new()
	# 色温对齐黄昏太阳（hd_world.gd:299 Color(1.0,0.74,0.52) 暖橙）：泄洪管原
	# (0.42,0.45,0.48) 蓝灰是全坝唯一冷调结构材质，低角度夕照下与坝体暖灰脱节；
	# 收暖为 R>B 暖钢灰 (0.48,0.44,0.40)，与混凝土 (0.60,0.58,0.55) 同一暖偏侧，
	# metallic0.55 保留橙霞天穹反射（ProceduralSky 地平线 0.92,0.5,0.28）
	_mat_pipe.albedo_color = Color(0.48, 0.44, 0.4)
	_mat_pipe.metallic = 0.55
	_mat_pipe.roughness = 0.4
	_mat_graffiti = StandardMaterial3D.new()
	_mat_graffiti.albedo_color = Color(0.75, 0.06, 0.05)   # 无透明：纯实心涂鸦红
	_mat_graffiti.roughness = 0.6


func _make_meshes() -> void:
	_mesh_box = BoxMesh.new()
	_mesh_box.size = Vector3.ONE   # BoxMesh 默认 2m 见方，压回单位盒配合实例 scale
	_mesh_post = CylinderMesh.new()
	_mesh_post.top_radius = 0.08
	_mesh_post.bottom_radius = 0.08
	_mesh_post.height = 1.1
	_mesh_post.radial_segments = 6
	_mesh_col = CylinderMesh.new()
	_mesh_col.top_radius = 0.7
	_mesh_col.bottom_radius = 0.7
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


## 摆盒：共用单位 BoxMesh + 实例 scale 定尺寸（网格构成红线：唯一 mesh 数收敛）
func _box(root, size: Vector3, pos: Vector3, mat: StandardMaterial3D,
		rot_x := 0.0, rot_z := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_box
	mi.scale = size
	mi.position = pos
	mi.rotation.x = rot_x
	mi.rotation.z = rot_z
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
			_ob(root, sx, front - STEP_D * 0.5, 60.0, STEP_D * 0.5,
					bot + STEP_H, bot)
		_box(root, Vector3(120.0, STEP_H, 10.0), Vector3(sx, 48.1, -143.0), _mat_concrete)
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

## 柱距 6m ×100（-147→147 每侧 50 根，同 Mesh 复用）+ 扁钢轨 ×4（每侧上下两道）
func _railing(root) -> void:
	for pz in [-138.4, -147.6]:
		for k in 50:
			var px: float = -147.0 + 6.0 * float(k)
			_inst(root, _mesh_post, Vector3(px, 53.55, pz), _mat_pipe)
		for ry in [53.45, 54.02]:
			_box(root, Vector3(296.0, 0.08, 0.08), Vector3(0.0, ry, pz), _mat_pipe)


# ================= F 扶壁肋柱阵列 ×16 =================

## 竖向贴面肋柱（第 2 轮观感返工）：1.5 厚×39 高×2 深，y13（廊道顶）→52（坝顶），
## 中心 z=-122.9 → 背面 -123.9 嵌入 C 面 0.1 消共面、前脸 -121.9 凸出 2.1m（契约 ≤2m 口径）；
## 柱距 18m（x_k=-140+18k 共 16 榀）保持参考图扶壁柱节奏；环被柱带打断原样保留
## （x=-14/4 两柱竖向切过涂鸦环弧）。与泄洪管 x 向距 ≥5.5、与闸墩距 ≥3.2、
## 与排水管距 ≥2 零相交；无碰撞（凸出 ≤2.1m，坡体/溢流段 AABB 兜底）。
## 西端两柱（x=-140/-122）落取水塔体内被吞（塔 18 见方罩住）——远景 150m 外不显，维持 16 榀节奏
func _fins(root) -> void:
	for k in 16:
		var xk: float = -140.0 + 18.0 * float(k)
		_box(root, Vector3(1.5, 39.0, 2.0), Vector3(xk, 32.5, -122.9), _mat_concrete)


# ================= G/H 红龙门吊与塔吊 =================

## 门吊生成器：双腿 + 主梁 + 小车（红钢）；近景（地面门吊）加吊缆+吊钩
func _gantry(root, base: Vector3, leg_h: float, with_hook: bool) -> void:
	for sx in [-7.0, 7.0]:
		_box(root, Vector3(1.6, leg_h, 1.6), base + Vector3(sx, leg_h * 0.5, 0.0),
				_mat_steel_red)
	_box(root, Vector3(16.0, 0.9, 1.4), base + Vector3(0.0, leg_h + 0.45, 0.0),
			_mat_steel_red)
	_box(root, Vector3(2.2, 1.4, 1.8), base + Vector3(2.0, leg_h + 0.1, 0.0),
			_mat_steel_red)
	if with_hook:
		var top: float = leg_h - 0.6
		_box(root, Vector3(0.12, 2.2, 0.12), base + Vector3(2.0, top - 1.1, 0.0),
				_mat_pipe)
		_box(root, Vector3(0.45, 0.5, 0.45), base + Vector3(2.0, top - 2.45, 0.0),
				_mat_concrete_dark)


## 塔吊：塔身+驾驶室（暗色）+双伸臂+配重（远景天际线，粗模）
func _tower_crane(root, base: Vector3) -> void:
	_box(root, Vector3(2.2, 16.0, 2.2), base + Vector3(0.0, 8.0, 0.0), _mat_steel_red)
	_box(root, Vector3(2.8, 2.2, 2.8), base + Vector3(0.0, 15.1, 0.0), _mat_concrete_dark)
	_box(root, Vector3(24.0, 0.8, 1.2), base + Vector3(0.0, 16.4, 0.0), _mat_steel_red)
	_box(root, Vector3(2.0, 1.8, 2.4), base + Vector3(-8.0, 15.3, 0.0), _mat_concrete_dark)


## 坝顶红龙门吊×2（x=-40/55）+ 塔吊×1（x=-5），y52 起 z=-143，纯远景无碰撞
func _cranes_top(root) -> void:
	for gx in [-40.0, 55.0]:
		_gantry(root, Vector3(gx, 52.0, -143.0), 9.0, false)
	_tower_crane(root, Vector3(-5.0, 52.0, -143.0))


## 地面红门吊×2 @(-18,-106)/(22,-106)（廊道前广场记忆点）：
## 复用门吊生成器落 y0，只注册腿碰撞（2 条/台，梁 y8+ 可穿行）
func _cranes_ground(root) -> void:
	for gx in [-18.0, 22.0]:
		_gantry(root, Vector3(gx, 0.0, -106.0), 8.0, true)
		for sx in [-7.0, 7.0]:
			_ob(root, gx + sx, -106.0, 0.8, 0.8, 8.0)


# ================= I 泄洪大圆柱管 =================

## 3 组×2 根：r3.2 长 55 贴坡（rot.x=-FIN_TILT），根端 y8 出坝、顶端 y51.6 没入坝顶；
## 每根 4 道箍环（TorusMesh 同转角）；出口短管 ×2 落 (71.5/78.5, 8, -105)
## （与大管 70.5 根端刻意交汇成汇流 manifold 观感）。无碰撞（近景结构件让走位）
func _pipes(root) -> void:
	var dir := Vector3(0.0, cos(SLOPE_ANG), -sin(SLOPE_ANG))
	for px in PIPE_XS:
		var c := Vector3(px, 29.8, -122.9)
		_inst(root, _mesh_pipe, c, _mat_pipe, -FIN_TILT)
		for t in COLLAR_TS:
			_inst(root, _mesh_collar, c + dir * float(t), _mat_pipe, -FIN_TILT)
	for ox in [71.5, 78.5]:
		_inst(root, _mesh_pipe, Vector3(ox, 8.0, -105.0), _mat_pipe,
				PI * 0.5, Vector3(1.0, 0.2, 1.0))


# ================= J 坝面排水细管 ×4 =================

## r0.3 长 30 垂直贴 C 面（管面 z∈[-123.9,-123.3]），从窗带后方穿环而下
func _drains(root) -> void:
	for dx in DRAIN_XS:
		_inst(root, _mesh_drain, Vector3(dx, 32.5, -123.6), _mat_pipe)


# ================= K 溢洪道闸墩排 =================

## 闸墩 ×7（1.8×12×1.8 红钢，定深贴面 z∈[-124,-122.2]）+ 门楣梁 ×2（顶梁坐墩顶/
## 底梁贴 C 面）+ 暗门片 ×6（墩间内退 z=-123.75）；涂鸦环从墩盒内刺过
## （环管面 z∈[-123.91,-123.69] 严格在墩盒内部，约 9% 弧被墩正面遮挡=参考图原样）
func _gates(root) -> void:
	for i in PIER_COUNT:
		var px: float = PIER_X0 + PIER_STEP * float(i)
		_box(root, Vector3(1.8, 12.0, 1.8), Vector3(px, 38.0, -123.1), _mat_steel_red)
		_ob(root, px, -123.1, 0.9, 0.9, 44.0, 30.0)
	_box(root, Vector3(60.0, 1.2, 1.8), Vector3(0.0, 44.6, -123.1), _mat_steel_red)
	_box(root, Vector3(60.0, 1.2, 1.8), Vector3(0.0, 31.4, -123.1), _mat_steel_red)
	for gx in [-21.5, -12.9, -4.3, 4.3, 12.9, 21.5]:
		_box(root, Vector3(6.8, 11.0, 0.3), Vector3(gx, 38.0, -123.75),
				_mat_concrete_dark)


# ================= L 坝面红色涂鸦圆环 =================

## 参考图最醒目记忆点：扁圆环（R12 管 0.9，实例 scale.y=0.12 → 环管面
## z∈[-123.91,-123.69]，整圆 y17.1→42.9 贴 C 竖直面）+ 45° 斜杠 + 滴泪条 ×6
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
	for dx in DRIP_DXS:
		var y_arc: float = 30.0 - sqrt(12.9 * 12.9 - dx * dx)
		var drip_top: float = y_arc + 0.4
		var drip_h: float = drip_top - 19.0
		_box(root, Vector3(0.5, drip_h, 0.14),
				Vector3(-4.0 + dx, (drip_top + 19.0) * 0.5, -123.8), _mat_graffiti)


# ================= M 坝底廊道层 =================

## 前墙 4 段（y0→13.1，比顶梁顶面高 0.1 消共面；开洞留空 x=-30/10/50 各 16 宽）+
## 顶梁 300.8×3.5×6.6（y9.5→13；x 向出檐 0.4、前脸 -111.8 出 0.2 成楣带，全消共面）+
## 柱廊柱 ×15（r0.7 h12.9，z=-111.25）+ 暗门片 ×12（bay 中心，避 3 开洞）。
## 背墙即 A 前立面 z=-118；开洞净高 9.5 可走进，容器①②③在洞内
func _corridor(root) -> void:
	for seg in [[-94.0, 112.0], [-10.0, 24.0], [30.0, 24.0], [104.0, 92.0]]:
		_box(root, Vector3(seg[1], 13.1, 6.0), Vector3(seg[0], 6.55, -115.0),
				_mat_concrete)
		_ob(root, seg[0], -115.0, seg[1] * 0.5, 3.0, 13.0)
	_box(root, Vector3(300.8, 3.5, 6.6), Vector3(0.0, 11.25, -115.1), _mat_concrete)
	for k in 15:
		var cx: float = -140.0 + 20.0 * float(k)
		_inst(root, _mesh_col, Vector3(cx, 6.45, -111.25), _mat_concrete)
	for px in PANEL_XS:
		_box(root, Vector3(6.0, 8.1, 0.3), Vector3(px, 5.25, -111.8),
				_mat_concrete_dark)


# ================= N 中层廊道窗带 =================

## 肩段（x∈[-138,-36]/[36,138]）背板 102×4.5×1.2 贴 step2 front + 窗片 ×12/侧；
## 中央段取消背板只留 0.2 厚窗片 ×6（z∈[-122.8,-122.6]，y15→17.5 避环底 y18——
## 涂鸦环与排水管全部从窗片后方穿过=正确遮挡）。无碰撞
func _window_band(root) -> void:
	for sx in [-87.0, 87.0]:
		_box(root, Vector3(102.0, 4.5, 1.2), Vector3(sx, 23.25, -119.4),
				_mat_concrete_dark)
		var x0: float = -132.0 if sx < 0.0 else 44.0
		for k in 12:
			var wx: float = x0 + 8.0 * float(k)
			_box(root, Vector3(3.0, 2.5, 0.2), Vector3(wx, 23.25, -118.7),
					_mat_concrete_dark)
	for wx in CWIN_XS:
		_box(root, Vector3(3.0, 2.5, 0.2), Vector3(wx, 16.25, -122.7),
				_mat_concrete_dark)


# ================= O 西端取水塔 ×2 =================

## 塔身 18×34×18 + 压扁穹顶（r9 scale(1,0.5,1)）总高 38.5；中心距 18.2
## （塔面间隙 0.2 消共面）；前脸 z=-114 挺出廊道带后景
func _towers(root) -> void:
	for tx in [-138.1, -119.9]:
		_box(root, Vector3(18.0, 34.0, 18.0), Vector3(tx, 17.0, -123.0), _mat_concrete)
		_inst(root, _mesh_dome, Vector3(tx, 34.0, -123.0), _mat_concrete,
				0.0, Vector3(1.0, 0.5, 1.0))
		_ob(root, tx, -123.0, 9.0, 9.0, 39.0)


# ================= W 服务街道条 =================

## 210×0.05×4 暗色路带（z=-90，x∈[-130,80]）：坝底服务街的铺装记忆线
func _street(root) -> void:
	_box(root, Vector3(210.0, 0.05, 4.0), Vector3(-25.0, 0.025, -90.0),
			_mat_concrete_dark)
