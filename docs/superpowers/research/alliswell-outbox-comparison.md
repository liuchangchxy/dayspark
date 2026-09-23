# AllisWell 同事务设计对照

> 存档自 P2 SDD task-5 报告（工作区已清理）。AllisWell = PolyForm NC，仅设计研究，未复制代码。详见 DECISIONS.md 对应条目。

## AllisWell 同事务设计对照

（brief 第 7 行要求；`sync_outbox.dart` 的 WHY 注释指向本节。）

**为什么 tableUpdates-only 不行（P1 小组件的教训反着用）：** `tableUpdates` 在**提交之后**才发——它适合做"刷新"的单一 choke point（刷新是幂等、可重算的，漏一次还能补），但不适合做入队：若写完行、等事件回调再补 `enqueue`，两次写之间存在崩溃窗口（行已提交、op 未入队 → 这条修改永远推不出去），而且它只"观察"写、不能把入队与变更绑成原子对。同步 outbox 必须与行变更**同一事务**提交/回滚，所以改用显式出口：每个 provider 变更函数 `db.transaction { 改行; SyncOutbox.enqueue(tx, …) }`。

| | AllisWell outbox 设计 | DaySpark P2（本实现） |
|---|---|---|
| 入队时机 | outbox 与业务写同一事务 | 同：`enqueue*` 在调用方 Drift 事务内（绑定规则 2） |
| 原子性 | 每次变更：行 + op 同生共死 | **等价**：同事务同生共死 |
| 写入汇聚 | 单一 central writer，所有变更必经 | 无中央写点 → 显式 per-provider 出口（create/edit/complete/restore/delete + reorder/setParent/moveOverdue）；覆盖由 checkpoint-8 全量扫 mutation 出口证明 |
| 失败模式 | writer 挂了全盘不动 | 单个调用点漏接 = 该路径静默不同步 → 以扫描清单约束（ICS 导入为已知 P2.5 缺口，见顾虑 1） |

参考性质说明：AllisWell 按 **PolyForm NonCommercial** 授权，仅作**设计研究**（字段级 LWW、同事务 outbox 形态），本仓库**未复制其任何代码**。
