# 需求清单

> **此文档已归档，不再更新。** 当前项目状态见 [docs/ROADMAP.md](ROADMAP.md)。
>
> 本文档严格来自用户的原始方案（`glowing-toasting-seal.md`），只记录用户明确要求的功能。
> 不包含 AI 自行添加的"应该有"的功能。

最后更新: 2026-04-19

---

## 核心定位

- 开源的、全平台日历 + 待办管理 APP
- 填补市场空白：没有开源客户端同时支持「日历 + 待办一体 + 全平台 + CalDAV 同步」
- 功能完整后再发布（非先出简版）
- 纯个人使用（无协作功能）
- AI 写代码、用户审核

---

## 一、平台要求

| 平台 | 批次 |
|------|------|
| Android | 第一批 |
| iOS | 第一批 |
| Web | 第一批 |
| Windows | 第一批 |
| macOS | 第一批 |
| Linux | 第一批 |
| 鸿蒙 | 第二批（Flutter-OH 或 ArkTS+ArkUI） |

---

## 二、日历功能（Phase 2）

- [x] 日/周/月视图切换
- [x] 事件创建（标题、日期时间、全天开关、描述、地点）
- [x] 事件编辑和删除
- [x] 重复事件（RRULE）
- [ ] 拖拽事件（方案提到 kalender 支持拖拽）
- [x] 事件在日历格子内显示为磁贴

---

## 三、待办功能（Phase 2）

- [x] 待办列表视图（独立 tab）
- [x] 待办创建（标题、截止日期、优先级、描述）
- [x] 待办编辑和删除
- [x] 完成追踪（标记完成、删除线显示）
- [x] 优先级：高/中/低（iCalendar 1/5/9）
- [x] 重复待办（RRULE）
- [x] 截止日期显示标签（逾期、今天、明天、日期）

---

## 四、搜索功能（Phase 2）

- [x] 全文搜索事件和待办
- [x] 搜索结果页（事件 + 待办合并显示）
- [x] 点击搜索结果跳转编辑页

---

## 五、CalDAV 同步（Phase 3）

- [x] CalDAV 账户配置（服务器地址、用户名、密码）
- [x] 日历列表发现（PROPFIND）
- [x] 全量同步（拉取 + 推送）
- [x] 增量同步（sync-token / ctag）✅ 已接线
- [x] VEVENT 同步
- [x] VTODO 同步
- [x] 双向同步（本地推服务器、服务器拉本地）
- [x] ETag 冲突检测
- [x] 冲突解决（服务端优先）
- [x] 离线同步队列（sync_queue 表）✅ 已接线
- [ ] 背景定时同步（默认 30 秒间隔）
- [x] 凭证安全存储（flutter_secure_storage）
- [ ] 多 CalDAV 账户同时连接
- [x] 账户管理页（添加/删除/编辑）
- [x] 同步状态显示（最后同步时间、同步按钮、进度指示）

---

## 六、通知与提醒（Phase 4）

- [x] 本地定时通知（flutter_local_notifications）
- [ ] 闹钟提醒（alarm 插件）— 用户意图是控制系统闹钟
- [ ] Android 桌面小组件
- [ ] iOS 桌面小组件（WidgetKit）
- [ ] macOS/Windows 桌面小组件

---

## 七、高级功能（Phase 5）

- [x] 标签/分类系统（名称 + 颜色，10 种预设色）
- [x] 标签关联事件（多对多）
- [x] 标签关联待办（多对多）
- [x] 优先级（高/中/低）
- [x] .ics 文件导出
- [x] .ics 文件导入 ✅ 已接线（file_picker）
- [x] 附件支持（事件和待办关联文件）✅ 已接线
- [ ] 渐进式披露设置（高级功能在设置中开关）

---

## 八、AI 集成（Phase 6）

- [x] AI API 配置页面（API Key、Base URL、模型选择）
- [x] 支持 OpenAI 兼容 API（含 Claude）
- [x] 自然语言输入解析（创建事件/待办时 AI 解析文本）
- [x] AI 自动排程（分析待办列表 + 日历空闲 → 推荐时间安排）✅ 已接线
- [x] 内置 AI 聊天界面（流式对话，查询日历数据）
- [x] 聊天中创建事件/待办（操作按钮）
- [ ] MCP Server（暴露日历/待办数据给外部 AI Agent）— 自研内嵌方案

---

## 九、UI/UX 设计要求

- [x] 功能导向极简设计
- [x] 拒绝"AI 味"（不大圆角、不渐变、信息密度优先）
- [x] 参考 Linear + Apple 日历风格
- [x] 色彩系统（tokenized light/dark）
- [x] 强调色蓝 #2563EB
- [x] 系统默认字体
- [x] 4px 基础间距单位
- [x] 圆角最大 12px（卡片 8px、按钮 6px）
- [x] 不用渐变
- [x] 不用 emoji
- [x] 深色模式支持
- [x] 主题切换 System/Light/Dark + 持久化
- [ ] 动画仅用于状态切换（0.2s ease）
- [ ] 最小阴影，用边框表达层级
- [ ] 最小触摸目标 48x48dp
- [ ] 色彩对比度 WCAG 2.1 AA

---

## 十、国际化（Phase 7）

- [x] 中文（zh-CN）和英文（en）
- [x] ARB 文件管理
- [ ] 日期/时间格式跟随系统 Locale
- [ ] 社区可贡献翻译（开源后）

---

## 十一、安全

- [x] 凭证存入 flutter_secure_storage
- [ ] 强制 HTTPS
- [ ] AI API Key 掩码显示
- [ ] 生物识别锁（Face ID / Touch ID）

---

## 十二、数据库

- [x] 9 张表（calendars, events, todos, tags, event_tags, todo_tags, attachments, sync_queue, reminders）
- [x] 本地 SQLite（Drift）作为唯一数据源
- [x] 响应式查询（Drift streams）
- [ ] 数据库迁移支持
- [ ] 数据库导出为 .db 文件

---

## 十三、备份与恢复

- [x] .ics 文件导出
- [ ] .ics 文件导入
- [ ] .db 数据库文件导出
- [ ] 云备份（可选）

---

## 十四、开源与合规

- [ ] GPLv3 许可证
- [ ] NOTICE 文件（第三方版权声明）
- [ ] 自动生成许可证页面（flutter_oss_licenses）
- [ ] GitHub 开源发布

---

## 十五、CI/CD

- [ ] GitHub Actions：dart analyze（每次 PR）
- [ ] GitHub Actions：flutter test
- [ ] GitHub Actions：多平台自动构建
- [ ] GitHub Releases：APK / IPA / 桌面安装包 / Web

---

## 十六、测试

- [x] 单元测试（91 个）
- [x] Widget 测试
- [ ] 集成测试（CalDAV 端到端）
- [ ] 各平台构建和运行验证

---

## 十七、发布

- [ ] iOS App Store 提交准备
- [ ] Android APK 发布
- [ ] 桌面安装包
- [ ] Web 部署
- [ ] 用户文档和自部署指南（含 Radicale）

---

## 十八、鸿蒙（Phase 8，第二批）

- [ ] Flutter-OH 环境搭建
- [ ] 鸿蒙平台适配
- [ ] 鸿蒙特有 API 对接（通知、小组件）
- [ ] 华为应用市场发布
