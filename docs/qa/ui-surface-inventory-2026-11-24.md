# UI 表面全集与残留审计（2026-11-24）

> 触发：用户反馈「旧的残留还是很多，你根本没扫描清楚；HTML 没定义的页面你定义全了吗」。
> 结论先行：上一轮的"穷举"是**规格 → App 单向**枚举（127 条渲染项），只能证明"HTML 画过的东西 App 都有"，
> 无法证明"App 里所有东西都被定义过"，也发现不了**死代码残留**。本文件改用**双向闭集**。

## 一、为什么上一轮会漏

| 上一轮做法 | 结构性缺陷 |
|---|---|
| 以 `dayspark-spec.html` 的渲染函数为清单逐条对拍 | 只能覆盖规格画过的面；规格没画的页面（标签、日历管理、AI、关于、反馈、事件表单）根本没有条目可对 |
| 对"没有独立渲染函数"的页面用"同类家族类比"判 PASS/PARTIAL | 类比不是定义。判 PASS 之后没人再回来重新定义，残留就此合法化 |
| 只扫 `lib/ui` 里"看得见"的文件 | 没有做 import 可达性，**编译进去但没人用的旧组件**不在任何清单里 |
| 以人工阅读代码判断"是否用了新设计系统" | 判断依赖读代码的人，换个人结论会变；而且 import 了设计系统 ≠ 视觉上用对了 |

## 二、最底层的方法：三个闭集 + 一次像素兜底

一个界面只能由两类东西产生，除此之外不存在第三种：

1. **路由表**（`lib/core/router/app_router.dart` 的 `path` 全集）—— 16 条。
2. **运行时表面**（`showDialog` / `showModalBottomSheet` / `showMenu` / `OverlayEntry` / `showGeneralDialog` / `showAdaptiveDialog` 的调用点全集）—— 26 个文件。

所以 **界面全集 = 路由 ∪ 运行时表面**，是可以用 grep 一次算完的有限集，不需要"想还有没有别的页面"。
在此之上再做三层机器判定：

3. **文件全集 = 从 `lib/main.dart` 出发的 import 可达性闭包**。不可达 = 死残留（这份残留一定还编译进产物里）。
4. **定义映射**：把规格 HTML 里的 174 个渲染函数当作"定义源"。界面全集里每一条都必须能落到一个具体函数名；
   落不到 = 规格未定义，必须**裁定**（补定义 / 明确不适用），不能默默放过。
5. **像素兜底**：只对上面这个有限集逐条截图对拍（路由可直接 `go(path)` 驱动），人工只看集合内的条目。

只有第 5 层是人眼，前 4 层是机器可复算的。这就是"绝对"的来源：不是"我这次看得仔细"，而是**集合是穷举的、规则是机器的、可重复执行**。

## 三、本轮机器扫描结果

### 3.1 死残留（不可达，已删）

`main.dart` 可达性闭包外、且全仓库零引用的 UI 文件：

- `lib/ui/pages/settings/settings_sections/todos_section.dart`
- `lib/ui/shell/workspace_sidebar.dart`
- `lib/ui/widgets/schedule/day_strip.dart`
- `lib/ui/widgets/schedule/schedule_actions.dart`
- `lib/ui/widgets/settings_group.dart`
- `lib/ui/widgets/todo/todo_list_tile.dart`（连同其孤立测试 `test/ui/widgets/todo/todo_list_tile_test.dart`）

已 `git rm`，`dart analyze .` 0 issue。

### 3.2 界面全集与规格定义覆盖

| 路由 | 页面文件 | 规格锚 | 判定 |
|---|---|---|---|
| `/` | `shell/workspace_scaffold.dart`、`pages/home/home_page.dart` | `todayPage` `mobileShell` `shell` | 有定义 |
| `/quick-add` | `pages/todo/quick_add_page.dart` | `capturePanel` `captureBar`（无独立页） | **部分** |
| `/search` | `pages/search/search_page.dart` | `commandOverlay` `cmdRow` `filterResultTodos`（无独立页） | **部分** |
| `/settings` | `pages/settings/settings_page.dart` + 9 个 section | `settingsPage` `settingsContent` `mobileSettings` | 有定义；**7 个子 section 无逐条定义** |
| `/todo/new` `/todo/edit` | `pages/todo/todo_form_page.dart` | `capturePanel` / `detailEditor`（表单页无独立定义） | **部分** |
| `/todo/detail` | `pages/todo/todo_detail_page.dart` | `detailDrawer` `detailSource` | 有定义 |
| `/event/new` `/event/edit` | `pages/event/event_form_page.dart` | 无 | **未定义** |
| `/event/detail` | `pages/event/event_detail_page.dart` | `detailDrawer` | 有定义 |
| `/tags` | `pages/tags/tags_page.dart` | 无 | **未定义** |
| `/calendars` | `pages/calendar/calendars_page.dart` | 无（`calOptions` 只是选择器数据） | **未定义** |
| `/ai-chat` | `pages/ai_chat/ai_chat_page.dart` | 无 | **未定义** |
| `/about` | `pages/about/about_page.dart` | 无 | **未定义** |
| `/trash` | `pages/trash/trash_page.dart` | `trashItems` `trashTarget` `trashCount` | 有定义 |
| `/feedback` | `pages/feedback/feedback_page.dart` | 无 | **未定义** |

**16 条路由：5 条有页面级定义，5 条只有部件级定义，6 条完全未定义。** 上一轮把这些未定义/部分定义的页按"同类家族"判为 PASS/PARTIAL，是审计漏洞。

### 3.3 运行时表面

26 个文件创建弹层，其中共享原语已覆盖：`SpecDeleteConfirmDialog`、`SpecPlanPickerDialog`、`calendar_filter_sheet`、`calendar_slot_sheet`、`todo_occurrence_picker_sheet`、`legacy_recurrence_dialog`、`month_year_picker`、`wheel_time_picker`、`calendar_picker`、`ai_config_dialog`、`spec_drawer_overlay`。
**未收敛的一类**：直接 `SnackBar(` 165 处 / 26 文件，而规格只定义了 `.toast` 一种样式（bottom 84、11px、radius 6、深色 pill）。需要统一到一个 `showSpecToast`。

### 3.4 组件语言残留

可达 UI 文件中不在规格设计系统 import 闭包内的：`home/day_agenda.dart`、`shell/workspace_navigation.dart`、`widgets/attachment_list.dart`、`widgets/calendar/{calendar_deadline_lane,calendar_filter_sheet,calendar_shared,view_switcher}.dart`、`widgets/color_swatch_grid.dart`、`widgets/schedule/schedule_row.dart`、`pages/calendar/frozen_calendar_colors.dart`（调色板定义，属允许）。
其中 `a2_composer.dart` 仍 import 旧 `AppColors`。

裸值统计（可达 UI 文件）：`Color(0x`/`Colors.` 186 处、`fontSize:` 硬编码 293 处、越界圆角 6 处。

## 四、裁定

| # | 决定 | 理由 |
|---|---|---|
| S1 | 6 条完全未定义路由（`/tags` `/calendars` `/ai-chat` `/about` `/feedback` `/event/new`）按**同一设计系统**补定义，不新造第四套语言 | 规格是"视觉方向"，不是"穷尽清单"；未定义页的默认答案就是同一家族 |
| S2 | 未定义页的定义写进 `SPEC.md` §2 的"表面清单"，并在本文件维护路由映射 | 否则下一轮审计还会退回"类比判定" |
| S3 | 6 个死文件直接删除，不保留 | 零引用，且会误导后续读者以为有两套实现 |
| S4 | 165 处 `SnackBar` 统一收敛到 `showSpecToast`，记 P1 | 消息提示是全 App 最高频表面，样式不一致最显眼 |
| S5 | 上述规则做成常驻 guard test（可达性 / 路由定义映射 / 裸色值 / 直连 SnackBar） | 一次性检查只能证明"这次干净"，门禁才能保证"以后不脏" |

## 五、门禁（待落地为测试）

1. `ui_reachability_guard_test`：`lib/ui` 下任何文件必须从 `main.dart` 可达，否则红。
2. `ui_surface_registry_test`：路由表每条必须在 `SPEC.md` 表面清单里有映射，新增路由未登记则红。
3. `ui_token_guard_test`：`lib/ui/pages`、`lib/ui/widgets`、`lib/ui/shell` 禁止裸 `Color(0x`、禁止越界 `circular()`。
4. `ui_toast_guard_test`：除 toast 实现文件外，禁止直接 `SnackBar(`。

## 六、子页家族定义（HTML 未覆盖的 6 条路由）

这 6 条路由在冻结规格里没有独立渲染函数。裁定（S1/S2）：不新造语言，按**同一家族的显式定义**收敛。
定义源是已有的共享原语，不引入任何新组件：

**外壳（全部 6 条一致）**
- `WorkspacePage`：54px 顶栏，返回 `CupertinoIcons.back`，标题 `DsText`，右侧主操作用 `PageSaveButton`（实心黑）或 `DsButton`。
- 正文左右留白 24（窄）/ 32（宽），分节用 `DsSectionLabel`。

**行与分组**
- 设置类行一律 `DsGroup` + `DsSettingRow`（标签左、值/开关右、`DsHairline` 分隔）。
- 列表类行一律 `DsRow`；空态 `DsEmpty`；错误态 `SpecErrorState`。
- 禁止 `ListTile`、`Card`、`ElevatedButton`（现有 `a2.dart` 内的兼容封装除外）。

**弹层**
- 确认类 `SpecDeleteConfirmDialog`；表单类 `DsDialog`；底部 sheet `DsSheetChrome`；消息 `showSpecToast`（本轮新增，规格 `.toast`）。

**逐条定义**

| 路由 | 定义 |
|---|---|
| `/tags` | 标签列表 = `DsGroup` + `DsSettingRow`（色点 + 名称 + 计数）；新建/改名内联 `DsTextField` 行；删除 `SpecDeleteConfirmDialog`；空态 `DsEmpty` |
| `/calendars` | 日历列表 = `DsGroup` + `DsSettingRow`（色点 + 名称 + 可见开关 + 删除）；新建内联 `DsTextField` 行；删除 `SpecDeleteConfirmDialog` |
| `/ai-chat` | 消息区 `SpecTokens.paper/ink` 气泡 + 输入区 `DsTextField`；工具条 `DsIconButton`；模型配置走 `DsDialog`；消息反馈 `showSpecToast` |
| `/about` | 信息行 = `DsGroup` + `DsSettingRow`；版本行只显示真实版本（不填默认值）；更新入口 `DsButton` |
| `/feedback` | 表单 = `DsTextField` + `DsButton`；提交结果 `showSpecToast`；副本文案沿用 l10n |
| `/event/new` `/event/edit` | 与 todo 表单同族：`DsSectionLabel` 分节 + `DsRow`/`DsSettingRow` 字段行 + `DsTextField`；保存 `PageSaveButton`；删除 `SpecDeleteConfirmDialog` |

**不变量（每条都要过）**
1. 无裸 `Color(0x` / `Colors.`（令牌文件除外）。
2. 无硬编码 `fontSize:`（用 `SpecTokens.t*`）。
3. 无直接 `SnackBar(`（用 `showSpecToast`）。
4. 可交互元素用 `FocusableTap`，触摸目标 ≥ 48×48。
5. 所有用户可见文案走 l10n，中英双语同步。
