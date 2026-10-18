"""烽火地带 · 枪模生成入口（美术写实化第五轮）。

  /Applications/Blender.app/Contents/MacOS/Blender -b --python make_gun.py -- <枪 id> [预览/贴图检查目录]

guns/<id>.py 定义 build()（真实米数建模，坐标见 gun_kit 头注）与 META
（ref 真枪握把点 / target 游戏 grip 点 / length 游戏枪长）。
输出 huodai/assets/pbr/models/guns/<id>.glb。环境变量 QUICK=1 只出外形预览、
BAKE_SIZE=1024 降烘焙分辨率（调试用）。
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "guns"))   # guns/ 下的共用件（_optic_common 等）
import gun_kit as K  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
gid = argv[0]
prev = os.path.abspath(argv[1]) if len(argv) > 1 else ""
spec = importlib.util.spec_from_file_location("gun_" + gid, os.path.join(HERE, "guns", gid + ".py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
K.reset()
mod.build()
out = os.path.join(HERE, "..", "..", "assets", "pbr", "models", "guns", gid + ".glb")
K.finish(gid, os.path.abspath(out), preview_dir=prev, tex_dir=prev, **mod.META)
