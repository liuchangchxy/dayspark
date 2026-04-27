# 跨平台日历 & 待办同步方案

> 创建时间: 2026-04-15
> 最后更新: 2026-04-16 (第二轮讨论)
> 状态: 方案验证 + 市场调研阶段

---

## 一、背景

### 用户场景
多台设备（OPPO安卓 + Windows + Mac + iPad），需要一个统一的日历和待办同步系统，国内直连不用代理。

### 核心约束
- 国内环境，不能始终依赖代理
- 需要国内能直连的方案
- Hermes（AI助手）需要能读写日历和待办数据
- 用户随时随地在任何设备能查看和录入

---

## 二、实测结论（2026-04-16）

### 关键发现

#### 1. QQ邮箱没有CalDAV日历，只有CardDAV通讯录
通过查系统账户数据库（Accounts4.sqlite）确认：
- Account 7 = iCloud CalDAV (p205-caldav.icloud.com.cn) → 日程+提醒事项
- Account 17 = QQ账号 (1344967911@qq.com) → 仅QQ服务
- Account 19 = QQ CardDAV (dav.qq.com) → 仅通讯录同步
- **不存在QQ邮箱CalDAV日历账户**
- 之前"已有QQ邮箱CalDAV日历"的假设是错误的

#### 2. 日程方案：iCloud CalDAV（已确定）
- Mac系统日历通过iCloud CalDAV同步（已验证）
- iCloud国内节点：p205-caldav.icloud.com.cn，国内直连
- Hermes通过AppleScript读写Mac日历 → 自动同步到iCloud → 所有设备
- Apple ID是手机号（8617852413507）

#### 3. OPPO系统日历自带CalDAV是阉割版（只读）
- OPPO系统日历添加CalDAV后显示"订阅日历，无法移动"
- 只实现了CalDAV的订阅（读取），没有实现写入
- **需要安装DAVx5**才能获得iCloud CalDAV的读写能力
- DAVx5下载需梯子（F-Droid/Play商店），日常运行不需梯子
- DAVx5配置：Login with URL → `https://icloud.com` → 手机号 + App专用密码

#### 4. Apple提醒事项iOS 13后砍了CalDAV VTODO
- DAVx5官方文档明确说明：升级提醒事项后CalDAV功能被Apple移除
- 非Apple设备无法通过CalDAV同步提醒事项
- 这条路彻底堵死

#### 5. 飞书日历支持CalDAV同步，但待办是封闭的
- 飞书日历有原生CalDAV：日历→设置→同步到本地日历（caldav.feishu.cn）
- 飞书任务/待办只有API接口（需企业自建应用），无CalDAV VTODO
- 飞书待办只能在飞书app内查看

#### 6. "Todo清单"app是封闭系统
- 开发商：杭州乾夕科技（evestudio.cn）
- 全平台（Android/iOS/Windows/Mac/iPad/手表）
- 能读取系统日历显示在app内，但待办数据不能同步回系统
- **没有开放API**，无API文档、无开放平台、无Webhook
- Hermes无法访问

---

## 三、最终方案

### 日程：iCloud CalDAV（全设备同步）

| 设备 | 方案 | 状态 |
|------|------|------|
| Mac | 系统日历（iCloud账户，已连通） | ✅ 已验证 |
| iPad | 系统日历（iCloud账户） | ✅ 应可用 |
| OPPO | DAVx5 + 系统日历 | ⏳ 待安装DAVx5 |
| Windows | Vivaldi浏览器日历 + iCloud CalDAV | ⏳ 待配置 |

Hermes通过AppleScript操作Mac日历 → iCloud自动同步到所有设备。

### 待办：全部当日程事件存入iCloud日历

**核心思路：** 不用待办协议，把待办当日程事件处理。

- 在iCloud里建一个专门的日历，叫「待办」
- 每个待办 = 一个全天日程事件（标题 + 截止日期 + 提醒）
- Hermes通过AppleScript读写这个日历
- iCloud CalDAV同步到所有设备
- 用户在任何设备的系统日历里都能看到待办

**功能对照：**
| 待办需求 | 日程事件方案 |
|----------|-------------|
| 标题 | 日程标题 |
| 截止日期 | 日程日期（全天事件） |
| 提醒 | 日程提醒 |
| 完成 | 删除或移到「已完成」日历 |
| 分类 | 不同日历区分 |

**代价：** 待办在日历里显示为事件而不是待办列表形式，但功能上够用。

---

## 四、DAVx5 安装配置指南（OPPO）

### 前置条件
- 开一次梯子，从F-Droid或Google Play下载安装DAVx5
- 日常使用不需要梯子

### 配置步骤
1. 删除OPPO系统日历里之前加的只读CalDAV账户
2. 打开DAVx5 → 添加账户
3. 选择「Login with URL」
4. Base URL: `https://icloud.com`
5. User name: Apple ID（手机号 8617852413507）
6. Password: 去 appleid.apple.com 生成App专用密码
7. 连接成功后选择要同步的日历
8. 同步完成后，OPPO系统日历就能正常查看和编辑iCloud日程了

### 注意事项
- 中国区iCloud：日历用 `https://icloud.com`，通讯录用 `https://contacts.icloud.com.cn`
- App专用密码不能用Apple ID登录密码代替
- DAVx5在后台自动同步，同步频率可调

---

## 五、Hermes 集成方式

### 日程操作（已验证可用）
```bash
# 通过AppleScript操作Calendar.app
osascript -e 'tell application "Calendar" to ...'

# 读取日程
osascript -e 'tell application "Calendar" to get every event of calendar "日历"'

# 写入日程
osascript -e 'tell application "Calendar" to make new event at calendar "待办" with properties {summary:"标题", start date:date "2026/4/17", end date:date "2026/4/17"}'
```

### 待办操作（方案同上，写日程事件到「待办」日历）
- 创建待办 = 创建全天日程事件
- 读取待办 = 读取「待办」日历的事件
- 完成待办 = 删除事件或移到「已完成」日历

### 权限
- Mac日历：Python有完全访问权限（系统设置已授权）
- 提醒事项：remindctl有Full access权限（但此路线已弃用）

---

## 六、待执行事项

- [ ] OPPO安装DAVx5（需开梯子下载）
- [ ] DAVx5配置iCloud CalDAV账户
- [ ] 验证OPPO能通过DAVx5读写iCloud日程
- [ ] 创建iCloud「待办」日历
- [ ] 测试Hermes写入待办 → OPPO同步显示
- [ ] Windows Vivaldi配置iCloud CalDAV
- [ ] 清理之前的测试日程和待办数据
- [ ] 考虑是否需要封装为Hermes Skill

---

## 七、踩过的坑

1. QQ邮箱Mac上只有CardDAV（通讯录），没有CalDAV（日历）——之前假设错了
2. OPPO系统日历自带CalDAV是阉割版（只读）——需要DAVx5
3. Apple提醒事项iOS 13后砍了CalDAV VTODO——第三方客户端无法同步提醒事项
4. 飞书待办是封闭系统，只有API没有CalDAV
5. "Todo清单"app没有开放API——Hermes无法访问
6. EventKit终端进程没有日历权限——用AppleScript绕过
7. pip安装pyobjc-framework-EventKit超时——放弃此路线
8. iCloud国内节点(p205-caldav.icloud.com.cn)可直连，不需要代理
9. Apple ID是手机号时，DAVx5要用"Login with URL"方式
10. 待办和日程本质是一回事——用日程事件存储待办是最简方案
11. 不要凭印象说国内不支持CalDAV——iCloud CalDAV国内直连正常
12. Windows自带日历故意不给CalDAV选项——用Vivaldi
13. 一个周末能出Demo的东西，不要在设计阶段打转太久
14. 先面向GitHub技术用户做到满意，再升级到小白用户——这个策略合理

---

## 八、历史产品化讨论（归档）

> 以下为2026-04-15的产品化愿景讨论，待个人验证完成后视情况推进。

### 产品分层

```
1. 核心引擎（Core）     — 干活的代码：CalDAV读写、同步逻辑
2. 配置层（Config）     — 用户设置：邮箱、授权码、偏好
3. 接入层（Interface）  — 用户怎么用它：CLI / API / Skill / 机器人
4. 引导层（Onboarding） — 新用户上手：配置引导、教程
5. 运维层（Ops）        — 部署、更新、错误监控
6. 生态层（Ecosystem）  — 社区、文档、插件市场
```

### 渐进路径

| 阶段 | 交付物 | 受众 | 工作量 |
|------|--------|------|--------|
| MVP | Python包(pip install) + Hermes Skill | 自己 + GitHub技术用户 | 1-2天 |
| v0.1 | + MCP Server | 所有AI助手用户 | +1天 |
| v0.2 | + 飞书/钉钉机器人 | 国内企业用户 | +2-3天 |
| v1.0 | + Web UI / 多用户 | 所有人（小白） | +1-2周 |

### GitHub 环境（已就绪）

| 项目 | 状态 |
|------|------|
| git | 2.50.1 ✅ |
| gh CLI | 2.86.0 ✅ |
| GitHub账号 | liuchangchxy ✅ |
| Token权限 | repo, workflow, gist, read:org ✅ |
| 认证方式 | keyring (HTTPS) ✅ |

---

## 九、第二轮调研：现成轮子与市场空白（2026-04-16）

> 起因：刘畅追问"到底要不要用飞书/Notion？有没有现成的开源软件同时支持日历+待办+全平台？"
> 结论：**没有。这是一个真实的市场空白。**

### 9.1 飞书 vs Notion 结论

**飞书**：面向企业的协作平台，个人使用过于繁重。日历有CalDAV同步但待办是封闭系统（只有API无CalDAV VTODO）。不推荐。

**Notion**：有API（Hermes可读写），但日历只是数据库视图（Calendar View），不是真正的日历协议实现。没有CalDAV/CalSync、没有推送通知、不能跟手机系统日历同步。日历功能弱。不理想。

### 9.2 后端/AI接口层：有现成轮子

| 组件 | 名称 | 说明 | 协议 |
|------|------|------|------|
| CalDAV服务器 | **Radicale** | pip install radicale，纯Python，存.ics文件，零配置 | AGPLv3 |
| AI Agent接口 | **dav-mcp** | npm包，26个MCP工具，暴露CalDAV日历+VTODO+CardDAV给AI Agent | MIT |
| 备选CalDAV | Nextcloud Calendar | Web端日历+任务都有，但移动端体验差 | AGPLv3 |
| 备选CalDAV | Baikal | 轻量CalDAV+CardDAV服务器 | GPL |

**最简落地组合：Radicale（存储同步）+ dav-mcp（Agent接口）**

这条路的架构：
```
Radicale（CalDAV存储）↔ CalDAV协议 ↔ 原生客户端（手机/桌面）
                          ↕
                    dav-mcp（MCP工具）
                          ↕
                    Hermes / AI Agent
```

### 9.3 客户端层：真正的空白

**核心发现：协议层CalDAV同时支持VEVENT（日历）+ VTODO（待办），但客户端层全碎了。**

| 客户端 | 日历 | 待办 | 跨平台 | CalDAV | 开源 | 问题 |
|--------|------|------|--------|--------|------|------|
| Apple日历 | ✅ | ❌ | Apple only | ✅ | ❌ | 不看待办 |
| Apple提醒事项 | ❌ | ✅ | Apple only | 砍了 | ❌ | iOS13后无CalDAV |
| Google Calendar | ✅ | ❌ | ✅ | ❌ | ❌ | 不处理VTODO |
| DAVx5 + Tasks.org | ✅ | ✅ | Android only | ✅ | ✅ | 两个app，日历和待办分开 |
| Thunderbird | ✅ | ✅ | 桌面 only | ✅ | ✅ | 没有移动端 |
| KDE Kalendar | ✅ | ✅ | Linux/KDE only | ✅ | ✅ | 只有Linux |
| Fossify Calendar | ✅ | ❌ | Android only | ✅ | ✅ | VTODO支持未实现（issue #36，132👍） |
| Etar Calendar | ✅ | 部分 | Android only | ✅ | ✅ | VTODO PR未合并（3年） |
| Vikunja | 弱 | ✅ | Web/PWA | ✅ | ✅ | 日历视图弱，无原生app |
| Nextcloud Calendar | ✅ | ✅ | Web only | ✅ | ✅ | 移动端体验差 |

**结论：没有任何一个客户端同时满足"日历+待办一体 + 全平台 + CalDAV同步 + 开源"。**

### 9.4 为什么没人做？

从Fossify Calendar的issue #36讨论总结：

1. **Android API分裂**：日历走CalendarContract，待办走各个task app自己的Contract（Tasks.org、OpenTasks各有各的），要在一个app里处理两套同步机制，工作量翻倍
2. **Apple封闭生态**：iOS 13后砍了提醒事项的CalDAV VTODO，非Apple设备无法同步
3. **商业产品路径不同**：闭源竞品（Motion、Akiflow）选择自有协议不走CalDAV，开了自己的生态
4. **开源社区动力不足**：做后端的人多（Radicale/Nextcloud），做客户端的人少，做"日历+待办合并"客户端的人几乎没有

### 9.5 闭源竞品参考

| 产品 | 做了什么 | 问题 |
|------|----------|------|
| **Motion** | 日历+待办融合+AI自动排程 | 闭源，贵，$19/月 |
| **Akiflow** | 多来源事件+任务聚合到日历 | 闭源 |
| **Cron（被Notion收了）** | 漂亮的日历+后加待办 | 闭源 |
| **Plazen** | 开源任务管理+自动排入时间表 | 2026年3月已archived，死项目 |

### 9.6 如果要造这个轮子

**切入点：CalDAV原生客户端，同时渲染VEVENT和VTODO到一个日历视图。**

技术路线选择：
- **方案A：fork Fossify Calendar加VTODO** —— Android only，但基础最好（2k stars，Material Design）
- **方案B：从零用Compose Multiplatform写** —— 跨Android/iOS/桌面，但工作量大（参考XCalendar，196 stars，纯日历无待办）
- **方案C：Web-first（Next.js/PWA）** —— 最快出MVP，全平台通过浏览器用，但原生体验差

后端不需要造，Radicale + dav-mcp现成。

### 9.7 APP与系统日历/闹钟对接方案

**问题：自建APP里的日历事件，怎么触发系统闹钟、提醒、通知？**

**答案：通过操作系统的"系统日历数据库"中间层。**

Android和iOS都有系统级日历数据库，任何APP都可以写入，写入后系统自动负责闹钟、提醒、通知弹出。

```
你的APP
  ├── 自己的数据库（日历+待办，扩展字段）
  ├── CalDAV同步（跟Radicale/其他服务器互通）
  └── 系统日历同步（写到CalendarProvider/EventKit）
        ↓
      系统闹钟/提醒/通知自动生效
      系统日历app也能看到
      桌面widget也能读取
```

**DAVx5就是验证过的先例：** 从CalDAV拉数据 → 写入CalendarProvider → 系统日历和闹钟全部生效。

各平台具体API：

| 平台 | API | 写入系统日历 | 系统提醒 |
|------|-----|-------------|---------|
| Android | CalendarProvider | ✅ | ✅ AlarmManager |
| iOS | EventKit | ✅ | ✅ 系统通知 |
| macOS | EventKit | ✅ | ✅ 系统通知 |
| Windows | Windows.ApplicationModel.Appointments | ✅ | ✅ 系统通知 |

**结论：这不是障碍。APP内部用自有数据库存储完整数据，同时通过系统日历API推一份到系统数据库，闹钟/提醒/通知就全是系统的活了。**

### 9.8 下一步决策点

- [ ] 先用Radicale + dav-mcp + 原生客户端（分开的日历/待办app）凑合用？
- [ ] 还是直接开始造客户端轮子？
- [ ] 如果造，选方案A/B/C哪条路？
- [ ] MVP只做Android还是一上来就跨平台？
