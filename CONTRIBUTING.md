# Contributing to DaySpark / 贡献指南

Thank you for your interest in contributing to DaySpark! / 感谢你对 DaySpark 的贡献兴趣！

---

## How to Contribute / 如何贡献

### Bug Reports / 报告 Bug

1. Check if the issue already exists in [GitHub Issues](https://github.com/liuchangchxy/dayspark/issues) / 先在 [GitHub Issues](https://github.com/liuchangchxy/dayspark/issues) 搜索是否已有人报告
2. Open a new issue using the **Bug Report** template / 使用 **Bug Report** 模板创建新 issue
3. Include: OS version, app version, steps to reproduce, expected vs actual behavior / 包含：系统版本、App 版本、复现步骤、期望与实际行为

### Feature Requests / 功能建议

1. Open an issue using the **Feature Request** template / 使用 **Feature Request** 模板创建 issue
2. Describe the use case, not just the solution / 描述使用场景，而不仅是解决方案

### Pull Requests / 提交 PR

1. Fork the repo and create a branch from `main` / Fork 仓库，从 `main` 创建分支
2. Make your changes / 进行修改
3. Ensure all checks pass / 确保所有检查通过（见下方 checklist）
4. Open a PR with a clear description / 提交 PR 并写清楚说明

---

## Development Setup / 开发环境搭建

### Prerequisites / 前置条件

- Flutter SDK >= 3.11.0
- Dart >= 3.11.0
- For macOS/iOS: Xcode + CocoaPods
- For Android: Android SDK

### Getting Started / 开始

```bash
# Clone / 克隆
git clone https://github.com/liuchangchxy/dayspark.git
cd dayspark

# Install dependencies / 安装依赖
flutter pub get

# Generate code (Drift tables, DAOs) / 生成代码
dart run build_runner build --delete-conflicting-outputs

# Generate l10n / 生成国际化
flutter gen-l10n

# Run / 运行
flutter run -d chrome    # Web
flutter run -d macos     # macOS
flutter run -d <device>  # Other platforms / 其他平台

# Test / 测试
flutter test

# Analyze / 分析
flutter analyze
```

---

## Code Style / 代码规范

- **Single quotes**, trailing commas, explicit return types / 单引号、尾逗号、显式返回类型
- `debugPrint` not `print`
- **No comments** unless the WHY is non-obvious / 除非 WHY 不显而易见，否则不加注释
- No emojis in code / 代码中不用 emoji
- No multi-line docstrings or comment blocks / 不写多行文档注释或注释块
- New user-facing strings **must** go through l10n (`app_en.arb` + `app_zh.arb`) / 新增用户可见文本必须走 l10n

### Architecture / 架构

- **Providers**: `lib/domain/providers/` — Riverpod `StreamProvider`/`Provider`
- **DAOs**: `lib/data/local/database/daos/` — Drift `@DriftAccessor`
- **Pages**: `lib/ui/pages/<feature>/` — naming: `<feature>_<action>_page.dart`
- **Theme**: `lib/core/theme/` — `AppTheme.light/dark(seedColor:)`
- **l10n**: `lib/l10n/app_en.arb` + `app_zh.arb` — must stay synced

### Commit Messages / 提交信息

Use concise, descriptive messages in English / 使用简洁的英文描述：
```
feat: add calendar event drag-and-drop
fix: resolve dark mode date picker color
docs: update README with setup instructions
```

---

## PR Checklist / PR 检查清单

Before submitting a PR, verify / 提交 PR 前确认：

- [ ] `flutter analyze` — zero issues / 零问题
- [ ] `flutter test` — all tests pass / 所有测试通过
- [ ] If you changed Drift tables/DAOs: ran `dart run build_runner build` / 如果改了 Drift 表/DAO，重新运行了 build_runner
- [ ] If you changed `.arb` files: ran `flutter gen-l10n` and both `app_en.arb` + `app_zh.arb` are synced / 如果改了 .arb 文件，运行了 gen-l10n 且中英同步
- [ ] New user-facing strings have l10n keys (no hardcoded strings) / 新增用户可见文本有 l10n key（无硬编码字符串）
- [ ] No new warnings or info-level lint issues / 没有新增的 warning 或 info 级 lint

---

## License / 许可证

By contributing, you agree that your contributions will be licensed under the [GPLv3 License](LICENSE).
贡献即表示你同意你的代码将在 [GPLv3 许可证](LICENSE)下授权。
