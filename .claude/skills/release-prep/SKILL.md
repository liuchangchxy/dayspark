---
name: release-prep
description: This skill should be used when the user asks to "release", "push and release", "update version", "publish prerelease", "发版", "推送发版", or wants to push changes, trigger CI, bump version, and update docs in one flow.
argument-hint: "[major|minor|patch]"
---

# Release Prep Skill

Prepare a prerelease: bump version, update docs, commit, push, and trigger CI.

## Steps (execute in order)

### 1. Determine version bump

Read current version from `pubspec.yaml` (format: `0.x+N`).

- If `$ARGUMENTS` is `major`: bump x (e.g. 0.17 → 0.18)
- If `$ARGUMENTS` is `minor`: bump x (e.g. 0.17 → 0.18)
- If `$ARGUMENTS` is `patch` or empty: bump x by 0.01 (e.g. 0.17 → 0.17.1 → round to 0.18 if needed, or just increment the minor)

Convention: `0.x+N` where x is the feature version, N is the build number (always +1).

### 2. Update `pubspec.yaml` version

Edit the `version:` line. Example: `0.17.0+13` → `0.18.0+14`.

### 3. Update `docs/changelog.md`

Add a new section at the top (after the title) summarizing the changes since last version. Use the same bilingual format as existing entries. Include:
- Security fixes
- Bug fixes
- Any new features
- Breaking changes if any

Base the summary on `git log` since the last version tag or recent commits.

### 4. Update `docs/CONSTRAINTS.md` if needed

If any new constraints were established during the fixes (e.g. new rules about error handling, security patterns), add them.

### 5. Run checks

```bash
cd /home/chang/dayspark && flutter analyze
```

If there are errors, fix them before proceeding. Warnings are acceptable.

### 6. Commit

Stage all changed files and commit with a message like:
```
release: v0.x.0+N — <brief summary>
```

### 7. Push to remote

```bash
git push origin main
```

### 8. Confirm with user

Report what was done: old version → new version, files changed, commit hash, and that CI has been triggered.
