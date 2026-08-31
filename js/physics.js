import * as THREE from 'three';
import { clamp, damp } from './util.js';
import { TUNING } from './tuning.js';

const GEAR_KMH = [0, 40, 76, 114, 154, 198, 246];   // 各档下限(km/h)
const WHEELBASE = 2.62;

// 车辆动力学（街机拟真折中）：
// 前向/侧向速度分离，转向按运动学目标横摆 + 漂移辅助混合，
// 抓地衰减侧滑；路面摩擦系数随柏油/路肩/草地变化；护栏为软墙反弹。
export class Vehicle {
    constructor(track, opts = {}) {
        this.track = track;
        this.isPlayer = !!opts.isPlayer;
        this.gripScale = opts.gripScale ?? 1;          // AI 技能同时缩放动力与抓地
        this.topSpeed = opts.topSpeed ?? 76;           // m/s
        this.power = opts.power ?? 13.4;               // 低速最大加速度 m/s²

        this.pos = new THREE.Vector3();
        this.heading = 0;
        this.vf = 0;               // 车头方向速度
        this.vl = 0;               // 左向速度
        this.yawRate = 0;
        this.steerVis = 0;
        this.wheelSpinAngle = 0;

        this.input = { throttle: 0, brake: 0, steer: 0, handbrake: false };

        this.surface = 'road';
        this.qIdx = null;
        this.latOff = 0;
        this.segAng = 0;
        this.drifting = false;
        this.slipAmount = 0;
        this.hitImpulse = 0;                 // >0 表示本步撞墙强度
        this.wallContact = new THREE.Vector3();
        this.gLong = 0; this.gLat = 0;
        this._vfPrev = 0;
        this.engineLoadSmoothed = 0;

        // 圈程与进度（连续索引计数）
        this.qPrevIdx = null;
        this.contIdx = 0;
        this.lastFloor = 0;
        this.lapsDone = 0;
        this.onLapComplete = null;
        this.finished = false;
        this.wrongWayTimer = 0;

        this.gear = 1;
        this.rpmNorm = 0.12;
        this.shiftTimer = 0;
        this.speedKmh = 0;
    }

    placeAt(pose) {
        this.pos.copy(pose.pos);
        this.heading = pose.heading;
        this.vf = this.vl = this.yawRate = 0;
        this.qIdx = this.qPrevIdx = pose.idx ?? null;
        if (this.qIdx != null) {
            this.contIdx = pose.idx - this.track.startIdx;   // 位于起跑线后方 => 负值
            if (this.contIdx < -this.track.N / 2) this.contIdx += this.track.N;
        }
        this.lastFloor = Math.floor(this.contIdx / this.track.N);
        this.lapsDone = 0;               // 重置圈数，否则再来一局会立刻"完赛"
        this.wrongWayTimer = 0;
        this.gear = 1; this.rpmNorm = 0.12; this.shiftTimer = 0;
        this.drifting = false; this.hitImpulse = 0;
        this.finished = false;
    }

    step(dt) {
        const trk = this.track;
        const q = trk.query(this.pos.x, this.pos.z, this.qIdx);
        const N = trk.N;
        this.qIdx = q.idx;
        this.latOff = q.latOff;
        this.segAng = q.ang;
        this.surface = q.surf;

        const spd = Math.abs(this.vf);
        const surfGrip = { road: 1.0, curb: 0.92, grass: 0.46 }[this.surface];
        const grip = surfGrip * this.gripScale * TUNING.gripMul;
        const dragMul = { road: 1, curb: 1.08, grass: 3.6 }[this.surface];

        // ---- 转向：运动学目标 + 漂移辅助 ----
        const effMax = TUNING.steerMax / (1 + Math.pow(spd / TUNING.steerFalloffSpeed, TUNING.steerFalloffPow) * TUNING.steerFalloffStr);
        const delta = this.input.steer * effMax;
        let yawT = (this.vf * Math.tan(delta)) / WHEELBASE;
        this.steerVis = damp(this.steerVis, delta, 12, dt);

        const slipAbs = Math.abs(this.vl);
        const driftBlend = clamp((slipAbs - TUNING.driftThresh) / 6, 0, 1);
        yawT = yawT * (1 - driftBlend * 0.72) + driftBlend * this.input.steer * 1.45;
        this.yawRate = damp(this.yawRate, yawT, TUNING.yawResponse, dt);
        this.heading += this.yawRate * dt;

        // ---- 纵向 ----
        const thrEff = this.shiftTimer > 0 ? this.input.throttle * 0.15 : this.input.throttle;
        const tractionCap = grip * 12.5;
        let drive = 0;
        const reverseIntent = this.input.brake > 0 && this.vf < 0.6 && this.input.throttle === 0 && !this.finished;
        if (this.input.throttle > 0 && this.vf >= -0.5) {
            const curve = Math.max(0, 1 - Math.pow(clamp(this.vf / this.topSpeed, 0, 1), 2.2));
            drive = Math.min(this.power * thrEff * curve, tractionCap);
        } else if (reverseIntent) {
            drive = -Math.min(6.2, tractionCap * 0.55);
        }

        let decel = 0;
        if (this.input.brake > 0 && !reverseIntent && Math.abs(this.vf) > 0.3) decel += 26 * grip * this.input.brake;
        if (this.input.handbrake && Math.abs(this.vf) > 0.3) decel += 3.8;
        // 倒车中踩油门：先强力刹停，速度回正后上面的前进驱动自动接管
        if (this.input.throttle > 0 && this.vf < -0.5) decel += 22 * grip;
        const passiveDrag = (0.09 * spd + 0.00075 * spd * spd) * dragMul * (this.input.handbrake ? 2.2 : 1);
        decel += passiveDrag;

        let newVf = this.vf + drive * dt;
        // 阻力只作用于现有运动方向
        const sign = Math.sign(newVf);
        newVf -= sign * Math.min(Math.abs(newVf) / dt, decel) * dt;
        // 低速回正死区
        if (Math.abs(newVf) < 0.14 && this.input.throttle === 0 && !(reverseIntent)) newVf *= 0.5;
        this.vf = newVf;
        this.vf = clamp(this.vf, -11, this.topSpeed);

        // ---- 车身旋转把前向动量泄入侧向（滑移根源）----
        const eps = clamp(this.yawRate * dt, -0.16, 0.16);
        const cs = Math.cos(eps), sn = Math.sin(eps);
        const rvf = this.vf * cs + this.vl * sn;
        const rvl = this.vl * cs - this.vf * sn;
        this.vf = rvf; this.vl = rvl;

        // 轮胎横向抓地
        const gripRate = TUNING.gripRate * grip * (this.input.handbrake ? 0.30 : 1);
        this.vl *= Math.exp(-gripRate * dt);

        this.drifting = Math.abs(this.vl) > 3 || (this.input.handbrake && spd > 9);
        this.slipAmount = damp(this.slipAmount, clamp(Math.abs(this.vl) / 9, 0, 1), 6, dt);

        // ---- 世界系位移 ----
        const s = Math.sin(this.heading), c = Math.cos(this.heading);
        let vx = s * this.vf + c * this.vl;
        let vz = c * this.vf - s * this.vl;
        this.pos.x += vx * dt;
        this.pos.z += vz * dt;

        // g 值平滑（视觉重心转移用）
        this.gLong = damp(this.gLong, (this.vf - this._vfPrev) / dt / 9.81, 6, dt);
        this.gLat = damp(this.gLat, (this.yawRate * this.vf) / 9.81, 6, dt);
        this._vfPrev = this.vf;

        // ---- 软墙 ----
        const WALL = trk.wallLat;
        if (Math.abs(this.latOff) > WALL) {
            const side = Math.sign(this.latOff);
            const la = Math.cos(q.ang), lb = -Math.sin(q.ang);       // 该段左向量(x,z)
            const excess = Math.abs(this.latOff) - WALL;
            this.pos.x -= la * side * excess;
            this.pos.z -= lb * side * excess;
            this.wallContact.set(
                this.pos.x - la * side * WALL * 0,
                0, this.pos.z
            );
            const worldLatVel = vx * la + vz * lb;
            if (worldLatVel * side > 0) {
                this.hitImpulse = Math.min(1, Math.abs(worldLatVel) / 13);
                // 反射向内并损耗切向速度
                const tX = Math.sin(q.ang), tZ = Math.cos(q.ang);
                let tangV = vx * tX + vz * tZ;
                tangV *= Math.max(0.62, 1 - Math.abs(worldLatVel) * 0.018);
                const latBack = -worldLatVel * 0.28;
                const nvx = tX * tangV + la * latBack;
                const nvz = tZ * tangV + lb * latBack;
                this.vf = nvx * s + nvz * c;
                this.vl = nvx * c - nvz * s;
                vx = nvx; vz = nvz;
            }
        }

        // ---- 进度 / 圈数 ----
        if (this.qPrevIdx != null) {
            let d = ((q.idx - this.qPrevIdx) % N + N + N / 2) % N - N / 2;
            if (Math.abs(d) < N / 4) this.contIdx += d;
            // 逆行检测
            const fwdDot = (s * Math.sin(q.ang) + c * Math.cos(q.ang));
            if (spd > 3 && fwdDot < -0.25) this.wrongWayTimer += dt;
            else this.wrongWayTimer = Math.max(0, this.wrongWayTimer - dt * 2);
            const nf = Math.floor(this.contIdx / N);
            if (nf > this.lastFloor && nf >= 1) {
                this.lastFloor = nf;
                this.lapsDone = nf;
                if (this.onLapComplete && !this.finished) this.onLapComplete(nf);
            }
        }
        this.qPrevIdx = q.idx;

        this.updateDrivetrain(dt);
    }

    updateDrivetrain(dt) {
        this.shiftTimer = Math.max(0, this.shiftTimer - dt);
        this.speedKmh = Math.abs(this.vf) * 3.6;
        const v = this.speedKmh;
        let g = 1;
        for (let i = GEAR_KMH.length - 1; i >= 0; i--) {
            if (v >= GEAR_KMH[i]) { g = i + 1; break; }
        }
        g = Math.min(g, GEAR_KMH.length);
        if (g !== this.gear && this.shiftTimer === 0) {
            this.gear = g;
            this.shiftTimer = 0.13;
        }
        const lo = GEAR_KMH[this.gear - 1] ?? 0;
        const hi = GEAR_KMH[this.gear] ?? 300;
        const frac = clamp((v - lo) / Math.max(1, hi - lo), 0, 1);
        const targetRpm = (v < 1 && this.input.throttle === 0) ? 0.10
            : clamp(0.16 + frac * 0.84 + this.input.throttle * 0.05, 0, 1);
        this.rpmNorm = damp(this.rpmNorm, targetRpm, 8, dt);
        this.engineLoadSmoothed = damp(this.engineLoadSmoothed,
            this.input.throttle * 0.7 + clamp((this.gLong * 9.81) / 13, 0, 0.5), 5, dt);
    }

    // 外部冲量（车对车碰撞）
    applyWorldImpulse(ix, iz) {
        const s = Math.sin(this.heading), c = Math.cos(this.heading);
        this.vf += ix * s + iz * c;
        this.vl += ix * c - iz * s;
    }

    worldVelocity(out) {
        const s = Math.sin(this.heading), c = Math.cos(this.heading);
        return out.set(s * this.vf + c * this.vl, 0, c * this.vf - s * this.vl);
    }

    forwardDir(out) { return out.set(Math.sin(this.heading), 0, Math.cos(this.heading)); }

    consumeHit() { const h = this.hitImpulse; this.hitImpulse = 0; return h; }
}
