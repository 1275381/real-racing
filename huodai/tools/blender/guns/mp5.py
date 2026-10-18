"""H&K MP5A2（9×19，冲压钢机匣 + 上方拉机柄管 + SEF 聚合物扳机座 + A2 固定枪托 + 30 发弧形钢弹匣）。

真实尺寸建模（米）：原点 z=0 = 机匣后端面，y=0 = 枪膛轴线；全长约 0.68 m
（枪口 z=-0.460 → 枪托底板 z=+0.219）。机匣顶线 y≈+0.034，准星/觇孔中心 y=+0.046。
"""
import math

import bmesh

import gun_kit as K
from gun_kit import Group, side, xsec, lathe, box, cyl, cut, cutter_box, cutter_cyl, taper_x, deform, B

# 握把顶后缘（虎口）→ 程序化 MP5 grip；整枪缩到程序化长度
META = dict(ref=(0.0, -0.043, -0.048), target=(0.0, -0.0192, -0.0439), length=0.7496)

RW = 0.0158          # 机匣下半半宽
RB = -0.022          # 机匣下沿
TC = 0.0215          # 拉机柄管轴心高
TR = 0.0125          # 拉机柄管半径
SL = 0.046           # 瞄准线高


# ---------------- 小工具（放本文件，不改 gun_kit） ----------------

def loft_bm(bm, secs, cap=(True, True)):
    """截面放样：secs = [(z, [(x, y)...])...]（各截面点数相同、闭合）"""
    rings = [[bm.verts.new(B(p[0], p[1], z)) for p in pts] for z, pts in secs]
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for j in range(n):
            j2 = (j + 1) % n
            bm.faces.new((a[j], a[j2], b[j2], b[j]))
    if cap[0]:
        bm.faces.new(rings[0][::-1])
    if cap[1]:
        bm.faces.new(rings[-1])


def loft(name, secs, zone, **kw):
    bm = bmesh.new()
    loft_bm(bm, secs)
    return K.obj(name, bm, zone, **kw)


def revolve_bm(bm, prof, c, axis="z", segs=24):
    """闭合轮廓 prof[(轴向偏移 t, 半径)] 绕过 c 的轴回转一周（环 / 圆圈 / 滚花环）"""
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for t, r in prof:
            if axis == "z":
                p = (c[0] + r * ca, c[1] + r * sa, c[2] + t)
            elif axis == "x":
                p = (c[0] + t, c[1] + r * ca, c[2] + r * sa)
            else:
                p = (c[0] + r * ca, c[1] + t, c[2] + r * sa)
            ring.append(bm.verts.new(B(*p)))
        rings.append(ring)
    m = len(prof)
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % segs]
        for j in range(m):
            j2 = (j + 1) % m
            bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))


def pyramid_bm(bm, pts, x0, x1):
    """侧面防滑格：底面四边形 pts[(z, y)] 在 x0，尖顶在 x1（菱形棱锥）"""
    vs = [bm.verts.new(B(x0, y, z)) for z, y in pts]
    cz = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    ap = bm.verts.new(B(x1, cy, cz))
    n = len(vs)
    for i in range(n):
        bm.faces.new((vs[i], vs[(i + 1) % n], ap))
    bm.faces.new(vs[::-1])


def ring_prof(r_in, r_out, h):
    return [(-h, r_in), (-h, r_out), (h, r_out), (h, r_in)]


def rot2(pts, ang, cx=0.0, cy=0.0):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + (p[0] - cx) * ca - (p[1] - cy) * sa, cy + (p[0] - cx) * sa + (p[1] - cy) * ca) for p in pts]


# ---------------- 机匣 ----------------

def rec_sec(bot, rb=0.003, n=4):
    """机匣截面：下半方盒 + 侧面冲压折肩 + 上半圆拱（拉机柄管一路延伸到后端）"""
    pts = []
    for k in range(n + 1):
        a = math.radians(-90 + 90 * k / n)
        pts.append((RW - rb + rb * math.cos(a), bot + rb + rb * math.sin(a)))
    pts += [(RW, 0.0105), (RW - 0.0022, 0.0130)]
    for k in range(17):
        a = math.radians(-12 + 204 * k / 16)
        pts.append((0.0137 * math.cos(a), 0.0205 + 0.0137 * math.sin(a)))
    pts += [(-(RW - 0.0022), 0.0130), (-RW, 0.0105)]
    for k in range(n + 1):
        a = math.radians(180 + 90 * k / n)
        pts.append((-RW + rb + rb * math.cos(a), bot + rb + rb * math.sin(a)))
    return pts


def receiver():
    secs = [(0.0, rec_sec(RB)), (-0.236, rec_sec(RB)), (-0.2445, rec_sec(-0.0195, 0.006)),
            (-0.2510, rec_sec(-0.0105, 0.006)), (-0.2555, rec_sec(-0.001, 0.0045)),
            (-0.2585, rec_sec(0.0045, 0.0028))]
    rec = loft("receiver", secs, "park", bevel=0.0009)
    # 右侧抛壳窗（露出枪机）
    cut(rec, cutter_box("ejport", (RW + 0.002, 0.0012, -0.2045), (0.0124, 0.0166, 0.049), r=0.0022))
    g = Group()
    g.box((0.0098, 0.0012, -0.2045), (0.006, 0.0138, 0.045))       # 枪机侧面
    g.box((0.0126, -0.0035, -0.2235), (0.0016, 0.0035, 0.007))      # 抛壳挺
    g.done("bolt", "steel", bevel=0.0005)
    # 拉机柄管（向前伸到准星座，左侧拉机柄槽）
    tube = lathe("cock_tube", [(-0.232, TR), (-0.4055, TR)], "park", cy=TC, segs=36)
    cut(tube, cutter_box("ch_slot", (-TR, TC, -0.3305), (0.009, 0.0046, 0.131), r=0.0021))
    cut(tube, cutter_box("ch_notch", (-TR, TC + 0.0045, -0.2675), (0.009, 0.0092, 0.0056), r=0.0018))
    # 机匣顶部爪式镜座凸台（两对）
    g = Group()
    for z in (-0.066, -0.186):
        for sx in (-1, 1):
            g.side([(z + 0.006, 0.0265), (z - 0.006, 0.0265), (z - 0.005, 0.0322, 0.001), (z + 0.005, 0.0322, 0.001)],
                   sx * 0.0122 - 0.0022, sx * 0.0122 + 0.0022)
    g.done("claw_bosses", "park", bevel=0.0005)
    # 弹匣井（冲压钢套，下沿前端外翻）
    side("magwell", [(-0.1905, RB + 0.002), (-0.2365, RB + 0.002), (-0.2392, -0.0465, 0.003), (-0.2422, -0.0528, 0.0015),
                     (-0.2365, -0.0546, 0.0015), (-0.1945, -0.0512, 0.002), (-0.1905, -0.0482, 0.002)],
         -0.0136, 0.0136, "park", bevel=0.0008)
    # 点焊/铆点：弹匣井两侧、机匣尾端
    pts = []
    for sx in (-1, 1):
        for z, y in ((-0.198, -0.030), (-0.229, -0.030), (-0.012, -0.012), (-0.248, 0.004)):
            x = sx * (0.0137 if z < -0.19 and z > -0.24 else RW + 0.0002)
            pts.append((x, y, z))
    K.screw_heads("rivets", pts, 0.0021, 0.0012, "park")
    # 护木横销（机匣前下）
    g = Group()
    g.cyl((0.0, -0.0075, -0.2465), 0.0024, 2 * RW + 0.0016, axis="x", segs=14)
    g.cyl((-RW - 0.0012, -0.0075, -0.2465), 0.0034, 0.0012, axis="x", segs=16)
    g.done("hg_pin", "steel", bevel=0.0003)


def cocking_handle():
    """左前拉机柄：槽内滑块 + 向左伸出、略前折的摆杆 + 球头"""
    z0 = -0.3915
    box("ch_slider", (-0.0118, TC, z0), (0.006, 0.0044, 0.009), "steel", bevel=0.0004)
    side("ch_hub", [(z0 + 0.006, TC - 0.0042), (z0 - 0.0055, TC - 0.0042), (z0 - 0.0055, TC + 0.0042),
                    (z0 + 0.006, TC + 0.0042)], -TR - 0.0045, -TR + 0.0005, "steel", bevel=0.0008)
    ang = math.radians(24)
    L = 0.024
    x1 = -TR - 0.004 - L * math.cos(ang)
    z1 = z0 - L * math.sin(ang)
    w = 0.0028
    arm = [(-TR - 0.003, z0 + w), (-TR - 0.003, z0 - w), (x1 - w * math.sin(ang), z1 - w * math.cos(ang) * 0.6),
           (x1 + w * math.sin(ang) * 0.2, z1 + w * math.cos(ang))]
    K.top("ch_arm", arm, TC - 0.0024, TC + 0.0024, "steel", bevel=0.0007)
    lathe("ch_knob", [(TC - 0.0062, 0.0001), (TC - 0.006, 0.0032), (TC - 0.0045, 0.0055), (TC, 0.0062),
                      (TC + 0.0045, 0.0055), (TC + 0.006, 0.0032), (TC + 0.0062, 0.0001)],
          "steel", cx=x1 - 0.0015, cy=z1, segs=20, axis="y")


# ---------------- 准星 / 觇孔照门 ----------------

def sights():
    # 前：准星座（箍枪管 + 管口塞 + 腹板）+ 圆形护圈 + 准星柱
    g = Group()
    g.lathe([(-0.4035, 0.0108), (-0.4045, 0.0121), (-0.4220, 0.0121), (-0.4232, 0.0108)], segs=32)
    g.lathe([(-0.4035, 0.0118), (-0.4045, 0.0132), (-0.4220, 0.0132), (-0.4232, 0.0118)], cy=TC, segs=32)
    g.side([(-0.4048, -0.004), (-0.4218, -0.004), (-0.4218, 0.03), (-0.4048, 0.03)], -0.0082, 0.0082)
    g.side([(-0.4062, 0.031), (-0.4204, 0.031), (-0.4204, 0.0365, 0.002), (-0.4062, 0.0365, 0.002)], -0.0086, 0.0086)
    revolve_bm(g.bm, ring_prof(0.0089, 0.0118, 0.0064), (0.0, SL, -0.4133), "z", 36)
    g.done("front_sight", "park", bevel=0.0006)
    g = Group()
    g.side([(-0.4118, 0.0355), (-0.4148, 0.0355), (-0.4142, 0.0458, 0.0006), (-0.4124, 0.0458, 0.0006)], -0.0009, 0.0009)
    g.done("fs_post", "steel", bevel=0.0002)
    # 前背带环（准星座左侧，水平环）
    g = Group()
    g.box((-0.0095, 0.0005, -0.4133), (0.004, 0.006, 0.010))
    revolve_bm(g.bm, [(-0.0012, 0.0052), (-0.0012, 0.0076), (0.0012, 0.0076), (0.0012, 0.0052)],
               (-0.0165, 0.0005, -0.4133), "y", 24)
    g.done("sling_front", "steel", bevel=0.0003)
    # 后：转鼓觇孔照门（底座 + 两侧夹板 + 转鼓 + 风偏螺钉）
    zc = -0.0335
    g = Group()
    g.side([(-0.0155, 0.029), (-0.0515, 0.029), (-0.0515, 0.0365, 0.002), (-0.0495, 0.0385, 0.002),
            (-0.0175, 0.0385, 0.002), (-0.0155, 0.0365, 0.002)], -0.0118, 0.0118)
    for sx in (-1, 1):
        g.side([(zc + 0.0125, 0.037), (zc - 0.0125, 0.037), (zc - 0.0105, 0.0435, 0.004), (zc - 0.004, 0.0478, 0.003),
                (zc + 0.004, 0.0478, 0.003), (zc + 0.0105, 0.0435, 0.004)], sx * 0.0108 - 0.0012, sx * 0.0108 + 0.0012)
    g.done("rs_base", "park", bevel=0.0006)
    prof = [(-0.0094, 0.0001), (-0.0094, 0.0094), (-0.0090, 0.0104)]
    for k in range(4):        # 转鼓外圈滚花环
        x = -0.0054 + 0.0036 * k
        prof += [(x - 0.0007, 0.0104), (x - 0.0003, 0.0099), (x + 0.0003, 0.0099), (x + 0.0007, 0.0104)]
    prof += [(0.0090, 0.0104), (0.0094, 0.0094), (0.0094, 0.0001)]
    drum = lathe("rs_drum", prof, "steel", cx=SL, cy=zc, segs=28, axis="x", bevel=0.0)
    cut(drum, cutter_cyl("aperture", (0.0, SL, zc), 0.0016, 0.03, axis="z", segs=14))
    g = Group()
    for sx in (-1, 1):
        g.cyl((sx * 0.0126, SL, zc), 0.0026, 0.0012, axis="x", segs=14)
    g.cyl((0.0127, 0.0335, zc - 0.009), 0.0021, 0.003, axis="x", segs=14)   # 风偏调节螺钉
    g.done("rs_screws", "steel", bevel=0.0003)


# ---------------- 枪管 / 护木 ----------------

def barrel():
    lathe("barrel", [(-0.236, 0.0092), (-0.4395, 0.0092), (-0.4398, 0.0097), (-0.4478, 0.0097), (-0.448, 0.0083),
                     (-0.4484, 0.0001)], "steel", segs=32)
    prof = [(-0.4482, 0.0001), (-0.4482, 0.0083)]
    for k in range(6):        # 枪口螺纹
        z = -0.4485 - 0.0018 * k
        prof += [(z, 0.0083), (z - 0.0009, 0.0078)]
    prof += [(-0.4593, 0.0083), (-0.4600, 0.0076), (-0.4601, 0.0001)]
    lathe("muzzle_thread", prof, "steel", segs=28, bevel=0.0)
    cyl("bore", (0.0, 0.0, -0.4600), 0.0046, 0.0006, "bore", axis="z", segs=20, bevel=0.0)
    # 三凸耳（消声器/枪口装置卡口）
    g = Group()
    for k in range(3):
        a = math.radians(90 + 120 * k)
        rect = [(-0.0023, 0.0094), (0.0023, 0.0094), (0.0021, 0.0128), (-0.0021, 0.0128)]
        g.xsec(rot2(rect, a - math.pi / 2), -0.4400, -0.4475)
    g.done("lugs", "steel", bevel=0.0004)


def hg_sec(s=1.0, drop=0.0):
    """细护木截面：上沿卡住拉机柄管两侧（槽下方），下部包住枪管"""
    out = [(0.0122, 0.0166), (0.0152, 0.0128), (0.0170, 0.0060), (0.0177, -0.0020), (0.0170, -0.0100),
           (0.0146, -0.0165), (0.0098, -0.0204), (0.0035, -0.0218)]
    outer = []
    for x, y in out:
        if y < 0.012:
            outer.append((x * s, y * s - drop * (0.012 - y) / 0.034))
        else:
            outer.append((x, y))
    full = outer + [(-x, y) for x, y in outer[::-1]]
    inner = []
    for k in range(13):
        a = math.radians(202 + 136 * k / 12)
        inner.append((0.0128 * math.cos(a), TC + 0.0128 * math.sin(a)))
    return full + inner


def handguard():
    secs = [(-0.2545, hg_sec(0.90)), (-0.2585, hg_sec(0.985)), (-0.264, hg_sec(1.0)), (-0.330, hg_sec(1.0)),
            (-0.372, hg_sec(0.985)), (-0.3775, hg_sec(1.0, 0.001)), (-0.3815, hg_sec(1.10, 0.0035)),
            (-0.3865, hg_sec(1.11, 0.0038)), (-0.3888, hg_sec(1.02, 0.0015))]
    hg = loft("handguard", secs, "poly", bevel=0.0016, segs=3, angle=40)
    # 两侧下部纵向防滑浅槽
    for sx in (-1, 1):
        cut(hg, cutter_box("hg_groove%d" % sx, (sx * 0.0178, -0.0075, -0.320), (0.0026, 0.0032, 0.088), r=0.0015))
    return hg


# ---------------- SEF 扳机座 / 握把 ----------------

def lower():
    side("trig_housing", [(0.0, RB + 0.0008), (-0.1905, RB + 0.0008), (-0.1905, -0.0395, 0.003), (-0.100, -0.0405),
                          (-0.046, -0.0405, 0.004), (-0.022, -0.0385, 0.008), (0.0, -0.0345, 0.004)],
         -0.0152, 0.0152, "poly", bevel=0.0018, segs=3)
    gp = side("grip", [(-0.0985, -0.036), (-0.0985, -0.047, 0.006), (-0.093, -0.068, 0.03), (-0.0785, -0.119, 0.008),
                       (-0.0775, -0.1275, 0.003), (-0.0745, -0.1305, 0.002), (-0.0305, -0.1305, 0.004),
                       (-0.0262, -0.1245, 0.006), (-0.0302, -0.1005, 0.03), (-0.0418, -0.0665, 0.02),
                       (-0.0492, -0.0475, 0.008), (-0.046, -0.036)],
              -0.0148, 0.0148, "poly", bevel=0.0034, segs=3)
    # 握把两侧菱形防滑格（斜置面板）
    a0 = (-0.0722, -0.0565)
    a1 = (-0.0548, -0.1150)
    du = (a1[0] - a0[0], a1[1] - a0[1])
    L = math.hypot(*du)
    u = (du[0] / L, du[1] / L)
    v = (-u[1], u[0])
    g = Group()
    st = 0.0040
    for i in range(int(L / (st * 0.6)) + 1):
        for j in range(-4, 5):
            off = 0.5 * st if i % 2 else 0.0
            cu = i * st * 0.6
            cv = j * st + off
            if abs(cv) > 0.0150 - 0.0020 * (cu / L):
                continue
            c = (a0[0] + u[0] * cu + v[0] * cv, a0[1] + u[1] * cu + v[1] * cv)
            d = 0.0017
            du_ = 0.0021
            dia = [(c[0] + u[0] * du_, c[1] + u[1] * du_), (c[0] + v[0] * d, c[1] + v[1] * d),
                   (c[0] - u[0] * du_, c[1] - u[1] * du_), (c[0] - v[0] * d, c[1] - v[1] * d)]
            hw = 0.0148
            for sx in (-1, 1):
                pyramid_bm(g.bm, dia, sx * (hw - 0.0002), sx * (hw + 0.0008))
    g.done("grip_checker", "poly", bevel=0.0, angle=20)
    # 扳机护圈（与扳机座一体的宽护圈）
    side("trigger_guard", [(-0.1805, -0.039), (-0.1805, -0.060, 0.006), (-0.1715, -0.0728, 0.008),
                           (-0.110, -0.0738, 0.010), (-0.0950, -0.0655, 0.006), (-0.0930, -0.056),
                           (-0.0985, -0.056), (-0.1010, -0.0605, 0.003), (-0.112, -0.0655, 0.005),
                           (-0.1675, -0.0645, 0.005), (-0.1745, -0.058, 0.004), (-0.1745, -0.039)],
         -0.0078, 0.0078, "poly", bevel=0.0016, segs=2)
    side("trigger", [(-0.1265, -0.040), (-0.1345, -0.040), (-0.1375, -0.050, 0.004), (-0.1335, -0.0598, 0.004),
                     (-0.1265, -0.0625), (-0.1290, -0.0575, 0.003), (-0.1305, -0.0500)],
         -0.0032, 0.0032, "steel", bevel=0.0005)
    # 拨片式弹匣扣（护圈前、弹匣后）+ 右侧按钮
    side("mag_paddle", [(-0.1826, -0.0385), (-0.1884, -0.0385), (-0.1910, -0.0500, 0.003), (-0.1946, -0.0612, 0.002),
                        (-0.1950, -0.0640, 0.001), (-0.1890, -0.0644, 0.002), (-0.1852, -0.0515, 0.003)],
         -0.0068, 0.0068, "steel", bevel=0.0006)
    cyl("mag_button", (0.0141, -0.0310, -0.1965), 0.0036, 0.0022, "steel", segs=18)
    # 快慢机（左）：轴座 + 拨杆；右侧轴端指示片
    g = Group()
    g.cyl((-0.0159, -0.0305, -0.0665), 0.0066, 0.0016, axis="x", segs=24)
    lev = [(-0.0665 + 0.0042, -0.0305), (-0.0665 - 0.0042, -0.0305), (-0.0845, -0.0160, 0.002),
           (-0.0872, -0.0112, 0.003), (-0.0800, -0.0100, 0.003), (-0.0765, -0.0150, 0.002)]
    g.side(lev, -0.0178, -0.0160)
    g.done("selector", "steel", bevel=0.0004)
    g = Group()
    g.cyl((0.0157, -0.0305, -0.0665), 0.0045, 0.0012, axis="x", segs=20)
    g.side([(-0.0640, -0.0315), (-0.0690, -0.0315), (-0.0752, -0.0215), (-0.0730, -0.0205)], 0.0154, 0.0168)
    g.done("sel_indicator", "steel", bevel=0.0003)
    # 前后穿销
    g = Group()
    for z, y in ((-0.1855, -0.0295), (0.0075, -0.0290)):
        g.cyl((0.0, y, z), 0.0026, 0.0352 if z > 0 else 0.0322, axis="x", segs=16)
        g.cyl((-0.0172 if z > 0 else -0.0159, y, z), 0.0036, 0.0012, axis="x", segs=18)
    g.done("push_pins", "steel", bevel=0.0003)


# ---------------- A2 固定枪托 ----------------

def rr_sec(hw, top_, bot, rt, rb, n=5, xc=0.0):
    """圆角矩形截面（点数固定，便于放样）"""
    pts = []
    for cx, cy, r, a0 in ((hw - rb, bot + rb, rb, -90), (hw - rt, top_ - rt, rt, 0),
                          (-hw + rt, top_ - rt, rt, 90), (-hw + rb, bot + rb, rb, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((xc + cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def stock():
    """A2 固定枪托：放样（顶线微降、底线下斜到托踵、由前向后加宽）"""
    bots = [(-0.004, -0.0405), (0.006, -0.0408), (0.020, -0.0425), (0.050, -0.0505), (0.090, -0.0625),
            (0.130, -0.0772), (0.165, -0.0910), (0.188, -0.0995), (0.2040, -0.1035)]
    secs = []
    for z, bot in bots:
        t = (z + 0.004) / 0.208
        top_ = 0.0300 - 0.0105 * t
        hw = 0.0172 + 0.0033 * min(1.0, t / 0.8)
        secs.append((z, rr_sec(hw, top_, bot, 0.0055 + 0.002 * t, 0.006 + 0.004 * t)))
    loft("stock", secs, "poly", bevel=0.0032, segs=3, angle=40)
    # 橡胶底板
    side("buttpad", [(0.2025, 0.0218, 0.003), (0.2188, 0.0226, 0.004), (0.2192, -0.1058, 0.004), (0.2025, -0.1058, 0.003)],
         -0.0214, 0.0214, "rubber", bevel=0.0024, segs=3)
    # 后背带环（左侧）
    g = Group()
    g.box((-0.0208, -0.0860, 0.172), (0.003, 0.010, 0.016))
    revolve_bm(g.bm, [(-0.0012, 0.0050), (-0.0012, 0.0072), (0.0012, 0.0072), (0.0012, 0.0050)],
               (-0.0225, -0.0860 - 0.0075, 0.172), "x", 24)
    g.done("sling_rear", "steel", bevel=0.0003)


# ---------------- 30 发弧形钢弹匣 ----------------

def magazine():
    n = 18

    def zb(t):
        return -0.1965 - 0.066 * t ** 1.55

    def zf(t):
        return -0.2315 - 0.073 * t ** 1.5

    def yb(t):
        return -0.020 - 0.184 * t

    def yf(t):
        return -0.020 - 0.168 * t

    back = [(zb(k / n), yb(k / n)) for k in range(n + 1)]
    front = [(zf(k / n), yf(k / n)) for k in range(n + 1)]
    side("magazine", back + front[::-1], -0.0112, 0.0112, "park", bevel=0.0014, segs=2)
    # 两侧冲压加强筋（沿弧线）
    g = Group()
    for sx in (-1, 1):
        rib = []
        for k in range(3, n):
            t = k / n
            rib.append(((zb(t) + zf(t)) * 0.5, (yb(t) + yf(t)) * 0.5))
        poly = [(z + 0.0028, y) for z, y in rib] + [(z - 0.0028, y) for z, y in rib[::-1]]
        g.side(poly, sx * 0.0108, sx * 0.0121)
    g.done("mag_ribs", "park", bevel=0.0004)
    z0, y0 = back[-1]
    z1, y1 = front[-1]
    side("mag_floor", [(z0 + 0.0028, y0 + 0.0035), (z1 - 0.0032, y1 + 0.0035), (z1 - 0.0036, y1 - 0.0028, 0.0018),
                       (z0 + 0.0030, y0 - 0.0032, 0.0018)], -0.0124, 0.0124, "park", bevel=0.0008)


def build():
    receiver()
    cocking_handle()
    sights()
    barrel()
    handguard()
    lower()
    stock()
    magazine()
