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

## 各档变卖物例表（图标 + 名称池，roll 时随机取名）
const LOOT_NAMES := [
	[["绷带", "🩹"], ["润滑油罐", "🛢"], ["废料零件", "🔩"], ["旧手表", "⌚"]],
	[["止痛药", "💊"], ["战术护目镜", "🥽"], ["工具组", "🧰"], ["罐头食品", "🥫"]],
	[["精密零件", "⚙"], ["急救包", "🧰"], ["军用电池", "🔋"], ["夜视仪", "👓"]],
	[["军用电路板", "📡"], ["防弹插板", "🛡"], ["加密硬盘", "💾"], ["狙击镜片", "🔭"]],
	[["金条", "🪙"], ["名贵腕表", "⌚"], ["显卡", "🎰"], ["机密文件", "🗂"]],
	[["机械外骨骼", "🦾"], ["原型芯片", "💠"], ["卫星通讯机", "📶"]],
	[["至臻黑箱", "🏆"], ["龙标藏品", "🐉"]],
]

## 每把枪的备弹（弹匣外储备；pistol/smg/shotgun/sniper 对齐网页版实测值）
const RESERVE := {
	"pistol": 60, "smg": 175, "rifle": 150, "shotgun": 30, "sniper": 25,
}

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
