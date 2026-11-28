# R7 证据包

全部图片为真实 Chrome（headless=new，CDP）渲染。演示时间固定 2026-11-20 15:00。

## 目录

- `screens/` — 51 张主集（`final_shots_r7.py 9791 <out> <file-url> r6`）。
- `screens-fixes/` — 38 张第二轮专项（`r7_shots_fixes.py`）：六项修复涉及的桌面/手机页面、时间槽、重复选择器、筛选菜单、小组件明暗。
- `baseline-r6/` — 13 张 R6 基线（产物 `4dd2f92f…4351`，同视口同状态）。
- `compare/` — 12 组 R6 → R7 前后对比（桌面上下、手机左右）。
- `r4-port/` + `r4-results-final/` — R4 原有 36 条路径在 R7 产物上的复跑与结果；`r4-baseline-results/` 是同一批脚本的 R4 基线。
- `scripts/` — 可复跑脚本：
  - `r7_fixes_check.py` — 51 条：六项缺陷修复 + 任意重复间隔（含 每 N 月/年计数）+ ICS 往返
  - `r7_event_tags_check.py` — 18 条：日程标签（桌面/手机）与事件附件
  - `r7_paths_check.py` — 16 条：备份往返（含「合并」确认）与行菜单安排
  - `drag_r7.py` — 8 条：分钟级拖动/缩放（R7 日列 2 px/分钟）
  - `r7_rules_check.py` — 28 条共享规则断言
  - `r7_focus_check.py` — 日期复位、详情直改、偏好持久化、计划返回
  - `r7_detail_fields.py` — 只读详情写入、手机新建入口、新建页 Esc 保护
  - `smoke_r6.py` / `ai_actions_check.py` / `capture_copy_check.py` — R6 回归
  - `final_shots_r7.py` / `make_compare_r7.py` — 截图与对比

## 复跑

```bash
python3 -I evidence-r7/scripts/r7_rules_check.py
python3 -I evidence-r7/scripts/smoke_r6.py
python3 -I evidence-r7/scripts/final_shots_r7.py 9791 evidence-r7/screens \
  "file://$(pwd)/dayspark-prototype.html" r6
```

对比图需要 Python 的 Pillow（`python3 -m pip install pillow`），并设置：
`R4_SHOTS=evidence-r7/baseline-r6 R6_SHOTS=evidence-r7/screens python3 evidence-r7/scripts/make_compare_r7.py`。
