// 程序化引擎音效：锯齿+方波双振荡器 -> 波形整形 -> 低通，转速驱动音高
// 另有：轮胎摩擦啸叫(带通噪声)、风噪、路肩隆隆、碰撞闷响、倒计时哔声
export class AudioManager {
    constructor() {
        this.ctx = null;
        this.master = null;
        this.muted = false;
        this._engine = null;
        this._skidGain = null;
        this._windGain = null;
        this._rumbleGain = null;
    }

    // 必须在用户手势里调用（浏览器自动播放策略）
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

        // --- 噪声缓冲 ---
        const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 1.2, ctx.sampleRate);
        const nd = noiseBuf.getChannelData(0);
        for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;

        // --- 引擎 ---
        const osc1 = ctx.createOscillator(); osc1.type = 'sawtooth';
        const osc2 = ctx.createOscillator(); osc2.type = 'square';
        const engMix = ctx.createGain(); engMix.gain.value = 1;
        const o2g = ctx.createGain(); o2g.gain.value = 0.55;
        const shaper = ctx.createWaveShaper();
        shaper.curve = makeDistCurve(2.6);
        const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 600; lp.Q.value = 1.1;
        const engGain = ctx.createGain(); engGain.gain.value = 0.0;
        osc1.connect(engMix); osc2.connect(o2g); o2g.connect(engMix);
        engMix.connect(shaper); shaper.connect(lp); lp.connect(engGain); engGain.connect(master);
        osc1.start(); osc2.start();
        this._engine = { osc1, osc2, lp, engGain };

        // --- 轮胎啸叫 ---
        const skidSrc = ctx.createBufferSource(); skidSrc.buffer = noiseBuf; skidSrc.loop = true;
        const skidBP = ctx.createBiquadFilter(); skidBP.type = 'bandpass'; skidBP.frequency.value = 850; skidBP.Q.value = 6;
        this._skidGain = ctx.createGain(); this._skidGain.gain.value = 0;
        skidSrc.connect(skidBP); skidBP.connect(this._skidGain); this._skidGain.connect(master);
        skidSrc.start();

        // --- 风噪 ---
        const windSrc = ctx.createBufferSource(); windSrc.buffer = noiseBuf; windSrc.loop = true;
        const windLP = ctx.createBiquadFilter(); windLP.type = 'lowpass'; windLP.frequency.value = 300;
        this._windGain = ctx.createGain(); this._windGain.gain.value = 0;
        windSrc.connect(windLP); windLP.connect(this._windGain); this._windGain.connect(master);
        windSrc.start();

        // --- 路肩/砂石隆隆 ---
        const rumSrc = ctx.createBufferSource(); rumSrc.buffer = noiseBuf; rumSrc.loop = true; rumSrc.playbackRate.value = 0.4;
        const rumLP = ctx.createBiquadFilter(); rumLP.type = 'lowpass'; rumLP.frequency.value = 120;
        this._rumbleGain = ctx.createGain(); this._rumbleGain.gain.value = 0;
        rumSrc.connect(rumLP); rumLP.connect(this._rumbleGain); this._rumbleGain.connect(master);
        rumSrc.start();
    }

    setMuted(m) {
        this.muted = m;
        if (this.master) this.master.gain.setTargetAtTime(m ? 0 : 0.9, this.ctx.currentTime, 0.05);
    }

    // rpmNorm: 0..1；load: 油门/负载 0..1
    updateEngine(rpmNorm, load, running) {
        if (!this.ctx || !this._engine) return;
        const t = this.ctx.currentTime;
        const baseFreq = 42 + rpmNorm * 175;          // 基频 Hz
        this._engine.osc1.frequency.setTargetAtTime(baseFreq, t, 0.03);
        this._engine.osc2.frequency.setTargetAtTime(baseFreq * 0.501, t, 0.03);
        this._engine.lp.frequency.setTargetAtTime(320 + rpmNorm * 2600 + load * 900, t, 0.05);
        const vol = running ? (0.05 + load * 0.17 + rpmNorm * 0.09) : 0;
        this._engine.engGain.gain.setTargetAtTime(vol, t, 0.06);
    }

    updateSkid(amount) {   // 0..1
        if (!this.ctx) return;
        this._skidGain.gain.setTargetAtTime(Math.min(0.34, amount * 0.34), this.ctx.currentTime, 0.05);
    }

    updateWind(speedRatio) {
        if (!this.ctx) return;
        this._windGain.gain.setTargetAtTime(speedRatio * speedRatio * 0.22, this.ctx.currentTime, 0.12);
    }

    updateRumble(on, speed) {
        if (!this.ctx) return;
        const v = on ? Math.min(0.3, 0.1 + speed * 0.004) : 0;
        this._rumbleGain.gain.setTargetAtTime(v, this.ctx.currentTime, 0.04);
    }

    collision(strength) {
        if (!this.ctx) return;
        const t = this.ctx.currentTime;
        const s = Math.min(1, strength);
        // 噪声爆
        const src = this.ctx.createBufferSource();
        src.buffer = makeThudBuffer(this.ctx);
        const g = this.ctx.createGain();
        g.gain.setValueAtTime(0.5 * s, t);
        g.gain.exponentialRampToValueAtTime(0.001, t + 0.25);
        const f = this.ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 500;
        src.connect(f); f.connect(g); g.connect(this.master);
        src.start(t); src.stop(t + 0.3);
        // 低频砰
        const o = this.ctx.createOscillator(); o.type = 'sine';
        o.frequency.setValueAtTime(90, t); o.frequency.exponentialRampToValueAtTime(38, t + 0.18);
        const og = this.ctx.createGain();
        og.gain.setValueAtTime(0.5 * s, t); og.gain.exponentialRampToValueAtTime(0.001, t + 0.2);
        o.connect(og); og.connect(this.master);
        o.start(t); o.stop(t + 0.25);
    }

    beep(freq, dur = 0.14, vol = 0.3) {
        if (!this.ctx) return;
        const t = this.ctx.currentTime;
        const o = this.ctx.createOscillator(); o.type = 'square'; o.frequency.value = freq;
        const g = this.ctx.createGain();
        g.gain.setValueAtTime(vol, t);
        g.gain.setValueAtTime(vol, t + dur - 0.02);
        g.gain.linearRampToValueAtTime(0, t + dur);
        o.connect(g); g.connect(this.master);
        o.start(t); o.stop(t + dur + 0.02);
    }
}

function makeDistCurve(k) {
    const n = 256, curve = new Float32Array(n);
    for (let i = 0; i < n; i++) {
        const x = (i / (n - 1)) * 2 - 1;
        curve[i] = Math.tanh(k * x) / Math.tanh(k);
    }
    return curve;
}

function makeThudBuffer(ctx) {
    const len = Math.floor(ctx.sampleRate * 0.28);
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) {
        d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.2);
    }
    return buf;
}
