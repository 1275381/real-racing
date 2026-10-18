"""M7 战斗步枪 = 美军 XM7 / SIG MCX-SPEAR（6.8×51，13 英寸枪管）。

FDE 陶瓷涂层整体式上机匣（通长顶导轨 + 右抛壳窗 / 防尘盖 + 左侧折叠侧拉柄 + 尾部 T 形
拉柄）、M-LOK 护木、FDE 下机匣（喇叭口弹匣井、一体扳机护圈、双侧保险 / 弹匣释放 /
空仓挂机）、FDE 握把、可折叠伸缩托（收到最短档）、黑钢枪管 + SLX 消焰器（消音器快拆座）、
20 发 6.8 聚合物弹匣、折叠机械瞄具。

真实尺寸建模（米）：原点 z=0 = 上机匣后端面，y=0 = 枪膛轴线；全长约 0.818 m
（消焰器前缘 z=-0.613 → 托底胶垫 z=+0.205）。
"""
import math
from bisect import bisect_right

import bmesh

import gun_kit as K
from gun_kit import Group, side, xsec, top, lathe, box, cyl, cut, cutter_box, deform, taper_x

UT = 0.0225          # 上机匣顶（导轨底）
UB = -0.019          # 上下机匣分缝
UX = 0.0165          # 机匣半宽
LB = -0.040          # 下机匣握把处底面
Z_REF = -0.014       # 握把背顶（虎口位，握把尾舌下）

# 握把背顶（虎口位）→ 程序化 M7 grip；整枪缩到程序化长度
META = dict(ref=(0.0, LB, Z_REF), target=(0.0, -0.031, 0.0672), length=1.1100)


# ---------------- 本枪用的小工具（不改共享 gun_kit） ----------------

def _sg(v):
    return 1.0 if v >= 0 else -1.0


def superel(hw, yt, ym, yb, et=3.0, eb=3.0, wt=1.0, wb=1.0, n=28, xc=0.0):
    """圆角截面（逆时针）：上半 ym→yt 指数 et，下半 ym→yb 指数 eb；wt/wb 上/下半收窄"""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        c, s = math.cos(t), math.sin(t)
        if s >= 0:
            e, hh = et, yt - ym
        else:
            e, hh = eb, ym - yb
        x = hw * _sg(c) * abs(c) ** (2.0 / e)
        y = ym + hh * _sg(s) * abs(s) ** (2.0 / e)
        x *= 1 + (wt - 1) * max(s, 0.0) + (wb - 1) * max(-s, 0.0)
        pts.append((xc + x, y))
    return pts


def shell_bm(bm, outer, inner, z0, z1):
    """空心型材：外/内截面（点数相同、同向）沿 z 挤出，两端环面封口"""
    o0 = [bm.verts.new(K.B(x, y, z0)) for x, y in outer]
    o1 = [bm.verts.new(K.B(x, y, z1)) for x, y in outer]
    i0 = [bm.verts.new(K.B(x, y, z0)) for x, y in inner]
    i1 = [bm.verts.new(K.B(x, y, z1)) for x, y in inner]
    n = len(outer)
    for j in range(n):
        j2 = (j + 1) % n
        bm.faces.new((o0[j], o0[j2], o1[j2], o1[j]))
        bm.faces.new((i0[j2], i0[j], i1[j], i1[j2]))
        bm.faces.new((o0[j2], o0[j], i0[j], i0[j2]))
        bm.faces.new((o1[j], o1[j2], i1[j2], i1[j]))


def revolve_bm(bm, prof, cx=0.0, cy=0.0, segs=32):
    """闭环回转体（管、环）：prof 为 (z, r) 闭合环，首尾相连、不封面"""
    rings = []
    for z, r in prof:
        rings.append([bm.verts.new(K.B(cx + r * math.cos(2 * math.pi * j / segs),
                                       cy + r * math.sin(2 * math.pi * j / segs), z)) for j in range(segs)])
    n = len(rings)
    for i in range(n):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for j in range(segs):
            j2 = (j + 1) % segs
            bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))


def sector(r0, r1, a0, a1, n=6, cy=0.0):
    """环扇形截面（x, y）：角度制 a0→a1"""
    out = [(r1 * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
            cy + r1 * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]
    inn = [(r0 * math.cos(math.radians(a1 - (a1 - a0) * k / n)),
            cy + r0 * math.sin(math.radians(a1 - (a1 - a0) * k / n))) for k in range(n + 1)]
    return out + inn


def gear_xy(r, teeth, depth=0.0007, cy=0.0):
    """绕枪管轴的棘齿环截面（x, y）"""
    pts = []
    for k in range(teeth * 2):
        a = math.pi * k / teeth
        rr = r if k % 2 == 0 else r - depth
        pts.append((rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def _side_cutter(pts, x0, x1):
    bm = bmesh.new()
    K.side_bm(bm, pts, x0, x1)
    return bm


def slot_cutters(g, axis_pts, length, width, along="x", span=0.08):
    """M-LOK 长圆孔刀具：axis_pts 为孔中心 (x/y, y/x, z) 列表"""
    for a, b, zc in axis_pts:
        pts = [(zc - length / 2, -width / 2, width / 2), (zc + length / 2, -width / 2, width / 2),
               (zc + length / 2, width / 2, width / 2), (zc - length / 2, width / 2, width / 2)]
        if along == "x":     # 穿 x 方向（侧面孔）：轮廓在 (z, y)
            K.side_bm(g.bm, [(p[0], b + p[1], p[2]) for p in pts], a - span, a + span)
        else:                # 穿 y 方向（底面孔）：轮廓在 (x, z)
            K.top_bm(g.bm, [(a + p[1], p[0], p[2]) for p in pts], b - span, b + span)


# ---------------- 上机匣 ----------------

def upper():
    sec = [(-UX, UB), (UX, UB), (UX, 0.0095, 0.006), (0.0108, UT, 0.002), (-0.0108, UT, 0.002),
           (-UX, 0.0095, 0.006)]
    up = xsec("upper", sec, 0.0, -0.268, "cera_fde", bevel=0.0009)
    # 右抛壳窗（掏到枪机框）、左侧拉柄导槽、右侧机匣减重凹槽
    cut(up, cutter_box("ejport", (0.0125, 0.0012, -0.2015), (0.029, 0.0165, 0.064), r=0.002))
    cut(up, cutter_box("ch_slot", (-UX, 0.0062, -0.170), (0.007, 0.0052, 0.17), r=0.0022))
    g = Group()
    for sx in (-1, 1):
        K.side_bm(g.bm, [(-0.022, 0.0105, 0.0035), (-0.098, 0.0105, 0.0035), (-0.098, 0.0165, 0.0035),
                         (-0.022, 0.0165, 0.0035)], sx * UX - 0.0012, sx * UX + 0.0012)
    cut(up, K.obj("up_flutes", g.bm, None, cutter=True))
    # 枪机框（抛壳窗里露出）+ 枪机头 / 抽壳钩
    g = Group()
    g.lathe([(-0.150, 0.0089), (-0.236, 0.0089)], cy=0.0015, segs=28)
    g.box((0.0072, 0.0085, -0.205), (0.004, 0.004, 0.05))
    g.done("carrier", "steel", bevel=0.0005)
    # 防尘盖（打开，垂在抛壳窗下）+ 铰链杆
    g = Group()
    g.side([(-0.171, -0.0075), (-0.233, -0.0075), (-0.233, -0.0205, 0.002), (-0.171, -0.0205, 0.002)],
           UX + 0.0002, UX + 0.0014)
    g.cyl((UX + 0.0011, -0.0072, -0.202), 0.0013, 0.066, axis="z", segs=10)
    g.done("dust_cover", "alu", bevel=0.0003)
    # 抛壳挡（窗后）
    side("deflector", [(-0.155, 0.003), (-0.169, 0.003), (-0.169, 0.016, 0.002), (-0.160, 0.016, 0.003)],
         UX - 0.001, UX + 0.0055, "cera_fde", bevel=0.0008)
    # 左侧折叠拉柄（静止位在导槽前端）
    g = Group()
    g.side([(-0.2425, 0.0035), (-0.2535, 0.0035), (-0.2535, 0.0089), (-0.2425, 0.0089)], -UX - 0.004, -UX + 0.002)
    g.done("side_ch_base", "alu", bevel=0.0005)
    ch = top("side_ch", [(-UX - 0.003, -0.2430), (-UX - 0.016, -0.2470, 0.003), (-UX - 0.022, -0.2560, 0.004),
                         (-UX - 0.019, -0.2610, 0.002), (-UX - 0.003, -0.2555)], 0.0012, 0.0115, "alu",
             bevel=0.0012, segs=2)
    deform(ch, lambda x, y, z: (x, y + 0.002 * max(0.0, (-UX - x) / 0.02), z))
    # 尾部 T 形拉柄 + 双侧锁扣翼
    g = Group()
    g.side([(0.0015, 0.0095), (0.0015, 0.0175, 0.002), (0.0105, 0.0175, 0.002), (0.0105, 0.0095, 0.002)],
           -0.0065, 0.0065)
    for sx in (-1, 1):
        g.top([(sx * 0.0065, 0.0015), (sx * 0.0175, 0.0035, 0.002), (sx * 0.0185, 0.0095, 0.002),
               (sx * 0.0065, 0.0105)], 0.0105, 0.0165)
    g.done("rear_ch", "alu", bevel=0.0006)
    # 顶导轨（通长：上机匣 + 护木）
    K.picatinny("top_rail", -0.528, 0.002, UT, zone="cera_fde")
    # 护木连接螺钉、左右 QD 背带座
    pts = []
    for sx in (-1, 1):
        pts += [(sx * (UX + 0.0003), -0.008, -0.258), (sx * (UX + 0.0003), 0.004, -0.258)]
    K.screw_heads("up_screws", pts, 0.0022, 0.0012)


# ---------------- 护木 / 枪管 / 消焰器 ----------------

def handguard():
    hw, yt, ym, yb = 0.0222, UT, -0.0015, -0.0275
    outer = superel(hw, yt, ym, yb, et=7.0, eb=3.4, wt=0.72, wb=0.9, n=28)
    inner = superel(hw - 0.0028, yt - 0.003, ym, yb + 0.0028, et=7.0, eb=3.4, wt=0.72, wb=0.9, n=28)
    bm = bmesh.new()
    shell_bm(bm, outer, inner, -0.2665, -0.528)
    hg = K.obj("handguard", bm, "cera_fde", bevel=0.0009)
    # M-LOK 长圆孔：两侧各 6 个 + 底面 5 个；45° 斜面短孔
    g = Group()
    slot_cutters(g, [(0.0, -0.0035, -0.300 - 0.0395 * k) for k in range(6)], 0.0315, 0.0072, along="x", span=0.04)
    slot_cutters(g, [(0.0, yb, -0.320 - 0.0395 * k) for k in range(5)], 0.0315, 0.0072, along="y", span=0.006)
    cut(hg, K.obj("mlok", g.bm, None, cutter=True))
    # 前端加强环（护木口）+ 后端 QD 座
    bm = bmesh.new()
    o2 = superel(hw + 0.0006, yt, ym, yb - 0.0006, et=7.0, eb=3.4, wt=0.72, wb=0.9, n=28)
    shell_bm(bm, o2, inner, -0.520, -0.5285)
    K.obj("hg_lip", bm, "cera_fde", bevel=0.0006)
    g = Group()
    for sx in (-1, 1):
        g.cyl((sx * (hw + 0.0012), -0.0035, -0.278), 0.0055, 0.0034, axis="x", segs=18)
    g.done("hg_qd", "alu", bevel=0.0005)
    # 导气箍 + 活塞（从 M-LOK 孔里看得到）
    g = Group()
    g.lathe([(-0.455, 0.0125), (-0.478, 0.0125)], segs=24)
    g.lathe([(-0.30, 0.0062), (-0.456, 0.0062)], cy=0.0128, segs=16)
    g.box((0.0, 0.0105, -0.4665), (0.012, 0.012, 0.022))
    g.done("gas_block", "alu", bevel=0.0006)


def barrel_group():
    lathe("barrel", [(-0.236, 0.0128), (-0.30, 0.0118), (-0.40, 0.0102), (-0.47, 0.0098), (-0.545, 0.0094)],
          "steel", segs=28)
    # SLX 消焰器：棘齿锁环 + 锥形座 + 六槽前笼 + 前环
    xsec("fh_ratchet", gear_xy(0.0150, 24, 0.0008), -0.5335, -0.5425, "steel", bevel=0.0003)
    lathe("fh_body", [(-0.5425, 0.0141), (-0.5435, 0.0145), (-0.556, 0.0145), (-0.566, 0.0123),
                      (-0.5705, 0.0123), (-0.5705, 0.0001)], "steel", segs=36)
    g = Group()
    for k in range(6):
        a = 90 + 60 * k + 9
        g.xsec(sector(0.0090, 0.0123, a, a + 42, n=5), -0.5703, -0.6047)
    g.done("fh_prongs", "steel", bevel=0.0004)
    bm = bmesh.new()
    revolve_bm(bm, [(-0.6045, 0.0090), (-0.6045, 0.0123), (-0.6125, 0.0123), (-0.6132, 0.0114),
                    (-0.6132, 0.0090)], segs=36)
    K.obj("fh_ring", bm, "steel", bevel=0.0004)
    cyl("bore", (0.0, 0.0, -0.5709), 0.0040, 0.0008, "bore", axis="z", segs=20, bevel=0.0)


# ---------------- 下机匣 / 握把 / 扳机 ----------------

def lower():
    prof = [(-0.002, UB), (-0.2515, UB), (-0.2515, -0.031, 0.004), (-0.2425, -0.040, 0.004),
            (-0.2405, -0.0625, 0.003), (-0.1285, -0.0625, 0.003), (-0.1265, -0.046, 0.003),
            (-0.118, -0.0415, 0.002), (-0.010, LB, 0.003), (-0.002, -0.032, 0.005)]
    lo = side("lower", prof, -UX, UX, "cera_fde", bevel=0.0009)

    def flare(x, y, z):   # 弹匣井下口外扩
        if z < -0.125 and y < -0.05:
            t = (-0.05 - y) / 0.0125
            return (x * (1.0 + 0.11 * t), y, z)
        return (x, y, z)
    deform(lo, flare)
    # 弹匣井两侧凹面（防滑浅槽）
    g = Group()
    for sx in (-1, 1):
        K.side_bm(g.bm, [(-0.150, -0.047, 0.003), (-0.218, -0.047, 0.003), (-0.218, -0.034, 0.003),
                         (-0.150, -0.034, 0.003)], sx * UX - 0.001, sx * UX + 0.001)
    cut(lo, K.obj("mw_flats", g.bm, None, cutter=True))
    # 一体扳机护圈（加大、前端接弹匣井）
    tg = [(-0.040, LB + 0.002), (-0.044, -0.054, 0.004), (-0.054, -0.0605, 0.005), (-0.1265, -0.0605),
          (-0.1265, -0.0555), (-0.058, -0.0555, 0.003), (-0.050, -0.0505, 0.003), (-0.048, LB + 0.002)]
    side("trigger_guard", tg, -0.0058, 0.0058, "cera_fde", bevel=0.0008)
    side("trigger", [(-0.070, LB + 0.001), (-0.0785, LB + 0.001), (-0.0805, -0.048, 0.003),
                     (-0.0765, -0.0545, 0.003), (-0.0725, -0.0552, 0.002), (-0.0745, -0.049, 0.003)],
         -0.0028, 0.0028, "steel", bevel=0.0004)
    # 双侧保险拨杆（左长右短）、弹匣释放钮（右）+ 左侧拨片、空仓挂机（左大拨片 / 右释放杆）
    g = Group()
    g.cyl((0.0, -0.0285, -0.048), 0.0045, 2 * UX + 0.003, axis="x", segs=18)
    g.side([(-0.046, -0.0255), (-0.050, -0.0255), (-0.030, -0.0225, 0.002), (-0.027, -0.0275, 0.002),
            (-0.046, -0.0315)], -UX - 0.0035, -UX - 0.0015)
    g.side([(-0.046, -0.0255), (-0.050, -0.0255), (-0.036, -0.0235, 0.002), (-0.034, -0.0285, 0.002),
            (-0.046, -0.0315)], UX + 0.0015, UX + 0.0035)
    g.cyl((UX + 0.0018, -0.0345, -0.1215), 0.0046, 0.0036, axis="x", segs=18)
    g.side([(-0.116, -0.026), (-0.126, -0.026), (-0.128, -0.0375, 0.002), (-0.118, -0.039, 0.002)],
           -UX - 0.0022, -UX)
    g.side([(-0.131, -0.0215), (-0.146, -0.0215, 0.002), (-0.148, -0.0335, 0.002), (-0.137, -0.0345, 0.002),
            (-0.131, -0.029)], -UX - 0.0024, -UX)
    g.side([(-0.130, -0.0205), (-0.150, -0.0205, 0.0015), (-0.150, -0.0255, 0.0015), (-0.130, -0.0255)],
           UX, UX + 0.0018)
    g.done("controls", "alu", bevel=0.0004)
    # 前后机匣连接销
    pts = []
    for sx in (-1, 1):
        pts += [(sx * (UX + 0.0002), -0.025, -0.0095), (sx * (UX + 0.0002), -0.026, -0.2445),
                (sx * (UX + 0.0002), -0.0325, -0.072), (sx * (UX + 0.0002), -0.0325, -0.090)]
    K.screw_heads("pins", pts, 0.0025, 0.0010, zone="steel")
    # 下机匣尾端 QD 背带座
    cyl("rear_qd", (0.0, -0.030, 0.0005), 0.0052, 0.004, "alu", axis="z", segs=18)


def grip():
    gp = side("grip", [(-0.0205, LB + 0.001), (-0.062, LB + 0.001), (-0.064, -0.050, 0.004),
                       (-0.057, -0.064, 0.012), (-0.0475, -0.088, 0.01), (-0.041, -0.112, 0.015),
                       (-0.029, -0.1375, 0.004), (-0.0035, -0.1395, 0.005), (0.0015, -0.131, 0.005),
                       (-0.009, -0.086, 0.02), (-0.017, -0.056, 0.008), (-0.009, -0.046, 0.006),
                       (-0.006, -0.041, 0.003)],
              -0.0145, 0.0145, "poly_fde", bevel=0.0035, segs=3)
    taper_x(gp, -0.06, -0.01, 0.86, 1.0)
    deform(gp, lambda x, y, z: (x * (1.0 - 0.10 * max(0.0, (-0.06 - y) / 0.08)), y, z))
    # 两侧防滑纹区（浅凸起块）
    g = Group()
    for sx in (-1, 1):
        for k in range(7):
            y0 = -0.060 - 0.0105 * k
            zf = -0.0555 - 0.30 * (y0 + 0.060)
            g.side([(zf + 0.004, y0), (zf + 0.028, y0 - 0.0042), (zf + 0.028, y0 - 0.0072), (zf + 0.004, y0 - 0.003)],
                   sx * 0.0128 - 0.0006, sx * 0.0128 + sx * 0.0008)
    g.done("grip_tex", "poly_fde", bevel=0.0004)


# ---------------- 枪托（折叠伸缩托，收到最短档） ----------------

def stock():
    # 折叠铰链座（上机匣尾）+ 左侧铰链节
    g = Group()
    g.side([(0.0, -0.0205), (0.0, 0.0085), (0.017, 0.0085, 0.003), (0.023, 0.002, 0.003), (0.023, -0.0205, 0.003)],
           -0.0135, 0.0135)
    g.cyl((-0.0138, -0.006, 0.010), 0.0042, 0.026, axis="y", segs=16)
    g.done("hinge", "cera_fde", bevel=0.0008)
    # 伸缩管（露出前段）
    lathe("stock_tube", [(0.020, 0.0128), (0.075, 0.0128)], "alu", cy=-0.0055, segs=24)
    # 托身：上沿平直、下沿斜收；两侧掏空减重槽
    sp = [(0.040, -0.0225, 0.004), (0.040, 0.0115, 0.004), (0.060, 0.0138, 0.01), (0.193, 0.0148, 0.004),
          (0.193, -0.1025, 0.004), (0.172, -0.1035, 0.006), (0.120, -0.062, 0.03), (0.075, -0.0285, 0.012),
          (0.055, -0.0245, 0.004)]
    sb = side("stock_body", sp, -0.0175, 0.0175, "poly_fde", bevel=0.003, segs=3)
    taper_x(sb, 0.04, 0.19, 0.88, 1.06)
    deform(sb, lambda x, y, z: (x * (1.0 - 0.14 * max(0.0, (y - 0.002) / 0.013)), y, z))
    # 托身下部三角镂空（贯通）+ 上沿贴腮条下的浅槽
    cut(sb, K.obj("stock_window", _side_cutter([(0.101, -0.0315, 0.004), (0.1795, -0.0315, 0.006),
                                                (0.1795, -0.0905, 0.006), (0.1655, -0.0905, 0.004)],
                                               -0.03, 0.03), None, cutter=True))
    g = Group()
    for sx in (-1, 1):
        K.side_bm(g.bm, [(0.072, -0.0035, 0.003), (0.182, -0.0035, 0.003), (0.182, 0.0005, 0.003),
                         (0.072, 0.0005, 0.003)], sx * 0.0175 - 0.0012, sx * 0.0175 + 0.0012)
    cut(sb, K.obj("stock_groove", g.bm, None, cutter=True))
    # 托底胶垫
    side("buttpad", [(0.1925, 0.0155), (0.2055, 0.0145, 0.003), (0.2055, -0.1035, 0.004), (0.1925, -0.1045)],
         -0.0192, 0.0192, "rubber", bevel=0.0025, segs=3)
    # 伸缩锁杆（托身下前）+ QD 座
    g = Group()
    g.side([(0.045, -0.0235), (0.078, -0.0285), (0.080, -0.0325, 0.002), (0.050, -0.0285, 0.002)], -0.0045, 0.0045)
    g.done("stock_lever", "alu", bevel=0.0005)
    cyl("stock_qd", (0.0, -0.016, 0.172), 0.0058, 2 * 0.0185, "alu", axis="x", segs=18)


# ---------------- 弹匣 / 折叠瞄具 ----------------

def magazine():
    """20 发 6.8 聚合物弹匣：微弧形、下段横纹、底板"""
    n = 12
    y0, y1 = -0.014, -0.165
    back = [(-0.1415 - 0.012 * (k / n) ** 1.6, y0 + (y1 - y0) * k / n) for k in range(n + 1)]
    front = [(-0.2255 - 0.015 * (k / n) ** 1.6, y0 + (y1 - y0 + 0.003) * k / n) for k in range(n + 1)]
    m = side("magazine", back + front[::-1], -0.0133, 0.0133, "poly", bevel=0.0018, segs=3)
    g = Group()
    for sx in (-1, 1):
        for k in range(5):
            t = (0.128 + 0.0055 * k) / 0.151
            zb = -0.1415 - 0.012 * t ** 1.6
            zf = -0.2255 - 0.015 * t ** 1.6
            yy = y0 + (y1 - y0) * t
            g.side([(zb - 0.006, yy + 0.0012), (zf + 0.006, yy + 0.0012), (zf + 0.006, yy - 0.0012),
                    (zb - 0.006, yy - 0.0012)], sx * 0.0133 - 0.0004, sx * 0.0133 + sx * 0.0007)
        # 侧面竖向加强筋
        pts = [((b[0] + f[0]) * 0.5 + 0.022, b[1]) for b, f in zip(back, front)]
        rib = [(z + 0.0015, y) for z, y in pts[3:10]] + [(z - 0.0015, y) for z, y in pts[3:10][::-1]]
        g.side(rib, sx * 0.0133 - 0.0004, sx * 0.0133 + sx * 0.0006)
    g.done("mag_tex", "poly", bevel=0.0004)
    zb, yb = back[-1]
    zf, yf = front[-1]
    side("mag_floor", [(zb + 0.0025, yb + 0.003), (zf - 0.003, yf + 0.003), (zf - 0.0045, yf - 0.004, 0.003),
                       (zb + 0.0035, yb - 0.0045, 0.003)], -0.0150, 0.0150, "poly", bevel=0.0012, segs=2)
    return m


def sights():
    """折叠机械瞄具（导轨上，收起状态）"""
    g = Group()
    # 照门：夹座 + 放倒的觇孔片 + 护翼
    g.side([(-0.004, UT + 0.0035), (-0.040, UT + 0.0035), (-0.040, UT + 0.0105, 0.002), (-0.004, UT + 0.0105, 0.002)],
           -0.0108, 0.0108)
    g.side([(-0.010, UT + 0.0105), (-0.036, UT + 0.0105), (-0.034, UT + 0.0145, 0.002), (-0.012, UT + 0.0145, 0.002)],
           -0.0075, 0.0075)
    g.cyl((0.0118, UT + 0.007, -0.022), 0.0045, 0.004, axis="x", segs=16)
    # 准星：夹座 + 放倒的准星翼
    g.side([(-0.488, UT + 0.0035), (-0.522, UT + 0.0035), (-0.522, UT + 0.0105, 0.002), (-0.488, UT + 0.0105, 0.002)],
           -0.0108, 0.0108)
    g.side([(-0.492, UT + 0.0105), (-0.520, UT + 0.0105), (-0.518, UT + 0.0148, 0.002), (-0.496, UT + 0.0148, 0.002)],
           -0.0080, 0.0080)
    g.cyl((0.0118, UT + 0.007, -0.505), 0.004, 0.004, axis="x", segs=16)
    g.done("flip_sights", "alu", bevel=0.0006)


def build():
    upper()
    handguard()
    barrel_group()
    lower()
    grip()
    stock()
    magazine()
    sights()
