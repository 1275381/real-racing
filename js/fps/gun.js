import * as THREE from 'three';
import { gunMaterials } from './gunTextures.js';
import { GUNS } from './gunsData.js';

/* =====================================================================
   js/fps/gun.js —— 五枪程序化建模库（【枪械】组）
   buildGunMesh(id)：pistol / smg / rifle / shotgun / sniper 五枪拼装。
   数值在 gunsData.js（guns.gd 移植），本文件只管几何。
   契约 C1（接口冻结）：每枪必产
     parts.mag / parts.bolt 命名节点（gunview 掉匣克隆/拉栓动画按名取），
     root.userData.muzzle / sight / shellPort（枪口/机瞄线/抛壳窗参考点）。
   每枪另带（gunview 多枪化用）：
     userData.opticAnchor {y,z}  瞄具导轨接口面（buildScopeMesh 组原点）
     userData.hands {grip,guard,bolt,well}  双手 IK 关键位（换弹随枪型适配）
     userData.slideFire / boltCycle           手枪套筒循环 / 栓动枪机循环
   约定：原点=弹匣井中心；本地 −Z 为枪口；弹膛轴线各枪注明 boreY。
   ===================================================================== */

/* 兼容导出：旧 import { RIFLE } from './gun.js' 仍可用（同一对象） */
export const RIFLE = GUNS.rifle;

/* ==== 1. 拼装小工具 ==== */

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

/* 球（霰弹准星珠等） */
function sphere(r, mat, x = 0, y = 0, z = 0, seg = 10) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, seg, seg), mat);
    m.position.set(x, y, z);
    return m;
}

/* 命名组 */
function grp(name) {
    const g = new THREE.Group();
    g.name = name;
    return g;
}

/* ==== 2. 收尾：阴影 + 参考点 + 手部关键位 ====
 * ref = { boreY, sight:[y,z], shellPort:[x,y,z], opticAnchor:[y,z],
 *         hands:{grip,guard,bolt,well}, slideFire, boltCycle }
 * hands 各位姿 {p:[x,y,z], r:[rx,ry,rz]}（枪本地系，gunview 换算）。 */
function finishGun(root, parts, ref) {
    root.traverse((o) => { if (o.isMesh) { o.castShadow = true; } });
    const u = root.userData;
    u.muzzle = new THREE.Vector3(0, ref.boreY, ref.muzzleZ);
    u.sight = { y: ref.sight[0], z: ref.sight[1] };
    u.shellPort = new THREE.Vector3(...ref.shellPort);
    u.opticAnchor = { y: ref.opticAnchor[0], z: ref.opticAnchor[1] };
    u.hands = ref.hands;
    u.slideFire = !!ref.slideFire;
    u.boltCycle = !!ref.boltCycle;
    /* 弹匣/枪机组静置位（换弹/切枪中断复位用；手枪弹匣带井位偏移+后倾角，
     * 不能假设在原点——gunview 一律从这两个值恢复） */
    u.magHome = parts.mag.position.clone();
    u.boltHome = parts.bolt.position.clone();
    return { root, parts };
}

/* ==== 3. 突击步枪（现有模型原样保留） ==== */

function buildRifleInner() {
    const M = gunMaterials(GUNS.rifle.skin);
    const BORE_Y = 0.05;

    const root = grp('rifle');
    const parts = {};

    /* ---- 3.1 receiver 机匣 ---- */
    const receiver = grp('receiver');
    receiver.add(box(0.050, 0.050, 0.250, M.receiverMat, 0, 0.043, -0.015));
    receiver.add(box(0.044, 0.006, 0.250, M.receiverMat, 0, 0.071, -0.015));
    for (let i = 0; i < 14; i++) {
        receiver.add(box(0.046, 0.0045, 0.009, M.receiverMat, 0, 0.076, -0.128 + i * 0.017));
    }
    receiver.add(box(0.046, 0.042, 0.200, M.receiverMat, 0, 0.000, -0.005));
    receiver.add(box(0.056, 0.062, 0.068, M.receiverMat, 0, -0.028, 0.000));
    receiver.add(box(0.060, 0.010, 0.075, M.receiverMat, 0, -0.056, 0.000));
    receiver.add(box(0.002, 0.018, 0.060, M.boltMat, 0.0255, 0.045, -0.010));
    const deflector = box(0.009, 0.020, 0.013, M.receiverMat, 0.026, 0.050, 0.035);
    deflector.rotation.y = -0.5;
    receiver.add(deflector);
    receiver.add(cylZ(0.007, 0.012, M.boltMat, 0.026, 0.055, 0.060));
    receiver.add(box(0.006, 0.010, 0.010, M.boltMat, 0.0245, 0.005, 0.030));
    receiver.add(box(0.004, 0.008, 0.022, M.boltMat, -0.0245, 0.012, 0.055));
    parts.receiver = receiver;
    root.add(receiver);

    /* ---- 3.2 trigger 扳机护圈 ---- */
    const trigger = grp('trigger');
    trigger.add(box(0.022, 0.004, 0.062, M.receiverMat, 0, -0.060, 0.042));
    trigger.add(box(0.022, 0.026, 0.005, M.receiverMat, 0, -0.047, 0.013));
    trigger.add(box(0.022, 0.020, 0.005, M.receiverMat, 0, -0.050, 0.073));
    const blade = box(0.006, 0.026, 0.009, M.boltMat, 0, -0.040, 0.043);
    blade.rotation.x = -0.18;
    trigger.add(blade);
    parts.trigger = trigger;
    root.add(trigger);

    /* ---- 3.3 grip 握把 ---- */
    const grip = grp('grip');
    const g1 = box(0.030, 0.096, 0.046, M.polymerMat, 0, -0.062, 0.096);
    g1.rotation.x = -0.38;
    const g2 = box(0.032, 0.030, 0.020, M.polymerMat, 0, -0.088, 0.117);
    g2.rotation.x = -0.38;
    const g3 = box(0.033, 0.010, 0.050, M.polymerMat, 0, -0.106, 0.104);
    g3.rotation.x = -0.38;
    grip.add(g1, g2, g3);
    parts.grip = grip;
    root.add(grip);

    /* ---- 3.4 stock 枪托 ---- */
    const stock = grp('stock');
    stock.add(cylZ(0.016, 0.130, M.receiverMat, 0, 0.045, 0.172));
    stock.add(cylZ(0.019, 0.014, M.receiverMat, 0, 0.045, 0.117));
    const body = box(0.040, 0.098, 0.080, M.polymerMat, 0, 0.032, 0.243);
    body.rotation.x = -0.06;
    stock.add(body);
    const cheek = box(0.036, 0.020, 0.090, M.polymerMat, 0, 0.078, 0.222);
    cheek.rotation.x = -0.30;
    stock.add(cheek);
    stock.add(box(0.043, 0.100, 0.012, M.polymerMat, 0, 0.030, 0.286));
    stock.add(box(0.040, 0.030, 0.050, M.polymerMat, 0, -0.008, 0.262));
    parts.stock = stock;
    root.add(stock);

    /* ---- 3.5 barrel 枪管 ---- */
    const barrel = grp('barrel');
    barrel.add(cylZ(0.008, 0.305, M.barrelMat, 0, BORE_Y, -0.2925, 16));
    barrel.add(cylZ(0.0135, 0.024, M.barrelMat, 0, BORE_Y, -0.152));
    parts.barrel = barrel;
    root.add(barrel);

    /* ---- 3.6 handguard 护木 ---- */
    const handguard = grp('handguard');
    handguard.add(box(0.046, 0.048, 0.240, M.polymerMat, 0, 0.050, -0.260));
    handguard.add(box(0.040, 0.005, 0.240, M.receiverMat, 0, 0.0765, -0.260));
    for (let i = 0; i < 9; i++) {
        handguard.add(box(0.042, 0.004, 0.008, M.receiverMat, 0, 0.081, -0.365 + i * 0.025));
    }
    for (const zz of [-0.185, -0.230, -0.275, -0.320]) {
        handguard.add(box(0.0025, 0.013, 0.034, M.receiverMat, 0.0235, 0.050, zz));
        handguard.add(box(0.0025, 0.013, 0.034, M.receiverMat, -0.0235, 0.050, zz));
    }
    for (const zz of [-0.210, -0.280]) {
        handguard.add(box(0.013, 0.0025, 0.034, M.receiverMat, 0, 0.0255, zz));
    }
    handguard.add(box(0.050, 0.052, 0.012, M.polymerMat, 0, 0.050, -0.378));
    parts.handguard = handguard;
    root.add(handguard);

    /* ---- 3.7 sightFront 前准星 ---- */
    const sightFront = grp('sightFront');
    sightFront.add(box(0.034, 0.014, 0.036, M.barrelMat, 0, 0.086, -0.355));
    const legL = box(0.006, 0.026, 0.014, M.barrelMat, 0.013, 0.098, -0.355);
    legL.rotation.z = -0.18;
    const legR = box(0.006, 0.026, 0.014, M.barrelMat, -0.013, 0.098, -0.355);
    legR.rotation.z = 0.18;
    sightFront.add(legL, legR);
    sightFront.add(cylY(0.0028, 0.024, M.boltMat, 0, 0.091, -0.355));
    sightFront.add(box(0.005, 0.022, 0.020, M.barrelMat, 0.014, 0.100, -0.355));
    sightFront.add(box(0.005, 0.022, 0.020, M.barrelMat, -0.014, 0.100, -0.355));
    parts.sightFront = sightFront;
    root.add(sightFront);

    /* ---- 3.8 sightRear 后照门 ---- */
    const sightRear = grp('sightRear');
    sightRear.add(box(0.032, 0.016, 0.030, M.barrelMat, 0, 0.087, 0.090));
    sightRear.add(box(0.008, 0.008, 0.008, M.boltMat, 0.018, 0.090, 0.090));
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.0075, 0.0022, 8, 20), M.boltMat);
    ring.position.set(0, 0.102, 0.090);
    sightRear.add(ring);
    sightRear.add(box(0.005, 0.020, 0.024, M.barrelMat, 0.013, 0.101, 0.090));
    sightRear.add(box(0.005, 0.020, 0.024, M.barrelMat, -0.013, 0.101, 0.090));
    parts.sightRear = sightRear;
    root.add(sightRear);

    /* ---- 3.9 mag 弹匣（STANAG 弧形三段） ---- */
    const mag = grp('mag');
    mag.add(box(0.027, 0.075, 0.060, M.magMat, 0, -0.060, 0.002));
    mag.add(box(0.029, 0.003, 0.060, M.magMat, 0, -0.035, 0.002));
    const m2 = box(0.027, 0.070, 0.058, M.magMat, 0, -0.125, -0.0025);
    m2.rotation.x = 0.14;
    const m3 = box(0.027, 0.065, 0.056, M.magMat, 0, -0.185, -0.016);
    m3.rotation.x = 0.28;
    const mb = box(0.031, 0.012, 0.062, M.magMat, 0, -0.215, -0.028);
    mb.rotation.x = 0.28;
    mag.add(m2, m3, mb);
    parts.mag = mag;
    root.add(mag);

    /* ---- 3.10 bolt 枪机拉栓 ---- */
    const bolt = grp('bolt');
    bolt.add(box(0.042, 0.007, 0.024, M.boltMat, 0, 0.064, 0.120));
    bolt.add(box(0.010, 0.006, 0.012, M.boltMat, -0.024, 0.064, 0.122));
    bolt.add(box(0.012, 0.008, 0.080, M.boltMat, 0, 0.062, 0.085));
    parts.bolt = bolt;
    root.add(bolt);

    /* ---- 3.11 muzzle 消焰器 ---- */
    const muzzle = grp('muzzle');
    muzzle.add(cylZ(0.0115, 0.058, M.barrelMat, 0, BORE_Y, -0.469, 16));
    muzzle.add(cylZ(0.0122, 0.004, M.barrelMat, 0, BORE_Y, -0.455, 16));
    muzzle.add(cylZ(0.0122, 0.004, M.barrelMat, 0, BORE_Y, -0.477, 16));
    muzzle.add(cylZ(0.0045, 0.060, M.receiverMat, 0, BORE_Y, -0.469, 10));
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, 0.006, BORE_Y + 0.0095, -0.468));
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, -0.006, BORE_Y + 0.0095, -0.468));
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, 0.006, BORE_Y - 0.0095, -0.468));
    muzzle.add(box(0.0035, 0.004, 0.028, M.receiverMat, -0.006, BORE_Y - 0.0095, -0.468));
    parts.muzzle = muzzle;
    root.add(muzzle);

    /* ---- 3.12 参考点/手位（与旧 buildRifle 完全一致 + 新增 hands） ---- */
    root.userData.sight = { y: 0.1025, z: -0.1325 };
    return finishGun(root, parts, {
        boreY: BORE_Y, muzzleZ: -0.50,
        sight: [0.1025, -0.1325],
        shellPort: [0.04, 0.03, 0.12],
        opticAnchor: [0.081, -0.06],
        slideFire: false, boltCycle: false,
        hands: {
            grip: { p: [0.020, -0.064, 0.108], r: [0.15, 0.25, 1.30] },
            guard: { p: [0, 0.010, -0.148], r: [-Math.PI / 2, 0, 0] },
            bolt: { p: [0.024, 0.078, 0.20], r: [Math.PI / 2, -0.15, 0.1] },
            well: { p: [0, -0.075, 0.058], r: [0.25, Math.PI, -0.12] },
        },
    });
}

/* ==== 4. 侦察手枪（银灰短套筒 · 副武器） ====
 * 全长约 0.30m：套筒+短管在上，双列握把含弹匣；套筒开火循环（slideFire）。 */

function buildPistolInner() {
    const M = gunMaterials(GUNS.pistol.skin);
    const BORE_Y = 0.045;

    const root = grp('pistol');
    const parts = {};

    /* ---- 4.1 frame 下机架 + 握把（含弹匣井，握把后倾 0.30rad） ---- */
    const frame = grp('frame');
    frame.add(box(0.030, 0.022, 0.140, M.receiverMat, 0, 0.016, -0.045));   // 下机架
    frame.add(box(0.024, 0.006, 0.050, M.receiverMat, 0, 0.030, -0.010));   // 中铰链条
    const gripWell = box(0.030, 0.098, 0.044, M.polymerMat, 0, -0.050, 0.058);
    gripWell.rotation.x = -0.30;
    frame.add(gripWell);                                                     // 握把主体
    const gripBand = box(0.032, 0.020, 0.046, M.polymerMat, 0, -0.020, 0.044);
    gripBand.rotation.x = -0.30;
    frame.add(gripBand);                                                     // 握把上箍
    const butt = box(0.034, 0.014, 0.050, M.polymerMat, 0, -0.100, 0.074);
    butt.rotation.x = -0.30;
    frame.add(butt);                                                         // 握把底
    frame.add(box(0.026, 0.010, 0.024, M.polymerMat, 0, -0.008, 0.010));     // 护弓前根
    frame.add(box(0.005, 0.006, 0.014, M.boltMat, 0.017, 0.022, -0.075));    // 空挂锁扣
    parts.frame = frame;
    root.add(frame);

    /* ---- 4.2 trigger 护弓+扳机 ---- */
    const trigger = grp('trigger');
    const guard = box(0.006, 0.024, 0.008, M.receiverMat, 0, -0.024, -0.020);
    trigger.add(guard);                                                      // 护弓前柱
    const guardBot = box(0.020, 0.005, 0.044, M.receiverMat, 0, -0.035, 0.002);
    trigger.add(guardBot);                                                   // 护弓底
    const blade = box(0.005, 0.018, 0.007, M.boltMat, 0, -0.026, 0.004);
    blade.rotation.x = -0.2;
    trigger.add(blade);
    parts.trigger = trigger;
    root.add(trigger);

    /* ---- 4.3 slide 套筒（银灰主件；parts.bolt=套筒后段，开火随发后坐循环） ---- */
    const slide = grp('slide');
    slide.add(box(0.034, 0.034, 0.185, M.receiverMat, 0, 0.052, -0.058));    // 套筒主体
    for (let i = 0; i < 8; i++) {                                            // 后段防滑纹
        slide.add(box(0.036, 0.026, 0.004, M.receiverMat, 0, 0.052, 0.018 + i * 0.008));
    }
    slide.add(box(0.010, 0.006, 0.016, M.boltMat, 0.020, 0.052, -0.135));    // 抛壳窗
    slide.add(box(0.008, 0.006, 0.014, M.boltMat, -0.020, 0.038, 0.055));    // 松匣钮
    parts.slide = slide;
    root.add(slide);

    /* bolt（契约 C1）：套筒可动后段，slideFire 时 +Z 循环、空仓锁定 */
    const bolt = grp('bolt');
    bolt.add(box(0.0355, 0.030, 0.042, M.boltMat, 0, 0.052, 0.048));         // 后段块
    bolt.add(box(0.006, 0.020, 0.030, M.boltMat, 0.019, 0.048, 0.040));      // 右侧防滑槽
    bolt.add(box(0.006, 0.020, 0.030, M.boltMat, -0.019, 0.048, 0.040));     // 左侧防滑槽
    parts.bolt = bolt;
    root.add(bolt);

    /* ---- 4.4 barrel 短管（套筒前伸出 2cm）+ 复进簧导孔 ---- */
    const barrel = grp('barrel');
    barrel.add(cylZ(0.0075, 0.030, M.barrelMat, 0, BORE_Y, -0.160, 14));
    barrel.add(cylZ(0.0092, 0.008, M.barrelMat, 0, BORE_Y, -0.146, 14));     // 管口环
    parts.barrel = barrel;
    root.add(barrel);

    /* ---- 4.5 机瞄：前准星柱 + 后缺口 ---- */
    const sights = grp('sights');
    sights.add(box(0.005, 0.010, 0.010, M.boltMat, 0, 0.074, -0.138));       // 前柱（顶 y≈0.079）
    sights.add(box(0.018, 0.008, 0.012, M.boltMat, 0, 0.072, 0.030));        // 后缺口座
    sights.add(box(0.004, 0.008, 0.006, M.boltMat, 0.006, 0.078, 0.030));    // 缺口右叶
    sights.add(box(0.004, 0.008, 0.006, M.boltMat, -0.006, 0.078, 0.030));   // 缺口左叶
    parts.sights = sights;
    root.add(sights);

    /* ---- 4.6 mag 弹匣（双列短匣藏于握把，组随握把后倾） ---- */
    const mag = grp('mag');
    mag.rotation.x = -0.30;                                                  // 与握把同角
    mag.position.set(0, -0.016, 0.056);                                      // 井口
    mag.add(box(0.024, 0.082, 0.038, M.magMat, 0, -0.045, 0));               // 匣体
    mag.add(box(0.026, 0.004, 0.040, M.magMat, 0, -0.006, 0));               // 井口衬板
    mag.add(box(0.027, 0.010, 0.042, M.magMat, 0, -0.090, 0.002));           // 底板
    parts.mag = mag;
    root.add(mag);

    return finishGun(root, parts, {
        boreY: BORE_Y, muzzleZ: -0.175,
        sight: [0.0775, -0.054],
        shellPort: [0.026, 0.045, -0.02],
        opticAnchor: [0.069, -0.045],
        slideFire: true, boltCycle: false,
        hands: {
            grip: { p: [0.017, -0.052, 0.062], r: [0.10, 0.22, 1.22] },
            guard: { p: [-0.010, -0.050, 0.042], r: [-1.30, 0.15, -0.25] },
            bolt: { p: [0.022, 0.056, 0.030], r: [1.42, -0.20, 0.15] },
            well: { p: [0, -0.046, 0.056], r: [0.32, Math.PI, -0.10] },
        },
    });
}

/* ==== 5. 冲锋枪（紧凑圆管机匣 + 长直弹匣 + 折叠钢丝托） ====
 * 全长约 0.62m：圆管机匣在上，35 发长直匣垂直下插。 */

function buildSmgInner() {
    const M = gunMaterials(GUNS.smg.skin);
    const BORE_Y = 0.05;

    const root = grp('smg');
    const parts = {};

    /* ---- 5.1 receiver 圆管机匣 + 下机匣 ---- */
    const receiver = grp('receiver');
    receiver.add(cylZ(0.026, 0.300, M.receiverMat, 0, BORE_Y + 0.006, -0.050, 18)); // 主圆管
    receiver.add(box(0.040, 0.052, 0.140, M.receiverMat, 0, -0.012, 0.010));        // 下机匣
    receiver.add(box(0.044, 0.008, 0.130, M.receiverMat, 0, 0.084, -0.045));        // 顶部短轨
    for (let i = 0; i < 7; i++) {
        receiver.add(box(0.040, 0.005, 0.008, M.receiverMat, 0, 0.089, -0.10 + i * 0.018));
    }
    receiver.add(box(0.048, 0.056, 0.052, M.receiverMat, 0, -0.024, -0.012));       // 弹匣井
    receiver.add(box(0.002, 0.014, 0.046, M.boltMat, 0.021, BORE_Y, -0.010));       // 抛壳窗盖
    receiver.add(box(0.005, 0.008, 0.018, M.boltMat, -0.021, 0.016, 0.040));        // 保险
    parts.receiver = receiver;
    root.add(receiver);

    /* ---- 5.2 trigger 护圈 ---- */
    const trigger = grp('trigger');
    trigger.add(box(0.020, 0.004, 0.056, M.receiverMat, 0, -0.052, 0.052));
    trigger.add(box(0.020, 0.022, 0.005, M.receiverMat, 0, -0.041, 0.028));
    trigger.add(box(0.020, 0.018, 0.005, M.receiverMat, 0, -0.043, 0.078));
    const blade = box(0.005, 0.022, 0.008, M.boltMat, 0, -0.033, 0.052);
    blade.rotation.x = -0.18;
    trigger.add(blade);
    parts.trigger = trigger;
    root.add(trigger);

    /* ---- 5.3 grip 握把 ---- */
    const grip = grp('grip');
    const pg1 = box(0.028, 0.088, 0.042, M.polymerMat, 0, -0.056, 0.098);
    pg1.rotation.x = -0.36;
    const pg2 = box(0.030, 0.026, 0.018, M.polymerMat, 0, -0.080, 0.116);
    pg2.rotation.x = -0.36;
    const pg3 = box(0.031, 0.010, 0.046, M.polymerMat, 0, -0.096, 0.104);
    pg3.rotation.x = -0.36;
    grip.add(pg1, pg2, pg3);
    parts.grip = grip;
    root.add(grip);

    /* ---- 5.4 stock 折叠钢丝托（两斜杆 + 肩板） ---- */
    const stock = grp('stock');
    const rodL = box(0.008, 0.008, 0.150, M.boltMat, -0.014, 0.042, 0.150);
    rodL.rotation.x = -0.12;
    const rodR = box(0.008, 0.008, 0.150, M.boltMat, 0.014, 0.042, 0.150);
    rodR.rotation.x = -0.12;
    stock.add(rodL, rodR);
    const crossBar = box(0.036, 0.008, 0.008, M.boltMat, 0, 0.020, 0.205);
    stock.add(crossBar);
    stock.add(box(0.034, 0.078, 0.012, M.polymerMat, 0, 0.018, 0.222));             // 肩板
    parts.stock = stock;
    root.add(stock);

    /* ---- 5.5 barrel 短管 + 锥形消焰器 ---- */
    const barrel = grp('barrel');
    barrel.add(cylZ(0.009, 0.090, M.barrelMat, 0, BORE_Y, -0.245, 14));
    barrel.add(cylZ(0.0135, 0.040, M.barrelMat, 0, BORE_Y, -0.310, 14));            // 锥形套
    barrel.add(cylZ(0.0045, 0.044, M.receiverMat, 0, BORE_Y, -0.310, 10));
    parts.barrel = barrel;
    root.add(barrel);

    /* ---- 5.6 handguard 护筒（机匣前段包覆） ---- */
    const handguard = grp('handguard');
    handguard.add(cylZ(0.029, 0.110, M.polymerMat, 0, BORE_Y + 0.006, -0.150, 16));
    for (const zz of [-0.120, -0.150, -0.180]) {                                    // 散热环槽
        handguard.add(cylZ(0.0305, 0.006, M.receiverMat, 0, BORE_Y + 0.006, zz, 16));
    }
    parts.handguard = handguard;
    root.add(handguard);

    /* ---- 5.7 机瞄：前柱 + 后觇孔环 ---- */
    const sightFront = grp('sightFront');
    sightFront.add(box(0.026, 0.010, 0.014, M.barrelMat, 0, 0.088, -0.205));
    sightFront.add(cylY(0.0026, 0.020, M.boltMat, 0, 0.100, -0.205));               // 前柱（顶 y≈0.110）
    parts.sightFront = sightFront;
    root.add(sightFront);
    const sightRear = grp('sightRear');
    sightRear.add(box(0.026, 0.012, 0.012, M.barrelMat, 0, 0.090, 0.052));
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.0062, 0.0020, 8, 18), M.boltMat);
    ring.position.set(0, 0.104, 0.052);
    sightRear.add(ring);
    parts.sightRear = sightRear;
    root.add(sightRear);

    /* ---- 5.8 mag 长直弹匣（35 发，微前倾） ---- */
    const mag = grp('mag');
    mag.rotation.x = 0.10;
    mag.add(box(0.024, 0.170, 0.050, M.magMat, 0, -0.100, -0.004));
    for (let i = 0; i < 4; i++) {                                                   // 匣壁加强筋
        mag.add(box(0.026, 0.004, 0.052, M.magMat, 0, -0.045 - i * 0.038, -0.004));
    }
    mag.add(box(0.028, 0.012, 0.054, M.magMat, 0, -0.190, -0.010));                 // 底板
    parts.mag = mag;
    root.add(mag);

    /* ---- 5.9 bolt 拉机柄（圆管机匣左侧外露） ---- */
    const bolt = grp('bolt');
    bolt.add(box(0.010, 0.008, 0.052, M.boltMat, -0.026, BORE_Y + 0.006, 0.030));   // 拉机柄杆
    bolt.add(box(0.012, 0.020, 0.014, M.boltMat, -0.032, BORE_Y + 0.006, 0.048));   // 柄头
    parts.bolt = bolt;
    root.add(bolt);

    return finishGun(root, parts, {
        boreY: BORE_Y, muzzleZ: -0.332,
        sight: [0.107, -0.077],
        shellPort: [0.032, 0.038, -0.01],
        opticAnchor: [0.093, -0.045],
        slideFire: false, boltCycle: false,
        hands: {
            grip: { p: [0.018, -0.058, 0.100], r: [0.15, 0.25, 1.28] },
            guard: { p: [0, 0.008, -0.150], r: [-Math.PI / 2, 0, 0] },
            bolt: { p: [0.022, 0.072, 0.150], r: [Math.PI / 2, -0.15, 0.1] },
            well: { p: [0, -0.068, 0.022], r: [0.28, Math.PI, -0.12] },
        },
    });
}

/* ==== 6. 霰弹枪（长管 + 管状弹仓护筒 + 木托木护木 + 短盒式弹匣） ====
 * 全长约 0.95m：Vepr 式——长枪管下置管仓护筒，木护木/木托，配短盒匣便于掉匣动画。 */

function buildShotgunInner() {
    const M = gunMaterials(GUNS.shotgun.skin);
    const BORE_Y = 0.05;

    const root = grp('shotgun');
    const parts = {};

    /* ---- 6.1 receiver 机匣 ---- */
    const receiver = grp('receiver');
    receiver.add(box(0.046, 0.052, 0.220, M.receiverMat, 0, 0.040, -0.020));
    receiver.add(box(0.042, 0.006, 0.100, M.receiverMat, 0, 0.070, -0.040));        // 短导轨
    receiver.add(box(0.048, 0.058, 0.058, M.receiverMat, 0, -0.024, -0.004));       // 弹匣井
    receiver.add(box(0.002, 0.016, 0.050, M.boltMat, 0.0245, 0.040, -0.030));       // 抛壳窗盖
    receiver.add(box(0.005, 0.009, 0.020, M.boltMat, -0.0245, 0.008, 0.036));       // 保险
    parts.receiver = receiver;
    root.add(receiver);

    /* ---- 6.2 trigger 护圈 ---- */
    const trigger = grp('trigger');
    trigger.add(box(0.022, 0.004, 0.060, M.receiverMat, 0, -0.054, 0.038));
    trigger.add(box(0.022, 0.024, 0.005, M.receiverMat, 0, -0.043, 0.012));
    trigger.add(box(0.022, 0.018, 0.005, M.receiverMat, 0, -0.045, 0.066));
    const blade = box(0.006, 0.024, 0.008, M.boltMat, 0, -0.035, 0.038);
    blade.rotation.x = -0.18;
    trigger.add(blade);
    parts.trigger = trigger;
    root.add(trigger);

    /* ---- 6.3 grip + stock 木托（胡桃木色整托） ---- */
    const stock = grp('stock');
    const wrist = box(0.032, 0.086, 0.044, M.woodMat, 0, -0.050, 0.088);
    wrist.rotation.x = -0.35;
    stock.add(wrist);
    const body = box(0.042, 0.100, 0.150, M.woodMat, 0, 0.030, 0.185);
    body.rotation.x = -0.05;
    stock.add(body);
    const cheek = box(0.038, 0.022, 0.100, M.woodMat, 0, 0.076, 0.150);
    cheek.rotation.x = -0.28;
    stock.add(cheek);
    stock.add(box(0.046, 0.104, 0.012, M.polymerMat, 0, 0.024, 0.262));             // 托底胶垫
    parts.stock = stock;
    root.add(stock);

    /* ---- 6.4 barrel 长管 + 管状弹仓护筒 ---- */
    const barrel = grp('barrel');
    barrel.add(cylZ(0.0105, 0.470, M.barrelMat, 0, BORE_Y, -0.385, 16));            // 主长管
    barrel.add(cylZ(0.0135, 0.020, M.barrelMat, 0, BORE_Y, -0.165, 16));            // 管座
    barrel.add(cylZ(0.014, 0.300, M.barrelMat, 0, 0.014, -0.320, 14));              // 管仓护筒（下置）
    barrel.add(cylZ(0.0145, 0.008, M.receiverMat, 0, 0.014, -0.185, 14));           // 护筒前箍
    barrel.add(cylZ(0.0145, 0.008, M.receiverMat, 0, 0.014, -0.455, 14));
    parts.barrel = barrel;
    root.add(barrel);

    /* ---- 6.5 handguard 木护木（包住护筒前段） ---- */
    const handguard = grp('handguard');
    const hg = box(0.044, 0.044, 0.180, M.woodMat, 0, 0.014, -0.300);
    handguard.add(hg);
    for (const zz of [-0.250, -0.300, -0.350]) {                                    // 木面防滑刻槽
        handguard.add(box(0.046, 0.004, 0.010, M.receiverMat, 0, 0.006, zz));
        handguard.add(box(0.046, 0.004, 0.010, M.receiverMat, 0, 0.024, zz));
    }
    parts.handguard = handguard;
    root.add(handguard);

    /* ---- 6.6 机瞄：金属肋条 + 前准星珠 ---- */
    const sights = grp('sights');
    for (let i = 0; i < 5; i++) {                                                   // 肋条（vent rib）
        sights.add(box(0.008, 0.005, 0.050, M.barrelMat, 0, BORE_Y + 0.014, -0.22 - i * 0.062));
    }
    sights.add(sphere(0.0042, M.boltMat, 0, BORE_Y + 0.021, -0.575));               // 前珠（顶 y≈0.075）
    parts.sights = sights;
    root.add(sights);

    /* ---- 6.7 mag 短盒式弹匣（6 发鹿弹，微前弧） ---- */
    const mag = grp('mag');
    mag.add(box(0.030, 0.072, 0.062, M.magMat, 0, -0.055, -0.004));
    mag.add(box(0.032, 0.004, 0.064, M.magMat, 0, -0.030, -0.004));                 // 加强筋
    const mb = box(0.034, 0.012, 0.066, M.magMat, 0, -0.094, -0.010);
    mb.rotation.x = 0.16;
    mag.add(mb);
    parts.mag = mag;
    root.add(mag);

    /* ---- 6.8 bolt 拉机柄（右侧大柄，跟枪机） ---- */
    const bolt = grp('bolt');
    bolt.add(box(0.012, 0.008, 0.070, M.boltMat, 0, 0.058, 0.060));
    bolt.add(cylY(0.009, 0.026, M.boltMat, 0.024, 0.058, 0.082));                   // 球形柄头
    parts.bolt = bolt;
    root.add(bolt);

    return finishGun(root, parts, {
        boreY: BORE_Y, muzzleZ: -0.622,
        sight: [0.0705, -0.40],
        shellPort: [0.034, 0.036, -0.03],
        opticAnchor: [0.074, -0.040],
        slideFire: false, boltCycle: false,
        hands: {
            grip: { p: [0.018, -0.054, 0.100], r: [0.15, 0.25, 1.28] },
            guard: { p: [0, 0.006, -0.300], r: [-Math.PI / 2, 0, 0.05] },
            bolt: { p: [0.026, 0.068, 0.150], r: [Math.PI / 2, -0.15, 0.1] },
            well: { p: [0, -0.062, 0.030], r: [0.26, Math.PI, -0.12] },
        },
    });
}

/* ==== 7. 狙击步枪（长重管 + 两脚架 + 墨绿底盘 + 栓动大枪机） ====
 * 全长约 1.06m：栓动（boltCycle 每发循环枪机），自带 6× 镜挂点。 */

function buildSniperInner() {
    const M = gunMaterials(GUNS.sniper.skin);
    const BORE_Y = 0.055;

    const root = grp('sniper');
    const parts = {};

    /* ---- 7.1 chassis 底盘机匣（墨绿长铝底盘 + 全长导轨） ---- */
    const chassis = grp('chassis');
    chassis.add(box(0.048, 0.054, 0.260, M.receiverMat, 0, 0.042, -0.030));         // 机匣主体
    chassis.add(box(0.044, 0.006, 0.420, M.receiverMat, 0, 0.073, -0.090));         // 全长导轨
    for (let i = 0; i < 20; i++) {
        chassis.add(box(0.040, 0.005, 0.009, M.receiverMat, 0, 0.078, -0.285 + i * 0.019));
    }
    chassis.add(box(0.050, 0.060, 0.052, M.receiverMat, 0, -0.024, -0.006));        // 弹匣井
    chassis.add(box(0.002, 0.018, 0.056, M.boltMat, 0.0255, 0.042, -0.040));        // 抛壳窗盖
    parts.chassis = chassis;
    root.add(chassis);

    /* ---- 7.2 trigger 护圈 ---- */
    const trigger = grp('trigger');
    trigger.add(box(0.022, 0.004, 0.064, M.receiverMat, 0, -0.056, 0.040));
    trigger.add(box(0.022, 0.026, 0.005, M.receiverMat, 0, -0.044, 0.012));
    trigger.add(box(0.022, 0.020, 0.005, M.receiverMat, 0, -0.047, 0.070));
    const blade = box(0.006, 0.026, 0.009, M.boltMat, 0, -0.035, 0.042);
    blade.rotation.x = -0.18;
    trigger.add(blade);
    parts.trigger = trigger;
    root.add(trigger);

    /* ---- 7.3 grip 握把（与底盘一体，坡度更立） ---- */
    const grip = grp('grip');
    const sg1 = box(0.030, 0.094, 0.046, M.polymerMat, 0, -0.058, 0.092);
    sg1.rotation.x = -0.30;
    const sg2 = box(0.032, 0.010, 0.050, M.polymerMat, 0, -0.102, 0.102);
    sg2.rotation.x = -0.30;
    grip.add(sg1, sg2);
    parts.grip = grip;
    root.add(grip);

    /* ---- 7.4 stock 枪托（墨绿底盘托 + 可调贴腮 + 托底板） ---- */
    const stock = grp('stock');
    const spine = box(0.040, 0.038, 0.180, M.polymerMat, 0, 0.040, 0.180);          // 托脊
    stock.add(spine);
    const buttPad = box(0.046, 0.110, 0.014, M.polymerMat, 0, 0.024, 0.268);        // 托底板
    stock.add(buttPad);
    const cheekR = box(0.038, 0.024, 0.090, M.polymerMat, 0, 0.086, 0.210);         // 可调贴腮
    cheekR.rotation.x = -0.22;
    stock.add(cheekR);
    stock.add(box(0.036, 0.028, 0.060, M.polymerMat, 0, -0.010, 0.240));            // 托底钩
    stock.add(box(0.010, 0.010, 0.030, M.boltMat, 0.024, 0.060, 0.230));            // 托底调节钮
    parts.stock = stock;
    root.add(stock);

    /* ---- 7.5 barrel 重管（两段变径）+ 消音/制退器 ---- */
    const barrel = grp('barrel');
    barrel.add(cylZ(0.016, 0.180, M.barrelMat, 0, BORE_Y, -0.200, 16));             // 管颈
    barrel.add(cylZ(0.014, 0.340, M.barrelMat, 0, BORE_Y, -0.450, 16));             // 重管
    barrel.add(cylZ(0.018, 0.070, M.barrelMat, 0, BORE_Y, -0.630, 16));             // 制退器
    for (const dx of [-0.006, 0.006]) {                                             // 侧面泄气孔
        barrel.add(box(0.0035, 0.010, 0.040, M.receiverMat, dx, BORE_Y + 0.006, -0.630));
        barrel.add(box(0.0035, 0.010, 0.040, M.receiverMat, dx, BORE_Y - 0.006, -0.630));
    }
    parts.barrel = barrel;
    root.add(barrel);

    /* ---- 7.6 handguard 护木（底盘前段 + M-LOK 槽） ---- */
    const handguard = grp('handguard');
    handguard.add(box(0.046, 0.050, 0.140, M.polymerMat, 0, 0.045, -0.180));
    for (const zz of [-0.145, -0.185, -0.225]) {
        handguard.add(box(0.0025, 0.012, 0.030, M.receiverMat, 0.0235, 0.045, zz));
        handguard.add(box(0.0025, 0.012, 0.030, M.receiverMat, -0.0235, 0.045, zz));
    }
    parts.handguard = handguard;
    root.add(handguard);

    /* ---- 7.7 bipod 两脚架（折叠收拢于管下） ---- */
    const bipod = grp('bipod');
    const legL2 = box(0.006, 0.130, 0.008, M.boltMat, -0.012, -0.010, -0.290);
    legL2.rotation.x = 0.20;
    legL2.rotation.z = 0.10;
    const legR2 = box(0.006, 0.130, 0.008, M.boltMat, 0.012, -0.010, -0.290);
    legR2.rotation.x = 0.20;
    legR2.rotation.z = -0.10;
    bipod.add(legL2, legR2);
    bipod.add(box(0.020, 0.010, 0.024, M.boltMat, 0, 0.048, -0.255));               // 挂座
    parts.bipod = bipod;
    root.add(bipod);

    /* ---- 7.8 机瞄： backup 前后小型准星 ---- */
    const sightFront = grp('sightFront');
    sightFront.add(box(0.024, 0.010, 0.012, M.barrelMat, 0, 0.092, -0.255));
    sightFront.add(cylY(0.0026, 0.018, M.boltMat, 0, 0.103, -0.255));               // 顶 y≈0.112
    parts.sightFront = sightFront;
    root.add(sightFront);
    const sightRear = grp('sightRear');
    sightRear.add(box(0.024, 0.012, 0.010, M.barrelMat, 0, 0.096, 0.100));
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.0058, 0.0018, 8, 18), M.boltMat);
    ring.position.set(0, 0.108, 0.100);
    sightRear.add(ring);
    parts.sightRear = sightRear;
    root.add(sightRear);

    /* ---- 7.9 mag 短盒弹匣（5 发大口径） ---- */
    const mag = grp('mag');
    mag.add(box(0.026, 0.060, 0.070, M.magMat, 0, -0.050, -0.006));
    mag.add(box(0.028, 0.004, 0.072, M.magMat, 0, -0.028, -0.006));
    mag.add(box(0.030, 0.012, 0.074, M.magMat, 0, -0.084, -0.012));
    parts.mag = mag;
    root.add(mag);

    /* ---- 7.10 bolt 栓动大枪机（右球头柄；boltCycle 每发循环） ---- */
    const bolt = grp('bolt');
    bolt.add(box(0.014, 0.010, 0.090, M.boltMat, 0, 0.066, 0.070));                 // 枪机杆
    bolt.add(cylY(0.011, 0.030, M.boltMat, 0.028, 0.066, 0.098));                   // 球形柄头
    bolt.add(box(0.016, 0.008, 0.030, M.boltMat, 0, 0.066, 0.010));                 // 机头
    parts.bolt = bolt;
    root.add(bolt);

    return finishGun(root, parts, {
        boreY: BORE_Y, muzzleZ: -0.667,
        sight: [0.110, -0.078],
        shellPort: [0.036, 0.038, -0.04],
        opticAnchor: [0.082, -0.040],
        slideFire: false, boltCycle: true,
        hands: {
            grip: { p: [0.020, -0.060, 0.096], r: [0.15, 0.25, 1.30] },
            guard: { p: [0, 0.004, -0.180], r: [-Math.PI / 2, 0, 0] },
            bolt: { p: [0.030, 0.080, 0.170], r: [Math.PI / 2, -0.20, 0.1] },
            well: { p: [0, -0.058, 0.028], r: [0.26, Math.PI, -0.12] },
        },
    });
}

/* ==== 8. 五枪分发 ==== */

const BUILDERS = {
    pistol: buildPistolInner,
    smg: buildSmgInner,
    rifle: buildRifleInner,
    shotgun: buildShotgunInner,
    sniper: buildSniperInner,
};

/* buildGunMesh(id)：五枪统一入口；未知名回退步枪（gunById 同规）。
 * 返回 { root, parts }，契约 C1 见文件头。 */
export function buildGunMesh(id) {
    const fn = BUILDERS[id] || buildRifleInner;
    return fn();
}

/* 兼容旧入口：buildRifle() == buildGunMesh('rifle') */
export function buildRifle() {
    return buildRifleInner();
}
