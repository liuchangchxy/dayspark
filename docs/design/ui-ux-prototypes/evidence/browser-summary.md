# 浏览器测量摘要

最终复测：12 页全部通过横向溢出与控制台检查。原始逐页 JSON 在本次会话临时目录，未随仓库提交；下表为关键数值。

| 方向 | 页面 | 视口 | 横向溢出 | 控制台/页面错误 | Tabler | 零宽图标 | 内部裁切 |
|---|---|---|---|---|---|---|---|
| A Refined Native | action | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| A Refined Native | calendar | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| A Refined Native | todo | 1440×900 | 0 | 0 | loaded | 0 | todo-main 0×6px |
| A Refined Native | mobile | 390×844 | 0 | 0 | loaded | 0 | m-scroll 0×6px |
| B Precision | action | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| B Precision | calendar | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| B Precision | todo | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| B Precision | mobile | 390×844 | 0 | 0 | loaded | 0 | m-list 0×5px |
| C Signature | action | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| C Signature | calendar | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| C Signature | todo | 1440×900 | 0 | 0 | loaded | 0 | 0 |
| C Signature | mobile | 390×844 | 0 | 0 | loaded | 0 | m-scroll 0×10px |

## 首轮发现（已修复）

`a-refined-native` 日历：`.cal-scroll` 的 `clientHeight 671` / `scrollHeight 693`，21:00 标签位于 `top 910`，视口底部 900，容器 `overflow:hidden` 不可滚动。修复 `GRID_H` 686→662 后，最终内部裁切为 0，21:00 线可见。

## 判断

- 12 页 `document.documentElement.scrollWidth == clientWidth`，无元素右边界越过视口。
- 无 console error / page error。
- Tabler 字体全部 `loaded`，`tiZero=0`。
- 移动端固定快照的 5–10px 尾部裁切只发生在 `overflow:hidden` 的滚动容器内，截图中内容行完整；属于静态快照限制，不是布局溢出。
