# 用户可见文案出口清单 / User-visible text outlets

> **为什么要有这个文件**：i18n 返工的第三大来源是**字典之外的出口**——通知、桌面小组件、服务端错误、AI 输出。它们不走 UI 组件，任何"检查界面文案"的守卫都看不见它们。一份显式清单让"漏了一个出口"变成一个能被问出来的问题，而不是等用户投诉。
>
> **规矩**：新增一个会出现用户可见文字的地方，必须同时 ①登记进本表 ②被冒烟覆盖。**不在表上的出口，视为未接线。**

最后更新：2026-10-05（Recurring Todo lazy confirmation）

---

## 出口表

| # | 出口 | 文案来源 | 语言取自 | 语言切换时如何刷新 | 覆盖手段 |
|---|---|---|---|---|---|
| 1 | 应用内 UI | `AppLocalizations`（经 `AppStr` 之外的直接 `l.xxx`；含 Todo 安排/编辑时的 legacy recurrence 确认、来源证据、occurrence 预览与错误提示） | `MaterialApp.locale` ← `localeProvider` | 重建即生效 | `test/architecture/no_raw_text_guard_test.dart`（裸文案）+ `l10n_parity_guard_test.dart`（键对齐）+ `test/ui/widgets/todo/task_allocations_section_test.dart` |
| 2 | 本地通知（提醒） | `loadNotificationStrings()` | `resolveNotificationLocale()`：持久化 prefs → 系统 | **`ReminderReconciler.onLocaleChanged()`**：清掉已交给 OS 的 `_applied` 条目 → `_reconcileAll(force: true)` 重排 | `test/domain/records/reminder_reconciler_test.dart` 测试 18 |
| 3 | 桌面 / 锁屏小组件 | `WidgetUiStrings` 快照（预本地化后交给原生） | 同上 | `home_page.dart` 监听 `localeProvider` → `_refreshHomeWidget()` | `test/infrastructure/home_widget_interactivity_test.dart` + `home_widget_refresh_triggers_test.dart` |
| 4 | 通知动作按钮 / 渠道名 | 原生资源（Android `strings.xml` / iOS） | 系统语言，**不随 App 内切换** | 不适用（系统级，切换需改系统语言） | ⚠️ 未覆盖——见下方"已知缺口" |
| 5 | 服务端错误 | 结构化 `{"error":{"code","message"}}`，前端按 code 查表 | 不适用（返回的是 code） | 不适用 | `_mapApiError` 走枚举 → `_errorText` 走 l10n |
| 6 | MCP / CLI 输出 | 服务端工具描述与错误（面向 AI，非终端用户） | 不适用 | 不适用 | 不纳入本清单（读者是 AI agent） |
| 7 | AI 生成文本 | 模型输出 | `languageNameFor(resolveAppLocale())` 显式透传进 prompt | 不适用（每次请求现生成，天然跟随当前语言） | `ai_provider_test.dart` 断言 prompt 真含语言约束 |
| 8 | 导出（ICS） | 文件名 / 日历名 | — | — | 内容为数据（SUMMARY 是用户数据，不翻译） |
| 9 | 权限弹窗 / 应用名 / 应用商店文案 | 原生资源 + 商店后台 | 系统语言 | 不适用 | ⚠️ 未覆盖 |

---

## 已知缺口

1. **通知渠道名与动作按钮**（#4）走 Android/iOS 原生资源，不随 App 内语言切换。当前只有一份。要支持双语需按语言各出一份原生资源；且 Android 通知渠道创建后**不可改名**，改语言需要新建渠道 id。
2. ~~**AI 输出语言**（#7）靠启发式~~ ✅ 2026-10-01 已修：`buildChatSystemPrompt` 改为硬约束 `Respond strictly in {appLanguage}`；`buildParseSystemPrompt` 透传语言并**明确要求不要翻译用户写的 summary**（标题是用户自己的话）。两个 prompt 抽成纯函数，由 `ai_provider_test.dart` 断言语言约束真的进了 prompt——否则只是"接了线"而不是"证明接了线"。
   - **代价披露**：硬约束意味着 App 语言为英文时，即使用户用中文提问，AI 也用英文回答。这是 L-12 的要求，但双语用户可能觉得别扭；若要改回"跟随提问语言"，改 `buildChatSystemPrompt` 一处即可。
3. **#1 的覆盖是"事后扫描"而非"事前拦截"**：`no_raw_text_guard_test.dart` 能拦住新写的裸中文，但拦不住"该加的 key 没加"——那个由键对齐门禁在补了 key 之后才生效。
4. **Recurring Todo 确认页预览**：widget 测试现已覆盖预览成功后才可保存；2037 horizon/结果上限错误分支仍需单独行为测试。

---

## 维护

- 新增出口 → 加一行 + 接上刷新路径 + 补覆盖手段，三件事同一次提交完成。
- 某行"覆盖手段"为空 → 要么补上，要么在"已知缺口"里写明为什么暂时不做。
