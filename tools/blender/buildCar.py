# -*- coding: utf-8 -*-
"""赛车建模总入口（Blender 4/5.x 无头运行）

    Blender --background --python tools/blender/buildCar.py                    # 全部车型
    Blender --background --python tools/blender/buildCar.py -- --spec=gt3      # 指定车型
    Blender --background --python tools/blender/buildCar.py -- --render        # 顺带出预览图
    Blender --background --python tools/blender/buildCar.py -- --views=hero,rear,side

输出 assets/car_<id>.glb，游戏端车型清单见 js/carModels.js（两边 id 必须一致）。
"""
import importlib
import os
import traceback
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
for p in (HERE, os.path.join(HERE, 'specs')):
    if p not in sys.path:
        sys.path.insert(0, p)

import carlib as C     # noqa: E402

SPECS = ['gt3', 'hyper', 'formula', 'muscle', 'rally']


def main():
    a = C.cli_args()
    todo = SPECS if a['spec'] == 'all' else [s for s in a['spec'].split(',') if s]
    views = tuple(v for v in a['views'].split(',') if v)
    ok, t0 = [], time.time()
    bad = []
    for sid in todo:
        t = time.time()
        print('\n▶ 建模 %s' % sid)
        try:                      # 单个车型失败不影响其他车型继续导出
            mod = importlib.import_module(sid)
            importlib.reload(mod)
            mod.build()
            C.assemble()
            C.export(sid)
            if a['render']:
                C.render_preview(sid, views)
            ok.append(sid)
        except Exception:
            traceback.print_exc()
            bad.append(sid)
        print('  用时 %.1fs' % (time.time() - t))
    print('\nALL_DONE %s  总用时 %.1fs' % (','.join(ok), time.time() - t0))
    if bad:
        print('FAILED %s' % ','.join(bad))
        sys.exit(1)


main()
