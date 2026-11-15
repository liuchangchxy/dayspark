/* Action — one day wide. Answers "what now / today". No date switcher. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function dayLabel(d) {
    const now = U.now();
    const locale = S.state.lang;
    const wd = U.fmtWeekdayLong(d);
    if (locale === 'zh') {
      const lunar = S.state.showLunar ? ' · ' + t('lunarSample') : '';
      return U.esc(wd + lunar);
    }
    return U.esc(wd);
  }

  function openTodo(todo) {
    S.navigate('detail', { type: 'todo', id: todo.id });
  }
  function openEvent(event) {
    S.navigate('detail', { type: 'event', id: event.id, occurrence: event.occurrenceAnchor ? event.occurrenceAnchor.getTime() : null });
  }

  function row(opts) {
    const b = U.el('div', { class: 'row' + (opts.cls ? ' ' + opts.cls : ''), role: 'button', tabindex: '0' });
    if (opts.testid) b.dataset.testid = opts.testid;
    const time = U.el('span', { class: 'row-time', text: opts.time || '' });
    b.appendChild(time);
    const leading = U.el('span', { class: 'row-leading', html: opts.leading || '' });
    b.appendChild(leading);
    const main = U.el('span', { class: 'row-main' });
    main.appendChild(U.el('span', { class: 'row-title' + (opts.done ? ' done' : ''), text: opts.title }));
    if (opts.meta) main.appendChild(U.el('span', { class: 'row-meta', html: opts.meta }));
    b.appendChild(main);
    const tail = U.el('span', { class: 'row-tail' });
    if (opts.onToggle) {
      tail.appendChild(UI.checkbox(!!opts.done, opts.onToggle, opts.toggleLabel));
    } else {
      tail.innerHTML = `<span class="row-chevron">${ICON('chevronForward', 13)}</span>`;
    }
    b.appendChild(tail);
    b.addEventListener('click', opts.onTap);
    b.addEventListener('keydown', (e) => {
      if (e.target !== b) return;
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); opts.onTap(); }
    });
    return b;
  }

  function renderAction() {
    const day = S.state.actionDate || U.startOfDay(U.now());
    const proj = S.actionProjection(day);
    const now = U.now();

    const actions = [];
    if (!U.isNarrow()) {
      const addBtn = U.el('button', { class: 'btn primary', 'data-testid': 'action-create' });
      addBtn.innerHTML = ICON('plus', 14) + `<span>${U.esc(t('newTodo'))}</span>`;
      addBtn.addEventListener('click', () => App.openComposer('todo', { dueDate: day }));
      actions.push(addBtn);
    }

    const page = UI.page({
      title: t('pageAction'),
      subtitle: dayLabel(day),
      actions,
      build(content) {
        // capture
        const cap = U.el('div', { class: 'capture' });
        cap.innerHTML = ICON('plus', 15);
        const input = U.el('input', {
          placeholder: t('capturePlaceholder'), 'aria-label': t('capturePlaceholder'),
          'data-testid': 'action-capture',
        });
        cap.appendChild(input);
        const more = U.el('button', { class: 'capture-plus', title: t('addDeadline') });
        more.innerHTML = ICON('calendarPlus', 15) + `<span>${U.esc(t('addDeadline'))}</span>`;
        more.addEventListener('click', () => App.openComposer('todo', { summary: input.value, focus: 'deadline' }));
        cap.appendChild(more);
        cap.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && input.value.trim()) {
            const todo = S.createTodo({ summary: input.value });
            input.value = '';
            UI.announce(t('createdToast', { t: todo.summary }));
            UI.toast(t('createdToast', { t: todo.summary }), {
              undo: () => { S.softDeleteTodo(todo.id); App.render(); },
            });
            S.state.highlight = 'inbox-entry';
            App.render();
          }
        });
        content.appendChild(cap);
        content.appendChild(U.el('div', { class: 'capture-hint', text: t('captureHint') }));

        // Inbox entry sits directly under the capture box: it is the answer to
        // "where did it go", so it must be visible without scrolling.
        const inbox = U.el('button', { class: 'row', 'data-testid': 'inbox-entry' });
        inbox.style.marginBottom = '4px';
        inbox.innerHTML = `<span class="row-leading">${ICON('inbox', 15)}</span><span class="row-main"><span class="row-title" style="color:var(--ink-2)">${U.esc(t('inboxEntry', { n: proj.inboxCount }))}</span></span><span class="row-tail"><span class="row-chevron">${ICON('chevronForward', 13)}</span></span>`;
        inbox.addEventListener('click', () => {
          S.state.todosView = { kind: 'inbox', day: null };
          App.go('todos');
        });
        content.appendChild(inbox);

        UI.busyBar(day, content);

        const sections = [];

        // Now
        const current = [
          ...proj.events.filter((e) => e.startDt <= now && e.endDt > now).map((e) => ({ kind: 'event', start: e.startDt, end: e.endDt, event: e })),
          ...proj.allocations.filter((x) => x.allocation.startAt <= now && x.allocation.endAt > now).map((x) => ({ kind: 'alloc', start: x.allocation.startAt, end: x.allocation.endAt, item: x })),
        ].sort((a, b) => a.start - b.start);

        if (current.length) {
          sections.push(UI.sectionHead(t('actionNow'), current.length, { tone: 'warm' }));
          current.forEach((entry) => sections.push(entryRow(entry, true, now)));
        }

        const later = [
          ...proj.events.filter((e) => e.startDt > now).map((e) => ({ kind: 'event', start: e.startDt, end: e.endDt, event: e })),
          ...proj.allocations.filter((x) => x.allocation.startAt > now).map((x) => ({ kind: 'alloc', start: x.allocation.startAt, end: x.allocation.endAt, item: x })),
        ].sort((a, b) => a.start - b.start);
        if (later.length) {
          sections.push(UI.sectionHead(t('laterToday'), later.length, { right: { text: t('openCalendar'), icon: 'chevronForward', action: () => App.go('calendar') } }));
          later.forEach((entry) => sections.push(entryRow(entry, false, now)));
        }

        const dueRows = [];
        proj.todayTaskInstances.forEach((inst) => dueRows.push(instanceRow(inst, false, day)));
        proj.dueTodayTodos.forEach((todo) => dueRows.push(todoRow(todo, now)));
        if (dueRows.length) {
          sections.push(UI.sectionHead(t('dueTodaySection'), dueRows.length));
          dueRows.forEach((r) => sections.push(r));
        }

        const overdueRows = [];
        proj.overdueTodos.forEach((todo) => overdueRows.push(todoRow(todo, now)));
        proj.missedTaskInstances.slice(0, 5).forEach((inst) => overdueRows.push(instanceRow(inst, true, day)));
        if (overdueRows.length) {
          sections.push(UI.sectionHead(t('overdue'), overdueRows.length, { tone: 'danger' }));
          overdueRows.forEach((r) => sections.push(r));
        }

        const earlier = [
          ...proj.events.filter((e) => e.endDt <= now).map((e) => ({ kind: 'event', start: e.startDt, end: e.endDt, event: e })),
          ...proj.allocations.filter((x) => x.allocation.endAt <= now).map((x) => ({ kind: 'alloc', start: x.allocation.startAt, end: x.allocation.endAt, item: x })),
        ].sort((a, b) => a.start - b.start);
        const doneRows = [];
        earlier.forEach((entry) => doneRows.push(entryRow(entry, false, now, true)));
        proj.completedTodayTodos.forEach((todo) => doneRows.push(todoRow(todo, now, true)));
        proj.completedTodayTaskInstances.forEach((inst) => doneRows.push(instanceRow(inst, false, day, true)));
        if (doneRows.length) {
          sections.push(UI.sectionHead(t('actionEarlierToday'), doneRows.length));
          doneRows.forEach((r) => sections.push(r));
        }

        // Inbox entry is always present: it is the answer to "where did it go".
        if (!sections.length) {
          content.appendChild(UI.emptyState('bolt', t('actionNothingNow'), t('actionNothingNowHint'), [
            { label: t('newTodo'), primary: true, action: () => App.openComposer('todo', { dueDate: day }) },
            { label: t('openCalendar'), action: () => App.go('calendar') },
          ]));
          return;
        }
        sections.forEach((node) => content.appendChild(node));
      },
    });

    if (U.isNarrow()) {
      const fab = U.el('button', { class: 'btn primary', 'data-testid': 'action-create' });
      fab.innerHTML = ICON('plus', 14) + `<span>${U.esc(t('newTodo'))}</span>`;
      fab.style.position = 'fixed';
      fab.style.right = '16px';
      fab.style.bottom = '66px';
      fab.style.zIndex = '40';
      fab.style.boxShadow = 'var(--shadow-1)';
      fab.addEventListener('click', () => App.openComposer('todo', { dueDate: day }));
      page.appendChild(fab);
    }
    return page;
  }

  function entryRow(entry, warm, now, past) {
    if (entry.kind === 'event') {
      const e = entry.event;
      return row({
        time: U.fmtTime(e.startDt),
        leading: `<span style="color:${S.calendarColor(e.calendarId)}">${ICON('calendar', 14)}</span>`,
        title: e.summary,
        meta: `<span>${U.esc(t('untilTime', { t: U.fmtTime(e.endDt) }))}</span>${e.location ? `<span>·</span><span>${U.esc(e.location)}</span>` : ''}`,
        cls: (warm ? 'current' : '') + (past ? ' past' : ''),
        done: past,
        onTap: () => openEvent(e),
        testid: 'action-event',
      });
    }
    const item = entry.item;
    const todo = item.todo;
    const a = item.allocation;
    return row({
      time: U.fmtTime(a.startAt),
      leading: `<span style="color:var(--violet)">${ICON('clock', 14)}</span>`,
      title: todo.summary,
      meta: `<span>${U.esc(t('scheduledTime'))}</span>${UI.deadlineMeta(todo, now) ? '<span>·</span>' + UI.deadlineMeta(todo, now) : ''}`,
      cls: (warm ? 'current' : '') + (past ? ' past' : ''),
      done: S.isDone(todo),
      onToggle: () => {
        if (todo.recurrence && !a.occurrenceId) return;
        toggle(todo, a.occurrenceId);
      },
      onTap: () => openTodo(todo),
      testid: 'action-allocation',
    });
  }

  function todoRow(todo, now, past) {
    const isOverdue = S.isOpen(todo) && todo.dueDate && todo.dueDate < now;
    const clock = todo.dueDate ? U.fmtClockNoMidnight(todo.dueDate) : '';
    return row({
      time: clock || (todo.dueDate ? t('today') : ''),
      leading: `<span style="color:${isOverdue ? 'var(--red)' : 'var(--amber)'}">${ICON('flag', 14)}</span>`,
      title: todo.summary,
      meta: [
        todo.dueDate ? `<span class="${isOverdue ? 'row-deadline over' : 'row-deadline'}">${U.esc(t('deadlinePrefix', { d: U.fmtDeadline(todo.dueDate) }))}</span>` : '',
        UI.allocMeta(todo),
        UI.priorityDot(todo.priority),
        UI.tagChips(todo.tagIds, 2),
      ].filter(Boolean).join('<span>·</span>'),
      cls: (isOverdue && !past ? 'overdue' : '') + (past ? ' past' : ''),
      done: S.isDone(todo),
      onToggle: () => toggle(todo),
      onTap: () => openTodo(todo),
      testid: 'action-todo',
    });
  }

  function instanceRow(inst, missed, day, past) {
    const todo = inst.todo;
    const done = S.isOccurrenceDone(todo, inst.occurrenceId);
    return row({
      time: missed ? U.fmtMonthDay(inst.day) : '',
      leading: `<span style="color:var(--violet)">${ICON('repeat', 14)}</span>`,
      title: todo.summary,
      meta: `<span>${U.esc(missed ? t('missed') : t('recurringTask'))}</span><span>·</span><span>${U.esc(U.fmtRelativeDay(inst.day, day))}</span>${UI.priorityDot(todo.priority)}`,
      cls: (missed ? 'overdue' : '') + (past ? ' past' : ''),
      done,
      onToggle: () => toggle(todo, inst.occurrenceId),
      onTap: () => openTodo(todo),
      testid: 'action-instance',
    });
  }

  function toggle(todo, occurrenceId) {
    const wasDone = todo.recurrence ? S.isOccurrenceDone(todo, occurrenceId) : S.isDone(todo);
    const result = S.completeTodo(todo.id, { occurrenceId });
    if (!result) {
      UI.toast(S.state.lang === 'zh' ? '这个重复任务需要选择具体实例' : 'Pick an occurrence first', { warn: true });
      return;
    }
    App.render();
    if (!wasDone) {
      UI.toast(t('completedToast', { t: todo.summary }), {
        undo: () => { S.completeTodo(todo.id, { occurrenceId }); App.render(); },
      });
    } else {
      UI.toast(t('uncompletedToast', { t: todo.summary }), {
        undo: () => { S.completeTodo(todo.id, { occurrenceId }); App.render(); },
      });
    }
  }

  App.defineView('action', renderAction);
  App.defineView('todos', () => {
    // routed through todo.js renderTodos
    return window.__renderTodos ? window.__renderTodos() : UI.page({ title: t('pageTodos'), build() {} });
  });
})();
