class_name RRFont
## 共享 UI 字体：Windows 系统中文字体（Godot 默认字体无 CJK 字形）

static var _font: SystemFont


static func get_font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray([
			"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun", "sans-serif",
		])
	return _font
