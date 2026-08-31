import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { CONTROL_POINTS, ROAD_HALF_W } from './trackConfig.js';
import { asphaltTexture, checkerTexture, bannerTexture, crowdTexture } from './textures.js';

const UP = new THREE.Vector3(0, 1, 0);

// 赛道：闭样条 -> 均匀弧长采样 -> 路面/标线/路肩红白 curb/护栏/龙门架/看台
export class RaceTrack {
    constructor(scene, renderer, def = {}) {
        const points = def.points ?? CONTROL_POINTS;
        this.theme = def.theme ?? 'country';
        this.group = new THREE.Group();   // 本赛道全部静态物体，切换地图时整体显隐
        scene.add(this.group);
        const add = (o) => this.group.add(o);
        this.halfW = ROAD_HALF_W;
        this.wallLat = ROAD_HALF_W + 2.05;      // 软墙限位（护栏内侧）
        const cps = points.map(([x, z]) => new THREE.Vector3(x, 0, z));
        this.curve = new THREE.CatmullRomCurve3(cps, true, 'catmullrom', 0.55);
        this.length = this.curve.getLength();
        this.N = Math.max(700, Math.round(this.length / 1.3));   // 约1.3m一个采样

        this.pts = []; this.tang = []; this.leftV = [];
        this.ang = new Float32Array(this.N);
        this.curv = new Float32Array(this.N);

        for (let i = 0; i < this.N; i++) {
            const u = i / this.N;
            this.pts.push(this.curve.getPointAt(u));
            const t = this.curve.getTangentAt(u); t.y = 0; t.normalize();
            this.tang.push(t);
            this.leftV.push(new THREE.Vector3().crossVectors(UP, t).normalize());
            this.ang[i] = Math.atan2(t.x, t.z);
        }
        // 有符号曲率（平滑窗）
        const rawK = new Float32Array(this.N);
        for (let i = 0; i < this.N; i++) {
            const a = this.tang[i], b = this.tang[(i + 1) % this.N];
            rawK[i] = (a.z * b.x - a.x * b.z);
        }
        const W = 9;
        for (let i = 0; i < this.N; i++) {
            let s = 0;
            for (let j = -W; j <= W; j++) s += rawK[(i + j + this.N) % this.N];
            this.curv[i] = s / (2 * W + 1);
        }

        this._buildSpatialGrid();
        this._findStartLine();
        this._buildApron();
        const maxAniso = renderer.capabilities.getMaxAnisotropy();
        this._buildRoadMeshes(maxAniso);
        this._buildRails();
        this._buildGantry();
        this._buildStands();
        this.startPos = this.pts[this.startIdx].clone();
        this.startAng = this.ang[this.startIdx];
    }

    setVisible(v) { this.group.visible = v; }

    // ---------- 砂石路肩带 ----------
    _buildApron() {
        const pts = this.pts, lv = this.leftV, N = this.N, halfW = this.halfW;
        const pos = [], idx = [];
        for (let side of [-1, 1]) {
            const base = pos.length / 3;
            for (let i = 0; i <= N; i++) {
                const j = i % N;
                pos.push(pts[j].x + (-lv[j].x) * side * (halfW + 3.4), 0.015, pts[j].z + (-lv[j].z) * side * (halfW + 3.4));
                pos.push(pts[j].x + (-lv[j].x) * side * (halfW + 0.05), 0.015, pts[j].z + (-lv[j].z) * side * (halfW + 0.05));
            }
            for (let i = 0; i < N; i++) {
                const a = base + i * 2;
                idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
            }
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        geo.setIndex(pos.length / 3 > 65535 ? new THREE.BufferAttribute(new Uint32Array(idx), 1) : idx);
        geo.computeVertexNormals();
        const apronColor = { country: 0x9a8a6a, city: 0x8e9496, desert: 0xcbb18a }[this.theme] ?? 0x9a8a6a;
        const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
            color: apronColor, roughness: 1, metalness: 0,
        }));
        mesh.receiveShadow = true;
        this.group.add(mesh);
    }

    // ---------- 空间网格（树木摆放 & 无提示的全局查询） ----------
    _buildSpatialGrid(cell = 48) {
        this.cell = cell;
        this.grid = new Map();
        for (let i = 0; i < this.N; i += 2) {
            const p = this.pts[i];
            const key = ((p.x / cell) | 0) + '_' + ((p.z / cell) | 0);
            let arr = this.grid.get(key);
            if (!arr) { arr = []; this.grid.set(key, arr); }
            arr.push(i);
        }
    }

    _nearIndices(x, z, r) {
        const out = [];
        const c = this.cell, gx = (x / c) | 0, gz = (z / c) | 0, R = Math.ceil(r / c);
        for (let i = -R; i <= R; i++) for (let j = -R; j <= R; j++) {
            const arr = this.grid.get((gx + i) + '_' + (gz + j));
            if (arr) out.push(...arr);
        }
        return out;
    }

    isClearOfRoad(x, z, minDist) {
        const cand = this._nearIndices(x, z, minDist + 10);
        const d2min = minDist * minDist;
        for (const i of cand) {
            const p = this.pts[i], dx = p.x - x, dz = p.z - z;
            if (dx * dx + dz * dz < d2min) return false;
        }
        return true;
    }

    // ---------- 查找起跑直段 ----------
    _findStartLine() {
        const thr = 0.0055;
        let bestLen = 0, bestStart = 0, run = 0, runStart = 0;
        for (let i = 0; i < this.N * 2; i++) {
            const k = Math.abs(this.curv[i % this.N]);
            if (k < thr) {
                if (run === 0) runStart = i;
                run++;
                if (run > bestLen) { bestLen = run; bestStart = runStart; }
            } else run = 0;
        }
        if (bestLen < 50) { // 兜底：全赛道扫描曲率最小的窗口
            const win = Math.max(35, Math.round(46 / (this.length / this.N)));
            let bestKSum = 1e9;
            bestStart = 0;
            for (let i = 0; i < this.N; i++) {
                let s = 0;
                for (let d = 0; d < win; d++) s += Math.abs(this.curv[(i + d) % this.N]);
                if (s < bestKSum) { bestKSum = s; bestStart = i; }
            }
            bestLen = win;
        }
        this.startIdx = (bestStart + Math.floor(bestLen * 0.42)) % this.N;
        this.straightBehind = Math.min(bestLen - Math.floor(bestLen * 0.42), 46);
    }

    // ---------- 路面（沥青含标线纹理）与红白路肩 ----------
    _buildRoadMeshes(maxAniso) {
        const N = this.N, hw = this.halfW;

        // 主路面条带
        const pos = [], uv = [], idx = [];
        const rep = Math.max(1, Math.round(this.length / 16));   // 纹理重复次数，保证首尾无缝
        for (let i = 0; i <= N; i++) {
            const j = i % N;
            const p = this.pts[j], l = this.leftV[j];
            pos.push(p.x - l.x * hw, 0.03, p.z - l.z * hw);
            pos.push(p.x + l.x * hw, 0.03, p.z + l.z * hw);
            uv.push(0, (i / N) * rep, 1, (i / N) * rep);
            if (i < N) {
                const a = i * 2;
                idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
            }
        }
        const roadGeo = new THREE.BufferGeometry();
        roadGeo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        roadGeo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
        roadGeo.setIndex(pos.length / 3 > 65535 ? new THREE.BufferAttribute(new Uint32Array(idx), 1) : idx);
        roadGeo.computeVertexNormals();
        const asphalt = asphaltTexture(maxAniso);
        asphalt.repeat.set(1, 1);
        this.roadMat = new THREE.MeshStandardMaterial({
            map: asphalt, roughness: 0.92, metalness: 0,
            polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1,
        });
        const road = new THREE.Mesh(roadGeo, this.roadMat);
        road.receiveShadow = true;
        this.group.add(road);

        // 红白路肩：按曲率挑出弯道区段
        const SEG_W = 4;                     // 每4个样本换一次颜色
        const inCurve = (i) => Math.abs(this.curv[(i + N) % N]) > 0.0075;
        const ranges = [];
        let st = -1;
        for (let i = 0; i < N; i++) {
            if (inCurve(i)) { if (st < 0) st = i; }
            else if (st >= 0) { if (i - st > 8) ranges.push([st, i]); st = -1; }
        }
        if (st >= 0 && ranges.length && (ranges[0][0] + N) - st > 8 && ranges[0][0] < 8) ranges[0][0] = st - N;
        else if (st >= 0 && N - st > 8) ranges.push([st, st + 20]);

        const cpos = [], ccol = [], cidx = [];
        const red = new THREE.Color(0xd23a2e), white = new THREE.Color(0xeceff2);
        for (const [s0, s1] of ranges) {
            const len = s1 - s0;
            for (const side of [-1, 1]) {
                const base = cpos.length / 3;
                for (let q = 0; q <= len; q++) {
                    const i = ((s0 + q) % N + N) % N;
                    const p = this.pts[i], l = this.leftV[i];
                    const col = (Math.floor(q / SEG_W) % 2 === 0) ? red : white;
                    for (const w of [hw + 0.12, hw + 1.32]) {
                        cpos.push(p.x + l.x * w * side, 0.055, p.z + l.z * w * side);
                        ccol.push(col.r, col.g, col.b);
                    }
                }
                for (let q = 0; q < len; q++) {
                    const a = base + q * 2;
                    cidx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
                }
            }
        }
        if (cidx.length) {
            const cg = new THREE.BufferGeometry();
            cg.setAttribute('position', new THREE.Float32BufferAttribute(cpos, 3));
            cg.setAttribute('color', new THREE.Float32BufferAttribute(ccol, 3));
            cg.setIndex(cidx);
            cg.computeVertexNormals();
            const curbs = new THREE.Mesh(cg, new THREE.MeshStandardMaterial({
                vertexColors: true, roughness: 0.65,
            }));
            curbs.receiveShadow = true;
            this.group.add(curbs);
        }

        // 起跑线格子
        const sp = this.pts[this.startIdx];
        const lineGroup = new THREE.Group();
        lineGroup.position.copy(sp);
        lineGroup.rotation.y = this.ang[this.startIdx];
        const ck = new THREE.Mesh(
            new THREE.PlaneGeometry(hw * 2, 2.6),
            new THREE.MeshBasicMaterial({
                map: checkerTexture(Math.round(hw / 0.7), 2),
                polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
            })
        );
        ck.rotation.x = -Math.PI / 2;
        ck.position.y = 0.055;
        lineGroup.add(ck);
        this.group.add(lineGroup);
    }

    // ---------- 护栏（连续钢带 + 立柱） ----------
    _buildRails() {
        const N = this.N, off = this.halfW + 2.35;
        const mat = new THREE.MeshStandardMaterial({
            color: 0xb9bec5, metalness: 0.78, roughness: 0.34,
            side: THREE.DoubleSide,
        });

        for (const side of [-1, 1]) {
            const pos = [], idx = [];
            for (let i = 0; i <= N; i++) {
                const j = i % N;
                const p = this.pts[j], l = this.leftV[j];
                const bx = p.x - l.x * off * side, bz = p.z - l.z * off * side;
                pos.push(bx, 0.62, bz);
                pos.push(bx, 0.30, bz);
                if (i < N) {
                    const a = i * 2;
                    idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
                }
            }
            const g = new THREE.BufferGeometry();
            g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
            g.setIndex(pos.length / 3 > 65535 ? new THREE.BufferAttribute(new Uint32Array(idx), 1) : idx);
            g.computeVertexNormals();
            this.group.add(new THREE.Mesh(g, mat));
        }

        // 立柱
        const posts = [];
        const step = 7;
        for (const side of [-1, 1]) {
            for (let i = 0; i < N; i += step) {
                const p = this.pts[i], l = this.leftV[i];
                const pg = new THREE.BoxGeometry(0.16, 0.68, 0.16);
                const m4 = new THREE.Matrix4()
                    .makeRotationY(this.ang[i])
                    .setPosition(p.x - l.x * off * side, 0.34, p.z - l.z * off * side);
                pg.applyMatrix4(m4);
                posts.push(pg);
            }
        }
        const postGeo = mergeGeometries(posts);
        const postMesh = new THREE.Mesh(postGeo, new THREE.MeshStandardMaterial({
            color: 0x7c828a, metalness: 0.6, roughness: 0.5,
        }));
        postMesh.castShadow = true;
        this.group.add(postMesh);
    }

    // ---------- 起点龙门架 + 信号灯 ----------
    _buildGantry() {
        const hw = this.halfW;
        const sp = this.pts[this.startIdx];
        const A = this.ang[this.startIdx];
        const g = new THREE.Group();
        g.position.copy(sp);
        g.rotation.y = A;
        const steel = new THREE.MeshStandardMaterial({ color: 0x2b3038, metalness: 0.7, roughness: 0.4 });
        const spanX = hw + 3.2;
        for (const sx of [-spanX, spanX]) {
            const pil = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.36, 7.2, 12), steel);
            pil.position.set(sx, 3.6, 0);
            pil.castShadow = true;
            g.add(pil);
        }
        const beamW = spanX * 2;
        const beam = new THREE.Mesh(new THREE.BoxGeometry(beamW + 1, 1.3, 1.6), steel);
        beam.position.set(0, 7.4, 0);
        beam.castShadow = true;
        g.add(beam);

        const banner = new THREE.Mesh(
            new THREE.PlaneGeometry(beamW - 2, 2.1),
            new THREE.MeshBasicMaterial({ map: bannerTexture('REAL RACING · 极速争锋'), side: THREE.DoubleSide })
        );
        banner.position.set(0, 6.2, -0.05);
        banner.rotation.y = Math.PI;   // 正面朝向来车方向
        g.add(banner);

        this.lampMats = [];
        for (let k = -1; k <= 1; k++) {
            const m = new THREE.MeshStandardMaterial({
                color: 0x131313, emissive: 0xff2020, emissiveIntensity: 0,
            });
            const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.34, 14, 10), m);
            lamp.position.set(k * 1.5, 6.3, -0.2);
            g.add(lamp);
            this.lampMats.push(m);
        }
        this.group.add(g);
    }

    setLampStage(stage) {   // 0灭 1..3红灯 4绿灯起步
        for (let i = 0; i < 3; i++) {
            const m = this.lampMats[i];
            if (stage >= 4) { m.emissive.setHex(0x27d94c); m.emissiveIntensity = 2.6; }
            else { m.emissive.setHex(0xff2020); m.emissiveIntensity = stage > i ? 2.4 : 0; }
        }
    }

    // ---------- 看台 ----------
    _buildStands() {
        const crowdTex = crowdTexture();

        const stand = () => {
            const grp = new THREE.Group();
            const conc = new THREE.MeshStandardMaterial({ color: 0xb9b4ac, roughness: 0.9 });
            // 三层阶梯
            for (let t = 0; t < 3; t++) {
                const b = new THREE.Mesh(new THREE.BoxGeometry(44, 1.6 + t * 1.2, 3.4), conc);
                b.position.set(0, (1.6 + t * 1.2) / 2, -t * 3.2);
                b.castShadow = true; b.receiveShadow = true;
                grp.add(b);
            }
            // 观众墙
            const cw = new THREE.Mesh(
                new THREE.PlaneGeometry(43.5, 6),
                new THREE.MeshBasicMaterial({ map: crowdTex })
            );
            cw.position.set(0, 3.4, 1.73);
            grp.add(cw);
            // 顶棚
            const roof = new THREE.Mesh(
                new THREE.BoxGeometry(46, 0.5, 11),
                new THREE.MeshStandardMaterial({ color: 0xd8dde2, metalness: 0.4, roughness: 0.5 })
            );
            roof.position.set(0, 8.6, -4.4);
            roof.rotation.x = 0.09;
            roof.castShadow = true;
            grp.add(roof);
            for (const px of [-21, 21]) {
                const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 8.4, 8),
                    new THREE.MeshStandardMaterial({ color: 0x777d84, metalness: 0.6, roughness: 0.4 }));
                pole.position.set(px, 4.2, -8.6);
                grp.add(pole);
            }
            return grp;
        };

        // 1号看台：起跑线右侧（沿行进方向右手边）
        const s1 = stand();
        const dir = new THREE.Vector3().crossVectors(this.tang[this.startIdx], UP).normalize(); // 右侧向量
        const p1 = this.pts[this.startIdx].clone().addScaledVector(dir, -(this.halfW + 12.5));
        s1.position.copy(p1);
        s1.lookAt(this.pts[this.startIdx].x, 0, this.pts[this.startIdx].z);
        this.group.add(s1);

        // 2号看台：发夹弯外侧
        let tightest = 0;
        for (let i = 0; i < this.N; i++) if (Math.abs(this.curv[i]) > Math.abs(this.curv[tightest])) tightest = i;
        const s2 = stand();
        const idx2 = (tightest + 26) % this.N;
        const dir2 = new THREE.Vector3().crossVectors(this.tang[idx2], UP).normalize();
        const p2 = this.pts[idx2].clone().addScaledVector(dir2, this.halfW + 10.5);
        // 放在外侧：选择离赛道中心更远的一侧
        const alt = this.pts[idx2].clone().addScaledVector(dir2, -(this.halfW + 10.5));
        if (alt.distanceTo(new THREE.Vector3(0, 0, 30)) < p2.distanceTo(new THREE.Vector3(0, 0, 30))) s2.position.copy(alt);
        else s2.position.copy(p2);
        const near = this.pts[idx2];
        s2.lookAt(near.x, 0, near.z);
        this.group.add(s2);
    }

    // ---------- 运行时查询 ----------
    _scratch = { idx: 0, latOff: 0, ang: 0, surf: 'road', distSq: 0 };

    // hint 给上次索引可把搜索限制在局部；无 hint 全局搜
    query(x, z, hint) {
        const N = this.N;
        let bi = 0, bd = Infinity;
        if (hint == null) {
            for (let i = 0; i < N; i++) {
                const dx = this.pts[i].x - x, dz = this.pts[i].z - z;
                const d = dx * dx + dz * dz;
                if (d < bd) { bd = d; bi = i; }
            }
        } else {
            const W = 46;
            for (let o = -W; o <= W; o++) {
                const i = ((hint + o) % N + N) % N;
                const dx = this.pts[i].x - x, dz = this.pts[i].z - z;
                const d = dx * dx + dz * dz;
                if (d < bd) { bd = d; bi = i; }
            }
        }
        const p = this.pts[bi], l = this.leftV[bi];
        const lat = (x - p.x) * l.x + (z - p.z) * l.z;
        const al = Math.abs(lat);
        const s = this._scratch;
        s.idx = bi;
        s.latOff = lat;
        s.ang = this.ang[bi];
        s.distSq = bd;
        s.surf = al > this.halfW + 1.42 ? 'grass'
            : al > this.halfW - 0.35 ? 'curb' : 'road';
        return s;
    }

    aheadIdx(idx, meters) {
        const n = Math.round(meters / (this.length / this.N));
        return (((idx + n) % this.N) + this.N) % this.N;
    }

    // 发车位：startIdx 后方两列错开
    gridPose(slot) {
        const backD = 7 + slot * 5;
        const bi = this.aheadIdx(this.startIdx, -backD);
        const side = slot % 2 === 0 ? -1 : 1;
        const p = this.pts[bi], l = this.leftV[bi];
        const pos = new THREE.Vector3(
            p.x + l.x * 2.9 * side, 0, p.z + l.z * 2.9 * side
        );
        return { pos, heading: this.ang[bi], idx: bi };
    }
}
