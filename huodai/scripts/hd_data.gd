class_name HDData
## 烽火地带（Godot 版）共享数据契约 —— 全模块只读这一份表
## 数值移植自网页版 js/fps（loot.js 品质表 / gunsData 弹药储备 / lobby 签到），
## 枪械与瞄具表不在此处：直接用 guns.gd 的 class_name Guns（GUNS/SCOPES/gun_by_id）。

## 七档品质：id 即数组下标 0..6；weight 为荒野/中心两套权重的键。
## 2026-10 经济重定价（改进方案第 2 节，用户定案「战利品除以 10、枪价不动」）：
## 价值整体 ÷10——中位一局战利品 ≈ 中档出发装备（KIT_REF）的 1.2–1.6 倍，
## 撤离就赚、阵亡就亏（回归 test_huodai 2,000 局蒙特卡洛断言此比值）
const RARITY := [
	{"id": 0, "name": "白色", "color": Color(0.85, 0.85, 0.85), "vmin": 20.0, "vmax": 50.0},
	{"id": 1, "name": "绿色", "color": Color(0.35, 0.82, 0.43), "vmin": 80.0, "vmax": 150.0},
	{"id": 2, "name": "蓝色", "color": Color(0.23, 0.63, 1.0), "vmin": 250.0, "vmax": 500.0},
	{"id": 3, "name": "紫色", "color": Color(0.66, 0.42, 1.0), "vmin": 800.0, "vmax": 1500.0},
	{"id": 4, "name": "金色", "color": Color(1.0, 0.79, 0.3), "vmin": 2500.0, "vmax": 6000.0},
	{"id": 5, "name": "红色", "color": Color(1.0, 0.35, 0.25), "vmin": 10000.0, "vmax": 18000.0},
	{"id": 6, "name": "至臻", "color": Color(0.35, 1.0, 0.85), "vmin": 30000.0, "vmax": 50000.0},
]

## 分区开箱品质权重（荒野穷、中心富；dam 坝区介于 mid/center）：[白,绿,蓝,紫,金,红,彩]
## dam 权重和=100（roll_rarity 按和取模，hd_data.gd roll_rarity 消费；
## zone 名由 HDWorld.zone_at 大坝矩形分支给出，两处缺一即静默回退 mid）
const RARITY_W := {
	"wild": [62, 26, 9, 3, 0, 0, 0],
	"mid": [40, 30, 18, 9, 3, 0, 0],
	"center": [18, 24, 24, 17, 12, 4, 1],
	"dam": [30, 26, 20, 13, 8, 2, 1],
}

## UI 中文字体链：Godot 默认字体缺大量中文字形（乱码方框根因），改用系统字体兜底；
## 不用 "PingFang SC"——Godot 把它解析到 PingFang.ttc 首个字面（PingFang HK，繁体），
## 缺 杀(U+6740) 等简体独有字（「击杀」成方框，回归⑤），且 font_names 只取首个命中、
## 不向链后位逐字回退；macOS 首位 Hiragino Sans GB（杀/击/撤/亡 全有），Windows 命中微软雅黑
## （链序与 godot/scripts/ui_font.gd 同源，两路统一）
const UI_FONT_NAMES := [
	"Hiragino Sans GB", "Heiti SC", "STHeiti",                        # macOS
	"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun",      # Windows
	"Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei",  # Linux
	"sans-serif",
]
## 逐字回退（Font.fallbacks，主字体缺该字形才查）：补 ₵(U+20B5) 等符号——
## Hiragino/STHeiti/PingFang 全系都无 ₵（现金/签到/结算到处在用），由 Helvetica 供给
const UI_FONT_FALLBACK := ["Helvetica"]
const UI_FONT_SIZE := 14          # 未显式指定字号的控件兜底字号（设计基准 1440×810）

## 各档变卖物例表（两字中文徽标 + 名称池，roll 时随机取名）；
## 徽标不用 emoji：Godot 默认字体无 emoji 字形（渲染成方框），中文字徽标必可渲
const LOOT_NAMES := [
	[["绷带", "医疗"], ["润滑油罐", "物资"], ["废料零件", "零件"], ["旧手表", "钟表"]],
	[["止痛药", "医疗"], ["战术护目镜", "装具"], ["工具组", "工具"], ["罐头食品", "食品"]],
	[["精密零件", "零件"], ["急救包", "医疗"], ["军用电池", "电源"], ["夜视仪", "光学"]],
	[["军用电路板", "电子"], ["防弹插板", "防具"], ["加密硬盘", "数据"], ["狙击镜片", "光学"]],
	[["金条", "贵金属"], ["名贵腕表", "钟表"], ["显卡", "电子"], ["机密文件", "机密"]],
	[["机械外骨骼", "机甲"], ["原型芯片", "芯片"], ["卫星通讯机", "通讯"]],
	[["至臻黑箱", "至臻"], ["龙标藏品", "藏品"]],
]

## 旧档 emoji 图标 → 中文徽标映射（修复前存档里残留的 emoji 读档时一并归一化）
const LEGACY_ICONS := {
	"🩹": "医疗", "🛢": "物资", "🔩": "零件", "⌚": "钟表", "📦": "杂物",
	"💊": "医疗", "🥽": "装具", "🧰": "工具", "🥫": "食品", "⚙": "零件",
	"🔋": "电源", "👓": "光学", "📡": "电子", "🛡": "防具", "💾": "数据",
	"🔭": "光学", "🪙": "贵金属", "🎰": "电子", "🗂": "机密",
	"🦾": "机甲", "💠": "芯片", "📶": "通讯", "🏆": "至臻", "🐉": "藏品",
}
const ICON_DEFAULT := "杂物"      # 空/未知图标兜底徽标

## 每把枪的备弹（弹匣外储备；pistol/smg/shotgun/sniper 对齐网页版实测值；
## 2026-10 扩充七枪——漏加则 enter() 备弹 0、大厅速览也显 0）
const RESERVE := {
	"pistol": 60, "smg": 175, "rifle": 150, "shotgun": 30, "sniper": 25,
	"uzi": 175, "mp5": 150, "p90": 150, "vector": 125, "mk4": 150,
	"akm": 150, "m4a1": 150, "scarh": 100, "m250": 200, "mp7": 150,
	"m14": 80,   # 2026-10 商店枪 M14：DMR 备弹少（20 发匣 ×4 匣）
}

## ---- 极致备弹经济（2026-10）：备弹不再每局免费回满，改为按发购买、局终回收 ----
## 「极致备弹要自己买，买多少就用多少」：出发（行动/靶场）按 stash 库存装填，
## 局终（撤离/死亡/放弃回大厅）把剩余备弹写回库存——弹药不属于战利品，死亡也不掉。
## 首次入账礼物：每把枪第一次进弹药经济（库存缺键）一次性赠送满额备弹
## （满额 = RESERVE 该枪值，老档缺字段同按此规则初始化）——老玩家平滑过渡，
## 赠送后正常买卖、只送一次（实现见 hd_stash.ammo_of）。
const AMMO_NAME := "极致备弹"
const AMMO_COLOR := Color(1.0, 0.79, 0.3)   # 金色标识（与品质金色同值，弹药=硬通货的视效统一）
## 单价（₵/发，按枪定价：手枪贱 · 冲锋枪轻弹 · 步枪中价 · 霰弹/狙击一发一钱）；
## m250 缺键则交易行③区购弹静默拒（buy_ammo 按表拦截）——与 rifle 同 6.8mm
## 弹族单价
const AMMO_PRICE := {
	"pistol": 2, "smg": 4, "mp5": 4, "p90": 4, "uzi": 4, "mk4": 4, "vector": 5,
	"rifle": 6, "m4a1": 6, "akm": 6, "scarh": 8, "shotgun": 15, "sniper": 30,
	"m250": 6, "mp7": 4,
	"m14": 8,   # 2026-10 商店枪 M14：7.62×51 与 scarh 同弹族单价——缺键则交易
				# 行③区购弹静默拒（buy_ammo 按表拦截），买枪无弹的经济漏洞
}
## 大厅购买挡位（发数；B 键循环），总价 = 挡位 × 单价
const AMMO_TIERS := [30, 90, 300]

const DAILY_REWARD := 300    # 每日签到金额（₵；经济重定价后 1500→300，否则一天白送一把枪）
const BACKPACK_MAX := 12     # 背包格数

## ---- 带入即风险（2026-10 改进方案第 1 节，用户定案「阵亡丢失随身装备」）----
## 出发时主副武器、其所装瞄具、所带备弹 = 局内装备：撤离带回，阵亡/放弃全丢；
## 侦察手枪永久（免费、不会丢），保证输光也能再出发；安全箱里的物品阵亡保留
const PERMANENT_GUN := "pistol"
const SECURE_BASE := 2                       # 安全箱初始格数
const SECURE_UP_PRICE := [4000, 10000]       # 扩容价：2→3 格 / 3→4 格（₵）
const SECURE_MAX := SECURE_BASE + 2          # 安全箱上限 4 格
## 中档出发装备参考价（M4A1 1,800 + 3.5× 光学镜 1,800 + 300 发 ×₵6）：
## 经济门槛 A = 中位局战利品 ÷ KIT_REF 落在 1.2–1.6
const KIT_REF := 5400
const SAVE_PATH := "user://huodai_save.json"

## ---- 第三阶段：内容深度（2026-10 改进方案第 5/6 节）----
const RAID_TIME := 1500.0                       # 局时 25 分钟；超时未撤离 = 失踪（视同阵亡）
const DAM_OPEN_T := 720.0                       # 大坝撤离点 12 分钟后开放
const PAID_EXTRACT_POS := Vector3(-140.0, 0.0, -90.0)   # 西缘付费撤离（买通司机；行动边界 ±148 内）
const PAID_PRICE := 800                         # 付费撤离：撤离成功时从现金扣（不足不能用）
const LEVER_EXTRACT_POS := Vector3(135.0, 0.0, -10.0)   # 变电站东门拉闸撤离
const LEVER_POS := Vector3(124.6, 0.0, -19.0)   # 电闸：变电站主控楼内东墙
const LEVER_HOLD := 2.0                         # 按住 F 拉闸秒数
const LEVER_ALERT_R := 80.0                     # 拉闸动静惊动半径
## 每局启用概率（主撤离常开、大坝定时开；付费/拉闸按概率出现 → 每局撤离点组合不同）
const EXTRACT_ODDS := {"paid": 0.6, "lever": 0.6}
## 随机出生点（行动边界 ±148 内的四周空地 5 处，离最近巡逻点 ≥30 m，开局不会贴脸；
## 北缘是大坝坝体，不放出生点）
const SPAWN_POINTS := [Vector3(-138.0, 0.0, 138.0), Vector3(10.0, 0.0, 140.0),
	Vector3(140.0, 0.0, 95.0), Vector3(140.0, 0.0, -60.0), Vector3(-140.0, 0.0, -30.0)]

## 局内物资：占背包格；局内按 3/4/5/6（或 Tab 背包「使用」）用掉；撤离带回按价值变卖
const CONSUMABLES := {
	"medkit": {"name": "医疗包", "icon": "医疗", "rarity": 1, "value": 180, "use_t": 3.0},
	"pills": {"name": "止痛药", "icon": "医疗", "rarity": 0, "value": 60, "use_t": 1.2},
	"plate": {"name": "护甲板", "icon": "防具", "rarity": 2, "value": 260, "use_t": 2.0},
	"ammo": {"name": "弹药盒", "icon": "弹药", "rarity": 0, "value": 90, "use_t": 1.5},
}
const USE_KEYS := ["medkit", "pills", "plate", "ammo"]   # 键 3/4/5/6 依次对应
const MEDKIT_HEAL := 50.0          # 医疗包：读条 3 s 后回 50
const PILLS_HEAL := 20.0           # 止痛药：8 s 内缓回 20
const PILLS_TIME := 8.0
const PLATE_ARMOR := 50.0          # 护甲板：+50 护甲（上限 100）
const ARMOR_MAX := 100.0
const ARMOR_ABSORB := 0.6          # 护甲吸收 60% 伤害（吸多少扣多少护甲）
const AMMO_BOX_MAGS := 2           # 弹药盒：当前枪 +2 匣备弹

## 容器分类（改进方案第 5 节）：每个容器照旧出一件变卖物（保险箱搜 5 s、只出蓝色
## 及以上），另按 use_p 概率**额外**再出一件物资——武器箱多出弹药盒/护甲板、医疗箱
## 多出药品。物资是额外掉落、不顶替变卖物：经济门槛 A 不被稀释，背包也更快塞满，
## 逼出「用掉还是扔掉」的取舍
const CONTAINER_CLASS := {
	"weapon": {"name": "武器箱", "search": 1.8, "use_p": 0.45, "pool": [["ammo", 60], ["plate", 40]]},
	"medical": {"name": "医疗箱", "search": 1.8, "use_p": 0.55, "pool": [["medkit", 45], ["pills", 55]]},
	"crate": {"name": "杂物箱", "search": 1.8, "use_p": 0.15,
		"pool": [["medkit", 25], ["pills", 25], ["plate", 25], ["ammo", 25]]},
	"safe": {"name": "保险箱", "search": 5.0, "use_p": 0.0, "pool": [], "min_rarity": 2},
	# 首领保险柜（第四阶段）：首领守着，搜 6 s、只出红色及以上
	"vault": {"name": "首领保险柜", "search": 6.0, "use_p": 0.0, "pool": [], "min_rarity": 5},
	# 空投箱：搜 4 s、紫色及以上 + 必带一件护甲板/医疗包/弹药盒
	"airdrop": {"name": "空投箱", "search": 4.0, "use_p": 1.0, "min_rarity": 3,
		"pool": [["plate", 40], ["medkit", 40], ["ammo", 20]]},
}

## ---- 第四阶段：敌人分级（改进方案第 3 节「普通兵、精英、首领」）----
## hp 生命；armor 护甲（身体中弹先吸 ENEMY_ARMOR_ABSORB，爆头无视护甲）；
## spread 散布倍率（越小越准）；dmg 伤害倍率；pause 射击间歇倍率；react 首发反应倍率
const ENEMY_TIERS := {
	"regular": {"name": "士兵", "hp": 100.0, "armor": 0.0, "spread": 1.0, "dmg": 1.0, "pause": 1.0, "react": 1.0},
	"elite": {"name": "精英", "hp": 100.0, "armor": 60.0, "spread": 0.65, "dmg": 1.2, "pause": 0.8, "react": 0.7},
	"boss": {"name": "首领", "hp": 260.0, "armor": 100.0, "spread": 0.5, "dmg": 1.5, "pause": 0.65, "react": 0.5},
	"scav": {"name": "搜刮者", "hp": 120.0, "armor": 40.0, "spread": 0.8, "dmg": 1.1, "pause": 0.85, "react": 0.8},
}
const ENEMY_ARMOR_ABSORB := 0.5   # 敌方护甲吸收比例（吸多少扣多少护甲）
const ELITE_ZONES := ["center", "dam"]   # 精英只在高价值区：同区巡逻点每 3 名第 2 名是精英
const ELITE_EVERY := 3
## 首领 ×2：守在首领保险柜旁（中心核心巷道 / 大坝坝底），不巡逻，搜索也不离家远；
## 阵亡必掉一件金色及以上
const BOSSES := [
	{"id": "center", "name": "军火商", "pos": Vector3(4.5, 0.0, -11.0), "vault": Vector3(2.0, 0.0, -10.0), "zone": "center"},
	{"id": "dam", "name": "坝区指挥官", "pos": Vector3(-17.0, 0.0, -104.0), "vault": Vector3(-20.0, 0.0, -104.0), "zone": "dam"},
]
const BOSS_LEASH := 18.0          # 首领离家上限（米）：追出这么远就回守
const BOSS_DROP_MIN := 4          # 首领掉落品质下限（金色）

## ---- AI 搜刮者小队（用户勾选「在单机里模拟其他玩家的压力」）----
## 2 支 × 3 人，开局从玩家以外的出生点进图：队长挑最近的未搜容器去搜（抢玩家的箱子），
## 队员跟随；搜够件数或到 18 分钟就去最近的撤离点撤走（带走战利品）。
## 三方混战：守军 ⇄ 搜刮者 ⇄ 玩家互相敌对；搜刮者阵亡掉落身上全部战利品
const SCAV_SQUADS := 2
const SCAV_SIZE := 3
const SCAV_PICKS := [3, 5]        # 每队搜够这么多件就撤（减员到只剩 1 人且有货也撤）
const SCAV_EXFIL_T := 1080.0      # 18 分钟后不管搜没搜够都撤
const SCAV_SEARCH_T := 3.5        # 搜一个箱子要站多久（保险箱 ×2）
const SCAV_STUCK_T := 25.0        # 一个箱子走了这么久还没到 = 卡路，换下一个
const NPC_DMG_MUL := 2.5          # 守军/搜刮者互射伤害倍率（否则互殴要打一分钟）

## ---- 局内事件：空投（改进方案第 6 节「第 10 分钟空投：烟雾信号 + 附近敌人增援」）----
const AIRDROP_T := 600.0
const AIRDROP_H := 80.0           # 投放高度（米）
const AIRDROP_FALL := 4.5         # 伞降速度（米/秒）→ 约 18 s 落地
## 落点候选（过渡区空地，探针实测四周 5 m 无障碍；每局随机一处）
const AIRDROP_POINTS := [Vector3(73.0, 0.0, 61.0), Vector3(-73.0, 0.0, 61.0),
	Vector3(-73.0, 0.0, -61.0), Vector3(73.0, 0.0, -61.0), Vector3(16.0, 0.0, 94.0),
	Vector3(-90.0, 0.0, -32.0)]
const REINFORCE_N := 3            # 空投增援人数（2 普通 + 1 精英）
const REINFORCE_DIST := 38.0      # 增援从落点外这么远处进场
const AIRDROP_ALERT_R := 70.0     # 落点这么远内的守军会赶过去
## 各分区容器分类权重（保险箱只放高价值区；荒野没有）
const CLASS_W := {
	"center": [["safe", 20], ["weapon", 25], ["medical", 20], ["crate", 35]],
	"dam": [["safe", 20], ["weapon", 25], ["medical", 20], ["crate", 35]],
	"mid": [["safe", 6], ["weapon", 25], ["medical", 25], ["crate", 44]],
	"wild": [["weapon", 20], ["medical", 25], ["crate", 55]],
}

## ---- 第四阶段：持续消耗（改进方案第 1/2/3 节：保险、枪械耐久维修、消音器）----
## 保险：出发前付所带装备价值的 30%；阵亡时每件（枪/镜/消音器/备弹）各按 50% 概率退回
const INSURE_RATE := 0.3
const INSURE_RETURN := 0.5
## 耐久：每发 -0.05（约 2,000 发打坏）；低于 60 散布/后坐逐步变大（0 时 ×1.6）；
## 低于 25 每发 4% 卡壳（0.9 s 打不响）。改枪台维修：满修 = 枪价 × 25%
const DUR_PER_SHOT := 0.05
const DUR_WORN := 60.0
const DUR_WORN_MUL := 0.6
const JAM_DUR := 25.0
const JAM_P := 0.04
const JAM_TIME := 0.9
const REPAIR_RATE := 0.25
const REPAIR_BASE_MIN := 400      # 枪价低于此（侦察手枪免费）按此价算维修费
## 消音器：按枪购买、可拆装；开枪惊动半径 60 → 20 m，代价伤害 ×0.92；霰弹枪不能装
const SUP_PRICE := 1200
const SUP_HEAR_R := 20.0
const SUP_DMG_MUL := 0.92
const SUP_BLOCK := ["shotgun"]

## 地图与分区（340m 见方；中心危险区半径 80m）
const MAP_HALF := 170.0
const DANGER_R := 80.0
const HALL_CENTER := Vector3(120.0, 0.0, 130.0)   # 地下靶馆馆心（地图内东南；馆体埋深 -6.94，地表入口房在北侧 (120,154)——2026-10 用户定案「靶场做在地下」：独立空间回归地图，不留空白角）
const EXTRACT_POS := Vector3(128.0, 0.0, 24.0)    # 主撤离点
const DAM_EXTRACT_POS := Vector3(93.0, 0.0, -94.0)   # 第二撤离点（大坝撤离广场，与主撤离直线 122m）
const EXTRACT_R := 3.0                            # 撤离判定半径
const EXTRACT_HOLD := 5.0                         # 撤离读条秒数

## 按分区权重 roll 品质档（0..6）
static func roll_rarity(zone: String) -> int:
	var w: Array = RARITY_W.get(zone, RARITY_W["mid"])
	var total := 0
	for x in w:
		total += int(x)
	var r := randi() % total
	for i in w.size():
		r -= int(w[i])
		if r < 0:
			return i
	return 0

## 开箱 roll 一件变卖物：{uid,name,rarity,value,icon}
static func roll_loot(zone: String) -> Dictionary:
	var rid := roll_rarity(zone)
	var tier: Array = LOOT_NAMES[rid]
	var pick: Array = tier[randi() % tier.size()]
	var rar: Dictionary = RARITY[rid]
	var value := randf_range(float(rar["vmin"]), float(rar["vmax"]))
	value = float(int(value))   # 整数取整（重定价后白色 20–50，按 10 取整只剩 4 个值）
	return {
		"uid": "%d_%d" % [Time.get_ticks_msec(), randi() % 1000000],
		"name": String(pick[0]), "icon": String(pick[1]),
		"rarity": rid, "value": value,
	}


## 加权表 [[key, w], ...] 按 rng（缺省全局随机）取一个 key
static func pick_weighted(table: Array, rng: RandomNumberGenerator = null) -> String:
	var total := 0
	for e in table:
		total += int(e[1])
	if total <= 0:
		return str(table[0][0]) if not table.is_empty() else ""
	var r := (rng.randi() if rng != null else randi()) % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return str(e[0])
	return str(table[0][0])


## 局内物资实物：{uid,name,icon,rarity,value,use}
static func make_consumable(kind: String) -> Dictionary:
	var c: Dictionary = CONSUMABLES.get(kind, CONSUMABLES["medkit"])
	return {
		"uid": "%d_%d" % [Time.get_ticks_msec(), randi() % 1000000],
		"name": str(c["name"]), "icon": str(c["icon"]), "rarity": int(c["rarity"]),
		"value": float(c["value"]), "use": kind,
	}


## 容器额外物资：按 use_p 掷一件（没掷中返回 {}）
static func roll_bonus(cls: String) -> Dictionary:
	var cc: Dictionary = CONTAINER_CLASS.get(cls, CONTAINER_CLASS["crate"])
	if (cc["pool"] as Array).is_empty() or randf() >= float(cc["use_p"]):
		return {}
	return make_consumable(pick_weighted(cc["pool"]))


## 按容器分类开箱的变卖物：保险箱品质下限蓝色，其余同分区 roll_loot
static func roll_container(cls: String, zone: String) -> Dictionary:
	var cc: Dictionary = CONTAINER_CLASS.get(cls, CONTAINER_CLASS["crate"])
	return roll_min(zone, int(cc.get("min_rarity", 0)))


## 品质下限 roll：分区权重里低于 min_r 的档位清零后重新归一（保险箱/首领掉落）
static func roll_min(zone: String, min_r: int) -> Dictionary:
	if min_r <= 0:
		return roll_loot(zone)
	var w: Array = (RARITY_W.get(zone, RARITY_W["mid"]) as Array).duplicate()
	for i in mini(min_r, w.size()):
		w[i] = 0
	var total := 0
	for x in w:
		total += int(x)
	var rid := min_r
	if total > 0:
		var r := randi() % total
		for i in w.size():
			r -= int(w[i])
			if r < 0:
				rid = i
				break
	var it := roll_loot(zone)
	var tier: Array = LOOT_NAMES[rid]
	var pick: Array = tier[randi() % tier.size()]
	var rar: Dictionary = RARITY[rid]
	it["rarity"] = rid
	it["name"] = String(pick[0])
	it["icon"] = String(pick[1])
	it["value"] = float(int(randf_range(float(rar["vmin"]), float(rar["vmax"]))))
	return it


## 图标归一化：空 → 默认徽标；旧档 emoji → 中文徽标；其余原样放行（已是徽标文字）
static func norm_icon(icon: String) -> String:
	var ic := icon.strip_edges()
	if ic == "":
		return ICON_DEFAULT
	return String(LEGACY_ICONS.get(ic, ic))


## 大厅/HUD 共用 UI 主题：中文字体链设为 default_font（default_font_size 一并给出），
## 挂到各自 UI 根 Control 的 theme 上，全部 Label/Button 继承；
## fallbacks 挂逐字回退链，主字体缺 ₵ 等符号字形时按序补
static func ui_theme() -> Theme:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(UI_FONT_NAMES)
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(UI_FONT_FALLBACK)
	var fbs: Array[Font] = [fb]
	sf.fallbacks = fbs
	var th := Theme.new()
	th.default_font = sf
	th.default_font_size = UI_FONT_SIZE
	return th
