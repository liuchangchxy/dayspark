# 门禁总账 / Gate Ledger

> **为什么要有这个文件**：DaySpark 的门禁散在 pre-commit、CI 的三个 job、release 流水线和 `test/architecture/` 里，**没有任何一个地方能回答"我总共有哪些门禁、哪条从没红过"**。
>
> **判据来自 `docs/process/TESTING.md` §一.7「门禁即证据」：一条没红过的门禁视为不存在。** 本表的「红过没」列就是这个判据的账。
>
> **维护**：新增门禁 → 加一行 + 补一次变异实证（怎么打坏的 + 红的原文）。改门禁的覆盖范围 → 更新本行。

最后更新：2026-10-01 · 版本以 `pubspec.yaml` 为准

---

## 一、提交门禁（pre-commit，每次 commit 跑）

| # | 门禁 | 守什么 | 怎么跑 | 红过没 |
|---|---|---|---|---|
| 1 | `dart analyze .` | 静态分析零 issue | `sh scripts/setup-hooks.sh` 安装 | ✅ 2026-10-01（注入 `int f() => 'str'` → `error - …: A value of type 'String' can't be returned … - return_of_invalid_type`） |
| 2 | `tool/guard_test_tampering.py` | 删/放宽既有断言来造绿 | 同上，随钩子 | ✅ 2026-10-01（删掉 `expect(schedules, isEmpty)` → 报出文件与断言原文） |
| 3 | `tool/scan_hardcoded_paths.py` | 写死本机绝对路径 | 同上，随钩子 | ✅ 2026-10-01（写入 `/home/chang/secret` → 报出 `file:line`） |

## 二、CI 门禁（`.github/workflows/ci.yml`，push / PR）

| # | 门禁 | 守什么 | 挂在哪 | 红过没 |
|---|---|---|---|---|
| 4 | `tool/check_version_consistency.sh` | 版本号 SSOT（pubspec）与四处文档标记一致 | `test` job 首步（含 `--selftest`） | ✅ 自带 `--selftest` 自证 |
| 5 | `flutter gen-l10n` + `dart analyze .` + `flutter test` | 全量测试与分析 | `test` job | ✅ 2026-10-01（真实 CI 跑红并阻断：`365 tests passed, 2 failed`，run 36808807367） |
| 6 | `test/architecture/l10n_parity_guard_test.dart` | ARB 键双向对齐（漏译 / 废弃键） | `test` job | ✅ 2026-10-01（删 `todoReminder` → `zh 漏译 1 个键：todoReminder`） |
| 7 | `test/architecture/no_raw_text_guard_test.dart` | `lib/` 无未豁免的中文裸文案 | `test` job | ✅ 2026-10-01（写入 `Text('你好')` → 报出 `about_section.dart: 第 26 行`） |
| 8 | `test/architecture/web_platform_guard_test.dart` | `Platform.*` 全仓唯一读点（缺了会白屏） | `test` job | ✅ v0.25.1（抽掉守卫 → 守卫红 + 产物冒烟判白屏） |
| 9 | `test/architecture/radius_token_guard_test.dart` | 圆角只认 `{8, 10, 12, 16}` | `test` job | ✅ 2026-10-01（注入 `BorderRadius.circular(7)` → `lib/_mutation_probe.dart:4: 7 not in radius scale`） |
| 10 | `test/architecture/spacing_token_guard_test.dart` | 间距走 `AppSpacing` | `test` job | ✅ 2026-10-01（注入 `SizedBox(width: 9)` → `lib/_mutation_probe.dart:5: 9 in SizedBox(width: 9)…`） |
| 11 | `test/architecture/typography_token_guard_test.dart` | 字阶 token + 主标题/正文 1.7 倍层次 | `test` job | ✅ 2026-10-01（注入 `fontSize: 19` → `lib/_mutation_probe.dart:6: 19 not in type scale`） |
| 12 | `test/architecture/record_seam_guard_test.dart` | 单写入口 `RecordScope.run`（**消费 `tool/record_seam_baseline.txt` 棘轮基线**） | `test` job | ✅ 2026-10-01（注入 `db.into(db.todos).insert(...)` → `lib/_mutation_probe.dart:9 未登记在棘轮基线中；这条写入绕过了单写入口，派生态会静默失效`） |
| 13 | `test/data/local/database/migration/migration_test.dart` | schema 迁移不丢数据 | `test` job | ✅ 2026-10-01（`schemaVersion` 9→10 且不加迁移 → `Expected: <9> Actual: <10>`） |
| 14 | `tool/check_whitespace.py` | 行尾空格 / 换行符混用 | `test` job | ✅ 2026-10-01（写入行尾空格 → 报出 `file:line`） |
| 15 | `tool/check_glibc_version.sh` | Linux 产物不超 GLIBC 2.35 基线 | 发布相关 job | ❌ **拿不到红色实证，且已实证它会静默放行**：`tool/check_glibc_version.sh /nonexistent/bundle` → `SKIP: readelf not found` + **退出码 0**。见 §四.2 |
| 16 | `tool/web_smoke.dart` | Web 产物白屏即红（零依赖无头截图 + 着色比断言） | `build-web` job | ✅ v0.25.1（正身信号 + 抽掉守卫即判白屏） |
| 17 | 服务端 / contracts / wrapper / CLI 各自的 `dart test` | 非 Flutter 侧的回归 | `server-test` job | ✅ 2026-10-01（默认端口 8787→8788 → `Expected: <8787> Actual: <8788>`） |

## 三、发布门禁（`release.yml`，打 tag 触发）

| # | 门禁 | 守什么 | 红过没 |
|---|---|---|---|
| 18 | `version-gate`（`check_version_consistency.sh --tag`） | tag 必须等于 `v<pubspec semver>` | ✅ 同 4（同一脚本） |
| 19 | 五平台 `--release` 构建 | release-only 缺陷（如 Web 白屏）提前暴露 | ✅ v0.25.0 → v0.25.1 实测 |

---

## 三点五、当前红灯

无。`flutter test` 366 passed / 0 failed。

### 已关的假红（2026-10-01）

- `marked_month_day_header_test` 的 `month view grid shows current-month solar terms`：**日期相关假红**，在 HEAD(v0.26.0) 上即红、每月约 4 天命中。测试原先按"今天所在月"算期望值，而月视图显示的是"本周周一所在月"（月初跨月时两者不同）。已改为按 anchor 规则算，**未改产品行为**；"月初该显示哪个月"仍是待拍板的产品问题，见 `docs/CONSTRAINTS.md`。
- `no_raw_text_guard_test` 的 `白名单无死豁免`：**本地绿 CI 红**。守卫原用文件系统扫描，把 gitignore 的生成文件 `lib/oss_licenses.dart` 也算了进来（CI 干净检出里没有它）。已改为只扫 `git ls-files` 跟踪的文件。这条是"新门禁必须在干净检出上验"的实例。

## 四、已知缺口

1. ~~9 条门禁的"红过没"是未记录~~ ✅ 2026-10-01 已补齐 8 条（见上表）。**唯一没验的是 #15 glibc**，原因见下条。
2. **`check_glibc_version.sh` 会在环境缺失时静默放行 —— 已实证，不是推测。**
   ```
   $ tool/check_glibc_version.sh /nonexistent/bundle
   SKIP: readelf not found (install binutils)
   $ echo $?
   0
   ```
   脚本有两个提前返回分支（找不到 `readelf`、bundle 目录不存在），**两个都是 `echo "SKIP: …"; exit 0`**。也就是说：CI 上只要 bundle 忘了构建，或者 runner 少了 binutils，这条门禁就会安静地绿灯通过，而它守的恰恰是"Linux 产物能不能跑"。
   **一个"环境不对就绿灯"的门禁，是这个表里唯一一条我已经能证明它不能红的门禁。** 修法二选一：
   - (a) CI 该步骤后加断言「输出不得含 `SKIP`」；
   - (b) 脚本加 `--require` 开关，CI 用 `--require` 跑（缺环境即失败）。
   推荐 (b)：把"必须真的检查"变成调用方显式声明的事，本地仍可 SKIP。
3. **pre-commit 不跑全量测试**：`flutter test` 太慢，仍由 CI 与发布流程卡口。这是有意的取舍，不是遗漏。

## 五、待办

- [x] ~~补 #14 的 CI 步骤~~ ✅ 2026-10-01 已接进 `ci.yml` `test` job
- [x] ~~逐条补 9 条未记录门禁的变异实证~~ ✅ 2026-10-01 补了 8 条；glibc 那条见 §四.2
- [ ] 修 `check_glibc_version.sh` 的"静默 SKIP"（§四.2，二选一）
- [ ] 把 `tool/` 下三个 Python 脚本的用法写进 `CLAUDE.md` 或 `AGENTS.md` 的命令清单
