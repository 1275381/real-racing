"""霰弹枪 = Remington 870 Wingmaster（12 号，18.5 英寸枪管，泵动）。

烤蓝钢机匣（右抛壳窗露出枪机、下装弹口露出托弹板、两颗扳机座销）+ 黑色扳机座 / 护圈
（护圈后上方横推保险、左前方滑套释放杆）、胡桃木半手枪握颈枪托 + 握把帽 + 橡胶后托垫、
胡桃木带纵向沟槽的泵动护木（骑在两根滑轨上）、枪管下弹仓管 + 枪管箍 + 弹仓盖、
枪口铜珠准星。无可拆弹匣。

真实尺寸建模（米）：原点 z=0 = 机匣后端面，y=0 = 枪膛轴线；全长约 0.956 m
（枪口 z=-0.645 → 后托垫 z=+0.311）。
"""
import math
from bisect import bisect_right

import bmesh
from mathutils import Matrix

import gun_kit as K
from gun_kit import Group, side, xsec, lathe, box, cyl, cut, cutter_box, deform

RX = 0.0178          # 机匣半宽
RT = 0.0195          # 机匣顶
RB = -0.044          # 机匣底
TY = -0.0255         # 弹仓管轴线
Z_REF = 0.055        # 握颈顶（虎口位）


# ---------------- 本枪用的小工具（不改共享 gun_kit） ----------------

def pchip(keys):
    """单调三次插值（Fritsch–Carlson）：keys[(t, v)] → f(t)"""
    xs = [k[0] for k in keys]
    ys = [k[1] for k in keys]
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        i = bisect_right(xs, x) - 1
        t = (x - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])
    return f


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


def loft_bm(bm, secs, cap0=True, cap1=True):
    rings = [[bm.verts.new(K.B(x, y, z)) for x, y in pts] for z, pts in secs]
    n = len(rings[0])
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for j in range(n):
            j2 = (j + 1) % n
            bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))
    if cap0:
        bm.faces.new(rings[0][::-1])
    if cap1:
        bm.faces.new(rings[-1])


def loft(name, secs, zone, **kw):
    bm = bmesh.new()
    loft_bm(bm, secs)
    return K.obj(name, bm, zone, **kw)


def zsteps(z0, z1, step):
    n = max(1, int(round(abs(z1 - z0) / step)))
    return [z0 + (z1 - z0) * k / n for k in range(n + 1)]


def rot_z(bm, verts, ang_deg, cx=0.0, cy=0.0):
    """绕枪管方向轴（过 (cx, cy)）旋转：枪身局部 z 轴 = Blender -Y"""
    M = (Matrix.Translation(K.B(cx, cy, 0.0)) @ Matrix.Rotation(math.radians(-ang_deg), 4, "Y")
         @ Matrix.Translation(-K.B(cx, cy, 0.0)))
    bmesh.ops.transform(bm, matrix=M, verts=verts)


def gear_xy(r, teeth, depth=0.0006, cy=0.0):
    pts = []
    for k in range(teeth * 2):
        a = math.pi * k / teeth
        rr = r if k % 2 == 0 else r - depth
        pts.append((rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


# ---------------- 机匣 ----------------

RYT = pchip([(-0.210, RT - 0.0012), (-0.205, RT), (-0.024, RT), (-0.010, 0.0168), (0.0, 0.0105)])


def receiver():
    secs = []
    for z in zsteps(0.0, -0.210, 0.006):
        secs.append((z, superel(RX, RYT(z), -0.006, RB, et=2.4, eb=9.0, wt=1.0, wb=1.0, n=36)))
    rc = loft("receiver", secs, "steel", bevel=0.0009)
    # 右抛壳窗、下装弹口
    cut(rc, cutter_box("ejport", (0.0145, 0.0005, -0.140), (0.016, 0.0215, 0.076), r=0.0035))
    cut(rc, cutter_box("loadport", (0.0, RB, -0.150), (0.0245, 0.016, 0.092), r=0.004))
    # 枪机（抛壳窗内）+ 抽壳钩；托弹板（装弹口内）
    g = Group()
    g.side([(-0.100, -0.0085), (-0.177, -0.0085), (-0.177, 0.0095, 0.002), (-0.100, 0.0095)], 0.0, 0.0105)
    g.box((0.0098, 0.0035, -0.170), (0.003, 0.004, 0.012))
    g.done("bolt", "steel", bevel=0.0006)
    g = Group()
    g.side([(-0.106, RB + 0.0045), (-0.194, RB + 0.0045), (-0.194, RB + 0.0075), (-0.106, RB + 0.0075)],
           -0.0105, 0.0105)
    g.done("carrier", "steel", bevel=0.0005)
    # 扳机座固定销
    pts = []
    for sx in (-1, 1):
        pts += [(sx * (RX + 0.0002), -0.0365, -0.034), (sx * (RX + 0.0002), -0.0365, -0.146)]
    K.screw_heads("rec_pins", pts, 0.0028, 0.0010)


def trigger_group():
    TB = RB - 0.0055
    # 扳机座下沿（露在机匣下）+ 护圈
    g = Group()
    g.side([(-0.001, RB + 0.002), (-0.100, RB + 0.002), (-0.100, TB, 0.002), (-0.001, TB, 0.003)], -0.0115, 0.0115)
    g.done("trigger_plate", "alu", bevel=0.0007)
    tg = [(-0.0035, TB + 0.001), (-0.0015, -0.0775, 0.017), (-0.0975, -0.0775, 0.019), (-0.0995, TB + 0.001),
          (-0.0935, TB + 0.001), (-0.0915, -0.0725, 0.014), (-0.0065, -0.0725, 0.012), (-0.0085, TB + 0.001)]
    side("trigger_guard", tg, -0.0062, 0.0062, "alu", bevel=0.0007)
    side("trigger", [(-0.036, TB), (-0.0465, TB), (-0.049, -0.059, 0.004), (-0.044, -0.0685, 0.003),
                     (-0.0395, -0.0695, 0.002), (-0.0415, -0.061, 0.003), (-0.040, -0.054)],
         -0.003, 0.003, "steel", bevel=0.0004)
    # 横推保险（护圈后上方，左右穿出）
    lathe("safety", [(-0.0145, 0.0001), (-0.0145, 0.0034), (-0.0135, 0.0040), (0.0135, 0.0040), (0.0145, 0.0034),
                     (0.0145, 0.0001)], "steel", cx=-0.0472, cy=-0.016, segs=16, axis="x")
    # 滑套释放杆（左侧、护圈前）
    side("slide_release", [(-0.090, TB + 0.002), (-0.101, TB + 0.002), (-0.104, -0.057, 0.0015),
                           (-0.098, -0.0595, 0.0015), (-0.092, -0.056)], -0.0105, -0.0082, "alu", bevel=0.0004)


# ---------------- 枪托（胡桃木半手枪握颈） ----------------

Z_PAD = 0.287
YT = pchip([(0.0, 0.0100), (0.010, 0.0052), (0.026, -0.0010), (0.055, -0.0060), (0.12, -0.0165),
            (Z_PAD, -0.0455)])
YB = pchip([(0.0, -0.0505), (0.009, -0.0575), (0.024, -0.0750), (0.044, -0.0920), (0.062, -0.1005),
            (0.078, -0.1025), (0.094, -0.1003), (0.110, -0.0962), (0.128, -0.0968), (0.20, -0.1315),
            (Z_PAD, -0.1720)])
YM = pchip([(0.0, -0.016), (0.05, -0.040), (0.10, -0.052), (Z_PAD, -0.104)])
HW = pchip([(0.0, RX), (0.03, 0.0156), (0.06, 0.0149), (0.13, 0.0166), (Z_PAD, 0.0196)])
ET = pchip([(0.0, 2.4), (0.04, 2.3), (Z_PAD, 2.7)])
EB = pchip([(0.0, 6.0), (0.03, 2.4), (0.10, 2.4), (0.14, 2.6), (Z_PAD, 3.2)])
WT = pchip([(0.0, 1.0), (0.04, 0.84), (0.12, 0.72), (Z_PAD, 0.78)])
WB = pchip([(0.0, 0.9), (0.06, 0.82), (Z_PAD, 0.9)])

# 握颈顶（虎口位）→ 程序化霰弹枪 grip；整枪缩到程序化长度
META = dict(ref=(0.0, round(YT(Z_REF), 4), Z_REF), target=(0.0, 0.0024, 0.1206), length=0.9630)


def stock_sec(z):
    return superel(HW(z), YT(z), YM(z), YB(z), ET(z), EB(z), WT(z), WB(z), n=30)


def stock():
    zs = zsteps(0.0, 0.14, 0.005)[:-1] + zsteps(0.14, Z_PAD, 0.012)
    loft("stock", [(z, stock_sec(z)) for z in zs], "wood", bevel=0.0025, segs=3)
    # 握把帽（黑色胶木薄片，贴在握把底）
    zc = 0.072
    cap = []
    for k in range(20):
        a = 2 * math.pi * k / 20
        cap.append((0.0106 * math.cos(a), zc + 0.0135 * math.sin(a)))
    g = Group()
    g.top(cap, YB(zc) - 0.0022, YB(zc) + 0.0012)
    gc = g.done("grip_cap", "bakelite", bevel=0.0008)
    deform(gc, lambda x, y, z: (x, y - 0.12 * (z - zc), z))
    # 后托垫（橡胶，比托尾略大）+ 黑色垫片
    end = superel(HW(Z_PAD) * 1.04, YT(Z_PAD) + 0.0008, YM(Z_PAD), YB(Z_PAD) - 0.0008,
                  ET(Z_PAD), EB(Z_PAD), WT(Z_PAD), WB(Z_PAD), n=30)
    xsec("pad_spacer", [(x * 0.985, y) for x, y in end], Z_PAD - 0.0005, Z_PAD + 0.003, "bakelite", bevel=0.0004)
    pd = xsec("recoil_pad", end, Z_PAD + 0.003, Z_PAD + 0.0245, "rubber", bevel=0.0032, segs=3)
    deform(pd, lambda x, y, z: (x, y, z + 0.002 * max(0.0, z - Z_PAD - 0.01) / 0.0145 *
                                (1.0 - ((y - YM(Z_PAD)) / 0.065) ** 2)))


# ---------------- 枪管 / 弹仓管 / 护木 ----------------

def barrel_group():
    lathe("barrel", [(-0.200, 0.0138), (-0.240, 0.0133), (-0.290, 0.0122), (-0.420, 0.0109), (-0.560, 0.0103),
                     (-0.645, 0.0101), (-0.645, 0.0092), (-0.628, 0.0092), (-0.628, 0.0001)], "steel", segs=36)
    cyl("bore", (0.0, 0.0, -0.6284), 0.0092, 0.0008, "bore", axis="z", segs=28, bevel=0.0)
    # 铜珠准星
    lathe("bead", [(0.0096, 0.0001), (0.0096, 0.0011), (0.0108, 0.0011)] +
          [(0.0122 + 0.0019 * math.sin(math.radians(a)), 0.0019 * math.cos(math.radians(a))) for a in range(-40, 91, 13)],
          "brass", cx=0.0, cy=-0.6365, segs=14, axis="y", bevel=0.0)
    # 弹仓管 + 枪管箍（吊耳 + 环）+ 弹仓盖（滚花）
    lathe("mag_tube", [(-0.205, 0.0110), (-0.548, 0.0110)], "steel", cy=TY, segs=32)
    g = Group()
    g.side([(-0.536, -0.006), (-0.550, -0.006), (-0.550, TY + 0.004), (-0.536, TY + 0.004)], -0.0068, 0.0068)
    g.lathe([(-0.536, 0.0124), (-0.550, 0.0124)], cy=TY, segs=32)
    g.lathe([(-0.538, 0.0108), (-0.548, 0.0108)], cy=0.0, segs=32)
    g.done("barrel_ring", "steel", bevel=0.0006)
    xsec("mag_cap_knurl", gear_xy(0.0128, 30, 0.0006, cy=TY), -0.551, -0.566, "steel", bevel=0.0002)
    lathe("mag_cap", [(-0.5505, 0.0118), (-0.5665, 0.0122), (-0.5765, 0.0112), (-0.5805, 0.0085),
                      (-0.5815, 0.0001)], "steel", cy=TY, segs=32)
    # 滑轨（两根，从护木后端伸进机匣）+ 护木后端钢套环
    g = Group()
    for sx in (-1, 1):
        g.side([(-0.200, TY - 0.003), (-0.240, TY - 0.003), (-0.240, TY + 0.003), (-0.200, TY + 0.003)],
               sx * 0.0112 - 0.0011, sx * 0.0112 + 0.0011)
    g.lathe([(-0.2245, 0.0121), (-0.2305, 0.0121)], cy=TY, segs=32)
    g.done("action_bars", "steel", bevel=0.0003)


def forend():
    """带纵向沟槽的胡桃木泵动护木：包住弹仓管、上沿托到枪管下"""
    z0, z1 = -0.228, -0.418

    def sec(z):
        t = (z0 - z) / (z0 - z1)
        e = min(1.0, t / 0.08, (1.0 - t) / 0.08)       # 两端收圆
        e = math.sin(e * math.pi * 0.5)
        hw = 0.0205 - 0.0008 * t
        return superel(hw * (0.9 + 0.1 * e), -0.0065, TY + 0.001, -0.0505 + 0.004 * (1 - e),
                       et=2.8, eb=2.3, wt=0.86, wb=0.9, n=40)
    zs = zsteps(z0, z0 - 0.016, 0.004)[:-1] + zsteps(z0 - 0.016, z1 + 0.016, 0.012)[:-1] + zsteps(z1 + 0.016, z1, 0.004)
    fe = loft("forend", [(z, sec(z)) for z in zs], "wood", bevel=0.0015, segs=2)
    # 纵向沟槽：每侧 6 道，沿截面法向摆放、按外表面半径定深（一个刀具物体）
    cy = TY + 0.001
    mid = sec((z0 + z1) * 0.5)
    pol = [(math.degrees(math.atan2(y - cy, x)), math.hypot(x, y - cy)) for x, y in mid if x > 0]

    def r_at(a):
        best = min(pol, key=lambda p: abs(p[0] - a))
        return best[1]
    bm = bmesh.new()
    for sx in (-1, 1):
        for k in range(6):
            ang = -6 - 13.5 * k
            r0 = r_at(ang) - 0.0013
            vs_before = set(bm.verts)
            K.side_bm(bm, [(z0 - 0.024, cy - 0.0015, 0.0015), (z1 + 0.024, cy - 0.0015, 0.0015),
                           (z1 + 0.024, cy + 0.0015, 0.0015), (z0 - 0.024, cy + 0.0015, 0.0015)], r0, r0 + 0.01)
            new = [v for v in bm.verts if v not in vs_before]
            rot_z(bm, new, ang, 0.0, cy)
            if sx < 0:
                for v in new:
                    v.co.x = -v.co.x
    cut(fe, K.obj("forend_grooves", bm, None, cutter=True))
    return fe


def build():
    receiver()
    trigger_group()
    stock()
    barrel_group()
    forend()
