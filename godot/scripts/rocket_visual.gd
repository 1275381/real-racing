class_name RocketVisual
extends Node3D
## 「RR 快舟」火箭发射场 + 月球的全部程序化视觉（零 GLB）。
## 发射场：混凝土坪 / 钢板发射台（南侧导流槽）/ 62m 桁架勤务塔（双回转脐带臂 +
## 塔顶红色障碍灯）/ 四角泛光灯塔 / 停车广场与入场龙门。
## 火箭：总高 58m 直径 4m——一级白圆柱 32m（深灰裙 + 9 喷管环）+ 级间银灰环带 2m
## + 二级白 16m + 整流罩白锥 8m + 舷窗 pod；一级可分离（detach_stage 淡出删除）。
## 月球：月心 (5200,5000,2600) 半径 600 灰壤球 + 14 个撞击坑 + 静海基地着陆坪 +
## 月岩；全部 mesh 用专属 ALPHA 材质走 set_moon_fade 淡入协议（评审⑨：far 切 9000
## 的瞬间月球不能整球蹦进画面），fade 归 1 后切回不透明（防近距透明排序穿插）。
## 尾焰/烟尘/月尘照 plane_visual 的 scale 抖动 + emission_energy 模式。

const SEG_CHAMFER := 6

## 六面基架：n=外法线 / t1·t2=面内两轴（t1×t2=n）。Godot 正面=顺时针环绕
const _FACE_AXES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]

## 倒角方块闭包（自 car_visual.gd:342-428 原样复制——跨文件不可 preload 是既有
## 先例）。与车级版唯一差异：chamfer<0 的自动值按火箭/月岩的米级件放宽钳位。
static func _chamfer_box(parent: Node3D, mat: Material, size: Vector3,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO,
		chamfer: float = -1.0, seg: int = SEG_CHAMFER) -> MeshInstance3D:
	var half := size * 0.5
	var c := chamfer
	if c < 0.0:
		c = clampf(minf(size.x, minf(size.y, size.z)) * 0.18, 0.04, 0.5)
	var hi := Vector3(maxf(half.x - c, 0.0004), maxf(half.y - c, 0.0004),
			maxf(half.z - c, 0.0004))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axes in _FACE_AXES:
		var n: Vector3 = axes[0]
		var t1: Vector3 = axes[1]
		var t2: Vector3 = axes[2]
		var hn := _axis_half(n, half)
		var h1 := _axis_half(t1, half)
		var h2 := _axis_half(t2, half)
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


static func _axis_half(axis: Vector3, half: Vector3) -> float:
	return absf(axis.x) * half.x + absf(axis.y) * half.y + absf(axis.z) * half.z


static func _push_tri(st: SurfaceTool, a: Array, b: Array, c2: Array) -> void:
	for p in [a, b, c2]:
		st.set_normal(p[1])
		st.add_vertex(p[0])


# ===================== 运行时引用（状态机驱动） =====================

var rocket: Node3D            # 火箭根（基座在本地 y=0，轴线 +Y）
var stage1: Node3D            # 一级（0..32m，可分离）
var flame: Node3D             # 尾焰组
var arms: Array[Node3D] = []  # 两根回转脐带臂（T-10 摆开）
var pad_lamp_mats: Array[StandardMaterial3D] = []   # 坪周地灯（倒计时逐盏点亮）
var beacon_mat: StandardMaterial3D                  # 塔顶红色障碍灯
var floodlights: Array[SpotLight3D] = []            # 四角泛光灯塔（夜间开）
var moon: Node3D               # 月球根
var moon_mats: Array[StandardMaterial3D] = []       # 月球专属 ALPHA 材质
var _moon_fade := 0.0
var _moon_opaque := false      # fade 归 1 后切回不透明（评审遗留：防透明排序穿插）
var _smoke: GPUParticles3D     # 点火导流槽烟尘
var _moon_dust: GPUParticles3D # 月面触地月尘（低重力）
var _throttle := 0.0
var _flame_t := 0.0
var _beacon_t := 0.0
var _stage_debris: Node3D = null
var _debris_t := 0.0
var _debris_vel := Vector3.ZERO


## 建 rocket_visual 时同时建发射场静态件与火箭本体；月球由 build_moon 单独建
## （量大战表，只在漫游地图构建线程里跑一次）。
func build_site(pad_center: Vector3, door_pos: Vector3) -> void:
	var white := _mat(Color(0.92, 0.93, 0.95), 0.35)
	var steel := _mat(Color(0.52, 0.55, 0.6))
	var dark := _mat(Color(0.16, 0.17, 0.2))
	var concrete := _mat(Color(0.55, 0.56, 0.58), 0.95)
	var hot := Color(1.0, 0.55, 0.15)

	# ---- 发射坪：90×90 混凝土（标高 0.5，垫高防积沙）----
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(90, 1.0, 90)
	pm.material = concrete
	pad.mesh = pm
	pad.position = pad_center + Vector3(0, 0.0, 0)
	pad.position.y = 0.5
	add_child(pad)
	# 停车广场垫层
	var plaza := MeshInstance3D.new()
	var plm := BoxMesh.new()
	plm.size = Vector3(60, 0.9, 40)
	plm.material = concrete
	plaza.mesh = plm
	plaza.position = Vector3(pad_center.x, 0.45, pad_center.z + 142.0)
	add_child(plaza)

	# ---- 坪周两圈地灯（倒计时逐盏点亮）：外圈 12 + 内圈 8 ----
	var lamp_off := _mat(Color(0.18, 0.19, 0.2))
	for ring_i in 2:
		var rc := 36.0 if ring_i == 0 else 22.0
		var cnt := 12 if ring_i == 0 else 8
		for k in cnt:
			var ang := TAU * float(k) / float(cnt) + ring_i * 0.26
			var m := lamp_off.duplicate()
			m.emission_enabled = true
			m.emission = Color(1.0, 0.72, 0.25)
			m.emission_energy_multiplier = 0.0
			pad_lamp_mats.append(m)
			var lm := CylinderMesh.new()
			lm.top_radius = 0.28
			lm.bottom_radius = 0.34
			lm.height = 0.7
			lm.material = m
			var lmi := MeshInstance3D.new()
			lmi.mesh = lm
			lmi.position = Vector3(pad_center.x + cos(ang) * rc, 1.05,
					pad_center.z + sin(ang) * rc)
			add_child(lmi)

	# ---- 发射台：钢板基座 16×16×2，中心导流槽开口朝南（朝停车广场）----
	var mount := Node3D.new()
	add_child(mount)
	_chamfer_box(mount, steel, Vector3(16, 2.0, 16),
			pad_center + Vector3(0, 1.5, 0), Vector3.ZERO, 0.18)
	# 导流槽：台面中央开槽 + 两侧斜板把焰流导向南口
	_chamfer_box(mount, dark, Vector3(6.5, 2.6, 2.4),
			pad_center + Vector3(0, 1.4, 8.6), Vector3(18, 0, 0), 0.1)
	# 四个夹持臂（ignition 攒势 1.2s 后 release——视觉件，不复位也能看）
	for k in 4:
		var ang := TAU * float(k) / 4.0 + PI * 0.25
		_chamfer_box(mount, steel, Vector3(1.0, 5.0, 1.0),
				pad_center + Vector3(cos(ang) * 3.4, 4.2, sin(ang) * 3.4),
				Vector3(0, -rad_to_deg(ang), 24.0), 0.1)

	# ---- 勤务塔：62m 桁架钢塔（略高于火箭），立发射台西侧 ----
	var tower := Node3D.new()
	add_child(tower)
	var tw := pad_center + Vector3(-13.0, 0.0, 0.0)
	for sx in [-2.2, 2.2]:
		for sz in [-2.2, 2.2]:
			_chamfer_box(tower, steel, Vector3(0.9, 62.0, 0.9),
					tw + Vector3(sx, 31.0 + 1.0, sz), Vector3.ZERO, 0.12)
	for lv in 7:   # 水平横撑圈（桁架感）
		_chamfer_box(tower, steel, Vector3(5.4, 0.5, 5.4),
				tw + Vector3(0, 4.0 + lv * 8.6, 0), Vector3.ZERO, 0.1)
	# 电梯井外壳（贴塔北面）
	_chamfer_box(tower, _mat(Color(0.3, 0.32, 0.36)), Vector3(1.6, 58.0, 1.6),
			tw + Vector3(0, 30.0, -3.0), Vector3.ZERO, 0.12)
	# 塔顶红色航空障碍灯（emission + OmniLight 闪烁，不投影——7401889 阴影收敛基调）
	beacon_mat = StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(1.0, 0.2, 0.15)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.15, 0.1)
	beacon_mat.emission_energy_multiplier = 2.0
	var bc := MeshInstance3D.new()
	var bcm := BoxMesh.new()
	bcm.size = Vector3(1.2, 1.2, 1.2)
	bcm.material = beacon_mat
	bc.mesh = bcm
	bc.position = tw + Vector3(0, 63.4, 0)
	tower.add_child(bc)
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.2, 0.12)
	bl.light_energy = 0.0
	bl.omni_range = 60.0
	bl.shadow_enabled = false
	bl.position = tw + Vector3(0, 63.4, 0)
	tower.add_child(bl)
	set_meta("beacon_light", bl)
	# 两根回转脐带臂（高位 46m 主臂 + 低位 28m 液氧加注臂）：合拢抱箭体，
	# T-10~T-6 各自绕塔身回转摆开
	for arm_def in [[46.0, 9.0], [28.0, 7.0]]:
		var pivot := Node3D.new()
		pivot.position = tw + Vector3(2.6, arm_def[0], 0.0)
		tower.add_child(pivot)
		_chamfer_box(pivot, steel, Vector3(arm_def[1], 1.1, 1.6),
				Vector3(arm_def[1] * 0.5, 0, 0), Vector3.ZERO, 0.1)
		_chamfer_box(pivot, dark, Vector3(1.2, 1.2, 1.2),
				Vector3(arm_def[1] - 0.4, 0, 0), Vector3.ZERO, 0.08)
		arms.append(pivot)
	set_arms_open(0.0)

	# ---- 登船口：发射台南侧楼梯 + 平台（判定半径 10m 由状态机量）----
	var stair := Node3D.new()
	add_child(stair)
	for s in 7:
		_chamfer_box(stair, steel, Vector3(3.2, 0.5, 1.1),
				door_pos + Vector3(0, 0.25 + s * 0.34, 3.4 - s * 1.05),
				Vector3(17.0, 0, 0), 0.06)
	_chamfer_box(stair, steel, Vector3(5.0, 0.4, 4.0),
			door_pos + Vector3(0, 2.35, 0), Vector3.ZERO, 0.08)
	_chamfer_box(stair, dark, Vector3(1.6, 2.4, 0.35),
			door_pos + Vector3(0, 1.4, 1.9), Vector3.ZERO, 0.06)

	# ---- 四角泛光灯塔（12m 杆 + SpotLight 夜间开、不投影）----
	for k in 4:
		var ang := TAU * float(k) / 4.0 + PI * 0.25
		var c3 := pad_center + Vector3(cos(ang) * 40.0, 0, sin(ang) * 40.0)
		_chamfer_box(self, steel, Vector3(0.8, 12.0, 0.8),
				c3 + Vector3(0, 6.0, 0), Vector3.ZERO, 0.1)
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(2.4, 0.7, 1.0)
		var hmat := _mat(Color(1.0, 0.95, 0.82), 0.4, Color(1.0, 0.92, 0.7), 1.4)
		hm.material = hmat
		head.mesh = hm
		head.position = c3 + Vector3(0, 12.4, 0)
		add_child(head)
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.94, 0.8)
		sp.light_energy = 0.0
		sp.spot_range = 90.0
		sp.spot_angle = 42.0
		sp.shadow_enabled = false
		sp.position = c3 + Vector3(0, 12.2, 0)
		add_child(sp)
		floodlights.append(sp)
		# 建城线程里节点不在树内，look_at 会报错——用 Basis.looking_at 直接定向
		# （-Z 朝坪心，SpotLight 沿 -Z 投射）
		var aim: Vector3 = (pad_center + Vector3(0, 1.0, 0) - sp.position).normalized()
		var basis := Basis.looking_at(aim, Vector3.UP)
		sp.basis = basis
		head.basis = basis

	# ---- 入场龙门 + 大字（停车广场北侧）----
	var gate := Vector3(pad_center.x, 0.45, pad_center.z + 122.0)
	for sx in [-9.0, 9.0]:
		_chamfer_box(self, dark, Vector3(1.0, 8.0, 1.0),
				gate + Vector3(sx, 4.0, 0), Vector3.ZERO, 0.1)
	_chamfer_box(self, dark, Vector3(19.0, 1.4, 1.0),
			gate + Vector3(0, 8.2, 0), Vector3.ZERO, 0.1)
	for side in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = "RR 航天发射场"
		lb.font_size = 190
		lb.modulate = Color(1.0, 0.85, 0.3)
		lb.outline_size = 34
		lb.double_sided = false
		lb.position = gate + Vector3(0, 8.2, side * 0.6)
		lb.rotation.y = PI if side > 0.0 else 0.0
		add_child(lb)

	# ---- 火箭本体「RR 快舟」：总高 58m、直径 4m ----
	rocket = Node3D.new()
	rocket.name = "RRKuaizhou"
	add_child(rocket)
	var base := pad_center + Vector3(0, 2.55, 0)
	rocket.position = base
	# 一级（0..32m，可分离）：深灰裙 4m + 白圆柱 28m + 蓝条带
	stage1 = Node3D.new()
	stage1.name = "stage1"
	rocket.add_child(stage1)
	_cyl(stage1, Vector3(0, 2, 0), 2.0, 2.0, 4.0, _mat(Color(0.3, 0.31, 0.34), 0.5))
	_cyl(stage1, Vector3(0, 18, 0), 2.0, 2.0, 28.0, white)
	_cyl(stage1, Vector3(0, 16.5, 0), 2.03, 2.03, 6.0,
			_mat(Color(0.1, 0.16, 0.34), 0.4))
	# 9 喷管环（底部）
	for k in 9:
		var ang := TAU * float(k) / 9.0
		var noz := CylinderMesh.new()
		noz.top_radius = 0.32
		noz.bottom_radius = 0.52
		noz.height = 1.6
		noz.material = _mat(Color(0.2, 0.19, 0.18), 0.35, Color(0.35, 0.12, 0.05), 0.0)
		var nmi := MeshInstance3D.new()
		nmi.mesh = noz
		nmi.position = Vector3(cos(ang) * 1.25, -0.7, sin(ang) * 1.25)
		stage1.add_child(nmi)
	# 竖排大字（贴一级上部，两面）
	for side in [1.0, -1.0]:
		var rl := Label3D.new()
		rl.text = "RR 快舟"
		rl.font_size = 150
		rl.modulate = Color(0.95, 0.96, 1.0)
		rl.outline_size = 26
		rl.outline_modulate = Color(0.1, 0.12, 0.3, 0.9)
		rl.double_sided = false
		rl.pixel_size = 0.02
		rl.position = Vector3(side * 2.05, 26.0, 0)
		rl.rotation.y = PI * 0.5 * side
		stage1.add_child(rl)
	# 二级组（32..58m）：级间银灰环带 2m + 二级白 16m + 整流罩白锥 8m
	var stage2 := Node3D.new()
	stage2.name = "stage2"
	rocket.add_child(stage2)
	_cyl(stage2, Vector3(0, 33, 0), 2.05, 2.05, 2.0,
			_mat(Color(0.72, 0.74, 0.78), 0.3))
	_cyl(stage2, Vector3(0, 42, 0), 2.0, 2.0, 16.0, white)
	var fair := CylinderMesh.new()
	fair.top_radius = 0.55
	fair.bottom_radius = 2.0
	fair.height = 8.0
	fair.radial_segments = 24
	fair.material = white
	var fmi := MeshInstance3D.new()
	fmi.mesh = fair
	fmi.position = Vector3(0, 54, 0)
	stage2.add_child(fmi)
	_cyl(stage2, Vector3(0, 49.6, 0), 2.04, 2.04, 1.2,
			_mat(Color(0.1, 0.16, 0.34), 0.4))
	# 舷窗 pod（船内固定机位在 (0,44,2) 一带朝外看）
	var pod := MeshInstance3D.new()
	var podm := BoxMesh.new()
	podm.size = Vector3(1.9, 2.4, 1.9)
	podm.material = _mat(Color(0.12, 0.13, 0.16), 0.25)
	pod.mesh = podm
	pod.position = Vector3(0, 44, 2.0)
	stage2.add_child(pod)
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.3, 1.1, 0.25)
	var wmat := _mat(Color(0.35, 0.6, 0.75), 0.15, Color(0.3, 0.5, 0.8), 0.5)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color.a = 0.85
	wm.material = wmat
	win.mesh = wm
	win.position = Vector3(0, 44, 3.0)
	stage2.add_child(win)
	# 尾焰（照 plane_visual：emission 锥 + set_throttle 抖动；再入等离子复用）
	flame = Node3D.new()
	flame.name = "flame"
	stage1.add_child(flame)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = hot
	fmat.emission_enabled = true
	fmat.emission = hot
	fmat.emission_energy_multiplier = 3.0
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color.a = 0.85
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.no_depth_test = true
	var fo := CylinderMesh.new()
	fo.top_radius = 0.5
	fo.bottom_radius = 2.6
	fo.height = 26.0
	fo.material = fmat
	var foi := MeshInstance3D.new()
	foi.mesh = fo
	foi.position = Vector3(0, -13.6, 0)
	flame.add_child(foi)
	var fmat2 := fmat.duplicate() as StandardMaterial3D
	fmat2.albedo_color = Color(1.0, 0.9, 0.6)
	fmat2.emission = Color(1.0, 0.92, 0.55)
	var fi := CylinderMesh.new()
	fi.top_radius = 0.3
	fi.bottom_radius = 1.3
	fi.height = 13.0
	fi.material = fmat2
	var fii := MeshInstance3D.new()
	fii.mesh = fi
	fii.position = Vector3(0, -7.3, 0)
	flame.add_child(fii)
	flame.visible = false

	# ---- 点火烟尘：导流槽两侧（南口外，横向铺开）----
	_smoke = GPUParticles3D.new()
	_smoke.amount = 170
	_smoke.lifetime = 3.6
	_smoke.visibility_aabb = AABB(Vector3(-70, -4, -30), Vector3(140, 46, 70))
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(6, 1.2, 3)
	spm.direction = Vector3(0, 0.25, 1)
	spm.spread = 38.0
	spm.initial_velocity_min = 9.0
	spm.initial_velocity_max = 22.0
	spm.gravity = Vector3(0, 1.6, 0)
	spm.scale_min = 2.2
	spm.scale_max = 5.5
	_smoke.process_material = spm
	var sq := QuadMesh.new()
	sq.size = Vector2(3.2, 3.2)
	var sqm := StandardMaterial3D.new()
	sqm.albedo_color = Color(0.82, 0.8, 0.78, 0.4)
	sqm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sqm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sqm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sq.material = sqm
	_smoke.draw_pass_1 = sq
	_smoke.position = pad_center + Vector3(0, 1.2, 10.5)
	_smoke.emitting = false
	add_child(_smoke)

	# ---- 月面月尘（触地一次性扬起：重力 1.62，低重力下尘也飘）----
	_moon_dust = GPUParticles3D.new()
	_moon_dust.amount = 120
	_moon_dust.lifetime = 5.5
	_moon_dust.one_shot = true
	_moon_dust.visibility_aabb = AABB(Vector3(-26, -4, -26), Vector3(52, 22, 52))
	var dpm := ParticleProcessMaterial.new()
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	dpm.emission_ring_axis = Vector3(0, 1, 0)
	dpm.emission_ring_radius = 3.2
	dpm.emission_ring_inner_radius = 1.2
	dpm.emission_ring_height = 0.6
	dpm.direction = Vector3(0, 1, 0)
	dpm.spread = 80.0
	dpm.initial_velocity_min = 6.0
	dpm.initial_velocity_max = 14.0
	dpm.gravity = Vector3(0, -1.62, 0)   # 月面低重力：尘也飘
	dpm.scale_min = 1.4
	dpm.scale_max = 3.2
	_moon_dust.process_material = dpm
	var dq := QuadMesh.new()
	dq.size = Vector2(1.1, 1.1)
	var dqm := StandardMaterial3D.new()
	dqm.albedo_color = Color(0.66, 0.66, 0.64, 0.55)
	dqm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dqm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dqm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dq.material = dqm
	_moon_dust.draw_pass_1 = dq
	_moon_dust.emitting = false
	rocket.add_child(_moon_dust)


## 月球：灰壤球 + 撞击坑 + 静海基地着陆坪 + 月岩（全部 ALPHA 专属材质走淡入协议）
func build_moon(moon_c: Vector3, moon_r: float) -> void:
	moon = Node3D.new()
	moon.name = "Moon"
	moon.position = moon_c
	add_child(moon)
	# 基底球面（顶半球与 query 覆写严格同式：y = 月心 + sqrt(r²-d²)）
	var soil := _moon_mat(Color(0.54, 0.54, 0.53), 0.95)
	var sm := SphereMesh.new()
	sm.radius = moon_r
	sm.height = moon_r * 2.0
	sm.radial_segments = 48
	sm.rings = 26
	sm.material = soil
	var smi := MeshInstance3D.new()
	smi.mesh = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.add_child(smi)
	# 撞击坑 14 个：坑半径 30~120、极角 0.18~1.25（避开顶部着陆坪）、间距 > 1.5 坑半径
	var rng := RRUtil.Mulberry.new(20260930)
	var placed: Array[Vector3] = []
	var tried := 0
	while placed.size() < 14 and tried < 220:
		tried += 1
		var polar := rng.range(0.18, 1.25)
		var az := rng.range(0.0, TAU)
		var dir := Vector3(sin(polar) * cos(az), cos(polar),
				sin(polar) * sin(az))
		var cr := rng.range(30.0, 120.0)
		var ok := true
		for pdir in placed:
			# 弦长近似角距 × 月面半径；新增坑也离着陆坪（顶点）> 1.5 坑半径
			if dir.angle_to(pdir) * moon_r < cr * 1.5 \
					or dir.angle_to(Vector3.UP) * moon_r < cr + 120.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(dir)
		var grp := Node3D.new()
		grp.position = dir * moon_r
		grp.quaternion = Quaternion(Vector3.UP, dir)
		moon.add_child(grp)
		var rim := _moon_mat(Color(0.6, 0.6, 0.58), 0.9)
		var flo := _moon_mat(Color(0.44, 0.44, 0.43), 0.98)
		var splat := _moon_mat(Color(0.38, 0.38, 0.37), 1.0)
		# 浅凹坑盘（下沉）+ 周缘隆起环 + 暗色溅射纹
		_moon_cyl(grp, Vector3(0, -3.5, 0), cr * 0.72, cr, 9.0, flo)
		_moon_cyl(grp, Vector3(0, 0.9, 0), cr * 1.02, cr * 1.1, 2.6, rim)
		_moon_cyl(grp, Vector3(0, 0.35, 0), cr * 1.32, cr * 1.45, 0.7, splat)
	# 静海基地着陆坪：顶部平底（与 query 的 d<80 平底同口径）
	var padtop := Vector3(0, moon_r + 0.25, 0)
	var deck := _moon_mat(Color(0.48, 0.49, 0.5), 0.85)
	_moon_cyl(moon, padtop, 80.0, 80.0, 1.2, deck)
	var mark := _moon_mat(Color(0.9, 0.55, 0.15), 0.7)
	_moon_cyl(moon, Vector3(0, moon_r + 0.95, 0), 9.0, 12.0, 0.6, mark)
	for k in 4:   # 坪角信标
		var ang := TAU * float(k) / 4.0 + PI * 0.25
		var bm := _moon_mat(Color(1.0, 0.3, 0.2), 0.5, Color(1.0, 0.2, 0.15), 1.6)
		_moon_cyl(moon, Vector3(cos(ang) * 70.0, moon_r + 1.6, sin(ang) * 70.0),
				0.4, 0.55, 2.4, bm)
	var mlabel := Label3D.new()
	mlabel.text = "静海基地"
	mlabel.font_size = 220
	mlabel.modulate = Color(0.95, 0.85, 0.6)
	mlabel.outline_size = 36
	mlabel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mlabel.no_depth_test = true
	mlabel.position = Vector3(0, moon_r + 14.0, 34.0)
	moon.add_child(mlabel)
	# 月岩（倒角件表，静海基地周边 250m 内 14 块——follow_shadow 1200m 罩得住）
	var rock := _moon_mat(Color(0.42, 0.42, 0.41), 0.95)
	for k in 14:
		var ang := rng.range(0.0, TAU)
		var rr := rng.range(92.0, 250.0)
		var dx := cos(ang) * rr
		var dz := sin(ang) * rr
		var dy := sqrt(maxf(moon_r * moon_r - rr * rr, 0.0))
		var s := rng.range(1.2, 3.4)
		var mi := _chamfer_box(moon, rock, Vector3(s, s * 0.7, s * 1.2),
				Vector3(dx, dy + s * 0.2, dz), Vector3(0, rng.range(0.0, 90.0),
				rng.range(-8.0, 8.0)), -1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	moon.visible = false


# ===================== 驱动接口（rocket_site 调） =====================

func set_throttle(t: float) -> void:
	_throttle = clampf(t, 0.0, 1.0)


## 脐带臂回转摆开（0=合拢抱箭 1=完全摆开）
func set_arms_open(f: float) -> void:
	for i in arms.size():
		var pivot := arms[i]
		# 高位主臂先摆（T-10 起），低位臂稍迟半拍——摆开方向朝西（背离箭体）
		var ph := clampf(f * 1.25 - i * 0.18, 0.0, 1.0)
		pivot.rotation.y = lerpf(0.0, -1.35, ph)


## 倒计时地灯逐盏点亮（0..1）
func set_pad_lights(k: float) -> void:
	var n := pad_lamp_mats.size()
	for i in n:
		var on := 1.0 if float(i) / float(n) < k else 0.0
		pad_lamp_mats[i].emission_energy_multiplier = on * 2.4


func set_smoke(on: bool) -> void:
	if _smoke != null:
		_smoke.emitting = on


## 月面触地扬尘（一次性爆发）
func moon_dust_burst() -> void:
	if _moon_dust != null:
		_moon_dust.restart()
		_moon_dust.emitting = true


## 一级分离：原级隐藏，碎片体按离轨速度漂离 + 3s 淡出删除
func detach_stage(sep_vel: Vector3) -> void:
	if _stage_debris != null:
		_stage_debris.queue_free()
		_stage_debris = null
	stage1.visible = false
	_stage_debris = Node3D.new()
	add_child(_stage_debris)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.9, 0.91, 0.93)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dm := CylinderMesh.new()
	dm.top_radius = 2.0
	dm.bottom_radius = 2.0
	dm.height = 32.0
	dm.material = dmat
	var dmi := MeshInstance3D.new()
	dmi.mesh = dm
	dmi.position = rocket.position + Vector3(0, 16.0, 0)
	_stage_debris.add_child(dmi)
	_stage_debris.set_meta("mat", dmat)
	_debris_t = 0.0
	_debris_vel = sep_vel


## reset_launch 复位一级
func restore_stage1() -> void:
	stage1.visible = true
	if _stage_debris != null:
		_stage_debris.queue_free()
		_stage_debris = null


## 月球淡入淡出协议（评审⑨）：alpha 0→1 缓入 2s；归 1 切回不透明
func set_moon_fade(f: float) -> void:
	_moon_fade = clampf(f, 0.0, 1.0)
	if moon == null:
		return
	moon.visible = _moon_fade > 0.004
	var opaque := _moon_fade >= 0.999
	if opaque != _moon_opaque:
		_moon_opaque = opaque
		for m in moon_mats:
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if opaque \
					else BaseMaterial3D.TRANSPARENCY_ALPHA
	for m in moon_mats:
		m.albedo_color.a = _moon_fade


func _process(dt: float) -> void:
	_flame_t += dt
	_beacon_t += dt
	# 尾焰抖动（照 plane_visual._process）
	if flame != null:
		var on := _throttle > 0.04
		flame.visible = on
		if on:
			var flick := 1.0 + 0.18 * sin(_flame_t * 47.0) + 0.1 * sin(_flame_t * 89.0)
			var s := (0.22 + 1.05 * _throttle) * flick
			flame.scale = Vector3(0.6 + 0.5 * _throttle, s, 0.6 + 0.5 * _throttle)
			for fmi in flame.get_children():
				var mat := (fmi as MeshInstance3D).mesh.surface_get_material(0) \
						as StandardMaterial3D
				if mat != null:
					mat.emission_energy_multiplier = 1.5 + 5.0 * _throttle
	# 塔顶障碍灯闪烁（OmniLight 与 emission 同步呼吸）
	var bl: OmniLight3D = get_meta("beacon_light", null)
	var flash := 1.2 + 1.1 * maxf(sin(_beacon_t * 2.6), 0.0)
	if beacon_mat != null:
		beacon_mat.emission_energy_multiplier = flash
	if bl != null:
		bl.light_energy = maxf(sin(_beacon_t * 2.6), 0.0) * 2.2
	# 一级分离碎片：漂离 + 淡出
	if _stage_debris != null:
		_debris_t += dt
		_stage_debris.position += _debris_vel * dt
		var m2: StandardMaterial3D = _stage_debris.get_meta("mat")
		m2.albedo_color.a = clampf(1.0 - _debris_t / 3.0, 0.0, 1.0)
		if _debris_t > 3.0:
			_stage_debris.queue_free()
			_stage_debris = null


# ===================== 私有件表 =====================

func _mat(col: Color, rough := 0.82, emis := Color.BLACK,
		e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = e
	return m


func _cyl(parent: Node3D, at: Vector3, r_top: float, r_bot: float, h: float,
		m: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 24
	cm.material = m
	mi.mesh = cm
	mi.position = at
	parent.add_child(mi)
	return mi


func _moon_cyl(parent: Node3D, at: Vector3, r_top: float, r_bot: float, h: float,
		m: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 26
	cm.material = m
	mi.mesh = cm
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 月球专属材质：登记进 moon_mats 走 set_moon_fade 淡入协议
func _moon_mat(col: Color, rough := 0.95, emis := Color.BLACK,
		e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.0
	if e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = e
	moon_mats.append(m)
	return m
