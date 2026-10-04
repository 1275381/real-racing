/* ============================================================
 * js/fps/stash.js —— 大厅经济/仓库/持久化（【大厅】组）
 * localStorage 键 'fps_dt_save_v1'（与 rangeMode 的 fps_range_best 无关）：
 *   { v:1, cash, items[], guns:{owned[],scopes{gunId:scopeId|null},scopesOwned[]},
 *     loadout:{primary,secondary}, stats:{raids,extracts,deaths,kills} }
 * 读写全 try/catch（隐私模式降级内存档，rangeMode.js:23 先例）；v 不符即 wipe。
 * 纪律：对局进行中绝不写档 —— main 出发时置 stash.raidActive = true；
 * 结算入库/记战绩后调 recordRaid()（内部先复位 raidActive 再落盘）。
 * 瞄具单持约定（guns.gd:66）：同一瞄具同一时间只装在一把枪上，
 * equipScope 写入前自动从他枪卸下；'iron'/null 一律视为机瞄（可多枪同时机瞄）。
 * 只读依赖：gunsData.GUNS/DEFAULT_OWNED、scopes.SCOPES、loot.RARITY。
 * ============================================================ */
import { GUNS, DEFAULT_OWNED } from './gunsData.js';
import { SCOPES } from './scopes.js';
import { RARITY } from './loot.js';

const SAVE_KEY = 'fps_dt_save_v1';
const SAVE_VERSION = 1;

/* ==== 跨组数据防御适配器：字段名/容器形态不冻结，这里统一收敛 ==== */

// 品质档（0-6 白绿蓝紫金红彩）：兼容 {name,color,vMin,vMax,glow}（loot.js 实际
// 形态）与 {label,hex,value:[a,b]} 等命名变体
export function rarInfo(rarityId) {
    const i = Math.max(0, Math.min(6, rarityId | 0));
    const r = (RARITY && RARITY[i]) || {};
    return {
        name: r.name || r.label || r.tier || `T${i}`,
        color: r.color || r.colour || r.hex || '#d8d8d8',
        valueRange: (typeof r.vMin === 'number' && typeof r.vMax === 'number')
            ? [r.vMin, r.vMax]
            : (Array.isArray(r.value) && r.value)
                || (Array.isArray(r.range) && r.range) || null,
        glow: !!r.glow || i === 6,
    };
}

// 枪械 id 有序列表 / 单枪信息：兼容 GUNS 为键控对象或数组两种形态
export function gunIds() {
    if (Array.isArray(GUNS)) return GUNS.map((g) => g && g.id).filter(Boolean);
    return Object.keys(GUNS || {});
}
export function gunInfo(id) {
    if (Array.isArray(GUNS)) return GUNS.find((g) => g && g.id === id) || null;
    return (GUNS && GUNS[id]) || null;
}

// 瞄具有序列表 / 单个信息：兼容 SCOPES 为键控对象或数组
export function scopeList() {
    const arr = Array.isArray(SCOPES)
        ? SCOPES.slice()
        : Object.keys(SCOPES || {}).map((id) => ({ id, ...(SCOPES[id] || {}) }));
    return arr.filter((s) => s && s.id).map((s) => ({ id: s.id, info: s }));
}
export function scopeById(id) {
    return scopeList().find((s) => s.id === id) || null;
}

/* ==== Stash：现金 / 仓库变卖物 / 拥有枪械 / 已装瞄具 / 出发配置 / 战绩 ==== */
export class Stash {
    constructor() {
        this.onChanged = null;      // 资产变动回调（大厅刷新用），变动方法内部触发
        this.raidActive = false;    // true = 对局进行中：save() 拒写（防中断丢档）
        this._memOnly = false;      // localStorage 不可用 → 内存降级
        this._load();
    }

    /* ---------- 默认资产（冷启动：现金 0 / 仓库空 / 五枪在库 / rifle+pistol） ---------- */
    _defaults() {
        const valid = new Set(gunIds());
        let owned = Array.isArray(DEFAULT_OWNED) && DEFAULT_OWNED.length
            ? DEFAULT_OWNED.filter((id) => valid.has(id))
            : gunIds();
        if (!owned.length) owned = gunIds();
        return {
            cash: 0,
            items: [],                                    // rollLoot 形态 {uid,name,rarity,value,kind,icon}
            guns: { owned, scopes: {}, scopesOwned: [] },
            loadout: { primary: 'rifle', secondary: 'pistol' },
            stats: { raids: 0, extracts: 0, deaths: 0, kills: 0 },
        };
    }

    /* ---------- 读档 / 落盘 ---------- */
    _load() {
        Object.assign(this, this._defaults());
        try {
            const raw = localStorage.getItem(SAVE_KEY);
            if (!raw) return;
            const d = JSON.parse(raw);
            if (!d || d.v !== SAVE_VERSION) { this.wipe(); return; }   // 版本不符 → 重置
            this.cash = Math.max(0, Math.round(Number(d.cash) || 0));
            this.items = Array.isArray(d.items)
                ? d.items.filter((it) => it && it.uid).map((it) => ({
                    uid: String(it.uid), name: String(it.name || '战利品'),
                    rarity: Math.max(0, Math.min(6, it.rarity | 0)),
                    value: Math.max(0, Math.round(Number(it.value) || 0)),
                    kind: String(it.kind || 'misc'), icon: String(it.icon || '📦'),
                }))
                : [];
            const g = d.guns || {};
            const valid = new Set(gunIds());
            const owned = Array.isArray(g.owned) ? g.owned.filter((id) => valid.has(id)) : [];
            this.guns.owned = owned.length ? owned : this._defaults().guns.owned;
            this.guns.scopes = {};
            if (g.scopes && typeof g.scopes === 'object') {
                for (const [gid, sid] of Object.entries(g.scopes)) {
                    // 'iron' 归一化为 null（机瞄可多枪并存，不参与单持）
                    this.guns.scopes[gid] = (sid && sid !== 'iron') ? String(sid) : null;
                }
            }
            this.guns.scopesOwned = Array.isArray(g.scopesOwned)
                ? g.scopesOwned.filter((s) => typeof s === 'string' && s !== 'iron')
                : [];
            const lo = d.loadout || {};
            this.loadout = {
                primary: valid.has(lo.primary) ? lo.primary : 'rifle',
                secondary: valid.has(lo.secondary) ? lo.secondary : 'pistol',
            };
            if (this.loadout.primary === this.loadout.secondary) {
                this.loadout.secondary = this.loadout.primary === 'pistol' ? 'rifle' : 'pistol';
            }
            const st = d.stats || {};
            this.stats = {
                raids: Math.max(0, Number(st.raids) || 0),
                extracts: Math.max(0, Number(st.extracts) || 0),
                deaths: Math.max(0, Number(st.deaths) || 0),
                kills: Math.max(0, Number(st.kills) || 0),
            };
        } catch (e) {
            this._memOnly = true;   // 隐私模式 / 配额异常：内存档照常玩
        }
    }

    _serialize() {
        return {
            v: SAVE_VERSION, cash: this.cash, items: this.items,
            guns: {
                owned: this.guns.owned, scopes: this.guns.scopes,
                scopesOwned: this.guns.scopesOwned,
            },
            loadout: this.loadout, stats: this.stats,
        };
    }

    save() {
        if (this.raidActive) { console.warn('[Stash] 对局进行中，拒绝写档'); return false; }
        if (this._memOnly) return false;
        try {
            localStorage.setItem(SAVE_KEY, JSON.stringify(this._serialize()));
            return true;
        } catch (e) {
            this._memOnly = true;
            return false;
        }
    }

    _emit() { if (this.onChanged) this.onChanged(); }

    /* ---------- 现金 / 仓库 ---------- */
    setCash(n) {
        this.cash = Math.max(0, Math.round(Number(n) || 0));
        this.save(); this._emit();
    }

    // 撤离入库：整包带回（uid 去重），返回实际入库件数
    depositItems(items) {
        if (!Array.isArray(items)) return 0;
        let n = 0;
        for (const it of items) {
            if (!it || !it.uid) continue;
            if (this.items.some((x) => x.uid === it.uid)) continue;
            this.items.push({
                uid: String(it.uid), name: String(it.name || '战利品'),
                rarity: Math.max(0, Math.min(6, it.rarity | 0)),
                value: Math.max(0, Math.round(Number(it.value) || 0)),
                kind: String(it.kind || 'misc'), icon: String(it.icon || '📦'),
            });
            n++;
        }
        if (n) { this.save(); this._emit(); }
        return n;
    }

    // 变卖单件：成功返回价值，未找到返回 0
    sellItem(uid) {
        const i = this.items.findIndex((x) => x.uid === uid);
        if (i < 0) return 0;
        const value = Math.max(0, Math.round(Number(this.items[i].value) || 0));
        this.items.splice(i, 1);
        this.cash += value;
        this.save(); this._emit();
        return value;
    }

    totalValue() {
        return this.items.reduce((s, it) => s + (Math.round(Number(it.value) || 0)), 0);
    }

    /* ---------- 瞄具（改枪台） ---------- */
    ownsScope(scopeId) {
        if (!scopeId || scopeId === 'iron') return true;   // 机瞄默认拥有
        return this.guns.scopesOwned.includes(scopeId);
    }

    scopeOf(gunId) {
        return this.guns.scopes[gunId] || null;
    }

    // 购买瞄具：已拥有直接 true；现金不足返回 false（不扣款）
    buyScope(scopeId) {
        if (!scopeId || scopeId === 'iron') return true;
        if (this.ownsScope(scopeId)) return true;
        const sc = scopeById(scopeId);
        const price = Math.max(0, Math.round(Number(sc && sc.info && sc.info.price) || 0));
        if (this.cash < price) return false;
        this.cash -= price;
        this.guns.scopesOwned.push(scopeId);
        this.save(); this._emit();
        return true;
    }

    // 装配（单持强制）：同 scopeId 自动从他枪卸下；'iron'/null = 卸下回机瞄
    equipScope(gunId, scopeId) {
        if (!gunId) return;
        const sid = (!scopeId || scopeId === 'iron') ? null : String(scopeId);
        if (sid) {
            for (const gid of Object.keys(this.guns.scopes)) {
                if (gid !== gunId && this.guns.scopes[gid] === sid) this.guns.scopes[gid] = null;
            }
        }
        this.guns.scopes[gunId] = sid;
        this.save(); this._emit();
    }

    /* ---------- 出发配置 ---------- */
    setLoadout(primary, secondary) {
        const valid = new Set(gunIds());
        const p = valid.has(primary) ? primary : this.loadout.primary;
        let s = valid.has(secondary) ? secondary : this.loadout.secondary;
        if (p === s) s = (p === 'pistol') ? 'rifle' : 'pistol';   // 主副不可同枪
        this.loadout = { primary: p, secondary: s };
        this.save(); this._emit();
    }

    /* ---------- 对局结算 ---------- */
    // 对局结束（撤离/阵亡/放弃）记战绩；内部复位 raidActive 恢复写档
    recordRaid(opt = {}) {
        const s = this.stats;
        s.raids += 1;
        if (opt.win) s.extracts += 1; else s.deaths += 1;
        s.kills += Math.max(0, Math.round(Number(opt.kills) || 0));
        this.raidActive = false;
        this.save(); this._emit();
    }

    // 仅解除写档禁令（结算路径外的回大厅兜底）
    endRaid() {
        this.raidActive = false;
    }

    /* ---------- 调试句柄（__fps.stash 用） ---------- */
    addItem(rarityId, n = 1) {
        const r = rarInfo(rarityId);
        const rng = r.valueRange;
        const base = (Array.isArray(rng) && rng.length === 2)
            ? Math.round((rng[0] + rng[1]) / 2) : 1000 * ((rarityId | 0) + 1);
        const made = [];
        for (let i = 0; i < Math.max(1, n | 0); i++) {
            made.push({
                uid: `dbg_${Date.now().toString(36)}_${i}_${Math.floor(Math.random() * 1e6)}`,
                name: `战利品（${r.name}）`, rarity: rarityId | 0,
                value: Math.max(10, Math.round(base / 10) * 10),
                kind: 'misc', icon: '📦',
            });
        }
        this.items.push(...made);
        this.save(); this._emit();
        return made.length;
    }

    /* ---------- 重置 ---------- */
    wipe() {
        Object.assign(this, this._defaults());
        this.save(); this._emit();
    }
}
