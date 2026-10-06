#!/bin/bash
# 双击启动：烽火地带（Godot 版 FPS，搜刮→撤离）
# 前置：Godot.app 已安装（/Applications/Godot.app）
cd "$(dirname "$0")"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$GODOT" ]; then
	echo "未找到 Godot：$GODOT"
	exit 1
fi
echo "🔥 正在启动 烽火地带（Godot 版）..."
"$GODOT" --path godot res://huodai/main.tscn
