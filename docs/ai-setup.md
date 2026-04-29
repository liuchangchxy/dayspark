# AI Assistant Setup Guide

DaySpark's AI assistant lets you create events and todos using natural language. Just type "Meeting with John tomorrow 3pm" and the AI will parse it into a calendar event or todo.

## Supported Providers

DaySpark supports any OpenAI-compatible API:

| Provider | Base URL |
|----------|----------|
| OpenAI | `https://api.openai.com/v1` |
| Anthropic | `https://api.anthropic.com/v1` |
| DeepSeek | `https://api.deepseek.com/v1` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` |
| Moonshot (Kimi) | `https://api.moonshot.cn/v1` |
| Qwen (Tongyi) | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| GLM (Zhipu) | `https://open.bigmodel.cn/api/paas/v4` |
| Ollama (local) | `http://localhost:11434/v1` |
| LM Studio (local) | `http://localhost:1234/v1` |

## Setup Steps

1. Open **Settings → Advanced Features** and enable **AI Assistant**
2. Tap **AI Configuration**
3. Select your provider from the dropdown (or choose "Custom")
4. Enter your **API Key** (for local providers like Ollama, you can enter anything)
5. Tap **Detect Models** to auto-discover available models, or manually enter the model name
6. Select a model and save

## Usage

- Open the AI chat from the sparkle icon in the top-right corner
- Type requests in natural language, e.g.:
  - "明天下午3点开会"
  - "Remind me to buy groceries on Friday"
  - "Schedule a team standup every Monday 9am"
- The AI will create the event or todo automatically

## Tips

- For local models (Ollama, LM Studio), make sure the model is running before detecting
- Chat history is stored locally on your device
- You can clear chat history from the chat page menu
