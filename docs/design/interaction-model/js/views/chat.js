/* AI assistant: reads the calendar and to-dos; writes are proposed first. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function lastUserText() {
    for (let i = S.state.ai.messages.length - 1; i >= 0; i -= 1) {
      if (S.state.ai.messages[i].role === 'user') return S.state.ai.messages[i].text;
    }
    return '';
  }

  function renderChat() {
    const root = U.el('div', { class: 'page' });
    const narrow = U.isNarrow();

    const head = U.el('div', { class: 'page-head' + (narrow ? ' mobile' : '') });
    head.appendChild(UI.iconButton('chevronLeft', t('back'), () => App.back(), { cls: 'back-btn' }));
    const wrap = U.el('div', { class: 'page-title-wrap' });
    wrap.appendChild(U.el('h1', { class: 'page-title', text: t('pageChat') }));
    wrap.appendChild(U.el('div', { class: 'page-sub', text: !S.state.ai.enabled ? t('aiDisabled') : (S.state.ai.configured ? t('aiConfigured', { m: S.state.ai.model }) : t('aiNotConfigured')) }));
    head.appendChild(wrap);
    if (S.state.ai.messages.length) {
      const clear = UI.iconButton('trash', t('chatClear'), () => {
        UI.confirm({ title: t('chatClear'), message: t('chatClearBody'), danger: true, confirmText: t('chatClear') }).then((ok) => {
          if (!ok) return;
          S.state.ai.messages = [];
          S.state.ai.pending = false;
          App.render();
        });
      }, { testid: 'chat-clear' });
      head.appendChild(clear);
    }
    const cfg = UI.iconButton('settings', t('aiConfig'), () => App.go('settings', { section: 'advanced' }));
    head.appendChild(cfg);
    root.appendChild(head);

    if (!S.state.ai.enabled) {
      const empty = U.el('div', { class: 'page-scroll' });
      const inner = U.el('div', { class: 'page-content narrow' });
      inner.appendChild(UI.emptyState('sparkles', t('aiDisabled'), t('aiDisabledHint'), [
        { label: t('aiEnable'), primary: true, action: () => { S.state.ai.enabled = true; App.render(); } },
      ]));
      empty.appendChild(inner);
      root.appendChild(empty);
      return root;
    }

    if (!S.state.ai.configured) {
      const empty = U.el('div', { class: 'page-scroll' });
      const inner = U.el('div', { class: 'page-content narrow' });
      inner.appendChild(UI.emptyState('sparkles', t('aiNoKey'), '', [
        { label: t('aiConfig'), primary: true, action: () => App.go('settings', { section: 'advanced' }) },
      ]));
      empty.appendChild(inner);
      root.appendChild(empty);
      return root;
    }

    const scroll = U.el('div', { class: 'chat-scroll', 'data-testid': 'chat-scroll' });
    if (!S.state.ai.messages.length) {
      const intro = U.el('div', { class: 'pagecard' });
      intro.style.alignSelf = 'stretch';
      intro.innerHTML = `<h2>${U.esc(t('chatEmptyTitle'))}</h2><p>${U.esc(t('chatEmptyHint'))}</p>`;
      scroll.appendChild(intro);
      // One example, not a menu of prompt chips: the user came here with a
      // question, not to browse a template gallery.
      const example = U.el('button', { class: 'chip-btn', text: t('chatExample'), 'data-testid': 'chat-example' });
      example.addEventListener('click', () => send(t('chatExample')));
      scroll.appendChild(example);
    }
    const lastAssistant = S.state.ai.messages.reduce((n, m, i) => (m.role === 'assistant' ? i : n), -1);
    S.state.ai.messages.forEach((m, i) => scroll.appendChild(messageNode(m, i === lastAssistant)));
    if (S.state.ai.pending) {
      const typing = U.el('div', { class: 'msg assistant' });
      typing.innerHTML = `<div class="bubble"><span class="typing"><i></i><i></i><i></i></span></div>`;
      scroll.appendChild(typing);
    }
    root.appendChild(scroll);

    const wrapInput = U.el('div', { class: 'chat-input-wrap' });
    const box = U.el('div', { class: 'chat-input' });
    const ta = U.el('textarea', { rows: '1', placeholder: t('chatPlaceholder'), 'aria-label': t('chatPlaceholder'), 'data-testid': 'chat-input' });
    box.appendChild(ta);
    const sendBtn = UI.iconButton('send', t('send'), () => send(ta.value));
    sendBtn.dataset.testid = 'chat-send';
    sendBtn.classList.add('active');
    box.appendChild(sendBtn);
    // While a reply is pending the field is closed: leaving it editable either
    // drops what the user types or silently queues a second question.
    if (S.state.ai.pending) {
      ta.disabled = true;
      ta.placeholder = t('aiWaiting');
      sendBtn.disabled = true;
      sendBtn.classList.remove('active');
    }
    wrapInput.appendChild(box);
    // The input is 24px tall by design; the padded container forwards taps.
    box.addEventListener('click', (e) => { if (e.target === box) ta.focus(); });
    wrapInput.addEventListener('click', (e) => { if (e.target === wrapInput) ta.focus(); });
    root.appendChild(wrapInput);

    ta.addEventListener('input', () => {
      ta.style.height = 'auto';
      ta.style.height = Math.min(120, ta.scrollHeight) + 'px';
    });
    ta.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(ta.value); }
    });

    requestAnimationFrame(() => { scroll.scrollTop = scroll.scrollHeight; });
    setTimeout(() => ta.focus(), 30);
    return root;

    function send(text) {
      const q = (text || '').trim();
      if (!q || S.state.ai.pending) return;
      S.state.ai.messages.push({ role: 'user', text: q });
      S.state.ai.pending = true;
      App.render();
      setTimeout(() => {
        S.state.ai.pending = false;
        S.state.ai.messages.push(replyFor(q));
        App.render();
      }, 850);
    }
  }

  function messageNode(m, latest) {
    const node = U.el('div', { class: 'msg ' + m.role });
    node.appendChild(U.el('div', { class: 'who', text: m.role === 'user' ? (S.state.lang === 'zh' ? '你' : 'You') : t('aiAssistant') }));
    node.appendChild(U.el('div', { class: 'bubble', text: m.text }));
    if (m.proposal) {
      const card = U.el('div', { class: 'ai-action' });
      card.dataset.testid = 'ai-proposal';
      card.innerHTML = `<div class="at">${ICON('sparkles', 13)}<span>${U.esc(t('aiProposal'))}</span></div><div class="as">${U.esc(m.proposal.label)}</div>`;
      if (m.proposal.state === 'applied' || m.proposal.state === 'rejected') {
        const done = U.el('div', { class: 'as', style: m.proposal.state === 'applied' ? 'color:var(--green)' : 'color:var(--ink-3)' });
        done.innerHTML = m.proposal.state === 'applied' ? ICON('check', 12) + ' ' + U.esc(t('aiApplied')) : U.esc(t('aiRejected'));
        card.appendChild(done);
        node.appendChild(card);
        return node;
      }
      const acts = U.el('div', { class: 'ab' });
      const apply = U.el('button', { class: 'btn primary sm', text: t('aiApply'), 'data-testid': 'ai-apply' });
      const reject = U.el('button', { class: 'btn ghost sm', text: t('aiReject') });
      apply.addEventListener('click', () => {
        if (m.proposal.state === 'applied' || m.proposal.state === 'rejected') return;
        m.proposal.state = 'applied';
        m.proposal.run();
        App.render();
        UI.toast(t('aiApplied'));
      });
      reject.addEventListener('click', () => {
        if (m.proposal.state === 'applied' || m.proposal.state === 'rejected') return;
        m.proposal.state = 'rejected';
        App.render();
      });
      acts.appendChild(apply); acts.appendChild(reject);
      card.appendChild(acts);
      node.appendChild(card);
      return node;
    }
    if (latest && m.role === 'assistant') {
      // The latest answer carries the four things a next step can be. Each one
      // opens a real surface instead of silently writing.
      const row = U.el('div', { class: 'chat-actions', 'data-testid': 'chat-actions' });
      [
        ['calendar', t('chatQuickAddEvent'), () => App.openComposer('event', { summary: (lastUserText() || '').slice(0, 60) })],
        ['checkSquare', t('chatQuickAddTodo'), () => App.openComposer('todo', { summary: (lastUserText() || '').slice(0, 60) })],
        ['clockPlus', t('chatQuickSchedule'), () => scheduleSheet()],
        ['list', t('chatQuickBreakdown'), () => breakdownSheet(lastUserText())],
      ].forEach(([icon, label, action]) => {
        const b = U.el('button', { class: 'chip-btn' });
        b.innerHTML = ICON(icon, 12) + `<span>${U.esc(label)}</span>`;
        b.dataset.testid = 'chat-action-' + label;
        b.addEventListener('click', action);
        row.appendChild(b);
      });
      node.appendChild(row);
    }
    return node;
  }

  // A repeating to-do has no single row to schedule: the allocation has to name
  // the occurrence it belongs to. Find the first occurrence on or after the
  // requested day, keeping the requested clock time, so the write is visible.
  function occurrenceForSchedule(todo, start) {
    if (!todo || !todo.recurrence) return { at: start, occurrenceId: null };
    let day = U.startOfDay(start);
    for (let i = 0; i < 14; i++) {
      if (S.matchesRule(todo, day)) {
        const at = new Date(day.getFullYear(), day.getMonth(), day.getDate(), start.getHours(), start.getMinutes());
        return { at, occurrenceId: S.occurrenceIdFor(todo, day) };
      }
      day = U.addDays(day, 1);
    }
    return null;
  }

  function scheduleSheet() {
    const candidates = S.schedulableTodos();
    if (!candidates.length) {
      UI.toast(t('slotEmpty'), { warn: true });
      return;
    }
    UI.sheet({
      title: t('chatSchedulePick'),
      body(host, close) {
        const box = U.el('div', { class: 'picker', 'data-testid': 'chat-schedule' });
        host.appendChild(box);
        const todoSel = U.el('select', { class: 'select' });
        candidates.forEach((todo) => todoSel.appendChild(U.el('option', { value: String(todo.id), text: todo.summary })));
        box.appendChild(U.el('div', { class: 'field-label', text: t('scheduleExec') }));
        box.appendChild(todoSel);
        const start = U.el('input', { class: 'input', type: 'datetime-local' });
        const now = U.now();
        const first = new Date(now.getFullYear(), now.getMonth(), now.getDate(), Math.min(23, now.getHours() + 1), 0);
        start.value = U.toInputDateTime(first);
        box.appendChild(U.el('div', { class: 'field-label', text: t('starts') }));
        box.appendChild(start);
        const dur = U.el('select', { class: 'select' });
        [30, 45, 60, 90, 120].forEach((m) => dur.appendChild(U.el('option', {
          value: String(m),
          text: m < 60 ? m + (S.state.lang === 'zh' ? ' 分钟' : ' min') : (m / 60) + (S.state.lang === 'zh' ? ' 小时' : ' h'),
        })));
        dur.value = '60';
        box.appendChild(U.el('div', { class: 'field-label', text: t('ends') }));
        box.appendChild(dur);
        const apply = U.el('button', { class: 'btn primary', text: t('confirm'), 'data-testid': 'chat-schedule-apply' });
        apply.addEventListener('click', () => {
          const s = U.fromInputDateTime(start.value);
          if (!s) return;
          const todoId = Number(todoSel.value);
          const todo = S.todoById(todoId);
          const occ = occurrenceForSchedule(todo, s);
          if (!occ) {
            UI.toast(t('scheduleNoOccurrence'), { warn: true });
            return;
          }
          S.createAllocation({
            todoId, occurrenceId: occ.occurrenceId,
            startAt: occ.at, endAt: U.addMinutes(occ.at, parseInt(dur.value, 10)),
          });
          close(null);
          App.render();
          UI.toast(occ.occurrenceId && !U.sameDay(occ.at, s)
            ? t('scheduleMovedToOccurrence', { d: U.fmtMonthDayTime(occ.at) })
            : t('aiApplied'), { duration: 2400 });
        });
        box.appendChild(apply);
      },
    });
  }

  function breakdownSheet(text) {
    const candidates = S.pendingTodos();
    if (!candidates.length) {
      UI.toast(t('chatBreakdownEmpty'), { warn: true });
      return;
    }
    const matched = candidates.find((x) => text && (text.includes(x.summary) || x.summary.includes(text.slice(0, 4))));
    const target = matched || candidates[0];
    const parts = [
      S.state.lang === 'zh' ? '收集资料' : 'Gather material',
      S.state.lang === 'zh' ? '完成初稿' : 'Draft the first pass',
      S.state.lang === 'zh' ? '检查并收尾' : 'Review and finish',
    ];
    UI.sheet({
      title: t('chatBreakdownTitle'),
      subtitle: target.summary,
      body(host, close) {
        const box = U.el('div', { class: 'picker', 'data-testid': 'chat-breakdown' });
        host.appendChild(box);
        const checks = [];
        parts.forEach((label, i) => {
          const row = U.el('label', { class: 'list-row' });
          const cb = U.el('input', { type: 'checkbox', checked: 'checked' });
          cb.dataset.testid = 'chat-breakdown-item';
          checks.push(cb);
          row.appendChild(cb);
          row.appendChild(U.el('span', { class: 'main', html: `<span class="t">${U.esc(label)}</span>` }));
          box.appendChild(row);
        });
        const apply = U.el('button', { class: 'btn primary', text: t('aiApply'), 'data-testid': 'chat-breakdown-apply' });
        apply.addEventListener('click', () => {
          let n = 0;
          checks.forEach((cb, i) => {
            if (!cb.checked) return;
            S.createTodo({ summary: parts[i], parentId: target.id });
            n += 1;
          });
          close(null);
          App.render();
          UI.toast(t('chatBreakdownApplied', { n }));
        });
        box.appendChild(apply);
      },
    });
  }

  function replyFor(q) {
    const lower = q.toLowerCase();
    const proj = S.actionProjection(S.state.actionDate);
    if (/空闲|free|剩多少/.test(lower)) {
      const busy = proj.allocations.reduce((sum, x) => sum + U.minutesBetween(x.allocation.startAt, x.allocation.endAt), 0)
        + proj.events.reduce((sum, e) => sum + U.minutesBetween(e.startDt, e.endDt), 0);
      const total = 12 * 60;
      const free = Math.max(0, total - busy);
      const h = Math.floor(free / 60), m = free % 60;
      return { role: 'assistant', text: S.state.lang === 'zh'
        ? `今天 08:00–20:00 之间已排 ${Math.floor(busy / 60)} 小时 ${busy % 60} 分，空闲约 ${h} 小时 ${m} 分。`
        : `Between 08:00 and 20:00 today you have ${Math.floor(busy / 60)}h ${busy % 60}m booked, leaving about ${h}h ${m}m free.` };
    }
    if (/安排|schedule|排到/.test(lower)) {
      const named = S.liveTodos().find((x) => {
        const name = x.summary.toLowerCase();
        return lower.includes(name) || lower.includes(x.summary);
      });
      const target = named || S.liveTodos().find((x) => !x.recurrence && S.isOpen(x)) || S.liveTodos()[0];
      if (!target) return { role: 'assistant', text: S.state.lang === 'zh' ? '目前没有可安排的待办。' : 'There is no open to-do to schedule.' };
      const wantsTomorrow = /明天|tomorrow/.test(lower);
      const day = U.addDays(U.startOfDay(U.now()), wantsTomorrow ? 1 : 0);
      const hour = /下午|afternoon/.test(lower) ? 14 : 9;
      let start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, 0);
      let end = U.addMinutes(start, 60);
      const occ = occurrenceForSchedule(target, start);
      if (!occ) {
        return {
          role: 'assistant',
          text: S.state.lang === 'zh'
            ? '这个重复待办在接下来的两周里没有可安排的发生日，所以我没有写入任何时间。'
            : 'That repeating to-do has no occurrence in the next two weeks, so I did not book any time.',
        };
      }
      const shifted = !U.sameDay(occ.at, start);
      start = occ.at;
      end = U.addMinutes(start, 60);
      return {
        role: 'assistant',
        text: S.state.lang === 'zh'
          ? (named ? '可以。我不会直接写入，先给你确认。' : '没在待办里找到你提到的名字，先按第一条未完成待办给方案；如果不对，请改名后再试。')
            + (target.recurrence && shifted ? ' 这是重复待办，会排到它最近的发生日。' : '')
          : (named ? 'I can. Nothing is written until you confirm.' : 'I could not match that name, so this targets the first open to-do; rename it and ask again if that is wrong.')
            + (target.recurrence && shifted ? ' This repeats, so it books its next occurrence.' : ''),
        proposal: {
          label: t('aiProposalSchedule', { t: target.summary, when: U.fmtMonthDayTime(start) }),
          run: () => {
            S.createAllocation({ todoId: target.id, occurrenceId: occ.occurrenceId, startAt: start, endAt: end });
            App.render();
          },
        },
      };
    }
    if (/截止|due|这周|week/.test(lower)) {
      const items = S.liveTodos().filter((x) => S.isOpen(x) && x.dueDate);
      const lines = items.slice(0, 5).map((x) => `· ${x.summary} — ${U.fmtDeadline(x.dueDate)}`).join('\n');
      return { role: 'assistant', text: (S.state.lang === 'zh' ? '接下来有截止的事项：\n' : 'Upcoming deadlines:\n') + lines };
    }
    if (/创建|新建|create|加一个/.test(lower)) {
      return {
        role: 'assistant',
        text: S.state.lang === 'zh' ? '我可以创建，先确认内容。' : 'I can create it once you confirm.',
        proposal: {
          label: t('aiProposalCreate', { t: S.state.lang === 'zh' ? '新任务' : 'New task' }),
          run: () => { S.createTodo({ summary: S.state.lang === 'zh' ? '新任务' : 'New task' }); App.render(); },
        },
      };
    }
    return {
      role: 'assistant',
      text: S.state.lang === 'zh'
        ? '我可以读取今天的日程与待办、计算空闲时间，并在你确认后计划执行时间或创建条目。试试问「今天还剩多少空闲时间」。'
        : 'I can read today’s events and to-dos, compute free time, and — after you confirm — reserve time or create items. Try “how much free time is left today”.',
    };
  }

  App.defineView('chat', renderChat);
})();
