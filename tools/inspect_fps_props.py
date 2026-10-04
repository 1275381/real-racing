#!/usr/bin/env python3
"""探明 props GLB 的真实包围盒 / 原点高度 / 材质名 / 贴图引用方式（摆位与兜底用，一次性脚本）。"""
import json, struct, sys, math, os

PROPS_DIR = "godot/assets/battle/props"
NAMES = ["barn","barrel","barrier","bunker","container","crate","dead_tree",
         "fuel_tank","house","rocks","sandbags","tent","warehouse","wreck"]
# 接口给定的尺寸（W×H×D），用于对照
IFACE = {
    "barn": (12, 7, 8), "barrel": (0.57, 0.9, 0.57), "barrier": (4.16, 1.25, 0.75),
    "bunker": (14.1, 3.7, 9.1), "container": (2.46, 2.59, 6.08), "crate": (1.02, 1.02, 1.02),
    "dead_tree": (1, 4.9, 2), "fuel_tank": (10, 7.8, 10), "house": (7.1, 3.6, 6.1),
    "rocks": (13.6, 2.2, 3.3), "sandbags": (2.52, 1.61, 0.78), "tent": (6.3, 2.69, 4.31),
    "warehouse": (22, 8.1, 12.1), "wreck": (1.87, 1.13, 4.3),
}

def mat_mul(a, b):
    return [sum(a[k*4+c] * b[r*4+k] for k in range(4)) for r in range(4) for c in range(4)]

def apply(m, v):
    x, y, z = v
    return (m[0]*x + m[4]*y + m[8]*z + m[12],
            m[1]*x + m[5]*y + m[9]*z + m[13],
            m[2]*x + m[6]*y + m[10]*z + m[14])

def trs(n):
    t = n.get("translation", [0, 0, 0]); q = n.get("rotation", [0, 0, 0, 1]); s = n.get("scale", [1, 1, 1])
    x, y, z, w = q
    m = [1-(y*y+z*z)*2-(0), 0, 0, 0]*0  # placeholder
    # column-major rotation from quaternion
    r = [
        1-2*(y*y+z*z), 2*(x*y+z*w), 2*(x*z-y*w),
        2*(x*y-z*w), 1-2*(x*x+z*z), 2*(y*z+x*w),
        2*(x*z+y*w), 2*(y*z-x*w), 1-2*(x*x+y*y),
    ]
    return [r[0]*s[0], r[1]*s[0], r[2]*s[0], 0,
            r[3]*s[1], r[4]*s[1], r[5]*s[1], 0,
            r[6]*s[2], r[7]*s[2], r[8]*s[2], 0,
            t[0], t[1], t[2], 1]

def glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "not glb"
    clen, ctype = struct.unpack("<II", data[12:20])
    assert ctype == 0x4E4F534A
    return json.loads(data[20:20+clen])

def bbox(path):
    g = glb_json(path)
    accs, meshes, nodes = g["accessors"], g.get("meshes", []), g["nodes"]
    mats = [m.get("name", "?") for m in g.get("materials", [])]
    imgs = []
    for im in g.get("images", []):
        imgs.append("bufferView" if "bufferView" in im else str(im.get("uri", "?")))
    lo = [math.inf]*3; hi = [-math.inf]*3
    def walk(i, parent):
        m = mat_mul(parent, nodes[i]["matrix"] if "matrix" in nodes[i] else trs(nodes[i]))
        n = nodes[i]
        if "mesh" in n:
            for prim in meshes[n["mesh"]]["primitives"]:
                a = prim["attributes"].get("POSITION")
                if a is None: continue
                mn, mx = accs[a]["min"], accs[a]["max"]
                for corner in [(x, y, z) for x in (mn[0], mx[0]) for y in (mn[1], mx[1]) for z in (mn[2], mx[2])]:
                    w = apply(m, corner)
                    for k in range(3):
                        lo[k] = min(lo[k], w[k]); hi[k] = max(hi[k], w[k])
        for c in n.get("children", []):
            walk(c, m)
    for root in g.get("scenes", [{}])[0].get("nodes", []):
        walk(root, [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1])
    dims = tuple(hi[k]-lo[k] for k in range(3))
    return dims, lo, hi, mats, imgs

print(f"{'name':<11}{'dims(W×H×D)':<26}{'iface':<24}{'minY':>8}  materials | images")
for name in NAMES:
    path = os.path.join(PROPS_DIR, name + ".glb")
    dims, lo, hi, mats, imgs = bbox(path)
    iface = IFACE[name]
    ok = all(abs(dims[k]-iface[k]) < 0.35 for k in range(3))
    cx, cz = (lo[0]+hi[0])/2, (lo[2]+hi[2])/2
    print(f"{name:<11}{str(tuple(round(d,2) for d in dims)):<26}{str(iface):<24}minY={lo[1]:>7.3f} c=({cx:+.2f},{cz:+.2f}) "
          f"{'OK ' if ok else 'DIFF'} {mats}")

# soldier.glb：贴图是否内嵌 + 尺寸（敌人组参考）
g = glb_json("godot/assets/battle/soldier.glb")
print("\nsoldier.glb images:", ["bufferView" if "bufferView" in im else im.get("uri") for im in g.get("images", [])])
print("soldier.glb materials:", [m.get("name") for m in g.get("materials", [])])
clips = [a.get("name") for a in g.get("animations", [])]
print("soldier.glb animations:", clips)
