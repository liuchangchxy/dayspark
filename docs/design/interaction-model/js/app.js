/* App shell: rail, bottom nav, router, keyboard, lifecycle. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);
  const Registry = window.App;

  let lastRouteKey = null;
  // Scroll belongs to a destination, not to the window: leaving Todos for Today
  // must not carry the list's offset onto Today, and coming back must restore
  // the list where it was.
  const scrollByRoute = new Map();

  function focusRoute(host) {
    if (host.querySelector('[data-testid="composer-title"]')) return;
    const heading = host.querySelector('.page-title, .detail-title');
    if (!heading) return;
    heading.setAttribute('tabindex', '-1');
    heading.focus({ preventScroll: true });
  }

  // Replacing #view rebuilds every scroll container. Without this, selecting a
  // record near the bottom of a list (or dragging a late calendar block) throws
  // the user back to the top of the page.
  function scrollKey(el) {
    const cls = typeof el.className === 'string' ? el.className : '';
    return el.tagName + '.' + cls + (el.dataset && el.dataset.testid ? '#' + el.dataset.testid : '');
  }
  function scrollSnapshot(root) {
    const map = new Map();
    Array.from(root.querySelectorAll('*')).forEach((el) => {
      if (!(el.scrollTop > 0 || el.scrollLeft > 0)) return;
      const key = scrollKey(el);
      const list = map.get(key) || [];
      list.push([el.scrollTop, el.scrollLeft]);
      map.set(key, list);
    });
    return map;
  }
  function restoreScroll(root, map) {
    if (!map || !map.size) return;
    const seen = new Map();
    Array.from(root.querySelectorAll('*')).forEach((el) => {
      const key = scrollKey(el);
      const list = map.get(key);
      if (!list) return;
      const i = seen.get(key) || 0;
      seen.set(key, i + 1);
      if (list[i]) { el.scrollTop = list[i][0]; el.scrollLeft = list[i][1]; }
    });
  }

  function render() {
    Registry.leaveGuard = null;
    S.applyTheme();
    document.documentElement.lang = S.state.lang === 'zh' ? 'zh-CN' : 'en';
    renderRail();
    renderBottomNav();
    const host = U.qs('#view');
    const route = S.state.route;
    const fn = Registry.getView(route.name) || Registry.getView('action');
    // A re-render replaces the DOM, so keep keyboard focus (and the caret) on the
    // same control. Without this, every emit-driven render blurs the capture and
    // quick-add fields mid-typing.
    const prev = document.activeElement;
    const focusId = prev && prev.dataset ? prev.dataset.testid : null;
    const focusRec = prev && prev.dataset ? prev.dataset.id : null;
    const caret = focusId && typeof prev.selectionStart === 'number'
      ? { s: prev.selectionStart, e: prev.selectionEnd } : null;
    if (lastRouteKey) scrollByRoute.set(lastRouteKey, scrollSnapshot(host));
    host.innerHTML = '';
    Registry.escapeHandler = null;
    const node = fn(route.params || {});
    host.appendChild(node);
    const routeKey = route.name + ':' + JSON.stringify(route.params || {});
    const changedRoute = routeKey !== lastRouteKey;
    restoreScroll(host, scrollByRoute.get(routeKey));
    lastRouteKey = routeKey;
    if (focusId) {
      const recSel = focusRec ? `[data-id="${focusRec}"]` : '';
      const again = host.querySelector(`[data-testid="${focusId}"]${recSel}`);
      if (again && again.focus) {
        again.focus({ preventScroll: true });
        if (caret && typeof again.setSelectionRange === 'function') {
          try { again.setSelectionRange(caret.s, caret.e); } catch (err) { /* not a text field */ }
        }
      }
    } else if (changedRoute) {
      focusRoute(host);
    }
    if (S.state.highlight) {
      // Emits schedule another render a frame later; keep the marker alive until
      // its animation has run, otherwise the second render erases the class.
      const spec = S.state.highlight;
      let target = null;
      if (typeof spec === 'object') {
        // The same record renders under different testids per surface (todo-tile
        // in the lists, action-todo on Today, event-block in the calendar). The
        // spec names every testid the record can appear as, so ids from two
        // tables (a todo and an event can share a number) never collide.
        const ids = spec.testids || [spec.testid];
        for (const id of ids) {
          target = host.querySelector(`[data-testid="${id}"][data-id="${spec.id}"]`);
          if (target) break;
        }
      } else {
        target = host.querySelector(`[data-testid="${spec}"], [data-hl="${spec}"]`);
      }
      if (target) {
        target.classList.add('hl');
        target.scrollIntoView({ block: 'center' });
        if (!S.state.highlightTimer) {
          S.state.highlightTimer = setTimeout(() => {
            S.state.highlight = null;
            S.state.highlightTimer = null;
          }, 1600);
        }
      }
    }
  }

  function navItems() {
    return [
      { key: 'action', icon: 'bolt', label: t('navAction') },
      { key: 'calendar', icon: 'calendar', label: t('navCalendar') },
      { key: 'todos', icon: 'checkSquare', label: t('navTodos') },
    ];
  }

  function currentSection() {
    const n = S.state.route.name;
    if (n === 'search') return 'search';
    if (n === 'chat') return 'chat';
    if (n === 'quickadd') return 'quickadd';
    if (n === 'composer') return S.state.composer && S.state.composer.kind === 'event' ? 'calendar' : (S.state.tab || 'action');
    if (n === 'detail') return S.state.tab || 'action';
    if (n === 'action' || n === 'calendar' || n === 'todos') return n;
    return n;
  }

  // Master-detail is a pane on the Todo destination only, exactly where the
  // app has one. Everywhere else a detail is a page, because there is no list
  // to keep beside it.
  function paneOpenHere() {
    return !U.isNarrow() && U.isSplit() && S.state.tab === 'todos' && !!S.state.paneSelection;
  }

  // Opening a record: answer in place when the pane exists, otherwise navigate.
  // Clicking a row must not silently do nothing on the destinations that have
  // no pane.
  function openRecord(type, id, occurrence, day) {
    const dayMs = day ? U.startOfDay(day).getTime() : null;
    // The pane exists only on the Todo destination itself. From a routed detail
    // (Search, a calendar block, a child link) there is no list beside it, so
    // storing a pane selection there would be a click that does nothing.
    if (!U.isNarrow() && U.isSplit() && S.state.tab === 'todos' && S.state.route.name === 'todos') {
      S.selectPane(type, id, occurrence, dayMs);
      return;
    }
    S.navigate('detail', { type, id, occurrence: occurrence || null, day: dayMs });
  }

  // A detail route stays a route. Turning it into a pane here would hijack
  // arrivals from Search or a deep link, leaving the user on Todo instead of
  // the page they asked for. The pane is entered only by clicking a row.

  function renderRail() {
    const rail = U.qs('#rail');
    rail.innerHTML = '';
    const brand = U.el('div', { class: 'brand' });
    brand.innerHTML = `<div class="brand-mark">灵</div><div><div class="brand-name">${U.esc(t('appName'))}<i></i></div><span class="brand-sub">${U.esc(t('brandSub'))}</span></div>`;
    brand.style.cursor = 'pointer';
    brand.addEventListener('click', () => go('action'));
    rail.appendChild(brand);

    const nav = U.el('div', { class: 'rail-nav' });
    const active = currentSection();
    navItems().forEach((item) => {
      const b = U.el('button', { class: 'rail-item' + (active === item.key ? ' on' : ''), 'aria-current': active === item.key ? 'page' : null });
      b.dataset.testid = 'nav-' + item.key;
      b.innerHTML = ICON(item.icon, 16) + `<span>${U.esc(item.label)}</span>`;
      if (item.key === 'todos') {
        const n = S.pendingTodos().length;
        b.innerHTML += `<span class="count">${n}</span>`;
      }
      if (item.key === 'action') {
        const p = S.actionProjection(S.state.actionDate);
        const n = p.overdueTodos.length + p.missedTaskInstances.length;
        if (n > 0) b.innerHTML += `<span class="count" style="color:var(--red)">${n}</span>`;
      }
      b.addEventListener('click', () => go(item.key));
      nav.appendChild(b);
    });
    rail.appendChild(nav);
    rail.appendChild(U.el('div', { class: 'rail-label', text: t('navTools') }));

    const tools = U.el('div', { class: 'rail-nav' });
    [
      { key: 'quickadd', icon: 'bolt', label: t('quickAdd') },
      { key: 'search', icon: 'search', label: t('navSearch') },
      { key: 'chat', icon: 'sparkles', label: t('navAi') },
      { key: 'tags', icon: 'tag', label: t('navTags') },
      { key: 'calendars', icon: 'layers', label: t('pageCalendars') },
      { key: 'trash', icon: 'trash', label: t('navTrash') },
      { key: 'settings', icon: 'settings', label: t('navSettings') },
    ].forEach((item) => {
      const b = U.el('button', { class: 'rail-item' + (active === item.key ? ' on' : '') });
      b.dataset.testid = 'nav-' + item.key;
      b.innerHTML = ICON(item.icon, 16) + `<span>${U.esc(item.label)}</span>`;
      b.addEventListener('click', () => go(item.key));
      tools.appendChild(b);
    });
    rail.appendChild(tools);

    const foot = U.el('div', { class: 'rail-foot' });
    const status = U.el('button', { class: 'sync-status' });
    status.dataset.testid = 'rail-sync';
    const phase = S.state.offline ? 'off' : (S.state.account.phase === 'error' ? 'err' : '');
    status.innerHTML = `<span class="sync-dot ${phase}"></span><span>${U.esc(S.state.offline ? (S.state.lang === 'zh' ? '离线' : 'Offline') : (S.state.account.signedIn ? t('syncPhaseIdle') : (S.state.lang === 'zh' ? '本地模式' : 'Local only')))}</span>`;
    status.addEventListener('click', () => go('settings', { section: 'account' }));
    foot.appendChild(status);
    rail.appendChild(foot);
  }

  function renderBottomNav() {
    const nav = U.qs('#bottomnav');
    nav.innerHTML = '';
    const current = currentSection();
    const active = (current === 'action' || current === 'calendar' || current === 'todos') ? current : 'more';
    navItems().forEach((item) => {
      const b = U.el('button', { class: active === item.key ? 'on' : '', 'aria-label': item.label });
      b.dataset.testid = 'tab-' + item.key;
      b.innerHTML = ICON(item.icon, 19) + `<span>${U.esc(item.label)}</span>`;
      b.addEventListener('click', () => go(item.key));
      nav.appendChild(b);
    });
    // The rail carries every tool on desktop. On a phone the bottom bar is the
    // only shell the user has, so the tools have to live here too or Settings,
    // Search, AI and Calendars management become unreachable by touch.
    const more = U.el('button', { class: active === 'more' ? 'on' : '', 'aria-label': t('navMore') });
    more.dataset.testid = 'tab-more';
    more.innerHTML = ICON('ellipsis', 19) + `<span>${U.esc(t('navMore'))}</span>`;
    more.addEventListener('click', (ev) => {
      ev.stopPropagation();
      UI.menu(more, [
        { icon: 'bolt', text: t('quickAdd'), action: () => go('quickadd') },
        { icon: 'search', text: t('navSearch'), action: () => go('search') },
        { icon: 'sparkles', text: t('navAi'), action: () => go('chat') },
        { icon: 'tag', text: t('navTags'), action: () => go('tags') },
        { icon: 'layers', text: t('pageCalendars'), action: () => go('calendars') },
        { icon: 'trash', text: t('navTrash'), action: () => go('trash') },
        { sep: true },
        { icon: 'settings', text: t('navSettings'), action: () => go('settings') },
      ]);
    });
    nav.appendChild(more);
  }

  function guarded(fn) {
    const guard = Registry.leaveGuard;
    if (!guard) { fn(); return; }
    guard().then((ok) => { if (ok) { Registry.leaveGuard = null; fn(); } });
  }

  function go(name, params) {
    UI.closeMenu();
    guarded(() => {
      if (name !== 'todos' && name !== 'composer') S.state.paneSelection = null;
      if (name === 'action' || name === 'calendar' || name === 'todos') {
        S.state.tab = name;
        S.state.route = { name, params: params || {} };
        S.state.selection = null;
        // Changing destination closes the detail pane. What it holds belongs to
        // the list that opened it; leaving it up would show a record the user
        // is no longer looking at in the list.
        if (name !== 'todos') S.state.paneSelection = null;
        S.emit('navigate');
        return;
      }
      S.navigate(name, params || {});
    });
  }
  function back() {
    UI.closeMenu();
    S.back();
  }

  document.addEventListener('keydown', (e) => {
    const el = document.activeElement;
    const typing = el && (/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || el.isContentEditable);
    if (e.key === 'Escape') {
      if (UI.closeTop()) { e.preventDefault(); return; }
      // Menus are not modal layers, but Escape must still close one before it
      // means "leave this page".
      if (document.querySelector('.menu')) { UI.closeMenu(); e.preventDefault(); return; }
      if (S.state.menu) { UI.closeMenu(); return; }
      if (Registry.escapeHandler) { e.preventDefault(); Registry.escapeHandler(); return; }
      if (S.state.paneSelection && paneOpenHere()) {
        e.preventDefault();
        const id = S.state.paneSelection.id;
        S.clearPane();
        const row = document.querySelector(`[data-testid="todo-row"][data-id="${id}"]`);
        if (row) row.focus();
        return;
      }
      // Reaching here means nothing above claimed the key: no overlay, no menu,
      // and no page with an unsaved draft (the composer registers its own
      // handler). So Escape means "leave", even with the caret in a field —
      // a search box that swallows Escape strands the user on that page.
      if (S.state.route.name !== 'action') { e.preventDefault(); back(); }
      return;
    }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
    // Shortcuts must not mutate the page behind an open sheet or dialog.
    if (UI.hasOpenLayer()) return;
    if (e.key === 'n' || e.key === 'N') { e.preventDefault(); openComposer('todo'); return; }
    if (e.key === 'q' || e.key === 'Q') { e.preventDefault(); go('quickadd'); return; }
    if (e.key === '/') { e.preventDefault(); go('search'); return; }
    if (e.key === 't' || e.key === 'T') { e.preventDefault(); jumpToday(); return; }
    if (e.key === '?') { e.preventDefault(); showShortcuts(); return; }
  });

  function showShortcuts() {
    UI.modal({
      title: S.state.lang === 'zh' ? '键盘快捷键' : 'Keyboard shortcuts',
      body(body) {
        const rows = [
          ['N', S.state.lang === 'zh' ? '新建待办' : 'New to-do'],
          ['/', S.state.lang === 'zh' ? '搜索' : 'Search'],
          ['T', S.state.lang === 'zh' ? '回到今天' : 'Back to today'],
          ['Esc', S.state.lang === 'zh' ? '关闭 / 返回' : 'Close / back'],
          ['Enter', S.state.lang === 'zh' ? '在输入框中保存' : 'Save from a field'],
        ];
        const box = U.el('div', { class: 'applist' });
        rows.forEach(([k, v]) => {
          const r = U.el('div', { class: 'kv' });
          r.innerHTML = `<span class="k">${U.esc(v)}</span><span class="v mono">${U.esc(k)}</span>`;
          box.appendChild(r);
        });
        body.appendChild(box);
      },
    });
  }

  function jumpToday() {
    const today = U.startOfDay(U.now());
    S.state.actionDate = today;
    S.state.todosView = { kind: 'day', day: today };
    // "Back to today" moves the one browsed date, so the calendar and the Todo
    // list are back on the same day rather than each holding a different one.
    S.state.calendarAnchor = today;
    S.state.calendarFocusDay = today;
    S.state.browseDate = today;
    go(S.state.tab || 'action');
    UI.toast(S.state.lang === 'zh' ? '已回到今天' : 'Back to today', { duration: 1600 });
  }

  function openComposer(kind, opts) {
    // A fresh editor never inherits the previous draft, even if the route
    // parameters happen to be identical.
    S.state.composerDraft = null;
    S.state.composer = Object.assign({ kind: kind || 'todo', mode: 'create' }, opts || {});
    S.navigate('composer', {});
  }

  function boot() {
    S.seed();
    S.loadPrefs();
    I18N.setLang(S.state.lang);
    S.applyTheme();
    S.subscribe(() => render());
    window.addEventListener('resize', U.debounce(() => render(), 140));
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.menu')) UI.closeMenu();
    });
    // "Opens on" is a launch preference, so it is read here and nowhere else:
    // changing it must not yank the user off the page they are on.
    const start = S.state.defaultTab;
    if (start && start !== 'action') {
      S.state.route = { name: start, params: {} };
      if (start === 'action' || start === 'calendar' || start === 'todos') S.state.tab = start;
    }
    // The app has no real URL history (every route is in-memory), so the
    // browser Back button would otherwise unload the page and silently discard
    // a dirty draft. Take one entry of history for ourselves and route Back
    // through the same guard every in-app exit uses.
    if (window.history && history.pushState) {
      try { history.pushState({ ds: true }, ''); } catch (_) { /* file:// may refuse */ }
      window.addEventListener('popstate', () => {
        const guard = Registry.leaveGuard;
        if (guard) {
          guard().then((ok) => {
            if (ok) { Registry.leaveGuard = null; back(); }
            try { history.pushState({ ds: true }, ''); } catch (_) {}
          });
        } else {
          // Back closes the detail pane before it leaves the page: the pane is
          // the most recent thing the user opened.
          if (S.state.paneSelection && paneOpenHere()) { S.state.paneSelection = null; App.render(); }
          else back();
          try { history.pushState({ ds: true }, ''); } catch (_) {}
        }
      });
    }
    setTimeout(() => {
      U.qs('#boot').hidden = true;
      U.qs('#app').hidden = false;
      render();
      window.__READY__ = true;
    }, 80);
    rollTodayAtMidnight();
  }

  // Today is the clock, never a stored day: even an idle tab rolls its own
  // date when the clock crosses midnight.
  function rollTodayAtMidnight() {
    const now = U.now();
    const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
    setTimeout(() => {
      S.state.actionDate = U.startOfDay(U.now());
      App.render();
      rollTodayAtMidnight();
    }, Math.max(1000, next - now));
  }

  Registry.render = render;
  Registry.go = go;
  Registry.back = back;
  Registry.jumpToday = jumpToday;
  Registry.openComposer = openComposer;
  Registry.showShortcuts = showShortcuts;
  Registry.openRecord = openRecord;
  Registry.paneOpenHere = paneOpenHere;

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
