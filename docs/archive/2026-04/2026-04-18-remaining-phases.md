# Remaining Implementation Plan
> ⚠️ **已过时（2026-09-27 标注，正文原样保留仅供考古）**：本文是 2026-04 项目早期的方案讨论，CalDAV 路线已被自研同步后端替代（v0.22.0 落地），内容不再维护。现行状态唯一源：`calendar_todo_app/docs/START_HERE.md`（接续入口）、`calendar_todo_app/docs/ROADMAP.md`（功能全景）。

**Goal:** 完成 Phase 5-7 所有剩余功能，从高级功能到 AI 集成到发布准备。

**Architecture:** 继续沿用 Clean Architecture 三层分离。AI 集成通过 Dio 调用 Claude/OpenAI API，流式输出用 SSE。桌面小组件用 home_screen_widget (Android) + WidgetKit (iOS)。ics 导入导出复用 enough_icalendar。

**Tech Stack:** Dio (AI API) / enough_icalendar (ics) / flutter_local_notifications (alarm) / home_screen_widget / WidgetKit

---

## Task 1: Sync Queue 离线模式
- 同步服务写入 sync_queue 表，离线时队列堆积，联网后批量执行
- 修改 sync_service.dart 中 pushDirty 逻辑，失败时写 sync_queue
- 文件: `lib/data/remote/caldav/sync_service.dart`, `lib/data/local/database/daos/sync_queue_dao.dart`

## Task 2: .ics 文件导入/导出
- 导出: 选中日历 → 生成 .ics 文件 → 保存到文件系统
- 导入: 选 .ics 文件 → 解析 VEVENT/VTODO → 写入数据库
- 文件: `lib/domain/services/ics_service.dart`, 导入导出 UI 入口

## Task 3: 附件管理
- 附件表已有，创建附件选择/上传 UI
- 支持图片和文件附件
- 文件: `lib/domain/providers/attachments_provider.dart`, 附件 UI 组件

## Task 4: 键盘快捷键 (桌面端)
- 常用快捷键: Ctrl+N 新建, Ctrl+S 保存, Ctrl+F 搜索, Esc 返回
- 文件: `lib/ui/widgets/keyboard_shortcuts.dart`

## Task 5: AI API 配置
- 设置页 AI 配置区域: API Key, Base URL, 模型选择
- 用 flutter_secure_storage 存储 API Key
- 文件: `lib/domain/providers/ai_provider.dart`

## Task 6: 自然语言输入
- 在事件/待办创建页添加 AI 解析按钮
- 输入自然语言文本 → AI 返回结构化数据 → 填充表单
- 文件: `lib/domain/services/ai_parser_service.dart`

## Task 7: AI 聊天界面
- 内置聊天页面，流式对话
- AI 可查询日历和待办数据
- 文件: `lib/ui/pages/ai_chat/ai_chat_page.dart`, 路由注册

## Task 8: AI 自动排程
- 分析待办列表，推荐时间安排
- 一键将待办排入日历空闲时段
- 文件: `lib/domain/services/ai_scheduler_service.dart`

## Task 9: 多语言支持 (i18n)
- 中文和英文
- 用 Flutter 内置 ARB 方案
- 文件: `l10n.yaml`, `lib/l10n/`

## Task 10: 全平台构建验证
- Web: flutter build web
- macOS: 构建配置
- Android: 构建配置
- 更新 README 和使用文档

## Task 11: 完整测试 + 修复
- 为所有新功能写单元测试
- 运行全量测试套件
- 修复所有 analyze 警告

## Task 12: 最终验证
- flutter analyze 0 error
- 全部测试通过
- Web 构建成功
