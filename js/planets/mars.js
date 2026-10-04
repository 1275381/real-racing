// js/planets/mars.js —— 火星程序化贴图（canvas 2D，零外部资源）
// 视觉要素：锈红荒漠、暗色玄武岩平原（Syrtis Major 类大暗斑）、白色南北极冠、
// 密集陨坑（坑底阴影 + 亮缘 + 向光/背光弧）、水手谷峡谷带 + 分支 + 东端泛滥河道、
// 奥林帕斯等盾状火山、Hellas 亮盆地、尘暴亮纱、经向风蚀条纹。
// 契约：export function build() → { map(1024×512 SRGB), bumpMap(1024×512 线性灰度) }。
// 经度无缝：所有周期噪声 x 向按整数周期取模；所有矢量图形在 x、x±W 各画一次（环绕补画）。
import * as THREE from 'three';

const TAU = Math.PI * 2;
const W = 1024;
const H = 512;

// —— 值噪声：x 方向按 period（格数）取模 → 左右边缘严格无缝 ——
function makeNoise() {
    const p = new Uint8Array(256);
    for (let i = 0; i < 256; i++) p[i] = i;
    for (let i = 255; i > 0; i--) {
        const j = (Math.random() * (i + 1)) | 0;
        const t = p[i]; p[i] = p[j]; p[j] = t;
    }
    const perm = new Uint8Array(1024);
    for (let i = 0; i < 1024; i++) perm[i] = p[i & 255];
    return function noise(x, y, period) {
        const ix = Math.floor(x), iy = Math.floor(y);
        const fx = x - ix, fy = y - iy;
        const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
        const x0 = ((ix % period) + period) % period;
        const x1 = (x0 + 1) % period;
        const y0 = iy & 255, y1 = (iy + 1) & 255;
        const v00 = perm[x0 + perm[y0]];
        const v10 = perm[x1 + perm[y0]];
        const v01 = perm[x0 + perm[y1]];
        const v11 = perm[x1 + perm[y1]];
        const a = v00 + (v10 - v00) * sx;
        const b = v01 + (v11 - v01) * sx;
        return (a + (b - a) * sy) / 255;
    };
}

function fbm(noise, x, y, oct, period) {
    let sum = 0, amp = 1, tot = 0;
    for (let o = 0; o < oct; o++) {
        sum += noise(x, y, period) * amp;
        tot += amp;
        amp *= 0.5;
        x *= 2;
        period *= 2;
    }
    return sum / tot;
}

function clamp01(t) { return t < 0 ? 0 : t > 1 ? 1 : t; }
function smoothstep(a, b, t) { t = clamp01((t - a) / (b - a)); return t * t * (3 - 2 * t); }
function lerp(a, b, t) { return a + (b - a) * t; }

export function build() {
    const nCont = makeNoise();    // 大陆尺度（玄武岩省）
    const nDet = makeNoise();     // 中细纹理
    const nStreak = makeNoise();  // 经向拉长的风蚀条纹
    const nCap = makeNoise();     // 极冠边界

    const canvas = document.createElement('canvas');
    canvas.width = W; canvas.height = H;
    const ctx = canvas.getContext('2d');

    const bCanvas = document.createElement('canvas');
    bCanvas.width = W; bCanvas.height = H;
    const bctx = bCanvas.getContext('2d');

    // —— 极冠边界（逐列，x 向周期噪声 → 无缝；北冠大、南冠小）——
    const capN = new Float32Array(W);
    const capS = new Float32Array(W);
    for (let x = 0; x < W; x++) {
        const u = x / W;
        const w1 = fbm(nCap, u * 8 + 2.7, 3.7, 3, 8);
        const w2 = fbm(nCap, u * 23, 9.1, 2, 23);
        capN[x] = H * (0.026 + 0.034 * w1 + 0.014 * w2);
        capS[x] = H * (0.952 - 0.024 * w1 - 0.012 * w2);
    }

    // —— 逐像素基底：颜色 + 高程同步生成 ——
    const img = ctx.createImageData(W, H);
    const bd = bctx.createImageData(W, H);
    const px = img.data, bp = bd.data;
    let i = 0;
    for (let y = 0; y < H; y++) {
        const v = y / H;
        const latAbs = Math.abs(v - 0.5) * 2;              // 0 赤道 → 1 极
        const polarT = smoothstep(0.55, 0.95, latAbs);
        for (let x = 0; x < W; x++) {
            const u = x / W;
            const cont = fbm(nCont, u * 5 + 11.3, v * 2.5 + 7.1, 3, 5);
            const det = fbm(nDet, u * 26 + 4.2, v * 13 + 3.3, 2, 26);
            const streak = fbm(nStreak, u * 64, v * 6.5 + 21.4, 1, 64);

            const mm = cont * 0.72 + det * 0.28;
            const basalt = smoothstep(0.50, 0.66, mm);     // 玄武岩暗平原
            const deep = smoothstep(0.72, 0.86, mm);       // 更深的暗色核心

            // 锈红基底 ↔ 亮尘高原
            let r = lerp(176, 217, det);
            let g = lerp(98, 152, det);
            let b = lerp(61, 105, det);
            // 暗色玄武岩平原
            r = lerp(r, 104, basalt); g = lerp(g, 61, basalt); b = lerp(b, 45, basalt);
            r = lerp(r, 82, deep); g = lerp(g, 46, deep); b = lerp(b, 36, deep);
            // 风蚀条纹（x 向高频、y 向低频 → 经向拉长）
            const s = (streak - 0.5) * 24;
            r += s; g += s * 0.85; b += s * 0.7;
            // 极区霜尘变浅
            r = lerp(r, 208, polarT * 0.38);
            g = lerp(g, 180, polarT * 0.38);
            b = lerp(b, 156, polarT * 0.38);
            // 细颗粒噪点
            const gr = (Math.random() - 0.5) * 9;
            r += gr; g += gr; b += gr;

            // 白色极冠（羽化边界 + 冠内纹理）
            const cn = smoothstep(0, 6, capN[x] - y);
            const cs = smoothstep(0, 6, y - capS[x]);
            const cap = cn > cs ? cn : cs;
            if (cap > 0) {
                const inside = 0.72 + 0.28 * det;
                r = lerp(r, lerp(214, 247, cap * inside), cap);
                g = lerp(g, lerp(196, 243, cap * inside), cap);
                b = lerp(b, lerp(188, 238, cap * inside), cap);
            }

            px[i]     = r < 0 ? 0 : r > 255 ? 255 : r;
            px[i + 1] = g < 0 ? 0 : g > 255 ? 255 : g;
            px[i + 2] = b < 0 ? 0 : b > 255 ? 255 : b;
            px[i + 3] = 255;

            // 高程：大陆起伏 + 细节 + 条纹微起伏；平原略低；极冠霜层略高
            let h = 132 + (cont - 0.5) * 78 + (det - 0.5) * 44 + (streak - 0.5) * 12;
            h -= basalt * 14 + deep * 10;
            h = lerp(h, 206, cap * 0.42);
            const hg = h < 0 ? 0 : h > 255 ? 255 : h;
            bp[i] = hg; bp[i + 1] = hg; bp[i + 2] = hg; bp[i + 3] = 255;
            i += 4;
        }
    }
    ctx.putImageData(img, 0, 0);
    bctx.putImageData(bd, 0, 0);

    // —— 矢量细节层（全部环绕补画）——
    function withWrap(cx, draw) { draw(cx); draw(cx - W); draw(cx + W); }

    function radial(c, cx, cy, r0, r1, cr, cg, cb, stops) {
        const g = c.createRadialGradient(cx, cy, r0, cx, cy, r1);
        for (let k = 0; k < stops.length; k++)
            g.addColorStop(stops[k][0], `rgba(${cr},${cg},${cb},${stops[k][1]})`);
        return g;
    }

    // 椭圆软斑（反照率斑块 / 尘纱 / 盆地）
    function patch(c, x, y, rx, ry, cr, cg, cb, ca) {
        withWrap(x, (cx) => {
            c.save();
            c.translate(cx, y);
            c.scale(rx / ry, 1);
            const g = c.createRadialGradient(0, 0, ry * 0.1, 0, 0, ry);
            g.addColorStop(0, `rgba(${cr},${cg},${cb},${ca})`);
            g.addColorStop(0.6, `rgba(${cr},${cg},${cb},${ca * 0.55})`);
            g.addColorStop(1, `rgba(${cr},${cg},${cb},0)`);
            c.fillStyle = g;
            c.beginPath(); c.arc(0, 0, ry, 0, TAU); c.fill();
            c.restore();
        });
    }

    // 陨坑：坑底阴影 + 亮缘环 + 向光/背光弧（贴图为反照率，弧线给浮雕感）
    function crater(c, x, y, r, bump) {
        withWrap(x, (cx) => {
            c.fillStyle = bump
                ? radial(c, cx, y, r * 0.1, r, 0, 0, 0, [[0, 0.42], [0.7, 0.16], [1, 0]])
                : radial(c, cx, y, r * 0.1, r, 56, 30, 23, [[0, 0.34], [0.7, 0.15], [1, 0]]);
            c.beginPath(); c.arc(cx, y, r, 0, TAU); c.fill();

            c.lineWidth = Math.max(1, r * 0.14);
            c.strokeStyle = bump ? 'rgba(255,255,255,0.42)' : 'rgba(240,192,152,0.26)';
            c.beginPath(); c.arc(cx, y, r * 0.9, 0, TAU); c.stroke();

            c.lineWidth = Math.max(1, r * 0.2);
            c.strokeStyle = bump ? 'rgba(255,255,255,0.34)' : 'rgba(246,208,168,0.26)';
            c.beginPath(); c.arc(cx, y, r * 0.95, Math.PI * 0.8, Math.PI * 1.6); c.stroke();
            c.strokeStyle = bump ? 'rgba(0,0,0,0.34)' : 'rgba(66,36,27,0.24)';
            c.beginPath(); c.arc(cx, y, r * 0.95, Math.PI * 1.85, Math.PI * 2.65); c.stroke();
        });
    }

    // 盾状火山：亮晕（bump 为穹隆）+ 外缘陡崖暗环 + 暗色火山口
    function volcano(c, x, y, r, bump) {
        withWrap(x, (cx) => {
            c.fillStyle = bump
                ? radial(c, cx, y, r * 0.05, r, 255, 255, 255, [[0, 0.85], [0.55, 0.35], [1, 0]])
                : radial(c, cx, y, r * 0.05, r, 234, 178, 132, [[0, 0.34], [0.55, 0.16], [1, 0]]);
            c.beginPath(); c.arc(cx, y, r, 0, TAU); c.fill();

            c.lineWidth = Math.max(1.2, r * 0.06);
            c.strokeStyle = bump ? 'rgba(0,0,0,0.30)' : 'rgba(96,52,38,0.20)';
            c.beginPath(); c.arc(cx, y, r * 0.94, 0, TAU); c.stroke();

            c.fillStyle = bump ? 'rgba(0,0,0,0.66)' : 'rgba(52,28,22,0.5)';
            c.beginPath(); c.arc(cx, y, r * 0.16, 0, TAU); c.fill();
        });
    }

    // 峡谷碎块：亮壁 + 深暗核心（bump 为凹槽）
    function chasmBlob(c, x, y, r, bump) {
        withWrap(x, (cx) => {
            c.fillStyle = bump
                ? radial(c, cx, y, 0, r * 2.1, 255, 255, 255, [[0, 0.28], [1, 0]])
                : radial(c, cx, y, 0, r * 2.1, 216, 152, 112, [[0, 0.24], [1, 0]]);
            c.beginPath(); c.arc(cx, y, r * 2.1, 0, TAU); c.fill();
            c.fillStyle = bump
                ? radial(c, cx, y, 0, r, 0, 0, 0, [[0, 0.6], [0.8, 0.4], [1, 0]])
                : radial(c, cx, y, 0, r, 42, 21, 16, [[0, 0.55], [0.8, 0.35], [1, 0]]);
            c.beginPath(); c.arc(cx, y, r, 0, TAU); c.fill();
        });
    }

    // 1) 大暗斑（玄武岩反照率斑：Syrtis Major 等）
    const darkPatches = [
        [0.80, 0.50, 74, 34, 0.46],
        [0.34, 0.62, 62, 30, 0.40],
        [0.55, 0.44, 46, 20, 0.30],
        [0.09, 0.40, 42, 24, 0.26],
        [0.66, 0.64, 38, 22, 0.24],
    ];
    for (let k = 0; k < darkPatches.length; k++) {
        const d = darkPatches[k];
        patch(ctx, d[0] * W, d[1] * H, d[2], d[3], 66, 38, 30, d[4]);
        patch(bctx, d[0] * W, d[1] * H, d[2] * 0.9, d[3] * 0.9, 0, 0, 0, 0.12);
    }

    // 2) Hellas 亮盆地（颜色亮环 + 高程凹陷）
    patch(ctx, 0.20 * W, 0.63 * H, 60, 40, 234, 198, 162, 0.30);
    patch(bctx, 0.20 * W, 0.63 * H, 56, 38, 0, 0, 0, 0.18);

    // 3) 盾状火山群（Olympus Mons + Tharsis 三连 + Elysium）
    const volcs = [
        [0.685, 0.415, 40],
        [0.165, 0.415, 26],
        [0.215, 0.350, 22],
        [0.255, 0.450, 20],
        [0.610, 0.300, 16],
    ];
    for (let k = 0; k < volcs.length; k++) {
        volcano(ctx, volcs[k][0] * W, volcs[k][1] * H, volcs[k][2], false);
        volcano(bctx, volcs[k][0] * W, volcs[k][1] * H, volcs[k][2], true);
    }

    // 4) 水手谷：赤道南侧蜿蜒峡谷带 + 短分支 + 东端泛滥河道
    const N = 150;
    const path = [];
    for (let k = 0; k <= N; k++) {
        const t = k / N;
        path.push({
            x: W * (0.305 + 0.265 * t),
            y: H * 0.548
                + Math.sin(t * Math.PI * 2.1 + 0.6) * H * 0.02
                + Math.sin(t * 11.2 + 2.0) * 3.2
                + (Math.random() - 0.5) * 2.4,
            r: 3.2 + Math.sin(t * Math.PI * 0.9) * 5.6 + Math.random() * 1.4,
        });
    }
    for (let k = 0; k <= N; k++) {
        chasmBlob(ctx, path[k].x, path[k].y, path[k].r, false);
        chasmBlob(bctx, path[k].x, path[k].y, path[k].r, true);
    }
    for (let bi = 0; bi < 5; bi++) {                       // 南北向分支峡谷
        let bx = path[Math.floor((0.12 + bi * 0.18) * N)].x;
        let by = path[Math.floor((0.12 + bi * 0.18) * N)].y;
        const dir = bi % 2 === 0 ? -1 : 1;
        for (let s2 = 0; s2 < 12; s2++) {
            bx += 3.4 + Math.random() * 2.2;
            by += dir * (1.6 + Math.random() * 2.4);
            const r = Math.max(1.6, 4.2 - s2 * 0.28);
            chasmBlob(ctx, bx, by, r, false);
            chasmBlob(bctx, bx, by, r, true);
        }
    }
    for (let ci = 0; ci < 3; ci++) {                       // 东端泛滥河道（向东北散开）
        let ox = path[N].x + 4, oy = path[N].y;
        for (let s2 = 0; s2 < 16; s2++) {
            ox += 3.2;
            oy -= 1.4 + ci * 0.6 + Math.random() * 1.4;
            const r = Math.max(1.2, 3.6 - s2 * 0.2);
            chasmBlob(ctx, ox, oy, r, false);
            chasmBlob(bctx, ox, oy, r, true);
        }
    }

    // 5) 陨坑群（避开极冠带）+ 两个大撞击盆地
    const craters = [];
    for (let k = 0; k < 240; k++) {
        craters.push({
            x: Math.random() * W,
            y: H * (0.09 + Math.random() * 0.82),
            r: 2 + Math.pow(Math.random(), 2.4) * 24,
        });
    }
    craters.push({ x: 0.30 * W, y: 0.72 * H, r: 46 });
    craters.push({ x: 0.90 * W, y: 0.68 * H, r: 38 });
    for (let k = 0; k < craters.length; k++) {
        crater(ctx, craters[k].x, craters[k].y, craters[k].r, false);
        crater(bctx, craters[k].x, craters[k].y, craters[k].r, true);
    }

    // 6) 尘暴亮纱（只影响颜色）
    patch(ctx, 0.45 * W, 0.30 * H, 150, 70, 232, 190, 150, 0.10);
    patch(ctx, 0.72 * W, 0.58 * H, 120, 60, 232, 190, 150, 0.09);
    patch(ctx, 0.18 * W, 0.52 * H, 100, 55, 232, 190, 150, 0.08);

    // —— 纹理（wrap/采样参数一律不设，由 galaxy.js 统一处理）——
    const map = new THREE.CanvasTexture(canvas);
    map.colorSpace = THREE.SRGBColorSpace;
    const bumpMap = new THREE.CanvasTexture(bCanvas);
    return { map, bumpMap };
}
