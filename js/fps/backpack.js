/* =====================================================================
 * js/fps/backpack.js —— 局内背包（【战利品】组）
 * 12 格纯数据容器：不碰 DOM、零 import（连 three 都不引）。
 * 事件契约（interfaces）：
 *   onChanged(items) —— 每次增删后回调（集成者接 hud.setBag）；
 *   onFull(item)     —— 满员拒收时回调（集成者接 toast「背包已满」）。
 * 生命周期：main 出发时 clear()，撤离/阵亡/放弃时由结算读 items 快照
 * （win → stash.depositItems，lose → 整包丢弃），本模块不做持久化。
 * ===================================================================== */

export class Backpack {
    constructor(capacity = 12) {
        this.capacity = capacity;       // 格子上限（计划定值 12）
        this.items = [];                // loot.rollLoot 产物：{uid,name,rarity,value,kind,icon}
        this.onChanged = null;          // (items) => void
        this.onFull = null;             // (item) => void —— 被拒的那件
    }

    /* 放入：成功 true；满时回调 onFull(item) 并返回 false（不部分收纳） */
    add(item) {
        if (!item) return false;
        if (this.items.length >= this.capacity) {
            if (typeof this.onFull === 'function') this.onFull(item);
            return false;
        }
        this.items.push(item);
        this._emit();
        return true;
    }

    /* 按 uid 移除，返回被移除项（没有则 null） */
    remove(uid) {
        const i = this.items.findIndex((it) => it && it.uid === uid);
        if (i < 0) return null;
        const it = this.items.splice(i, 1)[0];
        this._emit();
        return it;
    }

    totalValue() {
        return this.items.reduce((s, it) => s + ((it && it.value) || 0), 0);
    }

    used() {
        return this.items.length;
    }

    has(uid) {
        return this.items.some((it) => it && it.uid === uid);
    }

    /* 出发/重开时清空（不触发 onFull；onChanged 照常通知刷新 HUD） */
    clear() {
        if (!this.items.length) return;
        this.items.length = 0;
        this._emit();
    }

    _emit() {
        if (typeof this.onChanged === 'function') this.onChanged(this.items);
    }
}
