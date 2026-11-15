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
    App.render();
  }

  function tagMatches(todo) {
    const sel = S.state.selectedTagIds;
    if (!sel.length) return true;
    return todo.tagIds.some((id) => sel.includes(id));
  }

  function openTodo(todo) {
    S.navigate('detail', { type: 'todo', id: todo.id });
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
      rowNode.appendChild(UI.checkbox(o.done, () => toggle(todo), t('markComplete')));
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
      const moreBtn = UI.iconButton('more' in ICON_NAMES ? 'more' : 'sliders', t('more'), (e) => {
        e.stopPropagation();
        openRowMenu(moreBtn, todo);
      }, { sm: true, size: 15 });
      actions.appendChild(moreBtn);
    }
    rowNode.appendChild(actions);

    rowNode.addEventListener('click', () => {
      if (multi.active) {
        if (multi.ids.has(todo.id)) multi.ids.delete(todo.id); else multi.ids.add(todo.id);
        App.render();
        return;
      }
      openTodo(todo);
    });
    rowNode.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      openRowMenu(rowNode, todo);
    });
    if (!multi.active && !o.done) attachReorder(wrap, rowNode, todo);
    attachSwipe(wrap, rowNode, todo);
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
      function up() {
        document.removeEventListener('pointermove', move);
        document.removeEventListener('pointerup', up);
        document.removeEventListener('pointercancel', up);
        rowNode.classList.remove('dragging');
        rowNode.style.transform = '';
        rowNode.style.zIndex = '';
        rowNode.style.boxShadow = '';
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

  function toggle(todo) { window.TodoOps.complete(todo); }

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

  function attachSwipe(wrap, rowNode, todo) {
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
        toggle(todo);
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
      ids.forEach((id) => {
        const todo = S.todoById(id);
        if (!todo || !S.isOpen(todo)) return;
        const occ = todo.recurrence ? window.TodoOps.todayOccurrenceId(todo) : null;
        if (todo.recurrence && !occ) { skipped.push(todo.summary); return; }
        const result = S.completeTodo(id, occ ? { occurrenceId: occ } : undefined);
        if (result) written.push({ id, occ });
      });
      multi.ids.clear();
      multi.active = false;
      App.render();
      if (!written.length) {
        UI.toast(t('recurrenceNeedsOccurrence'), { warn: true });
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
    const prev = U.el('button', { class: 'ws-arrow', 'aria-label': t('back'), html: ICON('chevronLeft', 15) });
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
    const next = U.el('button', { class: 'ws-arrow', 'aria-label': t('more'), html: ICON('chevronRight', 15) });
    next.addEventListener('click', () => setView({ kind: 'day', day: U.addDays(selected || today, 7) }));
    strip.appendChild(next);
    return strip;
  }

  function renderTodos() {
    const v = view();
    const today = U.startOfDay(U.now());
    const day = v.kind === 'day' ? v.day : null;
    const actions = [];
    if (!U.isNarrow()) {
      const add = U.el('button', { class: 'btn primary', 'data-testid': 'todos-create' });
      add.innerHTML = ICON('plus', 14) + `<span>${U.esc(t('newTodo'))}</span>`;
      add.addEventListener('click', () => App.openComposer('todo', day ? { dueDate: day } : {}));
      actions.push(add);
    }
    const tagsBtn = UI.iconButton('tag', t('navTags'), () => App.go('tags'));
    const trashBtn = UI.iconButton('trash', t('navTrash'), () => App.go('trash'));
    const filterBtn = UI.iconButton('filter', t('filterAndDisplay'), (ev) => {
      ev.stopPropagation();
      UI.menu(ev.currentTarget, [
        {
          icon: S.state.hideCompleted ? 'eye' : 'checkSquare',
          text: S.state.hideCompleted ? t('showCompleted') : t('hideCompleted'),
          action: () => { S.state.hideCompleted = !S.state.hideCompleted; S.savePrefs(); App.render(); },
        },
      ]);
    }, { testid: 'todos-filter' });
    actions.push(filterBtn, tagsBtn, trashBtn);

    const page = UI.page({
      title: t('pageTodos'),
      subtitle: day ? `${U.esc(U.fmtMonthDay(day))} · ${U.esc(U.fmtWeekdayLong(day))}` : (v.kind === 'inbox' ? t('inbox') : t('allTasks')),
      actions,
      build(content) {
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
        const spacer = U.el('span', { class: 'spacer' });
        toolbar.appendChild(spacer);
        const selBtn = U.el('button', { class: 'chip-btn' + (multi.active ? ' on' : ''), text: multi.active ? t('exitSelect') : t('selectMode') });
        selBtn.addEventListener('click', () => { multi.active = !multi.active; multi.ids.clear(); App.render(); });
        toolbar.appendChild(selBtn);
        content.appendChild(toolbar);

        if (v.kind === 'day') content.appendChild(weekStrip(day));

        if (S.state.tags.length) {
          const tagBar = U.el('div', { class: 'chips-scroll' });
          tagBar.style.paddingBottom = '6px';
          S.state.tags.forEach((tag) => {
            const on = S.state.selectedTagIds.includes(tag.id);
            const b = U.el('button', { class: 'chip-btn' + (on ? ' on' : '') });
            b.innerHTML = `<span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}`;
            b.setAttribute('aria-pressed', on ? 'true' : 'false');
            b.addEventListener('click', () => {
              S.state.selectedTagIds = on ? S.state.selectedTagIds.filter((x) => x !== tag.id) : S.state.selectedTagIds.concat(tag.id);
              App.render();
            });
            tagBar.appendChild(b);
          });
          if (S.state.selectedTagIds.length) {
            const clear = U.el('button', { class: 'chip-btn', text: t('clear') });
            clear.addEventListener('click', () => { S.state.selectedTagIds = []; App.render(); });
            tagBar.appendChild(clear);
          }
          content.appendChild(tagBar);
        }

        if (multi.active) content.appendChild(selectBar());

        const add = quickAdd(v.kind === 'day' ? U.fmtMonthDay(day) : (v.kind === 'inbox' ? t('inbox') : null), (text) => {
          const todo = S.createTodo({ summary: text, dueDate: v.kind === 'day' ? U.startOfDay(day) : null });
          App.render();
          UI.toast(t('createdToast', { t: todo.summary }), {
            undo: () => { S.softDeleteTodo(todo.id); App.render(); },
          });
          const focus = U.qs('[data-testid="todo-quick-add"]');
          if (focus) focus.focus();
        });
        content.appendChild(add.box);

        const list = U.el('div', { class: 'todo-list', 'data-testid': 'todo-list' });
        content.appendChild(list);

        if (v.kind === 'day') {
          renderDay(list, day);
        } else if (v.kind === 'inbox') {
          renderInbox(list);
        } else {
          renderAll(list);
        }
      },
    });

    if (U.isNarrow()) {
      const fab = U.el('button', { class: 'btn primary', 'data-testid': 'todos-create' });
      fab.innerHTML = ICON('plus', 14);
      fab.style.position = 'fixed';
      fab.style.right = '16px';
      fab.style.bottom = '66px';
      fab.style.zIndex = '40';
      fab.style.width = '48px';
      fab.style.height = '48px';
      fab.style.borderRadius = '50%';
      fab.style.boxShadow = 'var(--shadow-1)';
      fab.setAttribute('aria-label', t('newTodo'));
      fab.addEventListener('click', () => App.openComposer('todo', day ? { dueDate: day } : {}));
      page.appendChild(fab);
    }
    return page;
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
      list.appendChild(UI.sectionHead(t('overdue'), overdue.length, { tone: 'danger' }));
      overdue.forEach((todo) => list.appendChild(todoTile(todo)));
    }
    if (dated.length) {
      list.appendChild(UI.sectionHead(isToday ? t('today') : U.fmtMonthDay(day), dated.length, { tone: 'accent' }));
      dated.forEach((todo) => list.appendChild(todoTile(todo)));
    }
    if ((done.length || doneInstances.length) && !S.state.hideCompleted) {
      list.appendChild(UI.sectionHead(t('completedSection'), done.length + doneInstances.length));
      done.forEach((todo) => list.appendChild(todoTile(todo, { done: true })));
      // A ticked occurrence of a repeating to-do belongs here too: the series
      // stays open, but this day's instance is finished.
      doneInstances.forEach((x) => list.appendChild(todoTile(x.todo, { done: true })));
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
