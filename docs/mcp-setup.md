# MCP Setup Guide / MCP 服务器配置教程

DaySpark 的 MCP（Model Context Protocol）服务器**内建于自托管后端**（与同步服务同进程、同数据源），让 Claude Code、ChatGPT、Codex 等 AI 直接读写你的日历与任务。
DaySpark's MCP server lives **inside the self-hosted backend** (same process, same data as sync), letting Claude Code / ChatGPT / Codex read and manage your events and tasks.

> 本文替代旧版“应用内 localhost MCP”（v0.13 删除，v0.23 以服务端形态重建）。/ Replaces the removed in-app localhost MCP (deleted in v0.13, rebuilt server-side in v0.23).

## 能力 / Capabilities

- **17 个工具 / 17 tools** — 查询/创建/更新事件（含 RRULE 结构化重复）、任务的列表/完成/重开/暂缓、批量建任务、找空档、回收站只读等
- **3 个资源 / 3 resources** — `dayspark://today`、`dayspark://overdue`、`dayspark://inbox`
- **安全姿态** — 无永久删除工具（trash 软删=可恢复，与回收站一致）；读工具 `mcp:read`、写工具 `mcp:write` 分域授权；错误以工具结果返回并带 hint（不吐堆栈）

## 前置 / Prerequisites

1. 部署 DaySpark 后端并可从 Agent 访问（本机或 NAS）→ 见 [DEPLOY.md](DEPLOY.md)
2. ChatGPT 远程接入需公网 HTTPS（反代/Tailscale，见 DEPLOY §3/§4）

## 双轨认证 / Two Auth Tracks（不可混用）

| 使用者 | 轨道 | 取得令牌 |
|--------|------|---------|
| **本地 Agent**（Claude Code / Codex / Hermes 经 stdio 桥） | 登录轨 | `tool/dayspark_cli` 执行 `dayspark login --server URL --email you`（密码交互输入，存 `~/.dayspark/credentials.json` 0600）→ 取 access token |
| **ChatGPT Connector 等远程客户端** | OAuth 轨 | 走标准 OAuth 2.1（PKCE-S256、动态注册、浏览器同意页）；Bearer 访问令牌**不能**调同步 API，反之亦然（双轨互斥，设计如此） |

## Claude Code 配置 / Claude Code

**方式 A（推荐，stdio 桥）：**

```json
{
  "mcpServers": {
    "dayspark": {
      "command": "dart",
      "args": ["run", "tool/mcp_stdio_wrapper/bin/mcp_stdio_wrapper.dart"],
      "env": {
        "DAYSPARK_MCP_URL": "http://localhost:8787/mcp",
        "DAYSPARK_MCP_TOKEN": "<你的 access token>"
      }
    }
  }
}
```

**方式 B（HTTP 直连）：** `claude mcp add dayspark --transport http http://localhost:8787/mcp --header "Authorization: Bearer <token>"`

## Codex 配置 / Codex

`~/.codex/config.toml`：

```toml
[mcp_servers.dayspark]
command = "dart"
args = ["run", "/path/to/dayspark/tool/mcp_stdio_wrapper/bin/mcp_stdio_wrapper.dart"]
[...]
# 或用环境变量注入（视 Codex 版本的 env 语法）
```

（stdio 桥需要 `DAYSPARK_MCP_URL` + `DAYSPARK_MCP_TOKEN` 环境变量。）

## ChatGPT Connector / OpenAI

1. 后端需公网 HTTPS（DEPLOY.md：nginx 反代**必须**设置 `proxy_set_header X-Forwarded-Proto $scheme;`，否则 OAuth 元数据会错报 http）
2. 在 ChatGPT → Settings → Connectors → Add custom connector，填入你的服务器 MCP 地址，完成浏览器内 OAuth 同意
3. 需要 Developer Mode 才暴露全量读写工具（OpenAI 侧要求）

## 验证 / Verify

1. MCP Inspector：`npx @modelcontextprotocol/inspector` → 传输选 HTTP → URL `http://<host>:8787/mcp` → 填 Bearer → `tools/list` 应见 17 个工具
2. 完整手工清单（含各客户端连通、OAuth 全链路、双轨互斥）见 [docs/qa/p3-mcp-qa.md](../qa/p3-mcp-qa.md)

## 硬性约束 / Hard Rules（详见 CONSTRAINTS.md「MCP / AI 接口」）

- 日期参数：ISO 8601 + 必要处 `timezone`（IANA）；拒收无时区裸时间串
- RRULE 必须结构化对象 `{freq, interval, ...}`，不收裸字符串
- `get_events` 默认 now→+7 天，窗口上限 366 天
- 业务错误一律 `isError` 工具结果（带 code/message/hint），绝不走 JSON-RPC error
