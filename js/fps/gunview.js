import * as THREE from 'three';
import { RIFLE, buildRifle } from './gun.js';
import { gunMaterials } from './gunTextures.js';

/* GunView：第一人称 viewmodel + 射击循环 + 后坐力 + 换弹状态机 + 世界空间特效池
 * 渲染约定：自建 vmScene + vmCamera(FOV 55，恒等位姿挂载)——viewmodel 只进
 * vmScene；main.js 每帧双 pass：render(scene,camera) → clearDepth →
 * render(vmScene,vmCamera)。vmCamera 在 vmScene 中保持原点位姿，因此枪在
 * vmScene 的「世界坐标」即相机空间坐标；世界特效（曳光/抛壳/掉落弹匣）经
 * 主相机 matrixWorld 换算后挂主场景。 */

/* ==== 1. 常量与缓动 ==== */

const DEG = Math.PI / 180;
const TRACER_COLOR = 0xFFCC59;          // guns.gd AMMO standard 弹色
const TRACER_SPEED = 420;               // 米/秒（tracer_pool.gd 同款）
const TRACER_LEN = 6;                   // 拖尾长度（米）
const Z_AXIS = new THREE.Vector3(0, 0, 1);
const Y_AXIS = new THREE.Vector3(0, 1, 0);

/* 腰射持枪位 / 机瞄对准目标点（相机空间） */
const HIP_POS = new THREE.Vector3(0.17, -0.15, -0.43);
const HIP_ROT = { x: 0.02, y: 0.085, z: 0.03 };
const ADS_TARGET = new THREE.Vector3(0, -0.006, -0.46);

/* 新弹匣入场：起点 ≈ 画面右下 (0.35,-0.45,-0.35)（相机空间）折算到枪本地（腰射位） */
const GRAB_OFF = new THREE.Vector3(0.18, -0.30, 0.08);

/* 换弹时间轴（reloadTimeline 规格；弹药生效/开火解锁挂绝对秒点） */
const TACTICAL_TL = {
    rollIn: 0.25, rollOut: 1.15, end: RIFLE.reloadTactical,
    slideStart: 0.10, magOutAt: 0.25,
    grabStart: 0.45, grabEnd: 0.95, seatEnd: 1.15, ammoAt: 1.15,
    fireUnlock: 1.30, rollDeg: 24, dropY: 0.06,
    boltStart: 0, boltEnd: 0, boltRelEnd: 0, boltBackSnd: 0, boltFwdSnd: 0
};
const EMPTY_TL = {
    rollIn: 0.30, rollOut: 1.55, end: RIFLE.reloadEmpty,
    slideStart: 0.15, magOutAt: 0.30,
    grabStart: 0.50, grabEnd: 1.05, seatEnd: 1.25, ammoAt: 1.25,
    fireUnlock: 1.80, rollDeg: 28, dropY: 0.08,
    boltStart: 1.25, boltEnd: 1.45, boltRelEnd: 1.55, boltBackSnd: 1.30, boltFwdSnd: 1.50
};

function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
function moveToward(v, t, d) { return v < t ? Math.min(v + d, t) : Math.max(v - d, t); }
function easeOutQuad(k) { return 1 - (1 - k) * (1 - k); }
function easeInQuad(k) { return k * k; }
function easeInOutQuad(k) { return k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2; }
function easeInOutCubic(k) { return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2; }

/* 枪口火光贴图：径向辉光 + 星芒（Canvas 程序化） */
function muzzleFlashTexture() {
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const g = c.getContext('2d');
    const rg = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    rg.addColorStop(0, 'rgba(255,255,240,1)');
    rg.addColorStop(0.25, 'rgba(255,214,130,0.9)');
    rg.addColorStop(0.55, 'rgba(255,150,50,0.35)');
    rg.addColorStop(1, 'rgba(255,120,30,0)');
    g.fillStyle = rg;
    g.fillRect(0, 0, 128, 128);
    g.strokeStyle = 'rgba(255,230,170,0.8)';
    g.lineWidth = 4;
    g.lineCap = 'round';
    for (let i = 0; i < 5; i++) {
        const a = i / 5 * Math.PI * 2 + 0.4;
        g.beginPath();
        g.moveTo(64, 64);
        g.lineTo(64 + Math.cos(a) * 60, 64 + Math.sin(a) * 60);
        g.stroke();
    }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
}

/* ==== 2. GunView ==== */

export class GunView {
    constructor({ scene, camera, audio = null, ground = null }) {
        this.scene = scene;
        this.camera = camera;
        this.audio = audio || null;
        this._groundFn = typeof ground === 'function' ? ground : null;

        /* ---- 公开状态（接口约定字段） ---- */
        this.recoilPitch = 0;           // rad，内部自衰减，Player 每帧读取合成相机
        this.recoilYaw = 0;
        this.adsAmount = 0;             // 0..1
        this.ammo = RIFLE.mag;
        this.reserve = 150;             // 5 个弹匣（接口未规定初值，可 resetAmmo 覆盖）
        this.reloading = false;
        this.reloadKind = null;         // 'tactical' | 'empty' | null
        this.reloadProgress = 0;        // 0..1（完成后保持 1）
        this.stats = { shots: 0, hits: 0 };
        /* 可选伤害分发钩子：main.js 注入 gunview.applyDamage=(hit,dmg)=>combat.applyHit(hit,dmg)
         * 不注入时命中只反馈音效/特效，不结算伤害。 */
        this.applyDamage = null;

        /* ---- viewmodel 双场景 ---- */
        this.vmScene = new THREE.Scene();
        this.vmCamera = new THREE.PerspectiveCamera(55, camera ? camera.aspect : 16 / 9, 0.01, 6);
        this.vmCamera.matrixAutoUpdate = true;      // 恒等位姿：vmScene 世界 == 相机空间
        this.vmScene.add(this.vmCamera);
        this.vmScene.add(new THREE.HemisphereLight(0xe8f0fb, 0x54493a, 1.0));
        const key = new THREE.DirectionalLight(0xfff2dc, 1.7);
        key.position.set(0.5, 1.0, 0.4);
        this.vmScene.add(key);
        const rim = new THREE.DirectionalLight(0xa8c4ff, 0.5);
        rim.position.set(-0.6, 0.3, -0.5);
        this.vmScene.add(rim);

        /* ---- 程序化步枪 + 持枪挂点 ---- */
        const built = buildRifle();
        this.gun = built.root;
        this.parts = built.parts;
        this.holder = new THREE.Group();
        this.vmCamera.add(this.holder);
        this.holder.add(this.gun);
        /* ADS 位 = 让机瞄线（root.userData.sight）贴到 ADS_TARGET（屏幕正中偏下） */
        const s = this.gun.userData.sight;
        this._adsPos = new THREE.Vector3(0, ADS_TARGET.y - s.y, ADS_TARGET.z - s.z);
        this._magHome = this.parts.mag.position.clone();
        this._boltHome = this.parts.bolt.position.clone();
        /* 换弹用「新弹匣」克隆（与机上弹匣同形；改名避免干扰 getObjectByName('mag')） */
        this._grabMag = this.parts.mag.clone(true);
        this._grabMag.name = 'magGrab';
        this._grabMag.visible = false;
        this.gun.add(this._grabMag);

        /* ---- vm 枪口火光（正对一片 + 纵横两片，加法混合） ---- */
        const fTex = muzzleFlashTexture();
        this._flashMat = new THREE.MeshBasicMaterial({
            map: fTex, transparent: true, blending: THREE.AdditiveBlending,
            depthWrite: false, side: THREE.DoubleSide
        });
        this._flash = new THREE.Group();
        const fp1 = new THREE.Mesh(new THREE.PlaneGeometry(0.24, 0.24), this._flashMat);
        const fp2 = new THREE.Mesh(new THREE.PlaneGeometry(0.16, 0.16), this._flashMat);
        fp2.rotation.y = Math.PI / 2;
        const fp3 = new THREE.Mesh(new THREE.PlaneGeometry(0.16, 0.16), this._flashMat);
        fp3.rotation.x = Math.PI / 2;
        this._flash.add(fp1, fp2, fp3);
        this._flash.position.copy(this.gun.userData.muzzle);
        this._flash.position.z -= 0.02;
        this._flash.visible = false;
        this.gun.add(this._flash);

        /* ---- 世界空间特效池（曳光 12 / 抛壳 24 / 掉落弹匣 4 / 命中闪光 10） ---- */
        this._initPools();

        /* ---- 内部状态 ---- */
        this._time = 0;
        this._nextFire = 0;
        this._dryLatched = false;
        this._adsHold = false;
        this._raycast = null;
        this._reloadT = 0;
        this._tl = null;
        this._reloadStartAmmo = 0;
        this._rollK = 0;               // 倾枪系数
        this._tiltK = 0;               // 拉栓枪口抬升系数
        this._joltSeatT = -1;          // 拍合 jolt 起始时刻
        this._joltRelT = -1;           // 拉栓回位 jolt
        this._kickPos = 0; this._kickRot = 0; this._kickRoll = 0;
        this._lastShotT = -10;
        this._swayYaw = 0; this._swayPitch = 0;
        this._bobPhase = 0; this._bobX = 0; this._bobY = 0; this._bobR = 0;
        this._ePrevY = 0; this._ePrevX = 0;
        this._prevCamPos = new THREE.Vector3();
        this._baseFov = camera ? camera.fov : 75;
        this._light = null;
        this._lightScene = scene || null;
        this._lightI = 0;
        this._flashT = 0;

        /* 临时对象（避免每帧分配） */
        this._tV1 = new THREE.Vector3(); this._tV2 = new THREE.Vector3();
        this._tV3 = new THREE.Vector3(); this._tV4 = new THREE.Vector3();
        this._tV5 = new THREE.Vector3(); this._tV6 = new THREE.Vector3();
        this._tV7 = new THREE.Vector3(); this._tV8 = new THREE.Vector3();
        this._tM = new THREE.Matrix4();
        this._tE = new THREE.Euler();
        this._muzzleOut = new THREE.Vector3();

        if (camera) {
            camera.getWorldPosition(this._prevCamPos);
            const e = new THREE.Euler().setFromQuaternion(camera.quaternion, 'YXZ');
            this._ePrevY = e.y;
            this._ePrevX = e.x;
        }
        this.update(0);   // 首帧姿态就位（dt=0 无副作用）
    }

    /* ---- 2.1 公开 API ---- */

    setRaycast(fn) { this._raycast = fn; }

    setAds(hold) { this._adsHold = !!hold; }

    setMuzzleLight(scene) {
        this._lightScene = scene || this.scene;
        if (this._light) {                 // 换场景：摘下重建
            this._light.parent.remove(this._light);
            this._light = null;
        }
    }

    /* 换弹：满弹/换弹中/备弹耗尽返回 false；按下瞬间快照 ammo>0 ⇒ 战术 */
    startReload() {
        if (this.reloading) return false;
        if (this.ammo >= RIFLE.mag) return false;
        if (this.reserve <= 0) return false;
        this.reloadKind = this.ammo > 0 ? 'tactical' : 'empty';
        this._tl = this.reloadKind === 'tactical' ? TACTICAL_TL : EMPTY_TL;
        this._reloadStartAmmo = this.ammo;
        this._reloadT = 0;
        this.reloading = true;
        this.reloadProgress = 0;
        this._dryLatched = false;
        return true;
    }

    resetAmmo(reserve = 150) {
        this.reserve = reserve;
        this.ammo = RIFLE.mag;
        this.reloading = false;
        this.reloadKind = null;
        this.reloadProgress = 0;
        this._reloadT = 0;
        this._rollK = 0;
        this._tiltK = 0;
        this.parts.mag.visible = true;
        this.parts.mag.position.copy(this._magHome);
        this.parts.bolt.position.z = this._boltHome.z;
        this._grabMag.visible = false;
    }

    /* 枪口世界坐标（主场景系）：vm 相机空间 → 主相机世界 */
    muzzleWorld() {
        this.camera.updateMatrixWorld(true);
        this.gun.updateWorldMatrix(true, false);
        this._muzzleOut.copy(this.gun.userData.muzzle).applyMatrix4(this.gun.matrixWorld);
        this._muzzleOut.applyMatrix4(this.camera.matrixWorld);
        return this._muzzleOut;
    }

    /* 每帧调用：pressed=true 全自动；返回本帧是否真的开了一发 */
    tryFire(pressed) {
        if (!pressed) { this._dryLatched = false; return false; }
        if (this._time < this._nextFire) return false;
        if (this.reloading && this._tl && this._reloadT < this._tl.fireUnlock) return false;
        if (this.ammo <= 0) {
            if (!this._dryLatched) {         // 空仓干响：一次按压只响一声
                this._dryLatched = true;
                if (this.audio) this.audio.dry();
            }
            return false;
        }
        this._nextFire = this._time + RIFLE.cd;
        this.ammo -= 1;
        this.stats.shots += 1;

        /* 射线：自主相机眼位，散布 = 腰射 spread × 开镜插值倍率 */
        this.camera.updateMatrixWorld(true);
        const from = this._tV1.setFromMatrixPosition(this.camera.matrixWorld);
        const fwd = this._tV2.set(0, 0, -1).transformDirection(this.camera.matrixWorld);
        const right = this._tV3.setFromMatrixColumn(this.camera.matrixWorld, 0);
        const up = this._tV4.setFromMatrixColumn(this.camera.matrixWorld, 1);
        const spreadMul = 1 + (RIFLE.adsSpreadMul - 1) * this.adsAmount;
        const jx = (Math.random() * 2 - 1) * RIFLE.spread * spreadMul;
        const jy = (Math.random() * 2 - 1) * RIFLE.spread * spreadMul;
        const dir = this._tV5.copy(fwd).addScaledVector(right, jx).addScaledVector(up, jy).normalize();

        let hit = null;
        if (this._raycast) hit = this._raycast(from, dir, RIFLE.range);
        const end = this._tV6;
        if (hit && hit.point) end.copy(hit.point);
        else end.copy(from).addScaledVector(dir, RIFLE.range);

        /* 命中统计 / 伤害分发 / 命中音 */
        if (hit && hit.type && hit.type !== 'wall') {
            this.stats.hits += 1;
            let killed = false;
            if (typeof this.applyDamage === 'function') {
                const r = this.applyDamage(hit, RIFLE.dmg);
                killed = !!(r && r.killed);
            }
            if (this.audio) this.audio.hit(killed);
        }
        if (hit && hit.point) this._spawnImpact(end);   // 打墙也出火花

        /* 曳光 / 抛壳 / 枪口火光 */
        this._spawnTracer(this.muzzleWorld(), end, !!hit);
        this._spawnShell(right, up);
        this._flashOn();
        this._lightI = 55;
        if (this.audio) this.audio.shot();

        /* 后坐：onfoot.gd:848-849 公式（连发累增 + 水平漂移，开镜 6 折） */
        const mul = 1 + (RIFLE.recoilAdsMul - 1) * this.adsAmount;
        const pitchDeg = this.recoilPitch / DEG;
        this.recoilPitch = Math.min(RIFLE.recoilCapDeg * DEG,
            this.recoilPitch + (RIFLE.recoil.kick + RIFLE.recoil.growth * pitchDeg * 0.5) * DEG * mul);
        this.recoilYaw += (Math.random() * 2 - 1) * RIFLE.recoil.drift * DEG * mul;
        this._lastShotT = this._time;

        /* viewmodel 踢（自身衰减） */
        this._kickPos += 0.016;
        this._kickRot += 0.022;
        this._kickRoll += (Math.random() - 0.5) * 0.008;
        return true;
    }

    /* ---- 2.2 主更新 ---- */

    update(dt) {
        dt = clamp(dt, 0, 0.05);          // 防御性再夹（main 已夹紧）
        this._time += dt;
        if (this.reloading) this._updateReload(dt);
        this._updateAds(dt);
        this._updateRecoil(dt);
        this._updateSwayBob(dt);
        const kd = Math.exp(-13 * dt);
        this._kickPos *= kd; this._kickRot *= kd; this._kickRoll *= kd;
        this._composePose();
        this._updateVmFlash(dt);
        this._updatePools(dt);
        this._syncCameras();
        this._updateMuzzleLight(dt);
    }

    /* ---- 2.3 换弹时间轴（事件挂绝对秒点，prev<x<=t 触发一次） ---- */

    _updateReload(dt) {
        const tl = this._tl;
        const prev = this._reloadT;
        const t = this._reloadT = Math.min(prev + dt, tl.end);
        const mag = this.parts.mag;

        /* magSlide：旧匣沿本地 Y 下滑 5cm（仍挂枪上） */
        if (t >= tl.slideStart && t < tl.magOutAt) {
            mag.position.y = this._magHome.y - 0.05 * (t - tl.slideStart) / (tl.magOutAt - tl.slideStart);
        }

        /* magOut：旧匣转世界空间抛出（按 reloadTimeline 物理参数） */
        if (prev < tl.magOutAt && t >= tl.magOutAt) {
            this._spawnDroppedMag();
            mag.visible = false;
            if (this.audio) this.audio.magOut();
        }

        /* magSeat 末尾：弹药回满（弹匣永远回满 30）+ 拍合 jolt（挂全局时钟） */
        if (prev < tl.ammoAt && t >= tl.ammoAt) {
            const take = Math.min(this.reserve, RIFLE.mag - this._reloadStartAmmo);
            this.reserve = Math.max(0, this.reserve - take);
            this.ammo = RIFLE.mag;
            this._grabMag.visible = false;
            mag.visible = true;
            mag.position.copy(this._magHome);
            this._joltSeatT = this._time;
            if (this.audio) this.audio.magIn();
        }

        /* 空仓拉栓音效 */
        if (tl.boltBackSnd > 0 && prev < tl.boltBackSnd && t >= tl.boltBackSnd && this.audio) {
            this.audio.boltBack();
        }
        if (tl.boltFwdSnd > 0 && prev < tl.boltFwdSnd && t >= tl.boltFwdSnd) {
            this._joltRelT = this._time;
            if (this.audio) this.audio.boltForward();
        }

        /* magGrab：新匣从画面右下外插向弹匣井（easeInOutCubic）→ 最后 2cm 冲入 */
        const gm = this._grabMag;
        if (t >= tl.grabStart && t < tl.seatEnd) {
            gm.visible = true;
            if (t <= tl.grabEnd) {
                const k = easeInOutCubic((t - tl.grabStart) / (tl.grabEnd - tl.grabStart));
                gm.position.set(
                    this._magHome.x + GRAB_OFF.x * (1 - k),
                    this._magHome.y - 0.02 + (GRAB_OFF.y + 0.02) * (1 - k),
                    this._magHome.z + GRAB_OFF.z * (1 - k));
                gm.rotation.set(0.35 * (1 - k), 0, -0.3 * (1 - k));
            } else {
                const k = easeInQuad((t - tl.grabEnd) / (tl.seatEnd - tl.grabEnd));
                gm.position.set(this._magHome.x, this._magHome.y - 0.02 * (1 - k), this._magHome.z);
                gm.rotation.set(0, 0, 0);
            }
        }

        /* boltPull / boltRelease：拉栓件向枪尾(+Z)后拉 4.5cm 后快甩回位 */
        if (tl.boltStart > 0) {
            let bk = 0;
            if (t >= tl.boltStart && t < tl.boltEnd) {
                bk = easeOutQuad((t - tl.boltStart) / (tl.boltEnd - tl.boltStart));
            } else if (t >= tl.boltEnd && t < tl.boltRelEnd) {
                bk = 1 - easeInQuad((t - tl.boltEnd) / (tl.boltRelEnd - tl.boltEnd));
            }
            this.parts.bolt.position.z = this._boltHome.z + 0.045 * bk;
            this._tiltK = bk;
        }

        /* rollIn 保持 / rollOut 回位（easeOutQuad 进，easeInOutQuad 出） */
        if (t < tl.rollIn) this._rollK = easeOutQuad(t / tl.rollIn);
        else if (t < tl.rollOut) this._rollK = 1;
        else this._rollK = 1 - easeInOutQuad((t - tl.rollOut) / (tl.end - tl.rollOut));

        this.reloadProgress = t / tl.end;

        if (t >= tl.end) {                // 收尾：一切复位
            this.reloading = false;
            this.reloadKind = null;
            this._rollK = 0;
            this._tiltK = 0;
            this.parts.bolt.position.z = this._boltHome.z;
            mag.visible = true;
            mag.position.copy(this._magHome);
            gm.visible = false;
            this.reloadProgress = 1;
        }
    }

    /* ---- 2.4 开镜（换弹锁定段 6/s 强制回 0；解锁点同开火） ---- */

    _updateAds(dt) {
        let target = this._adsHold ? 1 : 0;
        let rate = RIFLE.adsSpeed;
        if (this.reloading && this._tl && this._reloadT < this._tl.fireUnlock) {
            target = 0;
            rate = 6;
        }
        this.adsAmount = moveToward(this.adsAmount, target, rate * dt);
    }

    /* ---- 2.5 后坐自衰减（onfoot.gd:772-775：0.25s 后 45°/s 回落，yaw 10°/s 归零） ---- */

    _updateRecoil(dt) {
        if (this._time - this._lastShotT > RIFLE.recoilRecoverDelay) {
            this.recoilPitch = Math.max(0, this.recoilPitch - RIFLE.recoilRecoverDegPerSec * DEG * dt);
            this.recoilYaw = moveToward(this.recoilYaw, 0, 10 * DEG * dt);
        }
    }

    /* ---- 2.6 摆动 sway（视角角速度反相滞后）与走路 bob（位移速度驱动） ---- */

    _updateSwayBob(dt) {
        const inv = 1 / Math.max(dt, 1e-4);
        if (this.camera) {
            this._tE.setFromQuaternion(this.camera.quaternion, 'YXZ');
            let dYaw = this._tE.y - this._ePrevY;
            if (dYaw > Math.PI) dYaw -= Math.PI * 2;
            else if (dYaw < -Math.PI) dYaw += Math.PI * 2;
            const dPitch = this._tE.x - this._ePrevX;
            this._ePrevY = this._tE.y;
            this._ePrevX = this._tE.x;
            const tYaw = clamp(-(dYaw * inv) * 0.022, -0.07, 0.07);
            const tPitch = clamp((dPitch * inv) * 0.016, -0.05, 0.05);
            const k = 1 - Math.exp(-10 * dt);
            this._swayYaw += (tYaw - this._swayYaw) * k;
            this._swayPitch += (tPitch - this._swayPitch) * k;

            this.camera.getWorldPosition(this._tV7);
            const dx = this._tV7.x - this._prevCamPos.x;
            const dz = this._tV7.z - this._prevCamPos.z;
            this._prevCamPos.copy(this._tV7);
            const spd = Math.sqrt(dx * dx + dz * dz) * inv;
            if (spd > 0.4) this._bobPhase += dt * (1.7 + spd * 1.0);
            const amp = Math.min(spd / 8, 1) * (1 - 0.85 * this.adsAmount);
            this._bobX = Math.sin(this._bobPhase) * 0.0085 * amp;
            this._bobY = (Math.sin(this._bobPhase * 2) * 0.006 - 0.003) * amp;
            this._bobR = Math.sin(this._bobPhase) * 0.011 * amp;
            this._bobY += Math.sin(this._time * 1.3) * 0.0012 * (1 - this.adsAmount);  // 待机呼吸
        }
    }

    /* ---- 2.7 姿态合成：hip/ADS 插值 + sway + bob + 换弹姿态 + jolt + 踢 ---- */

    _composePose() {
        const a = this.adsAmount;
        const adsE = a * a * (3 - 2 * a);       // smoothstep 更贴手感
        const p = this._tV8.lerpVectors(HIP_POS, this._adsPos, adsE);
        let rx = HIP_ROT.x * (1 - adsE);
        let ry = HIP_ROT.y * (1 - adsE);
        let rz = HIP_ROT.z * (1 - adsE);
        /* sway */
        ry += this._swayYaw;
        rx += this._swayPitch;
        p.x += -this._swayYaw * 0.35;
        p.y += this._swayPitch * 0.3;
        /* bob */
        p.x += this._bobX;
        p.y += this._bobY;
        rz += this._bobR;
        /* 换弹：倾枪 roll、下沉、后拉；拉栓时枪口微抬 */
        if (this.reloading && this._tl) {
            const tl = this._tl;
            p.y -= tl.dropY * this._rollK;
            p.z += 0.04 * this._rollK;
            rz += -tl.rollDeg * DEG * this._rollK;
            rx += -1.5 * DEG * this._tiltK;
        }
        /* 拍合 jolt：pitch 2°、y 1cm，指数阻尼 λ=18 */
        if (this._joltSeatT >= 0) {
            const e = Math.exp(-18 * (this._time - this._joltSeatT));
            rx += -2 * DEG * e;
            p.y += 0.01 * e;
        }
        /* 拉栓回位 jolt：pitch −1.5° */
        if (this._joltRelT >= 0) {
            const e = Math.exp(-18 * (this._time - this._joltRelT));
            rx += 1.5 * DEG * e;
        }
        /* 开火踢 */
        p.z += this._kickPos;
        rx -= this._kickRot;
        rz += this._kickRoll;
        this.holder.position.copy(p);
        this.holder.rotation.set(rx, ry, rz);
    }

    /* ---- 2.8 相机同步：主相机 FOV 75→55 随 adsAmount；vmCamera 宽高比跟随 ---- */

    _syncCameras() {
        if (!this.camera) return;
        const targetFov = this._baseFov + (55 - this._baseFov) * this.adsAmount;
        if (Math.abs(this.camera.fov - targetFov) > 0.01) {
            this.camera.fov = targetFov;
            this.camera.updateProjectionMatrix();
        }
        if (Math.abs(this.vmCamera.aspect - this.camera.aspect) > 1e-4) {
            this.vmCamera.aspect = this.camera.aspect;
            this.vmCamera.updateProjectionMatrix();
        }
    }

    /* ---- 2.9 枪口火光与点光 ---- */

    _flashOn() {
        this._flash.visible = true;
        this._flash.rotation.z = Math.random() * Math.PI * 2;
        const s = 0.75 + Math.random() * 0.55;
        this._flash.scale.set(s, s, s);
        this._flashT = 0.05;
    }

    _updateVmFlash(dt) {
        if (this._flashT > 0) {
            this._flashT -= dt;
            if (this._flashT <= 0) this._flash.visible = false;
        }
    }

    _updateMuzzleLight(dt) {
        if (!this._light && this._lightScene) {     // 惰性创建（setMuzzleLight 可指定场景）
            const l = new THREE.PointLight(0xffc873, 0, 14, 2);
            this._lightScene.add(l);
            this._light = l;
        }
        if (!this._light) return;
        this._lightI *= Math.exp(-dt / 0.03);
        if (this._lightI < 0.4) this._lightI = 0;
        this._light.intensity = this._lightI;
        if (this._lightI > 0) this._light.position.copy(this.muzzleWorld());
    }

    /* ==== 3. 世界空间特效池 ==== */

    _initPools() {
        /* 曳光弹 12：加法混合亮条，420m/s、拖尾 6m（tracer_pool.gd 同参数） */
        const tGeo = new THREE.BoxGeometry(0.012, 0.012, 1);
        this._tMat = new THREE.MeshBasicMaterial({
            color: TRACER_COLOR, transparent: true, opacity: 0.95,
            blending: THREE.AdditiveBlending, depthWrite: false
        });
        this._tracers = [];
        this._ti = 0;
        for (let i = 0; i < 12; i++) {
            const m = new THREE.Mesh(tGeo, this._tMat);
            m.visible = false;
            m.frustumCulled = false;
            this.scene.add(m);
            this._tracers.push({
                m, from: new THREE.Vector3(), dir: new THREE.Vector3(),
                dist: 0, s: 0, active: false, impact: false, sparkDone: false
            });
        }

        /* 抛壳 24：黄铜小圆柱，落地 e=0.3，寿命 1.2s + 0.3s 淡出 */
        const shGeo = new THREE.CylinderGeometry(0.004, 0.0042, 0.019, 8);
        this._shells = [];
        this._shi = 0;
        for (let i = 0; i < 24; i++) {
            const m = new THREE.Mesh(shGeo, gunMaterials().brassMat.clone());
            m.visible = false;
            m.frustumCulled = false;
            this.scene.add(m);
            this._shells.push({
                m, v: new THREE.Vector3(), ax: new THREE.Vector3(),
                w: 0, life: 0, fading: false, fadeT: 0, active: false
            });
        }

        /* 掉落弹匣 4：真弹匣组克隆（材质逐槽克隆以便淡出），gravity-only 物理 */
        this._drops = [];
        for (let i = 0; i < 4; i++) {
            const g = this.parts.mag.clone(true);
            g.name = 'magDrop' + i;
            const mats = [];
            g.traverse((o) => {
                if (o.isMesh) {
                    o.material = o.material.clone();
                    o.castShadow = true;
                    mats.push(o.material);
                }
            });
            g.visible = false;
            this.scene.add(g);
            this._drops.push({
                g, v: new THREE.Vector3(), spin: 0, drift: 0,
                state: 'off', t: 0, bounces: 0, mats
            });
        }

        /* 命中闪光 10：加法混合小面片，7ms */
        const iGeo = new THREE.PlaneGeometry(0.09, 0.09);
        const iTex = muzzleFlashTexture();
        this._impacts = [];
        for (let i = 0; i < 10; i++) {
            const mat = new THREE.MeshBasicMaterial({
                map: iTex, transparent: true, opacity: 0.9,
                blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide
            });
            const m = new THREE.Mesh(iGeo, mat);
            m.visible = false;
            m.frustumCulled = false;
            this.scene.add(m);
            this._impacts.push({ m, t: 0, active: false });
        }
    }

    _spawnTracer(from, to, impact) {
        const s = this._tracers[this._ti];
        this._ti = (this._ti + 1) % this._tracers.length;
        /* 被挤掉的旧曳光还没飞到：先补上它的命中火花（tracer_pool.gd 同款处理） */
        if (s.active && !s.sparkDone) {
            this._spawnImpact(this._tV1.copy(s.from).addScaledVector(s.dir, s.dist));
        }
        s.from.copy(from);
        s.dir.copy(to).sub(from);
        s.dist = s.dir.length();
        if (s.dist < 0.05) {           // 起终点几乎重合：不留幽灵曳光
            s.active = false;
            s.m.visible = false;
            if (impact) this._spawnImpact(to);
            return;
        }
        s.dir.divideScalar(s.dist);
        s.s = 0;
        s.active = true;
        s.impact = impact;
        s.sparkDone = !impact;
        s.m.visible = true;
    }

    _spawnShell(right, up) {
        /* 抛壳窗（机匣右本地 (0.04,0.03,0.12)）→ 相机空间 → 世界 */
        this.camera.updateMatrixWorld(true);
        this.gun.updateWorldMatrix(true, false);
        const pos = this._tV1.copy(this.gun.userData.shellPort).applyMatrix4(this.gun.matrixWorld);
        pos.applyMatrix4(this.camera.matrixWorld);
        const back = this._tV2.setFromMatrixColumn(this.camera.matrixWorld, 2);
        const sh = this._shells[this._shi];
        this._shi = (this._shi + 1) % this._shells.length;
        sh.m.position.copy(pos);
        sh.v.copy(right).multiplyScalar(1.8)
            .addScaledVector(up, 1.2)
            .addScaledVector(back, 0.4);
        sh.ax.set(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize();
        sh.w = (Math.random() < 0.5 ? -1 : 1) * 720 * DEG;
        sh.life = 0;
        sh.fading = false;
        sh.fadeT = 0;
        sh.active = true;
        sh.m.visible = true;
        sh.m.material.transparent = false;
        sh.m.material.opacity = 1;
        sh.m.scale.set(1, 1, 1);
    }

    _spawnDroppedMag() {
        /* 从枪上取弹匣世界变换（vm 相机空间 → 主场景世界） */
        this.camera.updateMatrixWorld(true);
        this.gun.updateWorldMatrix(true, false);
        this.parts.mag.updateWorldMatrix(false, false);
        const M = this._tM.multiplyMatrices(this.camera.matrixWorld, this.parts.mag.matrixWorld);
        /* v0 = camForward×0.5 + camRight×0.3 − up×0.2（onfoot.gd:667-670 变体） */
        const F = this._tV1.set(0, 0, -1).transformDirection(this.camera.matrixWorld);
        const R = this._tV2.setFromMatrixColumn(this.camera.matrixWorld, 0);
        const U = this._tV3.setFromMatrixColumn(this.camera.matrixWorld, 1);
        const v = this._tV4.copy(F).multiplyScalar(0.5).addScaledVector(R, 0.3).addScaledVector(U, -0.2);
        this._dropSpawn(M, v);
    }

    _dropSpawn(M, v) {
        let slot = this._drops.find((d) => d.state === 'off');
        if (!slot) {                       // 池满：最旧的立即让位（年龄最大者）
            let bestRank = -1;
            for (const d of this._drops) {
                const rank = d.state === 'fade' ? 1e6 + d.t : d.t;
                if (rank > bestRank) { bestRank = rank; slot = d; }
            }
        }
        slot.g.visible = true;
        slot.g.position.setFromMatrixPosition(M);
        slot.g.quaternion.setFromRotationMatrix(M);
        slot.g.scale.set(1, 1, 1);
        slot.v.copy(v);
        slot.spin = (Math.random() < 0.5 ? -1 : 1) * 480 * DEG;   // 绕弹匣长轴（本地 Y）
        slot.drift = 60 * DEG;                                     // 绕世界 Y 漂移
        slot.bounces = 0;
        slot.t = 0;
        slot.state = 'fly';
        for (const m of slot.mats) { m.transparent = false; m.opacity = 1; }
    }

    _spawnImpact(pos) {
        const s = this._impacts.find((i) => !i.active) || this._impacts[0];
        s.m.position.copy(pos);
        s.m.scale.set(1, 1, 1);
        s.m.material.opacity = 0.9;
        s.m.visible = true;
        s.t = 0;
        s.active = true;
    }

    /* 池推进：曳光飞行 / 弹壳物理 / 弹匣物理 / 闪光衰减 */
    _updatePools(dt) {
        /* 曳光 */
        for (const s of this._tracers) {
            if (!s.active) continue;
            s.s += TRACER_SPEED * dt;
            const head = Math.min(s.s, s.dist);
            const tail = Math.max(s.s - TRACER_LEN, 0);
            if (!s.sparkDone && head >= s.dist) {         // 到点：命中火花
                s.sparkDone = true;
                this._spawnImpact(this._tV1.copy(s.from).addScaledVector(s.dir, s.dist));
            }
            if (tail >= s.dist) {
                s.active = false;
                s.m.visible = false;
                continue;
            }
            const len = Math.max(head - tail, 0.05);
            s.m.position.copy(s.from).addScaledVector(s.dir, (head + tail) / 2);
            s.m.scale.set(1, 1, len);
            s.m.quaternion.setFromUnitVectors(Z_AXIS, s.dir);
        }

        /* 抛壳 */
        for (const sh of this._shells) {
            if (!sh.active) continue;
            sh.life += dt;
            if (!sh.fading && sh.life > 1.2) {
                sh.fading = true;
                sh.fadeT = 0;
                sh.m.material.transparent = true;
            }
            if (sh.fading) {
                sh.fadeT += dt;
                const op = Math.max(0, 1 - sh.fadeT / 0.3);
                sh.m.material.opacity = op;
                if (sh.fadeT >= 0.3) {
                    sh.active = false;
                    sh.m.visible = false;
                    continue;
                }
            }
            sh.v.y -= 9.8 * dt;
            sh.m.position.addScaledVector(sh.v, dt);
            sh.m.rotateOnWorldAxis(sh.ax, sh.w * dt);
            const h = this._ground(sh.m.position.x, sh.m.position.z);
            if (sh.m.position.y <= h + 0.012) {
                sh.m.position.y = h + 0.012;
                if (sh.v.y < 0) sh.v.y = -sh.v.y * 0.3;
                sh.v.x *= 0.6;
                sh.v.z *= 0.6;
                sh.w *= 0.5;
            }
        }

        /* 掉落弹匣 */
        for (const d of this._drops) {
            if (d.state === 'off') continue;
            if (d.state === 'fly') {
                d.t += dt;                          // 飞行中也计龄（池满择旧用）
                d.v.y -= 9.8 * dt;
                d.g.position.addScaledVector(d.v, dt);
                d.g.rotateY(d.spin * dt);                       // 绕本地长轴翻滚
                d.g.rotateOnWorldAxis(Y_AXIS, d.drift * dt);    // 绕世界 Y 漂移
                const h = this._ground(d.g.position.x, d.g.position.z);
                if (d.g.position.y <= h + 0.04) {
                    d.g.position.y = h + 0.04;
                    if (d.v.y < 0) {
                        const e = d.bounces === 0 ? 0.35 : 0.12;
                        d.v.y = -d.v.y * e;
                        d.v.x *= 0.55;
                        d.v.z *= 0.55;
                        d.spin *= 0.4;
                        d.drift *= 0.5;
                        d.bounces += 1;
                        if (d.v.length() < 0.3) {               // 静止：snap 贴地停转
                            d.v.set(0, 0, 0);
                            d.spin = 0;
                            d.drift = 0;
                            d.g.position.y = h + 0.035;
                            d.state = 'rest';
                            d.t = 0;
                        }
                    }
                }
                if (d.g.position.y < h - 2) {                   // 穿地兜底
                    d.g.position.y = h + 0.035;
                    d.state = 'rest';
                    d.t = 0;
                }
            } else if (d.state === 'rest') {
                d.t += dt;
                if (d.t >= 4.0) {                              // 停留 4s 后淡出
                    d.state = 'fade';
                    d.t = 0;
                    for (const m of d.mats) m.transparent = true;
                }
            } else if (d.state === 'fade') {
                d.t += dt;
                const op = Math.max(0, 1 - d.t / 0.8);
                for (const m of d.mats) m.opacity = op;
                if (d.t >= 0.8) {
                    d.state = 'off';
                    d.g.visible = false;
                    for (const m of d.mats) { m.opacity = 1; m.transparent = false; }
                }
            }
        }

        /* 命中闪光（面向相机，快速收缩） */
        for (const s of this._impacts) {
            if (!s.active) continue;
            s.t += dt;
            const k = 1 - s.t / 0.07;
            if (k <= 0) {
                s.active = false;
                s.m.visible = false;
                continue;
            }
            s.m.material.opacity = 0.9 * k;
            s.m.scale.setScalar(0.6 + 0.4 * k);
            s.m.quaternion.copy(this.camera.quaternion);
        }
    }

    /* 地面高度查询（异常/未注入兜底 0） */
    _ground(x, z) {
        if (!this._groundFn) return 0;
        try {
            const h = this._groundFn(x, z);
            return Number.isFinite(h) ? h : 0;
        } catch (e) {
            return 0;
        }
    }

    /* 清理（可选） */
    dispose() {
        for (const s of this._shells) this.scene.remove(s.m);
        for (const d of this._drops) this.scene.remove(d.g);
        for (const t of this._tracers) this.scene.remove(t.m);
        for (const i of this._impacts) this.scene.remove(i.m);
        if (this._light && this._light.parent) this._light.parent.remove(this._light);
        this._light = null;
    }
}
