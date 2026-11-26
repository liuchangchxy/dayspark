/* DaySpark prototype v3 — pickers and reminder anchoring.
   Priority scale matches the frozen master exactly:
     无 = 0 · 高 = 1 · 中 = 5 · 低 = 9
   Reminder rule: a relative reminder (准时 / N 分钟前 / N 小时前 / N 天前)
   is only selectable when a real time anchor exists — a plan start or a
   due time. Due date without dueTime and no plan = no anchor; then the
   picker disables the relative rows with a visible reason and offers an
   absolute time instead. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));

  /* ---------------- priority picker (one canonical scale) ---------------- */
  P.openPriorityPicker = function (opts) {
    opts = opts || {};
    const values = [['无', 0, '不参与排序'], ['低', 9, '列表靠后'], ['中', 5, '默认'], ['高', 1, '列表靠前并加标记']];
    const current = Number(opts.value);
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-list">${values.map(([n, v, s]) => `<button type="button" class="proto-list-row" data-pri="${v}"><span class="grow">${n}<small>${s}</small></span>${current === v ? '<span class="proto-badge">当前</span>' : ''}</button>`).join('')}</div>`;
    const scrim = modal({ title: '优先级', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-pri]'); if (!b) return;
      scrim.remove(); opts.onPick(Number(b.dataset.pri));
    });
    return scrim;
  };

  /* ---------------- reminder anchor helpers ---------------- */
  function contextKind() {
    if (state.screen === 'new-event') return 'event';
    if (state.screen === 'detail-event') return 'event';
    if (state.drawer && state.drawer.type === 'event') return 'event';
    return 'todo';
  }
  function contextDraft() {
    if (state.screen === 'new-todo' || state.screen === 'new-event') return P.data.newDraft || null;
    if (state.draft) return state.draft;
    if (typeof activeEditRef === 'function') {
      const ref = activeEditRef();
      if (ref && typeof draftFor === 'function') return draftFor(ref);
    }
    return null;
  }
  function anchorOf(d, kind) {
    if (!d) return '';
    if (d.plan && d.plan.start) return d.plan.start;
    if (Array.isArray(d.plans)) {
      const p = d.plans.find((x) => x && x.state === 'active' && x.start);
      if (p) return p.start;
    }
    if (kind === 'event') return d.allDay ? '' : (d.start || '');
    if (d.due && d.dueTime) return d.dueTime;
    return '';
  }
  function contextAnchor() {
    return anchorOf(contextDraft(), contextKind());
  }
  function isRelativeReminder(v) {
    return !!v && v !== '不提醒' && !/^绝对/.test(v);
  }

  /* ---------------- reminder picker ---------------- */
  P.openReminderPicker = function (opts) {
    opts = opts || {};
    const hasAnchor = opts.hasAnchor === undefined ? !!contextAnchor() : !!opts.hasAnchor;
    const relative = ['准时', '5 分钟前', '15 分钟前', '30 分钟前', '1 小时前', '1 天前'];
    const cur = opts.value || '不提醒';
    const body = document.createElement('div');
    const rows = [`<button type="button" class="proto-list-row" data-remind="不提醒"><span class="grow">不提醒</span>${cur === '不提醒' ? '<span class="proto-badge">当前</span>' : ''}</button>`]
      .concat(relative.map((o) => {
        const dis = !hasAnchor;
        const on = cur === o;
        return `<button type="button" class="proto-list-row${dis ? ' proto-disabled' : ''}" data-remind="${o}" ${dis ? 'disabled title="先设置计划执行或带时刻的截止"' : ''}><span class="grow">${o}${dis ? '<small>没有时间锚点</small>' : ''}</span>${on && !dis ? '<span class="proto-badge">当前</span>' : ''}</button>`;
      }))
      .join('');
    const absCur = /^绝对/.test(cur) ? cur : '';
    body.innerHTML = `<div class="proto-list">${rows}</div>
      <div class="proto-field" style="margin-top:8px"><label>具体时间</label><button type="button" class="proto-input" data-remind-abs style="text-align:left">${absCur ? P.esc(absCur) : '选择一个具体时间…'}</button></div>
      <div class="proto-note">${hasAnchor ? '提醒锚定计划开始或截止；没有计划时相对截止。' : '还没有可锚定的时间：相对提醒需要先设置计划执行或带时刻的截止，现在只能选“不提醒”或一个具体时间。'}</div>`;
    const scrim = modal({ title: '提醒', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-remind]');
      if (b && !b.disabled) {
        scrim.remove();
        opts.onPick(b.dataset.remind === '不提醒' ? '' : b.dataset.remind);
        return;
      }
      if (e.target.closest('[data-remind-abs]')) {
        P.openTimeOfDay({
          title: '指定提醒时间', value: absCur ? absCur.replace(/^绝对\s*·\s*/, '') : '09:00',
          onPick: (v) => {
            if (!v) return;
            scrim.remove();
            opts.onPick('绝对 · ' + v);
          },
        });
      }
    });
    return scrim;
  };

  registerAction('detail-remind-custom', () => {
    const d = contextDraft(); if (!d) return;
    const kind = contextKind();
    P.openReminderPicker({
      value: d.remind, hasAnchor: !!anchorOf(d, kind),
      onPick: (r) => { d.remind = r; render(); toast(r ? '提醒 · ' + r : '已关闭提醒'); },
    });
  });

  /* Detail native <select> must not offer relative reminders without an anchor. */
  registerEnhancer((root) => {
    const sel = q('select[data-mfield="remind"]', root);
    if (!sel) return;
    const d = contextDraft();
    if (!d) return;
    const kind = contextKind();
    const hasAnchor = !!anchorOf(d, kind);
    if (d.remind && /^绝对/.test(d.remind) && !Array.from(sel.options).some((o) => o.value === d.remind)) {
      const o = document.createElement('option');
      o.value = d.remind; o.textContent = d.remind;
      sel.appendChild(o);
    }
    Array.from(sel.options).forEach((o) => {
      const absolute = o.value === '不提醒' || /^绝对/.test(o.value);
      o.disabled = !absolute && !hasAnchor;
      if (o.disabled) o.title = '先设置计划执行或带时刻的截止';
      else o.removeAttribute('title');
    });
    const wrap = sel.closest('.v2-select-row') || sel.parentNode;
    let note = wrap.parentNode.querySelector('.v2-remind-note');
    if (!hasAnchor) {
      if (!note) {
        note = document.createElement('div');
        note.className = 'v2-remind-note proto-note';
        note.style.cssText = 'margin-top:4px;font-size:9px;color:var(--amber)';
        wrap.parentNode.insertBefore(note, wrap.nextSibling);
      }
      note.textContent = '还没有可锚定的时间；相对提醒已禁用。先设置计划执行或带时刻的截止，或选一个具体时间。';
    } else if (note) {
      note.remove();
    }
  });

  /* ---------------- plan selector opened from an editor: draft only ---------------- */
  document.addEventListener('click', (e) => {
    const btn = e.target.closest && e.target.closest('[data-action="plan-submit"]');
    if (!btn) return;
    // Only intercept when the plan picker was opened from an unsaved editor draft.
    if (!state.draftKey || !state.planReturnEdit || !state.draft) return;
    const ref = typeof draftRef === 'function' ? draftRef() : null;
    if (!ref || ref.type !== 'todo') return;
    const dateEl = document.getElementById('plan-date');
    const startEl = document.getElementById('plan-start');
    const endEl = document.getElementById('plan-end');
    const date = (dateEl && dateEl.value) || state.planDate || TODAY;
    const start = (startEl && startEl.value) || state.planStart || '15:15';
    const end = (endEl && endEl.value) || state.planEnd || '16:00';
    if (mins(end) <= mins(start)) { toast('结束时间必须晚于开始时间'); e.preventDefault(); e.stopPropagation(); return; }
    const d = state.draft;
    d.plan = { date, start, end };
    // Keep the draft's allocation list in the same projection without touching
    // the persisted todo. commitDraft() is what later writes it for real.
    if (Array.isArray(d.plans) && d.plans.length) {
      const p = d.plans.find((x) => x && x.state === 'active');
      if (p) { p.date = date; p.start = start; p.end = end; }
    }
    state.planAllocId = null;
    state.planOccurrence = null;
    if (typeof restorePlan === 'function') restorePlan();
    render();
    toast('已更新计划草稿 · ' + (P.dateShort ? P.dateShort(date) : date) + ' ' + start + '–' + end);
    e.preventDefault();
    e.stopPropagation();
  }, true);
})();
