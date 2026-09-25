"""Blender 生成脚本共用工具：程序化贴图、材质、bmesh 基本体、导出。
由 make_*.py 通过 sys.path 引入（Blender --python 只跑单文件）。
坐标约定：Z 向上、物体正面朝 -Y（导出 glTF 后即 Godot 中朝 +Z），原点在底面中心。
"""
import bpy
import bmesh
import math
import os

import numpy as np
from mathutils import Matrix, Vector


def V(x, y, z):
    return Vector((x, y, z))


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ================= 程序化贴图（numpy） =================

def smooth_noise(u, v, freq, seed):
    """可平铺的值噪声（双线性 + smoothstep），u/v ∈ [0,1)。"""
    rng = np.random.default_rng(seed)
    g = rng.random((freq + 1, freq + 1))
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    x = u * freq
    y = v * freq
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = g[y0, x0] * (1 - fx) + g[y0, x0 + 1] * fx
    b = g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def fbm(u, v, base, octaves, seed):
    out = np.zeros_like(u)
    amp = 0.5
    tot = 0.0
    for o in range(octaves):
        out += smooth_noise(u, v, base * (2 ** o), seed + o) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def image(name, size, fn):
    """fn(u, v) -> (H,W,3) RGB，写成打包进 glb 的 PNG。"""
    img = bpy.data.images.new(name, size, size, alpha=False)
    u, v = np.meshgrid(np.linspace(0, 1, size, endpoint=False),
                       np.linspace(0, 1, size, endpoint=False))
    rgb = np.clip(fn(u, v), 0.0, 1.0)
    rgba = np.concatenate([rgb, np.ones((size, size, 1))], axis=2)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.file_format = "PNG"
    img.pack()
    return img


def tint(t, col):
    """灰阶 t (H,W) × 颜色 → RGB"""
    return np.stack([t * col[0], t * col[1], t * col[2]], axis=2)


def tex_plaster(u, v):
    n = fbm(u, v, 4, 4, 101)
    fine = smooth_noise(u, v, 96, 7)
    cracks = np.abs(fbm(u, v, 6, 3, 55) - 0.5)
    t = 0.8 + 0.18 * (n - 0.5) + 0.06 * (fine - 0.5)
    t = np.where(cracks < 0.012, t * 0.72, t)
    return tint(t, (0.86, 0.76, 0.6))


def tex_concrete(u, v):
    n = fbm(u, v, 5, 4, 202)
    pits = smooth_noise(u, v, 128, 9)
    stain = fbm(u, v, 2, 2, 17)
    t = 0.72 + 0.16 * (n - 0.5) - 0.12 * np.maximum(stain - 0.6, 0) + 0.05 * (pits - 0.5)
    t = np.where(pits > 0.93, t * 0.8, t)
    return tint(t, (0.78, 0.77, 0.74))


def tex_burlap(u, v):
    wx = 0.5 + 0.5 * np.sin(u * 2 * math.pi * 48)
    wy = 0.5 + 0.5 * np.sin(v * 2 * math.pi * 48)
    weave = 0.82 + 0.1 * np.where((np.floor(u * 48) + np.floor(v * 48)) % 2 == 0, wx, wy)
    dirt = fbm(u, v, 4, 3, 303)
    t = weave * (0.85 + 0.25 * (dirt - 0.5))
    return tint(t, (0.78, 0.7, 0.52))


def tex_rust(u, v):
    n = fbm(u, v, 5, 4, 404)
    blot = fbm(u, v, 3, 3, 41)
    base = np.stack([0.42 + 0.2 * n, 0.24 + 0.12 * n, 0.14 + 0.06 * n], axis=2)
    burnt = np.stack([0.12 + 0.08 * n] * 3, axis=2)
    k = np.clip((blot - 0.45) * 4.0, 0, 1)[..., None]
    return base * (1 - k) + burnt * k


def tex_paint_gray(u, v):
    """集装箱/油桶漆面（灰阶，Godot 端按实例染色）：刮擦 + 锈斑"""
    n = fbm(u, v, 6, 3, 505)
    rust = fbm(u, v, 4, 4, 51)
    t = 0.86 + 0.1 * (n - 0.5)
    t = np.where(rust > 0.66, t * 0.62, t)
    return np.stack([t, t, t], axis=2)


def tex_tank(u, v):
    n = fbm(u, v, 5, 3, 606)
    streak = smooth_noise(u * 40.0 % 1.0, v * 0.5, 8, 61)
    t = 0.9 + 0.06 * (n - 0.5) - 0.18 * np.maximum(streak - 0.7, 0) * (v > 0.3)
    return tint(t, (0.86, 0.86, 0.84))


def tex_wood(u, v):
    plank = np.floor(v * 6)
    grain = smooth_noise(u * 0.5, v * 6 % 1.0, 32, 707) * 0.5 + 0.5 * np.sin(u * 60 + plank * 3)
    gap = (v * 6 % 1.0) < 0.04
    t = 0.72 + 0.12 * (grain - 0.5) + 0.06 * (smooth_noise(u, v, 6, int(8)) - 0.5)
    t = np.where(gap, t * 0.45, t)
    return tint(t, (0.62, 0.46, 0.3))


def tex_rock(u, v):
    n = fbm(u, v, 4, 5, 808)
    cr = np.abs(fbm(u, v, 8, 3, 81) - 0.5)
    t = 0.62 + 0.3 * (n - 0.5)
    t = np.where(cr < 0.02, t * 0.7, t)
    return tint(t, (0.62, 0.56, 0.48))


def tex_canvas(u, v):
    n = fbm(u, v, 5, 3, 909)
    w = 0.97 + 0.03 * np.sin(u * 2 * math.pi * 128) * np.sin(v * 2 * math.pi * 128)
    t = (0.8 + 0.15 * (n - 0.5)) * w
    return tint(t, (0.46, 0.47, 0.36))


def tex_bark(u, v):
    n = fbm(u * 3 % 1.0, v, 8, 3, 111)
    t = 0.55 + 0.35 * (n - 0.5) + 0.1 * np.sin(u * 2 * math.pi * 24)
    return tint(t, (0.3, 0.25, 0.2))


# ================= 材质 =================

_MATS = {}


def mat(name, color=(1, 1, 1), rough=0.9, metal=0.0, tex_fn=None, tex_size=256):
    """同名复用；tex_fn 给定时贴图直连 Base Color（glTF 只认这种接法）"""
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if tex_fn is not None:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image(name.lower() + "_tex", tex_size, tex_fn)
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    _MATS[name] = m
    return m


# ================= bmesh 基本体 =================

def box(bm, center, size, rot=(0, 0, 0), bevel=0.0, mat_i=0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]
    bmesh.ops.scale(bm, vec=size, verts=vs)
    if any(rot):
        bmesh.ops.rotate(bm, cent=V(0, 0, 0), verts=vs,
                         matrix=Matrix.Rotation(rot[2], 3, "Z") @ Matrix.Rotation(rot[1], 3, "Y")
                         @ Matrix.Rotation(rot[0], 3, "X"))
    bmesh.ops.translate(bm, vec=center, verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mat_i
    if bevel > 0:
        # 倒角会替换原顶点：材质先赋到原面，再补给新生成的倒角面
        edges = list({e for v in vs for e in v.link_edges})
        res = bmesh.ops.bevel(bm, geom=edges + vs, offset=bevel, segments=1, affect="EDGES")
        for f in res["faces"]:
            f.material_index = mat_i
    return vs


def cyl(bm, center, r, depth, axis="Z", segs=16, r2=None, mat_i=0, caps=True):
    res = bmesh.ops.create_cone(bm, cap_ends=caps, segments=segs, radius1=r,
                                radius2=r if r2 is None else r2, depth=depth)
    vs = res["verts"]
    if axis == "Y":
        bmesh.ops.rotate(bm, cent=V(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=vs)
    elif axis == "X":
        bmesh.ops.rotate(bm, cent=V(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=vs)
    bmesh.ops.translate(bm, vec=center, verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mat_i
    return vs


def sphere(bm, center, radius, scale=(1, 1, 1), segs=(12, 8), mat_i=0):
    res = bmesh.ops.create_uvsphere(bm, u_segments=segs[0], v_segments=segs[1], radius=radius)
    vs = res["verts"]
    bmesh.ops.scale(bm, vec=scale, verts=vs)
    bmesh.ops.translate(bm, vec=center, verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mat_i
    return vs


def wall_openings(bm, along_x, center, length, height, thick, openings, mat_i=0):
    """带门窗洞的墙：openings = [(沿墙偏移, 底高, 宽, 高), ...]，用盒子拼出洞口四周。
    along_x=True 时墙沿 X 延伸（前后墙），否则沿 Y（侧墙）。"""
    ops = sorted(openings, key=lambda o: o[0])
    def put(a0, a1, z0, z1):
        if a1 - a0 < 0.01 or z1 - z0 < 0.01:
            return
        mid = (a0 + a1) * 0.5
        c = center + (V(mid, 0, (z0 + z1) * 0.5) if along_x else V(0, mid, (z0 + z1) * 0.5))
        sz = V(a1 - a0, thick, z1 - z0) if along_x else V(thick, a1 - a0, z1 - z0)
        box(bm, c, sz, mat_i=mat_i)
    a = -length * 0.5
    for off, bot, w, h in ops:
        put(a, off - w * 0.5, 0, height)            # 洞口左侧整段
        put(off - w * 0.5, off + w * 0.5, 0, bot)   # 窗台以下
        put(off - w * 0.5, off + w * 0.5, bot + h, height)   # 过梁以上
        a = off + w * 0.5
    put(a, length * 0.5, 0, height)


def new_object(name, build_fn, mats):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build_fn(bm)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(m)
    return ob


def uv_box(ob, scale=0.5):
    """按世界尺寸做盒投影 UV：scale = 每米贴图重复次数（贴图不随物体大小拉伸）"""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                uv[li].uv = (co.y * scale, co.z * scale)
            elif ax == 1:
                uv[li].uv = (co.x * scale, co.z * scale)
            else:
                uv[li].uv = (co.x * scale, co.y * scale)


def flat_shade(ob):
    for p in ob.data.polygons:
        p.use_smooth = False


def export_glb(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_animations=False, export_yup=True,
                              export_image_format="AUTO")
