class_name RRLearnedLines
extends RefCounted
## AI 路线学习：录制玩家走线 → 聚合优化（撞墙路段自动绕开）→ AI 车手复用。
## 每条赛道一条学习线：按赛道进度分 BUCKETS 桶，每桶存玩家平均横向偏移与撞墙计数。
## 撞墙桶用前后干净桶插值绕开，再做平滑 —— AI 沿这条线跑就不会复现玩家的撞墙走线。

const DIR := "user://learned_lines"
const BUCKETS := 200

static var _cache := {}   # track_id -> {"lat": Array[float], "hits": Array[int]}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	DirAccess.make_dir_recursive_absolute(DIR)
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + f))
		if data is Dictionary and data.has("lat") and data["lat"] is Array:
			_cache[String(data.get("track", f.get_basename()))] = {
				"lat": data["lat"], "hits": data.get("hits", []),
			}


## 返回学习线的 lat 数组（无则空数组）
static func line_for(track_id: String) -> Array:
	_ensure_loaded()
	var e = _cache.get(track_id, null)
	return e["lat"] if e != null else []


static func has_line(track_id: String) -> bool:
	_ensure_loaded()
	return _cache.has(track_id)


static func remove(track_id: String) -> void:
	_ensure_loaded()
	_cache.erase(track_id)
	var path := DIR + "/" + track_id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 聚合一圈样本（[{b: 桶号, lat: 横向偏移, hit: 是否撞墙}]）进学习线并保存。
## 撞墙桶：用前后最近的干净桶插值绕开（玩家撞墙的走线不被 AI 复现）。
static func record_lap(track_id: String, lap: Array) -> void:
	if track_id == "" or lap.is_empty():
		return
	_ensure_loaded()
	var lat := []
	var hits := []
	lat.resize(BUCKETS)
	hits.resize(BUCKETS)
	for i in BUCKETS:
		lat[i] = []
		hits[i] = 0
	for s in lap:
		var b: int = wrapi(int(s["b"]), 0, BUCKETS)
		lat[b].append(float(s["lat"]))
		if s.get("hit", false):
			hits[b] += 1
	# 均值
	var avg := []
	avg.resize(BUCKETS)
	for i in BUCKETS:
		avg[i] = 0.0
		if not lat[i].is_empty():
			var sum := 0.0
			for v in lat[i]:
				sum += v
			avg[i] = sum / lat[i].size()
	# 与既有学习线融合（老数据权重 1 : 新圈权重 1）
	var e = _cache.get(track_id, null)
	if e != null:
		var old: Array = e["lat"]
		var old_hits: Array = e["hits"]
		for i in BUCKETS:
			if old_hits[i] > 0:
				hits[i] += int(old_hits[i])
			if lat[i].is_empty() and not old[i].is_empty():
				avg[i] = old[i]
				lat[i] = [old[i]]
	# 撞墙桶插值绕开：撞墙处的横向偏移用前后干净桶线性内插
	for i in BUCKETS:
		if hits[i] <= 0 or lat[i].is_empty():
			continue
		var prev := _find_clean(lat, hits, i, -1)
		var next := _find_clean(lat, hits, i, 1)
		if prev >= 0 and next >= 0 and next > prev:
			var t := float(i - prev) / float(next - prev)
			avg[i] = lerpf(_bucket_avg(lat, prev), _bucket_avg(lat, next), t)
	# 两遍平滑（去毛刺）
	for pass_i in 2:
		var copy := avg.duplicate()
		for i in BUCKETS:
			var a: float = copy[wrapi(i - 1, 0, BUCKETS)]
			var b: float = copy[i]
			var c: float = copy[wrapi(i + 1, 0, BUCKETS)]
			avg[i] = (a + b * 2.0 + c) / 4.0
	_cache[track_id] = {"lat": avg, "hits": hits}
	var f := FileAccess.open(DIR + "/" + track_id + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"track": track_id, "buckets": BUCKETS, "lat": avg, "hits": hits,
		}))
		f.close()


static func _bucket_avg(lat: Array, i: int) -> float:
	var arr: Array = lat[i]
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += v
	return s / arr.size()


## 从 i 出发沿 dir 方向找最近的干净桶（无撞墙且有数据），找不到返回 -1
static func _find_clean(lat: Array, hits: Array, i: int, dir: int) -> int:
	for step in range(1, BUCKETS / 2):
		var idx := wrapi(i + dir * step, 0, BUCKETS)
		if hits[idx] <= 0 and not lat[idx].is_empty():
			return idx
	return -1
