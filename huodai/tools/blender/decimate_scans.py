"""烽火地带 · 实拍植被减面：Poly Haven 扫描模型（几万~十几万面）→ 可大量摆放的 GLB。

  /Applications/Blender.app/Contents/MacOS/Blender -b --python decimate_scans.py

输入：huodai/assets/pbr/models/<name>/<name>_1k.gltf（原始 CC0 扫描，保留不动）
输出：huodai/assets/pbr/models/<name>/<name>_lod.glb（Decimate 折叠减面、贴图 JPEG 内嵌）
"""
import bpy
import os

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "..", "assets", "pbr", "models")
# name → 保留比例（目标：箭筒树 ~1.8 万面、灌木/枯枝 ~5 千面）
JOBS = {"quiver_tree_02": 0.12, "shrub_04": 0.12, "dry_branches_medium_01": 0.3}


def run(name, ratio):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = os.path.join(MODELS, name, name + "_1k.gltf")
    bpy.ops.import_scene.gltf(filepath=src)
    before = after = 0
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        before += len(ob.data.polygons)
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=mod.name)
        after += len(ob.data.polygons)
    out = os.path.join(MODELS, name, name + "_lod.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True,
                              export_animations=False, export_image_format="JPEG",
                              export_jpeg_quality=90)
    print("[decimate] %s %d -> %d faces -> %s" % (name, before, after, out))


for n, r in JOBS.items():
    run(n, r)
