extends Node
## 烽火地带 —— 大厅缩略图（2026-10 用户反馈「需要有图像，提高体验」）：
## 枪械/瞄具卡片配实物图。不画图标：直接拿局内同一套 3D 枪模（含所装瞄具/
## 消音器，HDGuns.build_preview）在离屏独立世界里拍一张透明底照片，缓存成
## ImageTexture——装备一改，键变了自动重拍，图永远和实物一致。
## 排队渲染：每次只拍一张（建模 → 等两帧画完 → 取图），拍完发 shot(key)，
## 大厅把等这张图的 TextureRect 补上，不整页重建。
## headless（测试/集成门槛）没有渲染目标：不排队，tex() 一律返回 null，卡片照常排版。
## 无 class_name（新脚本一律 preload）

signal shot(key: String)

const SIZE := Vector2i(448, 196)
const YAW := 0.32            # 转台角：略带 3/4 侧视，枪身有厚度感
const TILT := 0.16           # 俯视角（弧度）

var enabled := true
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _cache := {}             # key -> ImageTexture
var _queue: Array = []       # [[key, builder]]
var _queued := {}
var _busy := false


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if enabled:
		_build()


## 取缩略图：有缓存直接给；没有就排队（builder 返回待拍的 Node3D），先返回 null
func tex(key: String, builder: Callable) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if enabled and not _queued.has(key):
		_queued[key] = true
		_queue.append([key, builder])
	return null


func cached(key: String) -> Texture2D:
	return _cache.get(key, null)


func _process(_dt: float) -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	_render_next()


func _render_next() -> void:
	var job: Array = _queue.pop_front()
	var key: String = job[0]
	var node: Node3D = (job[1] as Callable).call()
	if node == null:
		_busy = false
		return
	var inner := Node3D.new()
	inner.add_child(node)
	_pivot.add_child(inner)
	_pivot.rotation = Vector3(0, YAW, 0)
	var bb := _aabb_of(node)
	node.position = -bb.get_center()
	# 正交相机按「转台角 + 俯视角」下的屏幕投影外接框取景，四周留 8%
	var dir := Vector3(-cos(TILT), -sin(TILT), 0.0)
	var cb := Basis.looking_at(dir, Vector3.UP)
	var inv := cb.inverse()
	var hw := 0.0
	var hh := 0.0
	var half := bb.size * 0.5
	for i in 8:
		var c := Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1),
				half.z * (1 if i & 4 else -1))
		var q := inv * (_pivot.basis * c)
		hw = maxf(hw, absf(q.x))
		hh = maxf(hh, absf(q.y))
	var aspect := float(SIZE.x) / float(SIZE.y)
	_cam.size = maxf(hh * 2.0, hw * 2.0 / aspect) * 1.08
	_cam.transform = Transform3D(cb, -dir * 6.0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img != null and not img.is_empty():
		_cache[key] = ImageTexture.create_from_image(img)
	_pivot.remove_child(inner)
	inner.queue_free()
	_busy = false
	if _cache.has(key):
		shot.emit(key)


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.68)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# 棚拍三灯：暖主光（左上前）+ 冷轮廓光（后方勾边，暗色枪身在暗卡片上才不糊）+ 顶补光
	for ld in [[Vector3(-30, 50, 0), 2.3, Color(1.0, 0.95, 0.88)],
			[Vector3(-8, -150, 0), 1.5, Color(0.72, 0.84, 1.0)],
			[Vector3(-80, 120, 0), 0.45, Color(1, 1, 1)]]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = ld[0]
		dl.light_energy = float(ld[1])
		dl.light_color = ld[2]
		_vp.add_child(dl)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 20.0
	_vp.add_child(_cam)
	_cam.current = true


static func _aabb_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi_v in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var bb: AABB = xf * mi.mesh.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out
