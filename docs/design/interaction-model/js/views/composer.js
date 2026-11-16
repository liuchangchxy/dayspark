/* Composer: one surface for creating and editing both Todo and Event.
   Type switch is explicit; a Todo's deadline and scheduled time are separate
   fields and never merge. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  // A sheet or picker outlives one render of the composer. When the window
  // crosses a breakpoint the form is rebuilt, so callbacks captured from the
  // old closure must reach the live form instead of writing into detached DOM.
  const live = { renderBody: () => {}, validate: () => {}, autoGrow: () => {}, titleInput: null };

  // Overlaps must be judged against what the calendar draws: a repeating event
  // owns one block per occurrence, not one block at its anchor.
  function eventBlocksBetween(from, to) {
    const out = [];
    const seen = new Set();
    let d = U.startOfDay(from);
    const last = U.startOfDay(to);
    while (d <= last) {
      S.eventsOnDay(d).forEach((e) => {
        if (e.startDt >= to || e.endDt <= from) return;
        const key = e.id + ':' + e.startDt.getTime();
        if (seen.has(key)) return;
        seen.add(key);
        out.push(e);
      });
      d = U.addDays(d, 1);
    }
    return out;
  }

  function draftFromRoute() {
    const c = S.state.composer || { kind: 'todo', mode: 'create' };
    const now = U.now();
    const base = {
      kind: c.kind, mode: c.mode, id: c.id || null, parentId: c.parentId || null,
      occurrence: c.occurrence || null,
      summary: c.summary || '', notes: '',
      dueDate: c.dueDate ? new Date(c.dueDate) : null,
      startDate: null,
      priority: 0, tagIds: [], calendarId: S.state.calendars[0] ? S.state.calendars[0].id : 1,
      recurrence: null, reminderOffsets: [], attachments: [],
      startDt: c.startDt ? new Date(c.startDt) : null, endDt: c.endDt ? new Date(c.endDt) : null, isAllDay: false, location: '',
      scheduleStart: c.scheduleStart ? new Date(c.scheduleStart) : null, scheduleEnd: c.scheduleEnd ? new Date(c.scheduleEnd) : null,
      scheduleOccurrence: c.scheduleOccurrence || null,
      planDate: c.planDate ? U.startOfDay(new Date(c.planDate)) : null,
      moreOpen: false, focus: c.focus || null,
      // CORE_UX_SPEC 4.2: a new Todo opens as Quick Create. The full five
      // sections are one 更多 away, not the first thing the user has to read.
      quick: c.mode !== 'edit' && (c.kind || 'todo') === 'todo',
      // Editing an existing record already has a title; a fresh form has not
      // been touched yet and must not be greeted with an error.
      touched: c.mode === 'edit',
    };
    if (c.mode === 'edit') {
      if (c.kind === 'todo') {
        const todo = S.todoById(c.id);
        if (!todo) return base;
        Object.assign(base, {
          summary: todo.summary, notes: todo.description || '', dueDate: todo.dueDate ? new Date(todo.dueDate) : null,
          startDate: todo.startDate ? new Date(todo.startDate) : null, priority: todo.priority, tagIds: todo.tagIds.slice(),
          calendarId: todo.calendarId, recurrence: todo.recurrence,
          reminderOffsets: todo.reminderOffsets.slice(), attachments: todo.attachments.slice(),
          parentId: todo.parentId,
          statusDone: S.isDone(todo),
        });
        const allocs = S.allocationsForTodo(todo.id).filter(S.isAllocationLive);
        if (allocs.length) {
          base.scheduleStart = new Date(allocs[0].startAt); base.scheduleEnd = new Date(allocs[0].endAt);
          base.scheduleAllocId = allocs[0].id;
          base.scheduleOccurrence = allocs[0].occurrenceId || null;
        }
      } else {
        const series = S.eventById(c.id);
        if (!series) return base;
        // Editing one occurrence edits that occurrence, not the series base.
        const occStart = c.occurrence ? new Date(c.occurrence) : new Date(series.startDt);
        const occEnd = c.occurrence
          ? new Date(c.occurrence + (series.endDt - series.startDt))
          : new Date(series.endDt);
        Object.assign(base, {
          summary: series.summary, notes: series.description || '', startDt: occStart, endDt: occEnd,
          isAllDay: series.isAllDay, location: series.location || '', calendarId: series.calendarId,
          recurrence: c.occurrence ? (c.scope === 'future' ? series.rrule : null) : series.rrule,
          reminderOffsets: (series.reminderOffsets || []).slice(), tagIds: (series.tagIds || []).slice(),
        });
      }
    } else {
      if (base.kind === 'event') {
        base.startDt = base.startDt || (() => {
          const s = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
          // The early hours are folded by default; landing a new event inside
          // the fold would create it where the user cannot see it.
          if (s.getHours() < 8) s.setHours(8, 0, 0, 0);
          return s;
        })();
        base.endDt = base.endDt || U.addMinutes(base.startDt, 60);
      }
      // "Plan this day" starts from a date, not from a deadline: it reserves a
      // slot on that day and leaves the deadline empty (no invented dueDate).
      if (base.planDate && base.kind === 'todo') {
        const planNow = U.now();
        const planToday = U.startOfDay(planNow);
        const planDay = U.startOfDay(base.planDate);
        // Planning never pre-fills a slot that has already passed: a past day
        // gets no slot at all, and late evening on today has no future hour.
        let planHour = null;
        if (planDay < planToday) planHour = null;
        else if (planDay.getTime() === planToday.getTime()) {
          if (planNow.getHours() < 9) planHour = 9;
          else if (planNow.getHours() < 23) planHour = planNow.getHours() + 1;
        } else planHour = 9;
        if (planHour !== null) {
          base.scheduleStart = base.scheduleStart
            || new Date(planDay.getFullYear(), planDay.getMonth(), planDay.getDate(), planHour, 0);
          base.scheduleEnd = base.scheduleEnd || U.addMinutes(base.scheduleStart, 60);
        }
      }
    }
    return base;
  }

  function composer() {
    const c = S.state.composer || {};
    // A render replaces #view, so the draft must live in state, not in this
    // closure: resizing across a breakpoint or a theme emit must not wipe a
    // half-typed form (or silently disarm its discard guard).
    const routeKey = JSON.stringify(c);
    const draft = (S.state.composerDraft && S.state.composerDraft._routeKey === routeKey)
      ? S.state.composerDraft
      : draftFromRoute();
    draft._routeKey = routeKey;
    S.state.composerDraft = draft;
    let dirty = !!draft.dirty;
    const isEdit = draft.mode === 'edit';
    const narrow = U.isNarrow();

    const root = U.el('div', { class: 'composer', 'data-testid': 'composer' });

    function markDirty() { dirty = true; draft.dirty = true; }

    function askDiscard() {
      return UI.confirm({
        title: t('discardTitle'), message: t('discardBody'),
        confirmText: t('discard'), cancelText: t('keepEditing'), danger: true,
      });
    }
    function closeComposer(force) {
      if (dirty && !force) {
        askDiscard().then((ok) => { if (ok) leave(); });
        return;
      }
      leave();
    }
    // Any navigation away from the composer (rail, bottom nav, shortcuts) goes
    // through the same question as Esc, so a draft cannot be dropped silently.
    App.leaveGuard = () => {
      if (!dirty) return Promise.resolve(true);
      return askDiscard().then((ok) => {
        // The guard has already asked; clearing the local flag keeps the page's
        // own escape handler from asking the same question a second time when
        // browser Back walks the ladder after the guard resolves.
        if (ok) { dirty = false; S.state.composer = null; S.state.composerDraft = null; }
        return ok;
      });
    };
    function leave() {
      S.state.composer = null;
      S.state.composerDraft = null;
      App.back();
    }

    const head = U.el('div', { class: 'composer-head' });
    const close = UI.iconButton(narrow ? 'chevronLeft' : 'x', t('cancel'), () => closeComposer());
    close.dataset.testid = 'composer-close';
    head.appendChild(close);
    head.appendChild(U.el('span', {
      class: 'title',
      text: isEdit ? (draft.kind === 'todo' ? t('composerEditTodo') : t('composerEditEvent')) : (draft.kind === 'todo' ? t('composerNewTodo') : t('composerNewEvent')),
    }));
    const saveTop = U.el('button', { class: 'btn primary', text: t('save'), 'data-testid': 'composer-save' });
    saveTop.addEventListener('click', () => save(true));
    if (!narrow) head.appendChild(saveTop);
    root.appendChild(head);

    const body = U.el('div', { class: 'composer-body' });
    root.appendChild(body);

    const titleInput = U.el('textarea', {
      class: 'composer-title-input', rows: '1',
      placeholder: draft.kind === 'todo' ? t('titlePlaceholderTodo') : t('titlePlaceholderEvent'),
      'aria-label': t('title'), 'data-testid': 'composer-title',
    });
    titleInput.value = draft.summary;
    titleInput.addEventListener('input', () => {
      draft.summary = titleInput.value;
      draft.touched = true;
      markDirty();
      autoGrow(titleInput);
      live.validate();
    });
    titleInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !U.isNarrow()) {
        e.preventDefault();
        if (draft.kind === 'todo') save(true);
      }
    });
    body.appendChild(titleInput);

    // A one-line parse is a faster path into the same draft, not a second form.
    if (!draft.planDate) {
      const parseBtn = U.el('button', { class: 'chip-btn', 'data-testid': 'composer-ai-parse' });
      parseBtn.innerHTML = ICON('sparkles', 12) + `<span>${U.esc(t('aiParse'))}</span>`;
      parseBtn.addEventListener('click', () => aiParseSheet());
      const parseRow = U.el('div', { class: 'chip-row', style: 'margin:8px 0 2px' });
      parseRow.appendChild(parseBtn);
      body.appendChild(parseRow);
    }

    const errBox = U.el('div', { class: 'hint-box error', hidden: 'hidden', role: 'alert' });
    body.appendChild(errBox);

    const typeRow = U.el('div', { class: 'composer-type' });
    const typeSeg = U.el('div', { class: 'segmented lg' });
    if (isEdit) {
      // The type is a fact once the record exists. Rendering enabled buttons
      // that do nothing is a control that lies about what it can do.
      const fact = U.el('div', { class: 'chip' });
      fact.dataset.testid = 'composer-type-fact';
      fact.innerHTML = (draft.kind === 'todo' ? ICON('checkSquare', 13) : ICON('calendar', 13)) +
        `<span>${U.esc(draft.kind === 'todo' ? t('typeTodo') : t('typeEvent'))}</span>`;
      typeRow.appendChild(fact);
    } else {
      [['todo', t('typeTodo'), 'checkSquare'], ['event', t('typeEvent'), 'calendar']].forEach(([k, label, icon]) => {
        const b = U.el('button', { class: draft.kind === k ? 'on' : '', 'aria-pressed': draft.kind === k ? 'true' : 'false' });
        b.innerHTML = ICON(icon, 14) + `<span>${U.esc(label)}</span>`;
        b.dataset.testid = 'composer-type-' + k;
        b.addEventListener('click', () => {
          if (draft.kind === k) return;
          draft.kind = k;
          markDirty();
          if (k === 'event' && !draft.startDt) {
            const now = U.now();
            const s = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
            if (s.getHours() < 8) s.setHours(8, 0, 0, 0);
            draft.startDt = s;
            draft.endDt = U.addMinutes(draft.startDt, 60);
          }
          live.renderBody();
        });
        typeSeg.appendChild(b);
      });
      typeRow.appendChild(typeSeg);
    }
    typeRow.appendChild(U.el('div', { class: 'type-hint', text: draft.kind === 'todo' ? t('typeHintTodo') : t('typeHintEvent') }));
    body.appendChild(typeRow);

    const formHost = U.el('div');
    body.appendChild(formHost);

    const foot = U.el('div', { class: 'composer-foot' });
    const cancelBtn = U.el('button', { class: 'btn ghost lg', text: t('cancel') });
    cancelBtn.addEventListener('click', () => closeComposer());
    foot.appendChild(cancelBtn);
    foot.appendChild(U.el('span', { class: 'spacer' }));
    if (isEdit && draft.kind === 'todo') {
      const del = U.el('button', { class: 'btn danger-ghost lg', text: t('moveToTrash') });
      del.addEventListener('click', () => {
        UI.confirm({ title: t('moveToTrash'), message: t('moveToTrashBody', { t: draft.summary }), danger: true, confirmText: t('moveToTrash') }).then((ok) => {
          if (!ok) return;
          const id = draft.id;
          S.softDeleteTodo(id);
          dirty = false;
          leave();
          App.render();
          UI.toast(t('deletedToast', { t: draft.summary }), { undo: () => { S.restoreTodo(id); App.render(); } });
        });
      });
      foot.appendChild(del);
    }
    const saveBtn = U.el('button', { class: 'btn primary lg', text: t('save'), 'data-testid': narrow ? 'composer-save' : 'composer-save-foot' });
    saveBtn.addEventListener('click', () => save(true));
    foot.appendChild(saveBtn);
    root.appendChild(foot);

    // A failed write keeps the draft and offers the retry in place. Telling the
    // user "save failed" and closing the sheet would discard their work.
    const saveErr = U.el('div', { class: 'save-error', hidden: 'hidden', role: 'alert', 'data-testid': 'composer-save-error' });
    root.appendChild(saveErr);

    // ---------- fields ----------
    function row(label, control, tail) {
      const r = U.el('div', { class: 'form-row' });
      if (label) r.appendChild(U.el('span', { class: 'label', text: label }));
      const ctrl = U.el('div', { class: 'control' });
      if (Array.isArray(control)) control.forEach((c) => ctrl.appendChild(c));
      else ctrl.appendChild(control);
      r.appendChild(ctrl);
      if (tail) r.appendChild(tail);
      return r;
    }

    function pillButton(icon, label, onClick, testid) {
      const b = U.el('button', { class: 'chip-btn' });
      if (testid) b.dataset.testid = testid;
      b.innerHTML = ICON(icon, 13) + `<span>${U.esc(label)}</span>`;
      b.addEventListener('click', onClick);
      return b;
    }

    function renderQuick() {
      const sec = section(formHost, t('sectionTask'));
      const deadlineBtn = pillButton('flag', draft.dueDate ? U.fmtDeadline(draft.dueDate) : t('noDeadline'), () => deadlinePicker(), 'composer-deadline');
      deadlineBtn.classList.toggle('on', !!draft.dueDate);
      const dueClear = draft.dueDate ? U.el('button', { class: 'icon-btn sm', 'aria-label': t('clear'), html: ICON('x', 13) }) : null;
      if (dueClear) dueClear.addEventListener('click', () => { draft.dueDate = null; markDirty(); live.renderBody(); live.validate(); });
      sec.appendChild(row(t('deadline'), [deadlineBtn, dueClear].filter(Boolean)));
      if (S.state.calendars.length > 1) {
        sec.appendChild(row(t('ownCalendar'), UI.calendarPicker(draft.calendarId, (id) => {
          draft.calendarId = id;
          markDirty();
          live.renderBody(); live.validate();
        })));
      }
      if (draft.scheduleStart) {
        const schBtn = pillButton('clockPlus', U.fmtMonthDayTime(draft.scheduleStart) + ' – ' + U.fmtTime(draft.scheduleEnd), () => schedulePicker(), 'composer-schedule');
        schBtn.classList.add('on');
        const schClear = U.el('button', { class: 'icon-btn sm', 'aria-label': t('clear'), html: ICON('x', 13) });
        schClear.addEventListener('click', () => {
          draft.scheduleStart = null; draft.scheduleEnd = null; markDirty(); live.renderBody(); live.validate();
        });
        sec.appendChild(row(t('scheduleExec'), [schBtn, schClear]));
      }
      const more = U.el('button', { class: 'chip-btn', 'data-testid': 'composer-more' });
      more.innerHTML = ICON('chevronDown', 13) + `<span>${U.esc(t('more'))}</span>`;
      more.addEventListener('click', () => { draft.quick = false; live.renderBody(); live.validate(); });
      const moreRow = U.el('div', { class: 'form-row' });
      const moreCtrl = U.el('div', { class: 'control' });
      moreCtrl.appendChild(more);
      moreRow.appendChild(moreCtrl);
      sec.appendChild(moreRow);
    }

    // CORE_UX_SPEC 4.2: the same section order everywhere — 任务 / 时间 / 提醒 /
    // 整理 / 内容. One flat run of fields makes 重复 look unrelated to 时间 and
    // buries 提醒, so the groups are explicit and each one is labelled.
    function section(parent, title) {
      const s = U.el('div', { class: 'form-section' });
      s.appendChild(U.el('div', { class: 'form-section-title', text: title }));
      parent.appendChild(s);
      return s;
    }

    function renderBody() {
      formHost.innerHTML = '';
      if (draft.kind === 'todo' && draft.quick && !isEdit) { renderQuick(); return; }
      const dueBtn = null;
      const block = U.el('div', { class: 'form-block' });

      if (draft.kind === 'todo') {
        // ---------- 任务 ----------
        const taskSec = section(formHost, t('sectionTask'));
        if (isEdit && !draft.recurrence) {
          const doneSeg = U.el('div', { class: 'segmented' });
          [[false, t('markComplete')], [true, t('completed')]].forEach(([val, label]) => {
            const b = U.el('button', { class: draft.statusDone === val ? 'on' : '', text: label });
            b.dataset.testid = 'composer-status-' + (val ? 'done' : 'open');
            b.addEventListener('click', () => { draft.statusDone = val; markDirty(); live.renderBody(); });
            doneSeg.appendChild(b);
          });
          taskSec.appendChild(row(t('status'), doneSeg));
        }

        // ---------- 时间 ----------
        const timeSec = section(formHost, t('sectionTime'));
        const deadlineBtn = pillButton('flag', draft.dueDate ? U.fmtDeadline(draft.dueDate) : t('noDeadline'), () => deadlinePicker(), 'composer-deadline');
        deadlineBtn.classList.toggle('on', !!draft.dueDate);
        const dueClear = draft.dueDate ? U.el('button', { class: 'icon-btn sm', 'aria-label': t('clear'), html: ICON('x', 13) }) : null;
        if (dueClear) dueClear.addEventListener('click', () => { draft.dueDate = null; markDirty(); live.renderBody(); live.validate(); });
        timeSec.appendChild(row(t('deadline'), [deadlineBtn, dueClear].filter(Boolean)));

        const recBtn = U.el('button', { class: 'chip-btn' + (draft.recurrence ? ' on' : '') });
        recBtn.dataset.testid = 'composer-repeat';
        recBtn.innerHTML = ICON('repeat', 13) + `<span>${U.esc(UI.ruleSummary(draft.recurrence))}</span>`;
        recBtn.addEventListener('click', () => repeatPicker());
        timeSec.appendChild(row(t('repeat'), recBtn));
        if (draft.recurrence) {
          timeSec.appendChild(U.el('div', { class: 'field-hint', style: 'padding-left:66px', text: t('repeatHint') }));
        }

        const schBtn = pillButton('clockPlus', draft.scheduleStart ? U.fmtMonthDayTime(draft.scheduleStart) + ' – ' + U.fmtTime(draft.scheduleEnd) : t('addSchedule'), () => schedulePicker(), 'composer-schedule');
        schBtn.classList.toggle('on', !!draft.scheduleStart);
        const schClear = draft.scheduleStart ? U.el('button', { class: 'icon-btn sm', 'aria-label': t('clear'), html: ICON('x', 13) }) : null;
        if (schClear) schClear.addEventListener('click', () => {
          draft.scheduleStart = null; draft.scheduleEnd = null; markDirty(); live.renderBody(); live.validate();
        });
        timeSec.appendChild(row(t('scheduleExec'), [schBtn, schClear].filter(Boolean)));
        timeSec.appendChild(U.el('div', { class: 'field-hint', style: 'padding-left:66px', text: t('scheduleHint') }));

        // ---------- 提醒 ----------
        renderReminderSection(section(formHost, t('sectionReminder')));

        // ---------- 整理 ----------
        const orgSec = section(formHost, t('sectionOrganize'));
        orgSec.appendChild(row(t('ownCalendar'), UI.calendarPicker(draft.calendarId, (id) => {
          draft.calendarId = id;
          markDirty();
          live.renderBody(); live.validate();
        })));
        const prio = U.el('div', { class: 'segmented' });
        [[0, t('noPriority')], [1, t('low')], [5, t('medium')], [9, t('high')]].forEach(([val, label]) => {
          const b = U.el('button', { class: draft.priority === val ? 'on' : '', text: label, 'aria-pressed': draft.priority === val ? 'true' : 'false' });
          b.dataset.testid = 'composer-priority-' + val;
          b.addEventListener('click', () => { draft.priority = val; markDirty(); live.renderBody(); });
          prio.appendChild(b);
        });
        orgSec.appendChild(row(t('priority'), prio));
        const tagWrap = U.el('div', { class: 'chip-row' });
        S.state.tags.forEach((tag) => {
          const on = draft.tagIds.includes(tag.id);
          const b = U.el('button', { class: 'chip-btn' + (on ? ' on' : '') });
          b.dataset.testid = 'composer-tag-' + tag.id;
          b.innerHTML = `<span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}`;
          b.setAttribute('aria-pressed', on ? 'true' : 'false');
          b.addEventListener('click', () => {
            draft.tagIds = on ? draft.tagIds.filter((x) => x !== tag.id) : draft.tagIds.concat(tag.id);
            markDirty(); live.renderBody(); live.validate();
          });
          tagWrap.appendChild(b);
        });
        orgSec.appendChild(row(t('tags'), tagWrap));

        // ---------- 内容 ----------
        renderContentSection();
      } else {
        // ---------- 时间 ----------
        const timeSec = section(formHost, t('sectionTime'));
        const allday = U.el('div', { class: 'segmented' });
        [[false, S.state.lang === 'zh' ? '定时' : 'Timed'], [true, t('allDay')]].forEach(([val, label]) => {
          const b = U.el('button', { class: draft.isAllDay === val ? 'on' : '', text: label, 'aria-pressed': draft.isAllDay === val ? 'true' : 'false' });
          b.dataset.testid = 'composer-allday-' + (val ? 'on' : 'off');
          b.addEventListener('click', () => {
            draft.isAllDay = val;
            if (val) {
              // Keep the number of days already chosen, including a multi-day
              // span, instead of resetting the end to the start day.
              const spanDays = Math.max(0, Math.round((U.startOfDay(draft.endDt) - U.startOfDay(draft.startDt)) / U.MS_DAY));
              draft.startDt.setHours(0, 0, 0, 0);
              draft.endDt = new Date(draft.startDt.getFullYear(), draft.startDt.getMonth(), draft.startDt.getDate() + spanDays, 23, 59);
            } else { draft.startDt.setHours(9, 0, 0, 0); draft.endDt = U.addMinutes(draft.startDt, 60); }
            markDirty(); live.renderBody(); live.validate();
          });
          allday.appendChild(b);
        });
        timeSec.appendChild(row(t('allDay'), allday));

        // A repeating Event is a first-class record (the series/occurrence
        // rules are already implemented); the form must expose its rule.
        const recBtn = U.el('button', { class: 'chip-btn' + (draft.recurrence ? ' on' : '') });
        recBtn.dataset.testid = 'composer-repeat';
        recBtn.innerHTML = ICON('repeat', 13) + `<span>${U.esc(UI.ruleSummary(draft.recurrence))}</span>`;
        recBtn.addEventListener('click', () => repeatPicker());
        timeSec.appendChild(row(t('repeat'), recBtn));
        if (draft.recurrence) {
          timeSec.appendChild(U.el('div', { class: 'field-hint', style: 'padding-left:66px', text: t('repeatHint') }));
        }

        const dateInput = U.el('input', { class: 'input', type: 'date', value: U.toInputDate(draft.startDt), 'aria-label': t('starts') });
        dateInput.dataset.testid = 'composer-start-date';
        dateInput.addEventListener('change', () => {
          const d = U.fromInputDate(dateInput.value);
          if (!d) return;
          const dur = draft.endDt - draft.startDt;
          // An all-day event may span several days. Changing its start moves
          // the whole span; collapsing it to one day would silently rewrite the
          // record the user is editing.
          const spanDays = Math.max(0, Math.round((U.startOfDay(draft.endDt) - U.startOfDay(draft.startDt)) / U.MS_DAY));
          const sh = draft.startDt.getHours(), sm = draft.startDt.getMinutes();
          draft.startDt = new Date(d.getFullYear(), d.getMonth(), d.getDate(), draft.isAllDay ? 0 : sh, draft.isAllDay ? 0 : sm);
          draft.endDt = draft.isAllDay
            ? new Date(d.getFullYear(), d.getMonth(), d.getDate() + spanDays, 23, 59)
            : new Date(draft.startDt.getTime() + dur);
          markDirty(); live.renderBody(); live.validate();
        });
        timeSec.appendChild(row(t('starts'), dateInput));

        const endDateInput = U.el('input', { class: 'input', type: 'date', value: U.toInputDate(draft.endDt), 'aria-label': t('ends') });
        endDateInput.dataset.testid = 'composer-end-date';
        endDateInput.addEventListener('change', () => {
          const d = U.fromInputDate(endDateInput.value);
          if (!d) return;
          // The end date is real: an event may end on another day, and rebuilt
          // on the start's date it could never describe 23:00 → 01:00.
          draft.endDt = draft.isAllDay
            ? new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59)
            : new Date(d.getFullYear(), d.getMonth(), d.getDate(), draft.endDt.getHours(), draft.endDt.getMinutes());
          markDirty(); live.validate();
        });

        if (!draft.isAllDay) {
          const t1 = U.el('input', { class: 'input', type: 'time', value: U.fmtTime(draft.startDt), 'aria-label': t('starts') });
          const t2 = U.el('input', { class: 'input', type: 'time', value: U.fmtTime(draft.endDt), 'aria-label': t('ends') });
          t1.dataset.testid = 'composer-start-time';
          t2.dataset.testid = 'composer-end-time';
          const applyTimes = () => {
            const [h1, m1] = t1.value.split(':').map(Number);
            const [h2, m2] = t2.value.split(':').map(Number);
            if (isNaN(h1) || isNaN(h2)) return;
            const s = new Date(draft.startDt.getFullYear(), draft.startDt.getMonth(), draft.startDt.getDate(), h1, m1 || 0);
            const e = new Date(draft.endDt.getFullYear(), draft.endDt.getMonth(), draft.endDt.getDate(), h2, m2 || 0);
            draft.startDt = s;
            draft.endDt = e;
            markDirty(); live.validate();
          };
          t1.addEventListener('change', applyTimes);
          t2.addEventListener('change', applyTimes);
          const timeRow = U.el('div', { class: 'input-row' });
          timeRow.appendChild(t1);
          timeRow.appendChild(U.el('span', { class: 'muted', text: '–' }));
          timeRow.appendChild(t2);
          timeSec.appendChild(row(t('ends'), timeRow));
          timeSec.appendChild(row(t('endDate'), endDateInput));
        } else {
          timeSec.appendChild(row(t('endDate'), endDateInput));
        }

        // ---------- 提醒 ----------
        renderReminderSection(section(formHost, t('sectionReminder')));

        // ---------- 整理 ----------
        const orgSec = section(formHost, t('sectionOrganize'));
        orgSec.appendChild(row(t('ownCalendar'), UI.calendarPicker(draft.calendarId, (id) => {
          draft.calendarId = id;
          markDirty();
          live.renderBody(); live.validate();
        })));
        const tagWrap = U.el('div', { class: 'chip-row' });
        S.state.tags.forEach((tag) => {
          const on = draft.tagIds.includes(tag.id);
          const b = U.el('button', { class: 'chip-btn' + (on ? ' on' : '') });
          b.dataset.testid = 'composer-tag-' + tag.id;
          b.innerHTML = `<span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}`;
          b.setAttribute('aria-pressed', on ? 'true' : 'false');
          b.addEventListener('click', () => {
            draft.tagIds = on ? draft.tagIds.filter((x) => x !== tag.id) : draft.tagIds.concat(tag.id);
            markDirty(); live.renderBody(); live.validate();
          });
          tagWrap.appendChild(b);
        });
        orgSec.appendChild(row(t('tags'), tagWrap));

        // ---------- 内容 ----------
        renderContentSection();
      }

      formHost.appendChild(block);

      if (draft.focus === 'deadline' && draft.kind === 'todo') { draft.focus = null; setTimeout(() => deadlinePicker(), 60); }
      if (draft.focus === 'schedule' && draft.kind === 'todo') { draft.focus = null; setTimeout(() => schedulePicker(), 60); }
      if (draft.focus === 'repeat') { draft.focus = null; setTimeout(() => repeatPicker(), 60); }
    }

    // 内容 is the same for both types: an event adds 地点 at the top.
    function renderContentSection() {
      const sec = section(formHost, t('sectionContent'));
      if (draft.kind === 'event') {
        const loc = U.el('input', { class: 'input', placeholder: t('location'), value: draft.location, 'aria-label': t('location') });
        loc.dataset.testid = 'composer-location';
        loc.addEventListener('input', () => { draft.location = loc.value; markDirty(); });
        sec.appendChild(row(t('location'), loc));
      }
      const notes = U.el('textarea', { class: 'textarea', placeholder: t('notesPlaceholder'), 'aria-label': t('notes'), rows: '3' });
      notes.dataset.testid = 'composer-notes';
      notes.value = draft.notes || '';
      notes.addEventListener('input', () => { draft.notes = notes.value; markDirty(); });
      sec.appendChild(U.el('div', { class: 'field-label', text: t('notes') }));
      sec.appendChild(notes);

      // Subtasks belong in the form as well as the detail: a parent whose
      // children only exist in one of the two surfaces is a hidden capability.
      if (draft.kind === 'todo' && isEdit && !draft.parentId) {
        const wrap = U.el('div', { class: 'chip-row', 'data-testid': 'composer-subtasks' });
        const subs = S.subtasksOf(draft.id);
        subs.forEach((s) => {
          const chip = U.el('span', { class: 'chip' });
          chip.innerHTML = ICON('list', 11) + `<span>${U.esc(s.summary)}</span>`;
          wrap.appendChild(chip);
        });
        const addSub = U.el('button', { class: 'chip-btn', 'data-testid': 'composer-add-subtask' });
        addSub.innerHTML = ICON('plus', 12) + `<span>${U.esc(t('addSubtask'))}</span>`;
        addSub.addEventListener('click', () => {
          const parentId = draft.id;
          // Adding a child is not a reason to lose the parent's edits: save the
          // parent first (validation still applies), then open the child form.
          if (dirty) { save(true, parentId); return; }
          S.state.composer = null;
          S.state.composerDraft = null;
          App.openComposer('todo', { parentId });
        });
        wrap.appendChild(addSub);
        sec.appendChild(row(t('subtasks'), wrap));
      }

      const attachWrap = U.el('div', { class: 'chip-row' });
      draft.attachments.forEach((a, i) => {
        const chip = U.el('span', { class: 'chip' });
        chip.innerHTML = ICON('paperclip', 11) + `<span>${U.esc(a)}</span>`;
        const x = U.el('button', { class: 'icon-btn sm', style: 'width:16px;height:16px', 'aria-label': t('remove'), html: ICON('x', 10) });
        x.addEventListener('click', () => { draft.attachments.splice(i, 1); markDirty(); live.renderBody(); });
        chip.appendChild(x);
        attachWrap.appendChild(chip);
      });
      const addAttach = U.el('button', { class: 'chip-btn' });
      addAttach.innerHTML = ICON('paperclip', 12) + `<span>${U.esc(t('attachments'))}</span>`;
      addAttach.addEventListener('click', () => {
        const input = document.createElement('input');
        input.type = 'file';
        input.multiple = true;
        input.addEventListener('change', () => {
          Array.from(input.files || []).forEach((f) => draft.attachments.push(f.name));
          markDirty(); live.renderBody();
        });
        input.click();
      });
      attachWrap.appendChild(addAttach);
      sec.appendChild(row(t('attachments'), attachWrap));
    }

    function renderReminderSection(sec) {
      const remWrap = U.el('div', { class: 'chip-row' });
      const offsets = draft.reminderOffsets;
      offsets.forEach((min, idx) => {
        const chip = U.el('span', { class: 'chip amber' });
        chip.innerHTML = `${ICON('bell', 11)}<span>${U.esc(reminderLabel(min))}</span>`;
        const x = U.el('button', { class: 'icon-btn sm', style: 'width:16px;height:16px', 'aria-label': t('remove'), html: ICON('x', 10) });
        x.addEventListener('click', () => { offsets.splice(idx, 1); markDirty(); live.renderBody(); });
        chip.appendChild(x);
        remWrap.appendChild(chip);
      });
      const addRem = U.el('button', { class: 'chip-btn', 'data-testid': 'composer-add-reminder' });
      addRem.innerHTML = ICON('plus', 12) + `<span>${U.esc(t('addReminder'))}</span>`;
      addRem.addEventListener('click', () => {
        UI.sheet({
          title: t('addReminder'),
          body(host, close) {
            [[0, t('onStart')], [5, '5 ' + t('minutesBefore')], [15, '15 ' + t('minutesBefore')], [30, '30 ' + t('minutesBefore')], [60, '1 ' + t('hoursBefore')], [1440, '1 ' + t('daysBefore')]].forEach(([v, label]) => {
              const b = U.el('button', { class: 'slot-sheet-option' });
              b.innerHTML = `<span class="ico">${ICON('bell', 16)}</span><span><span class="t">${U.esc(label)}</span></span>`;
              b.addEventListener('click', () => { offsets.push(v); offsets.sort((a, b) => a - b); markDirty(); close(null); live.renderBody(); live.validate(); });
              host.appendChild(b);
            });
          },
        });
      });
      remWrap.appendChild(addRem);
      sec.appendChild(row(t('reminder'), remWrap));
    }


    function reminderLabel(min) {
      if (min === 0) return t('onStart');
      if (min < 60) return min + ' ' + t('minutesBefore');
      if (min < 1440) return (min / 60) + ' ' + t('hoursBefore');
      return (min / 1440) + ' ' + t('daysBefore');
    }

    // A quick chip's label names the instant it will write. "今天" was hard-coded
    // next to a value that rolls to tomorrow after 23:00, and "本周" could land
    // in the following week, so the button and the value disagreed.
    function chipDayLabel(d) {
      const now = U.now();
      if (U.sameDay(d, now)) return t('today');
      if (U.sameDay(d, U.addDays(U.startOfDay(now), 1))) return t('tomorrow');
      return U.fmtMonthDay(d);
    }

    // ---------- pickers ----------
    function deadlinePicker() {
      UI.sheet({
        title: t('deadline'),
        subtitle: t('scheduleHint'),
        body(host, close) {
          const quick = U.el('div', { class: 'picker' });
          const now = U.now();
          const today = U.startOfDay(now);
          // Every chip writes a future instant, and its label says which one.
          // Fixed 18:00 values used to write a past deadline after 18:00, and a
          // "this week" Saturday could already be behind the clock.
          const at = (dayOffset, h) => new Date(today.getFullYear(), today.getMonth(), today.getDate() + dayOffset, h, 0);
          let todayDue = at(0, 18);
          if (todayDue <= now) {
            if (now.getHours() >= 23) {
              todayDue = at(1, 18);
            } else {
              todayDue = new Date(now.getTime());
              todayDue.setMinutes(0, 0, 0);
              todayDue.setHours(todayDue.getHours() + 1);
            }
          }
          let saturday = at((6 - today.getDay() + 7) % 7, 18);
          if (saturday <= now) saturday = at((6 - today.getDay() + 7) % 7 + 7, 18);
          const tomorrow = at(1, 18);
          const nextWeek = at(7, 18);
          const options = [
            { label: chipDayLabel(todayDue) + ' ' + U.fmtTime(todayDue), value: todayDue },
            { label: chipDayLabel(tomorrow) + ' ' + U.fmtTime(tomorrow), value: tomorrow },
            { label: chipDayLabel(saturday) + ' ' + U.fmtTime(saturday), value: saturday },
            { label: t('nextWeek') + ' ' + U.fmtMonthDay(nextWeek) + ' ' + U.fmtTime(nextWeek), value: nextWeek },
          ];
          const qRow = U.el('div', { class: 'quick' });
          options.forEach((o) => {
            const b = U.el('button', { class: 'chip-btn', text: o.label });
            b.dataset.testid = 'deadline-quick';
            b.addEventListener('click', () => { draft.dueDate = o.value; markDirty(); close(null); live.renderBody(); live.validate(); });
            qRow.appendChild(b);
          });
          quick.appendChild(qRow);

          const row2 = U.el('div', { class: 'row2' });
          const date = U.el('input', { class: 'input', type: 'date', value: U.toInputDate(draft.dueDate || today) });
          date.dataset.testid = 'deadline-date';
          const time = U.el('input', { class: 'input', type: 'time', value: draft.dueDate ? U.fmtTime(draft.dueDate) : '' });
          time.dataset.testid = 'deadline-time';
          row2.appendChild(date); row2.appendChild(time);
          quick.appendChild(row2);
          quick.appendChild(U.el('div', { class: 'field-hint', text: S.state.lang === 'zh' ? '留空时间表示只有日期，不会显示 00:00。' : 'Leave the time empty for a date-only deadline.' }));

          const actions = U.el('div', { class: 'input-row' });
          const clear = U.el('button', { class: 'btn ghost', text: t('noDeadline') });
          clear.addEventListener('click', () => { draft.dueDate = null; markDirty(); close(null); live.renderBody(); live.validate(); });
          const apply = U.el('button', { class: 'btn primary', text: t('apply') });
          apply.dataset.testid = 'deadline-apply';
          apply.addEventListener('click', () => {
            const d = U.fromInputDate(date.value);
            if (!d) return;
            if (time.value) {
              const [h, m] = time.value.split(':').map(Number);
              d.setHours(h, m || 0, 0, 0);
            }
            draft.dueDate = d;
            markDirty(); close(null); live.renderBody(); live.validate();
          });
          actions.appendChild(clear); actions.appendChild(apply);
          quick.appendChild(actions);
          host.appendChild(quick);
        },
      });
    }

    function schedulePicker() {
      const today = U.startOfDay(U.now());
      const baseStart = draft.scheduleStart || (() => {
        const now = U.now();
        return new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
      })();
      UI.sheet({
        title: t('scheduleExec'),
        subtitle: t('scheduleHint'),
        body(host, close) {
          const box = U.el('div', { class: 'picker' });
          let occStub = null;
          // The occurrence follows the planned day (E6): the select is a view of
          // that derivation, not a second source of truth.
          function syncOccurrence(occSel, value) {
            if (!occSel || !occStub || !value) return;
            const s = U.fromInputDateTime(value);
            if (!s) return;
            const day = U.startOfDay(s);
            if (!S.matchesRule(occStub, day)) return;
            const derived = S.occurrenceIdFor(occStub, day);
            if (Array.from(occSel.options).some((o) => o.value === derived && !o.disabled)) {
              occSel.value = derived;
            }
          }
          const row2 = U.el('div', { class: 'row2' });
          const start = U.el('input', { class: 'input', type: 'datetime-local', value: U.toInputDateTime(baseStart) });
          start.dataset.testid = 'schedule-start';
          const durSel = U.el('select', { class: 'select' });
          [15, 30, 45, 60, 90, 120].forEach((m) => durSel.appendChild(U.el('option', { value: String(m), text: (m < 60 ? m + ' ' + (S.state.lang === 'zh' ? '分钟' : 'min') : (m / 60) + ' ' + (S.state.lang === 'zh' ? '小时' : 'h')) })));
          const dur0 = draft.scheduleStart
            ? Math.max(15, Math.round(U.minutesBetween(draft.scheduleStart, draft.scheduleEnd)))
            : 60;
          if (dur0 && !Array.from(durSel.options).some((o) => Number(o.value) === dur0)) {
            durSel.appendChild(U.el('option', { value: String(dur0), text: dur0 + ' ' + (S.state.lang === 'zh' ? '分钟' : 'min') }));
          }
          durSel.value = String(dur0 || 60);
          row2.appendChild(start); row2.appendChild(durSel);
          box.appendChild(row2);

          // A repeating to-do is scheduled per occurrence; ask which one here so the
          // allocation is visible instead of orphaned.
          let occSel = null;
          if (draft.recurrence) {
            const occRow = U.el('div', { class: 'field' });
            occRow.innerHTML = `<label>${U.esc(t('occurrence'))}</label>`;
            occSel = U.el('select', { class: 'select' });
            occSel.dataset.testid = 'schedule-occurrence';
            const from = U.addDays(U.startOfDay(U.now()), -1);
            const to = U.addDays(U.startOfDay(U.now()), 60);
            const realTodo = draft.id ? S.todoById(draft.id) : null;
            const stub = {
              recurrence: draft.recurrence, dueDate: draft.dueDate,
              startDate: draft.startDate, createdAt: U.now(), id: draft.id,
              occurrenceStates: realTodo ? realTodo.occurrenceStates : {},
            };
            occStub = stub;
            S.occurrencesInWindow(stub, from, to).slice(0, 30).forEach((d) => {
              const id = S.occurrenceIdFor(stub, d);
              // A finished occurrence cannot take a new allocation: the write
              // would be valid but permanently invisible, because completion
              // invalidates every future block for that instance.
              const done = S.isOccurrenceDone(stub, id);
              const opt = U.el('option', {
                value: id,
                text: U.fmtMonthDay(d) + ' · ' + U.fmtWeekdayLong(d) + (done ? ' · ' + t('completed') : ''),
              });
              if (done) opt.disabled = true;
              occSel.appendChild(opt);
            });
            if (!occSel.options.length) {
              occSel.appendChild(U.el('option', { value: '', text: t('nothingHere') }));
            }
            if (draft.scheduleOccurrence) occSel.value = draft.scheduleOccurrence;
            if (!occSel.value || (occSel.selectedOptions[0] && occSel.selectedOptions[0].disabled)) {
              const firstOpen = Array.from(occSel.options).find((o) => !o.disabled && o.value);
              if (firstOpen) occSel.value = firstOpen.value;
            }
            occRow.appendChild(occSel);
            box.appendChild(occRow);
          }

          const quick = U.el('div', { class: 'quick' });
          [
            { d: 0 },
            { d: 1 },
          ].forEach((q) => {
            // Compute the slot once, then label the button with that same slot.
            // The label used to be a fixed "今天" while the value rolled over.
            const resolve = () => {
              const now = U.now();
              let day = U.addDays(today, q.d);
              let h = q.d === 0 ? Math.max(9, now.getHours() + 1) : 9;
              if (q.d === 0 && now.getHours() >= 23) {
                day = U.addDays(today, 1);
                h = 9;
              }
              return new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.min(23, h), 0);
            };
            const slot = resolve();
            const b = U.el('button', { class: 'chip-btn', text: chipDayLabel(slot) + ' ' + U.fmtTime(slot) });
            b.addEventListener('click', () => {
              // A quick chip must land on a slot that is still ahead. Late in
              // the evening "today at 09:00" is in the past and "today at 23:00"
              // is too, so the chip rolls to the next morning instead.
              start.value = U.toInputDateTime(resolve());
              upd();
            });
            quick.appendChild(b);
          });
          box.appendChild(quick);

          const preview = U.el('div', { class: 'preview' });
          box.appendChild(preview);

          const suggLabel = U.el('div', { class: 'field-label', text: t('recommendedSlots') });
          box.appendChild(suggLabel);
          const sugg = U.el('div', { class: 'chip-row', 'data-testid': 'schedule-suggestions' });
          box.appendChild(sugg);

          function drawSuggestions() {
            sugg.innerHTML = '';
            const s = U.fromInputDateTime(start.value) || baseStart;
            const day = U.startOfDay(s);
            const mins = parseInt(durSel.value, 10);
            const taken = [];
            eventBlocksBetween(day, U.endOfDay(day)).forEach((e) => taken.push([e.startDt, e.endDt]));
            S.state.allocations.forEach((a) => {
              if (S.isAllocationLive(a) && a.id !== draft.scheduleAllocId && a.todoId !== draft.id) taken.push([a.startAt, a.endAt]);
            });
            const slots = [];
            for (let m = 8 * 60; m + mins <= 21 * 60 && slots.length < 3; m += 30) {
              const from = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 0, m);
              const to = U.addMinutes(from, mins);
              const clash = taken.some(([a, b]) => a < to && b > from);
              if (!clash) slots.push(from);
            }
            if (!slots.length) {
              sugg.appendChild(U.el('span', { class: 'tiny muted', text: t('nothingHere') }));
              return;
            }
            slots.forEach((slot) => {
              const b = U.el('button', { class: 'chip-btn', text: U.fmtTimeRange(slot, U.addMinutes(slot, mins)) });
              b.dataset.testid = 'schedule-suggestion';
              b.addEventListener('click', () => {
                start.value = U.toInputDateTime(slot);
                upd();
              });
              sugg.appendChild(b);
            });
          }

          function upd() {
            const s = U.fromInputDateTime(start.value);
            const mins = parseInt(durSel.value, 10) || 60;
            if (!s) return;
            syncOccurrence(occSel, start.value);
            preview.textContent = `${U.fmtMonthDay(s)} ${U.fmtTimeRange(s, U.addMinutes(s, mins))}`;
            const conflict = S.state.allocations.filter((a) => S.isAllocationLive(a) && a.startAt < U.addMinutes(s, mins) && a.endAt > s && a.id !== draft.scheduleAllocId && a.todoId !== draft.id);
            const evs = eventBlocksBetween(s, U.addMinutes(s, mins));
            if (conflict.length) preview.innerHTML += `<div style="color:var(--amber);margin-top:4px">${U.esc(t('allocateConflict', { t: (S.todoById(conflict[0].todoId) || {}).summary || '' }))}</div>`;
            if (evs.length) preview.innerHTML += `<div style="color:var(--amber);margin-top:2px">${U.esc(t('conflict'))}: ${U.esc(evs[0].summary)}</div>`;
            drawSuggestions();
          }
          start.addEventListener('change', upd);
          durSel.addEventListener('change', upd);
          upd();

          const actions = U.el('div', { class: 'input-row' });
          const clear = U.el('button', { class: 'btn ghost', text: t('clear') });
          clear.addEventListener('click', () => { draft.scheduleStart = null; draft.scheduleEnd = null; markDirty(); close(null); live.renderBody(); live.validate(); });
          const apply = U.el('button', { class: 'btn primary', text: t('apply') });
          apply.dataset.testid = 'schedule-apply';
          apply.addEventListener('click', () => {
            const s = U.fromInputDateTime(start.value);
            if (!s) return;
            draft.scheduleStart = s;
            draft.scheduleEnd = U.addMinutes(s, parseInt(durSel.value, 10) || 60);
            syncOccurrence(occSel, start.value);
            if (occSel) draft.scheduleOccurrence = occSel.value || null;
            markDirty(); close(null); live.renderBody(); live.validate();
          });
          actions.appendChild(clear); actions.appendChild(apply);
          box.appendChild(actions);
          host.appendChild(box);
        },
      });
    }

    function repeatPicker() {
      UI.sheet({
        title: t('repeat'),
        body(host, close) {
          const box = U.el('div', { class: 'picker' });
          const opts = [
            { label: t('never'), rec: null },
            { label: t('daily'), rec: { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: draft.kind === 'todo' ? 'due' : 'start', valueType: draft.kind === 'todo' ? 'date' : 'localDateTime' } },
            { label: t('repeatWeekdays'), rec: { freq: 'WEEKLY', interval: 1, byday: [1, 2, 3, 4, 5], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' } },
            { label: t('weekly') + ' (' + U.fmtWeekdayLong(draft.dueDate || draft.startDt || U.now()) + ')', rec: { freq: 'WEEKLY', interval: 1, byday: [(draft.dueDate || draft.startDt || U.now()).getDay()], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' } },
            { label: t('monthly'), rec: { freq: 'MONTHLY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' } },
            { label: t('yearly'), rec: { freq: 'YEARLY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' } },
          ];
          opts.forEach((o) => {
            const b = U.el('button', { class: 'slot-sheet-option' });
            b.dataset.testid = 'repeat-option';
            const on = (o.rec === null && !draft.recurrence) || (o.rec && draft.recurrence && o.rec.freq === draft.recurrence.freq && o.label === t('repeatWeekdays') === (draft.recurrence.byday && draft.recurrence.byday.length === 5));
            b.innerHTML = `<span class="ico">${ICON(o.rec ? 'repeat' : 'x', 16)}</span><span><span class="t">${U.esc(o.label)}</span></span>${on ? '<span style="margin-left:auto;color:var(--accent)">' + ICON('check', 15) + '</span>' : ''}`;
            b.addEventListener('click', () => {
              // 重复开始 exists only inside recurrence: choosing a rule anchors
              // the series, choosing 不重复 must clear it even when the record
              // has a deadline, or the hidden value keeps blocking saves.
              if (draft.kind === 'todo') {
                if (!o.rec) draft.startDate = null;
                else if (!draft.dueDate) draft.startDate = draft.startDateInput || U.startOfDay(U.now());
              }
              draft.recurrence = o.rec;
              markDirty(); close(null); live.renderBody(); live.validate();
            });
            box.appendChild(b);
          });

          const custom = U.el('div', { class: 'form-block', style: 'margin-top:8px' });
          const intRow = U.el('div', { class: 'form-row' });
          intRow.appendChild(U.el('span', { class: 'label', text: t('every') }));
          const ctrl = U.el('div', { class: 'control' });
          const interval = U.el('input', { class: 'input', type: 'number', min: '1', max: '999', value: String(draft.recurrence ? draft.recurrence.interval : 1), style: 'max-width:88px' });
          const unit = U.el('select', { class: 'select', style: 'max-width:120px' });
          [['DAILY', t('dayUnit')], ['WEEKLY', t('weekUnit')], ['MONTHLY', t('monthUnit')], ['YEARLY', t('yearUnit')]].forEach(([v, l]) => unit.appendChild(U.el('option', { value: v, text: l })));
          unit.value = draft.recurrence ? draft.recurrence.freq : 'WEEKLY';
          ctrl.appendChild(interval); ctrl.appendChild(unit);
          intRow.appendChild(ctrl);
          custom.appendChild(intRow);

          const startRow = U.el('div', { class: 'form-row' });
          startRow.appendChild(U.el('span', { class: 'label', text: t('repeatStart') }));
          const sctrl = U.el('div', { class: 'control' });
          const startDateInput = U.el('input', { class: 'input', type: 'date', style: 'max-width:170px' });
          startDateInput.dataset.testid = 'repeat-start';
          const fallbackStart = draft.startDate || draft.dueDate || U.startOfDay(U.now());
          startDateInput.value = U.toInputDate(fallbackStart);
          startDateInput.addEventListener('change', () => {
            const d = U.fromInputDate(startDateInput.value);
            if (!d) return;
            // Pending value only: dismissing the sheet must not write an anchor
            // to a record whose rule the user never applied.
            draft.startDateInput = U.startOfDay(d);
            markDirty();
          });
          sctrl.appendChild(startDateInput);
          startRow.appendChild(sctrl);
          custom.appendChild(startRow);

          const untilRow = U.el('div', { class: 'form-row' });
          untilRow.appendChild(U.el('span', { class: 'label', text: t('until') }));
          const uctrl = U.el('div', { class: 'control' });
          const forever = U.el('div', { class: 'segmented' });
          const untilInput = U.el('input', { class: 'input', type: 'date', style: 'max-width:170px' });
          if (draft.recurrence && draft.recurrence.until) untilInput.value = U.toInputDate(draft.recurrence.until);
          [[true, t('forever')], [false, t('until')]].forEach(([v, l]) => {
            const b = U.el('button', { class: (draft.recurrence && !!draft.recurrence.until ? !v : v) ? 'on' : '', text: l });
            b.addEventListener('click', () => {
              forever.querySelectorAll('button').forEach((x) => x.classList.remove('on'));
              b.classList.add('on');
              untilInput.hidden = v;
            });
            forever.appendChild(b);
          });
          untilInput.hidden = !(draft.recurrence && draft.recurrence.until);
          uctrl.appendChild(forever); uctrl.appendChild(untilInput);
          untilRow.appendChild(uctrl);
          custom.appendChild(untilRow);

          const applyCustom = U.el('button', { class: 'btn ghost', text: t('apply') });
          applyCustom.addEventListener('click', () => {
            const freq = unit.value;
            const iv = Math.max(1, parseInt(interval.value, 10) || 1);
            draft.recurrence = {
              freq, interval: iv, byday: [], timeZone: 'Asia/Shanghai',
              until: untilInput.hidden ? null : U.fromInputDate(untilInput.value),
              anchor: draft.kind === 'todo' ? 'due' : 'start',
              valueType: draft.kind === 'todo' ? 'date' : 'localDateTime',
            };
            // A series needs a start or it can never match a day. A custom rule
            // gets the same anchor the presets set, honouring a chosen 重复开始.
            if (draft.kind === 'todo' && !draft.dueDate) {
              draft.startDate = draft.startDateInput
                ? U.startOfDay(draft.startDateInput)
                : U.startOfDay(U.now());
            }
            markDirty(); close(null); live.renderBody(); live.validate();
          });
          custom.appendChild(applyCustom);
          box.appendChild(custom);
          host.appendChild(box);
        },
      });
    }

    // The primary label names what the save will write. "Save" alone made a
    // form that quietly carried a deadline, a slot and two reminders read as a
    // title-only save.
    // A schedule on a repeating to-do belongs to one occurrence. Derive it from
    // the slot when the user set the slot before the repeat, so the write is not
    // silently dropped; false means the slot is not an occurrence at all.
    function scheduleProbe() {
      const realTodo = draft.id ? S.todoById(draft.id) : null;
      return {
        recurrence: draft.recurrence, startDate: draft.startDate, dueDate: draft.dueDate,
        createdAt: realTodo ? realTodo.createdAt : U.now(), id: draft.id,
        occurrenceStates: realTodo ? realTodo.occurrenceStates : {},
      };
    }
    function scheduleOccurrenceFor(start) {
      if (!draft.recurrence) return null;
      if (draft.scheduleOccurrence) return draft.scheduleOccurrence;
      const probe = scheduleProbe();
      if (!S.matchesRule(probe, start)) return false;
      return S.occurrenceIdFor(probe, start);
    }

    function saveFieldSummary() {
      const parts = [];
      if (draft.kind === 'todo') {
        if (draft.dueDate) parts.push(t('saveFieldsDue', { d: U.fmtDeadline(draft.dueDate) }));
        if (draft.scheduleStart && scheduleOccurrenceFor(draft.scheduleStart) !== false) {
          parts.push(t('saveFieldsSchedule', { d: U.fmtMonthDayTime(draft.scheduleStart) }));
        }
      } else {
        parts.push(U.fmtMonthDayTime(draft.startDt));
        if (draft.isAllDay) parts.push(t('allDay'));
      }
      if (draft.reminderOffsets.length) parts.push(t('saveFieldsReminders', { n: draft.reminderOffsets.length }));
      if (draft.tagIds.length) parts.push(t('saveFieldsTags', { n: draft.tagIds.length }));
      const cal = S.calendarById(draft.calendarId);
      if (cal) parts.push(t('saveFieldsCalendar', { c: cal.name }));
      return parts.slice(0, 3).join(' · ');
    }
    function updateSaveLabel() {
      const fields = saveFieldSummary();
      const label = fields ? t('saveWith', { fields }) : t('save');
      saveBtn.textContent = label;
      saveTop.textContent = label;
      saveBtn.title = label;
    }

    function aiParseSheet() {
      let parsed = null;
      UI.sheet({
        title: t('aiParse'),
        subtitle: t('aiParseHint'),
        body(host, close) {
          const box = U.el('div', { class: 'picker' });
          host.appendChild(box);
          const ta = U.el('textarea', { class: 'textarea', rows: '3', placeholder: t('quickAddPlaceholder'), 'data-testid': 'ai-parse-input' });
          ta.value = draft.summary;
          box.appendChild(ta);
          const out = U.el('div', { class: 'quick-preview', 'data-testid': 'ai-parse-preview' });
          box.appendChild(out);
          const acts = U.el('div', { class: 'input-row' });
          const apply = U.el('button', { class: 'btn primary', text: t('aiParseApply'), 'data-testid': 'ai-parse-apply' });
          apply.disabled = true;
          acts.appendChild(apply);
          box.appendChild(acts);
          function draw() {
            out.innerHTML = '';
            parsed = ta.value.trim() ? window.QuickParse.parse(ta.value, U.now()) : null;
            if (!parsed) { apply.disabled = true; return; }
            apply.disabled = false;
            const willSchedule = draft.kind === 'todo' && parsed.kind === 'event';
            out.appendChild(U.el('div', {
              class: 'quick-kind ' + (parsed.kind === 'event' ? 'event' : 'todo'),
              text: willSchedule ? t('scheduleExec') : (parsed.kind === 'event' ? t('quickAddEvent') : t('quickAddTodo')),
            }));
            out.appendChild(U.el('div', { class: 'quick-title', text: parsed.title }));
            const when = parsed.kind === 'event'
              ? U.fmtMonthDayTime(parsed.start) + ' · ' + U.fmtTimeRange(parsed.start, parsed.end)
              : (parsed.dueDate ? t('deadlinePrefix', { d: U.fmtDeadline(parsed.dueDate) }) : t('quickAddNoParse'));
            out.appendChild(U.el('div', { class: 'quick-when', text: when }));
          }
          ta.addEventListener('input', draw);
          apply.addEventListener('click', () => {
            if (!parsed) return;
            draft.summary = parsed.title || ta.value;
            if (live.titleInput) live.titleInput.value = draft.summary;
            if (draft.kind === 'todo') {
              if (parsed.kind === 'event') {
                draft.scheduleStart = parsed.start;
                draft.scheduleEnd = parsed.end;
              } else if (parsed.dueDate) {
                draft.dueDate = parsed.dueDate;
              }
            } else if (parsed.kind === 'event') {
              draft.startDt = parsed.start;
              draft.endDt = parsed.end;
            } else if (parsed.dueDate) {
              draft.startDt = new Date(parsed.dueDate.getFullYear(), parsed.dueDate.getMonth(), parsed.dueDate.getDate(), 9, 0);
              draft.endDt = U.addMinutes(draft.startDt, 60);
            }
            draft.touched = true;
            markDirty();
            close(null);
            live.renderBody();
            live.validate();
            autoGrow(titleInput);
          });
          draw();
        },
      });
    }

    function validate() {
      const errs = [];
      if (!draft.summary.trim()) errs.push(t('titleRequired'));
      if (draft.kind === 'event' && draft.endDt <= draft.startDt) errs.push(t('timeInvalid'));
      if (draft.kind === 'todo' && draft.recurrence && draft.startDate && draft.dueDate && draft.startDate > draft.dueDate) errs.push(t('startAfterDue'));
      if (draft.kind === 'todo' && draft.scheduleStart && draft.scheduleEnd && draft.recurrence) {
        // The rule on screen is the one that will be written, so the block has
        // to be reachable under it — a stale occurrence id from an earlier rule
        // must not carry a block onto a day the series never visits.
        if (!S.matchesRule(scheduleProbe(), draft.scheduleStart)) {
          errs.push(t('scheduleNeedsOccurrence'));
        } else if (draft.scheduleOccurrence) {
          const occDay = S.occurrenceDateFromId(draft.scheduleOccurrence);
          if (!occDay || !U.sameDay(occDay, draft.scheduleStart)) errs.push(t('scheduleOccurrenceMismatch'));
        }
      }
      // An untouched new form is not a mistake. Saving stays disabled so the
      // rule is still enforced, but the red message waits until the user has
      // actually typed into the field — otherwise the page greets them with an
      // accusation they did nothing to earn.
      const showErrors = draft.touched;
      if (errs.length) {
        errBox.hidden = !showErrors;
        errBox.textContent = showErrors ? errs.join(' · ') : '';
        saveBtn.disabled = true;
        saveTop.disabled = true;
        titleInput.classList.toggle('invalid', showErrors && !draft.summary.trim());
      } else {
        errBox.hidden = true;
        saveBtn.disabled = false;
        saveTop.disabled = false;
        titleInput.classList.remove('invalid');
      }
      updateSaveLabel();
      return errs;
    }

    function showSaveError() {
      saveErr.innerHTML = '';
      saveErr.hidden = false;
      saveErr.appendChild(U.el('span', { text: t('saveFailed') }));
      const retry = U.el('button', { class: 'btn ghost sm', text: t('retrySave'), 'data-testid': 'composer-retry' });
      retry.addEventListener('click', () => {
        S.state.simulateSaveFailure = false;
        saveErr.hidden = true;
        save(true);
      });
      saveErr.appendChild(retry);
    }

    function save(closeAfter, thenOpenSubtask) {
      const errs = live.validate();
      if (errs.length) {
        const first = root.querySelector('.invalid') || root.querySelector('.hint-box.error');
        if (first && first.focus) first.focus();
        UI.announce(errs[0]);
        return;
      }
      // The states bench can arm a failed write so the recovery path is real
      // rather than described.
      if (S.state.simulateSaveFailure) {
        showSaveError();
        UI.announce(t('saveFailed'));
        return;
      }
      saveErr.hidden = true;
      if (draft.kind === 'todo') {
        const payload = {
          summary: draft.summary.trim(), description: draft.notes || null,
          dueDate: draft.dueDate, startDate: draft.recurrence ? draft.startDate : null,
          priority: draft.priority, tagIds: draft.tagIds.slice(), calendarId: draft.calendarId,
          recurrence: draft.recurrence, reminderOffsets: draft.reminderOffsets.slice(),
          attachments: draft.attachments.slice(),
        };
        if (draft.parentId) payload.parentId = draft.parentId;
        const wasDone = isEdit && !draft.recurrence ? S.isDone(S.todoById(draft.id)) : false;
        let todo;
        if (isEdit) {
          todo = S.updateTodo(draft.id, payload);
        } else {
          todo = S.createTodo(payload);
        }
        // Status is not a second write path. The form may show the state, but
        // the single completion routine owns status, completedAt and which
        // allocations stop being current work; writing status here left a
        // reopened record with an invalidated block nobody could restore.
        if (isEdit && !draft.recurrence && !!draft.statusDone !== wasDone) {
          S.completeTodo(todo.id);
          todo = S.todoById(draft.id);
        }
        // Conflict is read BEFORE the write. Computing it afterwards counted the
        // row this save had just created as an overlap with itself.
        let conflictName = null;
        if (draft.scheduleStart && draft.scheduleEnd) {
          const cs = draft.scheduleStart;
          const ce = draft.scheduleEnd;
          const evs = eventBlocksBetween(cs, ce);
          const allocs = S.state.allocations.filter((a) => S.isAllocationLive(a) && a.startAt < ce && a.endAt > cs && a.id !== draft.scheduleAllocId && a.todoId !== todo.id);
          if (evs.length) conflictName = evs[0].summary;
          else if (allocs.length) conflictName = (S.todoById(allocs[0].todoId) || {}).summary || null;
        }
        // schedule: a repeating to-do is scheduled per occurrence, so a schedule
        // without an occurrence would be invisible; refuse instead of writing one.
        let scheduleBlocked = false;
        if (draft.scheduleStart && draft.scheduleEnd) {
          let occ = draft.scheduleOccurrence;
          if (todo.recurrence && !occ && S.matchesRule(todo, draft.scheduleStart)) {
            occ = S.occurrenceIdFor(todo, draft.scheduleStart);
          }
          if (todo.recurrence && !occ) {
            scheduleBlocked = true;
          } else if (todo.recurrence && S.isOccurrenceDone(todo, occ)) {
            // The picker disables finished occurrences; a stale draft must not
            // slip one through and write a block nothing will ever draw.
            scheduleBlocked = true;
          } else if (draft.scheduleAllocId) {
            const alloc = S.state.allocations.find((a) => a.id === draft.scheduleAllocId);
            if (alloc) {
              // A block of a record that is no longer repeating is a plain
              // allocation: keeping the old occurrence id made the move look
              // like a cross-day occurrence jump and get refused in silence.
              if (todo.recurrence) { if (occ) alloc.occurrenceId = occ; }
              else alloc.occurrenceId = null;
            }
            if (!S.rescheduleAllocation(draft.scheduleAllocId, draft.scheduleStart, draft.scheduleEnd)) {
              scheduleBlocked = true;
            }
          } else {
            S.createAllocation({
              todoId: todo.id, startAt: draft.scheduleStart, endAt: draft.scheduleEnd,
              occurrenceId: occ || null,
            });
          }
        } else if (draft.scheduleAllocId) {
          S.cancelAllocation(draft.scheduleAllocId);
        }
        dirty = false;
        draft.dirty = false;
        const created = !isEdit;
        S.state.composer = null;
        S.state.composerDraft = null;
        if (draft.parentId && created) {
          // Back must reach the list the parent came from, not the parent twice.
          if (S.state.history.length && S.state.history[S.state.history.length - 1].name === 'detail') {
            S.state.history.pop();
          }
          S.navigate('detail', { type: 'todo', id: draft.parentId }, { replace: true });
        } else if (created) {
          const backTo = S.state.route.name === 'composer' ? (S.state.tab || 'action') : S.state.route.name;
          App.back();
          // The row has to be where the user lands. A new record whose deadline
          // was cleared (or moved to another day) does not belong to the dated
          // list that opened the form, so that list is switched to the one that
          // owns it instead of showing a list without the new row.
          if (backTo === 'todos') {
            const scheduled = draft.scheduleStart && !scheduleBlocked ? U.startOfDay(draft.scheduleStart) : null;
            if (scheduled) {
              S.state.todosView = { kind: 'day', day: scheduled };
              S.state.browseDate = scheduled;
            } else if (todo.dueDate) {
              const d = U.startOfDay(todo.dueDate);
              S.state.todosView = { kind: 'day', day: d };
              S.state.browseDate = d;
            } else {
              S.state.todosView = { kind: 'inbox', day: null };
            }
          }
          S.state.highlight = { testid: 'todo-tile', testids: ['todo-tile', 'action-todo', 'alloc-block'], id: todo.id };
          App.render();
        } else if (thenOpenSubtask) {
          // The parent was written above; the child opens in a fresh form
          // without taking the parent's edits down with it.
          S.state.composer = { kind: 'todo', mode: 'create', parentId: thenOpenSubtask };
          S.state.composerDraft = null;
          S.navigate('composer', {});
        } else {
          App.back();
          App.render();
        }
        const base = created ? t('createdToast', { t: todo.summary }) : t('updatedToast', { t: todo.summary });
        // D-09: an overlapping schedule saves and the toast names the conflict.
        // The picker preview said it, then the save toast dropped it.
        const msg = base + (conflictName && !scheduleBlocked ? ' · ' + t('conflict') + ': ' + conflictName : '');
        UI.toast(scheduleBlocked ? msg + ' · ' + t('recurrenceNeedsOccurrence') : msg, {
          warn: scheduleBlocked,
          undo: created ? () => { S.softDeleteTodo(todo.id); App.render(); } : null,
        });
      } else {
        const payload = {
          summary: draft.summary.trim(), description: draft.notes || null,
          startDt: draft.startDt, endDt: draft.endDt, isAllDay: draft.isAllDay,
          location: draft.location || null, calendarId: draft.calendarId,
          rrule: draft.recurrence, tagIds: draft.tagIds.slice(),
          reminderOffsets: draft.reminderOffsets.slice(),
        };
        let event;
        let splitCopy = null;
        if (isEdit && draft.occurrence && c.scope === 'future') {
          // The old series stops the day before; the record continues from this
          // occurrence with the edited values.
          event = S.splitEventFuture(draft.id, draft.occurrence, payload);
        } else if (isEdit && draft.occurrence) {
          const split = S.splitEventOccurrence(draft.id, draft.occurrence, payload);
          event = split ? split.copy : null;
          splitCopy = split && !split.updated ? split.copy : null;
        } else if (isEdit) event = S.updateEvent(draft.id, payload);
        else event = S.createEvent(payload);
        dirty = false;
        draft.dirty = false;
        S.state.composer = null;
        S.state.composerDraft = null;
        if (splitCopy) {
          // The edited thing is now the one-off copy, not the series instance
          // that was on screen when Edit was pressed; staying there would show
          // a page whose data the save just replaced. The old detail was the
          // entry Back would return to, so drop it as well.
          if (S.state.history.length && S.state.history[S.state.history.length - 1].name === 'detail') {
            S.state.history.pop();
          }
          S.navigate('detail', { type: 'event', id: splitCopy.id }, { replace: true });
        } else {
          App.back();
          // A new event lands in the calendar grid (or Today's timeline), so the
          // row it just produced has to be marked the same way a to-do is.
          S.state.highlight = !isEdit ? { testid: 'event-block', testids: ['event-block', 'action-event'], id: event.id } : null;
        }
        App.render();
        UI.toast(isEdit ? t('updatedToast', { t: event.summary }) : t('createdToast', { t: event.summary }), {
          undo: !isEdit ? () => { S.softDeleteEvent(event.id); App.render(); } : null,
        });
      }
    }

    function autoGrow(node) {
      node.style.height = 'auto';
      node.style.height = Math.min(120, node.scrollHeight) + 'px';
    }

    live.renderBody = renderBody;
    live.validate = validate;
    live.autoGrow = autoGrow;
    live.titleInput = titleInput;
    renderBody();
    validate();
    App.escapeHandler = () => closeComposer();
    setTimeout(() => {
      if (draft.focus === 'deadline') {
        draft.focus = null;
        if (!draft.summary) titleInput.focus();
        deadlinePicker();
        return;
      }
      if (S.state.composer && S.state.composer.focus === 'title') titleInput.focus();
      else if (!draft.summary) titleInput.focus();
      autoGrow(titleInput);
    }, 30);
    return root;
  }

  App.defineView('composer', composer);
  window.__composer = { draftFromRoute };
})();
