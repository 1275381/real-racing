class_name HDStash
extends RefCounted
## 烽火地带 —— 经济/仓库/持久化（移植 js/fps/stash.js）
## 存档：HDData.SAVE_PATH（user://huodai_save.json，JSON + FileAccess）。
## 容错约定：文件缺失/损坏/版本不符/字段缺失 → 回默认档绝不崩；
## GDScript 无 try/catch，"try 容错" 以 FileAccess 判空 + 字段类型防御等价实现。
## 瞄具单持：同一瞄具同一时间只装一把枪，equip_scope 写入前自动从他枪卸下；
## "iron"/"" 一律视为机瞄（可多枪并存，不参与单持）。
## 契约无 set_loadout：出发页换装由大厅直接改 loadout 后 save() 并代发 changed。

signal changed

## 存档版本：2 = 2026-10 经济重定价（战利品 ÷10）。v1 档读入时迁移：现金与仓库
## 物品价值同样 ÷10，已买的枪/瞄具/弹药/配件原样保留；其余版本不符仍回默认档
const SAVE_VERSION := 2

## 默认拥有集：恰旧五枪（新枪默认不拥有、只走现金购买）。
## GUNS 扩充后绝不能再「遍历 GUNS 全送」——那是经济白送事故点
const DEFAULT_GUNS := ["pistol", "smg", "rifle", "shotgun", "sniper"]

var cash: int = 0
var items: Array = []                 # [{uid,name,icon,rarity,value}]
var guns_owned: Array = []            # 枪械 id 列表（默认五枪全有）
var scopes_owned: Array = []          # 已购瞄具 id 列表
var scope_fit: Dictionary = {}        # gun_id -> scope_id 或 "iron"
var grips_owned: Array = []           # 已购握把/护木 id 列表（GRIPS 表，2026-10 M14 首接入）
var grip_fit: Dictionary = {}         # gun_id -> grip_id 或 "none"
var ammo_inv: Dictionary = {}         # gun_id -> 极致备弹剩余发数（缺键 = 未进弹药经济，首读送礼）
var loadout: Dictionary = {"primary": "rifle", "secondary": "pistol"}
var stats: Dictionary = {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0, "time_total": 0, "contracts": 0}
var daily_last: String = ""          # 最近一次签到的日期键（YYYY-MM-DD）
var secure_slots: int = HDData.SECURE_BASE   # 安全箱格数（2 起，现金扩到 4；阵亡保留其中物品）
var durability: Dictionary = {}       # gun_id -> 耐久 0..100（缺键 = 全新 100）
var sup_owned: Array = []             # 已买消音器的枪 id（消音器按枪买，随枪丢）
var sup_off: Array = []               # 已买但拆下的枪 id（拆装免费）
var tutorial_done := false            # 首局引导已完成/跳过（老档有出击记录视为已完成）
## 合同系统（2026-10 阶段 A）：contracts_day = 发放日期键（YYYY-MM-DD，隔日重发）；
## contracts = [{id, prog, done, paid}]，def 查 HDData.CONTRACT_POOL
var contracts_day: String = ""
var contracts: Array = []
## 弹种（阶段 D）：ammo_kind = gun_id → 当前装备弹种 id（缺省 standard）；
## ammo_kinds_owned = gun_id → 已购弹种 id 数组（standard 恒有）
var ammo_kind: Dictionary = {}
var ammo_kinds_owned: Dictionary = {}
## 投掷物库存（阶段 D）：kind → 件数（买了常驻、局内消耗、阵亡不丢）
var throwables: Dictionary = {"frag": 0, "smoke": 0, "flash": 0}
## 钥匙卡库存（2026-10-24 用户定案「钥匙卡需要购买」）：lock_id → 件数；
## 开局自动注入背包（带入即风险——阵亡丢失，与局内拾取的钥匙同通道）
var keycards: Dictionary = {}


func _init() -> void:
	_load()


## 写 JSON 回盘（打开失败即静默放弃，不崩）
func save() -> void:
	var f := FileAccess.open(HDData.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_serialize()))
	f.close()


func _serialize() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"cash": cash,
		"items": items,
		"guns_owned": guns_owned,
		"scopes_owned": scopes_owned,
		"scope_fit": scope_fit,
		"grips_owned": grips_owned,
		"grip_fit": grip_fit,
		"m14_mods": m14_mods,
		"ammo_inv": ammo_inv,
		"loadout": loadout,
		"stats": stats,
		"daily_last": daily_last,
		"contracts_day": contracts_day,
		"contracts": contracts,
		"ammo_kind": ammo_kind,
		"ammo_kinds_owned": ammo_kinds_owned,
		"throwables": throwables,
		"keycards": keycards,
		"secure_slots": secure_slots,
		"durability": durability,
		"sup_owned": sup_owned,
		"sup_off": sup_off,
		"tutorial_done": tutorial_done,
	}


## 读档：先铺默认档，再逐字段防御式覆盖
func _load() -> void:
	_apply_defaults()
	if not FileAccess.file_exists(HDData.SAVE_PATH):
		return
	var f := FileAccess.open(HDData.SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return                       # 损坏 → 保持默认档
	var d: Dictionary = parsed
	var ver := _to_i(d.get("v", 0))
	if ver != SAVE_VERSION and ver != 1:
		wipe()                       # 版本不符 → 重置
		return
	# v1 → v2 迁移（经济重定价）：现金与仓库物品价值 ÷10，其余字段照常读
	var div := 10 if ver == 1 else 1
	cash = maxi(0, int(round(float(_to_i(d.get("cash", 0))) / float(div))))

	# 仓库变卖物（uid 去重 + 逐字段归一化）
	items = []
	var raw_items: Variant = d.get("items", null)
	if typeof(raw_items) == TYPE_ARRAY:
		for it in raw_items:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var norm := _norm_item(it)
			if str(norm["uid"]) == "" or _find_uid(str(norm["uid"])) >= 0:
				continue
			if div > 1:
				norm["value"] = maxi(1, int(round(float(norm["value"]) / float(div))))
			items.append(norm)

	# 枪械拥有（无效 id 过滤；清空回默认五枪——不再回退 GUNS 全集）
	var valid_guns: Array = []
	for g in Guns.GUNS:
		valid_guns.append(str(g["id"]))
	var owned: Array = []
	var raw_owned: Variant = d.get("guns_owned", null)
	if typeof(raw_owned) == TYPE_ARRAY:
		for id in raw_owned:
			var gid := str(id)
			if valid_guns.has(gid) and not owned.has(gid):
				owned.append(gid)
	guns_owned = owned if not owned.is_empty() else DEFAULT_GUNS.duplicate()
	if not guns_owned.has(HDData.PERMANENT_GUN):
		guns_owned.insert(0, HDData.PERMANENT_GUN)   # 侦察手枪永久拥有

	# 极致备弹库存（老档缺字段 → 空表：各枪首读按「首次礼物」规则送满额，见 ammo_of）
	ammo_inv = {}
	var raw_ammo: Variant = d.get("ammo_inv", null)
	if typeof(raw_ammo) == TYPE_DICTIONARY:
		for akey in raw_ammo.keys():
			var agid := str(akey)
			if valid_guns.has(agid):
				ammo_inv[agid] = maxi(0, _to_i(raw_ammo[akey]))

	# 瞄具拥有 / 装配（"iron"/"" 归一化为 "iron"，未知 id 丢弃）
	var valid_scopes: Array = []
	for sc in Guns.SCOPES:
		valid_scopes.append(str(sc["id"]))
	scopes_owned = []
	var raw_so: Variant = d.get("scopes_owned", null)
	if typeof(raw_so) == TYPE_ARRAY:
		for id in raw_so:
			var sid := str(id)
			if valid_scopes.has(sid) and not scopes_owned.has(sid):
				scopes_owned.append(sid)
	scope_fit = {}
	var raw_sf: Variant = d.get("scope_fit", null)
	if typeof(raw_sf) == TYPE_DICTIONARY:
		for key in raw_sf.keys():
			var gid2 := str(key)
			var sid2 := str(raw_sf[key])
			if not valid_guns.has(gid2):
				continue
			if sid2 == "" or sid2 == "iron":
				scope_fit[gid2] = "iron"
			elif valid_scopes.has(sid2):
				scope_fit[gid2] = sid2

	# 握把/护木拥有与装配（2026-10 M14 首接入；"none"/"" 归一化，未知 id 丢弃）
	var valid_grips: Array = []
	for gr in Guns.GRIPS:
		valid_grips.append(str(gr["id"]))
	grips_owned = ["none"]
	var raw_go: Variant = d.get("grips_owned", null)
	if typeof(raw_go) == TYPE_ARRAY:
		for id in raw_go:
			var gid3 := str(id)
			if valid_grips.has(gid3) and not grips_owned.has(gid3):
				grips_owned.append(gid3)
	grip_fit = {}
	var raw_gf: Variant = d.get("grip_fit", null)
	if typeof(raw_gf) == TYPE_DICTIONARY:
		for key in raw_gf.keys():
			var gk := str(key)
			var gval := str(raw_gf[key])
			if not valid_guns.has(gk):
				continue
			if gval == "" or gval == "none" or not valid_grips.has(gval):
				grip_fit[gk] = "none"
			else:
				grip_fit[gk] = gval

	# M14 专属配件（合法 id 过滤）
	m14_mods = []
	var raw_m14: Variant = d.get("m14_mods", null)
	if typeof(raw_m14) == TYPE_ARRAY:
		for id in raw_m14:
			var mid := str(id)
			if Guns.M14_MODS.has(mid) and not m14_mods.has(mid):
				m14_mods.append(mid)

	# 出发配置（主副不可同枪；副武器可空——阵亡丢枪后只剩一把时）
	var lo := _to_dict(d.get("loadout", null))
	var p := str(lo.get("primary", "rifle"))
	var s := str(lo.get("secondary", "pistol"))
	if not valid_guns.has(p):
		p = "rifle"
	if s != "" and not valid_guns.has(s):
		s = "pistol"
	if p == s:
		s = "pistol" if p != "pistol" else "rifle"
	loadout = {"primary": p, "secondary": s}
	repair_loadout()
	secure_slots = clampi(_to_i(d.get("secure_slots", HDData.SECURE_BASE)),
			HDData.SECURE_BASE, HDData.SECURE_MAX)

	# 战绩
	var st := _to_dict(d.get("stats", null))
	stats = {
		"raids": maxi(0, _to_i(st.get("raids", 0))),
		"extracts": maxi(0, _to_i(st.get("extracts", 0))),
		"deaths": maxi(0, _to_i(st.get("deaths", 0))),
		"kills": maxi(0, _to_i(st.get("kills", 0))),
		"time_total": maxi(0, _to_i(st.get("time_total", 0))),   # 累计局时（秒）：平均局时 = ÷ raids
		"contracts": maxi(0, _to_i(st.get("contracts", 0))),   # 合同完成数（2026-10 阶段 A）
	}
	daily_last = _to_s(d.get("daily_last", ""))

	# 合同系统（2026-10 阶段 A）：老档无字段 = 空表（首次读取时按今日种子补发）
	contracts_day = _to_s(d.get("contracts_day", ""))
	contracts = []
	var raw_ct: Variant = d.get("contracts", null)
	if typeof(raw_ct) == TYPE_ARRAY:
		var pool_ids := {}
		for pd in HDData.CONTRACT_POOL:
			pool_ids[str(pd["id"])] = pd
		for ct in raw_ct:
			if typeof(ct) != TYPE_DICTIONARY:
				continue
			var cid := _to_s(ct.get("id", ""))
			if not pool_ids.has(cid):
				continue   # 池改版后旧 id 失效 → 丢弃（次日重发）
			var defc: Dictionary = pool_ids[cid]
			contracts.append({
				"id": cid,
				"prog": clampi(_to_i(ct.get("prog", 0)), 0, _to_i(defc["n"])),
				"done": bool(ct.get("done", false)),
				"paid": bool(ct.get("paid", false)),
			})
	# 弹种 + 投掷物（阶段 D）：老档无字段 = 缺省（standard / 三件 0）
	var kind_ids := {}
	for ad in Guns.AMMO:
		kind_ids[str(ad["id"])] = true
	var raw_kinds := _to_dict(d.get("ammo_kinds_owned", null))
	for gk in raw_kinds.keys():
		var owned0: Array = []
		for k0 in (raw_kinds[gk] as Array):
			var k := str(k0)
			if kind_ids.has(k) and not owned0.has(k):
				owned0.append(k)
		if not owned0.has("standard"):
			owned0.push_front("standard")
		ammo_kinds_owned[str(gk)] = owned0
	var raw_kind := _to_dict(d.get("ammo_kind", null))
	for gk2 in raw_kind.keys():
		var kk := str(raw_kind[gk2])
		var owned_l: Array = ammo_kinds_owned.get(str(gk2), ["standard"])
		if kk == "standard" or owned_l.has(kk):
			ammo_kind[str(gk2)] = kk
	throwables = {"frag": 0, "smoke": 0, "flash": 0}
	keycards = {}
	var raw_th := _to_dict(d.get("throwables", null))
	for tk in ["frag", "smoke", "flash"]:
		throwables[tk] = clampi(_to_i(raw_th.get(tk, 0)), 0,
				_to_i(HDData.THROWABLES[tk]["max"]))
	# 钥匙卡库存（老档无字段 = 全 0；id 池外丢弃）
	var lock_ids := {}
	for ld in HDData.LOCKS:
		lock_ids[str(ld["id"])] = str(ld["key"])
	var raw_kc := _to_dict(d.get("keycards", null))
	for kid in raw_kc.keys():
		if lock_ids.has(str(kid)):
			keycards[str(kid)] = clampi(_to_i(raw_kc[kid]), 0, HDData.KEY_STOCK_MAX)

	# 第四阶段：耐久（0..100，缺键=全新）/ 消音器（按枪，随枪丢）/ 首局引导
	durability = {}
	var raw_dur := _to_dict(d.get("durability", null))
	for dk in raw_dur.keys():
		if valid_guns.has(str(dk)) and guns_owned.has(str(dk)):
			durability[str(dk)] = clampf(float(raw_dur[dk]), 0.0, 100.0)
	sup_owned = []
	sup_off = []
	for key2 in ["sup_owned", "sup_off"]:
		var raw_sup: Variant = d.get(key2, null)
		if typeof(raw_sup) != TYPE_ARRAY:
			continue
		for id in raw_sup:
			var sg := str(id)
			if valid_guns.has(sg) and guns_owned.has(sg) and not (get(key2) as Array).has(sg):
				(get(key2) as Array).append(sg)
	tutorial_done = bool(d.get("tutorial_done", false)) or int(stats["raids"]) > 0


## 默认资产：恰旧五枪全有 / 现金 0 / 仓库空 / rifle+pistol
func _apply_defaults() -> void:
	cash = 0
	items = []
	guns_owned = DEFAULT_GUNS.duplicate()
	scopes_owned = []
	scope_fit = {}
	grips_owned = ["none"]
	grip_fit = {}
	ammo_inv = {}
	loadout = {"primary": "rifle", "secondary": "pistol"}
	stats = {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0, "time_total": 0, "contracts": 0}
	daily_last = ""
	contracts_day = ""
	contracts = []
	ammo_kind = {}
	ammo_kinds_owned = {}
	throwables = {"frag": 0, "smoke": 0, "flash": 0}
	keycards = {}
	secure_slots = HDData.SECURE_BASE
	durability = {}
	sup_owned = []
	sup_off = []
	tutorial_done = false


## 今日（自然日）尚未签到 = 可领
func can_check_in() -> bool:
	return daily_last != Time.get_date_string_from_system()


## 领取：可领则入账记日存盘返回金额；已领返回 0
func check_in() -> int:
	if not can_check_in():
		return 0
	daily_last = Time.get_date_string_from_system()
	cash += HDData.DAILY_REWARD
	save()
	changed.emit()
	return HDData.DAILY_REWARD


# ================= 投掷物 + 弹种（2026-10 阶段 D） =================

## 当前弹种（缺省标准弹）
func ammo_kind_of(gid: String) -> String:
	return str(ammo_kind.get(gid, "standard"))


## N 键循环弹种：下一档未购则现场购买（钱不够 false + 提示），已购则直接换装。
## 返回 [ok, 新弹种 id]；standard 恒可切回
func cycle_ammo_kind(gid: String) -> Array:
	var order: Array = []
	for ad in Guns.AMMO:
		order.append(str(ad["id"]))
	var cur_i := order.find(ammo_kind_of(gid))
	var nxt: String = order[(cur_i + 1) % order.size()]
	if nxt == "standard":
		ammo_kind[gid] = "standard"
		save()
		return [true, "standard"]
	var owned: Array = ammo_kinds_owned.get(gid, ["standard"])
	if owned.has(nxt):
		ammo_kind[gid] = nxt
		save()
		return [true, nxt]
	var price := _to_i(Guns.ammo_by_id(nxt).get("price", 0))
	if cash < price:
		return [false, nxt]
	cash -= price
	owned.append(nxt)
	ammo_kinds_owned[gid] = owned
	ammo_kind[gid] = nxt
	save()
	changed.emit()
	return [true, nxt]


## 买投掷物一件（③区按钮）：满/没钱返回 false（提示由大厅发）
func buy_throwable(kind: String) -> bool:
	var def: Dictionary = HDData.THROWABLES.get(kind, {})
	if def.is_empty():
		return false
	var n := _to_i(throwables.get(kind, 0))
	if n >= _to_i(def["max"]):
		return false
	if cash < _to_i(def["price"]):
		return false
	cash -= _to_i(def["price"])
	throwables[kind] = n + 1
	save()
	changed.emit()
	return true


func throwables_of(kind: String) -> int:
	return _to_i(throwables.get(kind, 0))


## 局内投掷消耗一件（没了 false）
func consume_throwable(kind: String) -> bool:
	var n := _to_i(throwables.get(kind, 0))
	if n <= 0:
		return false
	throwables[kind] = n - 1
	save()
	return true


## 买一把钥匙卡（2026-10-24 用户定案）：上限 KEY_STOCK_MAX / 钱 insufficient 拒
func buy_keycard(lock_id: String) -> bool:
	var key_name := ""
	for ld in HDData.LOCKS:
		if str(ld["id"]) == lock_id:
			key_name = str(ld["key"])
	if key_name == "":
		return false
	var n := _to_i(keycards.get(lock_id, 0))
	if n >= HDData.KEY_STOCK_MAX or cash < HDData.KEY_PRICE:
		return false
	cash -= HDData.KEY_PRICE
	keycards[lock_id] = n + 1
	save()
	changed.emit()
	return true


func keycards_of(lock_id: String) -> int:
	return _to_i(keycards.get(lock_id, 0))


# ================= 合同系统（2026-10 阶段 A） =================

## 合同定义查表（id → HDData.CONTRACT_POOL 条目；无则空字典）
func contract_def(id: String) -> Dictionary:
	for pd in HDData.CONTRACT_POOL:
		if str(pd["id"]) == id:
			return pd
	return {}


## 今日合同（3 张，按日期种子定死——同一天多次读取/重开游戏都是同一组）。
## 隔日重发：未完成进度作废（塔科夫合同惯例），已领奖金照留现金。
## 首次读取/隔日时滚动新合同并落盘；种子 = 日期字符串哈希的确定性 LCG。
func daily_contracts() -> Array:
	var today := Time.get_date_string_from_system()
	if contracts_day == today and not contracts.is_empty():
		return contracts
	var pool: Array = HDData.CONTRACT_POOL.duplicate()
	var seed := today.hash()
	contracts = []
	for k in HDData.CONTRACT_DAILY:
		seed = 1103515245 * seed + 12345   # 经典 LCG（确定性，重开游戏不变）
		var idx := absi(seed) % pool.size()
		var defc: Dictionary = pool[idx]
		contracts.append({"id": str(defc["id"]), "prog": 0, "done": false, "paid": false})
		pool.remove_at(idx)   # 不重复发同一张
	contracts_day = today
	save()
	changed.emit()
	return contracts


## 局内事件推进合同：kind = "kill" / "kill_boss" / "safe" / "zone"（zone 另传分区名），
## n = 本次增量。完成即锁 done（阵亡不清——撤离时统一结算），进度落盘。
## 返回本次刚完成的合同定义数组（main 可即时播报「合同完成」）
func contract_add(kind: String, zone: String, n: int) -> Array:
	daily_contracts()   # 惰性补发（老档首局）
	var finished: Array = []
	var dirty := false
	for ct in contracts:
		if bool(ct["done"]):
			continue
		var defc := contract_def(str(ct["id"]))
		if defc.is_empty() or str(defc["type"]) != kind:
			continue
		if kind == "zone" and str(defc.get("zone", "")) != zone:
			continue
		var goal: int = _to_i(defc["n"])
		ct["prog"] = mini(goal, _to_i(ct["prog"]) + n)
		dirty = true
		if _to_i(ct["prog"]) >= goal:
			ct["done"] = true
			finished.append(defc)
	if dirty:
		save()
	return finished


## 撤离结算：value 类按本局带出价值一次性判定，随后所有 done 未领的一并发奖金。
## 返回发放明细 [{title, reward}]（main 播报 + 结算行）；无发放返回空数组。
func settle_contracts(extract_value: int) -> Array:
	daily_contracts()
	var dirty := false
	for ct in contracts:
		if bool(ct["done"]):
			continue
		var defc := contract_def(str(ct["id"]))
		if str(defc["type"]) == "value" and extract_value >= _to_i(defc["n"]):
			ct["done"] = true
			ct["prog"] = _to_i(defc["n"])
			dirty = true
	var paid: Array = []
	for ct in contracts:
		if bool(ct["done"]) and not bool(ct["paid"]):
			var defc := contract_def(str(ct["id"]))
			var reward: int = _to_i(defc["reward"])
			cash += reward
			ct["paid"] = true
			paid.append({"title": str(defc["title"]), "reward": reward})
			dirty = true
	if not paid.is_empty():
		stats["contracts"] = maxi(0, _to_i(stats.get("contracts", 0))) + paid.size()
		dirty = true
	if dirty:
		save()
		changed.emit()
	return paid


func owns_scope(id: String) -> bool:
	if id == "" or id == "iron":
		return true                  # 机瞄默认拥有
	return scopes_owned.has(id)


## 购买瞄具：已拥有直接 true；现金不足 false（不扣款）；买即拥有
func buy_scope(id: String) -> bool:
	if id == "" or id == "iron":
		return true
	if owns_scope(id):
		return true
	var sc := Guns.scope_by_id(id)
	if sc.is_empty():
		return false
	var price := maxi(0, _to_i(sc.get("price", 0)))
	if cash < price:
		return false
	cash -= price
	scopes_owned.append(id)
	save()
	changed.emit()
	return true


## 是否拥有该枪（枪械店 id；新枪默认不在拥有集里）
func owns_gun(id: String) -> bool:
	return guns_owned.has(id)


## 购买枪械：已拥有直接 true（幂等不重复扣款）；只在枪械店目录
## （Guns.shop_gun_by_id，不含大战场配发枪）里卖，未知 id 拒绝；
## 现金不足 false 不扣款；成交即扣款入拥有集并存盘（照 buy_scope 同款容错）
func buy_gun(id: String) -> bool:
	if guns_owned.has(id):
		return true
	var g := Guns.shop_gun_by_id(id)
	if g.is_empty():
		return false
	var price := maxi(0, _to_i(g.get("price", 0)))
	if cash < price:
		return false
	cash -= price
	guns_owned.append(id)
	save()
	changed.emit()
	return true


## ---- 极致备弹经济：库存读取（含首次礼物）/ 购买 / 局终回收 ----

## 读某枪备弹余量：缺键 = 该枪第一次进弹药经济 → 一次性赠送满额备弹
## （HDData.RESERVE 该枪值；老档缺字段同此初始化），只送一次、之后只买不送。
## 礼物立即落盘但不发 changed——渲染路径（大厅速览）会调到这里，
## 发信号会触发 _refresh_all 回流重入
func ammo_of(gun_id: String) -> int:
	if not ammo_inv.has(gun_id):
		ammo_inv[gun_id] = maxi(0, _to_i(HDData.RESERVE.get(gun_id, 0)))
		save()
	return maxi(0, _to_i(ammo_inv.get(gun_id, 0)))


## 购买极致备弹：n<=0 或不在单价表（如大战场配发枪）拒绝 false；
## 现金不足 false 不扣款；足额扣 n×单价、加弹（首买顺带入账礼物）、存盘、changed
func buy_ammo(gun_id: String, n: int) -> bool:
	if n <= 0 or not (HDData.AMMO_PRICE as Dictionary).has(gun_id):
		return false
	var total := maxi(0, _to_i(HDData.AMMO_PRICE.get(gun_id, 0))) * n
	if cash < total:
		return false
	cash -= total
	ammo_inv[gun_id] = ammo_of(gun_id) + n
	save()
	changed.emit()
	return true


## 撤离回收：把局内剩余备弹写回库存（阵亡/放弃走 lose_carried 清零，不回收）
func set_ammo(gun_id: String, n: int) -> void:
	ammo_inv[gun_id] = maxi(0, n)
	save()
	changed.emit()


## 装配（单持强制）：同瞄具自动从他枪卸下；"iron"/"" = 卸下回机瞄
func equip_scope(gun_id: String, scope_id: String) -> void:
	var sid := "iron" if scope_id == "" or scope_id == "iron" else scope_id
	if sid != "iron":
		for gid in scope_fit.keys():
			if str(gid) != gun_id and str(scope_fit[gid]) == sid:
				scope_fit[gid] = "iron"
	scope_fit[gun_id] = sid
	save()
	changed.emit()


## 开镜倍率：狙击自带 6×（GUNS builtin_scope）> 装镜 zoom > 1.0
func scope_zoom(gun_id: String) -> float:
	var g := Guns.gun_by_id(gun_id)
	if g.has("builtin_scope"):
		var bs: Dictionary = g["builtin_scope"]
		return maxf(1.0, float(bs.get("zoom", 1.0)))
	var sid := str(scope_fit.get(gun_id, "iron"))
	if sid != "iron":
		var sc := Guns.scope_by_id(sid)
		if not sc.is_empty():
			return maxf(1.0, float(sc.get("zoom", 1.0)))
	return 1.0


## 购买握把/护木（2026-10 M14 首接入：借 GRIPS 表——"none" 恒免费恒拥有）
func buy_grip(id: String) -> bool:
	if id == "" or id == "none" or owns_grip(id):
		return true
	var gr := Guns.grip_by_id(id)
	if gr.is_empty():
		return false
	var price := maxi(0, _to_i(gr.get("price", 0)))
	if cash < price:
		return false
	cash -= price
	grips_owned.append(id)
	save()
	changed.emit()
	return true


func owns_grip(id: String) -> bool:
	return id == "none" or grips_owned.has(id)


## 装配握把（与瞄具不同：握把多枪可复用，同一时间一把枪一个）——M14 装上
## 即生效：hd_guns 后坐 ×recoil_mul、ADS_SPEED ×ads_mul、护木视觉件
func equip_grip(gun_id: String, grip_id: String) -> void:
	var gid := "none" if grip_id == "" or not owns_grip(grip_id) else grip_id
	grip_fit[gun_id] = gid
	save()
	changed.emit()


## 当前枪握把的 (recoil_mul, ads_mul)；未装 = (1.0, 1.0)
func grip_muls(gun_id: String) -> Vector2:
	var gid := str(grip_fit.get(gun_id, "none"))
	if gid == "none":
		return Vector2.ONE
	var gr := Guns.grip_by_id(gid)
	if gr.is_empty():
		return Vector2.ONE
	return Vector2(maxf(0.0, float(gr.get("recoil_mul", 1.0))),
			maxf(0.5, float(gr.get("ads_mul", 1.0))))


## M14 专属配件（foregrip/extmag）：交易行⑤区购买，bool 解锁持久化——
## 借 m14_mods 列表存（可扩多枪专属件）；hd_guns 开火/出厂读 m14_mods_on
var m14_mods: Array = []              # 已购 M14 配件 id：["foregrip"]/["extmag"]

func buy_m14_mod(id: String) -> bool:
	if m14_mods.has(id):
		return true
	# 校验放宽到三张专属配件表（2026-10-25 MK4 / 2026-10-26 SR25 并入同链）：
	# 存储共用 m14_mods 数组（id 全局唯一）
	var md: Dictionary = Guns.M14_MODS.get(id, {})
	if md.is_empty():
		md = Guns.MK4_MODS.get(id, {})
	if md.is_empty():
		md = Guns.SR25_MODS.get(id, {})
	if md.is_empty():
		return false
	var price := maxi(0, _to_i(md.get("price", 0)))
	if cash < price:
		return false
	cash -= price
	m14_mods.append(id)
	save()
	changed.emit()
	return true


func m14_mods_on(id: String) -> bool:
	return m14_mods.has(id)


## ---- 带入即风险（2026-10）----

## 一套出发装备的价值：主副武器价 + 其所装瞄具价 + 所带备弹（库存 × 单价）。
## 侦察手枪不计（永久）；大厅风险提示与阵亡结算共用
func carried_value(lo: Dictionary) -> int:
	var sum := 0
	for slot in ["primary", "secondary"]:
		var gid := str(lo.get(slot, ""))
		if gid == "":
			continue
		if gid != HDData.PERMANENT_GUN:
			sum += maxi(0, _to_i(Guns.gun_by_id(gid).get("price", 0)))
			var sid := str(scope_fit.get(gid, "iron"))
			if sid != "iron" and owns_scope(sid):
				sum += maxi(0, _to_i(Guns.scope_by_id(sid).get("price", 0)))
		if sup_owned.has(gid):
			sum += HDData.SUP_PRICE   # 拆下的消音器也随枪带着（随枪丢）
		sum += maxi(0, _to_i(ammo_inv.get(gid, 0))) \
				* maxi(0, _to_i(HDData.AMMO_PRICE.get(gid, 0)))
	return sum


## 保险费 = 所带装备价值 × 30%（向上取整）
func insurance_price(lo: Dictionary) -> int:
	return int(ceil(float(carried_value(lo)) * HDData.INSURE_RATE))


## 阵亡/放弃：带进局的装备全部丢失——主副武器（侦察手枪除外）出拥有集、
## 其所装瞄具/消音器随枪丢、两枪所带备弹清零（置 0 不删键：缺键会被当首读再送礼）。
## insured（出发时投了保）：每件（枪/镜/消音器/备弹）各按 INSURE_RETURN 概率退回不丢。
## 返回 {"guns","scopes","sups","ammo","value", "back": [退回件名], "back_value"}；
## 丢失后修出发配置（repair_loadout），存盘发 changed
func lose_carried(lo: Dictionary, insured: bool = false) -> Dictionary:
	var out := {"guns": [], "scopes": [], "sups": 0, "ammo": 0, "value": carried_value(lo),
		"back": [], "back_value": 0}
	var keep := func() -> bool: return insured and randf() < HDData.INSURE_RETURN
	for slot in ["primary", "secondary"]:
		var gid := str(lo.get(slot, ""))
		if gid == "":
			continue
		var n_ammo := maxi(0, _to_i(ammo_inv.get(gid, 0)))
		if n_ammo > 0 and keep.call():
			(out["back"] as Array).append("备弹 %d 发" % n_ammo)
			out["back_value"] = int(out["back_value"]) + n_ammo * maxi(0, _to_i(HDData.AMMO_PRICE.get(gid, 0)))
		else:
			out["ammo"] = int(out["ammo"]) + n_ammo
			ammo_inv[gid] = 0
		if gid == HDData.PERMANENT_GUN:
			continue
		var gname := str(Guns.gun_by_id(gid).get("name", gid))
		var sid := str(scope_fit.get(gid, "iron"))
		if sid != "iron" and scopes_owned.has(sid):
			var sname := str(Guns.scope_by_id(sid).get("name", sid))
			if keep.call():
				(out["back"] as Array).append(sname)
				out["back_value"] = int(out["back_value"]) + _to_i(Guns.scope_by_id(sid).get("price", 0))
			else:
				scopes_owned.erase(sid)
				scope_fit.erase(gid)
				(out["scopes"] as Array).append(sname)
		if sup_owned.has(gid):
			if keep.call():
				(out["back"] as Array).append("%s 消音器" % gname)
				out["back_value"] = int(out["back_value"]) + HDData.SUP_PRICE
			else:
				sup_owned.erase(gid)
				sup_off.erase(gid)
				out["sups"] = int(out["sups"]) + 1
		if guns_owned.has(gid):
			if keep.call():
				(out["back"] as Array).append(gname)
				out["back_value"] = int(out["back_value"]) + _to_i(Guns.gun_by_id(gid).get("price", 0))
			else:
				guns_owned.erase(gid)
				durability.erase(gid)
				(out["guns"] as Array).append(gname)
				# 枪没了，没退回的配件也跟着没了（退回的镜/消音器留在仓库，可装别的枪）
				if scope_fit.has(gid):
					scope_fit.erase(gid)
				if sup_owned.has(gid):
					sup_owned.erase(gid)   # 消音器按枪买：枪丢了就算退回也无处可装，按价折现
					sup_off.erase(gid)
					cash += HDData.SUP_PRICE
	out["value"] = maxi(0, int(out["value"]) - int(out["back_value"]))
	repair_loadout()
	save()
	changed.emit()
	return out


## ---- 耐久 / 维修 ----

func dur_of(gid: String) -> float:
	return clampf(float(durability.get(gid, 100.0)), 0.0, 100.0)


## 局终结算磨损（开火发数 × DUR_PER_SHOT）；未拥有的枪忽略
func wear(gid: String, amount: float) -> void:
	if amount <= 0.0 or not guns_owned.has(gid):
		return
	durability[gid] = maxf(0.0, dur_of(gid) - amount)


## 满修价：缺多少修多少（枪价 × 25% × 缺损比例；最低按 REPAIR_BASE_MIN 计价）
func repair_price(gid: String) -> int:
	var base := maxi(HDData.REPAIR_BASE_MIN, _to_i(Guns.gun_by_id(gid).get("price", 0)))
	return int(ceil(float(base) * HDData.REPAIR_RATE * (100.0 - dur_of(gid)) / 100.0))


func repair(gid: String) -> bool:
	var price := repair_price(gid)
	if price <= 0 or not guns_owned.has(gid) or cash < price:
		return false
	cash -= price
	durability[gid] = 100.0
	save()
	changed.emit()
	return true


## ---- 消音器（按枪买，可拆装）----

func sup_allowed(gid: String) -> bool:
	return gid != "" and not (gid in HDData.SUP_BLOCK)


## 该枪当前装着消音器（买了且没拆）
func suppressed(gid: String) -> bool:
	return sup_owned.has(gid) and not sup_off.has(gid)


func buy_sup(gid: String) -> bool:
	if sup_owned.has(gid) or not sup_allowed(gid) or not guns_owned.has(gid) \
			or cash < HDData.SUP_PRICE:
		return false
	cash -= HDData.SUP_PRICE
	sup_owned.append(gid)
	sup_off.erase(gid)
	save()
	changed.emit()
	return true


## 拆/装（已买的才行）；返回装上后的状态
func toggle_sup(gid: String) -> bool:
	if not sup_owned.has(gid):
		return false
	if sup_off.has(gid):
		sup_off.erase(gid)
	else:
		sup_off.append(gid)
	save()
	changed.emit()
	return suppressed(gid)


## 出发配置修复：未拥有的枪从槽里清掉——主武器空则顶上副武器（再空则侦察
## 手枪），副武器允许空槽。不自动从仓库挑别的枪装上（那会让玩家没选过的枪
## 也带进局承担风险）
func repair_loadout() -> void:
	var p := str(loadout.get("primary", ""))
	var s := str(loadout.get("secondary", ""))
	if not guns_owned.has(p):
		p = ""
	if not guns_owned.has(s):
		s = ""
	if p == "":
		p = s if s != "" else HDData.PERMANENT_GUN
		s = "" if p == s else s
	if s == p:
		s = ""
	loadout = {"primary": p, "secondary": s}


## 安全箱扩容价（已满 4 格返回 0）
func secure_up_price() -> int:
	var k := secure_slots - HDData.SECURE_BASE
	if k < 0 or k >= (HDData.SECURE_UP_PRICE as Array).size():
		return 0
	return int(HDData.SECURE_UP_PRICE[k])


## 安全箱扩容一格：已满/现金不足 false 不扣款
func buy_secure_upgrade() -> bool:
	var price := secure_up_price()
	if price <= 0 or cash < price:
		return false
	cash -= price
	secure_slots += 1
	save()
	changed.emit()
	return true


## 变卖全部 items 加现金，返回总额
func sell_all() -> int:
	if items.is_empty():
		return 0
	var sum := 0
	for it in items:
		if typeof(it) == TYPE_DICTIONARY:
			sum += maxi(0, _to_i(it.get("value", 0)))
	items.clear()
	cash += sum
	save()
	changed.emit()
	return sum


## 撤离入库：整包带回（uid 去重），返回实际入库件数
func deposit(bag: Array) -> int:
	var n := 0
	for it in bag:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var norm := _norm_item(it)
		if str(norm["uid"]) == "" or _find_uid(str(norm["uid"])) >= 0:
			continue
		items.append(norm)
		n += 1
	if n > 0:
		save()
		changed.emit()
	return n


## 对局结算记战绩（撤离/阵亡/击杀/局时）——撤离率与平均局时是改进方案门槛 C
func record_raid(win: bool, kills: int, secs: float = 0.0) -> void:
	stats["time_total"] = maxi(0, _to_i(stats.get("time_total", 0))) + maxi(0, int(secs))
	stats["raids"] = maxi(0, _to_i(stats.get("raids", 0))) + 1
	if win:
		stats["extracts"] = maxi(0, _to_i(stats.get("extracts", 0))) + 1
	else:
		stats["deaths"] = maxi(0, _to_i(stats.get("deaths", 0))) + 1
	stats["kills"] = maxi(0, _to_i(stats.get("kills", 0))) + maxi(0, kills)
	save()
	changed.emit()


## 重置：回默认档并存盘
func wipe() -> void:
	_apply_defaults()
	save()
	changed.emit()


## 归一化一件变卖物：{uid,name,icon,rarity,value}
## icon 走 HDData.norm_icon：空 → 默认徽标；旧档 emoji → 中文徽标（默认字体无 emoji 字形）
func _norm_item(it: Dictionary) -> Dictionary:
	var uid := _to_s(it.get("uid", ""))
	var nm := _to_s(it.get("name", ""))
	var icon := _to_s(it.get("icon", ""))
	return {
		"uid": uid,
		"name": nm if nm != "" else "战利品",
		"icon": HDData.norm_icon(icon),
		"rarity": clampi(_to_i(it.get("rarity", 0)), 0, 6),
		"value": maxi(0, _to_i(it.get("value", 0))),
	}


## 按 uid 找 items 下标（无则 -1）
func _find_uid(uid: String) -> int:
	for i in items.size():
		var it: Variant = items[i]
		if typeof(it) == TYPE_DICTIONARY and str(it.get("uid", "")) == uid:
			return i
	return -1


## ---- 存档字段防御转换（损坏值安全落回默认） ----

static func _to_i(v: Variant) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return int(round(float(v)))
		TYPE_BOOL:
			return 1 if v else 0
		TYPE_STRING:
			return int(round(float(str(v))))
	return 0


static func _to_s(v: Variant) -> String:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME, TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return str(v)
	return ""


static func _to_dict(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}
