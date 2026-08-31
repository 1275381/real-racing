import * as THREE from 'three';
import { RaceTrack } from './track.js';
import { createEnvironment } from './environment.js';
import { buildCar, loadedModels } from './car.js';
import { Vehicle } from './physics.js';
import { AIController } from './opponents.js';
import { Effects } from './effects.js';
import { HUD } from './hud.js';
import { InputManager } from './input.js';
import { AudioManager } from './audio.js';
import { skyMaterial } from './textures.js';
import { TEAM_ROSTER, TRACKS } from './trackConfig.js';
import { modelById } from './carModels.js';
import { clamp, damp, formatTime, formatDelta } from './util.js';

const ST = { MENU: 'menu', COUNTDOWN: 'countdown', RACING: 'racing', PAUSED: 'paused', FINISHED: 'finished' };
const CAM_MODES = ['追尾远', '追尾近', '车头盖'];
const $ = (id) => document.getElementById(id);

const DIFF_PRESETS = {
    easy: { label: '轻松', skills: [0.90, 0.86, 0.83] },
    normal: { label: '标准', skills: [1.00, 0.97, 0.94] },
    hard: { label: '硬核', skills: [1.06, 1.03, 1.00] },
};

// 整场游戏编排：场景装配 / 状态机 / 定步物理 / 相机 / 竞速判定
export class Game {
    constructor(renderer, scene, camera) {
        this.renderer = renderer;
        this.scene = scene;
        this.camera = camera;

        scene.fog = new THREE.Fog(0xdfe9ee, 320, 2200);

        // ---- 环境反射（PMREM 渐变天空）----
        const pmrem = new THREE.PMREMGenerator(renderer);
        const envScene = new THREE.Scene();
        const skyMat = skyMaterial();
        envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 24, 12), skyMat));
        scene.environment = pmrem.fromScene(envScene, 0.04).texture;
        pmrem.dispose();

        // ---- 赛道（全部预构建，切换显隐）与环境 ----
        this.trackDefs = TRACKS;
        this.tracks = TRACKS.map((def) => new RaceTrack(scene, renderer, def));
        const savedTrackId = localStorage.getItem('rr_track');
        this.trackIdx = Math.max(0, TRACKS.findIndex((t) => t.id === savedTrackId));
        this.track = this.tracks[this.trackIdx];
        this.tracks.forEach((t, i) => t.setVisible(i === this.trackIdx));
        this.env = createEnvironment(scene, this.tracks, renderer);
        this.env.setTheme(this.trackDefs[this.trackIdx].theme);

        // ---- 车辆 ----
        // 玩家车型可在主菜单切换（?car=id 可直接指定），AI 各开一款以示区分
        const carParam = new URLSearchParams(location.search).get('car');
        this.carModelId = carParam || localStorage.getItem('rr_car') || TEAM_ROSTER[0].model;
        this.cars = [];
        const vScene = scene;
        TEAM_ROSTER.forEach((team, i) => {
            const visual = buildCar(team.color, vScene,
                { model: i === 0 ? this.carModelId : team.model, accent: team.accent });
            const veh = new Vehicle(this.track, { isPlayer: i === 0 });
            const rec = {
                veh, visual,
                team, teamIdx: i,
                ai: null,
                rollCur: 0, pitchCur: 0, bobPhase: Math.random() * 10,
                finishTime: null, bestLap: null, lastLap: null,
                _lapStamp: 0, _resultRowDirty: false,
            };
            if (i > 0) rec.ai = new AIController(veh, this.track, { skill: 1 });
            this.cars.push(rec);
        });
        this.player = this.cars[0];

        // 圈程回调：玩家走完整计时流程，AI 只记录圈速（供结算表）
        for (const rec of this.cars) {
            rec.veh.onLapComplete = (nf) => {
                if (rec.teamIdx === 0) { this.onLapComplete(nf); return; }
                const nowMs = this.simTime * 1000;
                rec.lastLap = nowMs - (rec._lapStamp || 0);
                rec._lapStamp = nowMs;
                if (rec.bestLap == null || rec.lastLap < rec.bestLap) rec.bestLap = rec.lastLap;
            };
        }

        // ---- 子系统 ----
        this.fx = new Effects(scene);
        this.hud = new HUD(TEAM_ROSTER.map((t) => t.color));
        this.hud.initMinimap(this.track);
        this.input = new InputManager();
        this.audio = new AudioManager();

        this.state = ST.MENU;
        this.totalLaps = parseInt(localStorage.getItem('rr_laps') || '3', 10) || 3;
        this.difficulty = localStorage.getItem('rr_diff') || 'normal';
        // 调试参数：?autodrive=1 玩家由AI代驾；&laps=N 指定圈数；&track=id 指定赛道
        this._autoDrive = new URLSearchParams(location.search).has('autodrive')
            ? new AIController(this.player.veh, this.track, { skill: 1.02 }) : null;
        const lapsParam = parseInt(new URLSearchParams(location.search).get('laps'), 10);
        if (lapsParam >= 1 && lapsParam <= 20) this.totalLaps = lapsParam;
        const trackParam = new URLSearchParams(location.search).get('track');
        if (trackParam) {
            const ti = this.trackDefs.findIndex((t) => t.id === trackParam);
            if (ti >= 0) {
                this.trackIdx = ti;
                this.track = this.tracks[ti];
                this.tracks.forEach((t, i) => t.setVisible(i === ti));
                this.env && this.env.setTheme(this.trackDefs[ti].theme);
                localStorage.setItem('rr_track', trackParam);
            }
        }
        this.camMode = 0;
        this.simTime = 0;              // 比赛计时秒（暂停不累计）
        this.raceClockRunning = true;  // FINISHED 后仍为 AI 计时
        this.countT = 0;
        this.shake = 0;
        this._acc = 0;
        this._nowS = 0;
        this._rescueCd = 0;
        this._bestStored = parseFloat(localStorage.getItem('rr_best_lap_v1')) || null;
        this._wasMuted = false;
        this._hudTick = 0;
        this._standingsTick = 0;
        this.menuAngle = 0;

        this.hud.el.btnStart.addEventListener('click', () => this.startFromMenu());
        this.hud.el.lapsSel.value = String(this.totalLaps);
        this.hud.el.diffSel.value = this.difficulty;
        // URL 调试圈数可能不在选项里（如 laps=1），此时不动下拉框避免显示空
        if (this.hud.el.lapsSel.selectedIndex < 0) this.hud.el.lapsSel.value = '3';
        // 赛道选择器
        const trackSel = this.hud.el.trackSel;
        this.trackDefs.forEach((def, i) => {
            const opt = document.createElement('option');
            opt.value = String(i);
            opt.textContent = def.name;
            trackSel.appendChild(opt);
        });
        trackSel.value = String(this.trackIdx);
        trackSel.addEventListener('change', () => this.setTrack(parseInt(trackSel.value, 10)));
        // 车型选择器（只列出真正加载成功的车模）
        const carSel = this.hud.el.carSel;
        if (carSel) {
            const avail = loadedModels();
            if (avail.length <= 1) {
                carSel.closest('label').style.display = 'none';
            } else {
                for (const m of avail) {
                    const opt = document.createElement('option');
                    opt.value = m.id;
                    opt.textContent = m.name;
                    carSel.appendChild(opt);
                }
                if (!avail.some((m) => m.id === this.carModelId)) this.carModelId = avail[0].id;
                carSel.value = this.carModelId;
                carSel.addEventListener('change', () => this.setCarModel(carSel.value));
            }
        }
        this.updateMenuSub();
        this.hud.el.lapsSel.addEventListener('change', () => {
            this.totalLaps = parseInt(this.hud.el.lapsSel.value, 10);
            localStorage.setItem('rr_laps', String(this.totalLaps));
        });
        this.hud.el.diffSel.addEventListener('change', () => {
            this.difficulty = this.hud.el.diffSel.value;
            localStorage.setItem('rr_diff', this.difficulty);
        });
        $('btnResume').addEventListener('click', () => this.togglePause());
        $('btnRestart').addEventListener('click', () => this.startRace());
        $('btnQuitPause').addEventListener('click', () => this.toMenu());
        $('btnAgain').addEventListener('click', () => this.startRace());
        $('btnQuitResults').addEventListener('click', () => this.toMenu());

        this._bindKeys();
        this.resetGrid();
        this.refreshMenuBest();
        this.hud.showOnly('menu');
    }

    get hudEl() { return this.hud.el; }

    _bindKeys() {
        this.input.onPress('KeyC', () => {
            this.camMode = (this.camMode + 1) % CAM_MODES.length;
            this.hud.showCenter(`镜头：${CAM_MODES[this.camMode]}`, '', 800);
        });
        this.input.onPress('KeyR', () => this.rescue());
        this.input.onPress('KeyM', () => {
            this.audio.ensure();
            this.audio.setMuted(!this.audio.muted);
            this.hud.showCenter(this.audio.muted ? '🔇 已静音' : '🔊 声音开启', '', 700);
        });
        this.input.onPress('Escape', () => this.togglePause());
        this.input.onPress('KeyP', () => this.togglePause());
        this.input.onPress('Enter', () => { if (this.state === ST.MENU) this.startFromMenu(); });
        // 调试：?autostart=1 自动开赛
        if (new URLSearchParams(location.search).has('autostart')) {
            setTimeout(() => { if (this.state === ST.MENU) this.startFromMenu(); }, 800);
        }
    }

    refreshMenuBest() {
        this.hud.setBestLapMenu(this._bestStored != null && isFinite(this._bestStored) ? this._bestStored : null);
    }

    // ---------- 车型切换 ----------
    setCarModel(id) {
        if (id === this.carModelId) return;
        this.carModelId = id;
        localStorage.setItem('rr_car', id);
        const rec = this.player;
        rec.visual.dispose();
        rec.visual = buildCar(rec.team.color, this.scene,
            { model: id, accent: rec.team.accent });
        this.syncVisual(rec, 0.016);
        this.updateMenuSub();
    }

    // ---------- 赛道切换 ----------
    setTrack(idx) {
        if (idx === this.trackIdx || !this.tracks[idx]) return;
        this.trackIdx = idx;
        this.track = this.tracks[idx];
        this.tracks.forEach((t, i) => t.setVisible(i === idx));
        this.env.setTheme(this.trackDefs[idx].theme);
        // 车辆与 AI 引用同步到新赛道，并把车摆上发车格供菜单展示
        for (const rec of this.cars) {
            rec.veh.track = this.track;
            if (rec.ai) rec.ai.track = this.track;
            if (rec.aiCruise) rec.aiCruise.track = this.track;
        }
        this.cars.forEach((c, i) => c.veh.placeAt(this.track.gridPose([3, 2, 1, 0][i])));
        this.fx.clearSkids();
        this.hud.initMinimap(this.track);
        localStorage.setItem('rr_track', this.trackDefs[idx].id);
        this.updateMenuSub();
    }

    updateMenuSub() {
        const def = this.trackDefs[this.trackIdx];
        const el = $('menuSub');
        const car = modelById(this.carModelId);
        if (el) el.textContent = `${def.name} · ${def.desc}　|　座驾：${car.name} · ${car.desc}`;
    }

    // ---------- 流程 ----------
    startFromMenu() {
        this.audio.ensure();
        this.startRace();
    }

    startRace() {
        const skills = DIFF_PRESETS[this.difficulty].skills;
        // 技能分配：最快的排杆位，玩家末位发车
        const slots = [[1, 0], [2, 1], [3, 2], [0, 3]];   // [carIdx, gridSlot]
        this.cars.forEach((c, i) => { c.ai && (c.ai.skill = skills[i - 1]); c.ai && c.ai.reset(); });
        this._autoDrive && this._autoDrive.reset();
        this.player.aiCruise = null;

        this.gridOrder = slots.map(([ci, s]) => s);
        for (const [ci, s] of slots) {
            const rec = this.cars[ci];
            rec.veh.placeAt(this.track.gridPose(s));
            rec.finishTime = null; rec.bestLap = null; rec.lastLap = null;
            rec._lapStamp = 0;
        }
        this.simTime = 0;
        this.raceClockRunning = true;
        this.playerFinishTime = null;
        this.fx.clearSkids();
        this.countT = 3.99;
        this.track.setLampStage(0);
        this.setState(ST.COUNTDOWN);
        this.lapNumDisplay = 1;
        this.hud.showCenter('准备…', `${this.difficulty === 'easy' ? '轻松' : this.difficulty === 'hard' ? '硬核' : '标准'} · ${this.totalLaps} 圈`, 1400);
    }

    setState(s) {
        this.state = s;
        this.hud.showOnly(
            s === ST.MENU ? 'menu'
                : s === ST.PAUSED ? 'pause'
                    : s === ST.FINISHED ? 'results'
                        : 'hud');
        const driving = s === ST.RACING || s === ST.FINISHED || s === ST.COUNTDOWN;
        this.input.enabled = driving && s !== ST.COUNTDOWN ? true : s === ST.COUNTDOWN;
        // 音频连续性
        if (!driving) {
            this.audio.updateEngine(0.1, 0, false);
            this.audio.updateSkid(0);
            this.audio.updateWind(0);
            this.audio.updateRumble(false, 0);
        }
    }

    togglePause() {
        if (this.state === ST.RACING || this.state === ST.COUNTDOWN) {
            this._pausedFrom = this.state;
            this.setState(ST.PAUSED);
            this.hud.showCenter('', '', 0);
        } else if (this.state === ST.PAUSED) {
            this.countdownResumeFlag = true;
            this.setState(this._pausedFrom || ST.RACING);
        }
    }

    toMenu() {
        this.setState(ST.MENU);
        this.refreshMenuBest();
    }

    rescue() {
        if (this.state !== ST.RACING || this._rescueCd > 0) return;
        this._rescueCd = 1;
        const p = this.player.veh;
        p.pos.copy(this.track.pts[p.qIdx]);
        p.heading = this.track.ang[p.qIdx];
        p.vf = p.vl = p.yawRate = 0;
    }

    // ---------- 发车格 ----------
    resetGrid() {
        this.cars.forEach((c, i) => c.veh.placeAt(this.track.gridPose([3, 2, 1, 0][i])));
        // 静止展示用：速度清零
    }

    // ---------- 主帧 ----------
    frame(dtRealMs) {
        const dt = Math.min(dtRealMs / 1000, 0.1);
        this._nowS += dt;
        this._rescueCd = Math.max(0, this._rescueCd - dt);

        // 固定步长模拟
        this._acc += dt;
        const H = 1 / 120;
        let n = 0;
        while (this._acc >= H && n++ < 10) {
            this.stepSim(H);
            this._acc -= H;
        }

        // 视觉同步 & 特效（每渲染帧）
        for (const rec of this.cars) this.syncVisual(rec, dt);
        this.fxSurfaceLoop();
        this.fx.update(dt);
        this.env.followShadow(this.player.veh.pos);
        this.env.updateClouds(dt);

        // 音效参数
        const pv = this.player.veh;
        const running = this.state === ST.RACING || this.state === ST.FINISHED || this.state === ST.COUNTDOWN;
        const revving = this.state === ST.COUNTDOWN && pv.input.throttle > 0;
        this.audio.updateEngine(
            this.state === ST.COUNTDOWN && revving ? 0.62 + 0.18 * Math.sin(this._nowS * 9) : pv.rpmNorm,
            pv.engineLoadSmoothed, running && !this.audio.muted);
        const skidVol = this.state === ST.RACING
            ? clamp(pv.slipAmount * 1.2, 0, 1) * clamp(Math.abs(pv.vf) / 16, 0, 1) : 0;
        this.audio.updateSkid(skidVol);
        this.audio.updateWind(clamp(Math.abs(pv.vf) / pv.topSpeed, 0, 1));
        this.audio.updateRumble(this.state === ST.RACING && pv.surface !== 'road', Math.abs(pv.vf));

        // 碰撞消费
        this.consumeCollisions();

        this.updateCamera(dt);
        this.updateHUD(dt);
    }

    // ---------- 固定步长模拟 ----------
    stepSim(h) {
        const s = this.state;
        if (s === ST.PAUSED || s === ST.MENU) return;

        if (s === ST.COUNTDOWN) {
            this.countT -= h;
            const stg = this.countT > 3 ? 0 : this.countT > 2 ? 1 : this.countT > 1 ? 2 : this.countT > 0 ? 3 : 4;
            this.track.setLampStage(stg);
            if (this.countT <= 3 && this.countT + h > 3) { this.hud.countdown(3); this.audio.beep(430, 0.12, 0.22); }
            if (this.countT <= 2 && this.countT + h > 2) { this.hud.countdown(2); this.audio.beep(430, 0.12, 0.22); }
            if (this.countT <= 1 && this.countT + h > 1) { this.hud.countdown(1); this.audio.beep(430, 0.12, 0.22); }
            if (this.countT <= 0) {
                this.hud.countdown('GO');
                this.audio.beep(870, 0.4, 0.26);
                this.setState(ST.RACING);
            }
            // 引擎轰鸣但不移动
            const is = this.input.sample(h);
            this.player.veh.input.throttle = is.throttle;
            this.player.veh.input.brake = 0;
            return;
        }

        // RACING / FINISHED 都持续模拟
        if (s !== ST.RACING && s !== ST.FINISHED) return;

        // 输入
        const is = this.input.sample(h);
        const pin = this.player.veh.input;
        if (this.player.veh.finished) {
            this.player.aiCruise ||= new AIController(this.player.veh, this.track, {});
            this.player.aiCruise.cruise();
        } else if (this._autoDrive) {
            this._autoDrive.update(h, this.cars.map((c) => c.veh));
        } else {
            pin.throttle = is.throttle;
            pin.brake = is.brake;
            pin.steer = is.steer;
            pin.handbrake = !!is.handbrake;
        }

        // AI 输入 + 橡皮筋
        const dsLen = this.track.length / this.track.N;
        for (let i = 1; i < this.cars.length; i++) {
            const rec = this.cars[i];
            const gapIdx = rec.veh.contIdx - this.player.veh.contIdx;
            const secGap = gapIdx * dsLen / 40;         // 约 40 m/s 的平均速度换算成秒
            rec.ai.rubber = -clamp(secGap * 0.012, -0.05, 0.06);
            rec.ai.update(h, this.cars.map((c) => c.veh));
        }

        // 物理步进
        for (const rec of this.cars) {
            rec.veh.finishedAlreadyHandled = false;
            if (!rec.veh.finished) rec.veh.step(h);
            else rec.veh.step(h);                       // 完赛后也继续滚动（巡航）
        }
        this.resolveCarCollisions();

        // 计时
        this.simTime += h;
        const tms = this.simTime * 1000;

        // 完赛检测
        for (const rec of this.cars) {
            if (!rec.finishTime && rec.veh.lapsDone >= this.totalLaps) {
                rec.finishTime = tms;
                rec._resultRowDirty = true;
                if (rec.teamIdx === 0) this.onPlayerFinished();
            }
        }
    }

    onLapComplete(nf) {
        const pv = this.player.veh;
        const lapMs = this.simTime * 1000 - this.player._lapStamp;
        this.player._lapStamp = this.simTime * 1000;
        this.player.lastLap = lapMs;
        let isBest = false;
        if (this.player.bestLap == null || lapMs < this.player.bestLap) {
            this.player.bestLap = lapMs; isBest = true;
        }
        if (this._bestStored == null || lapMs < this._bestStored) {
            this._bestStored = lapMs;
            localStorage.setItem('rr_best_lap_v1', String(lapMs));
        }
        // 存全局最快圈供结算对比
        if (nf < this.totalLaps) {
            this.hud.flashLap(nf, formatDelta(lapMs / 1000 - (this.player.bestLap ?? lapMs) / 1000 || null), isBest);
        }
        this.lapNumDisplay = Math.min(nf + 1, this.totalLaps);
    }

    onPlayerFinished() {
        this.playerFinishTime = this.simTime * 1000;
        this.player.veh.finished = true;
        this.setState(ST.FINISHED);
        this.buildResults();
        const pos = this.computePositions().findIndex((r) => r.isPlayer) + 1;
        setTimeout(() => {
            this.hud.showCenter(pos === 1 ? '🏆 冠军！' : `以第 ${pos} 名完赛`, '', 2600, pos === 1 ? 'go' : '');
        }, 300);
    }

    computePositions() {
        const arr = this.cars.map((c) => ({
            name: c.team.name, idx: c.teamIdx, isPlayer: c.teamIdx === 0,
            prog: c.veh.contIdx + (c.finishTime != null ? 100000 : 0),
            finishTime: c.finishTime, bestLap: c.bestLap,
        }));
        arr.sort((a, b) => b.prog - a.prog);
        return arr;
    }

    buildResults() {
        const positions = this.computePositions();
        const rows = positions.map((p, i) => ({
            pos: i + 1, name: p.name, teamIdx: p.idx, isPlayer: p.isPlayer,
            time: p.finishTime != null ? formatTime(p.finishTime) : '进行中',
            bestLap: p.bestLap != null ? formatTime(p.bestLap) : '--',
        }));
        this._latestRows = rows;
        this.hud.showResults(rows);
    }

    resolveCarCollisions() {
        const cars = this.cars;
        for (let i = 0; i < cars.length; i++) {
            for (let j = i + 1; j < cars.length; j++) {
                const a = cars[i].veh, b = cars[j].veh;
                const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z;
                const d2 = dx * dx + dz * dz;
                const RR = 3.4;
                if (d2 > RR * RR || d2 < 1e-6) continue;
                const d = Math.sqrt(d2);
                const nx = dx / d, nz = dz / d;
                const overlap = RR - d;
                a.pos.x -= nx * overlap * 0.5; a.pos.z -= nz * overlap * 0.5;
                b.pos.x += nx * overlap * 0.5; b.pos.z += nz * overlap * 0.5;
                const va = tmpV1.set(0, 0, 0); a.worldVelocity(va);
                const vb = tmpV2.set(0, 0, 0); b.worldVelocity(vb);
                const rel = (vb.x - va.x) * nx + (vb.z - va.z) * nz;
                if (rel < 0) {
                    const imp = -rel * 0.62;
                    a.applyWorldImpulse(-nx * imp, -nz * imp);
                    b.applyWorldImpulse(nx * imp, nz * imp);
                    if ((a.isPlayer || b.isPlayer) && imp > 0.3) {
                        this._bumpCount = (this._bumpCount || 0) + 1;
                        this._bumpLog ||= [];
                        const otherVeh = a.isPlayer ? b : a;
                        const otherRec = this.cars.find((r) => r.veh === otherVeh);
                        this._bumpLog.unshift(`#${this._bumpCount} ${otherRec ? otherRec.team.name : '?'} imp=${imp.toFixed(1)}`);
                        this._bumpLog.length = Math.min(this._bumpLog.length, 3);
                    }
                    const strength = clamp(-rel / 14, 0, 1);
                    if (strength > 0.08) {
                        tmpV3.copy(a.pos).add(b.pos).multiplyScalar(0.5);
                        this.fx.carBump(tmpV3);
                        const dist = this.camera.position.distanceTo(tmpV3);
                        const vol = strength * (a.isPlayer || b.isPlayer ? 1 : clamp(1 - dist / 70, 0, 0.6));
                        if (vol > 0.04) this.audio.collision(vol * 0.9);
                        if (a.isPlayer || b.isPlayer) this.shake = Math.min(1, this.shake + strength * 0.5);
                    }
                }
            }
        }
    }

    consumeCollisions() {
        for (const rec of this.cars) {
            const vh = rec.veh;
            if (vh.hitImpulse > 0) {
                const str = vh.consumeHit();
                this.fx.wallSparks(new THREE.Vector3(vh.pos.x, 0.3, vh.pos.z));
                const dist = this.camera.position.distanceTo(vh.pos);
                const vol = str * (vh.isPlayer ? 1 : clamp(1 - dist / 70, 0, 0.6));
                if (vol > 0.05) this.audio.collision(vol);
                if (vh.isPlayer) this.shake = Math.min(1, this.shake + str * 0.8);
            }
        }
    }

    fxSurfaceLoop() {
        if (this.state === ST.RACING || this.state === ST.FINISHED) {
            for (const rec of this.cars) {
                const v = rec.veh;
                this.fx.emitSkid(v,
                    (v.drifting ? clamp(Math.abs(v.vl) / 8, 0.2, 1)
                        : (v.input.brake > 0.9 && Math.abs(v.vf) > 22 && v.surface === 'road')) ? 0.7 : 0);
                this.fx.surfaceEffects(v);
            }
        }
    }

    // ---------- 视觉 ----------
    syncVisual(rec, dt) {
        const v = rec.veh, vis = rec.visual;
        vis.group.position.set(v.pos.x, 0, v.pos.z);
        vis.group.rotation.y = v.heading;

        rec.rollCur = damp(rec.rollCur, clamp(-v.gLat * 0.045, -0.09, 0.09), 8, dt);
        rec.pitchCur = damp(rec.pitchCur, clamp(v.gLong * 0.035, -0.07, 0.07), 8, dt);
        vis.bodyPivot.rotation.z = rec.rollCur;
        vis.bodyPivot.rotation.x = rec.pitchCur;

        const spd = Math.abs(v.vf);
        let bob = Math.sin(this._nowS * (5 + spd * 0.4) + rec.bobPhase) * Math.min(spd * 0.0016, 0.011);
        if (v.surface === 'curb') bob += Math.sin(this._nowS * 55) * 0.012;
        if (v.surface === 'grass') bob += Math.sin(this._nowS * 43) * 0.02 * Math.min(spd / 20, 1);
        vis.bodyPivot.position.y = bob;

        rec.visual.wheels.FL.spin.rotation.x += (v.vf / 0.34) * dt;
        rec.visual.wheels.FR.spin.rotation.x += (v.vf / 0.34) * dt;
        rec.visual.wheels.RL.spin.rotation.x += (v.vf / 0.34) * dt;
        rec.visual.wheels.RR.spin.rotation.x += (v.vf / 0.34) * dt;
        vis.wheels.FL.pivot.rotation.y = v.steerVis;
        vis.wheels.FR.pivot.rotation.y = v.steerVis;

        vis.tailMat.emissiveIntensity = (v.input.brake > 0 || v.input.handbrake) ? 3.6 : 0.42;
    }

    // ---------- 相机 ----------
    updateCamera(dt) {
        const cam = this.camera;
        const pv = this.player.veh;
        const f = pv.forwardDir(tmpV1);
        const spdRatio = clamp(Math.abs(pv.vf) / pv.topSpeed, 0, 1);

        if (this.state === ST.MENU) {
            this.menuAngle += dt * 0.14;
            const sp = this.player.veh.pos;
            cam.position.set(sp.x + Math.cos(this.menuAngle) * 13, 3.6, sp.z + Math.sin(this.menuAngle) * 13);
            cam.lookAt(sp.x, 0.8, sp.z);
            cam.fov = damp(cam.fov, 52, 3, dt);
            cam.updateProjectionMatrix();
            return;
        }

        let wantFov;
        if (this.state === ST.FINISHED) {
            const t = this._nowS * 0.32;
            cam.position.set(
                pv.pos.x + Math.cos(t) * 10.5,
                2.9 + Math.sin(t * 0.6) * 0.7,
                pv.pos.z + Math.sin(t) * 10.5);
            cam.lookAt(pv.pos.x, 0.9, pv.pos.z);
            wantFov = 55;
        } else {
            const mode = this.camMode;
            this._camPos ||= new THREE.Vector3().copy(cam.position);
            this._camLook ||= new THREE.Vector3();

            if (mode === 2) {   // 车头盖
                this._camPos.set(
                    pv.pos.x + f.x * 0.55,
                    1.06 + Math.abs(pv.gLat) * 0.15,
                    pv.pos.z + f.z * 0.55);
                this._camLook.copy(pv.pos).addScaledVector(f, 26);
                wantFov = 72 + spdRatio * 12;
            } else {
                const dist = mode === 0 ? 8.2 : 5.9;
                const height = mode === 0 ? 2.45 : 1.95;
                const back = tmpV2.copy(pv.pos).addScaledVector(f, -dist);
                back.y += height;
                const lam = 1 - Math.exp(-(4.6 + spdRatio * 2.4) * dt);
                this._camPos.lerp(back, lam);
                const lead = tmpV3.copy(pv.pos).addScaledVector(f, 7 + spdRatio * 6);
                lead.y += 1.1;
                this._camLook.lerp(lead, 1 - Math.exp(-7.5 * dt));
                wantFov = 63 + spdRatio * 14;
            }
            cam.position.copy(this._camPos);
            cam.lookAt(this._camLook);
        }

        // 抖动（撞击积累 + 草地颠簸）
        const rumble = pv.surface === 'grass' ? clamp(Math.abs(pv.vf) * 0.006, 0, 0.4) : 0;
        this.shake = Math.max(this.shake * Math.exp(-3.2 * dt), rumble);
        if (this.shake > 0.002) {
            const a = this.shake * 0.22;
            cam.position.x += (Math.random() - 0.5) * a;
            cam.position.y += (Math.random() - 0.5) * a * 0.7;
            cam.position.z += (Math.random() - 0.5) * a;
        }
        cam.fov = damp(cam.fov, wantFov, 4, dt);
        cam.updateProjectionMatrix();
    }

    // ---------- HUD ----------
    updateHUD(dt) {
        if (this.state === ST.MENU) return;
        const pv = this.player.veh;
        // 调试探针
        if (location.search.includes('debug')) {
            const inp = this.input;
            const carsVf = this.cars.map((c) => `${c.team.name[0]}:${c.veh.vf.toFixed(1)}`).join(' ');
            this.hud.showDebug(
                `state=${this.state} enabled=${inp.enabled}\n` +
                `T=${pv.input.throttle.toFixed(2)} B=${pv.input.brake.toFixed(2)} S=${pv.input.steer.toFixed(2)} HB=${pv.input.handbrake ? 1 : 0}\n` +
                `vf=${pv.vf.toFixed(1)} vl=${pv.vl.toFixed(1)} surf=${pv.surface}\n` +
                `cars ${carsVf}\n` +
                `bumps=${this._bumpCount || 0} ${(this._bumpLog || []).join(' | ')}\n` +
                `hit=${pv.hitImpulse.toFixed(2)} keys=[${[...inp.keys]}]`);
        }
        const gearLabel = this.state === ST.RACING && pv.vf < -0.5 ? 'R'
            : this.state === ST.COUNTDOWN ? 'N' : String(pv.gear);
        this.hud.drawTach(pv.speedKmh, gearLabel, Math.max(0.04, pv.rpmNorm), pv.drifting);

        this._hudTick -= dt;
        if (this._hudTick <= 0) {
            this._hudTick = 0.12;
            const lastLap = this.player.lastLap;
            this.hud.updateTiming({
                lapNum: this.lapNumDisplay ?? 1,
                totalLaps: this.totalLaps,
                current: this.state === ST.RACING ? this.simTime * 1000 - (this.player._lapStamp || 0) : (this.player.lastLap ?? 0),
                last: lastLap, best: this.player.bestLap,
                raceTime: this.playerFinishTime ?? this.simTime * 1000,
            });
        }
        this._standingsTick -= dt;
        if (this._standingsTick <= 0 && this.state !== ST.PAUSED && this.state !== ST.MENU) {
            this._standingsTick = 0.6;
            const positions = this.computePositions();
            if (this.state === ST.RACING || this.state === ST.COUNTDOWN) {
                this.hud.updateStandings(positions.slice(0, 4));
                this.hud.updatePos(positions.findIndex((r) => r.isPlayer) + 1, 4);
            }
            // 结算页打开期间刷新未完赛 AI 成绩
            if (this.state === ST.FINISHED && this.cars.some((c) => !c.finishTime)) this.buildResults();
        }

        this.hud.drawMinimap(this.cars.map((c) => ({
            x: c.veh.pos.x, z: c.veh.pos.z, heading: -c.veh.heading,
            color: this.hud.teamHex[c.teamIdx], isPlayer: c.teamIdx === 0,
        })));

        this.hud.setWrongWay(this.state === ST.RACING && pv.wrongWayTimer > 1.4);
    }
}

const tmpV1 = new THREE.Vector3();
const tmpV2 = new THREE.Vector3();
const tmpV3 = new THREE.Vector3();
