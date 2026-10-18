"""5× 可变倍率步枪瞄准镜（30 mm 主管 ×1.2）：物镜钟 + 主管 + 调节鞍座三塔 +
倍率环 + 目镜钟 + 两只镜圈（导轨夹座）。"""
import gun_kit as K
from gun_kit import Group, side, lathe, box, cyl

META = dict(ref=(0.0, 0.0, 0.0), target=(0.0, 0.0, 0.0), length=None, size=1024)
AY = 0.05


def build():
    lathe("tube", [(-0.255, 0.0285), (-0.25, 0.0295), (-0.205, 0.0295), (-0.19, 0.0262), (-0.165, 0.0185),
                   (-0.12, 0.018), (-0.06, 0.018), (-0.045, 0.0205), (-0.012, 0.0215), (0.0, 0.0225),
                   (0.03, 0.0235), (0.035, 0.0225)], "alu", cy=AY, segs=48)
    # 倍率环拨杆（右侧）
    side("throw_lever", [(-0.03, AY - 0.003), (-0.016, AY - 0.003), (-0.016, AY + 0.004), (-0.03, AY + 0.004)],
         0.021, 0.031, "alu", bevel=0.0012)
    # 调节鞍座 + 高低（上）/ 风偏（右）/ 视差（左）三塔
    box("saddle", (0.0, AY, -0.09), (0.034, 0.034, 0.05), "alu", bevel=0.004)
    g = Group()
    g.lathe([(AY + 0.016, 0.0125), (AY + 0.034, 0.0125), (AY + 0.036, 0.0105)], cx=0.0, cy=-0.09, segs=28, axis="y")
    g.lathe([(0.016, 0.0115), (0.031, 0.0115), (0.033, 0.0095)], cx=AY, cy=-0.09, segs=28, axis="x")
    g.lathe([(-0.016, 0.011), (-0.03, 0.011), (-0.0315, 0.0095)], cx=AY, cy=-0.09, segs=28, axis="x")
    g.done("turrets", "alu", bevel=0.0007)
    g = Group()
    for k in range(16):
        import math
        a = k * 22.5
        g.box((0.0127 * math.cos(math.radians(a)), AY + 0.026, -0.09 + 0.0127 * math.sin(math.radians(a))),
              (0.0018, 0.012, 0.0018))
    g.done("turret_knurl", "alu", bevel=0.0003)
    # 镜片
    cyl("lens_front", (0.0, AY, -0.2545), 0.0262, 0.001, "lens", axis="z", segs=48, bevel=0.0)
    cyl("lens_rear", (0.0, AY, 0.0345), 0.0195, 0.001, "lens", axis="z", segs=40, bevel=0.0)
    # 两只镜圈：环 + 立柱 + 导轨夹座 + 横螺栓
    for z in (-0.145, -0.035):
        g = Group()
        g.lathe([(z - 0.008, 0.0225), (z + 0.008, 0.0225)], cy=AY, segs=40)
        g.side([(z - 0.008, -0.0055), (z + 0.008, -0.0055), (z + 0.008, AY - 0.016), (z - 0.008, AY - 0.016)], -0.0175, 0.0175)
        g.done("ring%d" % int(z * 1000), "alu", bevel=0.0012)
        cyl("ring_bolt%d" % int(z * 1000), (0.0, -0.0022, z), 0.0028, 0.044, "steel", axis="x", segs=12)
        cyl("ring_cap%d" % int(z * 1000), (0.0, AY + 0.0228, z), 0.0035, 0.002, "steel", axis="y", segs=12)
