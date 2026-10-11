import * as THREE from 'three';
import { citySites } from './earthLights.js';

/*
 * 地球城市楼群模块（契约见 out/earth-cities-design.md §4）
 *   build(deps) -> { group, cities }
 *     deps   = { landAt, radius }    // landAt: (latDeg,lonDeg)=>boolean（earth.js 掩码采样）
 *     group  = THREE.Group，局部原点 = 行星中心，调用方必须 mesh.add(group)
 *              （随 mesh.rotation.y 自转同转，禁挂 holder，§2.2）；初始 visible=false
 *     子节点 = 每城 1 个 InstancedMesh（共享 1 份 translate(0,0.5,0) 的 BoxGeometry）
 *     cities = [{ name, country, lat, lon, tier, pop, desc, pos, hitR }]
 *
 * 落点事实源唯一：import { citySites }（earthLights.js 命名导出）——灯光与楼严格对位。
 * 坐标公式 = 文档 §2.1 唯一公式（已逐字核对 lib/three.module.js:39771-39784）。
 *
 * 自检清单（写完已跑 /tmp 桩测试，见提交说明）：
 *   ① 城市数与实例数 = 层级表合计；② 逐实例高度 ≤ hMax、足迹 ∈ [4e-5,1.1e-4]；
 *   ③ |pos| ≥ radius（楼不陷入球内）、基座抬升 ε=4e-5；④ 姿态基正交右手（det=+1）；
 *   ⑤ 经纬→局部坐标与逆变换往返一致；⑥ hitR ≈ 2.93e-4~2.96e-4（radius=0.014）。
 */

/* ========================= 随机数（固定种子 → 布局可复现、灯光与楼稳定咬合） ========================= */

function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
        a |= 0;
        a = (a + 0x6D2B79F5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

/* Box-Muller 高斯：CBD 梯度抽样用（|gauss|·σ 的均值 ≈ 0.8σ） */
function gauss(rng) {
    let u = 0;
    while (u === 0) u = rng();
    const v = rng();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/* ========================= 层级参数（§4.2 / §5 表） ========================= */

const TIER_COUNT = { 1: 220, 2: 140, 3: 80, 4: 40 };                 // 每城实例数
const TIER_SIGMA = { 1: 0.55, 2: 0.42, 3: 0.32, 4: 0.24 };           // 高斯散布 σ（度）
const TIER_HMAX  = { 1: 3.2e-4, 2: 2.4e-4, 3: 1.7e-4, 4: 1.1e-4 };   // 楼高上限（绝对单位）
const EPS_BASE   = 4e-5;        // 基座抬升（贴地防 z-fight，§8.2：余量 60× 深度分辨率）
const FOOT_MIN   = 4e-5;        // 足迹下限
const FOOT_SPAN  = 7e-5;        // 足迹跨度 → 足迹 ∈ [4e-5, 1.1e-4]
const HIT_MIN_DEG = 1.2;        // 点击热区最小角半径（度）
const MAX_TRY    = 9;           // 落点验陆重抽上限（1+8，仍失败按原样落=码头楼）

const DEG = Math.PI / 180;

/* ========================= 坐标公式（§2.1 唯一公式，禁止变体） ========================= */

/* 经纬 → 行星局部坐标（h = 海拔偏移；P=(−R'sinθcosφ, R'cosθ, R'sinθsinφ)） */
function latLonToLocal(latDeg, lonDeg, R, h, out) {
    const phi = lonDeg * DEG;
    const th = (90 - latDeg) * DEG;
    const st = Math.sin(th), ct = Math.cos(th);
    const r = R + h;
    return out.set(-r * st * Math.cos(phi), r * ct, r * st * Math.sin(phi));
}

/* ========================= 防御性落陆（ask 硬要求：先 landAt 校验） ========================= */

/* citySites 已做主搜索（名义点起、步长 0.35°、最远 ~30°）；此处只兜底：万一站点仍落海
 * （citySites found=false 兜底路径），向邻域再做小半径螺旋搜索挪到陆地，仍无则保持原样
 * （岛城观感，§9-1）。确定性：无随机数，纯环形扫描。 */
function settleOnLand(landAt, lat, lon) {
    if (landAt(lat, lon)) return { lat: lat, lon: lon };
    const cosLat = Math.max(0.02, Math.cos(lat * DEG));
    for (let k = 1; k <= 14; k++) {                       // 半径 0.35°~4.9°
        const r = k * 0.35;
        const n = Math.max(8, Math.round(2 * Math.PI * r / 0.35));
        for (let a = 0; a < n; a++) {
            const az = a / n * Math.PI * 2;
            const la = lat + r * Math.cos(az);
            if (Math.abs(la) >= 85) continue;
            const lo = lon + r * Math.sin(az) / cosLat;
            if (landAt(la, lo)) return { lat: la, lon: lo };
        }
    }
    return { lat: lat, lon: lon };
}

/* ========================= 入口 ========================= */

export function build(deps) {
    const group = new THREE.Group();
    group.name = 'earthCities';
    const cities = [];

    /* deps 缺省零副作用：返回空组（集成侧另有 tex.landAt 守卫，双保险） */
    if (!deps || typeof deps.landAt !== 'function' || !isFinite(deps.radius) || deps.radius <= 0) {
        group.visible = false;
        return { group: group, cities: cities };
    }
    const landAt = deps.landAt, R = deps.radius;

    /* 共享几何：单位盒原点移到底面中心 → 实例缩放直接「底面贴地、向上长高」（§4.2-2） */
    const boxGeo = new THREE.BoxGeometry(1, 1, 1);
    boxGeo.translate(0, 0.5, 0);

    /* 城市材质：0x2a1e10 暖色微自发光 = 夜侧窗光（昼侧由集成侧 onBeforeCompile
     * 昼夜补丁按太阳方向归零，§6；roughness/metalness 按 §4.2-6）。
     * 40 城参数相同 → 共享 1 份材质，补丁 traverse 只需改一个对象。 */
    const cityMat = new THREE.MeshStandardMaterial({
        roughness: 0.95,
        metalness: 0,
        emissive: new THREE.Color(0x2a1e10),
        emissiveIntensity: 0.9,
    });

    const rng = mulberry32(0xec1713);   // 固定种子：布局逐次加载一致
    const m4 = new THREE.Matrix4();
    const basis = new THREE.Matrix4();
    const q = new THREE.Quaternion(), qYaw = new THREE.Quaternion();
    const pos = new THREE.Vector3();
    const east = new THREE.Vector3(), up = new THREE.Vector3(), zen = new THREE.Vector3();
    const scl = new THREE.Vector3();
    const col = new THREE.Color();
    const AXIS_Y = new THREE.Vector3(0, 1, 0);

    const sites = citySites(landAt);    // 唯一事实源：与夜景灯光同点位（earthLights 命名导出）

    for (let si = 0; si < sites.length; si++) {
        const s = sites[si];
        const tier = s.tier >= 1 && s.tier <= 4 ? s.tier : 3;
        const count = TIER_COUNT[tier];
        const sigma = isFinite(s.sigmaDeg) && s.sigmaDeg > 0 ? s.sigmaDeg : TIER_SIGMA[tier];
        const hMax = TIER_HMAX[tier];

        /* 落点再校验（硬要求：先 landAt 校验，海上向邻域搜索挪到陆地） */
        const settled = settleOnLand(landAt, s.lat, s.lon);
        const lat0 = settled.lat, lon0 = settled.lon;
        const cosLat0 = Math.max(0.02, Math.cos(lat0 * DEG));

        const imesh = new THREE.InstancedMesh(boxGeo, cityMat, count);

        for (let i = 0; i < count; i++) {
            /* 高斯散布抽样 + 验陆重抽（≤8 次，仍失败按原样落=沿海码头楼，§4.2-4） */
            let latB = lat0, lonB = lon0, d = 0;
            for (let t = 0; t < MAX_TRY; t++) {
                d = Math.abs(gauss(rng)) * sigma;
                const az = rng() * Math.PI * 2;
                latB = Math.max(-85, Math.min(85, lat0 + d * Math.cos(az)));
                lonB = lon0 + d * Math.sin(az) / cosLat0;       // 小圆近似
                if (t === MAX_TRY - 1 || landAt(latB, lonB)) break;
            }

            /* CBD 梯度：中心摩天楼核，四周低矮裙楼（h = hMax·(0.18+0.82·rand^2.6)·exp(−(d/σ)²·1.2)） */
            const shape = 0.18 + 0.82 * Math.pow(rng(), 2.6);
            const h = hMax * shape * Math.exp(-(d / sigma) * (d / sigma) * 1.2);

            /* 足迹：east/north 两向独立抽（4e-5 ~ 1.1e-4） */
            const w1 = FOOT_MIN + rng() * FOOT_SPAN;
            const w2 = FOOT_MIN + rng() * FOOT_SPAN;

            /* 基座抬升 ε 贴地（pos = latLonToLocal(latB, lonB, radius, ε)） */
            latLonToLocal(latB, lonB, R, EPS_BASE, pos);

            /* 姿态：沿法线竖起 + 随机偏航（§2.1 切向基；x×y=z ⇒ 第三轴 = east×up） */
            const phi = lonB * DEG;
            const st = Math.sin((90 - latB) * DEG), ct = Math.cos((90 - latB) * DEG);
            up.set(-st * Math.cos(phi), ct, st * Math.sin(phi));            // N，|N|=1 解析成立
            east.set(Math.sin(phi), 0, Math.cos(phi));
            zen.copy(east).cross(up);
            basis.makeBasis(east, up, zen);
            q.setFromRotationMatrix(basis);
            qYaw.setFromAxisAngle(AXIS_Y, rng() * Math.PI * 2);
            q.multiply(qYaw);                       // 偏航在楼局部系（绕自身竖轴）

            scl.set(w1, h, w2);
            m4.compose(pos, q, scl);
            imesh.setMatrixAt(i, m4);

            /* 颜色：混凝土灰蓝微随机为主体；5% 玻璃偏蓝（§4.2-4）；4% 暖光立面
             * （ask 硬要求「少量楼顶暖光自发光」的逐实例成分；自发光本体在
             * cityMat.emissive，夜侧经集成补丁整体点亮） */
            const roll = rng();
            if (roll < 0.05) {
                col.setRGB(0.45, 0.55, 0.7);
            } else if (roll < 0.09) {
                col.setRGB(1.0, 0.84, 0.58);
            } else {
                const g = 0.55 + rng() * 0.25;
                col.setRGB(g * 0.94, g, g * 1.08);
            }
            imesh.setColorAt(i, col);
        }
        imesh.instanceMatrix.needsUpdate = true;
        if (imesh.instanceColor) imesh.instanceColor.needsUpdate = true;
        imesh.computeBoundingSphere();      // r160 按实例并集（lib/three.module.js:32700-32719）
        group.add(imesh);

        /* 站点数据（点击拾取用，§4.1）：pos = 站点贴地点，hitR = 热区半径（必有值，
         * 禁止缺省——SphereGeometry 缺参会生成 radius=1 巨球，lib:39709） */
        const sitePos = latLonToLocal(lat0, lon0, R, EPS_BASE, new THREE.Vector3());
        const hitR = Math.max(2.2 * sigma, HIT_MIN_DEG) * DEG * R;
        cities.push({
            name: s.name,
            country: s.country,
            lat: lat0,
            lon: lon0,
            tier: tier,
            pop: s.pop,
            desc: s.desc,
            pos: sitePos,
            hitR: hitR,
        });
    }

    group.visible = false;      // 初始隐藏，集成侧按模式+距离门控（§7.1-5）
    return { group: group, cities: cities };
}
