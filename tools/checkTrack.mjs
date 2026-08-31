// 校验全部赛道：总长、非相邻路段最小间距（防止路面重叠）
import { CatmullRomCurve3, Vector3 } from '../lib/three.module.js';
import { TRACKS } from '../js/trackConfig.js';

let allOk = true;
for (const def of TRACKS) {
    const cps = def.points.map(([x, z]) => new Vector3(x, 0, z));
    const curve = new CatmullRomCurve3(cps, true, 'catmullrom', 0.55);
    const len = curve.getLength();
    const N = Math.round(len / 1.0);
    const pts = [];
    for (let i = 0; i < N; i++) pts.push(curve.getPointAt(i / N));

    let worst = Infinity, wi = 0, wj = 0;
    for (let i = 0; i < N; i += 2) {
        for (let j = i + 100; j < N + i - 100; j += 2) {
            const jj = j % N;
            const d = Math.hypot(pts[i].x - pts[jj].x, pts[i].z - pts[jj].z);
            if (d < worst) { worst = d; wi = i; wj = jj; }
        }
    }
    const ok = worst > 23;
    allOk &&= ok;
    console.log(`${ok ? '✅' : '❌'} ${def.name}(${def.id}): ${len.toFixed(0)}m, 最小间距 ${worst.toFixed(1)}m @(${wi},${wj % N})`);
    if (!ok) console.log(`   冲突点 P=${pts[wi].x.toFixed(0)},${pts[wi].z.toFixed(0)} Q=${pts[wj % N].x.toFixed(0)},${pts[wj % N].z.toFixed(0)}`);
}
console.log(allOk ? '全部赛道布局安全' : '存在需要修正的赛道');
process.exit(allOk ? 0 : 1);
