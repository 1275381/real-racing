class_name RRLoadingScreen
extends CanvasLayer
## 加载遮罩：开机 / 换城市时盖住画面，显示标题 + 进度条 + 当前步骤。
## 画面直接用 RenderingServer 画在自有 canvas item 上，不走 Control 重绘 ——
## Control 的重绘靠 call_deferred，而 wait_thread() 等后台建城时主线程刻意
## 不回主循环（不 flush 消息队列），只能靠这种即时绘制 + force_draw 出帧。
## finish() 后先停留片刻（首帧渲染城市还会卡一下），再淡出并自行释放。

const BG := Color("#14171d")
const TRACK := Color("#262b35")
const ACCENT := Color("#ff7a1a")   # 与车库后墙灯线同色
const BAR_W := 520.0
const BAR_H := 6.0

var _ci: RID
var _font: Font
var _status := ""
var _target := 0.0
var _shown := 0.0
var _closing := false
var _hold := 0.0
var _fade := 1.0


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = RRFont.get_font()
	# 透明挡板：加载中不让点穿到下面的菜单/HUD（它自己不画任何东西）
	var block := Control.new()
	block.set_anchors_preset(Control.PRESET_FULL_RECT)
	block.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(block)


func _ready() -> void:
	_ci = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_ci, get_canvas())
	_paint()


func _exit_tree() -> void:
	if _ci.is_valid():
		RenderingServer.free_rid(_ci)
		_ci = RID()


## frac 只进不退；text 为空时保留上一条文案
func set_progress(frac: float, text := "") -> void:
	_target = maxf(_target, clampf(frac, 0.0, 1.0))
	if text != "":
		_status = text if _target >= 1.0 else text + "…"


func finish() -> void:
	set_progress(1.0, "完成")
	_closing = true
	_hold = 0.25


## 主线程在此阻塞等后台线程跑完，其间约 60fps 手动出帧刷新进度。
## poll() 返回 [0..1 进度, 步骤文案]，映射到本页的 [from, to] 区间。
## 刻意不回主循环：后台线程里建 BoxMesh/Label3D 等会 call_deferred 自更新，
## 这些调用排进主线程消息队列；主循环不 flush 就不会与后台线程并发改同一对象，
## 线程结束、回到主循环后再统一执行。
func wait_thread(th: Thread, poll: Callable, from: float, to: float) -> void:
	var last := Time.get_ticks_usec()
	while th.is_alive():
		var p: Array = poll.call()
		set_progress(from + float(p[0]) * (to - from), String(p[1]))
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000000.0
		last = now
		_advance(dt)
		_paint()
		RenderingServer.force_draw(true, dt)
		var spent := (Time.get_ticks_usec() - now) / 1000
		OS.delay_msec(maxi(1, 16 - spent))
	set_progress(to)


func _process(dt: float) -> void:
	_advance(dt)
	_paint()


func _advance(dt: float) -> void:
	# 缓动按真实 dt（上限 0.12s）追目标：卡顿帧后也能很快追上文案
	_shown = lerpf(_shown, _target, 1.0 - exp(-minf(dt, 0.12) * 12.0))
	if _target - _shown < 0.002:
		_shown = _target
	if not _closing or _shown < _target:
		return
	# 淡出钳到 1/30s 一步：进城首帧卡顿时过渡也看得见
	var d := minf(dt, 1.0 / 30.0)
	if _hold > 0.0:
		_hold -= d
		return
	_fade -= d / 0.35
	if _fade <= 0.0:
		queue_free()


func _paint() -> void:
	if not _ci.is_valid() or not is_inside_tree():
		return
	var vs := get_viewport().get_visible_rect().size
	var rs := RenderingServer
	rs.canvas_item_clear(_ci)
	rs.canvas_item_set_modulate(_ci, Color(1, 1, 1, clampf(_fade, 0.0, 1.0)))
	rs.canvas_item_add_rect(_ci, Rect2(Vector2.ZERO, vs), BG)
	var bw := minf(BAR_W, vs.x - 32.0)
	var x0 := (vs.x - bw) * 0.5
	var cy := vs.y * 0.5
	_font.draw_string(_ci, Vector2(x0, cy - 58.0), "极速争锋",
			HORIZONTAL_ALIGNMENT_CENTER, bw, 56, Color.WHITE)
	_font.draw_string(_ci, Vector2(x0, cy - 22.0), "R E A L   R A C I N G",
			HORIZONTAL_ALIGNMENT_CENTER, bw, 16, Color(1, 1, 1, 0.5))
	var by := cy + 28.0
	rs.canvas_item_add_rect(_ci, Rect2(x0, by, bw, BAR_H), TRACK)
	rs.canvas_item_add_rect(_ci, Rect2(x0, by, bw * _shown, BAR_H), ACCENT)
	_font.draw_string(_ci, Vector2(x0, by + 30.0), _status,
			HORIZONTAL_ALIGNMENT_LEFT, bw, 15, Color(1, 1, 1, 0.7))
	_font.draw_string(_ci, Vector2(x0, by + 30.0), "%d%%" % roundi(_shown * 100.0),
			HORIZONTAL_ALIGNMENT_RIGHT, bw, 15, ACCENT)
