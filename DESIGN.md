# DESIGN.md — DaySpark Design System

AI 编码工具读此文件来保持 UI 一致性。

## Design Philosophy

**温和清晰。** 参考标杆：Apple 日历（留白与层次）、iOS 系统控件（控件行为可预期）。
信息密度让位于**可读的层次**：一屏能看多少是次要的，一眼知道先看什么是主要的。

**拒绝"AI 味"：** 不渐变、不 emoji 图标、不装饰性动画。
**允许：** 连续圆角（iOS 观感）、卡片浮起（阴影用于分层，不是装饰）。

> 2026-09-28 方向变更：由「Linear 式冷淡 + 信息密度优先」转向「Apple 日历式温和清晰」。
> 浅深同做、适度留白、锁死自带色卡、真 iOS 质感。变更依据见会话预览 `home-preview.html`。

## Colors

照抄 iOS 系统色语义，与系统控件同源，避免打架。

### Light Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #F2F2F7 | 页面底色（systemGroupedBackground） |
| surface | #FFFFFF | 卡片、弹窗、输入框 |
| surfaceSecondary | #E5E5EA | 分段控件底、标签底 |
| textPrimary | #1C1C1E | 主文字（label） |
| textSecondary | #8A8A8E | 辅助文字（secondaryLabel） |
| textTertiary | #C7C7CC | 占位、禁用（tertiaryLabel） |
| accent | #007AFF | systemBlue，主操作 |
| accentHover | #0062CC | 按下态 |
| separator | #E5E5EA | 分割线 |
| separatorSoft | #F0F0F3 | 日历网格线（比分割线更轻） |
| success | #34C759 | systemGreen |
| warning | #FF9500 | systemOrange |
| error | #FF3B30 | systemRed，含日历 now-indicator |

### Dark Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #0A0A0C | 页面底色（不用纯黑：大屏上又硬又平） |
| surface | #1C1C1E | 卡片、弹窗、输入框 |
| surfaceSecondary | #2C2C2E | 分段控件底、标签底 |
| textPrimary | #FFFFFF | 主文字 |
| textSecondary | #98989D | 辅助文字 |
| textTertiary | #48484A | 占位、禁用 |
| accent | #0A84FF | systemBlue (dark) |
| accentHover | #409CFF | 按下态 |
| separator | #38383A | 分割线 |
| separatorSoft | #2A2A2C | 日历网格线 |
| success | #30D158 | systemGreen (dark) |
| warning | #FF9F0A | systemOrange (dark) |
| error | #FF453A | systemRed (dark) |

### 主题色（锁死色卡）

用户**不能**自由选色。提供一套预设主题色，每套都是调好的完整 accent 系：

| 名称 | Light | Dark |
|------|-------|------|
| 蓝（默认） | #007AFF | #0A84FF |
| 绿 | #34C759 | #30D158 |
| 橙 | #FF9500 | #FF9F0A |
| 紫 | #AF52DE | #BF5AF2 |
| 粉 | #FF2D55 | #FF375F |

- 换主题色**只替换 accent / accentHover**，`error` / `surface` / `onSurface` / 语义色一律回填 token。
- 禁止 `ColorScheme.fromSeed` 整套派生（会让语义色脱离 token 表）。

### 日历事件色

事件块：**浅色底（色相 13% 混 surface）+ 左侧 3px 色条 + 主文字色正文**。

| 分类 | 色条 |
|------|------|
| 工作 | accent（跟随主题色） |
| 生活 | success |
| 产品 | 紫 #AF52DE / #BF5AF2 |
| 提醒 | warning |

禁止实心高饱和块 + 白字（并排多个时过吵）。

## Typography

使用系统默认字体（SF Pro / 系统栈），不加自定义字体包。

| Token | Size | Weight | Line height | Usage |
|-------|------|--------|-------------|-------|
| display | 26sp | w700 | 1.12 | 页面主标题（如「9月」） |
| headline | 20sp | w600 | 1.3 | 区块大标题 |
| title | 17sp | w600 | 1.35 | 卡片标题、Section 标题 |
| body | 15sp | w400 | 1.4 | 正文、任务文本 |
| caption | 13sp | w400 | 1.4 | 辅助说明、时间标签 |
| overline | 11sp | w500 | 1.4 | 极小标签、星期头 |

**规则：** 主标题与正文的字号差必须 ≥ 1.7 倍（26 / 15），这是层次感的来源。
**字重只用 400 / 500 / 600 / 700。** 数字列一律 `tabular-nums`。

## Spacing

基础单位 4px，所有间距为 4 的倍数。

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | 图标与文字、行内紧凑 |
| sm | 8px | 列表项内、标签内 |
| md | 12px | 卡片内边距（紧凑） |
| lg | 16px | 页面边距、卡片内边距 |
| xl | 24px | 区块之间 |
| xxl | 32px | 大区块之间 |

**页面左右边距固定 16px**（手机）；桌面内容列另见下条。

## Border Radius

| Token | Value | Usage |
|-------|-------|------|
| sm | 8px | 小控件、标签、事件块 |
| md | 10px | 输入框、分段控件、图标按钮 |
| lg | 12px | 按钮 |
| xl | 16px | 卡片 |
| pill | 999px | 胶囊（今日按钮、色点、勾选框） |

连续圆角优先（`RoundedRectangleBorder` + 足够大的半径），禁止 16px 以上的非胶囊圆角。

## Elevation

阴影用于**分层**，不是装饰。

| 层级 | 用法 |
|------|------|
| 0 | 页面底色、日历网格 —— 无阴影 |
| 1 | 卡片、设置分组 —— 极轻（`blurRadius 8, opacity 0.06`）或纯色差 |
| 2 | 悬浮元素：FAB、底部 tab bar、模态 —— 明确浮起 |

- 禁止彩色阴影（FAB 阴影用 accent 系，透明度 ≤ 0.4）。
- 深色模式下阴影不可见时，用**表面色提亮**替代（#1C1C1E 上的卡片用 #2C2C2E）。

## Component Principles

1. 能用一个颜色不用渐变
2. 能用纯色图标不用 emoji
3. **可读的层次优先**——先让人一眼看清主次，再谈信息密度
4. 动画只用于状态切换（0.2s ease），不用于装饰
5. 阴影只用于分层（见 Elevation），不用于装饰
6. 最小触摸目标 48x48dp
7. 色彩对比度符合 WCAG 2.1 AA
8. 图标统一 `CupertinoIcons`（iOS 观感），禁用 Material `Icons`

## Page Layout（页面级条款）

### 页面主标题
- 一律左对齐：`display`（26sp w700），下方 `caption` 副标题（如「2026年」）。
- 页面边距 16px。

### Section 标题
- 一律左对齐：`title`（17sp w600）。
- 禁止居中分组标题。
- 右侧可放计数或操作入口（`caption` 字号，居中基线对齐）。

### 桌面内容列
- 表单 / 设置 / 关于 / 反馈 / 空状态页：内容列 `max-width 640`，超宽居中。
- 日历视图免此条（full-bleed），但工具条控件必须收进同一标题栏，禁止三拨控件各占一行。

### 空状态模板
- 结构：图标 + 标题（body）+ 一句说明（caption）+ 行动按钮。
- 行动点必须放在空状态体内（可与右上角入口并存，禁止只有右上角入口）。
- 四页差异化：search 给历史/建议入口，aichat 给"去哪找 Key"一句话引导，tags/trash 行动按钮就地新建/清空——禁止四胞胎。

### 表单输入框
- `filled: true`，`fillColor: surface`，圆角 `md`(10)。
- 禁止透明底输入框直接趴在 background 上。
- 聚焦态：边框 accent 2px。

### 底部导航
- 高度 56 + 安全区，图标 24、文字 `overline`(11) w500。
- 选中态：颜色 accent + 胶囊底（`accent` 12% 透明）。
- 背景毛玻璃（`blur 12`）+ 顶部 1px separator。

## Kalender 接管条款

第三方库样式必须显式接线，禁止用库默认混入两种 locale 体系：

- 星期标签：`weekDayHeaderStyle.stringBuilder` 用 App 语言（`Localizations.localeOf` + `DateFormat.E`），不跟 kalender 自身 `context.locale`。
- 时间轴：`timelineStyle.stringBuilder` 固定 24h `H:mm`（如 `8:00`）。标尺只做标尺：全半角统一 5 字符，测量与渲染同源，任何 locale 下零截断。标签密度与网格线同频。
- **默认滚动位置：停在当天钟点**，不固定从 0:00 起。
- now-indicator：`lineColor`/`circleColor` = theme `error`（已接线，保持）。
- 日列表头：自画（`CalendarDayHeader`），大数字（headline w600）+ 星期（overline），today 数字白字 + accent 圆底（32×32 胶囊）。
- 网格线：自画（`CalendarHourLines`），只画整点线，颜色 = `separatorSoft`；禁用库默认半小时自适应分段。
- 事件块：`tileBuilder` 统一（`event_tile.dart`），浅底 + 左 3px 色条，圆角 `sm`(8)。块高 ≥ 36px 时显示时间行，不足只显示标题。
- 全天事件：单独一条泳道（位于星期行之下、时间网格之上），胶囊形。
- 空态：日历无事件时叠一句非交互提示（`emptyCalendarHint`，`IgnorePointer` 透传点按新建），禁止晾整页空网。

## 变更记录

- **2026-09-28** 整体转向：Linear 冷淡 → Apple 日历温和清晰。色板换 iOS 系统色、字阶改 6 级（26/20/17/15/13/11）、圆角放宽、引入分层阴影、主题色改锁死色卡。
- **2026-09-27** 页面级条款（标题左对齐、640 内容列、空状态模板、表单输入框）+ Kalender 接管条款 + 自定义主题色条款。
