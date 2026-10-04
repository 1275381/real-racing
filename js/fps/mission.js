/* ============================================================
 * js/fps/mission.js —— 行动模式闭环状态机（照 missionSpec + 烽火地带改造）
 * DEPLOY(2s 黑幕淡入+简报卡) → PATROL(搜刮容器 + 世界标记指引情报) →
 * INTEL(距情报箱<1.6m 按住 F 3s，松手暂停不重置；loot.isPrompting 守卫) →
 * EXTRACT_ENROUTE(取最近撤离点，标记信号烟) → EXTRACT_CHANNEL(圈内站立 5s) →
 * WIN；任意时刻玩家 health≤0 → LOSE；暂停菜单 3 → abort() 同 LOSE 结算。
 * 【搜刮链唯一入口】update 每帧调 this.loot.update(dt, eyePos, this._fHeld)；
 * F 键监听唯一持有者 = 本文件（mission.js:268 附近），loot 不自行监听键盘；
 * loot.onLooted 由本文件链式接管：backpack.add → hud.setBag → 品质色 toast。
 * onEnd 扩展：{ win, stats, items(背包快照), intelDone, intelBonus }。
 * ============================================================ */
import { rarInfo } from './stash.js';

const INTEL_RADIUS = 1.6;     // 进距：显示「按住 F 搜索」
const INTEL_LEAVE = 2.6;      // 出距（滞回）：太远回 PATROL，进度保留
const INTEL_TIME = 3.0;       // 按住 F 秒数
const EXTRACT_TIME = 5.0;     // 撤离圈内站立秒数
const SPOT_HINT_CD = 6.0;     // 「被发现」提示节流
const INTEL_BONUS = 50000;    // 情报完成撤离奖金（₵，rarityTable 约定）
const DANGER_TOAST_CD = 8000; // 危险区进出提示节流（ms）

export class Mission {
    // { hud, player, enemies, zones, gunview, audio, loot, backpack, onEnd }
    // 全部鸭子类型注入；loot/backpack 未传时搜索链静默降级（兼容旧 main 接线）
    constructor({ hud, player, enemies, zones, gunview, audio, loot, backpack, onEnd }) {
        this.hud = hud;
        this.player = player;
        this.enemies = enemies;
        this.zones = zones;
        this.gunview = gunview;
        this.audio = audio;
        this.loot = loot || null;
        this.backpack = backpack || null;
        this.onEnd = onEnd || null;

        this.stats = { kills: 0, accuracy: 0, timeSec: 0, rank: 'C' };
        this._t = 0;                  // 用时（DEPLOY 起累计）
        this._deployT = 0;
        this._intelT = 0;             // 情报进度（松手/走远保留）
        this._intelDoneFlag = false;  // 情报是否到手（撤离奖金判定）
        this._extractT = 0;
        this._extractTarget = null;   // 本局选定的撤离点（zones.extractPos 主/备取近）
        this._lastHealth = 100;
        this._nextSpotHint = 0;
        this._fHeld = false;
        this._inDanger = false;       // 高危战区在区态（hud.setDanger 开关）
        this._nextDangerToast = 0;    // 危险区 toast 节流

        this._chainEnemyCallbacks();
        this._chainLoot();
        this._bindKeys();
        this.restart();
    }

    restart() {
        this._t = 0; this._deployT = 0; this._intelT = 0; this._extractT = 0;
        this._snapShots = this._snapshotGun();
        this._kills = 0;
        this._lastHealth = 100;
        this._nextSpotHint = 0;
        this._intelDoneFlag = false;
        this._extractTarget = null;
        this._inDanger = false;
        this._nextDangerToast = 0;
        // 敌兵复活回巡逻态：优先 resetAll()；enemies.js 落盘版以
        // 「spawnPatrol 重复调用 = 全量重置」等价提供（集成者补的接线回退）
        if (this.enemies) {
            if (typeof this.enemies.resetAll === 'function') this.enemies.resetAll();
            else if (this.zones && Array.isArray(this.zones.patrol)
                && typeof this.enemies.spawnPatrol === 'function') {
                this.enemies.spawnPatrol(this.zones.patrol);
            }
        }
        // 搜刮链复位：容器全关 + 背包清空（一局一背包，撤离/阵亡后带回大厅结算）
        if (this.loot && typeof this.loot.resetAll === 'function') this.loot.resetAll();
        if (this.backpack && typeof this.backpack.clear === 'function') {
            this.backpack.clear();
            this.hud.setBag(this.backpack.items, this.backpack.capacity || 12);
        }
        this.hud.setDanger(false);
        this.player.respawn(this.zones.playerSpawn);
        this._orientTo(this.zones.intelPos);
        this.hud.setVeil(1);
        this._enter('DEPLOY');
    }

    /* ---------- 公共：放弃行动（暂停菜单 3）——视同阵亡结算 ---------- */
    abort() {
        if (this.phase === 'WIN' || this.phase === 'LOSE') return;
        this._end(false, { aborted: true });
    }

    /* ---------- 状态推进 ---------- */
    update(dt) {
        const P = this.phase;
        if (P === 'WIN' || P === 'LOSE') return;

        // 阵亡判定（唯一失败条件）
        if (this.player.dead || this.player.health <= 0) { this._end(false); return; }

        this._t += dt;
        this._hudFrameSync();

        // 【搜刮链唯一入口】容器搜索驱动（提示条/进度由 loot 自绘 #fps-search-prompt）
        if (this.loot && typeof this.loot.update === 'function') {
            this.loot.update(dt, this.player.eyePos(), this._fHeld);
        }

        // 高危战区进出（zones.danger 由 layout 派生；缺失则静默跳过）
        this._updateDanger();

        switch (P) {
            case 'DEPLOY': {
                this._deployT += dt;
                this.hud.setVeil(Math.max(0, 1 - this._deployT / 1.4));   // 黑幕淡入
                if (this._deployT >= 2.0) this._enter('PATROL');
                break;
            }
            case 'PATROL': {
                this.hud.showMarker(this.zones.intelPos, '情报');
                if (this._distXZ(this.player.pos, this.zones.intelPos) < INTEL_RADIUS) {
                    this._enter('INTEL');
                }
                break;
            }
            case 'INTEL': {
                const d = this._distXZ(this.player.pos, this.zones.intelPos);
                this.hud.showMarker(this.zones.intelPos, '情报');
                // 容器提示优先：正在搜容器时不吃情报输入（防同键双跑）
                const lootBusy = !!(this.loot && typeof this.loot.isPrompting === 'function'
                    && this.loot.isPrompting());
                if (d > INTEL_LEAVE) { this._enter('PATROL'); break; }    // 走远回巡逻，进度保留
                if (d < INTEL_RADIUS && this._fHeld && !lootBusy) {
                    this._intelT += dt;
                    if (this._intelT >= INTEL_TIME) {
                        this._intelDone();
                        break;
                    }
                }
                this.hud.setIntelProgress(Math.min(1, this._intelT / INTEL_TIME));
                this.hud.setPhase('搜索情报', d < INTEL_RADIUS
                    ? (lootBusy ? '（容器搜索中 —— 情报暂停）'
                        : (this._fHeld ? '搜索中 …' : '按住 F 搜索'))
                    : '靠近情报箱（1.6m 内）');
                break;
            }
            case 'EXTRACT_ENROUTE': {
                const ex = this._extractTarget;
                if (ex) this.hud.showMarker(ex, '撤离点');
                if (ex && this._distXZ(this.player.pos, ex) < this._extractR()) {
                    this._enter('EXTRACT_CHANNEL');
                }
                break;
            }
            case 'EXTRACT_CHANNEL': {
                const ex = this._extractTarget;
                const d = ex ? this._distXZ(this.player.pos, ex) : Infinity;
                if (d > this._extractR() + 0.4) {                          // 滞回防抖
                    this.hud.setExtractProgress(null);
                    this.hud.toast('已离开撤离区');
                    this._enter('EXTRACT_ENROUTE');
                    break;
                }
                this._extractT += dt;
                this.hud.setExtractProgress(this._extractT / EXTRACT_TIME);
                if (this._extractT >= EXTRACT_TIME) this._end(true);
                break;
            }
        }
    }

    /* ---------- 内部：阶段切换 ---------- */
    _enter(phase) {
        this.phase = phase;
        const hud = this.hud;
        switch (phase) {
            case 'DEPLOY':
                hud.setExtractProgress(null);
                hud.setIntelProgress(null);
                hud.showMarker(null);
                hud.setPhase('部署', '投放中 …');
                hud.setObjectiveDetail([
                    '任务目标 —— 烽火地带',
                    '1 · 搜刮容器（木箱/弹药箱/医疗柜…）：靠近按住 F，变卖物计入撤离结算',
                    '2 ·（可选）情报点按住 F 3 秒：全员警戒，撤离成功额外 +₵50,000',
                    '3 · 前往信号烟撤离点，圈内站立 5 秒 —— 背包内物资全部入库',
                    '',
                    '高危战区（地图中心）容器品质更高，敌方精锐出没',
                    '阵亡 / 放弃行动（暂停菜单 3）= 携带全部丢失',
                    '按住 Tab 查看本详情',
                ].join('\n'));
                hud.showBrief('烽火地带 · 行动简报',
                    '搜刮 →（可选情报）→ 撤离\n武器已按大厅配置装载：对局内 1/2 切换主副\n携带物资离场才算你的 —— 阵亡即丢失', 4600);
                hud.setVeil(1);
                break;
            case 'PATROL':
                hud.setPhase('搜刮', '搜刮容器 · 可选：前往情报点（绿标）');
                hud.setIntelProgress(null);
                break;
            case 'INTEL':
                hud.setPhase('搜索情报', '按住 F 搜索 · 撤离成功 +₵50,000');
                break;
            case 'EXTRACT_ENROUTE':
                // 主/备撤离点取最近者并锁定（CHANNEL 滞回用同一点，防两 点间抖动）
                this._extractTarget = this._nearestExtract();
                hud.setPhase('撤离', '前往撤离点（绿色信号烟）');
                hud.setIntelProgress(null);
                hud.toast(this._intelDoneFlag
                    ? '情报到手 —— 前往撤离点'
                    : '携带物资 —— 前往撤离点撤离');
                if (this.audio && this.audio.uiBeep) this.audio.uiBeep();
                break;
            case 'EXTRACT_CHANNEL':
                this._extractT = 0;
                hud.setPhase('撤离', '在信号圈内站立 5 秒');
                if (this.audio && this.audio.uiBeep) this.audio.uiBeep();
                break;
        }
    }

    _intelDone() {
        this._intelT = INTEL_TIME;
        this._intelDoneFlag = true;
        this.hud.setIntelProgress(1);
        this.hud.toast('情报已获取 —— 敌军进入警戒搜索 · 撤离成功 +₵50,000');
        // 敌全员 search 警戒 + 移速×1.2：优先 setAlert(true)；enemies.js 落盘版
        // 以 alertAll(pos) 等价提供（集成者补的接线回退）
        if (this.enemies) {
            if (typeof this.enemies.setAlert === 'function') this.enemies.setAlert(true);
            else if (typeof this.enemies.alertAll === 'function') {
                this.enemies.alertAll(
                    this.player && this.player.eyePos ? this.player.eyePos()
                        : (this.zones && this.zones.intelPos));
            }
        }
        if (this.audio && this.audio.uiBeep) this.audio.uiBeep();
        this._enter('EXTRACT_ENROUTE');
    }

    _end(win, opt = {}) {
        if (this.phase === 'WIN' || this.phase === 'LOSE') return;
        this.phase = win ? 'WIN' : 'LOSE';
        const s = this._finalStats(win, !!opt.aborted);
        this.stats = s;
        const items = this.backpack ? this.backpack.items.slice() : [];   // 背包快照
        const intelBonus = this._intelDoneFlag ? INTEL_BONUS : 0;
        this.hud.setExtractProgress(null);
        this.hud.setIntelProgress(null);
        this.hud.showMarker(null);
        this.hud.setDanger(false);
        this._inDanger = false;
        this.hud.setVeil(win ? 0 : 0.5);   // 失败半黑衬结算页
        this.hud.setPhase(win ? '任务完成' : '行动失败',
            win ? '撤离成功 · 携带入库'
                : (opt.aborted ? '行动中止 · 视同阵亡' : '阵亡 · 携带丢失'));
        // 结算行一次给全（extraRows 替换默认三行，main 无需二次 showResult）
        const acc = `${(s.accuracy * 100).toFixed(1)}%`;
        const mm = Math.floor(s.timeSec / 60), ss = Math.floor(s.timeSec % 60);
        const extraRows = win
            ? [
                ['带出价值', '₵ ' + (s.carried || 0).toLocaleString('en-US')],
                ['情报奖金', this._intelDoneFlag ? '₵ 50,000' : '——'],
                ['击杀', `${s.kills}`], ['命中率', acc],
                ['用时', `${mm}:${String(ss).padStart(2, '0')}`], ['评级', s.rank],
            ]
            : [
                ['丢失携带', `₵ ${(s.carried || 0).toLocaleString('en-US')}（已入库资产无损）`],
                ['击杀', `${s.kills}`], ['命中率', acc],
                ['用时', `${mm}:${String(ss).padStart(2, '0')}`],
                [opt.aborted ? '中止' : '阵亡', '携带全部丢失'],
            ];
        this.hud.showResult({ ...s, extraRows });
        if (this.onEnd) {
            this.onEnd({ win, stats: s, items, intelDone: this._intelDoneFlag, intelBonus });
        }
    }

    /* ---------- 内部：高危战区 ---------- */
    _updateDanger() {
        const dz = this.zones && this.zones.danger;
        if (!dz) return;
        const r = dz.r || 80;
        const inZone = Math.hypot(this.player.pos.x - dz.cx, this.player.pos.z - dz.cz) <= r;
        if (inZone === this._inDanger) return;
        this._inDanger = inZone;
        this.hud.setDanger(inZone);
        const now = performance.now();
        if (now < this._nextDangerToast) return;
        this._nextDangerToast = now + DANGER_TOAST_CD;
        this.hud.toast(inZone
            ? '⚠ 进入高危战区 —— 敌方精锐出没，高品质物资亦在此'
            : '已离开高危战区', inZone ? 5000 : 3000);
    }

    /* ---------- 内部：统计 ---------- */
    _snapshotGun() {
        const st = this.gunview && this.gunview.stats;
        return { shots: st ? st.shots : 0, hits: st ? st.hits : 0 };
    }

    _finalStats(win, aborted = false) {
        const now = this._snapshotGun();
        const shots = Math.max(0, now.shots - this._snapShots.shots);
        const hits = Math.max(0, now.hits - this._snapShots.hits);
        const acc = shots > 0 ? hits / shots : 0;
        const t = this._t;
        let rank;
        if (!win) rank = 'C';
        else if (acc >= 0.35 && t <= 300) rank = 'S';
        else if (acc >= 0.22 || t <= 420) rank = 'A';
        else rank = 'B';
        return {
            win, aborted, kills: this._kills, accuracy: acc, timeSec: t, rank,
            carried: this.backpack ? this.backpack.totalValue() : 0,   // 携带价值（结算用）
        };
    }

    /* ---------- 内部：每帧 HUD 同步 ---------- */
    _hudFrameSync() {
        const g = this.gunview, p = this.player, hud = this.hud;
        if (g) {
            hud.setAmmoState({
                ammo: g.ammo, reserve: g.reserve, reloading: g.reloading,
                reloadProgress: g.reloadProgress, reloadKind: g.reloadKind,
            });
            hud.setAds(g.adsAmount || 0);
        }
        hud.setHealth(p.health);
        hud.compass(p.yaw);
        // 受击暗角兜底（无方向）：血量下降沿闪一下；精确方向提示由 main 接
        // player.onDamage(dmg,fromPos) → hud.damageFrom(dirAngle) 提供
        if (p.health < this._lastHealth - 0.01) hud.damageFrom(null);
        this._lastHealth = p.health;
    }

    /* ---------- 内部：搜刮链（loot → backpack → HUD） ---------- */
    // 链式接管 loot.onLooted：入包 → 背包 HUD → 品质色 toast（满包提示）
    _chainLoot() {
        if (!this.loot || !this.backpack) return;
        const old = this.loot.onLooted;
        this.loot.onLooted = (item) => {
            if (old) old(item);
            this._takeLoot(item);
        };
    }

    _takeLoot(item) {
        if (!item) return;
        if (this.backpack) {
            const ok = this.backpack.add(item);
            this.hud.setBag(this.backpack.items, this.backpack.capacity || 12);
            if (!ok) {
                this.hud.toast('背包已满 —— 只有撤离才能带出，先挑值钱的', 3200);
                return;
            }
        }
        const r = rarInfo(item.rarity);
        this.hud.toast(
            `获得：${item.name || '战利品'}（${r.name} · ₵ ${(item.value || 0).toLocaleString('en-US')}）`,
            3200, r.color);
        if (this.audio && this.audio.uiBeep) this.audio.uiBeep();
    }

    /* ---------- 内部：敌组回调（链式，不覆盖 main 可能挂的） ---------- */
    _chainEnemyCallbacks() {
        const chain = (obj, key, fn) => {
            if (!obj) return;
            const old = obj[key];
            obj[key] = (...a) => { if (old) old(...a); fn(...a); };
        };
        chain(this.enemies, 'onKill', (name, dist, head) => {
            this._kills += 1;
            this.hud.killfeed(`击杀 ${name || '敌兵'} · ${Math.round(dist || 0)}m${head ? ' · 爆头' : ''}`);
        });
        chain(this.enemies, 'onPlayerSpotted', () => {
            const now = performance.now();
            if (now < this._nextSpotHint) return;
            this._nextSpotHint = now + SPOT_HINT_CD * 1000;
            this.hud.toast('⚠ 已被敌军发现 —— 保持机动或还击');
        });
        // interfaces 未定义 GunView→伤害桥；若枪械组提供 onHit 字段则兜底出白 hitmarker
        //（完整 killed/head 判定由 main.js 接 combat.applyHit 后调 hud.hitmarker）
        const g = this.gunview;
        if (g && g.onHit === undefined) {
            g.onHit = (hit) => { if (hit) this.hud.hitmarker(false, false); };
        }
    }

    /* ---------- 内部：工具 ---------- */
    _bindKeys() {
        this._onKeyDown = (e) => { if (e.code === 'KeyF') this._fHeld = true; };
        this._onKeyUp = (e) => { if (e.code === 'KeyF') this._fHeld = false; };
        window.addEventListener('keydown', this._onKeyDown);
        window.addEventListener('keyup', this._onKeyUp);
    }

    _distXZ(a, b) {
        const dx = a.x - b.x, dz = a.z - b.z;
        return Math.sqrt(dx * dx + dz * dz);
    }

    // 主/备撤离点（zones.extractPos 数组化；兼容旧单点 Vector3）取最近者
    _nearestExtract() {
        const ep = this.zones && this.zones.extractPos;
        if (!ep) return null;
        const list = Array.isArray(ep) ? ep : [ep];
        let best = null, bd = Infinity;
        for (const p of list) {
            if (!p) continue;
            const d = this._distXZ(this.player.pos, p);
            if (d < bd) { bd = d; best = p; }
        }
        return best;
    }

    _extractR() {
        return this.zones.extractR || 3;
    }

    // 出生朝向目标点（yaw=0 面向 -Z）
    _orientTo(target) {
        const dx = target.x - this.player.pos.x;
        const dz = target.z - this.player.pos.z;
        this.player.yaw = Math.atan2(-dx, -dz);
        this.player.pitch = 0;
    }

    dispose() {
        window.removeEventListener('keydown', this._onKeyDown);
        window.removeEventListener('keyup', this._onKeyUp);
    }
}
