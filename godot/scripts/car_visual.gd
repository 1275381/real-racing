class_name CarVisual
extends Node3D
## 车模实例：优先 Blender GLB（复用网页版 assets 的 car_*.glb，命名契约一致：
## HubXX 转向枢轴 / WheelXX 滚动 / BodyPivot 车身姿态，材质 Paint/Accent/TailLight 染色），
## 缺失或损坏时回退到内置程序化车型。

const TIRE_R := 0.34

var wheels := {}          # "FL" -> {pivot: Node3D, spin: Node3D}
var body_pivot: Node3D
var body_pivot_rest := Vector3.ZERO      # GLB 导入的静息姿态（动画在其上叠加）
var body_pivot_rest_pos := Vector3.ZERO
var tail_mat: StandardMaterial3D
var using_glb := false

var _rest_euler := {}     # Node3D -> Vector3（导入时的静息欧拉角，动画时在其上叠加）
var _spin_angle := 0.0

# ---- 主动尾翼 / 空力套件（aiaero「风刃」等带 aero 键的车型；旧车全程为 null）----
var wing_pivot: Node3D = null       # 尾翼总成枢轴（升起位移挂这里）
var wing_blade: Node3D = null       # 翼片（迎角转轴）
var _wing_rest_y := 0.0             # 枢轴静息高度（升起量在其上叠加）
var _wing_rest_rx := 0.035          # 翼片静息迎角 ≈2°（平贴收敛位）
var _wing_t := 0.0                  # 展开量 0..1（速度驱动，move_toward 确定性插值）
var _wing_ab := 0.0                 # 急刹空气制动量 0..1（独立插值）
var _wing_raise_kmh := 90.0         # 起升阈值（仪表速度）
var _wing_full_kmh := 200.0         # 全展开阈值
var _wing_brake_kmh := 60.0         # 低于此速急刹不做气动刹车
var _aero_mats: Array = []          # 碳黑空力件材质名单：_apply_paint_gloss 遍历时跳过


static func available_model_ids() -> Array:
	var out: Array = []
	for m in TrackData.CAR_MODELS:
		# proc_body：程序化专属车身（零 GLB），无 file 键也不能从车库列表消失
		if m.has("proc_body") or ResourceLoader.exists(m.get("file", "")):
			out.append(m["id"])
	return out


static func create(model_id: String, color: Color, accent: Color) -> CarVisual:
	var cv := CarVisual.new()
	var def: Dictionary = TrackData.model_by_id(model_id)
	var built := false
	if def.has("proc_body"):
		cv._build_windblade(def, color, accent)
		built = true
	elif ResourceLoader.exists(def.get("file", "")):
		built = cv._build_from_glb(def, color, accent)
	if not built:
		cv._build_fallback(color, accent)
	cv._apply_paint_gloss()
	# 车底软阴影
	cv._add_blob_shadow()
	return cv


## 车漆质感：清漆层 + 适度金属度（Forward+ 天空反射下车身高光会流动）
func _apply_paint_gloss() -> void:
	var stack: Array = [self]
	var seen := {}
	while not stack.is_empty():
		var n = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat == null or not (mat is BaseMaterial3D):
					continue
				var bm := mat as BaseMaterial3D
				if seen.has(bm):
					continue
				seen[bm] = true
				# 碳黑空力件保住 roughness 0.55 哑光质感，不吃亮漆 clearcoat
				if _aero_mats.has(bm):
					continue
				bm.roughness = minf(bm.roughness, 0.42)
				bm.metallic = maxf(bm.metallic, 0.12)
				bm.clearcoat_enabled = true
				bm.clearcoat = 0.45
				bm.clearcoat_roughness = 0.18


func _find(node_name: String) -> Node3D:
	return find_child(node_name, true, false) as Node3D


func _build_from_glb(def: Dictionary, color: Color, accent: Color) -> bool:
	var packed: PackedScene = load(def["file"])
	if packed == null:
		return false
	var root := packed.instantiate()
	if root == null:
		return false
	# 模型级修正（TrackData 可选字段）：yaw_deg 摆正车头到 +Z，scale 统一到整队车长
	root.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(float(def.get("yaw_deg", 0.0))))
			.scaled(Vector3.ONE * float(def.get("scale", 1.0))), Vector3.ZERO)
	add_child(root)
	using_glb = true

	# ---- 每车克隆并染色共享材质 ----
	var mat_map := {}
	tail_mat = null
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var mesh := mi.mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat == null or not (mat is BaseMaterial3D):
					continue
				var mname := String(mat.resource_name)
				if mname == "Paint" or mname == "Accent":
					if not mat_map.has(mat):
						var c: BaseMaterial3D = mat.duplicate()
						c.albedo_color = color if mname == "Paint" else accent
						mat_map[mat] = c
					mi.set_surface_override_material(i, mat_map[mat])
				elif mname == "TailLight":
					if tail_mat == null:
						tail_mat = mat.duplicate()
						tail_mat.emission_enabled = true
						tail_mat.emission = Color(1.0, 0.1, 0.1)
						tail_mat.emission_energy_multiplier = 0.42
					mi.set_surface_override_material(i, tail_mat)

	if tail_mat == null:
		tail_mat = StandardMaterial3D.new()
		tail_mat.albedo_color = Color("#300505")
		tail_mat.emission_enabled = true
		tail_mat.emission = Color(1.0, 0.1, 0.1)
		tail_mat.emission_energy_multiplier = 0.42

	body_pivot = _find("BodyPivot")
	var missing_wheel := false
	for k in ["FL", "FR", "RL", "RR"]:
		var pivot := _find("Hub" + k)
		var spin := _find("Wheel" + k)
		if pivot == null or spin == null:
			missing_wheel = true
			break
		wheels[k] = {"pivot": pivot, "spin": spin}

	if missing_wheel:
		# AI 生成的整块网格车模：车轮不是独立节点，无法滚动/转向。
		# 不再回退方块车，直接采用：以车身中心包一层 BodyPivot，
		# 车身俯仰/侧倾/颠簸动画照常，车轮动画留空即可。
		wheels.clear()
		var aabb := _tree_aabb(root)
		root.get_parent().remove_child(root)
		# 贴地归一：AI 模型的原点可能在车高中面（底面悬在 -h/2），
		# 统一把底面抬到 y=0（车轮接地面），否则整车陷进地里；
		# 底面本就在 0 的模型此步为零位移
		root.position.y -= aabb.position.y
		var body := Node3D.new()
		body.name = "BodyPivot"
		body.position = Vector3(0, aabb.size.y * 0.45, 0)
		add_child(body)
		root.position.y -= body.position.y
		body.add_child(root)
		body_pivot = body
		# 空力套件只建在整块网格车模上（aabb 在本分支内才有效，见上）；
		# def 无 aero 键立即返回，旧车零开销
		_build_aero(def, aabb, body)
	else:
		if body_pivot == null:
			body_pivot = self

	body_pivot_rest = body_pivot.rotation
	body_pivot_rest_pos = body_pivot.position
	_cache_rest(root)
	return true


## 程序化空力套件 + 主动尾翼（挂在 BodyPivot 上随车身俯仰/侧倾）。
## 入参 aabb 为整车包围盒（车底已在 y=0）：hl/hw/hh 按实测比例落位，
## 全套件收敛在车身轮廓内；def 无 aero 键直接返回（旧车零开销）。
func _build_aero(def: Dictionary, aabb: AABB, body: Node3D) -> void:
	var aero: Dictionary = def.get("aero", {})
	if aero.is_empty():
		return
	var hl := aabb.size.z * 0.5     # 车长半轴（车头 +Z）
	var hw := aabb.size.x * 0.5     # 半车宽
	var hh := aabb.size.y           # 车高
	_wing_raise_kmh = float(aero.get("wing_kmh", 90.0))
	_wing_full_kmh = float(aero.get("full_kmh", 200.0))
	_wing_brake_kmh = float(aero.get("brake_kmh", 60.0))

	# 共享碳黑哑光材质：登记进 _aero_mats，_apply_paint_gloss 跳过不变亮漆
	var carbon := StandardMaterial3D.new()
	carbon.albedo_color = Color("#16181c")
	carbon.metallic = 0.35
	carbon.roughness = 0.55
	_aero_mats.append(carbon)

	# body 枢轴在车高中面偏上（y=hh*0.45），件的高度都是离地坐标，挂 body 时补偿
	var dy := -body.position.y
	# 通用建件：名字/尺寸/离地位姿/父节点/欧拉角（离地 y 减父节点 y 换算本地系）
	var add := func(name: String, size: Vector3, ground_pos: Vector3,
			parent: Node3D, rot: Vector3) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = name
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = carbon
		mi.mesh = mesh
		mi.position = ground_pos - Vector3(0, parent.position.y, 0)
		mi.rotation = rot
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mi)
		return mi

	# 前铲：贴前唇下缘探出，底缘离地 3.5cm 不蹭地
	add.call("AeroSplitter", Vector3(hw * 1.72, 0.05, 0.40),
			Vector3(0, 0.06, hl * 0.86), body, Vector3.ZERO)
	# 前扰流小翼×2：装前杠两角不遮车灯，各外撇 ∓8°
	add.call("AeroCanardL", Vector3(0.26, 0.035, 0.14),
			Vector3(hw * 0.82, hh * 0.30, hl * 0.72), body,
			Vector3(0, deg_to_rad(-8.0), 0))
	add.call("AeroCanardR", Vector3(0.26, 0.035, 0.14),
			Vector3(-hw * 0.82, hh * 0.30, hl * 0.72), body,
			Vector3(0, deg_to_rad(8.0), 0))
	# 侧裙×2：外缘内缩约 1cm 不外撇（hw-0.055 与 hw*0.90 取大者兜底窄车）
	var sk_x := maxf(hw - 0.055, hw * 0.90)
	add.call("AeroSkirtL", Vector3(0.09, 0.10, hl * 1.02),
			Vector3(sk_x, 0.075, -hl * 0.06), body, Vector3.ZERO)
	add.call("AeroSkirtR", Vector3(0.09, 0.10, hl * 1.02),
			Vector3(-sk_x, 0.075, -hl * 0.06), body, Vector3.ZERO)
	# 后扩散器：斜板后缘上翘 +10°，四片鳍片同角度跟随（斜置）
	var tilt := Vector3(deg_to_rad(10.0), 0, 0)
	add.call("AeroDiffuser", Vector3(hw * 1.42, 0.05, 0.50),
			Vector3(0, 0.09, -hl * 0.90), body, tilt)
	for i in 4:
		var fx: float = [hw * 0.26, hw * 0.62, -hw * 0.26, -hw * 0.62][i]
		add.call("AeroFin%d" % (i + 1), Vector3(0.025, 0.16, 0.46),
				Vector3(fx, 0.13, -hl * 0.90), body, tilt)

	# 主动尾翼总成：双支柱 + 翼片 + 端板（总成本体挂 body，子件用总成本地坐标）。
	# 收敛位翼面高约 hh*0.87 低于车顶，全展开支柱 +13cm / 迎角 +32°，
	# 仍落车身轮廓内不穿模
	wing_pivot = Node3D.new()
	wing_pivot.name = "WingPivot"
	wing_pivot.position = Vector3(0, hh * 0.70 + dy, -hl * 0.86)
	body.add_child(wing_pivot)
	var wing_add := func(name: String, size: Vector3, local_pos: Vector3,
			parent: Node3D) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = name
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = carbon
		mi.mesh = mesh
		mi.position = local_pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mi)
		return mi
	wing_add.call("WingStrutL", Vector3(0.05, 0.20, 0.10),
			Vector3(hw * 0.48, 0.10, 0), wing_pivot)
	wing_add.call("WingStrutR", Vector3(0.05, 0.20, 0.10),
			Vector3(-hw * 0.48, 0.10, 0), wing_pivot)
	wing_blade = wing_add.call("WingBlade", Vector3(hw * 1.48, 0.04, 0.34),
			Vector3(0, 0.21, 0), wing_pivot)
	wing_blade.rotation.x = _wing_rest_rx
	# 端板挂翼片子节点，随翼片同转
	wing_add.call("WingEndplateL", Vector3(0.03, 0.12, 0.36),
			Vector3(hw * 0.74, 0, 0), wing_blade)
	wing_add.call("WingEndplateR", Vector3(0.03, 0.12, 0.36),
			Vector3(-hw * 0.74, 0, 0), wing_blade)

	_wing_rest_y = wing_pivot.position.y


func _tree_aabb(n: Node) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [[n, Transform3D()]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		if e[0] is Node3D:
			e[1] = e[1] * (e[0] as Node3D).transform
		if e[0] is MeshInstance3D:
			var ab: AABB = e[1] * (e[0] as MeshInstance3D).get_aabb()
			total = ab if first else total.merge(ab)
			first = false
		for c in e[0].get_children():
			stack.append([c, e[1]])
	return total


func _cache_rest(node: Node) -> void:
	if node is Node3D:
		_rest_euler[node] = (node as Node3D).rotation
	for c in node.get_children():
		_cache_rest(c)


## 每帧：车轮滚动/转向 + 刹车灯
func animate(dt: float, vf: float, steer_vis: float, braking: bool) -> void:
	_spin_angle += (vf / TIRE_R) * dt
	for k in wheels:
		var spin: Node3D = wheels[k]["spin"]
		var rest: Vector3 = _rest_euler.get(spin, Vector3.ZERO)
		spin.rotation = Vector3(rest.x + _spin_angle, rest.y, rest.z)
	for k in ["FL", "FR"]:
		if wheels.has(k):
			var pivot: Node3D = wheels[k]["pivot"]
			var prest: Vector3 = _rest_euler.get(pivot, Vector3.ZERO)
			pivot.rotation = Vector3(prest.x, prest.y + steer_vis, prest.z)
	if tail_mat != null:
		tail_mat.emission_energy_multiplier = 3.6 if braking else 0.42
	# ---- 主动尾翼状态机（旧车 wing_pivot 为 null 整段跳过）----
	# 仪表速度超阈值起升、更高速度全展开；急刹且车速够快时翼片冲近竖立
	# 充当气动阻力板。move_toward 线性插值保证确定性可断言：
	# 展开/收敛全程 0.22s，急刹空气制动全程 0.12s，两态独立插值
	if wing_pivot != null and wing_blade != null:
		var kmh := absf(vf) * 3.6
		var target := clampf((kmh - _wing_raise_kmh)
				/ maxf(_wing_full_kmh - _wing_raise_kmh, 1.0), 0.0, 1.0)
		_wing_t = move_toward(_wing_t, target, dt / 0.22)
		_wing_ab = move_toward(_wing_ab,
				1.0 if braking and kmh > _wing_brake_kmh else 0.0, dt / 0.12)
		wing_pivot.position.y = _wing_rest_y + _wing_t * 0.13 + _wing_ab * 0.02
		wing_blade.rotation.x = _wing_rest_rx + _wing_t * 0.56 + _wing_ab * 0.50


# ---------------- 倒角件引擎（移植自 huodai hd_gunlib 的 7 符号闭包） ----------------
# 跨工程不可 preload（新文件 + class_name 曾两次挂回归，见 hd_gunlib.gd:4-6 头注释），
# 故整套闭包原样复制进本文件并按车级域改私有名：SEG_CHAMFER / _FACE_AXES /
# _count_verts / _mesh_verts_local / _chamfer_box / _axis_half / _push_tri。
# 六外表面严格保原盒面（面网格点 = 内收盒 clamp + 径向推回，平面区恰落 ±half 面，
# 仅棱角内收）→ 盒占位探针即倒角件 AABB，风刃件表标定可直接复用。

## 倒角盒每面网格分段（顶点 = 6·seg²+2 / 件，与 chamfer 半径无关）
const SEG_CHAMFER := 6

## 六面基架：n=外法线 / t1·t2=面内两轴（t1×t2=n）。Godot 正面=顺时针环绕，
## 三角形按 p00→p01→p11 / p00→p11→p10 出（t1 右 t2 上视角的顺时针）
const _FACE_AXES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


## 统计 root（含自身）子树所有 MeshInstance3D 的 0 号面顶点和——
## test_aero 顶点红线断言共用（防退化回直角方块车）
static func _count_verts(root: Node) -> int:
	var total := 0
	if root is MeshInstance3D:
		total += _mesh_verts_local((root as MeshInstance3D).mesh)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		total += _mesh_verts_local((mi as MeshInstance3D).mesh)
	return total


## 单 mesh 顶点数（无面/无顶点数组 = 0）
static func _mesh_verts_local(m: Mesh) -> int:
	if m == null or m.get_surface_count() == 0:
		return 0
	var arrs: Array = m.surface_get_arrays(0)
	if arrs.is_empty():
		return 0
	var v: Variant = arrs[Mesh.ARRAY_VERTEX]
	if v == null:
		return 0
	return (v as PackedVector3Array).size()


## 倒角方块：外盒表面每面 seg×seg 网格采样（cosine 间距向四边棱线加密），
## 每点先向内盒（半边长各收 chamfer）收拢、再沿径向推出 chamfer——
## 平面区严格贴原盒面、12 条棱变四分之一圆柱、8 角变球面：直角棱线消除、
## 法线全平滑。顶点 = 6·seg²+2 / 三角 = 12·seg²。
## 与枪械版唯一差异：chamfer<0 的自动值按车级钳 15~60mm（枪械版是 0.8~4mm，
## 对米级车身等于没倒角；平面区贴盒面的几何性质与该值无关，AABB 结论不受影响）
static func _chamfer_box(parent: Node3D, mat: Material, size: Vector3,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO,
		chamfer: float = -1.0, seg: int = SEG_CHAMFER) -> MeshInstance3D:
	var half := size * 0.5
	var c := chamfer
	if c < 0.0:
		c = clampf(minf(size.x, minf(size.y, size.z)) * 0.18, 0.015, 0.06)
	var hi := Vector3(maxf(half.x - c, 0.0004), maxf(half.y - c, 0.0004),
			maxf(half.z - c, 0.0004))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axes in _FACE_AXES:
		var n: Vector3 = axes[0]
		var t1: Vector3 = axes[1]
		var t2: Vector3 = axes[2]
		var hn := _axis_half(n, half)   # 面沿法线的半边长
		var h1 := _axis_half(t1, half)  # 面沿 t1 的半边长
		var h2 := _axis_half(t2, half)  # 面沿 t2 的半边长
		var grid: Array = []
		for i in seg + 1:
			var u: float = -cos(PI * float(i) / float(seg))
			var col: Array = []
			for j in seg + 1:
				var v: float = -cos(PI * float(j) / float(seg))
				var q: Vector3 = n * hn + t1 * (u * h1) + t2 * (v * h2)
				var inn := Vector3(clampf(q.x, -hi.x, hi.x),
						clampf(q.y, -hi.y, hi.y), clampf(q.z, -hi.z, hi.z))
				var dn := (q - inn).normalized()
				col.append([inn + dn * c, dn])
			grid.append(col)
		for i in seg:
			for j in seg:
				_push_tri(st, grid[i][j], grid[i][j + 1], grid[i + 1][j + 1])
				_push_tri(st, grid[i][j], grid[i + 1][j + 1], grid[i + 1][j])
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## 单轴单位向量的半边长取值（axis 是 ±单轴单位向量）
static func _axis_half(axis: Vector3, half: Vector3) -> float:
	return absf(axis.x) * half.x + absf(axis.y) * half.y + absf(axis.z) * half.z


## 推一个三角形（各顶点 [位置, 法线]；Godot 正面 = 顺时针环绕）
static func _push_tri(st: SurfaceTool, a: Array, b: Array, c2: Array) -> void:
	for p in [a, b, c2]:
		st.set_normal(p[1])
		st.add_vertex(p[0])


# ---------------- 风刃·刃形 speedform 专属车身（aiaero，100% 程序化零 GLB） ----------------

## 件表（米制、地面 y=0、车头 +Z；除 NoseDeck 前低后高 4° 外零旋转）——
## 外廓 4.60×2.02×1.08m，实测 AABB position=(−1.01,0.06,−2.30) size=(2.02,1.02,4.60)：
## ①KeelNose 龙骨船艏 PrismMesh(1.30,0.30,1.10)@(0,0.30,+1.75)（棱线沿 Z 居中置顶，
##   正投影 V 形船艏，探针实证 AABB 严格=占位盒）②NoseDeck 楔形甲板 倒角
##   (1.30,0.10,1.10)@(0,0.50,+1.75) 前低后高 4°（rotation.x=+4°：前缘 −0.038/后缘
##   +0.038 补出侧面楔形接 Tub 顶）③Tub 主舱 倒角(2.02,0.36,2.30)@(0,0.44,+0.05)
##   全车最宽 ±1.01 ④CanopyF/M 烟熏舱罩 ⑤CanopyR 引擎舱甲板+Periscope 潜望进气口
##   固定碳黑 ⑥BoatTail 船尾+TailDeck 尾甲板 z∈[−2.30,−1.10] 无缝接 Tub ⑦Floorboard
##   底板底 0.06 全车最低 ⑧轮眉浮筒×4 顶 0.68 恰盖胎顶 ⑨刃青饰条/白青刃灯/尾灯带。
## 涂装四层：队色亮漆上壳 / 烟熏舱罩 / 固定碳黑下盘（_aero_mats 保哑光不吃亮漆）/
## 刃青 #39d7d0 + 白青发光签名色（不进队色）——任何队色下都是亮漆+碳黑+青刃三层拼色。
func _build_windblade(def: Dictionary, color: Color, accent: Color) -> void:
	using_glb = false

	# ---- 材质段（_build_fallback:336-354 同口径，烟熏/碳黑/刃青为风刃专属）----
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.metallic = 0.68
	paint.roughness = 0.32
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.047, 0.067, 0.086, 0.90)   # #0c1116 烟熏
	glass.metallic = 0.35
	glass.roughness = 0.08
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var carbon := StandardMaterial3D.new()
	carbon.albedo_color = Color("#16181c")
	carbon.metallic = 0.35
	carbon.roughness = 0.55
	_aero_mats.append(carbon)   # 登记保哑光：_apply_paint_gloss 跳过（:72-73 同口径）
	var blade_glow := StandardMaterial3D.new()
	blade_glow.albedo_color = Color("#39d7d0")
	blade_glow.emission_enabled = true
	blade_glow.emission = Color("#39d7d0")
	blade_glow.emission_energy_multiplier = 0.7
	var lamp_glow := StandardMaterial3D.new()
	lamp_glow.albedo_color = Color("#cfeef2")
	lamp_glow.emission_enabled = true
	lamp_glow.emission = Color("#cfeef2")
	lamp_glow.emission_energy_multiplier = 2.2
	tail_mat = StandardMaterial3D.new()
	tail_mat.albedo_color = Color("#300505")
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.1, 0.1)
	tail_mat.emission_energy_multiplier = 0.42
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("#d8dde4")
	rim_mat.metallic = 1.0
	rim_mat.roughness = 0.28
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color("#17181a")
	tire_mat.roughness = 0.96

	# 壳先建在游离节点（_tree_aabb 只遍历 transform 不依赖进主树），自检后再挂 BodyPivot
	var shell := Node3D.new()
	shell.name = "WBShell"   # test_aero 壳体几何红线的寻址名
	var cb := func(name: String, size: Vector3, pos: Vector3,
			mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
		var mi := _chamfer_box(shell, mat, size, pos, rot_deg)
		mi.name = name
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return mi
	var bx := func(name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = name
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = mat
		mi.mesh = mesh
		mi.position = pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		shell.add_child(mi)
		return mi

	# ---- 件表（地面绝对坐标）----
	# 龙骨船艏：PrismMesh 三角截面在 X-Y、棱线沿 Z 居中置顶（探针实证）→ V 形正投影
	var keel := MeshInstance3D.new()
	keel.name = "KeelNose"
	var keel_mesh := PrismMesh.new()
	keel_mesh.size = Vector3(1.30, 0.30, 1.10)
	keel_mesh.material = paint
	keel.mesh = keel_mesh
	keel.position = Vector3(0, 0.30, 1.75)
	keel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	shell.add_child(keel)
	# 楔形甲板前低后高（rotation.x=+4°：前缘 −0.038/后缘 +0.038，探针实证符号）
	cb.call("NoseDeck", Vector3(1.30, 0.10, 1.10), Vector3(0, 0.50, 1.75),
			paint, Vector3(4.0, 0, 0))
	cb.call("Tub", Vector3(2.02, 0.36, 2.30), Vector3(0, 0.44, 0.05), paint)
	cb.call("CanopyF", Vector3(1.30, 0.26, 0.85), Vector3(0, 0.75, 0.02), glass)
	cb.call("CanopyM", Vector3(1.12, 0.16, 0.85), Vector3(0, 0.90, -0.28), glass)
	cb.call("CanopyR", Vector3(0.92, 0.12, 0.65), Vector3(0, 0.97, -0.83), carbon)
	cb.call("Periscope", Vector3(0.42, 0.14, 0.55), Vector3(0, 1.01, -0.95), carbon)
	cb.call("BoatTail", Vector3(1.40, 0.26, 1.20), Vector3(0, 0.42, -1.70), paint)
	cb.call("TailDeck", Vector3(1.16, 0.18, 1.00), Vector3(0, 0.62, -1.60), paint)
	bx.call("Floorboard", Vector3(1.80, 0.05, 4.40), Vector3(0, 0.085, -0.05), carbon)
	for k4 in ["FL", "FR", "RL", "RR"]:
		var fx: float = 0.84 if k4.ends_with("L") else -0.84
		var fz: float = 1.52 if k4.begins_with("F") else -1.44
		cb.call("Fender" + k4, Vector3(0.34, 0.16, 0.78), Vector3(fx, 0.60, fz), paint)
	bx.call("BladeLineL", Vector3(0.03, 0.03, 3.20), Vector3(0.995, 0.52, -0.10), blade_glow)
	bx.call("BladeLineR", Vector3(0.03, 0.03, 3.20), Vector3(-0.995, 0.52, -0.10), blade_glow)
	bx.call("TailBand", Vector3(1.10, 0.05, 0.04), Vector3(0, 0.50, -2.28), tail_mat)
	bx.call("BladeLightL", Vector3(0.34, 0.045, 0.06), Vector3(0.50, 0.40, 2.27), lamp_glow)
	bx.call("BladeLightR", Vector3(0.34, 0.045, 0.06), Vector3(-0.50, 0.40, 2.27), lamp_glow)

	# ---- 壳体 AABB 自检（件表红线；不符即 push_error，探针口径见函数头注释）----
	var aabb := _tree_aabb(shell)
	if absf(aabb.size.x - 2.02) > 0.005 or absf(aabb.size.y - 1.02) > 0.01 \
			or absf(aabb.size.z - 4.60) > 0.01 or absf(aabb.position.y - 0.06) > 0.005 \
			or absf(aabb.position.z + 2.30) > 0.005:
		push_error("[风刃] 壳体 AABB 超出件表标定：position=%s size=%s"
				% [aabb.position, aabb.size])

	# 重组进 BodyPivot（:161 同口径：枢轴在车高中面偏上，姿态动画围绕它俯仰/侧倾）
	var body := Node3D.new()
	body.name = "BodyPivot"
	body.position = Vector3(0, aabb.size.y * 0.45, 0)
	add_child(body)
	shell.position.y -= body.position.y
	body.add_child(shell)
	body_pivot = body
	body_pivot_rest = body_pivot.rotation
	body_pivot_rest_pos = body_pivot.position
	_cache_rest(shell)

	# ---- 四轮（挂 CarVisual 根、不进壳树：aabb 传壳不含轮，套件贴身；滚动/转向动画走 Hub/Wheel 契约）----
	var tire := CylinderMesh.new()
	tire.top_radius = TIRE_R
	tire.bottom_radius = TIRE_R
	tire.height = 0.28
	tire.radial_segments = 20
	tire.material = tire_mat
	var rim := CylinderMesh.new()
	rim.top_radius = 0.21
	rim.bottom_radius = 0.21
	rim.height = 0.30
	rim.radial_segments = 14
	rim.material = rim_mat
	for key in ["FL", "FR", "RL", "RR"]:
		var front: bool = key.begins_with("F")
		var pivot := Node3D.new()
		pivot.name = "Hub" + key
		var spin := Node3D.new()
		spin.name = "Wheel" + key
		pivot.add_child(spin)
		var tire_mi := MeshInstance3D.new()
		tire_mi.mesh = tire
		tire_mi.rotation.z = PI / 2.0
		tire_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		spin.add_child(tire_mi)
		var rim_mi := MeshInstance3D.new()
		rim_mi.mesh = rim
		rim_mi.rotation.z = PI / 2.0
		rim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		spin.add_child(rim_mi)
		pivot.position = Vector3(0.84 if key.ends_with("L") else -0.84,
				TIRE_R, 1.52 if front else -1.44)
		add_child(pivot)
		wheels[key] = {"pivot": pivot, "spin": spin}
		_rest_euler[pivot] = Vector3.ZERO
		_rest_euler[spin] = Vector3.ZERO

	# 空力套件 + 主动尾翼按实测壳 AABB 落位（与 GLB 整块网格车同一调用；
	# def.aero 驱动 90/200/60 三阈值，系数零改动）
	_build_aero(def, aabb, body)


# ---------------- 程序化回退车型（简化版 GT 跑车） ----------------

func _build_fallback(color: Color, accent: Color) -> void:
	using_glb = false
	body_pivot_rest = Vector3.ZERO
	body_pivot_rest_pos = Vector3.ZERO
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.metallic = 0.68
	paint.roughness = 0.32
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#15171b")
	dark.roughness = 0.6
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.09, 0.92)
	glass.metallic = 0.35
	glass.roughness = 0.08
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("#d8dde4")
	rim_mat.metallic = 1.0
	rim_mat.roughness = 0.28
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color("#17181a")
	tire_mat.roughness = 0.96

	body_pivot = Node3D.new()
	add_child(body_pivot)

	var shell := MeshInstance3D.new()
	var shell_mesh := BoxMesh.new()
	shell_mesh.size = Vector3(1.72, 0.62, 4.5)
	shell_mesh.material = paint
	shell.mesh = shell_mesh
	shell.position = Vector3(0, 0.55, 0)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body_pivot.add_child(shell)

	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.5, 0.5, 1.9)
	cabin_mesh.material = glass
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, 1.05, -0.15)
	body_pivot.add_child(cabin)

	var splitter := MeshInstance3D.new()
	var sp_mesh := BoxMesh.new()
	sp_mesh.size = Vector3(1.68, 0.12, 0.55)
	sp_mesh.material = dark
	splitter.mesh = sp_mesh
	splitter.position = Vector3(0, 0.2, 2.08)
	body_pivot.add_child(splitter)

	var foil := MeshInstance3D.new()
	var foil_mesh := BoxMesh.new()
	foil_mesh.size = Vector3(1.58, 0.06, 0.44)
	foil_mesh.material = dark
	foil.mesh = foil_mesh
	foil.position = Vector3(0, 1.1, -2.1)
	body_pivot.add_child(foil)

	tail_mat = StandardMaterial3D.new()
	tail_mat.albedo_color = Color("#300505")
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.1, 0.1)
	tail_mat.emission_energy_multiplier = 0.42
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(1.28, 0.08, 0.06)
	tail_mesh.material = tail_mat
	tail.mesh = tail_mesh
	tail.position = Vector3(0, 0.72, -2.26)
	body_pivot.add_child(tail)

	var tire := CylinderMesh.new()
	tire.top_radius = TIRE_R
	tire.bottom_radius = TIRE_R
	tire.height = 0.27
	tire.radial_segments = 20
	tire.material = tire_mat
	var rim := CylinderMesh.new()
	rim.top_radius = 0.21
	rim.bottom_radius = 0.21
	rim.height = 0.29
	rim.radial_segments = 14
	rim.material = rim_mat

	const TW := 0.84
	const AF := 1.46
	const AR := -1.44
	for key in ["FL", "FR", "RL", "RR"]:
		var front: bool = key.begins_with("F")
		var pivot := Node3D.new()
		var spin := Node3D.new()
		pivot.add_child(spin)
		var tire_mi := MeshInstance3D.new()
		tire_mi.mesh = tire
		tire_mi.rotation.z = PI / 2.0
		tire_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		spin.add_child(tire_mi)
		var rim_mi := MeshInstance3D.new()
		rim_mi.mesh = rim
		rim_mi.rotation.z = PI / 2.0
		spin.add_child(rim_mi)
		pivot.position = Vector3(TW if key.ends_with("L") else -TW, TIRE_R, AF if front else AR)
		add_child(pivot)
		wheels[key] = {"pivot": pivot, "spin": spin}
		_rest_euler[pivot] = Vector3.ZERO
		_rest_euler[spin] = Vector3.ZERO


func _add_blob_shadow() -> void:
	var blob := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.75, 5.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = RRTextures.blob_shadow()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	quad.material = mat
	blob.mesh = quad
	blob.rotation.x = -PI / 2.0
	blob.position.y = 0.045
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)
