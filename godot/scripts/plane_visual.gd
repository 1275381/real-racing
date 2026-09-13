class_name PlaneVisual
extends Node3D
## 程序化战机模型：机身/主翼/垂尾/座舱/螺旋桨（"prop" 子节点可自转）。
## 车库展示、自由漫游飞行、大战场三处共用。
## scheme: "ally" 蓝灰 / "enemy" 暗红 / "gold" 车库金色涂装

const SCHEMES := {
	"ally": {"body": Color(0.47, 0.56, 0.68), "wing": Color(0.4, 0.48, 0.58)},
	"enemy": {"body": Color(0.5, 0.27, 0.21), "wing": Color(0.42, 0.23, 0.18)},
	"gold": {"body": Color(0.85, 0.68, 0.28), "wing": Color(0.72, 0.57, 0.22)},
}

var prop: Node3D


static func create(scheme := "ally") -> PlaneVisual:
	var pv := PlaneVisual.new()
	var c: Dictionary = SCHEMES.get(scheme, SCHEMES["ally"])
	var body: Color = c["body"]
	var wing: Color = c["wing"]
	var dark := Color(0.16, 0.17, 0.19)
	var glass := Color(0.3, 0.5, 0.6, 0.9)
	var add_box := func(size: Vector3, p: Vector3, cc: Color) -> MeshInstance3D:
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cc
		mat.roughness = 0.55
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = p
		pv.add_child(mi)
		return mi
	# 机头朝 +Z（前向 = (sin h, 0, cos h) 约定）
	add_box.call(Vector3(1.1, 1.0, 5.6), Vector3(0, 0, 0), body)        # 机身
	add_box.call(Vector3(0.8, 0.62, 1.1), Vector3(0, 0.1, 2.6), body)   # 机鼻
	add_box.call(Vector3(7.2, 0.14, 1.6), Vector3(0, 0.22, 0.4), wing)  # 主翼
	add_box.call(Vector3(1.0, 0.1, 2.2), Vector3(2.6, 0.3, 0.4), wing)  # 翼尖
	add_box.call(Vector3(1.0, 0.1, 2.2), Vector3(-2.6, 0.3, 0.4), wing)
	add_box.call(Vector3(2.6, 0.12, 0.9), Vector3(0, 0.28, -2.4), wing) # 平尾
	add_box.call(Vector3(0.12, 1.15, 0.95), Vector3(0, 0.72, -2.4), body) # 垂尾
	add_box.call(Vector3(0.74, 0.5, 1.3), Vector3(0, 0.62, 0.7), glass) # 座舱盖
	# 起落架（前三点）
	for gear in [[Vector3(0, -0.62, 1.7)], [Vector3(-0.9, -0.62, -0.6)],
			[Vector3(0.9, -0.62, -0.6)]]:
		add_box.call(Vector3(0.12, 0.55, 0.12), gear[0], dark)
		add_box.call(Vector3(0.26, 0.26, 0.26),
				gear[0] + Vector3(0, -0.32, 0), Color(0.1, 0.1, 0.11))
	# 螺旋桨（双叶正交，"prop" 供外部按油门自转）
	pv.prop = Node3D.new()
	pv.prop.name = "prop"
	pv.prop.position = Vector3(0, 0, 3.25)
	pv.add_child(pv.prop)
	for b in 2:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 2.4, 0.05)
		var bm_mat := StandardMaterial3D.new()
		bm_mat.albedo_color = dark
		bm.material = bm_mat
		blade.mesh = bm
		blade.rotation.z = PI * 0.5 * b   # 两叶正交
		pv.prop.add_child(blade)
	return pv


## 按油门自转螺旋桨（dt 秒）
func spin_prop(dt: float, throttle: float) -> void:
	if prop != null:
		prop.rotation.z += dt * (3.0 + 55.0 * clampf(throttle, 0.0, 1.0))
