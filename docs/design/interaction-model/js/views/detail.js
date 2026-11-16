/* Detail: read-only surface for a Todo or Event. Edit is an explicit action.
   Todo detail also carries occurrence state, allocations and subtasks. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function iconFact(icon, key, valueHtml, actNode, cls, onValue) {
    const f = U.el('div', { class: 'fact' + (cls ? ' ' + cls : '') });
    f.innerHTML = `<span class="ico">${ICON(icon, 15)}</span><span class="body"><span class="k">${U.esc(key)}</span><span class="v">${valueHtml}</span></span>`;
    if (onValue) {
      const v = f.querySelector('.v');
      v.setAttribute('role', 'button');
      v.setAttribute('tabindex', '0');
      v.title = t('editInline');
      v.style.cursor = 'pointer';
      v.addEventListener('click', onValue);
      v.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onValue(); }
      });
    }
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

  // A series' deadline time applied to the occurrence's own day.
  function occurrenceDeadline(due, day) {
    const d = U.startOfDay(day);
    const src = new Date(due);
    if (src.getHours() === 0 && src.getMinutes() === 0) return d;
    d.setHours(src.getHours(), src.getMinutes(), 0, 0);
    return d;
  }

  function todoDetail(todo, contextDay) {
    const root = U.el('div', { class: 'detail', 'data-testid': 'todo-detail' });
    // A record in the Trash still opens, but only its facts and a way back:
    // the banner is the surface, not an error page, and nothing here writes.
    const ro = !!todo.deletedAt;
    const on = (fn) => (ro ? null : fn);
    const editBtnFor = (label, fn, opts) => (ro ? null : UI.iconButton('edit', label, fn, opts));
    // A detail opened for a day is about THAT occurrence. Reading the series'
    // anchor here made the page disagree with the row that opened it, and made
    // 取消安排 cancel a block belonging to another day.
    const contextStart = contextDay ? U.startOfDay(contextDay) : U.startOfDay(U.now());
    const contextOcc = todo.recurrence && S.matchesRule(todo, contextStart)
      ? S.occurrenceIdFor(todo, contextStart) : null;
    const dueForContext = todo.recurrence
      ? (contextDay && S.matchesRule(todo, contextStart)
        ? occurrenceDeadline(todo.dueDate, contextStart)
        : todo.dueDate)
      : todo.dueDate;
    const narrow = U.isNarrow();
    // A routed detail is a page at every width, so it always offers a visible
    // way back. A pane does not: its route is still Todo.
    const routed = S.state.route.name === 'detail';
    const head = U.el('div', { class: 'detail-head' });
    if (narrow || routed) head.appendChild(UI.iconButton('chevronLeft', t('back'), () => App.back(), { cls: 'back-btn' }));
    head.appendChild(U.el('span', { class: 'spacer' }));
    // A menu opened from a click needs to stop that click reaching the
    // document-level "click outside a menu closes it" handler, or it is built
    // and torn down in the same frame and the button looks dead.
    const moreBtn = UI.iconButton('sliders', t('more'), (ev) => {
      ev.stopPropagation();
      openMenu(moreBtn, todo);
    });
    // A trashed record is read-only: its only action is 恢复 in the banner. The
    // header menu used to stay live and wrote through every item.
    if (!ro) head.appendChild(moreBtn);
    if (narrow) head.appendChild(UI.iconButton('x', t('close'), () => App.back()));
    root.appendChild(head);

    const scroll = U.el('div', { class: 'detail-scroll' });
    root.appendChild(scroll);

    const title = U.el('h1', { class: 'detail-title' + (S.isDone(todo) ? ' done' : ''), text: todo.summary });
    scroll.appendChild(title);

    // A record that was deleted in another surface must not keep offering live
    // edits as if nothing happened.
    if (todo.deletedAt) {
      const bar = U.el('div', { class: 'deleted-banner', 'data-testid': 'detail-deleted' });
      bar.appendChild(U.el('div', { class: 'msg', html: `<strong>${U.esc(t('recordDeleted'))}</strong><span>${U.esc(t('recordDeletedHint'))}</span>` }));
      const restore = U.el('button', { class: 'btn primary sm', text: t('restore'), 'data-testid': 'detail-restore' });
      restore.addEventListener('click', () => {
        S.restoreTodo(todo.id);
        App.render();
        UI.toast(t('restoredToast', { t: todo.summary }));
      });
      const backBtn = U.el('button', { class: 'btn ghost sm', text: t('close') });
      backBtn.addEventListener('click', () => {
        if (S.state.paneSelection) S.clearPane(); else App.back();
      });
      bar.appendChild(restore);
      bar.appendChild(backBtn);
      scroll.appendChild(bar);
    }

    const status = U.el('div', { class: 'detail-status' });
    // A recurring detail is about one occurrence, not the series. The series
    // itself is never done, so the button has to read the occurrence's state.
    const done = todo.recurrence
      ? (contextOcc ? S.isOccurrenceDone(todo, contextOcc) : false)
      : S.isDone(todo);
    const doneAt = todo.recurrence && contextOcc
      ? ((S.occurrenceState(todo, contextOcc) || {}).completedAt || null)
      : todo.completedAt;
    // A trashed record is not a live obligation: completion and edits wait
    // until it is restored.
    if (!todo.deletedAt) {
      const doneBtn = U.el('button', { class: 'btn ' + (done ? 'ghost' : 'primary'), 'data-testid': 'detail-complete' });
      doneBtn.innerHTML = ICON('check', 14) + `<span>${U.esc(done ? t('markIncomplete') : t('markComplete'))}</span>`;
      doneBtn.addEventListener('click', () => {
        // Completion follows the day the record was opened from. A recurring
        // series has one open instance per day, so "today" is only correct
        // when the detail came from Today or an undated surface.
        if (todo.recurrence && !contextOcc) {
          UI.toast(t('recurrenceNeedsOccurrence'), { warn: true });
          return;
        }
        window.TodoOps.complete(todo, contextOcc);
      });
      status.appendChild(doneBtn);
    }
    if (todo.recurrence) status.appendChild(U.el('span', { class: 'chip violet', html: ICON('repeat', 10) + `<span>${U.esc(t('recurrence'))}</span>` }));
    if (doneAt && done) status.appendChild(U.el('span', { class: 'tiny muted', text: t('completed') + ' · ' + U.fmtMonthDayTime(doneAt) }));
    scroll.appendChild(status);

    const facts = U.el('div', { class: 'detail-facts' });
    scroll.appendChild(facts);

    // Sections follow CORE_UX_SPEC 4.2 so the detail and the editor read in
    // the same order: 时间 / 提醒 / 整理 / 内容.
    facts.appendChild(U.el('div', { class: 'form-section-title', text: t('sectionTime') }));

    // deadline
    // An occurrence's deadline is derived from the series; writing the series'
    // anchor from here moved every occurrence. Editing a recurring deadline is a
    // series edit, so it goes through 编辑.
    const dueAct = todo.recurrence ? null : editBtnFor(t('change'), () => editDeadline(todo), { sm: true, size: 13 });
    facts.appendChild(iconFact(
      'flag',
      t('deadline'),
      dueForContext ? U.esc(U.fmtDeadline(dueForContext)) : `<span class="muted">${U.esc(t('noDeadline'))}</span>`,
      dueAct,
      'amber',
      todo.recurrence ? null : on(() => editDeadline(todo)),
    ));

    // scheduled allocations
    const allocs = S.allocationsForTodo(todo.id)
      .filter((a) => !todo.recurrence || a.occurrenceId === contextOcc);
    // A trashed todo is hidden from live surfaces, but the blocks it holds are
    // still its own history: read them by their own state so the detail does
    // not call an active block "invalidated".
    const allocLive = (a) => (ro ? a.state === S.ALLOC.ACTIVE && !a.deletedAt : S.isAllocationLive(a));
    const liveAllocs = allocs.filter(allocLive);
    // Work that is already finished has nothing to reserve: offering the
    // control would write a block the completion rule immediately invalidates,
    // which looks like a successful action and produces nothing.
    const scheduleClosed = ro || (!todo.recurrence && S.isDone(todo));
    const allocValue = scheduleClosed && !ro && S.isDone(todo)
      ? `<span class="muted">${U.esc(t('scheduleNeedsOpen'))}</span>`
      : (liveAllocs.length ? '' : `<span class="muted">${U.esc(t('noSchedule'))}</span>`);
    const addAlloc = scheduleClosed ? null : UI.iconButton('clockPlus', t('allocateNow'), () => scheduleSheet(todo), { sm: true, size: 13 });
    if (addAlloc) addAlloc.dataset.testid = 'detail-schedule';
    const allocFact = iconFact('clock', t('scheduleExec'), allocValue, addAlloc, 'violet', on(() => scheduleSheet(todo)));
    facts.appendChild(allocFact);
    if (liveAllocs.length) {
      const list = allocFact.querySelector('.v');
      liveAllocs.forEach((a) => {
        const line = U.el('div', { class: 'alloc-live' });
        line.dataset.testid = 'live-allocation';
        const label = U.el('span', { text: U.fmtMonthDayTime(a.startAt) + ' – ' + U.fmtTime(a.endAt) });
        const cancel = U.el('button', { class: 'link-danger', text: t('cancelAllocation') });
        cancel.dataset.testid = 'cancel-allocation';
        cancel.addEventListener('click', (ev) => {
          // The row's value is itself click-to-edit; without this the cancel
          // tap also opens the scheduling sheet underneath the confirm.
          ev.stopPropagation();
          cancelAllocationFlow(a, todo);
        });
        line.appendChild(label);
        if (!ro) line.appendChild(cancel);
        list.appendChild(line);
      });
    }

    // repeat
    if (todo.recurrence) {
      facts.appendChild(iconFact('repeat', t('seriesRule'), U.esc(UI.ruleSummary(todo.recurrence)) + `<span class="tiny muted"> · ${U.esc(todo.recurrence.timeZone)}</span>`,
        editBtnFor(t('edit'), () => App.openComposer('todo', { mode: 'edit', id: todo.id, focus: 'repeat' }), { sm: true, size: 13 })));
    }

    // reminders: part of 提醒, ahead of the organising fields.
    facts.appendChild(U.el('div', { class: 'form-section-title', text: t('sectionReminder') }));
    const remValue = todo.reminderOffsets.length
      ? todo.reminderOffsets.map((m) => U.esc(reminderLabel(m))).join(' · ')
      : `<span class="muted">${U.esc(t('none'))}</span>`;
    const remFact = iconFact('bell', t('reminder'), remValue,
      ro ? null : UI.iconButton('edit', t('reminderEdit'), () => reminderSheet(todo), { sm: true, size: 13, testid: 'detail-reminder-edit' }),
      null, on(() => reminderSheet(todo)));
    facts.appendChild(remFact);

    // 整理
    facts.appendChild(U.el('div', { class: 'form-section-title', text: t('sectionOrganize') }));

    // priority
    const prioLabel = { 9: t('high'), 5: t('medium'), 1: t('low') }[todo.priority] || t('noPriority');
    facts.appendChild(iconFact('flag', t('priority'), U.esc(prioLabel),
      editBtnFor(t('change'), () => prioritySheet(todo), { sm: true, size: 13 }), null, on(() => prioritySheet(todo))));

    // tags
    const tagsHtml = todo.tagIds.length
      ? todo.tagIds.map((id) => {
        const tag = S.tagById(id);
        return tag ? `<span class="chip" style="background:color-mix(in srgb, ${tag.color} 12%, transparent);color:${tag.color}"><span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}</span>` : '';
      }).join('')
      : `<span class="muted">${U.esc(t('none'))}</span>`;
    facts.appendChild(iconFact('tag', t('tags'), tagsHtml,
      editBtnFor(t('change'), () => tagSheet(todo), { sm: true, size: 13 }), null, on(() => tagSheet(todo))));

    // calendar: a fact, not an inline editor. Picking a calendar in place writes
    // on the pick with no commit boundary (D-13); changing it is a 编辑 action.
    const cal = S.calendarById(todo.calendarId);
    facts.appendChild(iconFact(
      'folder',
      t('ownCalendar'),
      `<span class="chip"><span class="dot" style="background:${cal ? cal.color : 'var(--accent)'}"></span>${U.esc(cal ? cal.name : '')}</span>`,
      null,
      null,
      null,
    ));

    // parent
    if (todo.parentId) {
      const parent = S.todoById(todo.parentId);
      if (parent) {
        facts.appendChild(iconFact('list', t('parentTodo'), `<a href="#" data-parent>${U.esc(parent.summary)}</a>`));
        const link = facts.querySelector('[data-parent]');
        if (link) link.addEventListener('click', (e) => { e.preventDefault(); App.openRecord('todo', parent.id); });
      }
    }

    // 内容
    facts.appendChild(U.el('div', { class: 'form-section-title', text: t('sectionContent') }));

    // occurrences
    // A trashed record is read-only as a whole page (D-18): no occurrence
    // checkboxes, and none of the copy that promises completion.
    if (todo.recurrence && !ro) {
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
        const occBox = UI.checkbox(isDone, () => {
          if (ro) return;
          window.TodoOps.complete(todo, id);
        }, todo.summary);
        if (ro) { occBox.disabled = true; occBox.setAttribute('aria-disabled', 'true'); }
        row.appendChild(occBox);
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
          // A subtask may repeat, so both its shown state and its write resolve
          // the same occurrence. Reading the series status left the box unchecked
          // after a real write, and a second click deleted that occurrence again.
          const subOcc = sub.recurrence && S.matchesRule(sub, contextStart)
            ? S.occurrenceIdFor(sub, contextStart) : null;
          const subDone = sub.recurrence
            ? (subOcc ? S.isOccurrenceDone(sub, subOcc) : false)
            : S.isDone(sub);
          const subBox = UI.checkbox(subDone, () => {
            if (ro) return;
            window.TodoOps.complete(sub, subOcc || undefined);
          });
          if (ro) { subBox.disabled = true; subBox.setAttribute('aria-disabled', 'true'); }
          row.appendChild(subBox);
          const title = U.el('button', { class: 'title', text: sub.summary, style: 'text-align:left' });
          if (subDone) title.style.textDecoration = 'line-through';
          title.addEventListener('click', () => App.openRecord('todo', sub.id));
          row.appendChild(title);
          if (sub.dueDate) {
            const subDue = sub.recurrence ? occurrenceDeadline(sub.dueDate, contextStart) : sub.dueDate;
            row.appendChild(U.el('span', { class: 'tiny muted', text: U.fmtDeadline(subDue) }));
          }
          sec.appendChild(row);
        });
      } else {
        sec.appendChild(U.el('div', { class: 'field-hint', text: t('noSubtasks') }));
      }
      const addSub = ro ? null : U.el('button', { class: 'btn ghost sm', style: 'margin-top:8px' });
      if (addSub) {
        addSub.innerHTML = ICON('plus', 12) + `<span>${U.esc(t('addSubtask'))}</span>`;
        addSub.addEventListener('click', () => App.openComposer('todo', { parentId: todo.id }));
        sec.appendChild(addSub);
      }
      scroll.appendChild(sec);
    }

    // allocation history
    const history = allocs.filter((a) => !allocLive(a));
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
    if (!ro) {
      notes.style.cursor = 'pointer';
      notes.title = t('editInline');
      notes.addEventListener('click', () => notesEditor(todo));
    }
    notesSec.appendChild(notes);
    scroll.appendChild(notesSec);

    // Attachments are a local, read-only resource once saved: open is a local
    // handoff, delete is a real write, and the surface says which it is.
    const attach = (todo.attachments || []);
    const attachSec = U.el('div', { class: 'detail-section', 'data-testid': 'detail-attachments' });
    attachSec.appendChild(U.el('h3', { text: t('attachments') + (attach.length ? ' · ' + attach.length : '') }));
    if (!attach.length) {
      attachSec.appendChild(U.el('div', { class: 'field-hint', text: t('none') }));
    } else {
      attach.forEach((name, idx) => {
        const row = U.el('div', { class: 'attachment-row' });
        const open = U.el('button', { class: 'link-btn', text: name, 'data-testid': 'attachment-open' });
        open.addEventListener('click', () => UI.toast(t('attachmentLocal') + ' · ' + name));
        row.appendChild(open);
        if (!ro) {
          const del = U.el('button', { class: 'icon-btn sm', 'aria-label': t('remove'), html: ICON('trash', 13), 'data-testid': 'attachment-delete' });
          del.addEventListener('click', () => {
            const next = attach.slice();
            next.splice(idx, 1);
            if (writeTodo(todo, { attachments: next })) {
              App.render();
              UI.toast(t('updatedToast', { t: todo.summary }));
            }
          });
          row.appendChild(del);
        }
        attachSec.appendChild(row);
      });
    }
    scroll.appendChild(attachSec);

    // meta
    const metaSec = U.el('div', { class: 'detail-section' });
    metaSec.innerHTML = `<div class="kv"><span class="k">${U.esc(t('createdAt'))}</span><span class="v">${U.esc(U.fmtMonthDayTime(todo.createdAt))}</span></div>` +
      `<div class="kv"><span class="k">${U.esc(t('updatedAt'))}</span><span class="v">${U.esc(U.fmtMonthDayTime(todo.updatedAt))}</span></div>`;
    scroll.appendChild(metaSec);

    const actions = U.el('div', { class: 'detail-actions' });
    if (todo.deletedAt) { root.appendChild(actions); return root; }
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
    ];
    // Finished work reserves nothing. Offering the item and refusing on click
    // made an unavailable action look available, and the row menu elsewhere
    // still offered it outright.
    if (S.isOpen(todo)) {
      items.push({ icon: 'clockPlus', text: t('allocateNow'), action: () => scheduleSheet(todo) });
    }
    items.push(
      { icon: 'list', text: t('addSubtask'), action: () => App.openComposer('todo', { parentId: todo.id }) },
      { icon: 'copy', text: S.state.lang === 'zh' ? '复制标题' : 'Copy title', action: () => {
        const done = () => UI.toast(S.state.lang === 'zh' ? '已复制' : 'Copied');
        const fail = () => UI.toast(S.state.lang === 'zh' ? '复制失败' : 'Copy failed', { warn: true });
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(todo.summary).then(done, fail);
        else fail();
      } },
      { sep: true },
      { icon: 'trash', text: t('moveToTrash'), danger: true, action: () => deleteFlow(todo) },
    );
    UI.menu(anchor, items);
  }

  function reminderLabel(min) {
    if (min === 0) return t('onStart');
    if (min < 60) return min + ' ' + t('minutesBefore');
    if (min < 1440) return (min / 60) + ' ' + t('hoursBefore');
    return (min / 1440) + ' ' + t('daysBefore');
  }

  function cancelAllocationFlow(a, todo) {
    UI.confirm({
      title: t('cancelAllocation'),
      message: t('cancelAllocationBody'),
      danger: true,
      confirmText: t('cancelAllocation'),
    }).then((ok) => {
      if (!ok) return;
      const prev = { start: a.startAt, end: a.endAt };
      S.cancelAllocation(a.id);
      App.render();
      UI.toast(t('allocationCancelled'), {
        undo: () => {
          const cur = S.state.allocations.find((x) => x.id === a.id);
          if (cur) {
            cur.state = S.ALLOC.ACTIVE;
            cur.startAt = prev.start;
            cur.endAt = prev.end;
            S.emit('allocation:restore');
          }
          App.render();
        },
      });
    });
  }

  function deleteFlow(todo) {
    UI.confirm({
      title: t('moveToTrash'), message: t('moveToTrashBody', { t: todo.summary }),
      danger: true, confirmText: t('moveToTrash'),
    }).then((ok) => {
      if (!ok) return;
      const inPane = !!S.state.paneSelection;
      S.softDeleteTodo(todo.id);
      if (!inPane) App.back();
      App.render();
      UI.toast(t('deletedToast', { t: todo.summary }), {
        undo: () => { S.restoreTodo(todo.id); App.render(); },
      });
    });
  }

  // Inline edits share one write path so a failed write leaves the old value
  // visible and offers the retry, instead of pretending the change landed.
  function writeTodo(todo, patch) {
    if (todo.deletedAt) {
      UI.toast(t('recordDeleted'), { warn: true });
      return false;
    }
    if (S.state.simulateDetailFailure) {
      S.state.simulateDetailFailure = false;
      const host = document.querySelector('[data-testid="todo-detail"] .detail-scroll');
      if (host) {
        const bar = U.el('div', { class: 'save-error', 'data-testid': 'detail-save-error' });
        bar.appendChild(U.el('span', { text: t('detailSaveFailed') }));
        const retry = U.el('button', { class: 'btn ghost sm', text: t('retry'), 'data-testid': 'detail-retry' });
        retry.addEventListener('click', () => {
          S.updateTodo(todo.id, patch);
          App.render();
          UI.toast(t('updatedToast', { t: todo.summary }));
        });
        bar.appendChild(retry);
        host.prepend(bar);
      }
      return false;
    }
    S.updateTodo(todo.id, patch);
    return true;
  }

  function reminderSheet(todo) {
    let offsets = todo.reminderOffsets.slice();
    UI.sheet({
      title: t('reminder'),
      body(host, close) {
        function draw() {
          host.innerHTML = '';
          const box = U.el('div', { class: 'picker', 'data-testid': 'detail-reminders' });
          host.appendChild(box);
          const current = U.el('div', { class: 'chip-row' });
          if (!offsets.length) current.appendChild(U.el('span', { class: 'tiny muted', text: t('none') }));
          offsets.forEach((min, idx) => {
            const chip = U.el('span', { class: 'chip amber' });
            chip.innerHTML = `${ICON('bell', 11)}<span>${U.esc(reminderLabel(min))}</span>`;
            const x = U.el('button', { class: 'icon-btn sm', style: 'width:16px;height:16px', 'aria-label': t('remove'), html: ICON('x', 10) });
            x.addEventListener('click', () => { offsets.splice(idx, 1); draw(); });
            chip.appendChild(x);
            current.appendChild(chip);
          });
          box.appendChild(current);
          box.appendChild(U.el('div', { class: 'field-label', text: t('addReminder') }));
          [[0, t('onStart')], [5, '5 ' + t('minutesBefore')], [15, '15 ' + t('minutesBefore')], [30, '30 ' + t('minutesBefore')], [60, '1 ' + t('hoursBefore')], [1440, '1 ' + t('daysBefore')]].forEach(([v, label]) => {
            const b = U.el('button', { class: 'slot-sheet-option' });
            b.dataset.testid = 'detail-reminder-option';
            b.innerHTML = `<span class="ico">${ICON('bell', 16)}</span><span><span class="t">${U.esc(label)}</span></span>`;
            b.addEventListener('click', () => {
              if (!offsets.includes(v)) offsets.push(v);
              offsets.sort((a, b2) => a - b2);
              draw();
            });
            box.appendChild(b);
          });
          const acts = U.el('div', { class: 'input-row' });
          const apply = U.el('button', { class: 'btn primary', text: t('save'), 'data-testid': 'detail-reminder-save' });
          apply.addEventListener('click', () => {
            const ok = writeTodo(todo, { reminderOffsets: offsets.slice() });
            close(null);
            if (ok) { App.render(); UI.toast(t('updatedToast', { t: todo.summary })); }
          });
          acts.appendChild(apply);
          box.appendChild(acts);
        }
        draw();
      },
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
          const ok = writeTodo(todo, { dueDate: null });
          close(null); if (ok) { App.render(); UI.toast(t('updatedToast', { t: todo.summary })); }
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
          const ok = writeTodo(todo, { dueDate: d });
          close(null); if (ok) { App.render(); UI.toast(t('updatedToast', { t: todo.summary })); }
        });
        acts.appendChild(clear); acts.appendChild(apply);
        box.appendChild(acts);
        host.appendChild(box);
      },
    });
  }

  function changeCalendar(todo) {
    UI.openCalendarSheet(todo.calendarId, (id) => {
      if (writeTodo(todo, { calendarId: id })) {
        App.render();
        UI.toast(t('updatedToast', { t: todo.summary }));
      }
    });
  }

  function prioritySheet(todo) {
    UI.sheet({
      title: t('priority'),
      body(host, close) {
        [[0, t('noPriority')], [1, t('low')], [5, t('medium')], [9, t('high')]].forEach(([v, label]) => {
          const b = U.el('button', { class: 'slot-sheet-option' });
          b.innerHTML = `<span class="ico">${ICON('flag', 16)}</span><span><span class="t">${U.esc(label)}</span></span>${todo.priority === v ? '<span style="margin-left:auto;color:var(--accent)">' + ICON('check', 15) + '</span>' : ''}`;
          b.addEventListener('click', () => {
            const ok = writeTodo(todo, { priority: v });
            close(null); if (ok) App.render();
          });
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
            const ok = writeTodo(todo, { tagIds: next });
            close(null); if (ok) App.render();
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
          const ok = writeTodo(todo, { description: ta.value.trim() || null });
          close(null); if (ok) App.render();
        });
        foot.appendChild(cancel); foot.appendChild(save);
        host.appendChild(foot);
      },
    });
  }

  function scheduleSheet(todo) {
    if (todo.deletedAt) return;
    if (!todo.recurrence && S.isDone(todo)) {
      UI.toast(t('scheduleNeedsOpen'), { warn: true });
      return;
    }
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
            const created = S.createAllocation({ todoId: todo.id, startAt: st, endAt: en });
            const hit = S.conflictAt(created.startAt, created.endAt, { ignoreAllocId: created.id, ignoreTodoId: todo.id });
            App.render();
            const clash = hit ? t('allocateConflict', { t: hit.summary }) : null;
            UI.toast(t('scheduleToast', { t: todo.summary }) + (clash ? ' · ' + clash : ''), {
              undo: () => {
                const created = S.state.allocations[S.state.allocations.length - 1];
                if (created) S.deleteAllocation(created.id);
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
            // D-05 moves the block onto the occurrence's own day, so the
            // conflict must be read from the block that was actually written.
            const created = S.createAllocation({ todoId: todo.id, startAt: start, endAt: end, occurrenceId: id });
            const hit = S.conflictAt(created.startAt, created.endAt, { ignoreAllocId: created.id, ignoreTodoId: todo.id });
            App.render();
            const clash = hit ? t('allocateConflict', { t: hit.summary }) : null;
            UI.toast(t('scheduleToast', { t: todo.summary }) + (clash ? ' · ' + clash : ''));
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
    if (!series) {
      return UI.page({
        title: t('errorTitle'),
        onBack: () => App.back(),
        build(content) {
          content.appendChild(UI.emptyState('alert', t('errorTitle'), t('errorBody'), [
            { label: t('back'), primary: true, action: () => App.back() },
          ]));
        },
      });
    }
    // A trashed event opens read-only with its banner; only a missing record
    // is an error page.
    const roEvent = !!series.deletedAt;
    const occStart = occurrenceMs ? new Date(occurrenceMs) : (series ? series.startDt : U.now());
    const occEnd = series ? new Date(occStart.getTime() + (series.endDt - series.startDt)) : occStart;
    const isOcc = !!(series && series.rrule && occurrenceMs);
    const e = isOcc
      ? Object.assign({}, series, {
        startDt: occStart, endDt: occEnd,
        occurrenceAnchor: U.startOfDay(occStart), isOccurrence: true,
      })
      : series;

    const root = U.el('div', { class: 'detail', 'data-testid': 'event-detail' });
    const narrow = U.isNarrow();
    // A routed detail is a page at every width, so it always offers a visible
    // way back. A pane does not: its route is still Todo.
    const routed = S.state.route.name === 'detail';
    const head = U.el('div', { class: 'detail-head' });
    if (narrow || routed) head.appendChild(UI.iconButton('chevronLeft', t('back'), () => App.back(), { cls: 'back-btn' }));
    head.appendChild(U.el('span', { class: 'spacer' }));
    if (!roEvent) {
      head.appendChild(UI.iconButton('edit', t('edit'), () => editEvent(e), { sm: true }));
      head.appendChild(UI.iconButton('trash', t('moveToTrash'), () => deleteEvent(e)));
    }
    if (narrow) head.appendChild(UI.iconButton('x', t('close'), () => App.back()));
    root.appendChild(head);

    const scroll = U.el('div', { class: 'detail-scroll' });
    root.appendChild(scroll);
    scroll.appendChild(U.el('h1', { class: 'detail-title', text: e.summary }));

    if (roEvent) {
      const bar = U.el('div', { class: 'deleted-banner', 'data-testid': 'detail-deleted' });
      bar.appendChild(U.el('div', { class: 'msg', html: `<strong>${U.esc(t('recordDeleted'))}</strong><span>${U.esc(t('recordDeletedHint'))}</span>` }));
      const restore = U.el('button', { class: 'btn primary sm', text: t('restore'), 'data-testid': 'detail-restore' });
      restore.addEventListener('click', () => {
        S.restoreEvent(e.id);
        App.render();
        UI.toast(t('restoredToast', { t: e.summary }));
      });
      bar.appendChild(restore);
      scroll.appendChild(bar);
    }

    const status = U.el('div', { class: 'detail-status' });
    const cal = S.calendarById(e.calendarId);
    status.innerHTML = `<span class="chip"><span class="dot" style="background:${cal ? cal.color : 'var(--accent)'}"></span>${U.esc(cal ? cal.name : '')}</span>` +
      (isOcc ? `<span class="chip violet">${ICON('repeat', 10)}<span>${U.esc(t('recurrence'))}</span></span>` : '') +
      (e.isAllDay ? `<span class="chip">${U.esc(t('allDay'))}</span>` : '');
    scroll.appendChild(status);

    const facts = U.el('div', { class: 'detail-facts' });
    scroll.appendChild(facts);
    const when = e.isAllDay
      ? (U.sameDay(e.startDt, e.endDt)
        ? U.esc(U.fmtMonthDay(e.startDt)) + ' · ' + U.esc(t('allDay'))
        : `${U.esc(U.fmtMonthDay(e.startDt))} – ${U.esc(U.fmtMonthDay(e.endDt))} · ${U.esc(t('allDay'))}`)
      : `${U.esc(U.fmtMonthDay(e.startDt))} ${U.esc(U.fmtTimeRange(e.startDt, e.endDt))}`;
    facts.appendChild(iconFact('calendar', t('schedule'), when, roEvent ? null : UI.iconButton('edit', t('change'), () => editEvent(e), { sm: true, size: 13 })));
    if (e.location) facts.appendChild(iconFact('pin', t('location'), U.esc(e.location)));
    if (e.rrule) {
      const rec = { freq: e.rrule.freq, interval: e.rrule.interval, byday: e.rrule.byday };
      facts.appendChild(iconFact('repeat', t('seriesRule'), U.esc(UI.ruleSummary(rec)) + (e.rrule.until ? ` · ${U.esc(t('until'))} ${U.esc(U.fmtMonthDay(e.rrule.until))}` : ''),
        roEvent ? null : UI.iconButton('edit', t('edit'), () => editEvent(e), { sm: true, size: 13 })));
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
          row.addEventListener('click', () => App.openRecord('event', e.id, occ.startDt.getTime()));
          box.appendChild(row);
        }
      }
      sec.appendChild(box);
      scroll.appendChild(sec);
    }

    const actions = U.el('div', { class: 'detail-actions' });
    if (roEvent) { root.appendChild(actions); return root; }
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

  const editEvent = (e) => window.EventOps.editEvent(e);
  const deleteEvent = (e) => window.EventOps.deleteEvent(e);

  function renderDetail(params) {
    if (params.type === 'event') return eventDetail(params.id, params.occurrence);
    const todo = S.todoById(params.id);
    // A record that does not exist is an error page. A record in the Trash is
    // not: it opens with its deleted banner and a restore, and with nothing on
    // the page able to write to it.
    if (!todo) {
      return UI.page({
        title: t('errorTitle'),
        onBack: () => App.back(),
        build(content) {
          content.appendChild(UI.emptyState('alert', t('errorTitle'), t('errorBody'), [{ label: t('back'), primary: true, action: () => App.back() }]));
        },
      });
    }
    // The Todo list and Today open a record for a specific day; a recurring
    // record completed from that detail must resolve that day, not today.
    return todoDetail(todo, params.day ? new Date(params.day) : null);
  }

  App.defineView('detail', renderDetail);
  window.__detail = { todoDetail, eventDetail };
})();
