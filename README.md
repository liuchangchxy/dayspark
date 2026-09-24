# DaySpark / 灵光

[![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.41+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Web%20%7C%20Windows%20%7C%20Linux-green)](#)
[![Status](https://img.shields.io/badge/Status-v0.24.0--pre--release-orange)](https://github.com/liuchangchxy/dayspark/releases)

**灵光一闪，日程了然。**
*A flash of insight, your schedule at a glance.*

开源、自托管优先的日历与待办应用（对标 Todo清单 的执行向体验）。Flutter 全平台运行，数据同步与 AI 接口由你自己的服务器掌控。
An open-source, calendar & todo app with self-hosted sync and first-class AI control. Built with Flutter, runs everywhere.

---

## 功能 / Features

- **日历 / Calendar** — 月/周/日视图（kalender 库），RRULE 重复日程，节气/调休标记，点日期直接建事件 / Month/week/day views, recurring events, solar-term & work-shift markers
- **待办 / Todos** — 子任务、标签、优先级、回收站、**六件事收敛视图**（Ivy Lee）、隐藏已完成 / Subtasks, tags, priorities, trash, six-things convergence view
- **自托管同步 / Self-hosted Sync** — 自研 Dart 同步后端（Docker 单容器），多设备一致：幂等推送、字段级冲突合并、断线重连 / Own Dart sync backend in Docker: idempotent push, field-level merge, auto-reconnect
- **AI 接口 / MCP Server** — 后端内置 MCP：17 个日历/任务工具，OAuth 2.1 双轨（本地 Agent 走登录令牌，ChatGPT/Codex 走 OAuth）；配套 stdio 桥与 `dayspark` CLI / Built-in MCP with 17 tools, OAuth 2.1, stdio bridge and CLI
- **桌面小组件 / Widgets** — Android 三变体（今日/近七日/月点阵）+ iOS/macOS WidgetKit，勾选与快速添加 / Three Android variants + iOS/macOS widgets with quick-add
- **提醒 / Reminders** — 本地通知与精确闹钟，完成/改期/恢复全生命周期调度 / Full lifecycle scheduling (complete, reschedule, restore)
- **标签与搜索 / Tags & Search** — 彩色标签组织，全文搜索 / Colored tags, full-text search
- **ICS 导入/导出 / Import/Export** — 日历数据交换 / Calendar data interchange
- **国际化 / i18n** — 中文 + English（欢迎贡献更多语言）
- **离线优先 / Offline-first** — Drift 本地 SQLite 为权威存储，联网后增量同步 / Local SQLite is the source of truth; incremental sync when online
- **跨平台 / Cross-platform** — Android、iOS、macOS、Windows、Linux、Web

## 架构 / Architecture

```
Flutter 客户端（六平台）  ⇄  DaySpark 同步后端（NAS Docker）
  ├ 本地 SQLite（离线优先）      ├ 同步：游标 + 幂等 push + 字段级 LWW + SSE
  ├ kalender 日历视图            ├ AI：MCP（OAuth 2.1）+ 同源数据
  └ 桌面小组件                   └ SQLite 单文件存储
```

契约包 `dayspark_contracts` 是客户端与服务端共享的协议唯一真相源。详细设计见 [SPEC](SPEC.md)、[ROADMAP](docs/ROADMAP.md)、[约束与踩坑](docs/CONSTRAINTS.md)。

## 开始使用 / Getting Started

### 前置条件 / Prerequisites

- Flutter SDK ≥ 3.41（macOS/iOS 需 Xcode；Android 需 Android SDK）
- 自托管同步：Docker（可选，见 [部署指南](docs/DEPLOY.md)）

### 运行 / Run

```bash
flutter pub get
flutter run -d chrome     # Web
flutter run -d macos      # macOS
flutter test              # 测试 / Run tests
```

### 构建 / Build

```bash
flutter build web / macos / apk / ios
```

## 配置 / Configuration

- **AI（客户端自然语言创建）** — 设置 → AI 配置：任意 OpenAI 兼容 API，见 [AI 配置教程](docs/ai-setup.md)
- **AI（MCP：让 ChatGPT/Claude/Codex 操作你的日程）** — 部署后端后见 [MCP 配置教程](docs/mcp-setup.md)
- **多设备同步** — 设置 → 账号：注册/登录你的自托管服务器，见 [部署指南](docs/DEPLOY.md)

## 文档 / Documentation

- [接续入口 / START HERE](docs/START_HERE.md) — 新会话从这里开始 / Start here for new sessions
- [功能路线图 / Roadmap](docs/ROADMAP.md)
- [AI 配置 / AI Setup](docs/ai-setup.md)
- [MCP 配置 / MCP Setup](docs/mcp-setup.md)
- [部署指南 / Self-hosting & Deploy](docs/DEPLOY.md)
- [技术约束 / Constraints](docs/CONSTRAINTS.md) · [决策记录 / Decisions](DECISIONS.md) · [需求规范 / Spec](SPEC.md)
- [手工验收清单 / QA checklists](docs/qa/)

## 贡献 / Contributing

欢迎提交 Issue 和 Pull Request。详见 [贡献指南](CONTRIBUTING.md)。

## 更新日志 / Changelog

见 [GitHub Releases](https://github.com/liuchangchxy/dayspark/releases)。

## 致谢 / Acknowledgments

- [OpenCode](https://github.com/opencode-ai/opencode) · Claude Code · [Superpowers](https://github.com/claude-plugins) — 开发过程中使用的 AI 编码工具 / AI coding tools used in development
- AI 模型 / Models: DeepSeek、GLM (智谱)、小米 MiMo、Claude — 开发过程中使用的 AI 模型
- [kalender](https://pub.dev/packages/kalender) (KDAB) · [lunar](https://pub.dev/packages/lunar) — 关键开源依赖 / key open-source dependencies

## 许可证 / License

[GPLv3](LICENSE)
