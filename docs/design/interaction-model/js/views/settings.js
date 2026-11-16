/* Settings: appearance, to-dos, data, account & sync, AI, notifications, about. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function platform() {
    const ua = (navigator.userAgent || '');
    if (/Android/i.test(ua)) return 'android';
    if (/iPhone|iPad|iPod/i.test(ua)) return 'ios';
    if (/Mac OS X|Macintosh/i.test(ua)) return 'macos';
    if (/Windows/i.test(ua)) return 'windows';
    if (/Linux/i.test(ua)) return 'linux';
    return 'web';
  }

  function changelogSheet() {
    UI.sheet({
      title: t('changelogTitle'),
      subtitle: 'v0.34.0+34',
      body(host) {
        const zh = S.state.lang === 'zh';
        const items = zh
          ? ['桌面双栏：列表常驻，右侧查看详情', '统一创建入口：待办 / 日程 / 一句话快速添加', '待办支持筛选：日历、标签、优先级', '今日分区：逾期、遗漏、更早、今天完成']
          : ['Desktop split view: the list stays, details open beside it', 'One create entry: to-do, event, or one-line quick add', 'To-do filters: calendar, tag and priority', 'Today separates overdue, missed, earlier and completed'];
        const list = U.el('ul', { class: 'changelog-list' });
        items.forEach((x) => list.appendChild(U.el('li', { text: x })));
        host.appendChild(list);
      },
    });
  }

  function group(title) {
    const g = U.el('div', { class: 'settings-group' });
    if (title) g.appendChild(U.el('h2', { text: title }));
    return g;
  }

  function anchorGroup(node, key) {
    node.dataset.section = key;
    return node;
  }

  function row(opts) {
    const r = U.el(opts.onClick ? 'button' : 'div', { class: 'setting-row' + (opts.danger ? ' danger' : '') });
    if (opts.testid) r.dataset.testid = opts.testid;
    if (opts.icon) {
      const i = U.el('span', { class: 'icon', html: ICON(opts.icon, 16) });
      r.appendChild(i);
    }
    const body = U.el('span', { class: 'body' });
    body.appendChild(U.el('span', { class: 't', text: opts.title }));
    if (opts.subtitle) body.appendChild(U.el('span', { class: 's', text: opts.subtitle }));
    r.appendChild(body);
    if (opts.value !== undefined) r.appendChild(U.el('span', { class: 'value', html: opts.value }));
    if (opts.trailing) r.appendChild(opts.trailing);
    else if (opts.onClick) r.appendChild(U.el('span', { class: 'value', html: ICON('chevronRight', 13) }));
    if (opts.onClick) r.addEventListener('click', opts.onClick);
    return r;
  }

  function switchRow(title, subtitle, on, onToggle, testid) {
    const sw = U.el('button', { class: 'switch' + (on ? ' on' : ''), role: 'switch', 'aria-checked': on ? 'true' : 'false', 'aria-label': title });
    if (testid) sw.dataset.testid = testid;
    sw.addEventListener('click', () => onToggle(!on));
    const r = row({ title, subtitle, trailing: sw });
    // The whole row is the target, not only the 38px switch.
    r.style.cursor = 'pointer';
    r.addEventListener('click', (e) => {
      if (e.target.closest('.switch')) return;
      onToggle(!on);
    });
    return r;
  }

  function segmented(options, value, onChange, testidPrefix) {
    const seg = U.el('div', { class: 'segmented' });
    options.forEach(([val, label]) => {
      const b = U.el('button', { class: val === value ? 'on' : '', text: label, 'aria-pressed': val === value ? 'true' : 'false' });
      if (testidPrefix) b.dataset.testid = testidPrefix + '-' + val;
      b.addEventListener('click', () => onChange(val));
      seg.appendChild(b);
    });
    return seg;
  }

  function renderSettings(params) {
    const section = params && params.section;
    const page = UI.page({
      title: t('pageSettings'),
      onBack: () => App.back(),
      narrow: !(U.isSplit() && !U.isNarrow()),
      build(content) {
        const sections = [];
        function addSection(key, title, node) {
          node.dataset.section = key;
          sections.push({ key, title, node });
        }
        // Appearance
        const appearance = group(t('appearance'));
        appearance.appendChild(row({
          icon: 'sun', title: t('theme'),
          trailing: segmented([['system', t('themeSystem')], ['light', t('themeLight')], ['dark', t('themeDark')]], S.state.theme, (v) => { S.state.theme = v; S.applyTheme(); S.savePrefs(); App.render(); }, 'theme'),
        }));
        const swatchRow = row({ icon: 'star', title: t('themeColor') });
        const sw = U.el('div', { class: 'swatches' });
        [['blue', '#2457d6'], ['green', '#2f7d5a'], ['orange', '#b4530c'], ['violet', '#6d4aa0'], ['rose', '#b4375a']].forEach(([key, color]) => {
          const b = U.el('button', { class: 'swatch' + (S.state.accent === key ? ' on' : ''), 'aria-label': key });
          b.dataset.testid = 'accent-' + key;
          b.style.background = color;
          b.addEventListener('click', () => { S.state.accent = key; S.applyTheme(); S.savePrefs(); App.render(); });
          sw.appendChild(b);
        });
        swatchRow.appendChild(sw);
        appearance.appendChild(swatchRow);
        appearance.appendChild(row({
          icon: 'globe', title: t('language'),
          trailing: segmented([['system', t('languageSystem')], ['zh', t('languageZh')], ['en', t('languageEn')]], S.state.langPref || S.state.lang, (v) => { S.setLang(v); App.render(); }, 'lang'),
        }));
        appearance.appendChild(row({
          icon: 'bolt', title: t('defaultTab'),
          trailing: segmented([['action', t('today')], ['calendar', t('calendar')], ['todos', t('todos')]], S.state.defaultTab, (v) => { S.state.defaultTab = v; S.savePrefs(); App.render(); }, 'default-tab'),
        }));
        appearance.appendChild(switchRow(S.state.lang === 'zh' ? '显示农历' : 'Show lunar dates', S.state.lang === 'zh' ? '日期标题下显示农历日期。' : 'Show the lunar date under day headings.', S.state.showLunar, (v) => { S.state.showLunar = v; S.savePrefs(); App.render(); }, 'setting-lunar'));
        addSection('appearance', t('appearance'), appearance);

        // Calendars
        const cal = group(t('calendar'));
        cal.appendChild(row({ icon: 'calendar', title: t('manageCalendars'), onClick: () => App.go('calendars') }));
        addSection('calendar', t('calendar'), cal);

        // Data, split by the job: exchange with other calendar apps vs. keep
        // this install recoverable.
        const data = group(t('data'));
        data.appendChild(U.el('div', { class: 'group-label', text: t('dataExchange') }));
        data.appendChild(row({
          icon: 'upload', title: t('importIcs'), subtitle: t('calendarData'),
          onClick: () => importFlow(),
        }));
        data.appendChild(row({ icon: 'download', title: t('exportAllCalendars'), onClick: () => exportFlow() }));
        data.appendChild(U.el('div', { class: 'group-label', text: t('dataBackup') }));
        data.appendChild(row({ icon: 'archive', title: t('fullBackup'), subtitle: t('fullBackupDesc'), onClick: () => backupFlow() }));
        addSection('data', t('data'), data);

        // Account
        const account = group(t('account'));
        // A bare server field and a password box does not tell anyone what
        // sync is or where their data goes. Say it once, plainly.
        account.appendChild(U.el('p', { class: 'group-desc', text: t('syncDesc') }));
        if (S.state.account.signedIn) {
          if (S.state.account.loadError) {
            const err = row({
              icon: 'refresh', title: t('accountLoadFailed'), subtitle: t('errorBody'), danger: true,
              onClick: () => { S.state.account.loadError = false; App.render(); UI.toast(t('syncPhaseIdle')); },
            });
            err.dataset.testid = 'account-retry';
            account.appendChild(err);
          } else {
          account.appendChild(row({
            icon: 'globe', title: t('serverUrl'), value: S.state.account.server || '',
          }));
          account.appendChild(row({
            icon: 'user', title: S.state.account.email,
            subtitle: S.state.offline ? t('offlineBanner') : t('syncPhaseIdle') + (S.state.account.lastSync ? ' · ' + t('lastSync', { t: U.fmtMonthDayTime(S.state.account.lastSync) }) : ''),
            value: '',
          }));
          const syncRow = row({ icon: 'refresh', title: t('syncNow'), onClick: () => syncNow() });
          syncRow.dataset.testid = 'settings-sync';
          account.appendChild(syncRow);
          account.appendChild(row({ icon: 'layers', title: t('connectedDevices'), value: '2', onClick: () => devicesSheet() }));
          account.appendChild(row({
            icon: 'logout', title: t('logout'), danger: true, onClick: () => {
              UI.confirm({ title: t('logout'), message: t('signOutBody'), danger: true, confirmText: t('logout') }).then((ok) => {
                if (!ok) return;
                S.state.account = { signedIn: false, email: null, server: null, lastSync: null, phase: 'idle', rejected: [] };
                App.render();
              });
            },
          }));
          }
        } else {
          const form = U.el('div', { style: 'padding:12px 14px' });
          const fields = {};
          [['server', t('serverUrl'), 'https://nas.local:8080'], ['email', t('email'), 'you@example.com'], ['password', t('password'), '••••••••']].forEach(([key, label, ph]) => {
            const f = U.el('div', { class: 'field', style: 'margin-bottom:10px' });
            f.innerHTML = `<label>${U.esc(label)}</label>`;
            const input = U.el('input', { class: 'input', type: key === 'password' ? 'password' : 'text', placeholder: ph });
            input.dataset.testid = 'auth-' + key;
            f.appendChild(input);
            fields[key] = input;
            form.appendChild(f);
          });
          const err = U.el('div', { class: 'field-error', style: 'margin-bottom:8px' });
          form.appendChild(err);
          const btns = U.el('div', { class: 'input-row' });
          const login = U.el('button', { class: 'btn primary', text: t('login'), style: 'flex:1' });
          login.dataset.testid = 'auth-login';
          const register = U.el('button', { class: 'btn ghost', text: t('register'), style: 'flex:1' });
          function submit(kind) {
            err.textContent = '';
            const server = fields.server.value.trim();
            const email = fields.email.value.trim();
            const password = fields.password.value;
            if (!/^https?:\/\/.+/.test(server)) { err.textContent = t('serverUrlInvalid'); return; }
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { err.textContent = t('invalidCredentials'); return; }
            if (password.length < 8) { err.textContent = t('passwordTooShort'); return; }
            login.disabled = register.disabled = true;
            login.textContent = t('loading');
            setTimeout(() => {
              login.disabled = register.disabled = false;
              login.textContent = t('login');
              S.state.account = { signedIn: true, email, server, lastSync: U.now(), phase: 'idle', rejected: [] };
              S.state.offline = false;
              App.render();
              UI.toast(t('syncPhaseIdle'));
            }, 900);
          }
          login.addEventListener('click', () => submit('login'));
          register.addEventListener('click', () => submit('register'));
          form.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && e.target.tagName === 'INPUT') { e.preventDefault(); submit('login'); }
          });
          btns.appendChild(login); btns.appendChild(register);
          form.appendChild(btns);
          account.appendChild(form);
        }
        addSection('account', t('account'), account);

        // AI: one top-level group. No Advanced > ExpansionTile > dialog nesting.
        const advanced = group(t('aiAssistant'));
        advanced.appendChild(switchRow(t('aiEnable'), t('aiEnableDesc'), S.state.ai.enabled, (v) => { S.state.ai.enabled = v; App.render(); }, 'setting-ai-enabled'));
        if (S.state.ai.enabled) {
          advanced.appendChild(row({
            icon: 'sparkles', title: t('aiConfig'),
            value: S.state.ai.configured ? `<span class="chip green" style="height:18px">${U.esc(t('aiConfigured', { m: S.state.ai.model }))}</span>` : `<span class="chip amber" style="height:18px">${U.esc(t('aiNotConfigured'))}</span>`,
            onClick: () => aiConfigSheet(),
          }));
          advanced.appendChild(row({ icon: 'note', title: t('aiTutorial'), onClick: () => UI.toast(S.state.lang === 'zh' ? '把服务商的 Key 填进「AI 配置」；只保存在本机。' : 'Paste your provider key into AI configuration; it stays on this device.') }));
          // Opening the assistant is only meaningful once it is both enabled and
          // configured; a disabled row says why instead of opening an empty page.
          const openRow = row({
            icon: 'sparkles', title: t('openAssistant'),
            subtitle: S.state.ai.configured ? null : t('aiNotConfigured'),
            onClick: () => { if (S.state.ai.configured) App.go('chat'); else UI.toast(t('aiNoKey'), { warn: true }); },
          });
          if (!S.state.ai.configured) openRow.classList.add('is-disabled');
          advanced.appendChild(openRow);
        }
        addSection('advanced', t('aiAssistant'), advanced);

        // Platform-gated, not a wall of switches no one can act on: alarm
        // settings only exist where the platform has an alarm channel.
        const notif = group(t('notifications'));
        const plat = platform();
        notif.appendChild(U.el('p', { class: 'group-desc', text: t('platformLabel') + ' · ' + plat }));
        if (plat === 'android' || plat === 'ios') {
          notif.appendChild(switchRow(t('systemAlarm'), t('systemAlarmDesc'), S.state.notificationsEnabled, (v) => { S.state.notificationsEnabled = v; S.savePrefs(); App.render(); }, 'setting-alarm'));
        }
        notif.appendChild(row({
          icon: 'bell', title: t('notificationPermission'),
          subtitle: S.state.notificationsEnabled ? t('notificationPermissionDesc') : t('permissionDenied'),
          value: S.state.notificationsEnabled ? `<span class="chip green" style="height:18px">${U.esc(S.state.lang === 'zh' ? '已允许' : 'Allowed')}</span>` : `<span class="chip red" style="height:18px">${U.esc(S.state.lang === 'zh' ? '未允许' : 'Denied')}</span>`,
          onClick: () => UI.toast(t('notificationPermissionAsked'), { warn: true }),
        }));
        if (plat === 'android') {
          notif.appendChild(switchRow(t('exactAlarm'), t('exactAlarmDesc'), S.state.exactAlarm, (v) => { S.state.exactAlarm = v; S.savePrefs(); App.render(); }, 'setting-exact'));
        }
        if (plat === 'web') {
          notif.appendChild(U.el('div', { class: 'field-hint', text: t('unsupportedWeb') }));
        }
        addSection('notifications', t('notifications'), notif);

        // About
        const about = group('');
        about.appendChild(row({ icon: 'info', title: t('aboutTitle'), value: 'v0.34.0+34', onClick: () => App.go('about') }));
        about.appendChild(row({ icon: 'note', title: t('changelog'), onClick: () => changelogSheet() }));
        about.appendChild(row({ icon: 'note', title: t('feedbackTitle'), onClick: () => App.go('feedback') }));
        about.appendChild(row({
          icon: 'layers',
          title: S.state.lang === 'zh' ? '状态与边界' : 'States & edge cases',
          subtitle: S.state.lang === 'zh' ? '加载、空、错误、离线、权限、禁用（原型评审用）' : 'Loading, empty, error, offline, permission, disabled (prototype review)',
          onClick: () => App.go('states'),
        }));
        addSection('about', t('aboutTitle'), about);

        // Wide desktops get the same persistent list + content split the Todo
        // destination uses. A single long scroll makes a section jump a hunt.
        if (U.isSplit() && !U.isNarrow()) {
          const split = U.el('div', { class: 'settings-split', 'data-testid': 'settings-split' });
          const nav = U.el('div', { class: 'settings-nav' });
          const pane = U.el('div', { class: 'settings-pane' });
          let active = sections.some((x) => x.key === S.state.settingsSection)
            ? S.state.settingsSection
            : sections[0].key;
          // The route's section is an entry point, not a pin: once the user
          // picks another section, a re-render must not drag them back.
          if (section && sections.some((x) => x.key === section)
              && (!S.state.settingsRouteApplied || S.state.settingsRouteApplied !== section)) {
            active = section;
            S.state.settingsSection = section;
            S.state.settingsRouteApplied = section;
          }
          function show(key) {
            active = key;
            S.state.settingsSection = key;
            nav.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.section === key));
            pane.innerHTML = '';
            const sec = sections.find((x) => x.key === key);
            if (sec) {
              const anchor = U.el('div');
              anchor.appendChild(sec.node);
              pane.appendChild(anchor);
            }
          }
          sections.forEach((sec) => {
            const b = U.el('button', { class: 'settings-nav-item', 'data-testid': 'settings-nav-' + sec.key, text: sec.title });
            b.dataset.section = sec.key;
            b.addEventListener('click', () => show(sec.key));
            nav.appendChild(b);
          });
          split.appendChild(nav);
          split.appendChild(pane);
          content.appendChild(split);
          show(active);
        } else {
          sections.forEach((sec) => content.appendChild(sec.node));
        }
      },
    });
    if (section && !(U.isSplit() && !U.isNarrow())) {
      const target = page.querySelector('[data-section="' + section + '"]');
      if (target) setTimeout(() => target.scrollIntoView({ block: 'start' }), 40);
    }
    return page;
  }

  function syncNow() {
    if (S.state.offline) { UI.toast(t('offlineBanner'), { warn: true }); return; }
    S.state.account.phase = 'pulling';
    App.render();
    UI.toast(t('syncing'));
    setTimeout(() => {
      S.state.account.phase = 'idle';
      S.state.account.lastSync = U.now();
      App.render();
      UI.toast(t('syncPhaseIdle'));
    }, 1100);
  }

  function devicesSheet() {
    UI.sheet({
      title: t('connectedDevices'),
      body(host) {
        [
          { name: 'MacBook Pro', last: S.state.lang === 'zh' ? '刚刚' : 'just now', current: true },
          { name: 'iPhone 15', last: S.state.lang === 'zh' ? '12 分钟前' : '12 min ago' },
        ].forEach((d) => {
          const r = U.el('div', { class: 'list-row' });
          r.innerHTML = `<span class="icon">${ICON('user', 16)}</span><span class="main"><span class="t">${U.esc(d.name)}${d.current ? ' · ' + U.esc(S.state.lang === 'zh' ? '本机' : 'this device') : ''}</span><span class="s">${U.esc(d.last)}</span></span>`;
          host.appendChild(r);
        });
      },
    });
  }

  function importFlow() {
    let target = S.state.calendars[0] ? S.state.calendars[0].id : null;
    UI.sheet({
      title: t('importTo'),
      subtitle: t('calendarData'),
      body(host, close) {
        host.appendChild(U.el('div', { class: 'field-label', text: t('importTarget') }));
        const calRow = U.el('div', { class: 'chip-row', 'data-testid': 'import-calendars' });
        S.state.calendars.forEach((c) => {
          const b = U.el('button', { class: 'chip-btn' + (target === c.id ? ' on' : '') });
          b.dataset.testid = 'import-calendar-' + c.id;
          b.innerHTML = `<span class="dot" style="background:${c.color}"></span>${U.esc(c.name)}`;
          b.addEventListener('click', () => {
            target = c.id;
            calRow.querySelectorAll('button').forEach((x) => x.classList.remove('on'));
            b.classList.add('on');
          });
          calRow.appendChild(b);
        });
        host.appendChild(calRow);
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.ics,text/calendar';
        const zone = U.el('div', { class: 'input-row' });
        const pick = U.el('button', { class: 'btn ghost', text: S.state.lang === 'zh' ? '选择 .ics 文件' : 'Choose a .ics file' });
        const name = U.el('span', { class: 'tiny muted', text: S.state.lang === 'zh' ? '未选择' : 'None' });
        pick.addEventListener('click', () => input.click());
        input.addEventListener('change', () => { name.textContent = input.files && input.files[0] ? input.files[0].name : (S.state.lang === 'zh' ? '未选择' : 'None'); });
        zone.appendChild(pick); zone.appendChild(name);
        host.appendChild(zone);
        host.appendChild(U.el('div', { class: 'field-hint', style: 'margin:8px 0', text: S.state.lang === 'zh' ? '导入的重复项若无可靠时区，会保留为待确认的旧数据。' : 'Repeating items without a reliable time zone are kept for confirmation.' }));
        const btn = U.el('button', { class: 'btn primary', text: t('import') });
        btn.addEventListener('click', () => {
          btn.disabled = true; btn.textContent = t('loading');
          setTimeout(() => {
            btn.disabled = false; btn.textContent = t('import');
            close(null);
            const cal = S.calendarById(target);
            UI.toast(t('importedResult', { n: 12 }) + (cal ? ' · ' + cal.name : ''));
          }, 900);
        });
        host.appendChild(btn);
      },
    });
  }

  function exportFlow() {
    UI.sheet({
      title: t('exportAllCalendars'),
      body(host, close) {
        const btn = U.el('button', { class: 'btn primary', text: t('export') });
        btn.addEventListener('click', () => {
          btn.disabled = true; btn.textContent = t('loading');
          setTimeout(() => {
            btn.disabled = false; btn.textContent = t('export');
            close(null);
            UI.toast(t('exportedTo', { p: 'dayspark.ics' }) || t('export'));
          }, 800);
        });
        host.appendChild(btn);
        host.appendChild(U.el('div', { class: 'field-hint', style: 'margin-top:8px', text: S.state.lang === 'zh' ? '网页版会直接触发浏览器下载。' : 'On the web build this triggers a browser download.' }));
      },
    });
  }

  function backupFlow() {
    UI.sheet({
      title: t('fullBackup'),
      subtitle: t('fullBackupDesc'),
      body(host, close) {
        const a = U.el('button', { class: 'slot-sheet-option' });
        a.innerHTML = `<span class="ico">${ICON('download', 17)}</span><span><span class="t">${U.esc(t('export'))}</span><br><span class="s">${U.esc(t('fullBackupDesc'))}</span></span>`;
        a.addEventListener('click', () => { close(null); UI.toast(t('exportedTo', { p: 'dayspark-backup.zip' })); });
        host.appendChild(a);
        const b = U.el('button', { class: 'slot-sheet-option' });
        b.innerHTML = `<span class="ico">${ICON('upload', 17)}</span><span><span class="t">${U.esc(t('mergeBackup'))}</span><br><span class="s">${U.esc(S.state.lang === 'zh' ? '把备份内容合并到当前数据' : 'Merge a backup into current data')}</span></span>`;
        b.addEventListener('click', () => { close(null); UI.toast(t('backupRestored')); });
        host.appendChild(b);
      },
    });
  }

  function aiConfigSheet() {
    UI.sheet({
      title: t('aiConfig'),
      body(host, close) {
        const box = U.el('div', { class: 'picker' });
        const prov = U.el('select', { class: 'select' });
        ['OpenAI', 'Anthropic', 'DeepSeek', 'Gemini', t('providerCustom')].forEach((p) => prov.appendChild(U.el('option', { text: p })));
        prov.value = S.state.ai.provider === 'OpenAI' ? 'OpenAI' : S.state.ai.provider;
        box.appendChild(rowLabeled(t('aiProvider'), prov));
        const base = U.el('input', { class: 'input', value: 'https://api.openai.com/v1' });
        box.appendChild(rowLabeled(t('aiBaseUrl'), base));
        const key = U.el('input', { class: 'input', type: 'password', value: '••••••••••••' });
        box.appendChild(rowLabeled(t('aiApiKey'), key));
        const model = U.el('input', { class: 'input', value: S.state.ai.model });
        model.dataset.testid = 'ai-model';
        box.appendChild(rowLabeled(t('aiModel'), model));
        const test = U.el('button', { class: 'btn ghost', text: t('aiTest') });
        test.addEventListener('click', () => {
          test.disabled = true; test.textContent = t('loading');
          setTimeout(() => {
            test.disabled = false; test.textContent = t('aiTest');
            UI.toast(t('aiTestOk'));
          }, 800);
        });
        const detect = U.el('button', { class: 'btn ghost', text: t('detectModels'), 'data-testid': 'ai-detect' });
        detect.addEventListener('click', () => {
          detect.disabled = true; detect.textContent = t('loading');
          setTimeout(() => {
            detect.disabled = false; detect.textContent = t('detectModels');
            // A detected list, not a single answer: the user chooses what the
            // key actually has access to.
            const found = ['gpt-4o-mini', 'gpt-4o', 'claude-sonnet-5-5', 'deepseek-chat'];
            UI.sheet({
              title: t('detectModels'),
              body(host, close) {
                const list = U.el('div', { class: 'picker' });
                found.forEach((name) => {
                  const b = U.el('button', { class: 'slot-sheet-option', 'data-testid': 'ai-model-option' });
                  b.innerHTML = `<span class="t">${U.esc(name)}</span>`;
                  b.addEventListener('click', () => {
                    model.value = name;
                    close(null);
                    UI.toast(t('aiModelChosen', { m: name }));
                  });
                  list.appendChild(b);
                });
                host.appendChild(list);
              },
            });
          }, 700);
        });
        const remove = U.el('button', { class: 'btn danger-ghost', text: t('removeConfig'), 'data-testid': 'ai-remove' });
        remove.addEventListener('click', () => {
          UI.confirm({ title: t('removeConfig'), message: t('aiRemoveConfirm'), danger: true, confirmText: t('remove') }).then((ok) => {
            if (!ok) return;
            S.state.ai.configured = false;
            close(null);
            App.render();
          });
        });
        const save = U.el('button', { class: 'btn primary', text: t('save') });
        box.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && e.target.tagName === 'INPUT') {
            e.preventDefault();
            save.click();
          }
        });
        save.addEventListener('click', () => {
          S.state.ai.model = model.value;
          S.state.ai.provider = prov.value;
          S.state.ai.configured = true;
          close(null);
          App.render();
          UI.toast(t('savedToast'));
        });
        const acts = U.el('div', { class: 'input-row', style: 'margin-top:8px' });
        acts.appendChild(test); acts.appendChild(detect); acts.appendChild(remove); acts.appendChild(save);
        box.appendChild(acts);
        host.appendChild(box);
      },
    });
  }

  function rowLabeled(label, control) {
    const r = U.el('div', { class: 'field' });
    r.innerHTML = `<label>${U.esc(label)}</label>`;
    r.appendChild(control);
    return r;
  }

  App.defineView('settings', renderSettings);
})();
