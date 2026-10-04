import * as THREE from 'three';

/* 木星主贴图：1024×512 等距圆柱投影（x = 经度 0°→360°，y = 北极→南极）。
 * 视觉层次（全部 canvas 2D 程序化，零外部资源）：
 *  1) 米/橙/棕纬向条带：亮区(zone)+暗带(belt) 纬度色带 LUT，边界陡化插值
 *  2) 带界湍流扭曲：整数谐波正弦 + 周期格点 fbm 对纬度做波状偏移（经度天然无缝）
 *  3) 条带内水平拉长的湍流条痕：各向异性 fbm，暗带染色更脏更红
 *  4) 带界涡纹覆层：亮/暗交替的小椭圆串（NEB/SEB/STB/NTB 南北缘）
 *  5) NEB 南缘蓝灰花絮(festoon)下垂 + 亮羽流；南温带白椭圆涡；随机小风暴核
 *  6) 大红斑椭圆风暴：奶油色领圈 + 同心砖红椭圆 + 内部螺旋弧 + 西侧尾流涡列
 *  7) 极区变暗去饱和 + 斑驳噪点；全图细颗粒噪点收尾
 * 契约：仅返回 { map }（气巨不提供 bump）；不设 anisotropy/mipmap/repeat，
 * wrapS/wrapT 保持默认 ClampToEdgeWrapping，无缝由绘制保证。 */

export function build() {
    const W = 1024, H = 512;

    /* —— 可复现随机（每次 build 重新播种 → 幂等、无共享内部状态）—— */
    let seed = 0x13572468;
    const rand = () => {
        seed = (seed + 0x6d2b79f5) | 0;
        let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };

    /* —— 周期格点值噪声：第一维以 256 取模，任何“整数圈数”采样经度无缝 —— */
    const LX = 256, LY = 128;
    const lattice = new Float32Array(LX * LY);
    for (let i = 0; i < lattice.length; i++) lattice[i] = rand();
    const sm = (t) => t * t * (3 - 2 * t);
    const noise2 = (u, v) => {
        const xi = Math.floor(u), yi = Math.floor(v);
        const fx = sm(u - xi), fy = sm(v - yi);
        const x0 = ((xi % LX) + LX) % LX, x1 = (x0 + 1) % LX;
        const y0 = yi < 0 ? 0 : (yi > LY - 2 ? LY - 2 : yi);
        const y1 = y0 + 1;
        const a = lattice[y0 * LX + x0], b = lattice[y0 * LX + x1];
        const c = lattice[y1 * LX + x0], d = lattice[y1 * LX + x1];
        return a + (b - a) * fx + (c - a) * fy + (d - b - c + a) * fx * fy;
    };
    const fbm = (u, v, oct) => {
        let s = 0, amp = 0.5, f = 1;
        for (let o = 0; o < oct; o++) {
            s += amp * noise2(u * f + o * 41.7, v * f + o * 23.3);
            amp *= 0.5; f *= 2;
        }
        return s;
    };

    /* —— 纬度色带定义：[纬度°, 颜色, 暗带权重(0=亮区, 1=暗带)]，北→南 —— */
    const STOPS = [
        [ 90.0, 0x857768, 0.0], [ 78.0, 0x8f8071, 0.1], [ 70.0, 0x97887a, 0.15],
        [ 64.0, 0xa08c6c, 0.3],
        [ 56.0, 0xb5a483, 0.2], [ 50.0, 0xcabcaa, 0.0], [ 45.5, 0xa5744c, 0.8],
        [ 41.0, 0xd8c8a8, 0.1], [ 36.5, 0xad7a50, 0.7], [ 31.0, 0xc4a57c, 0.2],
        [ 26.0, 0xba6f42, 0.9], [ 19.5, 0xa8653a, 1.0], [ 16.0, 0xe4d6ba, 0.0],
        [  8.0, 0xeedfc7, 0.0], [  1.0, 0xe7d9be, 0.1], [ -6.0, 0xcbb896, 0.2],
        [-10.0, 0xb57a4e, 0.8], [-15.5, 0xab6c42, 1.0], [-20.5, 0xcab694, 0.3],
        [-26.0, 0xddd0b2, 0.0], [-31.0, 0xad8a62, 0.7], [-37.0, 0xd4c5a7, 0.1],
        [-43.0, 0xb09a7e, 0.3], [-50.0, 0xa8967c, 0.2], [-60.0, 0x9d8b74, 0.2],
        [-70.0, 0x948475, 0.15], [-80.0, 0x8c7d70, 0.1], [-90.0, 0x857768, 0.0],
    ];
    const NLAT = 2048;
    const lutR = new Float32Array(NLAT), lutG = new Float32Array(NLAT);
    const lutB = new Float32Array(NLAT), lutBelt = new Float32Array(NLAT);
    for (let i = 0; i < NLAT; i++) {
        const phi = 90 - (i / (NLAT - 1)) * 180;
        let k = 0;
        while (k < STOPS.length - 2 && phi < STOPS[k + 1][0]) k++;
        const s0 = STOPS[k], s1 = STOPS[k + 1];
        let t = (phi - s0[0]) / (s1[0] - s0[0]);
        t = Math.min(1, Math.max(0, (t - 0.5) * 1.7 + 0.5));   // 条带边界陡化
        t = sm(t);
        const r0 = (s0[1] >> 16) & 255, g0 = (s0[1] >> 8) & 255, b0 = s0[1] & 255;
        const r1 = (s1[1] >> 16) & 255, g1 = (s1[1] >> 8) & 255, b1 = s1[1] & 255;
        lutR[i] = r0 + (r1 - r0) * t;
        lutG[i] = g0 + (g1 - g0) * t;
        lutB[i] = b0 + (b1 - b0) * t;
        lutBelt[i] = s0[2] + (s1[2] - s0[2]) * t;
    }

    const canvas = document.createElement('canvas');
    canvas.width = W; canvas.height = H;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });

    /* ============ 第 1 层：逐像素条带 + 湍流扭曲 + 极区变暗 ============ */
    const TAU = Math.PI * 2;
    const img = ctx.createImageData(W, H);
    const D = img.data;
    for (let y = 0; y < H; y++) {
        const v = y / H;
        const phi = (0.5 - v) * 180;                 // +90 北极 → -90 南极
        const ap = Math.abs(phi);
        const pfs = sm(Math.min(1, Math.max(0, (ap - 48) / 38)));   // 极区因子
        for (let x = 0; x < W; x++) {
            const u = x / W;
            const lam = u * TAU;
            // 带界波状扭曲：整数次谐波（经度周期）+ 周期 fbm 碎屑
            const warp = 2.2 * Math.sin(3 * lam + 0.7 + phi * 0.21)
                       + 1.5 * Math.sin(7 * lam + 2.1 + phi * 0.35)
                       + 1.1 * Math.sin(13 * lam + 4.4 + phi * 0.12)
                       + 0.8 * Math.sin(23 * lam + 1.9 + phi * 0.50)
                       + (fbm(u * 1024, v * 90 + 11.0, 2) - 0.5) * 3.4;
            let li = ((90 - (phi + warp)) / 180) * (NLAT - 1);
            li = li < 0 ? 0 : (li > NLAT - 1 ? NLAT - 1 : li) | 0;
            const belt = lutBelt[li];
            // 水平拉长的湍流条痕（暗带更脏更红）+ 细颗粒 + 极区斑驳
            const streak = fbm(u * 768, v * 44 + 53.0, 3) - 0.5;
            const grain = noise2(u * 6144, v * 168) - 0.5;
            const br = 1 + streak * (0.10 + 0.20 * belt) + grain * 0.055
                     + (noise2(u * 2048, v * 140 + 77.0) - 0.5) * 0.16 * pfs;
            let r = lutR[li] * br, g = lutG[li] * br, b = lutB[li] * br;
            const red = streak > 0 ? streak * belt : 0;
            r += red * 26; g += red * 8;
            if (pfs > 0) {                            // 极区：去饱和 + 变暗
                const lum = (0.30 * r + 0.59 * g + 0.11 * b) * 0.92;
                const mix = 0.30 * pfs;
                r += (lum - r) * mix; g += (lum - g) * mix; b += (lum - b) * mix;
                const dk = 1 - 0.22 * pfs;
                r *= dk; g *= dk; b *= dk;
            }
            const o = (y * W + x) * 4;
            D[o]     = r < 0 ? 0 : (r > 255 ? 255 : r);
            D[o + 1] = g < 0 ? 0 : (g > 255 ? 255 : g);
            D[o + 2] = b < 0 ? 0 : (b > 255 ? 255 : b);
            D[o + 3] = 255;
        }
    }
    ctx.putImageData(img, 0, 0);

    /* ============ 第 2 层：矢量覆层（全部三重补画保证左右无缝） ============ */
    const latToY = (deg) => (0.5 - deg / 180) * H;
    const wrap3 = (cx, fn) => { fn(cx - W); fn(cx); fn(cx + W); };
    const ell = (x, y, rx, ry, rot, fill, alpha) => {
        ctx.globalAlpha = alpha; ctx.fillStyle = fill;
        ctx.beginPath(); ctx.ellipse(x, y, rx, ry, rot, 0, TAU); ctx.fill();
        ctx.globalAlpha = 1;
    };

    // —— 带界涡纹：亮/暗交替小椭圆串（NEB/SEB/STB/NTB 南北缘）——
    const EDGES = [
        { phi: 28.5, dark: '#8a5a3a', light: '#f0e3c6' },
        { phi: 17.2, dark: '#7e5136', light: '#f2e6ca' },
        { phi: -9.5, dark: '#84512f', light: '#eee0c2' },
        { phi: -20.8, dark: '#93572f', light: '#f0e2c4' },
        { phi: -31.5, dark: '#8a6a48', light: '#e9dcbe' },
        { phi: 36.0, dark: '#8a6244', light: '#e8dabc' },
    ];
    for (const e of EDGES) {
        let flip = 0;
        for (let cx = 10; cx < W; cx += 20 + rand() * 16) {
            flip ^= 1;
            const y = latToY(e.phi) + (rand() - 0.5) * 5;
            const rx = 9 + rand() * 14, ry = 2.6 + rand() * 2.6;
            wrap3(cx, (x) => {
                ell(x, y, rx, ry, (rand() - 0.5) * 0.3, flip ? e.light : e.dark,
                    0.16 + rand() * 0.16);
            });
        }
    }

    // —— NEB 南缘花絮(festoon)：蓝灰楔形垂入赤道亮区 + 旁侧亮羽流 ——
    for (let i = 0; i < 7; i++) {
        const cx = 40 + i * 138 + rand() * 60;
        const yTop = latToY(15.5);
        const yBot = yTop + 14 + rand() * 12;
        wrap3(cx, (x) => {
            ctx.globalAlpha = 0.42 + rand() * 0.15;
            ctx.fillStyle = '#6b5646';
            ctx.beginPath();
            ctx.moveTo(x - 16, yTop + 2);
            ctx.quadraticCurveTo(x - 4, yBot, x + 10 + rand() * 8, yBot - 4 - rand() * 6);
            ctx.quadraticCurveTo(x + 6, yTop + 6, x - 16, yTop + 2);
            ctx.fill();
            ctx.globalAlpha = 0.35;
            ctx.fillStyle = '#f2e8d0';
            ctx.beginPath();
            ctx.ellipse(x + 20, yTop + 6, 12, 3.2, 0.12, 0, TAU);
            ctx.fill();
            ctx.globalAlpha = 1;
        });
    }

    // —— 南温带白椭圆涡链（类 BA 白斑）——
    for (const ox of [150, 470, 705]) {
        wrap3(ox, (x) => {
            ell(x, latToY(-33.5), 11, 4.6, -0.06, '#e8dabb', 0.9);
            ctx.strokeStyle = 'rgba(138,110,80,0.55)'; ctx.lineWidth = 1.2;
            ctx.beginPath();
            ctx.ellipse(x, latToY(-33.5), 11, 4.6, -0.06, 0, TAU);
            ctx.stroke();
        });
    }

    // —— 随机小风暴核：亮胞 + 暗点 ——
    for (let i = 0; i < 14; i++) {
        const phi = rand() < 0.5 ? 17 + rand() * 14 : -8 - rand() * 26;
        const cx = rand() * W, y = latToY(phi);
        const bright = rand() < 0.6;
        wrap3(cx, (x) => {
            if (bright) ell(x, y, 2.5 + rand() * 3, 1.6 + rand() * 1.6, 0, '#f4ecd8', 0.75);
            else        ell(x, y, 2.0 + rand() * 2.5, 1.4 + rand() * 1.2, 0, '#7a5038', 0.45);
        });
    }

    // —— 大红斑（GRS，约南纬 21.5°）：领圈 + 同心椭圆 + 螺旋弧 + 西侧尾流 ——
    const gx = 300, gy = latToY(-21.5);
    wrap3(gx, (x0) => {
        ctx.save();
        ctx.translate(x0, gy); ctx.scale(1, 0.42);          // 奶油色领圈（柔边环）
        const col = ctx.createRadialGradient(0, 0, 30, 0, 0, 68);
        col.addColorStop(0.50, 'rgba(240,230,206,0)');
        col.addColorStop(0.70, 'rgba(240,230,206,0.85)');
        col.addColorStop(0.88, 'rgba(240,230,206,0.55)');
        col.addColorStop(1.00, 'rgba(240,230,206,0)');
        ctx.fillStyle = col;
        ctx.beginPath(); ctx.arc(0, 0, 68, 0, TAU); ctx.fill();
        ctx.restore();
        // 同心椭圆：外缘砖红 → 核心浅鲑
        ell(x0, gy, 50, 20.0, 0, '#a1482e', 0.96);
        ell(x0, gy, 44, 17.0, 0, '#b85436', 1.0);
        ell(x0, gy, 35, 13.5, 0, '#c97048', 1.0);
        ell(x0, gy, 25, 9.5, 0, '#d99070', 1.0);
        ell(x0, gy, 14, 5.6, 0, '#e6b39a', 1.0);
        // 内部螺旋弧：错位椭圆弧线模拟环流
        ctx.strokeStyle = 'rgba(122,52,34,0.5)'; ctx.lineWidth = 2.4;
        for (let a = 0; a < 3; a++) {
            ctx.beginPath();
            ctx.ellipse(x0, gy, 19 + a * 10, 7.6 + a * 4.0, 0.15 + a * 0.5,
                a * 1.1, a * 1.1 + 3.6);
            ctx.stroke();
        }
        // 外缘暗圈
        ctx.strokeStyle = 'rgba(66,28,18,0.65)'; ctx.lineWidth = 2.2;
        ctx.beginPath(); ctx.ellipse(x0, gy, 50, 20, 0, 0, TAU); ctx.stroke();
        // 西侧尾流涡列（亮/暗交替的弧线段）
        for (let i = 0; i < 6; i++) {
            const wx = x0 - 64 - i * 24, wy = gy + Math.sin(i * 1.7) * 7;
            ctx.strokeStyle = i % 2 ? 'rgba(240,230,205,0.4)' : 'rgba(120,78,52,0.35)';
            ctx.lineWidth = 2.6 + rand() * 1.6;
            ctx.beginPath();
            ctx.arc(wx, wy, 5 + (i % 3) * 3.2, 0.4 + rand() * 0.6, 3.2 + rand() * 0.8);
            ctx.stroke();
        }
    });

    /* ============ 第 3 层：全图细颗粒（统一质感收尾） ============ */
    const fin = ctx.getImageData(0, 0, W, H);
    const F = fin.data;
    for (let i = 0; i < F.length; i += 4) {
        const j = (rand() - 0.5) * 6;
        F[i] += j; F[i + 1] += j; F[i + 2] += j;
    }
    ctx.putImageData(fin, 0, 0);

    const map = new THREE.CanvasTexture(canvas);
    map.colorSpace = THREE.SRGBColorSpace;
    return { map };
}
