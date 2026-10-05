/* ============================================================
 * js/fps/lobby.js —— 烽火地带大厅（【大厅】组，仿三角洲主界面）
 * 自注入 DOM：#fps-lobby（fps.html 预留占位；缺失则自建），z-index 30，
 * 盖场时置 hud.uiBlocked = true（屏蔽 H/Tab 全局键，M 静音保留），
 * hide() 时 display:none 释放（点击不落到 canvas，不触发指针锁定）。
 * 页签：1 出发 / 2 仓库 / 3 改枪台；G 任意页签直接去靶场；C 每日签到 +₵1,500。
 * 出发页光标模型：←/→ 单轴扫 [主槽|副槽|候选枪×N|▶出发]，回车执行：
 *   槽 = 聚焦装入目标槽 · 枪 = 装入聚焦槽（主副不可同枪）· 出发 = onDeploy。
 * 数据来源（只读）：stash（自有资产）、gunsData（枪表，经 stash 适配器）、
 * loot.RARITY（品质色，经 stash 适配器）。
 * 样式：全部 .lobby-* 类（js 内注入兜底样式表，集成者可整段搬进 css/fps.css）。
 * ============================================================ */
import { rarInfo, gunIds, gunInfo, scopeList, scopeById, DAILY_REWARD } from './stash.js';
import { itemIconUrl } from './loot.js';

const GUN_IDS = gunIds();   // 出发页候选枪顺序（与 gunsData 表序一致）

/* ==== 大厅兜底样式：插入 head，css/fps.css 同名类可整体覆盖 ==== */
const LOBBY_CSS = `
.lobby-root{position:fixed;inset:0;z-index:30;display:none;flex-direction:column;
  pointer-events:auto;user-select:none;color:#d8ded2;
  font-family:Menlo,Consolas,'SF Mono',monospace;letter-spacing:.04em;
  background:linear-gradient(180deg,rgba(6,9,7,.93),rgba(8,11,9,.88));
  overflow:hidden}
.lobby-root::before{content:'';position:absolute;inset:0;pointer-events:none;
  background:repeating-linear-gradient(0deg,rgba(216,222,210,.028) 0 1px,transparent 1px 4px)}
.lobby-topbar{display:flex;align-items:center;gap:26px;padding:16px 34px;
  border-bottom:1px solid rgba(255,179,92,.28);
  background:linear-gradient(180deg,rgba(20,26,20,.85),rgba(20,26,20,.35))}
.lobby-logo{font-size:22px;letter-spacing:.42em;color:#ffb35c;font-weight:700}
.lobby-logo-sub{display:block;font-size:10px;letter-spacing:.3em;opacity:.55;margin-top:3px;font-weight:400}
.lobby-record{margin-left:auto;font-size:12px;opacity:.75;font-variant-numeric:tabular-nums}
.lobby-cash{font-size:22px;color:#7ee2a8;font-variant-numeric:tabular-nums;min-width:150px;text-align:right}
.lobby-cash-flash{animation:lobbyCashFlash .6s ease-out}
@keyframes lobbyCashFlash{0%{color:#ff5941;transform:scale(1.12)}100%{}}
/* -- 每日签到按钮（顶栏，现金左侧） -- */
.lobby-daily{padding:8px 18px;border:1px solid rgba(216,222,210,.25);border-radius:6px;
  font-size:13px;letter-spacing:.18em;color:#9fb3a0;background:rgba(20,26,20,.7);
  cursor:pointer;user-select:none;white-space:nowrap}
.lobby-daily-yes{border-color:rgba(255,179,92,.75);color:#ffd9a3;
  background:rgba(60,48,24,.5);animation:dailyPulse 2.2s ease-in-out infinite}
@keyframes dailyPulse{0%,100%{box-shadow:0 0 6px rgba(255,179,92,.22)}50%{box-shadow:0 0 16px rgba(255,179,92,.5)}}
.lobby-daily-no{opacity:.45;cursor:default}
.lobby-body{flex:1;display:flex;align-items:center;justify-content:center;min-height:0}
.lobby-panel{width:min(1020px,92vw);max-height:78vh;display:flex;flex-direction:column;
  background:rgba(10,14,11,.72);border:1px solid rgba(216,222,210,.22);
  box-shadow:0 0 40px rgba(0,0,0,.5);padding:20px 26px}
.lobby-page{display:none;flex-direction:column;gap:12px;min-height:0;overflow:auto}
.lobby-hint{font-size:12px;opacity:.6;text-align:center;letter-spacing:.18em;padding-top:2px}
.lobby-sel{border-color:#ffb35c !important;background:rgba(255,179,92,.13) !important;
  box-shadow:inset 0 0 0 1px #ffb35c,0 0 12px rgba(255,179,92,.28)}
/* -- 出发页 -- */
.lobby-slots{display:flex;gap:14px}
.lobby-slot{flex:1;position:relative;padding:12px 16px;border:1px solid rgba(216,222,210,.3);
  background:rgba(24,30,24,.6);cursor:pointer}
.lobby-slot-label{font-size:11px;letter-spacing:.3em;color:#7ee2a8;margin-bottom:6px}
.lobby-slot-gun{font-size:19px;color:#ffd9a3;letter-spacing:.12em}
.lobby-slot-desc{font-size:12px;opacity:.6;margin-top:4px}
.lobby-slot-tag{position:absolute;right:10px;top:10px;font-size:11px;color:#7ee2a8}
.lobby-slot-focus{border-color:rgba(126,226,168,.75)}
.lobby-guns{display:flex;flex-direction:column;gap:6px}
.lobby-gun-row{display:flex;align-items:baseline;gap:14px;padding:9px 16px;
  border:1px solid rgba(216,222,210,.22);background:rgba(24,30,24,.5);cursor:pointer}
.lobby-gun-name{font-size:15px;color:#e8ecdf;min-width:110px;letter-spacing:.14em}
.lobby-gun-desc{font-size:12px;opacity:.6;flex:1}
.lobby-gun-price{font-size:13px;color:#7ee2a8;font-variant-numeric:tabular-nums}
.lobby-gun-locked{opacity:.42}
.lobby-gun-locked .lobby-gun-price{color:#ffb35c}
.lobby-deploy-cols{display:flex;gap:18px;align-items:stretch;min-height:0}
.lobby-preview{width:340px;flex:none;display:flex;flex-direction:column;gap:8px}
.lobby-preview-cv{width:100%;border:1px solid rgba(216,222,210,.22);background:rgba(10,14,10,.6)}
.lobby-preview-name{font-size:15px;letter-spacing:.14em;color:#ffd9a3}
.lobby-stat-chips{display:flex;flex-wrap:wrap;gap:6px}
.lobby-stat-chip{display:flex;gap:6px;align-items:baseline;padding:3px 10px;
  border:1px solid rgba(216,222,210,.22);background:rgba(24,30,24,.5);font-size:12px}
.lobby-stat-chip .k{opacity:.55;letter-spacing:.15em}
.lobby-stat-chip .v{color:#7ee2a8;font-variant-numeric:tabular-nums}
.lobby-main{flex:1;display:flex;flex-direction:column;gap:10px;min-width:0;overflow:auto}
.lobby-guns-title{font-size:11px;letter-spacing:.3em;color:#7ee2a8;opacity:.85}
.lobby-gun-bars{display:flex;flex-direction:column;gap:3px;width:96px;margin-left:auto;flex:none}
.lobby-gun-bar{height:4px;background:rgba(216,222,210,.12)}
.lobby-gun-bar i{display:block;height:100%}
.lobby-deploy-btn{align-self:center;margin-top:4px;padding:12px 70px;font-size:17px;
  letter-spacing:.5em;border:1px solid rgba(255,179,92,.7);color:#ffb35c;cursor:pointer;
  background:rgba(60,48,24,.4)}
.lobby-deploy-btn-sel{background:rgba(255,179,92,.22);color:#ffd9a3}
/* -- 仓库页 -- */
.lobby-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:8px}
.lobby-cell{border:1px solid rgba(216,222,210,.3);border-width:2px;background:rgba(24,30,24,.55);
  padding:8px 6px;text-align:center;cursor:pointer;min-height:86px}
.lobby-cell-rainbow{animation:lobbyGlow 1.6s ease-in-out infinite}
@keyframes lobbyGlow{0%,100%{box-shadow:0 0 4px rgba(232,79,216,.3)}50%{box-shadow:0 0 16px rgba(232,79,216,.75)}}
.lobby-cell-icon{font-size:22px}
.lobby-cell-name{font-size:11px;margin-top:4px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
.lobby-cell-value{font-size:12px;color:#7ee2a8;margin-top:3px;font-variant-numeric:tabular-nums}
.lobby-cell-empty{font-size:14px;opacity:.55;text-align:center;padding:40px 0;letter-spacing:.2em}
.lobby-stash-foot{display:flex;align-items:center;gap:18px;margin-top:2px}
.lobby-total{font-size:14px;color:#ffd9a3;font-variant-numeric:tabular-nums}
.lobby-sellall{margin-left:auto;padding:7px 22px;font-size:13px;letter-spacing:.2em;cursor:pointer;
  border:1px solid rgba(255,179,92,.6);color:#ffb35c;background:rgba(60,48,24,.4)}
.lobby-gunrow{display:flex;flex-wrap:wrap;gap:8px;align-items:center;
  border-top:1px solid rgba(216,222,210,.18);padding-top:10px}
.lobby-gunrow-title{font-size:11px;letter-spacing:.3em;color:#7ee2a8;margin-right:6px}
.lobby-gunrow-item{font-size:12px;padding:4px 12px;border:1px solid rgba(216,222,210,.25);
  background:rgba(24,30,24,.5)}
/* -- 改枪台页 -- */
.lobby-bench{display:flex;gap:16px}
.lobby-bench-col{flex:1;display:flex;flex-direction:column;gap:6px;min-width:0}
.lobby-bench-title{font-size:12px;letter-spacing:.3em;color:#7ee2a8;margin-bottom:2px}
.lobby-bench-item{display:flex;align-items:baseline;gap:10px;padding:8px 14px;
  border:1px solid rgba(216,222,210,.22);background:rgba(24,30,24,.5);cursor:pointer}
.lobby-bench-name{font-size:14px;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lobby-bench-tag{font-size:12px;color:#7ee2a8;font-variant-numeric:tabular-nums;white-space:nowrap}
.lobby-bench-price{color:#ffb35c}
/* -- 底部页签栏 -- */
.lobby-bottombar{display:flex;align-items:center;gap:10px;padding:12px 34px;
  border-top:1px solid rgba(255,179,92,.28);
  background:linear-gradient(0deg,rgba(20,26,20,.9),rgba(20,26,20,.4))}
.lobby-tab{padding:9px 30px;font-size:14px;letter-spacing:.3em;cursor:pointer;
  border:1px solid rgba(216,222,210,.28);background:rgba(24,30,24,.6);color:#a8b0a2}
.lobby-tab-active{border-color:#ffb35c;color:#ffb35c;background:rgba(60,48,24,.6)}
.lobby-range-btn{margin-left:auto;padding:9px 26px;font-size:13px;letter-spacing:.24em;cursor:pointer;
  border:1px solid rgba(126,226,168,.6);color:#7ee2a8;background:rgba(20,40,28,.45)}
.lobby-range-btn:hover{background:rgba(126,226,168,.18)}
`;

/* ==== 小工具 ==== */
function _div(cls, txt) {
    const el = document.createElement('div');
    if (cls) el.className = cls;
    if (txt !== undefined) el.textContent = txt;
    return el;
}
function _span(cls, txt) {
    const el = document.createElement('span');
    if (cls) el.className = cls;
    if (txt !== undefined) el.textContent = txt;
    return el;
}
const _fmt = (n) => `₵ ${Math.max(0, Math.round(Number(n) || 0)).toLocaleString('en-US')}`;

/* ==== 武器剪影（写实度评审 #06：出发页「武器为主角」） ====
 * 每枪一组多边形侧视轮廓（100×44 单位盒，x 右 y 下），Canvas2D 按
 * 橄榄底 + 琥珀描边绘制——程序化零外部资源，与全站 UI 同一色系。 */
const GUN_PROFILES = {
    pistol: { polys: [
        [[12, 10], [64, 10], [64, 22], [40, 22], [36, 40], [20, 40], [26, 22], [12, 22]],
        [[64, 12], [78, 14], [78, 18], [64, 18]],
    ] },
    smg: { polys: [
        [[8, 12], [62, 12], [62, 24], [8, 24]],
        [[62, 15], [80, 15], [80, 20], [62, 20]],
        [[34, 24], [46, 24], [43, 44], [31, 44]],
        [[8, 14], [0, 16], [0, 22], [8, 22]],
        [[50, 24], [58, 24], [54, 38], [46, 38]],
    ] },
    rifle: { polys: [
        [[30, 12], [64, 12], [64, 24], [30, 24]],
        [[64, 14], [86, 14], [86, 22], [64, 22]],
        [[86, 16], [96, 16], [96, 19], [86, 19]],
        [[44, 24], [56, 24], [52, 42], [40, 42]],
        [[30, 24], [38, 24], [34, 38], [26, 38]],
        [[8, 14], [30, 14], [30, 22], [14, 24], [8, 22]],
        [[40, 7], [48, 7], [48, 12], [40, 12]],
    ] },
    shotgun: { polys: [
        [[34, 14], [58, 14], [58, 24], [34, 24]],
        [[58, 15], [97, 15], [97, 18], [58, 18]],
        [[58, 20], [88, 20], [88, 23], [58, 23]],
        [[70, 19], [82, 19], [82, 27], [70, 27]],
        [[10, 14], [34, 14], [34, 26], [16, 32], [8, 28]],
    ] },
    sniper: { polys: [
        [[28, 14], [58, 14], [58, 24], [28, 24]],
        [[58, 16], [97, 16], [97, 20], [58, 20]],
        [[34, 4], [56, 4], [56, 11], [34, 11]],
        [[38, 11], [41, 11], [41, 14], [38, 14]],
        [[50, 11], [53, 11], [53, 14], [50, 14]],
        [[42, 24], [52, 24], [50, 32], [40, 32]],
        [[6, 13], [28, 13], [28, 26], [12, 30], [6, 24]],
        [[80, 20], [86, 33], [84, 34], [78, 21]],
        [[80, 20], [74, 33], [76, 34], [82, 21]],
    ] },
};

function _drawSilhouette(cv, id) {
    const g = cv.getContext('2d');
    const W = cv.width, H = cv.height;
    g.clearRect(0, 0, W, H);
    /* 背景网格（蓝图感）+ 地平线 */
    g.strokeStyle = 'rgba(216,222,210,0.06)';
    g.lineWidth = 1;
    for (let x = 0; x < W; x += 24) {
        g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke();
    }
    for (let y = 0; y < H; y += 24) {
        g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke();
    }
    const prof = GUN_PROFILES[id] || GUN_PROFILES.rifle;
    const S = (W - 48) / 100, OX = 24, OY = H / 2 - 22 * S;
    g.save();
    g.translate(OX, OY);
    g.scale(S, S);
    g.lineJoin = 'round';
    for (const poly of prof.polys) {
        g.beginPath();
        poly.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y)));
        g.closePath();
        g.fillStyle = 'rgba(30,38,28,0.92)';
        g.fill();
        g.strokeStyle = 'rgba(255,179,92,0.85)';
        g.lineWidth = 0.9;
        g.stroke();
    }
    g.restore();
    g.strokeStyle = 'rgba(255,179,92,0.35)';
    g.beginPath(); g.moveTo(12, H - 10); g.lineTo(W - 12, H - 10); g.stroke();
}

export class Lobby {
    // { hud, stash, onDeploy({primary,secondary,scopes}), onRange() } 注入
    constructor({ hud, stash, onDeploy, onRange }) {
        this.hud = hud || null;
        this.stash = stash;
        this.onDeploy = onDeploy || null;
        this.onRange = onRange || null;

        this.visible = false;
        this._tab = 0;              // 0 出发 / 1 仓库 / 2 改枪台
        this._cur0 = 0;             // 出发页光标：0主槽 1副槽 2..N+1枪 N+2出发
        this._slotFocus = 'primary';// 出发页「装入目标槽」
        this._cur1 = 0;             // 仓库网格光标
        this._gunIdx = 0;           // 改枪台左列选中枪
        this._scopeIdx = 0;         // 改枪台右列选中瞄具
        this._col = 0;              // 改枪台列：0=枪 1=瞄具

        this._cashShown = Math.max(0, Math.round(stash.cash || 0));
        this._cashRAF = 0;

        this._injectStyle();
        this._build();
        this._bindKeys();

        // 资产变动 → 刷新（链式保留既有回调）
        const old = stash.onChanged;
        stash.onChanged = () => { if (old) old(); this._refreshAll(); };
        this._refreshAll();
    }

    /* ---------- DOM 构建 ---------- */
    _injectStyle() {
        if (document.getElementById('fpsLobbyStyle')) return;
        const st = document.createElement('style');
        st.id = 'fpsLobbyStyle';
        st.textContent = LOBBY_CSS;
        /* 插 <head> 最前（hud.js 兜底样式同款约定）：后加载的 css/fps.css
         * 大厅段同名规则永远胜出，本段只是兜底 */
        document.head.insertBefore(st, document.head.firstChild);
    }

    _build() {
        let root = document.getElementById('fps-lobby');
        if (!root) {
            root = document.createElement('div');
            root.id = 'fps-lobby';
            document.body.appendChild(root);
        }
        root.innerHTML = '';
        root.className = 'lobby-root';
        root.style.display = 'none';
        this._root = root;

        // 顶栏：LOGO / 战绩 / 每日签到 / 现金
        const top = _div('lobby-topbar');
        const logo = _div('lobby-logo', '烽火地带');
        logo.appendChild(_span('lobby-logo-sub', 'TACTICAL OPERATION · 战术行动'));
        top.appendChild(logo);
        this._recordEl = _div('lobby-record');
        top.appendChild(this._recordEl);
        this._dailyEl = _div('lobby-daily', '每日签到');
        this._dailyEl.dataset.act = 'daily';
        top.appendChild(this._dailyEl);
        this._cashEl = _div('lobby-cash');
        top.appendChild(this._cashEl);
        root.appendChild(top);

        // 主体面板 + 三页
        const body = _div('lobby-body');
        const panel = _div('lobby-panel');
        this._pgDeploy = _div('lobby-page');
        this._pgStash = _div('lobby-page');
        this._pgBench = _div('lobby-page');
        panel.append(this._pgDeploy, this._pgStash, this._pgBench);
        body.appendChild(panel);
        root.appendChild(body);

        // 底栏：页签 + 靶场入口
        const bottom = _div('lobby-bottombar');
        this._tabEls = [];
        ['1 · 出发', '2 · 仓库', '3 · 改枪台'].forEach((t, i) => {
            const tab = _div('lobby-tab' + (i === 0 ? ' lobby-tab-active' : ''), t);
            tab.dataset.act = 'tab'; tab.dataset.i = String(i);
            bottom.appendChild(tab);
            this._tabEls.push(tab);
        });
        const rangeBtn = _div('lobby-range-btn', 'G · 去靶场试枪');
        rangeBtn.dataset.act = 'range';
        bottom.appendChild(rangeBtn);
        root.appendChild(bottom);

        // 点击全走事件委托（innerHTML 重建后仍有效）
        root.addEventListener('click', (e) => {
            const t = e.target && e.target.closest('[data-act]');
            if (!t) return;
            const act = t.dataset.act, i = Number(t.dataset.i || 0);
            if (act === 'tab') this.setTab(i);
            else if (act === 'range') this._fireRange();
            else if (act === 'daily') this._checkIn();
            else if (act === 'entry') this._clickEntry(i);
            else if (act === 'cell') this._clickCell(i);
            else if (act === 'sellall') this._sellAll();
            else if (act === 'benchgun') this._clickBenchGun(i);
            else if (act === 'benchscope') this._clickBenchScope(i);
        });
    }

    _bindKeys() {
        this._onKeyDown = (e) => {
            if (!this.visible) return;
            if (this.hud && this.hud.resultVisible) return;   // 结算页按键归 HUD
            const c = e.code;
            if (c === 'Digit1' || c === 'Numpad1') { this.setTab(0); return; }
            if (c === 'Digit2' || c === 'Numpad2') { this.setTab(1); return; }
            if (c === 'Digit3' || c === 'Numpad3') { this.setTab(2); return; }
            if (c === 'KeyG') { this._fireRange(); return; }
            if (c === 'KeyC') { this._checkIn(); return; }   // C · 每日签到
            if (c === 'ArrowLeft') { this._move(-1, 0); e.preventDefault(); return; }
            if (c === 'ArrowRight') { this._move(1, 0); e.preventDefault(); return; }
            if (c === 'ArrowUp') { this._move(0, -1); e.preventDefault(); return; }
            if (c === 'ArrowDown') { this._move(0, 1); e.preventDefault(); return; }
            if ((c === 'Enter' || c === 'NumpadEnter') && !e.repeat) this._confirm();
        };
        window.addEventListener('keydown', this._onKeyDown);
    }

    /* ---------- 开关（联动 hud.uiBlocked + 盖场时藏局内 HUD） ---------- */
    /* 写实度评审 #r2：lobby 93% 渐变盖不住 z10 的 HUD DOM（背包格/残血/弹药
     * 幽灵穿透第一屏）。show 时藏 hud 根节点；toastBox 单独保留并提到
     * lobby 之上（资金不足/换装提示必须可见），hide 全量还原。 */
    _setHudVeil(on) {
        if (!this.hud || !this.hud.dom) return;
        const r = this.hud.dom;
        if (!r.hudRoot) return;
        r.hudRoot.style.visibility = on ? 'hidden' : '';
        if (r.toastBox) {
            r.toastBox.style.visibility = on ? 'visible' : '';
            r.toastBox.style.zIndex = on ? '40' : '';
        }
    }

    show() {
        this.visible = true;
        this._root.style.display = 'flex';
        if (this.hud) this.hud.uiBlocked = true;
        this._setHudVeil(true);
        this._refreshAll();
    }

    hide() {
        this.visible = false;
        this._root.style.display = 'none';   // display:none 释放点击（不触发指针锁定）
        this._setHudVeil(false);
        if (this.hud) this.hud.uiBlocked = false;
    }

    setTab(i) {
        const t = Math.max(0, Math.min(2, i | 0));
        if (t !== this._tab) this._beep(660, 0.05, 0.1);
        this._tab = t;
        this._refreshAll();
    }

    dispose() {
        window.removeEventListener('keydown', this._onKeyDown);
        if (this._cashRAF) cancelAnimationFrame(this._cashRAF);
    }

    /* ---------- 刷新 ---------- */
    _refreshAll() {
        this._renderTop();
        this._tabEls.forEach((el, i) => el.classList.toggle('lobby-tab-active', i === this._tab));
        this._pgDeploy.style.display = this._tab === 0 ? 'flex' : 'none';
        this._pgStash.style.display = this._tab === 1 ? 'flex' : 'none';
        this._pgBench.style.display = this._tab === 2 ? 'flex' : 'none';
        this._refreshTab();
    }

    _refreshTab() {
        if (this._tab === 0) this._renderDeploy();
        else if (this._tab === 1) this._renderStash();
        else this._renderBench();
    }

    _renderTop() {
        const s = this.stash.stats;
        this._recordEl.textContent =
            `出击 ${s.raids} · 撤离 ${s.extracts} · 阵亡 ${s.deaths} · 击杀 ${s.kills}`;
        // 每日签到按钮：可领琥珀呼吸高亮，已领灰化（日期键变化次日自动恢复）
        const can = this.stash.canCheckIn();
        this._dailyEl.className = 'lobby-daily ' + (can ? 'lobby-daily-yes' : 'lobby-daily-no');
        this._dailyEl.textContent = can ? `C · 每日签到 +₵${DAILY_REWARD.toLocaleString('en-US')}` : '今日已签到 ✓';
        this._tweenCash(Math.max(0, Math.round(this.stash.cash || 0)));
    }

    // 现金收付滚动 + 变动哔声（收绿付同色，只按方向响一声）
    _tweenCash(target) {
        if (target === this._cashShown) { this._cashEl.textContent = _fmt(target); return; }
        const up = target > this._cashShown;
        this._beep(up ? 980 : 520, 0.07, 0.14);
        if (this._cashRAF) cancelAnimationFrame(this._cashRAF);
        const from = this._cashShown, delta = target - from, t0 = performance.now();
        const DUR = 650;
        const step = (t) => {
            const k = Math.min(1, (t - t0) / DUR), e = 1 - Math.pow(1 - k, 3);
            this._cashShown = Math.round(from + delta * e);
            this._cashEl.textContent = _fmt(this._cashShown);
            this._cashRAF = k < 1 ? requestAnimationFrame(step) : 0;
        };
        this._cashRAF = requestAnimationFrame(step);
    }

    _cashFlash() {
        this._cashEl.classList.remove('lobby-cash-flash');
        void this._cashEl.offsetWidth;   // 重排重播动画
        this._cashEl.classList.add('lobby-cash-flash');
    }

    /* ---------- 每日签到 ---------- */
    _checkIn() {
        const got = this.stash.checkIn();
        if (got > 0) {
            this._toast(`签到成功 +${_fmt(got)} —— 明天再来`, 3200, '#ffd9a3');
            this._cashFlash();
        } else {
            this._toast('今天已经签到过了 —— 明天再来', 2600);
        }
    }

    _toast(text, dur, color) {
        if (this.hud && this.hud.toast) this.hud.toast(text, dur, color);
    }
    _beep(freq, dur, vol) {
        if (this.hud && this.hud.ui) this.hud.ui.beep(freq, dur, vol);
    }
    _errBeep() { this._beep(240, 0.14, 0.18); }

    /* ---------- 出发页 ---------- */
    /* 左区武器预览 + 数值读出，右区槽位/候选枪（微型数值条形）/出发。
     * 光标模型不变：[主槽0|副槽1|候选枪2..N+1|出发N+2]——条目索引与
     * data-act 委托一字未动（写实度评审 #06③：整组折叠会破坏冻结的
     * 单轴光标契约，改用视觉降权替代——见候选枪行内联样式）。 */
    _renderDeploy() {
        const pg = this._pgDeploy, st = this.stash, lo = st.loadout;
        pg.innerHTML = '';
        const nEntries = 3 + GUN_IDS.length;   // 2槽 + N枪 + 出发
        this._cur0 = ((this._cur0 % nEntries) + nEntries) % nEntries;

        const cols = _div('lobby-deploy-cols');

        /* -- 左区：选中武器剪影 + 数值徽章 -- */
        const prev = _div('lobby-preview');
        const cv = document.createElement('canvas');
        cv.className = 'lobby-preview-cv';
        cv.width = 340; cv.height = 150;
        const selId = this._cur0 <= 1
            ? lo[this._cur0 === 0 ? 'primary' : 'secondary']
            : (this._cur0 < 2 + GUN_IDS.length ? GUN_IDS[this._cur0 - 2] : lo.primary);
        _drawSilhouette(cv, selId);
        prev.appendChild(cv);
        const sel = gunInfo(selId) || {};
        const selName = _div('lobby-preview-name',
            `${sel.name || selId || '——'}${st.guns.owned.includes(selId) ? '' : '（未拥有）'}`);
        prev.appendChild(selName);
        const chips = _div('lobby-stat-chips');
        [['伤害', sel.dmg ?? '——'],
            ['射速', sel.cd ? `${(1 / sel.cd).toFixed(1)}/s` : '——'],
            ['弹匣', sel.mag ?? '——'],
            ['射程', sel.range ? `${sel.range}m` : '——'],
            ['身价', st.guns.owned.includes(selId) ? '已拥有' : _fmt(sel.price || 0)],
        ].forEach(([k, v]) => {
            const chip = _div('lobby-stat-chip');
            chip.appendChild(_span('k', k));
            chip.appendChild(_span('v', String(v)));
            chips.appendChild(chip);
        });
        prev.appendChild(chips);
        cols.appendChild(prev);

        /* -- 右区：槽位 + 候选枪 + 出发 -- */
        const main = _div('lobby-main');
        const slots = _div('lobby-slots');
        [['primary', '主武器 · 1'], ['secondary', '副武器 · 2']].forEach(([slot, label], i) => {
            const gun = gunInfo(lo[slot]);
            const card = _div('lobby-slot'
                + (this._slotFocus === slot ? ' lobby-slot-focus' : '')
                + (this._cur0 === i ? ' lobby-sel' : ''));
            card.dataset.act = 'entry'; card.dataset.i = String(i);
            card.appendChild(_div('lobby-slot-label', label));
            card.appendChild(_div('lobby-slot-gun', gun ? (gun.name || slot) : '——'));
            card.appendChild(_div('lobby-slot-desc', gun ? (gun.desc || '') : '（空）'));
            if (this._slotFocus === slot) card.appendChild(_div('lobby-slot-tag', '◀ 装入此槽'));
            slots.appendChild(card);
        });
        main.appendChild(slots);

        const ownedN = GUN_IDS.filter((id) => st.guns.owned.includes(id)).length;
        const list = _div('lobby-guns');
        list.appendChild(_div('lobby-guns-title',
            `候选枪（已拥有 ${ownedN}/${GUN_IDS.length}）· 未拥有即出发布局焦点`));
        GUN_IDS.forEach((id, gi) => {
            const g = gunInfo(id) || {};
            const i = 2 + gi;
            const owned = st.guns.owned.includes(id);
            const row = _div('lobby-gun-row'
                + (owned ? '' : ' lobby-gun-locked')
                + (this._cur0 === i ? ' lobby-sel' : ''));
            row.dataset.act = 'entry'; row.dataset.i = String(i);
            if (owned) row.style.opacity = '0.78';   // 已拥有降权（评审 #06③ 适配）
            else row.style.borderLeft = '3px solid var(--fps-accent, #ffb35c)';
            row.appendChild(_span('lobby-gun-name', g.name || id));
            row.appendChild(_span('lobby-gun-desc', g.desc || ''));
            /* 微型数值条形：伤害（琥珀，满标 100）/ 射速（绿，满标 smg 12.5发/s） */
            const bars = _div('lobby-gun-bars');
            const bar = (frac, color) => {
                const b = _div('lobby-gun-bar');
                const fill = document.createElement('i');
                fill.style.width = `${Math.round(Math.max(0, Math.min(1, frac)) * 100)}%`;
                fill.style.background = color;
                b.appendChild(fill);
                return b;
            };
            bars.appendChild(bar((g.dmg || 0) / 100, '#ffb35c'));
            bars.appendChild(bar((g.cd ? 1 / g.cd : 0) / 12.5, '#7ee2a8'));
            row.appendChild(bars);
            row.appendChild(_span('lobby-gun-price',
                owned ? '已拥有' : _fmt(g.price || 0)));
            list.appendChild(row);
        });
        main.appendChild(list);

        const di = 2 + GUN_IDS.length;
        const btn = _div('lobby-deploy-btn'
            + (this._cur0 === di ? ' lobby-sel lobby-deploy-btn-sel' : ''), '▶ 出 发');
        btn.dataset.act = 'entry'; btn.dataset.i = String(di);
        main.appendChild(btn);
        main.appendChild(_div('lobby-hint', '←/→ 选择 · 回车 确认/出发 · G 靶场 · 1/2/3 切页签'));
        cols.appendChild(main);

        pg.appendChild(cols);
    }

    _confirmDeploy() {
        const i = this._cur0;
        if (i <= 1) {   // 槽：聚焦为装入目标
            this._slotFocus = i === 0 ? 'primary' : 'secondary';
            this._beep(740, 0.05, 0.12);
            this._refreshTab();
            return;
        }
        const gi = i - 2;
        if (gi < GUN_IDS.length) { this._loadGun(GUN_IDS[gi]); return; }
        this._fireDeploy();
    }

    _loadGun(id) {
        const st = this.stash;
        if (!st.guns.owned.includes(id)) { this._toast('尚未拥有该枪械'); this._errBeep(); return; }
        const other = this._slotFocus === 'primary' ? 'secondary' : 'primary';
        if (st.loadout[other] === id) { this._toast('主副武器不可相同'); this._errBeep(); return; }
        if (this._slotFocus === 'primary') st.setLoadout(id, st.loadout.secondary);
        else st.setLoadout(st.loadout.primary, id);
        this._slotFocus = other;   // 装完自动跳另一槽（顺手配对）
        this._beep(880, 0.06, 0.14);
    }

    _fireDeploy() {
        const lo = this.stash.loadout;
        if (!lo.primary || !lo.secondary || lo.primary === lo.secondary) {
            this._toast('主副武器不可相同'); this._errBeep(); return;
        }
        this._beep(880, 0.1, 0.18);
        this.hide();   // 先收大厅再部署（释放 uiBlocked / 显示层）
        if (this.onDeploy) {
            this.onDeploy({
                primary: lo.primary, secondary: lo.secondary,
                scopes: { ...(this.stash.guns.scopes || {}) },
            });
        }
    }

    _fireRange() {
        this._beep(740, 0.08, 0.15);
        this.hide();
        if (this.onRange) this.onRange();
    }

    /* ---------- 仓库页 ---------- */
    _renderStash() {
        const pg = this._pgStash, st = this.stash;
        pg.innerHTML = '';
        const items = st.items;
        if (!items.length) {
            pg.appendChild(_div('lobby-cell-empty', '仓库空空如也 —— 出发搜刮，活着带回来'));
            this._cur1 = 0;
        } else {
            this._cur1 = Math.max(0, Math.min(this._cur1, items.length - 1));
            const grid = _div('lobby-grid');
            items.forEach((it, i) => {
                const r = rarInfo(it.rarity);
                const cell = _div('lobby-cell'
                    + (r.glow ? ' lobby-cell-rainbow' : '')
                    + (i === this._cur1 ? ' lobby-sel' : ''));
                /* 品质墙（写实度评审 #07d）：品质渐变底 + 品质色文字 +
                 * 档位辉光（紫 3+ 内辉光，金 4/红 5 叠外发光，彩 6 走呼吸动画）
                 * ——对标三角洲「一眼锁定金色」的辨识节奏 */
                cell.style.borderColor = r.color;
                cell.style.background =
                    `linear-gradient(180deg, ${r.color}2e, rgba(24,30,24,.55) 72%)`;
                if (!r.glow) {
                    let shadow = '';
                    if (it.rarity >= 3) shadow += `inset 0 0 14px ${r.color}59`;
                    if (it.rarity >= 4) shadow += `, 0 0 12px ${r.color}66`;
                    if (shadow) cell.style.boxShadow = shadow;
                }
                cell.dataset.act = 'cell'; cell.dataset.i = String(i);
                /* 图标 = 程序化剪影（shape 同 3D 掉落物语义）染品质色，
                 * 不再用系统 emoji（跨平台不一致 + 卡通风与军事 UI 相斥） */
                const icon = _div('lobby-cell-icon');
                icon.style.cssText =
                    'width:30px;height:30px;margin:0 auto;'
                    + `background:center/contain no-repeat url("${itemIconUrl(it, r.color)}");`;
                icon.title = it.name || '战利品';
                cell.appendChild(icon);
                const nameEl = _div('lobby-cell-name', it.name || '战利品');
                nameEl.style.color = r.color;
                cell.appendChild(nameEl);
                const valEl = _div('lobby-cell-value', _fmt(it.value || 0));
                valEl.style.color = r.color;
                cell.appendChild(valEl);
                grid.appendChild(cell);
            });
            pg.appendChild(grid);
        }
        const foot = _div('lobby-stash-foot');
        foot.appendChild(_div('lobby-total',
            `总计 ${_fmt(st.totalValue())} · ${items.length}/12 格`));
        const sellBtn = _div('lobby-sellall' + (items.length ? '' : ' lobby-gun-locked'), '一键变卖全部');
        sellBtn.dataset.act = 'sellall';
        foot.appendChild(sellBtn);
        pg.appendChild(foot);

        const row = _div('lobby-gunrow');
        row.appendChild(_div('lobby-gunrow-title', '枪械库'));
        st.guns.owned.forEach((id) => {
            const g = gunInfo(id) || {};
            const sid = st.scopeOf(id);
            const sc = sid ? scopeById(sid) : null;
            const sName = sc ? ((sc.info && sc.info.name) || sid) : '机瞄';
            row.appendChild(_span('lobby-gunrow-item', `${(g.name || id)} · ${sName}`));
        });
        pg.appendChild(row);
        pg.appendChild(_div('lobby-hint', '↑↓←→ 选格 · 回车 变卖选中 · 点「一键变卖」清仓'));
    }

    _sellSelected() {
        const items = this.stash.items;
        if (!items.length) return;
        const it = items[Math.max(0, Math.min(this._cur1, items.length - 1))];
        if (!it) return;
        const v = this.stash.sellItem(it.uid);
        if (v > 0) {
            this._beep(980, 0.07, 0.15);
            this._toast(`变卖 ${it.name || '战利品'} +${_fmt(v)}`);
        }
    }

    _sellAll() {
        const st = this.stash;
        if (!st.items.length) { this._errBeep(); return; }
        let n = 0, sum = 0;
        for (const it of st.items.slice()) {
            const v = st.sellItem(it.uid);
            if (v > 0) { n++; sum += v; }
        }
        this._beep(980, 0.09, 0.16);
        this._toast(`一键变卖 ${n} 件 +${_fmt(sum)}`, 3600);
    }

    /* ---------- 改枪台页 ---------- */
    _renderBench() {
        const pg = this._pgBench, st = this.stash;
        pg.innerHTML = '';
        this._gunIdx = ((this._gunIdx % GUN_IDS.length) + GUN_IDS.length) % GUN_IDS.length;
        const gunId = GUN_IDS[this._gunIdx];
        const gun = gunInfo(gunId) || {};

        const wrap = _div('lobby-bench');
        const left = _div('lobby-bench-col');
        left.appendChild(_div('lobby-bench-title', '枪械'));
        GUN_IDS.forEach((id, i) => {
            const g = gunInfo(id) || {};
            const sid = st.scopeOf(id);
            const sc = sid ? scopeById(sid) : null;
            const rowEl = _div('lobby-bench-item'
                + (this._col === 0 && i === this._gunIdx ? ' lobby-sel' : ''));
            rowEl.dataset.act = 'benchgun'; rowEl.dataset.i = String(i);
            rowEl.appendChild(_span('lobby-bench-name', g.name || id));
            rowEl.appendChild(_span('lobby-bench-tag',
                sc ? ((sc.info && sc.info.name) || sid) : '机瞄'));
            left.appendChild(rowEl);
        });
        wrap.appendChild(left);

        const right = _div('lobby-bench-col');
        right.appendChild(_div('lobby-bench-title', `瞄具 —— 为「${gun.name || gunId}」选配`));
        const list = scopeList();
        this._scopeIdx = ((this._scopeIdx % list.length) + list.length) % list.length;
        /* desc 去重（写实度评审 #03a）：SCOPES 的 desc 自带倍率前缀
         * （'1.5× · 单圈红点…'/'5×/8× 滚轮可调…'），程序化 zoomTxt 再拼一遍
         * 即重复且超宽触发 ellipsis——剥掉 desc 开头的倍率段再拼 */
        const dedupeDesc = (info) => (info.desc || '')
            .replace(/^\d+(?:\.\d+)?×(?:\/\d+(?:\.\d+)?×)*\s*·?\s*/, '');
        list.forEach((s, i) => {
            const info = s.info || {};
            const rowEl = _div('lobby-bench-item'
                + (this._col === 1 && i === this._scopeIdx ? ' lobby-sel' : ''));
            rowEl.dataset.act = 'benchscope'; rowEl.dataset.i = String(i);
            const zoomTxt = Array.isArray(info.zooms)
                ? info.zooms.map((z) => `${z}×`).join('/')
                : `${info.zoom || 1}×`;
            rowEl.appendChild(_span('lobby-bench-name',
                `${(info.name || s.id)}（${zoomTxt} · ${dedupeDesc(info)}）`));
            // 状态标签：默认 / 已装此枪 / 装于他枪（单持提示）/ 已拥有 / 价格
            let tag, cls = 'lobby-bench-tag';
            if (s.id === 'iron') tag = '默认 · 卸下';
            else if (st.scopeOf(gunId) === s.id) tag = '● 已装';
            else {
                const otherGun = GUN_IDS.find((gid) =>
                    gid !== gunId && st.scopeOf(gid) === s.id);
                if (otherGun) tag = `装于 ${(gunInfo(otherGun) || {}).name || otherGun}`;
                else if (st.ownsScope(s.id)) tag = '已拥有 · 回车换装';
                else { tag = _fmt(info.price || 0); cls += ' lobby-bench-price'; }
            }
            rowEl.appendChild(_span(cls, tag));
            right.appendChild(rowEl);
        });
        wrap.appendChild(right);
        pg.appendChild(wrap);
        pg.appendChild(_div('lobby-hint', '←→ 换列 · ↑↓ 选项 · 回车 购买/换装/卸下（瞄具单持：同镜装他枪自动卸下）'));
    }

    _benchConfirm() {
        const gunId = GUN_IDS[this._gunIdx];
        if (this._col === 0) { this._beep(740, 0.05, 0.12); return; }   // 左列=选枪（右侧联动）
        const list = scopeList();
        const entry = list[this._scopeIdx];
        if (!entry) return;
        const sid = entry.id;
        const info = entry.info || {};
        if (sid === 'iron') {
            this.stash.equipScope(gunId, null);
            this._toast('已卸下瞄具 —— 恢复机瞄');
            return;
        }
        if (this.stash.scopeOf(gunId) === sid) { this._toast('该瞄具已装在此枪上'); return; }
        if (!this.stash.ownsScope(sid)) {
            if (!this.stash.buyScope(sid)) {
                this._toast('资金不足 —— 先回仓库变卖战利品', 2600);
                this._cashFlash(); this._errBeep();
                return;
            }
            this.stash.equipScope(gunId, sid);
            this._toast(`已购买并装配：${info.name || sid}`);
            return;
        }
        this.stash.equipScope(gunId, sid);
        this._toast(`已换装：${info.name || sid}`);
    }

    /* ---------- 光标移动 / 确认（键盘主路径，鼠标点选同源） ---------- */
    _move(dh, dv) {
        if (this._tab === 0) {
            const n = 3 + GUN_IDS.length;
            if (dh) this._cur0 = (this._cur0 + dh + n) % n;
        } else if (this._tab === 1) {
            const n = this.stash.items.length;
            if (!n) return;
            const COLS = 5;
            let r = Math.floor(this._cur1 / COLS), c = this._cur1 % COLS;
            c = (c + (dh || 0) + COLS) % COLS;
            r = Math.max(0, Math.min(Math.floor((n - 1) / COLS), r + (dv || 0)));
            this._cur1 = Math.min(n - 1, r * COLS + c);
        } else {
            if (dh) this._col = this._col ? 0 : 1;
            if (dv) {
                if (this._col === 0) {
                    this._gunIdx = (this._gunIdx + dv + GUN_IDS.length) % GUN_IDS.length;
                } else {
                    const n = scopeList().length;
                    this._scopeIdx = (this._scopeIdx + dv + n) % n;
                }
            }
        }
        this._beep(700, 0.03, 0.07);
        this._refreshTab();
    }

    _confirm() {
        if (this._tab === 0) this._confirmDeploy();
        else if (this._tab === 1) this._sellSelected();
        else this._benchConfirm();
    }

    /* ---------- 鼠标点选（首次点=移动光标，再点同项=执行；终端按钮直执行） ---------- */
    _clickEntry(i) {
        if (this._cur0 !== i) {
            this._cur0 = i;
            if (i <= 1) this._slotFocus = i === 0 ? 'primary' : 'secondary';
            this._refreshTab();
            return;
        }
        this._confirmDeploy();
    }

    _clickCell(i) {
        const n = this.stash.items.length;
        if (!n) return;
        if (this._cur1 !== i) { this._cur1 = Math.max(0, Math.min(i, n - 1)); this._refreshTab(); return; }
        this._sellSelected();
    }

    _clickBenchGun(i) {
        this._col = 0;
        if (this._gunIdx !== i) { this._gunIdx = i; this._refreshTab(); return; }
        this._benchConfirm();
    }

    _clickBenchScope(i) {
        this._col = 1;
        if (this._scopeIdx !== i) { this._scopeIdx = i; this._refreshTab(); return; }
        this._benchConfirm();
    }
}
