// 土星材质（契约：js/planets/*.js）
// map     : 1024×512 等距圆柱——柔和米黄纬向条纹、赤道亮带、大白斑、北极六边形暗晕，经度 0/360 无缝
// ringMap : 1024×64 径向条带——x=0→1.5R、x=1023→2.4R；C/B/A 环、卡西尼缝、恩克缝、基勒缝、F 环细线，
//           alpha 挖缝 + 多尺度环let 亮度起伏，y 向仅作条带不均匀性
// 全部 canvas 程序化，零外部资源；不设 wrap/anisotropy/mipmap（由 galaxy.js 统一设置）
import * as THREE from 'three';

/* ---------------- 通用工具 ---------------- */

function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }
function lerp(a, b, t) { return a + (b - a) * t; }
function smooth(t) { return t * t * (3 - 2 * t); }

/** 2D 值噪声：x 方向网格环绕（保证经度无缝），y 方向钳制 */
function makeNoise2D(gw, gh) {
    const g = new Float32Array(gw * gh);
    for (let i = 0; i < g.length; i++) g[i] = Math.random();
    return { g, gw, gh };
}
function noise2D(n, u, v) {
    const x = u * n.gw, y = clamp(v, 0, 0.9999) * n.gh;
    const x0 = Math.floor(x), y0 = Math.floor(y);
    const fx = smooth(x - x0), fy = smooth(y - y0);
    const xa = x0 % n.gw, xb = (x0 + 1) % n.gw;
    const yb = Math.min(y0 + 1, n.gh - 1);
    const a = n.g[y0 * n.gw + xa], b = n.g[y0 * n.gw + xb];
    const c = n.g[yb * n.gw + xa], d = n.g[yb * n.gw + xb];
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
}

/** 1D 值噪声（网格环绕） */
function makeNoise1D(cells) {
    const g = new Float32Array(cells);
    for (let i = 0; i < cells; i++) g[i] = Math.random();
    return { g, cells };
}
function noise1D(n, t) {
    const x = clamp(t, 0, 0.999999) * n.cells;
    const i = Math.floor(x), f = smooth(x - i);
    return lerp(n.g[i], n.g[(i + 1) % n.cells], f);
}

/** 经向波列：频率取整数周期 → u=0 与 u=1 处值相同，接缝天然连续 */
function makeWaves(count) {
    const ws = [];
    let sum = 0;
    for (let i = 0; i < count; i++) {
        const w = { f: 1 + Math.floor(Math.random() * 11), p: Math.random() * Math.PI * 2, a: 1 / (1 + i * 0.9) };
        ws.push(w); sum += w.a;
    }
    for (const w of ws) w.a /= sum;
    return ws;
}
function evalWaves(ws, u) {
    let s = 0;
    for (let i = 0; i < ws.length; i++) { const w = ws[i]; s += w.a * Math.sin(w.f * u * Math.PI * 2 + w.p); }
    return s;
}

/* ---------------- 主贴图：米黄条纹球体 ---------------- */

function buildMap() {
    const W = 1024, H = 512;
    const canvas = document.createElement('canvas');
    canvas.width = W; canvas.height = H;
    const ctx = canvas.getContext('2d');

    /* 纬度色带（上=北极→下=南极）：低对比奶油米黄；赤道亮带最宽最亮，两极偏暗橄榄 */
    const STOPS = [
        [0.000, 151, 142, 108],
        [0.045, 172, 162, 124],
        [0.100, 198, 185, 142],
        [0.165, 214, 200, 156],
        [0.225, 203, 188, 144],
        [0.285, 223, 209, 162],
        [0.345, 206, 191, 147],
        [0.410, 231, 217, 170],
        [0.465, 237, 224, 176],
        [0.500, 241, 229, 182],
        [0.545, 235, 222, 174],
        [0.605, 221, 206, 160],
        [0.670, 211, 197, 152],
        [0.740, 219, 205, 159],
        [0.810, 200, 186, 143],
        [0.880, 184, 171, 131],
        [0.945, 163, 151, 115],
        [1.000, 147, 137, 105],
    ];
    function stopColor(v) {
        for (let i = 1; i < STOPS.length; i++) {
            if (v <= STOPS[i][0]) {
                const a = STOPS[i - 1], b = STOPS[i];
                const t = (v - a[0]) / (b[0] - a[0]);
                return [lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)];
            }
        }
        const s = STOPS[STOPS.length - 1];
        return [s[1], s[2], s[3]];
    }

    /* 每行 LUT：色带 + 两档高频细纹（气巨星细密纬向丝缕） */
    const stripeA = makeNoise1D(160), stripeB = makeNoise1D(70);
    const lut = new Float32Array(H * 3);
    for (let y = 0; y < H; y++) {
        const c = stopColor(y / (H - 1));
        const s = (noise1D(stripeA, y / H) - 0.5) * 13 + (noise1D(stripeB, y / H) - 0.5) * 9;
        lut[y * 3] = c[0] + s;
        lut[y * 3 + 1] = c[1] + s * 0.95;
        lut[y * 3 + 2] = c[2] + s * 0.8;
    }

    /* 条纹波动（整数频率波列）+ 两档大尺度斑驳 */
    const wavesA = makeWaves(6), wavesB = makeWaves(4);
    const mot1 = makeNoise2D(48, 24), mot2 = makeNoise2D(128, 56);

    const img = ctx.createImageData(W, H);
    const d = img.data;
    for (let y = 0; y < H; y++) {
        const v = y / (H - 1);
        // 波动幅度：赤道带最强（~8px），两极收平
        const amp = 2.2 + 6.5 * Math.pow(Math.sin(Math.PI * clamp((v - 0.04) / 0.92, 0.01, 0.99)), 0.8);
        for (let x = 0; x < W; x++) {
            const u = x / W;
            const wob = (evalWaves(wavesA, u) * 0.75 + evalWaves(wavesB, u) * 0.45) * amp;
            const yy = clamp(y + wob, 0, H - 1);
            const y0 = Math.floor(yy), y1 = Math.min(y0 + 1, H - 1);
            const f = smooth(yy - y0);
            let r = lerp(lut[y0 * 3], lut[y1 * 3], f);
            let g = lerp(lut[y0 * 3 + 1], lut[y1 * 3 + 1], f);
            let b = lerp(lut[y0 * 3 + 2], lut[y1 * 3 + 2], f);
            const m = (noise2D(mot1, u, v) - 0.5) * 15 + (noise2D(mot2, u, v) - 0.5) * 9;
            const gr = (Math.random() - 0.5) * 7;
            r += m + gr; g += m * 0.95 + gr; b += m * 0.75 + gr * 0.9;
            const i = (y * W + x) * 4;
            d[i] = clamp(r, 0, 255); d[i + 1] = clamp(g, 0, 255); d[i + 2] = clamp(b, 0, 255); d[i + 3] = 255;
        }
    }
    ctx.putImageData(img, 0, 0);

    /* 柔和椭圆斑（越界时 ±W 环绕补画，保证接缝连续） */
    function softOval(cx, cy, rx, ry, cr, cg, cb, a) {
        for (const dx of [-W, 0, W]) {
            ctx.save();
            ctx.translate(cx + dx, cy);
            ctx.scale(rx, ry);
            const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
            g.addColorStop(0, `rgba(${cr},${cg},${cb},${a})`);
            g.addColorStop(0.55, `rgba(${cr},${cg},${cb},${(a * 0.5).toFixed(3)})`);
            g.addColorStop(1, `rgba(${cr},${cg},${cb},0)`);
            ctx.fillStyle = g;
            ctx.beginPath(); ctx.arc(0, 0, 1, 0, Math.PI * 2); ctx.fill();
            ctx.restore();
        }
    }

    /* 大白斑（2010 年级大风暴）：北半球中纬亮核 + 西向拖尾 */
    const gx = 250 + Math.random() * 500, gy = 158;
    softOval(gx, gy, 120, 17, 251, 247, 234, 0.62);
    softOval(gx + 28, gy, 66, 10, 253, 250, 241, 0.8);
    softOval(gx - 60, gy + 3, 44, 8, 248, 244, 230, 0.4);
    for (let k = 1; k <= 4; k++)
        softOval(gx - 100 - k * 46, gy + k * 2.5, 36 - k * 5, 6.5 - k * 0.9, 250, 246, 232, Math.max(0.06, 0.34 - k * 0.06));

    /* 常年小白云斑 + 少量暗斑（高纬按等距圆柱压扁） */
    for (let i = 0; i < 9; i++) {
        const y = 60 + Math.random() * 400;
        const lat = Math.abs(y / H - 0.5);
        softOval(Math.random() * W, y, 14 + Math.random() * 36, 3 + Math.random() * 6 * (1 - lat * 0.7),
            250, 246, 230, 0.22 + Math.random() * 0.25);
    }
    for (let i = 0; i < 5; i++) {
        const y = 100 + Math.random() * 320;
        softOval(Math.random() * W, y, 12 + Math.random() * 26, 3 + Math.random() * 4,
            128, 112, 82, 0.16 + Math.random() * 0.14);
    }

    /* 北极六边形暗晕（78°N，六个顶点各一暗斑）+ 橄榄极冠 + 极眼 */
    for (let k = 0; k < 6; k++)
        softOval((k + 0.5) * W / 6, 30, 44, 8, 116, 112, 92, 0.13);
    let lg = ctx.createLinearGradient(0, 0, 0, 64);
    lg.addColorStop(0, 'rgba(108,108,88,0.42)');
    lg.addColorStop(1, 'rgba(108,108,88,0)');
    ctx.fillStyle = lg; ctx.fillRect(0, 0, W, 64);
    lg = ctx.createLinearGradient(0, H - 52, 0, H);
    lg.addColorStop(0, 'rgba(112,102,78,0)');
    lg.addColorStop(1, 'rgba(112,102,78,0.38)');
    ctx.fillStyle = lg; ctx.fillRect(0, H - 52, W, 52);
    lg = ctx.createLinearGradient(0, 0, 0, 12);
    lg.addColorStop(0, 'rgba(84,86,70,0.55)');
    lg.addColorStop(1, 'rgba(84,86,70,0)');
    ctx.fillStyle = lg; ctx.fillRect(0, 0, W, 12);

    /* 顺纬向细流线（亮/暗各半，环绕补画） */
    for (let i = 0; i < 130; i++) {
        const y = Math.random() * H;
        const len = 26 + Math.random() * 170;
        const x0 = Math.random() * W;
        const al = (0.03 + Math.random() * 0.05).toFixed(3);
        ctx.fillStyle = Math.random() < 0.55 ? `rgba(255,249,228,${al})` : `rgba(112,95,66,${al})`;
        for (const dx of [-W, 0, W]) ctx.fillRect(x0 + dx, y, len, 1);
    }

    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
}

/* ---------------- 光环：径向条带（含卡西尼缝） ---------------- */

function buildRingMap() {
    const W = 1024, H = 64;
    const canvas = document.createElement('canvas');
    canvas.width = W; canvas.height = H;
    const ctx = canvas.getContext('2d');

    /* 半径→像素：x=0 → 1.5R（环内缘），x=1023 → 2.4R（环外缘）
       真实环系（行星半径倍）：C 1.24-1.53 / B 1.53-1.95 / 卡西尼缝 1.95-2.03 /
       A 2.03-2.27（恩克缝 2.214、基勒缝 2.263）/ F 环 2.32 */
    const X = r => (r - 1.5) / 0.9 * (W - 1);
    const B_IN = X(1.53), CAS_IN = X(1.95), CAS_OUT = X(2.03), A_OUT = X(2.27);
    const ENCKE = X(2.214), KEELER = X(2.263), FRING = X(2.325);

    /* 多尺度环 let 噪声（粗起伏 → 极细丝缕） */
    const nA = makeNoise1D(40), nB = makeNoise1D(130), nC = makeNoise1D(380), nD = makeNoise1D(1024);

    const aProf = new Float32Array(W), bProf = new Float32Array(W);
    const cR = new Float32Array(W), cG = new Float32Array(W), cB = new Float32Array(W);

    for (let x = 0; x < W; x++) {
        let a, br, cr, cg, cb;
        if (x < B_IN) {                        // C 环：稀薄、偏灰蓝
            const t = x / B_IN;
            a = 0.10 + 0.24 * t; br = 0.60 + 0.14 * t;
            cr = 176; cg = 170; cb = 152;
        } else if (x < CAS_IN) {               // B 环：最亮最实
            const t = (x - B_IN) / (CAS_IN - B_IN);
            a = 0.86 + 0.11 * Math.sin(t * Math.PI);
            br = 1.0 + 0.10 * Math.sin(t * Math.PI * 1.7 + 0.8);
            cr = 229; cg = 217; cb = 190;
        } else if (x < CAS_OUT) {              // 卡西尼缝：近透明，缝内两条稀薄细环
            const t = (x - CAS_IN) / (CAS_OUT - CAS_IN);
            a = 0.05 + 0.03 * Math.sin(t * Math.PI);
            for (const gapC of [0.30, 0.62]) {
                const dd = Math.abs(t - gapC) / 0.035;
                if (dd < 1) a += 0.13 * Math.pow(1 - dd * dd, 2);
            }
            br = 0.55; cr = 168; cg = 160; cb = 142;
        } else if (x < A_OUT) {                // A 环：中等亮度，向外渐暗
            const t = (x - CAS_OUT) / (A_OUT - CAS_OUT);
            a = 0.78 - 0.20 * t; br = 0.85 - 0.12 * t;
            cr = 216; cg = 204; cb = 178;
        } else {                               // A 环外稀薄散逸区
            const t = (x - A_OUT) / (W - 1 - A_OUT);
            a = 0.09 * Math.pow(1 - t, 1.6); br = 0.60;
            cr = 192; cg = 182; cb = 158;
        }
        // 恩克缝：宽缝、缓变边缘
        let dd = Math.abs(x - ENCKE);
        if (dd < 16) a *= lerp(0.05, 1, smooth(clamp((dd - 2.5) / 13.5, 0, 1)));
        // 基勒缝：极窄
        dd = Math.abs(x - KEELER);
        if (dd < 5) a *= lerp(0.12, 1, smooth(clamp((dd - 1.0) / 4.0, 0, 1)));
        // F 环：孤立细亮线
        dd = Math.abs(x - FRING);
        if (dd < 12) a += 0.40 * Math.exp(-(dd * dd) / 9);
        // 内外缘淡出
        if (x < 8) a *= smooth(x / 8);
        if (x > W - 10) a *= smooth((W - 1 - x) / 9);

        // 多尺度环 let 明暗起伏（同调 RGB 与 alpha）
        const u = x / W;
        const rl = (noise1D(nA, u) + noise1D(nB, u) * 0.8 + noise1D(nC, u) * 0.5 + noise1D(nD, u) * 0.25) / 2.55;
        aProf[x] = clamp(a * (0.55 + 0.62 * rl), 0, 0.985);
        bProf[x] = br * (0.78 + 0.44 * rl);
        cR[x] = cr; cG[x] = cg; cB[x] = cb;
    }

    /* y 向不均匀性：条带轻微错位（行偏移）+ 行亮度微差 */
    const rowOff = new Float32Array(H), rowMul = new Float32Array(H);
    const p1 = Math.random() * 6.28, p2 = Math.random() * 6.28;
    const rMul = makeNoise1D(H);
    for (let y = 0; y < H; y++) {
        rowOff[y] = Math.sin(y * 0.35 + p1) * 1.6 + Math.sin(y * 0.11 + p2) * 1.1;
        rowMul[y] = 0.92 + 0.15 * rMul.g[y];
    }

    const img = ctx.createImageData(W, H);
    const d = img.data;
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const xi = clamp(Math.round(x + rowOff[y]), 0, W - 1);
            const i = (y * W + x) * 4;
            const bb = bProf[xi] * rowMul[y];
            d[i] = clamp(cR[xi] * bb, 0, 255);
            d[i + 1] = clamp(cG[xi] * bb, 0, 255);
            d[i + 2] = clamp(cB[xi] * bb, 0, 255);
            d[i + 3] = clamp(aProf[xi] * rowMul[y] * 255, 0, 255);
        }
    }
    ctx.putImageData(img, 0, 0);

    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
}

/* ---------------- 导出（幂等：每次全新纹理） ---------------- */

export function build() {
    return { map: buildMap(), ringMap: buildRingMap() };
}
