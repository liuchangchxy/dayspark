# DaySpark (灵光) — Project Rules

## 第一条规则
**当用户明确说"记住"、"以后都这样"、"忘了没"、"写入规则"等，立即提炼写入本文件。** 不要主动存，等用户要求再存。

## Project Overview
- Flutter + Dart | Drift (SQLite) | Riverpod | go_router
- Open-source calendar & todo app with CalDAV sync + AI
- GitHub: https://github.com/liuchangchxy/dayspark
- Package: `dayspark`, Android: `com.dayspark.app`

## Release & CI
1. `flutter analyze` **must** be zero issue before any push
2. `flutter test` **must** all pass before any push
3. Version in `pubspec.yaml`: `0.x+N` format, **never** skip to 1.0 before ready
4. 1.0 之前所有 release 标记为 **pre-release**
5. Commit → **ask user to confirm** → push
6. CI 不放 `dart format --set-exit-if-changed`，不用 `--no-fatal-infos`
7. 新增依赖前检查 macOS Xcode SDK 兼容性
8. 用户反馈整理后存入 `docs/changelog.md`

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
- `build_runner` 后必须重新运行（改了 Drift table/DAO）
- 改了 `.arb` 后必须 `flutter gen-l10n`
- 改了 provider 结构后检查 `test/` 下对应测试
- Fix code, don't suppress warnings
