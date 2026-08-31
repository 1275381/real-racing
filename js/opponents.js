import * as THREE from 'three';
import { clamp, damp, wrapAngle } from './util.js';

// AI 车手：前瞻追踪中心线 + 按前方曲率限速 + 避让 + 橡皮筋
export class AIController {
    constructor(vehicle, track, opts = {}) {
        this.veh = vehicle;
        this.track = track;
        this.skill = opts.skill ?? 1;               // 抓地/动力/限速整体系数
        this.baseLane = opts.baseLane ?? 0;         // 常用走线横向偏移
        this.rubber = 0;                            // 由 Game 注入 -0.06..+0.08
        this.laneOffset = this.baseLane;
        this.targetLane = this.baseLane;
        this.stuckTimer = 0;
        this.reverseTimer = 0;
        this._tmpV = new THREE.Vector3();
    }

    // 新一局开始时清空跨局残留状态
    reset() {
        this.stuckTimer = 0;
        this.reverseTimer = 0;
        this.laneOffset = this.baseLane;
        this.targetLane = this.baseLane;
        this.rubber = 0;
    }

    update(dt, others) {
        const veh = this.veh, trk = this.track;

        // 卡死自救：倒车 1.2 秒再继续
        if (this.reverseTimer > 0) {
            this.reverseTimer -= dt;
            veh.input.throttle = 0;
            veh.input.brake = 1;
            veh.input.steer = -Math.sign(veh.vl || 1);
            if (this.reverseTimer <= 0) this.stuckTimer = 0;
            return;
        }
        if (Math.abs(veh.vf) < 0.8 && veh.input.throttle > 0.5) {
            this.stuckTimer += dt;
            if (this.stuckTimer > 2.2) { this.reverseTimer = 1.15; return; }
        } else this.stuckTimer = Math.max(0, this.stuckTimer - dt);

        // ---- 目标点：前瞻 + 变线偏移 ----
        const la = 6 + Math.abs(veh.vf) * 0.55;
        const ti = trk.aheadIdx(veh.qIdx ?? 0, la);
        // 平滑变换走线（超越时横移）
        this.laneOffset = damp(this.laneOffset, this.targetLane, 1.4, dt);
        const tp = trk.pts[ti], tl = trk.leftV[ti];
        const tx = tp.x + tl.x * (this.laneOffset + this.baseLane);
        const tz = tp.z + tl.z * (this.laneOffset + this.baseLane);

        const desired = Math.atan2(tx - veh.pos.x, tz - veh.pos.z);
        const err = wrapAngle(desired - veh.heading);
        veh.input.steer = clamp(err * 3.0 - veh.yawRate * 0.12, -1, 1);

        // ---- 前方曲率 → 允许速度（含刹车距离约束）----
        let vAllow = veh.topSpeed;
        const muA = 10.2 * this.skill;
        let scanDist = 0;
        for (let j = 0; j < 64; j += 3) {
            const idx = trk.aheadIdx(veh.qIdx ?? 0, 8 + j * 3);
            const k = Math.max(Math.abs(trk.curv[idx]), 1e-5);
            const vc = Math.sqrt(muA / k) + 2.5;
            const d = 8 + j * 3;
            const allowed = Math.sqrt(vc * vc + 2 * 17 * d);
            vAllow = Math.min(vAllow, allowed);
        }
        vAllow *= this.skill * (1 + this.rubber);
        vAllow = Math.min(vAllow, veh.topSpeed * this.skill * (1 + this.rubber));

        // ---- 油门 / 刹车 ----
        const dv = vAllow - veh.vf;
        if (dv > 1.5) {
            veh.input.throttle = clamp(dv / 8, 0.35, 1);
            veh.input.brake = 0;
        } else if (dv < -2) {
            veh.input.throttle = 0;
            veh.input.brake = clamp(-dv / 9, 0.25, 1);
        } else {
            veh.input.throttle = 0.4;
            veh.input.brake = 0;
        }

        // ---- 简单避让：前车太近则变线并收油 ----
        if (others && others.length) {
            let dodged = false;
            for (const o of others) {
                if (o === veh) continue;
                const dx = o.pos.x - veh.pos.x, dz = o.pos.z - veh.pos.z;
                const s = Math.sin(veh.heading), c = Math.cos(veh.heading);
                const fwdD = dx * s + dz * c;
                const latD = dx * c - dz * (-s);      // dot with left vector (c,-s)
                if (fwdD > 0 && fwdD < 11 && Math.abs(latD) < 3.4 && o.speedKmh < veh.speedKmh + 12) {
                    this.targetLane = clamp((latD > 0 ? -1 : 1) * 3.2, -5, 5);
                    if (fwdD < 5.5) veh.input.throttle *= 0.4;
                    dodged = true;
                    break;
                }
            }
            if (!dodged && Math.abs(this.laneOffset) > 0.2) {
                // 无威胁后缓回本线路
                this.targetLane = 0;
            }
        }

        veh.input.handbrake = false;
    }

    // 完赛后的巡航自动驾驶
    cruise() {
        const veh = this.veh, trk = this.track;
        const ti = trk.aheadIdx(veh.qIdx ?? 0, 10 + Math.abs(veh.vf) * 0.5);
        const tp = trk.pts[ti];
        const desired = Math.atan2(tp.x - veh.pos.x, tp.z - veh.pos.z);
        const err = wrapAngle(desired - veh.heading);
        veh.input.steer = clamp(err * 2.6, -1, 1);
        veh.input.throttle = veh.vf < 12 ? 0.45 : 0;
        veh.input.brake = veh.vf > 18 ? 0.35 : 0;
    }
}
