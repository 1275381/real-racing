import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { boundaryBoxes, terrainHeight } from './env.js';
import { weaveHeight, speckleHeight, grainHeight, normalFromCanvas, toNormalTexture } from './normalmap.js';

/* ==== 1. 道具尺寸表 ==== */
// 碰撞登记用实测包围盒（tools/inspect_fps_props.py 探明，W×H×D，原点在底面中心、正面朝 +Z）
const PROP_DIMS = {
    barn: [12.7, 7.17, 8.74],  barrel: [0.60, 0.91, 0.61],  barrier: [4.16, 1.25, 0.75],
    bunker: [14.1, 3.7, 9.58], container: [2.46, 2.59, 6.12], crate: [1.02, 1.02, 1.02],
    dead_tree: [1.04, 4.88, 2.0], fuel_tank: [11.98, 8.12, 10.16], house: [7.1, 3.6, 6.92],
    rocks: [13.6, 2.22, 3.29], sandbags: [2.52, 1.61, 0.78], tent: [6.3, 2.69, 4.31],
    warehouse: [22.8, 8.2, 12.83], wreck: [1.88, 1.44, 4.3],
};
// 兜底盒体尺寸（接口约定的已探明清单）：GLB 加载失败时按此摆同尺寸替身
const FALLBACK_DIMS = {
    barn: [12, 7, 8],  barrel: [0.57, 0.9, 0.57],  barrier: [4.16, 1.25, 0.75],
    bunker: [14.1, 3.7, 9.1], container: [2.46, 2.59, 6.08], crate: [1.02, 1.02, 1.02],
    dead_tree: [1, 4.9, 2], fuel_tank: [10, 7.8, 10], house: [7.1, 3.6, 6.1],
    rocks: [13.6, 2.2, 3.3], sandbags: [2.52, 1.61, 0.78], tent: [6.3, 2.69, 4.31],
    warehouse: [22, 8.1, 12.1], wreck: [1.87, 1.13, 4.3],
};
const PROP_NAMES = Object.keys(PROP_DIMS);
// 兜底盒底色（贴合各道具本来的材质气质）
const FALLBACK_COLOR = {
    barn: 0x8a6f52, barrel: 0x6f7d86, barrier: 0x8f8d84, bunker: 0x84806f,
    container: 0x7a6a58, crate: 0x9c7c50, dead_tree: 0x5e4a38, fuel_tank: 0x8f8578,
    house: 0xb0a184, rocks: 0x7c7468, sandbags: 0x9c8e6a, tent: 0x8f8a78,
    warehouse: 0x8a8578, wreck: 0x6a5f56,
};
// 可按实例染色的 GLB 材质名（tools/inspect_fps_props.py 探明；battle_map.gd:38 同款）
const TINTABLE = new Set(['Paint', 'Plaster', 'Concrete', 'TankPaint', 'Canvas']);

/* ==== 2. loadProps：14 个 GLB 预载，单个失败降级同尺寸盒体（car.js 容错风格） ==== */

/* GLB 材质补法线（写实度评审 #4）：资产无烘焙法线，按材质名挂程序化高度场法线。
 * 材质被同模板所有实例共享，只在此处理一次（_fpsNormal 防重）。 */
const NORMAL_RULES = {
    Burlap:   { kind: 'weave',   cell: 18, repeat: 6, strength: 1.1, scale: 0.9 },
    Canvas:   { kind: 'weave',   cell: 10, repeat: 4, strength: 0.8, scale: 0.6 },
    Wood:     { kind: 'grain',   repeat: 3, strength: 1.0, scale: 0.5 },
    Bark:     { kind: 'grain',   repeat: 2, strength: 1.4, scale: 0.8 },
    Plaster:  { kind: 'speckle', repeat: 3, strength: 1.6, scale: 0.45 },
    Concrete: { kind: 'speckle', repeat: 3, strength: 1.6, scale: 0.5 },
    TankPaint:{ kind: 'speckle', repeat: 3, strength: 1.2, scale: 0.4 },
    Paint:    { kind: 'speckle', repeat: 4, strength: 1.0, scale: 0.35 },
    Metal:    { kind: 'speckle', repeat: 4, strength: 1.2, scale: 0.45 },
    Rust:     { kind: 'speckle', repeat: 3, strength: 1.8, scale: 0.6 },
    Rock:     { kind: 'speckle', repeat: 2, strength: 2.0, scale: 0.7 },
};
const _normalCache = new Map();
function detailNormal(matName) {
    const rule = NORMAL_RULES[matName];
    if (!rule) return null;
    if (!_normalCache.has(matName)) {
        let h;
        if (rule.kind === 'weave') h = weaveHeight(256, rule.cell || 16);
        else if (rule.kind === 'grain') h = grainHeight(256);
        else h = speckleHeight(256, rule.strength > 1.4 ? 3.4 : 2.4);
        _normalCache.set(matName, {
            tex: toNormalTexture(normalFromCanvas(h, rule.strength), rule.repeat),
            scale: rule.scale,
        });
    }
    return _normalCache.get(matName);
}

function applyDetailNormals(root) {
    root.traverse((o) => {
        if (!o.isMesh) return;
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) {
            if (!m || m._fpsNormal) continue;
            const n = detailNormal(m.name);
            if (!n) continue;
            m.normalMap = n.tex;
            if (m.normalScale) m.normalScale.set(n.scale, n.scale);
            m.needsUpdate = true;
            m._fpsNormal = true;
        }
    });
}

export async function loadProps() {
    const loader = new GLTFLoader();
    const templates = new Map();
    await Promise.all(PROP_NAMES.map(async (name) => {
        try {
            const gltf = await loader.loadAsync(`assets/fps/props/${name}.glb?v=1`);
            applyDetailNormals(gltf.scene);      // 法线挂模板材质（实例共享）
            templates.set(name, gltf.scene);
        } catch (e) {
            console.warn(`[场景] 道具 ${name}.glb 加载失败，改用同尺寸盒体：`, e && e.message);
        }
    }));
    return {
        missing: PROP_NAMES.filter((n) => !templates.has(n)),
        make(name) {
            const tpl = templates.get(name);
            if (tpl) {
                const g = tpl.clone(true);
                g.traverse((o) => {
                    if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; }
                });
                return g;
            }
            return makeFallback(name);
        },
    };
}

// 程序化替身：盒体（油桶用圆柱、枯树用树干柱），组原点同 GLB 约定在底面中心
let _gritTex = null;
function gritTexture() {
    if (_gritTex) return _gritTex;
    const S = 256;
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const g = c.getContext('2d');
    g.fillStyle = '#c8c2b4';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 3200; i++) {
        const v = 150 + Math.random() * 80;
        g.fillStyle = `rgba(${v},${v - 6},${v - 16},${0.3 + Math.random() * 0.35})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.6, 1.6);
    }
    for (let i = 0; i < 16; i++) {   // 污渍
        g.fillStyle = `rgba(90,84,70,${0.06 + Math.random() * 0.1})`;
        g.beginPath();
        g.arc(Math.random() * S, Math.random() * S, 14 + Math.random() * 40, 0, 7);
        g.fill();
    }
    _gritTex = new THREE.CanvasTexture(c);
    _gritTex.wrapS = _gritTex.wrapT = THREE.RepeatWrapping;
    _gritTex.repeat.set(1.5, 1.5);
    _gritTex.colorSpace = THREE.SRGBColorSpace;
    return _gritTex;
}

function makeFallback(name) {
    const dims = FALLBACK_DIMS[name];
    const group = new THREE.Group();
    group.name = 'fallback_' + name;
    if (!dims) {
        console.warn('[场景] 未知道具名：', name);
        return group;
    }
    const mat = new THREE.MeshStandardMaterial({
        color: FALLBACK_COLOR[name] || 0x8a8272, map: gritTexture(), roughness: 0.95,
    });
    const add = (geo, y) => {
        const m = new THREE.Mesh(geo, mat);
        m.position.y = y;
        m.castShadow = m.receiveShadow = true;
        group.add(m);
    };
    if (name === 'barrel') {
        add(new THREE.CylinderGeometry(dims[0] / 2, dims[0] / 2, dims[1], 14), dims[1] / 2);
    } else if (name === 'dead_tree') {
        add(new THREE.CylinderGeometry(0.12, 0.22, dims[1], 8), dims[1] / 2);
        add(new THREE.CylinderGeometry(0.05, 0.09, 1.6, 6), dims[1] * 0.78);
        group.children[1].rotation.z = 0.7;
    } else {
        add(new THREE.BoxGeometry(dims[0], dims[1], dims[2]), dims[1] / 2);
    }
    return group;
}

/* ==== 3. CollisionWorld：OBB 注册 / 地面高度 / 圆推出 / 墙体射线（battle_map.gd 同款算法） ==== */

// 射线打单个 OBB：2D 板层求交 + 高度判定（矮墙可从上方射过），返回距离或 Infinity
function rayOBB(from, dir, b, maxD) {
    const ox = from.x - b.cx, oz = from.z - b.cz;
    const lx = b.c * ox + b.s * oz;
    const lz = -b.s * ox + b.c * oz;
    const dx = b.c * dir.x + b.s * dir.z;
    const dz = -b.s * dir.x + b.c * dir.z;
    let t0 = 0, t1 = maxD;
    const axes = [[lx, dx, b.hx], [lz, dz, b.hz]];
    for (let k = 0; k < 2; k++) {
        const o = axes[k][0], d = axes[k][1], h = axes[k][2];
        if (Math.abs(d) < 1e-6) {
            if (Math.abs(o) > h) return Infinity;
            continue;
        }
        let ta = (-h - o) / d, tb = (h - o) / d;
        if (ta > tb) { const t = ta; ta = tb; tb = t; }
        if (ta > t0) t0 = ta;
        if (tb < t1) t1 = tb;
        if (t0 > t1) return Infinity;
    }
    const y = Math.min(from.y + dir.y * t0, from.y + dir.y * t1);
    if (y > b.top) return Infinity;
    return t0;
}

export class CollisionWorld {
    constructor() {
        this.boxes = [];   // {cx,cz,hx,hz,c,s,base,top}，base 贴地
    }

    /* 注册一个贴地 OBB：cx/cz 中心、hx/hz 半宽、rotY 朝向、h 离地高度 */
    addBox(cx, cz, hx, hz, rotY, h) {
        const base = terrainHeight(cx, cz);
        this.boxes.push({ cx, cz, hx, hz, c: Math.cos(rotY), s: Math.sin(rotY), base, top: base + h });
    }

    groundHeight(x, z) {
        return terrainHeight(x, z);
    }

    /* 圆（半径 r）从所有 OBB 中推出，返回修正后的 XZ（battle_map.gd:221 同款逐盒推） */
    pushOut(x, z, r) {
        let nx = x, nz = z;
        for (const b of this.boxes) {
            const dx = nx - b.cx, dz = nz - b.cz;
            let lx = b.c * dx + b.s * dz;
            let lz = -b.s * dx + b.c * dz;
            const px = b.hx + r - Math.abs(lx);
            const pz = b.hz + r - Math.abs(lz);
            if (px > 0 && pz > 0) {
                if (px < pz) lx = (lx >= 0 ? 1 : -1) * (b.hx + r);
                else lz = (lz >= 0 ? 1 : -1) * (b.hz + r);
                nx = b.cx + b.c * lx - b.s * lz;
                nz = b.cz + b.s * lx + b.c * lz;
            }
        }
        return { x: nx, z: nz };
    }

    /* 射线到第一面墙的距离（无命中返回 Infinity） */
    rayWall(from, dir, maxD) {
        let best = Infinity;
        for (const b of this.boxes) {
            const d = rayOBB(from, dir, b, Math.min(best, maxD));
            if (d < best) best = d;
        }
        return best;
    }
}

/* ==== 4. 摆位表（手工排布、确定性可复现；n=道具 x/z=位置 r=朝向 s=缩放 y=离地叠层 t=染色 col=碰撞覆盖[hx,hz,h]） ==== */

const LAYOUT = [
    // —— 南侧：出生观察点（帐篷 + 沙袋线 + 物资，玩家出生其后） ——
    { n: 'tent', x: 3.4, z: 54.2, r: -0.25, t: 0xb59f7a },
    { n: 'sandbags', x: -1.5, z: 50.6, r: 0.05 },
    { n: 'sandbags', x: 1.1, z: 50.4, r: -0.12 },
    { n: 'barrier', x: -4.6, z: 51.6, r: 0.18 },
    { n: 'barrier', x: 5.4, z: 50.9, r: -0.1 },
    { n: 'crate', x: 7.6, z: 57.0, r: 0.3, s: 0.95 },
    { n: 'crate', x: 8.7, z: 56.2, r: -0.2 },
    { n: 'barrel', x: -6.2, z: 55.0, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: -5.5, z: 55.6, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -6.1, z: 54.2, r: 0, t: 0x9fb4c6 },
    { n: 'wreck', x: 10.6, z: 52.8, r: 2.35 },
    { n: 'dead_tree', x: -8.5, z: 49.6, r: 0.7, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 6.5, z: 47.6, r: 2.1, col: [0.35, 0.35, 4.88] },

    // —— 西侧：40m 靶场（北=仓库墙 南=乱石 东=集装箱档弹墙，西向射界） ——
    { n: 'warehouse', x: -38, z: -28, r: 0, t: 0x9c8f7d },
    { n: 'container', x: -22, z: -16.5, r: 0.02, t: 0x3f6f8f },
    { n: 'container', x: -22, z: -10.25, r: -0.02, t: 0x8f5a3f },
    { n: 'container', x: -22, z: -4.0, r: 0.02, t: 0x5a7050 },
    { n: 'container', x: -22, z: 2.25, r: -0.02, t: 0x8a4a44 },
    { n: 'container', x: -22, z: 8.5, r: 0.02, t: 0x6f6a5f },
    { n: 'rocks', x: -40, z: 15.5, r: 0.06 },
    { n: 'sandbags', x: -29.5, z: 15.2, r: 0.1 },
    { n: 'crate', x: -53.8, z: -15.6, r: 0.2 },
    { n: 'crate', x: -53.8, z: -3.6, r: -0.3 },
    { n: 'crate', x: -53.8, z: 8.4, r: 0.15 },
    { n: 'barrel', x: -55.5, z: -19.2, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -55.2, z: 13.6, r: 0, t: 0x9fb4c6 },
    { n: 'dead_tree', x: -56.8, z: -23.5, r: 1.2, col: [0.35, 0.35, 4.88] },
    { n: 'wreck', x: -26, z: 17.5, r: 1.1 },

    // —— 中央：交战区掩体群（集装箱巷道 + 沙袋 + 油桶群 + 残骸 + 北侧地堡） ——
    { n: 'container', x: -3.5, z: -6.5, r: 0.12, t: 0x4a6d8f },
    { n: 'container', x: -3.5, z: -6.5, r: 0.02, y: 2.59, t: 0x7d5a45 },   // 叠层
    { n: 'container', x: -3.8, z: 0.2, r: -0.06, t: 0x6d6a58 },
    { n: 'container', x: 3.5, z: -14.2, r: 1.62, t: 0x8f4a3d },
    { n: 'container', x: 14.5, z: -8.5, r: -1.55, t: 0x3f7a62 },
    { n: 'sandbags', x: 8.5, z: -1.5, r: 0 },
    { n: 'sandbags', x: 11.5, z: -16.5, r: 1.25 },
    { n: 'sandbags', x: -7.5, z: -17.5, r: 0.55 },
    { n: 'sandbags', x: 5.0, z: -21.0, r: -0.15 },
    { n: 'sandbags', x: -9.0, z: -3.0, r: 1.35 },
    { n: 'barrier', x: 0.5, z: -10.5, r: 1.15 },
    { n: 'barrier', x: 17.0, z: -19.5, r: -0.35 },
    { n: 'barrier', x: -11.0, z: -9.0, r: 0.12 },
    { n: 'barrel', x: 19.5, z: -11.5, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 20.3, z: -12.3, r: 0, t: 0xb0452f },
    { n: 'barrel', x: 19.1, z: -13.0, r: 0, t: 0x8f8a4a },
    { n: 'barrel', x: -5.5, z: -20.5, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -6.4, z: -21.2, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 8.0, z: -6.2, r: 0, t: 0x8f8a4a },
    { n: 'barrel', x: 17.0, z: -3.0, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 16.4, z: -3.8, r: 0, t: 0xb0452f },
    { n: 'crate', x: 6.8, z: -4.6, r: 0.25 },
    { n: 'crate', x: 6.8, z: -4.6, r: -0.15, y: 1.02 },                     // 叠层
    { n: 'crate', x: 12.0, z: -11.2, r: 0.5 },
    { n: 'crate', x: -1.5, z: 3.5, r: -0.4, s: 0.9 },
    { n: 'wreck', x: 21.5, z: -3.0, r: 0.75 },
    { n: 'wreck', x: -9.5, z: -13.5, r: -0.55 },
    { n: 'fuel_tank', x: 26.0, z: -19.0, r: 0.25, t: 0x8f8578 },
    { n: 'bunker', x: 7.0, z: -26.5, r: 0 },

    // —— 东北：情报点（小屋 + 帐篷营地，情报箱在屋前） ——
    { n: 'house', x: 32.0, z: -32.5, r: 0.06, t: 0xc7b394 },
    { n: 'tent', x: 40.5, z: -29.5, r: -0.45, t: 0x8fa08f },
    { n: 'crate', x: 29.0, z: -27.6, r: 0.35 },
    { n: 'barrel', x: 36.2, z: -26.4, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 35.6, z: -25.6, r: 0, t: 0xb0452f },
    { n: 'sandbags', x: 27.0, z: -30.5, r: 1.5 },
    { n: 'dead_tree', x: 44.5, z: -35.0, r: 0.9, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 26.5, z: -38.5, r: 2.6, col: [0.35, 0.35, 4.88] },
    { n: 'wreck', x: 38.5, z: -37.5, r: 2.2 },

    // —— 东侧：撤离点（绿烟信标在场内，残骸与枯树在外圈） ——
    { n: 'wreck', x: 39.5, z: 14.5, r: 1.35 },
    { n: 'dead_tree', x: 49.5, z: 3.0, r: 1.8, col: [0.35, 0.35, 4.88] },
    { n: 'barrel', x: 41.0, z: 2.5, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 40.3, z: 3.2, r: 0, t: 0xb0452f },

    // —— 全场散布：地标与废墟感 ——
    { n: 'barn', x: -12.0, z: -49.0, r: 0.3, t: 0xa4552f },
    { n: 'rocks', x: -48, z: -49, r: 0.55 },
    { n: 'rocks', x: 50, z: -49, r: -0.8 },
    { n: 'rocks', x: -45, z: 38, r: 0.15 },
    { n: 'dead_tree', x: -30, z: -38, r: 0.4, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 8, z: -44, r: 1.9, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 22, z: 36, r: 2.8, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -56, z: 24, r: 0.3, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 52, z: 28, r: 1.1, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -52.5, z: -36, r: 2.3, col: [0.35, 0.35, 4.88] },
    { n: 'wreck', x: -16, z: 40, r: -1.1 },
    { n: 'wreck', x: 2.5, z: 18, r: 1.2 },
    { n: 'barrel', x: -19, z: -30, r: 0, t: 0x8f8a4a },
    { n: 'crate', x: 18, z: -38, r: 0.2 },
    { n: 'sandbags', x: 2.5, z: -36.5, r: 1.4 },
];

// 土路（纯视觉）：出生→交战区→情报点；分支去撤离点；支线去靶场
const ROADS = [
    [[0, 57], [0, 34], [5, 12], [15, -8], [24, -18], [30, -25.5]],
    [[18, -5], [28, 0], [38, 4], [44, 7.5]],
    [[0, 40], [-14, 32], [-30, 22], [-40, 15]],
];

// 巡逻线 3 条（8 名敌兵由 EnemyManager 分配：3+3+2）
const PATROL_ROUTES = [
    [[0, 14], [22, 4], [16, -16], [-4, -20], [-12, -1]],       // 交战区环线
    [[16, -35], [34, -44], [47, -31.5], [36, -20]],            // 情报点/油库环线
    [[28, 0], [44, 16], [30, 30], [12, 20]],                   // 东侧通往撤离点
];

/* ==== 5. 程序化小件贴图：烟团 / 撤离地标线 / 土路 ==== */

function makeCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return [c, c.getContext('2d')];
}

// 信号烟烟团（柔和圆斑带破边）
function puffTexture() {
    const S = 128;
    const [c, g] = makeCanvas(S, S);
    const grad = g.createRadialGradient(S / 2, S / 2, 4, S / 2, S / 2, S / 2);
    grad.addColorStop(0, 'rgba(255,255,255,0.9)');
    grad.addColorStop(0.4, 'rgba(255,255,255,0.55)');
    grad.addColorStop(0.75, 'rgba(255,255,255,0.18)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 26; i++) {   // 破边
        g.globalCompositeOperation = 'destination-out';
        const r = 4 + Math.random() * 10;
        g.beginPath();
        g.arc(S / 2 + (Math.random() - 0.5) * S * 0.8, S / 2 + (Math.random() - 0.5) * S * 0.8, r, 0, 7);
        g.fill();
    }
    const t = new THREE.CanvasTexture(c);
    return t;
}

// 撤离点地面标线：绿环 + H + 四向箭头
function extractMarkTexture() {
    const S = 512;
    const [c, g] = makeCanvas(S, S);
    g.translate(S / 2, S / 2);
    // 外环（虚线）
    g.strokeStyle = 'rgba(64,220,110,0.95)';
    g.lineWidth = 18;
    g.setLineDash([44, 26]);
    g.beginPath(); g.arc(0, 0, S * 0.40, 0, 7); g.stroke();
    g.setLineDash([]);
    // 内环
    g.strokeStyle = 'rgba(64,220,110,0.5)';
    g.lineWidth = 8;
    g.beginPath(); g.arc(0, 0, S * 0.335, 0, 7); g.stroke();
    // 中央 H
    g.strokeStyle = 'rgba(230,255,238,0.95)';
    g.lineWidth = 26;
    g.lineCap = 'round';
    g.beginPath();
    g.moveTo(-70, -90); g.lineTo(-70, 90);
    g.moveTo(70, -90); g.lineTo(70, 90);
    g.moveTo(-70, 0); g.lineTo(70, 0);
    g.stroke();
    // 四向箭头
    g.fillStyle = 'rgba(64,220,110,0.9)';
    for (let k = 0; k < 4; k++) {
        g.save();
        g.rotate(k * Math.PI / 2);
        g.beginPath();
        g.moveTo(0, -S * 0.48); g.lineTo(-22, -S * 0.43); g.lineTo(22, -S * 0.43);
        g.fill();
        g.restore();
    }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
}

// 土路：车辙双痕 + 碎石（v 沿路延伸）
function roadTexture() {
    const S = 256;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#93805c';
    g.fillRect(0, 0, S, S);
    for (const u of [0.30, 0.70]) {   // 两条车辙压痕
        const grad = g.createLinearGradient((u - 0.09) * S, 0, (u + 0.09) * S, 0);
        grad.addColorStop(0, 'rgba(0,0,0,0)');
        grad.addColorStop(0.5, 'rgba(70,58,38,0.35)');
        grad.addColorStop(1, 'rgba(0,0,0,0)');
        g.fillStyle = grad;
        g.fillRect((u - 0.09) * S, 0, S * 0.18, S);
    }
    for (let i = 0; i < 1500; i++) {  // 碎石与浮土
        const v = Math.random();
        g.fillStyle = `rgba(${120 + v * 60 | 0},${104 + v * 48 | 0},${70 + v * 36 | 0},${0.3 + Math.random() * 0.35})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.5, 1.5);
    }
    g.fillStyle = 'rgba(80,66,44,0.5)';   // 路缘虚暗
    g.fillRect(0, 0, 5, S); g.fillRect(S - 5, 0, 5, S);
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
}

/* ==== 6. 信号烟粒子柱（撤离点绿色信号烟，Points + 自写软烟着色器） ==== */

class SmokeColumn {
    constructor(scene, x, z, count = 110) {
        this.origin = new THREE.Vector3(x, terrainHeight(x, z) + 0.15, z);
        this.count = count;
        this.pos = new Float32Array(count * 3);
        this.col = new Float32Array(count * 3);
        this.size = new Float32Array(count);
        this.alpha = new Float32Array(count);
        this.p = [];   // 粒子状态
        const green = new THREE.Color(0x2fae4f);
        const gray = new THREE.Color(0x77917c);
        this.c0 = green; this.c1 = gray;
        for (let i = 0; i < count; i++) {
            this.p.push({ life: Math.random() * 5, max: 3 + Math.random() * 2, seed: Math.random() * 10 });
            this._respawn(i, true);
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
        geo.setAttribute('aColor', new THREE.BufferAttribute(this.col, 3));
        geo.setAttribute('aSize', new THREE.BufferAttribute(this.size, 1));
        geo.setAttribute('aAlpha', new THREE.BufferAttribute(this.alpha, 1));
        const mat = new THREE.ShaderMaterial({
            transparent: true,
            depthWrite: false,
            uniforms: { map: { value: puffTexture() } },
            vertexShader: `
                attribute float aSize; attribute float aAlpha; attribute vec3 aColor;
                varying float vA; varying vec3 vC;
                void main() {
                    vA = aAlpha; vC = aColor;
                    vec4 mv = modelViewMatrix * vec4(position, 1.0);
                    gl_PointSize = aSize * (700.0 / max(1.0, -mv.z));
                    gl_Position = projectionMatrix * mv;
                }`,
            fragmentShader: `
                uniform sampler2D map;
                varying float vA; varying vec3 vC;
                void main() {
                    float a = texture2D(map, gl_PointCoord).a * vA;
                    if (a < 0.012) discard;
                    gl_FragColor = vec4(vC, a);
                    #include <colorspace_fragment>
                }`,
        });
        this.points = new THREE.Points(geo, mat);
        this.points.frustumCulled = false;
        this.points.renderOrder = 2;
        scene.add(this.points);
        this._geo = geo; this._mat = mat;
    }

    _respawn(i, init) {
        const q = this.p[i];
        q.life = init ? Math.random() * q.max : 0;
        q.max = 3 + Math.random() * 2;
        q.rise = 0.55 + Math.random() * 0.5;
        q.drift = 0.12 + Math.random() * 0.22;
        const a = Math.random() * Math.PI * 2, rr = Math.random() * 0.35;
        this.pos[i * 3] = this.origin.x + Math.cos(a) * rr;
        this.pos[i * 3 + 1] = this.origin.y + Math.random() * 0.2;
        this.pos[i * 3 + 2] = this.origin.z + Math.sin(a) * rr;
    }

    update(dt, t) {
        const tmp = new THREE.Color();
        for (let i = 0; i < this.count; i++) {
            const q = this.p[i];
            q.life += dt;
            if (q.life > q.max) this._respawn(i, false);
            const k = q.life / q.max;
            const swirl = t * 1.4 + q.seed * 6.28;
            this.pos[i * 3] += (Math.cos(swirl) * q.drift + 0.25) * dt;   // 缓慢顺风飘 + 涡旋
            this.pos[i * 3 + 1] += q.rise * dt;
            this.pos[i * 3 + 2] += (Math.sin(swirl) * q.drift + 0.12) * dt;
            this.size[i] = 0.55 + k * 2.1;
            this.alpha[i] = 0.62 * Math.min(1, k / 0.12) * (1 - Math.pow(k, 1.6));
            tmp.copy(this.c0).lerp(this.c1, Math.min(1, k * 1.25));
            this.col[i * 3] = tmp.r; this.col[i * 3 + 1] = tmp.g; this.col[i * 3 + 2] = tmp.b;
        }
        this._geo.attributes.position.needsUpdate = true;
        this._geo.attributes.aColor.needsUpdate = true;
        this._geo.attributes.aSize.needsUpdate = true;
        this._geo.attributes.aAlpha.needsUpdate = true;
    }

    dispose(scene) {
        scene.remove(this.points);
        this._geo.dispose();
        this._mat.dispose();
    }
}

/* ==== 7. BattleMap：按摆位表布置战场，产出 zones 与碰撞 ==== */

export class BattleMap {
    constructor(scene, props) {
        this.scene = scene;
        this.props = props;
        this.collision = new CollisionWorld();
        this.missing = (props && props.missing) || [];
        this.zones = null;
        this._t = 0;
        this._roots = [];          // 便于整体卸载
        this._smoke = null;
        this._beaconLight = null;
        this._beaconHead = null;
        this._intelMat = null;
    }

    async build() {
        // —— 摆件（视觉 + 自动按包围盒注册 OBB 碰撞） ——
        for (const e of LAYOUT) this._prop(e);

        // —— 场地边界（墙体视觉在 env.js，碰撞在这里注册） ——
        for (const b of boundaryBoxes()) {
            this.collision.addBox(b.cx, b.cz, b.hx, b.hz, b.rotY, b.h);
        }

        // —— 土路（纯视觉） ——
        const roadMat = new THREE.MeshStandardMaterial({
            map: roadTexture(), roughness: 1, metalness: 0, side: THREE.DoubleSide,
        });
        for (const line of ROADS) this._buildRoad(line, 3.2, roadMat);

        // —— 情报箱（呼吸灯） + 撤离点（绿烟 + 信标 + 地面标线） + 靶道射位标线 ——
        this._buildIntel(32.9, -28.2, 0.35);
        this._buildExtract(44, 8);
        this._buildRangeMarks();

        // —— 交给任务/AI 的锚点 ——
        this.zones = {
            playerSpawn: this._v(-1.0, 53.2),
            patrol: PATROL_ROUTES.map((rt) => rt.map((p) => this._v(p[0], p[1]))),
            intelPos: this._v(32.0, -28.6),
            extractPos: this._v(44, 8),
            extractR: 3,
            rangeLanes: [
                { origin: this._v(-52, -14), dir: new THREE.Vector3(1, 0, 0) },
                { origin: this._v(-52, -2), dir: new THREE.Vector3(1, 0, 0) },
                { origin: this._v(-52, 10), dir: new THREE.Vector3(1, 0, 0) },
            ],
        };
        return this;
    }

    update(dt) {
        this._t += dt;
        if (this._smoke) this._smoke.update(dt, this._t);
        if (this._beaconLight) {
            const on = Math.sin(this._t * 4.2) > 0.35;
            this._beaconLight.intensity = on ? 2.6 : 0.1;
            this._beaconHead.emissiveIntensity = on ? 2.4 : 0.12;
        }
        if (this._intelMat) {
            this._intelMat.emissiveIntensity = 0.5 + 0.65 * (0.5 + 0.5 * Math.sin(this._t * 2.6));
        }
    }

    dispose() {
        for (const r of this._roots) this.scene.remove(r);
        this._roots.length = 0;
        if (this._smoke) this._smoke.dispose(this.scene);
    }

    /* ---- 内部工具 ---- */

    _v(x, z) {
        return new THREE.Vector3(x, terrainHeight(x, z), z);
    }

    // 摆一个道具：贴地/叠层、旋转、染色，并按包围盒（实测尺寸×缩放）注册 OBB
    _prop(e) {
        const inst = this.props.make(e.n);
        const s = e.s || 1;
        const y0 = terrainHeight(e.x, e.z);
        inst.position.set(e.x, y0 + (e.y || 0) - 0.04, e.z);   // −0.04 沉底遮接缝
        inst.rotation.y = e.r || 0;
        if (s !== 1) inst.scale.setScalar(s);
        if (e.t) this._applyTint(inst, e.t);
        this.scene.add(inst);
        this._roots.push(inst);
        if (e.noCol) return inst;
        const d = PROP_DIMS[e.n];
        const hx = e.col ? e.col[0] : d[0] * 0.5 * s;
        const hz = e.col ? e.col[1] : d[2] * 0.5 * s;
        const h = e.col ? e.col[2] : (e.y || 0) + d[1] * s;
        this.collision.addBox(e.x, e.z, hx, hz, e.r || 0, h);
        return inst;
    }

    // 实例染色：可染材质克隆后乘色（car.js:36 同款做法）
    _applyTint(root, hex) {
        const tint = new THREE.Color(hex);
        const cache = new Map();
        root.traverse((o) => {
            if (!o.isMesh) return;
            const fix = (mt) => {
                if (!mt || !TINTABLE.has(mt.name)) return mt;
                if (!cache.has(mt)) {
                    const c = mt.clone();
                    c.color = mt.color.clone().multiply(tint);
                    cache.set(mt, c);
                }
                return cache.get(mt);
            };
            o.material = Array.isArray(o.material) ? o.material.map(fix) : fix(o.material);
        });
    }

    // 情报箱：军绿箱体 + 呼吸灯条 + 天线
    _buildIntel(x, z, rot) {
        const g = new THREE.Group();
        const body = new THREE.Mesh(
            new THREE.BoxGeometry(0.78, 0.5, 0.55),
            new THREE.MeshStandardMaterial({ color: 0x39412e, roughness: 0.7, metalness: 0.35 })
        );
        body.position.y = 0.25;
        body.castShadow = body.receiveShadow = true;
        g.add(body);
        this._intelMat = new THREE.MeshStandardMaterial({
            color: 0x0a2c12, emissive: new THREE.Color(0x39ff6e), emissiveIntensity: 1, roughness: 0.4,
        });
        const led = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.07, 0.02), this._intelMat);
        led.position.set(0, 0.33, 0.285);
        g.add(led);
        const antenna = new THREE.Mesh(
            new THREE.CylinderGeometry(0.012, 0.018, 0.6, 6),
            new THREE.MeshStandardMaterial({ color: 0x1c1e22, roughness: 0.5, metalness: 0.8 })
        );
        antenna.position.set(-0.28, 0.75, -0.18);
        g.add(antenna);
        g.position.set(x, terrainHeight(x, z), z);
        g.rotation.y = rot;
        this.scene.add(g);
        this._roots.push(g);
        this.collision.addBox(x, z, 0.42, 0.34, rot, 0.85);
    }

    // 撤离点：地面标线 + 信标灯杆 + 绿色信号烟
    _buildExtract(x, z) {
        const y0 = terrainHeight(x, z);
        const mark = new THREE.Mesh(
            new THREE.CircleGeometry(3.4, 48),
            new THREE.MeshBasicMaterial({ map: extractMarkTexture(), transparent: true, depthWrite: false })
        );
        mark.rotation.x = -Math.PI / 2;
        mark.rotation.z = -Math.PI / 2;   // 让 H 横杠对准东西向
        mark.position.set(x, y0 + 0.04, z);
        mark.renderOrder = 1;
        this.scene.add(mark);
        this._roots.push(mark);

        // 信标灯杆（立在圈外东南角）
        const bx = 47.8, bz = 11.5, by = terrainHeight(bx, bz);
        const pole = new THREE.Mesh(
            new THREE.CylinderGeometry(0.04, 0.05, 2.3, 8),
            new THREE.MeshStandardMaterial({ color: 0x3a3f42, roughness: 0.6, metalness: 0.7 })
        );
        pole.position.set(bx, by + 1.15, bz);
        pole.castShadow = true;
        this.scene.add(pole);
        this._beaconHead = new THREE.MeshStandardMaterial({
            color: 0x0d2414, emissive: new THREE.Color(0x46ff7d), emissiveIntensity: 2, roughness: 0.4,
        });
        const head = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), this._beaconHead);
        head.position.set(bx, by + 2.36, bz);
        this.scene.add(head);
        this._beaconLight = new THREE.PointLight(0x46ff7d, 2, 7, 2);
        this._beaconLight.position.set(bx, by + 2.4, bz);
        this.scene.add(this._beaconLight);
        this._roots.push(pole, head, this._beaconLight);
        this.collision.addBox(bx, bz, 0.12, 0.12, 0, 2.4);

        this._smoke = new SmokeColumn(this.scene, x, z);
    }

    // 靶道射位标线（黄色横条 + 立柱一对）
    _buildRangeMarks() {
        const stripeMat = new THREE.MeshBasicMaterial({ color: 0xd8c874, transparent: true, opacity: 0.75, depthWrite: false });
        const postMat = new THREE.MeshStandardMaterial({ color: 0x8a6f3a, roughness: 0.9 });
        for (const lane of [[-52, -14], [-52, -2], [-52, 10]]) {
            const [x, z] = lane;
            const y = terrainHeight(x, z);
            const stripe = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 0.45), stripeMat);
            stripe.rotation.x = -Math.PI / 2;
            stripe.rotation.z = -Math.PI / 2;
            stripe.position.set(x, y + 0.04, z);
            stripe.renderOrder = 1;
            this.scene.add(stripe);
            this._roots.push(stripe);
            for (const dz of [-1.6, 1.6]) {
                const post = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.75, 0.09), postMat);
                post.position.set(x - 1.3, y + 0.37, z + dz);
                post.castShadow = true;
                this.scene.add(post);
                this._roots.push(post);
            }
        }
    }

    // 土路：折线按 1.5m 采样，四角逐点贴地形
    _buildRoad(pts, width, mat) {
        const sample = [];
        for (let i = 0; i < pts.length - 1; i++) {
            const dx = pts[i + 1][0] - pts[i][0], dz = pts[i + 1][1] - pts[i][1];
            const L = Math.hypot(dx, dz);
            const n = Math.max(1, Math.ceil(L / 1.5));
            for (let k = (i === 0 ? 0 : 1); k <= n; k++) {
                sample.push([pts[i][0] + dx * k / n, pts[i][1] + dz * k / n]);
            }
        }
        const verts = [], uvs = [], idx = [];
        for (let i = 0; i < sample.length; i++) {
            const [x, z] = sample[i];
            const prev = sample[Math.max(0, i - 1)], next = sample[Math.min(sample.length - 1, i + 1)];
            let tx = next[0] - prev[0], tz = next[1] - prev[1];
            const tl = Math.hypot(tx, tz) || 1;
            tx /= tl; tz /= tl;
            const nx = -tz * width / 2, nz = tx * width / 2;
            const v = (i * 1.5) / 3.2;
            verts.push(x + nx, terrainHeight(x + nx, z + nz) + 0.035, z + nz);
            verts.push(x - nx, terrainHeight(x - nx, z - nz) + 0.035, z - nz);
            uvs.push(0, v, 1, v);
            if (i < sample.length - 1) {
                const b = i * 2;
                idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2);
            }
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
        geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
        geo.setIndex(idx);
        geo.computeVertexNormals();
        const road = new THREE.Mesh(geo, mat);
        road.receiveShadow = true;
        this.scene.add(road);
        this._roots.push(road);
    }
}
