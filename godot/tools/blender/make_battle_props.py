"""大战场场景道具生成器（Blender 5.x 后台脚本）。

用法（在 godot/ 目录下）：
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/make_battle_props.py \
      -- assets/battle/props [预览图目录]

每个道具导出一个 glb（原点在底面中心、正面朝 -Y → Godot +Z），尺寸即地图里的实际尺寸，
Godot 端（battle_map.gd）按需缩放/旋转并沿用原来的碰撞盒：
  house        土坯平顶房 7×6×3.1（前后门洞 1.8m、窗洞、女儿墙、出挑木梁）
  barn         谷仓 12×8×4.8（双坡铁皮顶）
  warehouse    仓库 22×12×6.5（波纹钢板墙、卷帘门、高窗、双坡顶）
  bunker       混凝土掩体 14×9×3.2（射击孔、顶部沙袋）
  sandbags     沙袋墙 2.5×0.75×1.6（逐袋堆叠、错缝）
  container    集装箱 2.44×6.06×2.59（波纹侧板、端门锁杆，灰阶漆面按实例染色）
  fuel_tank    储油罐 r5×7（焊缝环、锥顶、爬梯、顶部栏杆）
  barrier      混凝土 T 型防爆墙 4.2×0.5×1.25
  crate        木箱 1×1×1（框 + 板条）
  barrel       油桶 0.6×0.9（加强筋，按实例染色）
  wreck        烧毁轿车残骸 2.0×4.4×1.5
  rocks        周界石墙段 12.5×2.8×2.8
  tent         军用帐篷 6×4×2.6
  dead_tree    枯树 高 4.2
"""
import bpy
import bmesh
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl_common as C  # noqa: E402
from bl_common import V  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(ARGV[0] if ARGV else "props")
PREVIEW = os.path.abspath(ARGV[1]) if len(ARGV) > 1 else ""

C.reset_scene()
random.seed(20260926)

M_PLASTER = C.mat("Plaster", tex_fn=C.tex_plaster)
M_CONCRETE = C.mat("Concrete", tex_fn=C.tex_concrete)
M_WOOD = C.mat("Wood", rough=0.85, tex_fn=C.tex_wood)
M_BURLAP = C.mat("Burlap", rough=1.0, tex_fn=C.tex_burlap)
M_RUST = C.mat("Rust", rough=0.8, metal=0.3, tex_fn=C.tex_rust)
M_PAINT = C.mat("Paint", rough=0.55, metal=0.35, tex_fn=C.tex_paint_gray)
M_TANK = C.mat("TankPaint", rough=0.45, metal=0.4, tex_fn=C.tex_tank)
M_ROCK = C.mat("Rock", rough=1.0, tex_fn=C.tex_rock)
M_CANVAS = C.mat("Canvas", rough=1.0, tex_fn=C.tex_canvas)
M_BARK = C.mat("Bark", rough=1.0, tex_fn=C.tex_bark)
M_DARK = C.mat("Dark", color=(0.05, 0.05, 0.055), rough=0.9)
M_METAL = C.mat("Metal", color=(0.35, 0.36, 0.38), rough=0.5, metal=0.8)

PROPS = []


def finish(ob, uv_scale=0.5, flat=True):
    C.uv_box(ob, uv_scale)
    if flat:
        C.flat_shade(ob)
    PROPS.append(ob)
    return ob


# ================= 房屋类 =================

def house_walls(bm, w, d, h, t, door_w, door_h, win, slits, mi):
    """四面墙：前后墙中间门洞，窗/射击孔按 win/slits"""
    fw = []   # 前后墙洞口
    sw = []   # 侧墙洞口
    fw.append((0.0, 0.0, door_w, door_h))
    if slits:
        for off in (-w * 0.32, w * 0.32):
            fw.append((off, 1.35, 0.9, 0.18))
        sw.append((0.0, 1.35, 1.2, 0.18))
    elif win:
        if w > 5.0:
            for off in (-w * 0.3, w * 0.3):
                fw.append((off, 1.0, 0.8, 0.85))
        sw.append((0.0, 1.0, 0.9, 0.85))
    for sy in (-1, 1):
        C.wall_openings(bm, True, V(0, sy * (d - t) * 0.5, 0), w, h, t, fw, mi)
    for sx in (-1, 1):
        C.wall_openings(bm, False, V(sx * (w - t) * 0.5, 0, 0), d - 2 * t, h, t, sw, mi)


def gable(bm, w, d, h, rise, overhang, mi_roof, mi_wall, t):
    """双坡顶（屋脊沿 X）+ 两端山墙三角"""
    half = d * 0.5 + overhang
    ang = math.atan2(rise, d * 0.5)
    slope = half / math.cos(ang)
    for sy in (-1, 1):
        C.box(bm, V(0, sy * half * 0.5, h + rise * 0.5), V(w + overhang * 2, slope, 0.08),
              rot=(sy * -ang, 0, 0), mat_i=mi_roof)
    for sx in (-1, 1):
        x = sx * (w * 0.5 - t * 0.5)
        vs = [bm.verts.new(V(x, -d * 0.5, h)), bm.verts.new(V(x, d * 0.5, h)),
              bm.verts.new(V(x, 0, h + rise))]
        f = bm.faces.new(vs if sx > 0 else list(reversed(vs)))
        f.material_index = mi_wall


def house(name, w, d, h, wall_mat, roof="flat", slits=False, vigas=True, sandbag_top=False):
    t = 0.4
    mats = [wall_mat, M_WOOD, M_DARK, M_PAINT, M_BURLAP]

    def build(bm):
        house_walls(bm, w, d, h, t, 1.8, 2.2, True, slits, 0)
        # 门框过梁 / 窗台（木）
        for sy in (-1, 1):
            C.box(bm, V(0, sy * (d * 0.5 + 0.02), 2.25), V(2.1, 0.12, 0.14), mat_i=1)
        if roof == "flat":
            C.box(bm, V(0, 0, h + 0.1), V(w + 0.1, d + 0.1, 0.2), mat_i=0)
            for sy in (-1, 1):
                C.box(bm, V(0, sy * (d * 0.5 - 0.05), h + 0.35), V(w + 0.1, 0.2, 0.3), mat_i=0)
            for sx in (-1, 1):
                C.box(bm, V(sx * (w * 0.5 - 0.05), 0, h + 0.35), V(0.2, d - 0.3, 0.3), mat_i=0)
            if vigas:   # 出挑木梁（土坯房的标志）
                n = max(3, int(w / 1.3))
                for k in range(n):
                    x = -w * 0.5 + (k + 0.5) * w / n
                    for sy in (-1, 1):
                        C.box(bm, V(x, sy * (d * 0.5 + 0.2), h - 0.12), V(0.14, 0.45, 0.14), mat_i=1)
            # 屋顶排水口
            C.box(bm, V(w * 0.3, -d * 0.5 - 0.25, h + 0.15), V(0.12, 0.5, 0.1), mat_i=1)
        else:
            gable(bm, w, d, h, rise=d * 0.28, overhang=0.35, mi_roof=3, mi_wall=0, t=t)
        if sandbag_top:
            for sx in (-1, 1):
                for k in range(int(d / 0.6)):
                    C.box(bm, V(sx * (w * 0.5 - 0.3), -d * 0.5 + 0.3 + k * 0.6, h + 0.28),
                          V(0.35, 0.55, 0.16), bevel=0.04, mat_i=4)

    return finish(C.new_object(name, build, mats), 0.5)


house("house", 7.0, 6.0, 3.1, M_PLASTER)
house("barn", 12.0, 8.0, 4.8, M_PLASTER, roof="gable", vigas=False)
house("bunker", 14.0, 9.0, 3.2, M_CONCRETE, slits=True, vigas=False, sandbag_top=True)


def warehouse():
    w, d, h, t = 22.0, 12.0, 6.5, 0.3
    mats = [M_PAINT, M_METAL, M_DARK, M_CONCRETE]

    def build(bm):
        # 墙：前后墙卷帘门洞 4.2×4.5，侧墙高窗
        fw = [(0.0, 0.0, 4.2, 4.5)]
        sw = [(off, 4.4, 2.2, 1.0) for off in (-3.0, 0.0, 3.0)]
        for sy in (-1, 1):
            C.wall_openings(bm, True, V(0, sy * (d - t) * 0.5, 0), w, h, t, fw, 0)
        for sx in (-1, 1):
            C.wall_openings(bm, False, V(sx * (w - t) * 0.5, 0, 0), d - 2 * t, h, t, sw, 0)
        # 波纹：外墙竖筋
        for sy in (-1, 1):
            x = -w * 0.5 + 0.2
            while x < w * 0.5 - 0.1:
                if abs(x) > 2.2:
                    C.box(bm, V(x, sy * (d * 0.5 + 0.02), h * 0.5), V(0.06, 0.05, h), mat_i=0)
                x += 0.45
        # 卷帘门（半开）+ 门框
        for sy in (-1, 1):
            C.box(bm, V(0, sy * (d * 0.5 - 0.1), 3.3), V(4.2, 0.08, 2.4), mat_i=1)
            for sx in (-1, 1):
                C.box(bm, V(sx * 2.2, sy * (d * 0.5 + 0.05), 2.25), V(0.2, 0.2, 4.5), mat_i=2)
        # 墙裙（混凝土）
        for sy in (-1, 1):
            for sx in (-1, 1):
                C.box(bm, V(sx * (w * 0.25 + 1.1), sy * (d * 0.5 + 0.03), 0.4),
                      V(w * 0.5 - 2.2, 0.36, 0.8), mat_i=3)
        # 屋顶：双坡（屋脊沿 X）+ 山墙
        half = d * 0.5 + 0.4
        rise = 1.6
        ang = math.atan2(rise, d * 0.5)
        for sy in (-1, 1):
            C.box(bm, V(0, sy * half * 0.5, h + rise * 0.5), V(w + 0.8, half / math.cos(ang), 0.1),
                  rot=(sy * -ang, 0, 0), mat_i=1)
        for sx in (-1, 1):
            x = sx * (w * 0.5 - t * 0.5)
            vs = [bm.verts.new(V(x, -d * 0.5, h)), bm.verts.new(V(x, d * 0.5, h)),
                  bm.verts.new(V(x, 0, h + rise))]
            bm.faces.new(vs if sx > 0 else list(reversed(vs))).material_index = 0

    return finish(C.new_object("warehouse", build, mats), 0.35)


warehouse()


# ================= 掩体 / 小道具 =================

def sandbags():
    L, D, H = 2.5, 0.75, 1.6
    mats = [M_BURLAP]
    rnd = random.Random(7)

    def build(bm):
        course = 0.16
        rows = int(H / course)
        for r in range(rows):
            z = r * course + course * 0.5
            off = 0.25 if r % 2 else 0.0
            n = 5
            bl = L / n
            for k in range(n + (1 if off else 0)):
                x = -L * 0.5 + off + (k + 0.5) * bl - (bl * 0.5 if off else 0)
                x0 = max(-L * 0.5, x - bl * 0.5)
                x1 = min(L * 0.5, x + bl * 0.5)
                if x1 - x0 < 0.1:
                    continue
                for dy in (-D * 0.25, D * 0.25):
                    C.box(bm, V((x0 + x1) * 0.5 + rnd.uniform(-0.02, 0.02), dy + rnd.uniform(-0.02, 0.02), z),
                          V((x1 - x0) * 0.96, D * 0.48, course * 1.05),
                          rot=(0, 0, rnd.uniform(-0.05, 0.05)), bevel=0.045)

    ob = C.new_object("sandbags", build, mats)
    finish(ob, 1.0, flat=False)


sandbags()


def container():
    W, L, H = 2.44, 6.06, 2.59
    mats = [M_PAINT, M_METAL, M_DARK]

    def build(bm):
        C.box(bm, V(0, 0, H * 0.5), V(W - 0.1, L - 0.1, H - 0.1), mat_i=0)
        # 侧板波纹
        for sx in (-1, 1):
            y = -L * 0.5 + 0.25
            while y < L * 0.5 - 0.2:
                C.box(bm, V(sx * (W * 0.5 - 0.02), y, H * 0.5), V(0.06, 0.12, H - 0.3), mat_i=0)
                y += 0.28
        # 顶/底框梁 + 四角柱
        for sx in (-1, 1):
            for z in (0.08, H - 0.08):
                C.box(bm, V(sx * (W * 0.5 - 0.05), 0, z), V(0.12, L, 0.16), mat_i=0)
            for sy in (-1, 1):
                C.box(bm, V(sx * (W * 0.5 - 0.06), sy * (L * 0.5 - 0.06), H * 0.5),
                      V(0.14, 0.14, H), mat_i=0)
        # 端门：两扇 + 4 根锁杆
        C.box(bm, V(0, -L * 0.5 + 0.02, H * 0.5), V(0.03, 0.02, H - 0.3), mat_i=2)
        for x in (-0.8, -0.35, 0.35, 0.8):
            C.cyl(bm, V(x, -L * 0.5 - 0.02, H * 0.5), 0.025, H - 0.25, segs=6, mat_i=1)

    finish(C.new_object("container", build, mats), 0.5)


container()


def fuel_tank():
    R, H = 5.0, 7.0
    mats = [M_TANK, M_METAL, M_RUST]

    def build(bm):
        C.cyl(bm, V(0, 0, H * 0.5), R, H, segs=40, mat_i=0)
        C.cyl(bm, V(0, 0, H + 0.4), R, 0.8, segs=40, r2=0.8, mat_i=0)
        for k in range(1, 5):   # 焊缝环
            C.cyl(bm, V(0, 0, k * H / 5.0), R + 0.025, 0.06, segs=40, mat_i=1)
        C.cyl(bm, V(0, 0, 0.15), R + 0.08, 0.3, segs=40, mat_i=2)   # 锈蚀底环
        # 爬梯（+X 侧）
        for sy in (-1, 1):
            C.box(bm, V(R + 0.35, sy * 0.25, (H + 0.8) * 0.5), V(0.06, 0.06, H + 0.8), mat_i=1)
        z = 0.4
        while z < H + 0.6:
            C.box(bm, V(R + 0.35, 0, z), V(0.05, 0.5, 0.04), mat_i=1)
            z += 0.35
        # 顶部栏杆（8 根立柱 + 横杆）
        for k in range(16):
            a = k / 16.0 * math.tau
            C.box(bm, V(math.cos(a) * (R - 0.25), math.sin(a) * (R - 0.25), H + 0.55),
                  V(0.05, 0.05, 1.1), mat_i=1)
        C.cyl(bm, V(0, 0, H + 1.1), R - 0.25, 0.05, segs=32, mat_i=1, caps=False)
        # 进出油管
        C.cyl(bm, V(-R - 0.8, 0, 0.6), 0.18, 1.6, axis="X", segs=10, mat_i=1)

    finish(C.new_object("fuel_tank", build, mats), 0.25)


fuel_tank()


def barrier():
    L, T, H = 4.2, 0.5, 1.25
    mats = [M_CONCRETE, M_METAL]

    def build(bm):
        for sx in (-1, 1):   # 两节 T 型墙，中间留缝
            cx = sx * L * 0.25
            C.box(bm, V(cx, 0, 0.12), V(L * 0.5 - 0.04, T * 1.5, 0.24), bevel=0.02, mat_i=0)
            C.box(bm, V(cx, 0, 0.24 + (H - 0.24) * 0.5), V(L * 0.5 - 0.04, T * 0.6, H - 0.24),
                  bevel=0.02, mat_i=0)
            C.box(bm, V(cx, 0, H - 0.05), V(0.12, 0.08, 0.1), mat_i=1)   # 吊环

    finish(C.new_object("barrier", build, mats), 0.6)


barrier()


def crate():
    mats = [M_WOOD]

    def build(bm):
        C.box(bm, V(0, 0, 0.5), V(0.94, 0.94, 0.94), mat_i=0)
        for ax in range(3):   # 12 条框边
            for s1 in (-1, 1):
                for s2 in (-1, 1):
                    if ax == 0:
                        C.box(bm, V(0, s1 * 0.47, 0.5 + s2 * 0.47), V(1.0, 0.08, 0.08))
                    elif ax == 1:
                        C.box(bm, V(s1 * 0.47, 0, 0.5 + s2 * 0.47), V(0.08, 1.0, 0.08))
                    else:
                        C.box(bm, V(s1 * 0.47, s2 * 0.47, 0.5), V(0.08, 0.08, 1.0))
        for sy in (-1, 1):   # 前后斜撑
            C.box(bm, V(0, sy * 0.48, 0.5), V(1.25, 0.05, 0.08), rot=(0, math.radians(45), 0))

    finish(C.new_object("crate", build, mats), 1.0)


crate()


def barrel():
    mats = [M_PAINT, M_METAL]

    def build(bm):
        C.cyl(bm, V(0, 0, 0.45), 0.29, 0.9, segs=18, mat_i=0)
        for z in (0.3, 0.6):
            C.cyl(bm, V(0, 0, z), 0.305, 0.03, segs=18, mat_i=1)
        C.cyl(bm, V(0.12, 0, 0.905), 0.03, 0.02, segs=8, mat_i=1)

    ob = C.new_object("barrel", build, mats)
    finish(ob, 1.5, flat=False)


barrel()


def wreck():
    mats = [M_RUST, M_DARK]

    def build(bm):
        C.box(bm, V(0, 0, 0.62), V(1.85, 4.3, 0.6), bevel=0.12, mat_i=0)          # 车身
        C.box(bm, V(0, 0.25, 1.12), V(1.55, 2.0, 0.5), bevel=0.1, mat_i=0)        # 车舱
        C.box(bm, V(0, -0.8, 1.05), V(1.4, 0.05, 0.4), rot=(math.radians(-35), 0, 0), mat_i=1)  # 破挡风
        for sx in (-1, 1):
            for sy in (-1.35, 1.35):
                C.cyl(bm, V(sx * 0.82, sy, 0.3), 0.3, 0.2, axis="X", segs=10, mat_i=1)   # 轮毂
            C.box(bm, V(sx * 0.79, 0.25, 1.12), V(0.03, 1.6, 0.34), mat_i=1)          # 空窗
        # 车身整体下沉略歪（烧毁趴窝）
        bmesh.ops.rotate(bm, cent=V(0, 0, 0), verts=bm.verts[:],
                         matrix=C.Matrix.Rotation(math.radians(3), 3, "Y"))

    finish(C.new_object("wreck", build, mats), 0.6, flat=False)


wreck()


def rocks():
    mats = [M_ROCK]
    rnd = random.Random(99)

    def build(bm):
        for k in range(4):
            x = -4.7 + k * 3.1 + rnd.uniform(-0.3, 0.3)
            res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
            vs = res["verts"]
            sx = rnd.uniform(1.7, 2.1)
            sy = rnd.uniform(1.2, 1.5)
            sz = rnd.uniform(1.1, 1.45)
            for v in vs:
                n = v.co.normalized()
                bump = 1.0 + 0.18 * math.sin(n.x * 5 + k) * math.cos(n.y * 4 + k * 2) \
                    + rnd.uniform(-0.06, 0.06)
                v.co = V(n.x * sx * bump + x, n.y * sy * bump, max(n.z * sz * bump + sz * 0.7, 0.0))

    finish(C.new_object("rocks", build, mats), 0.35, flat=True)


rocks()


def tent():
    W, D, H, WH = 6.0, 4.0, 2.6, 1.3
    mats = [M_CANVAS, M_WOOD, M_DARK]

    def build(bm):
        C.box(bm, V(0, 0, WH * 0.5), V(W, D, WH), mat_i=0)            # 墙
        for sy in (-1, 1):                                              # 两坡
            ang = math.atan2(H - WH, D * 0.5)
            C.box(bm, V(0, sy * D * 0.26, WH + (H - WH) * 0.5),
                  V(W + 0.3, (D * 0.5 + 0.2) / math.cos(ang), 0.05), rot=(sy * -ang, 0, 0), mat_i=0)
        for sx in (-1, 1):                                              # 山墙三角
            x = sx * W * 0.5
            vs = [bm.verts.new(V(x, -D * 0.5, WH)), bm.verts.new(V(x, D * 0.5, WH)),
                  bm.verts.new(V(x, 0, H))]
            bm.faces.new(vs if sx > 0 else list(reversed(vs))).material_index = 0
        C.box(bm, V(0, -D * 0.5 - 0.01, 0.8), V(1.1, 0.02, 1.6), mat_i=2)   # 门帘开口
        for sx in (-1, 0, 1):                                           # 撑杆
            C.cyl(bm, V(sx * (W * 0.5 - 0.1), 0, H * 0.5), 0.04, H, segs=6, mat_i=1)

    finish(C.new_object("tent", build, mats), 0.5)


tent()


def dead_tree():
    mats = [M_BARK]
    rnd = random.Random(5)

    def build(bm):
        C.cyl(bm, V(0, 0, 2.1), 0.17, 4.2, segs=8, r2=0.07)
        for k in range(4):
            z = 1.6 + k * 0.6
            a = rnd.uniform(0, math.tau)
            L = rnd.uniform(1.0, 1.8)
            tilt = rnd.uniform(0.5, 0.9)
            vs = C.cyl(bm, V(0, 0, L * 0.5), 0.06, L, segs=6, r2=0.02)
            bmesh.ops.rotate(bm, cent=V(0, 0, 0), verts=vs,
                             matrix=C.Matrix.Rotation(a, 3, "Z") @ C.Matrix.Rotation(tilt, 3, "X"))
            bmesh.ops.translate(bm, vec=V(0, 0, z), verts=vs)

    finish(C.new_object("dead_tree", build, mats), 1.0, flat=False)


dead_tree()

# ================= 导出 =================
for ob in PROPS:
    C.export_glb(ob, os.path.join(OUT_DIR, ob.name + ".glb"))
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("[props] %-10s 三角面 %5d" % (ob.name, tris))

if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 520
    scene.render.resolution_y = 420
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for ob in PROPS:
        for o in PROPS:
            o.hide_render = o is not ob
        dims = ob.dimensions
        r = max(dims.x, dims.y, dims.z) * 1.35 + 1.0
        cam.location = V(r * 0.75, -r * 0.95, dims.z * 0.5 + r * 0.45)
        direction = V(0, 0, dims.z * 0.4) - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(PREVIEW, ob.name + ".png")
        bpy.ops.render.render(write_still=True)
    print("[props] 预览 → %s" % PREVIEW)
