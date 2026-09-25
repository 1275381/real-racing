extends Node3D
## 曳光弹对象池：一段短亮线（拖尾 LEN 米）从枪口以 SPEED 飞向落点，飞到后回调
## on_arrive(落点) 出命中火花。原来是枪口到落点的一整条静止光柱（像激光），
## 且步行时起点算成了眼前 0.6m、正对视线，屏幕上缩成准星旁一团楔形光斑。
## 由 owner 在自己的 fx 节拍里调 tick(dt)（跟随游戏暂停/定步）。
## （按路径 preload，不注册 class_name：见 loading_screen.gd 顶注）

const SPEED := 420.0     # 米/秒：肉眼能看出从枪口飞出去，又不至于拖沓
const LEN := 6.0         # 拖尾长度（米）

var mat: StandardMaterial3D
var on_arrive: Callable  # func(pos: Vector3)
var _pool: Array = []    # {mi, from, dir, dist, s, impact}
var _i := 0


func setup(count: int, color: Color, energy: float, thick := 0.022) -> void:
	mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thick, thick, 1.0)
	mesh.material = mat
	for n in count:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pool.append({"mi": mi, "from": Vector3.ZERO, "dir": Vector3.FORWARD,
				"dist": 0.0, "s": -1.0, "impact": false})


## impact：飞到落点时回调 on_arrive（命中墙/人/车才要火花，打空不要）
func spawn(from: Vector3, to: Vector3, impact: bool) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 0.05:
		if impact and on_arrive.is_valid():
			on_arrive.call(to)
		return
	var slot: Dictionary = _pool[_i]
	_i = (_i + 1) % _pool.size()
	if float(slot["s"]) >= 0.0 and slot["impact"] and on_arrive.is_valid():
		# 被挤掉的那条还没飞到：直接补上它的火花
		on_arrive.call(Vector3(slot["from"]) + Vector3(slot["dir"]) * float(slot["dist"]))
	slot["from"] = from
	slot["dir"] = d / dist
	slot["dist"] = dist
	slot["s"] = 0.0
	slot["impact"] = impact
	_place(slot)


func tick(dt: float) -> void:
	for slot in _pool:
		if float(slot["s"]) < 0.0:
			continue
		slot["s"] = float(slot["s"]) + SPEED * dt
		var dist: float = slot["dist"]
		if float(slot["s"]) - LEN >= dist:
			slot["s"] = -1.0
			(slot["mi"] as MeshInstance3D).visible = false
			continue
		if slot["impact"] and float(slot["s"]) >= dist:
			slot["impact"] = false
			if on_arrive.is_valid():
				on_arrive.call(Vector3(slot["from"]) + Vector3(slot["dir"]) * dist)
		_place(slot)


func hide_all() -> void:
	for slot in _pool:
		slot["s"] = -1.0
		(slot["mi"] as MeshInstance3D).visible = false


func _place(slot: Dictionary) -> void:
	var mi: MeshInstance3D = slot["mi"]
	var dist: float = slot["dist"]
	var head := minf(float(slot["s"]), dist)
	var tail := maxf(0.0, float(slot["s"]) - LEN)
	if head - tail < 0.05:
		# 刚出膛的第一帧：先露一小截，免得空一帧
		head = minf(tail + minf(LEN, dist), dist)
	var from: Vector3 = slot["from"]
	var dir: Vector3 = slot["dir"]
	var a := from + dir * tail
	var b := from + dir * head
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	mi.look_at_from_position((a + b) * 0.5, b, up)
	mi.scale = Vector3(1, 1, b.distance_to(a))
	mi.visible = true
