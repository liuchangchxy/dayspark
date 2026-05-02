# AI Assistant Setup Guide / AI 助手配置教程

DaySpark's AI assistant lets you create events and todos using natural language. Just type "Meeting with John tomorrow 3pm" and the AI will parse it into a calendar event or todo.
DaySpark 的 AI 助手可以用自然语言创建事件和待办。输入"明天下午 3 点和 John 开会"，AI 会自动解析为日历事件或待办。

---

## Supported Providers / 支持的服务商

DaySpark supports any OpenAI-compatible API:
DaySpark 支持任何 OpenAI 兼容的 API：

| Provider / 服务商 | Base URL |
|----------|----------|
| OpenAI | `https://api.openai.com/v1` |
| Anthropic | `https://api.anthropic.com/v1` |
| DeepSeek | `https://api.deepseek.com/v1` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` |
| Moonshot (Kimi) | `https://api.moonshot.cn/v1` |
| Qwen (Tongyi) | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| GLM (Zhipu) | `https://open.bigmodel.cn/api/paas/v4` |
| Ollama (local / 本地) | `http://localhost:11434/v1` |
| LM Studio (local / 本地) | `http://localhost:1234/v1` |

## Setup Steps / 配置步骤

1. Open **Settings → Advanced Features** and enable **AI Assistant** / 打开 **设置 → 高级功能**，启用 **AI 助手**
2. Tap **AI Configuration** / 点击 **AI 配置**
3. Select your provider from the dropdown (or choose "Custom") / 从下拉菜单选择服务商（或选"自定义"）
4. Enter your **API Key** (for local providers like Ollama, you can enter anything) / 输入 **API Key**（本地模型如 Ollama 可以随意输入）
5. Tap **Detect Models** to auto-discover available models, or manually enter the model name / 点击 **探测模型** 自动发现可用模型，或手动输入模型名称
6. Select a model and save / 选择模型并保存

## Usage / 使用方法

- Open the AI chat from the sparkle icon in the top-right corner / 点击右上角闪光图标打开 AI 聊天
- Type requests in natural language, e.g. / 用自然语言输入请求，例如：
  - "明天下午3点开会"
  - "Remind me to buy groceries on Friday"
  - "Schedule a team standup every Monday 9am"
- The AI will create the event or todo automatically / AI 会自动创建事件或待办

## Tips / 提示

- For local models (Ollama, LM Studio), make sure the model is running before detecting / 本地模型请确保模型正在运行
- Chat history is stored locally on your device / 聊天记录仅存储在本地设备
- You can clear chat history from the chat page menu / 可以从聊天页菜单清除聊天记录
