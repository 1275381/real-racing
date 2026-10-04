import * as THREE from 'three';

//
// 天王星（Uranus）—— 冰巨星
// 视觉基调：均匀淡青色，极淡纬向条纹，宁静无扰。
// 512×256 等距圆柱投影：x = 经度 0°→360°（左右边缘无缝衔接），y = 北极→南极。
// 层次：纬度基色渐变 → 大尺度极淡云雾斑块（环绕补画）→ 逐行纬向条纹
//       （行内恒色，经度方向天然无缝）→ 横向缕状薄雾（环绕补画）→ ±2 灰阶细颗粒。
//

export function build() {
    const W = 512;
    const H = 256;

    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d');

    // ---- 1. 纬度基色：两极微亮偏白，赤道略深青 ------------------------------
    const base = ctx.createLinearGradient(0, 0, 0, H);
    base.addColorStop(0.00, '#b4e3ec');
    base.addColorStop(0.16, '#a6dce5');
    base.addColorStop(0.50, '#98d2dc');
    base.addColorStop(0.84, '#a7dde6');
    base.addColorStop(1.00, '#b5e4ed');
    ctx.fillStyle = base;
    ctx.fillRect(0, 0, W, H);

    // ---- 2. 大尺度极淡云雾斑块（左右超边各补画一份，保证经度缝连续） --------
    for (let i = 0; i < 16; i++) {
        const cx = Math.random() * W;
        const cy = Math.random() * H;
        const r = 50 + Math.random() * 90;
        const light = Math.random() < 0.55;
        const a = 0.015 + Math.random() * 0.02;
        for (const dx of [-W, 0, W]) {
            const g = ctx.createRadialGradient(cx + dx, cy, 0, cx + dx, cy, r);
            if (light) {
                g.addColorStop(0, `rgba(215, 245, 250, ${a})`);
                g.addColorStop(1, 'rgba(215, 245, 250, 0)');
            } else {
                g.addColorStop(0, `rgba(95, 145, 165, ${a})`);
                g.addColorStop(1, 'rgba(95, 145, 165, 0)');
            }
            ctx.fillStyle = g;
            ctx.fillRect(cx + dx - r, cy - r, r * 2, r * 2);
        }
    }

    // ---- 3. 纬向条纹：多频微幅亮暗 + 极区「极帽领口」亮带 -------------------
    // 逐行叠加、行内颜色恒定 ⇒ 经度无缝；幅度 ≤0.055 alpha，保持宁静观感。
    for (let y = 0; y < H; y++) {
        const lat = (y / (H - 1)) * Math.PI;        // 0=北极 π=南极
        let d = 1.6 * Math.sin(lat * 7.0 + 0.9)
              + 1.0 * Math.sin(lat * 13.0 + 2.2)
              + 0.6 * Math.sin(lat * 21.0 + 4.6);
        // ±60° 纬度各一道极淡亮带（天王星影像中标志性的极帽领口）
        d += 1.5 * Math.exp(-Math.pow((lat - Math.PI / 3) / 0.09, 2))
           + 1.5 * Math.exp(-Math.pow((lat - (2 * Math.PI) / 3) / 0.09, 2));
        const v = Math.max(-3, Math.min(3, d));
        ctx.fillStyle = v > 0
            ? `rgba(222, 246, 251, ${(v / 3) * 0.055})`
            : `rgba(80, 130, 152, ${(-v / 3) * 0.055})`;
        ctx.fillRect(0, y, W, 1);
    }

    // ---- 4. 横向缕状薄雾（细长椭圆随纬向气流拉长，环绕补画） ----------------
    for (let i = 0; i < 110; i++) {
        const x = Math.random() * W;
        const y = 8 + Math.random() * (H - 16);
        const w = 26 + Math.random() * 80;
        const h = 1.5 + Math.random() * 3.5;
        const light = Math.random() < 0.5;
        ctx.fillStyle = light
            ? `rgba(228, 248, 252, ${0.02 + Math.random() * 0.04})`
            : `rgba(88, 138, 158, ${0.02 + Math.random() * 0.035})`;
        for (const dx of [-W, 0, W]) {
            ctx.beginPath();
            ctx.ellipse(x + dx, y, w / 2, h / 2, 0, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    // ---- 5. 细颗粒噪点：±2 灰阶，打破数字平涂感 ----------------------------
    const img = ctx.getImageData(0, 0, W, H);
    const px = img.data;
    for (let i = 0; i < px.length; i += 4) {
        const n = (Math.random() - 0.5) * 4;
        px[i] = Math.min(255, Math.max(0, px[i] + n));
        px[i + 1] = Math.min(255, Math.max(0, px[i + 1] + n));
        px[i + 2] = Math.min(255, Math.max(0, px[i + 2] + n));
    }
    ctx.putImageData(img, 0, 0);

    // ---- 输出：冰巨星不提供 bumpMap；wrapS/wrapT、anisotropy 由集成方统一定 --
    const map = new THREE.CanvasTexture(canvas);
    map.colorSpace = THREE.SRGBColorSpace;
    return { map };
}
