/* DaySpark prototype v3 — message-scoped AI writes, key-safe model config,
   real simulated sync conflicts, and an honest fallback for unwired controls. */
(function () {
  'use strict';
  const P = window.Proto;
  if (!P) return;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = P.esc || ((s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m])));

  /* ------------------------------------------------------------------ */
  /* One-time styles for search expansion, conflict cards and the        */
  /* visible "未实现" marker.                                            */
  /* ------------------------------------------------------------------ */
  if (!document.getElementById('proto-v3-ai-style')) {
    const style = document.createElement('style');
    style.id = 'proto-v3-ai-style';
    style.textContent = `
.cmd-more{display:flex;align-items:center;justify-content:center;width:100%;min-height:30px;margin:2px 0 4px;border:1px dashed var(--hair-2);border-radius:5px;background:transparent;color:var(--muted);font-size:10px;cursor:pointer}
.cmd-more:hover{background:var(--wash);color:var(--ink)}
.sync-version{display:grid;grid-template-columns:44px minmax(0,1fr);gap:8px;padding:5px 0;border-top:1px solid var(--hair-2);font-size:11px;line-height:1.55}
.sync-version:first-of-type{border-top:0}
.sync-version>b{color:var(--faint);font-size:9px;letter-spacing:.06em;font-weight:600;padding-top:2px}
.sync-version span{min-width:0;overflow-wrap:anywhere;color:var(--ink-2);white-space:pre-line}
.sync-conflict-card{margin:8px 0}
.sync-conflict-card h3{margin:0 0 4px}
.proto-unimplemented{opacity:.55;cursor:not-allowed!important;outline:1px dashed #c4794a;outline-offset:1px}
.proto-unimplemented-tag{display:inline-block;margin-left:6px;padding:0 4px;border-radius:3px;background:#f7dcc8;color:#7c3a14;font-size:8px;line-height:14px;letter-spacing:.04em;vertical-align:middle}
.proto-unimplemented-note{margin:4px 0 0;font-size:9px;color:#7c3a14}
`;
    document.head.appendChild(style);
  }

  /* ------------------------------------------------------------------ */
  /* AI message-scoped action chips                                      */
  /* ------------------------------------------------------------------ */
  const AI_CHIPS = [
    ['plus', '新建待办'],
    ['calendar', '新建日程'],
    ['clock', '安排时间'],
    ['list', '拆成子任务'],
  ];

  function chip(iconName, label, idx) {
    const icon = typeof window.ico === 'function' ? window.ico(iconName, 10) : '';
    return `<button type="button" class="ai-chip" data-proto-action="ai-insert-proto" data-msg="${idx}">${icon}${label}</button>`;
  }

  function thread() {
    return typeof AI_THREAD !== 'undefined' && Array.isArray(AI_THREAD) ? AI_THREAD : [];
  }

  function paintAiChips(root) {
    /* R6: the master now renders one contextual proposal card for the latest
       reply. Older replies keep no action row, so the generic chip painter is
       deliberately disabled here. */
    return;
    if (state.screen !== 'ai-chat') return;
    // Desktop uses .ai-wrap; the phone shell keeps the same bubbles inside
    // .m-scroll, so scope to the page's scroll container there.
    const wrap = q('.ai-wrap', root) || q('.m-scroll', root);
    if (!wrap) return;
    const bubbles = qa('.ai-msg', wrap).filter((b) => {
      const head = q('.ai-msg-head', b);
      return head && /AI 助手/.test(head.textContent || '');
    });
    const arr = thread();
    const aiIndexes = [];
    arr.forEach((m, i) => { if (m && m.role === 'ai') aiIndexes.push(i); });
    bubbles.forEach((bubble, k) => {
      const idx = aiIndexes[k];
      if (idx == null) return;
      const m = arr[idx];
      if (!m || !m.actions) return;
      bubble.dataset.msg = String(idx);
      let row = q('.ai-actions', bubble);
      if (!row) {
        row = document.createElement('div');
        row.className = 'ai-actions';
        bubble.appendChild(row);
      }
      // Replace the master's four unindexed chips with chips bound to this
      // message's own index. Older AI replies now keep their chips too.
      row.innerHTML = AI_CHIPS.map(([ic, label]) => chip(ic, label, idx)).join('');
    });
  }

  function textForMessage(idx) {
    const arr = thread();
    const m = arr[idx];
    if (!m) return '';
    let userText = '';
    for (let i = idx - 1; i >= 0; i--) {
      if (arr[i] && arr[i].role === 'user') { userText = arr[i].text || ''; break; }
    }
    const base = userText || m.text || '';
    return String(base)
      .replace(/^(请|帮我|把|将)?(新建|创建|记成)(一条|一个)?(待办|任务)?[：:，,]?\s*/, '')
      .replace(/^(关于|安排一下|安排|排一下|计划)\s*/, '')
      .split('\n')[0]
      .replace(/[。！!？?]+$/, '')
      .trim();
  }

  /* The master and v2 bound every chip to the last act payload. Read the
     message index from the chip and use that message's own payload. */
  registerAction('ai-insert-proto', (el) => {
    const idx = Number(el.dataset.msg);
    const arr = thread();
    const msg = Number.isFinite(idx) && arr[idx] ? arr[idx] : null;
    const act = msg && msg.act ? msg.act : null;
    const label = (el.textContent || '').trim();

    if (label.includes('安排')) {
      if (typeof P.aiOpenPlan !== 'function') { toast('安排器没有加载'); return; }
      P.aiOpenPlan(act && act.kind === 'plan' ? act : null);
      return;
    }
    if (label.includes('子任务')) {
      if (typeof P.aiOpenSubtasks !== 'function') { toast('子任务编辑器没有加载'); return; }
      P.aiOpenSubtasks(act && act.kind === 'subtasks' ? act : { kind: 'subtasks', todoId: null, items: [] });
      return;
    }

    const suggested = act && act.kind === 'create' ? act.title : textForMessage(idx);
    if (label.includes('日程')) {
      P.data.newDraft = null;
      P.baseGo('new-event'); P.syncHash(true);
      setTimeout(() => {
        const input = q('#new-title') || q('.new-page .form-input') || q('.m-detail-scroll .m-form-input');
        if (input && suggested) { input.value = suggested; input.dispatchEvent(new Event('input', { bubbles: true })); }
      }, 40);
      return;
    }
    P.data.newDraft = null;
    P.baseGo('new-todo'); P.syncHash(true);
    setTimeout(() => {
      const input = q('#new-title') || q('.new-page .form-input') || q('.m-detail-scroll .m-form-input');
      if (input && suggested) { input.value = suggested; input.dispatchEvent(new Event('input', { bubbles: true })); }
    }, 40);
  });

  /* ------------------------------------------------------------------ */
  /* AI model configuration: masked keys are display, not input.         */
  /* The real key lives only in this page session (sessionSecret). It is */
  /* never written to P.data / state / TODOS / EVENTS or any snapshot.   */
  /* ------------------------------------------------------------------ */
  function maskKey(key) {
    const k = String(key || '').trim();
    if (!k) return '';
    if (k.length > 8) return k.slice(0, 3) + '••••' + k.slice(-4);
    return '••••';
  }
  function isMasked(v) { return String(v || '').includes('•'); }

  // Module-level only. Not attached to P, Proto, state, or any data object.
  let sessionSecret = '';
  P.aiHasSessionKey = function () { return !!sessionSecret; };
  P.maskKey = maskKey;

  // Migration: old builds wrote P.data.ai.secret (plaintext) and could store
  // an unmasked key. Read them into this session, then scrub the persisted
  // objects and overwrite localStorage right away.
  let aiMigrated = false;
  (function migrateAiConfig() {
    if (!P.data.ai || typeof P.data.ai !== 'object') P.data.ai = {};
    const ai = P.data.ai;
    if (Object.prototype.hasOwnProperty.call(ai, 'secret')) {
      const old = String(ai.secret == null ? '' : ai.secret).trim();
      if (old && !isMasked(old)) sessionSecret = old;
      delete ai.secret;
      aiMigrated = true;
    }
    // Defensive: any other credential-ish field on the AI config is removed.
    ['apiKey', 'api_key', 'password', 'token', 'accessToken', 'refreshToken'].forEach((field) => {
      if (!Object.prototype.hasOwnProperty.call(ai, field)) return;
      const v = String(ai[field] == null ? '' : ai[field]).trim();
      if (!sessionSecret && v && !isMasked(v)) sessionSecret = v;
      delete ai[field];
      aiMigrated = true;
    });
    if (ai.key && !isMasked(ai.key)) {
      const plain = String(ai.key).trim();
      if (!sessionSecret && plain) sessionSecret = plain;
      ai.key = maskKey(plain);
      aiMigrated = true;
    }
    if (!ai.base) ai.base = 'https://api.openai.com/v1';
    if (!ai.model) ai.model = 'gpt-4o-mini';
    if (!Object.prototype.hasOwnProperty.call(ai, 'key')) ai.key = '';
    if (aiMigrated) persistAiConfig();
  })();

  function persistAiConfig() {
    // Never serialise the session secret. Snapshot only sees data.ai.key (mask).
    if (P.data.ai) delete P.data.ai.secret;
    try {
      if (typeof P.persistNow === 'function') P.persistNow();
      else P.save();
    } catch (_) {}
  }

  /* Deep, non-mutating backup redaction. Agent ③'s export can call this
     directly: P.redactForBackup(P.snapshot()). */
  const CREDENTIAL_FIELDS = new Set(['secret', 'password', 'passwd', 'token', 'apiKey', 'api_key', 'accessToken', 'refreshToken', 'sessionSecret']);
  function looksLikeAiConfig(obj) {
    return !!obj && typeof obj === 'object' && !Array.isArray(obj)
      && Object.prototype.hasOwnProperty.call(obj, 'key')
      && (Object.prototype.hasOwnProperty.call(obj, 'base') || Object.prototype.hasOwnProperty.call(obj, 'model'));
  }
  function redactForBackup(input) {
    const seen = new WeakMap();
    function walk(val, inAi) {
      if (val == null || typeof val !== 'object') return val;
      if (val instanceof Date) return val.toISOString();
      if (seen.has(val)) return seen.get(val);
      if (Array.isArray(val)) {
        const arr = [];
        seen.set(val, arr);
        val.forEach((v) => arr.push(walk(v, inAi)));
        return arr;
      }
      const out = {};
      seen.set(val, out);
      const ai = inAi || looksLikeAiConfig(val);
      Object.keys(val).forEach((k) => {
        if (k === '__proto__' || k === 'constructor' || k === 'prototype') return;
        if (CREDENTIAL_FIELDS.has(k)) return; // remove, never copy
        if (k === 'key' && ai) {
          const v = val[k];
          out[k] = v && !isMasked(v) ? maskKey(v) : v;
          return;
        }
        out[k] = walk(val[k], ai);
      });
      return out;
    }
    return walk(input, false);
  }
  P.redactForBackup = redactForBackup;

  // Backup merge hook used by the data layer: keep only display-safe fields.
  // A masked key may be restored for display; a usable key never is.
  P.sanitizeAiCredentials = function sanitizeAiCredentials(ai) {
    const out = {};
    if (!ai || typeof ai !== 'object' || Array.isArray(ai)) return out;
    if (ai.base != null) out.base = String(ai.base);
    if (ai.model != null) out.model = String(ai.model);
    if (typeof ai.key === 'string' && isMasked(ai.key)) out.key = ai.key;
    return out;
  };

  let aiDraft = null;          // values while the config dialog is open
  let keyClearRequested = false; // explicit clear of the session key
  let wasConfigOpen = false;

  const PRESETS = {
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

  function aiConfigEnhance(root) {
    if (state.screen !== 'settings-ai') return;
    const dlg = q('.set-modal[aria-label="AI 模型配置"]', root);
    const open = !!dlg;
    const wasOpen = wasConfigOpen;
    if (open && !wasOpen) {
      aiDraft = {
        base: P.data.ai.base || 'https://api.openai.com/v1',
        model: P.data.ai.model || 'gpt-4o-mini',
        key: P.data.ai.key || '',
      };
      keyClearRequested = false;
    }
    wasConfigOpen = open;
    if (!open && wasOpen) {
      // Cancel/close must not leave a typed-but-unsaved key in module memory.
      aiDraft = null;
      keyClearRequested = false;
    }
    // The settings row should show the stored mask, never a stale literal.
    qa('.set-key', root).forEach((el) => { el.textContent = P.data.ai.key || '未配置'; });
    qa('.set-key-row', root).forEach((row) => {
      Array.from(row.children).forEach((el) => {
        if (/只在本机保存|保存在本机/.test(el.textContent || '')) {
          el.textContent = 'Key 只在本次会话 · 刷新后需重新输入';
        }
      });
    });
    // Phone settings: replace the master's hard-coded mask with the real mask.
    qa('.m-settings-row', root).forEach((row) => {
      if (!/模型配置/.test(row.textContent || '')) return;
      const small = q('small', row);
      if (!small) return;
      small.textContent = (state.aiConfigured && P.data.ai.key)
        ? P.data.ai.key + ' · ' + (P.data.ai.model || 'gpt-4o-mini') + ' · 仅本次会话'
        : '未配置';
    });
    if (dlg) {
      qa('.form-help', dlg).forEach((el) => {
        if (/Key 只保存在这台设备|不会同步到服务器/.test(el.textContent || '')) {
          el.textContent = 'Key 只在本次页面会话使用，刷新后需要重新输入；检测会请求 /models。';
        }
      });
    }
    if (!dlg) return;

    const inputs = qa('.form-input', dlg);
    const baseInput = inputs[0];
    const keyInput = inputs[1];
    const modelInput = inputs[2];
    if (baseInput && !baseInput.id) baseInput.id = 'ai-base';
    if (keyInput && !keyInput.id) keyInput.id = 'ai-key';
    if (modelInput && !modelInput.id) modelInput.id = 'ai-model';

    if (baseInput) baseInput.value = aiDraft ? aiDraft.base : (P.data.ai.base || 'https://api.openai.com/v1');
    if (modelInput) modelInput.value = aiDraft ? aiDraft.model : (P.data.ai.model || 'gpt-4o-mini');
    if (keyInput) keyInput.value = aiDraft ? aiDraft.key : (P.data.ai.key || '');

    if (keyInput && !keyInput.dataset.v3input) {
      keyInput.dataset.v3input = '1';
      keyInput.addEventListener('input', () => {
        aiDraft = aiDraft || {};
        aiDraft.key = keyInput.value;
        if (!isMasked(keyInput.value) && keyInput.value.trim()) {
          keyClearRequested = false;
          const clearBtn = q('[data-proto-action="ai-key-clear"]', dlg);
          if (clearBtn) clearBtn.classList.remove('is-on');
        }
      });
    }
    if (baseInput && !baseInput.dataset.v3input) {
      baseInput.dataset.v3input = '1';
      baseInput.addEventListener('input', () => { aiDraft = Object.assign({}, aiDraft, { base: baseInput.value }); });
    }
    if (modelInput && !modelInput.dataset.v3input) {
      modelInput.dataset.v3input = '1';
      modelInput.addEventListener('input', () => { aiDraft = Object.assign({}, aiDraft, { model: modelInput.value }); });
    }

    if (keyInput && !q('[data-proto-action="ai-key-clear"]', dlg)) {
      const clear = document.createElement('button');
      clear.type = 'button';
      clear.className = 'mini';
      clear.dataset.protoAction = 'ai-key-clear';
      clear.textContent = '清除已保存的 Key';
      clear.title = '清除本次会话使用的 Key 与本机掩码；Base URL 和模型名保留。';
      keyInput.insertAdjacentElement('afterend', clear);
      const note = document.createElement('div');
      note.className = 'form-help';
      note.textContent = 'Key 只保存在本次页面会话，刷新后需要重新输入；这里显示的是掩码，不是真实 Key。不改动直接保存会保留当前掩码；只有输入新的 Key，或显式清除，才会改变它。';
      clear.insertAdjacentElement('afterend', note);
    }
    const clearBtn = q('[data-proto-action="ai-key-clear"]', dlg);
    if (clearBtn) clearBtn.classList.toggle('is-on', keyClearRequested);

    qa('.ai-preset', dlg).forEach((b) => {
      if (b.dataset.action === 'noop') b.removeAttribute('data-action');
      b.dataset.protoAction = 'ai-preset';
      b.dataset.provider = b.textContent.trim();
    });

    // The master's own save handler never touched P.data.ai; route the
    // dialog's save/remove buttons through the key-safe implementation.
    qa('[data-action="ai-config-save"]', dlg).forEach((b) => { b.dataset.protoAction = 'ai-config-save'; });
    qa('[data-action="ai-config-remove"]', dlg).forEach((b) => { b.dataset.protoAction = 'ai-config-remove'; });
    qa('[data-action="ai-detect"]', dlg).forEach((b) => { if (!b.dataset.protoAction) b.dataset.protoAction = 'ai-detect'; });
  }

  registerAction('ai-preset', (el) => {
    const dlg = el.closest('.set-modal');
    const name = el.dataset.provider || el.textContent.trim();
    qa('.ai-preset', dlg).forEach((x) => x.classList.toggle('is-on', x === el));
    const map = PRESETS[name];
    if (!map) return; // 自定义: keep whatever Base URL/model the user typed.
    const base = q('#ai-base', dlg);
    const model = q('#ai-model', dlg);
    if (base) base.value = map[0];
    if (model) model.value = map[1];
    aiDraft = Object.assign({}, aiDraft, { base: map[0], model: map[1] });
    toast('已选择服务商 · ' + name);
  });

  registerAction('ai-key-clear', (el) => {
    keyClearRequested = !keyClearRequested;
    el.classList.toggle('is-on', keyClearRequested);
    const dlg = el.closest('.set-modal');
    const key = q('#ai-key', dlg);
    if (keyClearRequested && key) {
      key.value = '';
      aiDraft = Object.assign({}, aiDraft, { key: '' });
    } else if (aiDraft) {
      aiDraft.key = P.data.ai.key || '';
      if (key) key.value = aiDraft.key;
    }
    toast(keyClearRequested ? '保存后会清除本次会话的 Key' : '已取消清除，保存时保留当前掩码');
  });

  registerAction('ai-config-save', () => {
    const dlg = q('.set-modal[aria-label="AI 模型配置"]') || q('.set-modal');
    if (!dlg) return;
    const base = ((q('#ai-base', dlg) || {}).value || '').trim();
    const rawKey = ((q('#ai-key', dlg) || {}).value || '').trim();
    const model = ((q('#ai-model', dlg) || {}).value || '').trim();
    if (!base || !/^https?:\/\//.test(base)) { toast('Base URL 需要以 http(s):// 开头'); return; }
    if (!model) { toast('模型名不能为空'); return; }

    // The real key is session-only. An empty/masked input keeps whatever the
    // session already has (which may be nothing after a refresh) and the
    // persisted mask; it is never a "Key required" validation error.
    const masked = isMasked(rawKey);
    let nextSecret = String(sessionSecret || '').trim();
    let nextMask = String(P.data.ai.key || '');
    let cleared = false;

    if (keyClearRequested && (!rawKey || masked)) {
      nextSecret = '';
      nextMask = '';
      cleared = true;
    } else if (rawKey && !masked) {
      nextSecret = rawKey;
      nextMask = maskKey(rawKey);
    }

    aiDraft = { base, model, key: nextMask };
    keyClearRequested = false;
    state.variant = 'save-checking';
    state.aiConfigOpen = true;
    render();

    setTimeout(() => {
      P.data.ai.base = base;
      P.data.ai.model = model;
      P.data.ai.key = nextMask;
      delete P.data.ai.secret; // never persists in any form
      sessionSecret = nextSecret;
      state.aiConfigured = !!nextMask;
      if (nextMask) state.aiEnabled = true;
      state.aiConfigOpen = false;
      state.variant = cleared || !nextMask ? 'unconfigured' : 'normal';
      aiDraft = null;
      persistAiConfig();
      render();
      if (cleared) toast('已清除本次会话的 Key · Base URL 与模型名保留');
      else if (rawKey && !masked) toast('模型配置已保存 · Key 只在本次会话生效 · ' + model);
      else if (nextMask) toast('模型配置已保存 · Key 只在本次会话，刷新后需重新输入 · ' + model);
      else toast('模型配置已保存 · 未填写 Key · 刷新后需重新输入');
    }, 650);
  });

  registerAction('ai-config-remove', () => {
    modal({
      title: '移除模型配置？',
      body: '<div class="proto-note">会清除本次会话使用的 Key，并移除本机保存的掩码；已创建的待办和对话不受影响。</div>',
      actions: [{ label: '取消' }, {
        label: '移除', primary: true, danger: true, onClick: () => {
          sessionSecret = '';
          P.data.ai.key = '';
          delete P.data.ai.secret;
          aiDraft = null;
          keyClearRequested = false;
          state.aiConfigured = false;
          state.aiConfigOpen = false;
          state.variant = 'unconfigured';
          persistAiConfig();
          render();
          toast('已移除模型配置 · 本次会话的 Key 已清除');
        },
      }],
    });
  });

  /* ------------------------------------------------------------------ */
  /* Real simulated sync conflict                                        */
  /* ------------------------------------------------------------------ */
  const CONFLICT_SEEDS = [
    {
      id: 'report',
      local: { title: '提交周报给林总', note: '把本周的三个阻塞点写进周报，附上数据。', priority: 5 },
      server: { title: '提交周报 · 服务器修订版', note: '服务器：补充上周遗留的两个阻塞点。', priority: 9 },
    },
    {
      id: 'proposal',
      local: { title: '写 Q4 提案初稿', note: '先列框架，再补数据。', priority: 5 },
      server: { title: '写 Q4 提案初稿 · 补充数据', note: '服务器：先补数据，再列框架。', priority: 1 },
    },
  ];

  function todoFields(id) {
    const t = todoById(id);
    if (!t) return null;
    return {
      title: t.title || '',
      note: t.note || '',
      priority: t.priority == null ? 0 : t.priority,
    };
  }

  function conflictBatch() {
    P.data.sync = P.data.sync || {};
    if (!P.data.sync.conflictBatch || !Array.isArray(P.data.sync.conflictBatch.items)) {
      P.data.sync.conflictBatch = {
        createdAt: Date.now(),
        items: CONFLICT_SEEDS.map((seed) => ({
          id: seed.id,
          local: todoFields(seed.id) || Object.assign({}, seed.local),
          server: Object.assign({}, seed.server),
        })),
      };
    }
    return P.data.sync.conflictBatch;
  }

  // Field-level merge: notes are concatenated; a server title only replaces
  // an empty local title; the server wins on priority when it has one.
  function mergeConflict(local, server) {
    const l = local || {};
    const s = server || {};
    const notes = [];
    if (l.note != null && String(l.note).trim()) notes.push(String(l.note).trim());
    if (s.note != null && String(s.note).trim()) notes.push(String(s.note).trim());
    return {
      title: l.title != null && String(l.title).trim() ? l.title : (s.title || ''),
      note: notes.join('\n'),
      priority: s.priority != null ? s.priority : l.priority,
    };
  }
  P.syncMerge = mergeConflict;

  function applyOne(item, choice) {
    const t = todoById(item.id);
    if (!t) return null;
    let next;
    if (choice === 'local') next = Object.assign({}, item.local);
    else if (choice === 'server') next = Object.assign({}, item.server);
    else next = mergeConflict(item.local, item.server);
    t.title = next.title != null ? next.title : t.title;
    t.note = next.note;
    t.priority = next.priority;
    t.conflictResolvedAt = Date.now();
    return {
      id: item.id,
      choice,
      after: { title: t.title, note: t.note, priority: t.priority },
    };
  }

  function applyConflictSelection(picks) {
    const batch = conflictBatch();
    const missing = batch.items.filter((it) => !picks || !picks[it.id]);
    if (missing.length) {
      toast('还有 ' + missing.length + ' 项冲突没有选择');
      return false;
    }
    const applied = [];
    batch.items.forEach((it) => {
      const row = applyOne(it, picks[it.id]);
      if (row) applied.push(row);
    });
    const choices = {};
    applied.forEach((r) => { choices[r.id] = r.choice; });
    const stamp = new Date();
    const hh = String(stamp.getHours()).padStart(2, '0');
    const mm = String(stamp.getMinutes()).padStart(2, '0');
    P.demo = P.demo || {};
    P.demo.conflict = false;
    P.data.sync.conflicts = 0;
    P.data.account.lastSync = '刚刚 · 冲突已解决（' + hh + ':' + mm + '）';
    batch.resolvedAt = Date.now();
    batch.resolved = applied;
    P.data.sync.lastResolution = { at: Date.now(), picks: choices, applied };
    render();
    toast('已应用 ' + applied.length + ' 项冲突：' + applied.map((r) => r.id + '=' + r.choice).join('、'));
    return applied;
  }
  P.applySyncConflict = applyConflictSelection;

  function conflictCard(item, picked) {
    const local = item.local;
    const server = item.server;
    return `<div class="io-card sync-conflict-card" data-cid="${esc(item.id)}">
      <h3>${esc(item.local.title || item.server.title || item.id)}</h3>
      <div class="sync-version"><b>本地</b><span>标题：${esc(local.title || '（空）')}<br>备注：${esc(local.note || '（空）')}<br>优先级：${esc(local.priority)}</span></div>
      <div class="sync-version"><b>服务器</b><span>标题：${esc(server.title || '（空）')}<br>备注：${esc(server.note || '（空）')}<br>优先级：${esc(server.priority)}</span></div>
      <div class="proto-seg" data-conflict="${esc(item.id)}">
        <button type="button" data-v="local" class="${picked === 'local' ? 'is-on' : ''}">保留本地</button>
        <button type="button" data-v="server" class="${picked === 'server' ? 'is-on' : ''}">用服务器</button>
        <button type="button" data-v="merge" class="${picked === 'merge' ? 'is-on' : ''}">合并</button>
      </div>
    </div>`;
  }

  registerAction('sync-conflict-open', () => {
    const batch = conflictBatch();
    const body = document.createElement('div');
    const picks = {};
    body.innerHTML = `<div class="proto-note">每条单独选择。应用后会把结果写入本机待办并保存；“应用选择”会一次处理全部行。</div>` +
      batch.items.map((it) => conflictCard(it, null)).join('');
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-v]');
      if (!b) return;
      const seg = b.closest('.proto-seg');
      if (!seg) return;
      qa('button', seg).forEach((x) => x.classList.remove('is-on'));
      b.classList.add('is-on');
      picks[seg.dataset.conflict] = b.dataset.v;
    });
    modal({
      title: '处理同步冲突', wide: true, body,
      actions: [
        { label: '稍后' },
        {
          label: '应用选择', primary: true, onClick: () => {
            if (!applyConflictSelection(picks)) return true;
            return false;
          },
        },
      ],
    });
  });

  registerAction('sync-pick', (el) => {
    const seg = el.closest('.proto-seg');
    if (!seg) return;
    state.syncPicks = state.syncPicks || {};
    state.syncPicks[seg.dataset.conflict] = el.dataset.v;
    qa('button', seg).forEach((x) => x.classList.toggle('is-on', x === el));
  });

  registerAction('sync-apply', () => {
    const picks = state.syncPicks || {};
    const ok = applyConflictSelection(picks);
    if (ok) state.syncPicks = {};
    return ok;
  });

  function paintConflictPage(root) {
    if (state.screen !== 'settings-sync-conflict') return;
    // Desktop uses .set-content; the phone shell keeps the page body in
    // .m-scroll. Replace either so the same selectable conflict UI is used.
    const content = q('.set-content', root) || q('.m-scroll', root);
    if (!content) return;
    const batch = conflictBatch();
    const picks = state.syncPicks || {};
    const resolved = !!batch.resolvedAt && (!P.data.sync || !P.data.sync.conflicts);
    const current = batch.items.map((it) => {
      const f = todoFields(it.id);
      return f ? `<div class="sync-version"><b>${esc(f.title || it.id)}</b><span>标题：${esc(f.title)}<br>备注：${esc(f.note || '（空）')}<br>优先级：${esc(f.priority)}</span></div>` : '';
    }).join('');
    const cards = batch.items.map((it) => conflictCard(it, picks[it.id])).join('')
      // The modal card uses its own delegated picker; the full page needs
      // each option to be a real proto action so it can update state.syncPicks.
      .replace(/<button type="button" data-v=/g, '<button type="button" data-proto-action="sync-pick" data-v=');
    content.innerHTML = `<h2 class="set-h">同步冲突</h2>
      <p class="set-desc">同一个条目在本地和服务器都改过；逐项选择。应用后写入本机并保存。</p>
      ${resolved ? `<div class="inline-alert"><b>这组冲突已经应用。</b><br>最近一次结果：${esc((batch.resolved || []).map((r) => r.id + '=' + r.choice).join('、'))}。下面显示当前保存的值。</div>` : ''}
      ${cards}
      <div class="io-card"><h3>当前保存的值</h3>${current}</div>
      <div class="filter-actions"><button type="button" class="primary" data-proto-action="sync-apply">应用选择</button></div>`;
  }

  /* ------------------------------------------------------------------ */
  /* Honest fallback: product screens never become a tidy read-only card */
  /* ------------------------------------------------------------------ */
  const SURFACE_KEYS = (typeof SURFACES !== 'undefined' && SURFACES) ? Object.keys(SURFACES) : [];
  const NON_PRODUCT = new Set(['spec', 'states', 'overlays', 'widgets'].concat(SURFACE_KEYS));
  const warned = new Set();

  function controlLabel(el) {
    const row = el.closest && el.closest('.set-row, .m-settings-row, .field-row');
    if (row) {
      const l = q('.set-label, .m-settings-label, span', row);
      const t = (l ? l.textContent : row.textContent) || '';
      return t.replace(/\s+/g, ' ').trim().slice(0, 40);
    }
    return (el.getAttribute('aria-label') || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40) || '这一项';
  }

  function markDisabledReason(el, reason) {
    el.classList.add('proto-disabled');
    el.dataset.protoAction = 'disabled-info';
    el.dataset.reason = reason;
    el.setAttribute('aria-disabled', 'true');
    el.title = reason;
  }

  P.fallback = function fallback(el, root) {
    // A real disabled control keeps its disabled state, but now says why.
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') {
      markDisabledReason(el, el.dataset.reason || '这一项在当前状态下不可用。');
      return;
    }
    // Design-sample surfaces from the master keep their explicit
    // "这是设计样张" behaviour instead of pretending to be product writes.
    if (typeof SURFACES !== 'undefined' && state.screen in SURFACES) {
      el.dataset.protoAction = 'demo-surface-info';
      el.dataset.demoLabel = controlLabel(el);
      return;
    }
    if (NON_PRODUCT.has(state.screen)) {
      el.dataset.protoAction = 'demo-surface-info';
      el.dataset.demoLabel = controlLabel(el);
      return;
    }
    // Product route: do not cover an unwired control with a read-only dialog.
    const label = controlLabel(el);
    const reason = '这个控件还没有接入真实写入；已停用并标记为“未实现”。';
    if (!warned.has(state.screen + '/' + label)) {
      warned.add(state.screen + '/' + label);
      console.warn('[DaySpark 原型] 未实现的产品控件：' + state.screen + ' · ' + label, el);
    }
    el.dataset.protoAction = 'unimplemented-info';
    el.dataset.unimplementedLabel = label;
    el.classList.add('proto-unimplemented');
    el.setAttribute('aria-disabled', 'true');
    el.title = reason;
    if (el.tagName === 'BUTTON' || el.tagName === 'INPUT' || el.tagName === 'SELECT') el.disabled = true;
    if (!el.dataset.unimplementedMarked) {
      el.dataset.unimplementedMarked = '1';
      const tag = document.createElement('span');
      tag.className = 'proto-unimplemented-tag';
      tag.textContent = '未实现';
      if (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA') el.insertAdjacentElement('afterend', tag);
      else el.appendChild(tag);
    }
  };

  registerAction('unimplemented-info', (el) => {
    toast('未实现：' + (el.dataset.unimplementedLabel || '这个控件') + '（控制台有警告）');
  });

  registerAction('account-detail', () => {
    const a = P.data.account || {};
    modal({
      title: '账号与服务器',
      body: `<div class="proto-list">
        <div class="proto-list-row"><span class="grow">账号<small>${a.signedIn ? '已登录' : '未登录'}</small></span><span>${esc(a.email || '—')}</span></div>
        <div class="proto-list-row"><span class="grow">服务器<small>自托管同步地址</small></span><span>${esc(a.server || '—')}</span></div>
        <div class="proto-list-row"><span class="grow">最后同步<small>最近一次成功</small></span><span>${esc(a.lastSync || '—')}</span></div>
        <div class="proto-list-row"><span class="grow">已连接设备</span><span>${(a.devices || []).length} 台</span></div>
      </div><div class="proto-note">这是当前会话的只读事实；需要修改地址请用「服务器」那一行。</div>`,
      actions: [
        { label: '关闭' },
        { label: '复制账号', onClick: () => { if (navigator.clipboard) navigator.clipboard.writeText(a.email || '').catch(() => {}); toast('已复制账号'); } },
      ],
    });
  });

  /* ------------------------------------------------------------------ */
  /* Honest session-only key copy                                        */
  /* ------------------------------------------------------------------ */
  const AI_KEY_COPY = [
    ['Key 只保存在这台设备；不会同步到服务器。', 'Key 只在本次页面会话使用；刷新后需要重新输入。'],
    ['Key 只保存在本机，不会上传到 DaySpark 服务器。', 'Key 只在本次页面会话使用，刷新后需要重新输入；模拟对话不依赖真实 Key。'],
    ['Key 只保存在本机。', 'Key 只在本次页面会话使用，刷新后需要重新输入。'],
    ['Key 只在本机保存', 'Key 只在本次会话'],
    ['仅在本机保存 Key', 'Key 只在本次会话'],
    ['只在本机保存', '只在本次会话'],
  ];
  function honestAiCopy(root) {
    if (!['settings-ai', 'settings-home', 'ai-chat'].includes(state.screen)) return;
    const walker = document.createTreeWalker(root, window.NodeFilter ? NodeFilter.SHOW_TEXT : 4);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach((node) => {
      let text = node.nodeValue || '';
      AI_KEY_COPY.forEach(([from, to]) => { if (text.includes(from)) text = text.split(from).join(to); });
      if (text !== node.nodeValue) node.nodeValue = text;
    });
  }

  /* ------------------------------------------------------------------ */
  /* Per-render wiring                                                   */
  /* ------------------------------------------------------------------ */
  registerEnhancer((root) => {
    // Any control that already has a real proto action is no longer a noop;
    // remove the old attribute so the fallback cannot see it.
    qa('[data-action="noop"][data-proto-action]', root).forEach((el) => el.removeAttribute('data-action'));

    paintAiChips(root);
    if (state.screen === 'ai-chat') {
      qa('.ai-send, .cap-send', root).forEach((b) => { if (!b.dataset.protoAction) b.dataset.protoAction = 'ai-send-proto'; });
    }
    aiConfigEnhance(root);
    honestAiCopy(root);
    paintConflictPage(root);

    // The sync/account page has one genuine read-only fact: the account row.
    if (state.screen.startsWith('settings-sync') || state.screen === 'settings-account') {
      qa('.set-row', root).forEach((row) => {
        if (row.dataset.protoAction) return;
        const label = (q('.set-label', row) || {}).textContent || '';
        if (label.includes('账号') && !label.includes('已连接')) {
          row.dataset.protoAction = 'account-detail';
          row.removeAttribute('data-action');
          const v = q('.set-value', row);
          if (v && !v.dataset.protoAction) v.dataset.protoAction = 'account-detail';
        }
      });
    }
  });
})();
