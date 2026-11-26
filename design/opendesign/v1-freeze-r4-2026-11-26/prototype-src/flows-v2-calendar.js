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
  // "每周一、三、五" only prefixes 周 once; read the day characters that follow.
  function repeatDays(repeat) {
    const m = /^(每\s?2\s?周|每周)/.exec(repeat || '');
    if (!m) return [];
    return repeat.slice(m[0].length).split(/[、,，]/)
      .map((t) => t.trim().slice(-1))
      .map((ch) => '日一二三四五六'.indexOf(ch))
      .filter((n) => n >= 0);
  }
  // A repeat rule matches a day on its own terms (no count/until).
  function pureMatch(anchor, day, repeat) {
    const a = dayOf(anchor), d = dayOf(day);
    if (!(d >= a)) return false;
    if (repeat === '每天') return true;
    if (repeat === '每月') return d.getDate() === a.getDate();
    if (repeat === '每年') return d.getMonth() === a.getMonth() && d.getDate() === a.getDate();
    const two = /^每 2 周/.test(repeat);
    if (/^每周/.test(repeat) || two) {
      const diff = Math.round((d - a) / 86400000);
      if (two && Math.floor(diff / 7) % 2 !== 0) return false;
      const names = repeatDays(repeat);
      if (names.length) return names.includes(d.getDay());
      return d.getDay() === a.getDay();
    }
    return false;
  }
  // How many times this rule has fired from the anchor through `day` (1-based).
  // Counting real occurrences, not elapsed weeks: 每周一三五 10 次 means 10 dates.
  function occurrenceIndex(anchor, day, repeat, cap) {
    if (!pureMatch(anchor, day, repeat)) return 0;
    const a = dayOf(anchor), d = dayOf(day);
    if (/^每天/.test(repeat)) return Math.round((d - a) / 86400000) + 1;
    if (/^每月/.test(repeat)) return (d.getFullYear() - a.getFullYear()) * 12 + d.getMonth() - a.getMonth() + 1;
    if (/^每年/.test(repeat)) return d.getFullYear() - a.getFullYear() + 1;
    const two = /^每 2 周/.test(repeat);
    const names = repeatDays(repeat);
    let n = 0;
    const x = new Date(a.getFullYear(), a.getMonth(), a.getDate());
    while (x <= d) {
      const dayOk = names.length ? names.includes(x.getDay()) : x.getDay() === a.getDay();
      const weekOk = !two || Math.floor(Math.round((x - a) / 86400000) / 7) % 2 === 0;
      if (dayOk && weekOk) {
        n++;
        if (cap && n > cap) return n;
      }
      x.setDate(x.getDate() + 1);
    }
    return n;
  }
  function repeatMatch(anchor, day, repeat, item) {
    if (!repeat || !anchor || day < anchor) return false;
    if (item && item.repeatUntil && day > item.repeatUntil) return false;
    if (!pureMatch(anchor, day, repeat)) return false;
    if (item && item.repeatCount) {
      if (occurrenceIndex(anchor, day, repeat, item.repeatCount) > item.repeatCount) return false;
    }
    return true;
  }
  function skipped(id, day) { return (state.skipped || []).includes(id + '@' + day); }
  P.repeatMath = { pureMatch, occurrenceIndex, repeatMatch };
  P.occurrenceDate = (id, day) => (state.occurId === id && state.occurDate ? state.occurDate : day);

  // Legacy series projections (a t.plan adopted as an allocation) carry the
  // series anchor as their occurrenceDate, which is NOT the visible instance.
  // Priority: legacy -> the visible day; explicit occurrenceDate -> that
  // instance; repeating but nameless -> no guess (caller clears the binding so
  // completion/plan entry asks via DS3.requireOccurrence); otherwise the
  // allocation date.
  function boundOccurrence(t, alloc, visibleDay) {
    if (!alloc) return null;
    if (alloc.legacy) return visibleDay || alloc.date || null;
    if (alloc.occurrenceDate) return alloc.occurrenceDate;
    if (t && t.repeat) return null;
    return alloc.date || visibleDay || null;
  }
  function visibleDayOf(block) {
    const col = block.closest('.day-col');
    return (col && col.dataset.date) || state.selectedDate || TODAY;
  }

  // Remember which visible instance opened an event/plan block, so "仅这一次"
  // and "这一次及以后" use the instance the user actually clicked. For a plan
  // block the visible column is not trustworthy for explicit allocations: an
  // allocation may have been scheduled onto another day than its occurrence.
  document.addEventListener('click', (e) => {
    const b = e.target.closest('.cal-block, .m-block, .allday-chip');
    if (!b || !b.dataset.id) return;
    const visibleDay = visibleDayOf(b);
    if (b.classList.contains('is-plan')) {
      const allocId = b.dataset.alloc || b.getAttribute('data-alloc') || '';
      const t = todoById(b.dataset.id);
      const alloc = allocId && t && window.DS3 ? window.DS3.planById(t, allocId) : null;
      if (alloc) {
        const bound = boundOccurrence(t, alloc, visibleDay);
        if (bound) { state.occurId = b.dataset.id; state.occurDate = bound; }
        else { state.occurId = null; state.occurDate = null; }
        return;
      }
    }
    state.occurDate = visibleDay;
    state.occurId = b.dataset.id;
  }, true);

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

  // NOTE: plansOn is owned solely by flows-v3-model.js (it emits one entry per
  // allocation, with allocId). The old wrapper that used to live here was dead:
  // this file executes before flows-v3-model.js, which then replaces
  // window.plansOn outright, so the wrapper never ran. Do not reintroduce a
  // second plansOn — two projections would stack old logic.

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
  // Resolve the concrete allocation behind a plan block. A block carries
  // data-alloc (allocation id); that is the only safe identity, because the
  // todo id alone cannot tell which of several segments was grabbed. Never
  // read t.plan here as a writable source — it is only a derived projection.
  function blockData(block, col) {
    const id = block.dataset.id;
    const isPlan = block.classList.contains('is-plan');
    if (isPlan) {
      const t = todoById(id); if (!t) return null;
      const allocId = block.dataset.alloc || block.getAttribute('data-alloc') || '';
      let alloc = allocId && window.DS3 ? window.DS3.planById(t, allocId) : null;
      if (!alloc) {
        // Last-resort fallback: the block lost its data-alloc (stale markup or
        // an old cached render). Pick the active segment projected on this
        // column, otherwise the first active one. We still only operate on a
        // real allocation id afterwards; t.plan is never written.
        const list = window.DS3 ? window.DS3.activeAllocations(t) : [];
        alloc = list.find((p) => p && p.date === (col && col.dataset.date)) || list[0] || null;
      }
      if (!alloc) return null;
      return {
        type: 'plan', item: t, alloc, allocId: alloc.id,
        start: mins(alloc.start), end: mins(alloc.end),
        day: alloc.date, occurrenceDate: alloc.occurrenceDate, repeat: t.repeat,
      };
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
    if (data.type === 'plan') {
      // A repeating todo may be dragged only when the block names an explicit
      // allocation, i.e. one occurrence. A legacy single-plan projection is
      // shared by every instance; a real drag attempt is refused in
      // pointermove (a plain click still opens the detail normally).
      if (!data.allocId) return;
    } else if (data.repeat) {
      return; // recurring event instances are not draggable
    }
    const resize = !!e.target.closest('.proto-resize');
    drag = {
      block, col, data, resize, moved: false, startY: e.clientY, startX: e.clientX,
      legacyBlocked: data.type === 'plan' && data.repeat && data.alloc.legacy,
      // Fixed origin: every candidate is derived from these, never from a
      // mutated drag.start, so repeated drags cannot accumulate offset.
      originStart: data.start, originEnd: data.end, originDay: data.day,
      pointerStart: yToMin(col, e.clientY),
      start: data.start, end: data.end,
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
    if (drag.legacyBlocked) {
      // Refuse to reschedule a shared legacy series plan. Explain instead of
      // silently moving every instance. The render from toast happens here,
      // after a real drag began, so it cannot break a plain click.
      const blockedBlock = drag.block;
      drag = null;
      blockedBlock.classList.remove('is-dragging');
      toast('旧系列计划需先确认实例再改期');
      return;
    }
    drag.moved = true;
    const cur = yToMin(drag.col, e.clientY);
    const delta = snap(cur - drag.pointerStart);
    if (drag.resize) {
      const end = Math.max(drag.originStart + 15, Math.min(1439, drag.originEnd + delta));
      drag.start = drag.originStart;
      drag.end = end;
      drag.block.style.height = Math.max(2.4, (end - drag.originStart) / DAY_MIN * 100) + '%';
    } else {
      const dur = drag.originEnd - drag.originStart;
      const start = Math.max(0, Math.min(1439 - dur, drag.originStart + delta));
      drag.start = start;
      drag.end = start + dur;
      drag.block.style.top = Math.max(0, (start - AXIS_START) / DAY_MIN * 100) + '%';
      // Cross-day move: preview by switching the block into the target column.
      // Only the scheduled date changes; occurrenceDate is never touched.
      const el = document.elementFromPoint(e.clientX, e.clientY);
      const col2 = el && el.closest('.day-col');
      if (col2 && col2 !== drag.col) {
        drag.targetDay = col2.dataset.date || drag.targetDay;
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
      const DS3 = window.DS3;
      const t = d.data.item, alloc = d.data.alloc;
      if (!DS3 || !alloc || !alloc.id) { render(); return; }
      // Resize writes only the end; a move writes the target date plus a new
      // start/end. updateAllocation touches exactly this allocation; the
      // projection is then recomputed by DS3.syncProjection.
      const spec = d.resize
        ? { end: fmt(end) }
        : { date: d.targetDay || d.originDay, start: fmt(start), end: fmt(end) };
      if (!DS3.updateAllocation(t, alloc.id, spec)) {
        toast('这一段计划已经不在了 · 刷新后重试');
        render();
        return;
      }
      DS3.syncProjection(t);
      render();
      toast((d.resize ? '已改时长 · ' : '已移动 · ') + fmt(start) + '–' + fmt(end));
      return;
    }
    const ev = d.data.item;
    if (ev.startDate && ev.endDate) { render(); return; }
    ev.date = d.targetDay;
    ev.start = fmt(start);
    ev.end = fmt(end);
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
      <div class="proto-note">${day} · 只写日程，不会顺带创建待办。结束早于开始表示次日结束（跨午夜）。</div>`;
    modal({
      title: '新建日程', body,
      actions: [
        { label: '取消' },
        { label: '创建', primary: true, onClick: () => {
          const title = (q('#qe-title', body).value || '').trim();
          if (!title) { toast('先写标题'); q('#qe-title', body).focus(); return true; }
          const s = q('#qe-start', body).value || start, e2 = q('#qe-end', body).value || end;
          if (e2 === s) { toast('开始和结束不能相同'); return true; }
          // end < start means the event ends on the next day. It is stored as a
          // two-day span (startDate/endDate, no single date) so the calendar
          // projection shows it on both days without drawing a negative block.
          const ev = { id: 'local-event-' + (++state.localNo), title, cal: q('#qe-cal', body).value, start: s, end: e2, remind: '15 分钟前' };
          if (e2 < s) {
            ev.startDate = day;
            ev.endDate = addDays(day, 1);
            ev.crossMidnight = true;
            ev.allDay = false;
          } else {
            ev.date = day;
          }
          EVENTS.push(ev);
          render();
          toast(ev.crossMidnight ? '已创建跨午夜日程 · ' + s + '–次日 ' + e2 : '已创建日程 · ' + s + '–' + e2);
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
        if (it.type === 'plan') {
          // Bind the occurrence explicitly when the month item carries an
          // allocation id. Legacy series projections bind to the month cell
          // (the visible instance), not to the series anchor. Without a usable
          // identity, clear the binding so completion asks which instance.
          const t = todoById(it.id);
          const alloc = it.allocId && t && window.DS3 ? window.DS3.planById(t, it.allocId) : null;
          const bound = alloc ? boundOccurrence(t, alloc, day) : null;
          if (bound) {
            state.occurId = it.id;
            state.occurDate = bound;
          } else {
            state.occurId = null;
            state.occurDate = null;
          }
        }
        if (it.type === 'event') P.openEvent(it.id); else P.openTodo(it.id, { keepOccurrence: !!it.allocId });
      });
      body.appendChild(b);
    });
    modal({ title: day + ' · ' + items.length + ' 项', body, actions: [{ label: '关闭', primary: true }] });
  });
})();
