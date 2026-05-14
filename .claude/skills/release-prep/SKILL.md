---
name: release-prep
description: 发版四步走 — 更新文档 → git 保存并推送 → 触发 CI → 验收版本号 + 说明 + 构建
argument-hint: none
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Release Prep Skill / 发版四步走

用户说"发版"时，按以下 4 步执行：

---

## Step 1 — 更新所有文档

- `pubspec.yaml` version `0.x+N`（bump x 和 N）
- `docs/ROADMAP.md` — 补齐当前版本条目 + 更新 Pending Items
- `docs/changelog.md` — 顶部追加当前版本双语日志
- `CLAUDE.md` — Current version 行

## Step 2 — git 保存并推送到远程

```bash
git add -A
git commit -m "release: v<version> — <brief summary>"
git tag v<version>
git push origin main
git push origin v<version>
```

## Step 3 — 触发 GitHub CI

tag push 会自动触发 `release.yml` workflow。

验证：
```bash
gh run list --limit 2
```

## Step 4 — 验收

确认三样东西都没问题：
1. **GitHub Release 版本号** — `gh release view v<version>` 确认 tag name、prerelease 标记
2. **Release 说明** — 自动生成或手动改 body
3. **CI 构建产物** — `gh run watch <run-id> --exit-status` 等全部通过，确认 5 平台构件都在
