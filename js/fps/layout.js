import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { boundaryBoxes, terrainHeight } from './env.js';
import { weaveHeight, speckleHeight, grainHeight, normalFromCanvas, toNormalTexture } from './normalmap.js';

/* =====================================================================
   js/fps/layout.js —— 战场摆布（【地图】组，8× 扩图版）
   分区（zoneAt）：中心危险区 r=80 军事基地（集装箱巷道/军火库/油库/情报点，
   精英 AI + 高品质容器 30）→ 80~112m 过渡带 → >112m 荒野环带
   （7 POI：农场/废车场/哨塔/营地/加油站/管道带/靶场，散兵 + 容器 22）。
   锚点：出生 (0,152) · 主撤离 (128,24) · 备撤离 (−136,96) · 情报 (32,−28.6)。
   ===================================================================== */

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

/* ==== 4. 分区 API：坐标 → 分区（战利品品质 / HUD 危险警示 / AI 强度共用） ==== */

// 中心危险区（军事基地）圆参数——zones.danger 同源；HUD 入区警示/精英 AI 以此判定
export const DANGER = { cx: 0, cz: -10, r: 80 };
// 分区边界数据：≤80 中心 / 80~112 过渡带 / >112 荒野环带（mapSpec 荒野 POI 全部 >112）
export const ZONE_BANDS = { dangerR: DANGER.r, wildR: 112 };

/* 坐标 → 分区名：'center'（危险区）| 'mid'（过渡）| 'wild'（荒野） */
export function zoneAt(x, z) {
    const d = Math.hypot(x - DANGER.cx, z - DANGER.cz);
    if (d <= ZONE_BANDS.dangerR) return 'center';
    if (d <= ZONE_BANDS.wildR) return 'mid';
    return 'wild';
}

/* ==== 5. 摆位表（手工排布、确定性可复现；n=道具 x/z=位置 r=朝向 s=缩放 y=离地叠层 t=染色 col=碰撞覆盖[hx,hz,h]） ==== */

const LAYOUT = [
    // —— 北缘：出生营（帐篷 + 沙袋线 + 物资，玩家出生其后 (−1,151)） ——
    { n: 'tent', x: 3.4, z: 152.2, r: -0.25, t: 0xb59f7a },
    { n: 'sandbags', x: -1.5, z: 148.6, r: 0.05 },
    { n: 'sandbags', x: 1.1, z: 148.4, r: -0.12 },
    { n: 'barrier', x: -4.6, z: 149.6, r: 0.18 },
    { n: 'barrier', x: 5.4, z: 148.9, r: -0.1 },
    { n: 'crate', x: 7.6, z: 155.0, r: 0.3, s: 0.95 },
    { n: 'crate', x: 8.7, z: 154.2, r: -0.2 },
    { n: 'barrel', x: -6.2, z: 153.0, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: -5.5, z: 153.6, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -6.1, z: 152.2, r: 0, t: 0x9fb4c6 },
    { n: 'wreck', x: 10.6, z: 150.8, r: 2.35 },
    { n: 'dead_tree', x: -8.5, z: 147.6, r: 0.7, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 6.5, z: 145.6, r: 2.1, col: [0.35, 0.35, 4.88] },

    // —— 中心危险区 · 核心掩体巷道（集装箱巷道 + 沙袋 + 油桶群 + 残骸 + 地堡，旧交战区保留） ——
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
    { n: 'bunker', x: 7.0, z: -26.5, r: 0 },

    // —— 中心危险区 · 西侧军火库（仓库 + 集装箱弹列 + 门前卸货台） ——
    { n: 'warehouse', x: -24, z: -44, r: 0, t: 0x8a8578 },
    { n: 'container', x: -39, z: -45, r: 1.57, t: 0x5a7050 },
    { n: 'container', x: -39, z: -39, r: 1.55, t: 0x8a4a44 },
    { n: 'container', x: -8.5, z: -48, r: -1.57, t: 0x3f6f8f },
    { n: 'crate', x: -16, z: -38.5, r: 0.25 },
    { n: 'crate', x: -15.2, z: -37.6, r: -0.3 },
    { n: 'barrel', x: -33, z: -37, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -32.2, z: -36.2, r: 0, t: 0x9fb4c6 },
    { n: 'sandbags', x: -24, z: -36.4, r: 0.04 },
    { n: 'barrier', x: -29, z: -36.8, r: -0.06 },
    { n: 'barrier', x: -19, z: -36.8, r: 0.08 },
    { n: 'dead_tree', x: -42, z: -52, r: 1.2, col: [0.35, 0.35, 4.88] },
    { n: 'wreck', x: -8, z: -52, r: -1.1 },

    // —— 中心危险区 · 东侧油库（双立式油罐 + 桶阵 + 警戒沙袋） ——
    { n: 'fuel_tank', x: 26.0, z: -19.0, r: 0.25, t: 0x8f8578 },
    { n: 'fuel_tank', x: 44.0, z: -40.0, r: -0.12, t: 0x9a9484 },
    { n: 'barrel', x: 20.0, z: -25.5, r: 0, t: 0xb0452f },
    { n: 'barrel', x: 20.8, z: -24.8, r: 0, t: 0x8f8a4a },
    { n: 'barrel', x: 19.3, z: -24.9, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 50.5, z: -35.0, r: 0, t: 0x8f8a4a },
    { n: 'sandbags', x: 33.0, z: -20.5, r: 1.4 },
    { n: 'wreck', x: 49.5, z: -24.5, r: 0.9 },
    { n: 'barrier', x: 38.5, z: -22.5, r: 1.35 },

    // —— 中心危险区 · 北门 / 东门（检查站 + 哨塔，土路穿门而过） ——
    { n: 'barrier', x: -3.0, z: 60.5, r: 0.06 },
    { n: 'barrier', x: 4.8, z: 60.0, r: -0.08 },
    { n: 'sandbags', x: -6.5, z: 58.6, r: 0.1 },
    { n: 'sandbags', x: 7.2, z: 58.2, r: -0.15 },
    { n: 'barrier', x: 56.5, z: -4.5, r: 1.5 },
    { n: 'barrier', x: 59.5, z: -1.5, r: 1.45 },
    { n: 'sandbags', x: 55.0, z: 0.5, r: 1.55 },

    // —— 中心危险区 · 东北情报点（小屋 + 帐篷营地，情报箱在屋前，位置保留） ——
    { n: 'house', x: 32.0, z: -32.5, r: 0.06, t: 0xc7b394 },
    { n: 'tent', x: 40.5, z: -29.5, r: -0.45, t: 0x8fa08f },
    { n: 'crate', x: 29.0, z: -27.6, r: 0.35 },
    { n: 'barrel', x: 36.2, z: -26.4, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 35.6, z: -25.6, r: 0, t: 0xb0452f },
    { n: 'sandbags', x: 27.0, z: -30.5, r: 1.5 },
    { n: 'dead_tree', x: 44.5, z: -35.0, r: 0.9, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 26.5, z: -38.5, r: 2.6, col: [0.35, 0.35, 4.88] },
    { n: 'wreck', x: 38.5, z: -37.5, r: 2.2 },

    // —— 荒野 POI · 农场（谷仓 + 农舍，西北向） ——
    { n: 'barn', x: -104, z: 84, r: 0.3, t: 0xa4552f },
    { n: 'house', x: -92, z: 70, r: -0.5, t: 0xb0a184 },
    { n: 'dead_tree', x: -112, z: 92, r: 0.4, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -97, z: 96, r: 2.6, col: [0.35, 0.35, 4.88] },
    { n: 'crate', x: -99.6, z: 93.4, r: 0.2 },
    { n: 'barrel', x: -110, z: 78, r: 0, t: 0x8f8a4a },
    { n: 'wreck', x: -90, z: 90, r: 1.3 },
    { n: 'sandbags', x: -98, z: 75, r: 0.9 },
    { n: 'dead_tree', x: -116, z: 76, r: 1.9, col: [0.35, 0.35, 4.88] },

    // —— 荒野 POI · 废车场（残骸群正西向） ——
    { n: 'wreck', x: -148, z: 8, r: 0.2 },
    { n: 'wreck', x: -153, z: 3, r: -1.1 },
    { n: 'wreck', x: -143, z: 2, r: 2.4 },
    { n: 'wreck', x: -151, z: 13, r: 1.1 },
    { n: 'wreck', x: -144, z: 14, r: -0.6 },
    { n: 'wreck', x: -157, z: 9, r: 0.9 },
    { n: 'barrel', x: -147, z: 3, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -146.2, z: 2.3, r: 0, t: 0x9fb4c6 },
    { n: 'rocks', x: -140, z: 16, r: 0.4 },
    { n: 'dead_tree', x: -156, z: -4, r: 0.8, col: [0.35, 0.35, 4.88] },
    { n: 'sandbags', x: -141, z: 9, r: -0.4 },

    // —— 荒野 POI · 哨塔（程序化瞭望塔 + 驻勤帐篷） ——
    { n: 'tent', x: -113, z: -78, r: 0.35, t: 0x8f8a78 },
    { n: 'sandbags', x: -103, z: -79, r: 0.2 },
    { n: 'sandbags', x: -102, z: -82, r: -0.3 },
    { n: 'barrel', x: -112, z: -90, r: 0, t: 0x8f8a4a },
    { n: 'dead_tree', x: -100, z: -93, r: 1.4, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -115, z: -94, r: 2.7, col: [0.35, 0.35, 4.88] },
    { n: 'crate', x: -104, z: -90, r: -0.2 },

    // —— 荒野 POI · 露营营地（三帐环抱 + 篝火桶） ——
    { n: 'tent', x: -32, z: -136, r: 0.15, t: 0x8f9a8a },
    { n: 'tent', x: -24, z: -142, r: 1.2, t: 0xb59f7a },
    { n: 'tent', x: -40, z: -142, r: -0.8, t: 0x8fa08f },
    { n: 'barrel', x: -30, z: -131, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -29.2, z: -130.3, r: 0, t: 0x9fb4c6 },
    { n: 'crate', x: -36, z: -130, r: 0.35 },
    { n: 'crate', x: -35.2, z: -129.1, r: -0.25 },
    { n: 'dead_tree', x: -20, z: -132, r: 0.6, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -44, z: -130, r: 1.8, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -30, z: -150, r: 2.9, col: [0.35, 0.35, 4.88] },

    // —— 荒野 POI · 加油站（立罐 + 雨棚柱 + 抛锚车） ——
    { n: 'fuel_tank', x: 56, z: -142, r: 0.1, t: 0x9a9484 },
    { n: 'barrier', x: 47.5, z: -133.5, r: 1.5 },
    { n: 'barrier', x: 52.5, z: -133.5, r: 1.45 },
    { n: 'wreck', x: 63, z: -135, r: 0.7 },
    { n: 'barrel', x: 61, z: -148, r: 0, t: 0xb0452f },
    { n: 'barrel', x: 60.2, z: -147.2, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 48, z: -146, r: 0, t: 0x8f8a4a },
    { n: 'dead_tree', x: 66, z: -146, r: 1.1, col: [0.35, 0.35, 4.88] },
    { n: 'sandbags', x: 49, z: -149, r: 0.3 },

    // —— 荒野 POI · 管道带（废弃输送管三节 + 乱石） ——
    { n: 'container', x: 128, z: -84, r: 1.57, t: 0x6f6a5f },
    { n: 'container', x: 136, z: -84, r: 1.55, t: 0x7d5a45 },
    { n: 'container', x: 144, z: -84, r: 1.57, t: 0x5a7050 },
    { n: 'rocks', x: 132, z: -94, r: 0.5 },
    { n: 'rocks', x: 147, z: -101, r: -0.7 },
    { n: 'barrel', x: 124, z: -90, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 123.2, z: -89.2, r: 0, t: 0xb0452f },
    { n: 'sandbags', x: 148, z: -90, r: 1.2 },
    { n: 'dead_tree', x: 150, z: -100, r: 0.5, col: [0.35, 0.35, 4.88] },

    // —— 荒野 POI · 靶场（仓库挡弹墙 + 集装箱档弹排 + 三条靶道，自旧西靶场整体搬迁） ——
    { n: 'warehouse', x: -43, z: 108, r: 0, t: 0x9c8f7d },
    { n: 'container', x: -27, z: 119.5, r: 0.02, t: 0x3f6f8f },
    { n: 'container', x: -27, z: 125.75, r: -0.02, t: 0x8f5a3f },
    { n: 'container', x: -27, z: 132.0, r: 0.02, t: 0x5a7050 },
    { n: 'container', x: -27, z: 138.25, r: -0.02, t: 0x8a4a44 },
    { n: 'container', x: -27, z: 144.5, r: 0.02, t: 0x6f6a5f },
    { n: 'rocks', x: -45, z: 151.5, r: 0.06 },
    { n: 'sandbags', x: -34.5, z: 151.2, r: 0.1 },
    { n: 'crate', x: -58.8, z: 120.4, r: 0.2 },
    { n: 'crate', x: -58.8, z: 132.4, r: -0.3 },
    { n: 'crate', x: -58.8, z: 144.4, r: 0.15 },
    { n: 'barrel', x: -60.5, z: 116.8, r: 0, t: 0xb0452f },
    { n: 'barrel', x: -60.2, z: 149.6, r: 0, t: 0x9fb4c6 },
    { n: 'dead_tree', x: -61.8, z: 112.5, r: 1.2, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -50, z: 116, r: 2.0, col: [0.35, 0.35, 4.88] },
    { n: 'wreck', x: -31, z: 153.5, r: 1.1 },

    // —— 撤离点 ×2（绿烟信标由 BattleMap 摆放，此处摆外圈残骸/枯树/油桶） ——
    { n: 'wreck', x: 135, z: 30, r: 1.35 },                 // 主撤离 (128,24)
    { n: 'dead_tree', x: 141, z: 17, r: 1.8, col: [0.35, 0.35, 4.88] },
    { n: 'barrel', x: 131, z: 19.0, r: 0, t: 0x9fb4c6 },
    { n: 'barrel', x: 130.2, z: 19.8, r: 0, t: 0xb0452f },
    { n: 'wreck', x: -143, z: 101, r: -1.2 },               // 备撤离 (−136,96)
    { n: 'dead_tree', x: -147, z: 91, r: 0.9, col: [0.35, 0.35, 4.88] },
    { n: 'barrel', x: -133, z: 92.0, r: 0, t: 0xb0452f },
    { n: 'sandbags', x: -140, z: 90.5, r: 0.7 },

    // —— 过渡带/荒野散布：枯树·乱石·残骸·弃桶（地标与废墟感，确定性坐标） ——
    { n: 'dead_tree', x: 106.9, z: 67.1, r: 0.25, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -121.7, z: -115.8, r: 3.11, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -104.5, z: -33.4, r: 3.87, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 108.5, z: -114.7, r: 6.04, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -143.1, z: -72.1, r: 4.29, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -157.3, z: -54.3, r: 5.08, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 99.5, z: 117.5, r: 3.05, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 68.9, z: -94.8, r: 3.71, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 105.6, z: 63.1, r: 5.56, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 129.5, z: -18.5, r: 5.27, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -96.2, z: -60.3, r: 3.37, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: -143.4, z: 50.4, r: 4.7, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 98.7, z: 75.6, r: 1.82, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 32.1, z: 92.0, r: 2.98, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 109.0, z: -27.0, r: 1.65, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 98.2, z: -120.0, r: 0.84, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 110.9, z: -124.7, r: 5.0, col: [0.35, 0.35, 4.88] },
    { n: 'dead_tree', x: 88.0, z: 54.7, r: 0.49, col: [0.35, 0.35, 4.88] },
    { n: 'rocks', x: 37.5, z: -105.3, r: 2.65 },
    { n: 'rocks', x: -69.2, z: 63.4, r: 5.31 },
    { n: 'rocks', x: 125.4, z: 71.9, r: 3.04 },
    { n: 'rocks', x: 38.4, z: 86.6, r: 4.33 },
    { n: 'rocks', x: 10.9, z: 88.8, r: 3.14 },
    { n: 'rocks', x: 128.3, z: -12.3, r: 4.87 },
    { n: 'rocks', x: -55.1, z: -126.6, r: 4.41 },
    { n: 'wreck', x: -53.8, z: 97.2, r: 0.13 },
    { n: 'wreck', x: 108.1, z: -32.7, r: 1.59 },
    { n: 'wreck', x: 149.8, z: -32.7, r: 2.58 },
    { n: 'barrel', x: 125.1, z: 84.0, r: 3.47 },
    { n: 'barrel', x: 85.7, z: -54.5, r: 1.81 },
];

/* ==== 6. 可搜刮容器锚点（52 处，LootManager 据此实例化容器与刷 loot；
 * type ∈ CONTAINER_TYPES（loot.js 约定）；zone ∈ 'center'|'wild' 与 zoneAt 一致；
 * 品质分布按 mapSpec：中心 30（含保险箱/军火库各 1），荒野 22 全部低 bias 档） ==== */

export const CONTAINER_SPOTS = [
    // —— 中心 · 军火库（仓库门前） ——
    { type: 'rack', x: -24, z: -34.6, rotY: 0.1, zone: 'center' },
    { type: 'crate', x: -14.5, z: -35.5, rotY: 0.4, zone: 'center' },
    { type: 'toolbox', x: -30.5, z: -34.8, rotY: -0.3, zone: 'center' },
    { type: 'crate', x: -38.6, z: -41.6, rotY: 0.3, zone: 'center' },
    { type: 'ammo', x: -27.8, z: -52.2, rotY: 0.1, zone: 'center' },
    { type: 'crate', x: -19.6, z: -51.6, rotY: -0.25, zone: 'center' },
    { type: 'toolbox', x: -43.2, z: -48.8, rotY: 0.4, zone: 'center' },
    // —— 中心 · 核心巷道 ——
    { type: 'crate', x: 6.8, z: -2.6, rotY: 0.2, zone: 'center' },
    { type: 'ammo', x: -6.5, z: -10.8, rotY: -0.15, zone: 'center' },
    { type: 'ammo', x: 4.3, z: -16.8, rotY: 0.3, zone: 'center' },
    { type: 'ammo', x: -13.4, z: -14.6, rotY: 0.2, zone: 'center' },
    { type: 'duffle', x: 2.6, z: -11.6, rotY: 0.1, zone: 'center' },
    { type: 'drawer', x: -7.2, z: -10.2, rotY: 0.25, zone: 'center' },
    { type: 'crate', x: -9.8, z: -5.6, rotY: 0.1, zone: 'center' },
    { type: 'crate', x: 11.4, z: -13.4, rotY: -0.2, zone: 'center' },
    { type: 'duffle', x: -12.2, z: -0.6, rotY: 0.5, zone: 'center' },
    // —— 中心 · 地堡/油库一带 ——
    { type: 'medcab', x: 8.4, z: -19.6, rotY: 0.5, zone: 'center' },
    { type: 'medcab', x: -2.2, z: -24.2, rotY: -0.2, zone: 'center' },
    { type: 'safe', x: 16.9, z: -28.4, rotY: 0.2, zone: 'center' },
    { type: 'drawer', x: -6.2, z: -22.6, rotY: -0.35, zone: 'center' },
    { type: 'ammo', x: 16.4, z: -24.2, rotY: 0.35, zone: 'center' },
    { type: 'crate', x: 20.2, z: -28.9, rotY: -0.3, zone: 'center' },
    { type: 'toolbox', x: 35.4, z: -17.4, rotY: 0.5, zone: 'center' },
    { type: 'ammo', x: 46.8, z: -30.2, rotY: -0.1, zone: 'center' },
    { type: 'medcab', x: 52.6, z: -38.4, rotY: 0.2, zone: 'center' },
    { type: 'toolbox', x: 26.2, z: -6.8, rotY: 0.1, zone: 'center' },
    { type: 'duffle', x: 21.2, z: -9.4, rotY: 0.3, zone: 'center' },
    // —— 中心 · 情报建筑区 ——
    { type: 'medcab', x: 34.8, z: -25.4, rotY: -0.2, zone: 'center' },
    { type: 'duffle', x: 45.6, z: -24.8, rotY: 0.3, zone: 'center' },
    { type: 'crate', x: 27.2, z: -27.8, rotY: 0.15, zone: 'center' },
    // —— 荒野 · 农场 ——
    { type: 'crate', x: -95.4, z: 76.2, rotY: 0.4, zone: 'wild' },
    { type: 'drawer', x: -89, z: 78.5, rotY: -0.3, zone: 'wild' },
    { type: 'duffle', x: -109.6, z: 91.4, rotY: 0.2, zone: 'wild' },
    // —— 荒野 · 废车场 ——
    { type: 'ammo', x: -140.6, z: 22.4, rotY: 0.3, zone: 'wild' },
    { type: 'crate', x: -149.2, z: 1.8, rotY: -0.2, zone: 'wild' },
    { type: 'toolbox', x: -138.4, z: -0.6, rotY: 0.1, zone: 'wild' },
    // —— 荒野 · 哨塔 ——
    { type: 'medcab', x: -106.8, z: -77.4, rotY: -0.2, zone: 'wild' },
    { type: 'duffle', x: -103.6, z: -87.2, rotY: 0.4, zone: 'wild' },
    { type: 'crate', x: -112.8, z: -88.6, rotY: 0.15, zone: 'wild' },
    // —— 荒野 · 露营营地 ——
    { type: 'duffle', x: -26.2, z: -130.8, rotY: 0.2, zone: 'wild' },
    { type: 'medcab', x: -33.4, z: -145.8, rotY: 0.5, zone: 'wild' },
    { type: 'drawer', x: -21.4, z: -135.4, rotY: -0.3, zone: 'wild' },
    // —— 荒野 · 加油站 ——
    { type: 'toolbox', x: 66.8, z: -138.2, rotY: -0.4, zone: 'wild' },
    { type: 'crate', x: 50.2, z: -150.4, rotY: 0.3, zone: 'wild' },
    { type: 'ammo', x: 63.2, z: -150.2, rotY: 0.1, zone: 'wild' },
    // —— 荒野 · 管道带 ——
    { type: 'crate', x: 127.8, z: -88.0, rotY: 0.2, zone: 'wild' },
    { type: 'drawer', x: 140.6, z: -87.6, rotY: -0.15, zone: 'wild' },
    { type: 'ammo', x: 131.0, z: -87.2, rotY: 0.35, zone: 'wild' },
    // —— 荒野 · 靶场 ——
    { type: 'crate', x: -55.2, z: 123.8, rotY: 0.1, zone: 'wild' },
    { type: 'drawer', x: -50.6, z: 140.2, rotY: 0.4, zone: 'wild' },
    { type: 'medcab', x: -36.8, z: 152.2, rotY: -0.2, zone: 'wild' },
    { type: 'duffle', x: -66.4, z: 123.2, rotY: 0.25, zone: 'wild' },
];

// 土路（纯视觉）三线：出生→北门→基地核心；核心→主撤离；核心→备撤离
const ROADS = [
    [[0, 150], [0, 116], [0, 84], [1, 62], [0, 40], [3, 18], [2, 2]],
    [[8, -4], [38, -2], [68, 4], [98, 12], [126, 22]],
    [[-6, -16], [-36, -8], [-68, 16], [-100, 48], [-134, 92]],
];

/* 巡逻线（spawnPatrol 分区契约）：
 * 中心 4 条 = 精英 10（assault×4 / support×4 / recon×2，battlefield.gd:26-38 原值）；
 * 荒野 4 条 = 散兵 8（wild 档弱化，viewDist 50）。mix=一线混编多兵种。 */
const PATROL_ROUTES = [
    { pts: [[-40, 30], [8, 44], [38, 20], [20, -6], [-18, 6]], cls: 'elite', variant: 'assault', count: 2 },
    { pts: [[20, -30], [46, -24], [54, 2], [30, 14], [6, 2]], cls: 'elite', variant: 'assault', count: 2 },
    { pts: [[-14, -46], [-44, -40], [-56, -12], [-36, 4], [-10, -8]], cls: 'elite', mix: [['support', 2], ['recon', 1]] },
    { pts: [[24, -52], [0, -64], [-28, -56], [-44, -30], [-16, -22]], cls: 'elite', mix: [['support', 2], ['recon', 1]] },
    { pts: [[-40, 118], [-70, 104], [-100, 88], [-112, 64], [-104, 120], [-64, 134]], cls: 'wild', variant: 'rifleman', count: 2 },
    { pts: [[-148, 8], [-154, -30], [-138, -62], [-112, -84], [-100, -52], [-118, -16]], cls: 'wild', variant: 'scout', count: 2 },
    { pts: [[-32, -136], [4, -152], [44, -150], [80, -134], [96, -104], [58, -120], [12, -124]], cls: 'wild', variant: 'rifleman', count: 2 },
    { pts: [[136, -88], [150, -46], [148, -2], [138, 42], [122, 74], [112, 20], [118, -52]], cls: 'wild', variant: 'scout', count: 2 },
];

// 撤离点 / 情报点 / 靶道（构建期锚点，zones 同源输出）
const EXTRACT_MAIN = [128, 24];
const EXTRACT_BACK = [-136, 96];
const RANGE_LANES = [[-57, 122], [-57, 134], [-57, 146]];   // 射位（向 +X 射击，x=−27 集装箱档弹）

/* ==== 7. 程序化小件贴图：烟团 / 撤离地标线 / 土路 ==== */

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

/* ==== 8. 信号烟粒子柱（撤离点绿色信号烟，Points + 自写软烟着色器） ==== */

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

/* ==== 9. 瞭望哨塔（程序化：木柱/平台/护栏/爬梯/顶板，合批为 2 网格共享素材） ==== */

let _towerGeo = null, _towerMats = null;
function watchtowerAssets() {
    if (_towerGeo) return { geo: _towerGeo, mats: _towerMats };
    const wood = [], roof = [];
    const box = (w, h, d, x, y, z, arr) => {
        const g = new THREE.BoxGeometry(w, h, d);
        g.translate(x, y, z);
        arr.push(g);
    };
    for (const sx of [-1.1, 1.1]) for (const sz of [-1.1, 1.1]) box(0.24, 5.4, 0.24, sx, 2.7, sz, wood);
    box(3.4, 0.16, 3.4, 0, 5.4, 0, wood);              // 平台
    box(3.4, 0.5, 0.08, 0, 5.95, -1.66, wood);         // 护栏三面
    box(3.4, 0.5, 0.08, 0, 5.95, 1.66, wood);
    box(0.08, 0.5, 3.4, -1.66, 5.95, 0, wood);
    box(0.6, 5.4, 0.07, 0, 2.7, 1.82, wood);           // 爬梯背板
    for (let k = 0; k < 8; k++) box(0.55, 0.06, 0.14, 0, 0.7 + k * 0.62, 1.78, wood);
    for (const sx of [-1.3, 1.3]) box(0.14, 1.5, 0.14, sx, 6.85, 0, wood);   // 顶柱
    box(4.0, 0.14, 4.0, 0, 7.65, 0, roof);             // 顶板
    box(4.0, 0.3, 1.7, 0, 7.5, -1.15, roof);           // 顶檐（军绿）
    _towerGeo = [mergeGeometries(wood), mergeGeometries(roof)];
    _towerMats = [
        new THREE.MeshStandardMaterial({ color: 0x6b543c, roughness: 0.95, metalness: 0 }),
        new THREE.MeshStandardMaterial({ color: 0x4a5342, roughness: 0.9, metalness: 0 }),
    ];
    return { geo: _towerGeo, mats: _towerMats };
}

/* ==== 10. BattleMap：按摆位表布置战场，产出 zones 与碰撞 ==== */

export class BattleMap {
    constructor(scene, props) {
        this.scene = scene;
        this.props = props;
        this.collision = new CollisionWorld();
        this.missing = (props && props.missing) || [];
        this.zones = null;
        this._t = 0;
        this._roots = [];          // 便于整体卸载
        this._smokes = [];         // 撤离点绿烟 ×2
        this._beacons = [];        // 撤离信标 ×2（相错相位闪烁）
        this._intelMat = null;
    }

    async build() {
        // —— 摆件（视觉 + 自动按包围盒注册 OBB 碰撞） ——
        for (const e of LAYOUT) this._prop(e);

        // —— 场地边界（墙体视觉在 env.js，碰撞在这里注册；±ARENA 链式满覆盖） ——
        for (const b of boundaryBoxes()) {
            this.collision.addBox(b.cx, b.cz, b.hx, b.hz, b.rotY, b.h);
        }

        // —— 土路（纯视觉，三线） ——
        const roadMat = new THREE.MeshStandardMaterial({
            map: roadTexture(), roughness: 1, metalness: 0, side: THREE.DoubleSide,
        });
        for (const line of ROADS) this._buildRoad(line, 3.2, roadMat);

        // —— 哨塔 ×3（北门 / 东门 / 荒野哨塔 POI） ——
        this._buildWatchtower(5, 67);
        this._buildWatchtower(62, -6);
        this._buildWatchtower(-108, -84);

        // —— 情报箱（呼吸灯） + 撤离点 ×2（绿烟 + 信标 + 地面标线） + 靶道射位标线 ——
        this._buildIntel(32.9, -28.2, 0.35);
        this._buildExtract(EXTRACT_MAIN[0], EXTRACT_MAIN[1]);
        this._buildExtract(EXTRACT_BACK[0], EXTRACT_BACK[1]);
        this._buildRangeMarks();

        // —— 交给任务/AI/战利品的锚点 ——
        this.zones = {
            playerSpawn: this._v(-1.6, 150.6),
            patrol: PATROL_ROUTES.map((rt) => ({
                pts: rt.pts.map((p) => this._v(p[0], p[1])),
                cls: rt.cls,
                ...(rt.variant ? { variant: rt.variant } : {}),
                ...(rt.variant ? { count: rt.count } : {}),
                ...(rt.mix ? { mix: rt.mix } : {}),
            })),
            intelPos: this._v(32.0, -28.6),
            extractPos: [this._v(EXTRACT_MAIN[0], EXTRACT_MAIN[1]),
                         this._v(EXTRACT_BACK[0], EXTRACT_BACK[1])],   // mission 取最近者
            extractR: 3.2,
            danger: { cx: DANGER.cx, cz: DANGER.cz, r: DANGER.r },     // HUD 入区警示用
            rangeLanes: RANGE_LANES.map(([x, z]) => ({
                origin: this._v(x, z), dir: new THREE.Vector3(1, 0, 0),
            })),
            containerSpots: CONTAINER_SPOTS,
        };
        return this;
    }

    update(dt) {
        this._t += dt;
        for (const s of this._smokes) s.update(dt, this._t);
        for (const b of this._beacons) {
            const on = Math.sin(this._t * 4.2 + b.phase) > 0.35;
            b.light.intensity = on ? 2.6 : 0.1;
            b.head.emissiveIntensity = on ? 2.4 : 0.12;
        }
        if (this._intelMat) {
            this._intelMat.emissiveIntensity = 0.5 + 0.65 * (0.5 + 0.5 * Math.sin(this._t * 2.6));
        }
    }

    dispose() {
        for (const r of this._roots) this.scene.remove(r);
        this._roots.length = 0;
        for (const s of this._smokes) s.dispose(this.scene);
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

    // 撤离点：地面标线 + 信标灯杆 + 绿色信号烟（主/备两点复用同一套组件）
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
        const bx = x + 3.8, bz = z + 3.5, by = terrainHeight(bx, bz);
        const pole = new THREE.Mesh(
            new THREE.CylinderGeometry(0.04, 0.05, 2.3, 8),
            new THREE.MeshStandardMaterial({ color: 0x3a3f42, roughness: 0.6, metalness: 0.7 })
        );
        pole.position.set(bx, by + 1.15, bz);
        pole.castShadow = true;
        this.scene.add(pole);
        const headMat = new THREE.MeshStandardMaterial({
            color: 0x0d2414, emissive: new THREE.Color(0x46ff7d), emissiveIntensity: 2, roughness: 0.4,
        });
        const head = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), headMat);
        head.position.set(bx, by + 2.36, bz);
        this.scene.add(head);
        const light = new THREE.PointLight(0x46ff7d, 2, 7, 2);
        light.position.set(bx, by + 2.4, bz);
        this.scene.add(light);
        this._roots.push(pole, head, light);
        this.collision.addBox(bx, bz, 0.12, 0.12, 0, 2.4);
        this._beacons.push({ light, head: headMat, phase: this._beacons.length * 1.7 });

        this._smokes.push(new SmokeColumn(this.scene, x, z));
    }

    // 瞭望哨塔：四腿注册碰撞（平台不可攀，地标/掩体用）
    _buildWatchtower(x, z) {
        const { geo, mats } = watchtowerAssets();
        const g = new THREE.Group();
        for (let k = 0; k < 2; k++) {
            const m = new THREE.Mesh(geo[k], mats[k]);
            m.castShadow = m.receiveShadow = true;
            g.add(m);
        }
        g.position.set(x, terrainHeight(x, z) - 0.05, z);
        this.scene.add(g);
        this._roots.push(g);
        for (const sx of [-1.1, 1.1]) for (const sz of [-1.1, 1.1]) {
            this.collision.addBox(x + sx, z + sz, 0.16, 0.16, 0, 5.4);
        }
    }

    // 靶道射位标线（黄色横条 + 立柱一对）
    _buildRangeMarks() {
        const stripeMat = new THREE.MeshBasicMaterial({ color: 0xd8c874, transparent: true, opacity: 0.75, depthWrite: false });
        const postMat = new THREE.MeshStandardMaterial({ color: 0x8a6f3a, roughness: 0.9 });
        for (const [x, z] of RANGE_LANES) {
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
