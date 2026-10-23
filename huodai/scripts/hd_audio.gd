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
## M14 更厚（半自动 DMR）/ 霰弹宽轰 / 狙击长尾重轰 / M250 沉重 / 汤姆逊老式 /
## AS Val 消音（全枪册唯一消音档：机械脆、爆裂削、低频闷突、尾音短闷）。
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
	# AS Val：自带一体消音器的亚音速特种枪音色（2026-10 用户点名「注意声音」
	# ——消音枪与普通枪本质不同，专项调音不套 rifle 档；锚点 m4a1 5.56 全自动
	# 档逐层对照）：
	# ① click 机械瞬态保留但更脆：拉栓/枪机金属声不被消音器吸收——频率抬到
	#    4800Hz（比 rifle 4400 亮一档读「更脆」）、增益放大到 0.55（普通枪
	#    0.45~0.46）——总响度压低后机械层是主认知线索，必须放大补偿；
	# ② crack 膛口爆裂大幅削减：亚音速弹没有超音速爆响，消音器再把膛口压差
	#    泄成短促「噗」——时长 0.022（rifle 0.048 的一半不到）、增益 0.32
	#    （rifle 0.90 的 1/3 档）；
	# ③ boom 反而稍突出：消音器内腔共振拉长低频——130Hz（内腔驻波比 rifle
	#    138 更低沉）、时长 0.056 稍长、增益 0.66 反超 rifle 的 0.62（小口径
	#    枪低频反超=「罐子里放炮」的消音器体感）；
	# ④ tail 短促闷收：消音枪没有开阔膛口余响——时长 0.10（rifle 0.26 的
	#    一半不到）、亮度 0.18（低通截止 ≈1.4kHz「闷」档）、增益 0.14；
	# ⑤ 总增益 0.52：消音=安静，比全枪册普通步枪档（0.82~0.93）低一档多、
	#    也低于最安静的冲锋枪（vector 0.62）——全枪册唯一消音档
	"asval": {
		"click": {"freq": 4800.0, "dur": 0.006, "gain": 0.55},
		"crack": {"dur": 0.022, "gain": 0.32},
		"boom": {"freq": 130.0, "dur": 0.056, "tri": 0.35, "gain": 0.66},
		"tail": {"dur": 0.10, "bright": 0.18, "gain": 0.14},
		"gain": 0.52,
	},
	# K416：饱满偏脆——5.56 中口径 HK416 高射速（880rpm），参考 m4a1/scarh
	# 档之间：m4a1 的均衡骨架上 crack 略提脆（短行程活塞导气比直吹干脆）、
	# boom 略沉（枪体比 M4 重一档）、tail 明快收束——高射速连发不糊
	"k416": {
		"click": {"freq": 4600.0, "dur": 0.007, "gain": 0.44},
		"crack": {"dur": 0.047, "gain": 0.89},
		"boom": {"freq": 142.0, "dur": 0.050, "tri": 0.22, "gain": 0.61},
		"tail": {"dur": 0.25, "bright": 0.40, "gain": 0.29},
		"gain": 0.84,
	},
	# AN-94：尖脆双响——5.45×39mm 小口径高初速（900m/s，2026-10 商店枪 S12
	# 微光赛季超点射新枪）：在 m4a1/k416 的 5.56 档上再抬亮一档——click 更亮
	# （弹头轻、机械瞬态「叮」感强）、crack 短促尖锐（高初速小口径爆裂频谱
	# 偏高、衰减快——「啪」的鞭梢感）、boom 轻一档（3.85kg 重枪体+双室制退
	# 器泄压吸能）、tail 明快收短（制退器侧排泄压、开阔余响弱）。超点射两
	# 连发（间隔 0.0333s≈2 帧）两个 crack 自然叠出「哒」的密双响——间隔本身
	# 出效果，不需要特殊音频逻辑
	"an94": {
		"click": {"freq": 5000.0, "dur": 0.006, "gain": 0.44},
		"crack": {"dur": 0.042, "gain": 0.91},
		"boom": {"freq": 152.0, "dur": 0.044, "tri": 0.15, "gain": 0.56},
		"tail": {"dur": 0.21, "bright": 0.44, "gain": 0.26},
		"gain": 0.82,
	},
}

var _pool: Array[AudioStreamPlayer] = []
var _idx := 0
## 2026-10 改进方案第 4 节：敌人枪声/脚步走 AudioStreamPlayer3D（主世界听者 =
## 玩家主相机）——按距离衰减、左右声像、远处高频被滤（越远越闷）
var _pool3d: Array[AudioStreamPlayer3D] = []
var _idx3d := 0
const PLAYERS_3D := 10
var _steps: Array[AudioStreamWAV] = []   # 合成脚步（沙地军靴）6 个变体：实录缺失时兜底
## 实录脚步（2026-10 用户同意换 Kenney「Impact Sounds」CC0 音效包，见
## assets/audio/footsteps/LICENSE_Kenney_ImpactSounds.txt）：沙地用 snow 组（压实
## 颗粒的嘎吱声最像沙砾），地下靶馆/坡道/入口房等硬地坪用 concrete 组
const STEP_DIR := "res://assets/audio/footsteps/"
const STEP_SETS := {"sand": "snow", "concrete": "concrete"}
const STEP_REC_DB := -4.3   # 实录样本比合成版响（RMS 0.09 vs 0.055）：按同响度对齐
var _step_rec := {}         # 地面 -> Array[AudioStream]
var _step_foot := 1.0                     # 左右脚交替（音高 ±3%，不重复同一变体）
var _step_last := -1
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
	for k in 6:
		_steps.append(_make_step(311 + k * 17))
	for surf in STEP_SETS:
		var arr: Array = []
		for k in 5:
			var path := STEP_DIR + "footstep_%s_%03d.ogg" % [STEP_SETS[surf], k]
			var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
			if st == null and FileAccess.file_exists(path):
				st = AudioStreamOggVorbis.load_from_file(path)   # 另一台电脑还没导入：直接读原文件
			if st != null:
				arr.append(st)
		_step_rec[surf] = arr


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


## 敌人枪声（3D）：世界坐标 pos 发声；unit_size 14 → 14 m 处约原音量、
## 百米外衰减约 -17 dB；远处低通（attenuation_filter）让远枪发闷，听得出远近
func play_shot_3d(gun_id: String, pos: Vector3) -> void:
	var p := _next_3d()
	p.global_position = pos
	p.stream = _shot_stream(gun_id)
	var tune: Dictionary = SHOT_TUNE.get(gun_id, SHOT_TUNE["rifle"])
	p.unit_size = 14.0
	p.max_distance = 420.0
	p.attenuation_filter_cutoff_hz = 3200.0
	p.attenuation_filter_db = -20.0
	p.volume_db = linear_to_db(maxf(float(tune["gain"]) * 0.9, 0.05)) + randf_range(-1.5, 1.5)
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


## 取一声脚步：有实录用实录（不连续重复同一条），否则合成兜底；返回 [stream, 额外 dB]
func _pick_step(surface: String) -> Array:
	if _steps.is_empty():
		ensure()
	var rec: Array = _step_rec.get(surface, _step_rec.get("sand", []))
	var pool: Array = rec if not rec.is_empty() else _steps
	var k := randi() % pool.size()
	if k == _step_last and pool.size() > 1:
		k = (k + 1) % pool.size()
	_step_last = k
	return [pool[k], STEP_REC_DB if not rec.is_empty() else 0.0]


## 敌人脚步（3D）：22 m 外听不到（max_distance），跑动更响
func play_step_3d(pos: Vector3, running: bool, surface := "sand") -> void:
	var pk := _pick_step(surface)
	var p := _next_3d()
	p.global_position = pos
	p.stream = pk[0]
	p.unit_size = 3.5
	p.max_distance = 22.0
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -10.0
	p.volume_db = linear_to_db(0.95 if running else 0.7) + float(pk[1]) + randf_range(-1.5, 1.5)
	p.pitch_scale = randf_range(0.9, 1.04)   # 略压低：军靴比雪地鞋沉
	p.play()


## 玩家自己的脚步（2D，轻）：loud 0..1（main：蹲走 0.12 / 步行 0.32 / 疾跑 0.6）。
## 自己的脚步只做「在走」的提示，压在枪声与敌人脚步之下（旧版样本偏响 + -6 dB，整体约降 10 dB）；
## 左右脚交替微调音高、不连续重复同一变体，不再是同一声「噗」循环
func play_step(loud: float, surface := "sand") -> void:
	var pk := _pick_step(surface)
	var p := _next_player()
	_step_foot = -_step_foot
	p.stream = pk[0]
	p.volume_db = linear_to_db(maxf(loud, 0.02)) - 9.0 + float(pk[1]) + randf_range(-1.5, 1.0)
	p.pitch_scale = (0.97 + 0.03 * _step_foot) * randf_range(0.97, 1.03)
	p.play()


## 消音器枪声（第四阶段）：没有膛口爆裂与远场尾音，只剩一声闷「噗」+ 枪机金属
## 咔嗒——低通噪声 0.12 s + 双分音瞬态；音量比原枪声低约 12 dB
var _sup_stream: AudioStreamWAV
var _click_stream: AudioStreamWAV

func play_shot_sup(_gun_id: String) -> void:
	if _sup_stream == null:
		_sup_stream = _make_sup()
	var p := _next_player()
	p.stream = _sup_stream
	p.volume_db = linear_to_db(0.42) + randf_range(-1.0, 1.0)
	p.pitch_scale = randf_range(0.93, 1.07)
	p.play()


## 卡壳空击：干脆的单声金属咔哒
func play_click() -> void:
	if _click_stream == null:
		_click_stream = _make_click()
	var p := _next_player()
	p.stream = _click_stream
	p.volume_db = linear_to_db(0.6)
	p.pitch_scale = 1.0
	p.play()


func _make_sup() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.16)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var lp := 0.0
	var lp2 := 0.0
	var a := 1.0 - exp(-TAU * 1800.0 / MIX_RATE)
	for i in n:
		var t := float(i) / MIX_RATE
		var x := rng.randf() * 2.0 - 1.0
		lp += a * (x - lp)
		lp2 += a * (lp - lp2)
		var puff := lp2 * exp(-t * 38.0) * 2.4
		var clack := (sin(TAU * 2300.0 * t) + 0.5 * sin(TAU * 5100.0 * t)) \
				* exp(-maxf(t - 0.045, 0.0) * 160.0) * (0.35 if t > 0.045 else 0.0)
		data.encode_s16(i * 2, int(clampf(puff + clack, -1.0, 1.0) * 30000.0))
	return _raw_wav(data)


func _make_click() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.05)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := (sin(TAU * 3100.0 * t) + 0.6 * sin(TAU * 6900.0 * t)) * exp(-t * 140.0) * 0.7
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	return _raw_wav(data)


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


## 3D 播放器轮换池（首用时建，挂在本节点下；本节点非 Node3D，3D 播放器按
## 全局坐标定位）
func _next_3d() -> AudioStreamPlayer3D:
	if _pool3d.is_empty():
		for i in PLAYERS_3D:
			var p := AudioStreamPlayer3D.new()
			p.max_polyphony = 2
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			add_child(p)
			_pool3d.append(p)
	var q: AudioStreamPlayer3D = _pool3d[_idx3d]
	_idx3d = (_idx3d + 1) % _pool3d.size()
	return q


## 沙地军靴脚步（2026-10 用户反馈「步伐声音有点大、奇怪」重做）：
## 旧版是一段白噪声一阶低通 + 硬起音，听着像「噗嗤」电流声。新版三层：
## ① 脚跟落地闷响：80–110 Hz 下滑正弦 + 2 阶低通噪声（~450 Hz），3 ms 软起音不爆音；
## ② 沙粒碾压：脚跟/脚掌落地后几十毫秒内随机迸出的短促「沙沙」颗粒（1.6–4.5 kHz
##    衰减噪声颗粒，密度随时间衰减）；③ 脚掌滚动：脚跟后 45–75 ms 再一记更轻的闷响；
## ④ 鞋底擦沙：600–2400 Hz 带通噪声。能量分布刻意让中频占大头——笔记本扬声器
##    放不出 250 Hz 以下，纯低频闷响在那上面等于没声。
## 每个变体随机化落点/音高/颗粒，峰值归一到 0.5（留余量给枪声）
func _make_step(seed_v: int) -> AudioStreamWAV:
	var dur := 0.22
	var n := int(MIX_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t_heel := rng.randf_range(0.004, 0.009)
	var t_toe := t_heel + rng.randf_range(0.045, 0.075)
	var f0 := rng.randf_range(80.0, 110.0)
	# ①③ 闷响（脚跟 1.0 / 脚掌 0.5）
	for hit in [[t_heel, 1.0, 0.028], [t_toe, 0.5, 0.022]]:
		var t0: float = hit[0]
		var amp: float = hit[1]
		var tau: float = hit[2]
		var lp1 := 0.0
		var lp2 := 0.0
		var a := 1.0 - exp(-TAU * 700.0 / MIX_RATE)
		var phase := 0.0
		for i in range(int(t0 * MIX_RATE), n):
			var t := float(i) / MIX_RATE - t0
			var env := minf(t / 0.003, 1.0) * exp(-t / tau)
			if env < 0.0005 and t > 0.01:
				break
			var f := f0 * (1.0 - 0.35 * minf(t / 0.05, 1.0))   # 落地音高下滑
			phase += TAU * f / MIX_RATE
			var x := rng.randf() * 2.0 - 1.0
			lp1 += a * (x - lp1)
			lp2 += a * (lp1 - lp2)
			buf[i] += amp * env * (0.3 * sin(phase) + 1.5 * lp2)
	# ② 沙粒颗粒：脚跟 / 脚掌各一串，泊松式触发，密度指数衰减
	for burst in [[t_heel, 1600.0, 0.035, 1.0], [t_toe, 1100.0, 0.03, 0.7]]:
		var tb: float = burst[0]
		var dens: float = burst[1]
		var dk: float = burst[2]
		var gain: float = burst[3]
		var t := tb
		while t < tb + 0.14:
			t += -log(maxf(rng.randf(), 1e-4)) / (dens * exp(-(t - tb) / dk) + 40.0)
			if t >= dur - 0.01:
				break
			var g_len := int(rng.randf_range(0.0015, 0.005) * MIX_RATE)
			var g_amp := gain * rng.randf_range(0.1, 0.32) * exp(-(t - tb) / (dk * 1.6))
			var g_f := rng.randf_range(1600.0, 4500.0)
			var i0 := int(t * MIX_RATE)
			var prev := 0.0
			for k in g_len:
				if i0 + k >= n:
					break
				var x2 := rng.randf() * 2.0 - 1.0
				var hp := x2 - prev   # 一阶差分：去掉低频，只留「沙」的脆
				prev = x2
				var ge := exp(-float(k) / (g_len * 0.35))
				buf[i0 + k] += g_amp * ge * (0.6 * hp + 0.4 * sin(TAU * g_f * k / MIX_RATE))
	# ④ 擦地「沙——」：脚跟后 60 ms 内一段带通噪声（600–2400 Hz），鞋底陷进沙里的摩擦
	var b_lo := 0.0
	var b_hi := 0.0
	var al := 1.0 - exp(-TAU * 600.0 / MIX_RATE)
	var ah := 1.0 - exp(-TAU * 2400.0 / MIX_RATE)
	var s_len := rng.randf_range(0.05, 0.08)
	for i in range(int(t_heel * MIX_RATE), mini(n, int((t_heel + s_len + 0.03) * MIX_RATE))):
		var t := float(i) / MIX_RATE - t_heel
		var env := minf(t / 0.008, 1.0) * exp(-t / (s_len * 0.45))
		var x3 := rng.randf() * 2.0 - 1.0
		b_hi += ah * (x3 - b_hi)
		b_lo += al * (b_hi - b_lo)
		buf[i] += 0.55 * env * (b_hi - b_lo)
	# 收尾：全局轻低通去刺耳 + 峰值归一到 0.5
	var peak := 0.0
	var lp := 0.0
	var a2 := 1.0 - exp(-TAU * 6500.0 / MIX_RATE)
	for i in n:
		lp += a2 * (buf[i] - lp)
		buf[i] = lp
		peak = maxf(peak, absf(lp))
	var k_norm := 0.5 / maxf(peak, 1e-4)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var fade := minf(float(n - 1 - i) / (MIX_RATE * 0.01), 1.0)   # 尾部 10 ms 收干净
		data.encode_s16(i * 2, int(clampf(buf[i] * k_norm * fade, -1.0, 1.0) * 30000.0))
	return _raw_wav(data)


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
