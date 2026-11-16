/* Quick add: one line in, one record out. The preview is a promise, so it says
   exactly which record the current text will create before Save is pressed. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function renderQuickAdd() {
    let text = S.state.quickAddText || '';
    let override = 'auto';

    const root = U.el('div', { class: 'page' });
    const head = U.el('div', { class: 'page-head' + (U.isNarrow() ? ' mobile' : '') });
    head.appendChild(UI.iconButton(U.isNarrow() ? 'chevronLeft' : 'x', t('cancel'), () => App.back(), { cls: 'back-btn' }));
    const wrap = U.el('div', { class: 'page-title-wrap' });
    wrap.appendChild(U.el('h1', { class: 'page-title', text: t('quickAddFull') }));
    wrap.appendChild(U.el('div', { class: 'page-sub', text: t('quickAddHint') }));
    head.appendChild(wrap);
    root.appendChild(head);

    const scroll = U.el('div', { class: 'page-scroll' });
    const content = U.el('div', { class: 'page-content' + (U.isNarrow() ? ' tight' : '') });
    scroll.appendChild(content);
    root.appendChild(scroll);

    const input = U.el('textarea', {
      class: 'composer-title-input', rows: '2',
      placeholder: t('quickAddPlaceholder'), 'aria-label': t('quickAddFull'),
      'data-testid': 'quickadd-input',
    });
    input.value = text;
    content.appendChild(input);

    const typeRow = U.el('div', { class: 'chip-row', style: 'margin-top:10px' });
    [['auto', t('quickAdd')], ['event', t('typeEvent')], ['todo', t('typeTodo')]].forEach(([key, label]) => {
      const b = U.el('button', { class: 'chip-btn' + (override === key ? ' on' : ''), text: label });
      b.dataset.testid = 'quickadd-type-' + key;
      b.addEventListener('click', () => { override = key; draw(); });
      typeRow.appendChild(b);
    });
    content.appendChild(typeRow);

    const preview = U.el('div', { class: 'quick-preview' });
    preview.dataset.testid = 'quickadd-preview';
    content.appendChild(preview);

    const hint = U.el('div', { class: 'field-hint', style: 'margin-top:10px', text: t('quickAddRule') });
    content.appendChild(hint);

    const acts = U.el('div', { class: 'input-row', style: 'margin-top:16px' });
    const save = U.el('button', { class: 'btn primary lg', text: t('save'), 'data-testid': 'quickadd-save' });
    save.addEventListener('click', () => commit(false));
    acts.appendChild(save);
    if (U.isNarrow()) {
      const again = U.el('button', { class: 'btn ghost lg', text: t('quickAddSaveAnother'), 'data-testid': 'quickadd-save-another' });
      again.addEventListener('click', () => commit(true));
      acts.appendChild(again);
    }
    content.appendChild(acts);

    function parsed() {
      const raw = input.value;
      const p = window.QuickParse.parse(raw, U.now());
      if (override !== 'auto') {
        if (override === 'event') {
          if (p.kind === 'event') return p;
          return Object.assign({}, p, {
            kind: 'event',
            start: p.dueDate ? new Date(p.dueDate.getFullYear(), p.dueDate.getMonth(), p.dueDate.getDate(), 9, 0) : null,
            end: null,
          });
        }
        // A parsed clock time is still a real moment: turning it into a to-do
        // makes it that day's deadline instead of throwing the date away.
        const due = p.dueDate || (p.start ? new Date(p.start.getFullYear(), p.start.getMonth(), p.start.getDate(), 0, 0) : null);
        return Object.assign({}, p, { kind: 'todo', dueDate: due });
      }
      return p;
    }

    function draw() {
      typeRow.querySelectorAll('button').forEach((b, i) => {
        b.classList.toggle('on', ['auto', 'event', 'todo'][i] === override);
      });
      preview.innerHTML = '';
      const p = parsed();
      if (!input.value.trim()) {
        preview.appendChild(U.el('div', { class: 'muted', style: 'padding:14px', text: t('quickAddPlaceholder') }));
        save.disabled = true;
        return;
      }
      save.disabled = false;
      const badge = U.el('div', { class: 'quick-kind ' + (p.kind === 'event' ? 'event' : 'todo') });
      badge.dataset.testid = 'quickadd-kind';
      badge.textContent = p.kind === 'event' ? t('quickAddEvent') : t('quickAddTodo');
      preview.appendChild(badge);
      preview.appendChild(U.el('div', { class: 'quick-title', text: p.title || input.value.trim(), 'data-testid': 'quickadd-title' }));
      let when = '';
      if (p.kind === 'event') {
        if (!p.start) {
          p.start = new Date(U.now().getFullYear(), U.now().getMonth(), U.now().getDate(), U.now().getHours() + 1, 0);
          p.end = U.addMinutes(p.start, 60);
        }
        if (!p.end) p.end = U.addMinutes(p.start, 60);
        when = U.fmtMonthDayTime(p.start) + ' · ' + U.fmtTimeRange(p.start, p.end);
      } else if (p.dueDate) {
        when = t('deadlinePrefix', { d: U.fmtDeadline(p.dueDate) });
      } else {
        when = t('quickAddNoParse');
      }
      preview.appendChild(U.el('div', { class: 'quick-when', text: when, 'data-testid': 'quickadd-when' }));
      if (p.kind === 'event' && p.durationMin) {
        const m = p.durationMin;
        const label = m < 60
          ? m + (S.state.lang === 'zh' ? ' 分钟' : ' min')
          : (m / 60) + (S.state.lang === 'zh' ? ' 小时' : ' h');
        preview.appendChild(U.el('div', { class: 'quick-when muted', text: label }));
      }
    }

    function commit(again) {
      const p = parsed();
      if (!input.value.trim()) return;
      const title = (p.title || input.value).trim();
      if (!title) return;
      let created;
      if (p.kind === 'event') {
        const start = p.start || new Date(U.now().getFullYear(), U.now().getMonth(), U.now().getDate(), U.now().getHours() + 1, 0);
        created = S.createEvent({
          summary: title, startDt: start, endDt: p.end || U.addMinutes(start, 60),
          calendarId: S.state.calendars[0] ? S.state.calendars[0].id : 1,
        });
      } else {
        created = S.createTodo({ summary: title, dueDate: p.dueDate || null });
      }
      const announce = () => UI.toast(t('createdToast', { t: created.summary }), {
        undo: () => {
          if (p.kind === 'event') S.softDeleteEvent(created.id); else S.softDeleteTodo(created.id);
          App.render();
        },
      });
      S.state.quickAddText = '';
      S.state.highlight = p.kind === 'event'
        ? { testid: 'event-block', testids: ['event-block', 'action-event'], id: created.id }
        : { testid: 'todo-tile', testids: ['todo-tile', 'action-todo'], id: created.id };
      if (again) {
        input.value = '';
        S.state.quickAddText = '';
        draw();
        input.focus();
        announce();
        return;
      }
      App.back();
      App.render();
      announce();
    }

    input.addEventListener('input', () => {
      text = input.value;
      S.state.quickAddText = text;
      draw();
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); commit(false); }
    });
    draw();
    setTimeout(() => input.focus(), 30);
    App.escapeHandler = () => App.back();
    return root;
  }

  App.defineView('quickadd', renderQuickAdd);
})();
