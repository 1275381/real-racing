import * as THREE from 'three';

// 特效：①胎痕（环形缓冲四边形带）②粒子（尘土/烟雾/火花/砂石）
const SKID_SLOTS = 700;
const SKID_LIFE = 7;

export class Effects {
    constructor(scene) {
        this.scene = scene;
        this._buildSkidMarks();
        this._buildParticles();
        this._lastPos = new WeakMap();   // vehicle -> {L:[x,z], R:[x,z]}
    }

    // ---------- 胎痕 ----------
    _buildSkidMarks() {
        const V = SKID_SLOTS * 4;
        const geo = new THREE.BufferGeometry();
        this.skidPos = new Float32Array(V * 3);
        this.skidCol = new Float32Array(V * 4);
        this.skidAge = new Float32Array(SKID_SLOTS).fill(SKID_LIFE);
        this.skidBase = new Float32Array(SKID_SLOTS);
        this.skidHead = 0;
        for (let i = 0; i < V; i++) {
            this.skidPos[i * 3 + 1] = -10;    // 藏到地下
            this.skidCol[i * 4 + 3] = 0;
        }
        geo.setAttribute('position', new THREE.BufferAttribute(this.skidPos, 3));
        geo.setAttribute('color', new THREE.BufferAttribute(this.skidCol, 4));
        const idx = new Uint32Array(SKID_SLOTS * 6);
        for (let s = 0; s < SKID_SLOTS; s++) {
            const a = s * 4;
            idx.set([a, a + 2, a + 1, a + 2, a + 3, a + 1], s * 6);
        }
        geo.setIndex(new THREE.BufferAttribute(idx, 1));
        const mat = new THREE.MeshBasicMaterial({
            vertexColors: true, transparent: true, depthWrite: false,
            polygonOffset: true, polygonOffsetFactor: -4,
        });
        this.skidMesh = new THREE.Mesh(geo, mat);
        this.skidMesh.renderOrder = 3;
        this.skidMesh.frustumCulled = false;
        this.scene.add(this.skidMesh);
    }

    // 在两后轮位置间铺胎痕；intensity 0..1
    emitSkid(veh, intensity) {
        if (intensity <= 0.05) { this._lastPos.delete(veh); return; }
        const s = Math.sin(veh.heading), c = Math.cos(veh.heading);
        // 后轴左右轮位置
        const w = [];
        w.push([veh.pos.x - c * 0.84 + s * 1.44, veh.pos.z + s * 0.84 + c * 1.44]); // 左后
        w.push([veh.pos.x + c * 0.84 + s * 1.44, veh.pos.z - s * 0.84 + c * 1.44]); // 右后
        let last = this._lastPos.get(veh);
        if (!last) { this._lastPos.set(veh, { L: w[0], R: w[1] }); return; }
        for (let i = 0; i < 2; i++) {
            const key = i === 0 ? 'L' : 'R';
            const dx = w[i][0] - last[key][0], dz = w[i][1] - last[key][1];
            const d = Math.hypot(dx, dz);
            if (d > 0.75 || d < 0.02) { last[key] = w[i]; continue; }
            this._emitQuad(last[key], w[i], intensity);
            last[key] = w[i];
        }
    }

    _emitQuad(p0, p1, strength) {
        const h = this.skidHead;
        this.skidHead = (h + 1) % SKID_SLOTS;
        const dx = p1[0] - p0[0], dz = p1[1] - p0[1];
        const len = Math.hypot(dx, dz);
        if (len < 1e-4) return;
        const nx = (-dz / len) * 0.14, nz = (dx / len) * 0.14;
        const P = this.skidPos, C = this.skidCol;
        const y = 0.055;
        const corners = [
            [p0[0] - nx, y, p0[1] - nz],
            [p0[0] + nx, y, p0[1] + nz],
            [p1[0] - nx, y, p1[1] - nz],
            [p1[0] + nx, y, p1[1] + nz],
        ];
        for (let vi = 0; vi < 4; vi++) {
            const o = (h * 4 + vi) * 3;
            P[o] = corners[vi][0]; P[o + 1] = corners[vi][1]; P[o + 2] = corners[vi][2];
        }
        const a = Math.min(0.62, strength * 0.62);
        for (let vi = 0; vi < 4; vi++) {
            const o = (h * 4 + vi) * 4;
            C[o] = 0.04; C[o + 1] = 0.04; C[o + 2] = 0.05; C[o + 3] = a;
        }
        this.skidAge[h] = 0;
        this.skidBase[h] = strength;
        this._skidDirty = true;
    }

    _updateSkids(dt) {
        let dirty = false;
        for (let s = 0; s < SKID_SLOTS; s++) {
            if (this.skidAge[s] >= SKID_LIFE) continue;
            dirty = true;
            this.skidAge[s] += dt;
            const f = 1 - this.skidAge[s] / SKID_LIFE;
            const a = Math.min(0.62, this.skidBase[s] * 0.62) * f * f;
            const C = this.skidCol;
            for (let vi = 0; vi < 4; vi++) C[(s * 4 + vi) * 4 + 3] = a;
            if (f <= 0) {   // 淡出后沉入地下
                for (let vi = 0; vi < 4; vi++) this.skidPos[(s * 4 + vi) * 3 + 1] = -10;
            }
        }
        if (dirty || this._skidDirty) {
            this.skidMesh.geometry.attributes.position.needsUpdate = true;
            this.skidMesh.geometry.attributes.color.needsUpdate = true;
            this._skidDirty = false;
        }
    }

    clearSkids() {
        this.skidAge.fill(SKID_LIFE);
        this.skidBase.fill(0);
        for (let i = 0; i < SKID_SLOTS * 4; i++) {
            this.skidCol[i * 4 + 3] = 0;
            this.skidPos[i * 3 + 1] = -10;
        }
        this.skidMesh.geometry.attributes.position.needsUpdate = true;
        this.skidMesh.geometry.attributes.color.needsUpdate = true;
        this._lastPos = new WeakMap();
    }

    // ---------- 粒子 ----------
    _buildParticles() {
        const MAXP = this.MAXP = 520;
        const geo = new THREE.BufferGeometry();
        this.pPos = new Float32Array(MAXP * 3);
        this.pVel = new Float32Array(MAXP * 3);
        this.pLife = new Float32Array(MAXP);
        this.pSpan = new Float32Array(MAXP);
        this.pSize = new Float32Array(MAXP);
        this.pGrav = new Float32Array(MAXP);
        this.pCol = new Float32Array(MAXP * 3);
        this.pAlpha = new Float32Array(MAXP);
        this.pBaseA = new Float32Array(MAXP);
        this.head = 0;
        for (let i = 0; i < MAXP; i++) { this.pPos[i * 3 + 1] = -50; }

        geo.setAttribute('position', new THREE.BufferAttribute(this.pPos, 3));
        geo.setAttribute('color', new THREE.BufferAttribute(this.pCol, 3));
        geo.setAttribute('aAlpha', new THREE.BufferAttribute(this.pAlpha, 1));
        geo.setAttribute('aSize', new THREE.BufferAttribute(this.pSize, 1));

        const mat = new THREE.ShaderMaterial({
            transparent: true,
            depthWrite: false,
            vertexShader: `
                attribute float aAlpha;
                attribute float aSize;
                varying float vAlpha;
                varying vec3 vCol;
                void main() {
                    vAlpha = aAlpha;
                    vCol = color;
                    vec4 mv = modelViewMatrix * vec4(position, 1.0);
                    gl_PointSize = clamp(aSize * (200.0 / max(1.0, -mv.z)), 1.0, 72.0);
                    gl_Position = projectionMatrix * mv;
                }`,
            fragmentShader: `
                varying float vAlpha;
                varying vec3 vCol;
                void main() {
                    vec2 d = gl_PointCoord - 0.5;
                    float m = smoothstep(0.5, 0.12, length(d));
                    gl_FragColor = vec4(vCol, vAlpha * m);
                    if (gl_FragColor.a < 0.01) discard;
                }`,
            vertexColors: true,
        });
        this.points = new THREE.Points(geo, mat);
        this.points.frustumCulled = false;
        this.points.renderOrder = 5;
        this.scene.add(this.points);
    }

    spawn(pos, opts = {}) {
        const n = opts.count ?? 10;
        for (let k = 0; k < n; k++) {
            const i = this.head;
            this.head = (this.head + 1) % this.MAXP;
            const jx = (Math.random() - 0.5) * (opts.spread ?? 0.8);
            const jz = (Math.random() - 0.5) * (opts.spread ?? 0.8);
            const jit = opts.velocityJitter ?? 1;
            this.pPos[i * 3] = pos.x + jx;
            this.pPos[i * 3 + 1] = pos.y + Math.random() * (opts.lift ?? 0.15);
            this.pPos[i * 3 + 2] = pos.z + jz;
            this.pVel[i * 3] = (opts.vx ?? 0) * jit + (Math.random() - 0.5) * 1.6;
            this.pVel[i * 3 + 1] = (opts.vy ?? 1.2) * (0.5 + Math.random() * 0.9);
            this.pVel[i * 3 + 2] = (opts.vz ?? 0) * jit + (Math.random() - 0.5) * 1.6;
            this.pLife[i] = 0;
            this.pSpan[i] = (opts.life ?? 1.1) * (0.7 + Math.random() * 0.6);
            this.pSize[i] = (opts.size ?? 7) * (0.7 + Math.random() * 0.6);
            this.pGrav[i] = opts.gravity ?? -1.2;
            const col = opts.color ?? [0.72, 0.68, 0.55];
            this.pCol[i * 3] = col[0]; this.pCol[i * 3 + 1] = col[1]; this.pCol[i * 3 + 2] = col[2];
            this.pBaseA[i] = opts.alpha ?? 0.5;
        }
    }

    update(dt) {
        this._updateSkids(dt);
        for (let i = 0; i < this.MAXP; i++) {
            if (this.pLife[i] >= this.pSpan[i]) { this.pAlpha[i] = 0; continue; }
            this.pLife[i] += dt;
            const t = this.pLife[i] / this.pSpan[i];
            this.pVel[i * 3 + 1] += this.pGrav[i] * dt;
            this.pPos[i * 3] += this.pVel[i * 3] * dt;
            this.pPos[i * 3 + 1] = Math.max(0.03, this.pPos[i * 3 + 1] + this.pVel[i * 3 + 1] * dt);
            this.pPos[i * 3 + 2] += this.pVel[i * 3 + 2] * dt;
            this.pVel[i * 3] *= 1 - 1.4 * dt;
            this.pVel[i * 3 + 2] *= 1 - 1.4 * dt;
            this.pAlpha[i] = this.pBaseA[i] * (1 - t);
        }
        const g = this.points.geometry;
        g.attributes.position.needsUpdate = true;
        g.attributes.color.needsUpdate = true;
        g.attributes.aAlpha.needsUpdate = true;
        g.attributes.aSize.needsUpdate = true;
    }

    // ---------- 组合效果 ----------
    surfaceEffects(veh) {
        const spd = Math.abs(veh.vf);
        if (spd < 3) return;
        const now = performance.now();
        const rearY = 0.25;
        const s = Math.sin(veh.heading), c = Math.cos(veh.heading);
        const rl = new THREE.Vector3(
            veh.pos.x - c * 0.84 + s * 1.44, rearY, veh.pos.z + s * 0.84 + c * 1.44);

        if (veh.surface === 'grass') {
            if (now - (veh._fxT || 0) > 60) {
                veh._fxT = now;
                this.spawn(rl, {
                    count: 2, color: [0.45, 0.42, 0.26], alpha: 0.38,
                    vx: -s * spd * 0.18, vz: -c * spd * 0.18, size: 2.4, life: 0.8, lift: 0.3, velocityJitter: 1.6,
                });
            }
        } else if (veh.drifting) {
            if (now - (veh._fxT || 0) > 55) {
                veh._fxT = now;
                this.spawn(rl, {
                    count: 2, color: [0.72, 0.72, 0.75], alpha: 0.15,
                    vx: -s * spd * 0.22, vz: -c * spd * 0.22, size: 2.2, life: 1.0, lift: 0.2, velocityJitter: 2.0,
                });
            }
        } else if (veh.surface === 'curb' && spd > 12 && now - (veh._fxT || 0) > 140) {
            veh._fxT = now;
            this.spawn(rl, {
                count: 1, color: [0.55, 0.52, 0.48], alpha: 0.35,
                size: 1.4, life: 0.45, gravity: -6, velocityJitter: 2.4,
            });
        }
        // 起步烧胎烟
        if (veh.input.throttle > 0.9 && veh.vf > 0 && veh.vf < 7 && veh.surface === 'road') {
            if (now - (veh._fxT2 || 0) > 90 && Math.random() < 0.6) {
                veh._fxT2 = now;
                this.spawn(rl, {
                    count: 1, color: [0.78, 0.78, 0.8], alpha: 0.2, size: 2.0, life: 0.8,
                    vx: -s * 2, vz: -c * 2, velocityJitter: 2,
                });
            }
        }
    }

    wallSparks(contact) {
        this.spawn(contact, {
            count: 14, color: [1.0, 0.72, 0.25], alpha: 0.85, size: 2.2,
            life: 0.5, gravity: -11, vy: 2.4, spread: 0.5, velocityJitter: 4,
        });
        this.spawn(contact, {
            count: 5, color: [0.6, 0.58, 0.55], alpha: 0.35, size: 3.0,
            life: 0.7, vy: 1.2, velocityJitter: 2,
        });
    }

    carBump(pos) {
        this.spawn(pos, {
            count: 8, color: [0.95, 0.8, 0.35], alpha: 0.65, size: 2.2,
            life: 0.4, gravity: -9, vy: 2, spread: 0.8, velocityJitter: 3,
        });
    }
}
