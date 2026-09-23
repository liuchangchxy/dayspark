# P2 手工验收清单 (v0.22.0) / P2 Manual QA Checklist

> 来源：SDD Task 8（Phase 2 收尾）。**发布 tag v0.22.0 前必须全部人工过一遍。**
> 自动化双设备 e2e 矩阵（5 例）见 `test/integration/two_device_sync_test.dart`；部署步骤见 `docs/DEPLOY.md`。
> Source: SDD Task 8 (Phase 2 wrap-up). Must be walked through manually before tagging v0.22.0.
> Automated two-device e2e matrix (5 cases): `test/integration/two_device_sync_test.dart`; deployment: `docs/DEPLOY.md`.

## 〇、部署服务器 / Deploy the server (NAS Docker)

- [ ] 按 `docs/DEPLOY.md` 第 1–2 节部署：生成 `JWT_SECRET` → `docker compose up -d --build` → `curl http://<nas-ip>:8787/health` 返回 `{"ok":true,...}` / Follow `docs/DEPLOY.md` §1–2: generate `JWT_SECRET`, `docker compose up -d --build`, `/health` returns `{"ok":true,...}`
- [ ] 反代 + SSE（若走 nginx/Tailscale）按 `DEPLOY.md` 第 3 节关闭缓冲 / Reverse proxy + SSE per `DEPLOY.md` §3 (buffering off)

## 一、双设备注册登录 / Dual-device register + login（两台真实机器/实例）

> 实例 A = 模拟器/手机，实例 B = 桌面（或第二台真机）；两个独立数据目录 = 两份本地库。 / Instance A = emulator/phone, instance B = desktop (or a second real device); two separate data directories = two independent local DBs.

- [ ] A：设置 → 服务器地址填 `http://<nas-ip>:8787`（或 Tailscale 地址），**注册**同一账号 / A: Settings → server URL, register the account
- [ ] B：同一 Server URL，**登录**同一账号（不要注册第二个账号）/ B: same URL, **log in** with the same account (do not register a second one)
- [ ] 两台都登出后各自重新登录，token 轮换后仍能同步 / Log out and back in on both; sync still works after refresh-token rotation
- [ ] 错误密码 / 错误 Server URL → 设置区显示可读错误，不崩溃 / Wrong password or wrong server URL → readable error in the account section, no crash

## 二、真实 UI 离线-冲突场景 / Offline-conflict scenarios in the real UI

- [ ] **创建传播**：A 新建日程 → B 数秒内出现（不手动刷新）/ Create on A → appears on B within seconds (no manual refresh)
- [ ] **编辑传播**：A 改标题+时间 → B 收敛到同一值 / Edit title+time on A → B converges
- [ ] **删除传播**：A 删日程 → B 上进入回收站（软删/墓碑），恢复后可拉回 / Delete on A → B soft-deletes (tombstone); restore works
- [ ] **离线编辑合并（不同字段）**：两台开飞行模式，A 改标题、B 改描述，先后上线 → 两台都保留双方改动（字段级 LWW 合并）/ Offline edit on different fields, reconnect in turn → both edits survive on both devices (field-level merge)
- [ ] **同字段冲突**：两台离线改同一标题，后上线者胜，两台终值一致 / Offline edits to the same field → last arrival wins, both devices end identical
- [ ] **待办同步**：A 建/改（含 due date、优先级）/完成/删除待办 → B 收敛；子任务不出现错链 / Todo create/edit (due, priority)/complete/delete propagates; no mis-linked subtasks
- [ ] 断网期间本地照常编辑（离线可用），恢复网络后自动补推 / Editing while offline works locally; changes flush automatically on reconnect

## 三、设置区流程 / Settings section flows

- [ ] 未登录态：Server URL 输入框回填已保存地址；登录/注册按钮状态正确 / Logged-out state: server URL field prefills saved address; login/register states correct
- [ ] 登录成功 → 显示账号邮箱与同步状态；登出 → 状态清空且不报错 / Login shows email + sync status; logout clears state without errors
- [ ] 修改 Server URL 后重新登录生效 / Changing server URL then re-login takes effect
- [ ] 关于页版本号显示 `DaySpark v0.22.0` / About page shows `DaySpark v0.22.0`

## 四、SSE 实时更新体感 / SSE live-update feel

- [ ] A 保存编辑后，B **不切后台/不手动下拉**即在数秒内更新（SSE cursor 信号驱动 pull）/ After A saves, B updates within seconds without backgrounding or manual refresh (SSE cursor signal → pull)
- [ ] 杀掉 B 的网络再恢复 → 自动重连并补齐错过的变更 / Kill B's network, restore → auto-reconnect catches up
- [ ] 反代场景下走 `DEPLOY.md` §3 配置，实时感不受缓冲拖慢 / Behind a reverse proxy use `DEPLOY.md` §3; live updates not delayed by buffering

## 五、已知边界（P2.5，不需要阻塞发版）/ Known limits (P2.5, non-blocking)

- [ ] 记录复核：他端改日程时间/待办 due → 本机提醒**仍按旧时间**（已知，见 ROADMAP P2.5）/ Remote time/due edits do NOT reschedule local alarms (known, see ROADMAP P2.5)
- [ ] 记录复核：ICS 导入的行在首次编辑前不入同步 / ICS-imported rows don't sync until first edited (known)
- [ ] 记录复核：日历归属为启发式回退（日历本身不同步）/ calendarId is a heuristic fallback (calendars don't sync)
