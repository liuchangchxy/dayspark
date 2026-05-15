# Technical Constraints / 技术约束记录

> 防止上下文压缩后遗忘已踩过的坑，导致回归 bug。
> 每次修 bug 或做关键决策后必须更新此文件。

**TL;DR / 快速了解**
- 本文件记录所有技术约束，按领域分组（Calendar / Database / UI / Security / Platform）
- 核心约束：PageView 范围不能缩小、版本号必须动态读取、Linux 构建必须 Ubuntu 22.04
- 修改日历/DB/Provider/通知相关代码前**必须先读**对应章节

---

## Calendar / 日历

### PageView 页面范围不能缩小
- Day: `_totalDays = 20000`, `_epochDay = 10000`
- Week: `_totalWeeks = 4000`, `_epochWeek = 2000`
- Month: `_totalMonths = 800`, `_epochMonth = 400`
- **Why**: 2026-05-03 的 day index = 9619 + 10000 = 19619。如果范围不够大，PageController 会 clamp 到最后一页，显示 ~2004 年的日期。
- **Root cause**: v0.17.0 把范围从 24000 缩小到 3650/1040/240，没验证当前日期的 index 是否在范围内。
- **Date**: 2026-05-03

### _calendarRange 必须是静态的
- `home_page.dart` 中的 `_calendarRange()` 返回固定的 `DateTime(2000,1,1)` 到 `DateTime(2030,12,31)`
- 不能跟 `_calendarAnchor` 联动
- **Why**: 动态 range 会改变 provider key → `eventsInDateRangeProvider(rangeKey)` 重新加载 → CalendarSection 被销毁重建 → 滑动状态丢失
- **Date**: 2026-05-03

### _isAnimating 防止循环反馈
- week/day/month 视图的 `onPageChanged` 里必须检查 `if (!_isAnimating)`
- `didUpdateWidget` 里 `animateToPage` 前后设置 `_isAnimating = true/false`
- **Why**: 不加这个会形成 onPageChanged → setState → didUpdateWidget → animateToPage → onPageChanged 的循环
- **Date**: 2026-05-02

### 每个 PageView 页面需要独立的 ScrollController
- 用单独的 StatefulWidget（`_DayScrollablePage` / `_ScrollablePage`）持有各自的 ScrollController
- 不能共享一个 ScrollController
- **Why**: PageView 多个页面共享一个 ScrollController，只有一个能 attach
- **Date**: 2026-05-02

### 月导航日期必须规范化
- `_navigateForward` month case 用 `DateTime(year, month+1, 1)`，day 固定为 1
- **Why**: 如果 anchorDate.day = 31，`DateTime(year, month+1, 31)` 会跳月（如 1月31日 + 1月 = 3月3日）
- **Date**: 2026-05-02

### CalendaEventAdapter == 必须包含所有字段
- equality 和 hashCode 必须覆盖全部 12 个字段
- **Why**: Flutter widget diffing 依赖 ==，漏字段会导致旧数据不被替换
- **Date**: 2026-05-02

## Version / 版本号

### 版本号必须动态读取
- 设置页、关于页用 `PackageInfo.fromPlatform()` 读取
- 禁止硬编码 `'DaySpark v0.17.0'` 这种字符串
- **Why**: pubspec.yaml 版本改了但硬编码不跟着改，APK 显示旧版本
- **Date**: 2026-05-03

## Database / 数据库

### ICS import 用 insert 不用 insertOnConflictUpdate
- `ics_service.dart` 里用 `insert(companion)` 直接插入
- 不能用 `insertOnConflictUpdate(Event(id: -1, ...))`
- **Why**: `id: -1` 永远不会匹配已有行，且不传 id 时 Drift 自动生成，不会冲突
- **Date**: 2026-05-02

### emptyTrash 必须级联删除子表
- `todos_dao.dart` 的 `emptyTrash` 必须先删 todo_tags、attachments、reminders，再删 todos
- **Why**: 外键约束，不先删子表会报错
- **Date**: 2026-05-02

## Notifications / 通知

### Alarm ID 用偏移量避免冲突
- Event alarm: id + 500000
- Todo alarm: id + 600000
- **Why**: 同一个 todo/event 的 notification 和 alarm ID 不能冲突
- **Date**: 2026-05-02

## Time Picker / 时间选择器

### CupertinoDatePicker 不强制 24h
- 不传 `use24hFormat` 参数，让它跟随系统 locale
- **Why**: 强制 `use24hFormat: true` 导致 12h locale 的用户看到错误的格式
- **Date**: 2026-05-03

## UI / 界面

### 主题色不能用 const 引用运行时值
- `SizedBox(child: CircularProgressIndicator(color: Theme.of(context)...))` 不能加 const
- **Why**: Theme.of(context) 是运行时值，const 构造函数要求编译期常量
- **Date**: 2026-05-02

### 日历日期格子用 InkWell 提供触摸反馈
- 月视图的 `_buildDayCell` 用 `Material` + `InkWell` 替代 `GestureDetector`
- **Why**: 用户多次反馈没有触摸反馈
- **Date**: 2026-05-03

## Architecture / 架构

### 基础设施服务放在 lib/infrastructure/ 而非 domain/services/
- 平台插件调用（alarm、notification、home_widget）→ `lib/infrastructure/platform/`
- 网络/socket 服务（mcp_server）→ `lib/infrastructure/mcp/`
- `domain/services/` 只保留纯领域逻辑（ai_scheduler、ics）
- **Why**: 平台 API 变化不应触及领域层；基础设施可独立替换
- **Date**: 2026-05-14

### file_reader 属于 data 层
- `lib/data/file_reader.dart` + `_native.dart` + `_web.dart`
- 不在 `core/utils/`，因为文件 I/O 是数据访问操作
- **Date**: 2026-05-14

## Routing / 路由

### URL query params 用 tryParse 不用 parse
- `app_router.dart` 里 `int.tryParse` 而不是 `int.parse`
- state.extra 使用前必须做类型检查
- **Why**: URL 参数可能为空或格式不对，parse 会抛异常
- **Date**: 2026-05-02

## Security / 安全

### 密钥文件禁止提交到 Git
- `key.properties`、`*.jks` 必须在 `.gitignore` 中
- **Why**: 签名密钥泄露可导致供应链攻击
- **Date**: 2026-05-14

### 密码只存 FlutterSecureStorage，不回退到数据库
- 读取密码时 `storage.read()` 返回 null → 跳过该账户，不用 `?? account.password`
- **Why**: 数据库中密码字段是明文，迁移完成后应为空，但不应依赖回退
- **Date**: 2026-05-14

### Release 构建必须启用 R8 混淆
- `build.gradle.kts` release buildType 必须有 `isMinifyEnabled = true`
- **Why**: 不混淆的 APK 类名/方法名/字符串明文可读，逆向极容易
- **Date**: 2026-05-14

### 同步层禁止空 catch 块
- `sync_service.dart` 中所有 `catch` 必须至少 `debugPrint`
- **Why**: 空 catch 吞掉异常导致同步失败无法排查
- **Date**: 2026-05-14

### Provider 中解析外部输入用 tryParse + fallback
- `eventsInDateRangeProvider` 等 family provider 解析 key 时用 `int.tryParse`
- 解析失败返回空数据而非抛异常
- **Why**: 异常 key 会导致 Provider 级联崩溃，整个视图白屏
- **Date**: 2026-05-14

## Linux Distribution / Linux 分发

### Linux 构建必须在 Ubuntu 22.04 上执行
- CI 中 Linux 构建 job 的 `runs-on` 必须是 `ubuntu-22.04`，不能用 `ubuntu-latest`
- **Why**: Ubuntu 22.04 的 GLIBC 是 2.35，这是支持的最低目标版本。用更新系统构建会引入高版本 GLIBC 依赖，导致用户在旧系统上无法启动
- **验证方法**: `tool/check_glibc_version.sh` 会检查产物 GLIBC 版本需求不超过 2.35
- **Date**: 2026-05-14

### Linux 分发不做 Flatpak/AppImage/Snap 双轨制
- 只维护裸二进制 bundle 分发（`flutter build linux --release` 产物）
- 不做 Flatpak 打包，不做双轨制
- **Why**: 项目用户群体偏技术，Ubuntu 22.04 基线覆盖绝大多数用户。双轨制维护成本 > 收益
- **Date**: 2026-05-14

### 新增原生依赖前必须检查 GLIBC 基线
- 引入包含 `.so` 的 Flutter 插件后，在 CI 中通过 `tool/check_glibc_version.sh` 验证
- **Why**: 插件原生 `.so` 可能引入高版本 GLIBC 依赖，CI 未捕获会导致发布后用户无法运行
- **Date**: 2026-05-14

## Database / 数据库 (continued)

### subtask parentId 不加外键约束
- `todos.parentId` 定义为 `IntColumn get parentId => integer().nullable()()`，不设置 `REFERENCES todos(id)`
- 删除父待办时使用软删除（`deletedAt`），子待办的 `parentId` 保留
- **Why**: 子任务删除后父任务可能还存在，不需要级联删除；自引用 FK 在迁移中容易引发循环依赖
- **Date**: 2026-05-15

## CLI / 命令行

### CLI 数据库路径必须匹配 Flutter 应用
- `bin/dayspark.dart` 中的路径生成逻辑：
  - Linux: `$XDG_DATA_HOME/com.dayspark.app/calendar_todo.db` (fallback `~/.local/share`)
  - macOS: `~/Library/Application Support/com.dayspark.app/calendar_todo.db`
  - Windows: `$APPDATA/com.dayspark.app/calendar_todo.db`
- 如果 Flutter 应用更改了数据库路径，CLI 必须同步更新
- **Why**: CLI 和 GUI 共享同一个 SQLite 数据库文件，路径不一致会导致数据隔离
- **Date**: 2026-05-15

## Web / 网页

### app_database.dart 不能导入 drift/native.dart
- `lib/data/local/database/app_database.dart` 不 import `package:drift/native.dart`
- CLI 专用的 `NativeDatabase` 调用在 `lib/data/local/database/app_database_file.dart`
- **Why**: `drift/native.dart` 依赖 `dart:ffi`，而 `dart:ffi` 在 web 上不可用。web 构建使用 `drift_flutter` 的 WASM 后端（`DriftWebOptions` + `sqlite3.wasm`），不需要 native SQLite
- **Date**: 2026-05-15

### CLI 复用 Drift DAOs，不手写 SQL
- `bin/dayspark.dart` 使用 `AppDatabase.forFile()` + `NativeDatabase`（纯 Dart，不依赖 Flutter）
- 全部表定义、迁移、类型安全查询共享 Flutter 项目同一套 Drift 注解
- `lib/data/local/database/connect_flutter.dart` 隔离了 Flutter 的 `driftDatabase()` 调用，CLI 不导入该文件
- **Why**: 消除两份 Schema 维护成本；CLI 自动获得全部 9 表 + 迁移支持；`NativeDatabase` 来自 `package:drift/native.dart`，无需 Flutter
- **Date**: 2026-05-15

## Windows Build / Windows 构建

### Windows release AOT 必须在 NotificationDetails 中指定 windows 参数
- `_scheduleNotification` 和 `snooze` 方法中 `NotificationDetails` 必须包含 `windows: WindowsNotificationDetails(...)` 且至少含一个 action
- 不能省略 `windows` 参数或留空 `WindowsNotificationDetails()`
- **Why**: `flutter_local_notifications_windows` 3.0.0 的 FFI 绑定中 `NativeLaunchDetails` 类在无引用时会被 tree-shaker 删除，导致 Dart `gen_snapshot` full-AOT 编译崩溃（exit code -1073740791, "Class with illegal cid"），报错 MSB8066
- **Root cause**: Dart VM `gen_snapshot` 的 tree-shaking 与 AOT 序列化之间的兼容性 bug。FFI 类被 tree-shaker 优化掉后，序列化器找不到类定义
- **Diagnosis**: 添加 `--verbose` 发现 `aot_elf_release` 步骤中 `gen_snapshot` crashed with `Unexpected object (Class with illegal cid, full-aot): flutter_local_notifications_windows NativeLaunchDetails`
- **Date**: 2026-05-15
