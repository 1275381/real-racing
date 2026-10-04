#!/usr/bin/env python3
"""【玩家AI】组静态+逻辑自测装配器（无 node/npm，用 macOS 自带 jsc 跑）。
把四个 ES Module 去 import/export 拼进一个经典脚本，配上 THREE/DOM 桩，
再附加断言，输出 /tmp/fps_harness.js 交给 jsc 执行。"""
import re, pathlib

ROOT = pathlib.Path('/Users/chen/Documents/赛场游戏')
OUT = pathlib.Path('/tmp/fps_harness.js')

STUB = r'''
/* ================= jsc 桩环境 ================= */
class V3 {
    constructor(x=0,y=0,z=0){ this.x=x; this.y=y; this.z=z; }
    set(x,y,z){ this.x=x; this.y=y; this.z=z; return this; }
    copy(v){ this.x=v.x; this.y=v.y; this.z=v.z; return this; }
    clone(){ return new V3(this.x,this.y,this.z); }
    add(v){ this.x+=v.x; this.y+=v.y; this.z+=v.z; return this; }
    addScaledVector(v,s){ this.x+=v.x*s; this.y+=v.y*s; this.z+=v.z*s; return this; }
    sub(v){ this.x-=v.x; this.y-=v.y; this.z-=v.z; return this; }
    multiplyScalar(s){ this.x*=s; this.y*=s; this.z*=s; return this; }
    dot(v){ return this.x*v.x+this.y*v.y+this.z*v.z; }
    length(){ return Math.sqrt(this.x*this.x+this.y*this.y+this.z*this.z); }
    normalize(){ const l=this.length()||1; return this.multiplyScalar(1/l); }
    distanceTo(v){ return this.clone().sub(v).length(); }
    distanceToSquared(v){ const dx=this.x-v.x,dy=this.y-v.y,dz=this.z-v.z; return dx*dx+dy*dy+dz*dz; }
    applyMatrix4(m){ return this; }            /* 恒等桩 */
    transformDirection(m){ return this.normalize(); }
}
class M4 { copy(m){ return this; } invert(){ return this; } }
class AnyNode {
    constructor(a, b){ this.children=[]; this.parent=null; this.visible=false;
        this.position=new V3(); this.rotation={x:0,y:0,z:0,order:'XYZ'};
        this.matrixWorld=new M4(); this.scale={setScalar(){},x:1,y:1,z:1};
        this.material=null; this.geometry=null; this.castShadow=false; this.frustumCulled=true;
        this.attributes={ position:{ setXYZ(){}, needsUpdate:false } };
        if (a !== undefined && a !== null) this.geometry = a;
        if (b !== undefined && b !== null) this.material = b; }
    add(...o){ for(const c of o){ c.parent=this; this.children.push(c);} return this; }
    remove(...o){ this.children=this.children.filter(c=>!o.includes(c)); }
    clone(){ const n=new AnyNode(); n.material=this.material; return n; }
    lookAt(){}
    updateWorldMatrix(){}
    setAttribute(){}
    dispose(){}
    traverse(fn){ fn(this); for(const c of this.children) if(c.traverse) c.traverse(fn); }
}
const THREE = {
    Vector3: V3, Matrix4: M4,
    MathUtils: { clamp:(v,a,b)=>Math.min(Math.max(v,a),b), lerp:(a,b,t)=>a+(b-a)*t,
                 degToRad:(d)=>d*Math.PI/180 },
    LineBasicMaterial: AnyNode, BufferGeometry: AnyNode, BufferAttribute: AnyNode,
    Line: AnyNode, Group: AnyNode, Mesh: AnyNode, PlaneGeometry: AnyNode,
    MeshBasicMaterial: AnyNode, PointLight: AnyNode, MeshStandardMaterial: AnyNode,
    CapsuleGeometry: AnyNode, SphereGeometry: AnyNode, BoxGeometry: AnyNode,
    CylinderGeometry: AnyNode, CanvasTexture: AnyNode, AnimationMixer: AnyNode,
    Euler: AnyNode, LoopOnce: 'LoopOnce', SRGBColorSpace: 'srgb',
    AdditiveBlending: 2, DoubleSide: 2, Object3D: AnyNode,
};
class GLTFLoader { constructor(){} load(url, ok, prog, err){ /* 不回调：node 保持 null */ } }
const __winListeners = [];
const window = { addEventListener(t,h){ __winListeners.push([t,h]); }, removeEventListener(){} };
const __docListeners = [];
const document = {
    pointerLockElement: null,
    addEventListener(t,h){ __docListeners.push([t,h]); },
    removeEventListener(){},
    createElement(){ return { width:0, height:0, getContext(){ return new Proxy({}, {
        get(t,k){ if(typeof t[k]!=='undefined') return t[k]; return ()=>{}; },
        set(t,k,v){ t[k]=v; return true; } }); } }; },
};
let __lsSet = [];
const localStorage = { getItem(){ return null; }, setItem(k,v){ __lsSet.push([k,v]); } };
const setTimeout = (fn,ms)=>0;
const clearTimeout = ()=>{};
'''

TESTS = r'''
/* ================= 断言 ================= */
let __pass = 0, __fail = 0;
function ok(cond, msg) {
    if (cond) { __pass++; print('  PASS ' + msg); }
    else { __fail++; print('  FAIL ' + msg); }
}
function section(t){ print('== ' + t + ' =='); }

/* ---------- CombatWorld ---------- */
section('CombatWorld 聚合与分发');
const combat = new CombatWorld();
const calls = [];
const fakeEnemy = {
    damageStyle: 'head',
    raycast(from, dir, maxD) {
        if (dir.z < 0) return { type: 'enemy', index: 2, point: new V3(0,1,0), dist: 5, _p: this };
        return null;
    },
    damage(i, dmg, head) { calls.push(['enemy', i, dmg, head]); return { killed: head }; },
};
const fakeTarget = {
    damageStyle: 'hit',
    raycast() { return null; },
    damage(i, dmg, hit) { calls.push(['target', i, dmg, hit && hit.ring]); return { killed: true, score: 100 }; },
};
combat.addProvider(fakeEnemy);
combat.addProvider(fakeTarget);
const walls = { rayWall(from, dir, maxD) { return dir.x > 0.9 ? 3 : Infinity; } };
combat.setWalls(walls);
let h = combat.raycast(new V3(0,0,0), new V3(0,0,-1), 100);
ok(h && h.type === 'enemy' && h.index === 2 && Math.abs(h.dist - 5) < 1e-9, '聚合取敌兵命中 dist=5');
ok(combat.raycast(new V3(0,0,0), new V3(1,0,0), 100).type === 'wall', '墙更近时吃掉命中 type=wall');
ok(combat.raycast(new V3(0,0,0), new V3(-1,0,0), 100) === null, '无命中返回 null');
let r = combat.applyHit({ type: 'enemy', index: 2, dist: 5, _p: fakeEnemy }, 20);
ok(r.killed === false && r.head === false && calls.length === 1 && calls[0][3] === false,
    'applyHit enemy 走 head 签名（head=false）');
h = { type: 'enemy_head', index: 2, dist: 5, ring: 9, _p: fakeEnemy };
r = combat.applyHit(h, 20);
ok(r.killed === true && r.head === true && calls[1][3] === true, 'enemy_head head=true killed 透传');
h._p = fakeTarget; h.type = 'target';
r = combat.applyHit(h, 20);
ok(r.killed === true && calls[2][0] === 'target' && calls[2][3] === 9, 'target 走 hit 签名（ring 透传）');
ok(combat.applyHit({ type: 'wall', index: -1, dist: 3, _p: null }, 5).killed === false, 'wall 无伤害分发');

/* ---------- Player ---------- */
section('Player 移动/碰撞/血量/回退视角');
const camEvents = [];
const cam = { rotation: { set(...a){ camEvents.push(a); }, order: '' }, position: { set(){} } };
const pcol = {
    pushOut(x, z, r) { return { x: Math.max(-2, Math.min(2, x)), z }; },  // 左右 ±2 模拟墙
    groundHeight() { return 0; },
};
let dmgLog = [], deathN = 0;
const player = new Player({ camera: cam, collision: pcol,
    onDamage: (d, f) => dmgLog.push([d, f]), onDeath: () => deathN++ });
ok(player.pos && player.health === 100 && player.dead === false, '初始状态');
player._keys['KeyW'] = true;
for (let i = 0; i < 60; i++) player.update(1/60);
ok(Math.abs(player.pos.z - (-4.8)) < 0.05, 'W 前进 1s ≈ 4.8m 朝 -Z，实测 z=' + player.pos.z.toFixed(3));
ok(Math.abs(player.pos.x) < 1e-6, '直线行走无横向漂移');
player._keys['ShiftLeft'] = true;
const z0 = player.pos.z;
for (let i = 0; i < 60; i++) player.update(1/60);
ok(Math.abs((z0 - player.pos.z) - 8.2) < 0.05, '疾跑 1s ≈ 8.2m，实测 ' + (z0 - player.pos.z).toFixed(3));
ok(player.sprinting === true, '疾跑状态位');
player._keys['ShiftLeft'] = false;
player.setMoveStateProvider(() => ({ ads: 1, reloading: false }));
const z1 = player.pos.z;
for (let i = 0; i < 60; i++) player.update(1/60);
ok(Math.abs((z1 - player.pos.z) - 2.6) < 0.05, 'ADS 移速 2.6，实测 ' + (z1 - player.pos.z).toFixed(3));
player.setMoveStateProvider(() => ({ ads: 0, reloading: true }));
const z2 = player.pos.z;
for (let i = 0; i < 60; i++) player.update(1/60);
ok(Math.abs((z2 - player.pos.z) - 4.8 * 0.85) < 0.05, '换弹移速 ×0.85，实测 ' + (z2 - player.pos.z).toFixed(3));
player.setMoveStateProvider(null);
player.crouch = true;
const z3 = player.pos.z;
for (let i = 0; i < 60; i++) player.update(1/60);
ok(Math.abs((z3 - player.pos.z) - 2.4) < 0.05, '蹲伏移速 2.4，实测 ' + (z3 - player.pos.z).toFixed(3));
ok(Math.abs(player._eyeH - 1.05) < 0.01, '蹲伏眼高收敛 1.05，实测 ' + player._eyeH.toFixed(3));
player.crouch = false;
player._keys['KeyW'] = false;
player._keys['Space'] = true;
player.update(1/60);
ok(player.pos.y > 0, '跳跃离地 v0=4.5');
player._keys['Space'] = false;
for (let i = 0; i < 120; i++) player.update(1/60);
ok(Math.abs(player.pos.y) < 1e-6 && player._onGround, '重力回落贴地 g=12');
/* 推出：横向走出 ±2 会被推回 */
player._keys['KeyD'] = true; player._keys['KeyW'] = false;
for (let i = 0; i < 120; i++) player.update(1/60);
ok(player.pos.x <= 2.5 + 1e-6, 'pushOut 限制横移（x=' + player.pos.x.toFixed(2) + '）');
player._keys['KeyD'] = false;
/* 键盘转向 */
player._keys['ArrowLeft'] = true;
player.update(0.5);
ok(Math.abs(player.yaw - THREE.MathUtils.degToRad(120) * 0.5) < 1e-6, '← 键偏航 120°/s');
player._keys['ArrowLeft'] = false;
/* 回退视角：绝对坐标 pointermove 增量 */
const cvListeners = {};
const canvasStub = { addEventListener(t, h){ (cvListeners[t] = cvListeners[t] || []).push(h); },
    removeEventListener(){}, requestPointerLock(){ throw new Error('no lock'); } };
player.attachLook(canvasStub, true);
ok(player.isFallbackLook === true, '?test=1 强制回退视角');
cvListeners['pointermove'][0]({ clientX: 100, clientY: 100 });
cvListeners['pointermove'][0]({ clientX: 150, clientY: 90 });
const wantYaw = THREE.MathUtils.degToRad(120) * 0.5 - 50 * 0.0023;
ok(Math.abs(player.yaw - wantYaw) < 1e-9, 'pointermove 增量转向 dx=50 → yaw-0.115');
ok(Math.abs(player.pitch - 10 * 0.0023) < 1e-9, 'dy=-10（上移）→ pitch+0.023');
/* 血量/死亡 */
player.takeDamage(40, new V3(1, 0, 0));
player.takeDamage(40, new V3(1, 0, 0));
ok(player.health === 20 && dmgLog.length === 2 && deathN === 0, '两次受击 40→20，未死');
player.takeDamage(40, new V3(1, 0, 0));
ok(player.health === 0 && player.dead === true && deathN === 1, '致死触发 onDeath 一次');
const dz = player.pos.z;
player._keys['KeyW'] = true;
player.update(1/60);
ok(Math.abs(player.pos.z - dz) < 1e-9, '死亡后不再移动');
player.respawn(new V3(3, 0, 4));
ok(player.health === 100 && player.dead === false && player.pos.x === 3 && player.pos.z === 4, 'respawn 重置');
/* 世界边界（无碰撞注入，避开 pushOut 桩的 ±2 夹紧） */
const p2 = new Player({ camera: cam });
p2.pos.x = 100; p2.pos.z = -100;
p2.update(1/60);
ok(p2.pos.x === 58 && p2.pos.z === -58, '边界夹紧 ±58');
ok(typeof player.eyePos() === 'object' && player.eyePos().y > player.pos.y, 'eyePos 在脚底上方');
const fd = player.footDir();
ok(Math.abs(fd.x - (-Math.sin(player.yaw))) < 1e-9 && Math.abs(fd.z - (-Math.cos(player.yaw))) < 1e-9, 'footDir yaw=0 面向 -Z');

/* ---------- EnemyManager（绕过构造器重资源，直测几何/AI 内核） ---------- */
section('EnemyManager 命中球/伤害/AI');
const escene = { add(){}, remove(){} };
const em = new EnemyManager({ scene: escene, collision: null, audio: null });
ok(em.enemies.length === 0, '构造完成（fx 池初始化不炸）');
/* 手工摆 3 个敌兵（模拟 spawnPatrol 数据结构，GLB 不回调 → node=null） */
em.spawnPatrol([[new V3(0,0,0), new V3(5,0,0)], [new V3(-10,0,2), new V3(-10,0,-6), new V3(-2,0,-6)], [new V3(8,0,8)]]);
ok(em.enemies.length === 8, 'spawnPatrol 3 路线共 8 人');
ok(em.enemies.every(e => e.state === 'patrol' && e.hp === 70), '初始巡逻态 hp70');
const e0 = em.enemies[0];
/* 命中球：胸心 y=1.26 r=0.6 / 头心 y=1.98 r=0.24（S=1.2） */
let hit = em.raycast(new V3(0, 1.26, 5), new V3(0, 0, -1), 100);
ok(hit && hit.type === 'enemy' && hit.index === 0 && Math.abs(hit.dist - 5) < 0.2, '胸口高度命中 enemy dist≈5');
hit = em.raycast(new V3(0, 1.98, 5), new V3(0, 0, -1), 100);
ok(hit && hit.type === 'enemy_head' && hit.index === 0, '头部高度命中 enemy_head（头球优先）');
hit = em.raycast(new V3(0, 0.2, 5), new V3(0, 0, -1), 100);
ok(hit === null, '脚部高度不判定');
hit = em.raycast(new V3(0, 1.26, 5), new V3(0, 0, -1), 3);
ok(hit === null, '超出 maxD 不判定');
/* 伤害：爆头 ×2（内部乘）、硬直、死亡播报 */
let dr = em.damage(0, 20, false);
ok(dr.killed === false && e0.hp === 50 && e0.staggerT > 0, '身体 20 伤害 → hp50 + 硬直');
dr = em.damage(0, 20, true);
ok(dr.killed === false && e0.hp === 10, '爆头 20×2=40 → hp10');
let killLog = [];
em.onKill = (name, dist, head) => killLog.push([name, dist, head]);
dr = em.damage(0, 10, false);
ok(dr.killed === true && e0.state === 'dead' && killLog.length === 1 && killLog[0][2] === false,
    '致死 → dead + onKill(name,dist,head)');
ok(em.raycast(new V3(0, 1.26, 5), new V3(0, 0, -1), 100) === null
    || em.raycast(new V3(0, 1.26, 5), new V3(0, 0, -1), 100).index !== 0,
    '尸体不再吃弹（同点位 3 号敌兵可被打，但 0 号不吃）');
/* 受击警戒：远处巡逻敌被打 → 进 search */
const e1 = em.enemies[1];
em._playerEye.set(0, 1.6, 5); em._hasPlayerEye = true;
em.damage(1, 10, false);
ok(e1.state === 'search' || e1.state === 'combat', '受击立即警戒（state=' + e1.state + '）');
/* AI 定步：巡逻沿路线走 */
const em2 = new EnemyManager({ scene: escene, collision: null, audio: null });
em2.spawnPatrol([[new V3(0,0,0), new V3(10,0,0)]]);
const p0 = em2.enemies[0];
for (let i = 0; i < 240; i++) em2.update(1/60, new V3(0, 1.6, 40));  // 玩家在 40m 外视距内但 LOS 恒通
/* 无碰撞 → LOS 恒 true；40m < 60m 视距 → 只要朝向对就会发现，朝向不对则继续走 */
ok(p0.pos.distanceTo(new V3(0,0,0)) > 1 || p0.state !== 'patrol', '巡逻在动或已发现玩家');
/* 敌兵开火：Math.random 固定 0.5 → 无 jitter 必命中胶囊 */
const rnd = Math.random;
Math.random = function(){ return 0.5; };
const em3 = new EnemyManager({ scene: escene, collision: null, audio: null });
em3.spawnPatrol([[new V3(0,0,0), new V3(1,0,0)]]);
const e3 = em3.enemies[0];
let pHit = [];
const pStub = { pos: new V3(0, 0, 6), dead: false, takeDamage(d, f){ pHit.push([d, f]); } };
em3.setPlayer(pStub);
em3._playerEye.set(0, 1.58, 6); em3._hasPlayerEye = true;
e3.state = 'combat'; e3.losOk = true; e3.engaged = true; e3.staggerT = 0;
em3.update(1/60, new V3(0, 1.58, 6));
for (let i = 0; i < 40; i++) em3.update(1/60, new V3(0, 1.58, 6));   // 过 0.25s 随机开火冷却
ok(pHit.length >= 1, '交火敌兵开火命中玩家（jitter=0，实测 ' + pHit.length + ' 发）');
ok(pHit.length >= 1 && pHit[0][0] >= 5 && pHit[0][0] <= 8, '伤害 5–8（实测 ' + (pHit[0] ? pHit[0][0].toFixed(2) : '-') + '）');
ok(e3.mag === 30 - pHit.length, '每发耗弹（mag=' + e3.mag + '，命中=' + pHit.length + '）');
Math.random = rnd;
/* onPlayerSpotted 只在入战时触发一次 */
let spotN = 0;
const em4 = new EnemyManager({ scene: escene, collision: null, audio: null });
em4.spawnPatrol([[new V3(0,0,0), new V3(1,0,0)]]);
em4.onPlayerSpotted = () => spotN++;
const e4 = em4.enemies[0];
e4.yaw = 0;  // 面朝 +Z，玩家在 +Z 方向
for (let i = 0; i < 90; i++) em4.update(1/60, new V3(0, 1.6, 20));
ok(spotN === 1, 'FOV 内发现 → suspicious→combat，onPlayerSpotted 恰好 1 次（实测 ' + spotN + '）');
ok(e4.state === 'combat', '视距 20m 且视锥内 → combat');
/* alertAll：全员 search + ×1.2 */
em4.alertAll(new V3(1, 0, 1));
ok(em4.alertMul === 1.2 && em4.enemies.every(e => e.state === 'search'), 'alertAll 全员 search + 移速×1.2');

/* ---------- TargetRange ---------- */
section('TargetRange 环靶/计分/复位');
const tscene = { add(){}, remove(){} };
let tr = new TargetRange({ scene: tscene });
ok(tr.score === 0 && tr.best === 0, '初始计分');
tr.buildLanes([
    { origin: new V3(0, 0, 0), dir: new V3(0, 0, -1) },
    { origin: new V3(6, 0, 0), dir: new V3(0, 0, -1) },
    { origin: new V3(-6, 0, 0), dir: new V3(0, 0, -1) },
]);
const fixed = tr.targets.filter(t => !t.swinger).length;
const swing = tr.targets.filter(t => t.swinger).length;
ok(tr.targets.length === 12 && fixed === 8 && swing === 4, '固定 8 + 摆动 4 = 12');
ok([1.2, 1.6, 2.0, 2.4].every(p => tr.targets.some(t => t.period === p)), '摆动周期 1.2/1.6/2.0/2.4 各异');
/* 射击：从 (0, y, 3) 朝 -Z 打第 0 号靶（世界=面本地，恒等矩阵） */
let th = tr.raycast(new V3(0, -0.094, 3), new V3(0, 0, -1), 50);
ok(th && th.type === 'target' && th.ring === 10, '瞄环心 → ring 10（实测 ' + (th && th.ring) + '）');
th = tr.raycast(new V3(0, 0, 3), new V3(0, 0, -1), 50);
ok(th && th.ring === 9, '面中心 → ring 9（环心下移 0.094）');
ok(tr.raycast(new V3(0.4, 0, 3), new V3(0, 0, -1), 50) === null, '板外脱靶');
let tHit = [];
tr.onHit = (i, ring) => tHit.push([i, ring]);
let tRes = tr.damage(th.index, 20, th);
ok(tRes.killed === true && tRes.score === 100 && tr.score === 100 && tHit[0][1] === 9,
    '9 环=100 分入账（10/9=100）');
__lsSet = [];
for (let i = 0; i < 20; i++) tr.update(1/60);   // 倒靶动画走完 fallK→1
th = tr.raycast(new V3(0, -0.094, 3), new V3(0, 0, -1), 50);
ok(th === null || th.index !== 0, '倒下的 0 号靶不再判定');
ok(th && th.ring === 10 && th.index !== 0, '邻靶仍立，瞄环心 → ring 10');
tr.damage(th.index, 20, th);
ok(tr.score === 200 && tr.best === 200 && __lsSet.length >= 1 && __lsSet[0][0] === 'fps_range_best',
    '累计 200 分并写 localStorage fps_range_best');
/* 固定靶 0.9s 自动立起；摆动靶不自动复位 */
const fx = tr.targets.find(t => !t.swinger);
const sw = tr.targets.find(t => t.swinger);
fx.alive = false; fx.downT = 0;
sw.alive = false; sw.downT = 0;
tr.update(1.4);
tr.update(0.3);
ok(fx.alive === true, '固定靶 ~1.4s 后自动立起');
tr.update(5);
ok(sw.alive === false, '摆动靶倒下不自动复位');
/* 摆动正弦：±30° */
const sw2 = tr.targets.find(t => t.swinger && t.alive);
let sawMax = 0;
for (let i = 0; i < 300; i++) { tr.update(1/60); sawMax = Math.max(sawMax, Math.abs(sw2.board.rotation.z)); }
ok(Math.abs(sawMax - THREE.MathUtils.degToRad(30)) < 0.01,
    '摆动幅度 ≈±30°（实测 ' + sawMax.toFixed(3) + ' rad）');
tr.reset();
ok(tr.score === 0 && tr.best === 200 && tr.targets.every(t => t.alive && t.board.rotation.x === 0),
    'reset 清分不清最佳，全部立起');

/* ---------- 汇总 ---------- */
print('========================');
print('PASS=' + __pass + ' FAIL=' + __fail);
if (__fail > 0) throw new Error('HAS FAILURES');
'''

def transform(path):
    src = path.read_text(encoding='utf-8')
    src = re.sub(r"^import .*?;$", "", src, flags=re.M)
    src = re.sub(r"\bexport class\b", "class", src)
    return src

parts = [STUB]
for name in ['player', 'enemies', 'targets', 'combat']:
    p = ROOT / 'js' / 'fps' / f'{name}.js'
    parts.append(f'\n/* ================= 模块源码：js/fps/{name}.js ================= */\n')
    parts.append(transform(p))
parts.append(TESTS)
OUT.write_text('\n'.join(parts), encoding='utf-8')
print(f'wrote {OUT} ({OUT.stat().st_size} bytes)')
