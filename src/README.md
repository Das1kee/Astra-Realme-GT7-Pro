# Astra Beta0.1.06

为 Realme GT7 Pro（RMX5010）定制的模块：温控 · 电池 · 调度。

- 打开：SukiSU → 模块 → Astra → 打开
- 日志：`/data/adb/Astra/logs/astra.log`
- 报告：WebUI → 设置 → 生成 debug 报告（同时复制到 `/sdcard/Astra/`）
- 游戏名单：`/data/adb/Astra/settings/games.list`（每行一个包名）
- 卸载：管理器删除模块并重启，自动还原全部设置

三种温控模式互斥：官方（默认，零干预）/ 去温控 / 伪装温度。
伪装温度默认不改变 Scene 看到的电池温度（Scene 显示真实值）。
