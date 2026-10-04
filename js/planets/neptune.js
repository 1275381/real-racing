import * as THREE from 'three';

// 海王星：深蓝甲烷色调 + 大暗斑(GDS-89)风暴 + 白色卷云条
// 512×256 等距圆柱投影（契约允许海王星 512×256），x 方向噪声取整周期保证经度 0/360 无缝。
// 气巨契约不要求 bumpMap；cloudMap 仅限地球/金星，白色卷云直接画进主贴图。

export function build() {
    const W = 512, H = 256;
    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d');

    // 确定性伪随机（build 内局部状态，重复调用返回全新独立纹理）
    let rs = 20261004;
    const rnd = () => {
        rs = (Math.imul(rs, 1664525) + 1013904223) >>> 0;
        return rs / 4294967296;
    };

    // —— 周期性 value noise：u 方向按 pu 取模环绕，天然无缝 ——
    function hash2(ix, iy, seed) {
        let h = Math.imul(ix, 374761393) + Math.imul(iy, 668265263) + Math.imul(seed, 1442695041);
        h = Math.imul(h ^ (h >>> 13), 1274126177);
        h ^= h >>> 16;
        return (h >>> 0) / 4294967296;
    }
    function vnoise(u, v, pu, seed) {
        const iu = Math.floor(u), iv = Math.floor(v);
        const fu = u - iu, fv = v - iv;
        const su = fu * fu * (3 - 2 * fu), sv = fv * fv * (3 - 2 * fv);
        const w = (i) => ((i % pu) + pu) % pu;      // 经度环绕
        const a = hash2(w(iu), iv, seed), b = hash2(w(iu + 1), iv, seed);
        const c = hash2(w(iu), iv + 1, seed), e = hash2(w(iu + 1), iv + 1, seed);
        return a + (b - a) * su + (c - a) * sv + (a - b - c + e) * su * sv;
    }
    function fbm(u, v, pu, seed) {
        let s = 0, amp = 0.5, f = 1, tot = 0;
        for (let o = 0; o < 4; o++) {
            s += vnoise(u * f, v * f, pu * f, seed + o * 101) * amp;
            tot += amp;
            amp *= 0.5;
            f *= 2;
        }
        return s / tot;                              // 0..1
    }

    // —— 逐像素主体：纬向深蓝色带 + 甲烷斑驳 + 大暗斑 ——
    const img = ctx.getImageData(0, 0, W, H);
    const d = img.data;
    const PU = 6;                                    // 噪声 x 基频单元格数（整周期）
    const C1 = [22, 42, 118];                        // 暗谷：深靛蓝
    const C2 = [45, 82, 182];                        // 中带：海王星主蓝
    const C3 = [94, 136, 230];                       // 亮脊：浅甲烷蓝
    const GDS_X = 296, GDS_Y = 172, RX = 62, RY = 25; // 大暗斑：约南纬 30°
    for (let y = 0; y < H; y++) {
        const lat = (0.5 - y / H) * Math.PI;         // +π/2 北极 .. -π/2 南极
        const vv = y / H * 10;
        const pole = 1 - 0.16 * Math.pow(Math.abs(Math.sin(lat)), 3); // 极区微暗
        for (let x = 0; x < W; x++) {
            const u = x / W * PU;
            const flow = fbm(u, vv * 0.6, PU, 11);   // 大尺度流动（扭曲色带）
            const det = fbm(u, vv * 2.2, PU, 77);    // 细节斑驳
            const phase = lat * 6.5 + (flow - 0.5) * 2.4 + (det - 0.5) * 0.7;
            const band = 0.5 + 0.5 * Math.sin(phase);
            let r, g, b;
            if (band < 0.5) {
                const t = band * 2;
                r = C1[0] + (C2[0] - C1[0]) * t;
                g = C1[1] + (C2[1] - C1[1]) * t;
                b = C1[2] + (C2[2] - C1[2]) * t;
            } else {
                const t = (band - 0.5) * 2;
                r = C2[0] + (C3[0] - C2[0]) * t;
                g = C2[1] + (C3[1] - C2[1]) * t;
                b = C2[2] + (C3[2] - C2[2]) * t;
            }
            const m = 1 + (det - 0.5) * 0.2 + (flow - 0.5) * 0.1;
            r *= m; g *= m; b *= m;

            // 大暗斑：环绕 dx 的椭圆核 + 内部螺旋纹 + 南缘亮环
            let dx = x - GDS_X;
            if (dx > W / 2) dx -= W; else if (dx < -W / 2) dx += W;
            const ey = (y - GDS_Y) / RY, ex = dx / RX;
            const e2 = ex * ex + ey * ey;
            if (e2 < 1.5) {
                const s = Math.max(0, 1 - e2);
                const rad = Math.sqrt(e2), ang = Math.atan2(ey, ex);
                const sw = 0.5 + 0.5 * Math.sin(ang * 3 + rad * 9 - 0.8);
                const k = Math.pow(s, 0.7) * (0.62 + 0.22 * sw);
                r += (10 - r) * k; g += (22 - g) * k; b += (82 - b) * k;
                const ring = Math.exp(-Math.pow(e2 - 0.82, 2) / 0.018) * 0.3;
                r += (140 - r) * ring; g += (165 - g) * ring; b += (235 - b) * ring;
            }

            r *= pole; g *= pole; b *= pole;
            const gr = (hash2(x, y, 999) - 0.5) * 7; // 细颗粒质感
            const i = (y * W + x) * 4;
            d[i] = Math.max(0, Math.min(255, r + gr));
            d[i + 1] = Math.max(0, Math.min(255, g + gr));
            d[i + 2] = Math.max(0, Math.min(255, b + gr));
            d[i + 3] = 255;
        }
    }
    ctx.putImageData(img, 0, 0);

    // —— 矢量细节层：白色卷云条（screen 提亮）——
    function streak(x, y, len, wid, ang, alpha, dark) {
        const col = dark ? '16,28,90' : '238,245,255';
        for (const ox of [-W, 0, W]) {               // 超边元素环绕补画，保证无缝
            ctx.save();
            ctx.translate(x + ox, y);
            ctx.rotate(ang);
            ctx.scale(len, wid);
            const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
            g.addColorStop(0, `rgba(${col},${alpha})`);
            g.addColorStop(0.6, `rgba(${col},${alpha * 0.45})`);
            g.addColorStop(1, `rgba(${col},0)`);
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(0, 0, 1, 0, Math.PI * 2);
            ctx.fill();
            ctx.restore();
        }
    }

    ctx.globalCompositeOperation = 'screen';
    // 大暗斑伴云（Voyager 2 实况：暗斑附近的高空亮甲烷云，被风剪切拉长）
    streak(GDS_X + 30, GDS_Y - 22, 46, 5, -0.1, 0.75);
    streak(GDS_X + 62, GDS_Y - 14, 34, 4, 0.06, 0.6);
    streak(GDS_X - 20, GDS_Y + 26, 52, 4.5, 0.12, 0.5);
    streak(GDS_X + 8, GDS_Y + 34, 40, 3.5, -0.05, 0.45);
    // 「滑板车」：南纬 ~42° 的小快亮云
    streak(128, 192, 14, 5, 0, 0.9);
    streak(139, 193, 8, 3, 0, 0.7);
    // 北纬 28° 亮带内的稀疏长卷云
    streak(150, 88, 70, 3.5, -0.04, 0.32);
    streak(300, 92, 55, 3, 0.05, 0.26);
    streak(60, 84, 45, 2.5, 0, 0.22);
    // 赤道与南半球散布卷云
    streak(400, 117, 40, 2.5, -0.06, 0.2);
    streak(230, 196, 48, 3, 0.08, 0.3);
    streak(470, 150, 36, 2.5, -0.03, 0.18);
    // 随机细碎卷云补层次
    for (let i = 0; i < 14; i++) {
        streak(rnd() * W, 30 + rnd() * (H - 60), 12 + rnd() * 30,
            1.5 + rnd() * 2.5, (rnd() - 0.5) * 0.24, 0.1 + rnd() * 0.22);
    }

    // 暗色湍流丝缕 + 北半球次级暗斑（DS2），普通合成压暗
    ctx.globalCompositeOperation = 'source-over';
    streak(GDS_X - 30, GDS_Y + 20, 40, 3, 0.15, 0.35, true);
    streak(GDS_X + 40, GDS_Y + 18, 30, 2.5, -0.1, 0.3, true);
    streak(340, 70, 22, 8, 0, 0.28, true);
    streak(352, 74, 12, 5, 0.1, 0.22, true);

    const map = new THREE.CanvasTexture(canvas);
    map.colorSpace = THREE.SRGBColorSpace;           // 采样参数由 galaxy.js 统一设置
    return { map };
}
