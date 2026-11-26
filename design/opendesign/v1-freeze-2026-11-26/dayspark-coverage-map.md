# DaySpark 功能覆盖映射表

- 依据：`ui/converge@2027d5a` 的真实路由与实现；8 份独立功能域审计（`/tmp/dayspark-coverage/01…08-*.md`）；当前 OpenDesign 母版 `dayspark-spec.html`。
- 本表回答四个问题：这个功能有没有？用户怎么触发？需要哪些界面与状态？母版里哪块画板承担？
- 结论只分四种：**已覆盖**、**补变体/补画板**（本轮已补）、**系统负责**（原生面板，应用内前后态已设计）、**代码/产品缺陷**（无界面可设计，不新增功能）。
- 不冻结。`docs/design/frozen/dayspark-spec.html` 未改动。

当前母版：83 屏 / 341 变体 / 32 个细节表面实例；全量 smoke render 682 次，0 异常（数量仅作定位，不作覆盖证据）。

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
| 计划执行 | 安排时间 | 日期/起止、当日已有、重叠、改写 | `plan-picker`、`pick-schedule` | 已覆盖 |
| 完成与撤销 | 勾选 | 行内撤销、4 秒条、重复实例选择、失败 | `todo-*:undo`、`overlays:undo`、`pick-occurrence` | 已覆盖 |
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
| 时间槽捕获 | 点空槽/手机空日 | 标题、时间、日历、地点、提醒、必填、失败、安排已有待办 | `cal-week/day:slot`、`capture`、`pick-schedule`、`pick-calendar`、`location`、`pick-reminder` | 已覆盖 |
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
| 搜索/命令框 | Cmd+K / 搜索 | 空、结果分组、无结果、动作、失败、分页、键盘选中 | `command` 全变体 + `command:more` | 补变体 |
| 手机命令空态 | 打开搜索 | 最近 5 条 + 新建待办/新建日程/去设置 | 手机 `mobileCommand:empty` | 修正 |
| 日期/时间/月年选择 | 点日期 | 日期、时间、月/年、回到今天、非法 | `picker-date/time`、`pick-month` | 已覆盖 |
| 选择器内就地新建日历 | 点“新建日历” | 名称/颜色/必填/失败/重试 | `pick-calendar:new/new-error` | 补变体 |
| 导航错误 | 深链未知对象 | 错误页 + 返回 | `nav-error` | 已覆盖 |

### 域 04 · 提醒 / 标签 / 附件 / 回收站 / 删除恢复

| 功能 | 用户操作 | 所需界面及状态 | 设计稿 | 结论 |
|---|---|---|---|---|
| 提醒选项 | 点提醒行 | 无/准时/5/15/30 分/1 小时/1 天、自定义、无锚点拒绝 | `pick-reminder` 四变体 + `inl-editors:reminders` | 已覆盖 |
| 提醒读取中 | 打开详情 | spinner，不画成“无提醒” | `inl-editors:reminders-loading` | 补变体 |
| 通知权限 | 设置/首启 | 未请求、已允许、被拒、精确闹钟、系统闹钟 | `settings-notify`、`settings-notify-denied` | 已覆盖 |
| 标签管理 | 设置/独立页 | 列表、新建、编辑、删除确认、计数 | `settings-tags`、`tags-page`、`settings-tag-new/edit` | 已覆盖 |
| 标签新建失败 | 空名/重复/写入失败 | 字段错误、重复提示、保留输入 | `settings-tag-new:validation/duplicate/save-error` | 补变体 |
| 标签编辑失败 | 保存失败 | 保留字段 + 重试 | `settings-tag-edit:save-error` | 补变体 |
| 附件 | 添加/打开/删除 | 行、上传状态、空、读取中、未上传 | `inl-editors:attachments/attachments-empty/attachments-unsynced/attachments-loading` | 补变体 |
| 回收站 | 设置/独立页 | 列表、空、加载/错误、恢复、永久删除、清空、结果横幅 | `trash-page`、`settings-trash` 全态、`cfm-actions:trash/empty-trash` | 已覆盖 |
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

- 母版更新为 **88 屏 / 360 变体**；新增 `pick-theme`（主题 / 强调色 / 语言）、`menu-task`（任务快捷菜单）、`shortcuts`（键盘快捷键）、`sync-conflict`（同步冲突）、`pick-time`（时间选择：小时 / 分钟 / 常用时段 / 范围错误）五个表面。
- 新建待办补齐「重复」「标签」两行；底部说明同步改为“子任务和附件可以创建后再加；标签也可以在这里先选”。
- 产品范围以 `DAYS_PARK_PRODUCT_SPEC.md` 为准；209 项逐项裁定见 `DAYS_PARK_209_DECISIONS.md`。
- 原型新增：真实日期/时间/重复/提醒/优先级/日历/标签选择器；重复事件展开与结束条件；日历拖动/拉伸/空白时段新建；月 +N；任务右键菜单；主题/强调色/夜间；真实 ICS 文件读取与预览；备份文件合并；回收站保留原属性恢复；AI 动作写入前确认；全字段搜索与键盘选择。
- 详情与计划选择的日期 / 时间字段不再依赖系统控件：日期打开 42 格日历，时间打开小时 + 5 分钟步进选择器；设置页的值文本不再残留 `noop`。
- 原型入口：`index.html`（与 `dayspark-prototype.html` 同内容）；母版 SHA-256 `ba72f66bee7c47ac19d81129116cc55aad2e1f6df8f355e9ba30d8a99b528d26`；原型 SHA-256 `81f7d97ebf5a5fc6225a3f916035d4b793c7ae6e9ee1dab14ee0f8f1d4813359`。
- 当前状态：等待用户亲自体验验收；未修改 Flutter，未合并 PR #113。
