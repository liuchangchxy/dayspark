(() => {
  const D = window.DS;
  const CAT = { work: '#5d6b3b', life: '#2e6b4f', product: '#6d4a87', finance: '#a4781c', term: '#a4781c' };
  const TAG = { 工作: '#5d6b3b', 产品: '#6d4a87', 财务: '#a4781c', 生活: '#2e6b4f' };
  const ic = (n) => `<i class="ti ti-${n}"></i>`;
  const hm = (s) => { const [h, m] = s.split(':').map(Number); return h * 60 + m; };

  const rail = (active) => `
    <aside class="c-rail">
      <div class="c-logo">灵</div>
      <nav class="c-nav">
        <div class="c-nav-item ${active === 'action' ? 'on' : ''}">${ic('sun')}今日</div>
        <div class="c-nav-item ${active === 'calendar' ? 'on' : ''}">${ic('calendar')}日历</div>
        <div class="c-nav-item ${active === 'todo' ? 'on' : ''}">${ic('checkbox')}待办</div>
      </nav>
      <div class="c-rail-sep"></div>
      <nav class="c-nav">
        <div class="c-nav-item">${ic('inbox')}收件</div>
        <div class="c-nav-item">${ic('tag')}标签</div>
        <div class="c-nav-item">${ic('search')}搜索</div>
      </nav>
      <div class="c-rail-bottom">
        <div class="c-nav-item">${ic('settings')}设置</div>
        <div class="c-avatar">常</div>
      </div>
    </aside>`;

  const band = () => {
    const start = 6 * 60, end = 24 * 60, span = end - start;
    const blocks = D.timeline.filter((t) => t.type !== 'deadline').map((t) => {
      const s = hm(t.start), e = hm(t.end);
      return `<span class="c-block ${t.type === 'alloc' ? 'alloc' : ''}" style="left:${(s - start) / span * 100}%;width:${Math.max(0.7, (e - s) / span * 100)}%;--c:${CAT[t.cat] || '#5d6b3b'}"></span>`;
    }).join('');
    return `<div class="c-band">
      <div class="c-band-top"><span class="em">今日光带</span><span>06 - 24</span><span class="r">6 事件 · 5 安排</span></div>
      <div class="c-track">${blocks}<span class="c-now" style="left:${(D.today.nowMinutes - start) / span * 100}%"></span></div>
      <div class="c-axis"><span>06</span><span>09</span><span>12</span><span>15</span><span>18</span><span>21</span><span>24</span></div>
      <div class="c-band-legend"><span><i class="sw"></i>事件</span><span><i class="sw a"></i>任务安排</span><span style="margin-left:auto;font-family:var(--mono)">2 截止</span></div>
    </div>`;
  };

  const tlRow = (t) => {
    const cat = CAT[t.cat] || '#5d6b3b';
    if (t.type === 'deadline') {
      return `<div class="c-tl-row dl" style="--c:${cat}"><span class="t">${t.start}</span><span class="mark"></span><span class="body"><span class="title">${t.title}</span><span class="meta">${t.meta}</span></span><span class="right cat" style="color:var(--persimmon)">截止</span></div>`;
    }
    return `<div class="c-tl-row ${t.type === 'alloc' ? 'alloc' : ''}" style="--c:${cat}"><span class="t">${t.start}</span><span class="mark"></span><span class="body"><span class="title">${t.title}</span><span class="meta">${t.meta}</span></span><span class="right ${t.type === 'alloc' ? '' : 'cat'}">${t.type === 'alloc' ? '安排' : `${hm(t.end) - hm(t.start)} 分`}</span></div>`;
  };

  const sideRow = (t, o = {}) => `<div class="c-side-row"><span class="box ${o.round ? 'round' : ''}"></span><span class="txt">${t.title}<span class="meta">${o.meta || ''}</span></span><span class="due ${o.red ? 'red' : ''}">${o.due || ''}</span></div>`;

  const renderAction = () => {
    document.getElementById('app').innerHTML = `
      <div class="shell">
        ${rail('action')}
        <main class="c-main">
          <header class="c-head">
            <div class="c-date"><div class="big">22</div><div class="month">十月<span>${D.today.weekday} · 第 43 周</span></div></div>
            ${band()}
            <div class="c-lunar"><b>九月初二</b>丙午年 戊戌月<span class="term">明日霜降 · 10/23</span><span class="sync">已同步 15:40</span></div>
          </header>
          <div class="c-body">
            <section class="c-day">
              <div class="c-label">时间轴<span class="en">THE DAY</span><span class="r">11 项 · 15:42 现在</span></div>
              <div class="c-tl">${D.timeline.map(tlRow).join('')}</div>
              <div class="c-done">${ic('circle-check')}今天已完成 3 项<span class="r">最近 11:02 · 回复供应商报价</span></div>
              <div class="c-label" style="margin-top:12px;font-size:13px;border-bottom-color:var(--rule)">明日<span class="en">NEXT</span><span class="r">霜降</span></div>
              <div class="c-tl">
                <div class="c-tl-row" style="--c:var(--violet);height:32px"><span class="t">全天</span><span class="mark"></span><span class="body"><span class="title" style="font-size:12px">v0.29 发布</span></span><span class="right">产品</span></div>
                <div class="c-tl-row" style="--c:var(--olive);height:32px"><span class="t">10:00</span><span class="mark"></span><span class="body"><span class="title" style="font-size:12px">发布检查</span><span class="meta">线上</span></span><span class="right">60 分</span></div>
                <div class="c-tl-row" style="--c:var(--olive);height:32px"><span class="t">15:00</span><span class="mark"></span><span class="body"><span class="title" style="font-size:12px">周复盘</span><span class="meta">会议室 A</span></span><span class="right">60 分</span></div>
              </div>
            </section>
            <aside class="c-side">
              <div class="c-side-head">今日要做<span class="n">8 项</span></div>
              <div class="c-side-group">
                <div class="c-side-label red">逾期<span class="n">2</span></div>
                ${D.todos.overdue.map((t) => sideRow(t, { meta: t.late, due: t.late, red: true, round: true })).join('')}
              </div>
              <div class="c-side-group">
                <div class="c-side-label">今天截止<span class="n">3</span></div>
                ${D.todos.dueToday.map((t) => sideRow(t, { meta: t.subtasks ? `子任务 ${t.subtasks}` : '截止事项', due: t.due.replace('今天 ', ''), round: true })).join('')}
              </div>
              <div class="c-side-group">
                <div class="c-side-label">重复<span class="n">3</span></div>
                ${D.todos.recurring.map((t) => sideRow(t, { meta: t.occurrence || (t.missed ? '错过，保持待办' : ''), due: t.missed ? '逾期' : '今天', round: true, red: t.missed })).join('')}
              </div>
              <div class="c-inbox">${ic('inbox')}收件箱 · 未安排<span class="n">4 →</span></div>
              <div class="c-side-group">
                <div class="c-side-label">今日完成<span class="n">3</span></div>
                ${D.todos.completed.map((t) => `<div class="c-side-row" style="min-height:28px;padding:4px 0"><span class="box" style="background:var(--green);border-color:var(--green)"></span><span class="txt" style="color:var(--ink-3);text-decoration:line-through">${t.title}</span><span class="due">${t.at}</span></div>`).join('')}
              </div>
              <div class="c-side-foot"><b>注记</b><br>15:30 评审结束后直接整理纪要，没有缓冲。<br>域名续签已逾期 3 天，约 5 分钟可完成。</div>
            </aside>
          </div>
        </main>
      </div>`;
  };

  const RANGE_START = 7 * 60, RANGE_END = 21 * 60, GRID_H = 700;
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

  const calBlock = (it) => {
    const top = y(it.s), h = Math.max(14, y(it.e) - y(it.s));
    const w = 100 / it.cols, left = it.col * w;
    return `<div class="c-ev ${it.type === 'alloc' ? 'alloc' : ''}" style="top:${top}px;height:${h}px;left:calc(${left}% + 1px);width:calc(${w}% - 2px);--c:${CAT[it.cat] || '#5d6b3b'}"><div class="t">${it.title}</div>${h > 28 ? `<div class="m">${it.place || '任务安排'}</div>` : ''}</div>`;
  };

  const renderCalendar = () => {
    const days = [0, 1, 2, 3, 4, 5, 6].map((day) => {
      const evs = D.events.filter((e) => e.day === day).map((e) => ({ ...e, s: hm(e.start), e: hm(e.end), type: 'event' }));
      const allocs = D.allocations.filter((a) => a.day === day).map((a) => ({ ...a, s: hm(a.start), e: hm(a.end), type: 'alloc' }));
      return layout([...evs, ...allocs]);
    });
    const lines = [];
    for (let h = 7; h <= 21; h += 1) {
      lines.push(`<div class="c-hl" style="top:${y(h * 60)}px"></div>`);
      if (h < 21) lines.push(`<div class="c-hl half" style="top:${y(h * 60 + 30)}px"></div>`);
    }
    document.getElementById('app').innerHTML = `
      <div class="shell">
        ${rail('calendar')}
        <main class="c-main">
          <div class="c-cal-head">
            <div class="c-cal-title">十月<span>2026 · 第 43 周</span></div>
            <div class="c-tabs"><button>日</button><button class="on">周</button><button>月</button></div>
            <div class="c-cal-tools"><button class="c-txt-btn">今天</button><button class="c-arrow">${ic('chevron-left')}</button><button class="c-arrow">${ic('chevron-right')}</button><button class="c-mk">${ic('plus')}事件</button></div>
          </div>
          <div class="c-cal-body">
            <div class="c-cal-main">
              <div class="c-cal-headrow">
                <div class="c-gutter"></div>
                <div class="c-dayheads">${D.week.map((d) => `<div class="c-dayhead ${d.today ? 'today' : ''}"><div class="w">${d.w}</div><div class="d">${d.d}</div>${d.term ? `<span class="term">${d.term}</span>` : ''}</div>`).join('')}</div>
              </div>
              <div class="c-allday">
                <div class="c-gutter">全天</div>
                <div class="c-allday-cols">${[0,1,2,3,4,5,6].map((day) => `<div class="c-allday-col">${D.allDay.filter((a) => a.day === day).map((a) => `<span class="c-ad ${a.cat === 'term' ? 'term' : ''}" style="--c:${CAT[a.cat]}">${a.title}</span>`).join('')}</div>`).join('')}</div>
              </div>
              <div class="c-cal-scroll">
                <div class="c-times">${Array.from({ length: 14 }, (_, i) => `<label style="top:${y((8 + i) * 60)}px">${String(8 + i).padStart(2, '0')}:00</label>`).join('')}</div>
                <div class="c-cols">
                  ${days.map((items, day) => `<div class="c-col">${lines.join('')}${items.map(calBlock).join('')}${D.deadlines.filter((d) => d.day === day).map((d) => `<div class="c-dl ${d.overdue ? 'red' : ''}" style="top:${y(hm(d.time))}px"><div class="line"></div><div class="flag">${d.title}</div></div>`).join('')}</div>`).join('')}
                  <div class="c-nowline" style="top:${y(D.today.nowMinutes)}px"><span class="d"></span></div>
                </div>
              </div>
            </div>
            <aside class="c-cal-margin">
              <div class="c-margin-lab">选中事件 / SELECTED</div>
              <div class="c-sel-title">Q4 规划评审</div>
              <div class="c-sel-when">周四 10/22 · 14:00 - 15:30</div>
              <div class="c-sel-place">线上 · 产品 · 8 人</div>
              <div class="c-people"><span class="p">林</span><span class="p">周</span><span class="p">陈</span><span class="p">许</span><span class="p">+4</span></div>
              <div class="c-note">15:30 紧接「整理评审纪要」任务安排，没有缓冲时间。</div>
              <div class="c-margin-lab" style="margin-top:12px">本周负载 / WEEK</div>
              <div class="c-week">${D.week.map((d) => `<div class="c-week-row ${d.today ? 'today' : ''}"><span>${d.w}</span><span class="bar"><span style="width:${d.load}%"></span></span><span class="v">${d.load}</span></div>`).join('')}</div>
              <div class="c-margin-lab" style="margin-top:12px">图例 / LEGEND</div>
              <div class="c-legend"><div class="li"><span class="sw"></span>事件 · 占时间</div><div class="li"><span class="sw a"></span>任务安排 · 可移动</div><div class="li"><span class="sw d"></span>截止 · 不占时间</div></div>
              <div class="c-side-foot" style="margin-top:12px"><b>霜降</b> · 明日 10/23<br>九月初三 · 宜收尾</div>
            </aside>
          </div>
          <div class="c-cal-foot"><span>6 事件 · 5 安排 · 2 截止</span><span class="r">本地优先 · 已同步 15:40</span></div>
        </main>
      </div>`;
  };

  const tag = (t) => `<span class="tag" style="--tc:${TAG[t] || '#5e635a'}">${t}</span>`;

  const trow = (t, o = {}) => `
    <div class="c-row ${o.overdue ? 'overdue' : ''} ${o.done ? 'done' : ''}">
      <span class="pri ${t.priority === 1 ? 'p1' : t.priority === 2 ? 'p2' : ''}"></span>
      <span class="ck">${o.done ? ic('check') : ''}</span>
      <span class="tt">${t.title}</span>
      <span class="tags">${(t.tags || []).map(tag).join('')}</span>
      <span class="due ${o.overdue || t.missed ? 'red' : ''}">${o.done ? t.at : (t.late || t.due || '未安排')}</span>
      <span class="sub">${t.subtasks || ''}</span>
    </div>`;

  const renderTodo = () => {
    document.getElementById('app').innerHTML = `
      <div class="shell">
        ${rail('todo')}
        <main class="c-main">
          <div class="c-todo-head">
            <div class="c-todo-title">待办</div>
            <div class="c-todo-sub">19 项未完成 · <b>2 项逾期</b> · 今天 7 项</div>
            <div class="c-open"><span class="n">19</span><span class="l">未完成<br>OPEN</span></div>
          </div>
          <div class="c-todo-bar">
            <button class="c-filter on">全部</button><button class="c-filter">今天</button><button class="c-filter">逾期</button><button class="c-filter">已安排</button><button class="c-filter">已完成</button>
            <span class="r"><span>六件事</span><span class="sort">按截止</span><span>${ic('plus')} 新建</span></span>
          </div>
          <div class="c-todo-body">
            <section class="c-todo-main">
              <div class="c-group">
                <div class="c-group-head red">逾期<span class="n">02</span><span class="r">保持真实截止日期</span></div>
                ${D.todos.overdue.map((t) => trow(t, { overdue: true })).join('')}
              </div>
              <div class="c-group">
                <div class="c-group-head">今天<span class="n">03</span><span class="r">截止与执行分开</span></div>
                ${D.todos.dueToday.map((t) => trow(t)).join('')}
              </div>
              <div class="c-group">
                <div class="c-group-head">重复任务<span class="n">03</span><span class="r">按 occurrence 完成</span></div>
                ${D.todos.recurring.map((t) => trow(t, { overdue: t.missed })).join('')}
              </div>
              <div class="c-group">
                <div class="c-group-head">本周<span class="n">03</span><span class="r">10/22 - 10/25</span></div>
                ${D.todos.thisWeek.map((t) => trow(t)).join('')}
              </div>
              <div class="c-completed">${ic('circle-check')}今天已完成 3 项<span class="r">回复供应商报价 · 提交周报 · 确认周五场地</span></div>
            </section>
            <aside class="c-todo-side">
              <div class="c-six-head">六件事<span class="r">FOCUS · 上限 6</span></div>
              ${D.sixThings.map((s, i) => `<div class="c-six"><span class="ord">${String(i + 1).padStart(2, '0')}</span><div><div class="t">${s.title}</div><div class="m">${s.meta}</div></div></div>`).join('')}
              <div class="c-side-block">
                <div class="lab">收件箱 · 未安排<span class="n">4</span></div>
                ${D.todos.unplanned.map((t) => `<div class="c-side-item"><span class="dot" style="--tc:${TAG[t.tags[0]]}"></span><span class="tt">${t.title}</span><span class="d">未安排</span></div>`).join('')}
              </div>
              <div class="c-side-block">
                <div class="lab">今天完成<span class="n">3</span></div>
                ${D.todos.completed.map((t) => `<div class="c-side-item" style="color:var(--ink-3)"><span class="tt" style="text-decoration:line-through">${t.title}</span><span class="d">${t.at}</span></div>`).join('')}
              </div>
              <div class="c-side-foot" style="margin-top:14px"><b>拖拽</b>到时间轴创建任务安排，截止时间不变。<br><b>空格</b>完成 · <b>E</b> 编辑 · <b>S</b> 安排时间。</div>
            </aside>
          </div>
        </main>
      </div>`;
  };

  const mrow = (t) => {
    if (t.type === 'deadline') {
      return `<div class="m-row dl" style="--c:var(--persimmon)"><span class="t">${t.start}</span><span class="mark"></span><span class="body"><span class="tt">${t.title}</span><span class="meta">${t.meta}</span></span><span class="act"><span class="ck round"></span><span class="lb">截止</span></span></div>`;
    }
    if (t.type === 'alloc') {
      return `<div class="m-row alloc" style="--c:${CAT[t.cat] || '#5d6b3b'}"><span class="t">${t.start}</span><span class="mark"></span><span class="body"><span class="tt">${t.title}</span><span class="meta">${t.meta}</span></span><span class="act"><span class="ck"></span><span class="lb">安排</span></span></div>`;
    }
    return `<div class="m-row" style="--c:${CAT[t.cat] || '#5d6b3b'}"><span class="t">${t.start}</span><span class="mark"></span><span class="body"><span class="tt">${t.title}</span><span class="meta">${t.meta}</span></span><span class="due">${hm(t.end) - hm(t.start)} 分</span></div>`;
  };

  const renderMobile = () => {
    const start = 6 * 60, end = 24 * 60, span = end - start;
    const blocks = D.timeline.filter((t) => t.type !== 'deadline').map((t) => {
      const s = hm(t.start), e = hm(t.end);
      return `<span class="b ${t.type === 'alloc' ? 'a' : ''}" style="left:${(s - start) / span * 100}%;width:${Math.max(0.8, (e - s) / span * 100)}%;--c:${CAT[t.cat] || '#5d6b3b'}"></span>`;
    }).join('');
    const timeline = D.timeline.slice(0, 6);
    document.getElementById('app').innerHTML = `
      <div class="phone">
        <div class="m-status"><span>15:42</span><span class="ic">${ic('signal-4g')}${ic('wifi')}${ic('battery-3')}</span></div>
        <div class="m-top"><span class="m-brand">灵光<span>DAYSPARK</span></span><span class="acts">${ic('search')}<span class="six-jump">六件事</span><span class="add">${ic('plus')}</span></span></div>
        <div class="m-hero">
          <button class="m-chev">${ic('chevron-left')}</button>
          <div class="big">22</div>
          <div class="mid"><div class="mon">十月</div><div class="wk">周四 · 第 43 周</div></div>
          <div class="lun">九月初二<br><b>霜降 · 明日</b></div>
          <button class="m-chev">${ic('chevron-right')}</button>
        </div>
        <div class="m-band">
          <div class="top"><span>今日光带</span><span>06 - 24</span><span class="r"><i class="sw solid"></i>事件 6<i class="sw hollow"></i>安排 5</span></div>
          <div class="tr">${blocks}<span class="n" style="left:${(D.today.nowMinutes - start) / span * 100}%"></span></div>
          <div class="ax"><span>06</span><span>09</span><span>12</span><span>15</span><span>18</span><span>21</span><span>24</span></div>
        </div>
        <div class="m-scroll">
          <div class="m-sec red">逾期<span class="n">2</span><span class="r">保持原截止</span></div>
          ${D.todos.overdue.map((t) => `<div class="m-overdue"><span class="box"></span><span class="tt">${t.title}</span><span class="late">${t.late}</span></div>`).join('')}
          <div class="m-sec">时间轴<span class="n">11</span><span class="r">15:42 现在</span></div>
          ${timeline.map(mrow).join('')}
          <div class="m-sec">截止<span class="n">2</span><span class="r">不占时间</span></div>
          <div class="m-row dl" style="--c:var(--persimmon)"><span class="t">18:00</span><span class="mark"></span><span class="body"><span class="tt">提交 Q4 预算表</span><span class="meta">子任务 3/5</span></span><span class="act"><span class="ck round"></span><span class="lb">截止</span></span></div>
          <div class="m-row dl" style="--c:var(--persimmon)"><span class="t">今天</span><span class="mark"></span><span class="body"><span class="tt">预约牙医</span><span class="meta">生活</span></span><span class="act"><span class="ck round"></span><span class="lb">截止</span></span></div>
          <div class="m-done">${ic('circle-check')}今天已完成 3 项<span class="r">11:02 最后一项</span></div>
          <div class="m-inbox">${ic('inbox')}收件箱 · 未安排<span class="n">4 →</span></div>
        </div>
        <div class="m-nav"><div class="m-tab on">${ic('sun')}今日</div><div class="m-tab">${ic('calendar')}日历</div><div class="m-tab">${ic('checkbox')}待办</div></div>
      </div>`;
  };

  const screen = document.body.dataset.screen;
  const render = { action: renderAction, calendar: renderCalendar, todo: renderTodo, mobile: renderMobile }[screen];
  if (render) render();
})();
