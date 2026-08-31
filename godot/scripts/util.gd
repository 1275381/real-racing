class_name RRUtil
## 通用数学与格式化工具（移植自 js/util.js）

static func clampf01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func damp(cur: float, target: float, lam: float, dt: float) -> float:
	# 帧率无关的指数平滑
	return lerpf(cur, target, 1.0 - exp(-lam * dt))


static func damp_vec(cur: Vector3, target: Vector3, lam: float, dt: float) -> Vector3:
	return cur.lerp(target, 1.0 - exp(-lam * dt))


static func wrap_angle(a: float) -> float:
	while a > PI:
		a -= PI * 2.0
	while a < -PI:
		a += PI * 2.0
	return a


static func format_time(ms) -> String:
	if ms == null or not is_finite(ms):
		return "--:--.---"
	ms = maxf(0.0, round(float(ms)))
	var m := int(ms / 60000.0)
	var s := int(fmod(ms, 60000.0) / 1000.0)
	var t := int(fmod(ms, 1000.0))
	return "%d:%02d.%03d" % [m, s, t]


static func format_delta(sec) -> String:
	if sec == null or not is_finite(sec):
		return ""
	return ("-" if sec < 0.0 else "+") + "%.3f" % absf(sec)


## 简易确定性伪随机（mulberry32，环境摆放可复现）
class Mulberry:
	var _s: int

	func _init(seed_val: int) -> void:
		_s = seed_val & 0xFFFFFFFF

	func next() -> float:
		_s = (_s + 0x6D2B79F5) & 0xFFFFFFFF
		var t := _s
		t = (t ^ (t >> 15)) * (t | 1) & 0xFFFFFFFF
		t = (t ^ (t + ((t ^ (t >> 7)) * (t | 61) & 0xFFFFFFFF))) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

	func range(a: float, b: float) -> float:
		return a + next() * (b - a)
