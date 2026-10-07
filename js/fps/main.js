/* =====================================================================
   js/fps/main.js —— FPS 总装配与主循环（【集成】组）
   装配链：Environment/BattleMap（场景组）→ Player/EnemyManager/
   TargetRange/CombatWorld（玩家AI组）→ GunView/GunAudio（枪械组）→
   HUD/LootManager/Backpack（战利品组）→ Mission/RangeMode（HUD 任务组）→
   Stash/Lobby（大厅组）。
   已消化的跨组接口空隙与本轮烽火地带接线（详见各构建者 deviations）：
   · 枪械命中无伤害出口 → gunview.applyDamage 桥到 combat.applyHit，
     并把 {killed,head} 回喂 hud.hitmarker；
   · ADS/换弹影响移速 → player.setMoveStateProvider 读枪械状态；
   · 敌弹伤玩家 → enemies.setPlayer(player)（走 player.takeDamage）；
   · 主相机 fov 由 GunView 随 ADS 驱动（FOV=baseFov/zoom），本文件不再改 fov；
   · 入口流转：冷启动直达大厅（state.mode='lobby'）→ 出发 onDeploy /
     G 靶场 onRange；hud 主菜单退役为对局内暂停/重开面板（Esc 两段），
     Digit3=放弃行动（hud 菜单分支实证不认 Digit3，由本文件监听）；
   · 搜刮链：LootManager/Backpack 注入 Mission，驱动唯一入口 =
     mission.update 每帧 loot.update(dt,eyePos,fHeld)——本文件不绑
     loot.onLooted / backpack.onFull（mission._takeLoot 单点出 toast）；
   · 多枪：出发 gunview.setLoadout(主/副/瞄具)，对局内 1/2 切枪 →
     onSwitch → hud.setWeaponSlots。重开行动也经 setLoadout 重置双枪满弹
     ——不再用旧 resetAmmo(150)：枪械组 deviation③ 实证其排在 setLoadout
     之后会把非步枪主枪备弹虚标 150；
   · 结算：mission._end 一次给全结算页（main 不再 showResult），onEnd 只做
     经济入账：win → depositItems+情报奖金+recordRaid；败/放弃 → 仅 recordRaid；
   · 靶馆氛围：靶场=全封闭室内靶馆（rangeHall.js 建馆，zones.rangeLanes 指入
     馆内）。进出模式经 setRangeAtmosphere 统一切换：env.setIndoor（太阳/
     天光/雾/环境反射/曝光）+ rangeHall.setActive（馆内点光）+ vm 灯换顶灯；
     出发/回大厅整组还原，行动模式数值与几何零改动；
   · 敌兵首部署在装配期 spawnPatrol(zones.patrol)：enemies.resetAll 只重铺
     「最近一次非空部署」（enemies.js _deployRoutes），装配期不铺则首局
     mission.restart→resetAll 是空操作——首局满编敌兵由此保证。
   ===================================================================== */
import * as THREE from 'three';
import { Environment, SUN_DIR, INDOOR_KEY_DIR } from './env.js';
import { loadProps, BattleMap } from './layout.js';
import { RangeHall } from './rangeHall.js';
import { Player } from './player.js';
import { EnemyManager } from './enemies.js';
import { TargetRange } from './targets.js';
import { CombatWorld } from './combat.js';
import { GunView } from './gunview.js';
import { GunAudio } from './gunAudio.js';
import { HUD } from './hud.js';
import { Mission } from './mission.js';
import { RangeMode } from './rangeMode.js';
import { LootManager, rollLoot } from './loot.js';
import { Backpack } from './backpack.js';
import { Stash } from './stash.js';
import { Lobby } from './lobby.js';
import { gunById } from './gunsData.js';

/* ==== 1. 渲染器 / 场景 / 相机（照 js/main.js 先例） ==== */
const canvas = document.getElementById('gameCanvas');
const renderer = new THREE.WebGLRenderer({
    canvas, antialias: true, powerPreference: 'high-performance',
});
/* 性能自适应分辨率：Retina dpr=2 全速渲染 = 4× 像素量（低帧首因）。上限压到 1.5×
 * （AA 仍在，观感几乎无损）；帧率不足时调速器再逐步降到 1.0×，富余则回升（见 perfTick） */
const PERF = {
    cap: Math.min(window.devicePixelRatio || 1, 1.5),
    min: 1.0,
    cur: Math.min(window.devicePixelRatio || 1, 1.5),
    acc: 0, n: 0, last: 0, goodMs: 0,
};
renderer.setPixelRatio(PERF.cur);

/* 帧率角标：右上角小字实时显示 fps 与当前渲染档（优化效果用户可直读） */
const fpsBadge = document.createElement('div');
fpsBadge.style.cssText = 'position:fixed;right:10px;top:8px;z-index:95;font:11px/1.5 Menlo,Consolas,monospace;' +
    'letter-spacing:.08em;color:rgba(216,222,210,.7);background:rgba(8,11,9,.4);' +
    'padding:2px 9px;border-radius:5px;pointer-events:none;white-space:pre';
fpsBadge.textContent = '测速中…';
document.body.appendChild(fpsBadge);

/* 每 ~1.5s 评估一次平均帧时长：<45fps 降 0.25 档（至 1.0），>57fps 持续 4s 才升一档（防抖动） */
function perfTick(now) {
    if (!PERF.last) { PERF.last = now; return; }
    const dt = Math.min(100, now - PERF.last);   // 切标签页的时间大跳不毒化统计
    PERF.last = now; PERF.acc += dt; PERF.n++;
    if (PERF.acc < 1500) return;
    const fps = 1000 / (PERF.acc / PERF.n);
    if (fps < 45 && PERF.cur > PERF.min) {
        PERF.cur = Math.max(PERF.min, PERF.cur - 0.25);
        renderer.setPixelRatio(PERF.cur);
        PERF.goodMs = 0;
    } else if (fps > 57 && PERF.cur < PERF.cap) {
        PERF.goodMs += PERF.acc;
        if (PERF.goodMs >= 4000) {
            PERF.cur = Math.min(PERF.cap, PERF.cur + 0.25);
            renderer.setPixelRatio(PERF.cur);
            PERF.goodMs = 0;
        }
    } else {
        PERF.goodMs = Math.max(0, PERF.goodMs - PERF.acc);
    }
    fpsBadge.textContent = `${Math.round(fps)} FPS · 渲染 ${PERF.cur.toFixed(2)}×`;
    PERF.acc = 0; PERF.n = 0;
}
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.02;

const scene = new THREE.Scene();
/* 主相机基线 fov 75：GunView 构造时快照并按瞄具倍率驱动（FOV=75/zoom），这里只定一次 */
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
const zones = battleMap.zones;           // playerSpawn/patrol/intelPos/extractPos×2/danger/containerSpots/rangeLanes×3

/* 全封闭室内靶馆（独立建筑，馆心 (120,130)：静态壳体+射击位+灯板，常驻场景；
 * 碰撞/馆内地坪注册进同一 CollisionWorld，行动玩家进不去、也无感） */
const rangeHall = new RangeHall(scene, collision, props);
rangeHall.build();

/* ==== 3. 模块实例 ==== */
const gunAudio = new GunAudio();
const hud = new HUD(camera);
const gunview = new GunView({
    scene, camera, audio: gunAudio,
    ground: (x, z) => collision.groundHeight(x, z),   // 抛壳/掉落弹匣贴地用
});
/* 枪身 IBL：复用主场景黄昏 PMREM 环境贴图，vm 主灯对齐太阳方向（写实度评审 #1）
 * ——金属材质(metalness 0.85~1)由此反射天光，不再死黑 */
gunview.setEnvironment(scene.environment, SUN_DIR);
const player = new Player({ camera, collision });
const enemies = new EnemyManager({ scene, collision, audio: gunAudio });
const targets = new TargetRange({ scene });           // 音效由 RangeMode 的 UIAudio 叮/闷响承担，不重复注入
targets.buildLanes(zones.rangeLanes);

/* 战利品组：局内背包（纯数据）+ 容器世界（52 锚点自 layout.CONTAINER_SPOTS；
 * 碰撞/贴地经 collision 同源注入，loot 构造内部鸭子接 groundHeight） */
const backpack = new Backpack(12);
const loot = new LootManager({ scene, collision, spots: zones.containerSpots });

const combat = new CombatWorld();
combat.setWalls(collision);      // 墙体遮挡聚合进 raycast
combat.addProvider(enemies);     // damageStyle 'head'（爆头×2 在 EnemyManager.damage 内乘）
combat.addProvider(targets);     // damageStyle 'hit'

/* 敌兵首部署（装配期一次）：resetAll 只重铺最近一次非空部署，不铺则首局无敌 */
enemies.spawnPatrol(zones.patrol);

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

/* -- 武器槽 HUD ← 切枪/装配完成回调（霰弹 6 弹丸聚合等枪内事务不经此） --
 * 槽位名读 stash.loadout（出发后对局内不变）；HUD 弹药数字由
 * mission/rangeMode 每帧读 g.ammo/g.reserve 自动随枪，无需在此刷。 */
gunview.onSwitch = (slot) => {
    hud.setWeaponSlots({
        primary: (gunById(stash.loadout.primary) || {}).name || stash.loadout.primary,
        secondary: (gunById(stash.loadout.secondary) || {}).name || stash.loadout.secondary,
        active: slot,
    });
};

/* ==== 5. 模式状态机：lobby（默认起点）/ mission / range ==== */
const state = { mode: 'lobby', paused: false };
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

/* 出发载荷 = 大厅当前配置快照（对局内 stash 只读，重启行动沿用携带） */
function currentLoadoutPayload() {
    return {
        primary: stash.loadout.primary,
        secondary: stash.loadout.secondary,
        scopes: { ...(stash.guns.scopes || {}) },
    };
}

/* 室内/室外氛围总开关：靶馆进场 true，出发/回大厅 false。
 * 主场景灯光/雾/环境反射（env.setIndoor）+ 馆内点光（rangeHall.setActive）
 * + vm 主灯（顶灯 vs 太阳）三处一起切，保证「进馆即换氛围、出馆整组还原」 */
function setRangeAtmosphere(on) {
    env.setIndoor(on);
    rangeHall.setActive(on);
    gunview.setEnvironment(on ? env.indoorEnv : env.duskEnv,
        on ? INDOOR_KEY_DIR : SUN_DIR);
}

/* 出发/重开行动：装配双枪（满匣 + mag×5 备弹各自保账）→ 行动状态机启动。
 * 大厅 onDeploy 已先行 hide()（释放 uiBlocked/显示层）再回调本函数。 */
function deploy() {
    stash.raidActive = true;                   // 对局中禁写档（Stash 纪律）
    setRangeAtmosphere(false);                 // 若从靶场菜单转出发：先还原室外氛围
    hud.hideResult();
    hud.hideRangeStats();
    hud.hideMenu();
    gunview.setLoadout(currentLoadoutPayload());   // 顺带经 onSwitch 刷武器槽 HUD
    if (!mission) {
        mission = new Mission({
            hud, player, enemies, zones, gunview, audio: gunAudio,
            loot, backpack,
            onEnd: handleMissionEnd,
        });
    } else {
        mission.restart();                     // 内部 resetAll 复活敌兵 + loot/backpack 复位
    }
    state.mode = 'mission';
    state.paused = false;
}

/* 对局结束（撤离/阵亡/放弃）：经济入账，结算页已由 mission._end 一次给全
 *（大厅组 deviation③：main 在此不得再调 hud.showResult，会重复响铃） */
function handleMissionEnd({ win, stats, items, intelBonus }) {
    if (document.pointerLockElement) document.exitPointerLock();
    hud.hideMenu();                            // 放弃行动路径：菜单与结算不同屏
    const kills = stats ? stats.kills : 0;
    if (win) {
        const n = stash.depositItems(items || []);
        if (intelBonus > 0) stash.cash += intelBonus;   // recordRaid 内 save() 一并落盘
        stash.recordRaid({ win: true, kills });
        console.info(`[集成] 撤离：入库 ${n} 件 · 情报奖金 ₵${intelBonus || 0}`);
    } else {
        stash.recordRaid({ win: false, kills });        // 携带全丢；入库资产无损
    }
}

/* 大厅 G / 暂停菜单 2 → 靶场：清场敌兵（部署记录保留，回行动满编复活），
 * 切室内氛围（关太阳/天光、雾改冷灰、馆内点光点亮、vm 顶灯），
 * 按大厅配置装配（改枪台瞄具在靶场同样生效），备弹由 rangeMode 回满 120 */
function startRange() {
    hud.hideResult();
    hud.hideMenu();
    hud.showMarker(null);
    setRangeAtmosphere(true);                  // 进馆：全封闭室内氛围
    enemies.spawnPatrol([]);                   // 空路线 = 清空全部敌兵（靶场无交战）
    gunview.setLoadout(currentLoadoutPayload());
    if (!rangeMode) rangeMode = new RangeMode({ hud, targets, gunview });
    rangeMode.start();                         // 备弹回满 120 + 靶场 HUD 文案
    /* 玩家站中间射位后退一步半，面向 +X 靶道（lane.origin 已是馆内地坪高） */
    const lane = zones.rangeLanes[1] || zones.rangeLanes[0];
    player.respawn(lane.origin.clone().addScaledVector(lane.dir, -1.5));
    faceTo(lane.origin.clone().addScaledVector(lane.dir, 10));
    state.mode = 'range';
    state.paused = false;
}

/* 回大厅（结算页 回车/Esc；唯一大厅入口）：清对局 UI 残留 + 解写档禁令兜底 */
function toLobby() {
    state.mode = 'lobby';
    state.paused = false;
    setRangeAtmosphere(false);                 // 若从靶场回大厅：还原室外氛围
    hud.hideResult();
    hud.hideRangeStats();
    hud.hideMenu();
    hud.showMarker(null);
    hud.setExtractProgress(null);
    hud.setIntelProgress(null);
    hud.setDanger(false);
    hud.setVeil(0);
    stash.endRaid();                           // 异常路径兜底：解除写档禁令
    player.respawn(zones.playerSpawn);         // 背景机位回出生点（下次出发照常 respawn）
    faceTo(zones.intelPos);
    player.update(0);
    if (document.pointerLockElement) document.exitPointerLock();
    lobby.show();                              // 置 uiBlocked + display:flex
}

/* ==== 6. 模块回调装配 ==== */
hud.onSelectMission = () => deploy();          // 暂停菜单 1：重开行动（沿用携带）
hud.onSelectRange = () => startRange();        // 暂停菜单 2：重开靶场
hud.onRetry = () => {                          // 结算页 R：同图再战
    if (state.mode === 'range' && rangeMode) rangeMode.reset();
    else deploy();
};
hud.onBackToMenu = () => toLobby();            // 结算页 回车/Esc：回大厅
hud.onMuteToggle = (m) => gunAudio.setMuted(m);   // M 键由 HUD 监听并 toast

/* ==== 7. 大厅（默认起点）与开场机位 ==== */
const stash = new Stash();
const lobby = new Lobby({
    hud, stash,
    onDeploy: deploy,                          // 大厅内部已 hide() 再回调
    onRange: startRange,
});
player.pos.copy(zones.playerSpawn);
faceTo(zones.intelPos);
player.update(0);       // 相机就位（dt=0 无副作用）
gunview.update(0);      // viewmodel 姿态/相机宽高比同步
hud.setBag(backpack.items, backpack.capacity);
state.mode = 'lobby';
lobby.show();

/* ==== 8. 输入：开火 / 机瞄 / 换弹 / 切枪 / Esc 两段暂停 / Digit3 放弃 ==== */
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
    if (isPlaying()) {
        if (e.code === 'KeyQ') adsToggle = !adsToggle;      // Q 机瞄切换
        if (e.code === 'KeyR') gunview.startReload();       // R 换弹（靶场长按 R 重置归 RangeMode）
        if (e.code === 'Digit1' || e.code === 'Numpad1') gunview.switchSlot(0);   // 切主武器
        if (e.code === 'Digit2' || e.code === 'Numpad2') gunview.switchSlot(1);   // 切副武器
    }
    /* 暂停菜单 3 = 放弃行动（仅行动模式；hud 菜单分支实证不认 Digit3，
     * hud.js 键盘段只处理 Digit1/Digit2/Enter/箭头——监听归集成者） */
    if (e.code === 'Digit3' && hud.menuVisible
        && state.mode === 'mission' && mission) {
        mission.abort();                       // 视同阵亡结算（mission._end(false,{aborted:true})）
    }
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
    if (state.mode === 'lobby' || hud.resultVisible) return;    // 大厅/结算键各归其主
    if (hud.menuVisible && state.paused) {                      // 暂停中再按 Esc：恢复
        state.paused = false;
        hud.hideMenu();
        hud.toast('已恢复 —— 点击画面重新锁定鼠标');
        return;
    }
    if (hud.menuVisible) return;
    state.paused = true;                                        // 第二段：暂停
    hud.showMenu();
    hud.toast('已暂停 —— Esc 恢复 · 1 重开行动 · 2 重开靶场 · 3 放弃行动');
});

/* 暂停菜单「3 · 放弃行动」按钮（fps.html 静态节点；键盘路径在上面 Digit3） */
const btnAbort = document.getElementById('btnAbort');
if (btnAbort) {
    btnAbort.addEventListener('click', () => {
        if (hud.menuVisible && state.mode === 'mission' && mission) mission.abort();
    });
}

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

/* 窗口 resize：主相机改宽高比（fov 归 GunView 管），vmCamera 随 update 自同步；UI 缩放重算 */
window.addEventListener('resize', () => {
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    gunview.update(0);
    applyUiZoom();
});

/* ==== 9. 主循环：逻辑步进 + 双 pass 渲染（主场景 → 清深度 → viewmodel） ==== */
const clock = new THREE.Clock();
let uiW = window.innerWidth, uiH = window.innerHeight;
function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(clock.getDelta(), 0.05);
    /* 每帧核对视口尺寸：resize 事件/ResizeObserver 在部分环境不可靠（实测漏触发），
     * 两次属性读取的成本换缩放永远跟随窗口 */
    if (window.innerWidth !== uiW || window.innerHeight !== uiH) {
        uiW = window.innerWidth; uiH = window.innerHeight;
        applyUiZoom();
    }
    perfTick(typeof now === 'number' ? now : performance.now());
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
    /* 双 pass 渲染：viewmodel 只进 vmScene/vmCamera（枪械组约定）。
     * 大厅/结算盖场时背景只是 93% 遮罩下的氛围透出——降到 ~9fps 渲染，
     * 省下首屏大半 GPU；对局内每帧全速。 */
    if ((lobby && lobby.visible) || hud.resultVisible) {
        bgAcc += dt * 1000;
        if (bgAcc < 110) return;
        bgAcc = 0;
    } else {
        bgAcc = 0;
    }
    renderer.render(scene, camera);
    renderer.clearDepth();
    renderer.autoClear = false;
    renderer.render(gunview.vmScene, gunview.vmCamera);
    renderer.autoClear = true;
}

let bgAcc = 0;

/* ==== 10. 运行时错误屏显（js/main.js 同款；加载期错误由 fps.html 内联兜底） ==== */
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
    console.error('[FPS]', msg);   // 同步镜像到浏览器 console（CDP/实测员可见）
    errBox.style.display = 'block';
    errBox.textContent += `[${new Date().toLocaleTimeString()}] ${msg.slice(0, 500)}\n`;
}
window.addEventListener('error', (e) => reportErr(e.error || e.message));
window.addEventListener('unhandledrejection', (e) => reportErr(e.reason));

/* ==== 10.5 UI 缩放：DOM 界面全是固定 px，全屏/大屏上字太小——按窗口尺寸整体 zoom。
 * 基准 1280×760（小窗保持 1.0 不变），大屏线性放大，封顶 2.2；
 * 3D 画布分辨率归渲染器管不受影响，只放大界面层。
 * 世界标记（hud.showMarker）按真实屏幕像素定位，读 window.__uiZoom 做除法补偿。 ==== */
window.__uiZoom = 1;
function applyUiZoom() {
    const s = Math.min(2.2, Math.max(1, Math.min(window.innerWidth / 1280, window.innerHeight / 760)));
    window.__uiZoom = s;
    for (const id of ['hud-root', 'hud-menu-root', 'hud-result-root', 'hud-help-overlay', 'deployVeil', 'fps-lobby']) {
        const el = document.getElementById(id);
        if (el) el.style.zoom = String(s);
    }
    errBox.style.zoom = String(s);
    fpsBadge.style.zoom = String(s);
    return s;
}
applyUiZoom();
/* resize 事件之外兜一层 ResizeObserver：全屏切换/开发工具开合等不走 window resize
 * 的视口变化也能触发重算（观察 documentElement 尺寸即视口尺寸） */
if (typeof ResizeObserver !== 'undefined') {
    new ResizeObserver(applyUiZoom).observe(document.documentElement);
}

/* ==== 11. 调试句柄（extractFlow 契约） ==== */

/* __fps.tp('spawn'|'center'|'wild'|'extract') 或 __fps.tp(x, z)：瞬移（贴地+满血） */
function tp(a, b) {
    let x, z;
    if (typeof a === 'string') {
        let p = null;
        if (a === 'spawn') p = zones.playerSpawn;
        else if (a === 'center') p = { x: zones.danger.cx, z: zones.danger.cz };
        else if (a === 'wild') p = { x: -120, z: -120 };       // 荒野角（d>112，zoneAt='wild'）
        else if (a === 'extract') p = zones.extractPos[0];     // 主撤离点 (128,24)
        else if (a === 'range') p = zones.rangeLanes[1]        // 靶馆中间射位（室内地坪贴地）
            ? { x: zones.rangeLanes[1].origin.x - 1.5, z: zones.rangeLanes[1].origin.z } : null;
        if (!p) return false;
        x = p.x; z = p.z;
    } else if (typeof a === 'number' && typeof b === 'number') {
        x = a; z = b;
    } else {
        return false;
    }
    player.respawn(new THREE.Vector3(x, collision.groundHeight(x, z), z));
    player.update(0);
    return true;
}

/* __fps.give(rarityId, n=1)：直塞背包（战利品组 deviation① 的 forceRarity 通道），
 * 经 mission._takeLoot 走统一链（入包+背包 HUD+品质色 toast+满包提示） */
function give(rarityId, n = 1) {
    if (!mission || !backpack) return 0;
    let added = 0;
    const k = Math.max(1, n | 0);
    for (let i = 0; i < k; i++) {
        const before = backpack.items.length;
        mission._takeLoot(rollLoot('center', 'safe', rarityId));
        if (backpack.items.length > before) added++;
    }
    return added;
}

/* ==== 12. 收尾：撤加载遮罩、启动循环、调试句柄 ==== */
const veil = document.getElementById('loadingVeil');
if (veil) {
    veil.classList.add('done');
    veil.dataset.done = '1';
    setTimeout(() => veil.remove(), 900);
}
window.__fps = {
    renderer, scene, camera, player, enemies, targets, combat,
    gunview, gunAudio, hud, battleMap, state,
    stash, env, rangeHall,          // env.indoor / rangeHall.setActive：实测员断言「在靶馆」用
    /* __fps.loot：extractFlow 契约句柄 —— .containers() 可调用（战利品组 notes）。
     * 注意不能在实例上直接覆盖 containers（内部 _updateSearch/_cullTick 迭代该数组），
     * 故用闭包包一层的句柄对象；完整实例另挂 __fps.lootRef 供深度调试。 */
    loot: {
        spawnAt: (x, z, r) => loot.spawnAt(x, z, r),
        containers: () => loot.containers,
        isPrompting: () => loot.isPrompting(),
        resetAll: () => loot.resetAll(),
    },
    lootRef: loot,
    lobby, backpack,
    get mission() { return mission; },
    get rangeMode() { return rangeMode; },
    tp, give,
    raid: {
        end: (win) => { if (mission) mission._end(!!win); },   // 强制走完整结算路径
        abort: () => { if (mission) mission.abort(); },
    },
};
requestAnimationFrame(frame);
