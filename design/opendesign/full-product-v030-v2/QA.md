# DaySpark 设计原型 · 自测报告

**日期：** 2026-11-10
**设计基线：** `origin/main @ 5f48ad563cb1d242106a15aa19b73ab52ee13390`
**测试对象：** 本目录 `prototype/mobile.html`、`prototype/desktop.html`、`prototype/widgets.html`
**浏览器：** Microsoft Edge（Playwright `channel: 'msedge'`），桌面 shell 1280×1000 / 1440×900，手机内容 412×915，另测 360 / 320

---

## 1. 结论

| 项目 | 结果 |
| --- | --- |
| 手机原型页面与弹层 | **PASS**（操作路径见 §3） |
| 桌面原型页面与命令面板 | **PASS** |
| 小组件预览（4 类 × 3 尺寸） | **PASS**（HTML 规范预览，非真机 RenderViews） |
| 控制台 / 页面错误 | **0**（所有脚本 `ERRORS: []`） |
| 横向溢出 | **未发现**（320 / 360 / 412 / 900 / 1440） |
| 手机触控目标 | **PASS**（412 下除日历短日程块与横向日期条外均 ≥48dp） |
| Android 精确 HEAD 原生构建 | **NOT VERIFIED**（本机缺 NDK 许可，按要求不修复环境） |
| 真机小组件 / 真实网络服务 | **NOT TESTED** |

本报告只描述**设计原型**的可用性；不声称 Flutter、Android 原生或服务端已经实现。

---

## 2. 测试方法与命令

所有脚本位于仓库 `.audit-tools/`，均为一次性自测工具，不修改 `lib/`、数据库或生产测试。

```bash
node .audit-tools/proto-test.cjs          # 手机主流程 + 截图
node .audit-tools/proto-desktop-test.cjs  # 桌面主流程
node .audit-tools/proto-widgets-test.cjs  # 小组件尺寸与完成交互
node .audit-tools/textsheet-test.cjs      # 日历/标签创建、子任务、桌面表单
node .audit-tools/qa-journey.cjs          # 端到端用户旅程（手机）
node .audit-tools/ai-sync-test.cjs        # 手机 AI / 同步状态机
node .audit-tools/desktop-ai-sync-test.cjs
node .audit-tools/full-create-test.cjs    # 快速创建 → 完整表单
node .audit-tools/hit48.cjs               # 48dp 触控审计
node .audit-tools/overflow-audit.cjs      # 多宽度溢出审计
node .audit-tools/day-shots.cjs           # 天视图 412/360/320
node .audit-tools/long-title-test.cjs     # 长标题换行
node .audit-tools/share-test.cjs          # 手机 / 桌面共享状态
node .audit-tools/extra-test.cjs          # 主题色、ICS、备份、永久删除
node .audit-tools/settings-test.cjs       # 语言 / 启动页 / 周起始 / 时间格式（手机）
node .audit-tools/desktop-settings-test.cjs
node .audit-tools/desktop-filter-test.cjs # 桌面侧栏日历筛选
node .audit-tools/widgets-12h-test.cjs    # 12 小时制下小组件不裁切
```

每次都监听 `pageerror` 与 `console.error`；下面引用的结果均为最后一次运行输出。

---

## 3. 手机端端到端旅程

在 412×915、全新 localStorage 下执行。

| # | 用户任务 | 操作 | 结果 |
| --- | --- | --- | --- |
| 1 | 完成今天的一件事 | 今天 → 勾选“整理上周会议纪要” | 行从 6 → 5；复选框即时变化 |
| 2 | 只填标题创建待办 | 新建 → 待办 → 输入标题 → 保存 | 回到今天并出现“已添加：…”提示；待办“未安排”可见 |
| 3 | 快速创建完整信息 | 标题 + 截止 11/12 + 计划执行 + 子任务 → 保存 | 行元信息显示“计划 15:00–16:00 · 截止 11月12日 · 0/1 子任务” |
| 4 | 打开详情并完成子任务 | 点行 → 点子任务圆环 | 详情重新绘制，`aria-checked` 0→1，标题删除线 |
| 5 | 编辑标题 | 详情 → 铅笔 → 改标题 → 保存 | 列表标题变为“（已编辑）” |
| 6 | 搜索并进入结果 | 搜索“论文” → 点结果 | 打开待办详情；关闭后回到搜索页 |
| 7 | 设置返回来源 | 今天 → 设置 → 日历管理 → 返回 → 返回 | 依次回到设置、待办（来源页记忆） |
| 8 | 新建日历并选颜色 | 设置 → 日历管理 → 新建日历 → 名称 + 颜色 → 保存 | 列表出现“QA 项目日历”；删除按钮存在 |
| 9 | 从周议程进入某天 | 日历 → 周 → 点日期分组头 | 切换到该日天视图 |
| 10 | 在空白时段建日程 | 天视图 → 08:00 空白 → 选“新建日程” | 表单预填 08:00–09:00；保存后时间轴出现“QA 时间块” |
| 11 | 从天视图打开截止项 | 点截止带第一条 | 打开对应待办详情 |
| 12 | 月视图选日看议程 | 月 → 点今天 | 网格下方议程 9 条，含日程、计划执行与截止 |
| 13 | 删除并恢复 | 待办删除“QA 只填标题”→ 设置 → 回收站 → 恢复 | 删除后列表消失；回收站可恢复，恢复后条目移出 |
| 14 | 320 宽度 | 打开今天 | 文档宽 = 视口宽 320，无横向溢出 |

补充：快速创建“更多” → “打开完整表单”，标题带入；保存后轻提示，完整表单记录的标题正确写入（`full-create-test.cjs`）。

长标题：在 320 与 412 下创建 50+ 字标题，行高分别增至 101 / 81px，文字自然换行，文档宽度仍为 320 / 412，无横向溢出（`long-title-test.cjs`）。

跨端状态：桌面与手机页面共享同一 store；手机新建“共享状态测试”后，桌面刷新可见（`share-test.cjs`）。

### 3.1 天视图布局（截止带）

截止项改为横向可滚动卡片，每张 48dp 高：

| 宽度 | 截止带高度 | 时间轴起点 |
| --- | --- | --- |
| 412 | 94px | y=346 |
| 360 | 94px | y=402（工具栏两行） |
| 320 | 94px | y=402 |

此前 4 条截止纵向排列约占 300px；现在时间轴首屏可见约 8:00–16:00。

---

## 4. 设置、AI 与同步

| 状态 | 操作 | 结果 |
| --- | --- | --- |
| AI 默认 | 设置 → AI 助手 | “已关闭”；服务商、模型、密钥均为空态 |
| AI 启用未配置 | 点启用 | 提示“还需要填写模型与 API 密钥” |
| AI 已就绪 | 选 Anthropic、填模型、填密钥 | 显示“已配置 Anthropic · …”；密钥输入为 password 类型 |
| AI 生成中 | 输入一句话 → 生成待办 | 按钮禁用并显示“生成中…” |
| AI 失败 | 等待 0.9s | “连接失败：原型未接入模型服务。”；输入保留 |
| 同步校验 | 未填服务器直接登录 | 就地提示“请先填写服务器、邮箱和密码。” |
| 同步已配置 | 填服务器 / 邮箱 / 密码 | 密码只显示“已保存” |
| 登录 / 同步 | 登录 → 立即同步 | 已登录 → 同步中… → 上次同步“刚刚” |
| 退出 / 持久化 | 退出登录；刷新页面 | 回到未登录；服务器与邮箱仍保留 |
| 注册 | 点注册 | 明确说明需要服务器支持，不伪造成功 |

> 原型中的同步与 AI 结果为**本地状态演示**，不会发出网络请求。页面内已标注；真实接口联调为 `NOT TESTED`。

其他已验证的状态：

### 4.1 通用设置

在 412×915、全新 localStorage 下执行；选择后刷新页面复测。

| 设置 | 操作 | 结果 |
| --- | --- | --- |
| 语言 | 语言 → 简体中文 | 行值变为“简体中文”，轻提示说明原型只有中文文案 |
| 启动时打开 | 选“待办” | 提示“下次打开将进入‘待办’”；刷新后底部选中待办 |
| 周起始日 | 选“周日” | 周条从周日 8 日开始；月历首列为“日”；桌面周视图首列也为周日 |
| 时间格式 | 选“12 小时” | 周议程显示 `6:00 PM`、`9:30 AM–10:00 AM`；天视图小时轴为 `8 AM`；表单时间输入仍为 `15:00` 这类 24 小时值 |
| 刷新持久化 | 以上四项全部刷新 | 默认页、周起始、12 小时制均保持 |
| 320 宽度 + 12 小时制 | 周 / 天 / 月 | 文档宽 = 320，时间列加宽到 54px 后标题仍可换行，无横向溢出 |
| 设置行状态 | 配置同步 / AI 后返回设置 | 同步行显示“已配置 / 已登录”，AI 行显示“已启用 / 已就绪”，不再固定写“未登录 / 已关闭” |

桌面端相同四项通过居中单选对话框修改，并与手机共享设置；小组件在 12 小时制下时间文本无裁切（`widgets-12h-test.cjs`）。

其他已验证的状态：

| 检查 | 结果 |
| --- | --- |
| 主题色 | 选“青”后 `--primary` = `#0D9488`，色点 `aria-pressed=true`；刷新后仍保持 |
| 导入 / 导出 .ics | 选择文件 → 运行，出现“日程已导入 / 已生成 .ics”完成态 |
| 合并备份 | 运行后出现“备份已合并”与合并说明 |
| 永久删除 | 回收站条目 1 → 0，确认后不可恢复 |

（`extra-test.cjs`；文件与网络均为原型状态演示。）

---

## 5. 桌面端

- 1440×900：侧栏 232、主从详情；列表选中行、右栏详情、`Esc` 关闭。
- 快速添加：回车创建 1 条，列表即时 +1。
- 日历：周视图 7 列、8 个日程、7 个截止格；月视图 42 格；点击空白时段创建日程并在时间轴出现。
- 命令面板：`Ctrl+K`，输入后有结果，首项选中；`Enter` 打开并关闭面板。
- 设置：7 个分区（通用 / 日历与标签 / 通知 / 数据 / 同步 / AI / 关于）；主题深色生效；日历与标签可新建并选颜色。
- 通用四项可操作（语言 / 启动时打开 / 周起始日 / 时间格式），与手机共享设置。
- 侧栏日历行：点击按该日历筛选待办，计数器与列表同步；列表头出现可清除的日历 chip，再点一次同一日历也取消筛选。
- 回收站：恢复可用；已完成折叠可展开。
- 900×800：侧栏折叠为 64px 图标栏，详情改为覆盖层；设置各分区无横向溢出。
- 控制台错误：`[]`。

---

## 6. 小组件预览

| 检查 | 结果 |
| --- | --- |
| 待办 / 日历 / 时间轴 / 快捷操作 × 小中大 | 12 个预览，切换正常 |
| 待办中尺寸完成一条 | 条目移出，计数 6 → 5 |
| 重置 | 条目恢复，计数回到 6 |
| 日历大尺寸迷你月 | 42 格 |
| 时间轴大尺寸重叠 | 分栏布局，无相互覆盖 |
| 快捷操作 | 8 个可点 tile，点击有动作提示 |
| 深色主题 | 正常 |

**限制：** 这是 HTML 规范预览，不是 Android `RemoteViews` 渲染；真机尺寸、裁切、刷新与点击为 `NOT TESTED`。仓库当前只有待办 / 日历 / 今天三类 provider；日历组件最小 4×4，快捷操作组件尚不存在，均已在预览页标注。

---

## 7. 48dp 与溢出审计

`hit48.cjs` 在 412 宽扫描今天、待办、详情、周日/日/月、设置、AI、同步：

```
today 0   todos 0   detail 0   week 0   day 0   month 0   settings 0   ai 0   sync 0
```

排除项：

1. 日历中按真实时长渲染的短日程块（30 分钟约 28px；这是时间比例，不是可避免的排版）。
2. 320dp 下并排的 7 列日期条与月历格（约 40–42dp 宽，7 列无法同时满足 48）。
3. 天视图横向截止带内的卡片位于滚动容器中，不计入页面溢出。

`overflow-audit.cjs`：320 / 360 / 412 / 900 / 1440 下 `scrollWidth == clientWidth`，无文档级横向滚动。

---

## 8. 截图证据

均在 `_evidence/`：

- 源码基线：`web-today-current.png`、`web-desktop-current.png`
- 手机：`proto-mobile-today.png`、`proto-mobile-todos.png`、`proto-mobile-detail.png`、`proto-mobile-calendar.png`、`proto-mobile-calendar-day-412/360/320.png`、`proto-mobile-calendar-day-12h.png`、`proto-mobile-calendar-week-12h.png`、`proto-mobile-month.png`、`proto-mobile-search.png`、`proto-mobile-settings.png`、`proto-mobile-settings-general.png`、`proto-mobile-settings-time-format.png`、`proto-mobile-settings-dark.png`、`proto-mobile-settings-dark-lower.png`、`proto-mobile-quick-create.png`、`proto-mobile-full-create.png`、`proto-mobile-calendars.png`、`proto-mobile-calendar-editor.png`、`proto-mobile-trash.png`、`proto-mobile-ai.png`、`proto-mobile-ai-configured.png`、`proto-mobile-ai-failure.png`、`proto-mobile-sync.png`、`proto-mobile-sync-loggedin.png`、`proto-mobile-backup-success.png`
- 桌面：`proto-desktop-today.png`、`proto-desktop-todos.png`、`proto-desktop-calendar.png`、`proto-desktop-month.png`、`proto-desktop-event.png`、`proto-desktop-search.png`、`proto-desktop-narrow.png`、`proto-desktop-settings-general.png`、`proto-desktop-settings-dark.png`、`proto-desktop-ai.png`、`proto-desktop-sync.png`
- 小组件：`proto-widgets-todo.png`、`proto-widgets-calendar.png`、`proto-widgets-timeline.png`、`proto-widgets-quick-dark.png`、`proto-widgets-narrow.png`
- 边界：`qa-mobile-long-title-320.png`、`qa-mobile-long-title-412.png`、`qa-mobile-320-today.png`、`qa-mobile-settings-accent.png`
- 旧构建反例：`desktop-app.png`（10 月 5 日旧 Windows 构建，仅作反例，不参与设计判断）

---

## 9. 设计 QA 十问

1. **今天是否在 3 秒内回答“我现在要做什么、接下来是什么、今天必须完成什么”？** 是：正在进行卡 → 接下来 → 今天截止 → 已逾期；未安排以底部入口呈现。
2. **日历是否让日程、计划执行、截止在同一语境中被理解但不混淆？** 是：时间轴只放日程与计划执行；截止独立成带；月/周议程合并时仍保留“截止”文字标签。
3. **待办是否回答“我有哪些任务、如何组织”，而不是第二个今天？** 是：未安排 / 全部 / 按日期 + 筛选；无时间轴。
4. **截止与计划执行是否始终是两个对象、两个选择器、两种文案？** 是：选择器分离，计划执行进入时间轴，截止不占用时间。
5. **未安排是否只由“没有 effective planned execution”决定？** 是；与是否有截止无关。
6. **每个页面是否有明确的首屏问题与空状态？** 今天、日历、待办、搜索、回收站、AI、同步均有空状态或未配置态。
7. **手机单手与 48dp 是否成立？** 主要动作在底部或顶栏右侧；412 下审计为 0 个低于 48dp 的可点目标（除几何例外）。
8. **大尺寸是否改变结构而不是只加行数？** 小组件小/中/大分别回答一个问题、列 3 条、分组或表达时间关系。
9. **桌面是否是桌面，而不是放大的手机？** 232 侧栏、主从详情、命令面板、右键菜单、键盘快捷键、宽窄窗口断点。
10. **原型是否真的能走通，且没有伪造完成度？** 本报告中的旅程均可点击完成；网络、真机构建与小组件真机渲染明确标为 NOT TESTED / NOT VERIFIED。

---

## 10. 未完成 / 未验证（明确声明）

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Android 精确 HEAD 原生构建 | **NOT VERIFIED** | 本机缺少 NDK 许可；按要求未安装 / 修复 SDK、NDK |
| 桌面 Windows release（精确 HEAD） | **NOT VERIFIED** | 使用同源码 web release 渲染；旧 exe 判断已丢弃 |
| 真机桌面小组件（RemoteViews） | **NOT TESTED** | 仅 HTML 尺寸与结构预览；provider 约束已在页面标注 |
| 真实 .ics / 备份文件读写 | **NOT TESTED** | 原型演示选择文件、导出、成功状态，不做真实 IO |
| 真实同步服务器 / 账号 | **NOT TESTED** | 登录、同步中、完成均为本地状态演示 |
| 真实 AI 服务 | **NOT TESTED** | 配置状态可用；生成以失败态结束，不伪造结果 |
| 系统字体放大 / 屏幕阅读器 / RTL | **NOT TESTED** | 布局按两行标题与可换行元信息设计，但未在真机字号下逐页验证 |
| Flutter / Android 实现 | **未开始（按任务边界）** | 本次只交付设计；未修改 `lib/`、原生代码、数据库、Provider 或正式测试 |

---

## 11. 复现说明

原型是静态 HTML，无构建步骤：

```bash
# 直接打开
design/opendesign/full-product-v030-v2/prototype/mobile.html
design/opendesign/full-product-v030-v2/prototype/desktop.html
design/opendesign/full-product-v030-v2/prototype/widgets.html
```

手机与桌面共享 `assets/store.js` 的内存状态，并写入同一 `localStorage` key；同一浏览器会话内可看到互相影响的数据。
