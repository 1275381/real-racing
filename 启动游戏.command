#!/bin/bash
# 双击启动：本地起服务器并打开浏览器（必须通过 http 访问，直接双击 index.html 会因浏览器模块限制无法加载）
# 使用禁缓存服务器（tools/serveDev.py），避免浏览器缓存新旧混杂导致加载失败
cd "$(dirname "$0")"
PORT=8017
echo "🏁 正在启动 极速争锋 REAL RACING ..."
echo "   本地服务地址: http://localhost:$PORT/"
echo "   关闭本窗口即停止服务。"
(sleep 0.6 && open "http://localhost:$PORT/index.html") &
python3 tools/serveDev.py $PORT
