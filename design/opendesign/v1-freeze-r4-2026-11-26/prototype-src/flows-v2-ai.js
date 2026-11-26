/* DaySpark prototype v2 — AI conversation that can actually write, with confirmation. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));

  // Restore a local transcript if one was saved.
  if (Array.isArray(P.data.aiMessages) && P.data.aiMessages.length && typeof AI_THREAD !== 'undefined') {
    AI_THREAD.splice(0, AI_THREAD.length, ...P.data.aiMessages);
  }
  function saveThread() {
    if (typeof AI_THREAD !== 'undefined') P.data.aiMessages = AI_THREAD.map((m) => ({ role: m.role, text: m.text, actions: !!m.actions, act: m.act || null }));
  }
  function fmtM(n) { const x = Math.max(0, Math.min(1439, Math.round(n))); return String(Math.floor(x / 60)).padStart(2, '0') + ':' + String(x % 60).padStart(2, '0'); }
  function minsM(t) { const a = String(t || '0:0').split(':').map(Number); return a[0] * 60 + a[1]; }
  function openTodos() {
    return allTodos().filter((t) => t.status !== 'done' && !isDone(t) && !state.deletedTodos.includes(t.id));
  }
  function titleScore(title, text) {
    if (!title) return 0;
    if (text.includes(title)) return 1000;
    let hits = 0;
    for (let i = 0; i < title.length - 1; i++) {
      const pair = title.slice(i, i + 2);
      if (/[\s，,。：:、]/.test(pair)) continue;
      if (text.includes(pair)) hits++;
    }
    return hits;
  }
  function findTarget(text) {
    const list = openTodos();
    const scored = list.map((t) => [t, titleScore(t.title, text)]).sort((a, b) => b[1] - a[1]);
    if (scored.length && scored[0][1] >= 2) return scored[0][0];
    if (state.drawer && state.drawer.type === 'todo') {
      const t = todoById(state.drawer.id);
      if (t && !isDone(t)) return t;
    }
    return null;
  }
  function busyOn(day) {
    const arr = [];
    (window.eventsOn ? window.eventsOn(day) : []).forEach((e) => { if (!e.allDay && e.start) arr.push([minsM(e.start), minsM(e.end)]); });
    (window.plansOn ? window.plansOn(day) : []).forEach((p) => arr.push([p.start, p.end]));
    return arr.sort((a, b) => a[0] - b[0]);
  }
  function nextFreeSlot(day, dur) {
    const busy = busyOn(day);
    let t = 9 * 60;
    busy.forEach(([s, e]) => { if (s < t + dur) t = Math.max(t, e); });
    if (t > 20 * 60 - dur) t = 9 * 60;
    return { start: fmtM(t), end: fmtM(t + dur), busy: busy.length };
  }
  function lastUser() {
    const arr = (typeof AI_THREAD !== 'undefined' ? AI_THREAD : []).filter((m) => m.role === 'user');
    return arr.length ? arr[arr.length - 1].text : '';
  }
  function lastAct() {
    const arr = (typeof AI_THREAD !== 'undefined' ? AI_THREAD : []).filter((m) => m.role === 'ai' && m.act);
    return arr.length ? arr[arr.length - 1].act : null;
  }
  function deriveSubtasks(text, t) {
    const m = /拆成[：:]?(.+)$/.exec(text);
    if (m) {
      const parts = m[1].split(/[、,，]/).map((s) => s.trim()).filter(Boolean);
      if (parts.length) return parts;
    }
    return ['梳理「' + t.title + '」需要的材料', '完成初稿', '检查并提交'];
  }
  function reply(text) {
    const target = findTarget(text);
    // "安排一下提交周报" is a scheduling request first; do not let the
    // 周报 keyword turn it into a summary reply with no writable act payload.
    if (/周报|总结|纪要/.test(text) && !/安排|排一下|计划/.test(text)) {
      return { text: target
        ? '可以。我会围绕「' + target.title + '」整理要点；需要的话可以在下一步拆成子任务。'
        : '可以。告诉我具体是哪一条待办，我会围绕它整理要点。' };
    }
    if (/今天|还剩|剩下/.test(text)) {
      const open = openTodos().filter((t) => t.due === TODAY);
      return { text: open.length
        ? '今天还有 ' + open.length + ' 项：' + open.slice(0, 4).map((t) => t.title).join('、') + '。要安排其中一条吗？'
        : '今天没有今天截止的待办；日历里还有 ' + busyOn(TODAY).length + ' 段安排。' };
    }
    if (/安排|排一下|计划/.test(text)) {
      if (!target) return { text: '先选一件要安排的待办；我不会默认改某一条。', act: { kind: 'plan', todoId: null } };
      const slot = nextFreeSlot(TODAY, 60);
      return {
        text: '建议把「' + target.title + '」安排到今天 ' + slot.start + '–' + slot.end + '；今天已有 ' + slot.busy + ' 段安排，这个时段不重叠。要我写入吗？',
        act: { kind: 'plan', todoId: target.id, date: TODAY, start: slot.start, end: slot.end },
      };
    }
    if (/拆|子任务/.test(text)) {
      if (!target) return { text: '告诉我要拆哪一条待办，或先在详情里打开它。', act: { kind: 'subtasks', todoId: null } };
      const items = deriveSubtasks(text, target);
      return {
        text: '可以把「' + target.title + '」拆成：' + items.join('、') + '。要创建这些子任务吗？',
        act: { kind: 'subtasks', todoId: target.id, items },
      };
    }
    if (/新建|创建|记成/.test(text)) {
      const title = text.replace(/^(请|帮我|把|将)?(新建|创建|记成)(一条|一个)?(待办|任务)?[：:，,]?\s*/, '').trim() || text;
      return { text: '我可以把它整理成一条待办，标题先写作「' + title + '」；写入前会让你确认标题、日期和日历。', act: { kind: 'create', title } };
    }
    return { text: '我可以帮你整理待办、拆子任务或安排时间。说说你现在想先处理哪一件。' };
  }

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
      const r = reply(text);
      AI_THREAD.push({ role: 'ai', text: r.text, actions: true, act: r.act || null });
      state.variant = 'normal';
      saveThread();
      render();
    }, 700);
  });

  /* ---------------- AI write actions: choose the real target ---------------- */
  function targetPicker(onPick) {
    const list = openTodos();
    const body = document.createElement('div');
    body.className = 'proto-list';
    body.innerHTML = list.map((t) => `<button type="button" class="proto-list-row" data-todo="${esc(t.id)}"><span class="grow">${esc(t.title)}<small>${esc(calOf(t.cal).name)}${t.due ? ' · 截止 ' + t.due : ''}</small></span></button>`).join('') || '<div class="proto-note">没有可写入的未完成待办。</div>';
    const scrim = modal({ title: '选择要写入的待办', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-todo]'); if (!b) return;
      const t = todoById(b.dataset.todo); if (!t) return;
      scrim.remove(); onPick(t);
    });
  }
  function planModal(act) {
    let target = act && act.todoId ? todoById(act.todoId) : null;
    if (target && isDone(target)) target = null;
    let day = act && act.date || TODAY;
    const slot = nextFreeSlot(day, 60);
    let start = act && act.start || slot.start;
    let end = act && act.end || slot.end;
    // Identity of a repeating series is never guessed: null until the user
    // explicitly picks a concrete occurrence.
    let occ = null;
    function pickOcc() {
      if (!target || !target.repeat || !window.DS3) return;
      // Canonical explicit picker: no default to today, the selected date,
      // the plan date, or the nearest instance.
      window.DS3.requireOccurrence(target, (picked) => { occ = picked; paint(); });
    }
    const body = document.createElement('div');
    function paint() {
      body.innerHTML = `<div class="proto-field"><label>写入哪条待办</label><button type="button" class="proto-input" data-proto-action="ai-plan-target" style="text-align:left">${target ? esc(target.title) : '选择一条待办'}</button></div>
        ${target && target.repeat
          ? `<div class="proto-field"><label>这一次实例</label><button type="button" class="proto-input" data-proto-action="ai-plan-occ" style="text-align:left">${occ ? esc(occ) : '选择这一次实例'}</button></div>`
          : `<div class="proto-field"><label>日期</label><button type="button" class="proto-input" data-proto-action="ai-plan-date" style="text-align:left">${esc(day)}</button></div>`}
        <div class="proto-inline-row"><div class="proto-field" style="flex:1"><label>开始</label><button type="button" class="proto-input" data-proto-action="ai-plan-time" style="text-align:left">${esc(start)}</button></div><div class="proto-field" style="flex:1"><label>结束</label><button type="button" class="proto-input" data-proto-action="ai-plan-time" style="text-align:left">${esc(end)}</button></div></div>
        <div class="proto-note">只写计划执行，不改截止；确认后日历和今天的时间轴才会出现。${target && target.repeat ? ' 计划只属于选中的这一次实例。' : ''}</div>`;
    }
    paint();
    const scrim = modal({
      title: '写入计划？', body,
      actions: [
        { label: '取消' },
        { label: '写入', primary: true, onClick: () => {
          if (!target) { toast('先选一条待办'); return true; }
          if (target.repeat && !occ) { toast('重复待办要先选这一次实例'); return true; }
          if (minsM(end) <= minsM(start)) { toast('结束时间必须晚于开始'); return true; }
          if (!window.DS3) { toast('计划模型没有加载，未写入'); return true; }
          const alloc = window.DS3.addAllocation(target, {
            date: target.repeat ? occ : day,
            start,
            end,
            occurrenceDate: target.repeat ? occ : null,
          });
          if (!alloc) { toast('没有写入计划：缺少日期、时间或实例'); return true; }
          render();
          toast('已写入计划 · ' + target.title + ' · ' + (target.repeat ? occ + ' ' : '') + start + '–' + end);
        } },
      ],
    });
    // A repeating target must surface the instance picker instead of silently
    // inheriting any date. Cancel leaves the field visible and save blocked.
    if (target && target.repeat) setTimeout(() => { if (!occ) pickOcc(); }, 30);
    body.addEventListener('click', (e) => {
      if (e.target.closest('[data-proto-action="ai-plan-target"]')) targetPicker((t) => { target = t; occ = null; paint(); if (t.repeat) pickOcc(); });
      if (e.target.closest('[data-proto-action="ai-plan-occ"]')) pickOcc();
      if (e.target.closest('[data-proto-action="ai-plan-date"]')) {
        P.openDatePicker({ value: day, onPick: (v) => { if (!v) return; day = v; paint(); } });
      }
      if (e.target.closest('[data-proto-action="ai-plan-time"]')) {
        P.openTimePicker({ title: '计划时间', start, end, onPick: (s, e2) => { start = s; end = e2; paint(); } });
      }
    });
    return scrim;
  }
  function subtasksModal(act) {
    let target = act && act.todoId ? todoById(act.todoId) : null;
    let items = (act && act.items && act.items.length ? act.items.slice() : (target ? deriveSubtasks(lastUser(), target) : [])).slice();
    const body = document.createElement('div');
    function paint() {
      body.innerHTML = `<div class="proto-field"><label>写入哪条待办</label><button type="button" class="proto-input" data-proto-action="ai-sub-target" style="text-align:left">${target ? esc(target.title) : '选择一条待办'}</button></div>
        <div class="proto-field"><label>子任务（可以改）</label><div class="proto-list" data-sub-list>${items.map((x, i) => `<div class="proto-list-row"><input class="proto-input" data-sub="${i}" value="${esc(x)}"><button type="button" class="proto-btn" data-sub-del="${i}" aria-label="删除">×</button></div>`).join('')}</div>
        <button type="button" class="proto-btn" data-sub-add style="margin-top:6px">＋ 添加一条</button></div>
        <div class="proto-note">只写入这条待办的子任务，不创建新的待办。</div>`;
    }
    paint();
    const scrim = modal({
      title: '创建子任务？', body,
      actions: [
        { label: '取消' },
        { label: '创建', primary: true, onClick: () => {
          if (!target) { toast('先选一条待办'); return true; }
          const list = qa('[data-sub]', body).map((i) => i.value.trim()).filter(Boolean);
          if (!list.length) { toast('至少写一条子任务'); return true; }
          target.subtasks = target.subtasks || [];
          list.forEach((x) => { if (!target.subtasks.some((s) => s.title === x)) target.subtasks.push({ title: x, done: false }); });
          render(); toast('已写入 ' + list.length + ' 条子任务 · ' + target.title);
        } },
      ],
    });
    body.addEventListener('input', (e) => {
      const i = e.target.closest('[data-sub]'); if (!i) return;
      items[Number(i.dataset.sub)] = i.value;
    });
    body.addEventListener('click', (e) => {
      if (e.target.closest('[data-sub-add]')) { items = qa('[data-sub]', body).map((i) => i.value); items.push(''); paint(); return; }
      const del = e.target.closest('[data-sub-del]');
      if (del) { items = qa('[data-sub]', body).map((i) => i.value); items.splice(Number(del.dataset.subDel), 1); paint(); return; }
      if (e.target.closest('[data-proto-action="ai-sub-target"]')) targetPicker((t) => { target = t; paint(); });
    });
    return scrim;
  }

  registerAction('ai-insert-proto', (el) => {
    const label = (el.textContent || '').trim();
    const act = lastAct();
    if (label.includes('安排')) { planModal(act && act.kind === 'plan' ? act : null); return; }
    if (label.includes('子任务')) { subtasksModal(act && act.kind === 'subtasks' ? act : null); return; }
    const userText = lastUser();
    const suggested = act && act.kind === 'create' ? act.title : userText.replace(/^(请|帮我|把|将)?(新建|创建|记成)(一条|一个)?(待办|任务)?[：:，,]?\s*/, '').trim();
    if (label.includes('日程')) {
      P.data.newDraft = null;
      P.baseGo('new-event'); P.syncHash(true);
      setTimeout(() => { const i = q('#new-title') || q('.new-page .form-input') || q('.m-detail-scroll .m-form-input'); if (i && suggested) { i.value = suggested; i.dispatchEvent(new Event('input', { bubbles: true })); } }, 40);
      return;
    }
    P.data.newDraft = null;
    P.baseGo('new-todo'); P.syncHash(true);
    setTimeout(() => { const i = q('#new-title') || q('.new-page .form-input') || q('.m-detail-scroll .m-form-input'); if (i && suggested) { i.value = suggested; i.dispatchEvent(new Event('input', { bubbles: true })); } }, 40);
  });

  /* ---------------- model configuration ---------------- */
  registerEnhancer((root) => {
    if (state.screen !== 'settings-ai') return;
    const dlg = q('.set-modal[aria-label="AI 模型配置"]', root);
    if (!dlg) return;
    const inputs = qa('.form-input', dlg);
    if (inputs[0] && !inputs[0].id) inputs[0].id = 'ai-base';
    if (inputs[1] && !inputs[1].id) inputs[1].id = 'ai-key';
    if (inputs[2] && !inputs[2].id) inputs[2].id = 'ai-model';
    qa('.ai-preset', dlg).forEach((b) => {
      if (b.dataset.v2) return;
      b.dataset.v2 = '1';
      b.addEventListener('click', () => {
        qa('.ai-preset', dlg).forEach((x) => x.classList.remove('is-on'));
        b.classList.add('is-on');
        const n = b.textContent.trim();
        const map = {
          OpenAI: ['https://api.openai.com/v1', 'gpt-4o-mini'],
          Anthropic: ['https://api.anthropic.com/v1', 'claude-sonnet-5-5'],
          DeepSeek: ['https://api.deepseek.com/v1', 'deepseek-chat'],
          Gemini: ['https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-pro'],
          Moonshot: ['https://api.moonshot.cn/v1', 'moonshot-v1-8k'],
          Qwen: ['https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'],
          GLM: ['https://open.bigmodel.cn/api/paas/v4', 'glm-4-plus'],
          Ollama: ['http://localhost:11434/v1', 'llama3.2'],
          'LM Studio': ['http://localhost:1234/v1', 'local-model'],
        };
        if (map[n]) {
          if (q('#ai-base', dlg)) q('#ai-base', dlg).value = map[n][0];
          if (q('#ai-model', dlg)) q('#ai-model', dlg).value = map[n][1];
        }
      });
    });
    // Key visibility / persistence is owned by the v3 key-safe config layer;
    // there is no plaintext value here to reveal, and no write path remains.
  });

  registerAction('ai-detect', () => {
    state.variant = 'detecting'; render();
    setTimeout(() => {
      state.variant = 'normal'; render();
      const body = document.createElement('div');
      body.className = 'proto-list';
      ['gpt-4o-mini', 'gpt-4o', 'o4-mini'].forEach((m) => {
        const b = document.createElement('button');
        b.type = 'button'; b.className = 'proto-list-row';
        b.innerHTML = `<span class="grow">${m}<small>来自服务商 /models</small></span>`;
        b.addEventListener('click', () => {
          const input = q('#ai-model');
          if (input) input.value = m;
          b.closest('.proto-modal-scrim').remove();
          toast('已选择模型 · ' + m);
        });
        body.appendChild(b);
      });
      modal({ title: '选择模型', body, actions: [{ label: '取消' }] });
    }, 900);
  });

  registerAction('ai-clear-confirm', () => {
    if (typeof AI_THREAD !== 'undefined') AI_THREAD.splice(0, AI_THREAD.length);
    P.data.aiMessages = [];
    state.variant = 'normal';
    render();
    toast('对话已清空');
  });

  registerEnhancer((root) => {
    if (state.screen !== 'ai-chat') return;
    const head = q('.ai-head p', root);
    if (head) head.textContent = state.aiEnabled ? (state.aiConfigured ? '已连接 · 模型 ' + (P.data.ai.model || 'gpt-4o-mini') + ' · Key 只在本次会话' : '还没有配置模型') : 'AI 助手已关闭';
    // Quick prompts when the conversation is empty.
    const wrap = q('.ai-wrap', root);
    if (wrap && !wrap.dataset.v2 && !q('.ai-msg', wrap)) {
      wrap.dataset.v2 = '1';
      const row = document.createElement('div');
      row.className = 'proto-quick-row';
      row.style.margin = '4px 0 10px';
      row.innerHTML = ['今天还剩什么', '把这周的会议整理成纪要', '把周报拆成三条要点', '安排一下提交周报'].map((x) => `<button type="button" data-proto-action="ai-quick" data-q="${x}">${x}</button>`).join('');
      wrap.insertBefore(row, wrap.firstChild);
    }
  });
  registerAction('ai-quick', (el) => {
    const input = q('#ai-input');
    if (input) input.value = el.dataset.q || '';
    P.actions['ai-send-proto']();
  });

  // The v3 layer owns message-scoped action chips; it reuses these two write
  // dialogs instead of copying them, so a chip can pass the act payload that
  // belongs to its own message.
  P.aiOpenPlan = planModal;
  P.aiOpenSubtasks = subtasksModal;
})();
