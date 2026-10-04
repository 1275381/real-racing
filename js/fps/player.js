/* =====================================================================
   js/fps/player.js —— 第一人称玩家（【玩家AI】组）
   视角：PointerLock 常规 + 自动回退（?test=1 强制回退，自动化可驱动）；
   移动：WASD / Shift 疾跑 / C 蹲伏切换 / Space 跳跃，OBB 推出 r=0.5；
   数值来源：onfoot.gd:21 眼高 1.58、onfoot.gd:640-641 灵敏度 0.0023 rad/px
   与 pitch 夹角 ±1.35；移速按 interfaces 定：走 4.8 / 疾跑 8.2 / ADS 2.6 / 蹲 2.4；
   跳跃 v0=4.5、g=12（interfaces 约定）。
   ===================================================================== */
import * as THREE from 'three';

/* ==== 1. 常量 ==== */
const WALK_SPEED = 4.8;
const RUN_SPEED = 8.2;
const ADS_SPEED = 2.6;
const CROUCH_SPEED = 2.4;
const RELOAD_SPEED_MUL = 0.85;      // 换弹期间移速 ×0.85（reloadTimeline 约定）
const EYE_STAND = 1.58;             // onfoot.gd:21 EYE_H
const EYE_CROUCH = 1.05;            // missionSpec 键位表：蹲伏眼高
const EYE_DEAD = 0.35;              // 阵亡倒地视高
const EYE_LERP = 14.0;              // onfoot.gd:767 眼高插值速率
const JUMP_V0 = 4.5;
const GRAVITY = 12.0;
const RADIUS = 0.5;                 // OBB 推出半径（interfaces）
const LOOK_SENS = 0.0023;           // onfoot.gd:640 rad/px
const PITCH_LIMIT = 1.35;           // onfoot.gd:641
const ARROW_YAW_DEG = 120;          // 回退键盘路径 ←/→ 偏航 °/s
const ARROW_PITCH_DEG = 80;         // ↑/↓ 俯仰 °/s
const LOCK_TIMEOUT_MS = 300;        // 锁定 300ms 未生效自动降级（interfaces）
const EDGE = 58.0;                  // 120m 地表（±60）内侧安全边，防走出世界
const MAX_HEALTH = 100.0;

/* ==== 2. Player 类 ==== */
export class Player {
    constructor({ camera, collision, onDamage, onDeath } = {}) {
        /* -- 注入依赖 -- */
        this.camera = camera || null;
        this.collision = collision || null;
        this.onDamage = typeof onDamage === 'function' ? onDamage : null;
        this.onDeath = typeof onDeath === 'function' ? onDeath : null;

        /* -- 公开字段（interfaces 约定） -- */
        this.yaw = 0;                       // yaw=0 面向 −Z
        this.pitch = 0;
        this.pos = new THREE.Vector3();     // 脚底位置
        this.health = MAX_HEALTH;
        this.crouch = false;
        this.sprinting = false;
        this.dead = false;
        this.isFallbackLook = false;
        this.moveSpeed = 0;                 // 当前实际移速（供枪械 bob 等参考）
        this.onFallbackLook = null;         // 回退模式激活时回调一次（HUD 提示用）

        /* -- 内部状态 -- */
        this._vy = 0;
        this._onGround = true;
        this._eyeH = EYE_STAND;
        this._bobT = 0;
        this._recoil = { pitch: 0, yaw: 0 };
        this._recoilProvider = null;        // main 注入 ()=>({pitch,yaw})
        this._moveStateProvider = null;     // main 注入 ()=>({ads:0..1, reloading:bool})
        this._keys = Object.create(null);
        this._canvas = null;
        this._locked = false;
        this._lockTimer = 0;
        this._lastPX = 0;                   // 回退模式上次指针位置
        this._lastPY = 0;
        this._hasLastP = false;
        this._fallbackNotified = false;

        if (this.camera) this.camera.rotation.order = 'YXZ';
        this._bindKeyboard();
    }

    /* -- 3. 依赖注入（鸭子类型，无共享事件总线） -- */
    setRecoilProvider(fn) {
        this._recoilProvider = typeof fn === 'function' ? fn : null;
    }
    setMoveStateProvider(fn) {
        // 返回 {ads:0..1, reloading:boolean}：ADS 移速 2.6 与换弹 ×0.85 用
        this._moveStateProvider = typeof fn === 'function' ? fn : null;
    }

    /* ==== 4. 键盘（移动键 + 回退视角键盘路径） ==== */
    _bindKeyboard() {
        this._onKeyDown = (e) => {
            if (!e.repeat) {
                if (e.code === 'KeyC' && !this.dead) this.crouch = !this.crouch;
            }
            this._keys[e.code] = true;
            if (e.code === 'Space' || e.code.startsWith('Arrow')) e.preventDefault();
        };
        this._onKeyUp = (e) => { this._keys[e.code] = false; };
        this._onBlur = () => { this._keys = Object.create(null); };
        window.addEventListener('keydown', this._onKeyDown);
        window.addEventListener('keyup', this._onKeyUp);
        window.addEventListener('blur', this._onBlur);
    }

    /* ==== 5. 视角：PointerLock 常规 + 300ms 未生效/异常自动回退 ==== */
    attachLook(canvas, forceFallback = false) {
        if (!canvas) return;
        this._canvas = canvas;

        /* -- 常规：点击 canvas 请求指针锁定 -- */
        this._onClick = () => this._requestLock(canvas);
        canvas.addEventListener('click', this._onClick);

        /* -- 锁定成功后：movementX/Y 转向（onfoot.gd:639-641） -- */
        this._onDocMove = (e) => {
            if (this._locked) this._mouseLook(e.movementX || 0, e.movementY || 0);
        };
        document.addEventListener('mousemove', this._onDocMove);

        /* -- 回退：canvas pointermove 位置增量直接转向（绝对坐标差，合成事件可驱动） -- */
        this._onPointerMove = (e) => {
            if (!this.isFallbackLook) return;
            if (this._hasLastP) {
                this._mouseLook(e.clientX - this._lastPX, e.clientY - this._lastPY);
            }
            this._lastPX = e.clientX;
            this._lastPY = e.clientY;
            this._hasLastP = true;
        };
        this._onPointerOut = () => { this._hasLastP = false; };
        canvas.addEventListener('pointermove', this._onPointerMove);
        canvas.addEventListener('pointerleave', this._onPointerOut);

        /* -- 锁定状态变化 / 出错 -- */
        this._onLockChange = () => {
            this._locked = document.pointerLockElement === canvas;
            if (this._locked) {
                clearTimeout(this._lockTimer);
            }
        };
        this._onLockError = () => this._enterFallback();
        document.addEventListener('pointerlockchange', this._onLockChange);
        document.addEventListener('pointerlockerror', this._onLockError);

        if (forceFallback) this._enterFallback();
    }

    _requestLock(canvas) {
        if (this.isFallbackLook || this._locked || this.dead) return;
        if (typeof canvas.requestPointerLock !== 'function') {
            this._enterFallback();
            return;
        }
        try {
            const p = canvas.requestPointerLock();
            if (p && typeof p.catch === 'function') {
                p.catch(() => this._enterFallback());
            }
        } catch (err) {
            this._enterFallback();
            return;
        }
        clearTimeout(this._lockTimer);
        this._lockTimer = setTimeout(() => {
            if (document.pointerLockElement !== canvas) this._enterFallback();
        }, LOCK_TIMEOUT_MS);
    }

    _enterFallback() {
        clearTimeout(this._lockTimer);
        if (this.isFallbackLook) return;
        this.isFallbackLook = true;
        this._hasLastP = false;
        if (!this._fallbackNotified) {
            this._fallbackNotified = true;
            if (typeof this.onFallbackLook === 'function') this.onFallbackLook();
        }
    }

    _mouseLook(dx, dy) {
        if (this.dead) return;
        this.yaw -= dx * LOOK_SENS;
        this.pitch = THREE.MathUtils.clamp(this.pitch - dy * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT);
    }

    /* ==== 6. 每帧更新：移动 → 碰撞 → 跳跃/重力 → 相机合成 ==== */
    update(dt) {
        /* -- 键盘转向路径（回退模式保底，任何模式都可用） -- */
        const yawRate = THREE.MathUtils.degToRad(ARROW_YAW_DEG);
        const pitchRate = THREE.MathUtils.degToRad(ARROW_PITCH_DEG);
        if (!this.dead) {
            if (this._keys['ArrowLeft']) this.yaw += yawRate * dt;
            if (this._keys['ArrowRight']) this.yaw -= yawRate * dt;
            if (this._keys['ArrowUp']) this.pitch = Math.min(PITCH_LIMIT, this.pitch + pitchRate * dt);
            if (this._keys['ArrowDown']) this.pitch = Math.max(-PITCH_LIMIT, this.pitch - pitchRate * dt);
        }

        /* -- 枪械状态（ADS/换弹影响移速；未注入时按 0 处理） -- */
        let ads = 0, reloading = false;
        if (this._moveStateProvider) {
            try {
                const ms = this._moveStateProvider() || {};
                ads = THREE.MathUtils.clamp(+ms.ads || 0, 0, 1);
                reloading = !!ms.reloading;
            } catch (err) { /* 提供方异常不拖垮移动 */ }
        }

        /* -- 输入方向（three.js：yaw=0 前向 −Z） -- */
        let f = 0, s = 0;
        if (!this.dead) {
            if (this._keys['KeyW']) f += 1;
            if (this._keys['KeyS']) f -= 1;
            if (this._keys['KeyD']) s += 1;
            if (this._keys['KeyA']) s -= 1;
        }
        const hasInput = (f !== 0 || s !== 0);
        const wantSprint = (this._keys['ShiftLeft'] || this._keys['ShiftRight'])
            && f > 0 && !this.crouch && ads < 0.5 && !this.dead;
        this.sprinting = wantSprint && hasInput;

        let speed = wantSprint ? RUN_SPEED : (this.crouch ? CROUCH_SPEED : WALK_SPEED);
        if (ads > 0.5) speed = Math.min(speed, ADS_SPEED);
        if (reloading) speed *= RELOAD_SPEED_MUL;
        this.moveSpeed = hasInput ? speed : 0;

        if (hasInput) {
            const fwdX = -Math.sin(this.yaw), fwdZ = -Math.cos(this.yaw);
            const rgtX = Math.cos(this.yaw), rgtZ = -Math.sin(this.yaw);
            let dx = fwdX * f + rgtX * s;
            let dz = fwdZ * f + rgtZ * s;
            const len = Math.hypot(dx, dz);
            if (len > 0.0001) {
                this.pos.x += (dx / len) * speed * dt;
                this.pos.z += (dz / len) * speed * dt;
            }
        }

        /* -- OBB 推出 + 地面 + 跳跃/重力 -- */
        if (this.collision) {
            const pushed = this.collision.pushOut(this.pos.x, this.pos.z, RADIUS);
            if (pushed) { this.pos.x = pushed.x; this.pos.z = pushed.z; }
        }
        const groundY = this.collision
            ? (this.collision.groundHeight(this.pos.x, this.pos.z) || 0) : 0;
        if (!this.dead && this._keys['Space'] && this._onGround) {
            this._vy = JUMP_V0;
            this._onGround = false;
        }
        this._vy -= GRAVITY * dt;
        this.pos.y += this._vy * dt;
        if (this.pos.y <= groundY) {
            this.pos.y = groundY;
            if (this._vy < 0) this._vy = 0;
            this._onGround = true;
        } else {
            this._onGround = false;
        }

        /* -- 世界边界兜底 -- */
        this.pos.x = THREE.MathUtils.clamp(this.pos.x, -EDGE, EDGE);
        this.pos.z = THREE.MathUtils.clamp(this.pos.z, -EDGE, EDGE);

        /* -- 眼高插值 + 走路轻微点头（onfoot.gd:767-769） -- */
        const eyeTarget = this.dead ? EYE_DEAD : (this.crouch ? EYE_CROUCH : EYE_STAND);
        this._eyeH = THREE.MathUtils.lerp(this._eyeH, eyeTarget, 1 - Math.exp(-EYE_LERP * dt));
        this._bobT += dt * (this.moveSpeed > 0.1 ? 7.5 : 2.0);
        const bob = Math.sin(this._bobT) * 0.02 * Math.min(this.moveSpeed / WALK_SPEED, 1);

        /* -- 相机姿态合成：Euler(pitch+recoil, yaw+recoil, 0, 'YXZ') -- */
        if (this.camera) {
            this.camera.position.set(this.pos.x, this.pos.y + this._eyeH + bob, this.pos.z);
            if (this._recoilProvider) {
                try { Object.assign(this._recoil, this._recoilProvider() || {}); } catch (err) { /* 保持旧值 */ }
            }
            const rp = +this._recoil.pitch || 0;
            const ry = +this._recoil.yaw || 0;
            this.camera.rotation.set(
                THREE.MathUtils.clamp(this.pitch, -PITCH_LIMIT, PITCH_LIMIT) + rp,
                this.yaw + ry, 0);
        }
    }

    /* ==== 7. 查询 / 受击 / 重生 ==== */
    eyePos() {
        return new THREE.Vector3(this.pos.x, this.pos.y + this._eyeH, this.pos.z);
    }
    footDir() {
        // 水平前向（yaw=0 面向 −Z）
        return new THREE.Vector3(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    }
    takeDamage(dmg, fromPos) {
        if (this.dead || dmg <= 0) return false;
        this.health = Math.max(0, this.health - dmg);
        if (typeof this.onDamage === 'function') this.onDamage(dmg, fromPos);
        if (this.health <= 0) {
            this.dead = true;
            this.sprinting = false;
            if (typeof this.onDeath === 'function') this.onDeath();
        }
        return true;
    }
    respawn(pos) {
        this.dead = false;
        this.health = MAX_HEALTH;
        this.crouch = false;
        this.sprinting = false;
        this._vy = 0;
        this._onGround = true;
        this._eyeH = EYE_STAND;
        if (pos) this.pos.copy(pos);
    }

    /* ==== 8. 清理 ==== */
    dispose() {
        window.removeEventListener('keydown', this._onKeyDown);
        window.removeEventListener('keyup', this._onKeyUp);
        window.removeEventListener('blur', this._onBlur);
        document.removeEventListener('mousemove', this._onDocMove);
        document.removeEventListener('pointerlockchange', this._onLockChange);
        document.removeEventListener('pointerlockerror', this._onLockError);
        if (this._canvas) {
            this._canvas.removeEventListener('click', this._onClick);
            this._canvas.removeEventListener('pointermove', this._onPointerMove);
            this._canvas.removeEventListener('pointerleave', this._onPointerOut);
        }
        clearTimeout(this._lockTimer);
    }
}
