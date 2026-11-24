# Flutter UI Surface Inventory（2026-11-24）

> 目标：先定死"App 里到底有哪些界面、每个界面该继承哪一种已冻结的页面模型"，再动手改。
> 判定单位不是文件，是 **Surface × State × Form factor**。
> 本文件的表格由两名只读分析员按片产出后合并；代码一律未改。

## 一、口径

一个 **Surface** = 一个用户可见区域，在一种条件下出现。它由 Flutter 代码里的这些位置定义：

| 来源 | 枚举方法 | 数量（机器算） |
|---|---|---|
| 路由 | `app_router.dart` 的 `path` 全集 | 16 |
| Tab / 导航 | 顶栏 Today/Todo/Calendar + 设置入口 | 见矩阵 |
| Dialog | `showDialog(` 调用点 | 约 30 处，分布在 18 个页面文件 |
| Sheet | `showModalBottomSheet(` 调用点 | 4 处（slot sheet、月年选择、composer、时间槽候选待办选择）；时间选择已改为 `DsDialog` 内联方框 |
| Overlay | `OverlayEntry(` 调用点 | 2 处（筛选浮层、命令浮层） |
| 页面内条件分支 | 页面 build 里的状态开关 | 见矩阵 |
| Responsive 分支 | 720 / 1000 / 1180 三档 | 见矩阵 |
| 状态 | loading / empty / error / overdue / editing / dirty | 见矩阵 |

## 二、页面模型词表（只有这 12 种，没有"随便长"）

| 代号 | 模型 | 定义源 | 结构契约 |
|---|---|---|---|
| P1 | todayPage | `todayPage` `todayTaskSections` `todayTimeSections` `taskRow` `timelineRow` `emptyState` | 标题 + 遗漏卡 + 任务分组 + 时间线 + 底部采集条 |
| P2 | todoPage | `todoPage` `todoRow` `groupHead` `modeSwitch` `filterPanel` | 模式切换 + 分组列表 + 筛选浮层 + 行内计划入口 |
| P3 | calendarPage | `calendarPage` `monthView` `weekView` `dayView` `monthSpanBand` `weekAllDay` | 视图切换 + 月/周/日三种排布 + 隐藏日历横幅 + 工具条 |
| P4 | detailDrawer | `detailDrawer` `detailSource` `detailEditor` | 只读摘要 + 编辑态 + 底栏 编辑/安排/删除 |
| P5 | settingsPage | `settingsPage` `settingsContent` | 分组行（DsGroup + DsSettingRow + hairline），无卡片 |
| P6 | settings CRUD 子页 | `settingsPage` 的列表契约 | 列表 + 行内新建/编辑 + 确认删除 |
| P7 | settings 表单子页 | 同上 | DsTextField + 主按钮 + 空/错态 |
| P8 | content page | `commandOverlay` 的输入框 + 内容区契约 | 顶栏 + 滚动正文 + 底部输入坞 |
| P9 | form page | `detailEditor` | 分节字段行 + 保存主按钮 + 未保存拦截 |
| P10 | command overlay | `commandOverlay` `cmdRow` | 居中浮层 + 输入 + 结果行 |
| P11 | mobile variant | `mobileToday` `mobileTodo` `mobileCalendar` `mobileSettings` `mobileCaptureSheet` `mobileDock` | 手机顶栏 + 单列 + 底部坞 |
| 专属 | 专属契约 | 无（必须在矩阵里写一行合同） | 仅当一个界面确实不属于上面任何一种时使用 |

**HTML 未定义的界面（`/tags` `/calendars` `/ai-chat` `/about` `/feedback` `/event/new`）必须落到 P5/P6/P7/P8/P9 中的一个**，不允许"只统一样式、不定模型"。

## 三之前：Responsive 分歧点（必须每档显式列在矩阵"形态"列）

| 档位 | 常量 | 行为 |
|---|---|---|
| ≥720 | 移动布局阈值 | 之下为手机单列 + 底部坞；之上为桌面布局 |
| ≥1000 | `canShowDesktopDrawer` | 详情以右侧抽屉常驻（master-detail），入口点击不 push 全页 |
| ≥1180 | `kWideDesktopBreakpoint` | 双栏宽布局 |

## 三、机器枚举到的"第二套语言"证据

**先修正上一版的一个错误结论**：我此前按"调用点"计数，写成"18 个页面文件各自造了约 30 个对话框"。逐点核对后，绝大部分 `showDialog` 的 builder 里用的就是共享 `DsDialog`，属于同一个模型，不是第二套语言。真实数字如下（44 个弹层调用点全量分类）：

| 分类 | 数量 | 说明 |
|---|---|---|
| 走共享 `DsDialog` / `SpecDeleteConfirmDialog` / `SpecPlanPickerDialog` | 26 | 已属同一模型，**不动** |
| 弹层原语自身实现（`ds.dart`、`spec_components.dart` 内部） | 4 | 定义源，不是重复 |
| 已核实为平台感知的正确双形态（不违规） | 4 | composer、月年选择器、命令浮层、slot sheet |
| 已核实内部就是 `DsDialog` | 1 | `ai_config_dialog` |
| 真正偏离 | 3 | 见下表 |

真正偏离、**已逐点读过源码确认**的 3 处（另 1 处降级为 P2 打磨）：

| 位置 | 现状 | 应归入 |
|---|---|---|
| `todo_detail_page.dart:271` | `AlertDialog`，Material 默认标题/按钮 | P9 → 共享确认框 |
| `event_detail_page.dart:179` | 同上，复制粘贴的第二份 | P9 → 同上，合并成一处 |
| `import_export_section.dart` | `AlertDialog` | P7 → `DsDialog` |
| `settings_ui.dart:342`（P2） | `SimpleDialog` 手工容器，但内部已用 `SpecTokens.paper`/`r12`/`hair`/15px 标题/`DsSettingRow` | 视觉已是同一语言，只是容器没走 `DsDialog`；记 P2 |

**已读过源码确认不是残留（撤回原判断）**：

| 位置 | 实际 | 结论 |
|---|---|---|
| `ai_config_dialog.dart:28` | 容器里第 233 行返回的就是 `DsDialog`（`DsButton` + `DsTextField`） | 合规，撤回 |
| `a2_composer.dart:62` / `:69` | 同一个 composer 组件，桌面居中 dialog、手机 bottom sheet，**同一断点常量决定**，代码里有 WHY 注释 | 平台感知的正确实现，不动 |
| `search_page.dart:63` | `showCommandOverlay` 就是命令浮层模型 P10 的容器 | 归属 P10，不动 |
| `month_year_picker.dart:25` / `:32`、`calendar_slot_sheet.dart:48`、`todo_occurrence_picker_sheet.dart:71`、`legacy_recurrence_dialog.dart:96`、`calendar_filter_sheet.dart:40` | 各自的容器，内容组件在设计系统内 | 按 Surface 判定，不按文件判定 |

**教训**：`showDialog` / `showModalBottomSheet` 本身不是违规信号，违规的是"容器里不是设计系统组件"。按调用点计数会造假问题。

**另一处已核实并撤回的数**：`SnackBar` 真实调用点 108 处（我上一轮报 165，计数把 `SnackBar(` 的类型声明也算进去了）；`AlertDialog` 只有 3 个文件在用；只有 `onTap` 的裸 `GestureDetector` 58 处。

## 三·五、附录 A：机器抽取的状态维度（矩阵"状态集合"列的种子）

直接从代码里的 bool 开关 / enum / `AsyncValue.when` / responsive 判定抽出来，不是人猜的。**这才是"一个页面对应多少种界面"的实数。**

| 页面 | 状态维度 | 说明 |
|---|---|---|
| `today_page.dart` | `captureFocused` `capturing` `completedExpanded` `desktopEndedExpanded` `endedExpanded` `unplannedExpanded` `upcomingExpanded` `toastVisible` + responsive | 至少 8 个展开/折叠态 × 桌面·手机两形态，**这一个文件就是一个矩阵** |
| `a2_todo_page.dart` | `captureFocused` `capturing` `completedOpen` `resetCaptureScheduled` + `_UndoGroup` enum + `_loading` + responsive | 模式切换 × 分组展开 × 筛选浮层 × 撤销条 |
| `a2_composer.dart` | `discardOpen` `event` `parsedHasSuggestion` `planOpen` `saving` `suggestionApplied` `suggestionRemoved` `titleValidationError` `writeFailed` + responsive | 解析态 / 建议态 / 计划态 / 失败态 × 两种形态 |
| `todo_detail_page.dart` | `dirty` `editing` `saving` `saveFailed` `titleError` `repeatError` `deleting` `deletedNotified` + responsive | 只读 / 编辑 / 保存中 / 保存失败 / 字段错误 / 删除中 |
| `event_detail_page.dart` | 同上 + `timeError` | 与 todo 详情**同一套状态机**，两份复制 → 应合并为一个 P4/P9 实现 |
| `todo_form_page.dart` / `event_form_page.dart` | `saving` `deleting` `aiLoading` `loadingAssociations` + `AsyncValue.when` + responsive | 表单页同族 |
| `quick_add_page.dart` | `isEvent` `saving` `suggestionRemoved` + `_error` + responsive | 快速添加 |
| `a2_calendar_page.dart` / `a2_calendar_views.dart` | `hovered` `isEmpty` + `CalendarViewMode` enum | 月/周/日三视图 × 悬停/空态 |
| `calendar_slot_sheet.dart` | `_CandidatesState` enum `showingTodoPicker` | 时间槽三动作启动器 |
| `settings/calendar_settings_section.dart` | `_CalSubpage` enum `expanded` `deleteAllTogether` | 日历管理仍是折叠行 → 应归 P6 |
| `tags_page.dart` | `_TagSubpage` enum `saving` + `AsyncValue.when` | 标签 CRUD 子页 → P6 |
| `import_export_section.dart` | `backupBusy` `backupFailed` `importBusy` `importMode` | 备份/导入/恢复四态 |
| `about_page.dart` | `bodyExpanded` `checking` `noReleases` `versionFailed` | 更新检查三态 |
| `ai_chat_page.dart` | `sending` `writing` | 会话页 → P8 |
| `trash_page.dart` | `busy` + `AsyncValue.when` | P6 列表 |
| `feedback_page.dart` | `copied` | P7 表单 |

## 三·六、孤立路由与重复实现（本轮最有价值的一处真残留）

设置页不是路由跳转，而是一个**页内 section 注册表**（`settings_page.dart` 的 `_goToSectionKey`），key 为
`home / account / ai / general / calendars / data / tags / trash / io / notify / sync / about`。

按"每个路由是否真的被 UI 导航到"机械核查：

| 路由 | 是否被 UI 导航 | 页面文件 | 设置里的对应 section | 结论 |
|---|---|---|---|---|
| `/tags` | 是（`tag_chips.dart:52`）+ 设置内嵌 | `TagsPage(embedded: true)` | 同一个 widget | **正确做法**：一个实现，两个宿主 |
| `/trash` | 否（只有设置内嵌） | `TrashPage(embedded: true)` | 同一个 widget | 同上，但路由本身是孤立的 |
| `/about` | **否** | `about_page.dart`（341 行，独立 `WorkspacePage`） | `AboutSection`（65 行，另一套实现） | **重复实现 + 孤儿路由** |
| `/calendars` | **否** | `calendars_page.dart`（382 行，独立 `WorkspacePage`） | `CalendarSettingsSection`（772 行，另一套实现） | **重复实现 + 孤儿路由** |

证据：`about_page.dart`、`calendars_page.dart` 只被 `app_router.dart` 与各自测试引用，`lib/` 内没有任何字面量 `go('/about')` / `go('/calendars')`。

### 三条孤儿路由（全量核实，无一处入口）

| 路由 | 唯一引用者 | 结果 |
|---|---|---|
| `/about` | 无（`spark_top_bar` 只有 `startsWith` 判断，用于清高亮） | **用户无法进入**；设置里的「关于」是 `AboutSection`，与它无关 |
| `/calendars` | 无 | **用户无法进入**；设置里的「日历管理」是 `CalendarSettingsSection` |
| `/event/edit` | 无 | **用户无法进入**；事件编辑走详情页的编辑态，不走该路由 |
| `/feedback` | 唯一入口是 `about_page.dart:327`，而 `about_page` 本身不可达 | **整条链断掉**：反馈入口随孤立的关于页一起消失 |

也就是说：**`/about`、`/calendars`、`/event/edit` 三个页面文件、以及 `/feedback` 的页面，用户这辈子在 App 里点不到**。
它们还在路由表里、还在编译产物里、还有测试覆盖——这就是"旧 UI 残留"最硬的一种形态：不是样式旧，是**没人能看见，却还在维护**。

### 到处可见的重复实现

同一个界面存在两套实现，用户从设置进入看到 A 版，从路由/深链进入看到 B 版：

| 界面 | 设置内（可达） | 路由页（不可达） |
|---|---|---|
| 关于 | `AboutSection` 65 行 | `AboutPage` 341 行 |
| 日历管理 | `CalendarSettingsSection` 772 行 | `CalendarsPage` 382 行 |
| 反馈 | （无） | `FeedbackPage`，只能从不可达的 `AboutPage` 进入 |

`tags` / `trash` 已经示范了正确写法（`embedded: true`，一个 widget 两个宿主，路由和设置页共用同一实现）。

**这就是"像另一个 App"的根因之一**：同一个界面存在两套实现，用户从设置进入看到的是 A 版，从路由/深链进入看到的是 B 版，
两版的行高、分组、空态、按钮都不一样。

修法二选一，且必须先裁定：
- **A（推荐）**：`AboutPage` / `CalendarsPage` 改为 `embedded: true` 共享同一个内容 widget，设置内与路由内显示完全同一屏；
- **B**：删除 `/about`、`/calendars` 路由与页面文件，只保留设置内 section（同时删除对应测试）。

`/trash`、`/tags` 的孤立路由同样按此口径处理（要么接回入口，要么删路由）。

## 三·七、原生小组件（前几轮完全没进过任何清单）

**如实回答：小组件从头到尾没有被讨论过，也没有被重构过。** 我的"界面全集"只从 Flutter 的三个来源枚举（router / 弹层 / responsive），
原生小组件不属于这三样，所以一直不在清单里。这是方法的第四个漏点。

实测现状：

| 平台 | 实现 | 体量 | 重复情况 |
|---|---|---|---|
| iOS | `ios/CalendarTodoWidget/CalendarTodoWidget.swift` | 1654 行 | 与 macOS 版 **diff 只有 113 行（≈93% 同一份代码）**，两份各自维护 |
| macOS | `macos/CalendarTodoWidget/CalendarTodoWidget.swift` | 1648 行 | 同上 |
| Android | `TodayWidgetProvider` / `TodoWidgetProvider` / `CalendarWidgetProvider` + `WidgetSupport` / `WidgetSnapshot` + 4 个 XML 布局 | ≈ 2400 行 | 三个 provider 各自一套 row 构建 |

**规格覆盖**：`dayspark-spec.html` 里 `widget` 出现 **0 次** —— 小组件在冻结规格里完全没有定义。

**调色板（这是最硬的旧残留证据）**：两端小组件的颜色都没接设计令牌，用的仍是**收敛前的旧 `AppColors` 值**：

| 用途 | 小组件 fallback（iOS/macOS/Android 一致） | `SpecTokens` 现值 |
|---|---|---|
| 背景 | `#FCFCFA` | `paper #FFFFFF` |
| 主文字 | `#191A17` | `ink #191918` |
| 次文字 | `#3F413A` | `ink2 #45453F` |
| 强调 | `#C2410C` | `red #C92A1E` |
| 分隔线 | `#E8E7E1` | `hair #ECECE6` |

iOS Swift 里 `WidgetPalette` 的 fallback 就是这组旧值（`CalendarTodoWidget.swift:588-594`），Android XML 里也是同一组。

**Surface 集合（待补进矩阵）**：
- iOS/macOS：2 种 widget × `systemSmall / systemMedium / systemLarge`
- Android：Today / Todo / Calendar 三种 × 2–3 种尺寸 + 空态/有数据/暗色/紧凑
- 状态：正常、空、暗色、错误（无数据落盘时）

**需要新增的模型**：
- **P12 = 原生小组件家族**：内容模型跟随 P1/P2/P3 的行语义（taskRow / timelineRow / monthCell），视觉令牌必须与 `SpecTokens` 同源（建立一张 Dart → 原生的键值表，两端同改）。
- 另外要裁定：iOS 与 macOS 那两份 93% 相同的 Swift 是否合并为一份共享源码（当前是手动双维护）。

## 三·八、还有四类东西一直不在清单里（自曝）

前三轮我的枚举只覆盖了「Flutter 页面 + 弹层」。补齐后仍有四类没被算进界面全集：

### 1. 页面里的 Material 默认组件（数量最大，最显眼）

| 组件 | 处数 | 典型位置 | 为什么是问题 |
|---|---|---|---|
| `showDatePicker` / `showTimePicker` | **7 + 7 = 14** | `today_page`(2+2)、`a2_todo_page`(2+2)、`schedule_pickers`(2)、`spec_components`(2+2) | Material 3 日历选择器 / 表盘时钟，**和 App 的纸感设计完全不同族**，一打开就是"另一个 App" |
| `Card(` | 21 | `import_export_section`(6)、`tags_page`(4)、`calendar_settings_section`(4) | 设计规范明确"不要卡片" |
| `TextField(` | 36 | `ai_config_dialog`(3)、`todo_form_page`(3)、`todo_detail_page`(3) | 与 `DsTextField` 并存两套输入框 |
| `TextButton` | 62 | `a2_composer`(14)、`a2.dart`(13)、`todo_detail_page`(6) | Material 文字按钮，与 `DsButton` 并存 |
| `Switch(` | 12 | `a2_todo_page`(5)、`a2_calendar_page`(3) | Material 开关样式 |
| `Tooltip(` | 20 | `a2_todo_page`(4)、`todo_detail_page`(2) | 灰色圆角浮层，桌面悬停时很出戏 |
| `CircularProgressIndicator` | 20 | 各处 | Material 转圈 |
| `IconButton(` / `InkWell(` / `Divider(` | 26 / 33 / 10 | 各处 | 与 `DsIconButton` / `FocusableTap` / `DsDivider` 并存 |
| `LicensePage` / `showLicensePage` | 3 | `about_section`、`about_page` | Material 默认许可页 |

> 更正：我上一轮报 `showDatePicker` 为 0，是 grep 命令写坏导致的误报。真实是 14 处。

### 2. 服务端渲染的 HTML 界面（第三套 UI 家族）

- `server/lib/src/oauth/consent.dart`：MCP 客户端授权时浏览器里显示的**同意页**，纯手写 HTML/CSS，与 App 设计系统无任何关系，也从未进过任何 UI 清单。
- 同一文件族里的错误页/授权结果页同理。

### 3. 系统集成表面（不是 Flutter 画的，但用户会看见）

| 表面 | 位置 | 现状 |
|---|---|---|
| 通知（标题/正文/动作按钮/渠道名） | `notification_service.dart`（Android 渠道 + `AndroidNotificationAction`、iOS `DarwinNotificationCategory`） | 文案与动作从未按规格审过 |
| macOS 菜单栏 | `macos/Runner/Base.lproj/MainMenu.xib`（61 个 menuItem） | 仍是 Flutter 模板菜单，含 Edit/View/Window/Help 默认项 |
| Android 小组件选择器 | `res/xml/{today,todo,calendar}_widget_info.xml`（预览图 + 描述） | 预览图与描述是否与新视觉一致未核 |
| App 图标 / 启动图 | 各平台资源 | 从未与设计方向对过 |

### 4. 应用图标与品牌面

图标、启动页、关于页的版本信息展示，同属"用户第一眼看到"的表面，此前完全没进清单。

## 三·九、还差的不是"新界面"，而是四个维度

界面全集到这里基本闭合了。剩下漏的是**维度**——每一条 Surface 还必须在这些维度上各有定义，否则矩阵仍然不完整：

| 维度 | 现状 | 结论 |
|---|---|---|
| **主题（浅/深）** | `main.dart:126` 写死 `themeMode: ThemeMode.light`（注释说明冻结规格只有浅色）；但 `darkTheme` 仍在传、`themeModeProvider` 仍在（默认 system），且**桌面小组件会跟随系统变暗**（`CalendarTodoWidget.swift:588` 的 `dark ? …` 分支） | 三个不一致：App 强制浅色、暗色主题是死代码、小组件却会变暗。要么小组件也锁浅色，要么 App 恢复跟随系统——必须裁定 |
| **文本缩放 / 无障碍** | 全仓库 0 处 `textScaler` / `TextScaler` 处理 | 系统字号放大后没有任何约束与验证，也没做过布局压测 |
| **输入方式** | 键盘快捷键 42 处；鼠标悬停有；**右键/上下文菜单 0 处** | 桌面平台法则缺口：桌面用户没有右键菜单 |
| **滚动行为** | `AppScrollBehavior` 在 macOS 上用 `BouncingScrollPhysics`（iOS 手感） | 桌面平台用手机回弹手感，需确认是否有意为之 |

另外两处外部表面（跳出 App 后用户看到的页面）：

- `url_launcher` 3 处：AI 配置页（外部链接）、关于页（更新下载）、反馈页（邮件/网页）
- 服务端第二个 HTML 页面：`server/lib/src/oauth/as.dart`（OAuth 授权服务器页），与 `consent.dart` 同族

## 四、冻结清单（v1.0，未归类 Surface = 0）

四类归属：**F = 第一方 UI（必须有目标模型）**、**N = 系统原生 UI（保留系统样式）**、**X = 外部 Surface（不纳入收敛）**、**D = 删除**。

### 4.1 删除（D）

| Surface | 依据 |
|---|---|
| `AboutPage` + 路由 `/about` + `test/widget/app_flow_test.dart` 中关于页用例 | 无入口 + 与 `AboutSection` 双实现（用户裁定 B） |
| `CalendarsPage` + 路由 `/calendars` + `test/ui/pages/calendar/calendars_page_test.dart` | 无入口 + 与 `CalendarSettingsSection` 双实现（用户裁定 B） |
| 路由 `/event/edit` | 无入口；事件编辑走详情页编辑态，`EventFormPage` 仍由 `/event/new` 使用 |
| 6 个不可达 UI 文件（已于 `93947ff` 删除） | import 可达性闭包外 |

### 4.2 第一方 UI（F）与目标模型

| Surface | 形态/状态 | 目标模型 | 当前偏差 | Owner |
|---|---|---|---|---|
| Today 页 | 桌面·手机 × 8 个展开态 | P1（`todayPage`） | 已收敛；日期/时间选择仍为 Material | A1 |
| Todo 页 | 桌面·手机 × 模式/分组/筛选 | P2（`todoPage`） | 已收敛；日期/时间选择仍为 Material | A1 |
| Capture 条 / 展开面板 | 桌面锚定 / 手机模态 | P1 子模型（`capturePanel` `captureBar`） | 已收敛 | A1 |
| Todo 详情 | 只读/编辑/保存失败 | P4（`detailDrawer`） | 未保存确认是 Material `AlertDialog` | A1 |
| 搜索 / 命令浮层 | 浮层 + 全页两宿主 | P10（`commandOverlay`） | 已收敛 | A1 |
| 快速添加页 | 深链进入 | P9（`detailEditor`） | 已收敛 | A1 |
| 日历（月/周/日） | 三视图 × 悬停/空态 | P3（`calendarPage`） | 已收敛 | A2 |
| 日历时间槽 sheet | 手机/桌面 | P3 子模型（`slotCapture`） | 仍是三动作启动器（已知 P2） | A2 |
| 设置主区 + 12 个 section | 桌面侧栏 / 手机列表 | P5/P6/P7 | 已收敛；选择器用 `SimpleDialog` | A2 |
| 标签 | 设置内嵌 + 路由 | P6 | 已收敛 | A2 |
| 回收站 | 设置内嵌 + 路由 | P6 | 已收敛 | A2 |
| 关于 | 设置内嵌 | P6 | 已收敛（`AboutSection`） | A2 |
| 反馈 | 设置内嵌入口（**本轮补接**） | P7 | 路由存在但入口唯一来源是被删的关于页 → 需从 `AboutSection` 接入 | A2 |
| AI 对话 | 桌面·手机 | P8（内容页） | 已收敛 | A2 |
| 事件表单 / 详情 | 桌面·手机 × 编辑态 | P9 / P4 | 详情未保存确认是 Material `AlertDialog` | A2 |
| 共享弹层家族（DsDialog / SpecDelete… / Sheet chrome） | 全部 | 共享层 | `SimpleDialog` 1 处、`AlertDialog` 3 处 | A2 |
| 日期 / 时间选择器 | 全部入口（14 处） | `datePickerPanel` / `timeBlocks` | **全部是 Material `showDatePicker` / `showTimePicker`** | A1 |
| 消息提示 | 全部 | `.toast` | 108 处直连 SnackBar（样式未统一） | A1 |
| 原生小组件（iOS/macOS/Android） | 3 种 widget × 2–3 尺寸 × 空/暗 | P12 | 旧 `AppColors` 调色板；iOS/macOS 93% 重复 | A3 |
| 服务端 OAuth 同意页 / 授权页 | 浏览器 | P13（服务端页面契约，P2） | 独立 HTML 样式，不在冻结规格内 | 待排 |

### 4.3 系统原生 UI（N，保留系统样式）

文件选择/保存（导入导出）、通知权限弹窗、分享与邮件壳、App 图标与启动图、macOS 菜单栏框架、Android 小组件选择器容器。
**只收敛其中的"第一方内容"**（通知文案与动作、菜单项文案、widget 描述），不重画系统控件。

### 4.4 外部 Surface（X，不纳入收敛）

`url_launcher` 3 处（AI 配置外链、关于页下载、反馈页邮件/网页）、MCP 客户端自身界面、CLI 输出。

### 4.5 覆盖来源核对

| 来源 | 已归类 |
|---|---|
| Router 16 条 | ✅（含 4 条删除） |
| Dialog / Sheet / Overlay / Popover | ✅ |
| responsive 分支（720/1000/1180） | ✅ |
| 状态（loading/empty/error/editing/detail/expanded） | ✅ |
| iOS/macOS/Android Widget | ✅ P12 |
| macOS menu / 通知 | ✅ N |
| App icon / launch | ✅ N |
| 服务端第一方 HTML | ✅ P13（P2） |
| deep link 可进入页面（`/quick-add`、`/event/detail`、`/todo/detail`、`/`） | ✅ F |

**未归类 Surface = 0。清单冻结，不再扩大审计范围。**

### 4.6 Ownership

- **A1**（Claude 实施线程 1）：Today / Todo / Capture / Todo Detail / Search / 快速添加 / **日期时间选择器共享层** / **toast 共享层**
- **A2**（Claude 实施线程 2）：Calendar / Settings / Tags / Trash / About / Feedback / AI / Event 表单与详情 / 共享弹层
- **A3**（Claude 实施线程 3）：原生小组件（iOS / macOS / Android）
- **R1–R4**（只读复核）：每批结束后独立对拍，不写代码

> 说明：本机 T3 的 antigravity provider 可用，但 Windows 两侧工作区没有本 worktree 的检出，无法直接改这里的文件；
> 本轮实施由本地 Claude 线程按同一 ownership 执行，Antigravity 不参与，避免出现两份不同步的代码。


**结论**：`today_page.dart` 一个文件承载 ≥8 个状态 × 2 形态；`todo_detail` 与 `event_detail` 共用同一套 8 个状态开关——后者是前者的复制。这两个事实比"64 个文件里 51 个有违规"有意义得多。

## 五、验收口径（本文件定死，后续照此）

### 5.1 本轮已通过的条目

| 条目 | 证据 |
|---|---|
| 孤儿/双实现 | `AboutPage`、`CalendarsPage` 及 `/about`、`/calendars`、`/event/edit` 三条路由已删；`lib/` 内零引用；`grep class AboutPage\|class CalendarsPage` = 0 |
| 反馈入口 | `AboutSection` 新增一行 → `/feedback`（复用 `l.reportIssue`） |
| Material 弹层 | `AlertDialog`/`SimpleDialog` 在 A2 范围清零（`event_detail`、`import_export`、`settings_ui`） |
| 小组件色板 | iOS/macOS/Android 全部换到 `SpecTokens` 值；旧值 grep 仅剩 `ic_launcher_background`（品牌图标，P2）；两份 Swift diff 89→58 行 |
| toast | 除 A1 三个文件与实现本身外，直连 `showSnackBar` 清零；红底场景用新增的 `showSpecToast(danger: true)` 恢复 |
| 日期/时间选择器 | Material 选择器清零；`spec_pickers.dart` 按 `datePickerPanel` / `planPicker` 重画；42 格日格用 `FocusableTap`（Enter/Space 可激活，不再退回鼠标专用） |
| 机器守卫 | `test/architecture/ui_surface_guard_test.dart` 六条断言：孤儿路由与页面、legacy 组件复活、Material 对话框族、toast 出口、原生退役色（全 `res/` 递归）、modal sheet 出处白名单；每条均已注入违规验证可失败 |
| 全量门禁（阶段性） | `dart analyze .` 0 issue；`flutter test` **+1033 全绿**（跨午夜时间边界用例已由 `fec5507` 修根因，非豁免） |

### 5.2 本轮裁定

| # | 决定 | 理由 |
|---|---|---|
| R7 | `undo_bar.dart` 是规格 `.undo-bar`/`.m-undo` 表面，**不是**待统一的散落 SnackBar；不得合并进 toast | A2 曾把它重写成 toast，丢了规格几何与 `undo-bar`/`undo-bar-content` key，6 个测试红；已回滚并在门禁中豁免 |
| R8 | 时间选择的目标模型 = 规格 `planPicker` 的内联 `<input type="time">` 方框（开始/结束 + 时长读数），**不是**时钟表盘；日期 = `datePickerPanel` 的 320px popover + 42 格月历 | 规格本身用的是系统原生 `input type`，没有自定义表盘；照 Material 做会再引入异族 |
| R9 | `ic_launcher_background #2D4F7C` 保持不动 | 品牌资产，改图标影响商店素材，不属于本轮 |


### 5.3 通用口径

1. 每个 Surface 在矩阵里必须有：出现条件、形态、状态集合、页面模型、当前偏离。
2. `页面模型` 列只允许出现在词表里的代号；写"专属"必须附带一行合同。
3. 界面全集 = 16 条路由 ∪ 弹层调用点 ∪ 页面内状态分支 ∪ responsive 分支；任何新增界面必须补进本表。
4. 修改只按"偏离"列驱动，不按"裸色值/字号数量"驱动。
5. Guard 只守硬禁止项：直接 `AlertDialog`、直接 `showModalBottomSheet`（清单外的）、页面自建第二套顶栏/主按钮、legacy 组件复活。已落地为机器断言的：`AlertDialog`/`SimpleDialog`、`showModalBottomSheet` 出处白名单、legacy 组件/页面名复活、toast 出口、原生组件退役色（`res/` 全递归）。"页面自建第二套顶栏/主按钮"没有稳定机器判据，由审查者按本表逐页核对。

### 5.4 独立审查记录（2026-11-24）

审查者基于 `fec5507` 独立重跑门禁（`dart analyze .` 0 issue；子集 +290；全量 +1033；`skip:` 与 `--no-fatal` 均无）。裁定 **ACCEPT-WITH-FIXES**。

| 级别 | 发现 | 处置 |
|---|---|---|
| P1 | 日期选择器 42 格原为 `Semantics+MouseRegion+GestureDetector`，键盘无法聚焦/激活，较被替换的 Material 选择器是退步 | 已改为 `FocusableTap`（Tab 可达、Enter/Space 激活、焦点环可见），`spec_pickers_test` 绿 |
| P2 | 守卫只扫 `res/values`、`res/layout`，漏 `values-night` 等目录；§5.3 声称的 sheet/顶栏/legacy 三项未落地 | 色板扫描改为 `res/` 全递归；新增 legacy 复活与 sheet 白名单两条断言，均注入违规证伪；顶栏项按 §5.3.5 归人工审查 |
| P3 | toast 默认 2.2s + 每次 `hideCurrentSnackBar`，与旧 SnackBar 的 4s 排队语义不同 | 属规格 `setToast` 的 2200ms，记录为有意变更；未加测试 |
| ~~P3~~ | 移动端时间选择仍走 Cupertino 滚轮 sheet（`wheel_time_picker.dart`），R8 的"内联方框"只覆盖桌面 | **已修**：`wheel_time_picker.dart` 删除，`pickDeadline`/`pickDateTime` 全部平台走 `showSpecTimePicker` 内联方框；`todo_create_deadline_test` 同步断言 `SpecTimePickerDialog` |
| P3 | 选择器文案由 Material 的 "Select date/Time" 换为 app 自有 `pickDateHint`/`dueTime` | 正是收敛目的（消除第三套语言），保留 |
| ~~P3~~ | `reportIssue` 行无测试；`event_detail` 的 discard 对话框多了 `AnimationStyle.noAnimation`，`todo_detail` 没有 | **已修**：`about_section_test` 断言反馈行；`todo_detail` 的 discard 补同款 `AnimationStyle.noAnimation`，两处对话框一致 |

### 5.5 真机目检记录（2026-11-24 会话末，macOS release 构建 f045492）

在真实启动的 release 包上逐屏截图（非测试、非 golden），复用 App 自身 deep link 与 VM Service 导航；带 `screencapture` 存证。

| Surface | 结果 | 备注 |
|---|---|---|
| Today（桌面） | PASS | 顶栏 今天/待办/日历、过期/无日期分组、右侧时间轴红 now 线、浮动捕获条 |
| Todo（桌面） | PASS | 2026年11月 月条、按日期、无日期分组、筛选/捕获条 |
| Calendar 周（桌面） | PASS | 全天/截止泳道、红色今日头、空态文案、红 now 线 |
| Capture（快速添加 Dialog） | PASS | 纸面卡片、标题输入、保存/添加待办/取消 + esc 提示 |
| Detail（Todo 详情） | PASS | 只读摘要、已完成行、截止/计划/重复/提醒、取消/移到回收站 |
| Settings | PASS | 左侧 9 分区 + 右侧概览 6 行（与规格 `settingsPage('home')` 一致） |
| Search 命令浮层 | PASS | 最近结果 + 动作，类型标签右对齐，底部键位提示 |
| Tags / Trash / AI 空态 | PASS | 管理标签空态、回收站行内恢复/删除、AI 未配置空态 |
| 时间槽 Sheet | **FAIL → 已修** | 三动作启动器（已知 P2）的主行动原填 `ds.primary`（旧陶土 #C2410C），规格 `.btn.primary` 是墨色；已改 `SpecTokens.ink`，并暴露根因见下 |
| 时间槽 Sheet（复验 `b6bbf22`） | PASS | 实拍确认主行动为墨色填充、白字、白图标，与规格 `.cp-actions .btn.primary` 一致 |
| Detail 已完成行的分隔条（复验 `b6bbf22`） | PASS | 由旧陶土改为墨色（`ds.primary` 现在解析为 ink）；「移到回收站」仍为红，符合规格的破坏性语义 |
| 内联时间方框（复验 `5fc8923`） | PASS | 实拍「具体时间」卡片：两个数字输入框 09 : 52、取消/确定，墨色主按钮；不是滚轮、不是表盘 |
| 移动端 Today（Android 15 模拟器） | PASS | 同为纸白页 + 四档底栏 + 浮动捕获条，红 only 用于 now 线与逾期 |
| Android 原生小组件（模拟器桌面实拍） | PASS | 桌面上两个小组件（日期型 / 今天型）均为纯白卡片、墨色正文、红色 `+`、灰色空心圆，`values-night` 未受影响 |
| iOS/macOS 原生小组件 | 未目检 | 本机无法渲染 WidgetKit 表面；已由色板守卫断言覆盖（退役色为 0），仅剩系统宿主差异 |
| 分享 / 权限 / 系统页 | 未目检 | 属系统原生 UI，按 §4.3 保留系统样式 |

**目检暴露的根因（P1 级，已立案）**：`DsColors.light` 仍由旧调色板 `AppColors` 构造（`#FCFCFA / #F7F7F2 / #E8E7E1 / #3F413A / #C2410C`），80 处 `ds.primary` 消费点因此继续画旧值；守卫此前只覆盖原生组件目录，Dart 侧无禁线。修复方向：把 `DsColors` 映射到 `SpecTokens`（primary=墨、danger=红、warm/warn=琥珀），表内补 Dart 侧退役色禁线。状态见 5.6。

### 5.6 收口状态（2026-11-24）

| 门 | 状态 |
|---|---|
| 未归类 Surface = 0 / 未处理第一方 = 0 | 通过（§4） |
| orphan UI = 0 / duplicate UI = 0 | 通过（§4.1，守卫断言可失败） |
| P0 = 0 | 通过 |
| P1 = 0 | 本轮 P1（日期格键盘、palette 根因）均已修（palette 修复在 `ui/palette-root`） |
| `dart analyze .` | 0 issue |
| `flutter test` | `5fc8923`：1039 全绿、skipped=0 |
| release build | `5fc8923` macOS 63.0MB 构建成功；debug APK 装到 Android 15 模拟器实机跑步 |
| CI（PR #113） | f045492 全 9 个 job 绿（test 必需检查通过） |
| 代表页面目检 | 见 5.5（桌面 9 屏 + 移动端 Today + Android 原生小组件，均为 release/真机实拍） |
