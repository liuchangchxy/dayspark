/* DaySpark prototype v3 — shared domain model for instances, allocations and history.
   One owner only: this file defines the semantics other modules call. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
  const baseIsDone = window.isDone;

  state.doneInstances = state.doneInstances || [];
  state.planSeq = state.planSeq || 0;
  state.skipped = state.skipped || [];

  function key(id, day) { return id + '@' + day; }
  function occurrenceFor(t) {
    if (t && state.occurId === t.id && state.occurDate) return state.occurDate;
    if (t && t.__occurDate) return t.__occurDate;
    return null;
  }
  function mark(obj, name, value) {
    try { Object.defineProperty(obj, name, { value, writable: true, configurable: true, enumerable: false }); }
    catch (_) { obj[name] = value; }
  }
  function newAllocId() { return 'alloc-' + (++state.planSeq); }
  function nowMinutes() { return typeof NOW === 'number' ? NOW : 900; }
  function allocStatusLabel(p) {
    const st = allocationStatus(p);
    return { upcoming: '即将开始', ongoing: '进行中', ended: '已结束', cancelled: '已取消 · 待办保留', invalidated: '实例完成后失效' }[st] || st;
  }

  /* ---------------- allocation model ---------------- */
  // t.plan is a derived projection. Allocations are the source of truth.
  function normalizeAllocation(t, p) {
    if (!p || typeof p !== 'object') return null;
    if (!p.id) p.id = newAllocId();
    if (!p.state) p.state = 'active';
    if (!p.createdAt) p.createdAt = Date.now();
    if (t && t.repeat) {
      // A legacy series-level plan is projected onto every occurrence; it
      // must not claim one occurrence as its identity. Explicit allocations
      // always arrive with occurrenceDate from addAllocation.
      if (p.legacy) p.occurrenceDate = null;
      else if (p.occurrenceDate === undefined) p.occurrenceDate = null;
    } else if (p.occurrenceDate === undefined) {
      p.occurrenceDate = null;
    }
    return p;
  }
  function ensureAllocations(t) {
    if (!t) return [];
    if (!Array.isArray(t.plans)) {
      t.plans = [];
      if (t.plan && t.plan.date && t.plan.start != null) {
        // A legacy single plan has no identity. Give it one once, and tag it so
        // an untouched repeating series keeps its old projection behaviour.
        const legacy = normalizeAllocation(t, Object.assign({}, t.plan, { legacy: true }));
        t.plans.push(legacy);
      }
    }
    const seen = new Set();
    t.plans.forEach((p) => {
      if (!p) return;
      normalizeAllocation(t, p);
      if (seen.has(p.id)) p.id = newAllocId();
      seen.add(p.id);
    });
    adoptExternalPlan(t);
    return t.plans;
  }
  // A few older entry points still assign t.plan directly. Fold a single
  // non-repeating assignment into the one allocation it can refer to; never
  // guess which allocation a repeating assignment means.
  function adoptExternalPlan(t) {
    const plan = t.plan;
    if (!plan || !plan.date || plan.start == null) return;
    if (t.plans.indexOf(plan) >= 0) return;
    if (t.__externalPlan === plan) return;
    mark(t, '__externalPlan', plan);
    if (t.repeat) return;
    const active = t.plans.filter((p) => p && p.state === 'active');
    if (active.length === 1) {
      active[0].date = plan.date;
      active[0].start = plan.start;
      active[0].end = plan.end;
      return;
    }
    if (!active.length) {
      t.plans.push(normalizeAllocation(t, {
        id: newAllocId(), date: plan.date, start: plan.start, end: plan.end,
        state: 'active', createdAt: Date.now(),
      }));
    }
  }
  function allocations(t) {
    return t ? ensureAllocations(t) : [];
  }
  function activeAllocations(t) {
    return allocations(t).filter((p) => p && p.state === 'active');
  }
  function planById(t, id) {
    if (!t || !id) return null;
    return allocations(t).find((p) => p && p.id === id) || null;
  }
  function addAllocation(t, spec) {
    spec = spec || {};
    if (!t || !spec.start || !spec.end) return null;
    // A repeating todo's allocation must name the occurrence it belongs to.
    if (t.repeat && !spec.occurrenceDate) return null;
    ensureAllocations(t);
    const alloc = normalizeAllocation(t, {
      id: newAllocId(),
      date: spec.date || TODAY,
      start: spec.start,
      end: spec.end,
      occurrenceDate: t.repeat ? spec.occurrenceDate : null,
      state: 'active',
      createdAt: Date.now(),
    });
    t.plans.push(alloc);
    // Never derive a series anchor from an allocation (problem: guessing).
    syncProjection(t);
    return alloc;
  }
  function updateAllocation(t, id, spec) {
    spec = spec || {};
    if (!t || !id) return false;
    const p = allocations(t).find((x) => x && x.id === id);
    if (!p || p.state !== 'active') return false;
    if (spec.date) p.date = spec.date;
    if (spec.start) p.start = spec.start;
    if (spec.end) p.end = spec.end;
    // It is now explicitly managed, so the legacy repeat projection no longer
    // owns it. occurrenceDate is intentionally left untouched: identity is the
    // instance it was created for.
    delete p.legacy;
    syncProjection(t);
    return true;
  }
  function cancelAllocation(t, id) {
    if (!t || !id) return false;
    const p = allocations(t).find((x) => x && x.id === id);
    if (!p || p.state !== 'active') return false;
    p.state = 'cancelled';
    p.cancelledAt = Date.now();
    syncProjection(t);
    return true;
  }
  function invalidateAfter(t, occurrenceDay, boundary) {
    if (!t) return 0;
    const limit = typeof boundary === 'number' ? boundary : nowMinutes();
    let n = 0;
    allocations(t).forEach((p) => {
      if (!p || p.state !== 'active') return;
      if (t.repeat) {
        if (!occurrenceDay) return;
        // The legacy series plan is one shared display record, not an
        // allocation of this occurrence; completion must not invalidate it.
        if (p.legacy) return;
        const occ = p.occurrenceDate || p.date;
        if (occ !== occurrenceDay) return;
        if (p.date < occurrenceDay) return;
        if (p.date === occurrenceDay && mins(p.start) < limit) return;
      } else {
        if (p.date > TODAY) { /* a future day is after now */ }
        else if (p.date === TODAY) { if (mins(p.start) < limit) return; }
        else return;
      }
      p.state = 'invalidated';
      p.invalidatedAt = Date.now();
      n++;
    });
    if (n) syncProjection(t);
    return n;
  }
  function syncProjection(t) {
    if (!t) return null;
    const active = activeAllocations(t);
    if (!active.length) { delete t.plan; return null; }
    const sorted = active.slice().sort((a, b) => {
      if (a.date !== b.date) return a.date < b.date ? -1 : 1;
      return mins(a.start) - mins(b.start);
    });
    const ahead = sorted.find((p) => p.date >= TODAY);
    const chosen = ahead || sorted[0];
    t.plan = chosen;
    return chosen;
  }
  function allocationStatus(p, nowVal) {
    if (!p) return 'upcoming';
    if (p.state === 'cancelled') return 'cancelled';
    if (p.state === 'invalidated') return 'invalidated';
    if (!p.date) return 'upcoming';
    if (p.date < TODAY) return 'ended';
    if (p.date > TODAY) return 'upcoming';
    const now = typeof nowVal === 'number' ? nowVal : nowMinutes();
    const start = mins(p.start);
    const end = mins(p.end);
    if (end <= now) return 'ended';
    if (start <= now && now < end) return 'ongoing';
    if (start > now) return 'upcoming';
    return 'upcoming';
  }

  /* ---------------- occurrence helpers ---------------- */
  // Only explicit series facts may anchor a series. Plans are not anchors.
  function anchorOf(t) {
    if (!t) return null;
    return t.repeatAnchor || t.seriesStart || t.due || t.startDate || null;
  }
  // Called when the user is creating a new repeating series (creating=true).
  // Never derives from an allocation.
  function ensureSeriesAnchor(t, opts) {
    if (!t) return null;
    const existing = t.repeatAnchor || t.seriesStart || t.due || t.startDate;
    if (existing) { if (!t.repeatAnchor) t.repeatAnchor = existing; return existing; }
    const creating = opts === true || (opts && opts.creating);
    if (creating) { t.repeatAnchor = TODAY; return TODAY; }
    return null;
  }
  function occurrenceDays(t, from, to) {
    const out = [];
    if (!t || !t.repeat) return out;
    const m = P.repeatMath;
    const anchor = anchorOf(t);
    if (!m || !anchor) return out;
    const start = addDays(TODAY, from), end = addDays(TODAY, to);
    let d = start;
    for (let i = 0; i < 500 && d <= end; i++) {
      if (m.repeatMatch(anchor, d, t.repeat, t)) out.push(d);
      d = addDays(d, 1);
    }
    return out;
  }
  // Explicit instance picker: recent 30 days + future 90 days. Nothing is
  // selected by default and onPick runs only after a real click.
  function requireOccurrence(t, onPick, opts) {
    opts = opts || {};
    if (!t) return null;
    const pick = typeof onPick === 'function' ? onPick : function () {};
    const days = occurrenceDays(t, -30, 90);
    const body = document.createElement('div');
    const anchor = anchorOf(t);
    body.innerHTML = `<div class="proto-note" style="margin-top:0">${esc(t.title)}${anchor ? ' · 锚点 ' + esc(anchor) : ''} · 最近 30 天与未来 90 天</div>`
      + (days.length
        ? `<div class="proto-list">${days.map((d) => {
          const done = state.doneInstances.includes(key(t.id, d));
          const skipped = state.skipped.includes(key(t.id, d));
          return `<button type="button" class="proto-list-row" data-occ="${d}"><span class="grow">${d} · ${weekday(d)}<small>${done ? '已完成 · 只影响这一次' : skipped ? '这一次已单独删除' : '待完成'}</small></span></button>`;
        }).join('')}</div>`
        : '<div class="proto-note">这个系列还没有可确认的实例：先确认系列锚点。</div>')
      + '<div class="proto-note">必须明确选择某一天；不会默认今天、所选日期或计划日期。</div>';
    const scrim = modal({ title: opts.title || '选择这一次实例', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-occ]');
      if (!b) return;
      const day = b.dataset.occ;
      scrim.remove();
      pick(day);
    });
    return scrim;
  }

  /* ---------------- completion ---------------- */
  function isInstanceDone(t, day) {
    if (!t) return false;
    if (!t.repeat) return baseIsDone(t);
    const d = day || occurrenceFor(t);
    if (!d) return false; // no explicit instance -> not completed
    return state.doneInstances.includes(key(t.id, d));
  }
  function clearUndo() {
    state.undoId = null;
    state.undoName = null;
    state.undoInstance = null;
    state.undoKind = null;
  }
  function toggleDone(id, explicitDay) {
    const t = typeof todoById === 'function' ? todoById(id) : null;
    if (!t) return false;
    if (t.repeat) {
      let day = explicitDay || null;
      if (!day && state.occurId === t.id && state.occurDate) day = state.occurDate;
      if (!day) {
        // Refuse to guess TODAY / selectedDate / plan date. Ask which instance.
        requireOccurrence(t, (picked) => toggleDone(id, picked), { title: '完成哪一次 · ' + t.title });
        return false;
      }
      const k = key(id, day);
      if (state.doneInstances.includes(k)) {
        state.doneInstances = state.doneInstances.filter((x) => x !== k);
        clearUndo();
        return true;
      }
      state.doneInstances.push(k);
      state.undoId = id;
      state.undoName = t.title || '待办';
      state.undoInstance = day;
      state.undoKind = 'instance';
      // Segments of this instance that start after the completion boundary no
      // longer occupy time. Already-started segments keep their state.
      invalidateAfter(t, day, nowMinutes());
      return true;
    }
    if (!state.done) state.done = new Set();
    const completed = state.done.has(id) || t.status === 'done';
    if (completed) {
      state.done.delete(id);
      if (t.status === 'done') {
        t.status = 'open';
        delete t.completed;
        delete t.completedAt;
      }
      clearUndo();
      return true;
    }
    state.done.add(id);
    state.undoId = id;
    state.undoName = t.title || '待办';
    state.undoInstance = null;
    state.undoKind = 'todo';
    invalidateAfter(t, null, nowMinutes());
    return true;
  }
  function undoDone() {
    if (state.undoKind === 'instance' && state.undoId && state.undoInstance) {
      const k = key(state.undoId, state.undoInstance);
      state.doneInstances = state.doneInstances.filter((x) => x !== k);
      // Invalidated allocations stay invalidated: undo completion is not an
      // undo of the scheduling consequence.
    } else if (state.undoId) {
      if (state.done) state.done.delete(state.undoId);
      const t = typeof todoById === 'function' ? todoById(state.undoId) : null;
      if (t && t.status === 'done') {
        t.status = 'open';
        delete t.completed;
        delete t.completedAt;
      }
    }
    clearUndo();
  }

  /* ---------------- projections ---------------- */
  function instanceList(t, from, to) {
    const out = [];
    if (!t || !t.repeat) return out;
    occurrenceDays(t, from, to).forEach((d) => {
      out.push({
        date: d,
        done: state.doneInstances.includes(key(t.id, d)),
        skipped: state.skipped.includes(key(t.id, d)),
      });
    });
    return out;
  }
  function legacy(t) { return !!(t && t.legacyRrule); }
  // Missed = occurrences before today that are still pending: not completed,
  // not skipped, not truncated away. They stay actionable; nothing auto-skips.
  function missedInstances(t, days, offset) {
    const out = [];
    if (!t || !t.repeat) return out;
    const span = Math.max(1, days || 30);
    const skip = Math.max(0, offset || 0);
    const from = -(skip + span);
    const to = -skip - 1;
    occurrenceDays(t, from, to).forEach((d) => {
      if (!state.doneInstances.includes(key(t.id, d)) && !state.skipped.includes(key(t.id, d))) out.push(d);
    });
    return out;
  }
  function missedCount(t, days) { return missedInstances(t, days).length; }

  const DS3 = window.DS3 = {
    allocations, activeAllocations, planById,
    addAllocation, updateAllocation, cancelAllocation,
    invalidateAfter, syncProjection, allocationStatus,
    requireOccurrence, ensureSeriesAnchor,
    // Compatibility aliases for the other prototype layers.
    addPlan: addAllocation, cancelPlan: cancelAllocation,
    activePlans: activeAllocations, plansOf: activeAllocations,
    historyOf: (t) => allocations(t).filter((p) => p && (p.state === 'cancelled' || p.state === 'invalidated')),
    key, toggleDone, undoDone, instanceList, isInstanceDone, occurrenceFor,
    legacy, anchorOf, missedInstances, missedCount,
  };
  P.DS3 = DS3;

  // Completion reads instance state, never the series completion field.
  window.isDone = function (t) {
    if (!t) return false;
    if (!t.repeat) return baseIsDone(t);
    return isInstanceDone(t);
  };

  // ONE day projection. Allocation-aware todos project each allocation on its
  // own date with its own identity; an untouched legacy repeating todo keeps
  // the old "repeat the single plan" behaviour.
  window.plansOn = function (day) {
    const out = [];
    const m = P.repeatMath;
    allTodos().forEach((t) => {
      if (!t || state.deletedTodos.includes(t.id) || calHidden(t.cal)) return;
      const raw = Array.isArray(t.plans) ? t.plans : [];
      const explicit = raw.some((p) => p && !p.legacy);
      if (raw.length && (explicit || !t.repeat)) {
        // A completed non-repeat todo has no blocks; a repeating todo is
        // governed by each allocation's own state.
        if (!t.repeat && isDone(t)) return;
        activeAllocations(t).forEach((p) => {
          if (!p || p.date !== day) return;
          out.push({
            todo: Object.assign({}, t, { plan: p }),
            start: mins(p.start),
            end: mins(p.end),
            allocId: p.id,
            __alloc: p.id,
          });
        });
        return;
      }
      if (!t.plan || !t.plan.date) return;
      if (!t.repeat) {
        if (isDone(t) || t.plan.date !== day) return;
        // Normalize the id-less legacy plan once so the block can carry a
        // stable allocation identity even before the user edits it.
        const list = allocations(t);
        const p = list.find((x) => x && x.state === 'active') || list[0] || null;
        out.push({
          todo: Object.assign({}, t, p ? { plan: p } : {}),
          start: mins(p ? p.start : t.plan.start),
          end: mins(p ? p.end : t.plan.end),
          allocId: p ? p.id : null,
        });
        return;
      }
      if (!m || !m.repeatMatch(t.plan.date, day, t.repeat, t)) return;
      if (state.skipped.includes(key(t.id, day))) return;
      if (state.doneInstances.includes(key(t.id, day))) return;
      const list = allocations(t);
      const legacyAlloc = list.find((x) => x && x.legacy) || list[0] || null;
      out.push({
        todo: Object.assign({}, t, { plan: Object.assign({}, t.plan, { date: day }) }),
        start: mins(t.plan.start),
        end: mins(t.plan.end),
        allocId: legacyAlloc ? legacyAlloc.id : (t.plan.id || null),
      });
    });
    return out;
  };

  /* ---------------- surface wiring: instance history, allocations, legacy ---------------- */
  registerAction('occurrence-history', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (!t || !t.repeat) return;
    showInstances(t);
  });
  function showInstances(t) {
    const list = instanceList(t, -30, 90);
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-note" style="margin-top:0">${esc(t.title)} · ${esc(t.repeat)} · 最近 30 天与未来 90 天</div>` + (list.length ? list.map((x) => `<div class="proto-list-row"><span class="grow">${x.date} · ${weekday(x.date)}${x.done ? '<small>已完成 · 只影响这一次</small>' : x.skipped ? '<small>这一次已单独删除</small>' : '<small>待完成</small>'}</span><button type="button" class="proto-btn" data-inst="${x.date}" data-inst-act="${x.done ? 'undo' : x.skipped ? 'restore' : 'done'}">${x.done ? '撤销完成' : x.skipped ? '恢复这一次' : '完成这一次'}</button></div>`).join('') : '<div class="proto-note">这个系列还没有实例。</div>');
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

  function openPlanScreen(t, alloc, editing, occurrence, date, start, end) {
    const back = { screen: state.screen, variant: state.variant, drawer: state.drawer, edit: state.drawerEdit };
    P.baseGo('plan-picker');
    state.planTodoId = t.id;
    state.planAllocId = alloc ? alloc.id : null;
    state.planOccurrence = t.repeat ? (occurrence || (alloc && alloc.occurrenceDate) || null) : null;
    state.planDate = date || (alloc && alloc.date) || TODAY;
    state.planStart = start || (alloc && alloc.start) || '15:15';
    state.planEnd = end || (alloc && alloc.end) || '16:00';
    state.planReturn = back.screen;
    state.planReturnVariant = back.variant;
    state.planReturnDrawer = back.drawer;
    state.planReturnEdit = !!back.edit;
    state.variant = editing ? 'edit' : 'normal';
    render();
  }

  registerAction('alloc-open', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (!t) return;
    const body = document.createElement('div');
    function paint() {
      const all = allocations(t);
      const active = all.filter((p) => p && p.state === 'active');
      body.className = 'proto-list';
      body.innerHTML = (all.length ? all.map((p) => {
        const label = allocStatusLabel(p);
        return `<div class="proto-list-row"><span class="grow">${p.date} ${p.start}–${p.end}<small>${label}${p.occurrenceDate && t.repeat ? ' · 实例 ' + p.occurrenceDate : ''}</small></span>${p.state === 'active' ? `<button type="button" class="proto-btn" data-edit="${p.id}">改期</button><button type="button" class="proto-btn" data-cancel="${p.id}">取消</button>` : ''}</div>`;
      }).join('') : '<div class="proto-note">还没有计划执行。用「安排时间」新建一段。</div>')
        + (all.length && !active.length ? '<div class="proto-note">没有进行中的计划；下面的历史仍然保留。</div>' : '')
        + '<button type="button" class="proto-btn" data-add style="margin-top:8px">＋ 再安排一段</button>'
        + (t.repeat ? '<button type="button" class="proto-btn" data-history style="margin-top:8px">查看实例历史</button>' : '');
    }
    paint();
    const scrim = modal({ title: '计划执行 · ' + t.title, body, actions: [{ label: '关闭' }] });
    body.addEventListener('click', (e) => {
      const add = e.target.closest('[data-add]');
      const ed = e.target.closest('[data-edit]');
      const cx = e.target.closest('[data-cancel]');
      const hi = e.target.closest('[data-history]');
      if (add) {
        scrim.remove();
        if (t.repeat) {
          requireOccurrence(t, (day) => {
            openPlanScreen(t, null, false, day, day, (t.plan && t.plan.start) || '15:15', (t.plan && t.plan.end) || '16:00');
          }, { title: '安排哪一次 · ' + t.title });
          return;
        }
        openPlanScreen(t, null, false, null, (t.plan && t.plan.date) || TODAY, (t.plan && t.plan.start) || '15:15', (t.plan && t.plan.end) || '16:00');
        return;
      }
      if (ed) {
        const p = allocations(t).find((x) => x.id === ed.dataset.edit);
        if (!p) return;
        scrim.remove();
        openPlanScreen(t, p, true, p.occurrenceDate || null, p.date, p.start, p.end);
        return;
      }
      if (cx) {
        cancelAllocation(t, cx.dataset.cancel);
        paint(); render();
        toast('已取消这一段计划执行 · 待办保留');
        return;
      }
      if (hi) { scrim.remove(); showInstances(t); }
    });
  });

  // Legacy series: explain and migrate explicitly instead of reinterpreting.
  registerAction('legacy-migrate', (el) => {
    const t = todoById(el.dataset.id || (state.drawer && state.drawer.id) || '');
    if (!t) return;
    const zones = ['Asia/Shanghai', 'Asia/Tokyo', 'Europe/London', 'America/New_York', 'UTC'];
    let timezone = t.repeatTimezone || '';
    let anchor = t.repeatAnchor || '';
    let rule = '';
    let repeatEnd = t.repeatEnd || '永不结束';
    let repeatUntil = t.repeatUntil || '';
    let repeatCount = t.repeatCount || 0;
    const body = document.createElement('div');
    function paint() {
      body.innerHTML = `<div class="proto-note" style="margin-top:0">「${esc(t.title)}」来自旧版本，只存了一条旧规则（${esc(t.legacyRrule || t.repeat || '未知')}），没有可确认的时区、锚点日期和结束条件。确认后才会写入新的重复规则；确认前不会改写它。</div>
        <div class="proto-field"><label>时区</label><select class="proto-input" id="legacy-tz"><option value="">选择时区</option>${zones.map((z) => `<option value="${esc(z)}" ${timezone === z ? 'selected' : ''}>${esc(z)}</option>`).join('')}</select></div>
        <div class="proto-field"><label>系列锚点日期</label><input type="date" class="proto-input" id="legacy-anchor" value="${esc(anchor)}"></div>
        <div class="proto-field"><label>重复规则</label><button type="button" class="proto-input" data-legacy-rule style="text-align:left">${esc(rule ? rule + (repeatEnd && repeatEnd !== '永不结束' ? ' · ' + repeatEnd : '') : '选择重复规则')}</button></div>
        <div class="proto-note">时区、锚点日期和重复规则三项都确认后才会写入。</div>`;
    }
    paint();
    const scrim = modal({
      title: '这条重复规则需要确认',
      body,
      actions: [
        { label: '取消' },
        { label: '保留为旧规则', onClick: () => { t.legacyConfirmed = true; render(); toast('已保留为旧规则 · 不做迁移'); } },
        { label: '写入新规则', primary: true, onClick: () => {
          const tzEl = q('#legacy-tz', body);
          const anchorEl = q('#legacy-anchor', body);
          timezone = tzEl ? tzEl.value : '';
          anchor = anchorEl ? (anchorEl.value || '').trim() : '';
          if (!timezone || !anchor || !rule) {
            toast('时区、锚点日期和重复规则都要选');
            return true; // keep the dialog open
          }
          t.repeat = rule;
          t.repeatAnchor = anchor;
          t.repeatTimezone = timezone;
          t.repeatEnd = repeatEnd || '永不结束';
          t.repeatUntil = repeatUntil || '';
          t.repeatCount = repeatCount || 0;
          delete t.legacyRrule;
          t.legacyConfirmed = true;
          render();
          toast('已写入新重复规则 · ' + rule + ' · ' + timezone);
        } },
      ],
    });
    body.addEventListener('click', (e) => {
      if (!e.target.closest('[data-legacy-rule]')) return;
      // Preserve what the user already typed before repainting the dialog.
      const tzEl = q('#legacy-tz', body);
      const anchorEl = q('#legacy-anchor', body);
      if (tzEl) timezone = tzEl.value;
      if (anchorEl) anchor = (anchorEl.value || '').trim();
      P.openRepeatPicker({
        repeat: rule, repeatEnd, repeatUntil, repeatCount,
        onPick: (r, end, extra) => {
          if (!r) { toast('先选一个重复方式'); return; }
          rule = r;
          repeatEnd = end || '永不结束';
          repeatUntil = (extra && extra.until) || '';
          repeatCount = (extra && extra.count) || 0;
          paint();
        },
      });
    });
    return scrim;
  });

  /* ---------------- drawer affordances ---------------- */
  function setCompleteText(b, label) {
    if (!b.classList.contains('d-complete')) return;
    const check = b.querySelector('.check');
    b.textContent = '';
    if (check) b.appendChild(check);
    b.appendChild(document.createTextNode(label));
  }
  function decorateCompletion(root, t, boundDay) {
    qa('[data-action="toggle-done"]', root).forEach((b) => {
      const id = b.dataset.id;
      if (!id) return;
      const todo = t && t.id === id ? t : todoById(id);
      if (!todo || !todo.repeat) return;
      const bound = boundDay || (state.occurId === todo.id && state.occurDate) || null;
      if (bound) {
        b.dataset.date = bound;
        const done = state.doneInstances.includes(key(todo.id, bound));
        b.title = '只完成 ' + bound + ' 这一次';
        b.setAttribute('aria-label', '完成 ' + bound + ' 这一次');
        setCompleteText(b, done ? '本次已完成' : '完成这一次');
      } else {
        delete b.dataset.date;
        b.title = '选择这一次实例';
        b.setAttribute('aria-label', '选择这一次实例');
        setCompleteText(b, '选择这一次实例');
      }
    });
  }

  registerEnhancer((root) => {
    const ref = state.drawer;
    const t = ref && ref.type === 'todo' ? todoById(ref.id) : null;
    if (!t) return;
    const editing = !!state.drawerEdit;
    const allAllocs = allocations(t);
    const active = allAllocs.filter((p) => p && p.state === 'active');
    const history = allAllocs.filter((p) => p && (p.state === 'cancelled' || p.state === 'invalidated'));
    // Completion controls name the instance only when the user explicitly
    // opened that instance; otherwise they ask instead of guessing.
    decorateCompletion(root, t, null);
    if (t.repeat && !editing && !q('[data-proto-action="occurrence-history"]', root)) {
      const host = q('.d-sec, .field-list, .m-form', root);
      if (host) {
        const row = document.createElement('div');
        // Desktop uses field-row; the phone drawer renders m-form-row.
        row.className = root.querySelector('.m-detail-scroll') ? 'm-form-row' : 'field-row';
        row.innerHTML = (row.className === 'm-form-row'
          ? '<span class="m-form-label">重复实例</span><span class="m-form-value"><button type="button" class="mini" data-proto-action="occurrence-history" data-id="'
          : '<span class="f-label">重复实例</span><span class="f-value"><button type="button" class="mini" data-proto-action="occurrence-history" data-id="')
          + esc(t.id) + '">查看实例 / 遗漏</button></span>';
        host.appendChild(row);
      }
    }
    if (!editing && allAllocs.length && !q('[data-proto-action="alloc-open"]', root)) {
      const fr = qa('.field-row, .m-form-row', root).find((r) => ((q('.f-label, .m-form-label', r) || {}).textContent || '').trim() === '计划执行');
      if (fr) {
        const b = document.createElement('button');
        b.type = 'button'; b.className = 'mini';
        b.dataset.protoAction = 'alloc-open'; b.dataset.id = t.id;
        b.textContent = active.length > 1 ? '查看全部' : active.length === 1 ? '再安排一段' : (history.length ? '查看历史与再安排' : '再安排一段');
        const v = q('.f-value, .m-form-value', fr);
        if (v) { v.appendChild(document.createTextNode(' ')); v.appendChild(b); } else fr.appendChild(b);
      }
    }
    if ((t.legacyRrule) && !t.legacyConfirmed && !q('[data-proto-action="legacy-migrate"]', root)) {
      const bodyEl = q('.drawer-body, .m-detail-scroll', root);
      if (bodyEl) {
        const box = document.createElement('div');
        box.className = 'inline-alert';
        box.style.margin = '10px 0';
        box.innerHTML = '<b>这条重复规则来自旧版本。</b><br>确认后才写入新规则；确认前不改写它。<button type="button" class="mini-btn" style="margin-left:8px" data-proto-action="legacy-migrate" data-id="' + esc(t.id) + '">确认并迁移</button>';
        bodyEl.insertBefore(box, bodyEl.children[3] || null);
      }
    }
  });

  // Rows outside the drawer also need the explicit-instance affordance.
  registerEnhancer((root) => {
    decorateCompletion(root, null, null);
  });

  P.toggleDoneV3 = toggleDone;
  window.__v3ToggleDone = function (id, day) { return toggleDone(id, day); };
  window.__v3UndoDone = function () { undoDone(); };
})();
