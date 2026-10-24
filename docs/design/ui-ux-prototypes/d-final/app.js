(() => {
  const D = window.DS;
  const CAT = { work: '#2457d6', life: '#2a7151', product: '#6d4aa0', finance: '#9a4a06', term: '#9a4a06' };
  const ic = (n) => `<i class="ti ti-${n}"></i>`;
  const hm = (s) => { const [h, m] = s.split(':').map(Number); return h * 60 + m; };
  const Q4_ALLOC = { day: 3, start: '16:30', end: '17:30', title: 'Q4 预算表', todo: '提交 Q4 预算表', cat: 'finance' };
  const taskTitle = (t) => (t.title === '预约牙医' ? '确认牙医预约' : t.title);
  const cleanMeta = (t) => (t.meta || '')
    .replace('任务安排 · ', '')
    .replace('截止时间 · 不占用时间', '')
    .replace('线上 · 与上一项重叠', '与上一项重叠');

  const side = (active) => `
    <aside class="rail">
      <div class="brand">
        <div class="logo">${ic('calendar-star')}</div>
        <div class="wordmark"><b>灵光<i></i></b><span>DAYSPARK</span></div>
      </div>
      <nav class="nav">
        <div class="nav-item ${active === 'action' ? 'on' : ''}">${ic('sun')}今日执行<span class="count">8</span></div>
        <div class="nav-item ${active === 'calendar' ? 'on' : ''}">${ic('calendar')}日历</div>
        <div class="nav-item ${active === 'todo' ? 'on' : ''}">${ic('checkbox')}待办<span class="count">18</span></div>
      </nav>
      <div class="rail-label">列表</div>
      <nav class="nav">
        ${D.lists.map((l) => `<div class="nav-item sub">${ic(l.icon)}${l.name}<span class="count">${l.count}</span></div>`).join('')}
      </nav>
      <div class="rail-label">标签</div>
      <nav class="nav">
        ${D.tags.map((t) => `<div class="nav-item sub"><span class="dot" style="background:${CAT[t.color === 'blue' ? 'work' : t.color === 'purple' ? 'product' : t.color === 'orange' ? 'finance' : 'life']}"></span>${t.name}<span class="count">${t.count}</span></div>`).join('')}
      </nav>
      <div class="rail-foot"><span class="sync-dot"></span><span>3 台设备</span></div>
    </aside>`;

  const top = (label, local = false) => `
    <header class="topbar ${local ? 'has-local' : ''}">
      <div class="crumbs"><span>灵光</span>${ic('chevron-right')}<b>${label}</b></div>
      <div class="search">${ic('search')}<span>搜索任务与事件</span><kbd>⌘K</kbd></div>
      <div class="top-actions">
        <button class="icon-btn">${ic('bell')}</button>
        <button class="icon-btn">${ic('settings')}</button>
        <button class="new-btn">${ic('plus')}新建</button>
      </div>
    </header>`;

  const status = () => `
    <footer class="statusbar">
      <span>本地优先 · 已同步 15:40</span>
      <span>自托管</span>
    </footer>`;

  const drawer = (open = false) => `
    <aside class="drawer ${open ? 'open' : ''}" id="drawer">
      <div class="drawer-head">
        <div>
          <div class="drawer-kind">待办</div>
          <h2>提交 Q4 预算表</h2>
        </div>
        <button class="icon-btn drawer-close" id="drawer-close">${ic('x')}</button>
      </div>
      <div class="drawer-tags"><span class="tag mini">P1</span><span>工作</span><span>财务</span></div>
      <div class="drawer-props">
        <div><span>截止</span><b>10月22日 18:00</b></div>
        <div><span>安排</span><b>16:30 – 17:30</b></div>
      </div>
      <div class="drawer-section"><span>子任务</span><b>3 / 5</b></div>
      <div class="subtasks">
        ${D.selectedTodo.subtasks.map((s) => `<div class="subtask ${s.done ? 'done' : ''}"><span class="box">${s.done ? ic('check') : ''}</span><span>${s.title}</span></div>`).join('')}
      </div>
      <p class="drawer-note">${D.selectedTodo.note}</p>
      <div class="drawer-warn">${ic('alert-triangle')}<span>17:30 结束，距 18:00 截止仅 30 分钟。</span></div>
      <div class="drawer-actions">
        <button class="primary-btn">${ic('check')}完成</button>
        <button class="ghost-btn">${ic('calendar')}改期</button>
      </div>
    </aside>`;

  const bindDrawer = () => {
    const panel = document.getElementById('drawer');
    if (!panel) return;
    const main = panel.closest('.main');
    const close = () => {
      panel.classList.remove('open');
      main?.classList.remove('drawer-open');
    };
    document.getElementById('drawer-close')?.addEventListener('click', close);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
    document.querySelectorAll('[data-select]').forEach((row) => {
      const open = () => {
        document.querySelectorAll('.act-row.sel, .todo-row.sel').forEach((r) => r.classList.remove('sel'));
        row.classList.add('sel');
        panel.classList.add('open');
        main?.classList.add('drawer-open');
      };
      row.addEventListener('click', open);
      row.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); } });
    });
  };

  const rhythm = () => {
    const start = 6 * 60, end = 22 * 60, span = end - start;
    const blocks = D.timeline.filter((t) => t.type !== 'deadline').map((t) => {
      const s = hm(t.start), e = hm(t.end);
      return `<span class="rhythm-block ${t.type === 'alloc' ? 'alloc' : ''}" style="left:${(s - start) / span * 100}%;width:${Math.max(0.8, (e - s) / span * 100)}%;--c:${CAT[t.cat] || 'var(--blue)'}"></span>`;
    }).join('');
    return `<div class="rhythm">
      <div class="rhythm-track">${blocks}<span class="rhythm-now" style="left:${(D.today.nowMinutes - start) / span * 100}%"></span></div>
      <div class="rhythm-times"><span>06</span><span>09</span><span>12</span><span>15</span><span>18</span><span>21</span></div>
    </div>`;
  };

  const actRow = (o) => `
    <div class="act-row ${o.overdue ? 'overdue' : ''} ${o.sel ? 'sel' : ''}" ${o.sel ? 'data-select tabindex="0" role="button"' : ''}>
      <span class="time">${o.time}</span>
      <span class="kind ${o.kindClass}">${ic(o.icon)}</span>
      <span class="titleline"><span class="title">${o.title}</span>${o.meta ? `<span class="meta ${o.metaClass || ''}">${o.meta}</span>` : ''}</span>
      <span class="tail ${o.tailClass || ''}">${o.tail || ''}</span>
      <span class="check ${o.check === 'round' ? 'round' : ''} ${o.check === false ? 'ghost' : ''}"></span>
    </div>`;

  const renderAction = () => {
    const schedule = D.timeline.slice(0, 6).map((t) => ({
      time: t.start,
      icon: t.type === 'event' ? 'calendar-event' : 'clock',
      kindClass: t.type === 'event' ? 'evt' : 'alloc',
      title: t.title,
      meta: cleanMeta(t),
      metaClass: t.overlap ? 'warm' : '',
      tail: `→ ${t.end}`,
      check: t.type === 'alloc',
    }));
    const overdue = D.todos.overdue.map((t) => ({
      time: t.due.replace('月', '/').replace('日', ''),
      icon: 'alert-triangle',
      kindClass: 'over',
      title: t.title,
      tail: t.late,
      tailClass: 'red',
      overdue: true,
      check: 'round',
    }));
    const tasks = [
      ...D.todos.recurring.map((t) => ({
        time: t.due.includes(':') ? t.due.replace('今天 ', '') : (t.missed ? t.due.replace('月', '/').replace('日', '') : '—'),
        icon: 'repeat',
        kindClass: t.missed ? 'over' : 'alloc',
        title: t.title,
        meta: t.missed ? '' : (t.occurrence || ''),
        tail: t.missed ? '错过 2 天' : '今天',
        tailClass: t.missed ? 'warm' : '',
        check: 'round',
      })),
      ...D.todos.dueToday.map((t) => ({
        time: t.due.includes(':') ? t.due.replace('今天 ', '') : '—',
        icon: 'flag',
        kindClass: 'due',
        title: taskTitle(t),
        meta: t.deadline ? '16:30 安排' : (t.subtasks ? `子任务 ${t.subtasks}` : ''),
        tail: t.deadline ? '截止' : '今天',
        tailClass: 'amber',
        check: 'round',
        sel: t.title.includes('预算'),
      })),
    ];

    document.getElementById('app').innerHTML = `
      <div class="workspace">
        ${side('action')}
        <main class="main drawer-open">
          ${top('今日执行')}
          <div class="action-page">
            <header class="page-head">
              <div class="date-block">
                <h1>10月22日<span class="wd">周四</span></h1>
                <div class="sub">第 43 周 · 九月初二 · 明日霜降</div>
              </div>
              <div class="summary">6 事件<span>·</span>6 安排<span>·</span><b class="red">2 逾期</b></div>
              <div class="head-actions">
                <button class="ghost-btn">${ic('layout-list')}六件事</button>
                <button class="icon-btn">${ic('dots')}</button>
              </div>
            </header>
            ${rhythm()}
            <div class="group-head danger">逾期<span class="count">2</span><span class="right">保持原截止</span></div>
            ${overdue.map(actRow).join('')}
            <div class="group-head">时间线<span class="count">7 / 12</span><a class="more-link" href="calendar.html">完整日程${ic('chevron-right')}</a></div>
            ${schedule.map(actRow).join('')}
            <div class="act-row now-row">
              <span class="time">15:30</span>
              <span class="kind nowkind">${ic('clock')}</span>
              <span class="titleline"><span class="title">整理评审纪要</span><span class="meta warm">进行中 · 到 16:00</span></span>
              <span class="tail warm">剩 18 分</span>
              <span class="check round"></span>
            </div>
            <div class="group-head">待办<span class="count">6</span></div>
            ${tasks.map(actRow).join('')}
            <div class="inbox-line">${ic('inbox')}收件箱 · 未安排<span>4</span>${ic('chevron-right')}</div>
          </div>
          ${drawer(true)}
          ${status()}
        </main>
      </div>`;
    bindDrawer();
  };

  const RANGE_START = 7 * 60, RANGE_END = 21 * 60, GRID_H = 636;
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
    const top = y(it.s), h = Math.max(16, y(it.e) - y(it.s));
    const w = 100 / it.cols, left = it.col * w;
    return `<div class="ev ${it.type === 'alloc' ? 'alloc' : ''} ${it.cols > 1 ? 'narrow' : ''}" style="top:${top}px;height:${h}px;left:calc(${left}% + 1px);width:calc(${w}% - 2px);--c:${CAT[it.cat] || 'var(--blue)'}">
      <div class="t">${it.title}</div>${h > 36 && it.place ? `<div class="m">${it.place}</div>` : ''}
    </div>`;
  };

  const renderCalendar = () => {
    const days = [0, 1, 2, 3, 4, 5, 6].map((day) => {
      const evs = D.events.filter((e) => e.day === day).map((e) => ({ ...e, s: hm(e.start), e: hm(e.end), type: 'event' }));
      const allocs = [...D.allocations, Q4_ALLOC].filter((a) => a.day === day).map((a) => ({ ...a, s: hm(a.start), e: hm(a.end), type: 'alloc' }));
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
          ${top('日历', true)}
          <div class="cal-toolbar">
            <div class="cal-title">10月<span>2026 · 第 43 周</span></div>
            <div class="seg"><button>日</button><button class="on">周</button><button>月</button></div>
            <div class="legend">
              <span><i class="sw evt"></i>事件</span>
              <span><i class="sw alloc"></i>安排</span>
              <span><i class="sw due"></i>截止</span>
            </div>
            <div class="cal-tools">
              <button class="ghost-btn">今天</button>
              <button class="icon-btn">${ic('chevron-left')}</button><button class="icon-btn">${ic('chevron-right')}</button>
              <button class="new-btn">${ic('plus')}事件</button>
            </div>
          </div>
          <div class="cal-wrap">
            <div class="cal-head">
              <div class="gutter"></div>
              <div class="day-heads">${D.week.map((d) => `<div class="day-head ${d.today ? 'today' : ''}"><div class="w">${d.w}</div><div class="d">${d.d}</div>${d.term ? `<span class="term">${d.term}</span>` : ''}</div>`).join('')}</div>
            </div>
            <div class="allday">
              <div class="gutter">全天</div>
              <div class="allday-cols">${[0,1,2,3,4,5,6].map((day) => `<div class="allday-col">${D.allDay.filter((a) => a.day === day && a.cat !== 'term').map((a) => `<span class="ap ${a.cat === 'term' ? 'term' : ''}" style="--c:${CAT[a.cat]}">${a.title}</span>`).join('')}</div>`).join('')}</div>
            </div>
            <div class="dl-lane">
              <div class="gutter">截止</div>
              <div class="dl-cols">${[0,1,2,3,4,5,6].map((day) => `<div class="dl-col">${D.deadlines.filter((d) => d.day === day).map((d) => `<span class="dl-chip ${d.overdue ? 'red' : ''}"><b>${d.time}</b>${d.title}</span>`).join('')}</div>`).join('')}</div>
            </div>
            <div class="cal-scroll">
              <div class="times">${Array.from({ length: 13 }, (_, i) => `<label style="top:${y((8 + i) * 60)}px">${String(8 + i).padStart(2, '0')}:00</label>`).join('')}<label class="now-label" style="top:${y(D.today.nowMinutes)}px">15:42</label></div>
              <div class="cols">
                ${days.map((items, day) => `<div class="col ${day > 4 ? 'weekend' : ''}">${lines.join('')}${items.map(block).join('')}</div>`).join('')}
                <div class="now" style="top:${y(D.today.nowMinutes)}px"><span class="dot" style="left:calc(${(3 / 7) * 100}% - 2px)"></span></div>
              </div>
            </div>
          </div>
          ${status()}
        </main>
      </div>`;
  };

  const todoRow = (t, o = {}) => `
    <div class="todo-row ${o.overdue ? 'overdue' : ''} ${o.done ? 'done' : ''} ${o.sel ? 'sel' : ''}" ${o.sel ? 'data-select tabindex="0" role="button"' : ''}>
      <span class="pri ${t.priority === 1 ? 'p1' : t.priority === 2 ? 'p2' : ''}"></span>
      <span class="check ${o.done ? 'done' : ''}">${o.done ? ic('check') : ''}</span>
      <span class="todo-title"><span class="dot" style="background:${CAT[t.list === '产品' ? 'product' : t.list === '生活' ? 'life' : 'work']}"></span><span class="name">${taskTitle(t)}</span>${o.meta ? `<span class="meta">${o.meta}</span>` : ''}${t.repeat ? `<span class="repeat">${ic('repeat')}</span>` : ''}</span>
      <span class="due ${o.overdue ? 'red' : (o.warm ? 'warm' : '')}">${o.done ? t.at : (o.due !== undefined ? o.due : (t.late || t.due || '未安排'))}</span>
    </div>`;

  const renderTodo = () => {
    document.getElementById('app').innerHTML = `
      <div class="workspace">
        ${side('todo')}
        <main class="main">
          ${top('待办', true)}
          <div class="todo-page">
            <header class="todo-head">
              <div>
                <h1>待办<span>18</span></h1>
              </div>
              <div class="seg"><button class="on">全部</button><button>今天</button><button>逾期</button><button>已安排</button></div>
              <div class="todo-tools">
                <button class="ghost-btn">${ic('arrows-sort')}截止</button>
                <button class="icon-btn">${ic('filter')}</button>
                <button class="new-btn">${ic('plus')}待办</button>
              </div>
            </header>
            <div class="todo-scroll">
              <div class="tg red">逾期<span>2</span></div>
              ${D.todos.overdue.map((t) => todoRow(t, { overdue: true })).join('')}
              <div class="tg">今天<span>3</span></div>
              ${D.todos.dueToday.map((t) => todoRow(t, { due: t.due.includes(':') ? t.due.replace('今天 ', '') : '', meta: t.deadline ? '16:30 安排' : (t.subtasks ? `子任务 ${t.subtasks}` : '') })).join('')}
              <div class="tg">重复<span>3</span></div>
              ${D.todos.recurring.map((t) => todoRow(t, {
                warm: t.missed,
                due: t.missed ? '错过 2 天' : (t.due.includes(':') ? t.due.replace('今天 ', '') : '今天'),
                meta: t.occurrence || '',
              })).join('')}
              <div class="tg">本周<span>3</span></div>
              ${D.todos.thisWeek.map((t) => todoRow(t, { due: t.due === '明天' ? '周五' : t.due, meta: t.subtasks ? `子任务 ${t.subtasks}` : '' })).join('')}
              <div class="tg">已完成<span>3</span></div>
              ${D.todos.completed.map((t) => todoRow({ title: t.title, at: t.at, list: '工作' }, { done: true })).join('')}
              <div class="inbox-line">${ic('inbox')}收件箱 · 未安排<span>4</span>${ic('chevron-right')}</div>
            </div>
          </div>
          ${drawer(false)}
          ${status()}
        </main>
      </div>`;
    bindDrawer();
  };

  const mobileRow = (o) => `
    <div class="mr ${o.overdue ? 'overdue' : ''} ${o.deadline ? 'deadline' : ''} ${o.now ? 'now-row' : ''}">
      <span class="time">${o.time}</span>
      <span class="kind ${o.kindClass}">${ic(o.icon)}</span>
      <span class="body"><span class="t">${o.title}</span>${o.meta ? `<span class="m ${o.metaClass || ''}">${o.meta}</span>` : ''}</span>
      <span class="tail ${o.tailClass || ''}">${o.tail || ''}</span>
      <span class="check ${o.check === false ? 'ghost' : ''} ${o.check === 'round' ? 'round' : ''}"></span>
    </div>`;

  const renderMobile = () => {
    const mOverdue = D.todos.overdue.map((t) => ({
      time: t.due.replace('10月', '10/').replace('日', ''),
      icon: 'alert-triangle', kindClass: 'over', title: t.title,
      meta: t.late, metaClass: 'red', tail: '', check: 'round', overdue: true,
    }));
    const mSchedule = D.timeline.filter((t) => t.type !== 'deadline' && hm(t.start) >= 15 * 60).slice(0, 4).map((t) => {
      const isNow = t.start === '15:30';
      return {
        time: t.start,
        icon: t.type === 'event' ? 'calendar-event' : 'clock',
        kindClass: t.type === 'event' ? 'evt' : 'alloc',
        title: t.title,
        meta: isNow ? `进行中 · 到 ${t.end}` : cleanMeta(t),
        metaClass: isNow ? 'warm' : (t.overlap ? 'warm' : ''),
        tail: isNow ? '剩 18 分' : `→ ${t.end}`,
        tailClass: isNow ? 'warm' : '',
        check: t.type === 'alloc',
        now: isNow,
      };
    });
    const mDue = D.todos.dueToday.map((t) => ({
      time: t.due.includes(':') ? t.due.replace('今天 ', '') : '—',
      icon: 'flag', kindClass: 'due', title: taskTitle(t),
      meta: t.deadline ? '16:30 安排' : '',
      tail: t.deadline ? '截止' : '今天', tailClass: 'amber', check: 'round', deadline: true,
    }));
    document.getElementById('app').innerHTML = `
      <div class="phone">
        <div class="m-status"><span>15:42</span><span class="ic">${ic('signal-4g')}${ic('wifi')}${ic('battery-3')}</span></div>
        <header class="m-head">
          <div class="m-brand"><span class="logo">${ic('calendar-star')}</span><b>灵光<i></i></b><span>DAYSPARK</span></div>
          <div class="m-actions"><button class="icon-btn">${ic('search')}</button><button class="m-add">${ic('plus')}</button></div>
        </header>
        <div class="m-date">
          <div class="m-date-top">
            <button class="m-arrow">${ic('chevron-left')}</button>
            <div><h1>10月22日<span>周四</span></h1><div class="sub">第 43 周 · 九月初二 · 明日霜降</div></div>
            <button class="m-arrow">${ic('chevron-right')}</button>
          </div>
          <div class="m-week">
            ${D.week.map((d) => `<div class="m-day ${d.today ? 'today' : ''}"><span class="w">${d.w.replace('周', '')}</span><b>${d.d}</b><i></i></div>`).join('')}
          </div>
        </div>
        <div class="m-filters"><button class="pill on">全部</button><button class="pill">事件</button><button class="pill">待办</button><button class="six">${ic('layout-list')}六件事</button></div>
        <div class="m-scroll">
          <div class="m-group red">${ic('alert-triangle')}逾期<span class="n">2</span></div>
          <div class="sheet">${mOverdue.map(mobileRow).join('')}</div>
          <div class="m-group">${ic('clock')}接下来<span class="n">4</span><span class="r is-now">15:42 现在</span></div>
          <div class="sheet">${mSchedule.map(mobileRow).join('')}</div>
          <div class="m-group">${ic('flag')}今日截止<span class="n">3</span></div>
          <div class="sheet">${mDue.map(mobileRow).join('')}</div>
          <div class="m-inbox">${ic('inbox')}收件箱 · 未安排<span>4</span>${ic('chevron-right')}</div>
        </div>
        <nav class="m-tabs"><div class="tab on">${ic('sun')}今日</div><div class="tab">${ic('calendar')}日历</div><div class="tab">${ic('checkbox')}待办</div></nav>
      </div>`;
  };

  const screen = document.body.dataset.screen;
  const render = { action: renderAction, calendar: renderCalendar, todo: renderTodo, mobile: renderMobile }[screen];
  if (render) render();
})();
