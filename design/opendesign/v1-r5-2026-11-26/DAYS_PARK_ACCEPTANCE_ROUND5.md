# DaySpark R5 · UI/UX 验收记录

> 日期：2026-11-26  
> 基线：PR #117 / `cad5686a` / 第四轮产物 `65fdf776`  
> 本轮产物：R5 设计母版 + 单文件可交互原型  
> 验收方式：真实 Chrome（headless CDP）打开构建产物，按真实入口点击、勾选、拖动、切换设备与主题；截图只作证据，不以屏数/测试数/接线率代替体验。

---

## 1. 真实操作结果

| # | 操作 | 结果 |
|---|---|---|
| 1 | 桌面 Today 读取 | `todayStats = {done:2,total:7,planned:1,due:2,overdue:3,unplanned:5}`；显示“2/7 已完成 · 1 段安排 · 3 逾期 · 5 无日期” |
| 2 | 同一待办追加第二段安排 | `planned` 1 → 2；`timeBlocks` 中 `report` 出现 `alloc-3`、`alloc-2` 两个计划块 |
| 3 | 完成普通待办「提交周报给林总」 | 统计 2/7 → 3/7；Today 不再显示该计划；Calendar 历史行出现“提交周报给林总 · 15:15 已失效”，`.history-chip` 数量 1 |
| 4 | 完成重复实例 | `DS3.isInstanceDone(recurring, TODAY)=true`；`isDone(series)=false`；统计 3/7 → 4/7 |
| 5 | 旧版重复计划 | 今日锚点 1 个块，未来 7 天 0 个块；Calendar 顶部横幅“1 个旧版重复计划待确认” |
| 6 | 手机截止列表展开 | 默认 3 项；点击“还有 N 项 · 查看全部”后任务行 11 → 14；按钮 `aria-expanded=true` |
| 7 | 手机中央添加 | 五格 Dock：今天 / 待办 / 添加 / 日历 / 我的；点击添加进入 `screen=capture`，出现解析 sheet |
| 8 | 小组件勾选 | 点击小组件勾选写回主应用；`todoById('report')` 完成状态更新 |
| 9 | MCP 服务开关 | 点击后 `state.mcpEnabled=false`，页面显示“服务已暂停”，toast 出现 |
| 10 | MCP 写入范围 | 点击“写入”收回/授予权限；`state.mcpWrite` 更新；撤销按钮存在 |
| 11 | 快速添加四类输入 | 带时刻→日程；另存为待办→无截止/计划/提醒；纯日期→只写截止；跨午夜→结束在次日 |
| 12 | 备份真实文件合并 | 导出→清空→重载→文件选择合并；多计划、提醒、实例完成/遗漏、标签、localTodos 恢复；快照/localStorage 无明文 AI Key |
| 13 | AI Key | 设置保存后 `P.data.ai.key` 为 `sk-••••3456`；快照与 localStorage 无明文 |
| 14 | 旧版重复迁移 | 取消不改写原规则；确认时区/锚点/规则后写入 `每周五`、`2026-11-06`、`Asia/Shanghai` |

第四轮回归子集：`d1_check`、`d2_check`、`d3_check`、`d5_check`、`qa_force`、`backup_roundtrip`、`ai_probe`、`legacy_ui` 均通过。未重跑第四轮完整 36 条；本轮改动集中在视觉层与 Today/Calendar 读模型，D1–D5 与数据路径已重跑。

---

## 2. 截图索引

目录：`evidence-r5/`

| 文件 | 说明 |
|---|---|
| `desktop-today.png` | 1440×1000，浅色 Today |
| `desktop-todos.png` | 1440×1000，Todos |
| `desktop-calendar.png` | 1440×1000，Calendar 周 |
| `desktop-calendar-history.png` | 完成普通待办后的「历史」行 |
| `desktop-calendar-legacy.png` | 旧版重复计划待确认横幅 |
| `desktop-settings-home.png` | 设置首页：六个任务型入口 |
| `desktop-settings.png` | 设置：账户与同步 |
| `desktop-mcp.png` | 设置：MCP 连接 |
| `desktop-widgets.png` | 小组件实时画廊 |
| `mobile-today.png` | 390×844，Today |
| `mobile-deadline-expanded.png` / `-2.png` | 手机截止列表展开前/后 |
| `mobile-todos.png` | 390×844，Todos |
| `mobile-calendar.png` | 390×844，Calendar 日 |
| `mobile-settings.png` | 390×844，设置六组 |
| `mobile-mcp.png` | 390×844，MCP |
| `tablet-today.png` / `tablet-calendar.png` | 1024×768 平板 |
| `dark-today.png` / `dark-calendar.png` / `dark-settings.png` | 深色主题 |
| `warm-today.png` | 暖灰主题 |
| `before-after-desktop.png` / `before-after-mobile.png` | 第四轮基线 vs R5 |

---

## 3. 视觉检查

- 产品文字 12px 下限；手机正文与输入 16px。
- 桌面 40px 页边距；手机 20px；任务行桌面 56 / 手机 64；触控目标 ≥48。
- 1440 / 1024 / 390 无横向溢出；手机底部内容留 108px，不被五格 Dock 遮挡。
- 浅色 / 暖灰 / 深色覆盖 Today、Todos、Calendar、Settings、MCP。
- 首屏仅保留低存在感「预览」胶囊，不再显示七按钮调试条。
- 手机无悬浮 FAB；中央添加不遮挡列表。
- 设置首页按六个任务入口重排：账户与同步 / 外观与日历 / 提醒与通知 / 数据与备份 / AI 与自动化 / 关于与诊断；页面头不再与旧八行列表混排。
- 日历「历史」行与 08:00 轴标签分离，历史安排不再压住时间轴；已完成 / 已失效 / 已取消用文字状态区分，不只靠颜色。

---

## 4. 已知边界

- MCP 连接、OAuth、通知投递、原生小组件仍为原型模拟；不实现真实服务端。
- 平板验收通过 1024×768 视口；未提供独立平板设备按钮，浏览器缩放窗口即可。
- `repeat_detail_done.py` 的旧断言期待“撤销时再次出现实例选择器”；当前行为是直接撤销已绑定实例，功能正确，旧断言未更新。
- 第四轮完整 36 条未全部重跑；本轮只重跑与改动相关的 8 组脚本与 R5 专项探针。
