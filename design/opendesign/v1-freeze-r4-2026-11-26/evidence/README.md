# 第四轮证据

`run_all.sh` 会把本包原型复制到 `/tmp/r4-final/dayspark-prototype.html`，然后逐个运行脚本。每个脚本使用独立 Chrome profile 与端口，输出到指定目录。

## 快速运行

```bash
./run_all.sh /tmp/r4-evidence-out
```

## AI 重复安排两项

`ai_repeat_plan.txt` 与 `ai_repeat_requires_instance.txt` 由 `agent4_t5.py` / `agent4_t8.py` 生成。它们使用本地 HTTP 服务与固定调试端口：

```bash
python3 -m http.server 8765 --directory /tmp/r4-final
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --headless=new --disable-gpu --remote-debugging-port=9333 \
  --user-data-dir=/tmp/ds-agent4 --window-size=1440,1000 about:blank &
python3 agent4_t5.py
python3 agent4_t8.py
```

`agent4_cdp.py` 中的 `open_app` 默认读取 `http://127.0.0.1:8765/index.html`。

## 结果文件

- `results/backup_roundtrip.txt`：真实导出文件 → 清空 localStorage → 重载 → `input[type=file]` 合并 → 刷新后复读。
- `results/drag_delta.txt`：+30 → −30 回到原位；再 +60 只移动 60 分钟，证明不累计。
- `results/repeat_detail_done.txt`：详情无绑定实例时强制选择；撤销也需显式选实例。
- `results/qa_force.txt`：快速添加四种输入的真实写入数据。
- 其余每个文件对应验收记录表中的一行或一组。
