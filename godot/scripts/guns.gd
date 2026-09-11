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


static func gun_by_id(id: String) -> Dictionary:
	for g in GUNS:
		if g["id"] == id:
			return g
	return GUNS[0]
