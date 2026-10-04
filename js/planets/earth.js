import * as THREE from 'three';

/*
 * 地球材质模块（契约见 out/solar-design.md §1）
 *   map      1024×512  地表：海洋深浅渐变、程序化大陆、沙漠/植被/岩山/雪线、极地冰盖与浮冰
 *   bumpMap  1024×512  高程灰度图（不设 colorSpace，保持线性）
 *   cloudMap 1024×512  RGBA 云层：暖白 RGB + alpha 覆盖率（ITCZ 赤道云带 / 中纬风暴带 / 副热带少云带）
 *   moonMap  512×256   月面：暗色月海、亮缘陨石坑、中央峰与辐射纹
 *
 * 无缝策略：噪声晶格沿经度按整数周期取模（查表 + (x0+1)%w 环绕），像素按
 * u=(i+0.5)/W 采样；半分辨率粗场做周期化双线性上采样（x 向 (x0+1)%W2 环绕），
 * 故 x=W-1 与 x=0 之间自然连续；超边元素（月面陨石坑、辐射纹）按 x±W 三重补画。
 *
 * 性能：晶格查表替代逐点 hash；低频场（域扭曲/山脉/湿度/冰盖缘/洋流）在 512×256
 * 粗网格算一次，上采样的列索引/行索引与纬度气候量（植被基色、沙漠带、雪线、
 * 海岸色）全部预计算外提 → 单次 build 亚秒级。
 */

/* ========================= 随机 / 晶格查表噪声 ========================= */

function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
        a |= 0;
        a = (a + 0x6D2B79F5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function hash2(ix, iy, seed) {
    let h = Math.imul(ix, 0x27d4eb2d) ^ Math.imul(iy, 0x165667b1) ^ Math.imul(seed, 0x9e3779b1);
    h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
    h ^= h >>> 13;
    h = Math.imul(h, 0xc2b2ae35);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
}

/*
 * 预生成一张周期值噪声「场」：oct 层晶格，第 i 层宽 px·2^i（经度周期），
 * 行覆盖 [yMin,yMax]·2^i 并各外扩一行，采样只做数组读取 + 双线性插值。
 */
function makeField(px, oct, yMin, yMax, seed, isRidged) {
    const layers = [];
    let p = px, lo = yMin, hi = yMax;
    for (let i = 0; i < oct; i++) {
        const y0 = Math.floor(lo) - 1, y1 = Math.ceil(hi) + 1;
        const h = y1 - y0 + 1;
        const t = new Float32Array(p * h);
        for (let yy = 0; yy < h; yy++) {
            const row = yy * p, ly = yy + y0;
            for (let xx = 0; xx < p; xx++) t[row + xx] = hash2(xx, ly, seed + i * 101);
        }
        layers.push({ t: t, w: p, y0: y0, h: h });
        p *= 2; lo *= 2; hi *= 2;
    }
    let amp = 1, tot = 0;
    const amps = [];
    for (let i = 0; i < oct; i++) { amps.push(amp); tot += amp; amp *= 0.5; }
    return { layers: layers, amps: amps, inv: 1 / tot, px: px, ridged: !!isRidged };
}

/* 单层晶格采样：x 周期取模（无缝核心），y 行钳制防越界 */
function latt(L, x, y) {
    const xi = Math.floor(x), yi = Math.floor(y);
    const xf = x - xi, yf = y - yi;
    const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    let x0 = xi % L.w;
    if (x0 < 0) x0 += L.w;
    const x1 = x0 + 1 === L.w ? 0 : x0 + 1;
    let r0 = yi - L.y0;
    if (r0 < 0) r0 = 0;
    else if (r0 > L.h - 2) r0 = L.h - 2;
    const b0 = r0 * L.w, b1 = (r0 + 1) * L.w;
    const a = L.t[b0 + x0], b = L.t[b0 + x1], c = L.t[b1 + x0], d = L.t[b1 + x1];
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

/* 整场求值：分形叠加（或脊状，用于山脉） */
function nsAt(f, x, y) {
    let s = 0;
    for (let i = 0; i < f.layers.length; i++) {
        let v = latt(f.layers[i], x, y);
        if (f.ridged) v = 1 - Math.abs(2 * v - 1);
        s += f.amps[i] * v;
        x *= 2; y *= 2;
    }
    return s * f.inv;
}

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);

function smoothstep(a, b, x) {
    const t = clamp01((x - a) / (b - a));
    return t * t * (3 - 2 * t);
}

const mix = (a, b, t) => a + (b - a) * t;

/* 种子间归一化：把场拉回均值 0.5 / 目标标准差 → 海陆比例、云量不随随机种子漂移
 * （纯逐元素变换，不破坏经度周期性；scale 夹在 [0.7,1.5] 防极端放大） */
function normalizeField(arr, targetStd) {
    let sum = 0, sq = 0;
    const n = arr.length;
    for (let q = 0; q < n; q++) { const x = arr[q]; sum += x; sq += x * x; }
    const mean = sum / n;
    const sd = Math.sqrt(Math.max(1e-9, sq / n - mean * mean));
    const sc = Math.min(1.5, Math.max(0.7, targetStd / sd));
    for (let q = 0; q < n; q++) arr[q] = 0.5 + (arr[q] - mean) * sc;
}

function mkCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    return c;
}

/* ========================= 地表 + 高程（粗场 + 全分辨率着色） ========================= */

function drawSurface(S) {
    const W = 1024, H = 512, HW = 512, HH = 256;
    const SEA = 0.548;   // 海平面（值噪声均值 0.5，略高 → 约 1/3 陆地）

    /* —— 噪声场（各一次预生成） */
    const fW1 = makeField(4, 3, -1, 3, S[0]);          // 域扭曲 1
    const fW2 = makeField(4, 3, -1, 3, S[1]);          // 域扭曲 2
    const fE = makeField(5, 5, -2, 4.5, S[2]);         // 大陆高程
    const fDet = makeField(28, 2, -1, 15, S[4]);       // 细节/海岸碎部
    const fMount = makeField(8, 4, -1, 5, S[6], true); // 山脉（脊状）
    const fMoist = makeField(5, 3, 6, 11, S[7]);       // 湿度
    const fCap = makeField(6, 3, -1, 4, S[5]);         // 冰盖缘扰动
    const fSwirl = makeField(13, 3, -1, 8, S[8]);      // 洋流涡旋
    const fFloe = makeField(44, 2, -1, 23, S[9]);      // 浮冰碎斑

    /* —— 半分辨率粗场 */
    const eC = new Float32Array(HW * HH);
    const mountC = new Float32Array(HW * HH);
    const moistC = new Float32Array(HW * HH);
    const capC = new Float32Array(HW * HH);
    const swirlC = new Float32Array(HW * HH);
    for (let j = 0; j < HH; j++) {
        const v = (j + 0.5) / HH, lat = 90 - 180 * v, ab = Math.abs(lat);
        for (let i = 0; i < HW; i++) {
            const u = (i + 0.5) / HW, q = j * HW + i;
            const w1 = nsAt(fW1, u * 4, v * 2) - 0.5;
            const w2 = nsAt(fW2, u * 4, v * 2) - 0.5;
            eC[q] = nsAt(fE, u * 5 + w1 * 1.8, v * 2.5 + w2 * 1.8);
            mountC[q] = nsAt(fMount, u * 8, v * 4);
            moistC[q] = nsAt(fMoist, u * 5 + 3.3, v * 2.5 + 7.7);
            capC[q] = ab > 46 ? nsAt(fCap, u * 6, v * 3) : 0.5;
            swirlC[q] = nsAt(fSwirl, u * 13, v * 6.5);
        }
    }
    normalizeField(eC, 0.11);        // 锁定约 1/3 陆地
    normalizeField(moistC, 0.1);     // 锁定沙漠带出现率

    /* —— 上采样列索引（周期环绕）一次预计算，所有粗场共用 */
    const X0 = new Int32Array(W), X1 = new Int32Array(W), FX = new Float32Array(W);
    for (let i = 0; i < W; i++) {
        const gx = (i + 0.5) / W * HW - 0.5;
        let x0 = Math.floor(gx);
        FX[i] = gx - x0;
        if (x0 < 0) x0 += HW;
        X0[i] = x0;
        X1[i] = x0 + 1 === HW ? 0 : x0 + 1;
    }

    /* —— 全分辨率着色 + 高程 */
    const mapC = mkCanvas(W, H), ctx = mapC.getContext('2d');
    const img = ctx.createImageData(W, H), px = img.data;
    const bumpC = mkCanvas(W, H), bctx = bumpC.getContext('2d');
    const bimg = bctx.createImageData(W, H), bpx = bimg.data;

    for (let j = 0; j < H; j++) {
        const v = (j + 0.5) / H;
        const lat = 90 - 180 * v;                       // 北纬 +90 → 南纬 -90
        const ab = Math.abs(lat);
        let y0 = Math.floor(v * HH - 0.5);
        if (y0 < 0) y0 = 0;
        else if (y0 > HH - 2) y0 = HH - 2;
        const fy = v * HH - 0.5 - y0;
        const r0 = y0 * HW, r1 = r0 + HW;
        const sbl = (arr, i) => {
            const a0 = arr[r0 + X0[i]], a1 = arr[r0 + X1[i]];
            const b0 = arr[r1 + X0[i]], b1 = arr[r1 + X1[i]];
            const a = a0 + (a1 - a0) * FX[i], b = b0 + (b1 - b0) * FX[i];
            return a + (b - a) * fy;
        };

        /* 行级气候量（只随纬度变化） */
        const trop = smoothstep(18, 6, ab), bor = smoothstep(48, 62, ab);
        const vegR = mix(mix(74, 52, trop), 66, bor);
        const vegG = mix(mix(112, 106, trop), 96, bor);
        const vegB = mix(mix(58, 46, trop), 64, bor);
        const desertBand = smoothstep(10, 20, ab) * smoothstep(38, 27, ab);
        const tundra = smoothstep(56, 70, ab);
        const snowLine = 0.9 - (ab / 90) * 0.52;
        const coastK = smoothstep(28, 8, ab);
        const coastR = mix(62, 80, coastK), coastG = mix(152, 182, coastK), coastB = mix(160, 176, coastK);
        const polar = ab > 48;
        const capBase = lat >= 0 ? 67 : 61;             // 冰盖基准纬度（南极大、北极小）
        const floeLat = smoothstep(52, 64, ab);
        const tropical = ab < 32;

        for (let i = 0; i < W; i++) {
            const u = (i + 0.5) / W;
            const k = (j * W + i) * 4;
            const detail = nsAt(fDet, u * 28, v * 14);
            const e = sbl(eC, i) + (detail - 0.5) * 0.11;

            /* 极地冰盖边缘（噪声扰动的不规则纬线圈，极点方向递增） */
            let iceZone = 0;
            if (polar) {
                const cap = capBase + (sbl(capC, i) - 0.5) * 16;
                iceZone = smoothstep(cap - 3, cap + 3, ab);
            }

            const land = e > SEA;
            let r, gn, bl2, hgt;

            if (land) {
                const t = (e - SEA) / (1 - SEA);                       // 0 海岸 → 1 最高
                const mnt = smoothstep(0.62, 0.92, e * 0.7 + sbl(mountC, i) * 0.45);
                const dry = desertBand * smoothstep(0.55, 0.35, sbl(moistC, i));

                const vig = 0.88 + detail * 0.24;                      // 植被斑驳
                r = vegR * vig; gn = vegG * vig; bl2 = vegB * vig;
                r = mix(r, 198, dry * 0.9); gn = mix(gn, 168, dry * 0.9); bl2 = mix(bl2, 112, dry * 0.9);
                const rk = smoothstep(0.45, 0.8, t + mnt * 0.3);       // 高地岩石
                r = mix(r, 138, rk); gn = mix(gn, 122, rk); bl2 = mix(bl2, 104, rk);
                const beach = smoothstep(0.045, 0.012, t) * (1 - dry * 0.4);
                r = mix(r, 202, beach); gn = mix(gn, 186, beach); bl2 = mix(bl2, 142, beach);
                r = mix(r, 134, tundra * 0.8); gn = mix(gn, 126, tundra * 0.8); bl2 = mix(bl2, 108, tundra * 0.8);

                const sl = snowLine + (detail - 0.5) * 0.1;
                const snow = smoothstep(sl, sl + 0.08, t + mnt * 0.22);
                const icy = snow > iceZone ? snow : iceZone;
                r = mix(r, 240, icy); gn = mix(gn, 245, icy); bl2 = mix(bl2, 250, icy);

                hgt = clamp01(0.45 + t * 0.38 + mnt * 0.25);
                if (icy > 0.5 && hgt < 0.56 + (detail - 0.5) * 0.08) hgt = 0.56 + (detail - 0.5) * 0.08;
            } else {
                /* 海洋：岸线绿松石 → 大陆架 → 深海 → 深渊 的深度渐变 */
                const d = clamp01((SEA - e) / 0.34);
                if (d < 0.12) {
                    const q = d / 0.12;
                    r = mix(coastR, 34, q); gn = mix(coastG, 116, q); bl2 = mix(coastB, 166, q);
                } else if (d < 0.5) {
                    const q = (d - 0.12) / 0.38;
                    r = mix(34, 18, q); gn = mix(116, 70, q); bl2 = mix(166, 128, q);
                } else {
                    const q = (d - 0.5) / 0.5;
                    r = mix(18, 7, q); gn = mix(70, 33, q); bl2 = mix(128, 73, q);
                }
                const sw = (sbl(swirlC, i) - 0.5) * 10;                // 洋流大尺度明暗
                r += sw; gn += sw; bl2 += sw;

                /* 高纬浮冰（冰盖外缘碎冰斑，越靠近冰盖越密） */
                let floe = 0;
                if (polar) floe = smoothstep(0.58, 0.74, nsAt(fFloe, u * 44, v * 22)) * floeLat * 0.85;
                let icy = floe > iceZone ? floe : iceZone;
                r = mix(r, 228, icy); gn = mix(gn, 236, icy); bl2 = mix(bl2, 242, icy);

                /* 热带环礁小岛 */
                if (tropical && e > SEA - 0.006 && detail > 0.72) {
                    r = mix(r, 206, 0.9); gn = mix(gn, 190, 0.9); bl2 = mix(bl2, 150, 0.9);
                }
                hgt = 0.3 + d * 0.05 + (detail - 0.5) * 0.02;
                if (icy > 0.5 && hgt < 0.5 + (detail - 0.5) * 0.06) hgt = 0.5 + (detail - 0.5) * 0.06;
            }

            px[k] = r; px[k + 1] = gn; px[k + 2] = bl2; px[k + 3] = 255;
            const hb = hgt * 255;
            bpx[k] = hb; bpx[k + 1] = hb; bpx[k + 2] = hb; bpx[k + 3] = 255;
        }
    }
    ctx.putImageData(img, 0, 0);
    bctx.putImageData(bimg, 0, 0);
    return { map: mapC, bump: bumpC };
}

/* ========================= 云层（RGBA，alpha=覆盖率） ========================= */

function drawClouds(S) {
    const W = 1024, H = 512, HW = 512, HH = 256;
    const fW1 = makeField(4, 3, -1, 3, S[10]);
    const fW2 = makeField(4, 3, -1, 3, S[11]);
    const fD = makeField(7, 5, -2, 5.5, S[12]);        // 云系主体
    const fDet = makeField(22, 2, -1, 12, S[13]);      // 碎云

    const dC = new Float32Array(HW * HH);
    for (let j = 0; j < HH; j++) {
        const v = (j + 0.5) / HH;
        for (let i = 0; i < HW; i++) {
            const u = (i + 0.5) / HW;
            const w1 = nsAt(fW1, u * 4, v * 2) - 0.5;
            const w2 = nsAt(fW2, u * 4, v * 2) - 0.5;
            dC[j * HW + i] = nsAt(fD, u * 7 + w1 * 2.4, v * 3.5 + w2 * 2.4);
        }
    }
    normalizeField(dC, 0.105);       // 锁定云覆盖率

    const X0 = new Int32Array(W), X1 = new Int32Array(W), FX = new Float32Array(W);
    for (let i = 0; i < W; i++) {
        const gx = (i + 0.5) / W * HW - 0.5;
        let x0 = Math.floor(gx);
        FX[i] = gx - x0;
        if (x0 < 0) x0 += HW;
        X0[i] = x0;
        X1[i] = x0 + 1 === HW ? 0 : x0 + 1;
    }

    const c = mkCanvas(W, H), ctx = c.getContext('2d');
    const img = ctx.createImageData(W, H), px = img.data;

    for (let j = 0; j < H; j++) {
        const v = (j + 0.5) / H;
        const lat = 90 - 180 * v;
        const ab = Math.abs(lat);
        let y0 = Math.floor(v * HH - 0.5);
        if (y0 < 0) y0 = 0;
        else if (y0 > HH - 2) y0 = HH - 2;
        const fy = v * HH - 0.5 - y0;
        const r0 = y0 * HW, r1 = r0 + HW;
        const gaussEq = Math.exp(-(lat * lat) / 128);               // 赤道 ITCZ（σ≈8°）
        const gaussMid = Math.exp(-((ab - 52) * (ab - 52)) / 338);  // 中纬风暴带（σ≈13°）
        const gaussSub = Math.exp(-((ab - 26) * (ab - 26)) / 98);   // 副热带高压少云（σ≈7°）
        const gaussPol = Math.exp(-((ab - 84) * (ab - 84)) / 98);   // 极锋薄云
        const band = gaussEq * 0.15 + gaussMid * 0.13 - gaussSub * 0.16 + gaussPol * 0.1;

        for (let i = 0; i < W; i++) {
            const u = (i + 0.5) / W;
            const k = (j * W + i) * 4;
            const a0 = dC[r0 + X0[i]], a1 = dC[r0 + X1[i]];
            const b0 = dC[r1 + X0[i]], b1 = dC[r1 + X1[i]];
            const ax = a0 + (a1 - a0) * FX[i], bx = b0 + (b1 - b0) * FX[i];
            let d = ax + (bx - ax) * fy;
            d += (nsAt(fDet, u * 22, v * 11) - 0.5) * 0.22;         // 碎云细节
            d += band;
            const a = smoothstep(0.5, 0.71, d) * 0.94;
            px[k] = 250 + 5 * a;        // 暖白，厚云更亮
            px[k + 1] = 247 + 6 * a;
            px[k + 2] = 241 + 8 * a;
            px[k + 3] = a * 255;
        }
    }
    ctx.putImageData(img, 0, 0);
    return c;
}

/* ========================= 月面（月海 + 陨石坑 + 辐射纹） ========================= */

function moonCrater(g, x, y, r, maria, W) {
    const rimA = maria > 0.5 ? 0.3 : 0.5;   // 月海内缘对比弱一些
    for (const ox of [-W, 0, W]) {          // 经度环绕补画
        const cx = x + ox;
        if (cx + r * 1.2 < 0 || cx - r * 1.2 > W) continue;
        const gr = g.createRadialGradient(cx, y, r * 0.1, cx, y, r);
        gr.addColorStop(0.0, 'rgba(52,50,48,0.42)');        // 坑底阴影
        gr.addColorStop(0.45, 'rgba(60,58,56,0.30)');
        gr.addColorStop(0.62, 'rgba(90,88,86,0.10)');
        gr.addColorStop(0.78, 'rgba(236,233,228,' + rimA + ')'); // 亮缘
        gr.addColorStop(1.0, 'rgba(236,233,228,0)');
        g.fillStyle = gr;
        g.beginPath();
        g.arc(cx, y, r, 0, Math.PI * 2);
        g.fill();
        if (r > 8) {                                        // 大坑中央峰
            g.fillStyle = 'rgba(190,187,182,0.4)';
            g.beginPath();
            g.arc(cx, y, r * 0.14, 0, Math.PI * 2);
            g.fill();
        }
    }
}

function moonRays(g, x, y, r, W, rng) {
    const n = 9 + ((rng() * 6) | 0);
    g.lineCap = 'round';
    for (let k = 0; k < n; k++) {
        const ang = rng() * Math.PI * 2;
        const len = r * 2.2 + rng() * r * 5;
        g.strokeStyle = 'rgba(230,228,224,' + (0.06 + rng() * 0.09).toFixed(3) + ')';
        g.lineWidth = 0.8 + rng() * 1.8;
        const ca = Math.cos(ang), sa = Math.sin(ang);
        for (const ox of [-W, 0, W]) {
            const cx = x + ox;
            g.beginPath();
            g.moveTo(cx + ca * r * 0.9, y + sa * r * 0.9);
            g.lineTo(cx + ca * (r * 0.9 + len), y + sa * (r * 0.9 + len));
            g.stroke();
        }
    }
}

function drawMoon(S) {
    const W = 512, H = 256;
    const fN = makeField(9, 4, -1, 5.5, S[14]);        // 高地基底
    const fN2 = makeField(20, 2, -1, 11, S[15]);       // 细粒噪点
    const fMar = makeField(3, 4, 1, 4.5, S[16]);       // 月海大暗斑

    const c = mkCanvas(W, H), ctx = c.getContext('2d');
    const img = ctx.createImageData(W, H), px = img.data;
    const mariaMap = new Float32Array(W * H);

    for (let j = 0; j < H; j++) {
        const v = (j + 0.5) / H;
        const lat = 90 - 180 * v;
        const eqBias = (1 - Math.abs(lat) / 90) * 0.09;              // 月海偏向赤道一侧
        for (let i = 0; i < W; i++) {
            const u = (i + 0.5) / W;
            const k = (j * W + i) * 4;
            const n = nsAt(fN, u * 9, v * 4.5);
            const n2 = nsAt(fN2, u * 20, v * 10);
            let gv = 118 + n * 66 + (n2 - 0.5) * 14;                  // 高地亮壤
            const mm = smoothstep(0.575, 0.66, nsAt(fMar, u * 3 + 0.7, v * 1.5 + 2.1) + eqBias);
            gv = gv * (1 - 0.44 * mm) - 6 * mm;                       // 月海暗斑（低频大块）
            mariaMap[j * W + i] = mm;
            px[k] = gv; px[k + 1] = gv * 0.995; px[k + 2] = gv * 0.985; px[k + 3] = 255;
        }
    }
    ctx.putImageData(img, 0, 0);

    /* 陨石坑：小多大多，避开极端极区（避免等距圆柱拉伸变形） */
    const rng = mulberry32(S[17]);
    for (let ci = 0; ci < 210; ci++) {
        const r = 1.3 + 19 * Math.pow(rng(), 2.6);
        const x = rng() * W;
        const lat = (rng() * 2 - 1) * 82;
        if (Math.abs(lat) > 78 && rng() < 0.6) continue;
        const y = (90 - lat) / 180 * H;
        const jj = Math.max(0, Math.min(H - 1, y | 0));
        moonCrater(ctx, x, y, r, mariaMap[jj * W + (x | 0)], W);
    }
    /* 两个带辐射纹的年轻撞击坑 */
    moonRays(ctx, rng() * W, (90 - (-42)) / 180 * H, 9 + rng() * 4, W, rng);
    moonRays(ctx, rng() * W, (90 - 9) / 180 * H, 7 + rng() * 4, W, rng);
    return c;
}

/* ========================= 入口 ========================= */

export function build() {
    /* 每次调用全新随机种子 → 幂等但每次都是新地球/新月 */
    const base = (Math.random() * 0x7fffffff) | 0;
    const S = [];
    for (let i = 0; i < 18; i++) S.push((base + i * 7919 + 0x9e37) | 0);

    const surf = drawSurface(S);
    const cloud = drawClouds(S);
    const moon = drawMoon(S);

    const srgb = (canvas) => {
        const t = new THREE.CanvasTexture(canvas);
        t.colorSpace = THREE.SRGBColorSpace;
        return t;
    };
    const bumpTex = new THREE.CanvasTexture(surf.bump);   // 线性，不设 colorSpace

    return {
        map: srgb(surf.map),
        bumpMap: bumpTex,
        cloudMap: srgb(cloud),
        moonMap: srgb(moon),
    };
}
