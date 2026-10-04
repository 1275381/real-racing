import * as THREE from 'three';

/* ==== 1. Canvas 工具（照 js/textures.js 先例：全部程序化生成，零外部资源） ==== */

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

/* ==== 2. 各部件贴图 ==== */

/* 机匣金属：枪灰底 + 磨砂颗粒 + 使用划痕 */
function metalAlbedo() {
    const S = 256;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#33363b';
    g.fillRect(0, 0, S, S);
    grain(g, S, 5200, 60, 105, 0.10, 1.4);
    scratches(g, S, 22, '#c2c8d0', 1.1, 0.10);
    scratches(g, S, 14, '#0c0e11', 0.9, 0.16);
    // 大块油污晕
    for (let i = 0; i < 5; i++) {
        const r = 26 + Math.random() * 54;
        const rg = g.createRadialGradient(Math.random() * S, Math.random() * S, 0, Math.random() * S, Math.random() * S, r);
        rg.addColorStop(0, 'rgba(12,13,15,0.10)');
        rg.addColorStop(1, 'rgba(12,13,15,0)');
        g.fillStyle = rg;
        g.fillRect(0, 0, S, S);
    }
    return c;
}

/* 金属磨砂粗糙度：中高粗糙底 + 划痕处磨亮（低粗糙） */
function metalRough() {
    const S = 256;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#a6a6a6';       // ≈0.65 粗糙
    g.fillRect(0, 0, S, S);
    grain(g, S, 6000, 130, 200, 0.5, 1.6);
    scratches(g, S, 20, '#5f5f5f', 1.0, 0.35);   // 磨亮划痕
    scratches(g, S, 10, '#d8d8d8', 0.8, 0.25);   // 更毛糙的深痕
    return c;
}

/* 聚合物（护木/枪托/握把）：深灰底 + 防滑点纹 + 纤维微粒 */
function polymerAlbedo() {
    const S = 256;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#232528';
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
    grain(g, S, 2600, 70, 110, 0.08, 1.2);   // 纤维微粒微光
    scratches(g, S, 8, '#3d4046', 1.0, 0.12);
    return c;
}

function polymerRough() {
    const S = 256;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#c8c8c8';       // ≈0.78 粗糙，低反光
    g.fillRect(0, 0, S, S);
    grain(g, S, 5500, 160, 215, 0.5, 1.6);
    scratches(g, S, 10, '#9a9a9a', 1.0, 0.2);
    return c;
}

/* 枪管钢：深钢灰 + 车削纹理（横向细线） */
function steelAlbedo() {
    const S = 256;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#2b2e33';
    g.fillRect(0, 0, S, S);
    for (let y = 0; y < S; y += 2 + Math.random() * 2) {
        g.fillStyle = `rgba(${150 + Math.random() * 30 | 0},${155 + Math.random() * 30 | 0},${168 + Math.random() * 30 | 0},${0.05 + Math.random() * 0.06})`;
        g.fillRect(0, y, S, 1);
    }
    grain(g, S, 3200, 55, 95, 0.12, 1.3);
    scratches(g, S, 12, '#b8bec8', 0.9, 0.12);
    return c;
}

/* 黄铜弹壳：铜黄底 + 纵向拉丝 */
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

/* ==== 3. 单例材质包：gunMaterials() 返回六个 MeshStandardMaterial（缓存） ==== */

let _cache = null;

export function gunMaterials() {
    if (_cache) return _cache;
    const mA = toTex(metalAlbedo(), true);
    const mR = toTex(metalRough(), false);      // 粗糙度贴图保持线性
    const pA = toTex(polymerAlbedo(), true);
    const pR = toTex(polymerRough(), false);
    const sA = toTex(steelAlbedo(), true);
    const bA = toTex(brassAlbedo(), true);
    _cache = {
        // 机匣：深色铝合金 anodized，高金属度 + 磨砂
        receiverMat: new THREE.MeshStandardMaterial({
            map: mA, roughnessMap: mR, roughness: 1.0, metalness: 0.85
        }),
        // 枪管/消焰器：深钢，更高金属度
        barrelMat: new THREE.MeshStandardMaterial({
            map: sA, roughnessMap: mR, roughness: 1.0, metalness: 0.95
        }),
        // 聚合物：护木/枪托/握把，低反光
        polymerMat: new THREE.MeshStandardMaterial({
            map: pA, roughnessMap: pR, roughness: 1.0, metalness: 0.05
        }),
        // 弹匣：同聚合物贴图 + 橄榄色染色
        magMat: new THREE.MeshStandardMaterial({
            map: pA, roughnessMap: pR, roughness: 1.0, metalness: 0.05,
            color: 0xb8bfa6
        }),
        // 枪机/拉栓/小件：亮钢（无 albedo 贴图，纯色 + 粗糙度贴图）
        boltMat: new THREE.MeshStandardMaterial({
            color: 0x9aa1a9, roughnessMap: mR, roughness: 1.0, metalness: 1.0
        }),
        // 黄铜弹壳
        brassMat: new THREE.MeshStandardMaterial({
            map: bA, roughness: 0.32, metalness: 1.0
        }),
    };
    return _cache;
}
