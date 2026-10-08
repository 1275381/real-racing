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

const SAVE_VERSION := 1

## 默认拥有集：恰旧五枪（新枪默认不拥有、只走现金购买）。
## GUNS 扩充后绝不能再「遍历 GUNS 全送」——那是经济白送事故点
const DEFAULT_GUNS := ["pistol", "smg", "rifle", "shotgun", "sniper"]

var cash: int = 0
var items: Array = []                 # [{uid,name,icon,rarity,value}]
var guns_owned: Array = []            # 枪械 id 列表（默认五枪全有）
var scopes_owned: Array = []          # 已购瞄具 id 列表
var scope_fit: Dictionary = {}        # gun_id -> scope_id 或 "iron"
var loadout: Dictionary = {"primary": "rifle", "secondary": "pistol"}
var stats: Dictionary = {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0}
var daily_last: String = ""          # 最近一次签到的日期键（YYYY-MM-DD）


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
		"loadout": loadout,
		"stats": stats,
		"daily_last": daily_last,
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
	if _to_i(d.get("v", 0)) != SAVE_VERSION:
		wipe()                       # 版本不符 → 重置
		return
	cash = maxi(0, _to_i(d.get("cash", 0)))

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

	# 出发配置（主副不可同枪）
	var lo := _to_dict(d.get("loadout", null))
	var p := str(lo.get("primary", "rifle"))
	var s := str(lo.get("secondary", "pistol"))
	if not valid_guns.has(p):
		p = "rifle"
	if not valid_guns.has(s):
		s = "pistol"
	if p == s:
		s = "pistol" if p != "pistol" else "rifle"
	loadout = {"primary": p, "secondary": s}

	# 战绩
	var st := _to_dict(d.get("stats", null))
	stats = {
		"raids": maxi(0, _to_i(st.get("raids", 0))),
		"extracts": maxi(0, _to_i(st.get("extracts", 0))),
		"deaths": maxi(0, _to_i(st.get("deaths", 0))),
		"kills": maxi(0, _to_i(st.get("kills", 0))),
	}
	daily_last = _to_s(d.get("daily_last", ""))


## 默认资产：恰旧五枪全有 / 现金 0 / 仓库空 / rifle+pistol
func _apply_defaults() -> void:
	cash = 0
	items = []
	guns_owned = DEFAULT_GUNS.duplicate()
	scopes_owned = []
	scope_fit = {}
	loadout = {"primary": "rifle", "secondary": "pistol"}
	stats = {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0}
	daily_last = ""


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


## 对局结算记战绩（撤离/阵亡/击杀）
func record_raid(win: bool, kills: int) -> void:
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
