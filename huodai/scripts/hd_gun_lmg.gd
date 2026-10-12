class_name HDGunLMG
extends RefCounted
## 机枪册（m250：SIG XM250 体系，6.8×51mm 弹链机枪）高模几何体：用 HDGunLib
## 工具件（倒角盒/八角棱柱护木/螺纹枪管/消音筒/环件/握把）拼装，FDE 沙黄
## 涂装，体量比 SCAR-H 大一号、枪管更长（考证特征逐条落件，见 _m250 头注释）。
##
## 契约（与 HDGunAR 同约，保持不动）：
## - 入口：hd_guns.gd `_lmg_build(id)` 分发到本文件 build(id, mats)，语义不变
##   （未知 id 返回空 Node3D 防御不崩）；_lmg_has/_lmg_mag_of/_lmg_scope_anchor
##   仍在 hd_guns.gd 分发表。
## - 弹链袋：无弹匣——75 发软式弹链袋 = 本文件枪身根下的独立命名节点
##   （mag_pouch，原点=袋顶中心、软袋向下生长），换弹动画匣仍由 hd_guns
##   统一挂 holder（_lmg_mag_of 只切 show=false，pos/size=换弹手锚与掉匣
##   替身缩放基准，同 MK4 先例）。
## - 材质：调用方传参注入（build 收 hd_guns._lmg_mats() 字典），本文件零材质
##   创建——材质唯一出处纪律，与 HDGunLib/HDGunAR 同约。
## - 典型挂件 XM157 1-8x 火控镜按考证清单「可整体省略只留裸顶轨」处理：
##   镜体不落件，顶轨补折叠机械瞄具（装配瞄具仍走 _finish_gun 统一挂）。
##
## 顶点账目（公式口径，循环展开；运行时以 HDGunLib.count_vertices 实测为准）：
##   m250   基线 3429（93 盒×24 + 21 柱×57，逐行清点见 HDGunLib.POLY_BASE 注）
##          → 实测 33386；门槛 = 8× 基线 = 27432，见 HDGunLib.POLY_MIN["m250"]
##          （test_huodai.gd 实测断言）。

const GUN_LIB := preload("res://scripts/hd_gunlib.gd")


## 统一入口：按 id 拼一把枪身根；未知 id 返回空 Node3D（防御不崩）
static func build(id: String, mats: Dictionary) -> Node3D:
	var root := Node3D.new()
	match id:
		"m250":
			_m250(mats, root)
		_:
			pass   # 未知 id：不落任何部件，返回空枪身根
	return root


## M250 机枪（SIG XM250，6.8×51mm，射速 550 发每分，75 发弹链袋）考证特征
## 逐条落件（HDGunLib 高模重建——基线 3429 → 实测 33386，红线
## POLY_MIN["m250"]；FDE 沙黄主体 #B09A68，体量比 SCAR-H 大一号）：
## ①整体布局：AR 式直托三段结构（上机匣+下机匣+尾接托块+悬浮护木），
##   带消音器全长约 1045-1063mm、枪管 444mm、体量紧凑饱满、重心靠后
## ②供弹方式：无弹匣，机匣底部中前位下挂软式弹链袋（mag_pouch 独立命名
##   节点：帆布方袋+黑色硬质供弹口盖+束带/侧织带暗示），黄铜弹链横向喂入
##   机匣左侧受弹口（全枪唯一暖金点缀）
## ③供弹盖：机匣顶部侧向铰开的大平面盖板，平整嵌在左右两段顶轨缘条之间，
##   盖面防滑细纹 ×7 + 左缘铰链线
## ④顶轨：机匣至护木前端一整条连续皮卡汀尼楔齿顶轨（单根轨基贯通不中断），
##   前段楔齿×6 + 后段楔齿×2，中段供弹盖嵌于其中
## ⑤护木：八角截面加长护木（barrel seg=8 = 正八棱柱）包裹浮动枪管，上排
##   大尺寸斜切长条减重槽×2、下排 M-LOK 条孔×8，侧壁一圈银色内六角螺丝×10
## ⑥枪口：圆柱形快拆消音器（沙棕筒身 seg64 开筒内衬亮钢膛 + 根部黑色锁紧
##   套环 + 前后快拆夹环 + 枪口前挡环）
## ⑦导气系统：护木前段上方柱状导气箍带黑色两档导气阀（侧面刻档位标记），
##   顶槽内可见银色缓冲筒/活塞组件
## ⑧枪托：沙黄聚合物枪托 5 档贴腮调长、不可折叠，斜切面贴腮造型 + 底部
##   厚橡胶托底板 + 档位卡钮/调长扳柄/托侧调节钮
## ⑨握把与拉机柄：沙黄 AR 式手枪握把（直倾角指槽防滑纹）；黑色防滑纹拉机柄
##   位于机匣与护木交界的顶轨缺口内（顶部布局）
## ⑩两脚架：护木前下方黑色两脚架，行军态折叠收拢贴护木（双腿向后收拢 +
##   伸缩锁环），脚尖带金属驻钉
## ⑪抛壳与枪管撞色：机匣右侧大抛壳口配黑色铰链防尘盖，枪管段为发黑裸钢管
##   （36 段 + 螺纹环×3），与沙黄护木形成明显黑白撞色
## ⑫配色分区：沙黄主体（机匣/护木/枪托/握把/消音器筒身）、近黑件（枪管/
##   导气箍/两脚架/供弹盖/抛壳盖/锁环/拉机柄）、亮色点缀（银色螺丝与缓冲筒、
##   黄铜弹链）
## ⑬典型挂件：XM157 1-8x 火控镜整体省略只留裸顶轨（补折叠机械瞄具前后各一）
static func _m250(mats: Dictionary, root: Node3D) -> void:
	var fde: StandardMaterial3D = mats["fde"]       # ⑫ 沙黄主体（机匣/护木/托/握把）
	var supp: StandardMaterial3D = mats["supp"]     # ⑫ 消音器沙棕筒身
	var dark: StandardMaterial3D = mats["dark"]     # ⑫ 近黑件（枪管/导气箍/盖板/脚架）
	var stl: StandardMaterial3D = mats["steel"]     # ⑫ 亮钢点缀（螺丝/缓冲筒/挡环）
	var cnv: StandardMaterial3D = mats["canvas"]    # ⑫ 弹链袋卡其帆布
	var web: StandardMaterial3D = mats["webbing"]   # ⑫ 束带插扣深棕
	var brs: StandardMaterial3D = mats["brass"]     # ⑫ 黄铜弹链（唯一暖金）
	# ① 三段结构上段：AR 式平顶上机匣（顶面即④轨座）——倒角盒 s12
	GUN_LIB.chamfer_box(root, fde, Vector3(0.058, 0.07, 0.34),
			Vector3(0, 0.03, -0.05), Vector3.ZERO, 0.0035, 12)
	# ① 三段结构中段：下机匣（弹链袋座/握把座/护圈）——倒角盒 s12
	GUN_LIB.chamfer_box(root, fde, Vector3(0.054, 0.058, 0.22),
			Vector3(0, -0.024, 0.015), Vector3.ZERO, 0.003, 12)
	# ① 尾段接托块（托体挂接颈，体量饱满）
	GUN_LIB.chamfer_box(root, fde, Vector3(0.05, 0.06, 0.055),
			Vector3(0, 0.03, 0.145), Vector3.ZERO, 0.003, 8)
	# ④ 连续顶轨：单根轨基（z -0.54..0.12 一根直通不中断）——倒角盒 s12
	GUN_LIB.chamfer_box(root, dark, Vector3(0.026, 0.012, 0.66),
			Vector3(0, 0.071, -0.21), Vector3.ZERO, 0.0015, 12)
	for i in 6:
		# ④ 前段楔齿 ×6（护木上段，步距 0.07；-0.515 留导气箍缺口）
		GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.006, 0.016),
				Vector3(0, 0.08, -0.55 + 0.07 * float(i)), Vector3.ZERO,
				0.0012, 8)
	for i in 2:
		# ④ 后段楔齿 ×2（供弹盖后到机匣尾）
		GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.006, 0.016),
				Vector3(0, 0.08, 0.045 + 0.045 * float(i)), Vector3.ZERO,
				0.0012, 8)
	# ③ 供弹盖：左右顶轨缘条 + 嵌入其间的平面盖板（低于楔齿一档）+
	#    盖面防滑细纹 ×7 + 左缘铰链线（侧向铰开）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.006, 0.016, 0.19),
			Vector3(-0.0135, 0.073, -0.05), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.006, 0.016, 0.19),
			Vector3(0.0135, 0.073, -0.05), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.024, 0.008, 0.16),
			Vector3(0, 0.069, -0.05), Vector3.ZERO, 0.0015, 12)
	for i in 7:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.02, 0.002, 0.009),
				Vector3(0, 0.0735, -0.112 + 0.024 * float(i)), Vector3.ZERO,
				0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.003, 0.17),
			Vector3(-0.0155, 0.0805, -0.05), Vector3.ZERO, 0.0006, 2)
	# ⑨ 拉机柄：黑色防滑纹拉机柄，位于机匣与护木交界的顶轨缺口内（顶部
	#    布局；齿段 -0.20 与供弹盖缘条之间的缺口）+ 双翼
	GUN_LIB.chamfer_box(root, dark, Vector3(0.034, 0.008, 0.022),
			Vector3(0, 0.079, -0.175), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.011, 0.006, 0.011),
			Vector3(-0.019, 0.079, -0.175), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.011, 0.006, 0.011),
			Vector3(0.019, 0.079, -0.175), Vector3.ZERO, 0.0006, 2)
	# ⑤ 八角截面加长护木（barrel seg=8 = 正八棱柱，悬浮包裹枪管）+
	#    尾端八角过渡箍（同 seg=8 短棱柱，外扩 3mm 盖住接机匣的截面缝）
	GUN_LIB.barrel(root, fde, 0.38, 0.062, Vector3(0, 0.03, -0.40),
			Vector3(90, 0, 0), 0, 8)
	GUN_LIB.barrel(root, fde, 0.03, 0.068, Vector3(0, 0.03, -0.215),
			Vector3(90, 0, 0), 0, 8)
	# ⑤ 上排大尺寸斜切长条减重槽 ×2（顶斜面左右：长条沿 z 向、贴面侧倾
	#    22.5° 对齐八角斜面 + 微俯仰 8° 示斜切端向；齿顶之下不越轨线）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.016, 0.006, 0.22),
			Vector3(0.012, 0.058, -0.40), Vector3(8, 0, -22.5), 0.001, 5)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.016, 0.006, 0.22),
			Vector3(-0.012, 0.058, -0.40), Vector3(8, 0, 22.5), 0.001, 5)
	for i in 4:
		# ⑤ 下排 M-LOK 条孔 ×8（左右下斜面各 4 条：长条沿 z 向、贴面侧倾
		#    22.5° 对齐八角下斜面）
		GUN_LIB.chamfer_box(root, dark, Vector3(0.012, 0.005, 0.07),
				Vector3(0.012, 0.002, -0.29 - 0.07 * float(i)),
				Vector3(0, 0, -22.5), 0.0008, 8)
		GUN_LIB.chamfer_box(root, dark, Vector3(0.012, 0.005, 0.07),
				Vector3(-0.012, 0.002, -0.29 - 0.07 * float(i)),
				Vector3(0, 0, 22.5), 0.0008, 8)
	for i in 5:
		# ⑤ 侧壁一圈银色内六角螺丝 ×10（前后 5 站位 × 左右）
		GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.009, 0.009),
				Vector3(0.0325, 0.03, -0.56 + 0.08 * float(i)),
				Vector3.ZERO, 0.0008, 4)
		GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.009, 0.009),
				Vector3(-0.0325, 0.03, -0.56 + 0.08 * float(i)),
				Vector3.ZERO, 0.0008, 4)
	# ⑦ 导气系统：护木前段上方柱状导气箍（嵌前段楔齿缺口）+ 黑色两档
	#    导气阀（左阀钮 + 侧面两档刻位标记）+ 顶槽内银色缓冲筒/活塞组件
	GUN_LIB.chamfer_box(root, dark, Vector3(0.026, 0.03, 0.045),
			Vector3(0, 0.055, -0.515), Vector3.ZERO, 0.0015, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.008, 0.014, 0.018),
			Vector3(-0.018, 0.055, -0.515), Vector3.ZERO, 0.0008, 3)
	for i in 2:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.003, 0.004, 0.005),
				Vector3(-0.0225, 0.051 + 0.008 * float(i), -0.515),
				Vector3.ZERO, 0.0005, 2)
	GUN_LIB.barrel(root, stl, 0.14, 0.012, Vector3(0, 0.058, -0.36),
			Vector3(90, 0, 0), 0, 24)
	# ⑪⑥ 枪管（发黑裸钢管撞色：36 段高分段 + 枪口端螺纹环 ×3 作消音器
	#    锁紧段）+ 护木口枪管肩环（亮钢）
	GUN_LIB.barrel(root, dark, 0.10, 0.024, Vector3(0, 0.03, -0.62),
			Vector3(90, 0, 0), 3, 36)
	GUN_LIB.torus_ring(root, stl, 0.011, 0.018, Vector3(0, 0.03, -0.578),
			Vector3(90, 0, 0))
	# ⑥ 快拆消音器：根部黑色锁紧套环 + 沙棕筒身（seg64 开筒内衬亮钢膛）+
	#    前后快拆夹环 + 枪口前挡环（亮钢）——无消音器态不另建模（制式挂筒态）
	GUN_LIB.torus_ring(root, dark, 0.025, 0.037, Vector3(0, 0.03, -0.665),
			Vector3(90, 0, 0))
	GUN_LIB.tube(root, supp, 0.22, 0.064, Vector3(0, 0.03, -0.775),
			Vector3(90, 0, 0), 0.004, 0, stl, 3, 64)
	GUN_LIB.torus_ring(root, dark, 0.03, 0.038, Vector3(0, 0.03, -0.70),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, dark, 0.03, 0.038, Vector3(0, 0.03, -0.85),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, stl, 0.03, 0.036, Vector3(0, 0.03, -0.882),
			Vector3(90, 0, 0))
	# ⑪ 抛壳与撞色：机匣右侧大抛壳口（框 + 黑色铰链防尘盖 + 亮钢铰链轴）
	#    + 抛壳导板；右侧快慢机钮
	GUN_LIB.chamfer_box(root, dark, Vector3(0.004, 0.032, 0.085),
			Vector3(0.0295, 0.03, -0.10), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.005, 0.034, 0.09),
			Vector3(0.0325, 0.03, -0.10), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.004, 0.085),
			Vector3(0.031, 0.049, -0.10), Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.01, 0.014, 0.014),
			Vector3(0.03, 0.04, -0.048), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.012, 0.026),
			Vector3(0.029, -0.018, 0.045), Vector3.ZERO, 0.0006, 2)
	# ② 供弹侧：左侧受弹口框 + 黄铜弹链横向喂入（链节 ×3 探出 + 斜置
	#    弹链带，全枪唯一暖金点缀）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.004, 0.026, 0.075),
			Vector3(-0.0295, 0.026, -0.115), Vector3.ZERO, 0.001, 6)
	for i in 3:
		GUN_LIB.chamfer_box(root, brs, Vector3(0.012, 0.013, 0.02),
				Vector3(-0.037, 0.026, -0.135 + 0.022 * float(i)),
				Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, brs, Vector3(0.01, 0.03, 0.05),
			Vector3(-0.044, 0.008, -0.128), Vector3(0, 0, 22), 0.001, 3)
	# ② 机匣底受弹口座（弹链袋挂接框，袋顶黑色硬质供弹口盖扣在此）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.07, 0.014, 0.115),
			Vector3(0, -0.06, -0.085), Vector3.ZERO, 0.002, 12)
	# QD 背带环 ×2（机匣尾左侧 / 托颈右侧，穿孔轴沿 X = 侧挂环）
	GUN_LIB.torus_ring(root, stl, 0.003, 0.008,
			Vector3(-0.028, 0.005, 0.148), Vector3(0, 0, 90))
	GUN_LIB.torus_ring(root, stl, 0.003, 0.008,
			Vector3(0.028, -0.01, 0.16), Vector3(0, 0, 90))
	# ② 75 发软式弹链袋 = 独立命名节点 mag_pouch（原点=袋顶中心、软袋向下
	#    生长）：倒角盒堆叠软袋质感（大倒角主体 = 帆布鼓胀）+ 顶翻盖 +
	#    黑色硬质供弹口盖 + 前后束带/侧 MOLLE 织带暗示 + 插扣
	var pouch := Node3D.new()
	pouch.name = "mag_pouch"
	pouch.position = Vector3(0, -0.053, -0.085)
	root.add_child(pouch)
	GUN_LIB.chamfer_box(pouch, cnv, Vector3(0.074, 0.15, 0.104),
			Vector3(0, -0.075, 0), Vector3.ZERO, 0.006, 12)
	GUN_LIB.chamfer_box(pouch, cnv, Vector3(0.078, 0.028, 0.108),
			Vector3(0, -0.012, 0.003), Vector3.ZERO, 0.004, 8)
	GUN_LIB.chamfer_box(pouch, dark, Vector3(0.058, 0.012, 0.088),
			Vector3(0, 0.005, 0), Vector3.ZERO, 0.002, 6)
	for i in 2:
		GUN_LIB.chamfer_box(pouch, web, Vector3(0.078, 0.152, 0.013),
				Vector3(0, -0.075, -0.044 + 0.088 * float(i)),
				Vector3.ZERO, 0.0015, 8)
	for i in 2:
		GUN_LIB.chamfer_box(pouch, web, Vector3(0.01, 0.15, 0.024),
				Vector3(-0.04 + 0.08 * float(i), -0.075, 0),
				Vector3.ZERO, 0.0015, 8)
	GUN_LIB.chamfer_box(pouch, web, Vector3(0.018, 0.024, 0.009),
			Vector3(0, -0.03, -0.0525), Vector3.ZERO, 0.001, 3)
	# ⑨ 后握把（沙黄 AR 式直倾角、指槽防滑纹、后倾 20°）——grip() 顶锚
	#    = 旋转支点，落位下机匣后底
	GUN_LIB.grip(root, fde, 0.092, Vector3(0, -0.05, 0.07), 20.0,
			0.038, 0.054, dark, 3)
	# 护圈 / 扳机
	GUN_LIB.chamfer_box(root, dark, Vector3(0.012, 0.006, 0.075),
			Vector3(0, -0.062, 0.015), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.02, 0.008),
			Vector3(0, -0.05, 0.02), Vector3.ZERO, 0.0006, 2)
	# ⑧ 沙黄聚合物枪托（不可折叠）：托体 + 斜切面贴腮（-7° 侧影下斜）+
	#    底部厚橡胶托底板 + 5 档调长轨 + 档位卡钮 ×2 + 调长扳柄 +
	#    托侧滚花调节钮（torus 侧钮）
	GUN_LIB.chamfer_box(root, fde, Vector3(0.048, 0.08, 0.21),
			Vector3(0, 0.002, 0.24), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, fde, Vector3(0.042, 0.022, 0.18),
			Vector3(0, 0.052, 0.235), Vector3(-7, 0, 0), 0.002, 12)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.052, 0.1, 0.018),
			Vector3(0, -0.006, 0.352), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.028, 0.012, 0.18),
			Vector3(0, -0.046, 0.225), Vector3.ZERO, 0.0015, 6)
	for i in 2:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.032, 0.008, 0.014),
				Vector3(0, -0.034, 0.19 + 0.09 * float(i)), Vector3.ZERO,
				0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.01, 0.016, 0.024),
			Vector3(0.029, -0.034, 0.165), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.torus_ring(root, stl, 0.005, 0.011, Vector3(0.028, 0.03, 0.3),
			Vector3(0, 0, 90))
	GUN_LIB.torus_ring(root, stl, 0.004, 0.01, Vector3(0.027, 0.058, 0.19),
			Vector3(0, 0, 90))
	# ⑩ 两脚架（行军态折叠收拢贴护木下，双腿向后收拢 + 伸缩锁环 +
	#    脚尖金属驻钉）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.03, 0.022, 0.055),
			Vector3(0, -0.014, -0.50), Vector3.ZERO, 0.0015, 6)
	for i in 2:
		var sx := -0.015 + 0.03 * float(i)
		GUN_LIB.barrel(root, dark, 0.24, 0.008, Vector3(sx, -0.03, -0.39),
				Vector3(90, 0, 0), 0, 24)
		GUN_LIB.torus_ring(root, dark, 0.004, 0.01, Vector3(sx, -0.03, -0.47),
				Vector3(90, 0, 0))
		GUN_LIB.chamfer_box(root, stl, Vector3(0.01, 0.008, 0.018),
				Vector3(sx, -0.03, -0.258), Vector3.ZERO, 0.0006, 2)
	# ⑬ 裸顶轨补位折叠机械瞄具（XM157 整体省略）：前准星（基座 + 准星柱 +
	#    护耳双耳）+ 后照门（基座 + 照门片）
	GUN_LIB.chamfer_box(root, dark, Vector3(0.018, 0.01, 0.024),
			Vector3(0, 0.088, -0.53), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.014, 0.005),
			Vector3(0, 0.1, -0.53), Vector3.ZERO, 0.0006, 2)
	for i in 2:
		GUN_LIB.chamfer_box(root, dark, Vector3(0.004, 0.012, 0.01),
				Vector3(-0.008 + 0.016 * float(i), 0.097, -0.53),
				Vector3.ZERO, 0.0006, 2)
	GUN_LIB.chamfer_box(root, dark, Vector3(0.024, 0.01, 0.024),
			Vector3(0, 0.088, 0.105), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.012, 0.006),
			Vector3(0, 0.099, 0.105), Vector3.ZERO, 0.0006, 2)
