# MCP Server Setup Guide

DaySpark includes a built-in **Model Context Protocol (MCP) server** that lets AI agents (like Claude Code) read and manage your calendar events and todos programmatically.

## What is MCP?

MCP (Model Context Protocol) is an open standard that allows AI assistants to interact with external tools and data. By enabling DaySpark's MCP server, AI agents can:

- **List calendars** — See all your calendars
- **List events** — Query events by date range
- **Create events** — Add new calendar events
- **List todos** — Query todos with optional filters
- **Create todos** — Add new todos
- **Complete todos** — Mark todos as done

## Setup Steps

1. Open **Settings → Advanced Features** and enable **MCP Server**
2. The server starts on `localhost:3001`
3. Configure your AI agent to connect to it

## Claude Code Configuration

Add to your `.claude/settings.json`:

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

## Using with Other Agents

The MCP server exposes an SSE endpoint at `http://localhost:3001/sse`. Any MCP-compatible client can connect to it.

## Notes

- The server only runs on desktop platforms (macOS, Windows, Linux)
- It is not available on mobile or web
- All data stays local — no cloud relay
- The server starts/stops with the toggle in settings
