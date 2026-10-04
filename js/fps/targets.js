/* =====================================================================
   js/fps/targets.js —— 靶场（【玩家AI】组）
   场地（missionSpec 靶场规格）：3 条射位 lanes；
     固定靶 8 = 10m×3 + 15m×3 + 25m×2 人形环靶（命中倒下 0.9s 自动立起）；
     摆动靶 4 = 15m、±30° 正弦摆动、周期 1.2/1.6/2.0/2.4s（倒下不自动复位）。
   计分：环 10/9=100、8/7=50、6 及以外=25；最佳分 localStorage fps_range_best。
   靶面：Canvas 程序化人形环靶（零外部资源，仓库约定）。
   ===================================================================== */
import * as THREE from 'three';

/* ==== 1. 常量 ==== */
const BOARD_W = 0.6;              // 靶板宽（面本地 X ±0.3）
const BOARD_H = 0.82;             // 靶板高（面本地 Y ±0.41）
const RING_CX = 0;                // 环心（面本地坐标，与贴图 cy=430/700 对应）
const RING_CY = -0.094;
const RING_STEP = 0.055;          // 每环半径步进（10 环 0.055 起）
const RING_MIN = 6, RING_MAX = 10;
const RING_SCORE = { 10: 100, 9: 100, 8: 50, 7: 50, 6: 25 };
const SWING_DEG = 30;            // 摆动靶 ±30°
const SWING_PERIODS = [1.2, 1.6, 2.0, 2.4];
const FALL_TIME = 0.22;          // 倒靶动画时长
const RISE_TIME = 0.25;          // 立起动画时长
const AUTO_RISE = 0.9;           // 固定靶倒下 0.9s 后自动立起
const BEST_KEY = 'fps_range_best';

const _m4 = new THREE.Matrix4();
const _vf = new THREE.Vector3();
const _vd = new THREE.Vector3();

/* ==== 2. 靶面贴图：Canvas 程序化人形环靶 ==== */
function makeFaceTexture() {
    const c = document.createElement('canvas');
    c.width = 512;
    c.height = 700;
    const g = c.getContext('2d');
    /* 底纸：做旧米黄 + 噪点 */
    g.fillStyle = '#d8c9a3';
    g.fillRect(0, 0, c.width, c.height);
    for (let i = 0; i < 900; i++) {
        g.fillStyle = 'rgba(90,70,40,' + (Math.random() * 0.06).toFixed(3) + ')';
        g.fillRect(Math.random() * c.width, Math.random() * c.height, 2, 2);
    }
    /* 人形剪影：头 + 肩 + 躯干 */
    const cx = c.width / 2;
    g.fillStyle = '#3a3f3a';
    g.beginPath();
    g.arc(cx, 120, 62, 0, Math.PI * 2);           // 头
    g.fill();
    g.beginPath();
    g.moveTo(cx - 205, 660);
    g.quadraticCurveTo(cx - 210, 235, cx - 60, 208);
    g.lineTo(cx + 60, 208);
    g.quadraticCurveTo(cx + 210, 235, cx + 205, 660);
    g.closePath();                                 // 躯干
    g.fill();
    /* 环靶：10..6 黑白相间（躯干环心为准） */
    const rings = [
        { r: 150, n: 6 }, { r: 125, n: 7 }, { r: 100, n: 8 },
        { r: 75, n: 9 }, { r: 50, n: 10 },
    ];
    const cy = 430;
    for (const rg of rings) {
        g.beginPath();
        g.arc(cx, cy, rg.r, 0, Math.PI * 2);
        g.fillStyle = rg.n % 2 === 0 ? '#f2ead6' : '#2c2c2c';
        g.fill();
        g.lineWidth = 3;
        g.strokeStyle = 'rgba(30,30,30,.8)';
        g.stroke();
    }
    /* 环数标注（10 环白底黑字，其余对比色） */
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.font = 'bold 30px monospace';
    for (const rg of rings) {
        g.fillStyle = rg.n % 2 === 0 ? '#2c2c2c' : '#f2ead6';
        g.fillText(String(rg.n), cx, cy - rg.r + 22);
    }
    /* 靶心红点 */
    g.beginPath();
    g.arc(cx, cy, 7, 0, Math.PI * 2);
    g.fillStyle = '#c23b2e';
    g.fill();
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 4;
    return tex;
}

/* 板本地坐标 → 环数（ring=10..6，板内环外按 6 计 25 分） */
function ringAt(lx, ly) {
    const r = Math.hypot(lx - RING_CX, ly - RING_CY);
    const ring = Math.max(RING_MIN, Math.min(RING_MAX, RING_MAX - Math.floor(r / RING_STEP)));
    return ring;
}

/* ==== 3. TargetRange ==== */
export class TargetRange {
    constructor({ scene, audio } = {}) {
        this.scene = scene;
        this.audio = audio || null;    // 可选：main 装配后 setAudio(gunAudio) 注入
        this.onHit = null;             // (index, ring) 回调（interfaces）
        this.damageStyle = 'hit';      // CombatWorld 分发签名：damage(index, dmg, hit)
        this.targets = [];
        this.score = 0;
        this.best = 0;
        try {
            this.best = parseInt(localStorage.getItem(BEST_KEY) || '0', 10) || 0;
        } catch (err) { /* 隐私模式无 localStorage */ }
        this._tex = makeFaceTexture();
        this._faceMat = new THREE.MeshStandardMaterial({ map: this._tex, roughness: 0.85 });
        this._woodMat = new THREE.MeshStandardMaterial({ color: 0x6b5a3e, roughness: 0.9 });
        this._postMat = new THREE.MeshStandardMaterial({ color: 0x4a4a44, roughness: 0.7, metalness: 0.3 });
        this._t = 0;
        this._lastRing = { index: -1, ring: 0 };
    }

    setAudio(audio) { this.audio = audio; }

    /* ==== 4. 铺场：3 条射位 → 固定 8 + 摆动 4 ==== */
    buildLanes(lanes) {
        /* 清旧 */
        for (const tg of this.targets) {
            if (tg.group.parent) tg.group.parent.remove(tg.group);
        }
        this.targets.length = 0;
        this.score = 0;
        this._t = 0;
        if (!this.scene || !Array.isArray(lanes) || lanes.length < 1) return;
        const L = (i) => lanes[Math.min(i, lanes.length - 1)];

        /* 每条射位：lane0=10m×3 固定；lane1=15m×3 固定 + 2 摆动；lane2=25m×2 固定 + 2 摆动 */
        const plan = [];
        for (const off of [-1.8, 0, 1.8]) plan.push({ lane: 0, d: 10, off, swing: 0 });
        for (const off of [-1.8, 0, 1.8]) plan.push({ lane: 1, d: 15, off, swing: 0 });
        for (const off of [-2.2, 2.2]) plan.push({ lane: 2, d: 25, off, swing: 0 });
        const swingPlan = [
            { lane: 1, off: -4.4 }, { lane: 1, off: 4.4 },
            { lane: 2, off: -4.4 }, { lane: 2, off: 4.4 },
        ];
        swingPlan.forEach((sp, k) => {
            plan.push({ lane: sp.lane, d: 15, off: sp.off, swing: SWING_PERIODS[k % SWING_PERIODS.length] });
        });

        plan.forEach((p, index) => {
            const lane = L(p.lane);
            const origin = lane.origin instanceof THREE.Vector3 ? lane.origin : new THREE.Vector3();
            const dir = lane.dir instanceof THREE.Vector3 ? lane.dir.clone().normalize() : new THREE.Vector3(0, 0, -1);
            const right = new THREE.Vector3(-dir.z, 0, dir.x);
            const pos = new THREE.Vector3()
                .copy(origin)
                .addScaledVector(dir, p.d)
                .addScaledVector(right, p.off);
            this.targets.push(this._makeTarget(index, pos, origin, p.swing));
        });
    }

    /* 单个靶：立柱 + 吊点 pivot + 靶板（摆动=绕板法线正弦；倒下=绕水平轴后仰） */
    _makeTarget(index, pos, faceAt, swingPeriod) {
        const group = new THREE.Group();
        group.position.copy(pos);
        group.lookAt(faceAt.x, group.position.y, faceAt.z);   // 板面朝射位
        const post = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.05, 1.05, 8), this._postMat);
        post.position.y = 0.52;
        post.castShadow = true;
        group.add(post);
        const pivot = new THREE.Group();
        pivot.position.y = 1.05;
        group.add(pivot);
        const board = new THREE.Group();
        pivot.add(board);
        const face = new THREE.Mesh(new THREE.PlaneGeometry(BOARD_W, BOARD_H), this._faceMat);
        face.position.y = -BOARD_H / 2;
        face.castShadow = true;
        board.add(face);
        const back = new THREE.Mesh(new THREE.PlaneGeometry(BOARD_W, BOARD_H), this._woodMat);
        back.position.y = -BOARD_H / 2;
        back.rotation.y = Math.PI;
        board.add(back);
        this.scene.add(group);
        return {
            index, group, pivot, board, face,
            swinger: !!swingPeriod, period: swingPeriod || 0,
            phase: Math.random() * Math.PI * 2,
            alive: true, downT: -1, riseT: -1, fallK: 0,
        };
    }

    /* ==== 5. 射线命中（CombatWorld 聚合调用；type='target'） ==== */
    raycast(from, dir, maxD) {
        let best = null;
        for (const tg of this.targets) {
            if (!tg.alive && tg.fallK > 0.15) continue;   // 倒下途中/倒地不判定
            /* 世界 → 靶板本地：板平面 z=0 求交 */
            tg.face.updateWorldMatrix(true, false);
            _m4.copy(tg.face.matrixWorld).invert();
            _vf.copy(from).applyMatrix4(_m4);
            _vd.copy(dir).transformDirection(_m4);
            if (Math.abs(_vd.z) < 1e-6) continue;
            const t = -_vf.z / _vd.z;
            if (t <= 0.1 || t >= maxD) continue;
            const lx = _vf.x + _vd.x * t;
            const ly = _vf.y + _vd.y * t;
            if (Math.abs(lx) > BOARD_W / 2 || Math.abs(ly) > BOARD_H / 2) continue;
            if (best && t >= best.dist) continue;
            best = {
                type: 'target', index: tg.index,
                point: new THREE.Vector3().copy(dir).multiplyScalar(t).add(from),
                dist: t, ring: ringAt(lx, ly), _p: this,
            };
        }
        return best;
    }

    /* damage(index, dmg, hit)：倒靶 + 环数计分；hit 为 raycast 返回（含 ring） */
    damage(index, dmg, hit) {
        const tg = this.targets[index];
        if (!tg || !tg.alive) return { killed: false, score: 0 };
        let ring = 0;
        if (hit && typeof hit.ring === 'number') ring = hit.ring;
        else if (this._lastRing.index === index) ring = this._lastRing.ring;
        else ring = RING_MIN;
        this._lastRing = { index, ring };

        tg.alive = false;
        tg.downT = 0;
        const gained = RING_SCORE[ring] || 25;
        this.score += gained;
        if (this.score > this.best) {
            this.best = this.score;
            try { localStorage.setItem(BEST_KEY, String(this.best)); } catch (err) { /* 忽略 */ }
        }
        /* 命中音「叮」+ 倒靶闷响（可选注入的 GunAudio 鸭子类型） */
        if (this.audio) {
            if (typeof this.audio.uiBeep === 'function') this.audio.uiBeep();
            if (typeof this.audio.dry === 'function') setTimeout(() => this.audio.dry(), 120);
        }
        if (typeof this.onHit === 'function') this.onHit(index, ring);
        return { killed: true, score: gained };
    }

    /* ==== 6. 步进：摆动正弦 + 倒/立动画 + 固定靶自动立起 ==== */
    update(dt) {
        this._t += dt;
        for (const tg of this.targets) {
            /* 摆动：绕板法线（本地 Z）正弦 ±30°，倒下即停 */
            if (tg.swinger && tg.alive) {
                tg.phase += dt;
                const a = THREE.MathUtils.degToRad(SWING_DEG);
                tg.board.rotation.z = a * Math.sin(tg.phase * Math.PI * 2 / tg.period);
            }
            if (!tg.alive) {
                if (tg.downT >= 0) {
                    tg.downT += dt;
                    tg.fallK = Math.min(tg.downT / FALL_TIME, 1);
                    tg.board.rotation.x = -Math.PI / 2 * tg.fallK;   // 后仰倒下
                    /* 固定靶 0.9s 后自动立起（missionSpec） */
                    if (!tg.swinger && tg.downT >= AUTO_RISE + FALL_TIME) {
                        tg.downT = -1;
                        tg.riseT = 0;
                    }
                } else if (tg.riseT >= 0) {
                    tg.riseT += dt;
                    const k = Math.min(tg.riseT / RISE_TIME, 1);
                    tg.board.rotation.x = -Math.PI / 2 * (1 - k);
                    if (k >= 1) {
                        tg.riseT = -1;
                        tg.alive = true;
                        tg.fallK = 0;
                        tg.board.rotation.x = 0;
                    }
                }
            }
        }
    }

    /* 重置全场（RangeMode 长按 R 触发）：全部立起、计分清零（保留最佳分） */
    reset() {
        this.score = 0;
        for (const tg of this.targets) {
            tg.alive = true;
            tg.downT = -1;
            tg.riseT = -1;
            tg.fallK = 0;
            tg.board.rotation.x = 0;
            tg.phase = Math.random() * Math.PI * 2;
        }
    }

    dispose() {
        for (const tg of this.targets) {
            if (tg.group.parent) tg.group.parent.remove(tg.group);
        }
        this.targets.length = 0;
        this._tex.dispose();
        this._faceMat.dispose();
        this._woodMat.dispose();
        this._postMat.dispose();
    }
}
