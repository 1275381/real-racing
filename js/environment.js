import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { grassTexture, concreteTexture, sandTexture, buildingTexture, skyMaterial } from './textures.js';
import { mulberry32 } from './util.js';

const SUN_DIR = new THREE.Vector3(0.52, 0.46, 0.72).normalize();

// 主题外观配置
const THEMES = {
    country: {
        skyTop: 0x2f63b8, skyMid: 0x86aede, skyBot: 0xdfe9ee,
        fog: 0xdfe9ee, fogNear: 320, fogFar: 2200,
        mtn: 0x7d93a8, hemiSky: 0xbfd7ef, hemiGround: 0x53703f,
    },
    city: {
        skyTop: 0x54749f, skyMid: 0x9fb0c0, skyBot: 0xd2d6d8,
        fog: 0xc9ced2, fogNear: 240, fogFar: 1650,
        mtn: 0x69707a, hemiSky: 0xc4cdd6, hemiGround: 0x565c62,
    },
    desert: {
        skyTop: 0x4f86c8, skyMid: 0xd8b98a, skyBot: 0xf2dfba,
        fog: 0xecd8ae, fogNear: 300, fogFar: 2000,
        mtn: 0xb06f48, hemiSky: 0xdce6f2, hemiGround: 0xa08258,
    },
};

// 天空、光照、地形、树木、远山、云、岩石；setTheme 切换城市/沙漠/乡野外观
export function createEnvironment(scene, tracks, renderer) {
    const maxAniso = renderer.capabilities.getMaxAnisotropy();
    const clearOfAll = (x, z, d) => tracks.every((t) => t.isClearOfRoad(x, z, d));

    // ---- 天空穹顶 ----
    const skyMat = skyMaterial();
    skyMat.uniforms.sunDir.value.copy(SUN_DIR);
    const sky = new THREE.Mesh(new THREE.SphereGeometry(4200, 32, 16), skyMat);
    sky.frustumCulled = false;
    scene.add(sky);

    // ---- 光照 ----
    const sun = new THREE.DirectionalLight(0xfff2dd, 2.7);
    sun.position.copy(SUN_DIR).multiplyScalar(220);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.near = 40;
    sun.shadow.camera.far = 520;
    const sh = 95;
    sun.shadow.camera.left = -sh; sun.shadow.camera.right = sh;
    sun.shadow.camera.top = sh; sun.shadow.camera.bottom = -sh;
    sun.shadow.bias = -0.0006;
    sun.shadow.normalBias = 0.02;
    scene.add(sun);
    scene.add(sun.target);
    const hemi = new THREE.HemisphereLight(0xbfd7ef, 0x53703f, 0.65);
    scene.add(hemi);

    // ---- 地面（三种主题材质预构建）----
    const groundMats = {
        country: new THREE.MeshStandardMaterial({ map: grassTexture(maxAniso), color: 0xbfcfb2, roughness: 1 }),
        city: new THREE.MeshStandardMaterial({ map: concreteTexture(maxAniso), roughness: 0.95 }),
        desert: new THREE.MeshStandardMaterial({ map: sandTexture(maxAniso), roughness: 1 }),
    };
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(6500, 6500), groundMats.country);
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.15;
    ground.receiveShadow = true;
    scene.add(ground);

    // ---- 远山剪影 ----
    const rng = mulberry32(2024);
    const mtnMat = new THREE.MeshStandardMaterial({ color: 0x7d93a8, roughness: 1, metalness: 0, flatShading: true });
    const mtn = new THREE.InstancedMesh(new THREE.ConeGeometry(1, 1, 7), mtnMat, 14);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    for (let i = 0; i < 14; i++) {
        const a = (i / 14) * Math.PI * 2 + rng() * 0.4;
        const R = 1250 + rng() * 550;
        const hgt = 150 + rng() * 190;
        s.set(280 + rng() * 320, hgt, 280 + rng() * 320);
        q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rng() * 3);
        p.set(Math.cos(a) * R, hgt * 0.28 - 18, Math.sin(a) * R);
        m.compose(p, q, s);
        mtn.setMatrixAt(i, m);
    }
    mtn.instanceMatrix.needsUpdate = true;
    mtn.frustumCulled = false;
    scene.add(mtn);

    // ---- 树木（实例化，避开所有赛道）----
    const trunkGeo = new THREE.CylinderGeometry(0.42, 0.62, 3.4, 6);
    trunkGeo.translate(0, 1.7, 0);
    const leafGeo = new THREE.ConeGeometry(2.9, 7.6, 8);
    leafGeo.translate(0, 6.6, 0);
    const trunkMat = new THREE.MeshStandardMaterial({ color: 0x6e4a2c, roughness: 0.95 });
    const leafMat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.9 });
    const COUNT = 190;
    const trunks = new THREE.InstancedMesh(trunkGeo, trunkMat, COUNT);
    const leaves = new THREE.InstancedMesh(leafGeo, leafMat, COUNT);
    const col = new THREE.Color();
    let placed = 0, guard = 0;
    while (placed < COUNT && guard++ < 6000) {
        const x = -750 + rng() * 1500, z = -800 + rng() * 1550;
        if (!clearOfAll(x, z, 16)) continue;
        const sc = 0.75 + rng() * 0.85;
        q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rng() * 6.28);
        s.set(sc, sc * (0.9 + rng() * 0.5), sc);
        p.set(x, 0, z);
        m.compose(p, q, s);
        trunks.setMatrixAt(placed, m);
        leaves.setMatrixAt(placed, m);
        col.setHSL(0.29 + rng() * 0.06, 0.5 + rng() * 0.25, 0.26 + rng() * 0.12);
        leaves.setColorAt(placed, col);
        placed++;
    }
    trunks.count = leaves.count = placed;
    trunks.instanceMatrix.needsUpdate = true;
    leaves.instanceMatrix.needsUpdate = true;
    if (leaves.instanceColor) leaves.instanceColor.needsUpdate = true;
    trunks.castShadow = leaves.castShadow = true;
    trunks.frustumCulled = leaves.frustumCulled = false;
    scene.add(trunks, leaves);

    // ---- 岩石点缀 ----
    const rocks = new THREE.InstancedMesh(
        new THREE.DodecahedronGeometry(1.15, 0),
        new THREE.MeshStandardMaterial({ color: 0x8d8d88, roughness: 1, flatShading: true }), 42);
    for (let i = 0; i < 42; i++) {
        let x, z, tries = 0;
        do { x = -700 + rng() * 1400; z = -760 + rng() * 1470; } while (!clearOfAll(x, z, 13) && ++tries < 50);
        s.set(0.6 + rng() * 1.8, 0.5 + rng() * 1.1, 0.6 + rng() * 1.8);
        q.setFromAxisAngle(new THREE.Vector3(rng() * 2 - 1, 1, rng() * 2 - 1).normalize(), rng() * 3);
        m.compose(new THREE.Vector3(x, s.y * 0.3, z), q, s);
        rocks.setMatrixAt(i, m);
    }
    rocks.instanceMatrix.needsUpdate = true;
    rocks.castShadow = true;
    rocks.frustumCulled = false;
    scene.add(rocks);

    // ---- 城市楼宇（沿 city 赛道走廊）----
    const buildings = new THREE.Group();
    buildings.visible = false;
    for (const trk of tracks) {
        if (trk.theme !== 'city') continue;
        const N = trk.N;
        const step = Math.max(5, Math.round(N / 42));
        const bTex = buildingTexture();
        const mats = [
            new THREE.MeshStandardMaterial({ map: bTex, roughness: 0.8, metalness: 0.08 }),
            new THREE.MeshStandardMaterial({ map: bTex, color: 0xc9ccd2, roughness: 0.85, metalness: 0.05 }),
            new THREE.MeshStandardMaterial({ map: bTex, color: 0xaeb2a8, roughness: 0.9 }),
        ];
        let placedB = 0, guardB = 0;
        while (placedB < 84 && guardB++ < 400) {
            const i = ((guardB * step) % N + N) % N;
            const side = guardB % 2 === 0 ? 1 : -1;
            const off = 17 + rng() * 30;
            const x = trk.pts[i].x - trk.leftV[i].x * off * side;
            const z = trk.pts[i].z - trk.leftV[i].z * off * side;
            if (!clearOfAll(x, z, 13)) continue;
            const w = 9 + rng() * 11, d = 9 + rng() * 11;
            const h = 9 + Math.pow(rng(), 1.6) * 34;
            const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mats[placedB % 3]);
            b.position.set(x, h / 2, z);
            b.rotation.y = rng() * Math.PI;
            b.castShadow = true;
            buildings.add(b);
            placedB++;
        }
    }
    scene.add(buildings);

    // ---- 沙漠道具：三针仙人掌 + 红岩平顶山 ----
    const desertProps = new THREE.Group();
    desertProps.visible = false;
    const cacGeo = (() => {
        const t = new THREE.CylinderGeometry(0.3, 0.38, 2.8, 8); t.translate(0, 1.4, 0);
        const a1 = new THREE.CylinderGeometry(0.18, 0.2, 1.2, 7); a1.translate(0, 0.6, 0);
        a1.rotateZ(0.9); a1.translate(0.55, 1.5, 0);
        const a2 = new THREE.CylinderGeometry(0.18, 0.2, 1.0, 7); a2.translate(0, 0.5, 0);
        a2.rotateZ(-1.1); a2.translate(-0.5, 1.9, 0);
        return mergeGeometries([t, a1, a2]);
    })();
    const cacMat = new THREE.MeshStandardMaterial({ color: 0x4e7c3a, roughness: 0.9 });
    const cacti = new THREE.InstancedMesh(cacGeo, cacMat, 46);
    for (let i = 0; i < 46; i++) {
        let x, z, tries = 0;
        do { x = -700 + rng() * 1400; z = -760 + rng() * 1470; } while (!clearOfAll(x, z, 14) && ++tries < 50);
        const sc = 0.7 + rng() * 1.1;
        q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rng() * 6.28);
        m.compose(new THREE.Vector3(x, 0, z), q, new THREE.Vector3(sc, sc * (0.85 + rng() * 0.5), sc));
        cacti.setMatrixAt(i, m);
    }
    cacti.instanceMatrix.needsUpdate = true;
    cacti.castShadow = true;
    cacti.frustumCulled = false;
    desertProps.add(cacti);

    const mesaMat = new THREE.MeshStandardMaterial({ color: 0xb06f48, roughness: 1, flatShading: true });
    const mesas = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.62, 1, 1, 8), mesaMat, 12);
    for (let i = 0; i < 12; i++) {
        const a = (i / 12) * Math.PI * 2 + rng() * 0.5;
        const R = 620 + rng() * 320;
        const hgt = 42 + rng() * 60;
        s.set(120 + rng() * 160, hgt, 120 + rng() * 160);
        q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rng() * 3);
        m.compose(new THREE.Vector3(Math.cos(a) * R, hgt * 0.42, Math.sin(a) * R), q, s);
        mesas.setMatrixAt(i, m);
    }
    mesas.instanceMatrix.needsUpdate = true;
    mesas.frustumCulled = false;
    desertProps.add(mesas);
    scene.add(desertProps);

    // ---- 云朵 ----
    const cloudTex = cloudTexture();
    const clouds = [];
    for (let i = 0; i < 14; i++) {
        const mat = new THREE.SpriteMaterial({ map: cloudTex, transparent: true, opacity: 0.62, depthWrite: false, fog: false });
        const sp = new THREE.Sprite(mat);
        const sc = 340 + rng() * 480;
        sp.scale.set(sc, sc * 0.42, 1);
        sp.position.set(-1600 + rng() * 3200, 360 + rng() * 260, -1600 + rng() * 3200);
        sp.userData.speed = 1.5 + rng() * 2.5;
        scene.add(sp);
        clouds.push(sp);
    }

    // ---- 主题切换 ----
    function treesVisible(v) { trunks.visible = leaves.visible = v; }
    function setTheme(name) {
        const T = THEMES[name] ?? THEMES.country;
        ground.material = groundMats[name] ?? groundMats.country;
        skyMat.uniforms.topColor.value.set(T.skyTop);
        skyMat.uniforms.midColor.value.set(T.skyMid);
        skyMat.uniforms.botColor.value.set(T.skyBot);
        if (scene.fog) {
            scene.fog.color.set(T.fog);
            scene.fog.near = T.fogNear;
            scene.fog.far = T.fogFar;
        }
        hemi.color.set(T.hemiSky);
        hemi.groundColor.set(T.hemiGround);
        mtnMat.color.set(T.mtn);
        mesaMat.color.set(name === 'desert' ? 0xb06f48 : 0x8a7a68);
        treesVisible(name === 'country');
        buildings.visible = name === 'city';
        desertProps.visible = name === 'desert';
    }

    function followShadow(targetPos) {
        sun.target.position.copy(targetPos);
        sun.position.copy(targetPos).addScaledVector(SUN_DIR, 230);
    }
    function updateClouds(dt) {
        for (const c of clouds) {
            c.position.x += c.userData.speed * dt;
            if (c.position.x > 1800) c.position.x = -1800;
        }
    }

    return { sun, hemi, followShadow, updateClouds, setTheme, SUN_DIR };
}

function cloudTexture() {
    const S = 256;
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const g = c.getContext('2d');
    for (let i = 0; i < 26; i++) {
        const x = S * 0.2 + Math.random() * S * 0.6;
        const y = S * 0.35 + Math.random() * S * 0.3;
        const r = S * 0.08 + Math.random() * S * 0.14;
        const grad = g.createRadialGradient(x, y, 0, x, y, r);
        grad.addColorStop(0, 'rgba(255,255,255,0.75)');
        grad.addColorStop(1, 'rgba(255,255,255,0)');
        g.fillStyle = grad;
        g.beginPath(); g.arc(x, y, r, 0, 7); g.fill();
    }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
}
