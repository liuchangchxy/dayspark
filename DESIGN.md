# DESIGN.md — Calendar Todo App Design System

AI 编码工具读此文件来保持 UI 一致性。

## Design Philosophy

功能导向的极简设计。参考标杆：Linear（克制用色）、Apple 日历（清晰实用）。
**拒绝"AI 味"：** 不大圆角、不渐变、信息密度优先。

## Colors

### Light Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #FAFAFA | 页面背景 |
| surface | #FFFFFF | 卡片/弹窗背景 |
| textPrimary | #1A1A2E | 主文字 |
| textSecondary | #6B7280 | 辅助文字 |
| accent | #2563EB | 按钮、选中态、链接 |
| accentHover | #1D4ED8 | 按钮悬停 |
| success | #16A34A | 成功状态 |
| warning | #EAB308 | 警告状态 |
| error | #DC2626 | 错误状态 |
| border | #E5E7EB | 边框、分割线 |

### Dark Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #0F0F14 | 页面背景 |
| surface | #1A1A2E | 卡片/弹窗背景、输入框填充 |
| textPrimary | #E4E4E7 | 主文字 |
| textSecondary | #9CA3AF | 辅助文字 |
| accent | #3B82F6 | 按钮、选中态、链接 |
| accentHover | #93C5FD | 按钮悬停（dark） |
| success | #22C55E | 成功状态（dark） |
| warning | #FACC15 | 警告状态（dark） |
| error | #EF4444 | 错误状态（dark，含日历 now-indicator） |
| disabled | #4B5563 | 禁用态（dark；light 用 #9CA3AF） |
| border | #2D2D3A | 边框、分割线 |

## Typography

使用系统默认字体，不加自定义字体包。

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| headline | 20sp | w600 | 页面标题 |
| title | 16sp | w600 | 卡片标题、Section 标题 |
| body | 14sp | w400 | 正文 |
| caption | 12sp | w400 | 辅助说明、时间标签 |
| overline | 10sp | w500 | 极小标签 |

## Spacing

基础单位 4px，所有间距为 4 的倍数。

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | 紧凑间距 |
| sm | 8px | 列表项间距、卡片间距 |
| md | 12px | 内边距（紧凑） |
| lg | 16px | 卡片内边距、Section 间距 |
| xl | 24px | 页面边距 |
| xxl | 32px | 大间距 |

## Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| sm | 6px | 按钮、输入框 |
| md | 8px | 卡片 |
| lg | 12px | 弹窗、对话框（最大值） |

## Component Principles

1. 能用一个颜色不用渐变
2. 能用纯色图标不用 emoji
3. 信息密度优先——一屏显示尽量多的有用信息
4. 动画只用于状态切换（0.2s ease），不用于装饰
5. 阴影极少使用，用 border 区分层次
6. 最小触摸目标 48x48dp
7. 色彩对比度符合 WCAG 2.1 AA

## Page Layout（页面级条款，2026-09-27 走查补）

### Section 标题
- 一律左对齐：`title`（16sp w600），`padding horizontal 16 / vertical 8`。
- 禁止居中分组标题（"数据""账号"居中即此条违规实例）。

### 桌面内容列
- 表单 / 设置 / 关于 / 反馈 / 空状态页：内容列 `max-width 640`，超宽居中。
- 日历视图免此条（full-bleed），但工具条控件必须收进同一标题栏，禁止三拨控件各占一行。

### 空状态模板
- 结构：图标 + 标题（body）+ 一句说明（caption）+ 行动按钮。
- 行动点必须放在空状态体内（可与右上角入口并存，禁止只有右上角入口）。
- 四页差异化：search 给历史/建议入口，aichat 给"去哪找 Key"一句话引导，tags/trash 行动按钮就地新建/清空——禁止四胞胎。

### 表单输入框
- `filled: true`，`fillColor: surface`（light `#FFFFFF` / dark `#1A1A2E`）。
- 禁止透明底输入框直接趴在 background 上（"纯黑感"主因）。

## Kalender 接管条款（2026-09-27 走查补）

第三方库样式必须显式接线，禁止用库默认混入两种 locale 体系：

- 星期标签：`weekDayHeaderStyle.stringBuilder` 用 App 语言（`Localizations.localeOf` + `DateFormat.E`），不跟 kalender 自身 `context.locale`（浏览器/系统 locale）。
- 时间轴：`timelineStyle.stringBuilder` 固定 24h `H:mm`（如 `8:00`）。标尺只做标尺：全半角统一 5 字符，测量与渲染同源，任何 locale 下零截断。标签密度与网格线同频：整点线配整点标签（`textPadding.vertical` 即密度推子，归零会塌成 5 分钟一档，见 `calendar_section.dart` 注释）。
- now-indicator：`lineColor`/`circleColor` = theme `error`（已接线，保持）。
- 日列表头：自画（`CalendarDayHeader`），大数字（headline）+ 星期（caption），today 数字 accent + 14% accent 底 pill；禁用库默认 IconButton 圆点两行。
- 网格线：自画（`CalendarHourLines`），只画整点线，颜色 = divider 35%；禁用库默认半小时自适应分段。
- 空态：日历无事件时叠一句非交互提示（`emptyCalendarHint`，`IgnorePointer` 透传点按新建），禁止晾整页空网。

## 自定义主题色条款（2026-09-27 走查补）

- 用户选色（seed）只允许替换 accent 系（primary/secondary）。
- `error` / `surface` / `onSurface` / `surfaceContainerHighest` 必须回填 token（`ColorScheme.fromSeed(...).copyWith(...)`），禁止整套 scheme 脱离 token 表。
