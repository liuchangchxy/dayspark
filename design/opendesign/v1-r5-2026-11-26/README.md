# DaySpark · R5 UI/UX 交付包

> 基线：PR #117 / `cad5686a` / 第四轮产物 `65fdf776`  
> 本轮：全产品 UI/UX 视觉与交互优化，复用第四轮计划执行、重复实例、提醒、快速添加、备份与 AI Key 语义。  
> 状态：**验收候选**，不是最终冻结。未修改 Flutter，未合并 PR #113。

## 打开

```bash
cd design/opendesign/v1-r5-2026-11-26
python3 -m http.server 8137 --bind 127.0.0.1
open http://127.0.0.1:8137/dayspark-prototype.html
```

直接从正常产品首页（今天）开始。右下角「预览」胶囊可切换桌面 / 手机 / 主题 / 小组件 / 重置；数据保存在本机 `localStorage`。

单文件版本：`dayspark-prototype.html` 与 `index.html` 内容相同，均可离线打开。

## 产物

| 文件 | 说明 |
|---|---|
| `dayspark-prototype.html` / `index.html` | 最终单文件可交互原型 |
| `dayspark-spec.html` | 设计母版（组件、状态、页面与 R5 CSS） |
| `prototype-src/` | 构建源：`build.py` + `host.css` + `host.js` + `flows-*.js` |
| `DAYS_PARK_PRODUCT_SPEC.md` | 产品规格 FROZEN v1.0 rev.5 |
| `DAYS_PARK_UI_R5_SPEC.md` | R5 视觉与体验契约 |
| `DAYS_PARK_ACCEPTANCE_ROUND5.md` | 真实操作结果、截图索引、已知边界 |
| `dayspark-coverage-map.md` | 能力与 surface 覆盖表 |
| `evidence-r5/` | 22 张最终截图、`scripts/capture.py`、`probe-results.txt` |

## 构建

```bash
cd prototype-src
python3 build.py /tmp/ds-r5
```

## 校验

- `dayspark-prototype.html` SHA-256：`d79985e67d2ec3e7f079c5783a7ae59225d876849f872c3ecb1dbc6257ec1427`
- 字节数：1,118,589
- 构建源：15 个脚本文件；产物 1,020,525 字符
- 截图：1440×1000 桌面、1024×768 平板、390×844 手机；浅色 / 暖灰 / 深色
- 控制台：`errors []`，`Proto.lastEnhancerError = null`

## 已知边界

- MCP 连接、OAuth、通知投递与原生小组件为原型模拟；不实现真实服务端。
- 平板用 1024×768 视口验收，没有独立平板设备按钮；缩放浏览器窗口即可。
- 第四轮完整 36 条回归未全部重跑；本轮重跑与改动相关的 8 组脚本和 R5 专项探针。
- 旧脚本 `repeat_detail_done.py` 仍期待旧的二次实例选择器；当前撤销行为直接作用于已绑定实例，功能正确，脚本未更新。
