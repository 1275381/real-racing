"""热成像瞄准镜（Trijicon REAP-IR 形态，×1.2）：整体铝壳 + 锗物镜 + 调焦环 +
橡胶眼罩 + 顶部按键 + 左侧电池仓 + 快拆座。"""
import math
import gun_kit as K
from gun_kit import Group, side, xsec, top, lathe, box, cyl

META = dict(ref=(0.0, 0.0, 0.0), target=(0.0, 0.0, 0.0), length=None, size=1024)
AY = 0.066


def build():
    side("body", [(-0.17, 0.024), (0.0, 0.024), (0.004, 0.034, 0.006), (0.004, 0.098, 0.01), (-0.012, 0.106, 0.008),
                  (-0.15, 0.106, 0.008), (-0.172, 0.09, 0.01)], -0.031, 0.031, "alu", r=0.002, bevel=0.003)
    # 物镜：遮光筒 + 调焦滚花环 + 锗镜片
    lathe("objective", [(-0.205, 0.0325), (-0.2, 0.0335), (-0.185, 0.0335), (-0.18, 0.03), (-0.165, 0.03)],
          "alu", cy=AY, segs=40)
    g = Group()
    for k in range(24):
        a = k * 15.0
        g.box((0.0302 * math.cos(math.radians(a)), AY + 0.0302 * math.sin(math.radians(a)), -0.1725),
              (0.003, 0.003, 0.012))
    g.done("focus_knurl", "rubber", bevel=0.0006)
    cyl("germanium", (0.0, AY, -0.2035), 0.029, 0.001, "lens", axis="z", segs=40, bevel=0.0)
    # 橡胶眼罩
    lathe("eyecup", [(0.002, 0.018), (0.02, 0.019), (0.034, 0.024), (0.036, 0.022), (0.03, 0.0175), (0.006, 0.0165)],
          "rubber", cy=AY + 0.004, segs=36)
    cyl("eyelens", (0.0, AY + 0.004, 0.006), 0.0165, 0.001, "lens", axis="z", segs=32, bevel=0.0)
    # 顶部三键 + 左侧电池仓盖 + 右侧快拆扳把
    g = Group()
    for z in (-0.07, -0.055, -0.04):
        g.cyl((0.0, 0.1075, z), 0.0042, 0.004, axis="y", segs=16)
    g.done("buttons", "rubber", bevel=0.001)
    cyl("battery_cap", (-0.0335, 0.06, -0.11), 0.011, 0.006, "alu", axis="x", segs=28)
    # 快拆座
    g = Group()
    g.side([(-0.14, -0.0055), (-0.05, -0.0055), (-0.05, 0.026), (-0.14, 0.026)], -0.0215, 0.0215)
    g.done("mount", "alu", bevel=0.0015)
    side("qd_lever", [(-0.13, 0.002), (-0.06, 0.004, 0.003), (-0.058, 0.011, 0.003), (-0.128, 0.011, 0.002)],
         0.0215, 0.0255, "alu", bevel=0.0006)
