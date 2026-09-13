class_name PlaneVisual
extends Node3D
## 第六代隐形喷气战机模型（棱面隐身外形）：菱形机鼻 / 融合体机身 / 外倾双垂尾 /
## 双发喷管 + 尾焰（set_throttle 控制长度与亮度）/ 起落架收放（set_gear）。
## 车库展示、自由漫游飞行、大战场三处共用。
## scheme: "ally" 制空灰 / "enemy" 暗铁红 / "gold" 曜石金（车库）

const SCHEMES := {
	"ally": {"body": Color(0.34, 0.37, 0.42), "panel": Color(0.27, 0.3, 0.35),
		"trim": Color(0.55, 0.6, 0.66)},
	"enemy": {"body": Color(0.3, 0.24, 0.24), "panel": Color(0.22, 0.17, 0.17),
		"trim": Color(0.6, 0.2, 0.16)},
	"gold": {"body": Color(0.14, 0.15, 0.18), "panel": Color(0.1, 0.11, 0.13),
		"trim": Color(0.85, 0.68, 0.28)},
}

var flame: Node3D              # 尾焰组（双发）
var gear: Node3D               # 起落架组
var _throttle := 0.0
var _flame_t := 0.0


static func create(scheme := "ally") -> PlaneVisual:
	var pv := PlaneVisual.new()
	var c: Dictionary = SCHEMES.get(scheme, SCHEMES["ally"])
	var body: Color = c["body"]
	var panel: Color = c["panel"]
	var trim: Color = c["trim"]
	var dark := Color(0.1, 0.1, 0.12)
	var glass := Color(0.85, 0.66, 0.22, 0.88)   # 隐形舱盖金镀膜
	var hot := Color(1.0, 0.55, 0.15)
	var add_box := func(size: Vector3, p: Vector3, cc: Color,
			rot := Vector3.ZERO) -> MeshInstance3D:
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cc
		mat.roughness = 0.45
		mat.metallic = 0.25
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = p
		mi.rotation = rot
		pv.add_child(mi)
		return mi
	# ---- 机身（前向 +Z）：棱面融合体 ----
	add_box.call(Vector3(0.7, 0.42, 2.0), Vector3(0, -0.02, 3.0), body,
			Vector3(0, 0, PI * 0.25))                            # 菱形机鼻
	add_box.call(Vector3(1.7, 0.55, 3.6), Vector3(0, 0, 0.5), body)  # 中体
	add_box.call(Vector3(1.35, 0.5, 2.4), Vector3(0, 0.03, -2.1), panel) # 尾体
	add_box.call(Vector3(0.62, 0.3, 3.6), Vector3(0, 0.36, -0.3), panel) # 背脊
	add_box.call(Vector3(0.12, 0.18, 3.2), Vector3(-0.86, 0.02, 0.7),
			trim, Vector3(0, 0, 0.38))                       # 左棱线
	add_box.call(Vector3(0.12, 0.18, 3.2), Vector3(0.86, 0.02, 0.7),
			trim, Vector3(0, 0, -0.38))                      # 右棱线
	# ---- 座舱（金色镀膜气泡舱盖）----
	add_box.call(Vector3(0.6, 0.42, 1.5), Vector3(0, 0.5, 1.3), glass)
	add_box.call(Vector3(0.5, 0.14, 0.5), Vector3(0, 0.42, 1.95), dark)
	# ---- 两侧 DSI 进气道 ----
	add_box.call(Vector3(0.5, 0.44, 1.5), Vector3(-0.98, -0.04, 0.5), panel,
			Vector3(0, 0, 0.15))
	add_box.call(Vector3(0.5, 0.44, 1.5), Vector3(0.98, -0.04, 0.5), panel,
			Vector3(0, 0, -0.15))
	# ---- 主翼（后掠切尖三角，融合翼身）----
	add_box.call(Vector3(3.3, 0.09, 1.8), Vector3(-2.05, 0.1, -0.75), body,
			Vector3(0, -0.5, 0))
	add_box.call(Vector3(3.3, 0.09, 1.8), Vector3(2.05, 0.1, -0.75), body,
			Vector3(0, 0.5, 0))
	add_box.call(Vector3(1.2, 0.07, 1.2), Vector3(-0.85, 0.12, -0.2), panel)
	add_box.call(Vector3(1.2, 0.07, 1.2), Vector3(0.85, 0.12, -0.2), panel)
	# ---- 尾部：外倾双垂尾 + 全动平尾 ----
	add_box.call(Vector3(0.09, 1.35, 1.05), Vector3(-0.88, 0.8, -2.75), panel,
			Vector3(0, 0, 0.42))
	add_box.call(Vector3(0.09, 1.35, 1.05), Vector3(0.88, 0.8, -2.75), panel,
			Vector3(0, 0, -0.42))
	add_box.call(Vector3(1.5, 0.08, 1.0), Vector3(-1.05, 0.12, -2.75), body,
			Vector3(0, -0.38, 0))
	add_box.call(Vector3(1.5, 0.08, 1.0), Vector3(1.05, 0.12, -2.75), body,
			Vector3(0, 0.38, 0))
	# ---- 双发喷管 + 尾焰 ----
	add_box.call(Vector3(0.5, 0.42, 0.8), Vector3(-0.44, 0.0, -3.0), dark)
	add_box.call(Vector3(0.5, 0.42, 0.8), Vector3(0.44, 0.0, -3.0), dark)
	pv.flame = Node3D.new()
	pv.flame.name = "flame"
	pv.add_child(pv.flame)
	for side in [-0.44, 0.44]:
		var fm := CylinderMesh.new()
		fm.top_radius = 0.06
		fm.bottom_radius = 0.26
		fm.height = 1.7
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = hot
		fmat.emission_enabled = true
		fmat.emission = hot
		fmat.emission_energy_multiplier = 3.0
		fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fmat.albedo_color.a = 0.85
		fm.material = fmat
		var fmi := MeshInstance3D.new()
		fmi.mesh = fm
		fmi.position = Vector3(side, 0, -3.55)
		fmi.rotation.x = -PI * 0.5   # 焰锥指向 -Z（机尾）
		pv.flame.add_child(fmi)
	# ---- 起落架（前三点，可收放）----
	pv.gear = Node3D.new()
	pv.gear.name = "gear"
	pv.add_child(pv.gear)
	for g in [[Vector3(0, -0.5, 1.8)], [Vector3(-0.85, -0.5, -0.7)],
			[Vector3(0.85, -0.5, -0.7)]]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.6, 0.12)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = dark
		lm.material = lmat
		leg.mesh = lm
		leg.position = g[0]
		pv.gear.add_child(leg)
		var wheel := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.24, 0.24, 0.24)
		wheel.mesh = wm
		wheel.position = g[0] + Vector3(0, -0.36, 0)
		pv.gear.add_child(wheel)
	return pv


## 油门 → 尾焰长度/亮度（每帧内部动画 + 抖动）
func set_throttle(t: float) -> void:
	_throttle = clampf(t, 0.0, 1.0)


## 起落架收放（true = 放下）
func set_gear(down: bool) -> void:
	if gear != null:
		gear.visible = down


func _process(dt: float) -> void:
	_flame_t += dt
	if flame == null:
		return
	var on := _throttle > 0.04
	flame.visible = on
	if not on:
		return
	var flick := 1.0 + 0.18 * sin(_flame_t * 47.0) + 0.1 * sin(_flame_t * 89.0)
	var s := (0.22 + 1.05 * _throttle) * flick
	flame.scale = Vector3(0.6 + 0.5 * _throttle, 0.6 + 0.5 * _throttle, s)
	for fmi in flame.get_children():
		var mat := (fmi as MeshInstance3D).mesh.surface_get_material(0) \
				as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 1.5 + 5.0 * _throttle
