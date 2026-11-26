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
    if (typeof AI_THREAD !== 'undefined') P.data.aiMessages = AI_THREAD.map((m) => ({ role: m.role, text: m.text, actions: !!m.actions }));
  }

  function reply(text) {
    if (/周报|总结|纪要/.test(text)) return '可以。先把这周的进展压成三条：\n1. 11 月版本的三处交互已经收敛。\n2. ICS 第 14 行的日期容错还需要补。\n3. Q4 提案框架周三前给林总。\n\n要我把第三条记成周三 18:00 截止的待办吗？';
    if (/今天|还剩|剩下/.test(text)) {
      const open = TODOS.filter((t) => t.status !== 'done' && !isDone(t) && t.due === TODAY);
      return open.length ? '今天还有 ' + open.length + ' 项：' + open.slice(0, 4).map((t) => t.title).join('、') + '。要我按优先级重排吗？' : '今天的待办都完成了。日历里还有牙医复诊和钢琴课。';
    }
    if (/安排|排一下|计划/.test(text)) return '建议把「提交周报给林总」放在 15:15–16:00，避开 14:30 的牙医复诊。要我直接写入这个计划吗？';
    if (/拆|子任务/.test(text)) return '可以把「提交周报给林总」拆成：整理阻塞点、附上数据截图、发给林总。要创建这三条子任务吗？';
    if (/新建|创建|记成/.test(text)) return '我可以把它整理成一条待办，写入前会让你确认标题、日期和日历。';
    return '我可以帮你整理待办、拆子任务或安排时间。说说你现在想先处理哪一件。';
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
      AI_THREAD.push({ role: 'ai', text: reply(text), actions: true });
      state.variant = 'normal';
      saveThread();
      render();
    }, 700);
  });

  registerAction('ai-insert-proto', (el) => {
    const label = (el.textContent || '').trim();
    if (label.includes('安排')) {
      modal({
        title: '写入计划？',
        body: '<div class="proto-note">把「提交周报给林总」安排到今天 15:15–16:00？这会写入计划执行，不改截止。</div>',
        actions: [{ label: '取消' }, { label: '写入', primary: true, onClick: () => {
          const t = todoById('report');
          if (t) t.plan = { date: TODAY, start: '15:15', end: '16:00' };
          render(); toast('已写入计划 · 今天 15:15–16:00');
        } }],
      });
      return;
    }
    if (label.includes('子任务')) {
      const items = ['整理阻塞点', '附上数据截图', '发给林总'];
      modal({
        title: '创建 3 条子任务？',
        body: `<div class="proto-list">${items.map((x) => `<div class="proto-list-row"><span class="grow">${x}</span></div>`).join('')}</div><div class="proto-note">只会写入「提交周报给林总」；不会创建新的待办。</div>`,
        actions: [{ label: '取消' }, { label: '创建', primary: true, onClick: () => {
          const t = todoById('report');
          if (t) { t.subtasks = t.subtasks || []; items.forEach((x) => { if (!t.subtasks.some((s) => s.title === x)) t.subtasks.push({ title: x, done: false }); }); }
          render(); toast('已拆成 3 个子任务');
        } }],
      });
      return;
    }
    if (label.includes('日程')) {
      P.data.newDraft = null;
      P.baseGo('new-event'); P.syncHash(true);
      setTimeout(() => { const i = q('#new-title'); if (i) i.value = '周报评审'; }, 30);
      return;
    }
    P.data.newDraft = null;
    P.baseGo('new-todo'); P.syncHash(true);
    setTimeout(() => { const i = q('#new-title'); if (i) i.value = '整理这周周报的三条要点'; }, 30);
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
    // Reveal / hide the key without ever showing a fake full value.
    const key = q('#ai-key', dlg);
    if (key && !q('[data-proto-action="ai-key-toggle"]', dlg)) {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'mini'; b.textContent = '显示';
      b.dataset.protoAction = 'ai-key-toggle';
      key.insertAdjacentElement('afterend', b);
    }
  });

  registerAction('ai-key-toggle', (el) => {
    const dlg = el.closest('.set-modal');
    const key = q('#ai-key', dlg);
    if (!key) return;
    if (key.type === 'password') { key.type = 'text'; el.textContent = '隐藏'; }
    else { key.type = 'password'; el.textContent = '显示'; }
  });

  registerAction('ai-config-save', () => {
    const dlg = q('.set-modal[aria-label="AI 模型配置"]') || q('.set-modal');
    const base = (q('#ai-base', dlg) || {}).value || '';
    const key = (q('#ai-key', dlg) || {}).value || '';
    const model = (q('#ai-model', dlg) || {}).value || '';
    if (!base.trim() || !/^https?:\/\//.test(base)) { toast('Base URL 需要以 http(s):// 开头'); return; }
    if (!key.trim() || key.includes('••')) { state.variant = 'config-error'; render(); toast('API Key 不能为空'); return; }
    if (!model.trim()) { toast('模型名不能为空'); return; }
    state.variant = 'save-checking';
    render();
    setTimeout(() => {
      P.data.ai.base = base; P.data.ai.model = model;
      P.data.ai.key = key.length > 8 ? key.slice(0, 3) + '••••' + key.slice(-4) : '••••';
      state.aiConfigured = true;
      state.aiEnabled = true;
      state.aiConfigOpen = false;
      state.variant = 'normal';
      render();
      toast('模型配置已保存 · ' + model);
    }, 700);
  });

  registerAction('ai-config-remove', () => {
    modal({
      title: '移除模型配置？',
      body: '<div class="proto-note">会删除本机保存的 Key；已创建的待办和对话不受影响，但无法继续发送。</div>',
      actions: [{ label: '取消' }, { label: '移除', primary: true, danger: true, onClick: () => {
        state.aiConfigured = false;
        state.aiConfigOpen = false;
        state.variant = 'unconfigured';
        P.data.ai.key = '';
        render(); toast('已移除模型配置');
      } }],
    });
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
    if (head) head.textContent = state.aiEnabled ? (state.aiConfigured ? '已连接 · 模型 ' + (P.data.ai.model || 'gpt-4o-mini') + ' · Key 只在本机保存' : '还没有配置模型') : 'AI 助手已关闭';
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
})();
