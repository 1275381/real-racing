# -*- coding: utf-8 -*-
"""赛车程序化建模共享库（Blender 4/5.x，无头运行）

坐标约定: Z 向上，车头朝 -Y，原点在车底中心；导出 glTF 时转 Y-up / +Z 朝前（游戏坐标）。

命名契约（js/car.js 依赖，勿改）:
    空物体 HubFL/FR/RL/RR -> 转向枢轴；子物体 WheelXX -> 滚动自转；CaliperXX 不随轮转
    空物体 BodyPivot      -> 车身姿态容器（侧倾/俯仰/悬架起伏）
    材质 Paint(车队染色) / Accent(副色) / TailLight(刹车灯) / HeadLight / GlassDark / Carbon ...

建模思路（相较旧版的真实度提升）:
    1. 车身是一张连续曲面：截面参数沿 Y 做 Catmull-Rom 插值，座舱由同一张皮"长"出来，
       不再是一个扣在车顶上的独立罩子；
    2. 车窗/进气格栅是在这张皮上"开洞"（面遮罩），玻璃与格栅是同一网格向内偏移的内衬，
       洞口边缘天然形成 A/B/C 柱与包边；
    3. 轮胎/轮辋/刹车盘/卡钳全部由二维断面绕轴放样，有胎肩圆角、胎壁鼓包、轮辋唇口与桶身，
       辐条真实连接轮毂与桶身。
"""
import bpy
import bmesh
import json
import math
import os
import struct
import sys
from math import pi, cos, sin
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- 常量
HUB_X = 0.84          # 轮距半宽（枢轴 X），四款车统一
AXLE_F = -1.46        # 前轴 Y
AXLE_R = 1.44         # 后轴 Y
TIRE_R = 0.34         # 轮胎半径 —— game.js 用 (vf / 0.34) 算轮速，不可改
HUB_Z = TIRE_R        # 轮心高 = 半径，车轮正好落地

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, 'assets')

# 截面采样：右半侧 7 个控制点 + 每段采样数（详见 ring_of()）
SEG_N = (2, 3, 6, 5, 6, 6)
HALF_N = sum(SEG_N) + 1          # = 29，右半侧点数（含首尾）
RING_N = HALF_N * 2 - 2          # = 56，整圈点数
IDX_CROWN = HALF_N - 1           # 28 顶点中心
IDX_ROOF = 2 + 3 + 6 + 5 + 6     # 22 车顶外沿（d=6）
IDX_BELT = 2 + 3 + 6 + 5         # 16 腰线（d=12）
D_ROOF = IDX_CROWN - IDX_ROOF    # 6
D_BELT = IDX_CROWN - IDX_BELT    # 12


def d_of(i):
    """环索引 -> 距车顶中心的"环向距离"，0=车顶中心，12=腰线，28=车底中心。"""
    return abs(IDX_CROWN - i) if i <= IDX_CROWN else i - IDX_CROWN


# ---------------------------------------------------------------- 场景 / 材质
def reset_scene():
    """每款车一次彻底重置：避免材质/物体重名成 Paint.001 导致游戏端染色失效。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def principled(name, color, metallic=0.0, rough=0.5, coat=0.0, coat_rough=0.05,
               emis=None, emis_str=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    assert m.name == name, '材质重名: %s（场景没重置干净）' % m.name
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')

    def put(keys, val):
        for k in keys:
            try:
                bsdf.inputs[k].default_value = val
                return
            except Exception:
                pass

    put(['Base Color'], (*color, 1.0))
    put(['Metallic'], metallic)
    put(['Roughness'], rough)
    put(['Coat Weight', 'Clearcoat'], coat)
    put(['Coat Roughness', 'Clearcoat Roughness'], coat_rough)
    if emis:
        put(['Emission Color', 'Emission'], (*emis, 1.0))
        put(['Emission Strength'], emis_str)
    if alpha < 1.0:
        put(['Alpha'], alpha)
        m.blend_method = 'BLEND'
    return m


def build_materials(paint_rough=0.26):
    """统一材质库。Paint 低金属度 + 满清漆 —— 运行时车队染色才不会被金属反射吃掉。"""
    return {
        'Paint':     principled('Paint', (0.85, 0.86, 0.88), metallic=0.15, rough=paint_rough, coat=1.0, coat_rough=0.03),
        'Accent':    principled('Accent', (0.10, 0.11, 0.13), metallic=0.10, rough=0.30, coat=0.9),
        'GlassDark': principled('GlassDark', (0.014, 0.019, 0.026), metallic=0.10, rough=0.05, coat=0.8),
        'Carbon':    principled('Carbon', (0.021, 0.022, 0.026), metallic=0.30, rough=0.36),
        'CarbonMat': principled('CarbonMat', (0.030, 0.031, 0.034), metallic=0.10, rough=0.62),
        'Rubber':    principled('Rubber', (0.020, 0.020, 0.022), metallic=0.0, rough=0.92),
        'RimAlloy':  principled('RimAlloy', (0.62, 0.64, 0.68), metallic=1.0, rough=0.22),
        'RimGold':   principled('RimGold', (0.70, 0.52, 0.16), metallic=1.0, rough=0.30),
        'RimDark':   principled('RimDark', (0.075, 0.078, 0.085), metallic=1.0, rough=0.34),
        'Steel':     principled('Steel', (0.38, 0.39, 0.42), metallic=1.0, rough=0.38),
        'Chrome':    principled('Chrome', (0.86, 0.87, 0.89), metallic=1.0, rough=0.13),
        'Caliper':   principled('Caliper', (0.72, 0.26, 0.03), metallic=0.4, rough=0.34),
        'Mesh':      principled('Mesh', (0.028, 0.028, 0.030), metallic=0.65, rough=0.52),
        'Interior':  principled('Interior', (0.055, 0.057, 0.062), metallic=0.0, rough=0.80),
        'Cage':      principled('Cage', (0.72, 0.16, 0.12), metallic=0.55, rough=0.40),
        'Skin':      principled('Skin', (0.34, 0.24, 0.20), metallic=0.0, rough=0.72),
        'TailLight': principled('TailLight', (0.16, 0.010, 0.010), rough=0.20, emis=(1.0, 0.06, 0.04), emis_str=1.5),
        'HeadLight': principled('HeadLight', (0.72, 0.74, 0.78), metallic=0.3, rough=0.08, emis=(1.0, 0.96, 0.86), emis_str=1.6),
    }


M = {}   # 由 begin_car() 填充


# ---------------------------------------------------------------- 网格工具
def new_obj(name, verts, faces, mat, smooth=True, flat=()):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    flat = set(flat)
    for i, p in enumerate(mesh.polygons):
        p.use_smooth = smooth and i not in flat
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if mat is not None:
        obj.data.materials.append(M[mat] if isinstance(mat, str) else mat)
    return obj


def clean_mesh(obj, recalc=False, weld=1e-5):
    """删除孤立点 / 焊接重合点 / 可选重算法线朝外。"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    if weld:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def loft(name, stations, mat, close_ring=True, close_spine=False,
         cap_start=False, cap_end=False, keep=None, smooth=True, flip=False):
    """把一串等长点环放样成曲面。

    stations : [[Vector]*n] —— 沿脊线的截面
    keep     : (s, i) -> bool，返回 False 的格子不生成面（用于开窗/开口）
    cap_*    : 用质心扇形封口（平直着色）
    """
    n = len(stations[0])
    verts, faces, flat = [], [], []
    for st in stations:
        verts.extend(st)
    ns = len(stations)
    span = ns if close_spine else ns - 1
    for s in range(span):
        a, b = s * n, ((s + 1) % ns) * n
        for i in range(n if close_ring else n - 1):
            j = (i + 1) % n
            if keep is not None and not keep(s, i):
                continue
            f = (a + i, b + i, b + j, a + j)
            faces.append(f[::-1] if flip else f)
    for which, st, base in (('s', stations[0], 0), ('e', stations[-1], (ns - 1) * n)):
        if (which == 's' and not cap_start) or (which == 'e' and not cap_end):
            continue
        c = len(verts)
        verts.append(Vector((sum(v.x for v in st) / n, sum(v.y for v in st) / n, sum(v.z for v in st) / n)))
        for i in range(n):
            j = (i + 1) % n
            flat.append(len(faces))
            f = (c, base + j, base + i) if which == 's' else (c, base + i, base + j)
            faces.append(f[::-1] if flip else f)
    obj = new_obj(name, verts, faces, mat, smooth=smooth, flat=flat)
    return clean_mesh(obj, recalc=(cap_start and cap_end and keep is None))


def revolve(name, profile, mat, seg=32, center=(0, 0, 0), axis='X', smooth=True):
    """二维闭合断面绕轴旋成回转体。profile: [(轴向, 半径)]，轴向沿 axis。"""
    stations = []
    for k in range(seg):
        a = 2 * pi * k / seg
        ring = []
        for (ax, r) in profile:
            u, v = r * cos(a), r * sin(a)
            if axis == 'X':
                p = Vector((ax, u, v))
            elif axis == 'Y':
                p = Vector((v, ax, u))
            else:
                p = Vector((u, v, ax))
            ring.append(p + Vector(center))
        stations.append(ring)
    obj = loft(name, stations, mat, close_ring=True, close_spine=True, smooth=smooth)
    return clean_mesh(obj, recalc=True)


def tube(name, path, radius, mat, seg=10, closed=False, taper=None):
    """沿折线扫掠圆管（防滚架 / 悬架推杆 / 排气）。path: [Vector]"""
    pts = [Vector(p) for p in path]
    stations = []
    for k, p in enumerate(pts):
        if k == 0:
            t = (pts[1] - pts[0])
        elif k == len(pts) - 1:
            t = (pts[-1] - pts[-2])
        else:
            t = (pts[k + 1] - pts[k - 1])
        t.normalize()
        up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        u = t.cross(up).normalized()
        v = t.cross(u).normalized()
        r = radius * (taper[k] if taper else 1.0)
        stations.append([p + u * (r * cos(2 * pi * i / seg)) + v * (r * sin(2 * pi * i / seg))
                         for i in range(seg)])
    return loft(name, stations, mat, close_ring=True, close_spine=closed,
                cap_start=not closed, cap_end=not closed)


def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.010, seg=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[1], size[2])
    o.data.materials.append(M[mat] if isinstance(mat, str) else mat)
    if bevel > 0:
        b = o.modifiers.new('bevel', 'BEVEL')
        b.width = bevel
        b.segments = seg
        b.limit_method = 'ANGLE'
    return o


def wedge(name, verts, mat, smooth=False):
    """8 点自定义六面体（翼片 / 分流板 / 侧箱等需要非矩形轮廓时用）。
    verts 顺序: 底面 4 点(逆时针) + 顶面 4 点。"""
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return new_obj(name, [Vector(v) for v in verts], faces, mat, smooth=smooth)


def mirror_x(obj, name=None):
    """沿 X 镜像出一份副本（左右对称件）。"""
    dup = obj.copy()
    dup.data = obj.data.copy()
    dup.name = name or (obj.name[:-1] + ('R' if obj.name.endswith('L') else 'L'))
    bpy.context.collection.objects.link(dup)
    dup.matrix_world = Matrix.Diagonal((-1, 1, 1, 1)) @ obj.matrix_world
    bm = bmesh.new()
    bm.from_mesh(dup.data)
    for v in bm.verts:
        v.co.x *= -1
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(dup.data)
    bm.free()
    dup.matrix_world = obj.matrix_world
    return dup


def boolean(target, cutter, op='DIFFERENCE'):
    # 切刀继承目标材质：否则布尔会给结果留一个空材质槽，glTF 导出成"无材质"图元
    if not cutter.data.materials and target.data.materials:
        cutter.data.materials.append(target.data.materials[0])
    mod = target.modifiers.new('bool', 'BOOLEAN')
    mod.operation = op
    mod.object = cutter
    mod.solver = 'EXACT'
    try:
        mod.material_mode = 'TRANSFER'   # 按材质本体传递：否则布尔会把目标面的 material_index 全清零
    except Exception:
        pass
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return target


# ---------------------------------------------------------------- 曲线插值
def hermite(y, keys, field):
    """非均匀 Catmull-Rom（Hermite + 差分切线）插值某个截面参数。"""
    ys = [k[0] for k in keys]
    vs = [k[1][field] for k in keys]
    if y <= ys[0]:
        return vs[0]
    if y >= ys[-1]:
        return vs[-1]
    i = max(j for j in range(len(ys) - 1) if ys[j] <= y)
    h = ys[i + 1] - ys[i]
    t = (y - ys[i]) / h

    def tangent(k):
        if k == 0:
            return (vs[1] - vs[0]) / (ys[1] - ys[0])
        if k == len(ys) - 1:
            return (vs[-1] - vs[-2]) / (ys[-1] - ys[-2])
        return (vs[k + 1] - vs[k - 1]) / (ys[k + 1] - ys[k - 1])

    m0, m1 = tangent(i) * h, tangent(i + 1) * h
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * vs[i] + (t3 - 2 * t2 + t) * m0 +
            (-2 * t3 + 3 * t2) * vs[i + 1] + (t3 - t2) * m1)


def cr2d(knots, counts):
    """二维 Catmull-Rom 采样（截面右半侧轮廓）。返回 sum(counts)+1 个点。"""
    K = [Vector(k) for k in knots]
    ext = [K[0] * 2 - K[1]] + K + [K[-1] * 2 - K[-2]]
    out = []
    for s, n in enumerate(counts):
        p0, p1, p2, p3 = ext[s], ext[s + 1], ext[s + 2], ext[s + 3]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t +
                              (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(K[-1])
    return out


def ring_of(y, prm, squash=0.0):
    """由截面参数生成整圈点（Z 上 X 右，右半侧 -> 镜像左半侧）。

    prm 键: w_low z_low w_hip z_hip w_belt z_belt w_roof z_roof z_crown
    squash: 顶部内收系数（tumblehome）
    """
    wl, zl = prm['w_low'], prm['z_low']
    wh, zh = prm['w_hip'], prm['z_hip']
    wb, zb = prm['w_belt'], prm['z_belt']
    wr, zr = prm['w_roof'], prm['z_roof']
    zc = prm['z_crown']
    wb *= (1 - squash * 0.35)
    wr *= (1 - squash)
    knots = [(0.0, zl), (wl * 0.62, zl), (wl, zl + 0.012),
             (wh, zh), (wb, zb), (wr, zr), (0.0, zc)]
    half = cr2d(knots, SEG_N)
    ring = [Vector((p.x, y, p.y)) for p in half]
    for k in range(len(half) - 2, 0, -1):
        ring.append(Vector((-half[k].x, y, half[k].y)))
    assert len(ring) == RING_N, (len(ring), RING_N)
    return ring


def normals_of(stations):
    """网格顶点法线（环向切线 × 脊线切线），用于生成向内偏移的内衬（玻璃/格栅）。"""
    ns, n = len(stations), len(stations[0])
    out = []
    for s in range(ns):
        row = []
        for i in range(n):
            dr = stations[s][(i + 1) % n] - stations[s][(i - 1) % n]
            s0, s1 = max(0, s - 1), min(ns - 1, s + 1)
            dspine = stations[s1][i] - stations[s0][i]
            nv = dspine.cross(dr)
            row.append(nv.normalized() if nv.length > 1e-9 else Vector((0, 0, 1)))
        out.append(row)
    return out


# ---------------------------------------------------------------- 车身壳体
def _rim_walls(name, mat, stations, inner_st, cell, ns):
    """沿开口边界补一圈凹陷侧壁，把外皮开口和内衬连起来。

    不补的话，进气口/灯腔只是"外皮一个洞 + 里面一张悬空的板"，
    从斜角能顺着缝隙直接看进车壳内部（背面剔除后就是一个空洞）。
    """
    verts, faces = [], []

    def add(a, b, cc):
        p1, p2 = stations[a[0]][a[1]], stations[b[0]][b[1]]
        q1, q2 = inner_st[a[0]][a[1]], inner_st[b[0]][b[1]]
        quad = [p1, p2, q2, q1]
        ctr = (p1 + p2 + q1 + q2) / 4
        if (p2 - p1).cross(q1 - p1).dot(cc - ctr) < 0:   # 法线朝开口内侧
            quad = quad[::-1]
        base = len(verts)
        verts.extend(quad)
        faces.append((base, base + 1, base + 2, base + 3))

    for s in range(ns - 1):
        for i in range(RING_N):
            if not cell(s, i):
                continue
            j = (i + 1) % RING_N
            cc = (stations[s][i] + stations[s + 1][i] + stations[s][j] + stations[s + 1][j]) / 4
            if s == 0 or not cell(s - 1, i):
                add((s, i), (s, j), cc)
            if s == ns - 2 or not cell(s + 1, i):
                add((s + 1, i), (s + 1, j), cc)
            if not cell(s, (i - 1) % RING_N):
                add((s, i), (s + 1, i), cc)
            if not cell(s, j):
                add((s, j), (s + 1, j), cc)
    if not faces:
        return None
    return new_obj(name, verts, faces, mat, smooth=False)


def build_shell(keys, ys, holes=(), squash=0.0, arches=(), name='Body', mat='Paint',
                cap_mats=(None, None)):
    """按关键站参数生成连续车身皮：先做成闭合体切出轮拱，再挖开口并补内衬 + 侧壁。

    holes  : [{'cells': fn(y, d)->bool, 'mat': 'GlassDark', 'inset': 0.014,
               'name': 'Glass', 'rim_mat': 'CarbonMat'}]
    arches : [{'y':..., 'r':..., 'dz':...}] 轮拱（必须在挖洞之前切，EXACT 布尔要求闭合网格）
    cap_mats: (车头端面材质, 车尾端面材质)，None = 沿用车漆
    返回 (body, [内衬/侧壁对象])
    """
    fields = ('w_low', 'z_low', 'w_hip', 'z_hip', 'w_belt', 'z_belt', 'w_roof', 'z_roof', 'z_crown')
    stations = [ring_of(y, {k: hermite(y, keys, k) for k in fields}, squash) for y in ys]
    ns = len(ys)
    ymid = [(ys[s] + ys[s + 1]) / 2 for s in range(ns - 1)]

    def face_d(i):
        return abs(IDX_CROWN - i - 0.5) if i <= IDX_CROWN else i + 0.5 - IDX_CROWN

    def cell_of(h):
        return lambda s, i: bool(h['cells'](ymid[s], face_d(i)))

    # 先做成闭合体（EXACT 布尔要求闭合网格），开口位置用"临时材质槽"打标记 ——
    # 布尔一定会保留 material_index，切完轮拱再按标记删面，开口边界才不会被打成锯齿。
    body = loft(name, stations, mat, cap_start=True, cap_end=True)
    grid_n = (ns - 1) * RING_N
    cap_slots = []
    for ci, cm in enumerate(cap_mats):        # 鼻尖/尾板端面单独给材质（不然是一块白色椭圆）
        if not cm:
            continue
        body.data.materials.append(M[cm] if isinstance(cm, str) else cm)
        cap_slots.append(len(body.data.materials) - 1)
        base = grid_n + ci * RING_N
        for f in range(base, min(base + RING_N, len(body.data.polygons))):
            body.data.polygons[f].material_index = cap_slots[-1]
    # 开口槽位必须排在端面槽位之后；删面阈值也用它 —— 用死的 "index > 0"
    # 会把车头/车尾端面一起删掉，车就前后透空了。
    hole_base = len(body.data.materials)
    if holes:
        for hi in range(len(holes)):
            body.data.materials.append(bpy.data.materials.new('__hole%d' % hi))
        for idx in range(grid_n):
            s, i = divmod(idx, RING_N)
            d = face_d(i)
            for hi, h in enumerate(holes):
                if h['cells'](ymid[s], d):
                    body.data.polygons[idx].material_index = hole_base + hi
                    break
    for a in arches:
        arch_cut(body, a['y'], a.get('r', 0.45), a.get('x', HUB_X), a.get('w', 0.62), a.get('dz', 0.02))
    if holes:
        bm = bmesh.new()
        bm.from_mesh(body.data)
        doomed = [f for f in bm.faces if f.material_index >= hole_base]
        bmesh.ops.delete(bm, geom=doomed, context='FACES')
        kept = {}
        for f in bm.faces:
            kept[f.material_index] = kept.get(f.material_index, 0) + 1
        # 回归哨兵：车头/车尾端面必须活着，否则从正前/正后能直接看进车壳（用户报过的 bug）。
        # 端面所有顶点都在极值站上，面心 y 精确等于 ymin/ymax；相邻环带的面心至少差半个站距。
        for label, yt in (('车头', ys[0]), ('车尾', ys[-1])):
            n = sum(1 for f in bm.faces if abs(f.calc_center_median().y - yt) < 0.004)
            assert n > 0, '%s端面被开口遮罩删掉了（y=%.3f），车会透空' % (label, yt)
        bm.to_mesh(body.data)
        bm.free()
        for sl in cap_slots:
            assert kept.get(sl, 0) > 0, '端面材质槽 %d 上没有面了' % sl
        while (len(body.data.materials) > 1 and body.data.materials[-1] is not None
               and body.data.materials[-1].name.startswith('__hole')):
            bpy.data.materials.remove(body.data.materials.pop())
        clean_mesh(body, weld=0)

    # 内衬（玻璃 / 格栅 / 灯）：同一张网格向内偏移，遮罩比开口外扩一格保证不漏缝
    nrm = normals_of(stations)
    inners = []
    for h in holes:
        inset = h.get('inset', 0.014)
        cell = cell_of(h)

        def keep(s, i, cell=cell):
            for ds in (-1, 0, 1):
                for di in (-1, 0, 1):
                    if cell(min(max(s + ds, 0), ns - 2), (i + di) % RING_N):
                        return True
            return False

        inner_st = [[stations[s][i] - nrm[s][i] * inset for i in range(RING_N)]
                    for s in range(ns)]
        o = loft(h.get('name', 'Inner'), inner_st, h['mat'], keep=keep, smooth=h.get('smooth', True))
        if len(o.data.polygons) == 0:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        inners.append(o)
        rim = _rim_walls(h.get('name', 'Inner') + 'Rim', h.get('rim_mat', 'CarbonMat'),
                         stations, inner_st, cell, ns)
        if rim:
            inners.append(rim)
    return body, inners


def surface_strip(keys, y0, y1, d0, d1, mat, name='Stripe', offset=0.004,
                  squash=0.0, steps=None):
    """贴合车身表面的条带（拉花 / 分缝线 / 散热百叶）。

    d 用带符号环向坐标：0=车顶中心，正=+X 侧，负=-X 侧，|d| 6=顶沿 12=腰线 17=最宽处。
    """
    steps = steps or max(4, int(math.ceil(abs(y1 - y0) / 0.055)))
    fields = ('w_low', 'z_low', 'w_hip', 'z_hip', 'w_belt', 'z_belt', 'w_roof', 'z_roof', 'z_crown')
    stations = [ring_of(y0 + (y1 - y0) * k / steps,
                        {kk: hermite(y0 + (y1 - y0) * k / steps, keys, kk) for kk in fields}, squash)
                for k in range(steps + 1)]
    nrm = normals_of(stations)
    lo, hi = sorted((d0, d1))
    sd = lambda i: (IDX_CROWN - i) if i <= IDX_CROWN else -(i - IDX_CROWN)
    idx = sorted([i for i in range(RING_N) if lo <= sd(i) <= hi], key=sd)
    while len(idx) < 2 and hi - lo < RING_N:      # 环向采样是整数间距，范围太窄就对称放宽
        lo, hi = lo - 0.5, hi + 0.5
        idx = sorted([i for i in range(RING_N) if lo <= sd(i) <= hi], key=sd)
        if len(idx) >= 2:
            print('  · %s 环向范围太窄，已放宽到 d=%.1f..%.1f' % (name, lo, hi))
    if len(idx) < 2:
        raise ValueError('%s: 环向范围无解（d=%s..%s）' % (name, d0, d1))
    sub = [[stations[s][i] + nrm[s][i] * offset for i in idx] for s in range(len(stations))]
    return loft(name, sub, mat, close_ring=False, cap_start=False, cap_end=False)


def hexa(name, pts, mat, smooth=False):
    """8 点六面体（自动修正法线朝外）。"""
    o = wedge(name, pts, mat, smooth=smooth)
    return clean_mesh(o, recalc=True)


def revolve_arc(name, profile, mat, a0, a1, seg=14, center=(0, 0, 0), sx=1.0, smooth=True):
    """断面绕 X 轴扫过一段角度（刹车卡钳等），两端封口。"""
    stations = []
    for k in range(seg + 1):
        a = a0 + (a1 - a0) * k / seg
        stations.append([Vector((ax * sx + center[0], r * cos(a) + center[1], r * sin(a) + center[2]))
                         for (ax, r) in profile])
    o = loft(name, stations, mat, close_ring=True, cap_start=True, cap_end=True, smooth=smooth)
    return clean_mesh(o, recalc=True)


# ---------------------------------------------------------------- 车轮
WHEEL_DEFAULT = dict(
    rim_r=0.205,        # 胎圈/轮辋半径
    half_w_f=0.148,     # 前胎半宽
    half_w_r=0.170,     # 后胎半宽
    spokes=10,          # 辐条数
    spoke_w=0.030,      # 辐条半宽（根部）
    spoke_taper=0.55,   # 辐条端部收窄比
    rim_mat='RimAlloy',
    lip_mat='RimDark',
    caliper_mat='Caliper',
    grooves=0,          # 胎面纵向沟槽数（0=光头胎）
    center_lock=True,   # 单孔中锁螺母（赛车）/ False 用 5 螺栓
    cover=None,         # 轮辐盖板材质（F1 风格封闭轮罩）
    track_out=0.020,    # 轮组外移量（宽体姿态）
    disc_r=0.186,
)


def tire_profile(R, hw, br, grooves=0):
    out = [(-hw * 0.90, br + 0.004), (-hw * 0.99, br + 0.038), (-hw * 1.05, (R + br) * 0.5),
           (-hw * 1.04, R - 0.058), (-hw * 0.99, R - 0.019), (-hw * 0.87, R - 0.003)]
    n = max(2, grooves * 2 + 2)
    for k in range(n + 1):
        f = -0.87 + 1.74 * k / n
        r = R + 0.002 * (1 - (f / 0.87) ** 2)
        if grooves and 0 < k < n and k % 2 == 1:
            r = R - 0.013                      # 纵向排水沟
        out.append((hw * f, r))
    out += [(hw * 0.87, R - 0.003), (hw * 0.99, R - 0.019), (hw * 1.04, R - 0.058),
            (hw * 1.05, (R + br) * 0.5), (hw * 0.99, br + 0.038), (hw * 0.90, br + 0.004)]
    return out


def rim_profile(hw, br):
    barrel = br - 0.034
    return [(hw * 0.93, br + 0.011), (hw * 0.86, br + 0.011), (hw * 0.80, barrel),
            (-hw * 0.74, barrel), (-hw * 0.86, br + 0.008), (-hw * 0.93, br + 0.008),
            (-hw * 0.93, br - 0.006), (-hw * 0.88, br - 0.006), (-hw * 0.78, barrel - 0.013),
            (hw * 0.76, barrel - 0.013), (hw * 0.87, br - 0.002), (hw * 0.93, br - 0.002)]


def build_wheel(key, st):
    """造一只完整车轮 + 卡钳，挂到 Hub 空物体下。返回 hub。"""
    s = dict(WHEEL_DEFAULT)
    st = dict(st or {})
    front = key[0] == 'F'
    per_axle = st.pop('front' if front else 'rear', {})
    st.pop('rear' if front else 'front', None)
    s.update(st)
    s.update(per_axle)
    sx = 1 if key[1] == 'L' else -1              # +1 左侧(+X)
    y = AXLE_F if front else AXLE_R
    hw = s['half_w_f'] if front else s['half_w_r']
    br, R = s['rim_r'], TIRE_R
    cx = sx * (HUB_X + s['track_out'])
    center = (cx, y, HUB_Z)
    parts = []

    parts.append(revolve('Tire' + key, tire_profile(R, hw, br, s['grooves']), 'Rubber',
                         seg=34, center=center, axis='X'))
    prof = [(a * sx, r) for (a, r) in rim_profile(hw, br)]
    parts.append(revolve('RimBarrel' + key, prof, s['rim_mat'], seg=30, center=center, axis='X'))

    # 轮辐：真实连接轮毂盘与桶身内壁，带外倾（dish）
    barrel = br - 0.040
    a_out, a_in = hw * 0.60 * sx, hw * 0.16 * sx
    for k in range(s['spokes']):
        th = 2 * pi * k / s['spokes'] + (pi / s['spokes'] if key[1] == 'R' else 0)
        u = Vector((0, cos(th), sin(th)))
        v = Vector((0, -sin(th), cos(th)))
        xa = Vector((1, 0, 0))
        pts = []
        for (r, a, w, t) in ((0.062, a_in, s['spoke_w'], 0.019),
                             (barrel + 0.006, a_out, s['spoke_w'] * s['spoke_taper'], 0.013)):
            c = Vector(center) + u * r + xa * a
            pts += [c - v * w - xa * t, c + v * w - xa * t, c + v * w + xa * t, c - v * w + xa * t]
        parts.append(hexa('Spoke%s%d' % (key, k),
                          [pts[0], pts[1], pts[2], pts[3], pts[4], pts[5], pts[6], pts[7]],
                          s['rim_mat'], smooth=False))

    # 轮毂盘 + 中锁螺母
    parts.append(revolve('Hubface' + key,
                         [(a * sx, r) for (a, r) in
                          [(hw * 0.10, 0.0), (hw * 0.10, 0.075), (hw * 0.30, 0.070), (hw * 0.30, 0.0)]],
                         s['rim_mat'], seg=20, center=center, axis='X'))
    if s['center_lock']:
        nut = []
        for k in range(6):
            a = 2 * pi * k / 6
            nut.append((hw * 0.34 * sx, 0.036))
        parts.append(revolve('Nut' + key,
                             [(hw * 0.30 * sx, 0.040), (hw * 0.42 * sx, 0.038),
                              (hw * 0.42 * sx, 0.018), (hw * 0.30 * sx, 0.018)],
                             'Chrome', seg=6, center=center, axis='X', smooth=False))
    else:
        for k in range(5):
            a = 2 * pi * k / 5
            c = (center[0] + hw * 0.33 * sx, center[1] + 0.058 * cos(a), center[2] + 0.058 * sin(a))
            parts.append(revolve('Lug%s%d' % (key, k),
                                 [(0.0, 0.0), (0.0, 0.013), (0.020 * sx, 0.012), (0.020 * sx, 0.0)],
                                 'Steel', seg=6, center=c, axis='X', smooth=False))
    if s['cover']:
        parts.append(revolve('Cover' + key,
                             [(hw * 0.62 * sx, 0.075), (hw * 0.66 * sx, 0.075),
                              (hw * 0.66 * sx, br - 0.030), (hw * 0.62 * sx, br - 0.030)],
                             s['cover'], seg=28, center=center, axis='X'))

    # 通风刹车盘（钻孔）+ 盘帽
    dr = s['disc_r']
    disc = revolve('Disc' + key,
                   [(a * sx, r) for (a, r) in
                    [(0.014, 0.116), (0.014, dr), (-0.014, dr), (-0.014, 0.116)]],
                   'Steel', seg=30, center=center, axis='X', smooth=False)
    cutters = []
    for k in range(10):
        a = 2 * pi * k / 10 + 0.15
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=8, radius=0.011, depth=0.09, rotation=(0, pi / 2, 0),
            location=(center[0], center[1] + 0.152 * cos(a), center[2] + 0.152 * sin(a)))
        cutters.append(bpy.context.active_object)
    for c in cutters[1:]:
        c.select_set(True)
    bpy.context.view_layer.objects.active = cutters[0]
    cutters[0].select_set(True)
    bpy.ops.object.join()
    boolean(disc, bpy.context.active_object)
    parts.append(disc)
    parts.append(revolve('DiscHat' + key,
                         [(a * sx, r) for (a, r) in
                          [(-0.014, 0.116), (-0.014, 0.100), (-0.048, 0.088), (-0.048, 0.062),
                           (-0.030, 0.062), (-0.030, 0.082), (0.006, 0.096), (0.006, 0.116)]],
                         'RimDark', seg=24, center=center, axis='X'))

    # 合并为单个 WheelXX（随车速自转）
    for o in bpy.data.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    wheel = bpy.context.active_object
    wheel.name = 'Wheel' + key
    wheel.data.name = 'Wheel' + key
    # 关键：把原点搬到轮心。零件顶点都是绝对坐标、物体原点在 (0,0,0)，
    # 直接导出会让 glTF 把 WheelXX 的节点变换烤成 T(-轮心)，
    # 游戏里 spin.rotation.x 就变成绕车身原点 1.7m 公转而不是自转。
    hub_loc = Vector((sx * HUB_X, y, HUB_Z))
    wheel.data.transform(Matrix.Translation(-hub_loc))
    wheel.location = hub_loc

    # 卡钳（贴合刹车盘，不随轮转）
    ang = (0.55 * pi, 1.05 * pi) if front else (-0.45 * pi, 0.05 * pi)
    cal = revolve_arc('Caliper' + key,
                      [(0.045, 0.118), (0.045, dr + 0.014), (0.019, dr + 0.014), (0.019, 0.118),
                       (-0.019, 0.118), (-0.019, dr + 0.014), (-0.045, dr + 0.014), (-0.045, 0.118)],
                      s['caliper_mat'], ang[0], ang[1], seg=10, center=center, sx=sx, smooth=False)

    hub = bpy.data.objects.new('Hub' + key, None)
    hub.empty_display_size = 0.12
    bpy.context.collection.objects.link(hub)
    hub.location = (sx * HUB_X, y, HUB_Z)
    hub.matrix_world = Matrix.Translation(Vector(hub.location))
    inv = hub.matrix_world.inverted()
    for child in (wheel, cal):
        child.parent = hub
        child.matrix_parent_inverse = inv
    return hub


def build_wheels(style=None):
    return [build_wheel(k, style) for k in ('FL', 'FR', 'RL', 'RR')]


# ---------------------------------------------------------------- 装配 / 导出 / 自检
def begin_car(paint_rough=0.26):
    global M
    reset_scene()
    M = build_materials(paint_rough)
    return M


def assemble(merge=True):
    """把所有未挂在 Hub 下的网格挂到 BodyPivot（车身姿态容器）。

    merge=True 时把单材质零件按材质合并 —— glTF 本来就按材质拆图元，
    合并后每辆车的 draw call 从 ~70 降到 ~35，四辆车同屏差别明显。
    """
    pivot = bpy.data.objects.new('BodyPivot', None)
    pivot.empty_display_size = 0.15
    bpy.context.collection.objects.link(pivot)
    pivot.matrix_world = Matrix.Identity(4)
    parts = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent is None and o is not pivot]
    for o in parts:
        o.parent = pivot
    if merge:
        groups = {}
        for o in parts:
            if len(o.data.materials) == 1 and o.data.materials[0] is not None:
                groups.setdefault(o.data.materials[0].name, []).append(o)
        for mname, objs in groups.items():
            if len(objs) < 2:
                continue
            for x in bpy.data.objects:
                x.select_set(False)
            for x in objs:
                x.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.object.join()
            bpy.context.active_object.name = 'Part_' + mname
    return pivot


def stats():
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
    return tris


REQUIRED_NODES = ('BodyPivot', 'HubFL', 'HubFR', 'HubRL', 'HubRR',
                  'WheelFL', 'WheelFR', 'WheelRL', 'WheelRR',
                  'CaliperFL', 'CaliperFR', 'CaliperRL', 'CaliperRR')
REQUIRED_MATS = ('Paint', 'TailLight')


def verify_glb(path):
    """解析 GLB 的 JSON 块，核对游戏端依赖的节点名与材质名（"文件存在"不算验证）。"""
    with open(path, 'rb') as f:
        magic, ver, _ = struct.unpack('<4sII', f.read(12))
        assert magic == b'glTF', '不是 GLB 文件'
        clen, ctype = struct.unpack('<II', f.read(8))
        doc = json.loads(f.read(clen).decode('utf-8'))
    names = {n.get('name') for n in doc.get('nodes', [])}
    mats = {m.get('name') for m in doc.get('materials', [])}
    missing = [n for n in REQUIRED_NODES if n not in names]
    bad = [n for n in (names | mats) if n and '.00' in n]
    mmiss = [m for m in REQUIRED_MATS if m not in mats]
    assert not missing, '缺少节点: %s' % missing
    assert not mmiss, '缺少材质: %s' % mmiss
    assert not bad, '出现重名副本（场景未重置）: %s' % bad
    # 车轮必须挂在对应 Hub 之下
    idx = {i: n.get('name') for i, n in enumerate(doc['nodes'])}
    for i, n in enumerate(doc['nodes']):
        for c in n.get('children', []):
            if idx[c].startswith('Wheel'):
                assert idx[i] == 'Hub' + idx[c][5:], '%s 的父节点错了: %s' % (idx[c], idx[i])
    # 车轮自转原点必须落在轮心：节点自身不许带位移，几何包围盒在自转轴(X)以外两轴上要居中。
    # 否则游戏里 wheels.spin.rotation.x 会把轮子甩出一个大圆弧（静止截图看不出来）。
    for i, n in enumerate(doc['nodes']):
        if not (n.get('name') or '').startswith('Wheel'):
            continue
        t = n.get('translation', [0, 0, 0])
        off = max(abs(v) for v in t)
        assert off < 0.02, '%s 节点带位移 %s（自转会变公转）' % (n['name'], t)
        prim = doc['meshes'][n['mesh']]['primitives']
        lo = [min(doc['accessors'][p['attributes']['POSITION']]['min'][k] for p in prim) for k in range(3)]
        hi = [max(doc['accessors'][p['attributes']['POSITION']]['max'][k] for p in prim) for k in range(3)]
        ctr = [(lo[k] + hi[k]) / 2 for k in range(3)]
        assert abs(ctr[1]) < 0.06 and abs(ctr[2]) < 0.06, \
            '%s 几何没对齐轮心: 中心=%s' % (n['name'], [round(c, 3) for c in ctr])
    return len(doc.get('meshes', [])), len(mats)


def export(spec_id):
    path = os.path.join(ASSETS, 'car_%s.glb' % spec_id)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=True,
                              export_yup=True, export_animations=False,
                              export_normals=True, export_texcoords=False)
    nmesh, nmat = verify_glb(path)
    print('  ✓ 导出 %-14s %6.0f KB  三角面 %d  材质 %d'
          % (os.path.basename(path), os.path.getsize(path) / 1024, stats(), nmat))
    return path


# ---------------------------------------------------------------- 预览渲染
def render_preview(spec_id, views=('hero',), samples=28, res=(900, 560)):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX' if 'AgX' in [v.name for v in
        bpy.types.ColorManagedViewSettings.bl_rna.properties['view_transform'].enum_items] else 'Filmic'
    scene.view_settings.look = 'None'

    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    nt = world.node_tree
    bg = next(n for n in nt.nodes if n.type == 'BACKGROUND')
    grad = nt.nodes.new('ShaderNodeTexGradient')
    grad.gradient_type = 'EASING'
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (0.035, 0.040, 0.050, 1)
    ramp.color_ramp.elements[1].color = (0.62, 0.68, 0.76, 1)
    mapn = nt.nodes.new('ShaderNodeMapping')
    texc = nt.nodes.new('ShaderNodeTexCoord')
    mapn.inputs['Rotation'].default_value = (pi / 2, 0, 0)
    nt.links.new(texc.outputs['Generated'], mapn.inputs['Vector'])
    nt.links.new(mapn.outputs['Vector'], grad.inputs['Vector'])
    nt.links.new(grad.outputs['Color'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bg.inputs['Color'])
    bg.inputs[1].default_value = 1.15
    scene.world = world

    for (loc, rot, energy, size) in (((5, -6, 6), (0.75, 0.1, 0.72), 260, 6),
                                     ((-7, 3, 4), (1.05, 0, -1.2), 120, 5),
                                     ((2, 8, 3), (1.30, 0, 3.4), 90, 4)):
        la = bpy.data.lights.new('area', 'AREA')
        la.energy, la.size = energy, size
        lo = bpy.data.objects.new('area', la)
        lo.location, lo.rotation_euler = loc, rot
        bpy.context.collection.objects.link(lo)
    sun = bpy.data.lights.new('sun', 'SUN')
    sun.energy, sun.angle = 2.6, 0.06
    so = bpy.data.objects.new('sun', sun)
    so.rotation_euler = (0.82, 0.12, 0.66)
    bpy.context.collection.objects.link(so)

    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new('GroundMat')
    gm.use_nodes = True
    gb = next(n for n in gm.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    gb.inputs['Base Color'].default_value = (0.055, 0.058, 0.062, 1)
    gb.inputs['Roughness'].default_value = 0.32
    gb.inputs['Metallic'].default_value = 0.1
    ground.data.materials.append(gm)

    cam = bpy.data.cameras.new('cam')
    cam.lens = 78
    co = bpy.data.objects.new('cam', cam)
    bpy.context.collection.objects.link(co)
    tgt = bpy.data.objects.new('tgt', None)
    tgt.location = (0, 0, 0.55)
    bpy.context.collection.objects.link(tgt)
    co.constraints.new('TRACK_TO').target = tgt
    scene.camera = co

    VIEWS = {
        'hero':    ((6.4, -8.2, 2.5), (0, 0, 0.55)),
        'rear':    ((-6.0, 8.4, 2.6), (0, 0, 0.6)),
        'tail':    ((0.06, 7.4, 1.10), (0, 1.6, 0.52)),      # 正后方特写（玩家视角）
        'tailq':   ((2.9, 6.6, 1.35), (0, 1.5, 0.55)),
        'side':    ((11.5, 0.6, 1.4), (0, 0, 0.55)),
        'front':   ((0.5, -11.0, 1.6), (0, 0, 0.55)),
        'top':     ((0.01, -0.6, 9.5), (0, 0, 0.4)),
    }
    outs = []
    for v in views:
        loc, look = VIEWS[v]
        co.location = loc
        tgt.location = look
        p = os.path.join(ASSETS, 'preview_%s_%s.png' % (spec_id, v))
        scene.render.filepath = p
        scene.render.image_settings.file_format = 'PNG'
        bpy.ops.render.render(write_still=True)
        outs.append(p)
        print('  ✓ 预览', os.path.basename(p))
    return outs


def cli_args():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = {'spec': 'all', 'render': False, 'views': 'hero'}
    for a in argv:
        if a.startswith('--spec='):
            out['spec'] = a.split('=', 1)[1]
        elif a == '--render':
            out['render'] = True
        elif a.startswith('--views='):
            out['views'] = a.split('=', 1)[1]
            out['render'] = True
    return out


# ---------------------------------------------------------------- 空力件
def airfoil(chord, thick, camber=0.06, n=16, gurney=0.0):
    """翼型闭合断面 (y=弦向, z=厚度)，前缘在 -chord/2。"""
    up, lo = [], []
    for i in range(n):
        t = i / (n - 1)
        th = thick * math.sin(pi * (t ** 0.62)) if 0 < t < 1 else 0.0
        zc = camber * math.sin(pi * (t ** 0.85))
        y = chord * (t - 0.5)
        up.append((y, zc + th * 0.5))
        lo.append((y, zc - th * 0.5))
    if gurney:
        up[-1] = (up[-1][0], up[-1][1] + gurney)
    return up + lo[::-1][1:-1]


def wing(name, span, chord, mat, loc=(0, 0, 0), thick=0.030, camber=0.075, aoa=-0.20,
         taper=1.0, sweep=0.0, seg_span=4, gurney=0.0):
    """按翼型放样的尾翼/前翼单元（span 沿 X，弦向沿 Y）。"""
    prof = airfoil(chord, thick, camber, gurney=gurney)
    stations = []
    for k in range(seg_span + 1):
        f = k / seg_span
        x = -span / 2 + span * f
        sc = 1 - (1 - taper) * abs(2 * f - 1)
        ring = []
        for (y, z) in prof:
            yy, zz = y * sc, z * sc
            ya = yy * cos(aoa) - zz * sin(aoa)
            za = yy * sin(aoa) + zz * cos(aoa)
            ring.append(Vector((x + loc[0], ya + loc[1] + sweep * abs(2 * f - 1), za + loc[2])))
        stations.append(ring)
    return loft(name, stations, mat, close_ring=True, cap_start=True, cap_end=True)


def plate(name, pts2d, thick, mat, loc=(0, 0, 0), plane='yz', rot=0.0, smooth=False):
    """二维多边形挤出成薄板（端板 / 尾翼支柱 / 扰流板）。pts2d 逆时针。"""
    verts, faces = [], []
    n = len(pts2d)
    for sgn in (-1, 1):
        for (a, b) in pts2d:
            ca, cb = a * cos(rot) - b * sin(rot), a * sin(rot) + b * cos(rot)
            off = sgn * thick / 2
            if plane == 'yz':
                v = Vector((off, ca, cb))
            elif plane == 'xz':
                v = Vector((ca, off, cb))
            else:
                v = Vector((ca, cb, off))
            verts.append(v + Vector(loc))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(range(n, 2 * n)))
    o = new_obj(name, verts, faces, mat, smooth=smooth)
    return clean_mesh(o, recalc=True)


def superellipse(y, cx, cz, w, h, n=4.0, seg=18):
    """超椭圆断面（n 越大越方）。用于侧箱 / 进气道 / 鼻锥这类管状件。"""
    pts = []
    for i in range(seg):
        a = 2 * pi * i / seg
        c, s_ = cos(a), sin(a)
        x = w * (1 if c >= 0 else -1) * abs(c) ** (2 / n)
        z = h * (1 if s_ >= 0 else -1) * abs(s_) ** (2 / n)
        pts.append(Vector((cx + x, y, cz + z)))
    return pts


def duct(name, sections, mat, cap_start=True, cap_end=True, seg=18):
    """按 (y, cx, cz, w, h, n) 列表放样的管状件。"""
    st = [superellipse(y, cx, cz, w, h, n, seg) for (y, cx, cz, w, h, n) in sections]
    return loft(name, st, mat, cap_start=cap_start, cap_end=cap_end)


def sphere(name, r, loc, mat, seg=20, ring=10, squash=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (1, 1, squash)
    o.data.materials.append(M[mat] if isinstance(mat, str) else mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


# ---------------------------------------------------------------- 车尾套件
def tail_kit(keys, squash=0.0, bar=None, bar_seg=1, wrap=None, lip=None, valance=None,
             lic=None, exh=None, diff=None, refl=None, rev=None, badge=None, vents=None,
             rain=None):
    """车尾细节套件。玩家绝大部分时间只看得到车尾，这里的信息密度直接决定观感。

    自上而下的层次（照搬量产跑车的做法）：鸭尾压线 → 贯穿灯带（绕到两侧翼子板）
    → 车漆面板 + 车标 → 牌照凹槽 + 两侧网格出气 → 暗色下包围（四出排气 + 反光片）→ 扩散器竖鳍。

    bar     : (半宽, z0, z1, y)   尾面上的贯穿灯带；bar_seg>1 则切成 N 段（肌肉车风格）
    wrap    : (y0, y1, d0, d1)    灯带绕到侧面的延伸段（左右镜像，贴合车身曲面）
    lip     : (y0, y1, d半宽)     尾板上沿的暗色鸭尾压线
    valance : (y0, y1, d0, d1)    下包围暗色区（左右镜像）
    lic     : (半宽, z0, z1, y)   牌照凹槽
    vents   : (半宽, x, z0, z1, y) 牌照两侧的网格出气口
    exh     : dict(xs=[...], z=, y=, r=, box=(半宽, z0, z1))  排气 + 下半截暗色面板
    diff    : dict(y=(y0,y1), z=(z0,z1), w=, fins=)  扩散器 + 竖鳍
    refl    : (x, z0, z1, y)      两侧反光片
    rev     : (半宽, z0, z1, y)   倒车灯
    badge   : (半宽, z0, z1, y)   尾标条
    rain    : (半宽, z0, z1, y)   雨雾灯
    """
    out = []
    if valance:
        y0, y1, d0, d1 = valance
        for sgn, sd in ((1, 'L'), (-1, 'R')):
            lo, hi = sorted((sgn * d0, sgn * d1))
            out.append(surface_strip(keys, y0, y1, lo, hi, 'CarbonMat',
                                     name='Valance' + sd, offset=0.004, squash=squash))
    if lip:
        y0, y1, dd = lip
        out.append(surface_strip(keys, y0, y1, -dd, dd, 'CarbonMat',
                                 name='DuckLip', offset=0.006, squash=squash))
    if exh and exh.get('box'):
        # 尾面下半截整块暗色的下包围，并且要凸出尾面 2cm —— 平贴上去不出层次，
        # 埋在尾面后面则完全看不见（下包围本来就是一个独立的保险杠件）。
        hw, z0, z1 = exh['box']
        out.append(plate('LowerPanel',
                         [(-hw * 0.97, z0), (hw * 0.97, z0), (hw, z0 + 0.07),
                          (hw * 0.95, z1), (-hw * 0.95, z1), (-hw, z0 + 0.07)],
                         0.17, 'CarbonMat', loc=(0, exh['y'] - 0.065, 0), plane='xz'))
    if bar:
        hw, z0, z1, y = bar
        out.append(plate('TailBarSurround',            # 灯带整条嵌在一条贯穿的暗色带里
                         [(-hw - 0.028, z0 - 0.042), (hw + 0.028, z0 - 0.042),
                          (hw + 0.028, z1 + 0.042), (-hw - 0.028, z1 + 0.042)],
                         0.060, 'CarbonMat', loc=(0, y - 0.034, 0), plane='xz'))
        if bar_seg <= 1:
            out.append(plate_recess('TailBar', hw, z0, z1, y, 0.030, 'TailLight'))
        else:
            sw = 2 * hw / (bar_seg + (bar_seg - 1) * 0.20)
            for k in range(bar_seg):
                out.append(plate_recess('TailBar%d' % k, sw / 2, z0, z1, y, 0.030, 'TailLight',
                                        cx=-hw + sw / 2 + k * sw * 1.20))
    if wrap:
        y0, y1, d0, d1 = wrap
        for sgn, sd in ((1, 'L'), (-1, 'R')):
            lo, hi = sorted((sgn * d0, sgn * d1))
            out.append(surface_strip(keys, y0, y1, lo, hi, 'TailLight',
                                     name='TailWrap' + sd, offset=0.008, squash=squash))
    if lic:
        hw, z0, z1, y = lic
        out.append(plate_recess('PlateWell', hw + 0.030, z0 - 0.026, z1 + 0.026, y - 0.048, 0.10, 'CarbonMat'))
        out.append(plate_recess('PlateNum', hw, z0, z1, y, 0.022, 'Accent'))
    if badge:
        out.append(plate_recess('Badge', badge[0], badge[1], badge[2], badge[3], 0.020, 'Chrome'))
    if rain:
        out.append(plate_recess('RainLight', rain[0], rain[1], rain[2], rain[3], 0.024, 'TailLight'))
    if vents:
        hw, x, z0, z1, y = vents
        for sgn, sd in ((1, 'L'), (-1, 'R')):
            out.append(plate_recess('VentWell' + sd, hw + 0.020, z0 - 0.018, z1 + 0.018,
                                    y - 0.038, 0.08, 'CarbonMat', cx=sgn * x))
            out.append(plate_recess('TailVent' + sd, hw, z0, z1, y - 0.010, 0.030, 'Mesh', cx=sgn * x))
    if exh:
        z, y, r = exh['z'], exh['y'], exh.get('r', 0.050)
        for k, x in enumerate(exh['xs']):
            for sgn, sd in ((1, 'L'), (-1, 'R')):
                out.append(revolve('Exh%d%s' % (k, sd),      # 中空管口：看得见管内的黑
                                   [(0.0, r * 0.74), (0.0, r), (-0.18, r * 0.96), (-0.18, 0.0),
                                    (-0.165, 0.0), (-0.165, r * 0.72)],
                                   'Chrome', seg=16, center=(sgn * x, y + 0.026, z), axis='Y'))
                out.append(revolve('ExhRim%d%s' % (k, sd),
                                   [(0.018, r), (0.018, r + 0.017), (-0.06, r + 0.017), (-0.06, r)],
                                   'CarbonMat', seg=16, center=(sgn * x, y + 0.026, z), axis='Y'))
    if refl:
        x, z0, z1, y = refl
        for sgn, sd in ((1, 'L'), (-1, 'R')):
            out.append(plate_recess('Reflector' + sd, 0.052, z0, z1, y, 0.020, 'TailLight', cx=sgn * x))
    if rev:
        hw, z0, z1, y = rev
        for sgn, sd in ((1, 'L'), (-1, 'R')):
            out.append(plate_recess('ReverseLight' + sd, hw, z0, z1, y, 0.020, 'HeadLight',
                                    cx=sgn * (hw + 0.024)))
    if diff:
        (y0, y1), (z0, z1), w, fins = diff['y'], diff['z'], diff['w'], diff['fins']
        out.append(plate('Diffuser', [(y0, z0 + 0.030), (y1, z0), (y1, z1), (y0, z1 + 0.010)],
                         w * 2, 'CarbonMat', plane='yz'))
        for k in range(fins):
            x = -w * 0.84 + (2 * w * 0.84) * k / max(1, fins - 1)
            out.append(plate('DiffFin%d' % k,
                             [(y0 + 0.06, z0 + 0.040), (y1, z0 + 0.010), (y1, z1 + 0.050),
                              (y0 + 0.06, z1 + 0.020)], 0.022, 'Carbon', loc=(x, 0, 0), plane='yz'))
        for sgn, sd in ((1, 'L'), (-1, 'R')):     # 扩散器侧板
            out.append(plate('DiffEnd' + sd,
                             [(y0, z0 + 0.030), (y1, z0), (y1, z1 + 0.085), (y0, z1 + 0.045)],
                             0.026, 'CarbonMat', loc=(sgn * w, 0, 0), plane='yz'))
    return [o for o in out if o]


def plate_recess(name, hw, z0, z1, y, depth, mat, cx=0.0):
    """贴在尾面上的矩形板（牌照 / 反光片 / 倒车灯 / 尾标），向车内插 depth 保证不悬空。"""
    return plate(name, [(cx - hw, z0), (cx + hw, z0), (cx + hw, z1), (cx - hw, z1)],
                 depth, mat, loc=(0, y - depth / 2, 0), plane='xz')


# ---------------------------------------------------------------- 作者辅助
def K(y, w_low, z_low, w_hip, z_hip, w_belt, z_belt, w_roof, z_roof, z_crown):
    """一个车身关键站。参数含义见 ring_of()。"""
    return (y, dict(w_low=w_low, z_low=z_low, w_hip=w_hip, z_hip=z_hip, w_belt=w_belt,
                    z_belt=z_belt, w_roof=w_roof, z_roof=z_roof, z_crown=z_crown))


def zone(y0, y1, d0, d1):
    """(y, d) 矩形开口区域。d: 0=车顶中心 6=顶沿 12=腰线 17=最宽处 28=车底中心。"""
    return lambda y, d: y0 <= y <= y1 and d0 <= d <= d1


def any_of(*fns):
    return lambda y, d: any(f(y, d) for f in fns)


def sample_ys(keys, step=0.115, extra=()):
    """按关键站范围生成放样站位（含所有关键站与补充站）。"""
    y0, y1 = keys[0][0], keys[-1][0]
    n = max(2, int(round((y1 - y0) / step)))
    ys = {round(y0 + (y1 - y0) * i / n, 4) for i in range(n + 1)}
    ys |= {round(k[0], 4) for k in keys}
    ys |= {round(e, 4) for e in extra}
    return sorted(ys)


def arch_cut(body, y, r=0.44, x=HUB_X, w=0.62, dz=0.02):
    """开轮拱（布尔切圆柱）。"""
    for sx in (1, -1):
        bpy.ops.mesh.primitive_cylinder_add(vertices=28, radius=r, depth=w,
                                            location=(sx * x, y, HUB_Z + dz),
                                            rotation=(0, pi / 2, 0))
        boolean(body, bpy.context.active_object)
    return body
