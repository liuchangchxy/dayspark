/* DaySpark prototype v3 — data integrity layer.
   Round 3: trash is really permanent, restore keeps skipped instances, ICS
   round-trips full fields (time / end / cross-midnight / recurrence), and
   localStorage failures become a visible, retryable banner. */
(function () {
  'use strict';
  const P = window.Proto;
  const registerAction = P.registerAction;
  const registerEnhancer = P.registerEnhancer;
  const modal = P.modal;
  const toast = P.toast;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = P.esc || ((s) => String(s == null ? '' : s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m])));
  const clone = (v) => JSON.parse(JSON.stringify(v));
  const TODAY_ISO = () => (typeof TODAY !== 'undefined' ? TODAY : '2026-11-20');

  /* ------------------------------------------------------------------ *
   * 1. Persistence guard: every host render asks Proto.save(), which is
   *    debounced here. We write + read back a probe key, and on failure
   *    show a real banner with a retry that saves again. This replaces the
   *    silent catch in host.js without editing it.
   * ------------------------------------------------------------------ */
  const KEY = 'dayspark.prototype.v1';
  const PROBE = 'dayspark.prototype.probe';
  let persistTimer = 0;
  let persistBanner = null;

  function emitPersistError(err) {
    const hook = P.onPersistError;
    if (typeof hook === 'function') { try { hook(err); } catch (_) {} }
    else if (Array.isArray(hook)) hook.forEach((fn) => { try { fn(err); } catch (_) {} });
  }

  function hidePersistBanner() {
    if (persistBanner && persistBanner.parentNode) persistBanner.parentNode.removeChild(persistBanner);
    persistBanner = null;
  }

  function showPersistBanner() {
    if (persistBanner && document.body.contains(persistBanner)) return;
    persistBanner = document.createElement('div');
    persistBanner.id = 'proto-persist-banner';
    persistBanner.setAttribute('role', 'alert');
    persistBanner.style.cssText = 'position:fixed;left:50%;bottom:18px;transform:translateX(-50%);z-index:9999;' +
      'display:flex;align-items:center;gap:12px;max-width:92vw;padding:10px 14px;border-radius:10px;' +
      'background:#3a1d1d;color:#fff;border:1px solid #b35050;box-shadow:0 8px 30px rgba(0,0,0,.28);font-size:13px;line-height:1.4';
    persistBanner.innerHTML = '<span>本地保存失败 · 改动只在这个标签页，刷新会丢</span>' +
      '<button type="button" id="proto-persist-retry" style="flex:none;padding:5px 12px;border-radius:6px;border:1px solid #f0b4b4;background:transparent;color:#fff;font-size:12px;cursor:pointer">重试</button>';
    document.body.appendChild(persistBanner);
    const btn = q('#proto-persist-retry', persistBanner);
    if (btn) btn.addEventListener('click', () => {
      const ok = saveNow();
      if (ok) toast('已重新保存到本机');
      else toast('仍然保存失败 · 本地存储不可写');
    });
  }

  function saveNow() {
    let ok = false, err = null;
    try {
      localStorage.setItem(KEY, JSON.stringify(P.snapshot()));
      const token = String(Date.now()) + '.' + Math.random().toString(36).slice(2);
      localStorage.setItem(PROBE, token);
      if (localStorage.getItem(PROBE) !== token) throw new Error('probe read-back mismatch');
      ok = true;
    } catch (e) {
      err = e;
    }
    if (ok) { hidePersistBanner(); }
    else { showPersistBanner(); emitPersistError(err); }
    return ok;
  }

  P.save = function save() {
    clearTimeout(persistTimer);
    persistTimer = setTimeout(saveNow, 40);
  };
  P.persistNow = saveNow;
  P.onPersistError = null;

  /* ------------------------------------------------------------------ *
   * 2. Trash helpers — snapshots and permanent ids.
   * ------------------------------------------------------------------ */
  function allTrashItems() {
    return (typeof trashItems === 'function' ? trashItems() : []).slice();
  }

  function snapFor(id) {
    const extra = (state.trashExtra || []).find((x) => x.id === id);
    if (extra && extra.snap) return extra.snap;
    const base = allTrashItems().find((x) => x.id === id);
    return base && base.snap;
  }

  function markTrashRemoved(ids) {
    state.trashRemoved = state.trashRemoved || [];
    ids.forEach((id) => {
      if (String(id).indexOf('trash-') === 0 && !state.trashRemoved.includes(id)) state.trashRemoved.push(id);
    });
  }

  function rememberPurged(ids) {
    state.purgedIds = state.purgedIds || [];
    ids.forEach((id) => { if (id && !state.purgedIds.includes(id)) state.purgedIds.push(id); });
  }

  function dropRows(list, ids) {
    for (let i = list.length - 1; i >= 0; i--) {
      if (ids.has(list[i].id)) list.splice(i, 1);
    }
  }

  // Permanently remove the records behind every trash row. Pre-seeded rows are
  // static design data: marking them in trashRemoved is their permanent delete.
  function clearTrashForReal() {
    const items = allTrashItems();
    const ids = new Set();
    items.forEach((x) => ids.add(x.id));
    (state.deletedTodos || []).forEach((id) => ids.add(id));
    (state.deletedEvents || []).forEach((id) => ids.add(id));

    const baseIds = new Set(items.filter((x) => String(x.id).indexOf('trash-') === 0).map((x) => x.id));
    markTrashRemoved(baseIds);
    // Also clear any static ids that were already hidden one by one.
    markTrashRemoved(ids);

    const realIds = new Set();
    ids.forEach((id) => { if (String(id).indexOf('trash-') !== 0) realIds.add(id); });
    rememberPurged(ids);

    dropRows(TODOS, realIds);
    if (Array.isArray(state.localTodos)) dropRows(state.localTodos, realIds);
    dropRows(EVENTS, realIds);

    state.deletedTodos = [];
    state.deletedEvents = [];
    state.trashExtra = [];
    // The standalone design-only trash page uses titles as its hide list.
    P.data.hiddenTrash = items.map((x) => (x.title || '').trim()).filter(Boolean);
  }

  function confirmClearTrash(where) {
    modal({
      title: '清空回收站？',
      body: '<div class="proto-note">回收站里的所有项目会被永久删除，不能撤销。待办与日程本身也会从本地存储移除。</div>',
      actions: [
        { label: '取消' },
        { label: '清空', primary: true, danger: true, onClick: () => {
          clearTrashForReal();
          state.variant = where === 'standalone' ? 'empty' : 'cleared';
          render();
          toast('回收站已清空 · 底层记录已移除');
        } },
      ],
    });
  }

  // Both the settings page and the standalone trash page funnel here.
  registerAction('trash-clear-v2', () => confirmClearTrash('settings'));
  registerAction('trash-clear-proto', () => confirmClearTrash('standalone'));

  // Permanent delete of a single trash row drops the underlying record too,
  // so it cannot survive in localStorage and come back.
  registerAction('trash-delete-v2', (el) => {
    const id = el && el.dataset ? el.dataset.id : '';
    if (!id) return;
    const item = allTrashItems().find((x) => x.id === id) || { title: '这一项' };
    modal({
      title: '永久删除？',
      body: '<div class="proto-note">不会进回收站，也不能撤销。</div>',
      actions: [
        { label: '取消' },
        { label: '永久删除', primary: true, danger: true, onClick: () => {
          state.trashExtra = (state.trashExtra || []).filter((x) => x.id !== id);
          state.deletedTodos = (state.deletedTodos || []).filter((x) => x !== id);
          state.deletedEvents = (state.deletedEvents || []).filter((x) => x !== id);
          if (String(id).indexOf('trash-') === 0) markTrashRemoved([id]);
          rememberPurged([id]);
          const hit = new Set([id]);
          dropRows(TODOS, hit);
          if (Array.isArray(state.localTodos)) dropRows(state.localTodos, hit);
          dropRows(EVENTS, hit);
          render();
          toast('已永久删除 · ' + item.title);
        } },
      ],
    });
  });

  // Mobile settings rows use data-action only; wire them to the same handlers.
  registerEnhancer((root) => {
    if (state.screen !== 'settings-trash' && state.screen !== 'trash-page') return;
    qa('[data-action="trash-restore"]', root).forEach((b) => {
      if (b.dataset.protoAction === 'trash-restore-v2') return;
      b.dataset.protoAction = 'trash-restore-v2';
    });
    qa('[data-action="trash-delete"]', root).forEach((b) => { b.dataset.protoAction = 'trash-delete-v2'; });
    qa('[data-action="trash-clear"]', root).forEach((b) => { b.dataset.protoAction = 'trash-clear-v2'; });
  });

  /* ------------------------------------------------------------------ *
   * 2b. Deleting from the detail drawer must leave a real snapshot so
   *     "restore" brings the whole object back (the master path only
   *     pushed id + title). We listen in the capture phase before the
   *     master's own confirm-delete handler runs.
   * ------------------------------------------------------------------ */
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-action="confirm-delete"]');
    if (!el) return;
    const ref = state.deleteRef || state.drawer ||
      (typeof activeDetailRef === 'function' ? activeDetailRef() : null);
    if (!ref || !ref.id) return;
    const list = ref.type === 'event' ? EVENTS : TODOS.concat(state.localTodos || []);
    const src = list.find((x) => x.id === ref.id);
    if (!src) return;
    // Defer so the master handler records deletedTodos/deletedEvents first,
    // then patch the row it just pushed with the full pre-delete snapshot.
    setTimeout(() => {
      const row = (state.trashExtra || []).find((x) => x.id === ref.id);
      if (!row) return;
      if (!row.snap) row.snap = clone(src);
    }, 0);
  }, true);

  /* ------------------------------------------------------------------ *
   * 3. Real restore: full snapshot, no skipped keys touched, pre-seeded
   *    rows removed from the list for good.
   * ------------------------------------------------------------------ */
  registerAction('trash-restore-v2', (el) => {
    const id = el && el.dataset ? el.dataset.id : '';
    if (!id) return;
    const snap = snapFor(id);
    if (!snap) {
      modal({
        title: '这一项没有可恢复的原件',
        body: '<div class="proto-note">这条记录是在设计状态里预置的示例，没有保存原日历、标签和字段。恢复会创建一条只有标题的待办，并放进默认日历。</div>',
        actions: [
          { label: '取消' },
          { label: '仍然恢复为纯标题', onClick: () => {
            const row = el.closest('.trash-row, .m-settings-row');
            const title = ((q('.trash-main > div', row) || q('span', row) || {}).textContent || '恢复的待办').trim();
            state.trashExtra = (state.trashExtra || []).filter((x) => x.id !== id);
            if (String(id).indexOf('trash-') === 0) markTrashRemoved([id]);
            TODOS.unshift({ id: 'restored-' + Date.now(), title, cal: state.defaultCal || 'personal', priority: 0, tags: [], status: 'open' });
            render();
            toast('已恢复为纯标题 · ' + calOf(state.defaultCal || 'personal').name);
          } },
        ],
      });
      return;
    }
    state.deletedTodos = (state.deletedTodos || []).filter((x) => x !== id);
    state.deletedEvents = (state.deletedEvents || []).filter((x) => x !== id);
    state.trashExtra = (state.trashExtra || []).filter((x) => x.id !== id);
    // Pre-seeded rows are served from the static trash list; remember that the
    // row is gone so it cannot reappear after this render or a reload.
    if (String(id).indexOf('trash-') === 0) markTrashRemoved([id]);

    // NOTE: state.skipped is deliberately left untouched. Deleting one
    // occurrence (仅这一次) must stay hidden when the series is restored.
    const isEvent = !!(snap.start || snap.startDate || (snap.allDay && snap.date && !snap.status));
    const list = isEvent ? EVENTS : TODOS;
    const copy = clone(snap);
    const existing = list.find((x) => x.id === copy.id);
    if (existing) {
      Object.keys(existing).forEach((k) => { delete existing[k]; });
      Object.assign(existing, copy);
    } else if (isEvent) {
      EVENTS.push(copy);
    } else {
      TODOS.unshift(copy);
    }
    const backTo = snap.cal && typeof calOf === 'function' ? calOf(snap.cal).name : '原日历';
    state.drawer = isEvent ? { type: 'event', id: snap.id } : { type: 'todo', id: snap.id };
    state.drawerEdit = false;
    render();
    toast('已恢复 · 回到「' + backTo + '」· 原字段保留');
  });

  /* ------------------------------------------------------------------ *
   * 4. ICS export: full VEVENT / VTODO, CRLF folding, re-importable.
   * ------------------------------------------------------------------ */
  function pad2(n) { return String(n).padStart(2, '0'); }
  function compactDate(iso) { return String(iso || '').replace(/-/g, ''); }
  function stamp(iso, time) { return compactDate(iso) + 'T' + String(time || '09:00').replace(/:/g, '') + '00'; }
  function unescapeIcs(v) {
    return String(v == null ? '' : v)
      .replace(/\\n/gi, '\n')
      .replace(/\\,/g, ',')
      .replace(/\\;/g, ';')
      .replace(/\\\\/g, '\\');
  }
  function escapeIcs(v) {
    return String(v == null ? '' : v)
      .replace(/\\/g, '\\\\')
      .replace(/\r?\n/g, '\\n')
      .replace(/;/g, '\\;')
      .replace(/,/g, '\\,');
  }
  function utf8Len(ch) {
    const cp = ch.codePointAt(0);
    if (cp <= 0x7f) return 1;
    if (cp <= 0x7ff) return 2;
    if (cp <= 0xffff) return 3;
    return 4;
  }
  // RFC 5545 §3.1: fold logical lines at 75 octets, continuation starts with space.
  function foldLine(line) {
    const out = [];
    let cur = '';
    let bytes = 0;
    for (const ch of String(line)) {
      const b = utf8Len(ch);
      const limit = out.length ? 74 : 75;
      if (bytes + b > limit) { out.push(cur); cur = ''; bytes = 0; }
      cur += ch; bytes += b;
    }
    out.push(cur);
    return out.join('\r\n ');
  }
  const BYDAY = { 日: 'SU', 一: 'MO', 二: 'TU', 三: 'WE', 四: 'TH', 五: 'FR', 六: 'SA' };
  function rruleFor(item) {
    const repeat = String(item.repeat || '');
    if (!repeat) return '';
    let rule = '';
    const prefix = /^(每\s?2\s?周|每周)/.exec(repeat);
    const dayCodes = () => {
      if (!prefix) return '';
      return repeat.slice(prefix[0].length).split(/[、,，]/).map((t) => BYDAY[t.trim().slice(-1)]).filter(Boolean).join(',');
    };
    if (/^每天/.test(repeat)) rule = 'FREQ=DAILY';
    else if (/^每\s?2\s?周/.test(repeat)) rule = 'FREQ=WEEKLY;INTERVAL=2' + (dayCodes() ? ';BYDAY=' + dayCodes() : '');
    else if (/^每周/.test(repeat)) rule = 'FREQ=WEEKLY' + (dayCodes() ? ';BYDAY=' + dayCodes() : '');
    else if (/^每月/.test(repeat)) rule = 'FREQ=MONTHLY';
    else if (/^每年/.test(repeat)) rule = 'FREQ=YEARLY';
    if (!rule) return '';
    if (item.repeatUntil) rule += ';UNTIL=' + compactDate(item.repeatUntil);
    else if (item.repeatCount) rule += ';COUNT=' + Number(item.repeatCount);
    return 'RRULE:' + rule;
  }

  function eventLines(e) {
    const lines = ['BEGIN:VEVENT', 'UID:' + String(e.id || 'event'), 'SUMMARY:' + escapeIcs(e.title)];
    const timedCross = !!e.crossMidnight || !!(e.startDate && e.endDate && e.start && e.end && !e.allDay);
    const allDayish = !timedCross && (e.allDay || (!e.start && !e.end));
    const startDay = e.startDate || e.date || TODAY_ISO();
    const endDay = e.endDate || e.date || startDay;
    if (timedCross) {
      lines.push('DTSTART:' + stamp(startDay, e.start || '09:00'));
      lines.push('DTEND:' + stamp(endDay, e.end || '10:00'));
    } else if (allDayish) {
      lines.push('DTSTART;VALUE=DATE:' + compactDate(startDay));
      // ICS DTEND for all-day is exclusive; internal endDate is inclusive.
      lines.push('DTEND;VALUE=DATE:' + compactDate(addDays(endDay, 1)));
    } else {
      lines.push('DTSTART:' + stamp(startDay, e.start || '09:00'));
      lines.push('DTEND:' + stamp(startDay, e.end || '10:00'));
    }
    if (e.loc) lines.push('LOCATION:' + escapeIcs(e.loc));
    if (e.note) lines.push('DESCRIPTION:' + escapeIcs(e.note));
    const rr = rruleFor(e);
    if (rr) lines.push(rr);
    lines.push('END:VEVENT');
    return lines;
  }

  function todoLines(t) {
    const lines = ['BEGIN:VTODO', 'UID:' + String(t.id || 'todo'), 'SUMMARY:' + escapeIcs(t.title)];
    if (t.due) {
      if (t.dueTime) lines.push('DUE:' + stamp(t.due, t.dueTime));
      else lines.push('DUE;VALUE=DATE:' + compactDate(t.due));
    }
    if (t.note) lines.push('DESCRIPTION:' + escapeIcs(t.note));
    const rr = rruleFor(t);
    if (rr) lines.push(rr);
    lines.push('END:VTODO');
    return lines;
  }

  function buildICS() {
    const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//DaySpark//Prototype//CN', 'CALSCALE:GREGORIAN'];
    const events = EVENTS.filter((e) => !state.deletedEvents.includes(e.id));
    events.forEach((e) => { eventLines(e).forEach((l) => lines.push(l)); });
    const todos = (typeof allTodos === 'function' ? allTodos() : TODOS).filter((t) => !state.deletedTodos.includes(t.id));
    todos.forEach((t) => { todoLines(t).forEach((l) => lines.push(l)); });
    lines.push('END:VCALENDAR');
    return lines.map(foldLine).join('\r\n') + '\r\n';
  }
  P.buildICS = buildICS;

  function downloadText(name, text, type) {
    try {
      const blob = new Blob([text], { type });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = name;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (_) { /* download is a side effect; the file content is already built */ }
  }

  registerAction('export-ics', () => {
    const text = buildICS();
    const events = EVENTS.filter((e) => !state.deletedEvents.includes(e.id)).length;
    const todos = (typeof allTodos === 'function' ? allTodos() : TODOS).filter((t) => !state.deletedTodos.includes(t.id)).length;
    downloadText('dayspark-' + TODAY_ISO() + '.ics', text, 'text/calendar;charset=utf-8');
    toast('已导出 .ics · ' + (events + todos) + ' 项 · 含时间与重复');
  });

  /* ------------------------------------------------------------------ *
   * 5. Composer (new-event page): let "时间" express a next-day end and
   *    post-process the saved event into the two-day cross-midnight span.
   * ------------------------------------------------------------------ */
  function ensureDraft() {
    if (!P.data.newDraft) {
      P.data.newDraft = {
        cal: state.defaultCal || 'personal', date: TODAY_ISO(), start: '11:00', end: '12:00',
        allDay: false, endDate: '', loc: '', repeat: '', repeatEnd: '永不结束',
        remind: state.screen === 'new-event' ? '15 分钟前' : '不提醒',
        priority: '中', due: '', dueTime: '', plan: null, tags: [],
      };
    }
    return P.data.newDraft;
  }

  const prevNewField = P.actions['new-field'];
  registerAction('new-field', (el) => {
    const label = el && el.dataset ? (el.dataset.field || '') : '';
    if (label !== '时间') {
      if (typeof prevNewField === 'function') return prevNewField(el);
      return;
    }
    const d = ensureDraft();
    if (!d.date) d.date = TODAY_ISO();
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-check"><input type="checkbox" id="v3-allday" ${d.allDay ? 'checked' : ''}><label for="v3-allday">全天（可跨日）</label></div>
      <div class="proto-field"><label>开始日期</label><button type="button" class="proto-input" id="v3-sdate" style="text-align:left">${esc(d.date)}</button></div>
      <div class="proto-field" id="v3-edate-wrap" style="${d.allDay ? '' : 'display:none'}"><label>结束日期</label><button type="button" class="proto-input" id="v3-edate" style="text-align:left">${esc(d.endDate || d.date)}</button></div>
      <div class="proto-inline-row" id="v3-times" style="${d.allDay ? 'display:none' : ''}"><div class="proto-field" style="flex:1"><label>开始</label><input type="time" class="proto-input" id="v3-start" value="${esc(d.start || '11:00')}"></div><div class="proto-field" style="flex:1"><label>结束</label><input type="time" class="proto-input" id="v3-end" value="${esc(d.end || '12:00')}"></div></div>
      <div class="proto-note">结束早于开始 = 次日结束（跨午夜，例如 23:30 → 01:30）。全天条目不写具体时刻。</div>`;
    modal({
      title: '时间', body,
      actions: [
        { label: '取消' },
        { label: '应用', primary: true, onClick: () => {
          d.allDay = q('#v3-allday', body).checked;
          d.start = q('#v3-start', body).value || '11:00';
          d.end = q('#v3-end', body).value || '12:00';
          if (!d.allDay && d.end === d.start) { toast('开始和结束不能相同'); return true; }
          if (d.allDay && d.endDate && d.endDate < d.date) { toast('结束日期不能早于开始'); return true; }
          render();
          toast(!d.allDay && d.end < d.start ? '时间已更新 · 次日结束' : '时间已更新');
        } },
      ],
    });
    body.addEventListener('click', (e) => {
      if (e.target.id === 'v3-allday') {
        const on = e.target.checked;
        q('#v3-times', body).style.display = on ? 'none' : '';
        q('#v3-edate-wrap', body).style.display = on ? '' : 'none';
      }
      const sd = e.target.closest('#v3-sdate');
      if (sd) {
        P.openDatePicker({ value: d.date, onPick: (v) => { d.date = v || TODAY_ISO(); sd.textContent = d.date; } });
      }
      const ed = e.target.closest('#v3-edate');
      if (ed) {
        P.openDatePicker({ value: d.endDate || d.date, onPick: (v) => { d.endDate = v || d.date; ed.textContent = d.endDate; } });
      }
    });
  });

  const prevNewSave = P.actions['new-save'];
  registerAction('new-save', () => {
    const d = P.data.newDraft;
    const isEvent = state.screen === 'new-event';
    const cross = !!(isEvent && d && !d.allDay && d.start && d.end && d.end < d.start);
    if (!cross) {
      if (typeof prevNewSave === 'function') return prevNewSave();
      return;
    }
    const before = EVENTS.length;
    const beforeIds = EVENTS.map((e) => e.id).join('|');
    const titleInput = q('#new-title') || q('.new-page .form-input') || q('.m-detail-scroll .m-form-input');
    if (titleInput && !(titleInput.value || '').trim()) {
      // Let the base handler show the real validation state.
      return prevNewSave ? prevNewSave() : undefined;
    }
    if (typeof prevNewSave === 'function') prevNewSave();
    if (EVENTS.length <= before && EVENTS.map((e) => e.id).join('|') === beforeIds) return;
    const ev = EVENTS[EVENTS.length - 1];
    const day = ev.date || d.date || TODAY_ISO();
    ev.startDate = day;
    ev.endDate = addDays(day, 1);
    ev.crossMidnight = true;
    ev.allDay = false;
    delete ev.date;
    render();
    toast('已创建跨午夜日程 · ' + (ev.start || d.start) + '–次日 ' + (ev.end || d.end));
  });

  /* A light enhancer keeps the saved draft's time text honest on the page. */
  registerEnhancer((root) => {
    if (state.screen !== 'new-event') return;
    const d = P.data.newDraft;
    if (!d || d.allDay || !d.start || !d.end) return;
    const row = qa('.new-page .cp-field', root).find((r) => {
      const k = q('.k', r); return k && (k.textContent || '').trim() === '时间';
    });
    const v = row && q('.v', row);
    if (!v) return;
    const text = '时间 · ' + d.date + ' ' + d.start + '–' + (d.end < d.start ? '次日 ' : '') + d.end;
    if (v.textContent !== text) v.textContent = text;
  });

  /* ------------------------------------------------------------------ *
   * 6. Full backup — the one real JSON file and the one real merge path.
   *    The old handlers in flows-system.js / flows-v2-system.js were removed,
   *    so there is no second path that can overwrite this one.
   * ------------------------------------------------------------------ */
  const plainClone = (v) => JSON.parse(JSON.stringify(v));

  // Strip plaintext credentials even when P.redactForBackup (Agent ④) is not
  // present. A masked display key (contains "•") is kept so restored settings
  // still render something, but a usable secret never leaves the machine.
  const SECRET_KEY = /^(secret|password|passwd|token|access[-_]?token|refresh[-_]?token|api[-_]?key|apikey|credential)$/i;
  function scrubSecrets(value, depth) {
    if (depth > 10 || value == null) return value;
    if (Array.isArray(value)) return value.map((v) => scrubSecrets(v, depth + 1));
    if (typeof value !== 'object') return value;
    const out = {};
    Object.keys(value).forEach((k) => {
      if (SECRET_KEY.test(k)) return;
      if (k === 'key' && typeof value[k] === 'string' && value[k].indexOf('•') < 0 && /^sk-/.test(value[k])) return;
      out[k] = scrubSecrets(value[k], depth + 1);
    });
    return out;
  }

  function buildBackup() {
    let payload;
    try {
      payload = plainClone(P.snapshot ? P.snapshot() : { v: 1, todos: TODOS, events: EVENTS, cal: CAL, state: state, data: P.data });
    } catch (_) {
      payload = { v: 1, todos: plainClone(TODOS), events: plainClone(EVENTS), cal: plainClone(CAL), state: {}, data: {} };
    }
    payload.v = 1;
    // Agent ④'s redactor, when available, gets first refusal.
    if (typeof P.redactForBackup === 'function') {
      try {
        const red = P.redactForBackup(payload);
        if (red && typeof red === 'object') {
          if (red.data || red.todos || red.state || red.v) payload = red;
          else payload.data = red;
        }
      } catch (_) { /* fall through to the local scrub */ }
    }
    return scrubSecrets(payload, 0);
  }
  P.buildBackup = buildBackup;
  P.backupFilename = function () { return TODAY_ISO() + '.dayspark.json'; };

  function downloadJson(name, text) {
    const blob = new Blob([text], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = name; a.style.display = 'none';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => { try { URL.revokeObjectURL(url); } catch (_) {} }, 2000);
  }

  registerAction('backup-export', () => {
    if (state.screen !== 'settings-backup') P.baseGo('settings-backup');
    state.variant = 'progress';
    render();
    // Build the Blob first; only after it exists do we show success. A retry
    // from the error variant re-runs exactly this path and downloads again.
    setTimeout(() => {
      try {
        const payload = buildBackup();
        const text = JSON.stringify(payload, null, 2);
        const name = P.backupFilename();
        downloadJson(name, text);
        state.variant = 'success';
        render();
        toast('已导出完整备份 · ' + name);
      } catch (err) {
        state.variant = 'error';
        render();
        toast('备份失败 · 没有生成文件');
      }
    }, 450);
  });

  function mergeUniqueArray(base, incoming) {
    const out = Array.isArray(base) ? base.slice() : [];
    if (!Array.isArray(incoming)) return out;
    incoming.forEach((v) => { if (v != null && out.indexOf(v) < 0) out.push(v); });
    return out;
  }
  function pushUniqueById(list, incoming) {
    if (!Array.isArray(incoming)) return;
    incoming.forEach((row) => {
      if (!row || typeof row !== 'object' || !row.id) return;
      if (list.some((x) => x && x.id === row.id)) return;
      list.push(plainClone(row));
    });
  }
  // Restoring a backup onto a freshly seeded install hits the same sample ids.
  // "Merge" means补齐: keep local rows, but bring in the backup's business
  // fields and union its allocation identities instead of dropping the whole
  // row as a duplicate. Local-only allocations that are absent from the backup
  // stay untouched.
  function mergePlans(localPlans, incomingPlans) {
    const out = Array.isArray(localPlans) ? localPlans.slice() : [];
    (Array.isArray(incomingPlans) ? incomingPlans : []).forEach((p) => {
      if (!p || typeof p !== 'object') return;
      if (!p.id) return;
      const hit = out.find((x) => x && x.id === p.id);
      if (hit) Object.assign(hit, plainClone(p));
      else out.push(plainClone(p));
    });
    return out;
  }
  function mergeTodoRow(target, incoming) {
    const copy = plainClone(incoming);
    const incomingPlans = Array.isArray(copy.plans) ? copy.plans : null;
    const singlePlan = copy.plan && typeof copy.plan === 'object' ? copy.plan : null;
    delete copy.plans;
    delete copy.plan;
    Object.assign(target, copy);
    const planList = incomingPlans ? incomingPlans.slice() : [];
    if (singlePlan && !planList.some((p) => p && p.id === singlePlan.id)) planList.push(singlePlan);
    if (planList.length) target.plans = mergePlans(target.plans, planList);
    if (window.DS3 && window.DS3.syncProjection) window.DS3.syncProjection(target);
    else if (singlePlan) target.plan = plainClone(singlePlan);
  }
  function maxSeqFromPlans(todos, seed) {
    let max = seed;
    (todos || []).forEach((t) => {
      const plans = t && Array.isArray(t.plans) ? t.plans : [];
      plans.forEach((p) => {
        const m = /^alloc-(\d+)$/.exec((p && p.id) || '');
        if (m) max = Math.max(max, Number(m[1]));
      });
    });
    return max;
  }

  // A merged backup must never inject a credential into P.data. When Agent ④
  // exposes P.sanitizeAiCredentials we use it; otherwise we keep only the
  // non-secret display fields (base/model and a masked key containing "•").
  function sanitizeAiForMerge(ai) {
    if (!ai || typeof ai !== 'object' || Array.isArray(ai)) return null;
    let safe = null;
    if (typeof P.sanitizeAiCredentials === 'function') {
      try { safe = P.sanitizeAiCredentials(plainClone(ai)); } catch (_) { safe = null; }
    }
    if (!safe || typeof safe !== 'object' || Array.isArray(safe)) {
      safe = {};
      if (ai.model != null) safe.model = ai.model;
      if (ai.base != null) safe.base = ai.base;
      if (typeof ai.key === 'string' && ai.key.indexOf('•') >= 0) safe.key = ai.key;
    }
    // Belt and braces regardless of which branch ran.
    ['secret', 'password', 'passwd', 'token', 'accessToken', 'refreshToken', 'apiKey', 'api_key', 'credential'].forEach((k) => { delete safe[k]; });
    if (typeof safe.key === 'string' && safe.key.indexOf('•') < 0) delete safe.key;
    return safe;
  }

  // Transactional: every next* value is built first, then committed in one
  // pass. A throw while normalising leaves local data untouched.
  function applyBackupMerge(payload) {
    const incTodos = Array.isArray(payload.todos) ? payload.todos : [];
    const incEvents = Array.isArray(payload.events) ? payload.events : [];
    const incCal = payload.cal && typeof payload.cal === 'object' && !Array.isArray(payload.cal) ? payload.cal : {};
    const incState = payload.state && typeof payload.state === 'object' && !Array.isArray(payload.state) ? payload.state : {};
    const incData = payload.data && typeof payload.data === 'object' && !Array.isArray(payload.data) ? payload.data : {};
    const incTags = Array.isArray(incData.tags) ? incData.tags : (Array.isArray(payload.tags) ? payload.tags : []);
    const incLocal = Array.isArray(incState.localTodos) ? incState.localTodos : [];
    const seedDone = Array.isArray(incState.doneInstances) ? incState.doneInstances : (Array.isArray(payload.doneInstances) ? payload.doneInstances : []);
    const seedSkipped = Array.isArray(incState.skipped) ? incState.skipped : (Array.isArray(payload.skipped) ? payload.skipped : []);

    const nextTodos = TODOS.slice();
    const nextLocal = (state.localTodos || []).slice();
    const nextEvents = EVENTS.slice();
    const nextCal = Object.assign({}, CAL);
    const nextTags = (P.data.tags || []).slice();
    const nextAi = Object.assign({}, P.data.ai || {});
    const safeAi = sanitizeAiForMerge(incData.ai);
    if (safeAi) {
      ['model', 'base', 'provider', 'enabled'].forEach((k) => { if (safeAi[k] != null) nextAi[k] = safeAi[k]; });
      if (typeof safeAi.key === 'string' && safeAi.key.indexOf('•') >= 0) nextAi.key = safeAi.key;
    }
    let added = 0, updated = 0;
    incTodos.forEach((t) => {
      if (!t || typeof t !== 'object' || !t.id) return;
      const existing = nextTodos.find((x) => x && x.id === t.id);
      const existingLocal = nextLocal.find((x) => x && x.id === t.id);
      if (existing || existingLocal) {
        mergeTodoRow(existing || existingLocal, t);
        updated++;
        return;
      }
      const copy = plainClone(t);
      if (String(t.id).indexOf('local-') === 0) nextLocal.push(copy); else nextTodos.push(copy);
      added++;
    });
    incEvents.forEach((e) => {
      if (!e || typeof e !== 'object' || !e.id) return;
      const existing = nextEvents.find((x) => x && x.id === e.id);
      if (existing) {
        Object.assign(existing, plainClone(e));
        updated++;
        return;
      }
      nextEvents.push(plainClone(e)); added++;
    });
    Object.keys(incCal).forEach((k) => {
      if (!nextCal[k]) nextCal[k] = plainClone(incCal[k]);
      else if (incCal[k] && typeof incCal[k] === 'object') Object.assign(nextCal[k], plainClone(incCal[k]));
    });
    incTags.forEach((tag) => {
      if (!tag || !tag.name) return;
      if (!nextTags.some((x) => x && x.name === tag.name)) nextTags.push(plainClone(tag));
    });
    // state.localTodos may carry rows that are not in todos[].
    incLocal.forEach((t) => {
      if (!t || typeof t !== 'object' || !t.id) return;
      const existing = nextTodos.find((x) => x && x.id === t.id) || nextLocal.find((x) => x && x.id === t.id);
      if (existing) { mergeTodoRow(existing, t); updated++; return; }
      nextLocal.push(plainClone(t)); added++;
    });

    const nextDoneInstances = mergeUniqueArray(state.doneInstances, seedDone);
    const nextSkipped = mergeUniqueArray(state.skipped, seedSkipped);
    const nextDone = new Set(state.done instanceof Set ? state.done : []);
    const doneArr = Array.isArray(incState.done) ? incState.done : (Array.isArray(payload.done) ? payload.done : []);
    doneArr.forEach((id) => { if (id) nextDone.add(id); });
    const nextPlanSeq = Math.max(
      Number(state.planSeq) || 0,
      Number(incState.planSeq) || Number(payload.planSeq) || 0,
      maxSeqFromPlans(nextTodos, 0),
      maxSeqFromPlans(nextLocal, 0)
    );
    const nextLocalNo = Math.max(Number(state.localNo) || 0, Number(incState.localNo) || 0);
    const nextTrashExtra = (state.trashExtra || []).slice();
    pushUniqueById(nextTrashExtra, incState.trashExtra);

    // ---- commit ----
    TODOS.splice(0, TODOS.length, ...nextTodos);
    state.localTodos = nextLocal;
    EVENTS.splice(0, EVENTS.length, ...nextEvents);
    for (const k of Object.keys(CAL)) delete CAL[k];
    Object.assign(CAL, nextCal);
    P.data.tags = nextTags;
    P.data.ai = nextAi;
    state.doneInstances = nextDoneInstances;
    state.skipped = nextSkipped;
    state.done = nextDone;
    state.planSeq = nextPlanSeq;
    state.localNo = nextLocalNo;
    state.deletedTodos = mergeUniqueArray(state.deletedTodos, incState.deletedTodos);
    state.deletedEvents = mergeUniqueArray(state.deletedEvents, incState.deletedEvents);
    state.hiddenCals = mergeUniqueArray(state.hiddenCals, incState.hiddenCals);
    state.deletedCals = mergeUniqueArray(state.deletedCals, incState.deletedCals);
    state.purgedIds = mergeUniqueArray(state.purgedIds, incState.purgedIds);
    state.trashRemoved = mergeUniqueArray(state.trashRemoved, incState.trashRemoved);
    state.trashExtra = nextTrashExtra;
    return { added, updated };
  }
  // Exposed for verification only; the UI always goes through a real file.
  P.applyBackupMerge = applyBackupMerge;

  registerAction('backup-merge', () => {
    if (state.screen !== 'settings-backup') P.baseGo('settings-backup');
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json,application/json';
    input.className = 'proto-hidden-input';
    input.id = 'proto-backup-file';
    input.setAttribute('data-proto-backup-input', '1');
    input.style.display = 'none';
    document.body.appendChild(input);
    const cleanup = () => { setTimeout(() => { if (input.parentNode) input.parentNode.removeChild(input); }, 0); };
    input.addEventListener('change', () => {
      const file = input.files && input.files[0];
      if (!file) { cleanup(); return; }
      const reader = new FileReader();
      reader.onerror = () => {
        cleanup();
        state.variant = 'merge-error';
        render();
        toast('备份文件读取失败 · 没有写入任何内容');
      };
      reader.onload = () => {
        let payload = null;
        try { payload = JSON.parse(String(reader.result || '')); }
        catch (_) { payload = null; }
        if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
          cleanup();
          state.variant = 'merge-error';
          render();
          toast('备份文件无法解析 · 没有写入任何内容');
          return;
        }
        let counts;
        try { counts = applyBackupMerge(payload); }
        catch (err) {
          cleanup();
          state.variant = 'merge-error';
          render();
          toast('合并失败 · 没有写入任何内容');
          return;
        }
        cleanup();
        state.variant = 'merge-success';
        render();
        if (typeof P.persistNow === 'function') P.persistNow();
        toast('备份已合并 · ' + (counts.added + counts.updated) + ' 项已补齐 · 计划序号 ' + state.planSeq);
      };
      reader.readAsText(file);
    }, false);
    input.click();
  });
})();
