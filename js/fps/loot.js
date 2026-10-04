/* =====================================================================
 * js/fps/loot.js —— 战利品系统（【战利品】组）
 * 七档品质掉落表 + 八类搜刮容器（程序化建模）+ 搜索状态机 + 掉落物可视化。
 *
 * 驱动链（interfaces 约定，本模块不监听任何键盘）：
 *   mission.update 每帧调 loot.update(dt, player.eyePos(), mission._fHeld)
 *   —— F 按住态全靠第三参喂入，Mission 是唯一 KeyF 持有者。
 * 搜索提示/进度自注入 #fps-search-prompt（内联样式 z-index 12）渲染，
 * 不借用 hud.setIntelProgress（该环归 mission 情报专用，消除双写）。
 *
 * 导出：RARITY / ITEM_POOL / CONTAINER_TYPES / rollLoot / LootManager
 * ===================================================================== */
import * as THREE from 'three';

/* ==== 1. RARITY：七档品质表（下标 0-6 = 白绿蓝紫金红彩，rarityTable 修订版） ====
 * wildW/centerW = 荒野/中心分区基础权重（%），先乘容器 bias 偏置（内×4/外÷4）
 * 再取列。红/彩荒野权重 0 = 硬锁仅中心出。value 区间内均匀取整到 10 位。 */
export const RARITY = [
    { id: 0, name: '白·普通', color: '#d8d8d8', vMin: 800, vMax: 2500, wildW: 55, centerW: 15 },
    { id: 1, name: '绿·优良', color: '#4caf50', vMin: 2500, vMax: 8000, wildW: 28, centerW: 22 },
    { id: 2, name: '蓝·稀有', color: '#2f7fd8', vMin: 8000, vMax: 25000, wildW: 12, centerW: 26 },
    { id: 3, name: '紫·史诗', color: '#9a4fd8', vMin: 25000, vMax: 80000, wildW: 2, centerW: 20 },
    { id: 4, name: '金·传说', color: '#d8a12f', vMin: 80000, vMax: 250000, wildW: 1, centerW: 12 },
    { id: 5, name: '红·旷世', color: '#d83a2f', vMin: 250000, vMax: 800000, wildW: 0, centerW: 4 },
    { id: 6, name: '彩·至臻', color: '#e84fd8', vMin: 800000, vMax: 2000000, wildW: 0, centerW: 1, glow: true },
];

/* ==== 2. ITEM_POOL：变卖物池（按品质档分组；kind 供医疗柜过滤；shape 指定专属外形） ====
 * kind：valuables 贵重 / tech 电子 / medical 医疗 / parts 工具件 / food 食品 /
 *       gear 装备 / docs 文书 / misc 杂项 */
export const ITEM_POOL = [
    /* 0 白·普通 */
    [
        { n: '螺丝钉包', icon: '🔩', kind: 'parts' },
        { n: '旧电池', icon: '🔋', kind: 'tech' },
        { n: '绷带', icon: '🩹', kind: 'medical' },
        { n: '帆布碎片', icon: '🧵', kind: 'misc' },
        { n: '军用口粮', icon: '🥫', kind: 'food' },
        { n: '润滑油罐', icon: '🛢️', kind: 'parts' },
    ],
    /* 1 绿·优良 */
    [
        { n: '防毒面具', icon: '😷', kind: 'gear' },
        { n: '军用手电', icon: '🔦', kind: 'gear' },
        { n: '精密零件', icon: '⚙️', kind: 'parts' },
        { n: '咖啡豆', icon: '☕', kind: 'food' },
        { n: '止痛药', icon: '💊', kind: 'medical' },
        { n: '多功能扳手', icon: '🔧', kind: 'parts' },
    ],
    /* 2 蓝·稀有 */
    [
        { n: '急救包', icon: '⛑️', kind: 'medical' },
        { n: '军用电池组', icon: '🔌', kind: 'tech' },
        { n: '独立声卡', icon: '🎛️', kind: 'tech' },
        { n: '矿卡', icon: '🖥️', kind: 'tech' },
        { n: '战术护目镜', icon: '🥽', kind: 'gear' },
    ],
    /* 3 紫·史诗 */
    [
        { n: '医用无人机件', icon: '🚁', kind: 'medical' },
        { n: '加密硬盘', icon: '💾', kind: 'tech' },
        { n: '热瞄组件', icon: '🔭', kind: 'tech' },
        { n: '军用电路板', icon: '📟', kind: 'tech' },
        { n: '实验药剂', icon: '🧪', kind: 'medical' },
    ],
    /* 4 金·传说 */
    [
        { n: '夜视仪', icon: '👁️', kind: 'gear' },
        { n: 'AI 芯片组', icon: '🧠', kind: 'tech' },
        { n: '金条', icon: '🪙', kind: 'valuables', shape: 'bar' },
        { n: '名表', icon: '⌚', kind: 'valuables', shape: 'watch' },
        { n: '陈年名酒', icon: '🍾', kind: 'valuables' },
    ],
    /* 5 红·旷世（仅中心出） */
    [
        { n: '曼德尔砖', icon: '🧱', kind: 'valuables', shape: 'brick' },
        { n: '卫星电话', icon: '📡', kind: 'tech' },
        { n: '机密卷宗', icon: '📜', kind: 'docs' },
    ],
    /* 6 彩·至臻（仅中心保险箱，呼吸辉光） */
    [
        { n: '收藏机械表', icon: '⏱️', kind: 'valuables', shape: 'watch' },
        { n: '冷钱包', icon: '💳', kind: 'tech' },
        { n: '龙纹雕像', icon: '🐉', kind: 'valuables', shape: 'statue' },
    ],
];

/* ==== 3. CONTAINER_TYPES：八类容器（interfaces 原表） ====
 * searchT 秒 / bias 偏置档（内×4 外÷4）/ kind 限定产物类别 /
 * zones 建议分区（'both' | 'center'，摆放约束归 CONTAINER_SPOTS）。 */
export const CONTAINER_TYPES = {
    crate: { name: '木箱', searchT: 1.6, bias: [0, 1], zones: 'both' },
    ammo: { name: '弹药箱', searchT: 2.0, bias: [1, 2], zones: 'both' },
    medcab: { name: '医疗柜', searchT: 1.8, bias: [0, 1, 2], kind: 'medical', zones: 'both' },
    toolbox: { name: '工具柜', searchT: 2.0, bias: [1, 2], zones: 'both' },
    duffle: { name: '行李袋', searchT: 1.6, bias: [2, 3], zones: 'both' },
    drawer: { name: '抽屉柜', searchT: 1.8, bias: [0, 1], zones: 'both' },
    safe: { name: '保险箱', searchT: 2.6, bias: [4, 5, 6], zones: 'center' },
    rack: { name: '军火库', searchT: 2.4, bias: [3, 4, 5], zones: 'center' },
};

/* 容器占地（碰撞 hx/hz/h，半宽制）与掉落物弹出高度 pop */
const FOOTPRINT = {
    crate: { hx: 0.50, hz: 0.34, h: 0.60, pop: 0.85 },
    ammo: { hx: 0.38, hz: 0.25, h: 0.42, pop: 0.62 },
    medcab: { hx: 0.42, hz: 0.23, h: 1.18, pop: 1.45 },
    toolbox: { hx: 0.47, hz: 0.25, h: 1.05, pop: 1.30 },
    duffle: { hx: 0.56, hz: 0.23, h: 0.45, pop: 0.70 },
    drawer: { hx: 0.33, hz: 0.27, h: 0.95, pop: 1.20 },
    safe: { hx: 0.38, hz: 0.34, h: 0.85, pop: 1.10 },
    rack: { hx: 1.07, hz: 0.32, h: 1.52, pop: 1.75 },
};

/* 开盖动画规格（lid 部件命名 lootLid；'zpos' 为抽屉平移，其余为转轴角度 rad） */
const OPEN_SPECS = {
    crate: { axis: 'x', angle: -1.95 },
    ammo: { axis: 'x', angle: -1.95 },
    medcab: { axis: 'y', angle: -1.9 },
    toolbox: { axis: 'y', angle: -1.9 },
    duffle: { axis: 'x', angle: -2.3 },
    drawer: { axis: 'zpos', dist: 0.34 },
    safe: { axis: 'y', angle: 1.9 },
    rack: { axis: 'x', angle: -1.6 },   // 顶铰下翻闸门：−1.6 rad ≈ 贴平（−2.0 会翘过水平位）
};

/* ==== 4. 加权随机与 rollLoot ====
 * 权重 = RARITY[档][分区列] ×（bias 内×4 / 外÷4）；分区列取 'center' → centerW，
 * 其余一律 wildW。python3 复核：safe center → 金 54.1%/红 18.0%/彩 4.5%、
 * 单件期望 ≈₵251k；荒野紫经 duffle 偏置 10.4%。 */
let _uidSeq = 0;
const nextUid = (p) => `${p}_${(++_uidSeq).toString(36)}`;

function _rollRarity(zone, bias) {
    const col = zone === 'center' ? 'centerW' : 'wildW';
    const ws = RARITY.map((r, i) => {
        const w = r[col];
        if (!w) return 0;
        return bias.indexOf(i) >= 0 ? w * 4 : w / 4;
    });
    let total = 0;
    for (const w of ws) total += w;
    let roll = Math.random() * total;
    for (let i = 0; i < ws.length; i++) {
        roll -= ws[i];
        if (roll < 0) return i;
    }
    return 0;
}

function _pickItem(rarity, kind) {
    const list = ITEM_POOL[rarity] || ITEM_POOL[0];
    if (kind) {
        const f = list.filter((it) => it.kind === kind);
        if (f.length) return f[(Math.random() * f.length) | 0];
    }
    return list[(Math.random() * list.length) | 0];
}

/* 搜刮单件产出：{uid,name,rarity:0..6,value,kind,icon,shape}
 * forceRarity（可选附加参）：__fps.give(rarityId) 直塞背包用，省略走权重。 */
export function rollLoot(zone, containerType, forceRarity) {
    const def = CONTAINER_TYPES[containerType] || null;
    const bias = def ? def.bias : [0, 1, 2, 3];
    const r = (forceRarity === 0 || forceRarity)
        ? Math.max(0, Math.min(6, forceRarity | 0))
        : _rollRarity(zone, bias);
    const rar = RARITY[r] || RARITY[0];
    const pool = _pickItem(r, def && def.kind);
    const value = Math.round((rar.vMin + Math.random() * (rar.vMax - rar.vMin)) / 10) * 10;
    return {
        uid: nextUid('it'), name: pool.n, rarity: r, value,
        kind: pool.kind, icon: pool.icon, shape: pool.shape,
    };
}

/* ==== 5. 共享材质与程序化贴图（零外部资源；贴图底色做亮、由材质 color 乘色） ==== */
let _M = null;      // 材质单例
let _T = null;      // 贴图单例

function _canvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return [c, c.getContext('2d')];
}

function _texWood() {   // 三板拼接 + 木纹丝 + 板缝钉头
    if (_T && _T.wood) return _T.wood;
    const S = 192;
    const [c, g] = _canvas(S, S);
    g.fillStyle = '#b3905e';
    g.fillRect(0, 0, S, S);
    for (let r = 0; r < 3; r++) {
        const y0 = r * S / 3;
        const tone = 0.86 + Math.random() * 0.22;
        g.fillStyle = `rgba(${179 * tone | 0},${144 * tone | 0},${94 * tone | 0},0.6)`;
        g.fillRect(0, y0, S, S / 3 - 3);
        g.fillStyle = 'rgba(58,42,24,0.9)';                       // 板缝
        g.fillRect(0, y0 + S / 3 - 3, S, 3);
        for (let i = 0; i < 24; i++) {                            // 木纹
            g.strokeStyle = `rgba(${96 + Math.random() * 46 | 0},${72 + Math.random() * 34 | 0},40,${0.1 + Math.random() * 0.2})`;
            g.lineWidth = 1 + Math.random() * 1.6;
            const y = y0 + 4 + Math.random() * (S / 3 - 10);
            g.beginPath(); g.moveTo(0, y);
            g.bezierCurveTo(S * 0.3, y + (Math.random() - 0.5) * 7, S * 0.7, y + (Math.random() - 0.5) * 7, S, y);
            g.stroke();
        }
    }
    g.fillStyle = 'rgba(58,42,24,0.5)';                           // 端缝
    g.fillRect(S / 3 - 1, 0, 2, S);
    g.fillRect(2 * S / 3 - 1, 0, 2, S);
    g.fillStyle = 'rgba(40,30,18,0.85)';                          // 钉头
    for (let i = 0; i < 8; i++) {
        g.beginPath();
        g.arc((i % 4) * S / 4 + S / 8, (i < 4 ? 6 : S - 6), 2.2, 0, 7);
        g.fill();
    }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    if (!_T) _T = {};
    _T.wood = t;
    return t;
}

function _texMetal() {  // 中性亮灰底 + 磨损噪点 + 划痕（材质 color 乘出橄榄/钢灰/墨绿）
    if (_T && _T.metal) return _T.metal;
    const S = 128;
    const [c, g] = _canvas(S, S);
    g.fillStyle = '#c6c8c0';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 1100; i++) {
        const v = Math.random();
        g.fillStyle = `rgba(${v > 0.5 ? 255 : 40},${v > 0.5 ? 255 : 44},${v > 0.5 ? 250 : 40},${0.05 + Math.random() * 0.12})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.4, 1.4);
    }
    for (let i = 0; i < 12; i++) {                                // 划痕
        g.strokeStyle = `rgba(${Math.random() > 0.5 ? '235,235,228' : '52,56,50'},${0.14 + Math.random() * 0.16})`;
        g.lineWidth = 0.8 + Math.random();
        const x = Math.random() * S, y = Math.random() * S;
        g.beginPath(); g.moveTo(x, y);
        g.lineTo(x + (Math.random() - 0.5) * S * 0.7, y + (Math.random() - 0.5) * S * 0.7);
        g.stroke();
    }
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.colorSpace = THREE.SRGBColorSpace;
    if (!_T) _T = {};
    _T.metal = t;
    return t;
}

function _texGlow() {   // 掉落物辉光径向渐变（Sprite 用，白底由材质 color 染）
    if (_T && _T.glow) return _T.glow;
    const S = 64;
    const [c, g] = _canvas(S, S);
    const grad = g.createRadialGradient(S / 2, S / 2, 2, S / 2, S / 2, S / 2);
    grad.addColorStop(0, 'rgba(255,255,255,0.95)');
    grad.addColorStop(0.35, 'rgba(255,255,255,0.42)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
    const t = new THREE.CanvasTexture(c);
    if (!_T) _T = {};
    _T.glow = t;
    return t;
}

function mats() {
    if (_M) return _M;
    const wood = _texWood(), metal = _texMetal();
    const M = (opts) => new THREE.MeshStandardMaterial(Object.assign({ roughness: 0.85, metalness: 0.08 }, opts));
    _M = {
        wood: M({ color: 0xffffff, map: wood }),
        woodDark: M({ color: 0x9a8468, map: wood, roughness: 0.9 }),
        olive: M({ color: 0x6d7c56, map: metal, metalness: 0.4, roughness: 0.55 }),
        oliveDark: M({ color: 0x525f43, map: metal, metalness: 0.4, roughness: 0.6 }),
        gray: M({ color: 0x8b9095, map: metal, metalness: 0.55, roughness: 0.5 }),
        steel: M({ color: 0x4a5058, map: metal, metalness: 0.75, roughness: 0.42 }),
        white: M({ color: 0xdcd9d0, roughness: 0.55 }),
        red: M({ color: 0xc0392e, roughness: 0.5 }),
        orange: M({ color: 0xc46828, map: metal, metalness: 0.45, roughness: 0.5 }),
        orangeDark: M({ color: 0x8f4a1c, map: metal, metalness: 0.45, roughness: 0.55 }),
        fabric: M({ color: 0x6f7c5c, roughness: 1.0 }),
        fabricDark: M({ color: 0x515c44, roughness: 1.0 }),
        inner: M({ color: 0x15171a, roughness: 0.95 }),
        paper: M({ color: 0xd3caa9, roughness: 0.9 }),
        gold: M({ color: 0xe6b83e, metalness: 0.95, roughness: 0.26 }),
        brick: M({ color: 0xb04a32, roughness: 0.6 }),
        patina: M({ color: 0x7fae7a, metalness: 0.8, roughness: 0.35 }),
        latchOn: new THREE.MeshStandardMaterial({ color: 0x2a2013, emissive: 0xffb35c, emissiveIntensity: 1.35, roughness: 0.4 }),
        latchOff: new THREE.MeshStandardMaterial({ color: 0x2c2c28, roughness: 0.7 }),
    };
    return _M;
}

/* ==== 6. 容器模板：八类外观（每类建一次，实例 clone 共享几何/材质） ====
 * 每模板必产：lootLid（开盖动件，userData.open/home 纯数字 JSON 安全）+
 * lootLatch（琥珀搜寻指示灯）+ 涂装铭牌（类型色识别带 + 模板喷字——写实度
 * 评审 #05：未搜状态可读性，军火库黄黑警示条等）。 */

let _TPL = null;

/* 类型识别色（铭牌识别带用；与场景材质色系同族） */
const TYPE_ACCENT = {
    crate: '#c9a36a', ammo: '#a8c25c', medcab: '#e05252', toolbox: '#e08a2e',
    duffle: '#8ba06a', drawer: '#9aa2ad', safe: '#d8a12f', rack: '#e8c14a',
};

let _plaqueTexCache = {};
function _plaqueTex(type) {
    if (_plaqueTexCache[type]) return _plaqueTexCache[type];
    const W = 128, H = 40;
    const [c, g] = _canvas(W, H);
    g.fillStyle = 'rgba(14,16,12,0.88)';
    g.fillRect(0, 0, W, H);
    /* 左端类型色警示带（斜条纹，军火库双密度） */
    const acc = TYPE_ACCENT[type] || '#ffb35c';
    g.save();
    g.beginPath();
    g.rect(2, 2, 30, H - 4);
    g.clip();
    g.fillStyle = acc;
    g.fillRect(2, 2, 30, H - 4);
    g.fillStyle = 'rgba(10,10,8,0.85)';
    const step = type === 'rack' ? 8 : 12;
    for (let x = -H; x < 34; x += step) {
        g.beginPath();
        g.moveTo(x, H + 2); g.lineTo(x + H + 4, -2);
        g.lineTo(x + H + 4 + 4, -2); g.lineTo(x + 4, H + 2);
        g.closePath(); g.fill();
    }
    g.restore();
    /* 模板喷字（stencil 风：大写间距字 + 描边） */
    const label = (CONTAINER_TYPES[type] && CONTAINER_TYPES[type].name) || type;
    g.font = 'bold 17px Menlo, Consolas, monospace';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.lineWidth = 3;
    g.strokeStyle = 'rgba(0,0,0,0.8)';
    g.strokeText(label, 80, H / 2 + 1);
    g.fillStyle = acc;
    g.fillText(label, 80, H / 2 + 1);
    g.strokeStyle = 'rgba(216,222,210,0.35)';
    g.lineWidth = 1;
    g.strokeRect(0.5, 0.5, W - 1, H - 1);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 4;
    _plaqueTexCache[type] = t;
    return t;
}

/* 涂装铭牌：无光照 MeshBasicMaterial（夜间亦读得出），贴在模板正面/门板 */
function _plaque(type, w, h, x, y, z) {
    const m = new THREE.Mesh(
        new THREE.PlaneGeometry(w, h),
        new THREE.MeshBasicMaterial({ map: _plaqueTex(type), transparent: true }));
    m.position.set(x, y, z);
    return m;
}

function _tpls() {
    if (_TPL) return _TPL;
    const M = mats();
    /* 盒体帮助函数：Box 加进父级并投影 */
    const B = (p, w, h, d, mat, x = 0, y = 0, z = 0) => {
        const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
        m.position.set(x, y, z);
        m.castShadow = m.receiveShadow = true;
        p.add(m);
        return m;
    };
    /* 圆柱帮助函数（可指定欧拉角） */
    const C = (p, rT, rB, h, mat, x = 0, y = 0, z = 0, seg = 12, rx = 0, rz = 0) => {
        const m = new THREE.Mesh(new THREE.CylinderGeometry(rT, rB, h, seg), mat);
        m.position.set(x, y, z);
        m.rotation.set(rx, 0, rz);
        m.castShadow = m.receiveShadow = true;
        p.add(m);
        return m;
    };
    /* 开盖动件：挂开合规格 + 家位（纯数字，clone 走 JSON 序列化安全） */
    const lid = (open) => {
        const L = new THREE.Group();
        L.name = 'lootLid';
        L.userData.open = Object.assign({}, open);
        return L;
    };
    const seal = (home) => { home.userData.home = { x: home.position.x, y: home.position.y, z: home.position.z }; };
    /* 琥珀搜寻锁扣（评审 #05：加大一档，15-20m 外可辨；另有呼吸辉光信标兜底） */
    const latch = (p, x, y, z) => {
        const m = B(p, 0.11, 0.07, 0.045, M.latchOn, x, y, z);
        m.name = 'lootLatch';
        return m;
    };

    const T = {};

    /* -- 木箱：三板木身 + 双铁箍 + 后铰链盖 -- */
    {
        const g = new THREE.Group();
        B(g, 0.95, 0.48, 0.62, M.wood, 0, 0.24, 0);
        B(g, 0.99, 0.07, 0.66, M.woodDark, 0, 0.10, 0);
        B(g, 0.99, 0.07, 0.66, M.woodDark, 0, 0.44, 0);
        const L = lid(OPEN_SPECS.crate);
        L.position.set(0, 0.48, -0.31);
        B(L, 0.97, 0.07, 0.64, M.woodDark, 0, 0.035, 0.31);
        latch(L, 0, -0.005, 0.63);
        seal(L);
        g.add(L);
        g.add(_plaque('crate', 0.42, 0.13, 0, 0.26, 0.315));
        T.crate = g;
    }

    /* -- 弹药箱：橄榄铁皮 + 印字色带 + 平盖 -- */
    {
        const g = new THREE.Group();
        B(g, 0.72, 0.32, 0.46, M.olive, 0, 0.16, 0);
        B(g, 0.726, 0.07, 0.468, M.oliveDark, 0, 0.16, 0);       // 色带（外扩 3mm 防 z-fight）
        const L = lid(OPEN_SPECS.ammo);
        L.position.set(0, 0.32, -0.23);
        B(L, 0.74, 0.06, 0.48, M.oliveDark, 0, 0.03, 0.23);
        latch(L, 0, 0, 0.475);
        seal(L);
        g.add(L);
        g.add(_plaque('ammo', 0.34, 0.11, 0, 0.16, 0.233));
        T.ammo = g;
    }

    /* -- 医疗柜：白柜红十 + 左铰链玻璃门 -- */
    {
        const g = new THREE.Group();
        B(g, 0.8, 1.15, 0.42, M.white, 0, 0.575, 0);
        B(g, 0.3, 0.09, 0.02, M.red, 0, 0.82, 0.215);            // 红十字
        B(g, 0.09, 0.3, 0.02, M.red, 0, 0.82, 0.215);
        const L = lid(OPEN_SPECS.medcab);
        L.position.set(-0.4, 0.575, 0.21);
        B(L, 0.78, 1.07, 0.03, M.white, 0.39, 0, 0.012);
        B(L, 0.05, 0.16, 0.025, M.steel, 0.73, 0, 0.03);         // 把手
        latch(L, 0.72, -0.5, 0.035);
        seal(L);
        g.add(L);
        L.add(_plaque('medcab', 0.30, 0.10, 0.30, -0.35, 0.029));
        T.medcab = g;
    }

    /* -- 工具柜：橙钢柜门 + 双屉缝 -- */
    {
        const g = new THREE.Group();
        B(g, 0.9, 1.0, 0.45, M.orange, 0, 0.55, 0);
        B(g, 0.92, 0.1, 0.47, M.orangeDark, 0, 0.05, 0);
        const L = lid(OPEN_SPECS.toolbox);
        L.position.set(-0.45, 0.55, 0.225);
        B(L, 0.86, 0.92, 0.03, M.orangeDark, 0.43, 0, 0.012);
        B(L, 0.5, 0.025, 0.012, M.steel, 0.43, 0.2, 0.032);      // 屉缝上
        B(L, 0.5, 0.025, 0.012, M.steel, 0.43, -0.16, 0.032);    // 屉缝下
        latch(L, 0.72, -0.4, 0.035);
        seal(L);
        g.add(L);
        L.add(_plaque('toolbox', 0.30, 0.09, 0.43, -0.30, 0.029));
        T.toolbox = g;
    }

    /* -- 行李袋：胶囊袋体（CapsuleGeometry 卧倒）+ 掀盖 + 捆带 -- */
    {
        const g = new THREE.Group();
        const bag = new THREE.Mesh(new THREE.CapsuleGeometry(0.19, 0.62, 4, 10), M.fabric);
        bag.rotation.z = Math.PI / 2;
        bag.position.y = 0.2;
        bag.castShadow = bag.receiveShadow = true;
        g.add(bag);
        B(g, 0.05, 0.05, 0.44, M.fabricDark, -0.2, 0.36, 0);     // 捆带
        B(g, 0.05, 0.05, 0.44, M.fabricDark, 0.2, 0.36, 0);
        const L = lid(OPEN_SPECS.duffle);
        L.position.set(0, 0.37, -0.17);
        B(L, 0.95, 0.04, 0.34, M.fabricDark, 0, 0.02, 0.17);
        latch(L, 0, 0, 0.345);
        seal(L);
        g.add(L);
        g.add(_plaque('duffle', 0.26, 0.08, 0, 0.12, 0.196));
        T.duffle = g;
    }

    /* -- 抽屉柜：钢柜 + 滑出抽屉面（腔口暗板露底） -- */
    {
        const g = new THREE.Group();
        B(g, 0.62, 0.92, 0.5, M.gray, 0, 0.46, 0);
        B(g, 0.56, 0.3, 0.02, M.inner, 0, 0.62, 0.248);          // 腔口
        B(g, 0.56, 0.26, 0.015, M.steel, 0, 0.26, 0.253);        // 下屉装饰缝
        const L = lid(OPEN_SPECS.drawer);
        L.position.set(0, 0.62, 0.255);
        B(L, 0.54, 0.26, 0.04, M.gray, 0, 0, 0.02);
        B(L, 0.16, 0.035, 0.03, M.steel, 0, 0, 0.055);           // 拉手
        latch(L, 0.2, 0, 0.05);
        seal(L);
        g.add(L);
        g.add(_plaque('drawer', 0.26, 0.08, 0, 0.30, 0.262));
        T.drawer = g;
    }

    /* -- 保险箱：墨钢 + 右铰链厚门 + 密码盘 -- */
    {
        const g = new THREE.Group();
        B(g, 0.72, 0.8, 0.62, M.steel, 0, 0.4, 0);
        B(g, 0.74, 0.08, 0.64, M.inner, 0, 0.04, 0);
        const L = lid(OPEN_SPECS.safe);
        L.position.set(0.36, 0.44, 0.31);
        B(L, 0.68, 0.7, 0.05, M.steel, -0.34, 0, 0.012);
        C(L, 0.075, 0.075, 0.045, M.inner, -0.14, 0.06, 0.055, 16, Math.PI / 2, 0);
        C(L, 0.02, 0.02, 0.06, M.gold, -0.14, 0.06, 0.062, 8, Math.PI / 2, 0);
        latch(L, -0.32, 0, 0.05);
        seal(L);
        g.add(L);
        L.add(_plaque('safe', 0.26, 0.09, -0.20, -0.25, 0.039));
        T.safe = g;
    }

    /* -- 军火库：长架 + 格架枪影 + 顶铰下翻闸门 -- */
    {
        const g = new THREE.Group();
        B(g, 2.1, 0.1, 0.6, M.oliveDark, 0, 0.05, 0);            // 底座
        B(g, 0.06, 1.5, 0.6, M.olive, -1.02, 0.75, 0);           // 左柱
        B(g, 0.06, 1.5, 0.6, M.olive, 1.02, 0.75, 0);            // 右柱
        B(g, 2.1, 0.08, 0.6, M.olive, 0, 1.46, 0);               // 顶板
        B(g, 2.04, 1.4, 0.05, M.oliveDark, 0, 0.74, -0.275);     // 背板
        B(g, 2.0, 0.04, 0.52, M.oliveDark, 0, 0.78, 0);          // 中隔板
        B(g, 0.08, 0.1, 0.9, M.steel, -0.5, 0.86, -0.02);        // 格内枪影
        B(g, 0.08, 0.1, 0.9, M.steel, 0.45, 0.87, 0.04);
        B(g, 0.08, 0.1, 0.9, M.steel, -0.1, 0.15, -0.05);
        g.add(_plaque('rack', 0.56, 0.08, 0, 0.05, 0.302));      // 底座涂装铭牌
        const L = lid(OPEN_SPECS.rack);
        L.position.set(0, 1.42, 0.3);
        /* 闸门改栅条（写实度评审 #05）：立柱 + 5 根横条留缝，格架/枪影
         * 未搜时若隐若现；开合动画沿用顶铰下翻不变 */
        B(L, 0.07, 1.32, 0.045, M.oliveDark, -0.98, -0.66, 0);   // 左立柱
        B(L, 0.07, 1.32, 0.045, M.oliveDark, 0.98, -0.66, 0);    // 右立柱
        for (let i = 0; i < 5; i++) {
            B(L, 1.90, 0.14, 0.045, M.oliveDark, 0, -0.10 - i * 0.29, 0);  // 横栅
        }
        B(L, 1.7, 0.05, 0.02, M.steel, 0, -0.66, 0.03);          // 门加强筋
        latch(L, 0, -1.28, 0.04);
        seal(L);
        g.add(L);
        T.rack = g;
    }

    _TPL = T;
    return _TPL;
}

/* ==== 7. 掉落物可视化：小物件网格 + 品质辉光 + 价值签（弹出→悬浮→吸收） ==== */

let _GEO = null;
function geos() {
    if (_GEO) return _GEO;
    _GEO = {
        bar: new THREE.BoxGeometry(0.24, 0.075, 0.11),
        watch: new THREE.CylinderGeometry(0.055, 0.055, 0.022, 14),
        watchFace: new THREE.BoxGeometry(0.055, 0.01, 0.055),
        brick: new THREE.BoxGeometry(0.2, 0.095, 0.1),
        chip: new THREE.BoxGeometry(0.17, 0.045, 0.13),
        chipCore: new THREE.BoxGeometry(0.12, 0.014, 0.08),
        medkit: new THREE.BoxGeometry(0.17, 0.11, 0.13),
        crossH: new THREE.BoxGeometry(0.09, 0.026, 0.012),
        crossV: new THREE.BoxGeometry(0.026, 0.09, 0.012),
        can: new THREE.CylinderGeometry(0.062, 0.062, 0.13, 12),
        canBand: new THREE.CylinderGeometry(0.064, 0.064, 0.05, 12, 1, true),
        gear: new THREE.CylinderGeometry(0.075, 0.075, 0.032, 8),
        axle: new THREE.CylinderGeometry(0.022, 0.022, 0.05, 8),
        scroll: new THREE.CylinderGeometry(0.032, 0.032, 0.22, 10),
        helmet: new THREE.SphereGeometry(0.095, 12, 10),
        statue: new THREE.ConeGeometry(0.062, 0.19, 8),
        statueBase: new THREE.BoxGeometry(0.09, 0.03, 0.09),
        box: new THREE.BoxGeometry(0.13, 0.1, 0.1),
    };
    return _GEO;
}

const SHAPE_BY_KIND = {
    valuables: 'bar', tech: 'chip', medical: 'medkit', parts: 'gear',
    food: 'can', gear: 'helmet', docs: 'scroll', misc: 'box',
};

/* ==== 7b. 仓库/背包剪影图标（写实度评审 #07：emoji 与军事 UI 相斥且跨平台
 * 不一致）——按掉落物 shape 程序化 2D 剪影，染品质色，dataURL 缓存。
 * 形状语义与上方 3D 掉落物 _itemMesh 同源：金条/名表/砖/雕像/芯片/急救包/
 * 罐头/齿轮/卷宗/头盔/木匣，图标-掉落物-品质色三者统一。 */
const _iconCache = new Map();

export function itemIconUrl(item, color = '#d8d8d8') {
    const shape = (item && (item.shape || SHAPE_BY_KIND[item.kind])) || 'box';
    const key = shape + '|' + color;
    if (_iconCache.has(key)) return _iconCache.get(key);
    const url = _drawIcon(shape, color);
    _iconCache.set(key, url);
    return url;
}

function _drawIcon(shape, color) {
    const [c, g] = _canvas(48, 48);
    g.translate(24, 24);
    g.fillStyle = color;
    g.strokeStyle = color;
    g.lineWidth = 2.4;
    g.lineJoin = 'round';
    g.globalAlpha = 0.94;
    switch (shape) {
        case 'bar':                                     // 金条：双叠梯形锭
            g.beginPath();
            g.moveTo(-14, 8); g.lineTo(-8, 0); g.lineTo(8, 0); g.lineTo(14, 8);
            g.closePath(); g.fill();
            g.globalAlpha = 0.55;
            g.beginPath();
            g.moveTo(-9, -2); g.lineTo(-4, -9); g.lineTo(10, -9); g.lineTo(14, -2);
            g.closePath(); g.fill();
            break;
        case 'watch':                                   // 名表：表盘 + 表冠带
            g.lineWidth = 3.4;
            g.beginPath(); g.arc(0, 1, 9, 0, Math.PI * 2); g.stroke();
            g.beginPath(); g.moveTo(0, 1); g.lineTo(0, -5); g.moveTo(0, 1); g.lineTo(4, 3); g.stroke();
            g.globalAlpha = 0.55;
            g.fillRect(-3, -15, 6, 4); g.fillRect(-3, 12, 6, 4);
            break;
        case 'brick':                                   // 曼德尔砖：斜置砖块
            g.rotate(-0.18);
            g.fillRect(-13, -8, 26, 15);
            g.globalAlpha = 0.45;
            g.fillRect(-13, -8, 26, 4);
            break;
        case 'statue':                                  // 龙纹雕像：锥身 + 座
            g.fillRect(-9, 10, 18, 5);
            g.beginPath();
            g.moveTo(0, -14); g.lineTo(6, 10); g.lineTo(-6, 10);
            g.closePath(); g.fill();
            break;
        case 'chip': {                                  // 电子件：芯片 + 四边引脚
            g.fillRect(-9, -9, 18, 18);
            g.globalAlpha = 0.55;
            for (let i = -6; i <= 6; i += 6) {
                g.fillRect(i - 1.5, -14, 3, 4); g.fillRect(i - 1.5, 10, 3, 4);
                g.fillRect(-14, i - 1.5, 4, 3); g.fillRect(10, i - 1.5, 4, 3);
            }
            g.globalAlpha = 0.9;
            g.fillRect(-4, -4, 8, 8);
            break;
        }
        case 'medkit':                                  // 急救包：圆角匣 + 十字
            g.fillRect(-13, -9, 26, 19);
            g.fillStyle = 'rgba(8,10,8,0.9)';
            g.fillRect(-2.5, -6, 5, 13); g.fillRect(-6.5, -2, 13, 5);
            break;
        case 'can':                                     // 口粮罐：罐身 + 环带
            g.fillRect(-7, -11, 14, 22);
            g.globalAlpha = 0.5;
            g.fillRect(-7, -4, 14, 7);
            g.globalAlpha = 0.94;
            g.beginPath(); g.ellipse(0, -11, 7, 2.6, 0, 0, Math.PI * 2); g.fill();
            break;
        case 'gear': {                                  // 零件：齿轮 + 轴孔
            g.beginPath();
            for (let i = 0; i < 8; i++) {
                const a = (i / 8) * Math.PI * 2;
                g.moveTo(0, 0);
                g.arc(0, 0, 11, a - 0.18, a + 0.18);
                g.lineTo(0, 0);
            }
            g.fill();
            g.globalAlpha = 1;
            g.fillStyle = 'rgba(10,12,9,0.92)';
            g.beginPath(); g.arc(0, 0, 4.2, 0, Math.PI * 2); g.fill();
            break;
        }
        case 'scroll':                                  // 卷宗：卷轴 + 垂纸
            g.fillRect(-8, -12, 16, 24);
            g.globalAlpha = 0.55;
            g.fillRect(-11, -14, 22, 4); g.fillRect(-11, 10, 22, 4);
            break;
        case 'helmet':                                  // 装备：钢盔剖面
            g.beginPath();
            g.arc(0, 2, 13, Math.PI, 0);
            g.lineTo(13, 6); g.lineTo(-13, 6);
            g.closePath(); g.fill();
            g.globalAlpha = 0.5;
            g.fillRect(-13, 7, 26, 2.6);
            break;
        case 'box':                                     // 杂项：木匣 + 盖缝
        default:
            g.fillRect(-12, -9, 24, 19);
            g.globalAlpha = 0.5;
            g.fillRect(-12, -3, 24, 2.6);
    }
    return c.toDataURL('image/png');
}

/* 按物件 shape/kind 拼小网格（材质多数共享；发光件用 rarity 色临时材质） */
function _itemMesh(item, color) {
    const G = geos(), M = mats();
    const shape = item.shape || SHAPE_BY_KIND[item.kind] || 'box';
    const grp = new THREE.Group();
    const disposables = [];
    const add = (geo, mat, x = 0, y = 0, z = 0, rx = 0, rz = 0) => {
        const m = new THREE.Mesh(geo, mat);
        m.position.set(x, y, z);
        m.rotation.set(rx, 0, rz);
        m.castShadow = true;
        grp.add(m);
        return m;
    };
    switch (shape) {
        case 'bar':                                     // 金条
            add(G.bar, M.gold, 0, 0.04);
            break;
        case 'watch':                                   // 名表
            add(G.watch, M.gold, 0, 0.03);
            add(G.watchFace, M.inner, 0, 0.048);
            break;
        case 'brick':                                   // 曼德尔砖
            add(G.brick, M.brick, 0, 0.05, 0, 0, 0.25);
            break;
        case 'statue':                                  // 龙纹雕像
            add(G.statueBase, M.patina, 0, 0.015);
            add(G.statue, M.patina, 0, 0.12);
            break;
        case 'chip': {                                  // 电子件：暗壳 + 品质色发光芯
            const em = new THREE.MeshStandardMaterial({ color: 0x101210, emissive: new THREE.Color(color), emissiveIntensity: 1.7, roughness: 0.4 });
            disposables.push(em);
            add(G.chip, M.steel, 0, 0.025);
            add(G.chipCore, em, 0, 0.052);
            break;
        }
        case 'medkit':                                  // 急救包：白匣红十字
            add(G.medkit, M.white, 0, 0.055);
            add(G.crossH, M.red, 0, 0.115, 0.062);
            add(G.crossV, M.red, 0, 0.115, 0.062);
            break;
        case 'can':                                     // 口粮罐
            add(G.can, M.gray, 0, 0.065);
            add(G.canBand, M.paper, 0, 0.065);
            break;
        case 'gear': {                                  // 零件齿轮 + 发光轴
            const em = new THREE.MeshStandardMaterial({ color: 0x101210, emissive: new THREE.Color(color), emissiveIntensity: 1.5, roughness: 0.4 });
            disposables.push(em);
            add(G.gear, M.steel, 0, 0.02, 0, 0, Math.PI / 2);
            add(G.axle, em, 0, 0.02, 0, Math.PI / 2, 0);
            break;
        }
        case 'scroll':                                  // 卷宗
            add(G.scroll, M.paper, 0, 0.04, 0, 0, Math.PI / 2);
            break;
        case 'helmet': {                                // 装备盔
            const m = add(G.helmet, M.fabricDark, 0, 0.07);
            m.scale.set(1, 0.72, 1);
            break;
        }
        default:                                        // 杂项木匣
            add(G.box, M.fabric, 0, 0.05);
    }
    grp.userData.disposables = disposables;
    return grp;
}

/* 价值签 Sprite：品质色描边字 */
function _labelSprite(item, color) {
    const [c, g] = _canvas(256, 64);
    g.font = 'bold 30px Menlo, Consolas, monospace';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.lineWidth = 7;
    g.strokeStyle = 'rgba(0,0,0,0.85)';
    g.strokeText(`₵${item.value.toLocaleString('en-US')}`, 128, 34);
    g.fillStyle = color;
    g.fillText(`₵${item.value.toLocaleString('en-US')}`, 128, 34);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
    const sp = new THREE.Sprite(mat);
    sp.scale.set(0.95, 0.24, 1);
    sp.position.y = 0.34;
    sp.renderOrder = 5;
    return { sp, mat, tex };
}

/* 品质辉光 Sprite（加色混合；彩档呼吸在 fx 更新里做） */
function _glowSprite(color) {
    const mat = new THREE.SpriteMaterial({
        map: _texGlow(), color: new THREE.Color(color), transparent: true,
        opacity: 0.55, blending: THREE.AdditiveBlending, depthWrite: false,
    });
    const sp = new THREE.Sprite(mat);
    sp.scale.set(0.55, 0.55, 1);
    sp.renderOrder = 4;
    return { sp, mat };
}

/* fx 生命期常数：弹出 0.28s → 悬浮 → 末 0.6s 吸收消失 */
const FX_POP = 0.28;
const FX_TAIL = 0.6;

/* ==== 8. LootManager 主类 ==== */

export class LootManager {
    /* { scene, collision, spots, ground } —— ground 可选注入（默认鸭子调
     * collision.groundHeight，同 main.js:59 gunview 先例），无则按平地 y=0 */
    constructor({ scene, collision, spots, ground } = {}) {
        this.scene = scene || null;
        this.collision = collision || null;
        this.ground = (typeof ground === 'function')
            ? ground
            : (this.collision && typeof this.collision.groundHeight === 'function'
                ? (x, z) => this.collision.groundHeight(x, z)
                : null);

        /* -- 契约公开字段 -- */
        this.containers = [];       // [{uid,type,x,z,rotY,zone,searched,group,...}]
        this.onLooted = null;       // (item) => void —— 1~3 件逐件回调
        this.onPrompt = null;       // (text|null) => void —— 提示状态变化（可选）
        this.searchRadius = 2.2;    // 最近未搜容器进入提示的距离（interfaces）
        this.cullDist = 220;        // 距离剔除阈值（risks#4 降级预案②）

        /* -- 内部状态 -- */
        this._root = new THREE.Group();
        this._root.name = 'lootContainers';
        this._fxGroup = new THREE.Group();
        this._fxGroup.name = 'lootItemFx';
        if (this.scene) {
            this.scene.add(this._root);
            this.scene.add(this._fxGroup);
        }
        this._fx = [];              // 掉落物动效队列
        this._active = null;        // 当前提示容器
        this._progress = 0;         // 搜索进度 0..1
        this._prompting = false;    // 本帧是否有容器提示（isPrompting）
        this._cullT = 0;            // 剔除节流
        this._t = 0;                // 未搜信标呼吸时钟
        this._colKeys = new Set();  // 已登记碰撞的点位（CollisionWorld 无 remove）
        this._eye = { x: 0, z: 0 };
        this._dom = this._buildPromptDom();

        if (Array.isArray(spots) && spots.length) this.buildFromSpots(spots);
    }

    /* ---- 按分区生成 API：地图构建者 CONTAINER_SPOTS [{type,x,z,rotY,zone}] 传入 ---- */
    buildFromSpots(spots) {
        if (!Array.isArray(spots)) return 0;
        /* 重建语义：先清视觉实例；碰撞盒无法注销故同点位只登记一次 */
        for (const c of this.containers) this._root.remove(c.group);
        this.containers.length = 0;
        let n = 0;
        for (const s of spots) {
            if (this.addSpot(s)) n++;
        }
        return n;
    }

    addSpot(spot) {
        const s = spot || {};
        const tpl = _tpls()[s.type];
        if (!tpl || typeof s.x !== 'number' || typeof s.z !== 'number') {
            console.warn('[Loot] 跳过非法容器点位：', s);
            return null;
        }
        const g = tpl.clone(true);
        g.position.set(s.x, this._groundY(s.x, s.z), s.z);
        g.rotation.y = s.rotY || 0;
        const lid = g.getObjectByName('lootLid');
        const latch = g.getObjectByName('lootLatch');
        if (latch) latch.material = mats().latchOn;
        /* 未搜呼吸信标（写实度评审 #05③）：小号琥珀辉光 Sprite 悬在容器顶，
         * 15-20m 外靠光点找箱子；搜完即熄，resetAll 复燃。材质独立可逐容器呼吸 */
        const fpBeacon = FOOTPRINT[s.type];
        const beacon = _glowSprite('#ffb35c');
        beacon.sp.scale.set(0.34, 0.34, 1);
        beacon.sp.position.set(0, (fpBeacon ? fpBeacon.h : 0.6) + 0.30, 0);
        beacon.sp.material.opacity = 0.35;
        beacon.sp.renderOrder = 4;
        g.add(beacon.sp);
        this._root.add(g);
        const entry = {
            uid: nextUid('ct'),
            type: s.type,
            x: s.x, z: s.z,
            rotY: s.rotY || 0,
            zone: s.zone || 'wild',
            searched: false,
            group: g,
            lid,
            latch,
            open: lid ? lid.userData.open : null,
            home: lid ? lid.userData.home : null,
            openT: 0,
            beacon,
            phase: Math.random() * Math.PI * 2,
        };
        this.containers.push(entry);
        const fp = FOOTPRINT[s.type];
        const key = `${s.type}|${s.x}|${s.z}`;
        if (this.collision && fp && !this._colKeys.has(key)) {
            this._colKeys.add(key);
            this.collision.addBox(s.x, s.z, fp.hx, fp.hz, s.rotY || 0, fp.h);
        }
        return entry;
    }

    /* ---- 每帧驱动（唯一入口 mission.update；本模块零键盘监听） ---- */
    update(dt, playerEye, fHeld) {
        const eye = playerEye || this._eye;
        if (playerEye) this._eye = { x: playerEye.x, z: playerEye.z };
        this._updateSearch(dt, eye, !!fHeld);
        this._updateOpenAnims(dt);
        this._updateBeacons(dt);
        this._updateFx(dt);
        this._updateDom();
        this._cullTick(dt, eye);
    }

    /* 未搜容器呼吸信标：琥珀光点 0.35↔0.12 正弦呼吸（约 2.4s 周期，相位错开）；
     * 搜完即熄（_complete 置 searched），resetAll 复燃；随容器剔除同灭 */
    _updateBeacons(dt) {
        this._t += dt;
        for (const c of this.containers) {
            if (!c.beacon) continue;
            if (c.searched) {
                if (c.beacon.sp.visible) c.beacon.sp.visible = false;
                continue;
            }
            c.beacon.sp.visible = true;
            c.beacon.mat.opacity = 0.24 + 0.14 * Math.sin(this._t * 2.6 + c.phase);
        }
    }

    /* 当前帧是否有容器搜索提示（mission INTEL 分支守卫防双跑） */
    isPrompting() {
        return !!this._prompting;
    }

    /* 调试：在 (x,z) 生成指定品质掉落物样本（__fps.loot.spawnAt 复核品质色用） */
    spawnAt(x, z, rarityId = 4) {
        const r = Math.max(0, Math.min(6, rarityId | 0));
        const rar = RARITY[r];
        const item = {
            uid: nextUid('fx'), name: '调试样本', rarity: r,
            value: Math.round((rar.vMin + rar.vMax) / 2 / 10) * 10,
            kind: 'valuables', icon: rar.name, shape: null,
        };
        const gy = this._groundY(x, z);
        this._spawnFx(item, x, gy + 0.9, z, 0, 4.5);
        return item;
    }

    /* 重开行动：全部容器回未搜态、关盖、清掉落物与提示 */
    resetAll() {
        for (const c of this.containers) {
            c.searched = false;
            c.openT = 0;
            if (c.lid && c.home) {
                c.lid.position.set(c.home.x, c.home.y, c.home.z);
                c.lid.rotation.set(0, 0, 0);
            }
            if (c.latch) c.latch.material = mats().latchOn;
            c.group.visible = true;
        }
        this._clearFx();
        this._active = null;
        this._progress = 0;
        this._prompting = false;
        if (this._dom && this._dom.root.style.display !== 'none') {
            this._dom.root.style.display = 'none';
        }
    }

    /* ---- 内部：搜索状态机 ---- */
    _updateSearch(dt, eye, fHeld) {
        /* 最近未搜容器（XZ 平面 < searchRadius） */
        let best = null;
        let bestD = this.searchRadius * this.searchRadius;
        for (const c of this.containers) {
            if (c.searched) continue;
            const dx = eye.x - c.x, dz = eye.z - c.z;
            const d2 = dx * dx + dz * dz;
            if (d2 < bestD) { bestD = d2; best = c; }
        }
        if (best !== this._active) {
            this._active = best;
            this._progress = 0;
        }
        if (best) {
            if (!this._prompting) {
                this._prompting = true;
                if (this.onPrompt) this.onPrompt(this._label(best));
            }
            if (fHeld) {
                const def = CONTAINER_TYPES[best.type];
                this._progress = Math.min(1, this._progress + dt / (def ? def.searchT : 1.8));
                if (this._progress >= 1) this._complete(best);
            } else if (this._progress > 0) {
                this._progress = Math.max(0, this._progress - dt * 0.9);   // 松手回退不即时清零
            }
        } else if (this._prompting) {
            this._prompting = false;
            if (this.onPrompt) this.onPrompt(null);
        }
    }

    _complete(c) {
        const def = CONTAINER_TYPES[c.type];
        c.searched = true;
        c.openT = 0.0001;                              // 开盖动画启动（_updateOpenAnims 接管）
        if (c.latch) c.latch.material = mats().latchOff;
        this._progress = 0;
        this._active = null;
        this._prompting = false;
        if (this.onPrompt) this.onPrompt(null);
        /* 1~3 件产出（45/35/20 偏向少量），逐件回调 onLooted + 弹出物效 */
        const roll = Math.random();
        const n = roll < 0.45 ? 1 : (roll < 0.8 ? 2 : 3);
        for (let i = 0; i < n; i++) {
            const item = rollLoot(c.zone, c.type);
            if (this.onLooted) this.onLooted(item);
            const pop = (FOOTPRINT[c.type] && FOOTPRINT[c.type].pop) || 1.0;
            const a = Math.random() * Math.PI * 2;
            const rr = 0.12 + Math.random() * 0.3;
            this._spawnFx(item, c.x + Math.cos(a) * rr,
                this._groundY(c.x, c.z) + pop, c.z + Math.sin(a) * rr, i * 0.14, 2.6);
        }
        return def;
    }

    _label(c) {
        const def = CONTAINER_TYPES[c.type];
        return `按住 F 搜索 ${def ? def.name : c.type}`;
    }

    _updateOpenAnims(dt) {
        for (const c of this.containers) {
            if (c.openT <= 0 || c.openT >= 1) continue;
            c.openT = Math.min(1, c.openT + dt / 0.55);
            this._applyOpen(c);
        }
    }

    _applyOpen(c) {
        if (!c.lid || !c.open || !c.home) return;
        const k = 1 - Math.pow(1 - Math.min(1, c.openT), 3);       // easeOutCubic
        if (c.open.axis === 'zpos') {
            c.lid.position.z = c.home.z + (c.open.dist || 0.3) * k;
        } else if (c.open.axis) {
            c.lid.rotation[c.open.axis] = (c.open.angle || 0) * k;
        }
    }

    /* ---- 内部：掉落物动效 ---- */
    _spawnFx(item, x, y, z, delay, dur) {
        if (!this._fxGroup.parent) return;
        const rar = RARITY[item.rarity] || RARITY[0];
        const grp = new THREE.Group();
        grp.add(_itemMesh(item, rar.color));
        const glow = _glowSprite(rar.color);
        grp.add(glow.sp);
        const label = _labelSprite(item, rar.color);
        grp.add(label.sp);
        grp.position.set(x, y, z);
        grp.visible = false;
        this._fxGroup.add(grp);
        this._fx.push({
            grp, t: -delay, dur,
            life: dur - FX_TAIL,
            y0: y,
            spin: (0.7 + Math.random() * 0.9) * (Math.random() < 0.5 ? -1 : 1),
            s: 1.25,                       // 整体放大系数
            glowMat: glow.mat, labelMat: label.mat, labelTex: label.tex,
            rarity: item.rarity,
        });
    }

    _updateFx(dt) {
        for (let i = this._fx.length - 1; i >= 0; i--) {
            const f = this._fx[i];
            f.t += dt;
            if (f.t < 0) { f.grp.visible = false; continue; }
            f.grp.visible = true;
            const g = f.grp;
            if (f.t < FX_POP) {                        // 弹出小抛物线
                const q = f.t / FX_POP;
                g.position.y = f.y0 + 0.3 * Math.sin(q * Math.PI);
                g.scale.setScalar(f.s * (0.3 + 0.7 * (1 - Math.pow(1 - q, 3))));
            } else if (f.t < f.life) {                 // 悬浮呼吸
                g.position.y = f.y0 + Math.sin((f.t - FX_POP) * 3.1) * 0.05;
                g.scale.setScalar(f.s);
            } else {                                   // 吸收：上浮 + 缩没 + 标签淡出
                const q = Math.min(1, (f.t - f.life) / (f.dur - f.life));
                g.position.y = f.y0 + q * 0.55;
                g.scale.setScalar(Math.max(0.001, f.s * (1 - q)));
                f.labelMat.opacity = 1 - q;
                f.fade = 1 - q;
            }
            g.rotation.y += f.spin * dt;
            if (f.glowMat) {                           // 辉光：彩档呼吸 / 金红更亮，乘吸收淡出
                const base = f.rarity === 6
                    ? 0.5 + 0.32 * Math.sin(f.t * 6)
                    : (f.rarity >= 4 ? 0.62 : 0.4);
                f.glowMat.opacity = base * (f.fade === undefined ? 1 : f.fade);
            }
            if (f.t >= f.dur) {
                this._fxGroup.remove(f.grp);
                if (f.labelTex) f.labelTex.dispose();
                if (f.labelMat) f.labelMat.dispose();
                if (f.glowMat) f.glowMat.dispose();
                const ds = f.grp.userData && f.grp.userData.disposables;
                if (ds) {
                    for (const m of ds) m.dispose();
                }
                this._fx.splice(i, 1);
            }
        }
    }

    _clearFx() {
        for (const f of this._fx) {
            this._fxGroup.remove(f.grp);
            if (f.labelTex) f.labelTex.dispose();
            if (f.labelMat) f.labelMat.dispose();
            if (f.glowMat) f.glowMat.dispose();
            const ds = f.grp.userData && f.grp.userData.disposables;
            if (ds) {
                for (const m of ds) m.dispose();
            }
        }
        this._fx.length = 0;
    }

    /* ---- 内部：距离剔除（risks#4：>220m 隐藏，0.5s 节流） ---- */
    _cullTick(dt, eye) {
        this._cullT -= dt;
        if (this._cullT > 0) return;
        this._cullT = 0.5;
        const d2max = this.cullDist * this.cullDist;
        for (const c of this.containers) {
            const dx = eye.x - c.x, dz = eye.z - c.z;
            c.group.visible = (dx * dx + dz * dz) < d2max;
        }
    }

    _groundY(x, z) {
        return this.ground ? this.ground(x, z) : 0;
    }

    /* ---- 内部：搜索提示自注入 DOM（#fps-search-prompt，内联样式 z-index 12） ---- */
    _buildPromptDom() {
        const SVG_NS = 'http://www.w3.org/2000/svg';
        const RING_R = 15;
        const RING_C = Math.PI * 2 * RING_R;
        const root = document.createElement('div');
        root.id = 'fps-search-prompt';
        root.className = 'loot-search-root';
        root.style.cssText = 'position:fixed;left:50%;bottom:21%;transform:translateX(-50%);' +
            'display:none;align-items:center;gap:12px;z-index:12;pointer-events:none;' +
            'background:rgba(12,14,10,.78);border:1px solid rgba(255,179,92,.5);' +
            'border-radius:10px;padding:9px 16px;color:#ffd9a3;' +
            "font:600 13px/1 Menlo,Consolas,'SF Mono',monospace;letter-spacing:.05em;";

        const svg = document.createElementNS(SVG_NS, 'svg');       // 进度圈
        svg.setAttribute('width', '40');
        svg.setAttribute('height', '40');
        svg.setAttribute('viewBox', '0 0 40 40');
        svg.setAttribute('class', 'loot-search-ring');
        const bg = document.createElementNS(SVG_NS, 'circle');
        bg.setAttribute('cx', '20'); bg.setAttribute('cy', '20'); bg.setAttribute('r', RING_R);
        bg.setAttribute('fill', 'none');
        bg.setAttribute('stroke', 'rgba(216,222,210,.25)');
        bg.setAttribute('stroke-width', '4.5');
        bg.setAttribute('class', 'loot-search-ring-bg');
        const fg = document.createElementNS(SVG_NS, 'circle');
        fg.setAttribute('cx', '20'); fg.setAttribute('cy', '20'); fg.setAttribute('r', RING_R);
        fg.setAttribute('fill', 'none');
        fg.setAttribute('stroke', '#ffb35c');
        fg.setAttribute('stroke-width', '4.5');
        fg.setAttribute('stroke-linecap', 'round');
        fg.setAttribute('stroke-dasharray', String(RING_C));
        fg.setAttribute('stroke-dashoffset', String(RING_C));
        fg.setAttribute('transform', 'rotate(-90 20 20)');
        fg.setAttribute('class', 'loot-search-ring-fg');
        svg.appendChild(bg);
        svg.appendChild(fg);

        const col = document.createElement('div');                 // 右列：键位行 + 进度条
        col.className = 'loot-search-col';
        col.style.cssText = 'display:flex;flex-direction:column;gap:6px;align-items:flex-start;';
        const line = document.createElement('div');
        line.className = 'loot-search-line';
        line.style.cssText = 'display:flex;align-items:center;gap:8px;';
        const key = document.createElement('span');
        key.className = 'loot-search-key';
        key.textContent = 'F';
        key.style.cssText = 'display:inline-block;min-width:20px;text-align:center;padding:3px 6px;' +
            'border:1px solid rgba(255,179,92,.8);border-radius:4px;color:#ffb35c;';
        const label = document.createElement('span');
        label.className = 'loot-search-label';
        label.textContent = '按住 F 搜索';
        const bar = document.createElement('div');
        bar.className = 'loot-search-bar';
        bar.style.cssText = 'width:170px;height:4px;background:rgba(216,222,210,.18);' +
            'border-radius:2px;overflow:hidden;';
        const fill = document.createElement('div');
        fill.className = 'loot-search-fill';
        fill.style.cssText = 'height:100%;width:0;background:#ffb35c;';
        bar.appendChild(fill);
        line.appendChild(key);
        line.appendChild(label);
        col.appendChild(line);
        col.appendChild(bar);
        root.appendChild(svg);
        root.appendChild(col);
        document.body.appendChild(root);
        return { root, fg, label, fill, ringC: RING_C };
    }

    _updateDom() {
        const d = this._dom;
        if (!d) return;
        if (!this._prompting || !this._active) {
            if (d.root.style.display !== 'none') d.root.style.display = 'none';
            return;
        }
        if (d.root.style.display !== 'flex') d.root.style.display = 'flex';
        d.label.textContent = this._label(this._active);
        const p = this._progress;
        d.fg.setAttribute('stroke-dashoffset', String(d.ringC * (1 - p)));
        d.fill.style.width = (p * 100).toFixed(1) + '%';
    }
}
