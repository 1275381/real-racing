"""大战场士兵模型生成器（Blender 5.x 后台脚本）。

用法（在 godot/ 目录下）：
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/make_soldier.py \
      -- assets/battle/soldier.glb [预览图目录]

产出一个带骨骼与动画的写实低模士兵（约 3~5 千三角面）：
- 身体：蒙皮修改器（Skin）沿骨架生成连续躯体 + 一级细分，自动权重绑定
- 装备：头盔、护目镜、面罩、防弹背心 + 弹匣包、背包、腰带、护膝、步枪
- 材质：Skin / Uniform（迷彩灰阶贴图，Godot 按阵营染色）/ Gear / Dark / Weapon
- 持枪：步枪挂在 weapon 骨（胸骨子骨）上，双手用 IK 抓握把与护木，
  导出时 glTF 按帧采样把 IK 结果烘进骨骼动画
- 动画：idle_loop / walk_loop / run_loop / aim_loop / death
坐标：Blender Z 向上、人物面朝 -Y；导出 glTF 后即 Godot 中面朝 +Z。
"""
import bpy
import bmesh
import math
import os
import sys

import numpy as np
from mathutils import Matrix, Quaternion, Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGV[0] if ARGV else "soldier.glb")
PREVIEW = os.path.abspath(ARGV[1]) if len(ARGV) > 1 else ""
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS


def V(x, y, z):
    return Vector((x, y, z))


# ============================================================
#  骨架（A 字站姿：双臂下垂 45°）
# ============================================================
# 左侧 = +X（人物自己的左手边，人物面朝 -Y）
J = {
    "hips": V(0, 0.0, 0.96), "spine": V(0, 0.0, 1.08), "chest": V(0, 0.0, 1.24),
    "neck": V(0, 0.0, 1.45), "head": V(0, -0.01, 1.555), "head_end": V(0, -0.01, 1.78),
}
for s, sx in (("L", 1.0), ("R", -1.0)):
    J["shoulder." + s] = V(0.03 * sx, 0.0, 1.42)
    J["upper_arm." + s] = V(0.175 * sx, 0.01, 1.425)
    J["forearm." + s] = V(0.37 * sx, 0.02, 1.225)
    J["hand." + s] = V(0.545 * sx, 0.0, 1.05)
    J["hand_end." + s] = V(0.615 * sx, -0.01, 0.985)
    J["thigh." + s] = V(0.095 * sx, 0.0, 0.94)
    J["shin." + s] = V(0.105 * sx, 0.01, 0.52)
    J["foot." + s] = V(0.11 * sx, 0.035, 0.09)
    J["toe." + s] = V(0.115 * sx, -0.10, 0.03)
    J["toe_end." + s] = V(0.12 * sx, -0.19, 0.03)

arm_data = bpy.data.armatures.new("SoldierRig")
rig = bpy.data.objects.new("Soldier", arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones


def add_bone(name, head, tail, parent=None, connect=False, deform=True, roll=0.0):
    b = eb.new(name)
    b.head = head
    b.tail = tail
    b.roll = roll
    b.use_deform = deform
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b


add_bone("hips", J["hips"], J["spine"])
add_bone("spine", J["spine"], J["chest"], "hips", True)
add_bone("chest", J["chest"], J["neck"], "spine", True)
add_bone("neck", J["neck"], J["head"], "chest", True)
add_bone("head", J["head"], J["head_end"], "neck", True)
for s in ("L", "R"):
    add_bone("shoulder." + s, J["shoulder." + s], J["upper_arm." + s], "chest")
    add_bone("upper_arm." + s, J["upper_arm." + s], J["forearm." + s], "shoulder." + s, True)
    add_bone("forearm." + s, J["forearm." + s], J["hand." + s], "upper_arm." + s, True)
    add_bone("hand." + s, J["hand." + s], J["hand_end." + s], "forearm." + s, True)
    add_bone("thigh." + s, J["thigh." + s], J["shin." + s], "hips")
    add_bone("shin." + s, J["shin." + s], J["foot." + s], "thigh." + s, True)
    add_bone("foot." + s, J["foot." + s], J["toe." + s], "shin." + s, True)
    add_bone("toe." + s, J["toe." + s], J["toe_end." + s], "foot." + s, True)

# 武器骨：握把处，沿 -Y（枪口方向）；挂在胸骨下，跟随上身
GRIP = V(-0.125, -0.25, 1.47)         # 静置姿态 = 抵肩瞄准位的握把（贴腮高度，枪托抵右肩）
add_bone("weapon", GRIP, GRIP + V(0, -0.12, 0), "chest")
# IK 目标（不参与蒙皮、不导出）：挂在武器骨下，手腕落点
IKR = GRIP + V(0.0, 0.06, -0.05)       # 右手腕：握把后下方
IKL = GRIP + V(0.07, -0.28, -0.05)     # 左手腕：护木下方
add_bone("ik_hand.R", IKR, IKR + V(0, 0, 0.06), "weapon", deform=False)
add_bone("ik_hand.L", IKL, IKL + V(0, 0, 0.06), "weapon", deform=False)
# 肘部极向目标：挂在胸骨下（右肘外下，左肘下外）
add_bone("pole.R", V(-0.55, 0.10, 1.05), V(-0.55, 0.10, 1.10), "chest", deform=False)
add_bone("pole.L", V(0.35, -0.15, 0.95), V(0.35, -0.15, 1.00), "chest", deform=False)
bpy.ops.object.mode_set(mode="OBJECT")

POLE_DEF = {"R": "40", "L": "90"}      # 右肘略外张下垂、左肘在护木下（按预览图选定）
bpy.ops.object.mode_set(mode="POSE")
pb = rig.pose.bones
for s in ("R", "L"):
    ik = pb["forearm." + s].constraints.new("IK")
    ik.target = rig
    ik.subtarget = "ik_hand." + s
    ik.pole_target = rig
    ik.pole_subtarget = "pole." + s
    ik.pole_angle = math.radians(float(os.environ.get("POLE_" + s, POLE_DEF[s])))
    ik.chain_count = 2
bpy.ops.object.mode_set(mode="OBJECT")


# ============================================================
#  身体：Skin 修改器沿骨架包出躯体
# ============================================================
# 每个点：(名字, 坐标, (半径x, 半径y))；边按骨架连接
P = []
E = []


def pt(name, co, rx, ry=None):
    P.append((name, co, (rx, ry if ry is not None else rx)))
    return len(P) - 1


def chain(*idx):
    for a, b in zip(idx, idx[1:]):
        E.append((a, b))


pelvis = pt("pelvis", V(0, 0.005, 0.93), 0.17, 0.12)
waist = pt("waist", V(0, 0.0, 1.06), 0.155, 0.11)
belly = pt("belly", V(0, -0.005, 1.17), 0.16, 0.115)
chest = pt("chest", V(0, -0.005, 1.30), 0.18, 0.125)
upchest = pt("upchest", V(0, 0.0, 1.40), 0.175, 0.11)
neck0 = pt("neck0", V(0, 0.0, 1.47), 0.068, 0.066)
neck1 = pt("neck1", V(0, -0.005, 1.535), 0.062, 0.064)
head0 = pt("head0", V(0, -0.012, 1.60), 0.072, 0.085)
head1 = pt("head1", V(0, -0.012, 1.67), 0.085, 0.10)
head2 = pt("head2", V(0, -0.008, 1.735), 0.07, 0.082)
head3 = pt("head3", V(0, -0.005, 1.775), 0.03, 0.035)
chain(pelvis, waist, belly, chest, upchest, neck0, neck1, head0, head1, head2, head3)
for s, sx in (("L", 1.0), ("R", -1.0)):
    sh = pt("sh" + s, V(0.175 * sx, 0.01, 1.415), 0.072, 0.068)
    ua = pt("ua" + s, V(0.27 * sx, 0.015, 1.32), 0.062, 0.06)
    el = pt("el" + s, V(0.37 * sx, 0.02, 1.225), 0.052, 0.052)
    fa = pt("fa" + s, V(0.46 * sx, 0.012, 1.137), 0.05, 0.047)
    wr = pt("wr" + s, V(0.545 * sx, 0.0, 1.05), 0.036, 0.03)
    hm = pt("hm" + s, V(0.585 * sx, -0.005, 1.01), 0.042, 0.022)
    ht = pt("ht" + s, V(0.62 * sx, -0.01, 0.975), 0.03, 0.017)
    chain(upchest, sh, ua, el, fa, wr, hm, ht)
    hp = pt("hp" + s, V(0.095 * sx, 0.005, 0.90), 0.1, 0.1)      # 作战裤：宽松
    th = pt("th" + s, V(0.102 * sx, 0.01, 0.72), 0.09, 0.09)
    kn = pt("kn" + s, V(0.106 * sx, 0.01, 0.52), 0.068, 0.07)
    cf = pt("cf" + s, V(0.108 * sx, 0.02, 0.33), 0.066, 0.068)
    an = pt("an" + s, V(0.11 * sx, 0.03, 0.14), 0.055, 0.058)   # 靴筒
    fm = pt("fm" + s, V(0.113 * sx, -0.05, 0.065), 0.056, 0.042)
    tp = pt("tp" + s, V(0.118 * sx, -0.17, 0.05), 0.048, 0.034)
    chain(pelvis, hp, th, kn, cf, an, fm, tp)

me = bpy.data.meshes.new("Body")
me.from_pydata([p[1] for p in P], E, [])
body = bpy.data.objects.new("Body", me)
scene.collection.objects.link(body)
skin = body.modifiers.new("Skin", "SKIN")
skin.branch_smoothing = 0.6
skin.use_smooth_shade = True
for i, p in enumerate(P):
    sv = me.skin_vertices[0].data[i]
    sv.radius = p[2]
    sv.use_root = i == pelvis
sub = body.modifiers.new("Sub", "SUBSURF")
sub.levels = 1
sub.render_levels = 1
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.convert(target="MESH")


# ============================================================
#  材质 + 程序化贴图
# ============================================================
def noise_img(name, size, fn):
    """fn(u, v) -> RGB ndarray (size,size,3)，写成打包 PNG 贴图。"""
    img = bpy.data.images.new(name, size, size, alpha=False)
    u, v = np.meshgrid(np.linspace(0, 1, size, endpoint=False),
                       np.linspace(0, 1, size, endpoint=False))
    rgb = np.clip(fn(u, v), 0.0, 1.0)
    rgba = np.concatenate([rgb, np.ones((size, size, 1))], axis=2)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.file_format = "PNG"
    img.pack()
    return img


def smooth_noise(u, v, freq, seed):
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


def camo(u, v):
    # 三色林地迷彩（灰阶，Godot 按阵营着色）：两层低频噪声阈值分块 + 织物细纹
    n1 = smooth_noise(u, v, 6, 11) * 0.65 + smooth_noise(u, v, 13, 12) * 0.35
    n2 = smooth_noise(u, v, 7, 21) * 0.6 + smooth_noise(u, v, 17, 22) * 0.4
    tone = np.where(n1 > 0.56, 0.62, 0.9)
    tone = np.where(n2 > 0.6, 0.45, tone)
    weave = 0.96 + 0.04 * np.sin(u * 900.0) * np.sin(v * 900.0)
    grain = 0.95 + 0.1 * smooth_noise(u, v, 64, 5)
    t = tone * weave * grain
    return np.stack([t, t, t], axis=2)


def fabric(u, v):
    t = 0.85 + 0.1 * smooth_noise(u, v, 32, 7) + 0.05 * np.sin(u * 700.0) * np.sin(v * 700.0)
    return np.stack([t, t, t], axis=2)


def make_mat(name, color, rough=0.8, metal=0.0, img=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if img is not None:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = img
        mix = m.node_tree.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["A"].default_value = (*color, 1.0)
        m.node_tree.links.new(tex.outputs["Color"], mix.inputs["B"])
        m.node_tree.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        # glTF 只认「贴图直连 Base Color」：直接连，颜色交给 Godot 端染色
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


CAMO = noise_img("camo", 256, camo)
FABRIC = noise_img("fabric", 128, fabric)
M_SKIN = make_mat("Skin", (0.72, 0.53, 0.42), 0.6)
M_UNI = make_mat("Uniform", (1, 1, 1), 0.9, img=CAMO)
M_GEAR = make_mat("Gear", (1, 1, 1), 0.85, img=FABRIC)
M_DARK = make_mat("Dark", (0.07, 0.07, 0.075), 0.7)
M_WEAP = make_mat("Weapon", (0.09, 0.095, 0.1), 0.45, 0.6)
M_LENS = make_mat("Lens", (0.05, 0.08, 0.1), 0.1, 0.3)
MATS = [M_SKIN, M_UNI, M_GEAR, M_DARK, M_WEAP, M_LENS]
MI = {m.name: i for i, m in enumerate(MATS)}
for m in MATS:
    body.data.materials.append(m)

# 身体按区域分材质：手/靴/脸
bm = bmesh.new()
bm.from_mesh(body.data)
for f in bm.faces:
    c = f.calc_center_median()
    mi = MI["Uniform"]
    if c.z > 1.57:
        mi = MI["Skin"]               # 脸（头盔另盖）
    if abs(c.x) > 0.53 and c.z < 1.07:
        mi = MI["Dark"]               # 手套
    if c.z < 0.2:
        mi = MI["Dark"]               # 军靴
    f.material_index = mi
bm.to_mesh(body.data)
bm.free()


# ============================================================
#  装备（刚性挂骨：单骨权重 1）
# ============================================================
PARTS = []   # (object, bone)


def part(name, mesh_fn, bone, mat):
    me2 = bpy.data.meshes.new(name)
    bm2 = bmesh.new()
    mesh_fn(bm2)
    bm2.to_mesh(me2)
    bm2.free()
    ob = bpy.data.objects.new(name, me2)
    scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    PARTS.append((ob, bone))
    return ob


def box(bm2, center, size, rot_z=0.0, bevel=0.0):
    r = bmesh.ops.create_cube(bm2, size=1.0)
    verts = r["verts"]
    bmesh.ops.scale(bm2, vec=size, verts=verts)
    if rot_z:
        bmesh.ops.rotate(bm2, cent=V(0, 0, 0), matrix=Matrix.Rotation(rot_z, 3, "Z"), verts=verts)
    bmesh.ops.translate(bm2, vec=center, verts=verts)
    if bevel > 0:
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(bm2, geom=edges + verts, offset=bevel, segments=1, affect="EDGES")


def cyl(bm2, center, r, depth, axis="Z", segs=12, r2=None):
    res = bmesh.ops.create_cone(bm2, cap_ends=True, segments=segs, radius1=r,
                                radius2=r if r2 is None else r2, depth=depth)
    verts = res["verts"]
    if axis == "Y":
        bmesh.ops.rotate(bm2, cent=V(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=verts)
    elif axis == "X":
        bmesh.ops.rotate(bm2, cent=V(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=verts)
    bmesh.ops.translate(bm2, vec=center, verts=verts)


def helmet(bm2):
    res = bmesh.ops.create_uvsphere(bm2, u_segments=16, v_segments=10, radius=1.0)
    verts = res["verts"]
    bmesh.ops.scale(bm2, vec=V(0.118, 0.13, 0.105), verts=verts)
    bmesh.ops.translate(bm2, vec=V(0, 0.0, 1.68), verts=verts)
    bmesh.ops.bisect_plane(bm2, geom=bm2.verts[:] + bm2.edges[:] + bm2.faces[:],
                           plane_co=V(0, 0, 1.655), plane_no=V(0, 0, 1), clear_inner=True)
    edges = [e for e in bm2.edges if e.is_boundary]
    bmesh.ops.holes_fill(bm2, edges=edges)
    # 帽檐后沿与侧耳罩
    box(bm2, V(0, 0.04, 1.66), V(0.21, 0.19, 0.035))


def goggles(bm2):
    box(bm2, V(0, -0.098, 1.69), V(0.15, 0.03, 0.045), bevel=0.008)


def mask(bm2):
    # 下半脸面罩（盖住口鼻，避免低模脸部失真）
    res = bmesh.ops.create_uvsphere(bm2, u_segments=12, v_segments=8, radius=1.0)
    verts = res["verts"]
    bmesh.ops.scale(bm2, vec=V(0.078, 0.088, 0.06), verts=verts)
    bmesh.ops.translate(bm2, vec=V(0, -0.028, 1.625), verts=verts)


def vest(bm2):
    box(bm2, V(0, -0.005, 1.27), V(0.35, 0.265, 0.31), bevel=0.02)
    box(bm2, V(0, -0.14, 1.29), V(0.27, 0.03, 0.27), bevel=0.01)       # 前插板
    for k in range(3):
        box(bm2, V(-0.09 + k * 0.09, -0.165, 1.17), V(0.075, 0.045, 0.12), bevel=0.008)  # 弹匣包
    box(bm2, V(0.14, -0.13, 1.33), V(0.05, 0.04, 0.09), bevel=0.006)   # 电台包
    for sx in (-1, 1):
        box(bm2, V(0.105 * sx, 0.0, 1.43), V(0.07, 0.24, 0.03))        # 肩带


def backpack(bm2):
    box(bm2, V(0, 0.19, 1.28), V(0.28, 0.13, 0.34), bevel=0.025)
    box(bm2, V(0, 0.265, 1.24), V(0.2, 0.04, 0.16), bevel=0.012)
    cyl(bm2, V(0, 0.2, 1.47), 0.045, 0.3, axis="X")                   # 卷好的睡袋


def belt(bm2):
    cyl(bm2, V(0, 0.0, 1.0), 1.0, 0.055, segs=16)
    bmesh.ops.scale(bm2, vec=V(0.152, 0.112, 1.0), verts=bm2.verts[:])
    box(bm2, V(0.13, -0.02, 0.99), V(0.05, 0.07, 0.08), bevel=0.006)
    box(bm2, V(-0.13, 0.03, 0.97), V(0.05, 0.06, 0.1), bevel=0.006)


def kneepad(sx):
    def fn(bm2):
        box(bm2, V(0.105 * sx, -0.055, 0.51), V(0.085, 0.035, 0.1), bevel=0.012)
    return fn


def rifle(bm2):
    g = GRIP
    box(bm2, g + V(0, -0.1, 0.045), V(0.045, 0.3, 0.075), bevel=0.004)     # 机匣
    box(bm2, g + V(0, -0.34, 0.045), V(0.05, 0.22, 0.06), bevel=0.006)     # 护木
    cyl(bm2, g + V(0, -0.56, 0.05), 0.011, 0.26, axis="Y", segs=8)         # 枪管
    cyl(bm2, g + V(0, -0.7, 0.05), 0.018, 0.05, axis="Y", segs=8)          # 消焰器
    box(bm2, g + V(0, -0.02, -0.035), V(0.03, 0.035, 0.1), bevel=0.004)    # 握把
    box(bm2, g + V(0, -0.14, -0.05), V(0.03, 0.06, 0.14), bevel=0.004)     # 弹匣
    box(bm2, g + V(0, 0.16, 0.035), V(0.04, 0.22, 0.07), bevel=0.006)      # 枪托
    box(bm2, g + V(0, 0.28, 0.02), V(0.045, 0.03, 0.12))                   # 托底
    cyl(bm2, g + V(0, -0.1, 0.105), 0.019, 0.14, axis="Y", segs=10)        # 瞄准镜
    box(bm2, g + V(0, -0.1, 0.09), V(0.02, 0.05, 0.03))                    # 镜座


part("Helmet", helmet, "head", M_GEAR)
part("Goggles", goggles, "head", M_LENS)
part("Mask", mask, "head", M_DARK)
part("Vest", vest, "chest", M_GEAR)
part("Backpack", backpack, "chest", M_GEAR)
part("Belt", belt, "hips", M_DARK)
part("KneeL", kneepad(1), "shin.L", M_DARK)
part("KneeR", kneepad(-1), "shin.R", M_DARK)
part("Rifle", rifle, "weapon", M_WEAP)

# 合并成一个网格（每部件先建单骨顶点组）
for ob, bone in PARTS:
    vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    ob.data.materials.clear()

# 身体自动权重（骨热）
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

# 部件材质换成身体材质槽序号后并入
part_mat = {"Helmet": "Gear", "Goggles": "Lens", "Mask": "Dark", "Vest": "Gear",
            "Backpack": "Gear", "Belt": "Dark", "KneeL": "Dark", "KneeR": "Dark",
            "Rifle": "Weapon"}
for ob, bone in PARTS:
    for m in MATS:
        ob.data.materials.append(m)
    for poly in ob.data.polygons:
        poly.material_index = MI[part_mat[ob.name]]
bpy.ops.object.select_all(action="DESELECT")
for ob, _ in PARTS:
    ob.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "SoldierMesh"

# UV：智能展开（迷彩/织物贴图用）
bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01, scale_to_bounds=True)
bpy.ops.object.mode_set(mode="OBJECT")
# 装备部件是硬边：清掉平滑（身体保留平滑）
for poly in body.data.polygons:
    if poly.material_index in (MI["Gear"], MI["Weapon"], MI["Lens"]):
        poly.use_smooth = False


# ============================================================
#  动画
# ============================================================
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
for p in rig.pose.bones:
    p.rotation_mode = "QUATERNION"
REST = {b.name: b.matrix_local.copy() for b in rig.data.bones}
AX = {"x": V(1, 0, 0), "y": V(0, 1, 0), "z": V(0, 0, 1)}


def world_rot(bone, rots):
    """rots: [(轴 'x'/'y'/'z', 角度°), ...] 按骨架空间轴依次旋转 → 骨骼局部四元数。"""
    q = Quaternion()
    for ax, deg in rots:
        q = Quaternion(AX[ax], math.radians(deg)) @ q
    m = REST[bone].to_3x3()
    return (m.inverted() @ q.to_matrix() @ m).to_quaternion()


def clear_pose():
    for p in rig.pose.bones:
        p.rotation_quaternion = Quaternion()
        p.location = V(0, 0, 0)


def key_pose(frame, pose, loc=None):
    """pose: {骨: [(轴, 度)...]}; loc: {骨: 骨架空间位移}"""
    clear_pose()
    for b, rots in pose.items():
        rig.pose.bones[b].rotation_quaternion = world_rot(b, rots)
    for b, d in (loc or {}).items():
        rig.pose.bones[b].location = REST[b].to_3x3().inverted() @ d
    for p in rig.pose.bones:
        p.keyframe_insert("rotation_quaternion", frame=frame)
        p.keyframe_insert("location", frame=frame)


def make_action(name, frames, looped=True):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    for f, pose, loc in frames:
        key_pose(f, pose, loc)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(frames[0][0]), act)
    strip.name = name
    track.mute = True
    rig.animation_data.action = None
    return act


# 持枪姿态（武器骨相对抵肩瞄准位的偏移 / 旋转）
AIM_W = {}                                              # 抵肩瞄准：静置位
LOW_W = [("x", 28), ("z", 25)]                          # 低姿持枪：枪口朝左下（绕 X 正角 = 枪口下压）
LOW_L = V(0.06, 0.06, -0.24)
RUN_W = [("x", 20), ("z", 55), ("y", 20)]               # 奔跑：枪横在胸前
RUN_L = V(0.08, 0.1, -0.22)


def legs(tl, sl, fl, tr, sr, fr):
    """大腿/小腿/脚 绕 X 轴角度（负 = 向前摆）；小腿正 = 屈膝"""
    return {"thigh.L": [("x", tl)], "shin.L": [("x", sl)], "foot.L": [("x", fl)],
            "thigh.R": [("x", tr)], "shin.R": [("x", sr)], "foot.R": [("x", fr)]}


def merge(*ds):
    out = {}
    for d in ds:
        for k, v in d.items():
            out[k] = out.get(k, []) + v
    return out


# idle：低姿持枪、微屈膝、呼吸
IDLE_BASE = merge(legs(-6, 10, -4, -2, 6, -4), {"weapon": LOW_W, "spine": [("x", -3)],
                                                "head": [("x", 4)]})
make_action("idle_loop", [
    (1, merge(IDLE_BASE, {"chest": [("x", -1)]}), {"weapon": LOW_L, "hips": V(0, 0, -0.02)}),
    (31, merge(IDLE_BASE, {"chest": [("x", 1.5)]}), {"weapon": LOW_L, "hips": V(0, 0, -0.025)}),
    (61, merge(IDLE_BASE, {"chest": [("x", -1)]}), {"weapon": LOW_L, "hips": V(0, 0, -0.02)}),
])

# aim：抵肩瞄准、弓步站姿、轻微晃动
AIM_BASE = merge(legs(-14, 16, -2, 10, 8, -8), {"spine": [("x", -4)], "chest": [("z", 6)],
                                               "head": [("x", 8), ("z", -6)]})   # 低头贴腮
make_action("aim_loop", [
    (1, AIM_BASE, {"hips": V(0, 0, -0.04)}),
    (21, merge(AIM_BASE, {"chest": [("x", 1)]}), {"hips": V(0, 0, -0.045)}),
    (41, AIM_BASE, {"hips": V(0, 0, -0.04)}),
])


# walk：举枪行进（1 秒一个循环）
def walk_frames(period, amp_t, amp_k, bob, lean, wpose, wloc):
    f = [1, 1 + period / 4, 1 + period / 2, 1 + period * 3 / 4, 1 + period]
    ph = [
        legs(-amp_t, 6, -6, amp_t * 0.8, 12, 8),
        legs(0, 8, 0, -amp_t * 0.2, amp_k, 0),
        legs(amp_t * 0.8, 12, 8, -amp_t, 6, -6),
        legs(-amp_t * 0.2, amp_k, 0, 0, 8, 0),
        legs(-amp_t, 6, -6, amp_t * 0.8, 12, 8),
    ]
    hz = [-0.02, bob - 0.02, -0.02, bob - 0.02, -0.02]
    out = []
    for i in range(5):
        pose = merge(ph[i], {"spine": [("x", -lean)], "weapon": list(wpose),
                             "chest": [("z", 4 if i in (0, 1) else -4)]})
        out.append((f[i], pose, {"hips": V(0, 0, hz[i]), "weapon": wloc}))
    return out


make_action("walk_loop", walk_frames(30, 24, 42, 0.02, 4, [], V(0, 0, 0)))
make_action("run_loop", walk_frames(20, 38, 70, 0.04, 12, RUN_W, RUN_L))

# death：中弹后仰倒地（1.1 秒，末帧停住）
make_action("death", [
    (1, IDLE_BASE, {"weapon": LOW_L, "hips": V(0, 0, -0.02)}),
    (8, merge(legs(-10, 30, 0, -4, 25, 0), {"spine": [("x", 12)], "chest": [("x", 10)],
                                            "head": [("x", 15)], "weapon": LOW_W}),
     {"weapon": LOW_L, "hips": V(0, 0.05, -0.2)}),
    (20, merge(legs(-60, 80, 10, -40, 60, 10), {"hips": [("x", 55)], "spine": [("x", 10)],
                                                "head": [("x", 20)], "weapon": LOW_W}),
     {"weapon": LOW_L, "hips": V(0, 0.35, -0.6)}),
    (33, merge(legs(-80, 20, 20, -70, 35, 20), {"hips": [("x", 86)], "spine": [("x", 4)],
                                                "head": [("x", 10), ("z", 25)],
                                                "weapon": LOW_W}),
     {"weapon": LOW_L, "hips": V(0, 0.55, -0.78)}),
], looped=False)
bpy.ops.object.mode_set(mode="OBJECT")

tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
print("[soldier] 顶点 %d 面(三角) %d 骨骼 %d" % (len(body.data.vertices), tris, len(rig.data.bones)))

# ============================================================
#  导出
# ============================================================
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format="GLB", use_selection=False,
    export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
    export_def_bones=True, export_optimize_animation_size=True, export_skins=True,
    export_image_format="AUTO", export_yup=True)
print("[soldier] 导出 %s（%.0f KB）" % (OUT, os.path.getsize(OUT) / 1024.0))

# ============================================================
#  预览图（工作台渲染：各动作关键帧的正/侧视）
# ============================================================
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 480
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.1
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    shots = [("idle_loop", 1), ("aim_loop", 1), ("walk_loop", 1), ("walk_loop", 16),
             ("run_loop", 6), ("death", 33)]
    if os.environ.get("QUICK"):
        shots = [("aim_loop", 1), ("idle_loop", 1)]
    views = {"front": (V(0, -4, 0.95), (math.radians(90), 0, 0)),
             "side": (V(4, 0, 0.95), (math.radians(90), 0, math.radians(90)))}
    for act_name, frame in shots:
        for tr in rig.animation_data.nla_tracks:
            tr.mute = tr.name != act_name
            tr.is_solo = tr.name == act_name
        scene.frame_set(frame)
        for vname, (loc, rot) in views.items():
            cam.location = loc
            cam.rotation_euler = rot
            scene.render.filepath = os.path.join(PREVIEW, "%s_%d_%s.png" % (act_name, frame, vname))
            bpy.ops.render.render(write_still=True)
    print("[soldier] 预览图 → %s" % PREVIEW)
