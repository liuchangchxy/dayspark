# DaySpark (灵光) — Project Rules

## 第一条规则
**当用户明确说"记住"、"以后都这样"、"忘了没"、"写入规则"等，立即提炼写入本文件。** 不要主动存，等用户要求再存。

## 协作规则
1. **修改依赖/CI/平台构建相关代码前，先读 `docs/CONSTRAINTS.md`**，确认改动不违反已有约束
2. **每次修 bug 或做关键决策后，更新 `docs/CONSTRAINTS.md`**，记录具体约束 + 为什么
3. **用户反馈视为产品设计意图**，不是单纯的 bug 报告。反馈中提到的"为什么没有 X"意味着用户想要 X
4. **遇到模糊反馈先提问确认意图再动手**，不要自行假设后直接改代码
5. **Linux 构建必须在 Ubuntu 22.04 上**，不允许用高于 GLIBC 2.35 的系统构建 Linux 分发产物。CI 中的 `runs-on` 必须显式为 `ubuntu-22.04`，新增原生依赖后要确保 `tool/check_glibc_version.sh` 通过

## Project Overview
- Flutter + Dart | Drift (SQLite) | Riverpod | go_router | home_widget | mcp_dart | alarm | local_auth | workmanager
- Open-source calendar & todo app with CalDAV sync + AI + MCP server
- GitHub: https://github.com/liuchangchxy/dayspark
- Package: `dayspark`, Android: `com.dayspark.app`
- Account passwords stored in `FlutterSecureStorage`, not in DB plaintext
- Current version: `0.20.0+18`

## Release & CI
1. `flutter analyze` **must** be zero issue before any push
2. `flutter test` **must** all pass before any push
3. 验证后跑 `flutter build macos --debug` + `flutter build apk --debug` + `flutter build web --debug`，确认各平台编译无报错
4. Version in `pubspec.yaml`: `0.x+N` format, **never** skip to 1.0 before ready
5. 1.0 之前所有 release 标记为 **pre-release**
6. Commit → **ask user to confirm** → push
7. CI 不放 `dart format --set-exit-if-changed`，不用 `--no-fatal-infos`
8. 新增依赖前检查 macOS Xcode SDK 兼容性
9. 用户反馈整理后存入 `docs/changelog.md`

## Code Style
- Single quotes, trailing commas, explicit return types
- `debugPrint` not `print`
- **No comments** unless WHY is non-obvious (hidden constraint, subtle invariant, workaround)
- No emojis in code
- No docstrings / multi-line comment blocks

## Architecture
- **Providers**: Riverpod `StreamProvider`/`Provider` in `lib/domain/providers/`, watch `databaseProvider`, delegate to DAO
- **DAOs**: Drift `@DriftAccessor` in `lib/data/local/database/daos/`
- **Pages**: `lib/ui/pages/<feature>/`, naming `<feature>_<action>_page.dart`
- **Routing**: go_router flat routes in `lib/core/router/app_router.dart`
- **Theme**: `lib/core/theme/` — `AppTheme.light(seedColor:)` / `AppTheme.dark(seedColor:)`, colors in `AppColors`
- **l10n**: `lib/l10n/app_en.arb` + `app_zh.arb`, must stay synced, then `flutter gen-l10n`

## UI Rules
- 信息密度优先，不大圆角、不渐变、不 AI 味
- 用 `CupertinoIcons` 而非 `Icons`（iOS feel）
- Material 3 (`useMaterial3: true`)
- FilledButton for primary actions, TextButton for secondary
- 新增文本必须加 l10n key（中英双语），禁止硬编码字符串

## Workflow
- 所有工作走完整 pipeline：理解 → 实现 → 验证 → 确认 → 文档 → 推送 → 验收（见 `.claude/skills/release-prep/SKILL.md`）
- ⚠️ **完成所有改动后，必须逐条对照用户原始反馈清单验证**，不能只看自己的 todo 列表。遗漏一条也算未完成。
- ⚠️ **UI 改动必须考虑全部目标平台**（桌面和移动端），不能只适配一种。桌面端（Linux/Windows/macOS）的鼠标交互和移动端不同。
- ⚠️ **"修完了"必须经用户确认**，不要自己替用户宣布完成。
- `build_runner` 后必须重新运行（改了 Drift table/DAO）
- 改了 `.arb` 后必须 `flutter gen-l10n`
- 改了 provider 结构后检查 `test/` 下对应测试
- Fix code, don't suppress warnings
- 项目功能状态以 `docs/ROADMAP.md` 为准
