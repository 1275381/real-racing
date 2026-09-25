class_name RRFont
## 共享 UI 字体：系统简体中文字体（Godot 默认字体无 CJK 字形）。
## 必须列出各平台的简中字体：只写 Windows 字体时 macOS 落到 sans-serif（Helvetica），
## 缺字回退到 PingFang.ttc 的繁体字面，敌/军/杀等简体独有字显示成方框

static var _font: SystemFont


static func get_font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray([
			"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun",   # Windows
			# macOS：不用 PingFang SC —— 它解析到 PingFang.ttc 的首个字面（繁体），
			# 同样缺敌/军/杀；系统自动回退也落在这个文件上
			"Hiragino Sans GB", "Heiti SC", "STHeiti",
			"Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei",  # Linux
			"sans-serif",
		])
	return _font


## 设为全局回退字体：所有没单独指定字体的 Control / Label3D（路牌、登机口、
## 赛车场门楼、大战场标牌……）都用它，而不是走系统自动回退挑到繁体字面。
## 每个可直接运行的场景入口 _ready 最先调一次（重复调用无副作用）
static func apply_global() -> void:
	ThemeDB.fallback_font = get_font()
