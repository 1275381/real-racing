class_name RRAudio
extends Node
## 程序化引擎音效：锯齿+方波双振荡器 -> 软削波 -> 单极低通，转速驱动音高
## 另有：轮胎摩擦啸叫(带通噪声)、风噪、路肩隆隆、碰撞闷响、倒计时哔声
## （移植自 js/audio.js，全部用 Godot 音频节点 + 实时合成实现）

const MIX_RATE := 22050
const MASTER_VOL := 0.9

var muted := false
var _engine_player: AudioStreamPlayer
var _engine_gen: AudioStreamGenerator
var _ph1 := 0.0
var _ph2 := 0.0
var _lp_y := 0.0
var _engine_running := false
var _engine_vol := 0.0
var _engine_rpm := 0.1
var _engine_load := 0.0

var _skid_target := 0.0
var _wind_target := 0.0
var _rumble_target := 0.0
var _bus_skid := -1
var _bus_wind := -1
var _bus_rumble := -1

var _thud: AudioStreamWAV
var _thud_pool: Array[AudioStreamPlayer] = []
var _thud_idx := 0
var _beep_cache := {}


func _ready() -> void:
	_setup_noise_buses()
	_setup_engine()
	_thud = _make_thud()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.stream = _thud
		p.bus = "Master"
		add_child(p)
		_thud_pool.append(p)


func _setup_noise_buses() -> void:
	var noise := _make_noise_stream()
	var defs := [
		{"name": "RRSkid", "effect": AudioEffectBandPassFilter.new(), "freq": 850.0},
		{"name": "RRWind", "effect": AudioEffectLowPassFilter.new(), "freq": 300.0},
		{"name": "RRRumble", "effect": AudioEffectLowPassFilter.new(), "freq": 120.0},
	]
	for d in defs:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, d["name"])
		AudioServer.set_bus_send(idx, "Master")
		var fx: AudioEffect = d["effect"]
		fx.cutoff_hz = d["freq"]
		if fx is AudioEffectBandPassFilter:
			(fx as AudioEffectBandPassFilter).resonance = 12.0
		AudioServer.add_bus_effect(idx, fx)
		var player := AudioStreamPlayer.new()
		player.stream = noise
		player.bus = d["name"]
		player.volume_db = -60.0
		player.autoplay = false
		add_child(player)
		player.play()
		player.stop()   # 就绪后由 ensure() 启动
		match d["name"]:
			"RRSkid":
				_bus_skid = idx
				_skid_player = player
			"RRWind":
				_bus_wind = idx
				_wind_player = player
			"RRRumble":
				_bus_rumble = idx
				_rumble_player = player
	# 路肩隆隆低速回放（JS 里 playbackRate 0.4）
	if _rumble_player != null:
		_rumble_player.pitch_scale = 0.4


var _skid_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _rumble_player: AudioStreamPlayer


## 必须在用户手势/开始比赛时调用
func ensure() -> void:
	if _skid_player != null and not _skid_player.playing:
		_skid_player.play()
	if _wind_player != null and not _wind_player.playing:
		_wind_player.play()
	if _rumble_player != null and not _rumble_player.playing:
		_rumble_player.play()


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


# ---------------- 引擎 ----------------

## 组别引擎声纹：同一套合成器，不同波形/频率/滤波参数 → 截然不同的声浪
const ENGINE_PROFILES := {
	"street": {      # 运动街头：低频粗暴隆隆（不规则点火、方波粗、低通闷）
		"base_hz": 34.0, "rpm_span": 160.0, "sub_ratio": 0.25, "sq_mix": 0.9,
		"lp_base": 250.0, "lp_rpm": 2000.0, "lp_load": 750.0, "drive_k": 3.1,
	},
	"combustion": {  # 燃油跑车：V8/V12 均匀点火咆哮（锯齿为主、中低频厚实）
		"base_hz": 42.0, "rpm_span": 175.0, "sub_ratio": 0.501, "sq_mix": 0.55,
		"lp_base": 320.0, "lp_rpm": 2600.0, "lp_load": 900.0, "drive_k": 2.6,
	},
	"hybrid": {      # 混动电驱：电机高频啸叫（近正弦软削波、低通明亮、随转速飙升）
		"base_hz": 55.0, "rpm_span": 215.0, "sub_ratio": 0.5, "sq_mix": 0.1,
		"lp_base": 520.0, "lp_rpm": 3300.0, "lp_load": 1000.0, "drive_k": 1.5,
	},
	"endurance": {   # 热芒耐力：高转竞技尖啸（0.75 高次谐波、低通很亮）
		"base_hz": 48.0, "rpm_span": 195.0, "sub_ratio": 0.75, "sq_mix": 0.35,
		"lp_base": 420.0, "lp_rpm": 3100.0, "lp_load": 950.0, "drive_k": 2.3,
	},
	"dual": {        # 双模旗舰：燃油咆哮 × 耐力尖啸的综合声纹（两 mode 共用）
		"base_hz": 45.0, "rpm_span": 185.0, "sub_ratio": 0.625, "sq_mix": 0.45,
		"lp_base": 370.0, "lp_rpm": 2850.0, "lp_load": 925.0, "drive_k": 2.45,
	},
}

var _profile: Dictionary = ENGINE_PROFILES["combustion"]


## 按组别切换引擎声纹（未知组别回退燃油跑车）
func set_engine_profile(cls: String) -> void:
	_profile = ENGINE_PROFILES.get(cls, ENGINE_PROFILES["combustion"])


func _setup_engine() -> void:
	_engine_gen = AudioStreamGenerator.new()
	_engine_gen.mix_rate = MIX_RATE
	_engine_gen.buffer_length = 0.15
	_engine_player = AudioStreamPlayer.new()
	_engine_player.stream = _engine_gen
	_engine_player.volume_db = -3.0
	add_child(_engine_player)


func start_engine() -> void:
	if not _engine_player.playing:
		_engine_player.play()


func update_engine(rpm_norm: float, load: float, running: bool) -> void:
	_engine_rpm = rpm_norm
	_engine_load = load
	_engine_running = running
	if running:
		start_engine()


func _process(_dt: float) -> void:
	if _engine_player == null or not _engine_player.playing:
		return
	var pb := _engine_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var avail := pb.get_frames_available()
	if avail <= 0:
		return
	avail = mini(avail, 4096)   # 防止一次性生成过大缓冲（headless 下尤其必要）
	var buf := PackedVector2Array()
	buf.resize(avail)
	# 软削波 tanh 近似系数（JS: tanh(2.6x)/tanh(2.6)）；强度随组别声纹可调
	var k: float = _profile.get("drive_k", 2.6)
	var inv_tanh_k := 1.0 / _tanhf(k)
	var base_freq: float = _profile.get("base_hz", 42.0) + _engine_rpm * _profile.get("rpm_span", 175.0)
	var f1 := base_freq
	var f2: float = base_freq * _profile.get("sub_ratio", 0.501)
	var lp_cut: float = _profile.get("lp_base", 320.0) + _engine_rpm * _profile.get("lp_rpm", 2600.0) \
			+ _engine_load * _profile.get("lp_load", 900.0)
	var a_coef := 1.0 - exp(-2.0 * PI * lp_cut / MIX_RATE)
	var vol := (0.05 + _engine_load * 0.17 + _engine_rpm * 0.09) if _engine_running else 0.0
	vol *= MASTER_VOL
	var dt_frame := 1.0 / MIX_RATE
	var sq_mix: float = _profile.get("sq_mix", 0.55)
	for i in avail:
		_ph1 = fposmod(_ph1 + f1 * dt_frame, 1.0)
		_ph2 = fposmod(_ph2 + f2 * dt_frame, 1.0)
		var saw := _ph1 * 2.0 - 1.0
		var sq := 1.0 if _ph2 < 0.5 else -1.0
		var mixed := saw + sq * sq_mix
		var shaped := _tanhf(k * mixed) * inv_tanh_k
		_lp_y += a_coef * (shaped - _lp_y)
		buf[i] = Vector2(_lp_y * vol, _lp_y * vol)   # 立体声帧
	pb.push_buffer(buf)


func _tanhf(x: float) -> float:
	var e := exp(clampf(2.0 * x, -20.0, 20.0))
	return (e - 1.0) / (e + 1.0)


# ---------------- 噪声通道音量 ----------------

func update_skid(amount: float) -> void:
	_set_bus_linear(_bus_skid, minf(0.34, amount * 0.34))


func update_wind(speed_ratio: float) -> void:
	_set_bus_linear(_bus_wind, speed_ratio * speed_ratio * 0.22)


func update_rumble(on: bool, speed: float) -> void:
	_set_bus_linear(_bus_rumble, minf(0.3, 0.1 + speed * 0.004) if on else 0.0)


func _set_bus_linear(idx: int, v: float) -> void:
	if idx < 0:
		return
	var db := linear_to_db(maxf(v, 1e-4))
	if v <= 0.001:
		db = -60.0
	AudioServer.set_bus_volume_db(idx, db)


# ---------------- 一次性音效 ----------------

func collision(strength: float) -> void:
	var s := minf(strength, 1.0)
	if s <= 0.02:
		return
	var p := _thud_pool[_thud_idx]
	_thud_idx = (_thud_idx + 1) % _thud_pool.size()
	p.volume_db = linear_to_db(maxf(0.5 * s, 1e-3))
	p.pitch_scale = 1.0
	p.play()


func beep(freq: int, dur := 0.14, vol := 0.3) -> void:
	var key := "%d_%.2f" % [freq, dur]
	var stream: AudioStreamWAV = _beep_cache.get(key)
	if stream == null:
		stream = _make_square(freq, dur)
		_beep_cache[key] = stream
	var p := _thud_pool[_thud_idx]
	_thud_idx = (_thud_idx + 1) % _thud_pool.size()
	p.stream = stream
	p.volume_db = linear_to_db(vol)
	p.play()
	# 恢复碰撞音流（延迟一拍无所谓，碰撞时会重设）
	p.finished.connect(_restore_stream.bind(p), CONNECT_ONE_SHOT)


func _restore_stream(p: AudioStreamPlayer) -> void:
	p.stream = _thud


# ---------------- WAV 生成 ----------------

func _make_noise_stream() -> AudioStreamWAV:
	var n := int(MIX_RATE * 1.2)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in n:
		var v := int(clampf(rng.randf() * 2.0 - 1.0, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


## 碰撞闷响：噪声衰减 + 低频正弦下扫
func _make_thud() -> AudioStreamWAV:
	var sr := MIX_RATE
	var n := int(sr * 0.28)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var env := pow(1.0 - t, 2.2)
		var noise := (rng.randf() * 2.0 - 1.0) * 0.6 * env
		var f := lerpf(90.0, 38.0, minf(t / 0.64, 1.0))
		phase += f / sr
		var sine := sin(phase * TAU) * 0.5 * env
		var v := int(clampf(noise + sine, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	return wav


func _make_square(freq: int, dur: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := 1.0 if t < dur - 0.02 else maxf(0.0, (dur - t) / 0.02)
		var sq := 1.0 if fposmod(t * freq, 1.0) < 0.5 else -1.0
		var v := int(clampf(sq * env, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
