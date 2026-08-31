import { TUNING, TUNING_DEFAULTS, saveTuning, resetTuning } from './tuning.js';

// 实时调参面板：开车时按 T 呼出/隐藏，滑杆即时生效并自动保存
export function createTuningPanel() {
    loadPanelDom();

    const defs = [
        ['steerMax', '转向角度·低速打满', 0.30, 0.80, 0.01, '越小越不易过度转向'],
        ['steerFalloffStr', '高速转向衰减', 0.40, 1.80, 0.05, '越大高速方向越稳'],
        ['steerFalloffSpeed', '衰减起始车速', 12, 40, 1, '低于此速拥有全部转向力'],
        ['steerFalloffPow', '衰减曲线陡度', 1.0, 2.5, 0.05, '越大高速收得越快'],
        ['steerRate', '打轮速度', 2.0, 12.0, 0.1, '方向盘打到头的快慢'],
        ['yawResponse', '车头跟随速度', 3.0, 14.0, 0.1, '越大转向越跟手'],
        ['gripMul', '整体抓地力', 0.60, 1.40, 0.02, '越大越不容易甩尾'],
        ['gripRate', '侧滑回收速度', 3.0, 12.0, 0.1, '越大甩尾回正越快'],
        ['driftThresh', '漂移介入阈值', 1.0, 6.0, 0.1, '越大越晚进入漂移辅助'],
    ];

    const rows = {};
    const panel = document.createElement('div');
    panel.id = 'tuningPanel';
    panel.classList.add('hidden');
    let html = `<div class="tp-head"><b>操控调参</b><span>T 收起</span></div>`;
    for (const [key, label, min, max, step, tip] of defs) {
        html += `<div class="tp-row" title="${tip}">
            <div class="tp-label"><span>${label}</span><b id="tpv_${key}"></b></div>
            <input type="range" id="tps_${key}" min="${min}" max="${max}" step="${step}">
        </div>`;
    }
    html += `<div class="tp-foot">
        <button id="tpReset">恢复默认</button>
        <span class="tp-note">参数即时生效并自动保存</span>
    </div>`;
    panel.innerHTML = html;
    document.body.appendChild(panel);

    const refresh = () => {
        for (const [key, , , , , ] of defs) {
            const slider = document.getElementById('tps_' + key);
            const val = document.getElementById('tpv_' + key);
            slider.value = String(TUNING[key]);
            val.textContent = (+TUNING[key]).toFixed(2);
        }
    };
    refresh();

    for (const [key, , , , , ] of defs) {
        const slider = document.getElementById('tps_' + key);
        slider.addEventListener('input', () => {
            TUNING[key] = parseFloat(slider.value);
            document.getElementById('tpv_' + key).textContent = TUNING[key].toFixed(2);
            saveTuning();
        });
    }
    document.getElementById('tpReset').addEventListener('click', () => {
        resetTuning();
        refresh();
    });

    // T 键开关（面板自身监听，不依赖游戏状态；兼容合成事件的 key 名）
    window.addEventListener('keydown', (e) => {
        const hit = e.code === 'KeyT' || e.key === 't' || e.key === 'T';
        if (hit && !e.repeat) {
            panel.classList.toggle('hidden');
            refresh();
        }
    });
    // 调试：?panel=1 默认展开
    if (new URLSearchParams(location.search).has('panel')) panel.classList.remove('hidden');

    function loadPanelDom() {
        const css = document.createElement('style');
        css.textContent = `
#tuningPanel {
    position: fixed; top: 14px; right: 14px; z-index: 45;
    width: 268px; padding: 14px 16px 12px;
    background: linear-gradient(160deg, rgba(15,19,27,.92), rgba(9,12,18,.95));
    border: 1px solid rgba(255,255,255,.16); border-radius: 14px;
    backdrop-filter: blur(10px); color: #eef2f7;
    box-shadow: 0 16px 40px rgba(0,0,0,.45);
    pointer-events: auto;
}
#tuningPanel.hidden { display: none; }
#tuningPanel .tp-head { display: flex; justify-content: space-between; align-items: baseline;
    margin-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,.12); padding-bottom: 7px; }
#tuningPanel .tp-head b { font-style: italic; letter-spacing: .1em; color: #ff9b47; }
#tuningPanel .tp-head span { font-size: 11px; color: rgba(238,242,247,.5); }
#tuningPanel .tp-row { margin-bottom: 8px; }
#tuningPanel .tp-label { display: flex; justify-content: space-between; font-size: 12px;
    color: rgba(238,242,247,.8); margin-bottom: 2px; }
#tuningPanel .tp-label b { color: #8fd3ff; font-variant-numeric: tabular-nums; font-weight: 700; }
#tuningPanel input[type=range] { width: 100%; accent-color: #ff7a1a; cursor: pointer; height: 18px; }
#tuningPanel .tp-foot { display: flex; justify-content: space-between; align-items: center;
    margin-top: 10px; border-top: 1px dashed rgba(255,255,255,.14); padding-top: 9px; }
#tuningPanel #tpReset { appearance: none; cursor: pointer; border: 1px solid rgba(255,255,255,.2);
    background: rgba(255,255,255,.06); color: #eef2f7; font-size: 12px; font-weight: 600;
    padding: 5px 12px; border-radius: 7px; }
#tuningPanel #tpReset:hover { background: rgba(255,255,255,.14); }
#tuningPanel .tp-note { font-size: 10.5px; color: rgba(238,242,247,.45); }
@media (max-width: 720px) { #tuningPanel { width: 220px; } }`;
        document.head.appendChild(css);
    }
}
