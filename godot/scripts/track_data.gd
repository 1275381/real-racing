class_name TrackData
## 赛道/车队/车型数据（移植自 js/trackConfig.js 与 js/carModels.js）
## 每条赛道为一组 CatmullRom 控制点（世界坐标 XZ 平面）+ 主题
## theme: "country" 草地乡野 | "city" 城市建筑 | "desert" 沙漠荒野

const ROAD_HALF_W := 7.0
const DEFAULT_LAPS := 3

const TRACKS := [
	{
		"id": "circuit", "theme": "country",
		"name": "极速环道", "desc": "技术型 · 回头发夹扇区",
		"points": [
			Vector2(-212, -168), Vector2(-95, -177), Vector2(45, -171), Vector2(155, -158),
			Vector2(218, -116), Vector2(250, -46), Vector2(256, 58), Vector2(233, 138),
			Vector2(178, 197), Vector2(166, 224), Vector2(146, 206), Vector2(127, 144),
			Vector2(124, 101), Vector2(98, 98), Vector2(81, 119), Vector2(75, 192),
			Vector2(56, 225), Vector2(-66, 233), Vector2(-158, 204), Vector2(-213, 131),
			Vector2(-227, 18), Vector2(-212, -112),
		],
	},
	{
		"id": "bay", "theme": "country",
		"name": "海湾冲刺", "desc": "高速流畅 · 长直道尾速为王",
		"points": [
			Vector2(-180, -140), Vector2(-40, -150), Vector2(30, -162), Vector2(100, -135),
			Vector2(190, -90), Vector2(238, 5), Vector2(255, 65), Vector2(205, 118),
			Vector2(120, 170), Vector2(10, 185), Vector2(-95, 195), Vector2(-185, 150),
			Vector2(-225, 55), Vector2(-235, -50), Vector2(-215, -115),
		],
	},
	{
		"id": "serpent", "theme": "country",
		"name": "蛇形峡谷", "desc": "连续S弯 · 节奏与技术",
		"points": [
			Vector2(-125, -95), Vector2(-35, -112), Vector2(80, -94), Vector2(124, -124),
			Vector2(168, -75), Vector2(175, 5), Vector2(140, 70), Vector2(165, 130),
			Vector2(95, 165), Vector2(5, 150), Vector2(-60, 172), Vector2(-140, 130),
			Vector2(-172, 45), Vector2(-160, -35),
		],
	},
	{
		"id": "horizon", "theme": "desert",
		"name": "地平线耐力", "desc": "碗型高速 · 全油门天堂",
		"points": [
			Vector2(-230, -130), Vector2(-90, -142), Vector2(60, -138), Vector2(180, -118),
			Vector2(258, -60), Vector2(272, 35), Vector2(225, 120), Vector2(130, 162),
			Vector2(20, 172), Vector2(-95, 165), Vector2(-185, 122), Vector2(-262, 30),
			Vector2(-268, -60),
		],
	},
	{
		"id": "city", "theme": "city",
		"name": "都市街区", "desc": "90°直角弯 · 摩天楼间穿行",
		"points": [
			Vector2(-160, -90), Vector2(-60, -95), Vector2(30, -95), Vector2(80, -92),
			Vector2(92, -62), Vector2(94, -23), Vector2(95, 15), Vector2(92, 75), Vector2(85, 122),
			Vector2(48, 128), Vector2(-15, 126), Vector2(-70, 122), Vector2(-108, 115),
			Vector2(-116, 80), Vector2(-113, 25), Vector2(-116, -28), Vector2(-152, -36),
			Vector2(-160, -64),
		],
	},
	{
		"id": "hairpin", "theme": "country",
		"name": "绝壁发夹", "desc": "三层叠弯 · 双发夹刹车地狱",
		"points": [
			Vector2(-170, -125), Vector2(-60, -135), Vector2(40, -128), Vector2(130, -108),
			Vector2(168, -60), Vector2(172, 30), Vector2(150, 95), Vector2(90, 122),
			Vector2(0, 128), Vector2(-90, 122), Vector2(-152, 122), Vector2(-186, 70),
			Vector2(-170, 15), Vector2(-100, 5), Vector2(0, 12), Vector2(95, 5),
			Vector2(138, 18), Vector2(135, -32), Vector2(70, -50), Vector2(-40, -56),
			Vector2(-150, -62), Vector2(-178, -95),
		],
	},
	{
		"id": "canyon", "theme": "desert",
		"name": "赤色荒漠", "desc": "尘土飞扬 · 红岩与仙人掌",
		"points": [
			Vector2(-210, -95), Vector2(-80, -118), Vector2(50, -108), Vector2(160, -65),
			Vector2(235, 5), Vector2(225, 95), Vector2(150, 150), Vector2(30, 162),
			Vector2(-90, 148), Vector2(-175, 105), Vector2(-232, 15),
		],
	},
]

## model 对应 CAR_MODELS 里的车型 id（玩家车型可在主菜单里改）
const TEAM_ROSTER := [
	{"name": "烈焰", "color": Color("#d8331f"), "accent": Color("#ffffff"), "model": "gt3"},
	{"name": "海鲨", "color": Color("#1f56c8"), "accent": Color("#cfe6ff"), "model": "hyper"},
	{"name": "雪鹰", "color": Color("#e8eaee"), "accent": Color("#20242c"), "model": "formula"},
	{"name": "雷霆", "color": Color("#f0b52a"), "accent": Color("#181818"), "model": "muscle"},
]

## 车辆组别：决定引擎声纹与性能基调（每车 stats 在组别基调上体现个性）
const CAR_CLASSES := {
	"street": {"name": "运动街头"},
	"combustion": {"name": "燃油跑车"},
	"hybrid": {"name": "混动电驱"},
	"endurance": {"name": "热芒耐力"},
	"dual": {"name": "燃油 × 耐力双模"},
}

## stats: top 极速(m/s) / power 功率 / accel 牵引上限(m/s²) / grip 抓地倍率 / brake 制动减速度(m/s²)
const CAR_MODELS := [
	{"id": "gt3", "name": "GT3 战驹", "file": "res://assets/cars/car_gt3.glb", "desc": "宽体包覆 · 鹅颈尾翼 · 均衡好开",
		"class": "combustion", "stats": {"top": 89.0, "power": 62.0, "accel": 11.2, "grip": 1.04, "brake": 18.5}},
	{"id": "hyper", "name": "原型超跑", "file": "res://assets/cars/car_hyper.glb", "desc": "极低重心 · 鲨鱼鳍 · 双层尾翼",
		"class": "combustion", "stats": {"top": 91.0, "power": 65.0, "accel": 11.5, "grip": 1.06, "brake": 19.0}},
	{"id": "formula", "name": "方程式", "file": "res://assets/cars/car_formula.glb", "desc": "开轮单体壳 · Halo · 多层前后翼",
		"class": "hybrid", "stats": {"top": 80.0, "power": 70.0, "accel": 14.2, "grip": 1.02, "brake": 19.5, "no_shift": true}},
	{"id": "muscle", "name": "肌肉房车", "file": "res://assets/cars/car_muscle.glb", "desc": "方正宽体 · 增压进气罩 · 侧排气",
		"class": "street", "stats": {"top": 85.0, "power": 58.0, "accel": 10.8, "grip": 0.97, "brake": 17.5}},
	{"id": "rally", "name": "拉力战车", "file": "res://assets/cars/car_rally.glb", "desc": "高底盘两厢 · 四射灯 · 大尾翼",
		"class": "endurance", "stats": {"top": 93.0, "power": 63.0, "accel": 11.6, "grip": 1.07, "brake": 18.8}},
	# AI 生成车模（Tripo）：整块网格无车轮骨架，CarVisual 自动适配（车轮不单独动画）；
	# yaw_deg 把车头摆正到 +Z，scale 归一到约 4.5m 车长
	{"id": "aif1", "name": "AI F1 赛车", "file": "res://assets/cars/car_tripo_a.glb", "desc": "AI 生成 · 红牛涂装 · 开轮式低趴", "yaw_deg": 180.0, "scale": 4.6,
		"class": "hybrid", "stats": {"top": 79.0, "power": 72.0, "accel": 14.6, "grip": 1.03, "brake": 20.0, "no_shift": true}},
	{"id": "aihyper", "name": "AI 蓝色超跑", "file": "res://assets/cars/car_tripo_b.glb", "desc": "AI 生成 · Bolide 风格 · 中置引擎", "yaw_deg": -90.0, "scale": 4.6,
		"class": "combustion", "stats": {"top": 90.0, "power": 64.0, "accel": 11.4, "grip": 1.05, "brake": 18.8}},
	{"id": "aigt", "name": "AI GT 跑车", "file": "res://assets/cars/car_tripo_c.glb", "desc": "AI 生成 · 灰鲨车身 · 大尾翼", "yaw_deg": -90.0, "scale": 4.6,
		"class": "hybrid", "stats": {"top": 79.0, "power": 68.0, "accel": 13.8, "grip": 1.00, "brake": 19.2, "no_shift": true}},
	{"id": "aiwhite", "name": "AI 白色超跑", "file": "res://assets/cars/car_tripo_d.glb", "desc": "AI 生成 · 低风阻概念车身", "yaw_deg": -90.0, "scale": 4.6,
		"class": "endurance", "stats": {"top": 95.0, "power": 66.0, "accel": 11.9, "grip": 1.09, "brake": 19.2}},
	{"id": "aimuscle", "name": "AI 黑色肌肉", "file": "res://assets/cars/car_tripo_e.glb", "desc": "AI 生成 · 宽体肌肉 · 机械增压", "yaw_deg": -90.0, "scale": 4.6,
		"class": "combustion", "stats": {"top": 87.0, "power": 60.0, "accel": 11.1, "grip": 0.99, "brake": 18.0}},
	{"id": "aicyan", "name": "AI 青蓝超跑", "file": "res://assets/cars/car_tripo_f.glb", "desc": "AI 生成 · 竞技大尾翼 · 兰博风格", "yaw_deg": -90.0, "scale": 4.6,
		"class": "hybrid", "stats": {"top": 80.0, "power": 69.0, "accel": 14.0, "grip": 1.01, "brake": 19.0, "no_shift": true}},
	# 双组别旗舰：燃油跑车 × 热芒耐力。modes 双模式（O 键切换）：
	# accel 加速模式（高牵引） / top 极速模式（高极速），sound 为对应引擎声纹组别
	{"id": "aidual", "name": "AI 赤焰双模", "file": "res://assets/cars/car_tripo_g.glb", "desc": "AI 生成 · 双组别旗舰 · O 键切换加速/极速模式", "yaw_deg": -90.0, "scale": 4.6,
		"class": "dual", "stats": {"top": 96.0, "power": 64.0, "accel": 11.8, "grip": 1.07, "brake": 19.2},
		"modes": {
			"accel": {"label": "加速模式", "top": 87.0, "power": 72.0, "accel": 14.2, "grip": 1.09, "brake": 20.0},
			"top": {"label": "极速模式", "top": 96.0, "power": 64.0, "accel": 11.8, "grip": 1.07, "brake": 19.2},
		}},
]

const DEFAULT_MODEL := "gt3"

const DIFF_PRESETS := {
	"easy": {"label": "轻松", "skills": [0.90, 0.86, 0.83]},
	"normal": {"label": "标准", "skills": [1.00, 0.97, 0.94]},
	"hard": {"label": "硬核", "skills": [1.06, 1.03, 1.00]},
}

const CAM_MODES := ["追尾远", "追尾近", "车头盖"]


static func model_by_id(id: String) -> Dictionary:
	for m in CAR_MODELS:
		if m["id"] == id:
			return m
	return CAR_MODELS[0]


static func track_index_by_id(id: String) -> int:
	var tracks := get_tracks()
	for i in tracks.size():
		if tracks[i]["id"] == id:
			return i
	return 0


# ============================================================
#  自定义赛道（地图编译器产出）：
#  源文件 user://custom_tracks/<id>.json，启动时合并进赛道列表
# ============================================================

const CUSTOM_DIR := "user://custom_tracks"

static var _custom_cache: Array = []
static var _custom_loaded := false
static var pending_track_id := ""   # 编辑器「试驾」：主场景启动后直接开这条赛道


## 内置 + 自定义的完整赛道列表
static func get_tracks() -> Array:
	if not _custom_loaded:
		_load_custom_tracks()
	return TRACKS + _custom_cache


static func reload_custom_tracks() -> void:
	_custom_loaded = false
	get_tracks()


static func _load_custom_tracks() -> void:
	_custom_loaded = true
	_custom_cache = []
	DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	var dir := DirAccess.open(CUSTOM_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var def := def_from_json(JSON.parse_string(
				FileAccess.get_file_as_string(CUSTOM_DIR + "/" + f)))
		if not def.is_empty():
			_custom_cache.append(def)


## JSON → 赛道定义（points 转 Vector3 数组）；非法返回空字典
static func def_from_json(data) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var raw: Array = data.get("points", [])
	if raw.size() < 3:
		return {}
	var points := []
	for p in raw:
		if p is Dictionary and p.has_all(["x", "z"]):
			points.append(Vector3(float(p["x"]), float(p.get("y", 0.0)), float(p["z"])))
	if points.size() < 3:
		return {}
	return {
		"id": String(data.get("id", "")),
		"name": String(data.get("name", "自定义赛道")),
		"desc": String(data.get("desc", "")),
		"theme": String(data.get("theme", "country")),
		"points": points,
	}


## 赛道定义 → JSON 字典（points 转 {x,y,z}）
static func def_to_json(def: Dictionary) -> Dictionary:
	var pts := []
	for p in def["points"]:
		pts.append({"x": p.x, "y": p.y, "z": p.z})
	return {
		"id": def["id"], "name": def["name"], "desc": def.get("desc", ""),
		"theme": def.get("theme", "country"), "points": pts,
	}


static func save_custom_track(def: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	var f := FileAccess.open(CUSTOM_DIR + "/" + def["id"] + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(def_to_json(def), "  "))
	f.close()
	reload_custom_tracks()
	return true


static func list_custom_tracks() -> Array:
	reload_custom_tracks()
	return _custom_cache


static func delete_custom_track(id: String) -> void:
	var path := CUSTOM_DIR + "/" + id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	reload_custom_tracks()


## 闭合 Catmull-Rom 密集采样（与 RaceTrack.build 同一套公式），支持 Vector2/Vector3 混合
static func sample_closed_spline(points: Array, per_seg := 12) -> PackedVector3Array:
	var m := points.size()
	if m < 3:
		return PackedVector3Array()
	var cps := PackedVector3Array()
	cps.resize(m)
	for i in m:
		var p = points[i]
		if p is Vector3:
			cps[i] = p
		else:
			cps[i] = Vector3(p.x, 0.0, p.y)
	const TENSION := 0.55
	var dense := PackedVector3Array()
	dense.resize(m * per_seg)
	for i in m:
		var p0 := cps[(i - 1 + m) % m]
		var p1 := cps[i]
		var p2 := cps[(i + 1) % m]
		var p3 := cps[(i + 2) % m]
		var v0 := (p2 - p0) * TENSION
		var v1 := (p3 - p1) * TENSION
		for k in per_seg:
			var t := float(k) / per_seg
			var t2 := t * t
			var t3 := t2 * t
			dense[i * per_seg + k] = (
				(2.0 * p1 - 2.0 * p2 + v0 + v1) * t3
				+ (3.0 * p2 - 3.0 * p1 - 2.0 * v0 - v1) * t2
				+ v0 * t + p1)
	return dense


## 编译校验：返回 {ok, errors: PackedStringArray, length, count}
static func validate_track(points: Array) -> Dictionary:
	var out := {"ok": false, "errors": PackedStringArray(),
			"length": 0.0, "count": points.size()}
	if points.size() < 6:
		out["errors"].append("控制点不足（至少 6 个，当前 %d）" % points.size())
		return out
	var dense := sample_closed_spline(points, 12)
	var cnt := dense.size()
	var length := 0.0
	for i in cnt:
		length += dense[i].distance_to(dense[(i + 1) % cnt])
	out["length"] = length
	if length < 200.0:
		out["errors"].append("赛道周长太短（%dm，至少 200m）" % int(length))
	if length > 9000.0:
		out["errors"].append("赛道周长太长（%dm，至多 9000m）" % int(length))
	for p in points:
		if p.y > 50.0 or p.y < 0.0:
			out["errors"].append("高度超出范围（0 ~ 50m）")
			break
	# 自交 / 路面过近：XZ 平面上非相邻采样段的最小距离（发夹弯进出段合法贴身 ~14m，
	# 曲线穿越自身则接近 0 → 判自交）
	var min_gap := 4.0
	var stride := 2
	var min_d := 1e9
	for i in range(0, cnt, stride):
		var a := Vector2(dense[i].x, dense[i].z)
		for j in range(i + stride, cnt, stride):
			if mini(j - i, cnt - (j - i)) < 12:
				continue
			min_d = minf(min_d, a.distance_to(Vector2(dense[j].x, dense[j].z)))
	if min_d < min_gap:
		out["errors"].append("赛道自交（路段在 XZ 平面穿越自身，最小间距 %.1fm）" % min_d)
		return out
	out["ok"] = out["errors"].is_empty()
	return out
