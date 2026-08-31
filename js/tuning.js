// 操控调参中枢：默认值 + 本地存取（physics/input 每帧实时读取）
const DEFAULTS = {
    steerMax: 0.52,        // 低速打满转向角（rad），越大低速越贼
    steerFalloffStr: 1.05, // 高速转向衰减强度，越大高速越稳
    steerFalloffSpeed: 23, // 衰减参考车速（m/s）
    steerFalloffPow: 1.6,  // 衰减曲线指数
    steerRate: 5.5,        // 方向盘打轮速度
    yawResponse: 7,        // 车头跟随转向的速度
    gripMul: 1.0,          // 整体抓地力倍率
    gripRate: 7.0,         // 侧向抓地（打滑回收速度）
    driftThresh: 2.0,      // 漂移辅助介入的侧滑阈值 (m/s)
};

export const TUNING = { ...DEFAULTS };
export const TUNING_DEFAULTS = { ...DEFAULTS };

export function loadTuning() {
    try {
        const saved = JSON.parse(localStorage.getItem('rr_tuning') || '{}');
        for (const k of Object.keys(DEFAULTS)) {
            if (typeof saved[k] === 'number' && isFinite(saved[k])) TUNING[k] = saved[k];
        }
    } catch (e) { /* 忽略坏数据 */ }
}

export function saveTuning() {
    try { localStorage.setItem('rr_tuning', JSON.stringify(TUNING)); } catch (e) { /* 忽略 */ }
}

export function resetTuning() {
    Object.assign(TUNING, DEFAULTS);
    saveTuning();
}
