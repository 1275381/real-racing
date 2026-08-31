# 🏁 极速争锋 REAL RACING

真实风格的 3D 赛车竞速游戏。纯浏览器运行，零外部资源——赛道、车辆、纹理、音效全部由代码程序化生成。

![tech](https://img.shields.io/badge/Three.js-r160-blue) ![lang](https://img.shields.io/badge/%E7%95%8C%E9%9D%A2-%E4%B8%AD%E6%96%87-orange)

> 🎮 本游戏已移植为 **Godot 4.7 原生版本**（[godot/](godot/) 目录），复用同一套赛道数据与 GLB 车模，详见 [godot/README.md](godot/README.md)。

## 启动方式

**方式一（推荐，macOS）：** 双击 `启动游戏.command`，会自动起本地服务并打开浏览器。

**方式一（推荐，Windows）：** 双击 `启动游戏.bat`，同样自动起本地服务并打开浏览器。零依赖（不需要安装 Python / Node），关掉窗口即停止服务；端口被占用时会自动换下一个端口。

**方式二：** 在本目录执行：

```bash
python3 -m http.server 8017
```

Windows（无 Python 时）：

```powershell
powershell -ExecutionPolicy Bypass -File start-game.ps1 8017
```

然后浏览器打开 <http://localhost:8017/index.html>

> ⚠️ 必须通过 http:// 访问。直接双击 index.html（file://）会因 ES Module 的跨域限制无法加载。

## 玩法

- **7 条风格赛道**：
  - 极速环道（1.76km 技术型 · 回头发夹扇区）
  - 海湾冲刺（1.38km 高速流畅 · 长直道）
  - 蛇形峡谷（1.14km 连续 S 弯）
  - 地平线耐力（1.44km 碗型高速 · 沙漠主题）
  - **都市街区**（0.9km · 90°直角弯 · 摩天楼间穿行 · 城市主题）
  - **绝壁发夹**（1.7km · 三层叠弯双发夹 · 刹车点地狱）
  - **赤色荒漠**（1.24km · 沙地/红岩/仙人掌 · 沙漠主题）
  - 每条赛道有独立的环境主题：天空雾色、地面材质（草地/水泥/沙地）、场景道具（树木/楼宇/仙人掌红岩）自动切换
- 4 车对决：你驾驶红色「烈焰」从 P4 发车，与海鲨（原型超跑）/ 雪鹰（方程式）/ 雷霆（肌肉房车）三支 AI 车队争夺冠军
- **5 款车型可选**：GT3 战驹 / 原型超跑 / 方程式 / 肌肉房车 / 拉力战车，主菜单实时切换（造型不同，性能一致）
- 按圈数比赛（2/3/5 圈可选），AI 强度三档可调
- 支持漂移手刹、逆行警告、最快圈纪录自动保存（localStorage）
- 新赛道设计约束：控制点放 `js/trackConfig.js` 的 `TRACKS`（带 `theme` 字段），非相邻路段中心线间距须 >24m，用 `node tools/checkTrack.mjs` 与 `node tools/checkStart.mjs` 校验布局与发车区

### 键位

| 按键 | 功能 |
| --- | --- |
| W / ↑ | 油门 |
| S / ↓ | 刹车 · 倒车 |
| A D / ← → | 转向 |
| Space | 手刹（漂移） |
| C | 切换镜头（追尾远 / 近 / 车头盖） |
| R | 回到赛道中央 |
| T | 操控调参面板（实时滑杆，自动保存） |
| P / Esc | 暂停 |
| M | 静音 |

手机等触屏设备会自动显示虚拟按键。

## 调试参数（可选）

在 URL 后追加查询串可启用隐藏功能，如 `index.html?debug=1&autodrive=1&laps=1`：

- `debug=1` — 左上角显示物理/输入实时读数
- `autodrive=1` — 玩家车由 AI 代驾（演示用）
- `laps=N` — 指定比赛圈数（1~20，可绕过菜单选项）
- `track=id` — 指定赛道（circuit / bay / serpent / horizon / city / hairpin / canyon）
- `car=id` — 指定玩家车型（gt3 / hyper / formula / muscle / rally）
- `panel=1` — 默认展开调参面板
- `autostart=1` — 自动开始比赛

改代码调试时建议用无缓存服务器：`python3 tools/serveDev.py 8044`（Windows 无 Python 时用 `powershell -ExecutionPolicy Bypass -File start-game.ps1 8044`，同样禁缓存）。改动物理后可运行回归测试：`node tools/testReverse.mjs`；改动赛道布局后运行 `node tools/checkTrack.mjs` 和 `node tools/checkStart.mjs`。

## 车辆建模（Blender 管线）

**5 款赛车全部由 Blender 程序化建模**，共用 `tools/blender/carlib.py` 这套建模库，
每款车一个规格文件 `tools/blender/specs/<id>.py`，导出 `assets/car_<id>.glb`（各约 2.3~2.5 万面）：

| id | 车型 | 特征 |
| --- | --- | --- |
| `gt3` | GT3 战驹 | 宽体包覆、鹅颈尾翼、前定风翼、侧出排气 |
| `hyper` | 原型超跑 | 极低重心、水滴座舱、鲨鱼鳍、双层尾翼 |
| `formula` | 方程式 | 开轮单体壳、Halo 保护环、多层前后翼、暴露双叉臂 |
| `muscle` | 肌肉房车 | 方正宽体、机械增压进气罩、刀片尾翼、四联侧排气 |
| `rally` | 拉力战车 | 高底盘两厢、前杠四射灯、车顶导风口、大尾翼 |

重新生成（不带参数=全部车型）：

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/buildCar.py
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/buildCar.py -- --spec=gt3 --views=tail,hero
```

`--spec=a,b` 只建指定车型；`--render` / `--views=...` 顺带用 Cycles 渲染 `assets/preview_<id>_<视角>.png`，
视角可选 `hero`（3/4 前）`tail`（正后特写，玩家实际视角）`tailq` `rear` `side` `front` `top`。
导出后脚本会解析 GLB 的 JSON 块自校验节点名/材质名（缺失或出现 `.001` 重名副本直接报错）。

**建模方式**（相比早期版本的真实度提升）：

- 车身是一张连续曲面：截面参数（车底宽/腰线/顶沿高…）沿车长做 Catmull-Rom 插值，座舱由同一张皮长出来，不再是扣在车顶上的独立玻璃罩
- 车窗、进气口、大灯是在这张皮上「开洞」——先做成闭合体用布尔切轮拱，再按面遮罩挖开口，补一层向内偏移的内衬 **+ 一圈凹陷侧壁**，洞口边缘天然形成 A/B/C 柱与灯腔包边（没有侧壁的话，从斜角会顺着缝隙看进车壳内部）
- 车头鼻尖 / 车尾端面单独上碳纤材质（`cap_mats`）；`build_shell` 里有回归哨兵断言端面没被开口遮罩误删——否则车前后会透空
- 轮胎/轮辋/刹车盘/卡钳由二维断面绕轴放样：有胎肩圆角、胎壁鼓包、轮辋唇口与桶身、钻孔通风盘、抱住刹车盘的卡钳，辐条真实连接轮毂与桶身
- 空力件按翼型断面放样（含 Gurney 襟翼），不是拍扁的方盒子
- **车尾单独下了功夫**（`carlib.tail_kit`）：玩家全程只看得到车尾，所以按量产跑车的层次做——
  鸭尾压线 → 嵌在暗色带里的贯穿式灯带（并绕到两侧翼子板）→ 车漆面板 + 车标/雨雾灯 →
  牌照凹槽 + 两侧网格出气 → 凸出车身的暗色下包围（中空管口的四出排气 + 反光片）→ 带竖鳍的扩散器。
  五款车各有各的灯语：GT3/原型车贯穿灯带、肌肉车六段式整面尾灯、拉力车立式双灯、方程式雨雾灯 + 尾翼端板示宽灯。
  这些件全用 `TailLight` 材质，刹车时一起变亮

**命名契约**（游戏端 `js/car.js` 依赖，改模型时不可破坏）：

- 空物体 `HubFL/FR/RL/RR` → 前轮转向枢轴；子物体 `WheelXX` → 滚动自转；`CaliperXX` 不随转
- 空物体 `BodyPivot` → 车身姿态容器（侧倾/俯仰/悬架起伏）
- 材质 `Paint`（运行时染车队主色）、`Accent`（染副色/拉花）、`TailLight`（刹车灯发光强度动画）、`HeadLight`
- 几何硬约束：轮心 X=±0.84、前轴 Y=-1.46、后轴 Y=+1.44、轮胎半径 0.34（`js/game.js` 用 `vf/0.34` 算轮速）、轮心高=半径。
  五款车只在造型上不同，尺寸与物理完全一致

车型清单在 `js/carModels.js`（id 必须与 spec 文件名、glb 文件名一致）。玩家车型在主菜单「座驾车型」里选，
存 localStorage；AI 三台车各开一款（`js/trackConfig.js` 的 `TEAM_ROSTER.model`）。
若 glb 全部缺失，游戏自动回退到内置程序化方块车型。

## 技术要点

- **Three.js r160** 渲染：ACES 电影色调映射、PCF 软阴影、PMREM 环境反射（车漆金属质感）
- **程序化赛道**：闭合 Catmull-Rom 样条 → 弧长均匀采样 → 沥青路面（含标线纹理）、红白路肩、双层护栏、龙门信号架、观众看台、发车格
- **车辆物理**：前向/侧向速度分离、运动学转向 + 漂移辅助混合、路面摩擦分级（柏油/路肩/草地）、软墙反弹、7 前速自动变速箱带换挡切油
- **AI 车手**：前瞻追踪走线、按前方曲率规划刹车点、超车避让变线、卡死自救、轻度橡皮筋平衡
- **特效**：持久胎痕环缓冲、轮胎烟雾 / 草地尘土 / 碰撞火花粒子系统
- **音频**：WebAudio 全合成引擎声（双振荡器 + 波形整形 + 转速驱动）、胎叫、风噪、碰撞
- **HUD**：Canvas 绘制转速表、实时小地图、排位榜、单圈计时面板

## 目录结构

```
赛场游戏/
├── index.html            入口页面
├── 启动游戏.command       macOS 双击启动脚本
├── 启动游戏.bat           Windows 双击启动脚本（调用 start-game.ps1）
├── start-game.ps1         Windows 本地服务（PowerShell 零依赖，禁缓存）
├── assets/car_*.glb      Blender 建模的 5 款车辆模型
├── css/style.css         HUD 与菜单样式
├── js/
│   ├── main.js           渲染器与主循环
│   ├── game.js           状态机 / 相机 / 竞速编排
│   ├── track.js          赛道几何生成
│   ├── trackConfig.js    赛道控制点与车队配置
│   ├── physics.js        车辆动力学
│   ├── car.js            车模加载/实例化（GLB 优先，回退程序化）
│   ├── carModels.js      车型清单
│   ├── opponents.js      AI 车手
│   ├── effects.js        胎痕与粒子特效
│   ├── hud.js            仪表盘 / 小地图 / 结算
│   ├── audio.js          引擎音效合成
│   ├── input.js          键鼠 + 触屏输入
│   ├── textures.js       程序化纹理
│   └── environment.js    天空光照地形植被
├── lib/three.module.js   Three.js 本地副本（离线可玩）
├── tools/                自检与测试脚本
│   ├── blender/carlib.py    Blender 建模共享库
│   ├── blender/specs/*.py   5 款车型规格
│   ├── blender/buildCar.py  建模总入口
│   ├── checkTrack.mjs    赛道布局自检（重叠/长度）
│   ├── testReverse.mjs   物理回归测试（倒车转前进/刹车/长按倒车）
│   ├── probeGrid.mjs     发车格数据探针
│   └── serveDev.py       开发用无缓存服务器
```
