/* DaySpark prototype v2 — shared preferences, demo states, real fallbacks,
   context menus, keyboard shortcuts and global chrome. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));

  P.data.prefs = Object.assign({
    theme: 'warm', accent: 'warm', language: 'zh', density: 'comfortable', startup: 'today',
  }, P.data.prefs || {});
  P.demo = P.demo || {
    offline: false, conflict: false, saveError: false, notifyDenied: false,
    storageFull: false, update: false, importError: false,
  };

  function applyPrefs() {
    document.body.dataset.protoTheme = P.data.prefs.theme || 'warm';
    document.body.dataset.protoAccent = P.data.prefs.accent || 'warm';
    document.body.dataset.protoDensity = P.data.prefs.density || 'comfortable';
    document.documentElement.lang = P.data.prefs.language === 'en' ? 'en' : 'zh-CN';
  }
  applyPrefs();
  registerEnhancer(applyPrefs);

  P.toastAction = function (msg, label, fn) {
    const scrim = modal({
      title: '', body: `<div class="proto-note" style="font-size:12px;color:var(--ink)">${esc(msg)}</div>`,
      actions: [{ label: '关闭' }, { label, primary: true, onClick: fn }],
    });
    return scrim;
  };

  /* ---------------- theme / language / preferences ---------------- */
  function choose(opts) {
    const body = document.createElement('div');
    body.className = 'proto-list';
    (opts.options || []).forEach((o) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'proto-list-row' + (o.disabled ? ' proto-disabled' : '');
      b.disabled = !!o.disabled;
      b.innerHTML = `<span class="grow">${esc(o.label)}${o.note ? `<small>${esc(o.note)}</small>` : ''}</span>${o.on ? '<span class="proto-badge">当前</span>' : ''}`;
      if (!o.disabled) b.addEventListener('click', () => { b.closest('.proto-modal-scrim').remove(); opts.onPick(o.value); });
      body.appendChild(b);
    });
    return modal({ title: opts.title, body, actions: [{ label: '取消' }], sheet: true });
  }

  registerAction('pref-theme', () => {
    const cur = P.data.prefs.theme;
    choose({
      title: '主题', options: [
        { value: 'light', label: '白纸', note: '纯白内容面，适合明亮环境', on: cur === 'light' },
        { value: 'warm', label: '暖灰', note: '默认 · 低对比纸面', on: cur === 'warm' },
        { value: 'dark', label: '夜间', note: '深色纸面，减少夜间眩光', on: cur === 'dark' },
      ], onPick: (v) => { P.data.prefs.theme = v; applyPrefs(); render(); toast('主题已切换'); },
    });
  });
  registerAction('pref-accent', () => {
    const cur = P.data.prefs.accent;
    choose({
      title: '强调色', options: [
        { value: 'warm', label: '墨色', note: '选中与操作用墨色，日历色不受影响', on: cur === 'warm' },
        { value: 'blue', label: '靛蓝', note: '只影响选中与主按钮', on: cur === 'blue' },
        { value: 'green', label: '苔绿', note: '只影响选中与主按钮', on: cur === 'green' },
      ], onPick: (v) => { P.data.prefs.accent = v; applyPrefs(); render(); toast('强调色已更新'); },
    });
  });
  registerAction('pref-language', () => {
    choose({
      title: '语言', options: [
        { value: 'zh', label: '简体中文', note: '当前版本唯一完整语言', on: P.data.prefs.language === 'zh' },
        { value: 'en', label: 'English', note: '文案尚未翻译，暂不提供', disabled: true },
      ], onPick: () => {},
    });
  });
  registerAction('settings-cal-new', () => { P.baseGo('settings-calendar-new'); render(); P.syncHash(true); });
  registerAction('pref-startup', () => {
    const cur = P.data.prefs.startup || 'today';
    choose({
      title: '启动时打开', options: [
        { value: 'today', label: '今天', on: cur === 'today' },
        { value: 'todo-inbox', label: '待办 · 未安排', on: cur === 'todo-inbox' },
        { value: 'cal-week', label: '日历 · 周', on: cur === 'cal-week' },
      ], onPick: (v) => { P.data.prefs.startup = v; P.data.startup = v; render(); toast('启动页已更新'); },
    });
  });

  /* ---------------- settings rows that are facts, not links ---------------- */
  function rowLabel(el) {
    const l = q('.set-label, .m-settings-row > span:first-child', el);
    return (l ? l.textContent : el.textContent || '').replace(/\s+/g, ' ').trim();
  }
  function rowValue(el) {
    const v = q('.set-value, .m-settings-value', el);
    return (v ? v.textContent : '').replace(/\s+/g, ' ').trim();
  }

  registerEnhancer((root) => {
    if (!state.screen.startsWith('settings-')) return;
    const section = state.screen.replace('settings-', '');
    qa('.set-row, .m-settings-row', root).forEach((el) => {
      if (el.dataset.protoAction && el.dataset.protoAction !== 'info-open') return;
      delete el.dataset.protoAction;
      const label = rowLabel(el);
      const value = rowValue(el);
      if (!el.dataset.action || el.dataset.action === 'noop') {
        if (label.includes('主题')) el.dataset.protoAction = 'pref-theme';
        else if (label.includes('强调色')) el.dataset.protoAction = 'pref-accent';
        else if (label.includes('语言')) el.dataset.protoAction = 'pref-language';
        else if (label.includes('启动时')) el.dataset.protoAction = 'pref-startup';
        else if (label.includes('服务器')) el.dataset.protoAction = 'server-edit';
        else if (label.includes('最后同步')) el.dataset.protoAction = 'sync-detail';
        else if (label.includes('待上传')) el.dataset.protoAction = 'sync-pending';
        else if (label.includes('服务器拒绝')) el.dataset.protoAction = 'sync-rejected';
        else if (label.includes('冲突')) el.dataset.protoAction = 'sync-conflict-open';
        else if (label.includes('版本')) el.dataset.protoAction = 'about-version';
        else if (label.includes('数据') && section === 'about') el.dataset.protoAction = 'storage-info';
        else if (label.includes('已连接设备')) el.dataset.protoAction = 'devices-open';
        else if (label.includes('立即同步')) el.dataset.protoAction = 'sync-now';
        else if (label.includes('退出登录')) el.dataset.protoAction = 'account-logout';
        else if (label.includes('许可')) el.dataset.protoAction = 'about-license';
      }
      if (el.dataset.protoAction) el.dataset.protoLabel = label;
    });
    // Empty-state creation buttons in settings.
    qa('button', root).forEach((b) => {
      if (b.dataset.protoAction) return;
      const t = (b.textContent || '').trim();
      if (t.includes('新建标签')) b.dataset.protoAction = 'tag-new';
      else if (t.includes('新建日历') && section.startsWith('calendar')) b.dataset.protoAction = 'settings-cal-new';
      else if (section === 'account' && t.includes('立即同步')) b.dataset.protoAction = 'sync-now';
      else if (section === 'account' && t.includes('退出登录')) b.dataset.protoAction = 'account-logout';
      else if (section === 'io' || section === 'import') {
        if (t.includes('选择文件')) b.dataset.protoAction = 'import-pick';
        else if (t.includes('选择日历')) b.dataset.protoAction = 'import-calendar';
        else if (t.includes('导出全部')) b.dataset.protoAction = 'export-ics';
        else if (t.includes('导出备份') || t.includes('完整备份')) b.dataset.protoAction = 'backup-export';
        else if (t.includes('合并备份') || t.includes('选择备份文件')) b.dataset.protoAction = 'backup-merge';
      }
    });
    // Keep the simulated facts in the copy.
    qa('.set-value', root).forEach((el) => {
      const t = (el.textContent || '').trim();
      if (t === 'sync.dayspark.local') el.textContent = P.data.account.server.replace(/^https?:\/\//, '');
      if (t === 'chang@local') el.textContent = P.data.account.email;
      if (t.includes('14:58')) el.textContent = P.data.account.lastSync;
      if (t.endsWith('台')) el.textContent = (P.data.account.devices || []).length + ' 台';
      if (t === '0 项' && el.closest('.set-row') && rowLabel(el.closest('.set-row')).includes('待上传')) el.textContent = P.data.account.pending + ' 项';
      if (t === '浅色') el.textContent = P.data.prefs.theme === 'dark' ? '夜间' : P.data.prefs.theme === 'light' ? '白纸' : '暖灰';
      if (t === '暖灰' && el.closest('.set-row') && rowLabel(el.closest('.set-row')).includes('强调色')) {
        el.textContent = P.data.prefs.accent === 'blue' ? '靛蓝' : P.data.prefs.accent === 'green' ? '苔绿' : '墨色';
      }
      if (t === '今天' && el.closest('.set-row') && rowLabel(el.closest('.set-row')).includes('启动时')) {
        el.textContent = P.data.prefs.startup === 'todo-inbox' ? '未安排' : P.data.prefs.startup === 'cal-week' ? '日历 · 周' : '今天';
      }
    });
  });

  registerAction('server-edit', () => {
    P.prompt({
      title: '同步服务器', label: '服务器地址', value: P.data.account.server,
      note: '只影响同步；本地数据不会因为改地址而删除。',
      onConfirm: (v) => {
        if (!v) { toast('服务器地址不能为空'); return; }
        P.data.account.server = v;
        render();
        toast('服务器已更新');
      },
    });
  });
  registerAction('sync-detail', () => {
    modal({
      title: '同步状态',
      body: `<div class="proto-list">
        <div class="proto-list-row"><span class="grow">最后成功<small>${esc(P.data.account.lastSync)}</small></span><span class="proto-badge">成功</span></div>
        <div class="proto-list-row"><span class="grow">待上传<small>本地改动还没上传</small></span><span>${P.data.account.pending} 项</span></div>
        <div class="proto-list-row"><span class="grow">服务器<small>${esc(P.data.account.server)}</small></span><span class="proto-badge">可达</span></div>
      </div>`,
      actions: [{ label: '关闭' }, { label: '立即同步', primary: true, onClick: () => { P.actions['sync-now'](); } }],
    });
  });
  registerAction('sync-pending', () => {
    modal({
      title: '待上传的改动',
      body: P.data.account.pending
        ? `<div class="proto-note">${P.data.account.pending} 项本地改动正在等待上传。断网或服务器不可达时，本地仍然可编辑。</div>`
        : '<div class="proto-note">没有待上传的改动。所有本地修改都已写入服务器。</div>',
      actions: [{ label: '关闭' }, { label: '立即同步', primary: true, onClick: () => P.actions['sync-now']() }],
    });
  });
  registerAction('sync-rejected', () => {
    modal({
      title: '服务器拒绝的改动',
      body: '<div class="proto-note">最近没有被服务器拒绝的改动。若出现，这里会逐条列出原因（权限、字段格式、版本不兼容），不会静默丢弃。</div>',
      actions: [{ label: '关闭' }],
    });
  });
  registerAction('storage-info', () => {    let bytes = 0;
    try { bytes = new Blob([localStorage.getItem('dayspark.prototype.v1') || '']).size; } catch (_) {}
    modal({
      title: '数据与存储',
      body: `<div class="proto-list">
        <div class="proto-list-row"><span class="grow">存储位置<small>本机浏览器</small></span><span>localStorage</span></div>
        <div class="proto-list-row"><span class="grow">当前占用<small>待办、日程、设置与草稿</small></span><span>${(bytes / 1024).toFixed(1)} KB</span></div>
        <div class="proto-list-row"><span class="grow">同步<small>${esc(P.data.account.server)}</small></span><span>${P.data.account.signedIn ? '已登录' : '未登录'}</span></div>
      </div>`,
      actions: [{ label: '关闭' }, { label: '导出备份', onClick: () => P.actions['backup-export']() }],
    });
  });

  /* ---------------- update notes / shortcuts ---------------- */
  registerAction('whats-new', () => {
    modal({
      title: 'DaySpark 0.36 · 更新内容',
      wide: true,
      body: `<div class="proto-note" style="line-height:1.7">
        <b style="color:var(--ink)">这次更新</b><br>
        · 重复日程会在日历里按规则展开，删除与保存都能选择影响范围。<br>
        · 日历支持拖动改期、拖动下缘改时长；空白时段可以直接新建。<br>
        · 主题、强调色、启动页与默认日历都可以真正修改。<br>
        · 导入会先预览再写入；备份可以合并回来。<br>
        · 所有“这一项没有更深步骤”的占位说明已移除；只读项会明确标注为只读。
      </div>`,
      actions: [{ label: '知道了', primary: true }],
    });
  });
  P.openShortcuts = function () {
    modal({
      title: '键盘快捷键',
      body: `<div class="proto-kbd-list">
        <div><span class="grow">搜索 / 命令框</span><span class="proto-kbd">⌘ K</span></div>
        <div><span class="grow">新建待办</span><span class="proto-kbd">N</span></div>
        <div><span class="grow">新建日程</span><span class="proto-kbd">E</span></div>
        <div><span class="grow">回到今天</span><span class="proto-kbd">T</span></div>
        <div><span class="grow">周 / 月 / 日</span><span class="proto-kbd">W</span><span class="proto-kbd">M</span><span class="proto-kbd">D</span></div>
        <div><span class="grow">打开选中项</span><span class="proto-kbd">Enter</span></div>
        <div><span class="grow">完成 / 取消完成</span><span class="proto-kbd">X</span></div>
        <div><span class="grow">删除选中项</span><span class="proto-kbd">Delete</span></div>
        <div><span class="grow">关闭弹层</span><span class="proto-kbd">Esc</span></div>
        <div><span class="grow">快捷键一览</span><span class="proto-kbd">?</span></div>
      </div>`,
      actions: [{ label: '知道了', primary: true }],
    });
  };

  /* ---------------- demo control (low-frequency states only) ---------------- */
  const demoDefs = [
    ['offline', '离线', '断开同步；本地仍可编辑'],
    ['conflict', '同步冲突', '两条改动需要选择版本'],
    ['saveError', '保存失败', '下一次保存保留输入并报错'],
    ['notifyDenied', '通知被拒绝', '进入权限被拒的恢复路径'],
    ['storageFull', '存储将满', '浏览器存储接近上限'],
    ['update', '有新版本', '显示更新说明入口'],
    ['importError', '导入失败', 'ICS 解析失败的报告'],
  ];
  P.openDemo = function () {
    const body = document.createElement('div');
    body.innerHTML = '<div class="proto-demo-grid"></div><div class="proto-demo-note" style="margin-top:10px">这些只用于触发低频异常状态；正常产品操作不依赖它们。刷新页面后恢复默认。</div>';
    const grid = q('.proto-demo-grid', body);
    demoDefs.forEach(([key, label, note]) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = P.demo[key] ? 'is-on' : '';
      b.innerHTML = `<b>${label}</b><small style="display:block;color:var(--faint);font-size:9.5px;margin-top:2px">${note}</small>`;
      b.addEventListener('click', () => {
        P.demo[key] = !P.demo[key];
        if (key === 'offline') P.data.sync.offline = P.demo.offline;
        if (key === 'conflict') P.data.sync.conflicts = P.demo.conflict ? 2 : 0;
        if (key === 'notifyDenied') {
          P.data.notify.permission = P.demo.notifyDenied ? 'denied' : 'granted';
          P.data.notify.exact = !P.demo.notifyDenied;
        }
        b.classList.toggle('is-on', P.demo[key]);
        render();
        toast(label + (P.demo[key] ? ' · 已开启' : ' · 已关闭'));
      });
      grid.appendChild(b);
    });
    modal({
      title: '演示状态', wide: true, body,
      actions: [
        { label: '全部关闭', onClick: () => { demoDefs.forEach(([k]) => { P.demo[k] = false; }); P.data.sync.offline = false; P.data.sync.conflicts = 0; render(); } },
        { label: '关闭', primary: true },
      ],
    });
  };

  registerEnhancer((root) => {
    const host = state.device === 'mobile' ? q('.m-app', root) : q('.p-main', root);
    if (!host) return;
    qa('.proto-banner', host).forEach((b) => b.remove());
    const banners = [];
    if (P.demo.offline) banners.push(`<div class="proto-banner is-amber"><span class="grow"><b>离线 · 本地优先</b> 修改会先保存在本机，联网后自动上传。</span><button type="button" data-proto-action="demo-retry">重试</button></div>`);
    if (P.demo.conflict) banners.push(`<div class="proto-banner is-red"><span class="grow"><b>有 2 项同步冲突</b> 需要选择保留本地、服务器或合并。</span><button type="button" data-proto-action="sync-conflict-open">处理</button></div>`);
    if (P.demo.storageFull) banners.push(`<div class="proto-banner is-amber"><span class="grow"><b>浏览器存储将满</b> 建议导出备份并清空回收站。</span><button type="button" data-proto-action="storage-info">查看</button></div>`);
    if (P.demo.update) banners.push(`<div class="proto-banner"><span class="grow"><b>DaySpark 0.36 已就绪</b> 下一次启动时生效。</span><button type="button" data-proto-action="whats-new">更新内容</button></div>`);
    if (P.demo.saveError) banners.push(`<div class="proto-banner is-red"><span class="grow"><b>演示：保存会失败</b> 下一次保存会保留输入并显示重试。</span><button type="button" data-proto-action="demo-clear-save">关闭</button></div>`);
    if (!banners.length) return;
    const wrap = document.createElement('div');
    wrap.innerHTML = banners.join('');
    const anchor = state.device === 'mobile' ? q('.m-scroll', host) : host;
    if (anchor) anchor.insertBefore(wrap, anchor.firstChild);
  });
  registerAction('demo-retry', () => { P.demo.offline = false; P.data.sync.offline = false; render(); toast('已恢复连接'); });
  registerAction('demo-clear-save', () => { P.demo.saveError = false; render(); });

  /* ---------------- sync conflict resolution ---------------- */
  registerAction('sync-conflict-open', () => {
    const items = [
      { id: 'report', title: '提交周报给林总', local: '标题：提交周报给林总 · 15:15 计划', server: '标题：提交周报 · 18:00 截止' },
      { id: 'dentist', title: '牙医复诊', local: '时间：14:30–15:15', server: '时间：15:00–15:45' },
    ];
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-note">每条单独选择。不会用“全部保留本地”掩盖差异。</div>` + items.map((it, i) => `
      <div class="proto-list-row" style="display:block">
        <b>${esc(it.title)}</b>
        <div class="proto-note" style="margin:4px 0 6px">本地：${esc(it.local)}<br>服务器：${esc(it.server)}</div>
        <div class="proto-seg" data-conflict="${i}">
          <button type="button" data-v="local">保留本地</button>
          <button type="button" data-v="server">用服务器</button>
          <button type="button" data-v="merge">合并</button>
        </div>
      </div>`).join('');
    const picked = {};
    qa('.proto-seg', body).forEach((seg) => seg.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      qa('button', seg).forEach((x) => x.classList.remove('is-on'));
      b.classList.add('is-on');
      picked[seg.dataset.conflict] = b.dataset.v;
    }));
    modal({
      title: '处理同步冲突', wide: true, body,
      actions: [
        { label: '稍后' },
        { label: '应用选择', primary: true, onClick: () => {
          if (Object.keys(picked).length < items.length) { toast('还有冲突没有选择'); return true; }
          P.demo.conflict = false;
          P.data.sync.conflicts = 0;
          P.data.account.lastSync = '刚刚 · 冲突已解决';
          render();
          toast('冲突已按选择处理');
        } },
      ],
    });
  });

  /* ---------------- task context menu ---------------- */
  function closeMenus() { qa('.proto-menu').forEach((m) => m.remove()); }
  document.addEventListener('click', (e) => { if (!e.target.closest('.proto-menu')) closeMenus(); }, true);
  window.addEventListener('scroll', closeMenus, true);

  function taskMenu(row, x, y) {
    const id = row.dataset.id || (row.closest('[data-id]') || {}).dataset?.id;
    const t = id && todoById(id);
    if (!t) return;
    closeMenus();
    const m = document.createElement('div');
    m.className = 'proto-menu';
    const done = isDone(t);
    m.innerHTML = `
      <button type="button" data-m="open">打开详情</button>
      <button type="button" data-m="done">${done ? '取消完成' : '标记完成'}</button>
      <button type="button" data-m="plan">安排时间…</button>
      <button type="button" data-m="tomorrow">顺延到明天</button>
      <button type="button" data-m="cal">移到日历…</button>
      <button type="button" data-m="tag">加标签…</button>
      <div class="sep"></div>
      <button type="button" data-m="copy">复制标题</button>
      <button type="button" data-m="delete" class="danger">删除到回收站</button>`;
    document.body.appendChild(m);
    const rect = m.getBoundingClientRect();
    m.style.left = Math.min(x, innerWidth - rect.width - 8) + 'px';
    m.style.top = Math.min(y, innerHeight - rect.height - 8) + 'px';
    m.addEventListener('click', (e) => {
      const b = e.target.closest('[data-m]'); if (!b) return;
      const act = b.dataset.m;
      closeMenus();
      if (act === 'open') { P.openTodo(t.id); return; }
      if (act === 'done') { if (!state.done) state.done = new Set(); state.done.has(t.id) ? state.done.delete(t.id) : state.done.add(t.id); state.undoId = t.id; render(); return; }
      if (act === 'plan') { state.planTodoId = t.id; state.planReturn = state.screen; P.baseGo('plan-picker'); render(); return; }
      if (act === 'tomorrow') {
        if (t.repeat) { P.openTodo(t.id); toast('重复待办请在详情里改期，避免改动整个系列的锚点'); return; }
        const tomorrow = addDays(TODAY, 1);
        if (t.due) t.due = tomorrow; else t.plan = { date: tomorrow, start: '09:00', end: '09:30' };
        render(); toast('已顺延到明天');
        return;
      }
      if (act === 'cal') {
        choose({
          title: '移到日历', options: calIds().map((id2) => ({ value: id2, label: calOf(id2).name, on: t.cal === id2 })),
          onPick: (v) => { t.cal = v; render(); toast('已移到「' + calOf(v).name + '」'); },
        });
        return;
      }
      if (act === 'tag') {
        if (P.openTagPicker) P.openTagPicker(t.tags || [], (tags) => { t.tags = tags; render(); toast('标签已更新'); });
        return;
      }
      if (act === 'copy') {
        const text = t.title;
        if (navigator.clipboard) navigator.clipboard.writeText(text).catch(() => {});
        toast('已复制标题');
        return;
      }
      if (act === 'delete') {
        if (t.repeat) {
          modal({
            title: '这是「' + t.repeat + '」的重复待办',
            body: '<div class="proto-note">要删除一个实例，还是整个系列？打开详情后可以选择范围。</div>',
            actions: [
              { label: '取消' },
              { label: '打开详情选择范围', primary: true, onClick: () => { P.openTodo(t.id); } },
            ],
          });
          return;
        }
        modal({
          title: '删除「' + t.title + '」？',
          body: '<div class="proto-note">会进回收站，可以恢复，原日历和标签都保留。</div>',
          actions: [
            { label: '取消' },
            { label: '删除', primary: true, danger: true, onClick: () => {
              if (!state.deletedTodos.includes(t.id)) state.deletedTodos.push(t.id);
              state.trashExtra.push({ id: t.id, title: t.title, sub: '待办 · ' + calOf(t.cal).name + ' · 刚刚删除', snap: JSON.parse(JSON.stringify(t)) });
              render(); toast('已删除到回收站');
            } },
          ],
        });
      }
    });
  }

  document.addEventListener('contextmenu', (e) => {
    const row = e.target.closest('.task-row, .tl-block.plan, .cal-block.is-plan');
    if (!row) return;
    e.preventDefault();
    taskMenu(row, e.clientX, e.clientY);
  });

  // Phone: long-press a task row opens the same menu (a visible secondary
  // entry, not a hidden gesture that replaces the row's tap action).
  let longPress = null;
  let suppressLongPressClick = 0;
  document.addEventListener('pointerdown', (e) => {
    if (e.pointerType === 'mouse' || e.button !== 0) return;
    const row = e.target.closest('.task-row');
    if (!row) return;
    const x = e.clientX, y = e.clientY;
    longPress = { row, x, y, fired: false, timer: setTimeout(() => {
      if (!longPress) return;
      longPress.fired = true;
      suppressLongPressClick = Date.now() + 500;
      taskMenu(row, x, y);
    }, 500) };
  }, true);
  document.addEventListener('pointermove', (e) => {
    if (!longPress || longPress.fired) return;
    if (Math.abs(e.clientX - longPress.x) > 8 || Math.abs(e.clientY - longPress.y) > 8) {
      clearTimeout(longPress.timer); longPress = null;
    }
  }, true);
  ['pointerup', 'pointercancel'].forEach((name) => document.addEventListener(name, () => {
    if (!longPress) return;
    if (!longPress.fired) clearTimeout(longPress.timer);
    longPress = null;
  }, true));
  document.addEventListener('click', (e) => {
    if (Date.now() < suppressLongPressClick && e.target.closest('.task-row')) {
      e.preventDefault(); e.stopPropagation();
    }
  }, true);

  /* ---------------- keyboard ---------------- */
  document.addEventListener('keydown', (e) => {
    const tag = (e.target && e.target.tagName || '').toLowerCase();
    const typing = tag === 'input' || tag === 'textarea' || tag === 'select' || (e.target && e.target.isContentEditable);
    if (e.key === 'Escape') {
      const scrim = qa('.proto-modal-scrim').pop();
      if (scrim) { scrim.remove(); e.preventDefault(); return; }
      closeMenus();
    }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === '?') { e.preventDefault(); P.openShortcuts(); return; }
    if (e.key === 'n' || e.key === 'N') { e.preventDefault(); P.baseGo('new-todo'); P.syncHash(true); return; }
    if (e.key === 'e' || e.key === 'E') { e.preventDefault(); P.baseGo('new-event'); P.syncHash(true); return; }
    if (e.key === 't' || e.key === 'T') { e.preventDefault(); state.selectedDate = TODAY; P.baseGo('today'); P.syncHash(true); return; }
    if (['w', 'm', 'd'].includes(e.key.toLowerCase()) && state.screen.startsWith('cal-')) {
      e.preventDefault();
      P.baseGo('cal-' + ({ w: 'week', m: 'month', d: 'day' })[e.key.toLowerCase()]);
      P.syncHash(true);
    }
    if (e.key === '/') { e.preventDefault(); P.baseGo('command'); P.syncHash(true); }
  });

  registerAction('notify-detail', (el) => {
    const label = (el.textContent || '').split('\n')[0].trim();
    const granted = P.data.notify.permission !== 'denied';
    modal({
      title: label || '通知与提醒',
      body: `<div class="proto-list">
        <div class="proto-list-row"><span class="grow">通知权限<small>${granted ? '系统允许 DaySpark 发通知' : '系统已拒绝；提醒仍保存，到点不会弹'}</small></span><span class="proto-badge">${granted ? '已允许' : '已拒绝'}</span></div>
        <div class="proto-list-row"><span class="grow">精确提醒<small>${P.data.notify.exact ? '可以按分钟触发' : '系统只允许粗略时间'}</small></span><span class="proto-badge">${P.data.notify.exact ? '可用' : '受限'}</span></div>
        <div class="proto-list-row"><span class="grow">应用内提醒<small>前台打开时仍会显示</small></span><span class="proto-badge">可用</span></div>
      </div><div class="proto-note">原型只模拟系统权限；真实权限需要在系统设置里改。</div>`,
      actions: [
        { label: '关闭' },
        { label: granted ? '模拟关闭权限' : '打开系统设置', primary: true, onClick: () => {
          if (P.data.notify.permission === 'denied') { P.data.notify.permission = 'granted'; P.data.notify.exact = true; toast('已重新允许通知'); render(); }
          else { P.data.notify.permission = 'denied'; P.data.notify.exact = false; toast('已模拟拒绝通知'); render(); }
        } },
      ],
    });
  });

  /* ---------------- real fallback: read-only facts ---------------- */
  P.fallback = function (el, root) {
    // Explicitly disabled controls stay disabled and say why.
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') {
      el.classList.add('proto-disabled');
      el.dataset.protoAction = 'disabled-info';
      el.dataset.reason = el.dataset.reason || '这一项在当前状态下不可用。';
      return;
    }
    // Design-sample surfaces from the master are not product pages; say so
    // instead of dressing their sample buttons up as real interactions.
    if (typeof SURFACES !== 'undefined' && state.screen in SURFACES) {
      el.dataset.protoAction = 'demo-surface-info';
      el.dataset.demoLabel = (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40);
      return;
    }
    // Read-only facts: show the actual value and let the user copy it.
    el.dataset.protoAction = 'info-detail';
    const row = el.closest('.set-row, .m-settings-row, .field-row');
    const label = row ? rowLabel(row) : '';
    const value = row ? rowValue(row) : (el.textContent || '').replace(/\s+/g, ' ').trim();
    el.dataset.infoLabel = label || (el.getAttribute('aria-label') || '这一项');
    el.dataset.infoValue = value;
  };
  registerAction('demo-surface-info', (el) => {
    modal({
      title: '这是设计样张',
      body: `<div class="proto-note">「${esc(el.dataset.demoLabel || '这一项')}」属于设计母版里的状态样张，用来展示样式和状态；它不对应产品里的真实写入。真实操作请回到今天、待办或日历页面。</div>`,
      actions: [{ label: '知道了', primary: true }],
    });
  });
  registerAction('info-detail', (el) => {
    const label = el.dataset.infoLabel || '这一项';
    const value = el.dataset.infoValue || (el.textContent || '').trim();
    modal({
      title: label,
      body: `<div class="proto-list"><div class="proto-list-row"><span class="grow">${esc(value || '—')}<small>只读事实</small></span></div></div><div class="proto-note">这是当前保存的值。需要修改时，使用同一页面里的编辑入口。</div>`,
      actions: [
        { label: '关闭' },
        { label: '复制', onClick: () => { if (navigator.clipboard) navigator.clipboard.writeText(value).catch(() => {}); toast('已复制'); } },
      ],
    });
  });
  registerAction('disabled-info', (el) => {
    toast(el.dataset.reason || '这一项在当前状态下不可用');
  });
  // Anything the earlier layers marked as the old generic placeholder now
  // goes through the same real read-only/copy path.
  registerAction('info-open', (el) => {
    if (el && !el.dataset.infoValue) {
      const row = el.closest('.set-row, .m-settings-row');
      el.dataset.infoLabel = row ? rowLabel(row) : ((el.textContent || '').trim().slice(0, 40) || '这一项');
      el.dataset.infoValue = row ? rowValue(row) : (el.textContent || '').trim();
    }
    P.actions['info-detail'](el);
  });

  /* Expose helpers for the other v2 modules. */
  P.choose = choose;
  P.applyPrefs = applyPrefs;
  P.esc = esc;
  P.q = q;
  P.qa = qa;
})();
