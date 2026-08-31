#!/usr/bin/env python3
"""开发/测试用静态服务器：禁用缓存（Cache-Control: no-store）。
正式游玩请用 启动游戏.command（python3 -m http.server）。"""
import sys
from functools import partial
from http.server import HTTPServer, SimpleHTTPRequestHandler


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def log_message(self, *args):
        pass  # 静默


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8044
    srv = HTTPServer(('0.0.0.0', port), NoCacheHandler)
    print(f'serving on http://localhost:{port}/ (no-cache)')
    srv.serve_forever()
