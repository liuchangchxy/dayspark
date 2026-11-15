/* App shell: rail, bottom nav, router, keyboard, lifecycle. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);
  const Registry = window.App;

  let lastRouteKey = null;

  function focusRoute(host) {
    if (host.querySelector('[data-testid="composer-title"]')) return;
    const heading = host.querySelector('.page-title, .detail-title');
    if (!heading) return;
    heading.setAttribute('tabindex', '-1');
    heading.focus({ preventScroll: true });
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
    const caret = focusId && typeof prev.selectionStart === 'number'
      ? { s: prev.selectionStart, e: prev.selectionEnd } : null;
    host.innerHTML = '';
    Registry.escapeHandler = null;
    const node = fn(route.params || {});
    host.appendChild(node);
    const routeKey = route.name + ':' + JSON.stringify(route.params || {});
    const changedRoute = routeKey !== lastRouteKey;
    lastRouteKey = routeKey;
    if (focusId) {
      const again = host.querySelector(`[data-testid="${focusId}"]`);
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
      const target = typeof spec === 'object'
        ? host.querySelector(`[data-testid="${spec.testid}"][data-id="${spec.id}"]`)
        : host.querySelector(`[data-testid="${spec}"], [data-hl="${spec}"]`);
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
    if (n === 'composer') return S.state.composer && S.state.composer.kind === 'event' ? 'calendar' : (S.state.tab || 'action');
    if (n === 'detail') return S.state.tab || 'action';
    if (n === 'action' || n === 'calendar' || n === 'todos') return n;
    return n;
  }

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
    const active = currentSection();
    navItems().forEach((item) => {
      const b = U.el('button', { class: active === item.key ? 'on' : '', 'aria-label': item.label });
      b.dataset.testid = 'tab-' + item.key;
      b.innerHTML = ICON(item.icon, 19) + `<span>${U.esc(item.label)}</span>`;
      b.addEventListener('click', () => go(item.key));
      nav.appendChild(b);
    });
  }

  function guarded(fn) {
    const guard = Registry.leaveGuard;
    if (!guard) { fn(); return; }
    guard().then((ok) => { if (ok) { Registry.leaveGuard = null; fn(); } });
  }

  function go(name, params) {
    UI.closeMenu();
    guarded(() => {
      if (name === 'action' || name === 'calendar' || name === 'todos') {
        S.state.tab = name;
        S.state.route = { name, params: params || {} };
        S.state.selection = null;
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
      if (S.state.menu) { UI.closeMenu(); return; }
      if (Registry.escapeHandler) { e.preventDefault(); Registry.escapeHandler(); return; }
      if (!typing && S.state.route.name !== 'action') { e.preventDefault(); back(); }
      return;
    }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
    // Shortcuts must not mutate the page behind an open sheet or dialog.
    if (UI.hasOpenLayer()) return;
    if (e.key === 'n' || e.key === 'N') { e.preventDefault(); openComposer('todo'); return; }
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
    S.state.calendarAnchor = today;
    S.state.calendarFocusDay = today;
    go(S.state.tab || 'action');
    UI.toast(S.state.lang === 'zh' ? '已回到今天' : 'Back to today', { duration: 1600 });
  }

  function openComposer(kind, opts) {
    S.state.composer = Object.assign({ kind: kind || 'todo', mode: 'create' }, opts || {});
    S.navigate('composer', {});
  }

  function boot() {
    S.seed();
    I18N.setLang(S.state.lang);
    S.applyTheme();
    S.subscribe(() => render());
    window.addEventListener('resize', U.debounce(() => render(), 140));
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.menu')) UI.closeMenu();
    });
    setTimeout(() => {
      U.qs('#boot').hidden = true;
      U.qs('#app').hidden = false;
      render();
      window.__READY__ = true;
    }, 80);
  }

  Registry.render = render;
  Registry.go = go;
  Registry.back = back;
  Registry.jumpToday = jumpToday;
  Registry.openComposer = openComposer;
  Registry.showShortcuts = showShortcuts;

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
