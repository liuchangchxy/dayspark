# 冻结规格 UI/UX 收敛 — 复验与裁定（2026-11-23）

> 基线：分支 `ui/converge`（PR #113）。冻结参考：`docs/design/frozen/dayspark-spec.html`。
> 口径：只收结构/行为差异（表面模型、交互模型、数据语义），不收 1–5px、字号、圆角、纯装饰。
> 方法：两名只读复验 agent 按根因簇分区独立读代码对拍（Today/Todo/Capture/Detail 半边；Calendar/Settings/Trash/Data/shell 半边），不改代码、不跑构建。裁定由主控汇总。

## 一、根因簇复验结果

| 簇 | 范围 | 结论 | 依据（锚点见代码） |
|---|---|---|---|
| A | Capture 表面模型 | PARTIAL → 已补 | 桌面为锚定非模态面板，12 态齐；展开面板字段原本只换子态不落值（已修，见 §二）；手机仍走模态 composer（P2） |
| B | Group / expand / more-row | PASS | Inbox/All/Date/Today 分组、截断、more-row 与规格一致 |
| C | Plan / schedule 入口 | PASS | `SpecPlanPickerDialog` 含日期/起止/时长/「当天已有」；行按钮、详情底栏、重复待办按 occurrence 接线 |
| D | Recurrence / occurrence 完成 | PASS | 单一完成入口，自动解析当前 occurrence；撤销保留 occurrence |
| E | Detail / edit | PASS | 只读摘要 + 编辑态；取消回滚草稿；底栏 编辑/安排/删除 |
| F | Navigation / overlay / command | PARTIAL | 详情抽屉/内嵌、顶栏子页清高亮、Ctrl+K 浮层均对；搜索结果仍 push 全页（P2） |
| G | Responsive / mobile | PASS | 720/1000/1180 三档；手机 Today/Todo 结构符合规格 |
| H | Row / meta / content | PASS | 共享 meta（日历点/重复/遗漏/计划）；时间块计划标签 |
| I | 共享 dialog/sheet/popover/undo/filter | PASS | 桌面锚定筛选浮层、共享撤销条、确认框统一；日历筛选仍为模态路由（P2） |
| J | Settings IA / 子页 | PARTIAL | CRUD 子页、标签内联、io-card 三步导入、回收站恢复校验、许可内联；日历管理仍是折叠行、回收站永久删除仍是模态（P2） |
| K | Calendar view / block | PARTIAL | 月格点击不再被 chip 拦截；全天/跨天泳道、密度、重叠、拖动、slot ghost、隐藏横幅齐；跨天条未按月过滤、计划块缺遗漏/逾期样式（P2） |
| L | Data / settings behavior | PARTIAL | 备份恢复走 `RecordScope`、按 syncId 匹配、id 冲突插新行；同 syncId 不同内容未进入冲突清单（P2） |
| M | 视觉令牌 / 色板 | PASS | 日历/标签/设置同一 muted 六色；AI chat 使用 `SpecTokens`，无第二套卡片。三处重复常量声明待合并（P2） |
| N | Keyboard / focus | **FAIL → P1 修复中** | 日历全部可点面与部分 Today/Todo/顶栏控件为裸 `GestureDetector`，Tab 不可达 |
| O | Overdue 按日期 | PASS | 全部逾期判定改为日历日比较，无 `DateTime.now()` 残留 |

### 规格面覆盖（穷举口径）

从 `dayspark-spec.html` 的全部渲染函数逐条对拍（含移动变体），共 **127 条渲染项**：
- 4 条为规格外壳（`renderNav`/`renderVariants`/`render`/`fitFrame`），4 条为规格画廊（`statesPage`/`specSheet`/`mobileStates`/`mobileSpec`），均非产品界面；
- **产品面 119 条：MATCH 113 / PARTIAL 4 / NOT FOUND 2**；**未检查 = 0**。

PARTIAL / NOT FOUND 明细（均为 P2，已记入待办）：
- `slotCapture`（PARTIAL）：时间槽 sheet 是三动作启动器，规格的「就地预填新建」面板未内联。
- `settings-import`（PARTIAL）：有文件/目标日历/行级预览，失败时只给一条 `importFailed`，无「跳过坏行继续」报告。
- `settings-backup`（PARTIAL）：进行中只有不确定进度条，无百分比；完成后才显示文件名与内容。
- `settings-sync-conflict`（PARTIAL）：只有冲突计数行，无逐项 local/server/merge 选择。
- `overdueToolbar`（NOT FOUND）：逾期已分组并排序，但缺「N 项逾期 · 最早 / 按截止排序」工具条。
- `mobileOverlapBand`（NOT FOUND）：手机日视图只排序，无重叠计数带。

## 二、本轮修复

1. **P1 — Capture 展开面板字段不落值**（A）：截止/计划执行/日历/提醒的选择原本只切回展开态。已补 `A2CaptureDraft` + `writeCapturedTodo`（`lib/domain/records/capture_submit.dart`），提交时经一个 `RecordScope` 写 todo / allocation / reminder；子态「选了才落、取消回滚」，提醒无截止按 `reminderNeedsAnchor` 拒绝；Todo 路径失败返回 false，面板保持 save-error 且草稿不丢；手机采集条与桌面草稿隔离。二轮复验 5 项全部 VERIFIED。
2. **P1 — 键盘可达性**（N）：日历月格/时间块/周表头/条目/月行/工具/视图切换，Today 遗漏卡与行内安排，Todo 模式切换/日期条/筛选行，顶栏导航与搜索，全部接入共享 `FocusableTap`（Enter/Space 激活 + 焦点环 + Semantics button）。
3. **P1（返修）— 共享原语读屏点击**：`FocusableTap` 一度把 `SemanticsAction.tap` 从带标签的控件上移除；已改为语义节点始终携带 onTap，`pointerEnabled` 只管指针路由，避免读屏双击无效。
4. **P2 语义回归同批修**：分组头恢复计数播报；`selected` 与标签/按钮/点击合并到同一语义节点；手机行标题只播一次，勾选框播「标记完成」动作。
5. **顺手修**：标签删除弹窗计数重复（「6 6 项」→「6 项」）；Todo 行加稳定 Key；筛选浮层初始焦点/焦点陷阱/Esc 归位；`DsCheck` 与未选中顶栏/手机月格焦点环可见。

## 三、裁定（Rulings）

| # | 决定 | 理由 |
|---|---|---|
| R1 | Capture 面板死控件按 **P1** 处理，不记 P2 | 可点可选却不生效，属「看起来一样、行为不同」，用户会得到无截止的待办 |
| R2 | 手机 capture 仍为模态 composer，**记 P2** | 已有 PopScope 保护草稿，不丢数据；改锚定行程超出本轮停止条件 |
| R3 | 日历键盘可达性按 **P1** 处理 | 桌面平台法则：可交互元素必须键盘可达；共享原语已存在，成本可控 |
| R4 | 搜索结果 push 全页、备份同 syncId 冲突、月跨天条按月过滤等 **记 P2 待办** | 不阻塞 P0/P1，不扩大本轮范围 |
| R5 | 三处重复调色板常量 **记 P2** | 当前值一致，无现网风险；合并需跨文件改动，收益低于回归风险 |
| R6 | `focusable_tap_test` 的语义断言**不阻塞提交** | 定向复验实测：禁用态跳过 Tab、月历弹层打开的断言会失败于旧代码；两条语义断言在新旧代码上都通过，只证明新契约成立、不证明修复前缺失。产品行为已由复验探针独立确认，测试质量记 P2 |

## 四、门禁

- `dart analyze .`：**No issues found**（0）
- `flutter test`：**1039 通过 / 1 失败**；唯一失败为 `test/integration/recurring_action_loop_vertical_test.dart` 的既有时间边界（本地 23:27 时 `now + 2h` 跨天），`TZ=UTC` 下 **+1040 全绿**（CI 以 UTC 运行）
- `flutter build macos --release`：**成功，63.8 MB**
- CI：PR #113，`build-macos` native UI 集成流已修（`f969890` 绿；集成测试对齐新的 shell/行控件/默认视图）
- 肉眼检查：Today / Todo / Calendar 周视图 / Settings / About / Todo 详情 / 快速添加对话框（上一构建，真实窗口）；Capture 展开面板的行为由写入级 widget 测试与复验探针覆盖（面板的展开态截图受限于本机无辅助功能权限、无法合成点击，未做窗口截图）；手机 Sheet 属 P2 保真度项，仅代码与测试覆盖

## 五、待办（P2/P3，不阻塞）

- 手机 capture sheet 完整 `mobileCaptureSheet` 子态（现状为功能完整的 composer，非规格的锚定 sheet）
- 命令面板/搜索结果在宽屏应开就地抽屉而非 push 全页
- 合并备份：同 syncId 不同内容应进入冲突清单
- 月视图跨天条按月过滤；计划块遗漏/逾期样式；周泳道 `+N` 可展开
- 日历管理去折叠、回收站永久删除子页化、日历筛选去模态
- 调色板常量三处合并；隐藏日历计数纳入无日期待办；月内条目按时间排序
- capture 失败态：「先记到未安排」应写裸待办而不是带同一草稿重试；采集条开关在 saveError 态丢已选字段前应确认；带时间标题的「重试」不应跳回解析态
- 键盘细节：焦点行吞掉 Space（不能空格翻页）；手机行 Tab 顺序为「行→勾选→安排」；月格 Enter 切日视图后焦点不回新视图；桌面采集展开按钮的焦点环被实心圆遮住（34×34 亦小于 48 目标）
- 已知环境噪声：`test/integration/recurring_action_loop_vertical_test.dart` 在 23:00 后会因 `now + 2h` 跨天失败，`TZ=UTC` 下通过（`+1040`），属既有测试的时间边界，与本轮改动无关
- 规格面 PARTIAL/NOT FOUND 6 条（`slotCapture` 内联预填新建、`settings-import` 失败报告/跳过坏行、`settings-backup` 百分比与先显文件名、`settings-sync-conflict` 逐项选择、`overdueToolbar`、`mobileOverlapBand`）
