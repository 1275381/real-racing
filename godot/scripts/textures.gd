class_name RRTextures
## 全部纹理均由代码程序生成，无需外部资源（移植自 js/textures.js）

static var _cache := {}


static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _tex(key: String, img: Image) -> ImageTexture:
	# 必须生成 mipmap：材质用了带 mipmap 的各向异性过滤，
	# 无 mipmap 的纹理在 GL 下视为不完整纹理，采样会直接返回白色
	if img.is_compressed() == false and img.get_width() > 1 and img.get_height() > 1:
		img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## 沥青路面：深灰底噪 + 白色边线 + 中央虚线（v 方向沿赛道前进）
static func asphalt() -> ImageTexture:
	if _cache.has("asphalt"):
		return _cache["asphalt"]
	var S := 512
	var img := _img(S, S)
	img.fill(Color("#33353a"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9000:
		var v := 30.0 + rng.randf() * 46.0
		var a := 0.35 + rng.randf() * 0.4
		img.set_pixel(int(rng.randf() * S) % S, int(rng.randf() * S) % S,
				Color(v / 255.0, v / 255.0, (v + 4.0) / 255.0, a))
	# 轻微车辙磨亮痕迹（两条略亮的纵向带）
	for x in S:
		var u := float(x) / S
		var lift := 0.0
		if u > 0.26 and u < 0.38:
			lift = 0.055
		elif u > 0.66 and u < 0.78:
			lift = 0.055
		if lift > 0.0:
			for y in range(0, S, 2):
				var c := img.get_pixel(x, y)
				c = c.lerp(Color(0.83, 0.83, 0.85), lift)
				img.set_pixel(x, y, c)
	# 左右白实线 + 中央白虚线
	img.fill_rect(Rect2i(int(S * 0.035), 0, int(S * 0.018), S), Color(0.92, 0.92, 0.93, 0.85))
	img.fill_rect(Rect2i(int(S * 0.947), 0, int(S * 0.018), S), Color(0.92, 0.92, 0.93, 0.85))
	var white := Color(0.94, 0.94, 0.95, 0.9)
	img.fill_rect(Rect2i(int(S * 0.4915), 0, int(S * 0.017), int(S * 0.33)), white)
	img.fill_rect(Rect2i(int(S * 0.4915), int(S * 0.5), int(S * 0.017), int(S * 0.33)), white)
	return _tex("asphalt", img)


static func grass() -> ImageTexture:
	if _cache.has("grass"):
		return _cache["grass"]
	var S := 512
	var img := _img(S, S)
	img.fill(Color("#4a7c37"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 9000:
		var sh := rng.randf()
		var a := 0.5
		img.set_pixel(int(rng.randf() * S) % S, int(rng.randf() * S) % S,
				Color((40 + sh * 40) / 255.0, (95 + sh * 55) / 255.0, (30 + sh * 30) / 255.0, a))
	for i in 26:
		var cx := rng.randf() * S
		var cy := rng.randf() * S
		var r := 30.0 + rng.randf() * 70.0
		var col := Color((30 + rng.randf() * 36) / 255.0, (80 + rng.randf() * 44) / 255.0,
				(26 + rng.randf() * 24) / 255.0, 0.16)
		_stamp_circle(img, cx, cy, r, col)
	return _tex("grass", img)


## 城市水泥地面（伸缩缝网格）
static func concrete() -> ImageTexture:
	if _cache.has("concrete"):
		return _cache["concrete"]
	var S := 512
	var img := _img(S, S)
	img.fill(Color("#8d9194"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 8000:
		var v := (120.0 + rng.randf() * 40.0) / 255.0
		img.set_pixel(int(rng.randf() * S) % S, int(rng.randf() * S) % S,
				Color(v, v, minf(v + 0.012, 1.0), 0.25 + rng.randf() * 0.3))
	for i in 18:
		_stamp_circle(img, rng.randf() * S, rng.randf() * S, 20.0 + rng.randf() * 60.0,
				Color(70 / 255.0, 72 / 255.0, 76 / 255.0, 0.08 + rng.randf() * 0.12))
	img.fill_rect(Rect2i(0, 0, S, 4), Color(60 / 255.0, 62 / 255.0, 66 / 255.0, 0.85))
	img.fill_rect(Rect2i(0, S - 4, S, 4), Color(60 / 255.0, 62 / 255.0, 66 / 255.0, 0.85))
	img.fill_rect(Rect2i(0, 0, 4, S), Color(60 / 255.0, 62 / 255.0, 66 / 255.0, 0.85))
	img.fill_rect(Rect2i(S - 4, 0, 4, S), Color(60 / 255.0, 62 / 255.0, 66 / 255.0, 0.85))
	img.fill_rect(Rect2i(S / 2 - 2, 0, 4, S), Color(60 / 255.0, 62 / 255.0, 66 / 255.0, 0.85))
	return _tex("concrete", img)


## 沙漠沙地（风纹）
static func sand() -> ImageTexture:
	if _cache.has("sand"):
		return _cache["sand"]
	var S := 512
	var img := _img(S, S)
	img.fill(Color("#d9b677"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 9000:
		var v := rng.randf()
		img.set_pixel(int(rng.randf() * S) % S, int(rng.randf() * S) % S,
				Color((185 + v * 50) / 255.0, (145 + v * 45) / 255.0, (85 + v * 35) / 255.0, 0.5))
	for y in range(0, S, 22):
		var th := 5.0 + rng.randf() * 4.0
		for x in S:
			var yy := int(y + sin(x * 0.03 + y) * 7.0)
			for d in int(th):
				var py := posmod(yy + d, S)
				var c := img.get_pixel(x, py)
				c = c.lerp(Color(160 / 255.0, 125 / 255.0, 70 / 255.0), 0.25)
				img.set_pixel(x, py, c)
	return _tex("sand", img)


## 城市建筑立面（窗格）
static func building() -> ImageTexture:
	if _cache.has("building"):
		return _cache["building"]
	var S := 256
	var img := _img(S, S)
	img.fill(Color("#6e747c"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var cols := 6
	var rows := 8
	var cw := S / cols
	var rh := S / rows
	for yy in rows:
		for xx in cols:
			var lit := rng.randf()
			var col := Color("#39434f")
			if lit < 0.12:
				col = Color("#dfe9ee")
			elif lit < 0.5:
				col = Color("#2c3540")
			img.fill_rect(Rect2i(xx * cw + 5, yy * rh + 6, cw - 10, rh - 12), col)
	for yy in rows:
		img.fill_rect(Rect2i(0, yy * rh + rh - 4, S, 4), Color(40 / 255.0, 44 / 255.0, 50 / 255.0, 0.5))
	return _tex("building", img)
## 车底软阴影贴图
static func blob_shadow() -> ImageTexture:
	if _cache.has("blob"):
		return _cache["blob"]
	var S := 128
	var img := _img(S, S)
	for y in S:
		for x in S:
			var d := Vector2(x - S / 2.0, y - S / 2.0).length() / (S / 2.0)
			var a := 0.0
			if d < 1.0:
				a = lerpf(0.62, 0.42, clampf(d / 0.55, 0.0, 1.0)) if d < 0.55 \
						else lerpf(0.42, 0.0, (d - 0.55) / 0.45)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return _tex("blob", img)


## 斑马线（白条沿 U 方向重复，透明底铺在路面上）
static func zebra() -> ImageTexture:
	if _cache.has("zebra"):
		return _cache["zebra"]
	var W := 128
	var H := 32
	var img := _img(W, H)
	for bar in 4:
		img.fill_rect(Rect2i(bar * 32 + 4, 0, 20, H), Color(0.92, 0.92, 0.94, 0.88))
	return _tex("zebra", img)


## 起跑线黑白格
static func checker(cols: int = 10, rows: int = 2) -> ImageTexture:
	var key := "checker_%d_%d" % [cols, rows]
	if _cache.has(key):
		return _cache[key]
	var cell := 32
	var img := _img(cols * cell, rows * cell)
	for y in rows:
		for x in cols:
			var col := Color("#151515") if (x + y) % 2 == 1 else Color("#efefef")
			img.fill_rect(Rect2i(x * cell, y * cell, cell, cell), col)
	return _tex(key, img)


## 看台“观众”——随机彩色像素点阵
static func crowd() -> ImageTexture:
	if _cache.has("crowd"):
		return _cache["crowd"]
	var W := 512
	var H := 256
	var img := _img(W, H)
	img.fill(Color("#1c2026"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var palette := [
		Color("#e8534a"), Color("#f2a13b"), Color("#f5e663"), Color("#69c56a"),
		Color("#57a7e8"), Color("#9d76e0"), Color("#eeeeee"), Color("#e07a9a"),
	]
	for row in 16:
		var y := 14 + row * 15
		var x := 4
		while x < W - 4:
			if rng.randf() >= 0.08:
				var col: Color = palette[rng.randi() % palette.size()]
				var cx := x + int(rng.randf() * 3)
				var cy := y + int(rng.randf() * 4)
				_stamp_circle(img, cx, cy, 3.4, col)
				img.fill_rect(Rect2i(x + int(rng.randf() * 3) - 3, y + 4, 6, 6), col)
			x += 9
	return _tex("crowd", img)


## 云朵贴图
static func cloud() -> ImageTexture:
	if _cache.has("cloud"):
		return _cache["cloud"]
	var S := 256
	var img := _img(S, S)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for i in 26:
		var cx := S * 0.2 + rng.randf() * S * 0.6
		var cy := S * 0.35 + rng.randf() * S * 0.3
		var r := S * 0.08 + rng.randf() * S * 0.14
		_stamp_circle(img, cx, cy, r, Color(1, 1, 1, 0.75))
	return _tex("cloud", img)


## 在图上叠一个柔和圆斑（近似 radial gradient 的 alpha 合成）
static func _stamp_circle(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var size := img.get_size()
	var x0 := maxi(0, int(cx - r))
	var x1 := mini(size.x - 1, int(cx + r))
	var y0 := maxi(0, int(cy - r))
	var y1 := mini(size.y - 1, int(cy + r))
	if x1 < x0 or y1 < y0:
		return
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x - cx, y - cy).length() / r
			if d > 1.0:
				continue
			var falloff := 1.0 - d * d * 0.65
			var src := img.get_pixel(x, y)
			var a := col.a * falloff
			img.set_pixel(x, y, src.lerp(Color(col.r, col.g, col.b, 1.0), a))
