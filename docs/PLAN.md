# 项目状态总览

最后更新: 2026-04-19

---

## 项目规模

| 指标 | 数量 |
|------|------|
| 源代码文件 (lib/) | ~62 |
| 测试文件 (test/) | 25 |
| 测试用例 | 86 (全部通过) |
| 分析问题 | 0 error, 0 warning, 19 info |
| i18n 字符串 | 97 个 key (en + zh) |
| flutter doctor | ✅ 全绿 |

---

## ✅ 已构建的平台（4/6）

| 平台 | 构建产物 | 状态 |
|------|----------|------|
| Web | `build/web/` ~7MB | ✅ |
| macOS | `calendar_todo_app.app` 138MB | ✅ |
| Android | `app-debug.apk` 159MB | ✅ |
| iOS | `Runner.app` (模拟器) | ✅ |
| Windows | — | ⏳ 需 Windows 主机 |
| Linux | — | ⏳ 需 WSL 或 Linux |

---

## ✅ 已完成的功能

| 功能 | Phase |
|------|-------|
| 项目基础架构、数据库、路由、主题 | Phase 1 ✅ |
| 日历日/周/月视图 + 事件 CRUD + RRULE | Phase 2 ✅ |
| 待办 CRUD + 优先级 + RRULE + 完成追踪 | Phase 2 ✅ |
| 搜索（事件+待办） | Phase 2 ✅ |
| CalDAV 全量双向同步 | Phase 3 ✅ |
| CalDAV 增量同步（sync-token） | Phase 3 ✅ |
| CalDAV 账户配置 + 凭证安全存储 | Phase 3 ✅ |
| 离线同步队列（自动消费） | Phase 3 ✅ |
| 通知提醒（flutter_local_notifications） | Phase 4 ✅ |
| 标签系统（CRUD + 多对多） | Phase 5 ✅ |
| ICS 导出 | Phase 5 ✅ |
| ICS 导入（file_picker） | Phase 5 ✅ |
| 附件支持（上传/显示/删除） | Phase 5 ✅ |
| AI 配置（OpenAI 兼容） | Phase 6 ✅ |
| AI 自然语言解析 | Phase 6 ✅ |
| AI 聊天 + 创建事件/待办 | Phase 6 ✅ |
| AI 自动排程（时间建议 + 任务分解） | Phase 6 ✅ |
| i18n（中英 97 key） | Phase 7 ✅ |
| kalender 升级到 v0.17.0 | 维护 ✅ |
| 代码冗余清理（39 个问题修复） | 维护 ✅ |
| 全平台环境配置（Xcode/Android/JDK） | 运维 ✅ |

---

## ❌ 未完成的功能

### 高优先级（用户明确要求）

| 功能 | Phase | 说明 |
|------|-------|------|
| 背景定时同步（前台30s + 后台15min） | 3 | 需 workmanager |
| 系统闹钟提醒 | 4 | alarm + flutter_alarmkit |
| Android 桌面小组件 | 4 | home_widget |
| iOS 桌面小组件（WidgetKit） | 4 | home_widget |
| macOS 桌面小组件 | 4 | 原生 Swift WidgetKit |
| 渐进式披露设置 | 5 | 高级功能在设置中开关 |
| MCP Server（AI Agent 接入） | 6 | mcp_sdk 内嵌方案 |
| 拖拽事件 | 2 | kalender 已支持 |
| 多 CalDAV 账户同时连接 | 3 | 需改数据模型 |

### UI/UX 打磨

| 功能 | 说明 |
|------|------|
| 动画仅用于状态切换（0.2s ease） | 统一动画规范 |
| 最小阴影，用边框表达层级 | 视觉规范 |
| 最小触摸目标 48x48dp | 可访问性 |
| 色彩对比度 WCAG 2.1 AA | 可访问性 |
| 日期/时间格式跟随系统 Locale | i18n 完善 |

### 安全

| 功能 | 说明 |
|------|------|
| 强制 HTTPS | 网络安全 |
| AI API Key 掩码显示 | 凭证保护 |
| 生物识别锁（Face ID / Touch ID） | 应用锁 |

### 数据库

| 功能 | 说明 |
|------|------|
| 数据库迁移支持 | 版本升级 |
| 数据库导出为 .db 文件 | 备份 |

### 开源与发布

| 功能 | 说明 |
|------|------|
| GPLv3 许可证 | 开源协议 |
| NOTICE 文件 | 第三方版权 |
| 自动生成许可证页面 | flutter_oss_licenses |
| GitHub 开源发布 | 仓库 + README |
| GitHub Actions CI/CD | 自动化构建测试 |
| 各平台发布包 | APK / .app / Web 部署 |
| 用户文档和自部署指南 | 含 Radicale |

### 鸿蒙（第二批）

| 功能 | 说明 |
|------|------|
| Flutter-OH 环境搭建 | 等生态成熟 |
| 鸿蒙平台适配 | — |
| 华为应用市场 | — |

---

## 执行计划

### Step 1：清理冗余代码 ✅ 已完成
1.1 ✅ 删除死代码（未使用 DAO 方法、service 方法）
1.2 ✅ 提取 `_formatTime` / `_mapTodoStatus` / `_parseColor` 到 `core/utils/`
1.3 ✅ 修复 `if(true)`、`importIcs` 循环 bug
1.4 ✅ 优化 DAO getter 为 `late final`、缓存 `DateTimeRange`、`_tileComponents`
1.5 ✅ 测试 + analyze 确认无回归

### Step 2：接线已有代码 ✅ 已完成
2.1 ✅ 增量同步（sync-token + fallback to full sync）
2.2 ✅ 离线同步队列（incremental sync 后自动消费）
2.3 ✅ ICS 导入（file_picker + importIcs）
2.4 ✅ 附件 UI（AttachmentList 组件 + 事件/待办编辑页集成）
2.5 ✅ AI 自动排程（时间建议 + 任务分解，AI 聊天页快捷按钮）
2.6 ✅ kalender 升级到 v0.17.0

### Step 3：新功能（进行中）
3.1 背景定时同步（前台 Timer 30s + workmanager 15min 后台）
3.2 系统闹钟提醒（alarm + flutter_alarmkit iOS 26+）
3.3 Android 桌面小组件（home_widget）
3.4 iOS 桌面小组件（home_widget + WidgetKit）
3.5 macOS 桌面小组件（原生 Swift）
3.6 渐进式披露设置
3.7 MCP Server（mcp_sdk 内嵌）
3.8 拖拽事件
3.9 多 CalDAV 账户

### Step 4：UI 打磨 + 发布
4.1 全平台 UI 适配（在 macOS/Web/Android 上逐页检查）
4.2 动画/阴影/触摸目标/对比度统一
4.3 日期格式跟随系统 Locale
4.4 安全加固（HTTPS、Key 掩码、生物识别）
4.5 数据库迁移 + .db 导出
4.6 GitHub Actions CI/CD
4.7 GPLv3 + NOTICE + 开源许可证页
4.8 用户文档 + Radicale 部署指南
4.9 各平台发布包
4.10 GitHub 开源发布

### Step 5：鸿蒙（第二批）
5.1 Flutter-OH 或 ArkTS 调研
5.2 鸿蒙适配
5.3 华为应用市场

---

## 验证方式

每个 Step 完成后：
```bash
flutter analyze   # 0 error, 0 warning
flutter test      # 全部通过
flutter build web --release
flutter build apk --debug
flutter build macos --debug
flutter build ios --simulator --debug
```

### 当前验证结果 ✅
```
flutter analyze: 0 error, 0 warning (19 info)
flutter test: 86/86 passed
4 平台构建成功 (Web, macOS, Android, iOS)
```
