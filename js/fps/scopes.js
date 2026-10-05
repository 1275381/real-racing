import * as THREE from 'three';
import { gunMaterials } from './gunTextures.js';

/* =====================================================================
   js/fps/scopes.js —— 瞄具系统（【枪械】组）
   ① SCOPES 数值表：guns.gd:69-80 移植 + iron 机瞄档（未装瞄具=iron）
   ② buildScopeMesh(kind)：viewmodel 镜身模型（挂枪顶导轨）
   ③ ScopeOverlay：高倍镜 DOM 分划覆盖层（自注入，红点/全息走镜内发光点
      模型、不走覆盖层； optic35/scope5/thermal/builtin 走覆盖层分划）
   纯程序化：贴图 Canvas、分划 Canvas 2D、样式全内联，零外部资源。
   ===================================================================== */

/* ==== 1. 瞄具表（guns.gd:69-80 移植；zooms = 可调倍率档，本期留字段不接滚轮） ==== */

export const SCOPES = {
    iron: {
        id: 'iron', name: '机瞄',
        desc: '1× · 准星直瞄 · 无附加镜片', price: 0,
        zoom: 1.0, kind: 'iron',
    },
    reddot: {
        id: 'reddot', name: '红点镜',
        desc: '1.5× · 单圈红点 · 快速获取', price: 700,
        zoom: 1.5, kind: 'reddot',
    },
    holo: {
        id: 'holo', name: '全息镜',
        desc: '1.5× · 全息方框绿点 · 视野宽', price: 900,
        zoom: 1.5, kind: 'holo',
    },
    optic35: {
        id: 'optic35', name: '3.5× 光学镜',
        desc: '3.5× · 密位十字 · 中距离精确', price: 1800,
        zoom: 3.5, kind: 'optic',
    },
    scope5: {
        id: 'scope5', name: '5× 密位镜',
        desc: '5×/8× 滚轮可调 · 暗角密位 · 远距离', price: 2800,
        zoom: 5.0, zooms: [5.0, 8.0], kind: 'sniper',
    },
    thermal: {
        id: 'thermal', name: '热成像镜',
        desc: '4× · 敌人热点高亮 · 夜战神器', price: 5200,
        zoom: 4.0, kind: 'thermal',
    },
};

/* id → 瞄具表（未知名回退机瞄） */
export function scopeById(id) {
    return SCOPES[id] || SCOPES.iron;
}

/* 是否高倍镜（zoom≥3 开镜隐枪模 + 走 DOM 分划，onfoot.gd:782 先例） */
export function isMagnified(scopeId) {
    return scopeById(scopeId).zoom >= 3;
}

/* ==== 1.5 屏幕空间发光点（红点/全息镜的瞄准点） ====
 * sizeAttenuation:false = 不随距离缩放，Sprite 以视口高度为基准投影，
 * scale 0.0048 ≈ 1080p 下 5px 亮点；AdditiveBlending 提饱和不污染深色；
 * depthTest 开（被枪身合理遮挡）但玻璃片不写深度，点在镜内清晰可见。
 * 写实度评审 #03i：原 0.0022 实心小球被实心镜筒端盖挡死，0 红色像素。 */
let _dotTex = null;
function dotTexture() {
    if (_dotTex) return _dotTex;
    const S = 32;
    const cv = document.createElement('canvas');
    cv.width = cv.height = S;
    const g = cv.getContext('2d');
    const grad = g.createRadialGradient(S / 2, S / 2, 0, S / 2, S / 2, S / 2);
    grad.addColorStop(0, 'rgba(255,255,255,1)');       // 白核保饱和
    grad.addColorStop(0.45, 'rgba(255,255,255,0.9)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
    _dotTex = new THREE.CanvasTexture(cv);
    return _dotTex;
}
function dotSprite(colorHex, x, y, z) {
    const mat = new THREE.SpriteMaterial({
        map: dotTexture(), color: new THREE.Color(colorHex),
        transparent: true, opacity: 0.95, depthWrite: false,
        blending: THREE.AdditiveBlending, sizeAttenuation: false,
    });
    const sp = new THREE.Sprite(mat);
    sp.position.set(x, y, z);
    sp.scale.set(0.0048, 0.0048, 1);
    sp.renderOrder = 10;                                // 晚于镜片玻璃
    return sp;
}

/* 圆角矩形轮廓（红点镜大方形圆角镜窗的框与玻璃用；中心在原点，XY 平面） */
function roundedRectShape(w, h, r) {
    const s = new THREE.Shape();
    const x = -w / 2, y = -h / 2;
    s.moveTo(x + r, y);
    s.lineTo(x + w - r, y);
    s.quadraticCurveTo(x + w, y, x + w, y + r);
    s.lineTo(x + w, y + h - r);
    s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    s.lineTo(x + r, y + h);
    s.quadraticCurveTo(x, y + h, x, y + h - r);
    s.lineTo(x, y + r);
    s.quadraticCurveTo(x, y, x + r, y);
    return s;
}

/* 红点镜护翼（参考图特征件）：单侧前弯弧形金属杆——样条管件根部埋入
 * 镜座后角，沿镜窗外侧爬升越过窗顶，再向镜口方向前弯收梢；两端球头封口
 * （TubeGeometry 端面开口朝斜前下，ADS 视角可见，必须封）。
 * side=±1 左右镜像；API 已在 lib/three.module.js 核对
 * （CatmullRomCurve3:35166 / TubeGeometry:40149）。 */
function scopeWing(M, side) {
    const pts = [
        new THREE.Vector3(side * 0.030, 0.034, 0.014),   // 根（埋进镜座）
        new THREE.Vector3(side * 0.036, 0.064, 0.012),   // 沿窗外侧爬升
        new THREE.Vector3(side * 0.038, 0.090, 0.003),   // 窗顶角外缘
        new THREE.Vector3(side * 0.036, 0.101, -0.012),  // 越过窗顶
        new THREE.Vector3(side * 0.030, 0.096, -0.027),  // 前弯端梢（镜口前方）
    ];
    const g = new THREE.Group();
    g.add(new THREE.Mesh(
        new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 24, 0.0035, 8, false),
        M.barrelMat));
    for (const p of [pts[0], pts[pts.length - 1]]) {
        const cap = new THREE.Mesh(new THREE.SphereGeometry(0.0035, 8, 6), M.barrelMat);
        cap.position.copy(p);
        g.add(cap);
    }
    return g;
}

/* ==== 2. buildScopeMesh(kind)：镜身模型 ====
 * 组原点 = 导轨接口面中心（gun.userData.opticAnchor 处），镜身向 −Z 伸出。
 * userData.sight = 瞄准线锚点 {y,z}（组本地）：GunView 据此重算 ADS 对准位。
 * 红点/全息的发光点用不受光照的 MeshBasicMaterial，开镜时直接可见。 */
export function buildScopeMesh(kind) {
    const M = gunMaterials();
    const root = new THREE.Group();
    root.name = 'scope';

    /* openEnded=true 开口短筒（镜圈不封端盖，镜内可透视——写实度评审：
     * 实心圆柱的端盖把红点/镜内空间整个挡死）；配 glassDisc 透镜玻璃 */
    const cylZ = (r, len, mat, x = 0, y = 0, z = 0, seg = 18, open = false) => {
        const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, len, seg, 1, open), mat);
        m.rotation.x = Math.PI / 2;
        m.position.set(x, y, z);
        return m;
    };
    /* 透镜玻璃：双面半透明片，不写深度（不挡镜内红点/分划） */
    const glassDisc = (r, x, y, z, opacity = 0.16) => {
        const m = new THREE.Mesh(
            new THREE.CircleGeometry(r, 20),
            new THREE.MeshBasicMaterial({
                color: 0x9fc4d8, transparent: true, opacity,
                side: THREE.DoubleSide, depthWrite: false,
            }));
        m.position.set(x, y, z);
        m.renderOrder = 8;
        return m;
    };
    const box = (w, h, d, mat, x = 0, y = 0, z = 0) => {
        const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
        m.position.set(x, y, z);
        return m;
    };
    /* 导轨卡扣（各镜通用底座） */
    const clampBase = (len = 0.044) => {
        const g = new THREE.Group();
        g.add(box(0.030, 0.008, len, M.boltMat, 0, 0.004, 0));
        g.add(box(0.034, 0.006, 0.010, M.boltMat, 0, 0.010, -len * 0.3));
        g.add(box(0.034, 0.006, 0.010, M.boltMat, 0, 0.010, len * 0.3));
        return g;
    };

    if (kind === 'reddot') {
        /* 红点镜 v2（照参考图重做）：
         * ① 增高架——导轨卡扣上加一级深色金属垫块，镜体明显架高：镜片中心
         *    y=0.072（高出导轨面 7.2cm，≈ 真实 0.5" riser + 高镜座比例），
         *    开镜视线（GunView._scopeLine）正好从镜片中心穿过，不贴机匣平视；
         * ② 大方形圆角镜窗——带真实镂空的环形拉伸框（沿用上轮 openEnded
         *    思路：框内无任何端盖封堵）+ 近全透淡色玻璃，透窗看靶道全干净；
         * ③ 左右前弯弧形金属护翼——scopeWing 样条管件（参考图最显眼特征）；
         * ④ 瞄准点 = 镜窗中心屏幕空间红点（sizeAttenuation:false 恒定像素
         *    尺寸 + AdditiveBlending，任何分辨率下 4-6px 饱和红点）；
         * ⑤ 装镜即隐机瞄——机瞄件可见性由 GunView._mountScope 统一处理。 */
        root.add(clampBase(0.052));                                          // 导轨卡扣
        root.add(box(0.038, 0.020, 0.050, M.barrelMat, 0, 0.016, 0.004));    // 增高架
        for (const sx of [-0.0195, 0.0195]) {                                // 架侧内六角螺栓
            for (const sz of [-0.013, 0.014]) {
                root.add(box(0.005, 0.009, 0.009, M.boltMat, sx, 0.016, sz));
            }
        }
        root.add(box(0.068, 0.028, 0.038, M.barrelMat, 0, 0.038, 0.002));    // 镜座（厚深色金属块）
        root.add(box(0.008, 0.012, 0.014, M.boltMat, 0.034, 0.038, 0.013));  // 亮度旋钮（右侧）
        /* 大方形圆角镜窗：外框环形拉伸体（真实镂空）+ 近全透淡色玻璃 */
        const winShape = roundedRectShape(0.070, 0.052, 0.013);
        winShape.holes.push(roundedRectShape(0.056, 0.040, 0.010));
        const winFrame = new THREE.Mesh(
            new THREE.ExtrudeGeometry(winShape, { depth: 0.010, bevelEnabled: false }),
            M.barrelMat);
        winFrame.position.set(0, 0.072, -0.009);                             // 框体 z −9..+1mm
        root.add(winFrame);
        const winGlass = new THREE.Mesh(
            new THREE.ShapeGeometry(roundedRectShape(0.056, 0.040, 0.010)),
            new THREE.MeshBasicMaterial({
                color: 0xaad0e2, transparent: true, opacity: 0.07,           // 淡色微反光近全透
                side: THREE.DoubleSide, depthWrite: false,                   // 不写深度：不挡红点
            }));
        winGlass.position.set(0, 0.072, -0.0075);
        winGlass.renderOrder = 8;
        root.add(winGlass);
        root.add(scopeWing(M, -1));                                          // 左护翼
        root.add(scopeWing(M, 1));                                           // 右护翼
        root.add(dotSprite('#ff2418', 0, 0.072, -0.002));                    // 镜窗中心红点
        root.userData.sight = { y: 0.072, z: -0.008 };                       // 瞄准线 = 镜片中心
    } else if (kind === 'holo') {
        /* 全息镜：方形视窗框 + 屏幕空间绿点 + 下部电池仓（红点镜同款处理） */
        root.add(clampBase(0.048));
        const win = box(0.050, 0.046, 0.006, M.receiverMat, 0, 0.036, -0.012);
        root.add(win);
        /* 视窗镂空感：前后面片用深色半透明玻璃（不写深度） */
        const glass = new THREE.Mesh(
            new THREE.PlaneGeometry(0.040, 0.036),
            new THREE.MeshBasicMaterial({ color: 0x0a1410, transparent: true, opacity: 0.30, side: THREE.DoubleSide, depthWrite: false }));
        glass.position.set(0, 0.036, -0.012);
        glass.renderOrder = 8;
        root.add(glass);
        root.add(dotSprite('#35ff6a', 0, 0.036, -0.006));
        const halo = new THREE.Mesh(                                     // 全息外框（发光线框感）
            new THREE.RingGeometry(0.0165, 0.018, 4, 1),
            new THREE.MeshBasicMaterial({ color: 0x2fdc60, transparent: true, opacity: 0.75, side: THREE.DoubleSide, depthWrite: false }));
        halo.position.set(0, 0.036, -0.0155);
        halo.rotation.z = Math.PI / 4;                                   // 方框对齐
        halo.renderOrder = 9;
        root.add(halo);
        root.add(box(0.026, 0.020, 0.036, M.polymerMat, 0, 0.010, 0.010)); // 电池仓
        root.userData.sight = { y: 0.036, z: -0.010 };
    } else if (kind === 'optic') {
        /* 3.5× 光学镜：直筒（开口）+ 物镜圈 + 密位分划板（镜内薄十字） */
        root.add(clampBase(0.050));
        root.add(cylZ(0.020, 0.120, M.receiverMat, 0, 0.036, -0.010, 18, true));
        root.add(cylZ(0.026, 0.030, M.receiverMat, 0, 0.036, -0.078, 18, true));   // 物镜筒
        root.add(cylZ(0.027, 0.005, M.boltMat, 0, 0.036, -0.092, 18, true));
        root.add(glassDisc(0.025, 0, 0.036, -0.090, 0.22));                        // 物镜玻璃
        root.add(cylZ(0.022, 0.026, M.receiverMat, 0, 0.036, 0.052, 18, true));    // 目镜筒
        root.add(cylZ(0.023, 0.005, M.boltMat, 0, 0.036, 0.064, 18, true));
        root.add(glassDisc(0.021, 0, 0.036, 0.062, 0.14));                         // 目镜玻璃
        root.add(box(0.008, 0.012, 0.016, M.boltMat, 0.022, 0.030, 0.010)); // 塔轮
        root.add(box(0.008, 0.010, 0.014, M.boltMat, 0, 0.052, 0.006));  // 顶塔轮
        /* 镜内分划片：细十字（贴图 16×16 十字，透明底） */
        const reticleTex = crossReticleTexture('#cfe3d4');
        const ret = new THREE.Mesh(
            new THREE.PlaneGeometry(0.036, 0.036),
            new THREE.MeshBasicMaterial({ map: reticleTex, transparent: true, depthWrite: false }));
        ret.position.set(0, 0.036, 0.040);
        ret.renderOrder = 9;
        root.add(ret);
        root.userData.sight = { y: 0.036, z: 0.052 };
    } else if (kind === 'sniper') {
        /* 5×/6× 密位镜：长筒（开口）大物镜 + 玻璃 + 镜内密位分划 */
        root.add(clampBase(0.056));
        root.add(cylZ(0.021, 0.150, M.receiverMat, 0, 0.040, 0.006, 18, true));
        root.add(cylZ(0.030, 0.052, M.receiverMat, 0, 0.040, -0.096, 18, true));   // 大物镜
        root.add(cylZ(0.031, 0.006, M.boltMat, 0, 0.040, -0.120, 18, true));
        root.add(glassDisc(0.029, 0, 0.040, -0.118, 0.22));                        // 物镜玻璃
        root.add(cylZ(0.024, 0.034, M.receiverMat, 0, 0.040, 0.096, 18, true));    // 目镜筒
        root.add(cylZ(0.025, 0.005, M.boltMat, 0, 0.040, 0.112, 18, true));
        root.add(glassDisc(0.023, 0, 0.040, 0.110, 0.14));                         // 目镜玻璃
        /* 镜内密位分划：十字 + 刻点（暗色线） */
        const ret = new THREE.Mesh(
            new THREE.PlaneGeometry(0.044, 0.044),
            new THREE.MeshBasicMaterial({ map: crossReticleTexture('#9fb8a6', true), transparent: true, depthWrite: false }));
        ret.position.set(0, 0.040, 0.084);
        ret.renderOrder = 9;
        root.add(ret);
        root.add(box(0.009, 0.014, 0.018, M.boltMat, 0.024, 0.034, 0.030)); // 塔轮
        root.add(box(0.009, 0.010, 0.016, M.boltMat, 0, 0.058, 0.020));
        root.userData.sight = { y: 0.040, z: 0.096 };
    } else if (kind === 'thermal') {
        /* 热成像镜：方盒机身 + 发绿光物镜 + 侧置屏幕 */
        root.add(clampBase(0.050));
        root.add(box(0.046, 0.052, 0.150, M.polymerMat, 0, 0.040, -0.012));
        const lens = new THREE.Mesh(
            new THREE.CircleGeometry(0.017, 20),
            new THREE.MeshBasicMaterial({ color: 0x1fd97a, transparent: true, opacity: 0.9 }));
        lens.position.set(0, 0.040, -0.088);
        root.add(lens);
        root.add(box(0.050, 0.010, 0.020, M.boltMat, 0, 0.040, -0.086)); // 物镜遮光罩圈
        const scr = new THREE.Mesh(
            new THREE.PlaneGeometry(0.020, 0.016),
            new THREE.MeshBasicMaterial({ color: 0x0d3320 }));
        scr.rotation.y = -Math.PI / 2;
        scr.position.set(-0.024, 0.046, 0.012);                          // 左侧小监视屏
        root.add(scr);
        root.add(box(0.008, 0.012, 0.014, M.boltMat, 0.026, 0.030, 0.020));
        root.userData.sight = { y: 0.040, z: 0.056 };
    } else {
        /* iron / 未知：不挂镜身模型 */
        return null;
    }
    return root;
}

/* 十字分划小贴图（镜内分划板用；mildot=true 加刻点） */
function crossReticleTexture(color, mildot = false) {
    const S = 128, c = 64;
    const cv = document.createElement('canvas');
    cv.width = cv.height = S;
    const g = cv.getContext('2d');
    g.strokeStyle = color;
    g.fillStyle = color;
    g.lineWidth = 2;
    g.globalAlpha = 0.9;
    /* 中心留缺口十字 */
    g.beginPath();
    g.moveTo(c, 4); g.lineTo(c, c - 9);
    g.moveTo(c, c + 9); g.lineTo(c, S - 4);
    g.moveTo(4, c); g.lineTo(c - 9, c);
    g.moveTo(c + 9, c); g.lineTo(S - 4, c);
    g.stroke();
    if (mildot) {
        for (let i = 1; i <= 3; i++) {
            const d = i * 13;
            g.beginPath();
            g.arc(c - d, c, 1.8, 0, 7); g.fill();
            g.beginPath();
            g.arc(c + d, c, 1.8, 0, 7); g.fill();
            g.beginPath();
            g.arc(c, c - d, 1.8, 0, 7); g.fill();
            g.beginPath();
            g.arc(c, c + d, 1.8, 0, 7); g.fill();
        }
    }
    const t = new THREE.CanvasTexture(cv);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
}

/* ==== 3. ScopeOverlay：高倍镜 DOM 分划覆盖层（自注入 document.body） ====
 * 层级约定：z-index 13（canvas < hud-root 10 < 本层 13 < 菜单 20 < 大厅 30）。
 * show(kind) 后每帧由 GunView 调 setAds(k) 调透明度；kind 分划画一次/一次 resize。
 * setThermal(on)：绿敏夜视风 —— backdrop 灰度化 + 绿色染色（DOM 滤镜，不做后处理）；
 *   敌热点材质覆染归敌兵系统（enemies.js），本层不越权。 */
export class ScopeOverlay {
    constructor(opts = {}) {
        this._kind = null;
        this._ads = 0;
        this._dpr = Math.min(window.devicePixelRatio || 1, 2);

        /* ---- 自注入 DOM ---- */
        const root = this._root = document.createElement('div');
        root.id = 'fps-scope-overlay';
        Object.assign(root.style, {
            position: 'fixed', inset: '0', zIndex: '13',
            pointerEvents: 'none', display: 'none', opacity: '0',
        });
        /* 分划画布 */
        const cv = this._cv = document.createElement('canvas');
        Object.assign(cv.style, { position: 'absolute', inset: '0', width: '100%', height: '100%' });
        root.appendChild(cv);
        /* 热成像染色层：backdrop 灰度 + 绿染（display 由 setThermal 控制） */
        const tint = this._tint = document.createElement('div');
        Object.assign(tint.style, {
            position: 'absolute', inset: '0', display: 'none',
            backdropFilter: 'grayscale(1) brightness(1.28) contrast(1.12)',
            WebkitBackdropFilter: 'grayscale(1) brightness(1.28) contrast(1.12)',
            background: 'radial-gradient(circle at 50% 50%, rgba(38,170,88,0.16) 0%, rgba(10,60,30,0.42) 78%, rgba(4,26,12,0.72) 100%)',
        });
        root.appendChild(tint);
        /* 倍率角标 */
        const zoomTag = this._zoomTag = document.createElement('div');
        Object.assign(zoomTag.style, {
            position: 'absolute', right: '18%', bottom: '16%',
            color: 'rgba(190,220,196,0.75)', font: '600 13px/1 monospace',
            letterSpacing: '0.12em', textShadow: '0 0 6px rgba(0,0,0,0.9)',
        });
        root.appendChild(zoomTag);
        (opts.parent || document.body).appendChild(root);

        /* ---- 尺寸自适应 ---- */
        this._onResize = () => { this._resize(); this._draw(); };
        window.addEventListener('resize', this._onResize);
    }

    /* 当前分划 kind（null=隐藏中；GunView 判断是否需要重 show 用） */
    get kind() { return this._kind; }

    /* 显示分划（kind ∈ SCOPES 的 kind；非高倍 kind 直接隐藏） */
    show(kind, zoomLabel = '') {
        this._kind = kind;
        this._zoomLabel = zoomLabel;
        if (kind === 'iron' || kind === 'reddot' || kind === 'holo' || !kind) {
            this.hide();
            return;
        }
        this._resize();
        this._draw();
        this._root.style.display = 'block';
    }

    /* 每帧喂开镜进度：0..1 → 淡入 + 控制显示 */
    setAds(k) {
        this._ads = k;
        const vis = k > 0.02 && this._kind && this._root.style.display !== 'none';
        if (!vis) { this._root.style.opacity = '0'; return; }
        /* 0.5 起淡入、0.9 全显（与隐枪阈值 ads>0.9 对齐） */
        const op = Math.min(1, Math.max(0, (k - 0.5) / 0.4));
        this._root.style.opacity = op.toFixed(3);
    }

    /* 热成像绿敏风开关 */
    setThermal(on) {
        this._tint.style.display = on ? 'block' : 'none';
    }

    hide() {
        this._root.style.display = 'none';
        this._root.style.opacity = '0';
        this._kind = null;
        this.setThermal(false);
    }

    dispose() {
        window.removeEventListener('resize', this._onResize);
        if (this._root && this._root.parentNode) this._root.parentNode.removeChild(this._root);
    }

    /* ---- 内部 ---- */

    _resize() {
        this._w = Math.max(2, window.innerWidth | 0);
        this._h = Math.max(2, window.innerHeight | 0);
        this._cv.width = this._w * this._dpr;
        this._cv.height = this._h * this._dpr;
        this._cv.getContext('2d').setTransform(this._dpr, 0, 0, this._dpr, 0, 0);
    }

    _draw() {
        const g = this._cv.getContext('2d');
        const w = this._w, h = this._h, cx = w / 2, cy = h / 2;
        g.clearRect(0, 0, w, h);
        if (!this._kind) return;
        if (this._kind === 'optic') this._drawMilCross(g, cx, cy, h, 'rgba(16,22,16,0.92)', false);
        else if (this._kind === 'sniper') this._drawSniper(g, cx, cy, w, h);
        else if (this._kind === 'thermal') this._drawThermal(g, cx, cy, w, h);
        this._zoomTag.textContent = this._zoomLabel || '';
    }

    /* 密位十字（optic35）：细黑十字 + 刻点，中心留缺口 */
    _drawMilCross(g, cx, cy, h, style, dots) {
        const arm = h * 0.46, gap = 12, step = h * 0.055;
        g.strokeStyle = style;
        g.fillStyle = style;
        g.lineWidth = 1.6;
        g.beginPath();
        g.moveTo(cx, cy - gap); g.lineTo(cx, cy - arm);
        g.moveTo(cx, cy + gap); g.lineTo(cx, cy + arm);
        g.moveTo(cx - gap, cy); g.lineTo(cx - arm, cy);
        g.moveTo(cx + gap, cy); g.lineTo(cx + arm, cy);
        g.stroke();
        if (dots) {
            for (let i = 1; i <= 4; i++) {
                const d = step * i + gap;
                for (const [dx, dy] of [[0, -d], [0, d], [-d, 0], [d, 0]]) {
                    g.beginPath();
                    g.arc(cx + dx, cy + dy, 2.4, 0, 7);
                    g.fill();
                }
            }
        }
    }

    /* 5×/6× 密位镜：暗角大圆 + 粗柱密位线 + 刻点 + 视差视距刻度 */
    _drawSniper(g, cx, cy, w, h) {
        const R = Math.min(w, h) * 0.44;
        /* 暗角：圆外全黑（软边） */
        g.fillStyle = 'rgba(2,4,2,0.985)';
        g.beginPath();
        g.rect(0, 0, w, h);
        g.arc(cx, cy, R, 0, Math.PI * 2, true);
        g.fill();
        /* 镜口内暗环 */
        const rg = g.createRadialGradient(cx, cy, R * 0.86, cx, cy, R);
        rg.addColorStop(0, 'rgba(0,0,0,0)');
        rg.addColorStop(1, 'rgba(0,0,0,0.75)');
        g.fillStyle = rg;
        g.beginPath();
        g.arc(cx, cy, R, 0, Math.PI * 2);
        g.fill();
        /* 密位柱：从边缘伸向中心的粗黑柱（四向） */
        g.strokeStyle = 'rgba(6,10,6,0.95)';
        g.fillStyle = 'rgba(6,10,6,0.95)';
        const post = R * 0.62;
        g.lineWidth = 7;
        g.beginPath();
        g.moveTo(cx, cy - R); g.lineTo(cx, cy - post);
        g.moveTo(cx, cy + R); g.lineTo(cx, cy + post);
        g.moveTo(cx - R, cy); g.lineTo(cx - post, cy);
        g.moveTo(cx + R, cy); g.lineTo(cx + post, cy);
        g.stroke();
        /* 细十字 + 刻点（柱尖到中心，密位间隔递增感） */
        g.lineWidth = 1.4;
        g.beginPath();
        g.moveTo(cx, cy - post); g.lineTo(cx, cy - 14);
        g.moveTo(cx, cy + 14); g.lineTo(cx, cy + post);
        g.moveTo(cx - post, cy); g.lineTo(cx - 14, cy);
        g.moveTo(cx + 14, cy); g.lineTo(cx + post, cy);
        g.stroke();
        for (let i = 1; i <= 4; i++) {
            const d = R * 0.11 * i + 14;
            for (const [dx, dy] of [[0, -d], [0, d], [-d, 0], [d, 0]]) {
                if (Math.abs(dx) > post && dy === 0) continue;
                if (Math.abs(dy) > post && dx === 0) continue;
                g.beginPath();
                g.arc(cx + dx, cy + dy, i <= 2 ? 2.2 : 3.0, 0, 7);
                g.fill();
            }
        }
        /* 密位数字（下柱旁 2/4/6） */
        g.fillStyle = 'rgba(180,200,182,0.6)';
        g.font = '10px monospace';
        g.fillText('2', cx + 6, cy + R * 0.11 * 2 + 17);
        g.fillText('4', cx + 6, cy + R * 0.11 * 4 + 19);
    }

    /* 热成像：亮色破折分划 + 中央捕捉框（白热风格） */
    _drawThermal(g, cx, cy, w, h) {
        const arm = Math.min(w, h) * 0.18;
        g.strokeStyle = 'rgba(235,255,240,0.92)';
        g.fillStyle = 'rgba(235,255,240,0.92)';
        g.lineWidth = 1.8;
        /* 四角破折线 */
        g.beginPath();
        for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
            g.moveTo(cx + sx * 26, cy + sy * 26);
            g.lineTo(cx + sx * 26 + sx * 14, cy + sy * 26);
            g.moveTo(cx + sx * 26, cy + sy * 26);
            g.lineTo(cx + sx * 26, cy + sy * 26 + sy * 14);
        }
        g.stroke();
        /* 中心点划十字 */
        g.beginPath();
        for (const [sx, sy] of [[0, -1], [0, 1], [-1, 0], [1, 0]]) {
            g.moveTo(cx + sx * 8, cy + sy * 8);
            g.lineTo(cx + sx * arm, cy + sy * arm);
        }
        g.stroke();
        g.beginPath();
        g.arc(cx, cy, 2.2, 0, 7);
        g.fill();
    }
}
