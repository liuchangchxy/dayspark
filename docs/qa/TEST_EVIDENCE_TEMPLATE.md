# 测试证据报告 / Test Evidence Report

> 套用自 vibe-coding-starter `docs/templates/TEST_EVIDENCE_TEMPLATE.md`。
> **判据**：分层写清 pass / fail / skipped / 未运行原因。低层证据不得冒充更高层的用户链路验收。

## 范围
- 变更 / 需求：
- 代码版本：
- 环境：

## 分层结果

| 层级 | 命令 | pass | fail | skipped | 未运行原因 |
|---|---|---:|---:|---:|---|
| 单元 / 领域 | `flutter test test/domain` | | | | |
| Widget / UI | `flutter test test/ui test/widget` | | | | |
| 数据 / 文件物理链路 | `flutter test test/data` | | | | |
| 集成 / 跨进程 | `flutter test test/integration`；`server` 侧 `dart test` | | | | |
| 构建 / 部署冒烟 | `flutter build web --release` + `dart run tool/web_smoke.dart` | | | | |
| 真机 / 客户端 E2E | | | | | |

## 结论
- 最高实际验证层级：
- 是否存在未披露的失败或跳过：
- 可声明的范围：
- **不能**声明的范围：

## 计数口径与重复采样（按需）
- runner 汇总数与实际业务场景数不一致时，说明两种计数及关系：
- 对已确认的偶发问题重复采样时，记录固定条件、总运行次数、通过数、失败数：
