/* DaySpark prototype controller. Runs after the frozen master script, reuses its
   state, screen renderers and component CSS, and turns the spec board into a
   continuous product. */
(function () {
  'use strict';

  const KEY = 'dayspark.prototype.v1';
  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

  const Proto = (window.Proto = {
    actions: Object.create(null),
    enhancers: [],
    data: {
      tags: [
        { name: '周报', color: '#4f7bbf' },
        { name: '林总', color: '#c4794a' },
        { name: '健康', color: '#6a9464' },
        { name: '家事', color: '#a98b4f' },
        { name: '学习', color: '#6c6fa8' },
        { name: '提案', color: '#8a8a82' },
      ],
      account: {
        signedIn: true,
        email: 'chang@local',
        server: 'https://sync.dayspark.local',
        pending: 0,
        lastSync: '今天 14:58',
        devices: [
          { name: 'MacBook Pro', meta: '本机 · 刚刚活跃', current: true },
          { name: 'iPhone 15', meta: '今天 09:12 · 已同步' },
          { name: 'iPad Air', meta: '11 月 18 日 · 已同步' },
        ],
      },
      notify: { permission: 'granted', exact: true },
      sync: { status: 'ok', offline: false, conflicts: 0, rejected: 0 },
      ai: { model: 'gpt-4o-mini', key: 'sk-••••4f2a' },
      importFile: 'dayplan.ics',
      backupFile: '2026-11-20.dayspark.zip',
    },
    registeredAt: Date.now(),
  });

  const TRANSIENT = new Set([
    'screen', 'variant', 'device', 'drawer', 'drawerEdit', 'draft', 'draftKey',
    'toast', 'cmdReturn', 'cmdQuery', 'planReturn', 'planReturnDrawer',
    'planReturnEdit', 'planReturnVariant', 'confirmDelete', 'deleteRef',
    'trashId', 'trashName', 'aiBusy', 'fbCopied', 'capture', 'captureReturn',
    'suggestionRemoved', 'aiConfigOpen', 'aiKeyVisible', 'overlayFocus',
    'widgetKind', 'widgetEmpty', 'pickerDate', 'pickerMonth', 'timeValue',
    'selectedDate', 'settings', 'tagId', 'calendarId', 'planTodoId',
  ]);

  function snapshot() {
    const stateOut = {};
    for (const k of Object.keys(state)) {
      if (!TRANSIENT.has(k) && k !== 'done') stateOut[k] = state[k];
    }
    stateOut.done = state.done instanceof Set ? Array.from(state.done) : [];
    // The AI key is session-only: snapshots (localStorage, backups, conflict
    // views) must never carry plaintext, even if a key was typed.
    let dataOut = Proto.data;
    try {
      dataOut = JSON.parse(JSON.stringify(Proto.data));
      if (dataOut && dataOut.ai && typeof dataOut.ai.key === 'string' && dataOut.ai.key && dataOut.ai.key.indexOf('•') < 0) {
        dataOut.ai.key = 'sk-••••' + dataOut.ai.key.slice(-4);
      }
    } catch (_) { dataOut = Proto.data; }
    return {
      v: 1,
      todos: TODOS,
      events: EVENTS,
      cal: CAL,
      state: stateOut,
      data: dataOut,
      screen: state.screen,
    };
  }

  let saveTimer = 0;
  Proto.save = function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      try { localStorage.setItem(KEY, JSON.stringify(snapshot())); } catch (_) {}
    }, 40);
  };

  function restore() {
    let raw = null;
    try { raw = localStorage.getItem(KEY); } catch (_) {}
    if (!raw) return false;
    try {
      const data = JSON.parse(raw);
      if (!data || data.v !== 1) return false;
      if (Array.isArray(data.todos)) {
        TODOS.splice(0, TODOS.length, ...data.todos);
      }
      if (Array.isArray(data.events)) {
        EVENTS.splice(0, EVENTS.length, ...data.events);
      }
      if (data.cal && typeof data.cal === 'object') {
        for (const k of Object.keys(CAL)) delete CAL[k];
        Object.assign(CAL, data.cal);
      }
      if (data.state) {
        Object.assign(state, data.state);
        state.done = new Set(Array.isArray(data.state.done) ? data.state.done : []);
      }
      if (data.data) {
        Object.assign(Proto.data, data.data);
        if (Array.isArray(data.data.tags)) Proto.data.tags = data.data.tags;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Proto.reset = function reset() {
    try { localStorage.removeItem(KEY); } catch (_) {}
    location.hash = '#/today';
    location.reload();
  };

  Proto.toast = function (msg) {
    if (typeof setToast === 'function') setToast(msg);
  };

  Proto.modal = function modal(opts) {
    const scrim = document.createElement('div');
    scrim.className = 'proto-modal-scrim' + (opts.sheet ? ' is-sheet' : '');
    scrim.innerHTML = `
      <div class="proto-modal${opts.wide ? ' is-wide' : ''}${opts.sheet ? ' is-sheet' : ''}" role="dialog" aria-modal="true" aria-label="${opts.title || ''}">
        <div class="proto-modal-head"><span>${opts.title || ''}</span></div>
        <div class="proto-modal-body"></div>
        <div class="proto-modal-foot"></div>
      </div>`;
    const body = $('.proto-modal-body', scrim);
    if (typeof opts.body === 'string') body.innerHTML = opts.body;
    else if (opts.body) body.appendChild(opts.body);
    const foot = $('.proto-modal-foot', scrim);
    (opts.actions || []).forEach((a) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'proto-btn' + (a.primary ? ' primary' : '') + (a.danger ? ' danger' : '');
      b.textContent = a.label;
      b.addEventListener('click', () => {
        const keep = a.onClick ? a.onClick(scrim) : false;
        if (!keep) scrim.remove();
      });
      foot.appendChild(b);
    });
    const close = () => scrim.remove();
    scrim.addEventListener('click', (e) => { if (e.target === scrim && !opts.sticky) close(); });
    scrim._close = close;
    document.body.appendChild(scrim);
    const first = $('input, textarea, select, button.primary', scrim);
    if (first) setTimeout(() => first.focus(), 20);
    return scrim;
  };

  Proto.prompt = function prompt(opts) {
    const id = 'p-' + Math.random().toString(36).slice(2);
    const value = (opts.value || '').replace(/"/g, '&quot;');
    const scrim = Proto.modal({
      title: opts.title,
      body: `<div class="proto-field"><label for="${id}">${opts.label || ''}</label><input id="${id}" class="proto-input" value="${value}" placeholder="${(opts.placeholder || '').replace(/"/g, '&quot;')}"></div>${opts.note ? `<div class="proto-note">${opts.note}</div>` : ''}`,
      actions: [
        { label: '取消' },
        { label: opts.confirm || '确定', primary: true, onClick: (root) => {
          opts.onConfirm($('#' + id, root).value.trim());
        } },
      ],
    });
    return scrim;
  };

  /* ---------------- routing ---------------- */
  const screenRoutes = {
    'today': 'today',
    'todo-inbox': 'todos/inbox',
    'todo-all': 'todos/all',
    'todo-date': 'todos/date',
    'cal-week': 'calendar/week',
    'cal-month': 'calendar/month',
    'cal-day': 'calendar/day',
    'new-todo': 'new/todo',
    'new-event': 'new/event',
    'command': 'search',
    'ai-chat': 'ai',
    'trash-page': 'trash',
    'tags-page': 'tags',
    'feedback': 'feedback',
    'capture': 'capture',
    'settings-home': 'settings/home',
  };

  function routeForState() {
    if (state.protoError) return 'error/' + (state.protoError.kind || 'missing');
    if (state.drawer) {
      return (state.drawer.type === 'event' ? 'event/' : 'todo/') + state.drawer.id;
    }
    if (screenRoutes[state.screen]) return screenRoutes[state.screen];
    if (state.screen.startsWith('settings-')) {
      return 'settings/' + state.screen.replace('settings-', '');
    }
    return 'today';
  }

  Proto.route = routeForState;

  function applyRoute(hash) {
    const raw = String(hash || '').replace(/^#\/?/, '');
    const bits = raw.split('/').filter(Boolean);
    if (!bits.length || bits[0] === 'today') { baseGo('today'); return; }
    if (bits[0] === 'todo' && bits[1]) {
      baseGo('today');
      const t = todoById(bits[1]);
      if (t) { state.drawer = { type: 'todo', id: t.id }; render(); }
      else showError((state.deletedTodos || []).includes(bits[1]) ? 'trashed' : 'missing', raw);
      return;
    }
    if (bits[0] === 'event' && bits[1]) {
      baseGo('cal-day');
      const e = eventById(bits[1]);
      if (e) { state.drawer = { type: 'event', id: e.id }; render(); }
      else showError((state.deletedEvents || []).includes(bits[1]) ? 'trashed' : 'missing', raw);
      return;
    }
    if (bits[0] === 'todos') {
      baseGo(bits[1] === 'all' ? 'todo-all' : bits[1] === 'date' ? 'todo-date' : 'todo-inbox');
      return;
    }
    if (bits[0] === 'calendar') {
      baseGo(bits[1] === 'month' ? 'cal-month' : bits[1] === 'day' ? 'cal-day' : 'cal-week');
      return;
    }
    if (bits[0] === 'settings') {
      baseGo('settings-' + (bits[1] || 'home'));
      return;
    }
    if (bits[0] === 'new') { baseGo(bits[1] === 'event' ? 'new-event' : 'new-todo'); return; }
    if (bits[0] === 'search') { baseGo('command'); return; }
    if (bits[0] === 'ai') { baseGo('ai-chat'); return; }
    if (bits[0] === 'trash') { baseGo('trash-page'); return; }
    if (bits[0] === 'tags') { baseGo('tags-page'); return; }
    if (bits[0] === 'feedback') { baseGo('feedback'); return; }
    if (bits[0] === 'widgets') { baseGo('widgets'); return; }
    if (bits[0] === 'quick-add') { baseGo('today'); Proto.quickAdd && Proto.quickAdd(); return; }
    if (bits[0] === 'oauth') { baseGo('server-oauth'); return; }
    if (bits[0] === 'error') { showError(bits[1] || 'missing', raw); return; }
    showError('missing', raw);
  }

  let suppressHash = false;
  function syncHash(push) {
    const next = '#/' + routeForState();
    if (location.hash === next) return;
    suppressHash = true;
    if (push) history.pushState({ proto: true }, '', next);
    else history.replaceState({ proto: true }, '', next);
    setTimeout(() => { suppressHash = false; }, 0);
  }

  const baseGo = go;
  const baseRender = render;

  // Every screen render also records the URL and the local snapshot.
  render = function () {
    baseRender();
    if (state.protoError) paintError();
    syncHash(false);
    Proto.save();
    requestAnimationFrame(enhance);
  };

  function showError(kind, detail) {
    state.protoError = { kind: kind || 'missing', detail: detail || '' };
    if (detail && window.console) console.warn('[deep link]', detail);
    render();
  }
  Proto.showError = showError;

  function paintError() {
    const frame = document.getElementById('frame');
    if (!frame) return;
    const e = state.protoError || {};
    const trashed = e.kind === 'trashed';
    const startup = e.kind === 'startup';
    const title = trashed ? '这一项已在回收站' : startup ? 'DaySpark 没有启动' : '找不到这个页面';
    const sub = trashed
      ? '它被删除后还在回收站里。恢复后会回到原来的日历，不会新建一条重复项。'
      : startup
        ? '本地数据没有丢。可以重试；如果一直失败，复制诊断信息再反馈。'
        : '链接可能过期，或这个对象从来没有同步到本机。';
    const body = `<div class="page"><div class="page-state-wrap"><div class="page-state">
      <span class="page-state-ico">${typeof ico === 'function' ? ico('alert', 24) : '!'}</span>
      <b>${title}</b><p>${sub}</p>
      <div style="display:flex;gap:8px;justify-content:center;flex-wrap:wrap">
        ${trashed ? `<button type="button" class="page-state-btn" data-proto-action="error-trash">去回收站</button>` : ''}
        ${startup ? `<button type="button" class="page-state-btn" data-proto-action="error-retry">重试</button>` : ''}
        <button type="button" class="page-state-btn" data-proto-action="error-home">返回首页</button>
      </div>
      ${''/* The raw route is for diagnosis, not for the reader. */}
    </div></div></div>`;
    if (state.device === 'mobile') {
      frame.innerHTML = `<div class="m-app"><div class="m-status"><span>15:00</span><span class="m-status-icons"><i></i><i></i><i></i></span></div><header class="m-top"><div class="m-title">DaySpark</div></header><div class="m-scroll">${body}</div></div>`;
    } else {
      frame.innerHTML = pTop('') + `<div class="p-main">${body}</div>`;
    }
  }

  go = function (screen) {
    state.protoError = null;
    if ((screen === 'new-todo' || screen === 'new-event') && state.screen !== screen) {
      Proto.data.newDraft = null;
    }
    baseGo(screen);
    syncHash(true);
  };

  window.addEventListener('popstate', () => {
    if (suppressHash) return;
    applyRoute(location.hash);
  });
  window.addEventListener('hashchange', () => {
    if (suppressHash) return;
    applyRoute(location.hash);
  });

  // Any product action that changes screen/drawer updates the URL once the
  // master's own handler has finished.
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-action]');
    if (!el) return;
    const act = el.dataset.action;
    if (act === 'noop') return;
    setTimeout(() => syncHash(true), 0);
  });

  /* ---------------- action capture ---------------- */
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-proto-action]');
    if (el) {
      const fn = Proto.actions[el.dataset.protoAction];
      if (!fn) return;
      e.preventDefault();
      e.stopPropagation();
      fn(el, e);
      return;
    }
    const noop = e.target.closest && e.target.closest('[data-action="noop"]');
    if (noop) {
      e.preventDefault();
      e.stopPropagation();
      Proto.actions['info-open'](noop, e);
    }
  }, true);

  Proto.registerAction = (name, fn) => { Proto.actions[name] = fn; };
  Proto.registerEnhancer = (fn) => Proto.enhancers.push(fn);
  // Debug hook: which enhancer throws (keeps enhancer errors local, not global).
  Proto.lastEnhancerError = null;

  function protoAction(el, name) {
    if (el && !el.dataset.protoAction) el.dataset.protoAction = name;
    return el;
  }
  Proto.protoAction = protoAction;

  /* ---------------- shared enhance ---------------- */
  function enhance() {
    const root = document.getElementById('frame');
    if (!root) return;
    $$('[data-action="noop"]', root).forEach((el) => {
      if (el.dataset.protoAction) return;
      wireNoop(el, root);
    });
    Proto.enhancers.forEach((fn) => {
      try { fn(root); } catch (err) { Proto.lastEnhancerError = String(err && err.stack || err); console.error('[prototype enhancer]', err); }
    });
    // "My" opens the settings index, not the General subsection.
    $$('[data-action="go-settings"]', root).forEach((el) => {
      if (!el.dataset.protoAction) el.dataset.protoAction = 'settings-home-proto';
    });
    const avatar = $('.p-avatar', root);
    if (avatar && !avatar.dataset.protoAction) avatar.dataset.protoAction = 'settings-home-proto';

    // Nothing falls through to the master's "design state" placeholder.
    // The v2 layer classifies every remaining control as a real read-only
    // fact, an explicit disabled state, or a removed entry.
    $$('[data-action="noop"]:not([data-proto-action])', root).forEach((el) => {
      const row = el.closest('.set-row, .m-settings-row');
      if (row && row.dataset.protoAction && row.dataset.protoAction !== 'info-detail') {
        // The value is part of the row control; clicking it already runs the row action.
        el.removeAttribute('data-action');
        return;
      }
      if (Proto.fallback) Proto.fallback(el, root);
      else protoAction(el, 'info-detail');
    });
    if (state.device === 'mobile') document.body.classList.add('proto-phone-preview');
    else document.body.classList.remove('proto-phone-preview');
    updateToolbar();
  }

  function wireNoop(el, root) {
    const text = (el.textContent || '').trim();
    const page = el.closest('.new-page');
    // The phone shell is not .settings-page, but the same settings semantics
    // apply; without this every import/backup button on mobile fell through.
    const settings = el.closest('.settings-page, .page.settings-page') || (state.screen.startsWith('settings-') ? el.closest('.m-app') : null);
    const section = state.screen.startsWith('settings-') ? state.screen.replace('settings-', '') : '';

    if (state.screen === 'new-todo' || state.screen === 'new-event') {
      if (el.closest('.m-actions')) return protoAction(el, 'new-save');
      if (el.closest('.m-back')) return protoAction(el, 'new-cancel');
      if (el.classList.contains('new-type-btn')) {
        return protoAction(el, text.includes('日程') ? 'new-type-event' : 'new-type-todo');
      }
    }

    if (page) {
      if (el.closest('.ph-right')) {
        if (text.includes('取消')) return protoAction(el, 'new-cancel');
        if (text.includes('记下') || text.includes('创建') || text.includes('保存') || text.includes('重试')) {
          return protoAction(el, 'new-save');
        }
      }
      if (el.closest('.m-actions')) return protoAction(el, 'new-save');
      if (el.classList.contains('new-type-btn')) {
        return protoAction(el, text.includes('日程') ? 'new-type-event' : 'new-type-todo');
      }
      if (el.closest('.confirm-modal')) {
        return protoAction(el, text.includes('丢弃') ? 'new-discard' : 'new-stay');
      }
    }

    if (settings && section === 'account') {
      if (text === '登录' || text.includes('登录') || text === '重新登录') return protoAction(el, 'account-login');
      if (text === '注册') return protoAction(el, 'account-register');
      if (text.includes('退出')) return protoAction(el, 'account-logout');
      if (text === '同步' || text.includes('立即同步')) return protoAction(el, 'sync-now');
      if (text.includes('重试')) return protoAction(el, 'account-retry');
      if (text === '取消') return protoAction(el, 'account-cancel');
    }
    if (settings && (section === 'sync' || section.startsWith('sync-'))) {
      if (text.includes('重试')) return protoAction(el, 'sync-now');
      if (text.includes('退出')) return protoAction(el, 'account-logout');
      if (text.includes('登录')) return protoAction(el, 'account-login');
      if (text.includes('应用选择')) return protoAction(el, 'sync-apply');
    }
    if (settings && section.startsWith('notify')) {
      if (text === '发送' || text.includes('发送测试')) return protoAction(el, 'notify-test');
      if (text.includes('打开设置')) return protoAction(el, 'notify-open-settings');
      if (text.includes('已允许') || text.includes('未生效') || text.includes('可用')) {
        return protoAction(el, 'notify-toggle');
      }
    }
    if (settings && section === 'io') {
      if (text.includes('选择文件')) return protoAction(el, 'import-pick');
      if (text.includes('选择日历')) return protoAction(el, 'import-calendar');
      if (text.includes('导出全部')) return protoAction(el, 'export-ics');
      if (text.includes('导出备份')) return protoAction(el, 'backup-export');
      if (text.includes('合并备份')) return protoAction(el, 'backup-merge');
    }
    if (settings && section === 'import') {
      if (text.includes('选择文件')) return protoAction(el, 'import-pick');
      if (text.includes('选择日历')) return protoAction(el, 'import-calendar');
      if (text.includes('下一步') || text.includes('开始导入')) return protoAction(el, 'import-next');
      if (text === '取消') return protoAction(el, 'import-cancel');
      if (text.includes('跳过') || text.includes('重试')) return protoAction(el, 'import-skip');
      if (text.includes('报告')) return protoAction(el, 'import-report');
    }
    if (settings && section === 'backup') {
      if (text.includes('选择备份文件') || text.includes('合并备份')) return protoAction(el, 'backup-merge');
      if (text.includes('导出完整备份')) return protoAction(el, 'backup-export');
      if (text.includes('重试') || text.includes('重新选择')) return protoAction(el, 'backup-export');
    }
    if (settings && (section === 'tags' || section === 'tag-new' || section === 'tag-edit')) {
      if (text.includes('新建标签')) return protoAction(el, 'tag-new');
      if (text.includes('创建标签') || text === '保存' || text.includes('重试创建')) return protoAction(el, 'tag-save');
      if (text.includes('删除标签')) return protoAction(el, 'tag-delete');
    }
    if (settings && (section === 'calendars' || section === 'calendar-new' || section === 'calendar-edit')) {
      if (text.includes('创建日历')) return protoAction(el, 'cal-save');
      if (text === '保存') return protoAction(el, 'cal-save');
    }
    if (settings && section === 'about') {
      if (text.includes('许可') || text === '查看') return protoAction(el, 'about-license');
      if (text.includes('版本')) return protoAction(el, 'about-version');
    }
    if (settings && section === 'general') {
      if (text.includes('启动时')) return protoAction(el, 'startup-pick');
    }
    if (settings && section === 'account' && text.includes('已连接设备')) {
      return protoAction(el, 'devices-open');
    }
    if (settings && section === 'data') {
      if (text.includes('导出')) return protoAction(el, 'export-ics');
    }

    if (el.closest('.d-sec-head') && text === '添加') {
      const isEvent = !!el.closest('.drawer') && ($('.drawer-kind', el.closest('.drawer')) || {}).textContent?.includes('日程');
      if (!isEvent) return protoAction(el, 'detail-add-tag');
    }
    if (el.closest('.d-sec-head') && text === '上传') return protoAction(el, 'detail-attach');
    if (el.closest('.dropzone') || text.includes('选择文件')) return protoAction(el, 'import-pick');

    if (text.includes('重试') || text.includes('重试读取')) return protoAction(el, 'generic-retry');
    if (text.includes('返回首页')) return protoAction(el, 'generic-home');
  }

  /* ---------------- generic handlers ---------------- */
  Proto.registerAction('generic-retry', () => {
    const section = state.screen.startsWith('settings-') ? state.screen.replace('settings-', '') : '';
    if (section) { state.variant = 'normal'; render(); Proto.toast('已重新读取'); }
    else if (state.screen === 'command') { state.variant = 'result'; render(); }
    else { state.variant = 'normal'; render(); }
  });
  Proto.registerAction('generic-home', () => go('today'));
  Proto.registerAction('settings-home-proto', () => { baseGo('settings-home'); syncHash(true); });
  Proto.registerAction('info-open', (el) => {
    const row = el.closest('.set-row, .m-settings-row');
    const labelEl = row ? $('.set-label, span', row) : null;
    const label = (labelEl ? labelEl.textContent : el.textContent || '').trim().slice(0, 40);
    const value = (el.dataset.infoValue || (row ? (row.textContent || '') : (el.textContent || ''))).replace(/\s+/g, ' ').trim();
    Proto.modal({
      title: label || '这一项',
      body: `<div class="proto-list"><div class="proto-list-row"><span class="grow">${value || '—'}<small>只读事实</small></span></div></div><div class="proto-note">这是当前保存的值；需要修改时使用同一页面里的编辑入口。</div>`,
      actions: [{ label: '关闭', primary: true }],
    });
  });
  Proto.registerAction('error-home', () => go('today'));
  Proto.registerAction('error-trash', () => go('settings-trash'));
  Proto.registerAction('error-retry', () => { state.protoError = null; baseGo('today'); });

  Proto.registerAction('about-license', () => {
    state.variant = state.variant === 'license' ? 'normal' : 'license';
    render();
  });
  Proto.registerAction('about-version', () => {
    Proto.modal({
      title: 'DaySpark 0.35.0',
      body: `<div class="proto-note">本地优先的日历与待办。当前原型的演示日期是 2026 年 11 月 20 日；所有写入只保存在这台设备的浏览器里。</div>`,
      actions: [{ label: '知道了', primary: true }],
    });
  });

  /* ---------------- toolbar ---------------- */
  let toolbar;
  function buildToolbar() {
    toolbar = document.createElement('div');
    toolbar.className = 'proto-bar';
    toolbar.innerHTML = `
      <button type="button" class="proto-pill" data-proto-tool="toggle" aria-expanded="false" aria-label="打开预览选项">预览 · 桌面</button>
      <div class="proto-menu proto-bar-menu" hidden>
        <button type="button" data-proto-tool="desktop">桌面</button>
        <button type="button" data-proto-tool="mobile">手机</button>
        <span class="proto-sep"></span>
        <button type="button" data-proto-tool="widgets">小组件</button>
        <span class="proto-sep"></span>
        <button type="button" data-proto-tool="demo">演示</button>
        <button type="button" data-proto-tool="shortcuts">快捷键</button>
        <span class="proto-sep"></span>
        <button type="button" data-proto-tool="reset">重置数据</button>
        <span class="proto-status">演示时间 11/20</span>
      </div>`;
    document.body.appendChild(toolbar);
    toolbar.addEventListener('click', (e) => {
      const b = e.target.closest('[data-proto-tool]');
      if (!b) return;
      const tool = b.dataset.protoTool;
      const menu = $('.proto-menu', toolbar);
      const closeMenu = () => {
        if (menu) menu.setAttribute('hidden', '');
        toolbar.classList.remove('is-open');
        const pill = $('.proto-pill', toolbar);
        if (pill) pill.setAttribute('aria-expanded', 'false');
      };
      if (tool === 'toggle') {
        const isOpen = menu && !menu.hasAttribute('hidden');
        if (isOpen) closeMenu();
        else {
          menu.removeAttribute('hidden');
          toolbar.classList.add('is-open');
          b.setAttribute('aria-expanded', 'true');
        }
        return;
      }
      if (tool === 'reset') {
        Proto.modal({
          title: '重置演示数据？',
          body: '<div class="proto-note">会清空你在原型里创建、修改和删除的全部内容，恢复到初始演示数据。</div>',
          actions: [
            { label: '取消' },
            { label: '重置', primary: true, danger: true, onClick: () => Proto.reset() },
          ],
        });
        return;
      }
      if (tool === 'widgets') {
        closeMenu();
        baseGo('widgets');
        syncHash(true);
        return;
      }
      if (tool === 'demo') {
        closeMenu();
        if (Proto.openDemo) Proto.openDemo();
        return;
      }
      if (tool === 'shortcuts') {
        closeMenu();
        if (Proto.openShortcuts) Proto.openShortcuts();
        return;
      }
      if (tool === 'desktop' || tool === 'mobile') {
        closeMenu();
        Proto.forcedDevice = tool;
        state.device = tool;
        baseRender();
        syncHash(false);
        enhance();
      }
    });
  }

  function updateToolbar() {
    if (!toolbar) return;
    const pill = $('.proto-pill', toolbar);
    if (pill) pill.textContent = '预览 · ' + (state.device === 'mobile' ? '手机' : '桌面');
    $$('[data-proto-tool]', toolbar).forEach((b) => {
      if (b.dataset.protoTool === 'reset') return;
      b.classList.toggle('is-on', b.dataset.protoTool === state.device);
    });
  }

  /* ---------------- boot ---------------- */
  document.body.classList.add('proto-running');
  const had = restore();
  state.device = window.innerWidth <= 720 ? 'mobile' : 'desktop';
  Proto.forcedDevice = null;
  buildToolbar();
  const initialHash = location.hash || ('#/' + (Proto.data.startup || 'today'));
  suppressHash = true;
  applyRoute(initialHash);
  suppressHash = false;
  enhance();
  if (!had) Proto.save();

  window.addEventListener('resize', () => {
    if (Proto.forcedDevice) return;
    const next = window.innerWidth <= 720 ? 'mobile' : 'desktop';
    if (state.device !== next) {
      state.device = next;
      baseRender();
      enhance();
    }
  });

  // Expose a few helpers for the domain files and for diagnosis.
  Proto.baseGo = baseGo;
  Proto.baseRender = baseRender;
  Proto.syncHash = syncHash;
  Proto.enhance = enhance;
  Proto.snapshot = snapshot;
  Proto.settingsSection = () => state.screen.startsWith('settings-') ? state.screen.replace('settings-', '') : '';
  // One navigation wrapper: keeps the URL, the per-screen scroll memory and
  // the enhancer pass consistent for every entry (nav, deep link, widget).
  Proto.navigate = (screen, opts) => {
    opts = opts || {};
    const before = state.screen + '|' + String(state.drawer && state.drawer.id || '');
    Proto.baseGo(screen);
    if (opts.drawer) state.drawer = opts.drawer;
    if (opts.date) state.selectedDate = opts.date;
    render();
    Proto.syncHash(!!opts.push);
    return before;
  };
  Proto.openTodo = (id, opts) => {
    if (Proto.recordRecent) Proto.recordRecent('todo', id);
    const t = typeof todoById === 'function' ? todoById(id) : null;
    // A series-level entry must not inherit a date bound by an earlier
    // calendar block. Only a caller that just bound an occurrence asks to keep it.
    if (!opts || !opts.keepOccurrence) { state.occurId = null; state.occurDate = null; }
    state.selectedDate = (t && t.due) || TODAY;
    baseGo('today');
    state.drawer = { type: 'todo', id };
    render();
  };
  Proto.openEvent = (id) => {
    if (Proto.recordRecent) Proto.recordRecent('event', id);
    baseGo('cal-day');
    state.drawer = { type: 'event', id };
    render();
  };
  Proto.goSection = (section, variant) => {
    baseGo('settings-' + section);
    if (variant) { state.variant = variant; render(); }
    syncHash(true);
  };
})();
