# DaySpark 交互模型原型 / Interaction model prototype

这是一个**可操作的真实交互原型**（纯 HTML/CSS/JS，无框架、无构建），用于在写生产 Flutter 之前，把 DaySpark 全产品的交互行为定义清楚并可被实际点击验证。

- 分支：`design/interaction-model-g0`（worktree `dayspark-g0`），与 G1 完全隔离
- **不含任何生产 Flutter 改动**
- 视觉语言：沿用仓库已冻结的 D Final（`DESIGN.md` 的 tokens：rail `#191C22`、canvas `#F5F6F8`、accent `#2457D6`，圆角 6/8/12，字阶 26/15/11–13，无渐变/无装饰动效）

---

## 1. 怎么打开

**方式 A（最快）**：用浏览器直接打开

```bash
open docs/design/interaction-model/index.html
```

`file://` 下一切功能可用（数据在内存里，刷新即回到种子数据）。

**方式 B（本地静态服务，便于手机尺寸真机看）**

```bash
cd docs/design/interaction-model
python3 -m http.server 8810
# 浏览器打开 http://localhost:8810/
```

**方式 C（手机视图）**：Chrome/Safari 开发者工具切到 390×844 设备模拟；或按方式 B 后在同一局域网的手机上打开 `http://<你的电脑 IP>:8810/`。

窗口宽度决定形态，与真实 App 的断点同义：

| 宽度 | 形态 |
|---|---|
| ≥ 1180px | 桌面双栏：待办页左侧列表 + 右侧详情窗格（`CORE_UX_SPEC` §4） |
| 900–1179px | 桌面单列：左侧 200px rail + 单列内容，详情整页 |
| < 900px | 手机：底部 4 个入口（今天 / 日历 / 待办 / 更多）+ 页头新建动作 |

---

## 2. 五分钟走一遍（推荐顺序）

桌面 1440×900：

1. **今天**页 → 顶部输入框打「买灯泡」→ Enter → 这条立刻出现在下方「未安排」预览里并高亮，计数 +1 → 点「未安排 · n 项」进列表看到全部。
2. **待办**页 → 行内输入框打「写周报」→ Enter（今天视图，会继承今天的截止）→ 勾选完成 → **已完成行内的「撤销」**（注意：待办回来，它原先占的时段也一起回来）。日视图输入框下方还有「计划这一天」：建待办并直接占用该日时段，截止保持为空。
3. **待办**页 1440 宽是双栏：点任意行，左边列表**不动**，右边出现详情窗格；点别的行换内容；右上「关闭」或 `Esc` 收起窗格。点副标题日期可跳任意月份。
4. 新建待办默认是 **Quick Create**（标题 + 截止 + 更多）；「更多」展开任务/时间/提醒/整理/内容。「安排时间」→ 选一个时段 → 切到**日历**周视图，看到虚线安排块；点它 → 进详情。
5. **日历** → 点某天空白时段 → sheet 三个出口（新建日程 / 安排待办 / 新建并安排）→ 新建日程 → 保存后回到日历，块出现在格子里。桌面可双击月视图空格直接建；手机点有事项的月格下钻。凌晨默认折叠，右下角可「回到现在」。
6. 详情页 → 只读；点「编辑」才进 composer；改标题 → 保存 → 回详情；切到**待办**和**今天**，标题同步。表单按 任务 / 时间 / 提醒 / 整理 / 内容 分区。
7. 详情「移到回收站」→ 去**回收站**恢复 → 回到原列表。
8. **设置** → 语言切 English、主题切深色 → 立刻生效；再切回来。

手机 390×844：底部四个入口（今天 / 日历 / 待办 / **更多**）——「更多」里是第一项「快速添加」，以及搜索、AI、标签、日历管理、回收站、设置。建一条 → 点行开整页详情 → 返回；待办行左滑删除并撤销；日历点格建日程。可点元素按有效命中区逐类测到 ≥48px（`reviewer-findings-r4.js` D6）。

**快速添加**：rail / 手机「更多」/ `Q`。打「明天下午三点 开会 1小时」→ 预览明说「将创建日程」与时段；打「明天 交报告」→「将创建待办 · 截止明天」；什么都不带日期 → 无截止待办。

键盘（桌面）：`N` 新建待办，`/` 搜索，`T` 回今天，`Esc` 关浮层/返回，`?` 看快捷键。

---

## 3. 目录

```
docs/design/interaction-model/
├── index.html              外壳（rail / 底部 nav / view 宿主）
├── css/app.css             全部样式与 D Final tokens
├── js/
│   ├── store.js            唯一数据源：种子数据 + 全部写操作（纯函数式改 state）
│   ├── event-ops.js        日程删除/编辑的唯一实现（重复范围只在这里问）
│   ├── todo-ops.js         待办完成的唯一实现（重复任务按实例）
│   ├── quick-add.js        一句话解析（时刻→日程，日期→截止，无日期→无截止待办）
│   ├── i18n.js             中英双语字典（切换即时生效）
│   ├── ui.js               page/row/sheet/modal/menu/toast/空态/骨架等构件
│   ├── util.js             日期格式化、断点判定
│   └── views/              action / quickadd / todo / calendar / composer / detail / search /
│                           library(tags,calendars,trash,about,feedback) / settings / chat / misc
├── tests/
│   ├── smoke.js            冒烟：启动、无横向溢出、按钮都有名字、路由可达、零控制台错误
│   ├── interactions.js     36 个真实操作场景（浏览器点击/输入/拖拽）
│   ├── surfaces.js         14 个功能面场景（标签/日历/回收站/账户/离线/手势…）
│   ├── reviewer-findings.js 20 条第一轮独立 Reviewer 发现的逐条回归
│   ├── reviewer-findings-r2.js 20 条第二轮独立 Reviewer 发现的逐条回归
│   ├── reviewer-findings-r3.js 24 条第三轮独立 Reviewer 发现的逐条回归
│   ├── reviewer-findings-r4.js 16 条第四轮独立 Reviewer 发现的逐条回归
│   └── debug/              调试与截图脚本（不参与门禁）
├── research/
│   ├── APP_SURFACE_V034.md 真实 Flutter 代码盘点（v0.34.0 基线，带 file:line 引用）
│   └── DOMAIN_BEHAVIORS.md 领域语义取证（15 域、108 处代码引用、20 条不变量）
├── COVERAGE.md             全产品页面/操作覆盖表（真实入口 → 原型路径 → 设计决定）
├── BEHAVIORS.md            关键操作行为定义（数据变 → 界面回 → 失败怎么办）
├── DIFF_VS_FLUTTER.md      与当前 Flutter 的实际差异清单（供 G2–G6）
├── DECISIONS_FOR_USER.md   真正需要你拍板的产品分歧（含推荐）
└── TEST_RESULTS.md         自动化真实操作测试及结果
```

---

## 4. 跑自动化验证

需要 `playwright-core` 与一份 Chromium（脚本里写死了本机缓存路径 `~/Library/Caches/ms-playwright/chromium-1243/...`，换机器需改 `CHROME` 常量）。

```bash
cd docs/design/interaction-model/tests
npm install            # 只装 playwright-core
node smoke.js              # 11 项冒烟
node interactions.js       # 36 个交互场景
node surfaces.js           # 14 个功能面场景
node reviewer-findings.js  # 20 条第一轮 Reviewer 发现回归
node reviewer-findings-r2.js # 20 条第二轮 Reviewer 发现回归
node reviewer-findings-r3.js # 24 条第三轮 Reviewer 发现回归
node reviewer-findings-r4.js # 16 条第四轮 Reviewer 发现回归
npm test                   # 八套一起跑（166 项）
```

加 `--headed` 可以看着浏览器跑；`--filter=<子串>` 只跑名字匹配的场景。结果与时间戳见 `TEST_RESULTS.md`。

---

## 5. 这个原型的边界（请按此验收）

**是**：真实状态、真实写入、真实跨页同步；每个页面有明确路径；核心任务可连续点击完成；创建后能看到对象；编辑后其它页面同步；展开能收起；取消能返回；按钮/图标/菜单/行都有动作；覆盖 loading/empty/error/disabled/offline/permission。

**不是**：生产 App；不连后端、不发通知、不做真实文件上传/ICS 解析/真实同步（用模拟延迟与结果 toast 表达状态）；不含 widget 深链；不含 legacy 重复数据迁移。逐条理由见 `COVERAGE.md` §7。

数据只存在内存中（语言/主题/启动页等**偏好**例外，存在 `localStorage`，刷新后保持）——记录数据本身刷新即恢复种子，这是刻意设计，方便反复验收同一条路径。

---

## 6. 已知的未决项

| 项 | 状态 |
|---|---|
| ~~桌面 master-detail~~ | **已按 `CORE_UX_SPEC.md` §4 实现**：≥1180 列表常驻 + 右侧详情窗格（选中而非路由）。见 `BEHAVIORS.md` A6 |
| 平台集成（widget 深链 / Android 返回键 / Web URL / 通知持久化） | 明确不在交互原型内；通知操作以模拟卡定义行为。见 `COVERAGE.md` §8 |
| 设计工具的在线协作（OpenDesign / DesignSync） | 本轮**无法访问**（无可用凭据/连接），因此原型是用本地 HTML/CSS/JS 手工实现的。视觉基线直接取自仓库冻结的 `DESIGN.md`（D Final tokens），未走在线设计项目。这是环境限制，不是选择。 |
