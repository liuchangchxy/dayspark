/* Detail: read-only surface for a Todo or Event. Edit is an explicit action.
   Todo detail also carries occurrence state, allocations and subtasks. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function iconFact(icon, key, valueHtml, actNode, cls) {
    const f = U.el('div', { class: 'fact' + (cls ? ' ' + cls : '') });
    f.innerHTML = `<span class="ico">${ICON(icon, 15)}</span><span class="body"><span class="k">${U.esc(key)}</span><span class="v">${valueHtml}</span></span>`;
    if (actNode) {
      const act = U.el('span', { class: 'act' });
      act.appendChild(actNode);
      f.appendChild(act);
    }
    return f;
  }

  function editableValue(text, onEdit, opts) {
    const v = U.el('span', { class: 'v' + (opts && opts.muted ? ' muted' : ''), text, role: 'button', tabindex: '0', title: t('editInline') });
    v.style.cursor = 'pointer';
    v.addEventListener('click', onEdit);
    v.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onEdit(); } });
    return v;
  }

  function todoDetail(todo) {
    const root = U.el('div', { class: 'detail', 'data-testid': 'todo-detail' });
    const narrow = U.isNarrow();
    const head = U.el('div', { class: 'detail-head' });
    if (narrow) head.appendChild(UI.iconButton('chevronLeft', t('back'), () => App.back()));
    head.appendChild(U.el('span', { class: 'spacer' }));
    const moreBtn = UI.iconButton('sliders', t('more'), () => openMenu(moreBtn, todo));
    head.appendChild(moreBtn);
    if (narrow) head.appendChild(UI.iconButton('x', t('close'), () => App.back()));
    root.appendChild(head);

    const scroll = U.el('div', { class: 'detail-scroll' });
    root.appendChild(scroll);

    const title = U.el('h1', { class: 'detail-title' + (S.isDone(todo) ? ' done' : ''), text: todo.summary });
    scroll.appendChild(title);

    const status = U.el('div', { class: 'detail-status' });
    const done = S.isDone(todo);
    const doneBtn = U.el('button', { class: 'btn ' + (done ? 'ghost' : 'primary'), 'data-testid': 'detail-complete' });
    doneBtn.innerHTML = ICON('check', 14) + `<span>${U.esc(done ? t('markIncomplete') : t('markComplete'))}</span>`;
    doneBtn.addEventListener('click', () => {
      const wasDone = S.isDone(todo);
      S.completeTodo(todo.id);
      App.render();
      UI.toast(wasDone ? t('uncompletedToast', { t: todo.summary }) : t('completedToast', { t: todo.summary }), {
        undo: () => { S.completeTodo(todo.id); App.render(); },
      });
    });
    status.appendChild(doneBtn);
    if (todo.recurrence) status.appendChild(U.el('span', { class: 'chip violet', html: ICON('repeat', 10) + `<span>${U.esc(t('recurrence'))}</span>` }));
    if (todo.completedAt && done) status.appendChild(U.el('span', { class: 'tiny muted', text: t('completed') + ' · ' + U.fmtMonthDayTime(todo.completedAt) }));
    scroll.appendChild(status);

    const facts = U.el('div', { class: 'detail-facts' });
    scroll.appendChild(facts);

    // deadline
    const dueAct = UI.iconButton('edit', t('change'), () => editDeadline(todo), { sm: true, size: 13 });
    facts.appendChild(iconFact(
      'flag',
      t('deadline'),
      todo.dueDate ? U.esc(U.fmtDeadline(todo.dueDate)) : `<span class="muted">${U.esc(t('noDeadline'))}</span>`,
      dueAct,
      'amber',
    ));

    // scheduled allocations
    const allocs = S.allocationsForTodo(todo.id);
    const liveAllocs = allocs.filter(S.isAllocationLive);
    const allocValue = liveAllocs.length
      ? liveAllocs.map((a) => `<div>${U.esc(U.fmtMonthDayTime(a.startAt))} – ${U.esc(U.fmtTime(a.endAt))}</div>`).join('')
      : `<span class="muted">${U.esc(t('noSchedule'))}</span>`;
    const addAlloc = UI.iconButton('clockPlus', t('allocateNow'), () => scheduleSheet(todo), { sm: true, size: 13 });
    facts.appendChild(iconFact('clock', t('scheduleExec'), allocValue, addAlloc, 'violet'));

    // repeat
    if (todo.recurrence) {
      facts.appendChild(iconFact('repeat', t('seriesRule'), U.esc(UI.ruleSummary(todo.recurrence)) + `<span class="tiny muted"> · ${U.esc(todo.recurrence.timeZone)}</span>`,
        UI.iconButton('edit', t('edit'), () => App.openComposer('todo', { mode: 'edit', id: todo.id, focus: 'repeat' }), { sm: true, size: 13 })));
    }

    // priority
    const prioLabel = { 9: t('high'), 5: t('medium'), 1: t('low') }[todo.priority] || t('noPriority');
    facts.appendChild(iconFact('flag', t('priority'), U.esc(prioLabel),
      UI.iconButton('edit', t('change'), () => prioritySheet(todo), { sm: true, size: 13 })));

    // tags
    const tagsHtml = todo.tagIds.length
      ? todo.tagIds.map((id) => {
        const tag = S.tagById(id);
        return tag ? `<span class="chip" style="background:color-mix(in srgb, ${tag.color} 12%, transparent);color:${tag.color}"><span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}</span>` : '';
      }).join('')
      : `<span class="muted">${U.esc(t('none'))}</span>`;
    facts.appendChild(iconFact('tag', t('tags'), tagsHtml,
      UI.iconButton('edit', t('change'), () => tagSheet(todo), { sm: true, size: 13 })));

    // calendar
    const cal = S.calendarById(todo.calendarId);
    facts.appendChild(iconFact('folder', t('calendar'), `<span class="chip"><span class="dot" style="background:${cal ? cal.color : 'var(--accent)'}"></span>${U.esc(cal ? cal.name : '')}</span>`));

    // reminders
    if (todo.reminderOffsets.length) {
      facts.appendChild(iconFact('bell', t('reminder'), todo.reminderOffsets.map((m) => U.esc(reminderLabel(m))).join(' · ')));
    }

    // parent
    if (todo.parentId) {
      const parent = S.todoById(todo.parentId);
      if (parent) {
        facts.appendChild(iconFact('list', t('parentTodo'), `<a href="#" data-parent>${U.esc(parent.summary)}</a>`));
        const link = facts.querySelector('[data-parent]');
        if (link) link.addEventListener('click', (e) => { e.preventDefault(); S.navigate('detail', { type: 'todo', id: parent.id }); });
      }
    }

    // occurrences
    if (todo.recurrence) {
      const sec = U.el('div', { class: 'detail-section' });
      sec.appendChild(U.el('h3', { text: t('occurrenceList') }));
      sec.appendChild(U.el('div', { class: 'field-hint', text: t('occurrenceListHint') }));
      const from = U.addDays(U.startOfDay(U.now()), -30);
      const to = U.addDays(U.startOfDay(U.now()), 30);
      const days = S.occurrencesInWindow(todo, from, to);
      const box = U.el('div', { class: 'occurrence-picker' });
      days.forEach((d) => {
        const id = S.occurrenceIdFor(todo, d);
        const isDone = S.isOccurrenceDone(todo, id);
        const row = U.el('div', { class: 'occ-row' });
        row.dataset.testid = 'detail-occurrence';
        row.appendChild(UI.checkbox(isDone, () => {
          S.completeTodo(todo.id, { occurrenceId: id });
          App.render();
        }, todo.summary));
        row.appendChild(U.el('span', { class: 'date', text: U.fmtMonthDay(d) + ' · ' + U.fmtWeekdayLong(d) }));
        const alloc = S.state.allocations.find((a) => a.todoId === todo.id && a.occurrenceId === id && a.state === S.ALLOC.ACTIVE);
        if (alloc) row.appendChild(U.el('span', { class: 'state', text: U.fmtTimeRange(alloc.startAt, alloc.endAt) }));
        if (isDone) row.appendChild(U.el('span', { class: 'chip green', text: t('completed') }));
        if (U.sameDay(d, U.now())) row.appendChild(U.el('span', { class: 'chip accent', text: t('today') }));
        box.appendChild(row);
      });
      if (!days.length) box.appendChild(U.el('div', { class: 'field-hint', text: t('nothingHere') }));
      sec.appendChild(box);
      scroll.appendChild(sec);
    }

    // subtasks
    if (!todo.parentId) {
      const subs = S.subtasksOf(todo.id);
      const sec = U.el('div', { class: 'detail-section' });
      const h = U.el('h3', { text: t('subtasks') + (subs.length ? ' · ' + subs.length : '') });
      sec.appendChild(h);
      if (subs.length) {
        subs.forEach((sub) => {
          const row = U.el('div', { class: 'subtask' });
          row.appendChild(UI.checkbox(S.isDone(sub), () => { S.completeTodo(sub.id); App.render(); }));
          const title = U.el('button', { class: 'title', text: sub.summary, style: 'text-align:left' });
          if (S.isDone(sub)) title.style.textDecoration = 'line-through';
          title.addEventListener('click', () => S.navigate('detail', { type: 'todo', id: sub.id }));
          row.appendChild(title);
          if (sub.dueDate) row.appendChild(U.el('span', { class: 'tiny muted', text: U.fmtDeadline(sub.dueDate) }));
          sec.appendChild(row);
        });
      } else {
        sec.appendChild(U.el('div', { class: 'field-hint', text: t('noSubtasks') }));
      }
      const addSub = U.el('button', { class: 'btn ghost sm', style: 'margin-top:8px' });
      addSub.innerHTML = ICON('plus', 12) + `<span>${U.esc(t('addSubtask'))}</span>`;
      addSub.addEventListener('click', () => App.openComposer('todo', { parentId: todo.id }));
      sec.appendChild(addSub);
      scroll.appendChild(sec);
    }

    // allocation history
    const history = allocs.filter((a) => !S.isAllocationLive(a));
    if (history.length) {
      const sec = U.el('div', { class: 'detail-section' });
      sec.appendChild(U.el('h3', { text: S.state.lang === 'zh' ? '历史安排' : 'Past schedules' }));
      history.forEach((a) => {
        const line = U.el('div', { class: 'alloc-line' });
        const stateLabel = a.state === S.ALLOC.CANCELLED ? t('cancelled') : (S.state.lang === 'zh' ? '完成时失效' : 'Invalidated');
        line.innerHTML = `<span class="when">${U.esc(U.fmtMonthDayTime(a.startAt))} – ${U.esc(U.fmtTime(a.endAt))}</span><span class="chip outline">${U.esc(stateLabel)}</span>`;
        sec.appendChild(line);
      });
      scroll.appendChild(sec);
    }

    // notes
    const notesSec = U.el('div', { class: 'detail-section' });
    notesSec.appendChild(U.el('h3', { text: t('notes') }));
    const notes = U.el('div', { class: 'detail-note' + (todo.description ? '' : ' muted'), text: todo.description || t('noDescription') });
    notes.style.cursor = 'pointer';
    notes.title = t('editInline');
    notes.addEventListener('click', () => notesEditor(todo));
    notesSec.appendChild(notes);
    scroll.appendChild(notesSec);

    // meta
    const metaSec = U.el('div', { class: 'detail-section' });
    metaSec.innerHTML = `<div class="kv"><span class="k">${U.esc(t('createdAt'))}</span><span class="v">${U.esc(U.fmtMonthDayTime(todo.createdAt))}</span></div>` +
      `<div class="kv"><span class="k">${U.esc(t('updatedAt'))}</span><span class="v">${U.esc(U.fmtMonthDayTime(todo.updatedAt))}</span></div>`;
    scroll.appendChild(metaSec);

    const actions = U.el('div', { class: 'detail-actions' });
    const editBtn = U.el('button', { class: 'btn ghost', 'data-testid': 'detail-edit' });
    editBtn.innerHTML = ICON('edit', 13) + `<span>${U.esc(t('edit'))}</span>`;
    editBtn.addEventListener('click', () => App.openComposer('todo', { mode: 'edit', id: todo.id }));
    actions.appendChild(editBtn);
    actions.appendChild(U.el('span', { class: 'spacer' }));
    const del = U.el('button', { class: 'btn danger-ghost', text: t('moveToTrash') });
    del.addEventListener('click', () => deleteFlow(todo));
    actions.appendChild(del);
    root.appendChild(actions);
    return root;
  }

  function openMenu(anchor, todo) {
    const items = [
      { icon: 'edit', text: t('edit'), action: () => App.openComposer('todo', { mode: 'edit', id: todo.id }) },
      { icon: 'clockPlus', text: t('allocateNow'), action: () => scheduleSheet(todo) },
      { icon: 'list', text: t('addSubtask'), action: () => App.openComposer('todo', { parentId: todo.id }) },
      { icon: 'copy', text: S.state.lang === 'zh' ? '复制标题' : 'Copy title', action: () => { navigator.clipboard && navigator.clipboard.writeText(todo.summary); UI.toast(S.state.lang === 'zh' ? '已复制' : 'Copied'); } },
      { sep: true },
      { icon: 'trash', text: t('moveToTrash'), danger: true, action: () => deleteFlow(todo) },
    ];
    UI.menu(anchor, items);
  }

  function reminderLabel(min) {
    if (min === 0) return t('onStart');
    if (min < 60) return min + ' ' + t('minutesBefore');
    if (min < 1440) return (min / 60) + ' ' + t('hoursBefore');
    return (min / 1440) + ' ' + t('daysBefore');
  }

  function deleteFlow(todo) {
    UI.confirm({
      title: t('moveToTrash'), message: t('moveToTrashBody', { t: todo.summary }),
      danger: true, confirmText: t('moveToTrash'),
    }).then((ok) => {
      if (!ok) return;
      S.softDeleteTodo(todo.id);
      App.back();
      App.render();
      UI.toast(t('deletedToast', { t: todo.summary }), {
        undo: () => { S.restoreTodo(todo.id); App.render(); },
      });
    });
  }

  function editDeadline(todo) {
    UI.sheet({
      title: t('deadline'),
      body(host, close) {
        const box = U.el('div', { class: 'picker' });
        const date = U.el('input', { class: 'input', type: 'date', value: todo.dueDate ? U.toInputDate(todo.dueDate) : U.toInputDate(U.now()) });
        date.dataset.testid = 'edit-deadline-date';
        const time = U.el('input', { class: 'input', type: 'time', value: todo.dueDate ? U.fmtTime(todo.dueDate) : '' });
        const row = U.el('div', { class: 'row2' });
        row.appendChild(date); row.appendChild(time);
        box.appendChild(row);
        box.appendChild(U.el('div', { class: 'field-hint', text: S.state.lang === 'zh' ? '只有日期的截止不显示 00:00。' : 'A date-only deadline shows no time.' }));
        const acts = U.el('div', { class: 'input-row' });
        const clear = U.el('button', { class: 'btn ghost', text: t('noDeadline') });
        clear.addEventListener('click', () => {
          S.updateTodo(todo.id, { dueDate: null });
          close(null); App.render();
          UI.toast(t('updatedToast', { t: todo.summary }));
        });
        const apply = U.el('button', { class: 'btn primary', text: t('save') });
        apply.dataset.testid = 'edit-deadline-apply';
        apply.addEventListener('click', () => {
          const d = U.fromInputDate(date.value);
          if (!d) return;
          if (time.value) {
            const [h, m] = time.value.split(':').map(Number);
            d.setHours(h, m || 0);
          }
          S.updateTodo(todo.id, { dueDate: d });
          close(null); App.render();
          UI.toast(t('updatedToast', { t: todo.summary }));
        });
        acts.appendChild(clear); acts.appendChild(apply);
        box.appendChild(acts);
        host.appendChild(box);
      },
    });
  }

  function prioritySheet(todo) {
    UI.sheet({
      title: t('priority'),
      body(host, close) {
        [[0, t('noPriority')], [1, t('low')], [5, t('medium')], [9, t('high')]].forEach(([v, label]) => {
          const b = U.el('button', { class: 'slot-sheet-option' });
          b.innerHTML = `<span class="ico">${ICON('flag', 16)}</span><span><span class="t">${U.esc(label)}</span></span>${todo.priority === v ? '<span style="margin-left:auto;color:var(--accent)">' + ICON('check', 15) + '</span>' : ''}`;
          b.addEventListener('click', () => { S.updateTodo(todo.id, { priority: v }); close(null); App.render(); });
          host.appendChild(b);
        });
      },
    });
  }

  function tagSheet(todo) {
    UI.sheet({
      title: t('tags'),
      body(host, close) {
        S.state.tags.forEach((tag) => {
          const on = todo.tagIds.includes(tag.id);
          const b = U.el('button', { class: 'slot-sheet-option' });
          b.innerHTML = `<span class="ico" style="background:color-mix(in srgb, ${tag.color} 14%, transparent);color:${tag.color}">${ICON('tag', 16)}</span><span><span class="t">${U.esc(tag.name)}</span></span>${on ? '<span style="margin-left:auto;color:var(--accent)">' + ICON('check', 15) + '</span>' : ''}`;
          b.addEventListener('click', () => {
            const next = on ? todo.tagIds.filter((x) => x !== tag.id) : todo.tagIds.concat(tag.id);
            S.updateTodo(todo.id, { tagIds: next });
            close(null); App.render();
          });
          host.appendChild(b);
        });
      },
    });
  }

  function notesEditor(todo) {
    UI.modal({
      title: t('notes'),
      body(host, close) {
        const ta = U.el('textarea', { class: 'textarea', rows: '6', 'data-autofocus': '' });
        ta.value = todo.description || '';
        host.appendChild(ta);
        const foot = U.el('div', { class: 'input-row', style: 'justify-content:flex-end;margin-top:8px' });
        const cancel = U.el('button', { class: 'btn ghost', text: t('cancel') });
        cancel.addEventListener('click', () => close(null));
        const save = U.el('button', { class: 'btn primary', text: t('save') });
        save.addEventListener('click', () => {
          S.updateTodo(todo.id, { description: ta.value.trim() || null });
          close(null); App.render();
        });
        foot.appendChild(cancel); foot.appendChild(save);
        host.appendChild(foot);
      },
    });
  }

  function scheduleSheet(todo) {
    const now = U.now();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
    UI.sheet({
      title: t('allocateNow'),
      subtitle: t('scheduleHint'),
      body(host, close) {
        const box = U.el('div', { class: 'picker' });
        const row = U.el('div', { class: 'row2' });
        const s = U.el('input', { class: 'input', type: 'datetime-local', value: U.toInputDateTime(start) });
        const dur = U.el('select', { class: 'select' });
        [15, 30, 45, 60, 90, 120].forEach((m) => dur.appendChild(U.el('option', { value: String(m), text: m + ' ' + (S.state.lang === 'zh' ? '分钟' : 'min') })));
        dur.value = '60';
        row.appendChild(s); row.appendChild(dur);
        box.appendChild(row);
        if (todo.recurrence) {
          box.appendChild(U.el('div', { class: 'hint-box warn', text: S.state.lang === 'zh' ? '这是重复待办，请选择要安排哪一次实例。' : 'This to-do repeats. Pick which occurrence to schedule.' }));
        }
        const apply = U.el('button', { class: 'btn primary', text: t('apply') });
        apply.dataset.testid = 'allocate-apply';
        apply.addEventListener('click', () => {
          const st = U.fromInputDateTime(s.value);
          if (!st) return;
          const en = U.addMinutes(st, parseInt(dur.value, 10));
          close(null);
          if (todo.recurrence) {
            pickOccurrence(todo, st, en);
          } else {
            S.createAllocation({ todoId: todo.id, startAt: st, endAt: en });
            App.render();
            UI.toast(t('scheduleToast', { t: todo.summary }), {
              undo: () => {
                const created = S.state.allocations[S.state.allocations.length - 1];
                if (created) S.cancelAllocation(created.id);
                App.render();
              },
            });
          }
        });
        box.appendChild(apply);
        host.appendChild(box);
      },
    });
  }

  function pickOccurrence(todo, start, end) {
    const from = U.addDays(U.startOfDay(U.now()), -30);
    const to = U.addDays(U.startOfDay(U.now()), 90);
    UI.sheet({
      title: t('occurrence'),
      body(host, close) {
        const box = U.el('div', { class: 'occurrence-picker' });
        S.occurrencesInWindow(todo, from, to).forEach((d) => {
          const id = S.occurrenceIdFor(todo, d);
          const isDone = S.isOccurrenceDone(todo, id);
          const b = U.el('button', { class: 'occ-row' });
          b.dataset.testid = 'occurrence-row';
          b.innerHTML = `<span class="date">${U.esc(U.fmtMonthDay(d))} · ${U.esc(U.fmtWeekdayLong(d))}</span>${isDone ? `<span class="state">${U.esc(t('completed'))}</span>` : ''}`;
          b.disabled = isDone;
          b.addEventListener('click', () => {
            close(null);
            S.createAllocation({ todoId: todo.id, startAt: start, endAt: end, occurrenceId: id });
            App.render();
            UI.toast(t('scheduleToast', { t: todo.summary }));
          });
          box.appendChild(b);
        });
        host.appendChild(box);
      },
    });
  }

  // ---------- event detail ----------
  function eventDetail(eventId, occurrenceMs) {
    const series = S.eventById(eventId);
    const occStart = occurrenceMs ? new Date(occurrenceMs) : (series ? series.startDt : U.now());
    const occEnd = series ? new Date(occStart.getTime() + (series.endDt - series.startDt)) : occStart;
    const isOcc = !!(series && series.rrule && occurrenceMs);
    const e = isOcc ? Object.assign({}, series, { startDt: occStart, endDt: occEnd, occurrenceAnchor: U.startOfDay(occStart) }) : series;

    const root = U.el('div', { class: 'detail', 'data-testid': 'event-detail' });
    const narrow = U.isNarrow();
    const head = U.el('div', { class: 'detail-head' });
    if (narrow) head.appendChild(UI.iconButton('chevronLeft', t('back'), () => App.back()));
    head.appendChild(U.el('span', { class: 'spacer' }));
    head.appendChild(UI.iconButton('edit', t('edit'), () => editEvent(e), { sm: true }));
    head.appendChild(UI.iconButton('trash', t('moveToTrash'), () => deleteEvent(e)));
    if (narrow) head.appendChild(UI.iconButton('x', t('close'), () => App.back()));
    root.appendChild(head);

    const scroll = U.el('div', { class: 'detail-scroll' });
    root.appendChild(scroll);
    scroll.appendChild(U.el('h1', { class: 'detail-title', text: e.summary }));

    const status = U.el('div', { class: 'detail-status' });
    const cal = S.calendarById(e.calendarId);
    status.innerHTML = `<span class="chip"><span class="dot" style="background:${cal ? cal.color : 'var(--accent)'}"></span>${U.esc(cal ? cal.name : '')}</span>` +
      (isOcc ? `<span class="chip violet">${ICON('repeat', 10)}<span>${U.esc(t('recurrence'))}</span></span>` : '') +
      (e.isAllDay ? `<span class="chip">${U.esc(t('allDay'))}</span>` : '');
    scroll.appendChild(status);

    const facts = U.el('div', { class: 'detail-facts' });
    scroll.appendChild(facts);
    const when = e.isAllDay
      ? `${U.esc(U.fmtMonthDay(e.startDt))} – ${U.esc(U.fmtMonthDay(e.endDt))} · ${U.esc(t('allDay'))}`
      : `${U.esc(U.fmtMonthDay(e.startDt))} ${U.esc(U.fmtTimeRange(e.startDt, e.endDt))}`;
    facts.appendChild(iconFact('calendar', t('schedule'), when, UI.iconButton('edit', t('change'), () => editEvent(e), { sm: true, size: 13 })));
    if (e.location) facts.appendChild(iconFact('pin', t('location'), U.esc(e.location)));
    if (e.rrule) {
      const rec = { freq: e.rrule.freq, interval: e.rrule.interval, byday: e.rrule.byday };
      facts.appendChild(iconFact('repeat', t('seriesRule'), U.esc(UI.ruleSummary(rec)) + (e.rrule.until ? ` · ${U.esc(t('until'))} ${U.esc(U.fmtMonthDay(e.rrule.until))}` : ''),
        UI.iconButton('edit', t('edit'), () => editEvent(e), { sm: true, size: 13 })));
    }
    if (e.tagIds && e.tagIds.length) {
      const html = e.tagIds.map((id) => {
        const tag = S.tagById(id);
        return tag ? `<span class="chip" style="background:color-mix(in srgb, ${tag.color} 12%, transparent);color:${tag.color}"><span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}</span>` : '';
      }).join('');
      facts.appendChild(iconFact('tag', t('tags'), html));
    }
    if (e.reminderOffsets && e.reminderOffsets.length) {
      facts.appendChild(iconFact('bell', t('reminder'), e.reminderOffsets.map((m) => U.esc(reminderLabel(m))).join(' · ')));
    }

    if (e.description) {
      const sec = U.el('div', { class: 'detail-section' });
      sec.appendChild(U.el('h3', { text: t('notes') }));
      sec.appendChild(U.el('div', { class: 'detail-note', text: e.description }));
      scroll.appendChild(sec);
    }

    if (e.rrule && !isOcc) {
      const sec = U.el('div', { class: 'detail-section' });
      sec.appendChild(U.el('h3', { text: S.state.lang === 'zh' ? '接下来的日程' : 'Upcoming occurrences' }));
      const box = U.el('div', { class: 'occurrence-picker' });
      const from = U.startOfDay(U.now());
      for (let i = 0; i < 60 && box.children.length < 8; i++) {
        const d = U.addDays(from, i);
        const occ = S.eventsOnDay(d).find((x) => x.id === e.id);
        if (occ) {
          const row = U.el('button', { class: 'occ-row' });
          row.innerHTML = `<span class="date">${U.esc(U.fmtMonthDay(d))} · ${U.esc(U.fmtWeekdayLong(d))}</span><span class="state">${U.esc(U.fmtTimeRange(occ.startDt, occ.endDt))}</span>`;
          row.addEventListener('click', () => S.navigate('detail', { type: 'event', id: e.id, occurrence: occ.startDt.getTime() }));
          box.appendChild(row);
        }
      }
      sec.appendChild(box);
      scroll.appendChild(sec);
    }

    const actions = U.el('div', { class: 'detail-actions' });
    const editBtn = U.el('button', { class: 'btn ghost' });
    editBtn.innerHTML = ICON('edit', 13) + `<span>${U.esc(t('edit'))}</span>`;
    editBtn.addEventListener('click', () => editEvent(e));
    actions.appendChild(editBtn);
    actions.appendChild(U.el('span', { class: 'spacer' }));
    const del = U.el('button', { class: 'btn danger-ghost', text: t('moveToTrash') });
    del.addEventListener('click', () => deleteEvent(e));
    actions.appendChild(del);
    root.appendChild(actions);
    return root;
  }

  function editEvent(e) {
    if (e.isOccurrence) {
      UI.sheet({
        title: t('repeatScopeTitle'),
        subtitle: t('repeatScopeBody'),
        body(host, close) {
          [
            { label: t('scopeThis'), desc: S.state.lang === 'zh' ? '只改这一次' : 'Change only this occurrence' },
            { label: t('scopeAll'), desc: S.state.lang === 'zh' ? '改整个系列' : 'Change the whole series' },
          ].forEach((opt, i) => {
            const b = U.el('button', { class: 'slot-sheet-option' });
            b.innerHTML = `<span class="ico">${ICON('repeat', 16)}</span><span><span class="t">${U.esc(opt.label)}</span><br><span class="s">${U.esc(opt.desc)}</span></span>`;
            b.addEventListener('click', () => {
              close(null);
              if (i === 0) {
                UI.toast(S.state.lang === 'zh' ? '单次编辑：只影响这一次' : 'Editing this occurrence only', { warn: true });
                App.openComposer('event', { mode: 'edit', id: e.id });
              } else {
                App.openComposer('event', { mode: 'edit', id: e.id });
              }
            });
            host.appendChild(b);
          });
        },
      });
      return;
    }
    App.openComposer('event', { mode: 'edit', id: e.id });
  }

  function deleteEvent(e) {
    const message = e.isOccurrence
      ? (S.state.lang === 'zh' ? '删除这一次重复日程？其他实例不受影响。' : 'Delete this occurrence? The rest of the series stays.')
      : t('eventDeleteBody');
    UI.confirm({ title: t('delete'), message, danger: true, confirmText: t('moveToTrash') }).then((ok) => {
      if (!ok) return;
      if (e.isOccurrence) {
        const series = S.eventById(e.id);
        series.exdates = (series.exdates || []).concat([e.occurrenceAnchor]);
        S.emit('event:update');
      } else {
        S.softDeleteEvent(e.id);
      }
      if (U.isNarrow()) App.back();
      App.render();
      UI.toast(t('deletedToast', { t: e.summary }), {
        undo: () => {
          if (e.isOccurrence) {
            const series = S.eventById(e.id);
            series.exdates = series.exdates.filter((x) => !U.sameDay(x, e.occurrenceAnchor));
            S.emit('event:update');
          } else {
            S.restoreEvent(e.id);
          }
          App.render();
        },
      });
    });
  }

  function renderDetail(params) {
    if (params.type === 'event') return eventDetail(params.id, params.occurrence);
    const todo = S.todoById(params.id);
    if (!todo) {
      return UI.page({
        title: t('errorTitle'),
        onBack: () => App.back(),
        build(content) {
          content.appendChild(UI.emptyState('alert', t('errorTitle'), t('errorBody'), [{ label: t('back'), primary: true, action: () => App.back() }]));
        },
      });
    }
    return todoDetail(todo);
  }

  App.defineView('detail', renderDetail);
  window.__detail = { todoDetail, eventDetail };
})();
