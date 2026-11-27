# R6 证据包

所有图片均为真实 Chrome（headless=new，CDP）渲染，不是设计稿拼贴。演示时间固定 2026-11-20 15:00。

## 目录

- `screens/` — 主索引 51 张（`final_shots.py … r6` 重拍，浅色 / 暖灰 / 深色，四档视口）+ 定点补图（`r3-*`、`polish-*`、`batch-*`），共 133 张。
- `baseline-r4/` — R4 基线 13 张（产物 `fe3aa531…9333`，同视口同状态，`final_shots.py … r4` 对 R4 构建重拍）。
- `compare/` — 12 组前后对比；桌面为上下堆叠（上基线、下 R6），手机为左右并排（左基线、右 R6）。
- `scripts/` — 可复跑的截图与操作脚本（含捕获文案、AI 动作、交互冒烟）。

## 截图索引（主集，screens/）

| 文件 | 视口 | 主题 | 状态 |
|---|---|---|---|
| `d-today.png` | 1440×1000 | 浅色 | 今天 · 任务/时间双栏 |
| `d-todos.png` / `d-todo-inbox.png` / `d-todo-date.png` | 1440 | 浅色 | 待办 全部 / 未安排 / 按日期 |
| `d-month.png` / `d-week.png` / `d-day.png` | 1440 | 浅色 | 月 / 周 / 日 |
| `d-settings.png` / `d-settings-data.png` | 1440 | 浅色 | 设置首页 / 数据与备份 |
| `d-detail.png` | 1440 | 浅色 | 待办详情（周报，420 抽屉） |
| `d-event-detail.png` | 1440 | 浅色 | 日程详情（牙医） |
| `d-capture.png` / `d-capture-expanded.png` | 1440 | 浅色 | 捕获解析 / 展开字段 |
| `d-search.png` | 1440 | 浅色 | 命令框（查「周报」） |
| `d-new.png` / `d-widgets.png` / `d-ai.png` | 1440 | 浅色 | 新建待办 / 小组件 / AI 提案卡 |
| `t-today.png` / `t-todos.png` / `t-week.png` / `t-detail.png` | 1024×768 | 浅色 | 平板四页 |
| `n-today-768.png` / `n-cal-768.png` / `n-detail-768.png` | 768×900 | 浅色 | 窄桌面（抽屉覆盖层） |
| `m-today.png` | 390×844 | 浅色 | 手机今天（现在条） |
| `m-todo.png` / `m-todo-all.png` / `m-date.png` | 390 | 浅色 | 手机待办三视图 |
| `m-cal.png` / `m-cal-month.png` / `m-week.png` | 390 | 浅色 | 手机日 / 月 / 周 |
| `m-settings.png` / `m-detail.png` / `m-event-detail.png` | 390 | 浅色 | 手机设置 / 待办详情 / 日程详情 |
| `m-capture.png` / `m-search.png` / `m-new.png` / `m-widgets.png` / `m-ai.png` | 390 | 浅色 | 手机捕获 / 搜索 / 新建 / 小组件 / AI |
| `d-warm-today.png` / `m-warm-today.png` | 1440 / 390 | 暖灰 | 今日 |
| `d-dark-today.png` / `d-dark-todos.png` / `d-dark-month.png` / `d-dark-week.png` / `d-dark-settings.png` / `d-dark-detail.png` | 1440 | 深色 | 桌面六页 |
| `m-dark-today.png` / `m-dark-cal.png` / `m-dark-settings.png` / `m-dark-detail.png` | 390 | 深色 | 手机四页 |

## 前后对比（compare/）

`compare-today-desktop.png`、`compare-todos-desktop.png`、`compare-month-desktop.png`、`compare-week-desktop.png`、`compare-settings-desktop.png`、`compare-detail-desktop.png`、`compare-today-mobile.png`、`compare-calendar-mobile.png`、`compare-settings-mobile.png`、`compare-today-dark-desktop.png`、`compare-month-dark-desktop.png`、`compare-today-dark-mobile.png`。

## 复跑

```bash
# 1) 截图（需要装有 Google Chrome；脚本会自建临时 profile 与 CDP 端口）
python3 scripts/final_shots.py 9670 /tmp/r6shots \
  "file:///<绝对路径>/dayspark-prototype.html" r6

# 2) 交互冒烟（23 条断言；会真实点击与按 Enter）
python3 scripts/smoke_r6.py
python3 scripts/capture_copy_check.py   # 捕获两条提交路径
python3 scripts/ai_actions_check.py     # AI 提案卡两个动作

# 3) 前后对比（需先生成 R4 基线截图到 /tmp/r4final）
python3 scripts/make_compare.py
```

脚本内的 `URL` 常量按需改成绝对路径；R4 基线截图使用 `final_shots.py ... r4` 对 R4 产物生成。`reshoot_after_polish.py` 是最后一轮修正（设置居中、深色时间轴点、短块把手、1024 捕获条）后的定点重拍。

## 说明

- 主集 51 张与 12 组对比的 R6 一侧，均由当前最终产物 `4dd2f92f…4351` 重新渲染（2026-11-27 第三轮）；R4 一侧由 R4 冻结产物 `fe3aa531…9333` 在同一视口与状态重拍，因此两侧尺寸一致。
- `r3-tags-list.png`、`r3-tag-edit-light/dark.png`、`r3-tags-after.png`、`r3-detail-attach.png`、`r3-m-detail-edit.png`、`r3-m-detail-bottom.png`、`r3-attach-failed.png`、`r3-cal-deadlines.png`、`r3-crossday-edit.png`、`r3-ctx-plan.png`、`r3-shortcuts.png`、`r3-m-tags.png`、`r3-vp-*.png` 是本轮新增的证据图。
- 视口补图已按“文件名 = 真实页面 + 真实主题 + 真实视口”逐张重拍并核对：`r3-vp-360-today/day/date/new.png`、`r3-vp-390-settings.png` 为手机外壳（`mobile:true`，720/780 宽），`r3-vp-768-week.png` 是 768 宽的周视图，`r3-vp-1024/1920-today.png` 为桌面今天。早期误拍的「360 宽桌面待办」「768 今天」「深色实为浅色」等图已替换。
- 截图前隐藏右下角「预览」胶囊，避免调试控件进入证据；实际体验时它默认可见。
- 每张截图前都校验 `innerWidth` 与 `document.body.dataset.protoTheme`，避免设备模拟残留或主题未生效。
