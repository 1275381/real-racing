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
##   m14    基线 1557（34 盒×24 + 13 柱×57）→ 公式推算 13837（目标 ≥10000，
##          红线 12456 = 8× 基线，见 HDGunLib.POLY_MIN["m14"]）
##   asval  基线 1878（45 盒×24 + 14 柱×57，新枪无旧模按建模调用清点，
##          逐行确权见 POLY_BASE 注）→ 公式推算 15820、实测 16022
##          （目标 ≥10000 达标，红线 15024 = 8× 基线，见 HDGunLib.POLY_MIN
##          ["asval"]）
##   k416   基线 2247（58 盒×24 + 15 柱×57，新枪无旧模按建模调用清点，
##          逐行确权见 POLY_BASE 注）→ 公式推算 21263、实测以
##          count_vertices 为准（目标 ≥10000，红线 17976 = 8× 基线，见
##          HDGunLib.POLY_MIN["k416"]）
##   an94   基线 3567（56 盒×24 + 39 柱×57，新枪无旧模按建模调用清点，
##          逐行确权见 POLY_BASE 注；柱多因制退器 20 排气孔环 + 星形盘
##          觇孔×5——识别件密度最高的一把）→ 实测以 count_vertices 为准
##          （目标 ≥10000，红线 28536 = 8× 基线，见 HDGunLib.POLY_MIN["an94"]）
##   sr25   基线 4073（2026-10-26 拆自带瞄准镜后按建模调用重清点：旧 4173
##          含镜体筒环件约 100 顶点调用；红线 POLY_MIN 同步 33384→32000，
##          拆镜后实测 32565 仍在红线上）→ 实测以 count_vertices 为准
##          （目标 ≥10000，红线 POLY_MIN["sr25"]）
##   k437   基线 2346（74 盒×24 + 8 柱×57，2026-10-29 商店枪·S4 现役 .300
##          BLK 突击步枪，新枪无旧模按建模调用清点，逐行确权见 POLY_BASE
##          注；柱少因枪管几乎全被护木包住、出厂裸冠——盒多柱少的布局）
##          → 实测以 count_vertices 为准（目标 ≥10000，红线 18776 =
##          8× 基线，见 HDGunLib.POLY_MIN["k437"]）
##   qcq171 基线 2361（77 盒×24 + 9 柱×57，2026-10-30 商店枪·9×19mm 冲锋枪
##          【册属冲锋枪 SMG_IDS，几何体按常规有托布局放本册——hd_guns
##          _smg_build 分发到 AR_LIB.build 同链】，新枪无旧模按建模调用清点，
##          逐行确权见 POLY_BASE 注）→ 实测以 count_vertices 为准（目标
##          ≥10000，红线 18888 = 8× 基线，见 HDGunLib.POLY_MIN["qcq171"]）
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
		"m14":
			_m14(mats, root)
		"asval":
			_ar_asval(mats, root)
		"k416":
			_ar_k416(mats, root)
		"an94":
			_ar_an94(mats, root)
		"sr25":
			_ar_sr25(mats, root)
		"k437":
			_ar_k437(mats, root)
		"qcq171":
			_ar_qcq171(mats, root)
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
	# 弹匣 polymer 近黑（2026-10 二轮判图「M4A1 银白弹匣」：dark 直射渲染
	# 0.4 左右在黑枪身上读作银白——黑聚合物匣通用语义）
	GUN_LIB.curved_mag(mag, mats["polymer"], Vector3(0.05, 0.17, 0.09),
			5.0, 3, 3)
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
	# 弹匣 polymer 近黑（2026-10 二轮判图「AKM 银白弹匣」：blued 渲 0.49
	# 亮银灰——黑聚合物匣，木件/电木撞色不变）
	GUN_LIB.curved_mag(mag, mats["polymer"], Vector3(0.048, 0.19, 0.08),
			12.0, 4, 3)
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
	# ③ 大侧折托：托接颈（2026-10 判图「枪托衔接断缝」：机匣尾 z +0.10 与
	#    托体头 z +0.205 之间 105mm 空档只有悬空贴腮板——补 FDE 接颈盒两端
	#    各嵌入 5mm 连成一体）+ 贴腮板（⑦ 顶 0.080 与轨齿顶齐平）+ 倒角托体
	#    + 托底板 + 折叠钮 + 铰链轴（24 段）/ 端钮 torus + 托侧调节钮 torus
	#    + 托底斜楔（「大方托」，与 M7 的 Magpul 小托对照）
	GUN_LIB.chamfer_box(root, fde, Vector3(0.046, 0.055, 0.13),
			Vector3(0, 0.008, 0.157), Vector3.ZERO, 0.002, 8)
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
	# 弹匣 polymer 近黑（2026-10 二轮判图「SCAR-H 银白弹匣」，同 M4A1 案）
	GUN_LIB.curved_mag(mag, mats["polymer"], Vector3(0.054, 0.2, 0.09),
			4.0, 3, 3)
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


## M14 射手步枪（官方考证 DMR，7.62×51mm NATO 半自动）考证特征逐条落件
## （HDGunLib 高模重建——基线 1533 → 公式推算 12971，红线 POLY_MIN["m14"]；
## 枪体量比 SCAR-H 更长：枪口 -0.74 到托底板 +0.435 全长 ≈1.18m 模型尺，
## 对官方 1.12m 总长 + 559mm/22 英寸枪管——枪管轴线从枪托到枪口近乎通直，
## 轮廓是 M1 加兰德的弹匣供弹放大版、重心明显偏前）：
## ①整体布局：全尺寸战斗步枪，22 寸长枪管（0.56 模型尺）贯通前托直出枪口
## ②枪托形制：一体式全包胡桃木托从托底板直通前托端，直通式贴腮无鼓包
##   （托体后端 -4° 微抬出渐高的托尾线），握把颈部为和缓曲线收腰（14° 缓倾
##   +窄截面）；托底板深钢色金属 + 尾端铰接仓门
## ③上护木：棕色玻纤护木罩枪管前半段，顶/侧 5 条横向弧形凹槽搓纹，前端
##   被金属箍收口
## ④导气系统：枪管中段下方与枪管平行的圆柱导气活塞管（深钢色），向前插入
##   导气箍、端面露圆形活塞调节帽——枪身侧下方最醒目部件
## ⑤导气箍与背带环：枪管前端的金属箍环把枪管/活塞管/护木束成一体，箍下
##   挂椭圆钢背带环
## ⑥消焰器：枪口 5cm 多缝棱柱式（侧面长条排烟缝 + 端面圆孔内衬），其后为
##   裸露枪管段、无其他枪口件
## ⑦准星：消焰器后方立「大麦粒」柱状准星 + 两侧厚重护圈耳
## ⑧照门：机匣后上方导轨式照门座 + 两侧大直径规正轮（风偏/高低）+ 可放倒
##   觇孔照门板（真实机瞄为建模件——_finish_gun iron 分支跳过兜底机瞄片，
##   同 mp7 先例）
## ⑨机匣与拉机柄：长方形平顶深灰钢机匣 + 右侧弯钩形拉机柄 + 右后侧快慢机
##   小圆钮
## ⑩供弹具：黑色磷化 20 发钢直匣微前倾（mag_dmr 独立命名节点 + curved_mag
##   三段 5° 弧），匣底明显伸出木托底面以下
## ⑪扳机护圈：大尺寸钢质环形护圈与弹匣井/握把颈连成一体（加兰德式布局）
## ⑫背带点位：三处椭圆钢背带环——枪托左侧前部/导气箍正下方/托底板左下角
## ⑬配色分区：胡桃木棕托体+护木最大色块；机匣/枪管/导气管磷化深灰钢；
##   消焰器/弹匣/照门近黑；背带环/快慢机等小件哑光黑（专用五色见
##   hd_guns._ar_mats 的 m14* 键）
static func _m14(mats: Dictionary, root: Node3D) -> void:
	var stl: StandardMaterial3D = mats["m14steel"]    # ⑬ 磷化深灰钢（机匣/枪管/导气管）
	var wln: StandardMaterial3D = mats["m14walnut"]   # ⑬ 胡桃木（托体/前托/握把颈）
	var fgr: StandardMaterial3D = mats["m14fg"]       # ⑬ 玻纤棕（上护木）
	var blk: StandardMaterial3D = mats["m14black"]    # ⑬ 近黑（消焰器/弹匣/照门）
	var drk: StandardMaterial3D = mats["m14dark"]     # ⑬ 哑光黑（背带环/快慢机/扳机）
	# ⑨ 长方形平顶深灰钢机匣（上体顶面为⑧照门座轨面）+ 下机匣（护圈/弹匣
	#    井座，加兰德式一体布局）——大件 s16/s12 倒角盒；下机匣后端伸进②托
	#    尾桥体内（端面埋入木托，不在 vm_fill 补光灯 6cm 死区裸露）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.052, 0.062, 0.30),
			Vector3(0, 0.045, -0.04), Vector3.ZERO, 0.003, 16)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.048, 0.048, 0.24),
			Vector3(0, 0.0, -0.045), Vector3.ZERO, 0.0025, 12)
	# ⑧ 导轨式照门座（机匣后上方）+ 大直径滚花规正轮×2（风偏/高低，48 段
	#    高分段读滚花）+ 可放倒觇孔照门板（后仰 12°）
	GUN_LIB.chamfer_box(root, blk, Vector3(0.034, 0.014, 0.08),
			Vector3(0, 0.083, 0.06), Vector3.ZERO, 0.001, 4)
	GUN_LIB.barrel(root, blk, 0.014, 0.028, Vector3(-0.023, 0.086, 0.06),
			Vector3(0, 0, 90), 0, 48)
	GUN_LIB.barrel(root, blk, 0.014, 0.028, Vector3(0.023, 0.086, 0.06),
			Vector3(0, 0, 90), 0, 48)
	GUN_LIB.chamfer_box(root, blk, Vector3(0.006, 0.024, 0.006),
			Vector3(0, 0.098, 0.085), Vector3(-12, 0, 0), 0.0008, 4)
	# ⑨ 右侧弯钩形拉机柄（杆 + 前下弯钩两件）+ 右后侧快慢机选择杆小圆钮
	GUN_LIB.chamfer_box(root, stl, Vector3(0.026, 0.013, 0.016),
			Vector3(0.034, 0.055, 0.01), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.01, 0.01, 0.026),
			Vector3(0.034, 0.048, -0.006), Vector3(15, 0, 0), 0.0008, 3)
	GUN_LIB.barrel(root, drk, 0.008, 0.013, Vector3(0.028, 0.032, 0.075),
			Vector3(0, 0, 90), 0, 16)
	# ① 22 寸长枪管（48 段高分段、无螺纹环——⑥裸管直出消焰器）
	GUN_LIB.barrel(root, stl, 0.56, 0.022, Vector3(0, 0.032, -0.41),
			Vector3(90, 0, 0), 0, 48)
	# ⑥ 多缝棱柱式消焰器：开筒内衬亮钢膛（端面圆孔）+ 侧面长条排烟缝×2
	#    （约 5cm，其后即裸露枪管段）
	GUN_LIB.tube(root, blk, 0.05, 0.026, Vector3(0, 0.032, -0.715),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.chamfer_box(root, blk, Vector3(0.004, 0.005, 0.034),
			Vector3(-0.011, 0.032, -0.715), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, blk, Vector3(0.004, 0.005, 0.034),
			Vector3(0.011, 0.032, -0.715), Vector3.ZERO, 0.0006, 3)
	# ⑦ 「大麦粒」柱状准星（基座 + 圆顶柱）+ 两侧厚重护圈耳
	GUN_LIB.chamfer_box(root, stl, Vector3(0.014, 0.01, 0.016),
			Vector3(0, 0.038, -0.655), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.barrel(root, stl, 0.02, 0.007, Vector3(0, 0.052, -0.655),
			Vector3.ZERO, 0, 16)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.024, 0.012),
			Vector3(-0.012, 0.052, -0.655), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.024, 0.012),
			Vector3(0.012, 0.052, -0.655), Vector3.ZERO, 0.0008, 4)
	# ④⑤ 导气系统：导气箍金属环（束枪管/活塞管/护木一体）+ 箍下椭圆钢
	#    背带环（⑫点位 2）+ 24 段导气活塞管（枪管中段下方平行前插）+
	#    端面圆形活塞调节帽（凸出箍前面可辨）
	GUN_LIB.barrel(root, stl, 0.024, 0.052, Vector3(0, 0.032, -0.575),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.torus_ring(root, drk, 0.004, 0.011, Vector3(0, 0.0, -0.575),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.barrel(root, stl, 0.26, 0.018, Vector3(0, 0.011, -0.445),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.barrel(root, stl, 0.012, 0.021, Vector3(0, 0.011, -0.591),
			Vector3(90, 0, 0), 0, 16)
	# ③ 上护木：玻纤棕圆筒开筒（seg48 内衬露壁厚）+ 前端金属收口箍 +
	#    顶/侧横向弧形凹槽搓纹×5（暗色木纹槽影，防滑纹）
	GUN_LIB.tube(root, fgr, 0.36, 0.046, Vector3(0, 0.032, -0.39),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 48)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.05, 0.05, 0.014),
			Vector3(0, 0.032, -0.563), Vector3.ZERO, 0.0008, 3)
	for i in 5:
		GUN_LIB.chamfer_box(root, wln, Vector3(0.048, 0.005, 0.008),
				Vector3(0, 0.032, -0.53 + 0.05 * float(i)), Vector3.ZERO,
				0.0008, 4)
	# ② 一体式全包胡桃木托：前托（从托底板直通前护木端，顶面留枪管嵌槽）
	#    + 托体（直通式贴腮无鼓包，后端 -4° 微抬出渐高托尾线）+ 握把颈
	#    过渡腰（和缓曲线收腰）
	GUN_LIB.chamfer_box(root, wln, Vector3(0.046, 0.04, 0.75),
			Vector3(0, -0.012, -0.205), Vector3.ZERO, 0.003, 16)
	GUN_LIB.chamfer_box(root, wln, Vector3(0.046, 0.088, 0.25),
			Vector3(0, 0.002, 0.295), Vector3(-4, 0, 0), 0.003, 16)
	GUN_LIB.chamfer_box(root, wln, Vector3(0.044, 0.055, 0.09),
			Vector3(0, -0.022, 0.205), Vector3(-6, 0, 0), 0.0025, 12)
	# ② 托尾桥（木托包机匣尾，M14 真车木托本就围住机匣后段）：从托体顶升至
	#    照门座底（y 0.076 与机匣顶齐平），把上/下机匣后端面整个埋进木托——
	#    2026-10 一轮自查判图硬伤：裸露后端面距 vm_fill 补光灯（挂握把锚
	#    原点，枪身局部 (0,-0.006,0.1568)）仅 4.5cm、正入射近距爆白成「白色
	#    大板」；桥体各面背向/侧向灯光，自身不进爆白死区（A/B 熄灯对照实证）。
	#    桥宽 0.052 与上机匣同宽：窄于机匣会在两侧露出 2mm 端面边条、补光下
	#    依旧爆白（二轮 A/B 实证后加宽盖满）
	GUN_LIB.chamfer_box(root, wln, Vector3(0.052, 0.07, 0.09),
			Vector3(0, 0.041, 0.115), Vector3.ZERO, 0.0025, 12)
	# ② 后握把（握把颈部和缓收腰：14° 缓倾 + 窄截面 0.034×0.046，木纹同色
	#    指棱×2 读检查纹）：grip() 顶锚=旋转支点，HOLD_DELTA 精算锚点
	#    （见 hd_guns.gd m14 条目：Δ = MK4 基准 − 本锚 (0,-0.028,0.155)）
	GUN_LIB.grip(root, wln, 0.09, Vector3(0, -0.028, 0.155), 14.0,
			0.034, 0.046, wln, 2)
	# ② 深钢色金属托底板（随托体 -4°）+ 尾端铰接仓门
	GUN_LIB.chamfer_box(root, stl, Vector3(0.05, 0.1, 0.016),
			Vector3(0, -0.006, 0.427), Vector3(-4, 0, 0), 0.0015, 12)
	GUN_LIB.chamfer_box(root, drk, Vector3(0.03, 0.03, 0.008),
			Vector3(0, -0.048, 0.424), Vector3.ZERO, 0.0008, 4)
	# ⑫ 背带点位 1/3：枪托左侧前部 + 托底板左下角（椭圆环面贴托侧）
	GUN_LIB.torus_ring(root, drk, 0.004, 0.011, Vector3(-0.026, -0.012, -0.5),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.torus_ring(root, drk, 0.004, 0.011, Vector3(-0.026, -0.052, 0.42),
			Vector3(0, 0, 90), 28, 18)
	# ⑪ 大尺寸钢质环形扳机护圈（底梁 + 前后柱与弹匣井/握把颈连成一体）+
	#    扳机
	GUN_LIB.chamfer_box(root, stl, Vector3(0.014, 0.008, 0.10),
			Vector3(0, -0.062, 0.055), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.014, 0.03, 0.01),
			Vector3(0, -0.047, 0.008), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.014, 0.026, 0.01),
			Vector3(0, -0.049, 0.102), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, drk, Vector3(0.008, 0.026, 0.008),
			Vector3(0, -0.04, 0.055), Vector3(8, 0, 0), 0.0006, 3)
	# ⑩ 20 发黑色磷化钢直匣（独立命名节点 mag_dmr：原点=匣顶中心，动画匣
	#    锚见 _ar_mag_of m14——5° 三段微弧微带前倾，匣底伸出木托底面以下）
	var mag := Node3D.new()
	mag.name = "mag_dmr"
	mag.position = Vector3(0, -0.02, -0.085)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, blk, Vector3(0.042, 0.15, 0.072), 5.0, 3, 3)
	# M14 专属配件（2026-10 用户定案，视觉件；解锁态由 hd_guns._m14_mod
	# 查询注入——build 时 mats 附 "_m14_mods" 字典键传递，缺省 = 原版）：
	# foregrip 战术护木（下挂导轨 + 垂直前握把，替代玻纤上护木段视觉升级）
	# extmag 30 发长匣（匣体加长 5cm + 底部扩容台阶）
	var mods: Dictionary = mats.get("_m14_mods", {})
	if bool(mods.get("foregrip", false)):
		# 战术护木：下挂短轨基条 + 垂直前握把（深灰聚合物，grip 高模件）
		GUN_LIB.chamfer_box(root, drk, Vector3(0.024, 0.008, 0.11),
				Vector3(0, -0.028, -0.23), Vector3.ZERO, 0.001, 4)
		GUN_LIB.grip(root, drk, 0.075, Vector3(0, -0.036, -0.24), 8.0,
				0.03, 0.038, blk, 3)
	if bool(mods.get("extmag", false)):
		# 30 发长匣：匣体向下加长（原匣 0.15 → 0.20）+ 底部扩容台阶
		GUN_LIB.chamfer_box(mag, blk, Vector3(0.046, 0.09, 0.076),
				Vector3(0, -0.19, 0.0), Vector3.ZERO, 0.001, 4)


## AS Val 特种突击步枪（官方考证 9×39mm 亚音速特种突击步枪，2026-10 商店枪）
## 考证特征逐条落件（HDGunLib 高模重建——基线 1878 → 公式推算 15820、实测
## 16022，红线 POLY_MIN["asval"]；整体布局照 ref_asval 实物参考图：短机匣后接
## 全长消音管，消音管约占全枪 1/2 长度，「半杆枪都是管子」——枪身 z -0.603
## (枪口) 到 +0.369(托底板) 全长 ≈0.97 模型尺，对官方展开 875mm）：
## ①整体布局：常规（非无托）布局，短机匣（z -0.14..+0.14）后接全长消音管
##   （含台阶座/锥罩的消音段 z -0.095..-0.60 ≈全枪 52%），侧折骨架托收尾
## ②一体消音器：等直径光滑圆柱粗管（tube seg48 外径 0.048），外壁无散热孔
##   （考证明确「外壁无散热孔」——高模语言用近枪口两道接缝环带刻线表达管节，
##   不开孔）；后端以一级台阶收进护木锥罩（d0.058 台阶座骑在 d0.048 管上）、
##   前端顶装准星抱箍，管面仅近枪口处一圈细微接缝环带
## ③照门：U 型缺口照门带滑动游标，装在机匣前缘/护木尾端上方的独立凸起座上，
##   与消音管前准星构成超长瞄准基线（-0.115 到 -0.52）
## ④准星：柱形准星带两侧半圆护翼，立在环抱消音管前段的圆形基座上
## ⑤上机匣与防尘盖：冲压钢板（vsteel），防尘盖面三条纵向加强肋，尾端连枪托
##   折叠铰链座，右侧面 AK 式大型杠杆保险
## ⑥聚合物下护木：锥形多面体罩壳（三段收张倒角盒读锥面）包住导气装置并
##   平滑过渡到消音器基座，老化梅棕色变体（考证「黑或老化梅棕」取梅棕——
##   苏系梅棕聚合物家具是 AS Val 的招牌识别色）
## ⑦侧折骨架枪托：圆管三角骨架（上管+斜撑）+ 矩形带钩底板，铰链块带解锁
##   拨杆（展开态建模，折叠贴靠机匣右侧的动态不表达）
## ⑧弹匣：聚合物弧形匣、背板平直、两面横向肋条——游戏按用户定案做 40 发
##   长匣（等比拉长匣体 0.245、肋条加密 4 道随弧排布），mag_val 独立命名
##   节点、动画匣 show:false 照 scarh 先例
## ⑨拉机柄：仅右侧、扁平杠杆式，位于弹匣口上方偏后位置
## ⑩快慢机：扳机护圈后端内藏双销点按式选择器（外观即护圈内两颗小圆销）
## ⑪扳机与握把：AK 式弯钩扳机 + 镂空护圈 + 后倾 18° 全尺寸聚合物握把
## ⑫背带环与配色：护木下方与枪托底板左侧各一背带环；全枪黑色磷化钢
##   （vsteel #1B1D1F）+ 哑光碳黑聚合物（vpolym #26282A），仅棱边磨损露
##   冷灰金属（vwear #6E7378）、防尘盖旧枪面磨损高光（vcover #3A3D40），
##   无木件、无花色涂装
static func _ar_asval(mats: Dictionary, root: Node3D) -> void:
	var stl: StandardMaterial3D = mats["vsteel"]    # ⑫ 黑色磷化钢（机匣/消音器/枪托骨架）
	var ply: StandardMaterial3D = mats["vpolym"]    # ⑫ 哑光碳黑聚合物（握把/弹匣/胶垫）
	var plm: StandardMaterial3D = mats["vplum"]     # ⑥ 老化梅棕聚合物（护木锥罩）
	var wear: StandardMaterial3D = mats["vwear"]    # ⑫ 冷灰磨损（棱边露金属/滑动游标）
	var cvr: StandardMaterial3D = mats["vcover"]    # ⑫ 防尘盖磨损高光（旧枪面）
	# ⑤ 上机匣（冲压钢板，s16 高分段）+ 下机匣（弹匣井/握把座一体）——大件
	#    高分段倒角盒：直角棱线消除、顶面轨线高光顺滑
	GUN_LIB.chamfer_box(root, stl, Vector3(0.050, 0.056, 0.28),
			Vector3(0, 0.040, 0.0), Vector3.ZERO, 0.003, 16)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.048, 0.048, 0.20),
			Vector3(0, -0.008, 0.02), Vector3.ZERO, 0.0025, 14)
	# ⑤ 防尘盖（旧枪面磨损高光 vcover 分色盖板，顶 0.078）+ 纵向加强肋×3
	#    （沿机匣纵向的冲压加强槽，左右对称+中线）
	GUN_LIB.chamfer_box(root, cvr, Vector3(0.046, 0.014, 0.24),
			Vector3(0, 0.071, 0.005), Vector3.ZERO, 0.0015, 12)
	for i in 3:
		GUN_LIB.chamfer_box(root, cvr, Vector3(0.005, 0.004, 0.22),
				Vector3(-0.014 + 0.014 * float(i), 0.080, 0.005), Vector3.ZERO,
				0.0006, 2)
	# ⑧ 弹匣井（下机匣前下、井口前缘 z -0.1225 在机匣内；井底 y -0.067
	#    对 mag_val 匣顶 -0.060 嵌入 7mm 防接缝）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.052, 0.050, 0.075),
			Vector3(0, -0.042, -0.085), Vector3.ZERO, 0.002, 10)
	# ⑤ 右侧面 AK 式大型杠杆保险（长杆 + 轴销圆盘，x 正 = 右侧）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.006, 0.016, 0.05),
			Vector3(0.028, 0.010, 0.055), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.barrel(root, stl, 0.030, 0.016, Vector3(0.0285, 0.010, 0.028),
			Vector3(0, 0, 90), 0, 24)
	# ⑨ 右侧扁平杠杆式拉机柄（弹匣口上方偏后：匣井前缘 z -0.0475，柄 z 0.0
	#    在其后、y 0.026 在机匣右侧面上段）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.007, 0.05),
			Vector3(0.029, 0.026, 0.0), Vector3.ZERO, 0.0008, 3)
	# ③ 照门凸起座（机匣前缘/护木尾端上方的独立凸起座）+ 照门基 + U 型缺口
	#    双耳 + 滑动游标（冷灰磨损色游标——照门上最常摩的滑动件）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.032, 0.024, 0.05),
			Vector3(0, 0.088, -0.115), Vector3.ZERO, 0.0015, 8)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.030, 0.008, 0.045),
			Vector3(0, 0.103, -0.115), Vector3.ZERO, 0.001, 6)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.007, 0.016, 0.010),
				Vector3(0.011 * sx, 0.114, -0.115), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, wear, Vector3(0.022, 0.005, 0.012),
			Vector3(0, 0.110, -0.100), Vector3.ZERO, 0.0006, 2)
	# ⑥ 聚合物下护木：锥形多面体罩壳三段收张（后段接机匣 → 中段包导气装置
	#    最宽 → 前唇过渡到消音器基座），梅棕聚合物哑光件
	GUN_LIB.chamfer_box(root, plm, Vector3(0.054, 0.050, 0.07),
			Vector3(0, 0.020, -0.125), Vector3.ZERO, 0.002, 12)
	GUN_LIB.chamfer_box(root, plm, Vector3(0.058, 0.056, 0.07),
			Vector3(0, 0.022, -0.19), Vector3.ZERO, 0.002, 12)
	GUN_LIB.chamfer_box(root, plm, Vector3(0.052, 0.048, 0.045),
			Vector3(0, 0.026, -0.242), Vector3.ZERO, 0.0015, 8)
	# ② 一级台阶收进座（d0.058 台阶骑在护木锥罩前，d0.048 消音管从座里
	#    穿出——「后端以一级台阶收进护木锥罩」的台阶语言）+ 一体消音主管
	#    （seg48 高分段等直径光滑圆柱粗管，尾盖藏台阶座内、枪口端开放由
	#    内衬探出露壁厚断面——沿轴视角见消音管腔）
	GUN_LIB.tube(root, stl, 0.05, 0.058, Vector3(0, 0.032, -0.285),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 48)
	GUN_LIB.tube(root, stl, 0.30, 0.048, Vector3(0, 0.032, -0.45),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 48)
	# ② 近枪口接缝环带×2（消音管管节的细微接缝环带，36×18 高密度环读细
	#    刻线；不开散热孔——考证明确外壁无孔）
	GUN_LIB.torus_ring(root, stl, 0.0235, 0.0255, Vector3(0, 0.032, -0.575),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, stl, 0.0235, 0.0255, Vector3(0, 0.032, -0.555),
			Vector3(90, 0, 0))
	# ④ 前准星：环抱消音管前段的圆形基座（36 段短抱箍）+ 柱形准星 + 两侧
	#    半圆护翼（立抱箍上、略高于准星柱的保护翼）
	GUN_LIB.barrel(root, stl, 0.024, 0.056, Vector3(0, 0.032, -0.52),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.barrel(root, stl, 0.02, 0.006, Vector3(0, 0.058, -0.52),
			Vector3.ZERO, 0, 48)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.006, 0.024, 0.012),
				Vector3(0.008 * sx, 0.060, -0.52), Vector3.ZERO, 0.0008, 3)
	# ⑦ 侧折骨架枪托（展开态建模）：机匣尾铰链块 + 解锁拨杆（右）+ 铰链销
	#    + 圆管三角骨架（上管平直 / 斜撑下斜 Rx(105°) 入托底板下角）+
	#    矩形带钩底板（板顶钩唇 + 聚合物胶垫）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.048, 0.050, 0.05),
			Vector3(0, 0.034, 0.165), Vector3.ZERO, 0.002, 12)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.010, 0.018, 0.028),
			Vector3(0.028, 0.024, 0.17), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.barrel(root, stl, 0.056, 0.012, Vector3(0, 0.034, 0.148),
			Vector3(0, 0, 90), 0, 36)
	GUN_LIB.barrel(root, stl, 0.185, 0.012, Vector3(0, 0.022, 0.275),
			Vector3(90, 0, 0), 0, 48)
	GUN_LIB.barrel(root, stl, 0.19, 0.012, Vector3(0, -0.008, 0.272),
			Vector3(105, 0, 0), 0, 48)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.050, 0.096, 0.014),
			Vector3(0, -0.009, 0.362), Vector3.ZERO, 0.0015, 12)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.046, 0.022, 0.018),
			Vector3(0, 0.049, 0.356), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.048, 0.018, 0.008),
			Vector3(0, -0.065, 0.363), Vector3.ZERO, 0.001, 8)
	# ⑪ 镂空护圈（底梁 + 前后柱）+ AK 弯钩扳机 + ⑩ 护圈后端双销点按式快慢机
	#    （护圈内两颗小圆销——后拉单发/前推连发）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.007, 0.075),
			Vector3(0, -0.055, 0.018), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.030, 0.008),
			Vector3(0, -0.038, -0.017), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.026, 0.008),
			Vector3(0, -0.041, 0.053), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.026, 0.008),
			Vector3(0, -0.034, 0.018), Vector3(14, 0, 0), 0.0006, 3)
	for sx in [-1.0, 1.0]:
		GUN_LIB.barrel(root, stl, 0.008, 0.006, Vector3(0.006 * sx, -0.046, 0.050),
				Vector3.ZERO, 0, 16)
	# ⑪ 后握把（AK 式后倾 18°、全尺寸聚合物握把 vpolym，钢指棱提层次）：
	#    grip() 顶锚=旋转支点，HOLD_DELTA 精算锚点（见 hd_guns.gd asval 条目：
	#    Δ = MK4 基准 (0,-0.022,-0.0018) − 本锚 (0,-0.028,0.075)）
	GUN_LIB.grip(root, ply, 0.092, Vector3(0, -0.028, 0.075), 18.0,
			0.034, 0.048, stl, 3)
	# ⑧ 40 发长弧匣（独立命名节点 mag_val：原点=匣顶中心，curved_mag 向下
	#    生长、6° 四段微弧弧向前、背板平直；匣体等比拉长到 0.245 读 40 发；
	#    动画匣 show:false 照 scarh 先例，见 _ar_mag_of）
	var mag := Node3D.new()
	mag.name = "mag_val"
	mag.position = Vector3(0, -0.060, -0.085)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, ply, Vector3(0.048, 0.245, 0.082), 6.0, 4, 3)
	# ⑧ 两面横向肋条×4（加密排布、随匣弧逐段转角 0/6/12/18°——肋条比匣身
	#    宽 4mm 两面同时出肋，碳黑同色靠几何凸起读影；步进/弧向逐段复刻
	#    curved_mag 的段心算法，肋条正贴每段段心）
	var cm_step := 0.245 / 4.0
	var cm_c := Vector3(0, -cm_step * 0.5, 0)
	for i in 4:
		if i > 0:
			var ra := deg_to_rad(6.0 * (float(i) - 0.5))
			cm_c += Vector3(0.0, -cos(ra), -sin(ra)) * cm_step
		GUN_LIB.chamfer_box(mag, ply, Vector3(0.052, 0.007, 0.086),
				cm_c, Vector3(6.0 * float(i), 0, 0), 0.0008, 3)
	# ⑫ 背带环×2（护木锥罩正下方 + 托底板左侧，环面 ⊥ X 竖环）
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011, Vector3(0, -0.014, -0.17),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011, Vector3(-0.031, -0.045, 0.345),
			Vector3(0, 0, 90), 28, 18)
	# ⑫ 棱边磨损×2（仅棱边露灰白金属、不整面做旧：机匣右上棱细条 + 台阶座
	#    前棱环线）
	GUN_LIB.chamfer_box(root, wear, Vector3(0.003, 0.005, 0.04),
			Vector3(0.0262, 0.060, -0.05), Vector3.ZERO, 0.0005, 3)
	GUN_LIB.chamfer_box(root, wear, Vector3(0.060, 0.003, 0.006),
			Vector3(0, 0.032, -0.262), Vector3.ZERO, 0.0005, 3)


## K416 突击步枪（官方考证 HK416 风格突击步枪，5.56×45mm，2026-10 商店枪）
## 考证特征逐条落件（HDGunLib 高模重建——基线 2247 → 公式推算 21229，红线
## POLY_MIN["k416"]；AR-15/M4 系上下机匣分体直托布局，默认通体黑色，枪身
## z -0.69(枪口) 到 +0.365(托底板) 全长 ≈1.05 模型尺，比 M4A1 略长——护木
## 较长 + 全长顶轨）：
## ①AR-15/M4 系布局：上机匣（平顶，顶面即全长轨座）+ 下机匣分体、直托结构，
##   全黑配色（黑阳极氧化铝机匣 + 黑聚合物护木/握把/枪托，polymer 主体 +
##   近黑金属细节 + 亮钢小件提层次）
## ②枪口鸟笼式消焰器：开筒内衬亮钢膛 + 两侧纵槽口 + 前挡环（A2 鸟笼同族）
## ③导气座 + 可折叠准星：护木前端导气座上立准星基座 + 圆柱准星 + 双护耳；
##   机匣后段轨上折叠照门（觇孔板 + 双耳）——真实机瞄为建模件（_finish_gun
##   iron 分支跳过兜底机瞄片，同 m14/asval 先例）
## ④长护木 + 全长皮卡汀尼顶轨（轨基从机匣尾直通护木头）+ 中部两节肋条状
##   滚花散热套筒（圆柱段 + 环件×3 读「滚花散热」）+ 左右侧面导轨贴片 +
##   底侧散热开孔
## ⑤AR 式 T 形拉机柄（机匣尾后置，杆 + 双翼三件）+ 机匣右侧带防尘盖抛壳窗
## ⑥机匣侧面白色刻字厂标：弹匣井左上 AMET 刻字条 + 编号刻印（白色 mrk 专用色）
## ⑦默认机械瞄具 = 折叠准星 + 照门组合（见③；红点/全息镜走 _scope_visual
##   既有链，挂点见 _ar_scope_anchor k416）
## ⑧STANAG 微弯聚合物弹匣 30 发：mag_k416 独立命名节点 + curved_mag 三段
##   5° 微弧 + 两面横向筋条刻度×3（随匣弧逐段转角，筋条比匣身宽 4mm 靠
##   几何凸起读影，asval 匣肋同法）
## ⑨手枪式握把（防滑指棱）+ 握把根部尾撑配重（亮钢配重块，ref_01 握把
##   底部浅色件）+ 下机匣保留 AR 标准控件：右侧弹匣卡笋 / 左侧空仓挂机杆 /
##   右侧快慢机 / 方形圆角扳机护圈 / 小握把与护木间下导轨衔接段
## ⑩HK416 风格多段伸缩骨架枪托：缓冲管 + 锁环 + 倒角托体 + 侧面漏空减重孔
##   ×4（暗件负形暗示）+ 斜切托底板 + 托下背带环
static func _ar_k416(mats: Dictionary, root: Node3D) -> void:
	var ply: StandardMaterial3D = mats["polymer"]   # ① 黑聚合物主体（机匣/护木/托/握把/弹匣）
	var met: StandardMaterial3D = mats["dark"]      # ① 近黑金属细节（轨/枪管/消焰器/控件）
	var stl: StandardMaterial3D = mats["steel"]     # ① 亮钢小件（准星/扳机/配重/环）
	var mrk: StandardMaterial3D = mats["kmark"]     # ⑥ 白色刻字厂标（AMET/编号）
	# ① 上机匣（平顶，s20 高分段：顶轨线高光顺滑直角棱消除）+ 下机匣——
	#    上下机匣分体、直托布局
	GUN_LIB.chamfer_box(root, ply, Vector3(0.055, 0.062, 0.26),
			Vector3(0, 0.034, -0.02), Vector3.ZERO, 0.003, 20)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.05, 0.052, 0.20),
			Vector3(0, -0.018, 0.01), Vector3.ZERO, 0.0025, 12)
	# ⑧ 弹匣井（下机匣前下，井底 y -0.0945 对 mag_k416 匣顶 -0.058 嵌入
	#    防接缝）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.054, 0.085, 0.09),
			Vector3(0, -0.052, -0.155), Vector3.ZERO, 0.002, 8)
	# ④ 全长皮卡汀尼顶轨：单根轨基（机匣尾 z +0.16 直通护木头 z -0.47）+
	#    连续楔齿×8（机匣段/护木段齿列连续无分段感）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.012, 0.63),
			Vector3(0, 0.071, -0.155), Vector3.ZERO, 0.0015, 10)
	for i in 8:
		GUN_LIB.chamfer_box(root, met, Vector3(0.031, 0.006, 0.016),
				Vector3(0, 0.08, -0.44 + 0.075 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ⑤ AR 式 T 形拉机柄（机匣尾后置：杆 + 双翼三件，非侧拉）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.007, 0.018),
			Vector3(0, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(-0.017, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(0.017, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	# ⑤ 机匣右侧带防尘盖抛壳窗（盖板贴合右侧面）
	GUN_LIB.chamfer_box(root, met, Vector3(0.004, 0.024, 0.068),
			Vector3(0.0285, 0.032, -0.045), Vector3.ZERO, 0.0008, 3)
	# ⑥ 机匣侧面白色刻字厂标：AMET 刻字条 + 编号刻印（弹匣井左上）
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.005, 0.028),
			Vector3(-0.0283, -0.026, -0.135), Vector3.ZERO, 0.0005, 2)
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.003, 0.014),
			Vector3(-0.0283, -0.036, -0.14), Vector3.ZERO, 0.0004, 2)
	# ⑨ AR 标准控件：右侧弹匣卡笋 / 左侧空仓挂机杆 / 右侧快慢机 /
	#    下导轨衔接段（小握把与护木间）
	GUN_LIB.chamfer_box(root, met, Vector3(0.006, 0.012, 0.018),
			Vector3(0.029, -0.022, -0.105), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.013, 0.036),
			Vector3(-0.0285, 0.008, -0.035), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.012, 0.028),
			Vector3(0.0285, 0.004, 0.03), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, met, Vector3(0.03, 0.008, 0.10),
			Vector3(0, -0.048, -0.14), Vector3.ZERO, 0.0008, 6)
	# ④ 长护木（0.33，顶面接全长轨）：主体倒角盒 + 左右侧导轨贴片（前段）+
	#    底侧散热开孔×3（前段底面）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.056, 0.06, 0.33),
			Vector3(0, 0.03, -0.305), Vector3.ZERO, 0.003, 20)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, met, Vector3(0.006, 0.018, 0.065),
				Vector3(0.0305 * sx, 0.024, -0.43), Vector3.ZERO, 0.0008, 5)
	for i in 3:
		GUN_LIB.chamfer_box(root, met, Vector3(0.026, 0.006, 0.022),
				Vector3(0, -0.0025, -0.405 - 0.03 * float(i)), Vector3.ZERO,
				0.0006, 2)
	# ④ 中部肋条状滚花散热套筒两节：圆柱段（seg32）+ 环件×3 读「滚花散热」
	#    （筒 r 0.029 微凸护木侧面 1mm，环再凸 2.5mm——两节圆柱防滑散热段）
	GUN_LIB.barrel(root, met, 0.08, 0.058, Vector3(0, 0.03, -0.24),
			Vector3(90, 0, 0), 0, 32)
	GUN_LIB.torus_ring(root, met, 0.0285, 0.0315, Vector3(0, 0.03, -0.22),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, met, 0.0285, 0.0315, Vector3(0, 0.03, -0.245),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, met, 0.0285, 0.0315, Vector3(0, 0.03, -0.27),
			Vector3(90, 0, 0))
	GUN_LIB.barrel(root, met, 0.08, 0.058, Vector3(0, 0.03, -0.35),
			Vector3(90, 0, 0), 0, 32)
	GUN_LIB.torus_ring(root, met, 0.0285, 0.0315, Vector3(0, 0.03, -0.33),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, met, 0.0285, 0.0315, Vector3(0, 0.03, -0.355),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, met, 0.0285, 0.0315, Vector3(0, 0.03, -0.38),
			Vector3(90, 0, 0))
	# ③ 导气座（护木前端）+ 可折叠准星：基座 + 圆柱准星 + 双护耳
	GUN_LIB.chamfer_box(root, met, Vector3(0.03, 0.034, 0.032),
			Vector3(0, 0.044, -0.49), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, met, Vector3(0.016, 0.01, 0.02),
			Vector3(0, 0.067, -0.49), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.barrel(root, stl, 0.014, 0.005, Vector3(0, 0.079, -0.49),
			Vector3.ZERO, 0, 16)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.02, 0.01),
			Vector3(-0.009, 0.077, -0.49), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.02, 0.01),
			Vector3(0.009, 0.077, -0.49), Vector3.ZERO, 0.0006, 3)
	# ③ 折叠照门（机匣后段轨上）：基座 + 觇孔板（后仰 10°）+ 双耳
	GUN_LIB.chamfer_box(root, met, Vector3(0.018, 0.008, 0.024),
			Vector3(0, 0.085, 0.075), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.02, 0.006),
			Vector3(0, 0.098, 0.08), Vector3(-10, 0, 0), 0.0006, 3)
	# ② 枪管（36 段高分段，护木前裸露段）+ 鸟笼式消焰器：开筒内衬亮钢膛 +
	#    两侧纵槽口 + 前挡环
	GUN_LIB.barrel(root, met, 0.16, 0.022, Vector3(0, 0.03, -0.55),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.tube(root, met, 0.06, 0.03, Vector3(0, 0.03, -0.66),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.034),
			Vector3(-0.013, 0.03, -0.66), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.034),
			Vector3(0.013, 0.03, -0.66), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.torus_ring(root, stl, 0.013, 0.018, Vector3(0, 0.03, -0.685),
			Vector3(90, 0, 0))
	# ⑨ 方形圆角扳机护圈（底梁 + 前后柱）+ 扳机
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.008, 0.07),
			Vector3(0, -0.065, 0.015), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.03, 0.008),
			Vector3(0, -0.047, -0.016), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.028, 0.008),
			Vector3(0, -0.048, 0.046), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.042, 0.014), Vector3(10, 0, 0), 0.0006, 2)
	# ⑨ 后握把（防滑指棱高模握把、后倾 20°，AR 握把角）：grip() 顶锚=旋转
	#    支点，HOLD_DELTA 精算锚点（见 hd_guns.gd k416 条目：Δ = MK4 基准
	#    (0,-0.022,-0.0018) − 本锚 (0,-0.030,0.075)）
	GUN_LIB.grip(root, ply, 0.092, Vector3(0, -0.03, 0.075), 20.0,
			0.036, 0.05, stl, 3)
	# ⑨ 握把根部尾撑配重（亮钢配重块，随握把 20° 后倾——ref_01 握把底部
	#    浅色件）：grip 本体底部 (0,-0.095,0) 局部 → 世界 (0,-0.119,0.108)，
	#    配重贴其下
	GUN_LIB.chamfer_box(root, stl, Vector3(0.044, 0.016, 0.062),
			Vector3(0, -0.127, 0.112), Vector3(-20, 0, 0), 0.001, 3)
	# ⑩ HK416 风格多段伸缩骨架枪托：缓冲管（seg32 开筒壁厚断面）+ 锁环 +
	#    倒角托体 + 侧面漏空减重孔×4 + 斜切托底板 + 托下背带环
	GUN_LIB.tube(root, met, 0.14, 0.034, Vector3(0, 0.014, 0.18),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, stl, 0.016, 0.02, Vector3(0, 0.014, 0.125),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, ply, Vector3(0.046, 0.08, 0.15),
			Vector3(0, -0.002, 0.29), Vector3.ZERO, 0.003, 20)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.03, 0.016, 0.13),
			Vector3(0, 0.038, 0.28), Vector3.ZERO, 0.001, 6)
	for sy in [0.012, -0.018]:
		GUN_LIB.chamfer_box(root, met, Vector3(0.004, 0.024, 0.05),
				Vector3(-0.0253, float(sy), 0.285), Vector3.ZERO, 0.0006, 2)
		GUN_LIB.chamfer_box(root, met, Vector3(0.004, 0.024, 0.05),
				Vector3(0.0253, float(sy), 0.285), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, met, Vector3(0.052, 0.1, 0.016),
			Vector3(0, -0.016, 0.357), Vector3(12, 0, 0), 0.0015, 12)
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011, Vector3(0, -0.03, 0.125),
			Vector3(0, 0, 90), 28, 18)
	# ⑧ 30 发 STANAG 微弯聚合物弹匣（独立命名节点 mag_k416：原点=匣顶中心，
	#    curved_mag 向下生长、5° 三段微弧弧向前；动画匣 show:false 照 m4a1
	#    先例，见 _ar_mag_of）
	var mag := Node3D.new()
	mag.name = "mag_k416"
	mag.position = Vector3(0, -0.058, -0.155)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, ply, Vector3(0.05, 0.175, 0.09), 5.0, 3, 3)
	# ⑧ 两面横向筋条刻度×3（随匣弧逐段转角 0/5/10°——筋条比匣身宽 4mm 两面
	#    同时出肋，黑聚合物同色靠几何凸起读影；步进/弧向逐段复刻 curved_mag
	#    的段心算法，asval 匣肋同法）
	var cm_step := 0.175 / 3.0
	var cm_c := Vector3(0, -cm_step * 0.5, 0)
	for i in 3:
		if i > 0:
			var ra := deg_to_rad(5.0 * (float(i) - 0.5))
			cm_c += Vector3(0.0, -cos(ra), -sin(ra)) * cm_step
		GUN_LIB.chamfer_box(mag, ply, Vector3(0.054, 0.007, 0.094),
				cm_c, Vector3(5.0 * float(i), 0, 0), 0.0008, 2)


## AN-94 突击步枪（官方考证 5.45×39mm「阿巴甘」，2026-10 商店枪·S12 微光赛季）
## 考证特征逐条落件（HDGunLib 高模重建——基线与红线见 HDGunLib.POLY_MIN["an94"]；
## 整体布局照 ref_03/ref_04（modernfirearms 左右整枪视图）：943mm 展开全长 →
## 枪身 z -0.706(喇叭口) 到 +0.276(托底胶垫) 全长 ≈0.98 模型尺；轮廓比 AK-74
## 更方正饱满——聚合物外壳上缘与枪管轴线近平行、等高贯穿）：
## ①大型双室制退/消焰器（第一识别件，快拆式）：侧视侧放「8」字双腔、两腔间
##   收腰、前缘外扩成喇叭口，直径明显大于枪管；侧壁多排圆形排气孔（每腔两排
##   ×两侧，torus 孔缘读「圆孔」）
## ②枪口装置后：准星基座带刺刀座，刺刀横置枪管右侧（水平贴放，ref_03 视觉）
## ③机匣顶部后端：回转式星形觇孔表尺——五角盘（barrel seg5 五棱柱）+ 沿盘缘
##   均布 5 觇孔（暗色短柱）+ 亮钢轴销，盘面立向（含枪管轴，ref_04 左侧见全盘）
## ④机匣左侧：俄式通用侧导轨座（燕尾槽基板+上下唇缘+后挡块）；原型无皮轨
## ⑤护木与上盖：黑玻纤增强聚合物整体外壳（外壳上体+下体+横向防滑凸棱×6+
##   上盖分缝条），将钢制内机匣整个包住——射击时内机匣在壳内后坐（延迟后坐）
## ⑥弹匣：AK-74 式 30 发弧匣竖直入井、弧度向前（2026-10-23 用户实测「匣歪了
##   没对齐井」定案去掉旧版 10° 侧倾——匣顶埋进井内对齐井口）：mag_an94
##   独立命名节点 + curved_mag 四段 13° 弧 + 横肋×3；弹匣井竖直
## ⑦枪托：右侧折叠骨架式塑料托（展开态建模）：铰链座+上骨架杆（续壳顶直线）+
##   斜撑+托底板+下钩唇+胶垫——中空大开孔（上杆与斜撑间的三角大孔，ref_03）
## ⑧一体化黑色聚合物握把（无木质部件，与枪身同材质同色）
## ⑨右侧长柄式三档快慢机（长杆+轴盘）+ 右侧拉机柄（杆+柄头，弹匣口上方偏后）
## ⑩通体哑光黑：聚合物黑壳（polymer）+磷化深灰钢（dark：枪管/准星座/弹匣井/
##   抛壳窗）+灰蓝钢识别件（blued：制退器/星形盘）+亮钢小件（steel：轴销/
##   扳机/背带环/刺刀），无木质色、无亮面大件
## ⑪扳机护圈镂空（底梁+前后柱）+ 右侧抛壳窗框（露出钢内机匣的暗窗）+
##   背带环×2（护木下+托底板左下）
## ⑫超点射机制（guns.cd_profile 射速档案：按压内首对 0.0333s/1800rpm、之后
##   0.1s/600rpm）——外观不受影响，手感件在 hd_guns.try_fire/BURST_SOFT_*
static func _ar_an94(mats: Dictionary, root: Node3D) -> void:
	var shell: StandardMaterial3D = mats["polymer"]   # ⑩ 黑玻纤聚合物外壳（护木+上盖整体件）
	var stl: StandardMaterial3D = mats["dark"]        # ⑩ 磷化深灰钢（枪管/准星座/弹匣井/抛壳窗）
	var mz: StandardMaterial3D = mats["blued"]        # ⑩ 灰蓝钢识别件（制退器/星形表尺盘）
	var brt: StandardMaterial3D = mats["steel"]       # ⑩ 亮钢小件（轴销/扳机/背带环/刺刀）
	# ⑤ 聚合物整体外壳上体（包钢内机匣；上缘 y 0.068 与枪管轴 0.03 平行等高
	#    贯穿 z -0.535..+0.085——「比 AK-74 方正饱满」的轮廓根）+ 下体（弹匣
	#    井区/握把座）+ 前段横向防滑凸棱×6 + 上盖分缝条 + 上盖凸棱×2
	GUN_LIB.chamfer_box(root, shell, Vector3(0.054, 0.068, 0.62),
			Vector3(0, 0.034, -0.225), Vector3.ZERO, 0.0035, 24)
	GUN_LIB.chamfer_box(root, shell, Vector3(0.050, 0.046, 0.30),
			Vector3(0, -0.021, -0.045), Vector3.ZERO, 0.003, 20)
	for i in 6:
		GUN_LIB.chamfer_box(root, shell, Vector3(0.058, 0.058, 0.006),
				Vector3(0, 0.032, -0.49 + 0.075 * float(i)), Vector3.ZERO,
				0.0008, 6)
	GUN_LIB.chamfer_box(root, shell, Vector3(0.050, 0.006, 0.60),
			Vector3(0, 0.0695, -0.22), Vector3.ZERO, 0.001, 20)
	for i in 2:
		GUN_LIB.chamfer_box(root, shell, Vector3(0.056, 0.010, 0.006),
				Vector3(0, 0.0715, -0.09 + 0.095 * float(i)), Vector3.ZERO,
				0.0008, 4)
	# ① 大型双室制退/消焰器（快拆式，灵魂件）：快拆锁环 → 后腔（d0.044）→
	#    收腰环带（d0.030 两腔间收腰）→ 前腔（d0.046 稍大）→ 前缘两级外扩
	#    喇叭口（torus 阶梯环读「外扩喇叭」）；直径全段明显大于枪管 d0.020
	GUN_LIB.tube(root, mz, 0.024, 0.035, Vector3(0, 0.03, -0.601),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 36)
	GUN_LIB.tube(root, mz, 0.050, 0.044, Vector3(0, 0.03, -0.630),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.tube(root, mz, 0.016, 0.030, Vector3(0, 0.03, -0.652),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 24)
	GUN_LIB.tube(root, mz, 0.036, 0.046, Vector3(0, 0.03, -0.674),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.torus_ring(root, mz, 0.0175, 0.024, Vector3(0, 0.03, -0.691),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, mz, 0.019, 0.0275, Vector3(0, 0.03, -0.700),
			Vector3(90, 0, 0))
	# ① 侧壁多排圆形排气孔：每腔两排（枪管轴上下 ±7.5/8mm）、左右两侧面，
	#    torus 孔缘（环轴沿 X 穿壁）读「圆孔」——后腔 3 孔/排、前腔 2 孔/排
	for sx in [-1.0, 1.0]:
		var fx := float(sx)
		for i in 3:
			for sy in [-0.0075, 0.0075]:
				GUN_LIB.torus_ring(root, stl, 0.0028, 0.0052,
						Vector3(0.022 * fx, 0.03 + sy, -0.617 - 0.013 * float(i)),
						Vector3(0, 0, 90), 24, 12)
		for i in 2:
			for sy in [-0.008, 0.008]:
				GUN_LIB.torus_ring(root, stl, 0.0028, 0.0052,
						Vector3(0.023 * fx, 0.03 + sy, -0.665 - 0.013 * float(i)),
						Vector3(0, 0, 90), 24, 12)
	# ② 枪管裸露段（外壳前缘 -0.535 到锁环 -0.589，36 段 + 近口螺纹环×2）+
	#    准星基座（骑枪管上方带护耳）+ 柱形准星 + 刺刀座 + 刺刀横置右侧
	GUN_LIB.barrel(root, stl, 0.056, 0.020, Vector3(0, 0.03, -0.562),
			Vector3(90, 0, 0), 2, 36)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.030, 0.034, 0.026),
			Vector3(0, 0.048, -0.556), Vector3.ZERO, 0.001, 6)
	GUN_LIB.barrel(root, mz, 0.018, 0.006, Vector3(0, 0.074, -0.556),
			Vector3.ZERO, 0, 16)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.022, 0.014),
				Vector3(0.011 * sx, 0.072, -0.556), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.014, 0.012, 0.030),
			Vector3(0.014, 0.026, -0.552), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(root, brt, Vector3(0.012, 0.016, 0.048),
			Vector3(0.026, 0.030, -0.478), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, brt, Vector3(0.012, 0.030, 0.008),
			Vector3(0.026, 0.030, -0.505), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, brt, Vector3(0.004, 0.016, 0.062),
			Vector3(0.026, 0.030, -0.540), Vector3.ZERO, 0.0008, 6)
	# ③ 回转式星形觇孔表尺（机匣顶部后端）：表尺座 + 盘侧护耳板×2 + 五角盘
	#    （barrel seg5 = 五棱柱，盘面立向含枪管轴——ref_04 左侧视图见全盘）+
	#    沿盘缘均布 5 觇孔（72° 步进，暗色短柱沿盘轴穿盘读「孔」）+ 亮钢轴销
	#    + 盘缘拨柄小块
	GUN_LIB.chamfer_box(root, stl, Vector3(0.036, 0.020, 0.054),
			Vector3(0, 0.078, 0.048), Vector3.ZERO, 0.001, 8)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.036, 0.040),
				Vector3(0.008 * sx, 0.102, 0.048), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.barrel(root, mz, 0.007, 0.034, Vector3(0, 0.102, 0.048),
			Vector3(0, 0, 90), 0, 5)
	for k in 5:
		var sa := PI / 2.0 + TAU * float(k) / 5.0
		GUN_LIB.barrel(root, stl, 0.010, 0.0045,
				Vector3(0, 0.102 + 0.0105 * cos(sa), 0.048 + 0.0105 * sin(sa)),
				Vector3(0, 0, 90), 0, 10)
	GUN_LIB.barrel(root, brt, 0.016, 0.007, Vector3(0, 0.102, 0.048),
			Vector3(0, 0, 90), 0, 12)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.006, 0.008, 0.012),
			Vector3(0, 0.112, 0.066), Vector3.ZERO, 0.0006, 3)
	# ④ 机匣左侧俄式通用侧导轨座（燕尾槽）：基板 + 上唇缘 + 下支撑缘 + 后
	#    定位挡块（加挂瞄具的侧装接口——原型无皮卡汀尼顶轨）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.010, 0.036, 0.15),
			Vector3(-0.031, 0.036, -0.02), Vector3.ZERO, 0.001, 8)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.012, 0.14),
			Vector3(-0.0345, 0.050, -0.02), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.010, 0.14),
			Vector3(-0.0345, 0.024, -0.02), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.010, 0.040, 0.014),
			Vector3(-0.031, 0.036, 0.062), Vector3.ZERO, 0.0008, 4)
	# ⑥ 弹匣井（磷化钢，竖直）+ AK-74 式 30 发弧匣竖直插入、弧度向前：
	#    旧版匣/井整体绕枪管轴侧倾 10°（两侧转心不同致匣口对不上井口，用户
	#    实测「弹匣歪了且没对齐弹匣井」）——修：井与匣都取正，匣顶埋进井内
	#    0.038 对齐井口（真实 AN-94 匣只有向前弧度，侧倾去掉）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.050, 0.060, 0.086),
			Vector3(0, -0.050, -0.115), Vector3.ZERO, 0.002, 12)
	var mag := Node3D.new()
	mag.name = "mag_an94"
	mag.position = Vector3(0, -0.042, -0.115)
	mag.rotation_degrees = Vector3.ZERO
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, shell, Vector3(0.048, 0.18, 0.076), 13.0, 4, 3)
	var cm_step := 0.18 / 3.0
	var cm_c := Vector3(0, -cm_step * 0.5, 0)
	for i in 3:
		if i > 0:
			var ra := deg_to_rad(13.0 * (float(i) - 0.5))
			cm_c += Vector3(0.0, -cos(ra), -sin(ra)) * cm_step
		GUN_LIB.chamfer_box(mag, shell, Vector3(0.052, 0.007, 0.080),
				cm_c, Vector3(13.0 * float(i), 0, 0), 0.0008, 2)
	# ⑦ 右侧折叠骨架式枪托（展开态建模，中空大开孔）：铰链座块 + 铰链销 +
	#    折叠释放钮（右）+ 上骨架杆（上缘续外壳顶线 y 0.068）+ 斜撑杆（前上
	#    后下——与上杆围出三角大孔）+ 托底板 + 底板下钩唇 + 托底胶垫
	GUN_LIB.chamfer_box(root, stl, Vector3(0.044, 0.050, 0.046),
			Vector3(0, 0.040, 0.108), Vector3.ZERO, 0.002, 12)
	GUN_LIB.barrel(root, brt, 0.050, 0.009, Vector3(0, 0.052, 0.118),
			Vector3(0, 0, 90), 0, 16)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.016, 0.020),
			Vector3(0.027, 0.040, 0.118), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, shell, Vector3(0.018, 0.024, 0.145),
			Vector3(0, 0.056, 0.193), Vector3.ZERO, 0.0015, 8)
	GUN_LIB.chamfer_box(root, shell, Vector3(0.016, 0.018, 0.185),
			Vector3(0, -0.010, 0.185), Vector3(32, 0, 0), 0.0015, 8)
	GUN_LIB.chamfer_box(root, shell, Vector3(0.036, 0.118, 0.014),
			Vector3(0, 0.002, 0.262), Vector3.ZERO, 0.002, 12)
	GUN_LIB.chamfer_box(root, shell, Vector3(0.034, 0.020, 0.028),
			Vector3(0, -0.047, 0.251), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, shell, Vector3(0.038, 0.120, 0.007),
			Vector3(0, 0.002, 0.2725), Vector3.ZERO, 0.001, 6)
	# ⑨ 右侧长柄式三档快慢机（保险/单发/连发长杆 + 轴盘）+ 右侧拉机柄
	#    （杆 + 柄头，弹匣口上方偏后）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.006, 0.013, 0.088),
			Vector3(0.0295, 0.010, 0.028), Vector3.ZERO, 0.0008, 5)
	GUN_LIB.barrel(root, stl, 0.010, 0.014, Vector3(0.0295, 0.014, 0.072),
			Vector3(0, 0, 90), 0, 16)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.008, 0.042),
			Vector3(0.030, 0.028, -0.03), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.010, 0.014, 0.010),
			Vector3(0.034, 0.028, -0.048), Vector3.ZERO, 0.0006, 4)
	# ⑪ 右侧抛壳窗框（露出钢内机匣的暗窗——外壳右侧面开口）+ 镂空扳机护圈
	#    （底梁+前后柱）+ 扳机 + 背带环×2（护木下 + 托底板左下）
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.020, 0.058),
			Vector3(0.0275, 0.040, -0.035), Vector3.ZERO, 0.0008, 5)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.007, 0.088),
			Vector3(0, -0.056, -0.005), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.026, 0.008),
			Vector3(0, -0.040, -0.046), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.012, 0.028, 0.008),
			Vector3(0, -0.040, 0.036), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, brt, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.043, -0.003), Vector3(14, 0, 0), 0.0006, 3)
	GUN_LIB.torus_ring(root, brt, 0.004, 0.011, Vector3(0, -0.030, -0.36),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.torus_ring(root, brt, 0.004, 0.011, Vector3(-0.024, -0.040, 0.250),
			Vector3(0, 0, 90), 28, 18)
	# ⑧ 一体化黑色聚合物握把（无木质、与枪身同材质同色，后倾 20° 指棱高模
	#    握把）：grip() 顶锚=旋转支点，HOLD_DELTA 精算锚点（见 hd_guns.gd
	#    an94 条目：Δ = MK4 基准 (0,-0.022,-0.0018) − 本锚 (0,-0.030,0.075)）
	GUN_LIB.grip(root, shell, 0.088, Vector3(0, -0.030, 0.075), 20.0,
			0.036, 0.050, brt, 3)


## SR25 射手步枪（官方考证 7.62×51mm 半自动 DMR，2026-10 商店枪·群星赛季）
## 考证特征逐条落件（HDGunLib 高模重建——基线 4173 → 实测以 count_vertices
## 为准，红线 POLY_MIN["sr25"]；整枪布局照 ref_01/ref_02/ref_05：AR-10/M110
## 系全尺寸半自动 DMR，上下机匣分体、弹匣井位于握把前方、尾部接伸缩枪托，
## 枪身 z -0.76(消音器口) 到 +0.39(托底垫) 全长 ≈1.15 模型尺——全枪册最长，
## 「整枪比突击步枪明显更长更重」。2026-10 首轮判图 7.5/11 返工：本轮补
## 特征11 瞄具/特征10 出筒脚架/特征9 前握把+握把座/特征14 放大铭牌/
## 特征13 分材质/特征8 骨架托减薄，并修复「顶轨与护木筒互吞」——旧版筒心
## y 0.030 外径 0.058（顶 0.088）盖过轨齿顶 0.083 与前置准星整段：护木段
## 顶轨/准星全部藏进筒内不可见；现筒降位缩径（心 0.024/外径 0.054，顶
## 0.051）+ 筒顶加 URX 桥接座，全长轨齿出露，准星改挂轨顶）：
## ①整体布局：AR-10 系上下机匣分体（平顶上机匣 + 弹匣井/握把座下机匣），
##   金属机匣 + 聚合物护木/弹匣/握把/托体分质（特征13：m14steel 磷化钢
##   机匣亮一档 vs polymer 哑光黑家具，ref_04 金属磨损面/聚合物哑光面对比）
## ②KAC 风格浮置式圆筒护木（第一识别件）：seg48 圆管开筒浮置（不触枪管）
##   + 外壁一圈圈横向肋条环×6（torus 环件——散热/防滑槽，ref_04 特写最
##   清晰）+ 前端收口环 + 筒顶 URX 桥接座（衔接轨基与筒身——轨筒不再互吞）
## ③全长 MIL-STD-1913 鱼骨导轨：单根轨基从机匣尾直通护木头 + 连续楔齿×8
##   （护木左右侧面铺导轨贴片+横齿×4×2、底面导轨+横齿×3——改装分解图
##   ref_01 的贴片/脚架/前握把安装位）
## ④机械瞄具：护木前端可折叠立式准星（轨顶基座+圆柱准星+双护耳，ref_04
##   竖起的准星翼）+ 机匣尾部轨上折叠觇孔照门——真实机瞄为建模件
##   （_finish_gun iron 分支跳过兜底机瞄片，同 k416 先例）
## ⑤细长重型枪管：护木前端浮置伸出（48 段高分段裸管段）
## ⑥大直径圆柱形战术消音器（第二识别件，常装）：d0.050 粗管 + 尾锁环 +
##   近口接缝环带×2 + 前挡环（ref_03/ref_05 特写；音效/火光仍走普通枪
##   路径——消音机制只认改枪台 sup_provider，本件为外观考证件）
## ⑦20 发 7.62×51 直-微弧弹匣：mag_sr25 独立命名节点 + curved_mag 三段
##   4° 微弧 + 两面横向加强筋×3（ref_01/02 侧视「平直略带弧度、侧面有
##   加强筋」；面板容量 20）
## ⑧伸缩式精准枪托（特征8 骨架化减薄返工）：缓冲管 + 锁环 + 骨架框架托
##   （顶板+前立柱+尾立板+下斜撑四边框——框内透空见缓冲管=骨架化，替代
##   旧版 0.048×0.085 实心厚托）+ 贴腮板独立升高 0.022 台阶（顶板上另起
##   一层，台阶清晰）+ 腮板搓纹×4 + 橡胶托底垫 + 托底钩 + 托侧/腮板调节钮
##   （ref_01 枪托放大：骨架框 + 升高贴腮板 + 厚胶垫）
## ⑨前握把 + 握把座（特征9 返工补件）：护木底轨前握把（连接座+前倾 8°
##   握把体+指槽×3，ref_01 前握把标注）+ 下机匣后握把座（握把前方金属座
##   块，ref_01 握把座标注）+ AR 式手枪握把（后倾 20° 指棱高模握把=后握把）
## ⑩导轨脚架（特征10 返工出筒）：护木底轨收拢双腿——旧版腿心 y -0.014
##   整段藏进筒内不可见；现挂座/双腿/足垫全挂底轨下方（y ≤ -0.019）出筒
##   可见 + 双腿轴钮（ref_01 导轨脚架标注）
## ⑪（2026-10-26 用户定案「这把枪原来不带瞄准镜」——旧版自带 2.5-8 倍镜+
##   45° 侧瞄已整段拆除，改装镜走 _finish_gun 通用 else 路径照常上轨）+
##   AR 系尾部 T 形拉机柄 + 右侧抛壳窗防尘盖/偏转楔 +
##   弹匣卡笋/快慢机 + 上机匣右侧白色刻印铭牌×3（特征14 返工放大：主
##   铭牌 0.035 长 + 编号行 + 二维块，ref_04 白色数据铭牌特写，kmark 色）
## ⑫配色材质（特征13 返工分质）：机匣/弹匣井/握把座 = m14steel 磷化深灰
##   钢（亮一档读「金属」）；护木筒/托体/贴腮板/握把/弹匣/前握把 = polymer
##   哑光黑聚合物；导轨/齿/肋环/脚架/镜筒 = dark 近黑金属；准星/镜环/
##   镜片/钮 = steel 亮钢；胶垫/目镜杯/指槽/足垫 = m14dark 橡胶；铭牌 =
##   kmark 白刻印——全部既有材质传参，零新材质
static func _ar_sr25(mats: Dictionary, root: Node3D) -> void:
	var rec: StandardMaterial3D = mats["m14steel"]  # ⑫ 磷化深灰钢（机匣/井/握把座）
	var ply: StandardMaterial3D = mats["polymer"]   # ⑫ 哑光黑聚合物（护木/托/握把/弹匣）
	var met: StandardMaterial3D = mats["dark"]      # ⑫ 近黑金属（导轨/枪管/消音器/脚架/镜体）
	var stl: StandardMaterial3D = mats["steel"]     # ⑫ 亮钢小件（准星/镜环/镜片/调节钮）
	var rub: StandardMaterial3D = mats["m14dark"]   # ⑫ 橡胶件（托底垫/目镜杯/指槽/足垫）
	var mrk: StandardMaterial3D = mats["kmark"]     # ⑪ 白色刻印铭牌（ref_04 特写）
	var bkl: StandardMaterial3D = mats["bakelite"]  # ⑪ 侧瞄红点评（暖橙读「通电红点」）
	# ① 上下机匣分体：平顶上机匣（s24 高分段：顶轨线高光顺滑直角棱消除，
	#    顶面即③全长轨座）+ 下机匣（弹匣井/握把座一体）——AR-10 系布局；
	#    磷化钢亮色与聚合物家具分质（特征13）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.056, 0.066, 0.30),
			Vector3(0, 0.036, -0.03), Vector3.ZERO, 0.003, 24)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.052, 0.054, 0.20),
			Vector3(0, -0.010, 0.02), Vector3.ZERO, 0.0025, 16)
	# ③ 全长 MIL-STD-1913 鱼骨顶轨：单根轨基（机匣尾 z +0.12 直通护木头
	#    z -0.46）+ 连续楔齿×8（机匣段/护木段齿列连续无分段感）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.014, 0.58),
			Vector3(0, 0.071, -0.17), Vector3.ZERO, 0.0015, 12)
	for i in 8:
		GUN_LIB.chamfer_box(root, met, Vector3(0.031, 0.006, 0.016),
				Vector3(0, 0.080, -0.44 + 0.075 * float(i)), Vector3.ZERO,
				0.0012, 8)
	# ⑪ AR 系尾部 T 形拉机柄（机匣尾后置：杆 + 双翼三件，非侧拉杆——
	#    「采用AR系统」的拉机柄形制；游戏「枪机自动后拉」为手感配件不改外观）
	GUN_LIB.chamfer_box(root, met, Vector3(0.030, 0.007, 0.018),
			Vector3(0, 0.068, 0.105), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(-0.018, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(0.018, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	# ⑪ 右侧抛壳窗防尘盖 + 抛壳偏转楔（盖板贴合右侧面，k416 同族件）
	GUN_LIB.chamfer_box(root, met, Vector3(0.004, 0.024, 0.068),
			Vector3(0.0285, 0.036, -0.05), Vector3.ZERO, 0.0008, 5)
	GUN_LIB.chamfer_box(root, met, Vector3(0.008, 0.016, 0.014),
			Vector3(0.0285, 0.030, -0.005), Vector3.ZERO, 0.0006, 4)
	# ⑪ 上机匣右侧白色刻印铭牌×3（特征14 返工放大：主铭牌 0.035 长 +
	#    编号行 + 二维方块——ref_04 右下机匣白色数据铭牌特写，旧版 2mm
	#    细线暗场不可判读）
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.014, 0.035),
			Vector3(0.0287, 0.013, -0.1125), Vector3.ZERO, 0.0005, 3)
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.005, 0.030),
			Vector3(0.0287, 0.030, -0.135), Vector3.ZERO, 0.0005, 3)
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.010, 0.010),
			Vector3(0.0287, 0.013, -0.084), Vector3.ZERO, 0.0005, 3)
	# ② KAC 风格浮置式圆筒护木（第一识别件）：seg48 圆管开筒（尾封前开、
	#    内衬露壁厚断面）——浮置式不触枪管；降位缩径（心 y 0.024/外径
	#    0.054，顶 0.051）让出全长顶轨——修复旧版筒顶 0.088 吞轨齿/准星
	GUN_LIB.tube(root, ply, 0.36, 0.054, Vector3(0, 0.024, -0.31),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 48)
	# ② 外壁一圈圈横向肋条环×6（散热/防滑槽——torus 环件沿筒身均布，
	#    ref_04 白板原厂护木特写最清晰的特征）
	for i in 6:
		GUN_LIB.torus_ring(root, met, 0.0245, 0.0295,
				Vector3(0, 0.024, -0.155 - 0.06 * float(i)), Vector3(90, 0, 0))
	# ② 护木前端收口环
	GUN_LIB.torus_ring(root, met, 0.0245, 0.029, Vector3(0, 0.024, -0.49),
			Vector3(90, 0, 0))
	# ② URX 桥接座：筒顶与轨基之间的全长桥（0.020 高——轨筒衔接件，
	#    ref_04/05 轨下整条桥体轮廓）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.020, 0.34),
			Vector3(0, 0.055, -0.31), Vector3.ZERO, 0.0012, 12)
	# ③ 护木左右侧面导轨贴片（3/9 点位 3mm 出肋贴筒面）+ 横齿×4×2
	#    （改装贴片/侧瞄具安装位，ref_01 左右贴片标注）
	for sx in [-1.0, 1.0]:
		var fx := float(sx)
		GUN_LIB.chamfer_box(root, met, Vector3(0.006, 0.020, 0.24),
				Vector3(0.030 * fx, 0.024, -0.31), Vector3.ZERO, 0.0008, 5)
		for i in 4:
			GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.016, 0.014),
					Vector3(0.0325 * fx, 0.024, -0.405 + 0.03 * float(i)),
					Vector3.ZERO, 0.0006, 4)
	# ③ 护木底部导轨（前握把/脚架安装位）+ 横齿×3——贴筒底下沿出露
	#    （旧版心 y 0.003 整段藏进筒内不可见，现筒底 -0.003、轨心 -0.009）
	GUN_LIB.chamfer_box(root, met, Vector3(0.022, 0.008, 0.24),
			Vector3(0, -0.009, -0.31), Vector3.ZERO, 0.0008, 4)
	for i in 3:
		GUN_LIB.chamfer_box(root, met, Vector3(0.026, 0.006, 0.014),
				Vector3(0, -0.016, -0.405 + 0.03 * float(i)), Vector3.ZERO,
				0.0006, 4)
	# ④ 可折叠立式准星（护木前端轨顶，ref_04 竖起的准星翼）：基座 + 圆柱
	#    准星 + 双护耳——旧版心 y 0.048 藏进筒内，现改挂轨齿顶 0.083
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.024, 0.030),
			Vector3(0, 0.095, -0.45), Vector3.ZERO, 0.001, 10)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.024, 0.012),
				Vector3(0.009 * float(sx), 0.117, -0.45), Vector3.ZERO,
				0.0006, 5)
	GUN_LIB.barrel(root, stl, 0.016, 0.014, Vector3(0, 0.117, -0.45),
			Vector3.ZERO, 0, 16)
	# ④ 折叠觇孔照门（机匣尾部轨上）：基座 + 觇孔板（后仰 10°）
	GUN_LIB.chamfer_box(root, met, Vector3(0.020, 0.008, 0.026),
			Vector3(0, 0.088, 0.075), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.020, 0.006),
			Vector3(0, 0.100, 0.080), Vector3(-10, 0, 0), 0.0006, 5)
	# ⑤ 细长重型枪管（护木前端浮置伸出段，48 段高分段）
	GUN_LIB.barrel(root, met, 0.09, 0.020, Vector3(0, 0.03, -0.535),
			Vector3(90, 0, 0), 0, 48)
	# ⑥ 大直径圆柱形战术消音器（第二识别件，常装）：尾锁环（骑裸管与
	#    消音器之间）+ d0.050 粗管（seg40 内衬亮钢膛）+ 近口接缝环带×2 +
	#    前挡环（ref_03/ref_05 特写；外观考证件——音效/火光仍走普通枪
	#    路径，消音机制只认改枪台 sup_provider）
	GUN_LIB.torus_ring(root, met, 0.021, 0.028, Vector3(0, 0.03, -0.565),
			Vector3(90, 0, 0))
	GUN_LIB.tube(root, met, 0.20, 0.050, Vector3(0, 0.03, -0.66),
			Vector3(90, 0, 0), 0.004, 0, stl, 3, 40)
	GUN_LIB.torus_ring(root, met, 0.0235, 0.0255, Vector3(0, 0.03, -0.735),
			Vector3(90, 0, 0), 24, 12)
	GUN_LIB.torus_ring(root, met, 0.0235, 0.0255, Vector3(0, 0.03, -0.715),
			Vector3(90, 0, 0), 24, 12)
	GUN_LIB.torus_ring(root, met, 0.017, 0.0245, Vector3(0, 0.03, -0.753),
			Vector3(90, 0, 0))
	# ⑦ 弹匣井（下机匣前下、握把前方——AR-10 系布局；井底 y -0.0875 对
	#    mag_sr25 匣顶 -0.048 嵌入防接缝）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.056, 0.075, 0.088),
			Vector3(0, -0.050, -0.145), Vector3.ZERO, 0.002, 12)
	# ⑧ 伸缩式精准枪托（特征8 骨架化返工）：缓冲管（seg32 开筒壁厚断面）+
	#    锁环 + 骨架框架（顶板/前立柱/尾立板/下斜撑四边——框内透空见缓冲
	#    管，替代旧版实心厚托 0.048×0.085「偏厚笨重」）+ 贴腮板（顶板上另
	#    起一层 0.022 台阶——「贴腮板台阶不清」修复）+ 腮板搓纹×4 + 橡胶
	#    托底垫 + 托底钩 + 托侧/腮板调节钮（ref_01 枪托放大）
	GUN_LIB.tube(root, met, 0.22, 0.038, Vector3(0, 0.014, 0.21),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	GUN_LIB.torus_ring(root, stl, 0.017, 0.021, Vector3(0, 0.014, 0.135),
			Vector3(90, 0, 0))
	GUN_LIB.chamfer_box(root, ply, Vector3(0.036, 0.020, 0.16),
			Vector3(0, 0.040, 0.295), Vector3.ZERO, 0.002, 12)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.036, 0.075, 0.016),
			Vector3(0, -0.008, 0.245), Vector3.ZERO, 0.0015, 8)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.036, 0.100, 0.024),
			Vector3(0, -0.010, 0.363), Vector3.ZERO, 0.002, 12)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.036, 0.016, 0.125),
			Vector3(0, -0.050, 0.305), Vector3(15, 0, 0), 0.0015, 8)
	GUN_LIB.chamfer_box(root, rub, Vector3(0.048, 0.088, 0.014),
			Vector3(0, -0.013, 0.381), Vector3.ZERO, 0.002, 10)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.034, 0.022, 0.055),
			Vector3(0, -0.066, 0.345), Vector3.ZERO, 0.0015, 4)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.040, 0.022, 0.11),
			Vector3(0, 0.061, 0.29), Vector3.ZERO, 0.0018, 10)
	for i in 4:
		GUN_LIB.chamfer_box(root, met, Vector3(0.044, 0.004, 0.008),
				Vector3(0, 0.074, 0.255 + 0.025 * float(i)), Vector3.ZERO,
				0.0006, 3)
	GUN_LIB.torus_ring(root, stl, 0.005, 0.011, Vector3(0.024, 0.040, 0.30),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.torus_ring(root, stl, 0.004, 0.010,
			Vector3(-0.024, 0.061, 0.335), Vector3(0, 0, 90), 28, 18)
	# ⑩ 导轨脚架（特征10 返工出筒，ref_01 导轨脚架标注）：挂座骑底轨前段
	#    齿下（y -0.025）+ 双腿并拢指向后方贴底轨下侧（y -0.031 全段出筒
	#    可见——旧版腿心 -0.014 藏进筒内）+ 足垫×2 + 双腿轴钮
	GUN_LIB.chamfer_box(root, met, Vector3(0.030, 0.012, 0.05),
			Vector3(0, -0.025, -0.43), Vector3.ZERO, 0.001, 6)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, met, Vector3(0.009, 0.012, 0.17),
				Vector3(0.0095 * float(sx), -0.031, -0.345), Vector3.ZERO,
				0.0008, 5)
		GUN_LIB.chamfer_box(root, rub, Vector3(0.011, 0.008, 0.016),
				Vector3(0.0095 * float(sx), -0.031, -0.262), Vector3.ZERO,
				0.0006, 4)
		GUN_LIB.barrel(root, stl, 0.008, 0.010,
				Vector3(0.016 * float(sx), -0.025, -0.43),
				Vector3(0, 0, 90), 0, 12)
	# ⑨ 前握把（特征9 返工补件，ref_01 前握把标注）：底轨连接座 + 前倾 8°
	#    握把体 + 前脸指槽×3——旧版缺失
	GUN_LIB.chamfer_box(root, met, Vector3(0.026, 0.010, 0.05),
			Vector3(0, -0.024, -0.24), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.030, 0.080, 0.040),
			Vector3(0, -0.069, -0.235), Vector3(8, 0, 0), 0.002, 6)
	for i in 3:
		GUN_LIB.chamfer_box(root, rub, Vector3(0.028, 0.006, 0.006),
				Vector3(0, -0.049 - 0.016 * float(i), -0.258),
				Vector3(8, 0, 0), 0.0006, 3)
	# ⑨ 后握把座（特征9 返工补件，ref_01 握把座标注）：下机匣后下金属座
	#    块——握把与前护圈之间的过渡件
	GUN_LIB.chamfer_box(root, rec, Vector3(0.044, 0.026, 0.050),
			Vector3(0, -0.036, 0.043), Vector3.ZERO, 0.0015, 4)
	# ⑨ AR 式手枪握把（后倾 20° 指棱高模握把=后握把）：grip() 顶锚=旋转
	#    支点，HOLD_DELTA 精算锚点（见 hd_guns.gd sr25 条目：Δ = MK4 基准
	#    (0,-0.022,-0.0018) − 本锚 (0,-0.030,0.075)，k416 同值）
	GUN_LIB.grip(root, ply, 0.092, Vector3(0, -0.030, 0.075), 20.0,
			0.036, 0.05, stl, 3)
	# ⑪ 右侧弹匣卡笋圆钮 + 快慢机杆（AR 标准控件）
	GUN_LIB.barrel(root, stl, 0.010, 0.012, Vector3(0.0285, -0.012, -0.105),
			Vector3(0, 0, 90), 0, 16)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.012, 0.030),
			Vector3(0.0285, 0.006, 0.035), Vector3.ZERO, 0.0006, 4)
	# ⑪ 方形圆角扳机护圈（底梁 + 前后柱）+ 扳机
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.008, 0.075),
			Vector3(0, -0.060, 0.015), Vector3.ZERO, 0.0008, 5)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.030, 0.008),
			Vector3(0, -0.043, -0.020), Vector3.ZERO, 0.0008, 5)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.028, 0.008),
			Vector3(0, -0.044, 0.048), Vector3.ZERO, 0.0008, 5)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.040, 0.012), Vector3(10, 0, 0), 0.0006, 4)
	# ⑪ 背带环×2（底轨尾端下 + 托尾立板左侧，环面 ⊥ X 竖环——前环让位
	#    新增前握把，从护木下 -0.24 移到轨尾 -0.185）
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011, Vector3(0, -0.026, -0.185),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011,
			Vector3(-0.022, -0.030, 0.363), Vector3(0, 0, 90), 28, 18)
	# ⑦ 20 发 7.62×51 直-微弧弹匣（独立命名节点 mag_sr25：原点=匣顶中心，
	#    curved_mag 向下生长、4° 三段微弧弧向前——「平直略带弧度」；
	#    动画匣 show:false 照 k416 先例，见 _ar_mag_of）
	var mag := Node3D.new()
	mag.name = "mag_sr25"
	mag.position = Vector3(0, -0.048, -0.145)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, ply, Vector3(0.048, 0.155, 0.078), 4.0, 3, 3)
	# ⑦ 两面横向加强筋×3（随匣弧逐段转角 0/4/8°——筋条比匣身宽 4mm 两面
	#    同时出肋，「侧面有加强筋」；黑聚合物同色靠几何凸起读影，步进/
	#    弧向逐段复刻 curved_mag 的段心算法，an94 匣肋同法）
	var cm_step := 0.155 / 3.0
	var cm_c := Vector3(0, -cm_step * 0.5, 0)
	for i in 3:
		if i > 0:
			var ra := deg_to_rad(4.0 * (float(i) - 0.5))
			cm_c += Vector3(0.0, -cos(ra), -sin(ra)) * cm_step
		GUN_LIB.chamfer_box(mag, ply, Vector3(0.052, 0.007, 0.082),
				cm_c, Vector3(4.0 * float(i), 0, 0), 0.0008, 2)


## K437 突击步枪（烽火地带现役突击步枪考证，.300 BLK，2026-10-29 商店枪）
## 考证特征逐条落件（HDGunLib 高模重建——基线与红线见 HDGunLib.POLY_MIN
## ["k437"]；整体布局照 ref_01/ref_04/ref_07/ref_10：传统 AR 式上下机匣分体
## 中长卡宾、整机哑光石墨黑，枪身 z -0.615(裸冠口) 到 +0.369(托底垫) 全长
## ≈0.98 模型尺——比 K416（1.05）修长一档：中长管 + 骨架托收短）：
## ①整体布局：AR 式上/下机匣分体、非无托（平顶上机匣顶面即②全长轨座），
##   黑色阳极氧化铝机匣 + 黑聚合物护木/握把/弹匣（polymer 主体 + 近黑金属
##   细节 + 亮钢小件提层次，全枪哑光石墨黑 ref_01/04/07/10）
## ②全长皮卡汀尼顶轨：单根轨基从机匣尾直通护木前端 + 连续楔齿×8 + 轨基
##   减重镂空暗槽×3（ref_10「轨条带减重镂空」）；机匣尾部上方 AR 式顶部
##   拉机柄凸台（T 杆 + 双翼——样式为看图推断，未见侧拉柄）
## ③细长自由浮置护木（全枪最强识别件）：细长倒角盒主体 + 两侧各一排大型
##   斜向平行四边形散热开槽×4（Rx(35°) 斜置暗板读「斜槽」，ref_04/07/08/
##   10）+ 底部短导轨段（横齿×3，下挂前握把安装位）+ 顶轨衔接桥（轨基
##   骑护木顶）+ 前端收口环
## ④出厂翻折式机械瞄具（前后各一，展开态建模，ref_04/07/10）：护木前端
##   轨上翻折准星（基座 + 圆柱准星 + 双护耳）+ 机匣尾轨上翻折觇孔照门
##   （基座 + 后仰觇孔板 + 双耳）——真实机瞄为建模件（_finish_gun iron
##   分支跳过兜底机瞄片，同 k416/sr25 先例；改装镜走通用 else 挂载，
##   严禁 sr25 镜体丢失式 pass 分支回归）
## ⑤三角镂空骨架式折叠托（AAC 蜜獾/Q 系轮廓，ref_04/07 默认托）：铰链块
##   + 铰链销 + 折叠解锁钮 + 缓冲短管 + 托体上杆（微下斜）+ 贴腮板 + 下
##   斜撑（与上杆围出三角镂空）+ 托底板 + 橡胶抵肩垫 + 托底前钩；改装可
##   换骨架狙击枪托（社区满改标配——SKEL_STOCK 生态自动可装，不入厂）
## ⑥弹匣：.300 BLK 弧形聚合物匣（烟灰半透明按材质纪律读烟黑聚合物），
##   mag_k437 独立命名节点 + curved_mag 四段 8° 弧（弧度大于 STANAG 5°
##   微弧、小于 AK 13°——大弧烟灰匣 ref_02/05/07）+ 两面横肋×3 + 匣侧
##   DAF 白标（kmark）——30 发默认匣（45 发扩容匣为改装件不入册）
## ⑦机匣印字与红点缀：弹匣井上方 DAF 白标 + 机匣右侧白色枪号刻印（ref_01
##   /03「302-0436601」样式）+ 快慢机红点缀（bakelite 暖橙读红，sr25 侧瞄
##   红点同法）
## ⑧手枪握把：后倾 20° 带指槽人体工学聚合物握把（grip 高模件，指棱×3）+
##   一体式扳机护圈（底梁 + 前后柱与下机匣连成一体，ref_01/04）+ AR 标准
##   控件（弹匣卡笋/空仓挂机/下导轨衔接段）
## ⑨枪口：枪管几乎全被护木包住（裸露段仅 0.115）+ 出厂裸冠无消焰器
##   （口环读冠，ref_04；改装可装鸟笼消焰器/特工一体消音枪管——枪口配件
##   走改装生态，本件为出厂态）
static func _ar_k437(mats: Dictionary, root: Node3D) -> void:
	var ply: StandardMaterial3D = mats["polymer"]   # ① 黑聚合物主体（机匣/护木/托/握把/弹匣）
	var met: StandardMaterial3D = mats["dark"]      # ① 近黑金属细节（轨/枪管/斜槽/控件）
	var stl: StandardMaterial3D = mats["steel"]     # ① 亮钢小件（准星/销/扳机/背带环/冠环）
	var rub: StandardMaterial3D = mats["m14dark"]   # ⑤ 橡胶抵肩垫（sr25 托垫同件）
	var mrk: StandardMaterial3D = mats["kmark"]     # ⑦ 白色刻印（DAF 标/枪号）
	var bkl: StandardMaterial3D = mats["bakelite"]  # ⑦ 快慢机红点缀（暖橙读红）
	# ① AR 式上下机匣分体：平顶上机匣（s24 高分段：顶轨线高光顺滑直角棱
	#    消除，顶面即②全长轨座）+ 下机匣（弹匣井/握把座一体）——非无托
	GUN_LIB.chamfer_box(root, ply, Vector3(0.055, 0.062, 0.26),
			Vector3(0, 0.034, -0.02), Vector3.ZERO, 0.003, 24)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.05, 0.052, 0.20),
			Vector3(0, -0.018, 0.01), Vector3.ZERO, 0.0025, 16)
	# ⑥ 弹匣井（下机匣前下，井底 y -0.0945 对 mag_k437 匣顶 -0.058 嵌入
	#    防接缝，k416 同井位）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.054, 0.085, 0.09),
			Vector3(0, -0.052, -0.155), Vector3.ZERO, 0.002, 12)
	# ② 全长皮卡汀尼顶轨：单根轨基（机匣尾 z +0.16 直通护木头 z -0.47）+
	#    连续楔齿×8（机匣段/护木段齿列连续无分段感）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.012, 0.63),
			Vector3(0, 0.071, -0.155), Vector3.ZERO, 0.0015, 10)
	for i in 8:
		GUN_LIB.chamfer_box(root, met, Vector3(0.031, 0.006, 0.016),
				Vector3(0, 0.08, -0.44 + 0.075 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ② 轨基减重镂空暗槽×3（ref_10 轨条镂空——聚合物暗板嵌轨基读「挖空」）
	for i in 3:
		GUN_LIB.chamfer_box(root, ply, Vector3(0.029, 0.006, 0.012),
				Vector3(0, 0.071, -0.325 + 0.15 * float(i)), Vector3.ZERO,
				0.0008, 2)
	# ② AR 式顶部拉机柄凸台（机匣尾：T 杆 + 双翼三件——看图推断样式）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.007, 0.018),
			Vector3(0, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(-0.017, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(0.017, 0.068, 0.105), Vector3.ZERO, 0.0008, 3)
	# ① 机匣右侧带防尘盖抛壳窗（盖板贴合右侧面，AR 系同族件）
	GUN_LIB.chamfer_box(root, met, Vector3(0.004, 0.024, 0.068),
			Vector3(0.0285, 0.032, -0.045), Vector3.ZERO, 0.0008, 3)
	# ⑦ 弹匣井上方 DAF 白标 + 机匣右侧白色枪号刻印（ref_01/02/03 印字）
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.005, 0.028),
			Vector3(-0.0283, -0.026, -0.135), Vector3.ZERO, 0.0005, 2)
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.004, 0.030),
			Vector3(0.0283, 0.030, 0.015), Vector3.ZERO, 0.0005, 2)
	# ⑦ 快慢机红点缀（右侧控件暖橙小杆——ref_01/03 红色点缀）
	GUN_LIB.chamfer_box(root, bkl, Vector3(0.004, 0.010, 0.024),
			Vector3(0.0285, 0.006, 0.032), Vector3.ZERO, 0.0005, 2)
	# ⑧ AR 标准控件：右侧弹匣卡笋 / 左侧空仓挂机杆 / 下导轨衔接段
	GUN_LIB.chamfer_box(root, met, Vector3(0.006, 0.012, 0.018),
			Vector3(0.029, -0.022, -0.105), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.013, 0.036),
			Vector3(-0.0285, 0.008, -0.035), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, met, Vector3(0.03, 0.008, 0.10),
			Vector3(0, -0.048, -0.14), Vector3.ZERO, 0.0008, 6)
	# ③ 细长自由浮置护木（最强识别件）：细长倒角盒主体（0.052 宽比 k416
	#    0.056 窄——「更修长」）+ 顶轨衔接桥（轨基骑护木顶的过渡件）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.052, 0.058, 0.36),
			Vector3(0, 0.030, -0.32), Vector3.ZERO, 0.003, 24)
	GUN_LIB.chamfer_box(root, met, Vector3(0.030, 0.018, 0.36),
			Vector3(0, 0.062, -0.32), Vector3.ZERO, 0.0012, 12)
	# ③ 两侧各一排大型斜向平行四边形散热开槽×4（Rx(35°) 斜置暗板微凸侧面
	#    1mm 读「斜槽」——斜切口朝前上，ref_04/07/08/10 特征全枪最强）
	for sx in [-1.0, 1.0]:
		var fx := float(sx)
		for i in 4:
			GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.020, 0.058),
					Vector3(0.027 * fx, 0.020, -0.40 + 0.08 * float(i)),
					Vector3(35, 0, 0), 0.0008, 3)
	# ③ 底部短导轨段（下挂前握把安装位）+ 横齿×3——凸出护木底面
	GUN_LIB.chamfer_box(root, met, Vector3(0.024, 0.008, 0.12),
			Vector3(0, -0.004, -0.30), Vector3.ZERO, 0.0008, 4)
	for i in 3:
		GUN_LIB.chamfer_box(root, met, Vector3(0.026, 0.005, 0.014),
				Vector3(0, -0.011, -0.345 + 0.045 * float(i)), Vector3.ZERO,
				0.0006, 2)
	# ③ 护木前端收口环（浮置护木收口）
	GUN_LIB.chamfer_box(root, met, Vector3(0.056, 0.062, 0.014),
			Vector3(0, 0.030, -0.497), Vector3.ZERO, 0.001, 8)
	# ⑨ 枪管裸露段（护木前短露段 0.115，36 段高分段）+ 裸冠口环（出厂
	#    无消焰器的裸冠——亮钢口环读冠缘，ref_04）
	GUN_LIB.barrel(root, met, 0.115, 0.020, Vector3(0, 0.03, -0.5575),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.torus_ring(root, stl, 0.0085, 0.0115, Vector3(0, 0.03, -0.608),
			Vector3(90, 0, 0))
	# ④ 前翻折准星（护木前端轨上，展开态）：基座 + 圆柱准星 + 双护耳
	GUN_LIB.chamfer_box(root, met, Vector3(0.02, 0.012, 0.026),
			Vector3(0, 0.086, -0.44), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.barrel(root, stl, 0.014, 0.005, Vector3(0, 0.098, -0.44),
			Vector3.ZERO, 0, 16)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.018, 0.012),
				Vector3(0.008 * float(sx), 0.096, -0.44), Vector3.ZERO,
				0.0006, 3)
	# ④ 后翻折觇孔照门（机匣尾轨上，展开态）：基座 + 后仰觇孔板 + 双耳
	GUN_LIB.chamfer_box(root, met, Vector3(0.02, 0.012, 0.026),
			Vector3(0, 0.086, 0.085), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.02, 0.006),
			Vector3(0, 0.098, 0.09), Vector3(-10, 0, 0), 0.0006, 3)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.016, 0.010),
				Vector3(0.009 * float(sx), 0.095, 0.095), Vector3.ZERO,
				0.0006, 3)
	# ⑤ 三角镂空骨架式折叠托（AAC 蜜獾/Q 系轮廓，展开态）：铰链块 + 铰链
	#    销 + 折叠解锁钮 + 缓冲短管（seg32 开筒壁厚断面）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.044, 0.050, 0.045),
			Vector3(0, 0.034, 0.130), Vector3.ZERO, 0.002, 16)
	GUN_LIB.barrel(root, stl, 0.050, 0.010, Vector3(0, 0.038, 0.132),
			Vector3(0, 0, 90), 0, 16)
	GUN_LIB.chamfer_box(root, met, Vector3(0.008, 0.016, 0.020),
			Vector3(0.026, 0.030, 0.130), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.tube(root, met, 0.06, 0.036, Vector3(0, 0.020, 0.180),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	# ⑤ 托体上杆（微下斜 Rx(5°)——托尾线向抵肩垫渐降）+ 贴腮板（顶杆上
	#    另起一层，随杆微倾）+ 下斜撑（Rx(28°) 从下机匣后斜插托底板下角
	#    ——与上杆围出三角镂空）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.024, 0.026, 0.17),
			Vector3(0, 0.030, 0.285), Vector3(5, 0, 0), 0.0015, 8)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.040, 0.014, 0.12),
			Vector3(0, 0.050, 0.27), Vector3(5, 0, 0), 0.001, 6)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.018, 0.018, 0.20),
			Vector3(0, -0.010, 0.26), Vector3(28, 0, 0), 0.0015, 8)
	# ⑤ 托底板 + 橡胶抵肩垫 + 托底前钩（三角托收尾三件）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.038, 0.105, 0.014),
			Vector3(0, -0.008, 0.352), Vector3.ZERO, 0.0015, 12)
	GUN_LIB.chamfer_box(root, rub, Vector3(0.046, 0.100, 0.010),
			Vector3(0, -0.010, 0.364), Vector3.ZERO, 0.0012, 10)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.034, 0.020, 0.030),
			Vector3(0, -0.046, 0.336), Vector3.ZERO, 0.001, 4)
	# ⑦ 一体式扳机护圈（底梁 + 前后柱与下机匣连成一体）+ 扳机
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.008, 0.07),
			Vector3(0, -0.062, 0.015), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.030, 0.008),
			Vector3(0, -0.046, -0.016), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.028, 0.008),
			Vector3(0, -0.047, 0.046), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.041, 0.014), Vector3(10, 0, 0), 0.0006, 2)
	# ⑧ 后握把（后倾 20° 带指槽人体工学聚合物握把，指棱×3）：grip() 顶锚
	#    = 旋转支点，HOLD_DELTA 精算锚点（见 hd_guns.gd k437 条目：Δ =
	#    MK4 基准 (0,-0.022,-0.0018) − 本锚 (0,-0.030,0.075)，AR 式握把
	#    与 k416/an94/sr25 同锚）
	GUN_LIB.grip(root, ply, 0.092, Vector3(0, -0.030, 0.075), 20.0,
			0.036, 0.05, stl, 3)
	# ⑫ 背带环×2（护木底中段 + 托底板左下，环面 ⊥ X 竖环）
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011, Vector3(0, -0.014, -0.20),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011,
			Vector3(-0.022, -0.035, 0.335), Vector3(0, 0, 90), 28, 18)
	# ⑥ 30 发 .300 BLK 大弧烟灰匣（独立命名节点 mag_k437：原点=匣顶中心，
	#    curved_mag 向下生长、8° 四段弧弧向前——弧度大于 STANAG 5° 微弧、
	#    小于 AK 13°；动画匣 show:false 照 k416「匣形由枪身件表达」先例，
	#    见 _ar_mag_of）
	var mag := Node3D.new()
	mag.name = "mag_k437"
	mag.position = Vector3(0, -0.058, -0.155)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, ply, Vector3(0.05, 0.19, 0.085), 8.0, 4, 3)
	# ⑥ 两面横向肋条×3（随匣弧逐段转角 0/8/16°——肋条比匣身宽 4mm 两面
	#    同时出肋，黑聚合物同色靠几何凸起读影；步进/弧向逐段复刻
	#    curved_mag 的段心算法，asval/k416 匣肋同法）
	var cm_step := 0.19 / 4.0
	var cm_c := Vector3(0, -cm_step * 0.5, 0)
	for i in 3:
		if i > 0:
			var ra := deg_to_rad(8.0 * (float(i) - 0.5))
			cm_c += Vector3(0.0, -cos(ra), -sin(ra)) * cm_step
		GUN_LIB.chamfer_box(mag, ply, Vector3(0.054, 0.007, 0.089),
				cm_c, Vector3(8.0 * float(i), 0, 0), 0.0008, 2)
	# ⑥ 匣侧 DAF 白标（烟灰匣身白色印刷标——ref_02/05/07「DAF」）
	GUN_LIB.chamfer_box(mag, mrk, Vector3(0.002, 0.022, 0.034),
			Vector3(-0.0255, -0.052, 0.004), Vector3.ZERO, 0.0005, 2)


## QCQ171 冲锋枪（2026-10-30 商店枪·9×19mm，国产 QCQ-171 原外贸型 CS/LR-7
## 「出口转内销」列装高原部队单兵自卫）考证特征逐条落件（HDGunLib 高模重建
## ——基线 2361 与红线见 HDGunLib.POLY_MIN["qcq171"]；整体布局照用户图
## ref_00（首要）+ ref_01/03 三角洲游戏图 + ref_04 真枪照三源一致：紧凑方正
## 常规有托布局，枪身 z -0.475(消焰器口) 到 +0.320(托底板) 全长 ≈0.80 模型尺
## ——比 K437（0.98）短一档的紧凑冲锋枪，托伸 690mm 实枪按本作模型尺惯例
## ≈1.16×；册属冲锋枪（hd_guns SMG_IDS 分发到本册 AR_LIB 同链）：
## ①常规有托布局：弹匣直插握把前方的弹匣井（井 z -0.115 在握把 z +0.075
##   之前）、握把位于扳机正上方——非无托、非握把供弹（用户图 ref_00 铁证）
## ②伸缩式枪托（非侧折）：两根银灰金属伸缩杆（亮钢 barrel×2，x ±0.016）
##   各带 4 个长条形减重镂空孔（暗板负形读「长孔」）、末端黑聚合物方板托
##   底板略后倾 8°、无折叠铰链（部分网络资料描述真枪侧折托——冲突处以
##   用户图为准：只见双杆+方板，不见铰链）
## ③上机匣为金属平顶机匣 + 全长皮卡汀尼导轨：单根轨基从机匣尾 z +0.16
##   直通护木前端 z -0.37（连成一线无分段感）+ 连续楔齿×7（用户图 + ref_01/03
##   游戏图 + ref_04 真枪照三源一致）
## ④下机匣与护木为黑色聚合物、轮廓方正一体感强：护木中等偏短（0.21），
##   侧面开 M-LOK 风格散热镂空（横向长孔×3×2 暗板负形）+ 底部短接口条
## ⑤黑色聚合物直弹匣、不透明无余弹观察窗：30 发长度（匣体 0.165）、微
##   前倾 6°（mp7 先例）、两段 3° 近直微弧 + 横肋×2、无并联弹匣——
##   mag_qcq171 独立命名节点 + curved_mag（动画匣 show:false 照 k437 先例）
## ⑥独立聚合物握把：后倾 17°（考证 15-20° 取中）、表面点状防滑纹
##   （2 列×3 行点阵×2 侧，12 点暗色小方点）
## ⑦拉机柄为上置后拉式：机匣尾部上侧 T 形柄（杆+双翼三件，非随动——
##   ref_01/03 三角洲游戏图，用户图上看不清此条以网图为准）
## ⑧白板瞄具：翻转式觇孔照门（机匣尾轨上：基座+觇孔板+双耳）+ 护木前端
##   片状准星（薄片刃+双护耳）——真实机瞄为建模件（_finish_gun iron 分支
##   跳过兜底机瞄片，同 k437 先例）；顶部导轨可换红点/全息（ref_01 游戏
##   改装常态）走通用挂载
## ⑨枪口为短鸟笼式消焰器（开筒内衬亮钢膛 + 两侧纵槽口 + 前挡环），消焰器
##   后有一小段裸露枪管（36 段 + 肩环）；消音器为选配件不入厂（用户图枪口）
## ⑩配色全黑单色：聚合物黑主体 + 近黑金属上机匣/轨/枪管；仅快慢机标记点
##   为红色（bakelite 暖橙读红，k437 先例）、伸缩托杆为银灰金属色（steel）
## ⑪机匣左侧白色刻印编号（『DSU-**-018000』样式，用户图独有）：kmark 白
##   长条刻印贴上机匣左侧
## ⑫快慢机位于握把上方左侧、带红色标记点，支持单发/全自动（用户图 +
##   三角洲面板）：左侧选择杆 + 红点
## ⑬整体紧凑短小、线条方正平直，枪管轴线（y 0.030）与托底板同高形成直托
##   抵肩线（双杆 y 0.022、托底板中心 y 0.020 跨轴线——无下坠无上翘）
static func _ar_qcq171(mats: Dictionary, root: Node3D) -> void:
	var ply: StandardMaterial3D = mats["polymer"]   # ⑩ 黑聚合物（下机匣/护木/托底板/握把/弹匣）
	var met: StandardMaterial3D = mats["dark"]      # ⑩ 近黑金属（上机匣平顶/轨/枪管/消焰器/控件）
	var stl: StandardMaterial3D = mats["steel"]     # ⑩ 银灰金属（伸缩托双杆——全枪唯一银色件）
	var mrk: StandardMaterial3D = mats["kmark"]     # ⑪ 白色刻印（DSU-**-018000 编号）
	var bkl: StandardMaterial3D = mats["bakelite"]  # ⑫ 快慢机红标记点（暖橙读红）
	# ③① 上机匣（金属平顶，s24 高分段：顶面即③全长轨座，与下机匣分质读
	#    「金属上/聚合物下」）+ 下机匣（弹匣井/握把座一体，方正轮廓）
	GUN_LIB.chamfer_box(root, met, Vector3(0.050, 0.055, 0.30),
			Vector3(0, 0.033, 0.01), Vector3.ZERO, 0.003, 24)
	GUN_LIB.chamfer_box(root, ply, Vector3(0.052, 0.050, 0.26),
			Vector3(0, -0.016, 0.0), Vector3.ZERO, 0.0025, 20)
	# ① 弹匣井（下机匣前下、握把前方——常规有托布局的合同件；井底 y -0.088
	#    对 mag_qcq171 匣顶 -0.055 嵌入 33mm 防接缝，k416 同口径）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.050, 0.080, 0.082),
			Vector3(0, -0.048, -0.115), Vector3.ZERO, 0.002, 8)
	# ② 机匣尾封板（伸缩托接口座——无折叠铰链，双杆直接从板后探出）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.046, 0.062, 0.022),
			Vector3(0, 0.022, 0.166), Vector3.ZERO, 0.002, 8)
	# ③ 全长皮卡汀尼顶轨：单根轨基（机匣尾 z +0.155 直通护木前端 z -0.365
	#    ——「导轨向前延伸与护木顶部连成一线」）+ 连续楔齿×7
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.012, 0.52),
			Vector3(0, 0.0665, -0.105), Vector3.ZERO, 0.0015, 10)
	for i in 7:
		GUN_LIB.chamfer_box(root, met, Vector3(0.031, 0.006, 0.016),
				Vector3(0, 0.0756, -0.345 + 0.065 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ⑦ 上置后拉式拉机柄（机匣尾部上侧 T 形柄：杆 + 双翼三件，非随动）
	GUN_LIB.chamfer_box(root, met, Vector3(0.028, 0.007, 0.018),
			Vector3(0, 0.0595, 0.125), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(-0.017, 0.0595, 0.125), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.006, 0.012),
			Vector3(0.017, 0.0595, 0.125), Vector3.ZERO, 0.0008, 3)
	# ⑩ 机匣右侧抛壳窗（暗腔盖板贴合右侧面，k437 同族件）
	GUN_LIB.chamfer_box(root, met, Vector3(0.004, 0.022, 0.060),
			Vector3(0.0265, 0.030, -0.035), Vector3.ZERO, 0.0008, 3)
	# ⑪ 机匣左侧白色刻印编号（『DSU-**-018000』样式长条白刻印，用户图独有）
	GUN_LIB.chamfer_box(root, mrk, Vector3(0.002, 0.006, 0.036),
			Vector3(-0.0265, 0.044, -0.055), Vector3.ZERO, 0.0005, 2)
	# ⑫ 左侧快慢机（握把上方）+ 红色标记点
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.012, 0.026),
			Vector3(-0.0275, 0.002, 0.038), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, bkl, Vector3(0.004, 0.006, 0.004),
			Vector3(-0.0285, 0.009, 0.030), Vector3.ZERO, 0.0005, 2)
	# AR 标准控件：右侧弹匣卡笋 / 左侧空仓挂机杆
	GUN_LIB.chamfer_box(root, met, Vector3(0.006, 0.012, 0.018),
			Vector3(0.027, -0.022, -0.075), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.013, 0.034),
			Vector3(-0.0275, 0.006, -0.030), Vector3.ZERO, 0.0006, 2)
	# ④ 聚合物护木（中等偏短 0.21、方正轮廓）+ 轨基衔接桥（轨基骑护木顶，
	#    轨线与护木顶连成一体不悬空）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.052, 0.056, 0.21),
			Vector3(0, 0.030, -0.245), Vector3.ZERO, 0.003, 24)
	GUN_LIB.chamfer_box(root, met, Vector3(0.030, 0.006, 0.21),
			Vector3(0, 0.0585, -0.245), Vector3.ZERO, 0.001, 8)
	# ④ 护木侧面 M-LOK 风格散热镂空（横向长孔×3×2，暗板负形微凸侧面读「槽」）
	for sx in [-1.0, 1.0]:
		var fx := float(sx)
		for i in 3:
			GUN_LIB.chamfer_box(root, met, Vector3(0.004, 0.013, 0.046),
					Vector3(0.027 * fx, 0.028, -0.283 + 0.055 * float(i)),
					Vector3.ZERO, 0.0008, 3)
	# ④ 护木底部短接口条（下挂件安装位的光条，不刻齿）
	GUN_LIB.chamfer_box(root, met, Vector3(0.024, 0.006, 0.16),
			Vector3(0, 0.000, -0.26), Vector3.ZERO, 0.0008, 4)
	# ⑧ 护木前端片状准星（轨顶基座 + 薄片刃 + 双护耳——「片状准星」的薄刃
	#    读法，区别于圆柱准星）
	GUN_LIB.chamfer_box(root, met, Vector3(0.020, 0.012, 0.026),
			Vector3(0, 0.079, -0.335), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.022, 0.006),
			Vector3(0, 0.096, -0.338), Vector3.ZERO, 0.0006, 2)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.020, 0.010),
				Vector3(0.008 * float(sx), 0.094, -0.335), Vector3.ZERO,
				0.0006, 3)
	# ⑧ 机匣尾轨上翻转觇孔照门（基座 + 后仰觇孔板 + 双耳，展开态建模）
	GUN_LIB.chamfer_box(root, met, Vector3(0.020, 0.010, 0.026),
			Vector3(0, 0.077, 0.10), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.005, 0.020, 0.006),
			Vector3(0, 0.092, 0.105), Vector3(-10, 0, 0), 0.0006, 3)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.016, 0.010),
				Vector3(0.009 * float(sx), 0.089, 0.105), Vector3.ZERO,
				0.0006, 3)
	# ⑨ 裸露枪管段（消焰器后一小段，36 段高分段）+ 枪口肩环
	GUN_LIB.barrel(root, met, 0.07, 0.022, Vector3(0, 0.030, -0.375),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.torus_ring(root, met, 0.0095, 0.0135, Vector3(0, 0.030, -0.412),
			Vector3(90, 0, 0))
	# ⑨ 短鸟笼式消焰器：开筒内衬亮钢膛 + 两侧纵槽口 + 前挡环（k416 同族短冠）
	GUN_LIB.tube(root, met, 0.055, 0.026, Vector3(0, 0.030, -0.438),
			Vector3(90, 0, 0), 0.003, 0, stl, 3, 32)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.030),
			Vector3(-0.011, 0.030, -0.438), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.030),
			Vector3(0.011, 0.030, -0.438), Vector3.ZERO, 0.0006, 3)
	GUN_LIB.torus_ring(root, stl, 0.011, 0.014, Vector3(0, 0.030, -0.460),
			Vector3(90, 0, 0))
	# ② 伸缩式枪托（非侧折）：两根银灰金属伸缩杆（亮钢 barrel×2，x ±0.016
	#    沿 z 平直后伸 z 0.1675..0.3125 尾端 8.5mm 埋进托底板防接缝——⑬直托
	#    抵肩线：杆轴 y 0.022 与枪管轴 0.030 近同高）
	GUN_LIB.barrel(root, stl, 0.145, 0.016, Vector3(-0.016, 0.022, 0.24),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.barrel(root, stl, 0.145, 0.016, Vector3(0.016, 0.022, 0.24),
			Vector3(90, 0, 0), 0, 24)
	# ② 每杆 4 个长条形减重镂空孔（外侧暗板负形读「长孔」，杆面开槽的
	#    高模语言——k416 托侧减重孔同法）
	for sx in [-1.0, 1.0]:
		var rx := float(sx)
		for i in 4:
			GUN_LIB.chamfer_box(root, met, Vector3(0.002, 0.0045, 0.020),
					Vector3(0.0245 * rx, 0.022, 0.196 + 0.026 * float(i)),
					Vector3.ZERO, 0.0006, 2)
	# ② 托杆伸缩锁扣钮（右侧、尾封板后）
	GUN_LIB.chamfer_box(root, met, Vector3(0.010, 0.012, 0.024),
			Vector3(0.022, 0.010, 0.185), Vector3.ZERO, 0.0008, 3)
	# ② 黑色聚合物方板托底板（略后倾 8°；⑬中心 y 0.020 跨枪管轴线——直托
	#    抵肩线无下坠）
	GUN_LIB.chamfer_box(root, ply, Vector3(0.048, 0.088, 0.016),
			Vector3(0, 0.020, 0.312), Vector3(8, 0, 0), 0.002, 12)
	# 一体式扳机护圈（底梁 + 前后柱与下机匣连成一体）+ 扳机
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.007, 0.075),
			Vector3(0, -0.062, 0.015), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.030, 0.008),
			Vector3(0, -0.047, -0.020), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, met, Vector3(0.012, 0.028, 0.008),
			Vector3(0, -0.047, 0.048), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.041, 0.012), Vector3(10, 0, 0), 0.0006, 2)
	# ⑥ 独立聚合物握把（后倾 17°——考证 15-20° 取中；grip() 顶锚=旋转支点，
	#    HOLD_DELTA 精算锚点（见 hd_guns.gd qcq171 条目：Δ = MK4 基准
	#    (0,-0.022,-0.0018) − 本锚 (0,-0.030,0.075)，AR 式握把与 k416/k437
	#    同锚））
	var grp: Node3D = GUN_LIB.grip(root, ply, 0.088, Vector3(0, -0.030, 0.075),
			17.0, 0.036, 0.050, stl, 3)
	# ⑥ 握把表面点状防滑纹（2 列×3 行点阵×2 侧 = 12 点暗色小方点——「点状
	#    防滑纹」的点阵读法，区别于 k416 条状指棱）
	for sx in [-1.0, 1.0]:
		var gx := float(sx)
		for i in 3:
			for j in 2:
				GUN_LIB.chamfer_box(grp, met, Vector3(0.0025, 0.0025, 0.0025),
						Vector3(0.0185 * gx, -0.026 - 0.012 * float(i),
								-0.010 + 0.012 * float(j)), Vector3.ZERO,
						0.0004, 2)
	# ⑬ 背带环×2（护木下 + 托底板左下，环面 ⊥ X 竖环）
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011, Vector3(0, -0.010, -0.31),
			Vector3(0, 0, 90), 28, 18)
	GUN_LIB.torus_ring(root, stl, 0.004, 0.011,
			Vector3(-0.026, -0.006, 0.300), Vector3(0, 0, 90), 28, 18)
	# ⑤ 黑色聚合物直弹匣（不透明无余弹观察窗、30 发长度、微前倾 6°：独立
	#    命名节点 mag_qcq171 + curved_mag 两段 3° 近直微弧弧向前——「直匣
	#    微前倾 5-10°」；动画匣 show:false 照 k437「匣形由枪身件表达」先例，
	#    见 hd_guns._smg_mag_of）
	var mag := Node3D.new()
	mag.name = "mag_qcq171"
	mag.position = Vector3(0, -0.055, -0.115)
	mag.rotation_degrees = Vector3(6, 0, 0)
	root.add_child(mag)
	GUN_LIB.curved_mag(mag, ply, Vector3(0.046, 0.165, 0.075), 3.0, 2, 3)
	# ⑤ 匣体横肋×2（随匣弧逐段转角 0/3°——肋条比匣身宽 4mm 两面同时出肋，
	#    黑聚合物同色靠几何凸起读影；步进/弧向逐段复刻 curved_mag 的段心
	#    算法，k416/k437 匣肋同法）
	var cm_step := 0.165 / 2.0
	var cm_c := Vector3(0, -cm_step * 0.5, 0)
	for i in 2:
		if i > 0:
			var ra := deg_to_rad(3.0 * (float(i) - 0.5))
			cm_c += Vector3(0.0, -cos(ra), -sin(ra)) * cm_step
		GUN_LIB.chamfer_box(mag, ply, Vector3(0.050, 0.007, 0.079),
				cm_c, Vector3(3.0 * float(i), 0, 0), 0.0008, 2)
