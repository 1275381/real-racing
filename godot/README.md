# 极速争锋 REAL RACING — Godot 版

网页版（`../` 目录，Three.js）的 **Godot 4.7 原生移植版**。赛道控制点、车辆物理、AI
策略逐行对应移植，5 款 Blender 建模的 GLB 车模直接复用，全部纹理/音效仍由代码程序化生成。

## 运行方式

1. 安装 [Godot 4.7](https://godotengine.org)（本机已有：`D:\Godot\Godot_v4.7-stable_win64.exe`）。
2. 打开 Godot → **Import** → 选择本目录的 `project.godot`。
3. 按 **F5** 运行。

## 玩法流程：车库 → 比赛 / 自由漫游

游戏开局直接进入 **3D 车库**：

- 红色爱车停在旋转展台上，**按住鼠标左键拖动**可旋转展台环视车辆
- 底部 **◀ / ▶** 切换 5 款车型（GT3 战驹 / 原型超跑 / 方程式 / 肌肉房车 / 拉力战车）
- 右侧 **「选择比赛」面板**：选赛道（7 条）、圈数（2/3/5）、AI 强度（轻松/标准/硬核），
  面板会显示赛道简介与本作最快圈纪录
- 点 **「开始比赛」**（或按 Enter）离开车库，发车网格开赛
- 点 **「自由漫游」** 进入大地图城市，不比赛、不计时，想去哪就去哪；
  比赛后暂停菜单 / 结算页的「回到车库」可返回车库

## 自由漫游（开放城市）

- **约 2.4km × 2.4km 的城市**：11×11 密集网格街道（约 120 个十字路口）、
  内圈高楼群（约 800 栋楼宇）、中心广场
- **可驾驶高架系统**：高架环线（10m）+ 东西/南北两条高架快速路（14m，与环线立交）+
  8 条弯曲匝道——沿匝道爬升、桥面巡航、护栏防侧翻
- **立体车辆物理**：重力 / 垂直速度 / 接地-腾空状态；爬坡减速、下坡加速，
  高速冲过坡顶会腾空飞跃，落地有震动与闷响；腾空时无驱动无抓地
- **极速约 300km/h**：8 前速变速箱（带换挡回差，修复了换挡切断在档位边界振荡
  导致极速被锁死的问题）
- **路口细节**：主要路口红绿灯（红黄绿循环）、斑马线、路缘人行道
- 漫游 HUD：转速表 + 整张路网小地图（高架高亮）+ 操作提示
- **Esc** 回车库，**R** 复位到最近道路，地图边界 ±1250m 软限位

命令行直接运行（免开编辑器）：

```bat
"D:\Godot\Godot_v4.7-stable_win64_console.exe" --path "D:\赛场游戏\godot"
```

调试参数（追加在 `--` 之后，等价网页版 URL 参数）：

```bat
... --path "D:\赛场游戏\godot" -- --autostart --laps=1 --track=circuit
```

- `--autostart` 自动开赛；`--laps=N` 指定圈数；`--track=<id>` 指定赛道
  （circuit / bay / serpent / horizon / city / hairpin / canyon）
- 环境变量 `RR_DEBUG=1` 每秒打印一次各车状态（headless 验证用）
- headless 冒烟测试：`... --headless --path . --quit-after 1200 -- --autostart`

## 已移植内容

| 模块 | 说明 | 对应网页版 |
| --- | --- | --- |
| 赛道生成 | 闭式 Catmull-Rom（张力 0.55）→ 弧长均匀采样 → 路面/砂石路肩/红白 curb/护栏/龙门架信号灯/看台/发车格，7 条赛道长度与网页版一致 | `js/track.js` |
| 车辆物理 | 前向/侧向速度分离、运动学转向+漂移辅助、路面摩擦分级（柏油/路肩/草地）、软墙反弹、7 前速自动变速箱，固定 120Hz 步长 | `js/physics.js` |
| AI 车手 | 前瞻追踪走线、按前方曲率规划刹车、超车避让变线、卡死自救、橡皮筋平衡、完赛巡航 | `js/opponents.js` |
| 车模 | 直接加载 `assets/cars/car_*.glb`（Blender 命名契约 HubXX/WheelXX/BodyPivot，Paint/Accent/TailLight 材质染色，刹车灯增亮）；GLB 缺失自动回退程序化车型 | `js/car.js` |
| 竞速编排 | 菜单→倒计时（3 盏红灯+哔声）→比赛→完赛结算状态机；圈速/最快圈纪录、实时排位、逆行警告、车对车碰撞冲量、R 键救援 | `js/game.js` |
| HUD | 自绘转速表（速度/档位/名次/漂移指示）、小地图、计时面板、排位榜、圈速提示、结算表 | `js/hud.js` |
| 环境 | 天空穹顶着色器（含太阳）、平行光阴影跟随玩家、深度雾、三种主题（草地/城市/沙漠）自动切换树木/楼宇/仙人掌红岩/远山/云 | `js/environment.js` |
| 特效 | 持久胎痕（环形缓冲）、漂移烟雾、离地尘土、碰撞火花 | `js/effects.js` |
| 音频 | AudioStreamGenerator 实时合成引擎声（锯齿+方波→软削波→低通，转速驱动音高）、轮胎啸叫/风噪/路肩隆隆（滤波噪声总线）、碰撞闷响、倒计时哔声 | `js/audio.js` |
| 存档 | 赛道/车型/圈数/难度/历史最快圈，存 `user://rr_settings.cfg` | localStorage |

## 按键

与网页版一致：W/↑ 油门，S/↓ 刹车·倒车，A D/← → 转向，空格 手刹漂移，
C 切换镜头（追尾远/近/车头盖），R 回到赛道，P/Esc 暂停，M 静音，Enter 菜单开赛。

## 与网页版的差异

- 渲染器使用 Compatibility（OpenGL）以保证低配机与后续网页导出的兼容性；色调映射 ACES 对齐网页版。
- 操控调参面板（网页版 T 键）未移植，物理参数取默认值（`scripts/tuning.gd`）。
- 网页版的调参 URL 参数（`?debug=1` 等）对应为命令行参数，仅保留 autostart/laps/track。
- 触屏虚拟按键未移植（桌面端游玩）。

## 调试参数（-- 之后传参）

- `--autostart` 自动开赛；`--laps=N` 指定圈数；`--track=<id>` 指定赛道；`--roam` 直接进漫游
- 环境变量 `RR_DEBUG=1` 每秒打印各车状态；`ROAM_SPAWN=x,z,heading` 指定漫游出生点
- headless 冒烟：`... --headless --path . --quit-after 1200 -- --autostart`
- 漫游地图/物理探针：`Godot --headless --path . -s res://tools/probe_roam.gd`

## 目录结构

```
godot/
├── project.godot          工程配置（主场景/兼容渲染器/1440×810）
├── scenes/main.tscn       唯一场景（根节点挂 game.gd，其余全部代码构建）
├── assets/cars/*.glb      复用网页版 Blender 车模（5 款）
├── scripts/
│   ├── game.gd            主编排：车库/漫游/状态机/定步物理/相机/碰撞/存档
│   ├── garage.gd          3D 车库：展厅/旋转展台/顶灯/车漆反射
│   ├── freeroam_map.gd    漫游大地图：路网采样/立交高架/匝道/红绿灯/楼宇/查询
│   ├── track_data.gd      赛道控制点、车队、车型、难度数据
│   ├── race_track.gd      程序化赛道生成 + 空间网格 + 位置查询
│   ├── vehicle.gd         车辆动力学（平面操控 + 垂直重力/腾空落地）
│   ├── ai_driver.gd       AI 车手（比赛模式）
│   ├── car_visual.gd      GLB 车模加载/染色/车轮动画 + 程序化回退
│   ├── environment.gd     天空/光照/地面/植被/楼宇/沙漠道具/云
│   ├── effects.gd         胎痕/烟雾/尘土/火花
│   ├── engine_audio.gd    程序化合成音效
│   ├── hud.gd             HUD 与车库 UI（自绘转速表/小地图双模式）
│   ├── textures.gd        程序化纹理（沥青/草地/水泥/沙地/观众/斑马线/云…）
│   ├── tuning.gd          操控参数默认值
│   ├── ui_font.gd         系统中文字体（微软雅黑）
│   └── util.gd            数学/格式化/确定性随机
└── tools/                 headless 探针（赛道几何/网格/纹理/漫游物理自检）
```

## 开发自检

```bat
:: 赛道几何（长度应与 README 吻合）
Godot --headless --path . -s res://tools/probe_track.gd
:: 网格完整性
Godot --headless --path . -s res://tools/probe_mesh.gd
:: 渲染帧检查（生成 PNG 序列）
Godot --path . --write-movie %TEMP%\rr.png --quit-after 400 -- --autostart
```
