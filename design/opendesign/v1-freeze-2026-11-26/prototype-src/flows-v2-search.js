/* DaySpark prototype v2 — real full-text search with keyboard navigation. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = P.esc;
  let sel = 0;

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
      const recents = TODOS.filter((t) => !isDone(t)).slice(0, 3);
      return `<div class="cmd-group">最近</div>` + recents.map((t) => rowTodo(t, '')).join('') +
        `<div class="cmd-group">动作</div>` + actionRows('');
    }
    const todos = TODOS.concat(state.localTodos || []).filter((t) => !state.deletedTodos.includes(t.id) && (hay(t).includes(qtext) || matchCal(t).toLowerCase().includes(qtext))).slice(0, 6);
    const events = EVENTS.filter((e) => !state.deletedEvents.includes(e.id) && (hay(e).includes(qtext) || matchCal(e).toLowerCase().includes(qtext))).slice(0, 5);
    if (!todos.length && !events.length) {
      return `<div class="proto-search-empty"><div>没有找到「${esc(raw)}」</div><button type="button" class="proto-btn primary" style="margin-top:10px" data-proto-action="search-new-todo">用这句话新建待办</button></div>` + `<div class="cmd-group">动作</div>` + actionRows(raw);
    }
    let out = '';
    if (todos.length) out += '<div class="cmd-group">待办 · ' + todos.length + '</div>' + todos.map((t) => rowTodo(t, raw)).join('');
    if (events.length) out += '<div class="cmd-group">日程 · ' + events.length + '</div>' + events.map((e) => rowEvent(e, raw)).join('');
    out += '<div class="cmd-group">动作</div>' + actionRows(raw);
    return out;
  }
  function rowTodo(t, query) {
    return `<button type="button" class="cmd-row proto-search" data-idx data-proto-action="search-open-todo" data-id="${t.id}">
      <span class="check ${isDone(t) ? 'is-on' : ''}" style="pointer-events:none">${isDone(t) ? ico('check', 7) : ''}</span>
      <span class="cmd-row-main"><span class="cmd-row-t">${hl(t.title, query)}</span><span class="cmd-row-m">${esc(calOf(t.cal).name)}${t.due ? ' · 截止 ' + dueText(t) : ''}${(t.tags || []).length ? ' · ' + esc(t.tags.join('、')) : ''}</span></span>
      <span class="cmd-row-side">待办</span></button>`;
  }
  function rowEvent(e, query) {
    return `<button type="button" class="cmd-row proto-search" data-idx data-proto-action="search-open-event" data-id="${e.id}">
      ${ico('calendar', 14)}<span class="cmd-row-main"><span class="cmd-row-t">${hl(e.title, query)}</span><span class="cmd-row-m">${esc(calOf(e.cal).name)} · ${mdShort(e.date || e.startDate || TODAY)}${e.loc ? ' · ' + esc(e.loc) : ''}</span></span>
      <span class="cmd-row-side">日程</span></button>`;
  }
  function actionRows(query) {
    return `<button type="button" class="cmd-row" data-idx data-proto-action="search-new-todo">${ico('plus', 14)}<span class="cmd-row-main"><span class="cmd-row-t">新建待办</span><span class="cmd-row-m">${query ? '标题“' + esc(query) + '”' : '进入整页创建'}</span></span><span class="cmd-row-side">动作</span></button>
      <button type="button" class="cmd-row" data-idx data-proto-action="search-new-event">${ico('calendar', 14)}<span class="cmd-row-main"><span class="cmd-row-t">新建日程</span><span class="cmd-row-m">进入整页创建</span></span><span class="cmd-row-side">动作</span></button>
      <button type="button" class="cmd-row" data-idx data-proto-action="search-ai">${ico('sparkles', 14)}<span class="cmd-row-main"><span class="cmd-row-t">问 AI</span><span class="cmd-row-m">${query ? '关于“' + esc(query) + '”' : '打开助手'}</span></span><span class="cmd-row-side">动作</span></button>
      <button type="button" class="cmd-row" data-idx data-proto-action="search-settings">${ico('settings', 14)}<span class="cmd-row-main"><span class="cmd-row-t">打开设置</span></span><span class="cmd-row-side">动作</span></button>`;
  }

  registerEnhancer((root) => {
    if (state.screen !== 'command') return;
    const el = q('.cmd-body, .m-cmd-body', root);
    if (!el) return;
    el.innerHTML = body(state.cmdQuery);
    el.dataset.v2 = '1';
    const rows = qa('.cmd-row[data-idx]', el);
    sel = Math.max(0, Math.min(sel, rows.length - 1));
    rows.forEach((r, i) => r.classList.toggle('is-sel', i === sel));
  });

  document.addEventListener('keydown', (e) => {
    if (state.screen !== 'command') return;
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
      if (active && active.tagName === 'INPUT') {
        e.preventDefault();
        (rows[sel] || rows[0]).click();
      }
    }
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

  // Reset selection when the query changes.
  let lastQ = null;
  registerEnhancer(() => {
    if (state.screen !== 'command') { lastQ = null; return; }
    if (state.cmdQuery !== lastQ) { lastQ = state.cmdQuery; sel = 0; }
  });
})();
