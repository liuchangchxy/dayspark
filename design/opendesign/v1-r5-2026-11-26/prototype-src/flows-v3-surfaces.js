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
    // In an editor the master owns the draft path: it opens the occurrence
    // picker and keeps planReturnEdit. Intercepting here would write the
    // persisted todo before the user saves.
    if (state.drawerEdit || (state.draftKey && state.planReturnEdit)) return;
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
  // Only a surface that really represents one occurrence may bind it. Calendar
  // plan blocks bind by allocation identity; ordinary todo/task rows are
  // series-level and must clear any stale binding, so completion asks instead
  // of reusing a date from an earlier view.
  document.addEventListener('click', (e) => {
    const block = e.target.closest('.m-block[data-id]');
    if (block) {
      const visibleDay = (block.closest('.day-col') && block.closest('.day-col').dataset.date) || state.selectedDate || TODAY;
      if (block.classList.contains('is-plan')) {
        const allocId = block.dataset.alloc || block.getAttribute('data-alloc') || '';
        const t = todoById(block.dataset.id);
        const alloc = allocId && t && window.DS3 ? window.DS3.planById(t, allocId) : null;
        if (alloc) {
          const bound = alloc.legacy ? visibleDay : (alloc.occurrenceDate || (t && t.repeat ? null : alloc.date));
          if (bound) { state.occurId = block.dataset.id; state.occurDate = bound; }
          else { state.occurId = null; state.occurDate = null; }
          return;
        }
      }
      state.occurId = block.dataset.id;
      state.occurDate = visibleDay;
      return;
    }
    const row = e.target.closest('.task-row[data-id], .todo-row[data-id]');
    if (row) { state.occurId = null; state.occurDate = null; }
  }, true);

  /* ---------------- multiple reminders (one item, many reminders) ---------------- */
  function remindersOf(obj) {
    if (!obj) return [];
    const list = [];
    if (obj.remind && obj.remind !== '不提醒') list.push(obj.remind);
    (obj.reminders || []).forEach((r) => { if (r && r !== '不提醒' && !list.includes(r)) list.push(r); });
    return list;
  }
  function hasAnchorFor(obj, kind) {
    if (!obj) return false;
    if (kind === 'event') return !obj.allDay && !!obj.start;
    return !!(obj.due && obj.dueTime);
  }
  // One resolver for every form: new composer, detail editor draft, or the
  // persisted detail object. Reminder edits follow the containing form's
  // save/cancel semantics because they always write this object.
  function reminderSlot() {
    if (state.screen === 'new-todo' || state.screen === 'new-event') {
      return { obj: P.data.newDraft, kind: state.screen === 'new-event' ? 'event' : 'todo', newForm: true };
    }
    if (state.draft && state.draftKey) {
      return { obj: state.draft, kind: state.draftKey.indexOf('event:') === 0 ? 'event' : 'todo', newForm: false };
    }
    const ref = state.drawer;
    if (!ref) return null;
    return { obj: ref.type === 'event' ? eventById(ref.id) : todoById(ref.id), kind: ref.type, newForm: false };
  }
  function addReminderTo(slot) {
    if (!slot || !slot.obj) return;
    const obj = slot.obj;
    P.openReminderPicker({
      value: '',
      hasAnchor: hasAnchorFor(obj, slot.kind),
      onPick: (r) => {
        if (!r) return;
        if (remindersOf(obj).includes(r)) { toast('这个提醒已经有了'); return; }
        if (!obj.remind || obj.remind === '不提醒') obj.remind = r;
        else { obj.reminders = obj.reminders || []; obj.reminders.push(r); }
        render(); toast('已添加提醒 · ' + r);
      },
    });
  }
  function removeReminderFrom(slot, r) {
    const obj = slot && slot.obj;
    if (!obj) return;
    if (obj.remind === r) {
      const next = (obj.reminders || [])[0];
      obj.remind = next || '';
      if (next) obj.reminders = (obj.reminders || []).filter((x) => x !== next);
    } else {
      obj.reminders = (obj.reminders || []).filter((x) => x !== r);
    }
    render(); toast('已移除提醒 · ' + r);
  }

  function decorateReminderRows(root) {
    const slot = reminderSlot();
    if (!slot || !slot.obj) return;
    const list = remindersOf(slot.obj);
    const hasAnchor = hasAnchorFor(slot.obj, slot.kind);
    const addLabel = hasAnchor ? '＋ 再加一个' : '＋ 加绝对提醒';
    const addTitle = hasAnchor ? '' : '没有时间锚点；只能添加具体时间';
    if (slot.newForm) {
      const row = qa('.cp-field', root).find((r) => ((q('.k', r) || {}).textContent || '').trim() === '提醒');
      if (!row) return;
      const v = q('.v', row);
      if (v) v.innerHTML = esc(list[0] || '不提醒') + ' <button type="button" class="mini" data-proto-action="remind-add" title="' + esc(addTitle) + '">' + esc(addLabel) + '</button>';
      qa('.cp-remind-extra', root).forEach((n) => n.remove());
      const host = row.parentElement;
      list.slice(1).forEach((r) => {
        const extra = document.createElement('div');
        extra.className = 'cp-field cp-remind-extra';
        extra.innerHTML = '<span class="k">提醒</span><span class="v">' + esc(r) + ' <button type="button" class="mini" data-proto-action="remind-remove" data-remind="' + esc(r) + '">移除</button></span>';
        if (host) host.insertBefore(extra, row.nextSibling);
      });
      return;
    }
    const ref = state.drawer;
    if (!ref) return;
    const mobile = !!q('.m-detail-scroll', root);
    const rowSel = mobile ? '.m-form-row' : '.field-row, .form-row';
    const remindRow = qa(rowSel, root)
      .find((r) => ((q(mobile ? '.m-form-label' : '.f-label, .form-label', r) || {}).textContent || '').trim() === '提醒');
    if (!remindRow) return;
    const valueEl = q(mobile ? '.m-form-value' : '.f-value', remindRow);
    const select = q('select[data-mfield="remind"]', remindRow);
    if (select) {
      // Detail editor keeps its native primary-reminder select; the extra
      // reminders are appended as their own removable rows.
      if (!q('[data-remind-add]', remindRow)) {
        const b = document.createElement('button');
        b.type = 'button'; b.className = 'mini'; b.textContent = addLabel; b.title = addTitle;
        b.dataset.remindAdd = '1'; b.dataset.protoAction = 'remind-add';
        select.insertAdjacentElement('afterend', b);
      }
    } else if (valueEl) {
      valueEl.innerHTML = esc(list[0] || '不提醒') + ' <button type="button" class="mini" data-proto-action="remind-add" title="' + esc(addTitle) + '">' + esc(addLabel) + '</button>';
    }
    qa('[data-remind-extra]', root).forEach((n) => n.remove());
    const host = q(mobile ? '.m-form' : '.field-list, .form-grid', root) || remindRow.parentElement;
    list.slice(1).forEach((r) => {
      const row = document.createElement('div');
      const formRow = !mobile && remindRow.classList.contains('form-row');
      row.className = mobile ? 'm-form-row' : (formRow ? 'form-row' : 'field-row');
      row.dataset.remindExtra = '1';
      row.innerHTML = mobile
        ? '<span class="m-form-label">提醒</span><span class="m-form-value">' + esc(r) + ' <button type="button" class="mini" data-proto-action="remind-remove" data-remind="' + esc(r) + '">移除</button></span>'
        : (formRow
          ? '<label class="form-label">提醒</label><div class="form-input" style="display:flex;align-items:center;justify-content:space-between">' + esc(r) + ' <button type="button" class="mini" data-proto-action="remind-remove" data-remind="' + esc(r) + '">移除</button></div>'
          : '<span class="f-label">提醒</span><span class="f-value">' + esc(r) + ' <button type="button" class="mini" data-proto-action="remind-remove" data-remind="' + esc(r) + '">移除</button></span>');
      if (host) host.insertBefore(row, remindRow.nextSibling);
    });
  }

  registerEnhancer((root) => {
    if (!root) return;
    if (!(state.screen === 'new-todo' || state.screen === 'new-event' || state.drawer || state.draftKey)) return;
    decorateReminderRows(root);
  });

  registerEnhancer((root) => {
    qa('[data-action="widget-toggle"], [data-action="mcp-toggle"], [data-action="mcp-scope"], [data-action="mcp-revoke"], [data-action="mcp-copy"], [data-action="toggle-mobile-due"]', root).forEach((el) => {
      el.dataset.protoAction = el.dataset.action;
    });
  });

  registerAction('widget-toggle', (el) => {
    const id = el && el.dataset ? el.dataset.id : '';
    const t = todoById(id);
    if (!t) return;
    if (t.repeat) {
      DS3.requireOccurrence(t, (picked) => {
        if (DS3.toggleDone(id, picked)) render();
      }, { title: '完成哪一次 · ' + t.title });
    } else if (DS3.toggleDone(id)) {
      render();
    }
  });
  registerAction('mcp-toggle', () => { state.mcpEnabled = state.mcpEnabled === false; render(); toast(state.mcpEnabled === false ? 'MCP 服务已暂停' : 'MCP 服务已恢复'); });
  registerAction('mcp-scope', () => { state.mcpWrite = state.mcpWrite === false; render(); toast(state.mcpWrite === false ? '已收回写入权限' : '已授予写入权限'); });
  registerAction('mcp-copy', async () => {
    const text = 'https://sync.dayspark.local/mcp';
    try { await navigator.clipboard.writeText(text); toast('端点已复制'); }
    catch (_) { toast('端点：' + text); }
  });
  registerAction('mcp-revoke', () => { state.mcpRevoked = true; render(); toast('已撤销客户端授权；现有会话需要重新连接'); });
  registerAction('toggle-mobile-due', () => { state.mobileDueOpen = !state.mobileDueOpen; render(); });
  registerAction('remind-add', () => { addReminderTo(reminderSlot()); });
  registerAction('remind-remove', (el) => { removeReminderFrom(reminderSlot(), el.dataset.remind); });

  // The boot render ran before this file loaded, so derived missed counts were
  // not in the first DOM. Re-render once so the initial screen tells the truth.
  setTimeout(() => { try { render(); } catch (_) { /* master not ready */ } }, 0);
})();
