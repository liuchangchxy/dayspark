# DaySpark (灵光) — Project Rules

## 元法则（Meta-Rules）
以下四条是所有具体规则和操作流程的来源依据。若具体规则与元法则冲突，以元法则为准。

1. **溯源法则**：每个用户反馈必须建立"原文 → todo → 代码"的可追踪链路。完成检查时，验证依据是**原文**，不是 todo 列表。→ 可避免：漏改、假完成。
2. **根因法则**：修复任何失败前，必须先定位根因。不做猜测式修复。→ 可避免：修多次修不对、引入新问题。
3. **正交验证法则**：验证一件事的手段必须独立于做这件事的手段。修代码的人不独自验证、验证清单不来自 todo 而来自原文、CI 配置变更先普通 push 验证再打 tag。→ 可避免：自己骗自己。
4. **平台感知法则**：任何 UI/交互改动，必须显式考虑所有目标平台的差异（桌面鼠标 vs 移动触摸），而不是只在一个平台上验证。→ 可避免：跨平台不兼容。

---

## 项目总览 / Project Overview

Flutter + Dart | Drift (SQLite) | Riverpod | go_router | home_widget | mcp_dart | alarm | local_auth | workmanager

- 开源日历待办 App，支持 CalDAV 同步 + AI + MCP server
- GitHub: https://github.com/liuchangchxy/dayspark
- Package: `dayspark`, Android: `com.dayspark.app`
- Current version: `0.20.4+22`
- 项目功能状态：`docs/ROADMAP.md`
- 技术约束记录：`docs/CONSTRAINTS.md`

---

## 协作守则 / Collaboration

第一条：**用户明确要求写入规则时，立即提炼写入本文件。** 不主动存，等用户要求再存。

修改依赖/CI/平台构建前，先读 `docs/CONSTRAINTS.md`。修 bug 或做关键决策后，更新同一文件记录约束。

**用户反馈视为产品设计意图**，不是单纯的 bug 报告。遇到模糊反馈先提问确认意图，不自行假设后直接改代码。

---

## 开发规范 / Code Standards

### 代码风格
- Single quotes, trailing commas, explicit return types
- `debugPrint` not `print`；**No comments** unless WHY is non-obvious
- No emojis in code, no docstrings

### 架构
| 层 | 位置 | 说明 |
|----|------|------|
| Providers | `lib/domain/providers/` | Riverpod, watch `databaseProvider`, delegate to DAO |
| DAOs | `lib/data/local/database/daos/` | Drift `@DriftAccessor` |
| Pages | `lib/ui/pages/<feature>/` | 命名 `<feature>_<action>_page.dart` |
| Routing | `lib/core/router/app_router.dart` | go_router 扁平路由 |
| Theme | `lib/core/theme/` | `AppTheme.light(seedColor:)` / `AppTheme.dark(seedColor:)` |
| l10n | `lib/l10n/app_en.arb` + `app_zh.arb` | 中英双语同步，改后 `flutter gen-l10n` |

### UI 原则
- 信息密度优先，不大圆角、不渐变、不 AI 味
- `CupertinoIcons` 而非 `Icons`；Material 3；FilledButton 主操作
- 新增文本必须加 l10n key（中英双语），禁止硬编码

---

## 发版流程 / Release Pipeline

### 前置检查（每次 push 前）
1. `flutter analyze` — **零 issue**
2. `flutter test` — **全绿**
3. 验证后跑 `flutter build macos --debug` + `flutter build apk --debug` + `flutter build web --debug`

### 版本规则
4. `pubspec.yaml`: `0.x+N` 格式，**1.0 之前不跳版**
5. 所有 release 标记为 **pre-release**（`release.yml` 已自动处理）
6. 1.0 之前所有 release 标记为 **pre-release**

### 操作流程
7. Commit → **ask user to confirm** → push
8. CI 不放 `dart format --set-exit-if-changed`，不用 `--no-fatal-infos`
9. 新增依赖前检查 macOS Xcode SDK 兼容性
10. 用户反馈整理后存入 `docs/changelog.md`
11. Linux 构建锁 `runs-on: ubuntu-22.04`（GLIBC 2.35），新增原生依赖后跑 `tool/check_glibc_version.sh`

### 完整工作流
所有工作走：理解 → 实现 → 验证 → 确认 → 文档 → 推送 → 验收

详见 `.claude/skills/release-prep/SKILL.md`

---

## 变更追踪 / Change Tracking

| 文件 | 用途 | 何时更新 |
|------|------|----------|
| `docs/changelog.md` | 用户反馈日志 | 收到反馈后 |
| `docs/ROADMAP.md` | 功能演进全景 | 版本更新时 |
| `docs/CONSTRAINTS.md` | 技术约束 | 修 bug/关键决策后 |
| `CLAUDE.md` | 项目规则 | 用户要求时 / 流程改进时 |
