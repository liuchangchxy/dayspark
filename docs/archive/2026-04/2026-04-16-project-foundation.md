# Project Foundation Implementation Plan
> ⚠️ **已过时（2026-09-27 标注，正文原样保留仅供考古）**：本文是 2026-04 项目早期的方案讨论，CalDAV 路线已被自研同步后端替代（v0.22.0 落地），内容不再维护。现行状态唯一源：`calendar_todo_app/docs/START_HERE.md`（接续入口）、`calendar_todo_app/docs/ROADMAP.md`（功能全景）。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭建 Flutter 项目骨架——Clean Architecture 目录结构、主题系统、路由、Drift 数据库 schema + DAOs——产出可在 Web 上运行的应用壳。

**Architecture:** 采用 Clean Architecture 三层分离（data / domain / ui）。本地 SQLite（Drift）是唯一真相来源，所有读写先走本地。主题系统用 Token 化设计（颜色/字体分离为常量文件），路由用 go_router 声明式配置。

**Tech Stack:** Flutter 3.41.6 / Dart 3.11.4 / Drift 2.x (SQLite ORM) / Riverpod / go_router / freezed + json_serializable

---

## File Structure

```
calendar_todo_app/
├── lib/
│   ├── main.dart                          # App 入口，ProviderScope + MaterialApp.router
│   ├── core/
│   │   ├── theme/
│   │   │   ├── app_colors.dart            # 颜色 Token（亮色+暗色）
│   │   │   ├── app_typography.dart        # 字体排版 Token
│   │   │   └── app_theme.dart             # ThemeData 组装
│   │   ├── router/
│   │   │   └── app_router.dart            # GoRouter 路由配置
│   │   └── constants/
│   │       └── app_constants.dart         # 全局常量
│   ├── data/
│   │   └── local/
│   │       ├── database/
│   │       │   ├── app_database.dart      # Drift Database 类定义
│   │       │   ├── app_database.g.dart    # 生成文件
│   │       │   ├── tables/
│   │       │   │   ├── calendars_table.dart
│   │       │   │   ├── events_table.dart
│   │       │   │   ├── todos_table.dart
│   │       │   │   ├── tags_table.dart
│   │       │   │   ├── event_tags_table.dart
│   │       │   │   ├── todo_tags_table.dart
│   │       │   │   ├── attachments_table.dart
│   │       │   │   ├── sync_queue_table.dart
│   │       │   │   └── reminders_table.dart
│   │       │   └── daos/
│   │       │       ├── calendars_dao.dart
│   │       │       ├── events_dao.dart
│   │       │       ├── todos_dao.dart
│   │       │       └── sync_queue_dao.dart
│   │       └── secure_storage/
│   │           └── credential_storage.dart # 凭证安全存储
│   ├── domain/                            # 业务逻辑层（Phase 2+ 填充）
│   └── ui/
│       ├── pages/
│       │   ├── home/
│       │   │   └── home_page.dart         # 主页（日历+待办入口）
│       │   └── settings/
│       │       └── settings_page.dart     # 设置页
│       └── widgets/                       # 共享组件（Phase 2+ 填充）
├── test/
│   ├── data/
│   │   └── local/
│   │       └── database/
│   │           ├── tables/
│   │           │   └── tables_test.dart   # 表定义验证测试
│   │           └── daos/
│   │               ├── calendars_dao_test.dart
│   │               ├── events_dao_test.dart
│   │               └── todos_dao_test.dart
│   └── helpers/
│       └── test_database.dart             # 测试用内存数据库
├── DESIGN.md
├── NOTICE
├── pubspec.yaml
└── analysis_options.yaml
```

---

## Task 1: Create Flutter Project + Directory Structure

**Files:**
- Create: Flutter 项目骨架
- Create: `lib/core/`, `lib/data/local/database/tables/`, `lib/data/local/database/daos/`, `lib/data/local/secure_storage/`, `lib/domain/`, `lib/ui/pages/home/`, `lib/ui/pages/settings/`, `lib/ui/widgets/`, `test/helpers/`, `test/data/local/database/daos/`, `test/data/local/database/tables/`

- [ ] **Step 1: Create Flutter project**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目"
flutter create --project-name calendar_todo_app --org dev.opencal --platforms android,ios,web,macos,windows,linux calendar_todo_app
```

Expected: 项目创建成功，目录 `calendar_todo_app/` 出现

- [ ] **Step 2: Create Clean Architecture directories**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
mkdir -p lib/core/theme lib/core/router lib/core/constants
mkdir -p lib/data/local/database/tables lib/data/local/database/daos
mkdir -p lib/data/local/secure_storage
mkdir -p lib/domain
mkdir -p lib/ui/pages/home lib/ui/pages/settings lib/ui/widgets
mkdir -p test/helpers test/data/local/database/tables test/data/local/database/daos
```

- [ ] **Step 3: Remove Flutter template files**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
rm -f lib/counter.dart lib/screens/*.dart
```

- [ ] **Step 4: Verify project structure**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
find lib test -type d | sort
```

Expected: 看到上述所有目录

- [ ] **Step 5: Commit**

```bash
git init
git add -A
git commit -m "chore: initialize Flutter project with Clean Architecture directory structure"
```

---

## Task 2: DESIGN.md + NOTICE

**Files:**
- Create: `DESIGN.md`
- Create: `NOTICE`

- [ ] **Step 1: Create DESIGN.md**

```markdown
# DESIGN.md — Calendar Todo App Design System

AI 编码工具读此文件来保持 UI 一致性。

## Design Philosophy

功能导向的极简设计。参考标杆：Linear（克制用色）、Apple 日历（清晰实用）。
**拒绝"AI 味"：** 不大圆角、不渐变、信息密度优先。

## Colors

### Light Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #FAFAFA | 页面背景 |
| surface | #FFFFFF | 卡片/弹窗背景 |
| textPrimary | #1A1A2E | 主文字 |
| textSecondary | #6B7280 | 辅助文字 |
| accent | #2563EB | 按钮、选中态、链接 |
| accentHover | #1D4ED8 | 按钮悬停 |
| success | #16A34A | 成功状态 |
| warning | #EAB308 | 警告状态 |
| error | #DC2626 | 错误状态 |
| border | #E5E7EB | 边框、分割线 |

### Dark Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #0F0F14 | 页面背景 |
| surface | #1A1A2E | 卡片/弹窗背景 |
| textPrimary | #E4E4E7 | 主文字 |
| textSecondary | #9CA3AF | 辅助文字 |
| accent | #3B82F6 | 按钮、选中态、链接 |
| border | #2D2D3A | 边框、分割线 |

## Typography

使用系统默认字体，不加自定义字体包。

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| headline | 20sp | w600 | 页面标题 |
| title | 16sp | w600 | 卡片标题、Section 标题 |
| body | 14sp | w400 | 正文 |
| caption | 12sp | w400 | 辅助说明、时间标签 |
| overline | 10sp | w500 | 极小标签 |

## Spacing

基础单位 4px，所有间距为 4 的倍数。

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | 紧凑间距 |
| sm | 8px | 列表项间距、卡片间距 |
| md | 12px | 内边距（紧凑） |
| lg | 16px | 卡片内边距、Section 间距 |
| xl | 24px | 页面边距 |
| xxl | 32px | 大间距 |

## Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| sm | 6px | 按钮、输入框 |
| md | 8px | 卡片 |
| lg | 12px | 弹窗、对话框（最大值） |

## Component Principles

1. 能用一个颜色不用渐变
2. 能用纯色图标不用 emoji
3. 信息密度优先——一屏显示尽量多的有用信息
4. 动画只用于状态切换（0.2s ease），不用于装饰
5. 阴影极少使用，用 border 区分层次
6. 最小触摸目标 48x48dp
7. 色彩对比度符合 WCAG 2.1 AA
```

- [ ] **Step 2: Create NOTICE file**

```markdown
# Third-Party Notices

This project uses the following third-party libraries:

## Flutter SDK
Copyright 2014 The Flutter Authors. All rights reserved.
License: BSD-3-Clause

## Drift (SQLite ORM)
Copyright 2021 Simon Binder.
License: MIT

## Riverpod
License: MIT

## GoRouter
License: BSD-3-Clause

## Dio
License: MIT

## Freezed
License: MIT

## json_serializable
License: BSD-3-Clause

## flutter_local_notifications
License: BSD-3-Clause

## flutter_secure_storage
License: BSD-3-Clause

---
Full license texts are available in the respective package repositories.
This file will be auto-updated by `flutter_oss_licenses` in CI.
```

- [ ] **Step 3: Commit**

```bash
git add DESIGN.md NOTICE
git commit -m "docs: add DESIGN.md design system and NOTICE third-party licenses"
```

---

## Task 3: Dependencies (pubspec.yaml)

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Update pubspec.yaml with all Phase 1 dependencies**

Replace the default `pubspec.yaml` with:

```yaml
name: calendar_todo_app
description: An open-source cross-platform calendar and todo app with CalDAV sync.
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: '>=3.11.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1

  # Routing
  go_router: ^14.8.1

  # Database (Drift / SQLite)
  drift: ^2.24.0
  sqlite3_flutter_libs: ^0.5.30

  # Data models
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

  # Secure storage
  flutter_secure_storage: ^9.2.4

  # HTTP client
  dio: ^5.8.0+1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

  # Code generation
  build_runner: ^2.4.14
  drift_dev: ^2.24.0
  freezed: ^2.5.8
  json_serializable: ^6.9.4
  riverpod_generator: ^2.6.3

  # Testing
  drift_test:
    git:
      url: https://github.com/simolus3/drift.git
      path: extras/testing
```

- [ ] **Step 2: Run flutter pub get**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
flutter pub get
```

Expected: dependencies resolved successfully

- [ ] **Step 3: Update analysis_options.yaml**

Replace with:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_single_quotes: true
    require_trailing_commas: true
    always_declare_return_types: true
    avoid_print: true
    omit_local_variable_types: true
```

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml
git commit -m "chore: add core dependencies (riverpod, drift, go_router, freezed, dio)"
```

---

## Task 4: Theme System — Color Tokens

**Files:**
- Create: `lib/core/theme/app_colors.dart`
- Test: `test/core/theme/app_colors_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_colors_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/core/theme/app_colors.dart';

void main() {
  group('AppColors', () {
    test('light color tokens are non-null Color instances', () {
      expect(AppColors.lightBackground, isA<Color>());
      expect(AppColors.lightSurface, isA<Color>());
      expect(AppColors.lightTextPrimary, isA<Color>());
      expect(AppColors.lightTextSecondary, isA<Color>());
      expect(AppColors.lightAccent, isA<Color>());
      expect(AppColors.lightSuccess, isA<Color>());
      expect(AppColors.lightWarning, isA<Color>());
      expect(AppColors.lightError, isA<Color>());
      expect(AppColors.lightBorder, isA<Color>());
    });

    test('dark color tokens are non-null Color instances', () {
      expect(AppColors.darkBackground, isA<Color>());
      expect(AppColors.darkSurface, isA<Color>());
      expect(AppColors.darkTextPrimary, isA<Color>());
      expect(AppColors.darkTextSecondary, isA<Color>());
      expect(AppColors.darkAccent, isA<Color>());
      expect(AppColors.darkBorder, isA<Color>());
    });

    test('accent values are valid hex', () {
      // Light accent: #2563EB
      expect(AppColors.lightAccent, const Color(0xFF2563EB));
      // Dark accent: #3B82F6
      expect(AppColors.darkAccent, const Color(0xFF3B82F6));
    });

    test('light background is #FAFAFA', () {
      expect(AppColors.lightBackground, const Color(0xFFFAFAFA));
    });

    test('dark background is #0F0F14', () {
      expect(AppColors.darkBackground, const Color(0xFF0F0F14));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
flutter test test/core/theme/app_colors_test.dart
```

Expected: FAIL — `app_colors.dart` not found

- [ ] **Step 3: Write implementation**

Create `lib/core/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Design tokens for app colors. Matches DESIGN.md.
/// Do not use raw Color() values elsewhere — import from here.
@immutable
abstract final class AppColors {
  // --- Light Mode ---
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1A1A2E);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightAccent = Color(0xFF2563EB);
  static const Color lightAccentHover = Color(0xFF1D4ED8);
  static const Color lightSuccess = Color(0xFF16A34A);
  static const Color lightWarning = Color(0xFFEAB308);
  static const Color lightError = Color(0xFFDC2626);
  static const Color lightBorder = Color(0xFFE5E7EB);

  // --- Dark Mode ---
  static const Color darkBackground = Color(0xFF0F0F14);
  static const Color darkSurface = Color(0xFF1A1A2E);
  static const Color darkTextPrimary = Color(0xFFE4E4E7);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkAccent = Color(0xFF3B82F6);
  static const Color darkAccentHover = Color(0xFF2563EB);
  static const Color darkSuccess = Color(0xFF22C55E);
  static const Color darkWarning = Color(0xFFFACC15);
  static const Color darkError = Color(0xFFEF4444);
  static const Color darkBorder = Color(0xFF2D2D3A);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/theme/app_colors_test.dart
```

Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_colors.dart test/core/theme/app_colors_test.dart
git commit -m "feat: add color design tokens (light + dark mode)"
```

---

## Task 5: Theme System — Typography + AppTheme

**Files:**
- Create: `lib/core/theme/app_typography.dart`
- Create: `lib/core/theme/app_theme.dart`
- Test: `test/core/theme/app_theme_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme is a valid ThemeData', () {
      final theme = AppTheme.light;
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme is a valid ThemeData', () {
      final theme = AppTheme.dark;
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.dark);
    });

    test('light theme uses system font family', () {
      // Default font on all platforms, no custom font package
      expect(AppTheme.light.textTheme.bodyLarge?.fontSize, 14);
      expect(AppTheme.light.textTheme.headlineSmall?.fontSize, 20);
    });

    test('card border radius is 8px', () {
      final theme = AppTheme.light;
      final shape = theme.cardTheme.shape as RoundedRectangleBorder?;
      final borderRadius = shape?.borderRadius as BorderRadius?;
      expect(borderRadius?.topLeft.radius, 8);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/theme/app_theme_test.dart
```

Expected: FAIL — files not found

- [ ] **Step 3: Create typography tokens**

Create `lib/core/theme/app_typography.dart`:

```dart
import 'package:flutter/material.dart';

/// Typography design tokens. Matches DESIGN.md.
@immutable
abstract final class AppTypography {
  static const TextStyle headline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.5,
  );

  /// Build a TextTheme from our tokens for use in ThemeData.
  static TextTheme textTheme() {
    return TextTheme(
      headlineSmall: headline,
      titleMedium: title,
      bodyLarge: body,
      bodyMedium: body.copyWith(fontSize: 14),
      labelLarge: title,
      labelMedium: caption,
      labelSmall: overline,
      bodySmall: caption,
    );
  }
}
```

- [ ] **Step 4: Create AppTheme**

Create `lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:calendar_todo_app/core/theme/app_colors.dart';
import 'package:calendar_todo_app/core/theme/app_typography.dart';

/// App-wide theme configuration. Read DESIGN.md for design rationale.
@immutable
abstract final class AppTheme {
  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final bg = isLight ? AppColors.lightBackground : AppColors.darkBackground;
    final surface = isLight ? AppColors.lightSurface : AppColors.darkSurface;
    final textPrimary =
        isLight ? AppColors.lightTextPrimary : AppColors.darkTextPrimary;
    final textSecondary =
        isLight ? AppColors.lightTextSecondary : AppColors.darkTextSecondary;
    final accent = isLight ? AppColors.lightAccent : AppColors.darkAccent;
    final accentHover =
        isLight ? AppColors.lightAccentHover : AppColors.darkAccentHover;
    final border = isLight ? AppColors.lightBorder : AppColors.darkBorder;
    final error = isLight ? AppColors.lightError : AppColors.darkError;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      textTheme: AppTypography.textTheme().apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border, width: 1),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: TextStyle(color: textSecondary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/core/theme/app_theme_test.dart
```

Expected: All 4 tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/ test/core/theme/
git commit -m "feat: add typography tokens and AppTheme with light/dark mode"
```

---

## Task 6: App Constants

**Files:**
- Create: `lib/core/constants/app_constants.dart`

- [ ] **Step 1: Create constants file**

Create `lib/core/constants/app_constants.dart`:

```dart
/// App-wide constants.
abstract final class AppConstants {
  static const String appName = 'Calendar Todo';

  // Sync defaults
  static const Duration defaultSyncInterval = Duration(seconds: 30);
  static const Duration syncPollingInterval = Duration(seconds: 10);

  // UI spacing (base unit: 4px, matching DESIGN.md)
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 24;
  static const double spacingXxl = 32;

  // Border radius
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;

  // Animation
  static const Duration animationDuration = Duration(milliseconds: 200);
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/constants/app_constants.dart
git commit -m "feat: add app-wide constants (spacing, radius, sync intervals)"
```

---

## Task 7: Database Tables — Core (calendars, events, todos)

**Files:**
- Create: `lib/data/local/database/tables/calendars_table.dart`
- Create: `lib/data/local/database/tables/events_table.dart`
- Create: `lib/data/local/database/tables/todos_table.dart`
- Test: `test/data/local/database/tables/tables_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/local/database/tables/tables_test.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('CalendarsTable', () {
    test('insert and read a calendar', () async {
      final id = await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/calendars/user/main/',
              name: 'My Calendar',
              color: '#2563EB',
              timezone: 'Asia/Shanghai',
            ),
          );
      final calendar = await (db.select(db.calendars)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(calendar.name, 'My Calendar');
      expect(calendar.color, '#2563EB');
      expect(calendar.caldavHref, '/calendars/user/main/');
    });
  });

  group('EventsTable', () {
    test('insert and read an event', () async {
      // First create a calendar (FK dependency)
      final calId = await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
              color: '#000',
              timezone: 'UTC',
            ),
          );
      final eventId = await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'uid-123',
              summary: 'Team Meeting',
              startDt: DateTime(2026, 4, 17, 15, 0),
              endDt: DateTime(2026, 4, 17, 16, 0),
              isAllDay: false,
            ),
          );
      final event = await (db.select(db.events)
            ..where((t) => t.id.equals(eventId)))
          .getSingle();
      expect(event.summary, 'Team Meeting');
      expect(event.uid, 'uid-123');
      expect(event.isAllDay, false);
    });
  });

  group('TodosTable', () {
    test('insert and read a todo', () async {
      final calId = await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
              color: '#000',
              timezone: 'UTC',
            ),
          );
      final todoId = await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 'todo-456',
              summary: 'Buy groceries',
              priority: 1,
              status: 'NEEDS-ACTION',
            ),
          );
      final todo = await (db.select(db.todos)
            ..where((t) => t.id.equals(todoId)))
          .getSingle();
      expect(todo.summary, 'Buy groceries');
      expect(todo.priority, 1);
      expect(todo.status, 'NEEDS-ACTION');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/data/local/database/tables/tables_test.dart
```

Expected: FAIL — `app_database.dart` not found

- [ ] **Step 3: Create CalendarsTable**

Create `lib/data/local/database/tables/calendars_table.dart`:

```dart
import 'package:drift/drift.dart';

/// CalDAV calendar collection.
@DataClassName('Calendar')
class Calendars extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get caldavHref => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#2563EB'))();
  TextColumn get timezone => text().withDefault(const Constant('UTC'))();
  TextColumn get syncToken => text().nullable()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
```

- [ ] **Step 4: Create EventsTable**

Create `lib/data/local/database/tables/events_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Calendar events (VEVENT).
@DataClassName('Event')
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get calendarId => integer().references(Calendars, #id)();
  TextColumn get uid => text()();
  TextColumn get summary => text()();
  DateTimeColumn get startDt => dateTime()();
  DateTimeColumn get endDt => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get rrule => text().nullable()();
  TextColumn get etag => text().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

- [ ] **Step 5: Create TodosTable**

Create `lib/data/local/database/tables/todos_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Todo items (VTODO).
@DataClassName('Todo')
class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get calendarId => integer().references(Calendars, #id)();
  TextColumn get uid => text()();
  TextColumn get summary => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  IntColumn get priority =>
      integer().withDefault(const Constant(0))(); // 0=none, 1=high, 5=medium, 9=low
  TextColumn get status =>
      text().withDefault(const Constant('NEEDS-ACTION'))(); // NEEDS-ACTION | IN-PROCESS | COMPLETED | CANCELLED
  TextColumn get description => text().nullable()();
  TextColumn get rrule => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get percentComplete =>
      integer().withDefault(const Constant(0))();
  TextColumn get etag => text().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

- [ ] **Step 6: Create AppDatabase shell (for code generation)**

Create `lib/data/local/database/app_database.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/calendars_table.dart';
import 'tables/events_table.dart';
import 'tables/todos_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Calendars, Events, Todos])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For testing: pass an in-memory database.
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'calendar_todo.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

- [ ] **Step 7: Run code generation**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
dart run build_runner build --delete-conflicting-outputs
```

Expected: `app_database.g.dart` generated successfully

- [ ] **Step 8: Run tests**

```bash
flutter test test/data/local/database/tables/tables_test.dart
```

Expected: All 3 tests PASS (calendars, events, todos CRUD)

- [ ] **Step 9: Commit**

```bash
git add lib/data/local/database/ test/data/local/database/
git commit -m "feat: add Drift database with calendars, events, todos tables"
```

---

## Task 8: Database Tables — Supporting (tags, attachments, sync_queue, reminders)

**Files:**
- Create: `lib/data/local/database/tables/tags_table.dart`
- Create: `lib/data/local/database/tables/event_tags_table.dart`
- Create: `lib/data/local/database/tables/todo_tags_table.dart`
- Create: `lib/data/local/database/tables/attachments_table.dart`
- Create: `lib/data/local/database/tables/sync_queue_table.dart`
- Create: `lib/data/local/database/tables/reminders_table.dart`

- [ ] **Step 1: Create TagsTable**

Create `lib/data/local/database/tables/tags_table.dart`:

```dart
import 'package:drift/drift.dart';

/// User-defined tags/labels.
@DataClassName('Tag')
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get color => text().withDefault(const Constant('#6B7280'))();
}
```

- [ ] **Step 2: Create EventTagsTable (join table)**

Create `lib/data/local/database/tables/event_tags_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Many-to-many: events <-> tags.
@DataClassName('EventTag')
class EventTags extends Table {
  IntColumn get eventId => integer().references(Events, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {eventId, tagId};
}
```

- [ ] **Step 3: Create TodoTagsTable (join table)**

Create `lib/data/local/database/tables/todo_tags_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Many-to-many: todos <-> tags.
@DataClassName('TodoTag')
class TodoTags extends Table {
  IntColumn get todoId => integer().references(Todos, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {todoId, tagId};
}
```

- [ ] **Step 4: Create AttachmentsTable**

Create `lib/data/local/database/tables/attachments_table.dart`:

```dart
import 'package:drift/drift.dart';

/// File attachments for events or todos.
@DataClassName('Attachment')
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get parentType => text()(); // 'event' or 'todo'
  IntColumn get parentId => integer()();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  TextColumn get mimeType => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

- [ ] **Step 5: Create SyncQueueTable**

Create `lib/data/local/database/tables/sync_queue_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Pending sync operations for offline support.
@DataClassName('SyncQueueItem')
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get operation => text()(); // 'create', 'update', 'delete'
  TextColumn get resourceType => text()(); // 'event', 'todo', 'calendar'
  IntColumn get resourceId => integer()();
  TextColumn get payload => text().nullable()(); // JSON snapshot
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
}
```

- [ ] **Step 6: Create RemindersTable**

Create `lib/data/local/database/tables/reminders_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Alarms / reminders for events or todos.
@DataClassName('Reminder')
class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get parentType => text()(); // 'event' or 'todo'
  IntColumn get parentId => integer()();
  DateTimeColumn get triggerTime => dateTime()();
  BoolColumn get isTriggered =>
      boolean().withDefault(const Constant(false))();
}
```

- [ ] **Step 7: Update AppDatabase to include all tables**

Update `lib/data/local/database/app_database.dart` — add imports and table references:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/calendars_table.dart';
import 'tables/events_table.dart';
import 'tables/todos_table.dart';
import 'tables/tags_table.dart';
import 'tables/event_tags_table.dart';
import 'tables/todo_tags_table.dart';
import 'tables/attachments_table.dart';
import 'tables/sync_queue_table.dart';
import 'tables/reminders_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Calendars,
  Events,
  Todos,
  Tags,
  EventTags,
  TodoTags,
  Attachments,
  SyncQueue,
  Reminders,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'calendar_todo.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

- [ ] **Step 8: Regenerate code**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 9: Re-run existing tests to verify nothing broke**

```bash
flutter test test/data/local/database/tables/tables_test.dart
```

Expected: Still all PASS

- [ ] **Step 10: Commit**

```bash
git add lib/data/local/database/
git commit -m "feat: add supporting tables (tags, attachments, sync_queue, reminders)"
```

---

## Task 9: DAOs — CalendarsDao

**Files:**
- Create: `lib/data/local/database/daos/calendars_dao.dart`
- Test: `test/data/local/database/daos/calendars_dao_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/local/database/daos/calendars_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('CalendarsDao', () {
    test('watchAll returns stream of calendars', () async {
      await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/1',
              name: 'Work',
              color: '#2563EB',
              timezone: 'Asia/Shanghai',
            ),
          );
      await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/2',
              name: 'Personal',
              color: '#16A34A',
              timezone: 'UTC',
            ),
          );

      final calendars = await db.calendarsDao.watchAll().first;
      expect(calendars.length, 2);
      expect(calendars[0].name, 'Work');
      expect(calendars[1].name, 'Personal');
    });

    test('getById returns single calendar', () async {
      final id = await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/x',
              name: 'Test',
              color: '#000',
              timezone: 'UTC',
            ),
          );
      final cal = await db.calendarsDao.getById(id);
      expect(cal?.name, 'Test');
    });

    test('getById returns null for non-existent id', () async {
      final cal = await db.calendarsDao.getById(9999);
      expect(cal, isNull);
    });

    test('setActive toggles active status', () async {
      final id = await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
              color: '#000',
              timezone: 'UTC',
            ),
          );
      await db.calendarsDao.setActive(id, false);
      final cal = await db.calendarsDao.getById(id);
      expect(cal?.isActive, false);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/data/local/database/daos/calendars_dao_test.dart
```

Expected: FAIL — `calendarsDao` not found on AppDatabase

- [ ] **Step 3: Create CalendarsDao**

Create `lib/data/local/database/daos/calendars_dao.dart`:

```dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/calendars_table.dart';

part 'calendars_dao.g.dart';

/// Data access for calendars.
@DriftAccessor(tables: [Calendars])
class CalendarsDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarsDaoMixin {
  CalendarsDao(super.db);

  /// Watch all calendars as a reactive stream.
  Stream<List<Calendar>> watchAll() {
    return (select(calendars)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  /// Get a single calendar by id.
  Future<Calendar?> getById(int id) {
    return (select(calendars)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Set calendar active/inactive.
  Future<void> setActive(int id, bool active) {
    return (update(calendars)..where((t) => t.id.equals(id))).write(
      CalendarsCompanion(isActive: Value(active)),
    );
  }

  /// Upsert calendar from CalDAV sync.
  Future<void> upsert(Calendar entry) {
    return into(calendars).insertOnConflictUpdate(entry);
  }
}
```

- [ ] **Step 4: Register DAO in AppDatabase**

Update `lib/data/local/database/app_database.dart` — add DAO import and accessor:

```dart
// Add to imports:
import 'daos/calendars_dao.dart';

// Add inside AppDatabase class, after schemaVersion getter:
  // DAOs
  CalendarsDao get calendarsDao => CalendarsDao(this);
```

And update `@DriftDatabase` annotation to include the DAO:

```dart
@DriftDatabase(
  tables: [
    Calendars, Events, Todos, Tags, EventTags, TodoTags,
    Attachments, SyncQueue, Reminders,
  ],
  daos: [CalendarsDao],
)
```

- [ ] **Step 5: Regenerate and run tests**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
dart run build_runner build --delete-conflicting-outputs
flutter test test/data/local/database/daos/calendars_dao_test.dart
```

Expected: All 4 tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/data/local/database/ test/data/local/database/daos/
git commit -m "feat: add CalendarsDao with watchAll, getById, setActive, upsert"
```

---

## Task 10: DAOs — EventsDao + TodosDao

**Files:**
- Create: `lib/data/local/database/daos/events_dao.dart`
- Create: `lib/data/local/database/daos/todos_dao.dart`
- Test: `test/data/local/database/daos/events_dao_test.dart`
- Test: `test/data/local/database/daos/todos_dao_test.dart`

- [ ] **Step 1: Write failing tests for EventsDao**

Create `test/data/local/database/daos/events_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int calId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            caldavHref: '/cal/',
            name: 'Test',
            color: '#000',
            timezone: 'UTC',
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('EventsDao', () {
    test('watchByDateRange returns events in range', () async {
      await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e1',
              summary: 'Meeting',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
              isAllDay: false,
            ),
          );
      // Outside range — should not appear
      await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e2',
              summary: 'Other',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 1, 1),
              isAllDay: false,
            ),
          );

      final events = await db.eventsDao
          .watchByDateRange(
            DateTime(2026, 4, 1),
            DateTime(2026, 4, 30),
          )
          .first;
      expect(events.length, 1);
      expect(events.first.summary, 'Meeting');
    });

    test('markDirty sets isDirty flag', () async {
      final eventId = await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e3',
              summary: 'Test',
              startDt: DateTime(2026, 1, 1),
              endDt: DateTime(2026, 1, 1, 1),
              isAllDay: false,
            ),
          );
      await db.eventsDao.markDirty(eventId);
      final event = await (db.select(db.events)
            ..where((t) => t.id.equals(eventId)))
          .getSingle();
      expect(event.isDirty, true);
    });
  });
}
```

- [ ] **Step 2: Write failing tests for TodosDao**

Create `test/data/local/database/daos/todos_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int calId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            caldavHref: '/cal/',
            name: 'Test',
            color: '#000',
            timezone: 'UTC',
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('TodosDao', () {
    test('watchPending returns only non-completed todos', () async {
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't1',
              summary: 'Pending task',
              priority: 1,
              status: 'NEEDS-ACTION',
            ),
          );
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't2',
              summary: 'Done task',
              priority: 5,
              status: 'COMPLETED',
            ),
          );

      final todos = await db.todosDao.watchPending().first;
      expect(todos.length, 1);
      expect(todos.first.summary, 'Pending task');
    });

    test('markComplete sets status and completedAt', () async {
      final todoId = await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't3',
              summary: 'To complete',
              priority: 5,
              status: 'NEEDS-ACTION',
            ),
          );
      await db.todosDao.markComplete(todoId);
      final todo = await (db.select(db.todos)
            ..where((t) => t.id.equals(todoId)))
          .getSingle();
      expect(todo.status, 'COMPLETED');
      expect(todo.completedAt, isNotNull);
    });

    test('watchByDueDate returns todos due on specific date', () async {
      final dueDate = DateTime(2026, 4, 20);
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't4',
              summary: 'Due today',
              priority: 5,
              status: 'NEEDS-ACTION',
              dueDate: Value(dueDate),
            ),
          );

      final todos = await db.todosDao
          .watchByDueDate(DateTime(2026, 4, 20))
          .first;
      expect(todos.length, 1);
      expect(todos.first.summary, 'Due today');
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
flutter test test/data/local/database/daos/
```

Expected: FAIL — DAOs not found

- [ ] **Step 4: Create EventsDao**

Create `lib/data/local/database/daos/events_dao.dart`:

```dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/events_table.dart';

part 'events_dao.g.dart';

/// Data access for events.
@DriftAccessor(tables: [Events])
class EventsDao extends DatabaseAccessor<AppDatabase>
    with _$EventsDaoMixin {
  EventsDao(super.db);

  /// Watch events whose start time falls within [start, end].
  Stream<List<Event>> watchByDateRange(DateTime start, DateTime end) {
    return (select(events)
          ..where((t) =>
              t.startDt.isBiggerOrEqualValue(start) &
              t.startDt.isSmallerOrEqualValue(end))
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)]))
        .watch();
  }

  /// Mark an event as needing sync.
  Future<void> markDirty(int id) {
    return (update(events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(
        isDirty: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Upsert event from CalDAV sync.
  Future<void> upsert(Event entry) {
    return into(events).insertOnConflictUpdate(entry);
  }

  /// Get events by calendar.
  Stream<List<Event>> watchByCalendar(int calendarId) {
    return (select(events)..where((t) => t.calendarId.equals(calendarId)))
        .watch();
  }
}
```

- [ ] **Step 5: Create TodosDao**

Create `lib/data/local/database/daos/todos_dao.dart`:

```dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/todos_table.dart';

part 'todos_dao.g.dart';

/// Data access for todos.
@DriftAccessor(tables: [Todos])
class TodosDao extends DatabaseAccessor<AppDatabase>
    with _$TodosDaoMixin {
  TodosDao(super.db);

  /// Watch all non-completed todos.
  Stream<List<Todo>> watchPending() {
    return (select(todos)
          ..where((t) => t.status.isNotIn(const ['COMPLETED', 'CANCELLED']))
          ..orderBy([
            (t) => OrderingTerm.asc(t.priority),
            (t) => OrderingTerm.asc(t.dueDate),
          ]))
        .watch();
  }

  /// Mark a todo as completed.
  Future<void> markComplete(int id) {
    return (update(todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(
        status: const Value('COMPLETED'),
        completedAt: Value(DateTime.now()),
        percentComplete: const Value(100),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Watch todos due on a specific date.
  Stream<List<Todo>> watchByDueDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(todos)
          ..where((t) =>
              t.dueDate.isBiggerOrEqualValue(startOfDay) &
              t.dueDate.isSmallerThanValue(endOfDay)))
        .watch();
  }

  /// Upsert todo from CalDAV sync.
  Future<void> upsert(Todo entry) {
    return into(todos).insertOnConflictUpdate(entry);
  }
}
```

- [ ] **Step 6: Register DAOs in AppDatabase**

Update `lib/data/local/database/app_database.dart`:

```dart
// Add imports:
import 'daos/calendars_dao.dart';
import 'daos/events_dao.dart';
import 'daos/todos_dao.dart';

// Update @DriftDatabase:
@DriftDatabase(
  tables: [
    Calendars, Events, Todos, Tags, EventTags, TodoTags,
    Attachments, SyncQueue, Reminders,
  ],
  daos: [CalendarsDao, EventsDao, TodosDao],
)

// Add inside AppDatabase class:
  // DAOs
  CalendarsDao get calendarsDao => CalendarsDao(this);
  EventsDao get eventsDao => EventsDao(this);
  TodosDao get todosDao => TodosDao(this);
```

- [ ] **Step 7: Regenerate and run all DAO tests**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
dart run build_runner build --delete-conflicting-outputs
flutter test test/data/local/database/daos/
```

Expected: All 7 tests PASS (4 calendars + 2 events + 3 todos)

- [ ] **Step 8: Commit**

```bash
git add lib/data/local/database/ test/data/local/database/daos/
git commit -m "feat: add EventsDao and TodosDao with query methods"
```

---

## Task 11: Router Setup

**Files:**
- Create: `lib/core/router/app_router.dart`

- [ ] **Step 1: Create router configuration**

Create `lib/core/router/app_router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/ui/pages/home/home_page.dart';
import 'package:calendar_todo_app/ui/pages/settings/settings_page.dart';

/// App-wide router configuration using go_router.
abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );

  /// Convenience method for navigation without context.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat: add go_router configuration with home and settings routes"
```

---

## Task 12: Home Page Shell + Settings Page Shell

**Files:**
- Create: `lib/ui/pages/home/home_page.dart`
- Create: `lib/ui/pages/settings/settings_page.dart`

- [ ] **Step 1: Create Home Page**

Create `lib/ui/pages/home/home_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Main page — calendar + todo entry point.
/// Will be populated with actual views in Phase 2.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar Todo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 64),
            SizedBox(height: 16),
            Text('Calendar & Todo', style: TextStyle(fontSize: 20)),
            SizedBox(height: 8),
            Text(
              'Phase 1 skeleton — UI coming next',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create Settings Page**

Create `lib/ui/pages/settings/settings_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Settings page shell — will be populated in later phases.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('CalDAV Accounts'),
            subtitle: Text('Not yet implemented — Phase 3'),
          ),
          ListTile(
            leading: Icon(Icons.smart_toy_outlined),
            title: Text('AI Configuration'),
            subtitle: Text('Not yet implemented — Phase 6'),
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Theme and display options'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('Calendar Todo v0.1.0'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/ui/
git commit -m "feat: add HomePage and SettingsPage shells"
```

---

## Task 13: Main Entry Point + Verification

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace default main.dart**

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CalendarTodoApp()));
}

class CalendarTodoApp extends ConsumerWidget {
  const CalendarTodoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Calendar Todo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }
}
```

- [ ] **Step 2: Run all tests**

```bash
cd "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app"
flutter test
```

Expected: All tests PASS

- [ ] **Step 3: Verify web build**

```bash
flutter build web --release
```

Expected: Build succeeds, output in `build/web/`

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: wire up main.dart with theme, router, and Riverpod"
```

---

## Task 14: Test Helper — Shared In-Memory Database

**Files:**
- Create: `test/helpers/test_database.dart`

- [ ] **Step 1: Create shared test database helper**

Create `test/helpers/test_database.dart`:

```dart
import 'package:drift/native.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

/// Creates an in-memory AppDatabase for use in tests.
/// Automatically closes after each test via [tearDown].
AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}
```

This helper will be used by all future DAO and integration tests to avoid duplication.

- [ ] **Step 2: Commit**

```bash
git add test/helpers/
git commit -m "test: add shared in-memory database helper for tests"
```

---

## Self-Review

### 1. Spec Coverage Check

| Spec Requirement | Task |
|-----------------|------|
| Flutter project init, all 6 platforms | Task 1 |
| Clean Architecture directory structure | Task 1 |
| Drift database schema + migration | Tasks 7, 8 |
| Basic theme system (light + dark) | Tasks 4, 5 |
| go_router routing framework | Task 11 |
| DESIGN.md design spec | Task 2 |
| All core tables (calendars, events, todos, tags, attachments, sync_queue, reminders) | Tasks 7, 8 |
| DAOs with CRUD + reactive streams | Tasks 9, 10 |
| Home page + Settings page shells | Task 12 |
| Main entry point wiring | Task 13 |
| Secure storage stub | (directory created, implementation deferred to Phase 3) |
| NOTICE file for license compliance | Task 2 |
| Test helpers for future tests | Task 14 |

### 2. Placeholder Scan

No TBD, TODO, or placeholder patterns found. All steps contain complete code.

### 3. Type Consistency

- `CalendarsCompanion.insert()` used consistently in all test files — matches Drift-generated API
- `EventsCompanion.insert()` requires `calendarId`, `uid`, `summary`, `startDt`, `endDt`, `isAllDay` — all provided
- `TodosCompanion.insert()` requires `calendarId`, `uid`, `summary`, `priority`, `status` — all provided
- DAO method names (`watchAll`, `getById`, `setActive`, `markDirty`, `markComplete`, `watchByDateRange`, `watchPending`, `watchByDueDate`) used consistently between DAO definitions and test files
- `Value()` wrapper from `drift` used correctly for nullable/optional fields

---

## Notes

- **Secure storage** (`credential_storage.dart`) is deferred to Phase 3 (CalDAV Sync) since it's only needed when connecting to servers
- **Domain layer** is intentionally empty — it will be populated in Phase 2-3 with sync services and business logic
- **Web platform** is immediately testable; iOS/Android/macOS need Xcode/Android Studio installed separately
- All code generation uses `build_runner` — must be re-run after any table/DAO change
