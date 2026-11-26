/* DaySpark prototype v2 — real recurrence, calendar drag/resize and slot create. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
  const DAY_MIN = 720, AXIS_START = 480;
  const WD = ['日', '一', '二', '三', '四', '五', '六'];

  function dayOf(isoStr) { const [y, m, d] = String(isoStr).split('-').map(Number); return new Date(y, m - 1, d); }
  function iso(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }
  function snap(n) { return Math.round(n / 15) * 15; }
  function fmt(m) { m = Math.max(0, Math.min(1439, Math.round(m))); return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); }
  function mins(t) { if (!t) return 0; const a = String(t).split(':').map(Number); return a[0] * 60 + a[1]; }

  state.skipped = state.skipped || [];

  /* ---------------- recurrence ---------------- */
  function repeatMatch(anchor, day, repeat, item) {
    if (!repeat || !anchor || day < anchor) return false;
    if (item && item.repeatUntil && day > item.repeatUntil) return false;
    if (item && item.repeatCount) {
      const diff = Math.round((dayOf(day) - dayOf(anchor)) / 86400000);
      let n = 1;
      if (/^每天/.test(repeat)) n = diff + 1;
      else if (/^每 2 周/.test(repeat)) n = Math.floor(diff / 14) + 1;
      else if (/^每周/.test(repeat)) n = Math.floor(diff / 7) + 1;
      else if (/^每月/.test(repeat)) n = (dayOf(day).getFullYear() - dayOf(anchor).getFullYear()) * 12 + dayOf(day).getMonth() - dayOf(anchor).getMonth() + 1;
      else if (/^每年/.test(repeat)) n = dayOf(day).getFullYear() - dayOf(anchor).getFullYear() + 1;
      if (n > item.repeatCount) return false;
    }
    if (repeat === '每天') return true;
    if (repeat === '每月') return dayOf(day).getDate() === dayOf(anchor).getDate();
    if (repeat === '每年') return dayOf(day).getMonth() === dayOf(anchor).getMonth() && dayOf(day).getDate() === dayOf(anchor).getDate();
    const two = /^每 2 周/.test(repeat);
    if (/^每周|^每 2 周/.test(repeat)) {
      const diffDays = Math.round((dayOf(day) - dayOf(anchor)) / 86400000);
      if (two && Math.floor(diffDays / 7) % 2 !== 0) return false;
      const names = (repeat.match(/周[一二三四五六日]/g) || []).map((x) => '日一二三四五六'.indexOf(x[1]));
      if (names.length) return names.includes(dayOf(day).getDay());
      return dayOf(day).getDay() === dayOf(anchor).getDay();
    }
    return false;
  }
  function skipped(id, day) { return (state.skipped || []).includes(id + '@' + day); }

  const baseEventsOn = window.eventsOn;
  window.eventsOn = function (day) {
    const out = baseEventsOn(day).filter((e) => !skipped(e.id, day));
    if (!out.some((e) => e.date === day)) { /* keep order stable */ }
    EVENTS.filter((e) => !state.deletedEvents.includes(e.id) && !calHidden(e.cal) && e.repeat && e.date && e.date !== day && !state.skipped.includes(e.id + '@' + day))
      .forEach((e) => {
        if (out.some((x) => x.id === e.id && x.date === day)) return;
        if (repeatMatch(e.date, day, e.repeat, e)) out.push(Object.assign({}, e, { date: day, seriesDate: e.date, occurrence: true }));
      });
    return out;
  };

  const basePlansOn = window.plansOn;
  window.plansOn = function (day) {
    const out = basePlansOn(day);
    allTodos().forEach((t) => {
      if (!t.repeat || !t.plan || t.plan.date === day || isDone(t) || calHidden(t.cal)) return;
      if (skipped(t.id, day)) return;
      if (!repeatMatch(t.plan.date, day, t.repeat, t)) return;
      if (out.some((x) => x.todo.id === t.id)) return;
      out.push({ todo: Object.assign({}, t, { plan: Object.assign({}, t.plan, { date: day }) }), start: mins(t.plan.start), end: mins(t.plan.end) });
    });
    return out;
  };

  const baseDeadlinesOn = window.deadlinesOn;
  window.deadlinesOn = function (day) {
    const out = baseDeadlinesOn(day);
    allTodos().forEach((t) => {
      if (!t.repeat || !t.due || t.due === day || isDone(t) || calHidden(t.cal)) return;
      if (skipped(t.id, day)) return;
      if (!repeatMatch(t.due, day, t.repeat, t)) return;
      if (out.some((x) => x.id === t.id)) return;
      out.push(Object.assign({}, t, { due: day, occurrence: true }));
    });
    return out;
  };

  /* ---------------- drag / resize ---------------- */
  let drag = null;
  let suppressClick = 0;

  function columnInfo(col) {
    const r = col.getBoundingClientRect();
    return { rect: r, day: col.dataset.date };
  }
  function yToMin(col, y) {
    const { rect } = columnInfo(col);
    return AXIS_START + (y - rect.top) / rect.height * DAY_MIN;
  }
  function blockData(block, col) {
    const id = block.dataset.id;
    const isPlan = block.classList.contains('is-plan');
    if (isPlan) {
      const t = todoById(id); if (!t || !t.plan) return null;
      return { type: 'plan', item: t, start: mins(t.plan.start), end: mins(t.plan.end), day: t.plan.date, repeat: t.repeat };
    }
    const e = eventById(id); if (!e) return null;
    if (e.allDay || (e.startDate && e.endDate)) return null;
    return { type: 'event', item: e, start: mins(e.start), end: mins(e.end), day: e.date, repeat: e.repeat };
  }

  document.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    const block = e.target.closest('.day-col .cal-block');
    if (!block) return;
    const col = block.closest('.day-col');
    const data = blockData(block, col);
    if (!data) return;
    if (data.repeat) return; // recurring instances are not draggable
    const resize = !!e.target.closest('.proto-resize');
    drag = {
      block, col, data, resize, moved: false, startY: e.clientY, startX: e.clientX,
      start: data.start, end: data.end, day: data.day, pointerStart: yToMin(col, e.clientY),
      targetDay: data.day,
    };
    block.classList.add('is-dragging');
    // A handle exists on every block.
    e.preventDefault();
  });

  document.addEventListener('pointermove', (e) => {
    if (!drag) return;
    const dx = Math.abs(e.clientX - drag.startX), dy = Math.abs(e.clientY - drag.startY);
    if (!drag.moved && dx < 4 && dy < 4) return;
    drag.moved = true;
    const cur = yToMin(drag.col, e.clientY);
    let delta = snap(cur - drag.pointerStart);
    if (drag.resize) {
      const end = Math.max(drag.start + 15, Math.min(1439, drag.end + delta));
      drag.end = end;
      drag.block.style.height = Math.max(2.4, (end - drag.start) / DAY_MIN * 100) + '%';
    } else {
      const dur = drag.end - drag.start;
      let start = Math.max(0, Math.min(1439 - dur, drag.start + delta));
      drag.start = start;
      drag.end = start + dur;
      drag.block.style.top = Math.max(0, (start - AXIS_START) / DAY_MIN * 100) + '%';
      // Cross-day move: preview by switching the block into the target column.
      const el = document.elementFromPoint(e.clientX, e.clientY);
      const col2 = el && el.closest('.day-col');
      if (col2 && col2 !== drag.col) {
        drag.targetDay = col2.dataset.date;
        col2.appendChild(drag.block);
        drag.col = col2;
      }
    }
  });

  document.addEventListener('pointerup', () => {
    if (!drag) return;
    const d = drag; drag = null;
    d.block.classList.remove('is-dragging');
    if (!d.moved) return;
    suppressClick = Date.now() + 350;
    const start = d.start, end = d.end;
    if (start >= end) { render(); return; }
    if (d.data.type === 'plan') {
      d.data.item.plan = { date: d.targetDay, start: fmt(start), end: fmt(end) };
    } else {
      const ev = d.data.item;
      if (ev.startDate && ev.endDate) { render(); return; }
      const oldDay = ev.date;
      ev.date = d.targetDay;
      ev.start = fmt(start);
      ev.end = fmt(end);
    }
    render();
    toast((d.resize ? '已改时长 · ' : '已移动 · ') + fmt(start) + '–' + fmt(end));
  });

  document.addEventListener('click', (e) => {
    if (Date.now() < suppressClick && e.target.closest('.cal-block')) {
      e.preventDefault(); e.stopPropagation();
    }
  }, true);

  registerEnhancer((root) => {
    if (!state.screen.startsWith('cal-')) return;
    if (state.screen === 'cal-month') return;
    qa('.day-col .cal-block', root).forEach((b) => {
      if (q('.proto-resize', b)) return;
      const h = document.createElement('span');
      h.className = 'proto-resize';
      h.setAttribute('aria-hidden', 'true');
      b.appendChild(h);
    });
  });

  /* ---------------- empty slot create ---------------- */
  document.addEventListener('click', (e) => {
    if (Date.now() < suppressClick) return;
    const col = e.target.closest('.day-col');
    if (!col) return;
    if (e.target.closest('.cal-block, .dl-marker, .slot-ghost, .now-line-cal')) return;
    // Only a click on the column itself / its empty background creates.
    if (e.target !== col) return;
    e.preventDefault(); e.stopPropagation();
    const day = col.dataset.date;
    const m = snap(yToMin(col, e.clientY));
    const start = Math.max(0, Math.min(1439 - 60, m));
    openQuickEvent(day, fmt(start), fmt(Math.min(1439, start + 60)));
  }, true);

  function openQuickEvent(day, start, end) {
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-field"><label>标题</label><input class="proto-input" id="qe-title" placeholder="这段时间做什么？" autofocus></div>
      <div class="proto-inline-row"><div class="proto-field" style="flex:1"><label>开始</label><input type="time" class="proto-input" id="qe-start" value="${start}"></div><div class="proto-field" style="flex:1"><label>结束</label><input type="time" class="proto-input" id="qe-end" value="${end}"></div></div>
      <div class="proto-field"><label>日历</label><select class="proto-input" id="qe-cal">${calIds().map((id) => `<option value="${id}" ${id === (state.defaultCal || 'personal') ? 'selected' : ''}>${esc(calOf(id).name)}</option>`).join('')}</select></div>
      <div class="proto-note">${day} · 只写日程，不会顺带创建待办。</div>`;
    modal({
      title: '新建日程', body,
      actions: [
        { label: '取消' },
        { label: '创建', primary: true, onClick: () => {
          const title = (q('#qe-title', body).value || '').trim();
          if (!title) { toast('先写标题'); q('#qe-title', body).focus(); return true; }
          const s = q('#qe-start', body).value || start, e2 = q('#qe-end', body).value || end;
          if (e2 <= s) { toast('结束必须晚于开始'); return true; }
          EVENTS.push({ id: 'local-event-' + (++state.localNo), title, cal: q('#qe-cal', body).value, date: day, start: s, end: e2, remind: '15 分钟前' });
          render(); toast('已创建日程 · ' + s + '–' + e2);
        } },
      ],
    });
  }

  /* ---------------- all-day overflow and month +N ---------------- */
  registerAction('allday-overflow', (el) => {
    const day = el.dataset.date || state.selectedDate || TODAY;
    const items = allDayOn(day);
    modal({
      title: '全天事项 · ' + day,
      body: `<div class="proto-list">${items.map((e) => `<button type="button" class="proto-list-row" data-id="${e.id}"><span class="cal-dot" style="background:${calOf(e.cal).color}"></span><span class="grow">${esc(e.title)}<small>${calOf(e.cal).name}${e.startDate ? ' · ' + e.startDate + '–' + e.endDate : ''}</small></span></button>`).join('') || '<div class="proto-note">这一天没有全天事项。</div>'}</div>`,
      actions: [{ label: '关闭' }],
    });
  });

  /* ---------------- calendar filter: select all / none ---------------- */
  registerEnhancer((root) => {
    if (state.screen !== 'cal-week' && state.screen !== 'cal-month' && state.screen !== 'cal-day') return;
    if (state.variant !== 'calendars' && state.variant !== 'calendars-empty') return;
    const panel = q('.cal-filter-pop', root) || q('.m-filter-sheet', root);
    if (!panel || q('[data-proto-action="cal-none"]', panel)) return;
    const actions = q('.filter-actions', panel);
    if (!actions) return;
    const b = document.createElement('button');
    b.type = 'button'; b.textContent = '全不选';
    b.dataset.protoAction = 'cal-none';
    actions.insertBefore(b, actions.firstChild);
  });
  registerAction('cal-none', () => { state.hiddenCals = calIds(); render(); toast('已隐藏全部日历'); });

  // Month "+N" opens the full day list instead of silently navigating.
  registerEnhancer((root) => {
    if (state.screen !== 'cal-month') return;
    qa('.mcell .mmore', root).forEach((m) => {
      m.dataset.protoAction = 'month-more';
      m.dataset.date = m.closest('.mcell').dataset.date;
      m.style.pointerEvents = 'auto';
      m.style.cursor = 'pointer';
    });
  });
  registerAction('month-more', (el) => {
    const day = el.dataset.date;
    const items = monthItems(day);
    const body = document.createElement('div');
    body.className = 'proto-list';
    items.forEach((it) => {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'proto-list-row';
      b.innerHTML = `<span class="cal-dot" style="background:${calOf(it.cal).color}"></span><span class="grow">${esc(it.title)}<small>${it.type === 'event' ? '日程' : it.type === 'plan' ? '计划' : '截止'}${it.time ? ' · ' + it.time : ''}</small></span>`;
      b.addEventListener('click', () => {
        b.closest('.proto-modal-scrim').remove();
        if (it.type === 'event') P.openEvent(it.id); else P.openTodo(it.id);
      });
      body.appendChild(b);
    });
    modal({ title: day + ' · ' + items.length + ' 项', body, actions: [{ label: '关闭', primary: true }] });
  });
})();
