"""烽火地带 · 枪械建模 + 烘焙工具包（美术写实化第五轮：程序化枪 → Blender 写实枪）。

坐标：建模参数一律「枪身局部、真实米数」——x 右、y 上、z 向后（枪口朝 -z），
与 Godot hd_guns 枪身局部同轴；内部转 Blender (x, -z, y)，glTF 导出（+Y up）后
正好回到枪身局部。finish() 再整体等比缩放 + 平移，把真枪的握把点对到程序化枪
的 grip（游戏里沿用原持握/腰射/开镜数据链）。

建模：零件 = 侧视轮廓挤出 side() / 截面挤出 xsec() / 车削 lathe() / 盒 box() /
圆柱 cyl()；同材质小件用 Group 合成一个物体。每件带倒角 + 加权法线（硬表面
标准做法：大平面平整、棱边有圆角高光）；cut() 布尔开槽。
烘焙：合并 → Smart UV → Cycles 烘焙 7 张（底色 / 粗糙金属 / 磨损色 / 磨损参数 /
棱边遮罩 / AO / 法线(倒角圆角 + 聚合物颗粒/木纹)）→ numpy 合成
（棱边掉漆露底材、凹处积灰、AO 压暗）→ 单材质 + 三张贴图
（albedo / 粗糙金属 G=粗糙 B=金属 / 法线），Godot 读成一个 StandardMaterial3D。
"""
import bpy
import bmesh
import math
import os

import numpy as np
from mathutils import Vector, Matrix

PARTS = []
CUTTERS = []
_MATS = {}

# 材质分区：base 底色（线性）/ rough / metal / wear 磨损露出的底材色 / wr wm 磨损处
# 粗糙与金属 / amt 磨损强度 / kind 决定颗粒法线与底色纹理
ZONES = {
    "steel": dict(base=(0.05, 0.05, 0.054), rough=0.4, metal=0.8, wear=(0.4, 0.4, 0.41),
                  wr=0.28, wm=1.0, amt=0.9, kind="metal"),
    "park": dict(base=(0.075, 0.075, 0.07), rough=0.62, metal=0.55, wear=(0.36, 0.36, 0.36),
                 wr=0.3, wm=1.0, amt=0.75, kind="metal"),
    "alu": dict(base=(0.05, 0.05, 0.055), rough=0.5, metal=0.5, wear=(0.55, 0.55, 0.56),
                wr=0.3, wm=1.0, amt=0.7, kind="metal"),
    "poly": dict(base=(0.04, 0.04, 0.042), rough=0.72, metal=0.0, wear=(0.1, 0.1, 0.1),
                 wr=0.5, wm=0.0, amt=0.6, kind="poly"),
    # FDE / Coyote Tan 实物 ≈ sRGB(0.50,0.42,0.32)（vm 世界饱和 1.18 + 自发光会再提亮）
    "poly_fde": dict(base=(0.2, 0.15, 0.095), rough=0.68, metal=0.0, wear=(0.3, 0.24, 0.16),
                     wr=0.5, wm=0.0, amt=0.5, kind="poly"),
    "cera_fde": dict(base=(0.21, 0.155, 0.095), rough=0.55, metal=0.1, wear=(0.42, 0.42, 0.42),
                     wr=0.3, wm=1.0, amt=0.6, kind="metal"),
    "poly_od": dict(base=(0.066, 0.07, 0.046), rough=0.7, metal=0.0, wear=(0.13, 0.13, 0.1),
                    wr=0.5, wm=0.0, amt=0.5, kind="poly"),
    # 木/胶木按实物 sRGB 换算到线性：胡桃木 ≈ sRGB(0.40,0.24,0.13)、AK 层压红木
    # ≈ sRGB(0.36,0.15,0.08)、梅子色胶木 ≈ sRGB(0.38,0.16,0.09)
    "wood": dict(base=(0.055, 0.028, 0.016), base2=(0.1, 0.055, 0.032), rough=0.45, metal=0.0,
                 wear=(0.24, 0.15, 0.08), wr=0.6, wm=0.0, amt=0.55, kind="wood"),
    "wood_red": dict(base=(0.058, 0.02, 0.011), base2=(0.1, 0.04, 0.022), rough=0.4, metal=0.0,
                     wear=(0.26, 0.11, 0.05), wr=0.6, wm=0.0, amt=0.55, kind="wood"),
    "bakelite": dict(base=(0.07, 0.02, 0.012), rough=0.36, metal=0.0, wear=(0.15, 0.06, 0.035),
                     wr=0.3, wm=0.0, amt=0.4, kind="smooth"),
    "rubber": dict(base=(0.028, 0.028, 0.028), rough=0.92, metal=0.0, wear=(0.06, 0.06, 0.06),
                   wr=0.8, wm=0.0, amt=0.3, kind="poly"),
    "bore": dict(base=(0.01, 0.01, 0.01), rough=0.6, metal=0.6, wear=(0.01, 0.01, 0.01),
                 wr=0.6, wm=0.6, amt=0.0, kind="smooth"),
    "lens": dict(base=(0.018, 0.02, 0.028), rough=0.08, metal=0.85, wear=(0.018, 0.02, 0.028),
                 wr=0.08, wm=0.85, amt=0.0, kind="smooth"),
    "brass": dict(base=(0.55, 0.38, 0.14), rough=0.3, metal=1.0, wear=(0.75, 0.6, 0.35),
                  wr=0.2, wm=1.0, amt=0.3, kind="smooth"),
}


# 竖纹木（握把/竖握把等竖向件：木纹沿 y）
ZONES["wood_v"] = dict(ZONES["wood"], grain="Z")
ZONES["wood_red_v"] = dict(ZONES["wood_red"], grain="Z")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PARTS.clear()
    CUTTERS.clear()
    _MATS.clear()


def B(x, y, z):
    """枪身局部 → Blender"""
    return Vector((x, -z, y))


def _mat(zone):
    if zone not in _MATS:
        m = bpy.data.materials.new(zone)
        m.use_nodes = True
        z = ZONES[zone]
        m.diffuse_color = (*z["base"], 1.0)
        _MATS[zone] = m
    return _MATS[zone]


# ---------------- 2D 轮廓工具 ----------------

def rounded(pts, r=0.0, segs=4):
    """闭合多边形圆角：pts 为 (a, b) 或 (a, b, 半径)；半径缺省用 r"""
    n = len(pts)
    out = []
    for i in range(n):
        p = pts[i]
        rr = p[2] if len(p) > 2 else r
        a = Vector((p[0], p[1]))
        if rr <= 0:
            out.append(a)
            continue
        prv = Vector(pts[i - 1][:2])
        nxt = Vector(pts[(i + 1) % n][:2])
        d1 = prv - a
        d2 = nxt - a
        if d1.length < 1e-9 or d2.length < 1e-9:
            out.append(a)
            continue
        ang = d1.angle(d2)
        if ang < 1e-3 or ang > math.pi - 1e-3:
            out.append(a)
            continue
        t = min(rr / math.tan(ang * 0.5), d1.length * 0.49, d2.length * 0.49)
        p1 = a + d1.normalized() * t
        p2 = a + d2.normalized() * t
        for k in range(segs + 1):
            s = k / segs
            out.append((1 - s) ** 2 * p1 + 2 * (1 - s) * s * a + s * s * p2)
    return [(v[0], v[1]) for v in out]


def arc(cx, cy, r, a0, a1, n=8):
    """圆弧点列（角度制，逆时针 a0→a1）"""
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


# ---------------- bmesh 构件（写入给定 bm） ----------------

def _extrude_poly(bm, pts3, vec):
    vs = [bm.verts.new(p) for p in pts3]
    f = bm.faces.new(vs)
    ret = bmesh.ops.extrude_face_region(bm, geom=[f])
    vv = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=vec, verts=vv)


def side_bm(bm, pts, x0, x1, r=0.0):
    """侧视轮廓 pts[(z, y)] 沿 x 从 x0 挤到 x1"""
    p2 = rounded(pts, r)
    _extrude_poly(bm, [B(x0, p[1], p[0]) for p in p2], Vector((x1 - x0, 0, 0)))


def xsec_bm(bm, pts, z0, z1, r=0.0):
    """截面 pts[(x, y)] 沿 z 从 z0 挤到 z1"""
    p2 = rounded(pts, r)
    _extrude_poly(bm, [B(p[0], p[1], z0) for p in p2], B(0, 0, z1 - z0))


def top_bm(bm, pts, y0, y1, r=0.0):
    """俯视轮廓 pts[(x, z)] 沿 y 从 y0 挤到 y1"""
    p2 = rounded(pts, r)
    _extrude_poly(bm, [B(p[0], y0, p[1]) for p in p2], Vector((0, 0, y1 - y0)))


def box_bm(bm, c, s):
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]
    bmesh.ops.scale(bm, vec=Vector((s[0], s[2], s[1])), verts=vs)
    bmesh.ops.translate(bm, vec=B(*c), verts=vs)


def lathe_bm(bm, prof, cx=0.0, cy=0.0, segs=32, axis="z"):
    """车削：prof[(沿轴坐标, 半径)]，绕过 (cx, cy) 的轴（默认枪管 z 轴）。
    半径 0 的点收成顶点（锥尖/端面中心）"""
    rings = []
    for t, rad in prof:
        if rad < 1e-6:
            if axis == "z":
                rings.append([bm.verts.new(B(cx, cy, t))])
            elif axis == "x":
                rings.append([bm.verts.new(B(t, cx, cy))])
            else:
                rings.append([bm.verts.new(B(cx, t, cy))])
            continue
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            u, v = rad * math.cos(a), rad * math.sin(a)
            if axis == "z":
                ring.append(bm.verts.new(B(cx + u, cy + v, t)))
            elif axis == "x":       # 轴沿 x：截面在 (y, z)
                ring.append(bm.verts.new(B(t, cx + u, cy + v)))
            else:                   # 轴沿 y：截面在 (x, z)
                ring.append(bm.verts.new(B(cx + u, t, cy + v)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for j in range(segs):
            j2 = (j + 1) % segs
            try:
                if len(r0) == 1 and len(r1) == 1:
                    continue
                if len(r0) == 1:
                    bm.faces.new((r0[0], r1[j2], r1[j]))
                elif len(r1) == 1:
                    bm.faces.new((r0[j], r0[j2], r1[0]))
                else:
                    bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))
            except ValueError:
                pass
    if len(rings[0]) > 1 and prof[0][1] > 1e-6:
        bm.faces.new(rings[0][::-1])
    if len(rings[-1]) > 1 and prof[-1][1] > 1e-6:
        bm.faces.new(rings[-1])


def cyl_bm(bm, c, r, length, axis="x", segs=16):
    h = length * 0.5
    if axis == "x":
        lathe_bm(bm, [(c[0] - h, r), (c[0] + h, r)], cx=c[1], cy=c[2], segs=segs, axis="x")
    elif axis == "y":
        lathe_bm(bm, [(c[1] - h, r), (c[1] + h, r)], cx=c[0], cy=c[2], segs=segs, axis="y")
    else:
        lathe_bm(bm, [(c[2] - h, r), (c[2] + h, r)], cx=c[0], cy=c[1], segs=segs, axis="z")


# ---------------- 物体 ----------------

def _sharpen(bm, deg=32.0):
    lim = math.radians(deg)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) < lim
        else:
            e.smooth = False


def obj(name, bm, zone, bevel=0.0012, segs=2, angle=32.0, cutter=False):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _sharpen(bm, angle)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if cutter:
        ob.hide_render = True
        ob.display_type = "WIRE"
        CUTTERS.append(ob)
        return ob
    ob.data.materials.append(_mat(zone))
    for p in me.polygons:
        p.use_smooth = True
    if bevel > 0:
        md = ob.modifiers.new("bev", "BEVEL")
        md.width = bevel
        md.segments = segs
        md.limit_method = "ANGLE"
        md.angle_limit = math.radians(angle)
        md.miter_outer = "MITER_ARC"
    wn = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    wn.weight = 50
    PARTS.append(ob)
    return ob


def side(name, pts, x0, x1, zone, r=0.0, **kw):
    bm = bmesh.new()
    side_bm(bm, pts, x0, x1, r)
    return obj(name, bm, zone, **kw)


def xsec(name, pts, z0, z1, zone, r=0.0, **kw):
    bm = bmesh.new()
    xsec_bm(bm, pts, z0, z1, r)
    return obj(name, bm, zone, **kw)


def top(name, pts, y0, y1, zone, r=0.0, **kw):
    bm = bmesh.new()
    top_bm(bm, pts, y0, y1, r)
    return obj(name, bm, zone, **kw)


def box(name, c, s, zone, **kw):
    bm = bmesh.new()
    box_bm(bm, c, s)
    return obj(name, bm, zone, **kw)


def lathe(name, prof, zone, cx=0.0, cy=0.0, segs=32, axis="z", **kw):
    bm = bmesh.new()
    lathe_bm(bm, prof, cx, cy, segs, axis)
    kw.setdefault("bevel", 0.0006)
    return obj(name, bm, zone, **kw)


def cyl(name, c, r, length, zone, axis="x", segs=16, **kw):
    bm = bmesh.new()
    cyl_bm(bm, c, r, length, axis, segs)
    kw.setdefault("bevel", 0.0004)
    return obj(name, bm, zone, **kw)


class Group:
    """同材质小件合成一个物体：g = Group(); g.box(...); g.cyl(...); g.done("name", "steel")"""

    def __init__(self):
        self.bm = bmesh.new()

    def side(self, pts, x0, x1, r=0.0):
        side_bm(self.bm, pts, x0, x1, r)
        return self

    def xsec(self, pts, z0, z1, r=0.0):
        xsec_bm(self.bm, pts, z0, z1, r)
        return self

    def top(self, pts, y0, y1, r=0.0):
        top_bm(self.bm, pts, y0, y1, r)
        return self

    def box(self, c, s):
        box_bm(self.bm, c, s)
        return self

    def lathe(self, prof, cx=0.0, cy=0.0, segs=32, axis="z"):
        lathe_bm(self.bm, prof, cx, cy, segs, axis)
        return self

    def cyl(self, c, r, length, axis="x", segs=16):
        cyl_bm(self.bm, c, r, length, axis, segs)
        return self

    def done(self, name, zone, **kw):
        return obj(name, self.bm, zone, **kw)


def deform(ob, fn):
    """按枪身局部坐标逐顶点变形：fn(x, y, z) -> (x, y, z)（锥度/弯曲用）"""
    for v in ob.data.vertices:
        nx, ny, nz = fn(v.co.x, v.co.z, -v.co.y)
        v.co = B(nx, ny, nz)
    ob.data.update()
    return ob


def taper_x(ob, z0, z1, s0, s1, xc=0.0):
    """沿 z 线性改宽度：z0 处 x 缩放 s0、z1 处 s1（两端外钳住）"""
    def f(x, y, z):
        t = min(1.0, max(0.0, (z - z0) / (z1 - z0))) if z1 != z0 else 0.0
        return (xc + (x - xc) * (s0 + (s1 - s0) * t), y, z)
    return deform(ob, f)


def cut(target, cutter):
    """布尔差集（EXACT），排在倒角之前：开孔边也会被倒角"""
    md = target.modifiers.new("cut_" + cutter.name, "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.solver = "EXACT"
    md.object = cutter
    target.modifiers.move(len(target.modifiers) - 1, 0)


def cutter_box(name, c, s, r=0.0):
    bm = bmesh.new()
    if r > 0:
        hx, hy, hz = s[0] * 0.5, s[1] * 0.5, s[2] * 0.5
        side_bm(bm, [(c[2] - hz, c[1] - hy, r), (c[2] + hz, c[1] - hy, r), (c[2] + hz, c[1] + hy, r),
                     (c[2] - hz, c[1] + hy, r)], c[0] - hx, c[0] + hx)
    else:
        box_bm(bm, c, s)
    return obj(name, bm, None, cutter=True)


def cutter_cyl(name, c, r, length, axis="x", segs=16):
    bm = bmesh.new()
    cyl_bm(bm, c, r, length, axis, segs)
    return obj(name, bm, None, cutter=True)


# ---------------- 常用组件 ----------------

def picatinny(name, z0, z1, y, zone="alu", x=0.0):
    """皮卡汀尼导轨：底座（y..y+0.0035）+ 燕尾齿（10mm 节距、齿长 4.8mm、齿顶 y+0.0065）"""
    g = Group()
    g.xsec([(x - 0.0078, y), (x + 0.0078, y), (x + 0.0078, y + 0.0035), (x - 0.0078, y + 0.0035)], z0, z1)
    tooth = [(x - 0.0078, y + 0.0025), (x + 0.0078, y + 0.0025), (x + 0.0106, y + 0.0045),
             (x + 0.0106, y + 0.0057), (x + 0.0095, y + 0.0066), (x - 0.0095, y + 0.0066),
             (x - 0.0106, y + 0.0057), (x - 0.0106, y + 0.0045)]
    n = int((z1 - z0 - 0.002) / 0.01)
    off = (z1 - z0 - n * 0.01) * 0.5
    for k in range(n):
        za = z0 + off + k * 0.01 + 0.0026
        g.xsec(tooth, za, za + 0.0048)
    return g.done(name, zone, bevel=0.0004)


def screw_heads(name, pts, r, depth, zone="steel", axis="x"):
    """一组圆螺钉头/铆钉头（pts 为中心，沿 axis 方向凸出 depth）"""
    g = Group()
    for p in pts:
        g.cyl(p, r, depth, axis=axis, segs=12)
    return g.done(name, zone, bevel=0.0003)


# ---------------- 烘焙 ----------------

def _new_img(name, size, data=True, float_buf=True):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    return bpy.data.images.new(name, size, size, alpha=False, float_buffer=float_buf, is_data=data)


def _tree_reset(m):
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    return nt, out


def _noise(nt, scale, detail=3.0, lo=0.0, hi=1.0, coord=None):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    if coord is not None:
        nt.links.new(coord, n.inputs["Vector"])
    if lo == 0.0 and hi == 1.0:
        return n.outputs["Fac"]
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.3
    mr.inputs["From Max"].default_value = 0.7
    mr.inputs["To Min"].default_value = lo
    mr.inputs["To Max"].default_value = hi
    nt.links.new(n.outputs["Fac"], mr.inputs["Value"])
    return mr.outputs["Result"]


def _obj_coord(nt):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    return tc.outputs["Object"]


def _mul_col(nt, col_socket_or_val, fac_socket):
    mx = nt.nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs["Factor"].default_value = 1.0
    a_in = next(i for i in mx.inputs if i.identifier == "A_Color")
    b_in = next(i for i in mx.inputs if i.identifier == "B_Color")
    if isinstance(col_socket_or_val, tuple):
        a_in.default_value = (*col_socket_or_val, 1.0)
    else:
        nt.links.new(col_socket_or_val, a_in)
    nt.links.new(fac_socket, b_in)
    return next(o for o in mx.outputs if o.identifier == "Result_Color")


def _wood_color(nt, z):
    co = _obj_coord(nt)
    mp = nt.nodes.new("ShaderNodeMapping")
    vert = z.get("grain", "Y") == "Z"
    mp.inputs["Scale"].default_value = (1.0, 1.0, 0.06) if vert else (1.0, 0.06, 1.0)
    nt.links.new(co, mp.inputs["Vector"])
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = "RINGS"
    wv.rings_direction = "Z" if vert else "Y"
    wv.inputs["Scale"].default_value = 70.0
    wv.inputs["Distortion"].default_value = 9.0
    wv.inputs["Detail"].default_value = 4.0
    wv.inputs["Detail Scale"].default_value = 1.5
    nt.links.new(mp.outputs["Vector"], wv.inputs["Vector"])
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].position = 0.2
    cr.color_ramp.elements[0].color = (*z["base"], 1.0)
    cr.color_ramp.elements[1].position = 1.0
    cr.color_ramp.elements[1].color = (*z["base2"], 1.0)
    nt.links.new(wv.outputs["Fac"], cr.inputs["Fac"])
    return cr.outputs["Color"]


def _pass_tree(m, zone, pas, img):
    """按烘焙通道重建材质节点：EMIT 类通道把要的量接 Emission；nor 通道接带
    Bevel+Bump 法线的 BSDF"""
    z = ZONES[zone]
    nt, out = _tree_reset(m)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    tex.select = True
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    co = _obj_coord(nt)
    if pas == "base":
        if z["kind"] == "wood":
            col = _wood_color(nt, z)
        else:
            col = (z["base"])
        if z["kind"] == "wood":
            mott = _noise(nt, 9.0, 5.0, 0.78, 1.2, co)
        elif z["kind"] == "poly" or max(z["base"]) > 0.12:   # 浅色涂层斑驳收敛
            mott = _noise(nt, 55.0, 4.0, 0.93, 1.07, co)
        else:
            mott = _noise(nt, 55.0, 4.0, 0.85, 1.15, co)
        nt.links.new(_mul_col(nt, col, mott), em.inputs["Color"])
    elif pas == "rm":
        cc = nt.nodes.new("ShaderNodeCombineColor")
        rn = _noise(nt, 30.0, 3.0, z["rough"] * 0.88, min(1.0, z["rough"] * 1.12), co)
        nt.links.new(rn, cc.inputs[0])
        cc.inputs[1].default_value = z["metal"]
        cc.inputs[2].default_value = 0.0
        nt.links.new(cc.outputs["Color"], em.inputs["Color"])
    elif pas == "wear":
        em.inputs["Color"].default_value = (*z["wear"], 1.0)
    elif pas == "wpar":
        cc = nt.nodes.new("ShaderNodeCombineColor")
        cc.inputs[0].default_value = z["wr"]
        cc.inputs[1].default_value = z["wm"]
        amt = _noise(nt, 14.0, 4.0, 0.25 * z["amt"], 1.15 * z["amt"], co)
        nt.links.new(amt, cc.inputs[2])
        nt.links.new(cc.outputs["Color"], em.inputs["Color"])
    elif pas == "edge":
        bv = nt.nodes.new("ShaderNodeBevel")
        bv.samples = 8
        bv.inputs["Radius"].default_value = 0.0016
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        dp = nt.nodes.new("ShaderNodeVectorMath")
        dp.operation = "DOT_PRODUCT"
        nt.links.new(bv.outputs["Normal"], dp.inputs[0])
        nt.links.new(geo.outputs["Normal"], dp.inputs[1])
        m1 = nt.nodes.new("ShaderNodeMath")
        m1.operation = "SUBTRACT"
        m1.inputs[0].default_value = 1.0
        nt.links.new(dp.outputs["Value"], m1.inputs[1])
        m2 = nt.nodes.new("ShaderNodeMath")
        m2.operation = "MULTIPLY"
        m2.use_clamp = True
        m2.inputs[1].default_value = 9.0
        nt.links.new(m1.outputs["Value"], m2.inputs[0])
        nt.links.new(m2.outputs["Value"], em.inputs["Color"])
    elif pas == "nor":
        nt.nodes.remove(em)
        bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
        bump = nt.nodes.new("ShaderNodeBump")
        kind = z["kind"]
        if kind == "poly":
            h = _noise(nt, 900.0, 2.0, coord=co)
            bump.inputs["Strength"].default_value = 0.22
        elif kind == "metal":
            h = _noise(nt, 700.0, 2.0, coord=co)
            bump.inputs["Strength"].default_value = 0.05
        elif kind == "wood":
            mp = nt.nodes.new("ShaderNodeMapping")
            vert = z.get("grain", "Y") == "Z"
            mp.inputs["Scale"].default_value = (1.0, 1.0, 0.06) if vert else (1.0, 0.06, 1.0)
            nt.links.new(co, mp.inputs["Vector"])
            wv = nt.nodes.new("ShaderNodeTexWave")
            wv.wave_type = "RINGS"
            wv.rings_direction = "Z" if vert else "Y"
            wv.inputs["Scale"].default_value = 70.0
            wv.inputs["Distortion"].default_value = 9.0
            wv.inputs["Detail"].default_value = 4.0
            wv.inputs["Detail Scale"].default_value = 1.5
            nt.links.new(mp.outputs["Vector"], wv.inputs["Vector"])
            h = wv.outputs["Fac"]
            bump.inputs["Strength"].default_value = 0.04
        else:
            h = _noise(nt, 300.0, 1.0, coord=co)
            bump.inputs["Strength"].default_value = 0.01
        bump.inputs["Distance"].default_value = 0.0004
        nt.links.new(h, bump.inputs["Height"])
        bv = nt.nodes.new("ShaderNodeBevel")
        bv.samples = 8
        bv.inputs["Radius"].default_value = 0.0007
        nt.links.new(bump.outputs["Normal"], bv.inputs["Normal"])
        nt.links.new(bv.outputs["Normal"], bs.inputs["Normal"])


def _bake(gun, pas, img, btype, samples):
    for zone, m in _MATS.items():
        _pass_tree(m, zone, pas, img)
    sc = bpy.context.scene
    sc.cycles.samples = samples
    kw = dict(type=btype, margin=8, use_clear=True)
    if btype == "NORMAL":
        kw.update(normal_space="TANGENT")
    bpy.ops.object.bake(**kw)


def _px(img):
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)[..., :3].copy()


def _to_srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def _pack(name, rgb, data, save_dir=""):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False, is_data=data)
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((h, w, 1), dtype=np.float32)], axis=2)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    if save_dir:   # 检查用 PNG 副本（存储值原样写出）
        os.makedirs(save_dir, exist_ok=True)
        img.filepath_raw = os.path.join(save_dir, name + ".png")
        img.file_format = "PNG"
        img.save()
    img.file_format = "JPEG"
    img.pack()
    return img


def _setup_cycles():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception as e:  # noqa: BLE001
        print("[gun] GPU 不可用，用 CPU：", e)
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 8
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.light_settings.distance = 0.035


def finish(name, out_path, ref, target, length=None, size=2048, preview_dir="", tex_dir=""):
    """合并 → UV → 烘焙 → 合成 → 等比缩放平移（真枪 ref 点 → 游戏 target 点；
    length 给定时按整枪 z 向长度缩放到该值）→ 导出 GLB"""
    sc = bpy.context.scene
    quick = os.environ.get("QUICK", "") != ""
    size = int(os.environ.get("BAKE_SIZE", size))
    for o in CUTTERS:
        o.hide_set(True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in PARTS:
        o.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    gun = bpy.context.view_layer.objects.active
    gun.name = name
    for o in list(CUTTERS):
        bpy.data.objects.remove(o, do_unlink=True)
    CUTTERS.clear()
    me = gun.data
    tri = gun.modifiers.new("tri", "TRIANGULATE")   # 只拆 >4 边面：切线（MikkTSpace）要三/四边形
    tri.min_vertices = 5
    bpy.ops.object.modifier_apply(modifier="tri")
    if quick:   # 只看外形：工作台按分区色出图，不烘焙不导出
        _preview_quick(gun, preview_dir, name)
        return gun, 1.0
    # 烘焙在真实米数下做（AO 距离/倒角半径按真实尺寸），缩放平移放到最后
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(72), island_margin=0.003,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    _setup_cycles()
    imgs = {k: _new_img("bk_" + k, size) for k in ("base", "rm", "wear", "wpar", "edge", "ao", "nor")}
    gun.select_set(True)
    bpy.context.view_layer.objects.active = gun
    _bake(gun, "base", imgs["base"], "EMIT", 1)
    _bake(gun, "rm", imgs["rm"], "EMIT", 1)
    _bake(gun, "wear", imgs["wear"], "EMIT", 1)
    _bake(gun, "wpar", imgs["wpar"], "EMIT", 1)
    _bake(gun, "edge", imgs["edge"], "EMIT", 24)
    _bake(gun, "ao", imgs["ao"], "AO", 48)
    _bake(gun, "nor", imgs["nor"], "NORMAL", 24)
    base = _px(imgs["base"])
    rm = _px(imgs["rm"])
    wear = _px(imgs["wear"])
    wpar = _px(imgs["wpar"])
    edge = _px(imgs["edge"])[..., 0]
    ao = np.clip(_px(imgs["ao"])[..., 0], 0, 1)
    nor = _px(imgs["nor"])
    # 合成：凸棱（AO 高处的棱）掉漆露底材；凹角（AO 低）积灰
    convex = np.clip((ao - 0.55) / 0.3, 0, 1)
    e = np.clip(edge * convex * wpar[..., 2] * 1.4, 0, 1)[..., None]
    cav = np.clip((0.78 - ao) / 0.5, 0, 1)[..., None]
    alb = base * (0.42 + 0.58 * ao[..., None])
    alb = alb * (1 - e) + wear * e
    dirt = np.array([0.045, 0.04, 0.032], dtype=np.float32)
    alb = alb * (1 - cav * 0.45) + dirt * cav * 0.45
    rough = rm[..., 0] * (1 - e[..., 0]) + wpar[..., 0] * e[..., 0] + cav[..., 0] * 0.12
    metal = rm[..., 1] * (1 - e[..., 0]) + wpar[..., 1] * e[..., 0]
    orm = np.stack([ao, np.clip(rough, 0.05, 1.0), np.clip(metal, 0, 1)], axis=2)
    t_alb = _pack(name + "_albedo", _to_srgb(alb), False, tex_dir)
    t_orm = _pack(name + "_orm", orm, True, tex_dir)
    t_nor = _pack(name + "_normal", nor, True, tex_dir)
    # 最终材质：单材质三贴图
    fm = bpy.data.materials.new(name)
    fm.use_nodes = True
    nt = fm.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    ta = nt.nodes.new("ShaderNodeTexImage")
    ta.image = t_alb
    nt.links.new(ta.outputs["Color"], bs.inputs["Base Color"])
    to = nt.nodes.new("ShaderNodeTexImage")
    to.image = t_orm
    sp = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sp.inputs["Color"])
    nt.links.new(sp.outputs["Green"], bs.inputs["Roughness"])
    nt.links.new(sp.outputs["Blue"], bs.inputs["Metallic"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = t_nor
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    me.materials.clear()
    me.materials.append(fm)
    for p in me.polygons:
        p.material_index = 0
    # 缩放 + 平移到游戏枪身局部
    zs = [v.co.y for v in me.vertices]
    real_len = max(zs) - min(zs)
    k = (length / real_len) if length else 1.0
    M = Matrix.Translation(B(*target)) @ Matrix.Scale(k, 4) @ Matrix.Translation(-B(*ref))
    me.transform(M)
    me.update()
    bpy.ops.object.select_all(action="DESELECT")
    gun.select_set(True)
    bpy.context.view_layer.objects.active = gun
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True,
                              export_yup=True, export_animations=False, export_tangents=True,
                              export_image_format="JPEG", export_jpeg_quality=92,
                              export_materials="EXPORT")
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zz = [v.co.z for v in me.vertices]
    # Blender → 枪身局部：x=x, y=z, z=-y
    print("[gun] %s k=%.4f verts=%d tris=%d aabb_x=[%.4f,%.4f] y=[%.4f,%.4f] z=[%.4f,%.4f] -> %s" % (
        name, k, len(me.vertices), sum(len(p.vertices) - 2 for p in me.polygons),
        min(xs), max(xs), min(zz), max(zz), -max(ys), -min(ys), out_path))
    if preview_dir:
        _preview(gun, preview_dir, name)
    return gun, k


def _preview(gun, d, name):
    """EEVEE 实拍天空预览：右侧视 + 右前上 3/4 + 左后 3/4"""
    os.makedirs(d, exist_ok=True)
    sc = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    w = bpy.data.worlds.new("pv")
    w.use_nodes = True
    nt = w.node_tree
    hdr = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "pbr", "hdri",
                       "kloofendal_43d_clear_puresky_2k.hdr")
    bg = nt.nodes["Background"]
    if os.path.exists(hdr):
        et = nt.nodes.new("ShaderNodeTexEnvironment")
        et.image = bpy.data.images.load(hdr)
        nt.links.new(et.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    sc.world = w
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 800
    bb = [Vector(v) for v in gun.bound_box]
    c = sum(bb, Vector()) / 8.0
    L = max((bb[6] - bb[0]).length, 0.2)
    cam = bpy.data.objects.new("pvcam", bpy.data.cameras.new("pvcam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    for tag, off in (("side", Vector((L * 2.2, 0, 0))), ("34", Vector((L * 1.5, -L * 1.2, L * 0.7))),
                     ("back", Vector((-L * 1.4, L * 1.3, L * 0.6)))):
        cam.location = c + off
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(d, "%s_%s.png" % (name, tag))
        bpy.ops.render.render(write_still=True)


def _preview_quick(gun, d, name):
    os.makedirs(d, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_cavity = True
    sc.display.shading.cavity_type = "BOTH"
    sc.display.shading.show_shadows = False
    sc.render.resolution_x, sc.render.resolution_y = 1800, 800
    bb = [Vector(v) for v in gun.bound_box]
    c = sum(bb, Vector()) / 8.0
    L = max((bb[6] - bb[0]).length, 0.2)
    cam = bpy.data.objects.new("qcam", bpy.data.cameras.new("qcam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for tag, off, ortho in (("qside", Vector((L * 2.0, 0, 0)), True), ("q34", Vector((L * 1.3, -L * 1.0, L * 0.6)), False),
                            ("qtop", Vector((0.0001, 0, L * 2.0)), True), ("qleft", Vector((-L * 1.3, L * 0.6, L * 0.35)), False)):
        cam.data.type = "ORTHO" if ortho else "PERSP"
        cam.data.ortho_scale = L * 1.05
        cam.data.lens = 50
        cam.location = c + off
        up = "Y" if tag != "qtop" else "Z"
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        if tag == "qtop":
            cam.rotation_euler = (0.0, 0.0, math.pi * 0.5)
        sc.render.filepath = os.path.join(d, "%s_%s.png" % (name, tag))
        bpy.ops.render.render(write_still=True)
