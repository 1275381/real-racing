import { clamp } from './util.js';
import { TUNING } from './tuning.js';

// 键盘 + 触屏输入管理
// steer: -1(右)..+1(左)，throttle/brake/handbrake: 0..1
export class InputManager {
    constructor() {
        this.state = { throttle: 0, brake: 0, steer: 0, handbrake: 0 };
        this.keys = new Set();
        this._pressHandlers = new Map(); // code -> fn()
        this.touchActive = false;
        this._touch = { tThrottle: false, tBrake: false, tLeft: false, tRight: false, tHand: false };
        this.enabled = true; // 菜单/暂停时锁赛车输入，但按键事件仍派发

        window.addEventListener('keydown', (e) => {
            if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) e.preventDefault();
            if (!e.repeat) {
                const fn = this._pressHandlers.get(e.code);
                if (fn) fn();
            }
            this._addKey(e);
        });
        window.addEventListener('keyup', (e) => this._removeKey(e));
        // 失焦清空，防止按键卡住
        window.addEventListener('blur', () => this.keys.clear());

        this._setupTouch();
    }

    onPress(code, fn) { this._pressHandlers.set(code, fn); }

    // 兼容合成事件：e.code 缺失时用 e.key 推导；同时登记小写别名
    _keyIds(e) {
        const ids = new Set();
        if (e.code) {
            ids.add(e.code);
            const alias = e.code.replace(/^Key/, '').toLowerCase();
            if (alias.length === 1) ids.add(alias);
        }
        if (e.key) {
            ids.add(e.key.toLowerCase());
            if (e.key === ' ') ids.add('Space');
            if (e.key.length === 1) ids.add('Key' + e.key.toUpperCase());
        }
        return ids;
    }
    _addKey(e) { for (const id of this._keyIds(e)) this.keys.add(id); }
    _removeKey(e) { for (const id of this._keyIds(e)) this.keys.delete(id); }

    key(...codes) {
        for (const c of codes) {
            if (this.keys.has(c)) return true;
            if (this.keys.has(c.toLowerCase())) return true;
            const alias = c.replace(/^Key/, '').toLowerCase();
            if (alias.length === 1 && this.keys.has(alias)) return true;
        }
        return false;
    }

    // 每帧调用：汇总为模拟量
    sample(dt) {
        const s = this.state;
        if (!this.enabled) {
            // 菜单/暂停时输入衰减为 0
            s.throttle *= 0.8; s.brake *= 0.8; s.steer *= 0.8; s.handbrake = 0;
            return s;
        }
        let steerTarget = 0;
        let th = 0, br = 0;

        if (this.key('KeyW', 'ArrowUp')) th = 1;
        if (this.key('KeyS', 'ArrowDown')) br = 1;
        if (this.key('KeyA', 'ArrowLeft')) steerTarget += 1;   // 左转 = +（约定见 physics）
        if (this.key('KeyD', 'ArrowRight')) steerTarget -= 1;
        const hand = this.key('Space') ? 1 : 0;

        if (this._touch.tThrottle) th = 1;
        if (this._touch.tBrake) br = 1;
        if (this._touch.tLeft) steerTarget += 1;
        if (this._touch.tRight) steerTarget -= 1;

        // 平滑转向，快速回正
        const rate = steerTarget === 0 ? 10 : TUNING.steerRate;
        s.steer += clamp(steerTarget - s.steer, -rate * dt, rate * dt);
        s.throttle = th;
        s.brake = br;
        s.handbrake = hand || (this._touch.tHand ? 1 : 0);
        return s;
    }

    _setupTouch() {
        const coarse = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
        if (!coarse) return;
        this.touchActive = true;
        const mk = (label, cls, bind) => {
            const el = document.createElement('div');
            el.className = 'touch-btn ' + cls;
            el.textContent = label;
            const set = (v) => (e) => { e.preventDefault(); this._touch[bind] = v; el.classList.toggle('active', v); };
            el.addEventListener('pointerdown', set(true));
            el.addEventListener('pointerup', set(false));
            el.addEventListener('pointercancel', set(false));
            el.addEventListener('pointerleave', set(false));
            document.getElementById('touchControls').appendChild(el);
        };
        mk('◀', 't-left', 'tLeft');
        mk('▶', 't-right', 'tRight');
        mk('手刹', 't-hand', 'tHand');
        mk('刹车', 't-brake', 'tBrake');
        mk('油门', 't-gas', 'tThrottle');
    }
}
