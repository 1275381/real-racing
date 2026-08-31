// 数值验证每条赛道的起跑线检测与发车格（无需浏览器渲染）
import { CatmullRomCurve3, Vector3 } from '../lib/three.module.js';
import { TRACKS } from '../js/trackConfig.js';

const UP = new Vector3(0, 1, 0);
for (const def of TRACKS) {
    const cps = def.points.map(([x, z]) => new Vector3(x, 0, z));
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
    // _findStartLine 复现
    const thr = 0.0055;
    let bestLen = 0, bestStart = 0, run = 0, runStart = 0;
    for (let i = 0; i < N * 2; i++) {
        if (Math.abs(curv[i % N]) < thr) {
            if (run === 0) runStart = i;
            run++;
            if (run > bestLen) { bestLen = run; bestStart = runStart; }
        } else run = 0;
    }
    const startIdx = (bestStart + Math.floor(bestLen * 0.42)) % N;
    const behind = Math.min(bestLen - Math.floor(bestLen * 0.42), 46);
    const straightM = (bestLen * length / N).toFixed(0);
    // 发车格横向偏移检查
    const ds = length / N;
    const aheadIdx = (idx, m) => (((idx + Math.round(m / ds)) % N) + N) % N;
    let gridOk = true;
    for (let slot = 0; slot < 4; slot++) {
        const bi = aheadIdx(startIdx, -(7 + slot * 5));
        const lat = 2.9; // 由构造保证，检查的是“都在同一直段”即曲率小
        if (Math.abs(curv[bi]) > 0.006) gridOk = false;
    }
    console.log(`${gridOk && behind >= 20 ? '✅' : '⚠️'} ${def.name}: 总长${length.toFixed(0)}m N=${N} 起跑直段=${straightM}m 起跑线后余量=${(behind * ds).toFixed(0)}m startIdx=${startIdx}`);
}
