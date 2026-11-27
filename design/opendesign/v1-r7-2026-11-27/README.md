# DaySpark R7 · 全局交互收敛与全功能补齐

基线：PR #119 / R6 最终提交 `95b63eb`，R6 目录与产物原样保留（`design/opendesign/v1-r6-2026-11-27`）。本轮只在这个独立目录里增量修改，未动 Flutter、未合并 PR、未改视觉方向。

## 直接体验

- R7：http://127.0.0.1:8123/dayspark-prototype.html
- R6（对照）：http://127.0.0.1:8765/dayspark-prototype.html

两个服务都指向各自目录，可在两个标签页里同条件来回比较。演示时间固定 **2026-11-20 15:00**。

## 文档索引

| 顺序 | 文件 | 用途 |
|---|---|---|
| 1 | `DAYS_PARK_ACCEPTANCE_ROUND7.md` | 本轮真实验收：28 条规则断言、R6 回归复跑、截图与对比 |
| 2 | `CHANGES_R7.md` | 改了什么、解决什么问题、相比 R6 的实际改善、真实剩余问题 |
| 3 | `dayspark-coverage-map.md` | 功能覆盖映射（沿用 R4/R6 结论，R7 补功能项） |
| 4 | `DAYS_PARK_PRODUCT_SPEC.md` | 产品规格（自 R6 原样收录，未改） |
| 5 | `DAYS_PARK_209_DECISIONS.md` | 209 项裁定（未改） |
| 6 | `DAYS_PARK_UI_R6_SPEC.md` | R6 视觉契约（本轮视觉语言未变，继续有效） |
| 7 | `R6_README.md` / `CHANGES_R6_BASELINE.md` / `DAYS_PARK_ACCEPTANCE_ROUND6.md` | R6 基线记录，保留作对照 |
| 8 | `dayspark-prototype.html` / `index.html` | 单文件可交互原型（构建产物） |
| 9 | `prototype-src/` | 源码：16 个脚本 + `host.css` + `build.py` |
| 10 | `evidence-r7/` | 51 张主集截图、13 张 R6 基线、12 组前后对比、可复跑脚本 |

## 构建

```bash
cd design/opendesign/v1-r7-2026-11-27
python3 prototype-src/build.py .
```

- 产物 SHA-256：`c9c3711ee9c55fe6d80c3f8a81922720eb3a865349cea43038822d73453ae957`
- 产物大小：1,196,450 bytes，16 个脚本
- R6 基线产物：`4dd2f92f2f80e6b076fa9e3588325c3b24a767dee9de6b7d2ff438c7b8244351`

## 边界

- 截图与操作均在 Chrome（headless + CDP）完成；Safari / Firefox、真实设备未验证。
- 同步、通知投递、原生小组件仍为原型模拟（既定边界）；AI 对话为内置示例。
- 本轮只补正式产品已有、用户可见且原型缺失的能力；未扩产品范围。
