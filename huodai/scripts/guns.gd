class_name Guns
## 枪械店目录：22 种枪械数值/价格。
## stats 约定：dmg 单发伤害 / cd 开火间隔 / mag 弹匣 / reload 换弹秒数 /
## pellets 弹丸数（霰弹）/ spread 散布弧度 / range 射程 /
## builtin_scope 枪自带的瞄具（没另装瞄具时用它；没有该字段 = 机瞄）/
## auto 缺省 true=全自动（按住连发）；false=半自动/栓动（只认 tap 边沿，
## 按住不连发，cd = 两发 tap 的最小间隔）/
## cd_profile 可选「射速档案」数组（2026-10 AN-94 超点射机制引入，纯增量）：
##   含义 = 同一扳机按压内第 k 发之后的冷却间隔（秒），k 超出数组长度取末值；
##   缺省不写 = 单 cd 原路径（hd_guns.try_fire 逐字不变行为）。范例 AN-94：
##   [0.0333, 0.1] = 首对 1800rpm 超点射 + 之后 600rpm 稳态；松开扳机计数
##   复位（hd_guns.update 归零 _press_shots），再按又是新的一对——an94 外
##   全枪册不带此字段，零行为变化

## ad = 甲伤（2026-10-29 护甲机制，照三角洲：打甲时削护甲耐久的数值）。
## 全表按口径与定位映射三角洲同源实测锚点（TapTap：QBZ191 38/SMG-45 40/
## PSG-1 55/M250 53/M700 61/416 系 35）推算——赛季数值有波动，锚点已注明；
## 消费在 hd_soldiers.apply_hit（对敌）与 hd_player.hit（对玩家）
const GUNS := [
	{"id": "pistol", "name": "侦察手枪", "desc": "伤害 25 · 半自动 · 12 发", "price": 0,
		"dmg": 25.0, "cd": 0.25, "mag": 12, "reload": 1.2, "pellets": 1,
		"spread": 0.012, "range": 120.0, "auto": false, "ad": 30},
	{"id": "smg", "name": "汤姆逊冲锋枪", "desc": "伤害 15 · 全自动 · 35 发 · .45 ACP · 木质枪托/护木", "price": 800,
		"dmg": 15.0, "cd": 0.08, "mag": 35, "reload": 1.6, "pellets": 1,
		"spread": 0.02, "range": 150.0, "ad": 40},
	{"id": "rifle", "name": "M7 战斗步枪", "desc": "伤害 20 · 全自动 · 30 发 · 6.8mm · FDE 涂装", "price": 1500,
		"dmg": 20.0, "cd": 0.13, "mag": 30, "reload": 1.5, "pellets": 1,
		"spread": 0.015, "range": 250.0, "ad": 40},
	{"id": "shotgun", "name": "霰弹枪", "desc": "伤害 12×6 散射 · 近战毁灭性", "price": 2000,
		"dmg": 12.0, "cd": 0.8, "mag": 6, "reload": 2.2, "pellets": 6,
		"spread": 0.055, "range": 60.0, "ad": 28},
	{"id": "sniper", "name": "狙击步枪", "desc": "伤害 100 · 自带 6× 密位镜 · 5 发", "price": 3000,
		"dmg": 100.0, "cd": 1.2, "mag": 5, "reload": 2.4, "pellets": 1,
		"spread": 0.0, "range": 400.0, "auto": false,
		"builtin_scope": {"id": "builtin_sniper", "name": "原厂 6× 镜", "zoom": 6.0,
			"kind": "sniper"}, "ad": 58},
	# ---- 枪械店扩充（2026-10）：七把新枪默认不拥有、现金购买；无 builtin_scope，
	# 开镜倍率只认装配瞄具（工程纪律：非狙击枪绝不自带倍率）----
	{"id": "uzi", "name": "乌兹冲锋枪", "desc": "伤害 14 · 全自动 · 32 发 · 9mm · 弹匣入握把/折叠托", "price": 900,
		"dmg": 14.0, "cd": 0.10, "mag": 32, "reload": 1.5, "pellets": 1,
		"spread": 0.024, "range": 130.0, "ad": 30},
	{"id": "mp5", "name": "MP5 冲锋枪", "desc": "伤害 13 · 全自动 · 30 发 · 9mm · 弯月弹匣/圆护木/固定托", "price": 1200,
		"dmg": 13.0, "cd": 0.075, "mag": 30, "reload": 1.7, "pellets": 1,
		"spread": 0.016, "range": 160.0, "ad": 32},
	{"id": "p90", "name": "P90 冲锋枪", "desc": "伤害 11 · 全自动 · 50 发 · 5.7mm · 无托/顶置弹匣", "price": 1600,
		"dmg": 11.0, "cd": 0.066, "mag": 50, "reload": 2.0, "pellets": 1,
		"spread": 0.022, "range": 170.0, "ad": 36},
	{"id": "vector", "name": "维克托冲锋枪", "desc": "伤害 10 · 全自动 · 25 发 · .45 ACP · 超高射速/后坐柔和", "price": 1800,
		"dmg": 10.0, "cd": 0.05, "mag": 25, "reload": 1.6, "pellets": 1,
		"spread": 0.021, "range": 140.0, "ad": 40},
	{"id": "akm", "name": "AKM 突击步枪", "desc": "伤害 22 · 全自动 · 30 发 · 7.62mm · 木托/弯月匣/斜切口", "price": 1700,
		"dmg": 22.0, "cd": 0.11, "mag": 30, "reload": 2.1, "pellets": 1,
		"spread": 0.018, "range": 200.0, "ad": 50},
	{"id": "m4a1", "name": "M4A1 突击步枪", "desc": "伤害 15 · 全自动 · 30 发 · 5.56mm · 提把/伸缩托/全黑", "price": 1800,
		"dmg": 15.0, "cd": 0.08, "mag": 30, "reload": 1.7, "pellets": 1,
		"spread": 0.013, "range": 240.0, "ad": 40},
	{"id": "scarh", "name": "SCAR-H 战斗步枪", "desc": "伤害 26 · 全自动 · 20 发 · 7.62 NATO · 沙色/长护木/侧折托", "price": 2400,
		"dmg": 26.0, "cd": 0.1, "mag": 20, "reload": 2.0, "pellets": 1,
		"spread": 0.016, "range": 280.0, "ad": 52},
	# 2026-10-25 用户定案：MK4 改三连发（burst=3：点一下打一个三连发，按住
	# 不重复——每次点射都要新的扳机边沿）；全自动需购「全自动枪管」配件
	# （MK4_MODS.autobarrel，走 M14 配件同链）解锁。
	# 2026-10-26 轮间锁考证（TapTap 实测三角洲 MK4）：单轮内 ~1200rpm（0.05s
	# 间隔、0.1s 打完三发）+ 打完约 100ms 才能点下一轮——面板 800rpm 即含间隔
	# 平均值。burst_cd=0.05（轮内）、burst_gap=0.1（轮间锁）、cd 保留 0.063
	# （全自动枪管解锁后的连发节拍）
	{"id": "mk4", "name": "MK4 冲锋枪", "desc": "伤害 16 · 三连发（轮间 0.1 秒）· 40 发 · 4.6×30mm · 全自动枪管可解锁全自动", "price": 1200,
		"dmg": 16.0, "cd": 0.063, "mag": 40, "reload": 1.7, "pellets": 1,
		"spread": 0.018, "range": 160.0, "burst": 3, "burst_cd": 0.05, "burst_gap": 0.1, "ad": 34},
	# ---- 机枪册（2026-10）：M250 弹链机枪（SIG XM250 考证），商店购入 ----
	# 2026-10-19 用户定案：射速 550rpm（cd=60/550≈0.1091，与 desc 逐字对齐）
	# 2026-10-24 用户定案：扳机延迟 0.5 秒（弹链机枪按下先蓄力再出第一发，
	# 松开/切枪复位重蓄——hd_guns.trigger_delay 通用字段，其余枪不带零变化）
	{"id": "m250", "name": "M250 机枪", "desc": "伤害 24 · 全自动 · 75 发弹链 · 6.8×51mm · 550发每分 · 扳机延迟 0.5 秒 · FDE 沙黄", "price": 3200,
		"dmg": 24.0, "cd": 0.1091, "mag": 75, "reload": 4.6, "pellets": 1,
		"spread": 0.02, "range": 260.0, "trigger_delay": 0.5, "ad": 53},
	# ---- 商店枪 MP7（2026-10）：H&K MP7 PDW 考证（4.6×30mm，950rpm）----
	# cd 0.063 ≈ 952rpm 与 desc「950发每分」一致；40 发半透明短匣插中空握把
	{"id": "mp7", "name": "MP7 冲锋枪", "desc": "伤害 14 · 全自动 · 40 发 · 4.6×30mm · 950发每分 · 紧凑 PDW · 握把内插匣", "price": 1300,
		"dmg": 14.0, "cd": 0.063, "mag": 40, "reload": 1.6, "pellets": 1,
		"spread": 0.017, "range": 160.0, "ad": 34},
	# ---- 商店枪 M14（2026-10）：官方考证（7.62×51mm NATO）----
	# 2026-10-19 用户定案：改全自动 730rpm（cd=60/730≈0.0822）——真 M14 的
	# 选发机构本就有全自动档；游戏里保留 DMR 高单发（dmg 32 最高单发动能档）
	# + 全自动压制的双面手感。spread 0.012 精确步枪精度；range 320 全枪册最远
	# （全尺寸 22 寸枪管）；price 3000 与狙击同档（desc 与数值逐项一致）
	{"id": "m14", "name": "M14 射手步枪", "desc": "伤害 32 · 全自动 730发每分 · 20 发（可扩 30）· 7.62×51mm NATO · 胡桃木全托 · 全场最远射程", "price": 3000,
		"dmg": 32.0, "cd": 0.0822, "mag": 20, "reload": 2.2, "pellets": 1,
		"spread": 0.012, "range": 320.0, "ad": 56},
	# ---- 商店枪 AS Val（2026-10）：官方考证特种突击步枪（9×39mm 亚音速）----
	# 2026-10 用户定案：射速 972 发每分（cd=60/972≈0.0617 精确）；自带一体
	# 消音器（消音管约占全枪一半长——音色专项 SHOT_TUNE["asval"]、开火火光
	# 减半分支见 hd_guns.try_fire）；40 发长匣（等比拉长匣体、肋条加密）；
	# dmg 30 亚音速重弹单发；range 240 亚音速弹存速差于全威力步枪（m4a1 同
	# 240 但弹道存能更差）；price 3600 消音特种枪溢价
	{"id": "asval", "name": "AS Val 特种突击步枪", "desc": "伤害 30 · 全自动 972发每分 · 40 发 · 9×39mm 亚音速 · 自带一体消音器 · 骨架侧折托", "price": 3600,
		"dmg": 30.0, "cd": 0.0617, "mag": 40, "reload": 2.0, "pellets": 1,
		"spread": 0.014, "range": 240.0, "ad": 46},
	# ---- 商店枪 K416（2026-10）：官方考证突击步枪（HK416 风格，5.56×45mm）----
	# 射速 880 发每分三源交叉（ref_06 面板原文「射速 880发/分」/ orzice / 17173），
	# cd=60/880≈0.0682（保留 4 位小数，换算 879.8rpm 与 desc ±1% 内）；
	# dmg 30 采 29~31 考证区间中值（orzice 29 / 游戏面板 31）；30 发 STANAG 匣
	# （ref_05「5.56*45 30发聚合物弹匣」）；price 2600 SCAR-H 档位（2500-2800）
	{"id": "k416", "name": "K416 突击步枪", "desc": "伤害 30 · 全自动 880发每分 · 30 发 · 5.56×45mm · HK416 血统 · 肋条散热护木/鸟笼消焰器", "price": 2600,
		"dmg": 30.0, "cd": 0.0682, "mag": 30, "reload": 1.8, "pellets": 1,
		"spread": 0.014, "range": 250.0, "ad": 42},
	# ---- 商店枪 AN-94（2026-10）：S12「微光」赛季新枪（三角洲 2026-11-05 上线，
	# 截至集成日官方未公布面板——伤害为社区爆料、射速/外观按现实原型考证）----
	# 超点射机制（用户定案，本枪灵魂）：同一扳机按压内第 1→2 发间隔 0.0333s
	# （=60/1800，前两发 1800rpm 超快点射）、第 2 发之后回落 0.1s（=60/600，
	# 后续 600rpm 稳态）；松开扳机按压计数复位，再按又是新的一对——由
	# cd_profile 射速档案字段驱动（hd_guns.try_fire/_press_shots，其余 18 把
	# 枪不带此字段走单 cd 原路径零变化）。dmg 33 采三角洲爆料肉伤（B站 UP
	# 「Always聪聪」预测：33/48/优势射程 15 米，非官方最终）；30 发 AK-74
	# 式弧匣向右倾斜（现实标配，弹匣兼容 30/45/60）；price 3200 落 LV4 爆料
	# 档 2800-3400（m250 同档）；spread 0.012——延迟后坐前两发几乎同一弹孔
	# （5.45×39 高初速 900m/s + 405mm 长枪管的精度卖点）；range 230 5.45
	# 步枪档（akm 200 与 m4a1 240 之间）；desc 双射速文案与 cd/cd_profile
	# 换算一致（test_huodai 27c 断言：60/0.0333=1801.8≈1800、60/0.1=600）
	# 2026-10-23 用户实测「弹匣歪了没对齐弹匣井」定案：侧倾已去、匣竖直入井
	# （真实 AN-94 匣只有向前弧度）——desc 同步去「右倾」
	{"id": "an94", "name": "AN-94 突击步枪", "desc": "伤害 33 · 前两发 1800 · 后续 600发每分 · 30 发 · 5.45×39mm · 超点射双发 · 双室制退器/星形表尺/弧形弹匣", "price": 3200,
		"dmg": 33.0, "cd": 0.1, "mag": 30, "reload": 2.0, "pellets": 1,
		"spread": 0.012, "range": 230.0, "cd_profile": [0.0333, 0.1], "ad": 38},
	# ---- 商店枪 SR25（2026-10）：群星赛季新枪·官方考证 7.62×51mm 半自动
	# 射手步枪（AR-10/M110 系 DMR，官网「采用AR系统的7.62×51mm半自动步枪，
	# 人机工效上乘，精准度不俗」）----
	# 射速 364发/分=面板半自动连点上限（ref_03/04/05 三图读数一致 +
	# orzice 交叉印证），cd=60/364≈0.1648（保留 4 位，换算 364.1rpm 与
	# desc ±1% 内）；auto=false 半自动 tap 门（pistol/sniper 同款，按住
	# 只 1 弹——2026-10-26 集成定案，不改 trigger_delay/burst）
	# dmg 50 采三角洲白板面板基础伤害（ref_05 读数 50，与 orzice 一致；
	# 单发伤害全枪册仅次于狙击/霰弹，半自动 DMR 重击档）；range 320 取
	# m14 既有锚点同档（全尺寸 DMR 长枪管；三角洲「优势射程 90→122 米」
	# 是衰减机制口径，本引擎 range 为弹道判定距离，按 DMR 档对齐 m14）
	# 弹匣 20 发 7.62×51 直-微弧匣（ref_03/05 面板容量 20——白板初始
	# 10 发、20 发匣为标配配件，本作按 20 发满配入册）；spread 0.012
	# 精确步枪精度（m14 同档）；price 3200 DMR 档（m14 3000 与 asval
	# 3600 之间，三角洲交易行白板约 25 万哈夫币的中高价定位）
	{"id": "sr25", "name": "SR25 射手步枪", "desc": "伤害 50 · 半自动 364发每分 · 20 发 · 7.62×51mm · 浮置肋条护木/战术消音器 · 伸缩精准枪托", "price": 3200,
		"dmg": 50.0, "cd": 0.1648, "mag": 20, "reload": 2.2, "pellets": 1,
		"spread": 0.012, "range": 320.0, "auto": false, "ad": 58},
	# ---- 商店枪 K437（2026-10-29）：烽火地带现役突击步枪考证（.300 BLK，
	# AAC 蜜獾/SIG MCX 一脉 AR 平台——社区推断原型；S4 赛季随干员「无名」
	# 上线，S11 因超长枪管加强翻红，建模按现役枪处理）----
	# 射速 780rpm 多源一致（ref_02/04/09 面板直读 + gamersky/ali213/
	# deltaforcetools 交叉），cd=60/780≈0.0769（保留 4 位小数，换算
	# 780.2rpm 与 desc「780发每分」±1% 内）；dmg 34/护甲伤 35 面板直读
	# （ref_02/04/09，基础伤害 34 不随配件变）；30 发 .300 大弧烟灰匣
	# （ref_02 Capacity 30；45 发扩容匣为改装配件不入册）；auto 缺省
	# true（面板 Modes Auto/Single 全自动档，不带 cd_profile/burst——
	# 纯突击步枪靠配件生态）；range 260 .300 BLK 中口径档（k416 5.56
	# 250 与 scarh 7.62 280 之间——三角洲优势射程裸枪 40m/满改 46m 是
	# 衰减机制口径，本引擎 range 为弹道判定距离按口径档对齐）；
	# price 3400 赛季新枪档（an94 3200 与 asval 3600 之间；三角洲改枪
	# 总价值中改 27.6 万/满改 58 万哈夫币为本作经济折算参考）；
	# spread 0.014 k416 同档突击步枪精度
	{"id": "k437", "name": "K437 突击步枪", "desc": "伤害 34 · 全自动 780发每分 · 30 发 · .300 BLK · 斜槽浮置护木/骨架折叠托/翻折机械瞄具", "price": 3400,
		"dmg": 34.0, "cd": 0.0769, "mag": 30, "reload": 1.8, "pellets": 1,
		"spread": 0.014, "range": 260.0, "ad": 48},
	# ---- 商店枪 QCQ171（2026-10-30）：烽火地带现役冲锋枪考证（国产 QCQ-171，
	# 原外贸型 CS/LR-7「出口转内销」列装高原部队单兵自卫）——外形照用户图
	# ref_00（首要）+ ref_01/03 三角洲游戏图 + ref_04 真枪照三源一致：常规有托
	# 布局（弹匣井在握把前方）、金属平顶机匣 + 全长皮轨直通护木顶、双杆银灰
	# 伸缩托（每杆 4 长条减重孔 + 黑聚合物方板托底板）、黑聚合物方正护木
	# M-LOK 散热槽、30 发黑直匣微前倾 6°、短鸟笼消焰器、翻转觇孔照门 + 片状
	# 准星、快慢机红点、机匣左侧 DSU 编号白刻印——几何体在 hd_gun_ar.gd
	# _ar_qcq171，册属冲锋枪（SMG_IDS，hd_guns._smg_build 分发到 AR_LIB）
	# 口径考证【如实注明】：任务前提写 5.8×21mm DAP92，但网易文章
	# （163.com/dy/article/H3OBT6B20552BD4S.html）与三角洲游戏内弹药均证实
	# QCQ-171 为 9×19mm（5.8×21mm 是 QCW-05 的弹药，非本枪）——desc/数值
	# 按 9×19mm 落；面板另模式（ref_01）25 伤/23m 射程为大战场口径，本游戏
	# 仿烽火地带以烽火面板为准
	# 数值（三角洲烽火地带面板双源一致 orzice.com/v/info/50 +
	# qieyou.com/content/114982）：伤害 36 / 护甲伤 33 / 射速 763rpm / 弹匣 30 /
	# 初速 450m/s / 优势射程 20m / 仓库 2×4 重 2.70kg——伤害按 MP7 锚点换算
	# （三角洲 MP7 伤 20 → QCQ171/MP7=1.8×；本作 MP7 dmg14 → 14×1.8=25.2
	# ≈ dmg 25，高于 MK4 的 16 档位关系成立）；cd=60/763≈0.0786（保留 4 位，
	# 换算 763.4rpm 与 desc「763发每分」±1% 内）；ad 33 面板护甲伤直读
	# （k437「面板直读」同法，33/36≈0.92 与 mk4 34/mp7 34 冲锋枪档同源）；
	# auto 缺省 true（单发/全自动面板，纯全自动冲锋枪不带特殊机制字段）；
	# spread 0.017 9mm 冲锋枪档（mp7 同值）；range 160 9mm 档（mp5/mp7/mk4
	# 同值）；price 1400 任务定案冲锋枪中档（三角洲交易行约 11.2 万哈夫币
	# 无法直折本作₵体系）
		{"id": "qcq171", "name": "QCQ171 冲锋枪", "desc": "伤害 25 · 全自动 763发每分 · 30 发 · 9×19mm · 平顶全长轨/双杆伸缩托/高原列装", "price": 1400,
		"dmg": 25.0, "cd": 0.0786, "mag": 30, "reload": 1.7, "pellets": 1,
		"spread": 0.017, "range": 160.0, "ad": 33},
	# ---- 商店枪腾龙（2026-10-31）：国产 QBZ-191「191式」自动步枪考证（2019
	# 国庆阅兵亮相的新一代制式步枪；游戏原名「191式」后更名「腾龙突击步枪」，
	# 维基 QBZ-191 词条明言 + gamersky/TapTap 多源一致；国际服枪库无此枪、
	# 腾龙为国服命名）——常规有托布局（弹匣井在握把正前方）、上/下铝合金
	# 机匣双销连接、平顶机匣 + 全长皮轨直通护木顶、聚合物多边形截面护木开
	# 长条散热孔、4 档可调聚合物伸缩托（托腮板+后跟垫）、拉机柄右置随动、
	# 30 发 PMAG 风弧匣带透明余弹观察窗（黄色底板）、短鸟笼消焰器、翻折
	# 机械瞄具（平时放倒让位光学镜）、双侧快慢机 + 加长前置弹匣释放杆、
	# 机匣左侧白色序列号铭文（真枪直读「000235-21-296」样式）——游戏渲染
	# 银灰机匣 + 黑色护木/枪托/握把双色调（QCQ171 同款国产枪渲染风格，
	# 真枪实物全黑，几何体在 hd_gun_ar.gd _ar_tenglong）
	# 数值（三角洲烽火地带 S7 面板多源直读，gamersky 攻略 + qieyou 两源
	# 一致）：伤害 25 / 护甲伤 ad 38（面板直读，同 k437 ad48/qcq171 ad33
	# 口径） / 射速 706rpm（装「高速导气」改装件 759rpm 为三角洲改装生态、
	# 本作白板入册）/ 弹匣 30（45 扩容匣/60 弹鼓为改件不入册）/ 初速 550m/s /
	# 后坐控制 42·操控 60·稳定 50·腰射 56（0-100 制）/ 重 2.60kg·仓库 5×2·
	# 战场等级 43 解锁 / 全自动+单发。部位伤害表（qieyou：头 49/上身 26/
	# 腹 24/四肢 23 @18m，上身 18→200m 衰减 26.0→14.3）与面板伤 25 同档
	# 自洽；「基础伤害 35」（qieyou 另页）为孤例疑大战场/旧版口径不采。
	# cd=60/706≈0.0850（保留 4 位，换算 705.9rpm 与 desc「706发每分」±1% 内）；
	# dmg 25 全自动步枪册最低单发（5.8×42 国产小口径高人气 T0 枪，30 发匣
	# + 706rpm 中速连发火力密度补回）；spread 0.014 5.56 档小口径精度
	# （k416/k437 同值）；range 250 5.8 步枪档（k416 同值，真枪 368mm 枪管
	# 有效射程 400-600m 考证）；reload 1.8 30 发聚合物匣档（k416/k437 同值）；
	# auto 缺省 true 纯全自动（面板全自动+单发、无三角洲特有机制——不带
	# cd_profile/trigger_delay/burst）；price 2500（SCAR-H 2400 与 K416 2600
	# 之间：单发伤最低但 30 发 + 706rpm + 国产 T0 人气定位；三角洲无固定
	# 店售价、交易行裸枪约 7-9 万哈夫币量级无法直折本作₵体系）
	{"id": "tenglong", "name": "腾龙突击步枪", "desc": "伤害 25 · 全自动 706发每分 · 30 发 · 5.8×42mm · 银灰双销机匣/全长轨/可调托/透明窗弹匣", "price": 2500,
		"dmg": 25.0, "cd": 0.0850, "mag": 30, "reload": 1.8, "pellets": 1,
		"spread": 0.014, "range": 250.0, "ad": 38},
]

## M14 专属配件解锁态（2026-10 用户定案）：护木（GRIPS 表 GripMods 生效
## ——减后坐/加开镜速）与 30 发扩容匣——不走 GUNS 商店表，由交易行⑤区
## （hd_lobby）按 bool 卖；hd_guns 出厂/开火按此放大弹容与挂护木视觉件
const M14_MODS := {
	"foregrip": {"name": "M14 战术护木", "price": 1200,
		"desc": "前护木：后坐力 -45% · 开镜速度 +25%（垂直前握把档）"},
	"extmag": {"name": "M14 30 发扩容匣", "price": 900,
		"desc": "专属 30 发长匣：弹容 20→30（换弹 +0.4s）"},
}

## MK4 专属配件（2026-10-25 用户定案：三连发原厂，全自动走配件解锁）——
## 存储复用 stash.m14_mods 数组（id 全局唯一，buy/owns 链同源）
const MK4_MODS := {
	"autobarrel": {"name": "MK4 全自动枪管", "price": 1800,
		"desc": "重型长枪管 + 鸟笼消焰器：解锁全自动（原厂三连发）"},
}

## SR25 专属配件（2026-10-26 用户定案「很贵的全自动套件」）：装上后解锁全自动
## 且每次扣扳机一次射出两发（double tap 双位点射）、弹匣自动换 45 发专用长匣——
## 存储复用 stash.m14_mods 数组（id 全局唯一，buy/owns 链同源）；表字段约定：
## auto_to/burst_to/mag_to = 装上后的 auto/burst/mag 覆写值（hd_guns 消费）
const SR25_MODS := {
	# 2026-10-26 三次定案（用户）：B 键切换开火模式——默认全自动（1069rpm 连发），
	# 按 B 切 MK4 式三连发（轮内同 1069rpm + 轮间锁 0.1s），再按 B 切回全自动。
	# 字段族：cd_to=全自动节拍覆写 / burst_to+burst_cd_to+burst_gap_to=三连发形态
	# recoil_mul_to=0.45（2026-10-27 用户报告「后坐力非常大」）：RECOIL sr25
	# 单发 0.32 是半自动 364rpm 手感——1069rpm 下每秒冲量 3× 步枪还会被连发
	# 累增项滚雪球；射速转换套件自带制退补偿（两轴同乘）
	"fullauto": {"name": "SR25 全自动套件", "price": 6800,
		"desc": "快慢机改装（1069rpm·B 切换全自动/三连发·制退补偿）+ 45 发专用长匣：弹匣 20→45",
		"auto_to": true, "cd_to": 0.0561, "burst_to": 3, "burst_cd_to": 0.0561,
		"burst_gap_to": 0.1, "mag_to": 45, "recoil_mul_to": 0.45},
}

## 骨架狙击枪托（2026-10-29 deltaforcetools 烽火地带数据考证「骨架狙擊槍托」，
## 站内 ID 34703；deltaforce.th.gl 797 件索引无同名条目故属性以前者为准）：
## sniper 专属一体式骨架镂空托（黑色哑光聚合物、0.1kg 轻量、可快拆、交易所在售）
## ——社区所称「高据枪高操控」万金油狙击托；腰射/压枪明显让位（本作只建模
## 后坐与开镜两轴）。走 m14_mods 同链存储（id 全局唯一，buy/owns 链同源），
## 表字段约定：ads_mul/recoil_mul = 装上后的开镜/后坐乘数（hd_guns 消费）
const SKEL_STOCK := {
	"skel_stock": {"name": "骨架狙击枪托", "price": 3600,
		"desc": "操控速度 +10% · 后坐力 -10%（开镜使用为主，腰射让位）",
		"ads_mul": 1.10, "recoil_mul": 0.90},
}


## 大战场兵种配发枪械（不进枪械店）
const BATTLE_GUNS := [
	{"id": "lmg", "name": "轻机枪", "desc": "伤害 18 · 全自动 · 80 发", "price": 0,
		"dmg": 18.0, "cd": 0.1, "mag": 80, "reload": 3.2, "pellets": 1,
		"spread": 0.022, "range": 220.0, "ad": 45},
]


static func gun_by_id(id: String) -> Dictionary:
	for g in GUNS:
		if g["id"] == id:
			return g
	for g in BATTLE_GUNS:
		if g["id"] == id:
			return g
	return GUNS[0]


## 只在枪械店目录（GUNS，不含大战场配发 BATTLE_GUNS）里精确找 id；
## 找不到返回 {}——gun_by_id 有 GUNS[0] 兜底无法区分未知 id，
## 购枪路径（HDStash.buy_gun）需要这个防御
static func shop_gun_by_id(id: String) -> Dictionary:
	for g in GUNS:
		if g["id"] == id:
			return g
	return {}


# 弹药类型：装备后影响所有枪械的伤害与曳光/火花颜色
const AMMO := [
	{"id": "standard", "name": "标准弹", "desc": "标准威力", "price": 0, "dmg_mul": 1.0,
		"color": Color(1.0, 0.8, 0.35)},
	{"id": "power", "name": "强力弹", "desc": "伤害 +35%", "price": 600, "dmg_mul": 1.35,
		"color": Color(1.0, 0.55, 0.2)},
	{"id": "ap", "name": "穿甲弹", "desc": "伤害 +75%", "price": 1500, "dmg_mul": 1.75,
		"color": Color(0.75, 0.85, 1.0)},
	{"id": "incendiary", "name": "燃烧弹", "desc": "伤害 +120% · 红色曳光", "price": 3000,
		"dmg_mul": 2.2, "color": Color(1.0, 0.3, 0.15)},
]


static func ammo_by_id(id: String) -> Dictionary:
	for a in AMMO:
		if a["id"] == id:
			return a
	return AMMO[0]


# 瞄具：安装到枪上（每枪一槽，一个瞄具同一时间只装在一把枪上），未装 = 机瞄。
# zoom 为开镜倍率；zooms 为可调倍率档（滚轮切换，没有 = 固定倍率）；
# kind 决定镜面风格（iron/holo/reddot/optic/sniper/thermal）
const SCOPES := [
	{"id": "holo", "name": "全息镜", "desc": "1.5× · 全息方框绿点 · 视野宽", "price": 900,
		"zoom": 1.5, "kind": "holo"},
	{"id": "reddot", "name": "红点镜", "desc": "1.5× · 无框红点 · 快速获取", "price": 700,
		"zoom": 1.5, "kind": "reddot"},
	{"id": "optic35", "name": "3.5× 光学镜", "desc": "3.5× · 密位十字 · 中距离精确", "price": 1800,
		"zoom": 3.5, "kind": "optic"},
	{"id": "scope5", "name": "5× 密位镜", "desc": "5×/8× 滚轮可调 · 暗角密位 · 远距离", "price": 2800,
		"zoom": 5.0, "zooms": [5.0, 8.0], "kind": "sniper"},
	{"id": "thermal", "name": "热成像镜", "desc": "4× · 敌人热点高亮 · 夜战神器", "price": 5200,
		"zoom": 4.0, "kind": "thermal"},
]


# 前握把：购买后随身生效（所有枪械），降低后坐力 + 加快开镜速度
const GRIPS := [
	{"id": "none", "name": "无握把", "desc": "原始手感", "price": 0,
		"recoil_mul": 1.0, "ads_mul": 1.0},
	{"id": "angle", "name": "直角前握把", "desc": "后坐力 -25% · 开镜速度 +40%", "price": 900,
		"recoil_mul": 0.75, "ads_mul": 1.4},
	{"id": "vertical", "name": "垂直前握把", "desc": "后坐力 -45% · 开镜速度 +25% · 更稳", "price": 1500,
		"recoil_mul": 0.55, "ads_mul": 1.25},
	{"id": "resonant", "name": "共振握把", "desc": "后坐力归零 · 开镜速度 +50% · 顶级配件", "price": 4800,
		"recoil_mul": 0.0, "ads_mul": 1.5},
	# 共振前握把（2026-10-27 用户定案「大幅减少垂直后坐力」）：vy_mul 只压
	# 垂直轴（pitch 上顶 ×0.30 = -70%），水平漂移不变（recoil_mul 1.0）——
	# 与全归零的共振握把拉开档位差（专精垂直 vs 全消）
	{"id": "resonant_fg", "name": "共振前握把", "desc": "垂直后坐 -70% · 开镜速度 +20%（水平后坐不变）", "price": 3200,
		"recoil_mul": 1.0, "vy_mul": 0.3, "ads_mul": 1.2},
]


static func grip_by_id(id: String) -> Dictionary:
	for g in GRIPS:
		if g["id"] == id:
			return g
	return GRIPS[0]


## 后握把（2026-10-29 幻影后握把落地，三角洲考证）：AR 手枪握把式后握把、
## 纯黑哑光聚合物、紫色稀有度（0.2kg/1×1 格，deltaforce.th.gl item_13030000111，
## 参考价约 35,535 哈夫币按本作经济折 ₵2,800）——操控速度型：牺牲少量据枪
## 稳定（本作不建模）换开镜/举镜操控响应，适配高机动改法。per-gun 装配
## （stash rear_grip_fit，照 GRIPS/grip_fit 先例），全步枪/冲锋枪可装
const REAR_GRIPS := [
	{"id": "none", "name": "无后握把", "desc": "原始手感", "price": 0,
		"ads_mul": 1.0},
	{"id": "phantom", "name": "幻影后握把", "desc": "操控速度 +15%", "price": 2800,
		"ads_mul": 1.15},
]


static func rear_grip_by_id(id: String) -> Dictionary:
	for g in REAR_GRIPS:
		if g["id"] == id:
			return g
	return REAR_GRIPS[0]


## 瞄具的倍率档（固定倍率的瞄具只有一档）
static func scope_zooms(sc: Dictionary) -> Array:
	if sc.is_empty():
		return [1.0]
	return sc.get("zooms", [float(sc.get("zoom", 1.0))])


static func scope_by_id(id: String) -> Dictionary:
	for s in SCOPES:
		if s["id"] == id:
			return s
	return {}
