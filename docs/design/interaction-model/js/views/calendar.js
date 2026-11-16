/* Calendar: month / week / day. Events occupy time, allocations are movable,
   deadlines live in their own lane and never occupy the grid. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  // A 30-minute block is the smallest thing a finger has to hit, so on a phone
  // the hour itself grows until half an hour is 48px tall. The alternative —
  // expanding the hit box with a pseudo-element — made neighbouring blocks
  // steal each other's taps.
  const HOUR_H = () => (U.isNarrow() ? 192 : 48);
  const DAY_END = 24;
  // Early hours are folded by default: nobody plans a 03:00 meeting often, and
  // the four empty rows cost more than they explain. Expanding is one tap and
  // stays for the session.
  function dayStart() { return S.state.dawnOpen ? 0 : 6; }

  // One browsed date, shared with Todo · 按日期 (CORE_UX_SPEC 16.1).
  function anchor() { return S.browseDate(); }
  function setAnchor(d, focusDay) {
    const day = U.startOfDay(d);
    S.state.calendarAnchor = day;
    S.setBrowseDate(day);
    if (focusDay) S.state.calendarFocusDay = day;
    App.render();
  }
  function setView(v) { S.state.calendarView = v; App.render(); }

  function openEvent(e) {
    App.openRecord('event', e.id, e.isOccurrence ? e.startDt.getTime() : null);
  }
  function openTodo(todo, day) {
    App.openRecord('todo', todo.id, null, day || anchor());
  }

  // The series' deadline time applied to the occurrence's own day.
  function occurrenceDeadline(due, day) {
    const d = U.startOfDay(day);
    const src = new Date(due);
    if (src.getHours() === 0 && src.getMinutes() === 0) return d;
    d.setHours(src.getHours(), src.getMinutes(), 0, 0);
    return d;
  }

  function shift(dir) {
    const a = anchor();
    const v = S.state.calendarView;
    if (v === 'month') {
      // Keep the day of the month and clamp at shorter months: paging from
      // 31 January used to land on 1 February and move the shared browseDate.
      const day = a.getDate();
      const last = new Date(a.getFullYear(), a.getMonth() + dir + 1, 0).getDate();
      setAnchor(new Date(a.getFullYear(), a.getMonth() + dir, Math.min(day, last)));
    }
    else if (v === 'week') setAnchor(U.addDays(a, 7 * dir));
    else setAnchor(U.addDays(a, dir));
  }

  function titleFor() {
    const a = anchor();
    const v = S.state.calendarView;
    if (v === 'month') return U.fmtMonthYear(a);
    if (v === 'week') return U.fmtMonthYear(weekDays()[0]);
    if (U.isNarrow()) {
      return S.state.lang === 'zh'
        ? `${a.getFullYear()}年${a.getMonth() + 1}月${a.getDate()}日`
        : `${U.fmtMonthDay(a)} ${a.getFullYear()}`;
    }
    return U.fmtMonthYear(a) + ' · ' + U.fmtMonthDay(a);
  }

  function weekDays() {
    const a = anchor();
    const ws = U.startOfWeek(a, S.state.weekStartsOn);
    const count = U.isNarrow() ? 3 : 7;
    const startIdx = U.isNarrow() ? Math.max(0, Math.min(4, Math.round((U.startOfDay(a) - ws) / U.MS_DAY))) : 0;
    const days = [];
    for (let i = 0; i < count; i++) days.push(U.addDays(ws, startIdx + i));
    return days;
  }

  function subFor() {
    const a = anchor();
    const v = S.state.calendarView;
    if (v === 'day') return U.esc(U.fmtWeekdayLong(a));
    if (v === 'week') {
      const days = weekDays();
      const first = days[0];
      const last = days[days.length - 1];
      return U.esc(U.fmtMonthDay(first)) + ' – ' + U.esc(U.fmtMonthDay(last));
    }
    return '';
  }

  // ---------- month ----------
  function renderMonth(content) {
    const a = anchor();
    const today = U.startOfDay(U.now());
    const first = U.startOfMonth(a);
    const gridStart = U.startOfWeek(first, S.state.weekStartsOn);
    const weeks = [];
    let cursor = gridStart;
    for (let w = 0; w < 6; w++) {
      const row = [];
      for (let i = 0; i < 7; i++) { row.push(cursor); cursor = U.addDays(cursor, 1); }
      weeks.push(row);
      if (cursor > U.endOfMonth(a) && w >= 4) break;
    }

    content.appendChild(deadlineLane(a, 'month'));

    const wrap = U.el('div', { class: 'month-wrap' });
    const dow = U.el('div', { class: 'month-dow' });
    for (let i = 0; i < 7; i++) {
      const d = U.addDays(gridStart, i);
      dow.appendChild(U.el('span', { text: U.fmtWeekdayShort(d) }));
    }
    wrap.appendChild(dow);

    const grid = U.el('div', { class: 'month-grid', 'data-testid': 'month-grid' });
    weeks.forEach((row) => row.forEach((d) => {
      const cell = U.el('button', {
        class: 'month-cell' + (U.sameMonth(d, a) ? '' : ' other') + (U.sameDay(d, today) ? ' today' : ''),
        'aria-label': U.fmtMonthDay(d) + ' ' + U.fmtWeekdayLong(d),
      });
      const events = S.eventsOnDay(d);
      const allocs = S.allocationsOnDay(d);
      // A recurring series owns one deadline per occurrence day, and a finished
      // occurrence is not an open deadline — the cell must agree with the lane.
      const due = [];
      S.liveTodos().filter((x) => S.isOpen(x) && x.dueDate).forEach((x) => {
        if (!x.recurrence) {
          if (U.sameDay(x.dueDate, d)) due.push({ todo: x, due: x.dueDate });
          return;
        }
        const day = U.startOfDay(d);
        if (!S.matchesRule(x, day)) return;
        if (S.isOccurrenceDone(x, S.occurrenceIdFor(x, day))) return;
        due.push({ todo: x, due: occurrenceDeadline(x.dueDate, day) });
      });
      const head = U.el('div', { class: 'mhead' });
      head.innerHTML = `<span class="mday">${d.getDate()}</span>`;
      if (S.state.showLunar && d.getDate() === 1) head.innerHTML += `<span class="lunar">${U.esc(t('lunarSample'))}</span>`;
      cell.appendChild(head);

      const items = [];
      events.forEach((e) => items.push({ kind: 'evt', label: e.summary, color: S.calendarColor(e.calendarId), time: e.isAllDay ? '' : U.fmtTime(e.startDt), data: e }));
      allocs.forEach((x) => items.push({ kind: 'alloc', label: S.todoById(x.todoId) ? S.todoById(x.todoId).summary : '', time: U.fmtTime(x.startAt), data: x }));
      due.forEach((x) => items.push({ kind: 'due', label: x.todo.summary, time: U.fmtClockNoMidnight(x.due), data: x.todo }));

      if (U.isNarrow()) {
        const dots = U.el('div', { class: 'mdots' });
        items.slice(0, 3).forEach((it) => {
          const dot = U.el('span', { class: 'mdot ' + it.kind });
          dot.style.background = it.color || (it.kind === 'alloc' ? 'var(--violet)' : 'var(--amber)');
          dots.appendChild(dot);
        });
        if (items.length > 3) dots.appendChild(U.el('span', { class: 'mmore', text: '+' + (items.length - 3) }));
        cell.appendChild(dots);
        cell.setAttribute('aria-label', `${U.fmtMonthDay(d)} ${U.fmtWeekdayLong(d)} · ${items.length}`);
        cell.addEventListener('click', () => {
          // On a phone a month cell is too small to preview anything, so a tap
          // only drills into a day that has something to show. An empty cell
          // would open an empty day and cost a back-press to leave.
          if (!items.length) { UI.toast(t('phoneDrillHint'), { duration: 1600 }); return; }
          S.state.calendarFocusDay = U.startOfDay(d);
          S.state.calendarAnchor = U.startOfDay(d);
          // Picking a day in the calendar is the gesture that moves the shared
          // browse date, so Todo · 按日期 lands on the same day.
          S.setBrowseDate(U.startOfDay(d));
          S.state.calendarView = 'day';
          App.render();
        });
        grid.appendChild(cell);
        return;
      }

      const max = 3;
      items.slice(0, max).forEach((it) => {
        const chip = U.el('span', { class: 'month-event ' + it.kind });
        if (it.color) chip.style.setProperty('--c', it.color);
        chip.innerHTML = `<span class="dot" style="background:${it.color || (it.kind === 'alloc' ? 'var(--violet)' : 'var(--amber)')}"></span><span style="overflow:hidden;text-overflow:ellipsis">${U.esc(it.time ? it.time + ' ' : '')}${U.esc(it.label)}</span>`;
        cell.appendChild(chip);
      });
      if (items.length > max) cell.appendChild(U.el('span', { class: 'month-more', text: '+' + (items.length - max) }));

      const drill = () => {
        S.state.calendarFocusDay = U.startOfDay(d);
        S.state.calendarAnchor = U.startOfDay(d);
        S.setBrowseDate(U.startOfDay(d));
        S.state.calendarView = 'day';
        App.render();
      };
      // Desktop months have room for a creation gesture the phone does not:
      // double-clicking a cell opens a new event at the next hour. The single
      // click has to wait for the second one, because drilling re-renders and
      // the fresh cell can never receive the dblclick.
      let clickTimer = null;
      cell.addEventListener('click', () => {
        if (U.isNarrow()) { drill(); return; }
        if (clickTimer) return;
        clickTimer = setTimeout(() => { clickTimer = null; drill(); }, 220);
      });
      cell.addEventListener('dblclick', (ev) => {
        ev.preventDefault();
        if (clickTimer) { clearTimeout(clickTimer); clickTimer = null; }
        const now = U.now();
        const hour = U.sameDay(d, now) ? Math.min(23, now.getHours() + 1) : 9;
        const start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), hour, 0);
        App.openComposer('event', { startDt: start, endDt: U.addMinutes(start, 60) });
      });
      grid.appendChild(cell);
    }));
    wrap.appendChild(grid);
    content.appendChild(wrap);
    content.appendChild(legend('month'));
  }

  // ---------- deadline lane ----------
  function deadlineLane(a, mode) {
    const lane = U.el('div', { class: 'deadline-lane', 'data-testid': 'deadline-lane' });
    lane.appendChild(U.el('span', { class: 'lane-label', html: ICON('flag', 12) + `<span>${U.esc(t('deadlineLane'))}</span>` }));
    const from = mode === 'month' ? U.startOfMonth(a) : U.startOfDay(a);
    const to = mode === 'month' ? U.endOfMonth(a) : U.endOfDay(U.addDays(a, mode === 'week' ? 6 : 0));
    // A recurring series has no single deadline date: each occurrence owns the
    // series' time of day on its own day. Filtering the raw anchor hid every
    // series whose anchor sat outside the visible range, while the dated list
    // showed those same deadlines as due.
    const items = [];
    S.liveTodos().filter((x) => S.isOpen(x) && x.dueDate).forEach((todo) => {
      if (!todo.recurrence) {
        if (todo.dueDate >= from && todo.dueDate <= to) items.push({ todo, due: todo.dueDate, day: U.startOfDay(todo.dueDate) });
        return;
      }
      S.occurrencesInWindow(todo, U.startOfDay(from), U.startOfDay(to)).forEach((occDay) => {
        // A finished instance is history, not an open deadline; the dated list
        // already splits done instances out, and the two must agree (I13).
        if (S.isOccurrenceDone(todo, S.occurrenceIdFor(todo, occDay))) return;
        const due = occurrenceDeadline(todo.dueDate, occDay);
        if (due >= from && due <= to) items.push({ todo, due, day: occDay });
      });
    });
    items.sort((x, y) => x.due - y.due);
    if (!items.length) {
      lane.appendChild(U.el('span', { class: 'tiny muted', text: S.state.lang === 'zh' ? '这段时间没有截止事项' : 'No deadlines in this range' }));
      return lane;
    }
    const chipFor = (item) => {
      const chip = U.el('button', { class: 'deadline-chip' });
      const overdue = U.startOfDay(item.due) < U.startOfDay(U.now());
      chip.innerHTML = `<span class="date" style="${overdue ? 'color:var(--red)' : ''}">${U.esc(U.fmtDeadline(item.due))}</span><span>${U.esc(item.todo.summary)}</span>`;
      // The chip stands for one occurrence: open that day, not the browsed one.
      chip.addEventListener('click', () => openTodo(item.todo, item.day));
      return chip;
    };
    if (U.isNarrow()) {
      // One scrolling line on phones: the lane must not push the grid off screen.
      lane.classList.add('scroll');
      const rail = U.el('div', { class: 'lane-rail' });
      items.forEach((item) => rail.appendChild(chipFor(item)));
      lane.appendChild(rail);
      return lane;
    }
    const expanded = S.state.deadlineExpanded;
    const visible = expanded ? items : items.slice(0, 8);
    visible.forEach((item) => lane.appendChild(chipFor(item)));
    if (items.length > 8) {
      const fold = U.el('button', {
        class: 'deadline-chip more',
        'data-testid': expanded ? 'deadline-less' : 'deadline-more',
      });
      fold.innerHTML = expanded
        ? `<span>${U.esc(t('collapseList'))}</span>`
        : `<span>${U.esc(t('moreItems', { n: items.length - 8 }))}</span>`;
      fold.addEventListener('click', () => { S.state.deadlineExpanded = !expanded; App.render(); });
      lane.appendChild(fold);
    }
    return lane;
  }

  function legend(mode) {
    const lg = U.el('div', { class: 'cal-legend' });
    const hint = mode === 'month' ? t('monthCellHint') : t('tapSlotHint');
    lg.innerHTML = `
      <span class="lg"><span class="sw"></span>${U.esc(S.state.lang === 'zh' ? '日程（占时间）' : 'Event (occupies time)')}</span>
      <span class="lg"><span class="sw alloc"></span>${U.esc(S.state.lang === 'zh' ? '安排（可移动）' : 'Scheduled time (movable)')}</span>
      <span class="lg"><span class="sw due"></span>${U.esc(S.state.lang === 'zh' ? '截止（不占时间）' : 'Deadline (no time)')}</span>
      <span class="lg" style="margin-left:auto">${U.esc(hint)}</span>`;
    return lg;
  }

  // ---------- time grid ----------
  function renderTimeGrid(content, days, opts) {
    const narrow = U.isNarrow();
    content.appendChild(deadlineLane(days[0], days.length === 1 ? 'day' : 'week'));
    const wrap = U.el('div', { class: 'time-wrap' });
    const hh = HOUR_H();
    const ds = dayStart();
    const gridH = (DAY_END - ds) * hh;

    const head = U.el('div', { class: 'time-head' });
    head.appendChild(U.el('div', { class: 'gutter' }));
    days.forEach((d) => {
      const col = U.el('div', { class: 'daycol' + (U.sameDay(d, U.now()) ? ' today' : '') + (opts && opts.focus && U.sameDay(d, opts.focus) ? ' on' : '') });
      col.innerHTML = `<div class="dow">${U.esc(U.fmtWeekdayShort(d))}</div><div class="num">${d.getDate()}</div>`;
      head.appendChild(col);
    });
    wrap.appendChild(head);

    const allDay = U.el('div', { class: 'all-day-row' });
    allDay.appendChild(U.el('div', { class: 'gutter', text: t('allDay') }));
    days.forEach((d) => {
      const col = U.el('div', { class: 'daycol' });
      S.eventsOnDay(d).filter((e) => e.isAllDay).forEach((e) => {
        const chip = U.el('button', { class: 'month-event evt', style: 'height:19px' });
        chip.style.setProperty('--c', S.calendarColor(e.calendarId));
        chip.innerHTML = `<span class="dot" style="background:${S.calendarColor(e.calendarId)}"></span><span>${U.esc(e.summary)}</span>`;
        chip.addEventListener('click', () => openEvent(e));
        col.appendChild(chip);
      });
      allDay.appendChild(col);
    });
    wrap.appendChild(allDay);

    const scroll = U.el('div', { class: 'time-scroll', 'data-testid': 'time-scroll' });
    const body = U.el('div', { class: 'time-body' });
    body.style.height = gridH + 'px';

    const gutter = U.el('div', { class: 'time-gutter' });
    for (let h = ds; h < DAY_END; h++) {
      const lab = U.el('span', { class: 'hour-label', text: U.pad(h) + ':00' });
      lab.style.top = ((h - ds) * hh) + 'px';
      gutter.appendChild(lab);
    }
    body.appendChild(gutter);

    const now = U.now();
    days.forEach((d, di) => {
      const col = U.el('div', { class: 'daycol' + (di === 0 ? ' first' : '') });
      for (let h = ds; h < DAY_END; h++) {
        const line = U.el('div', { class: 'hour-line' });
        line.style.top = ((h - ds) * hh) + 'px';
        col.appendChild(line);
        const half = U.el('div', { class: 'half-line' });
        half.style.top = ((h - ds) * hh + hh / 2) + 'px';
        col.appendChild(half);
        const slot = U.el('button', { class: 'slot-hit' });
        slot.style.top = ((h - ds) * hh) + 'px';
        slot.style.height = hh + 'px';
        slot.setAttribute('aria-label', `${U.fmtMonthDay(d)} ${U.pad(h)}:00 ${t('createHere')}`);
        slot.dataset.day = String(d.getTime());
        slot.dataset.hour = String(h);
        slot.addEventListener('click', () => openSlotSheet(d, h, h + 1));
        col.appendChild(slot);
      }

      const foldMin = dayStart() * 60;
      const events = S.eventsOnDay(d).filter((e) => !e.isAllDay)
        .filter((e) => S.state.dawnOpen || ((e.endDt - U.startOfDay(d)) / U.MS_MIN) > foldMin);
      const allocs = S.allocationsOnDay(d)
        .filter((a) => S.state.dawnOpen || ((a.endAt - U.startOfDay(d)) / U.MS_MIN) > foldMin);
      const evItems = events.map((e) => ({ s: e.startDt, e: e.endDt, raw: e }));
      const allocItems = allocs.map((x) => ({ s: x.startAt, e: x.endAt, raw: x }));
      computeOverlaps(evItems.concat(allocItems));

      evItems.forEach((it) => {
        col.appendChild(eventBlock(it.raw, d, it.pos || { col: 0, cols: 1 }, hh));
      });
      allocItems.forEach((it) => {
        col.appendChild(allocBlock(it.raw, d, it.pos || { col: 0, cols: 1 }, hh));
      });

      if (U.sameDay(d, now)) {
        const mins = now.getHours() * 60 + now.getMinutes();
        if (mins >= ds * 60 && mins <= DAY_END * 60) {
          const nl = U.el('div', { class: 'now-line' });
          nl.style.top = ((mins / 60 - ds) * hh) + 'px';
          col.appendChild(nl);
        }
      }
      body.appendChild(col);
    });

    scroll.appendChild(body);
    // Folded early hours: a strip that says what is hidden and opens them.
    const fold = U.el('button', { class: 'dawn-fold', 'data-testid': 'dawn-fold' });
    fold.innerHTML = S.state.dawnOpen
      ? ICON('chevronUp', 12) + `<span>${U.esc(t('collapseList'))}</span>`
      : ICON('chevronDown', 12) + `<span>${U.esc(t('dawnShow'))}</span><span class="tiny muted">${U.esc(t('dawnFold'))}</span>`;
    fold.addEventListener('click', () => { S.state.dawnOpen = !S.state.dawnOpen; App.render(); });
    wrap.appendChild(fold);
    wrap.appendChild(scroll);
    const jump = U.el('button', { class: 'back-now btn ghost sm', 'data-testid': 'back-to-now', text: t('backToNow') });
    jump.addEventListener('click', () => {
      const n = U.now();
      const mins = n.getHours() * 60 + n.getMinutes();
      const top = Math.max(0, ((mins / 60) - dayStart()) * hh - 80);
      if (scroll.scrollTo) scroll.scrollTo({ top, behavior: 'smooth' });
      else scroll.scrollTop = top;
    });
    wrap.appendChild(jump);
    content.appendChild(wrap);
    content.appendChild(legend('time'));

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (scroll.dataset.scrolled) return;
        scroll.dataset.scrolled = '1';
        const target = Math.max(0, (8 - ds) * hh - 8);
        if (scroll.scrollHeight > scroll.clientHeight + 4) {
          scroll.scrollTop = target;
          return;
        }
        const outer = scroll.closest('.page-scroll');
        if (outer) {
          const delta = scroll.getBoundingClientRect().top - outer.getBoundingClientRect().top + outer.scrollTop;
          outer.scrollTop = Math.max(0, delta + target - 8);
        }
      });
    });
  }

  function computeOverlaps(items) {
    const sorted = items.slice().sort((a, b) => a.s - b.s || a.e - b.e);
    const groups = [];
    let current = null;
    sorted.forEach((it) => {
      if (!current || it.s >= current.end) {
        current = { items: [it], end: it.e };
        groups.push(current);
      } else {
        current.items.push(it);
        current.end = Math.max(current.end, it.e);
      }
    });
    groups.forEach((g) => {
      // simple column packing
      const cols = [];
      g.items.forEach((it) => {
        let placed = false;
        for (let i = 0; i < cols.length; i++) {
          if (cols[i] <= it.s) { cols[i] = it.e; it._col = i; placed = true; break; }
        }
        if (!placed) { cols.push(it.e); it._col = cols.length - 1; }
      });
      // Position hangs off the item itself. A key of start-end collapsed two
      // events with identical intervals into one entry, so both drew in the same
      // column and the first became unreachable underneath the second.
      g.items.forEach((it) => { it.pos = { col: it._col || 0, cols: cols.length }; });
    });
    return items;
  }

  function blockPosition(start, end, day, hh, pos) {
    const day0 = U.startOfDay(day);
    const sMin = (start - day0) / U.MS_MIN;
    const eMin = (end - day0) / U.MS_MIN;
    // Folded dawn clips the visible start, not the data: a 03:00 block that
    // runs past 06:00 is drawn from 06:00, and its height starts there too.
    const visStart = Math.max(sMin, dayStart() * 60);
    const top = Math.max(0, (visStart / 60 - dayStart()) * hh);
    const height = Math.max(16, ((eMin - visStart) / 60) * hh - (U.isNarrow() ? 0 : 1));
    return { top, height, sMin, eMin };
  }

  function eventBlock(e, day, pos, hh) {
    const p = blockPosition(e.startDt, e.endDt, day, hh, pos);
    const node = U.el('button', { class: 'block', 'data-testid': 'event-block' });
    node.dataset.id = String(e.id);
    node.style.top = p.top + 'px';
    node.style.height = p.height + 'px';
    node.style.setProperty('--c', S.calendarColor(e.calendarId));
    if (pos.cols > 1) {
      const w = 100 / pos.cols;
      node.style.left = `calc(${pos.col * w}% + 1px)`;
      node.style.width = `calc(${w}% - 2px)`;
      node.style.right = 'auto';
    }
    node.innerHTML = `<div class="bt">${U.esc(e.summary)}</div><div class="bm">${U.esc(U.fmtTimeRange(e.startDt, e.endDt))}${e.location ? ' · ' + U.esc(e.location) : ''}</div>`;
    node.setAttribute('aria-label', `${e.summary} ${U.fmtTimeRange(e.startDt, e.endDt)}`);
    if (p.height < 34) node.classList.add('short');
    // On a phone a short block cannot carry a 48px resize handle without
    // covering its whole body; 改期… in the block menu is the precise path.
    if (U.isNarrow() && p.height < 96) node.classList.add('no-resize');
    const resize = U.el('div', { class: 'resize' });
    node.appendChild(resize);
    attachBlockDrag(node, resize, {
      kind: 'event', data: e, day, hh, top: p.top, height: p.height,
    });
    node.addEventListener('click', (ev) => {
      if (node.dataset.moved === '1') { node.dataset.moved = '0'; return; }
      openEvent(e);
    });
    node.addEventListener('contextmenu', (ev) => {
      ev.preventDefault();
      blockMenu(node, { kind: 'event', data: e });
    });
    attachTouchMenu(node, { kind: 'event', data: e });
    return node;
  }

  function allocBlock(a, day, pos, hh) {
    const todo = S.todoById(a.todoId);
    const p = blockPosition(a.startAt, a.endAt, day, hh, pos);
    const node = U.el('button', { class: 'block alloc', 'data-testid': 'alloc-block' });
    node.dataset.id = String(a.id);
    node.style.top = p.top + 'px';
    node.style.height = p.height + 'px';
    if (pos.cols > 1) {
      const w = 100 / pos.cols;
      node.style.left = `calc(${pos.col * w}% + 1px)`;
      node.style.width = `calc(${w}% - 2px)`;
      node.style.right = 'auto';
    }
    node.innerHTML = `<div class="bt">${U.esc(todo ? todo.summary : '')}</div><div class="bm">${U.esc(t('scheduled'))} · ${U.esc(U.fmtTimeRange(a.startAt, a.endAt))}</div>`;
    if (p.height < 34) node.classList.add('short');
    if (U.isNarrow() && p.height < 96) node.classList.add('no-resize');
    const resize = U.el('div', { class: 'resize' });
    node.appendChild(resize);
    attachBlockDrag(node, resize, { kind: 'alloc', data: a, day, hh, top: p.top, height: p.height });
    node.addEventListener('click', (ev) => {
      if (node.dataset.moved === '1') { node.dataset.moved = '0'; return; }
      if (todo) openTodo(todo, day);
    });
    node.addEventListener('contextmenu', (ev) => {
      ev.preventDefault();
      blockMenu(node, { kind: 'alloc', data: a, todo });
    });
    attachTouchMenu(node, { kind: 'alloc', data: a, todo });
    return node;
  }

  // A gesture that ends in a write re-renders the grid, so a guard stored on the
  // old node cannot swallow the click the browser synthesises afterwards. The
  // guard therefore lives at document level for the instant after a gesture.
  let suppressClick = null;
  function swallowTrailingClick(x, y) {
    suppressClick = { x: x || 0, y: y || 0, until: Date.now() + 400 };
  }
  document.addEventListener('click', (ev) => {
    if (!suppressClick || Date.now() >= suppressClick.until) { suppressClick = null; return; }
    const onBlock = ev.target instanceof Element && ev.target.closest('.block');
    // Only the click the browser synthesised at the gesture's own release point
    // is the gesture's; a different block clicked afterwards is a real click.
    const near = Math.abs((ev.clientX || 0) - suppressClick.x) <= 8
      && Math.abs((ev.clientY || 0) - suppressClick.y) <= 8;
    if (!onBlock || !near) return;
    suppressClick = null;
    ev.stopPropagation();
    ev.preventDefault();
  }, true);

  // D-16 sends short-block resizing to the block menu. On a real touch device
  // there is no right-click, and long-press does not synthesise contextmenu in
  // every shell, so the menu needs its own hold gesture.
  function attachTouchMenu(node, ctx) {
    let timer = null;
    let fired = false;
    let sx = 0;
    let sy = 0;
    const clear = () => { if (timer) { clearTimeout(timer); timer = null; } };
    node.addEventListener('pointerdown', (ev) => {
      if (ev.pointerType !== 'touch') return;
      fired = false;
      sx = ev.clientX;
      sy = ev.clientY;
      timer = setTimeout(() => { timer = null; fired = true; blockMenu(node, ctx); }, 480);
    });
    node.addEventListener('pointermove', (ev) => {
      if (timer && (Math.abs(ev.clientX - sx) > 8 || Math.abs(ev.clientY - sy) > 8)) clear();
    });
    node.addEventListener('pointerup', (ev) => {
      const held = fired;
      clear();
      if (held) swallowTrailingClick(ev.clientX, ev.clientY);
    });
    node.addEventListener('pointercancel', clear);
    node.addEventListener('click', (ev) => {
      if (!fired) return;
      fired = false;
      ev.stopPropagation();
      ev.preventDefault();
    }, true);
  }

  function blockMenu(anchorNode, ctx) {
    const items = [];
    if (ctx.kind === 'event') {
      const e = ctx.data;
      items.push({ icon: 'eye', text: t('view'), action: () => openEvent(e) });
      items.push({ icon: 'edit', text: t('edit'), action: () => window.EventOps.editEvent(e) });
      items.push({ icon: 'clockPlus', text: S.state.lang === 'zh' ? '改期…' : 'Reschedule…', action: () => rescheduleDialog(ctx) });
      items.push({ sep: true });
      items.push({ icon: 'trash', text: t('delete'), danger: true, action: () => deleteEventFlow(e) });
    } else {
      const a = ctx.data;
      items.push({ icon: 'eye', text: t('view'), action: () => ctx.todo && openTodo(ctx.todo, ctx.data.startAt) });
      items.push({ icon: 'clockPlus', text: S.state.lang === 'zh' ? '改期…' : 'Reschedule…', action: () => rescheduleDialog(ctx) });
      items.push({ icon: 'x', text: t('cancelAllocation'), danger: true, action: () => cancelAllocFlow(a) });
    }
    UI.menu(anchorNode, items);
  }

  function rescheduleDialog(ctx) {
    const isEvent = ctx.kind === 'event';
    const item = ctx.data;
    const start = isEvent ? item.startDt : item.startAt;
    const end = isEvent ? item.endDt : item.endAt;
    UI.modal({
      title: S.state.lang === 'zh' ? '改期' : 'Reschedule',
      body(body, close) {
        const f1 = U.el('div', { class: 'field' });
        f1.innerHTML = `<label>${U.esc(t('starts'))}</label>`;
        const i1 = U.el('input', { class: 'input', type: 'datetime-local', value: U.toInputDateTime(start) });
        f1.appendChild(i1);
        const f2 = U.el('div', { class: 'field' });
        f2.innerHTML = `<label>${U.esc(t('ends'))}</label>`;
        const i2 = U.el('input', { class: 'input', type: 'datetime-local', value: U.toInputDateTime(end) });
        f2.appendChild(i2);
        const err = U.el('div', { class: 'field-error' });
        body.appendChild(f1); body.appendChild(f2); body.appendChild(err);
        const apply = U.el('button', { class: 'btn primary lg', text: t('save'), style: 'margin-top:6px' });
        apply.addEventListener('click', () => {
          const s = U.fromInputDateTime(i1.value), e2 = U.fromInputDateTime(i2.value);
          if (!s || !e2 || e2 <= s) { err.textContent = t('timeInvalid'); return; }
          close(null);
          if (isEvent) moveEvent(item, s, e2, { exact: true }); else moveAlloc(item, s, e2);
        });
        body.appendChild(apply);
      },
    });
  }

  function attachBlockDrag(node, resize, ctx) {
    let mode = null, startX = 0, startY = 0, origTop = 0, origH = 0, moved = false, dayOffset = 0, lastDy = 0, lastDx = 0;
    const hh = ctx.hh;

    function down(e, m) {
      if (e.button !== undefined && e.button !== 0) return;
      // A refused drop leaves its click to be consumed; starting a new gesture
      // must clear that guard or the next real click would be swallowed.
      node.dataset.moved = '0';
      mode = m;
      startX = e.clientX; startY = e.clientY;
      origTop = parseFloat(node.style.top) || 0;
      origH = parseFloat(node.style.height) || 0;
      moved = false;
      dayOffset = 0;
      lastDy = 0; lastDx = 0;
      node.classList.add('dragging');
      node.setPointerCapture && node.setPointerCapture(e.pointerId);
      e.preventDefault();
    }
    node.addEventListener('pointerdown', (e) => down(e, 'move'));
    resize.addEventListener('pointerdown', (e) => { e.stopPropagation(); down(e, 'resize'); });

    node.addEventListener('pointermove', (e) => {
      if (!mode) return;
      // The hold menu owns the gesture once it is open; a finger that slides
      // afterwards must not drag the block behind it (D-24).
      if (document.querySelector('.menu')) return;
      const dy = e.clientY - startY;
      const dx = e.clientX - startX;
      lastDy = dy; lastDx = dx;
      // Exactly 8px is still a hold (D-24): a drag starts beyond it.
      if (!moved && Math.abs(dy) <= 8 && Math.abs(dx) <= 8) return;
      moved = true;
      if (mode === 'move') {
        node.style.top = origTop + dy + 'px';
        const colWidth = node.parentElement.getBoundingClientRect().width;
        const dOff = Math.round(dx / Math.max(1, colWidth));
        if (dOff !== dayOffset) { dayOffset = dOff; node.style.opacity = dOff ? '.55' : '1'; }
      } else {
        node.style.height = Math.max(12, origH + dy) + 'px';
      }
    });

    function restoreVisual() {
      node.style.top = ctx.top + 'px';
      node.style.height = ctx.height + 'px';
      node.dataset.moved = '0';
    }

    function up(e) {
      if (!mode) return;
      const wasMode = mode;
      const upX = e ? e.clientX : 0;
      const upY = e ? e.clientY : 0;
      if (e && e.type === 'pointercancel') {
        // The browser took the gesture for scrolling; the block never moved.
        mode = null;
        node.classList.remove('dragging');
        node.style.opacity = '1';
        restoreVisual(false);
        return;
      }
      mode = null;
      node.classList.remove('dragging');
      node.style.opacity = '1';
      if (!moved) {
        node.dataset.moved = '0';
        // The resize strip is a control, not a way into the record: a tap or a
        // jitter there must not navigate away from the calendar.
        if (wasMode === 'resize') swallowTrailingClick(upX, upY);
        return;
      }
      node.dataset.moved = '1';
      swallowTrailingClick(upX, upY);
      if (document.querySelector('.menu')) { restoreVisual(); return; }
      const top = parseFloat(node.style.top) || origTop;
      const height = parseFloat(node.style.height) || origH;
      // Move by the finger's movement, not by the rendered top: with dawn
      // folded the top is clipped, and a block that starts at 09:07 has no
      // quarter-hour top to snap from either. Both cases wrote a phantom
      // +15 minutes on a release that moved nothing.
      const movedMin = Math.round((lastDy / hh) * 60 / 15) * 15 + dayOffset * 24 * 60;
      const resizedMin = Math.round((lastDy / hh) * 60 / 15) * 15;
      const newTop = origTop + (movedMin / 60) * hh;
      const newH = Math.max(hh / 4, origH + (resizedMin / 60) * hh);
      node.style.top = newTop + 'px';
      node.style.height = newH + 'px';
      const start = ctx.kind === 'event' ? ctx.data.startDt : ctx.data.startAt;
      const end = ctx.kind === 'event' ? ctx.data.endDt : ctx.data.endAt;
      if (wasMode === 'resize') {
        const e2 = U.addMinutes(end, resizedMin);
        if (e2 <= start) return;
        if (resizedMin === 0) { restoreVisual(); return; }
        if (ctx.kind === 'event') moveEvent(ctx.data, start, e2, { silent: false, from: start, resized: true, onCancel: restoreVisual });
        else if (moveAlloc(ctx.data, start, e2, { resized: true, onCancel: restoreVisual }) === false) node.dataset.moved = '1';
      } else {
        if (movedMin === 0) { restoreVisual(); return; }
        const s = U.addMinutes(start, movedMin);
        const e2 = U.addMinutes(end, movedMin);
        if (ctx.kind === 'event') moveEvent(ctx.data, s, e2, { from: start, onCancel: restoreVisual });
        else if (moveAlloc(ctx.data, s, e2, { onCancel: restoreVisual }) === false) node.dataset.moved = '1';
      }
    }
    node.addEventListener('pointerup', up);
    node.addEventListener('pointercancel', up);
  }

  function moveEvent(e, start, end, opts) {
    const o = opts || {};
    const apply = (mode) => {
      const series = S.eventById(e.id);
      let undo = null;
      if (mode === 'this' && e.isOccurrence) {
        const anchor = e.occurrenceAnchor;
        series.exdates = (series.exdates || []).concat([anchor]);
        const copy = S.createEvent({
          summary: e.summary, calendarId: e.calendarId, startDt: start, endDt: end,
          isAllDay: e.isAllDay, description: e.description, location: e.location, tagIds: e.tagIds,
          reminderOffsets: (series.reminderOffsets || []).slice(),
        });
        S.emit('event:update');
        undo = () => {
          series.exdates = series.exdates.filter((x) => x.getTime() !== anchor.getTime());
          S.purgeEvent(copy.id);
        };
      } else if (mode === 'future' && e.rrule) {
        const prevUntil = series.rrule.until;
        const prevExdates = (series.exdates || []).slice();
        const anchorDay = U.startOfDay(e.startDt);
        // The dragged instance belongs to the new series, not the old one: the
        // old series must stop before it, and its anchor must be excluded, or
        // it is drawn twice (once where it was dragged from).
        series.exdates = prevExdates.concat([e.occurrenceAnchor || anchorDay]);
        series.rrule = Object.assign({}, series.rrule, { until: U.addDays(anchorDay, -1) });
        // The copy starts on the dragged instance's new day, so a weekday rule
        // has to follow it; otherwise the new series keeps the old weekday and
        // the moved instance never appears.
        const newStartDay = U.startOfDay(start);
        const movedRule = Object.assign({}, series.rrule, { until: null });
        if (movedRule.freq === 'WEEKLY' && movedRule.byday && movedRule.byday.length) {
          movedRule.byday = movedRule.byday.map((d, i) => (i === 0 ? newStartDay.getDay() : d));
        }
        const copy = S.createEvent({
          summary: e.summary, calendarId: e.calendarId, startDt: start, endDt: end,
          isAllDay: e.isAllDay, description: e.description, location: e.location, tagIds: e.tagIds,
          reminderOffsets: (series.reminderOffsets || []).slice(),
          rrule: movedRule,
        });
        undo = () => {
          series.rrule = Object.assign({}, series.rrule, { until: prevUntil });
          series.exdates = prevExdates;
          S.purgeEvent(copy.id);
        };
      } else {
        const prevStart = series.startDt, prevEnd = series.endDt;
        if (o.exact) {
          // 改期… shows and owns both fields: writing only start and deriving
          // the end from the old duration meant the dialog lied about the end,
          // and on a phone short block this is the only resize path (D-16).
          series.startDt = start;
          series.endDt = end;
        } else if (o.resized) {
          // Resize keeps the start and moves only the end.
          series.endDt = end;
        } else {
          const delta = start - (e.isOccurrence ? e.startDt : series.startDt);
          series.startDt = new Date(series.startDt.getTime() + delta);
          series.endDt = new Date(series.endDt.getTime() + delta);
        }
        series.updatedAt = U.now();
        S.emit('event:update');
        undo = () => {
          series.startDt = prevStart;
          series.endDt = prevEnd;
          S.emit('event:update');
        };
      }
      App.render();
      // A resize leaves the start alone, so a "moved to <start>" toast states a
      // time that did not change; report the new end instead.
      UI.toast(
        o.resized
          ? t('eventResizedToast', { t: U.fmtMonthDayTime(end) })
          : t('eventMovedToast', { t: U.fmtMonthDayTime(start) }),
        { undo: () => { if (undo) undo(); App.render(); } },
      );
    };
    if (e.isOccurrence && e.rrule && !o.silent) {
      window.EventOps.scopeSheet({
        options: [
          { mode: 'this', label: t('scopeThis'), desc: t('moveScopeThisDesc') },
          { mode: 'future', label: t('scopeFuture'), desc: t('moveScopeFutureDesc') },
          { mode: 'all', label: t('scopeAll'), desc: t('moveScopeAllDesc') },
        ],
        onPick: (mode) => apply(mode),
        onCancel: o.onCancel,
      });
    } else if (e.isOccurrence && !o.silent) {
      apply('this');
    } else {
      apply('all');
    }
  }

  function moveAlloc(a, start, end, opts) {
    const prev = { start: a.startAt, end: a.endAt };
    const o = opts || {};
    const moved = S.rescheduleAllocation(a.id, start, end);
    if (!moved) {
      // The drop was refused because the day cannot own this occurrence; put
      // the block back where it was instead of leaving a moved ghost on screen.
      if (o.onCancel) o.onCancel();
      UI.toast(t('occurrenceMoveBlocked'), { warn: true });
      return false;
    }
    App.render();
    if (!o.silent) {
      UI.toast(t(o.resized ? 'allocationResized' : 'allocationMoved', { t: U.fmtMonthDayTime(o.resized ? end : start) }), {
        undo: () => { S.rescheduleAllocation(a.id, prev.start, prev.end); App.render(); },
      });
    }
    return true;
  }

  function cancelAllocFlow(a) {
    UI.confirm({
      title: t('cancelAllocation'),
      message: t('cancelAllocationBody'),
      confirmText: t('cancelAllocation'),
      danger: true,
    }).then((ok) => {
      if (!ok) return;
      const prev = { start: a.startAt, end: a.endAt };
      S.cancelAllocation(a.id);
      App.render();
      UI.toast(t('allocationCancelled'), {
        undo: () => {
          const alloc = S.state.allocations.find((x) => x.id === a.id);
          if (alloc) { alloc.state = S.ALLOC.ACTIVE; alloc.startAt = prev.start; alloc.endAt = prev.end; S.emit('allocation:restore'); }
          App.render();
        },
      });
    });
  }

  const deleteEventFlow = (e) => window.EventOps.deleteEvent(e);

  // ---------- slot sheet ----------
  function openSlotSheet(day, h1, h2) {
    const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), h1, 0, 0, 0);
    const end = new Date(day.getFullYear(), day.getMonth(), day.getDate(), h2, 0, 0, 0);
    const rangeLabel = U.fmtMonthDay(day) + ' ' + U.fmtTimeRange(start, end);
    UI.sheet({
      title: t('slotTitle', { a: U.fmtTime(start), b: U.fmtTime(end) }),
      subtitle: U.fmtMonthDay(day) + ' · ' + U.fmtWeekdayLong(day),
      body(host, close) {
        const mk = (icon, title, sub, action, testid) => {
          const b = U.el('button', { class: 'slot-sheet-option' });
          if (testid) b.dataset.testid = testid;
          b.innerHTML = `<span class="ico">${ICON(icon, 17)}</span><span><span class="t">${U.esc(title)}</span><br><span class="s">${U.esc(sub)}</span></span>`;
          b.addEventListener('click', () => { close(null); action(); });
          return b;
        };
        host.appendChild(mk('calendarPlus', t('newEvent'), t('createEventDesc'), () => {
          App.openComposer('event', { startDt: start, endDt: end });
        }, 'slot-new-event'));
        const candidates = S.schedulableTodos().length;
        host.appendChild(mk('clockPlus', t('scheduleTodo'), t('slotCandidates', { n: candidates }), () => {
          pickSchedulable(start, end);
        }, 'slot-schedule-todo'));
        host.appendChild(mk('checkSquare', t('newAndSchedule'), t('planThisDayHint'), () => {
          App.openComposer('todo', { scheduleStart: start, scheduleEnd: end });
        }, 'slot-new-and-schedule'));
      },
    });
  }

  function pickSchedulable(start, end) {
    UI.sheet({
      title: t('scheduleTodo'),
      subtitle: U.fmtMonthDay(start) + ' ' + U.fmtTimeRange(start, end),
      body(host, close) {
        if (S.state.simulateSlotFailure) {
          S.state.simulateSlotFailure = false;
          const err = U.el('div', { class: 'field-hint', style: 'color:var(--red);padding:10px 0', text: t('slotFailed') });
          host.appendChild(err);
          const retry = U.el('button', { class: 'btn ghost sm', text: t('retry'), 'data-testid': 'slot-retry' });
          retry.addEventListener('click', () => { close(null); pickSchedulable(start, end); });
          host.appendChild(retry);
          return;
        }
        const search = U.el('input', { class: 'input', placeholder: S.state.lang === 'zh' ? '搜索待办' : 'Search to-dos', style: 'margin-bottom:8px' });
        host.appendChild(search);
        const list = U.el('div');
        host.appendChild(list);
        function draw(q) {
          list.innerHTML = '';
          const items = S.schedulableTodos().filter((x) => !q || x.summary.toLowerCase().includes(q.toLowerCase()));
          if (!items.length) {
            list.appendChild(UI.emptyState('checkSquare', t('schedulableEmpty'), t('schedulableEmptyHint'), [
              { label: t('createTodoHere'), primary: true, action: () => { close(null); App.openComposer('todo', { scheduleStart: start, scheduleEnd: end }); } },
            ]));
            return;
          }
          items.forEach((todo) => {
            const isRec = !!todo.recurrence;
            const b = U.el('button', { class: 'row' });
            b.dataset.testid = 'schedulable-todo';
            b.innerHTML = `<span class="row-leading">${ICON(isRec ? 'repeat' : 'checkSquare', 14)}</span><span class="row-main"><span class="row-title">${U.esc(todo.summary)}</span><span class="row-meta">${isRec ? U.esc(t('recurrence')) + ' · ' + U.esc(t('occurrence')) : ''}${todo.dueDate ? U.esc(t('deadlinePrefix', { d: U.fmtDeadline(todo.dueDate) })) : ''}</span></span><span class="row-tail">${ICON('chevronForward', 13)}</span>`;
            b.addEventListener('click', () => {
              if (isRec) {
                close(null);
                pickOccurrence(todo, start, end);
              } else {
                close(null);
                schedule(todo, start, end);
              }
            });
            list.appendChild(b);
          });
        }
        search.addEventListener('input', () => draw(search.value));
        draw('');
      },
    });
  }

  function pickOccurrence(todo, start, end) {
    const from = U.addDays(U.startOfDay(U.now()), -30);
    const to = U.addDays(U.startOfDay(U.now()), 90);
    const days = S.occurrencesInWindow(todo, from, to);
    UI.sheet({
      title: t('occurrence'),
      subtitle: S.state.lang === 'zh' ? '为哪一次实例安排这段时间？' : 'Which occurrence gets this time?',
      body(host, close) {
        const box = U.el('div', { class: 'occurrence-picker' });
        days.forEach((d) => {
          const id = S.occurrenceIdFor(todo, d);
          const done = S.isOccurrenceDone(todo, id);
          const b = U.el('button', { class: 'occ-row' });
          b.dataset.testid = 'occurrence-row';
          b.innerHTML = `<span class="date">${U.esc(U.fmtMonthDay(d))} · ${U.esc(U.fmtWeekdayLong(d))}</span><span class="state">${done ? U.esc(t('completed')) : ''}</span>`;
          if (done) b.disabled = true;
          b.addEventListener('click', () => { close(null); schedule(todo, start, end, id); });
          box.appendChild(b);
        });
        if (!days.length) box.appendChild(U.el('div', { class: 'empty-hint', text: t('nothingHere') }));
        host.appendChild(box);
      },
    });
  }

  function schedule(todo, start, end, occurrenceId) {
    const overlap = S.allocationsOnDay(start).concat([]).find((a) => a.startAt < end && a.endAt > start && !(todo.id === a.todoId && occurrenceId && occurrenceId === a.occurrenceId));
    S.createAllocation({ todoId: todo.id, startAt: start, endAt: end, occurrenceId });
    App.render();
    UI.toast(t('scheduleToast', { t: todo.summary }) + (overlap ? ' · ' + t('allocateConflict', { t: (S.todoById(overlap.todoId) || {}).summary || '' }) : ''), {
      warn: !!overlap,
      undo: () => {
        const created = S.state.allocations[S.state.allocations.length - 1];
        if (created) S.cancelAllocation(created.id);
        App.render();
      },
    });
  }

  // ---------- page ----------
  function renderCalendar() {
    const v = S.state.calendarView || 'week';
    const a = anchor();
    const actions = [];
    const prev = UI.iconButton('chevronLeft', S.state.lang === 'zh' ? '上一段' : 'Previous', () => shift(-1));
    const next = UI.iconButton('chevronRight', S.state.lang === 'zh' ? '下一段' : 'Next', () => shift(1));
    const todayBtn = U.el('button', { class: 'cal-today-btn', text: t('today') });
    todayBtn.addEventListener('click', () => setAnchor(U.startOfDay(U.now()), true));
    const seg = U.el('div', { class: 'segmented' });
    [['month', t('viewMonth')], ['week', t('viewWeek')], ['day', t('viewDay')]].forEach(([key, label]) => {
      const b = U.el('button', { class: key === v ? 'on' : '', text: label, 'aria-pressed': key === v ? 'true' : 'false' });
      b.dataset.testid = 'cal-view-' + key;
      b.addEventListener('click', () => setView(key));
      seg.appendChild(b);
    });
    if (!U.isNarrow()) {
      actions.push(prev, next, todayBtn, seg);
    }
    const create = U.el('button', { class: 'btn primary', 'data-testid': 'calendar-create' });
    create.innerHTML = ICON('plus', 14) + `<span class="label">${U.esc(t('newEvent'))}</span>`;
    create.setAttribute('aria-label', t('newEvent'));
    create.addEventListener('click', () => {
      // The calendar shows one browsed date. calendarFocusDay was a second
      // source of truth that paging never moved, so the form opened a week away.
      const base = S.state.browseDate || a;
      const day = U.startOfDay(base);
      const now = U.now();
      const isToday = U.sameDay(day, now);
      let start;
      if (isToday) {
        const nextHour = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
        // A block created inside the folded dawn looks like it vanished: the
        // calendar does not draw it until the fold is opened.
        if (U.sameDay(nextHour, day) && nextHour.getHours() < 8) {
          start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 8, 0, 0, 0);
        } else if (!U.sameDay(nextHour, day)) {
          start = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1, 8, 0, 0, 0);
        } else {
          start = nextHour;
        }
      } else {
        start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 9, 0, 0, 0);
      }
      App.openComposer('event', { startDt: start, endDt: U.addMinutes(start, 60) });
    });
    actions.push(create);

    const page = UI.page({
      title: titleFor(),
      subtitle: subFor(),
      actions,
      build(content) {
        if (U.isNarrow()) {
          const bar = U.el('div', { class: 'cal-head' });
          bar.appendChild(prev);
          bar.appendChild(next);
          bar.appendChild(todayBtn);
          bar.appendChild(U.el('span', { class: 'spacer' }));
          bar.appendChild(seg);
          content.appendChild(bar);
        }
        if (v === 'month') renderMonth(content);
        else if (v === 'week') {
          renderTimeGrid(content, weekDays(), { focus: a });
        } else {
          renderTimeGrid(content, [U.startOfDay(a)], { focus: a });
        }
      },
    });
    return page;
  }

  App.defineView('calendar', renderCalendar);
  window.__calendarHelpers = { openSlotSheet, schedule, setAnchor, setView };
})();
