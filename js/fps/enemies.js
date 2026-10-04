/* =====================================================================
   js/fps/enemies.js —— 敌兵管理（【玩家AI】组）
   模型：assets/fps/soldier.glb?v=1（贴图内嵌，单文件）；
         加载失败降级胶囊人（battlefield.gd:1198-1224 先例）+ 程序化摆动动画。
         lib/addons 无 SkeletonUtils，故每个敌兵独立加载一份 GLB（8×432KB 本地可承受），
         材质天然互不共享，死亡淡出只影响自己。
   AI：状态机 patrol/suspicious/combat/search/dead，1/60 定步（battlefield.gd:22）；
       索敌 FOV110°/分区视距（e.stats.viewDist：wild 50 / elite 60）/LOS 走 collision.rayWall；
       交火点射/精度衰减/卡墙绕行 移植 battlefield.gd:561-581、591-621。
   命中球：battlefield.gd:824-833 公式参数化 SOLDIER_SCALE=1.2
       （头心 y=1.65×S r=0.2×S、胸心 y=1.05×S r=0.5×S）。
   数值（分区兵种表）：中心精英 assault/support/recon 取 battlefield.gd:26-38 原值
       （assault hp70/acc0.095/dmg5-8；support hp80/acc0.115/cd0.09/burst9；
         recon hp65/dmg28-40/cd2.0/burst1/range150/acc0.028）；
       荒野散兵 scout/rifleman 为 wild 弱化档（hp55-65/acc0.06-0.08/dmg4-7）。
       爆头 ×2（battlefield.gd:23）。
   ===================================================================== */
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { weaveHeight, normalFromCanvas, toNormalTexture } from './normalmap.js';

/* ==== 1. 常量（数值均注明出处） ==== */
const SOLDIER_URL = 'assets/fps/soldier.glb?v=1';
const SOLDIER_SCALE = 1.2;                    // interfaces 约定（命中球同源参数化）
const AI_TICK = 1 / 60;                       // battlefield.gd:22
const MAX_STEPS = 3;                          // battlefield.gd:315 每帧最多补 3 步
const HEAD_MUL = 2.0;                         // battlefield.gd:23
/* 分区兵种表（字段含 viewDist；_canSee 改查 e.stats.viewDist）：
 * ELITE 三档 = battlefield.gd:26-38 原值；WILD 两档 = mapSpec 荒野弱化档。
 * speed 沿用各自 gd 原速（交火/巡逻另有 ×0.45 等系数）。 */
const WILD = {
    scout:    { hp: 55, speed: 6.6, dmgMin: 4, dmgMax: 7, cd: 0.14, burst: 3, range: 60,  acc: 0.060, viewDist: 50 },
    rifleman: { hp: 65, speed: 7.0, dmgMin: 4, dmgMax: 7, cd: 0.12, burst: 4, range: 65,  acc: 0.080, viewDist: 50 },
};
const ELITE = {
    assault:  { hp: 70, speed: 7.6, dmgMin: 5, dmgMax: 8,  cd: 0.11, burst: 4, range: 75,  acc: 0.095, viewDist: 60 },
    support:  { hp: 80, speed: 6.6, dmgMin: 5, dmgMax: 7,  cd: 0.09, burst: 9, range: 80,  acc: 0.115, viewDist: 60 },
    recon:    { hp: 65, speed: 7.2, dmgMin: 28, dmgMax: 40, cd: 2.0, burst: 1, range: 150, acc: 0.028, viewDist: 60 },
};
const ELITE_LABEL = { assault: '精锐突击', support: '精锐支援', recon: '精锐狙击' };
const ENGAGE_SPEED_MUL = 0.45;                // 交火移速 ×0.45（interfaces）
const PATROL_SPEED_MUL = 0.45;                // 巡逻步行
const SEARCH_SPEED_MUL = 0.62;                // 搜索小跑
const VIEW_DIST = 60;                         // missionSpec 视距 60m
const FOV_HALF = THREE.MathUtils.degToRad(55); // missionSpec FOV110° 半角
const NEAR_SENSE = 3.0;                       // 贴身必发现（背后 3m 内）
const REACT_TIME = 0.5;                       // suspicious 反应时长
const LOSE_TIME = 3.5;                        // combat 丢 LOS 判脱离
const SEARCH_TIME = 14.0;                     // search 回 patrol
const LOS_RECHECK = 0.4;                      // battlefield.gd:388 视线复测周期
const ENEMY_R = 0.4;                          // 敌兵 OBB 推出半径（battlefield.gd:570）
const SEP_DIST = 2.2, SEP_PUSH = 2.5;         // battlefield.gd:559-560 同队推挤
const MAG_SIZE = 30, RELOAD_T = 2.2;          // battlefield.gd:600-601
const PAUSE_MIN = 1.1, PAUSE_MAX = 2.2;       // battlefield.gd:607 点射间歇
const EYE_H = 1.6;                            // 敌兵眼睛高度（模型 1.775m×1.2）
const MUZZLE_LOCAL = new THREE.Vector3(-0.12, 1.5, 0.95).multiplyScalar(SOLDIER_SCALE); // battlefield.gd:48
const PLAYER_CAP_R = 0.45, PLAYER_CAP_H = 1.7; // 玩家命中胶囊（interfaces）
const DEATH_HOLD = 3.5, DEATH_FADE = 1.2;     // 倒地停留后淡出
const TRACER_POOL = 24, TRACER_SPEED = 320, TRACER_LEN = 3.0;   // 提速去激光感（评审 #5）
const TRACER_RATIO = 0.34;            // 仅约 1/3 敌弹出曳光，其余只枪口闪
const SND_BUDGET_MAX = 6, SND_BUDGET_REFILL = 6; // battlefield.gd:77 每秒 6 发枪声预算
const CALLSIGNS = ['夜枭', '磐石', '疾风', '铁砧', '苍狼', '寒霜', '雷鸣', '赤狐']; // battlefield.gd:52

const _v1 = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _v3 = new THREE.Vector3();

/* 织物法线（军装布纹浮雕，全部敌兵共享一张；写实度评审 #3/#4） */
let _fabricNormal = null;
function fabricNormal() {
    if (!_fabricNormal) {
        _fabricNormal = toNormalTexture(normalFromCanvas(weaveHeight(128, 8, 0.2), 1.1), 8);
    }
    return _fabricNormal;
}

/* 点到竖直线段距离（敌弹打玩家胶囊的近似） */
function distToVertSegment(p, ax, az, y0, y1) {
    const cy = THREE.MathUtils.clamp(p.y, y0, y1);
    const dy = p.y - cy, dx = p.x - ax, dz = p.z - az;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

/* ==== 2. EnemyManager ==== */
export class EnemyManager {
    constructor({ scene, collision, audio } = {}) {
        this.scene = scene;
        this.collision = collision || null;
        this.audio = audio || null;

        /* 回调字段（interfaces 约定，外部赋值） */
        this.onKill = null;             // (name, dist, head)
        this.onPlayerSpotted = null;    // () 首次被发现提示
        this.onEnemyFire = null;        // (muzzleWorldPos, targetPos)
        this.onPlayerHit = null;        // (dmg, fromPos) 覆盖式：设了就不走 player.takeDamage

        /* CombatWorld 伤害分发签名标记：damage(index, dmg, head)，爆头倍率在本类内乘 */
        this.damageStyle = 'head';

        this.enemies = [];
        this.player = null;             // main 装配后 setPlayer(player) 注入
        this.alertMul = 1.0;            // INTEL 完成后全员警戒 ×1.2（missionSpec）
        this._deployRoutes = [];        // 最近一次非空部署（resetAll 复活重铺用）

        this._loader = null;
        this._acc = 0;
        this._playerEye = new THREE.Vector3();
        this._hasPlayerEye = false;
        this._sndBudget = SND_BUDGET_MAX;
        this._tracers = [];
        this._tracerI = 0;
        this._flash = null;             // 共享枪口火光片
        this._flashLight = null;
        this._flashT = 0;

        this._initFx();
    }

    /* ==== 3. 曳光线池 + 枪口火光（自带，不走枪械组） ==== */
    _initFx() {
        if (!this.scene) return;
        const mat = new THREE.LineBasicMaterial({
            color: 0xFFCC59, transparent: true, opacity: 0.5, depthWrite: false,
        });
        for (let i = 0; i < TRACER_POOL; i++) {
            const geo = new THREE.BufferGeometry();
            geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(6), 3));
            const line = new THREE.Line(geo, mat);
            line.frustumCulled = false;
            line.visible = false;
            this.scene.add(line);
            this._tracers.push({ line, from: new THREE.Vector3(), to: new THREE.Vector3(), t: 0, dur: 0.01 });
        }
        /* 火光片：加法混合四边形，始终面向相机的近似（两片十字） */
        const flashMat = new THREE.MeshBasicMaterial({
            color: 0xFFC873, transparent: true, opacity: 0.95,
            blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
        });
        this._flash = new THREE.Group();
        this._flashMat = flashMat;
        const p1 = new THREE.Mesh(new THREE.PlaneGeometry(0.42, 0.42), flashMat);
        const p2 = p1.clone();
        p2.rotation.y = Math.PI / 2;
        this._flash.add(p1, p2);
        this._flash.visible = false;
        this.scene.add(this._flash);
        this._flashLight = new THREE.PointLight(0xFFB46B, 0, 7, 2);
        this._flashLight.castShadow = false;
        this.scene.add(this._flashLight);
    }

    _spawnTracer(from, to) {
        if (!this._tracers.length) return;
        const s = this._tracers[this._tracerI];
        this._tracerI = (this._tracerI + 1) % this._tracers.length;
        s.from.copy(from);
        s.to.copy(to);
        const d = s.from.distanceTo(s.to);
        s.dur = Math.max(d / TRACER_SPEED, 0.02);
        s.t = 0;
        s.line.visible = true;
    }

    _muzzleFlash(pos) {
        if (!this._flash) return;
        this._flash.position.copy(pos);
        this._flash.rotation.z = Math.random() * Math.PI;
        this._flash.visible = true;
        this._flashLight.position.copy(pos);
        this._flashLight.intensity = 10;
        this._flashT = 0.06;
    }

    /* ==== 4. 巡逻部署（分区契约）：routes 元素 {pts, cls:'wild'|'elite', count[, variant|mix]}
     * 兼容旧纯数组路线（=荒野散兵单人线）；空数组 = 清空全部（靶场模式）。
     * 重复调用即全量重置。实体带 e.stats（含 viewDist），_step/_canSee/_tryFire 按表取数 ==== */
    spawnPatrol(routes) {
        for (const e of this.enemies) {
            if (e.node && e.node.parent) e.node.parent.remove(e.node);
        }
        this.enemies.length = 0;
        this.alertMul = 1.0;
        this._sndBudget = SND_BUDGET_MAX;
        const list = this._normalizeRoutes(routes);
        if (list.length) this._deployRoutes = list;   // 记录最近一次非空部署
        for (let i = 0; i < list.length; i++) {
            const plan = list[i];
            const route = plan.pts;
            const start = route[0];
            const cs = CALLSIGNS[i % CALLSIGNS.length]
                + (i >= CALLSIGNS.length * 2 ? 'Ⅲ' : i >= CALLSIGNS.length ? 'Ⅱ' : '');
            const e = {
                i, name: plan.label + '·' + cs,
                node: null, mixer: null, actions: {}, capsule: null, anim: '',
                route: route.slice(), wp: Math.min(1, route.length - 1),
                pos: new THREE.Vector3().copy(start),
                yaw: 0, stats: plan.stats, hp: plan.stats.hp, state: 'patrol',
                fireCd: Math.random() * 0.5, mag: MAG_SIZE, reloadT: 0, burstLeft: 0,
                staggerT: 0, losT: 0, losOk: false, lostT: 0, suspT: 0, searchT: 0,
                searchGoal: new THREE.Vector3().copy(start), searchPickT: 0,
                strafeT: 0, strafeDir: Math.random() < 0.5 ? 1 : -1,
                detourT: 0, detourX: 0, detourZ: 0, blockT: 0, curSpeed: 0,
                lastKnown: new THREE.Vector3(), visible: false, engaged: false,
                moving: false, deathT: 0, fadeMats: [], caps: null, capsT: Math.random() * 10,
                spotted: false,
            };
            /* 初始朝向路线下一 waypoint */
            const nx = route[e.wp];
            if (nx) e.yaw = Math.atan2(nx.x - e.pos.x, nx.z - e.pos.z);
            this.enemies.push(e);
            this._attachModel(e);
        }
    }

    /* 部署计划规整：输出逐兵种展开表 [{pts,label,stats}]；
     * 旧纯数组 = wild 单人线；对象缺 count 视为 1；未知兵种回落默认档 */
    _normalizeRoutes(routes) {
        const out = [];
        if (!Array.isArray(routes)) return out;
        for (const r of routes) {
            if (Array.isArray(r)) {
                if (r.length > 0) out.push({ pts: r.slice(), stats: WILD.rifleman, label: '散兵' });
                continue;
            }
            if (!r || !Array.isArray(r.pts) || r.pts.length === 0) continue;
            const elite = r.cls === 'elite';
            const table = elite ? ELITE : WILD;
            const fallback = elite ? 'assault' : 'rifleman';
            const jobs = (elite && Array.isArray(r.mix) && r.mix.length)
                ? r.mix
                : [[(table[r.variant] ? r.variant : fallback), Math.max(1, (r.count | 0) || 1)]];
            for (const mv of jobs) {
                const vName = table[mv[0]] ? mv[0] : fallback;
                const n = Math.max(1, Math.min(6, (mv[1] | 0) || 1));
                for (let k = 0; k < n; k++) {
                    out.push({
                        pts: r.pts.slice(),
                        stats: table[vName],
                        label: elite ? (ELITE_LABEL[vName] || '精锐') : '散兵',
                    });
                }
            }
        }
        return out;
    }

    /* 重开行动复活：按最近一次非空部署原样重铺
     *（靶场 spawnPatrol([]) 清场后再重开任务，也能正确复活满编） */
    resetAll() {
        this.spawnPatrol(this._deployRoutes);
    }

    /* INTEL 完成：全员警戒 search + 移速 ×1.2（missionSpec；Mission 组调用） */
    alertAll(atPos) {
        this.alertMul = 1.2;
        const p = atPos || (this._hasPlayerEye ? this._playerEye : null);
        for (const e of this.enemies) {
            if (e.state === 'dead') continue;
            e.state = 'search';
            e.searchT = SEARCH_TIME;
            if (p) e.lastKnown.copy(p);
            this._pickSearchGoal(e);
        }
    }

    /* main 装配后注入玩家（takeDamage/pos/dead 鸭子类型） */
    setPlayer(player) { this.player = player; }

    /* ==== 5. 模型：每敌独立 GLB，失败降级胶囊人 ==== */
    _getLoader() {
        if (!this._loader) this._loader = new GLTFLoader();
        return this._loader;
    }

    _attachModel(e) {
        this._getLoader().load(
            SOLDIER_URL,
            (gltf) => this._onModelOk(e, gltf),
            undefined,
            () => this._onModelFail(e),
        );
    }

    _onModelOk(e, gltf) {
        if (!this.scene || this.enemies.indexOf(e) < 0 || e.node) return;
        const root = gltf.scene;
        root.scale.setScalar(SOLDIER_SCALE);
        root.position.copy(e.pos);
        root.rotation.y = e.yaw;
        const mats = [];
        root.traverse((o) => {
            if (o.isMesh) {
                o.castShadow = true;
                o.frustumCulled = false;
                const ms = Array.isArray(o.material) ? o.material : [o.material];
                for (const m of ms) {
                    if (!m) continue;
                    /* 敌军配色：sRGB 指定军橄榄调乘子（评审 #3——旧 setRGB 线性值
                     * 0.7/0.5/0.4 等效亮米色，把 256px 迷彩洗白），另叠织物法线出布纹 */
                    if (m.name === 'Uniform') {
                        m.color.setRGB(0.55, 0.47, 0.38, THREE.SRGBColorSpace);
                        m.normalMap = fabricNormal();
                        m.normalScale = new THREE.Vector2(0.45, 0.45);
                        m.needsUpdate = true;
                    } else if (m.name === 'Gear') {
                        m.color.setRGB(0.42, 0.38, 0.31, THREE.SRGBColorSpace);
                        m.normalMap = fabricNormal();
                        m.normalScale = new THREE.Vector2(0.35, 0.35);
                        m.needsUpdate = true;
                    }
                    mats.push(m);
                }
            }
        });
        this.scene.add(root);
        e.node = root;
        e.fadeMats = mats;
        e.mixer = new THREE.AnimationMixer(root);
        /* clip 名带 _loop 后缀：按后缀匹配优先精确名（interfaces 风险项） */
        const find = (base) => (gltf.animations || []).find(a => a.name === base)
            || (gltf.animations || []).find(a => a.name === base + '_loop')
            || (gltf.animations || []).find(a => a.name.indexOf(base) === 0) || null;
        for (const base of ['idle', 'aim', 'walk', 'run', 'death']) {
            const clip = find(base);
            if (clip) e.actions[base] = e.mixer.clipAction(clip);
        }
        e.anim = '';
        /* 加载完成前已阵亡：直接摆死亡姿势 */
        if (e.state === 'dead') this._startDeathAnim(e);
    }

    _onModelFail(e) {
        if (!this.scene || this.enemies.indexOf(e) < 0) return;
        /* 胶囊人替身（battlefield.gd:1217-1224）+ 程序化摆动 */
        const g = new THREE.Group();
        const uni = new THREE.MeshStandardMaterial({ color: 0x9a6f60, roughness: 0.9 });
        const dark = new THREE.MeshStandardMaterial({ color: 0x574437, roughness: 0.9 });
        const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.28, 1.2, 4, 10), uni);
        body.position.y = 0.875;
        const head = new THREE.Mesh(new THREE.SphereGeometry(0.16, 10, 8), dark);
        head.position.y = 1.62;
        const legGeo = new THREE.BoxGeometry(0.16, 0.75, 0.18);
        const legL = new THREE.Mesh(legGeo, dark); legL.position.set(0.12, 0.38, 0);
        const legR = new THREE.Mesh(legGeo, dark); legR.position.set(-0.12, 0.38, 0);
        const armGeo = new THREE.BoxGeometry(0.12, 0.6, 0.14);
        const armL = new THREE.Mesh(armGeo, uni); armL.position.set(0.36, 1.1, 0.1);
        const armR = new THREE.Mesh(armGeo, uni); armR.position.set(-0.36, 1.1, 0.1);
        const gun = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.1, 0.7), dark);
        gun.position.set(0.16, 1.15, 0.42);
        g.add(body, head, legL, legR, armL, armR, gun);
        g.traverse(o => { if (o.isMesh) o.castShadow = true; });
        g.position.copy(e.pos);
        g.rotation.y = e.yaw;
        this.scene.add(g);
        e.node = g;
        e.capsule = { body, head, legL, legR, armL, armR, gun };
        e.fadeMats = [uni, dark];
        e.anim = '';
    }

    /* ==== 6. 命中球射线（玩家枪共用判定入口，battlefield.gd:818-833） ==== */
    raycast(from, dir, maxD) {
        let best = null;
        for (const e of this.enemies) {
            if (e.state === 'dead') continue;
            /* 头：y=1.65×S r=0.2×S */
            _v1.set(e.pos.x, e.pos.y + 1.65 * SOLDIER_SCALE, e.pos.z).sub(from);
            const th = _v1.dot(dir);
            if (th > 0.5 && th < maxD && (!best || th < best.dist)) {
                _v2.copy(dir).multiplyScalar(th);
                if (_v1.sub(_v2).length() < 0.2 * SOLDIER_SCALE) {
                    best = { type: 'enemy_head', index: e.i, point: null, dist: th, _p: this };
                    continue;
                }
            }
            /* 胸：y=1.05×S r=0.5×S */
            _v1.set(e.pos.x, e.pos.y + 1.05 * SOLDIER_SCALE, e.pos.z).sub(from);
            const tc = _v1.dot(dir);
            if (tc > 0.5 && tc < maxD && (!best || tc < best.dist)) {
                _v2.copy(dir).multiplyScalar(tc);
                if (_v1.sub(_v2).length() < 0.5 * SOLDIER_SCALE) {
                    best = { type: 'enemy', index: e.i, point: null, dist: tc, _p: this };
                }
            }
        }
        if (best) best.point = new THREE.Vector3().copy(dir).multiplyScalar(best.dist).add(from);
        return best;
    }

    /* damage(index, dmg, head)：爆头倍率在此内生效（battlefield.gd:811 同层） */
    damage(index, dmg, head) {
        const e = this.enemies[index];
        if (!e || e.state === 'dead') return { killed: false, head: !!head };
        e.hp -= dmg * (head ? HEAD_MUL : 1);
        if (e.hp > 0) {
            /* 受击硬直 + 立即向玩家方位警戒 */
            e.staggerT = 0.25;
            const see = this._hasPlayerEye && this._canSee(e, this._playerEye);
            if (this._hasPlayerEye) e.lastKnown.copy(this._playerEye);
            if (e.state !== 'combat') {
                e.state = see ? 'combat' : 'search';
                if (e.state === 'combat') this._fireSpotted(e);
                e.searchT = SEARCH_TIME;
                if (e.state === 'search') this._pickSearchGoal(e);
            }
            return { killed: false, head: !!head };
        }
        /* 死亡：倒地淡出 + 击杀播报 */
        e.state = 'dead';
        e.moving = false;
        e.engaged = false;
        e.deathT = 0;
        this._startDeathAnim(e);
        let dist = 0;
        if (this._hasPlayerEye) {
            dist = Math.hypot(this._playerEye.x - e.pos.x, this._playerEye.z - e.pos.z);
        }
        if (typeof this.onKill === 'function') this.onKill(e.name, dist, !!head);
        return { killed: true, head: !!head };
    }

    /* ==== 7. 每帧：1/60 定步 AI + 渲染姿势/动画/特效 ==== */
    update(dt, playerEye) {
        if (playerEye) {
            this._playerEye.copy(playerEye);
            this._hasPlayerEye = true;
        }
        const playerAlive = this.player ? !this.player.dead : true;

        this._acc += dt;
        let steps = 0;
        while (this._acc >= AI_TICK && steps < MAX_STEPS) {
            this._acc -= AI_TICK;
            steps++;
            for (const e of this.enemies) this._step(e, AI_TICK, playerAlive);
        }
        if (this._acc > AI_TICK * MAX_STEPS) this._acc = 0;   // 低帧防雪崩

        /* 声音预算回填（battlefield.gd:300） */
        this._sndBudget = Math.min(this._sndBudget + dt * SND_BUDGET_REFILL, SND_BUDGET_MAX);

        this._renderPoses(dt);
        this._tickFx(dt);
    }

    /* ==== 8. 单个敌兵 AI 定步 ==== */
    _step(e, dt, playerAlive) {
        if (e.state === 'dead') return;
        if (e.staggerT > 0) { e.staggerT -= dt; return; }   // 受击硬直：原地僵直

        const canSee = playerAlive && this._hasPlayerEye && this._canSee(e, this._playerEye);
        e.visible = canSee;
        if (canSee) e.lastKnown.copy(this._playerEye);

        switch (e.state) {
            case 'patrol': {
                if (canSee) { this._toSuspicious(e); break; }
                this._patrolMove(e, dt);
                break;
            }
            case 'suspicious': {
                e.suspT -= dt;
                if (canSee && e.suspT <= 0) { this._toCombat(e); break; }
                if (!canSee && e.suspT <= 0) { this._toSearch(e); break; }
                /* 面向可疑点缓步逼近 */
                this._moveToward(e, e.lastKnown, e.stats.speed * 0.35 * this.alertMul, dt, e.lastKnown);
                break;
            }
            case 'combat': {
                if (!playerAlive) { this._toSearch(e); break; }
                e.losT -= dt;
                if (e.losT <= 0) {
                    e.losT = LOS_RECHECK;
                    e.losOk = this._hasPlayerEye
                        ? this._los(e.pos.x, e.pos.y + EYE_H, e.pos.z, this._playerEye) : false;
                }
                if (canSee) { e.losOk = true; e.lostT = 0; } else { e.lostT += dt; }
                const dist = this._hasPlayerEye
                    ? Math.hypot(this._playerEye.x - e.pos.x, this._playerEye.z - e.pos.z) : Infinity;
                e.engaged = e.losOk && dist < e.stats.range;
                if (e.engaged) this._combatMove(e, dt, dist);
                else this._moveToward(e, e.lastKnown, e.stats.speed * ENGAGE_SPEED_MUL * this.alertMul, dt, e.lastKnown);
                if (e.engaged) this._tryFire(e, dt, dist);
                if (e.lostT > LOSE_TIME) this._toSearch(e);
                break;
            }
            case 'search': {
                if (canSee) { this._toCombat(e); break; }
                e.searchT -= dt;
                e.searchPickT -= dt;
                if (e.searchPickT <= 0) this._pickSearchGoal(e);
                this._moveToward(e, e.searchGoal, e.stats.speed * SEARCH_SPEED_MUL * this.alertMul, dt, e.searchGoal);
                if (e.searchT <= 0) { this._toPatrol(e); break; }
                break;
            }
        }
    }

    _toSuspicious(e) {
        e.state = 'suspicious';
        e.suspT = REACT_TIME;
        e.engaged = false;
    }
    _toCombat(e) {
        if (e.state !== 'combat') this._fireSpotted(e);
        e.state = 'combat';
        e.losT = 0;
        e.losOk = true;
        e.lostT = 0;
    }
    _fireSpotted(e) {
        if (e.spotted) return;
        e.spotted = true;
        if (typeof this.onPlayerSpotted === 'function') this.onPlayerSpotted();
    }
    _toSearch(e) {
        e.state = 'search';
        e.searchT = SEARCH_TIME;
        e.engaged = false;
        this._pickSearchGoal(e);
    }
    _toPatrol(e) {
        e.state = 'patrol';
        e.engaged = false;
        e.spotted = false;   // 下次再被发现可再触发提示
        /* 回最近 waypoint */
        let bi = 0, bd = Infinity;
        for (let k = 0; k < e.route.length; k++) {
            const d = e.pos.distanceToSquared(e.route[k]);
            if (d < bd) { bd = d; bi = k; }
        }
        e.wp = bi;
    }
    _pickSearchGoal(e) {
        e.searchPickT = 3 + Math.random() * 2;
        const a = Math.random() * Math.PI * 2;
        const r = 1.5 + Math.random() * 4.5;
        e.searchGoal.set(e.lastKnown.x + Math.sin(a) * r, 0, e.lastKnown.z + Math.cos(a) * r);
    }

    /* 死亡动画启动（GLB 到位前后两个时机共用） */
    _startDeathAnim(e) {
        if (e.mixer && e.actions.death) {
            const a = e.actions.death;
            a.reset().setLoop(THREE.LoopOnce, 1);
            a.clampWhenFinished = true;
            for (const k in e.actions) if (k !== 'death') e.actions[k].stop();
            a.play();
            e.anim = 'death';
        }
    }

    _patrolMove(e, dt) {
        const wp = e.route[e.wp];
        if (!wp) return;
        const arrive = this._moveToward(e, wp, e.stats.speed * PATROL_SPEED_MUL * this.alertMul, dt, wp);
        if (arrive) e.wp = (e.wp + 1) % e.route.length;
    }

    /* 交火走位（battlefield.gd:398-408）：近距侧移 / 远距缓进 */
    _combatMove(e, dt, dist) {
        const tx = this._playerEye.x - e.pos.x;
        const tz = this._playerEye.z - e.pos.z;
        const d = Math.max(dist, 0.01);
        const fx = tx / d, fz = tz / d;
        let mx = 0, mz = 0;
        if (dist < 22) {
            e.strafeT -= dt;
            if (e.strafeT <= 0) {
                e.strafeT = 1.5 + Math.random() * 2.0;
                e.strafeDir = -e.strafeDir;
            }
            mx = -fz * e.strafeDir;
            mz = fx * e.strafeDir;
        } else if (dist > 26) {
            mx = fx * 0.55;
            mz = fz * 0.55;
        }
        this._applyMove(e, mx, mz, fx, fz, e.stats.speed * ENGAGE_SPEED_MUL * this.alertMul, dt);
    }

    /* 通用走位：到点返回 true */
    _moveToward(e, target, speed, dt, faceAt) {
        const dx = target.x - e.pos.x, dz = target.z - e.pos.z;
        const d = Math.hypot(dx, dz);
        if (d < 1.2) { e.moving = false; return true; }
        const fx = faceAt ? (faceAt.x - e.pos.x) : dx;
        const fz = faceAt ? (faceAt.z - e.pos.z) : dz;
        this._applyMove(e, dx / d, dz / d, fx, fz, speed, dt);
        return false;
    }

    /* 移动执行：同队推挤 + 卡墙绕行 + OBB 推出 + 贴地（battlefield.gd:550-587） */
    _applyMove(e, mx, mz, fx, fz, speed, dt) {
        let vx = mx * speed, vz = mz * speed;
        for (const o of this.enemies) {
            if (o === e || o.state === 'dead') continue;
            const ddx = e.pos.x - o.pos.x, ddz = e.pos.z - o.pos.z;
            const d = Math.hypot(ddx, ddz);
            if (d > 0.01 && d < SEP_DIST) {
                vx += (ddx / d) * (SEP_DIST - d) * SEP_PUSH;
                vz += (ddz / d) * (SEP_DIST - d) * SEP_PUSH;
            }
        }
        if (e.detourT > 0) {
            e.detourT -= dt;
            const dl = Math.hypot(e.detourX, e.detourZ) || 1;
            vx = (e.detourX / dl) * speed;
            vz = (e.detourZ / dl) * speed;
        }
        const wantStep = Math.hypot(vx, vz) * dt;
        let nx = e.pos.x + vx * dt, nz = e.pos.z + vz * dt;
        if (this.collision) {
            const p = this.collision.pushOut(nx, nz, ENEMY_R);
            if (p) { nx = p.x; nz = p.z; }
        }        /* 卡墙判定：想走却只走出不到 30%，累计 0.4s 开始绕（battlefield.gd:571-581） */
        const moved = Math.hypot(nx - e.pos.x, nz - e.pos.z);
        if (wantStep > 0.02 && moved < wantStep * 0.3) {
            e.blockT += dt;
            if (e.blockT > 0.4 && e.detourT <= 0) {
                e.blockT = 0;
                const side = Math.random() < 0.5 ? 1 : -1;
                const ml = Math.hypot(mx, mz);
                if (ml > 0.01) {
                    e.detourX = (-mz / ml) * side;
                    e.detourZ = (mx / ml) * side;
                } else {
                    e.detourX = side; e.detourZ = 0;
                }
                e.detourT = 0.8 + Math.random() * 0.8;
            }
        } else {
            e.blockT = Math.max(0, e.blockT - dt);
        }
        e.pos.x = nx;
        e.pos.z = nz;
        e.pos.y = this.collision ? (this.collision.groundHeight(nx, nz) || 0) : 0;
        e.moving = wantStep > 0.02;
        e.curSpeed = e.moving ? speed : 0;
        const fl = Math.hypot(fx, fz);
        if (fl > 0.0001) {
            const want = Math.atan2(fx / fl, fz / fl);   // 模型面朝 +Z（make_soldier.py:14）
            let dy = want - e.yaw;
            while (dy > Math.PI) dy -= Math.PI * 2;
            while (dy < -Math.PI) dy += Math.PI * 2;
            e.yaw += dy * (1 - Math.exp(-10 * dt));      // battlefield.gd:586
        }
    }

    /* ==== 9. 索敌：分区视距 + 视锥 + LOS（FOV110°；视距查 e.stats.viewDist：
     * 荒野散兵 50m / 中心精英 60m，字段缺失回落 VIEW_DIST 常量） ==== */
    _canSee(e, eye) {
        const dx = eye.x - e.pos.x, dz = eye.z - e.pos.z;
        const dist = Math.hypot(dx, dz);
        const viewDist = (e.stats && e.stats.viewDist) || VIEW_DIST;
        if (dist > viewDist) return false;
        if (dist > NEAR_SENSE) {
            const fx = Math.sin(e.yaw), fz = Math.cos(e.yaw);   // 面朝 +Z 基
            const cosA = (dx * fx + dz * fz) / dist;
            if (cosA < Math.cos(FOV_HALF)) return false;
        }
        return this._los(e.pos.x, e.pos.y + EYE_H, e.pos.z, eye);
    }

    _los(fx, fy, fz, to) {
        const dx = to.x - fx, dy = to.y - fy, dz = to.z - fz;
        const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (d < 0.5) return true;
        if (!this.collision || typeof this.collision.rayWall !== 'function') return true;
        const wd = this.collision.rayWall(_v1.set(fx, fy, fz), _v2.set(dx / d, dy / d, dz / d), d - 0.5);
        return !(wd < d - 0.5);   // Infinity 或贴脸都算通视
    }

    /* ==== 10. 开火：点射 + 精度随距离衰减（battlefield.gd:591-621） ==== */
    _tryFire(e, dt, dist) {
        e.fireCd -= dt;
        if (e.reloadT > 0) { e.reloadT -= dt; return; }
        if (e.fireCd > 0) return;
        if (e.mag <= 0) {
            e.reloadT = RELOAD_T;
            e.mag = MAG_SIZE;
            return;
        }
        if (e.burstLeft <= 0) e.burstLeft = e.stats.burst;
        e.burstLeft--;
        e.mag--;
        e.fireCd = e.burstLeft > 0 ? e.stats.cd : (PAUSE_MIN + Math.random() * (PAUSE_MAX - PAUSE_MIN));

        /* 弹道：目标方向 + 几何 jitter（acc × (1 + dist/60)，battlefield.gd:613-614） */
        const ex = e.pos.x, ey = e.pos.y + EYE_H, ez = e.pos.z;
        _v1.set(this._playerEye.x - ex, this._playerEye.y - ey, this._playerEye.z - ez).normalize();
        const acc = e.stats.acc * (1 + dist / 60);
        _v1.x += (Math.random() - 0.5) * acc;
        _v1.y += (Math.random() - 0.5) * 0.5 * acc;
        _v1.z += (Math.random() - 0.5) * acc;
        _v1.normalize();

        /* 枪口世界坐标（battlefield.gd:48/615） */
        const cy = Math.cos(e.yaw), sy = Math.sin(e.yaw);
        const muzzle = _v2.set(
            e.pos.x + MUZZLE_LOCAL.x * cy + MUZZLE_LOCAL.z * sy,
            e.pos.y + MUZZLE_LOCAL.y,
            e.pos.z - MUZZLE_LOCAL.x * sy + MUZZLE_LOCAL.z * cy,
        );

        /* 命中判定：几何 jitter 射线打玩家胶囊（r0.45 h1.7） */
        const pFoot = this.player ? this.player.pos : null;
        let hitPlayer = false, endD = e.stats.range;
        if (pFoot) {
            const midY = pFoot.y + PLAYER_CAP_H * 0.5;
            _v3.set(pFoot.x - ex, midY - ey, pFoot.z - ez);
            const t = _v3.dot(_v1);
            if (t > 0.5 && t < e.stats.range) {
                const px = ex + _v1.x * t, py = ey + _v1.y * t, pz = ez + _v1.z * t;
                if (distToVertSegment({ x: px, y: py, z: pz }, pFoot.x, pFoot.z,
                        pFoot.y + 0.1, pFoot.y + PLAYER_CAP_H - 0.1) < PLAYER_CAP_R) {
                    /* 墙体遮挡优先 */
                    let blocked = false;
                    if (this.collision && typeof this.collision.rayWall === 'function') {
                        const wd = this.collision.rayWall(
                            _v3.set(ex, ey, ez), _v1, t - 0.2);
                        blocked = wd < t - 0.2;
                    }
                    if (!blocked) {
                        hitPlayer = true;
                        endD = t;
                    }
                }
            }
        }

        /* 曳光终点：命中点 / 打到墙 / 沿射线射程处 */
        if (!hitPlayer && this.collision && typeof this.collision.rayWall === 'function') {
            const wd = this.collision.rayWall(_v3.set(ex, ey, ez), _v1, e.stats.range);
            if (wd < e.stats.range) endD = wd;
        }
        const end = _v3.set(ex + _v1.x * endD, ey + _v1.y * endD, ez + _v1.z * endD);
        if (Math.random() < TRACER_RATIO) this._spawnTracer(muzzle, end);   // 约 1/3 出曳光
        this._muzzleFlash(muzzle);
        if (typeof this.onEnemyFire === 'function') {
            this.onEnemyFire(muzzle.clone(), end.clone());
        }
        if (hitPlayer) {
            const dmg = e.stats.dmgMin + Math.random() * (e.stats.dmgMax - e.stats.dmgMin);
            if (typeof this.onPlayerHit === 'function') {
                this.onPlayerHit(dmg, muzzle.clone());
            } else if (this.player && typeof this.player.takeDamage === 'function') {
                this.player.takeDamage(dmg, muzzle.clone());
            }
        }
        /* 远处枪声（距离衰减，预算限流） */
        if (this.audio && typeof this.audio.enemyShot === 'function' && this._sndBudget >= 1) {
            this._sndBudget -= 1;
            const pd = this._hasPlayerEye
                ? Math.hypot(this._playerEye.x - ex, this._playerEye.z - ez) : 0;
            this.audio.enemyShot(pd);
        }
    }

    /* ==== 11. 渲染姿势：模型同步 + 动画切换 + 死亡淡出 + 胶囊摆动 ==== */
    _renderPoses(dt) {
        for (const e of this.enemies) {
            if (!e.node) continue;
            e.node.position.copy(e.pos);
            e.node.rotation.y = e.yaw;

            if (e.state === 'dead') {
                e.deathT += dt;
                if (e.capsule) this._capsuleDeath(e, dt);
                if (e.deathT > DEATH_HOLD) {
                    const k = Math.min((e.deathT - DEATH_HOLD) / DEATH_FADE, 1);
                    for (const m of e.fadeMats) { m.transparent = true; m.opacity = 1 - k; }
                    if (k >= 1) e.node.visible = false;
                }
                if (e.mixer) e.mixer.update(dt);
                continue;
            }

            /* 动画选择（battlefield.gd:1284-1290） */
            let want = 'idle';
            const spd = e.curSpeed;
            if (e.moving) want = e.engaged ? 'walk' : 'run';
            else if (e.engaged) want = 'aim';
            if (e.mixer) {
                if (want !== e.anim) {
                    const next = e.actions[want];
                    if (next) {
                        const prev = e.actions[e.anim];
                        next.reset().fadeIn(0.18).play();
                        if (prev && prev !== next) prev.fadeOut(0.18);
                        e.anim = want;
                    }
                }
                if (e.actions.run && e.anim === 'run') {
                    e.actions.run.setEffectiveTimeScale(spd / 6.5);   // battlefield.gd:1298
                } else if (e.actions.walk && e.anim === 'walk') {
                    e.actions.walk.setEffectiveTimeScale(Math.max(spd, 0.5) / 1.5);
                }
                e.mixer.update(dt);
            } else if (e.capsule) {
                this._animateCapsule(e, dt, spd);
            }
        }
    }

    /* 胶囊替身：程序化待机呼吸/跑动摆腿（加载失败降级用） */
    _animateCapsule(e, dt, speed) {
        const c = e.capsule;
        const moving = speed > 0.3;
        e.capsT += dt * (moving ? Math.max(speed * 1.4, 4) : 1.4);
        const ph = e.capsT;
        const k = moving ? 1 : 0;
        c.legL.rotation.x = Math.sin(ph) * 0.75 * k;
        c.legR.rotation.x = -Math.sin(ph) * 0.75 * k;
        c.armL.rotation.x = -Math.sin(ph) * 0.55 * k;
        c.armR.rotation.x = Math.sin(ph) * 0.35 * k;
        c.body.position.y = 0.875 + Math.abs(Math.sin(ph)) * 0.035 * k;
        c.body.rotation.z = moving ? Math.sin(ph * 0.5) * 0.03 : Math.sin(ph) * 0.02;
        c.head.rotation.y = moving ? 0 : Math.sin(ph * 0.4) * 0.25;
        c.gun.rotation.x = e.engaged ? -0.12 : -0.55;
        c.gun.position.set(e.engaged ? 0.05 : 0.16, e.engaged ? 1.35 : 1.15,
            e.engaged ? 0.55 : 0.42);
    }

    _capsuleDeath(e, dt) {
        const c = e.capsule;
        if (!c) return;
        const k = Math.min(e.deathT / 0.45, 1);
        e.node.rotation.x = -Math.PI / 2 * k;   // 后仰倒地（battlefield.gd:1293）
        e.node.position.y = e.pos.y + 0.15 * k;
        c.legL.rotation.x = 0.3 * k;
        c.legR.rotation.x = -0.2 * k;
        c.armL.rotation.x = -0.9 * k;
        c.armR.rotation.x = 0.4 * k;
    }

    /* ==== 12. 特效步进：曳光飞行 / 火光衰减 ==== */
    _tickFx(dt) {
        for (const s of this._tracers) {
            if (!s.line.visible) continue;
            s.t += dt;
            const total = s.from.distanceTo(s.to) || 1;
            const head = Math.min(s.t / s.dur, 1);
            const tail = Math.max(Math.min(head - TRACER_LEN / total, head), 0);
            const pos = s.line.geometry.attributes.position;
            pos.setXYZ(0,
                s.from.x + (s.to.x - s.from.x) * tail,
                s.from.y + (s.to.y - s.from.y) * tail,
                s.from.z + (s.to.z - s.from.z) * tail);
            pos.setXYZ(1,
                s.from.x + (s.to.x - s.from.x) * head,
                s.from.y + (s.to.y - s.from.y) * head,
                s.from.z + (s.to.z - s.from.z) * head);
            pos.needsUpdate = true;
            if (head >= 1) s.line.visible = false;
        }
        if (this._flashT > 0) {
            this._flashT -= dt;
            const k = Math.max(this._flashT / 0.06, 0);
            if (this._flashMat) this._flashMat.opacity = k * 0.95;
            if (this._flashLight) this._flashLight.intensity = k * 10;
            if (this._flashT <= 0) {
                if (this._flash) this._flash.visible = false;
                if (this._flashLight) this._flashLight.intensity = 0;
            }
        }
    }

    /* ==== 13. 清理 ==== */
    dispose() {
        for (const e of this.enemies) {
            if (e.node && e.node.parent) e.node.parent.remove(e.node);
        }
        this.enemies.length = 0;
        for (const s of this._tracers) {
            if (s.line.parent) s.line.parent.remove(s.line);
            s.line.geometry.dispose();
        }
        if (this._flash && this._flash.parent) this._flash.parent.remove(this._flash);
        if (this._flashLight && this._flashLight.parent) this._flashLight.parent.remove(this._flashLight);
    }
}
