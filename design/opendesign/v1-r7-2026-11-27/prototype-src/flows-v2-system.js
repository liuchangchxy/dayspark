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
        const token = section === 'calendar-new' ? 'new' : (state.calendarId || '');
        setColorDraft('cal', token, s.dataset.color);
      });
    });
  });

  registerAction('cal-save', () => {
    const section = state.screen.replace('settings-', '');
    const input = q('.io-card .form-input') || q('.m-form .m-form-input');
    const name = (input && input.value || '').trim();
    if (!name) { toast('先写日历名称'); input && input.focus(); return; }
    const token = section === 'calendar-new' ? 'new' : (state.calendarId || '');
    const color = colorDraft('cal', token) || '#4f7bbf';
    if (section === 'calendar-new') {
      let id = name.toLowerCase().replace(/[^a-z0-9一-龥]+/g, '-').replace(/^-|-$/g, '') || 'calendar';
      const base = id; let n = 2; while (CAL[id]) id = base + '-' + n++;
      const t = tint(color);
      CAL[id] = { name, color, bg: t.bg, ink: t.ink };
      clearColorDraft();
      P.baseGo('settings-calendars'); P.syncHash(true);
      toast('已创建日历 · ' + name);
      return;
    }
    const id = state.calendarId;
    if (!id || !CAL[id]) return;
    CAL[id].name = name;
    if (colorDraft('cal', id)) {
      const t = tint(colorDraft('cal', id));
      CAL[id].color = colorDraft('cal', id);
      CAL[id].bg = t.bg;
      CAL[id].ink = t.ink;
    }
    clearColorDraft();
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
        const token = state.screen === 'settings-tag-new' ? 'new' : (state.tagId || '');
        setColorDraft('tag', token, s.dataset.color);
      });
    });
  });

  function colorDraft(kind, token) {
    const d = P.data;
    if (!d || d.colorFor !== kind + '|' + token || !d.colorDraft) return '';
    return d.colorDraft;
  }
  P.colorDraft = colorDraft;
  function setColorDraft(kind, token, color) {
    P.data.colorFor = kind + '|' + token;
    P.data.colorDraft = color;
  }
  function clearColorDraft() { P.data.colorFor = ''; P.data.colorDraft = ''; }
  registerAction('tag-cancel', () => { clearColorDraft(); P.baseGo('settings-tags'); P.syncHash(true); });
  registerAction('cal-cancel', () => { clearColorDraft(); P.baseGo('settings-calendars'); P.syncHash(true); });

  registerAction('tag-save', () => {
    const section = state.screen.replace('settings-', '');
    const input = q('.io-card .form-input') || q('.m-form .m-form-input');
    const name = (input && input.value || '').trim();
    if (!name) { state.variant = 'validation'; render(); return; }
    const inUse = P.data.tags.some((t) => t.name === name) ||
      TODOS.concat(state.localTodos || []).some((t) => (t.tags || []).includes(name));
    if (section === 'tag-new') {
      if (inUse) { state.variant = 'duplicate'; render(); toast('标签名已存在'); return; }
      P.data.tags.push({ name, color: colorDraft('tag', 'new') || '#4f7bbf' });
      clearColorDraft();
      P.baseGo('settings-tags'); P.syncHash(true);
      toast('已创建标签 · ' + name);
      return;
    }
    const old = state.tagId || '周报';
    if (name !== old && inUse) { toast('标签名已存在'); return; }
    const tag = P.data.tags.find((t) => t.name === old);
    const picked = colorDraft('tag', old);
    if (tag) { tag.name = name; if (picked) tag.color = picked; }
    TODOS.concat(state.localTodos || []).forEach((t) => {
      if (Array.isArray(t.tags)) t.tags = t.tags.map((x) => x === old ? name : x);
    });
    state.tagId = name;
    clearColorDraft();
    P.baseGo('settings-tags'); P.syncHash(true);
    toast('标签已保存');
  });

  registerAction('tag-delete', () => {
    const old = state.tagId || '周报';
    const used = TODOS.concat(state.localTodos || []).filter((t) => (t.tags || []).includes(old)).length + allTodos().filter((t) => (t.tags || []).includes(old)).length;
    modal({
      title: '删除标签',
      body: `<div class="proto-note">「${esc(old)}」会从 ${used} 条待办上移除，但不会删除待办本身。这个操作不能撤销。</div>`,
      actions: [
        { label: '取消' },
        { label: '删除标签', primary: true, danger: true, onClick: () => {
          P.data.tags = P.data.tags.filter((t) => t.name !== old);
          const strip = (t) => { if (Array.isArray(t.tags)) t.tags = t.tags.filter((x) => x !== old); };
          TODOS.forEach(strip); (state.localTodos || []).forEach(strip); allTodos().forEach(strip);
          clearColorDraft();
          P.baseGo('settings-tags'); P.syncHash(true);
          toast('已删除标签 · ' + old + ' · 条目本身保留');
        } },
      ],
    });
  });

  /* ---------------- trash: confirm and real restore ---------------- */
  function snapFor(id) {
    const row = (state.trashExtra || []).find((x) => x.id === id);
    if (row && row.snap) return row.snap;
    const base = (typeof trashItems === 'function' ? trashItems() : []).find((x) => x.id === id);
    return base && base.snap;
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
    if (!snap) {
      // No snapshot: never rebuild from the title. Say what actually happens.
      modal({
        title: '这一项没有可恢复的原件',
        body: '<div class="proto-note">这条记录是在设计状态里预置的示例，没有保存原日历、标签和字段。恢复会创建一条只有标题的待办，并放进默认日历。</div>',
        actions: [
          { label: '取消' },
          { label: '仍然恢复为纯标题', onClick: () => {
            const row = el.closest('.trash-row, .m-settings-row');
            const title = (q('.trash-main > div', row) || q('span', row) || {}).textContent || '恢复的待办';
            const keep = state.trashExtra.filter((x) => x.id === id);
            state.deletedTodos = state.deletedTodos.filter((x) => x !== id);
            state.deletedEvents = state.deletedEvents.filter((x) => x !== id);
            state.trashExtra = state.trashExtra.filter((x) => x.id !== id);
            if (!keep.length && id.startsWith('trash-')) {
              state.trashRemoved = state.trashRemoved || [];
              if (!state.trashRemoved.includes(id)) state.trashRemoved.push(id);
            }
            TODOS.unshift({ id: 'restored-' + Date.now(), title: title.trim(), cal: state.defaultCal || 'personal', priority: 0, tags: [], status: 'open' });
            render(); toast('已恢复为纯标题 · ' + calOf(state.defaultCal || 'personal').name);
          } },
        ],
      });
      return;
    }
    state.deletedTodos = (state.deletedTodos || []).filter((x) => x !== id);
    state.deletedEvents = (state.deletedEvents || []).filter((x) => x !== id);
    state.trashExtra = (state.trashExtra || []).filter((x) => x.id !== id);
    const isEvent = !!(snap.start || snap.startDate || snap.allDay && snap.date && !snap.status);
    const list = isEvent ? EVENTS : TODOS;
    const copy = JSON.parse(JSON.stringify(snap));
    const existing = list.find((x) => x.id === copy.id);
    if (existing) {
      Object.keys(existing).forEach((k) => { delete existing[k]; });
      Object.assign(existing, copy);
    } else if (isEvent) {
      EVENTS.push(copy);
    } else {
      TODOS.unshift(copy);
    }
    state.skipped = (state.skipped || []).filter((k) => !k.startsWith(snap.id + '@'));
    const backTo = snap.cal ? calOf(snap.cal).name : '原日历';
    state.drawer = isEvent ? { type: 'event', id: snap.id } : { type: 'todo', id: snap.id };
    state.drawerEdit = false;
    render();
    toast('已恢复 · 回到「' + backTo + '」· 原字段保留');
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
    let cur = null, kind = null, startLine = 0;
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
      if (line === 'BEGIN:VEVENT') { kind = 'event'; cur = {}; startLine = idx + 1; return; }
      if (line === 'BEGIN:VTODO') { kind = 'todo'; cur = {}; startLine = idx + 1; return; }
      if (line === 'END:VEVENT' || line === 'END:VTODO') {
        if (cur) {
          const summary = (cur.SUMMARY || '').trim();
          const start = cur.DTSTART || cur.DUE || '';
          const day = dateOf(start);
          if (!summary || !day) skipped.push({ line: startLine, reason: !summary ? '缺少标题（SUMMARY 为空）' : '日期无法识别', raw: summary ? line.replace(/\s+/g, ' ').trim() : 'BEGIN:' + (kind === 'event' ? 'VEVENT' : 'VTODO') });
          else if (kind === 'event') events.push({ line: idx + 1, uid: (cur.UID || '').trim(), title: summary, date: day, endDate: dateOf(cur.DTEND), start: timeOf(start), end: timeOf(cur.DTEND), allDay: !timeOf(start), loc: cur.LOCATION || '', note: cur.DESCRIPTION || '', repeat: '', rrule: cur.RRULE || '' });
          else todos.push({ line: idx + 1, uid: (cur.UID || '').trim(), title: summary, due: day, dueTime: timeOf(start), note: cur.DESCRIPTION || '', rrule: cur.RRULE || '' });
        }
        cur = null; kind = null; return;
      }
      if (!cur) return;
      const m = /^([A-Z-]+)(;[^:]*)?:(.*)$/.exec(line);
      if (m) cur[m[1]] = m[3].replace(/\\n/gi, '\n').replace(/\\,/g, ',').replace(/\\;/g, ';').replace(/\\\\/g, '\\');
    });
    return { events, todos, skipped };
  }

  const WD_CODE = { MO: '一', TU: '二', WE: '三', TH: '四', FR: '五', SA: '六', SU: '日' };
  function parseRRule(v) {
    const out = { repeat: '', repeatUntil: '', repeatCount: 0, repeatEnd: '永不结束', warning: '' };
    if (!v) return out;
    const kv = {};
    String(v).split(';').forEach((p) => { const i = p.indexOf('='); if (i > 0) kv[p.slice(0, i).toUpperCase()] = p.slice(i + 1); });
    const freq = kv.FREQ || '';
    const interval = Math.max(1, Math.min(99, Number(kv.INTERVAL || 1)));
    // Any INTERVAL is representable: 每 N 天 / 每 N 周 / 每 N 月 / 每 N 年.
    // Flutter's repeat editor accepts arbitrary INTERVAL, so an imported
    // "每 3 周" must not fall back to 不重复.
    const WD_LIST = (kv.BYDAY || '').split(',').map((x) => WD_CODE[x.replace(/^\d+/, '')]).filter(Boolean);
    const rule = (unit) => {
      const base = { day: '每天', week: '每周', month: '每月', year: '每年' }[unit];
      return interval === 1 ? base : '每 ' + interval + ' ' + { day: '天', week: '周', month: '月', year: '年' }[unit];
    };
    if (freq === 'DAILY') out.repeat = rule('day');
    else if (freq === 'WEEKLY') out.repeat = rule('week') + (WD_LIST.length ? WD_LIST.join('、') : '');
    else if (freq === 'MONTHLY') out.repeat = rule('month');
    else if (freq === 'YEARLY') out.repeat = rule('year');
    if (!out.repeat) out.warning = '不支持的重复规则（' + v + '），按不重复导入';
    const um = /^(\d{4})(\d{2})(\d{2})/.exec(kv.UNTIL || '');
    if (um) out.repeatUntil = um[1] + '-' + um[2] + '-' + um[3];
    out.repeatCount = Number(kv.COUNT || 0);
    out.repeatEnd = out.repeatCount ? '在次数' : out.repeatUntil ? '在日期' : '永不结束';
    return out;
  }
  function plusMinutes(t, n) {
    const a = String(t || '09:00').split(':').map(Number);
    const m = Math.min(1439, a[0] * 60 + a[1] + n);
    return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0');
  }

  // Expose the real importer so the export can be verified by re-parsing it.
  P.parseICS = parseICS;
  P.parseRRule = parseRRule;

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
        accept('dayplan.ics', `BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:设计评审
DTSTART:20261121T100000
DTEND:20261121T110000
LOCATION:会议室 B
END:VEVENT
BEGIN:VEVENT
SUMMARY:每周站会
DTSTART:20261123T093000
DTEND:20261123T100000
RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6
END:VEVENT
BEGIN:VEVENT
SUMMARY:设计冲刺
DTSTART;VALUE=DATE:20261124
DTEND;VALUE=DATE:20261126
END:VEVENT
BEGIN:VEVENT
SUMMARY:牙医复诊
DTSTART:20261122T143000
DTEND:20261122T151500
END:VEVENT
BEGIN:VEVENT
SUMMARY:
DTSTART:20261125T100000
END:VEVENT
BEGIN:VTODO
SUMMARY:整理导入后的重复项
DUE:20261123T180000
END:VTODO
END:VCALENDAR`);
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
      const warnings = [];
      // The same file imported twice must not duplicate rows: match by UID
      // (stored on import) plus title+day as a fallback for files without UID.
      const known = {};
      EVENTS.concat(TODOS).forEach((x) => { if (x && x.icsUid) known[x.icsUid] = x.id; });
      let duplicates = 0;
      parsed.events.forEach((e, i) => {
        if (e.uid && known[e.uid]) { duplicates++; return; }
        if (!e.uid && EVENTS.some((x) => x.title === e.title && (x.date === e.date || x.startDate === e.date))) { duplicates++; return; }
        const rr = parseRRule(e.rrule);
        if (rr.warning) warnings.push({ line: e.line, text: e.title + '：' + rr.warning });
        const ev = {
          id: 'import-' + Date.now() + '-' + i, title: e.title, cal,
          loc: e.loc || '', note: e.note || '', icsUid: e.uid || '',
          repeat: rr.repeat, repeatEnd: rr.repeatEnd, repeatUntil: rr.repeatUntil, repeatCount: rr.repeatCount,
        };
        const endDate = e.allDay && e.endDate ? addDays(e.endDate, -1) : e.endDate;
        const multiDay = endDate && endDate > e.date;
        // A timed event whose DTEND sits on the next day (23:30 → next 01:30)
        // is cross-midnight, not an all-day span: keep the two-day span but
        // keep the clock times so the projection can show it on both days.
        const crossTimed = !e.allDay && e.start && e.end && e.end < e.start && multiDay;
        if (crossTimed) {
          ev.startDate = e.date; ev.endDate = endDate;
          ev.start = e.start; ev.end = e.end;
          ev.allDay = false; ev.crossMidnight = true;
        } else if (e.allDay || multiDay) {
          ev.allDay = true;
          if (multiDay) { ev.startDate = e.date; ev.endDate = endDate; }
          else ev.date = e.date;
          if (multiDay && !e.allDay && !crossTimed) warnings.push({ line: e.line, text: e.title + '：跨天日程按全天导入' });
        } else {
          ev.date = e.date;
          ev.start = e.start || '09:00';
          ev.end = e.end && e.end > ev.start ? e.end : plusMinutes(ev.start, 60);
          ev.allDay = false;
        }
        EVENTS.push(ev);
      });
      parsed.todos.forEach((t, i) => {
        if (t.uid && known[t.uid]) { duplicates++; return; }
        if (!t.uid && TODOS.some((x) => x.title === t.title && x.due === t.due)) { duplicates++; return; }
        const rr = parseRRule(t.rrule);
        if (rr.warning) warnings.push({ line: t.line, text: t.title + '：' + rr.warning });
        TODOS.unshift({ id: 'import-todo-' + Date.now() + '-' + i, title: t.title, cal, priority: 0, tags: [], note: t.note || '', status: 'open', due: t.due, dueTime: t.dueTime || '', icsUid: t.uid || '',
          repeat: rr.repeat, repeatEnd: rr.repeatEnd, repeatUntil: rr.repeatUntil, repeatCount: rr.repeatCount });
      });
      P.data.importDuplicates = duplicates;
      P.data.importWarnings = warnings;
      state.variant = 'success';
      render();
      const written = parsed.events.length + parsed.todos.length - duplicates;
      toast('导入完成 · ' + written + ' 项写入' + (duplicates ? ' · ' + duplicates + ' 项已存在跳过' : '') + (parsed.skipped.length ? ' · ' + parsed.skipped.length + ' 行跳过' : ''));
    }, 800);
  });

  registerAction('import-skip', () => {
    const parsed = P.data.importParsed;
    if (parsed && parsed.skipped.length) {
      modal({
        title: '跳过 ' + parsed.skipped.length + ' 行并继续？',
        body: '<div class="proto-note">被跳过的行不会写入，导入报告里仍会逐条列出原因。</div>',
        actions: [
          { label: '取消' },
          { label: '继续导入', primary: true, onClick: () => { P.actions['import-next'](); } },
        ],
      });
      return;
    }
    P.actions['import-next']();
  });

  registerAction('import-report', () => {
    const p = P.data.importParsed || { name: 'dayplan.ics', events: [], todos: [], skipped: [{ line: 14, reason: '日期无法识别' }] };
    const warnings = P.data.importWarnings || [];
    modal({
      title: '导入报告',
      body: `<div class="proto-list"><div class="proto-note">${esc(p.name)} · 目标「${esc(calOf(P.data.importCalendar || 'work').name)}」</div>
        <div class="proto-list-row"><span class="grow">成功写入<small>${p.events.length} 个日程 · ${p.todos.length} 个待办</small></span><span class="proto-badge">${p.events.length + p.todos.length}</span></div>
        ${p.skipped.length ? p.skipped.map((s) => `<div class="proto-list-row"><span class="grow">第 ${s.line} 行<small>${esc(s.reason)}${s.raw ? ' · ' + esc(s.raw.slice(0, 40)) : ''}</small></span><span class="proto-badge">跳过</span></div>`).join('') : '<div class="proto-list-row"><span class="grow">没有跳过行</span></div>'}
        ${warnings.length ? warnings.map((w) => `<div class="proto-list-row"><span class="grow">第 ${w.line || '—'} 行<small>${esc(w.text)}</small></span><span class="proto-badge">近似导入</span></div>`).join('') : ''}</div>`,
      actions: [{ label: '关闭', primary: true }],
    });
  });

  /* ---------------- backup merge from a real file ----------------
     The single backup-merge implementation lives in flows-v3-data.js, which
     loads later and also restores state.doneInstances / skipped / localTodos /
     planSeq. No second handler here. */
})();
