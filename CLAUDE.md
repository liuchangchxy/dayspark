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
- Current version: `0.20.5+23`
- 项目功能状态：`docs/ROADMAP.md`
- 技术约束记录：`docs/CONSTRAINTS.md`
- 完整工作流详见本文件下方

---

## 完整工作流 / Complete Workflow

从需求到发布的完整生命周期，每阶段是卡口，不允许跳过。

---

### 0 — 需求

**输入：** 用户反馈 / 新功能需求 / bug 报告

- **用户反馈视为产品设计意图**，不是单纯的 bug 报告。遇到模糊反馈先提问确认意图，不自行假设后直接改代码
- 每个反馈必须建立"原文 → todo → 代码"的可追踪链路
- 反馈整理后存入 `docs/changelog.md`
- 涉及重大方案变更时更新 `docs/ROADMAP.md` 的"需求变更记录"

---

### 1 — 理解

- 读相关文件（要改的代码）
- **读 `docs/CONSTRAINTS.md`** — 改日历/DB/Provider/通知/同步前必读，防止回归
- 加载 `dayspark-code-review` skill（改相关代码时）
- 如果需求模糊，先问清楚再动手

---

### 2 — 实现

按以下规则写代码。改啥补啥：

| 改动 | 必须做的事 |
|------|-----------|
| 改 Drift table/DAO | 跑 `dart run build_runner build --delete-conflicting-outputs` |
| 改 `.arb`（l10n） | 跑 `flutter gen-l10n` |
| 改 provider 结构 | 检查 `test/` 下对应测试 |
| 新增依赖 | 检查 macOS Xcode SDK 兼容性 |
| **改 DB schema** | 见下方"改表规则" |
| 新增/改 UI 文本 | 必须加 l10n key（中英双语），禁止硬编码 |
| 新增平台相关代码 | 必须考虑所有目标平台差异 |

#### 改表规则

1. `schemaVersion` 递增 + 在 `onUpgrade` 写迁移逻辑
2. **禁止**直接改 schemaVersion 让 Drift 重建表（会丢数据）
3. 跑 `dart run build_runner build`
4. 跑 `dart run drift_dev make-migrations`（生成 schema 快照）
5. 更新 `test/data/local/database/migration/migration_test.dart`
6. `flutter test` 迁移测试必须绿

#### 代码风格

- Single quotes, trailing commas, explicit return types
- `debugPrint` not `print`；**No comments** unless WHY is non-obvious
- No emojis in code, no docstrings

#### 架构

| 层 | 位置 | 说明 |
|----|------|------|
| Providers | `lib/domain/providers/` | Riverpod, watch `databaseProvider`, delegate to DAO |
| DAOs | `lib/data/local/database/daos/` | Drift `@DriftAccessor` |
| Pages | `lib/ui/pages/<feature>/` | 命名 `<feature>_<action>_page.dart` |
| Routing | `lib/core/router/app_router.dart` | go_router 扁平路由 |
| Theme | `lib/core/theme/` | `AppTheme.light(seedColor:)` / `AppTheme.dark(seedColor:)` |
| l10n | `lib/l10n/app_en.arb` + `app_zh.arb` | 中英双语同步，改后 `flutter gen-l10n` |

基础设施服务（platform/alarm/notification/home_widget）→ `lib/infrastructure/platform/`，不放在 `domain/`。

#### UI 原则

- 信息密度优先，不大圆角、不渐变、不 AI 味
- `CupertinoIcons` 而非 `Icons`；Material 3；FilledButton 主操作
- 新增文本必须加 l10n key（中英双语），禁止硬编码
- 触摸目标 ≥ 48x48
- 桌面端可交互元素加 `MouseRegion(cursor: click)` + 键盘快捷键
- 圆角统一 6/8/12

---

### 3 — 验证

```bash
flutter analyze      # 必须零 issue
flutter test         # 必须全绿
```

- 如果失败：**Fix code**，不要 suppress（禁止 `--no-fatal-infos` 绕过）
- CI 配置变更：先普通 push 验证再打 tag（正交法则）
- CI 自动跑：全平台 `--release` 构建（`ci.yml`），release-only bug 提前暴露
- CI 不改 `dart format --set-exit-if-changed`

---

### 4 — 代码审查

加载 `dayspark-code-review` skill，对本次所有改动逐项检查。

- **BLOCKER** 项必须修复才能继续
- **WARNING** 项建议修复，至少确认已知悉
- 修复后重新跑 `flutter analyze` + `flutter test`

---

### 5 — 确认

用户确认改动。没确认不推。

---

### 6 — 文档

| 文件 | 操作 |
|------|------|
| `pubspec.yaml` | version `0.x+N`（x 和 N 不能同时改：feature 改 x，fix 改 N），**1.0 前不跳版** |
| `docs/ROADMAP.md` | 补齐当前版本条目 + 更新 Pending Items + 最后更新行 |
| `docs/changelog.md` | 顶部追加双语日志（feature 写新功能，bug 写问题+修复） |
| `docs/CONSTRAINTS.md` | 修 bug 或关键决策后有新约束就加 |
| `CLAUDE.md` | Current version 行 + 流程改进时同步 |

---

### 7 — 推送

```bash
git add -A
git commit -m "release: v<version> — <summary>"
git tag v<version>
git push origin main
git push origin v<version>
```

**tag 规则：**
- tag 版本号必须匹配 `pubspec.yaml` 的 version 字段
- 禁止创建 `v1.0.0` 或更高版本 tag（1.0 前不跳版）
- tag 推后自动触发 `release.yml`：
  - build 全部 5 平台 `--release`
  - 产物上传到 **Draft Release**（不公开）

---

### 8 — 验收

```bash
# 去 GitHub Releases 页面查看 Draft
gh release view v<version>
```

1. 下载各平台产物
2. 本地安装/打开验证（至少跑得起来）
3. 重点测：本次改动涉及的功能 + 各平台 launch 不崩溃

**产物列表：** Android APK / macOS DMG / Web zip / Windows exe / Linux zip

---

### 9 — 发布

确认产物没问题后，在 GitHub Release 页面点击 **Publish release**。

```bash
# 发布后验证
gh release view v<version> --json name,tagName,isDraft,isPrerelease,assets
```

确认四点：
1. **isDraft** — `false`（已发布）
2. **isPrerelease** — `true`（v0.x 全部标记 prerelease）
3. **Release 说明** — 自动生成或手动补充
4. **构建产物** — 5 平台齐全

---

## 版本规则 / Version Rules

- `pubspec.yaml` 格式：`0.x+N`，**1.0 之前不跳版**
- `+N` build number 单调递增，不可重复、不可回退
- tag 版本号必须与 pubspec.yaml 一致
- 所有 v0.x release 标记为 **pre-release**（`release.yml` 自动处理）
- release 默认为 **draft**，人工验收后再 publish（`release.yml` `draft: true`）

## CI 规则 / CI Rules

- `ci.yml`：全平台 `--release` 构建（非 `--debug`），每次 push/PR 触发
- `release.yml`：打 tag 触发，build 5 平台 + 上传 Draft Release（不公开）
- Linux CI 锁定 `runs-on: ubuntu-22.04`（GLIBC 2.35）
- 新增原生依赖后必须跑 `tool/check_glibc_version.sh`
- 禁用 `dart format --set-exit-if-changed`，禁用 `--no-fatal-infos`

---

## 变更追踪 / Change Tracking

| 文件 | 用途 | 何时更新 |
|------|------|----------|
| `docs/changelog.md` | 用户反馈日志 | 收到反馈后 |
| `docs/ROADMAP.md` | 功能演进全景 | 版本更新时 |
| `docs/CONSTRAINTS.md` | 技术约束 | 修 bug/关键决策后 |
| `CLAUDE.md` | 项目规则 | 用户要求时 / 流程改进时 |
