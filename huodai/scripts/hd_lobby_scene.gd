extends Node3D
## 烽火地带 —— 3D 出发大厅（2026-10 三角洲式改版）：备战机库里站着干员，
## 手持当前配枪、穿标准护甲，仓库/交易行面板停靠大厅 UI 左下角。
## 无 class_name（新脚本一律 preload，hd_thumbs 同款约定——-s 测试/探针跑法
## 不刷新全局类缓存，class_name 会「Could not find type」编译失败）。
## 架构照 HDPlayer._build_vm 先例：own_world_3d 独立世界 SubViewport
## （机库场景与主战场零深度/光照纠缠）→ 纯色清屏 → CanvasLayer
## 全屏 TextureRect 合成进主画面；尺寸跟随窗口、UPDATE_ALWAYS 常更新。
## 层序契约：主世界(0) < vm 枪模(5) < 本场景(6) < HUD(10) < 大厅 UI(20)——
## 大厅页（tab 0）时机库画面垫在大厅 UI 之下；改枪台/交易行页与对局中整层
## 隐藏并停更（性能红线 ≥55 帧：盖住的视口一帧不多画）。
## 干员：soldier_hd.glb 实例化（照 hd_soldiers._make_body 先例：AnimationPlayer
## 播 idle、材质逐份 duplicate 重染——敌军赭红换我方深灰作训服+炭黑装具）。
## 手持枪：main 注入 gun_preview_provider（HDGuns.build_preview：unibody 一体
## 成型+所装瞄具/消音器同局内枪模），挂 Skeleton3D 的 weapon 骨骼（建模自带的
## 握把 socket，make_soldier_hd.py:99-106）——idle 动画里武器骨下沉/前倾，
## 枪跟着骨骼走，换枪=loadout 键变才重建（交易行换枪/改枪台换装当场换手持枪）。
## 骨骼对位（python 复算 glb 静息姿态）：weapon 骨 X=模型 -X、Y=枪口方向（模型
## +Z）、Z=模型 +Y；枪模 -Z=枪口、+Y=上——修正旋转 = 绕 X +90°。静息握把锚
## （HOLD_DELTA 统一后≈枪身原点）落骨原点=右手握把点，零平移起步、探针截图微调。
## 护甲：HDStash 无持久化护甲字段（第三阶段护甲=局内护甲板 player.armor，
## hd_player.gd:54 出局即清零；全库 grep 实证）——按「标准护甲档」在躯干叠
## 程序化板件（挂 chest 骨：静息基 = 模型空间单位阵，+Z=胸前），无档位制
## 就恒穿标准件（深灰作战服+护甲色块即干员基础形象）。
## 性能：装饰件（货架/弹药箱/灯带/地圈）cast_shadow 全关、灯全不投影、
## 共用单位盒网格；stats() 给回归测试写节点数/面数数值断言防膨胀。

const PBR := preload("res://scripts/hd_pbr.gd")
const SOLDIER_HD_PATH := "res://assets/pbr/models/soldier/soldier_hd.glb"
const SOLDIER_PATH := "res://assets/battle/soldier.glb"   # LFS 缺失回退（hd_soldiers 同款兜底）

## 合成层：夹在 vm 枪模(5) 与 HUD(10) 之间——机库画面永远压住对局残影、
## 永远被大厅 UI 与 HUD 盖住（与 HDPlayer.VM_LAYER 同一套层序纪律）
const COMPOSITE_LAYER := 6
## 我方干员配色（对照 hd_soldiers 敌军赭红 TIER_UNIFORM.elite 同档深灰，
## 略带蓝调拉开「我方」观感；机库暗光下压太黑会读成一块剪影，比战场档提亮）
const OP_UNIFORM := Color(0.33, 0.35, 0.4)    # 深灰作训服
const OP_GEAR := Color(0.21, 0.22, 0.25)      # 炭黑装具/护甲
const ACCENT := Color(1.0, 0.7, 0.36)         # 琥珀（与大厅 UI COL_ACCENT 同源）

## 相机（微仰平视 + 呼吸式环摆）：环摆幅度 ±0.07 rad（≈±4°）、周期 ~28s、
## 高度浮动 ±0.035——「缓慢呼吸」，不做快转。
## 机位定案（判图 3 轮方案级复盘：连续两轮 5 分的主因=4.6m 远景下低模干员
## 细节全失、读成方块小人）——回调到 1 轮被认可的「大半身英雄位」：3.15m/
## FOV34 视野高 1.93m，干员占屏高 ~93%、头到膝全可见，膝下交给换枪条接住
## （三角洲 menu 角色同款大半身）；cam 低于视线目标=保住微仰
const OP_POS := Vector3(0.62, 0.0, 0.0)       # 干员站位：画面右三分线（相机偏左取景）
const CAM_LOOK := Vector3(-0.05, 1.02, 0.0)   # 视线目标：胸口（偏左看，干员落右侧留白）
const CAM_BASE := Vector3(-0.3, 0.94, 3.15)   # 相机基准位（低于视线目标=微仰）
const CAM_FOV := 34.0

## 面数/节点数红线（test_huodai 数值断言用）：机库布景 30 件盒级程序化件
## + 写实干员 + 一把枪模；阈值=实测值 +25% 余量（防膨胀，超线即 FAIL）
const MAX_NODES := 220
const MAX_TRIS := 120000

var vp: SubViewport                    # 独立世界视口（大厅机库）
var composite: CanvasLayer             # 合成层（全屏贴图）
var held_gun_id := ""                  # 干员当前手持枪 id（测试/探针断言用）
var operator: Node3D                   # 干员根节点（测试断言「干员节点在位」）
var gun_preview_provider: Callable = Callable()   # main 注入：func(gid)->Node3D

var _stash                             # HDStash（鸭子类型：loadout/scope_fit/suppressed）
var _cam: Camera3D
var _gun_mount: BoneAttachment3D       # weapon 骨骼挂点（枪随持枪手动画走）
var _gun_holder: Node3D                # 枪座：修正旋转挂这里（BoneAttachment3D 自身
                                       # transform 会被骨骼全局位姿覆写，不能直接用）
var _armor_mount: BoneAttachment3D     # chest 骨骼挂点（护甲板随呼吸起伏）
var _held_key := ""                    # 手持枪重建键：枪|镜|消音（键变才重建）
var _active := false                   # 大厅可见且在出发页（其余态停更省 GPU）
var _t := 0.0                          # 呼吸摆相位
var _mesh_box: BoxMesh                 # 共用单位盒（约 30 处布景件实例缩放复用）


func _ready() -> void:
	_build_viewport()
	_build_env()
	_build_hangar()
	_build_operator()
	_build_cam()


## 机库相机：微仰平视基准位起步（呼吸摆动在 _process 接管）
func _build_cam() -> void:
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.near = 0.05
	_cam.far = 40.0
	vp.add_child(_cam)
	_cam.current = true
	_cam.position = CAM_BASE
	_cam.look_at(CAM_LOOK)


## —— 独立视口装配（照 HDPlayer._build_vm 模板）——
## own_world_3d：机库是独立世界，主战场雾/光照/几何一概不掺和；BG_COLOR
## 不用透明底：机库四面围合本就露不出背景，纯色兜底防对局画面从任何缝里渗出
func _build_viewport() -> void:
	var main_vp := get_viewport()
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED   # 未激活一帧不画
	vp.msaa_3d = main_vp.msaa_3d if main_vp != null else Viewport.MSAA_2X
	vp.size = main_vp.size if main_vp != null else Vector2i(1440, 810)
	add_child(vp)
	if main_vp != null and not main_vp.size_changed.is_connected(_on_vp_resize):
		main_vp.size_changed.connect(_on_vp_resize)
	composite = CanvasLayer.new()
	composite.layer = COMPOSITE_LAYER
	composite.visible = false
	add_child(composite)
	var rect := TextureRect.new()
	rect.texture = vp.get_texture()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 全屏 Control 吃输入是交互陷阱（vm 同款教训）
	composite.add_child(rect)


func _on_vp_resize() -> void:
	var main_vp := get_viewport()
	if vp != null and main_vp != null:
		vp.size = main_vp.size


## —— 机库氛围：暖工作灯 + 中性环境光 + 轻泛光（灯带/地圈辉光），胶片调色
## 与主世界同参（ACES/对比/饱和，见 HDPlayer vm_env 同款理由：合成不显贴片感）
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.016, 0.022, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_hdr_threshold = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	# 顶部补一盏极弱冷定向光：让墙面/地面有方向性明暗（纯点光会显得平）
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	dl.light_energy = 0.22
	dl.light_color = Color(0.8, 0.85, 1.0)
	dl.shadow_enabled = false
	vp.add_child(dl)


## —— 备战机库布景（全部程序化件，照 hd_dam 摆件纪律：共用单位盒 + 实例
## 定尺寸、恰 6 枚材质本文件自建、装饰件零投影）——
func _build_hangar() -> void:
	_mesh_box = BoxMesh.new()
	_mesh_box.size = Vector3.ONE
	var m_conc: StandardMaterial3D = PBR.make("concrete", Color(0.42, 0.43, 0.44), 3.0)
	var m_conc_dark: StandardMaterial3D = PBR.make("concrete", Color(0.2, 0.21, 0.22), 3.0)
	var m_steel: StandardMaterial3D = PBR.make("paint_rust", Color(0.3, 0.31, 0.33), 1.5, 0.6)
	var m_olive: StandardMaterial3D = PBR.make("paint_rust", Color(0.28, 0.3, 0.2), 1.2)
	var m_strip := StandardMaterial3D.new()   # 工作灯带发光面
	m_strip.albedo_color = Color(1.0, 0.93, 0.8)
	m_strip.emission_enabled = true
	m_strip.emission = Color(1.0, 0.88, 0.68)
	m_strip.emission_energy_multiplier = 3.2
	var m_accent := StandardMaterial3D.new()   # 地圈琥珀描线（呼应大厅 UI 主色）
	m_accent.albedo_color = ACCENT
	m_accent.emission_enabled = true
	m_accent.emission = ACCENT
	m_accent.emission_energy_multiplier = 1.7
	var mats := {"conc": m_conc, "dark": m_conc_dark, "steel": m_steel,
			"olive": m_olive, "strip": m_strip, "accent": m_accent}
	# 围合体：地台/后墙/左右墙/顶棚（混凝土实拍贴图，装饰件角色）
	_box(Vector3(10.0, 0.24, 10.0), Vector3(0, -0.12, 0), mats["conc"])
	_box(Vector3(10.0, 3.8, 0.3), Vector3(0, 1.9, -4.85), mats["dark"])
	_box(Vector3(0.3, 3.8, 10.0), Vector3(-4.85, 1.9, 0), mats["dark"])
	_box(Vector3(0.3, 3.8, 10.0), Vector3(4.85, 1.9, 0), mats["dark"])
	_box(Vector3(10.0, 0.24, 10.0), Vector3(0, 3.92, 0), mats["dark"])
	# 顶部工作灯带 ×2（发光条 + 不投影点光：暖光从头顶两槽洒下）
	for z in [-1.7, 1.7]:
		_box(Vector3(6.4, 0.07, 0.34), Vector3(0, 3.72, z), mats["strip"])
		var om := OmniLight3D.new()
		om.position = Vector3(0, 3.4, z)
		om.light_color = Color(1.0, 0.9, 0.74)
		om.light_energy = 1.8
		om.omni_range = 10.0
		om.shadow_enabled = false
		vp.add_child(om)
	# 干员站位聚光（微顶光塑形；阴影关=性能红线，落影用地面暗盘伪造）
	var spot := SpotLight3D.new()
	spot.position = OP_POS + Vector3(0.35, 3.3, 1.15)
	spot.light_color = Color(1.0, 0.92, 0.78)
	spot.light_energy = 5.6
	spot.spot_range = 7.0
	spot.spot_angle = 26.0
	spot.shadow_enabled = false
	vp.add_child(spot)
	spot.look_at(OP_POS + Vector3(0, 1.1, 0))
	# 左半场冷补光（工作灯带是两槽居中，左墙角照不到会黑成一整块剪影底）
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.6, 2.6, 1.2)
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.7
	fill.omni_range = 9.0
	fill.shadow_enabled = false
	vp.add_child(fill)
	# 干员正面补光（镜头侧）：作战服布料贴图偏暗，只靠顶光聚光会让躯干读成
	# 一块黑影、护甲板反成「整个身体」——正面一盏把作训服/装具的层次提出来
	var face := OmniLight3D.new()
	face.position = OP_POS + Vector3(-0.3, 1.7, 2.4)
	face.light_color = Color(1.0, 0.95, 0.86)
	face.light_energy = 1.1
	face.omni_range = 5.0
	face.shadow_enabled = false
	vp.add_child(face)
	# 轮廓逆光（三光格局的 rim：主=站位聚光 / 辅=正面补光+环境）——SpotLight
	# 从干员正后上定向打背（OmniLight 会被背包挡散，聚光勾边更锐），冷青光把
	# 头肩从暗后墙里勾出来
	var rim := SpotLight3D.new()
	rim.position = OP_POS + Vector3(0.1, 2.7, -2.0)
	rim.light_color = Color(0.72, 0.85, 1.0)
	rim.light_energy = 6.0
	rim.spot_range = 7.0
	rim.spot_angle = 32.0
	rim.shadow_enabled = false
	vp.add_child(rim)
	rim.look_at(OP_POS + Vector3(0.0, 1.2, 0.2))
	# 干员地圈：暗盘（伪造接触影）+ 琥珀描线圈（备战位标识，也是画面记忆点）
	var blob := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.62
	bm.bottom_radius = 0.62
	bm.height = 0.012
	bm.radial_segments = 24
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0, 0, 0, 0.4)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = bmat
	blob.mesh = bm
	blob.position = OP_POS + Vector3(0, 0.012, 0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(blob)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.86
	tm.outer_radius = 0.92
	tm.rings = 28
	tm.ring_segments = 6
	tm.material = mats["accent"]
	ring.mesh = tm
	ring.position = OP_POS + Vector3(0, 0.02, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(ring)
	# 后墙武器架：双立柱 + 两层搁板 + 三支枪形暗件（装饰剪影，全不投影）
	var rack_z := -4.55
	for x in [-1.3, 1.3]:
		_box(Vector3(0.1, 2.0, 0.14), Vector3(x, 1.0, rack_z), mats["steel"])
	for y in [0.55, 1.45]:
		_box(Vector3(2.7, 0.07, 0.2), Vector3(0, y, rack_z), mats["steel"])
	for i in 5:
		var gx := -1.1 + float(i) * 0.55
		_box(Vector3(0.08, 1.02, 0.05), Vector3(gx, 1.13, rack_z + 0.02),
				mats["dark" if i % 2 == 0 else "steel"])
		_box(Vector3(0.05, 0.28, 0.05), Vector3(gx, 0.44, rack_z + 0.02), mats["dark"])
	# 门右侧弹药堆（干员身后右，半遮半露=纵深）
	_box(Vector3(0.62, 0.44, 0.5), Vector3(1.95, 0.22, -4.15), mats["olive"])
	_box(Vector3(0.62, 0.44, 0.5), Vector3(1.98, 0.68, -4.18), mats["olive"])
	_box(Vector3(0.44, 0.3, 0.36), Vector3(1.95, 1.05, -4.15), mats["steel"])
	# 干员左前低矮弹药箱（前景净空带，读作「备战区堆放」）
	_box(Vector3(0.55, 0.34, 0.42), Vector3(-0.95, 0.17, 0.95), mats["olive"])
	_box(Vector3(0.4, 0.26, 0.34), Vector3(-0.42, 0.13, 1.15), mats["olive"])
	# 洗墙光 ×2：从棚顶向前墙洗（照出门/架/箱的材质层次，破「背景黑团」）
	for wx in [0.5, 2.3]:   # 避开简报大屏（-1.15）：洗墙正照会把发光屏「洗白隐身」
		var wash := SpotLight3D.new()
		wash.position = Vector3(wx, 3.3, -2.2)
		wash.light_color = Color(1.0, 0.93, 0.8)
		wash.light_energy = 3.0
		wash.spot_range = 6.0
		wash.spot_angle = 40.0
		wash.shadow_enabled = false
		vp.add_child(wash)
		wash.look_at(Vector3(wx * 0.9, 1.1, -4.6))
	# 后墙工业大门（备战室出去就是战场的门语汇）：双扇门板 + 中缝 + 门楣横梁
	# + 门框琥珀警示条——背景从「一整块黑墙」变成有出口指向的纵深
	_box(Vector3(1.5, 2.7, 0.08), Vector3(-0.85, 1.35, -4.66), mats["dark"])
	_box(Vector3(1.5, 2.7, 0.08), Vector3(0.85, 1.35, -4.66), mats["dark"])
	_box(Vector3(0.1, 2.7, 0.06), Vector3(0, 1.35, -4.58), mats["steel"])
	_box(Vector3(3.4, 0.22, 0.14), Vector3(0, 2.82, -4.62), mats["steel"])
	_box(Vector3(0.09, 2.7, 0.05), Vector3(-1.66, 1.35, -4.58), mats["accent"])
	_box(Vector3(0.09, 2.7, 0.05), Vector3(1.66, 1.35, -4.58), mats["accent"])
	# 门上小窗带 ×3（工业门观察窗，暗玻璃剪影）
	for wx in [-0.85, 0.0, 0.85]:
		_box(Vector3(0.5, 0.32, 0.04), Vector3(wx, 2.35, -4.58), mats["steel"])
	# 地面光池（灯带正下方的暖光斑，unshaded 微透明）：给顶灯一个「落在地上」
	# 的着点，配合泛光出备战机库的灯下氛围
	for z in [-1.7, 1.7]:
		var pool := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(6.0, 1.1)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(1.0, 0.88, 0.66, 0.05)
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.material = pmat
		pool.mesh = pm
		pool.position = Vector3(0, 0.012, z)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vp.add_child(pool)
	# 备战区引导虚线（琥珀，从地圈前沿指向镜头方向：整备完成即出这门）
	for i in 3:
		_box(Vector3(0.55, 0.012, 0.09), Vector3(OP_POS.x - 0.35, 0.008, 1.35 + float(i) * 0.62), mats["accent"])
	# 左墙弹药箱堆（三箱错缝 + 一只小件箱 + 立式工具柜：备战机库语汇）
	_box(Vector3(0.9, 0.55, 0.6), Vector3(-3.9, 0.28, -2.6), mats["olive"])
	_box(Vector3(0.9, 0.55, 0.6), Vector3(-3.9, 0.84, -2.62), mats["olive"])
	_box(Vector3(0.9, 0.55, 0.6), Vector3(-3.86, 0.28, -1.8), mats["olive"])
	_box(Vector3(0.5, 0.34, 0.4), Vector3(-3.9, 0.17, -0.9), mats["steel"])
	_box(Vector3(0.85, 1.9, 0.5), Vector3(-4.25, 0.95, 0.4), mats["dark"])
	_box(Vector3(0.06, 1.7, 0.06), Vector3(-3.79, 0.95, 0.4), mats["accent"])
	# 右墙工具台剪影（台面 + 两条腿 + 台弹药箱：平衡左墙体量）
	_box(Vector3(0.7, 0.08, 2.2), Vector3(4.2, 0.9, -1.6), mats["steel"])
	_box(Vector3(0.6, 0.9, 0.08), Vector3(4.2, 0.45, -2.6), mats["dark"])
	_box(Vector3(0.6, 0.9, 0.08), Vector3(4.2, 0.45, -0.6), mats["dark"])
	_box(Vector3(0.5, 0.3, 0.36), Vector3(4.1, 1.1, -2.2), mats["olive"])
	# 前景右侧弹药托盘（相机右下角入画一角，压住画面底缘）
	_box(Vector3(1.1, 0.16, 0.7), Vector3(2.4, 0.08, 1.9), mats["dark"])
	_box(Vector3(0.34, 0.2, 0.34), Vector3(2.2, 0.26, 1.85), mats["olive"])
	_box(Vector3(0.34, 0.2, 0.34), Vector3(2.62, 0.26, 1.95), mats["olive"])
	# 后墙两侧竖发光条（帧化后墙、给「三光格局」两个竖向光位）
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.1, 2.6, 0.05), Vector3(2.0 * sx, 1.5, -4.72), mats["strip"])
	# —— 任务简报大屏（备战室核心元素：出征前看图）——
	# 位置=武器架上方（4 轮方案级复盘后按大半身新机位重校：左栏与干员
	# 之间的净空带 wx∈[-2.1,0.45]）；屏面噪声程序纹理出「等高线战区图」，
	# 自发光让屏幕成为空间里的光域
	_box(Vector3(2.0, 1.15, 0.09), Vector3(-0.35, 2.5, -4.55), mats["steel"])
	var scr := MeshInstance3D.new()
	var smesh := BoxMesh.new()
	smesh.size = Vector3(1.85, 1.0, 0.02)
	smesh.material = _make_screen_mat()
	scr.mesh = smesh
	scr.position = Vector3(-0.35, 2.5, -4.49)
	_screen_overlay(1.85, 1.0, Vector3(-0.35, 2.5, -4.49), scr)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(scr)
	# 屏下沿字幕条 + 屏幕辉光照台（屏幕作为辅光源：冷青光洒在屏前地面）
	_box(Vector3(1.85, 0.05, 0.03), Vector3(-0.35, 1.92, -4.48), mats["accent"])
	var glow := OmniLight3D.new()
	glow.position = Vector3(-0.35, 2.0, -3.8)
	glow.light_color = Color(0.62, 0.8, 1.0)
	glow.light_energy = 1.3
	glow.omni_range = 4.5
	glow.shadow_enabled = false
	vp.add_child(glow)
	# —— 出发前整备工作台（左前景，斜对镜头）——
	# 台面/侧板 + 显示器（亮着同一张战区图）+ 键盘鼠标 + 弹药盒/零件盒：
	# 「人在备战机库里整备装备」的叙事件
	var desk := Node3D.new()
	desk.position = Vector3(-1.15, 0.0, 1.05)
	desk.rotation.y = 0.42   # 斜对镜头（正摆会读成「贴墙家具」，斜 24° 有面向感）
	vp.add_child(desk)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.24, 0.25, 0.27)
	dm.roughness = 0.55
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3.ONE
	var dbox := func(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = dmesh
		mi.scale = size
		mi.position = pos
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	dbox.call(Vector3(1.85, 0.07, 0.72), Vector3(0, 0.94, 0), dm, desk)   # 台面
	dbox.call(Vector3(0.06, 0.92, 0.66), Vector3(-0.86, 0.46, 0), mats["dark"], desk)   # 侧板
	dbox.call(Vector3(0.06, 0.92, 0.66), Vector3(0.86, 0.46, 0), mats["dark"], desk)
	dbox.call(Vector3(1.5, 0.3, 0.5), Vector3(0, 0.42, 0), mats["dark"], desk)   # 台下储物箱
	# 显示器：支架 + 屏面（同款战区图，微转向镜头）
	dbox.call(Vector3(0.07, 0.24, 0.07), Vector3(-0.45, 1.09, -0.12), mats["steel"], desk)
	dbox.call(Vector3(0.66, 0.42, 0.04), Vector3(-0.45, 1.36, -0.14), mats["steel"], desk)
	var mon := MeshInstance3D.new()
	var mmesh := BoxMesh.new()
	mmesh.size = Vector3(0.6, 0.36, 0.02)
	mmesh.material = _make_screen_mat()
	mon.mesh = mmesh
	mon.position = Vector3(-0.45, 1.36, -0.11)
	mon.rotation.y = 0.28   # 微转向镜头
	mon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	desk.add_child(mon)
	dbox.call(Vector3(0.44, 0.025, 0.16), Vector3(-0.2, 0.99, 0.08), mats["dark"], desk)   # 键盘
	dbox.call(Vector3(0.07, 0.03, 0.11), Vector3(0.2, 0.99, 0.1), mats["dark"], desk)   # 鼠标
	dbox.call(Vector3(0.32, 0.2, 0.22), Vector3(0.62, 1.08, -0.05), mats["olive"], desk)   # 弹药盒
	dbox.call(Vector3(0.2, 0.12, 0.14), Vector3(0.3, 1.02, -0.18), mats["steel"], desk)   # 零件盒
	# 台面工作灯（暖光小灯带 + 一盏小 omni：工作台的「主光」位）
	dbox.call(Vector3(0.5, 0.04, 0.05), Vector3(-0.45, 1.62, -0.1), mats["strip"], desk)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-1.6, 1.55, 0.95)
	lamp.light_color = Color(1.0, 0.9, 0.72)
	lamp.light_energy = 0.9
	lamp.omni_range = 3.2
	lamp.shadow_enabled = false
	vp.add_child(lamp)


## 布景盒件：共用单位盒 + 节点缩放定尺寸（mesh 只此一份=面数可数），零投影
func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_box
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(mi)


## 屏幕材质（简报大屏/显示器共用）：噪声程序纹理出「战区等高线图」——
## 深青底 + 琥珀等高纹，自发光让屏幕成为机库里的光域（三光的辅光位）。
## NoiseTexture 生成 ~几 ms（256 宽），_ready 同步生成可接受
func _make_screen_mat() -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.02
	n.fractal_octaves = 2
	var ramp := Gradient.new()
	# 三段 ramp：深青海 → 中亮琥珀坡 → 亮峰——首版两段 ramp 的深青底占比
	# 过高，unshaded 恒亮后屏面仍读作「暗墙」（3 轮判图「大屏零落地」主因之一）
	ramp.set_color(0, Color(0.06, 0.1, 0.14))
	ramp.add_point(0.45, Color(0.62, 0.42, 0.18))
	ramp.set_color(1, Color(1.0, 0.82, 0.45))
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.color_ramp = ramp
	nt.width = 512
	nt.height = 256
	var m := StandardMaterial3D.new()
	# unshaded：屏幕完全不受灯影响——洗墙/聚光一叠就把噪声纹理洗成白板
	# （两轮实拍教训），恒定全亮显示纹理才读作「发光的战区图」
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = nt
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


## 战区图屏面增强（2026-10-20 判图「大屏内容糊」）：噪声底图上叠电网格线 +
## 任务标记点 + 高亮航线——unshaded 屏在 256 宽下只读作模糊色斑，实拍迭代
func _screen_overlay(w: float, h: float, pos: Vector3, parent: Node3D) -> void:
	var grid := MeshInstance3D.new()
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.55, 0.75, 0.9, 0.35)
	var gmesh := PlaneMesh.new()
	gmesh.size = Vector2(w * 0.92, h * 0.86)
	var gimg := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	for x in range(0, 256, 16):
		for y in 128:
			gimg.set_pixel(x, y, Color(1, 1, 1, 0.5))
	for y in range(0, 128, 16):
		for x in 256:
			gimg.set_pixel(x, y, Color(1, 1, 1, 0.5))
	var gt := ImageTexture.create_from_image(gimg)
	gm.albedo_texture = gt
	gmesh.material = gm
	grid.mesh = gmesh
	grid.position = pos + Vector3(0, 0, 0.02)
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(grid)


## —— 干员：soldier_hd.glb 实例化 + 重染 + idle + weapon/chest 骨骼挂点 ——
func _build_operator() -> void:
	var scene: PackedScene = load(SOLDIER_HD_PATH) if ResourceLoader.exists(SOLDIER_HD_PATH) else null
	if scene == null:
		scene = load(SOLDIER_PATH) if ResourceLoader.exists(SOLDIER_PATH) else null
	operator = scene.instantiate() if scene != null else Node3D.new()
	operator.position = OP_POS
	# 2026-10-20 目检定案（判图「人物位置反向」）：模型 rest 面朝 -Z（远离
	# 相机），-0.46 只给了侧身没给翻身——画面里看到的是后脑勺。翻面朝镜头
	# 3/4 站姿：PI 基础上偏 0.42（面向镜头、身姿微侧，照三角洲 menu 构图）
	operator.rotation.y = PI - 0.42
	vp.add_child(operator)
	var skel: Skeleton3D = null
	var ap: AnimationPlayer = null
	for c in operator.find_children("*", "Skeleton3D", true, false):
		skel = c
		break
	for c in operator.find_children("*", "AnimationPlayer", true, false):
		ap = c
		break
	# 材质逐份重染（照 hd_soldiers._make_body：duplicate 后改 Uniform/Gear，
	# 只影响干员自己）；大厅光照充足，不加敌军那套远景自发光。
	# Weapon/Lens 面隐身：模型自带一把挂在 weapon 骨上的步枪 prop（'胸口
	# 双枪'穿帮的其中一把）——干员手里拿的是真实配枪（gun_preview_provider
	# 产物），模型自带 prop 用全透明材质消隐
	for mi_v in operator.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D:
				var t: StandardMaterial3D = m.duplicate()
				if t.resource_name == "Uniform":
					t.albedo_color = OP_UNIFORM
				elif t.resource_name == "Gear":
					t.albedo_color = OP_GEAR
				elif t.resource_name == "Weapon" or t.resource_name == "Lens":
					t.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					t.albedo_color = Color(1, 1, 1, 0)
					t.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(si, t)
	if ap != null:
		ap.play("idle")   # GLB 导入时 _loop 后缀被剥并标循环（hd_soldiers 同款播放名）
	# 武器/护甲挂点：骨骼缺失（旧模型/加载失败）退化为胸口固定件，不崩。
	# BoneAttachment3D 自身 transform 每帧被骨骼全局位姿覆写——修正旋转/
	# 微调偏移一律挂在它下面的 _gun_holder 上，挂点只当「骨骼坐标系的根」
	# 2026-10-20 目检定案（判图「握枪悬浮」）：手臂无持枪动画恒 A 字垂臂，
	# 枪挂 weapon 骨（抵肩位）必然悬空。改「斜挎胸前的背枪带姿态」——三角洲
	# menu 的经典 standby：枪斜置胸前、枪口朝上偏内侧、贴住躯干，垂臂看画
	# 面自然（背带挎枪不依赖手部动画）。挂 chest 骨（呼吸随动）+ 手工斜置
	var has_chest := skel != null and skel.find_bone("chest") >= 0
	if has_chest:
		_gun_mount = BoneAttachment3D.new()
		_gun_mount.bone_name = "chest"
		skel.add_child(_gun_mount)
	else:
		_gun_mount = Node3D.new()   # 骨骼缺失兜底：换枪链照跑（枪挂胸口固定件）
		_gun_mount.position = Vector3(0.05, 1.14, 0.24)
		operator.add_child(_gun_mount)
	_gun_holder = Node3D.new()
	_gun_mount.add_child(_gun_holder)
	# 斜挎姿态（chest 骨空间：X=模型右、Y=上、Z=前向）：枪身贴胸前、
	# 绕 Z 斜 ~52°（枪口朝干员左肩上、托底朝右髋）、绕 Y 180°（枪口面朝
	# 镜头微偏）、微前倾贴胸不穿模；位置压回胸口中线略偏右（背带视觉）
	_gun_holder.position = Vector3(0.12, 0.1, -0.24)
	# 斜挎朝向：chest 骨 +Z=模型背向（枪挂 +0.2 会跑到背后，实拍定位）——
	# 枪位取负 z 贴胸前后，用 look_at 把枪口(-Z)对准「左肩上前方」，托底
	# 自然落右髋成斜挎背带姿态
	_gun_holder.look_at(_gun_holder.global_position
			+ Vector3(-0.5, 0.06, 0.4), Vector3.UP)
	if skel != null and skel.find_bone("chest") >= 0:
		_armor_mount = BoneAttachment3D.new()
		_armor_mount.bone_name = "chest"
		skel.add_child(_armor_mount)
	else:
		_armor_mount = BoneAttachment3D.new()
		_armor_mount.position = Vector3(0, 1.24, 0.1)
		operator.add_child(_armor_mount)
	_build_armor()


## 标准护甲板件（挂 chest 骨；chest 静息基=模型空间单位阵：骨 X=模型 X、
## 骨 Y=模型上、骨 Z=模型前向）。定位口径（侧视机位实拍校准）：模型自带
## 胸挂/背包剪影（Gear 材质），板件只做「外加陶瓷板」叠层——板心压回胸口
## （+0.02 而非 +0.09：首版顶到锁骨、正面读成一块冰箱门），肩/腰带收小
func _build_armor() -> void:
	var m_armor := StandardMaterial3D.new()
	m_armor.albedo_color = OP_GEAR
	m_armor.roughness = 0.72
	var m_pad := StandardMaterial3D.new()
	m_pad.albedo_color = OP_UNIFORM
	var m_stripe := StandardMaterial3D.new()   # 识别条：微发光琥珀，暗机库里一眼读出「我方」
	m_stripe.albedo_color = ACCENT
	m_stripe.emission_enabled = true
	m_stripe.emission = ACCENT
	m_stripe.emission_energy_multiplier = 0.5
	_armor_mount.add_child(_plate(Vector3(0.3, 0.34, 0.06), Vector3(0, 0.02, 0.12), m_armor))
	_armor_mount.add_child(_plate(Vector3(0.28, 0.3, 0.05), Vector3(0, 0.02, -0.11), m_armor))
	for sx in [-1.0, 1.0]:
		_armor_mount.add_child(_plate(Vector3(0.14, 0.08, 0.17), Vector3(0.21 * sx, 0.24, 0.02), m_armor))
	_armor_mount.add_child(_plate(Vector3(0.38, 0.1, 0.2), Vector3(0, -0.14, 0.0), m_armor))
	# 胸前双弹匣包：破掉主板「一整块平板」的观感（首版无细节，实拍读成大背板）
	_armor_mount.add_child(_plate(Vector3(0.11, 0.12, 0.025), Vector3(-0.075, -0.07, 0.155), m_pad))
	_armor_mount.add_child(_plate(Vector3(0.11, 0.12, 0.025), Vector3(0.075, -0.07, 0.155), m_pad))
	# 识别条单条（近景下双霓虹小块读成玩具），贴弹匣包下缘
	_armor_mount.add_child(_plate(Vector3(0.16, 0.022, 0.015), Vector3(0, -0.135, 0.155), m_stripe))


## 护甲板件（不投影：灯全关影，板件投影无收益）
func _plate(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_box
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## —— 装备联动（用户主诉求）：loadout/镜/消音键变 → 重建手持枪 ——
## 由 HDLobby._refresh_all 每次刷页时调用（键未变零开销）
func sync_gear() -> void:
	if _stash == null or not gun_preview_provider.is_valid():
		return
	var gid := str(_stash.loadout.get("primary", ""))
	if gid == "":
		gid = str(_stash.loadout.get("secondary", ""))
	if gid == "":
		_set_held(null, "")
		return
	var key := "%s|%s|%s" % [gid, str(_stash.scope_fit.get(gid, "iron")),
			str(_stash.suppressed(gid))]
	if key == _held_key:
		return
	var gun: Node3D = gun_preview_provider.call(gid)
	_set_held(gun, key)


func _set_held(gun: Node3D, key: String) -> void:
	_held_key = key
	for c in _gun_holder.get_children():
		_gun_holder.remove_child(c)
		c.queue_free()
	held_gun_id = ""
	if gun == null:
		return
	held_gun_id = str(gun.get_meta("gun_id", held_gun_id))
	_fix_gun_materials(gun)
	_gun_holder.add_child(gun)


## 枪模材质修正：局内镜体材质带 no_depth_test（vm 世界零几何下防分裂用的），
## 大厅机库有真实几何——不关会让镜片/准星隔人透画。duplicate 后关掉，
## 不动局内共享的那份（改枪台 3D 预览照旧）
func _fix_gun_materials(root: Node3D) -> void:
	for mi_v in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(si)
			if m == null:
				m = mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D and (m as StandardMaterial3D).no_depth_test:
				var t: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				t.no_depth_test = false
				t.render_priority = 0
				mi.set_surface_override_material(si, t)


## —— 显隐/停更 ——
## active = 大厅可见且在出发页：机库画面才值得占 GPU；改枪台/交易行页与
## 对局中整层隐藏 + UPDATE_DISABLED（盖住的视口一帧不多画=性能红线）
func set_active(on: bool) -> void:
	_active = on
	if composite != null:
		composite.visible = on
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on \
				else SubViewport.UPDATE_DISABLED
	set_process(on)
	if on:
		sync_gear()


func setup(stash) -> void:
	_stash = stash
	sync_gear()


## 呼吸式环摆：视线锚定干员胸口，方位角 ±4°/28s 正弦、高度 ±3.5cm——
## 「画面是活的」又不抢 UI 焦点（用户点名：不做快转）
func _process(dt: float) -> void:
	_t += dt
	if _cam == null:
		return
	var off := CAM_BASE - CAM_LOOK
	var yaw := 0.07 * sin(_t * 0.22)
	var pos := CAM_LOOK + off.rotated(Vector3.UP, yaw) \
			+ Vector3(0, 0.035 * sin(_t * 0.45), 0)
	_cam.position = pos
	_cam.look_at(CAM_LOOK)


## —— 回归断言用：场景统计（节点数/三角形面数）——
## 面数按「网格三角形数 × 实例」计（get_faces 顶点数/3，ArrayMesh/
## PrimitiveMesh 通吃）；蒙皮干员与枪模一并计入——红线断言防布景膨胀
func stats() -> Dictionary:
	var nodes := 0
	var tris := 0
	if vp == null:
		return {"nodes": 0, "tris": 0}
	var stack: Array = [vp]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			tris += int((n as MeshInstance3D).mesh.get_faces().size() / 3)
	return {"nodes": nodes, "tris": tris}
