/* DaySpark prototype v3 — missed instances, instance entry points, and the
   second calendar-slot action (arrange an existing todo instead of creating
   an event). Semantics live in flows-v3-model.js (DS3); this file only adds
   entry points and the arrange flow. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
  const DS3 = window.DS3;

  /* ---------------- real missed counts ---------------- */
  // `t.missed` used to be a hand-written demo number. Now it is derived from
  // the series anchor + recorded completions/skips, so completing a missed
  // instance lowers the count and restoring it raises it again.
  const baseAllTodos = window.allTodos;
  window.allTodos = function () {
    const list = baseAllTodos();
    if (!DS3) return list;
    list.forEach((t) => {
      if (!t || !t.repeat || t.legacyRrule) return;
      t.missed = DS3.missedCount(t, 30);
    });
    return list;
  };

  function missedEntry(t, offset) {
    const page = Math.max(0, offset || 0);
    const list = DS3.missedInstances(t, 30, page);
    const older = DS3.missedInstances(t, 30, page + 30);
    if (!list.length && !page) { toast('最近 30 天没有遗漏的实例'); return; }
    const body = document.createElement('div');
    function paint() {
      body.innerHTML = `<div class="proto-note" style="margin-top:0">${esc(t.repeat)} · ${page ? '更早' : '最近'} 30 天有 ${list.length} 次没有完成。它们仍然可以补完成，不会自动跳过。</div>`        + `<div class="proto-list">${list.length ? list.map((d) => `<div class="proto-list-row"><span class="grow">${d}<small>${weekday(d)} · 仍然待完成</small></span><button type="button" class="proto-btn" data-miss="${d}">完成这一次</button></div>`).join('') : '<div class="proto-note">这 30 天没有遗漏的实例。</div>'}</div>`;
    }
    paint();
    const scrim = modal({
      title: '遗漏的实例 · ' + t.title,
      body,
      actions: [
        { label: '关闭' },
        { label: '查看全部实例', onClick: () => { P.showInstances && P.showInstances(t); } },
      ],
    });
    // Footer buttons live outside the body, so listen on the dialog.
    scrim.addEventListener('click', (e) => {
      const more = e.target.closest('[data-missed-older]');
      if (more) {
        const prev = DS3.missedInstances(t, 30, page + 30);
        if (!prev.length) { toast('再往前没有遗漏的实例'); return; }
        scrim.remove();
        missedEntry(t, page + 30);
        return;
      }
    });
    body.addEventListener('click', (e) => {
      const done = e.target.closest('[data-miss]');
      if (done) {
        DS3.toggleDone(t.id, done.dataset.miss);
        render(); toast('已完成 ' + done.dataset.miss + ' 这一次');
        scrim.remove();
      }
    });
    if (older.length) {
      const foot = q('.proto-modal-foot', scrim);
      const more = document.createElement('button');
      more.type = 'button'; more.className = 'proto-btn'; more.textContent = '更早遗漏（' + older.length + '）';
      more.dataset.missedOlder = '1';
      foot.insertBefore(more, q('.proto-btn.primary', foot) || null);
    }
  }

  registerEnhancer((root) => {
    if (!root) return;
    // Any "已遗漏 N" in a row or drawer opens the missed-instance list.
    qa('.missed', root).forEach((el) => {
      if (el.dataset.protoAction) return;
      const row = el.closest('[data-id]');
      // The demo card has a data-id too; only the newest-first card offset
      // should start on the older page.
      const id = (row && row.dataset.id) || (state.drawer && state.drawer.id);
      if (!id) return;
      el.dataset.protoAction = 'missed-open';
      el.dataset.id = id;
      el.style.cursor = 'pointer';
      el.title = '查看遗漏的实例';
    });
    // The demo "已遗漏" card completes the *latest missed* instance, never today.
    qa('.missed-card', root).forEach((card) => {
      const btn = q('[data-action="toggle-done"]', card);
      if (btn && !btn.dataset.v3miss) {
        const t = todoById(btn.dataset.id);
        const list = t ? DS3.missedInstances(t, 30) : [];
        btn.dataset.v3miss = '1';
        if (list.length) {
          btn.dataset.date = list[list.length - 1];
          btn.title = '只完成 ' + list[list.length - 1] + ' 这一次';
          btn.textContent = '完成这一次';
        }
      }
      if (!q('[data-missed-more]', card)) {
        const acts = q('.missed-card-actions', card);
        if (acts) {
          const b = document.createElement('button');
          b.type = 'button'; b.textContent = '更早遗漏';
          b.dataset.missedMore = '1';
          b.dataset.protoAction = 'missed-open';
          b.dataset.offset = '30';
          b.dataset.id = btn ? btn.dataset.id : '';
          acts.appendChild(b);
        }
      }
    });
  });

  registerAction('missed-open', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (!t) return;
    if (t.repeat) missedEntry(t, Number(el.dataset.offset) || 0);
    else toast('这项没有遗漏实例');
  });

  /* ---------------- calendar slot: create event OR arrange a todo ---------------- */
  // The slot click already opens the "新建日程" modal (flows-v2-calendar.js).
  // We add the second explicit action next to it, as the domain contract
  // requires (CalendarSlotSheet onCreateEvent + onScheduleTodo).
  new MutationObserver((muts) => {
    muts.forEach((m) => Array.from(m.addedNodes || []).forEach((n) => {
      if (!n || n.nodeType !== 1) return;
      const scrim = n.classList && n.classList.contains('proto-modal-scrim') ? n : q('.proto-modal-scrim', n);
      if (!scrim) return;
      const head = q('.proto-modal-head span', scrim);
      if (!head || head.textContent.trim() !== '新建日程') return;
      const foot = q('.proto-modal-foot', scrim);
      if (!foot) return;
      if (scrim.__v3arr) {
        if (!q('[data-arrange]', foot)) foot.insertBefore(scrim.__v3arr, q('.proto-btn.primary', foot) || null);
        return;
      }
      const note = q('.proto-note', scrim);
      const day = ((note && note.textContent.match(/\d{4}-\d{2}-\d{2}/)) || [])[0] || state.selectedDate || TODAY;
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'proto-btn'; b.textContent = '安排已有待办'; b.dataset.arrange = '1';
      b.addEventListener('click', () => {
        const start = (q('#qe-start', scrim) || {}).value || '09:00';
        const end = (q('#qe-end', scrim) || {}).value || '10:00';
        if (scrim._close) scrim._close(); else scrim.remove();
        openArrange(day, start, end);
      });
      scrim.__v3arr = b;
      const primary = q('.proto-btn.primary', foot);
      foot.insertBefore(b, primary || null);
    }));
  }).observe(document.body, { childList: true });

  function openArrange(day, start, end) {
    const todos = allTodos().filter((t) => !isDone(t) && !state.deletedTodos.includes(t.id));
    if (!todos.length) { toast('没有可安排的待办'); return; }
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-note" style="margin-top:0">${day} ${start}–${end} · 只写计划执行，不新建日程，也不改截止。</div>`
      + `<div class="proto-list">${todos.map((t) => `<button type="button" class="proto-list-row" data-arr="${esc(t.id)}"><span class="grow">${esc(t.title)}<small>${esc(calOf(t.cal).name)}${t.repeat ? ' · ' + esc(t.repeat) + ' · 需先选实例' : ''}</small></span></button>`).join('')}</div>`;
    const scrim = modal({ title: '安排待办 · ' + start + '–' + end, body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-arr]'); if (!b) return;
      const t = todoById(b.dataset.arr); if (!t) return;
      scrim.remove();
      if (!t.repeat) { toPlanPicker(t, null, day, start, end); return; }
      pickInstance(t, day, start, end);
    });
  }

  function pickInstance(t, day, start, end) {
    const list = DS3.instanceList(t, -30, 90).filter((x) => !x.done && !x.skipped);
    if (!list.length) {
      modal({ title: '没有可安排的实例', body: `<div class="proto-note">「${esc(t.title)}」在未来 90 天没有待完成的实例。</div>`, actions: [{ label: '关闭', primary: true }] });
      return;
    }
    // Prefer the occurrence that owns this slot day, then the nearest pending one.
    const exact = list.find((x) => x.date === day);
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-note" style="margin-top:0">重复待办的计划执行必须绑定这一次实例；只影响选中的这一次。</div>`
      + `<div class="proto-list">${list.map((x) => `<button type="button" class="proto-list-row" data-occ="${x.date}"><span class="grow">${x.date}<small>${weekday(x.date)}${x.date === day ? ' · 就是这个时间槽' : ''}</small></span></button>`).join('')}</div>`;
    const scrim = modal({ title: '选择哪一次 · ' + t.title, body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-occ]'); if (!b) return;
      scrim.remove();
      toPlanPicker(t, b.dataset.occ, day, start, end);
    });
    if (exact) { /* the list shows it first with a hint; nothing auto-selected */ }
  }

  // Scheduling a repeating todo must name the occurrence. The master's
  // plan-todo would silently default to today; ask instead of guessing.
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-action="plan-todo"]');
    if (!b || state.screen === 'plan-picker') return;
    const t = todoById(b.dataset.id); if (!t || !t.repeat || !DS3) return;
    e.preventDefault(); e.stopPropagation();
    const day = state.planDateHint || state.selectedDate || TODAY;
    const start = (t.plan && t.plan.start) || '15:15';
    const end = (t.plan && t.plan.end) || '16:00';
    pickInstance(t, day, start, end);
  }, true);

  function toPlanPicker(t, occurrenceDate, day, start, end) {
    const back = { screen: state.screen || 'cal-day', variant: state.variant || 'normal' };
    // The master's go('plan-picker') resets plan defaults and planReturn, so
    // the slot day/time and the return screen are applied after it.
    P.baseGo('plan-picker');
    state.planTodoId = t.id;
    state.planAllocId = null;
    state.planOccurrence = occurrenceDate;
    state.planReturn = back.screen;
    state.planReturnVariant = back.variant;
    state.planReturnDrawer = null;
    state.planReturnEdit = false;
    state.planDate = occurrenceDate || day;
    state.planStart = start;
    state.planEnd = end;
    render();
  }

  /* ---------------- drawer / detail instance scope ---------------- */
  // Rows carry the occurrence that was clicked; the drawer keeps it so the
  // completion button and history entry talk about the same instance.
  document.addEventListener('click', (e) => {
    const row = e.target.closest('.task-row[data-id], .todo-row[data-id], .m-block[data-id]');
    if (row && row.dataset.id) {
      state.occurId = row.dataset.id;
      state.occurDate = (row.closest('.day-col') && row.closest('.day-col').dataset.date) || state.selectedDate || TODAY;
    }
  }, true);

  // A rendered row keeps its own occurrence, so opening it can name that
  // instance even in a repeating series.
  registerEnhancer((root) => {
    qa('.task-row[data-id], .todo-row[data-id]', root).forEach((row) => {
      if (row.dataset.v3occhint) return;
      row.dataset.v3occhint = '1';
      row.addEventListener('click', (ev) => {
        if (ev.target.closest('[data-action="toggle-done"], [data-action="plan-todo"], [data-proto-action]')) return;
        state.occurId = row.dataset.id;
        state.occurDate = state.selectedDate || TODAY;
      }, true);
    });
  });

  /* ---------------- multiple reminders (one item, many reminders) ---------------- */
  function hasAnchor(t) {
    if (!t) return false;
    if (t.plan && t.plan.start) return true;
    if (Array.isArray(t.plans) && t.plans.some((p) => p && p.state === 'active' && p.start)) return true;
    return !!(t.due && t.dueTime);
  }
  function remindersOf(t) {
    if (!t) return [];
    const list = [];
    if (t.remind) list.push(t.remind);
    (t.reminders || []).forEach((r) => { if (r && !list.includes(r)) list.push(r); });
    return list;
  }
  function addReminder(t) {
    P.openReminderPicker({
      value: '',
      hasAnchor: hasAnchor(t),
      onPick: (r) => {
        if (!r) return;
        if (remindersOf(t).includes(r)) { toast('这个提醒已经有了'); return; }
        if (!t.remind) t.remind = r;
        else { t.reminders = t.reminders || []; t.reminders.push(r); }
        render(); toast('已添加提醒 · ' + r);
      },
    });
  }
  function removeReminder(t, r) {
    if (t.remind === r) {
      const next = (t.reminders || [])[0];
      t.remind = next || '';
      if (next) t.reminders = (t.reminders || []).filter((x) => x !== next);
    } else {
      t.reminders = (t.reminders || []).filter((x) => x !== r);
    }
    render(); toast('已移除提醒 · ' + r);
  }

  registerEnhancer((root) => {
    const ref = state.drawer;
    if (!ref || ref.type !== 'todo' || state.drawerEdit) return;
    const t = todoById(ref.id);
    if (!t) return;
    // Desktop drawer uses field-row; the phone drawer uses m-form-row.
    const mobile = !!q('.m-detail-scroll', root);
    const remindRow = qa(mobile ? '.m-form-row' : '.field-row', root)
      .find((r) => ((q(mobile ? '.m-form-label' : '.f-label', r) || {}).textContent || '').trim() === '提醒');
    if (!remindRow) return;
    if (!q('[data-remind-add]', remindRow)) {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'mini'; b.textContent = '＋ 再加一个';
      b.dataset.remindAdd = '1'; b.dataset.protoAction = 'remind-add'; b.dataset.id = t.id;
      const v = q(mobile ? '.m-form-value' : '.f-value', remindRow);
      if (v) { v.appendChild(document.createTextNode(' ')); v.appendChild(b); }
      else { remindRow.appendChild(b); }
    }
    // Extra reminders render as their own rows (each removable) so the
    // primary reminder stays where the master put it.
    qa('[data-remind-extra]', root).forEach((n) => n.remove());
    const extras = (t.reminders || []).filter((r) => r && r !== t.remind);
    const list = q(mobile ? '.m-form' : '.field-list', root) || remindRow.parentElement;
    if (extras.length && list) {
      extras.forEach((r) => {
        const row = document.createElement('div');
        row.className = mobile ? 'm-form-row' : 'field-row';
        row.dataset.remindExtra = '1';
        row.innerHTML = mobile
          ? '<span class="m-form-label">提醒</span><span class="m-form-value">' + esc(r) + ' <button type="button" class="mini" data-proto-action="remind-remove" data-id="' + esc(t.id) + '" data-remind="' + esc(r) + '">移除</button></span>'
          : '<span class="f-label">提醒</span><span class="f-value">' + esc(r) + ' <button type="button" class="mini" data-proto-action="remind-remove" data-id="' + esc(t.id) + '" data-remind="' + esc(r) + '">移除</button></span>';
        list.insertBefore(row, remindRow.nextSibling);
      });
    }
  });

  registerAction('remind-add', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (t) addReminder(t);
  });
  registerAction('remind-remove', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (t) removeReminder(t, el.dataset.remind);
  });

  // The boot render ran before this file loaded, so derived missed counts were
  // not in the first DOM. Re-render once so the initial screen tells the truth.
  setTimeout(() => { try { render(); } catch (_) { /* master not ready */ } }, 0);
})();
