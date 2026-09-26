# DaySpark (灵光) — Project Rules

## 元法则（Meta-Rules）
以下四条是所有具体规则和操作流程的来源依据。若具体规则与元法则冲突，以元法则为准。

1. **溯源法则**：每个用户反馈必须建立"原文 → todo → 代码"的可追踪链路。完成检查时，验证依据是**原文**，不是 todo 列表。→ 可避免：漏改、假完成。
2. **根因法则**：修复任何失败前，必须先定位根因。不做猜测式修复。→ 可避免：修多次修不对、引入新问题。
3. **正交验证法则**：验证一件事的手段必须独立于做这件事的手段。修代码的人不独自验证、验证清单不来自 todo 而来自原文、CI 配置变更先普通 push 验证再打 tag。→ 可避免：自己骗自己。
4. **平台感知法则**：任何 UI/交互改动，必须显式考虑所有目标平台的差异（桌面鼠标 vs 移动触摸），而不是只在一个平台上验证。→ 可避免：跨平台不兼容。

---

## 项目总览 / Project Overview

Flutter + Dart | Drift (SQLite) | Riverpod | go_router | kalender | lunar (solar terms/holidays) | home_widget | alarm | flutter_local_notifications | Dart server (shelf/drift/SQLite) + dayspark_contracts | Server MCP (`POST /mcp`, 17 tools, OAuth 2.1) + `tool/mcp_stdio_wrapper` + `tool/dayspark_cli`

- 开源日历待办 App + AI 助手（BYO key 客户端 AI）；自托管同步后端（P2, v0.22.0 落地）与服务端 MCP（P3, v0.23.0 落地）
- GitHub: https://github.com/liuchangchxy/dayspark
- Package: `dayspark`, Android: `com.dayspark.app`
- Current version: `0.25.1+26`
- 项目功能状态：`docs/ROADMAP.md`
- **接续入口（新会话说"从哪开始"先读它）：`docs/START_HERE.md`**
- 技术约束记录：`docs/CONSTRAINTS.md`
- 完整工作流详见本文件下方

---

## 完整工作流 / Complete Workflow

从需求到发布的完整生命周期，每阶段是卡口，不允许跳过。

**流程文档分工（四件 vendored 自 vibe-coding-starter@d339922，定义见各文件头）：**

- 多任务执行工序（简报/报告/diff 审查包、Fix 循环 ≤5、**Rulings 裁定披露**、预检接缝扫描）→ `docs/process/EXECUTION.md`
- 审查攻击配方（空转测试/边界数学/证据链倒挂/自证向量/跨端键一致性 + 审查者三律）→ `docs/process/REVIEWING.md`
- 测试铁律、门禁、**DoD 收敛停止准则**（P0–P3 阶梯 + `skipped=0` 即收）→ `docs/process/TESTING.md`
- 顶层架构推导法（七步 + 三判据 + 抄/造判据；产物写入 SPEC §2）→ `docs/process/ARCHITECTURE.md`
- DaySpark 专属差异（发版流程、版本规则、平台法则、改表/l10n/UI 规则）**只写在本文件**，不写入 vendored 文件

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
| Sync engine | `lib/domain/sync/` | outbox + applier + SyncEngine + SSE（P2） |
| Records seam | `lib/domain/records/` | 单写入口 `RecordScope.run`（写入即登记、提交后发布）+ `writers/` 是记录行的唯一写点 + 消费端（重排器 / 组件刷新）；守卫 `test/architecture/record_seam_guard_test.dart` |
| Server | `server/` | Dart shelf 同步后端（auth/JWT、push/pull/SSE、drift/SQLite、Docker）+ MCP 端点（`POST /mcp` 17 工具 + 3 资源）与 OAuth 2.1 授权服务器 |
| Contracts | `packages/dayspark_contracts/` | 客户端/服务端共享协议 DTO（SSOT） |
| MCP tooling | `tool/mcp_stdio_wrapper/`、`tool/dayspark_cli/` | stdio↔HTTP 桥（本地 Agent）与 `dayspark` CLI（HTTP MCP 客户端） |

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
- **何时收口**：停止准则用 `docs/process/TESTING.md` DoD——P0/P1 清零 + 测试 100% 且 `skipped=0` → 必须明确宣布通过，禁止借 P2/P3 理论风险无限发散
- **审查怎么做**：配方见 `docs/process/REVIEWING.md`（发现期五攻击法；修复期回 TESTING 铁律 RCA 全局清扫）；审查者必须亲手重跑门禁，禁止只信报告

---

### 4 — 代码审查

加载 `dayspark-code-review` skill（若存在），对本次所有改动逐项检查；**同时按 `docs/process/REVIEWING.md` 五攻击配方主动找洞**（至少各试一次：空转测试、边界数学、证据链倒挂、自证向量、跨端键一致性）。

- **严重度阶梯统一为 P0–P3**（定义见 `docs/process/TESTING.md` DoD）：P0/P1 = 阻断必须清零；P2/P3 = 记入待办禁内耗。旧称 BLOCKER≈P0/P1、WARNING≈P2/P3，不再混用
- P0/P1 必须修复才能继续；修复时执行 RCA：全项目同类实现一次清剿，严禁孤立改单行
- 修复后重新跑 `dart analyze .` + `flutter test`
- **阶段收尾必须交付 Rulings 裁定清单**（格式与阈值见 `docs/process/EXECUTION.md` §3）：只收行为/范围/代价级决定，禁止静默裁定

---

### 5 — 确认

用户确认改动。没确认不推。

---

### 6 — 文档

| 文件 | 操作 |
|------|------|
| `pubspec.yaml` | version `0.x+N`（x 和 N 不能同时改：feature 改 x，fix 改 N），**1.0 前不跳版** |
| `docs/ROADMAP.md` | 补齐当前版本条目 + 更新 Pending Items + 最后更新行 |
| `docs/changelog.md` | 顶部追加双语日志（feature 写新功能，bug 写问题+修复）+ 更新 `最新版本 / Latest` 与 `上一版本 / Previous` 两行 |
| `docs/CONSTRAINTS.md` | 修 bug 或关键决策后有新约束就加 |
| `CLAUDE.md` | Current version 行 + 流程改进时同步 |

改完跑 `tool/check_version_consistency.sh` 自检（CI 同款门，别等 push 后才发现漂移）。

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
- **版本一致性守卫**：`tool/check_version_consistency.sh` 以 `pubspec.yaml` 为 SSOT，校验 `CLAUDE.md` / `docs/changelog.md` / `docs/ROADMAP.md` 的版本标记 + `server/lib/src/mcp/schemas.dart` 的 `mcpServerVersion`（对外 `serverInfo.version`）—— `ci.yml` `test` job 首步（含 `--selftest` 自证可失败），`release.yml` `version-gate` 门（`--tag` 要求 tag = `v<pubspec semver>`）。README 徽章是 shields.io 动态徽章（读 GitHub Releases，无手同步点）；`docs/START_HERE.md` **不在门内**（版本一律指向 pubspec/ROADMAP，不复制）
- 禁用 `dart format --set-exit-if-changed`，禁用 `--no-fatal-infos`

---

## 变更追踪 / Change Tracking

| 文件 | 用途 | 何时更新 |
|------|------|----------|
| `docs/changelog.md` | 用户反馈日志 | 收到反馈后 |
| `docs/ROADMAP.md` | 功能演进全景 | 版本更新时 |
| `docs/CONSTRAINTS.md` | 技术约束 | 修 bug/关键决策后 |
| `CLAUDE.md` | 项目规则 | 用户要求时 / 流程改进时 |

---

## 文档地图 / Documentation Map

各文档分工明确、互相引用、不重复维护同一内容：

| 文档 | 一句话定位 |
|------|-----------|
| `docs/START_HERE.md` | **接续入口**：新会话“从哪开始”先读它（未做事项唯一清单） |
| `SPEC.md` | **业务**真理源：做什么、规则契约、架构实例（§2）（改业务先改它；**状态一律看 ROADMAP**） |
| `DECISIONS.md` | **为什么**：重大决策的轻量 ADR 时间线 |
| `docs/CONSTRAINTS.md` | **坑**：技术约束与避坑清单（用户纠错也追加到这里） |
| `docs/changelog.md` | **反馈**：用户反馈日志（原文→todo→代码 溯源） |
| `docs/ROADMAP.md` | **状态唯一源**：功能全景、需求/阶段状态、P2.5、follow-ups |
| `DESIGN.md` | **设计令牌 SSOT**：颜色/字阶/间距/圆角/组件原则（UI 改动对拍它；代码差距见 `docs/design-token-gap.md`） |
| `docs/process/*.md` | **流程四件**（vendored）：执行/审查/测试/架构方法，见本文件工作流开头的分工 |
| `docs/qa/` | 各阶段手工验收清单（可按用户豁免先例处理） |
| `docs/archive/` | 过时文档归档（历史考古，不维护） |
| `docs/superpowers/plans/` | 各阶段实施计划（含主计划） |

跨工具 AI 入口见 `AGENTS.md`（三大底线 + 指向本文件与 SPEC.md）。
