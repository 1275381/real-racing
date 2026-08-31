import * as THREE from 'three';
import { Game } from './game.js';
import { loadCarTemplates } from './car.js';
import { loadTuning } from './tuning.js';
import { createTuningPanel } from './tuningPanel.js';

const canvas = document.getElementById('gl');
const renderer = new THREE.WebGLRenderer({
    canvas, antialias: true,
    powerPreference: 'high-performance',
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.02;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(63, innerWidth / innerHeight, 0.3, 5000);
camera.position.set(0, 6, -14);

let game;
(async () => {
    try {
        loadTuning();
        createTuningPanel();      // T 键呼出调参面板
        await loadCarTemplates();     // 全部车型并行加载，失败自动回退程序化车型
        game = new Game(renderer, scene, camera);
    } catch (err) {
        console.error(err);
        const veil = document.getElementById('loadingVeil');
        if (veil) veil.innerHTML = `<div class="veil-inner"><h2>加载失败</h2><pre>${String(err.stack || err)}</pre></div>`;
        return;
    }
    game.hud.hideLoading();
    const veil = document.getElementById('loadingVeil');
    if (veil) veil.dataset.done = '1';
    window.__game = game;   // 调试句柄

    let lastT = performance.now();
    // 屏显运行时错误（便于诊断；正常时不显示）
    const errBox = document.createElement('div');
    errBox.style.cssText = 'position:fixed;left:8px;top:8px;z-index:99;background:rgba(160,20,20,.92);color:#fff;' +
        'font:12px/1.5 Menlo,monospace;padding:8px 12px;border-radius:8px;max-width:70vw;white-space:pre-wrap;display:none';
    document.body.appendChild(errBox);
    const seenErrs = new Set();
    function reportErr(e) {
        const msg = (e && (e.stack || e.message)) || String(e);
        const key = msg.split('\n')[0];
        if (seenErrs.has(key) || seenErrs.size > 3) return;
        seenErrs.add(key);
        errBox.style.display = 'block';
        errBox.textContent += `[${new Date().toLocaleTimeString()}] ${msg.slice(0, 500)}\n`;
    }
    window.addEventListener('error', (e) => reportErr(e.error || e.message));
    window.addEventListener('unhandledrejection', (e) => reportErr(e.reason));

    function loop(t) {
        requestAnimationFrame(loop);
        const dt = Math.min(t - lastT, 100);
        lastT = t;
        try {
            game.frame(dt);
        } catch (e) { reportErr(e); }
        renderer.render(scene, camera);
    }
    requestAnimationFrame(loop);
})();

// 页面隐藏时自动暂停（仅比赛中）
document.addEventListener('visibilitychange', () => {
    if (document.hidden && game && game.state === 'racing') game.togglePause();
});

window.addEventListener('resize', () => {
    renderer.setSize(innerWidth, innerHeight);
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
});
