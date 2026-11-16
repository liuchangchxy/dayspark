/* Settings: appearance, to-dos, data, account & sync, AI, notifications, about. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

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
    return row({ title, subtitle, trailing: sw });
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
      narrow: true,
      build(content) {
        // Appearance
        const appearance = group(t('appearance'));
        appearance.appendChild(row({
          icon: 'sun', title: t('theme'),
          trailing: segmented([['light', t('themeLight')], ['dark', t('themeDark')]], S.state.theme, (v) => { S.state.theme = v; S.applyTheme(); S.savePrefs(); App.render(); }, 'theme'),
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
          trailing: segmented([['zh', t('languageZh')], ['en', t('languageEn')]], S.state.lang, (v) => { S.setLang(v); App.render(); }, 'lang'),
        }));
        appearance.appendChild(row({
          icon: 'bolt', title: t('defaultTab'),
          trailing: segmented([['action', t('today')], ['calendar', t('calendar')], ['todos', t('todos')]], S.state.defaultTab, (v) => { S.state.defaultTab = v; S.savePrefs(); App.render(); }, 'default-tab'),
        }));
        appearance.appendChild(switchRow(S.state.lang === 'zh' ? '显示农历' : 'Show lunar dates', S.state.lang === 'zh' ? '日期标题下显示农历日期。' : 'Show the lunar date under day headings.', S.state.showLunar, (v) => { S.state.showLunar = v; S.savePrefs(); App.render(); }, 'setting-lunar'));
        content.appendChild(anchorGroup(appearance, 'appearance'));

        // Calendars
        const cal = group(t('calendar'));
        cal.appendChild(row({ icon: 'calendar', title: t('manageCalendars'), onClick: () => App.go('calendars') }));
        content.appendChild(anchorGroup(cal, 'calendar'));

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
        content.appendChild(anchorGroup(data, 'data'));

        // Account
        const account = group(t('account'));
        // A bare server field and a password box does not tell anyone what
        // sync is or where their data goes. Say it once, plainly.
        account.appendChild(U.el('p', { class: 'group-desc', text: t('syncDesc') }));
        if (S.state.account.signedIn) {
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
          btns.appendChild(login); btns.appendChild(register);
          form.appendChild(btns);
          account.appendChild(form);
        }
        content.appendChild(anchorGroup(account, 'account'));

        // AI: one top-level group. No Advanced > ExpansionTile > dialog nesting.
        const advanced = group(t('aiAssistant'));
        advanced.appendChild(switchRow(t('aiEnable'), t('aiEnableDesc'), S.state.ai.enabled, (v) => { S.state.ai.enabled = v; App.render(); }, 'setting-ai-enabled'));
        if (S.state.ai.enabled) {
          advanced.appendChild(row({
            icon: 'sparkles', title: t('aiConfig'),
            value: S.state.ai.configured ? `<span class="chip green" style="height:18px">${U.esc(t('aiConfigured', { m: S.state.ai.model }))}</span>` : `<span class="chip amber" style="height:18px">${U.esc(t('aiNotConfigured'))}</span>`,
            onClick: () => aiConfigSheet(),
          }));
          advanced.appendChild(row({ icon: 'sparkles', title: t('pageChat'), onClick: () => App.go('chat') }));
        }
        content.appendChild(anchorGroup(advanced, 'advanced'));

        // Notifications
        const notif = group(t('notifications'));
        notif.appendChild(switchRow(t('systemAlarm'), t('systemAlarmDesc'), S.state.notificationsEnabled, (v) => { S.state.notificationsEnabled = v; S.savePrefs(); App.render(); }, 'setting-alarm'));
        notif.appendChild(row({
          icon: 'bell', title: t('notificationPermission'),
          subtitle: S.state.notificationsEnabled ? t('notificationPermissionDesc') : t('permissionDenied'),
          value: S.state.notificationsEnabled ? `<span class="chip green" style="height:18px">${U.esc(S.state.lang === 'zh' ? '已允许' : 'Allowed')}</span>` : `<span class="chip red" style="height:18px">${U.esc(S.state.lang === 'zh' ? '未允许' : 'Denied')}</span>`,
          onClick: () => UI.toast(t('notificationPermissionAsked'), { warn: true }),
        }));
        notif.appendChild(switchRow(t('exactAlarm'), t('exactAlarmDesc'), S.state.exactAlarm, (v) => { S.state.exactAlarm = v; S.savePrefs(); App.render(); }, 'setting-exact'));
        content.appendChild(anchorGroup(notif, 'notifications'));

        // About
        const about = group('');
        about.appendChild(row({ icon: 'info', title: t('aboutTitle'), value: 'v0.34.0+34', onClick: () => App.go('about') }));
        about.appendChild(row({ icon: 'note', title: t('feedbackTitle'), onClick: () => App.go('feedback') }));
        about.appendChild(row({
          icon: 'layers',
          title: S.state.lang === 'zh' ? '状态与边界' : 'States & edge cases',
          subtitle: S.state.lang === 'zh' ? '加载、空、错误、离线、权限、禁用（原型评审用）' : 'Loading, empty, error, offline, permission, disabled (prototype review)',
          onClick: () => App.go('states'),
        }));
        content.appendChild(anchorGroup(about, 'about'));
      },
    });
    if (section) {
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
    UI.sheet({
      title: t('importTo'),
      subtitle: t('calendarData'),
      body(host, close) {
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
            UI.toast(t('importedResult', { n: 12 }));
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
        const save = U.el('button', { class: 'btn primary', text: t('save') });
        save.addEventListener('click', () => {
          S.state.ai.model = model.value;
          S.state.ai.provider = prov.value;
          S.state.ai.configured = true;
          close(null);
          App.render();
          UI.toast(t('savedToast'));
        });
        const acts = U.el('div', { class: 'input-row', style: 'margin-top:8px' });
        acts.appendChild(test); acts.appendChild(save);
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
