class_name Tuning
## 操控调参默认值（移植自 js/tuning.js；Godot 版暂不含调参面板，读默认值）

const STEER_MAX := 0.52            # 低速打满转向角（rad）
const STEER_FALLOFF_STR := 1.35    # 高速转向衰减强度：偏强，高速过弯更早推头、更稳重
const STEER_FALLOFF_SPEED := 23.0  # 衰减参考车速（m/s）
const STEER_FALLOFF_POW := 1.6     # 衰减曲线指数
const STEER_RATE := 3.8            # 方向盘打轮速度：偏慢，模拟真实打轮力度
const YAW_RESPONSE := 5.0          # 车头跟随转向的速度：偏慢，车身有重量感
const GRIP_MUL := 1.0              # 整体抓地力倍率
const GRIP_RATE := 7.0             # 侧向抓地（漂移中的打滑回收速度）
const DRIFT_THRESH := 2.0          # 起漂阈值 (m/s)：未达阈值速度矢量吸附车头（转弯零侧滑）
