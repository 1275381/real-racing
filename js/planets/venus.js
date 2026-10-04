import * as THREE from 'three';

// ---------------------------------------------------------------------------
// 金星材质：浓硫酸云层的黄白色漩涡条纹 + 被云半掩的黄褐色火山地表
// 全部 canvas 程序化；噪声用「周期格点表 + 双线性插值」，x 方向按整数
// 周期 wrap、所有条纹/极涡相位在经度 0/360 处相等 → 贴图左右无缝。
// ---------------------------------------------------------------------------

const W = 1024, H = 512, TAU = Math.PI * 2;

// ---- 周期格点噪声：预生成每个 octave 的随机格点表，采样只做查表 + 插值 ----
function hash2(ix, iy, seed) {
    let h = Math.imul(ix, 374761393) + Math.imul(iy, 668265263) + Math.imul(seed, 1442695041);
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}
// gx = x 向格点周期（整数，保证 u=0/1 采样一致），gy = y 向格点数
function makeFbm(gx, gy, oct, seed) {
    const tabs = [];
    for (let i = 0; i < oct; i++) {
        const fx = gx << i, fy = gy << i;
        const t = new Float32Array(fx * (fy + 1));
        for (let k = 0; k < t.length; k++) t[k] = hash2(k % fx, (k / fx) | 0, seed + i * 101);
        tabs.push(t);
    }
    return {
        // u,v ∈ [0,1)；返回 0..1 的 fBm 值。u 方向周期 wrap → 无缝。
        sample(u, v) {
            let s = 0, amp = 0.5, tot = 0;
            for (let i = 0; i < oct; i++) {
                const fx = gx << i, fy = gy << i;
                const x = u * fx, y = v * fy;
                const ix = x | 0, iy = y | 0;
                const fxr = x - ix, fyr = y - iy;
                const sx = fxr * fxr * (3 - 2 * fxr), sy = fyr * fyr * (3 - 2 * fyr);
                const x0 = ix % fx, x1 = (x0 + 1) % fx;      // x 周期 wrap
                const g = tabs[i], row = iy * fx;
                const a = g[row + x0], b = g[row + x1];
                const c = g[row + fx + x0], d = g[row + fx + x1];
                s += amp * (a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy);
                tot += amp;
                amp *= 0.5;
            }
            return s / tot;
        },
    };
}

// ---- 工具 ----
function wrapDx(a, b) { let d = a - b; d -= Math.round(d); return d; }        // 经度方向最短差
function blob(u, v, cu, cv, ru, rv) {                                        // 柔和椭圆高斯掩码
    const dx = wrapDx(u, cu) / ru, dy = (v - cv) / rv;
    return Math.exp(-(dx * dx + dy * dy) * 2.6);
}
function lerpC(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}
function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }

// 随机盾火山/低地斑列表（map 与 bump 共用同一份位置，保证高程与颜色一致）
function makeSpots() {
    const spots = [];
    for (let i = 0; i < 14; i++) spots.push({ u: Math.random(), v: 0.12 + Math.random() * 0.76, r: 0.012 + Math.random() * 0.026, k: 1 });    // 亮盾火山
    for (let i = 0; i < 7; i++) spots.push({ u: Math.random(), v: 0.15 + Math.random() * 0.7, r: 0.03 + Math.random() * 0.05, k: -0.55 });     // 暗低地平原
    return spots;
}

// wrap 补画的径向渐变斑：越出左右边界时在 x±W 各补画一遍
function paintSpot(ctx, x, y, r, inner, outer) {
    const offs = [0];
    if (x - r < 0) offs.push(W);
    if (x + r > W) offs.push(-W);
    for (const o of offs) {
        const g = ctx.createRadialGradient(x + o, y, 0, x + o, y, r);
        g.addColorStop(0, inner);
        g.addColorStop(1, outer);
        ctx.fillStyle = g;
        ctx.fillRect(x + o - r, y - r, r * 2, r * 2);
    }
}

export function build() {
    // ============ 1. 地表高程场（map 着色与 bumpMap 共用） ============
    const mapCanvas = document.createElement('canvas');
    mapCanvas.width = W; mapCanvas.height = H;
    const mctx = mapCanvas.getContext('2d');
    const mImg = mctx.createImageData(W, H), mD = mImg.data;

    const bumpCanvas = document.createElement('canvas');
    bumpCanvas.width = W; bumpCanvas.height = H;
    const bctx = bumpCanvas.getContext('2d');
    const bImg = bctx.createImageData(W, H), bD = bImg.data;

    const spots = makeSpots();
    const terrain = makeFbm(6, 3, 5, 11);      // 大尺度起伏
    const detail = makeFbm(24, 12, 2, 77);     // 细颗粒
    const cDark = [141, 107, 72], cMid = [199, 168, 124], cLight = [240, 221, 184];

    for (let y = 0; y < H; y++) {
        const v = y / H;
        // 行级剪枝：blob 高斯 d2<9 要求 |dy| < 3r·√2.2 ≈ 4.45r，行内仅保留有效 spot
        const active = [];
        for (const s of spots) if (Math.abs(v - s.v) < s.r * 4.5) active.push(s);
        for (let x = 0; x < W; x++) {
            const u = x / W;
            // 基础起伏 + 大尺度地形（Ishtar Terra 北极高地、Aphrodite Terra 赤道长条高地）
            let elev = terrain.sample(u, v) * 0.52
                + blob(u, v, 0.20, 0.10, 0.11, 0.075) * 0.30
                + blob(u, v, 0.44, 0.56, 0.20, 0.058) * 0.26
                + blob(u, v, 0.78, 0.36, 0.07, 0.05) * 0.10
                + blob(u, v, 0.62, 0.78, 0.09, 0.06) * 0.10;
            // 火山/低地斑
            for (const s of active) {
                const dx = wrapDx(u, s.u), dy = v - s.v;
                const d2 = (dx * dx) / (s.r * s.r) + (dy * dy) / (s.r * s.r * 2.2);
                if (d2 < 9) elev += s.k * Math.exp(-d2 * 1.4) * 0.30;
            }
            elev = clamp01(elev);

            // 地表颜色：低地暗黄褐 → 高地亮沙金，叠细噪声增加层次
            let tone = clamp01(elev + (detail.sample(u, v) - 0.5) * 0.14);
            let col;
            if (tone < 0.5) col = lerpC(cDark, cMid, tone * 2);
            else col = lerpC(cMid, cLight, (tone - 0.5) * 2);

            const i = (y * W + x) * 4;
            mD[i] = col[0]; mD[i + 1] = col[1]; mD[i + 2] = col[2]; mD[i + 3] = 255;
            const g = (elev * 255) | 0;
            bD[i] = g; bD[i + 1] = g; bD[i + 2] = g; bD[i + 3] = 255;
        }
    }
    mctx.putImageData(mImg, 0, 0);
    bctx.putImageData(bImg, 0, 0);

    // 在 map 上补一层柔和的火山晕斑（与 spots 同源、wrap 补画），增强辨识度
    for (const s of spots) {
        const px = s.u * W, py = s.v * H, r = s.r * W * 1.9;
        if (s.k > 0) paintSpot(mctx, px, py, r, 'rgba(246,228,192,0.28)', 'rgba(246,228,192,0)');
        else paintSpot(mctx, px, py, r, 'rgba(96,70,44,0.22)', 'rgba(96,70,44,0)');
    }

    // ============ 2. 硫酸云层：黄白 V 形条纹 + 极涡螺旋（RGBA） ============
    const cloudCanvas = document.createElement('canvas');
    cloudCanvas.width = W; cloudCanvas.height = H;
    const cctx = cloudCanvas.getContext('2d');
    const cImg = cctx.createImageData(W, H), cD = cImg.data;

    const clDark = [201, 177, 137], clLight = [250, 242, 216];
    const warpN = makeFbm(3, 2, 4, 31);        // 大尺度扭曲（x 周期）
    const thick = makeFbm(8, 4, 3, 57);        // 中尺度厚薄
    const NPu = 0.30;                          // 北极涡中心经度（极点 y=0）
    const SPu = 0.72;                          // 南极涡中心经度

    for (let y = 0; y < H; y++) {
        const v = y / H;
        const chev = 1.55 * Math.abs(v - 0.5);                     // V 形（chevron）相位
        // 纬度权重与极区亮晕均为 v-only，行级预计算；极涡只在意权重 >1.2% 的行
        const wN = Math.exp(-(v / 0.15) * (v / 0.15));
        const wS = Math.exp(-((1 - v) / 0.15) * ((1 - v) / 0.15));
        const nv = v * 0.5, sv = (1 - v) * 0.5;
        const doN = wN > 0.012, doS = wS > 0.012;
        const qn = v / 0.08, qs = (1 - v) / 0.08;
        const poleGlow = Math.exp(-qn * qn) * 0.08 + Math.exp(-qs * qs) * 0.08;
        const yChev7 = chev * 0.7;
        for (let x = 0; x < W; x++) {
            const u = x / W;
            const w1 = warpN.sample(u, v);
            const w2 = thick.sample(u, v);

            // 主条带：整数倍经向频率 + 周期扭曲 → u=0/1 处相位相等，无缝
            let t = 0.5
                + 0.30 * Math.sin(TAU * (u * 5 + chev) + (w1 - 0.5) * 4.2)
                + 0.16 * Math.sin(TAU * (u * 9 - yChev7) + (w1 - 0.5) * 6.5)
                + 0.10 * Math.sin(TAU * (u * 2 + 0.35) + (w2 - 0.5) * 3.0);

            // 极涡：同心弧 + 整数角频率的螺旋（k·θ 在 θ=±π 处连续，无缝）
            if (doN) {
                const ndx = wrapDx(u, NPu);
                const polarN = Math.sin(TAU * Math.hypot(ndx, nv) * 16 + 2 * Math.atan2(ndx, nv + 1e-6) + (w1 - 0.5) * 3.0);
                t = t * (1 - wN) + (0.5 + 0.30 * polarN) * wN;
            }
            if (doS) {
                const sdx = wrapDx(u, SPu);
                const polarS = Math.sin(TAU * Math.hypot(sdx, sv) * 16 - 2 * Math.atan2(sdx, sv + 1e-6) + (w1 - 0.5) * 3.0);
                t = t * (1 - wS) + (0.5 + 0.30 * polarS) * wS;
            }
            t = clamp01(t + poleGlow);

            const col = lerpC(clDark, clLight, t);
            // 云不透明度：几乎全覆盖（0.80~1），暗带略透出地表
            let a = 0.87 + 0.13 * w2 - (1 - t) * 0.07;
            a = clamp01(a);

            const i = (y * W + x) * 4;
            cD[i] = col[0]; cD[i + 1] = col[1]; cD[i + 2] = col[2]; cD[i + 3] = (a * 255) | 0;
        }
    }
    cctx.putImageData(cImg, 0, 0);

    // ============ 3. 组装纹理（契约：map/cloudMap 设 SRGB，bump 保持线性） ============
    const map = new THREE.CanvasTexture(mapCanvas);
    map.colorSpace = THREE.SRGBColorSpace;

    const bumpMap = new THREE.CanvasTexture(bumpCanvas);

    const cloudMap = new THREE.CanvasTexture(cloudCanvas);
    cloudMap.colorSpace = THREE.SRGBColorSpace;

    return { map, bumpMap, cloudMap };
}
