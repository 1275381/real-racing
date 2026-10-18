"""FN SCAR-H（Mk17 Mod 0 CQC，13" 枪管，FDE 沙色）。

真实尺寸建模（米）：原点 z=0 = 上机匣后端面（折叠托铰链前），y=0 = 枪膛轴线；枪托收到最短位
（全长约 0.815 m：消焰器前缘 z=-0.615 → 托底 z≈+0.200）。
长铝上机匣（cera_fde）+ 通长顶导轨 + 前段左右/下短导轨；聚合物下机匣（poly_fde，一体护圈）；
拉机柄在左侧（随枪机往复）；右折叠伸缩托 + 腮托；20 发 7.62 钢弹匣（黑）。
"""
import math

import bmesh
from mathutils import Matrix, Vector

import gun_kit as K
from gun_kit import Group, side, xsec, top, lathe, box, cyl, cut, cutter_box, taper_x, deform, picatinny

# 握把顶后缘（虎口位）→ 程序化 SCAR-H grip；整枪缩到程序化长度
META = dict(ref=(0.0, -0.0420, -0.0440), target=(0.0, -0.0301, 0.0605), length=1.1125)

UX = 0.0180          # 上机匣半宽
UT = 0.0270          # 上机匣顶面（导轨底座）
UB = -0.0230         # 上机匣底面 / 下机匣顶面
UF = -0.5000         # 上机匣前端
LX = 0.0150          # 下机匣半宽
MX = 0.0175          # 弹匣井半宽
LB = -0.0420         # 下机匣底面（握把段）
MR, MF = -0.1500, -0.2440    # 弹匣井后/前外壁
BF = -0.2350         # 枪机面
MZ = BF - 0.3300     # 枪口（13"）
SB = 0.1860          # 托体后端（收到最短）


# ---------------- 小工具 ----------------

def _rot_new(bm, n0, deg, cx=0.0, cy=0.0):
    bm.verts.ensure_lookup_table()
    bmesh.ops.rotate(bm, cent=K.B(cx, cy, 0.0), matrix=Matrix.Rotation(math.radians(-deg), 3, "Y"),
                     verts=bm.verts[n0:])


def _lathe_loop(bm, prof, cx=0.0, cy=0.0, segs=32):
    rings = []
    for t, rad in prof:
        rings.append([bm.verts.new(K.B(cx + rad * math.cos(2 * math.pi * j / segs),
                                       cy + rad * math.sin(2 * math.pi * j / segs), t)) for j in range(segs)])
    n = len(rings)
    for i in range(n):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for j in range(segs):
            j2 = (j + 1) % segs
            bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))


def _slot(bm, zc, length, width, dist, deg, depth=0.008, cy=0.0):
    n0 = len(bm.verts)
    h = width * 0.5
    K.side_bm(bm, [(zc - length * 0.5, cy - h, h * 0.98), (zc + length * 0.5, cy - h, h * 0.98),
                   (zc + length * 0.5, cy + h, h * 0.98), (zc - length * 0.5, cy + h, h * 0.98)],
              dist - depth, dist + depth)
    _rot_new(bm, n0, deg, 0.0, cy)


def _rail(bm, z0, z1, dist, deg, cy=0.0):
    """皮卡汀尼导轨（同 gun_kit.picatinny 截面），底座离轴 dist、朝 deg 方向"""
    n0 = len(bm.verts)
    y = dist
    K.xsec_bm(bm, [(-0.0078, y), (0.0078, y), (0.0078, y + 0.0035), (-0.0078, y + 0.0035)], z0, z1)
    tooth = [(-0.0078, y + 0.0025), (0.0078, y + 0.0025), (0.0106, y + 0.0045), (0.0106, y + 0.0057),
             (0.0095, y + 0.0066), (-0.0095, y + 0.0066), (-0.0106, y + 0.0057), (-0.0106, y + 0.0045)]
    n = int((z1 - z0 - 0.002) / 0.01)
    off = (z1 - z0 - n * 0.01) * 0.5
    for k in range(n):
        za = z0 + off + k * 0.01 + 0.0026
        K.xsec_bm(bm, tooth, za, za + 0.0048)
    _rot_new(bm, n0, deg - 90.0)
    bm.verts.ensure_lookup_table()
    bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, cy)), verts=bm.verts[n0:])


def _lowpoly():
    for o in K.PARTS:
        md = o.modifiers.get("bev")
        if md and md.width <= 0.00065:
            md.segments = 1


# ---------------- 上机匣 ----------------

def upper():
    # 截面：方盒 + 顶部倒角；前端下沿倒角
    sec = [(-UX, UB), (UX, UB), (UX, 0.0200, 0.002), (0.0130, UT), (-0.0130, UT), (-UX, 0.0200, 0.002)]
    up = xsec("upper", sec, 0.0, UF, "cera_fde", bevel=0.0010)
    # 右侧抛壳窗；左侧拉机柄导槽
    cut(up, cutter_box("ejport", (UX, 0.0020, -0.1975), (0.0170, 0.0180, 0.0750), r=0.0025))
    cut(up, cutter_box("ch_slot", (-UX, 0.0120, -0.1950), (0.0060, 0.0060, 0.2300), r=0.0028))
    picatinny("rail_top", UF + 0.0010, -0.0010, UT, zone="cera_fde")
    # 前段（护木段）下沿比机匣段低一级，后端斜接下机匣前下巴
    side("upper_front", [(-0.2980, UB + 0.002), (UF, UB + 0.002), (UF, -0.0310, 0.002), (UF + 0.004, -0.0330),
                         (-0.3080, -0.0330, 0.003), (-0.2980, -0.0260, 0.003)], -UX, UX, "cera_fde", bevel=0.0010)
    g = Group()
    for sx in (-1, 1):
        _rail(g.bm, UF + 0.0020, UF + 0.1100, UX, 0.0 if sx > 0 else 180.0, cy=-0.0010)
    _rail(g.bm, UF + 0.0040, UF + 0.1000, 0.0330, -90.0)
    g.done("side_rails", "cera_fde", bevel=0.0004)
    # 抛壳挡（窗后凸台）
    top("deflector", [(UX - 0.001, -0.1400), (0.0255, -0.1520, 0.002), (0.0255, -0.1590, 0.0015),
                      (UX - 0.001, -0.1610)], -0.0020, 0.0190, "cera_fde", bevel=0.0009)
    # 枪机框（窗内）+ 枪机头
    lathe("carrier", [(-0.020, 0.0001), (-0.020, 0.0150), (BF + 0.012, 0.0150), (BF + 0.011, 0.0118),
                      (BF, 0.0112), (BF, 0.0001)], "park", segs=28)
    g = Group()
    g.box((0.0118, 0.0030, BF + 0.0080), (0.0035, 0.0045, 0.0150))
    g.done("extractor", "park", bevel=0.0003)
    # 拉机柄（左，随枪机往复，静止在前位）：杆 + 球头
    g = Group()
    g.cyl((-UX - 0.0060, 0.0120, -0.2900), 0.0038, 0.0160, axis="x", segs=16)
    g.lathe([(-UX - 0.0110, 0.0001), (-UX - 0.0112, 0.0055), (-UX - 0.0160, 0.0072), (-UX - 0.0230, 0.0070),
             (-UX - 0.0260, 0.0050), (-UX - 0.0264, 0.0001)], cx=0.0130, cy=-0.2900, segs=20, axis="x")
    g.done("charging_handle", "steel", bevel=0.0004)
    # 枪管夹紧螺栓（左头右螺母）+ 前端气体调节钮
    g = Group()
    for z in (-0.3150, -0.3400):
        g.cyl((-UX - 0.0008, -0.0120, z), 0.0042, 0.0018, axis="x", segs=6)
        g.cyl((UX + 0.0006, -0.0120, z), 0.0036, 0.0014, axis="x", segs=16)
    g.done("barrel_bolts", "steel", bevel=0.0003)
    lathe("gas_knob", [(UF + 0.002, 0.0080), (UF - 0.0080, 0.0080), (UF - 0.0090, 0.0068), (UF - 0.0092, 0.0001)],
          "steel", cy=0.0135, segs=8, bevel=0.0005)
    # 后端：铰链座金属板
    xsec("rear_plate", [(-UX, UB), (UX, UB), (UX, UT - 0.001), (-UX, UT - 0.001)], -0.0010, 0.0040, "alu",
         bevel=0.0006)


# ---------------- 下机匣（聚合物）----------------

def lower():
    lw = side("lower", [(0.0040, UB + 0.001), (0.0040, -0.0330, 0.006), (-0.0080, LB, 0.006), (MR + 0.002, LB),
                        (MR + 0.002, UB + 0.001)], -LX, LX, "poly_fde", bevel=0.0018, segs=2)
    mw = side("magwell", [(MR, UB + 0.001), (MR, -0.0790, 0.002), (MF - 0.0020, -0.0815, 0.002), (MF, -0.0520, 0.006),
                          (-0.2950, -0.0290, 0.010), (-0.3000, UB + 0.001)], -MX, MX, "poly_fde", bevel=0.0018,
              segs=2)
    taper_x(mw, MR, -0.3000, 1.0, 0.88)
    mouth = cutter_box("mag_mouth", (0.0, -0.0790, (MR + MF) * 0.5 - 0.0005), (0.0275, 0.0200, 0.0850), r=0.003)
    cut(mw, mouth)
    lip = side("magwell_lip", [(MR + 0.0010, -0.0740), (MF - 0.0012, -0.0765), (MF - 0.0030, -0.0835, 0.002),
                               (MR + 0.0025, -0.0810, 0.002)], -MX - 0.0015, MX + 0.0015, "poly_fde", bevel=0.0012)
    cut(lip, mouth)
    # 一体扳机护圈
    side("trigger_guard", [(-0.0860, LB + 0.001), (-0.0870, -0.0630, 0.008), (-0.0960, -0.0715, 0.010),
                           (-0.1380, -0.0715, 0.010), (MR + 0.001, -0.0620, 0.006), (MR + 0.001, LB + 0.001),
                           (MR + 0.0065, LB + 0.001), (MR + 0.0065, -0.0600, 0.004), (-0.1370, -0.0665, 0.006),
                           (-0.0980, -0.0665, 0.006), (-0.0920, -0.0610, 0.004), (-0.0920, LB + 0.001)],
         -0.0070, 0.0070, "poly_fde", bevel=0.0012)
    side("trigger", [(-0.1080, LB + 0.001), (-0.1170, LB + 0.001), (-0.1188, -0.0520, 0.004), (-0.1150, -0.0605, 0.003),
                     (-0.1118, -0.0630), (-0.1100, -0.0608, 0.002), (-0.1120, -0.0530, 0.004), (-0.1090, -0.0460)],
         -0.0035, 0.0035, "steel", bevel=0.0004)
    # 双侧快慢机
    g = Group()
    for sx in (-1, 1):
        g.cyl((sx * (LX + 0.0010), -0.0300, -0.0640), 0.0060, 0.0020, axis="x", segs=20)
        g.side([(-0.0620, -0.0270, 0.003), (-0.0860, -0.0282, 0.003), (-0.0885, -0.0302, 0.002),
                (-0.0860, -0.0325, 0.003), (-0.0620, -0.0335, 0.003)], sx * (LX + 0.0016), sx * (LX + 0.0036))
    g.done("selector", "steel", bevel=0.0004)
    # 双侧弹匣卡笋 + 左侧空仓挂机柄
    g = Group()
    for sx in (-1, 1):
        g.lathe([(sx * (LX - 0.002), 0.0045), (sx * (LX + 0.0030), 0.0045), (sx * (LX + 0.0036), 0.0038),
                 (sx * (LX + 0.0038), 0.0001)], cx=-0.0430, cy=-0.1440, segs=18, axis="x")
    g.done("mag_release", "steel", bevel=0.0)
    side("bolt_catch", [(-0.1420, -0.0250), (-0.1560, -0.0250), (-0.1575, -0.0310, 0.002), (-0.1545, -0.0365, 0.003),
                        (-0.1430, -0.0360, 0.003)], -MX - 0.0026, -MX + 0.001, "steel", bevel=0.0005)
    # 销
    g = Group()
    for z, y, xs in ((-0.0120, -0.0300, LX), (-0.2850, -0.0270, MX * 0.89)):
        for sx in (-1, 1):
            g.cyl((sx * (xs + 0.0004), y, z), 0.0040, 0.0012, axis="x", segs=16)
    for z, y in ((-0.1130, -0.0360), (-0.0960, -0.0290)):
        for sx in (-1, 1):
            g.cyl((sx * (LX + 0.0002), y, z), 0.0024, 0.0008, axis="x", segs=12)
    g.done("pins", "steel", bevel=0.0003)


def grip():
    def lerp(a, b, t):
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    f0, f1 = (-0.0870, LB + 0.0005), (-0.0520, -0.1300)
    r0, r1 = (-0.0430, LB + 0.0005), (-0.0140, -0.1190)
    pts = []
    n = 10
    for k in range(n + 1):
        t = k / n
        z, y = lerp(r0, r1, t)
        z += 0.0040 * math.sin(math.pi * t) - 0.0030 * math.exp(-((t - 0.12) / 0.07) ** 2)
        pts.append((z, y, 0.006) if k == n else (z, y))
    for k in range(n + 1):
        t = 1.0 - k / n
        z, y = lerp(f0, f1, t)
        z -= 0.0042 * math.exp(-((t - 0.42) / 0.10) ** 2) - 0.0014 * math.sin(math.pi * t)
        pts.append((z, y, 0.005) if k == 0 else (z, y))
    gp = side("grip", pts, -0.0135, 0.0135, "poly_fde", bevel=0.0035, segs=3)
    taper_x(gp, -0.092, -0.010, 0.80, 1.0)
    # 两侧方块防滑纹
    c0 = ((f0[0] + r0[0]) * 0.5, (f0[1] + r0[1]) * 0.5)
    c1 = ((f1[0] + r1[0]) * 0.5, (f1[1] + r1[1]) * 0.5)
    L = math.hypot(c1[0] - c0[0], c1[1] - c0[1])
    ax = ((c1[0] - c0[0]) / L, (c1[1] - c0[1]) / L)
    pp = (-ax[1], ax[0]) if -ax[1] > 0 else (ax[1], -ax[0])
    g = Group()
    d = 0.0014
    for sx in (-1, 1):
        for i in range(10):
            for j in range(-2, 4):
                s = 0.026 + i * 0.0044
                c = j * 0.0042
                zc = c0[0] + ax[0] * s + pp[0] * c
                yc = c0[1] + ax[1] * s + pp[1] * c
                xx = 0.0135 * (0.80 + 0.20 * min(1.0, max(0.0, (zc + 0.092) / 0.082)))
                q = [(zc + ax[0] * d + pp[0] * d, yc + ax[1] * d + pp[1] * d),
                     (zc + ax[0] * d - pp[0] * d, yc + ax[1] * d - pp[1] * d),
                     (zc - ax[0] * d - pp[0] * d, yc - ax[1] * d - pp[1] * d),
                     (zc - ax[0] * d + pp[0] * d, yc - ax[1] * d + pp[1] * d)]
                g.side(q, sx * (xx - 0.0003), sx * (xx + 0.0006))
    g.done("grip_texture", "poly_fde", bevel=0.0)


def stock():
    """右折叠伸缩托（收到最短）：铰链座 + 前固定段 + 后滑动段（托踵背带孔）+ 可调腮托 + 橡胶托底"""
    side("hinge", [(0.0040, UT - 0.002), (0.0200, UT - 0.002, 0.004), (0.0230, 0.0150), (0.0230, -0.0330, 0.004),
                   (0.0040, -0.0380)], -0.0170, 0.0170, "poly_fde", bevel=0.0015)
    g = Group()
    g.cyl((0.0185, -0.0040, 0.0150), 0.0048, 0.0500, axis="y", segs=18)
    g.cyl((-0.0172, 0.0050, 0.0130), 0.0050, 0.0030, axis="x", segs=18)
    g.done("hinge_pin", "steel", bevel=0.0004)
    # 前固定段（窄）
    fs = side("stock_fixed", [(0.0220, 0.0220), (0.1050, 0.0220), (0.1050, -0.0480), (0.0700, -0.0420, 0.010),
                              (0.0220, -0.0320, 0.004)], -0.0140, 0.0140, "poly_fde", bevel=0.0025, segs=2)
    for sx in (-1, 1):
        cut(fs, cutter_box("fixed_recess%d" % sx, (sx * 0.0150, -0.0060, 0.0640), (0.0040, 0.0180, 0.0620), r=0.006))
    # 后滑动段（宽）+ 托踵背带孔
    ss = side("stock_slide", [(0.0950, 0.0225, 0.003), (SB, 0.0230, 0.004), (SB, -0.0920, 0.004),
                              (SB - 0.0300, -0.0920, 0.006), (0.0950, -0.0530, 0.006)], -0.0175, 0.0175, "poly_fde",
              bevel=0.0030, segs=3)
    taper_x(ss, 0.0950, SB, 0.90, 1.0)
    cut(ss, cutter_box("sling_hole", (0.0, -0.0760, SB - 0.0230), (0.06, 0.0080, 0.0220), r=0.0035))
    g = Group()
    for sx in (-1, 1):
        g.side([(0.1150, -0.0050), (SB - 0.0120, -0.0050), (SB - 0.0120, -0.0080), (0.1150, -0.0080)],
               sx * 0.0170, sx * 0.0182)
    g.done("slide_ribs", "poly_fde", bevel=0.0004)
    # 可调腮托（顶）+ 调节钮
    side("cheek", [(0.0600, 0.0200), (SB - 0.0060, 0.0200), (SB - 0.0060, 0.0300, 0.004), (0.0800, 0.0310, 0.006),
                   (0.0600, 0.0270, 0.004)], -0.0150, 0.0150, "poly_fde", bevel=0.0025, segs=2)
    g = Group()
    g.cyl((-0.0175, 0.0120, 0.1400), 0.0045, 0.0030, axis="x", segs=16)
    g.box((0.0, -0.0500, 0.1000), (0.0080, 0.0050, 0.0120))
    g.done("stock_buttons", "steel", bevel=0.0004)
    side("butt_pad", [(SB - 0.0010, 0.0240), (SB + 0.0100, 0.0240, 0.003), (SB + 0.0130, 0.0120, 0.010),
                      (SB + 0.0130, -0.0800, 0.010), (SB + 0.0100, -0.0935, 0.003), (SB - 0.0010, -0.0935)],
         -0.0190, 0.0190, "rubber", bevel=0.0025, segs=3)
    g = Group()
    for k in range(10):
        g.box((0.0, 0.0150 - k * 0.0100, SB + 0.0130), (0.032, 0.0030, 0.0016))
    g.done("butt_ribs", "rubber", bevel=0.0)


def barrel():
    lathe("barrel", [(BF, 0.0130), (UF + 0.004, 0.0130), (UF + 0.002, 0.0110), (MZ + 0.012, 0.0105),
                     (MZ + 0.0115, 0.0092), (MZ - 0.0010, 0.0092), (MZ - 0.0012, 0.0001)], "steel", segs=28)
    # SCAR 消焰器：实心后段 + 空心笼体 6 槽（前环封闭）
    lathe("fh_rear", [(MZ + 0.0060, 0.0001), (MZ + 0.0060, 0.0105), (MZ + 0.0040, 0.0115), (MZ - 0.0120, 0.0115),
                      (MZ - 0.0120, 0.0001)], "steel", segs=32)
    g = Group()
    _lathe_loop(g.bm, [(MZ - 0.0115, 0.0082), (MZ - 0.0115, 0.0115), (MZ - 0.0480, 0.0115), (MZ - 0.0500, 0.0106),
                       (MZ - 0.0500, 0.0088), (MZ - 0.0494, 0.0082)], segs=36)
    fh = g.done("flash_hider", "steel", bevel=0.0004)
    sc = Group()
    for k in range(6):
        _slot(sc.bm, MZ - 0.0300, 0.0260, 0.0042, 0.0098, 90.0 + k * 60.0, depth=0.004)
    cut(fh, K.obj("fh_slots", sc.bm, None, cutter=True))
    cyl("bore", (0.0, 0.0, MZ - 0.0122), 0.0031, 0.0006, "bore", axis="z", segs=16, bevel=0.0)


def sights():
    """SCAR 折叠机瞄（放倒）：前准星在导轨前端，后觇孔在导轨后端"""
    zf = UF + 0.0040
    g = Group()
    g.xsec([(-0.0130, UT + 0.0012), (0.0130, UT + 0.0012), (0.0130, 0.0372, 0.002), (0.0090, 0.0395, 0.002),
            (-0.0090, 0.0395, 0.002), (-0.0130, 0.0372, 0.002)], zf + 0.0280, zf)
    g.cyl((0.0, 0.0390, zf + 0.0045), 0.0030, 0.0220, axis="x", segs=14)
    g.xsec([(-0.0085, 0.0390), (0.0085, 0.0390), (0.0085, 0.0420), (-0.0085, 0.0420)], zf + 0.0420, zf + 0.0050)
    for sx in (-1, 1):
        g.xsec([(sx * 0.0072, 0.0390), (sx * 0.0104, 0.0390), (sx * 0.0104, 0.0438), (sx * 0.0072, 0.0438)],
               zf + 0.0440, zf + 0.0250)
    g.done("front_sight", "alu", bevel=0.0005)
    cyl("front_post", (0.0, 0.0428, zf + 0.0360), 0.0012, 0.0150, "steel", axis="z", segs=10)
    g = Group()
    g.xsec([(-0.0130, UT + 0.0012), (0.0130, UT + 0.0012), (0.0130, 0.0370, 0.002), (0.0090, 0.0392, 0.002),
            (-0.0090, 0.0392, 0.002), (-0.0130, 0.0370, 0.002)], -0.0050, -0.0360)
    g.cyl((0.0, 0.0392, -0.0080), 0.0030, 0.0220, axis="x", segs=14)
    g.xsec([(-0.0092, 0.0390), (0.0092, 0.0390), (0.0092, 0.0420), (-0.0092, 0.0420)], -0.0090, -0.0420)
    g.lathe([(0.0390, 0.0001), (0.0390, 0.0050), (0.0424, 0.0050), (0.0424, 0.0001)], cx=0.0, cy=-0.0370,
            segs=16, axis="y")
    for sx in (-1, 1):
        g.xsec([(sx * 0.0078, 0.0390), (sx * 0.0108, 0.0390), (sx * 0.0108, 0.0436), (sx * 0.0078, 0.0436)],
               -0.0250, -0.0420)
    g.cyl((0.0150, 0.0330, -0.0180), 0.0052, 0.0040, axis="x", segs=20)
    g.done("rear_sight", "alu", bevel=0.0005)


def magazine():
    """20 发 7.62 钢弹匣：后沿直、前沿下段微前弯，两侧冲压筋，底板"""
    d, w = 0.0830, 0.0128
    zr0, yc0 = MR - 0.0050, -0.0400
    ystr = -0.1000
    R, alpha = 0.50, math.radians(10.0)
    zc0 = zr0 - d * 0.5
    ls = yc0 - ystr

    def center(s):
        if s <= ls:
            return (zc0, yc0 - s), (1.0, 0.0)
        phi = (s - ls) / R
        return (zc0 - R * (1 - math.cos(phi)), ystr - R * math.sin(phi)), (math.cos(phi), -math.sin(phi))
    n = 12
    rear, front, mid = [], [], []
    for k in range(n + 1):
        s = ls * k / 3 if k <= 3 else ls + R * alpha * (k - 3) / (n - 3)
        (cz, cy), (nz, ny) = center(s)
        rear.append((cz + nz * d * 0.5, cy + ny * d * 0.5))
        front.append((cz - nz * d * 0.5, cy - ny * d * 0.5))
        mid.append(((cz, cy), (nz, ny)))
    side("magazine", rear + front[::-1], -w, w, "steel", bevel=0.0012, segs=2)
    g = Group()
    for sx in (-1, 1):
        for off in (0.0250, -0.0080):
            strip = [(cz + nz * off, cy + ny * off) for (cz, cy), (nz, ny) in mid[2:-1]]
            poly = [(z + 0.0035, y) for z, y in strip] + [(z - 0.0035, y) for z, y in strip[::-1]]
            g.side(poly, sx * (w - 0.0004), sx * (w + 0.0008))
    g.done("mag_ribs", "steel", bevel=0.0005)
    (cz, cy), (nz, ny) = mid[-1]
    dz, dy = -math.sin(alpha), -math.cos(alpha)

    def P(a, b):
        return (cz + nz * a + dz * b, cy + ny * a + dy * b)
    side("mag_floor", [P(d * 0.5 + 0.0020, -0.0040), P(-d * 0.5 - 0.0040, -0.0040), P(-d * 0.5 - 0.0040, 0.0020),
                       P(-d * 0.5 - 0.0015, 0.0048), P(d * 0.5 + 0.0020, 0.0048)],
         -w - 0.0012, w + 0.0012, "steel", bevel=0.0008)


def build():
    upper()
    lower()
    grip()
    stock()
    barrel()
    sights()
    magazine()
    _lowpoly()
