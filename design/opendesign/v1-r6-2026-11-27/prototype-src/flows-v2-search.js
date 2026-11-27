/* DaySpark prototype v2 — real full-text search with keyboard navigation. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = P.esc;
  let sel = 0;
  /* The old renderer cut each group at a hard limit and never showed the
     remainder. Keep the first screenful but expose the rest in place. */
  const PAGE = { todos: 6, events: 5 };
  const expanded = { todos: false, events: false };
  // Actual visit order, newest first. Seeded from a first open, then written
  // by search-open-*; deleted objects are filtered on read, never rendered stale.
  const RECENT_KEY = 'dayspark.prototype.recent.v1';
  function recentIds() {
    try {
      const raw = JSON.parse(localStorage.getItem(RECENT_KEY) || '[]');
      return Array.isArray(raw) ? raw.filter((x) => x && x.id && (x.type === 'todo' || x.type === 'event')) : [];
    } catch (_) { return []; }
  }
  function pushRecent(type, id) {
    if (!id) return;
    const next = [{ type, id }].concat(recentIds().filter((x) => !(x.type === type && x.id === id))).slice(0, 8);
    try { localStorage.setItem(RECENT_KEY, JSON.stringify(next)); } catch (_) {}
  }
  function recentRows() {
    const live = [];
    recentIds().forEach((x) => {
      if (x.type === 'todo') {
        const t = (typeof allTodos === 'function' ? allTodos() : []).find((v) => v.id === x.id);
        if (t && !state.deletedTodos.includes(t.id)) live.push(rowTodo(t, '', '最近打开'));
      } else {
        const e = EVENT_BYID(x.id);
        if (e && !state.deletedEvents.includes(e.id)) live.push(rowEvent(e, '', '最近打开'));
      }
    });
    return live;
  }
  function EVENT_BYID(id) { return EVENTS.find((e) => e.id === id) || null; }

  function hl(text, query) {
    const t = esc(text);
    const qq = String(query || '').trim();
    if (!qq) return t;
    try {
      return t.replace(new RegExp('(' + qq.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'gi'), '<mark>$1</mark>');
    } catch (_) { return t; }
  }
  function hay(t) {
    return [t.title, t.note, (t.tags || []).join(' '), (t.subtasks || []).map((s) => s.title).join(' '), t.loc].filter(Boolean).join(' ').toLowerCase();
  }
  function matchCal(t) { return calOf(t.cal).name + ' ' + (t.cal || ''); }

  function body(query) {
    const raw = String(query || '').trim();
    const qtext = raw.toLowerCase();
    if (!qtext) {
      const recents = recentRows();
      const fallback = recents.length ? '' : `<div class="cmd-empty">还没有打开过待办或日程。搜一个标题，或从下面开始。</div>`;
      return `<div class="cmd-group">最近</div>` + (recents.length ? recents.slice(0, 4).join('') : fallback) +
        `<div class="cmd-group">动作</div>` + actionRows('');
    }
    const todos = TODOS.concat(state.localTodos || []).filter((t) => !state.deletedTodos.includes(t.id) && (hay(t).includes(qtext) || matchCal(t).toLowerCase().includes(qtext)));
    const events = EVENTS.filter((e) => !state.deletedEvents.includes(e.id) && (hay(e).includes(qtext) || matchCal(e).toLowerCase().includes(qtext)));
    if (!todos.length && !events.length) {
      return `<div class="proto-search-empty"><div>没有找到「${esc(raw)}」</div><button type="button" class="proto-btn primary" style="margin-top:10px" data-proto-action="search-new-todo">用这句话新建待办</button></div>` + `<div class="cmd-group">动作</div>` + actionRows(raw);
    }
    const shownTodos = expanded.todos ? todos : todos.slice(0, PAGE.todos);
    const shownEvents = expanded.events ? events : events.slice(0, PAGE.events);
    let out = '';
    if (todos.length) {
      out += '<div class="cmd-group">待办 · ' + todos.length + '</div>' + shownTodos.map((t) => rowTodo(t, raw)).join('');
      if (todos.length > PAGE.todos) out += moreRow('todos', shownTodos.length, todos.length, expanded.todos);
    }
    if (events.length) {
      out += '<div class="cmd-group">日程 · ' + events.length + '</div>' + shownEvents.map((e) => rowEvent(e, raw)).join('');
      if (events.length > PAGE.events) out += moreRow('events', shownEvents.length, events.length, expanded.events);
    }
    out += '<div class="cmd-group">动作</div>' + actionRows(raw);
    return out;
  }
  function moreRow(group, shown, total, isOpen) {
    const label = group === 'todos' ? '待办' : '日程';
    if (isOpen) {
      return `<button type="button" class="cmd-more" data-proto-action="search-more" data-group="${group}">收起${label}，只看前 ${group === 'todos' ? PAGE.todos : PAGE.events} 项</button>`;
    }
    return `<button type="button" class="cmd-more" data-proto-action="search-more" data-group="${group}">显示其余 ${total - shown} 项${label}（共 ${total} 项）</button>`;
  }
  // Which field actually matched. A hit on a note or a subtask is otherwise
  // invisible: the row shows a title with no highlighted word.
  function matchWhy(item, query, fields) {
    const qtext = String(query || '').trim().toLowerCase();
    if (!qtext) return '';
    const hit = fields.find(([name, value]) => value && String(value).toLowerCase().includes(qtext));
    if (!hit || !hit[0] || hit[0] === 'title') return '';
    const snippet = String(hit[1]).replace(/\s+/g, ' ').trim();
    const at = snippet.toLowerCase().indexOf(qtext);
    const from = Math.max(0, at - 8);
    const text = (from ? '…' : '') + snippet.slice(from, at + qtext.length + 18) + (snippet.length > at + qtext.length + 18 ? '…' : '');
    return ` · 命中${hit[0]}「${text}」`;
  }
  function rowTodo(t, query, why) {
    const reason = why ? '' : matchWhy(t, query, [['标题', t.title], ['备注', t.note], ['标签', (t.tags || []).join('、')], ['子任务', (t.subtasks || []).map((x) => x.title).join('、')], ['日历', calOf(t.cal).name]]);
    return `<button type="button" class="cmd-row proto-search" data-idx data-proto-action="search-open-todo" data-id="${t.id}">
      <span class="check ${isDone(t) ? 'is-on' : ''}" style="pointer-events:none">${isDone(t) ? ico('check', 7) : ''}</span>
      <span class="cmd-row-main"><span class="cmd-row-t">${hl(t.title, query)}</span><span class="cmd-row-m">${esc(calOf(t.cal).name)}${t.due ? ' · 截止 ' + dueText(t) : ''}${(t.tags || []).length ? ' · ' + esc(t.tags.join('、')) : ''}${esc(reason)}</span></span>
      <span class="cmd-row-side">${why ? esc(why) : '待办'}</span></button>`;
  }
  function eventWhen(e) {
    if (e.startDate && e.endDate) return mdShort(e.startDate) + '–' + mdShort(e.endDate) + ' · 跨天';
    if (e.allDay) return mdShort(e.date || TODAY) + ' · 全天';
    const day = mdShort(e.date || e.startDate || TODAY);
    if (!e.start) return day;
    const end = e.end && e.end > e.start ? '–' + e.end : '';
    return day + ' · ' + e.start + end;
  }
  function rowEvent(e, query, why) {
    const reason = why ? '' : matchWhy(e, query, [['标题', e.title], ['备注', e.note], ['地点', e.loc], ['日历', calOf(e.cal).name]]);
    return `<button type="button" class="cmd-row proto-search" data-idx data-proto-action="search-open-event" data-id="${e.id}">
      ${ico('calendar', 14)}<span class="cmd-row-main"><span class="cmd-row-t">${hl(e.title, query)}</span><span class="cmd-row-m">${esc(calOf(e.cal).name)} · ${esc(eventWhen(e))}${esc(reason)}</span></span>
      <span class="cmd-row-side">${why ? esc(why) : '日程'}</span></button>`;
  }
  function actionRows(query) {
    return `<button type="button" class="cmd-row" data-idx data-proto-action="search-new-todo">${ico('plus', 14)}<span class="cmd-row-main"><span class="cmd-row-t">新建待办</span><span class="cmd-row-m">${query ? '标题“' + esc(query) + '”' : '进入整页创建'}</span></span><span class="cmd-row-side">动作</span></button>
      <button type="button" class="cmd-row" data-idx data-proto-action="search-new-event">${ico('calendar', 14)}<span class="cmd-row-main"><span class="cmd-row-t">新建日程</span><span class="cmd-row-m">进入整页创建</span></span><span class="cmd-row-side">动作</span></button>
      <button type="button" class="cmd-row" data-idx data-proto-action="search-ai">${ico('sparkles', 14)}<span class="cmd-row-main"><span class="cmd-row-t">问 AI</span><span class="cmd-row-m">${query ? '关于“' + esc(query) + '”' : '打开助手'}</span></span><span class="cmd-row-side">动作</span></button>
      <button type="button" class="cmd-row" data-idx data-proto-action="search-settings">${ico('settings', 14)}<span class="cmd-row-main"><span class="cmd-row-t">打开设置</span></span><span class="cmd-row-side">动作</span></button>`;
  }

  let lastQ = null;
  let lastExp = '';
  function paintSearch(root) {
    if (state.screen !== 'command') return;
    const expKey = (expanded.todos ? 't' : '') + (expanded.events ? 'e' : '');
    if (state.cmdQuery !== lastQ) {
      lastQ = state.cmdQuery;
      sel = 0;
      expanded.todos = false;
      expanded.events = false;
      lastExp = '';
    } else if (expKey !== lastExp) {
      // Expanding a group re-renders; keep keyboard position instead of
      // snapping back to the first row and firing it on the next Enter.
      lastExp = expKey;
    }
    const el = q('.cmd-body, .m-cmd-body', root);
    if (!el) return;
    const focused = document.activeElement && document.activeElement.closest && document.activeElement.closest('.cmd-body, .m-cmd-body');
    const keepSel = focused ? sel : 0;
    if (el.dataset.v2 === expKey + '|' + String(state.cmdQuery)) return;
    el.dataset.v2 = expKey + '|' + String(state.cmdQuery);
    el.innerHTML = body(state.cmdQuery);
    el.querySelectorAll('[data-idx]').forEach((r, i) => r.dataset.idx = i);
    const rows = qa('.cmd-row[data-idx]', el);
    sel = Math.max(0, Math.min(keepSel, rows.length - 1));
    rows.forEach((r, i) => r.classList.toggle('is-sel', i === sel));
  }
  registerEnhancer(paintSearch);
  // Typing repaints only the result body. Replacing the whole frame on every
  // keystroke would drop the caret and abort Chinese IME composition.
  P.paintSearch = (root) => paintSearch(root || document);
  P.recordRecent = pushRecent;

  registerAction('search-more', (el) => {
    const group = el.dataset.group === 'events' ? 'events' : 'todos';
    expanded[group] = !expanded[group];
    render();
    // Keep the keyboard path usable after expanding: put focus back in the
    // search field so ArrowUp/Down/Enter still drive the result list.
    setTimeout(() => {
      const input = q('.cmd-input input, .m-cmd-input input');
      if (input) {
        input.focus();
        input.setSelectionRange(input.value.length, input.value.length);
      }
    }, 0);
  });

  document.addEventListener('keydown', (e) => {
    if (state.screen !== 'command') return;
    // Enter that confirms an IME candidate must never open a row. composition
    // is true during the candidate window; keyCode 229 covers the same event.
    if (e.isComposing || e.keyCode === 229) return;
    const rows = qa('.cmd-body .cmd-row[data-idx], .m-cmd-body .cmd-row[data-idx]');
    if (!rows.length) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      sel = (sel + (e.key === 'ArrowDown' ? 1 : -1) + rows.length) % rows.length;
      rows.forEach((r, i) => r.classList.toggle('is-sel', i === sel));
      rows[sel].scrollIntoView({ block: 'nearest' });
      return;
    }
    if (e.key === 'Enter') {
      const active = document.activeElement;
      const typing = active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA');
      // Do not hijack Enter on the "显示更多" button itself; once focus is
      // back in the search input, Enter opens the highlighted row.
      if (typing || !active || active === document.body) {
        e.preventDefault();
        (rows[sel] || rows[0]).click();
      }
    }
  });

  registerAction('search-open-todo', (el) => {
    window.__v2SearchOpen = true;
    pushRecent('todo', el.dataset.id);
    const qtext = state.cmdQuery || '';
    P.openTodo(el.dataset.id);
    state.drawerReturn = { screen: 'command', cmdQuery: qtext, variant: 'result' };
  });
  registerAction('search-open-event', (el) => {
    window.__v2SearchOpen = true;
    pushRecent('event', el.dataset.id);
    const qtext = state.cmdQuery || '';
    P.openEvent(el.dataset.id);
    state.drawerReturn = { screen: 'command', cmdQuery: qtext, variant: 'result' };
  });
  registerAction('search-ai', () => {
    P.baseGo('ai-chat');
    const qtext = state.cmdQuery || '';
    state.aiInput = qtext ? '关于「' + qtext + '」，' : '';
    P.syncHash(true);
    setTimeout(() => { const i = q('#ai-input'); if (i) { i.value = state.aiInput; i.focus(); } }, 40);
  });
  registerAction('search-settings', () => {
    P.baseGo('settings-home'); P.syncHash(true);
  });
})();
