## 城市地图存档：底板（烘焙）+ 用户补丁层。
##
## 形状照搬 scripts/track_data.gd 的自定义赛道流水线（那套已经跑通并有 e2e
## 测试），但**不复用它的序列化** —— track_data 的 def_to_json 是硬编码
## 5 键白名单，加字段会被静默丢弃。这里改成「已知键规范化 + 未知键原样保留」，
## 好让底板升级到 v2 时旧存档仍能加载。
##
## 为什么底板是烘焙而不是「跑生成器再打补丁」：
## 建筑的随机流是数据相关的 —— put() 在禁建判定失败时一笔随机数都不抽就
## return，且每栋消耗 4/9/10+ 笔取决于退台/设备房/天线三个分支。所以只要
## 生成器的任何常量变一点，之后每一栋楼都会重排，按序号或按生成顺序挂靠的
## 补丁就会张冠李戴。烘焙把这条流冻住，稳定 id 才有意义。
##
## 由 preload 引用（不走 class_name，避免依赖编辑器的类缓存）。

const BAKE_PATH := "res://data/city_bake_v1.json"
const CUSTOM_DIR := "user://custom_maps"
const DEFAULT_ID := "default"

static var _bake: Dictionary = {}
static var _bake_loaded := false
static var _cache: Array = []
static var _loaded := false
static var pending_map_id := ""   # 编辑器「试驾」：主场景启动后直接进这张城市


# ============================================================
#  底板
# ============================================================

static func bake() -> Dictionary:
	if not _bake_loaded:
		_bake_loaded = true
		var raw := FileAccess.get_file_as_string(BAKE_PATH)
		if raw != "":
			var d = JSON.parse_string(raw)
			if d is Dictionary:
				_bake = d
	return _bake


## 底板建筑记录表（与 FreeroamMap._gen_buildings() 同形状）。
## 取不到就返回空数组，调用方回退到跑生成器。
static func base_buildings() -> Array:
	var b := bake()
	if not b.has("bld"):
		return []
	var out: Array = []
	for e in b["bld"]:
		var r := {"id": String(e["id"]), "x": float(e["x"]), "z": float(e["z"]),
				"w": float(e["w"]), "dep": float(e["dep"]), "h": float(e["h"]),
				"tint": Color(float(e["t"][0]), float(e["t"][1]), float(e["t"][2]), 1.0)}
		if e.has("sb"):
			r["sb"] = {"k": float(e["sb"][0]), "uh": float(e["sb"][1])}
		if e.has("rf"):
			r["rf"] = {"mw": float(e["rf"][0]), "md": float(e["rf"][1]),
					"mh": float(e["rf"][2]), "ox": float(e["rf"][3]),
					"oz": float(e["rf"][4])}
		if e.has("ant"):
			r["ant"] = float(e["ant"])
		out.append(r)
	return out


# ============================================================
#  补丁层
# ============================================================

## 把用户补丁叠到底板上。
## 补丁是**逐字段**的而不是整元素快照：这样「手工拖过位置的楼」在之后做
## 全局操作（例如整体加高）时，没被改过的字段照常参与，改过的保留手动值，
## 两种编辑正交叠加、互不吞噬。
## 返回 {"recs": Array, "orphans": Array} —— 找不到宿主的补丁不静默丢弃，
## 交给调用方提示用户。
static func apply_patches(base: Array, def: Dictionary) -> Dictionary:
	var by_id := {}
	var out: Array = []
	for r in base:
		var c: Dictionary = r.duplicate(true)
		by_id[c["id"]] = c
		out.append(c)

	var orphans: Array = []

	for d in def.get("dels", []):
		var did := String(d)
		if by_id.has(did):
			by_id[did]["_del"] = true
		else:
			orphans.append({"op": "del", "id": did})

	for e in def.get("edits", []):
		var eid := String(e.get("id", ""))
		if not by_id.has(eid):
			orphans.append({"op": "edit", "id": eid, "f": e.get("f", {})})
			continue
		var tgt: Dictionary = by_id[eid]
		for k in e.get("f", {}):
			tgt[k] = _decode_field(k, e["f"][k])

	for a in def.get("adds", []):
		var aid := String(a.get("id", ""))
		if aid == "" or by_id.has(aid):
			orphans.append({"op": "add", "id": aid})
			continue
		var rec := {"id": aid, "x": 0.0, "z": 0.0, "w": 16.0, "dep": 16.0, "h": 20.0,
				"tint": Color(0.78, 0.80, 0.84, 1.0)}
		for k in a.get("f", {}):
			rec[k] = _decode_field(k, a["f"][k])
		by_id[aid] = rec
		out.append(rec)

	var kept: Array = []
	for r in out:
		if not r.has("_del"):
			kept.append(r)
	return {"recs": kept, "orphans": orphans}


static func _decode_field(k: String, v):
	if k == "tint" and v is Array:
		return Color(float(v[0]), float(v[1]), float(v[2]), 1.0)
	if k == "sb" and v is Array:
		return {"k": float(v[0]), "uh": float(v[1])}
	if k == "rf" and v is Array:
		return {"mw": float(v[0]), "md": float(v[1]), "mh": float(v[2]),
				"ox": float(v[3]), "oz": float(v[4])}
	return v


static func encode_field(k: String, v):
	if k == "tint" and v is Color:
		return [snappedf(v.r, 0.00001), snappedf(v.g, 0.00001), snappedf(v.b, 0.00001)]
	if k == "sb" and v is Dictionary:
		return [snappedf(v["k"], 0.00001), snappedf(v["uh"], 0.001)]
	if k == "rf" and v is Dictionary:
		return [snappedf(v["mw"], 0.001), snappedf(v["md"], 0.001),
				snappedf(v["mh"], 0.001), snappedf(v["ox"], 0.001),
				snappedf(v["oz"], 0.001)]
	if v is float:
		return snappedf(v, 0.001)
	return v


# ============================================================
#  存档（一图一文件，与 user://custom_tracks 并列互不干扰）
# ============================================================

static func default_def() -> Dictionary:
	return {"v": 1, "id": DEFAULT_ID, "name": "默认城市", "base": "default",
			"edits": [], "adds": [], "dels": []}


static func get_maps() -> Array:
	if not _loaded:
		_load()
	return [default_def()] + _cache


static func reload() -> void:
	_loaded = false
	get_maps()


static func list_custom_maps() -> Array:
	reload()
	return _cache


static func _load() -> void:
	_loaded = true
	_cache = []
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
			_cache.append(def)


## JSON → 城市定义。已知键规范化，未知键原样保留（底板升级到 v2 时
## 旧存档仍能加载）。非法返回空字典。
static func def_from_json(data) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var id := String(data.get("id", ""))
	if id == "" or id == DEFAULT_ID:
		return {}
	var def: Dictionary = data.duplicate(true)
	def["v"] = int(data.get("v", 1))
	def["id"] = id
	def["name"] = String(data.get("name", "自定义城市"))
	def["base"] = String(data.get("base", "default"))
	for k in ["edits", "adds", "dels"]:
		if not (def.get(k) is Array):
			def[k] = []
	return def


static func def_to_json(def: Dictionary) -> Dictionary:
	var out: Dictionary = def.duplicate(true)
	out["v"] = int(def.get("v", 1))
	return out


static func save_custom_map(def: Dictionary) -> bool:
	if String(def.get("id", "")) in ["", DEFAULT_ID]:
		return false
	DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	var f := FileAccess.open(CUSTOM_DIR + "/" + def["id"] + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(def_to_json(def)))
	f.close()
	reload()
	return true


static func delete_custom_map(id: String) -> void:
	var path := CUSTOM_DIR + "/" + id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	reload()


static func map_by_id(id: String) -> Dictionary:
	for m in get_maps():
		if String(m["id"]) == id:
			return m
	return default_def()


static func new_id(name: String) -> String:
	return "city_%s_%04d" % [name.md5_text().substr(0, 6), randi() % 10000]
