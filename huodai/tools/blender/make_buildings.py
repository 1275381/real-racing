"""烽火地带 · 建筑重建模（美术写实化第四轮）：坝底三座厂房 + 游客中心 + 军营宿舍楼 +
两座营区板房 + 变电站控制楼 + 水泥厂主楼与宿舍。

  /Applications/Blender.app/Contents/MacOS/Blender -b --python make_buildings.py -- <输出目录> [预览目录]

每栋楼的占地、墙线、门洞、层高严格对齐 hd_dam_base.gd / hd_dam_zones.gd 里
原方块版（碰撞 _obstacle 不动，游戏端只替换可见层），坐标全部写游戏坐标。
输出 <name>.glb（只有几何 + 材质名，贴图由 Godot 端 hd_pbr.apply_named 按名字套）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bldg_kit as K  # noqa: E402
from bldg_kit import (box, wall, window, door_frame, door_leaf, roller_shutter, canopy,  # noqa: E402
                      wall_lamp, ac_unit, roof_vent, downpipe, gable_roof_x, gable_roof_z,
                      flat_roof, panel_joints, railing, ladder, cyl, quad_slab, prism_tri,
                      pbr, plain, GLASS)

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGV[0]) if ARGV else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "pbr", "models", "buildings")
PREV = os.path.abspath(ARGV[1]) if len(ARGV) > 1 else ""
os.makedirs(OUT, exist_ok=True)
WT = 0.5

# ---------------- 共用材质 ----------------
CONC = pbr("concrete", (0.6, 0.6, 0.58), 3.0)
CONC_D = pbr("concrete", (0.44, 0.43, 0.41), 2.5)
STEEL = pbr("paint_rust", (0.3, 0.31, 0.32), 2.0)
STEEL_L = pbr("paint_rust", (0.72, 0.72, 0.7), 2.0)
RED = pbr("paint_rust", (0.56, 0.16, 0.12), 2.0)
GRATE = pbr("steel_plate", (1.0, 1.0, 1.0), 1.2)
FRAME_D = plain((0.12, 0.12, 0.13), 0.5, 0.5)
FRAME_W = plain((0.86, 0.86, 0.84), 0.45, 0.2)
ROOF_GREY = pbr("corrugated", (0.62, 0.63, 0.62), 2.5)
DARK = plain((0.08, 0.08, 0.085), 0.8, 0.0)
FLOOR = pbr("concrete", (0.66, 0.65, 0.62), 3.0)


def done(name, cam_from, look_at):
    ob = K.finish(name, os.path.join(OUT, name + ".glb"))
    if PREV:
        K.preview(ob, os.path.join(PREV, name + ".png"), cam_from, look_at)


# =====================================================================
#  坝底厂房 甲（装配车间）：x[15,41]×z[-102,-88]，墙高 9，南门 x[26,30] 净高 7.8
# =====================================================================
def fac_a():
    x0, x1, z0, z1, h = 15.0, 41.0, -102.0, -88.0, 9.0
    K.begin(28.0, -95.0)
    clad = pbr("corrugated", (0.44, 0.46, 0.35), 2.5)
    dh = 7.8
    s_open = [(26.0, 30.0, 0.0, dh)]
    s_win = [(18.25, 2.0), (24.0, 2.0), (32.0, 2.0), (37.75, 2.0)]
    for c, w in s_win:
        s_open.append((c - w / 2, c + w / 2, 1.5, 2.8))
    hi_s = [18.25, 37.75]
    hi_n = [18.25, 24.75, 31.25, 37.75]
    for c in hi_s:
        s_open.append((c - 2.0, c + 2.0, 6.2, 7.4))
    n_open = [(c - 2.0, c + 2.0, 6.2, 7.4) for c in hi_n] + \
        [(c - 1.0, c + 1.0, 1.5, 2.8) for c in (24.0, 32.0)]
    side_hi = [(-99.5, -96.5, 6.2, 7.4), (-93.5, -90.5, 6.2, 7.4)]
    e_open = [(-98.0, -96.0, 1.5, 2.8)] + side_hi
    w_open = list(side_hi)
    for y0, y1, m in ((0.0, 1.2, CONC_D), (1.2, h, clad)):
        wall("x", z1 - WT / 2, x0, x1, y0, y1, WT, s_open, m)
        wall("x", z0 + WT / 2, x0, x1, y0, y1, WT, n_open, m)
        wall("z", x1 - WT / 2, z0 + WT, z1 - WT, y0, y1, WT, e_open, m)
        wall("z", x0 + WT / 2, z0 + WT, z1 - WT, y0, y1, WT, w_open, m)
    for c, w in s_win:
        window("x", z1 - WT / 2, 1, c, w, 1.5, 1.3, WT, FRAME_D, 1, 0, CONC)
    for c in (24.0, 32.0):
        window("x", z0 + WT / 2, -1, c, 2.0, 1.5, 1.3, WT, FRAME_D, 1, 0, CONC)
    for c in hi_s:
        window("x", z1 - WT / 2, 1, c, 4.0, 6.2, 1.2, WT, FRAME_D, 3)
    for c in hi_n:
        window("x", z0 + WT / 2, -1, c, 4.0, 6.2, 1.2, WT, FRAME_D, 3)
    window("z", x1 - WT / 2, 1, -97.0, 2.0, 1.5, 1.3, WT, FRAME_D, 1, 0, CONC)
    for c in (-98.0, -92.0):
        window("z", x1 - WT / 2, 1, c, 3.0, 6.2, 1.2, WT, FRAME_D, 2)
        window("z", x0 + WT / 2, -1, c, 3.0, 6.2, 1.2, WT, FRAME_D, 2)
    # 门架钢柱（外露结构，6.5m 一跨）
    for x in (15.0, 21.5, 34.5, 41.0):
        box(x, h / 2, z1 + 0.12, 0.36, h, 0.24, STEEL)
    for x in (15.0, 21.5, 28.0, 34.5, 41.0):
        box(x, h / 2, z0 - 0.12, 0.36, h, 0.24, STEEL)
    for z in (z0, (z0 + z1) / 2, z1):
        box(x0 - 0.12, h / 2, z, 0.24, h, 0.36, STEEL)
        box(x1 + 0.12, h / 2, z, 0.24, h, 0.36, STEEL)
    yr = gable_roof_x(x0, x1, z0, z1, h, 9.0, 0.5, 0.35, ROOF_GREY, STEEL_L, clad,
                      gutter=STEEL_L)
    # 采光带（每坡 3 段浅色透光板）+ 屋脊通风器
    import math
    t = math.tan(math.radians(9.0))
    for xa, xb in ((18.0, 22.0), (26.0, 30.0), (34.0, 38.0)):
        for za, zb in ((z0 + 1.5, -96.0), (-94.0, z1 - 1.5)):
            ya = h + (min(za - z0, z1 - za)) * t + 0.03
            yb = h + (min(zb - z0, z1 - zb)) * t + 0.03
            quad_slab((xa, ya, za), (xb, ya, za), (xb, yb, zb), (xa, yb, zb), 0.03,
                      plain((0.78, 0.82, 0.84), 0.25, 0.0))
    for x in (19.0, 28.0, 37.0):
        roof_vent(x, yr, -95.0, STEEL_L)
    roller_shutter("x", z1 - WT / 2, 1, 26.0, 30.0, dh, WT, STEEL_L, STEEL, STEEL)
    canopy("x", z1, 1, 25.2, 30.8, dh + 0.45, 1.6, STEEL_L, STEEL)
    for a in (25.0, 31.0):
        wall_lamp("x", z1 - WT / 2, 1, a, 6.6, WT)
    # 北墙人行门（实墙上的钢门）+ 门灯
    door_frame("x", z0 + WT / 2, -1, 19.5, 20.5, 2.2, WT, FRAME_D)
    door_leaf("x", z0 + WT / 2, -1, 19.5, 20.5, 2.2, STEEL)
    wall_lamp("x", z0 + WT / 2, -1, 20.0, 2.8, WT)
    for x in (x0 + 0.35, x1 - 0.35):
        for z in (z0 - 0.62, z1 + 0.62):
            downpipe(x, z, h - 0.2, STEEL_L)
    # 室内：环氧地坪 + 行车轨道梁 + 行车大梁
    box(28.0, 0.025, -95.0, x1 - x0 - 1.0, 0.05, z1 - z0 - 1.0, FLOOR)
    for z in (z0 + 0.7, z1 - 0.7):
        box(28.0, 7.0, z, x1 - x0 - 1.2, 0.35, 0.3, STEEL)
    box(32.0, 7.35, -95.0, 0.5, 0.5, z1 - z0 - 1.2, RED)
    box(32.0, 6.9, -95.0, 0.8, 0.4, 0.8, STEEL)
    done("fac_a", (8.0, 5.0, -72.0), (28.0, 5.0, -95.0))


# =====================================================================
#  坝底厂房 乙（机修间）：x[53,71]×z[-100,-88]，墙高 6，南门 x[58,62] 净高 4.8
# =====================================================================
def fac_b():
    x0, x1, z0, z1, h = 53.0, 71.0, -100.0, -88.0, 6.0
    K.begin(62.0, -94.0)
    brick = pbr("brick", (0.62, 0.44, 0.35), 2.2)
    clad = pbr("corrugated", (0.8, 0.76, 0.64), 2.5)
    dh = 4.8
    s_win = [55.5, 65.0, 68.5]
    n_win = [56.0, 60.0, 64.0, 68.0]
    s_open = [(58.0, 62.0, 0.0, dh)] + [(c - 0.7, c + 0.7, 1.0, 2.3) for c in s_win]
    n_open = [(c - 0.7, c + 0.7, 1.0, 2.3) for c in n_win]
    w_open = [(-95.7, -94.3, 1.0, 2.3)]
    e_open = [(-97.0, -96.0, 0.0, 2.1)]
    for y0, y1, m in ((0.0, 0.4, CONC_D), (0.4, 2.6, brick), (2.6, h, clad)):
        wall("x", z1 - WT / 2, x0, x1, y0, y1, WT, s_open, m)
        wall("x", z0 + WT / 2, x0, x1, y0, y1, WT, n_open, m)
        wall("z", x0 + WT / 2, z0 + WT, z1 - WT, y0, y1, WT, w_open, m)
        wall("z", x1 - WT / 2, z0 + WT, z1 - WT, y0, y1, WT, e_open, m)
    # 砖墙与彩钢交界的混凝土腰线
    for args in (("x", z1 - WT / 2, 1, x0, x1), ("x", z0 + WT / 2, -1, x0, x1)):
        box((x0 + x1) / 2, 2.62, args[1] + args[2] * 0.06, x1 - x0, 0.12, WT + 0.12, CONC)
    for xx in (x0 + WT / 2, x1 - WT / 2):
        box(xx, 2.62, (z0 + z1) / 2, WT + 0.12, 0.12, z1 - z0, CONC)
    for c in s_win:
        window("x", z1 - WT / 2, 1, c, 1.4, 1.0, 1.3, WT, FRAME_W, 1, 1, CONC)
    for c in n_win:
        window("x", z0 + WT / 2, -1, c, 1.4, 1.0, 1.3, WT, FRAME_W, 1, 1, CONC)
    window("z", x0 + WT / 2, -1, -95.0, 1.4, 1.0, 1.3, WT, FRAME_W, 1, 1, CONC)
    door_frame("z", x1 - WT / 2, 1, -97.0, -96.0, 2.1, WT, FRAME_D)
    door_leaf("z", x1 - WT / 2, 1, -97.0, -96.0, 2.1, STEEL)
    for x in (x0, x1):
        for z in (z0, z1):
            box(x, h / 2, z, 0.6, h, 0.6, CONC)       # 转角混凝土柱
    roof = pbr("corrugated", (0.52, 0.3, 0.24), 2.5)
    yr = gable_roof_x(x0, x1, z0, z1, h, 12.0, 0.55, 0.4, roof, STEEL_L, clad, gutter=STEEL_L)
    roller_shutter("x", z1 - WT / 2, 1, 58.0, 62.0, dh, WT, STEEL_L, STEEL, STEEL)
    canopy("x", z1, 1, 57.2, 62.8, dh + 0.4, 1.4, STEEL_L, STEEL)
    for a in (57.0, 63.0):
        wall_lamp("x", z1 - WT / 2, 1, a, 4.4, WT)
    for x in (x0 + 0.4, x1 - 0.4):
        for z in (z0 - 0.66, z1 + 0.66):
            downpipe(x, z, h - 0.25, STEEL_L)
    ac_unit(x1 + 0.5, 1.6, -92.0, False)
    ac_unit(x1 + 0.5, 1.6, -98.5, False)
    cyl(66.0, yr + 1.0, -96.0, 0.22, 3.0, "y", STEEL, 12)     # 锻炉烟囱
    cyl(66.0, yr + 2.55, -96.0, 0.32, 0.12, "y", STEEL, 12)
    roof_vent(57.0, yr - 0.4, -92.5, STEEL_L)
    box(62.0, 0.025, -94.0, x1 - x0 - 1.0, 0.05, z1 - z0 - 1.0, FLOOR)
    done("fac_b", (46.0, 4.0, -76.0), (62.0, 3.0, -94.0))


# =====================================================================
#  坝底 丙 泵站：x[-11,-1]×z[-100,-92]，墙高 5，南门 x[-7.5,-4.5] 净高 3.8
# =====================================================================
def fac_c():
    x0, x1, z0, z1, h = -11.0, -1.0, -100.0, -92.0, 5.0
    K.begin(-6.0, -96.0)
    brick = pbr("brick", (0.56, 0.4, 0.32), 2.2)
    dh = 3.8
    s_open = [(-7.5, -4.5, 0.0, dh)]
    n_open = [(-9.5, -8.3, 3.4, 4.2), (-3.7, -2.5, 3.4, 4.2)]
    for y0, y1, m in ((0.0, 0.5, CONC_D), (0.5, h, brick)):
        wall("x", z1 - WT / 2, x0, x1, y0, y1, WT, s_open, m)
        wall("x", z0 + WT / 2, x0, x1, y0, y1, WT, n_open, m)
        wall("z", x0 + WT / 2, z0 + WT, z1 - WT, y0, y1, WT, [], m)
        wall("z", x1 - WT / 2, z0 + WT, z1 - WT, y0, y1, WT, [], m)
    for c in (-8.9, -3.1):
        window("x", z0 + WT / 2, -1, c, 1.2, 3.4, 0.8, WT, FRAME_D, 1, 0, CONC)
    flat_roof(x0, x1, z0, z1, h, CONC, brick, CONC, 0.6, 0.0)
    door_frame("x", z1 - WT / 2, 1, -7.5, -4.5, dh, WT, FRAME_D)
    box(-6.0, dh + 0.18, z1 + 0.05, 3.4, 0.36, WT + 0.1, CONC)            # 门过梁
    for a, s in ((-8.2, -1), (-3.8, 1)):                                    # 外开双门扇（贴墙敞开）
        box(a + s * 0.0, dh * 0.5, z1 + 0.06, 1.45, dh - 0.1, 0.05, STEEL)
    box(-6.0, dh + 0.62, z1 + 0.04, 1.6, 0.4, 0.03, RED)                   # 标识牌
    for zc in (-97.5, -94.5):                                               # 东西墙百叶通风口
        for xx, s in ((x0 + WT / 2, -1), (x1 - WT / 2, 1)):
            box(xx + s * 0.27, 2.6, zc, 0.04, 1.0, 1.2, FRAME_D)
            for k in range(6):
                box(xx + s * 0.3, 2.2 + 0.15 * k, zc, 0.08, 0.04, 1.1, STEEL_L)
    for zc in (-97.0, -95.0):                                               # 东墙出水管：法兰 + 弯头入地
        cyl(-0.62, 1.0, zc, 0.22, 0.76, "x", STEEL, 16)
        cyl(-0.9, 1.0, zc, 0.3, 0.06, "x", STEEL_L, 16)
        cyl(-0.3, 0.55, zc, 0.22, 1.1, "y", STEEL, 16)
        cyl(-0.3, 0.7, zc, 0.3, 0.06, "y", STEEL_L, 16)
        box(-0.3, 0.05, zc, 0.7, 0.1, 0.7, CONC)
    for x in (-8.5, -3.5):
        roof_vent(x, h + 0.3, -96.0, STEEL_L)
    cyl(-2.0, h + 1.8, -99.3, 0.03, 3.0, "y", STEEL, 6)                    # 天线
    wall_lamp("x", z1 - WT / 2, 1, -8.4, 3.4, WT)
    downpipe(x0 + 0.3, z1 + 0.32, h, STEEL_L)
    box(-6.0, 0.025, -96.0, x1 - x0 - 1.0, 0.05, z1 - z0 - 1.0, FLOOR)
    done("fac_c", (-16.0, 3.5, -82.0), (-6.0, 2.5, -96.0))


# =====================================================================
#  游客中心：主翼 x[76,100]×z[33,42.5] 高 8（门厅 x[76,82] 通高 9.5）
#            + 短翼 x[96,106]×z[42.5,54] 高 8
# =====================================================================
def visitor():
    K.begin(88.0, 43.0)
    plaster = pbr("plaster_paint", (0.86, 0.85, 0.82), 3.0)
    fascia = plain((0.2, 0.21, 0.23), 0.4, 0.6)
    z0, z1, x0, x1, h, h1 = 33.0, 42.5, 76.0, 100.0, 8.0, 4.2

    def curtain(axis, fixed, side, a0, a1, y0, y1, step, transoms=()):
        """玻璃幕墙：通长玻璃 + 竖梃（step 间距）+ 横梃"""
        c = (a0 + a1) * 0.5
        K._box_on(axis, fixed, c, (y0 + y1) * 0.5, 0.0, a1 - a0, y1 - y0, 0.05, GLASS)
        n = int(round((a1 - a0) / step))
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            K._box_on(axis, fixed, a, (y0 + y1) * 0.5, side * 0.08, 0.08, y1 - y0, 0.16, FRAME_W)
        for y in (y0 + 0.05, y1 - 0.05) + tuple(transoms):
            K._box_on(axis, fixed, c, y, side * 0.08, a1 - a0, 0.08, 0.16, FRAME_W)

    # 主翼南北墙：一层幕墙 + 二层抹灰（开横向窗带）
    for zf, s in ((z0 + WT / 2, -1), (z1 - WT / 2, 1)):
        curtain("x", zf, s, x0 + 0.25, x1 - 0.25, 0.0, h1, 1.2, (2.6,))
        band = [(77.0, 99.0, 5.6, 7.2)]
        wall("x", zf, x0, x1, h1, h, WT, band, plaster)
        window("x", zf, s, 88.0, 22.0, 5.6, 1.6, WT, FRAME_W, 8, 0, CONC)
        if s < 0:   # 门厅北面 8~9.5 高侧窗
            curtain("x", zf, s, x0 + 0.25, 82.0, h, 9.5, 1.5)
    curtain("x", z1 - WT / 2, 1, x0 + 0.25, 82.0, h, 9.5, 1.5)
    # 门厅西立面：通高幕墙 + 门洞 z[33.5,35.9] 高 3.5
    curtain("z", x0 + WT / 2, -1, 35.9, z1 - 0.25, 0.0, 9.5, 1.5, (3.5, 6.5))
    curtain("z", x0 + WT / 2, -1, 33.25, 35.9, 3.5, 9.5, 1.2, (6.5,))
    door_frame("z", x0 + WT / 2, -1, 33.5, 35.9, 3.5, WT, FRAME_W)
    # 主翼东墙（短翼以北）
    curtain("z", x1 - WT / 2, 1, z0 + 0.25, z1 - 0.25, 0.0, h1, 1.2, (2.6,))
    wall("z", x1 - WT / 2, z0, z1, h1, h, WT, [(34.0, 41.5, 5.6, 7.2)], plaster)
    window("z", x1 - WT / 2, 1, 37.75, 7.5, 5.6, 1.6, WT, FRAME_W, 2, 0, CONC)
    # 屋面：门厅 9.5 + 主翼 8（铝板封檐 + 女儿墙）+ 北侧深挑檐 + 钢柱
    box(79.0, 9.7, 37.75, 6.6, 0.4, 9.9, plaster)
    box(79.0, 9.7, 37.75, 6.7, 0.18, 10.0, fascia)
    flat_roof(81.7, 100.3, z0 - 0.2, z1 + 0.2, h, plaster, plaster, fascia, 0.5, 0.0)
    box(88.0, h + 0.25, 31.4, 25.6, 0.4, 3.8, plaster)
    box(88.0, h + 0.25, 29.52, 25.7, 0.42, 0.06, fascia)
    for k in range(5):
        cyl(79.4 + 4.4 * k, h * 0.5, 30.4, 0.11, h, "y", FRAME_W, 12)
    for k in range(3):
        ac_unit(85.0 + 4.0 * k, h + 0.3, 38.5, True)
    # 短翼
    sx0, sx1, sz0, sz1 = 96.0, 106.0, 42.5, 54.0
    curtain("z", sx1 - WT / 2, 1, sz0 + 0.3, sz1 - 0.25, 0.0, h1, 1.2, (2.6,))
    wall("z", sx1 - WT / 2, sz0 + 0.3, sz1, h1, h, WT, [(44.0, 52.5, 5.6, 7.2)], plaster)
    window("z", sx1 - WT / 2, 1, 48.25, 8.5, 5.6, 1.6, WT, FRAME_W, 3, 0, CONC)
    curtain("x", sz1 - WT / 2, 1, sx0 + 0.25, sx1 - 0.25, 0.0, h1, 1.2, (2.6,))
    wall("x", sz1 - WT / 2, sx0, sx1, h1, h, WT, [(97.5, 104.5, 5.6, 7.2)], plaster)
    window("x", sz1 - WT / 2, 1, 101.0, 7.0, 5.6, 1.6, WT, FRAME_W, 2, 0, CONC)
    curtain("z", sx0 + WT / 2, -1, sz0 + 0.3, 47.3, 0.0, h1, 1.4, (2.6,))
    curtain("z", sx0 + WT / 2, -1, 49.5, sz1 - 0.25, 0.0, h1, 1.4, (2.6,))
    curtain("z", sx0 + WT / 2, -1, 47.3, 49.5, 3.5, h1, 1.1)
    door_frame("z", sx0 + WT / 2, -1, 47.3, 49.5, 3.5, WT, FRAME_W)
    wall("z", sx0 + WT / 2, sz0 + 0.3, sz1, h1, h, WT, [(44.0, 52.5, 5.6, 7.2)], plaster)
    window("z", sx0 + WT / 2, -1, 48.25, 8.5, 5.6, 1.6, WT, FRAME_W, 3, 0, CONC)
    # 短翼北面（主翼东墙以东 x[100,106]）：原方块版是敞口，补幕墙 + 二层窗带
    curtain("x", sz0 + WT / 2, -1, 100.0, sx1 - 0.25, 0.0, h1, 1.2, (2.6,))
    wall("x", sz0 + WT / 2, 100.0, sx1, h1, h, WT, [(101.0, 105.0, 5.6, 7.2)], plaster)
    window("x", sz0 + WT / 2, -1, 103.0, 4.0, 5.6, 1.6, WT, FRAME_W, 1, 0, CONC)
    flat_roof(sx0 - 0.2, sx1 + 0.2, sz0, sz1 + 0.2, h, plaster, plaster, fascia, 0.5, 0.0)
    # 室内：门厅展墙 + 前台 + 地面
    box(82.0, 1.3, 38.0, 0.3, 2.6, 8.5, plain((0.2, 0.21, 0.24), 0.6, 0.0))
    box(88.0, 0.02, 37.75, x1 - x0 - 0.6, 0.04, z1 - z0 - 0.6, plain((0.7, 0.69, 0.66), 0.25))
    box(101.0, 0.02, 48.4, 9.4, 0.04, 11.0, plain((0.7, 0.69, 0.66), 0.25))
    done("visitor", (64.0, 6.0, 62.0), (90.0, 4.0, 40.0))


# =====================================================================
#  军营宿舍楼：x[-130,-98]×z[-30,-18] 高 6.2，南面一层 3 门、二层外廊
# =====================================================================
def barracks():
    x0, x1, z0, z1, h = -130.0, -98.0, -30.0, -18.0, 6.2
    K.begin(-114.0, -24.0)
    panel = pbr("plaster_paint", (0.42, 0.44, 0.33), 3.0)
    joint = plain((0.18, 0.19, 0.15), 0.8, 0.0)
    doors = [(-130.0, -128.2), (-115.4, -112.9), (-99.8, -98.0)]
    s_win = [-125.0, -119.5, -109.5, -104.0]
    s_open = [(a, b, 0.0, 2.5) for a, b in doors] + [(c - 0.6, c + 0.6, 1.0, 2.2) for c in s_win]
    wall("x", z1 - WT / 2, x0, x1, 0.0, 3.4, WT, s_open, panel)
    n_win1 = [-126.0 + 4.0 * k for k in range(8)]
    n_win2 = [-127.0 + 4.0 * k for k in range(8)]
    n_open = [(c - 0.6, c + 0.6, 1.0, 2.2) for c in n_win1] + \
        [(c - 0.6, c + 0.6, 4.1, 5.5) for c in n_win2]
    wall("x", z0 + WT / 2, x0, x1, 0.0, h, WT, n_open, panel)
    for xx, s in ((x0 + WT / 2, -1), (x1 - WT / 2, 1)):
        wall("z", xx, z0 + WT, z1 - WT, 0.0, h, WT, [(-25.0, -23.0, 1.0, 2.2), (-25.0, -23.0, 4.1, 5.5)],
             panel)
        window("z", xx, s, -24.0, 2.0, 1.0, 1.2, WT, FRAME_W, 1, 0, CONC)
        window("z", xx, s, -24.0, 2.0, 4.1, 1.4, WT, FRAME_W, 1, 0, CONC)
        panel_joints("z", xx, s, z0 + WT, z1 - WT, 0.0, h, 1.2, WT, joint)
    for c in s_win:
        window("x", z1 - WT / 2, 1, c, 1.2, 1.0, 1.2, WT, FRAME_W, 1, 0, CONC)
    for c in n_win1:
        window("x", z0 + WT / 2, -1, c, 1.2, 1.0, 1.2, WT, FRAME_W, 1, 0, CONC)
    for c in n_win2:
        window("x", z0 + WT / 2, -1, c, 1.2, 4.1, 1.4, WT, FRAME_W, 1, 0, CONC)
    panel_joints("x", z0 + WT / 2, -1, x0, x1, 0.0, h, 1.2, WT, joint)
    panel_joints("x", z1 - WT / 2, 1, x0, x1, 0.0, 3.4, 1.2, WT, joint)
    for a, b in doors:
        door_frame("x", z1 - WT / 2, 1, a + 0.1, b - 0.1, 2.5, WT, FRAME_W)
        wall_lamp("x", z1 - WT / 2, 1, (a + b) * 0.5, 2.85, WT)
    # 二层：楼板 + 退进的房间外墙（门窗）+ 外廊栏杆 + 檐柱
    box(-114.0, 3.3, -24.0, 31.2, 0.2, 11.6, CONC)
    box(-114.0, 3.35, z1 - 0.1, 32.0, 0.3, 0.2, CONC)
    d2 = [-126.5, -118.0, -110.0, -101.5]
    w2 = [-123.5, -115.0, -106.5]
    o2 = [(c - 0.45, c + 0.45, 3.4, 5.5) for c in d2] + [(c - 0.6, c + 0.6, 4.3, 5.5) for c in w2]
    wall("x", -20.4, x0 + WT, x1 - WT, 3.4, h, 0.25, o2, panel)
    for c in d2:
        door_frame("x", -20.4, 1, c - 0.45, c + 0.45, 2.1, 0.25, FRAME_W)
        door_leaf("x", -20.4, 1, c - 0.45, c + 0.45, 2.1, plain((0.35, 0.3, 0.22), 0.7))
    for c in w2:
        window("x", -20.4, 1, c, 1.2, 4.3, 1.2, 0.25, FRAME_W, 1, 0)
    railing([(x0 + 0.5, z1 - 0.25), (x1 - 0.5, z1 - 0.25)], 3.45, 1.0, STEEL, STEEL, 1.2)
    for k in range(7):
        box(-129.6 + 5.2 * k, 4.8, z1 - 0.15, 0.2, 2.8, 0.2, STEEL)
    gable_roof_x(x0, x1, z0, z1, h, 10.0, 0.45, 0.35, pbr("corrugated", (0.34, 0.37, 0.3), 2.5),
                 STEEL, panel, gutter=STEEL)
    # 内隔墙 / 楼梯 / 中门坡道 / 东侧门台阶 / 设备
    for px in (-122.5, -107.5):
        box(px, 1.65, -24.0, WT, 3.3, 11.0, panel)
        box(px, 4.8, -25.2, WT, 2.8, 8.6, panel)
    box(-103.0, 1.55, -27.7, 9.0, 3.1, 0.24, panel)
    for k in range(14):
        box(-106.0 + 0.3 * k, 0.11 + 0.22 * k, -28.6, 0.3, 0.22, 1.6, CONC)
    quad_slab((-115.6, 0.02, z1 + 1.85), (-112.7, 0.02, z1 + 1.85), (-112.7, 0.24, z1 + 0.25),
              (-115.6, 0.24, z1 + 0.25), 0.2, CONC)
    for a, b in (doors[0], doors[2]):
        box((a + b) * 0.5, 0.1, z1 + 0.6, b - a + 0.4, 0.2, 1.0, CONC)
    ac_unit(x1 + 0.5, 1.5, -27.0, False)
    ac_unit(x1 + 0.5, 4.6, -27.0, False)
    cyl(-99.5, h + 3.0, -28.5, 0.04, 6.0, "y", STEEL, 6)                   # 通信天线杆
    for x in (x0 + 0.3, x1 - 0.3):
        downpipe(x, z0 - 0.62, h - 0.2, STEEL)
    done("barracks", (-92.0, 5.0, -2.0), (-114.0, 3.0, -24.0))


# =====================================================================
#  营区板房 8×6×3.2（单坡顶，北高南低）：A 门朝西 / B 门朝南
# =====================================================================
def hut(name, cx, cz, door_west):
    K.begin(cx, cz)
    x0, x1, z0, z1, h = cx - 4.0, cx + 4.0, cz - 3.0, cz + 3.0, 3.2
    hn = 3.9
    skin = pbr("container", (0.4, 0.42, 0.3), 2.4)
    win = [(cx + 2.0 - 0.55, cx + 2.0 + 0.55, 1.2, 2.4)]
    wall("x", z1 - WT / 2, x0, x1, 0.0, h, WT, win, skin)
    wall("x", z0 + WT / 2, x0, x1, 0.0, hn, WT, [], skin)
    for xx in (x0 + WT / 2, x1 - WT / 2):
        wall("z", xx, z0 + WT, z1 - WT, 0.0, h, WT, [], skin)
        prism_tri((xx, h, z1 - WT), (xx, h, z0 + WT), (xx, hn, z0 + WT), "x", WT, skin)
    window("x", z1 - WT / 2, 1, cx + 2.0, 1.1, 1.2, 1.2, WT, FRAME_W, 1, 0, CONC)
    if door_west:
        door_frame("z", x0 + WT / 2, -1, cz + 1.2, cz + 2.1, 2.1, WT, FRAME_W)
        door_leaf("z", x0 + WT / 2, -1, cz + 1.2, cz + 2.1, 2.1, STEEL)
        box(x0 - 0.5, 0.1, cz + 1.65, 1.0, 0.2, 1.4, CONC)
        wall_lamp("z", x0 + WT / 2, -1, cz + 1.65, 2.5, WT)
    else:
        door_frame("x", z1 - WT / 2, 1, cx - 0.45, cx + 0.45, 2.1, WT, FRAME_W)
        door_leaf("x", z1 - WT / 2, 1, cx - 0.45, cx + 0.45, 2.1, STEEL)
        box(cx, 0.1, z1 + 0.5, 1.4, 0.2, 1.0, CONC)
        wall_lamp("x", z1 - WT / 2, 1, cx, 2.5, WT)
    quad_slab((x0 - 0.3, h - 0.05, z1 + 0.3), (x1 + 0.3, h - 0.05, z1 + 0.3),
              (x1 + 0.3, hn + 0.12, z0 - 0.3), (x0 - 0.3, hn + 0.12, z0 - 0.3), 0.12,
              pbr("corrugated", (0.3, 0.32, 0.28), 2.0))
    for x in (x0, x1):                                     # 角柱（集装箱式板房角件）
        for z in (z0, z1):
            box(x, (h if z == z1 else hn) * 0.5, z, 0.22, h if z == z1 else hn, 0.22, STEEL)
    for k in range(3):                                     # 地脚混凝土墩
        box(x0 + 1.0 + 3.0 * k, 0.08, cz, 0.6, 0.16, z1 - z0 + 0.2, CONC)
    ac_unit(cx - 2.0, 1.4, z1 + 0.5, True)
    done(name, (cx + 9.0, 3.0, cz + 10.0), (cx, 1.8, cz))


# =====================================================================
#  变电站控制楼：x[104,126]×z[-26,-12] 高 5，南门 x[106,109] 净高 3.4
# =====================================================================
def sub_ctrl():
    x0, x1, z0, z1, h = 104.0, 126.0, -26.0, -12.0, 5.0
    K.begin(115.0, -19.0)
    plaster = pbr("plaster_paint", (0.8, 0.8, 0.77), 3.0)
    s_win = [111.0 + 3.25 * k for k in range(5)]
    s_open = [(106.0, 109.0, 0.0, 3.4)] + [(c - 1.0, c + 1.0, 1.0, 3.4) for c in s_win]
    w_win = [-23.0 + 2.8 * k for k in range(4)]
    w_open = [(c - 0.95, c + 0.95, 1.2, 3.2) for c in w_win]
    n_win = [107.5 + 3.0 * k for k in range(6)]
    n_open = [(c - 1.3, c + 1.3, 3.4, 4.6) for c in n_win]
    e_open = []
    for y0, y1, m in ((0.0, 0.6, CONC_D), (0.6, h, plaster)):
        wall("x", z1 - WT / 2, x0, x1, y0, y1, WT, s_open, m)
        wall("x", z0 + WT / 2, x0, x1, y0, y1, WT, n_open, m)
        wall("z", x0 + WT / 2, z0 + WT, z1 - WT, y0, y1, WT, w_open, m)
        wall("z", x1 - WT / 2, z0 + WT, z1 - WT, y0, y1, WT, e_open, m)
    for c in s_win:
        window("x", z1 - WT / 2, 1, c, 2.0, 1.0, 2.4, WT, FRAME_W, 1, 1, CONC)
    for c in w_win:
        window("z", x0 + WT / 2, -1, c, 1.9, 1.2, 2.0, WT, FRAME_W, 1, 0, CONC)
    for c in n_win:
        window("x", z0 + WT / 2, -1, c, 2.6, 3.4, 1.2, WT, FRAME_W, 2, 0)
    door_frame("x", z1 - WT / 2, 1, 106.0, 109.0, 3.4, WT, FRAME_D)
    canopy("x", z1, 1, 105.6, 109.4, 3.75, 1.3, plain((0.85, 0.85, 0.83), 0.5, 0.2), STEEL)
    box(107.5, 4.3, z1 + 0.04, 2.6, 0.45, 0.04, RED)                        # 站名牌
    wall_lamp("x", z1 - WT / 2, 1, 110.0, 3.0, WT)
    flat_roof(x0, x1, z0, z1, h, CONC, plaster, CONC, 0.6, 0.0)
    # 东墙：电缆桥架 + 竖向线管 + 百叶 + 外机
    box(x1 + 0.3, 4.1, -19.0, 0.15, 0.12, 12.0, STEEL)
    for z in (-24.0, -19.0, -14.0):
        cyl(x1 + 0.3, 2.05, z, 0.05, 4.1, "y", STEEL, 8)
    for z in (-21.5, -16.5):
        box(x1 + 0.27, 2.4, z, 0.04, 1.0, 1.4, FRAME_D)
        for k in range(6):
            box(x1 + 0.3, 2.0 + 0.15 * k, z, 0.08, 0.04, 1.3, STEEL_L)
    ac_unit(x1 + 0.5, 0.6, -23.5, False)
    # 屋顶：卧罐 ×2（鞍座）+ 立式水塔（短腿立在屋面）
    for tx in (112.0, 118.0):
        cyl(tx, h + 1.5, -21.5, 0.8, 4.0, "x", STEEL_L, 20)
        for dx in (-1.2, 1.2):
            box(tx + dx, h + 0.65, -21.5, 0.25, 0.7, 1.2, STEEL)
    for k in range(4):
        import math
        a = math.tau * k / 4 + 0.79
        box(122.5 + math.cos(a) * 0.95, h + 1.05, -22.5 + math.sin(a) * 0.95, 0.15, 1.5, 0.15,
            STEEL)
    cyl(122.5, h + 3.1, -22.5, 1.2, 2.6, "y", STEEL_L, 20)
    cyl(122.5, h + 4.6, -22.5, 0.6, 0.5, "y", STEEL_L, 16)
    ladder(121.1, -22.5, h + 0.3, h + 4.4, "x", STEEL)
    # 室内机柜 ×3
    for k in range(3):
        box(105.6 + 1.5 * k, 1.1, -25.0, 1.2, 2.2, 0.7, plain((0.24, 0.25, 0.27), 0.5, 0.4))
    box(115.0, 0.02, -19.0, x1 - x0 - 1.0, 0.04, z1 - z0 - 1.0, FLOOR)
    for x in (x0 + 0.3, x1 - 0.3):
        downpipe(x, z1 + 0.32, h, STEEL_L)
    done("sub_ctrl", (96.0, 5.0, 0.0), (115.0, 2.5, -19.0))


# =====================================================================
#  水泥厂主楼：x[-92,-76]×z[14,40] 高 10，北面 3 个卷帘门洞（净高 3.3）
# =====================================================================
def cement_main():
    x0, x1, z0, z1, h = -92.0, -76.0, 14.0, 40.0, 10.0
    K.begin(-84.0, 27.0)
    brick = pbr("brick", (0.6, 0.45, 0.35), 2.2)
    clad = pbr("corrugated", (0.72, 0.68, 0.57), 2.5)
    dh = 3.3
    n_doors = [(-92.0, -89.0), (-87.0, -81.0), (-79.0, -76.0)]
    n_up = [-89.5, -84.0, -78.5]
    n_open = [(a, b, 0.0, dh) for a, b in n_doors] + [(c - 1.2, c + 1.2, 6.4, 7.8) for c in n_up]
    s_up = [-90.0 + 3.5 * k for k in range(5)]
    s_open = [(c - 1.3, c + 1.3, 6.1, 7.9) for c in s_up] + \
        [(-91.5, -90.6, 1.2, 2.6), (-79.8, -78.2, 1.2, 2.6)]
    side_up = [18.0, 23.0, 28.0, 33.0]
    side_lo = [20.0, 27.0, 34.0]
    side_open = [(c - 1.2, c + 1.2, 6.4, 7.8) for c in side_up] + \
        [(c - 0.8, c + 0.8, 1.2, 2.6) for c in side_lo]
    for y0, y1, m in ((0.0, 0.5, CONC_D), (0.5, 5.2, brick), (5.5, h, clad)):
        wall("x", z0 + WT / 2, x0, x1, y0, y1, WT, n_open, m)
        wall("x", z1 - WT / 2, x0, x1, y0, y1, WT, s_open, m)
        wall("z", x0 + WT / 2, z0 + WT, z1 - WT, y0, y1, WT, side_open, m)
        wall("z", x1 - WT / 2, z0 + WT, z1 - WT, y0, y1, WT, side_open, m)
    # 楼层腰线（5.2~5.5 混凝土）
    wall("x", z0 + WT / 2, x0, x1, 5.2, 5.5, WT + 0.12, [], CONC)
    wall("x", z1 - WT / 2, x0, x1, 5.2, 5.5, WT + 0.12, [], CONC)
    wall("z", x0 + WT / 2, z0, z1, 5.2, 5.5, WT + 0.12, [], CONC)
    wall("z", x1 - WT / 2, z0, z1, 5.2, 5.5, WT + 0.12, [], CONC)
    for c in n_up:
        window("x", z0 + WT / 2, -1, c, 2.4, 6.4, 1.4, WT, FRAME_D, 1, 0, CONC)
    for c in s_up:
        window("x", z1 - WT / 2, 1, c, 2.6, 6.1, 1.8, WT, FRAME_D, 1, 0, CONC)
    for c in (-91.05, -79.0):
        window("x", z1 - WT / 2, 1, c, 0.9 if c < -90 else 1.6, 1.2, 1.4, WT, FRAME_D, 0, 0, CONC)
    for xx, s in ((x0 + WT / 2, -1), (x1 - WT / 2, 1)):
        for c in side_up:
            window("z", xx, s, c, 2.4, 6.4, 1.4, WT, FRAME_D, 1, 0, CONC)
        for c in side_lo:
            window("z", xx, s, c, 1.6, 1.2, 1.4, WT, FRAME_D, 1, 0, CONC)
    for a, b in ((-91.5, -89.0), (-87.0, -81.0), (-79.0, -76.5)):
        roller_shutter("x", z0 + WT / 2, -1, a, b, dh, WT, STEEL_L, RED, STEEL)
    gable_roof_z(x0, x1, z0, z1, h, 8.0, 0.5, 0.4, ROOF_GREY, STEEL_L, clad, gutter=STEEL_L)
    box(-84.0, 5.3, 27.25, 15.0, 0.4, 25.0, CONC)                           # 二层楼板
    # 北侧二层平台（钢格栅）+ 栏杆 + 两根混凝土柱 + 两段爬梯
    box(-88.0, 5.3, 12.25, 8.0, 0.4, 3.5, GRATE)
    railing([(-92.0, 13.8), (-92.0, 10.6), (-84.0, 10.6), (-84.0, 13.8)], 5.5, 1.05, STEEL,
            STEEL_L, 1.3)
    for px in (-90.8, -85.2):
        box(px, 2.55, 10.9, 0.6, 5.1, 0.6, CONC)
    ladder(-88.0, 10.3, 0.0, 5.5, "z", STEEL)
    for x in (x0 - 0.62, x1 + 0.62):          # 屋脊沿 Z：檐沟在东西两侧
        for z in (z0 + 0.35, z1 - 0.35):
            downpipe(x, z, h - 0.2, STEEL_L)
    for c in (-90.5, -82.5, -77.5):
        wall_lamp("x", z0 + WT / 2, -1, c, 4.0, WT)
    box(-84.0, 0.025, 27.0, x1 - x0 - 1.0, 0.05, z1 - z0 - 1.0, FLOOR)
    done("cement_main", (-62.0, 7.0, 4.0), (-84.0, 4.0, 27.0))


# =====================================================================
#  水泥厂宿舍：x[-90,-82]×z[40,46] 高 5，西门 z[44.6,46] 净高 3.1，单坡顶（东高西低）
# =====================================================================
def cement_dorm():
    K.begin(-86.0, 43.0)
    plaster = pbr("plaster_paint", (0.82, 0.78, 0.66), 3.0)
    h, he = 5.0, 5.9
    win = [(-88.2, -86.8, 1.5, 3.1), (-85.2, -83.8, 1.5, 3.1)]
    for y0, y1, m in ((0.0, 0.5, CONC_D), (0.5, h, plaster)):
        wall("x", 40.15, -90.0, -82.0, y0, y1, 0.4, [], m)
        wall("x", 45.75, -90.0, -82.0, y0, y1, WT, win if y0 > 0 else [], m)
        wall("z", -89.75, 40.35, 46.0, y0, y1, WT, [(44.6, 46.0, 0.0, 3.1)], m)
        wall("z", -82.25, 40.35, 45.5, y0, y1, WT, [], m)
    prism_tri((-90.0, h, 40.15), (-82.0, h, 40.15), (-82.0, he, 40.15), "z", 0.4, plaster)
    prism_tri((-90.0, h, 45.75), (-82.0, h, 45.75), (-82.0, he, 45.75), "z", WT, plaster)
    wall("z", -82.25, 40.35, 45.5, h, he, WT, [], plaster)
    for c in (-87.5, -84.5):
        window("x", 45.75, 1, c, 1.4, 1.5, 1.6, WT, FRAME_W, 1, 0, CONC)
    door_frame("z", -89.75, -1, 44.6, 45.9, 3.1, WT, FRAME_D)
    quad_slab((-90.35, h - 0.02, 46.3), (-81.65, he + 0.05, 46.3), (-81.65, he + 0.05, 39.9),
              (-90.35, h - 0.02, 39.9), 0.12, pbr("corrugated", (0.45, 0.32, 0.26), 2.0))
    box(-91.2, 0.15, 45.0, 1.9, 0.3, 2.6, CONC)
    canopy("z", -90.0, -1, 44.4, 46.1, 3.45, 1.1, STEEL_L, STEEL)
    wall_lamp("z", -89.75, -1, 44.3, 3.0, WT)
    ladder(-82.6, 46.05, 0.0, he, "z", STEEL)
    ac_unit(-88.0, 0.9, 46.5, True)
    done("cement_dorm", (-96.0, 3.0, 54.0), (-86.0, 2.5, 43.0))


if __name__ == "__main__":
    only = os.environ.get("ONLY", "")
    jobs = {"fac_a": fac_a, "fac_b": fac_b, "fac_c": fac_c, "visitor": visitor,
            "barracks": barracks, "hut_a": lambda: hut("hut_a", -123.0, -11.0, True),
            "hut_b": lambda: hut("hut_b", -125.0, -37.0, False), "sub_ctrl": sub_ctrl,
            "cement_main": cement_main, "cement_dorm": cement_dorm}
    for n, fn in jobs.items():
        if only and n not in only.split(","):
            continue
        fn()
