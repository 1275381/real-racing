/* ============================================================
 * js/fps/rangeMode.js —— 靶场会话（照 missionSpec 靶场模式规格；场地为
 * rangeHall.js 全封闭室内靶馆）· 无限备弹（reserve<30 自动回满 120）、
 * 命中音「叮」+倒靶闷响、连击（miss 清零）、命中率、最佳分持久化
 * localStorage fps_range_best（targets.best 字段优先，缺失时本地兜底）。
 * 长按 R 0.5s 重置全场。
 * ============================================================ */

const RESERVE_REFILL = 120;   // 自动回满的备弹数
const REFILL_BELOW = 30;      // 低于即回满
const R_HOLD_MS = 500;        // 长按 R 重置

export class RangeMode {
    // { hud, targets, gunview } 鸭子类型注入
    constructor({ hud, targets, gunview }) {
        this.hud = hud;
        this.targets = targets;
        this.gunview = gunview;

        this.streak = 0;
        this.bestStreak = 0;
        this._started = false;
        this._best = 0;
        try { this._best = Number(localStorage.getItem('fps_range_best') || 0) || 0; } catch (e) { /* 隐私模式 */ }
        this._sess0 = { shots: 0, hits: 0 };   // 会话命中率快照
        this._lastShots = 0;                    // 上一帧开火数快照（判 miss 清连击）
        this._frameHits = 0;                    // 本帧命中靶数
        this._rDownAt = 0;
        this._rFired = false;

        this._bindKeys();
        this._chainTargetCallbacks();
    }

    start() {
        this._started = true;
        const g = this.gunview;
        if (g) {
            if (g.resetAmmo) g.resetAmmo(RESERVE_REFILL);
            if (g.stats) this._sess0 = { shots: g.stats.shots, hits: g.stats.hits };
            this._lastShots = g.stats ? g.stats.shots : 0;
        }
        const hud = this.hud;
        hud.setVeil(0);
        hud.showMarker(null);
        hud.setExtractProgress(null);
        hud.setIntelProgress(null);
        hud.setPhase('室内靶馆', '固定靶 ×8 · 摆动靶 ×4 · 长按 R 重置');
        hud.setObjectiveDetail([
            '靶馆说明（全封闭室内靶道）',
            '· 10 / 15 / 25m 人形环靶，命中倒下 0.9s 后自动立起',
            '· 15m 摆动靶 ±30° 正弦，倒下不自动复位',
            '· 环 10/9 = 100 分 · 8/7 = 50 分 · 其余 25 分',
            '· 备弹无限（自动回满 120）',
            '· 长按 R 0.5 秒：重置全场靶与计分',
            '· 枪口始终朝向靶道，越过黄线前退弹（告示牌守则）',
            '按住 Tab 查看本详情',
        ].join('\n'));
        hud.toast('室内靶馆 —— 自由开火');
        hud.ui.ensure();
    }

    reset() {
        if (this.targets && this.targets.reset) this.targets.reset();
        this.streak = 0;
        const g = this.gunview;
        if (g && g.stats) {
            this._sess0 = { shots: g.stats.shots, hits: g.stats.hits };
            this._lastShots = g.stats.shots;
        }
        if (g && g.resetAmmo) g.resetAmmo(RESERVE_REFILL);
        this.hud.toast('全场已重置 —— 计分清零');
        this.hud.ui.beep(660, 0.08, 0.15);
    }

    update(dt) {
        if (!this._started) this.start();
        const g = this.gunview, hud = this.hud;

        // 无限备弹：低于阈值自动回满
        if (g && g.reserve < REFILL_BELOW && g.resetAmmo) g.resetAmmo(RESERVE_REFILL);

        // HUD：弹药 + ADS（靶场无血量/罗盘压力，罗盘由 main 每帧统一喂 yaw）
        if (g) {
            hud.setAmmoState({
                ammo: g.ammo, reserve: g.reserve, reloading: g.reloading,
                reloadProgress: g.reloadProgress, reloadKind: g.reloadKind,
            });
            hud.setAds(g.adsAmount || 0);
        }

        // 连击：本帧开火数 − 本帧靶命中数 = miss → 清零（onHit 在渲染前由伤害桥触发）
        if (g && g.stats) {
            const fired = g.stats.shots - this._lastShots;
            if (fired > this._frameHits) this.streak = 0;
            if (fired > 0) this._lastShots = g.stats.shots;
        }
        this._frameHits = 0;

        // 成绩板
        const score = (this.targets && this.targets.score) || 0;
        this._syncBest(score);
        hud.setRangeStats({
            score,
            acc: this._accuracy(),
            best: this._best,
            streak: this.streak,
        });

        // 长按 R 重置
        if (this._rDownAt > 0 && !this._rFired
            && performance.now() - this._rDownAt >= R_HOLD_MS) {
            this._rFired = true;
            this.reset();
        }
    }

    /* ---------- 内部 ---------- */
    _accuracy() {
        const g = this.gunview;
        if (!g || !g.stats) return 0;
        const shots = g.stats.shots - this._sess0.shots;
        const hits = g.stats.hits - this._sess0.hits;
        return shots > 0 ? Math.max(0, hits / shots) : 0;
    }

    _syncBest(score) {
        // targets.best 字段优先（targets 组可能自己持久化），否则本地 localStorage 兜底
        if (typeof this.targets.best === 'number') this._best = Math.max(this._best, this.targets.best);
        if (score > this._best) {
            this._best = score;
            try { localStorage.setItem('fps_range_best', String(score)); } catch (e) { /* 忽略 */ }
            if (this.targets.best !== undefined) this.targets.best = score;
            this.hud.toast(`新纪录 ${score} 分！`);
            this.hud.ui.ding(true);
        }
    }

    _bindKeys() {
        this._onKeyDown = (e) => {
            if (e.code === 'KeyR' && !e.repeat) {
                this._rDownAt = performance.now();
                this._rFired = false;
            }
        };
        this._onKeyUp = (e) => {
            if (e.code === 'KeyR') this._rDownAt = 0;
        };
        window.addEventListener('keydown', this._onKeyDown);
        window.addEventListener('keyup', this._onKeyUp);
    }

    // 靶组回调（链式，不覆盖 main 可能挂的）：命中音 + 倒靶闷响 + 连击
    _chainTargetCallbacks() {
        const t = this.targets;
        if (!t) return;
        const old = t.onHit;
        t.onHit = (index, ring) => {
            if (old) old(index, ring);
            this._frameHits += 1;
            this.streak += 1;
            this.bestStreak = Math.max(this.bestStreak, this.streak);
            this.hud.ui.ding(ring >= 9);                       // 命中「叮」，内环更亮
            this.hud.ui.thud(0.09);                             // 倒靶闷响稍滞后（WebAudio 时间调度）
        };
    }

    dispose() {
        window.removeEventListener('keydown', this._onKeyDown);
        window.removeEventListener('keyup', this._onKeyUp);
    }
}
