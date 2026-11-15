/* Composer: one surface for creating and editing both Todo and Event.
   Type switch is explicit; a Todo's deadline and scheduled time are separate
   fields and never merge. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

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
      startDt: c.startDt || null, endDt: c.endDt || null, isAllDay: false, location: '',
      scheduleStart: c.scheduleStart || null, scheduleEnd: c.scheduleEnd || null,
      scheduleOccurrence: c.scheduleOccurrence || null,
      moreOpen: false, focus: c.focus || null,
    };
    if (c.mode === 'edit') {
      if (c.kind === 'todo') {
        const todo = S.todoById(c.id);
        if (!todo) return base;
        Object.assign(base, {
          summary: todo.summary, notes: todo.description || '', dueDate: todo.dueDate,
          startDate: todo.startDate, priority: todo.priority, tagIds: todo.tagIds.slice(),
          calendarId: todo.calendarId, recurrence: todo.recurrence,
          reminderOffsets: todo.reminderOffsets.slice(), attachments: todo.attachments.slice(),
          parentId: todo.parentId,
        });
        const allocs = S.allocationsForTodo(todo.id).filter(S.isAllocationLive);
        if (allocs.length) {
          base.scheduleStart = allocs[0].startAt; base.scheduleEnd = allocs[0].endAt;
          base.scheduleAllocId = allocs[0].id;
          base.scheduleOccurrence = allocs[0].occurrenceId || null;
        }
      } else {
        const series = S.eventById(c.id);
        if (!series) return base;
        // Editing one occurrence edits that occurrence, not the series base.
        const occStart = c.occurrence ? new Date(c.occurrence) : series.startDt;
        const occEnd = c.occurrence ? new Date(c.occurrence + (series.endDt - series.startDt)) : series.endDt;
        Object.assign(base, {
          summary: series.summary, notes: series.description || '', startDt: occStart, endDt: occEnd,
          isAllDay: series.isAllDay, location: series.location || '', calendarId: series.calendarId,
          recurrence: c.occurrence ? null : series.rrule,
          reminderOffsets: (series.reminderOffsets || []).slice(), tagIds: (series.tagIds || []).slice(),
        });
      }
    } else {
      if (base.kind === 'event') {
        base.startDt = base.startDt || new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
        base.endDt = base.endDt || U.addMinutes(base.startDt, 60);
      }
    }
    return base;
  }

  function composer() {
    const c = S.state.composer || {};
    const draft = draftFromRoute();
    let dirty = false;
    const isEdit = draft.mode === 'edit';
    const narrow = U.isNarrow();

    const root = U.el('div', { class: 'composer', 'data-testid': 'composer' });

    function markDirty() { dirty = true; }

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
        if (ok) S.state.composer = null;
        return ok;
      });
    };
    function leave() {
      S.state.composer = null;
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
      markDirty();
      autoGrow(titleInput);
      validate();
    });
    titleInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !U.isNarrow()) {
        e.preventDefault();
        if (draft.kind === 'todo') save(true);
      }
    });
    body.appendChild(titleInput);

    const errBox = U.el('div', { class: 'hint-box error', hidden: 'hidden', role: 'alert' });
    body.appendChild(errBox);

    const typeRow = U.el('div', { class: 'composer-type' });
    const typeSeg = U.el('div', { class: 'segmented lg' });
    [['todo', t('typeTodo'), 'checkSquare'], ['event', t('typeEvent'), 'calendar']].forEach(([k, label, icon]) => {
      const b = U.el('button', { class: draft.kind === k ? 'on' : '', 'aria-pressed': draft.kind === k ? 'true' : 'false' });
      b.innerHTML = ICON(icon, 14) + `<span>${U.esc(label)}</span>`;
      b.dataset.testid = 'composer-type-' + k;
      b.addEventListener('click', () => {
        if (draft.kind === k) return;
        if (isEdit) return; // type is fixed once the record exists
        draft.kind = k;
        markDirty();
        if (k === 'event' && !draft.startDt) {
          const now = U.now();
          draft.startDt = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
          draft.endDt = U.addMinutes(draft.startDt, 60);
        }
        renderBody();
      });
      typeSeg.appendChild(b);
    });
    typeRow.appendChild(typeSeg);
    typeRow.appendChild(U.el('div', { class: 'type-hint', text: draft.kind === 'todo' ? t('typeHintTodo') : t('typeHintEvent') }));
    body.appendChild(typeRow);

    const formHost = U.el('div');
    body.appendChild(formHost);

    const moreHost = U.el('div');
    body.appendChild(moreHost);

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

    function renderBody() {
      formHost.innerHTML = '';
      const block = U.el('div', { class: 'form-block' });

      if (draft.kind === 'todo') {
        // deadline
        const dueBtn = pillButton('flag', draft.dueDate ? U.fmtDeadline(draft.dueDate) : t('noDeadline'), () => deadlinePicker(), 'composer-deadline');
        dueBtn.classList.toggle('on', !!draft.dueDate);
        const dueClear = draft.dueDate ? U.el('button', { class: 'icon-btn sm', 'aria-label': t('clear'), html: ICON('x', 13) }) : null;
        if (dueClear) dueClear.addEventListener('click', () => { draft.dueDate = null; markDirty(); renderBody(); validate(); });
        block.appendChild(row(t('deadline'), [dueBtn, dueClear].filter(Boolean)));

        // scheduled execution
        const schBtn = pillButton('clockPlus', draft.scheduleStart ? U.fmtMonthDayTime(draft.scheduleStart) + ' – ' + U.fmtTime(draft.scheduleEnd) : t('addSchedule'), () => schedulePicker(), 'composer-schedule');
        schBtn.classList.toggle('on', !!draft.scheduleStart);
        const schClear = draft.scheduleStart ? U.el('button', { class: 'icon-btn sm', 'aria-label': t('clear'), html: ICON('x', 13) }) : null;
        if (schClear) schClear.addEventListener('click', () => {
          draft.scheduleStart = null; draft.scheduleEnd = null; markDirty(); renderBody(); validate();
        });
        block.appendChild(row(t('scheduleExec'), [schBtn, schClear].filter(Boolean)));
        block.appendChild(U.el('div', { class: 'field-hint', style: 'padding-left:66px;margin-top:-6px', text: t('scheduleHint') }));

        // priority
        const prio = U.el('div', { class: 'segmented' });
        [[0, t('noPriority')], [1, t('low')], [5, t('medium')], [9, t('high')]].forEach(([val, label]) => {
          const b = U.el('button', { class: draft.priority === val ? 'on' : '', text: label, 'aria-pressed': draft.priority === val ? 'true' : 'false' });
          b.dataset.testid = 'composer-priority-' + val;
          b.addEventListener('click', () => { draft.priority = val; markDirty(); renderBody(); });
          prio.appendChild(b);
        });
        block.appendChild(row(t('priority'), prio));

        // calendar
        const calSel = U.el('select', { class: 'select', 'aria-label': t('calendar') });
        S.state.calendars.forEach((cal) => {
          const o = U.el('option', { value: String(cal.id), text: cal.name });
          if (cal.id === draft.calendarId) o.selected = true;
          calSel.appendChild(o);
        });
        calSel.addEventListener('change', () => { draft.calendarId = parseInt(calSel.value, 10); markDirty(); });
        block.appendChild(row(t('calendar'), calSel));
      } else {
        // event: all-day
        const allday = U.el('div', { class: 'segmented' });
        [[false, S.state.lang === 'zh' ? '定时' : 'Timed'], [true, t('allDay')]].forEach(([val, label]) => {
          const b = U.el('button', { class: draft.isAllDay === val ? 'on' : '', text: label, 'aria-pressed': draft.isAllDay === val ? 'true' : 'false' });
          b.dataset.testid = 'composer-allday-' + (val ? 'on' : 'off');
          b.addEventListener('click', () => {
            draft.isAllDay = val;
            if (val) { draft.startDt.setHours(0, 0, 0, 0); draft.endDt = new Date(draft.startDt.getFullYear(), draft.startDt.getMonth(), draft.startDt.getDate(), 23, 59); }
            else { draft.startDt.setHours(9, 0, 0, 0); draft.endDt = U.addMinutes(draft.startDt, 60); }
            markDirty(); renderBody(); validate();
          });
          allday.appendChild(b);
        });
        block.appendChild(row(t('allDay'), allday));

        const dateInput = U.el('input', { class: 'input', type: 'date', value: U.toInputDate(draft.startDt), 'aria-label': t('starts') });
        dateInput.dataset.testid = 'composer-start-date';
        dateInput.addEventListener('change', () => {
          const d = U.fromInputDate(dateInput.value);
          if (!d) return;
          const dur = draft.endDt - draft.startDt;
          const sh = draft.startDt.getHours(), sm = draft.startDt.getMinutes();
          draft.startDt = new Date(d.getFullYear(), d.getMonth(), d.getDate(), draft.isAllDay ? 0 : sh, draft.isAllDay ? 0 : sm);
          draft.endDt = draft.isAllDay ? new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59) : new Date(draft.startDt.getTime() + dur);
          markDirty(); renderBody(); validate();
        });
        block.appendChild(row(t('starts'), dateInput));

        if (!draft.isAllDay) {
          const t1 = U.el('input', { class: 'input', type: 'time', value: U.fmtTime(draft.startDt), 'aria-label': t('starts') });
          const t2 = U.el('input', { class: 'input', type: 'time', value: U.fmtTime(draft.endDt), 'aria-label': t('ends') });
          t1.dataset.testid = 'composer-start-time';
          t2.dataset.testid = 'composer-end-time';
          const applyTimes = () => {
            const [h1, m1] = t1.value.split(':').map(Number);
            const [h2, m2] = t2.value.split(':').map(Number);
            if (isNaN(h1) || isNaN(h2)) return;
            draft.startDt = new Date(draft.startDt.getFullYear(), draft.startDt.getMonth(), draft.startDt.getDate(), h1, m1 || 0);
            let end = new Date(draft.startDt.getFullYear(), draft.startDt.getMonth(), draft.startDt.getDate(), h2, m2 || 0);
            draft.endDt = end;
            markDirty(); validate();
          };
          t1.addEventListener('change', applyTimes);
          t2.addEventListener('change', applyTimes);
          const timeRow = U.el('div', { class: 'input-row' });
          timeRow.appendChild(t1);
          timeRow.appendChild(U.el('span', { class: 'muted', text: '–' }));
          timeRow.appendChild(t2);
          block.appendChild(row(t('schedule'), timeRow));
        }

        const loc = U.el('input', { class: 'input', placeholder: t('location'), value: draft.location, 'aria-label': t('location') });
        loc.dataset.testid = 'composer-location';
        loc.addEventListener('input', () => { draft.location = loc.value; markDirty(); });
        block.appendChild(row(t('location'), loc));

        const calSel = U.el('select', { class: 'select', 'aria-label': t('calendar') });
        S.state.calendars.forEach((cal) => {
          const o = U.el('option', { value: String(cal.id), text: cal.name });
          if (cal.id === draft.calendarId) o.selected = true;
          calSel.appendChild(o);
        });
        calSel.addEventListener('change', () => { draft.calendarId = parseInt(calSel.value, 10); markDirty(); });
        block.appendChild(row(t('calendar'), calSel));
      }

      // tags
      const tagWrap = U.el('div', { class: 'chip-row' });
      S.state.tags.forEach((tag) => {
        const on = draft.tagIds.includes(tag.id);
        const b = U.el('button', { class: 'chip-btn' + (on ? ' on' : '') });
        b.dataset.testid = 'composer-tag-' + tag.id;
        b.innerHTML = `<span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}`;
        b.setAttribute('aria-pressed', on ? 'true' : 'false');
        b.addEventListener('click', () => {
          draft.tagIds = on ? draft.tagIds.filter((x) => x !== tag.id) : draft.tagIds.concat(tag.id);
          markDirty(); renderBody();
        });
        tagWrap.appendChild(b);
      });
      block.appendChild(row(t('tags'), tagWrap));

      formHost.appendChild(block);

      // notes
      const notesBlock = U.el('div', { class: 'form-block' });
      const notes = U.el('textarea', { class: 'textarea', placeholder: t('notesPlaceholder'), 'aria-label': t('notes'), rows: '3' });
      notes.dataset.testid = 'composer-notes';
      notes.value = draft.notes || '';
      notes.addEventListener('input', () => { draft.notes = notes.value; markDirty(); });
      notesBlock.appendChild(U.el('div', { class: 'field-label', text: t('notes') }));
      notesBlock.appendChild(notes);
      formHost.appendChild(notesBlock);

      renderMore();
      if (draft.focus === 'deadline' && draft.kind === 'todo') { draft.focus = null; setTimeout(() => deadlinePicker(), 60); }
      if (draft.focus === 'schedule' && draft.kind === 'todo') { draft.focus = null; setTimeout(() => schedulePicker(), 60); }
      if (draft.focus === 'repeat') { draft.focus = null; draft.moreOpen = true; renderMore(); }
    }

    function renderMore() {
      moreHost.innerHTML = '';
      const toggle = U.el('button', { class: 'more-toggle' });
      toggle.dataset.testid = 'composer-more';
      toggle.innerHTML = (draft.moreOpen ? ICON('chevronUp', 13) : ICON('chevronDown', 13)) + `<span>${U.esc(S.state.lang === 'zh' ? '重复与提醒' : 'Repeat & reminders')}</span>`;
      toggle.addEventListener('click', () => { draft.moreOpen = !draft.moreOpen; renderMore(); });
      moreHost.appendChild(toggle);
      if (!draft.moreOpen) return;

      const block = U.el('div', { class: 'form-block' });
      const recBtn = U.el('button', { class: 'chip-btn' + (draft.recurrence ? ' on' : '') });
      recBtn.dataset.testid = 'composer-repeat';
      recBtn.innerHTML = ICON('repeat', 13) + `<span>${U.esc(UI.ruleSummary(draft.recurrence))}</span>`;
      recBtn.addEventListener('click', () => repeatPicker());
      block.appendChild(row(t('repeat'), recBtn));
      if (draft.recurrence) {
        block.appendChild(U.el('div', { class: 'field-hint', style: 'padding-left:66px;margin-top:-6px', text: draft.kind === 'todo' ? t('repeatHint') : (S.state.lang === 'zh' ? '重复日程按系列编辑，单次改动会询问范围。' : 'Repeating events edit as a series; single changes ask for scope.') }));
      }

      const remWrap = U.el('div', { class: 'chip-row' });
      const offsets = draft.reminderOffsets;
      offsets.forEach((min, idx) => {
        const chip = U.el('span', { class: 'chip amber' });
        chip.innerHTML = `${ICON('bell', 11)}<span>${U.esc(reminderLabel(min))}</span>`;
        const x = U.el('button', { class: 'icon-btn sm', style: 'width:16px;height:16px', 'aria-label': t('remove'), html: ICON('x', 10) });
        x.addEventListener('click', () => { offsets.splice(idx, 1); markDirty(); renderMore(); });
        chip.appendChild(x);
        remWrap.appendChild(chip);
      });
      const addRem = U.el('button', { class: 'chip-btn' });
      addRem.innerHTML = ICON('plus', 12) + `<span>${U.esc(t('addReminder'))}</span>`;
      addRem.addEventListener('click', () => {
        UI.sheet({
          title: t('addReminder'),
          body(host, close) {
            [[0, t('onStart')], [5, '5 ' + t('minutesBefore')], [15, '15 ' + t('minutesBefore')], [30, '30 ' + t('minutesBefore')], [60, '1 ' + t('hoursBefore')], [1440, '1 ' + t('daysBefore')]].forEach(([v, label]) => {
              const b = U.el('button', { class: 'slot-sheet-option' });
              b.innerHTML = `<span class="ico">${ICON('bell', 16)}</span><span><span class="t">${U.esc(label)}</span></span>`;
              b.addEventListener('click', () => { offsets.push(v); offsets.sort((a, b) => a - b); markDirty(); close(null); renderMore(); });
              host.appendChild(b);
            });
          },
        });
      });
      remWrap.appendChild(addRem);
      block.appendChild(row(t('reminder'), remWrap));
      moreHost.appendChild(block);

      const attachBlock = U.el('div', { class: 'form-block' });
      const attachWrap = U.el('div', { class: 'chip-row' });
      draft.attachments.forEach((a, i) => {
        const chip = U.el('span', { class: 'chip' });
        chip.innerHTML = ICON('paperclip', 11) + `<span>${U.esc(a)}</span>`;
        const x = U.el('button', { class: 'icon-btn sm', style: 'width:16px;height:16px', 'aria-label': t('remove'), html: ICON('x', 10) });
        x.addEventListener('click', () => { draft.attachments.splice(i, 1); markDirty(); renderMore(); });
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
          markDirty(); renderMore();
        });
        input.click();
      });
      attachWrap.appendChild(addAttach);
      block.appendChild(row(t('attachments'), attachWrap));
      moreHost.appendChild(block);
    }

    function reminderLabel(min) {
      if (min === 0) return t('onStart');
      if (min < 60) return min + ' ' + t('minutesBefore');
      if (min < 1440) return (min / 60) + ' ' + t('hoursBefore');
      return (min / 1440) + ' ' + t('daysBefore');
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
          const options = [
            { label: t('today') + ' 18:00', value: new Date(today.getFullYear(), today.getMonth(), today.getDate(), 18, 0) },
            { label: t('tomorrow'), value: new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1, 18, 0) },
            { label: t('thisWeek') + ' ' + U.fmtWeekdayShort(U.addDays(today, 5)), value: new Date(today.getFullYear(), today.getMonth(), today.getDate() + ((5 - today.getDay() + 7) % 7), 18, 0) },
            { label: t('nextWeek'), value: new Date(today.getFullYear(), today.getMonth(), today.getDate() + 7, 18, 0) },
          ];
          const qRow = U.el('div', { class: 'quick' });
          options.forEach((o) => {
            const b = U.el('button', { class: 'chip-btn', text: o.label });
            b.dataset.testid = 'deadline-quick';
            b.addEventListener('click', () => { draft.dueDate = o.value; markDirty(); close(null); renderBody(); validate(); });
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
          clear.addEventListener('click', () => { draft.dueDate = null; markDirty(); close(null); renderBody(); validate(); });
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
            markDirty(); close(null); renderBody(); validate();
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
          const row2 = U.el('div', { class: 'row2' });
          const start = U.el('input', { class: 'input', type: 'datetime-local', value: U.toInputDateTime(baseStart) });
          start.dataset.testid = 'schedule-start';
          const durSel = U.el('select', { class: 'select' });
          [15, 30, 45, 60, 90, 120].forEach((m) => durSel.appendChild(U.el('option', { value: String(m), text: (m < 60 ? m + ' ' + (S.state.lang === 'zh' ? '分钟' : 'min') : (m / 60) + ' ' + (S.state.lang === 'zh' ? '小时' : 'h')) })));
          durSel.value = String(draft.scheduleStart ? Math.max(15, U.minutesBetween(draft.scheduleStart, draft.scheduleEnd)) : 60);
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
            { label: t('today'), d: 0 },
            { label: t('tomorrow'), d: 1 },
          ].forEach((q) => {
            const b = U.el('button', { class: 'chip-btn', text: q.label });
            b.addEventListener('click', () => {
              const now = U.now();
              // A quick chip must land on a slot that is still ahead. Late in
              // the evening "today at 09:00" is in the past and "today at 23:00"
              // is too, so the chip rolls to the next morning instead.
              let day = U.addDays(today, q.d);
              let h = q.d === 0 ? Math.max(9, now.getHours() + 1) : 9;
              if (q.d === 0 && now.getHours() >= 23) {
                day = U.addDays(today, 1);
                h = 9;
              }
              start.value = U.toInputDateTime(new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.min(23, h), 0));
              upd();
            });
            quick.appendChild(b);
          });
          box.appendChild(quick);

          const preview = U.el('div', { class: 'preview' });
          box.appendChild(preview);
          function upd() {
            const s = U.fromInputDateTime(start.value);
            const mins = parseInt(durSel.value, 10);
            if (!s) return;
            preview.textContent = `${U.fmtMonthDay(s)} ${U.fmtTimeRange(s, U.addMinutes(s, mins))}`;
            const conflict = S.state.allocations.filter((a) => S.isAllocationLive(a) && a.startAt < U.addMinutes(s, mins) && a.endAt > s && a.id !== draft.scheduleAllocId);
            const evs = S.state.events.filter((e) => !e.deletedAt && e.startDt < U.addMinutes(s, mins) && e.endDt > s);
            if (conflict.length) preview.innerHTML += `<div style="color:var(--amber);margin-top:4px">${U.esc(t('allocateConflict', { t: (S.todoById(conflict[0].todoId) || {}).summary || '' }))}</div>`;
            if (evs.length) preview.innerHTML += `<div style="color:var(--amber);margin-top:2px">${U.esc(t('conflict'))}: ${U.esc(evs[0].summary)}</div>`;
          }
          start.addEventListener('change', upd);
          durSel.addEventListener('change', upd);
          upd();

          const actions = U.el('div', { class: 'input-row' });
          const clear = U.el('button', { class: 'btn ghost', text: t('clear') });
          clear.addEventListener('click', () => { draft.scheduleStart = null; draft.scheduleEnd = null; markDirty(); close(null); renderBody(); validate(); });
          const apply = U.el('button', { class: 'btn primary', text: t('apply') });
          apply.dataset.testid = 'schedule-apply';
          apply.addEventListener('click', () => {
            const s = U.fromInputDateTime(start.value);
            if (!s) return;
            draft.scheduleStart = s;
            draft.scheduleEnd = U.addMinutes(s, parseInt(durSel.value, 10));
            if (occSel) draft.scheduleOccurrence = occSel.value || null;
            markDirty(); close(null); renderBody(); validate();
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
              if (o.rec && draft.kind === 'todo' && !draft.dueDate && !draft.startDate) {
                draft.dueDate = U.startOfDay(U.now());
              }
              draft.recurrence = o.rec;
              markDirty(); close(null); renderMore(); renderBody(); validate();
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
            markDirty(); close(null); renderMore(); renderBody(); validate();
          });
          custom.appendChild(applyCustom);
          box.appendChild(custom);
          host.appendChild(box);
        },
      });
    }

    function validate() {
      const errs = [];
      if (!draft.summary.trim()) errs.push(t('titleRequired'));
      if (draft.kind === 'event' && draft.endDt <= draft.startDt) errs.push(t('timeInvalid'));
      if (draft.kind === 'todo' && draft.startDate && draft.dueDate && draft.startDate > draft.dueDate) errs.push(t('startAfterDue'));
      if (errs.length) {
        errBox.hidden = false;
        errBox.textContent = errs.join(' · ');
        saveBtn.disabled = true;
        saveTop.disabled = true;
        titleInput.classList.toggle('invalid', !draft.summary.trim());
      } else {
        errBox.hidden = true;
        saveBtn.disabled = false;
        saveTop.disabled = false;
        titleInput.classList.remove('invalid');
      }
      return errs;
    }

    function save(closeAfter) {
      const errs = validate();
      if (errs.length) {
        const first = root.querySelector('.invalid') || root.querySelector('.hint-box.error');
        if (first && first.focus) first.focus();
        UI.announce(errs[0]);
        return;
      }
      if (draft.kind === 'todo') {
        const payload = {
          summary: draft.summary.trim(), description: draft.notes || null,
          dueDate: draft.dueDate, startDate: draft.startDate,
          priority: draft.priority, tagIds: draft.tagIds.slice(), calendarId: draft.calendarId,
          recurrence: draft.recurrence, reminderOffsets: draft.reminderOffsets.slice(),
          attachments: draft.attachments.slice(),
        };
        if (draft.parentId) payload.parentId = draft.parentId;
        let todo;
        if (isEdit) {
          todo = S.updateTodo(draft.id, payload);
        } else {
          todo = S.createTodo(payload);
        }
        // schedule: a repeating to-do is scheduled per occurrence, so a schedule
        // without an occurrence would be invisible; refuse instead of writing one.
        let scheduleBlocked = false;
        if (draft.scheduleStart && draft.scheduleEnd) {
          if (todo.recurrence && !draft.scheduleOccurrence) {
            scheduleBlocked = true;
          } else if (todo.recurrence && S.isOccurrenceDone(todo, draft.scheduleOccurrence)) {
            // The picker disables finished occurrences; a stale draft must not
            // slip one through and write a block nothing will ever draw.
            scheduleBlocked = true;
          } else if (draft.scheduleAllocId) {
            const alloc = S.state.allocations.find((a) => a.id === draft.scheduleAllocId);
            if (alloc && draft.scheduleOccurrence) alloc.occurrenceId = draft.scheduleOccurrence;
            S.rescheduleAllocation(draft.scheduleAllocId, draft.scheduleStart, draft.scheduleEnd);
          } else {
            S.createAllocation({
              todoId: todo.id, startAt: draft.scheduleStart, endAt: draft.scheduleEnd,
              occurrenceId: draft.scheduleOccurrence || null,
            });
          }
        } else if (draft.scheduleAllocId) {
          S.cancelAllocation(draft.scheduleAllocId);
        }
        dirty = false;
        const created = !isEdit;
        S.state.composer = null;
        if (draft.parentId && created) {
          S.navigate('detail', { type: 'todo', id: draft.parentId });
        } else if (created) {
          const backTo = S.state.route.name === 'composer' ? (S.state.tab || 'action') : S.state.route.name;
          App.back();
          S.state.highlight = created ? { testid: 'todo-tile', testids: ['todo-tile', 'action-todo'], id: todo.id } : null;
          App.render();
        } else {
          App.back();
          App.render();
        }
        const base = created ? t('createdToast', { t: todo.summary }) : t('updatedToast', { t: todo.summary });
        UI.toast(scheduleBlocked ? base + ' · ' + t('recurrenceNeedsOccurrence') : base, {
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
        if (isEdit && draft.occurrence) {
          const split = S.splitEventOccurrence(draft.id, draft.occurrence, payload);
          event = split ? split.copy : null;
          splitCopy = split && !split.updated ? split.copy : null;
        } else if (isEdit) event = S.updateEvent(draft.id, payload);
        else event = S.createEvent(payload);
        dirty = false;
        S.state.composer = null;
        if (splitCopy) {
          // The edited thing is now the one-off copy, not the series instance
          // that was on screen when Edit was pressed; staying there would show
          // a page whose data the save just replaced.
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

    renderBody();
    validate();
    App.escapeHandler = () => closeComposer();
    setTimeout(() => {
      if (S.state.composer && S.state.composer.focus === 'title') titleInput.focus();
      else if (!draft.summary) titleInput.focus();
      autoGrow(titleInput);
    }, 30);
    return root;
  }

  App.defineView('composer', composer);
  window.__composer = { draftFromRoute };
})();
