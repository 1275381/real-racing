"""M14 战术护木配件（商店配件「战术护木」）：前托下方的随形垫座 + 倒挂皮卡汀尼短轨
（两颗固定螺钉）+ 垂直前握把（RVG 式：导轨夹座 + 横穿螺栓 + 前缘指槽）。
真实尺寸，坐标同 m14 本体（z 向后、y=0 枪膛轴线）。"""
import m14 as M
from gun_kit import Group, side, cyl
from _m14_part import meta

META = meta()

Z0, Z1 = -0.378, -0.272      # 导轨前后端
ZG = -0.33                   # 握把中心


def rail_down(name, z0, z1, y, zone="alu"):
    """倒挂导轨：底座 y..y-0.0035，燕尾齿朝下（齿底 y-0.0066），10 mm 节距"""
    g = Group()
    g.xsec([(-0.0078, y), (0.0078, y), (0.0078, y - 0.0035), (-0.0078, y - 0.0035)], z0, z1)
    tooth = [(-0.0078, y - 0.0025), (0.0078, y - 0.0025), (0.0106, y - 0.0045), (0.0106, y - 0.0057),
             (0.0095, y - 0.0066), (-0.0095, y - 0.0066), (-0.0106, y - 0.0057), (-0.0106, y - 0.0045)]
    n = int((z1 - z0 - 0.002) / 0.01)
    off = (z1 - z0 - n * 0.01) * 0.5
    for k in range(n):
        za = z0 + off + k * 0.01 + 0.0026
        g.xsec(tooth, za, za + 0.0048)
    return g.done(name, zone, bevel=0.0004)


def build():
    yr = min(M.YB(Z0), M.YB(Z1), M.YB((Z0 + Z1) * 0.5)) - 0.003    # 导轨顶面（平）
    # 随形垫座：上沿贴前托底弧线（略嵌入木头），下沿平——吃掉护木底面坡度
    pts = []
    n = 8
    for k in range(n + 1):
        z = Z0 + (Z1 - Z0) * k / n
        pts.append((z, M.YB(z) + 0.0025))
    pts += [(Z1, yr), (Z0, yr)]
    side("fg_riser", pts, -0.0088, 0.0088, "alu", bevel=0.0008)
    rail_down("fg_rail", Z0 + 0.004, Z1 - 0.004, yr, "alu")
    g = Group()
    for z in (Z0 + 0.009, Z1 - 0.009):
        g.cyl((0.0, yr - 0.0037, z), 0.0032, 0.0014, axis="y", segs=14)
    g.done("fg_screws", "steel", bevel=0.0003)
    # 垂直前握把：夹座（包住导轨齿）+ 握把体
    yt = yr - 0.0066
    side("fg_clamp", [(ZG - 0.019, yt + 0.0032), (ZG + 0.019, yt + 0.0032), (ZG + 0.019, yt - 0.011, 0.003),
                      (ZG - 0.019, yt - 0.011, 0.003)], -0.0128, 0.0128, "poly", bevel=0.0012)
    cyl("fg_bolt", (0.0, yt - 0.003, ZG + 0.011), 0.0026, 0.0298, "steel", axis="x", segs=12)
    h = 0.088
    body = [(ZG + 0.016, yt - 0.008), (ZG + 0.0155, yt - h * 0.5, 0.012), (ZG + 0.013, yt - h, 0.008),
            (ZG - 0.017, yt - h - 0.002, 0.008)]
    # 前缘三道指槽（自下而上）
    for k, fy in enumerate((0.075, 0.053, 0.031)):
        zf = ZG - 0.019 + 0.0012 * k
        body += [(zf, yt - fy - 0.006, 0.004), (zf + 0.004, yt - fy, 0.004), (zf, yt - fy + 0.006, 0.004)]
    body += [(ZG - 0.018, yt - 0.008)]
    side("fg_grip", body, -0.0118, 0.0118, "poly", r=0.002, bevel=0.0032, segs=3)
    # 握把底端盖（防滑橡胶）
    side("fg_cap", [(ZG + 0.0128, yt - h + 0.0005), (ZG - 0.017, yt - h - 0.0015), (ZG - 0.016, yt - h - 0.006, 0.002),
                    (ZG + 0.012, yt - h - 0.0045, 0.002)], -0.011, 0.011, "rubber", bevel=0.0015)
