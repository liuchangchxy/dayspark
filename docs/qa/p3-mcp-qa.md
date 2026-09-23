# P3 MCP 手工验收清单 / P3 MCP Manual QA Checklist

> 来源：SDD Task 5（Phase 3）。**对外声称 MCP 四客户端可用前必须人工过一遍（或按 P2 先例豁免并记录）。**
> 自动化 e2e 矩阵（5 例）见 `server/test/mcp_e2e_test.dart`；部署步骤见 `docs/DEPLOY.md`；两条鉴权轨（login token / OAuth）语义见 `server/test/oauth_test.dart`。
> Source: SDD Task 5 (Phase 3). Walk through manually before claiming four-client MCP support (or waive per the P2 precedent and record the waiver).
> Automated e2e matrix (5 cases): `server/test/mcp_e2e_test.dart`; deployment: `docs/DEPLOY.md`; the two auth tracks (login token vs OAuth): `server/test/oauth_test.dart`.

**自动化 vs 手工 / Automated vs manual**

| 项 / Item | 方式 / How |
|---|---|
| AI 写 → 设备 pull/SSE 收敛、AI 完成待办收敛、同记录并发 LWW、OAuth 全链路（DCR→PKCE→call→refresh）、scope 降权 | 自动化 `server/test/mcp_e2e_test.dart`（5/5） |
| 工具面/协议/OAuth 单元面、P2 双设备引擎矩阵 | 自动化 `mcp_tools_test` / `mcp_protocol_test` / `oauth_test` / `test/integration/two_device_sync_test.dart` |
| Inspector / Claude Code / Codex / ChatGPT connector 接入、schema 2→3 文件库迁移 | **手工**（外部工具无法进 CI，本清单即交付物） |

## 〇、起服务 / Boot the server locally

- [ ] 本地起服务：`cd server && JWT_SECRET=$(openssl rand -hex 32) DB_PATH=./data/qa.db dart run bin/server.dart` → 打印 `listening on :8787`；或按 `docs/DEPLOY.md` §1–2 起 Docker / Local boot: `cd server && JWT_SECRET=… DB_PATH=./data/qa.db dart run bin/server.dart` (or Docker per `DEPLOY.md` §1–2)
- [ ] 取一个 login token（①–③ 用，15 分钟有效，过期重跑一次即可）：

```bash
# 先注册（已有账号则跳过）/ register once (skip if the account exists)
curl -s -X POST http://localhost:8787/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"qa@example.com","password":"password123"}'
# 登录取 accessToken / login for a track-1 token
TOKEN=$(curl -s -X POST http://localhost:8787/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"qa@example.com","password":"password123"}' | jq -r .accessToken)
```

## 一、MCP Inspector / MCP Inspector（login-token 轨）

- [ ] 起 Inspector：`npx @modelcontextprotocol/inspector` → 浏览器打开它打印的地址（默认 `http://localhost:6274`）/ Launch: `npx @modelcontextprotocol/inspector`, open the printed URL
- [ ] Connect 面板：Transport 选 **HTTP**，URL 填 `http://localhost:8787/mcp`；鉴权选 Bearer/Header，填 `Authorization: Bearer $TOKEN`（login-token 轨，**不是** OAuth 弹窗）/ Transport **HTTP**, URL `http://localhost:8787/mcp`, header `Authorization: Bearer $TOKEN` (login-token track — do **not** run the OAuth flow here)
- [ ] 不带 token 连接 → 401，且 `WWW-Authenticate` 里 `resource_metadata` 指向 `/.well-known/oauth-protected-resource`（错误信息可读）/ Without a token → 401 with a readable challenge pointing at the protected-resource metadata
- [ ] **initialize 成功 → Tools 列表出现 17 个工具**（`get_events`…`batch_create_tasks`）/ Initialize succeeds → 17 tools listed
- [ ] 跑一次写工具 `create_event`，arguments：

```json
{
  "title": "Inspector smoke",
  "start": "2026-10-01T10:00:00Z",
  "end": "2026-10-01T11:00:00Z",
  "timezone": "Asia/Shanghai"
}
```

- [ ] 返回 `event.event_id` + `op.status = applied`；App 或 `GET /sync/pull?cursor=0`（带 login token）能拉到这条记录 / Result carries `event_id` + `op.status=applied`; an app device or a login-token `/sync/pull` sees the record（跨层收敛的自动化版见 e2e ①）

## 二、Claude Code / Claude Code（两条轨都可，任选其一）

**轨 A：HTTP 直连（Bearer header）/ Track A: HTTP with bearer header**

```bash
claude mcp add --transport http dayspark http://localhost:8787/mcp \
  --header "Authorization: Bearer $TOKEN"
```

**轨 B：stdio wrapper（env 配置）/ Track B: stdio wrapper via env**

```bash
claude mcp add dayspark \
  -e DAYSPARK_MCP_URL=http://localhost:8787/mcp \
  -e DAYSPARK_MCP_TOKEN="$TOKEN" \
  -- dart run "$PWD/tool/mcp_stdio_wrapper/bin/mcp_stdio_wrapper.dart"
```

- [ ] `claude mcp list` → dayspark **connected** / shows connected
- [ ] 会话里问「列出今天的待办」→ 走 `list_tasks` 返回真实数据；让它建一条日程 → `create_event` 落库 / Ask for today's tasks → real `list_tasks` data; have it create an event → `create_event` persists
- [ ] `claude mcp remove dayspark` 清理（两轨同名，加完一条先测完再换轨）/ Clean up with `claude mcp remove dayspark` (both tracks share the name — test one before switching)
- [ ] 注意：login token 15 分钟过期；wrapper 只透传、不自动 refresh，401 会显示为 JSON-RPC `-32002` → 重跑 §〇 的 login 取新 token、重启客户端即可 / Note: the login token expires after 15 min; the wrapper proxies blindly (no refresh), so a 401 surfaces as `-32002` — re-run the login curl and restart the client（CLI 自带 401→refresh 重试，不受此限）

## 三、Codex（stdio wrapper，`~/.codex/config.toml`）

在 `~/.codex/config.toml` 追加（`command`/`args` 用绝对路径；token 同样 15 分钟有效）/ Append to `~/.codex/config.toml` (absolute paths; token is 15-minute-lived):

```toml
[mcp_servers.dayspark]
command = "dart"
args = [
  "run",
  "/Users/chang/Desktop/日历待办 app 项目/calendar_todo_app/tool/mcp_stdio_wrapper/bin/mcp_stdio_wrapper.dart",
]
env = { DAYSPARK_MCP_URL = "http://localhost:8787/mcp", DAYSPARK_MCP_TOKEN = "< accessToken >" }
```

- [ ] 重启 Codex → 会话里能看到 dayspark 的 17 个工具 / Restart Codex → the 17 tools are visible
- [ ] 让它「把明天 10 点的例会加进日历」→ `create_event` 成功，App 端数秒内出现 / Create an event by voice-text → succeeds, appears in the app within seconds
- [ ] env 缺 `DAYSPARK_MCP_URL`/`DAYSPARK_MCP_TOKEN` → wrapper 退出码 78 并在 stderr 点名缺失变量（不挂起）/ Missing env → exit 78 naming the variable, never a hang

## 四、ChatGPT connector（OAuth 轨，需公网 HTTPS）

> 两条轨互不相通：connector 走 **OAuth 2.1**（DCR + PKCE + 浏览器同意），**不会**用 §〇 的 login token——login token 只给 Inspector/Claude Code/Codex 这类能自由塞 header 的客户端。 / The connector performs OAuth — it never sees the login token (track 1 is for clients that can set headers themselves).

- [ ] 先有公网 HTTPS：按 `docs/DEPLOY.md` §3（nginx 反代 + certbot）或 §4（Tailscale）部署；**ChatGPT 要从公网可达**——tailnet 内网地址不行，需公网域名+TLS，或 Tailscale Funnel / Public HTTPS per `DEPLOY.md` §3 (nginx + certbot) or §4 — plain tailnet addresses are NOT internet-reachable; use a public domain+TLS or Tailscale Funnel
- [ ] **反代必须带** `proxy_set_header X-Forwarded-Proto $scheme;`（DEPLOY §3 模板已含）：否则 discovery 把 origin 广告成 `http://`，connector 会拒绝。服务端已实现「有该 header 就信任其 scheme」（`requestOrigin`，仅反代场景）/ The proxy **must** send `proxy_set_header X-Forwarded-Proto $scheme;` (already in the `DEPLOY.md` §3 template); without it discovery advertises `http://` origins and the connector refuses. The server now trusts the header when present (behind-proxy only)
- [ ] 反代同时带上 §3 模板新增的两行：`client_max_body_size 256k;` + `limit_req zone=dcr burst=5 nodelay;`（`/oauth/register` 限流，zone 声明在 http 上下文）/ The proxy also carries the two new §3 lines: `client_max_body_size 256k;` and `limit_req zone=dcr burst=5 nodelay;` on `/oauth/register` (zone declared in the http context)
- [ ] 验证 discovery：`curl -s https://your.host/.well-known/oauth-authorization-server | jq .issuer` → `https://your.host`（直连 8787 无 header 时仍是 `http://…`，属预期）/ Verify: issuer is `https://your.host`; a direct no-header request stays `http://…` as expected
- [ ] ChatGPT → Settings → Connectors → Add custom connector → MCP server URL = `https://your.host/mcp` → 它自动做 OAuth discovery（`/.well-known/oauth-authorization-server` + protected-resource）→ DCR 注册 → 跳转你的同意页，**用 DaySpark 账号密码登录授权**（PKCE S256）/ Add connector with `https://your.host/mcp`; ChatGPT discovers, registers dynamically, and redirects to the consent page — log in with the DaySpark account (PKCE)
- [ ] 回到 ChatGPT 后能列出工具；「明天有什么安排」→ `get_events` 返回真实数据 / Tools list after consent; a schedule question returns real `get_events` data
- [ ] 同意页拒绝（错误密码）→ 不发 code、留在表单页；re-consent 可重试 / Wrong password on the consent page issues no code; retry works
- [ ] scope 核对：connector 拿到的 token 调 `create_*` 成功（写 scope 在）；若只授只读 → 写工具回 `FORBIDDEN_SCOPE` 工具结果（自动化 e2e ⑤ 覆盖）/ Write tools succeed with write scope; read-only grant returns a `FORBIDDEN_SCOPE` tool result (e2e ⑤)

## 五、schema 2→3 文件库迁移手工检查 / Manual 2→3 file-DB migration check

> T3 carry：`onUpgrade(2→3)` 写了（补 `refresh_tokens.clientId/scope`、建 `oauth_clients`/`oauth_codes`），但没有自动化用例真开过 P2 期文件库——本步人工补上。 / T3 carry: the upgrade path is code-covered only by `onCreate` in tests — open a real P2-era file once, manually.

任选一条拿到 P2 库（schema `user_version=2`）： / Get a P2-era DB (schema `user_version=2`) either way:

```bash
# A) 生产卷里拷（Docker 部署）/ from the production volume
docker run --rm -v dayspark-data:/data -v "$PWD":/backup alpine \
  cp /data/dayspark.db /backup/p2-dayspark.db

# B) 没有生产库 → 用 main（P2，schemaVersion=2）现造一个
git worktree add /tmp/dayspark-p2 main
(cd /tmp/dayspark-p2/server && JWT_SECRET=x DB_PATH=/tmp/p2-dayspark.db dart run bin/server.dart &) 
sleep 2 && pkill -f 'p2-dayspark.db'   # boot once, then stop / 起一次即停
```

检查 + 升级 + 复验 / Check, upgrade, re-verify:

```bash
sqlite3 /tmp/p2-dayspark.db 'PRAGMA user_version;'    # expect 2
sqlite3 /tmp/p2-dayspark.db '.tables'                 # no oauth_* tables

cd server
DB_PATH=/tmp/p2-dayspark.db PORT=8788 JWT_SECRET=migrate-check dart run bin/server.dart
# 另开一个 shell / in another shell:
curl -s http://localhost:8788/health                   # {"ok":true,...}

sqlite3 /tmp/p2-dayspark.db 'PRAGMA user_version;'    # expect 3
sqlite3 /tmp/p2-dayspark.db '.schema oauth_clients'    # created
sqlite3 /tmp/p2-dayspark.db '.schema refresh_tokens'   # clientId + scope columns added
# 旧数据仍在 / old rows survive:
sqlite3 /tmp/p2-dayspark.db 'SELECT count(*) FROM users; SELECT count(*) FROM records;'
# 老账号能登录（生产 A 的库带上自己的账号密码）/ old account can still log in:
curl -s -X POST http://localhost:8788/auth/login -H 'content-type: application/json' \
  -d '{"email":"<old-account>","password":"<password>"}' | jq -r .accessToken
```

- [ ] user_version 2→3、oauth 表建出、users/records 行数不变、老账号登录成功 / All four checks pass; row counts unchanged; old login works

## 六、豁免先例 / Waiver precedent

P2 双设备手工 QA 已由用户于 2026-09-23 明确豁免（SDD ledger 记录），清单保留于 `docs/qa/p2-manual-qa.md`。本清单同理：**用户可豁免四客户端手工接入，但须在 ledger/报告记录**——自动化 e2e 矩阵不可豁免。 / The P2 dual-device manual QA was explicitly waived by the user on 2026-09-23 (recorded in the SDD ledger) with its checklist retained. Same rule here: the user may waive the four-client manual walkthrough, but the waiver must be recorded — the automated e2e matrix is not waivable.
