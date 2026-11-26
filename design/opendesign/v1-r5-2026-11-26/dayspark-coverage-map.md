# DaySpark 功能覆盖映射表

- 依据：**产品规格 v1.0（`DAYS_PARK_PRODUCT_SPEC.md`，13 个功能域）** + 209 项裁定（`DAYS_PARK_209_DECISIONS.md`）+ 当前母版与原型。
- 历史来源（仅作为背景，不作当前依据）：`ui/converge@2027d5a` 的旧路由审计与 8 份旧功能域审计。
- 本表回答四个问题：这个功能有没有？用户怎么触发？需要哪些界面与状态？母版/原型里哪一块承担？
- 结论只分四种：**已覆盖**、**原型已实现**、**原型模拟**、**v1 不做**。
- 不冻结。`docs/design/frozen/dayspark-spec.html` 未改动。

当前母版：88 屏 / 360 变体 / 39 个表面；原型：`index.html`（单文件，无外部依赖，15 个原型脚本）。数量仅作定位，不作覆盖证据。

## 0. 当前验收口径（2026-11-26 第四轮）

验收不以“按钮有没有反应”为准，只认**操作结果正确**：数据被正确修改、失败保留输入、范围选择只影响该范围、重启后结果不变。

| 验收主线 | 规格 §6 场景 | 原型状态 |
|---|---|---|
| 捕获 → 改类型/时间 → 保存 → 出现在待办/日历 | 1 | 已实现（真数据） |
| 新建待办 → 截止 + 重复 + 提醒 + 标签 | 2 | 已实现（重复按真实发生次数计数） |
| 详情编辑 → 子任务/标签/附件 → 失败重试 → 刷新保留 | 3 | 已实现 |
| 日历拖动改期/改时长 → 重复日程删除三档 | 4 | 已实现（仅这一次 / 及以后 / 整个系列分别生效） |
| 月视图 +N → 打开条目 → 返回 | 5 | 已实现 |
| 空白时段 → 新建日程 → 周/日出现 | 6 | 已实现 |
| 搜索 → 高亮 → 键盘选择 → 完成/撤销 → 无结果新建 | 7 | 已实现 |
| AI 回复 → 安排时间 → 确认写入 | 8 | 已实现（目标取真实待办，不再固定 `report`） |
| 设置主题/强调色/启动页 → 刷新保留 | 9 | 已实现 |
| ICS 导入 → 预览 → 目标日历 → 报告；备份导出/合并 | 10 | 已实现（结束日期、RRULE、跨天、跳过行均写入并列入报告） |
| 删除 → 回收站恢复 → 原属性；清空需确认 | 11 | 已实现（快照恢复；无快照时明确说明会退化成纯标题） |
| 离线/冲突/保存失败/通知被拒 | 12 | 已实现（横幅 + 恢复路径） |
| 手机 Dock → 新建 → 详情 → 日历 → 设置返回栈 | 13 | 已实现（四入口 + 长按菜单） |
| 无占位兜底 | 14 | 已实现（产品页 0 死控件；样张页明确标注为设计样张） |

独立 Reviewer 在最终冻结产物（`d7785545…`）上复验：13/13 连续操作通过，4/4 专项抽查通过，0 失败。

第三轮（恢复被删能力 + 修 17 项数据语义）新增的连续操作验收，按**数据结果**判定：

| 连续操作 | 数据断言 | 原型状态 |
|---|---|---|
| 建每日重复任务 → 完成今天 → 看明天 | `doneInstances=['id@TODAY']`；明天 `isInstanceDone=false` | 已实现 |
| 一个待办安排两段（上午 + 下午） | `plans` 两段均 `active`；`plansOn` 返回两段 | 已实现 |
| 安排重复待办的某一次 | 分配带 `occurrenceDate`；其他实例的计划不受影响 | 已实现 |
| 改截止 → 取消 → 原值；只写日期保存 → 无隐含时刻 | 取消后源对象 `due` 不变；日期模式 `dueTime=''` | 已实现 |
| 四档优先级显示/存储/筛选一致 | 无=0 低=9 中=5 高=1；筛选“高”只出 1 | 已实现 |
| 删除 → 恢复 → 原属性 | 快照整对象恢复（cal/tags/note/due/subtasks） | 已实现 |
| 删除 → 清空回收站 → 刷新 → 彻底消失 | 运行时与 localStorage 都不再含该 id | 已实现 |
| 删单次 → 删及以后 → 恢复及以后 → 单次不复活 | `state.skipped` 保留，`eventsOn(单次日)` 仍为空 | 已实现 |
| 跨午夜日程 → 导出 → 再导入 | `DTSTART/DTEND` 含时刻，往返 `start/end/endDate` 一致 | 已实现 |
| 模拟同步冲突 → 选本地/服务器/合并 | 三条路径写入不同且正确的字段 | 已实现 |
| AI 多条建议 → 点较早一条的动作 | 只改该消息的 `todoId`，另一条不动 | 已实现 |
| 保存失败 → 输入保留 → 重试成功 | 失败后 draft 仍在；重试写入源对象 | 已实现 |

仍待人工逐条点击确认的只有“观感与文案”层，不再有已知实现层缺陷清单。

---

## 1. 按功能域

### 域 01 · 待办 / 重复 / 计划 / 完成撤销

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| 三视图与非安排桶 | 切未安排/全部/按日期 | 分组、日期条、空态、加载/错误、筛选面板 | `todo-inbox`、`todo-all`、`todo-date` 全变体 | 已覆盖 |
| 只看无日期 | 点顶部提示 | 仅无日期列表 + 可退出筛选 | `todo-inbox:nodate` | 补变体 |
| 筛选生效 | 选日历/标签/优先级/逾期 | 条件摘要 + 命中数 + 清除 | `todo-*:filtered` | 补变体 |
| 新建待办整页 | 从捕获/深链进入 | 标题、截止、计划、提醒、日历、优先级、校验、失败、放弃 | `new-todo` 五变体 + 选择器 | 已覆盖 |
| 详情编辑 | 点行 | 摘要/编辑、校验、保存失败、放弃、删除、重复范围 | `detail-todo` 七变体 + `cfm-actions` | 已覆盖 |
| 全量编辑页 | 深链/编辑 | 关联读取中、读取失败、旧重复规则、AI 填充 | `edit-todo:loading/load-error/legacy/ai-fill` | 补变体 |
| 重复规则 | 点重复行 | 标准档、自定义 RRULE、起点、旧规则确认/预览失败 | `pick-repeat:normal/custom/start/legacy/legacy-preview/legacy-error` | 补变体 |
| 计划执行（0..n） | 安排时间 / 再安排一段 | 日期/起止、当日已有、重叠、多段并列 | `plan-picker`、`allocations` | 已覆盖（第三轮恢复） |
| 计划执行生命周期 | 改期 / 取消 / 完成失效 | 进行中、已取消、实例完成后失效、历史保留 | `allocations:active/cancelled/invalidated` | 已覆盖（第三轮恢复） |
| 完成与撤销（按实例） | 勾选 | 只写当前实例、行内撤销、4 秒条、失败 | `todo-*:undo`、`overlays:undo`、`occurrence-history` | 已覆盖（第三轮恢复） |
| 重复实例历史 / 遗漏 | 打开“查看实例 / 遗漏” | 最近 30 天、已完成/遗漏/已跳过、补完成/撤销 | `occurrence-history:normal/empty` | 已覆盖（第三轮恢复） |
| 旧重复规则 | 系列带 legacy 规则 | 先解释、确认前不改写、迁移或保留 | `pick-repeat:legacy/legacy-preview/legacy-error` | 已覆盖（第三轮恢复） |
| 实例选择器异常 | 重复待办完成 | 列表/分页/加载/空/读取失败 | `pick-occurrence:normal/page2/loading/empty/error` | 补变体 |

### 域 02 · 日历 / 日程

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| 月/周/日视图 | 底栏或顶栏进入，切视图 | 三视图、周期副标题、翻页、今天、空态、加载/错误 | `cal-week`、`cal-month`、`cal-day` 全变体 | 已覆盖 |
| 桌面时间网格 | 浏览/点空槽 | 08–20 轴、重叠、拖动/缩放 ghost、空槽新建、全天/截止通道 | `cal-week/day:drag/slot/overlap/allday/deadline` | 已覆盖 |
| 手机周/日列表 | 浏览 | 日组、系列卡、重叠带、点状截止、空态 | `cal-week`、`cal-day` 手机壳 | 已覆盖 |
| 跨午夜定时事件 | 浏览 | 不进 08–20 轴，作为跨天条目 | `cal-week/day:allday`（新增说明行） | 补说明 |
| 日历显示/隐藏 | 点漏斗 | 勾选行、计数、已隐藏、全选/完成、隐藏横幅 | `cal-week:calendars` | 已覆盖 |
| 无日历时的过滤面板 | 打开过滤 | 空态说明 + 重试 + 完成，不画成空列表 | `cal-week:calendars-empty`（桌面 + 手机） | 补变体 |
| 时间槽捕获（双入口） | 点空槽/手机空日 | “新建日程”与“安排已有待办”两个明确动作；安排只建计划执行，不改截止 | `cal-week/day:slot`（两个 ghost）、`capture`、`pick-schedule`、`plan-picker` | 已覆盖（第三轮恢复） |
| 新建日程整页 | 月 FAB/深链 | 类型、字段、全天、校验、失败、草稿丢弃 | `new-event` 五变体 | 已覆盖 |
| 日程详情 | 点事件 | 摘要/编辑、全天、重复、删除范围、校验、失败 | `detail-event` + `event-scope` | 已覆盖 |
| 重复实例打开 | 点某次实例 | 本次实例 vs 系列锚点、保存作用于整个系列 | `detail-event:instance` | 补变体 |
| 跨天定时结束 | 编辑 22:00→次日 02:00 | 结束日期行 + 跨天说明 | `detail-event:crossday` | 补变体 |
| 日程标签 | 查看 | 只读 chip，无添加入口 | `detail-event`（已改为只读说明） | 修正 |

### 域 03 · 捕获 / 新建编辑 / 快速添加 / 搜索命令

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| 捕获条与浮动捕获 | 输入一句话 | 紧凑、展开、时间建议、移除建议、改日程、日期/计划/日历/提醒、校验、失败、放弃、键盘 | `capture` 全变体 | 已覆盖 |
| 移除时间建议 | 点“移除” | 建议位变“已移除 / 恢复”，仍不写日期 | `capture:removed` | 补变体 |
| A″ 快速编辑浮层 | 从通知/深链 | 新建、建议、安排已有、日程、校验、保存中、失败、放弃 | `a2-composer` 全变体 | 补 suggest/saving |
| 快速添加 | 点快捷入口 | 空、待办、日程、移除建议、失败、放弃 | `quick-add` 五变体 | 已覆盖 |
| 新建整页 | 深链 | 待办/日程字段、校验、脏离开、失败 | `new-todo`、`new-event` | 已覆盖 |
| 全量编辑加载 | 打开编辑页 | 读取中、读取失败、旧规则、AI 填充 | `edit-todo` 新增四态 | 补变体 |
| 搜索/命令框 | Cmd+K / 搜索 | 空、结果分组、无结果、动作、失败、“显示更多/收起”、键盘选中 | `command` 全变体 + `command:more` | 已覆盖（第三轮修复截断） |
| 手机命令空态 | 打开搜索 | 最近 5 条 + 新建待办/新建日程/去设置 | 手机 `mobileCommand:empty` | 修正 |
| 日期/时间/月年选择 | 点日期 | 日期、时间、月/年、回到今天、非法 | `picker-date/time`、`pick-month` | 已覆盖 |
| 选择器内就地新建日历 | 点“新建日历” | 名称/颜色/必填/失败/重试 | `pick-calendar:new/new-error` | 补变体 |
| 导航错误 | 深链未知对象 | 错误页 + 返回 | `nav-error` | 已覆盖 |

### 域 04 · 提醒 / 标签 / 附件 / 回收站 / 删除恢复

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| 提醒（可多个） | 点提醒行 / “再加一个” | 多个提醒并列、逐个移除、相对偏移、无锚点只允许绝对时间 | `pick-reminder` 四变体 + `inl-editors:reminders` | 已覆盖（第三轮恢复） |
| 提醒锚点 | 无计划 / 无截止时刻 | 相对选项禁用并说明原因；具体时间仍可用 | `pick-reminder`（禁用行）、`pick-time` | 已覆盖（第三轮修复） |
| 提醒读取中 | 打开详情 | spinner，不画成“无提醒” | `inl-editors:reminders-loading` | 补变体 |
| 通知权限 | 设置/首启 | 未请求、已允许、被拒、精确闹钟、系统闹钟 | `settings-notify`、`settings-notify-denied` | 已覆盖 |
| 标签管理 | 设置/独立页 | 列表、新建、编辑、删除确认、计数 | `settings-tags`、`tags-page`、`settings-tag-new/edit` | 已覆盖 |
| 标签新建失败 | 空名/重复/写入失败 | 字段错误、重复提示、保留输入 | `settings-tag-new:validation/duplicate/save-error` | 补变体 |
| 标签编辑失败 | 保存失败 | 保留字段 + 重试 | `settings-tag-edit:save-error` | 补变体 |
| 附件 | 添加/打开/删除 | 行、上传状态、空、读取中、未上传 | `inl-editors:attachments/attachments-empty/attachments-unsynced/attachments-loading` | 补变体 |
| 回收站 | 设置/独立页 | 列表、空、加载/错误、整对象恢复（保留跳过记录）、永久删除、清空（物理移除） | `trash-page`、`settings-trash` 全态、`cfm-actions:trash/empty-trash` | 已覆盖（第三轮修复） |
| 删除与撤销 | 删除 | 普通/重复范围、4 秒撤销、EXDATE | `event-scope`、`cfm-actions`、`overlays:undo` | 已覆盖 |

### 域 05 · AI

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| AI 设置 | 开关/配置 | 开、关、未配置、配置浮层、检测中、失败、读取中、保存校验 | `settings-ai` 全变体 | 补 loading/save-checking |
| 模型选择 | 点模型行 | 列表、读取中、读取失败、手动填写 | `pick-ai-model` 四变体 | 修正变体声明 |
| 对话页 | 底栏/入口 | 就绪空对话、消息、发送中、失败重试、加载中、清空确认 | `ai-chat` 全变体 | 补 loading |
| 创建动作 | 点动作芯片 | 选日历、确认写入、成功/失败 toast | `ai-create-confirm`、`ai-calendar`、`overlays:toast` | 已覆盖 |
| 安排到日历 | 说“安排一下” | 先选真实待办（含空态）→ 推荐时段 → 确认 | `ai-task-pick`、`ai-slots`、`ai-schedule-confirm` | 补画板 |
| 任务拆分 | 说“拆一下” | 候选子任务、点一条才建 | `ai-breakdown` | 已覆盖 |
| 编辑页 AI 填充 | 点 sparkles | 解析中、填入结果、未配置/失败提示 | `edit-todo:ai-fill` | 补变体 |

### 域 06 · 设置 / 账号 / 同步 / 设备 / 通知 / 关于

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| 设置壳 | 顶栏“我”/底栏设置 | 桌面左导航、手机分区行、返回 | `settings-home` + 各分区 | 已覆盖 |
| 通用/默认日历/启动页/语言 | 点行 | 单选卡、空日历 | `settings-general`、`settings-choice`、`settings-default-calendar:empty` | 补空态 |
| 账号未登录 | 进入账号 | 服务器/邮箱/密码 + 注册/登录 | `settings-account:logged-out` | 已覆盖（补注册按钮） |
| 账号读取/提交/注册 | 登录/注册 | 读取中、失败、注册三态、提交中、已登录摘要、加载失败 | `settings-account` 九变体 | 补变体 |
| 同步分区 | 进入同步 | 未登录、计数行、失败、冲突三选 | `settings-sync*`、`settings-sync-conflict` | 已覆盖（补计数行） |
| 桌面同步横幅 | 离线/失败/冲突 | 三种横幅 + 说明手机不显示 | `overlays:sync` | 补变体 |
| 设备列表 | 进入设备 | 列表、空、读取中、读取失败 | `account-devices` 四变体 | 已覆盖 |
| 关于/许可 | 点行 | 版本、数据、反馈、许可展开 | `settings-about` + `license` | 补变体 |
| 反馈 | 进入反馈 | 撰写、空、已复制、外链失败 | `feedback` | 已覆盖 |

### 域 07 · 导入 / 导出 / 备份 / 恢复

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| 数据入口 | 设置 · 数据 | 标签/回收站/导入/备份 | `settings-data`、`settings-io` | 已覆盖 |
| 导入 ICS | 选文件 | 预览汇总、目标日历、无日历、解析失败、执行中、结果、跳过报告 | `settings-import` + `import-report` | 补 importing |
| 导出 ICS | 点导出 | 空库提示、生成、系统分享/失败 | `overlays:toast`；系统负责 | 已覆盖 |
| 完整备份 | 点备份 | 进度、成功卡、失败重试 | `settings-backup:progress/success/error` | 已覆盖 |
| 合并备份 | 恢复 | 读取中、冲突三选、成功、失败 | `settings-backup:merging/merge-success/merge-error`、`cfm-backup` | 补变体 |

### 域 08 · 原生小组件 / 深链 / 全局壳层 / 通知 / 服务端授权

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| iOS / macOS 小组件 | 组件库添加、点行、点 `+` | 今日/待办/月历 × 小中大；空、过期、全完成 | `widgets:today/todo/calendar/empty/stale/done` | 已覆盖 |
| Android 小组件 | 添加、resize、点行 | 三种 × 2×2/4×2/4×4；过期保留旧日期、无快照回退、全完成 | `widgets:android/android-states` | 补变体 |
| 条目溢出 | 行预算放不下 | “还有 N 项”，点击进列表 | `widgets:overflow` | 补变体 |
| 组件配置 / resize | 长按编辑 | 系统 App Intent / launcher；三列表仅 Apple | 系统负责（`widgets` 注明） | 系统负责 |
| 深链落点 | 点组件/通知/外部链接 | `quick-add`、`new-event`、详情、日历日期 | `quick-add`、`new-event`、`detail-*`、`cal-*` | 已覆盖 |
| 详情加载器 | 深链按 id 打开 | 读取中、无对象、读取错误 | `detail-loading`、`nav-error:missing` | 已覆盖（错误与缺失共用文案属代码缺陷） |
| 未知/畸形深链 | 手输/坏参数 | 导航错误 + 回首页 | `nav-error:normal` | 已覆盖 |
| 桌面顶栏 / 手机 Dock | 切换目的地、搜索、设置 | 选中、搜索、时间、设置入口 | 各页面壳层 | 已覆盖 |
| 同步横幅 | 离线/失败/冲突 | 三种横幅，桌面顶栏下 | `overlays:sync` | 补变体 |
| Toast / Undo | 完成/删除/保存 | 4 秒撤销、成功/失败 toast | `overlays:toast/undo`、`states` | 已覆盖（互相打断属代码缺陷） |
| 通知权限 | 首次启动/设置 | 系统弹窗、权限行、被拒横幅、精确闹钟、系统闹钟 | `settings-notify`、`settings-notify-denied` | 已覆盖；弹窗系统负责 |
| 通知动作/点击 | 点通知按钮/正文 | 系统通知 UI；落点详情 | 系统负责按钮；`detail-*` 承接 | 已覆盖（点击无处理属代码缺陷） |
| 反馈页 | 设置 · 关于 · 反馈 | 撰写、复制、已复制、外链失败 | `feedback` | 已覆盖 |
| OAuth 同意页 | MCP 客户端打开授权链接 | 说明、scope、邮箱/密码、拒绝/允许；凭据错误；拒绝；参数/CSRF 错误 | `server-oauth:normal/error/denied/invalid` | 补变体 + 修正登录字段 |
| 更新内容 | 升级后首启 | 仅版本号 / 发布说明 | `whats-new:normal/notes` | 已覆盖 |

---

## 2. 本轮新增 / 修正的画板（全部已在母版中）

- 日历：`cal-week:calendars-empty`（桌面 + 手机）、`detail-event:instance`、`detail-event:crossday`；`allday` 变体补跨午夜说明；手机空周文案修正；日程标签改为只读。
- 待办：`todo-inbox:nodate`、`todo-*:filtered`、`pick-occurrence:error`、`pick-repeat:start/legacy-error`、`edit-todo:loading/load-error/legacy/ai-fill/validation/save-error`。
- 捕获/命令：`capture:removed`、`a2-composer:suggest/saving`、`command:more`、手机命令空态补齐动作。
- AI：`settings-ai:loading/save-checking`、`ai-chat:loading`、`ai-task-pick`（normal/empty）、`pick-ai-model` 四变体声明与实现对齐。
- 设置/账号：`settings-account` 九变体、`settings-about:license`、`settings-default-calendar:empty`、`overlays:sync`。
- 标签/附件：`settings-tag-new:validation/duplicate/save-error`、`settings-tag-edit:save-error`、`inl-editors:reminders-loading/attachments-empty/attachments-unsynced/attachments-loading`。
- 导入/备份：`settings-import:importing`、`settings-backup:merging/merge-success/merge-error`、`pick-calendar:new/new-error`。
- 平台/全局：`widgets:android-states/overflow`、`server-oauth:error/invalid`、同意页补邮箱/密码字段；`settings-notify` 注明精确闹钟仅 Android。
- 冻结前裁定补齐：手机日历「今天 / 搜索 / 新建」、`cal-day:out-of-range`、`cal-week:deadline` 与 `stale-error`、`new-event:multiday`、`event-scope:save`、`nav-error:trashed/startup`、`overlays:sync-mobile`。

---

## 3. 系统负责的原生面（应用内前后态已设计）

| 原生能力 | 触发 | 应用内承接 |
|---|---|---|
| 通知权限与调度 | 提醒创建/修改 | `settings-notify`、`settings-notify-denied`；失败属代码缺陷 |
| 通知点击/动作 | 点系统通知 | `pick-occurrence`、`detail-todo`、`detail-event` |
| 文件选择 / 分享 | 附件、导入、导出 | 附件行 `inl-editors`；导入预览 `settings-import` |
| 桌面小组件 | 主屏 widget | `widgets` + 深链落到 `cal-*`/`new-event`/`quick-add` |
| 系统返回 / 键盘 / 触觉 | 手机/桌面 | 壳层与详情返回、Cmd+K、`command` |

---

## 4. 缺陷裁定（冻结前）

### 4.1 实现缺陷（设计已明确，直接修）

- 日历：视图菜单 1×1 热区改为可见分段控件；拖动/缩放越界 clamp；月跨天带按月过滤；过滤持久化；读取失败保留旧数据；全天关闭恢复合理时长；提醒/附件纳入草稿；Undo 恢复关联数据；重复实例保存前确认系列范围；新建页全天支持多日；定时截止可点；手机周列出定时截止。
- 待办：详情关联读取 loading/error；旧重复规则提示覆盖所有入口；命令框旧结果失败不静默；设置首页读取中不显示未登录；设备失败可重试。
- 平台：通知点击/动作/冷启动；iOS 通知分类；事件提醒完成；组件过期 `+ 日程` 日期；Today「查看全部」跳待办；软删深链状态；启动失败页；手机推送页同步横幅；精确闹钟平台门控；组件文案与只读行为一致。
- 导入/备份：部分失败、重试与报告按现有设计落实。

### 4.2 设计缺口（本轮已补进母版）

- 手机日历：今天、搜索、统一新建 FAB。
- 轴外时间与跨午夜条目；定时截止可点。
- 日历读取失败保留旧数据。
- 重复日程保存范围确认。
- 新建页全天多日与结束日期。
- 深链已删除对象、启动失败页。
- 手机推送页同步横幅。

### 4.3 产品裁决（不新增功能）

- 重复日程仍按系列编辑，不做实例级覆盖/“仅此次编辑”。
- AI 流式/停止/超时、多选、滑动操作、导入格式扩展不属本轮缺陷。
- 手机日历保留可见分段切换，取代 2026-11-16 的单一菜单约束。
- 重复待办的截止不进日历（避免一个系列 N 条截止），保留。
- 未知深链错误页只保留「返回首页」；不新增诊断上报。

## 5. 停止条件对照

- 未覆盖功能：0（域 01–08 全部并入）。
- 未设计的必要界面与状态：0（本轮补的画板均已渲染验证，桌面 + 手机）。
- 新增设计可渲染：682 次 smoke render，0 异常；新增态已逐屏查看。
- 已有正确设计：未重做成熟主页面；仅修正与代码不符的只读标签、空态文案与 OAuth 登录字段。

**状态：等待确认后冻结。**

---

## 6. Phase 4 更新（2026-11-26）

- 母版为 **88 屏 / 360 变体 / 39 个表面**；新增 `pick-theme`（主题 / 强调色 / 语言）、`menu-task`（任务快捷菜单）、`shortcuts`（键盘快捷键）、`sync-conflict`（同步冲突）、`pick-time`（时间选择：小时 / 分钟 / 常用时段 / 范围错误）五个表面。
- 新建待办补齐「重复」「标签」两行；底部说明同步改为“子任务和附件可以创建后再加；标签也可以在这里先选”。
- 产品范围以 `DAYS_PARK_PRODUCT_SPEC.md` 为准；209 项逐项裁定见 `DAYS_PARK_209_DECISIONS.md`。
- 原型新增：真实日期/时间/重复/提醒/优先级/日历/标签选择器；重复事件展开与结束条件；日历拖动/拉伸/空白时段新建；月 +N；任务右键菜单；主题/强调色/夜间；真实 ICS 文件读取与预览；备份文件合并；回收站保留原属性恢复；AI 动作写入前确认；全字段搜索与键盘选择。
- 详情与计划选择的日期 / 时间字段不再依赖系统控件：日期打开 42 格日历，时间打开小时 + 5 分钟步进选择器；设置页的值文本不再残留 `noop`。
- 原型入口：`index.html`（与 `dayspark-prototype.html` 同内容）；母版 SHA-256 `672e7f35fbdd49c61e4ee148b1a619a8400a5189f9a9b67cf2c0b7313912cbdc`；原型 SHA-256 `c29bd2c31cb1d35c5fa8027fbdf1c2efea1b9dc83dde87db13d076eed498c4fd`。
- 当前状态：等待用户亲自体验验收；未修改 Flutter，未合并 PR #113。

---

## 5. 第三轮：恢复能力与数据语义修复（2026-11-26）

### 5.1 恢复的真实能力（规格、母版、原型均已同步）

| 能力 | 规格 | 母版表面 | 原型实现（唯一所有者） | 结论 |
|---|---|---|---|---|
| 重复待办按实例完成 / 撤销 | R1、R10 | `detail-todo`、`today`、`todo-*`、`occurrence-history` | `DS3.toggleDone/undoDone`；master `toggle-done/undo-done` 路由到 DS3 | 已覆盖 |
| 一个待办 0..n 段计划执行 | R2 | `allocations:active` | `DS3.addPlan`；详情“共 N 段 / 再安排一段” | 已覆盖 |
| 分配绑定具体实例 | R3 | `plan-picker`（显示“这一次实例”） | `occurrenceDate`；槽位/AI/详情都先选实例 | 已覆盖 |
| 取消 / 完成失效 / 历史 | R4 | `allocations:cancelled/invalidated` | `cancelPlan`、`invalidateAfter`、`historyOf` | 已覆盖 |
| 遗漏实例可补完成 + 历史入口 | R5 | `today:missed`、`occurrence-history` | 真实 `missedInstances`（锚点 + 完成/跳过推导）、`.missed` 可点、`missed-open` | 已覆盖 |
| 旧重复规则识别 / 显式迁移 | R6 | `pick-repeat:legacy*` | `legacy-migrate` 确认框；确认前不改写 | 已覆盖 |
| 多条提醒 + 锚点规则 | R7 | `pick-reminder`、`detail-todo` | 详情“＋ 再加一个 / 移除”；无锚点时相对项禁用 | 已覆盖 |
| 时间槽双入口 | R8 | `cal-week/day:slot` 两个 ghost、`pick-schedule` | 空槽弹层“安排已有待办” → 选待办/实例 → 计划选择器；不建 Event、不改截止 | 已覆盖 |
| 计划执行独立持久化 | R9 | `settings-sync*` | 计划执行随 Todo 进快照/备份；跨设备同步仍按项目边界模拟 | 原型模拟 |
| 系列取消/归档 vs 实例完成 | R10 | `detail-todo`、`cfm-actions` | 完成只写实例；删除/归档作用于系列 | 已覆盖 |

### 5.2 本轮修复的 17 项数据语义（原型实测）

| # | 问题 | 实际生效路径 | 结论 |
|---:|---|---|---|
| 1 | 清空回收站只删标记 | `flows-v3-data.js` `trash-clear-v2` → 物理 splice + `purgedIds` | 已修复 |
| 2 | 同步冲突选择不写数据 | `flows-v3-ai.js` 冲突批次 → 逐条写 `title/note/priority` + `lastResolution` | 已修复 |
| 3 | 优先级数值与母版不一致 | `flows-v3-capture.js` 唯一尺度 无0/高1/中5/低9 | 已修复 |
| 4 | 只写日期却写入 18:00 | 截止弹层仅 time 模式读取时间；日期模式清空 | 已修复 |
| 5 | 嵌套日期选择器后取消外层仍保留 | 截止/时间快照 + 取消/遮罩回滚 | 已修复 |
| 6 | 快速添加固定 15:00–16:00 | `Proto.quickAdd` 重写为中文时间解析 | 已修复 |
| 7 | 定时日程不能跨午夜 | 槽位与表单 `end < start` → 两天跨度 + `crossMidnight` | 已修复 |
| 8 | 无锚点仍可选相对提醒 | 提醒选择器禁用相对项 + 原因；详情 select 同步禁用 | 已修复 |
| 9 | ICS 导出丢时刻/结束/重复 | `buildICS` 写 DTSTART/DTEND/LOCATION/DESCRIPTION/RRULE + 折行 | 已修复 |
| 10 | ICS 待办无日期、不能往返 | VTODO DUE（含时刻）/DESCRIPTION/RRULE；导入写回 repeat | 已修复 |
| 11 | 恢复预置回收站行仍留在回收站 | `trash-restore-v2` 统一 `markTrashRemoved` | 已修复 |
| 12 | 恢复重复系列清空 skip | 恢复不动 `state.skipped` | 已修复 |
| 13 | AI 旧消息动作读最后一条建议 | 每个气泡带消息下标；只读该消息的 `act` | 已修复 |
| 14 | 掩码 Key 被当成非法输入 | `secret` + 掩码显示；掩码/留空保存 = 保留 | 已修复 |
| 15 | 搜索硬截断 6/5 条 | 分组“显示更多（共 N）/收起”，焦点回搜索框 | 已修复 |
| 16 | localStorage 失败静默 | `Proto.save` 覆盖 + 探针回读 + 可见横幅 + 重试 | 已修复 |
| 17 | 只读兜底掩盖未接线控件 | 产品页未接线控件禁用并标“未实现”；样张明确标注 | 已修复 |

### 5.3 仍需人工确认的边界

- 跨设备同步、真实通知投递、原生小组件仍是**原型模拟**（项目既定边界，不是能力删除）。
- 重复待办的实例级“跳过/仅此次删除”按真实领域契约不提供；实例完成、遗漏补完成与计划取消已提供。


### 5.4 第四轮模型收敛与缺陷结论（2026-11-26）

| 级别 | 原问题 | 当前有效路径 | 结论 |
|---|---|---|---|
| P0-1 | 日历拖动读写 `t.plan` | 点击/拖动只按 `data-alloc` 取分配；`DS3.updateAllocation(id)` 写回；固定起点计算偏移 | 已修复并实测 |
| P0-2 | 编辑器新增计划覆盖第一段 | 新页/详情草稿的 `plans[]` 追加；保存时逐段 `addAllocation`；取消整份丢弃 | 已修复并实测 |
| P0-3 | 重复完成/改期靠猜实例 | `requireOccurrence` 显式选择；`toggleDone(id,date)`；拖拽保留 `occurrenceDate`；列表/详情/日历/AI 同一条路径 | 已修复并实测 |
| P0-4 | 备份合并跳过同 id 的业务数据 | `applyBackupMerge` 对已有 todo/event 补齐字段并合并分配/提醒/标签，同时恢复实例状态；真实文件导出→清空→重载→合并回归 | 已修复并实测 |
| P0-5 | 旧重复规则静默迁移 | `legacy-migrate` 必须显式时区/锚点/规则；取消原样保留 | 已修复并实测 |
| P1-1 | 提醒把计划当锚点 | `anchorOf` 只取日程开始或带时刻的截止；无锚点禁用相对项 | 已修复并实测 |
| P1-2 | 多提醒入口不全 | 新建待办/日程、详情待办/日程、编辑态统一主提醒 + 附加行 | 已修复并实测 |
| P1-3 | 重复锚点取自计划日期 | `ensureSeriesAnchor` 只取 `repeatAnchor/seriesStart/due/startDate`；新建无锚点时取今天 | 已修复并实测 |
| P1-4 | 原始 `status='done'` 不能撤销 | `toggleDone` 同时清 `state.done` 与 `status/completed` | 已修复并实测 |
| P1-5 | 日历按 todo+时间去重 | `plansOn` 每个分配一条并携带 `allocId` | 已修复并实测 |
| P1-6 | 全部取消后历史消失 | 历史入口常驻，取消记录保留 | 已修复并实测 |
| P1-7 | 所有计划都显示“进行中” | `allocationStatus` 分即将开始/进行中/已结束/已取消/已失效 | 已修复并实测 |
| P1-8 | 快速添加把时刻写成待办计划 | 带时刻默认日程；显式另存待办不写截止/计划/提醒 | 已修复并实测 |
| P1-9 | 快速添加跨午夜结束错误 | 结束分钟跨 1440 时写次日 `endDate`，不 clamp | 已修复并实测 |
| P1-10 | 拖动累计偏移 | 固定 `originStart/originEnd` 计算 delta；+30→−30 回到原位，+60 不叠加 | 已修复并实测 |
| P1-11 | 备份失败重试只显示成功 | 失败态重试真实重新生成下载文件 | 已修复并实测 |
| P1-12 | AI Key 明文进快照/备份 | 会话模块变量保存真实 Key；`P.data.ai.key` 仅掩码；快照/localStorage/备份均无明文 | 已修复并实测 |

验收证据随本轮评审包提交：`evidence/` 下为真实 Chrome + CDP 操作脚本与输出；产品页入口为桌面 1440×1000 与手机 390×844。

---

## R5 · UI/UX 优化覆盖（2026-11-26）

| 表面 | 入口 | R5 变化 | 证据 |
|---|---|---|---|
| 桌面壳 | 所有桌面页 | 深墨左轨、页面头、72px 图标轨（<1180） | `desktop-today.png`、`tablet-today.png` |
| Today | 左轨「今天」 | 概览带、5/7 分栏、实例统计、全量分配、手机截止展开 | `desktop-today.png`、`mobile-today.png`、`mobile-deadline-expanded*.png` |
| Todos | 左轨「待办」 | 行高 64、16px 标题、13px 元信息、440px 详情 | `desktop-todos.png`、`mobile-todos.png` |
| Calendar | 左轨「日历」 | 日程/计划/截止/已执行语义、旧版横幅、历史行 | `desktop-calendar.png`、`desktop-calendar-history.png`、`desktop-calendar-legacy.png` |
| 详情 | 任意行/块 | 440px 抽屉、26px 标题、50px 字段行 | 原型操作 |
| 设置 | 账号/设置 | 六组任务 IA、账户与同步合并 | `desktop-settings.png`、`mobile-settings.png` |
| MCP | 设置 → AI 与自动化 → MCP | 状态、范围、客户端、活动、撤销 | `desktop-mcp.png`、`mobile-mcp.png` |
| 小组件 | 设置 → 外观与日历 → 小组件 | 实时勾选完成当天实例 | `desktop-widgets.png` |
| 手机壳 | <600 | 五格 Dock、中央添加、无 FAB、16px 输入 | `mobile-today.png`、`mobile-calendar.png` |
| 平板 | 900–1179 | 图标轨 + 双栏；1024×768 可用 | `tablet-today.png`、`tablet-calendar.png` |
| 主题 | 设置 → 外观与日历 | 浅色 / 暖灰 / 深色同一语义 | `dark-today.png`、`dark-calendar.png`、`dark-settings.png`、`warm-today.png` |

### R5 缺陷收口

| 缺陷 | 状态 | 证据 |
|---|---|---|
| 手机 Today 截止只显示前两条，无展开 | 已修：前三项 + 还有 N 项 + 展开 | `mobile-deadline-expanded*.png` |
| Today 只读一个派生计划 | 已修：`plansOn` 聚合全部 active allocations；统计按段计数 | `r5probe`：planned 1→2 |
| 完成统计不反映重复实例 | 已修：`isDoneToday` / `DS3.isInstanceDone` | `r5probe`：完成重复实例 done +1，series false |
| 完成普通待办后历史安排消失 | 已修：invalidated/cancelled 作为历史保留；日历新增「已执行」行 | `desktop-calendar-history.png` |
| 旧重复计划自动投影未来 | 已修：无显式分配时只显示锚点，不合成未来 | `desktop-calendar-legacy.png`、`r5probe` future 0 |
| 手机 FAB 遮挡列表 | 已修：取消 FAB，五格 Dock 中央添加 | `mobile-today.png` |
| 调试工具条暴露 | 已修：折叠为「预览」胶囊 | `desktop-today.png` |
| 8–10px 字号 | 已修：12px 下限，正文/输入按设备提升 | 字阶门禁 |
