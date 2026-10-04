import * as THREE from 'three';
import { gunMaterials } from './gunTextures.js';

/* ==== 1. RIFLE 数值表（guns.gd:14-16 + onfoot.gd:151-158/162-168/772-775 移植） ====
 * dmg/cd/mag/spread/range ← guns.gd rifle 原值；
 * recoil {kick 上抬, growth 连发累增, drift 水平漂移} ← onfoot.gd:158 rifle 行
 * [0.17, 0.09, 0.10]；开镜 6 折、上限 6°、0.25s 后 45°/s 回落、开镜速度 dt*5
 * ← onfoot.gd:772-775/787；仅 reload 1.5s 拉长为可读动画（战术 1.8 / 空仓 2.6）。 */
export const RIFLE = {
    id: 'rifle', name: '突击步枪',
    dmg: 20, cd: 0.13, mag: 30,
    reloadTactical: 1.8, reloadEmpty: 2.6,
    spread: 0.015, adsSpreadMul: 0.1, range: 250,
    recoil: { kick: 0.17, growth: 0.09, drift: 0.10 },
    recoilAdsMul: 0.6, recoilCapDeg: 6,
    recoilRecoverDegPerSec: 45, recoilRecoverDelay: 0.25,
    adsSpeed: 5
};

/* ==== 2. 拼装小工具 ==== */

function box(w, h, d, mat, x = 0, y = 0, z = 0) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    m.position.set(x, y, z);
    return m;
}

/* 圆柱默认沿 Y，转到沿 Z（枪管/管件用） */
function cylZ(r, len, mat, x = 0, y = 0, z = 0, seg = 20) {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, len, seg), mat);
    m.rotation.x = Math.PI / 2;
    m.position.set(x, y, z);
    return m;
}

/* 沿 Y 的短圆柱（准星针等） */
function cylY(r, len, mat, x = 0, y = 0, z = 0, seg = 12) {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, len, seg), mat);
    m.position.set(x, y, z);
    return m;
}

/* ==== 3. buildRifle()：程序化多部件拼枪 ====
 * 约定：原点=弹匣井中心；本地 −Z 为枪口；全长约 0.79m（真突击步枪比例）。
 * 返回 { root, parts }，parts 全部为命名节点（root.getObjectByName('mag') 可得）。
 * 关键参考点写入 root.userData：
 *   muzzle     枪口点（本地）
 *   sight      机瞄瞄准线中点 {y,z}（GunView 据此计算 ADS 对准位）
 *   shellPort  抛壳窗（本地，按接口约定 (0.04,0.03,0.12)）
 * 弹膛轴线（枪管中心）在 y=+0.05。 */
export function buildRifle() {
    const M = gunMaterials();
    const BORE_Y = 0.05;

    const root = new THREE.Group();
    root.name = 'rifle';
    const parts = {};

    /* ---- 3.1 receiver 机匣（上机匣+下机匣+导轨+弹匣井+左右小件） ---- */
    const receiver = new THREE.Group();
    receiver.name = 'receiver';
    receiver.add(box(0.050, 0.050, 0.250, M.receiverMat, 0, 0.043, -0.015));   // 上机匣
    receiver.add(box(0.044, 0.006, 0.250, M.receiverMat, 0, 0.071, -0.015));   // 顶部导轨基座
    for (let i = 0; i < 14; i++) {                                             // 导轨防滑齿
        receiver.add(box(0.046, 0.0045, 0.009, M.receiverMat, 0, 0.076, -0.128 + i * 0.017));
    }
    receiver.add(box(0.046, 0.042, 0.200, M.receiverMat, 0, 0.000, -0.005));   // 下机匣
    receiver.add(box(0.056, 0.062, 0.068, M.receiverMat, 0, -0.028, 0.000));   // 弹匣井（原点在此）
    receiver.add(box(0.060, 0.010, 0.075, M.receiverMat, 0, -0.056, 0.000));   // 弹匣井裙边
    receiver.add(box(0.002, 0.018, 0.060, M.boltMat, 0.0255, 0.045, -0.010));  // 抛壳窗盖（右）
    const deflector = box(0.009, 0.020, 0.013, M.receiverMat, 0.026, 0.050, 0.035); // 抛壳导流板
    deflector.rotation.y = -0.5;
    receiver.add(deflector);
    receiver.add(cylZ(0.007, 0.012, M.boltMat, 0.026, 0.055, 0.060));          // 前助推器
    receiver.add(box(0.006, 0.010, 0.010, M.boltMat, 0.0245, 0.005, 0.030));   // 弹匣卡榫（右）
    receiver.add(box(0.004, 0.008, 0.022, M.boltMat, -0.0245, 0.012, 0.055));  // 保险 selector（左）
    parts.receiver = receiver;
    root.add(receiver);

    /* ---- 3.2 trigger 扳机护圈（护圈+扳机） ---- */
    const trigger = new THREE.Group();
    trigger.name = 'trigger';
    trigger.add(box(0.022, 0.004, 0.062, M.receiverMat, 0, -0.060, 0.042));    // 护圈底条
    trigger.add(box(0.022, 0.026, 0.005, M.receiverMat, 0, -0.047, 0.013));   // 护圈前柱
    trigger.add(box(0.022, 0.020, 0.005, M.receiverMat, 0, -0.050, 0.073));   // 护圈后柱
    const blade = box(0.006, 0.026, 0.009, M.boltMat, 0, -0.040, 0.043);       // 扳机
    blade.rotation.x = -0.18;
    trigger.add(blade);
    parts.trigger = trigger;
    root.add(trigger);

    /* ---- 3.3 grip 握把（聚合物，后倾约 22°） ---- */
    const grip = new THREE.Group();
    grip.name = 'grip';
    const g1 = box(0.030, 0.096, 0.046, M.polymerMat, 0, -0.062, 0.096);
    g1.rotation.x = -0.38;
    const g2 = box(0.032, 0.030, 0.020, M.polymerMat, 0, -0.088, 0.117);
    g2.rotation.x = -0.38;
    const g3 = box(0.033, 0.010, 0.050, M.polymerMat, 0, -0.106, 0.104);
    g3.rotation.x = -0.38;
    grip.add(g1, g2, g3);
    parts.grip = grip;
    root.add(grip);

    /* ---- 3.4 stock 枪托（缓冲管+托体+贴腮+托底板，后端 z≈+0.292） ---- */
    const stock = new THREE.Group();
    stock.name = 'stock';
    stock.add(cylZ(0.016, 0.130, M.receiverMat, 0, 0.045, 0.172));             // 缓冲管
    stock.add(cylZ(0.019, 0.014, M.receiverMat, 0, 0.045, 0.117));             // 固定螺环
    const body = box(0.040, 0.098, 0.080, M.polymerMat, 0, 0.032, 0.243);
    body.rotation.x = -0.06;
    stock.add(body);
    const cheek = box(0.036, 0.020, 0.090, M.polymerMat, 0, 0.078, 0.222);     // 贴腮斜面
    cheek.rotation.x = -0.30;
    stock.add(cheek);
    stock.add(box(0.043, 0.100, 0.012, M.polymerMat, 0, 0.030, 0.286));        // 托底缓冲垫
    stock.add(box(0.040, 0.030, 0.050, M.polymerMat, 0, -0.008, 0.262));       // 托底趾部
    parts.stock = stock;
    root.add(stock);

    /* ---- 3.5 barrel 枪管（膛轴 y=0.05，z −0.14 → −0.445） ---- */
    const barrel = new THREE.Group();
    barrel.name = 'barrel';
    barrel.add(cylZ(0.008, 0.305, M.barrelMat, 0, BORE_Y, -0.2925, 16));
    barrel.add(cylZ(0.0135, 0.024, M.barrelMat, 0, BORE_Y, -0.152));           // 枪管螺母
    parts.barrel = barrel;
    root.add(barrel);

    /* ---- 3.6 handguard 护木（聚合物 + 顶部导轨 + M-LOKE 长槽） ---- */
    const handguard = new THREE.Group();
    handguard.name = 'handguard';
    handguard.add(box(0.046, 0.048, 0.240, M.polymerMat, 0, 0.050, -0.260));   // 主体
    handguard.add(box(0.040, 0.005, 0.240, M.receiverMat, 0, 0.0765, -0.260)); // 顶部导轨
    for (let i = 0; i < 9; i++) {                                              // 导轨齿
        handguard.add(box(0.042, 0.004, 0.008, M.receiverMat, 0, 0.081, -0.365 + i * 0.025));
    }
    for (const zz of [-0.185, -0.230, -0.275, -0.320]) {                       // 侧面 M-LOK 槽
        handguard.add(box(0.0025, 0.013, 0.034, M.receiverMat, 0.0235, 0.050, zz));
        handguard.add(box(0.0025, 0.013, 0.034, M.receiverMat, -0.0235, 0.050, zz));
    }
    for (const zz of [-0.210, -0.280]) {                                       // 底面槽
        handguard.add(box(0.013, 0.0025, 0.034, M.receiverMat, 0, 0.0255, zz));
    }
    handguard.add(box(0.050, 0.052, 0.012, M.polymerMat, 0, 0.050, -0.378));   // 前端盖
    parts.handguard = handguard;
    root.add(handguard);

    /* ---- 3.7 sightFront 前准星（带护耳的 A 柱，位于护木前端 z=-0.355） ---- */
    const sightFront = new THREE.Group();
    sightFront.name = 'sightFront';
    sightFront.add(box(0.034, 0.014, 0.036, M.barrelMat, 0, 0.086, -0.355));   // 基座
    const legL = box(0.006, 0.026, 0.014, M.barrelMat, 0.013, 0.098, -0.355);
    legL.rotation.z = -0.18;
    const legR = box(0.006, 0.026, 0.014, M.barrelMat, -0.013, 0.098, -0.355);
    legR.rotation.z = 0.18;
    sightFront.add(legL, legR);
    sightFront.add(cylY(0.0028, 0.024, M.boltMat, 0, 0.091, -0.355));          // 准星针（顶 y≈0.103）
    sightFront.add(box(0.005, 0.022, 0.020, M.barrelMat, 0.014, 0.100, -0.355)); // 护耳
    sightFront.add(box(0.005, 0.022, 0.020, M.barrelMat, -0.014, 0.100, -0.355));
    parts.sightFront = sightFront;
    root.add(sightFront);

    /* ---- 3.8 sightRear 后照门（觇孔环，位于机匣尾 z=+0.09，孔心 y=0.102） ---- */
    const sightRear = new THREE.Group();
    sightRear.name = 'sightRear';
    sightRear.add(box(0.032, 0.016, 0.030, M.barrelMat, 0, 0.087, 0.090));
    sightRear.add(box(0.008, 0.008, 0.008, M.boltMat, 0.018, 0.090, 0.090));   // 高低调节钮
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.0075, 0.0022, 8, 20), M.boltMat);
    ring.position.set(0, 0.102, 0.090);                                        // 觇孔正对 −Z
    sightRear.add(ring);
    sightRear.add(box(0.005, 0.020, 0.024, M.barrelMat, 0.013, 0.101, 0.090)); // 护耳
    sightRear.add(box(0.005, 0.020, 0.024, M.barrelMat, -0.013, 0.101, 0.090));
    parts.sightRear = sightRear;
    root.add(sightRear);

    /* ---- 3.9 mag 弹匣（独立命名节点；STANAG 弧形三段 + 底板）
     * 挂在枪根下、组内子件用绝对坐标；换弹时 GunView 直接改本节点
     * position（下滑/隐藏）并克隆做抛掷体。 ---- */
    const mag = new THREE.Group();
    mag.name = 'mag';
    mag.add(box(0.027, 0.075, 0.060, M.magMat, 0, -0.060, 0.002));             // 上段（井内）
    mag.add(box(0.029, 0.003, 0.060, M.magMat, 0, -0.035, 0.002));             // 加强筋
    const m2 = box(0.027, 0.070, 0.058, M.magMat, 0, -0.125, -0.0025);
    m2.rotation.x = 0.14;                                                      // 弧形前弯
    const m3 = box(0.027, 0.065, 0.056, M.magMat, 0, -0.185, -0.016);
    m3.rotation.x = 0.28;
    const mb = box(0.031, 0.012, 0.062, M.magMat, 0, -0.215, -0.028);
    mb.rotation.x = 0.28;                                                      // 底板
    mag.add(m2, m3, mb);
    parts.mag = mag;
    root.add(mag);

    /* ---- 3.10 bolt 枪机拉栓（T 形拉机柄，位于上机匣尾顶部）
     * 组坐标原点为拉栓常态位；换弹空仓动画沿 +Z（枪尾方向）后拉 4.5cm。 ---- */
    const bolt = new THREE.Group();
    bolt.name = 'bolt';
    bolt.add(box(0.042, 0.007, 0.024, M.boltMat, 0, 0.064, 0.120));            // T 柄横杆
    bolt.add(box(0.010, 0.006, 0.012, M.boltMat, -0.024, 0.064, 0.122));       // 左侧锁扣
    bolt.add(box(0.012, 0.008, 0.080, M.boltMat, 0, 0.062, 0.085));            // 拉杆（常态藏于机匣）
    parts.bolt = bolt;
    root.add(bolt);

    /* ---- 3.11 muzzle 消焰器（鸟笼式，z −0.44 → −0.498） ---- */
    const muzzle = new THREE.Group();
    muzzle.name = 'muzzle';
    muzzle.add(cylZ(0.0115, 0.058, M.barrelMat, 0, BORE_Y, -0.469, 16));
    muzzle.add(cylZ(0.0122, 0.004, M.barrelMat, 0, BORE_Y, -0.455, 16));       // 收口环
    muzzle.add(cylZ(0.0122, 0.004, M.barrelMat, 0, BORE_Y, -0.477, 16));
    muzzle.add(cylZ(0.0045, 0.060, M.receiverMat, 0, BORE_Y, -0.469, 10));     // 中央暗孔
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, 0.006, BORE_Y + 0.0095, -0.468)); // 上泄气槽
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, -0.006, BORE_Y + 0.0095, -0.468));
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, 0.006, BORE_Y - 0.0095, -0.468)); // 下泄气槽
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, -0.006, BORE_Y - 0.0095, -0.468));
    parts.muzzle = muzzle;
    root.add(muzzle);

    /* ---- 3.12 阴影与参考点 ---- */
    root.traverse((o) => { if (o.isMesh) { o.castShadow = true; } });
    root.userData.muzzle = new THREE.Vector3(0, BORE_Y, -0.50);
    root.userData.sight = { y: 0.1025, z: -0.1325 };   // 前/后瞄具中点（ADS 对准线）
    root.userData.shellPort = new THREE.Vector3(0.04, 0.03, 0.12);

    return { root, parts };
}
