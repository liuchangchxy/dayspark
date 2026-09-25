# START HERE — DaySpark 接续工作唯一入口

> **给 AI 的指令**：当用户说"看看从哪里开始 / 继续项目"时，先读完本文档，再按「优先队列」行动。本文档是**未做事项的唯一清单索引**；状态类信息一律引用专业文档，不在此重复（防漂移）。

**最后更新：2026-09-24 · 当前版本以 `pubspec.yaml` 为准（全景见 `docs/ROADMAP.md`，发布记录见 https://github.com/liuchangchxy/dayspark/releases ）**

---

## 1. 我们在哪（一句话）

四阶段主计划 **P1 地基 → P2 同步后端 → P3 MCP/CLI → P4 平台+UX 全部完成**；**债务2 统一事件缝已交付**（v0.25.0+25，五平台构建全绿）。六套测试全绿（app 316 / server 195 / contracts 37 / wrapper 9 / CLI 20 / Kotlin 7）。每任务经独立审查+终审，过程裁定见各 DECISIONS 条目与 `docs/superpowers/plans/2026-09-24-d2-event-seam.md` 收尾记录。

## 2. 下一步优先队列（按序）

| # | 事项 | 一句话说明 | 详情来源 |
|---|------|-----------|---------|
| 1 | ~~**债务2：统一事件缝**~~ ✅ 2026-09-24 | 派生态失效已收敛为 post-commit 领域事件（`record-applied`/`record-removed`）：三条临时通道 → 一条缝；远端改期重挂本机提醒（关 P2.5#1）、远端删除撤销已排队通知（幽灵响铃）、事件回收站恢复重挂；守卫 + 棘轮基线（已收敛为空）落地。文档与版本 0.25.0+25 已同步 | 已实现 / `docs/ROADMAP.md` v0.25.0 + `docs/CONSTRAINTS.md` 架构章节 |
| 2 | **前端设计走查** | 输入物已就绪：`docs/design-token-gap.md`（DESIGN.md 令牌 vs 代码逐条差距 + kalender 专项）。流程：按五维度清单（间距节奏/字阶/视觉层级/主题一致[驯化 kalender]/状态设计）逐条产出“具体哪+为什么+怎么改”的选择题 → 用户勾选 → 批量执行。设计语言权威 = `DESIGN.md` | §5 |
| 3 | ~~**MCP 换官方 SDK**~~ ✅ 2026-09-24 | spike 实测**不能承载** → 手写版转正。0.5.2 服务端 Streamable HTTP 未发版；main 只认 2026-07-28（该修订已删 initialize/session）；无 shelf 适配；无 OAuth AS。测试兜底精确边界：壳测试 16 例随壳重写 / 行为守卫 = 工具 47 + CLI 13 + e2e 5 / OAuth 54 应原地绿 | DECISIONS [2026-09-24] MCP 转正手写版 |
| 4 | ~~**CI 防漂移 grep**~~ ✅ 2026-09-24 | 版本号散布四处靠人同步 → 已落 `tool/check_version_consistency.sh`：ci.yml `test` 首步（含 `--selftest`）+ release.yml `version-gate`（tag 必须 = `v<pubspec semver>`）。README 徽章已改 shields.io 动态徽章（读 GitHub Releases，无手同步点），本文件也不再复制当前版本 | 已实现 / `tool/check_version_consistency.sh` |
| 5 | **债务1：载荷 schema 版本化** | 同一实体三份表示（Drift/payload/contracts）；payload 加 schemaVersion + 字段清单进 contracts | §4 |
| 6 | **债务4：应用内限流** | DCR/登录限流目前只靠 DEPLOY.md 的 nginx，裸部署裸奔；加令牌桶中间件 | §4 |
| 7 | **P5 主菜：后台同步 + 设备注册** | 同步目前前台协作式（App 关闭收不到远端变更）；devices 表/deviceId 半出生从未写入 | §4 + ROADMAP |
| 8 | 用户决策项：TestFlight time-sensitive keep/remove（上架前）；~~v下一版 release notes 补 iOS15/macOS12 地板抬升~~ ✅ 2026-09-25（v0.25.0 release notes 已写明「最低系统要求 iOS 17+ / macOS 12+」） | 见 ROADMAP P4 follow-ups + docs/qa/p4-manual-qa.md | ROADMAP/QA |

## 3. 完整"说了但没做"清单（散落在会话、未进任何任务的全部条目）

**A. 架构债务（2026-09-24 架构评审产出，仅存在于会话）**
- ~~D2 统一事件缝（=队列1，最高 ROI）~~ ✅ 2026-09-24 完成（实施计划 `docs/superpowers/plans/2026-09-24-d2-event-seam.md`，T1–T4 全交付 + 2026-09-25 收尾小改动「事件软删保留提醒行」按用户裁定实施），遗留登记见 ROADMAP Pending Items P3（`triggerTime` 派生态存表 / ICS 接 outbox / CLI 跨进程写）
- D1 payload schemaVersion + contracts 字段清单（=队列5）
- D3 后台同步重建 + device 注册补全（=队列7）
- D4 应用内令牌桶限流（=队列6）
- D5 时间三约定（UTC串/墙钟/本地tz）类型化收敛到单一 TimeCodec（靠 CONSTRAINTS 文档约束着，未类型强制）

**B. 用户直接指令（已执行）**
- ~~MCP → 官方 SDK 迁移（=队列3）~~ ✅ 2026-09-24 spike 实测不能承载，已按预案写 DECISIONS 转正手写版（含复核触发条件）

**C. 前端设计（=队列2，流程见 §5）**

**D. 终审 triage 出的 (b) 类小项（部分只在会话）**
- quick-add PendingIntent 加 `setPackage(context.packageName)`（防 scheme 抢注）
- iOS widget 扩展 IPHONEOS_DEPLOYMENT_TARGET 26.4 → 15/17（否则老 iOS 无小组件）
- AppIntent/gallery 硬编码英文 l10n（widget 运行时文案已预本地化，仅 gallery 元数据）
- Apple 端无 legacy 三键回退（升级窗口期的优雅度）
- 月视图空白槽补 Semantics(button)（日/周已有）
- 六件事 FutureProvider 冷启动 1 帧闪烁；拖拽测试 600ms 防抖；DateStrip 360dp 真机检查（docs/qa/p4-manual-qa.md §二）
- ROADMAP "Current Features" 区块未随 P4 刷新（i18n 计数已改264）
- P2 期 two_device_sync_test 观察到过 1 秒边界 flake ×1（未复现）

**E. 已在档、只需知其位置的（不在本文重复）**
- P2.5 同步遗留5条（远程改期重挂提醒为第1条）→ `docs/ROADMAP.md` Phase P2.5 表
- lunar 2026+ 法定数据、Windows 通知 stub 上游复查 → ROADMAP P4 follow-ups
- P1–P3 各终审 deferred (b)/(c) → 各阶段会话已交付，凡承重者均已入 ROADMAP/CONSTRAINTS

**F. 过程记录（豁免类，防止下次被当成"没做的流程"）**
- 人工 QA 豁免：P2（2026-09-23）、P4（2026-09-24 用户明示"不想做任何人工事"）、**D2 债务2（2026-09-25 用户裁定记账豁免，3 项抽查未执行，清单留存 `docs/qa/d2-manual-qa.md`）**；P3 四客户端走查未做。清单留存 `docs/qa/p{2,3,4}-*.md` 供有需要时补
- 发布自动化链已跑通一次：push→CI 8格→tag→五平台产物冒烟→publish（含 secret 二进制雷修复）

## 4. 架构债务详情

见会话归档要点：诊断依据=架构评审七步法对照；每笔债务有处方与工作量估计（D2≈半天，D5≈轻，D3≈数天）。若需完整论证，让 AI 重读 `docs/DECISIONS.md` + `docs/CONSTRAINTS.md` 即可重建上下文（评审原文明细未入库，此为索引）。

## 5. 前端设计走查流程（固定套路，勿改成"直接改好看"）

1. 主输入 = `docs/design-token-gap.md`（DESIGN.md vs 代码的逐条差距表）；可选补充：用户觉得丑的 3–5 张截图
2. AI 按五维度逐条产出“具体哪、为什么、怎么改”：**间距节奏(4/8倍数)/字阶(固定层级)/视觉层级(重点是否跳出来)/主题一致性(kalender 未驯化处)/状态设计(空/加载/错误)**
3. 清单 → 用户只做 改/不改 选择题
4. AI 批量执行 + 测试收口
- 设计语言权威：`DESIGN.md` UI 令牌（CLAUDE.md UI 原则为行为补充）

## 6. 关键文档地图（状态类信息永远看这里，别信本文复述）

| 要查什么 | 去哪 |
|---------|------|
| 冻结需求8条 / 规则契约 / 架构实例(§2) | `SPEC.md`（**状态一律看 ROADMAP**） |
| 版本 / 工作流红线 / 架构分层 / 文档地图 | `CLAUDE.md` |
| 流程四件：执行工序·Rulings / 审查五配方 / 测试DoD / 架构七步 | `docs/process/{EXECUTION,REVIEWING,TESTING,ARCHITECTURE}.md`（vendored 自 vibe-coding-starter，定制规则见 CLAUDE 工作流开头） |
| 踩坑防回归（签名、同步、小组件、时区…） | `docs/CONSTRAINTS.md` |
| 为什么这样决定 | `DECISIONS.md` |
| 进度全景 / P2.5 / follow-ups（**状态唯一源**） | `docs/ROADMAP.md` |
| 用户可见变更史 | `docs/changelog.md` |
| 设计令牌（颜色/字阶/间距/圆角） | `DESIGN.md`；**规范 vs 代码差距表** `docs/design-token-gap.md`（设计走查任务的输入） |
| 各Phase实施计划（含主计划） | `docs/superpowers/plans/` |
| 手工验收清单 | `docs/qa/` |
| AI 跨工具入口（Codex 等） | `AGENTS.md` |
| 归档（CalDAV 旧文档、旧外部评审） | `docs/archive/` |

## 7. 开工方式

用户说"继续/看从哪开始"→ 按 §2 队列第1项行动；改动前照 `CLAUDE.md` 完整工作流（SDD：计划→子代理实现→独立审查→终审→Rulings 披露→用户确认后才 push/tag）。**未在本文档与 ROADMAP 出现的"会话中提到但未做"的事项 = 不存在，以本清单为准。**
