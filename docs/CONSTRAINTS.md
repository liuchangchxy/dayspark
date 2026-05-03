# Technical Constraints / 技术约束记录

> 防止上下文压缩后遗忘已踩过的坑，导致回归 bug。
> 每次修 bug 或做关键决策后必须更新此文件。

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

## Routing / 路由

### URL query params 用 tryParse 不用 parse
- `app_router.dart` 里 `int.tryParse` 而不是 `int.parse`
- state.extra 使用前必须做类型检查
- **Why**: URL 参数可能为空或格式不对，parse 会抛异常
- **Date**: 2026-05-02
