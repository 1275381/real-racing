"""烽火地带 · 写实厢式货车（美术写实化第一轮）：
平头驾驶室 + 厢式货箱 + 三轴六轮，贴 Poly Haven CC0 实拍 PBR 贴图（颜色/法线/ARM）。

  /Applications/Blender.app/Contents/MacOS/Blender -b --python make_truck.py -- <out.glb> [preview.png]

坐标（Blender，Z 向上）：长轴 X、车头朝 +X、原点在车身中线地面；导出 glTF 后
Godot 中同样长轴 X、车头 +X（与 hd_dam_base.gd 原方块卡车同朝向、同占地 7.0×2.4 m）。
"""
import bpy
import bmesh
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "godot", "tools", "blender"))
from bl_common import V, reset_scene, box, cyl, new_object, uv_box, export_glb  # noqa: E402

TEX = os.path.join(HERE, "..", "..", "assets", "pbr", "tex")


def load_img(rel, non_color=False):
    img = bpy.data.images.load(os.path.join(TEX, rel), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def tinted(rel, tint, name):
    """颜色贴图乘设计色（glTF 只认贴图直连 Base Color，乘色只能烘进贴图）"""
    src = load_img(rel)
    w, h = src.size
    px = np.empty(w * h * 4, dtype=np.float32)
    src.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    px[:, 0] *= tint[0]
    px[:, 1] *= tint[1]
    px[:, 2] *= tint[2]
    out = bpy.data.images.new(name, w, h)
    out.pixels.foreach_set(px.reshape(-1))
    out.file_format = "JPEG"
    out.pack()
    return out


def pbr_mat(name, diff_img, set_name, normal_strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t_d = nt.nodes.new("ShaderNodeTexImage")
    t_d.image = diff_img
    nt.links.new(t_d.outputs["Color"], bsdf.inputs["Base Color"])
    t_n = nt.nodes.new("ShaderNodeTexImage")
    t_n.image = load_img("%s/%s_nor_gl_1k.jpg" % (set_name, set_name), True)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = normal_strength
    nt.links.new(t_n.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    t_a = nt.nodes.new("ShaderNodeTexImage")
    t_a.image = load_img("%s/%s_arm_1k.jpg" % (set_name, set_name), True)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(t_a.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return m


def plain_mat(name, color, rough, metal=0.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    return m


# 材质槽位
CAB, CARGO, STEEL, PLATE, RIM, RUBBER, GLASS, LAMP, TAIL, TRIM = range(10)


def build(bm):
    # ---------- 底盘 ----------
    for sy in (-0.45, 0.45):
        box(bm, V(0.2, sy, 0.78), V(7.0, 0.12, 0.22), mat_i=STEEL)
    for x in (-2.6, -1.2, 0.6, 2.4):
        box(bm, V(x, 0, 0.78), V(0.1, 1.0, 0.16), mat_i=STEEL)   # 横梁
    # ---------- 货箱 ----------
    box(bm, V(-0.45, 0, 0.92), V(5.25, 2.46, 0.12), mat_i=PLATE)          # 箱底板
    box(bm, V(-0.45, 0, 1.97), V(5.1, 2.40, 2.0), bevel=0.02, mat_i=CARGO)
    for i in range(10):                                                    # 侧立柱
        x = -2.95 + i * (5.0 / 9.0)
        box(bm, V(x, 0, 1.97), V(0.07, 2.46, 2.02), mat_i=TRIM)
    for sy in (-1.22, 1.22):
        box(bm, V(-0.45, sy, 2.98), V(5.15, 0.06, 0.07), mat_i=TRIM)      # 顶边梁
        box(bm, V(-0.45, sy, 0.98), V(5.15, 0.06, 0.07), mat_i=TRIM)      # 底边梁
    box(bm, V(-3.02, 0, 1.97), V(0.04, 2.44, 2.04), mat_i=CARGO)           # 后门板
    box(bm, V(-3.05, 0, 1.97), V(0.02, 0.03, 1.98), mat_i=TRIM)            # 门缝
    for sy in (-0.85, -0.35, 0.35, 0.85):                                  # 锁杆
        cyl(bm, V(-3.08, sy, 1.97), 0.022, 1.95, axis="Z", segs=8, mat_i=STEEL)
        box(bm, V(-3.1, sy, 1.55), V(0.05, 0.14, 0.04), mat_i=STEEL)        # 把手
    for sy in (-1.0, 1.0):
        box(bm, V(-3.06, sy, 1.02), V(0.05, 0.26, 0.12), mat_i=TAIL)       # 尾灯
        box(bm, V(-2.95, sy, 0.45), V(0.02, 0.5, 0.5), mat_i=RUBBER)       # 挡泥皮
    box(bm, V(-3.1, 0, 0.65), V(0.12, 2.3, 0.15), mat_i=PLATE)             # 后防撞梁
    # ---------- 驾驶室 ----------
    box(bm, V(3.1, 0, 1.86), V(1.7, 2.36, 1.92), bevel=0.09, mat_i=CAB)
    box(bm, V(3.05, 0, 2.86), V(1.5, 2.2, 0.12), bevel=0.04, mat_i=CAB)     # 顶盖
    box(bm, V(3.965, 0, 2.2), V(0.04, 2.02, 0.86), bevel=0.02, mat_i=GLASS)  # 风挡
    box(bm, V(3.975, 0, 2.2), V(0.03, 0.05, 0.88), mat_i=TRIM)              # 风挡中柱
    for sy in (-1.185, 1.185):
        box(bm, V(3.45, sy, 2.25), V(0.8, 0.02, 0.62), mat_i=GLASS)        # 侧窗
        box(bm, V(2.85, sy, 1.7), V(0.02, 0.02, 1.45), mat_i=TRIM)         # 门缝
        box(bm, V(3.0, sy * 1.005, 1.75), V(0.12, 0.03, 0.04), mat_i=STEEL)  # 门把手
        box(bm, V(3.3, sy, 0.68), V(0.55, 0.16, 0.06), mat_i=PLATE)        # 上车踏板
        box(bm, V(3.12, sy * 0.93, 1.1), V(1.1, 0.34, 0.06), mat_i=TRIM)    # 前轮挡泥板
        box(bm, V(3.86, sy * 1.06, 2.25), V(0.04, 0.22, 0.04), mat_i=STEEL)  # 后视镜臂
        box(bm, V(3.86, sy * 1.18, 2.12), V(0.06, 0.16, 0.36), mat_i=TRIM)   # 后视镜
    box(bm, V(3.965, 0, 1.4), V(0.03, 1.3, 0.56), mat_i=TRIM)              # 格栅底
    for i in range(5):
        box(bm, V(3.985, 0, 1.2 + i * 0.1), V(0.02, 1.26, 0.035), mat_i=STEEL)
    for sy in (-0.85, 0.85):
        cyl(bm, V(3.97, sy, 1.36), 0.11, 0.07, axis="X", segs=20, mat_i=LAMP)  # 大灯
        box(bm, V(3.97, sy * 1.2, 1.36), V(0.05, 0.14, 0.08), mat_i=TAIL)      # 转向灯
    box(bm, V(4.03, 0, 0.75), V(0.18, 2.4, 0.28), bevel=0.03, mat_i=PLATE)  # 前保险杠
    cyl(bm, V(2.15, 0.95, 2.45), 0.06, 1.7, axis="Z", segs=12, mat_i=STEEL)  # 排气管
    cyl(bm, V(1.2, -1.0, 0.72), 0.28, 1.0, axis="X", segs=20, mat_i=RIM)     # 油箱
    box(bm, V(0.1, 1.0, 0.72), V(0.8, 0.36, 0.4), mat_i=STEEL)               # 电瓶箱
    # ---------- 车轮（前单胎 + 后双轴） ----------
    for wx in (3.1, -1.6, -2.75):
        for sy in (-1.0, 1.0):
            cyl(bm, V(wx, sy, 0.5), 0.5, 0.32, axis="Y", segs=28, mat_i=RUBBER)
            cyl(bm, V(wx, sy * 1.01, 0.5), 0.3, 0.33, axis="Y", segs=20, mat_i=RIM)
            cyl(bm, V(wx, sy * 1.03, 0.5), 0.11, 0.34, axis="Y", segs=12, mat_i=STEEL)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else os.path.join(HERE, "..", "..", "assets", "pbr", "models",
                                            "truck", "truck.glb")
    preview = argv[1] if len(argv) > 1 else ""
    reset_scene()
    mats = [
        pbr_mat("Cab", tinted("rusty_metal_02/rusty_metal_02_diff_1k.jpg", (0.62, 0.14, 0.1),
                              "truck_cab_diff"), "rusty_metal_02"),
        pbr_mat("Cargo", tinted("container_side/container_side_gray_diff_1k.jpg",
                                (1.25, 1.02, 0.66), "truck_cargo_diff"), "container_side"),
        pbr_mat("Steel", tinted("rusty_metal_02/rusty_metal_02_diff_1k.jpg", (0.22, 0.22, 0.23),
                                "truck_steel_diff"), "rusty_metal_02"),
        pbr_mat("Plate", load_img("metal_plate/metal_plate_diff_1k.jpg"), "metal_plate"),
        pbr_mat("Rim", tinted("rusty_metal_02/rusty_metal_02_diff_1k.jpg", (0.5, 0.5, 0.5),
                              "truck_rim_diff"), "rusty_metal_02"),
        plain_mat("Rubber", (0.035, 0.035, 0.038), 0.92),
        plain_mat("Glass", (0.03, 0.04, 0.05), 0.06, 0.3),
        plain_mat("Lamp", (0.9, 0.88, 0.8), 0.15, 0.0, emit=(0.5, 0.48, 0.4)),
        plain_mat("Tail", (0.6, 0.05, 0.03), 0.3, 0.0, emit=(0.3, 0.02, 0.01)),
        plain_mat("Trim", (0.07, 0.075, 0.08), 0.6, 0.4),
    ]
    ob = new_object("truck", build, mats)
    uv_box(ob, scale=0.5)
    # 圆柱件（轮胎/轮辋/油箱/排气管）平滑着色，其余保持硬边
    # 只平滑胎面/轮辋侧面；端面（法线沿轴 Y）保持平——平滑端面会把法线
    # 拉歪，轮胎侧面一圈发白
    smooth_mats = {RUBBER, RIM}
    for p in ob.data.polygons:
        p.use_smooth = p.material_index in smooth_mats and abs(p.normal.y) < 0.9
    export_glb_jpeg(ob, out)
    if preview:
        render_preview(ob, preview)
    print("[truck] tris=%d -> %s" % (sum(len(p.vertices) - 2 for p in ob.data.polygons), out))


def export_glb_jpeg(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_animations=False, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=88)


def render_preview(ob, path):
    scn = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scn.collection.objects.link(cam)
    cam.location = (9.5, -7.5, 4.2)
    direction = V(0, 0, 1.4) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.0
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), 0, math.radians(30))
    scn.collection.objects.link(so)
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [
        e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
    ] else "BLENDER_EEVEE"
    scn.render.resolution_x = 960
    scn.render.resolution_y = 540
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)


main()
