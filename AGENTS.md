# AI 助手行为准则 (AGENTS.md)

本文件是 DaySpark (灵光) 仓库的**跨工具 AI 入口**（Claude Code、Codex、Cursor、Windsurf、Aider、Copilot 等均原生/兼容读取 `AGENTS.md`）。
任何 AI 助手在本仓库开始工作前，必须先读本文件；工程规则细节见 [CLAUDE.md](CLAUDE.md)，业务规则见 [SPEC.md](SPEC.md)。

---

## 三大底线 (Hard Constraints)

1. **SPEC 先行**：任何业务改动的最终标准以 [SPEC.md](SPEC.md) 为准。改需求 / 新功能 / 行为变更，必须**先修订 SPEC.md 对应章节**，再改测试，最后改实现；代码只是 Spec 的具象化体现。禁止只改代码不落文档。
2. **非破坏性操作**：严禁未经用户明确许可物理删除已有数据或覆盖受保护的配置（数据库、用户配置、签名密钥、git 历史等）。删除/覆盖前必须获得用户确认。
3. **交付全绿**：改动代码后必须跑 `dart analyze .`（零 issue）与 `flutter test`（全绿）并以输出为证，杜绝"带病提交"。pre-commit 钩子会物理拦截非零 analyze 退出码；测试全量靠流程卡口（钩子不跑全量测试）。

---

## 文件分工（互相引用，不重复）

| 文件 | 职责 | 谁读 |
| :--- | :--- | :--- |
| [SPEC.md](SPEC.md) | **业务规则**真理源（做什么、规则契约、功能矩阵） | 所有 AI，改业务前必读 |
| [CLAUDE.md](CLAUDE.md) | **工程规则**（代码风格、架构分层、工作流卡口、版本/CI 规则） | 所有 AI，写代码前必读 |
| [DECISIONS.md](DECISIONS.md) | **为什么**（轻量 ADR 时间线，重大决策留痕） | 决策存疑时查 |
| [docs/CONSTRAINTS.md](docs/CONSTRAINTS.md) | **坑**（技术约束/避坑清单） | 改日历/DB/Provider/通知/同步前必读 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | **功能**演进全景与状态 | 判断功能现状时查 |
| [docs/changelog.md](docs/changelog.md) | **反馈**日志（原文→todo→代码 溯源） | 处理用户反馈时查 |

---

## 规则：用户纠错 → 追加避坑清单

当用户对 AI 的行为进行**纠正、批评或提出开发习惯偏好**时（例如："不要动我的某个配置"、"命令别用全屏"、"别用 flutter analyze"）：

1. AI 必须**主动编辑 [docs/CONSTRAINTS.md](docs/CONSTRAINTS.md)**，在对应领域章节追加一条带 **Why / Date** 的避坑条目（负面约束）；
2. 从下一次交互起，该条目即为红线，新会话不可再犯；
3. 若纠错涉及业务规则本身，同步修订 SPEC.md；若涉及重大架构走向，顺手在 DECISIONS.md 追加一条时间戳记录。

## 附：初始化预设教训

1. 改需求严禁只改业务代码，必须第一时间同步修改 SPEC.md。
2. 代码交付前必须确保 `dart analyze .` 零 issue 且 `flutter test` 全绿，杜绝"修了 A 破坏了 B"。
