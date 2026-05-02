# MCP Server Setup Guide / MCP 服务器配置教程

DaySpark includes a built-in **Model Context Protocol (MCP) server** that lets AI agents (like Claude Code) read and manage your calendar events and todos programmatically.
DaySpark 内置 **MCP（Model Context Protocol）服务器**，允许 AI Agent（如 Claude Code）通过编程方式读取和管理你的日历事件和待办。

---

## What is MCP? / 什么是 MCP？

MCP (Model Context Protocol) is an open standard that allows AI assistants to interact with external tools and data. By enabling DaySpark's MCP server, AI agents can:
MCP 是一种开放标准，允许 AI 助手与外部工具和数据交互。启用 DaySpark 的 MCP 服务器后，AI Agent 可以：

- **List calendars** — See all your calendars / 查看所有日历
- **List events** — Query events by date range / 按日期范围查询事件
- **Create events** — Add new calendar events / 创建新日历事件
- **List todos** — Query todos with optional filters / 查询待办（可选过滤）
- **Create todos** — Add new todos / 创建新待办
- **Complete todos** — Mark todos as done / 标记待办为完成

## Setup Steps / 配置步骤

1. Open **Settings → Advanced Features** and enable **MCP Server** / 打开 **设置 → 高级功能**，启用 **MCP 服务器**
2. The server starts on `localhost:3001` / 服务器在 `localhost:3001` 启动
3. Configure your AI agent to connect to it / 配置你的 AI Agent 连接到此地址

## Claude Code Configuration / Claude Code 配置

Add to your `.claude/settings.json` / 添加到 `.claude/settings.json`：

```json
{
  "mcpServers": {
    "dayspark": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sse", "http://localhost:3001/sse"]
    }
  }
}
```

## Using with Other Agents / 使用其他 Agent

The MCP server exposes an SSE endpoint at `http://localhost:3001/sse`. Any MCP-compatible client can connect to it.
MCP 服务器在 `http://localhost:3001/sse` 提供 SSE 端点，任何兼容 MCP 的客户端都可以连接。

## Notes / 注意事项

- The server only runs on desktop platforms (macOS, Windows, Linux) / 服务器仅在桌面平台运行
- It is not available on mobile or web / 移动端和 Web 端不可用
- All data stays local — no cloud relay / 所有数据保留在本地，不经云端中转
- The server starts/stops with the toggle in settings / 服务器随设置中的开关启停
