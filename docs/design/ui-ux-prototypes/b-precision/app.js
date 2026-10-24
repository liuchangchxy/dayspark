(() => {
  const D = window.DS;
  const CAT = { work: '#2b5ce6', life: '#1f7a57', product: '#7448b8', finance: '#a9670a', term: '#a9670a' };
  const tagClass = { 工作: 'blue', 产品: 'purple', 财务: 'orange', 生活: 'green' };
  const ic = (n) => `<i class="ti ti-${n}"></i>`;
  const tag = (t) => `<span class="tag ${tagClass[t] || ''}">${t}</span>`;

  const side = (active) => `
    <aside class="rail-dark">
      <div class="brand"><div class="logo">${ic('sparkles')}</div><div><div class="nm">灵光</div><div class="sb">DAYSPARK</div></div></div>
      <div class="ws">${ic('box')}个人工作区${ic('chevron-down')}<span class="chev"></span></div>
      <div class="rail-sec">工作区</div>
      <nav class="rail-nav">
        <div class="rn ${active === 'action' ? 'on' : ''}" style="margin-left:0">${ic('sun')}今日执行<span class="kbd">G A</span></div>
        <div class="rn ${active === 'calendar' ? 'on' : ''}">${ic('calendar')}日历<span class="kbd">G C</span></div>
        <div class="rn ${active === 'todo' ? 'on' : ''}">${ic('checkbox')}待办<span class="cnt">19</span></div>
      </nav>
      <div class="rail-sec">列表</div>
      <nav class="rail-nav">
        ${D.lists.map((l) => `<div class="rn">${ic(l.icon)}${l.name}<span class="cnt">${l.count}</span></div>`).join('')}
      </nav>
      <div class="rail-sec">标签</div>
      <nav class="rail-nav">
        ${D.tags.map((t) => `<div class="rn"><span class="dot" style="background:${CAT[t.color === 'blue' ? 'work' : t.color === 'purple' ? 'product' : t.color === 'orange' ? 'finance' : 'life']}"></span>${t.name}<span class="cnt">${t.count}</span></div>`).join('')}
      </nav>
      <div class="rail-foot">
        <div class="rf-avatar">常</div>
        <div class="rf-txt"><b>已同步</b>15:40 · 3 台设备</div>
        <span class="sync-dot"></span>
      </div>
    </aside>`;

  const top = (label, meta) => `
    <header class="topbar">
      <div class="crumbs"><span>灵光</span>${ic('chevron-right')}<b>${label}</b>${meta ? `<span class="badge">${meta}</span>` : ''}</div>
      <div class="search">${ic('search')}<span>搜索任务与事件</span><span class="k">⌘K</span></div>
      <div class="top-right">
        <button class="ib">${ic('bell')}</button>
        <button class="ib">${ic('settings')}</button>
        <button class="ib">${ic('help-circle')}</button>
        <button class="btn">${ic('plus')}新建</button>
      </div>
    </header>`;

  const status = () => `
    <div class="statusbar">
      <span>6 事件 · 5 安排 · 2 截止</span>
      <span class="r"><span>本地优先</span><span>已同步 15:40</span><span>v0.28.0</span></span>
    </div>`;

  const density = () => {
    const start = 6 * 60, end = 22 * 60, span = end - start;
    const blocks = D.timeline.filter((t) => t.type !== 'deadline').map((t) => {
      const s = hm(t.start), e = hm(t.end);
      const c = CAT[t.cat] || '#2b5ce6';
      return `<span class="density-block ${t.type === 'alloc' ? 'alloc' : ''}" style="left:${(s - start) / span * 100}%;width:${Math.max(0.8, (e - s) / span * 100)}%;--c:${c}"></span>`;
    }).join('');
    const now = (D.today.nowMinutes - start) / span * 100;
    return `<div class="density">
      <div class="density-label">今日密度<br>06 - 22</div>
      <div style="flex:1">
        <div class="density-track">${blocks}<span class="density-now" style="left:${now}%"></span></div>
        <div class="density-axis"><span>06</span><span>09</span><span>12</span><span>15</span><span>18</span><span>21</span></div>
      </div>
      <div class="density-key">
        <span><i class="k-solid"></i>事件</span>
        <span><i class="k-hatch"></i>安排</span>
        <span><i class="k-now"></i>现在</span>
      </div>
    </div>`;
  };

  const actRow = (o) => `
    <div class="row ${o.overdue ? 'overdue' : ''} ${o.sel ? 'sel' : ''}">
      <span class="time">${o.time}</span>
      <span class="kind ${o.kindClass}">${ic(o.icon)}</span>
      <span class="title">${o.title}${o.meta ? `<span class="m">${o.meta}</span>` : ''}</span>
      <span class="tags">${(o.tags || []).map(tag).join('')}</span>
      <span class="due ${o.dueClass || ''}">${o.due || ''}</span>
      <span class="ck ${o.round ? 'round' : ''}" style="${o.nock ? 'border-color:transparent' : ''}"></span>
    </div>`;

  const renderAction = () => {
    const sched = D.timeline.slice(0, 6).map((t) => ({
      time: t.start,
      icon: t.type === 'event' ? 'calendar-event' : 'checkbox',
      kindClass: t.type === 'event' ? 'evt' : 'alloc',
      title: t.title,
      meta: t.meta,
      tags: [t.cat === 'work' ? '工作' : t.cat === 'life' ? '生活' : '产品'],
      due: `${hm(t.end) - hm(t.start)} 分`,
      nock: true,
    }));
    const overdue = D.todos.overdue.map((t) => ({ time: t.due.replace('月', '/').replace('日', ''), icon: 'alert-triangle', kindClass: 'over', title: t.title, meta: t.late, tags: t.tags, due: t.late, dueClass: 'red', overdue: true, round: true }));
    const tasks = D.todos.recurring.map((t) => ({ time: t.due.replace('今天 ', ''), icon: 'repeat', kindClass: 'alloc', title: t.title, meta: t.occurrence || (t.missed ? '错过 2 天，保持待办' : '重复任务'), tags: t.tags, due: t.missed ? '逾期' : '今天', dueClass: t.missed ? 'red' : '', round: true }));
    const due = D.todos.dueToday.map((t) => ({ time: t.due.replace('今天 ', ''), icon: 'flag', kindClass: 'due', title: t.title, meta: t.subtasks ? `子任务 ${t.subtasks}` : '截止事项', tags: t.tags, due: t.due.includes('18:00') ? '18:00' : '今天', dueClass: 'amber', round: true, sel: t.title.includes('预算') }));

    document.getElementById('app').innerHTML = `
      <div class="workspace">
        ${side('action')}
        <main class="main">
          ${top('今日执行', 'THU 22')}
          <div class="body">
            <section class="content">
              <div class="act-head">
                <div>
                  <div class="act-date">10月22日<span>周四 · 第 43 周</span></div>
                  <div class="act-sub">九月初二<span class="s">/</span>明日霜降<span class="s">/</span>15:42 现在</div>
                </div>
                <div class="act-metrics">
                  <div class="metric"><div class="k">事件</div><div class="v">6</div></div>
                  <div class="metric"><div class="k">安排</div><div class="v">5</div></div>
                  <div class="metric"><div class="k">任务</div><div class="v">7</div></div>
                  <div class="metric"><div class="k">空余</div><div class="v">2<small>h</small>10</div></div>
                </div>
                <div class="act-actions">
                  <button class="btn ghost">${ic('layout-list')}六件事</button>
                  <button class="ib">${ic('dots')}</button>
                </div>
              </div>
              ${density()}
              <div class="group-bar danger">${ic('alert-triangle')}逾期<span class="n">02</span><span class="r">保持原截止日期</span></div>
              <div class="rows">${overdue.map(actRow).join('')}</div>
              <div class="group-bar">${ic('clock')}今日时间轴<span class="n">06</span><span class="r">事件与任务安排</span></div>
              <div class="rows">${sched.map(actRow).join('')}</div>
              <div class="group-bar">${ic('repeat')}重复任务<span class="n">03</span><span class="r">按 occurrence 完成</span></div>
              <div class="rows">${tasks.map(actRow).join('')}</div>
              <div class="group-bar">${ic('flag')}今日截止<span class="n">03</span><span class="r">不占时间</span></div>
              <div class="rows">${due.map(actRow).join('')}</div>
              <div class="inbox-row">${ic('inbox')}收件箱 · 未安排<span class="n">4 项</span>${ic('chevron-right')}</div>
            </section>
            <aside class="inspector">
              <div class="insp-head">
                <span class="insp-check"></span>
                <div class="insp-title"><span class="p">P1</span>提交 Q4 预算表</div>
                <div class="insp-menu"><button class="ib">${ic('dots')}</button></div>
              </div>
              <div class="insp-meta"><span class="m">工作</span><span class="m">今天</span><span class="m">3 / 5 子任务</span></div>
              <div class="prop">
                <span class="k">列表</span><span class="v">${ic('folder')}工作</span>
                <span class="k">截止</span><span class="v mono">2026-10-22 18:00</span>
                <span class="k">安排</span><span class="v mono">今天 16:30 - 17:30</span>
                <span class="k">优先</span><span class="v"><span class="tag" style="background:#fdeaea;color:#b23434">P1 高</span></span>
                <span class="k">标签</span><span class="v">${tag('财务')}${tag('产品')}</span>
                <span class="k">创建</span><span class="v mono">10月18日 08:12</span>
                <span class="k">更新</span><span class="v mono">2 小时前</span>
              </div>
              <div class="sub-head">子任务<span class="n">3 / 5</span></div>
              ${D.selectedTodo.subtasks.map((s) => `<div class="sub-row ${s.done ? 'done' : ''}"><span class="bx">${s.done ? ic('check') : ''}</span><span class="t">${s.title}</span></div>`).join('')}
              <div class="note-box">${D.selectedTodo.note}</div>
              <div class="load">
                <div class="load-top">今日负载<b>68%</b></div>
                <div class="load-track"><div class="load-fill" style="width:68%"></div></div>
                <div class="load-foot"><span>已排 4h30m</span><span>可用 6h40m</span></div>
              </div>
              <div class="insp-btns"><button class="btn">${ic('check')}完成</button><button class="btn ghost">${ic('calendar')}改期</button></div>
              <div class="insp-sec">
                <div class="lab">关联</div>
                <div class="keys">14:00 - 15:30 · Q4 规划评审<br>明天 10:00 · 发布检查 · 线上</div>
              </div>
              <div class="hint"><kbd>⌘↵</kbd> 完成 · <kbd>⌘⇧D</kbd> 改截止 · <kbd>⌘⌥→</kbd> 顺延安排</div>
            </aside>
          </div>
          ${status()}
        </main>
      </div>`;
  };

  const hm = (s) => { const [h, m] = s.split(':').map(Number); return h * 60 + m; };
  const RANGE_START = 7 * 60, RANGE_END = 21 * 60, GRID_H = 660;
  const y = (m) => ((m - RANGE_START) / (RANGE_END - RANGE_START)) * GRID_H;

  const layout = (items) => {
    const sorted = [...items].sort((a, b) => a.s - b.s || a.e - b.e);
    let cluster = [], clusterEnd = -1;
    const flush = () => {
      const ends = [];
      cluster.forEach((it) => {
        let c = ends.findIndex((end) => end <= it.s);
        if (c === -1) { c = ends.length; ends.push(it.e); } else { ends[c] = it.e; }
        it.col = c;
      });
      cluster.forEach((it) => { it.cols = ends.length; });
      cluster = []; clusterEnd = -1;
    };
    sorted.forEach((it) => {
      if (cluster.length && it.s >= clusterEnd) flush();
      cluster.push(it); clusterEnd = Math.max(clusterEnd, it.e);
    });
    if (cluster.length) flush();
    return sorted;
  };

  const block = (it) => {
    const top = y(it.s), h = Math.max(15, y(it.e) - y(it.s));
    const w = 100 / it.cols, left = it.col * w;
    return `<div class="ev ${it.type === 'alloc' ? 'alloc' : ''}" style="top:${top}px;height:${h}px;left:calc(${left}% + 1px);width:calc(${w}% - 2px);--c:${CAT[it.cat] || '#2b5ce6'}">
      <div class="t">${it.title}</div>${h > 28 ? `<div class="m">${it.place || '任务安排'}</div>` : ''}
    </div>`;
  };

  const miniMonth = () => {
    const cells = [];
    const wd = ['一', '二', '三', '四', '五', '六', '日'];
    wd.forEach((w) => cells.push(`<div class="wd">${w}</div>`));
    for (let i = 0; i < 3; i += 1) cells.push('<div></div>');
    for (let d = 1; d <= 31; d += 1) {
      const cls = d === 22 ? 'today' : (d >= 19 && d <= 25) || d === 5 || d === 12 ? 'has' : '';
      cells.push(`<div class="cd ${cls}">${d}</div>`);
    }
    return `<div class="mini">${cells.join('')}</div>`;
  };

  const renderCalendar = () => {
    const days = [0, 1, 2, 3, 4, 5, 6].map((day) => {
      const evs = D.events.filter((e) => e.day === day).map((e) => ({ ...e, s: hm(e.start), e: hm(e.end), type: 'event' }));
      const allocs = D.allocations.filter((a) => a.day === day).map((a) => ({ ...a, s: hm(a.start), e: hm(a.end), type: 'alloc' }));
      return layout([...evs, ...allocs]);
    });
    const lines = [];
    for (let h = 7; h <= 21; h += 1) {
      lines.push(`<div class="hl" style="top:${y(h * 60)}px"></div>`);
      if (h < 21) lines.push(`<div class="hl half" style="top:${y(h * 60 + 30)}px"></div>`);
    }
    document.getElementById('app').innerHTML = `
      <div class="workspace">
        ${side('calendar')}
        <main class="main">
          ${top('日历', 'W43')}
          <div class="cal-toolbar">
            <div class="cal-title">2026 年 10 月<span>第 43 周</span></div>
            <div class="seg"><button>日</button><button class="on">周</button><button>月</button></div>
            <div class="cal-tools">
              <button class="btn ghost">今天</button>
              <button class="ib">${ic('chevron-left')}</button><button class="ib">${ic('chevron-right')}</button>
              <button class="ib">${ic('adjustments')}</button>
              <button class="btn">${ic('plus')}事件</button>
            </div>
          </div>
          <div class="cal-body">
            <div class="cal-main">
              <div class="cal-head">
                <div class="gutter"></div>
                <div class="day-heads">${D.week.map((d) => `<div class="day-head ${d.today ? 'today' : ''}"><div class="w">${d.w}</div><div class="d">${d.d}</div>${d.term ? `<span class="term">${d.term}</span>` : ''}</div>`).join('')}</div>
              </div>
              <div class="allday">
                <div class="gutter">全天</div>
                <div class="allday-cols">${[0,1,2,3,4,5,6].map((day) => `<div class="allday-col">${D.allDay.filter((a) => a.day === day).map((a) => `<span class="ap ${a.cat === 'term' ? 'term' : ''}" style="--c:${CAT[a.cat]}">${a.title}</span>`).join('')}</div>`).join('')}</div>
              </div>
              <div class="cal-scroll">
                <div class="times">${Array.from({ length: 14 }, (_, i) => `<label style="top:${y((8 + i) * 60)}px">${String(8 + i).padStart(2, '0')}:00</label>`).join('')}</div>
                <div class="cols">
                  ${days.map((items, day) => `<div class="col ${day > 4 ? 'weekend' : ''}">${lines.join('')}${items.map(block).join('')}${D.deadlines.filter((d) => d.day === day).map((d) => `<div class="dl ${d.overdue ? 'red' : ''}" style="top:${y(hm(d.time))}px"><div class="line"></div><div class="flag">${d.title}</div></div>`).join('')}</div>`).join('')}
                  <div class="now" style="top:${y(D.today.nowMinutes)}px"><span class="dot" style="left:calc(${(3 / 7) * 100}% - 2px)"></span></div>
                </div>
              </div>
            </div>
            <aside class="cal-insp">
              <div class="mini-head">2026 年 10 月<span class="navs">${ic('chevron-left')}${ic('chevron-right')}</span></div>
              ${miniMonth()}
              <div class="insp-sec">
                <div class="lab">选中事件</div>
                <div class="ev-title">Q4 规划评审</div>
                <div class="ev-when">周四 10/22 · 14:00 - 15:30 · 90 分</div>
                <div class="ev-place">${ic('video')}线上会议 · 产品</div>
                <div class="attend"><span class="av">林</span><span class="av">周</span><span class="av">陈</span><span class="av">许</span><span class="more">+4</span></div>
              </div>
              <div class="warn-card">${ic('alert-triangle')}<span>15:30 紧接「整理评审纪要」任务安排，没有缓冲时间。</span></div>
              <div class="insp-sec">
                <div class="lab">今日</div>
                <div class="day-stats"><span>事件 <b>6</b></span><span>安排 <b>5</b></span><span>截止 <b>2</b></span><span>已排 <b>4h30</b></span></div>
              </div>
              <div class="insp-sec">
                <div class="lab">快捷键</div>
                <div class="keys"><kbd>N</kbd> 新建事件 · <kbd>T</kbd> 今天 · <kbd>1/2/3</kbd> 日周月<br><kbd>← →</kbd> 切换周 · <kbd>⌘K</kbd> 命令</div>
              </div>
            </aside>
          </div>
          ${status()}
        </main>
      </div>`;
  };

  const trow = (t, o = {}) => `
    <div class="trow ${o.overdue ? 'overdue' : ''} ${o.done ? 'done' : ''} ${o.sel ? 'sel' : ''}">
      <span class="pri ${t.priority === 1 ? 'p1' : t.priority === 2 ? 'p2' : ''}"></span>
      <span class="tt">${t.title}</span>
      <span class="list">${t.list || '工作'}</span>
      <span class="tags">${(t.tags || []).map(tag).join('')}</span>
      <span class="due ${o.overdue || t.missed ? 'red' : ''}">${o.done ? t.at : (t.late || t.due || '未安排')}</span>
      <span class="sub">${t.subtasks || ''}</span>
      <span class="rep">${t.repeat ? ic('repeat') : ''}</span>
      <span class="plan">${o.done ? '完成' : (o.plan || '')}</span>
    </div>`;

  const renderTodo = () => {
    document.getElementById('app').innerHTML = `
      <div class="workspace">
        ${side('todo')}
        <main class="main">
          ${top('待办', '19')}
          <div class="todo-toolbar">
            <div class="todo-title">全部待办<span class="n">19 项</span></div>
            <div class="seg"><button class="on">全部</button><button>今天</button><button>逾期</button><button>已安排</button></div>
            <div class="todo-tools">
              <button class="btn ghost">${ic('arrows-sort')}截止</button>
              <button class="ib">${ic('filter')}</button>
              <button class="ib">${ic('layout-list')}</button>
              <button class="btn">${ic('plus')}待办</button>
            </div>
          </div>
          <div class="metrics">
            <div class="mt"><div class="k">今天完成</div><div class="v">3 <small>/ 10</small></div></div>
            <div class="mt red"><div class="k">逾期</div><div class="v">2</div></div>
            <div class="mt"><div class="k">本周</div><div class="v">3</div></div>
            <div class="mt"><div class="k">收件箱</div><div class="v">4</div></div>
            <div class="mt"><div class="k">已安排</div><div class="v">5 <small>段</small></div></div>
            <div class="mt"><div class="k">无截止</div><div class="v">4</div></div>
          </div>
          <div class="body">
            <section class="table-wrap">
              <div class="thead"><span></span><span>标题</span><span>列表</span><span>标签</span><span>截止</span><span>子任务</span><span>重</span><span>安排</span></div>
              <div class="tgroup red">${ic('alert-triangle')}逾期<span class="n">02</span><span class="r">保持真实截止日期</span></div>
              <div class="trows">${D.todos.overdue.map((t) => trow(t, { overdue: true, plan: '未安排' })).join('')}</div>
              <div class="tgroup">${ic('sun')}今天<span class="n">03</span><span class="r">截止与执行分离</span></div>
              <div class="trows">${D.todos.dueToday.map((t) => trow(t, { sel: t.title.includes('预算'), plan: t.title.includes('预算') ? '16:30' : '' })).join('')}</div>
              <div class="tgroup">${ic('repeat')}重复任务<span class="n">03</span><span class="r">按 occurrence 完成</span></div>
              <div class="trows">${D.todos.recurring.map((t) => trow(t, { overdue: t.missed, plan: '09:30' })).join('')}</div>
              <div class="tgroup">${ic('calendar')}本周<span class="n">03</span></div>
              <div class="trows">${D.todos.thisWeek.map((t) => trow(t)).join('')}</div>
              <div class="tgroup">${ic('circle-check')}已完成<span class="n">03</span><span class="r">今天 08:40 - 11:02</span></div>
              <div class="trows">${D.todos.completed.map((t) => trow({ title: t.title, at: t.at, tags: [], list: '工作' }, { done: true })).join('')}</div>
            </section>
            <aside class="inspector">
              <div class="sub-head" style="margin-top:0">六件事<span class="n">专注模式</span></div>
              <div class="six-list">${D.sixThings.map((s, i) => `<div class="six-item"><span class="no">${String(i + 1).padStart(2, '0')}</span><div><div class="t">${s.title}</div><div class="m">${s.meta}</div></div></div>`).join('')}</div>
              <div class="insp-sec">
                <div class="lab">收件箱 · 4</div>
                <div class="inbox-list">${D.todos.unplanned.map((t) => `<div class="inbox-item"><span class="ck"></span><span>${t.title}</span>${tag(t.tags[0])}<span class="due">未安排</span></div>`).join('')}</div>
              </div>
              <div class="insp-sec">
                <div class="lab">批量操作</div>
                <div class="keys"><kbd>Space</kbd> 完成 · <kbd>E</kbd> 编辑 · <kbd>D</kbd> 设截止<br><kbd>S</kbd> 安排时间 · <kbd>⌫</kbd> 移入回收站</div>
              </div>
              <div class="insp-sec">
                <div class="lab">今日完成 · 3</div>
                ${D.todos.completed.map((t) => `<div class="sub-row" style="height:23px"><span class="bx" style="background:var(--green);border-color:var(--green);color:#fff;display:grid;place-items:center;font-size:8px">${ic('check')}</span><span class="t" style="color:var(--ink-3);text-decoration:line-through">${t.title}</span><span style="margin-left:auto;font-family:var(--mono);font-size:8.5px;color:var(--ink-3)">${t.at}</span></div>`).join('')}
              </div>
              <div class="warn-card" style="margin-top:12px">${ic('info-circle')}<span>拖拽到时间轴可创建任务安排，不会修改截止时间。</span></div>
            </aside>
          </div>
          ${status()}
        </main>
      </div>`;
  };

  const mrow = (o) => `
    <div class="m-row ${o.overdue ? 'overdue' : ''} ${o.deadline ? 'deadline' : ''}">
      <span class="tm">${o.time}</span>
      <span class="kd ${o.kindClass}">${ic(o.icon)}</span>
      <span class="tt">${o.title}${o.meta ? `<span class="m">${o.meta}</span>` : ''}</span>
      <span class="tag ${o.tagClass || ''}">${o.tag || ''}</span>
      <span class="ck" style="${o.nock ? 'border-color:transparent' : ''}"></span>
    </div>`;

  const renderMobile = () => {
    const start = 6 * 60, end = 22 * 60, span = end - start;
    const blocks = D.timeline.filter((t) => t.type !== 'deadline').map((t) => {
      const s = hm(t.start), e = hm(t.end);
      return `<span class="b ${t.type === 'alloc' ? 'a' : ''}" style="left:${(s - start) / span * 100}%;width:${Math.max(1, (e - s) / span * 100)}%;--c:${CAT[t.cat] || '#2b5ce6'}"></span>`;
    }).join('');
    const rows = [
      ...D.todos.overdue.map((t) => ({ time: t.due.replace('10月', '10/').replace('日', ''), icon: 'alert-triangle', kindClass: 'over', title: t.title, meta: t.late, tag: t.tags[0], tagClass: tagClass[t.tags[0]], overdue: true, nock: true })),
      ...D.timeline.slice(0, 6).map((t) => ({ time: t.start, icon: t.type === 'event' ? 'calendar-event' : 'checkbox', kindClass: t.type === 'event' ? 'evt' : 'alloc', title: t.title, meta: t.meta, tag: t.cat === 'work' ? '工作' : t.cat === 'life' ? '生活' : '产品', tagClass: t.cat === 'work' ? 'blue' : t.cat === 'life' ? 'green' : 'purple', nock: t.type === 'event' })),
      ...D.todos.dueToday.map((t) => ({ time: t.due.replace('今天 ', ''), icon: 'flag', kindClass: 'due', title: t.title, meta: t.subtasks ? `子任务 ${t.subtasks}` : '截止今天', tag: t.tags[0], tagClass: tagClass[t.tags[0]], deadline: true, nock: true })),
    ];
    document.getElementById('app').innerHTML = `
      <div class="phone">
        <div class="m-status"><span>15:42</span><span class="ic">${ic('signal-4g')}${ic('wifi')}${ic('battery-3')}</span></div>
        <div class="m-appbar"><div class="logo">${ic('sparkles')}</div><span class="nm">DAYSPARK</span><button class="ib">${ic('search')}</button><button class="ib">${ic('adjustments')}</button></div>
        <div class="m-date">
          <div class="top">
            <div class="m-dnav"><button class="ib nb">${ic('chevron-left')}</button><div><div class="d">10月22日<span>周四</span></div><div class="sub">W43 · 明日霜降 · 15:42</div></div><button class="ib nb">${ic('chevron-right')}</button></div>
            <div class="acts"><button class="add">${ic('plus')}</button></div>
          </div>
          <div class="m-count"><span>6 事件</span><span>5 安排</span><span>7 任务</span><span class="red">2 逾期</span></div>
          <div class="m-density"><span class="lb">密度 06–22</span><div class="tr">${blocks}<span class="n" style="left:${(D.today.nowMinutes - start) / span * 100}%"></span></div></div>
        </div>
        <div class="m-seg"><button class="on">执行</button><button>时间轴</button><button>全部</button><span class="right">${ic('layout-list')}六件事</span></div>
        <div class="m-list">
          <div class="m-group red">${ic('alert-triangle')}逾期<span class="n">2</span><span class="r">保持原截止</span></div>
          <div class="m-box">${rows.slice(0, 2).map(mrow).join('')}</div>
          <div class="m-group">${ic('clock')}时间轴<span class="n">6</span><span class="r">事件与安排</span></div>
          <div class="m-box">${rows.slice(2, 8).map(mrow).join('')}</div>
          <div class="m-group">${ic('flag')}今日截止<span class="n">3</span><span class="r">不占时间</span></div>
          <div class="m-box">${rows.slice(8).map(mrow).join('')}</div>
          <div class="m-inbox">${ic('inbox')}收件箱 · 未安排<span class="n">4</span>${ic('chevron-right')}</div>
        </div>
        <div class="m-nav"><div class="tab on"><span>${ic('sun')}</span>今日</div><div class="tab"><span>${ic('calendar')}</span>日历</div><div class="tab"><span>${ic('checkbox')}</span>待办</div></div>
      </div>`;
  };

  const screen = document.body.dataset.screen;
  const render = { action: renderAction, calendar: renderCalendar, todo: renderTodo, mobile: renderMobile }[screen];
  if (render) render();
})();
