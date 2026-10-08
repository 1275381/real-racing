class_name HDAudio
extends Node
## 烽火地带音效：全部程序化生成 AudioStreamWAV（16bit/22050），零音频文件。
## 枪声 = 白噪声指数衰减 + 80Hz 低频 thump 叠加，按 gun_id 微调时长/音量
## （sniper 长而响、pistol 短脆）；命中 ding（1200Hz 短音）、换弹两声咔哒、
## UI beep（方波按需生成缓存）。播放用 4 个 AudioStreamPlayer（复音 4）轮换，
## 同帧连发不互相掐断。ensure() 幂等：重复调用不重建。

const MIX_RATE := 22050
const PLAYERS := 4      # 轮换播放器数
const POLYPHONY := 4    # 每个播放器复音数

## 按 gun_id 微调枪声：dur 时长(秒) / decay 衰减速度 / gain 音量。
## 2026-10 扩充七枪：射速越快单发越短促；7.62 重弹更长更响（未知 id 仍兜底 rifle）
const SHOT_TUNE := {
	"pistol": {"dur": 0.12, "decay": 36.0, "gain": 0.7},
	"smg": {"dur": 0.13, "decay": 32.0, "gain": 0.65},
	"rifle": {"dur": 0.18, "decay": 24.0, "gain": 0.85},
	"shotgun": {"dur": 0.26, "decay": 16.0, "gain": 0.95},
	"sniper": {"dur": 0.34, "decay": 11.0, "gain": 1.0},
	"uzi": {"dur": 0.14, "decay": 30.0, "gain": 0.66},
	"mp5": {"dur": 0.13, "decay": 32.0, "gain": 0.65},
	"p90": {"dur": 0.12, "decay": 34.0, "gain": 0.62},
	"vector": {"dur": 0.11, "decay": 36.0, "gain": 0.6},
	"m4a1": {"dur": 0.18, "decay": 24.0, "gain": 0.85},
	"akm": {"dur": 0.2, "decay": 22.0, "gain": 0.88},
	"scarh": {"dur": 0.24, "decay": 18.0, "gain": 0.92},
}

var _pool: Array[AudioStreamPlayer] = []
var _idx := 0
var _shots := {}          # gun_id -> AudioStreamWAV（ensure 预生成，懒生成兜底）
var _hit: AudioStreamWAV
var _reload: AudioStreamWAV
var _beeps := {}          # "freq_dur" -> AudioStreamWAV（按需生成缓存）


## 生成全部流与播放器（幂等：只有首次调用才建）。进本模式时 main 调一次
func ensure() -> void:
	if not _pool.is_empty():
		return
	for i in PLAYERS:
		var p := AudioStreamPlayer.new()
		p.max_polyphony = POLYPHONY
		add_child(p)
		_pool.append(p)
	for gid in SHOT_TUNE:
		_shot_stream(str(gid))
	_hit = _make_ding()
	_reload = _make_reload()


func play_shot(gun_id: String) -> void:
	var p := _next_player()
	p.stream = _shot_stream(gun_id)
	var tune: Dictionary = SHOT_TUNE.get(gun_id, SHOT_TUNE["rifle"])
	p.volume_db = linear_to_db(maxf(float(tune["gain"]) * 0.9, 0.05))
	p.pitch_scale = randf_range(0.92, 1.08)   # 每发微移调：连发不像机关枪一样死板
	p.play()


## 命中反馈 ding：1200Hz 正弦 0.06s 快衰减
func play_hit() -> void:
	var p := _next_player()
	p.stream = _hit
	p.volume_db = linear_to_db(0.5)
	p.pitch_scale = 1.0
	p.play()


## 换弹：两声金属咔哒（与枪声共用轮换池）
func play_reload() -> void:
	var p := _next_player()
	p.stream = _reload
	p.volume_db = linear_to_db(0.55)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


## UI beep：方波，按需生成并缓存（同参数复用流，不刷内存）
func beep(freq: float, dur: float) -> void:
	var key := "%.1f_%.2f" % [freq, dur]
	var stream: AudioStreamWAV = _beeps.get(key)
	if stream == null:
		stream = _make_square(freq, dur)
		_beeps[key] = stream
	var p := _next_player()
	p.stream = stream
	p.volume_db = linear_to_db(0.35)
	p.pitch_scale = 1.0
	p.play()


## ---------------- 内部：WAV 生成 ----------------


## 轮换取播放器；ensure 未跑过则先补跑（播放接口不依赖外部先 ensure）
func _next_player() -> AudioStreamPlayer:
	if _pool.is_empty():
		ensure()
	var p: AudioStreamPlayer = _pool[_idx]
	_idx = (_idx + 1) % _pool.size()
	return p


## 枪声：白噪声 0.8 + 80Hz 低频 thump 0.55 叠加，指数衰减包络（时长/衰减按枪调）
func _shot_stream(gun_id: String) -> AudioStreamWAV:
	if _shots.has(gun_id):
		var cached: AudioStreamWAV = _shots[gun_id]
		return cached
	var tune: Dictionary = SHOT_TUNE.get(gun_id, SHOT_TUNE["rifle"])
	var dur: float = float(tune["dur"])
	var decay: float = float(tune["decay"])
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71   # 固定种子：同一把枪每次音色一致，只有 pitch 微移
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * decay)
		phase += TAU * 80.0 / MIX_RATE
		var v := ((rng.randf() * 2.0 - 1.0) * 0.8 + sin(phase) * 0.55) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var wav := _raw_wav(data)
	_shots[gun_id] = wav
	return wav


## 命中 ding：1200Hz 正弦 0.06s，指数衰减出"叮"的金属感
func _make_ding() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.06)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := sin(TAU * 1200.0 * t) * exp(-t * 70.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	return _raw_wav(data)


## 换弹：0.22s 内两声短促噪声咔哒（脱匣 + 上匣）
func _make_reload() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.22)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	for i in n:
		var t := float(i) / MIX_RATE
		var click := 0.0
		if t < 0.03 or (0.1 < t and t < 0.13):
			click = (rng.randf() * 2.0 - 1.0) * exp(-t * 60.0)
		data.encode_s16(i * 2, int(clampf(click, -1.0, 1.0) * 32000.0))
	return _raw_wav(data)


## UI beep：方波 + 结尾 0.02s 收音，防咔哒爆音
func _make_square(freq: float, dur: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := 1.0 if t < dur - 0.02 else maxf(0.0, (dur - t) / 0.02)
		var sq := 1.0 if fposmod(t * freq, 1.0) < 0.5 else -1.0
		data.encode_s16(i * 2, int(clampf(sq * env * 0.6, -1.0, 1.0) * 32000.0))
	return _raw_wav(data)


func _raw_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
