# P5 后台同步 + 设备注册 — 实施方案

> 2026-10-01 制定。**用户已拍板**：P5-a 先单独交付；P5-b 以 C+D 为主，A（FCM/APNs）做可选开关默认关。
> 现状诊断与备选论证见本文件 §1–§2；执行按 §3 的顺序。

## 1. 现状（实测，非推断）

| 部件 | 状态 |
|---|---|
| 客户端 deviceId | ✅ 已生成+持久化（`loadOrCreateDeviceId`），且已在 push 请求体上报（`PushRequest.deviceId`） |
| 服务端 `Devices` 表 | ✅ 已建（`id / userId / deviceId(unique) / name / lastSeen`） |
| 服务端**写入** Devices | ❌ 零处——`applyInternalOp` 不接收 deviceId |
| 设备注册接口 | ❌ 无 `/devices` 路由 |
| `SyncOps` 表 | ❌ 无 `deviceId` 列——「这条变更哪台设备写的」查不到 |
| `x-device-id` 头 | ⚠️ `requireAuth` 会读进 `AuthContext.deviceId`，但**客户端从不发** |
| 前台同步 | ✅ SSE 流 + 15s 兜底轮询 + 连通性监听 + onResume 补一轮 |
| 后台/关闭 | ❌ `poller.paused()` 直接停；pubspec 零推送/后台任务依赖 |

**一句话**：同步地基（outbox / LWW / 幂等 / SSE / 单写缝 / 游标）全在，缺的只有「应用不在前台时，怎么知道远端变了」。

## 2. P5-b 的四条路与选型

| | 机制 | 可靠性 | 经过谁 | 结论 |
|---|---|---|---|---|
| A | FCM / APNs 无内容唤醒推 | 高 | Google + Apple | **做成可选开关，默认关**——不发数据，但「何时、哪台设备有变更」这类元数据会过第三方，该由用户自己决定 |
| B | 自托管推送（UnifiedPush / ntfy） | Android 好，**iOS 无对应实现** | 自己的 NAS | 否——只覆盖一半平台，还要多维护一个通道 |
| C | 后台拉取（WorkManager / BGAppRefreshTask） | 尽力而为（Doze / iOS 配额） | 无 | **✅ 主路径** |
| D | 回前台即补同步 | 打开就同步 | 无 | **✅ 兜底** |

**选定：C + D 为主，A 可选。**

## 3. 执行顺序

### P5-a 设备注册（先单独交付）

**服务端**
1. `SyncOps` 加 `deviceId` 列（`withDefault('')`，向后兼容）；`schemaVersion` 3 → 4 + 迁移
2. `applyInternalOp` 增加 `deviceId` 透传，落在 `SyncOps.deviceId`
   —— **为什么落 SyncOps 而不是 Records**：`Records` 是「当前状态」（已有 `lastOpId` 表达「谁最后写的」），设备归属是**逐 op 的历史**，SyncOps 本就是 append-only 的 op 账本
3. `POST /devices/register`（auth）：body `{deviceId, name?}` → upsert + `lastSeen`
   —— deviceId 已被别的账号占用 → 403，不做跨账号重绑（防劫持）
4. `GET /devices`（auth）：列出本账号设备（供设置页）
5. `/sync/push` 用 `x-device-id` 头（缺失则回退 body 的 `deviceId`）；顺带 touch `lastSeen`

**契约**（`packages/dayspark_contracts`）
6. `DeviceDto` + register 请求体

**客户端**
7. `_authHeaders()` 加 `x-device-id`
8. 登录成功后 + 冷启动时各上报一次（幂等）
9. 设备名：用现有 `platform_target` 派生（Android/iOS/macOS/Windows/Linux/Web），**不引新依赖**
10. 设置页「已连接设备」：显示名称 + 最后活跃时间

**验收**
- 服务端：注册幂等、跨账号 deviceId 冲突被拒、push 后 SyncOps 有 deviceId、lastSeen 被 touch
- 客户端：头真的发出去了、重复启动不重复建行

### P5-b 后台同步（P5-a 交付后再开）
1. 先做 D 的完善 + 测试（回前台补同步的边界：长时间后台、跨设备游标、断连恢复）
2. 再做 C（各平台后台任务接入）
3. A 最后做，且**必须先与用户确认告知文案**再动手

## 4. 风险与边界（据实记录）

- **P5-b 的 C 是"尽力而为"**：iOS `BGAppRefreshTask` 由系统决定何时给配额，可能数小时一次。**不能向用户承诺"实时"**，UI 文案不能这么写。
- **A 一旦启用**，元数据（时间 + 设备标识）经过 Google/Apple。开关的说明文案必须写明这一点，不能含糊。
- 桌面三平台（macOS/Windows/Linux）本来就常驻，D 基本够用；Web 标签页关闭同样只能靠 D。
- 本方案不动 `Records` 表结构，因此不影响 LWW 与既有的 `lastOpId` 平局裁决。
