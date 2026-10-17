"""烽火地带 · 写实棕榈（美术写实化第二轮）：弯干 + 叶痕环 + 拱垂羽叶 + 下垂枯叶。

  /Applications/Blender.app/Contents/MacOS/Blender -b --python make_palm.py -- <out.glb> [preview.png]

树干贴 Poly Haven CC0 树皮（bark_brown_02）；羽叶贴图程序生成（中脉 + 两侧斜向
小叶 + 透明缝隙，RGBA），游戏端材质改 alpha scissor + 双面。
坐标：Z 向上，原点在树干底面中心，总高约 6.0 m（游戏里按每株高度缩放）。
"""
import bpy
import bmesh
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "..", "..", "assets", "pbr", "tex")
H = 6.0           # 树干高
SEGS_V = 36       # 树干竖向段
SEGS_R = 14       # 树干周向段


def load_img(rel, non_color=False):
    img = bpy.data.images.load(os.path.join(TEX, rel), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def tinted(rel, tint, name):
    src = load_img(rel)
    w, h = src.size
    px = np.empty(w * h * 4, dtype=np.float32)
    src.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    px[:, :3] *= np.array(tint, dtype=np.float32)
    out = bpy.data.images.new(name, w, h)
    out.pixels.foreach_set(px.reshape(-1))
    out.file_format = "JPEG"
    out.pack()
    return out


def frond_image(name, dead=False):
    """羽叶贴图（u 沿叶长 0→1，v 横向 0→1，中脉在 v=0.5）：两侧斜向线状小叶，
    小叶间透明；颜色由叶基黄绿渐变到叶尖暗橄榄，dead=True 为枯褐"""
    W, Hh = 512, 128
    u = np.linspace(0, 1, W)[None, :]
    v = np.linspace(0, 1, Hh)[:, None]
    dv = np.abs(v - 0.5) * 2.0                    # 离中脉距离 0..1
    width = np.clip(0.15 + 0.85 * np.sin(np.pi * np.clip(u * 1.05, 0, 1)) ** 0.7, 0, 1)
    # 小叶：沿 u 方向周期排布、向叶尖斜伸（u 偏移随 dv 增大）
    phase = (u * 46.0 - dv * 3.2) % 1.0
    leaflet = (phase < 0.42) & (dv < width)
    rachis = dv < 0.035
    alpha = (leaflet | rachis).astype(np.float32)
    # 小叶端头不规则：随机咬缺
    rng = np.random.default_rng(7 if not dead else 11)
    jag = rng.random((1, W)) * 0.12
    alpha *= (dv < width - jag).astype(np.float32) + rachis
    alpha = np.clip(alpha, 0, 1)
    if dead:
        base = np.array([0.42, 0.33, 0.2])
        tip = np.array([0.3, 0.24, 0.15])
    else:
        base = np.array([0.36, 0.42, 0.18])
        tip = np.array([0.2, 0.27, 0.12])
    col = base[None, None, :] * (1 - u[..., None]) + tip[None, None, :] * u[..., None]
    col = col * (0.85 + 0.3 * rng.random((Hh, W, 1)))      # 小叶间明暗
    col = np.where(rachis[..., None], col * 1.25 + 0.05, col)
    rgba = np.concatenate([np.clip(col, 0, 1), alpha[..., None]], axis=2).astype(np.float32)
    img = bpy.data.images.new(name, W, Hh, alpha=True)
    img.pixels.foreach_set(rgba.reshape(-1))
    img.file_format = "PNG"
    img.pack()
    return img


def mat_bark():
    m = bpy.data.materials.new("Bark")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t_d = nt.nodes.new("ShaderNodeTexImage")
    t_d.image = tinted("bark_brown_02/bark_brown_02_diff_1k.jpg", (0.95, 0.88, 0.78), "palm_bark_diff")
    nt.links.new(t_d.outputs["Color"], bsdf.inputs["Base Color"])
    t_n = nt.nodes.new("ShaderNodeTexImage")
    t_n.image = load_img("bark_brown_02/bark_brown_02_nor_gl_1k.jpg", True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(t_n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    t_a = nt.nodes.new("ShaderNodeTexImage")
    t_a.image = load_img("bark_brown_02/bark_brown_02_arm_1k.jpg", True)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(t_a.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return m


def mat_frond(name, img):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.65
    return m


def trunk_point(t, lean):
    """树干中心线：微弯（顶部偏移 lean 米，二次曲线）"""
    return (lean * t * t, 0.0, H * t)


def build_trunk(bm, uv_layer, lean):
    rings = []
    for i in range(SEGS_V + 1):
        t = i / SEGS_V
        cx, cy, cz = trunk_point(t, lean)
        r = 0.25 - 0.08 * t                          # 基部粗、顶部细
        r *= 1.0 + 0.07 * max(0.0, math.sin(t * SEGS_V * math.pi * 0.5))  # 叶痕环凸起
        if t < 0.06:
            r *= 1.0 + (0.06 - t) * 4.0               # 根部外扩
        ring = []
        for j in range(SEGS_R):
            a = 2 * math.pi * j / SEGS_R
            ring.append(bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), cz)))
        rings.append(ring)
    for i in range(SEGS_V):
        for j in range(SEGS_R):
            j2 = (j + 1) % SEGS_R
            f = bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
            f.material_index = 0
            f.smooth = True
            for loop, (uu, vv) in zip(f.loops, ((j, i), (j + 1, i), (j + 1, i + 1), (j, i + 1))):
                loop[uv_layer].uv = (uu / SEGS_R * 1.5, vv / SEGS_V * H / 1.2)


def build_frond(bm, uv_layer, base, yaw, pitch, length, mat_i, droop):
    """一片羽叶：沿叶长 12 段的折 V 条带（中脉略高，两翼下折 22°）"""
    segs = 12
    ca, sa = math.cos(yaw), math.sin(yaw)
    prev = None
    for i in range(segs + 1):
        t = i / segs
        # 叶轴：先按 pitch 上扬，再随长度下垂
        horiz = length * t
        rise = horiz * math.tan(pitch) - droop * length * t * t
        cx = base[0] + ca * horiz
        cy = base[1] + sa * horiz
        cz = base[2] + rise
        half_w = 0.55 * math.sin(math.pi * min(1.0, t * 1.05) + 0.12) + 0.03
        fold = half_w * math.sin(math.radians(22))
        side = (-sa, ca)
        mid = bm.verts.new((cx, cy, cz))
        l = bm.verts.new((cx + side[0] * half_w, cy + side[1] * half_w, cz - fold))
        r = bm.verts.new((cx - side[0] * half_w, cy - side[1] * half_w, cz - fold))
        cur = (l, mid, r, t)
        if prev is not None:
            t0 = prev[3]
            for quad, uvs in (((prev[0], prev[1], cur[1], cur[0]),
                               ((t0, 0.0), (t0, 0.5), (t, 0.5), (t, 0.0))),
                              ((prev[1], prev[2], cur[2], cur[1]),
                               ((t0, 0.5), (t0, 1.0), (t, 1.0), (t, 0.5)))):
                f = bm.faces.new(quad)
                f.material_index = mat_i
                for loop, uvv in zip(f.loops, uvs):
                    loop[uv_layer].uv = uvv
        prev = cur


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else os.path.join(HERE, "..", "..", "assets", "pbr", "models",
                                            "palm", "palm.glb")
    preview = argv[1] if len(argv) > 1 else ""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = [mat_bark(), mat_frond("Frond", frond_image("palm_frond")),
            mat_frond("FrondDead", frond_image("palm_frond_dead", dead=True))]
    me = bpy.data.meshes.new("palm")
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    lean = 0.35
    build_trunk(bm, uv, lean)
    top = trunk_point(1.0, lean)
    # 活叶 ×16：两圈错开，内圈上扬、外圈平展下垂
    for k in range(16):
        yaw = 2 * math.pi * k / 16 + (0.2 if k % 2 else 0.0)
        inner = k % 2 == 0
        build_frond(bm, uv, (top[0], top[1], top[2] - 0.05), yaw,
                    math.radians(36 if inner else 14), 3.0 if inner else 3.5, 1,
                    0.85 if inner else 1.15)
    # 枯叶 ×6：贴着树干下垂（真实棕榈冠下的干枯叶裙）
    for k in range(6):
        yaw = 2 * math.pi * k / 6 + 0.4
        build_frond(bm, uv, (top[0], top[1], top[2] - 0.35), yaw,
                    math.radians(-55), 2.2, 2, 0.15)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("palm", me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(m)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
                              export_yup=True, export_animations=False,
                              export_image_format="AUTO")
    print("[palm] tris=%d -> %s" % (sum(len(p.vertices) - 2 for p in me.polygons), out))
    if preview:
        scn = bpy.context.scene
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scn.collection.objects.link(cam)
        cam.location = (9.0, -9.0, 4.5)
        from mathutils import Vector
        cam.rotation_euler = (Vector((0, 0, 3.5)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.camera = cam
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = 4.0
        sun.rotation_euler = (math.radians(45), 0, math.radians(30))
        scn.collection.objects.link(sun)
        world = bpy.data.worlds.new("w")
        world.color = (0.5, 0.6, 0.75)
        scn.world = world
        scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [
            e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
        ] else "BLENDER_EEVEE"
        scn.render.resolution_x = 640
        scn.render.resolution_y = 640
        scn.render.filepath = preview
        bpy.ops.render.render(write_still=True)


main()
