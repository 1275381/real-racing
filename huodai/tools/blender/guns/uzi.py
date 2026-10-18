"""IMI Uzi（9×19：冲压钢方机匣 + 横棱顶盖与顶置拉机钮 + 握把内 32 发直弹匣 +
聚合物握把片/护木 + 握把保险 + 金属折叠托（展开））。

真实尺寸建模（米）：原点 z=0 = 机匣后端面，y=0 = 枪膛轴线；全长约 0.65 m
（枪口 z=-0.455 → 托底板 z=+0.195）。顶盖顶 y=+0.030，准星/照门缺口 y≈+0.047。
"""
import math

import bmesh

import gun_kit as K
from gun_kit import Group, side, xsec, lathe, box, cyl, cut, cutter_box, cutter_cyl, taper_x, deform, B

# 握把顶后缘（虎口）→ 程序化 Uzi grip；整枪缩到程序化长度（托展开）
META = dict(ref=(0.0, -0.038, -0.146), target=(0.0, -0.0243, 0.0674), length=0.5620)

RW = 0.0225          # 机匣半宽
RB = -0.0330         # 机匣下沿
RT = 0.0225          # 机匣侧板上沿
CT = 0.0300          # 顶盖顶
SL = 0.0470          # 瞄准线高


# ---------------- 小工具 ----------------

def loft_bm(bm, secs, cap=(True, True)):
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


def rr_sec(hw, top_, bot, rt, rb, n=5, xc=0.0):
    pts = []
    for cx, cy, r, a0 in ((hw - rb, bot + rb, rb, -90), (hw - rt, top_ - rt, rt, 0),
                          (-hw + rt, top_ - rt, rt, 90), (-hw + rb, bot + rb, rb, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((xc + cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def knurl_sec(r0, r1, teeth, cx=0.0, cy=0.0):
    """滚花截面（星形齿）"""
    pts = []
    for k in range(teeth * 2):
        a = math.pi * k / teeth
        r = r1 if k % 2 == 0 else r0
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# ---------------- 机匣 / 顶盖 ----------------

def receiver():
    rec = side("receiver", [(0.0, RT), (-0.3900, RT), (-0.3900, RB, 0.003), (0.0, RB, 0.003)],
               -RW, RW, "park", bevel=0.0016, segs=2)
    # 两侧冲压纵向集尘槽（各两道）
    for sx in (-1, 1):
        for yc in (0.0105, -0.0135):
            cut(rec, cutter_box("groove%d%d" % (sx, int(yc * 1e4)), (sx * RW, yc, -0.198), (0.0040, 0.0072, 0.330),
                                r=0.0033))
    # 右侧抛壳窗（露出枪机）
    cut(rec, cutter_box("ejport", (RW + 0.001, 0.0005, -0.1735), (0.020, 0.0145, 0.040), r=0.0018))
    g = Group()
    g.box((RW - 0.0080, 0.0005, -0.1735), (0.0080, 0.0125, 0.0365))
    g.box((RW - 0.0045, -0.0040, -0.1905), (0.0016, 0.0030, 0.006))
    g.done("bolt", "steel", bevel=0.0004)
    # 后端盖（托铰座）+ 托锁钮
    g = Group()
    g.side([(0.0060, RT - 0.002), (-0.0020, RT - 0.002), (-0.0020, RB + 0.001), (0.0060, RB + 0.001, 0.003)],
           -RW - 0.0008, RW + 0.0008)
    g.side([(0.0160, -0.0120, 0.003), (0.0020, -0.0120), (0.0020, -0.0320), (0.0160, -0.0320, 0.004)],
           -RW - 0.0006, RW + 0.0006)
    g.done("end_cap", "park", bevel=0.0010)
    # 前/后卡销与铆钉
    pts = []
    for sx in (-1, 1):
        x = sx * (RW + 0.0003)
        for z, y in ((-0.0120, -0.0250), (-0.0260, 0.0150), (-0.3740, 0.0150), (-0.3740, -0.0250),
                     (-0.1500, -0.0270), (-0.2650, -0.0270)):
            pts.append((x, y, z))
    K.screw_heads("rivets", pts, 0.0021, 0.0012, "park")


def top_cover():
    """顶盖：浅拱冲压板 + 横向加强棱 + 中央拉机钮槽"""
    pts = [(RW + 0.0006, RT - 0.0015)] + \
        [(RW * 1.02 * math.cos(math.radians(a)), RT + (CT - RT) * math.sin(math.radians(a))) for a in range(5, 176, 10)] + \
        [(-RW - 0.0006, RT - 0.0015)]
    tc = xsec("top_cover", pts, -0.3700, -0.0060, "park", bevel=0.0007)
    cut(tc, cutter_box("ck_slot", (0.0, CT, -0.2175), (0.0062, 0.010, 0.225), r=0.0028))
    g = Group()
    for k in range(13):
        zc = -0.055 - 0.0195 * k
        for sx in (-1, 1):
            rp = []
            for a in range(0, 81, 10):
                aa = a if sx > 0 else 180 - a
                rp.append((RW * 1.0 * math.cos(math.radians(aa)), RT + (CT - RT + 0.0012) * math.sin(math.radians(aa))))
            # 只保留槽外侧部分
            rp = [p for p in rp if abs(p[0]) > 0.0045]
            inner = [(x * 0.94, RT + (y - RT) * 0.82) for x, y in rp[::-1]]
            g.xsec(rp + inner, zc - 0.0032, zc + 0.0032)
    g.done("cover_ribs", "park", bevel=0.0004)
    # 顶盖后端锁扣
    box("cover_latch", (0.0, CT - 0.0012, -0.0040), (0.022, 0.0046, 0.0080), "steel", bevel=0.0008)


def cocking_knob():
    """顶置拉机钮（前位），中间开槽让出瞄准线"""
    zc = -0.3230
    g = Group()
    g.box((0.0, CT - 0.0010, zc), (0.0058, 0.0040, 0.0120))
    g.lathe([(CT + 0.0010, 0.0001), (CT + 0.0010, 0.0072), (CT + 0.0020, 0.0078)] +
            sum([[(CT + 0.0030 + 0.0016 * k, 0.0078), (CT + 0.0036 + 0.0016 * k, 0.0074),
                  (CT + 0.0040 + 0.0016 * k, 0.0078)] for k in range(4)], []) +
            [(CT + 0.0100, 0.0077), (CT + 0.0108, 0.0066), (CT + 0.0110, 0.0001)], cx=0.0, cy=zc, segs=28, axis="y")
    kn = g.done("cocking_knob", "steel", bevel=0.0003)
    cut(kn, cutter_box("knob_slot", (0.0, CT + 0.0095, zc), (0.0040, 0.0060, 0.030), r=0.0012))


# ---------------- 瞄具 ----------------

def sights():
    # 准星：底座 + 两侧护翼 + 准星柱
    zf = -0.3775
    g = Group()
    g.side([(zf + 0.0090, RT - 0.0010), (zf - 0.0090, RT - 0.0010), (zf - 0.0090, CT + 0.0060, 0.002),
            (zf + 0.0090, CT + 0.0060, 0.002)], -0.0150, 0.0150)
    for sx in (-1, 1):
        g.side([(zf + 0.0070, CT + 0.0040), (zf - 0.0070, CT + 0.0040), (zf - 0.0062, SL + 0.0080, 0.0035),
                (zf + 0.0062, SL + 0.0080, 0.0035)], sx * 0.0122 - 0.0016, sx * 0.0122 + 0.0016)
    g.side([(zf + 0.0045, CT + 0.0050), (zf - 0.0045, CT + 0.0050), (zf - 0.0045, CT + 0.0110, 0.0015),
            (zf + 0.0045, CT + 0.0110, 0.0015)], -0.0045, 0.0045)
    g.done("fs_body", "steel", bevel=0.0005)
    g = Group()
    g.cyl((0.0, CT + 0.0110 + 0.0030, zf), 0.0018, 0.006, axis="y", segs=12)
    g.side([(zf + 0.0010, CT + 0.0120), (zf - 0.0010, CT + 0.0120), (zf - 0.0006, SL, 0.0003),
            (zf + 0.0006, SL, 0.0003)], -0.0008, 0.0008)
    g.done("fs_post", "steel", bevel=0.0002)
    # 照门：L 形翻转觇孔 + 两侧护耳
    zr = -0.0330
    g = Group()
    g.side([(zr + 0.0110, CT - 0.0015), (zr - 0.0110, CT - 0.0015), (zr - 0.0110, CT + 0.0050, 0.002),
            (zr + 0.0110, CT + 0.0050, 0.002)], -0.0150, 0.0150)
    for sx in (-1, 1):
        g.side([(zr + 0.0080, CT + 0.0040), (zr - 0.0080, CT + 0.0040), (zr - 0.0060, SL + 0.0050, 0.003),
                (zr + 0.0060, SL + 0.0050, 0.003)], sx * 0.0122 - 0.0016, sx * 0.0122 + 0.0016)
    g.done("rs_body", "steel", bevel=0.0005)
    leaf = xsec("rs_leaf", rr_sec(0.0062, SL + 0.0042, CT + 0.0040, 0.0025, 0.001, 3), zr + 0.0012, zr - 0.0012,
                "steel", bevel=0.0003)
    cut(leaf, cutter_cyl("peep", (0.0, SL, zr), 0.0014, 0.01, axis="z", segs=14))
    g = Group()
    g.side([(zr + 0.0012, CT + 0.0040), (zr + 0.0060, CT + 0.0040), (zr + 0.0060, CT + 0.0075, 0.001),
            (zr + 0.0012, CT + 0.0075, 0.001)], -0.0055, 0.0055)       # 后倒的第二片觇孔
    g.cyl((0.0, CT + 0.0040, zr), 0.0016, 0.0275, axis="x", segs=12)
    g.done("rs_pins", "steel", bevel=0.0002)


# ---------------- 枪管 / 枪管螺帽 ----------------

def barrel():
    lathe("barrel", [(-0.3880, 0.0102), (-0.4535, 0.0102), (-0.4550, 0.0094), (-0.4551, 0.0001)], "steel", segs=32)
    cyl("bore", (0.0, 0.0, -0.4551), 0.0046, 0.0004, "bore", axis="z", segs=20, bevel=0.0)
    xsec("barrel_nut", knurl_sec(0.0198, 0.0210, 40), -0.3895, -0.4060, "park", bevel=0.0)
    lathe("nut_face", [(-0.4055, 0.0001), (-0.4055, 0.0192), (-0.4075, 0.0178), (-0.4078, 0.0001)], "park",
          segs=40, bevel=0.0004)
    lathe("nut_rear", [(-0.3880, 0.0001), (-0.3880, 0.0206), (-0.3898, 0.0206), (-0.3900, 0.0001)], "park",
          segs=40, bevel=0.0003)


# ---------------- 握把 / 扳机 / 护木 ----------------

def grip():
    gpts = [(-0.1460, RB + 0.001), (-0.2010, RB + 0.001), (-0.2010, -0.0420, 0.004), (-0.1965, -0.1240, 0.004),
            (-0.1945, -0.1290, 0.002), (-0.1415, -0.1290, 0.002), (-0.1400, -0.1240, 0.004), (-0.1450, -0.0420, 0.004)]
    side("grip_frame", gpts, -0.0150, 0.0150, "park", bevel=0.0018, segs=2)
    # 聚合物握把片（两侧）：外凸 + 横向防滑棱
    for sx in (-1, 1):
        pts = [(-0.1490, -0.0440), (-0.1975, -0.0440, 0.003), (-0.1935, -0.1215, 0.006), (-0.1450, -0.1215, 0.006)]
        side("grip_panel%d" % sx, pts, sx * 0.0142, sx * 0.0176, "poly", bevel=0.0018, segs=3)
    g = Group()
    for k in range(12):
        y = -0.0520 - 0.0058 * k
        zf = -0.1935 + 0.0035 * (k / 11.0)
        zb = -0.1500 + 0.0045 * (k / 11.0)
        for sx in (-1, 1):
            g.side([(zb, y - 0.0013), (zf, y - 0.0013), (zf, y + 0.0013), (zb, y + 0.0013)],
                   sx * 0.0172, sx * 0.0186)
    g.done("panel_ribs", "poly", bevel=0.0005)
    # 握把保险（后背板，上部突出）
    side("grip_safety", [(-0.1450, -0.0390), (-0.1395, -0.0430, 0.002), (-0.1360, -0.0560, 0.004),
                         (-0.1370, -0.0880, 0.004), (-0.1420, -0.0920, 0.002), (-0.1440, -0.0880)],
         -0.0085, 0.0085, "steel", bevel=0.0006)
    # 快慢机（左上滑钮）+ 弹匣扣（左下按钮）
    g = Group()
    g.side([(-0.1580, -0.0410), (-0.1880, -0.0410), (-0.1880, -0.0370), (-0.1580, -0.0370)], -0.0162, -0.0148)
    g.done("sel_track", "park", bevel=0.0003)
    g = Group()
    g.lathe([(-0.0154, 0.0001), (-0.0154, 0.0042), (-0.0200, 0.0042), (-0.0206, 0.0034), (-0.0208, 0.0001)],
            cx=-0.0395, cy=-0.1630, segs=20, axis="x")
    g.cyl((-0.0172, -0.1170, -0.1470), 0.0038, 0.0040, axis="x", segs=18)
    g.done("sel_mag_btn", "steel", bevel=0.0003)
    # 扳机护圈（冲压钢，大圆）+ 扳机
    side("trigger_guard", [(-0.2000, -0.0560), (-0.2080, -0.0700, 0.006), (-0.2200, -0.0765, 0.010),
                           (-0.2560, -0.0745, 0.012), (-0.2680, -0.0560, 0.010), (-0.2700, RB + 0.001),
                           (-0.2640, RB + 0.001), (-0.2630, -0.0545, 0.008), (-0.2530, -0.0700, 0.010),
                           (-0.2210, -0.0715, 0.008), (-0.2115, -0.0665, 0.004), (-0.2010, -0.0520)],
         -0.0060, 0.0060, "park", bevel=0.0008)
    side("trigger", [(-0.2210, RB), (-0.2290, RB), (-0.2320, -0.0450, 0.004), (-0.2280, -0.0560, 0.004),
                     (-0.2210, -0.0590), (-0.2235, -0.0535, 0.003), (-0.2245, -0.0450)],
         -0.0032, 0.0032, "steel", bevel=0.0005)


def handguard():
    """前护木：U 形聚合物件包住机匣前下部，两侧纵向防滑槽"""
    pts = [(RW + 0.0030, -0.0080), (RW + 0.0035, -0.0300, 0.006), (RW - 0.0040, RB - 0.0040, 0.006),
           (-RW + 0.0040, RB - 0.0040, 0.006), (-RW - 0.0035, -0.0300, 0.006), (-RW - 0.0030, -0.0080),
           (-RW + 0.0005, -0.0080), (-RW + 0.0005, RB + 0.0005), (RW - 0.0005, RB + 0.0005), (RW - 0.0005, -0.0080)]
    hg = xsec("handguard", pts, -0.2730, -0.3700, "poly", r=0.0, bevel=0.0018, segs=3)
    for sx in (-1, 1):
        for yc in (-0.0160, -0.0250):
            cut(hg, cutter_box("hg_g%d%d" % (sx, int(-yc * 1e4)), (sx * (RW + 0.0042), yc, -0.3215),
                               (0.0026, 0.0040, 0.0800), r=0.0018))


# ---------------- 折叠金属托（展开） ----------------

def stock():
    g = Group()
    for sx in (-1, 1):
        x0 = sx * 0.0208
        # 扁钢托杆：铰座 → 托底板（略下斜）
        g.side([(0.0080, -0.0150), (0.1880, -0.0220), (0.1880, -0.0330), (0.0080, -0.0260)],
               x0 - 0.0016, x0 + 0.0016)
        # 中段折叠铰
        g.cyl((x0, -0.0235, 0.0960), 0.0058, 0.0050, axis="x", segs=18)
    g.cyl((0.0, -0.0205, 0.0100), 0.0040, 0.0480, axis="x", segs=18)      # 后铰轴
    g.done("stock_struts", "park", bevel=0.0005)
    # 托底板：弯曲钢板（侧视弧形）+ 上下卷边
    n = 12
    back = []
    front = []
    for k in range(n + 1):
        t = k / n
        y = 0.0080 - 0.1000 * t
        bulge = 0.0055 * math.sin(math.pi * t)
        back.append((0.1960 - bulge, y))
        front.append((0.1880 - bulge, y))
    side("buttplate", back + front[::-1], -0.0235, 0.0235, "park", bevel=0.0022, segs=3)
    g = Group()
    for sx in (-1, 1):   # 托杆与底板的焊接耳
        g.side([(0.1760, -0.0140), (0.1920, -0.0140), (0.1920, -0.0380), (0.1760, -0.0380, 0.004)],
               sx * 0.0208 - 0.0026, sx * 0.0208 + 0.0026)
    g.done("butt_lugs", "park", bevel=0.0006)
    # 后背带环（左侧铰座）
    g = Group()
    revolve_bm(g.bm, [(-0.0011, 0.0045), (-0.0011, 0.0066), (0.0011, 0.0066), (0.0011, 0.0045)],
               (-RW - 0.0030, -0.0300, 0.0080), "x", 20)
    g.done("sling_rear", "steel", bevel=0.0003)


def sling_front():
    g = Group()
    g.box((-RW - 0.0012, 0.0060, -0.3600), (0.0030, 0.0080, 0.0120))
    revolve_bm(g.bm, [(-0.0011, 0.0045), (-0.0011, 0.0066), (0.0011, 0.0066), (0.0011, 0.0045)],
               (-RW - 0.0060, 0.0060, -0.3600), "y", 20)
    g.done("sling_front", "steel", bevel=0.0003)


# ---------------- 32 发直弹匣（握把内，下方突出） ----------------

MAG_RAKE = 0.045


def mag_z(y, base):
    return base + (y + 0.13) * (-MAG_RAKE)


def magazine():
    yt, yb = -0.1240, -0.2480
    pts = [(mag_z(yt, -0.1535), yt), (mag_z(yt, -0.1875), yt), (mag_z(yb, -0.1875), yb, 0.002),
           (mag_z(yb, -0.1535), yb, 0.002)]
    side("magazine", pts, -0.0118, 0.0118, "park", bevel=0.0012, segs=2)
    g = Group()
    for sx in (-1, 1):   # 两侧纵向冲压筋 + 余弹观察孔边框
        g.side([(mag_z(-0.136, -0.1690), -0.136), (mag_z(-0.136, -0.1720), -0.136),
                (mag_z(-0.238, -0.1720), -0.238), (mag_z(-0.238, -0.1690), -0.238)], sx * 0.0114, sx * 0.0126)
    g.done("mag_ribs", "park", bevel=0.0004)
    side("mag_floor", [(mag_z(-0.2455, -0.1515), -0.2455), (mag_z(-0.2455, -0.1905), -0.2455),
                       (mag_z(-0.2525, -0.1910), -0.2525, 0.002), (mag_z(-0.2525, -0.1510), -0.2525, 0.002)],
         -0.0132, 0.0132, "park", bevel=0.0008)


def build():
    receiver()
    top_cover()
    cocking_knob()
    sights()
    barrel()
    grip()
    handguard()
    stock()
    sling_front()
    magazine()
