# DESIGN.md — Calendar Todo App Design System

AI 编码工具读此文件来保持 UI 一致性。

## Design Philosophy

功能导向的极简设计。参考标杆：Linear（克制用色）、Apple 日历（清晰实用）。
**拒绝"AI 味"：** 不大圆角、不渐变、信息密度优先。

## Colors

### Light Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #FAFAFA | 页面背景 |
| surface | #FFFFFF | 卡片/弹窗背景 |
| textPrimary | #1A1A2E | 主文字 |
| textSecondary | #6B7280 | 辅助文字 |
| accent | #2563EB | 按钮、选中态、链接 |
| accentHover | #1D4ED8 | 按钮悬停 |
| success | #16A34A | 成功状态 |
| warning | #EAB308 | 警告状态 |
| error | #DC2626 | 错误状态 |
| border | #E5E7EB | 边框、分割线 |

### Dark Mode
| Token | Hex | Usage |
|-------|-----|-------|
| background | #0F0F14 | 页面背景 |
| surface | #1A1A2E | 卡片/弹窗背景 |
| textPrimary | #E4E4E7 | 主文字 |
| textSecondary | #9CA3AF | 辅助文字 |
| accent | #3B82F6 | 按钮、选中态、链接 |
| border | #2D2D3A | 边框、分割线 |

## Typography

使用系统默认字体，不加自定义字体包。

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| headline | 20sp | w600 | 页面标题 |
| title | 16sp | w600 | 卡片标题、Section 标题 |
| body | 14sp | w400 | 正文 |
| caption | 12sp | w400 | 辅助说明、时间标签 |
| overline | 10sp | w500 | 极小标签 |

## Spacing

基础单位 4px，所有间距为 4 的倍数。

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | 紧凑间距 |
| sm | 8px | 列表项间距、卡片间距 |
| md | 12px | 内边距（紧凑） |
| lg | 16px | 卡片内边距、Section 间距 |
| xl | 24px | 页面边距 |
| xxl | 32px | 大间距 |

## Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| sm | 6px | 按钮、输入框 |
| md | 8px | 卡片 |
| lg | 12px | 弹窗、对话框（最大值） |

## Component Principles

1. 能用一个颜色不用渐变
2. 能用纯色图标不用 emoji
3. 信息密度优先——一屏显示尽量多的有用信息
4. 动画只用于状态切换（0.2s ease），不用于装饰
5. 阴影极少使用，用 border 区分层次
6. 最小触摸目标 48x48dp
7. 色彩对比度符合 WCAG 2.1 AA
