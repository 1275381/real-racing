// 回归测试：倒车中按油门应先刹停再转前进（street-arcade 标准手感）
// 运行：node tools/testReverse.mjs
import { Vehicle } from '../js/physics.js';

// 沿 +X 方向的无限直道桩
const track = {
    N: 1000, length: 100000, startIdx: 0, halfW: 7, wallLat: 9.05,
    pts: Array.from({ length: 1000 }, (_, i) => ({ x: i * 100, z: 0, clone() { return { x: this.x, z: this.z }; } })),
    leftV: Array.from({ length: 1000 }, () => ({ x: 0, z: -1 })),
    ang: new Float32Array(1000).fill(Math.PI / 2),
    curv: new Float32Array(1000),
    _s: { idx: 0, latOff: 0, ang: Math.PI / 2, surf: 'road', distSq: 0 },
    query() { return this._s; },
};

const H = 1 / 120;
const v = new Vehicle(track, { isPlayer: true });
v.placeAt({ pos: { x: 100, y: 0, z: 0 }, heading: Math.PI / 2, idx: 100 });

// 阶段1：按住刹车(S) 2.5s → 应进入倒车
v.input.brake = 1;
for (let t = 0; t < 2.5; t += H) v.step(H);
const afterReverse = v.vf;
console.log(`倒车阶段结束 vf=${afterReverse.toFixed(2)} m/s （应为负）`);
if (afterReverse >= -1) { console.log('❌ 未能进入倒车'); process.exit(1); }

// 阶段2：松开刹车、按住油门(W) —— 修复点
v.input.brake = 0;
v.input.throttle = 1;
const minVfTrace = [];
let forwardOk = false, tToForward = null;
for (let t = 0; t < 5; t += H) {
    v.step(H);
    minVfTrace.push(v.vf);
    if (v.vf > 5 && tToForward == null) tToForward = t;
    if (v.vf > 10) { forwardOk = true; break; }
}
const minVf = Math.min(...minVfTrace);
console.log(`按油门后 vf 从 ${afterReverse.toFixed(2)} → ${v.vf.toFixed(2)} m/s，用时 ${tToForward?.toFixed(2) ?? '∞'}s`);

// 阶段3（回归）：前进中按刹车应快速减速（长按才会转入倒车，属设计行为）
v.input.throttle = 0; v.input.brake = 1;
const vBefore = v.vf;
for (let t = 0; t < 0.3; t += H) v.step(H);
console.log(`前进中刹车 0.3s：${vBefore.toFixed(1)} → ${v.vf.toFixed(2)} m/s （应明显减速）`);
const brakeOk = v.vf < vBefore - 5 && v.vf > 0;   // 0.3s 内应仍是正向减速中
for (let t = 0.3; t < 1.5; t += H) v.step(H);     // 继续长按 → 应转倒车
console.log(`继续长按至 1.5s：${v.vf.toFixed(2)} m/s （设计行为：自动转入倒车，应为负）`);
const reverseOk = v.vf < -1;

if (forwardOk && brakeOk && reverseOk) {
    console.log('✅ 通过：倒车中按油门先刹停再前进；前进刹车与长按倒车逻辑无回归');
} else {
    console.log(`❌ 失败 forwardOk=${forwardOk} brakeOk=${brakeOk} reverseOk=${reverseOk}`);
    process.exit(1);
}
