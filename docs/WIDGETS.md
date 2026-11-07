# DaySpark Widgets / 桌面小组件

产品规格。状态与实现进度看 `docs/ROADMAP.md`；数据契约看 `SPEC.md` §3.5。

## 原则

Widget 只做两件事：把 DaySpark 已有的高频信息放到桌面；把已有高频操作缩短一步。
不新增推荐、标签、过滤器、习惯、番茄钟等业务能力，也不维护第二套业务模型。

数据来自既有 Action 投影快照（Event / TaskAllocation / Todo），原生端只读渲染；
打勾写入独立 `widget_command_<id>` 队列，由 App 统一消费。

## 1. 今日行动 Today

| 尺寸 | 内容 |
|------|------|
| Small | 日期；下一项 Event / TaskAllocation；1 条最靠前 Todo |
| Medium | 日期；今日时间线与 Todo（按可用高度取 2–3 条）；`+ 待办` |
| Large | 日期；今日时间线与 Todo（按可用高度扩充，上限 6 / 8 条）；`+ 待办` / `+ 日程` |

交互：Todo 勾选 → 完成；Todo 文字 → Todo 详情；Event / 时间安排 → Event / Todo 详情；
`+ 待办` → 新建待办；`+ 日程` → 新建日程；空白 → Today（Action 页）。

Small 在 iOS/macOS 受系统限制只有一个整体点击目标，因此整体点击进入 Today，
勾选仍可独立触发；Medium/Large 才有逐条 deep link。

## 2. 近期安排 Upcoming

按日期分组，含今天与未来约 7 天；Event、TaskAllocation、Todo 混排。

| 尺寸 | 内容 |
|------|------|
| Medium | 今天 + 明天（空间允许时继续显示后续日期） |
| Large | 未来约 3–7 天 |

交互：Event / 时间安排 → 详情；Todo → Todo 详情；标题或空白 → Calendar。
无 Small。

## 3. 月历 Calendar

| 尺寸 | 内容 |
|------|------|
| Medium | 完整月历（4×4 起）；今日、有 Event 的日期、有截止 Todo 的日期；有日历时用日历颜色 |
| Large | 月历 + 今日摘要（Event / Todo，4×6 起） |

交互：日期 → Calendar 对应日期；Event → Event 详情；Todo → Todo 详情；
`+` → 新建 Event，默认所点日期。第一版不做 Widget 内月份切换。

## 4. 快速操作 Quick Actions

不依赖数据刷新，始终可用。

| 尺寸 | 内容 |
|------|------|
| Small | `+ 待办` / `+ 日程` |
| Medium | `+ 待办`、`+ 日程`、Today、Calendar |

## 空状态与错误状态

- App 尚未生成快照：Today / Upcoming 显示“打开 DaySpark 以显示你的安排”，点击打开 App；
  Calendar 显示正常空月历；Quick Actions 始终可用。
- 快照损坏或原生渲染异常：原生端捕获并显示同一 fallback，绝不让 launcher 显示
  “载入窗口小组件时出现问题”。
- Today 无内容：`今天没有安排` + `+ 添加待办`。
- Upcoming 无内容：`未来几天没有安排`。
- Calendar 无内容：空月历仍显示。

## 本地化

Android 的 Gallery 名称/描述走 `res/values/strings.xml` 与 `res/values-zh/strings.xml`
（系统语言）。Widget 运行期文案由快照 `ui` 块预本地化（跟随 App 内语言）。
iOS/macOS 的 Gallery 名称/描述跟随系统语言；运行期同样读快照 `ui`。

## 平台差异

- Android：按 `AppWidgetManager` 的 `OPTION_APPWIDGET_MIN/MAX_WIDTH/HEIGHT` 选择 Small/Medium/Large
  布局，并在 `onAppWidgetOptionsChanged` 重绘；不假设固定像素或固定格数。
- iOS：WidgetKit `systemSmall/systemMedium/systemLarge`；iOS 17+（AppIntents 交互）。
- macOS：WidgetKit `systemSmall/systemMedium/systemLarge`；与 iOS 共享快照与 deep link 语义。
- 不追求的差异：各平台布局不必逐像素一致，原生能力受限时按平台能力降级。
