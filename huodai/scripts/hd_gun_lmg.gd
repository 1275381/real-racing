class_name HDGunLMG
extends RefCounted
## 机枪册（m250：SIG XM250 体系，6.8×51mm 弹链机枪；qjb201：国产 QJB-201
## 班用机枪，5.8×42mm；m3：三角洲 S12「微光」赛季 M3 通用机枪——原型德国
## MG3，MG42 改 7.62×51 NATO）高模几何体：用 HDGunLib 工具件（倒角盒/八角
## 棱柱护木/螺纹枪管/消音筒/环件/握把）拼装，M250 FDE 沙黄涂装、QJB201 哑光
## 全黑、M3 深灰枪铁 + 黑色聚合物，体量比 SCAR-H 大一号、枪管更长（考证
## 特征逐条落件，见各枪头注释）。
##
## 契约（与 HDGunAR 同约，保持不动）：
## - 入口：hd_guns.gd `_lmg_build(id)` 分发到本文件 build(id, mats)，语义不变
##   （未知 id 返回空 Node3D 防御不崩）；_lmg_has/_lmg_mag_of/_lmg_scope_anchor
##   仍在 hd_guns.gd 分发表。
## - 弹链袋/弹箱：无弹匣——供弹具 = 本文件枪身根下的独立命名节点
##   （m250 mag_pouch 软式弹链袋 / qjb201 mag_qjb201 硬弹箱，原点=袋/箱顶
##   中心、向下生长），换弹动画匣仍由 hd_guns 统一挂 holder（_lmg_mag_of
##   只切 show=false，pos/size=换弹手锚与掉匣替身缩放基准，同 MK4 先例）。
## - 材质：调用方传参注入（build 收 hd_guns._lmg_mats() 字典），本文件零材质
##   创建——材质唯一出处纪律，与 HDGunLib/HDGunAR 同约。
## - 典型挂件（m250 XM157 火控镜 / qjb201 QMK-204 3x 镜）按考证清单「可整体
##   省略只留裸顶轨」处理：镜体不落件，顶轨放倒态机械瞄具备位（装配瞄具
##   仍走 _finish_gun 统一挂）。
##
## 顶点账目（公式口径，循环展开；运行时以 HDGunLib.count_vertices 实测为准）：
##   m250   基线 3429（93 盒×24 + 21 柱×57，逐行清点见 HDGunLib.POLY_BASE 注）
##          → 实测 33386；门槛 = 8× 基线 = 27432，见 HDGunLib.POLY_MIN["m250"]
##          （test_huodai.gd 实测断言）。
##   qjb201 基线 4953（166 盒×24 + 17 柱×57，逐行清点见 HDGunLib.POLY_BASE
##          注——R1~R4 验收修复 2026-11-02 机械重清点；R5 2026-11-03 弹链弧
##          9+2→11+2 节 +2 盒）→ 门槛 = 8× 基线 = 39624，见
##          HDGunLib.POLY_MIN["qjb201"]（R4 实测 51007，R5 实测 51321）。
##   m3     基线 3129（90 盒×24 + 17 柱×57，逐行清点见 HDGunLib.POLY_BASE
##          注——2026-11-06 并册机械清点）→ 门槛 = 8× 基线 = 25032，见
##          HDGunLib.POLY_MIN["m3"]（test_huodai.gd 实测断言）。

const GUN_LIB := preload("res://scripts/hd_gunlib.gd")


## 统一入口：按 id 拼一把枪身根；未知 id 返回空 Node3D（防御不崩）
static func build(id: String, mats: Dictionary) -> Node3D:
	var root := Node3D.new()
	match id:
		"m250":
			_m250(mats, root)
		"qjb201":
			_lmg_qjb201(mats, root)
		"m3":
			_lmg_m3(mats, root)
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


## QJB201 机枪（国产 QJB-201 班用机枪，5.8×42mm DBP-191，785 发每分，75 发
## 弹箱，扳机延迟 0.25s）考证特征逐条落件（2026-11-02 并册，哑光全黑配色，
## 几何体走本册 build 分发；参考 huodai/out/ref_qjb201/ref_01~11）：
## 【R5 验收修复 2026-11-03（第 5 轮验收 9/11、相似度 78% 未过——六条
##   意见逐条落件）：①弹链弧再外抛成「箱口→机匣完整饱满大弧」视觉中心
##   （9+2→11+2 节、控制点 x -0.064→-0.085、链节 16×14×30→18×16×32、
##   弹箱下探 14mm 加长外露段）、②聚合物/金属反差再拉大（qjpoly
##   0.038→0.030 + glow 0.42→0.30，qjrec 粗糙 0.45→0.40）、③白刻印加大
##   （主行 18→24mm 高 20→26mm 宽 + 白度 0.78→0.86/发光 0.7→0.85）、
##   ④弹匣井口环体量全线加大 + probe_shot 补底部视角出证（well 图）、
##   ⑤拉机柄体量再加大（杆 95→115/柄头 d30→d38 l38→52）、⑥弹箱提手
##   加大成可辨拱把（下探让出顶面净空 17mm、双竖柱外移贴箱缘 + probe
##   belt 机位带出提手）】：
## 【R1 验收修复 2026-11-02（第 1 轮验收 6.5/11、相似度 55% 未过——九条
##   意见逐条落件）：③弹链链节加大加密贝塞尔外抛弧（原 5+2 节判「完全
##   缺失」）、⑦脚架全线加大贴护套、⑤散热孔改圆形亮钢孔衬成排（原暗
##   条黑底零对比）、⑥消焰器加长加大泄压槽 6 道亮钢、⑫白刻印加大两行、
##   ②弹箱体量加大+左侧供弹口/受弹口/弹匣井可辨造型、⑧骨架托细杆大
##   镂空+调长齿条、⑩拉机柄加大+端帽】；ADS 红点镜挂载细化在 hd_guns.gd
##   _scope_visual（detail 参数仅 qjb201 生效）：
## ①方正长方体机匣 + 顶部全长皮卡汀尼导轨裸露、无固定提把（维基
##   「picatinny rail on top of receiver」——供弹盖短、导轨在后方）
## ②下挂式供弹具挂机匣正下方（非侧挂）：默认 75 发硬弹箱 = 独立命名节点
##   mag_qjb201（原点=箱顶中心、箱体向下生长，M250 mag_pouch 契约）
## ③金黄色弹链从弹箱上方弧形外露供入机匣——黄铜链节×5 沿弧排布（全枪
##   唯一暖金 = 最醒目识别件，ref_01/05/06/09/10 视觉直读）
## ④双路供弹系统：左侧弹链受弹口 + 底部弹匣井（QBZ-191 30 发匣兼容，
##   ref_01 面板「双路供弹系统支持弹链或弹匣供弹」+ 维基锚点）
## ⑤粗重枪管 + 圆柱形带散热孔枪管护套（机枪级重型枪管：圆筒护套 + 上侧
##   斜置散热长孔×10）
## ⑥枪口圆柱形消焰器侧面泄压孔（鸟笼式：筒体 + 四向纵长槽 + 前挡环）
## ⑦两脚架位于护套前下方、行军态折叠向后收纳贴护套（双腿 + 锁环 + 驻钉）
## ⑧骨架式聚合物枪托：上下双杆 + 斜撑大面积镂空 + 可调托底板/贴腮板
##   （现实原型侧向折叠 + 可调贴腮/托底，维基锚点）
## ⑨独立手枪式黑色聚合物握把（grip 高模件，HOLD_DELTA 与 m250 同锚）
## ⑩拉机柄非随动式右置（维基「non-reciprocating charging handle on right」
##   现实锚点；游戏截图多报左置两说并存，按右侧落）
## ⑪配色哑光全黑/深灰：金属机匣黑 + 聚合物哑黑 + 亮钢小件（蓝金「珍珑谷」
##   限定皮肤与灰绿迷彩软袋态不入册，默认涂装）
## ⑫机匣右侧白色型号刻印（ref_01 读「CM-3300x2」样式，白刻印长条+口径行）
## ⑬全长顶轨裸露可自挂瞄具（QMK-204 3x 现实标配整体省略只留裸轨——补
##   放倒态机械瞄具前后各一，tenglong 放倒先例；改装镜走通用挂载）
## ⑭弹种 5.8×42mm（DBP-191）；抛壳窗右置带防尘盖、快慢机右置、机匣销×2
static func _lmg_qjb201(mats: Dictionary, root: Node3D) -> void:
	var rec: StandardMaterial3D = mats["qjrec"]     # ⑪ 金属机匣黑（机匣/轨/护套）
	var poly: StandardMaterial3D = mats["qjpoly"]   # ⑪ 聚合物哑光黑（箱/托/握把）
	var dk: StandardMaterial3D = mats["dark"]       # ⑪ 近黑负形（散热孔/消焰器）
	var stl: StandardMaterial3D = mats["qjsteel"]   # ⑪ 亮钢小件（箍环/销/驻钉）
	var brs: StandardMaterial3D = mats["brass"]     # ③ 黄铜弹链（唯一暖金）
	var mrk: StandardMaterial3D = mats["qjmark"]    # ⑫ 白色刻印（型号/口径行）
	# ① 方正长方体机匣（s24 高分段大平面）+ 下机匣扳机座——「方正」读法全靠
	#    平直大面无鼓无收腰，z -0.20..0.17
	GUN_LIB.chamfer_box(root, rec, Vector3(0.058, 0.064, 0.37),
			Vector3(0, 0.026, -0.015), Vector3.ZERO, 0.0035, 28)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.050, 0.042, 0.13),
			Vector3(0, -0.024, 0.065), Vector3.ZERO, 0.0025, 14)
	# ①⑬ 顶部全长导轨：jacket 段桥垫 + 单根轨基直通机匣尾（z -0.565..0.10
	#    连续不中断，无固定提把——裸轨形态）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.032, 0.016, 0.40),
			Vector3(0, 0.0525, -0.375), Vector3.ZERO, 0.002, 10)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.026, 0.011, 0.665),
			Vector3(0, 0.0645, -0.2325), Vector3.ZERO, 0.0015, 16)
	for i in 8:
		# ①⑬ 前段楔齿 ×8（R2 6→8 加密——护套段全长轨视觉更密，步距
		#    0.055；-0.21 前让位供弹盖）
		GUN_LIB.chamfer_box(root, rec, Vector3(0.030, 0.006, 0.016),
				Vector3(0, 0.0715, -0.535 + 0.055 * float(i)), Vector3.ZERO,
				0.0012, 5)
	for i in 3:
		# ①⑬ 后段楔齿 ×3（供弹盖后到机匣尾）
		GUN_LIB.chamfer_box(root, rec, Vector3(0.030, 0.006, 0.016),
				Vector3(0, 0.0715, -0.06 + 0.0725 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ① 短供弹盖（维基「供弹盖短、导轨在后方」：嵌在轨间前段、低于齿顶一档）
	#    + 左右轨缘条 + 盖面防滑纹 ×3 + 左缘铰链线（m250 供弹盖同法）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.046, 0.009, 0.105),
			Vector3(0, 0.064, -0.1425), Vector3.ZERO, 0.0015, 10)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.005, 0.014, 0.105),
				Vector3(0.0125 * float(sx), 0.0645, -0.1425), Vector3.ZERO,
				0.001, 6)
	for i in 5:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.038, 0.002, 0.010),
				Vector3(0, 0.0685, -0.176 + 0.0165 * float(i)), Vector3.ZERO,
				0.0008, 2)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.003, 0.095),
			Vector3(-0.0145, 0.0705, -0.1425), Vector3.ZERO, 0.0006, 2)
	# ⑤ 圆柱形枪管护套（seg48 圆筒 + 壁厚内衬）+ 前后收口箍（亮钢环读
	#    「套筒接缝」）——机枪级重型枪管的粗径读法（d 0.054 vs 枪管 0.028）
	GUN_LIB.tube(root, rec, 0.40, 0.054, Vector3(0, 0.026, -0.375),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 48)
	GUN_LIB.torus_ring(root, stl, 0.024, 0.030, Vector3(0, 0.026, -0.172),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, stl, 0.0225, 0.0285, Vector3(0, 0.026, -0.578),
			Vector3(90, 0, 0))
	# ⑤ 护套散热孔 ×26（R4 验收修复 2026-11-02：连续两轮判「读不出成排
	#    圆形散热孔」——R2 亮钢钉/R3 亮钢圆片在主图光照下读「零星暗点」
	#    （亮件读铆钉不读孔）；R4 反转读法做「真开孔」：dk 深黑大孔衬
	#    （0.024 见方近圆倒角盒、凸 4mm）嵌中灰护套（qjrec 0.150 vs dk
	#    0.06 对比 2.5 倍），灰筒黑孔才读「通孔」；±65° 每侧 7 站 +
	#    ±90° 正侧每侧 6 站错半步，圆周角 θ 处 pos=(r·sinθ, y+r·cosθ)、
	#    贴面转角 90°−θ 同 M250 法）
	var vent_r := 0.0285
	for deg in [65.0, -65.0]:
		var th0 := deg_to_rad(float(deg))
		for i in 7:
			GUN_LIB.chamfer_box(root, dk, Vector3(0.008, 0.024, 0.024),
					Vector3(vent_r * sin(th0), 0.026 + vent_r * cos(th0),
							-0.22 - 0.056 * float(i)),
					Vector3(0, 0, 90.0 - float(deg)), 0.006, 8)
	for deg in [90.0, -90.0]:
		var th2 := deg_to_rad(float(deg))
		for i in 6:
			GUN_LIB.chamfer_box(root, dk, Vector3(0.008, 0.024, 0.024),
					Vector3(vent_r * sin(th2), 0.026 + vent_r * cos(th2),
							-0.25 - 0.056 * float(i)),
					Vector3(0, 0, 90.0 - float(deg)), 0.006, 8)
	# ⑤ 粗重枪管裸露段（护套前短露 + 螺纹环 1 道）
	GUN_LIB.barrel(root, dk, 0.04, 0.028, Vector3(0, 0.026, -0.595),
			Vector3(90, 0, 0), 1, 36)
	# ⑥ 圆柱形消焰器（鸟笼式——R2 起历轮加大；R6→R7 验收修复 2026-11-03：
	#    R6 判「棱柱感偏方——方柱多面体+方形泄压孔+前缘实心」——实锤
	#    根因：R6 的 12 条 8mm 宽亮钢条贴在周长 116mm 笼筒上盖掉 96mm，
	#    每条亮条即一道弦平面 → 整筒读作 12 棱柱；R7 反转成真鸟笼语汇：
	#    笼筒提亮 stl 钢筒 64 段（亮曲面出连续高光读「圆柱」）+ 6 道 dk
	#    暗槽条（经典鸟笼 6 长槽，槽间 13mm 亮弧自然连成圆轮廓，暗槽
	#    外面仅凸 0.5mm 读「开槽」不读「棱」）；前挡环收平齐筒径消
	#    「阶梯块」；膛口暗环推出端面 1mm——前端读「中心通孔」不实心
	GUN_LIB.tube(root, dk, 0.016, 0.038, Vector3(0, 0.026, -0.623),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 24)
	GUN_LIB.tube(root, stl, 0.064, 0.037, Vector3(0, 0.026, -0.663),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 64)
	GUN_LIB.torus_ring(root, stl, 0.0148, 0.0075, Vector3(0, 0.026, -0.6955),
			Vector3(90, 0, 0))
	GUN_LIB.barrel(root, stl, 0.022, 0.019, Vector3(0, 0.026, -0.703),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.tube(root, dk, 0.008, 0.0155, Vector3(0, 0.026, -0.711),
			Vector3(90, 0, 0), 0.0005, 0, null, 2, 20)
	var mz_r := 0.0160
	for deg in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
		var th1 := deg_to_rad(float(deg))
		GUN_LIB.chamfer_box(root, dk, Vector3(0.006, 0.006, 0.052),
				Vector3(mz_r * sin(th1), 0.026 + mz_r * cos(th1), -0.663),
				Vector3(0, 0, 90.0 - float(deg)), 0.0006, 3)
	# ⑥② 枪管护套口消音器锁紧接口环（QJB201 可挂消音器的接口座——stl
	#    亮钢环嵌裸枪管段，ref 消音形态接口；兼作枪管肩环读「可扩展」）
	GUN_LIB.torus_ring(root, stl, 0.0115, 0.0165, Vector3(0, 0.026, -0.602),
			Vector3(90, 0, 0))
	# ② 机匣底弹箱挂框（下挂式供弹具的挂接轨，机匣正下方 z -0.1825..0.0025；
	#    R5 2026-11-03：弹箱下探 14mm（给顶面提手让净空 + 加长弹链外露段）
	#    ——挂轨加高 12→16mm 随之下延（y -0.022..-0.006 上贴机匣底、下压
	#    箱顶 1mm，箱轨始终相连不悬空）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.056, 0.016, 0.185),
			Vector3(0, -0.014, -0.09), Vector3.ZERO, 0.002, 10)
	# ② 75 发硬弹箱 = 独立命名节点 mag_qjb201（原点=箱顶中心、向下生长；
	#    R1 加大体量 0.094×0.135×0.190（ref_05 弹箱横向突出机匣两侧、垂深
	#    约机匣 2 倍）；R4 验收修复 2026-11-02：判「表面平坦无细节且挂位
	#    偏后」——挂位前移 10mm（z -0.10→-0.11）+ 顶后携行提手（拱把：
	#    双竖柱+横梁）+ 前上角锁扣 ×2 + 底缘排泥缝；R5 2026-11-03：整箱
	#    下探 14mm（y -0.009→-0.023）——箱顶与机匣底之间让出拱把净空带
	#    （提手加大成可辨拱把，见下）+ 弹链弧起点随之下移、外露段更长：
	#    大倒角箱体 + 底板 + 侧筋 ×4 + 前下收角 + 前锁扣 + 提手/角锁扣/
	#    排泥缝 + 导链座/盖/出链口
	var box := Node3D.new()
	box.name = "mag_qjb201"
	box.position = Vector3(0, -0.023, -0.11)
	root.add_child(box)
	GUN_LIB.chamfer_box(box, poly, Vector3(0.094, 0.135, 0.190),
			Vector3(0, -0.0675, 0), Vector3.ZERO, 0.005, 20)
	GUN_LIB.chamfer_box(box, dk, Vector3(0.096, 0.012, 0.192),
			Vector3(0, -0.135, 0), Vector3.ZERO, 0.0015, 8)
	for sz in [-1.0, 1.0]:
		for zz in [-0.026, 0.026]:
			GUN_LIB.chamfer_box(box, poly, Vector3(0.098, 0.100, 0.012),
					Vector3(0, -0.0675, zz + 0.049 * float(sz)), Vector3.ZERO,
					0.0015, 6)
	GUN_LIB.chamfer_box(box, poly, Vector3(0.088, 0.028, 0.030),
			Vector3(0, -0.121, -0.094), Vector3(10, 0, 0), 0.002, 6)
	GUN_LIB.chamfer_box(box, stl, Vector3(0.026, 0.022, 0.012),
			Vector3(0, -0.026, -0.095), Vector3.ZERO, 0.0008, 3)
	# ② R5 提手（顶后拱形携行把：双竖柱 + 横梁）；R6→R7 验收修复
	#    2026-11-03：R6 判「提手连成一片块状、锁扣不可辨」——实锤根因：
	#    R5/R6 提手横梁与挂框轨带同层穿插（挂轨占箱局部 y 0.001..0.017
	#    × |x|<0.028，梁 y 0.005..0.017 中段整个埋进轨里，只露两端
	#    8mm——几何上不可能读出拱形）。R7 整体后移到箱后上角「挂轨
	#    外露带」（箱 z 局部 -0.095..-0.0725 无轨）：双竖柱+通宽横梁
	#    完整成拱（梁顶 1mm 净空于机匣底、梁宽 76mm 超出轨两侧各 20mm
	#    显独立轮廓），横梁后缘+竖柱外缘 stl 亮钢描边，角锁扣从「藏箱
	#    顶平面内」抬高成箱后上角可辨凸台（y 0..10mm、轨宽外 x ±0.049）
	GUN_LIB.chamfer_box(box, poly, Vector3(0.012, 0.015, 0.014),
			Vector3(-0.030, 0.0075, -0.084), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(box, poly, Vector3(0.012, 0.015, 0.014),
			Vector3(0.030, 0.0075, -0.084), Vector3.ZERO, 0.001, 4)
	GUN_LIB.chamfer_box(box, poly, Vector3(0.076, 0.007, 0.022),
			Vector3(0, 0.0125, -0.0835), Vector3.ZERO, 0.0015, 5)
	GUN_LIB.chamfer_box(box, stl, Vector3(0.070, 0.0025, 0.003),
			Vector3(0, 0.011, -0.0935), Vector3.ZERO, 0.0006, 3)
	for hz in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(box, stl, Vector3(0.003, 0.013, 0.012),
				Vector3(0.0365 * hz, 0.0075, -0.084), Vector3.ZERO,
				0.0006, 3)
		GUN_LIB.chamfer_box(box, stl, Vector3(0.014, 0.010, 0.012),
				Vector3(0.042 * hz, 0.005, -0.070), Vector3.ZERO,
				0.0008, 3)
	# ② R4 底缘排泥缝（dk 通长窄缝读「箱底功能缝」）
	GUN_LIB.chamfer_box(box, dk, Vector3(0.098, 0.004, 0.150),
			Vector3(0, -0.128, 0.012), Vector3.ZERO, 0.0006, 3)
	# ②③ 箱左侧弹链供弹口（导链座：突出箱顶左前正对受弹口 + 斜口盖 +
	#    出链口黄铜链头探出——弹链③起点，「供弹口」可辨造型）
	GUN_LIB.chamfer_box(box, dk, Vector3(0.042, 0.024, 0.064),
			Vector3(-0.024, 0.000, -0.008), Vector3.ZERO, 0.002, 8)
	GUN_LIB.chamfer_box(box, poly, Vector3(0.038, 0.010, 0.056),
			Vector3(-0.024, 0.013, -0.010), Vector3(-6, 0, 0), 0.001, 4)
	GUN_LIB.chamfer_box(box, brs, Vector3(0.014, 0.012, 0.028),
			Vector3(-0.040, 0.002, -0.008), Vector3(50, 0, 0), 0.0008, 3)
	# ③ 金黄弹链弧形外露（全枪最醒目识别件——R1~R5 迭代史见 git 历史）；
	#    R6 2026-11-04 用户定案「弹链宽度和长度都不太真实」：R5 为可辨性
	#    放大的体量收回真实 5.8mm 档——链节 18×16×32→12×11×24（5.8×42
	#    弹链节距/截面实测档）、节数 11+2→8+2、控制点 x -0.085→-0.066
	#    （弧顶外缘=机匣面外 ~25mm）、B 端外露垂距 48→36mm：仍是「箱口→
	#    受弹口」完整饱满弧，但读作短促贴身的真弹链而非大吊索
	var belt_a := Vector3(-0.046, -0.018, -0.124)
	var belt_c := Vector3(-0.066, 0.004, -0.112)
	var belt_b := Vector3(-0.040, 0.018, -0.098)
	for i in 9:
		var t := float(i) / 8.0
		var p := belt_a.lerp(belt_c, t).lerp(belt_c.lerp(belt_b, t), t)
		GUN_LIB.chamfer_box(root, brs, Vector3(0.012, 0.011, 0.024),
				p, Vector3(70.0 - 11.5 * float(i), 0, -28.0 + 5.2 * float(i)),
				0.0008, 5)
	GUN_LIB.chamfer_box(root, brs, Vector3(0.012, 0.011, 0.024),
			Vector3(-0.049, -0.028, -0.127), Vector3(48, 0, -6), 0.0008, 5)
	GUN_LIB.chamfer_box(root, brs, Vector3(0.012, 0.011, 0.024),
			Vector3(-0.051, -0.038, -0.130), Vector3(42, 0, -3), 0.0008, 5)
	# ④ 双路供弹之一：左侧弹链受弹口（R1 验收修复：原框 5mm 薄片判不可
	#    辨——外凸受弹座 + 黑色受弹嘴 + 亮钢口沿销，③链节终点正对口）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.008, 0.036, 0.088),
			Vector3(-0.032, 0.022, -0.088), Vector3.ZERO, 0.0015, 8)
	GUN_LIB.chamfer_box(root, dk, Vector3(0.004, 0.026, 0.068),
			Vector3(-0.030, 0.021, -0.088), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.003, 0.004, 0.078),
			Vector3(-0.0365, 0.036, -0.088), Vector3.ZERO, 0.0006, 2)
	# ④ 双路供弹之二：底部弹匣井（QBZ-191 30 发匣兼容口，下机匣前底·
	#    弹箱后方握把之前——R3 加外凸井口环；R4 竖框加高；R5 全线加大；
	#    R6 验收修复 2026-11-03：判「well 特写未见井口边框——疑被弹箱
	#    遮挡」实锤（井竖框旧区间 z -0.013..0.065 整段落在弹箱 z 范围
	#    -0.205..0.085 内、箱底又比井口低 88mm——正下方视线被箱体挡死）：
	#    井口整体前移 z 0.026→0.10（竖框区间 0.061..0.139 完全越过弹箱
	#    前缘 0.085，正下方视线直达井口；后框缘 0.061 在握把前缘 0.044
	#    前方不穿模——真机「井贴握把前」布局；井座顶仍挂下机匣底）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.054, 0.032, 0.052),
			Vector3(0, -0.058, 0.10), Vector3.ZERO, 0.002, 8)
	GUN_LIB.chamfer_box(root, dk, Vector3(0.040, 0.014, 0.044),
			Vector3(0, -0.070, 0.10), Vector3.ZERO, 0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.050, 0.022, 0.016),
			Vector3(0, -0.063, 0.074), Vector3(-8, 0, 0), 0.0008, 5)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.013, 0.028, 0.078),
				Vector3(0.025 * float(sx), -0.061, 0.10), Vector3.ZERO,
				0.0008, 5)
		GUN_LIB.chamfer_box(root, stl, Vector3(0.007, 0.010, 0.040),
				Vector3(0.029 * float(sx), -0.066, 0.10), Vector3.ZERO,
				0.0006, 3)
	# ⑩ 拉机柄非随动式右置（机匣右侧靠前——R3/R4 连续加大；R5 验收修复
	#    2026-11-03：判「小型不够醒目」——体量再上一档：杆 95→115mm 加粗
	#    16×14→20×18、柄头圆柱 d30→38 加长 38→52（凸出机匣面 52mm）、
	#    前伸下折弯钩 18×18×26→24×24×32 读「非随动拉机柄」造型，静置不随动）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.020, 0.018, 0.115),
			Vector3(0.036, 0.043, -0.150), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.barrel(root, stl, 0.052, 0.038, Vector3(0.055, 0.043, -0.135),
			Vector3(0, 0, 90), 0, 20)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.024, 0.024, 0.032),
			Vector3(0.050, 0.033, -0.096), Vector3(25, 0, 0), 0.0008, 4)
	# ⑭ 右侧抛壳窗（凹嵌 + 防尘盖）+ 快慢机 + 机匣右侧亮钢铆钉排 ×6
	#    （m250 护木内六角螺丝同法——机匣面板装配铆钉读「金属机匣拼装」，
	#    亦拉开 rec 金属面与 poly 聚合件的反差）
	GUN_LIB.chamfer_box(root, dk, Vector3(0.004, 0.024, 0.072),
			Vector3(0.0295, 0.030, -0.048), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.005, 0.026, 0.077),
			Vector3(0.0315, 0.030, -0.048), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.005, 0.013, 0.028),
			Vector3(0.0305, -0.004, 0.098), Vector3.ZERO, 0.0006, 2)
	for rz in [0.028, 0.062, 0.096, 0.130]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.003, 0.004, 0.004),
				Vector3(0.0298, 0.048, float(rz)), Vector3.ZERO, 0.0005, 6)
	# ⑫ 机匣右侧白色型号刻印（R4 移受光中带 + 5+2 段；R5 加大；R6 验收
	#    修复 2026-11-03：R5 后主视图/handle 特写仍判「未检出任何白色
	#    文字刻印」——主图上机匣右面刻印段仅 ~15px 高，小而不可读是
	#    物理现实：主行再加一档 24→30mm 高、26→34mm 宽、段距 33mm、
	#    y 0.030→0.036 上移受光带；副行 13→16mm 高、28→36mm 宽、
	#    y 0.013→0.010；凸出量 6mm 不变（再凸读浮贴）；并专拍刻印特写
	#    shot_gun_qjb201_mark（probe ⑲ 段）出可读证据；R7 验收修复
	#    2026-11-03（判 mark 特写「一整块纯白高亮矩形、无分段结构」）
	#    ——实锤根因：主行段长 34mm > 段距 33mm，相邻段搭接 1mm，
	#    5 段物理上连成通长白带；R7 段长 34→24mm（段间 9mm 断缝 =
	#    特写下 ~25px 暗隔，读「5 个独立字符块」）、副行 36→26mm
	#    （断缝 14mm），配合 qjmark 发光收敛（hd_guns R7）出可读证据
	for i in 5:
		GUN_LIB.chamfer_box(root, mrk, Vector3(0.007, 0.030, 0.024),
				Vector3(0.0315, 0.036, 0.005 + 0.033 * float(i)),
				Vector3.ZERO, 0.0008, 4)
	for zz in [-0.020, 0.020]:
		GUN_LIB.chamfer_box(root, mrk, Vector3(0.007, 0.016, 0.026),
				Vector3(0.0315, 0.010, 0.068 + float(zz)), Vector3.ZERO,
				0.0008, 4)
	# ⑬ 放倒态机械瞄具前后各一（裸轨备位：贴轨薄片 + 侧铰链凸，tenglong
	#    放倒先例；_finish_gun iron 不叠兜底片，改装镜走通用挂载）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.024, 0.005, 0.020),
			Vector3(0, 0.0735, 0.112), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.020, 0.005, 0.018),
			Vector3(0, 0.0735, -0.50), Vector3.ZERO, 0.0008, 6)
	for hz in [0.112, -0.50]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.006, 0.007, 0.006),
				Vector3(0.014, 0.0745, float(hz)), Vector3.ZERO, 0.0006, 2)
	# ⑦ 两脚架（行军态折叠向后收纳贴护套下——R3 验收修复 2026-11-02：
	#    R2 后仍判「无法确认」——全线再加一档：挂座加宽 40→46mm、腿径
	#    9→11mm、膝铰链块/锁环/驻钉/驻锄板同步加大 + 补脚架特写
	#    shot_gun_qjb201_bipod（probe_shot ⑲ 段）：挂座 + 铰链销 + 双腿
	#    沿护套底向后收拢 + 膝铰链块 ×2 + 伸缩锁环 ×2 + 驻钉/驻锄板 ×2
	GUN_LIB.chamfer_box(root, rec, Vector3(0.052, 0.030, 0.070),
			Vector3(0, -0.016, -0.50), Vector3.ZERO, 0.0015, 8)
	GUN_LIB.torus_ring(root, stl, 0.005, 0.012, Vector3(0, -0.022, -0.526),
			Vector3(0, 0, 90), 24, 12)
	for sx in [-1.0, 1.0]:
		var lx := float(sx)
		GUN_LIB.barrel(root, dk, 0.21, 0.013,
				Vector3(0.021 * lx, -0.025, -0.405),
				Vector3(90, -3.0 * lx, 0), 0, 24)
		GUN_LIB.chamfer_box(root, rec, Vector3(0.018, 0.018, 0.026),
				Vector3(0.021 * lx, -0.025, -0.492), Vector3.ZERO,
				0.0008, 5)
		GUN_LIB.torus_ring(root, dk, 0.007, 0.015,
				Vector3(0.021 * lx, -0.025, -0.472), Vector3(90, 0, 0))
		GUN_LIB.chamfer_box(root, stl, Vector3(0.016, 0.014, 0.026),
				Vector3(0.021 * lx, -0.025, -0.298), Vector3.ZERO,
				0.0006, 4)
		# ⑦ 脚尖驻锄横板（R2 加——折叠终端加大读「两脚架驻锄」）
		GUN_LIB.chamfer_box(root, dk, Vector3(0.028, 0.010, 0.020),
				Vector3(0.021 * lx, -0.033, -0.288), Vector3.ZERO,
				0.0008, 5)
	# ⑧ 骨架式聚合物枪托（R2 验收修复 2026-11-02：R1 只减薄杆仍判「实心
	#    厚板未开镂空」——大面积减重孔遍布托全长（an94 托杆孔/k416 托侧孔
	#    同法暗板负形）：铰接座收小开孔 + 上/下杆侧开长孔 3+2×每侧 +
	#    托底立板开大孔 ×2 + 两杆间 52mm 大镂空 + 双斜撑交叉 + 调长齿条 ×4
	#    + 加大肩形托底板读「可调托底板轮廓」）
	GUN_LIB.chamfer_box(root, poly, Vector3(0.040, 0.046, 0.030),
			Vector3(0, 0.024, 0.187), Vector3.ZERO, 0.002, 10)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, dk, Vector3(0.003, 0.020, 0.018),
				Vector3(0.0185 * float(sx), 0.024, 0.187), Vector3.ZERO,
				0.0006, 6)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.024, 0.016, 0.118),
			Vector3(0, 0.049, 0.258), Vector3.ZERO, 0.0015, 12)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.024, 0.014, 0.108),
			Vector3(0, -0.018, 0.252), Vector3.ZERO, 0.0015, 8)
	for sx in [-1.0, 1.0]:
		var hx := float(sx)
		for i in 3:
			GUN_LIB.chamfer_box(root, dk, Vector3(0.003, 0.006, 0.024),
					Vector3(0.0125 * hx, 0.049, 0.222 + 0.036 * float(i)),
					Vector3.ZERO, 0.0006, 6)
		for i in 2:
			GUN_LIB.chamfer_box(root, dk, Vector3(0.003, 0.005, 0.022),
					Vector3(0.0125 * hx, -0.018, 0.228 + 0.046 * float(i)),
					Vector3.ZERO, 0.0006, 6)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.014, 0.009, 0.112),
			Vector3(0, 0.018, 0.258), Vector3(16, 0, 0), 0.001, 6)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.013, 0.008, 0.090),
			Vector3(0, 0.006, 0.296), Vector3(-14, 0, 0), 0.001, 5)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.030, 0.086, 0.022),
			Vector3(0, 0.014, 0.328), Vector3.ZERO, 0.002, 12)
	for iy in [0.000, 0.028]:
		GUN_LIB.chamfer_box(root, dk, Vector3(0.030, 0.028, 0.014),
				Vector3(0, iy + 0.014, 0.328), Vector3.ZERO, 0.0008, 4)
	for iy in [-0.008, 0.008, 0.024, 0.040]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.026, 0.004, 0.005),
				Vector3(0, iy + 0.014, 0.340), Vector3.ZERO, 0.0006, 4)
	GUN_LIB.chamfer_box(root, dk, Vector3(0.044, 0.104, 0.016),
			Vector3(0, 0.012, 0.350), Vector3.ZERO, 0.0015, 8)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.016, 0.022),
				Vector3(0.023 * float(sx), 0.030, 0.338), Vector3.ZERO,
				0.0006, 3)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.032, 0.016, 0.074),
			Vector3(0, 0.064, 0.252), Vector3.ZERO, 0.0015, 8)
	# ⑨ 手枪式黑色聚合物握把（grip 顶锚 = 旋转支点，HOLD_DELTA 与 m250 同式
	#    精算：Δ = MK4 基准 (0,-0.022,-0.0018) − 本锚 (0,-0.05,0.07)）
	GUN_LIB.grip(root, poly, 0.096, Vector3(0, -0.05, 0.07), 20.0,
			0.038, 0.052, dk, 3)
	# 扳机护圈（底梁 + 前后柱）+ 扳机
	GUN_LIB.chamfer_box(root, rec, Vector3(0.012, 0.006, 0.068),
			Vector3(0, -0.061, 0.055), Vector3.ZERO, 0.0008, 3)
	for sz in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.012, 0.028, 0.008),
				Vector3(0, -0.047, 0.055 + 0.034 * float(sz)), Vector3.ZERO,
				0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.022, 0.008),
			Vector3(0, -0.041, 0.052), Vector3(10, 0, 0), 0.0006, 2)
	# QD 背带环 ×2（护套尾下 / 托底左，穿孔轴沿 X = 侧挂环）+ 机匣销 ×2（左）
	GUN_LIB.torus_ring(root, stl, 0.004, 0.010, Vector3(0, -0.024, -0.19),
			Vector3(0, 0, 90))
	GUN_LIB.torus_ring(root, stl, 0.004, 0.010, Vector3(-0.019, 0.004, 0.322),
			Vector3(0, 0, 90))
	for pz in [0.02, 0.132]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.003, 0.008, 0.008),
				Vector3(-0.0295, 0.014, float(pz)), Vector3.ZERO,
				0.0006, 2)


## M3 通用机枪（三角洲 S12「微光」赛季新机枪，2026-11-06 并册；现实原型
## 德国莱茵金属 MG3 通用机枪——MG42 直系改膛 7.62×51 NATO「撕布机」，全枪
## 长 1225mm、空枪约 10.5kg、左侧弹链供弹 DM1/M13/DM6 链节、可快换枪管，
## 维基/军武资料锚点 + ref_08 乌军 MG3 实拍对照）考证特征逐条落件
## （几何体走本册 build 分发，哑光深灰枪铁 + 黑色聚合物，参考
## huodai/out/ref_m3/ref_01~12）：
## 【识别特征1】MG42 系长条椭圆散热孔枪管护筒：护筒占枪管前段全长
##   （z -0.57..-0.13 一根贯通圆筒）、每侧 4 条纵向长椭圆散热槽共 8 条
##   （dk 深黑真开孔读法，qjb201 R4 同法——灰筒黑孔对比 3.7 倍），全枪
##   最醒目剪影元素（ref_01/03/07/10 直读）
## 【识别特征2】左侧弹链供弹、弹箱挂机匣左下：7.62×51 全尺寸黄铜弹链
##   （链节 16×13×34，比 5.8mm 档 qjb201 12×11×24 大一圈）从机匣左侧受弹
##   口外抛弧形喂入，供弹具垂挂机匣左下（ref_01/02/05/10/12 直读）
## 【识别特征3】MG42 式鱼尾形枪托 + 独立手枪握把：托体向后再下扩的鱼尾
##   板式（上脊 + 主托板 -8° 后仰 + 后跟抵肩垫 + 下缘收窄条），握把带握纹
##   与扳机护圈分离（ref_01/05/10 直读）
## ④顶部全长皮卡汀尼导轨（现代改装化设计，架于机匣盖上方）：单根轨基
##   直通机匣尾 + 前后楔齿 6+3，机匣盖嵌于轨缘之间低于齿顶一档
##   （ref_02/05/10/12 直读）
## ⑤供弹具默认 60 发「M3通用机枪平衡弹箱」= 独立命名节点 mag_m3（软式
##   迷彩布 MOLLE 袋型：大倒角鼓胀主体 + 顶翻盖 + 黑色硬质供弹口盖 +
##   横竖 MOLLE 织带 + 插扣 + 底排泥缝，ref_12 UI 直读袋型；90 发硬质
##   弹箱为改装件不入册）；原点=箱顶中心、向下生长，M250 mag_pouch/
##   QJB201 mag_qjb201 契约；箱顶嵌入机匣底挂框内 2mm（井/匣/手锚同源
##   对齐——MCX-LT 教训）
## ⑥枪口阶梯锥形助退/消焰器（MG42 助退器造型）：锁紧环 + 大径筒
##   d40 → 中径筒 d32 → 枪口小径管 d20 两段锥收小 + 膛口暗环 + 侧面
##   泄压孔 ×2（ref_01/07/10 直读）
## ⑦两脚架折叠收拢枪管前段两侧：骨架式三角截面支腿银灰色（m3steel
##   亮钢腿与深色枪身对比明显）向后收拢贴护筒侧下 + 挂座/铰链销/膝铰链
##   块/伸缩锁环/驻锄板（ref_05 改枪界面默认枪态直读）
## ⑧机械瞄具：护筒前段柱形准星（基座 + 准星柱 + 护耳双耳，直立态）+
##   机匣前部觇孔表尺（放倒态低廓贴轨，腾龙/qjb201 放倒先例——给顶轨
##   中段让出瞄具挂位，导轨上另可装翻转照门）；_finish_gun iron 不叠
##   兜底片，改装镜走通用挂载（严禁 sr25 式 pass 分支吞镜）
## ⑨配色深灰枪铁色金属 + 黑色聚合物握把/枪托，默认无花哨涂装、金属
##   微反光（m3rec rough 0.42 vs m3poly rough 1.0，ref_01/10 直读）
## ⑩弹链 7.62×51 无底缘全尺寸弹（黄铜弹壳 + 裸弹头外露成排——链节
##   黄铜件，brass 复用 m250 键，ref_01/02/12 直读）
## ⑪拉机柄左置（MG42 系左置传统）+ 右侧抛壳窗防尘盖 + 快慢机 + 机匣
##   右侧铆钉 ×4 + 机匣销 ×2 + QD 背带环 ×2
static func _lmg_m3(mats: Dictionary, root: Node3D) -> void:
	var rec: StandardMaterial3D = mats["m3rec"]     # ⑨ 深灰枪铁金属（机匣/轨/护筒）
	var poly: StandardMaterial3D = mats["m3poly"]   # ⑨ 黑色聚合物（托/握把）
	var stl: StandardMaterial3D = mats["m3steel"]   # ⑦ 亮钢小件（脚架腿/箍环/销）
	var dk: StandardMaterial3D = mats["m3dk"]       # 负形近黑（散热槽/抛壳窗/膛口环）
	var cam: StandardMaterial3D = mats["m3camo"]    # ⑤ 迷彩弹箱布面
	var web: StandardMaterial3D = mats["m3web"]     # ⑤ MOLLE 织带深棕
	var brs: StandardMaterial3D = mats["brass"]     # ⑩ 黄铜弹链（唯一暖金）
	# ⑨ 机匣主体（s28 高分段大平面，z -0.13..0.17）+ 下机匣扳机座 +
	#    尾接托块——MG3 方正机匣读法
	GUN_LIB.chamfer_box(root, rec, Vector3(0.058, 0.064, 0.30),
			Vector3(0, 0.030, 0.02), Vector3.ZERO, 0.0035, 28)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.050, 0.046, 0.15),
			Vector3(0, -0.026, 0.055), Vector3.ZERO, 0.0025, 14)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.048, 0.054, 0.05),
			Vector3(0, 0.026, 0.185), Vector3.ZERO, 0.0025, 8)
	# ④ 顶部全长导轨：轨基（架于机匣盖上缘，y 0.062..0.074 z -0.1475..0.1675
	#    直通机匣尾）+ 前段楔齿 ×6 + 后段楔齿 ×3（齿位避开前后件留缝）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.026, 0.012, 0.315),
			Vector3(0, 0.068, 0.01), Vector3.ZERO, 0.0015, 16)
	for i in 6:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.030, 0.006, 0.016),
				Vector3(0, 0.077, -0.115 + 0.032 * float(i)), Vector3.ZERO,
				0.0012, 5)
	for i in 3:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.030, 0.006, 0.016),
				Vector3(0, 0.077, 0.075 + 0.032 * float(i)), Vector3.ZERO,
				0.0012, 5)
	# ④ 机匣盖（供弹盖板嵌于轨缘之间，低于齿顶一档）+ 盖面防滑纹 ×4
	GUN_LIB.chamfer_box(root, rec, Vector3(0.040, 0.008, 0.19),
			Vector3(0, 0.058, -0.02), Vector3.ZERO, 0.0015, 10)
	for i in 4:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.026, 0.002, 0.010),
				Vector3(0, 0.0625, -0.085 + 0.04 * float(i)), Vector3.ZERO,
				0.0008, 2)
	# 【识别特征1】MG42 系长条椭圆散热孔护筒：贯通圆筒（seg48 z -0.57..-0.13）
	#    + 前后收口箍（亮钢环读「套筒接缝/快换枪管接口」）+ 每侧 4 条纵向
	#    长椭圆散热槽（±90° 正侧；dk 深黑真开孔凸 4mm——qjb201 R4 反转读法：
	#    深灰筒黑槽对比 3.7 倍读「通槽」，槽端大倒角 0.006 出长椭圆轮廓）
	GUN_LIB.tube(root, rec, 0.44, 0.054, Vector3(0, 0.026, -0.35),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 48)
	GUN_LIB.torus_ring(root, stl, 0.024, 0.031, Vector3(0, 0.026, -0.135),
			Vector3(90, 0, 0))
	GUN_LIB.torus_ring(root, stl, 0.024, 0.030, Vector3(0, 0.026, -0.565),
			Vector3(90, 0, 0))
	for deg in [90.0, -90.0]:
		var th0 := deg_to_rad(float(deg))
		for i in 4:
			GUN_LIB.chamfer_box(root, dk, Vector3(0.008, 0.026, 0.082),
					Vector3(0.027 * sin(th0), 0.026 + 0.027 * cos(th0),
							-0.505 + 0.10 * float(i)),
					Vector3(0, 0, 90.0 - float(deg)), 0.006, 6)
	# ⑥ 裸枪管露段（护筒前短露）+ 阶梯锥形助退/消焰器（MG42 助退器造型：
	#    锁紧环 + 大径筒 d40 + 中径筒 d32 + 枪口小径管 d20 两段锥收小 +
	#    膛口暗环 + 侧面泄压孔 ×2）
	GUN_LIB.barrel(root, dk, 0.035, 0.028, Vector3(0, 0.026, -0.5875),
			Vector3(90, 0, 0), 0, 36)
	GUN_LIB.torus_ring(root, stl, 0.017, 0.023, Vector3(0, 0.026, -0.605),
			Vector3(90, 0, 0))
	GUN_LIB.tube(root, rec, 0.05, 0.040, Vector3(0, 0.026, -0.6325),
			Vector3(90, 0, 0), 0.004, 0, null, 3, 32)
	GUN_LIB.tube(root, rec, 0.03, 0.032, Vector3(0, 0.026, -0.6725),
			Vector3(90, 0, 0), 0.003, 0, null, 3, 24)
	GUN_LIB.barrel(root, dk, 0.016, 0.020, Vector3(0, 0.026, -0.6955),
			Vector3(90, 0, 0), 0, 24)
	GUN_LIB.tube(root, dk, 0.006, 0.013, Vector3(0, 0.026, -0.7065),
			Vector3(90, 0, 0), 0.0005, 0, null, 2, 16)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, dk, Vector3(0.006, 0.010, 0.014),
				Vector3(0.0175 * float(sx), 0.032, -0.6325), Vector3.ZERO,
				0.0006, 3)
	# 【识别特征2】左侧弹链供弹：受弹口框（外凸座 + 黑色受弹嘴 + 亮钢口沿
	#    销，qjb201 ④同法）——⑩ 7.62 全尺寸黄铜弹链外抛弧喂入（链节
	#    16×13×34 比qjb201 5.8 档大一圈，弧顶机匣面外 ~50mm：箱口→受弹口
	#    完整饱满弧 + 尾段 2 节垂入箱口）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.008, 0.036, 0.09),
			Vector3(-0.031, 0.024, -0.055), Vector3.ZERO, 0.0015, 8)
	GUN_LIB.chamfer_box(root, dk, Vector3(0.004, 0.028, 0.07),
			Vector3(-0.0335, 0.023, -0.055), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.003, 0.004, 0.08),
			Vector3(-0.0355, 0.038, -0.055), Vector3.ZERO, 0.0006, 2)
	var belt_a := Vector3(-0.052, -0.008, -0.100)
	var belt_c := Vector3(-0.086, 0.024, -0.082)
	var belt_b := Vector3(-0.042, 0.020, -0.058)
	for i in 9:
		var t := float(i) / 8.0
		var p := belt_a.lerp(belt_c, t).lerp(belt_c.lerp(belt_b, t), t)
		GUN_LIB.chamfer_box(root, brs, Vector3(0.016, 0.013, 0.034),
				p, Vector3(70.0 - 10.0 * float(i), 0, -30.0 + 4.5 * float(i)),
				0.0008, 4)
	GUN_LIB.chamfer_box(root, brs, Vector3(0.016, 0.013, 0.034),
			Vector3(-0.055, -0.016, -0.103), Vector3(58, 0, -24), 0.0008, 4)
	GUN_LIB.chamfer_box(root, brs, Vector3(0.016, 0.013, 0.034),
			Vector3(-0.058, -0.024, -0.106), Vector3(52, 0, -22), 0.0008, 4)
	# ⑤ 机匣底弹箱挂框（下挂供弹具挂接轨，箱顶嵌入框内——MCX-LT 对齐教训：
	#    挂框 y -0.018..-0.002 上贴机匣底、箱顶 -0.016 嵌入框下沿 2mm）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.052, 0.016, 0.16),
			Vector3(0, -0.010, -0.06), Vector3.ZERO, 0.002, 10)
	# ⑤ 60 发平衡弹箱 = 独立命名节点 mag_m3（原点=箱顶中心、向下生长；
	#    软式迷彩布 MOLLE 袋型 ref_12 UI 直读：大倒角鼓胀主体读「软袋」+
	#    顶翻盖 + 黑色硬质供弹口盖 + 横竖 MOLLE 织带 ×4 + 插扣 + 底排泥缝；
	#    挂机匣左下 x -0.014 随弹链左偏——ref_01/12 弹箱垂挂左下位）
	var pouch := Node3D.new()
	pouch.name = "mag_m3"
	pouch.position = Vector3(-0.014, -0.016, -0.075)
	root.add_child(pouch)
	GUN_LIB.chamfer_box(pouch, cam, Vector3(0.088, 0.155, 0.120),
			Vector3(0, -0.0775, 0), Vector3.ZERO, 0.006, 16)
	GUN_LIB.chamfer_box(pouch, cam, Vector3(0.092, 0.030, 0.124),
			Vector3(0, -0.013, 0.003), Vector3.ZERO, 0.004, 8)
	GUN_LIB.chamfer_box(pouch, dk, Vector3(0.056, 0.012, 0.086),
			Vector3(0, 0.002, -0.008), Vector3.ZERO, 0.002, 6)
	for i in 2:
		GUN_LIB.chamfer_box(pouch, web, Vector3(0.090, 0.157, 0.014),
				Vector3(0, -0.0775, -0.046 + 0.092 * float(i)),
				Vector3.ZERO, 0.0015, 8)
	for i in 2:
		GUN_LIB.chamfer_box(pouch, web, Vector3(0.010, 0.155, 0.026),
				Vector3(-0.043 + 0.086 * float(i), -0.0775, 0),
				Vector3.ZERO, 0.0015, 8)
	GUN_LIB.chamfer_box(pouch, web, Vector3(0.018, 0.024, 0.010),
			Vector3(0, -0.038, -0.0625), Vector3.ZERO, 0.001, 3)
	GUN_LIB.chamfer_box(pouch, dk, Vector3(0.090, 0.004, 0.09),
			Vector3(0, -0.152, 0.006), Vector3.ZERO, 0.0006, 3)
	# 【识别特征3】⑨ 独立手枪握把（黑色聚合物带握纹，grip 顶锚 = 旋转支点
	#    与 m250/qjb201 同锚同式——HOLD_DELTA 机枪档 (0,0.028,-0.0718)）
	GUN_LIB.grip(root, poly, 0.096, Vector3(0, -0.05, 0.07), 20.0,
			0.038, 0.052, stl, 3)
	# 扳机护圈（底梁 + 前后柱）+ 扳机——握把带护纹、护圈分离读法
	GUN_LIB.chamfer_box(root, rec, Vector3(0.012, 0.006, 0.075),
			Vector3(0, -0.063, 0.055), Vector3.ZERO, 0.0008, 3)
	for sz in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.012, 0.030, 0.008),
				Vector3(0, -0.048, 0.055 + 0.036 * float(sz)), Vector3.ZERO,
				0.0008, 3)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.008, 0.024, 0.008),
			Vector3(0, -0.042, 0.052), Vector3(10, 0, 0), 0.0006, 2)
	# 【识别特征3】MG42 式鱼尾形枪托（黑色聚合物）：托颈 + 托体上脊 +
	#    主托板（-8° 向后下扩的鱼尾板式）+ 后跟抵肩垫（近黑橡胶）+
	#    下缘收窄条 + 托侧贴腮凸台 + 托底调节卡钮 ×2
	GUN_LIB.chamfer_box(root, poly, Vector3(0.042, 0.050, 0.04),
			Vector3(0, 0.028, 0.222), Vector3.ZERO, 0.002, 10)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.046, 0.052, 0.14),
			Vector3(0, 0.020, 0.295), Vector3.ZERO, 0.003, 12)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.050, 0.086, 0.13),
			Vector3(0, -0.008, 0.32), Vector3(-8, 0, 0), 0.003, 14)
	GUN_LIB.chamfer_box(root, dk, Vector3(0.054, 0.100, 0.016),
			Vector3(0, -0.022, 0.392), Vector3.ZERO, 0.002, 6)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.030, 0.014, 0.12),
			Vector3(0, -0.048, 0.30), Vector3(-8, 0, 0), 0.0015, 5)
	GUN_LIB.chamfer_box(root, poly, Vector3(0.052, 0.020, 0.09),
			Vector3(0, 0.058, 0.30), Vector3(-7, 0, 0), 0.002, 8)
	for i in 2:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.030, 0.008, 0.012),
				Vector3(0, -0.036, 0.255 + 0.075 * float(i)), Vector3.ZERO,
				0.0008, 4)
	# ⑦ 两脚架（行军态折叠收拢枪管前段两侧：骨架式三角截面支腿银灰色
	#    m3steel 与深色枪身对比明显——ref_05 默认枪态；挂座 + 铰链销 +
	#    双腿向后收拢贴护筒侧下 + 膝铰链块 + 伸缩锁环 + 脚尖驻锄板）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.036, 0.022, 0.055),
			Vector3(0, -0.012, -0.50), Vector3.ZERO, 0.0015, 8)
	GUN_LIB.torus_ring(root, stl, 0.005, 0.012, Vector3(0, -0.020, -0.524),
			Vector3(0, 0, 90), 24, 12)
	for sx in [-1.0, 1.0]:
		var lx := float(sx)
		GUN_LIB.barrel(root, stl, 0.26, 0.012,
				Vector3(0.024 * lx, -0.020, -0.395),
				Vector3(90, -3.0 * lx, 0), 0, 24)
		GUN_LIB.chamfer_box(root, rec, Vector3(0.016, 0.016, 0.024),
				Vector3(0.024 * lx, -0.020, -0.486), Vector3.ZERO,
				0.0008, 5)
		GUN_LIB.torus_ring(root, dk, 0.007, 0.0145,
				Vector3(0.024 * lx, -0.020, -0.462), Vector3(90, 0, 0))
		GUN_LIB.chamfer_box(root, dk, Vector3(0.024, 0.009, 0.018),
				Vector3(0.024 * lx, -0.026, -0.262), Vector3.ZERO,
				0.0008, 5)
	# ⑧ 机械瞄具：护筒前段柱形准星（基座 + 准星柱 + 护耳双耳，直立态
	#    ref_01/10 直读）+ 机匣前部觇孔表尺（放倒态低廓贴轨 z -0.103 齿缝
	#    位——给顶轨中段改装镜让位（镜座 mz 0.01 前 18mm 净空），腾龙/
	#    qjb201 放倒先例）
	GUN_LIB.chamfer_box(root, rec, Vector3(0.020, 0.012, 0.030),
			Vector3(0, 0.058, -0.515), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.005, 0.016, 0.006),
			Vector3(0, 0.070, -0.515), Vector3.ZERO, 0.0006, 2)
	for sx in [-1.0, 1.0]:
		GUN_LIB.chamfer_box(root, rec, Vector3(0.004, 0.014, 0.010),
				Vector3(0.008 * float(sx), 0.066, -0.515), Vector3.ZERO,
				0.0006, 2)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.024, 0.007, 0.020),
			Vector3(0, 0.0765, -0.103), Vector3.ZERO, 0.0008, 5)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.020, 0.005, 0.032),
			Vector3(0, 0.0795, -0.103), Vector3.ZERO, 0.0006, 4)
	# ⑪ 右侧抛壳窗（凹嵌 + 防尘盖）+ 快慢机 + 机匣右侧亮钢铆钉 ×4 + 拉机柄
	#    左置（MG42 系左置传统：杆 + 圆柱柄头）
	GUN_LIB.chamfer_box(root, dk, Vector3(0.004, 0.026, 0.075),
			Vector3(0.0295, 0.032, -0.02), Vector3.ZERO, 0.0008, 6)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.005, 0.028, 0.08),
			Vector3(0.032, 0.032, -0.02), Vector3.ZERO, 0.001, 6)
	GUN_LIB.chamfer_box(root, stl, Vector3(0.004, 0.012, 0.026),
			Vector3(0.030, -0.012, 0.055), Vector3.ZERO, 0.0006, 2)
	for rz in [0.0, 0.05, 0.10, 0.15]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.003, 0.004, 0.004),
				Vector3(0.0298, 0.052, float(rz)), Vector3.ZERO, 0.0005, 2)
	GUN_LIB.chamfer_box(root, rec, Vector3(0.020, 0.016, 0.09),
			Vector3(-0.034, 0.046, 0.0), Vector3.ZERO, 0.0008, 4)
	GUN_LIB.barrel(root, stl, 0.034, 0.026, Vector3(-0.050, 0.046, 0.002),
			Vector3(0, 0, 90), 0, 20)
	# ⑪ QD 背带环 ×2（护筒尾下 / 托颈左，穿孔轴沿 X = 侧挂环）+ 机匣销 ×2（左）
	GUN_LIB.torus_ring(root, stl, 0.004, 0.010, Vector3(0, -0.008, -0.545),
			Vector3(0, 0, 90))
	GUN_LIB.torus_ring(root, stl, 0.004, 0.010, Vector3(-0.020, 0.030, 0.215),
			Vector3(0, 0, 90))
	for pz in [0.03, 0.12]:
		GUN_LIB.chamfer_box(root, stl, Vector3(0.003, 0.008, 0.008),
				Vector3(-0.0295, 0.016, float(pz)), Vector3.ZERO,
				0.0006, 2)
