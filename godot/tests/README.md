# 回归探针（headless SceneTree 脚本）

运行方式（在 godot/ 目录下）：

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_traffic.gd
```

退出码 0 = 通过。改动地图 / 交通 / NPC / 任务逻辑后建议全跑一遍：

| 探针 | 覆盖 |
| --- | --- |
| test_traffic.gd | 交通灯相位映射 / NPC 红灯停止线与排队 / 灯光材质联动 |
| test_raceway.gd | 赛车场高速高架查询 / 赛道与连接道路面 / 导航可达 / 赛道周长 |
| test_heist.gd | 截机任务全链路（未接不触发 → 接取 → 夺货 → 警察） |
| test_npc_cars.gd | NPC 车轮联动滚动 / 双闪状态机（灯色视觉走窗口截图） |
| test_smoke.gd | 全模式冒烟：漫游 / 步行 / 比赛 / 大战场 / 战机 / 班机（关注 stderr 无 SCRIPT ERROR） |
| test_e2e_custom.gd | 编辑器自定义赛道端到端 |
| test_map_compiler.gd | 地图编译器单测 |

注意：
- `query()` 返回共享字典引用，多次查询须 `.duplicate()` 快照后再比较。
- headless（Dummy 渲染服务器）下 MultiMesh 的 `get_instance_color/transform`
  不回读，视觉类断言请用窗口模式截图验证。
