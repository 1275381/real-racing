// 复现 track.js 的核心数学，诊断发车格为何偏离路面
import { CatmullRomCurve3, Vector3 } from '../lib/three.module.js';
import { CONTROL_POINTS } from '../js/trackConfig.js';

const UP = new THREE_Vector(0, 1, 0);
function THREE_Vector(x, y, z) { return new Vector3(x, y, z); }

const cps = CONTROL_POINTS.map(([x, z]) => new Vector3(x, 0, z));
const curve = new CatmullRomCurve3(cps, true, 'catmullrom', 0.55);
const length = curve.getLength();
const N = Math.max(700, Math.round(length / 1.3));
const pts = [], tang = [], leftV = [];
const ang = new Float32Array(N), curv = new Float32Array(N);
for (let i = 0; i < N; i++) {
    const u = i / N;
    pts.push(curve.getPointAt(u));
    const t = curve.getTangentAt(u); t.y = 0; t.normalize();
    tang.push(t);
    leftV.push(new Vector3().crossVectors(UP, t).normalize());
    ang[i] = Math.atan2(t.x, t.z);
}
const rawK = new Float32Array(N);
for (let i = 0; i < N; i++) {
    const a = tang[i], b = tang[(i + 1) % N];
    rawK[i] = (a.z * b.x - a.x * b.z);
}
const W = 9;
for (let i = 0; i < N; i++) {
    let s = 0;
    for (let j = -W; j <= W; j++) s += rawK[(i + j + N) % N];
    curv[i] = s / (2 * W + 1);
}

// —— _findStartLine 原样复现 ——
const thr = 0.0055;
let bestLen = 0, bestStart = 0, run = 0, runStart = 0;
for (let i = 0; i < N * 2; i++) {
    const k = Math.abs(curv[i % N]);
    if (k < thr) {
        if (run === 0) runStart = i;
        run++;
        if (run > bestLen) { bestLen = run; bestStart = runStart; }
    } else run = 0;
}
const startIdx = (bestStart + Math.floor(bestLen * 0.42)) % N;
const straightBehind = Math.min(bestLen - Math.floor(bestLen * 0.42), 46);
console.log(`N=${N} bestLen=${bestLen} bestStart=${bestStart} startIdx=${startIdx} (${(startIdx / N * 100).toFixed(1)}%) straightBehind=${straightBehind}`);
console.log(`startPos = (${pts[startIdx].x.toFixed(1)}, ${pts[startIdx].z.toFixed(1)})  ang=${(ang[startIdx] * 180 / Math.PI).toFixed(1)}°`);

// —— gridPose 复现 ——
const halfW = 7;
function aheadIdx(idx, meters) {
    const n = Math.round(meters / (length / N));
    return (((idx + n) % N) + N) % N;
}
function gridPose(slot) {
    const backD = 7 + slot * 5;
    const bi = aheadIdx(startIdx, -backD);
    const side = slot % 2 === 0 ? -1 : 1;
    const p = pts[bi], l = leftV[bi];
    const pos = new Vector3(p.x + l.x * 2.9 * side, 0, p.z + l.z * 2.9 * side);
    return { pos, heading: ang[bi], idx: bi };
}
for (let slot = 0; slot < 4; slot++) {
    const gp = gridPose(slot);
    // 到最近中心线点的距离
    let bd = Infinity, bi = 0;
    for (let i = 0; i < N; i++) {
        const d = (pts[i].x - gp.pos.x) ** 2 + (pts[i].z - gp.pos.z) ** 2;
        if (d < bd) { bd = d; bi = i; }
    }
    const l = leftV[bi];
    const lat = (gp.pos.x - pts[bi].x) * l.x + (gp.pos.z - pts[bi].z) * l.z;
    console.log(`slot${slot}: pos=(${gp.pos.x.toFixed(1)},${gp.pos.z.toFixed(1)}) heading=${(gp.heading * 180 / Math.PI).toFixed(0)}° nearest=(${pts[bi].x.toFixed(1)},${pts[bi].z.toFixed(1)}) dist=${Math.sqrt(bd).toFixed(2)}m lat=${lat.toFixed(2)}m`);
}
