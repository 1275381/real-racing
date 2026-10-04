/* =====================================================================
   js/fps/gunsData.js —— 五枪数值表（【枪械】组数据单一出口）
   数值移植：godot/scripts/guns.gd:8-24（dmg/cd/mag/reload/pellets/spread/range/price）
            godot/scripts/onfoot.gd:151-158（RECOIL 后坐力表）
            onfoot.gd:162-168（开镜散布 ×0.1）、:772-775（后坐回复 0.25s 后 45°/s、上限 6°）
   纯数据模块：不 import 任何东西，大厅/仓库/改枪台 UI 可直接读表。
   字段约定（接口冻结）：
     dmg 单发伤害 / cd 开火间隔秒 / mag 弹匣 / reload 换弹秒 /
     reloadTactical 战术换弹( reload+0.3 ) / reloadEmpty 空仓换弹( reload+1.1 ) /
     pellets 弹丸数（霰弹 6）/ spread 腰射散布弧度 / adsSpreadMul 开镜散布倍率 /
     range 射程 m / recoil {kick 上抬°, growth 连发累增, drift 水平漂移°} /
     recoilAdsMul 开镜后坐 6 折 / recoilCapDeg 后坐上限 / recoilRecover* 回复 /
     adsSpeed 开镜速度 / auto 全自动 / price 价格 / desc 描述
   表现扩展字段（枪械组内部用，大厅可忽略）：skin 配色 / snd 枪声档位 / fx 动作标志
   ===================================================================== */

export const GUNS = {
    /* 侦察手枪（副武器）：guns.gd:10-12 + onfoot.gd RECOIL pistol 行 */
    pistol: {
        id: 'pistol', name: '侦察手枪',
        desc: '伤害 25 · 半自动 · 12 发', price: 0,
        dmg: 25, cd: 0.25, mag: 12, reload: 1.2,
        reloadTactical: 1.5, reloadEmpty: 2.3,
        pellets: 1, spread: 0.012, adsSpreadMul: 0.1, range: 120,
        recoil: { kick: 0.22, growth: 0.14, drift: 0.08 },
        recoilAdsMul: 0.6, recoilCapDeg: 6,
        recoilRecoverDegPerSec: 45, recoilRecoverDelay: 0.25,
        adsSpeed: 5, auto: false,
        skin: { receiver: '#8d939c', polymer: '#26282c', mag: '#3a3d42', wood: null },
        snd: 'pistol', fx: { slideFire: true, boltCycle: false },
    },
    /* 冲锋枪：guns.gd:13-15 + onfoot.gd RECOIL smg 行 */
    smg: {
        id: 'smg', name: '冲锋枪',
        desc: '伤害 15 · 全自动 · 35 发', price: 800,
        dmg: 15, cd: 0.08, mag: 35, reload: 1.6,
        reloadTactical: 1.9, reloadEmpty: 2.7,
        pellets: 1, spread: 0.020, adsSpreadMul: 0.1, range: 150,
        recoil: { kick: 0.13, growth: 0.06, drift: 0.09 },
        recoilAdsMul: 0.6, recoilCapDeg: 6,
        recoilRecoverDegPerSec: 45, recoilRecoverDelay: 0.25,
        adsSpeed: 5, auto: true,
        skin: { receiver: '#2e3237', polymer: '#1d1f22', mag: '#26282c', wood: null },
        snd: 'smg', fx: { slideFire: false, boltCycle: false },
    },
    /* 突击步枪：guns.gd:16-18 + onfoot.gd RECOIL rifle 行（与旧 RIFLE 表逐值一致） */
    rifle: {
        id: 'rifle', name: '突击步枪',
        desc: '伤害 20 · 全自动 · 30 发', price: 1500,
        dmg: 20, cd: 0.13, mag: 30, reload: 1.5,
        reloadTactical: 1.8, reloadEmpty: 2.6,
        pellets: 1, spread: 0.015, adsSpreadMul: 0.1, range: 250,
        recoil: { kick: 0.17, growth: 0.09, drift: 0.10 },
        recoilAdsMul: 0.6, recoilCapDeg: 6,
        recoilRecoverDegPerSec: 45, recoilRecoverDelay: 0.25,
        adsSpeed: 5, auto: true,
        skin: { receiver: null, polymer: null, mag: '#b8bfa6', wood: null },   // null = 默认贴图原色
        snd: 'rifle', fx: { slideFire: false, boltCycle: false },
    },
    /* 霰弹枪：guns.gd:19-21（dmg 12×6 弹丸）+ onfoot.gd RECOIL shotgun 行 */
    shotgun: {
        id: 'shotgun', name: '霰弹枪',
        desc: '伤害 12×6 散射 · 近战毁灭性', price: 2000,
        dmg: 12, cd: 0.80, mag: 6, reload: 2.2,
        reloadTactical: 2.5, reloadEmpty: 3.3,
        pellets: 6, spread: 0.055, adsSpreadMul: 0.1, range: 60,
        recoil: { kick: 0.90, growth: 0.0, drift: 0.32 },
        recoilAdsMul: 0.6, recoilCapDeg: 6,
        recoilRecoverDegPerSec: 45, recoilRecoverDelay: 0.25,
        adsSpeed: 5, auto: false,
        skin: { receiver: '#33363b', polymer: '#4a3625', mag: '#33363b', wood: '#5a3d24' },
        snd: 'shotgun', fx: { slideFire: false, boltCycle: false },
    },
    /* 狙击步枪：guns.gd:22-24（自带 6× 密位镜）+ onfoot.gd RECOIL sniper 行 */
    sniper: {
        id: 'sniper', name: '狙击步枪',
        desc: '伤害 100 · 自带 6× 密位镜 · 5 发', price: 3000,
        dmg: 100, cd: 1.20, mag: 5, reload: 2.4,
        reloadTactical: 2.7, reloadEmpty: 3.5,
        pellets: 1, spread: 0.0, adsSpreadMul: 0.1, range: 400,
        recoil: { kick: 1.30, growth: 0.0, drift: 0.20 },
        recoilAdsMul: 0.6, recoilCapDeg: 6,
        recoilRecoverDegPerSec: 45, recoilRecoverDelay: 0.25,
        adsSpeed: 5, auto: false,
        skin: { receiver: '#3a453b', polymer: '#2c352d', mag: '#333c34', wood: null },
        snd: 'sniper', fx: { slideFire: false, boltCycle: true },
        /* 枪自带瞄具（guns.gd:23-24 builtin_scope）：未另装瞄具时生效 */
        builtinScope: { id: 'builtin_sniper', name: '原厂 6× 镜', zoom: 6.0, kind: 'sniper' },
    },
};

/* 出厂默认全枪在库（stashSpec：五把默认全在仓库） */
export const DEFAULT_OWNED = ['pistol', 'smg', 'rifle', 'shotgun', 'sniper'];

/* 默认携带（大厅出发页 fallback）：主突击步枪 + 副手枪，主副不可同枪恒合法 */
export const DEFAULT_LOADOUT = { primary: 'rifle', secondary: 'pistol' };

/* id → 枪表（未知名回退突击步枪，照 guns.gd gun_by_id 先例） */
export function gunById(id) {
    return GUNS[id] || GUNS.rifle;
}
