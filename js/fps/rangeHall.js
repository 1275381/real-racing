import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { terrainHeight } from './env.js';

/* =====================================================================
   js/fps/rangeHall.js —— 全封闭室内靶馆（本轮重做：分不清靶场与真实行动）
   馆体放在地图东北空地 (120,130)（核对过 LAYOUT/CONTAINER_SPOTS/巡逻线/
   土路均无重叠；且在 player 世界夹边 ±(ARENA-2) 之内，无需动 player）。
   · 全封闭：水泥地坪/墙面/立柱/吊顶 + 四面实墙，任何方向看不到室外
     天空/地形/太阳雾天——核心验收点；
   · 人工光照：顶部成排长条灯板（自发光面片常亮）+ 6 盏点光（仅靶场
     模式 setActive(true) 点亮，控制灯数保帧率）；室外太阳/半球光由
     env.setIndoor 统一压暗（见 env.js）；
   · 射击位：隔断挡墙（下实上玻璃）+ 木质台面 + 射击线黄黑警示斜纹 +
     墙面大号车道编号（5/6/7，CanvasTexture）+ 安全告示/灭火器/路锥/
     弹药箱等馆内道具；
   · 靶道：沿用 targets.js 计分系统（targets.buildLanes 读 zones.
     rangeLanes，layout.js 把射位锚点改到馆内），10/15/25m 距离标记 +
     尽端挡弹斜墙/沙袋排；弹着火花/烟团沿用 gunview 现有弹着反馈。
   行动模式（室外/敌兵/容器/撤离）零改动：馆体只是战场里一栋
   封闭建筑，行动玩家无法进入；馆内地坪经 CollisionWorld.addFloor
   注册（additive，行动区无地板注册，着地逻辑不受影响）。
   ===================================================================== */

/* ==== 1. 馆体锚点（layout.js 引用：射位锚点与馆内地坪同源） ==== */

// 馆中心（地图东北空地：核对过 LAYOUT/容器锚点/巡逻线/土路均无重叠，
// 且在 player 世界夹边 ±(ARENA-2) 之内，无需动 player）
const RANGE_HALL_CX = 120, RANGE_HALL_CZ = 130;

// 地坪标高：取散水全范围 5×5 网格地形最高点 + 0.35m 抬升（确定性，无随机；
// 盖住散水外沿，保证散水/地坪任何一处不被起伏地形顶穿）
const FLOOR_Y = (() => {
    let m = -Infinity;
    for (let i = 0; i < 5; i++) {
        for (let j = 0; j < 5; j++) {
            const x = RANGE_HALL_CX - 26 + i * 13;      // 散水 52×52m：cx±26
            const z = RANGE_HALL_CZ - 26 + j * 13;
            m = Math.max(m, terrainHeight(x, z));
        }
    }
    return Math.ceil((m + 0.35) * 20) / 20;    // 0.05m 取整，避免零碎标高
})();

export const RANGE_HALL = {
    cx: RANGE_HALL_CX, cz: RANGE_HALL_CZ,   // 馆中心
    xBack: -17, xFront: 21,    // 内墙面相对 cx：后墙（射击位后）/ 前墙（挡弹端）
    halfZ: 18.5,               // 内半宽（摆动靶 ±(12+4.4) 距墙仍有 2.1m）
    height: 5.8,               // 馆内净高
    laneOff: 12,               // 射道间距（沿袭旧靶场 12m，摆动靶 ±4.4 不越道）
    fireX: -11,                // 射击线（lane origin 即此 x，targets 距离由此起算）
    floorY: FLOOR_Y,           // 馆内地坪标高（zones.rangeLanes / 碰撞地板同源）
    dir: new THREE.Vector3(1, 0, 0),   // 射向 +X（与旧靶场一致）
};

/* ==== 2. 程序化贴图（零外部资源，仓库约定；手法同 env.js/layout.js） ==== */

function makeCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return [c, c.getContext('2d')];
}

function toTex(c, rx = 1, ry = 1, srgb = true) {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(rx, ry);
    t.anisotropy = 8;
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    return t;
}

// 水泥墙面：模板板缝 + 对拉螺栓孔 + 流痕 + 底部踢脚污渍
function concreteWallTexture() {
    const S = 512;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#a3a19a';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 5200; i++) {
        const v = 120 + Math.random() * 62;
        g.fillStyle = `rgba(${v},${v - 2},${v - 8},${0.2 + Math.random() * 0.3})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.6, 1.6);
    }
    for (let i = 0; i < 16; i++) {   // 垂直流痕
        g.fillStyle = `rgba(84,82,74,${0.05 + Math.random() * 0.09})`;
        const x = Math.random() * S;
        g.fillRect(x, Math.random() * S * 0.4, 4 + Math.random() * 18, S * (0.4 + Math.random() * 0.6));
    }
    // 模板分缝：横缝一条 + 竖缝两条（平铺成板格）
    g.fillStyle = '#7e7c74';
    g.fillRect(0, S / 2 - 2, S, 4);
    g.fillRect(S / 3 - 2, 0, 4, S);
    g.fillRect(2 * S / 3 - 2, 0, 4, S);
    g.fillStyle = 'rgba(255,255,255,0.14)';   // 缝口高光
    g.fillRect(0, S / 2 + 2, S, 2);
    // 对拉螺栓孔（板格交叉处）
    for (const sx of [S / 3, 2 * S / 3]) for (const sy of [6, S / 2 + 22, S - 30]) {
        g.fillStyle = 'rgba(52,50,46,0.85)';
        g.beginPath(); g.arc(sx, sy, 7, 0, 7); g.fill();
        g.fillStyle = 'rgba(180,178,170,0.5)';
        g.beginPath(); g.arc(sx, sy - 2, 4, 0, 7); g.fill();
    }
    g.fillStyle = 'rgba(60,58,52,0.5)';       // 踢脚污渍
    g.fillRect(0, S - 34, S, 34);
    return c;
}

// 水泥地坪：伸缩缝网格 + 划痕 + 油渍（平铺后成整片网格）
function concreteFloorTexture() {
    const S = 512;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#8b8a85';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 4200; i++) {
        const v = 100 + Math.random() * 60;
        g.fillStyle = `rgba(${v},${v},${v - 4},${0.2 + Math.random() * 0.28})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.7, 1.7);
    }
    for (let i = 0; i < 26; i++) {   // 划痕弧线（拖靶箱/鞋底）
        g.strokeStyle = `rgba(66,64,58,${0.08 + Math.random() * 0.14})`;
        g.lineWidth = 1 + Math.random() * 2;
        const x = Math.random() * S, y = Math.random() * S;
        g.beginPath(); g.arc(x, y, 20 + Math.random() * 90, Math.random() * 7, Math.random() * 7); g.stroke();
    }
    for (let i = 0; i < 7; i++) {    // 油渍
        const grad = g.createRadialGradient(0, 0, 4, 0, 0, 30 + Math.random() * 50);
        grad.addColorStop(0, 'rgba(52,50,46,0.28)');
        grad.addColorStop(1, 'rgba(52,50,46,0)');
        g.save();
        g.translate(Math.random() * S, Math.random() * S);
        g.fillStyle = grad;
        g.fillRect(-90, -90, 180, 180);
        g.restore();
    }
    g.strokeStyle = '#6e6d68';       // 伸缩缝（四边 → 平铺成格）
    g.lineWidth = 5;
    g.strokeRect(2, 2, S - 4, S - 4);
    return c;
}

// 吊顶：深色混凝土 + 板缝（灯板/风梁单独建面）
function ceilingTexture() {
    const S = 256;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#74767a';
    g.fillRect(0, 0, S, S);
    for (let i = 0; i < 1800; i++) {
        const v = 84 + Math.random() * 40;
        g.fillStyle = `rgba(${v},${v + 2},${v + 6},${0.2 + Math.random() * 0.25})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.6, 1.6);
    }
    g.fillStyle = '#5d5f63';
    g.fillRect(0, S / 2 - 2, S, 4);
    g.fillRect(S / 2 - 2, 0, 4, S);
    return c;
}

// 黄黑警示斜纹（45°，斜纹画进贴图，面片无需旋转）
function hazardTexture() {
    const S = 128;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#c79a26';
    g.fillRect(0, 0, S, S);
    g.save();
    g.translate(S / 2, S / 2);
    g.rotate(Math.PI / 4);
    g.fillStyle = '#232323';
    for (let x = -S * 1.5; x < S * 1.5; x += 44) g.fillRect(x, -S, 22, S * 2);
    g.restore();
    for (let i = 0; i < 900; i++) {  // 做旧磨蚀
        g.fillStyle = `rgba(70,66,56,${Math.random() * 0.22})`;
        g.fillRect(Math.random() * S, Math.random() * S, 2, 2);
    }
    return c;
}

// 挡弹墙橡胶缓弹板：竖向密槽
function rubberSlatTexture() {
    const S = 256;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#2b2d2f';
    g.fillRect(0, 0, S, S);
    for (let x = 4; x < S; x += 20) {
        g.fillStyle = '#1c1e20';
        g.fillRect(x, 0, 9, S);
        g.fillStyle = 'rgba(255,255,255,0.07)';
        g.fillRect(x + 9, 0, 3, S);
    }
    for (let i = 0; i < 500; i++) {  // 弹痕白点
        g.fillStyle = `rgba(210,210,205,${Math.random() * 0.12})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1.4, 1.4);
    }
    return c;
}

// 木质台面：横纹 + 结疤
function woodTexture() {
    const S = 256;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#7c5c38';
    g.fillRect(0, 0, S, S);
    for (let y = 0; y < S; y += 2) {
        const v = Math.random();
        g.strokeStyle = `rgba(${60 + v * 60 | 0},${40 + v * 40 | 0},${18 + v * 24 | 0},${0.25 + Math.random() * 0.3})`;
        g.beginPath(); g.moveTo(0, y); g.lineTo(S, y + Math.random() * 3 - 1.5); g.stroke();
    }
    for (let i = 0; i < 7; i++) {    // 结疤
        g.fillStyle = 'rgba(52,34,16,0.8)';
        g.beginPath();
        g.ellipse(Math.random() * S, Math.random() * S, 3 + Math.random() * 5, 2 + Math.random() * 3, 0, 0, 7);
        g.fill();
    }
    return c;
}

// 大号车道编号牌（如 5/6/7）：深底 + 黄描边 + 白色模板大字
function laneNumberTexture(digit) {
    const W = 256, H = 384;
    const [c, g] = makeCanvas(W, H);
    g.fillStyle = '#25282c';
    g.fillRect(0, 0, W, H);
    g.strokeStyle = '#c79a26';
    g.lineWidth = 10;
    g.strokeRect(14, 14, W - 28, H - 28);
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillStyle = '#e9e5da';
    g.font = 'bold 236px "Arial Black", sans-serif';
    g.fillText(String(digit), W / 2, H / 2 + 8);
    g.font = 'bold 30px monospace';
    g.fillStyle = '#9aa0a6';
    g.fillText('LANE', W / 2, H - 52);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
}

// 距离标记牌（10M/15M/25M）：黄底黑字
function distanceTexture(label) {
    const S = 256;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#cfa42e';
    g.fillRect(0, 0, S, S);
    g.strokeStyle = '#1c1c1c';
    g.lineWidth = 14;
    g.strokeRect(10, 10, S - 20, S - 20);
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillStyle = '#171717';
    g.font = 'bold 92px monospace';
    g.fillText(label, S / 2, S / 2);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
}

// 安全告示牌：红头 DANGER + 警示三角 + 守则行（参考图版式，不复刻像素）
function dangerSignTexture() {
    const W = 512, H = 384;
    const [c, g] = makeCanvas(W, H);
    g.fillStyle = '#e9e6dd';
    g.fillRect(0, 0, W, H);
    g.strokeStyle = '#b3251d';
    g.lineWidth = 16;
    g.strokeRect(8, 8, W - 16, H - 16);
    g.fillStyle = '#b3251d';                       // 红头
    g.fillRect(24, 24, W - 48, 64);
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillStyle = '#ffffff';
    g.font = 'bold 40px sans-serif';
    g.fillText('DANGER · 射击危险区', W / 2, 58);
    // 警示三角
    g.fillStyle = '#e8c832';
    g.strokeStyle = '#1c1c1c';
    g.lineWidth = 6;
    g.beginPath();
    g.moveTo(96, 232); g.lineTo(160, 120); g.lineTo(224, 232);
    g.closePath(); g.fill(); g.stroke();
    g.fillStyle = '#1c1c1c';
    g.font = 'bold 56px sans-serif';
    g.fillText('!', 160, 208);
    // 守则行
    g.textAlign = 'left';
    g.fillStyle = '#2c2c2c';
    g.font = 'bold 27px sans-serif';
    ['· 听到哨音立即停火', '· 枪口始终朝向靶道', '· 越过黄线前必须退弹', '· 佩戴护目与听力防护']
        .forEach((s, i) => g.fillText(s, 252, 138 + i * 42));
    g.fillStyle = '#6a675e';
    g.font = '22px monospace';
    g.fillText('RANGE SAFETY RULES · 违者停止使用靶道', 40, H - 40);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
}

// 靶馆守则牌（深蓝底白字，与告示牌并排）
function rulesSignTexture() {
    const W = 512, H = 384;
    const [c, g] = makeCanvas(W, H);
    g.fillStyle = '#1d2733';
    g.fillRect(0, 0, W, H);
    g.strokeStyle = '#8b95a1';
    g.lineWidth = 10;
    g.strokeRect(10, 10, W - 20, H - 20);
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillStyle = '#e8ecf1';
    g.font = 'bold 42px sans-serif';
    g.fillText('靶 馆 使 用 守 则', W / 2, 62);
    g.textAlign = 'left';
    g.font = '26px sans-serif';
    ['1. 本馆为全封闭靶道，禁用曳光燃烧弹', '2. 只准对准本车道正面靶标射击', '3. 前方挡弹墙后禁止越入', '4. 收枪后验枪，退膛上保险', '5. 异常情况举手示意教官']
        .forEach((s, i) => g.fillText(s, 46, 122 + i * 46));
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
}

// 弹药箱戳记（箱面小标）
function ammoStencilTexture() {
    const W = 256, H = 96;
    const [c, g] = makeCanvas(W, H);
    g.fillStyle = '#4a5b40';
    g.fillRect(0, 0, W, H);
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillStyle = '#d9d6c8';
    g.font = 'bold 44px monospace';
    g.fillText('5.56 MM', W / 2, 34);
    g.font = 'bold 24px monospace';
    g.fillText('BALL M855 · 800 RDS', W / 2, 72);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
}

// 馆外横幅（西墙外侧，行动模式远看的门面）：室内靶馆 · INDOOR RANGE
function hallBannerTexture() {
    const W = 1024, H = 224;
    const [c, g] = makeCanvas(W, H);
    g.fillStyle = '#3a3e43';
    g.fillRect(0, 0, W, H);
    g.fillStyle = '#c79a26';
    g.fillRect(0, 0, W, 18); g.fillRect(0, H - 18, W, 18);
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillStyle = '#e9e5da';
    g.font = 'bold 104px sans-serif';
    g.fillText('室内靶馆 · INDOOR RANGE', W / 2, H / 2 + 4);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
}

/* ==== 3. RangeHall：建馆 / 登记碰撞 / 灯光开关 ==== */
export class RangeHall {
    /* scene：主场景；collision：BattleMap 的 CollisionWorld；props：loadProps 结果 */
    constructor(scene, collision, props) {
        this.scene = scene;
        this.collision = collision || null;
        this.props = props || null;
        this.group = new THREE.Group();
        this.group.name = 'rangeHall';
        this._lights = [];             // 馆内点光（setActive 开关）
        this._disposables = [];
        this._built = false;
    }

    build() {
        if (this._built) return this;
        this._built = true;
        const H = RANGE_HALL;
        const cx = H.cx, cz = H.cz, F = H.floorY;

        /* -- 素材：贴图 + 共享材质 -- */
        const wallTex = toTex(concreteWallTexture(), 9, 1.4);
        const floorTex = toTex(concreteFloorTexture(), 13, 12);
        const ceilTex = toTex(ceilingTexture(), 14, 14);
        const slatTex = toTex(rubberSlatTexture(), 10, 1);
        const woodTex = toTex(woodTexture(), 1, 1);
        const matFloor = this._mat(new THREE.MeshStandardMaterial({ map: floorTex, roughness: 0.94, metalness: 0 }));
        const matWall = this._mat(new THREE.MeshStandardMaterial({ map: wallTex, roughness: 0.95, metalness: 0 }));
        const matCeil = this._mat(new THREE.MeshStandardMaterial({ map: ceilTex, roughness: 0.96, metalness: 0 }));
        const matConcrete = this._mat(new THREE.MeshStandardMaterial({ color: 0xa6a49d, roughness: 0.95 }));
        const matSteel = this._mat(new THREE.MeshStandardMaterial({ color: 0x45484c, roughness: 0.6, metalness: 0.55 }));
        const matHazard = this._mat(new THREE.MeshStandardMaterial({ map: toTex(hazardTexture(), 20, 1), roughness: 0.85 }));
        const matRubber = this._mat(new THREE.MeshStandardMaterial({ map: slatTex, roughness: 0.9 }));
        const matWood = this._mat(new THREE.MeshStandardMaterial({ map: woodTex, roughness: 0.8 }));
        const matGlass = this._mat(new THREE.MeshStandardMaterial({
            color: 0x9fb6c4, transparent: true, opacity: 0.16, roughness: 0.12,
            metalness: 0.1, side: THREE.DoubleSide, depthWrite: false,
        }));
        const matPanel = this._mat(new THREE.MeshStandardMaterial({
            color: 0x2c2f33, emissive: new THREE.Color(0xdfeaf4), emissiveIntensity: 1.6, roughness: 0.4,
        }));

        /* -- 壳体：地坪（含馆外混凝土散水）/ 四墙 / 吊顶（挡太阳=室内恒暗） -- */
        this._box(40, 0.5, 39.6, cx + 2, F - 0.25, cz, matFloor, true, true);
        this._box(52, 3.0, 52, cx + 2, F - 1.55, cz, matConcrete, false, false);   // 散水坡座
        this._box(40, 0.4, 39.6, cx + 2, F + 6.0, cz, matCeil, true, true);        // 吊顶 castShadow
        const wallH = 6.3, wy = F + 3.0;
        this._box(39, wallH, 0.5, cx + 2, wy, cz - 18.75, matWall, true, true);    // 北墙
        this._box(39, wallH, 0.5, cx + 2, wy, cz + 18.75, matWall, true, true);    // 南墙
        this._box(0.5, wallH, 38, cx - 17.25, wy, cz, matWall, true, true);        // 西墙（射击位后）
        this._box(0.5, wallH, 38, cx + 21.25, wy, cz, matWall, true, true);        // 东墙（挡弹端）

        /* -- 立柱（贴墙一圈）+ 吊顶横梁：各合 1 mesh -- */
        const colGeos = [], beamGeos = [];
        const colAt = (x, z) => {
            const g = new THREE.BoxGeometry(0.55, 5.8, 0.55);
            g.translate(x, F + 2.9, z);
            colGeos.push(g);
        };
        for (const lx of [-13, -6, 1, 8, 15]) {
            colAt(cx + lx, cz - 17.9);
            colAt(cx + lx, cz + 17.9);
            const bg = new THREE.BoxGeometry(0.32, 0.5, 37);
            bg.translate(cx + lx, F + 5.45, cz);
            beamGeos.push(bg);
        }
        colAt(cx - 16.9, cz - 9); colAt(cx - 16.9, cz + 9);
        const cols = new THREE.Mesh(mergeGeometries(colGeos), matConcrete);
        cols.receiveShadow = true;
        this.group.add(cols); this._track(cols.geometry);
        const beams = new THREE.Mesh(mergeGeometries(beamGeos), matSteel);
        this.group.add(beams); this._track(beams.geometry);

        /* -- 顶部成排长条灯板（自发光常亮）+ 点光（靶场模式才亮，保帧率） -- */
        const panelGeos = [];
        for (const lx of [-9.5, -2.5, 4.5, 11.5]) {
            for (const pz of [-6.5, 6.5]) {
                const g = new THREE.BoxGeometry(4.6, 0.12, 0.62);
                g.translate(cx + lx, F + 5.55, cz + pz);
                panelGeos.push(g);
            }
        }
        const panels = new THREE.Mesh(mergeGeometries(panelGeos), matPanel);
        this.group.add(panels); this._track(panels.geometry);
        for (const lx of [-10, 1.5, 13]) {
            for (const pz of [-6.5, 6.5]) {
                const l = new THREE.PointLight(0xcfe0ec, 26, 34, 2);
                l.position.set(cx + lx, F + 5.0, cz + pz);
                l.visible = false;                     // 默认灭：进场 setActive(true)
                this.group.add(l);
                this._lights.push(l);
            }
        }

        /* -- 尽端挡弹结构：斜置橡胶缓弹墙 + 墙沿红白警示带 + 沙袋排 -- */
        const baffle = this._box(0.35, 3.4, 36, cx + 18.7, F + 1.55, cz, matRubber, false, true);
        baffle.rotation.z = -0.3;                      // 顶面向挡弹端后倾（top→+X）
        this._box(0.06, 0.5, 36, cx + 20.94, F + 4.9, cz, matHazard, false, false);
        if (this.props) {
            for (const [bz, br] of [[-13.5, 0.12], [-4.5, -0.08], [4.5, 0.06], [13.5, -0.1]]) {
                const s = this.props.make('sandbags');
                s.position.set(cx + 16.6, F, cz + bz);
                s.rotation.y = br;
                this.group.add(s);
            }
        }
        // 挡弹前排碰撞（一根长盒罩住沙袋排；挡弹斜墙本体另行注册）
        this._col(cx + 16.7, cz, 1.2, 15, 0, 1.6);

        /* -- 射击位 ×3（车道）：木质台面 + 下实上玻璃隔断 + 车道编号 -- */
        const laneDigits = ['5', '6', '7'];
        H._laneZ = [];                                 // 调试可读：三条射位 z
        [-1, 0, 1].forEach((k, i) => {
            const lz = cz + k * H.laneOff;
            H._laneZ.push(lz);
            // 台面（木）+ 前板 + 两侧板
            this._box(2.4, 0.06, 0.85, cx - 10.75, F + 1.05, lz, matWood, false, true);
            this._box(0.06, 1.02, 0.85, cx - 10.32, F + 0.51, lz, matSteel, false, true);
            for (const dz of [-0.425, 0.425]) {
                this._box(0.9, 1.02, 0.05, cx - 10.75, F + 0.51, lz + dz, matSteel, false, true);
            }
            this._col(cx - 10.75, lz, 1.35, 0.5, 0, 1.1);
        });
        // 隔断挡墙（车道分界 cz±6）：下实墙 + 玻璃 + 顶盖 + 端柱 + 车道小号牌
        for (const [pz, digit] of [[cz - 6, '5'], [cz + 6, '6']]) {
            this._box(5.2, 1.15, 0.1, cx - 13.4, F + 0.575, pz, matConcrete, false, true);
            this._box(5.2, 1.0, 0.05, cx - 13.4, F + 1.73, pz, matGlass, false, false);
            this._box(5.2, 0.12, 0.14, cx - 13.4, F + 2.28, pz, matSteel, false, false);
            for (const px of [cx - 16, cx - 10.8]) {
                this._box(0.12, 2.3, 0.16, px, F + 1.15, pz, matSteel, false, false);
            }
            const plate = this._plane(0.5, 0.7, laneNumberTexture(digit));
            plate.position.set(cx - 10.86, F + 1.6, pz);
            plate.rotation.y = -Math.PI / 2;           // 面朝射击位（-X）
            this.group.add(plate);
            this._col(cx - 13.4, pz, 2.6, 0.12, 0, 2.3);
        }
        // 东墙大号车道编号（参考图的 5/6 大字）
        for (let i = 0; i < 3; i++) {
            const big = this._plane(1.5, 2.1, laneNumberTexture(laneDigits[i]));
            big.position.set(cx + 20.93, F + 3.4, cz + (i - 1) * H.laneOff);
            big.rotation.y = -Math.PI / 2;             // 面朝射手（-X）
            this.group.add(big);
        }

        /* -- 射击线黄黑警示斜纹带 + 10/15/25m 距离细线/立牌 -- */
        // 斜纹画进贴图：条带沿 Z 铺开 → 纹理 repeat 只在 v 向加密（repeat 归纹理管）
        const fireBand = this._plane(0.6, 37, toTex(hazardTexture(), 1, 16));
        fireBand.rotation.x = -Math.PI / 2;
        fireBand.position.set(cx - 11.3, F + 0.012, cz);
        fireBand.renderOrder = 1;
        this.group.add(fireBand);
        const trapBand = this._plane(0.6, 37, toTex(hazardTexture(), 1, 16));
        trapBand.rotation.x = -Math.PI / 2;
        trapBand.position.set(cx + 17.6, F + 0.012, cz);
        trapBand.renderOrder = 1;
        this.group.add(trapBand);
        const matLine = this._mat(new THREE.MeshBasicMaterial({ color: 0x35342f, transparent: true, opacity: 0.45, depthWrite: false }));
        const marks = [[cx - 1, '10M'], [cx + 4, '15M'], [cx + 14, '25M']];
        for (const [mx, label] of marks) {
            const line = new THREE.Mesh(new THREE.PlaneGeometry(0.12, 37), matLine);
            line.rotation.x = -Math.PI / 2;
            line.position.set(mx, F + 0.012, cz);
            line.renderOrder = 1;
            this.group.add(line);
            this._track(line.geometry);
            for (const sz of [-14, 14]) {              // 距离立牌（配对分列两侧）
                const post = this._box(0.06, 0.9, 0.06, mx, F + 0.45, cz + sz, matSteel, false, false);
                const plate = this._plane(0.5, 0.5, distanceTexture(label));
                plate.position.set(mx, F + 1.02, cz + sz + (sz < 0 ? 0.02 : -0.02));
                plate.rotation.y = sz < 0 ? 0 : Math.PI;   // 南牌朝 +Z / 北牌朝 −Z
                this.group.add(plate);
            }
        }

        /* -- 馆内道具：安全告示牌×2 / 灭火器 / 路锥×3 / 弹药箱×2摞 / 密封门 -- */
        const sign1 = this._plane(1.7, 1.28, dangerSignTexture());
        sign1.position.set(cx - 16.94, F + 2.55, cz - 5);
        sign1.rotation.y = Math.PI / 2;                // 西墙面朝 +X（射手回身可见）
        this.group.add(sign1);
        const sign2 = this._plane(1.7, 1.28, rulesSignTexture());
        sign2.position.set(cx - 16.94, F + 2.55, cz + 5);
        sign2.rotation.y = Math.PI / 2;
        this.group.add(sign2);

        const matRed = this._mat(new THREE.MeshStandardMaterial({ color: 0xb3251d, roughness: 0.45, metalness: 0.2 }));
        this._box(0.26, 0.7, 0.08, cx - 14, F + 1.1, cz - 18.42, matSteel, false, false);  // 灭火器挂架
        const ext = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 0.55, 10), matRed);
        ext.position.set(cx - 14, F + 0.95, cz - 18.3);
        this.group.add(ext); this._track(ext.geometry);
        this._box(0.2, 0.05, 0.1, cx - 14, F + 1.26, cz - 18.3, matSteel, false, false);   // 压把

        const matCone = this._mat(new THREE.MeshStandardMaterial({ color: 0xc2571f, roughness: 0.7 }));
        const coneAt = (x, z) => {
            this._box(0.4, 0.05, 0.4, x, F + 0.025, z, matSteel, false, false);
            const body = new THREE.Mesh(new THREE.ConeGeometry(0.17, 0.55, 12), matCone);
            body.position.set(x, F + 0.3, z);
            this.group.add(body); this._track(body.geometry);
            const band = new THREE.Mesh(new THREE.CylinderGeometry(0.115, 0.125, 0.1, 12),
                this._mat(new THREE.MeshStandardMaterial({ color: 0xe4e2da, roughness: 0.6 })));
            band.position.set(x, F + 0.3, z);
            this.group.add(band); this._track(band.geometry);
        };
        coneAt(cx - 9.5, cz + 16.2); coneAt(cx + 15.5, cz - 16.2); coneAt(cx - 16, cz + 8.5);

        const matCrate = this._mat(new THREE.MeshStandardMaterial({ color: 0x4a5b40, roughness: 0.8, metalness: 0.1 }));
        const crateAt = (x, z, tiers) => {
            for (let t = 0; t < tiers; t++) {
                this._box(0.85, 0.42, 0.5, x, F + 0.21 + t * 0.43, z, matCrate, false, true);
            }
            const st = this._plane(0.6, 0.22, ammoStencilTexture());
            st.position.set(x + 0.44, F + 0.21 + (tiers - 1) * 0.43, z);
            st.rotation.y = Math.PI / 2;
            this.group.add(st);
            this._col(x, z, 0.45, 0.28, 0, 0.45 * tiers + 0.05);
        };
        crateAt(cx - 15.5, cz + 15.6, 2);
        crateAt(cx - 15.5, cz - 10, 1);

        // 密封门（贴西墙装饰，门后即墙=不可通行）
        this._box(1.1, 2.25, 0.1, cx - 16.92, F + 1.12, cz, matSteel, false, false);
        this._box(1.3, 0.12, 0.16, cx - 16.9, F + 2.3, cz, matSteel, false, false);
        this._box(0.07, 0.07, 0.7, cx - 16.85, F + 1.05, cz, matConcrete, false, false);   // 推杆

        // 馆外横幅（行动模式远看的门面，西墙外侧）
        const banner = this._plane(7, 1.6, hallBannerTexture());
        banner.position.set(cx - 17.56, F + 4.2, cz);
        banner.rotation.y = -Math.PI / 2;              // 面朝 -X（地图中心方向）
        this.group.add(banner);

        /* -- 碰撞登记：四面墙 + 挡弹斜墙（OBB 满高，弹与人都出不去） -- */
        this._col(cx - 17.25, cz, 0.25, 19, 0, wallH);
        this._col(cx + 21.25, cz, 0.25, 19, 0, wallH);
        this._col(cx + 2, cz - 18.75, 19, 0.25, 0, wallH);
        this._col(cx + 2, cz + 18.75, 19, 0.25, 0, wallH);
        this._col(cx + 18.7, cz, 0.5, 18, 0, 4.2);     // 挡弹斜墙（含倾倒量的保守盒）

        /* -- 馆内地坪注册：室内行走/抛壳/掉落弹匣全部落在水泥地坪上 -- */
        if (this.collision && this.collision.addFloor) {
            this.collision.addFloor(cx + 2, cz, 18.5, 18, F);
        }

        this.scene.add(this.group);
        return this;
    }

    /* 靶场模式开关：只开关 6 盏点光（灯板自发光常亮，无每帧开销） */
    setActive(on) {
        for (const l of this._lights) l.visible = !!on;
    }

    dispose() {
        this.scene.remove(this.group);
        for (const d of this._disposables) d.dispose && d.dispose();
        this._disposables.length = 0;
        this._lights.length = 0;
        this._built = false;
    }

    /* ---- 内部工具 ---- */

    _box(w, h, d, x, y, z, mat, castShadow, receiveShadow) {
        const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
        m.position.set(x, y, z);
        m.castShadow = !!castShadow;
        m.receiveShadow = !!receiveShadow;
        this.group.add(m);
        this._track(m.geometry);
        return m;
    }

    _plane(w, h, tex) {
        const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h),
            new THREE.MeshStandardMaterial({ map: tex, roughness: 0.85 }));
        this._track(m.geometry, m.material, tex);
        return m;
    }

    _mat(mat) { this._disposables.push(mat); return mat; }
    _track(...items) { this._disposables.push(...items); }

    /* 碰撞登记（馆内专用：以地坪 F 为基座的 OBB，h=离地坪高度；
     * 弹道 top 判定与室内行走高度一致，addBox 的地形基座在馆内不准） */
    _col(cx, cz, hx, hz, rotY, h) {
        if (this.collision && this.collision.addFloorBox) {
            this.collision.addFloorBox(cx, cz, hx, hz, rotY, h, RANGE_HALL.floorY);
        }
    }
}
