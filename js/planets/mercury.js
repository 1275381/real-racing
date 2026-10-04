// js/planets/mercury.js —— 水星程序化贴图
//
// 契约（out/solar-design.md §1）：
//   · 顶部唯一导入 import * as THREE from 'three'，零外部资源，纯 canvas 绘制
//   · export function build() 无参/同步/幂等，返回 { map, bumpMap }
//   · map     1024×512 等距圆柱（x: 经度 0°→360°，y: 北极→南极），SRGBColorSpace，
//             左右边缘无缝（低频底色用整数周期正弦叠加保证 x=0/x=1023 连续；
//             陨石坑/辐射纹等超边元素按 x±W 环绕补画）
//   · bumpMap 同尺寸灰度高程（越白越高），不设 colorSpace（保持线性）
//   · 不设置 wrapS/wrapT/anisotropy/mipmaps/repeat（由 galaxy.js 统一处理）
//
// 视觉：灰褐月壤基底 + 冷暖斑块对比，密布大中小陨石坑（坑底暗、环缘受光亮），
//       卡洛里式同心环大盆地，若干新鲜亮坑的长辐射纹，表层细颗粒噪点。

import * as THREE from 'three';

const W = 1024;
const H = 512;

const TAU = Math.PI * 2;

function makeCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    return c;
}

const R = Math.random;
function rr(a, b) { return a + (b - a) * R(); }
function clamp255(v) { return v < 0 ? 0 : v > 255 ? 255 : v | 0; }

// 纬度（y=0 北极 → y=H 南极）
function latOf(y) { return (0.5 - y / H) * Math.PI; }
// 等距圆柱上保持球面圆形的横向拉伸系数（极区封顶，避免无限拉伸）
function stretchOf(y) { return 1 / Math.max(Math.cos(latOf(y)), 0.28); }

// 经度环绕补画：fn 会在 x-W / x / x+W 三个偏移处各执行一次（仅保留可能可见的）
const WRAP_OFFS = [-W, 0, W];
function withWrap(x, reachX, fn) {
    for (let k = 0; k < 3; k++) {
        const xx = x + WRAP_OFFS[k];
        if (xx + reachX > 0 && xx - reachX < W) fn(xx);
    }
}

// ---------------------------------------------------------------------------
// 1) 基底：低频明暗 + 冷暖斑块（整数周期正弦叠加 → 经度方向天然无缝）
//    同时生成 bump 的低频起伏。低频量每 2×2 像素采样一次（频率远低于采样密度）。
// ---------------------------------------------------------------------------
function paintBase(m, b) {
    const mImg = m.getImageData(0, 0, W, H);
    const bImg = b.getImageData(0, 0, W, H);
    const md = mImg.data;
    const bd = bImg.data;

    const makeWaves = (n, amp) => {
        const arr = [];
        for (let i = 0; i < n; i++) {
            arr.push({
                kx: 1 + Math.floor(R() * 6),          // 整数周期 → x 方向无缝
                ky: 1 + Math.floor(R() * 3),
                p: R() * TAU,
                a: rr(-1, 1) * amp,
            });
        }
        return arr;
    };
    const lumW = makeWaves(5, 6.5);   // 明暗
    const tintW = makeWaves(4, 9);    // 冷暖（红↑蓝↓ = 暖褐 / 红↓蓝↑ = 冷灰）
    const elW = makeWaves(4, 5.5);    // bump 低频地形起伏

    let lum = 0, tint = 0, el = 0;
    for (let y = 0; y < H; y++) {
        const evenY = (y & 1) === 0;
        for (let x = 0; x < W; x++) {
            if (evenY && (x & 1) === 0) {
                lum = 0; tint = 0; el = 0;
                const px = TAU * x / W, py = TAU * y / H;
                for (let i = 0; i < lumW.length; i++) {
                    const w = lumW[i];
                    lum += w.a * Math.sin(w.kx * px + w.ky * py + w.p);
                }
                for (let i = 0; i < tintW.length; i++) {
                    const w = tintW[i];
                    tint += w.a * Math.sin(w.kx * px + w.ky * py + w.p);
                }
                for (let i = 0; i < elW.length; i++) {
                    const w = elW[i];
                    el += w.a * Math.sin(w.kx * px + w.ky * py + w.p);
                }
            }
            const i = (y * W + x) * 4;
            const g = (R() - 0.5) * 9;                // 底色细噪
            // 灰褐月壤：R>G>B 的暖灰基调
            md[i]     = clamp255(141 + lum + tint + g);
            md[i + 1] = clamp255(133 + lum * 0.92 + tint * 0.35 + g);
            md[i + 2] = clamp255(123 + lum * 0.85 - tint * 0.9 + g);
            md[i + 3] = 255;
            const hv = clamp255(128 + el + (R() - 0.5) * 10);
            bd[i] = bd[i + 1] = bd[i + 2] = hv;
            bd[i + 3] = 255;
        }
    }
    m.putImageData(mImg, 0, 0);
    b.putImageData(bImg, 0, 0);
}

// ---------------------------------------------------------------------------
// 2) 卡洛里式大盆地：暗色平坦坑底 + 同心环脊 + 外围溅射晕
// ---------------------------------------------------------------------------
function drawBasin(m, b, x, y, r, strength) {
    const s = stretchOf(y);
    withWrap(x, r * 1.8 * s, (xx) => {
        // —— bump：浅盆地形 + 环脊 ——
        b.save(); b.translate(xx, y); b.scale(s, 1);
        const dFloor = b.createRadialGradient(0, 0, 0, 0, 0, r * 0.96);
        dFloor.addColorStop(0, `rgba(72,72,72,${0.55 * strength})`);
        dFloor.addColorStop(0.85, `rgba(95,95,95,${0.3 * strength})`);
        dFloor.addColorStop(1, 'rgba(128,128,128,0)');
        b.fillStyle = dFloor;
        b.beginPath(); b.arc(0, 0, r * 0.96, 0, TAU); b.fill();
        const rings = [0.5, 0.72, 0.93];
        for (let k = 0; k < rings.length; k++) {
            b.strokeStyle = `rgba(216,216,216,${(0.28 + 0.14 * k) * strength})`;
            b.lineWidth = 4 + k * 2;
            b.beginPath(); b.arc(0, 0, r * rings[k], 0, TAU); b.stroke();
        }
        b.restore();
        // —— map：低反照暖褐坑底 + 亮环 + 溅射晕 ——
        m.save(); m.translate(xx, y); m.scale(s, 1);
        const halo = m.createRadialGradient(0, 0, r * 0.9, 0, 0, r * 1.8);
        halo.addColorStop(0, `rgba(172,160,140,${0.26 * strength})`);
        halo.addColorStop(1, 'rgba(172,160,140,0)');
        m.fillStyle = halo;
        m.beginPath(); m.arc(0, 0, r * 1.8, 0, TAU); m.fill();
        const floor = m.createRadialGradient(0, 0, 0, 0, 0, r * 0.9);
        floor.addColorStop(0, `rgba(94,84,71,${0.5 * strength})`);
        floor.addColorStop(0.8, `rgba(104,94,80,${0.22 * strength})`);
        floor.addColorStop(1, 'rgba(110,100,86,0)');
        m.fillStyle = floor;
        m.beginPath(); m.arc(0, 0, r * 0.9, 0, TAU); m.fill();
        for (let k = 0; k < rings.length; k++) {
            m.strokeStyle = `rgba(184,176,160,${(0.3 - 0.06 * k) * strength})`;
            m.lineWidth = 2.5 + k * 1.5;
            m.beginPath(); m.arc(0, 0, r * rings[k], 0, TAU); m.stroke();
        }
        m.restore();
    });
}

// ---------------------------------------------------------------------------
// 3) 平滑平原：大而柔的冷暖色调补丁（拉开全局冷暖对比）
// ---------------------------------------------------------------------------
function drawPlains(m) {
    const tints = [
        [162, 145, 123],   // 暖褐平原
        [124, 127, 136],   // 冷灰平原
        [152, 141, 126],
    ];
    for (let i = 0; i < 5; i++) {
        const x = R() * W;
        const y = rr(H * 0.16, H * 0.84);
        const r = rr(75, 155);
        const t = tints[Math.floor(R() * tints.length)];
        const a = rr(0.1, 0.17);
        withWrap(x, r, (xx) => {
            const g = m.createRadialGradient(xx, y, r * 0.15, xx, y, r);
            g.addColorStop(0, `rgba(${t[0]},${t[1]},${t[2]},${a})`);
            g.addColorStop(1, `rgba(${t[0]},${t[1]},${t[2]},0)`);
            m.fillStyle = g;
            m.beginPath(); m.arc(xx, y, r, 0, TAU); m.fill();
        });
    }
}

// ---------------------------------------------------------------------------
// 4) 陨石坑：坑底暗、受光侧环缘亮弧、背光侧暗弧；bump 为对称深度剖面
//    （光向取纹理左上，全局一致，叠加动态光照后仍保有雕刻感）
// ---------------------------------------------------------------------------
function drawCrater(m, b, x, y, r, fresh) {
    const s = stretchOf(y);
    withWrap(x, r * 1.7 * s, (xx) => {
        // —— bump 高程：中心深 → 环脊最高 → 回落平原 ——
        b.save(); b.translate(xx, y); b.scale(s, 1);
        const hb = b.createRadialGradient(0, 0, 0, 0, 0, r * 1.3);
        hb.addColorStop(0, 'rgba(52,52,52,0.85)');
        hb.addColorStop(0.42, 'rgba(96,96,96,0.75)');
        hb.addColorStop(0.7, 'rgba(150,150,150,0.55)');
        hb.addColorStop(0.86, 'rgba(236,236,236,0.85)');
        hb.addColorStop(1, 'rgba(150,150,150,0)');
        b.fillStyle = hb;
        b.beginPath(); b.arc(0, 0, r * 1.3, 0, TAU); b.fill();
        if (r > 11) {  // 大坑中央峰
            const cg = b.createRadialGradient(0, 0, 0, 0, 0, r * 0.22);
            cg.addColorStop(0, 'rgba(224,224,224,0.7)');
            cg.addColorStop(1, 'rgba(224,224,224,0)');
            b.fillStyle = cg;
            b.beginPath(); b.arc(0, 0, r * 0.22, 0, TAU); b.fill();
        }
        b.restore();
        // —— map 反照 ——
        m.save(); m.translate(xx, y); m.scale(s, 1);
        if (r > 3.5) {  // 溅射物晕（新鲜坑更亮）
            const ea = fresh ? 0.32 : 0.12;
            const eg = m.createRadialGradient(0, 0, r * 0.8, 0, 0, r * 1.7);
            eg.addColorStop(0, `rgba(198,190,173,${ea})`);
            eg.addColorStop(1, 'rgba(198,190,173,0)');
            m.fillStyle = eg;
            m.beginPath(); m.arc(0, 0, r * 1.7, 0, TAU); m.fill();
        }
        const fg = m.createRadialGradient(0, 0, 0, 0, 0, r * 0.95);
        fg.addColorStop(0, 'rgba(82,72,60,0.5)');
        fg.addColorStop(0.75, 'rgba(95,85,72,0.4)');
        fg.addColorStop(1, 'rgba(120,110,96,0)');
        m.fillStyle = fg;
        m.beginPath(); m.arc(0, 0, r * 0.95, 0, TAU); m.fill();
        if (r > 2.2) {  // 环缘受光/背光弧
            const A = -Math.PI * 0.75;            // 光来自左上
            const span = 1.85;
            m.lineWidth = Math.max(1, r * 0.26);
            m.strokeStyle = `rgba(216,208,192,${fresh ? 0.6 : 0.42})`;
            m.beginPath(); m.arc(0, 0, r * 0.97, A - span, A + span); m.stroke();
            m.strokeStyle = 'rgba(50,43,35,0.42)';
            m.beginPath(); m.arc(0, 0, r * 0.97, A + Math.PI - span, A + Math.PI + span); m.stroke();
        }
        m.restore();
    });
}

function drawCraters(m, b) {
    // 大中型坑：小尺寸占多数（幂律偏置）
    for (let i = 0; i < 400; i++) {
        const y = rr(H * 0.06, H * 0.94);
        if (Math.abs(latOf(y)) > 1.36) continue;   // ±78° 以内
        const r = 2.5 + 27 * Math.pow(R(), 2.4);
        drawCrater(m, b, R() * W, y, r, false);
    }
    // 密集小坑层
    for (let i = 0; i < 260; i++) {
        const y = rr(H * 0.05, H * 0.95);
        if (Math.abs(latOf(y)) > 1.36) continue;
        drawCrater(m, b, R() * W, y, 1.2 + 1.9 * R(), false);
    }
}

// ---------------------------------------------------------------------------
// 5) 辐射纹系统：新鲜亮坑 + 数十条微弯亮线（加色叠加，越长越细淡）
// ---------------------------------------------------------------------------
function drawRaySystems(m, b) {
    const n = 6 + Math.floor(R() * 3);
    for (let i = 0; i < n; i++) {
        const x = R() * W;
        const y = rr(H * 0.18, H * 0.82);
        const rc = rr(3.5, 7);
        const s = stretchOf(y);
        drawCrater(m, b, x, y, rc, true);
        const rays = 34 + Math.floor(R() * 46);
        m.save();
        m.globalCompositeOperation = 'lighter';
        withWrap(x, rc * 11 * s, (xx) => {
            m.save(); m.translate(xx, y); m.scale(s, 1);
            const hg = m.createRadialGradient(0, 0, rc * 0.5, 0, 0, rc * 4);
            hg.addColorStop(0, 'rgba(212,205,190,0.3)');
            hg.addColorStop(1, 'rgba(212,205,190,0)');
            m.fillStyle = hg;
            m.beginPath(); m.arc(0, 0, rc * 4, 0, TAU); m.fill();
            for (let k = 0; k < rays; k++) {
                const ang = R() * TAU;
                const len = rc * (2.5 + R() * 8.5);
                const ex = Math.cos(ang) * len;
                const ey = Math.sin(ang) * len;
                const bow = (R() - 0.5) * len * 0.35;      // 轻微弯曲
                const nx = -Math.sin(ang), ny = Math.cos(ang);
                m.strokeStyle = `rgba(224,218,204,${(0.05 + R() * 0.1).toFixed(3)})`;
                m.lineWidth = 0.8 + R() * 2.4;
                m.beginPath();
                m.moveTo(Math.cos(ang) * rc * 0.55, Math.sin(ang) * rc * 0.55);
                m.quadraticCurveTo(ex * 0.5 + nx * bow, ey * 0.5 + ny * bow, ex, ey);
                m.stroke();
            }
            m.restore();
        });
        m.restore();
    }
}

// ---------------------------------------------------------------------------
// 6) 表层颗粒：全图逐像素中性噪点（map）+ 高程细碎起伏（bump）
// ---------------------------------------------------------------------------
function addGrain(m, b) {
    const mi = m.getImageData(0, 0, W, H);
    const bi = b.getImageData(0, 0, W, H);
    const md = mi.data;
    const bd = bi.data;
    for (let i = 0; i < md.length; i += 4) {
        const g = (R() - 0.5) * 13;
        md[i] = clamp255(md[i] + g);
        md[i + 1] = clamp255(md[i + 1] + g);
        md[i + 2] = clamp255(md[i + 2] + g);
        const hv = clamp255(bd[i] + (R() - 0.5) * 26);
        bd[i] = bd[i + 1] = bd[i + 2] = hv;
    }
    m.putImageData(mi, 0, 0);
    b.putImageData(bi, 0, 0);
}

// ---------------------------------------------------------------------------

export function build() {
    const mapCanvas = makeCanvas(W, H);
    const bumpCanvas = makeCanvas(W, H);
    const m = mapCanvas.getContext('2d');
    const b = bumpCanvas.getContext('2d');

    paintBase(m, b);       // 底色 + 冷暖/明暗斑块（无缝）
    drawBasin(m, b, R() * W, rr(H * 0.3, H * 0.46), rr(64, 88), 1.0);    // 卡洛里级
    drawBasin(m, b, R() * W, rr(H * 0.52, H * 0.7), rr(36, 52), 0.7);
    drawBasin(m, b, R() * W, rr(H * 0.3, H * 0.66), rr(22, 34), 0.55);
    drawPlains(m);
    drawCraters(m, b);
    drawRaySystems(m, b);
    addGrain(m, b);

    const map = new THREE.CanvasTexture(mapCanvas);
    map.colorSpace = THREE.SRGBColorSpace;
    const bumpMap = new THREE.CanvasTexture(bumpCanvas);   // 不设 colorSpace，保持线性
    return { map, bumpMap };
}
