# DaySpark / 灵光

[![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.11+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Web%20%7C%20Windows%20%7C%20Linux-green)](#)
[![Pre-release](https://img.shields.io/badge/Status-Pre--release-orange)](https://github.com/liuchangchxy/dayspark/releases)

**灵光一闪，日程了然。**
*A flash of insight, your schedule at a glance.*

开源 AI 日历与待办应用。基于 Flutter，全平台运行。
An open-source, AI-powered calendar and todo app. Built with Flutter, runs everywhere.

<!-- Uncomment and replace with actual screenshots / 取消注释并替换为真实截图 -->
<!--
## Screenshots / 截图

<p float="left">
  <img src="docs/screenshots/calendar.png" width="240" />
  <img src="docs/screenshots/todos.png" width="240" />
</p>
-->

---

## 功能 / Features

- **日历 / Calendar** — 月/周/日视图，事件创建与重复日程（RRULE） / Month/week/day views with event creation and recurring events
- **待办 / Todos** — 优先级、截止日期、完成追踪、重复任务 / Priority levels, due dates, completion tracking, recurring tasks
- **CalDAV 同步 / Sync** — 双向同步任何 CalDAV 服务器 / Two-way sync with any CalDAV server (Radicale, Nextcloud, etc.)
- **AI 助手 / Assistant** — 自然语言创建事件/待办 / Natural language event/todo creation via OpenAI-compatible API
- **标签 / Tags** — 用彩色标签组织事件和待办 / Organize events and todos with colored tags
- **提醒 / Reminders** — 事件和截止日期自动通知 / Automatic notifications before events and due dates
- **搜索 / Search** — 全文搜索事件和待办 / Full-text search across events and todos
- **ICS 导入/导出 / Import/Export** — 日历数据交换 / Calendar data interchange
- **MCP 服务器 / MCP Server** — 通过本地 HTTP 接口暴露日历/待办数据给 AI Agent（仅桌面） / Expose calendar/todo data to AI agents via localhost HTTP (desktop only)
- **国际化 / i18n** — 中文 + English（欢迎贡献更多语言 / contribution welcome）
- **离线优先 / Offline-first** — 所有数据通过 Drift 存储在本地 SQLite / All data stored locally in SQLite via Drift
- **跨平台 / Cross-platform** — Web、macOS、iOS、Android、Windows、Linux

## 技术栈 / Tech Stack

- **Flutter** + Dart
- **Drift** (SQLite ORM) — 本地数据库 / local database
- **Riverpod** — 状态管理 / state management
- **go_router** — 路由 / navigation
- **自建日历视图** — 月/周/日视图（v0.13.0 起替代 kalender 库） / Self-built calendar views (replaced kalender library since v0.13.0)
- **Dio** — HTTP 客户端 / HTTP client (CalDAV)

## 开始使用 / Getting Started

### 前置条件 / Prerequisites

- Flutter SDK >= 3.11.0
- macOS/iOS: Xcode + CocoaPods
- Android: Android SDK
- Web: Chrome

### 安装与运行 / Install & Run

```bash
flutter pub get
dart run build_runner build
flutter run -d chrome    # Web
flutter run -d macos     # macOS
flutter test             # 运行测试 / Run tests
```

### 构建 / Build

```bash
flutter build web     # Web
flutter build macos   # macOS
flutter build apk     # Android
flutter build ios     # iOS
```

## 配置 / Configuration

### CalDAV
设置 → CalDAV 账户 → 输入服务器地址、用户名、密码
Settings → CalDAV Account → enter server URL, username, password.

### AI
设置 → AI 配置 → 输入 API Key、Base URL、模型名称。兼容任何 OpenAI 格式的 API。
Settings → AI Configuration → enter API key, base URL, model name. Works with any OpenAI-compatible API.

## 文档 / Documentation

- [功能演进 / Roadmap](docs/ROADMAP.md) — 功能状态与路线图 / Feature status and roadmap
- [AI 配置教程 / AI Setup](docs/ai-setup.md) — AI 助手配置指南 / AI assistant setup guide
- [CalDAV 配置教程 / CalDAV Setup](docs/caldav-setup.md) — CalDAV 同步配置指南 / CalDAV sync setup guide
- [MCP 配置教程 / MCP Setup](docs/mcp-setup.md) — MCP 服务器配置指南 / MCP server setup guide
- [CalDAV 同步方案 / Sync Plan](docs/caldav-sync-plan.md) — 同步架构设计 / Synchronization architecture

## 贡献 / Contributing

欢迎提交 Issue 和 Pull Request。详见 [贡献指南](CONTRIBUTING.md)。
Issues and pull requests are welcome. See [Contributing Guide](CONTRIBUTING.md) for details.

## 更新日志 / Changelog

See [GitHub Releases](https://github.com/liuchangchxy/dayspark/releases) for all release notes.
查看 [GitHub Releases](https://github.com/liuchangchxy/dayspark/releases) 获取所有版本的更新说明。

## 许可证 / License

[GPLv3](LICENSE)
