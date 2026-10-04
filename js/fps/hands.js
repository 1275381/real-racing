import * as THREE from 'three';

/* =====================================================================
   js/fps/hands.js —— 程序化低模持枪手套（写实度评审 #2：换弹全程带手）
   拼装手法同 gun.js（命名节点 + 少量 Box，零外部资源）。
   本地系：腕部原点、指根 +Y、掌面法线 +Z；四指各 2 节 + 拇指 2 节，
   预弯成 C 形握持姿势；换弹动画只驱动腕部（位置/旋转），指形静态。
   side = +1 右手 / −1 左手：X 坐标与绕 Z 旋转显式乘 side 做镜像
   （不用负 scale，避免法线翻转）。
   ===================================================================== */

function box(w, h, d, mat, x = 0, y = 0, z = 0) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    m.position.set(x, y, z);
    return m;
}

export function buildHand(side = 1) {
    const S = side >= 0 ? 1 : -1;
    /* 战术手套：暗橄榄胶皮掌面 + 卡其腕带 */
    const glove = new THREE.MeshStandardMaterial({ color: 0x2c2a22, roughness: 0.9, metalness: 0.02 });
    const strap = new THREE.MeshStandardMaterial({ color: 0x453d2c, roughness: 0.82, metalness: 0.05 });

    const root = new THREE.Group();
    root.name = S > 0 ? 'handR' : 'handL';

    /* ---- 掌 / 腕袖 / 指根护壳 ---- */
    root.add(box(0.066, 0.078, 0.026, glove, 0, 0.046, 0.004));     // 掌
    root.add(box(0.058, 0.032, 0.052, strap, 0, -0.008, -0.006));    // 腕袖
    root.add(box(0.062, 0.012, 0.030, strap, 0, 0.086, 0.006));      // 指根护壳

    /* ---- 四指各 2 节：向掌面(+Z)预弯 C 形 ---- */
    const fingers = [];
    for (let i = 0; i < 4; i++) {
        const fx = (-0.024 + i * 0.016) * S;
        const k1 = new THREE.Group();
        k1.position.set(fx, 0.090, 0.006);
        k1.rotation.x = 0.95 + i * 0.05;                 // 近节弯（指长微差）
        k1.add(box(0.0135, 0.032, 0.016, glove, 0, 0.016, 0));
        const k2 = new THREE.Group();
        k2.position.set(0, 0.032, 0);
        k2.rotation.x = 1.18;                            // 远节更弯
        k2.add(box(0.0122, 0.028, 0.014, glove, 0, 0.014, 0));
        k1.add(k2);
        root.add(k1);
        fingers.push(k1);
    }

    /* ---- 拇指 2 节：掌侧斜出、对指 ---- */
    const t1 = new THREE.Group();
    t1.position.set(-0.037 * S, 0.052, 0.010);
    t1.rotation.set(0.55, 0, -0.85 * S);
    t1.add(box(0.015, 0.034, 0.018, glove, 0, 0.017, 0));
    const t2 = new THREE.Group();
    t2.position.set(0, 0.034, 0);
    t2.rotation.x = 0.9;
    t2.add(box(0.013, 0.028, 0.015, glove, 0, 0.014, 0));
    t1.add(t2);
    root.add(t1);

    return { root, parts: { fingers, thumb: [t1, t2] } };
}
