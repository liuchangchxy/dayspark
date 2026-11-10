# 测试证据报告 / Test Evidence Report — v0.31.0 OpenDesign 表现层重写

## 范围

- 变更 / 需求：按 `design/opendesign/full-product-v030-v2/` 原型重写 Presentation（保留 Domain / Drift / 业务语义）
- 代码版本：分支 `feat/v030-opendesign-full-implementation`（基于 `main` @ `5f48ad5`），版本 `0.31.0+31`
- 环境：Windows 11 Pro 26200；Flutter SDK `C:\src\flutter`；Chrome（agent-browser 0.31.1）；本地 `python -m http.server` 服务 `build/web`

## 分层结果

| 层级 | 命令 | pass | fail | skipped | 未运行原因 |
|---|---|---:|---:|---:|---|
| 静态分析 | `dart analyze .` | 全仓 0 issue | 0 | 0 | — |
| 单元 / 领域 / Widget / UI（全套） | `flutter test` | 719 | 0 | 0 | — |
| 版本一致性守卫 | `tool/check_version_consistency.sh` | 9 marker | 0 | 0 | — |
| Web 生产构建 | `flutter build web --release` | 成功 | 0 | 0 | — |
| Windows release 构建 | `flutter build windows --release` | 成功 | 0 | 0 | — |
| Windows 启动冒烟 | 启动 `calendar_todo_app.exe`，8 秒后进程仍在运行 | 通过 | 0 | 0 | 仅验证启动到可运行状态，未做 GUI 目视验收（由用户完成） |
| 浏览器视觉 QA | agent-browser 截图对比 prototype | 见下表 | 0 | 0 | — |
| 原生交互 flow（`integration_test/app_test.dart`） | `flutter test --no-pub integration_test/app_test.dart -d windows` | 3 | 0 | 0 | 本机实跑 Windows 桌面原生壳；macOS 由 CI `build-macos` job 跑同一条命令 |

## 浏览器视觉 QA 覆盖（Flutter Web release 产物）

| 视口 | 页面 | 结论 |
|---|---|---|
| 360×800 | 待办（按日期）、日历管理 | 工具栏折行正常，无溢出 |
| 390×844 | 今天、待办（未安排/全部/按日期）、日历（日/周/月）、快速新建、待办详情、设置（亮/暗）、日历管理、标签管理 | 结构、层级、字阶、间距、配色、密度与原型一致，无溢出 |
| 412×915 | 待办、标签管理 | 同上 |
| 900×800 | 日历管理（折叠图标栏） | 64px 图标栏 + 内容区正常 |
| 1200×900 | 今天（含右侧未安排面）、待办（列表 + 详情面）、日历（周视图） | 主区 + 详情面分栏正常 |
| 1440×900 | 今天、待办（master-detail）、日历（周/月）、搜索、设置（通用 / 日历与标签）、日历管理、标签管理、回收站 | 与 desktop.html 原型一致 |

## 结论

- 最高实际验证层级：浏览器真实渲染（Flutter Web release）+ Windows release 构建与启动冒烟 + Windows 原生交互 flow（3/3）+ 全套自动化测试
- 是否存在未披露的失败或跳过：无失败；macOS 原生交互未在本机运行（本机无 macOS），由 CI `build-macos` 执行同一 integration_test
- 可声明的范围：表现层重写在 Web/桌面宽窄断点下结构正确；业务层（Domain / Drift / Sync / AI / ICS / 备份）语义未改动且全套测试通过
- **不能**声明的范围：Windows 桌面 App 的目视验收（未使用可见桌面 Computer Use，仅验证进程启动）；Android 真机小组件目视验收（仅完成布局/色板代码与构建）
