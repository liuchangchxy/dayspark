(() => {
  const D = window.DS;
  const CAT = {
    work: 'var(--blue)',
    life: 'var(--green)',
    product: 'var(--violet)',
    finance: 'var(--orange)',
    term: 'var(--orange)',
  };
  const tagClass = { 工作: 'blue', 产品: 'purple', 财务: 'orange', 生活: 'green' };
  const ic = (n) => `<i class="ti ti-${n}"></i>`;
  const tag = (t) => `<span class="tag ${tagClass[t] || ''}">${t}</span>`;

  const sidebar = (active) => `
    <aside class="sidebar">
      <div class="brand">
        <div class="brand-mark">${ic('sparkles')}</div>
        <div><div class="brand-name">灵光</div><div class="brand-sub">DAYSPARK</div></div>
      </div>
      <nav class="nav">
        <div class="nav-item ${active === 'action' ? 'active' : ''}">${ic('sun')}今日执行</div>
        <div class="nav-item ${active === 'calendar' ? 'active' : ''}">${ic('calendar')}日历</div>
        <div class="nav-item ${active === 'todo' ? 'active' : ''}">${ic('checkbox')}待办<span class="count">19</span></div>
      </nav>
      <div class="side-label">列表</div>
      <div class="side-list">
        ${D.lists.map((l) => `<div class="side-row">${ic(l.icon)}${l.name}<span class="n">${l.count}</span></div>`).join('')}
      </div>
      <div class="side-label">标签</div>
      <div class="side-list">
        ${D.tags.map((t) => `<div class="side-row"><span class="dot" style="background:${CAT[t.color === 'blue' ? 'work' : t.color === 'purple' ? 'product' : t.color === 'orange' ? 'finance' : 'life']}"></span>${t.name}<span class="n">${t.count}</span></div>`).join('')}
      </div>
      <div class="side-bottom">
        <div class="avatar">常</div>
        <div class="sync"><b>已同步</b>2 分钟前 · 3 台设备</div>
      </div>
    </aside>`;

  const topbar = (label) => `
    <header class="topbar">
      <div class="crumbs">${ic('layout-sidebar')}<span>灵光</span>${ic('chevron-right')}<b>${label}</b></div>
      <div class="top-actions">
        <button class="icon-btn">${ic('search')}</button>
        <button class="icon-btn">${ic('bell')}</button>
        <button class="icon-btn">${ic('settings')}</button>
        <button class="btn-primary">${ic('plus')}新建</button>
      </div>
    </header>`;

  const weekStrip = () => `
    <div class="week">
      ${D.week.map((d) => `
        <div class="day ${d.today ? 'today' : ''}">
          <div class="w">${d.w}</div>
          <div class="d">${d.d}</div>
          <div class="bar"></div>
        </div>`).join('')}
    </div>`;

  const actionRow = (item) => {
    const color = CAT[item.cat] || 'var(--blue)';
    if (item.type === 'deadline') {
      return `<div class="tl-row deadline" style="--mark:${color}">
        <div class="tl-time">${item.start}</div><div class="tl-mark"></div>
        <div class="tl-body"><span class="flag-icon">${ic('flag')}</span><div class="grow"><span class="title">${item.title}</span><span class="meta">${item.meta}</span></div><span class="tag-mini" style="--mark:${color}">截止</span></div>
      </div>`;
    }
    if (item.type === 'alloc') {
      return `<div class="tl-row alloc" style="--mark:${color}">
        <div class="tl-time">${item.start}</div><div class="tl-mark"></div>
        <div class="tl-body"><span class="tl-check"></span><div class="grow"><span class="title">${item.title}</span><span class="meta">${item.meta}</span></div><span class="tag-mini" style="--mark:${color}">安排</span></div>
      </div>`;
    }
    return `<div class="tl-row" style="--mark:${color}">
      <div class="tl-time">${item.start}</div><div class="tl-mark"></div>
      <div class="tl-body"><div class="grow"><span class="title">${item.title}</span><span class="meta">${item.meta}</span></div><span class="tag-mini" style="--mark:${color}">${item.cat === 'life' ? '生活' : item.cat === 'product' ? '产品' : '工作'}</span></div>
    </div>`;
  };

  const taskRow = (t, dueStyle) => `
    <div class="task-row">
      <span class="check"></span>
      <span class="tag" style="background:${CAT[t.tags[0] === '工作' ? 'work' : t.tags[0] === '产品' ? 'product' : t.tags[0] === '财务' ? 'finance' : 'life']}"></span>
      <span class="t">${t.title}</span>
      <span class="due ${dueStyle || ''}">${t.due || ''}</span>
    </div>`;

  const renderAction = () => {
    const root = document.getElementById('app');
    root.innerHTML = `
      <div class="app">
        ${sidebar('action')}
        <main class="main">
          ${topbar('今日执行')}
          <div class="action-body">
            <section class="action-main">
              <div class="page-head">
                <div>
                  <div class="page-title">10月22日<span>周四</span></div>
                  <div class="page-sub">第 43 周<span class="sep">·</span>九月初二<span class="sep">·</span>明日霜降</div>
                </div>
                <div class="head-actions">
                  <button class="btn-quiet">${ic('layout-list')} 六件事</button>
                  <button class="icon-btn">${ic('dots')}</button>
                  <button class="icon-btn">${ic('plus')}</button>
                </div>
              </div>
              ${weekStrip()}
              <div class="section-head">${ic('clock')}今日时间轴<span class="n">${D.timeline.length}</span><span class="more">事件与任务安排</span></div>
              <div class="sheet">${D.timeline.map(actionRow).join('')}</div>
              <div class="done-strip">${ic('circle-check')}今天已完成 3 项<span style="color:var(--ink-3)">· 最近 11:02 回复供应商报价</span><span class="avatars"><span class="a"></span><span class="a"></span><span class="a"></span></span></div>
            </section>
            <aside class="rail">
              <div class="rail-head"><div class="rail-title">今天要做</div><div class="rail-sub">7 项</div></div>
              <div class="rail-group">
                <div class="rail-label">${ic('alert-triangle')}逾期<span class="n">2</span></div>
                ${D.todos.overdue.map((t) => taskRow(t, 'red')).join('')}
              </div>
              <div class="rail-group">
                <div class="rail-label">${ic('sun')}今天截止<span class="n">3</span></div>
                ${D.todos.dueToday.map((t) => taskRow(t, 'orange')).join('')}
              </div>
              <div class="rail-group">
                <div class="rail-label">${ic('repeat')}重复任务<span class="n">3</span></div>
                ${D.todos.recurring.map((t) => taskRow(t, t.missed ? 'red' : '')).join('')}
              </div>
              <div class="rail-inbox">${ic('inbox')}收件箱 · 未安排<span class="n">4</span>${ic('chevron-right')}</div>
              <div class="progress-card">
                <div class="progress-top">今日完成<b>3 / 10</b></div>
                <div class="progress-track"><div class="progress-fill" style="width:30%"></div></div>
                <div class="progress-note"><span>已安排 4 小时 30 分</span><span>空余 2 小时 10 分</span></div>
              </div>
              <div class="tomorrow">
                <div class="th">${ic('sunrise')}明日 · 霜降<span>3 项事件</span></div>
                <div class="trow"><span class="h">全天</span><span>v0.29 发布</span></div>
                <div class="trow"><span class="h">10:00</span><span>发布检查 · 线上</span></div>
                <div class="trow"><span class="h">15:00</span><span>周复盘 · 会议室 A</span></div>
              </div>
            </aside>
          </div>
        </main>
      </div>`;
  };

  const hm = (s) => {
    const [h, m] = s.split(':').map(Number);
    return h * 60 + m;
  };
  const RANGE_START = 7 * 60;
  const RANGE_END = 21 * 60;
  const GRID_H = 662;
  const y = (m) => ((m - RANGE_START) / (RANGE_END - RANGE_START)) * GRID_H;

  const layout = (items) => {
    const sorted = [...items].sort((a, b) => a.s - b.s || a.e - b.e);
    let cluster = [];
    let clusterEnd = -1;
    const flush = () => {
      const ends = [];
      cluster.forEach((it) => {
        let c = ends.findIndex((end) => end <= it.s);
        if (c === -1) {
          c = ends.length;
          ends.push(it.e);
        } else {
          ends[c] = it.e;
        }
        it.col = c;
      });
      cluster.forEach((it) => { it.cols = ends.length; });
      cluster = [];
      clusterEnd = -1;
    };
    sorted.forEach((it) => {
      if (cluster.length && it.s >= clusterEnd) flush();
      cluster.push(it);
      clusterEnd = Math.max(clusterEnd, it.e);
    });
    if (cluster.length) flush();
    return sorted;
  };

  const eventBlock = (it) => {
    const top = y(it.s);
    const h = Math.max(it.type === 'alloc' ? 20 : 18, y(it.e) - y(it.s));
    const w = 100 / it.cols;
    const left = `${it.col * w}%`;
    const style = `top:${top}px;height:${h}px;left:calc(${left} + 2px);width:calc(${w}% - 4px);--c:${CAT[it.cat] || 'var(--blue)'}`;
    const meta = h >= 32 ? `<div class="m">${it.place || (it.type === 'alloc' ? '任务安排' : '')}</div>` : '';
    return `<div class="ev ${it.type === 'alloc' ? 'alloc' : ''} ${it.cols > 1 ? 'overlap' : ''}" style="${style}"><div class="t">${it.title}</div>${meta}</div>`;
  };

  const renderCalendar = () => {
    const root = document.getElementById('app');
    const days = [0, 1, 2, 3, 4, 5, 6].map((day) => {
      const evs = D.events.filter((e) => e.day === day).map((e) => ({ ...e, s: hm(e.start), e: hm(e.end), type: 'event' }));
      const allocs = D.allocations.filter((a) => a.day === day).map((a) => ({ ...a, s: hm(a.start), e: hm(a.end), type: 'alloc' }));
      return layout([...evs, ...allocs]);
    });
    const hours = [];
    for (let h = 7; h <= 21; h += 1) {
      hours.push(`<div class="hour-line" style="top:${y(h * 60)}px"></div>`);
      if (h < 21) hours.push(`<div class="half-line" style="top:${y(h * 60 + 30)}px"></div>`);
    }
    root.innerHTML = `
      <div class="app">
        ${sidebar('calendar')}
        <main class="main">
          ${topbar('日历')}
          <div class="cal-toolbar">
            <div class="cal-title">10月<span>2026</span></div>
            <div class="seg"><button>日</button><button class="on">周</button><button>月</button></div>
            <div class="cal-legend">
              <span><i class="lg lg-ev"></i>事件</span>
              <span><i class="lg lg-alloc"></i>安排</span>
              <span><i class="lg lg-due"></i>截止</span>
            </div>
            <div class="cal-tools">
              <button class="btn-quiet">今天</button>
              <div class="cal-nav"><button class="icon-btn">${ic('chevron-left')}</button><button class="icon-btn">${ic('chevron-right')}</button></div>
              <button class="icon-btn">${ic('dots')}</button>
            </div>
          </div>
          <div class="cal-grid-wrap">
            <div class="cal-head">
              <div class="gutter"></div>
              <div class="day-heads">
                ${D.week.map((d) => `<div class="day-head ${d.today ? 'today' : ''}"><div class="w">${d.w}</div><div class="d">${d.d}</div>${d.term ? `<span class="term">${d.term}</span>` : ''}</div>`).join('')}
              </div>
            </div>
            <div class="allday">
              <div class="gutter">全天</div>
              <div class="allday-cols">
                ${[0,1,2,3,4,5,6].map((day) => `<div class="allday-col">${D.allDay.filter((a) => a.day === day).map((a) => `<span class="allday-pill ${a.cat === 'term' ? 'term' : ''}" style="--c:${CAT[a.cat]}">${a.cat === 'term' ? ic('sun') + ' ' : ''}${a.title}</span>`).join('')}</div>`).join('')}
              </div>
            </div>
            <div class="cal-scroll">
              <div class="times">${Array.from({ length: 14 }, (_, i) => `<label style="top:${y((8 + i) * 60)}px">${String(8 + i).padStart(2, '0')}:00</label>`).join('')}</div>
              <div class="cols">
                ${days.map((items, day) => `
                  <div class="col ${day > 4 ? 'weekend' : ''} ${day === 3 ? 'today' : ''}">
                    ${hours.join('')}
                    ${items.map(eventBlock).join('')}
                    ${D.deadlines.filter((d) => d.day === day).map((d) => `<div class="deadline-mark ${d.overdue ? 'overdue' : ''}" style="top:${y(hm(d.time))}px"><div class="line"></div><div class="flag">${ic('flag')} ${d.title}</div></div>`).join('')}
                  </div>`).join('')}
                <div class="now-line" style="top:${y(D.today.nowMinutes)}px"><span class="now-dot" style="left:calc(${(3 / 7) * 100}% - 4px)"></span></div>
              </div>
            </div>
          </div>
        </main>
      </div>`;
  };

  const todoRow = (t, opts = {}) => `
    <div class="tr ${opts.overdue ? 'overdue' : ''} ${opts.done ? 'done' : ''}">
      <span class="pri ${t.priority === 1 ? 'p1' : t.priority === 2 ? 'p2' : ''}"></span>
      <span class="cb">${opts.done ? ic('check') : ''}</span>
      <span class="tt">${t.title}</span>
      ${t.repeat ? `<span class="repeat">${ic('repeat')}</span>` : ''}
      ${t.subtasks ? `<span class="sub">${t.subtasks}</span>` : ''}
      <span class="tags">${(t.tags || []).map(tag).join('')}</span>
      <span class="due ${opts.overdue ? 'red' : ''}">${opts.done ? `<span class="at">${t.at}</span>` : (t.late || t.due || '')}</span>
    </div>`;

  const renderTodo = () => {
    const root = document.getElementById('app');
    root.innerHTML = `
      <div class="app">
        ${sidebar('todo')}
        <main class="main">
          ${topbar('待办')}
          <div class="todo-body">
            <section class="todo-main">
              <div class="todo-head">
                <div>
                  <div class="todo-title">待办</div>
                  <div class="todo-sub">19 项未完成，其中 <b>2 项逾期</b> · 今天 7 项</div>
                </div>
                <div class="todo-tools">
                  <button class="btn-quiet">${ic('arrows-sort')} 按截止</button>
                  <button class="btn-primary">${ic('plus')}新建待办</button>
                </div>
              </div>
              <div class="chip-row">
                <button class="chip on">全部</button>
                <button class="chip">今天</button>
                <button class="chip">逾期</button>
                <button class="chip">已安排</button>
                <button class="chip">已完成</button>
                <button class="chip" style="margin-left:auto">${ic('layout-list')}六件事</button>
              </div>
              <div class="group">
                <div class="group-head red">${ic('alert-triangle')}逾期<span class="n">2</span><span class="right">保持原截止日期</span></div>
                <div class="todo-list">${D.todos.overdue.map((t) => todoRow(t, { overdue: true })).join('')}</div>
              </div>
              <div class="group">
                <div class="group-head">${ic('sun')}今天<span class="n">3</span><span class="right">截止与安排分开</span></div>
                <div class="todo-list">${D.todos.dueToday.map((t) => todoRow(t)).join('')}</div>
              </div>
              <div class="group">
                <div class="group-head">${ic('repeat')}重复任务<span class="n">3</span><span class="right">按 occurrence 完成</span></div>
                <div class="todo-list">${D.todos.recurring.map((t) => todoRow(t, { overdue: t.missed })).join('')}</div>
              </div>
              <div class="group">
                <div class="group-head">${ic('calendar')}本周<span class="n">3</span></div>
                <div class="todo-list">${D.todos.thisWeek.map((t) => todoRow(t)).join('')}</div>
              </div>
              <div class="done-strip">${ic('circle-check')}今天已完成 3 项<span style="color:var(--ink-3)">· 回复供应商报价 · 提交周报 · 确认周五场地</span></div>
            </section>
            <aside class="todo-rail">
              <div class="todo-progress">
                <div class="top">今天完成<b>3 / 10</b></div>
                <div class="track"><div class="fill" style="width:30%"></div></div>
                <div class="foot"><span>7 项待完成</span><span>2 项逾期</span><span>5 段安排</span></div>
              </div>
              <div class="six-card" style="margin-bottom:18px">
                <div class="six-head">${ic('sparkles')}六件事<span class="go">专注视图</span></div>
                ${D.sixThings.slice(0, 6).map((s, i) => `<div class="six-row"><span class="ord">${i + 1}</span><div><div class="st ${s.done ? 'done' : ''}">${s.title}</div><div class="sm">${s.meta}</div></div></div>`).join('')}
              </div>
              <div class="rail-label">${ic('inbox')}收件箱 · 未安排<span class="n">4</span></div>
              <div class="todo-list" style="margin-bottom:18px">${D.todos.unplanned.map((t) => `<div class="tr"><span class="pri"></span><span class="cb"></span><span class="tt">${t.title}</span><span class="tags">${t.tags.map(tag).join('')}</span><span class="due">未安排</span></div>`).join('')}</div>
            </aside>
          </div>
        </main>
      </div>`;
  };

  const mobileRow = (item) => {
    const color = CAT[item.cat] || 'var(--blue)';
    if (item.type === 'alloc') {
      return `<div class="m-row alloc" style="--c:${color}"><div class="m-time">${item.start}</div><div class="bar"></div><div class="txt"><div class="t">${item.title}</div><div class="m">${item.meta}</div></div><span class="cb"></span></div>`;
    }
    if (item.type === 'deadline') {
      return `<div class="m-row" style="--c:var(--orange)"><div class="m-time">${item.start}</div><div class="bar"></div><div class="txt"><div class="t" style="color:#9a4d00">${item.title}</div><div class="m">${item.meta}</div></div><i class="ti ti-flag" style="color:var(--orange)"></i></div>`;
    }
    return `<div class="m-row" style="--c:${color}"><div class="m-time">${item.start}</div><div class="bar"></div><div class="txt"><div class="t">${item.title}</div><div class="m">${item.meta}</div></div></div>`;
  };

  const renderMobile = () => {
    const root = document.getElementById('app');
    root.innerHTML = `
      <div class="phone">
        <div class="status"><span>15:42</span><span class="icons">${ic('signal-4g')}${ic('wifi')}${ic('battery-3')}</span></div>
        <div class="m-head">
          <div><div class="m-title">10月22日<span>周四</span></div><div class="m-sub"><button class="m-weeknav">${ic('chevron-left')}</button><span>第 43 周 · 明日霜降 · 7 项要做 · 已完成 3</span><button class="m-weeknav">${ic('chevron-right')}</button></div></div>
          <button class="icon-btn">${ic('search')}</button>
          <button class="icon-btn">${ic('plus')}</button>
        </div>
        <div class="m-week">
          ${D.week.map((d) => `<div class="m-day ${d.today ? 'today' : ''}"><div class="w">${d.w.replace('周', '')}</div><div class="d">${d.d}</div><div class="dot"></div></div>`).join('')}
        </div>
        <div class="m-filters">
          <button class="m-pill on">全部</button>
          <button class="m-pill">事件</button>
          <button class="m-pill">任务</button>
          <button class="m-pill" style="margin-left:auto">${ic('layout-list')}六件事</button>
        </div>
        <div class="m-scroll">
          <div class="m-sec">${ic('alert-triangle')}逾期<span class="n">2</span><span class="right">保持原截止</span></div>
          <div class="m-sheet">
            ${D.todos.overdue.map((t) => `<div class="m-overdue"><span class="cb"></span><span class="t">${t.title}</span><span class="late">${t.late}</span></div>`).join('')}
          </div>
          <div class="m-sec">${ic('clock')}今日时间轴<span class="n">11</span><span class="right">15:42 现在</span></div>
          <div class="m-sheet">
            ${D.timeline.slice(0, 4).map(mobileRow).join('')}
          </div>
          <div class="m-sec">${ic('flag')}今日截止<span class="n">2</span><span class="right">不占时间</span></div>
          <div class="m-sheet">
            <div class="m-row" style="--c:var(--orange)"><div class="m-time">18:00</div><div class="bar"></div><div class="txt"><div class="t">提交 Q4 预算表</div><div class="m">截止 · 子任务 3/5</div></div><i class="ti ti-flag" style="color:var(--orange)"></i></div>
            <div class="m-row" style="--c:var(--orange)"><div class="m-time">今天</div><div class="bar"></div><div class="txt"><div class="t">预约牙医</div><div class="m">截止 · 生活</div></div><i class="ti ti-flag" style="color:var(--orange)"></i></div>
          </div>
          <div class="m-inbox">${ic('inbox')}收件箱 · 未安排<span class="n">4</span>${ic('chevron-right')}</div>
        </div>
        <div class="tabbar">
          <div class="tab on"><span class="ico">${ic('sun')}</span>今日</div>
          <div class="tab"><span class="ico">${ic('calendar')}</span>日历</div>
          <div class="tab"><span class="ico">${ic('checkbox')}</span>待办</div>
        </div>
      </div>`;
  };

  const screen = document.body.dataset.screen;
  const render = { action: renderAction, calendar: renderCalendar, todo: renderTodo, mobile: renderMobile }[screen];
  if (render) render();
})();
