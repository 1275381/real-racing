import * as THREE from 'three';

/* ==== 0. 场地尺度与地形函数（layout.js 引用同一函数，视觉网格与碰撞地面同源） ==== */

export const ARENA = 170;         // 场地半边长：340×340m 交战地域（8× 扩图，mapSpec）
export const BOUNDARY_H = 4.6;    // 边界墙碰撞高度（含铁丝网视觉裕量；随墙加高同步上调）

// 地形起伏：基础三个 octave 正弦噪声（幅值 ≤0.78m、坡度 6.0%，旧版既有）+ 荒野环带大波。
// 荒野起伏：距中心危险区圆心 78m 内（军事基地台地）保持平缓，78→112m 平滑过渡，
// 外围 ±1.5m 大波——解析偏导 20 万采样实测全图最大坡度 9.7%（其中基础项 6.0% 为
// 旧版存量手感，本模块增量 ≈3%）；游戏无坡度物理（贴地跟随），不影响跑动/瞄准；
// 视觉网格与碰撞地面同源本函数（battle_map.gd:96 同思路）
export function terrainHeight(x, z) {
    const base = 0.42 * Math.sin(x * 0.043) * Math.cos(z * 0.050)
           + 0.26 * Math.sin(x * 0.095 + 1.7) * Math.cos(z * 0.083 + 0.6)
           + 0.10 * Math.sin(x * 0.210 + 4.0) * Math.cos(z * 0.190 + 2.2);
    const w = THREE.MathUtils.smoothstep(Math.hypot(x, z + 10), 78, 112);
    if (w <= 0) return base;
    return base + w * (1.0 * Math.sin(x * 0.016 + 0.8) * Math.cos(z * 0.019 - 1.2)
                     + 0.5 * Math.sin(x * 0.031 + 2.1) * Math.cos(z * 0.027 + 0.4));
}

// 边界墙碰撞盒（贴合起伏地形；由 BattleMap 注册进 CollisionWorld）。
// 段数/段长由 ARENA 派生（修硬编码：旧版固定 6 段，60→170 后每边会缺 220m 碰撞），
// 段长上限 ≈20m，链式铺满 ±ARENA 无缺口
export function boundaryBoxes() {
    const out = [];
    const half = ARENA;
    const n = Math.max(6, Math.ceil((ARENA * 2) / 20));
    const seg = (ARENA * 2) / n;
    for (let i = 0; i < n; i++) {
        const c = -half + seg / 2 + i * seg;
        out.push({ cx: c,    cz: half,  hx: seg / 2 + 0.4, hz: 0.4, rotY: 0, h: BOUNDARY_H });
        out.push({ cx: c,    cz: -half, hx: seg / 2 + 0.4, hz: 0.4, rotY: 0, h: BOUNDARY_H });
        out.push({ cx: half, cz: c,     hx: 0.4, hz: seg / 2 + 0.4, rotY: 0, h: BOUNDARY_H });
        out.push({ cx: -half, cz: c,    hx: 0.4, hz: seg / 2 + 0.4, rotY: 0, h: BOUNDARY_H });
    }
    return out;
}

/* ==== 1. 程序化贴图（零外部资源，参考 js/textures.js 手法） ==== */

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

// 地表：戈壁草土混合——干土底 + 橄榄草斑 + 砾石 + 干裂
function groundTexture() {
    const S = 1024;
    const [c, g] = makeCanvas(S, S);
    g.fillStyle = '#8d7a56';
    g.fillRect(0, 0, S, S);
    // 大块草斑（橄榄→枯黄）
    for (let i = 0; i < 90; i++) {
        const grn = Math.random();
        g.fillStyle = `rgba(${86 + grn * 40 | 0},${96 + grn * 34 | 0},${44 + grn * 26 | 0},${0.10 + Math.random() * 0.14})`;
        g.beginPath();
        g.ellipse(Math.random() * S, Math.random() * S, 24 + Math.random() * 90,
            16 + Math.random() * 60, Math.random() * Math.PI, 0, 7);
        g.fill();
    }
    // 干草短线簇（写实度评审 #4：密度上调，平铺周期内高频细节更足）
    for (let i = 0; i < 7200; i++) {
        const v = Math.random();
        g.strokeStyle = `rgba(${120 + v * 60 | 0},${105 + v * 50 | 0},${52 + v * 30 | 0},${0.25 + Math.random() * 0.3})`;
        g.lineWidth = 1;
        const x = Math.random() * S, y = Math.random() * S;
        g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.random() * 4 - 2, y - 3 - Math.random() * 4); g.stroke();
    }
    // 裸土补丁（车碾/风蚀）
    for (let i = 0; i < 40; i++) {
        g.fillStyle = `rgba(${135 + Math.random() * 30 | 0},${112 + Math.random() * 26 | 0},${70 + Math.random() * 22 | 0},0.22)`;
        g.beginPath();
        g.ellipse(Math.random() * S, Math.random() * S, 20 + Math.random() * 70, 10 + Math.random() * 34,
            Math.random() * Math.PI, 0, 7);
        g.fill();
    }
    // 砾石
    for (let i = 0; i < 4200; i++) {
        const v = Math.random();
        g.fillStyle = `rgba(${125 + v * 55 | 0},${115 + v * 45 | 0},${95 + v * 40 | 0},${0.5 + Math.random() * 0.4})`;
        g.fillRect(Math.random() * S, Math.random() * S, 1 + Math.random() * 2.2, 1 + Math.random() * 2.2);
    }
    // 干裂纹
    g.strokeStyle = 'rgba(96,78,52,0.30)';
    for (let i = 0; i < 42; i++) {
        g.lineWidth = 0.8 + Math.random();
        let x = Math.random() * S, y = Math.random() * S;
        g.beginPath(); g.moveTo(x, y);
        for (let k = 0; k < 5; k++) {
            x += Math.random() * 46 - 23; y += Math.random() * 46 - 23;
            g.lineTo(x, y);
        }
        g.stroke();
    }
    return toTex(c, 72, 72);   // 平铺密度与 120m 版持平（≈4.7m/格）
}

// 边界墙：混凝土板 + 污渍 + 顶部压顶条
function boundaryTexture() {
    const W = 512, H = 256;
    const [c, g] = makeCanvas(W, H);
    g.fillStyle = '#9a958c';
    g.fillRect(0, 0, W, H);
    for (let i = 0; i < 5200; i++) {
        const v = 120 + Math.random() * 60;
        g.fillStyle = `rgba(${v},${v - 3},${v - 10},${0.22 + Math.random() * 0.3})`;
        g.fillRect(Math.random() * W, Math.random() * H, 1.6, 1.6);
    }
    for (let i = 0; i < 22; i++) {   // 风化流痕
        g.fillStyle = `rgba(88,84,76,${0.06 + Math.random() * 0.10})`;
        g.fillRect(Math.random() * W, 0, 6 + Math.random() * 26, H * (0.3 + Math.random() * 0.7));
    }
    g.fillStyle = '#6f6a61';          // 板缝
    g.fillRect(0, 0, 3, H); g.fillRect(W / 2, 0, 3, H);
    g.fillStyle = '#7c776d';          // 压顶
    g.fillRect(0, 0, W, 16);
    g.fillStyle = 'rgba(70,66,58,0.8)';  // 底部溅土
    g.fillRect(0, H - 26, W, 26);
    return c;
}

/* ==== 2. 傍晚天空穹（渐变 + 太阳辉光，写法同 js/textures.js skyMaterial，换黄昏调色） ==== */

// 太阳方向（指向太阳的单位向量）：西偏北、仰角 ≈15°，长影拖向东侧。
// 导出给 GunView.setEnvironment 对齐 vm 主灯（写实度评审 #1）
export const SUN_DIR = new THREE.Vector3(-0.80, 0.235, -0.34).normalize();

const SKY = {
    top: new THREE.Color(0x1e2f5c),     // 天顶暮蓝
    mid: new THREE.Color(0x8a6f8f),     // 中层暮紫
    bot: new THREE.Color(0xf5b060),     // 地平线暖橙
    sun: new THREE.Color(0xffd9a3),     // 太阳辉光
    fog: 0xd8a276,                      // 距离雾同地平线色
};

/* ==== 室内/室外氛围预设（靶馆 setIndoor 切换，成对还原） ====
 * indoor：太阳/天光近乎归零（馆内由 rangeHall 灯板+点光照明）、雾改冷灰
 * 短距、曝光微降——进馆即换氛围；vm 主灯方向给顶灯（gunview.setEnvironment 用） */
export const INDOOR_KEY_DIR = new THREE.Vector3(0.18, 1, 0.14).normalize();
const LIGHT_PRESETS = {
    outdoor: { sun: 2.5, hemi: 0.55, hemiSky: 0x93a2cc, hemiGround: 0x9a7b52,
               amb: 0.25, ambColor: 0x4a4438, fog: SKY.fog, fogNear: 100, fogFar: 620,
               exposure: 1.02 },
    indoor:  { sun: 0.05, hemi: 0.32, hemiSky: 0x9fb0be, hemiGround: 0x3e4247,
               amb: 0.10, ambColor: 0x707a84, fog: 0x23282c, fogNear: 36, fogFar: 160,
               exposure: 0.94 },
};

/* 室内环境反射球：冷灰棚（顶亮地暗）——馆内金属枪身反射顶灯而非黄昏天光 */
function hallEnvMaterial() {
    return new THREE.ShaderMaterial({
        side: THREE.BackSide,
        vertexShader: `
            varying vec3 vDir;
            void main() {
                vDir = normalize(position);
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }`,
        fragmentShader: `
            varying vec3 vDir;
            void main() {
                float h = normalize(vDir).y;
                vec3 col = mix(vec3(0.10, 0.11, 0.12), vec3(0.42, 0.47, 0.52), smoothstep(-0.5, 0.75, h));
                col += vec3(0.85, 0.92, 1.0) * smoothstep(0.72, 0.95, h);   // 顶部灯带更亮
                gl_FragColor = vec4(col, 1.0);
                #include <tonemapping_fragment>
                #include <colorspace_fragment>
            }`,
    });
}

function duskSkyMaterial() {
    return new THREE.ShaderMaterial({
        side: THREE.BackSide,
        depthWrite: false,
        fog: false,
        uniforms: {
            topColor: { value: SKY.top.clone() },
            midColor: { value: SKY.mid.clone() },
            botColor: { value: SKY.bot.clone() },
            sunColor: { value: SKY.sun.clone() },
            sunDir: { value: SUN_DIR.clone() },
        },
        vertexShader: `
            varying vec3 vDir;
            void main() {
                vDir = normalize(position);
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }`,
        fragmentShader: `
            uniform vec3 topColor, midColor, botColor, sunColor, sunDir;
            varying vec3 vDir;
            void main() {
                vec3 d = normalize(vDir);
                float h = clamp(d.y, -1.0, 1.0);
                vec3 col = mix(midColor, topColor, pow(clamp((h - 0.02) / 0.55, 0.0, 1.0), 0.65));
                float horiz = 1.0 - clamp(abs(h) / 0.16, 0.0, 1.0);      // 地平线亮带
                col = mix(col, botColor, horiz * 0.9);
                float sd = max(dot(d, normalize(sunDir)), 0.0);
                col += botColor * horiz * pow(sd, 3.0) * 0.5;            // 太阳侧地平线更暖
                col += sunColor * (pow(sd, 720.0) * 1.25                 // 日轮
                                 + pow(sd, 48.0) * 0.34                  // 内晕
                                 + pow(sd, 7.0) * 0.16);                 // 大范围暮光
                col *= mix(1.0, 0.84, clamp(-h * 6.0, 0.0, 1.0));        // 地平线下压暗
                gl_FragColor = vec4(col, 1.0);
                #include <tonemapping_fragment>
                #include <colorspace_fragment>
            }`,
    });
}

/* ==== 3. 远山剪影环（两圈渐远的山脊线，撑出戈壁盆地的纵深） ==== */

function makeRidge(radius, baseH, amp, phase, color) {
    const N = 120;
    const pos = new Float32Array((N + 1) * 2 * 3);
    const idx = [];
    for (let i = 0; i <= N; i++) {
        const a = (i / N) * Math.PI * 2;
        const rr = radius * (1 + 0.05 * Math.sin(a * 5 + phase));          // 山脊错落
        const h = baseH + amp * (0.5 + 0.5 * Math.sin(a * 7 + phase * 2.7))
                + amp * 0.5 * Math.sin(a * 17 + phase);
        const x = Math.cos(a) * rr, z = Math.sin(a) * rr;
        pos.set([x, -4, z], i * 6);                                        // 底
        pos.set([x, Math.max(2, h), z], i * 6 + 3);                        // 顶
        if (i < N) {
            const b = i * 2;
            idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2);
        }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setIndex(idx);
    const mat = new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide, fog: true });
    return new THREE.Mesh(geo, mat);
}

/* ==== 4. Environment：天空 / 灯光 / 雾 / 地表 / 边界，一次装配 ==== */

export class Environment {
    constructor(scene, renderer) {
        this.scene = scene;
        this.renderer = renderer;
        this._disposables = [];
        this.indoor = false;               // 当前是否室内氛围（setIndoor 切换）

        // ---- 天空穹（背景 + PMREM 环境反射，game.js:35-41 同款流程） ----
        const skyMat = duskSkyMaterial();
        const dome = new THREE.Mesh(new THREE.SphereGeometry(680, 40, 20), skyMat);
        scene.add(dome);
        const pmrem = new THREE.PMREMGenerator(renderer);
        const envScene = new THREE.Scene();
        envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 24, 12), duskSkyMaterial()));
        this.duskEnv = pmrem.fromScene(envScene, 0.04).texture;
        scene.environment = this.duskEnv;
        // 室内环境反射：冷灰棚 + 顶灯光带（馆内金属不再反射黄昏天光）
        const hallScene = new THREE.Scene();
        hallScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 24, 12), hallEnvMaterial()));
        const strip = new THREE.Mesh(new THREE.PlaneGeometry(30, 3.5),
            new THREE.MeshBasicMaterial({ color: 0xffffff }));
        strip.position.set(0, 16, 0);
        strip.rotation.x = Math.PI / 2;
        hallScene.add(strip);
        this.indoorEnv = pmrem.fromScene(hallScene, 0.04).texture;
        pmrem.dispose();
        this._track(dome.geometry, skyMat);

        // ---- 距离雾（同地平线暖色；随扩图推远，mask 340m 场内视距） ----
        const op = LIGHT_PRESETS.outdoor;
        scene.fog = new THREE.Fog(op.fog, op.fogNear, op.fogFar);

        // ---- 太阳：傍晚低角度暖光，唯一投影源，阴影相机随玩家平移 ----
        const sun = new THREE.DirectionalLight(0xffcf9c, op.sun);
        sun.castShadow = true;
        sun.shadow.mapSize.set(2048, 2048);
        const sc = sun.shadow.camera;
        sc.near = 10; sc.far = 240;
        sc.left = -38; sc.right = 38; sc.top = 38; sc.bottom = -38;
        sc.updateProjectionMatrix();   // 改过正交边界必须手动刷新（否则停在默认 ±5m）
        sun.shadow.bias = -0.0006;
        sun.shadow.normalBias = 0.04;
        scene.add(sun);
        scene.add(sun.target);
        this.sun = sun;
        this.update(0, new THREE.Vector3(0, 0, 150));

        // ---- 半球光（暮天天光偏蓝、地面反光偏暖）+ 一点环境补光 ----
        this.hemi = new THREE.HemisphereLight(op.hemiSky, op.hemiGround, op.hemi);
        scene.add(this.hemi);
        this.amb = new THREE.AmbientLight(op.ambColor, op.amb);
        scene.add(this.amb);

        // ---- 地表：340×340m 起伏网格（200×200 段，与 terrainHeight 同源） ----
        const gGeo = new THREE.PlaneGeometry(ARENA * 2, ARENA * 2, 200, 200);
        gGeo.rotateX(-Math.PI / 2);
        const gp = gGeo.attributes.position;
        for (let i = 0; i < gp.count; i++) {
            gp.setY(i, terrainHeight(gp.getX(i), gp.getZ(i)));
        }
        gGeo.computeVertexNormals();
        const gMat = new THREE.MeshStandardMaterial({ map: groundTexture(), roughness: 0.96, metalness: 0 });
        const ground = new THREE.Mesh(gGeo, gMat);
        ground.receiveShadow = true;
        scene.add(ground);
        this._track(gGeo, gMat);

        // ---- 场外大地（边界墙外的平地，遮住墙脚与远山之间的空隙） ----
        const apron = new THREE.Mesh(
            new THREE.CircleGeometry(480, 48),
            new THREE.MeshBasicMaterial({ color: 0x7d6c4e, fog: true })
        );
        apron.rotation.x = -Math.PI / 2;
        apron.position.y = -3.2;    // 压到荒野起伏最低谷之下（terrainHeight ≥ −2.6）
        scene.add(apron);
        this._track(apron.geometry, apron.material);

        // ---- 远山剪影两圈 ----
        const r1 = makeRidge(560, 16, 30, 1.3, 0x574a58);
        const r2 = makeRidge(640, 26, 42, 4.1, 0x6a5a60);
        scene.add(r1); scene.add(r2);
        this._track(r1.geometry, r1.material);
        this._track(r2.geometry, r2.material);

        // ---- 场地边界：混凝土围墙 + 四角哨塔柱（碰撞由 BattleMap 注册） ----
        const bTex = toTex(boundaryTexture(), 45, 1);
        const bMat = new THREE.MeshStandardMaterial({ map: bTex, roughness: 0.92, metalness: 0.02 });
        const wallH = 7.0, len = ARENA * 2 + 1.4, th = 0.7;   // 墙加高：荒野起伏（±1.8m）下仍露出 ≥1.8m
        for (let side = 0; side < 4; side++) {
            const alongX = side < 2;   // 0=南(+Z) 1=北(−Z) 2=东(+X) 3=西(−X)
            const w = new THREE.Mesh(new THREE.BoxGeometry(
                alongX ? len : th, wallH, alongX ? th : len), bMat);
            w.position.set(side === 2 ? ARENA : side === 3 ? -ARENA : 0, 0.9,
                           side === 0 ? ARENA : side === 1 ? -ARENA : 0);
            w.receiveShadow = true;
            scene.add(w);
            this._track(w.geometry);
        }
        const pGeo = new THREE.BoxGeometry(1.1, 7.4, 1.1);
        const pMat = new THREE.MeshStandardMaterial({ color: 0x7c776d, roughness: 0.9 });
        for (const sx of [-ARENA, ARENA]) for (const sz of [-ARENA, ARENA]) {
            const p = new THREE.Mesh(pGeo, pMat);
            p.position.set(sx, 1.5, sz);
            p.castShadow = true;
            scene.add(p);
        }
        this._track(pGeo, pMat, bMat, bTex);
    }

    /* 每帧：太阳与阴影相机跟随玩家（吸附 0.5m 网格，避免阴影边缘闪烁） */
    update(dt, playerPos) {
        if (!playerPos) return;
        const tx = Math.round(playerPos.x * 2) / 2;
        const tz = Math.round(playerPos.z * 2) / 2;
        this.sun.target.position.set(tx, 0, tz);
        this.sun.position.set(tx, 0, tz).addScaledVector(SUN_DIR, 110);
    }

    /* ==== 室内/室外氛围切换（靶馆进场 true；出发/回大厅 false） ====
     * 只动灯光/雾/环境反射/曝光，几何零改动；行动模式数值由 outdoor
     * 预设整组还原（与构造值一致），实现「进馆即换氛围」 */
    setIndoor(on) {
        const p = on ? LIGHT_PRESETS.indoor : LIGHT_PRESETS.outdoor;
        this.sun.intensity = p.sun;
        this.hemi.intensity = p.hemi;
        this.hemi.color.setHex(p.hemiSky);
        this.hemi.groundColor.setHex(p.hemiGround);
        this.amb.intensity = p.amb;
        this.amb.color.setHex(p.ambColor);
        this.scene.fog.color.setHex(p.fog);
        this.scene.fog.near = p.fogNear;
        this.scene.fog.far = p.fogFar;
        this.scene.environment = on ? this.indoorEnv : this.duskEnv;
        this.renderer.toneMappingExposure = p.exposure;
        this.indoor = !!on;
    }

    dispose() {
        for (const d of this._disposables) d.dispose && d.dispose();
        this._disposables.length = 0;
    }

    _track(...items) {
        this._disposables.push(...items);
    }
}
