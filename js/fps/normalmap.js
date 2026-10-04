import * as THREE from 'three';

/* =====================================================================
   js/fps/normalmap.js —— 切线空间法线贴图工具（写实度评审 #4）
   全部 Canvas 程序化（零外部资源）：① 把已有 albedo 画布按亮度当高度场
   求差分法线（枪金属磨砂受益最大）；② 程序化高度场生成器（席纹编织 /
   斑点灰泥 / 木纹拉丝），供 GLB 材质补法线（沙袋/墙/集装箱无烘焙法线）。
   周期性：数学高度场天然周期；斑点用九向跨边补章，法线 wrap 采样无缝。
   ===================================================================== */

/* ==== 1. 亮度 → 高度 → 差分法线（要求 2 的幂尺寸，wrap 寻址） ==== */
export function normalFromCanvas(src, strength = 1) {
    const S = src.width;
    const d = src.getContext('2d').getImageData(0, 0, S, S).data;
    const lum = new Float32Array(S * S);
    for (let i = 0; i < S * S; i++) {
        const j = i * 4;
        lum[i] = (d[j] * 0.299 + d[j + 1] * 0.587 + d[j + 2] * 0.114) / 255;
    }
    const out = document.createElement('canvas');
    out.width = out.height = S;
    const oc = out.getContext('2d');
    const img = oc.createImageData(S, S);
    const at = (x, y) => lum[(y & (S - 1)) * S + (x & (S - 1))];
    for (let y = 0; y < S; y++) {
        for (let x = 0; x < S; x++) {
            const dx = (at(x + 1, y) - at(x - 1, y)) * strength;
            const dy = (at(x, y + 1) - at(x, y - 1)) * strength;
            const inv = 1 / Math.sqrt(dx * dx + dy * dy + 1);
            const i = (y * S + x) * 4;
            img.data[i] = (-dx * inv * 0.5 + 0.5) * 255;
            img.data[i + 1] = (-dy * inv * 0.5 + 0.5) * 255;
            img.data[i + 2] = (inv * 0.5 + 0.5) * 255;
            img.data[i + 3] = 255;
        }
    }
    oc.putImageData(img, 0, 0);
    return out;
}

/* 法线画布 → 纹理（必须线性色域：不设 SRGBColorSpace），可平铺 repeat */
export function toNormalTexture(c, repeat = 1) {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(repeat, repeat);
    t.anisotropy = 4;
    return t;
}

/* ==== 2. 程序化高度场 ==== */

/* 席纹编织（沙袋麻布 / 帐篷帆布 / 军装布料）：经纬纱上下交错 + 纱线圆拱 + 纤维噪 */
export function weaveHeight(S = 256, cell = 16, fiber = 0.14) {
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const g = c.getContext('2d');
    const img = g.createImageData(S, S);
    for (let y = 0; y < S; y++) {
        for (let x = 0; x < S; x++) {
            const over = (Math.floor(x / cell) + Math.floor(y / cell)) % 2 === 0;
            const fx = (x % cell) / cell, fy = (y % cell) / cell;
            const arch = over ? Math.sin(fy * Math.PI) : Math.sin(fx * Math.PI);
            const n = (Math.random() - 0.5) * fiber;
            const h = 0.5 + arch * 0.34 + n;
            const i = (y * S + x) * 4;
            const v = Math.max(0, Math.min(255, h * 255)) | 0;
            img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
            img.data[i + 3] = 255;
        }
    }
    g.putImageData(img, 0, 0);
    return c;
}

/* 斑点凹凸（灰泥/混凝土/漆面锈迹/岩石）：随机圆斑明暗堆叠，九向跨边补章保周期 */
export function speckleHeight(S = 256, blobR = 2.4, count = 1100) {
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const g = c.getContext('2d');
    g.fillStyle = '#808080';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < count; i++) {
        const x = Math.random() * S, y = Math.random() * S;
        const r = blobR * (0.5 + Math.random() * 1.6);
        const light = Math.random() < 0.5;
        g.fillStyle = light
            ? `rgba(255,255,255,${0.10 + Math.random() * 0.16})`
            : `rgba(0,0,0,${0.10 + Math.random() * 0.16})`;
        for (const ox of [-S, 0, S]) {
            for (const oy of [-S, 0, S]) {
                g.beginPath();
                g.arc(x + ox, y + oy, r, 0, 7);
                g.fill();
            }
        }
    }
    return c;
}

/* 木纹/拉丝（木板/树皮）：水平条纹正弦微扰 + 噪点，波长取 S 约数保周期 */
export function grainHeight(S = 256, streaks = 48, warpAmp = 3) {
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const g = c.getContext('2d');
    const img = g.createImageData(S, S);
    const period = S / Math.max(4, Math.round(S / 24));   // 每条纹宽 ~24px 且整除 S
    for (let y = 0; y < S; y++) {
        for (let x = 0; x < S; x++) {
            const warp = Math.sin((x / S) * Math.PI * 2 * streaks) * warpAmp;
            const band = Math.sin(((y + warp) / period) * Math.PI * 2) * 0.5 + 0.5;
            const n = (Math.random() - 0.5) * 0.10;
            const v = Math.max(0, Math.min(255, (0.5 + band * 0.42 + n) * 255)) | 0;
            const i = (y * S + x) * 4;
            img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
            img.data[i + 3] = 255;
        }
    }
    g.putImageData(img, 0, 0);
    return c;
}
