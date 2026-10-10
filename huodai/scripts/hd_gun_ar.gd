class_name HDGunAR
extends RefCounted
## 步枪册三枪（m4a1/akm/scarh）高模几何体：用 HDGunLib 工具件（倒角盒/螺纹
## 枪管/圆护木/环件/握把/弧匣）重建，替换原 hd_guns.gd 里的 BoxMesh 直角块
## 低模（考证特征逐条保留，见各枪头注释）。
##
## 契约（保持不动）：
## - 入口：hd_guns.gd `_ar_build(id)` 分发到本文件 build(id, mats)，语义不变
##   （未知 id 返回空 Node3D 防御不崩）；_ar_has/_ar_mag_of/_ar_scope_anchor
##   仍在 hd_guns.gd 分发表。
## - 弹匣：静置真匣 = 本文件枪身根下的独立命名节点（mag_stanag/mag_banana/
##   mag_wide，原点=匣顶中心、curved_mag 向下生长、弧向前），换弹动画匣仍由
##   hd_guns 统一挂 holder（_ar_mag_of 三把只切 show=false，pos/size 逐字
##   保留——换弹手锚与掉匣替身缩放沿用原值，同 MK4 先例）。
## - 材质：调用方传参注入（build 收 hd_guns._ar_mats() 字典），本文件零材质
##   创建——材质唯一出处纪律，与 HDGunLib 同约。
##
## 顶点账目（公式口径，循环展开；运行时以 HDGunLib.count_vertices 实测为准）：
##   m4a1   基线 1266（git HEAD 机械清点：29 盒×24 + 10 柱×57）→ 推算 15058
##   akm    基线  819（27 盒×24 +  3 柱×57）→ 推算  8876
##   scarh  基线  900（28 盒×24 +  4 柱×57）→ 推算  9971
##   门槛 = 8× 基线，见 HDGunLib.POLY_MIN（test_huodai.gd #27 实测断言）。

const GUN_LIB := preload("res://scripts/hd_gunlib.gd")


## 统一入口：按 id 拼一把枪身根；未知 id 返回空 Node3D（防御不崩）
static func build(id: String, mats: Dictionary) -> Node3D:
	var root := Node3D.new()
	match id:
		"m4a1":
			_m4a1(mats, root)
		"akm":
			_akm(mats, root)
		"scarh":
			_scarh(mats, root)
		_:
			pass   # 未知 id：不落任何部件，返回空枪身根
	return root


## M4A1 突击步枪（柯尔特 M4A1 卡宾，5.56×45mm，平顶机匣）考证特征逐条落件
## （HDGunLib 高模重建——基线 1266 → 公式推算 15058，红线 POLY_MIN["m4a1"]）：
## ①全黑配色：黑机匣/黑护木/黑托（polymer 主体 + 近黑金属细节 + 亮钢小件，
##   与 M7 的 FDE 沙色形成枪册最大色差）——机匣/托体倒角盒 s12，直角棱线消除
## ②平顶机匣 + 可拆卸拱形提把（带后照门）：最强辨识件，装在顶轨上
## ③6 段伸缩聚合物托：开筒缓冲管（seg32 壁厚断面）+ 锁环/尾环双 torus +
##   倒角托体 + 侧面斜切楔（梯形侧影）+ 托底板 + 释放钮
## ④三角形准星座：宽基座 + 收顶窄段（三角收顶）+ 双护耳 + 准星柱（M16 血脉）
## ⑤圆形截面护木：seg48 圆管开筒（尾封前开）+ 散热环×3 + 尾部 delta 环
##   （全 torus 环件——「双环散热感」高模语言，对照 MK4 的 M-LOK 槽板）
## ⑥A2 鸟笼消焰器：36 段螺纹枪管 + 开筒消焰器 + 两侧纵槽口 + 前挡环
##   （短，非 M7 的长消音筒）
## ⑦微弯梯形 STANAG 30 发直匣：mag_stanag 独立命名节点 + curved_mag 三段
##   5° 微弧（_ar_mag_of 只切 show=false，pos/size 保留）
## ⑧顶部皮轨楔齿（提把座前后可见）+ 尾部 T 形拉机柄（杆+双翼三件）
static func _m4a1(mats: Dictionary, root: Node3D) -> void:
	var blk: StandardMaterial3D = mats["polymer"]   # ① 纯黑聚合物主体
	var met: StandardMaterial3D = mats["dark"]      # ① 近黑金属细节
	var stl: StandardMaterial3D = mats["steel"]     # ① 亮钢小件提层次
	# ① 平顶机匣上体 + 下机匣（上体顶面就是②⑧的平顶轨座）——倒角盒 s12
	GUN_LIB.chamfer_box(root, blk, Vector3(0.055, 0.065, 0.28),
			Vector3(0, 0.03, -0.01), Vector3.ZERO, 0.0035, 12)
	GUN_LIB.chamfer_box(root, blk, Vector3(0.05, 0.05, 0.18),
			Vector3(0, -0.02, 0.01), Vector3.ZERO, 0.003, 12)
	# ② 拱形提把：拱梁 + 前后支腿 + 提把顶后照门座 + 侧风偏钮（顶 0.103 不变）
	GUN_LIB.chamfer_box(root, met, Vector3(0.05, 0.012, 0.115),
			Vector3(0, 0.084, 0.045), Vector3.ZERO, 0.0015, 6)
	GUN_LIB.chamfer_box(root, met, Vector3(0.046, 0.03, 0.014),
			Vector3(0, 0.066, -0.005), Vector3.ZERO, 0.0012, 4)
	GUN_LIB.chamfer_box(root, met, Vector3(0.046, 0.028, 0.014),
			Vector3(0, 0.066, 0.095), Vector3.ZERO, 0.0012, 4)
	GUN_LIB.chamfer_box(root, met, Vector3(0.016, 0.014, 0.012),
			Vector3(0, 0.096, 0.07), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.01, 0.012, 0.012),
			Vector3(0.031, 0.084, 0.07), Vector3.ZERO, 0.0008, 2)
	# ⑧ 平顶皮轨：轨基 + 连续楔齿×5（提把座前后齿段均可见）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.014, 0.27),
			Vector3(0, 0.067, -0.01), Vector3.ZERO, 0.0015, 6)
	for i in 5:
		GUN_LIB.chamfer_box(root, met, Vector3(0.031, 0.006, 0.016),
				Vector3(0, 0.077, -0.125 + 0.06 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ⑧ 尾部 T 形拉机柄（杆 + 双翼三件，区别于 AKM 右侧大柄 / MP5 左置小柄）
	GUN_LIB.chamfer_box(root, met, Vector3(0.03, 0.007, 0.018),
			Vector3(0, 0.064, 0.128), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(-0.017, 0.064, 0.128), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(0.017, 0.064, 0.128), Vector3.ZERO, 0.0008, 3)
	# ③ 伸缩托：开筒缓冲管（壁厚断面）+ 锁环/尾环双 torus + 倒角托体 +
	#    侧面斜切楔（梯形侧影）+ 托底板 + 释放钮
	GUN_LIB.tube(root, blk, 0.17, 0.038, Vector3(0, 0.012, 0.215),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, stl, 0.016, 0.02, Vector3(0, 0.012, 0.148),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, stl, 0.016, 0.019, Vector3(0, 0.012, 0.205),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, blk, Vector3(0.046, 0.08, 0.13),
			Vector3(0, -0.008, 0.28), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, blk, Vector3(0.04, 0.05, 0.12),
			Vector3(0, -0.043, 0.285), Vector3(12, 0, 0), 0.002, 6)
	GUN_LIB.chamfer_box(root, met, Vector3(0.05, 0.096, 0.02),
			Vector3(0, -0.022, 0.345), Vector3.ZERO, 0.0015, 6)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.018, 0.028),
			Vector3(0.029, -0.02, 0.3), Vector3.ZERO, 0.0008, 3)
	# ⑤ 圆护木：seg48 圆管开筒（圆截面，尾封前开）+ 三道散热环 +
	#    尾部 delta 环（环件全 torus——「双环散热感」）
	GUN_LIB.tube(root, blk, 0.28, 0.054, Vector3(0, 0.02, -0.3),
			Vector3(90, 0, 0), 0.004, 0, null, 4, 48)
	for i in 3:
		GUN_LIB.torus_ring(root, met, 0.0265, 0.031,
				Vector3(0, 0.02, -0.21 - 0.09 * float(i)), Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, met, 0.0265, 0.0335, Vector3(0, 0.02, -0.155),
			Vector3(90, 0, 0))
	# ④ 三角形准星座：宽基座 + 收顶窄段（三角收顶）+ 双护耳 + 准星柱
	GUN_LIB.chamfer_box(root, met, Vector3(0.032, 0.028, 0.03),
			Vector3(0, 0.052, -0.455), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, met, Vector3(0.02, 0.022, 0.024),
			Vector3(0, 0.077, -0.455), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.006, 0.02, 0.022),
			Vector3(-0.014, 0.072, -0.455), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.006, 0.02, 0.022),
			Vector3(0.014, 0.072, -0.455), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.014, 0.005),
			Vector3(0, 0.082, -0.455), Vector3.ZERO, 0.0006, 2)
	# ⑥ 枪管（36 段高分段 + 枪口螺纹环×3 紧贴消焰器后）+ A2 鸟笼消焰器：
	#    开筒内衬亮钢膛 + 两侧纵槽口提示 + 前挡环（短于 M7 消音筒）
	GUN_LIB.barrel(root, met, 0.19, 0.024, Vector3(0, 0.03, -0.535),
			Vector3(90, 0, 0), 3, 36)
	GUN_LIB.tube(root, met, 0.058, 0.03, Vector3(0, 0.03, -0.655),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.034),
			Vector3(-0.013, 0.03, -0.655), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.034),
			Vector3(0.013, 0.03, -0.655), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.torus_ring(root, stl, 0.013, 0.018, Vector3(0, 0.03, -0.68),
			Vector3(90, 0, 0))
	# ⑦ 弹匣井（挂合同 STANAG 直匣：井口 y 顶 -0.092 对动画匣顶 -0.055）+
	#    直匣微弧（独立命名节点 mag_stanag：原点=匣顶中心，动画匣锚
	#    (0.02,-0.14,-0.16) 的匣顶 y=-0.055——5° 三段微弧，弧向前）
	GUN_LIB.chamfer_box(root, blk, Vector3(0.052, 0.092, 0.09),
			Vector3(0, -0.046, -0.16), Vector3.ZERO, 0.002, 6)
	var mag := Node3D.new()
	mag.name = "mag_stanag"
	mag.position = Vector3(0, -0.055, -0.16)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, met, Vector3(0.05, 0.17, 0.09), 5.0, 3, 3)
	# 后握把（护圈正后、后倾 20°——A2 握把角，指棱高模握把）：grip() 顶锚
	# = 旋转支点，旧 _add_grip 中心锚迁移矢量式（含 z）：
	# pos = 旧盒心 (0,-0.072,0.085) + Rx(−20°)·(0, 0.044, 0) = (0,-0.0307,0.0700)
	GUN_LIB.grip(root, blk, 0.088, Vector3(0, -0.0307, 0.07), 20.0,
			0.036, 0.05, stl, 3)
	# 护圈 / 扳机 / 前助推器（右后侧 torus 侧钮）/ 抛壳口防挡板
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.008, 0.06),
			Vector3(0, -0.052, 0.03), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.043, 0.035), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.torus_ring(root, met, 0.006, 0.012, Vector3(0.031, 0.038, 0.06),
			Vector3(0, 0, 90))
	GUN_LIB.chamfer_box(root, met, Vector3(0.008, 0.022, 0.02),
			Vector3(0.029, 0.028, 0.015), Vector3.ZERO, 0.0008, 3)


## AKM 突击步枪（7.62×39mm，冲压机匣）考证特征逐条落件（HDGunLib 高模重建
## ——基线 819 → 公式推算 8876，红线 POLY_MIN["akm"]）：
## ①木质三件套：斜切贴腮枪托 + 上护木（包住导气管的通条状木段）+ 下护木
##   （带左右掌肚），胡桃木色——大件全 s12 倒角盒 + 前箍/背带环钢件
## ②大弧度弯月 30 发弹匣（7.62 弧度比 MP5 更大更前倾，「山羊角」）：
##   mag_banana 独立命名节点 + curved_mag 四段 12° 弧（mag_of 只切 show）
## ③斜切枪口制退器：开筒短筒 + 前端斜面楔块（斜切口朝前上，AKM 独有标志）
## ④冲压机匣 + 稍亮机匣盖（分层）+ 前凸弹匣井小盒，侧面铆钉×6
## ⑤右侧大型长杆拉机柄凸出（区别于 MP5 左置小柄 / M4 尾部 T 柄）
## ⑥气块上的准星座带两翼护圈（骑在枪管上方）+ 导气管外露段 + 枪口肩环
## ⑦深灰钢机匣 + 木色件双色分明；表尺座/表尺板（机匣前上方曲射照门）
## ⑧小而直的下置握把（bakelite 橙棕、后倾 16°）
static func _akm(mats: Dictionary, root: Node3D) -> void:
	var rcv: StandardMaterial3D = mats["blued"]    # ⑦ 深灰冲压钢机匣
	var wln: StandardMaterial3D = mats["walnut"]   # ① 胡桃木三件套
	var met: StandardMaterial3D = mats["dark"]     # 深色金属件
	var stl: StandardMaterial3D = mats["steel"]    # 亮钢小件（机匣盖/铆钉/拉机柄）
	var bkl: StandardMaterial3D = mats["bakelite"] # ⑧ 橙棕电木握把
	# ④ 冲压机匣 + 稍亮机匣盖（分层）+ 前凸弹匣井小盒 + 侧面铆钉×6（左右各 3）
	GUN_LIB.chamfer_box(root, rcv, Vector3(0.05, 0.075, 0.34),
			Vector3(0, 0.02, 0), Vector3.ZERO, 0.0035, 12)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.044, 0.022, 0.30),
			Vector3(0, 0.064, 0), Vector3.ZERO, 0.002, 12)
	GUN_LIB.chamfer_box(root, rcv, Vector3(0.052, 0.08, 0.07),
			Vector3(0, -0.055, -0.18), Vector3.ZERO, 0.002, 6)
	for i in 3:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.006, 0.006),
				Vector3(-0.026, 0.032, -0.13 + 0.1 * float(i)), Vector3.ZERO,
				0.0006, 3)
		GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.006, 0.006),
				Vector3(0.026, 0.032, -0.13 + 0.1 * float(i)), Vector3.ZERO,
				0.0006, 3)
	# ① 下护木（带左右掌肚）+ 上护木（枪管上方通条状木段，包住导气管）+
	#    上护木前箍 / 下护木前箍（钢箍分层）+ 前背带环（竖环，护木下）
	GUN_LIB.chamfer_box(root, wln, Vector3(0.052, 0.052, 0.20),
			Vector3(0, -0.005, -0.27), Vector3.ZERO, 0.0035, 12)
	GUN_LIB.chamfer_box(root, wln, Vector3(0.006, 0.028, 0.09),
			Vector3(-0.0285, -0.014, -0.29), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, wln, Vector3(0.006, 0.028, 0.09),
			Vector3(0.0285, -0.014, -0.29), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, wln, Vector3(0.038, 0.032, 0.17),
			Vector3(0, 0.058, -0.28), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.042, 0.036, 0.012),
			Vector3(0, 0.058, -0.35), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.056, 0.056, 0.014),
			Vector3(0, -0.005, -0.355), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.torus_ring(root, stl, 0.004, 0.009, Vector3(0, -0.04, -0.345),
			Vector3(90, 0, 0))
	# ① 斜切贴腮枪托：托体（下斜贴腮线）+ 斜切钢托底板
	GUN_LIB.chamfer_box(root, wln, Vector3(0.042, 0.085, 0.25),
			Vector3(0, -0.045, 0.285), Vector3(-6, 0, 0), 0.003, 12)
	GUN_LIB.chamfer_box(root, met, Vector3(0.048, 0.105, 0.016),
			Vector3(0, -0.062, 0.395), Vector3(12, 0, 0), 0.0015, 12)
	# ⑦ 表尺座 + 表尺板（机匣前上方的曲射照门，与木件分色）
	GUN_LIB.chamfer_box(root, rcv, Vector3(0.034, 0.02, 0.03),
			Vector3(0, 0.055, -0.19), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.03, 0.012, 0.055),
			Vector3(0, 0.069, -0.205), Vector3.ZERO, 0.0008, 4)
	# ⑥ 导气系统：36 段枪管 + 枪口肩环（torus 阴线，制退器后露段）+
	#    气块 + 24 段导气管外露段 + 准星柱 + 两翼护圈（骑在枪管上方）
	GUN_LIB.barrel(root, rcv, 0.17, 0.022, Vector3(0, 0.03, -0.53),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.torus_ring(root, rcv, 0.01, 0.0135, Vector3(0, 0.03, -0.575),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, rcv, Vector3(0.03, 0.036, 0.03),
			Vector3(0, 0.048, -0.44), Vector3.ZERO, 0.0015, 6)
	GUN_LIB.barrel(root, stl, 0.06, 0.016, Vector3(0, 0.058, -0.395),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.01, 0.022, 0.01),
			Vector3(0, 0.072, -0.44), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.022, 0.022),
			Vector3(-0.014, 0.072, -0.44), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.022, 0.022),
			Vector3(0.014, 0.072, -0.44), Vector3.ZERO, 0.0006, 3)
	# ③ 斜切枪口制退器：开筒短筒（内衬亮钢膛）+ 前端斜面楔块（斜切口朝前上）
	GUN_LIB.tube(root, rcv, 0.06, 0.028, Vector3(0, 0.03, -0.625),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.chamfer_box(root, rcv, Vector3(0.024, 0.028, 0.02),
			Vector3(0, 0.034, -0.648), Vector3(20, 0, 0), 0.001, 4)
	# ⑤ 右侧大型长杆拉机柄（凸出机匣右侧面，z 在表尺座后方）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.03, 0.018, 0.036),
			Vector3(0.039, 0.042, 0.03), Vector3.ZERO, 0.001, 3)
	# ② 弯月匣（独立命名节点 mag_banana：原点=匣顶中心，动画匣锚
	#    (0.02,-0.13,-0.15) 的匣顶 y=-0.035——12° 四段大弧，弧向前，
	#    「山羊角」弧度大于 MP5）
	var mag := Node3D.new()
	mag.name = "mag_banana"
	mag.position = Vector3(0, -0.035, -0.17)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, rcv, Vector3(0.048, 0.19, 0.08), 12.0, 4, 3)
	# ⑧ 小而直的下置握把（bakelite 橙棕、后倾 16°，电木同色指棱×2）：
	#    grip() 顶锚迁移矢量式：pos = 旧盒心 (0,-0.055,0.11) +
	#    Rx(−16°)·(0, 0.04, 0) = (0,-0.0165,0.0990)（8 角点偏差 ≤0.05mm）
	GUN_LIB.grip(root, bkl, 0.08, Vector3(0, -0.0165, 0.099), 16.0,
			0.03, 0.042, bkl, 2)
	# 右侧快慢机柄 / 护圈 / 扳机
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.012, 0.032),
			Vector3(0.027, 0.008, 0.05), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, rcv, Vector3(0.012, 0.006, 0.06),
			Vector3(0, -0.05, 0.03), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.022, 0.008),
			Vector3(0, -0.045, 0.035), Vector3.ZERO, 0.0006, 2)


## SCAR-H 战斗步枪（FN SCAR-H Mk17，7.62×51mm NATO）考证特征逐条落件
## （HDGunLib 高模重建——基线 900 → 公式推算 9971，红线 POLY_MIN["scarh"]）：
## ①沙 tan(FDE) 细长机匣：色近 M7 但轮廓细长（0.05 宽 × 0.44 长）——大件
##   全 s12 倒角盒
## ②全长一体顶轨：从机匣尾直通护木头的单根轨基 + 连续楔齿×9（无分段感）
## ③大尺寸侧折聚合物托：贴腮板（顶 0.080 与轨齿尖齐平的⑦狙击感直线侧影）+
##   倒角托体 + 托底板 + 折叠钮 + 铰链轴/端钮 + 托侧调节钮 + 托底斜楔
## ④细长枪管 + 长护木（约占全枪一半）：左右侧开槽轨板（轨基 + 横齿×4 =
##   「侧开槽」语言）+ 护木前导气座
## ⑤宽直体 20 发 7.62 弹匣：mag_wide 独立命名节点 + curved_mag 三段 4°
##   微弧（mag_of 只切 show）
## ⑥短鸟笼消焰器（对照 M7 的长双挡环消音筒）
static func _scarh(mats: Dictionary, root: Node3D) -> void:
	var fde: StandardMaterial3D = mats["fde"]   # ① 沙 tan 细长机匣/托体
	var met: StandardMaterial3D = mats["dark"]  # 黑色轨齿/握把
	var stl: StandardMaterial3D = mats["steel"] # 亮钢小件
	# ① 细长一体机匣 + 下机匣（比 M7 的 0.062×0.075×0.30 明显瘦长）
	GUN_LIB.chamfer_box(root, fde, Vector3(0.05, 0.068, 0.44),
			Vector3(0, 0.024, -0.12), Vector3.ZERO, 0.0035, 12)
	GUN_LIB.chamfer_box(root, fde, Vector3(0.046, 0.05, 0.18),
			Vector3(0, -0.035, 0.05), Vector3.ZERO, 0.003, 12)
	# ② 全长一体顶轨：单根轨基（机匣尾 z 0.23 直通护木前 z -0.51）+ 楔齿×9
	GUN_LIB.chamfer_box(root, met, Vector3(0.026, 0.016, 0.74),
			Vector3(0, 0.066, -0.14), Vector3.ZERO, 0.0015, 6)
	for i in 9:
		GUN_LIB.chamfer_box(root, met, Vector3(0.029, 0.006, 0.016),
				Vector3(0, 0.077, -0.48 + 0.085 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ④ 长护木（0.32，约占全长一半）+ 左右侧开槽轨板（轨基 + 横齿×4）+
	#    36 段细长枪管 + 护木前导气座
	GUN_LIB.chamfer_box(root, fde, Vector3(0.048, 0.064, 0.32),
			Vector3(0, 0.026, -0.36), Vector3.ZERO, 0.0035, 12)
	for sx in [-1.0, 1.0]:
		var fx := float(sx)
		GUN_LIB.chamfer_box(root, met, Vector3(0.008, 0.03, 0.12),
				Vector3(0.028 * fx, 0.012, -0.36), Vector3.ZERO, 0.0008, 3)
		for i in 4:
			GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.028, 0.014),
					Vector3(0.0305 * fx, 0.012, -0.405 + 0.03 * float(i)),
					Vector3.ZERO, 0.0006, 2)
	GUN_LIB.barrel(root, met, 0.16, 0.022, Vector3(0, 0.028, -0.6),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.chamfer_box(root, met, Vector3(0.024, 0.026, 0.024),
			Vector3(0, 0.042, -0.505), Vector3.ZERO, 0.001, 4)
	# ⑥ 短鸟笼消焰器：开筒内衬亮钢膛 + 两侧纵槽口提示 + 后挡环
	GUN_LIB.tube(root, met, 0.055, 0.03, Vector3(0, 0.028, -0.675),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.03),
			Vector3(-0.013, 0.028, -0.675), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.03),
			Vector3(0.013, 0.028, -0.675), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.torus_ring(root, stl, 0.0135, 0.018, Vector3(0, 0.028, -0.65),
			Vector3(90, 0, 0))
	# ③ 大侧折托：贴腮板（⑦ 顶 0.080 与轨齿顶齐平）+ 倒角托体 + 托底板 +
	#    折叠钮 + 铰链轴（24 段）/ 端钮 torus + 托侧调节钮 torus + 托底斜楔
	#    （「大方托」，与 M7 的 Magpul 小托对照）
	GUN_LIB.chamfer_box(root, fde, Vector3(0.042, 0.026, 0.24),
			Vector3(0, 0.067, 0.28), Vector3.ZERO, 0.0015, 6)
	GUN_LIB.chamfer_box(root, fde, Vector3(0.046, 0.085, 0.19),
			Vector3(0, -0.005, 0.30), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, met, Vector3(0.052, 0.105, 0.018),
			Vector3(0, -0.012, 0.40), Vector3.ZERO, 0.0015, 6)
	GUN_LIB.chamfer_box(root, met, Vector3(0.014, 0.026, 0.03),
			Vector3(0.032, 0.02, 0.225), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.barrel(root, stl, 0.05, 0.024, Vector3(0.03, 0.005, 0.19),
			Vector3(0, 0, 90), 0, 24)
	GUN_LIB.torus_ring(root, stl, 0.007, 0.012, Vector3(0.058, 0.005, 0.19),
			Vector3(0, 0, 90))
	GUN_LIB.torus_ring(root, stl, 0.005, 0.011, Vector3(0.027, -0.01, 0.3),
			Vector3(0, 0, 90))
	GUN_LIB.chamfer_box(root, fde, Vector3(0.04, 0.042, 0.11),
			Vector3(0, -0.052, 0.33), Vector3(10, 0, 0), 0.002, 6)
	# ⑤ 宽弹匣井（挂 mag_of 宽直匣：井口 y 顶 -0.0825 对动画匣顶 -0.03）+
	#    宽直匣微弧（独立命名节点 mag_wide：原点=匣顶中心，动画匣锚
	#    (0.02,-0.13,-0.16) 的匣顶 y=-0.03——4° 三段近直微弧）
	GUN_LIB.chamfer_box(root, fde, Vector3(0.056, 0.075, 0.085),
			Vector3(0, -0.045, -0.19), Vector3.ZERO, 0.002, 6)
	var mag := Node3D.new()
	mag.name = "mag_wide"
	mag.position = Vector3(0, -0.03, -0.175)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, met, Vector3(0.054, 0.2, 0.09), 4.0, 3, 3)
	# 后握把（护圈正后、后倾 20°，指棱高模握把）：grip() 顶锚迁移矢量式：
	# pos = 旧盒心 (0,-0.07,0.075) + Rx(−20°)·(0, 0.0425, 0) = (0,-0.0301,0.0605)
	GUN_LIB.grip(root, met, 0.085, Vector3(0, -0.0301, 0.0605), 20.0,
			0.036, 0.05, stl, 3)
	# 护圈 / 扳机 / 前置左侧拉机柄（SCAR 位于护木后上左）
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.055),
			Vector3(0, -0.052, 0.015), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.02, 0.008),
			Vector3(0, -0.045, 0.02), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, met, Vector3(0.022, 0.012, 0.028),
			Vector3(-0.034, 0.03, -0.3), Vector3.ZERO, 0.0008, 3)
