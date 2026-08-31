// 通用数学与格式化工具
export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
export const lerp = (a, b, t) => a + (b - a) * t;
// 帧率无关的指数平滑（趋近 target）
export const damp = (cur, target, lambda, dt) => lerp(cur, target, 1 - Math.exp(-lambda * dt));

// 角度归一化到 [-PI, PI]
export function wrapAngle(a) {
    while (a > Math.PI) a -= Math.PI * 2;
    while (a < -Math.PI) a += Math.PI * 2;
    return a;
}

export const randRange = (a, b) => a + Math.random() * (b - a);

// 毫秒 -> "m:ss.mmm"
export function formatTime(ms) {
    if (ms == null || !isFinite(ms)) return '--:--.---';
    ms = Math.max(0, Math.round(ms));
    const m = Math.floor(ms / 60000);
    const s = Math.floor((ms % 60000) / 1000);
    const t = ms % 1000;
    return `${m}:${String(s).padStart(2, '0')}.${String(t).padStart(3, '0')}`;
}

// 圈速差显示，如 "-0.324" / "+1.102"
export function formatDelta(sec) {
    if (sec == null || !isFinite(sec)) return '';
    return (sec < 0 ? '-' : '+') + Math.abs(sec).toFixed(3);
}

// 简易确定性伪随机（用于环境摆 placement 可复现）
export function mulberry32(seed) {
    let s = seed >>> 0;
    return function () {
        s |= 0; s = (s + 0x6D2B79F5) | 0;
        let t = Math.imul(s ^ (s >>> 15), 1 | s);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
