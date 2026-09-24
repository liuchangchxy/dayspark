# Cross-Platform Calendar & Todo Sync Plan / 跨平台日历 & 待办同步方案

> Created / 创建时间: 2026-04-15
> Last updated / 最后更新: 2026-04-16 (Round 2 / 第二轮讨论)
> Status / 状态: Solution validation + market research phase / 方案验证 + 市场调研阶段

---

## 一、Background / 背景

### User Scenario / 用户场景
Multiple devices (OPPO Android + Windows + Mac + iPad), need a unified calendar and todo sync system, direct connection in China without proxy.
多台设备（OPPO安卓 + Windows + Mac + iPad），需要一个统一的日历和待办同步系统，国内直连不用代理。

### Core Constraints / 核心约束
- China environment, cannot always rely on proxy / 国内环境，不能始终依赖代理
- Need China-direct-connect solutions / 需要国内能直连的方案
- Hermes (AI assistant) needs to read/write calendar and todo data / Hermes（AI助手）需要能读写日历和待办数据
- User can view and input from any device at any time / 用户随时随地在任何设备能查看和录入

---

## 二、Test Findings (2026-04-16) / 实测结论

### Key Discoveries / 关键发现

#### 1. QQ Mail has no CalDAV calendar, only CardDAV contacts / QQ邮箱没有CalDAV日历，只有CardDAV通讯录
Verified via system account database (Accounts4.sqlite):
通过查系统账户数据库（Accounts4.sqlite）确认：
- Account 7 = iCloud CalDAV (p205-caldav.icloud.com.cn) → Calendar + Reminders / 日程+提醒事项
- Account 17 = QQ account (1344967911@qq.com) → QQ services only / 仅QQ服务
- Account 19 = QQ CardDAV (dav.qq.com) → Contacts sync only / 仅通讯录同步
- **No QQ Mail CalDAV calendar account exists** / **不存在QQ邮箱CalDAV日历账户**
- Previous assumption of "QQ Mail CalDAV calendar" was wrong / 之前"已有QQ邮箱CalDAV日历"的假设是错误的

#### 2. Calendar Solution: iCloud CalDAV (Confirmed) / 日程方案：iCloud CalDAV（已确定）
- Mac Calendar syncs via iCloud CalDAV (verified) / Mac系统日历通过iCloud CalDAV同步（已验证）
- iCloud China node: p205-caldav.icloud.com.cn, direct connection in China / iCloud国内节点，国内直连
- Hermes reads/writes Mac Calendar via AppleScript → auto-syncs to iCloud → all devices / Hermes通过AppleScript读写Mac日历 → iCloud自动同步到所有设备

#### 3. OPPO System Calendar Built-in CalDAV is Castrated (Read-only) / OPPO系统日历自带CalDAV是阉割版（只读）
- OPPO Calendar shows "Subscribed calendar, cannot move" after adding CalDAV / OPPO系统日历添加CalDAV后显示"订阅日历，无法移动"
- Only implemented CalDAV subscription (reading), no write / 只实现了CalDAV的订阅（读取），没有实现写入
- **Need to install DAVx5** for full iCloud CalDAV read/write / **需要安装DAVx5**才能获得iCloud CalDAV的读写能力
- DAVx5 download requires VPN (F-Droid/Play Store), daily use doesn't / DAVx5下载需梯子，日常运行不需梯子

#### 4. Apple Reminders Killed CalDAV VTODO Since iOS 13 / Apple提醒事项iOS 13后砍了CalDAV VTODO
- DAVx5 docs explicitly state: CalDAV functionality removed by Apple after Reminders upgrade / DAVx5官方文档明确说明：升级提醒事项后CalDAV功能被Apple移除
- Non-Apple devices cannot sync Reminders via CalDAV / 非Apple设备无法通过CalDAV同步提醒事项
- This path is completely blocked / 这条路彻底堵死

#### 5. Feishu Calendar Supports CalDAV, But Todos are Closed / 飞书日历支持CalDAV同步，但待办是封闭的
- Feishu Calendar has native CalDAV: Calendar→Settings→Sync to local calendar / 飞书日历有原生CalDAV
- Feishu tasks/todos only have API (requires enterprise self-built app), no CalDAV VTODO / 飞书任务/待办只有API接口，无CalDAV VTODO
- Feishu todos only viewable in Feishu app / 飞书待办只能在飞书app内查看

#### 6. "Todo List" App is a Closed System / "Todo清单"app是封闭系统
- Developer: Hangzhou Qianxi Tech (evestudio.cn) / 开发商：杭州乾夕科技
- Cross-platform (Android/iOS/Windows/Mac/iPad/Watch) / 全平台
- Can read system calendar to display in-app, but todo data cannot sync back to system / 能读取系统日历显示在app内，但待办数据不能同步回系统
- **No open API** — no API docs, no developer platform, no webhooks / **没有开放API**
- Hermes cannot access / Hermes无法访问

---

## 三、Final Solution / 最终方案

### Calendar: iCloud CalDAV (All-device Sync) / 日程：iCloud CalDAV（全设备同步）

| Device / 设备 | Solution / 方案 | Status / 状态 |
|------|------|------|
| Mac | System Calendar (iCloud account, connected) / 系统日历（iCloud账户，已连通） | ✅ Verified / 已验证 |
| iPad | System Calendar (iCloud account) / 系统日历（iCloud账户） | ✅ Should work / 应可用 |
| OPPO | DAVx5 + System Calendar / DAVx5 + 系统日历 | ⏳ Pending DAVx5 install / 待安装DAVx5 |
| Windows | Vivaldi Browser Calendar + iCloud CalDAV / Vivaldi浏览器日历 + iCloud CalDAV | ⏳ Pending config / 待配置 |

Hermes operates Mac Calendar via AppleScript → iCloud auto-syncs to all devices.
Hermes通过AppleScript操作Mac日历 → iCloud自动同步到所有设备。

### Todos: All Stored as Calendar Events in iCloud Calendar / 待办：全部当日程事件存入iCloud日历

**Core idea / 核心思路:** Don't use todo protocol, treat todos as calendar events. / 不用待办协议，把待办当日程事件处理。

- Create a dedicated calendar in iCloud called "Todos" / 在iCloud里建一个专门的日历，叫「待办」
- Each todo = one all-day calendar event (title + due date + reminder) / 每个待办 = 一个全天日程事件（标题 + 截止日期 + 提醒）
- Hermes reads/writes this calendar via AppleScript / Hermes通过AppleScript读写这个日历
- iCloud CalDAV syncs to all devices / iCloud CalDAV同步到所有设备
- Users see todos in system calendar on any device / 用户在任何设备的系统日历里都能看到待办

**Feature Mapping / 功能对照：**
| Todo Need / 待办需求 | Calendar Event Approach / 日程事件方案 |
|----------|-------------|
| Title / 标题 | Event title / 日程标题 |
| Due date / 截止日期 | Event date (all-day) / 日程日期（全天事件） |
| Reminder / 提醒 | Event reminder / 日程提醒 |
| Complete / 完成 | Delete or move to "Completed" calendar / 删除或移到「已完成」日历 |
| Category / 分类 | Separate calendars / 不同日历区分 |

**Trade-off / 代价:** Todos display as events in calendar rather than a todo list format, but functionally sufficient. / 待办在日历里显示为事件而不是待办列表形式，但功能上够用。

---

## 四、DAVx5 Setup Guide for OPPO / DAVx5 安装配置指南（OPPO）

### Prerequisites / 前置条件
- Use VPN once to download DAVx5 from F-Droid or Google Play / 开一次梯子，从F-Droid或Google Play下载安装DAVx5
- No VPN needed for daily use / 日常使用不需要梯子

### Setup Steps / 配置步骤
1. Delete the read-only CalDAV account previously added in OPPO Calendar / 删除OPPO系统日历里之前加的只读CalDAV账户
2. Open DAVx5 → Add Account / 打开DAVx5 → 添加账户
3. Select "Login with URL" / 选择「Login with URL」
4. Base URL: `https://icloud.com`
5. User name: Apple ID (phone number) / Apple ID（手机号）
6. Password: Generate App-Specific Password at appleid.apple.com / 去 appleid.apple.com 生成App专用密码
7. After connection, select calendars to sync / 连接成功后选择要同步的日历
8. OPPO Calendar can now view and edit iCloud events / OPPO系统日历就能正常查看和编辑iCloud日程了

### Notes / 注意事项
- China iCloud: calendar uses `https://icloud.com`, contacts use `https://contacts.icloud.com.cn` / 中国区iCloud区分地址
- App-Specific Password cannot be replaced with Apple ID login password / App专用密码不能用Apple ID登录密码代替
- DAVx5 auto-syncs in background, sync frequency is adjustable / DAVx5在后台自动同步，同步频率可调

---

## 五、Hermes Integration / Hermes 集成方式

### Calendar Operations (Verified) / 日程操作（已验证可用）
```bash
# Via AppleScript operating Calendar.app / 通过AppleScript操作Calendar.app
osascript -e 'tell application "Calendar" to ...'

# Read events / 读取日程
osascript -e 'tell application "Calendar" to get every event of calendar "日历"'

# Write events / 写入日程
osascript -e 'tell application "Calendar" to make new event at calendar "待办" with properties {summary:"Title", start date:date "2026/4/17", end date:date "2026/4/17"}'
```

### Todo Operations (Same approach — write calendar events to "Todos" calendar) / 待办操作（方案同上）
- Create todo = create all-day calendar event / 创建待办 = 创建全天日程事件
- Read todos = read events from "Todos" calendar / 读取待办 = 读取「待办」日历的事件
- Complete todo = delete event or move to "Completed" calendar / 完成待办 = 删除事件或移到「已完成」日历

### Permissions / 权限
- Mac Calendar: Python has full access (system settings authorized) / Mac日历：Python有完全访问权限（系统设置已授权）
- Reminders: remindctl has Full access (but this path deprecated) / 提醒事项：remindctl有Full access权限（但此路线已弃用）

---

## 六、Todo Items / 待执行事项

- [ ] Install DAVx5 on OPPO (requires VPN for download) / OPPO安装DAVx5（需开梯子下载）
- [ ] Configure DAVx5 with iCloud CalDAV account / DAVx5配置iCloud CalDAV账户
- [ ] Verify OPPO can read/write iCloud events via DAVx5 / 验证OPPO能通过DAVx5读写iCloud日程
- [ ] Create iCloud "Todos" calendar / 创建iCloud「待办」日历
- [ ] Test Hermes write todo → OPPO sync display / 测试Hermes写入待办 → OPPO同步显示
- [ ] Configure Windows Vivaldi with iCloud CalDAV / Windows Vivaldi配置iCloud CalDAV
- [ ] Clean up previous test events and todo data / 清理之前的测试日程和待办数据
- [ ] Consider encapsulating as Hermes Skill / 考虑是否需要封装为Hermes Skill

---

## 七、Lessons Learned / 踩过的坑

1. QQ Mail on Mac only has CardDAV (contacts), no CalDAV (calendar) — previous assumption was wrong / QQ邮箱Mac上只有CardDAV，没有CalDAV——之前假设错了
2. OPPO Calendar built-in CalDAV is castrated (read-only) — needs DAVx5 / OPPO系统日历自带CalDAV是阉割版——需要DAVx5
3. Apple Reminders killed CalDAV VTODO since iOS 13 — third-party clients can't sync Reminders / Apple提醒事项iOS 13后砍了CalDAV VTODO——第三方客户端无法同步提醒事项
4. Feishu todos are closed system, only API no CalDAV / 飞书待办是封闭系统，只有API没有CalDAV
5. "Todo List" app has no open API — Hermes can't access / "Todo清单"app没有开放API——Hermes无法访问
6. EventKit terminal process has no calendar permission — use AppleScript workaround / EventKit终端进程没有日历权限——用AppleScript绕过
7. pip install pyobjc-framework-EventKit timeout — abandoned this path / pip安装超时——放弃此路线
8. iCloud China node (p205-caldav.icloud.com.cn) works direct, no proxy needed / iCloud国内节点可直连，不需要代理
9. When Apple ID is phone number, DAVx5 needs "Login with URL" method / Apple ID是手机号时，DAVx5要用"Login with URL"方式
10. Todos and events are essentially the same thing — storing todos as events is the simplest solution / 待办和日程本质是一回事——用日程事件存储待办是最简方案
11. Don't assume China doesn't support CalDAV based on impressions — iCloud CalDAV works fine direct / 不要凭印象说国内不支持CalDAV——iCloud CalDAV国内直连正常
12. Windows built-in Calendar deliberately omits CalDAV option — use Vivaldi / Windows自带日历故意不给CalDAV选项——用Vivaldi
13. A weekend-demo-level project shouldn't spend too long in design phase / 一个周末能出Demo的东西，不要在设计阶段打转太久
14. Target GitHub technical users first, then upgrade for general users — this strategy is sound / 先面向GitHub技术用户做到满意，再升级到小白用户——这个策略合理

---

## 八、Archived: Product Vision Discussion / 历史产品化讨论（归档）

> The following is from 2026-04-15 product vision discussion, to be revisited after personal validation.
> 以下为2026-04-15的产品化愿景讨论，待个人验证完成后视情况推进。

### Product Layers / 产品分层

```
1. Core Engine / 核心引擎 (Core)    — The working code: CalDAV read/write, sync logic / 干活的代码
2. Config Layer / 配置层 (Config)    — User settings: email, auth codes, preferences / 用户设置
3. Interface / 接入层 (Interface)    — How users interact: CLI / API / Skill / Bot / 用户怎么用它
4. Onboarding / 引导层 (Onboarding) — New user setup: config wizard, tutorials / 新用户上手
5. Ops / 运维层 (Ops)               — Deployment, updates, error monitoring / 部署、更新、错误监控
6. Ecosystem / 生态层 (Ecosystem)   — Community, docs, plugin marketplace / 社区、文档、插件市场
```

### Progressive Path / 渐进路径

| Stage / 阶段 | Deliverable / 交付物 | Audience / 受众 | Effort / 工作量 |
|------|--------|------|--------|
| MVP | Python package (pip install) + Hermes Skill / Python包 + Hermes Skill | Self + GitHub tech users / 自己 + GitHub技术用户 | 1-2 days / 天 |
| v0.1 | + MCP Server | All AI assistant users / 所有AI助手用户 | +1 day / 天 |
| v0.2 | + Feishu/DingTalk Bot / + 飞书/钉钉机器人 | China enterprise users / 国内企业用户 | +2-3 days / 天 |
| v1.0 | + Web UI / multi-user / + Web UI / 多用户 | Everyone / 所有人（小白） | +1-2 weeks / 周 |

### GitHub Environment (Ready) / GitHub 环境（已就绪）

| Item / 项目 | Status / 状态 |
|------|------|
| git | 2.50.1 ✅ |
| gh CLI | 2.86.0 ✅ |
| GitHub account / GitHub账号 | liuchangchxy ✅ |
| Token permissions / Token权限 | repo, workflow, gist, read:org ✅ |
| Auth method / 认证方式 | keyring (HTTPS) ✅ |

---

## 九、Round 2 Research: Existing Solutions & Market Gap / 第二轮调研：现成轮子与市场空白（2026-04-16）

> Trigger: User asked "Should we use Feishu/Notion? Is there an existing open-source app that supports both calendar + todos + cross-platform?" / 起因：用户追问"到底要不要用飞书/Notion？有没有现成的开源软件同时支持日历+待办+全平台？"
> Conclusion: **No. This is a genuine market gap.** / 结论：**没有。这是一个真实的市场空白。**

### 9.1 Feishu vs Notion Conclusion / 飞书 vs Notion 结论

**Feishu / 飞书**: Enterprise collaboration platform, too heavy for personal use. Calendar has CalDAV but todos are closed (API only, no CalDAV VTODO). Not recommended. / 面向企业的协作平台，个人使用过于繁重。日历有CalDAV同步但待办是封闭系统。不推荐。

**Notion**: Has API (Hermes can read/write), but calendar is just a database view (Calendar View), not a real calendar protocol. No CalDAV/CalSync, no push notifications, can't sync with phone system calendar. Calendar features are weak. Not ideal. / 有API（Hermes可读写），但日历只是数据库视图，不是真正的日历协议实现。没有CalDAV、没有推送通知、不能跟手机系统日历同步。不理想。

### 9.2 Backend/AI Interface Layer: Existing Solutions / 后端/AI接口层：有现成轮子

| Component / 组件 | Name / 名称 | Description / 说明 | License / 协议 |
|------|------|------|------|
| CalDAV server / CalDAV服务器 | **Radicale** | pip install radicale, pure Python, stores .ics files, zero config / 纯Python，存.ics文件，零配置 | AGPLv3 |
| AI Agent interface / AI Agent接口 | **dav-mcp** | npm package, 26 MCP tools, exposes CalDAV calendar+VTODO+CardDAV to AI Agent / npm包，26个MCP工具 | MIT |
| Alt CalDAV / 备选CalDAV | Nextcloud Calendar | Web calendar + tasks, poor mobile UX / Web端日历+任务都有，但移动端体验差 | AGPLv3 |
| Alt CalDAV / 备选CalDAV | Baikal | Lightweight CalDAV+CardDAV server / 轻量CalDAV+CardDAV服务器 | GPL |

**Simplest deployment: Radicale (storage/sync) + dav-mcp (Agent interface)** / **最简落地组合：Radicale + dav-mcp**

Architecture / 架构：
```
Radicale (CalDAV storage) ↔ CalDAV protocol ↔ Native clients (mobile/desktop)
                              ↕
                        dav-mcp (MCP tools)
                              ↕
                        Hermes / AI Agent
```

### 9.3 Client Layer: The Real Gap / 客户端层：真正的空白

**Core finding: CalDAV protocol supports both VEVENT (calendar) + VTODO (todo), but the client layer is completely fragmented.** / **核心发现：协议层CalDAV同时支持VEVENT（日历）+ VTODO（待办），但客户端层全碎了。**

| Client / 客户端 | Calendar / 日历 | Todos / 待办 | Cross-platform / 跨平台 | CalDAV | Open Source / 开源 | Issues / 问题 |
|--------|------|------|--------|--------|------|------|
| Apple Calendar / Apple日历 | ✅ | ❌ | Apple only | ✅ | ❌ | No todos / 不看待办 |
| Apple Reminders / Apple提醒事项 | ❌ | ✅ | Apple only | Cut / 砍了 | ❌ | No CalDAV since iOS13 / iOS13后无CalDAV |
| Google Calendar | ✅ | ❌ | ✅ | ❌ | ❌ | No VTODO / 不处理VTODO |
| DAVx5 + Tasks.org | ✅ | ✅ | Android only | ✅ | ✅ | Two apps, calendar and todos separate / 两个app，日历和待办分开 |
| Thunderbird | ✅ | ✅ | Desktop only | ✅ | ✅ | No mobile / 没有移动端 |
| KDE Kalendar | ✅ | ✅ | Linux/KDE only | ✅ | ✅ | Linux only / 只有Linux |
| Fossify Calendar | ✅ | ❌ | Android only | ✅ | ✅ | VTODO not implemented (issue #36, 132👍) / VTODO支持未实现 |
| Etar Calendar | ✅ | Partial / 部分 | Android only | ✅ | ✅ | VTODO PR unmerged (3 years) / VTODO PR未合并 |
| Vikunja | Weak / 弱 | ✅ | Web/PWA | ✅ | ✅ | Weak calendar view, no native app / 日历视图弱，无原生app |
| Nextcloud Calendar | ✅ | ✅ | Web only | ✅ | ✅ | Poor mobile UX / 移动端体验差 |

**Conclusion: No single client satisfies "calendar + todo unified + cross-platform + CalDAV sync + open source".** / **结论：没有任何一个客户端同时满足"日历+待办一体 + 全平台 + CalDAV同步 + 开源"。**

### 9.4 Why Hasn't Anyone Done It? / 为什么没人做？

Summarized from Fossify Calendar issue #36 discussion:
从Fossify Calendar的issue #36讨论总结：

1. **Android API fragmentation / Android API分裂**: Calendar uses CalendarContract, todos use each task app's own Contract (Tasks.org, OpenTasks each have their own), handling two sync mechanisms in one app doubles the work / 日历走CalendarContract，待办走各个task app自己的Contract，要在一个app里处理两套同步机制，工作量翻倍
2. **Apple closed ecosystem / Apple封闭生态**: iOS 13 cut Reminders CalDAV VTODO, non-Apple devices can't sync / iOS 13后砍了提醒事项的CalDAV VTODO，非Apple设备无法同步
3. **Commercial products take different paths / 商业产品路径不同**: Closed-source competitors (Motion, Akiflow) use proprietary protocols instead of CalDAV / 闭源竞品选择自有协议不走CalDAV
4. **Open source community lacks motivation / 开源社区动力不足**: Many people build backends (Radicale/Nextcloud), few build clients, almost none build "calendar + todo unified" clients / 做后端的人多，做客户端的人少，做"日历+待办合并"客户端的人几乎没有

### 9.5 Closed-Source Competitors / 闭源竞品参考

| Product / 产品 | What they did / 做了什么 | Issues / 问题 |
|------|----------|------|
| **Motion** | Calendar + todo fusion + AI auto-scheduling / 日历+待办融合+AI自动排程 | Closed source, expensive, $19/mo / 闭源，贵 |
| **Akiflow** | Multi-source events + task aggregation into calendar / 多来源事件+任务聚合到日历 | Closed source / 闭源 |
| **Cron (acquired by Notion)** | Beautiful calendar + later-added todos / 漂亮的日历+后加待办 | Closed source / 闭源 |
| **Plazen** | Open source task management + auto-scheduling / 开源任务管理+自动排入时间表 | Archived March 2026, dead project / 2026年3月已archived，死项目 |

### 9.6 If We Build This / 如果要造这个轮子

**Entry point: CalDAV native client that renders both VEVENT and VTODO in a single calendar view.** / **切入点：CalDAV原生客户端，同时渲染VEVENT和VTODO到一个日历视图。**

Technical route options / 技术路线选择：
- **Option A: Fork Fossify Calendar + add VTODO** — Android only, but best foundation (2k stars, Material Design) / Android only，但基础最好
- **Option B: Build from scratch with Compose Multiplatform** — Cross Android/iOS/desktop, but high effort / 跨Android/iOS/桌面，但工作量大
- **Option C: Web-first (Next.js/PWA)** — Fastest MVP, all platforms via browser, but poor native UX / 最快出MVP，但原生体验差

Backend doesn't need building — Radicale + dav-mcp are ready. / 后端不需要造，Radicale + dav-mcp现成。

### 9.7 APP System Calendar/Alarm Integration / APP与系统日历/闹钟对接方案

**Question: How do in-app calendar events trigger system alarms, reminders, and notifications?** / **问题：自建APP里的日历事件，怎么触发系统闹钟、提醒、通知？**

**Answer: Through the OS "system calendar database" middleware.** / **答案：通过操作系统的"系统日历数据库"中间层。**

Both Android and iOS have system-level calendar databases. Any app can write to them, and the OS automatically handles alarms, reminders, and notification popups. / Android和iOS都有系统级日历数据库，任何APP都可以写入，写入后系统自动负责闹钟、提醒、通知弹出。

```
Your APP / 你的APP
  ├── Own database (calendar + todos, extended fields) / 自己的数据库
  ├── CalDAV sync (with Radicale/other servers) / CalDAV同步
  └── System calendar sync (write to CalendarProvider/EventKit) / 系统日历同步
        ↓
      System alarm/reminder/notification auto-enabled / 系统闹钟/提醒/通知自动生效
      System calendar app can see / 系统日历app也能看到
      Desktop widget can read / 桌面widget也能读取
```

**DAVx5 is a proven precedent:** Pulls from CalDAV → writes to CalendarProvider → system calendar and alarms all work. / **DAVx5就是验证过的先例。**

Platform APIs / 各平台具体API：

| Platform / 平台 | API | Write System Calendar / 写入系统日历 | System Reminder / 系统提醒 |
|------|-----|-------------|---------|
| Android | CalendarProvider | ✅ | ✅ AlarmManager |
| iOS | EventKit | ✅ | ✅ System notification / 系统通知 |
| macOS | EventKit | ✅ | ✅ System notification / 系统通知 |
| Windows | Windows.ApplicationModel.Appointments | ✅ | ✅ System notification / 系统通知 |

**Conclusion: This is not an obstacle. APP uses its own database for complete data, while pushing a copy to the system calendar database. Alarms/reminders/notifications are all handled by the OS.** / **结论：这不是障碍。APP内部用自有数据库存储完整数据，同时通过系统日历API推一份到系统数据库，闹钟/提醒/通知就全是系统的活了。**

### 9.8 Next Decision Points / 下一步决策点

- [ ] Use Radicale + dav-mcp + native clients (separate calendar/todo apps) for now? / 先用Radicale + dav-mcp + 原生客户端凑合用？
- [ ] Or start building the client? / 还是直接开始造客户端轮子？
- [ ] If building, which route: A/B/C? / 如果造，选方案A/B/C哪条路？
- [ ] MVP Android-only or cross-platform from start? / MVP只做Android还是一上来就跨平台？
