/* DaySpark prototype v3 — capture, composer and priority consistency.
   One canonical priority scale for create / edit / save / filter / store:
     无 = 0 · 高 = 1 · 中 = 5 · 低 = 9
   This is the scale the frozen master already uses in priorityChips(),
   filterPriorityValue(), set-priority and the demo TODOS (rent/internet = 1
   are the urgent ones; car/mom/groceries/books = 9 are the someday ones).
   Older prototype layers had two different, partially inverted maps. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, toast, modal } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));

  const PRIORITY_VALUE = { 无: 0, 高: 1, 中: 5, 低: 9 };
  function priorityValue(label) {
    if (typeof label === 'number') return label;
    return PRIORITY_VALUE[label] == null ? 5 : PRIORITY_VALUE[label];
  }
  function priorityLabel(value) {
    const v = Number(value);
    if (v === 0) return '无';
    if (v === 1) return '高';
    if (v === 5) return '中';
    if (v === 9) return '低';
    if (!Number.isFinite(v)) return '中';
    return v <= 3 ? '高' : v >= 7 ? '低' : '中';
  }
  P.priorityValue = priorityValue;
  P.priorityLabel = priorityLabel;

  function draft() {
    if (!P.data.newDraft) {
      P.data.newDraft = {
        cal: state.defaultCal || 'personal', date: TODAY, start: '11:00', end: '12:00',
        allDay: false, endDate: '', loc: '', repeat: '', repeatEnd: '永不结束',
        remind: state.screen === 'new-event' ? '15 分钟前' : '不提醒',
        priority: '中', due: '', dueTime: '', plan: null, tags: [],
      };
    }
    return P.data.newDraft;
  }

  function snap(obj, keys) {
    const out = {};
    keys.forEach((k) => { out[k] = obj[k]; });
    return out;
  }
  function restore(obj, saved) {
    Object.keys(saved).forEach((k) => {
      if (saved[k] === undefined) delete obj[k];
      else obj[k] = saved[k];
    });
  }
  // Clicking the scrim is the same as Cancel: nothing opened inside it may leak.
  function guardScrim(scrim, onDismiss) {
    scrim.addEventListener('click', (e) => { if (e.target === scrim) onDismiss(); });
    return scrim;
  }

  /* ---------------- composer: due / time with nested-picker rollback ---------------- */
  const baseNewField = P.actions['new-field'];

  function openDue(d) {
    const body = document.createElement('div');
    let mode = d.dueTime ? 'time' : 'date';
    body.innerHTML = `<div class="proto-seg" data-due-mode><button type="button" class="${mode === 'date' ? 'is-on' : ''}" data-mode="date">只写日期</button><button type="button" class="${mode === 'time' ? 'is-on' : ''}" data-mode="time">日期 + 时间</button></div>
      <div class="proto-field" style="margin-top:8px"><label>日期</label><button type="button" class="proto-input" data-proto-action="composer-date" style="text-align:left">${P.esc(d.due || '选择日期')}</button></div>
      <div class="proto-field" data-time-wrap style="${mode === 'time' ? '' : 'display:none'}"><label>时间</label><input type="time" class="proto-input" id="nf-due-time" value="${P.esc(d.dueTime || '18:00')}"></div>
      <div class="proto-note">截止不是时间占用；它只表示这件事什么时候必须完成。只写日期时不会写入任何时刻。</div>`;
    const saved = snap(d, ['due', 'dueTime']);
    const scrim = modal({ title: '截止', body, actions: [
      { label: '取消', onClick: () => { restore(d, saved); render(); } },
      { label: '清除', onClick: () => { d.due = ''; d.dueTime = ''; render(); toast('已清除截止'); } },
      { label: '应用', primary: true, onClick: () => {
        // Fix: the hidden time input must never be read in "只写日期" mode.
        if (mode === 'time') d.dueTime = (q('#nf-due-time', body).value || '');
        else d.dueTime = '';
        if (!d.due) d.due = TODAY;
        render(); toast('截止已更新');
      } },
    ] });
    guardScrim(scrim, () => { restore(d, saved); render(); });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-mode]');
      if (b) {
        mode = b.dataset.mode;
        qa('[data-mode]', body).forEach((x) => x.classList.toggle('is-on', x === b));
        q('[data-time-wrap]', body).style.display = mode === 'time' ? '' : 'none';
        if (mode === 'date') { const t = q('#nf-due-time', body); if (t) t.value = ''; }
        else { const t = q('#nf-due-time', body); if (t && !t.value) t.value = d.dueTime || '18:00'; }
      }
      if (e.target.closest('[data-proto-action="composer-date"]')) {
        P.openDatePicker({ value: d.due || TODAY, allowClear: true, onPick: (v) => {
          d.due = v || '';
          const btn = q('[data-proto-action="composer-date"]', body); if (btn) btn.textContent = v || '选择日期';
        } });
      }
    });
    return scrim;
  }

  function openEventTime(d) {
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-check"><input type="checkbox" id="nf-allday" ${d.allDay ? 'checked' : ''}><label for="nf-allday">全天（可跨日）</label></div>
      <div class="proto-field"><label>开始日期</label><button type="button" class="proto-input" data-proto-action="composer-start-date" style="text-align:left">${P.esc(d.date)}</button></div>
      <div class="proto-field" data-end-date style="${d.allDay && d.endDate ? '' : 'display:none'}"><label>结束日期</label><button type="button" class="proto-input" data-proto-action="composer-end-date" style="text-align:left">${P.esc(d.endDate || d.date)}</button></div>
      <div class="proto-inline-row" data-time-row style="${d.allDay ? 'display:none' : ''}"><div class="proto-field" style="flex:1"><label>开始</label><input type="time" class="proto-input" id="nf-start" value="${P.esc(d.start)}"></div><div class="proto-field" style="flex:1"><label>结束</label><input type="time" class="proto-input" id="nf-end" value="${P.esc(d.end)}"></div></div>
      <div class="proto-note">全天条目不写具体时刻；跨日时结束日期必须晚于开始日期。</div>`;
    const saved = snap(d, ['allDay', 'date', 'endDate', 'start', 'end']);
    const scrim = modal({ title: '时间', body, actions: [
      { label: '取消', onClick: () => { restore(d, saved); render(); } },
      { label: '应用', primary: true, onClick: () => {
        d.allDay = q('#nf-allday', body).checked;
        d.start = q('#nf-start', body).value || '11:00';
        d.end = q('#nf-end', body).value || '12:00';
        if (!d.allDay && d.end <= d.start) { toast('结束必须晚于开始'); return true; }
        if (d.allDay && d.endDate && d.endDate < d.date) { toast('结束日期不能早于开始'); return true; }
        render(); toast('时间已更新');
      } },
    ] });
    guardScrim(scrim, () => { restore(d, saved); render(); });
    body.addEventListener('click', (e) => {
      if (e.target.id === 'nf-allday') {
        const on = e.target.checked;
        q('[data-time-row]', body).style.display = on ? 'none' : '';
        q('[data-end-date]', body).style.display = on ? '' : 'none';
      }
      if (e.target.closest('[data-proto-action="composer-start-date"]')) {
        P.openDatePicker({ value: d.date, onPick: (v) => { d.date = v || TODAY; const b = q('[data-proto-action="composer-start-date"]', body); if (b) b.textContent = d.date; } });
      }
      if (e.target.closest('[data-proto-action="composer-end-date"]')) {
        P.openDatePicker({ value: d.endDate || d.date, onPick: (v) => { d.endDate = v || d.date; const b = q('[data-proto-action="composer-end-date"]', body); if (b) b.textContent = d.endDate; } });
      }
    });
    return scrim;
  }

  registerAction('new-field', (el) => {
    const label = el.dataset.field || '';
    const d = draft();
    if (label === '截止') { openDue(d); return; }
    if (label === '时间' && state.screen === 'new-event') { openEventTime(d); return; }
    if (label === '优先级') {
      P.openPriorityPicker({
        value: priorityValue(d.priority),
        onPick: (v) => { d.priority = priorityLabel(v); render(); toast('优先级 · ' + d.priority); },
      });
      return;
    }
    return baseNewField ? baseNewField(el) : undefined;
  });

  /* ---------------- composer save: one priority scale, no phantom dueTime ---------------- */
  registerAction('new-save', () => {
    if (P.demo.saveError) {
      state.variant = 'save-error';
      render();
      toast('保存失败 · 内容已保留');
      return;
    }
    const ev = state.screen === 'new-event';
    const titleEl = q('#new-title') || q('.new-page .form-input') || q('.m-detail-scroll .m-form-input');
    const d = draft();
    const title = ((titleEl && titleEl.value) || d.title || '').trim();
    if (!title) { state.variant = 'validation'; render(); toast('先写一个标题'); return; }
    if (ev) {
      const event = {
        id: 'local-event-' + (++state.localNo), title, cal: d.cal || state.defaultCal || 'personal',
        allDay: !!d.allDay, loc: d.loc, remind: d.remind === '不提醒' ? '' : d.remind,
        note: '', repeat: d.repeat || '', repeatEnd: d.repeatEnd || '',
        repeatUntil: d.repeatUntil || '', repeatCount: d.repeatCount || 0,
      };
      if (d.allDay) {
        event.date = d.date;
        if (d.endDate && d.endDate !== d.date) { event.startDate = d.date; event.endDate = d.endDate; delete event.date; }
      } else { event.date = d.date; event.start = d.start; event.end = d.end; }
      EVENTS.push(event);
      state.deletedEvents = state.deletedEvents.filter((x) => x !== event.id);
      P.data.newDraft = null;
      P.baseGo('cal-day');
      P.syncHash(true);
      toast('已创建日程 · ' + (d.allDay ? '全天' : d.start + '–' + d.end));
      return;
    }
    const todo = {
      id: 'local-' + (++state.localNo), title, cal: d.cal || state.defaultCal || 'personal',
      priority: priorityValue(d.priority),
      tags: (d.tags || []).slice(), note: '', subtasks: [], status: 'open',
      repeat: d.repeat || '', repeatEnd: d.repeatEnd || '',
      repeatUntil: d.repeatUntil || '', repeatCount: d.repeatCount || 0,
    };
    if (d.due) { todo.due = d.due; if (d.dueTime) todo.dueTime = d.dueTime; }
    if (d.plan) todo.plan = d.plan;
    if (d.remind && d.remind !== '不提醒') todo.remind = d.remind;
    TODOS.unshift(todo);
    P.data.newDraft = null;
    P.baseGo('todo-inbox');
    P.syncHash(true);
    toast('已记下待办');
  });

  /* ---------------- priority markers + "high floats up" in todo lists ---------------- */
  function rank(v) { return { 1: 0, 5: 1, 9: 2, 0: 3 }[Number(v)] == null ? 2 : ({ 1: 0, 5: 1, 9: 2, 0: 3 }[Number(v)]); }
  function runsAfter(head) {
    const rows = [];
    let n = head.nextElementSibling;
    while (n && n.classList && n.classList.contains('todo-row')) { rows.push(n); n = n.nextElementSibling; }
    return rows;
  }
  registerEnhancer((root) => {
    if (!/^todo-(inbox|all|date)$/.test(state.screen)) return;
    qa('.todo-row', root).forEach((row) => {
      const t = todoById(row.dataset.id);
      if (!t) return;
      const v = Number(t.priority) || 0;
      row.dataset.priority = String(v);
      const side = q('.todo-side', row);
      if (!side) return;
      let badge = q('.prio-badge', side);
      const lab = priorityLabel(v);
      const show = lab === '高' || lab === '低';
      if (!show) { if (badge) badge.remove(); return; }
      if (!badge) {
        badge = document.createElement('span');
        badge.className = 'prio-badge';
        side.insertBefore(badge, side.firstChild);
      }
      badge.textContent = lab;
      badge.title = '优先级 ' + lab;
      badge.style.cssText = lab === '高'
        ? 'font-size:9px;line-height:1;padding:3px 5px;border-radius:4px;background:var(--ink);color:#fff;margin-right:2px;flex:none'
        : 'font-size:9px;line-height:1;padding:3px 5px;border-radius:4px;border:1px solid var(--hair-2);color:var(--muted);margin-right:2px;flex:none';
    });
    qa('.group-head', root).forEach((head) => {
      const rows = runsAfter(head);
      if (rows.length < 2) return;
      const sorted = rows.slice().sort((a, b) => rank(a.dataset.priority) - rank(b.dataset.priority));
      if (sorted.every((r, i) => r === rows[i])) return;
      rows.forEach((r) => r.remove());
      let at = head;
      sorted.forEach((r) => { at.parentNode.insertBefore(r, at.nextSibling); at = r; });
    });
  });

  /* ---------------- quick add: real sentence parsing ---------------- */
  const CN = { 零: 0, 〇: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
  function cnNum(s) {
    s = String(s || '').trim();
    if (/^\d+$/.test(s)) return Number(s);
    if (s === '十') return 10;
    let m = /^十([一二两三四五六七八九])$/.exec(s);
    if (m) return 10 + CN[m[1]];
    m = /^([一二两三四五六七八九])十([一二两三四五六七八九])?$/.exec(s);
    if (m) return CN[m[1]] * 10 + (m[2] ? CN[m[2]] : 0);
    if (s.length === 1 && CN[s] != null) return CN[s];
    return NaN;
  }
  function dowOf(day) { return new Date(day + 'T00:00:00Z').getUTCDay(); } // 0 Sun … 6 Sat
  const WD_MAP = { 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6, 日: 0, 天: 0 };

  function parseQuickDate(text) {
    if (/大后天/.test(text)) return addDays(TODAY, 3);
    if (/后天/.test(text)) return addDays(TODAY, 2);
    if (/明天|明日/.test(text)) return addDays(TODAY, 1);
    if (/今天|今日/.test(text)) return TODAY;
    let m = /(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?/.exec(text);
    if (m) {
      const y = Number(TODAY.slice(0, 4));
      return y + '-' + String(Number(m[1])).padStart(2, '0') + '-' + String(Number(m[2])).padStart(2, '0');
    }
    m = /(\d{4})\s*[\/\-]\s*(\d{1,2})\s*[\/\-]\s*(\d{1,2})/.exec(text);
    if (m) return m[1] + '-' + String(Number(m[2])).padStart(2, '0') + '-' + String(Number(m[3])).padStart(2, '0');
    m = /(?:^|[^\d])(\d{1,2})\s*[\/\-]\s*(\d{1,2})(?!\d)/.exec(text);
    if (m) {
      const y = Number(TODAY.slice(0, 4));
      return y + '-' + String(Number(m[1])).padStart(2, '0') + '-' + String(Number(m[2])).padStart(2, '0');
    }
    m = /下周([一二三四五六日天])?/.exec(text);
    if (m) {
      const dow = dowOf(TODAY);
      const nextMon = addDays(TODAY, ((8 - dow) % 7) || 7);
      if (!m[1]) return nextMon;
      return addDays(nextMon, WD_MAP[m[1]] === 0 ? 6 : WD_MAP[m[1]] - 1);
    }
    m = /(?:周|星期|礼拜)([一二三四五六日天])/.exec(text);
    if (m) {
      const target = WD_MAP[m[1]];
      const dow = dowOf(TODAY);
      const delta = (target - dow + 7) % 7;
      return addDays(TODAY, delta);
    }
    return '';
  }

  function applyPeriod(hour, period) {
    if (!period) return hour;
    if (period === '凌晨' || period === '早上' || period === '早晨' || period === '上午') return hour === 12 ? 0 : hour;
    if (period === '中午') return hour < 11 ? hour + 12 : hour;
    if (period === '下午' || period === '傍晚' || period === '晚上' || period === '夜里' || period === '夜晚') return hour < 12 ? hour + 12 : hour;
    return hour;
  }

  function parseQuickTime(text) {
    const periodRe = '(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜晚)';
    let m = new RegExp(periodRe + '?\\s*(\\d{1,2})\\s*[:：]\\s*(\\d{2})').exec(text);
    if (m) {
      let h = Number(m[2]); const mi = Number(m[3]);
      h = applyPeriod(h, m[1]);
      if (h >= 0 && h <= 23 && mi >= 0 && mi <= 59) return { hour: h, minute: mi };
    }
    m = new RegExp(periodRe + '?\\s*(\\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\\s*[点时](?:(半|一刻|三刻)|(\\d{1,2})\\s*分?|([零〇一二两三四五六七八九十]{1,3})\\s*分?)?').exec(text);
    if (!m) return null;
    let h = cnNum(m[2]);
    if (!Number.isFinite(h)) return null;
    let mi = 0;
    if (m[3] === '半') mi = 30;
    else if (m[3] === '一刻') mi = 15;
    else if (m[3] === '三刻') mi = 45;
    else if (m[4]) mi = Number(m[4]);
    else if (m[5]) mi = cnNum(m[5]);
    if (!Number.isFinite(mi)) mi = 0;
    h = applyPeriod(h, m[1]);
    if (h < 0 || h > 23 || mi < 0 || mi > 59) return null;
    return { hour: h, minute: mi };
  }

  function quickDuration(text) {
    if (/半小时|30\s*分钟/.test(text)) return 30;
    const m = /(\d{1,2}|[一二两三四五六七八九十])\s*个?\s*小时/.exec(text);
    if (m) { const n = cnNum(m[1]); if (n > 0 && n <= 8) return n * 60; }
    return 60;
  }

  function parseQuickSentence(text) {
    const raw = String(text || '');
    const date = parseQuickDate(raw) || '';
    const time = parseQuickTime(raw);
    if (!time) return { date, time: null, start: '', end: '', plan: null };
    const start = String(time.hour).padStart(2, '0') + ':' + String(time.minute).padStart(2, '0');
    const total = time.hour * 60 + time.minute + quickDuration(raw);
    const eh = Math.min(23, Math.floor(total / 60)); const em = total % 60;
    const end = String(eh).padStart(2, '0') + ':' + String(em).padStart(2, '0');
    return { date: date || TODAY, time, start, end, plan: { date: date || TODAY, start, end } };
  }
  P.parseQuickSentence = parseQuickSentence;

  P.quickAdd = function quickAdd() {
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-field"><label>一句话</label><input class="proto-input" id="qa-title" placeholder="明天下午三点交报告"></div>
      <div class="qa-suggest-wrap" id="qa-suggest"></div>
      <div class="proto-field"><label>保存为</label><select class="proto-input" id="qa-type"><option value="todo">待办 · 默认</option><option value="event">日程</option></select></div>
      <div class="proto-note">识别到的时间只是建议：待办写为“计划执行”，日程写为开始/结束；没有识别到时间就只记标题，不写日期、计划或截止。</div>`;
    let removed = false;
    let lastParsed = null;
    const input = q('#qa-title', body);
    const sugg = q('#qa-suggest', body);

    function paintSuggestion() {
      const parsed = parseQuickSentence(input.value);
      lastParsed = parsed;
      const dayLabel = parsed.time ? (parsed.date === TODAY ? '今天' : P.dateMD ? P.dateMD(parsed.date) : parsed.date) : '';
      if (!parsed.time) {
        removed = false;
        sugg.innerHTML = input.value.trim()
          ? `<div class="proto-note" style="margin-top:-2px">没有识别到时间；保存后只记标题，无日期、无计划、无截止。</div>`
          : '';
        return;
      }
      if (removed) {
        sugg.innerHTML = `<div style="display:flex;align-items:center;gap:8px;margin:4px 0 8px;padding:8px 10px;border:1px dashed var(--hair-2);border-radius:8px;background:#fbfaf6"><span>⏱</span><div style="flex:1;min-width:0"><b style="display:block;font-size:11px">时间建议已移除</b><small style="color:var(--faint);font-size:10px">保存后只记标题；无日期、无计划、无截止。</small></div><button type="button" class="proto-btn" data-qa-restore>恢复</button></div>`;
        return;
      }
      const isEvent = q('#qa-type', body).value === 'event';
      sugg.innerHTML = `<div style="display:flex;align-items:center;gap:8px;margin:4px 0 8px;padding:8px 10px;border:1px solid var(--hair-2);border-radius:8px;background:#fbfaf6"><span>⏱</span><div style="flex:1;min-width:0"><b style="display:block;font-size:11px">${dayLabel} ${parsed.start}–${parsed.end} · ${isEvent ? '日程安排' : '建议安排'}</b><small style="color:var(--faint);font-size:10px">${isEvent ? '保存后直接写入日历。' : '保存后写为“计划执行”。'}可以移除。</small></div><button type="button" class="proto-btn" data-qa-remove>移除</button></div>`;
    }

    input.addEventListener('input', () => { removed = false; paintSuggestion(); });
    q('#qa-type', body).addEventListener('change', paintSuggestion);
    sugg.addEventListener('click', (e) => {
      if (e.target.closest('[data-qa-remove]')) { removed = true; paintSuggestion(); }
      if (e.target.closest('[data-qa-restore]')) { removed = false; paintSuggestion(); }
    });
    paintSuggestion();

    modal({
      title: '快速添加',
      body,
      actions: [
        { label: '取消' },
        { label: '保存', primary: true, onClick: (root) => {
          const raw = (q('#qa-title', root).value || '').trim();
          if (!raw) { q('#qa-title', root).focus(); return true; }
          const isEvent = q('#qa-type', root).value === 'event';
          const parsed = parseQuickSentence(raw);
          const useTime = !removed && !!parsed.time;
          const cal = state.defaultCal || 'personal';
          if (isEvent) {
            const id = 'quick-' + Date.now();
            if (useTime) {
              EVENTS.push({ id, title: raw, cal, date: parsed.date, start: parsed.start, end: parsed.end, remind: '15 分钟前' });
            } else {
              EVENTS.push({ id, title: raw, cal, date: parsed.date || TODAY, allDay: true, remind: '' });
            }
            P.baseGo('cal-day');
            P.syncHash(true);
            toast(useTime ? '已创建日程 · ' + parsed.start + '–' + parsed.end : '已创建日程 · 全天');
          } else {
            const todo = { id: 'quick-' + Date.now(), title: raw, cal, priority: priorityValue('中'), tags: [], status: 'open' };
            if (useTime) todo.plan = { date: parsed.date, start: parsed.start, end: parsed.end };
            TODOS.unshift(todo);
            P.baseGo('todo-inbox');
            P.syncHash(true);
            toast(useTime ? '已记下待办 · ' + parsed.start + ' 计划' : '已记下待办 · 未安排');
          }
        } },
      ],
    });
  };
})();
