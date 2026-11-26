/* System flows: account, sync, notification permission, import/export/backup,
   AI conversation, command search and the widget entry. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, toast, modal, protoAction } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const go = (s) => { P.baseGo(s); P.syncHash(true); };

  /* ---------------- account ---------------- */
  registerAction('account-login', () => {
    if (state.variant === 'logged-out' || state.variant === 'failed' || state.variant === 'load-error') {
      const pw = qa('.settings-page .io-card input[type=password], .m-form input[type=password]').pop();
      if (pw && pw.value && pw.value.length < 8) {
        state.variant = 'failed';
        render();
        toast('邮箱或密码不正确 · 没有创建会话');
        return;
      }
      state.variant = 'submitting';
      render();
      setTimeout(() => {
        P.data.account.signedIn = true;
        P.data.account.email = 'chang@local';
        state.variant = 'normal';
        render();
        toast('已登录 · 同步已开启');
      }, 900);
      return;
    }
    state.variant = 'logged-out';
    render();
  });

  registerAction('account-register', () => {
    if (state.variant !== 'register' && state.variant !== 'register-error' && state.variant !== 'register-conflict') {
      state.variant = 'register';
      render();
      return;
    }
    const pw = qa('.settings-page .io-card input[type=password], .m-form input[type=password]').pop();
    if (pw && pw.value && pw.value.length < 8) {
      state.variant = 'register-error';
      render();
      toast('密码太短 · 至少 8 位');
      return;
    }
    state.variant = 'submitting';
    render();
    setTimeout(() => {
      P.data.account.signedIn = true;
      state.variant = 'normal';
      render();
      toast('账号已创建 · 已登录');
    }, 900);
  });

  registerAction('account-logout', () => {
    modal({
      title: '退出登录？',
      body: '<div class="proto-note">本地待办、日程和设置都会保留；只是停止上传与下载。</div>',
      actions: [
        { label: '取消' },
        { label: '退出', primary: true, danger: true, onClick: () => {
          P.data.account.signedIn = false;
          state.variant = 'logged-out';
          render();
          toast('已退出登录 · 本地数据保留');
        } },
      ],
    });
  });

  registerAction('account-retry', () => {
    state.variant = 'loading';
    render();
    setTimeout(() => { state.variant = 'normal'; render(); }, 700);
  });

  registerAction('account-cancel', () => { state.variant = 'normal'; render(); });

  registerAction('sync-now', () => {
    if (!P.data.account.signedIn) { go('settings-sync-logged-out'); return; }
    if (P.data.sync.offline) {
      state.variant = 'error';
      render();
      toast('服务器不可达 · 本地修改没有丢');
      return;
    }
    state.variant = 'loading';
    render();
    setTimeout(() => {
      P.data.account.lastSync = '刚刚 · 成功';
      P.data.account.pending = 0;
      state.variant = 'normal';
      render();
      toast('同步完成 · 本地与服务器一致');
    }, 900);
  });

  registerAction('sync-apply', () => {
    state.variant = 'normal';
    P.data.sync.conflicts = 0;
    render();
    toast('冲突已按选择处理');
  });

  /* ---------------- notification permission ---------------- */
  registerAction('notify-open-settings', () => {
    if (P.data.notify.permission === 'denied') {
      P.data.notify.permission = 'granted';
      P.data.notify.exact = true;
      go('settings-notify');
      toast('系统通知已重新允许');
    } else {
      P.data.notify.permission = 'denied';
      P.data.notify.exact = false;
      go('settings-notify-denied');
    }
  });

  registerAction('notify-toggle', () => {
    if (P.data.notify.permission === 'granted') {
      P.data.notify.permission = 'denied';
      P.data.notify.exact = false;
      go('settings-notify-denied');
    } else {
      P.data.notify.permission = 'granted';
      P.data.notify.exact = true;
      go('settings-notify');
    }
  });

  /* ---------------- import / export / backup ---------------- */
  registerAction('import-pick', () => {
    const files = [
      { name: 'dayplan.ics', meta: '18 个事件 · 4 个待办 · 1 行日期无效', bad: false },
      { name: 'dayplan-broken.ics', meta: '第 14 行日期无法识别，导入会失败', bad: true },
    ];
    const body = document.createElement('div');
    body.className = 'proto-list';
    files.forEach((f) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'proto-list-row';
      b.innerHTML = `<span class="grow">${f.name}<small>${f.meta}</small></span><span class="proto-badge">选择</span>`;
      b.addEventListener('click', () => {
        P.data.importFile = f.name;
        P.data.importBad = f.bad;
        state.variant = 'preview';
        if (state.screen !== 'settings-import') { P.baseGo('settings-import'); state.variant = 'preview'; }
        render();
        toast('已选择 ' + f.name);
      });
      body.appendChild(b);
    });
    modal({ title: '选择要导入的 ICS 文件', body, actions: [{ label: '取消' }] });
  });

  registerAction('import-calendar', () => {
    const body = document.createElement('div');
    body.className = 'proto-list';
    Object.keys(CAL).filter((id) => !state.deletedCals.includes(id)).forEach((id) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'proto-list-row';
      b.innerHTML = `<span class="cal-dot" style="background:${CAL[id].color}"></span><span class="grow">${CAL[id].name}<small>${CAL[id].name} · 当前 ${EVENTS.filter((e) => e.cal === id).length} 个日程</small></span>`;
      b.addEventListener('click', () => {
        P.data.importCalendar = id;
        render();
        toast('导入目标 · ' + CAL[id].name);
      });
      body.appendChild(b);
    });
    modal({ title: '导入到哪个日历', body, actions: [{ label: '取消' }] });
  });

  registerAction('import-next', () => {
    simulateImport(false);
  });
  registerAction('import-skip', () => {
    simulateImport(true);
  });
  registerAction('import-cancel', () => { go('settings-io'); });
  registerAction('import-report', () => {
    modal({
      title: '导入报告',
      body: `<div class="proto-list"><div class="proto-note">dayplan.ics · 目标「工作」</div>
        <div class="proto-list-row"><span class="grow">成功写入<small>18 个日程 · 4 个待办</small></span><span class="proto-badge">22</span></div>
        <div class="proto-list-row"><span class="grow">跳过<small>第 14 行：日期格式无法识别</small></span><span class="proto-badge">1</span></div>
        <div class="proto-list-row"><span class="grow">重复<small>按 UID 去重，没有覆盖已有条目</small></span><span class="proto-badge">0</span></div></div>`,
      actions: [{ label: '关闭', primary: true }],
    });
  });

  function simulateImport(skipBad) {
    if (P.data.importBad && !skipBad) {
      state.variant = 'importing';
      render();
      setTimeout(() => {
        state.variant = 'error';
        render();
        toast('导入失败 · 没有写入任何内容');
      }, 800);
      return;
    }
    state.variant = 'importing';
    render();
    setTimeout(() => {
      const cal = P.data.importCalendar || 'work';
      const today = TODAY;
      EVENTS.push(
        { id: 'import-' + Date.now() + '-a', title: '设计评审（导入）', cal, date: today, start: '10:00', end: '11:00' },
        { id: 'import-' + Date.now() + '-b', title: '牙医复诊（导入）', cal: 'health', date: today, start: '14:30', end: '15:15' },
      );
      TODOS.unshift({ id: 'import-todo-' + Date.now(), title: '整理导入后的重复项', cal, priority: 0, tags: [], note: '从 dayplan.ics 导入', status: 'open' });
      state.variant = 'success';
      render();
      toast('导入完成 · 21 项写入');
    }, 900);
  }

  // ICS export/import is owned by flows-v3-data.js (full DTSTART/DTEND, CRLF
  // folding, VTODO). No second builder here.

  // Full backup export + merge back live in flows-v3-data.js (it loads later
  // and owns the real file-producing implementation). Do not add a second
  // handler here — two paths would overwrite each other.

  /* ---------------- AI ---------------- */
  const AI_REPLY = (text) => {
    if (/周报|总结|纪要/.test(text)) {
      return '可以。先把这周的进展压成三条：\n1. 11 月版本的三处交互已经收敛。\n2. ICS 第 14 行的日期容错还需要补。\n3. Q4 提案框架周三前给林总。\n\n要我把第三条记成周三 18:00 截止的待办吗？';
    }
    if (/今天|还剩|剩下/.test(text)) {
      const open = TODOS.filter((t) => t.status !== 'done' && t.due === TODAY);
      return open.length
        ? '今天还有 ' + open.length + ' 项：' + open.slice(0, 4).map((t) => t.title).join('、') + '。要我按优先级重排吗？'
        : '今天的待办都完成了。日历里还有牙医复诊和钢琴课。';
    }
    if (/安排|排一下|计划/.test(text)) {
      return '建议把「提交周报给林总」放在 15:15–16:00，避开 14:30 的牙医复诊。要打开安排选择器吗？';
    }
    return '我可以帮你整理待办、拆子任务或安排时间。说说你现在想先处理哪一件。';
  };

  registerAction('ai-send-proto', () => {
    const input = q('#ai-input');
    const text = (input && input.value || '').trim();
    if (!text) return;
    if (typeof AI_THREAD === 'undefined') return;
    AI_THREAD.push({ role: 'user', text });
    state.aiInput = '';
    state.variant = 'sending';
    render();
    setTimeout(() => {
      AI_THREAD.push({ role: 'ai', text: AI_REPLY(text), actions: true });
      state.variant = 'normal';
      render();
    }, 900);
  });

  registerAction('ai-insert-proto', (el) => {
    const label = (el.textContent || '').trim();
    if (label.includes('日程')) {
      P.baseGo('new-event');
      P.syncHash(true);
      setTimeout(() => { const i = q('#new-title'); if (i) i.value = '周报评审'; }, 30);
    } else if (label.includes('安排')) {
      P.baseGo('plan-picker');
      state.planTodoId = 'report';
      state.planReturn = 'ai-chat';
      render();
      P.syncHash(true);
    } else if (label.includes('子任务')) {
      const t = TODOS.find((x) => x.id === 'report');
      if (t) {
        t.subtasks = t.subtasks || [];
        ['整理阻塞点', '附上数据', '发给林总'].forEach((s) => t.subtasks.push({ title: s, done: false }));
      }
      toast('已拆成 3 个子任务 · 打开详情查看');
    } else {
      P.baseGo('new-todo');
      P.syncHash(true);
      setTimeout(() => { const i = q('#new-title'); if (i) i.value = '整理这周周报的三条要点'; }, 30);
    }
  });

  /* ---------------- widgets entry ---------------- */
  registerAction('widget-open', (el) => {
    const target = el.dataset.widgetTarget || 'today';
    if (target === 'todo') { go('todos/inbox'); return; }
    if (target === 'calendar') { go('calendar/month'); return; }
    go('today');
  });

  /* ---------------- enhancer ---------------- */
  registerEnhancer((root) => {
    // Account / sync / notify display should follow the simulated facts.
    const section = state.screen.startsWith('settings-') ? state.screen.replace('settings-', '') : '';

    if (section === 'general') {
      qa('.m-settings-row', root).forEach((el) => {
        if (!el.dataset.protoAction && (el.textContent || '').includes('启动时打开')) {
          el.dataset.protoAction = 'startup-pick';
        }
      });
    }

    qa('.m-settings-row', root).forEach((el) => {
      if (el.dataset.protoAction || el.dataset.action) return;
      const t = (el.textContent || '');
      if (section === 'about' && t.includes('许可')) el.dataset.protoAction = 'about-license';
      else if (section === 'about' && t.includes('版本')) el.dataset.protoAction = 'about-version';
      else if (section === 'about' && t.includes('数据')) el.dataset.protoAction = 'storage-info';
      else if (section === 'general' && t.includes('启动时')) el.dataset.protoAction = 'startup-pick';
      else if (section === 'account' && t.includes('已连接设备')) el.dataset.protoAction = 'devices-open';
      else if ((section === 'import' || section === 'io') && t.includes('选择文件')) el.dataset.protoAction = 'import-pick';
      else if ((section === 'import' || section === 'io') && t.includes('目标日历')) el.dataset.protoAction = 'import-calendar';
      else if ((section === 'import' || section === 'io') && t.includes('预览与写入')) el.dataset.protoAction = 'import-next';
      else if (section === 'backup' && t.includes('完整备份')) el.dataset.protoAction = 'backup-export';
      else if (section === 'backup' && t.includes('合并备份')) el.dataset.protoAction = 'backup-merge';
      else if (section === 'notify' && (t.includes('系统闹钟') || t.includes('通知权限') || t.includes('精确提醒'))) el.dataset.protoAction = 'notify-detail';
      else if (section === 'sync-failed' && t.includes('本地状态')) el.dataset.protoAction = 'sync-pending';
    });

    if (section === 'account') {
      qa('.m-settings-row', root).forEach((el) => {
        if ((el.textContent || '').includes('已连接设备') && !el.dataset.protoAction) {
          el.dataset.protoAction = 'devices-open';
        }
      });
    }

    if (section === 'account' || section === 'sync') {
      const who = P.data.account.signedIn ? P.data.account.email : '未登录';
      qa('.set-account-main b', root).forEach((b) => {
        if (!P.data.account.signedIn && state.variant !== 'logged-out') b.textContent = '未登录';
      });
      qa('.set-value, .set-account-main small', root).forEach((el) => {
        if ((el.textContent || '').includes('chang@local')) el.textContent = who;
        if ((el.textContent || '').includes('14:58')) el.textContent = P.data.account.lastSync;
        if ((el.textContent || '').trim().endsWith('台')) el.textContent = (P.data.account.devices || []).length + ' 台';
      });
    }

    if (section === 'notify') {
      qa('.m-settings-row', root).forEach((el) => {
        if (!el.dataset.protoAction) el.dataset.protoAction = 'notify-toggle';
      });
      qa('.set-value', root).forEach((el) => {
        const t = el.textContent || '';
        if (t.includes('已允许') && P.data.notify.permission !== 'granted') el.textContent = '已拒绝';
      });
    }

    // Command palette: search the real store instead of the spec sample.
    if (state.screen === 'command') {
      if (!state._cmdTouched && state.cmdQuery === '周报') state.cmdQuery = '';
      const input = q('.cmd-input input, .m-cmd-input input', root);
      if (input) {
        input.value = state.cmdQuery;
        if (!input.dataset.bound) {
          input.dataset.bound = '1';
          input.addEventListener('input', () => {
            state._cmdTouched = true;
            state.cmdQuery = input.value;
            state.variant = 'result';
            render();
            const again = q('.cmd-input input, .m-cmd-input input');
            if (again) { again.focus(); again.setSelectionRange(again.value.length, again.value.length); }
          });
        }
      }
      const body = q('.cmd-body, .m-cmd-body', root);
      if (body) body.innerHTML = searchBody(state.cmdQuery);
    }

    // AI composer and chips.
    qa('.ai-send', root).forEach((b) => protoAction(b, 'ai-send-proto'));
    qa('.ai-chip', root).forEach((b) => protoAction(b, 'ai-insert-proto'));

    // Widget page is a preview surface: make each widget clickable into the app.
    if (state.screen === 'widgets') {
      qa('.wd-ios, .wd-and', root).forEach((w) => {
        if (w.dataset.protoAction) return;
        w.dataset.protoAction = 'widget-open';
        w.dataset.widgetTarget = (w.textContent || '').includes('待办') ? 'todo'
          : (w.textContent || '').includes('月') ? 'calendar' : 'today';
        w.style.cursor = 'pointer';
      });
    }
  });

  function searchBody(query) {
    const qtext = (query || '').trim();
    if (!qtext) {
      const recents = TODOS.slice(0, 2).map((t) =>
        `<button type="button" class="cmd-row" data-proto-action="search-open-todo" data-id="${t.id}">${ico('check', 14)}<span class="cmd-row-main"><span class="cmd-row-t">${esc(t.title)}</span><span class="cmd-row-m">${calOf(t.cal).name} · 待办</span></span><span class="cmd-row-side">待办</span></button>`).join('');
      return `<div class="cmd-group">最近</div>${recents}<div class="cmd-group">动作</div>
        <button type="button" class="cmd-row" data-proto-action="search-new-todo">${ico('plus', 14)}<span class="cmd-row-main"><span class="cmd-row-t">新建待办</span><span class="cmd-row-m">进入整页创建</span></span><span class="cmd-row-side">动作</span></button>
        <button type="button" class="cmd-row" data-proto-action="search-new-event">${ico('calendar', 14)}<span class="cmd-row-main"><span class="cmd-row-t">新建日程</span><span class="cmd-row-m">进入整页创建</span></span><span class="cmd-row-side">动作</span></button>`;
    }
    const lower = qtext.toLowerCase();
    const todos = TODOS.concat(state.localTodos || []).filter((t) => (t.title || '').toLowerCase().includes(lower)).slice(0, 4);
    const events = EVENTS.filter((e) => !state.deletedEvents.includes(e.id) && (e.title || '').toLowerCase().includes(lower)).slice(0, 4);
    if (!todos.length && !events.length) {
      return `<div class="cmd-empty">${ico('search', 23)}<p>没有找到「${esc(qtext)}」</p><button type="button" class="mini-btn" style="margin-top:10px" data-proto-action="search-new-todo">用这句话新建待办</button></div>`;
    }
    let out = '';
    if (todos.length) {
      out += '<div class="cmd-group">待办</div>' + todos.map((t) =>
        `<button type="button" class="cmd-row" data-proto-action="search-open-todo" data-id="${t.id}">${ico('check', 14)}<span class="cmd-row-main"><span class="cmd-row-t">${esc(t.title)}</span><span class="cmd-row-m">${calOf(t.cal).name}${t.due ? ' · 截止 ' + dueText(t) : ''}</span></span><span class="cmd-row-side">待办</span></button>`).join('');
    }
    if (events.length) {
      out += '<div class="cmd-group">日程</div>' + events.map((e) =>
        `<button type="button" class="cmd-row" data-proto-action="search-open-event" data-id="${e.id}">${ico('calendar', 14)}<span class="cmd-row-main"><span class="cmd-row-t">${esc(e.title)}</span><span class="cmd-row-m">${calOf(e.cal).name} · ${mdShort(e.date || e.startDate || TODAY)}</span></span><span class="cmd-row-side">日程</span></button>`).join('');
    }
    out += `<div class="cmd-group">动作</div>
      <button type="button" class="cmd-row" data-proto-action="search-new-todo">${ico('plus', 14)}<span class="cmd-row-main"><span class="cmd-row-t">新建待办</span><span class="cmd-row-m">标题“${esc(qtext)}”</span></span><span class="cmd-row-side">动作</span></button>`;
    return out;
  }

  registerAction('search-open-todo', (el) => P.openTodo(el.dataset.id));
  registerAction('search-open-event', (el) => P.openEvent(el.dataset.id));
  registerAction('search-new-todo', () => {
    P.baseGo('new-todo');
    P.syncHash(true);
    setTimeout(() => { const i = q('#new-title'); if (i && state.cmdQuery) i.value = state.cmdQuery; }, 30);
  });
  registerAction('search-new-event', () => {
    P.baseGo('new-event');
    P.syncHash(true);
    setTimeout(() => { const i = q('#new-title'); if (i && state.cmdQuery) i.value = state.cmdQuery; }, 30);
  });
})();

/* ---------------- devices, startup, feedback, standalone trash ---------------- */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, toast, modal } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));

  registerAction('devices-open', () => {
    const body = document.createElement('div');
    body.className = 'proto-list';
    (P.data.account.devices || []).forEach((d) => {
      const row = document.createElement('div');
      row.className = 'proto-list-row';
      row.innerHTML = `<span class="grow">${d.name}<small>${d.meta}</small></span>${d.current ? '<span class="proto-badge">本机</span>' : ''}`;
      body.appendChild(row);
    });
    modal({
      title: '已连接设备',
      body: body.outerHTML + '<div class="proto-note">只读列表，按最后活跃排序。原型不会真的吊销设备。</div>',
      actions: [{ label: '关闭', primary: true }],
    });
  });

  registerAction('startup-pick', () => {
    const options = [['today', '今天'], ['todos/inbox', '待办'], ['calendar/week', '日历']];
    const body = document.createElement('div');
    body.className = 'proto-list';
    options.forEach(([value, label]) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'proto-list-row';
      b.innerHTML = `<span class="grow">${label}</span>${P.data.startup === value ? '<span class="proto-badge">当前</span>' : ''}`;
      b.addEventListener('click', () => {
        P.data.startup = value;
        render();
        toast('启动时打开 · ' + label);
        b.closest('.proto-modal-scrim').remove();
      });
      body.appendChild(b);
    });
    modal({ title: '启动时打开', body, actions: [{ label: '取消' }] });
  });

  registerEnhancer((root) => {
    // Feedback copy should really hit the clipboard.
    qa('[data-action="fb-copy"]', root).forEach((b) => {
      if (b.dataset.protoAction) return;
      b.dataset.protoAction = 'fb-copy-proto';
    });
    // Standalone trash page rows are static in the master; make them act.
    const rows = qa('.simple-wrap .trash-row, .edit-body .trash-row', root);
    const hidden = P.data.hiddenTrash || (P.data.hiddenTrash = []);
    rows.forEach((row) => {
      const titleEl = q('.trash-main > div', row);
      const title = (titleEl && titleEl.textContent || '').trim();
      if (!title) return;
      if (hidden.includes(title)) { row.remove(); return; }
      const buttons = qa('button', row);
      buttons.forEach((b) => {
        const t = (b.textContent || '').trim();
        if (t === '恢复') b.dataset.protoAction = 'trash-restore-proto';
        if (t.includes('永久')) b.dataset.protoAction = 'trash-delete-proto';
        b.dataset.trashTitle = title;
      });
    });
    const clear = qa('.edit-bar .edit-save, .edit-bar .tool', root).find((b) => (b.textContent || '').includes('清空'));
    if (clear && !clear.dataset.protoAction) clear.dataset.protoAction = 'trash-clear-proto';
  });

  registerAction('trash-restore-proto', (el) => {
    const title = el.dataset.trashTitle || '这一项';
    if (!TODOS.some((t) => t.title === title)) {
      TODOS.unshift({ id: 'restored-' + Date.now(), title, cal: 'personal', priority: 0, tags: [], status: 'open' });
    }
    P.data.hiddenTrash = P.data.hiddenTrash || [];
    P.data.hiddenTrash.push(title);
    render();
    toast('已恢复 · ' + title);
  });

  registerAction('trash-delete-proto', (el) => {
    const title = el.dataset.trashTitle || '这一项';
    P.data.hiddenTrash = P.data.hiddenTrash || [];
    if (!P.data.hiddenTrash.includes(title)) P.data.hiddenTrash.push(title);
    render();
    toast('已永久删除 · ' + title);
  });

  registerAction('trash-clear-proto', () => {
    P.data.hiddenTrash = qa('.trash-row .trash-main > div').map((x) => (x.textContent || '').trim());
    render();
    toast('回收站已清空');
  });

  registerAction('fb-copy-proto', () => {
    const text = (q('#fb-text') && q('#fb-text').value) || (q('.form-textarea') && q('.form-textarea').value) || 'DaySpark 反馈';
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).catch(() => {});
    state.fbCopied = true;
    state.variant = 'copied';
    render();
    toast('已复制反馈内容');
  });
})();

/* Undo bar lives for four seconds, like the frozen interaction. */
(function () {
  let timer = 0;
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-action="toggle-done"]');
    if (!el) return;
    const id = el.dataset.id;
    clearTimeout(timer);
    setTimeout(() => {
      if (state.undoId === id) {
        state.undoId = null;
        state.undoName = null;
        render();
      }
    }, 4000);
  }, false);
})();

/* Quick Add is owned by flows-v3-capture.js (loaded later): one parser, one
   contract, one save path. This file must not define a second P.quickAdd. */

/* Account pages reflect the simulated session. */
(function () {
  const P = window.Proto;
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-action="settings"][data-section]');
    if (!el) return;
    const section = el.dataset.section;
    if (P.data.account.signedIn) return;
    if (section !== 'account' && section !== 'sync') return;
    setTimeout(() => {
      if (section === 'account' && state.screen === 'settings-account' && state.variant === 'normal') {
        state.variant = 'logged-out';
        render();
      }
      if (section === 'sync' && state.screen === 'settings-sync' && state.variant === 'normal') {
        state.variant = 'sync-logged-out';
        render();
      }
    }, 0);
  }, false);
})();

/* Clearing the AI thread removes the messages this prototype appended. */
(function () {
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-action="ai-clear-confirm"]');
    if (!el) return;
    if (typeof AI_THREAD !== 'undefined' && AI_THREAD.length > 2) {
      AI_THREAD.splice(2);
      render();
    }
  }, false);
})();

/* The master resets aiConfigOpen from the variant on every render; open via
   the design's own "config" variant so the dialog survives the render. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer } = P;
  registerEnhancer((root) => {
    root.querySelectorAll('[data-action="ai-config-open"], [data-action="ai-open-config"]').forEach((b) => {
      if (!b.dataset.protoAction) b.dataset.protoAction = 'ai-config-open-proto';
    });
  });
  registerAction('ai-config-open-proto', () => {
    state.variant = 'config';
    state.aiConfigOpen = true;
    render();
  });
})();
