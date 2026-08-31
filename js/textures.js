import * as THREE from 'three';

// 全部纹理均由 Canvas 程序生成，无需外部资源

function canvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return [c, c.getContext('2d')];
}

function toTex(c, repeatX = 1, repeatY = 1, srgb = true) {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(repeatX, repeatY);
    t.anisotropy = 8;
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    return t;
}

// 沥青路面：深灰底噪 + 白色边线 + 中央虚线（v 方向沿赛道前进）
export function asphaltTexture(maxAniso = 8) {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#33353a';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 9000; i++) {
        const v = 30 + Math.random() * 46;
        g.fillStyle = `rgba(${v},${v},${v + 4},${0.35 + Math.random() * 0.4})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.6, 1.6);
    }
    // 轻微车辙磨亮痕迹（两条略亮的纵向带）
    const grad = g.createLinearGradient(0, 0, S, 0);
    grad.addColorStop(0.20, 'rgba(255,255,255,0)');
    grad.addColorStop(0.32, 'rgba(210,210,215,0.055)');
    grad.addColorStop(0.45, 'rgba(255,255,255,0)');
    grad.addColorStop(0.60, 'rgba(255,255,255,0)');
    grad.addColorStop(0.72, 'rgba(210,210,215,0.055)');
    grad.addColorStop(0.84, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);

    // 左右白实线（u≈0.04 与 0.96）
    g.fillStyle = 'rgba(235,235,238,0.85)';
    g.fillRect(S * 0.035, 0, S * 0.018, S);
    g.fillRect(S * 0.947, 0, S * 0.018, S);
    // 中央白虚线（本格内画两段）
    g.fillStyle = 'rgba(240,240,242,0.9)';
    g.fillRect(S * 0.4915, 0, S * 0.017, S * 0.33);
    g.fillRect(S * 0.4915, S * 0.5, S * 0.017, S * 0.33);

    const t = toTex(c);
    t.anisotropy = maxAniso;
    return t;
}

export function grassTexture(maxAniso = 8) {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#4a7c37';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 12000; i++) {
        const shade = Math.random();
        g.fillStyle = `rgba(${40 + shade * 40 | 0},${95 + shade * 55 | 0},${30 + shade * 30 | 0},0.5)`;
        g.fillRect(Math.random() * S, Math.random() * S, 2.2, 2.2);
    }
    // 大块明暗补丁
    for (let i = 0; i < 26; i++) {
        g.fillStyle = `rgba(${30 + Math.random() * 36 | 0},${80 + Math.random() * 44 | 0},${26 + Math.random() * 24 | 0},0.16)`;
        g.beginPath();
        g.arc(Math.random() * S, Math.random() * S, 30 + Math.random() * 70, 0, 7);
        g.fill();
    }
    const t = toTex(c, 160, 160);
    t.anisotropy = maxAniso;
    return t;
}

// 城市水泥地面（伸缩缝网格）
export function concreteTexture(maxAniso = 8) {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#8d9194';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 9000; i++) {
        const v = 120 + Math.random() * 40;
        g.fillStyle = `rgba(${v},${v},${v + 3},${0.25 + Math.random() * 0.3})`;
        g.fillRect(Math.random() * S, Math.random() * S, 2, 2);
    }
    // 深色污渍斑
    for (let i = 0; i < 18; i++) {
        g.fillStyle = `rgba(70,72,76,${0.08 + Math.random() * 0.12})`;
        g.beginPath();
        g.arc(Math.random() * S, Math.random() * S, 20 + Math.random() * 60, 0, 7);
        g.fill();
    }
    // 伸缩缝
    g.strokeStyle = 'rgba(60,62,66,0.85)';
    g.lineWidth = 4;
    g.strokeRect(0, 0, S, S);
    g.beginPath(); g.moveTo(S / 2, 0); g.lineTo(S / 2, S); g.stroke();
    const t = toTex(c, 150, 150);
    t.anisotropy = maxAniso;
    return t;
}

// 沙漠沙地（风纹）
export function sandTexture(maxAniso = 8) {
    const S = 512;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#d9b677';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 11000; i++) {
        const v = Math.random();
        g.fillStyle = `rgba(${185 + v * 50 | 0},${145 + v * 45 | 0},${85 + v * 35 | 0},0.5)`;
        g.fillRect(Math.random() * S, Math.random() * S, 2.4, 1.6);
    }
    // 风纹波
    g.strokeStyle = 'rgba(160,125,70,0.25)';
    for (let y = 0; y < S; y += 22) {
        g.lineWidth = 5 + Math.random() * 4;
        g.beginPath();
        for (let x = 0; x <= S; x += 16) {
            const yy = y + Math.sin(x * 0.03 + y) * 7;
            x === 0 ? g.moveTo(x, yy) : g.lineTo(x, yy);
        }
        g.stroke();
    }
    const t = toTex(c, 140, 140);
    t.anisotropy = maxAniso;
    return t;
}

// 城市建筑立面（窗格）
export function buildingTexture() {
    const S = 256;
    const [c, g] = canvas(S, S);
    g.fillStyle = '#6e747c';
    g.fillRect(0, 0, S, S);
    const cols = 6, rows = 8;
    const cw = S / cols, rh = S / rows;
    for (let y = 0; y < rows; y++) {
        for (let x = 0; x < cols; x++) {
            const lit = Math.random();
            g.fillStyle = lit < 0.12 ? '#dfe9ee' : lit < 0.5 ? '#2c3540' : '#39434f';
            g.fillRect(x * cw + 5, y * rh + 6, cw - 10, rh - 12);
        }
    }
    // 楼层分隔线
    g.fillStyle = 'rgba(40,44,50,0.5)';
    for (let y = 0; y < rows; y++) g.fillRect(0, y * rh + rh - 4, S, 4);
    return toTex(c, 1, 1);
}

// 车底软阴影贴图
export function blobShadowTexture() {
    const S = 128;
    const [c, g] = canvas(S, S);
    const grad = g.createRadialGradient(S / 2, S / 2, 6, S / 2, S / 2, S / 2);
    grad.addColorStop(0, 'rgba(0,0,0,0.62)');
    grad.addColorStop(0.55, 'rgba(0,0,0,0.42)');
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
    return toTex(c, 1, 1);
}

// 起跑线黑白格
export function checkerTexture(cols = 10, rows = 2) {
    const cell = 32;
    const [c, g] = canvas(cols * cell, rows * cell);
    for (let y = 0; y < rows; y++) {
        for (let x = 0; x < cols; x++) {
            g.fillStyle = (x + y) % 2 ? '#151515' : '#efefef';
            g.fillRect(x * cell, y * cell, cell, cell);
        }
    }
    return toTex(c);
}

// 龙门横幅文字
export function bannerTexture(text) {
    const [c, g] = canvas(1024, 192);
    g.fillStyle = '#10141f';
    g.fillRect(0, 0, 1024, 192);
    g.strokeStyle = '#ff7a1a'; g.lineWidth = 10;
    g.strokeRect(14, 14, 996, 164);
    g.font = 'bold 110px "PingFang SC", "Microsoft YaHei", sans-serif';
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillStyle = '#ffffff';
    g.fillText(text, 512, 104);
    return toTex(c);
}

// 看台“观众”——随机彩色像素点阵
export function crowdTexture() {
    const W = 512, H = 256;
    const [c, g] = canvas(W, H);
    g.fillStyle = '#1c2026';
    g.fillRect(0, 0, W, H);
    const palette = ['#e8534a', '#f2a13b', '#f5e663', '#69c56a', '#57a7e8', '#9d76e0', '#eeeeee', '#e07a9a'];
    // 一排排观众
    for (let row = 0; row < 16; row++) {
        const y = 14 + row * 15;
        for (let x = 4; x < W - 4; x += 9) {
            if (Math.random() < 0.08) continue; // 空座
            g.fillStyle = palette[(Math.random() * palette.length) | 0];
            g.beginPath();
            g.arc(x + Math.random() * 3, y + Math.random() * 4, 3.4, 0, 7);
            g.fill();
            // 身体
            g.fillRect(x + Math.random() * 3 - 3, y + 4, 6.5, 6);
        }
    }
    return toTex(c, 3, 1);
}

// 用于 PMREM 环境反射的渐变天空盒材质（同时用作背景天空）
export function skyMaterial() {
    return new THREE.ShaderMaterial({
        side: THREE.BackSide,
        depthWrite: false,
        fog: false,
        uniforms: {
            topColor: { value: new THREE.Color(0x2f63b8) },
            midColor: { value: new THREE.Color(0x86aede) },
            botColor: { value: new THREE.Color(0xdfe9ee) },
            sunDir: { value: new THREE.Vector3(0.52, 0.42, 0.74).normalize() },
            sunColor: { value: new THREE.Color(0xfff1d6) },
        },
        vertexShader: `
            varying vec3 vDir;
            void main() {
                vDir = normalize(position);
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }`,
        fragmentShader: `
            uniform vec3 topColor, midColor, botColor, sunColor, sunDir;
            varying vec3 vDir;
            void main() {
                float h = clamp(vDir.y, -1.0, 1.0);
                vec3 col = h > 0.12
                    ? mix(midColor, topColor, pow((h - 0.12) / 0.88, 0.72))
                    : mix(botColor, midColor, clamp((h + 0.06) / 0.18, 0.0, 1.0));
                float sd = max(dot(normalize(vDir), normalize(sunDir)), 0.0);
                col += sunColor * (pow(sd, 900.0) * 1.15 + pow(sd, 26.0) * 0.16);
                gl_FragColor = vec4(col, 1.0);
                #include <colorspace_fragment>
            }`,
    });
}
