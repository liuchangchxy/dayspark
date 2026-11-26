/* DaySpark prototype v3 — shared domain model for instances, allocations and history.
   One owner only: this file defines the semantics other modules call. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
  const baseIsDone = window.isDone;
  const basePlansOn = window.plansOn;

  state.doneInstances = state.doneInstances || [];
  state.planSeq = state.planSeq || 0;
  state.skipped = state.skipped || [];

  function key(id, day) { return id + '@' + day; }
  function dateOfPlan(t) { return (t.plan && t.plan.date) || t.due || TODAY; }
  function occurrenceFor(t) {
    if (t && state.occurId === t.id && state.occurDate) return state.occurDate;
    if (t && t.__occurDate) return t.__occurDate;
    return null;
  }
  function isInstanceDone(t, day) {
    if (!t) return false;
    if (t.status === 'done') return true;
    if (!t.repeat) return baseIsDone(t);
    const d = day || occurrenceFor(t) || dateOfPlan(t);
    return state.doneInstances.includes(key(t.id, d));
  }
  function ensurePlans(t) {
    if (!t) return [];
    if (!Array.isArray(t.plans)) t.plans = t.plan ? [t.plan] : [];
    // The old single projection has no identity; give it one so it can be
    // rescheduled/cancelled like every other allocation.
    t.plans.forEach((p) => {
      if (!p) return;
      if (!p.id) p.id = 'alloc-' + (++state.planSeq);
      if (!p.state) p.state = 'active';
    });
    return t.plans;
  }
  function activePlans(t) {
    if (!t) return [];
    const all = ensurePlans(t);
    return all.filter((p) => p && p.state !== 'cancelled' && p.state !== 'invalidated');
  }
  function syncProjection(t) {
    if (!t) return;
    const list = activePlans(t);
    if (list.length) {
      // Prefer the earliest allocation still ahead of today; otherwise keep
      // the first active one, so the drawer and calendar agree on identity.
      const sorted = list.slice().sort((a, b) => (a.date + a.start).localeCompare(b.date + b.start));
      const ahead = sorted.find((p) => p.date >= TODAY);
      t.plan = ahead || sorted[0];
    } else {
      delete t.plan;
    }
  }
  function addPlan(t, spec) {
    if (!t) return null;
    ensurePlans(t);
    const alloc = {
      id: 'alloc-' + (++state.planSeq),
      date: spec.date || TODAY,
      start: spec.start,
      end: spec.end,
      occurrenceDate: t.repeat ? (spec.occurrenceDate || spec.date || TODAY) : null,
      state: 'active',
      createdAt: Date.now(),
    };
    t.plans.push(alloc);
    if (t.repeat && !t.repeatAnchor) t.repeatAnchor = alloc.occurrenceDate || alloc.date;
    syncProjection(t);
    return alloc;
  }
  function cancelPlan(t, allocId) {
    if (!t) return false;
    const p = ensurePlans(t).find((x) => x.id === allocId || x === t.plan && allocId === 'primary');
    if (!p) return false;
    p.state = 'cancelled';
    p.cancelledAt = Date.now();
    syncProjection(t);
    return true;
  }
  function invalidateAfter(t, day, boundary) {
    if (!t) return 0;
    const plans = ensurePlans(t);
    let n = 0;
    plans.forEach((p) => {
      if (!p || p.state !== 'active') return;
      // A repeating series only invalidates allocations of the completed
      // instance; other occurrences keep their schedules.
      if (t.repeat && (p.occurrenceDate || p.date) !== day) return;
      if (p.date < day) return;
      const start = String(p.start || '00:00').split(':').map(Number);
      const startMin = start[0] * 60 + start[1];
      if (p.date === day && startMin < boundary) return; // already started
      p.state = 'invalidated'; p.invalidatedAt = Date.now(); n++;
    });
    if (n) syncProjection(t);
    return n;
  }
  function nowMinutes() { return typeof NOW === 'number' ? NOW : 900; }
  function toggleDone(id, explicitDay) {
    const t = typeof todoById === 'function' ? todoById(id) : null;
    if (!t) return;
    const day = explicitDay || occurrenceFor(t) || (t.repeat ? dateOfPlan(t) : null) || TODAY;
    if (!t.repeat) {
      if (!state.done) state.done = new Set();
      if (state.done.has(id)) { state.done.delete(id); state.undoId = null; }
      else {
        state.done.add(id); state.undoId = id; state.undoName = t.title || '待办';
        invalidateAfter(t, TODAY, nowMinutes());
      }
      return;
    }
    const k = key(id, day);
    if (state.doneInstances.includes(k)) {
      state.doneInstances = state.doneInstances.filter((x) => x !== k);
      state.undoId = null;
    } else {
      state.doneInstances.push(k);
      state.undoId = id;
      state.undoName = t.title || '待办';
      state.undoInstance = day;
      // Rule: active allocations that start after this instance's completion
      // boundary stop occupying time. Already started ones keep their state.
      invalidateAfter(t, day, nowMinutes());
    }
  }
  function undoDone() {
    if (state.undoId && state.undoInstance) {
      const k = key(state.undoId, state.undoInstance);
      state.doneInstances = state.doneInstances.filter((x) => x !== k);
    } else if (state.undoId && state.done) {
      state.done.delete(state.undoId);
    }
    state.undoId = null;
    state.undoName = null;
    state.undoInstance = null;
  }
  function instanceList(t, from, to) {
    const out = [];
    if (!t || !t.repeat) return out;
    const m = P.repeatMath;
    if (!m) return out;
    const anchor = anchorOf(t);
    if (!anchor) return out;
    const start = addDays(TODAY, from), end = addDays(TODAY, to);
    let d = start;
    for (let i = 0; i < 400 && d <= end; i++) {
      if (m.repeatMatch(anchor, d, t.repeat, t)) {
        const done = state.doneInstances.includes(key(t.id, d));
        const skipped = state.skipped.includes(key(t.id, d));
        out.push({ date: d, done, skipped });
      }
      d = addDays(d, 1);
    }
    return out;
  }
  function legacy(t) { return !!(t && t.legacyRrule); }
  function anchorOf(t) {
    return t.repeatAnchor || (t.plans && t.plans.length ? t.plans.map((p) => p.date).sort()[0] : (t.plan ? t.plan.date : (t.due || t.startDate)));
  }
  // Missed = occurrences before today that are still pending: not completed,
  // not skipped, not truncated away. They stay actionable; nothing auto-skips.
  function missedInstances(t, days) {
    const out = [];
    if (!t || !t.repeat) return out;
    const m = P.repeatMath;
    if (!m) return out;
    const anchor = anchorOf(t);
    if (!anchor) return out;
    const from = addDays(TODAY, -Math.max(1, days || 30));
    const end = addDays(TODAY, -1);
    let d = anchor >= from ? anchor : from;
    for (let i = 0; i < 400 && d <= end; i++) {
      if (m.repeatMatch(anchor, d, t.repeat, t) && !state.doneInstances.includes(key(t.id, d)) && !state.skipped.includes(key(t.id, d))) {
        out.push(d);
      }
      d = addDays(d, 1);
    }
    return out;
  }
  function missedCount(t, days) { return missedInstances(t, days).length; }

  const DS3 = window.DS3 = {
    key, activePlans, addPlan, cancelPlan, invalidateAfter, syncProjection,
    toggleDone, undoDone, instanceList, isInstanceDone, occurrenceFor, legacy,
    anchorOf, missedInstances, missedCount,
    plansOf: activePlans, historyOf: (t) => (t && Array.isArray(t.plans) ? t.plans.filter((p) => p.state === 'cancelled' || p.state === 'invalidated') : []),
  };
  // Mirrored onto Proto so every module can resolve the shared model the
  // same way (and so a missing DS3 is visible instead of silently bypassed).
  P.DS3 = DS3;

  // Completion reads instance state, never the series completion field.
  window.isDone = function (t) {
    if (!t) return false;
    if (!t.repeat) return baseIsDone(t);
    return isInstanceDone(t);
  };

  // Calendar/day projections include every active allocation, not only t.plan.
  window.plansOn = function (day) {
    const out = basePlansOn(day);
    allTodos().forEach((t) => {
      if (!Array.isArray(t.plans) || !t.plans.length) return;
      // A completed instance must not hide allocations that belong to other
      // occurrences; the allocation's own state decides what occupies time.
      if (!t.repeat && isDone(t)) return;
      if (state.deletedTodos.includes(t.id) || calHidden(t.cal)) return;
      t.plans.forEach((p) => {
        if (!p || p.state !== 'active' || p.date !== day) return;
        if (out.some((x) => x.todo.id === t.id && x.start === mins(p.start) && x.end === mins(p.end))) return;
        if (out.some((x) => x.todo.id === t.id && x.todo.plan === p)) return;
        out.push({ todo: Object.assign({}, t, { plan: p, __alloc: p.id }), start: mins(p.start), end: mins(p.end) });
      });
    });
    return out;
  };

  
  // Master completion hooks (toggle-done / undo-done) call these.
  /* ---------------- surface wiring: instance history, allocations, legacy ---------------- */
  registerAction('occurrence-history', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (!t || !t.repeat) return;
    showInstances(t);
  });
  function showInstances(t) {
    const list = instanceList(t, -30, 90);
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-note" style="margin-top:0">${esc(t.title)} · ${esc(t.repeat)} · 最近 30 天与未来 90 天</div>` + (list.length ? list.map((x) => `<div class="proto-list-row"><span class="grow">${x.date}${x.done ? '<small>已完成 · 只影响这一次</small>' : x.skipped ? '<small>这一次已单独删除</small>' : '<small>待完成</small>'}</span><button type="button" class="proto-btn" data-inst="${x.date}" data-inst-act="${x.done ? 'undo' : x.skipped ? 'restore' : 'done'}">${x.done ? '撤销完成' : x.skipped ? '恢复这一次' : '完成这一次'}</button></div>`).join('') : '<div class="proto-note">这个系列还没有实例。</div>');
    const scrim = modal({ title: '重复实例', body, actions: [{ label: '关闭' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-inst]'); if (!b) return;
      const day = b.dataset.inst, act = b.dataset.instAct;
      if (act === 'done') toggleDone(t.id, day);
      else if (act === 'undo') state.doneInstances = state.doneInstances.filter((k) => k !== key(t.id, day));
      else if (act === 'restore') state.skipped = state.skipped.filter((k) => k !== key(t.id, day));
      scrim.remove(); render(); toast(act === 'done' ? '已完成 ' + day + ' 这一次' : act === 'undo' ? '已撤销 ' + day + ' 的完成' : '已恢复 ' + day);
      showInstances(t);
    });
    return scrim;
  }
  P.showInstances = showInstances;

  registerAction('alloc-open', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (!t) return;
    const body = document.createElement('div');
    function paint() {
      const all = ensurePlans(t);
      body.className = 'proto-list';
      body.innerHTML = all.length ? all.map((p) => {
        const label = p.state === 'cancelled' ? '已取消 · 待办保留' : p.state === 'invalidated' ? '实例完成后失效' : '进行中';
        return `<div class="proto-list-row"><span class="grow">${p.date} ${p.start}–${p.end}<small>${label}${p.occurrenceDate ? ' · 实例 ' + p.occurrenceDate : ''}</small></span>${p.state === 'active' ? `<button type="button" class="proto-btn" data-edit="${p.id}">改期</button><button type="button" class="proto-btn" data-cancel="${p.id}">取消</button>` : ''}</div>`;
      }).join('') : '<div class="proto-note">还没有计划执行。用「安排时间」新建一段。</div>';
      body.innerHTML += '<button type="button" class="proto-btn" data-add style="margin-top:8px">＋ 再安排一段</button>';
    }
    paint();
    const scrim = modal({ title: '计划执行 · ' + t.title, body, actions: [{ label: '关闭' }] });
    body.addEventListener('click', (e) => {
      const add = e.target.closest('[data-add]');
      const ed = e.target.closest('[data-edit]');
      const cx = e.target.closest('[data-cancel]');
      if (add) {
        scrim.remove();
        state.planTodoId = t.id;
        const back = { screen: state.screen, variant: state.variant, drawer: state.drawer, edit: state.drawerEdit };
        P.baseGo('plan-picker');
        state.planReturn = back.screen; state.planReturnVariant = back.variant;
        state.planReturnDrawer = back.drawer; state.planReturnEdit = !!back.edit;
        state.planAllocId = null;
        state.planOccurrence = t.repeat ? (occurrenceFor(t) || state.selectedDate || TODAY) : null;
        render();
        return;
      }
      if (ed) {
        const p = t.plans.find((x) => x.id === ed.dataset.edit); if (!p) return;
        scrim.remove();
        const back = { screen: state.screen, variant: state.variant, drawer: state.drawer, edit: state.drawerEdit };
        P.baseGo('plan-picker');
        state.planTodoId = t.id; state.planAllocId = p.id;
        state.planOccurrence = p.occurrenceDate || state.planOccurrence || null;
        state.planDate = p.date; state.planStart = p.start; state.planEnd = p.end;
        state.planReturn = back.screen; state.planReturnVariant = back.variant;
        state.planReturnDrawer = back.drawer; state.planReturnEdit = !!back.edit;
        render();
        return;
      }
      if (cx) {
        cancelPlan(t, cx.dataset.cancel); paint(); render(); toast('已取消这一段计划执行 · 待办保留');
      }
    });
  });

  // Legacy series: explain and migrate explicitly instead of reinterpreting.
  registerAction('legacy-migrate', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (!t) return;
    modal({
      title: '这条重复规则需要确认',
      body: `<div class="proto-note">「${esc(t.title)}」来自旧版本，只存了一条旧规则（${esc(t.legacyRrule || t.repeat || '未知')}），没有可确认的锚点日期和结束条件。确认后才会写入新的重复规则；确认前不会改写它。</div>`,
      actions: [
        { label: '稍后再说' },
        { label: '保留为旧规则', onClick: () => { t.legacyConfirmed = true; render(); toast('已保留为旧规则 · 不做迁移'); } },
        { label: '写入新规则', primary: true, onClick: () => {
          P.openRepeatPicker({ repeat: '', onPick: (r, end, extra) => {
            if (!r) { toast('先选一个重复方式'); return; }
            t.repeat = r; t.repeatEnd = end; t.repeatUntil = (extra && extra.until) || ''; t.repeatCount = (extra && extra.count) || 0;
            t.repeatAnchor = t.plans && t.plans.length ? t.plans[0].date : (t.due || TODAY);
            delete t.legacyRrule; t.legacyConfirmed = true;
            render(); toast('已写入新重复规则 · ' + r);
          } });
        } },
      ],
    });
  });

  /* Drawer affordances: instance completion/history, multi-allocation list, legacy. */
  registerEnhancer((root) => {
    const ref = state.drawer;
    if (!ref || ref.type !== 'todo') return;
    const t = todoById(ref.id);
    if (!t) return;
    const editing = !!state.drawerEdit;
    // Completing a repeating todo must name the instance, not the series.
    qa('[data-action="toggle-done"]', root).forEach((b) => {
      if (t.repeat) {
        const day = occurrenceFor(t) || state.selectedDate || TODAY;
        b.dataset.date = day;
        if (!b.dataset.v3inst) {
          b.dataset.v3inst = '1';
          if (!editing) b.title = '只完成 ' + day + ' 这一次';
        }
      }
    });
    if (t.repeat && !editing && !q('[data-proto-action="occurrence-history"]', root)) {
      const host = q('.d-sec, .field-list', root);
      if (host) {
        const row = document.createElement('div');
        row.className = 'field-row';
        row.innerHTML = '<span class="f-label">重复实例</span><span class="f-value"><button type="button" class="mini" data-proto-action="occurrence-history" data-id="' + esc(t.id) + '">查看实例 / 遗漏</button></span>';
        host.appendChild(row);
      }
    }
    const plans = activePlans(t);
    if (!editing && plans.length && !q('[data-proto-action="alloc-open"]', root)) {
      const fr = qa('.field-row', root).find((r) => (q('.f-label', r) || {}).textContent === '计划执行');
      if (fr) {
        const v = q('.f-value', fr);
        v.innerHTML = v.innerHTML + ' <button type="button" class="mini" data-proto-action="alloc-open" data-id="' + esc(t.id) + '">' + (plans.length > 1 ? '共 ' + plans.length + ' 段' : '再安排一段') + '</button>';
      }
    }
    if ((t.legacyRrule) && !t.legacyConfirmed && !q('[data-proto-action="legacy-migrate"]', root)) {
      const body = q('.drawer-body', root);
      if (body) {
        const box = document.createElement('div');
        box.className = 'inline-alert';
        box.style.margin = '10px 0';
        box.innerHTML = '<b>这条重复规则来自旧版本。</b><br>确认后才写入新规则；确认前不改写它。<button type="button" class="mini-btn" style="margin-left:8px" data-proto-action="legacy-migrate" data-id="' + esc(t.id) + '">确认并迁移</button>';
        body.insertBefore(box, body.children[3] || null);
      }
    }
  });

  P.toggleDoneV3 = toggleDone;
  window.__v3ToggleDone = function (id, day) { toggleDone(id, day); };
  window.__v3UndoDone = function () { undoDone(); };
})();
