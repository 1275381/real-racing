class_name Guns
## 枪械店目录：5 种枪械数值/价格。
## stats 约定：dmg 单发伤害 / cd 开火间隔 / mag 弹匣 / reload 换弹秒数 /
## pellets 弹丸数（霰弹）/ spread 散布弧度 / scope_div 开镜倍数 / range 射程

const GUNS := [
	{"id": "pistol", "name": "侦察手枪", "desc": "伤害 25 · 半自动 · 12 发", "price": 0,
		"dmg": 25.0, "cd": 0.25, "mag": 12, "reload": 1.2, "pellets": 1,
		"spread": 0.0, "scope_div": 1.0, "range": 180.0},
	{"id": "smg", "name": "冲锋枪", "desc": "伤害 15 · 全自动 · 35 发", "price": 800,
		"dmg": 15.0, "cd": 0.08, "mag": 35, "reload": 1.6, "pellets": 1,
		"spread": 0.02, "scope_div": 1.0, "range": 150.0},
	{"id": "rifle", "name": "突击步枪", "desc": "伤害 20 · 全自动 · 30 发", "price": 1500,
		"dmg": 20.0, "cd": 0.13, "mag": 30, "reload": 1.5, "pellets": 1,
		"spread": 0.015, "scope_div": 3.0, "range": 250.0},
	{"id": "shotgun", "name": "霰弹枪", "desc": "伤害 12×6 散射 · 近战毁灭性", "price": 2000,
		"dmg": 12.0, "cd": 0.8, "mag": 6, "reload": 2.2, "pellets": 6,
		"spread": 0.055, "scope_div": 1.0, "range": 60.0},
	{"id": "sniper", "name": "狙击步枪", "desc": "伤害 100 · 高倍镜 6× · 5 发", "price": 3000,
		"dmg": 100.0, "cd": 1.2, "mag": 5, "reload": 2.4, "pellets": 1,
		"spread": 0.0, "scope_div": 6.0, "range": 400.0},
]


## 大战场兵种配发枪械（不进枪械店）
const BATTLE_GUNS := [
	{"id": "lmg", "name": "轻机枪", "desc": "伤害 18 · 全自动 · 80 发", "price": 0,
		"dmg": 18.0, "cd": 0.1, "mag": 80, "reload": 3.2, "pellets": 1,
		"spread": 0.022, "scope_div": 2.0, "range": 220.0},
]


static func gun_by_id(id: String) -> Dictionary:
	for g in GUNS:
		if g["id"] == id:
			return g
	for g in BATTLE_GUNS:
		if g["id"] == id:
			return g
	return GUNS[0]


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


# 瞄具：安装到枪上（每枪一槽），未装 = 机瞄。zoom 为开镜倍率；
# kind 决定镜面风格（iron/holo/reddot/optic/sniper/thermal）
const SCOPES := [
	{"id": "holo", "name": "全息镜", "desc": "1.5× · 全息方框绿点 · 视野宽", "price": 900,
		"zoom": 1.5, "kind": "holo"},
	{"id": "reddot", "name": "红点镜", "desc": "1.5× · 单圈红点 · 快速获取", "price": 700,
		"zoom": 1.5, "kind": "reddot"},
	{"id": "optic35", "name": "3.5× 光学镜", "desc": "3.5× · 密位十字 · 中距离精确", "price": 1800,
		"zoom": 3.5, "kind": "optic"},
	{"id": "scope5", "name": "5× 密位镜", "desc": "5× · 暗角密位 · 远距离", "price": 2800,
		"zoom": 5.0, "kind": "sniper"},
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
]


static func grip_by_id(id: String) -> Dictionary:
	for g in GRIPS:
		if g["id"] == id:
			return g
	return GRIPS[0]


static func scope_by_id(id: String) -> Dictionary:
	for s in SCOPES:
		if s["id"] == id:
			return s
	return {}
