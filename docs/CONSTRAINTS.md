# Technical Constraints / 技术约束记录

> 防止上下文压缩后遗忘已踩过的坑，导致回归 bug。
> 每次修 bug 或做关键决策后必须更新此文件。

**TL;DR / 快速了解**
- 本文件记录所有技术约束，按领域分组（Calendar / Database / UI / Security / Platform）
- 核心约束：kalender 钉 0.17.x、App Group 家族名 `group.com.dayspark.app` 双写、adhoc 下 macOS 禁 keychain-access-groups、iOS entitlements 三配置接线、小组件 v2 快照 10 键（含 monthDots）、版本号必须动态读取、Linux 构建必须 Ubuntu 22.04
- 修改日历/DB/Provider/通知/小组件/Apple 签名相关代码前**必须先读**对应章节

---

## Calendar / 日历

### kalender 钉 0.17.x minor
- `pubspec.yaml` 只允许 `kalender: ^0.17.x`，禁止跨 minor 升级
- **Why**: pre-1.0 破坏性变更落在 minor；跨 minor 必须先读上游 migration guide 并回归日历测试
- **Date**: 2026-09-22

### 重复事件只按可见窗口展开
- `expandRecurringEvents` 用 `before/after` 窗口参数（`home_page` 传 viewedDate ±45 天），禁止回到 2000–2030 全量展开
- **Why**: 全量展开是性能 bug；±45 天覆盖月视图 6 周网格（anchor 前 7 天、后 34 天）
- **Date**: 2026-09-22

### 重复/全天事件禁止拖拽（S1 系列损坏守卫）
- `KalenderCalendarEvent.fromAdapter` 对 `rrule != null || isAllDay` 设 `EventInteraction.allowNone()`；`onEventChanged` 回调层再拦一次
- **Why**: 拖单次实例会把新时间写回共享 drifId，改坏整个系列
- **Date**: 2026-09-22

### _calendarRange 必须是静态的
- `home_page.dart` 中的 `_calendarRange()` 返回固定的 `DateTime(2000,1,1)` 到 `DateTime(2030,12,31)`
- 不能跟 `_calendarAnchor` 联动
- **Why**: 动态 range 会改变 provider key → `eventsInDateRangeProvider(rangeKey)` 重新加载 → CalendarSection 被销毁重建 → 滑动状态丢失
- **Date**: 2026-05-03

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

### 版本标记由 CI 守卫，SSOT 是 pubspec.yaml
- `tool/check_version_consistency.sh` 校验 `CLAUDE.md`（Current version）、`docs/changelog.md`（`Latest` + 顶部 `## v` 节 + `Previous` 行必须等于第二节版本）、`docs/ROADMAP.md`（`Last updated` + `Current` + `Version` 行）
- 门的位置：`ci.yml` `test` job 首步（`test` 是所有构建 job 的 `needs`，不一致即全红）+ `release.yml` `version-gate`（`--tag` 要求 tag = `v<pubspec semver>`，防止打错 tag 发出标注错误的产物）
- **README 徽章与 `docs/START_HERE.md` 不在门内**：徽章已改 shields.io 动态徽章（`github/v/release?include_prereleases`，读 GitHub Releases，无手同步点）；START_HERE 的版本一律指向 `pubspec.yaml` / `docs/ROADMAP.md`，不复制（其自身第 3 行的防漂移原则）
- **`releases/latest` 对本仓库无效**：全部 release 都是 prerelease，GitHub 的 `/releases/latest` 只认非 prerelease → 302 回 `/releases` 列表。徽章靠 `include_prereleases` 参数绕开，文档链接一律用 `/releases`
- **Why**: 四处版本号靠人同步，发布提交漏改一处即静默漂移；tag 与 pubspec 不一致时 `release.yml` 仍会照常出包
- **Date**: 2026-09-24

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

### 通知 payload 带 reminderId，snooze 用 reminder.id
- Payload 格式：`parentType:parentId:reminderId`（旧两段格式仍可解析）
- Snooze 以 reminder.id 调度（不再用 parentId+100000 偏移）
- **Why**: parentId 会撞 notification id 空间，且 cancel 够不到 snooze 后的通知
- **Date**: 2026-09-22

### 通知链手工验证清单（真机/模拟器，每次改通知相关代码后过一遍）
- [ ] 创建带提醒的待办 → 到点响
- [ ] 通知上点 Snooze 1h → 1 小时后再次响
- [ ] 通知上点 Mark Complete → 待办完成且剩余提醒不响
- [ ] 完成待办 → 其提醒不再响；取消完成 → 提醒恢复
- [ ] 修改 due date → 提醒按新时间响
- [ ] 待办进回收站 → 提醒不响；恢复 → 未来提醒恢复调度
- [ ] 父待办删除（级联子任务）→ 父子提醒都不响
- [ ] 清空回收站 / 永久删除 → 无残留通知
- [ ] 事件删除/清空事件回收站 → 提醒不响
- [ ] 重启设备 → 提醒仍会响（ScheduledNotificationBootReceiver）
- [ ] 语言切中文后新建提醒 → 通知文案为中文
- [ ] Android 14+：系统设置→精确定时权限已授予（设置页有引导入口兜底）
- **Date**: 2026-09-22

### time-sensitive entitlement 的设备门：个人 team 不支持 capability，上真机/TestFlight 前必须 keep/remove 拍板
- `ios/Runner/Runner.entitlements` 保留 `com.apple.developer.usernotifications.time-sensitive` + 代码两路径（schedule/snooze）`interruptionLevel: .timeSensitive`；但**个人免费开发 team 不支持该 capability** → `flutter build ios`（device）在 provisioning profile 创建阶段 **fail-closed** 失败（无损坏产物）；模拟器/CI 不受影响
- 真机/AdHoc/TestFlight 前二选一并记录决策：**保留**（付费 team 开启 capability）或**移除**（删 entitlement 中该单行——代码优雅降级为普通 `.active` 行为，无需改 Dart）
- macOS 侧 `timeSensitive` 无对应 capability 时由系统降级，故意不动 macOS entitlements
- **Why**: 与 macOS keychain 同类的「capability 与签名身份不匹配」风险——这次落在构建期 fail-closed 而非启动期 SIGKILL，但放行真机签名前不拍板就发不出 TestFlight 包
- **Date**: 2026-09-24

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

## Architecture / 架构

### 基础设施服务放在 lib/infrastructure/ 而非 domain/services/
- 平台插件调用（alarm、notification、home_widget）→ `lib/infrastructure/platform/`
- `domain/services/` 只保留纯领域逻辑（ai_scheduler、ics）
- **Why**: 平台 API 变化不应触及领域层；基础设施可独立替换
- **Date**: 2026-05-14 (updated 2026-09-22: CalDAV sync 与客户端 MCP 已移除)

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
- CI 中从 **GitHub Secrets** 注入：`ANDROID_KEYSTORE` (base64)、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`
- `release.yml` 的 `build-android` job 在 `flutter build` 前通过 `echo "${{ secrets.ANDROID_KEYSTORE }}" | base64 -d` 还原 keystore 文件
- `build.gradle.kts` 有 `if (keystorePropertiesFile.exists())` 守卫，无 keystore 时跳过签名（CI 验证构建走 unsigned 路径）
- **Why**: 签名密钥泄露可导致供应链攻击
- **Date**: 2026-05-14 (updated 2026-05-17)

### Release 构建必须启用 R8 混淆
- `build.gradle.kts` release buildType 必须有 `isMinifyEnabled = true`
- **Why**: 不混淆的 APK 类名/方法名/字符串明文可读，逆向极容易
- **Date**: 2026-05-14

### Provider 中解析外部输入用 tryParse + fallback
- `eventsInDateRangeProvider` 等 family provider 解析 key 时用 `int.tryParse`
- 解析失败返回空数据而非抛异常
- **Why**: 异常 key 会导致 Provider 级联崩溃，整个视图白屏
- **Date**: 2026-05-14

## Home Widget / 小组件

### App Group 固定 `group.com.dayspark.app`，宿主与组件必须同组
- iOS/macOS 宿主与 widget extension 的 entitlements `application-groups` 都必须含 `group.com.dayspark.app`（**macOS Runner 的 DebugProfile/Release 曾整段缺失**，沙盒宿主写不进组件读的 suite）
- `lib/main.dart` 在 `WidgetsFlutterBinding.ensureInitialized()` 后立即 `HomeWidget.setAppGroupId('group.com.dayspark.app')`（仅 iOS/macOS，`!kIsWeb` 守卫），必须在任何 `saveWidgetData` 之前
- **Why**: 不同组 = 静默写入失败，组件永远显示旧数据；改组名需同时改 5 个 entitlements + Swift/Kotlin 读取端，禁止单边改
- **Date**: 2026-09-24（P4 资产统一群组从 `group.com.calendarTodoApp` 迁移到 `group.com.dayspark.app`，宿主/组件/代码三处必须原子同改）

### 小组件刷新是写驱动的，刷新逻辑只能挂在 tableUpdates 单点
- `homeWidgetAutoRefreshProvider` 订阅 `db.tableUpdates`（todos + events 两表），合并去重后调 `HomeWidgetService.updateWidget`（同一时刻最多一个 in-flight，写入期间只补一次 trailing run）
- 禁止改为逐 provider 手动调刷新：`todo_edit_page._save`、`event_edit_page._save`、`home_page` 拖拽都绕过 provider 直接 `db.update(...).write(...)`，挂 provider 会全部漏掉
- 冷启动读不触发（`tableUpdates` 只在写时发）；冷启动刷新保留在 `home_page` initState
- **Why**: Drift 的表更新通知是唯一能覆盖所有写入点的 choke point
- **Date**: 2026-09-22

### 小组件键双写：legacy 三键 + versioned `widget_snapshot` 同时写
- legacy：`today_events` / `pending_todos` / `todo_count` — 现有 Kotlin/Swift 读取端只认这三个
- versioned：`widget_snapshot` v2（`{version:2, generatedAt, todayEvents, pendingTodos, todoCount, upcoming, pendingTaps, ui, theme, monthDots}`，**10 顶层键**）— P4 迁移读取端的唯一契约，item 形状与 legacy 刻意一致
  - `upcoming`：**今天之后连续 7 天**（[明天 00:00, +8 天 00:00)）的事件+有日期顶层待办；今天不进 upcoming（todayEvents 已覆盖，Upcoming 变体与今日组件并排会重复）
  - `pendingTaps[]`：native→app 勾选通道。app 每次 flush 消费后写 `[]`；无消费者的 flush 必须**原样保留** native 追加的条目（禁止裸清空）；消费走 `toggleTodoProvider`（提醒取消/markComplete/outbox 单一写路径），组件端禁止直写库。flush 在途的 read→write 窗口内 native append 会被覆盖，已接受的已知边缘（概率=突变触发的 flush 与点击同毫秒）
  - `ui`：按当前 locale **预本地化**的全部组件文案（gen-l10n arb 生成，Kotlin/Swift 零硬编码英文）；locale 切换靠下一次快照写入生效
  - `theme`：`{dark, colors{background,surface,textPrimary,textSecondary,accent,border}}`（`#RRGGBB`），dark 由 `theme_mode` prefs + 平台亮度解析
  - `monthDots`：`List<[int day, bool hasEvent]>`（仅 `hasEvent=true` 对写入；当前自然月），月点阵变体数据源——**T4 评审时的 9 键清单已过期，golden 断言以 10 键为准**
- 删除/改名任何一侧前必须先迁移全部三个原生读取端（Android SharedPreferences + iOS/macOS UserDefaults suite）
- **Why**: 单写新键会让现网组件立刻空白；单写旧键则 P4 无迁移目标
- **Date**: 2026-09-22（v2 契约补全 2026-09-24：upcoming/pendingTaps/ui/theme；`monthDots` 第 10 键 2026-09-24 随 T3 原生端落地）

### 小组件快速添加通路：home_widget interactivity 回调 + `dayspark://quick-add`
- widget 按钮点击走 `HomeWidget.registerInteractivityCallback(widgetInteractivityCallback)`（main() 注册，vm:entry-point）；回调**只做导航**（→ `/todo/new?source=widget`），不碰数据库——落库只在 flush 的 pendingTaps 消费路径
- 通用 deep link 统一翻译函数 `widgetDeepLinkLocation`（`dayspark://quick-add` → quick-add location）；go_router 只认 path 不认 scheme，scheme→path 的映射必须集中在此
- Android intent-filter / iOS URL types 注册在原生任务（T3）；本任务只保证 Dart 侧 route + 回调入口存在
- **Why**: 双通道（SP 队列勾选 + interactivity 导航）职责分离，防双写库
- **Date**: 2026-09-24

## Apple Signing / Apple 签名

### adhoc/teamless 签名下 macOS entitlements 禁止出现 `keychain-access-groups`（整键必须缺失）
- `macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements` 在 adhoc/teamless 签名（本地 debug 直跑、CI release/DMG）下**不得包含** `keychain-access-groups` key——**空数组也不行**
- 现象：`$(AppIdentifierPrefix)` 展开为裸 bundle id → sandboxed adhoc app 被 taskgate 以 `Invalid Signature` SIGKILL（`codesign --verify` 仍通过、`spctl` 是红鲱鱼）；2026-09-24 用户实测崩溃，填值版与**空数组版均 exit 137**，整键删除后存活（VM service + GoRouter home）
- `flutter_secure_storage` 落 default keychain partition（Dart 侧不传 groupId）；只有真实 Developer-ID/Team 签名构建才可加回该键（WHY 注释留在 plist dict 内）
- **Why**: upstream README 的 empty-array 写法只适用于有真实签名身份的场景；macOS 27 adhoc+sandbox 下 key 存在即触发 taskgate 拒绝，CI macOS DMG 走同一 adhoc 路径会全军覆没
- **Date**: 2026-09-24

### iOS `Runner.entitlements` 必须挂在全部三个构建配置
- `ios/Runner.xcodeproj/project.pbxproj` 的 Runner Debug/Release/Profile 必须各有 `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`（现位于 :728/:911/:934）；文件存在但 pbxproj 不引用 = **inert**（2026-09-24 实锤：entitlements 文件从未被接线，time-sensitive/app-group 都没真正嵌入，旧「sim build 绿」门禁是空的）
- 新增/修改 entitlement key 后必须用 `xcodebuild -showBuildSettings` 核对该配置，并检查构建产物链接进的 `__TEXT,__entitlements` 段；注意 Xcode 27 对 `iphonesimulator` SDK 报 `ENTITLEMENTS_ALLOWED = NO`——`codesign -d --entitlements -` 在 sim 产物上打印空 `{}` 是平台策略，不代表没嵌入
- **Why**: 接线遗漏让 entitlement 静默失效，验收门形同虚设；三配置缺一（如只挂 Release）会在对应构建形态下丢失 capability
- **Date**: 2026-09-24

### `build-ios-simulator`：无证书 iOS 编译门（首跑未验）
- `ci.yml` 新增 `build-ios-simulator` job（`needs: test` → `runs-on: macos-latest` → `flutter build ios --simulator --debug`），是个人/无证书 team 下的 iOS 编译门；对 `ci.yml` 的改动 insertion-only（只新增 job/步骤，不动既有逻辑）
- **首跑未证实**：job 本地同命令跑绿过，但 CI 运行时行为要到首次普通 push 才验证——按正交法则，首次 push 必须盯该 job 首跑
- 与上条互补：sim 编译绿 **≠** entitlement 已嵌入（Xcode 27 对 `iphonesimulator` 的 `codesign -d` 打空 `{}` 属平台策略；嵌入验证见上条 `Runner.entitlements` 的 `__TEXT,__entitlements` 段检查）
- **Why**: 个人 team 无证书、device `flutter build ios` 在 provisioning 阶段 fail-closed，没有此门则 iOS 编译回归只能靠手工冒烟兜底；同时防止把「sim 编译门」误当 entitlements 验收门（旧「sim build 绿 = 门禁空」教训）
- **Date**: 2026-09-24

### pending_todos 查询：NULL 到期沉底 + 过滤子任务
- `ORDER BY (due_date IS NULL) ASC, due_date ASC` + `parentId.isNull()`
- **Why**: 普通 `ASC` 在 SQLite 中 NULL 排最前，组件三个槽位会被无日期/子任务占满
- **Date**: 2026-09-22

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

### Windows release AOT 崩溃 (MSB8066 / gen_snapshot exit code -1073740791)
- **现象**: `flutter build windows --release` 在 `gen_snapshot --snapshot_kind=app-aot-elf` 步骤崩溃，报错 `Unexpected object (Class with illegal cid, full-aot): NativeLaunchDetails`，然后 AOT snapshotter crashed with exit code -1073740791
- **影响版本**: Flutter 3.41.5 / 3.41.7 / Dart 3.11.x
- **触发类**: `package:flutter_local_notifications_windows/src/ffi/bindings.dart` 中的 `NativeLaunchDetails` FFI struct
- **已排除的假设**:
  - ❌ 不是 runner image 问题（windows-2022 和 windows-2025 都崩溃）
  - ❌ 不是 tree-shaking 问题
  - ❌ 不是 `final class` vs `base class` 问题（两者都崩溃）
  - ❌ 不是 struct 内的 getter 问题（移除 getter 后仍然崩溃）
- **根因**: Dart VM `gen_snapshot` 对 `NativeLaunchDetails` FFI struct 的 AOT 序列化 bug。该 struct 在回调中按值传递（`ffi.Void Function(NativeLaunchDetails details)`），包含嵌套 struct 和 `Pointer<Utf8>` 字段，触发 VM 内部 class ID 错误
- **最终方案**: 将 `patches/flutter_local_notifications_windows/` 替换为纯 Dart stub 实现，不依赖 FFI、不编译原生 DLL。Windows 通知功能暂时禁用，但 Windows release 构建可以成功
- **Flutter 版本**: release.yml 统一使用 3.41.7（与 CI debug 和 macOS release 一致）
- **CI lint**: `analysis_options.yaml` 排除 `patches/**` 目录，避免第三方补丁包的 pre-existing lint 警告导致 CI 失败
- **Date**: 2026-05-16

## CI/CD / 持续集成与发布

### CI 必须构建 release 模式
- `ci.yml` 中所有平台的 `flutter build` 命令使用 `--release` 而非 `--debug`
- Web/macOS/Linux/Windows/Android 全部走 release 构建
- **Why**: `--debug` 不会触发 AOT 编译、tree-shaking、R8 混淆等 release-only 阶段， 只测 debug 就放行会导致发版时才暴露构建崩溃
- **验证方法**: CI 绿了等于 release 构建通过了
- **Date**: 2026-05-16

### Release 必须从 Draft 发布
- `release.yml` 使用 `draft: true`，tag 推了只创建草稿 release
- 人工验收产物后，去 GitHub 上手动点 "Publish release"
- **Why**: 防止 bug 通过未经验证的 release 直接暴露给用户；给"打磨"留一道质检关卡
- **例外**: 不影响已有 prerelease 标记（`isPrerelease` 仍然为 true，v0.x 全部是 prerelease）
- **Date**: 2026-05-16

## Android Build / Android 构建

### home_widget 必须 ≥0.9.2（钉住浮动 Android 依赖）
- home_widget 0.9.1 的 `android/build.gradle` 用 `glance-appwidget:1.+` / `work-runtime-ktx:2.+` / `kotlinx-coroutines-android:1.+` 动态坐标，构建日漂移：`glance 1.3.0-alpha02` 要求 compileSdk 37（本项目 AGP 8.11.1 上限 36）、`work-runtime` 新版 JVM-11 字节码与插件 `jvmTarget 1.8` 内联冲突
- 上游 0.9.2 修复（#418 pin deps）；当前 lock 为 **0.9.4**（`^0.9.2` 范围内），升级依赖时禁止回退到 0.9.1
- **Why**: 5 月能过的 APK 构建突然失败，根因是上游浮动坐标，不在本仓库代码
- **Date**: 2026-09-22

### 本地构建 Java：Flutter 必须指向 JDK 17，不能用 Android Studio JBR 25
- `flutter config --jdk-dir=/opt/homebrew/Cellar/openjdk@17/17.0.20.1/libexec/openjdk.jdk/Contents/Home`
- Flutter JDK 探测顺序是 Android Studio JBR → JAVA_HOME → PATH；本机 JBR 为 **25.0.3**，与 Gradle 8.14 不兼容（Gradle 8.14 支持 ≤24），设 `JAVA_HOME` 无效
- `android/gradle.properties` 中 `android.builtInKotlin=false` / `android.newDsl=false` 是 Flutter 3.47 migrator 自动写入，勿删
- **Why**: 不设 jdk-dir 每次本地 APK 构建都在第一步炸，报错指向 Gradle 而非真正原因
- **Date**: 2026-09-22

## Toolchain / 工具链

### 本地 Flutter 版本与 CI pin 不一致（2026-09-22）
- 本地 `flutter --version`（2026-09-22）：
  - **Flutter 3.47.3** • channel stable • https://github.com/flutter/flutter.git
  - Framework • revision e8113bf456 (2 weeks ago) • 2026-09-04 13:20:08 -0700
  - Engine • hash 0e228ec8c8d2abc9fcf1d053e8a40665bb859ec7 (revision 06a2e2a110) (19 days ago) • 2026-09-03 16:07:13.000Z
  - Tools • Dart 3.13.3 • DevTools 2.60.0
- 修复方式：brew cask 卡在 `3.41.7.upgrading`（实际内容为 3.47.3），`brew upgrade flutter --cleanup` 无效（无 `--cleanup` 选项），`brew reinstall --cask flutter` 下载 3.47.5 过慢（>1 小时）放弃；fallback 为 symlink：`/opt/homebrew/bin/{flutter,dart}` → `/opt/homebrew/Caskroom/flutter/3.41.7.upgrading/flutter/bin/{flutter,dart}`
- **CI 对照**：`ci.yml`/`release.yml` 在 macOS/Windows job 固定 `flutter-version: "3.41.7"`，其余 job 用 `channel: stable`（浮动最新）→ **本地 3.47.3 与 CI pin 3.41.7 不一致**，存在版本漂移风险；本任务不改 CI 文件
- **Why**: 记录实际可用工具链版本与 CI 差异，防止后续任务误以为本地=CI
- **Date**: 2026-09-22

## Sync / 同步

### 游标 = 服务器单调水位线，绝不用时间戳
- `GET /sync/pull` 与 push 响应里的 cursor 是 `records.seq` 的**单调不透明水位线**（整数），禁止改用客户端/服务器时间戳当游标；`PushResponse.cursor` = **已投递水位线**（piggyback 封顶时 = 最后一条已投递 seq，未封顶 = head，空 piggyback 保留请求 cursor 不回退）
- **Why**: 时钟漂移与同秒并发改动会让时间戳游标丢变更；水位线语义保证「≤ cursor 的变更已全部见过」，封顶 piggyback 不产生静默缺口（T3 C1 裁定）
- **Date**: 2026-09-23

### LWW 只按服务器到达序对 set 键字段合并
- 冲突解决 = **op set 过的字段**按服务器到达顺序取胜，未 set 的字段保留服务器现值；记录级 delete vs update 用 `server_ts` 比较，同秒用 opId 字典序破平；客户端**只发 dirty 字段**（`SyncSnapshot` + `dirtyFields` 对上次服务端真值求差，空 diff 视为收敛丢弃 op）
- **Why**: 全量 payload 推送会让每个键都被 "set"，字段级 LWW 退化为整条覆写——e2e 矩阵例 ④ 抓到的真实丢更新（并发不相交字段编辑被改回旧值）
- **Date**: 2026-09-23

### Push 逐 op 独立事务，部分失败绝不整批回滚
- 每个 op 单独事务：查 `sync_ops(op_id)` 幂等回放 → 校验 → LWW 写 `records` → `nextSeq` → 存 op 结果；非法 op 只标记自身 `rejected/…`，同批其余 op 照常应用，响应逐条返回 status
- **Why**: 整批回滚会让合法操作被非法邻居拖累，违背协议「逐条结果、绝不整批回滚」契约（SPEC 3.2 规则 2）
- **Date**: 2026-09-23

### Tombstone ≥45 天才 GC；SSE 只发 cursor 信号
- 软删写 tombstone，经 pull 广播，**保留 ≥45 天**后才可 GC；`GET /sync/stream` 的 SSE 帧**只含 `{"cursor":N}`**，不携带记录载荷，收到信号后走 pull 取数
- **Why**: 45 天覆盖长期离线设备的重连窗口，提前 GC 会让离线删除复活/丢失；SSE 无载荷使 pull 成为唯一数据通路，避免流上分叉出第二套应用语义（SPEC 3.2 规则 3/5）
- **Date**: 2026-09-23

### 服务端密码哈希：argon2id（argon2_web）
- 参数 **argon2id, v=19 (0x13), t=3, m=32768 KiB (32 MiB), p=1, 16 字节随机盐, 32 字节 key**；存储串为自描述格式 `argon2id$v=19$m=32768,t=3,p=1$<salt>$<key>`（b64url，非 PHC），verify 从串内读参数；比较用常量时间 XOR
- 选型前已跑 KAT：包自带测试 + pointycastle argon2i v1.0、官方 argon2i v1.3 向量、**RFC 9106 argon2id 全向量** 全部通过；PBKDF2-SHA256 100k 回退预案**未启用**
- **Why**: 纯 Dart（无 FFI，避开 Xcode/CI 原生编译风险）；KAT 先证伪再采用，防止小众包哈希错误静默损坏全部账号
- **Date**: 2026-09-23

### 服务端镜像 glibc 天花板 GLIBC_2.18（server AOT 非静态）
- `dart compile exe` 产物**不是**静态 ELF（构建期 ldd 实证动态链接 libc），符号天花板实测最高 **GLIBC_2.18**；运行时与构建同代（`debian:trixie-slim` ↔ `dart:stable`），Dockerfile 两行 `FROM` 必须保持同代（构建日志 `head /etc/os-release` 可查）
- `tool/check_glibc_version.sh` 面向 Flutter Linux bundle，**不管** server 产物；本地执行若无 readelf 会输出 `SKIP: readelf not found (install binutils)`
- **Why**: 运行镜像比构建镜像旧会启动即 `GLIBC_x.y not found`；记录天花板供换基座时对照
- **Date**: 2026-09-23

### 前台 15s 定时轮询兜底 + resumed 立即触发（ForegroundSyncPoller）
- 仅「前台 && 引擎运行」时 `Timer.periodic(15s)` → `requestRound`（每 tick 一次 push+pull HTTP，引擎 coalesce 控代价，计划内可接受）；`onResume` 立即触发一轮再启表，`onPause` 停表
- **Why**: 部分反代下 SSE 长连接静默滞留不 FIN（T4），监听器既不 error 也不重连、信号断流；前台靠定时拉取兜底，回前台立即一轮覆盖离线期变更（changelog/ROADMAP 的「回前台触发」即此）
- **Date**: 2026-09-23

## MCP / AI 接口

### 业务错误必须以工具结果返回，绝不走 JSON-RPC error
- `tools/call` 的校验失败/未找到/无权限 → `{content:[{type:'text',text:{code,message,hint}}], isError:true}`；JSON-RPC error（−32601/−32700/−32600/−32002/−32601）**只**留给协议层（未知 method、解析失败、坏信封、未知资源 URI）
- **Why**: AI 客户端对 `isError` 工具结果会读内容并自行纠错重试，对 JSON-RPC error 则直接中止会话——业务失败走协议层会让 AI 拿不到 hint（SPEC 3.3 规则 4）
- **Date**: 2026-09-23

### 禁止任何永久删除工具（trash = 软删可恢复）
- 工具面只有 `trash_event`/`trash_task`（写 `deletedAt` 进回收站，`destructiveHint:true`）；**不存在** `delete_*`/`purge_*`/`empty_trash` 工具，永久删除与清空回收站只在 App UI
- **Why**: AI 幻觉点错不可撤销是信任一票否决项；软删与 App 回收站语义对齐，用户可全量恢复（SPEC 3.3 规则 5）
- **Date**: 2026-09-23

### Datetime：输出固定 ISO-8601 `…Z`，输入拒 naive、timezone 参数必须 IANA
- 所有工具输出的时间字段经 `isoZ` 规范化为定宽 UTC `Z` 串；输入（`from`/`to`/`due`/`until`…）必须带时区偏移，naive 串直接 `VALIDATION` 拒绝；`timezone` 参数只接受 IANA 名（`Asia/Shanghai`），不收 `UTC+8`/缩写
- **Why**: naive 串按服务器本地时区解析会在部署环境变化时静默漂移（T1 结转 M-2）；定宽 `Z` 串使字典序 = 时间序，窗口过滤 SQL/Dart 双路径一致
- **Date**: 2026-09-23

### RRULE 只收结构化对象，不收原始字符串
- `recurrence` 参数 = 结构化对象（`freq`/`until`/`count`/`interval`/`byday`…），经 `parseRruleStructured` 校验；裸 RRULE 文本串拒绝
- **Why**: 原始 RRULE 字符串方言多（分隔符、参数序），自由文本校验无法给出逐字段 hint；结构化对象可逐键验证并生成 AI 可执行的修正建议
- **Date**: 2026-09-23

### Scope 双门：`mcp:read`/`mcp:write` 同时管工具与资源
- scope 校验覆盖 `tools/call`（按注解 readOnly/destructive 映射）**和** `resources/list`/`resources/read`（read 资源也要 `mcp:read`）；缺 scope → 工具侧 `FORBIDDEN_SCOPE` 工具结果、资源侧 JSON-RPC −32000 `data.code`；缺 scope 声明的 token 一律 fail-closed
- **Why**: 只门工具不门资源 = 只读降权 token 仍可枚举数据快照；T2 缝起初只盖 tools/call，评审结转由 T3 补全 resources——两处必须同进同退
- **Date**: 2026-09-23

### 双轨认证永不交叉：CLI = `/auth/login` token，Agent/connector = OAuth token
- CLI/本地脚本只走 `POST /auth/login`（`track:"cli"`，全 scope，`/oauth/*` 刷新端点拒绝）；Agent/ChatGPT connector 只走 OAuth 2.1（`track:"oauth"`，同意的 scope 子集，**仅**有效于 `/mcp`，`requireAuth` 在 `/sync/*` 与 `/auth/me` 上 401 拒绝）
- **Why**: 无头/CLI 场景没有浏览器会话走不了同意页；反过来 OAuth token 若能打 `/sync/push`，`mcp:read` 同意就变成全量写凭证——同意页上的 scope 列表会成为谎言（T3 裁定）
- **Date**: 2026-09-23

### Open DCR 必须落在反代限流 + body 上限之后
- 规则：Open DCR must sit behind rate limiting (nginx `limit_req`) + body cap; in-app limiter = P4（模板见 `docs/DEPLOY.md` §3：`limit_req_zone … 5r/m` + `client_max_body_size 256k`，作用域 `/oauth/register`）
- **Why**: `/oauth/register` 匿名可达且每次注册跑 argon2（CPU 密集），应用层限流 P3 未做——没有反代闸门就是匿名算力放大入口；body cap 另挡内存
- **Date**: 2026-09-23
