# DaySpark v1 第二轮评审包（2026-11-26）

本目录是第二轮验收的评审快照：**只新增文档与静态原型，不修改 Flutter 代码，不合并 PR #113**。

## 评审入口

| 顺序 | 文件 | 用途 |
|---|---|---|
| 1 | `DAYS_PARK_ACCEPTANCE_ROUND2.md` | 第二轮验收记录：上轮 9 个确认缺陷逐条处理 + 实测结果；规格/裁定冲突的处理 |
| 2 | `DAYS_PARK_PRODUCT_SPEC.md` | 产品规格 v1.0（已修订冲突：计划执行、重复范围、手机导航、长按、原型 vs 正式产品边界） |
| 3 | `DAYS_PARK_209_DECISIONS.md` | 209 项逐项裁定（已同步第 3 / 27 / 178 / 182 项口径） |
| 4 | `dayspark-prototype.html` | 单文件可交互原型，双击打开，无外部依赖、无需构建 |
| 5 | `dayspark-spec.html` | 设计母版：88 屏 / 360 变体 |
| 6 | `dayspark-coverage-map.md` | 覆盖映射表（已按 13 个功能域 + 14 条场景重建第 0 节验收口径） |
| 7 | `prototype-src/` | 原型源码（可在本目录直接运行 `python3 prototype-src/build.py` 复现产物） |

在线试用：

- 原型 <https://raw.githack.com/liuchangchxy/dayspark/design/v1-freeze-r2-2026-11-26/design/opendesign/v1-freeze-r2-2026-11-26/dayspark-prototype.html>
- 母版 <https://raw.githack.com/liuchangchxy/dayspark/design/v1-freeze-r2-2026-11-26/design/opendesign/v1-freeze-r2-2026-11-26/dayspark-spec.html>

## 这轮改了什么（只修质量，不扩功能）

- 重复规则按**真实发生次数**计数；“每周一、三、五 + 10 次”第 10 次是 12/09。
- 重复条目删除三档真正分工：仅这一次只跳过该日期；这一次及以后从该实例截断、之前保留；整个系列全删。
- 回收站恢复用快照整对象还原（日历/标签/优先级/备注/子任务/计划），并清掉跳过记录；无快照时先说明会退化为纯标题。
- 导入写入 `DTEND` 与跨天 `startDate/endDate`，解析 `RRULE`（含 `UNTIL`/`COUNT`）；跳过行不再清空错误记录，报告保留原始行与原因。
- AI 安时间 / 拆子任务不再固定改某条待办：目标从对话里匹配真实待办，写入前可改，确认后才落库。
- 产品页不再有未接线控件被包装成“只读事实”；设计样张页点击会明确说明“这是设计样张”。
- 手机长按打开与桌面右键相同的菜单；行本身仍可点开详情。

## 已知边界

- AI、登录、同步、设备、冲突、通知、权限在原型里是**本地模拟**；正式产品按现有后端实现（规格已明确这一点）。
- 导入/导出/备份走真实 File API 与本地解析，但不上传文件；附件只记录文件名/大小。
- 演示数据固定为 2026-11-20。
- 少量捕获弹层里的精细时间仍使用系统时间控件；详情与计划选择器已用设计选择器。
- 批量选择、手动排序、设置内搜索、重复待办逐实例状态按裁定留在 v1 之外。

## 校验

- 原型 `dayspark-prototype.html` SHA-256：`c29bd2c31cb1d35c5fa8027fbdf1c2efea1b9dc83dde87db13d076eed498c4fd`
- 母版 `dayspark-spec.html` SHA-256：`672e7f35fbdd49c61e4ee148b1a619a8400a5189f9a9b67cf2c0b7313912cbdc`
- 母版：88 屏 / 360 变体
