class_name HDData
## 烽火地带（Godot 版）共享数据契约 —— 全模块只读这一份表
## 数值移植自网页版 js/fps（loot.js 品质表 / gunsData 弹药储备 / lobby 签到），
## 枪械与瞄具表不在此处：直接用 guns.gd 的 class_name Guns（GUNS/SCOPES/gun_by_id）。

## 七档品质：id 即数组下标 0..6；weight 为荒野/中心两套权重的键
const RARITY := [
	{"id": 0, "name": "白色", "color": Color(0.85, 0.85, 0.85), "vmin": 200.0, "vmax": 500.0},
	{"id": 1, "name": "绿色", "color": Color(0.35, 0.82, 0.43), "vmin": 800.0, "vmax": 1500.0},
	{"id": 2, "name": "蓝色", "color": Color(0.23, 0.63, 1.0), "vmin": 2500.0, "vmax": 5000.0},
	{"id": 3, "name": "紫色", "color": Color(0.66, 0.42, 1.0), "vmin": 8000.0, "vmax": 15000.0},
	{"id": 4, "name": "金色", "color": Color(1.0, 0.79, 0.3), "vmin": 25000.0, "vmax": 60000.0},
	{"id": 5, "name": "红色", "color": Color(1.0, 0.35, 0.25), "vmin": 100000.0, "vmax": 180000.0},
	{"id": 6, "name": "至臻", "color": Color(0.35, 1.0, 0.85), "vmin": 300000.0, "vmax": 500000.0},
]

## 分区开箱品质权重（荒野穷、中心富）：[白,绿,蓝,紫,金,红,彩]
const RARITY_W := {
	"wild": [62, 26, 9, 3, 0, 0, 0],
	"mid": [40, 30, 18, 9, 3, 0, 0],
	"center": [18, 24, 24, 17, 12, 4, 1],
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
	"akm": 150, "m4a1": 150, "scarh": 100,
}

## ---- 极致备弹经济（2026-10）：备弹不再每局免费回满，改为按发购买、局终回收 ----
## 「极致备弹要自己买，买多少就用多少」：出发（行动/靶场）按 stash 库存装填，
## 局终（撤离/死亡/放弃回大厅）把剩余备弹写回库存——弹药不属于战利品，死亡也不掉。
## 首次入账礼物：每把枪第一次进弹药经济（库存缺键）一次性赠送满额备弹
## （满额 = RESERVE 该枪值，老档缺字段同按此规则初始化）——老玩家平滑过渡，
## 赠送后正常买卖、只送一次（实现见 hd_stash.ammo_of）。
const AMMO_NAME := "极致备弹"
const AMMO_COLOR := Color(1.0, 0.79, 0.3)   # 金色标识（与品质金色同值，弹药=硬通货的视效统一）
## 单价（₵/发，按枪定价：手枪贱 · 冲锋枪轻弹 · 步枪中价 · 霰弹/狙击一发一钱）
const AMMO_PRICE := {
	"pistol": 2, "smg": 4, "mp5": 4, "p90": 4, "uzi": 4, "mk4": 4, "vector": 5,
	"rifle": 6, "m4a1": 6, "akm": 6, "scarh": 8, "shotgun": 15, "sniper": 30,
}
## 大厅购买挡位（发数；B 键循环），总价 = 挡位 × 单价
const AMMO_TIERS := [30, 90, 300]

const DAILY_REWARD := 1500   # 每日签到金额（₵）
const BACKPACK_MAX := 12     # 背包格数
const SAVE_PATH := "user://huodai_save.json"

## 地图与分区（340m 见方；中心危险区半径 80m）
const MAP_HALF := 170.0
const DANGER_R := 80.0
const HALL_CENTER := Vector3(120.0, 0.0, 130.0)   # 室内靶馆馆心（行动区东北角外沿）
const EXTRACT_POS := Vector3(128.0, 0.0, 24.0)    # 主撤离点
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
	value = float(int(value / 10.0) * 10)   # 10₵ 取整，好看
	return {
		"uid": "%d_%d" % [Time.get_ticks_msec(), randi() % 1000000],
		"name": String(pick[0]), "icon": String(pick[1]),
		"rarity": rid, "value": value,
	}


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
