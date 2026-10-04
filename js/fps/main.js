/* =====================================================================
   js/fps/main.js —— FPS 总装配与主循环（【集成】组）
   装配链：Environment/BattleMap（场景组）→ Player/EnemyManager/
   TargetRange/CombatWorld（玩家AI组）→ GunView/GunAudio（枪械组）→
   HUD/Mission/RangeMode（HUD 任务组）。
   已消化的跨组接口空隙（详见各组 deviations）：
   · 枪械命中无伤害出口 → gunview.applyDamage 桥到 combat.applyHit，
     并把 {killed,head} 回喂 hud.hitmarker；
   · ADS/换弹影响移速 → player.setMoveStateProvider 读枪械状态；
   · 敌弹伤玩家 → enemies.setPlayer(player)（走 player.takeDamage）；
   · INTEL 警戒/重开复活敌兵 → mission.js 内 setAlert/resetAll 鸭子回退；
   · 主相机 fov 由 GunView 随 ADS 驱动（75→55），本文件不再改 fov。
   ===================================================================== */
import * as THREE from 'three';
import { Environment } from './env.js';
import { loadProps, BattleMap } from './layout.js';
import { Player } from './player.js';
import { EnemyManager } from './enemies.js';
import { TargetRange } from './targets.js';
import { CombatWorld } from './combat.js';
import { GunView } from './gunview.js';
import { GunAudio } from './gunAudio.js';
import { HUD } from './hud.js';
import { Mission } from './mission.js';
import { RangeMode } from './rangeMode.js';

/* ==== 1. 渲染器 / 场景 / 相机（照 js/main.js 先例） ==== */
const canvas = document.getElementById('gameCanvas');
const renderer = new THREE.WebGLRenderer({
    canvas, antialias: true, powerPreference: 'high-performance',
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.02;

const scene = new THREE.Scene();
/* 主相机基线 fov 75：GunView 构造时快照并在 ADS 时驱动到 55，这里只定一次 */
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.08, 900);

/* ==== 2. 世界装配（场景组接口：Environment → loadProps → BattleMap.build） ==== */
const env = new Environment(scene, renderer);
const props = await loadProps();
if (props.missing && props.missing.length) {
    console.warn('[集成] 以下道具 GLB 加载失败，已降级程序化盒体：', props.missing.join(', '));
}
const battleMap = new BattleMap(scene, props);
await battleMap.build();
const collision = battleMap.collision;   // CollisionWorld：pushOut/groundHeight/rayWall
const zones = battleMap.zones;           // playerSpawn/patrol×3/intelPos/extractPos/rangeLanes×3

/* ==== 3. 模块实例 ==== */
const gunAudio = new GunAudio();
const hud = new HUD(camera);
const gunview = new GunView({
    scene, camera, audio: gunAudio,
    ground: (x, z) => collision.groundHeight(x, z),   // 抛壳/掉落弹匣贴地用
});
const player = new Player({ camera, collision });
const enemies = new EnemyManager({ scene, collision, audio: gunAudio });
const targets = new TargetRange({ scene });           // 音效由 RangeMode 的 UIAudio 叮/闷响承担，不重复注入
targets.buildLanes(zones.rangeLanes);

const combat = new CombatWorld();
combat.setWalls(collision);      // 墙体遮挡聚合进 raycast
combat.addProvider(enemies);     // damageStyle 'head'（爆头×2 在 EnemyManager.damage 内乘）
combat.addProvider(targets);     // damageStyle 'hit'

/* ==== 4. 跨组接线 ==== */

/* -- 玩家 ← 枪械状态：ADS 移速 2.6 / 换弹 ×0.85 / 后坐姿态合成 -- */
player.setMoveStateProvider(() => ({ ads: gunview.adsAmount, reloading: gunview.reloading }));
player.setRecoilProvider(() => ({ pitch: gunview.recoilPitch, yaw: gunview.recoilYaw }));
player.attachLook(canvas, new URLSearchParams(location.search).get('test') === '1');
player.onFallbackLook = () => hud.toast('指针锁定不可用 —— 回退视角：鼠标滑过画面转向（?test=1 可强制）');

/* -- 受击方向指示：来向投影到玩家前/右基向量（右为正，rad） -- */
const _up = new THREE.Vector3(0, 1, 0);
const _f = new THREE.Vector3(), _r = new THREE.Vector3(), _d = new THREE.Vector3();
player.onDamage = (dmg, from) => {
    if (!from) { hud.damageFrom(null); return; }
    _f.copy(player.footDir());
    _r.crossVectors(_f, _up).normalize();          // 右向量（与 player 移动的 rgt 同源）
    _d.copy(from).sub(player.eyePos());
    hud.damageFrom(Math.atan2(_d.dot(_r), _d.dot(_f)));
};

/* -- 敌兵 ← 玩家引用（敌弹命中走 player.takeDamage → onDamage → 方向指示） -- */
enemies.setPlayer(player);

/* -- 枪械命中 → 伤害分发 → hitmarker（接口空隙桥，GunView.applyDamage 形态） -- */
gunview.setRaycast((from, dir, maxD) => combat.raycast(from, dir, maxD));
gunview.applyDamage = (hit, dmg) => {
    const res = combat.applyHit(hit, dmg);
    hud.hitmarker(!!res.killed, !!(res.head || (hit && hit.type === 'enemy_head')));
    return res;
};

/* ==== 5. 模式状态机：menu / mission / range ==== */
const state = { mode: 'menu', paused: false };
let mission = null;      // 惰性构造（Mission 构造即 restart 进 DEPLOY）
let rangeMode = null;

const isPlaying = () =>
    (state.mode === 'mission' || state.mode === 'range') && !state.paused
    && !hud.menuVisible && !hud.resultVisible;

/* 出生朝向目标点（yaw=0 面向 −Z，同 mission._orientTo） */
function faceTo(target) {
    const dx = target.x - player.pos.x, dz = target.z - player.pos.z;
    player.yaw = Math.atan2(-dx, -dz);
    player.pitch = 0;
}

function startMission() {
    hud.hideResult();
    hud.hideRangeStats();
    gunview.resetAmmo(150);                    // 新行动 = 满配 30+150（5 匣备弹）
    if (!mission) {
        mission = new Mission({
            hud, player, enemies, zones, gunview, audio: gunAudio,
            onEnd: () => { if (document.pointerLockElement) document.exitPointerLock(); },
        });
    } else {
        mission.restart();                     // 内部经 resetAll/spawnPatrol 回退复活全部敌兵
    }
    state.mode = 'mission';
    state.paused = false;
}

function startRange() {
    hud.hideResult();
    hud.showMarker(null);
    enemies.spawnPatrol([]);                   // 空路线 = 清空全部敌兵（靶场无交战）
    if (!rangeMode) rangeMode = new RangeMode({ hud, targets, gunview });
    rangeMode.start();                         // 备弹回满 120 + 靶场 HUD 文案
    /* 玩家站中间射位（x=−52）后退一步半，面向 +X 靶道 */
    const lane = zones.rangeLanes[1] || zones.rangeLanes[0];
    player.respawn(lane.origin.clone().addScaledVector(lane.dir, -1.5));
    faceTo(lane.origin.clone().addScaledVector(lane.dir, 10));
    state.mode = 'range';
    state.paused = false;
}

function toMenu() {
    state.mode = 'menu';
    state.paused = false;
    hud.hideResult();
    hud.hideRangeStats();
    hud.showMarker(null);
    hud.setExtractProgress(null);
    hud.setIntelProgress(null);
    hud.showMenu();
}

hud.onSelectMission = () => startMission();
hud.onSelectRange = () => startRange();
hud.onRetry = () => {
    hud.hideResult();
    if (state.mode === 'mission' && mission) {
        gunview.resetAmmo(150);
        mission.restart();
    } else if (state.mode === 'range' && rangeMode) {
        rangeMode.reset();
    }
};
hud.onBackToMenu = () => toMenu();
hud.onMuteToggle = (m) => gunAudio.setMuted(m);   // M 键由 HUD 监听并 toast

/* 菜单背景 = 出生点朝情报点的定机位 */
player.pos.copy(zones.playerSpawn);
faceTo(zones.intelPos);
player.update(0);       // 相机就位（dt=0 无副作用）
gunview.update(0);      // viewmodel 姿态/相机宽高比同步
hud.showMenu();

/* ==== 6. 输入：开火 / 机瞄 / 换弹 / Esc 两段暂停 ==== */
let fireHeld = false, adsHeld = false, adsToggle = false;
canvas.addEventListener('mousedown', (e) => {
    if (e.button === 0) fireHeld = true;
    else if (e.button === 2) adsHeld = true;
});
window.addEventListener('mouseup', (e) => {
    if (e.button === 0) fireHeld = false;
    else if (e.button === 2) adsHeld = false;
});
window.addEventListener('blur', () => { fireHeld = false; adsHeld = false; });
canvas.addEventListener('contextmenu', (e) => e.preventDefault());

window.addEventListener('keydown', (e) => {
    if (e.repeat) return;
    if (e.code === 'KeyQ' && isPlaying()) adsToggle = !adsToggle;      // Q 机瞄切换
    if (e.code === 'KeyR' && isPlaying()) gunview.startReload();       // R 换弹（靶场长按 R 重置归 RangeMode）
});

/* Esc 两段：锁定中按下由浏览器解锁（本下不暂停）；解锁后再按 → 暂停/恢复 */
let lockLostAt = -1e9;
document.addEventListener('pointerlockchange', () => {
    if (!document.pointerLockElement) lockLostAt = performance.now();
});
window.addEventListener('keydown', (e) => {
    if (e.code !== 'Escape') return;
    if (document.pointerLockElement) return;                    // 第一段：先解锁
    if (performance.now() - lockLostAt < 350) return;           // 刚解锁的这半秒内不触发
    if (state.mode === 'menu' || hud.resultVisible) return;     // 菜单/结算键归 HUD
    if (hud.menuVisible && state.paused) {                      // 暂停中再按 Esc：恢复
        state.paused = false;
        hud.hideMenu();
        hud.toast('已恢复 —— 点击画面重新锁定鼠标');
        return;
    }
    if (hud.menuVisible) return;
    state.paused = true;                                        // 第二段：暂停
    hud.showMenu();
    hud.toast('已暂停 —— Esc 恢复 · 1/2 重开对应模式');
});

/* 页面切走自动暂停 */
document.addEventListener('visibilitychange', () => {
    if (document.hidden && isPlaying()) {
        state.paused = true;
        hud.showMenu();
    }
});

/* 首次用户手势激活枪械音频（照 js/audio.js 先例；UIAudio 由 HUD 自带手势） */
const ensureGunAudio = () => gunAudio.ensure();
window.addEventListener('pointerdown', ensureGunAudio, { once: true });
window.addEventListener('keydown', ensureGunAudio, { once: true });

/* 窗口 resize：主相机改宽高比（fov 归 GunView 管），vmCamera 随 update 自同步 */
window.addEventListener('resize', () => {
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    gunview.update(0);
});

/* ==== 7. 主循环：逻辑步进 + 双 pass 渲染（主场景 → 清深度 → viewmodel） ==== */
const clock = new THREE.Clock();
function frame() {
    requestAnimationFrame(frame);
    const dt = Math.min(clock.getDelta(), 0.05);
    try {
        step(dt);
    } catch (err) {
        reportErr(err);
    }
}

function step(dt) {
    const playing = isPlaying();
    if (playing) {
        gunview.setAds(adsHeld || adsToggle);
        player.update(dt);                                       // 移动/碰撞/相机（含后坐合成）
        if (state.mode === 'mission' && mission) mission.update(dt);
        else if (state.mode === 'range' && rangeMode) rangeMode.update(dt);
        enemies.update(dt, player.eyePos());                     // 1/60 定步 AI + 敌弹
        targets.update(dt);                                      // 摆动/倒立靶动画
        gunview.update(dt);                                      // 持枪姿态/特效池/FOV 同步
        gunview.tryFire(fireHeld && !player.sprinting && !player.dead);   // 疾跑禁开火
    } else {
        gunview.update(0);                       // 冻结时间但保持姿态与相机宽高比同步
    }
    env.update(dt, player.pos);                  // 太阳阴影相机随玩家
    battleMap.update(dt);                        // 绿信号烟/信标闪/情报箱呼吸灯
    hud.compass(player.yaw);
    hud.setHealth(player.health);
    hud.update(dt);                              // 环境风/低血心跳（可选调用）
    /* 双 pass 渲染：viewmodel 只进 vmScene/vmCamera（枪械组约定） */
    renderer.render(scene, camera);
    renderer.clearDepth();
    renderer.autoClear = false;
    renderer.render(gunview.vmScene, gunview.vmCamera);
    renderer.autoClear = true;
}

/* ==== 8. 运行时错误屏显（js/main.js 同款；加载期错误由 fps.html 内联兜底） ==== */
const errBox = document.createElement('div');
errBox.style.cssText = 'position:fixed;left:8px;top:8px;z-index:99;background:rgba(160,20,20,.92);' +
    'color:#fff;font:12px/1.5 Menlo,monospace;padding:8px 12px;border-radius:8px;max-width:70vw;' +
    'white-space:pre-wrap;display:none';
document.body.appendChild(errBox);
const seenErrs = new Set();
function reportErr(e) {
    const msg = (e && (e.stack || e.message)) || String(e);
    const key = msg.split('\n')[0];
    if (seenErrs.has(key) || seenErrs.size > 3) return;
    seenErrs.add(key);
    errBox.style.display = 'block';
    errBox.textContent += `[${new Date().toLocaleTimeString()}] ${msg.slice(0, 500)}\n`;
}
window.addEventListener('error', (e) => reportErr(e.error || e.message));
window.addEventListener('unhandledrejection', (e) => reportErr(e.reason));

/* ==== 9. 收尾：撤加载遮罩、启动循环、调试句柄 ==== */
const veil = document.getElementById('loadingVeil');
if (veil) {
    veil.classList.add('done');
    veil.dataset.done = '1';
    setTimeout(() => veil.remove(), 900);
}
window.__fps = {
    renderer, scene, camera, player, enemies, targets, combat,
    gunview, gunAudio, hud, battleMap, state,
    get mission() { return mission; },
    get rangeMode() { return rangeMode; },
};
requestAnimationFrame(frame);
