# DaySpark R6 · 全产品 UI/UX 精细打磨

本目录是 R6 轮次的独立产物：在第四轮评审包（PR #117，`v1-freeze-r4-2026-11-26`）的**同一个可交互原型**上，把成熟度、密度、字阶、对齐、层级、组件状态与文案精修到可直接体验的程度。**不换视觉方向、不重做导航、不改产品范围、不删能力、不改 Flutter、不合并任何 PR。**

- 视觉基线：PR #113（`ui/converge`）的白纸 / 墨 / 朱砂语言、系统字体、顶栏三入口、手机四入口 Dock、基础组件形态全部保留。
- 产品与语义基线：PR #117 的产品规格 rev.4、209 项裁定、模型收敛与第四轮验收；本轮只改呈现层，以及三处与文案/动作一致性直接相关的交互修正（见 `CHANGES_R6.md`）。
- 本轮不是最终冻结，也不进入 Flutter 实现；是否定稿由你体验后决定。

## 直接打开

双击 **`dayspark-prototype.html`**（或同内容的 `index.html`）即可，无需构建、无外部依赖、无需联网。

- 演示时间固定为 **2026-11-20（周五）15:00**；数据为内置示例，可随意勾选、拖动、编辑，刷新后恢复。
- 右下角是安静的「预览 · 桌面」胶囊：点开可切桌面/手机、看小组件、打开演示与快捷键、重置数据。截图与验收时该控件被隐藏，实际体验时默认可见。
- 手机版既可用胶囊切到「手机」，也可把窗口缩到 720px 及以下；桌面抽屉在 ≤1200px 改为覆盖层。

## 文档索引

| 顺序 | 文件 | 用途 |
|---|---|---|
| 1 | `DAYS_PARK_ACCEPTANCE_ROUND6.md` | 本轮真实验收：23 条连续操作、51 张截图、12 组前后对比、逐项结论与未执行项 |
| 2 | `DAYS_PARK_UI_R6_SPEC.md` | R6 视觉契约：令牌、字阶、间距、断点、组件语法、页面规则、主题、文案原则 |
| 3 | `CHANGES_R6.md` | 实际改了什么、为什么改、真实遗留问题 |
| 4 | `dayspark-coverage-map.md` | 13 个功能域的覆盖映射（沿用 R4 结论，R6 只做界面层增补） |
| 5 | `DAYS_PARK_PRODUCT_SPEC.md` | 产品规格 v1.0 rev.4（自 R4 原样收录，未改） |
| 6 | `DAYS_PARK_MODEL_CONVERGENCE.md` | 模型收敛：每个事实的唯一写入路径（未改） |
| 7 | `DAYS_PARK_209_DECISIONS.md` | 209 项裁定（未改） |
| 8 | `DAYS_PARK_RESTORED_CAPABILITIES.md` | 第三轮恢复的能力清单（未改） |
| 9 | `DAYS_PARK_ACCEPTANCE_ROUND4.md` | 第四轮 36 条真实入口操作记录（功能基线） |
| 10 | `dayspark-prototype.html` | 单文件可交互原型（构建产物） |
| 11 | `dayspark-spec.html` | 设计母版（88 屏 / 360 变体 / 39 个表面 + R6 覆盖层） |
| 12 | `prototype-src/` | 原型源码：15 个脚本 + `host.css` + `build.py` |
| 13 | `evidence-r6/` | 截图、基线、前后对比、可复跑的 CDP 脚本 |

## 构建与校验

```bash
cd design/opendesign/v1-r6-2026-11-27
python3 prototype-src/build.py /tmp/dayspark-r6
# 产物 /tmp/dayspark-r6/dayspark-prototype.html
```

- 原型 SHA-256：`a247275161f6c0a280e46b2c896ad3e9c6f95bbb52ec61cf80e8de289b64d940`
- 母版 SHA-256：`dadaf6af297270d9e0d14c3c3923462c0b464e13480badaa74829bf1a3405515`
- 原型由 15 个脚本构建；产物 1,054,260 bytes（UTF-8；构建器报告 957,263 字符）。
- 重复执行 `build.py` 到不同目录得到同一 SHA，可复现。
- 基线（R4，PR #117）：`fe3aa531…9333`；前后对比均以该产物为「前」。

## 本轮的真实边界

- 截图与操作均在 **Chrome（headless + CDP）** 上完成；1440×1000、1024×768、768×900、390×844 四档，浅色/暖灰/深色三种主题。Safari / Firefox 未验证。
- 同步、通知投递、原生小组件仍是原型模拟（既定边界）；AI 对话为内置示例，不请求真实模型。
- 本轮复验了 23 条跨页连续操作（`DAYS_PARK_ACCEPTANCE_ROUND6.md`），没有重跑第四轮 36 条全量功能回归；功能语义以 R4 验收为准。
- `dayspark-spec.html` 中 R6 覆盖层集中在样式末尾（`R6 · 成熟度精修`），便于逐条对照与回退。
