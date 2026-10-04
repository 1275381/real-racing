/* GunAudio：枪械组全合成音效（照 js/audio.js 先例：零外部资源、零采样）
 * AudioContext 延迟到首次用户手势创建（ensure() 由 main.js 在首次
 * keydown/pointerdown 时调用，规避浏览器自动播放策略）。
 * 枪声分层：高频破裂(噪声高通) + 主体(噪声低通) + 低频体感(正弦下扫)
 *          + 撞针机械声(方波极短) + 环境尾音(带通)。 */

export class GunAudio {
    constructor() {
        this.ctx = null;
        this.master = null;
        this.muted = false;
        this._noiseBuf = null;
    }

    /* 必须在用户手势内调用；幂等 */
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
        const comp = ctx.createDynamicsCompressor();       // 压限：连发不爆音
        comp.threshold.value = -12;
        comp.ratio.value = 6;
        master.connect(comp);
        comp.connect(ctx.destination);
        const len = Math.floor(ctx.sampleRate * 1.2);      // 共享白噪声缓冲
        const buf = ctx.createBuffer(1, len, ctx.sampleRate);
        const d = buf.getChannelData(0);
        for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
        this._noiseBuf = buf;
    }

    setMuted(m) {
        this.muted = m;
        if (this.master) {
            this.master.gain.setTargetAtTime(m ? 0 : 0.9, this.ctx.currentTime, 0.05);
        }
    }

    /* ---- 内部工具：噪声爆发层 / 音调层 ---- */

    /* 噪声层：白噪声 -> 滤波 -> 指数衰减包络 */
    _burst(t0, { type = 'bandpass', freq = 1000, freqEnd = 0, q = 1, gain = 0.3, decay = 0.08, rate = 1 } = {}) {
        const ctx = this.ctx;
        const src = ctx.createBufferSource();
        src.buffer = this._noiseBuf;
        src.playbackRate.value = rate;
        const f = ctx.createBiquadFilter();
        f.type = type;
        f.frequency.setValueAtTime(freq, t0);
        if (freqEnd > 0) f.frequency.exponentialRampToValueAtTime(freqEnd, t0 + decay);
        f.Q.value = q;
        const g = ctx.createGain();
        g.gain.setValueAtTime(gain, t0);
        g.gain.exponentialRampToValueAtTime(0.0008, t0 + decay);
        src.connect(f); f.connect(g); g.connect(this.master);
        src.start(t0, Math.random() * 0.8);
        src.stop(t0 + decay + 0.05);
    }

    /* 音调层：振荡器 f0→f1 下扫 + 指数衰减 */
    _tone(t0, { type = 'sine', f0 = 200, f1 = 0, dur = 0.1, gain = 0.3 } = {}) {
        const ctx = this.ctx;
        const o = ctx.createOscillator();
        o.type = type;
        o.frequency.setValueAtTime(f0, t0);
        if (f1 > 0) o.frequency.exponentialRampToValueAtTime(f1, t0 + dur);
        const g = ctx.createGain();
        g.gain.setValueAtTime(gain, t0);
        g.gain.exponentialRampToValueAtTime(0.0008, t0 + dur);
        o.connect(g); g.connect(this.master);
        o.start(t0);
        o.stop(t0 + dur + 0.03);
    }

    _now() { return this.ctx.currentTime; }

    /* ---- 枪械动作音 ---- */

    /* 开枪：四层叠加 + 随机音高抖动（避免连发机械感） */
    shot() {
        if (!this.ctx) return;
        const t = this._now();
        const r = 0.94 + Math.random() * 0.12;
        this._burst(t, { type: 'highpass', freq: 2800 * r, gain: 0.55, decay: 0.028, rate: r }); // 破裂
        this._burst(t, { type: 'lowpass', freq: 900 * r, freqEnd: 260, gain: 0.6, decay: 0.075, rate: r }); // 主体
        this._tone(t, { type: 'sine', f0: 150, f1: 42, dur: 0.16, gain: 0.65 });                 // 低频体感
        this._tone(t, { type: 'square', f0: 1900, f1: 1400, dur: 0.012, gain: 0.06 });           // 撞针
        this._burst(t + 0.02, { type: 'bandpass', freq: 700 * r, q: 0.8, gain: 0.12, decay: 0.22, rate: r }); // 尾音
    }

    /* 空仓干响：击锤空击两声脆响 */
    dry() {
        if (!this.ctx) return;
        const t = this._now();
        this._tone(t, { type: 'square', f0: 1100, f1: 900, dur: 0.012, gain: 0.14 });
        this._burst(t + 0.028, { type: 'highpass', freq: 1600, gain: 0.1, decay: 0.02 });
        this._tone(t + 0.03, { type: 'square', f0: 720, f1: 560, dur: 0.016, gain: 0.1 });
    }

    /* 弹匣脱出：聚合物滑出 + 轻磕 */
    magOut() {
        if (!this.ctx) return;
        const t = this._now();
        this._burst(t, { type: 'bandpass', freq: 850, freqEnd: 380, q: 1.6, gain: 0.22, decay: 0.11 });
        this._tone(t + 0.09, { type: 'sine', f0: 190, f1: 120, dur: 0.06, gain: 0.16 });
    }

    /* 弹匣拍合：短促重插 + 卡榫咔哒 */
    magIn() {
        if (!this.ctx) return;
        const t = this._now();
        this._burst(t, { type: 'lowpass', freq: 1100, gain: 0.5, decay: 0.05 });
        this._tone(t, { type: 'sine', f0: 210, f1: 120, dur: 0.07, gain: 0.4 });
        this._burst(t + 0.015, { type: 'bandpass', freq: 2300, q: 4, gain: 0.2, decay: 0.02 });
    }

    /* 拉栓后段：金属长滑 + 末端定位 */
    boltBack() {
        if (!this.ctx) return;
        const t = this._now();
        this._burst(t, { type: 'bandpass', freq: 2400, freqEnd: 1400, q: 3.5, gain: 0.2, decay: 0.13 });
        this._burst(t + 0.1, { type: 'highpass', freq: 1800, gain: 0.22, decay: 0.02 });
    }

    /* 拉栓前甩：枪机复位的双重脆响 */
    boltForward() {
        if (!this.ctx) return;
        const t = this._now();
        this._burst(t, { type: 'highpass', freq: 1500, gain: 0.5, decay: 0.02 });
        this._tone(t, { type: 'sine', f0: 250, f1: 150, dur: 0.045, gain: 0.32 });
        this._burst(t + 0.018, { type: 'bandpass', freq: 2600, q: 5, gain: 0.24, decay: 0.015 });
    }

    /* 命中反馈：hit=高频叮；kill=低沉双音 */
    hit(kill) {
        if (!this.ctx) return;
        const t = this._now();
        if (kill) {
            this._tone(t, { type: 'triangle', f0: 620, f1: 600, dur: 0.1, gain: 0.32 });
            this._tone(t + 0.07, { type: 'triangle', f0: 415, f1: 395, dur: 0.16, gain: 0.36 });
        } else {
            this._tone(t, { type: 'sine', f0: 2500, f1: 2200, dur: 0.035, gain: 0.2 });
            this._tone(t + 0.01, { type: 'sine', f0: 1250, f1: 1150, dur: 0.04, gain: 0.12 });
        }
    }

    /* 敌方远处枪声：距离衰减增益 + 低通闷化 + 传声延迟 */
    enemyShot(dist) {
        if (!this.ctx) return;
        const d = Math.max(0, dist);
        const t = this._now() + Math.min(d / 343, 0.35);
        const att = 1 / (1 + d * 0.045);
        const lp = Math.max(240, 2400 / (1 + d / 25));
        this._burst(t, { type: 'lowpass', freq: lp, gain: 0.5 * att, decay: 0.09 });
        this._tone(t, { type: 'sine', f0: 110, f1: 36, dur: 0.18, gain: 0.4 * att });
    }

    /* UI 哔声 */
    uiBeep() {
        if (!this.ctx) return;
        const t = this._now();
        this._tone(t, { type: 'square', f0: 880, f1: 880, dur: 0.06, gain: 0.1 });
    }
}
