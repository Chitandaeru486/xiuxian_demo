# 山海灵境

按 s1-spec.1 实现的世界时间、状态、命令事务、事件与存档骨架。Windows / Godot 4.7.2 / Compatibility。

规格来源：D:/a_my_vibe_coding/codex_work/xiuxian_engine/v1/S1。用户于2026-10-29改为直接更新 Demo 本体：D:/a_my_vibe_coding/codex_work/xiuxian-world。更新前代码和资源另有备份；S1不是完整v1游戏。

## 启动与操作

双击 run.cmd。脚本优先使用本工程 .tools/godot 中的便携引擎，也可复用已记录的旧Demo引擎路径；没有重复复制180MB引擎。

默认启动恢复为像素游戏画面：地图、小人、人物面板、灵泉与修炼。S1调试台通过 run-debug.cmd 单独打开。二者目前运行不同的模拟世界：像素画面仍使用原Demo逻辑，S1权威核心尚未接入该画面；不能将调试台的存档当成像素游戏存档。

S1调试入口提供暂停、倍率、确认提醒继续、单步、人物选择与关注、三手动存档槽和读档确认。世界日期与实测速度来自实际模拟，不用目标倍率冒充实测。

“测试夹具模式”用于S1调度验证，需显式开启；测试提醒/突破/转移不是正式玩法，也不开放普通天道强升或操控人物权限。

本工程的等效本地存档目录为 .local_saves；测试使用独立 evidence/*_saves 目录。读档前确认放弃当前进度；覆盖需确认；关闭后不推进，不按现实离线时长补算。

## 验证

源代码和测试分别在 core/、ui/、tests/。在本目录 PowerShell 7 中运行：

```powershell
.\verify.ps1 -IncludeGui
```

若引擎不在旧Demo目录，可加 `-Godot '完整路径/Godot_v4.7.2-stable_win64_console.exe'`。不加 `-IncludeGui` 仅运行无窗口测试，不把 AC23 标为通过。运行会重建独立测试存档并更新 evidence/summary.json、各场景 JSON、日志和截图；不操作 .local_saves 中的游玩存档。

实际执行结果、限制与验收编号见 evidence/summary.json、[评审记录](../xiuxian_engine/v1/s1_final/review.md) 和 [交付报告](../xiuxian_engine/v1/s1_final/final_report.md)。summary 中保存本次受测源码 SHA-256，改代码后应重跑。尚未运行的场景不能视为通过。

保存成功覆盖槽位后，上一份有效存档保留为同目录 `manual_1.json.backup`（其他槽同理）。主档损坏会明确拒绝，不自动隐藏错误。需要人工恢复时，先退出游戏，另存损坏主档，再复制对应 `.backup` 为原 `.json` 文件名，重新读取。

候选配置仍标为 candidate，不将纸面概率/经济/突破夹具称为完整玩法。S1的192×192是逻辑边界；不以此宣称地图、美术、300人完整AI或百年经济已经完成。


S1 设计、计划、评审和交付报告统一存放于 [s1_final](../xiuxian_engine/v1/s1_final/README.md)，与 S1 规格目录平级。
