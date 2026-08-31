import * as THREE from 'three';
import { formatTime, formatDelta } from './util.js';

const $ = (id) => document.getElementById(id);

// HUD / 菜单 / 结算 的全部 DOM 与 2D 表盘绘制
export class HUD {
    constructor(teamColors) {
        this.el = {
            menu: $('menu'), btnStart: $('btnStart'),
            lapsSel: $('lapsSel'), diffSel: $('diffSel'), trackSel: $('trackSel'), carSel: $('carSel'), bestLapMenu: $('bestLapMenu'),
            hud: $('hud'),
            minimap: $('minimap'), standings: $('standings'),
            posBig: $('posBig'), timeTotal: $('timeTotal'),
            lapNum: $('lapNum'), lapCur: $('lapCur'), lapLast: $('lapLast'), lapBest: $('lapBest'),
            tach: $('tach'),
            centerMsg: $('centerMsg'), wrongWay: $('wrongWay'),
            pauseMenu: $('pauseMenu'), resultsScreen: $('resultsScreen'),
            resultsBody: $('resultsBody'),
            touchControls: $('touchControls'),
            loadingVeil: $('loadingVeil'),
        };
        this.teamHex = teamColors.map((h) => '#' + h.toString(16).padStart(6, '0'));
        this._tachState = { needle: 0 };
        this._setupTach();
        this._resizeTach();
        window.addEventListener('resize', () => this._resizeTach());
        // 调试读数（?debug 时显示）
        const dbg = document.createElement('div');
        dbg.id = 'dbgProbe';
        dbg.style.cssText = 'position:fixed;top:8px;right:8px;z-index:50;background:rgba(0,0,0,.6);color:#0f0;' +
            'font:11px/1.5 Menlo,monospace;padding:4px 8px;border-radius:6px;display:none;white-space:pre';
        document.body.appendChild(dbg);
        this.dbg = dbg;
    }

    showDebug(v) {
        if (v == null) { this.dbg.style.display = 'none'; return; }
        this.dbg.style.display = 'block';
        this.dbg.textContent = v;
    }

    hideLoading() { this.el.loadingVeil.style.opacity = '0'; setTimeout(() => this.el.loadingVeil.remove(), 600); }

    // ---------- 界面状态 ----------
    showOnly(layer) {   // 'menu' | 'hud' | 'pause' | 'results' | 'none'
        const e = this.el;
        e.menu.classList.toggle('hidden', layer !== 'menu');
        e.hud.classList.toggle('hidden', !(layer === 'hud' || layer === 'pause' || layer === 'results'));
        e.pauseMenu.classList.toggle('hidden', layer !== 'pause');
        e.resultsScreen.classList.toggle('hidden', layer !== 'results');
    }

    setBestLapMenu(ms) {
        this.el.bestLapMenu.textContent = ms != null ? formatTime(ms) : '--:--.---';
    }

    // ---------- 中央消息 ----------
    showCenter(mainHTML, subHTML, ms = 1200, cls = '') {
        const el = this.el.centerMsg;
        el.className = cls;
        el.innerHTML = `<div class="cm-main">${mainHTML}</div>${subHTML ? `<div class="cm-sub">${subHTML}</div>` : ''}`;
        el.classList.add('visible');
        clearTimeout(this._cmTimer);
        if (ms > 0) this._cmTimer = setTimeout(() => el.classList.remove('visible'), ms);
    }
    hideCenter() { this.el.centerMsg.classList.remove('visible'); }

    countdown(v) {
        if (v == null) { this.hideCenter(); return; }
        if (v === 'GO') this.showCenter('GO!', '', 900, 'go');
        else this.showCenter(String(v), '', 800, 'cd');
    }

    setWrongWay(vis) { this.el.wrongWay.classList.toggle('visible', vis); }

    flashLap(lapIdx, deltaStr, isBest) {
        const cls = isBest ? 'best' : '';
        this.showCenter(`第 ${lapIdx} 圈完成`, deltaStr ? `与最快圈差 ${deltaStr}` : '', 2000, cls);
    }

    // ---------- 计时面板 ----------
    updateTiming(t) {
        this.el.lapNum.textContent = `${Math.min(t.lapNum, t.totalLaps)} / ${t.totalLaps}`;
        this.el.lapCur.textContent = formatTime(t.current);
        this.el.lapLast.textContent = t.last != null ? formatTime(t.last) : '--:--.---';
        this.el.lapBest.textContent = t.best != null ? formatTime(t.best) : '--:--.---';
        this.el.timeTotal.textContent = formatTime(t.raceTime);
    }

    updatePos(p, total) {
        this.el.posBig.textContent = `P${p}`;
        this.el.posBig.dataset.total = `/ ${total}`;
    }

    updateStandings(list) {
        let html = '';
        list.forEach((r, i) => {
            html += `<div class="std-row ${r.isPlayer ? 'me' : ''}">
                <span class="std-pos">${i + 1}</span>
                <span class="std-dot" style="background:${this.teamHex[r.idx]}"></span>
                <span class="std-name">${r.name}</span></div>`;
        });
        this.el.standings.innerHTML = html;
    }

    // ---------- 小地图 ----------
    initMinimap(track, canvasEl) {
        this.mmCanvas = canvasEl ?? this.el.minimap;
        const c = this.mmCanvas;
        const size = 190, dpr = Math.min(devicePixelRatio, 2);
        c.width = size * dpr; c.height = size * dpr;
        // 计算包围盒
        let minX = 1e9, maxX = -1e9, minZ = 1e9, maxZ = -1e9;
        for (const p of track.pts) {
            minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
            minZ = Math.min(minZ, p.z); maxZ = Math.max(maxZ, p.z);
        }
        const pad = 14;
        const scale = Math.min((size - pad * 2) / (maxX - minX), (size - pad * 2) / (maxZ - minZ));
        this.mmTransform = (x, z) => [
            pad + (x - minX) * scale + ((size - pad * 2) - (maxX - minX) * scale) / 2,
            size - (pad + (z - minZ) * scale + ((size - pad * 2) - (maxZ - minZ) * scale) / 2),
        ];
        // 预渲染路径
        const off = document.createElement('canvas');
        off.width = c.width; off.height = c.height;
        const g = off.getContext('2d');
        g.scale(dpr, dpr);
        g.lineJoin = 'round';
        const path = () => {
            g.beginPath();
            for (let i = 0; i <= track.N; i += 4) {
                const p = track.pts[i % track.N];
                const [mx, my] = this.mmTransform(p.x, p.z);
                i === 0 ? g.moveTo(mx, my) : g.lineTo(mx, my);
            }
            g.closePath();
        };
        path(); g.strokeStyle = 'rgba(0,0,0,0.55)'; g.lineWidth = 7.5; g.stroke();
        path(); g.strokeStyle = 'rgba(235,238,244,0.92)'; g.lineWidth = 4.5; g.stroke();
        // 起跑线标记
        const sp = track.pts[track.startIdx];
        const [sx, sy] = this.mmTransform(sp.x, sp.z);
        g.fillStyle = '#ff7a1a';
        g.beginPath(); g.arc(sx, sy, 3.6, 0, 7); g.fill();
        this.mmBake = off;
        this.mmDpr = dpr;
    }

    drawMinimap(cars) {
        const c = this.mmCanvas, g = c.getContext('2d');
        g.setTransform(1, 0, 0, 1, 0, 0);
        g.clearRect(0, 0, c.width, c.height);
        g.drawImage(this.mmBake, 0, 0);
        g.setTransform(this.mmDpr, 0, 0, this.mmDpr, 0, 0);
        for (const car of cars) {
            const [x, y] = this.mmTransform(car.x, car.z);
            if (car.isPlayer) {
                g.save();
                g.translate(x, y);
                g.rotate(car.heading);
                g.fillStyle = '#ffb84d';
                g.strokeStyle = 'rgba(0,0,0,0.7)';
                g.lineWidth = 1.5;
                g.beginPath();
                g.moveTo(0, -7); g.lineTo(4.6, 5); g.lineTo(-4.6, 5);
                g.closePath(); g.fill(); g.stroke();
                g.restore();
            } else {
                g.fillStyle = car.color;
                g.beginPath(); g.arc(x, y, 4, 0, 7); g.fill();
                g.strokeStyle = 'rgba(0,0,0,0.5)'; g.lineWidth = 1; g.stroke();
            }
        }
        g.setTransform(1, 0, 0, 1, 0, 0);
    }

    // ---------- 转速表 ----------
    _setupTach() {
        this.tachG = this.el.tach.getContext('2d');
    }
    _resizeTach() {
        const c = this.el.tach;
        const px = 210;
        const dpr = Math.min(devicePixelRatio || 1, 2);
        c.width = px * dpr; c.height = px * dpr;
        c.style.width = px + 'px'; c.style.height = px + 'px';
        this.tachPx = px; this.tachDpr = dpr;
    }

    drawTach(speedKmh, gearLabel, rpmNorm, drifting) {
        const g = this.tachG;
        const S = this.tachPx, D = this.tachDpr;
        g.setTransform(D, 0, 0, D, 0, 0);
        g.clearRect(0, 0, S, S);
        const cx = S / 2, cy = S / 2, R = S / 2 - 6;

        // 表盘底盘
        g.beginPath(); g.arc(cx, cy, R, 0, Math.PI * 2);
        g.fillStyle = 'rgba(10,13,18,0.72)';
        g.fill();
        g.lineWidth = 2;
        g.strokeStyle = 'rgba(255,255,255,0.16)';
        g.stroke();

        const A0 = Math.PI * 0.75, SWEEP = Math.PI * 1.5;   // 左下起顺时针
        // 刻度弧：正常区白、红区红
        g.lineWidth = 9;
        g.strokeStyle = 'rgba(240,244,250,0.25)';
        g.beginPath(); g.arc(cx, cy, R - 12, A0, A0 + SWEEP); g.stroke();
        g.strokeStyle = 'rgba(226,54,40,0.9)';
        g.beginPath(); g.arc(cx, cy, R - 12, A0 + SWEEP * 0.82, A0 + SWEEP); g.stroke();

        // 数字刻度 0..8（千转）
        g.fillStyle = 'rgba(255,255,255,0.75)';
        g.font = '600 10px system-ui, sans-serif';
        g.textAlign = 'center'; g.textBaseline = 'middle';
        for (let k = 0; k <= 8; k++) {
            const a = A0 + SWEEP * (k / 8);
            const tx = cx + Math.cos(a) * (R - 24);
            const ty = cy + Math.sin(a) * (R - 24);
            g.fillText(k, tx, ty);
        }

        // 指针
        const targetA = A0 + SWEEP * Math.max(0.02, rpmNorm);
        this._tachState.needle += (targetA - this._tachState.needle) * 0.35;
        const na = this._tachState.needle;
        g.strokeStyle = drifting ? '#ffd34d' : '#ff7a1a';
        g.lineWidth = 3.4;
        g.lineCap = 'round';
        g.shadowColor = 'rgba(255,122,26,0.8)';
        g.shadowBlur = 6;
        g.beginPath();
        g.moveTo(cx - Math.cos(na) * 14, cy - Math.sin(na) * 14);
        g.lineTo(cx + Math.cos(na) * (R - 26), cy + Math.sin(na) * (R - 26));
        g.stroke();
        g.shadowBlur = 0;
        g.beginPath(); g.arc(cx, cy, 5.5, 0, Math.PI * 2);
        g.fillStyle = '#23262c'; g.fill();

        // 数字速度
        g.fillStyle = '#ffffff';
        g.font = 'italic 700 38px system-ui, sans-serif';
        g.fillText(Math.round(speedKmh), cx, cy + 42);
        g.fillStyle = 'rgba(255,255,255,0.55)';
        g.font = '600 10px system-ui, sans-serif';
        g.fillText('km/h', cx, cy + 64);

        // 档位
        g.fillStyle = gearLabel === 'R' ? '#ffd34d' : '#8fd3ff';
        g.font = 'italic 800 24px system-ui, sans-serif';
        g.fillText(gearLabel, cx - R + 40, cy - 24);
        g.fillStyle = 'rgba(255,255,255,0.45)';
        g.font = '600 9px system-ui, sans-serif';
        g.fillText('GEAR', cx - R + 40, cy - 44);

        g.setTransform(1, 0, 0, 1, 0, 0);
    }

    // ---------- 结算 ----------
    showResults(rows) {
        let html = '';
        rows.forEach((r) => {
            html += `<tr class="${r.isPlayer ? 'me' : ''}">
                <td class="res-pos">P${r.pos}</td>
                <td><span class="std-dot" style="background:${this.teamHex[r.teamIdx]}"></span>${r.name}${r.isPlayer ? '<i>（你）</i>' : ''}</td>
                <td>${r.time}</td>
                <td>${r.bestLap}</td>
            </tr>`;
        });
        this.el.resultsBody.innerHTML = html;
    }
}
