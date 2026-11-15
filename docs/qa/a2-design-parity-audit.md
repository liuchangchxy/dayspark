# A″ 设计稿 vs 实现 — 逐元素对拍审计

> **状态：已收口（2026-11-16，v0.34.0）。** 本文是 v0.34.0 的取证记录，基线为 `main @ 7f17af4`（v0.33.0+33）。5 个 P0 与其中可执行的 P1/P2 已在本轮修复，逐项结果见 `docs/qa/ux-convergence-2026-11-15.md`。文中「需拍板」一类字样是当时的现场记录，裁定结果见该文档 §五：**P0-2 按 SPEC 直接新建 Event，设计说明 §7 的冲突文字已删**。

- 对拍对象：`design/opendesign/a2-visual-rebase-2026-11-15/`（shared.css + screens-today/todo/calendar/desktop.html）
- 实现基线：`main @ 7f17af4`（v0.33.0+33）
- 方法：五个只读 subagent 分区取证，设计侧读 CSS 精确值，实现侧读源码与 l10n，逐元素给「设计值 vs 实现值 + file:line」
- 截图交叉验证：`build/a2-shots/` 生成于 12:48，早于提交 13:11；凡仅截图不符者已标「疑似截图过期」

## 总计

| 区域 | P0 | P1 | P2 |
|---|---|---|---|
| 今天 01–03 / M15 / DARK | 0 | 9 | 10 |
| 待办 04–08 | 1 | 4 | 12 |
| Composer 09–11 + 槽交接 | 1 | 5 | 8 |
| 日历 12–14 | 2 | 2 | 9 |
| 桌面 16 + 全局令牌 | 1 | 4 | 15 |
| **合计** | **5** | **24** | **54** |

令牌侧结论：33 个浅色令牌、暗色全套、字阶 11/12/13/15/17/20/24/26、圆角 6/8/10/18、行高与时间槽宽**一一相等**。问题不在 token，在**页面结构与组件实现**。

---

## P0（一眼看出不是同一套界面）

### P0-1 桌面详情面 = 整张编辑表单，主次动作对调
- 设计：标题 20/600 + 关闭；5 条 KV（截止/计划执行/提醒/所属日历/优先级）+ 备注；底部**两个**按钮，主 = 实心「安排到 11/15」，次 = ghost「完成」（desktop.html:199-219，shared.css:916-918，note:225）
- 实现：三大段编辑区 + 执行计划/重复/提醒/日历/优先级/标签/备注/子任务/附件；页脚 4 按钮「标记完成/安排/编辑/移动回收站」，实心主按钮是 `markComplete`（todo_detail_page.dart:249-306, 650-673）

### P0-2 日历 FAB 跳过三动作菜单，直接建事件
- 设计：FAB 是此页唯一创建入口，点击弹 14 的三动作 sheet（design-notes.md:80, shared.css:764-776, screens-calendar.html:13）
- 实现：`A2Fab.onPressed → onCreateAtDay` → `push('/event/new?start=…&end=…')`（a2_calendar_page.dart:319-324, home_page.dart:555-575）；lib 内无 `.fab-menu` 实现
- **裁定（2026-11-16）：按 SPEC，直接新建 Event。** 三动作菜单只属于「具体时间槽」场景；设计 §7 的冲突文字已删除（仓库内 `design-notes.md` 与 OpenDesign 项目两处均已改），约束见 `docs/CONSTRAINTS.md`。

### P0-3 时间槽 sheet 仍是旧 Material 表单
- 设计 `.slot-sheet`：18 圆角 + surface + 1px 顶线 + shadow-sheet；grip 36×4 surface-3；`.sctx` 20/600 + 5px primary 点，文案「11月15日 · 周日 · 18:00–19:00」；`.srow` padding 10/0 + 发丝底；20px ink-2 图标；`.st` 15/600 + `.sd` 15/400 ink-2；第二行右侧 14px chevron
- 实现：圆角 16；grip 用 onSurfaceVariant@30%；头部 `formatTaskAllocationRange` →「2026-11-15  18:00 – 19:00」（ISO + 双空格），无圆点；三个原生 `ListTile`（标题落到 bodyLarge 15/**400**），无发丝、无 chevron；第三行文案「新建待办」而非「新建并安排」（calendar_slot_sheet.dart:42-44, 104-152；app_zh.arb:660）
- 该文件最后一次改动是 #75，7f17af4 未触碰

### P0-4 「新建并安排」打开的是全屏表单，composer 预填是死代码
- 设计：该入口是唯一会预填时段的 composer 入口（screens-calendar.html:366，board 10 即预填态）
- 实现：`onCreateTodoHere → push('/todo/new?start=…&end=…')` → 全屏 `TodoFormPage`；`A2ComposerSheet.initialStart/initialEnd` 无任何生产调用者（home_page.dart:610-612, app_router.dart:357-387, a2_composer.dart:71-74,104-105）

### P0-5 日期条相对日期取绝对值
- 设计：「2 天后 · 2026」（screens-todo.html:284）
- 实现：`l.inDaysCount(_daysBetween(day, today).abs())` → 浏览过去日期显示「5 天后」（a2_todo_page.dart:486；app_zh.arb:808）

---

## P1（明显视觉/语义偏差）

### 今天 01–03（9）
| # | 差在哪 | 设计 | 实现 |
|---|---|---|---|
| T1 | 「现在」节标签与圆点颜色对调 | 标签 ink-3 / 点 primary（CSS:427-431） | 标签 primary / 点 faint（today_page.dart:498-510, a2.dart:221-239） |
| T2 | 「今天截止」节圆点没跟 warn | 点 #7d5416（HTML:79） | 点恒 faint（a2.dart:237） |
| T3 | 节头计数缺「项」且颜色错 | 「1 项」「2 项」继承 warn/danger | 淡灰纯数字（a2.dart:255-268, today_page.dart:544,558） |
| T4 | 纯截止块缺「未安排执行时段」 | `截止 18:00 · 未安排执行时段 [去安排]`（HTML:87） | 「截止今天 18:00」+ chip；`l.noExecutionSlot` 全项目 0 引用（today_page.dart:686-745；app_zh.arb:774） |
| T5 | 逾期时间列缺「昨天」 | 时间列「昨天」，meta「截止 昨天 18:00」（HTML:106,112） | 一律 `MMd`→「11/14」，meta「截止 18:00」（today_page.dart:600-603,709-728） |
| T6 | 多出第 5 节「今日早前」 | 只有 现在/接下来/今天截止/已逾期（HTML:13，SPEC:70-74） | 追加 `A2GroupHead(l.actionEarlierToday)`（today_page.dart:492,569-580） |
| T7 | 空状态多出时钟徽 | `.empty .eico{display:none}`（CSS:655） | 56×56 圆 + 24px 图标（today_page.dart:323-327, a2.dart:777-788） |
| T8 | 捕获行非整行可点 | 44px 命中区 = 整行（design-notes.md:30） | 只有 TextField 可聚焦（a2.dart:614-665） |
| T9 | 新捕获行没置顶 | 顶部即时插入新行（design-notes.md:29，HTML:281-292） | preview 沿用 provider 顺序 + take(3)，新行可能被截掉（today_page.dart:241-245） |

### 待办 04–08（4）
| # | 差在哪 | 设计 | 实现 |
|---|---|---|---|
| D1 | 完成行标题过浅 | ink-3 #6A6D64（CSS:345） | doneInk #A5A79D（a2.dart:517, app_colors.dart:43） |
| D2 | 事件行仍占 48px 勾选槽 | 无 `.cbx`，文字 x=12（HTML:238-244） | 48 占位 + 12 gap → 文字 x=72（a2.dart:499-500, a2_todo_page.dart:816-836） |
| D3 | 缺「未安排执行时段」meta | `截止 11/14 18:00 · 未安排执行时段`（work 色，HTML:139） | `_allMeta` 无该分支；`l.noExecutionSlot` 0 引用（a2_todo_page.dart:887-924） |
| D4 | 表头文案 | 「全部」（HTML:111） | 「全部待办 / All Tasks」（a2_todo_page.dart:280） |

### Composer 09–11（5）
| # | 差在哪 | 设计 | 实现 |
|---|---|---|---|
| C1 | 主按钮与「…」左右镜像 | save 右对齐、ghost 最右（CSS:621-634） | 「…」在最左（a2_composer.dart:566-600） |
| C2 | 选了时段无法清除 | 同一控件两个可逆状态（HTML:493-496,575-578） | `_start/_end` 无置空路径（a2_composer.dart:104-186,711-714） |
| C3 | 计划执行值缺日期 | 「11/17 14:00–15:00」 | 「14:00–15:00」（a2_composer.dart:122-123,687） |
| C4 | 截止行设置后整行加粗 | due 只改色，保持 400（CSS:598-601） | due 也套 w600（a2_composer.dart:882,895） |
| C5 | 候选待办列表未筛「未安排」、未按截止置顶 | 当天未安排 + 带截止最前（screens-calendar.html:366） | `getSchedulableTodos()` 仅排除完成/取消、按 sortOrder（todos_dao.dart:112-121） |

### 日历 12–14（2）
| # | 差在哪 | 设计 | 实现 |
|---|---|---|---|
| K1 | FAB 高 56px，压在倒数第二行 | 悬于末行右下角，底边距 dock 顶 16（CSS:756-763, design-notes.md:79,135） | `Positioned(right:16, bottom:72)` → 距 dock 顶 72（a2.dart:1029-1030） |
| K2 | 日视图计划执行块第二行显示日历名 | 「16:00–17:00 · 截止 18:00」（screens-calendar.html:255, design-notes.md:52-53） | 「16:00 – 17:00 · Work」（a2_calendar_views.dart:64-83,1168-1170） |

### 桌面 16 + 令牌（4）
| # | 差在哪 | 设计 | 实现 |
|---|---|---|---|
| W1 | hover 150ms 不开详情面、无 Esc 关闭 | hover 150ms 滑入，Esc 关闭（desktop.html:225） | hover 只换底色，需点击；全库无详情面 Escape 绑定（a2_todo_page.dart:838-848, home_page.dart:763-772） |
| W2 | 待办卡多出 56px 标题带 | 卡片直接以 group-head 开始（desktop.html:169-171） | `_cardHead` 56 高 + 20/600 标题（a2_todo_page.dart:229,325-365） |
| W3 | 桌面出现手机式底部条 | 桌面无捕获行/FAB（desktop.html:13,197-221） | 未安排/全部 = `A2CaptureBar` 48；按日期 = `A2PlanBar` 44（a2_todo_page.dart:181,232,554-568） |
| W4 | 未安排组没做「3 行预览 + 还有 N 项」 | 预览 3 行 + 「还有 5 项 · 展开全部」（desktop.html:125-142） | `preview = noDue` 全量渲染，`_showAllRow` 只看带截止项（today_page.dart:384-385,455-458） |

---

## P2（打磨，按区域）

**今天**：时间轴块内字距（event left 8 vs 11；checkbox 后缺 8px）· 捕获行聚焦时仍有 top border（CSS:461）· 空状态文案未强制两行（max-width 280）· workBg #F3F5F6 vs --work-tint #EFF1F3 · 深色事件 tint 0.10 vs 16% + 未用 `eventAccent` · 气泡「刚加入」底色 primary-soft vs surface-2（设计文档自相矛盾）· 未安排组 chevron 默认方向（coding 与 board 相反，截图疑似过期）· 次级灰 faint vs ink3 / 右内距 18 vs 16 / 列表顶部缺 4px · `_recentId` 单值，连续捕获只能保留一条高亮 · 待办 tab 图标 checkmark_circle vs checklist glyph

**待办**：组头「无截止」缺「未安排 ·」前缀 · 全部模式今日到期缺「今天」 · 「截止 今天」多一个空格 · 全部模式完成行缺「已完成」 · 月年标题「2026年11月」缺空格 · 星期行「周一…周日」vs 单字 · 段控 30/26 vs 34/30 · sheet 固定 78% 高，网格下多 180px 空白 · 吸底按钮圆角 6 vs 8 · 未安排/按日期多出筛选图标（且用 slider 而非三横线）· 行尾无日历归属点 · 模式切换是不可见热区

**Composer**：未选时段提示色 ink3 vs primary（设计内部冲突）· 截止+计划并存时提示文案与板相反 · sheet 缺 shadow-sheet · 优先级「无」vs「普通」· 槽 sheet 三动作副标题不带实际时段 · 第三动作文案丢「并安排」 · 备注行不可点

**日历**：头部每视图多一个图标（3 vs 2）· 日头 44 居中 vs 56 左对齐 · 块字号 10.5/9.5 vs 拍板注 12/12（设计自相矛盾）· 计划执行块标题 ink vs ink-2 · 块内时间「16:00 – 17:00」多空格 · 月条纹 ‹› 40×36 vs 32×32 · FAB 无 shadow-1 · 长按事件是拖动改期而非弹 sheet · 「全天」横条设计未定义 · 月格 chip gap 2 vs 3、「+N」非 chip、段控选中多描边、日头 padding 10 vs 12

**桌面**：`.dcontent` 内容列 gap 20 缺失 · 日历卡 width 1240 vs 1200（Padding 在 ConstrainedBox 外）· 组头/行缩进比设计贴边 20px · 卡片无 `padding:16 20 20` · 时间轴 gutter/块内距 · 顶栏日期缺年份（`MMMd` vs `yMMMMd`）+ 间距 8/4 vs 12 · 详情面 KV 行语言（62px 标签列 vs 图标+两端对齐）· 820 内容列约束全库不存在 · 今天页多出「Earlier today」分组（与 T6 同源）· `--r-ctrl` 8 vs 6 · 详情面按钮 36/12 vs 40/13 · 详情面分隔线用 line 而非 line-soft · `--cal-1..4` 归属色未落地（默认 #5F7183）

---

## 设计文档自身的矛盾（不算实现缺陷）

1. 深色主色：board-note 写 `#7ba3d4`，CSS 实际 `#e0703c` → 实现跟 CSS
2. 时间列：design-notes 写 64px，CSS 52px → 实现跟 CSS
3. 空状态字号：notes 17/13，CSS 13/12 → 跟 CSS
4. 捕获行高度：notes 52 / 32 两处，CSS 48 → 跟 CSS
5. 新行高亮：HTML surface-2 vs notes primary-soft
6. 月格选中：CSS surface-2 vs 板面文案 surface-3
7. 块字号：CSS 10.5/9.5 vs 拍板注 12/12
8. 周/日是否该有 FAB：板注说相同，§1 与 ruling 14 说仅月视图
9. 「+N」：板面文案要，ruling 11 明确删掉
10. dock 指示条：notes 两处相反
11. FAB 三动作菜单 vs SPEC 规则 19「`+ 日程` 直接建日程」

## 需要拍板的两处口径冲突

1. **日历 FAB**：设计 §7 / `.fab-menu` 要求弹三动作菜单；SPEC 规则 19 与上轮 Domain 审查裁定「直接建事件」。当前实现按 SPEC。
2. **新捕获行底色**：board 渲染 surface-2；design-notes 写 primary-soft。当前实现 primary-soft。
