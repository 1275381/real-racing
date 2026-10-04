#!/usr/bin/env osascript -l JavaScript
// 场景组无浏览器自检：剥离 import/export 后在 JXA 中真实执行 env.js / layout.js，
// 用桩 THREE/document 跑通 BattleMap.build()，再对真实注册的碰撞盒与 zones 做几何断言。

const ROOT = '/Users/chen/Documents/赛场游戏/';
const app = Application.currentApplication();
app.includeStandardAdditions = true;

/* ---- 桩：THREE（Vector3 为真实现，其余一律万能代理）与 document ---- */
const magicTarget = function () {};
const magic = new Proxy(magicTarget, {
    get(t, k) {
        if (k === Symbol.toPrimitive) return () => 0;
        if (k === 'then') return undefined;
        return magic;
    },
    set() { return true; },
    apply() { return magic; },
    construct() { return magic; },
});
class RealVector3 {
    constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; }
    set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; }
    copy(v) { this.x = v.x; this.y = v.y; this.z = v.z; return this; }
    addScaledVector(v, s) { this.x += v.x * s; this.y += v.y * s; this.z += v.z * s; return this; }
    length() { return Math.hypot(this.x, this.y, this.z); }
    normalize() { const l = this.length() || 1; return this.multiplyScalar(1 / l); }
    multiplyScalar(s) { this.x *= s; this.y *= s; this.z *= s; return this; }
    clone() { return new RealVector3(this.x, this.y, this.z); }
}
const THREE = new Proxy({}, {
    get(t, k) { return k === 'Vector3' ? RealVector3 : magic; },
});
const document = { createElement: () => magic };
if (!console.warn) console.warn = console.log;   // JXA 无 console.warn

/* ---- 读取并剥掉 import/export，直译执行模块 ---- */
function loadModule(path, prelude, exportsExpr) {
    let src = app.read(Path(ROOT + path));
    src = src.replace(/^import[^\n]*$/gm, '')
             .replace(/^export\s+(?=(async\s+function|function|class|const)\b)/gm, '');
    return eval('(function(){\n' + prelude + '\n' + src + '\nreturn (' + exportsExpr + ');\n})()');
}

const ENV = loadModule('js/fps/env.js', '', '({ ARENA, BOUNDARY_H, terrainHeight, boundaryBoxes, Environment })');
const LAY = loadModule(
    'js/fps/layout.js',
    'const boundaryBoxes = ENV.boundaryBoxes, terrainHeight = ENV.terrainHeight, ARENA = ENV.ARENA;',
    '({ loadProps, CollisionWorld, BattleMap, LAYOUT, PROP_DIMS, ROADS, PATROL_ROUTES })'
);

/* ---- 断言工具 ---- */
let pass = 0, fail = 0;
function check(name, ok, detail) {
    if (ok) { pass++; console.log('PASS  ' + name + (detail ? '  [' + detail + ']' : '')); }
    else { fail++; console.log('FAIL  ' + name + '  [' + detail + ']'); }
}

/* ---- 1. CollisionWorld 单元断言 ---- */
(function () {
    const cw = new LAY.CollisionWorld();
    cw.addBox(0, 0, 1, 1, 0, 2);
    const top = ENV.terrainHeight(0, 0) + 2;
    const d1 = cw.rayWall({ x: 0, y: 1, z: 5 }, { x: 0, y: 0, z: -1 }, 50);
    check('rayWall 正面命中距离=4.0', Math.abs(d1 - 4) < 1e-6, 'd=' + d1.toFixed(4) + ' top=' + top.toFixed(3));
    const d2 = cw.rayWall({ x: 0, y: top + 1, z: 5 }, { x: 0, y: 0, z: -1 }, 50);
    check('rayWall 高于墙顶→Infinity', d2 === Infinity, 'd=' + d2);
    const d3 = cw.rayWall({ x: 0, y: 1.6, z: 0 }, { x: 0, y: 1, z: 0 }, 50);
    check('rayWall 起点在盒内→0（既定行为，同 battle_map.gd）', d3 === 0, 'd=' + d3);
    const p = cw.pushOut(0.5, 0, 0.45);
    check('pushOut 沿 X 推出到 1.45', Math.abs(p.x - 1.45) < 1e-6 && Math.abs(p.z) < 1e-6,
        'p=(' + p.x.toFixed(3) + ',' + p.z.toFixed(3) + ')');
    check('groundHeight=terrainHeight', cw.groundHeight(12.3, -45.6) === ENV.terrainHeight(12.3, -45.6), '');
})();

/* ---- 2. BattleMap.build() 全量执行（桩 props/scene） ---- */
const sceneStub = { n: 0, add() { this.n++; }, remove() {} };
const propsStub = {
    missing: [],
    make() { return { position: { set() {} }, rotation: {}, scale: { setScalar() {} }, traverse() {}, name: '' }; },
};
const bm = new LAY.BattleMap(sceneStub, propsStub);
bm.build();
bm.update(0.016); bm.update(0.016);
const cw = bm.collision;
const zones = bm.zones;
check('build() 无异常且注册碰撞盒 ≥ 100', cw.boxes.length >= 100, 'boxes=' + cw.boxes.length + ' scene.add=' + sceneStub.n);
check('zones 就绪', !!zones && !!zones.playerSpawn && zones.extractR === 3, '');

/* ---- 3. 摆位表两两 OBB 重叠审计（SAT，容差 0.10m，叠层豁免） ---- */
function obbOf(e) {
    const d = LAY.PROP_DIMS[e.n];
    const s = e.s || 1;
    const hx = e.col ? e.col[0] : d[0] * 0.5 * s;
    const hz = e.col ? e.col[1] : d[2] * 0.5 * s;
    const r = e.r || 0;
    return { cx: e.x, cz: e.z, hx, hz, c: Math.cos(r), s: Math.sin(r), n: e.n, y: e.y || 0 };
}
const obbs = LAY.LAYOUT.map(obbOf);
function satPen(A, B) {
    const dx = B.cx - A.cx, dz = B.cz - A.cz;
    const axes = [[A.c, A.s], [-A.s, A.c], [B.c, B.s], [-B.s, B.c]];
    let minPen = Infinity;
    for (const [ax, az] of axes) {
        const dist = Math.abs(dx * ax + dz * az);
        const ra = A.hx * Math.abs(A.c * ax + A.s * az) + A.hz * Math.abs(-A.s * ax + A.c * az);
        const rb = B.hx * Math.abs(B.c * ax + B.s * az) + B.hz * Math.abs(-B.s * ax + B.c * az);
        const pen = ra + rb - dist;
        if (pen <= 0.10) return -1;
        if (pen < minPen) minPen = pen;
    }
    return minPen;
}
let overlaps = [];
for (let i = 0; i < obbs.length; i++) {
    for (let j = i + 1; j < obbs.length; j++) {
        const A = obbs[i], B = obbs[j];
        const stacked = Math.abs(A.cx - B.cx) < 0.5 && Math.abs(A.cz - B.cz) < 0.5 && (A.y > 0 || B.y > 0);
        if (stacked) continue;
        const pen = satPen(A, B);
        if (pen > 0) overlaps.push(A.n + '@(' + A.cx + ',' + A.cz + ') × ' + B.n + '@(' + B.cx + ',' + B.cz + ') pen=' + pen.toFixed(2));
    }
}
check('摆件两两无重叠（>10cm）', overlaps.length === 0, overlaps.slice(0, 6).join(' | '));

/* ---- 4. 场地边界包含 ---- */
let out = [];
for (const o of obbs) {
    const ex = Math.abs(o.c) * o.hx + Math.abs(o.s) * o.hz;
    const ez = Math.abs(o.s) * o.hx + Math.abs(o.c) * o.hz;
    if (Math.abs(o.cx) + ex > 59.9 || Math.abs(o.cz) + ez > 59.9) out.push(o.n + '@(' + o.cx + ',' + o.cz + ')');
}
check('摆件全部在 ±60 边界内', out.length === 0, out.join(' | '));

/* ---- 5. 关键点净空（不落在任何碰撞盒内） ---- */
function insideAny(x, z, m) {
    for (const b of cw.boxes) {
        const dx = x - b.cx, dz = z - b.cz;
        const lx = b.c * dx + b.s * dz;
        const lz = -b.s * dx + b.c * dz;
        if (Math.abs(lx) < b.hx + m && Math.abs(lz) < b.hz + m) return b;
    }
    return null;
}
const clear = [];
function clearPoint(tag, x, z, m) {
    const hit = insideAny(x, z, m);
    if (hit) clear.push(tag + '(' + x + ',' + z + ') m=' + m + ' hit box@(' + hit.cx.toFixed(1) + ',' + hit.cz.toFixed(1) + ')');
}
clearPoint('出生点', zones.playerSpawn.x, zones.playerSpawn.z, 0.6);
clearPoint('情报交互点', zones.intelPos.x, zones.intelPos.z, 0.35);
for (let k = 0; k < 8; k++) {
    const a = k / 8 * Math.PI * 2;
    clearPoint('撤离圈', zones.extractPos.x + Math.cos(a) * 2.7, zones.extractPos.z + Math.sin(a) * 2.7, 0.15);
}
zones.patrol.forEach((rt, ri) => rt.forEach((p, pi) => clearPoint('巡逻' + ri + '-' + pi, p.x, p.z, 0.5)));
zones.rangeLanes.forEach((ln, li) => {
    clearPoint('射位' + li, ln.origin.x, ln.origin.z, 0.55);
    for (let d = 4; d <= 26; d += 2) clearPoint('靶道' + li + 'd' + d, ln.origin.x + ln.dir.x * d, ln.origin.z + ln.dir.z * d, 0.2);
});
check('关键点全部净空（出生/情报/撤离圈/巡逻点/靶道）', clear.length === 0, clear.slice(0, 8).join(' | '));

/* ---- 6. 射线场景断言 ---- */
const fire = zones.rangeLanes.map((ln, i) => {
    const d = cw.rayWall({ x: ln.origin.x, y: ENV.terrainHeight(ln.origin.x, ln.origin.z) + 1.5, z: ln.origin.z },
        { x: 1, y: 0, z: 0 }, 60);
    return { i, d };
});
check('三条靶道射界畅通（首障碍 ≥ 28.5m，25m 靶前无遮挡）',
    fire.every((f) => f.d >= 28.5), fire.map((f) => 'lane' + f.i + '=' + f.d.toFixed(1)).join(' '));

const south = cw.rayWall({ x: 30, y: 1.6, z: 0 }, { x: 0, y: 0, z: 1 }, 120);
check('南边界墙挡弹（≈59.6m，取无遮挡起点）', south > 55 && south < 61, 'd=' + south.toFixed(2));
const up = cw.rayWall({ x: 0, y: 1.6, z: 0 }, { x: 0, y: 1, z: 0 }, 120);
check('朝天射线无遮挡', up === Infinity, 'd=' + up);

const po = cw.pushOut(zones.playerSpawn.x, zones.playerSpawn.z, 0.5);
check('出生点 pushOut 不卡墙', Math.hypot(po.x - zones.playerSpawn.x, po.z - zones.playerSpawn.z) < 0.05,
    'Δ=' + Math.hypot(po.x - zones.playerSpawn.x, po.z - zones.playerSpawn.z).toFixed(3));

/* ---- 7. zones 结构与距离关系 ---- */
check('巡逻线 3 条、每条 ≥ 3 点', zones.patrol.length === 3 && zones.patrol.every((r) => r.length >= 3),
    zones.patrol.map((r) => r.length).join('+'));
check('靶道 3 条朝 +X', zones.rangeLanes.length === 3 && zones.rangeLanes.every((l) => l.dir.x === 1 && l.dir.y === 0), '');
const spawnToZone = Math.hypot(zones.playerSpawn.x - 8, zones.playerSpawn.z - -8);
check('出生点距交战区中心 ≈60m（55~70）', spawnToZone > 55 && spawnToZone < 70, 'd=' + spawnToZone.toFixed(1));
check('zones 的 y 均贴地形', Math.abs(zones.playerSpawn.y - ENV.terrainHeight(zones.playerSpawn.x, zones.playerSpawn.z)) < 1e-9
    && Math.abs(zones.extractPos.y - ENV.terrainHeight(44, 8)) < 1e-9, '');
check('update() 连跑两帧无异常（烟/信标/呼吸灯）', true, '');

/* ---- 8. Environment 构造 + update 全流程（桩 THREE/document 下真执行抓引用错） ---- */
try {
    const envInst = new ENV.Environment(sceneStub, {});
    envInst.update(0.016, { x: 3, y: 1, z: -4 });
    envInst.dispose();
    check('Environment 构造/update/dispose 无异常', true, '');
} catch (e) {
    check('Environment 构造/update/dispose 无异常', false, String(e));
}

/* ---- 9. 兜底盒：14 种道具名全部走 makeFallback 真构造 ---- */
try {
    const LAYFB = loadModule('js/fps/layout.js',
        'const boundaryBoxes = ENV.boundaryBoxes, terrainHeight = ENV.terrainHeight;' +
        'var GLTFLoader = function(){ this.loadAsync = () => Promise.reject(new Error("no-net")); };',
        '({ makeFallback })');
    const names = ['barn', 'barrel', 'barrier', 'bunker', 'container', 'crate', 'dead_tree',
        'fuel_tank', 'house', 'rocks', 'sandbags', 'tent', 'warehouse', 'wreck'];
    let n = 0;
    for (const nm of names) { const g = LAYFB.makeFallback(nm); if (g) n++; }
    check('makeFallback 14 种全构造成功', n === 14, n + '/14');
    const bad = LAYFB.makeFallback('not_a_prop');
    check('makeFallback 未知名不抛异常', !!bad, '');
} catch (e) {
    check('makeFallback 14 种全构造成功', false, String(e));
}

console.log('\nRESULT: ' + (fail === 0 ? 'PASS' : 'FAIL') + '  ' + pass + ' passed, ' + fail + ' failed');
