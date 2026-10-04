/* ============================================================
 * js/fps/mission.js —— 行动模式闭环状态机（照 missionSpec）
 * DEPLOY(2s 黑幕淡入+简报卡) → PATROL(世界标记指引情报) →
 * INTEL(距情报箱<1.6m 按住 F 3s，松手暂停不重置) →
 * EXTRACT_ENROUTE(标记信号烟) → EXTRACT_CHANNEL(圈内站立 5s，离圈中断) →
 * WIN；任意时刻玩家 health≤0 → LOSE。敌 onPlayerSpotted 只改提示不换 phase。
 * ============================================================ */

const INTEL_RADIUS = 1.6;     // 进距：显示「按住 F 搜索」
const INTEL_LEAVE = 2.6;      // 出距（滞回）：太远回 PATROL，进度保留
const INTEL_TIME = 3.0;       // 按住 F 秒数
const EXTRACT_TIME = 5.0;     // 撤离圈内站立秒数
const SPOT_HINT_CD = 6.0;     // 「被发现」提示节流

export class Mission {
    // { hud, player, enemies, zones, gunview, audio, onEnd } 全部鸭子类型注入
    constructor({ hud, player, enemies, zones, gunview, audio, onEnd }) {
        this.hud = hud;
        this.player = player;
        this.enemies = enemies;
        this.zones = zones;
        this.gunview = gunview;
        this.audio = audio;
        this.onEnd = onEnd || null;

        this.stats = { kills: 0, accuracy: 0, timeSec: 0, rank: 'C' };
        this._t = 0;                  // 用时（DEPLOY 起累计）
        this._deployT = 0;
        this._intelT = 0;             // 情报进度（松手/走远保留）
        this._extractT = 0;
        this._lastHealth = 100;
        this._nextSpotHint = 0;
        this._fHeld = false;

        this._chainEnemyCallbacks();
        this._bindKeys();
        this.restart();
    }

    restart() {
        this._t = 0; this._deployT = 0; this._intelT = 0; this._extractT = 0;
        this._snapShots = this._snapshotGun();
        this._kills = 0;
        this._lastHealth = 100;
        this._nextSpotHint = 0;
        // 敌兵复活回巡逻态：优先 resetAll()；enemies.js 落盘版以
        // 「spawnPatrol 重复调用 = 全量重置」等价提供（集成者补的接线回退）
        if (this.enemies) {
            if (typeof this.enemies.resetAll === 'function') this.enemies.resetAll();
            else if (this.zones && Array.isArray(this.zones.patrol)
                && typeof this.enemies.spawnPatrol === 'function') {
                this.enemies.spawnPatrol(this.zones.patrol);
            }
        }
        this.player.respawn(this.zones.playerSpawn);
        this._orientTo(this.zones.intelPos);
        this.hud.setVeil(1);
        this._enter('DEPLOY');
    }

    /* ---------- 状态推进 ---------- */
    update(dt) {
        const P = this.phase;
        if (P === 'WIN' || P === 'LOSE') return;

        // 阵亡判定（唯一失败条件）
        if (this.player.dead || this.player.health <= 0) { this._end(false); return; }

        this._t += dt;
        this._hudFrameSync();

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
                if (d > INTEL_LEAVE) { this._enter('PATROL'); break; }    // 走远回巡逻，进度保留
                if (d < INTEL_RADIUS && this._fHeld) {
                    this._intelT += dt;
                    if (this._intelT >= INTEL_TIME) {
                        this._intelDone();
                        break;
                    }
                }
                this.hud.setIntelProgress(Math.min(1, this._intelT / INTEL_TIME));
                this.hud.setPhase('搜索情报', d < INTEL_RADIUS
                    ? (this._fHeld ? '搜索中 …' : '按住 F 搜索')
                    : '靠近情报箱（1.6m 内）');
                break;
            }
            case 'EXTRACT_ENROUTE': {
                this.hud.showMarker(this.zones.extractPos, '撤离点');
                if (this._distXZ(this.player.pos, this.zones.extractPos) < this._extractR()) {
                    this._enter('EXTRACT_CHANNEL');
                }
                break;
            }
            case 'EXTRACT_CHANNEL': {
                const d = this._distXZ(this.player.pos, this.zones.extractPos);
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
                    '任务目标',
                    '1 · 前往情报建筑，按住 F 搜索 3 秒获取情报',
                    '2 · 前往绿色信号烟撤离点，圈内站立 5 秒',
                    '',
                    '敌军 8 人 · 3 条巡逻线 · 可绕行可歼灭',
                    '失败条件：阵亡',
                    '按住 Tab 查看本详情',
                ].join('\n'));
                hud.showBrief('行动简报', '目标：获取情报 → 撤离\n区域内有敌军巡逻，保持警惕', 4200);
                hud.setVeil(1);
                break;
            case 'PATROL':
                hud.setPhase('巡逻', '前往情报点获取情报');
                hud.setIntelProgress(null);
                break;
            case 'INTEL':
                hud.setPhase('搜索情报', '按住 F 搜索');
                break;
            case 'EXTRACT_ENROUTE':
                hud.setPhase('撤离', '前往撤离点（绿色信号烟）');
                hud.setIntelProgress(null);
                hud.toast('情报到手 —— 前往撤离点');
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
        this.hud.setIntelProgress(1);
        this.hud.toast('情报已获取 —— 敌军进入警戒搜索');
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

    _end(win) {
        this.phase = win ? 'WIN' : 'LOSE';
        const s = this._finalStats(win);
        this.stats = s;
        this.hud.setExtractProgress(null);
        this.hud.setIntelProgress(null);
        this.hud.showMarker(null);
        this.hud.setVeil(win ? 0 : 0.5);   // 失败半黑衬结算页
        this.hud.setPhase(win ? '任务完成' : '行动失败', win ? '撤离成功' : '阵亡');
        this.hud.showResult(s);
        if (this.onEnd) this.onEnd({ win, stats: s });
    }

    /* ---------- 内部：统计 ---------- */
    _snapshotGun() {
        const st = this.gunview && this.gunview.stats;
        return { shots: st ? st.shots : 0, hits: st ? st.hits : 0 };
    }

    _finalStats(win) {
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
        return { win, kills: this._kills, accuracy: acc, timeSec: t, rank };
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
