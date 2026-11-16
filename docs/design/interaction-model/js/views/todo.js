/* To-dos: day / inbox / all views, quick add, selection, reorder, swipe. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  const view = () => S.state.todosView;
  const multi = { active: false, ids: new Set() };

  function setView(next) {
    S.state.todosView = next;
    multi.active = false;
    multi.ids.clear();
    // Browsing a day here is the same act as tapping a calendar day, so both
    // surfaces move together (CORE_UX_SPEC 16.1).
    if (next.kind === 'day' && next.day) S.state.browseDate = U.startOfDay(next.day);
    App.render();
  }

  function tagMatches(todo) {
    // One filter model, three axes: calendar, tag (OR within tags) and priority.
    // Hide-completed stays a display switch, not a filter condition.
    if (S.state.filterCalendarId && todo.calendarId !== S.state.filterCalendarId) return false;
    if (S.state.filterPriority !== null && S.state.filterPriority !== undefined && todo.priority !== S.state.filterPriority) return false;
    const sel = S.state.selectedTagIds;
    if (!sel.length) return true;
    return todo.tagIds.some((id) => sel.includes(id));
  }

  function activeFilterCount() {
    return (S.state.filterCalendarId ? 1 : 0)
      + (S.state.filterPriority !== null && S.state.filterPriority !== undefined ? 1 : 0)
      + S.state.selectedTagIds.length;
  }

  function openTodo(todo, day) {
    App.openRecord('todo', todo.id, null, day);
  }

  function todoTile(todo, opts) {
    const o = opts || {};
    const wrap = U.el('div', { class: 'swipe-wrap', 'data-testid': 'todo-tile' });
    wrap.dataset.id = String(todo.id);
    const bg = U.el('div', { class: 'swipe-bg' });
    bg.innerHTML = `<span class="left">${ICON('check', 14)} ${U.esc(t('done'))}</span><span class="right">${U.esc(t('delete'))} ${ICON('trash', 14)}</span>`;
    wrap.appendChild(bg);

    const rowNode = U.el('div', { class: 'todo-row' });
    rowNode.dataset.id = String(todo.id);
    if (multi.active) {
      const box = U.el('button', {
        class: 'selbox' + (multi.ids.has(todo.id) ? ' on' : ''),
        role: 'checkbox', 'aria-checked': multi.ids.has(todo.id) ? 'true' : 'false',
        'aria-label': todo.summary,
      });
      box.innerHTML = ICON('check', 12);
      box.addEventListener('click', (e) => {
        e.stopPropagation();
        if (multi.ids.has(todo.id)) multi.ids.delete(todo.id); else multi.ids.add(todo.id);
        App.render();
      });
      rowNode.appendChild(box);
    } else {
      const grab = U.el('span', { class: 'grab' + (o.alwaysHandle ? ' always' : ''), html: ICON('grip', 15), title: t('dragHint') });
      rowNode.appendChild(grab);
      if (o.ordinal !== undefined && o.ordinal !== null) {
        rowNode.appendChild(U.el('span', { class: 'ordinal', text: String(o.ordinal + 1) }));
      }
      rowNode.appendChild(UI.checkbox(o.done, () => toggle(todo, o), t('markComplete')));
    }

    const main = U.el('div', { class: 'main' });
    main.appendChild(U.el('div', { class: 'row-title' + (o.done ? ' done' : ''), text: todo.summary }));
    const meta = U.el('div', { class: 'row-meta' });
    const bits = [];
    if (todo.dueDate) bits.push(UI.deadlineMeta(todo, U.now()));
    bits.push(UI.allocMeta(todo));
    if (todo.recurrence) bits.push(UI.repeatMeta(todo));
    bits.push(UI.priorityDot(todo.priority));
    bits.push(UI.tagChips(todo.tagIds, 2));
    if (todo.parentId) bits.push(`<span>${ICON('list', 10)} ${U.esc(t('subtasks'))}</span>`);
    meta.innerHTML = bits.filter(Boolean).join('');
    main.appendChild(meta);
    rowNode.appendChild(main);

    const actions = U.el('div', { class: 'actions' });
    if (!multi.active) {
      const rowOcc = todo.recurrence
        ? (o.day && S.matchesRule(todo, o.day)
          ? S.occurrenceIdFor(todo, o.day)
          : (S.matchesRule(todo, U.startOfDay(U.now())) ? S.occurrenceIdFor(todo, U.startOfDay(U.now())) : null))
        : null;
      const undo = o.done ? rowUndoFor(todo, rowOcc) : null;
      if (undo) actions.appendChild(undo);
      const moreBtn = UI.iconButton('more' in ICON_NAMES ? 'more' : 'sliders', t('more'), (e) => {
        e.stopPropagation();
        openRowMenu(moreBtn, todo);
      }, { sm: true, size: 15 });
      actions.appendChild(moreBtn);
    }
    rowNode.appendChild(actions);

    rowNode.tabIndex = 0;
    rowNode.dataset.testid = 'todo-row';
    rowNode.setAttribute('aria-label', todo.summary);
    rowNode.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();
      if (multi.active) {
        if (multi.ids.has(todo.id)) multi.ids.delete(todo.id); else multi.ids.add(todo.id);
        App.render();
        return;
      }
      openTodo(todo, o.day);
    });
    rowNode.addEventListener('click', () => {
      if (multi.active) {
        if (multi.ids.has(todo.id)) multi.ids.delete(todo.id); else multi.ids.add(todo.id);
        App.render();
        return;
      }
      openTodo(todo, o.day);
    });
    rowNode.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      openRowMenu(rowNode, todo);
    });
    // The row the pane is showing reads as selected, so the list still says
    // which record is on the right.
    if (!U.isNarrow() && U.isSplit() && S.state.paneSelection && S.state.paneSelection.type === 'todo'
        && String(S.state.paneSelection.id) === String(todo.id)) {
      rowNode.classList.add('md-selected');
      wrap.classList.add('md-selected');
    }
    if (!multi.active && !o.done) attachReorder(wrap, rowNode, todo);
    attachSwipe(wrap, rowNode, todo, o);
    wrap.appendChild(rowNode);
    return wrap;
  }

  function attachReorder(wrap, rowNode, todo) {
    const handle = rowNode.querySelector('.grab');
    if (!handle) return;
    handle.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      e.stopPropagation();
      const list = wrap.parentElement;
      if (!list) return;
      const rows = Array.from(list.querySelectorAll('.swipe-wrap'));
      const index = rows.indexOf(wrap);
      if (index < 0 || rows.length < 2) return;
      const startY = e.clientY;
      let target = index;
      rowNode.classList.add('dragging');
      rowNode.style.position = 'relative';
      rowNode.style.zIndex = '5';
      rowNode.style.boxShadow = 'var(--shadow-1)';
      const heights = rows.map((r) => r.getBoundingClientRect().height);
      function offset(i) {
        let sum = 0;
        for (let k = 0; k < i; k++) sum += heights[k];
        return sum;
      }
      function move(ev) {
        const dy = ev.clientY - startY;
        rowNode.style.transform = `translateY(${dy}px)`;
        const center = offset(index) + heights[index] / 2 + dy;
        target = index;
        for (let i = 0; i < rows.length; i++) {
          if (i === index) continue;
          const mid = offset(i) + heights[i] / 2;
          if (i > index && center > mid) target = Math.max(target, i);
          if (i < index && center < mid) target = Math.min(target, i);
        }
      }
      function up(ev) {
        document.removeEventListener('pointermove', move);
        document.removeEventListener('pointerup', up);
        document.removeEventListener('pointercancel', up);
        rowNode.classList.remove('dragging');
        rowNode.style.transform = '';
        rowNode.style.zIndex = '';
        rowNode.style.boxShadow = '';
        if (ev && ev.type === 'pointercancel') return;
        if (target !== index) {
          const ids = rows.map((r) => Number(r.dataset.id));
          const moved = ids.splice(index, 1)[0];
          ids.splice(target, 0, moved);
          S.reorderTodos(ids);
          App.render();
          UI.toast(t('reorderedToast'), { duration: 1800 });
        }
      }
      document.addEventListener('pointermove', move);
      document.addEventListener('pointerup', up);
      document.addEventListener('pointercancel', up);
    });
  }

  function rowUndoFor(todo, occurrenceId) {
    const u = S.state.inlineUndo;
    if (!u || u.key !== todo.id + ':' + (occurrenceId || '') || u.until <= Date.now()) return null;
    const b = U.el('button', { class: 'row-undo', text: t('undo'), 'data-testid': 'todo-undo' });
    b.addEventListener('click', (e) => {
      e.stopPropagation();
      S.state.inlineUndo = null;
      window.TodoOps.complete(todo, occurrenceId);
      App.render();
    });
    return b;
  }

  function toggle(todo, opts) {
    // On a browsed day the row is that day's occurrence, not today's. Resolving
    // "today" here ticked the wrong instance and left the visible row untouched.
    if (todo.recurrence) {
      const day = (opts && opts.day) || U.startOfDay(U.now());
      if (!S.matchesRule(todo, day)) {
        UI.toast(t('recurrenceNeedsOccurrence'), { warn: true });
        return;
      }
      window.TodoOps.complete(todo, S.occurrenceIdFor(todo, day));
      return;
    }
    window.TodoOps.complete(todo);
  }

  function openRowMenu(anchor, todo) {
    const items = [
      { icon: 'edit', text: t('edit'), action: () => App.openComposer('todo', { mode: 'edit', id: todo.id }) },
      { icon: 'clockPlus', text: t('allocateNow'), action: () => scheduleNow(todo) },
      { icon: 'calendarPlus', text: t('deadline'), action: () => App.openComposer('todo', { mode: 'edit', id: todo.id, focus: 'deadline' }) },
      { icon: 'tag', text: t('tags'), action: () => tagPicker(todo) },
      { sep: true },
    ];
    if (todo.parentId == null) {
      items.push({ icon: 'list', text: t('addSubtask'), action: () => App.openComposer('todo', { parentId: todo.id }) });
    }
    if (todo.recurrence) {
      items.push({ icon: 'repeat', text: t('editSeries'), action: () => App.openComposer('todo', { mode: 'edit', id: todo.id, focus: 'repeat' }) });
    }
    items.push({ icon: 'check', text: t('selectMode'), action: () => { multi.active = true; multi.ids.clear(); App.render(); } });
    items.push({ sep: true });
    items.push({ icon: 'trash', text: t('moveToTrash'), danger: true, action: () => deleteTodo(todo) });
    UI.menu(anchor, items);
  }

  function deleteTodo(todo) {
    S.softDeleteTodo(todo.id);
    App.render();
    UI.toast(t('deletedToast', { t: todo.summary }), {
      undo: () => { S.restoreTodo(todo.id); App.render(); },
    });
  }

  function scheduleNow(todo) {
    const now = U.now();
    const start = U.addMinutes(now, 60 - now.getMinutes());
    App.openComposer('todo', { mode: 'edit', id: todo.id, focus: 'schedule', scheduleStart: start, scheduleEnd: U.addMinutes(start, 60) });
  }

  function tagPicker(todo) {
    const body = (host, close) => {
      const list = U.el('div', { class: 'applist' });
      S.state.tags.forEach((tag) => {
        const on = todo.tagIds.includes(tag.id);
        const r = U.el('button', { class: 'list-row' });
        r.innerHTML = `<span class="dot" style="background:${tag.color}"></span><span class="main"><span class="t">${U.esc(tag.name)}</span></span><span class="selbox${on ? ' on' : ''}" style="width:18px;height:18px;border-radius:5px;border:1.5px solid var(--line);display:grid;place-items:center;${on ? 'background:var(--accent);border-color:var(--accent);color:#fff' : 'color:transparent'}">${ICON('check', 11)}</span>`;
        r.addEventListener('click', () => {
          const next = on ? todo.tagIds.filter((x) => x !== tag.id) : todo.tagIds.concat(tag.id);
          S.updateTodo(todo.id, { tagIds: next });
          close(null);
          App.render();
        });
        list.appendChild(r);
      });
      host.appendChild(list);
      const add = U.el('button', { class: 'btn ghost', text: t('newTag') });
      add.style.marginTop = '10px';
      add.addEventListener('click', () => { close(null); S.navigate('tags', {}); });
      host.appendChild(add);
    };
    UI.modal({ title: t('tags'), body });
  }

  function attachSwipe(wrap, rowNode, todo, opts) {
    let startX = 0, startY = 0, dx = 0, active = false, decided = false, horizontal = false;
    rowNode.addEventListener('pointerdown', (e) => {
      if (e.pointerType === 'mouse') return;
      if (e.target.closest('button') && !e.target.closest('.checkbox')) return;
      startX = e.clientX; startY = e.clientY; active = true; decided = false; horizontal = false; dx = 0;
      // Keep the stream on this row: without capture the browser retargets to
      // the scroller as soon as the finger crosses out of the row box.
      if (rowNode.setPointerCapture) {
        try { rowNode.setPointerCapture(e.pointerId); } catch (_) { /* synthetic pointer */ }
      }
    });
    rowNode.addEventListener('pointermove', (e) => {
      if (!active) return;
      const mx = e.clientX - startX, my = e.clientY - startY;
      if (!decided) {
        if (Math.abs(mx) > 10 || Math.abs(my) > 10) {
          decided = true;
          horizontal = Math.abs(mx) > Math.abs(my);
        } else return;
      }
      if (!horizontal) return;
      dx = U.clamp(mx, -110, 110);
      rowNode.style.transition = 'none';
      rowNode.style.transform = `translateX(${dx}px)`;
    });
    const finish = (commit) => {
      if (!active) return;
      active = false;
      rowNode.style.transition = '';
      if (commit && dx <= -80) {
        rowNode.style.transform = 'translateX(-84px)';
        setTimeout(() => {
          deleteTodo(todo);
        }, 120);
      } else if (commit && dx >= 80) {
        rowNode.style.transform = '';
        toggle(todo, opts);
      } else {
        rowNode.style.transform = '';
      }
      dx = 0;
    };
    rowNode.addEventListener('pointerup', () => finish(true));
    // A pointercancel means the browser took the gesture (a scroll, a system
    // gesture). Committing on it deleted rows the user never finished swiping.
    rowNode.addEventListener('pointercancel', () => finish(false));
  }

  function quickAdd(contextLabel, onAdd) {
    const box = U.el('div', { class: 'todo-quick' });
    box.innerHTML = ICON('plus', 15);
    const input = U.el('input', { placeholder: t('quickAddPlaceholder'), 'aria-label': t('quickAddPlaceholder'), 'data-testid': 'todo-quick-add' });
    box.appendChild(input);
    if (contextLabel) {
      const chip = U.el('span', { class: 'chip accent context-chip', text: contextLabel });
      box.appendChild(chip);
    }
    const hint = U.el('span', { class: 'tiny muted', text: t('quickAddHint') });
    hint.style.flex = 'none';
    box.appendChild(hint);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && input.value.trim()) {
        onAdd(input.value.trim());
        input.value = '';
      }
      if (e.key === 'Escape') input.blur();
    });
    return { box, input };
  }

  function selectBar() {
    const bar = U.el('div', { class: 'selectbar' });
    bar.appendChild(U.el('span', { text: t('selectedCount', { n: multi.ids.size }) }));
    bar.appendChild(U.el('span', { class: 'spacer' }));
    const all = U.el('button', { class: 'btn ghost sm', text: t('selectAll') });
    all.addEventListener('click', () => {
      const list = currentList().map((x) => x.id);
      if (multi.ids.size === list.length) multi.ids.clear();
      else list.forEach((id) => multi.ids.add(id));
      App.render();
    });
    bar.appendChild(all);
    const done = U.el('button', { class: 'btn ghost sm', text: t('completeSelected') });
    done.disabled = multi.ids.size === 0;
    done.addEventListener('click', () => {
      const ids = Array.from(multi.ids);
      // Route through TodoOps so a repeating row resolves its occurrence the
      // same way the single-row tick does; calling completeTodo directly wrote
      // nothing for a series and still reported success.
      const written = [];
      const skipped = [];
      const v = view();
      const contextDay = v.kind === 'day' ? v.day : null;
      ids.forEach((id) => {
        const todo = S.todoById(id);
        if (!todo || !S.isOpen(todo)) return;
        // Batch completion follows the day being browsed, exactly like the
        // single-row tick; resolving today here ticked an off-screen instance.
        let occ = null;
        if (todo.recurrence) {
          if (contextDay && S.matchesRule(todo, contextDay)) occ = S.occurrenceIdFor(todo, contextDay);
          else if (!contextDay) occ = window.TodoOps.todayOccurrenceId(todo);
        }
        if (todo.recurrence && !occ) { skipped.push(todo.summary); return; }
        // Batch 完成 must never flip a finished row back open. For a series the
        // parent stays OPEN after one occurrence is ticked, so the row is still
        // on screen and would otherwise be toggled the wrong way.
        if (window.TodoOps.isDone(todo, occ)) { skipped.push(todo.summary); return; }
        const result = S.completeTodo(id, occ ? { occurrenceId: occ } : undefined);
        if (result) written.push({ id, occ });
      });
      multi.ids.clear();
      multi.active = false;
      App.render();
      if (!written.length) {
        UI.toast(t('batchNothingToComplete', { n: skipped.length }), { warn: true });
        return;
      }
      UI.toast(t('selectedCount', { n: written.length }) + ' · ' + t('done'), {
        undo: () => {
          written.forEach((w) => S.completeTodo(w.id, w.occ ? { occurrenceId: w.occ } : undefined));
          App.render();
        },
      });
      if (skipped.length) UI.toast(t('batchSkippedRecurring', { n: skipped.length }), { warn: true });
    });
    bar.appendChild(done);
    const del = U.el('button', { class: 'btn danger-ghost sm', text: t('deleteSelected') });
    del.disabled = multi.ids.size === 0;
    del.addEventListener('click', async () => {
      const ok = await UI.confirm({ title: t('deleteSelected'), message: t('deleteConfirm'), danger: true, confirmText: t('delete') });
      if (!ok) return;
      const ids = Array.from(multi.ids);
      ids.forEach((id) => S.softDeleteTodo(id));
      multi.ids.clear();
      multi.active = false;
      App.render();
      UI.toast(t('selectedCount', { n: ids.length }) + ' · ' + t('deletedToast', { t: '' }).replace('「」', ''), {
        undo: () => { ids.forEach((id) => S.restoreTodo(id)); App.render(); },
      });
    });
    bar.appendChild(del);
    const exit = U.el('button', { class: 'btn subtle sm', text: t('exitSelect') });
    exit.addEventListener('click', () => { multi.active = false; multi.ids.clear(); App.render(); });
    bar.appendChild(exit);
    return bar;
  }

  function visibleForPane() {
    const v = view();
    const done = S.state.hideCompleted ? [] : S.completedTodos();
    if (v.kind === 'day') {
      const g = S.todosForDay(v.day);
      return new Set(g.overdue.concat(g.dated, S.state.hideCompleted ? [] : g.done).filter(tagMatches).map((t) => t.id));
    }
    if (v.kind === 'inbox') {
      const extra = done.filter((t) => !t.dueDate && !t.parentId);
      return new Set(S.inboxTodos().concat(extra).filter(tagMatches).map((t) => t.id));
    }
    return new Set(S.pendingTodos().concat(done).filter(tagMatches).map((t) => t.id));
  }

  function currentList() {
    const v = view();
    if (v.kind === 'all') return S.pendingTodos().filter(tagMatches);
    if (v.kind === 'inbox') return S.inboxTodos().filter(tagMatches);
    const groups = S.todosForDay(v.day);
    return groups.overdue.concat(groups.dated).filter(tagMatches);
  }

  function weekStrip(selected) {
    const today = U.startOfDay(U.now());
    const ws = U.startOfWeek(selected || today, S.state.weekStartsOn);
    const strip = U.el('div', { class: 'weekstrip' });
    const prev = U.el('button', { class: 'ws-arrow', 'aria-label': t('prevWeek'), html: ICON('chevronLeft', 15) });
    prev.addEventListener('click', () => setView({ kind: 'day', day: U.addDays(selected || today, -7) }));
    strip.appendChild(prev);
    const days = U.el('div', { class: 'ws-days' });
    for (let i = 0; i < 7; i++) {
      const d = U.addDays(ws, i);
      const groups = S.todosForDay(d);
      const has = groups.dated.length + groups.overdue.length > 0;
      const b = U.el('button', {
        class: 'ws-day' + (U.sameDay(d, today) ? ' today' : '') + (U.sameDay(d, selected) ? ' on' : '') + (has ? ' has' : ''),
        'aria-label': `${U.fmtMonthDay(d)} ${U.fmtWeekdayLong(d)}`,
        'aria-pressed': U.sameDay(d, selected) ? 'true' : 'false',
      });
      b.innerHTML = `<span class="dow">${U.esc(U.fmtWeekdayShort(d))}</span><span class="num">${d.getDate()}</span><span class="dot"></span>`;
      b.addEventListener('click', () => setView({ kind: 'day', day: U.startOfDay(d) }));
      days.appendChild(b);
    }
    strip.appendChild(days);
    const next = U.el('button', { class: 'ws-arrow', 'aria-label': t('nextWeek'), html: ICON('chevronRight', 15) });
    next.addEventListener('click', () => setView({ kind: 'day', day: U.addDays(selected || today, 7) }));
    strip.appendChild(next);
    return strip;
  }

  // A week strip alone means reaching a date three months out is twelve taps.
  // The subtitle is the shortcut: tap it, pick a month, pick a day.
  function datePicker(current) {
    const cur = U.startOfDay(current || U.now());
    UI.sheet({
      title: t('jumpToDate'),
      body(host, close) {
        let shown = new Date(cur.getFullYear(), cur.getMonth(), 1);
        const head = U.el('div', { class: 'picker-head' });
        const prevY = U.el('button', { class: 'chip-btn', text: '«', 'aria-label': t('prevYear') });
        const prevM = U.el('button', { class: 'chip-btn', text: '‹', 'aria-label': t('prevMonth') });
        const label = U.el('span', { class: 'picker-month' });
        const nextM = U.el('button', { class: 'chip-btn', text: '›', 'aria-label': t('nextMonth') });
        const nextY = U.el('button', { class: 'chip-btn', text: '»', 'aria-label': t('nextYear') });
        [prevY, prevM, label, nextM, nextY].forEach((n) => head.appendChild(n));
        host.appendChild(head);
        const direct = U.el('div', { class: 'input-row', style: 'margin-bottom:8px' });
        const jumpDate = U.el('input', { class: 'input', type: 'date', value: U.toInputDate(cur), 'aria-label': t('jumpToDate') });
        jumpDate.dataset.testid = 'picker-jump-date';
        jumpDate.addEventListener('change', () => {
          const d = U.fromInputDate(jumpDate.value);
          if (!d) return;
          close(null);
          setView({ kind: 'day', day: U.startOfDay(d) });
        });
        direct.appendChild(jumpDate);
        host.appendChild(direct);
        const grid = U.el('div', { class: 'picker-grid' });
        host.appendChild(grid);
        const jump = U.el('button', { class: 'btn ghost sm', 'data-testid': 'picker-today', text: t('today') });
        jump.addEventListener('click', () => { close(null); setView({ kind: 'day', day: U.startOfDay(U.now()) }); });
        host.appendChild(jump);

        function draw() {
          label.textContent = S.state.lang === 'zh'
            ? `${shown.getFullYear()} 年 ${shown.getMonth() + 1} 月`
            : U.fmtMonthYear(shown);
          grid.innerHTML = '';
          I18N.t('weekdaysShort').forEach((w) => grid.appendChild(U.el('span', { class: 'picker-dow', text: w })));
          const first = U.startOfWeek(shown, S.state.weekStartsOn);
          for (let i = 0; i < 42; i += 1) {
            const d = U.addDays(first, i);
            const out = d.getMonth() !== shown.getMonth();
            const b = U.el('button', {
              class: 'picker-day' + (out ? ' out' : '') + (U.sameDay(d, cur) ? ' on' : '') + (U.sameDay(d, U.now()) ? ' today' : ''),
              text: String(d.getDate()),
              'aria-label': U.fmtMonthDay(d),
            });
            b.dataset.testid = 'picker-day';
            b.addEventListener('click', () => { close(null); setView({ kind: 'day', day: U.startOfDay(d) }); });
            grid.appendChild(b);
          }
        }
        prevY.addEventListener('click', () => { shown = new Date(shown.getFullYear() - 1, shown.getMonth(), 1); draw(); });
        nextY.addEventListener('click', () => { shown = new Date(shown.getFullYear() + 1, shown.getMonth(), 1); draw(); });
        prevM.addEventListener('click', () => { shown = new Date(shown.getFullYear(), shown.getMonth() - 1, 1); draw(); });
        nextM.addEventListener('click', () => { shown = new Date(shown.getFullYear(), shown.getMonth() + 1, 1); draw(); });
        draw();
      },
    });
  }

  // Filtering has three axes in v0.34.0 (calendar, tag, priority) plus the
  // display switch for completed work. A tag-only chip strip looked like the
  // whole feature and silently hid the other two.
  function filterSheet() {
    let cal = S.state.filterCalendarId || null;
    let prio = S.state.filterPriority === undefined ? null : S.state.filterPriority;
    let tags = S.state.selectedTagIds.slice();
    let hide = !!S.state.hideCompleted;
    UI.sheet({
      title: t('filter'),
      body(host, close) {
        function draw() {
          host.innerHTML = '';
          const box = U.el('div', { class: 'picker', 'data-testid': 'filter-sheet' });
          host.appendChild(box);

          function groupLabel(text) {
            box.appendChild(U.el('div', { class: 'field-label', text }));
          }
          function chipRow() { const r = U.el('div', { class: 'chip-row' }); box.appendChild(r); return r; }
          function chip(parent, label, on, onClick, testid) {
            const b = U.el('button', { class: 'chip-btn' + (on ? ' on' : ''), text: label });
            if (testid) b.dataset.testid = testid;
            b.setAttribute('aria-pressed', on ? 'true' : 'false');
            b.addEventListener('click', onClick);
            parent.appendChild(b);
            return b;
          }

          groupLabel(t('filterCalendar'));
          const calRow = chipRow();
          chip(calRow, t('filterAny'), !cal, () => { cal = null; draw(); }, 'filter-any-calendar');
          S.state.calendars.forEach((c) => {
            const b = chip(calRow, c.name, cal === c.id, () => { cal = c.id; draw(); }, 'filter-calendar-' + c.id);
            b.innerHTML = `<span class="dot" style="background:${c.color}"></span>${U.esc(c.name)}`;
          });

          groupLabel(t('filterPriority'));
          const prioRow = chipRow();
          chip(prioRow, t('filterAny'), prio === null, () => { prio = null; draw(); }, 'filter-any-priority');
          [[0, t('noPriority')], [1, t('low')], [5, t('medium')], [9, t('high')]].forEach(([v, label]) => {
            chip(prioRow, label, prio === v, () => { prio = v; draw(); }, 'filter-priority-' + v);
          });

          groupLabel(t('filterTag'));
          const tagRow = chipRow();
          if (!S.state.tags.length) tagRow.appendChild(U.el('span', { class: 'tiny muted', text: t('none') }));
          S.state.tags.forEach((tag) => {
            const on = tags.includes(tag.id);
            const b = chip(tagRow, tag.name, on, () => {
              tags = on ? tags.filter((x) => x !== tag.id) : tags.concat(tag.id);
              draw();
            }, 'filter-tag-' + tag.id);
            b.innerHTML = `<span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}`;
          });

          const swRow = U.el('div', { class: 'setting-row', style: 'border:0;padding:8px 0' });
          const sw = U.el('button', { class: 'switch' + (hide ? ' on' : ''), role: 'switch', 'aria-checked': hide ? 'true' : 'false', 'aria-label': t('hideCompleted'), 'data-testid': 'filter-hide-done' });
          sw.addEventListener('click', () => { hide = !hide; draw(); });
          swRow.innerHTML = `<span class="body"><span class="t">${U.esc(t('hideCompleted'))}</span><span class="s">${U.esc(t('hideCompletedDesc'))}</span></span>`;
          swRow.appendChild(sw);
          box.appendChild(swRow);

          const acts = U.el('div', { class: 'input-row' });
          const clear = U.el('button', { class: 'btn ghost', text: t('filterClear'), 'data-testid': 'filter-clear' });
          clear.addEventListener('click', () => {
            cal = null; prio = null; tags = []; hide = false;
            S.state.filterCalendarId = null; S.state.filterPriority = null;
            S.state.selectedTagIds = []; S.state.hideCompleted = false;
            close(null); App.render();
          });
          const apply = U.el('button', { class: 'btn primary', text: t('confirm'), 'data-testid': 'filter-apply' });
          apply.addEventListener('click', () => {
            S.state.filterCalendarId = cal;
            S.state.filterPriority = prio;
            S.state.selectedTagIds = tags;
            S.state.hideCompleted = hide;
            S.savePrefs();
            close(null);
            App.render();
          });
          acts.appendChild(clear); acts.appendChild(apply);
          box.appendChild(acts);
        }
        draw();
      },
    });
  }

  function renderTodos() {
    const v = view();
    const today = U.startOfDay(U.now());
    const day = v.kind === 'day' ? v.day : null;
    // A filter or an edit can move the selected record out of the list. Keeping
    // its detail in the pane would show a record the list no longer contains.
    if (S.state.paneSelection && S.state.paneSelection.type === 'todo') {
      const visible = visibleForPane();
      if (!visible.has(Number(S.state.paneSelection.id))) {
        // Completion removes a (recurring) instance from the visible list but
        // the record is still what the user is looking at. Keep its pane; only
        // a filter/date change that hides an open record retires the selection.
        const rec = S.todoById(S.state.paneSelection.id);
        const sel = S.state.paneSelection;
        const d = sel.day ? new Date(sel.day) : U.startOfDay(U.now());
        const occDone = rec && rec.recurrence && S.matchesRule(rec, d)
          && S.isOccurrenceDone(rec, S.occurrenceIdFor(rec, d));
        if (!(rec && !rec.deletedAt && (S.isDone(rec) || occDone))) S.state.paneSelection = null;
      }
    }
    // Create sits in the header on every platform (CORE_UX_SPEC 1.2: no FAB).
    // On a phone it drops the label; the action itself never moves.
    const actions = [];
    const add = U.el('button', { class: 'btn primary', 'data-testid': 'todos-create' });
    add.innerHTML = ICON('plus', 14) + `<span class="label">${U.esc(t('newTodo'))}</span>`;
    add.setAttribute('aria-label', t('newTodo'));
    add.addEventListener('click', () => App.openComposer('todo', day ? { dueDate: day } : {}));
    actions.push(add);
    const tagsBtn = UI.iconButton('tag', t('navTags'), () => App.go('tags'));
    const trashBtn = UI.iconButton('trash', t('navTrash'), () => App.go('trash'));
    const filterBtn = UI.iconButton('filter', t('filter'), (ev) => {
      ev.stopPropagation();
      filterSheet();
    }, { testid: 'todos-filter' });
    const count = activeFilterCount();
    if (count) {
      filterBtn.classList.add('active');
      filterBtn.innerHTML += `<span class="filter-count">${count}</span>`;
    }
    actions.push(filterBtn, tagsBtn, trashBtn);

    // In a day view the subtitle is the only control that can reach a far date,
    // so it is a button, not decoration.
    let subtitleNode = null;
    if (day) {
      subtitleNode = U.el('button', { class: 'page-sub-btn', 'data-testid': 'todos-date-picker' });
      const yearPart = day.getFullYear() === new Date().getFullYear() ? '' : day.getFullYear() + (S.state.lang === 'zh' ? '年' : ' ');
      subtitleNode.innerHTML = `${U.esc(yearPart + U.fmtMonthDay(day))} · ${U.esc(U.fmtWeekdayLong(day))}` + ICON('chevronDown', 12);
      subtitleNode.addEventListener('click', (ev) => { ev.stopPropagation(); datePicker(day); });
    }

    const page = UI.page({
      title: t('pageTodos'),
      subtitle: day ? subtitleNode : (v.kind === 'inbox' ? t('inbox') : t('allTasks')),
      actions,
      build(content) {
        const panes = buildList(v, day, today);
        const split = !U.isNarrow() && U.isSplit();
        if (!split) {
          content.appendChild(panes);
          return;
        }
        // Master-detail: the list never leaves. The right pane is a selection,
        // so closing it puts the user back exactly where they were in the list.
        const wrap = U.el('div', { class: 'todos-masterdetail', 'data-testid': 'todos-masterdetail' });
        const left = U.el('div', { class: 'md-list' });
        left.appendChild(panes);
        wrap.appendChild(left);
        const right = U.el('div', { class: 'md-detail', 'data-testid': 'detail-pane' });
        wrap.appendChild(right);
        const sel = S.state.paneSelection;
        if (sel) right.appendChild(buildPane(sel));
        else right.appendChild(U.el('div', { class: 'md-empty', text: t('paneEmpty') }));
        content.appendChild(wrap);
      },
    });

    return page;
  }

  // The scrolling body of the Todo destination: chips, week strip, tag filter,
  // quick add and the list itself. Kept separate from the page frame so the
  // master-detail layout can put it in the left column verbatim.
  function buildList(v, day, today) {
    const root = U.el('div', { class: 'todo-body' });
    const toolbar = U.el('div', { class: 'todo-toolbar' });
    const chips = U.el('div', { class: 'chips-scroll' });
    [
      { label: t('allTasks'), on: v.kind === 'all', act: () => setView({ kind: 'all', day: null }) },
      { label: t('inbox'), on: v.kind === 'inbox', act: () => setView({ kind: 'inbox', day: null }) },
      { label: t('today'), on: v.kind === 'day' && U.sameDay(v.day, today), act: () => setView({ kind: 'day', day: today }) },
    ].forEach((c) => {
      const b = U.el('button', { class: 'chip-btn' + (c.on ? ' on' : ''), text: c.label, 'aria-pressed': c.on ? 'true' : 'false' });
      b.addEventListener('click', c.act);
      chips.appendChild(b);
    });
    toolbar.appendChild(chips);
    toolbar.appendChild(U.el('span', { class: 'spacer' }));
    const selBtn = U.el('button', { class: 'chip-btn' + (multi.active ? ' on' : ''), text: multi.active ? t('exitSelect') : t('selectMode') });
    selBtn.addEventListener('click', () => { multi.active = !multi.active; multi.ids.clear(); App.render(); });
    toolbar.appendChild(selBtn);
    root.appendChild(toolbar);

    if (v.kind === 'day') root.appendChild(weekStrip(day));

    if (S.state.tags.length || activeFilterCount()) {
      // The sheet is where filtering happens; this row only reports what is on
      // and offers one-tap clearing, so the list never hides items silently.
      const tagBar = U.el('div', { class: 'chips-scroll', 'data-testid': 'active-filters' });
      tagBar.style.paddingBottom = '6px';
      if (S.state.filterCalendarId) {
        const cal = S.calendarById(S.state.filterCalendarId);
        const b = U.el('button', { class: 'chip-btn on' });
        b.innerHTML = `<span class="dot" style="background:${cal ? cal.color : 'var(--accent)'}"></span>${U.esc(cal ? cal.name : '')}`;
        b.addEventListener('click', () => { S.state.filterCalendarId = null; App.render(); });
        tagBar.appendChild(b);
      }
      if (S.state.filterPriority !== null && S.state.filterPriority !== undefined) {
        const labels = { 0: t('noPriority'), 1: t('low'), 5: t('medium'), 9: t('high') };
        const b = U.el('button', { class: 'chip-btn on', text: labels[S.state.filterPriority] || '' });
        b.addEventListener('click', () => { S.state.filterPriority = null; App.render(); });
        tagBar.appendChild(b);
      }
      S.state.selectedTagIds.forEach((id) => {
        const tag = S.tagById(id);
        if (!tag) return;
        const b = U.el('button', { class: 'chip-btn on' });
        b.innerHTML = `<span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}`;
        b.addEventListener('click', () => {
          S.state.selectedTagIds = S.state.selectedTagIds.filter((x) => x !== id);
          App.render();
        });
        tagBar.appendChild(b);
      });
      if (activeFilterCount()) {
        const clear = U.el('button', { class: 'chip-btn', text: t('filterClear') });
        clear.addEventListener('click', () => {
          S.state.filterCalendarId = null;
          S.state.filterPriority = null;
          S.state.selectedTagIds = [];
          App.render();
        });
        tagBar.appendChild(clear);
      } else {
        tagBar.appendChild(U.el('span', { class: 'tiny muted', text: t('filter') }));
      }
      root.appendChild(tagBar);
    }

    if (multi.active) root.appendChild(selectBar());

    if (v.kind === 'day') {
      const plan = U.el('button', { class: 'plan-bar', 'data-testid': 'plan-day' });
      plan.innerHTML = `${ICON('clockPlus', 15)}<span>${U.esc(t('planThisDay'))}</span><span class="tiny muted">${U.esc(t('planThisDayHint'))}</span>`;
      plan.addEventListener('click', () => App.openComposer('todo', { planDate: day, focus: 'title' }));
      root.appendChild(plan);
    }

    const add = quickAdd(v.kind === 'day' ? t('deadlinePrefix', { d: U.fmtMonthDay(day) }) : (v.kind === 'inbox' ? t('inbox') : null), (text) => {
      const todo = S.createTodo({ summary: text, dueDate: v.kind === 'day' ? U.startOfDay(day) : null });
      App.render();
      UI.toast(t('createdToast', { t: todo.summary }), {
        undo: () => { S.softDeleteTodo(todo.id); App.render(); },
      });
      const focus = U.qs('[data-testid="todo-quick-add"]');
      if (focus) focus.focus();
    });
    root.appendChild(add.box);

    const list = U.el('div', { class: 'todo-list', 'data-testid': 'todo-list' });
    root.appendChild(list);
    if (v.kind === 'day') renderDay(list, day);
    else if (v.kind === 'inbox') renderInbox(list);
    else renderAll(list);
    return root;
  }

  // The right column. Reuses the read-only detail body, and adds the two things
  // a pane needs that a page does not: a visible way to close it, and no
  // back chevron (there is nowhere to go back to).
  function buildPane(sel) {
    const host = U.el('div', { class: 'pane-body', 'data-testid': 'detail-pane-body' });

    const rec = sel.type === 'event' ? S.eventById(sel.id) : S.todoById(sel.id);
    if (!rec) {
      const head = U.el('div', { class: 'detail-head', style: 'justify-content:flex-end' });
      const btn = U.el('button', { class: 'btn ghost sm md-close', 'data-testid': 'pane-close' });
      btn.innerHTML = ICON('x', 13) + `<span>${U.esc(t('close'))}</span>`;
      btn.addEventListener('click', () => S.clearPane());
      head.appendChild(btn);
      host.appendChild(head);
      host.appendChild(UI.emptyState('alert', t('nothingHere'), t('errorBody')));
      return host;
    }
    let body;
    if (sel.type === 'event') body = window.__detail.eventDetail(sel.id, sel.occurrence);
    else body = window.__detail.todoDetail(rec, sel.day ? new Date(sel.day) : null);

    const isDetail = body && body.classList && body.classList.contains('detail');
    const head = isDetail ? body.querySelector('.detail-head') : null;
    if (head) {
      // The pane keeps the record's own controls (its More menu holds edit,
      // schedule, subtask, delete) and gains a close button beside them. A pane
      // with no visible exit strands pointer users on Escape alone.
      head.style.justifyContent = 'flex-end';
      head.querySelectorAll('.spacer').forEach((n) => n.remove());
      const btn = U.el('button', { class: 'btn ghost sm md-close', 'data-testid': 'pane-close' });
      btn.innerHTML = ICON('x', 13) + `<span>${U.esc(t('close'))}</span>`;
      btn.addEventListener('click', () => S.clearPane());
      head.appendChild(btn);
    } else {
      const close = U.el('div', { class: 'detail-head', style: 'justify-content:flex-end' });
      const btn = U.el('button', { class: 'btn ghost sm md-close', 'data-testid': 'pane-close' });
      btn.innerHTML = ICON('x', 13) + `<span>${U.esc(t('close'))}</span>`;
      btn.addEventListener('click', () => S.clearPane());
      close.appendChild(btn);
      host.appendChild(close);
    }
    host.appendChild(body);
    return host;
  }

  function renderDay(list, day) {
    const groups = S.todosForDay(day);
    const today = U.startOfDay(U.now());
    const isToday = U.sameDay(day, today);
    const overdue = groups.overdue.filter(tagMatches);
    const dated = groups.dated.filter(tagMatches);
    const done = groups.done.filter(tagMatches);
    const doneInstances = (groups.doneInstances || []).filter((x) => tagMatches(x.todo));

    if (!overdue.length && !dated.length && !done.length && !doneInstances.length) {
      list.appendChild(UI.emptyState('checkSquare', t('noPendingTodos'), t('noPendingHint'), [
        { label: t('newTodo'), primary: true, action: () => App.openComposer('todo', { dueDate: day }) },
      ]));
      return;
    }
    if (overdue.length) {
      list.appendChild(UI.sectionHead(t('overdueSection'), overdue.length, { tone: 'danger' }));
      overdue.forEach((todo) => list.appendChild(todoTile(todo, { day })));
    }
    if (dated.length) {
      list.appendChild(UI.sectionHead(isToday ? t('today') : U.fmtMonthDay(day), dated.length, { tone: 'accent' }));
      dated.forEach((todo) => list.appendChild(todoTile(todo, { day })));
    }
    if ((done.length || doneInstances.length) && !S.state.hideCompleted) {
      list.appendChild(UI.sectionHead(t('completedSection'), done.length + doneInstances.length));
      done.forEach((todo) => list.appendChild(todoTile(todo, { done: true, day })));
      // A ticked occurrence of a repeating to-do belongs here too: the series
      // stays open, but this day's instance is finished.
      doneInstances.forEach((x) => list.appendChild(todoTile(x.todo, { done: true, day })));
    }
  }

  // In the inventory views a repeating row stands for the series, but the tick
  // on that row is today's occurrence. Once today is ticked the row belongs in
  // the completed group for today, not in the open list with an empty box.
  function splitRecurring(rows) {
    const today = U.startOfDay(U.now());
    const open = [];
    const doneToday = [];
    rows.forEach((todo) => {
      if (todo.recurrence && S.matchesRule(todo, today)) {
        const occ = S.occurrenceIdFor(todo, today);
        if (S.isOccurrenceDone(todo, occ)) { doneToday.push({ todo, day: today }); return; }
      }
      open.push(todo);
    });
    return { open, doneToday };
  }

  function renderInbox(list) {
    const split = splitRecurring(S.inboxTodos().filter(tagMatches));
    const items = split.open;
    const done = S.completedTodos().filter((t) => !t.dueDate && !t.parentId).filter(tagMatches);
    const doneRows = done.length + split.doneToday.length;
    if (!items.length && (!doneRows || S.state.hideCompleted)) {
      list.appendChild(UI.emptyState('inbox', t('noPendingTodos'), t('noPendingHint'), [
        { label: t('newTodo'), primary: true, action: () => App.openComposer('todo', {}) },
      ]));
      return;
    }
    if (items.length) {
      list.appendChild(UI.sectionHead(t('inbox'), items.length));
      items.forEach((todo) => list.appendChild(todoTile(todo)));
    }
    if (doneRows && !S.state.hideCompleted) {
      list.appendChild(UI.sectionHead(t('completedSection'), doneRows));
      done.forEach((todo) => list.appendChild(todoTile(todo, { done: true })));
      split.doneToday.forEach((x) => list.appendChild(todoTile(x.todo, { done: true })));
    }
  }

  function renderAll(list) {
    const split = splitRecurring(S.pendingTodos().filter(tagMatches));
    const pending = split.open.sort((a, b) => a.sortOrder - b.sortOrder);
    const done = S.completedTodos().filter(tagMatches);
    const doneCount = done.length + split.doneToday.length;
    if (!pending.length && (!doneCount || S.state.hideCompleted)) {
      list.appendChild(UI.emptyState('checkSquare', t('noPendingTodos'), t('noPendingHint'), [
        { label: t('newTodo'), primary: true, action: () => App.openComposer('todo', {}) },
      ]));
      return;
    }
    if (pending.length) {
      list.appendChild(UI.sectionHead(t('allTasks'), pending.length));
      pending.forEach((todo) => list.appendChild(todoTile(todo)));
    }
    if ((done.length || split.doneToday.length) && !S.state.hideCompleted) {
      const groups = {};
      const push = (day, todo) => {
        const key = day.getTime();
        groups[key] = groups[key] || { day, items: [] };
        groups[key].items.push(todo);
      };
      done.forEach((todo) => push(todo.completedAt ? U.startOfDay(todo.completedAt) : new Date(1970, 0, 1), todo));
      split.doneToday.forEach((x) => push(x.day, x.todo));
      Object.values(groups).sort((a, b) => b.day - a.day).forEach((g) => {
        list.appendChild(UI.sectionHead(U.fmtRelativeDay(g.day), g.items.length));
        g.items.forEach((todo) => list.appendChild(todoTile(todo, { done: true })));
      });
    }
  }

  window.__renderTodos = renderTodos;
  App.defineView('todos', renderTodos);
  window.__todoHelpers = { setView, openTodo };
})();
