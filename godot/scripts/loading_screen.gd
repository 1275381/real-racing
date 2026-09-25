class_name RRLoadingScreen
extends CanvasLayer
## 加载遮罩：开机 / 换城市时盖住画面，显示标题 + 进度条 + 当前步骤。
## 城市构建是主线程上的大块同步计算，只能在步骤之间刷新一帧，
## 所以进度按步骤跳进，显示值再用缓动追上去，避免一顿一顿。
## finish() 后先停留几帧（首帧渲染城市还会卡一下），再淡出并自行释放。

const BG := Color("#14171d")
const TRACK := Color("#262b35")
const ACCENT := Color("#ff7a1a")   # 与车库后墙灯线同色
const BAR_W := 520.0

var _root: Control
var _bar: ColorRect
var _fill: ColorRect
var _status: Label
var _pct: Label
var _target := 0.0
var _shown := 0.0
var _closing := false
var _hold := 0.0
var _fade := 1.0


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # 加载中不让点穿到菜单/HUD
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(BAR_W, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := _label("极速争锋", 56, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("R E A L   R A C I N G", 16, Color(1, 1, 1, 0.5))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	box.add_child(gap)

	_bar = ColorRect.new()
	_bar.color = TRACK
	_bar.custom_minimum_size = Vector2(BAR_W, 6)
	box.add_child(_bar)
	_fill = ColorRect.new()
	_fill.color = ACCENT
	_fill.size = Vector2(0, 6)
	_bar.add_child(_fill)

	var row := HBoxContainer.new()
	box.add_child(row)
	_status = _label("", 15, Color(1, 1, 1, 0.7))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	_pct = _label("0%", 15, ACCENT)
	row.add_child(_pct)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", RRFont.get_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## frac 只进不退；text 为空时保留上一条文案
func set_progress(frac: float, text := "") -> void:
	_target = maxf(_target, clampf(frac, 0.0, 1.0))
	if text != "":
		_status.text = text if _target >= 1.0 else text + "…"


func finish() -> void:
	set_progress(1.0, "完成")
	_closing = true
	_hold = 0.25


func _process(dt: float) -> void:
	# 加载期整段只有几帧、每帧几百毫秒：缓动按真实 dt（上限 0.12s）追，
	# 否则进度条永远落后文案；淡出则钳到 1/30s，卡顿帧里也看得见过渡
	_shown = lerpf(_shown, _target, 1.0 - exp(-minf(dt, 0.12) * 14.0))
	if _target - _shown < 0.002:
		_shown = _target
	_fill.size = Vector2(_bar.size.x * _shown, _bar.size.y)
	_pct.text = "%d%%" % roundi(_shown * 100.0)
	var d := minf(dt, 1.0 / 30.0)
	if not _closing or _shown < _target:
		return
	if _hold > 0.0:
		_hold -= d
		return
	_fade -= d / 0.35
	_root.modulate.a = clampf(_fade, 0.0, 1.0)
	if _fade <= 0.0:
		queue_free()
