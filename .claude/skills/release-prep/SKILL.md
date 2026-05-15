---
name: release-prep
description: 完整 dev-to-release 流水线 — 理解 → 实现 → 验证 → 确认 → 文档 → 推送 → 验收
argument-hint: none
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Dev-to-Release Pipeline / 开发到发版流水线

无论 feature 开发还是 bug fix，都按以下 7 阶段走。每阶段是卡口，不允许跳过。

---

## 0 — 理解

- 读相关文件 + `docs/CONSTRAINTS.md`（改日历/DB/provider/通知前必读）
- 如果需求模糊，先问清楚再动手

## 1 — 实现

- 按 `CLAUDE.md` 的代码风格、架构、UI 规则写代码
- 改啥补啥：
  - 改了 Drift table/DAO → `build_runner`
  - 改了 `.arb` → `flutter gen-l10n`
  - 改了 provider 结构 → 检查 `test/` 下对应测试
  - 新增依赖 → 检查 macOS Xcode SDK 兼容性

## 2 — 验证

```
flutter analyze    # 必须零 issue
flutter test       # 必须全绿
```

如果失败：Fix code，不要 suppress。通过后再继续。

## 2.5 — 代码审查

加载 `dayspark-code-review` skill，对本次所有改动逐项检查。

- **BLOCKER** 项必须修复才能继续
- **WARNING** 项建议修复，至少确认已知悉
- 修复后重新跑 `flutter analyze` + `flutter test`

## 3 — 确认

用户确认。没确认不推。

## 4 — 文档

- `pubspec.yaml` — version `0.x+N`（bump x 和 N）
- `docs/ROADMAP.md` — 补齐当前版本条目 + 更新 Pending Items
- `docs/changelog.md` — 顶部追加双语日志（feature 写新功能，bug 写问题+修复）
- `docs/CONSTRAINTS.md` — 修 bug 或关键决策后有新约束就加
- `CLAUDE.md` — Current version 行

## 5 — 推送

```bash
git add -A
git commit -m "release: v<version> — <brief summary>"
git tag v<version>
git push origin main
git push origin v<version>
```

## 6 — CI

tag push 自动触发 `release.yml`。

验证：
```bash
gh run list --limit 2
```

## 7 — 验收

```bash
gh release view v<version> --json name,tagName,isPrerelease,assets
```

确认三点：
1. **版本号 + prerelease 标记** — `isPrerelease: true`
2. **Release 说明** — 自动生成或手动补充
3. **构建产物** — 5 平台都在（android / macos / windows / linux / web）
