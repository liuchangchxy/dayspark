# D Final 实施账本

基线 main: 03ae0cf8fff089c27c5ce1d3ef2d9ab48be92c91；设计 PR #71 dc3715c98a0762365d5b09c79087f845b07961b9。

## 接缝与任务简报
- Action：仅 action_section.dart 及独立 inspector/row 组件；保留投影及完成 Provider；消费主题。
- Calendar：仅 calendar widgets 与独立 deadline lane；保留 kalender 引擎及适配层；消费主题。
- Todo：仅 todo_list_tile.dart；保持完成与 occurrence selector；Home 保留筛选/排序。
- Shell/Theme（主实现者）：Home 响应式侧栏与底栏，统一内容起点；现有主题值收敛到 D Final，无新增框架。
- 共享 l10n 由主实现者整合，子任务不同时改 ARB。

## 验收
- [ ] Action / Calendar / Todo / Shell / Theme 完整实施
- [ ] Desktop 1440x900 三页 + Mobile 390x844 Action 真渲染截图
- [ ] 对拍 D Final + Impeccable 一轮精修并确认
- [ ] Light/Dark、长文本、核心交互、布局边界
- [ ] dart analyze . / flutter test / 现有 CI
- [ ] 单 PR 推送，不合并

## 裁定
- 冻结设计已确定，本轮不重复产品设计；沿用现有业务入口 → 若误解映射会导致视觉或交互验收失败，须以截图和回归检查。
