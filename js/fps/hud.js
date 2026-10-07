/* ============================================================
 * js/fps/hud.js —— 战术 HUD（DOM 层）+ UI/环境音（WebAudio 全合成）
 * 依赖注入：new HUD(camera)。fps.html 按 interfaces 提供 DOM id 清单；
 * 缺失的 id 会 console.warn 并动态补建，保证功能不断（照 risk 表约定）。
 * 布局/进度/衰减等每帧变化的视觉走内联样式；配色与静态形状走
 * .hud-* class（由 css/fps.css 定皮肤）。构造时向 <head> 最前插入一份
 * 保守的兜底样式表——特异性下它永远输给 css/fps.css，可整体覆盖。
 * ============================================================ */
import * as THREE from 'three';

/* ==== 1. UIAudio：UI 哔声 / 靶场命中叮 / 倒靶闷响 / 低血心跳 / 环境风 ==== */
/* 写法照 js/audio.js 先例：AudioContext 延迟到首次用户手势（自动播放策略），
 * 噪声用循环 buffer，持续声（风）用 gain 包络，短音用一次性振荡器。 */
export class UIAudio {
    constructor() {
        this.ctx = null;
        this.master = null;
        this.muted = false;
        this._windGain = null;
        this._gustPhase = Math.random() * 6.28;
    }

    // 必须在用户手势里调用一次（main 挂 keydown/pointerdown；HUD 自己也挂了兜底）
    ensure() {
        if (this.ctx) {
            if (this.ctx.state === 'suspended') this.ctx.resume();
            return;
        }
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        const ctx = this.ctx = new AC();
        const master = this.master = ctx.createGain();
        master.gain.value = this.muted ? 0 : 0.9;
        master.connect(ctx.destination);

        // --- 环境风：白噪声 → 低通 → 增益（叠加两个慢正弦做阵风起伏） ---
        const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
        const nd = noiseBuf.getChannelData(0);
        for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
        this._noiseBuf = noiseBuf;
        const windSrc = ctx.createBufferSource();
        windSrc.buffer = noiseBuf; windSrc.loop = true;
        const windLP = ctx.createBiquadFilter();
        windLP.type = 'lowpass'; windLP.frequency.value = 340; windLP.Q.value = 0.6;
        this._windGain = ctx.createGain(); this._windGain.gain.value = 0;
        windSrc.connect(windLP); windLP.connect(this._windGain);
        this._windGain.connect(master);
        windSrc.start();
        this._windGain.gain.setTargetAtTime(0.04, ctx.currentTime, 1.2);   // 缓起
    }

    setMuted(m) {
        this.muted = m;
        if (this.master) this.master.gain.setTargetAtTime(m ? 0 : 0.9, this.ctx.currentTime, 0.05);
    }

    // 阵风包络：两个不同频率正弦叠加，setTargetAtTime 平滑逼近
    update(dt) {
        if (!this.ctx || this.muted) return;
        this._gustPhase += dt * 0.35;
        const g = 0.032
            + 0.018 * (0.5 + 0.5 * Math.sin(this._gustPhase))
            + 0.012 * (0.5 + 0.5 * Math.sin(this._gustPhase * 2.37 + 1.7));
        this._windGain.gain.setTargetAtTime(g, this.ctx.currentTime, 0.45);
    }

    // 通用短音
    _tone(freq, dur, vol, type, when, slideTo) {
        if (!this.ctx || this.muted) return;
        const t = this.ctx.currentTime + (when || 0);
        const o = this.ctx.createOscillator();
        o.type = type || 'sine'; o.frequency.setValueAtTime(freq, t);
        if (slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, t + dur);
        const g = this.ctx.createGain();
        g.gain.setValueAtTime(vol, t);
        g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
        o.connect(g); g.connect(this.master);
        o.start(t); o.stop(t + dur + 0.03);
    }

    beep(freq, dur, vol) { this._tone(freq || 880, dur || 0.07, vol || 0.18, 'square'); }

    // 靶场命中「叮」：基音 + 八度泛音，内环更亮
    ding(bright) {
        this._tone(bright ? 1568 : 1245, 0.28, 0.16, 'triangle');
        this._tone(bright ? 3136 : 2490, 0.16, 0.05, 'sine', 0.01);
    }

    // 倒靶闷响：低频下坠 + 短噪声垫；delay 为相对当前的延迟秒数
    thud(delay) {
        const d = delay || 0;
        this._tone(150, 0.22, 0.22, 'sine', d, 55);
        if (!this.ctx || this.muted) return;
        const t = this.ctx.currentTime + d;
        const src = this.ctx.createBufferSource(); src.buffer = this._noiseBuf;
        const f = this.ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 320;
        const g = this.ctx.createGain();
        g.gain.setValueAtTime(0.12, t);
        g.gain.exponentialRampToValueAtTime(0.0008, t + 0.18);
        src.connect(f); f.connect(g); g.connect(this.master);
        src.start(t, Math.random()); src.stop(t + 0.2);
    }

    // 低血心跳：两连低鼓
    heartbeat() {
        this._tone(58, 0.12, 0.26, 'sine', 0, 40);
        this._tone(52, 0.10, 0.18, 'sine', 0.16, 38);
    }
}

/* ==== 2. 兜底样式：插入 head 最前，css/fps.css 永远可覆盖 ==== */
const FALLBACK_CSS = `
.hud-root{position:fixed;inset:0;pointer-events:none;z-index:10;user-select:none;
  font-family:Menlo,Consolas,'SF Mono',monospace;color:#d8ded2;letter-spacing:.04em}
.hud-root>div{position:absolute}
.hud-crosshair{left:50%;top:50%;width:0;height:0}
.hud-ch-dot{position:absolute;left:-1.5px;top:-1.5px;width:3px;height:3px;background:#d8ffea;
  box-shadow:0 0 3px rgba(0,0,0,.8)}
.hud-ch-line{position:absolute;left:-1px;top:-5px;width:2px;height:10px;background:#d8ffea;
  box-shadow:0 0 3px rgba(0,0,0,.8)}
.hud-hitmarker{left:50%;top:50%;width:0;height:0;opacity:0}
.hud-hit-line{position:absolute;width:2px;height:9px;background:#fff;box-shadow:0 0 4px rgba(0,0,0,.9)}
.hud-hitmarker.hud-kill .hud-hit-line{background:#ff5941;height:12px}
.hud-hitmarker.hud-head .hud-hit-line{background:#ffd257}
.hud-ammo-box{right:26px;bottom:22px;text-align:right;background:rgba(10,14,10,.55);
  border:1px solid rgba(216,222,210,.25);padding:8px 14px 6px;min-width:120px}
.hud-ammo-cur{font-size:34px;font-weight:700;line-height:1;font-variant-numeric:tabular-nums}
.hud-ammo-cur.hud-low{color:#ff7a45}
.hud-ammo-reserve{font-size:14px;opacity:.75;font-variant-numeric:tabular-nums}
.hud-reload-hint{right:26px;bottom:96px;width:150px;text-align:center;font-size:12px;opacity:.9}
.hud-reload-track{height:3px;background:rgba(216,222,210,.2);margin-top:4px}
.hud-reload-fill{height:100%;width:0;background:#ffb35c}
.hud-health-bar{left:26px;bottom:30px;width:220px;height:10px;background:rgba(10,14,10,.6);
  border:1px solid rgba(216,222,210,.3)}
.hud-health-fill{height:100%;width:100%;background:#9fb98a;transition:width .15s}
.hud-health-bar.hud-low .hud-health-fill{background:#c74a3c}
.hud-health-num{left:26px;bottom:44px;font-size:20px;font-variant-numeric:tabular-nums}
.hud-phase-card{left:50%;top:18px;transform:translateX(-50%);text-align:center;background:rgba(10,14,10,.5);
  border:1px solid rgba(216,222,210,.22);padding:6px 22px;min-width:280px}
.hud-phase-name{font-size:13px;letter-spacing:.35em;color:#ffb35c}
.hud-objective-text{font-size:12px;opacity:.85;margin-top:2px}
.hud-phase-card.hud-flash{animation:hudFlash .5s ease-out}
@keyframes hudFlash{0%{background:rgba(255,179,92,.4)}100%{background:rgba(10,14,10,.5)}}
.hud-world-marker{opacity:0}
.hud-marker-diamond{position:absolute;left:-7px;top:-7px;width:14px;height:14px;
  border:2px solid #7ee2a8;transform:rotate(45deg);background:rgba(126,226,168,.12)}
.hud-marker-arrow{position:absolute;left:-8px;top:-8px;width:0;height:0;display:none;
  border-left:7px solid transparent;border-right:7px solid transparent;
  border-bottom:12px solid #7ee2a8}
.hud-marker-label{position:absolute;top:14px;left:50%;transform:translateX(-50%);
  font-size:12px;color:#7ee2a8;white-space:nowrap;text-shadow:0 0 3px #000}
.hud-marker-dist{position:absolute;top:-26px;left:50%;transform:translateX(-50%);
  font-size:12px;white-space:nowrap;text-shadow:0 0 3px #000}
.hud-compass-strip{left:50%;top:56px;transform:translateX(-50%);width:340px;height:34px;
  background-repeat:repeat-x;background-size:1440px 34px;opacity:.9;
  -webkit-mask-image:linear-gradient(90deg,transparent,#000 18%,#000 82%,transparent);
  mask-image:linear-gradient(90deg,transparent,#000 18%,#000 82%,transparent)}
.hud-compass-center{position:absolute;left:50%;top:0;width:2px;height:9px;background:#ffb35c;
  transform:translateX(-50%)}
.hud-compass-deg{left:50%;top:94px;transform:translateX(-50%);font-size:13px;
  color:#ffb35c;font-variant-numeric:tabular-nums;text-shadow:0 0 3px #000}
.hud-killfeed{right:24px;top:90px;text-align:right;font-size:13px;max-width:320px}
.hud-kill-item{margin:3px 0;padding:3px 10px;background:rgba(10,14,10,.55);
  border-right:2px solid #ffb35c;color:#e8ecdf;white-space:nowrap}
.hud-damage-vignette{inset:0;opacity:0;transition:opacity .5s;pointer-events:none;
  background:radial-gradient(ellipse at center,transparent 52%,rgba(150,20,10,.55) 100%)}
.hud-damage-vignette.hud-show{opacity:1;transition:opacity .08s}
.hud-damage-vignette.hud-lowblood{opacity:.75;transition:opacity .8s}
.hud-dmg-dir{left:50%;top:50%;width:0;height:0;opacity:0}
.hud-dmg-dir-mark{position:absolute;left:-14px;top:-86px;width:28px;height:10px;
  background:rgba(255,70,50,.85);clip-path:polygon(0 100%,50% 0,100% 100%)}
.hud-extract-bar{left:50%;bottom:120px;transform:translateX(-50%);width:260px;height:8px;
  background:rgba(10,14,10,.6);border:1px solid rgba(126,226,168,.5);display:none}
.hud-extract-fill{height:100%;width:0;background:#7ee2a8}
.hud-extract-label{position:absolute;top:-20px;width:100%;text-align:center;font-size:12px;color:#7ee2a8}
.hud-intel-ring{left:50%;top:58%;transform:translate(-50%,-50%);width:96px;height:96px;display:none}
.hud-intel-svg{width:96px;height:96px;transform:rotate(-90deg)}
.hud-intel-bg{fill:none;stroke:rgba(216,222,210,.25);stroke-width:6}
.hud-intel-fg{fill:none;stroke:#ffb35c;stroke-width:6;stroke-linecap:round}
.hud-intel-text{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
  font-size:26px;color:#ffb35c;font-weight:700}
.hud-toast-box{left:50%;bottom:170px;transform:translateX(-50%);text-align:center;pointer-events:none}
.hud-toast{margin:4px auto;padding:5px 16px;background:rgba(10,14,10,.72);
  border:1px solid rgba(216,222,210,.3);font-size:13px;width:max-content;max-width:70vw}
.hud-menu-root,.hud-result-root,.hud-help-overlay{position:fixed;inset:0;z-index:20;
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;
  background:rgba(6,8,6,.82);pointer-events:auto;font-family:inherit;color:#d8ded2}
.hud-menu-title{font-size:26px;letter-spacing:.5em;color:#ffb35c;margin-bottom:6px}
.hud-menu-sub{font-size:12px;opacity:.6;letter-spacing:.2em;margin-bottom:10px}
.hud-btn{min-width:240px;padding:10px 26px;background:rgba(24,30,24,.85);
  border:1px solid rgba(216,222,210,.35);color:#d8ded2;font-size:15px;letter-spacing:.3em;
  cursor:pointer;text-align:center;font-family:inherit}
.hud-btn.hud-btn-focus{border-color:#ffb35c;color:#ffb35c;background:rgba(60,48,24,.85)}
.hud-menu-keys{font-size:12px;opacity:.65;line-height:1.9;margin-top:14px;white-space:pre;text-align:left}
.hud-result-title{font-size:30px;letter-spacing:.5em;margin-bottom:4px}
.hud-result-title.hud-win{color:#7ee2a8}.hud-result-title.hud-lose{color:#ff5941}
.hud-rank{font-size:64px;font-weight:700;color:#ffb35c;margin:6px 0}
.hud-result-stats{font-size:14px;line-height:2;opacity:.9;text-align:center;font-variant-numeric:tabular-nums}
.hud-help-overlay{background:rgba(6,8,6,.9);font-size:14px;line-height:2.1}
.hud-help-title{font-size:20px;letter-spacing:.4em;color:#ffb35c;margin-bottom:8px}
.hud-help-body{white-space:pre;text-align:left}
.hud-deploy-veil{position:fixed;inset:0;background:#000;z-index:15;pointer-events:none;
  opacity:0;transition:opacity .4s}
.hud-brief-card{left:50%;top:34%;transform:translateX(-50%);text-align:center;
  background:rgba(10,14,10,.78);border:1px solid rgba(255,179,92,.5);padding:18px 40px;max-width:80vw}
.hud-brief-title{font-size:15px;letter-spacing:.4em;color:#ffb35c}
.hud-brief-sub{font-size:13px;margin-top:8px;opacity:.85;line-height:1.8}
.hud-objective-detail{left:50%;top:140px;transform:translateX(-50%);display:none;
  background:rgba(10,14,10,.72);border:1px solid rgba(216,222,210,.28);
  padding:10px 24px;font-size:13px;line-height:1.9;max-width:70vw;white-space:pre-line;text-align:center}
.hud-range-stats{right:26px;top:150px;text-align:right;font-size:14px;line-height:1.9;
  background:rgba(10,14,10,.55);border:1px solid rgba(216,222,210,.25);padding:8px 14px;
  font-variant-numeric:tabular-nums;display:none}
.hud-danger-banner{left:50%;top:132px;transform:translateX(-50%);padding:5px 26px;
  background:rgba(96,18,8,.6);border:1px solid rgba(255,116,64,.8);color:#ff9a6a;
  font-size:13px;letter-spacing:.3em;animation:hudDangerPulse 1.5s ease-in-out infinite}
.hud-danger-vignette{inset:0;pointer-events:none;
  background:radial-gradient(ellipse at center,transparent 58%,rgba(200,60,20,.28) 100%)}
@keyframes hudDangerPulse{0%,100%{box-shadow:0 0 4px rgba(255,116,64,.2)}
  50%{box-shadow:0 0 16px rgba(255,116,64,.65)}}
.hud-bag{left:26px;bottom:70px;background:rgba(10,14,10,.55);
  border:1px solid rgba(216,222,210,.25);padding:6px 10px 5px}
.hud-bag-num{font-size:12px;letter-spacing:.12em;margin-bottom:4px;font-variant-numeric:tabular-nums}
.hud-bag-pips{display:flex;gap:3px}
.hud-bag-pip{width:8px;height:8px;background:rgba(216,222,210,.16);
  border:1px solid rgba(216,222,210,.25)}
.hud-bag-pip-full{background:#ffb35c;border-color:#ffb35c}
.hud-weapon-slots{right:26px;bottom:136px;display:flex;flex-direction:column;gap:4px;align-items:flex-end}
.hud-wslot{display:flex;gap:8px;align-items:center;padding:4px 10px;background:rgba(10,14,10,.55);
  border:1px solid rgba(216,222,210,.22);border-right:3px solid rgba(216,222,210,.22);
  font-size:12px;letter-spacing:.08em}
.hud-wslot-key{color:#7ee2a8}
.hud-wslot-active{border-color:rgba(255,179,92,.85);border-right-color:#ffb35c;color:#ffd9a3}
`;

/* ==== 3. 罗盘刻度条：Canvas 程序化生成（零外部资源） ==== */
const COMPASS_PX_PER_DEG = 4;   // 360° = 1440px，repeat-x 循环

function makeCompassStrip() {
    const W = 360 * COMPASS_PX_PER_DEG, H = 34;
    const cv = document.createElement('canvas');
    cv.width = W; cv.height = H;
    const c = cv.getContext('2d');
    c.clearRect(0, 0, W, H);
    const CARD = { 0: 'N', 45: 'NE', 90: 'E', 135: 'SE', 180: 'S', 225: 'SW', 270: 'W', 315: 'NW' };
    for (let deg = 0; deg < 360; deg += 5) {
        const x = deg * COMPASS_PX_PER_DEG;
        const major = deg % 45 === 0, mid = deg % 15 === 0;
        c.fillStyle = major ? '#ffd9a3' : (mid ? 'rgba(216,222,210,.9)' : 'rgba(216,222,210,.45)');
        const len = major ? 14 : (mid ? 10 : 6);
        c.fillRect(x - 1, H - 2 - len, 2, len);
        if (major) {
            c.fillStyle = '#ffd9a3';
            c.font = 'bold 12px Menlo, monospace';
            c.textAlign = 'center';
            c.fillText(CARD[deg], x, H - 20);
        } else if (deg % 30 === 0) {
            c.fillStyle = 'rgba(216,222,210,.7)';
            c.font = '10px Menlo, monospace';
            c.textAlign = 'center';
            c.fillText(String(deg), x, H - 20);
        }
    }
    return cv.toDataURL();
}

/* ==== 4. HUD 类 ==== */
/* fps.html 必须提供的 29 个 DOM id（interfaces 清单）；缺失时 warn+自动补建。
 * 回调字段（main.js 绑定）：onSelectMission / onSelectRange / onRetry /
 * onBackToMenu / onMuteToggle(muted)。 */
export class HUD {
    constructor(camera) {
        this.camera = camera;
        this.muted = false;
        this.ui = new UIAudio();
        this.onSelectMission = null;
        this.onSelectRange = null;
        this.onRetry = null;
        this.onBackToMenu = null;
        this.onMuteToggle = null;

        this.menuVisible = false;
        this.resultVisible = false;
        this.helpVisible = false;
        this.uiBlocked = false;      // 大厅盖场时屏蔽 H/Tab 全局键（M 静音保留）
        this._menuIdx = 0;

        // 衰减效果统一用 performance.now() 时间戳，update(dt) 不调也不致卡死
        this._hit = { until: 0, dur: 1 };
        this._dmgDirs = [];          // 受击方向箭头池 [{el, until}]
        this._dmgVigTimer = 0;
        this._lowBlood = false;
        this._nextHeartbeat = 0;
        this._compassW = 340;
        this._markerDist = '';

        this._v = new THREE.Vector3();
        this._camDir = new THREE.Vector3();
        this._toT = new THREE.Vector3();

        this._injectFallbackStyle();
        this._collectDom();
        this._buildSubStructure();
        this._bindInput();
    }

    /* ---------- 4.1 DOM 收集 / 补建 ---------- */
    _injectFallbackStyle() {
        if (document.getElementById('hudFallbackStyle')) return;
        const st = document.createElement('style');
        st.id = 'hudFallbackStyle';
        st.textContent = FALLBACK_CSS;
        document.head.insertBefore(st, document.head.firstChild);   // 插最前，css/fps.css 可覆盖
    }

    _collectDom() {
        const MAP = {
            hudRoot: 'hud-root', crosshair: 'hud-crosshair', hitmarker: 'hud-hitmarker',
            ammoBox: 'hud-ammo-box', ammoCur: 'hud-ammo-cur', ammoReserve: 'hud-ammo-reserve',
            healthBar: 'hud-health-bar', healthNum: 'hud-health-num',
            phaseCard: 'hud-phase-card', phaseName: 'hud-phase-name', objectiveText: 'hud-objective-text',
            worldMarker: 'hud-world-marker', compassStrip: 'hud-compass-strip', killfeed: 'hud-killfeed',
            damageVignette: 'hud-damage-vignette', extractBar: 'hud-extract-bar',
            extractFill: 'hud-extract-fill', intelRing: 'hud-intel-ring', toastBox: 'hud-toast-box',
            menuRoot: 'hud-menu-root', btnMission: 'hud-btn', btnRange: 'hud-btn',
            resultRoot: 'hud-result-root', resultTitle: 'hud-result-title',
            resultStats: 'hud-result-stats', btnRetry: 'hud-btn', btnMenu: 'hud-btn',
            helpOverlay: 'hud-help-overlay', reloadHint: 'hud-reload-hint',
        };
        this.dom = {};
        /* 真实 html id 规约（fps.html / interfaces 29 id 冻结清单）：
         * 句柄名 camel → kebab；已带 hud- 前缀的（hudRoot→hud-root）不重复加，
         * 其余补 'hud-'（ammoCur→hud-ammo-cur），按钮本就是 camel（btnMission…）。
         * 此前 getElementById(句柄名) 对 25 个 hud-* 全部落空 → 静默走补建分支
         * 克隆出一整套影子 HUD（id="ammoCur" 等），且补建的 hudRoot 从未挂进
         * body——整棵子树 detached，每帧弹药/危险警示/血量全部写进不可见节点，
         * 页面停留 fps.html 原生壳初值（30/150）。BUG#2 根因，特此修正。 */
        const htmlId = (k) => {
            if (k.startsWith('btn')) return k;
            const kebab = k.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();
            return kebab.startsWith('hud-') ? kebab : 'hud-' + kebab;
        };
        for (const [key, cls] of Object.entries(MAP)) {
            const hid = htmlId(key);
            let el = document.getElementById(hid);
            if (!el) {
                console.warn(`[HUD] fps.html 缺少 #${hid}，已自动补建（建议集成者补进页面）`);
                el = document.createElement(key.startsWith('btn') ? 'button' : 'div');
                el.id = hid;
            }
            el.classList.add(cls);
            this.dom[key] = el;
        }
        // 归位：真实 DOM 本就在这些父级里（append 幂等无害）；补建场景保证嵌套正确
        const D = this.dom;
        document.body.append(D.menuRoot, D.resultRoot, D.helpOverlay);
        D.ammoBox.append(D.ammoCur, D.ammoReserve);
        D.phaseCard.append(D.phaseName, D.objectiveText);
        D.extractBar.append(D.extractFill);
        D.menuRoot.append(D.btnMission, D.btnRange);
        D.resultRoot.append(D.resultTitle, D.resultStats, D.btnRetry, D.btnMenu);
        [D.crosshair, D.hitmarker, D.ammoBox, D.healthBar, D.healthNum, D.phaseCard,
            D.worldMarker, D.compassStrip, D.killfeed, D.damageVignette, D.extractBar,
            D.intelRing, D.toastBox, D.reloadHint].forEach(el => D.hudRoot.appendChild(el));
    }

    // 给已有/补建元素补齐内部子结构（集成者 DOM 只要有 id，内部结构由这里兜底）
    _buildSubStructure() {
        const D = this.dom;
        const ensure = (parent, tag, cls, html) => {
            let el = parent && parent.querySelector('.' + cls.replace(/\s/g, '.'));
            if (!el) {
                el = document.createElement(tag);
                el.className = cls;
                if (html !== undefined) el.innerHTML = html;
                parent.appendChild(el);
            }
            return el;
        };

        // 准星：中心点 + 4 短线（ADS 时 JS 收拢）
        ensure(D.crosshair, 'div', 'hud-ch-dot');
        this._chLines = ['0deg', '90deg', '180deg', '270deg'].map(() => ensure(D.crosshair, 'div', 'hud-ch-line'));
        this.setAds(0);

        // hitmarker：X 形四线
        for (let i = 0; i < 4; i++) {
            const l = ensure(D.hitmarker, 'div', 'hud-hit-line');
            const a = 45 + i * 90;
            l.style.transform = `rotate(${a}deg) translateY(-9px)`;
            l.style.transformOrigin = '1px 0';
        }

        // 血量条内芯
        this._healthFill = ensure(D.healthBar, 'div', 'hud-health-fill');

        // 换弹提示：文本 + 进度条
        this._reloadText = ensure(D.reloadHint, 'span', 'hud-reload-text', '');
        this._reloadTrack = ensure(D.reloadHint, 'div', 'hud-reload-track');
        this._reloadFill = ensure(this._reloadTrack, 'div', 'hud-reload-fill');

        // 世界标记：菱形 + 边缘箭头 + 标签 + 距离
        ensure(D.worldMarker, 'div', 'hud-marker-diamond');
        this._markerArrow = ensure(D.worldMarker, 'div', 'hud-marker-arrow');
        this._markerDiamond = D.worldMarker.querySelector('.hud-marker-diamond');
        this._markerLabel = ensure(D.worldMarker, 'div', 'hud-marker-label', '');
        this._markerDistEl = ensure(D.worldMarker, 'div', 'hud-marker-dist', '');

        // 罗盘：刻度背景 + 中央指针 + 度数读数
        D.compassStrip.style.backgroundImage = `url(${makeCompassStrip()})`;
        ensure(D.compassStrip, 'div', 'hud-compass-center');
        this._compassDeg = ensure(D.hudRoot, 'div', 'hud-compass-deg');
        this._measureCompass();
        window.addEventListener('resize', this._measureCompass.bind(this));

        // 情报环形进度（SVG 圆环，rotate(-90) 从 12 点方向起）
        if (!D.intelRing.querySelector('svg')) {
            D.intelRing.innerHTML = `<svg class="hud-intel-svg" viewBox="0 0 120 120">
                <circle class="hud-intel-bg" cx="60" cy="60" r="52"></circle>
                <circle class="hud-intel-fg" cx="60" cy="60" r="52"></circle>
            </svg>`;
        }
        this._intelFg = D.intelRing.querySelector('.hud-intel-fg');
        this._intelFg.style.strokeDasharray = String(2 * Math.PI * 52);
        this._intelText = ensure(D.intelRing, 'div', 'hud-intel-text', 'F');

        // 撤离读条标签
        ensure(D.extractBar, 'div', 'hud-extract-label', '撤离中');

        // 受击方向箭头池（4 个循环用）
        for (let i = 0; i < 4; i++) {
            const w = document.createElement('div');
            w.className = 'hud-dmg-dir';
            ensure(w, 'div', 'hud-dmg-dir-mark');
            D.hudRoot.appendChild(w);
            this._dmgDirs.push({ el: w, until: 0 });
        }

        // 部署黑幕 / 简报卡 / Tab 目标详情 / 靶场成绩板（均动态，不占 id 清单）
        if (!document.getElementById('deployVeil')) {
            const v = document.createElement('div');
            v.id = 'deployVeil'; v.className = 'hud-deploy-veil';
            document.body.appendChild(v);
        }
        this.veil = document.getElementById('deployVeil');
        this._brief = ensure(D.hudRoot, 'div', 'hud-brief-card');
        this._briefTitle = ensure(this._brief, 'div', 'hud-brief-title', '');
        this._briefSub = ensure(this._brief, 'div', 'hud-brief-sub', '');
        this._brief.style.display = 'none';
        this._detail = ensure(D.hudRoot, 'div', 'hud-objective-detail');
        this._rangeStats = ensure(D.hudRoot, 'div', 'hud-range-stats');

        // 危险区警示（横幅 + 边缘渐晕，mission → setDanger 控制）/ 背包格 / 武器槽
        // （【大厅】组新增 HUD 分区；样式见 FALLBACK_CSS，可被 css/fps.css 覆盖）
        this._dangerBanner = ensure(D.hudRoot, 'div', 'hud-danger-banner', '');
        this._dangerBanner.style.display = 'none';
        this._dangerVig = ensure(D.hudRoot, 'div', 'hud-danger-vignette');
        this._dangerVig.style.display = 'none';
        this._bagBox = ensure(D.hudRoot, 'div', 'hud-bag');
        this._bagNum = ensure(this._bagBox, 'div', 'hud-bag-num', '背包 0/12');
        this._bagPips = ensure(this._bagBox, 'div', 'hud-bag-pips');
        this._bagCap = 0;
        this._bagPipEls = [];
        this._wslots = ensure(D.hudRoot, 'div', 'hud-weapon-slots');
        this._wslotEls = [0, 1].map((i) => {
            const s = ensure(this._wslots, 'div', 'hud-wslot');
            ensure(s, 'span', 'hud-wslot-key', i === 0 ? '1' : '2');
            ensure(s, 'span', 'hud-wslot-name', '——');
            return s;
        });
        this.setBag([], 12);

        // 主菜单：给补建场景注入按钮文字与键位说明；真实 DOM 有按钮则只补键位说明
        if (!D.btnMission.textContent) D.btnMission.textContent = '1 · 行动模式（获取情报 → 撤离）';
        if (!D.btnRange.textContent) D.btnRange.textContent = '2 · 靶场模式（练枪 · 计分）';
        if (!D.btnRetry.textContent) D.btnRetry.textContent = 'R · 重新部署';
        if (!D.btnMenu.textContent) D.btnMenu.textContent = 'Esc · 返回主菜单';
        ensure(D.menuRoot, 'div', 'hud-menu-title', '行动准备');
        ensure(D.menuRoot, 'div', 'hud-menu-sub', 'TACTICAL OPERATION · 战术行动');
        const keys = ensure(D.menuRoot, 'div', 'hud-menu-keys');
        keys.textContent = [
            '移动 W/A/S/D · 疾跑 Shift · 蹲伏 C · 跳跃 Space',
            '开火 左键 · 开镜 右键/Q · 换弹 R · 切枪 1/2 · 搜索/互动 按住 F',
            '暂停菜单 1 重开行动 · 2 重开靶场 · 3 放弃行动（视同阵亡） · Esc 恢复',
            '静音 M · 键位帮助 H · 目标详情 按住 Tab',
        ].join('\n');
        // 说明文字固定在前，按钮（含 fps.html 静态追加的「3 · 放弃行动」）按
        // DOM 相对顺序统一排到其后——collectDom 的 append 移位不会打散排版
        const _menuBtns = Array.from(D.menuRoot.querySelectorAll('button'));
        [D.menuRoot.querySelector('.hud-menu-title'),
            D.menuRoot.querySelector('.hud-menu-sub'), keys]
            .forEach((el) => el && D.menuRoot.appendChild(el));
        _menuBtns.forEach((b) => D.menuRoot.appendChild(b));
        D.btnMission.addEventListener('click', () => this._fireSelect(0));
        D.btnRange.addEventListener('click', () => this._fireSelect(1));
        D.btnRetry.addEventListener('click', () => this.onRetry && this.onRetry());
        D.btnMenu.addEventListener('click', () => this.onBackToMenu && this.onBackToMenu());
        this._menuFocus(0);
        this.hideMenu();
        this.showResult(null);   // 初始化为隐藏（传 null 直接藏）
        this.showHelp(false);
    }

    _measureCompass() {
        const D = this.dom;
        this._compassW = D.compassStrip && D.compassStrip.clientWidth > 0
            ? D.compassStrip.clientWidth : 340;
    }

    /* ---------- 4.2 键盘可达层（菜单/结算/静音/帮助/Tab） ---------- */
    _bindInput() {
        this._onKeyDown = (e) => {
            const code = e.code;
            if (this.menuVisible) {
                if (code === 'Digit1' || code === 'Numpad1') { this._fireSelect(0); return; }
                if (code === 'Digit2' || code === 'Numpad2') { this._fireSelect(1); return; }
                if (code === 'Enter' || code === 'NumpadEnter') { this._fireSelect(this._menuIdx); return; }
                if (code === 'ArrowUp' || code === 'ArrowDown' || code === 'KeyW' || code === 'KeyS') {
                    this._menuFocus(1 - this._menuIdx);
                    e.preventDefault();
                }
                return;
            }
            if (this.resultVisible) {
                if (code === 'KeyR') { this.ui.beep(660, 0.06, 0.15); this.onRetry && this.onRetry(); return; }
                if (code === 'Enter' || code === 'NumpadEnter') {   // 结算回车 = 回大厅（extractFlow）
                    this.ui.beep(440, 0.06, 0.12);
                    this.onBackToMenu && this.onBackToMenu();
                    return;
                }
                if (code === 'Escape') { this.ui.beep(440, 0.06, 0.12); this.onBackToMenu && this.onBackToMenu(); return; }
            }
            if (code === 'KeyM') { this.toggleMute(); }               // 静音：全局保留
            else if (this.uiBlocked) { /* 大厅盖场：H/Tab 不转发（lobby.show 置位） */ }
            else if (code === 'KeyH') { this.showHelp(!this.helpVisible); }
            else if (code === 'Tab') {
                e.preventDefault();
                this._detail.style.display = 'block';
            }
        };
        this._onKeyUp = (e) => {
            if (e.code === 'Tab') this._detail.style.display = 'none';
        };
        window.addEventListener('keydown', this._onKeyDown);
        window.addEventListener('keyup', this._onKeyUp);

        // 首次用户手势激活 UIAudio（main 对 GunAudio.ensure 做的同一件事）
        const gesture = () => { this.ui.ensure(); };
        window.addEventListener('pointerdown', gesture, { once: true });
        window.addEventListener('keydown', gesture, { once: true });
    }

    _menuFocus(i) {
        this._menuIdx = i;
        const D = this.dom;
        D.btnMission.classList.toggle('hud-btn-focus', i === 0);
        D.btnRange.classList.toggle('hud-btn-focus', i === 1);
    }

    _fireSelect(i) {
        this.ui.beep(i === 0 ? 740 : 740, 0.07, 0.16);
        this.hideMenu();
        if (i === 0) this.onSelectMission && this.onSelectMission();
        else this.onSelectRange && this.onSelectRange();
    }

    toggleMute() {
        this.setMuted(!this.muted);
    }

    setMuted(m) {
        this.muted = m;
        this.ui.setMuted(m);
        this.toast(m ? '已静音（M 恢复）' : '声音已开启');
        this.onMuteToggle && this.onMuteToggle(m);
    }

    /* ---------- 4.3 弹药 / 换弹 ---------- */
    setAmmoState({ ammo, reserve, reloading, reloadProgress, reloadKind }) {
        const D = this.dom;
        D.ammoCur.textContent = String(ammo ?? '--');
        D.ammoReserve.textContent = reserve === Infinity ? '/ ∞' : '/ ' + (reserve ?? '--');
        D.ammoCur.classList.toggle('hud-low', !reloading && ammo <= 8);

        if (reloading) {
            D.reloadHint.style.display = 'block';
            this._reloadText.textContent = reloadKind === 'empty' ? '空仓装填' : '战术装填';
            this._reloadFill.style.width = `${Math.round((reloadProgress || 0) * 100)}%`;
        } else if (ammo === 0) {
            D.reloadHint.style.display = 'block';
            this._reloadText.textContent = '弹药耗尽 —— 按 R 装填';
            this._reloadFill.style.width = '0%';
        } else if (ammo <= 8) {
            D.reloadHint.style.display = 'block';
            this._reloadText.textContent = '弹药不足';
            this._reloadFill.style.width = '0%';
        } else {
            D.reloadHint.style.display = 'none';
        }
    }

    /* ---------- 4.4 血量 / 低血 ---------- */
    setHealth(h) {
        const D = this.dom;
        const pct = Math.max(0, Math.min(100, h));
        D.healthNum.textContent = String(Math.ceil(h));
        if (this._healthFill) this._healthFill.style.width = pct + '%';
        const low = h <= 30;
        D.healthBar.classList.toggle('hud-low', low);
        D.damageVignette.classList.toggle('hud-lowblood', low && h > 0);
        this._lowBlood = low && h > 0;
        if (h <= 0) D.damageVignette.classList.remove('hud-lowblood');
    }

    /* ---------- 4.5 阶段卡 / 目标 ---------- */
    setPhase(name, objective) {
        const D = this.dom;
        D.phaseName.textContent = name || '';
        D.objectiveText.textContent = objective || '';
        D.phaseCard.classList.remove('hud-flash');
        void D.phaseCard.offsetWidth;   // 重排触发重播动画
        D.phaseCard.classList.add('hud-flash');
    }

    // Tab 按住显示的目标详情（多行文本）
    setObjectiveDetail(text) {
        this._detail.textContent = text || '';
    }

    /* ---------- 4.6 世界标记（3D→2D 投影，屏外夹边箭头） ---------- */
    showMarker(worldPos, label) {
        const D = this.dom;
        if (!worldPos) { D.worldMarker.style.opacity = '0'; return; }
        const cam = this.camera;
        cam.updateMatrixWorld();
        cam.getWorldDirection(this._camDir);
        this._toT.copy(worldPos).sub(cam.position);
        const dist = this._toT.length();
        const behind = this._toT.dot(this._camDir) < 0;
        this._v.copy(worldPos).project(cam);

        const W = window.innerWidth, H = window.innerHeight;
        const M = 48;   // 边缘留白
        let x = (this._v.x * 0.5 + 0.5) * W;
        let y = (-this._v.y * 0.5 + 0.5) * H;
        if (behind) { x = W - x; y = H - y; }   // 背后点投影镜像翻转

        const off = behind || x < M || x > W - M || y < M || y > H - M;
        if (off) {
            // 夹到屏幕边缘，箭头指向目标
            const cx = W / 2, cy = H / 2;
            let dx = x - cx, dy = y - cy;
            if (dx === 0 && dy === 0) dx = 1;
            const sx = (W / 2 - M) / Math.abs(dx || 1e-6);
            const sy = (H / 2 - M) / Math.abs(dy || 1e-6);
            const s = Math.min(sx, sy);
            x = cx + dx * s; y = cy + dy * s;
            this._markerArrow.style.display = 'block';
            this._markerArrow.style.transform = `rotate(${Math.atan2(dx, -dy)}rad)`;
            this._markerArrow.style.transformOrigin = '8px 8px';
            this._markerDiamond.style.display = 'none';
            this._markerDistEl.textContent = '';
        } else {
            this._markerArrow.style.display = 'none';
            this._markerDiamond.style.display = 'block';
            const d = `${Math.round(dist)}m`;
            if (d !== this._markerDist) { this._markerDist = d; this._markerDistEl.textContent = d; }
        }
        if (label !== undefined && label !== this._label) {
            this._label = label;
            this._markerLabel.textContent = label || '';
        }
        /* UI 缩放补偿：标记按真实屏幕像素算的，挂在 zoom 过的 hud-root 里要除回去，
         * 否则全屏时标记会飞出屏幕（main.js applyUiZoom 维护 __uiZoom） */
        const uz = window.__uiZoom || 1;
        D.worldMarker.style.left = `${x / uz}px`;
        D.worldMarker.style.top = `${y / uz}px`;
        D.worldMarker.style.opacity = '1';
    }

    /* ---------- 4.7 罗盘 ---------- */
    compass(yaw) {
        const heading = ((-yaw * 180 / Math.PI) % 360 + 360) % 360;   // yaw=0 面向 -Z 定为北
        const D = this.dom;
        D.compassStrip.style.backgroundPositionX = `${(this._compassW / 2 - heading * COMPASS_PX_PER_DEG).toFixed(1)}px`;
        const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
        const card = names[Math.round(heading / 45) % 8];
        this._compassDeg.textContent = `${String(Math.round(heading) % 360).padStart(3, '0')}° ${card}`;
        this._refreshIdle();
    }

    /* ---------- 4.8 命中反馈 / 播报 / 受击 ---------- */
    hitmarker(kill, head) {
        this._hit.until = performance.now() + (kill ? 420 : 240);
        this._hit.dur = kill ? 420 : 240;
        const D = this.dom;
        D.hitmarker.classList.toggle('hud-kill', !!kill);
        D.hitmarker.classList.toggle('hud-head', !!head && !kill);
    }

    killfeed(text) {
        const D = this.dom;
        const item = document.createElement('div');
        item.className = 'hud-kill-item';
        item.textContent = text;
        D.killfeed.appendChild(item);
        while (D.killfeed.children.length > 5) D.killfeed.removeChild(D.killfeed.firstChild);
        setTimeout(() => { item.style.transition = 'opacity .4s'; item.style.opacity = '0'; }, 4200);
        setTimeout(() => { item.remove(); }, 4800);
    }

    // dirAngle：受击来向相对玩家正前方的方位角（rad，右为正）；null=仅红晕
    damageFrom(dirAngle) {
        const D = this.dom;
        D.damageVignette.classList.add('hud-show');
        clearTimeout(this._dmgVigTimer);
        this._dmgVigTimer = setTimeout(() => D.damageVignette.classList.remove('hud-show'), 350);
        if (dirAngle === null || dirAngle === undefined) return;
        const slot = this._dmgDirs.reduce((a, b) => (a.until < b.until ? a : b));
        slot.until = performance.now() + 1100;
        slot.el.style.transform = `rotate(${dirAngle * 180 / Math.PI}deg)`;
    }

    /* ---------- 4.9 读条 / 环形进度 ---------- */
    setExtractProgress(k) {
        const D = this.dom;
        if (k === null || k === undefined) {
            D.extractBar.style.display = 'none';
            return;
        }
        D.extractBar.style.display = 'block';
        D.extractFill.style.width = `${Math.round(Math.max(0, Math.min(1, k)) * 100)}%`;
    }

    setIntelProgress(k) {
        const D = this.dom;
        if (k === null || k === undefined) {
            D.intelRing.style.display = 'none';
            return;
        }
        D.intelRing.style.display = 'block';
        const C = 2 * Math.PI * 52;
        this._intelFg.style.strokeDashoffset = String(C * (1 - Math.max(0, Math.min(1, k))));
        this._intelText.textContent = k >= 1 ? '✓' : 'F';
    }

    /* ---------- 4.10 菜单 / 结算 / 帮助 / 简报 ---------- */
    showMenu() {
        this.dom.menuRoot.style.display = 'flex';
        this.menuVisible = true;
        this._menuFocus(this._menuIdx);
    }

    hideMenu() {
        this.dom.menuRoot.style.display = 'none';
        this.menuVisible = false;
    }

    // accuracy 接受 0..1（>1 且 ≤100 视为已是百分数）；rank 'S'|'A'|'B'|'C'
    // 传 null / undefined 仅隐藏结算页
    showResult(arg) {
        const D = this.dom;
        if (!arg) {
            D.resultRoot.style.display = 'none';
            this.resultVisible = false;
            return;
        }
        const { win, kills, accuracy, timeSec, rank } = arg;
        const acc = accuracy == null ? 0 : (accuracy <= 1 ? accuracy * 100 : accuracy);
        const mm = Math.floor((timeSec || 0) / 60), ss = Math.floor((timeSec || 0) % 60);
        D.resultTitle.textContent = win ? '行动成功' : '行动失败';
        D.resultTitle.classList.toggle('hud-win', !!win);
        D.resultTitle.classList.toggle('hud-lose', !win);
        D.resultStats.innerHTML = '';
        // extraRows（[[label, value], ...]）非空时整体替换默认三行（撤离结算用：
        // 带出价值/情报奖金/击杀/命中率/评级 等由调用方自由拼装）
        const rows = (Array.isArray(arg.extraRows) && arg.extraRows.length)
            ? arg.extraRows
            : [
                ['击杀', `${kills ?? 0}`],
                ['命中率', `${acc.toFixed(1)}%`],
                ['用时', `${mm}:${String(ss).padStart(2, '0')}`],
            ];
        rows.forEach(([k, v]) => {
            const line = document.createElement('div');
            line.textContent = `${k}　${v}`;
            D.resultStats.appendChild(line);
        });
        const rk = document.createElement('div');
        rk.className = 'hud-rank';
        rk.textContent = rank || (win ? 'B' : 'C');
        D.resultRoot.querySelectorAll('.hud-rank').forEach(x => x.remove());   // 防重复堆叠
        D.resultRoot.insertBefore(rk, D.resultStats);
        D.resultRoot.style.display = 'flex';
        this.resultVisible = true;
        this.ui.beep(win ? 880 : 330, 0.12, 0.2);
        if (win) this.ui.beep(1175, 0.14, 0.16, 'square');
    }

    hideResult() {
        this.showResult(null);
    }

    showHelp(on) {
        const D = this.dom;
        if (on && !D.helpOverlay.querySelector('.hud-help-body')) {
            const t = document.createElement('div');
            t.className = 'hud-help-title';
            t.textContent = '键位说明';
            const b = document.createElement('div');
            b.className = 'hud-help-body';
            b.textContent = [
                '大厅　1/2/3 切换 出发/仓库/改枪台　·　G 去靶场试枪',
                '出发页　←/→ 选择 · 回车 确认/出发　　仓库　↑↓←→ 选格 · 回车 变卖',
                '改枪台　←→ 换列 · ↑↓ 选项 · 回车 购买/换装/卸下（瞄具单持）',
                '移动　W/A/S/D　　疾跑　Shift（按住，禁开火）',
                '蹲伏　C（切换）　跳跃　Space　　切枪　1 主武器 / 2 副武器',
                '视角　点击画面锁定鼠标；?test=1 时鼠标滑过画面即转向 + ←→↑↓',
                '开火　鼠标左键（全自动）　开镜　右键按住 / Q 切换',
                '换弹　R（自动判定战术/空仓）　搜索/互动　按住 F',
                '静音　M　　帮助　H　　目标详情　按住 Tab',
                '暂停 Esc：1 重开行动 / 2 重开靶场 / 3 放弃行动 / Esc 恢复',
                '靶场：长按 R 0.5s 重置全场　·　结算页：回车回大厅 / R 同图再战',
            ].join('\n');
            D.helpOverlay.append(t, b);
        }
        D.helpOverlay.style.display = on ? 'flex' : 'none';
        this.helpVisible = !!on;
    }

    // 部署黑幕：0=全透明 1=全黑（CSS transition 平滑）
    setVeil(k) {
        this.veil.style.opacity = String(Math.max(0, Math.min(1, k)));
    }

    // 简报卡（DEPLOY 阶段），dur 毫秒后自动隐藏
    showBrief(title, sub, dur = 4000) {
        this._briefTitle.textContent = title || '';
        this._briefSub.textContent = sub || '';
        this._brief.style.display = 'block';
        clearTimeout(this._briefTimer);
        this._briefTimer = setTimeout(() => { this._brief.style.display = 'none'; }, dur);
    }

    // color（可选）：品质色描边+文字（拾取战利品 toast 用，如 loot.RARITY[i].color）
    toast(text, dur = 3000, color) {
        const t = document.createElement('div');
        t.className = 'hud-toast';
        t.textContent = text;
        if (color) { t.style.borderColor = color; t.style.color = color; }
        this.dom.toastBox.appendChild(t);
        while (this.dom.toastBox.children.length > 4) this.dom.toastBox.removeChild(this.dom.toastBox.firstChild);
        setTimeout(() => { t.style.transition = 'opacity .4s'; t.style.opacity = '0'; }, dur - 400);
        setTimeout(() => { t.remove(); }, dur);
    }

    // ADS 收拢准星（0=腰射 1=全收）
    setAds(k) {
        const gap = 7 * (1 - (k || 0));
        const lines = this._chLines || [];
        if (lines[0]) lines[0].style.transform = `translateY(${-gap - 5}px)`;
        if (lines[1]) lines[1].style.transform = `rotate(90deg) translateY(${-gap - 5}px)`;
        if (lines[2]) lines[2].style.transform = `rotate(180deg) translateY(${-gap - 5}px)`;
        if (lines[3]) lines[3].style.transform = `rotate(270deg) translateY(${-gap - 5}px)`;
    }

    // 靶场成绩板（动态元素，不占 id 清单）
    setRangeStats({ score, acc, best, streak }) {
        const el = this._rangeStats;
        el.style.display = 'block';
        const a = acc == null ? 0 : (acc <= 1 ? acc * 100 : acc);
        el.innerHTML = '';
        [['得分', score ?? 0], ['命中率', a.toFixed(1) + '%'],
            ['最佳分', best ?? 0], ['连击', streak ?? 0]].forEach(([k, v]) => {
            const line = document.createElement('div');
            line.textContent = `${k}　${v}`;
            el.appendChild(line);
        });
    }

    hideRangeStats() {
        this._rangeStats.style.display = 'none';
    }

    /* ---------- 4.10b 大厅组新增 HUD 分区（样式见 FALLBACK_CSS / css/fps.css） ---------- */

    // 危险区警示：true = 进入高危战区（横幅 + 边缘渐晕），false = 离开
    setDanger(on) {
        this._dangerBanner.textContent = '⚠ 高危战区 · 敌方精锐出没';
        this._dangerBanner.style.display = on ? 'block' : 'none';
        this._dangerVig.style.display = on ? 'block' : 'none';
    }

    // 背包格数：items 数组（取 length）或直接传数量；cap 默认 12（Backpack 容量）
    setBag(items, cap = 12) {
        const n = Array.isArray(items) ? items.length : Math.max(0, items | 0);
        const c = Math.max(1, cap | 0);
        if (this._bagCap !== c) {   // 容量变化才重建格点（每帧调用零 DOM 抖动）
            this._bagCap = c;
            this._bagPips.innerHTML = '';
            this._bagPipEls = [];
            for (let i = 0; i < c; i++) {
                const p = document.createElement('span');
                p.className = 'hud-bag-pip';
                this._bagPips.appendChild(p);
                this._bagPipEls.push(p);
            }
        }
        this._bagPipEls.forEach((p, i) => p.classList.toggle('hud-bag-pip-full', i < n));
        this._bagNum.textContent = `背包 ${n}/${c}`;
    }

    // 武器槽：{primary, secondary, active}；primary/secondary 传展示名或 {name}；
    // active 传 0/1 或 'primary'/'secondary'（gunview.onSwitch → main 转喂）
    setWeaponSlots(slots) {
        const s = slots || {};
        const label = (g) => g == null ? '——'
            : (typeof g === 'string' ? g : (g.name || g.id || '——'));
        const act = s.active === 'primary' ? 0
            : s.active === 'secondary' ? 1
                : (typeof s.active === 'number' ? s.active : -1);   // 缺省不高亮
        const names = [label(s.primary), label(s.secondary)];
        this._wslotEls.forEach((el, i) => {
            el.querySelector('.hud-wslot-name').textContent = names[i];
            el.classList.toggle('hud-wslot-active', act === i);
        });
    }

    /* ---------- 4.11 每帧刷新 / 销毁 ---------- */
    // main.js 每帧可选调用；衰减全部基于 performance.now()，不调也不致卡死
    update(dt) {
        this.ui.update(dt || 0);
        if (this._lowBlood && performance.now() > this._nextHeartbeat) {
            this._nextHeartbeat = performance.now() + 1150;
            this.ui.heartbeat();
        }
        this._refreshIdle();
    }

    _refreshIdle() {
        const now = performance.now();
        // hitmarker 衰减
        const h = this._hit;
        if (h.until > 0) {
            const k = Math.max(0, Math.min(1, (h.until - now) / h.dur));
            this.dom.hitmarker.style.opacity = String(k);
            this.dom.hitmarker.style.transform = `scale(${0.8 + 0.2 * k})`;
            if (k === 0) h.until = 0;
        }
        // 受击方向箭头衰减
        for (const d of this._dmgDirs) {
            d.el.style.opacity = String(Math.max(0, Math.min(1, (d.until - now) / 1100)));
        }
    }

    dispose() {
        window.removeEventListener('keydown', this._onKeyDown);
        window.removeEventListener('keyup', this._onKeyUp);
        if (this.ui.ctx) this.ui.ctx.close();
    }
}
