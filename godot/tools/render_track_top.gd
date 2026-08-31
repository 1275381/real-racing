extends SceneTree
## 赛道俯视图渲染器（诊断用）：
##   godot --headless --path . -s res://tools/render_track_top.gd
## 输出 res://tools/out/<id>.png —— 路面/路肩/发车格/起跑线/看台 俯视示意图

const W := 900
const H := 900
const PAD := 60.0

const C_BG := Color("#1b1f26")
const C_ROAD := Color("#4a4f57")
const C_CURB := Color("#d23a2e")
const C_LINE := Color("#e8ecf2")
const C_GRID := Color("#f5d442")
const C_START := Color("#39e07a")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/out")
	for def in TrackData.TRACKS:
		_draw(def)
		print("wrote res://tools/out/%s.png" % def["id"])
	quit()


func _draw(def: Dictionary) -> void:
	var t := RaceTrack.new()
	t.build(def)

	# ---- 世界 → 像素 ----
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in t.pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var span: Vector2 = hi - lo
	var sc: float = minf((W - PAD * 2.0) / maxf(span.x, 1.0), (H - PAD * 2.0) / maxf(span.y, 1.0))
	var ox: float = (W - span.x * sc) * 0.5 - lo.x * sc
	var oy: float = (H - span.y * sc) * 0.5 - lo.y * sc
	var to_px := func(p: Vector2) -> Vector2i:
		return Vector2i(int(p.x * sc + ox), int(p.y * sc + oy))

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(C_BG)

	# ---- 砂石路肩带（外侧 3.4m）----
	for side in [-1.0, 1.0]:
		for i in t.n:
			var j := (i + 1) % t.n
			var a: Vector2 = t.pts[i] - t.left_v[i] * side * (t.half_w + 3.4)
			var b: Vector2 = t.pts[j] - t.left_v[j] * side * (t.half_w + 3.4)
			_line(img, to_px.call(a), to_px.call(b), Color("#6b6152"))

	# ---- 沥青路面（按路宽填充横向线段）----
	for i in t.n:
		var a: Vector2 = t.pts[i] - t.left_v[i] * t.half_w
		var b: Vector2 = t.pts[i] + t.left_v[i] * t.half_w
		_line(img, to_px.call(a), to_px.call(b), C_ROAD)

	# ---- 红白路肩（弯道段，与 _build_road_meshes 同阈值）----
	for i in t.n:
		if absf(t.curv[i]) <= 0.0075:
			continue
		for side in [-1.0, 1.0]:
			var a: Vector2 = t.pts[i] + t.left_v[i] * side * (t.half_w + 0.12)
			var b: Vector2 = t.pts[i] + t.left_v[i] * side * (t.half_w + 1.32)
			_line(img, to_px.call(a), to_px.call(b), C_CURB)

	# ---- 起跑线 ----
	var sp: Vector2 = t.pts[t.start_idx]
	var sl: Vector2 = t.left_v[t.start_idx]
	_line(img, to_px.call(sp - sl * t.half_w), to_px.call(sp + sl * t.half_w), C_START)

	# ---- 发车格 4 位 ----
	for slot in 4:
		var g: Dictionary = t.grid_pose(slot)
		var gp := Vector2((g["pos"] as Vector3).x, (g["pos"] as Vector3).z)
		_dot(img, to_px.call(gp), 4, C_GRID)
		# 车头朝向短线
		var hd: float = g["heading"]
		var fwd := Vector2(sin(hd), cos(hd))
		_line(img, to_px.call(gp), to_px.call(gp + fwd * 6.0), C_LINE)

	# ---- 看台 ----
	var stands := t.get_node_or_null(".")  # 占位，看台直接从 build 复算
	_draw_stands(img, t, to_px)

	img.save_png("res://tools/out/%s.png" % def["id"])


func _draw_stands(img: Image, t: RaceTrack, to_px: Callable) -> void:
	# 1 号：起跑线一侧
	var dir := Vector2(-t.tang[t.start_idx].y, t.tang[t.start_idx].x)
	var p1 := t.pts[t.start_idx] - dir * (t.half_w + 12.5)
	_dot(img, to_px.call(p1), 5, Color("#5fa8ff"))
	# 2 号：最紧弯外侧（复刻 _build_stands 逻辑）
	var tightest := 0
	for i in t.n:
		if absf(t.curv[i]) > absf(t.curv[tightest]):
			tightest = i
	var idx2 := (tightest + 26) % t.n
	var dir2 := t.left_v[idx2]
	var p2 := t.pts[idx2] - dir2 * (t.half_w + 10.5)
	var alt := t.pts[idx2] + dir2 * (t.half_w + 10.5)
	var ref := Vector2(0, 30)
	if alt.distance_to(ref) < p2.distance_to(ref):
		p2 = alt
	_dot(img, to_px.call(p2), 5, Color("#5fa8ff"))


func _dot(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			_put(img, c.x + dx, c.y + dy, col)


func _put(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	img.set_pixel(x, y, col)


func _line(img: Image, a: Vector2i, b: Vector2i, col: Color) -> void:
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var guard := 0
	while guard < 100000:
		guard += 1
		_put(img, x0, y0, col)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
