# 设计 Token 一致性差距报告 / Design Token Gap Report

对照源：`DESIGN.md`（仓库根目录）。审计日期：2026-09-24。

## 结论（一句话）

**综合一致率约 75%**：token 文件层面高（颜色 15/16、字体规格 5/5 ≈ 94%），但落地层明显漂移 —— fontSize 仅 34/51 在标（67%）、间距约 80%、圆角 27/30（90%），另加 kalender 未接线样式（now-indicator 硬编码红）、M3 默认弹窗/按钮形状越过 12px 上限、多处触控 <48dp。

## 差距表（按影响排序）

| # | 位置 | 期望 (DESIGN) | 实际 | 修复建议 |
|---|------|---------------|------|----------|
| 1 | `lib/ui/widgets/calendar/calendar_section.dart:289-317`（`CalendarComponents` 未传 `multiDayComponentStyles`；kalender 包 `time_indicator.dart:136` 默认 `Colors.red`） | now-indicator = theme `error`（light `#DC2626` / dark `#EF4444`） | 库默认硬编码 `Colors.red`（≈`#F44336`），暗色下尤其突兀 | 传 `multiDayComponentStyles: MultiDayComponentStyles(bodyStyles: MultiDayBodyComponentStyles(timeIndicatorStyle: TimeIndicatorStyle(lineColor: theme.colorScheme.error, circleColor: theme.colorScheme.error)))` |
| 2 | 全部 `AlertDialog`/`SimpleDialog`（约 14 处，如 `lib/ui/pages/settings/settings_sections/appearance_section.dart:78,141,207,261`、`lib/ui/pages/home/home_page.dart:159,185`、`lib/ui/pages/tags/tags_page.dart:93,125,198` 等），`app_theme.dart` 无 `dialogTheme` | 弹窗圆角 lg = 12px（最大值） | M3 默认对话框圆角 28dp | `app_theme.dart` 加 `dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))` —— 机械替换 |
| 3 | `app_theme.dart:103` FAB shape；无 `filledButtonTheme`/`textButtonTheme` | 圆角 ≤12 | FAB `circular(16)`；`FilledButton`/`TextButton`/`OutlinedButton` 走 M3 默认胶囊形（≈20+） | FAB 改 12（或圆形成形并写入 DESIGN 豁免）；补 filled/text button 圆角 6 |
| 4 | `lib/core/theme/app_colors.dart:25` | dark accent `#3B82F6` | `#60A5FA`（`0xFF60A5FA`） | 机械替换为 `#3B82F6`，或经设计确认后回写 DESIGN |
| 5 | `app_colors.dart:18,26-29,31` | DESIGN dark 表仅 6 token；light 无 disabled | 代码扩展 `lightDisabled/darkDisabled/darkAccentHover/darkSuccess/darkWarning/darkError`，DESIGN 未收录 | 二选一：补进 DESIGN.md，或标注为「实现扩展 token」 |
| 6 | `app_theme.dart:42-44` | `surfaceContainerHighest` 应来自 token | light `Color(0xFFEEEEEE)` 不在 DESIGN；dark `0xFF2D2D3A` 恰等于 border 值但语义是 surface | `#EEEEEE` 定 token 或改用 border/surface 系；避免裸 hex |
| 7 | `app_theme.dart:26-30` + `lib/main.dart:99-100` + `lib/domain/providers/theme_provider.dart:35-44` | 主题色变化不应破坏 token（accent/error/border 等） | `seedColor != null`（用户在外观设置选色后）整个 ColorScheme 走 `ColorScheme.fromSeed`，accent/border/error/surface 全部脱离 DESIGN 表 | 需设计走查：`fromSeed` 仅派生 primary，其余保持 token；或 DESIGN 增补「自定义主题色」条款 |
| 8 | fontSize 集群（17/51 处 off-scale）：`fontSize: 13` ×9 —— `lib/ui/pages/home/home_page.dart:832,896,918`、`lib/ui/pages/trash/trash_page.dart:271`、`lib/ui/pages/todo/todo_edit_page.dart:453,488`、`lib/ui/pages/todo/todo_create_page.dart:497`、`lib/ui/widgets/attachment_list.dart:55`、`lib/ui/widgets/calendar/marked_month_day_header.dart:66` | 标题类 16sp w600 或 caption 12sp | 13sp（不在 {10,12,14,16,20}） | 分区标题 → `textTheme.titleMedium`(16/w600)，辅助文本 → 12；机械替换 |
| 9 | `fontSize: 11` ×6：`lib/ui/pages/ai_chat/ai_chat_page.dart:558`、`lib/ui/widgets/ai_config_dialog.dart:187`、`lib/ui/widgets/attachment_list.dart:59`、`lib/ui/widgets/todo/date_strip.dart:73,250`、`lib/ui/widgets/todo/todo_list_tile.dart:149` | caption 12sp 或 overline 10sp | 11sp | 机械替换到 12 或 10（按语义） |
| 10 | `lib/ui/widgets/calendar/marked_month_day_header.dart:116`（`fontSize: 7`）、`:137`（`fontSize: 9`） | 最小 overline 10sp | 7sp / 9sp | 收到 10sp 或在 DESIGN 写明「日历微标签豁免」—— 需设计走查（格子宽度受限） |
| 11 | 触控 <48 抽样：`lib/ui/widgets/todo/todo_list_tile.dart:106-130`（Checkbox `shrinkWrap` 24×24）、`lib/ui/pages/home/home_page.dart:462`（FilterChip 行高 36）、`lib/ui/pages/settings/settings_sections/appearance_section.dart:162`（色点 40×40）、`lib/ui/pages/tags/tags_page.dart:145-148,218-221`（色点 32×32）、`lib/ui/pages/home/home_page.dart:507,517`（`visualDensity.compact` IconButton ≈40）、`lib/ui/widgets/calendar/calendar_section.dart:385-393`（Today `minimumSize: Size.zero`）、`lib/ui/pages/todo/todo_edit_page.dart:493-503`（子任务勾选 InkWell ≈22、删除 ≈22） | 最小触摸 48×48dp | 24–40 不等 | 包裹 `ConstrainedBox(minConstraints: 48×48)` 或去 compact；需逐个走查（列表密度 vs 触控） |
| 12 | 间距 off-scale（4px 基准）抽样 15 处：`calendar_section.dart:323`(`vertical:6`)、`:343-344`(`10/6`)、`:368,381,421`(gap 6)、`home_page.dart:836,923`(gap 6)、`trash_page.dart:273`(gap 6)、`ai_chat/ai_chat_page.dart:154`(6)、`:549`(`h6 v2`)、`date_strip.dart:67`(h6)、`:153`(v10)、`:239`(h10)、`app_theme.dart:78,96`(v10)、`marked_month_day_header.dart:99,130`(2/1)、`todo_edit_page.dart:462`(v2) | 全部间距为 4 的倍数（xs4/sm8/md12/lg16/xl24/xxl32） | 6/10/2/1 | 多数可机械替换（6→4 或 8，10→8 或 12）；日历头部微间距需看效果 |
| 13 | `lib/ui/pages/tags/tags_page.dart:145,218` | 圆角 ∈ {6,8,12} | `circular(16)`（用于圆形色点的 InkWell，容器本身 `BoxShape.circle`） | 低危：改为 16 无视觉意义可留，或换 `CircleBorder` 匹配的 clip；建议清理避免审计噪声 |
| 14 | `app_typography.dart:38-48`（`textTheme()` 未映射 `titleSmall`/`titleLarge`/`headlineMedium` 等）+ 使用点 `settings_sections/account_section.dart:59`、`import_export_section.dart:25`、`date_strip.dart:57` | Section 标题 = title 16sp w600 | `titleSmall` 未入 token 表，回落 Material 默认（≈14sp w500），与 DESIGN title 不符 | 显式映射 `titleSmall: title`（或 12/caption 并改 DESIGN）—— 需确认语义 |
| 15 | `app_theme.dart:60`(Card 8 ✓)、`inputDecoration` 6 ✓、ElevatedButton 6 ✓ —— 但 `app_theme.dart:78` 按钮 `vertical: 10` | 按钮内边距 4 的倍数 | v10 off-scale | 机械改 12 或 8 |

## Kalender 专项（`lib/ui/widgets/calendar/*`）

| 项 | 期望 | 实际（file:line） | 建议 |
|----|------|-------------------|------|
| now-indicator 颜色 | theme error token | 库默认 `Colors.red`，`calendar_section.dart:289-317` 未传 `multiDayComponentStyles`（触发点：kalender `lib/src/widgets/components/time_indicator.dart:136`） | 见差距表 #1，机械接线 |
| 月视图日号样式 | caption/正文 token | `marked_month_day_header.dart:66` `fontSize:13 w500` off-scale（`style?.numberTextStyle` 默认 null 走此 fallback） | 收到 12 或 14 |
| 节假日徽标 | overline 10 w500 | `marked_month_day_header.dart:116` `fontSize:7`；`padding h2 v0.5`（:101-104）、`SizedBox(2)`（:99） | 需设计走查：格子空间 vs 10sp 最小值 |
| 节气微标签 | overline 10 | `marked_month_day_header.dart:137` `fontSize:9`；`only(top:1,bottom:2)`（:130） | 同上 |
| 月视图周标题（weekday label） | caption 12sp w400 | **符合**：kalender `WeekDayHeader` 默认用 `theme.textTheme.bodySmall`，而 `app_typography.dart:47` 把 `bodySmall` 映射为 caption；但库默认 `padding vertical: 2` off-scale（kalender `week_day_header.dart`） | 通过 `monthComponentStyles.headerStyles.weekDayHeaderStyle` 调 padding 4 |
| 日/周视图行高（密度） | 信息密度优先 | 库默认 `defaultHeightPerMinute = 0.7` → 42px/小时，`calendar_section.dart:263-270` 未配置 `initialHeightPerMinute` | 需设计走查：是否提密（如 0.5 → 30px/h） |
| 日/周头部今日标记触控 | 48×48 | kalender `DayHeader` 用 `IconButton(.filled)` + `visualDensity.compact`（≈40），`day_header.dart` | 传 `dayHeaderStyle`/自定义 builder 提高触控 |
| 日历工具条间距 | 4 倍数 | `calendar_section.dart:323`(v6)、`:343-344`(h10/v6)、`:368,381,421`(6) | 机械改 4/8 |
| Today 按钮触控 | ≥48 高 | `calendar_section.dart:388-390` `visualDensity.compact` + `minimumSize: Size.zero` | 去掉 Size.zero，保底 48 |
| view switcher | 触控/标度 | `view_switcher.dart:31` `visualDensity.compact`（SegmentedButton 高度 <48） | 走查密度 vs 触控 |
| event tile | 半径 6、间距 4 倍数 | `event_tile.dart:25,74,77` 半径 6 ✓；`:28` `h6 v4` 横向 6 off-scale | h6→4 或 8 |
| 动画 0.2s | 仅状态切换 | `calendar_section.dart:354` AnimatedSwitcher 200ms ✓ | 保持 |

## 匹配项（无需复审）

- **Light 颜色 10/10**：`app_colors.dart:8-17` 与 DESIGN light 表 hex 全部一致（background/surface/textPrimary/textSecondary/accent/accentHover/success/warning/error/border）。
- **Dark 颜色 5/6**：background `#0F0F14`、surface `#1A1A2E`、textPrimary `#E4E4E7`、textSecondary `#9CA3AF`、border `#2D2D3A` 一致（accent 见 #4）。
- **字体规格 5/5**：`app_typography.dart` headline20/w600、title16/w600、body14/w400、caption12/w400、overline10/w500 与 DESIGN 完全一致；系统字体无自定义包 ✓。
- **渐变/阴影（原则 1/5）**：全 `lib/` 零 `LinearGradient|RadialGradient|BoxShadow`；Card/AppBar `elevation: 0`（`app_theme.dart:63,69`），层次靠 border ✓。
- **圆角主体**：`BorderRadius.circular` 30 次调用中 27 次 ∈ {6,8,12}（8×12、6×11、12×4）；`BorderRadius.circular(16)` 仅 3 处（差距 #3、#13）。
- **Card/Input/ElevatedButton 形状**：半径 8/6/6 ✓（`app_theme.dart:60,77,83-91`）。
- **P4 six-things 折叠行**：`home_page.dart:889` 高度 48 ✓；`date_strip.dart` 芯片/日格圆角 8、外边距 h8 v4 ✓；折叠与 section 计数颜色走 theme error/primary ✓（`home_page.dart:684,696`）。
- **动画时长**：`lib/ui` 仅 200ms 两处（`ai_chat_page.dart:47`、`calendar_section.dart:354`），符合 0.2s 状态切换原则；其余 Duration 秒级均为网络/同步超时，非 UI 动画。
- **l10n**：抽样 UI 文本均走 `AppLocalizations`，无硬编码文案问题（本报告范围外）。
- **fontSize 基数**：51 处中 34 处在标（10×3、12×20、14×7、16×3、20×1）。

## P4（six-things / date_strip）专项

| 位置 | 期望 | 实际 | 建议 |
|------|------|------|------|
| `date_strip.dart:73`（Today 按钮文字） | 12 或 10 | `fontSize: 11` | 机械改 10/12 |
| `date_strip.dart:250`（_chip 标签） | 12 或 10 | `fontSize: 11` | 机械改 10/12 |
| `date_strip.dart:239`（_chip padding） | 4 倍数 | `h10 v8` | h10→8 或 12 |
| `date_strip.dart:153`（日格 vertical padding） | 4 倍数 | `v10` | →8 或 12（触控高度联动，见 #11） |
| `home_page.dart:832,918`（six-things/section 标题） | 16sp w600 | 13sp w600 | 机械改 titleMedium |
| `todo_list_tile.dart:149`（序号徽标 1） | 10 或 12 | 11 | 机械改 |

## 建议的修复批次

**批次 A — 机械替换（无设计决策，可一次清剿）**
1. dark accent `#60A5FA`→`#3B82F6`（或改 DESIGN——二选一，改前确认）。
2. `fontSize: 13` ×9 → 16(标题语义)/12(辅助)；`fontSize: 11` ×6 → 12 或 10。
3. 间距 6/10/2 → 最近的 4 倍数（列表内 gap 6→4 或 8，按钮 v10→8/12）。
4. `app_theme.dart` 补 `dialogTheme`(12) + `filledButtonTheme`/`textButtonTheme` 半径 6；FAB 16→12。
5. kalender now-indicator 接 `theme.colorScheme.error`（`calendar_section.dart` 传 style）。
6. `titleSmall` 映射进 `AppTypography.textTheme()`。

**批次 B — 需设计走查决策**
1. `ColorScheme.fromSeed` 主题色功能 vs DESIGN token 表（#7）——确定「自定义主题色」的 token 契约。
2. 日历微字号 7/9/13 与 2/1px 间距：密度现实 vs overline 10sp 下限（#10、kalender 表）。
3. 触控 48 vs 密度：Checkbox 24、FilterChip 36、色点 32/40、compact IconButton、Today Size.zero（#11）——列出可豁免的「仅桌面鼠标」场景。
4. 周/日视图 `initialHeightPerMinute`（42px/h）是否按密度原则调低。
5. DESIGN dark 表补齐扩展 token（success/warning/error/hover/disabled）与否（#5）。
6. `surfaceContainerHighest #EEEEEE` 归属（#6）。
