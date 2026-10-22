# 工具与实际调用记录

这份记录只写**真的执行过**的工具。未安装、未调用、仅阅读说明的，单列在最后，避免把“知道有这个工具”写成“用过”。

## 1. 实际调用的 Skill

### Impeccable（已调用）

- 通过 Skill 工具加载 `impeccable`。
- 执行 `impeccable context`：返回 `NO_PRODUCT_MD` / `PRODUCT_INIT_REQUIRED`。因为用户明确要求不修改 DaySpark 仓库，未执行 `impeccable init`，改为直接读仓库 `DESIGN.md`、`SPEC.md` 和现有主题/页面，作为设计约束。
- 按 Impeccable critique 协议启动两个隔离评审 Agent：
  - Assessment A：逐页看 12 张截图，Nielsen 十项评分 + P0–P3。
  - Assessment B：Impeccable detector + 浏览器证据。
- 最终 detector 命令（真实执行，三份 JSON 保留）：

```bash
REPO=/path/to/dayspark
"$REPO/.claude/skills/impeccable/scripts/impeccable" detect --json "$PWD/a-refined-native"
"$REPO/.claude/skills/impeccable/scripts/impeccable" detect --json "$PWD/b-precision"
"$REPO/.claude/skills/impeccable/scripts/impeccable" detect --json "$PWD/c-signature"
```

最终结果：

| 方向 | 退出码 | Findings | 构成 |
|---|---|---|---|
| A | 2 | 2 | `side-tab` warning ×2（`style.css:231` 图例色块、`:265` 事件类别色条） |
| B | 2 | 5 | `side-tab` warning ×1（`style.css:268`）+ `repeating-stripes-gradient` advisory ×4 |
| C | 2 | 8 | `cream-palette` warning ×4 + `repeating-stripes-gradient` advisory ×4 |

退出码 2 表示“扫描完成且有 finding”，不是崩溃。原始 JSON：

- `evidence/detector-a-refined-native.json`
- `evidence/detector-b-precision.json`
- `evidence/detector-c-signature.json`

误报判断：

- `side-tab` 命中的是日历事件块的类别色条，不是卡片装饰。
- `repeating-stripes-gradient` 命中的是密度条/光带里“安排（不占整块时间）”的斜线编码，是功能图例。
- `cream-palette` 是 C 方向的核心选择（暖纸 + 宋体 + 编年账本），不是无意落入默认模板。
- 链接 CSS 的 finding 被 detector 归到 HTML `line 0`，这是工具对 linked CSS 的报告限制。

### design-taste-frontend（已调用）

- 通过 Skill 工具加载。
- 用它做反模板检查：字体层级、对比、间距、圆角一致性、避免渐变/玻璃/卡片堆叠、避免“三张等宽 feature card”式 AI 版式。
- 该 skill 偏 landing/portfolio，不直接覆盖产品 UI；只取与当前“Operate”界面兼容的规则，未照搬其 landing 结构。

## 2. 实际调用的 Agent

- Assessment A（设计评审）：读取 12 张最终截图，输出方向特异性判断、Nielsen 0–4 评分、每方向 3–5 条 P0–P3、优点与 AI 模板痕迹。
- Assessment B（证据评审）：执行 Impeccable detector；用 agent-browser + headless Chrome 对 12 页做溢出、裁切、控制台、字体加载测量；首轮发现 A 日历底部 22px 裁切。
- 两个 Agent 的结论独立，未共用结果；最终修改由主会话完成。

首轮关键证据（A 日历）：

> `.cal-scroll` 的 `clientHeight 671`，`scrollHeight 693`，21:00 标签在 `top 910`，视口底部 900；容器 `overflow:hidden` 且不可滚动。

修复：A 的 `GRID_H` 686→662，重渲染后内部裁切测量为 0。

## 3. 实际调用的浏览器与截图工具

### Headless Chrome

统一脚本：`shot.sh`（本目录）

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --allow-file-access-from-files \
  --window-size=1440,900 --force-device-scale-factor=1 \
  --screenshot=shots/a-desktop-action.png \
  --virtual-time-budget=6000 \
  --user-data-dir=/tmp/ds-chrome-$$ \
  "file://$PWD/a-refined-native/action.html"
```

- 桌面：1440×900
- 移动：390×844（headless Chrome 有 500px 最小 layout viewport，移动原型通过 `body[data-screen="mobile"]{width:390px}` 固定；画廊的移动截图用临时 390px body 副本验证后删除）
- 最终 12 张：`shots/a-*`、`shots/b-*`、`shots/c-*`
- 画廊：`shots/index-desktop.png`、`shots/index-mobile.png`
- 总览：`shots/contact-sheet.png`（Pillow 合成，字体 `/System/Library/Fonts/Supplemental/Arial Unicode.ttf`，避免中文标签变方框）

### agent-browser 测量

系统已安装 `/opt/homebrew/bin/agent-browser`。用它加载每个原型并执行 JS 测量：

- 脚本：本次会话临时目录中的 `measure.sh` / `internal.sh`（未随仓库提交）
- 结果摘要：`evidence/browser-summary.md`
- 首轮与最终结果原始 JSON：本次会话临时目录（未随仓库提交，摘要中保留关键数值）
- 本地服务：`python3 -m http.server 8766 --directory docs/design/ui-ux-prototypes`，结束后停止

最终 12 页结论：

- 无横向溢出（`documentElement.scrollWidth == clientWidth`，无元素右边界越过视口）
- 无 console error / page error
- Tabler 字体 `loaded`，`tiZero=0`（无零宽图标）
- 无本地资源 404（仅 favicon）
- A 日历内部裁切 0；A/B/C 移动端滚动容器仍有 5–10px 尾部留白裁切，属于固定快照，不是内容缺失

## 4. 实际调用的其他工具

- **Pillow（Python）**：生成 `shots/contact-sheet.png` 与画廊移动端验证图。
- **Python 标准库 HTTP server**：本地静态服务，供 agent-browser 访问；未引入框架。
- **Tabler Icons 3.31.0**：下载并 vendor 到 `assets/tabler/`，本地 CSS + woff2/woff。原因是 headless Chrome 访问外部 CDN 不稳定，B 方向一度出现图标缺字；vendor 后 12 页 `fontTabler=true`、零宽图标 0。

## 5. 已检查但未调用 / 不可用

- **baoyu-design（P0）**：当前 Skill 列表中不存在，未安装、未调用。没有伪造其输出。
- **frontend-design / Claude Design（P0）**：当前 Skill 列表中不存在，未调用。
- **UI/UX Pro Max（P1）**：当前 Skill 列表中不存在，未调用。
- **Playwright（P1）**：Python `playwright` 包不存在；Node 环境也未安装 Puppeteer。没有为它改系统配置或装额外基础设施，改用已存在的 agent-browser + headless Chrome 完成同等验证。
- **Figma / 设计 MCP**：没有可用的设计类 MCP；`searxng` MCP 存在但本任务不需要联网检索，未调用。
- **Impeccable `init`**：未执行。原因是会写 PRODUCT.md 到仓库，而本轮明确“不修改 DaySpark 仓库源码”；改为读取现有 `DESIGN.md`/`SPEC.md`。
- **真实设备 / Flutter 渲染**：未运行；本轮范围是视觉原型，不实施 Flutter。

## 6. 可复现

```bash
cd docs/design/ui-ux-prototypes
python3 -m http.server 8766
# 用 agent-browser 或浏览器打开 http://127.0.0.1:8766/index.html
```

或直接打开 `index.html`。等待 Chat-8 审定。

## 7. D · DaySpark Final（追加）

2026-10-23，在 A/B/C 之后制作最终候选 D，仍只做视觉原型。

### 实际执行的检测

```bash
"/Users/chang/Desktop/Code/dayspark/.claude/skills/impeccable/scripts/impeccable" detect --json /tmp/dayspark-ui-design/d-final
```

- 退出码 0，`[]`。首轮曾出现 3 条 `side-tab`（日历事件类别色条）与 1 条 `layout-transition`（检查器 padding 过渡），均已通过改为类别圆点/空心方点、移除布局过渡消除。
- 原始 JSON：`/tmp/dayspark-ui-design/detector-d-final.json`。

### 浏览器测量

最终四页在 1440×900 / 390×844 实测：

| 页面 | 横向溢出 | 控制台/页面错误 | Tabler 字体 | 零宽图标 | 内容贴合 |
|---|---|---|---|---|---|
| Action | 0 | 0 | loaded | 0 | 底 866 / 878 |
| Calendar | 0 | 0 | loaded | 0 | 网格 636 / 652 |
| Todo | 0 | 0 | loaded | 0 | 底 866 / 878 |
| Mobile | 0 | 0 | loaded | 0 | 底 779 / 782 |

桌面检查器打开时 Action 内容右缩 372px，行尾不再被浮层遮挡；关闭/Esc 恢复全宽。

### 评审

- 两个隔离评审 Agent：一轮 Impeccable critique（Nielsen + P0–P3），一轮 design-taste-frontend 反模板检查。
- 修复后终审：无 P0/P1；确认 7 项 B 问题全部达成（Action 非表格、Todo 去列、检查器按需、移动端 A 节奏、深色侧栏去后台感、克制的品牌细节、标签不冗余）。
- 剩余 P2/P3（已记录在 `d-final/README.md`）：页面栅格对齐、10px 级辅助字、Action 时间线为 7/12 切片（有“完整日程”入口）、移动端 Action 只承担“接下来”。

### 截图

`d-final/shots/d-desktop-action.png` / `d-desktop-calendar.png` / `d-desktop-todo.png` / `d-mobile-action.png`。

未运行 Flutter，未修改业务源码。
