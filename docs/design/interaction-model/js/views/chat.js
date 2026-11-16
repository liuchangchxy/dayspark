/* AI assistant: reads the calendar and to-dos; writes are proposed first. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function renderChat() {
    const root = U.el('div', { class: 'page' });
    const narrow = U.isNarrow();

    const head = U.el('div', { class: 'page-head' + (narrow ? ' mobile' : '') });
    head.appendChild(UI.iconButton('chevronLeft', t('back'), () => App.back(), { cls: 'back-btn' }));
    const wrap = U.el('div', { class: 'page-title-wrap' });
    wrap.appendChild(U.el('h1', { class: 'page-title', text: t('pageChat') }));
    wrap.appendChild(U.el('div', { class: 'page-sub', text: !S.state.ai.enabled ? t('aiDisabled') : (S.state.ai.configured ? t('aiConfigured', { m: S.state.ai.model }) : t('aiNotConfigured')) }));
    head.appendChild(wrap);
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
      const prompts = S.state.lang === 'zh'
        ? ['今天还剩多少空闲时间？', '把「Q4 预算表」安排到明天上午', '这周有什么截止事项？']
        : ['How much free time is left today?', 'Schedule “Q4 budget” tomorrow morning', 'What is due this week?'];
      const box = U.el('div', { class: 'chip-row', style: 'margin-top:4px' });
      prompts.forEach((p) => {
        const b = U.el('button', { class: 'chip-btn', text: p });
        b.addEventListener('click', () => send(p));
        box.appendChild(b);
      });
      scroll.appendChild(box);
    }
    S.state.ai.messages.forEach((m) => scroll.appendChild(messageNode(m)));
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
    wrapInput.appendChild(box);
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

  function messageNode(m) {
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
      const apply = U.el('button', { class: 'btn primary sm', text: t('aiApply') });
      apply.dataset.testid = 'ai-apply';
      const reject = U.el('button', { class: 'btn ghost sm', text: t('aiReject') });
      apply.addEventListener('click', () => {
        // A double-click or a synchronous second dispatch would otherwise run
        // the write twice. The state check is the guard, not the re-render.
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
    }
    return node;
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
      // Act on the to-do the user named. Falling back to "the first open one"
      // meant the proposal card could describe a different task than the one
      // asked about, and applying it wrote to that other task.
      const named = S.liveTodos().find((x) => {
        const name = x.summary.toLowerCase();
        return lower.includes(name) || lower.includes(x.summary);
      });
      const target = named || S.liveTodos().find((x) => !x.recurrence && S.isOpen(x)) || S.liveTodos()[0];
      if (!target) return { role: 'assistant', text: S.state.lang === 'zh' ? '目前没有可安排的待办。' : 'There is no open to-do to schedule.' };
      const wantsTomorrow = /明天|tomorrow/.test(lower);
      const day = U.addDays(U.startOfDay(U.now()), wantsTomorrow ? 1 : 0);
      const hour = /下午|afternoon/.test(lower) ? 14 : 9;
      const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, 0);
      const end = U.addMinutes(start, 60);
      return {
        role: 'assistant',
        text: S.state.lang === 'zh'
          ? (named ? '可以。我不会直接写入，先给你确认。' : '没在待办里找到你提到的名字，先按第一条未完成待办给方案；如果不对，请改名后再试。')
          : (named ? 'I can. Nothing is written until you confirm.' : 'I could not match that name, so this targets the first open to-do; rename it and ask again if that is wrong.'),
        proposal: {
          label: t('aiProposalSchedule', { t: target.summary, when: U.fmtMonthDayTime(start) }),
          run: () => {
            S.createAllocation({ todoId: target.id, startAt: start, endAt: end });
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
