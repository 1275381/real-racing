extends Node
## 烽火地带 —— 投掷物系统（2026-10「更好玩」阶段 D）
## 破片雷（AoE 130 伤害 7m 衰减 + 惊动 90m）/ 烟雾弹（12s 烟球遮 AI 视线）/
## 闪光弹（9m 内有视线士兵致盲 2.5s · 玩家正对白屏渐退）。
## 抛物线弹道（重力 + 出手速度），落地起爆。无 class_name（preload 先例）。
## 士兵视线遮蔽：smoke_spheres 静态表 + blocks_sight(a,b)——HDSoldiers._blocked 调。

static var smoke_spheres: Array = []   # [{pos, r, t}]（本局活烟球；reset 清）

var _world
var _player
var _soldiers
var _hud
var _projs: Array = []                 # {kind, node, vel, t, landed, fuse_t}
var _fx: Array = []                    # 爆炸/烟云视觉 {node, t, dur, kind}
var _flash_t := 0.0                    # 玩家白屏剩余

func setup(world, player, soldiers, hud) -> void:
	_world = world
	_player = player
	_soldiers = soldiers
	_hud = hud

func reset_all() -> void:
	for p0 in _projs:
		(p0["node"] as Node3D).queue_free()
	_projs.clear()
	smoke_spheres.clear()
	for f0 in _fx:
		(f0["node"] as Node3D).queue_free()
	_fx.clear()
	_flash_t = 0.0


static func blocks_sight(a: Vector3, b: Vector3) -> bool:
	for sm in smoke_spheres:
		var c: Vector3 = sm["pos"]
		var r: float = float(sm["r"]) * 0.85
		var ab := b - a
		var ab2 := ab.length_squared()
		if ab2 < 0.01:
			continue
		var t := clampf((c - a).dot(ab) / ab2, 0.0, 1.0)
		var closest := a + ab * t
		if closest.distance_to(c) < r:
			return true
	return false


## 出手：从眼位沿视线抛出（速度 13 + 上抛 3.5）
func throw_one(kind: String, from: Vector3, dir: Vector3) -> void:
	var node := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh: Mesh
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.5
	match kind:
		"frag":
			var fg := SphereMesh.new()
			fg.radius = 0.07
			fg.height = 0.14
			mesh = fg
			mat.albedo_color = Color(0.25, 0.3, 0.22)
		"smoke":
			mesh = CylinderMesh.new()
			mat.albedo_color = Color(0.4, 0.42, 0.4)
		_:
			mesh = BoxMesh.new()
			mat.albedo_color = Color(0.5, 0.5, 0.55)
	body.mesh = mesh
	body.set_surface_override_material(0, mat)
	node.add_child(body)
	node.position = from
	add_child(node)
	_projs.append({"kind": kind, "node": node, "vel": dir.normalized() * 13.0
			+ Vector3(0.0, 3.5, 0.0), "t": 0.0, "landed": false, "fuse_t": 0.0})


func update(dt: float) -> void:
	# 投掷物弹道（重力 + 地面反弹一次后停）
	for i in range(_projs.size() - 1, -1, -1):
		var p: Dictionary = _projs[i]
		var n := p["node"] as Node3D
		var v: Vector3 = p["vel"]
		if not p["landed"]:
			v.y -= 19.0 * dt
			n.position += v * dt
			n.rotate_x(dt * 6.0)
			var gy: float = _world.ground_height(n.position.x, n.position.z, n.position.y)
			if n.position.y <= gy + 0.07:
				n.position.y = gy + 0.07
				if v.y < -3.0:
					v.y = -v.y * 0.35   # 弱反弹
					v.x *= 0.6
					v.z *= 0.6
				else:
					p["landed"] = true
				p["vel"] = v
		p["fuse_t"] = float(p["fuse_t"]) + dt
		p["t"] = float(p["t"]) + dt
		var boom_at := 0.9 if str(p["kind"]) == "frag" else 0.5
		if float(p["fuse_t"]) >= boom_at or float(p["t"]) > 4.0:
			_detonate(str(p["kind"]), n.position)
			n.queue_free()
			_projs.remove_at(i)
	# 视觉寿元
	for j in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[j]
		f["t"] = float(f["t"]) + dt
		var fn := f["node"] as Node3D
		var k := float(f["t"]) / float(f["dur"])
		if str(f["kind"]) == "boom":
			fn.scale = Vector3.ONE * (0.4 + 2.6 * k)
			var m: StandardMaterial3D = (fn.get_child(0) as MeshInstance3D).get_active_material(0)
			m.albedo_color.a = 0.85 * (1.0 - k)
		elif str(f["kind"]) == "cloud":
			var cm: StandardMaterial3D = (fn.get_child(0) as MeshInstance3D).get_active_material(0)
			cm.albedo_color.a = 0.62 * (1.0 - k) if k > 0.75 else 0.62
		if float(f["t"]) >= float(f["dur"]):
			fn.queue_free()
			_fx.remove_at(j)
	# 烟球表寿元
	for m2 in range(smoke_spheres.size() - 1, -1, -1):
		var sm2: Dictionary = smoke_spheres[m2]
		sm2["t"] = float(sm2["t"]) - dt
		if float(sm2["t"]) <= 0.0:
			smoke_spheres.remove_at(m2)
	# 玩家白屏渐退
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - dt)
		if _hud != null and _hud.has_method("flash_screen"):
			_hud.flash_screen(_flash_t / 2.0)


## 起爆：三分支效果 + 视觉
func _detonate(kind: String, at: Vector3) -> void:
	match kind:
		"frag":
			var def: Dictionary = HDData.THROWABLES["frag"]
			var r: float = float(def["r"])
			var dmg0: float = float(def["dmg"])
			for si in _soldiers.soldiers.size():
				var s: Dictionary = _soldiers.soldiers[si]
				if bool(s.get("dead", true)):
					continue
				var d := (Vector3(s["pos"].x, float(s["pos"].y) + 1.0, s["pos"].z)).distance_to(at)
				if d <= r:
					_soldiers.apply_hit(si, dmg0 * (1.0 - 0.6 * d / r), false)
			var pd := Vector3(_player.pos.x, _player.pos.y + 1.2, _player.pos.z).distance_to(at)
			if pd <= r:
				_player.hit(dmg0 * 0.8 * (1.0 - 0.6 * pd / r))
			_soldiers.hear_shot(at, 90.0)
			_fx.push_back(_mk_fx(at, "boom", 0.45, Color(1.0, 0.6, 0.25)))
		"smoke":
			var def2: Dictionary = HDData.THROWABLES["smoke"]
			var cloud := _mk_fx(at, "cloud", float(def2["cloud_t"]), Color(0.75, 0.76, 0.74))
			(cloud["node"] as Node3D).scale = Vector3.ONE * (float(def2["r"]) * 0.55)
			smoke_spheres.append({"pos": at + Vector3(0.0, 1.2, 0.0),
					"r": float(def2["r"]), "t": float(def2["cloud_t"])})
		"flash":
			var def3: Dictionary = HDData.THROWABLES["flash"]
			var rf: float = float(def3["r"])
			var pe := Vector3(_player.pos.x, _player.pos.y + 1.55, _player.pos.z)
			var to_f := (at - pe).normalized()
			var fwd: Vector3 = -_player.cam.global_transform.basis.z
			if pe.distance_to(at) <= rf + 1.0 and fwd.dot(to_f) > 0.25 \
					and not blocks_sight(pe, at):
				_flash_t = 2.0
			for si2 in _soldiers.soldiers.size():
				var s2: Dictionary = _soldiers.soldiers[si2]
				if bool(s2.get("dead", true)):
					continue
				var se := Vector3(s2["pos"].x, float(s2["pos"].y) + 1.5, s2["pos"].z)
				if se.distance_to(at) <= rf and not blocks_sight(se, at):
					s2["blind_t"] = float(def3["blind_t"])
			_fx.push_back(_mk_fx(at, "boom", 0.25, Color(1.0, 1.0, 0.95)))


func _mk_fx(at: Vector3, kind: String, dur: float, col: Color) -> Dictionary:
	var root := Node3D.new()
	root.position = at
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5 if kind == "boom" else 1.0
	sm.height = 1.0 if kind == "boom" else 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.set_surface_override_material(0, m)
	root.add_child(mi)
	if kind == "boom":
		var li := OmniLight3D.new()
		li.light_color = col
		li.omni_range = 9.0
		li.light_energy = 2.4
		root.add_child(li)
	add_child(root)
	return {"node": root, "t": 0.0, "dur": dur, "kind": kind}
