/* DaySpark R7 — shared interaction rules.
   One module owns the cross-page grammar so pages do not each invent their
   own control: create entry, date navigation, direct field editing, exit
   layering, the hide-completed preference, Chinese calendar marks and the
   notification snooze write path. Everything here writes real data through
   the same stores the rest of the prototype uses; nothing is display-only. */
(function () {
  const P = window.Proto;
  if (!P) return;
  const { registerAction, registerEnhancer, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const save = () => { if (P.save) P.save(); };
  const esc = P.esc || ((s) => String(s == null ? '' : s));

  P.data.prefs = Object.assign({ hideCompleted: false }, P.data.prefs || {});

  /* ---------------- 1. one create entry ---------------- */
  function todoForSchedule() {
    return allTodos().filter((t) => !isDone(t));
  }
  // The entry is the same control on every page: a header ＋ that opens one
  // two-choice sheet. What changes is only the context it carries — the page
  // you are on and the date you are browsing — never the grammar.
  function createContext() {
    const browse = state.screen.startsWith('cal-') || state.screen === 'todo-date'
      ? (state.selectedDate || TODAY)
      : TODAY;
    return { date: browse, from: state.screen };
  }
  function defaultEventWindow(day) {
    // Same rule Flutter's slot sheet applies: a concrete range, not an
    // invented free-slot search. Today starts at the next round hour, and the
    // last possible one-hour window on any day is 22:00–23:00 so a window is
    // never offered partly in the past (22:30 → 22:00 would be).
    if (day === TODAY) {
      const h = Math.floor(NOW / 60);
      const next = Math.min(22, h + 1);
      return { start: String(next).padStart(2, '0') + ':00', end: String(Math.min(23, next + 1)).padStart(2, '0') + ':00' };
    }
    return { start: '09:00', end: '10:00' };
  }
  P.openNewPicker = function (ctx) {
    ctx = ctx || createContext();
    const win = defaultEventWindow(ctx.date);
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-list">
      <button type="button" class="proto-list-row" data-new="todo"><span class="grow">待办<small>记一件事；默认无截止、无计划，先落到未安排</small></span></button>
      <button type="button" class="proto-list-row" data-new="event"><span class="grow">日程<small>${esc(mdShort(ctx.date))} ${win.start}–${win.end}；有明确时间段的安排</small></span></button>
    </div>`;
    const scrim = P.modal({ title: '新建', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-new]');
      if (!b) return;
      scrim.remove();
      P.data.newDraft = null;
      P.data.aiPrefill = null;
      P.data.newContext = b.dataset.new === 'event'
        ? { date: ctx.date, start: win.start, end: win.end }
        : null;
      P.baseGo(b.dataset.new === 'event' ? 'new-event' : 'new-todo');
      P.syncHash(true);
    });
    return scrim;
  };
  registerAction('new-pick', (el) => { P.openNewPicker(el && el.dataset && el.dataset.date ? { date: el.dataset.date } : createContext()); });

  /* ---------------- 2. date navigation ---------------- */
  function navDate(next) {
    const target = next || TODAY;
    state.selectedDate = target;
    // A pending filter and the browse date are independent facts; switching
    // days must not silently drop the filter the user just set.
    state.variant = state.variant === 'filter' || state.variant === 'filter-empty' ? 'normal' : state.variant;
    state.drawer = null;
    state.confirmDelete = false;
    if (typeof clearDraft === 'function') clearDraft();
    render();
  }
  registerAction('date-step', (el) => {
    const step = Number(el.dataset.step) || 0;
    navDate(addDays(state.selectedDate || TODAY, step));
  });
  registerAction('date-today', () => navDate(TODAY));

  /* Calendar keeps its own 今天 control; it must land on the same date the
     todo date strip uses, not on a stale browse date. */
  const baseCalToday = P.actions['cal-today'];
  registerAction('cal-today', () => { navDate(TODAY); if (baseCalToday) baseCalToday(); });

  /* ---------------- 3. direct editing of frequent fields ---------------- */
  function writeTodo(item, patch, message) {
    Object.keys(patch).forEach((k) => { item[k] = patch[k]; });
    render();
    save();
    if (message) toast(message);
  }
  function fieldRowByLabel(root, label) {
    return qa('.drawer .field-row', root).find((row) => {
      const l = q('.f-label', row);
      return l && (l.textContent || '').trim() === label;
    });
  }
  function markRow(row, name, id) {
    if (!row) return;
    row.dataset.protoAction = name;
    if (id) row.dataset.id = id;
    // The row already draws its own chevron; adding a second one made the
    // same affordance appear twice on five rows.
    row.classList.add('is-direct');
  }
  function openDueDirect(item) {
    let due = item.due || TODAY;
    let dueTime = item.dueTime || '';
    const body = document.createElement('div');
    function paint() {
      body.innerHTML = `<div class="proto-field"><label>日期</label><button type="button" class="proto-input" data-proto-action="dd-date" style="text-align:left">${esc(due)}</button></div>
        <div class="proto-field"><label>时间（可选）</label><input type="time" class="proto-input" id="dd-time" value="${esc(dueTime)}"></div>
        <div class="proto-note">只写日期时不会写入任何时刻；截止不是时间占用，也不会自动安排计划。</div>`;
    }
    paint();
    const scrim = P.modal({ title: '截止', body, actions: [
      { label: '取消' },
      { label: '清除截止', onClick: () => { writeTodo(item, { due: '', dueTime: '' }, '已清除截止'); } },
      { label: '保存', primary: true, onClick: () => {
        const t = q('#dd-time', body).value;
        writeTodo(item, { due, dueTime: t }, t ? '截止 · ' + mdShort(due) + ' ' + t : '截止 · ' + mdShort(due));
      } },
    ] });
    body.addEventListener('click', (e) => {
      if (!e.target.closest('[data-proto-action="dd-date"]')) return;
      P.openDatePicker({ value: due, onPick: (v) => { due = v || TODAY; paint(); } });
    });
    return scrim;
  }
  registerAction('direct-due', (el) => {
    const item = todoById(el.dataset.id);
    if (item) openDueDirect(item);
  });
  registerAction('direct-priority', (el) => {
    const item = todoById(el.dataset.id);
    if (!item) return;
    P.openPriorityPicker({ value: Number(item.priority), onPick: (v) => writeTodo(item, { priority: v }, '优先级已保存') });
  });
  registerAction('direct-calendar', (el) => {
    const ref = state.drawer;
    const item = ref && ref.type === 'event' ? eventById(ref.id) : todoById(el.dataset.id);
    if (!item) return;
    P.openCalendarPicker({ value: item.cal, onPick: (id) => writeTodo(item, { cal: id }, '日历 · ' + calOf(id).name) });
  });
  registerAction('direct-reminder', (el) => {
    const ref = state.drawer;
    const kind = ref && ref.type === 'event' ? 'event' : 'todo';
    const item = kind === 'event' ? eventById(ref.id) : todoById(el.dataset.id);
    if (!item) return;
    if (P.openReminderPicker) {
      P.openReminderPicker({ value: item.remind || '不提醒', kind, onPick: (v) => {
        if (kind === 'event') writeTodo(item, { remind: v === '不提醒' ? '' : v }, '提醒已保存');
        else writeTodo(item, { remind: v === '不提醒' ? '' : v }, '提醒已保存');
      } });
      return;
    }
    P.actions['start-edit'] && P.actions['start-edit']();
  });
  registerAction('direct-repeat', (el) => {
    // Repeat is not an ordinary field: changing it rewrites the series anchor,
    // its instances and its range. The picker used to write `item.repeat` in
    // place, which skipped every one of those constraints and left the
    // projection inconsistent with the stored rule. It now enters the real
    // edit flow — draft, series-level save confirmation, anchor/instance
    // handling — exactly as the 编辑 button does, and opens the same picker
    // inside it. Nothing else about the drawer changes.
    const ref = state.drawer;
    if (!ref) return;
    clearDraft();
    state.drawerEdit = true;
    render();
    // The editor's own 重复 row owns the picker (select + 自定义…); clicking the
    // read-only row simply lands the user there with focus on that row.
    // The desktop editor draws `.form-row` + `.form-label`; the phone drawer
    // has `.m-form-row` + `.m-form-label`. Both label classes are checked so
    // the row is actually found and focused rather than silently skipped.
    const control = q('.drawer select[data-mfield="repeat"]', document);
    // The row that owns the control — not the control itself. The previous
    // selector could return the <select> (it matches [data-mfield=repeat]),
    // then looked for a select *inside* it and focused nothing.
    const row = (control && control.closest('.form-row, .m-form-row')) || qa('.drawer .m-form-row, .drawer .form-row', document).find((r) => {
      const label = q('.m-form-label', r) || q('.form-label', r) || q('.f-label', r);
      return label && (label.textContent || '').trim() === '重复';
    });
    if (row) {
      row.classList.add('is-focus');
      row.scrollIntoView({ block: 'nearest' });
    }
    // Focus after this render cycle finishes: the shared enhancer pass still
    // runs in a following frame and moves focus back to the document, so
    // focusing synchronously here looked correct for one frame and then lost
    // the caret. The row highlight is re-applied in case that pass rebuilt it.
    // Focus now, and once more after the shared enhancer pass and any closing
    // toast have re-rendered the frame: both can replace the node, and a
    // caret that disappears one frame later is not "landed on the field".
    if (control) control.focus();
    const refocus = () => {
      if (!state.drawerEdit) return;
      const c = q('.drawer select[data-mfield="repeat"]', document) || q('select[data-mfield="repeat"]', document);
      if (!c) return;
      const r = c.closest('.form-row, .m-form-row');
      if (r) r.classList.add('is-focus');
      c.focus();
    };
    requestAnimationFrame(() => requestAnimationFrame(refocus));
  });
  registerAction('plan-row', (el) => {
    // Reuse the master's one real entry so the occurrence picker, planReturn
    // and the draft path all stay exactly as they are. The synthetic button is
    // needed because the master handles data-action, not proto actions.
    const id = (el && el.dataset.id) || (state.drawer && state.drawer.id);
    if (!id) return;
    const b = document.createElement('button');
    b.type = 'button';
    b.dataset.action = 'plan-todo';
    b.dataset.id = id;
    b.style.display = 'none';
    document.body.appendChild(b);
    b.click();
    b.remove();
  });
  registerAction('direct-subtask-add', (el) => {
    const ref = state.drawer;
    const item = ref ? (ref.type === 'event' ? eventById(ref.id) : todoById(ref.id)) : null;
    if (!item) return;
    P.prompt({
      title: '添加子任务',
      label: '子任务',
      placeholder: '只写标题',
      onConfirm: (v) => {
        if (!v) { toast('先写子任务标题'); return; }
        item.subtasks = item.subtasks || [];
        item.subtasks.push({ title: v, done: false });
        render();
        save();
        toast('已添加子任务');
      },
    });
  });
  registerAction('direct-tags', (el) => {
    const ref = state.drawer;
    const kind = ref && ref.type === 'event' ? 'event' : 'todo';
    const item = kind === 'event' ? eventById(ref.id) : todoById(el.dataset.id);
    if (!item) return;
    P.openTagPicker(item.tags || [], (tags) => { writeTodo(item, { tags }, tags.length ? '标签已更新' : '已清除标签'); });
  });

  /* The phone editor has no .d-sec sections; its tag row is a real form row
     with an 编辑 button, so it writes through the draft like every other field
     (commitDraft copies tags along with the rest). */
  registerAction('m-tags', (el) => {
    const ref = state.drawer || (state.screen.startsWith('detail-') ? activeDetailRef() : null);
    if (!ref) { toast('先打开一项待办或日程'); return; }
    const d = state.draft || (typeof draftFor === 'function' ? draftFor(ref) : null);
    if (!d) return;
    P.openTagPicker(d.tags || [], (tags) => {
      d.tags = tags;
      render();
      toast(tags.length ? '标签已更新 · 保存后生效' : '已清除标签 · 保存后生效');
    });
  });

  /* ---------------- 4. exit layering ---------------- */
  function topScrim() {
    const all = qa('.proto-modal-scrim');
    return all.length ? all[all.length - 1] : null;
  }
  function draftDirtyState() {
    if (typeof activeEditRef === 'function' && state.drawer && state.drawerEdit && typeof draftDirty === 'function') {
      try { return draftDirty(); } catch (_) { return false; }
    }
    return false;
  }
  registerAction('exit-new', () => {
    // Desktop and phone draw different headers; "typed" is any real content in
    // the open form, so a filled phone form is protected exactly like desktop.
    const page = q('.new-page') || q('.m-app') || document;
    const candidate = q('#new-title', page)
      || q('.new-page .form-input', page)
      || q('.m-detail-scroll .m-form-input', page)
      || q('.m-form-input', page);
    const d = P.data.newDraft || {};
    const typed = !!((candidate && candidate.value) || '').trim() || !!((d.title || '').trim());
    if (!typed) { P.actions['new-cancel'](); return; }
    P.modal({
      title: '离开这张表单？',
      body: '<div class="proto-note">标题和已填字段还没有保存；离开会丢弃这次输入。</div>',
      actions: [{ label: '继续编辑' }, { label: '丢弃', primary: true, danger: true, onClick: () => P.actions['new-cancel']() }],
    });
  });
  window.addEventListener('keydown', (e) => {
    if (e.isComposing || e.keyCode === 229) return;
    if (e.key !== 'Escape') return;
    // One Escape closes exactly one layer, starting at the top. The master's
    // own Escape handler runs later in the bubble phase, so a modal is gone
    // before it decides whether to close the drawer underneath.
    const scrim = topScrim();
    if (scrim) { e.preventDefault(); e.stopPropagation(); scrim._close ? scrim._close() : scrim.remove(); return; }
    if (state.screen === 'new-todo' || state.screen === 'new-event') {
      e.preventDefault(); e.stopPropagation(); P.actions['exit-new'](); return;
    }
    if (state.drawer && state.drawerEdit) {
      const dirty = draftDirtyState();
      if (!dirty) return; // the master closes a clean editor itself
      e.preventDefault(); e.stopPropagation();
      P.modal({
        title: '放弃未保存的修改？',
        body: '<div class="proto-note">表单里的改动还没有保存；离开会回到修改前的状态。</div>',
        actions: [{ label: '继续编辑' }, { label: '放弃修改', primary: true, danger: true, onClick: () => P.actions['m-close-edit']() }],
      });
      return;
    }
  }, true);

  /* ---------------- 5. calendar: schedule an existing todo ---------------- */
  // One planner for every entry that has a concrete range: the toolbar
  // 安排待办 button, an empty calendar slot, and the slot ghost. The range is
  // the caller's (slot date + time) or, for the toolbar, the day being
  // browsed + the same default window the create sheet uses.
  P.scheduleTodo = function (opts) {
    opts = opts || {};
    const list = todoForSchedule();
    if (!list.length) { toast('没有可安排的待办'); return; }
    const day = opts.date || state.selectedDate || TODAY;
    const win = opts.start ? { start: opts.start, end: opts.end || opts.start } : defaultEventWindow(day);
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-list">${list.map((t) => `<button type="button" class="proto-list-row" data-sched="${esc(t.id)}"><span class="grow">${esc(t.title)}<small>${calOf(t.cal).name}${t.due ? ' · 截止 ' + dueText(t) : ''}${t.repeat ? ' · ' + esc(t.repeat) : ''}</small></span></button>`).join('')}</div>
      <div class="proto-note">安排只写入一段计划执行，落在 ${esc(mdShort(day))} ${win.start}–${win.end}；截止和提醒都不改。时间可以在下一步改。</div>`;
    const scrim = P.modal({ title: '安排已有待办', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-sched]');
      if (!b) return;
      const t = todoById(b.dataset.sched);
      const fromScreen = state.screen;
      const fromVariant = state.variant;
      const fromDrawer = state.drawer;
      scrim.remove();
      if (!t) return;
      const open = (occ) => {
        // The picker's own defaults (planReturn='today', planDate=TODAY,
        // 15:15) are overwritten one by one here: the slot the user clicked
        // wins over "today" for both the instance and the block written.
        state.planTodoId = t.id;
        state.planAllocId = null;
        state.planOccurrence = occ || null;
        state.planDate = opts.occurrenceDate || occ || day;
        state.planStart = win.start;
        state.planEnd = win.end;
        state.planReturn = opts.returnScreen || fromScreen;
        state.planReturnVariant = opts.returnVariant || fromVariant;
        state.planReturnDrawer = opts.returnDrawer !== undefined ? opts.returnDrawer : fromDrawer;
        state.planReturnEdit = false;
        state.screen = 'plan-picker';
        state.variant = 'normal';
        state.drawer = null;
        render();
      };
      if (t.repeat && window.DS3 && window.DS3.requireOccurrence) {
        window.DS3.requireOccurrence(t, open, { title: '安排哪一次 · ' + t.title });
        return;
      }
      open(null);
    });
    return scrim;
  };
  registerAction('cal-schedule-todo', () => {
    P.scheduleTodo({ date: state.selectedDate || TODAY, returnScreen: state.screen, returnVariant: state.variant, returnDrawer: state.drawer });
  });

  /* ---------------- 6. hide-completed preference ---------------- */
  // CORE_UX_SPEC §7: "隐藏已完成 belongs to the Todo page's display/filter
  // menu, not global Settings." The switch therefore lives in the 待办 filter
  // sheet (desktop popover and phone sheet), and the Settings row R7 added is
  // removed rather than kept as a second entry.
  function setHideCompleted(on) {
    P.data.prefs.hideCompleted = !!on;
    if (on) state.completedOpen = false;
    render();
    // A preference must survive an immediate reload; the debounced snapshot
    // would still be in flight when the page is replaced.
    try {
      const snap = P.snapshot ? P.snapshot() : null;
      if (snap) localStorage.setItem('dayspark.prototype.v1', JSON.stringify(snap));
    } catch (_) { /* storage unavailable */ }
    save();
    toast(on ? '已完成项已隐藏' : '已完成项重新显示');
  }
  P.setHideCompleted = setHideCompleted;
  registerAction('pref-hide-completed', (el) => {
    setHideCompleted(!P.data.prefs.hideCompleted);
  });
  // The row is drawn, not actioned: it is inserted into whichever filter sheet
  // the current screen has open, so both devices share one preference.
  function hideCompletedRow(mobile) {
    const on = !!P.data.prefs.hideCompleted;
    if (mobile) {
      return `<button type="button" class="m-filter-option" data-proto-action="pref-hide-completed" role="switch" aria-checked="${on}"><span class="filter-box ${on ? 'is-on' : ''}">${on ? (typeof ico === 'function' ? ico('check', 8) : '✓') : ''}</span>隐藏已完成</button>`;
    }
    return `<div class="filter-sec"><div class="filter-label">显示</div><button type="button" class="filter-option" data-proto-action="pref-hide-completed" role="switch" aria-checked="${on}"><span class="filter-box ${on ? 'is-on' : ''}">${on ? (typeof ico === 'function' ? ico('check', 8) : '✓') : ''}</span>隐藏已完成 <span class="r7-faint">${on ? '列表里不显示' : '列表里照常显示'}</span></button></div>`;
  }

  /* ---------------- 7. Chinese calendar marks ---------------- */
  // Terms and statutory holiday marks are the same facts Flutter's
  // ChineseCalendarService exposes (solar term name, 休/班 + holiday name).
  // Dates below are the 2026 calendar the demo runs on.
  const TERMS = {
    '2026-01-05': '小寒', '2026-01-20': '大寒', '2026-02-04': '立春', '2026-02-18': '雨水',
    '2026-03-05': '惊蛰', '2026-03-20': '春分', '2026-04-20': '谷雨', '2026-05-05': '立夏',
    '2026-05-21': '小满', '2026-06-05': '芒种', '2026-06-21': '夏至', '2026-07-07': '小暑',
    '2026-07-23': '大暑', '2026-08-07': '立秋', '2026-08-23': '处暑', '2026-09-07': '白露',
    '2026-09-23': '秋分', '2026-10-08': '寒露', '2026-10-23': '霜降', '2026-11-07': '立冬',
    '2026-11-22': '小雪', '2026-12-07': '大雪', '2026-12-22': '冬至',
  };
  const HOLIDAYS = {
    '2026-01-01': ['元旦', false],
    '2026-02-16': ['春节', false], '2026-02-17': ['春节', false], '2026-02-18': ['春节', false],
    '2026-02-19': ['春节', false], '2026-02-20': ['春节', false],
    '2026-04-05': ['清明', false],
    '2026-05-01': ['劳动节', false],
    '2026-06-19': ['端午', false],
    '2026-09-20': ['国庆节', true], '2026-09-25': ['中秋', false],
    '2026-10-01': ['国庆节', false], '2026-10-02': ['国庆节', false], '2026-10-03': ['国庆节', false],
  };
  P.calendarMark = function (day) {
    const term = TERMS[day];
    const hol = HOLIDAYS[day];
    if (hol) return { kind: hol[1] ? 'work' : 'rest', label: hol[1] ? '班' : '休', name: hol[0], term };
    if (term) return { kind: 'term', label: term, name: term, term };
    return null;
  };
  function markHtml(day, compact) {
    const m = P.calendarMark(day);
    if (!m) return '';
    if (m.kind === 'term') return `<span class="r7-term${compact ? ' is-compact' : ''}">${m.label}</span>`;
    return `<span class="r7-hol is-${m.kind}" title="${esc(m.name)}">${m.label}</span>`;
  }

  /* ---------------- 8. notification snooze ---------------- */
  // The system notification card gains the third action the Flutter
  // notification exposes: 延后 1 小时. The card itself stays the master's
  // (same title, same 打开/忽略), so this only appends one real button after
  // it is drawn, and the write moves the reminder — never the due date.
  function addSnoozeButton() {
    const host = q('#proto-notify-demo');
    if (!host) return;
    const acts = q('.pn-acts', host);
    if (!acts || q('[data-proto-action="notify-snooze"]', acts)) return;
    const t = todoById('report');
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = '延后 1 小时';
    b.dataset.protoAction = 'notify-snooze';
    b.dataset.id = t ? t.id : 'report';
    acts.insertBefore(b, q('[data-pn="close"]', acts));
  }
  registerAction('notify-demo-open', () => {
    const b = document.createElement('button');
    b.type = 'button';
    b.dataset.action = 'notify-test';
    b.style.display = 'none';
    document.body.appendChild(b);
    b.click();
    b.remove();
    addSnoozeButton();
  });
  registerAction('notify-snooze', (el) => {
    const id = el.dataset.id || 'report';
    const t = todoById(id);
    if (!t) { toast('这一项已经不在了'); return; }
    // Flutter snoozes the REMINDER from the current clock (home_page.dart:
    // newTime = DateTime.now().add(1 hour)), never from the due time; the due
    // date and time are not part of snoozing at all. The demo clock is
    // 15:00 on 11/20, so the re-armed reminder lands at 16:00 the same day.
    const clock = (n) => String(n).padStart(2, '0');
    const when = new Date(TODAY + 'T' + clock(Math.floor(NOW / 60)) + ':' + clock(NOW % 60) + ':00');
    when.setHours(when.getHours() + 1);
    const label = '绝对 · ' + when.getFullYear() + '-' + clock(when.getMonth() + 1) + '-' + clock(when.getDate()) + ' ' + clock(when.getHours()) + ':' + clock(when.getMinutes());
    // Snoozing re-arms the reminder; the due fields stay byte-identical.
    t.snoozedRemind = label;
    t.snoozeUntil = label.replace('绝对 · ', '');
    const host = q('#proto-notify-demo');
    if (host) host.remove();
    render();
    save();
    toast('提醒延后到 ' + clock(when.getHours()) + ':' + clock(when.getMinutes()) + ' · 截止不变');
  });

  /* The drawer is decorated as soon as it exists, not only on the next
     animation frame: every render replaces the frame, and a row that still
     looks tappable but has no handler is the exact defect this round removes. */
  function watchDrawer() {
    const frame = document.getElementById('frame');
    if (!frame || typeof MutationObserver === 'undefined') return;
    let queued = 0;
    const run = () => {
      queued = 0;
      if (state.drawer && !state.drawerEdit) decorateDrawer(frame);
    };
    const observer = new MutationObserver(() => {
      if (queued) return;
      queued = requestAnimationFrame(run);
    });
    observer.observe(frame, { childList: true, subtree: true });
    run();
  }
  if (document.readyState === 'complete') setTimeout(watchDrawer, 0);
  else window.addEventListener('load', () => setTimeout(watchDrawer, 0));
  P.refreshDrawerWiring = () => {
    const frame = document.getElementById('frame');
    if (frame) decorateDrawer(frame);
    // Same rule for the notification entry: it must be live the moment it is
    // drawn, not one animation frame later.
    qa('[data-action="notify-test"]').forEach((b) => {
      if (!b.dataset.protoAction) b.dataset.protoAction = 'notify-demo-open';
    });
  };

  /* The read-only drawer is a real editor for its frequent fields: the values
     that are drawn with a chevron must open something and write something. */
  function decorateDrawer(root) {
    if (!state.drawer || state.drawerEdit || !q('.drawer .field-list', root) || q('.drawer .form-grid', root)) return;
    /* Read-only detail rows become real direct editors. */
      const ref = state.drawer;
      const item = ref.type === 'event' ? eventById(ref.id) : todoById(ref.id);
      if (item) {
        if (ref.type === 'todo') {
          markRow(fieldRowByLabel(root, '截止'), 'direct-due', item.id);
          markRow(fieldRowByLabel(root, '优先级'), 'direct-priority', item.id);
        }
        const planRow = fieldRowByLabel(root, '计划执行');
        if (planRow && ref.type === 'todo') {
          planRow.dataset.protoAction = 'plan-row';
          planRow.dataset.id = item.id;
          planRow.classList.add('is-direct');
        }
        markRow(fieldRowByLabel(root, '重复'), 'direct-repeat', item.id);
        markRow(fieldRowByLabel(root, '提醒'), 'direct-reminder', item.id);
        markRow(fieldRowByLabel(root, '日历'), 'direct-calendar', item.id);
        // A 优先级 row on a todo with 无 priority still needs a visible value.
        const prioVal = prioRowValue(root, '优先级');
        if (prioVal && !prioVal.textContent.trim()) {
          prioVal.innerHTML = '<span class="f-chip prio-static">无</span>';
        }
        // Tag chips are the add/edit entry too, not decoration.
        // In a read-only drawer the earlier layer deliberately routes the
        // 添加 buttons through "edit first"; read-only is now a real direct
        // editor, so these buttons must write instead of dead-ending.
        qa('.d-sec-head button', root).forEach((b) => {
          const head = b.closest('.d-sec-head');
          const label = (head.textContent || '').trim();
          if (!label.startsWith('子任务') && !label.startsWith('标签')) return;
          b.dataset.protoAction = label.startsWith('子任务') ? 'direct-subtask-add' : 'direct-tags';
          b.dataset.id = item.id;
          b.dataset.reason = '';
          b.textContent = '添加';
        });
        const tagSec = qa('.d-sec', root).find((sec) => {
          const head = q('.d-sec-head', sec);
          return head && (head.textContent || '').trim().startsWith('标签');
        });
        if (tagSec) {
          qa('.tag', tagSec).forEach((chip) => {
            chip.dataset.protoAction = 'direct-tags';
            chip.dataset.id = item.id;
          });
        }
      }
  }

  /* ---------------- enhancers: wiring what the master draws ---------------- */
  registerEnhancer((root) => {
    decorateDrawer(root);
    /* Date navigation buttons are drawn by the master with a plain
       data-action; they need the prototype bridge to reach these handlers. */
    qa('.ds-step, .ds-today', root).forEach((b) => {
      if (!b.dataset.protoAction) b.dataset.protoAction = b.dataset.action;
    });

    /* Calendar needs the second half of the slot pair on every view:
       "安排已有待办" next to 新建日程 — same rule as the empty-slot ghosts. */
    if ((state.screen.startsWith('cal-') || state.screen === 'todo-date') && state.device !== 'mobile') {
      const right = q('.cal-page .ph-right', root);
      if (right && !q('[data-proto-action="cal-schedule-todo"]', right)) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'tool';
        b.dataset.protoAction = 'cal-schedule-todo';
        b.innerHTML = '<span aria-hidden="true">＋</span> 安排待办';
        const filter = q('[data-action="open-cal-filter"]', right);
        right.insertBefore(b, filter || null);
      }
    }
    /* The system notification entry and its card actions. */
    qa('[data-action="notify-test"]', root).forEach((b) => {
      if (!b.dataset.protoAction) b.dataset.protoAction = 'notify-demo-open';
    });
    if (q('#proto-notify-demo', document)) addSnoozeButton();

    /* 隐藏已完成 lives in the 待办 filter/display menu (desktop popover and
       phone sheet). Insert it before the sheet's hint/actions so it reads as
       part of "显示", and keep it out of Settings entirely.
       The phone calendar's 显示日历 sheet shares the `.m-filter-sheet` class
       but is a calendar-visibility control, not the Todo display menu, so the
       row is scoped to the Todo screens. */
    const todoScope = /^(today|todo-|detail-todo)/.test(state.screen);
    const filterPanel = q('.filter-pop', root);
    if (todoScope && filterPanel && !q('[data-proto-action="pref-hide-completed"]', filterPanel)) {
      const host = q('.filter-hint', filterPanel) || q('.filter-actions', filterPanel);
      if (host) host.insertAdjacentHTML('beforebegin', hideCompletedRow(false));
    }
    const mFilter = todoScope ? q('.m-filter-sheet', root) : null;
    if (mFilter && !q('[data-proto-action="pref-hide-completed"]', mFilter)) {
      const host = q('.filter-hint', mFilter) || q('.filter-actions', mFilter);
      if (host) host.insertAdjacentHTML('beforebegin', '<h3>显示</h3>' + hideCompletedRow(true));
    }

    /* Month cells are drawn as one big button; the mark must not swallow the
       click that opens the day. */
    if (state.screen.startsWith('cal-') || state.screen === 'todo-date' || state.screen === 'today') {
      qa('.day-head', root).forEach((head) => {
        const day = head.dataset.date;
        if (!day || q('.r7-mark', head)) return;
        const html = markHtml(day);
        if (html) head.querySelector('span') ? head.querySelector('span').insertAdjacentHTML('beforeend', `<i class="r7-mark">${html}</i>`) : 0;
      });
      qa('.mcell', root).forEach((cell) => {
        const num = q('.mnum', cell);
        const day = cell.dataset.date;
        if (!num || !day || q('.r7-mark', cell)) return;
        const html = markHtml(day);
        if (html) num.insertAdjacentHTML('afterend', `<i class="r7-mark">${html}</i>`);
      });
      qa('.m-cal-day', root).forEach((cell) => {
        const b = q('b', cell);
        const day = cell.dataset.date;
        if (!b || !day || q('.r7-mark', cell)) return;
        const html = markHtml(day);
        if (html) b.insertAdjacentHTML('afterend', `<i class="r7-mark">${html}</i>`);
      });
      qa('.m-month-cell', root).forEach((cell) => {
        const num = q('.m-month-num', cell);
        const day = cell.dataset.date;
        if (!num || !day || q('.r7-mark', cell)) return;
        const html = markHtml(day);
        if (html) num.insertAdjacentHTML('afterend', `<i class="r7-mark">${html}</i>`);
      });
      const headRow = q('.ph-title-row', root);
      if (headRow && state.screen === 'today' && !q('.r7-head-mark', root)) {
        const html = markHtml(TODAY);
        if (html) headRow.querySelector('.ph-sub').insertAdjacentHTML('beforeend', ` <span class="r7-head-mark">${html}</span>`);
      }
    }

    /* One create entry on the three core pages (and their sub-views), phone
       included. 日历 used a floating ＋ at a different place with a hard-wired
       "new event" meaning; 今天/待办 keep their capture bar for quick typing,
       which is a different, allowed affordance. The header ＋ is now the same
       control everywhere and asks the same two-choice question, so "where do I
       create things" has one answer; the floating ＋ is hidden rather than
       kept as a second entry. */
    if (state.device === 'mobile' && (/^(today|todo-(all|inbox|date)|cal-(week|month|day))$/.test(state.screen))) {
      const actions = q('.m-app .m-top .m-actions', root);
      if (actions && !q('[data-proto-action="new-pick"]', actions)) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'm-icon m-new-entry';
        b.dataset.protoAction = 'new-pick';
        b.setAttribute('aria-label', '新建');
        b.innerHTML = typeof ico === 'function' ? ico('plus', 16) : '+';
        actions.insertBefore(b, actions.firstChild);
      }
      // The screen-local floating ＋ is the same action at a second place.
      qa('.m-fab', root).forEach((f) => { f.style.display = 'none'; });
    }

    /* Completed sections honour the preference. */
    if (P.data.prefs.hideCompleted) {
      qa('.completed-group, .m-completed-group', root).forEach((el) => { el.style.display = 'none'; });
      qa('.group-head, .m-group, .more-row', root).forEach((el) => {
        const t = (el.textContent || '').trim();
        if (t.startsWith('已完成') || t.startsWith('今日已完成')) el.style.display = 'none';
      });
    }

    /* Settings: no designer-facing copy, real overview. The hide-completed
       switch is NOT here — it belongs to the Todo filter menu. */
    const section = state.screen.startsWith('settings-') ? state.screen.replace('settings-', '') : '';
    if (section === 'home') {
      const content = q('.set-content', root);
      if (content && !content.dataset.r7Overview) {
        content.dataset.r7Overview = '1';
        const live = allTodos().filter((t) => !isDone(t));
        const overdue = live.filter((t) => isOverdue(t) || t.missed).length;
        content.innerHTML = `<p class="set-desc">本地优先的日历与待办。${P.data.account.signedIn ? '已连接 ' + esc(P.data.account.server.replace(/^https?:\/\//, '')) + '，' + (P.data.account.devices || []).length + ' 台设备。' : '未登录；本地功能全部可用。'}</p>
          <div class="set-stats">
            <div class="set-stat"><b>${live.length}</b><span>项待完成</span></div>
            <div class="set-stat ${overdue ? 'is-red' : ''}"><b>${overdue}</b><span>项逾期</span></div>
            <div class="set-stat"><b>${calIds().length}</b><span>个日历</span></div>
            <div class="set-stat"><b>${(P.data.tags || []).length}</b><span>个标签</span></div>
          </div>
          ${(() => {
            // The left column already navigates every section; repeating those
            // links here was the duplicate navigation this round removes. Only
            // rows that need a decision stay, and they link to the one place
            // that resolves them.
            const rows = [];
            const conflicts = (P.data.sync && P.data.sync.conflicts) || 0;
            const rejected = (P.data.sync && P.data.sync.rejected) || 0;
            if (conflicts) rows.push(setRow('待处理的同步冲突', conflicts + ' 项需要选择保留哪一版。', '去处理', 'settings', 'sync'));
            if (rejected) rows.push(setRow('服务器拒绝的改动', rejected + ' 项没有上传成功。', '查看', 'settings', 'sync'));
            if (P.data.notify && P.data.notify.permission === 'denied') rows.push(setRow('通知权限被拒绝', '提醒不会触发；可在系统设置里重新允许。', '查看', 'settings', 'notify'));
            if (!P.data.account.signedIn) rows.push(setRow('尚未登录', '本地功能全部可用；登录后才多设备同步。', '去登录', 'settings', 'account'));
            return rows.length ? '<div class="set-group-label">需要你处理</div>' + rows.join('') : '<div class="set-group-label">需要你处理</div><div class="set-desc">没有待处理的事项。</div>';
          })()}`;
      }
    }
  });

  function prioRowValue(root, label) {
    const row = qa('.drawer .field-row', root).find((r) => {
      const l = q('.f-label', r);
      return l && (l.textContent || '').trim() === label;
    });
    return row ? q('.f-value', row) : null;
  }

})();
