/* DaySpark prototype v2 — calendars, tags, trash, devices, import and backup. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = P.esc;

  function tint(hex) {
    const h = String(hex).replace('#', '');
    const n = parseInt(h.length === 3 ? h.split('').map((x) => x + x).join('') : h, 16);
    const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
    const mix = (c, t) => Math.round(c + (t - c) * 0.86);
    const dark = (c) => Math.round(c * 0.55);
    return {
      bg: '#' + [mix(r, 255), mix(g, 255), mix(b, 255)].map((x) => x.toString(16).padStart(2, '0')).join(''),
      ink: '#' + [dark(r), dark(g), dark(b)].map((x) => x.toString(16).padStart(2, '0')).join(''),
    };
  }

  /* ---------------- calendar colour ---------------- */
  registerEnhancer((root) => {
    if (!state.screen.startsWith('settings-')) return;
    const section = state.screen.replace('settings-', '');
    if (section !== 'calendar-new' && section !== 'calendar-edit') return;
    const swatches = qa('.filter-chip-row .swatch', root);
    swatches.forEach((s) => {
      if (s.dataset.v2) return;
      s.dataset.v2 = '1';
      s.style.cursor = 'pointer';
      s.dataset.color = (s.style.getPropertyValue('--bar') || '').trim();
      s.addEventListener('click', () => {
        swatches.forEach((x) => x.classList.remove('is-on'));
        s.classList.add('is-on');
        P.data.calColorDraft = s.dataset.color;
      });
    });
  });

  registerAction('cal-save', () => {
    const section = state.screen.replace('settings-', '');
    const input = q('.io-card .form-input') || q('.m-form .m-form-input');
    const name = (input && input.value || '').trim();
    if (!name) { toast('先写日历名称'); input && input.focus(); return; }
    const color = P.data.calColorDraft || '#4f7bbf';
    if (section === 'calendar-new') {
      let id = name.toLowerCase().replace(/[^a-z0-9一-龥]+/g, '-').replace(/^-|-$/g, '') || 'calendar';
      const base = id; let n = 2; while (CAL[id]) id = base + '-' + n++;
      const t = tint(color);
      CAL[id] = { name, color, bg: t.bg, ink: t.ink };
      P.data.calColorDraft = '';
      P.baseGo('settings-calendars'); P.syncHash(true);
      toast('已创建日历 · ' + name);
      return;
    }
    const id = state.calendarId;
    if (!id || !CAL[id]) return;
    CAL[id].name = name;
    if (P.data.calColorDraft) {
      const t = tint(P.data.calColorDraft);
      CAL[id].color = P.data.calColorDraft;
      CAL[id].bg = t.bg;
      CAL[id].ink = t.ink;
    }
    P.data.calColorDraft = '';
    P.baseGo('settings-calendars'); P.syncHash(true);
    toast('日历已保存');
  });

  /* ---------------- tag colour + save ---------------- */
  registerEnhancer((root) => {
    if (state.screen !== 'settings-tag-new' && state.screen !== 'settings-tag-edit') return;
    const swatches = qa('.filter-chip-row .swatch', root);
    swatches.forEach((s) => {
      if (s.dataset.v2) return;
      s.dataset.v2 = '1';
      s.style.cursor = 'pointer';
      s.dataset.color = (s.style.getPropertyValue('--bar') || '').trim();
      s.addEventListener('click', () => {
        swatches.forEach((x) => x.classList.remove('is-on'));
        s.classList.add('is-on');
        P.data.tagColorDraft = s.dataset.color;
      });
    });
  });

  registerAction('tag-save', () => {
    const section = state.screen.replace('settings-', '');
    const input = q('.io-card .form-input') || q('.m-form .m-form-input');
    const name = (input && input.value || '').trim();
    if (!name) { state.variant = 'validation'; render(); return; }
    const inUse = P.data.tags.some((t) => t.name === name) ||
      TODOS.concat(state.localTodos || []).some((t) => (t.tags || []).includes(name));
    if (section === 'tag-new') {
      if (inUse) { state.variant = 'duplicate'; render(); toast('标签名已存在'); return; }
      P.data.tags.push({ name, color: P.data.tagColorDraft || '#4f7bbf' });
      P.data.tagColorDraft = '';
      P.baseGo('settings-tags'); P.syncHash(true);
      toast('已创建标签 · ' + name);
      return;
    }
    const old = state.tagId || '周报';
    if (name !== old && inUse) { toast('标签名已存在'); return; }
    const tag = P.data.tags.find((t) => t.name === old);
    if (tag) { tag.name = name; if (P.data.tagColorDraft) tag.color = P.data.tagColorDraft; }
    TODOS.concat(state.localTodos || []).forEach((t) => {
      if (Array.isArray(t.tags)) t.tags = t.tags.map((x) => x === old ? name : x);
    });
    state.tagId = name;
    P.data.tagColorDraft = '';
    P.baseGo('settings-tags'); P.syncHash(true);
    toast('标签已保存');
  });

  /* ---------------- trash: confirm and real restore ---------------- */
  function snapFor(id) {
    const row = (state.trashExtra || []).find((x) => x.id === id);
    return row && row.snap;
  }
  registerEnhancer((root) => {
    if (state.screen !== 'settings-trash' && state.screen !== 'trash-page') return;
    qa('.trash-row', root).forEach((row) => {
      const id = (q('[data-action="trash-restore"]', row) || {}).dataset?.id;
      if (!id) return;
      qa('[data-action="trash-restore"]', row).forEach((b) => { b.dataset.protoAction = 'trash-restore-v2'; b.dataset.id = id; });
      qa('[data-action="trash-delete"]', row).forEach((b) => { b.dataset.protoAction = 'trash-delete-v2'; b.dataset.id = id; });
    });
    qa('[data-action="trash-clear"]', root).forEach((b) => { b.dataset.protoAction = 'trash-clear-v2'; });
  });

  registerAction('trash-restore-v2', (el) => {
    const id = el.dataset.id;
    const snap = snapFor(id);
    state.deletedTodos = (state.deletedTodos || []).filter((x) => x !== id);
    state.deletedEvents = (state.deletedEvents || []).filter((x) => x !== id);
    state.trashExtra = (state.trashExtra || []).filter((x) => x.id !== id);
    if (snap) {
      if (snap.start || snap.startDate) {
        if (!EVENTS.some((e) => e.id === snap.id)) EVENTS.push(snap);
      } else if (!TODOS.some((t) => t.id === snap.id)) {
        TODOS.unshift(snap);
      }
    } else if (id.startsWith('trash-')) {
      const title = (el.closest('.trash-row') && q('.trash-main > div', el.closest('.trash-row')).textContent || '恢复的待办').trim();
      TODOS.unshift({ id: 'restored-' + Date.now(), title, cal: 'personal', priority: 0, tags: [], status: 'open' });
    }
    render(); toast('已恢复 · 回到原来的日历');
  });

  registerAction('trash-delete-v2', (el) => {
    const id = el.dataset.id;
    modal({
      title: '永久删除？',
      body: '<div class="proto-note">不会进回收站，也不能撤销。</div>',
      actions: [
        { label: '取消' },
        { label: '永久删除', primary: true, danger: true, onClick: () => {
          state.trashExtra = (state.trashExtra || []).filter((x) => x.id !== id);
          state.trashRemoved = state.trashRemoved || [];
          if (!state.trashRemoved.includes(id)) state.trashRemoved.push(id);
          render(); toast('已永久删除');
        } },
      ],
    });
  });

  registerAction('trash-clear-v2', () => {
    modal({
      title: '清空回收站？',
      body: '<div class="proto-note">回收站里的所有项目会被永久删除，不能撤销。待办与日程本身也会从本地存储移除。</div>',
      actions: [
        { label: '取消' },
        { label: '清空', primary: true, danger: true, onClick: () => {
          state.deletedTodos = [];
          state.deletedEvents = [];
          state.trashExtra = [];
          state.trashRemoved = ['trash-books', 'trash-template', 'trash-review'];
          render(); toast('回收站已清空');
        } },
      ],
    });
  });

  /* ---------------- devices ---------------- */
  registerAction('devices-open', () => {
    const scrim = modal({ title: '已连接设备', body: '<div class="proto-note">正在读取设备列表…</div>', actions: [{ label: '关闭' }] });
    setTimeout(() => {
      if (!document.body.contains(scrim)) return;
      const body = q('.proto-modal-body', scrim);
      const devices = P.data.account.devices || [];
      body.innerHTML = devices.length ? `<div class="proto-list">${devices.map((d, i) => `<div class="proto-list-row"><span class="grow">${esc(d.name)}<small>${esc(d.meta)}</small></span>${d.current ? '<span class="proto-badge">本机</span>' : `<button type="button" class="proto-btn" data-device="${i}">移除</button>`}</div>`).join('')}</div><div class="proto-note">移除设备会撤销它的同步会话；本机不能被移除。</div>` : '<div class="proto-empty">还没有连接设备。登录并完成一次同步后，这里会出现设备记录。</div>';
      body.addEventListener('click', (e) => {
        const b = e.target.closest('[data-device]'); if (!b) return;
        const i = Number(b.dataset.device);
        const d = devices[i];
        modal({
          title: '移除「' + d.name + '」？',
          body: '<div class="proto-note">它会立即停止同步；本地数据不会被远程清空。</div>',
          actions: [{ label: '取消' }, { label: '移除', primary: true, danger: true, onClick: () => {
            devices.splice(i, 1); render(); toast('已移除设备 · ' + d.name); scrim.remove();
          } }],
        });
      });
    }, 450);
  });

  /* ---------------- ICS import ---------------- */
  function parseICS(text) {
    const lines = text.replace(/\r\n/g, '\n').replace(/\n[ \t]/g, '').split('\n');
    const events = [], todos = [], skipped = [];
    let cur = null, kind = null;
    const dateOf = (v) => {
      const m = /^(\d{4})(\d{2})(\d{2})/.exec(v || '');
      return m ? m[1] + '-' + m[2] + '-' + m[3] : '';
    };
    const timeOf = (v) => {
      const m = /T(\d{2})(\d{2})/.exec(v || '');
      return m ? m[1] + ':' + m[2] : '';
    };
    lines.forEach((raw, idx) => {
      const line = raw.trim();
      if (line === 'BEGIN:VEVENT') { kind = 'event'; cur = {}; return; }
      if (line === 'BEGIN:VTODO') { kind = 'todo'; cur = {}; return; }
      if (line === 'END:VEVENT' || line === 'END:VTODO') {
        if (cur) {
          const summary = (cur.SUMMARY || '').trim();
          const start = cur.DTSTART || cur.DUE || '';
          const day = dateOf(start);
          if (!summary || !day) skipped.push({ line: idx + 1, reason: !summary ? '缺少标题' : '日期无法识别', raw: line });
          else if (kind === 'event') events.push({ title: summary, date: day, endDate: dateOf(cur.DTEND), start: timeOf(start), end: timeOf(cur.DTEND), loc: cur.LOCATION || '', note: cur.DESCRIPTION || '' });
          else todos.push({ title: summary, due: day, dueTime: timeOf(start), note: cur.DESCRIPTION || '' });
        }
        cur = null; kind = null; return;
      }
      if (!cur) return;
      const m = /^([A-Z-]+)(;[^:]*)?:(.*)$/.exec(line);
      if (m) cur[m[1]] = m[3];
    });
    return { events, todos, skipped };
  }

  registerAction('import-pick', () => {
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-note">选择一个 .ics 文件；解析后先预览，不会直接写入。</div>
      <div class="proto-quick-row"><button type="button" class="proto-btn primary" data-pick>选择文件</button><button type="button" class="proto-btn" data-sample>使用示例文件</button></div>`;
    const scrim = modal({ title: '选择 ICS 文件', body, actions: [{ label: '取消' }] });
    const input = document.createElement('input');
    input.type = 'file'; input.accept = '.ics,text/calendar'; input.className = 'proto-hidden-input';
    document.body.appendChild(input);
    function accept(name, text) {
      const parsed = parseICS(text);
      P.data.importParsed = Object.assign({ name }, parsed);
      P.data.importFile = name;
      P.data.importBad = parsed.events.length + parsed.todos.length === 0;
      scrim.remove();
      P.baseGo('settings-import');
      state.variant = 'preview';
      render();
      toast('已解析 ' + name + ' · ' + (parsed.events.length + parsed.todos.length) + ' 项');
    }
    body.addEventListener('click', (e) => {
      if (e.target.closest('[data-pick]')) input.click();
      if (e.target.closest('[data-sample]')) {
        accept('dayplan.ics', 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:设计评审\nDTSTART:20261121T100000\nDTEND:20261121T110000\nLOCATION:会议室 B\nEND:VEVENT\nBEGIN:VEVENT\nSUMMARY:牙医复诊\nDTSTART:20261122T143000\nDTEND:20261122T151500\nEND:VEVENT\nBEGIN:VTODO\nSUMMARY:整理导入后的重复项\nDUE:20261123T180000\nEND:VTODO\nEND:VCALENDAR');
      }
    });
    input.addEventListener('change', () => {
      const f = input.files && input.files[0]; if (!f) return;
      const reader = new FileReader();
      reader.onload = () => accept(f.name, String(reader.result || ''));
      reader.onerror = () => { toast('文件读取失败'); };
      reader.readAsText(f);
    });
  });

  registerAction('import-next', () => {
    const parsed = P.data.importParsed;
    if (!parsed || (!parsed.events.length && !parsed.todos.length)) {
      state.variant = 'error'; render(); toast('没有可导入的内容'); return;
    }
    const cal = P.data.importCalendar || 'work';
    state.variant = 'importing'; render();
    setTimeout(() => {
      parsed.events.forEach((e, i) => {
        EVENTS.push({
          id: 'import-' + Date.now() + '-' + i, title: e.title, cal,
          date: e.date, allDay: !e.start, start: e.start || '', end: e.end || '',
          loc: e.loc || '', note: e.note || '', repeat: '',
        });
      });
      parsed.todos.forEach((t, i) => {
        TODOS.unshift({ id: 'import-todo-' + Date.now() + '-' + i, title: t.title, cal, priority: 0, tags: [], note: t.note || '', status: 'open', due: t.due, dueTime: t.dueTime || '' });
      });
      state.variant = 'success';
      render();
      toast('导入完成 · ' + (parsed.events.length + parsed.todos.length) + ' 项写入');
    }, 800);
  });

  registerAction('import-skip', () => {
    const parsed = P.data.importParsed;
    if (parsed) {
      parsed.skipped = [];
      P.data.importParsed = parsed;
      P.actions['import-next']();
    } else {
      state.variant = 'success'; render(); toast('已跳过无效行');
    }
  });

  registerAction('import-report', () => {
    const p = P.data.importParsed || { name: 'dayplan.ics', events: [], todos: [], skipped: [{ line: 14, reason: '日期无法识别' }] };
    modal({
      title: '导入报告',
      body: `<div class="proto-list"><div class="proto-note">${esc(p.name)} · 目标「${esc(calOf(P.data.importCalendar || 'work').name)}」</div>
        <div class="proto-list-row"><span class="grow">成功写入<small>${p.events.length} 个日程 · ${p.todos.length} 个待办</small></span><span class="proto-badge">${p.events.length + p.todos.length}</span></div>
        ${p.skipped.length ? p.skipped.map((s) => `<div class="proto-list-row"><span class="grow">第 ${s.line} 行<small>${esc(s.reason)}</small></span><span class="proto-badge">跳过</span></div>`).join('') : '<div class="proto-list-row"><span class="grow">没有跳过行</span></div>'}</div>`,
      actions: [{ label: '关闭', primary: true }],
    });
  });

  /* ---------------- backup merge from a real file ---------------- */
  registerAction('backup-merge', () => {
    if (state.screen !== 'settings-backup') { P.baseGo('settings-backup'); }
    const input = document.createElement('input');
    input.type = 'file'; input.accept = '.json,application/json'; input.className = 'proto-hidden-input';
    document.body.appendChild(input);
    input.addEventListener('change', () => {
      const f = input.files && input.files[0]; if (!f) { input.remove(); return; }
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const data = JSON.parse(String(reader.result || '{}'));
          const todos = Array.isArray(data.todos) ? data.todos : [];
          const events = Array.isArray(data.events) ? data.events : [];
          let added = 0;
          todos.forEach((t) => { if (t && t.id && !TODOS.some((x) => x.id === t.id)) { TODOS.unshift(t); added++; } });
          events.forEach((e) => { if (e && e.id && !EVENTS.some((x) => x.id === e.id)) { EVENTS.push(e); added++; } });
          if (data.cal && typeof data.cal === 'object') Object.keys(data.cal).forEach((k) => { if (!CAL[k]) CAL[k] = data.cal[k]; });
          if (Array.isArray(data.data?.tags)) data.data.tags.forEach((t) => { if (!P.data.tags.some((x) => x.name === t.name)) P.data.tags.push(t); });
          state.variant = 'merge-success';
          render();
          toast('备份已合并 · ' + added + ' 项新增');
        } catch (err) {
          state.variant = 'merge-error'; render(); toast('备份文件无法解析');
        }
        input.remove();
      };
      reader.readAsText(f);
    });
    input.click();
  });
})();
