/* =====================================================================
   js/fps/combat.js —— 命中聚合（【玩家AI】组）
   CombatWorld：聚合各 raycast provider（敌兵 / 靶 / 墙体）取最近命中；
   applyHit 按命中类型把伤害分发给对应 provider，并把 {killed, head}
   汇总给 hitmarker / 击杀播报。
   玩家枪与敌兵枪共用本入口做几何判定（墙体遮挡走 CollisionWorld.rayWall）。
   跨组约定：provider = { raycast(from,dir,maxD), damage(...), damageStyle }；
     damageStyle='head' → damage(index, dmg, head)   （敌兵：内部再乘爆头 ×2）
     damageStyle='hit'  → damage(index, dmg, hit)    （靶：用 hit.ring 计环分）
     缺省               → damage(index, dmg)
   ===================================================================== */
import * as THREE from 'three';

export class CombatWorld {
    constructor() {
        this.providers = [];
        this.walls = null;              // CollisionWorld（setWalls 注入）
    }

    setWalls(collision) {
        this.walls = collision || null;
    }

    addProvider(provider) {
        if (provider && typeof provider.raycast === 'function') {
            this.providers.push(provider);
        }
    }

    /* ==== 1. 聚合射线：各 provider 取最近，再和墙体比较 ==== */
    raycast(from, dir, maxD) {
        let best = null;
        for (const p of this.providers) {
            const hit = p.raycast(from, dir, maxD);
            if (hit && hit.dist > 0 && (!best || hit.dist < best.dist)) {
                best = hit;
                best._p = best._p || p;
            }
        }
        if (this.walls && typeof this.walls.rayWall === 'function') {
            const limit = best ? best.dist : maxD;
            const wd = this.walls.rayWall(from, dir, limit);
            if (wd < limit) {
                best = {
                    type: 'wall', index: -1,
                    point: new THREE.Vector3().copy(dir).multiplyScalar(wd).add(from),
                    dist: wd, _p: null,
                };
            }
        }
        return best;
    }

    /* ==== 2. 伤害分发：返回 {killed, head}（HUD hitmarker 用） ==== */
    applyHit(hit, dmg) {
        if (!hit || !hit._p) return { killed: false, head: false };
        const p = hit._p;
        const head = hit.type === 'enemy_head';
        try {
            if (p.damageStyle === 'head') {
                const r = p.damage(hit.index, dmg, head);
                return { killed: !!(r && r.killed), head };
            }
            if (p.damageStyle === 'hit') {
                const r = p.damage(hit.index, dmg, hit);
                return { killed: !!(r && r.killed), head: false };
            }
            if (typeof p.damage === 'function') {
                const r = p.damage(hit.index, dmg);
                return { killed: !!(r && r.killed), head: false };
            }
        } catch (err) {
            /* provider 异常不拖垮开火循环 */
            return { killed: false, head };
        }
        return { killed: false, head };
    }
}
