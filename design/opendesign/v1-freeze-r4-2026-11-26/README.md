# DaySpark v1 第四轮评审包（2026-11-26）

本目录是第四轮“模型与交互最终收敛”的评审快照：**只新增文档与静态原型，不修改 Flutter，不合并 PR #113**。
本轮不重新调查竞品、不重建功能全集、不重写原型；只把计划执行、重复实例、提醒、快速添加、备份与 AI 凭据收敛到各自唯一的有效路径，并修掉 P0/P1 缺陷。

## 评审入口

| 顺序 | 文件 | 用途 |
|---|---|---|
| 1 | `DAYS_PARK_ACCEPTANCE_ROUND4.md` | 第四轮验收记录：35 条真实入口操作 + 17 项缺陷逐条结论 + 复现方式 |
| 2 | `DAYS_PARK_MODEL_CONVERGENCE.md` | 模型收敛结果：每个事实的唯一写入路径、旧路径处理、保留边界 |
| 3 | `DAYS_PARK_PRODUCT_SPEC.md` | 产品规格 v1.0 **rev.4**（分配记录为事实源、实例身份、提醒锚点、快速添加契约、备份补齐） |
| 4 | `DAYS_PARK_209_DECISIONS.md` | 209 项裁定（本轮未改范围） |
| 5 | `dayspark-prototype.html` | 单文件可交互原型，双击打开；无外部依赖 |
| 6 | `dayspark-spec.html` | 设计母版（88 屏 / 360 变体 / 39 个表面） |
| 7 | `dayspark-coverage-map.md` | 覆盖映射表 + 第四轮 17 项缺陷结论 |
| 8 | `prototype-src/` | 原型源码（15 个脚本；在本目录运行 `python3 prototype-src/build.py` 可复现产物） |
| 9 | `evidence/` | 真实 Chrome + CDP 操作脚本与输出；`backup_roundtrip.py` 走真实导出文件→清空→重载→合并 |

## 在线试用

- 原型：`https://htmlpreview.github.io/?https://raw.githubusercontent.com/liuchangchxy/dayspark/8eaae4b3/design/opendesign/v1-freeze-r4-2026-11-26/dayspark-prototype.html`
- 母版：`https://htmlpreview.github.io/?https://raw.githubusercontent.com/liuchangchxy/dayspark/8eaae4b3/design/opendesign/v1-freeze-r4-2026-11-26/dayspark-spec.html`

> 若在线预览服务不可用，下载本目录后双击 `dayspark-prototype.html` 即可，无需构建或网络。

## 这轮真正改变的产品语义

- **计划执行分配是唯一事实源**：`t.plans[]` 每段有独立 id；`t.plan` 只由 `DS3.syncProjection` 派生。新增只追加，改期/缩放/取消按 alloc id 落盘；详情编辑先草稿，保存才写入。
- **重复实例身份贯穿所有入口**：完成/撤销/安排/拖拽都必须有显式 `occurrenceDate`；列表、详情、日历、AI、手机日历不按今天/浏览日期/计划日期猜。
- **提醒锚点唯一**：只取日程开始或待办 `due + dueTime`；计划不是锚点，计划新增/改期/取消不改写提醒。新建、详情、编辑、待办、日程都支持多个提醒。
- **快速添加契约**：带时刻默认日程；纯日期只写截止；显式“另存为待办/添加待办”不写截止、计划或提醒；跨午夜结束写次日；移除时刻保留日期作为截止。
- **备份恢复补齐已有条目**：同 id 的示例/已有条目不再整体跳过，按字段补齐并合并分配、提醒、标签，同时恢复实例完成/遗漏等状态。
- **AI Key 不落盘**：真实 Key 只存页面会话变量；`P.data.ai.key` 仅掩码；快照、localStorage 与备份均无明文。

## 已知边界

- 跨设备同步、真实通知投递、原生小组件仍为**原型模拟**（既定边界，不是能力删除）。
- 旧系列单计划（`legacy:true`）拖拽被拒绝并提示先确认实例；这是有意的安全边界。
- 真实产品仍应把 AI Key 存在系统安全存储；原型只验证“不落快照/不进备份”。
- 演示数据固定为 2026-11-20。

## 构建与校验

```bash
cd design/opendesign/v1-freeze-r4-2026-11-26
python3 prototype-src/build.py /tmp/dayspark-r4
# 产物 /tmp/dayspark-r4/dayspark-prototype.html
```

- 原型 `dayspark-prototype.html` SHA-256：`5190f7a7594bb725c6ffc3a8f4c5aa4c5bd08ce7b1d71252d9c3ed8c6c24659f`
- 母版 `dayspark-spec.html` SHA-256：`87416724ae983de675b0f19295d6dc792fc0168eacb53bd1c91eacb04cedf079`
- 原型由 15 个脚本构建，产物 1,022,357 bytes（UTF-8；构建器报告 926,131 字符）。
- 评审包提交：`8eaae4b3`
