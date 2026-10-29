# 山海灵境 · 观世

Windows 像素修仙沙盒的第二轮原型：点化灵泉，观察 30 位行者自主选择修炼之地。

## 启动

双击项目根目录的 `run.cmd`。本地已准备便携 Godot，正常启动不需要安装到系统。

如需从其他目录重建运行环境：从 Godot 官方下载归档获取 `Godot_v4.7.2-stable_win64.exe.zip`，解压到 `.tools/godot/`，在该目录新建名为 `_sc_` 的空文件以启用便携数据目录，再运行 `run.cmd`。锁定版本为 Godot 4.7.2 stable，Compatibility 渲染。

官方来源：https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable

## 操作

| 操作 | 功能 |
| --- | --- |
| Q 或左上“布灵泉” | 进入放置模式，左键点击陆地放置；右键或 Esc 取消 |
| H 或“灵气视图” | 查看实际灵气覆盖范围 |
| 左键点选小人 | 查看姓名、年龄、灵根、资质、出身与当前行为 |
| 按住左/中/右键拖动 | 平移地图；拖动不会误选人物 |
| 鼠标滚轮或工具栏 ± | 缩放 |
| 方向键 | 移动镜头 |
| 空格 | 暂停 / 继续 |
| 1 / 2 / 4 | 时间流速 |
| F 或“跟随此人” | 镜头跟随 / 取消跟随 |
| Home 或“村落” | 回到青禾村 |
| 点击侧栏同行者 | 切换观察对象 |
| 点击小地图 | 定位世界 |
| F12 | 保存运行截图到 evidence/ |
| Esc | 取消布泉、关闭帮助、退出跟随 |

## 本轮边界

首次启动没有灵泉。按 Q，在村落附近的空地放一处灵泉，再按 Esc 返回观察模式。附近有灵根的人会前往可达的位置打坐；点击人物查看修为、吸纳速率和选择原因。可用 4× 加快观察。

灵泉最多六处，水域、山地和重复位置不能放置。无灵根者继续漫游；资质影响修炼速度。修为上限 100，暂不自动突破。仍未实现战斗、存档或附身。

地图与模拟使用固定种子 `20261027`。游戏重启会重建初始世界。

## 源码

- `scripts/world_sim.gd`：不依赖场景的世界数据与模拟。
- `scripts/world_view.gd`：TileMapLayer、装饰、像素小人与选择提示。
- `scripts/main.gd`：镜头、输入、人物面板、时间控制、小地图。
- `tools/generate_assets.py`：使用 Pillow 生成全部原创像素素材。
- `tests/test_world.gd`：模拟不变量与可复现性检查。

## 开发验证

在项目目录用 PowerShell 运行：

```powershell
$engine = '.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --editor --import --quit
& $engine --headless --path . --log-file evidence/simulation.log --script res://tests/test_world.gd
& $engine --path . --log-file evidence/gui-smoke.log -- --smoke-test --capture
& $engine --headless --path . --log-file evidence/cultivation-tests.log --script res://tests/test_cultivation.gd
& $engine --path . --log-file evidence/cultivation-ui.log -- --cultivation-test --capture --capture-path=res://evidence/cultivation-loop.png
```

第三条会开启真实图形窗口，将键盘与鼠标事件送入实际输入路径，检查暂停/恢复/地图点选/拖动/跟随/滚轮/倍速按钮，并输出游戏实际截图到 `evidence/first-playable.png`。它不替代人工试玩与视觉判断。实际执行结果见 `notes.md`。

素材可用 `python tools/generate_assets.py` 重新生成。运行游戏无需 Python。

## 后续

灵泉到修为增长的闭环已打通。后续可以围绕突破条件与资源竞争迭代。完整规划见 `design.md`，协作流程见 `WORKFLOW.md`。
