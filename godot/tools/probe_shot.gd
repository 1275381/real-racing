extends SceneTree
## 画面渲染探针（诊断用，非 headless）：
##   [环境变量] /Applications/Godot.app/Contents/MacOS/Godot \
##       --path . --audio-driver Dummy -s res://tools/probe_shot.gd
##
## RR_MODE      roam(默认) / race / garage；同时用作输出文件名后缀
## ROAM_SPAWN   "x,z,heading" 漫游出生点
## RR_CAM       "x,y,z,lx,ly,lz" 直接指定机位与朝向
## RR_FOV       覆盖视场角
## RR_SEQ=1     连拍入场运镜 7 帧到 seq_0..6.png（检查穿地/穿楼）
## RR_HIST=1    把跳变像素反投影统计世界 X 直方图（很慢）
## 诊断开关：RR_NOFOG / RR_NOREFL / RR_NOAMB / RR_MAGENTA(洋红天空) / RR_REDGROUND
##
## 默认输出 shot_<mode>_a/_b/_diff.png：冻结逻辑后拍 A，相机沿视线推 2cm 拍 B。
## 几何稳定的像素两帧一致；深度打架的面会翻面 → diff 里高亮成红色。

var _cam: Camera3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/out")
	var mode := OS.get_environment("RR_MODE")
	if mode == "":
		mode = "roam"
	var g: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	for i in 30:
		await process_frame
	if mode == "race":
		g.start_from_garage()
	elif mode == "garage":
		g.to_garage()
	else:
		await g.enter_roam()

	_apply_toggles(g)

	if OS.get_environment("RR_SEQ") == "1":
		for k in 7:
			for i in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/out/seq_%d.png" % k)
			print("  seq_%d cam_y=%.2f" % [k, (g.camera as Camera3D).position.y])
		quit()
		return

	for i in 240:
		await process_frame

	_cam = g.camera
	var veh = g.player.veh
	print("car pos=(%.2f, %.3f, %.2f) surf=%s" % [veh.pos.x, veh.pos.y, veh.pos.z, veh.surface])

	var t_fps := Time.get_ticks_usec()
	for i in 120:
		await process_frame
	print("平均帧时 %.2f ms (%.0f fps)" % [(Time.get_ticks_usec() - t_fps) / 120000.0,
			120.0 * 1e6 / float(Time.get_ticks_usec() - t_fps)])

	g.set_process(false)
	g.set_physics_process(false)

	var cam_env := OS.get_environment("RR_CAM")
	if cam_env.count(",") == 5:
		var cp := cam_env.split(",")
		_cam.position = Vector3(cp[0].to_float(), cp[1].to_float(), cp[2].to_float())
		_cam.look_at(Vector3(cp[3].to_float(), cp[4].to_float(), cp[5].to_float()), Vector3.UP)
	var fov_env := OS.get_environment("RR_FOV")
	if fov_env != "":
		_cam.fov = fov_env.to_float()

	var a := await _shot()
	_cam.position += (-_cam.global_transform.basis.z.normalized()) * 0.02
	var b := await _shot()
	a.save_png("res://tools/out/shot_%s_a.png" % mode)
	b.save_png("res://tools/out/shot_%s_b.png" % mode)

	var w := a.get_width()
	var h := a.get_height()
	var diff := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var changed := 0
	for y in h:
		for x in w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.12:
				changed += 1
				diff.set_pixel(x, y, Color(1, 0, 0, 1))
			else:
				var l := ca.get_luminance() * 0.35
				diff.set_pixel(x, y, Color(l, l, l, 1))
	diff.save_png("res://tools/out/shot_%s_diff.png" % mode)
	print("diff: %d / %d 像素跳变 (%.2f%%)" % [changed, w * h, 100.0 * changed / (w * h)])

	for plane_y in ([0.23, 0.51, 0.56] if OS.get_environment("RR_HIST") == "1" else []):
		var hist := {}
		for y in range(360, 700):
			for x in w:
				if diff.get_pixel(x, y).r < 0.9:
					continue
				var ro := _cam.project_ray_origin(Vector2(x, y))
				var rd := _cam.project_ray_normal(Vector2(x, y))
				if rd.y >= -1e-5:
					continue
				var t: float = (plane_y - ro.y) / rd.y
				if t <= 0.0 or t > 900.0:
					continue
				var key := int(round((ro.x + rd.x * t) * 2.0))
				hist[key] = int(hist.get(key, 0)) + 1
		var keys := hist.keys()
		keys.sort_custom(func(a2, b2): return hist[a2] > hist[b2])
		var top := []
		for k in keys.slice(0, 10):
			top.append("x=%.1f:%d" % [float(k) / 2.0, hist[k]])
		print("plane y=%.2f 顶峰: %s" % [plane_y, ", ".join(top)])
	quit()


func _apply_toggles(g: Node) -> void:
	if OS.get_environment("RR_NOFOG") == "1":
		g.env._env.fog_enabled = false
		print("已关闭雾")
	if OS.get_environment("RR_NOREFL") == "1":
		g.env._env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		print("已关闭反射源")
	if OS.get_environment("RR_NOAMB") == "1":
		g.env._env.ambient_light_energy = 0.0
		print("已关闭环境光")
	if OS.get_environment("RR_MAGENTA") == "1":
		for k in ["top_color", "mid_color", "bot_color"]:
			g.env._sky_mat.set_shader_parameter(k, Color(1, 0, 1))
		print("天空已改为洋红")
	if OS.get_environment("RR_NOMIP") == "1":
		var gm2: StandardMaterial3D = (g.env._ground.mesh as PlaneMesh).material
		gm2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		print("地面已关闭 mipmap")
	if OS.get_environment("RR_REDGROUND") == "1":
		var gm: StandardMaterial3D = (g.env._ground.mesh as PlaneMesh).material
		gm.albedo_texture = null
		gm.albedo_color = Color(1, 0, 0)
		print("地面已染红 visible=%s y=%.2f" % [g.env._ground.visible, g.env._ground.position.y])


func _shot() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
