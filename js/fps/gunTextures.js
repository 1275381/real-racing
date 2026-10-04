import * as THREE from 'three';
import { normalFromCanvas } from './normalmap.js';

/* =====================================================================
   js/fps/gunTextures.js —— 枪械程序化材质（【枪械】组，零外部资源）
   gunMaterials(tint?)：tint = { receiver, polymer, mag, wood }（hex 串或 null）
   → 返回该配色的材质包（receiver/barrel/polymer/mag/bolt/brass/wood 七材质）。
   ① 空参 = 默认配色（与旧版逐像素一致，弹壳池等旧调用点不受影响）；
   ② 每个 tint 一套缓存：着色差异通过「重生成 albedo 底色」实现
     （深色底贴图乘 color 只会更暗，银灰/墨绿必须换底色画布）；
   ③ 粗糙度/法线/黄铜贴图与配色无关，全局只生成一次共享。
   ===================================================================== */

/* ==== 1. Canvas 工具（照 js/textures.js 先例） ==== */

function canvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return [c, c.getContext('2d')];
}

function toTex(c, srgb = true) {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(1, 1);
    t.anisotropy = 4;
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    return t;
}

/* 细颗粒噪点：lo..hi 灰度随机小方块 */
function grain(g, S, count, lo, hi, alpha, size) {
    for (let i = 0; i < count; i++) {
        const v = lo + Math.random() * (hi - lo);
        g.fillStyle = `rgba(${v | 0},${v | 0},${(v + 2) | 0},${alpha})`;
        g.fillRect(Math.random() * S, Math.random() * S, size, size);
    }
}

/* 细长划痕：随机角度的浅色/深色线（金属磨损） */
function scratches(g, S, count, style, width, alpha) {
    g.strokeStyle = style;
    g.globalAlpha = alpha;
    g.lineCap = 'round';
    for (let i = 0; i < count; i++) {
        const x = Math.random() * S, y = Math.random() * S;
        const a = Math.random() * Math.PI * 2;
        const len = 18 + Math.random() * 110;
        g.lineWidth = width * (0.5 + Math.random());
        g.beginPath();
        g.moveTo(x, y);
        g.lineTo(x + Math.cos(a) * len, y + Math.sin(a) * len);
        g.stroke();
    }
    g.globalAlpha = 1;
}

/* ==== 2. 各部件贴图（写实度评审 #4：关键贴图 512 + 亮度法线） ==== */

/* 机匣金属：base 底色 + 磨砂颗粒 + 使用划痕（512） */
function metalAlbedo(base = '#33363b') {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = base;
    g.fillRect(0, 0, S, S);
    grain(g, S, 20000, 60, 105, 0.10, 1.6);
    scratches(g, S, 80, '#c2c8d0', 1.1, 0.10);
    scratches(g, S, 52, '#0c0e11', 0.9, 0.16);
    // 大块油污晕
    for (let i = 0; i < 10; i++) {
        const r = 52 + Math.random() * 108;
        const rg = g.createRadialGradient(Math.random() * S, Math.random() * S, 0, Math.random() * S, Math.random() * S, r);
        rg.addColorStop(0, 'rgba(12,13,15,0.10)');
        rg.addColorStop(1, 'rgba(12,13,15,0)');
        g.fillStyle = rg;
        g.fillRect(0, 0, S, S);
    }
    return c;
}

/* 金属磨砂粗糙度：中高粗糙底 + 划痕处磨亮（512） */
function metalRough() {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#a6a6a6';       // ≈0.65 粗糙
    g.fillRect(0, 0, S, S);
    grain(g, S, 22000, 130, 200, 0.5, 1.8);
    scratches(g, S, 72, '#5f5f5f', 1.0, 0.35);   // 磨亮划痕
    scratches(g, S, 36, '#d8d8d8', 0.8, 0.25);   // 更毛糙的深痕
    return c;
}

/* 聚合物（护木/枪托/握把）：base 底色 + 防滑点纹 + 纤维微粒（512） */
function polymerAlbedo(base = '#232528') {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = base;
    g.fillRect(0, 0, S, S);
    // 防滑纹：错排点阵
    for (let y = 0; y < S; y += 7) {
        for (let x = 0; x < S; x += 7) {
            const jx = x + ((y / 7) % 2) * 3.5 + (Math.random() - 0.5) * 2;
            const jy = y + (Math.random() - 0.5) * 2;
            g.fillStyle = `rgba(10,11,13,${0.28 + Math.random() * 0.3})`;
            g.beginPath();
            g.arc(jx, jy, 1.1 + Math.random() * 0.7, 0, 7);
            g.fill();
        }
    }
    grain(g, S, 10000, 70, 110, 0.08, 1.3);   // 纤维微粒微光
    scratches(g, S, 30, '#3d4046', 1.0, 0.12);
    return c;
}

function polymerRough() {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#c8c8c8';       // ≈0.78 粗糙，低反光
    g.fillRect(0, 0, S, S);
    grain(g, S, 20000, 160, 215, 0.5, 1.8);
    scratches(g, S, 36, '#9a9a9a', 1.0, 0.2);
    return c;
}

/* 枪管钢：深钢灰 + 车削纹理（横向细线）（512） */
function steelAlbedo() {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#2b2e33';
    g.fillRect(0, 0, S, S);
    for (let y = 0; y < S; y += 2 + Math.random() * 2) {
        g.fillStyle = `rgba(${150 + Math.random() * 30 | 0},${155 + Math.random() * 30 | 0},${168 + Math.random() * 30 | 0},${0.05 + Math.random() * 0.06})`;
        g.fillRect(0, y, S, 1);
    }
    grain(g, S, 12000, 55, 95, 0.12, 1.4);
    scratches(g, S, 44, '#b8bec8', 0.9, 0.12);
    return c;
}

/* 木托（霰弹枪）：base 木色 + 纵向木纹条 + 导管点（512） */
function woodAlbedo(base = '#5a3d24') {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = base;
    g.fillRect(0, 0, S, S);
    for (let y = 0; y < S; y += 3) {           // 纵向木纹：明暗交替长条
        const l = Math.random();
        g.fillStyle = l > 0.5
            ? `rgba(122,86,52,${0.10 + Math.random() * 0.16})`
            : `rgba(40,24,12,${0.10 + Math.random() * 0.18})`;
        g.fillRect(0, y, S, 1 + Math.random() * 2);
    }
    for (let i = 0; i < 26; i++) {             // 导管弧纹
        g.strokeStyle = `rgba(34,20,10,${0.10 + Math.random() * 0.14})`;
        g.lineWidth = 0.8 + Math.random();
        const x0 = Math.random() * S, y0 = Math.random() * S;
        g.beginPath();
        g.moveTo(x0, y0);
        g.bezierCurveTo(x0 + 40, y0 + 14, x0 + 110, y0 - 12, x0 + 190, y0 + 6);
        g.stroke();
    }
    grain(g, S, 9000, 70, 115, 0.07, 1.3);
    return c;
}

/* 黄铜弹壳：铜黄底 + 纵向拉丝（128，配色无关，只生成一次） */
function brassAlbedo() {
    const S = 128;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#b08c3e';
    g.fillRect(0, 0, S, S);
    for (let x = 0; x < S; x += 2) {
        const l = Math.random();
        g.fillStyle = l > 0.5
            ? `rgba(236,196,110,${0.08 + Math.random() * 0.08})`
            : `rgba(96,72,28,${0.08 + Math.random() * 0.08})`;
        g.fillRect(x, 0, 1, S);
    }
    grain(g, S, 900, 150, 200, 0.1, 1);
    return c;
}

/* ==== 3. 材质包：gunMaterials(tint?) —— 每个 tint 一套（缓存），空参=默认 ==== */

let _common = null;              // 配色无关贴图（粗糙度/法线/黄铜），全局一次
const _tintCache = new Map();    // tintKey → 材质包

/* 通用贴图惰性生成：金属/聚合物粗糙度、默认 albedo 派生法线、黄铜 */
function common() {
    if (_common) return _common;
    const mRough_c = metalRough();
    const pRough_c = polymerRough();
    const mR = toTex(mRough_c, false);          // 粗糙度贴图保持线性
    const pR = toTex(pRough_c, false);
    /* 法线贴图：以默认 albedo 亮度为高度场求差分（磨砂颗粒/车削纹/防滑点起
     * 浮雕；配色换底不换纹理，法线全局共享） */
    const mN = toTex(normalFromCanvas(metalAlbedo(), 1.7), false);
    const pN = toTex(normalFromCanvas(polymerAlbedo(), 1.3), false);
    const sN = toTex(normalFromCanvas(steelAlbedo(), 2.2), false);
    const bA = toTex(brassAlbedo(), true);
    _common = { mR, pR, mN, pN, sN, bA };
    return _common;
}

/* tint → 缓存键（null/undefined/非对象都归默认） */
function tintKey(tint) {
    if (!tint || typeof tint !== 'object') return '';
    return JSON.stringify(tint);
}

export function gunMaterials(tint = null) {
    const key = tintKey(tint);
    if (_tintCache.has(key)) return _tintCache.get(key);
    const t = (tint && typeof tint === 'object') ? tint : {};
    const C = common();

    /* 各 tint 重画的 albedo（底色差异）；未指定用默认底色 = 旧版外观 */
    const mA = toTex(metalAlbedo(t.receiver || '#33363b'), true);
    const pA = toTex(polymerAlbedo(t.polymer || '#232528'), true);
    const sA = toTex(steelAlbedo(), true);
    const wA = toTex(woodAlbedo(t.wood || '#5a3d24'), true);
    const ns = (x) => new THREE.Vector2(x, x);

    const pack = {
        // 机匣：anodized 铝合金，高金属度 + 磨砂
        receiverMat: new THREE.MeshStandardMaterial({
            map: mA, roughnessMap: C.mR, roughness: 1.0, metalness: 0.85,
            normalMap: C.mN, normalScale: ns(0.55),
        }),
        // 枪管/消焰器：深钢，更高金属度（所有枪统一深钢灰）
        barrelMat: new THREE.MeshStandardMaterial({
            map: sA, roughnessMap: C.mR, roughness: 1.0, metalness: 0.95,
            normalMap: C.sN, normalScale: ns(0.65),
        }),
        // 聚合物：护木/枪托/握把，低反光
        polymerMat: new THREE.MeshStandardMaterial({
            map: pA, roughnessMap: C.pR, roughness: 1.0, metalness: 0.05,
            normalMap: C.pN, normalScale: ns(0.5),
        }),
        // 弹匣：聚合物贴图 + tint.mag 染色（默认橄榄色 = 旧版）
        magMat: new THREE.MeshStandardMaterial({
            map: pA, roughnessMap: C.pR, roughness: 1.0, metalness: 0.05,
            color: new THREE.Color(t.mag || '#b8bfa6'),
            normalMap: C.pN, normalScale: ns(0.45),
        }),
        // 枪机/拉栓/小件：亮钢（纯色 + 粗糙度贴图）
        boltMat: new THREE.MeshStandardMaterial({
            color: 0x9aa1a9, roughnessMap: C.mR, roughness: 1.0, metalness: 1.0,
            normalMap: C.mN, normalScale: ns(0.4),
        }),
        // 黄铜弹壳（配色无关，全局同一份贴图）
        brassMat: new THREE.MeshStandardMaterial({
            map: C.bA, roughness: 0.32, metalness: 1.0
        }),
        // 木托（霰弹枪，tint.wood 底色）
        woodMat: new THREE.MeshStandardMaterial({
            map: wA, roughness: 0.55, metalness: 0.0,
        }),
    };
    _tintCache.set(key, pack);
    return pack;
}
