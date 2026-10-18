class_name HDAudio
extends Node
## 烽火地带音效：全部程序化生成 AudioStreamWAV（16bit/22050），零音频文件。
## 枪声拟真四层合成（2026-10 重做，用户反馈「现在的枪声不拟真」——旧版只有
## 白噪声+80Hz 正弦，听感是软「噗」）。真枪的感知分层（业界分层配方：
## Call of Duty Kilborn 的 Transient/Mechanical/Body/Sub/Tail 五层、
## Splice 武器声 mechanics/low end/detail/tail——本作合并为四层）：
##   ① click 击发机械瞬态：2-8kHz 阻尼正弦短促 click（5-15ms 快衰减）
##      ——拉栓/滑套的机械质感；
##   ② crack 膛口爆裂：宽带噪声减低通残差（≈1kHz 一阶高通，1-4kHz 能量
##      强调）、攻击沿 <1ms——真枪「脆响」的来源，旧版完全缺失的一层；
##   ③ boom 枪体低频：90-220Hz 正弦/三角脉冲（30-80ms）——旧 80Hz thump
##      的升级，三角形变给重枪加「胸腔捶击」谐波；
##   ④ tail 混响尾：低通噪声指数衰减（80-350ms 按枪型、亮度可调）
##      ——室外开阔余响，与爆裂错峰 18ms 起振（毫秒级错峰防瞬态叠满）。
## 每发随机在 play_shot（移调 0.94-1.06 + 音量 ±1.5dB——真枪每发都不同，
## 防采样循环的「机关枪味」）；同一把枪音色一致（种子按枪 id 派生）。
## 命中 ding（1200Hz 短音）、换弹两声咔哒、UI beep（方波按需生成缓存）不变。
## 播放用 4 个 AudioStreamPlayer（复音 4）轮换，同帧连发不互相掐断。
## ensure() 幂等：重复调用不重建。

const MIX_RATE := 22050
const PLAYERS := 4      # 轮换播放器数
const POLYPHONY := 4    # 每个播放器复音数
const CRACK_HP_HZ := 1000.0   # crack 高通角频：噪声减低通残差，1-4kHz 能量强调
const TAIL_OFFSET := 0.018    # 混响尾起振偏移(秒)：与膛口爆裂错峰，出开阔纵深感

## 按枪型四层调音表（未知 id 兜底 rifle）。各层键：
##   click{freq 谐振Hz, dur 秒, gain}——机械瞬态，真枪域 2-8kHz / 5-15ms；
##   crack{dur 秒, gain}——膛口爆裂时长/能量（dur 处包络衰减到 -60dB）；
##   boom{freq Hz, dur 秒, tri 三角占比 0-1, gain}——枪体低频 90-220Hz/30-80ms；
##   tail{dur 秒, bright 亮度 0-1（低通截止 600-5000Hz）, gain}——混响尾；
##   gain 总响度（play_shot 里 linear_to_db(gain*0.9)，沿用旧轨音量基准）。
## 单枪总时长 = TAIL_OFFSET + tail.dur，全部 ≤0.5s（短枪更短，狙击最长）。
## 性格：手枪短促尖 / SMG 干脆 / 步枪饱满 / AKM 略闷 / SCAR-H 厚 /
## M14 更厚（半自动 DMR）/ 霰弹宽轰 / 狙击长尾重轰 / M250 沉重 / 汤姆逊老式。
const SHOT_TUNE := {
	# 手枪：短促尖——click 最亮、boom 短高、尾音收得快
	"pistol": {
		"click": {"freq": 5500.0, "dur": 0.006, "gain": 0.40},
		"crack": {"dur": 0.032, "gain": 0.85},
		"boom": {"freq": 170.0, "dur": 0.036, "tri": 0.10, "gain": 0.48},
		"tail": {"dur": 0.11, "bright": 0.45, "gain": 0.20},
		"gain": 0.68,
	},
	# 汤姆逊：老式——.45 重膛压低频沉、木托吃高频，尾音温
	"smg": {
		"click": {"freq": 3000.0, "dur": 0.008, "gain": 0.42},
		"crack": {"dur": 0.042, "gain": 0.80},
		"boom": {"freq": 112.0, "dur": 0.062, "tri": 0.55, "gain": 0.60},
		"tail": {"dur": 0.17, "bright": 0.30, "gain": 0.26},
		"gain": 0.70,
	},
	# 步枪：饱满——四层均衡、中庸亮度尾音
	"rifle": {
		"click": {"freq": 4200.0, "dur": 0.007, "gain": 0.45},
		"crack": {"dur": 0.048, "gain": 0.90},
		"boom": {"freq": 138.0, "dur": 0.052, "tri": 0.25, "gain": 0.62},
		"tail": {"dur": 0.26, "bright": 0.38, "gain": 0.30},
		"gain": 0.85,
	},
	# 霰弹：宽轰——boom 最低最三角、crack 最长、尾音亮而散
	"shotgun": {
		"click": {"freq": 2400.0, "dur": 0.010, "gain": 0.40},
		"crack": {"dur": 0.062, "gain": 0.95},
		"boom": {"freq": 96.0, "dur": 0.075, "tri": 0.70, "gain": 0.75},
		"tail": {"dur": 0.30, "bright": 0.42, "gain": 0.34},
		"gain": 0.95,
	},
	# 狙击：长尾重轰——最长尾音 + 重低频，响度顶格
	"sniper": {
		"click": {"freq": 3600.0, "dur": 0.008, "gain": 0.42},
		"crack": {"dur": 0.055, "gain": 0.95},
		"boom": {"freq": 98.0, "dur": 0.078, "tri": 0.60, "gain": 0.78},
		"tail": {"dur": 0.35, "bright": 0.32, "gain": 0.36},
		"gain": 1.0,
	},
	# 乌兹：干脆偏薄——高射速单发最短
	"uzi": {
		"click": {"freq": 5200.0, "dur": 0.005, "gain": 0.38},
		"crack": {"dur": 0.030, "gain": 0.82},
		"boom": {"freq": 185.0, "dur": 0.032, "tri": 0.10, "gain": 0.42},
		"tail": {"dur": 0.10, "bright": 0.50, "gain": 0.18},
		"gain": 0.64,
	},
	# MP5：干脆——9mm 清脆机械感
	"mp5": {
		"click": {"freq": 4800.0, "dur": 0.006, "gain": 0.40},
		"crack": {"dur": 0.034, "gain": 0.85},
		"boom": {"freq": 160.0, "dur": 0.038, "tri": 0.15, "gain": 0.48},
		"tail": {"dur": 0.12, "bright": 0.45, "gain": 0.20},
		"gain": 0.66,
	},
	# P90：干脆偏尖——5.7mm 高压细响
	"p90": {
		"click": {"freq": 5600.0, "dur": 0.005, "gain": 0.36},
		"crack": {"dur": 0.031, "gain": 0.80},
		"boom": {"freq": 190.0, "dur": 0.034, "tri": 0.05, "gain": 0.42},
		"tail": {"dur": 0.11, "bright": 0.50, "gain": 0.18},
		"gain": 0.63,
	},
	# 维克托：干脆最短——后坐柔和、连发哒哒
	"vector": {
		"click": {"freq": 5000.0, "dur": 0.005, "gain": 0.36},
		"crack": {"dur": 0.028, "gain": 0.78},
		"boom": {"freq": 175.0, "dur": 0.032, "tri": 0.05, "gain": 0.40},
		"tail": {"dur": 0.09, "bright": 0.52, "gain": 0.16},
		"gain": 0.62,
	},
	# MK4：干脆——4.6mm 微口径与 MP5 同族稍紧
	"mk4": {
		"click": {"freq": 4600.0, "dur": 0.006, "gain": 0.40},
		"crack": {"dur": 0.033, "gain": 0.84},
		"boom": {"freq": 165.0, "dur": 0.036, "tri": 0.10, "gain": 0.46},
		"tail": {"dur": 0.12, "bright": 0.45, "gain": 0.19},
		"gain": 0.66,
	},
	# MP7：更短促——4.6×30mm PDW 高射速（950rpm），短枪管轻爆裂快收尾
	# （参考 mp5 档收紧：crack/boom/tail 各缩短 1-2ms，click 略亮）
	"mp7": {
		"click": {"freq": 5000.0, "dur": 0.005, "gain": 0.39},
		"crack": {"dur": 0.030, "gain": 0.83},
		"boom": {"freq": 172.0, "dur": 0.034, "tri": 0.08, "gain": 0.45},
		"tail": {"dur": 0.10, "bright": 0.48, "gain": 0.18},
		"gain": 0.64,
	},
	# M4A1：饱满——5.56 均衡、尾音明快
	"m4a1": {
		"click": {"freq": 4400.0, "dur": 0.007, "gain": 0.45},
		"crack": {"dur": 0.045, "gain": 0.88},
		"boom": {"freq": 150.0, "dur": 0.048, "tri": 0.20, "gain": 0.60},
		"tail": {"dur": 0.24, "bright": 0.40, "gain": 0.28},
		"gain": 0.82,
	},
	# AKM：略闷——导气孔大+木托，亮度压低、低频三角加厚
	"akm": {
		"click": {"freq": 3400.0, "dur": 0.008, "gain": 0.42},
		"crack": {"dur": 0.050, "gain": 0.85},
		"boom": {"freq": 118.0, "dur": 0.058, "tri": 0.50, "gain": 0.66},
		"tail": {"dur": 0.26, "bright": 0.30, "gain": 0.30},
		"gain": 0.86,
	},
	# SCAR-H：厚——7.62 NATO 满装药，低频长而沉
	"scarh": {
		"click": {"freq": 3200.0, "dur": 0.009, "gain": 0.45},
		"crack": {"dur": 0.052, "gain": 0.88},
		"boom": {"freq": 105.0, "dur": 0.066, "tri": 0.55, "gain": 0.70},
		"tail": {"dur": 0.28, "bright": 0.30, "gain": 0.32},
		"gain": 0.90,
	},
	# M250：沉重——机枪持续压制感，最低 boom 最暗长尾
	"m250": {
		"click": {"freq": 2800.0, "dur": 0.009, "gain": 0.44},
		"crack": {"dur": 0.056, "gain": 0.90},
		"boom": {"freq": 92.0, "dur": 0.080, "tri": 0.65, "gain": 0.80},
		"tail": {"dur": 0.33, "bright": 0.25, "gain": 0.34},
		"gain": 0.94,
	},
	# M14：更厚——7.62 NATO 半自动 DMR 比赛级长枪管满装药（参考 scarh 档
	# 加厚：boom 更沉更长、tail 长枪管余响再长一档、click 稍钝）
	"m14": {
		"click": {"freq": 3000.0, "dur": 0.009, "gain": 0.46},
		"crack": {"dur": 0.054, "gain": 0.90},
		"boom": {"freq": 98.0, "dur": 0.072, "tri": 0.60, "gain": 0.74},
		"tail": {"dur": 0.31, "bright": 0.28, "gain": 0.34},
		"gain": 0.93,
	},
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


## 开枪：轮换池播放 + 每发随机——移调 0.94-1.06、音量 ±1.5dB。
## 真枪每发都不同（弹药批次/膛压/气温微差）；固定采样不加抖动，
## 连发听感就是「机关枪采样循环」（Splice 武器声设计同款建议）
func play_shot(gun_id: String) -> void:
	var p := _next_player()
	p.stream = _shot_stream(gun_id)
	var tune: Dictionary = SHOT_TUNE.get(gun_id, SHOT_TUNE["rifle"])
	p.volume_db = linear_to_db(maxf(float(tune["gain"]) * 0.9, 0.05)) \
			+ randf_range(-1.5, 1.5)
	p.pitch_scale = randf_range(0.94, 1.06)
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


## 枪声四层合成（分层见类头）。各层独立包络、错峰起振（boom +4ms / tail
## +18ms——毫秒级错峰防瞬态叠满，纵深感即出）；叠完按峰值归一再乘总响度：
## 归一保证永不削波，编码峰值上限 0.88×1.0×31500 ≈ 27720 < 旧轨 32000
## 满刻度——比旧声不响，只更「真」。种子按枪 id 派生：同枪每次音色一致、
## 异枪噪声纹理不同；每发的「不同」交给 play_shot 的移调/音量抖动。
func _shot_stream(gun_id: String) -> AudioStreamWAV:
	if _shots.has(gun_id):
		var cached: AudioStreamWAV = _shots[gun_id]
		return cached
	var tune: Dictionary = SHOT_TUNE.get(gun_id, SHOT_TUNE["rifle"])
	var click: Dictionary = tune["click"]
	var crack: Dictionary = tune["crack"]
	var boom: Dictionary = tune["boom"]
	var tail: Dictionary = tune["tail"]
	# 总时长 = tail 起振偏移 + tail 时长（tail 永远收尾，其余层都在窗口内）
	var total: float = TAIL_OFFSET + float(tail["dur"])
	var n := int(MIX_RATE * total)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gun_id)
	# --- ① click 击发机械瞬态：阻尼正弦双分音（基频 + 2.7× 泛音）——
	#     单正弦太「纯」，双分音出金属拉栓的「锵」而非「哔」
	var c_dur: float = float(click["dur"])
	var c_n := int(MIX_RATE * c_dur)
	var c_f: float = float(click["freq"])
	for i in c_n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 6.9 / c_dur)   # dur 处衰减到 -60dB（ln1000≈6.9）
		buf[i] += (sin(TAU * c_f * t) + sin(TAU * c_f * 2.7 * t) * 0.4) \
				* env * float(click["gain"])
	# --- ② crack 膛口爆裂：白噪声减一阶低通残差（≈1kHz 高通），1-4kHz
	#     能量强调；攻击沿 4 个采样（0.2ms <1ms）——脆响全靠这道立起的沿
	var k_dur: float = float(crack["dur"])
	var k_n := int(MIX_RATE * k_dur)
	var lp := 0.0
	var k := 1.0 - exp(-TAU * CRACK_HP_HZ / MIX_RATE)   # 一阶低通系数
	for i in k_n:
		var x := rng.randf() * 2.0 - 1.0
		lp += (x - lp) * k
		var t := float(i) / MIX_RATE
		var atk := minf(t / 0.0002, 1.0)
		var env := exp(-t * 6.9 / k_dur)
		buf[i] += (x - lp) * env * atk * float(crack["gain"])
	# --- ③ boom 枪体低频：正弦/三角按 tri 比例混合（三角谐波多=重枪的
	#     「捶胸」感），+4ms 起振与 crack 错峰；2ms 起振防低频猝发的「砰」杂音
	var b_dur: float = float(boom["dur"])
	var b_n := int(MIX_RATE * b_dur)
	var b_off := int(MIX_RATE * 0.004)
	var b_f: float = float(boom["freq"])
	var tri: float = float(boom["tri"])
	var phase := 0.0
	for i in b_n:
		var t := float(i) / MIX_RATE
		phase += TAU * b_f / MIX_RATE
		var x01 := fposmod(phase / TAU + 0.25, 1.0)
		var tw := 1.0 - 2.0 * absf(2.0 * x01 - 1.0)   # 与正弦同相位的三角波
		var atk := minf(t / 0.002, 1.0)
		var env := exp(-t * 6.9 / b_dur)
		if b_off + i < n:
			buf[b_off + i] += lerpf(sin(phase), tw, tri) * env * atk \
					* float(boom["gain"])
	# --- ④ tail 混响尾：低通噪声指数衰减，亮度 0-1 映射低通截止 600-5000Hz
	#     （闷=远处/吸收面，亮=开阔硬反射面），+18ms 起振出「打出去飘出去」
	var t_dur: float = float(tail["dur"])
	var t_n := int(MIX_RATE * t_dur)
	var t_off := int(MIX_RATE * TAIL_OFFSET)
	var fc := lerpf(600.0, 5000.0, float(tail["bright"]))
	var tk := 1.0 - exp(-TAU * fc / MIX_RATE)
	var tlp := 0.0
	for i in t_n:
		var x := rng.randf() * 2.0 - 1.0
		tlp += (x - tlp) * tk
		var t := float(i) / MIX_RATE
		var atk := minf(t / 0.003, 1.0)
		var env := exp(-t * 6.9 / t_dur)
		if t_off + i < n:
			buf[t_off + i] += tlp * env * atk * float(tail["gain"])
	# 峰值归一 → 乘总响度 → 16bit 编码
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var norm: float = (0.88 / peak) if peak > 0.0001 else 0.0
	var g: float = float(tune["gain"])
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * norm * g, -1.0, 1.0) * 31500.0))
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
