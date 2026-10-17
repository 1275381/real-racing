"""烽火地带建筑建模工具包（Blender 后台脚本共用）。

坐标约定：所有函数参数都用「游戏坐标」（Godot：X 东、Y 上、Z 南），并减去当前建筑
原点 ORIGIN（建筑在游戏里的摆放点）；内部转成 Blender（Z 向上）：
  游戏 (x, y, z) → Blender (x, -z, y)，glTF 导出（+Y up）后正好回到游戏坐标。

材质只导出「名字」，不带贴图：Godot 端 hd_pbr.apply_named() 按名字换成世界坐标
三平面 PBR（与场景其余部分同一套 CC0 贴图），GLB 只有几何、体积小。命名：
  pbr_<kind>_<r>_<g>_<b>_<周期×10>   例 pbr_corrugated_45_42_33_25
  plain_<r>_<g>_<b>_<rough>_<metal>   （各两位百分数）
  glass / lamp
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix

ORIGIN = [0.0, 0.0]          # 当前建筑原点（游戏 x, z）
_MATS = {}
_BM = None


def begin(origin_x, origin_z):
    """开一栋新楼：清场、设原点、新 bmesh"""
    global _BM
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    ORIGIN[0] = origin_x
    ORIGIN[1] = origin_z
    _BM = bmesh.new()


def G(x, y, z):
    return Vector((x - ORIGIN[0], -(z - ORIGIN[1]), y))


# ---------------- 材质 ----------------

def _pct(v):
    return int(round(max(0.0, min(0.99, v)) * 100))


def pbr(kind, rgb, period):
    return "pbr_%s_%02d_%02d_%02d_%02d" % (kind, _pct(rgb[0]), _pct(rgb[1]), _pct(rgb[2]),
                                            int(round(period * 10)))


def plain(rgb, rough=0.7, metal=0.0):
    return "plain_%02d_%02d_%02d_%02d_%02d" % (_pct(rgb[0]), _pct(rgb[1]), _pct(rgb[2]),
                                               _pct(rough), _pct(metal))


GLASS = "glass"
LAMP = "lamp"


def _mat_index(name):
    if name not in _MATS:
        m = bpy.data.materials.new(name)
        # 预览色（工作台渲染用）：从名字里取设计色
        col = (0.6, 0.6, 0.6)
        parts = name.split("_")
        try:
            if name.startswith("pbr_"):
                col = tuple(int(p) / 100.0 for p in parts[-4:-1])
            elif name.startswith("plain_"):
                col = tuple(int(p) / 100.0 for p in parts[1:4])
            elif name == GLASS:
                col = (0.25, 0.32, 0.38)
            elif name == LAMP:
                col = (1.0, 0.95, 0.8)
        except ValueError:
            pass
        m.diffuse_color = (*col, 1.0)
        _MATS[name] = (len(_MATS), m)
    return _MATS[name][0]


# ---------------- 基本体 ----------------

def box(cx, cy, cz, sx, sy, sz, mat, bevel=0.0):
    """游戏坐标轴对齐盒：中心 (cx,cy,cz)、尺寸 (sx,sy,sz)"""
    r = bmesh.ops.create_cube(_BM, size=1.0)
    vs = r["verts"]
    bmesh.ops.scale(_BM, vec=Vector((sx, sz, sy)), verts=vs)
    bmesh.ops.translate(_BM, vec=G(cx, cy, cz), verts=vs)
    mi = _mat_index(mat)
    faces = {f for v in vs for f in v.link_faces}
    for f in faces:
        f.material_index = mi
    if bevel > 0:
        edges = list({e for v in vs for e in v.link_edges})
        res = bmesh.ops.bevel(_BM, geom=edges + vs, offset=bevel, segments=1, affect="EDGES")
        for f in res["faces"]:
            f.material_index = mi


def quad_slab(p0, p1, p2, p3, thick, mat):
    """任意四边形板（四个游戏坐标顶点，逆时针朝上）沿法线向下加厚"""
    ps = [G(*p) for p in (p0, p1, p2, p3)]
    n = (ps[1] - ps[0]).cross(ps[3] - ps[0]).normalized()
    top = [_BM.verts.new(p) for p in ps]
    bot = [_BM.verts.new(p - n * thick) for p in ps]
    mi = _mat_index(mat)
    faces = [top, bot[::-1]]
    for i in range(4):
        j = (i + 1) % 4
        faces.append([top[j], top[i], bot[i], bot[j]])
    for fv in faces:
        try:
            f = _BM.faces.new(fv)
            f.material_index = mi
        except ValueError:
            pass


def prism_tri(a, b, apex, thick_axis, thick, mat):
    """三角板（山墙）：三点游戏坐标，沿 thick_axis（'x' 或 'z'）加厚"""
    off = Vector((thick * 0.5, 0, 0)) if thick_axis == "x" else Vector((0, 0, thick * 0.5))
    pts = [Vector(a), Vector(b), Vector(apex)]
    f0 = [_BM.verts.new(G(*(p - off))) for p in pts]
    f1 = [_BM.verts.new(G(*(p + off))) for p in pts]
    mi = _mat_index(mat)
    for fv in (f0, f1[::-1], [f0[0], f0[1], f1[1], f1[0]], [f0[1], f0[2], f1[2], f1[1]],
               [f0[2], f0[0], f1[0], f1[2]]):
        try:
            f = _BM.faces.new(fv)
            f.material_index = mi
        except ValueError:
            pass


def cyl(cx, cy, cz, r, length, axis, mat, segs=12):
    """圆柱：axis 为游戏轴 'x'/'y'/'z'"""
    res = bmesh.ops.create_cone(_BM, cap_ends=True, segments=segs, radius1=r, radius2=r,
                                depth=length)
    vs = res["verts"]
    if axis == "x":
        bmesh.ops.rotate(_BM, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"),
                         verts=vs)
    elif axis == "z":
        bmesh.ops.rotate(_BM, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"),
                         verts=vs)
    bmesh.ops.translate(_BM, vec=G(cx, cy, cz), verts=vs)
    mi = _mat_index(mat)
    faces = {f for v in vs for f in v.link_faces}
    for f in faces:
        f.normal_update()
    for f in faces:
        f.material_index = mi
        f.smooth = abs(f.normal.dot(Vector((1, 0, 0)) if axis == "x" else
                           Vector((0, 0, 1)) if axis == "y" else Vector((0, 1, 0)))) < 0.9


# ---------------- 墙与洞口 ----------------

def wall(axis, fixed, a0, a1, y0, y1, thick, openings, mat):
    """开洞墙：axis='x' 墙沿 X（z=fixed），'z' 墙沿 Z（x=fixed）。
    openings: [(o0, o1, oy0, oy1)] 沿墙方向区间 + 高度区间；墙体按洞口切成矩形块"""
    pts = sorted({a0, a1} | {max(a0, min(a1, o[0])) for o in openings}
                 | {max(a0, min(a1, o[1])) for o in openings})
    for p, q in zip(pts, pts[1:]):
        if q - p < 1e-4:
            continue
        gaps = sorted((o[2], o[3]) for o in openings if o[0] <= p + 1e-4 and o[1] >= q - 1e-4)
        ys = y0
        spans = []
        for g0, g1 in gaps:
            if g0 > ys + 1e-4:
                spans.append((ys, min(g0, y1)))
            ys = max(ys, g1)
        if y1 > ys + 1e-4:
            spans.append((ys, y1))
        for s0, s1 in spans:
            if s1 - s0 < 1e-4:
                continue
            c = (p + q) * 0.5
            if axis == "x":
                box(c, (s0 + s1) * 0.5, fixed, q - p, s1 - s0, thick, mat)
            else:
                box(fixed, (s0 + s1) * 0.5, c, thick, s1 - s0, q - p, mat)


def _along(axis, fixed, a, y, out):
    """墙上一点：沿墙坐标 a、高度 y、离墙中线外移 out（游戏坐标三元组）"""
    return (a, y, fixed + out) if axis == "x" else (fixed + out, y, a)


def _box_on(axis, fixed, a, y, out, la, sy, depth, mat, bevel=0.0):
    c = _along(axis, fixed, a, y, out)
    if axis == "x":
        box(c[0], c[1], c[2], la, sy, depth, mat, bevel)
    else:
        box(c[0], c[1], c[2], depth, sy, la, mat, bevel)


def window(axis, fixed, side, c, w, y0, h, thick, frame, mullions=1, transoms=0,
           sill=None):
    """窗：玻璃居墙中、外框贴外墙皮凸出、窗台外挑。side=外侧方向 ±1。
    洞口须已在 wall(openings) 里留出"""
    o = side * thick * 0.5
    _box_on(axis, fixed, c, y0 + h * 0.5, 0.0, w, h, 0.05, GLASS)
    fw = 0.07
    for a in (c - w * 0.5 + fw * 0.5, c + w * 0.5 - fw * 0.5):
        _box_on(axis, fixed, a, y0 + h * 0.5, o * 0.6, fw, h, thick * 0.55, frame)
    for y in (y0 + fw * 0.5, y0 + h - fw * 0.5):
        _box_on(axis, fixed, c, y, o * 0.6, w, fw, thick * 0.55, frame)
    for k in range(1, mullions + 1):
        a = c - w * 0.5 + w * k / (mullions + 1)
        _box_on(axis, fixed, a, y0 + h * 0.5, side * 0.03, 0.05, h, 0.06, frame)
    for k in range(1, transoms + 1):
        _box_on(axis, fixed, c, y0 + h * k / (transoms + 1), side * 0.03, w, 0.05, 0.06, frame)
    if sill:
        _box_on(axis, fixed, c, y0 - 0.04, side * (thick * 0.5 + 0.03), w + 0.16, 0.08, 0.12,
                sill)


def door_frame(axis, fixed, side, a0, a1, h, thick, frame):
    o = side * (thick * 0.5 + 0.02)
    for a in (a0 - 0.06, a1 + 0.06):
        _box_on(axis, fixed, a, h * 0.5, o, 0.12, h, 0.08, frame)
    _box_on(axis, fixed, (a0 + a1) * 0.5, h + 0.06, o, a1 - a0 + 0.24, 0.12, 0.08, frame)


def door_leaf(axis, fixed, side, a0, a1, h, mat):
    """关着的门扇（实墙上的假门或半开门洞旁）"""
    _box_on(axis, fixed, (a0 + a1) * 0.5, h * 0.5, side * 0.27, a1 - a0, h, 0.05, mat)
    _box_on(axis, fixed, a1 - 0.18, h * 0.47, side * 0.31, 0.04, 0.16, 0.04, plain((0.5, 0.5, 0.5), 0.3, 0.9))


def roller_shutter(axis, fixed, side, a0, a1, h, thick, housing, slats, rail):
    """卷帘门（卷起）：洞口顶卷帘箱 + 两侧导轨 + 露出 0.35m 帘片"""
    o = side * (thick * 0.5 + 0.22)
    w = a1 - a0
    _box_on(axis, fixed, (a0 + a1) * 0.5, h - 0.3, o, w + 0.4, 0.6, 0.44, housing, 0.03)
    _box_on(axis, fixed, (a0 + a1) * 0.5, h - 0.78, side * (thick * 0.5 + 0.06), w, 0.36, 0.04,
            slats)
    for k in range(4):
        _box_on(axis, fixed, (a0 + a1) * 0.5, h - 0.65 - 0.09 * k, side * (thick * 0.5 + 0.085),
                w, 0.02, 0.012, housing)
    for a in (a0 - 0.05, a1 + 0.05):
        _box_on(axis, fixed, a, (h - 0.6) * 0.5, side * (thick * 0.5 + 0.05), 0.1, h - 0.6, 0.1,
                rail)


def canopy(axis, fixed, side, a0, a1, y, depth, mat, rod):
    """门雨棚：挑板 + 两根斜拉杆（fixed = 外墙皮坐标）"""
    _box_on(axis, fixed, (a0 + a1) * 0.5, y, side * depth * 0.5, a1 - a0, 0.12, depth, mat, 0.02)
    for a in (a0 + 0.2, a1 - 0.2):
        n = 6
        for k in range(n):
            t = (k + 0.5) / n
            _box_on(axis, fixed, a, y + 0.9 * (1 - t), side * depth * t, 0.04, 0.04,
                    depth / n * 1.15, rod)


def wall_lamp(axis, fixed, side, a, y, thick):
    _box_on(axis, fixed, a, y, side * (thick * 0.5 + 0.08), 0.22, 0.14, 0.16,
            plain((0.12, 0.12, 0.13), 0.5, 0.6))
    _box_on(axis, fixed, a, y - 0.09, side * (thick * 0.5 + 0.1), 0.18, 0.04, 0.12, LAMP)


def ac_unit(x, y, z, rot_axis_x=True, mat=None):
    """屋面/墙挂空调外机：机箱 + 风扇罩"""
    m = mat or plain((0.82, 0.82, 0.8), 0.5, 0.2)
    if rot_axis_x:
        box(x, y + 0.4, z, 1.1, 0.8, 0.45, m, 0.02)
        cyl(x + 0.15, y + 0.42, z + 0.23, 0.26, 0.03, "z", plain((0.1, 0.1, 0.1), 0.6, 0.3), 16)
    else:
        box(x, y + 0.4, z, 0.45, 0.8, 1.1, m, 0.02)
        cyl(x + 0.23, y + 0.42, z + 0.15, 0.26, 0.03, "x", plain((0.1, 0.1, 0.1), 0.6, 0.3), 16)


def roof_vent(x, y, z, mat):
    cyl(x, y + 0.35, z, 0.18, 0.7, "y", mat, 12)
    cyl(x, y + 0.75, z, 0.3, 0.08, "y", mat, 12)


def downpipe(x, z, y_top, mat):
    cyl(x, y_top * 0.5, z, 0.055, y_top, "y", mat, 10)
    box(x, 0.12, z, 0.14, 0.08, 0.14, mat)


def gable_roof_x(x0, x1, z0, z1, ye, pitch_deg, ov_z, ov_x, roof, fascia, gable_mat, thick=0.15,
                 wall_t=0.5, gutter=None):
    """双坡顶，屋脊沿 X（z 中线）。ye=墙顶（檐口线）高度；含山墙三角、脊盖、封檐板、檐沟"""
    zm = (z0 + z1) * 0.5
    t = math.tan(math.radians(pitch_deg))
    half = (z1 - z0) * 0.5
    yr = ye + half * t
    ye_out = ye - ov_z * t
    xa, xb = x0 - ov_x, x1 + ov_x
    quad_slab((xa, ye_out, z0 - ov_z), (xb, ye_out, z0 - ov_z), (xb, yr, zm), (xa, yr, zm), thick,
              roof)
    quad_slab((xb, ye_out, z1 + ov_z), (xa, ye_out, z1 + ov_z), (xa, yr, zm), (xb, yr, zm), thick,
              roof)
    box((x0 + x1) * 0.5, yr + 0.04, zm, xb - xa, 0.12, 0.42, fascia)   # 脊盖
    for gx in (x0 + wall_t * 0.5, x1 - wall_t * 0.5):
        prism_tri((gx, ye, z0), (gx, ye, z1), (gx, yr - 0.05, zm), "x", wall_t, gable_mat)
    for zz, s in ((z0 - ov_z, -1), (z1 + ov_z, 1)):
        box((x0 + x1) * 0.5, ye_out - 0.12, zz + s * 0.02, xb - xa, 0.26, 0.05, fascia)
        if gutter:
            box((x0 + x1) * 0.5, ye_out - 0.2, zz + s * 0.12, xb - xa, 0.14, 0.18, gutter)
    for xx in (xa, xb):   # 山墙封檐板（沿坡）
        for zs, ze in ((z0 - ov_z, zm), (z1 + ov_z, zm)):
            n = 8
            for k in range(n):
                ta = (k + 0.5) / n
                zz = zs + (ze - zs) * ta
                yy = ye_out + (yr - ye_out) * ta
                box(xx, yy - 0.08, zz, 0.05, 0.22, abs(ze - zs) / n * 1.02, fascia)
    return yr


def gable_roof_z(x0, x1, z0, z1, ye, pitch_deg, ov_x, ov_z, roof, fascia, gable_mat, thick=0.15,
                 wall_t=0.5, gutter=None):
    """双坡顶，屋脊沿 Z（x 中线）"""
    xm = (x0 + x1) * 0.5
    t = math.tan(math.radians(pitch_deg))
    half = (x1 - x0) * 0.5
    yr = ye + half * t
    ye_out = ye - ov_x * t
    za, zb = z0 - ov_z, z1 + ov_z
    quad_slab((x0 - ov_x, ye_out, zb), (x0 - ov_x, ye_out, za), (xm, yr, za), (xm, yr, zb), thick,
              roof)
    quad_slab((x1 + ov_x, ye_out, za), (x1 + ov_x, ye_out, zb), (xm, yr, zb), (xm, yr, za), thick,
              roof)
    box(xm, yr + 0.04, (z0 + z1) * 0.5, 0.42, 0.12, zb - za, fascia)
    for gz in (z0 + wall_t * 0.5, z1 - wall_t * 0.5):
        prism_tri((x0, ye, gz), (x1, ye, gz), (xm, yr - 0.05, gz), "z", wall_t, gable_mat)
    for xx, s in ((x0 - ov_x, -1), (x1 + ov_x, 1)):
        box(xx + s * 0.02, ye_out - 0.12, (z0 + z1) * 0.5, 0.05, 0.26, zb - za, fascia)
        if gutter:
            box(xx + s * 0.12, ye_out - 0.2, (z0 + z1) * 0.5, 0.18, 0.14, zb - za, gutter)
    return yr


def flat_roof(x0, x1, z0, z1, y, slab_mat, parapet_mat, coping_mat, parapet_h=0.7, ov=0.0):
    box((x0 + x1) * 0.5, y + 0.15, (z0 + z1) * 0.5, x1 - x0 + 2 * ov, 0.3, z1 - z0 + 2 * ov, slab_mat)
    if parapet_h > 0:
        t = 0.25
        for zz in (z0 - ov + t * 0.5, z1 + ov - t * 0.5):
            box((x0 + x1) * 0.5, y + 0.3 + parapet_h * 0.5, zz, x1 - x0 + 2 * ov, parapet_h, t,
                parapet_mat)
            box((x0 + x1) * 0.5, y + 0.3 + parapet_h + 0.05, zz, x1 - x0 + 2 * ov + 0.08, 0.1,
                t + 0.1, coping_mat)
        for xx in (x0 - ov + t * 0.5, x1 + ov - t * 0.5):
            box(xx, y + 0.3 + parapet_h * 0.5, (z0 + z1) * 0.5, t, parapet_h, z1 - z0 + 2 * ov - 2 * t,
                parapet_mat)
            box(xx, y + 0.3 + parapet_h + 0.05, (z0 + z1) * 0.5, t + 0.1, 0.1, z1 - z0 + 2 * ov,
                coping_mat)


def panel_joints(axis, fixed, side, a0, a1, y0, y1, step, thick, mat):
    """预制板竖缝（外墙皮上 1cm 凸线）"""
    n = int((a1 - a0) / step)
    for k in range(1, n + 1):
        a = a0 + k * step
        if a >= a1 - 0.1:
            break
        _box_on(axis, fixed, a, (y0 + y1) * 0.5, side * (thick * 0.5 + 0.005), 0.03, y1 - y0, 0.02,
                mat)


def railing(points, y, h, post_mat, rail_mat, post_step=1.5):
    """栏杆：沿折线 points[(x,z)]，立柱 + 上下扶手"""
    for (xa, za), (xb, zb) in zip(points, points[1:]):
        L = math.hypot(xb - xa, zb - za)
        n = max(1, int(L / post_step))
        for k in range(n + 1):
            t = k / n
            box(xa + (xb - xa) * t, y + h * 0.5, za + (zb - za) * t, 0.05, h, 0.05, post_mat)
        for yy in (y + h, y + h * 0.5):
            if abs(xb - xa) > abs(zb - za):
                box((xa + xb) * 0.5, yy, (za + zb) * 0.5, L, 0.045, 0.045, rail_mat)
            else:
                box((xa + xb) * 0.5, yy, (za + zb) * 0.5, 0.045, 0.045, L, rail_mat)


def ladder(x, z, y0, y1, axis, mat):
    """竖爬梯：两侧扶手 + 横档；axis = 梯面朝向的墙法线轴（'x' 或 'z'）"""
    for d in (-0.22, 0.22):
        if axis == "z":
            box(x + d, (y0 + y1) * 0.5, z, 0.05, y1 - y0, 0.05, mat)
        else:
            box(x, (y0 + y1) * 0.5, z + d, 0.05, y1 - y0, 0.05, mat)
    k = 0
    y = y0 + 0.3
    while y < y1:
        if axis == "z":
            box(x, y, z, 0.44, 0.035, 0.035, mat)
        else:
            box(x, y, z, 0.035, 0.035, 0.44, mat)
        y += 0.3
        k += 1


# ---------------- 导出 ----------------

def finish(name, out_path):
    me = bpy.data.meshes.new(name)
    bmesh.ops.remove_doubles(_BM, verts=_BM.verts, dist=0.0005)
    _BM.to_mesh(me)
    _BM.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for nm, (idx, m) in sorted(_MATS.items(), key=lambda kv: kv[1][0]):
        ob.data.materials.append(m)
    for p in me.polygons:
        if not p.use_smooth:
            p.use_smooth = False
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True,
                              export_yup=True, export_animations=False, export_materials="EXPORT")
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("[bldg] %s tris=%d mats=%d -> %s" % (name, tris, len(_MATS), out_path))
    return ob


def preview(ob, path, cam_from, look_at, size=(900, 560)):
    scn = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.location = G(*cam_from)
    cam.rotation_euler = (G(*look_at) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 28
    scn.camera = cam
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.display.shading.light = "STUDIO"
    scn.display.shading.color_type = "MATERIAL"
    scn.display.shading.show_shadows = True
    scn.display.shading.show_cavity = True
    scn.render.resolution_x, scn.render.resolution_y = size
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
