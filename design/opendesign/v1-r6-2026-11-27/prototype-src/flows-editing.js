/* Editing flows: create, detail associations, tags, calendars. */
(function () {
  const P = window.Proto;
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
  const { registerAction, registerEnhancer, toast, modal, protoAction } = window.Proto;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));

  function isEventScreen() { return state.screen === 'new-event'; }
  function firstInput(root) { return q('.form-input', root) || q('.proto-input', root); }

  /* ---------------- new item ---------------- */
  // new-save is owned by flows-v3-capture.js (the last registered handler).
  registerAction('new-cancel', () => {
    window.Proto.data.newDraft = null;
    window.Proto.baseGo(isEventScreen() ? 'cal-week' : 'today');
    window.Proto.syncHash(true);
  });
  registerAction('cal-new-proto', () => {
    window.Proto.data.newDraft = null;
    window.Proto.baseGo('new-event');
    window.Proto.syncHash(true);
  });
  registerAction('new-type-event', () => { window.Proto.baseGo('new-event'); window.Proto.syncHash(true); });
  registerAction('new-type-todo', () => { window.Proto.baseGo('new-todo'); window.Proto.syncHash(true); });
  registerAction('new-stay', () => { state.variant = 'normal'; render(); });
  registerAction('new-discard', () => { window.Proto.baseGo(isEventScreen() ? 'cal-week' : 'today'); window.Proto.syncHash(true); });

  /* ---------------- detail associations ---------------- */
  function currentDraft() {
    return state.draft && state.draftKey ? state.draft : null;
  }
  /* The row being edited is either the draft (unsaved) or the live object
     (view drawer). Both need real controls; only the draft delays the write. */
  function editTarget() {
    const draft = currentDraft();
    if (draft) return draft;
    const ref = typeof activeEditRef === 'function' ? activeEditRef() : state.drawer;
    if (!ref) return null;
    return ref.type === 'event' ? eventById(ref.id) : todoById(ref.id);
  }
  function isDraftTarget(obj) { return !!obj && !!state.draft && obj === state.draft; }
  function attsOf(obj) {
    if (!obj) return [];
    if (Array.isArray(obj.attachments)) return obj.attachments;
    if (obj.attach) obj.attachments = [{ id: 'legacy', name: obj.attach, state: 'local', size: '' }];
    else obj.attachments = [];
    return obj.attachments;
  }
  function findAtt(obj, id) { return attsOf(obj).find((a) => a.id === id); }

  registerAction('detail-add-tag', () => {
    const draft = editTarget();
    if (!draft) return;
    const tags = window.Proto.data.tags.slice();
    const body = document.createElement('div');
    body.className = 'proto-list';
    tags.forEach((t) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'proto-list-row';
      const on = (draft.tags || []).includes(t.name);
      b.innerHTML = `<span class="tag-dot" style="background:${t.color}"></span><span class="grow">${t.name}</span>${on ? '<span class="proto-badge">已添加</span>' : '<span class="proto-badge">添加</span>'}`;
      b.addEventListener('click', () => {
        draft.tags = draft.tags || [];
        if (on) draft.tags = draft.tags.filter((x) => x !== t.name);
        else draft.tags.push(t.name);
        b.querySelector('.proto-badge').textContent = on ? '添加' : '已添加';
        b.dataset.on = on ? '' : '1';
      });
      body.appendChild(b);
    });
    const inputRow = document.createElement('div');
    inputRow.className = 'proto-field';
    inputRow.innerHTML = '<label>新标签</label><input class="proto-input" placeholder="输入名称后点添加">';
    const add = document.createElement('button');
    add.type = 'button';
    add.className = 'proto-btn';
    add.textContent = '添加新标签';
    add.addEventListener('click', () => {
      const name = q('.proto-input', inputRow).value.trim();
      if (!name) return;
      if (!window.Proto.data.tags.some((t) => t.name === name)) {
        window.Proto.data.tags.push({ name, color: '#8a8a82' });
      }
      draft.tags = draft.tags || [];
      if (!draft.tags.includes(name)) draft.tags.push(name);
      toast('已添加标签 · ' + name);
      q('.proto-input', inputRow).value = '';
    });
    inputRow.appendChild(add);
    body.appendChild(inputRow);
    modal({ title: '标签', body, actions: [{ label: '完成', primary: true, onClick: () => render() }] });
  });

  registerAction('detail-subtask-add', () => {
    const draft = editTarget();
    if (!draft) return;
    window.Proto.prompt({
      title: '添加子任务',
      label: '子任务',
      placeholder: '例如：整理阻塞点',
      onConfirm: (value) => {
        if (!value) return;
        draft.subtasks = draft.subtasks || [];
        draft.subtasks.push({ title: value, done: false });
        render();
        toast(isDraftTarget(draft) ? '已添加子任务 · 保存后生效' : '已添加子任务');
      },
    });
  });

  let attSeq = 0;
  registerAction('attach-add', () => {
    const obj = editTarget();
    if (!obj) { toast('先打开一项待办或日程'); return; }
    const files = ['本周数据.xlsx|86 KB', '会议纪要.pdf|1.2 MB', '设计稿-v4.fig|4.8 MB'];
    const body = document.createElement('div');
    body.className = 'proto-list';
    const note = document.createElement('div');
    note.className = 'proto-note';
    note.style.marginTop = '0';
    note.textContent = '可以连续添加多个；选择后仍在列表里，点「完成」关闭。';
    body.appendChild(note);
    files.forEach((spec) => {
      const [name, size] = spec.split('|');
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'proto-list-row';
      b.innerHTML = `<span class="grow">${esc(name)}<small>${esc(size)} · 本机文件</small></span><span class="proto-badge">添加</span>`;
      b.addEventListener('click', () => {
        const list = attsOf(obj);
        if (list.some((a) => a.name === name)) { toast('这个文件已经在附件里'); return; }
        const offline = !!(P.demo && P.demo.offline);
        list.push({ id: 'att-' + (++attSeq), name, size, state: offline ? 'failed' : 'local' });
        if (isDraftTarget(obj)) toast(offline ? '上传失败 · 文件留在本机，可重试' : '已添加附件 · 保存后生效');
        else { render(); toast('已添加附件 · ' + name); }
        const badge = q('.proto-badge', b);
        if (badge) { badge.textContent = '已添加'; b.disabled = true; b.classList.add('proto-disabled'); }
      });
      body.appendChild(b);
    });
    modal({ title: '添加附件', body, actions: [{ label: '完成', primary: true, onClick: () => { render(); } }] });
  });
  registerAction('detail-attach', () => { P.actions['attach-add'](); });

  registerAction('attach-open', (el) => {
    const obj = editTarget();
    const att = obj && findAtt(obj, el.dataset.att);
    if (!att) { toast('这个附件已经不在列表里'); return; }
    const stateText = att.state === 'failed' ? '上传失败 · 没有服务器副本' : att.state === 'ready' ? '已保存 · 可在其他设备打开' : '本机文件 · 尚未同步到服务器';
    modal({
      title: att.name,
      body: `<div class="proto-list">
        <div class="proto-list-row"><span class="grow">大小<small>本地记录，不是真实文件内容</small></span><span class="proto-badge">${esc(att.size || '未知')}</span></div>
        <div class="proto-list-row"><span class="grow">状态<small>${esc(stateText)}</small></span><span class="proto-badge">${att.state === 'failed' ? '失败' : att.state === 'ready' ? '可用' : '本机'}</span></div>
      </div><div class="proto-note">原型只模拟打开和下载；不会读取真实文件，也不会真的写磁盘。</div>`,
      actions: [
        { label: '关闭' },
        { label: '下载', primary: true, onClick: () => { toast('已保存到本机 · ' + att.name + '（模拟）'); } },
      ],
    });
  });
  registerAction('attach-retry', (el) => {
    const obj = editTarget();
    const att = obj && findAtt(obj, el.dataset.att);
    if (!att) return;
    if (P.demo && P.demo.offline) { toast('仍然离线；文件留在本机，联网后再重试'); return; }
    att.state = 'ready';
    render();
    toast('已重新上传 · ' + att.name);
  });
  registerAction('attach-remove', (el) => {
    const obj = editTarget();
    const att = obj && findAtt(obj, el.dataset.att);
    if (!att) return;
    modal({
      title: '移除「' + att.name + '」？',
      body: '<div class="proto-note">只会从这一项移除附件记录；本机文件不会被删除。</div>',
      actions: [
        { label: '取消' },
        { label: '移除', primary: true, danger: true, onClick: () => {
          obj.attachments = attsOf(obj).filter((a) => a.id !== att.id);
          if (obj.attach === att.name) obj.attach = '';
          render();
          toast(isDraftTarget(obj) ? '已移除附件 · 保存后生效' : '已移除附件');
        } },
      ],
    });
  });

  /* ---------------- subtasks: complete, rename, delete ---------------- */
  registerAction('subtask-toggle', (el) => {
    const obj = editTarget();
    const i = Number(el.dataset.i);
    if (!obj || !Array.isArray(obj.subtasks) || !obj.subtasks[i]) return;
    const s = obj.subtasks[i];
    s.done = !s.done;
    render();
    toast((s.done ? '已完成子任务' : '已取消完成') + (isDraftTarget(obj) ? ' · 保存后生效' : ''));
  });
  registerAction('subtask-rename', (el) => {
    const obj = editTarget();
    const i = Number(el.dataset.i);
    if (!obj || !Array.isArray(obj.subtasks) || !obj.subtasks[i]) return;
    const s = obj.subtasks[i];
    window.Proto.prompt({
      title: '重命名子任务',
      label: '子任务标题',
      value: s.title,
      confirm: '保存',
      onConfirm: (v) => {
        if (!v) { toast('子任务标题不能为空'); return; }
        s.title = v;
        render();
        toast(isDraftTarget(obj) ? '子任务已改名 · 保存后生效' : '子任务已改名');
      },
    });
  });
  registerAction('subtask-remove', (el) => {
    const obj = editTarget();
    const i = Number(el.dataset.i);
    if (!obj || !Array.isArray(obj.subtasks) || !obj.subtasks[i]) return;
    const s = obj.subtasks[i];
    modal({
      title: '删除子任务「' + s.title + '」？',
      body: '<div class="proto-note">只删除这一条子任务，不影响父待办。</div>',
      actions: [
        { label: '取消' },
        { label: '删除', primary: true, danger: true, onClick: () => {
          obj.subtasks.splice(i, 1);
          render();
          toast(isDraftTarget(obj) ? '已删除子任务 · 保存后生效' : '已删除子任务');
        } },
      ],
    });
  });

  /* ---------------- tags ---------------- */
  function tagNamesInUse() {
    const names = new Set(window.Proto.data.tags.map((t) => t.name));
    TODOS.concat(state.localTodos || []).forEach((t) => (t.tags || []).forEach((n) => names.add(n)));
    return names;
  }

  registerAction('tag-new', () => {
    window.Proto.baseGo('settings-tag-new');
    window.Proto.syncHash(true);
  });

  registerAction('tag-save', () => {
    const section = state.screen.replace('settings-', '');
    if (section === 'tag-new') {
      const input = q('.io-card .form-input') || q('.m-form .m-form-input');
      const name = (input && input.value || '').trim();
      if (!name) { state.variant = 'validation'; render(); return; }
      if (tagNamesInUse().has(name)) { state.variant = 'duplicate'; render(); toast('标签名已存在'); return; }
      window.Proto.data.tags.push({ name, color: '#4f7bbf' });
      window.Proto.baseGo('settings-tags');
      toast('已创建标签 · ' + name);
      window.Proto.syncHash(true);
      return;
    }
    const old = state.tagId || '周报';
    const input = q('.io-card .form-input') || q('.m-form .m-form-input');
    const name = (input && input.value || '').trim();
    if (!name) { state.variant = 'validation'; render(); return; }
    const tag = window.Proto.data.tags.find((t) => t.name === old);
    if (tag) tag.name = name;
    TODOS.concat(state.localTodos || []).forEach((t) => {
      if (Array.isArray(t.tags)) t.tags = t.tags.map((x) => x === old ? name : x);
    });
    state.tagId = name;
    window.Proto.baseGo('settings-tags');
    toast('标签已改名 · ' + name);
    window.Proto.syncHash(true);
  });

  registerAction('tag-delete', () => {
    const old = state.tagId || '周报';
    modal({
      title: '删除标签',
      body: `<div class="proto-note">「${old}」会从所有待办上移除，但不会删除待办本身。</div>`,
      actions: [
        { label: '取消' },
        { label: '删除', primary: true, danger: true, onClick: () => {
          window.Proto.data.tags = window.Proto.data.tags.filter((t) => t.name !== old);
          TODOS.concat(state.localTodos || []).forEach((t) => {
            if (Array.isArray(t.tags)) t.tags = t.tags.filter((x) => x !== old);
          });
          window.Proto.baseGo('settings-tags');
          toast('已删除标签 · ' + old);
          window.Proto.syncHash(true);
        } },
      ],
    });
  });

  /* ---------------- calendars ---------------- */
  function slug(name) {
    const base = name.toLowerCase().replace(/[^a-z0-9一-龥]+/g, '-').replace(/^-|-$/g, '');
    let id = base || 'calendar';
    let i = 2;
    while (CAL[id]) id = base + '-' + i++;
    return id;
  }

  registerAction('cal-save', () => {
    const section = state.screen.replace('settings-', '');
    if (section === 'calendar-new') {
      const input = q('.io-card .form-input') || q('.m-form .m-form-input');
      const name = (input && input.value || '').trim();
      if (!name) { toast('先写日历名称'); input && input.focus(); return; }
      const id = slug(name);
      CAL[id] = { name, color: '#4f7bbf', bg: '#dce7f7', ink: '#1e3557' };
      window.Proto.baseGo('settings-calendars');
      toast('已创建日历 · ' + name);
      window.Proto.syncHash(true);
      return;
    }
    const id = state.calendarId;
    const input = q('.io-card .form-input') || q('.m-form .m-form-input');
    const name = (input && input.value || '').trim();
    if (!id || !CAL[id]) return;
    if (!name) { toast('先写日历名称'); return; }
    CAL[id].name = name;
    window.Proto.baseGo('settings-calendars');
    toast('日历已保存');
    window.Proto.syncHash(true);
  });

  /* ---------------- enhancer ---------------- */
  registerEnhancer((root) => {
    const section = state.screen.startsWith('settings-') ? state.screen.replace('settings-', '') : '';

    // Desktop calendar needs a discoverable create entry, matching the phone FAB.
    if (state.screen.startsWith('cal-') && state.device !== 'mobile') {
      const right = q('.cal-page .ph-right', root);
      if (right && !q('[data-proto-action="cal-new-proto"]', right)) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'tool';
        b.dataset.protoAction = 'cal-new-proto';
        b.innerHTML = (typeof ico === 'function' ? ico('plus', 12) : '+') + ' 新建日程';
        right.insertBefore(b, right.querySelector('[data-action="open-cal-filter"]'));
      }
    }

    // Detail section headers: each "添加" belongs to its own section.
    qa('.d-sec', root).forEach((sec) => {
      const head = q('.d-sec-head', sec);
      const add = q('[data-action="noop"]', head);
      if (!head || !add) return;
      const label = (head.textContent || '').trim();
      if (label.startsWith('标签')) protoAction(add, 'detail-add-tag');
      else if (label.startsWith('子任务')) protoAction(add, 'detail-subtask-add');
    });

    // The standalone sample tag page still needs its rows wired here; the
    // settings tag list is rendered from real data and only needs search.
    if (state.screen === 'tags-page') {
      const container = q('.set-content', root) || q('.simple-wrap', root);
      if (!container) return;
      const addRow = q('.add-row, .simple-add', container);
      const existing = qa('.tag-row', container);
      existing.forEach((row, i) => {
        const tag = window.Proto.data.tags[i];
        if (!tag) return;
        const textNodes = Array.from(row.childNodes).filter((n) => n.nodeType === 3);
        if (textNodes.length) {
          textNodes[0].nodeValue = tag.name;
        } else {
          const span = document.createElement('span');
          span.textContent = tag.name;
          span.style.marginRight = 'auto';
          const count = q('.tag-count', row);
          row.insertBefore(span, count || null);
        }
      });
      const shown = new Set(existing.map((r) => (r.textContent || '').trim()));
      window.Proto.data.tags.forEach((t) => {
        if (shown.has(t.name)) return;
        if (qa('.tag-row', container).some((r) => (r.textContent || '').includes(t.name))) return;
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'tag-row';
        b.style.cssText = 'width:100%;text-align:left';
        b.dataset.protoAction = 'tag-open';
        b.dataset.tag = t.name;
        const count = TODOS.concat(state.localTodos || []).filter((x) => (x.tags || []).includes(t.name)).length;
        b.innerHTML = `<span class="tag-dot" style="background:${t.color}"></span>${t.name}<span class="tag-count">${count} 项</span>`;
        if (addRow && addRow.parentNode) addRow.parentNode.insertBefore(b, addRow);
        else container.appendChild(b);
      });
      qa('.tag-row', container).forEach((row) => {
        if (row.dataset.protoAction) return;
        const name = (row.textContent || '').replace(/\s*\d+\s*项\s*$/, '').trim();
        if (!name) return;
        row.dataset.protoAction = 'tag-open';
        row.dataset.tag = name;
      });
      if (addRow) protoAction(addRow, 'tag-new');
    }
    if (section === 'tags') {
      const search = q('#tag-search', root);
      if (!search) return;
      const container = q('#tag-list', root) || root;
      if (search.dataset.v3) return;
      search.dataset.v3 = '1';
      const apply = () => {
        const term = (search.value || '').trim().toLowerCase();
        let shown = 0;
        qa('.tag-row', container).forEach((row) => {
          const name = row.dataset.name || (q('.tag-name', row) || {}).textContent || '';
          const hit = !term || name.toLowerCase().includes(term);
          row.hidden = !hit;
          if (hit) shown++;
        });
        const none = q('#tag-none', root);
        if (none) none.hidden = !(term && !shown);
      };
      search.addEventListener('input', apply);
      apply();
    }
  });

  registerAction('tag-open', (el) => {
    state.tagId = el.dataset.tag;
    window.Proto.baseGo('settings-tag-edit');
    state.tagId = el.dataset.tag;
    render();
    window.Proto.syncHash(true);
  });
})();

/* Recurring edits are series-level: confirm before writing the anchor. */
(function () {
  const P = window.Proto;
  const { modal, toast } = P;
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-action="save-detail"]');
    if (!el) return;
    const ref = typeof activeEditRef === 'function' ? activeEditRef() : (state.drawer || null);
    if (!ref) return;
    const item = ref.type === 'event' ? eventById(ref.id) : todoById(ref.id);
    if (!item || !item.repeat) return;
    // A plan-only edit changes instance-scoped allocation records, not the
    // series anchor or future instance content. Let the normal save path apply
    // it without a misleading "save to the whole series" confirmation.
    const draft = state.draft;
    if (draft && state.draftKey === ref.type + ':' + ref.id) {
      const draftOther = Object.assign({}, draft);
      const liveOther = Object.assign({}, item);
      delete draftOther.plans; delete draftOther.plan;
      delete liveOther.plans; delete liveOther.plan;
      if (JSON.stringify(draftOther) === JSON.stringify(liveOther)) return;
    }
    e.preventDefault();
    e.stopPropagation();
    modal({
      title: '保存到整个系列？',
      body: `<div class="proto-note">「${item.title || '这一项'}」属于「${item.repeat}」系列。这次修改会写到系列锚点，之后所有实例都会使用新内容；不会只改这一次。</div>`,
      actions: [
        { label: '取消' },
        { label: '保存到整个系列', primary: true, onClick: () => {
          if (typeof commitDraft === 'function') commitDraft();
          if (typeof clearDraft === 'function') clearDraft();
          if (state.variant !== 'detail') state.variant = 'normal';
          render();
          toast('已保存到整个系列');
        } },
      ],
    });
  }, true);
})();

/* New-item fields: keep the master's rows, make them actually editable. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast, protoAction } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));

  function draft() {
    if (!P.data.newDraft) {
      P.data.newDraft = {
        cal: state.defaultCal || 'personal', date: TODAY, start: '11:00', end: '12:00',
        allDay: false, endDate: '', loc: '', repeat: '', repeatEnd: '永不结束',
        repeatUntil: '', repeatCount: 0,
        remind: state.screen === 'new-event' ? '15 分钟前' : '不提醒',
        reminders: [], priority: '中', due: '', dueTime: '', plan: null, plans: [], tags: [], note: '',
      };
    }
    return P.data.newDraft;
  }

  function fieldRow(label) {
    return qa('.new-page .cp-field, .m-detail-scroll .cp-field').find((row) => {
      const k = q('.k', row);
      return k && (k.textContent || '').trim() === label;
    });
  }

  function paint(label, value) {
    const row = fieldRow(label);
    const v = row && q('.v', row);
    if (v) v.textContent = value;
  }

  registerEnhancer((root) => {
    if (state.screen !== 'new-todo' && state.screen !== 'new-event') return;
    qa('.new-page .cp-field, .m-detail-scroll .cp-field', root).forEach((row) => {
      const k = q('.k', row);
      if (!k) return;
      const label = (k.textContent || '').trim();
      row.style.cursor = 'pointer';
      row.dataset.protoAction = 'new-field';
      row.dataset.field = label;
    });
    const d = draft();
    const timeText = d.allDay
      ? (d.endDate && d.endDate !== d.date ? '全天 · ' + d.date + '–' + d.endDate : '全天 · ' + d.date)
      : d.date + ' ' + d.start + '–' + d.end;
    const set = (label, value) => {
      const row = qa('.new-page .cp-field, .m-detail-scroll .cp-field', root).find((x) => {
        const k = q('.k', x);
        return k && (k.textContent || '').trim() === label;
      });
      const v = row && q('.v', row);
      if (v) v.textContent = value;
    };
    set('时间', timeText);
    set('全天', d.allDay ? '是' : '否');
    set('日历', calOf(d.cal).name + (d.cal === (state.defaultCal || 'personal') ? ' · 默认' : ''));
    set('地点', d.loc || '未填写');
    set('重复', d.repeat || '不重复');
    const reminderList = [d.remind].concat(d.reminders || []).filter((r) => r && r !== '不提醒');
    set('提醒', reminderList.length ? Array.from(new Set(reminderList)).join(' · ') : '不提醒');
    set('截止', d.due ? d.due + (d.dueTime ? ' ' + d.dueTime : '') : '无截止');
    const draftPlans = (Array.isArray(d.plans) ? d.plans : []).filter((p) => p && (!p.state || p.state === 'active'));
    const draftHistory = (Array.isArray(d.plans) ? d.plans : []).filter((p) => p && (p.state === 'cancelled' || p.state === 'invalidated')).length;
    const firstPlan = draftPlans.slice().sort((a, b) => String(a.date + a.start).localeCompare(String(b.date + b.start)))[0];
    set('计划执行', firstPlan
      ? firstPlan.date + ' ' + firstPlan.start + '–' + firstPlan.end + (draftPlans.length > 1 ? ' · 共 ' + draftPlans.length + ' 段' : '') + (draftHistory ? ' · 历史 ' + draftHistory : '')
      : (draftHistory ? '没有进行中的计划 · 历史 ' + draftHistory + ' 段' : (d.plan ? d.plan.date + ' ' + d.plan.start + '–' + d.plan.end : '未安排')));
    set('优先级', d.priority || '中');
    // The fact strip above the fields is the same draft. Repaint it so it never
    // contradicts the rows (or what save will actually write).
    const facts = q('#new-facts', root);
    if (facts) {
      const calName = calOf(d.cal).name;
      const whenText = state.screen === 'new-event'
        ? (d.allDay
          ? (d.endDate && d.endDate !== d.date ? '全天 · ' + mdShort(d.date) + '–' + mdShort(d.endDate) : '全天 · ' + mdShort(d.date))
          : mdShort(d.date) + ' ' + (d.start || '') + '–' + (d.end || ''))
        : (d.due ? '截止 ' + mdShort(d.due) + (d.dueTime ? ' ' + d.dueTime : '') : '无截止');
      const trig = reminderList.length && P.reminderTriggerText ? P.reminderTriggerText(d, state.screen === 'new-event' ? 'event' : 'todo', reminderList[0]) : '';
      const remindText = reminderList.length ? reminderList[0] + (trig ? ' · ' + trig : '') : '不提醒';
      facts.innerHTML = `<span class="new-fact"><i class="cal-dot" style="background:${calOf(d.cal).color}"></i>${esc(calName)}</span><span class="new-fact">${ico('clock',10)} ${esc(whenText)}</span><span class="new-fact">${ico('bell',10)} ${esc(remindText)}</span>`;
    }
  });

  // new-field is owned by the later pickers/capture chain; no second writer here.

  // new-save is owned by flows-v3-capture.js (delegated through v3-data).
})();
