---
name: release-prep
description: This skill should be used when the user asks to "release", "push and release", "update version", "publish prerelease", "发版", "推送发版", or wants to push changes, trigger CI, bump version, and update docs in one flow.
argument-hint: "[major|minor|patch]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Release Prep Skill

Prepare a prerelease: configure signing (if needed), bump version, update docs, commit, push, tag, trigger CI.

## Steps (execute in order)

### 0. Check Android signing setup

Check if CI signing is properly configured. Run:

```bash
gh secret list --json name -q '.[].name' 2>/dev/null
```

If `ANDROID_KEYSTORE_BASE64` is NOT in the list, set up signing:

1. Read `android/app/key.properties` to get `storeFile`, `storePassword`, `keyPassword`, `keyAlias`
2. Read the keystore file path from `storeFile` (relative to `android/app/`)
3. Base64-encode the keystore: `base64 -i android/app/<storeFile>`
4. Upload secrets:
   ```bash
   gh secret set ANDROID_KEYSTORE_BASE64 --body "$(base64 -i android/app/<storeFile>)"
   gh secret set ANDROID_STORE_PASSWORD --body "<storePassword>"
   gh secret set ANDROID_KEY_PASSWORD --body "<keyPassword>"
   gh secret set ANDROID_KEY_ALIAS --body "<keyAlias>"
   ```
5. Update `.github/workflows/release.yml` — in the `build-android` job, add a step before `flutter build apk`:
   ```yaml
   - name: Setup Android signing
     run: |
       echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 -d > android/app/release-keystore.jks
       cat > android/app/key.properties << EOF
       storePassword=${{ secrets.ANDROID_STORE_PASSWORD }}
       keyPassword=${{ secrets.ANDROID_KEY_PASSWORD }}
       keyAlias=${{ secrets.ANDROID_KEY_ALIAS }}
       storeFile=release-keystore.jks
       EOF
   ```
6. Remove `key.properties` and `*.jks` from git tracking, add back to `.gitignore`
7. Commit this change as `chore: Android 签名迁移到 GitHub Secrets`

If secrets already exist, skip this step.

### 1. Determine version bump

Read current version from `pubspec.yaml` (format: `0.x+N`).

- If `$ARGUMENTS` is `major`: bump x (e.g. 0.17 → 0.18)
- If `$ARGUMENTS` is `minor`: bump x (e.g. 0.17 → 0.18)
- If `$ARGUMENTS` is `patch` or empty: bump the minor (e.g. 0.17 → 0.18)

Convention: `0.x+N` where x is the feature version, N is the build number (always +1).

Check existing tags with `git tag -l 'v*' | sort -V | tail -3` to avoid conflicts.

### 2. Update `pubspec.yaml` version

Edit the `version:` line. Example: `0.17.0+13` → `0.18.0+14`.

### 3. Update `docs/changelog.md`

Add a new section at the top (after the title) summarizing the changes since last version. Use the same bilingual format as existing entries. Include:
- Security fixes
- Bug fixes
- Any new features
- Breaking changes if any

Base the summary on `git log` since the last version tag.

### 4. Update `docs/CONSTRAINTS.md` if needed

If any new constraints were established during the fixes, add them.

### 5. Run checks

```bash
flutter analyze
```

If there are errors, fix them before proceeding. Warnings are acceptable.

### 6. Commit, tag, push

```bash
git add -A
git commit -m "release: v0.x.0+N — <brief summary>"
git tag v0.x.0
git push origin main
git push origin v0.x.0
```

### 7. Verify CI

```bash
gh run list --limit 2
```

Report: old version → new version, commit hash, tag, and CI status.

### 8. Wait for Release workflow

```bash
gh run watch <run-id> --exit-status
```

If Android build fails with signing errors, the secret setup in Step 0 was incomplete. Re-run that step.
