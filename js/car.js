import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { blobShadowTexture } from './textures.js';
import { CAR_MODELS, DEFAULT_MODEL } from './carModels.js';

// ---------- Blender GLB 车模（优先） ----------
// 命名契约见 tools/blender/carlib.py：HubXX 转向枢轴 / WheelXX 滚动 / BodyPivot 车身姿态
// 材质 Paint(主色染色) / Accent(副色染色) / TailLight(刹车灯)
const CACHE_BUST = '?v=10';
const _templates = new Map();

// 并行加载全部车型；任何一款失败只是少一个选项，全失败才回退程序化车型。
export async function loadCarTemplates() {
    const loader = new GLTFLoader();
    await Promise.all(CAR_MODELS.map(async (m) => {
        try {
            const gltf = await loader.loadAsync(m.file + CACHE_BUST);
            _templates.set(m.id, gltf.scene);
        } catch (e) {
            console.warn(`车模 ${m.id} 加载失败：`, e && e.message);
        }
    }));
    return _templates.size > 0;
}

export const hasModel = (id) => _templates.has(id);
export const loadedModels = () => CAR_MODELS.filter((m) => _templates.has(m.id));

function buildFromGLB(template, colorHex, accentHex, scene) {
    const root = template.clone(true);
    const matMap = new Map();      // 原材质 -> 每车克隆
    let tailMat = null;
    root.traverse((o) => {
        if (!o.isMesh) return;
        o.castShadow = true;
        const fix = (mt) => {
            if (mt.name === 'Paint' || mt.name === 'Accent') {
                if (!matMap.has(mt)) {
                    const c = mt.clone();
                    c.color.setHex(mt.name === 'Paint' ? colorHex : accentHex);
                    matMap.set(mt, c);
                }
                return matMap.get(mt);
            }
            if (mt.name === 'TailLight') {
                if (!tailMat) {
                    tailMat = mt.clone();
                    tailMat.emissive = new THREE.Color(0xff1a1a);
                }
                return tailMat;
            }
            return mt;
        };
        o.material = Array.isArray(o.material) ? o.material.map(fix) : fix(o.material);
    });

    const ref = (name) => root.getObjectByName(name);
    const bodyPivot = ref('BodyPivot') || root;
    const wheels = {};
    for (const k of ['FL', 'FR', 'RL', 'RR']) {
        const pivot = ref('Hub' + k);
        const spin = ref('Wheel' + k);
        if (!pivot || !spin) throw new Error('GLB 车模缺少 Hub/Wheel 节点: ' + k);
        wheels[k] = { pivot, spin };
    }

    if (!tailMat) tailMat = new THREE.MeshStandardMaterial({ color: 0x300505, emissive: 0xff1a1a, emissiveIntensity: 0.4 });

    // 车底软阴影
    const blob = new THREE.Mesh(
        new THREE.PlaneGeometry(2.75, 5.1),
        new THREE.MeshBasicMaterial({
            map: blobShadowTexture(), transparent: true, depthWrite: false, opacity: 0.85,
        })
    );
    blob.rotation.x = -Math.PI / 2;
    blob.position.y = 0.045;
    blob.renderOrder = 1;
    root.add(blob);

    scene.add(root);
    return { group: root, bodyPivot, wheels, tailMat, dispose() { scene.remove(root); } };
}

// ---------- 程序化车模（回退方案） ----------

// 程序化 GT 跑车模型。局部坐标：+Z 车头，+X 左侧，Y 向上。
// 几何体在多辆车之间共享缓存。

let _geoCache = null;
function geos() {
    if (_geoCache) return _geoCache;

    // 侧面轮廓（x=车长方向, y=高度），挤出成车身
    const profile = new THREE.Shape();
    const P = [
        [-2.28, 0.32], [-2.34, 0.66], [-2.02, 0.86], [-1.42, 0.94],
        [-1.05, 1.18], [-0.52, 1.30], [0.10, 1.31], [0.62, 1.06],
        [1.02, 0.92], [1.98, 0.74], [2.24, 0.58], [2.26, 0.38],
        [1.95, 0.26], [-1.90, 0.24],
    ];
    profile.moveTo(P[0][0], P[0][1]);
    for (let i = 1; i < P.length; i++) profile.lineTo(P[i][0], P[i][1]);
    const shell = new THREE.ExtrudeGeometry(profile, {
        depth: 1.72, bevelEnabled: true, bevelThickness: 0.05,
        bevelSize: 0.06, bevelSegments: 2, steps: 1,
    });
    shell.translate(0, 0, -0.86);
    shell.rotateY(-Math.PI / 2);   // 轮廓 x -> +Z（车头）

    // 挡风玻璃 / 后窗玻璃：贴合轮廓斜面的"贴纸"式面片
    const windshield = quadGeo(
        [-0.72, 1.308, 0.10], [0.72, 1.308, 0.10],
        [0.74, 1.078, 0.60], [-0.74, 1.078, 0.60]
    );
    const rearGlass = quadGeo(
        [-0.68, 1.192, -1.04], [0.68, 1.192, -1.04],
        [0.82, 0.952, -1.42], [-0.82, 0.952, -1.42]
    );

    // 车轮
    const tire = new THREE.CylinderGeometry(0.34, 0.34, 0.27, 22);
    tire.rotateZ(Math.PI / 2);
    const rim = new THREE.CylinderGeometry(0.21, 0.21, 0.29, 18);
    rim.rotateZ(Math.PI / 2);
    const discR = new THREE.CylinderGeometry(0.17, 0.17, 0.30, 14);
    discR.rotateZ(Math.PI / 2);
    const spoke = new THREE.BoxGeometry(0.32, 0.38, 0.045);

    _geoCache = { shell, windshield, rearGlass, tire, rim, discR, spoke };
    return _geoCache;
}

// 由4个角点生成双三角面片
function quadGeo(a, b, c, d) {
    const g = new THREE.BufferGeometry();
    const v = new Float32Array([...a, ...b, ...c, ...a, ...c, ...d]);
    g.setAttribute('position', new THREE.BufferAttribute(v, 3));
    // uv 简单铺满
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 1, 1, 1, 1, 0, 0, 0]), 2));
    g.computeVertexNormals();
    return g;
}

export function buildCar(colorHex, scene, opts = {}) {
    const tpl = _templates.get(opts.model || DEFAULT_MODEL) || _templates.get(DEFAULT_MODEL);
    if (tpl) {
        try {
            return buildFromGLB(tpl, colorHex, opts.accent != null ? opts.accent : 0xf2f4f8, scene);
        } catch (e) {
            console.warn('GLB 车模实例化失败，回退程序化车型：', e);
        }
    }
    const G = geos();

    const paint = new THREE.MeshPhysicalMaterial({
        color: colorHex, metalness: 0.68, roughness: 0.32,
        clearcoat: 0.75, clearcoatRoughness: 0.22, envMapIntensity: 1.1,
    });
    const dark = new THREE.MeshStandardMaterial({ color: 0x15171b, roughness: 0.6, metalness: 0.35 });
    const glass = new THREE.MeshPhysicalMaterial({
        color: 0x0d1218, metalness: 0.35, roughness: 0.08,
        envMapIntensity: 1.6, transparent: true, opacity: 0.92,
        depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2,
        side: THREE.DoubleSide,
    });
    const rimMat = new THREE.MeshStandardMaterial({ color: 0xd8dde4, metalness: 1, roughness: 0.28 });
    const tireMat = new THREE.MeshStandardMaterial({ color: 0x17181a, roughness: 0.96 });
    const chrome = new THREE.MeshStandardMaterial({ color: 0xcfd4da, metalness: 1, roughness: 0.22 });

    const root = new THREE.Group();
    const bodyPivot = new THREE.Group();   // 承载重心转移姿态
    root.add(bodyPivot);

    const shellMesh = new THREE.Mesh(G.shell, paint);
    shellMesh.castShadow = true;
    bodyPivot.add(shellMesh);

    const ws = new THREE.Mesh(G.windshield, glass); ws.renderOrder = 2; bodyPivot.add(ws);
    const rg = new THREE.Mesh(G.rearGlass, glass); rg.renderOrder = 2; bodyPivot.add(rg);

    // 前后包围 / 侧裙
    const splitter = new THREE.Mesh(new THREE.BoxGeometry(1.68, 0.12, 0.55), dark);
    splitter.position.set(0, 0.20, 2.08);
    bodyPivot.add(splitter);
    const diffuser = new THREE.Mesh(new THREE.BoxGeometry(1.62, 0.14, 0.42), dark);
    diffuser.position.set(0, 0.22, -2.18);
    bodyPivot.add(diffuser);
    for (const sx of [-0.88, 0.88]) {
        const skirt = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.14, 2.4), dark);
        skirt.position.set(sx, 0.22, 0);
        bodyPivot.add(skirt);
    }

    // 尾翼
    const wingMat = new THREE.MeshStandardMaterial({ color: 0x101216, roughness: 0.45, metalness: 0.5 });
    for (const sx of [-0.62, 0.62]) {
        const upr = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.26, 0.16), wingMat);
        upr.position.set(sx, 1.04, -2.12);
        bodyPivot.add(upr);
    }
    const foil = new THREE.Mesh(new THREE.BoxGeometry(1.58, 0.06, 0.44), wingMat);
    foil.position.set(0, 1.19, -2.14);
    foil.rotation.x = 0.13;
    foil.castShadow = true;
    bodyPivot.add(foil);
    for (const sx of [-0.79, 0.79]) {
        const plate = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.15, 0.42), wingMat);
        plate.position.set(sx, 1.19, -2.14);
        bodyPivot.add(plate);
    }

    // 大灯（常亮日行灯）
    const headMat = new THREE.MeshStandardMaterial({
        color: 0xf8f4e6, emissive: 0xfff3cf, emissiveIntensity: 1.1,
    });
    for (const sx of [-0.52, 0.52]) {
        const hl = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.08, 0.08), headMat);
        hl.position.set(sx, 0.62, 2.19);
        hl.rotation.x = -0.25;
        bodyPivot.add(hl);
    }
    // 尾灯条（刹车增亮）
    const tailMat = new THREE.MeshStandardMaterial({
        color: 0x300505, emissive: 0xff1a1a, emissiveIntensity: 0.4,
    });
    const tail = new THREE.Mesh(new THREE.BoxGeometry(1.28, 0.07, 0.06), tailMat);
    tail.position.set(0, 0.74, -2.345);
    bodyPivot.add(tail);

    // 排气
    for (const sx of [-0.30, 0.30]) {
        const pipe = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.06, 0.16, 10), chrome);
        pipe.rotation.x = Math.PI / 2;
        pipe.position.set(sx, 0.32, -2.34);
        bodyPivot.add(pipe);
    }

    // 后视镜
    for (const sx of [-0.95, 0.95]) {
        const arm = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.035, 0.05), dark);
        arm.position.set(sx * 0.93, 0.98, 0.48);
        bodyPivot.add(arm);
        const mir = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.10, 0.17), paint);
        mir.position.set(sx * 1.02, 1.01, 0.47);
        bodyPivot.add(mir);
    }

    // ---- 车轮 ----
    function makeWheel(front) {
        const pivot = new THREE.Group();       // 前轮转向枢轴
        const spin = new THREE.Group();
        pivot.add(spin);
        const tireM = new THREE.Mesh(G.tire, tireMat);
        tireM.castShadow = true;
        spin.add(tireM);
        spin.add(new THREE.Mesh(G.rim, rimMat));
        const disc = new THREE.Mesh(G.discR, new THREE.MeshStandardMaterial({ color: 0x4a4d52, metalness: 0.9, roughness: 0.45 }));
        spin.add(disc);
        for (let i = 0; i < 5; i++) {
            const sp = new THREE.Mesh(G.spoke, rimMat);
            sp.rotation.x = (i / 5) * Math.PI;
            sp.scale.set(1, 1, 0.8);
            spin.add(sp);
        }
        if (!front) {
            // 卡钳固定在转向节上
            const cal = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.14, 0.10),
                new THREE.MeshStandardMaterial({ color: 0xd7701e, roughness: 0.5 }));
            cal.position.set(-0.26, 0.06, 0);
            pivot.add(cal);
        }
        return { pivot, spin };
    }

    const TW = 0.84, AF = 1.46, AR = -1.44;
    const wheels = {};
    for (const key of ['FL', 'FR', 'RL', 'RR']) {
        const front = key[0] === 'F';
        const w = makeWheel(front);
        const x = key[1] === 'L' ? TW : -TW;
        w.pivot.position.set(x, 0.34, front ? AF : AR);
        root.add(w.pivot);
        wheels[key] = w;
    }

    // 车底软阴影
    const blob = new THREE.Mesh(
        new THREE.PlaneGeometry(2.75, 5.1),
        new THREE.MeshBasicMaterial({
            map: blobShadowTexture(), transparent: true, depthWrite: false, opacity: 0.85,
        })
    );
    blob.rotation.x = -Math.PI / 2;
    blob.position.y = 0.045;
    blob.renderOrder = 1;
    root.add(blob);

    scene.add(root);
    return {
        group: root, bodyPivot, wheels,
        tailMat, headMat,
        dispose() { scene.remove(root); },
    };
}
