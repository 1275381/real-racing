// 银河系全景 · 程序化银河 + 双视角控制
// 通过 galaxy.html 的 importmap 引入仓库本地 three（r160），零外部资源
import * as THREE from 'three';
// 八大行星高清程序贴图模块（契约见 out/solar-design.md §1，导出名统一为 build）
import { build as texMercury } from './planets/mercury.js';
import { build as texVenus }   from './planets/venus.js';
import { build as texEarth }   from './planets/earth.js';
import { build as texMars }    from './planets/mars.js';
import { build as texJupiter } from './planets/jupiter.js';
import { build as texSaturn }  from './planets/saturn.js';
import { build as texUranus }  from './planets/uranus.js';
import { build as texNeptune } from './planets/neptune.js';
const PLANET_TEX = {
    mercury: texMercury, venus: texVenus, earth: texEarth, mars: texMars,
    jupiter: texJupiter, saturn: texSaturn, uranus: texUranus, neptune: texNeptune,
};

/* ================= 1. 参数与 DOM ================= */
const params = {
    arms: 4,        // 旋臂数量
    starCount: 80000,
    spin: 1,        // 自转速度倍率
    brightness: 1,  // 整体亮度
    twinkle: true,  // 恒星闪烁
};
const $ = (id) => document.getElementById(id);
const veil = $('loadingVeil');
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

function gauss() { // Box-Muller 标准正态
    let u = 0, v = 0;
    while (!u) u = Math.random();
    while (!v) v = Math.random();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/* ================= 2. 渲染器 / 场景 / 相机 ================= */
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.setClearColor(0x020308, 1);
renderer.domElement.id = 'gl';
document.body.appendChild(renderer.domElement);
const canvas = renderer.domElement;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 4000);

/* ================= 3. 程序纹理 ================= */
function makeStarTexture() { // 柔和圆星点
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    const g = c.getContext('2d');
    const grad = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    grad.addColorStop(0, 'rgba(255,255,255,1)');
    grad.addColorStop(0.22, 'rgba(255,255,255,0.85)');
    grad.addColorStop(0.48, 'rgba(255,255,255,0.28)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 64, 64);
    return new THREE.CanvasTexture(c);
}
function makeGlowTexture() { // 银心辉光
    const c = document.createElement('canvas');
    c.width = c.height = 256;
    const g = c.getContext('2d');
    const grad = g.createRadialGradient(128, 128, 0, 128, 128, 128);
    grad.addColorStop(0, 'rgba(255,244,224,1)');
    grad.addColorStop(0.22, 'rgba(255,224,185,0.55)');
    grad.addColorStop(0.55, 'rgba(255,195,150,0.16)');
    grad.addColorStop(1, 'rgba(255,180,140,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 256, 256);
    return new THREE.CanvasTexture(c);
}
const starTex = makeStarTexture();
const glowTex = makeGlowTexture();

/* ================= 4. 银河着色器 =================
   差速自转在 GPU 完成：每星存初始角/柱半径/高度，
   顶点着色器按 ω ∝ 1/(r+c)（近似平坦旋转曲线）旋转。
   aSpd 为速度倍率（亮星中的太阳固定为 0，作相机锚点）。 */
const VERT = `
uniform float uTime;
uniform float uSpinSpeed;
uniform float uSize;
uniform float uPixelRatio;
uniform float uTwinkle;
attribute float aTheta;
attribute float aRadius;
attribute float aY;
attribute float aSize;
attribute float aPhase;
attribute float aSpd;
attribute vec3 aColor;
varying vec3 vColor;
varying float vTw;
void main() {
    float omega = uSpinSpeed * 1.7 / (aRadius * 0.55 + 9.0);
    float th = aTheta + uTime * omega * aSpd;
    vec3 p = vec3(cos(th) * aRadius, aY, sin(th) * aRadius);
    vec4 mv = modelViewMatrix * vec4(p, 1.0);
    gl_Position = projectionMatrix * mv;
    float tw = 1.0 + 0.42 * uTwinkle * sin(uTime * 2.6 + aPhase);
    float ps = aSize * uSize * uPixelRatio * tw * (250.0 / max(1.0, -mv.z));
    gl_PointSize = clamp(ps, 0.0, POINT_MAX * uPixelRatio);
    vColor = aColor;
    vTw = tw;
}`;
const FRAG = `
uniform sampler2D uMap;
uniform float uBrightness;
uniform float uFade;
varying vec3 vColor;
varying float vTw;
void main() {
    vec4 tex = texture2D(uMap, gl_PointCoord);
    if (tex.a < 0.02) discard;
    gl_FragColor = vec4(vColor * uBrightness * uFade * (0.8 + 0.2 * vTw), tex.a);
}`;
function makeGalaxyMaterial(pointMax) {
    const m = new THREE.ShaderMaterial({
        uniforms: {
            uTime: { value: 0 },
            uSpinSpeed: { value: params.spin },
            uSize: { value: 1 },
            uPixelRatio: { value: renderer.getPixelRatio() },
            uTwinkle: { value: params.twinkle ? 1 : 0 },
            uBrightness: { value: params.brightness },
            uFade: { value: 1 },
            uMap: { value: starTex },
        },
        vertexShader: VERT,
        fragmentShader: FRAG,
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        defines: { POINT_MAX: pointMax.toFixed(1) },
    });
    return m;
}
const galaxyMat = makeGalaxyMaterial(48); // 近距离光斑上限压低，避免贴脸恒星变巨块
const namedMat = makeGalaxyMaterial(26);
namedMat.uniforms.uSize.value = 1.2;
const spinMats = [galaxyMat, namedMat]; // 联动 uniform 用

/* 太阳系「真实夜空」分层淡入淡出：
   skyFade: 0 = 银河场景（近场银盘可见），1 = 太阳系场景（远近只剩夜空星点+银河暗带） */
let solarSky = null;
let skyFade = 0;
const skyFadeMats = [];    // 随 skyFade 淡入（夜空层）
const galaxyFadeMats = []; // 随 skyFade 淡出（银心辉光等银河层材质）

/* ================= 5. 银河构建 ================= */
const GALAXY_R = 100;
let galaxyPoints = null;

function buildGalaxy() {
    const count = params.starCount;
    // 颜色板：核心暖黄白 → 旋臂蓝白，点缀电离氢区/红巨星/蓝白亮星
    const cIn = new THREE.Color(0xffd9a8);
    const cMid = new THREE.Color(0xfff3dd);
    const cOut = new THREE.Color(0x7fa8ff);
    const cHII = new THREE.Color(0xff5f9e);
    const cRed = new THREE.Color(0xff8f6a);
    const cBlue = new THREE.Color(0x9db8ff);
    const tmp = new THREE.Color();

    const thetas = new Float32Array(count);
    const radii = new Float32Array(count);
    const ys = new Float32Array(count);
    const colors = new Float32Array(count * 3);
    const sizes = new Float32Array(count);
    const phases = new Float32Array(count);
    const spds = new Float32Array(count);
    const positions = new Float32Array(count * 3); // t=0 位置，仅用于包围球

    for (let i = 0; i < count; i++) {
        spds[i] = 1;
        phases[i] = Math.random() * Math.PI * 2;
        const dice = Math.random();
        let r, th, y, color, size;
        if (dice < 0.22) {
            // 核球：略扁的高斯球
            r = Math.abs(gauss()) * GALAXY_R * 0.12;
            th = Math.random() * Math.PI * 2;
            y = gauss() * GALAXY_R * 0.075;
            tmp.copy(cIn).lerp(cMid, Math.random() * 0.7);
            color = tmp; size = 0.55 + Math.random();
        } else if (dice < 0.30) {
            // 盘面弥散星（不属旋臂）
            r = (0.12 + 0.88 * Math.pow(Math.random(), 1.5)) * GALAXY_R;
            th = Math.random() * Math.PI * 2;
            y = gauss() * 2.6 * (1.1 - 0.5 * r / GALAXY_R);
            tmp.copy(cIn).lerp(cOut, Math.min(1, (r / GALAXY_R) * 1.15));
            color = tmp; size = 0.5 + Math.pow(Math.random(), 2) * 1.1;
        } else if (dice < 0.96) {
            // 旋臂：对数缠绕 + 随半径增大的角向离散
            const arm = i % params.arms;
            r = (0.12 + 0.88 * Math.pow(Math.random(), 1.35)) * GALAXY_R;
            const twist = Math.pow(r / GALAXY_R, 0.72) * 3.6;
            const scatter = gauss() * (0.10 + 0.15 * r / GALAXY_R);
            th = (arm / params.arms) * Math.PI * 2 + twist + scatter;
            y = gauss() * 3.4 * (1.15 - 0.55 * r / GALAXY_R) * (0.45 + 0.55 * Math.random());
            const d2 = Math.random();
            if (d2 < 0.015) { tmp.copy(cHII); size = 2.1 + Math.random() * 2.1; }
            else if (d2 < 0.03) { tmp.copy(cRed); size = 1.3 + Math.random() * 1.2; }
            else if (d2 < 0.075) { tmp.copy(cBlue); size = 1.15 + Math.random() * 1.35; }
            else {
                tmp.copy(cIn).lerp(cOut, Math.min(1, Math.max(0, (r / GALAXY_R) * 1.3 + gauss() * 0.08)));
                size = 0.55 + Math.pow(Math.random(), 2.2) * 1.5;
            }
            color = tmp;
        } else {
            // 内晕：稀疏球状包裹
            const u = Math.random() * 2 - 1;
            const ang = Math.random() * Math.PI * 2;
            const s = Math.sqrt(1 - u * u);
            const rr = GALAXY_R * (1.05 + Math.pow(Math.random(), 2.2) * 2.6);
            const x = s * Math.cos(ang) * rr, z = s * Math.sin(ang) * rr;
            th = Math.atan2(z, x);
            r = Math.hypot(x, z);
            y = u * rr * 0.85;
            tmp.copy(cMid).lerp(cOut, Math.random()).multiplyScalar(0.55);
            color = tmp; size = 0.45 + Math.random() * 0.8;
        }
        thetas[i] = th; radii[i] = r; ys[i] = y; sizes[i] = size;
        colors[i * 3] = color.r; colors[i * 3 + 1] = color.g; colors[i * 3 + 2] = color.b;
        positions[i * 3] = Math.cos(th) * r;
        positions[i * 3 + 1] = y;
        positions[i * 3 + 2] = Math.sin(th) * r;
    }

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geo.setAttribute('aTheta', new THREE.BufferAttribute(thetas, 1));
    geo.setAttribute('aRadius', new THREE.BufferAttribute(radii, 1));
    geo.setAttribute('aY', new THREE.BufferAttribute(ys, 1));
    geo.setAttribute('aColor', new THREE.BufferAttribute(colors, 3));
    geo.setAttribute('aSize', new THREE.BufferAttribute(sizes, 1));
    geo.setAttribute('aPhase', new THREE.BufferAttribute(phases, 1));
    geo.setAttribute('aSpd', new THREE.BufferAttribute(spds, 1));

    if (galaxyPoints) {
        galaxyPoints.geometry.dispose();
        galaxyPoints.geometry = geo;
    } else {
        galaxyPoints = new THREE.Points(geo, galaxyMat);
        galaxyPoints.frustumCulled = false; // 真实位置在着色器中计算，包围球不可信
        scene.add(galaxyPoints);
    }
}

function buildCoreGlow() {
    const mk = (scale, opacity) => {
        const mat = new THREE.SpriteMaterial({
            map: glowTex, transparent: true, opacity,
            blending: THREE.AdditiveBlending, depthWrite: false,
        });
        const sp = new THREE.Sprite(mat);
        sp.scale.setScalar(scale);
        scene.add(sp);
        galaxyFadeMats.push({ m: mat, base: opacity }); // 进太阳系时随银盘一起淡出
    };
    mk(150, 0.32); // 大范围暖雾
    mk(60, 0.85);  // 银心主体
    mk(24, 1);     // 极亮核
}

/* ---------- 背景远景星场 ---------- */
function buildBackground() {
    const mk = (n, rMin, rSpan, size, opacity) => {
        const pos = new Float32Array(n * 3);
        const col = new Float32Array(n * 3);
        const c = new THREE.Color();
        for (let i = 0; i < n; i++) {
            const u = Math.random() * 2 - 1;
            const ang = Math.random() * Math.PI * 2;
            const s = Math.sqrt(1 - u * u);
            const rr = rMin + Math.random() * rSpan;
            pos[i * 3] = s * Math.cos(ang) * rr;
            pos[i * 3 + 1] = u * rr;
            pos[i * 3 + 2] = s * Math.sin(ang) * rr;
            const d = Math.random();
            c.setHSL(d < 0.6 ? 0.62 : 0.09, 0.35 * Math.random(), 0.75 + Math.random() * 0.25);
            col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        g.setAttribute('color', new THREE.BufferAttribute(col, 3));
        const m = new THREE.PointsMaterial({
            size, map: starTex, transparent: true, opacity,
            vertexColors: true, sizeAttenuation: true,
            blending: THREE.AdditiveBlending, depthWrite: false,
        });
        scene.add(new THREE.Points(g, m));
    };
    mk(2400, 1150, 500, 3.2, 0.8);
    mk(140, 1000, 600, 6.5, 1); // 少量更亮的远景
}

/* ---------- 卫星星系（大小麦哲伦云） ---------- */
function buildSatellites() {
    const defs = [
        { pos: [-660, -160, 540], R: 55, n: 900 }, // 大麦哲伦云
        { pos: [-480, -300, 780], R: 32, n: 520 }, // 小麦哲伦云
    ];
    const cCore = new THREE.Color(0xffe9cf);
    const cEdge = new THREE.Color(0x9fb6ff);
    for (const d of defs) {
        const pos = new Float32Array(d.n * 3);
        const col = new Float32Array(d.n * 3);
        const c = new THREE.Color();
        for (let i = 0; i < d.n; i++) {
            pos[i * 3] = d.pos[0] + gauss() * d.R * 0.4;
            pos[i * 3 + 1] = d.pos[1] + gauss() * d.R * 0.28;
            pos[i * 3 + 2] = d.pos[2] + gauss() * d.R * 0.4;
            c.copy(cCore).lerp(cEdge, Math.random());
            col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        g.setAttribute('color', new THREE.BufferAttribute(col, 3));
        scene.add(new THREE.Points(g, new THREE.PointsMaterial({
            size: 2.1, map: starTex, transparent: true, opacity: 0.9,
            vertexColors: true, blending: THREE.AdditiveBlending, depthWrite: false,
        })));
    }
}

/* ================= 6. 亮星（可点击） ================= */
const SUN_THETA = 2.3, SUN_R = 55;
const sunPos = new THREE.Vector3(Math.cos(SUN_THETA) * SUN_R, 1.2, Math.sin(SUN_THETA) * SUN_R);
const insideCamPos = sunPos.clone().add(new THREE.Vector3(0, 1.8, 0));

// zone: near=太阳附近（内部全景主角） far=盘面各处
const NAMED_STARS = [
    { name: '太阳', spec: 'G2V 黄矮星', dist: 0, size: 2.0, col: '#ffe3b0', zone: 'sun', desc: '我们的家园恒星，位于猎户臂内侧、距银心约 2.6 万光年处。此刻你正站在它附近仰望银河。' },
    { name: '比邻星', spec: 'M5.5Ve 红矮星', dist: 4.2, size: 1.7, col: '#ffb08a', zone: 'near', desc: '距太阳最近的恒星，拥有宜居带内的行星比邻星 b，隶属半人马座 α 三合星系统。' },
    { name: '南门二', spec: 'G2V 黄矮星', dist: 4.4, size: 2.2, col: '#ffe9c0', zone: 'near', desc: '即半人马座 α 星 A，与太阳同为 G 型黄矮星，全天第三亮星。' },
    { name: '巴纳德星', spec: 'M4V 红矮星', dist: 6.0, size: 1.7, col: '#ffb08a', zone: 'near', desc: '蛇夫座红矮星，自行速度全天最大，约 180 年可在天球上移动一个月亮直径。' },
    { name: '天狼星', spec: 'A1V 蓝白主序星', dist: 8.6, size: 2.6, col: '#e8eeff', zone: 'near', desc: '大犬座 α，全天最亮恒星。它的伴星天狼 B 是人类最早发现的白矮星。' },
    { name: '牛郎星', spec: 'A7V 白色主序星', dist: 16.7, size: 2.4, col: '#eef2ff', zone: 'near', desc: '又名河鼓二，天鹰座 α。与织女星隔银河相望，是「夏季大三角」成员。' },
    { name: '南河三', spec: 'F5IV 亚巨星', dist: 11.5, size: 2.2, col: '#fff4e4', zone: 'near', desc: '小犬座 α，「冬季大三角」成员，同样拥有一颗白矮星伴星。' },
    { name: '织女星', spec: 'A0V 蓝白主序星', dist: 25, size: 2.5, col: '#e8eeff', zone: 'near', desc: '天琴座 α，北半球夏夜最亮的恒星之一，曾是历史上的北极星。' },
    { name: '北落师门', spec: 'A3V 白色主序星', dist: 25, size: 2.2, col: '#eef2ff', zone: 'near', desc: '南鱼座 α，秋夜南方低空最亮星，周围有醒目的尘埃盘。' },
    { name: '五车二', spec: 'G8III 黄巨星', dist: 42.9, size: 2.5, col: '#ffe9c0', zone: 'near', desc: '御夫座 α，实际是两对黄巨星组成的四合星系统。' },
    { name: '北河三', spec: 'K0III 橙巨星', dist: 33.8, size: 2.4, col: '#ffca96', zone: 'near', desc: '双子座 β，「北河之子」，最早确认拥有行星的巨星之一。' },
    { name: '大角星', spec: 'K1.5III 橙巨星', dist: 36.7, size: 2.6, col: '#ffca96', zone: 'near', desc: '牧夫座 α，北天最亮恒星。其橙红色光芒来自膨胀后的巨星外层。' },
    { name: '水委一', spec: 'B6V 蓝白主序星', dist: 139, size: 2.3, col: '#c4d4ff', zone: 'near', desc: '波江座 α，自转极快而被压成扁球形，赤道抛出气体环。' },
    { name: '老人星', spec: 'A9II 亮巨星', dist: 310, size: 3.0, col: '#fff6ea', zone: 'far', desc: '船底座 α，全天第二亮星，南天的标志性亮星，仅在南半球和低纬度易见。' },
    { name: '毕宿五', spec: 'K5III 橙巨星', dist: 65, size: 2.4, col: '#ffbe8a', zone: 'far', desc: '金牛座 α，「跟随者」，位于毕星团方向，前景橙巨星。' },
    { name: '轩辕十四', spec: 'B8IV 蓝白亚巨星', dist: 79, size: 2.2, col: '#c4d4ff', zone: 'far', desc: '狮子座 α，「小王」，几乎正好落在黄道上，常被月亮掩食。' },
    { name: '角宿一', spec: 'B1V 蓝色主序星', dist: 250, size: 2.6, col: '#b8ccff', zone: 'far', desc: '室女座 α，「春季大三角」成员，密近双星互绕周期仅 4 天。' },
    { name: '十字架二', spec: 'B0.5IV 蓝色亚巨星', dist: 320, size: 2.7, col: '#b8ccff', zone: 'far', desc: '南十字座 α，南天导航标志——十字长轴指向南天极。' },
    { name: '北极星', spec: 'F7Ib 黄超巨星', dist: 433, size: 2.7, col: '#fff4e0', zone: 'far', desc: '小熊座 α，现任北极星，一颗造父变星，周期约 4 天。' },
    { name: '心宿二', spec: 'M1.5Iab 红超巨星', dist: 550, size: 3.1, col: '#ff9d76', zone: 'far', desc: '天蝎座 α，又名「大火」，直径约为太阳 700 倍的红超巨星。' },
    { name: '参宿四', spec: 'M1-2Ia 红超巨星', dist: 550, size: 3.3, col: '#ff9d76', zone: 'far', desc: '猎户座 α，左肩红超巨星，已进入生命末期，未来百万年内将以超新星终结。' },
    { name: '参宿七', spec: 'B8Ia 蓝超巨星', dist: 860, size: 3.3, col: '#c4d4ff', zone: 'far', desc: '猎户座 β，猎户「左足」，光度约为太阳的 12 万倍。' },
    { name: '参宿三', spec: 'O9.5II 蓝亮巨星', dist: 1200, size: 3.0, col: '#b8ccff', zone: 'far', desc: '猎户腰带三星之一，多星系统，腰带三星在多种文化中都是著名符号。' },
    { name: '天津四', spec: 'A2Ia 蓝白超巨星', dist: 2600, size: 3.3, col: '#dfe6ff', zone: 'far', desc: '天鹅座 α，「夏季大三角」最远一角，距离约 2600 光年却仍是一等星。' },
];

let namedPoints = null;
const namedData = { thetas: null, radii: null, ys: null, spds: null };

function buildNamedStars() {
    const n = NAMED_STARS.length;
    const thetas = new Float32Array(n);
    const radii = new Float32Array(n);
    const ys = new Float32Array(n);
    const spds = new Float32Array(n);
    const colors = new Float32Array(n * 3);
    const sizes = new Float32Array(n);
    const phases = new Float32Array(n);
    const positions = new Float32Array(n * 3); // CPU 同步位置，供射线拾取
    const c = new THREE.Color();

    NAMED_STARS.forEach((s, i) => {
        phases[i] = Math.random() * Math.PI * 2;
        c.set(s.col);
        colors[i * 3] = c.r; colors[i * 3 + 1] = c.g; colors[i * 3 + 2] = c.b;
        sizes[i] = s.size;
        if (s.zone === 'sun') {
            // 太阳固定不动，作为内部全景的相机锚点
            thetas[i] = Math.atan2(sunPos.z, sunPos.x);
            radii[i] = Math.hypot(sunPos.x, sunPos.z);
            ys[i] = sunPos.y;
            spds[i] = 0;
        } else if (s.zone === 'near') {
            // 太阳邻域：球状散布在太阳周围
            const u = Math.random() * 2 - 1;
            const ang = Math.random() * Math.PI * 2;
            const sxy = Math.sqrt(1 - u * u);
            const d = 6 + Math.random() * 24;
            const x = sunPos.x + sxy * Math.cos(ang) * d;
            const z = sunPos.z + sxy * Math.sin(ang) * d;
            const y = sunPos.y + u * d * 0.35;
            thetas[i] = Math.atan2(z, x);
            radii[i] = Math.hypot(x, z);
            ys[i] = y;
            spds[i] = 1;
        } else {
            // 远方盘面各处
            const r = 18 + Math.random() * 92;
            const th = Math.random() * Math.PI * 2;
            thetas[i] = th; radii[i] = r;
            ys[i] = gauss() * 4;
            spds[i] = 1;
        }
    });

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geo.setAttribute('aTheta', new THREE.BufferAttribute(thetas, 1));
    geo.setAttribute('aRadius', new THREE.BufferAttribute(radii, 1));
    geo.setAttribute('aY', new THREE.BufferAttribute(ys, 1));
    geo.setAttribute('aColor', new THREE.BufferAttribute(colors, 3));
    geo.setAttribute('aSize', new THREE.BufferAttribute(sizes, 1));
    geo.setAttribute('aPhase', new THREE.BufferAttribute(phases, 1));
    geo.setAttribute('aSpd', new THREE.BufferAttribute(spds, 1));
    geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(), 260);

    namedPoints = new THREE.Points(geo, namedMat);
    namedPoints.frustumCulled = false;
    scene.add(namedPoints);
    namedData.thetas = thetas; namedData.radii = radii;
    namedData.ys = ys; namedData.spds = spds;
    syncNamedPositions();
}

// CPU 侧用同一差速公式镜像亮星位置，保证拾取与画面一致
function syncNamedPositions() {
    if (!namedPoints) return;
    const t = galaxyMat.uniforms.uTime.value;
    const spd = params.spin;
    const attr = namedPoints.geometry.getAttribute('position');
    const arr = attr.array;
    for (let i = 0; i < NAMED_STARS.length; i++) {
        const omega = spd * 1.7 / (namedData.radii[i] * 0.55 + 9) * namedData.spds[i];
        const th = namedData.thetas[i] + t * omega;
        arr[i * 3] = Math.cos(th) * namedData.radii[i];
        arr[i * 3 + 1] = namedData.ys[i];
        arr[i * 3 + 2] = Math.sin(th) * namedData.radii[i];
    }
    attr.needsUpdate = true;
}

/* ================= 6.5 太阳系（☀ 模式，位于太阳标记处） =================
   尺寸按真实比例：整个太阳系相对银盘只是一个点（海王星轨道 ≈ 1.5 单位），
   进入该模式后相机贴近到个位数量级观看。 */
const SOLAR_SCALE = 0.05;       // 与银河的比例压缩（再大就会在银盘上明显可见）
const SOLAR_VIEW_R = 2.4;       // 默认观看距离（约为海王星轨道的 1.6 倍）
const MOON_ORBIT = 0.55 * SOLAR_SCALE;
let solarGroup = null;
const solarPickables = [];
const solarBodies = []; // { holder, mesh, orbitR, speed, angle }
let moonPivot = null, moonAngle = 0;

const PLANETS = [
    { name: '水星', key: 'mercury', type: '岩质行星 · 第 1 行星', au: 0.39, color: '#b8afa2', kind: 'rock', orbitR: 4.6, size: 0.17, period: 7, inc: 0.12, axial: 0.01, desc: '距太阳最近的行星，表面布满陨石坑，昼夜温差接近 600℃，几乎没有大气。' },
    { name: '金星', key: 'venus', type: '岩质行星 · 第 2 行星', au: 0.72, color: '#e6c088', kind: 'rock', orbitR: 6.5, size: 0.26, period: 11, inc: 0.06, axial: 3.1, desc: '浓密的二氧化碳大气造就 460℃ 的失控温室效应，自转方向与多数行星相反。' },
    { name: '地球', key: 'earth', type: '岩质行星 · 第 3 行星', au: 1.00, color: '#3f7fd0', kind: 'earth', orbitR: 8.6, size: 0.28, period: 15, inc: 0, axial: 0.41, desc: '目前已知唯一存在生命的星球，71% 的表面被海洋覆盖，拥有一颗大卫星——月球。' },
    { name: '火星', key: 'mars', type: '岩质行星 · 第 4 行星', au: 1.52, color: '#c97a55', kind: 'rock', orbitR: 11.2, size: 0.23, period: 24, inc: 0.03, axial: 0.44, desc: '红色荒漠世界，拥有太阳系最高的火山——奥林帕斯山，两极有干冰极冠。' },
    { name: '木星', key: 'jupiter', type: '气态巨行星 · 第 5 行星', au: 5.20, color: '#c9a678', kind: 'gas', orbitR: 15.5, size: 0.85, period: 45, inc: 0.02, axial: 0.05, desc: '太阳系最大的行星，大红斑风暴已持续数百年，已知卫星超过 90 颗。' },
    { name: '土星', key: 'saturn', type: '气态巨行星 · 第 6 行星', au: 9.58, color: '#d9c08e', kind: 'gas', orbitR: 20.5, size: 0.72, period: 60, inc: 0.04, axial: 0.47, desc: '以壮丽的冰质光环著称，密度比水还低，是肉眼可见的最远行星。' },
    { name: '天王星', key: 'uranus', type: '冰巨星 · 第 7 行星', au: 19.2, color: '#9fd4d8', kind: 'ice', orbitR: 25, size: 0.46, period: 80, inc: 0.01, axial: 1.7, desc: '自转轴几乎躺倒的冰巨星，呈现淡青色，是第一颗用望远镜发现的行星。' },
    { name: '海王星', key: 'neptune', type: '冰巨星 · 第 8 行星', au: 30.1, color: '#5d7fd6', kind: 'ice', orbitR: 29.5, size: 0.45, period: 100, inc: 0.03, axial: 0.49, desc: '太阳系最外侧的行星，深蓝色大气中咆哮着时速 2100 公里的最强风暴。' },
];

/* ---------- 行星环绕观光（planet 模式）状态与常量 ---------- */
const BASE_NEAR = 0.1;              // 常规近平面（与 camera 初始值一致）
let planetIdx = -1;                 // 当前环绕的行星下标（与 PLANETS/solarBodies 对齐）
const planetR = (i) => PLANETS[i].size * SOLAR_SCALE;            // 行星半径
const planetNear = (i) => planetR(i) * 0.02;                     // planet 模式近平面
const planetZoom = (i) => [planetR(i) * 1.6, planetR(i) * 14];   // 环绕半径上下限
const PLANET_HOME = 4;              // 进入时默认环绕半径 = 4×行星半径
const _flyTarget = new THREE.Vector3(); // tween 每帧取行星世界坐标（避免逐帧 new）

// 土星环 UV 重排：RingGeometry 默认 UV 是平面投影，径向条带贴图（x=半径方向）
// 要求 u 沿半径线性、v 取条带中线
function makeRingGeometry(inner, outer) {
    const g = new THREE.RingGeometry(inner, outer, 128, 1);
    const pos = g.attributes.position, uv = g.attributes.uv;
    for (let i = 0; i < uv.count; i++) {
        const r = Math.hypot(pos.getX(i), pos.getY(i));    // 顶点在 XY 平面，直接取平面半径
        uv.setXY(i, (r - inner) / (outer - inner), 0.5);   // u: 内缘0 → 外缘1
    }
    uv.needsUpdate = true;
    return g;
}

function buildSolarSystem() {
    solarGroup = new THREE.Group();
    solarGroup.position.copy(sunPos);
    solarGroup.visible = false;
    scene.add(solarGroup);

    // 太阳本体（可点击）+ 辉光 + 光源 + 隐形点击代理（缩小后保证易点中）
    const sunR = 1.9 * SOLAR_SCALE;
    const sunMesh = new THREE.Mesh(
        new THREE.SphereGeometry(sunR, 32, 24),
        new THREE.MeshBasicMaterial({ color: 0xffedb8 }));
    const sunCard = {
        name: '太阳', spec: 'G2V 黄矮星 · 太阳系中心',
        dist: '我们在这里', desc: NAMED_STARS[0].desc,
    };
    sunMesh.userData.card = sunCard;
    solarGroup.add(sunMesh);
    solarPickables.push(sunMesh);
    const sunProxy = new THREE.Mesh(
        new THREE.SphereGeometry(sunR * 4, 8, 6),
        new THREE.MeshBasicMaterial({ visible: false }));
    sunProxy.userData.card = sunCard;
    solarGroup.add(sunProxy);
    solarPickables.push(sunProxy);
    const mkGlow = (s, o) => {
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({
            map: glowTex, transparent: true, opacity: o,
            blending: THREE.AdditiveBlending, depthWrite: false,
        }));
        sp.scale.setScalar(s * SOLAR_SCALE);
        solarGroup.add(sp);
    };
    mkGlow(9, 0.9);
    mkGlow(26, 0.4);
    solarGroup.add(new THREE.PointLight(0xfff0d0, 3, 0, 0));
    scene.add(new THREE.AmbientLight(0x2a3352, 0.9)); // 仅供行星标准材质

    for (let idx = 0; idx < PLANETS.length; idx++) { // 带下标，供 userData.planetIdx 双击进入
        const p = PLANETS[idx];
        const oR = p.orbitR * SOLAR_SCALE;
        const sz = p.size * SOLAR_SCALE;
        const orbit = new THREE.Group(); // 轨道面（小倾角）
        orbit.rotation.x = p.inc;
        solarGroup.add(orbit);

        const pts = [];
        for (let i = 0; i <= 128; i++) {
            const a = (i / 128) * Math.PI * 2;
            pts.push(new THREE.Vector3(Math.cos(a) * oR, 0, Math.sin(a) * oR));
        }
        orbit.add(new THREE.Line(
            new THREE.BufferGeometry().setFromPoints(pts),
            new THREE.LineBasicMaterial({ color: 0x66779f, transparent: true, opacity: 0.35 })));

        const holder = new THREE.Group(); // 行星位置（含轴倾角）
        holder.rotation.z = p.axial;
        orbit.add(holder);

        // 每行星恰好一次纹理构建；本迭代后续分支（本体/bump/云/环/月球）只引用 tex.*
        const tex = PLANET_TEX[p.key]();
        const maxAniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());
        for (const t of [tex.map, tex.bumpMap, tex.cloudMap, tex.ringMap, tex.moonMap])
            if (t) t.anisotropy = maxAniso;

        // 行星本体：高清程序贴图（契约必返 map）+ 可选 bump
        const mat = new THREE.MeshStandardMaterial({ map: tex.map, roughness: 0.9, metalness: 0 });
        if (tex.bumpMap) { mat.bumpMap = tex.bumpMap; mat.bumpScale = sz * 0.6; }
        const mesh = new THREE.Mesh(new THREE.SphereGeometry(sz, 96, 64), mat);
        mesh.userData.card = { name: p.name, spec: p.type, dist: `距太阳 ${p.au.toFixed(2)} AU`, desc: p.desc };
        mesh.userData.planetIdx = idx; // 双击进入环绕观光
        holder.add(mesh);
        solarPickables.push(mesh);

        // 隐形点击代理：放大命中范围，缩小后不用精确瞄准
        const proxy = new THREE.Mesh(
            new THREE.SphereGeometry(Math.max(sz * 3.5, 0.02), 8, 6),
            new THREE.MeshBasicMaterial({ visible: false }));
        proxy.userData.card = mesh.userData.card;
        proxy.userData.planetIdx = idx; // 双击代理同样可进入
        holder.add(proxy);
        solarPickables.push(proxy);

        // 云层：凡提供 cloudMap 的行星（地球/金星）自动生效，缺省跳过
        let cloud = null;
        if (tex.cloudMap) {
            cloud = new THREE.Mesh(
                new THREE.SphereGeometry(sz * 1.015, 96, 64), // 略大于地表 +1.5%，差速自转
                new THREE.MeshStandardMaterial({
                    map: tex.cloudMap, transparent: true, opacity: 0.85,
                    depthWrite: false, roughness: 1, metalness: 0,
                }));
            holder.add(cloud);
        }

        // 土星环：ringMap 径向条带 + UV 重排；缺省回退纯色环（契约违约降级）
        if (p.key === 'saturn') {
            const ring = tex.ringMap
                ? new THREE.Mesh(
                    makeRingGeometry(sz * 1.5, sz * 2.4),
                    new THREE.MeshBasicMaterial({
                        map: tex.ringMap, transparent: true,
                        side: THREE.DoubleSide, depthWrite: false,
                    }))
                : new THREE.Mesh(
                    new THREE.RingGeometry(sz * 1.5, sz * 2.4, 64),
                    new THREE.MeshBasicMaterial({ color: 0xcbb98f, transparent: true, opacity: 0.5, side: THREE.DoubleSide }));
            ring.rotation.x = Math.PI / 2; // 随 holder 轴倾角一起倾斜
            holder.add(ring);
        }

        // 地球月球：moonMap 贴图；缺省回退灰月（契约违约降级）
        if (p.key === 'earth') {
            moonPivot = new THREE.Mesh(
                new THREE.SphereGeometry(0.075 * SOLAR_SCALE, 24, 16),
                tex.moonMap
                    ? new THREE.MeshStandardMaterial({ map: tex.moonMap, roughness: 1, metalness: 0 })
                    : new THREE.MeshStandardMaterial({ color: 0xb8b8c0, roughness: 1 }));
            holder.add(moonPivot);
        }
        solarBodies.push({ holder, mesh, cloud, orbitR: oR, speed: (Math.PI * 2) / p.period, angle: Math.random() * Math.PI * 2 });
    }
}

function updateSolar(dt) {
    if (!solarGroup || !solarGroup.visible) return;
    for (const b of solarBodies) {
        b.angle += dt * b.speed;
        b.holder.position.set(Math.cos(b.angle) * b.orbitR, 0, Math.sin(b.angle) * b.orbitR);
        b.mesh.rotation.y += dt * 0.5;
        if (b.cloud) b.cloud.rotation.y += dt * 0.535; // 与地表 0.5 差速 → 缓慢相对漂移
    }
    if (moonPivot) {
        moonAngle += dt * 2.4;
        moonPivot.position.set(Math.cos(moonAngle) * MOON_ORBIT, 0, Math.sin(moonAngle) * MOON_ORBIT);
        moonPivot.rotation.y = -moonAngle; // 潮汐锁定：始终同面朝向地球
    }
    solarGroup.updateMatrixWorld(true); // planet 模式相机锁定需零滞后的世界矩阵
}

/* 太阳系内看到的「真实夜空」：其他恒星都在成千上万倍太阳系宽度之外，
   只呈现为固定的小点；银河是一条横跨天空的暗带，银心方向（人马座方向）更亮。
   半径 420 ≈ 太阳系宽度的 140 倍（真实为 ~9000 倍，此为单场景可行的最远层）。 */
function buildSolarSky() {
    solarSky = new THREE.Group();
    solarSky.position.copy(sunPos);
    solarSky.visible = false;
    scene.add(solarSky);

    const R = 420;
    const CORE_DIR = Math.atan2(-sunPos.z, -sunPos.x); // 银心方向的天球经度
    const c = new THREE.Color();

    const mkLayer = (n, size, opacity, band) => {
        const pos = new Float32Array(n * 3);
        const col = new Float32Array(n * 3);
        for (let i = 0; i < n; i++) {
            let lon, lat;
            if (band) {
                // 银河带：集中在银道面附近，银心方向加密
                lon = Math.random() < 0.45 ? CORE_DIR + gauss() * 0.9 : Math.random() * Math.PI * 2;
                lat = gauss() * 0.13;
            } else {
                lon = Math.random() * Math.PI * 2;
                lat = Math.asin(Math.random() * 2 - 1);
            }
            const cl = Math.cos(lat);
            pos[i * 3] = Math.cos(lon) * cl * R;
            pos[i * 3 + 1] = Math.sin(lat) * R;
            pos[i * 3 + 2] = Math.sin(lon) * cl * R;
            // 银心方向与带核心处更暖更亮，远离则偏蓝偏暗
            const coreBias = band
                ? Math.max(0, Math.cos(lon - CORE_DIR)) * Math.exp(-Math.abs(lat) * 2.2)
                : 0;
            const l = (band ? 0.5 : 0.62) + coreBias * 0.28 + Math.random() * 0.14;
            c.setHSL(0.62 - coreBias * 0.45, 0.18 + coreBias * 0.3, Math.min(0.9, l));
            col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        g.setAttribute('color', new THREE.BufferAttribute(col, 3));
        g.boundingSphere = new THREE.Sphere(new THREE.Vector3(), R * 1.1);
        const m = new THREE.PointsMaterial({
            size, map: starTex, transparent: true, opacity,
            vertexColors: true, sizeAttenuation: true,
            blending: THREE.AdditiveBlending, depthWrite: false,
        });
        solarSky.add(new THREE.Points(g, m));
        skyFadeMats.push({ m, base: opacity });
    };
    mkLayer(2600, 1.4, 0.9, false); // 全天星点
    mkLayer(2800, 1.9, 0.85, true); // 银河带恒星
    mkLayer(1500, 3.8, 0.2, true);  // 银河雾状辉光

    // 银心方向的暗淡亮区（人马座方向的银河最亮段）
    const coreMat = new THREE.SpriteMaterial({
        map: glowTex, transparent: true, opacity: 0.5,
        blending: THREE.AdditiveBlending, depthWrite: false,
    });
    const core = new THREE.Sprite(coreMat);
    core.position.set(Math.cos(CORE_DIR) * 400, 0, Math.sin(CORE_DIR) * 400);
    core.scale.setScalar(130);
    solarSky.add(core);
    skyFadeMats.push({ m: coreMat, base: 0.5 });
}

/* ================= 7. 相机控制（自实现，含惯性/触摸/双指） ================= */
const ctrl = {
    mode: 'outside', // outside | inside | solar | cruise | planet（行星环绕观光）
    sph: new THREE.Spherical(178, 1.08, 0.9), // 环绕球坐标（相对 target）
    target: new THREE.Vector3(0, 0, 0),       // 环绕中心：星系中心或太阳位置
    savedSph: new THREE.Spherical(178, 1.08, 0.9),
    vel: { th: 0, ph: 0 },      // 外部惯性
    look: { yaw: 0, pitch: 0, vyaw: 0, vpitch: 0 }, // 内部自由环视
    fov: 60, fovTarget: 60,
    dragging: false,
};
const DEFAULT_SPH = new THREE.Spherical(178, 1.08, 0.9);
const ORIGIN = new THREE.Vector3(0, 0, 0);
let tween = null;
let cruiseT = 0, cruiseTheta0 = 0;

const easeInOut = (k) => k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;

// 用户任何输入都可打断转场：取消 tween 并从相机当前姿态无缝接管
function interruptTween() {
    if (!tween) return;
    tween = null;
    // solar/planet 同属太阳系层级，打断后行星系不得消失
    if (ctrl.mode !== 'solar' && ctrl.mode !== 'planet') solarGroup.visible = false;
    const rel = camera.position.clone().sub(ctrl.target);
    const r = rel.length();
    if (ctrl.mode === 'outside' || ctrl.mode === 'cruise' || ctrl.mode === 'solar' || ctrl.mode === 'planet') {
        ctrl.sph.set(
            r,
            Math.acos(clamp(rel.y / (r || 1), -1, 1)),
            Math.atan2(rel.x, rel.z));
    } else if (ctrl.mode === 'inside') {
        const e = new THREE.Euler().setFromQuaternion(camera.quaternion, 'YXZ');
        ctrl.look.pitch = e.x;
        ctrl.look.yaw = e.y;
    }
}

// moving：返回运动目标当前世界坐标的函数。存在时 pos 视为相对目标的偏移，
// 落点与朝向每帧重算（行星公转最快 0.897 rad/s，固定落点必脱靶）；既有 4 参调用不受影响
function flyTo(pos, quat, dur, done, moving) {
    tween = {
        t: 0, dur,
        p0: camera.position.clone(), q0: camera.quaternion.clone(),
        off: pos.clone(), // moving 存在时：相对运动目标的落点偏移
        p1: moving ? moving().clone().add(pos) : pos.clone(),
        q1: quat ? quat.clone() : null,
        done, moving: moving || null,
    };
}
function stepTween(dt) {
    tween.t += dt;
    if (tween.moving) { // 紧盯运动中的行星：每帧重算落点与朝向
        const tp = tween.moving();
        tween.p1.copy(tp).add(tween.off);
        tween.q1 = quatLookAt(tween.p1, tp);
    }
    const k = easeInOut(Math.min(1, tween.t / tween.dur));
    camera.position.lerpVectors(tween.p0, tween.p1, k);
    camera.quaternion.slerpQuaternions(tween.q0, tween.q1, k);
    if (tween.t >= tween.dur) {
        const d = tween.done;
        tween = null;
        d && d();
    }
}
function quatLookAt(from, target) {
    const m = new THREE.Matrix4().lookAt(from, target, new THREE.Vector3(0, 1, 0));
    return new THREE.Quaternion().setFromRotationMatrix(m);
}
function sphToVec(sph) {
    return new THREE.Vector3().setFromSphericalCoords(sph.radius, sph.phi, sph.theta);
}
// 内部视角朝向银心的初始 yaw/pitch（Euler YXZ 约定）
function insideFaceCenter() {
    const d = new THREE.Vector3(0, 0, 0).sub(insideCamPos).normalize();
    return { pitch: Math.asin(clamp(d.y, -1, 1)), yaw: Math.atan2(-d.x, -d.z) };
}

function applyOutside(dt) {
    if (!ctrl.dragging) {
        ctrl.sph.theta += ctrl.vel.th;
        ctrl.sph.phi = clamp(ctrl.sph.phi + ctrl.vel.ph, 0.12, Math.PI - 0.35);
        ctrl.vel.th *= 0.93; ctrl.vel.ph *= 0.93;
    }
    camera.position.copy(ctrl.target).add(sphToVec(ctrl.sph));
    camera.lookAt(ctrl.target);
}
function applyInside() {
    if (!ctrl.dragging) {
        ctrl.look.yaw += ctrl.look.vyaw;
        ctrl.look.pitch = clamp(ctrl.look.pitch + ctrl.look.vpitch, -1.45, 1.45);
        ctrl.look.vyaw *= 0.9; ctrl.look.vpitch *= 0.9;
    }
    camera.position.copy(insideCamPos);
    camera.quaternion.setFromEuler(new THREE.Euler(ctrl.look.pitch, ctrl.look.yaw, 0, 'YXZ'));
}
// 巡演路径：方位角持续推进（约 25°/s，肉眼明显），半径与俯仰以不同周期起伏
function cruisePose(tau) {
    return new THREE.Spherical(
        150 + 85 * Math.sin(0.13 * tau + 0.6),
        0.95 + 0.62 * Math.sin(0.085 * tau + 2.2),
        cruiseTheta0 + 0.14 * tau);
}
function applyCruise(dt) {
    cruiseT += dt;
    ctrl.sph.copy(cruisePose(cruiseT));
    camera.position.copy(sphToVec(ctrl.sph));
    camera.lookAt(0, 0, 0);
}

function setMode(next) {
    interruptTween();
    if (next === ctrl.mode && next !== 'cruise') return;
    if (ctrl.mode === 'planet' && next !== 'planet') { // 从行星观光直接切其他模式：统一收尾
        hidePlanetNav();
        planetIdx = -1;
    }
    if (ctrl.mode === 'outside' || ctrl.mode === 'cruise') {
        ctrl.savedSph.copy(ctrl.sph);
    }
    // 离开太阳系层级（solar/planet → 非 solar 且非 planet）时，
    // 飞行结束后再隐藏行星系，避免眼前突然消失
    const hideSolar = (ctrl.mode === 'solar' || ctrl.mode === 'planet') && next !== 'solar' && next !== 'planet'
        ? () => { if (ctrl.mode !== 'solar' && ctrl.mode !== 'planet') solarGroup.visible = false; }
        : null;
    if (next === 'inside') {
        ctrl.target.copy(ORIGIN);
        ctrl.fovTarget = 60;
        const f = insideFaceCenter();
        ctrl.look.yaw = f.yaw; ctrl.look.pitch = f.pitch;
        ctrl.look.vyaw = ctrl.look.vpitch = 0;
        ctrl.mode = 'inside';
        flyTo(insideCamPos, new THREE.Quaternion().setFromEuler(
            new THREE.Euler(f.pitch, f.yaw, 0, 'YXZ')), 2.4, hideSolar);
    } else if (next === 'outside') {
        ctrl.target.copy(ORIGIN);
        ctrl.fovTarget = 60;
        if (ctrl.mode === 'cruise') {
            // 巡演中切回：镜头就地接管，不飞行
            ctrl.vel.th = ctrl.vel.ph = 0;
            ctrl.mode = 'outside';
        } else {
            const pos = sphToVec(ctrl.savedSph);
            ctrl.sph.copy(ctrl.savedSph);
            ctrl.vel.th = ctrl.vel.ph = 0;
            ctrl.mode = 'outside';
            flyTo(pos, quatLookAt(pos, ORIGIN), 2.2, hideSolar);
        }
    } else if (next === 'solar') {
        ctrl.target.copy(sunPos);
        ctrl.fovTarget = 60;
        // 延续当前方位角，飞到太阳系上空
        const rel = camera.position.clone().sub(sunPos);
        ctrl.sph.set(SOLAR_VIEW_R, 1.05, Math.atan2(rel.x, rel.z));
        ctrl.vel.th = ctrl.vel.ph = 0;
        ctrl.mode = 'solar';
        solarGroup.visible = true;
        const p0 = ctrl.target.clone().add(sphToVec(ctrl.sph));
        flyTo(p0, quatLookAt(p0, ctrl.target), 2.2);
    } else if (next === 'cruise') {
        ctrl.target.copy(ORIGIN);
        ctrl.fovTarget = 60;
        // 路径起点沿用当前方位角，先飞至起点再沿路径巡游
        cruiseTheta0 = Math.atan2(camera.position.x, camera.position.z);
        ctrl.sph.copy(cruisePose(0));
        cruiseT = 0;
        ctrl.mode = 'cruise';
        const p0 = sphToVec(ctrl.sph);
        flyTo(p0, quatLookAt(p0, ORIGIN), 1.6, hideSolar);
    }
    updateModeButtons();
}
function exitCruise() { // 用户拖拽时无缝接管，不飞行
    if (ctrl.mode !== 'cruise') return;
    ctrl.mode = 'outside';
    ctrl.vel.th = ctrl.vel.ph = 0;
    updateModeButtons();
}
function resetView() {
    interruptTween();
    if (ctrl.mode === 'cruise') exitCruise();
    if (ctrl.mode === 'inside') {
        const f = insideFaceCenter();
        ctrl.look.yaw = f.yaw; ctrl.look.pitch = f.pitch;
        ctrl.fovTarget = 60;
        flyTo(insideCamPos, new THREE.Quaternion().setFromEuler(
            new THREE.Euler(f.pitch, f.yaw, 0, 'YXZ')), 1.2);
    } else if (ctrl.mode === 'planet') {
        ctrl.sph.radius = planetR(planetIdx) * PLANET_HOME; // 保留方位/俯仰，仅复位距离
        flyTo(sphToVec(ctrl.sph), null, 1.0, null,
            () => planetWorldPos(planetIdx, _flyTarget));
    } else if (ctrl.mode === 'solar') {
        ctrl.sph.set(SOLAR_VIEW_R, 1.05, ctrl.sph.theta); // 保留方位角，仅复位距离/高度
        const p0 = ctrl.target.clone().add(sphToVec(ctrl.sph));
        flyTo(p0, quatLookAt(p0, ctrl.target), 1.2);
    } else {
        const pos = sphToVec(DEFAULT_SPH);
        ctrl.sph.copy(DEFAULT_SPH);
        ctrl.vel.th = ctrl.vel.ph = 0;
        flyTo(pos, quatLookAt(pos, ORIGIN), 1.2);
    }
}

/* ---------- 指针 / 滚轮 / 双指 ---------- */
const pointers = new Map();
let pinchD = 0, movedPx = 0;
const mouseNDC = new THREE.Vector2();
let mouseActive = false;

canvas.addEventListener('pointerdown', (e) => {
    mouseNDC.set((e.clientX / innerWidth) * 2 - 1, -(e.clientY / innerHeight) * 2 + 1);
    mouseActive = true;
    interruptTween();
    canvas.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    ctrl.dragging = true;
    movedPx = 0;
    ctrl.vel.th = ctrl.vel.ph = 0;
    ctrl.look.vyaw = ctrl.look.vpitch = 0;
    canvas.classList.add('dragging');
    exitCruise();
    if (pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        pinchD = Math.hypot(a.x - b.x, a.y - b.y);
    }
});
canvas.addEventListener('pointermove', (e) => {
    mouseNDC.set((e.clientX / innerWidth) * 2 - 1, -(e.clientY / innerHeight) * 2 + 1);
    mouseActive = true;
    const p = pointers.get(e.pointerId);
    if (!p) return;
    const dx = e.clientX - p.x, dy = e.clientY - p.y;
    p.x = e.clientX; p.y = e.clientY;
    movedPx += Math.abs(dx) + Math.abs(dy);
    if (pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        const d = Math.hypot(a.x - b.x, a.y - b.y);
        if (pinchD > 0 && d > 0) {
            const s = pinchD / d;
            if (ctrl.mode === 'inside') ctrl.fovTarget = clamp(ctrl.fovTarget * s, 30, 78);
            else if (ctrl.mode === 'solar') ctrl.sph.radius = clamp(ctrl.sph.radius * s, 0.35, 10);
            else if (ctrl.mode === 'planet') { // 环绕半径按行星大小自适应
                const [rMin, rMax] = planetZoom(planetIdx);
                // 半径仍超上限（进入飞行途中/刚打断转场）时不向内硬拉瞬移，只阻止继续拉远
                const hi = Math.max(rMax, ctrl.sph.radius);
                ctrl.sph.radius = clamp(ctrl.sph.radius * s, rMin, hi);
            }
            else ctrl.sph.radius = clamp(ctrl.sph.radius * s, 26, 560);
        }
        pinchD = d;
        return;
    }
    if (ctrl.mode === 'inside') {
        const s = 0.0026;
        ctrl.look.yaw -= dx * s;
        ctrl.look.pitch = clamp(ctrl.look.pitch - dy * s, -1.45, 1.45);
        ctrl.look.vyaw = -dx * s;
        ctrl.look.vpitch = -dy * s;
    } else {
        const s = 0.0045;
        ctrl.sph.theta -= dx * s;
        ctrl.sph.phi = clamp(ctrl.sph.phi - dy * s, 0.12, Math.PI - 0.35);
        ctrl.vel.th = -dx * s;
        ctrl.vel.ph = -dy * s;
    }
});
function endPointer(e) {
    pointers.delete(e.pointerId);
    if (pointers.size < 2) pinchD = 0;
    if (pointers.size === 0) {
        ctrl.dragging = false;
        canvas.classList.remove('dragging');
        if (movedPx < 6) handleClick();
    }
}
canvas.addEventListener('pointerup', endPointer);
canvas.addEventListener('pointercancel', endPointer);
canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    interruptTween();
    exitCruise();
    if (ctrl.mode === 'inside') {
        ctrl.fovTarget = clamp(ctrl.fovTarget * Math.exp(e.deltaY * 0.0009), 30, 78);
    } else if (ctrl.mode === 'solar') {
        ctrl.sph.radius = clamp(ctrl.sph.radius * Math.exp(e.deltaY * 0.0011), 0.35, 10);
    } else if (ctrl.mode === 'planet') { // 环绕半径按行星大小自适应
        const [rMin, rMax] = planetZoom(planetIdx);
        // 半径仍超上限（进入飞行途中/刚打断转场）时不向内硬拉瞬移，只阻止继续拉远
        const hi = Math.max(rMax, ctrl.sph.radius);
        ctrl.sph.radius = clamp(ctrl.sph.radius * Math.exp(e.deltaY * 0.0011), rMin, hi);
    } else {
        ctrl.sph.radius = clamp(ctrl.sph.radius * Math.exp(e.deltaY * 0.0011), 26, 560);
    }
}, { passive: false });
// 太阳系/行星环绕模式下双击行星 → 进入（切换到）该行星的环绕观光；
// 双击太阳/空处维持原复位逻辑
canvas.addEventListener('dblclick', () => {
    if (ctrl.mode === 'solar' || ctrl.mode === 'planet') {
        const hit = pickSolar();
        if (hit && hit.userData.planetIdx !== undefined) {
            enterPlanet(hit.userData.planetIdx); // 内部会 hideCard() 收掉双击残留的信息卡
            return;
        }
    }
    resetView();
});
window.addEventListener('keydown', (e) => {
    // 参数面板控件持焦点时方向键归滑杆专用，避免「切换行星 + 改参数」双重效果
    // （ESC 不受影响：滑杆不响应 ESC，保留全局退出语义）
    if (e.target && e.target.closest && e.target.closest('#panel')
        && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) return;
    if (e.key === 'Escape') { ctrl.mode === 'planet' ? exitPlanet() : hideCard(); }
    else if (ctrl.mode === 'planet' && e.key === 'ArrowLeft') switchPlanet(-1);
    else if (ctrl.mode === 'planet' && e.key === 'ArrowRight') switchPlanet(1);
});

/* ================= 8. 亮星拾取与信息卡 ================= */
const raycaster = new THREE.Raycaster();
raycaster.params.Points.threshold = 3.2;

function pickNamed() {
    if (!namedPoints || !mouseActive || skyFade > 0.5) return -1; // 已淡出的亮星不可拾取
    raycaster.setFromCamera(mouseNDC, camera);
    const hits = raycaster.intersectObject(namedPoints, false);
    return hits.length ? hits[0].index : -1;
}
function pickSolar() {
    if (!solarGroup || !solarGroup.visible || !mouseActive) return null;
    raycaster.setFromCamera(mouseNDC, camera);
    const hits = raycaster.intersectObjects(solarPickables, false);
    return hits.length ? hits[0].object : null;
}
function handleClick() {
    const body = pickSolar();
    if (body) { showCardData(body.userData.card, body.userData.planetIdx); return; }
    const idx = pickNamed();
    if (idx >= 0) showCard(idx);
    else hideCard();
}
let cardPlanetIdx = null; // 当前信息卡对应的行星下标（有值时显示「进入环绕观光」入口）
function showCardData(c, planetIdx) {
    $('cardName').textContent = c.name;
    $('cardSpec').textContent = c.spec;
    $('cardDist').textContent = c.dist;
    $('cardDesc').textContent = c.desc;
    cardPlanetIdx = (planetIdx === undefined || planetIdx === null) ? null : planetIdx;
    $('cardEnter').classList.toggle('show', cardPlanetIdx !== null);
    $('starCard').classList.add('show');
}
function showCard(idx) {
    const s = NAMED_STARS[idx];
    showCardData({
        name: s.name,
        spec: s.spec,
        dist: s.dist === 0 ? '我们在这里' : `距太阳 ${s.dist} 光年`,
        desc: s.desc,
    });
}
function hideCard() {
    $('starCard').classList.remove('show');
}
$('cardClose').addEventListener('click', hideCard);
// 行星卡内的环绕观光入口（触屏双击 dblclick 不可靠时的首次进入通道，非行星卡自动隐藏）
$('cardEnter').addEventListener('click', () => {
    if (cardPlanetIdx !== null) enterPlanet(cardPlanetIdx); // 内部会 hideCard()
});

/* ================= 8.5 行星环绕观光（planet 模式） ================= */
// holder 挂在带倾角的 orbit 组内，世界坐标须经矩阵变换取
function planetWorldPos(i, out) {
    return solarBodies[i].holder.getWorldPosition(out);
}
// 每帧把环绕中心锁到公转中的行星（applyOutside 的 sph 是相对 target 的偏移，
// target 跟随即刚性锁定；须在主循环 tween/派发之前调用）
function syncPlanetCamera() {
    if (ctrl.mode !== 'planet' || planetIdx < 0) return;
    planetWorldPos(planetIdx, ctrl.target);
}

function enterPlanet(i) {
    if (ctrl.mode !== 'solar' && ctrl.mode !== 'planet') return;
    interruptTween();
    hideCard(); // 双击会先触发两次单击弹卡，这里收掉
    planetIdx = clamp(i, 0, PLANETS.length - 1);
    const r = planetR(planetIdx);
    ctrl.mode = 'planet'; // 先定模式，interruptTween/派发都能正确归类
    ctrl.fovTarget = 60;
    ctrl.vel.th = ctrl.vel.ph = 0;
    solarGroup.visible = true;
    planetWorldPos(planetIdx, ctrl.target); // 立即锁定，转场期间也跟随
    // 延续当前方位角：从相机→行星的方向取 theta，落点高度略俯视
    const rel = camera.position.clone().sub(ctrl.target);
    ctrl.sph.set(r * PLANET_HOME, 1.15, Math.atan2(rel.x, rel.z));
    // 近平面收紧须在飞行开始前：接近段（<0.1）行星否则会被近平面整体裁掉
    camera.near = planetNear(planetIdx);
    camera.updateProjectionMatrix();
    flyTo(sphToVec(ctrl.sph), null, 1.9,
        () => {}, // 到达即处于 applyOutside 环绕
        () => planetWorldPos(planetIdx, _flyTarget));
    showPlanetNav();
    updateModeButtons();
}

function exitPlanet() { // ESC / 导航按钮 / 模式按钮统一走这里
    if (ctrl.mode !== 'planet') return;
    hideCard();
    hidePlanetNav();
    planetIdx = -1;
    setMode('solar'); // 复用 solar 分支：target=sunPos、飞回 SOLAR_VIEW_R
    // camera.near 不在此恢复 → 交给主循环自愈守卫，避免飞行途中行星突然消失
}

function switchPlanet(dir) { // 导航「上一颗/下一颗」与 ←/→ 键（环形取模）
    if (ctrl.mode !== 'planet') return;
    enterPlanet((planetIdx + dir + PLANETS.length) % PLANETS.length);
}

function showPlanetNav() {
    const p = PLANETS[planetIdx];
    $('planetLabel').textContent = `${p.name} · ${p.type.replace(' · ', '（')}）`;
    $('planetNav').classList.add('show');
    $('planetNav').setAttribute('aria-hidden', 'false');
}
function hidePlanetNav() {
    $('planetNav').classList.remove('show');
    $('planetNav').setAttribute('aria-hidden', 'true');
}
$('prevPlanet').addEventListener('click', () => switchPlanet(-1));
$('nextPlanet').addEventListener('click', () => switchPlanet(1));
$('exitPlanet').addEventListener('click', exitPlanet);

/* ================= 9. UI 联动 ================= */
const modeBtns = [...document.querySelectorAll('#modeBar .btn[data-mode]')];
function updateModeButtons() {
    modeBtns.forEach(b => b.classList.toggle('active', b.dataset.mode === ctrl.mode
        || (ctrl.mode === 'planet' && b.dataset.mode === 'solar'))); // planet 无独立按钮，☀ 保持高亮
    $('cruiseBtn').textContent = ctrl.mode === 'cruise' ? '⏸ 停止巡演' : '🎬 自动巡演';
}
modeBtns.forEach(b => b.addEventListener('click', () => {
    if (b.dataset.mode === 'cruise' && ctrl.mode === 'cruise') setMode('outside');
    else setMode(b.dataset.mode);
}));
$('resetBtn').addEventListener('click', resetView);

const fmtMul = (v) => `${(+v).toFixed(2).replace(/\.?0+$/, '')}×`;
$('arms').addEventListener('input', (e) => { $('armsOut').textContent = e.target.value; });
$('arms').addEventListener('change', (e) => { params.arms = +e.target.value; buildGalaxy(); });
$('stars').addEventListener('input', (e) => { $('starsOut').textContent = `${e.target.value / 10000} 万`; });
$('stars').addEventListener('change', (e) => { params.starCount = +e.target.value; buildGalaxy(); });
$('spin').addEventListener('input', (e) => {
    params.spin = +e.target.value;
    $('spinOut').textContent = fmtMul(params.spin);
    spinMats.forEach(m => { m.uniforms.uSpinSpeed.value = params.spin; });
});
$('bright').addEventListener('input', (e) => {
    params.brightness = +e.target.value;
    $('brightOut').textContent = fmtMul(params.brightness);
    spinMats.forEach(m => { m.uniforms.uBrightness.value = params.brightness; });
});
$('twinkle').addEventListener('change', (e) => {
    params.twinkle = e.target.checked;
    spinMats.forEach(m => { m.uniforms.uTwinkle.value = params.twinkle ? 1 : 0; });
});
$('panelHead').addEventListener('click', () => {
    const p = $('panel');
    p.classList.toggle('collapsed');
    $('panelToggle').textContent = p.classList.contains('collapsed') ? '展开' : '收起';
});
if (innerWidth < 720) {
    $('panel').classList.add('collapsed');
    $('panelToggle').textContent = '展开';
}

/* ================= 10. 初始化与主循环 ================= */
buildGalaxy();
buildCoreGlow();
buildBackground();
buildSatellites();
buildNamedStars();
buildSolarSystem();
buildSolarSky();
camera.position.copy(sphToVec(ctrl.sph));
camera.lookAt(0, 0, 0);
updateModeButtons();

window.addEventListener('resize', () => {
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
});

const clock = new THREE.Clock();
let fpsFrames = 0, fpsTime = 0, fpsVal = 0, firstFrame = true;

function loop() {
    requestAnimationFrame(loop);
    const dt = Math.min(clock.getDelta(), 0.05);

    galaxyMat.uniforms.uTime.value += dt;
    namedMat.uniforms.uTime.value = galaxyMat.uniforms.uTime.value;
    updateSolar(dt);

    // 银河场景 ↔ 太阳系夜空 的交叉淡入淡出（由相机到太阳的距离驱动）
    // planet 模式相机距 sunPos ≈ 0.2~1.5，k 自动 = 1，夜空层全程保持
    let k = (ctrl.mode === 'solar' || ctrl.mode === 'planet')
        ? clamp((40 - camera.position.distanceTo(sunPos)) / 30, 0, 1)
        : 0;
    k = k * k * (3 - 2 * k); // smoothstep
    skyFade += (k - skyFade) * Math.min(1, dt * 5);
    galaxyMat.uniforms.uFade.value = 1 - skyFade;
    namedMat.uniforms.uFade.value = 1 - skyFade;
    for (const f of galaxyFadeMats) f.m.opacity = f.base * (1 - skyFade);
    solarSky.visible = skyFade > 0.01;
    if (solarSky.visible) for (const f of skyFadeMats) f.m.opacity = f.base * skyFade;

    syncPlanetCamera(); // planet 模式：target 逐帧锁定公转中的行星（先于转场与环绕派发）
    if (tween) stepTween(dt);
    else if (ctrl.mode === 'outside' || ctrl.mode === 'solar' || ctrl.mode === 'planet') applyOutside(dt);
    else if (ctrl.mode === 'inside') applyInside();
    else applyCruise(dt);

    // near 自愈守卫：离开 planet 模式且无转场、相机已拉远后才恢复默认近平面
    // （覆盖 exitPlanet 飞行结束、飞行中被打断、planet 直接切其他模式三条路径）
    if (ctrl.mode !== 'planet' && camera.near !== BASE_NEAR && !tween
        && camera.position.distanceTo(sunPos) > 0.8) {
        camera.near = BASE_NEAR;
        camera.updateProjectionMatrix();
    }

    // 视场平滑（内部模式滚轮=变焦）
    const fovT = ctrl.mode === 'inside' ? ctrl.fovTarget : 60;
    if (Math.abs(camera.fov - fovT) > 0.05) {
        camera.fov += (fovT - camera.fov) * Math.min(1, dt * 9);
        camera.updateProjectionMatrix();
    }

    // 悬停亮星/行星 → 手型光标
    if (!ctrl.dragging && !tween && mouseActive) {
        canvas.classList.toggle('hoverStar', pickNamed() >= 0 || !!pickSolar());
    }

    renderer.render(scene, camera);

    if (firstFrame) {
        firstFrame = false;
        veil.classList.add('done');
        veil.dataset.done = '1';
    }
    fpsFrames++;
    fpsTime += dt;
    if (fpsTime >= 0.5) {
        fpsVal = Math.round(fpsFrames / fpsTime);
        fpsFrames = 0; fpsTime = 0;
        $('stats').textContent = `FPS ${fpsVal} · 恒星 ${(params.starCount / 10000).toFixed(0)} 万`;
    }
}
loop();
