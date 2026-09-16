class_name DayCycle
extends Node
## 20 分钟一昼夜（日出/白天/黄昏/黑夜）+ 天气系统（晴/大雾/雨/雪）。
## 每帧 advance(dt) 推进时间与天气状态机，apply(env, cam) 驱动环境表现。

const DAY_REAL_SECONDS := 1200.0   # 现实 20 分钟 = 游戏 24 小时
const MIN_PER_SEC := 1440.0 / DAY_REAL_SECONDS

var time_min := 480.0              # 游戏时刻（分钟，480 = 08:00 开局）
var day_index := 0                 # 第几天（时间跨过午夜 +1）
var weather := "clear"             # clear / fog / rain / snow
var weather_intensity := 0.0       # 当前天气强度 0..1（平滑过渡）
var night_f := 0.0                 # 夜色系数 0..1
var phase_name := "day"            # sunrise / day / dusk / night

var _weather_target := "clear"
var _weather_switch := randf_range(100.0, 220.0)
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _cam: Camera3D


func setup(env, cam: Camera3D) -> void:
	_cam = cam
	_make_weather_particles()


## 每帧推进（真实 dt 秒）
func advance(dt: float) -> void:
	var prev := time_min
	time_min = fmod(time_min + dt * MIN_PER_SEC, 1440.0)
	if time_min < prev:
		day_index += 1   # 跨过午夜：新的一天
	# ---- 天气状态机：到点掷骰换天气，强度平滑过渡 ----
	_weather_switch -= dt
	if _weather_switch <= 0.0:
		_weather_switch = randf_range(110.0, 240.0)
		var roll := randf()
		_weather_target = "clear" if roll < 0.5 else (
				"fog" if roll < 0.66 else (
				"rain" if roll < 0.86 else "snow"))
	if weather != _weather_target and weather_intensity <= 0.0:
		weather = _weather_target   # 旧天气已淡出，切入新天气
	# 强度：非晴天气淡入；切走时先淡出
	var want := 1.0 if weather == _weather_target and weather != "clear" else 0.0
	weather_intensity = move_toward(weather_intensity, want, dt / 9.0)


## 应用到环境（game._process 调用）
func apply(env) -> void:
	# ---- 太阳/月亮姿态：elev = sin((t-6:00)/24h * 2π)，6 点升 18 点落 ----
	var ang := (time_min - 360.0) / 1440.0 * TAU
	var elev := sin(ang)                        # -1 深夜 .. 1 正午
	var az := deg_to_rad(-108.0) + (time_min / 1440.0) * TAU * 0.5
	var el := clampf(elev, -1.0, 1.0) * deg_to_rad(58.0)
	var sun_dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
	var moon_dir := Vector3(-sun_dir.x, maxf(-sun_dir.y, 0.12), -sun_dir.z).normalized()
	# ---- 相位权重 ----
	var day_w := clampf(elev * 3.2, 0.0, 1.0)
	var night_w := clampf(-elev * 3.2, 0.0, 1.0)
	var dusk_w := clampf(1.0 - day_w - night_w, 0.0, 1.0)
	var total := maxf(day_w + dusk_w + night_w, 0.001)
	day_w /= total
	dusk_w /= total
	night_w /= total
	night_f = night_w
	if night_w > 0.6:
		phase_name = "night"
	elif dusk_w > 0.35:
		phase_name = "sunrise" if time_min < 720.0 else "dusk"
	else:
		phase_name = "day"
	# ---- 调色板（白天 / 黄昏 / 夜）----
	var day_top := Color("#2f63b8")
	var day_mid := Color("#6fa3dc")
	var day_bot := Color("#a9cfec")
	var dusk_top := Color("#3a3f6e")
	var dusk_mid := Color("#c96a3a")
	var dusk_bot := Color("#e8944a")
	var night_top := Color("#050813")
	var night_mid := Color("#0a1024")
	var night_bot := Color("#141c34")
	var top := (day_top * day_w + dusk_top * dusk_w + night_top * night_w)
	var mid := (day_mid * day_w + dusk_mid * dusk_w + night_mid * night_w)
	var bot := (day_bot * day_w + dusk_bot * dusk_w + night_bot * night_w)
	# ---- 天气灰化 ----
	var dim := 0.0
	var fog_mul := 1.0
	var vol_mul := 1.0
	var amb_mul := 1.0
	if env.get("underground") != null and bool(env.get("underground")):
		amb_mul = 1.15   # 地下靠灯光照明，环境光略提
	match weather:
		"fog":
			dim = 0.75
			fog_mul = lerpf(1.0, 0.10, weather_intensity)
			vol_mul = lerpf(1.0, 3.2, weather_intensity)
			amb_mul = lerpf(1.0, 0.9, weather_intensity)
		"rain":
			dim = 0.62
			fog_mul = lerpf(1.0, 0.62, weather_intensity)
			vol_mul = lerpf(1.0, 1.8, weather_intensity)
			amb_mul = lerpf(1.0, 0.72, weather_intensity)
		"snow":
			dim = 0.45
			fog_mul = lerpf(1.0, 0.4, weather_intensity)
			vol_mul = lerpf(1.0, 1.6, weather_intensity)
			amb_mul = lerpf(1.0, 0.82, weather_intensity)
			env.set_snow_ground(weather_intensity if weather == "snow" else 0.0)
	if weather != "snow":
		env.set_snow_ground(0.0)
	# ---- 应用 ----
	var amb_col := Color("#c4cdd6").lerp(Color("#2c3d63"), night_w)
	env.set_sky_palette(top, mid, bot)
	env.set_celestial(sun_dir,
			clampf(elev * 4.0, 0.0, 1.0) * 1.5 * amb_mul,
			Color("#ffedd0").lerp(Color("#ff9a4a"), dusk_w),
			moon_dir, night_f, dim * weather_intensity
					if weather != "clear" else dim)
	env.set_atmosphere(amb_col,
			(0.55 + 0.4 * day_w + 0.18 * dusk_w) * amb_mul,
			bot, fog_mul, vol_mul)
	if _rain != null:
		_rain.emitting = weather == "rain" and weather_intensity > 0.03
		_rain.amount_ratio = lerpf(0.25, 1.0, weather_intensity)
	if _snow != null:
		_snow.emitting = weather == "snow" and weather_intensity > 0.03
	if _cam != null:
		var cp: Vector3 = _cam.global_position
		if _rain != null:
			_rain.global_position = Vector3(cp.x, cp.y + 8.0, cp.z)
		if _snow != null:
			_snow.global_position = Vector3(cp.x, cp.y + 10.0, cp.z)


## 天气抓地倍率（车辆物理每帧读取：雨 0.8 / 雪 0.6，随强度平滑）
func grip_mul() -> float:
	var mul := 1.0
	match weather:
		"rain": mul = 0.8
		"snow": mul = 0.6
		"fog": mul = 0.92
	return lerpf(1.0, mul, weather_intensity)


## 时刻字符串（08:24）
func clock_text() -> String:
	var hh := int(time_min / 60.0)
	var mm := int(time_min) % 60
	return "%02d:%02d" % [hh, mm]


func phase_text() -> String:
	match phase_name:
		"sunrise": return "日出"
		"dusk": return "黄昏"
		"night": return "夜"
		_: return "白天"


func weather_text() -> String:
	match weather:
		"fog": return "大雾"
		"rain": return "下雨"
		"snow": return "下雪"
		_: return "晴"


## ---- 雨 / 雪 粒子 ----

func _make_weather_particles() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 1100
	_rain.lifetime = 1.1
	_rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var rpm := ParticleProcessMaterial.new()
	rpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rpm.emission_box_extents = Vector3(34, 2, 34)
	rpm.gravity = Vector3(3, -46, 0)
	rpm.initial_velocity_min = 0.0
	rpm.initial_velocity_max = 2.0
	_rain.process_material = rpm
	var rquad := QuadMesh.new()
	rquad.size = Vector2(0.05, 0.8)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.62, 0.72, 0.85, 0.34)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rquad.material = rmat
	_rain.draw_pass_1 = rquad
	_rain.emitting = false
	add_child(_rain)

	_snow = GPUParticles3D.new()
	_snow.amount = 750
	_snow.lifetime = 9.0
	_snow.visibility_aabb = AABB(Vector3(-45, -34, -45), Vector3(90, 68, 90))
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(40, 2, 40)
	spm.gravity = Vector3(0.6, -2.6, 0.4)
	spm.initial_velocity_min = 0.2
	spm.initial_velocity_max = 1.0
	spm.angle_min = -PI
	spm.angle_max = PI
	spm.angular_velocity_min = -2.0
	spm.angular_velocity_max = 2.0
	_snow.process_material = spm
	var squad := QuadMesh.new()
	squad.size = Vector2(0.16, 0.16)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.97, 0.98, 1.0, 0.8)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	squad.material = smat
	_snow.draw_pass_1 = squad
	_snow.emitting = false
	add_child(_snow)
