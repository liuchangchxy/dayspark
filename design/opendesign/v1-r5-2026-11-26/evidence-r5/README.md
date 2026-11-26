# R5 evidence

所有截图由 `scripts/capture.py` 通过 Chrome DevTools Protocol 对最终构建产物实拍，不是设计板导出。

- 桌面 1440×1000：Today / Todos / Calendar / 历史 / 旧版重复 / 设置首页 / 账户与同步 / MCP / 小组件
- 平板 1024×768：Today / Calendar
- 手机 390×844：Today / 截止展开前与后 / Todos / Calendar 日 / 设置 / MCP
- 主题：浅色、暖灰、深色
- 前后对比：第四轮基线 vs R5（`before-after-*.png`）

复现：

```bash
python3 -m http.server 8137 --bind 127.0.0.1   # 在包根目录
python3 evidence-r5/scripts/capture.py          # 需 Chrome + websockets，路径按本机调整
```

`probe-results.txt` 记录真实操作断言与控制台状态。
