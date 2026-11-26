/* DaySpark prototype v2 — designed pickers and detail/composer editing. */
(function () {
  const P = window.Proto;
  const { registerAction, registerEnhancer, modal, toast } = P;
  const q = (s, r) => (r || document).querySelector(s);
  const qa = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = P.esc;
  const WD = ['一', '二', '三', '四', '五', '六', '日'];

  function iso(d) {
    const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + day;
  }
  function parse(isoStr) { const [y, m, d] = String(isoStr || TODAY).split('-').map(Number); return new Date(y, m - 1, d); }
  function md(isoStr) { const [, m, d] = String(isoStr).split('-').map(Number); return m + ' 月 ' + d + ' 日'; }
  function short(isoStr) { const [, m, d] = String(isoStr).split('-').map(Number); return m + '/' + d; }

  /* ---------------- date picker ---------------- */
  P.openDatePicker = function (opts) {
    opts = opts || {};
    let value = opts.value || TODAY;
    let month = (value || TODAY).slice(0, 7);
    const body = document.createElement('div');
    let picked = value;

    function paint() {
      const [y, m] = month.split('-').map(Number);
      const first = new Date(y, m - 1, 1);
      const lead = (first.getDay() + 6) % 7;
      const total = new Date(y, m, 0).getDate();
      const prevTotal = new Date(y, m - 1, 0).getDate();
      const cells = [];
      for (let i = lead - 1; i >= 0; i--) cells.push({ day: prevTotal - i, out: true, date: iso(new Date(y, m - 1, prevTotal - i)) });
      for (let d = 1; d <= total; d++) cells.push({ day: d, out: false, date: iso(new Date(y, m - 1, d)) });
      while (cells.length % 7) { const d = cells.length - lead - total + 1; cells.push({ day: d, out: true, date: iso(new Date(y, m, d)) }); }
      body.innerHTML = `
        <div class="proto-cal-head">
          <button type="button" class="proto-btn" data-nav="-1" aria-label="上个月">‹</button>
          <b>${y} 年 ${m} 月</b>
          <button type="button" class="proto-btn" data-nav="1" aria-label="下个月">›</button>
        </div>
        <div class="proto-cal-grid">${WD.map((w) => `<div class="proto-cal-dow">${w}</div>`).join('')}
          ${cells.map((c) => `<button type="button" class="proto-cal-day${c.out ? ' is-out' : ''}${c.date === TODAY ? ' is-today' : ''}${c.date === picked ? ' is-on' : ''}" data-date="${c.date}">${c.day}</button>`).join('')}
        </div>
        <div class="proto-quick-row" style="margin-top:10px">
          <button type="button" data-quick="today">今天</button>
          <button type="button" data-quick="tomorrow">明天</button>
          <button type="button" data-quick="nextweek">下周今天</button>
          ${opts.allowClear ? '<button type="button" data-quick="clear">清除日期</button>' : ''}
        </div>`;
    }
    paint();
    const scrim = modal({
      title: opts.title || '选择日期', body,
      actions: [
        { label: '取消' },
        ...(opts.allowClear ? [{ label: '清除', onClick: () => opts.onPick('') }] : []),
        { label: '确定', primary: true, onClick: () => { opts.onPick(picked); } },
      ],
    });
    body.addEventListener('click', (e) => {
      const nav = e.target.closest('[data-nav]');
      if (nav) {
        const [y, m] = month.split('-').map(Number);
        const d = new Date(y, m - 1 + Number(nav.dataset.nav), 1);
        month = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
        paint(); return;
      }
      const day = e.target.closest('[data-date]');
      if (day) { picked = day.dataset.date; month = picked.slice(0, 7); paint(); return; }
      const quick = e.target.closest('[data-quick]');
      if (quick) {
        const k = quick.dataset.quick;
        if (k === 'clear') { picked = ''; scrim.remove(); opts.onPick(''); return; }
        picked = k === 'today' ? TODAY : k === 'tomorrow' ? addDays(TODAY, 1) : addDays(TODAY, 7);
        month = picked.slice(0, 7); paint();
      }
    });
    return scrim;
  };

  /* ---------------- time picker ---------------- */
  P.openTimePicker = function (opts) {
    opts = opts || {};
    const body = document.createElement('div');
    body.innerHTML = `
      <div class="proto-inline-row">
        <div class="proto-field" style="flex:1"><label>开始</label><input type="time" class="proto-input" id="tp-start" value="${opts.start || '09:00'}"></div>
        <div class="proto-field" style="flex:1"><label>结束</label><input type="time" class="proto-input" id="tp-end" value="${opts.end || '10:00'}"></div>
      </div>
      <div class="proto-quick-row">
        ${[['09:00', '09:30'], ['10:00', '11:00'], ['14:00', '15:00'], ['15:15', '16:00'], ['19:00', '20:00']].map(([a, b]) => `<button type="button" data-pair="${a},${b}">${a}–${b}</button>`).join('')}
      </div>
      <div class="proto-note">结束必须晚于开始；全天条目不写具体时间。</div>`;
    const scrim = modal({
      title: opts.title || '选择时间', body,
      actions: [
        { label: '取消' },
        { label: '确定', primary: true, onClick: () => {
          const s = q('#tp-start', body).value, e = q('#tp-end', body).value;
          if (!s || !e) { toast('开始和结束都要填写'); return true; }
          if (e <= s) { toast('结束时间必须晚于开始'); return true; }
          opts.onPick(s, e);
        } },
      ],
    });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-pair]'); if (!b) return;
      const [s, e2] = b.dataset.pair.split(',');
      q('#tp-start', body).value = s; q('#tp-end', body).value = e2;
    });
    return scrim;
  };

  /* ---------------- single time-of-day picker ---------------- */
  P.openTimeOfDay = function (opts) {
    opts = opts || {};
    const init = /^\d{2}:\d{2}$/.test(opts.value) ? opts.value : '09:00';
    let hour = init.slice(0, 2), minute = init.slice(3, 5);
    const HH = Array.from({ length: 24 }, (_, h) => String(h).padStart(2, '0'));
    const MM = ['00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55'];
    const body = document.createElement('div');
    function paint() {
      body.innerHTML = `
        <div class="proto-picked-time">${hour}:${minute}</div>
        <div class="proto-field"><label>小时</label><div class="proto-tag-pick">${HH.map((h) => `<button type="button" class="${h === hour ? 'is-on' : ''}" data-h="${h}">${h}</button>`).join('')}</div></div>
        <div class="proto-field"><label>分钟</label><div class="proto-tag-pick">${MM.map((m) => `<button type="button" class="${m === minute ? 'is-on' : ''}" data-m="${m}">${m}</button>`).join('')}</div></div>
        <div class="proto-quick-row">${['09:00', '12:00', '14:00', '15:00', '18:00', '20:00'].map((t) => `<button type="button" data-set="${t}">${t}</button>`).join('')}</div>
        <div class="proto-note">时间以 5 分钟为步进；日历拖动按 15 分钟吸附。</div>`;
    }
    paint();
    const scrim = modal({
      title: opts.title || '选择时间', body,
      actions: [
        { label: '取消' },
        ...(opts.allowClear ? [{ label: '清除', onClick: () => opts.onPick('') }] : []),
        { label: '确定', primary: true, onClick: () => opts.onPick(hour + ':' + minute) },
      ],
    });
    body.addEventListener('click', (e) => {
      const h = e.target.closest('[data-h]');
      if (h) { hour = h.dataset.h; paint(); return; }
      const m = e.target.closest('[data-m]');
      if (m) { minute = m.dataset.m; paint(); return; }
      const s = e.target.closest('[data-set]');
      if (s) { hour = s.dataset.set.slice(0, 2); minute = s.dataset.set.slice(3, 5); paint(); }
    });
    return scrim;
  };

  /* ---------------- repeat picker ---------------- */
  P.openRepeatPicker = function (opts) {
    opts = opts || {};
    let current = opts.repeat || '';
    let days = [];
    const m = /^每周(.+)$/.exec(current);
    if (m) days = m[1].split('、').filter(Boolean);
    let interval = /^每 2 周/.test(current) ? 2 : 1;
    let end = opts.repeatEnd || '永不结束';
    let until = opts.repeatUntil || '';
    let count = opts.repeatCount || 10;
    const body = document.createElement('div');
    function paint() {
      const base = ['不重复', '每天', '每周', '每 2 周', '每月', '每年'];
      body.innerHTML = `
        <div class="proto-list">${base.map((o) => `<button type="button" class="proto-list-row${(current === o || (o === '每周' && m && interval === 1)) ? ' is-on' : ''}" data-repeat="${o}"><span class="grow">${o}</span>${(current === o) ? '<span class="proto-badge">当前</span>' : ''}</button>`).join('')}</div>
        <div class="proto-field" style="margin-top:8px"><label>自定义 · 每周的哪几天</label>
          <div class="proto-tag-pick" data-days>${WD.map((w, i) => `<button type="button" class="${days.includes(w) ? 'is-on' : ''}" data-day="${w}">周${w}</button>`).join('')}</div>
        </div>
        <div class="proto-field"><label>结束</label>
          <div class="proto-seg" data-end>
            ${['永不结束', '在日期', '重复次数'].map((x) => `<button type="button" class="${end === x ? 'is-on' : ''}" data-endv="${x}">${x}</button>`).join('')}
          </div>
        </div>
        <div class="proto-field" data-until style="${end === '在日期' ? '' : 'display:none'}"><label>结束日期</label><button type="button" class="proto-input" data-proto-action="rp-until" style="text-align:left">${esc(until || '选择日期')}</button></div>
        <div class="proto-field" data-count style="${end === '重复次数' ? '' : 'display:none'}"><label>重复次数</label><input class="proto-input" type="number" min="1" max="99" id="rp-count" value="${count}"></div>
        <div class="proto-note" data-summary>${repeatText()}</div>`;
    }
    function repeatText() {
      if (!current || current === '不重复') return '不重复；保存后不写重复规则。';
      const tail = end === '在日期' && until ? '到 ' + until : end === '重复次数' ? '共 ' + count + ' 次' : end;
      if (days.length) return '每' + (interval === 2 ? ' 2 周' : '周') + ' · 周' + days.join('、周') + ' · ' + tail;
      return current + ' · ' + tail;
    }
    paint();
    const scrim = modal({
      title: opts.title || '重复', body,
      actions: [
        { label: '取消' },
        { label: '应用', primary: true, onClick: () => {
          let r = current;
          if (days.length) r = (interval === 2 ? '每 2 周' : '每周') + days.join('、');
          opts.onPick(r === '不重复' ? '' : r, end, { until, count: Number(count) || 10 });
        } },
      ],
    });
    body.addEventListener('change', (e) => {
      if (e.target.id === 'rp-count') { count = Number(e.target.value) || 10; const sm = q('[data-summary]', body); if (sm) sm.textContent = repeatText(); }
    });
    body.addEventListener('click', (e) => {
      const r = e.target.closest('[data-repeat]');
      if (r) {
        const v = r.dataset.repeat;
        current = v === '不重复' ? '' : v;
        days = v === '每周' ? days : [];
        interval = v === '每 2 周' ? 2 : 1;
        paint(); return;
      }
      const d = e.target.closest('[data-day]');
      if (d) {
        const w = d.dataset.day;
        days = days.includes(w) ? days.filter((x) => x !== w) : days.concat([w]);
        if (days.length) current = '每周';
        paint(); return;
      }
      const ev = e.target.closest('[data-endv]');
      if (ev) { end = ev.dataset.endv; paint(); return; }
      if (e.target.closest('[data-proto-action="rp-until"]')) {
        P.openDatePicker({ value: until || TODAY, onPick: (v) => { until = v || TODAY; paint(); } });
      }
    });
    return scrim;
  };

  // Reminder picker is owned by flows-v3-pickers.js (anchor rules live there).

  /* ---------------- priority / calendar / tag ---------------- */
  P.openPriorityPicker = function (opts) {
    const values = [['无', 0, '不参与排序'], ['低', 1, '列表靠后'], ['中', 5, '默认'], ['高', 9, '列表靠前并加标记']];
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-list">${values.map(([n, v, s]) => `<button type="button" class="proto-list-row" data-pri="${v}"><span class="grow">${n}<small>${s}</small></span></button>`).join('')}</div>`;
    const scrim = modal({ title: '优先级', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-pri]'); if (!b) return;
      scrim.remove(); opts.onPick(Number(b.dataset.pri));
    });
  };

  P.openCalendarPicker = function (opts) {
    const body = document.createElement('div');
    body.className = 'proto-list';
    function paint() {
      body.innerHTML = calIds().map((id) => `<button type="button" class="proto-list-row" data-cal="${id}"><span class="cal-dot" style="background:${calOf(id).color}"></span><span class="grow">${esc(calOf(id).name)}${id === state.defaultCal ? '<small>默认日历</small>' : ''}</span>${opts.value === id ? '<span class="proto-badge">当前</span>' : ''}</button>`).join('') + '<button type="button" class="proto-list-row" data-newcal><span class="grow">＋ 新建日历</span></button>';
    }
    paint();
    const scrim = modal({ title: '日历', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-cal]');
      if (b) { scrim.remove(); opts.onPick(b.dataset.cal); return; }
      if (e.target.closest('[data-newcal]')) {
        P.prompt({
          title: '新建日历', label: '名称', placeholder: '例如：副业',
          onConfirm: (name) => {
            if (!name) { toast('先写日历名称'); return; }
            let id = name.toLowerCase().replace(/[^a-z0-9一-龥]+/g, '-').replace(/^-|-$/g, '') || 'calendar';
            let n = 2; const base = id; while (CAL[id]) id = base + '-' + n++;
            CAL[id] = { name, color: '#4f7bbf', bg: '#dce7f7', ink: '#1e3557' };
            scrim.remove(); opts.onPick(id); toast('已创建日历 · ' + name);
          },
        });
      }
    });
    return scrim;
  };

  P.openTagPicker = function (selected, onPick) {
    let picked = (selected || []).slice();
    const body = document.createElement('div');
    function paint() {
      body.innerHTML = `<div class="proto-tag-pick">${P.data.tags.map((t) => `<button type="button" class="${picked.includes(t.name) ? 'is-on' : ''}" data-tag="${esc(t.name)}">${esc(t.name)}</button>`).join('')}</div>
        <div class="proto-inline-row" style="margin-top:10px"><input class="proto-input" id="tp-new" placeholder="新标签名称"><button type="button" class="proto-btn" data-newtag>新建</button></div>
        <div class="proto-note">标签可以多选；新建后立即选中。标签不是日历，不改变条目归属。</div>`;
    }
    paint();
    const scrim = modal({
      title: '标签', body,
      actions: [{ label: '取消' }, { label: '应用' + (picked.length ? `（${picked.length}）` : ''), primary: true, onClick: () => onPick(picked) }],
    });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-tag]');
      if (b) { const n = b.dataset.tag; picked = picked.includes(n) ? picked.filter((x) => x !== n) : picked.concat([n]); paint(); return; }
      if (e.target.closest('[data-newtag]')) {
        const n = (q('#tp-new', body).value || '').trim();
        if (!n) { toast('先写标签名称'); return; }
        if (!P.data.tags.some((t) => t.name === n)) P.data.tags.push({ name: n, color: '#4f7bbf' });
        if (!picked.includes(n)) picked.push(n);
        paint(); toast('已创建标签 · ' + n);
      }
    });
    return scrim;
  };

  /* ---------------- occurrence scope ---------------- */
  P.openOccurrence = function (opts) {
    const day = opts.day || TODAY;
    const body = document.createElement('div');
    body.innerHTML = `<div class="proto-list">
      <button type="button" class="proto-list-row" data-scope="one"><span class="grow">仅这一次<small>只删除 ${esc(day)} 这一次；系列和其他日期保持原样。</small></span></button>
      <button type="button" class="proto-list-row" data-scope="future"><span class="grow">这一次及以后<small>删除 ${esc(day)} 及之后的实例；之前的保留。</small></span></button>
      <button type="button" class="proto-list-row" data-scope="all"><span class="grow">整个系列<small>删除全部实例，包括已经过去的。</small></span></button>
    </div>`;
    const scrim = modal({ title: opts.title || '应用到哪些实例？', body, actions: [{ label: '取消' }] });
    body.addEventListener('click', (e) => {
      const b = e.target.closest('[data-scope]'); if (!b) return;
      scrim.remove(); opts.onPick(b.dataset.scope);
    });
  };

  /* ---------------- draft helpers ---------------- */
  function activeDraft() {
    if (state.draft) return state.draft;
    if (state.drawer && state.drawerEdit) {
      const ref = activeEditRef();
      return ref ? draftFor(ref) : null;
    }
    return null;
  }
  function repaintDraft() { render(); }

  /* ---------------- detail: tags, subtasks, attachment ---------------- */
  registerAction('start-edit', () => { clearDraft(); state.drawerEdit = true; render(); });
  registerAction('detail-add-tag', () => {
    syncDraftFromDom();
    const d = activeDraft(); if (!d) return;
    P.openTagPicker(d.tags || [], (tags) => { d.tags = tags; repaintDraft(); toast('标签已更新'); });
  });

  registerAction('detail-subtask-add', () => {
    syncDraftFromDom();
    const d = activeDraft(); if (!d) return;
    P.prompt({
      title: '添加子任务', label: '子任务', placeholder: '只写标题',
      onConfirm: (v) => {
        if (!v) { toast('先写子任务标题'); return; }
        d.subtasks = d.subtasks || [];
        d.subtasks.push({ title: v, done: false });
        repaintDraft(); toast('已添加子任务');
      },
    });
  });

  registerAction('detail-attach', () => {
    syncDraftFromDom();
    const d = activeDraft(); if (!d) return;
    const input = document.createElement('input');
    input.type = 'file';
    input.className = 'proto-hidden-input';
    document.body.appendChild(input);
    input.addEventListener('change', () => {
      const f = input.files && input.files[0];
      if (f) {
        d.attach = f.name;
        d.attachSize = f.size;
        render(); toast('已添加附件 · ' + f.name + '（模拟上传）');
      }
      input.remove();
    });
    input.click();
  });

  registerAction('detail-attach-remove', () => {
    const d = activeDraft(); if (!d) return;
    d.attach = ''; d.attachSize = 0; render(); toast('已移除附件');
  });

  /* ---------------- detail: repeat / reminder custom ---------------- */
  registerAction('detail-repeat-custom', () => {
    syncDraftFromDom();
    const d = activeDraft(); if (!d) return;
    P.openRepeatPicker({ repeat: d.repeat, repeatEnd: d.repeatEnd, repeatUntil: d.repeatUntil, repeatCount: d.repeatCount, onPick: (r, end, extra) => {
      d.repeat = r; d.repeatEnd = end; d.repeatUntil = extra && extra.until || ''; d.repeatCount = extra && extra.count || 0;
      render(); toast(r ? '重复 · ' + r : '已设为不重复');
    } });
  });
  /* ---------------- detail: save / delete scope ---------------- */
  // Event time must be valid before the master commits the draft.
  document.addEventListener('click', (e) => {
    const save = e.target.closest('[data-action="save-detail"]');
    if (!save) return;
    const ref = activeEditRef();
    if (!ref || ref.type !== 'event') return;
    const d = draftFor(ref);
    if (!d || d.allDay || (d.startDate && d.endDate)) return;
    if (d.start && d.end && d.end <= d.start) {
      e.preventDefault(); e.stopPropagation();
      state.variant = 'validation';
      render();
      toast('结束时间必须晚于开始');
    }
  }, true);

  document.addEventListener('click', (e) => {
    const save = e.target.closest('[data-action="save-detail"], [data-action="retry-save"]');
    if (!save) return;
    if (!P.demo.saveError) return;
    e.preventDefault();
    e.stopPropagation();
    state.variant = 'save-error';
    P.demo.saveError = false;
    render();
    toast('保存失败 · 输入已保留，可以重试');
  }, true);

  registerAction('delete-scope', (el) => {
    const ref = activeEditRef() || state.drawer;
    const isEvent = ref && ref.type === 'event';
    const item = ref ? detailSource(ref) : null;
    if (!item) return;
    const anchor = isEvent ? (item.date || item.startDate || TODAY) : ((item.plan && item.plan.date) || item.due || TODAY);
    const occDay = (state.occurId === item.id && state.occurDate) ? state.occurDate : anchor;
    const calName = calOf(item.cal).name;
    const original = JSON.parse(JSON.stringify(item));
    function trash(extra) {
      state.trashExtra.push({
        id: item.id, title: item.title,
        sub: (isEvent ? '日程' : '待办') + ' · ' + calName + ' · ' + extra,
        snap: original,
      });
    }
    function removeWhole(scopeLabel) {
      if (!isEvent) {
        if (!state.deletedTodos.includes(item.id)) state.deletedTodos.push(item.id);
      } else {
        if (!state.deletedEvents.includes(item.id)) state.deletedEvents.push(item.id);
      }
      trash('刚刚删除');
      state.drawer = null; state.drawerEdit = false; state.confirmDelete = false;
      render(); toast('已删除' + scopeLabel);
    }
    P.openOccurrence({
      title: '删除重复' + (isEvent ? '日程' : '待办'),
      day: occDay,
      onPick: (scope) => {
        if (scope === 'one') {
          state.skipped = state.skipped || [];
          const key = item.id + '@' + occDay;
          if (!state.skipped.includes(key)) state.skipped.push(key);
          state.drawer = null; state.drawerEdit = false; render();
          toast('已删除 ' + occDay + ' 这一次 · 系列保留');
          return;
        }
        if (scope === 'future') {
          const cut = addDays(occDay, -1);
          if (cut < anchor) { removeWhole('整个系列（从第一次起）'); return; }
          // Keep earlier instances: stop the rule the day before this occurrence.
          item.repeatUntil = cut;
          item.repeatEnd = '在日期';
          item.repeatCount = 0;
          trash('已删除 ' + occDay + ' 及以后');
          state.drawer = null; state.drawerEdit = false;
          render();
          toast('已删除 ' + occDay + ' 及以后的实例；之前的保留');
          return;
        }
        removeWhole('整个系列');
      },
    });
  });

  // Keep the draft in sync while typing, so opening a picker never drops text.
  document.addEventListener('input', (e) => {
    const f = e.target.closest && e.target.closest('[data-mfield]');
    if (!f) return;
    const ref = activeEditRef();
    if (!ref) return;
    const d = draftFor(ref);
    if (!d) return;
    d[f.dataset.mfield] = f.value;
  });
  function syncDraftFromDom() {
    const ref = activeEditRef(); if (!ref) return;
    const d = draftFor(ref); if (!d) return;
    const title = q('#detail-title'); if (title) d.title = title.value;
    qa('[data-mfield]').forEach((f) => { if (f.id === 'detail-title') return; d[f.dataset.mfield] = f.value; });
  }

  /* ---------------- plan selector: same designed calendar ---------------- */
  registerEnhancer((root) => {
    qa('#plan-date', root).forEach((inp) => {
      if (inp.dataset.v2cal) return;
      inp.dataset.v2cal = '1';
      inp.type = 'text';
      inp.setAttribute('inputmode', 'numeric');
      inp.classList.add('v2-date-field');
      inp.style.cursor = 'pointer';
      inp.addEventListener('click', (e) => {
        e.preventDefault();
        P.openDatePicker({
          value: /^\d{4}-\d{2}-\d{2}$/.test(inp.value) ? inp.value : TODAY,
          onPick: (v) => {
            if (!v) return;
            inp.value = v;
            inp.dispatchEvent(new Event('change', { bubbles: true }));
          },
        });
      });
    });
    qa('#plan-start, #plan-end', root).forEach((inp) => {
      if (inp.dataset.v2clock) return;
      inp.dataset.v2clock = '1';
      inp.type = 'text';
      inp.setAttribute('inputmode', 'numeric');
      inp.classList.add('v2-time-field');
      inp.style.cursor = 'pointer';
      inp.addEventListener('click', (e) => {
        e.preventDefault();
        P.openTimeOfDay({
          title: inp.id === 'plan-start' ? '开始时间' : '结束时间',
          value: inp.value || '15:00',
          onPick: (v) => {
            if (!v) return;
            inp.value = v;
            inp.dispatchEvent(new Event('change', { bubbles: true }));
          },
        });
      });
    });
    // A start later than the end must say so, not show a bare dash.
    if (!window.__v2planWarn) {
      window.__v2planWarn = true;
      document.addEventListener('change', (e) => {
        const t = e.target;
        if (!t || (t.id !== 'plan-start' && t.id !== 'plan-end')) return;
        const s = (document.getElementById('plan-start') || {}).value;
        const e2 = (document.getElementById('plan-end') || {}).value;
        const dur = document.getElementById('plan-duration');
        if (!dur || !s || !e2) return;
        const bad = mins(e2) <= mins(s);
        dur.textContent = bad ? '结束早于开始' : planDuration(s, e2);
        dur.style.color = bad ? 'var(--red)' : '';
      });
    }
  });

  /* ---------------- detail enhancer: fix wires and add affordances ---------------- */
  registerEnhancer((root) => {
    if (!state.drawer && !state.screen.startsWith('detail-')) return;
    const d = activeDraft();
    const editing = !!state.draft || state.drawerEdit;
    // Subtask "添加" must add a subtask, not open the tag picker.
    qa('.d-sec', root).forEach((sec) => {
      const head = q('.d-sec-head', sec);
      if (!head) return;
      const label = (head.querySelector('span') || {}).textContent || '';
      const btn = q('button', head);
      if (btn && (head.textContent.includes('子任务') || head.textContent.includes('标签'))) {
        btn.dataset.protoAction = editing ? (head.textContent.includes('子任务') ? 'detail-subtask-add' : 'detail-add-tag') : 'start-edit';
        btn.dataset.reason = '先在详情里点“编辑”，再添加。';
      }
    });
    // Show the real attachment name, size and a remove control.
    if (editing) {
      const attachSec = qa('.d-sec', root).find((s) => s.textContent.includes('附件'));
      if (attachSec) {
        const at = q('.attach', attachSec);
        if (at) {
          at.innerHTML = `${ico('folder', 13)} ${d && d.attach ? esc(d.attach) + (d.attachSize ? ' · ' + Math.round(d.attachSize / 1024) + ' KB' : '') : '没有附件'}${d && d.attach ? '<button type="button" class="del" data-proto-action="detail-attach-remove" aria-label="移除附件">×</button>' : ''}`;
        }
      }
      // Date fields open the designed calendar (desktop and phone share it),
      // so editing never depends on the platform date control alone.
      qa('input[type="date"][data-mfield]', root).forEach((inp) => {
        if (inp.dataset.v2cal) return;
        inp.dataset.v2cal = '1';
        const before = inp.value;
        inp.type = 'text';
        inp.setAttribute('inputmode', 'numeric');
        inp.setAttribute('placeholder', 'YYYY-MM-DD');
        inp.classList.add('v2-date-field');
        inp.style.cursor = 'pointer';
        inp.addEventListener('click', (e) => {
          e.preventDefault();
          const field = inp.dataset.mfield;
          P.openDatePicker({
            value: /^\d{4}-\d{2}-\d{2}$/.test(inp.value) ? inp.value : (before || TODAY),
            allowClear: field === 'due' || field === 'repeatUntil',
            onPick: (v) => {
              inp.value = v;
              inp.dispatchEvent(new Event('input', { bubbles: true }));
              render();
              toast(v ? '日期 · ' + v : '已清除日期');
            },
          });
          inp.blur();
        });
      });
      // Time fields use the designed hour/minute picker.
      qa('input[type="time"][data-mfield]', root).forEach((inp) => {
        if (inp.dataset.v2clock) return;
        inp.dataset.v2clock = '1';
        inp.type = 'text';
        inp.setAttribute('inputmode', 'numeric');
        inp.setAttribute('placeholder', 'HH:MM');
        inp.classList.add('v2-time-field');
        inp.style.cursor = 'pointer';
        inp.addEventListener('click', (e) => {
          e.preventDefault();
          const isDue = inp.dataset.mfield === 'dueTime';
          P.openTimeOfDay({
            title: isDue ? '截止时间' : '时间',
            value: inp.value || (isDue ? '18:00' : '09:00'),
            allowClear: isDue,
            onPick: (v) => {
              inp.value = v;
              inp.dispatchEvent(new Event('input', { bubbles: true }));
              inp.dispatchEvent(new Event('change', { bubbles: true }));
              render();
              toast(v ? '时间 · ' + v : '已清除时间');
            },
          });
          inp.blur();
        });
      });
      // Custom repeat / reminder affordances next to the native selects.
      qa('select[data-mfield="repeat"], select[data-mfield="remind"]', root).forEach((sel) => {
        if (sel.dataset.v2) return;
        sel.dataset.v2 = '1';
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'mini';
        b.style.marginLeft = '6px';
        b.textContent = '自定义…';
        b.dataset.protoAction = sel.dataset.mfield === 'repeat' ? 'detail-repeat-custom' : 'detail-remind-custom';
        const wrap = document.createElement('div');
        wrap.className = 'v2-select-row';
        sel.parentNode.insertBefore(wrap, sel);
        wrap.appendChild(sel);
        wrap.appendChild(b);
      });
      // Subtask rows: toggle, delete, rename.
      if (d && Array.isArray(d.subtasks)) {
        const subSec = qa('.d-sec', root).find((s) => s.textContent.includes('子任务'));
        if (subSec) {
          const rows = qa('.subtask', subSec);
          rows.forEach((row, i) => {
            if (!d.subtasks[i]) return;
            row.dataset.index = i;
            row.style.cursor = 'pointer';
            if (!q('button', row)) {
              const del = document.createElement('button');
              del.type = 'button';
              del.className = 'del';
              del.textContent = '×';
              del.setAttribute('aria-label', '删除子任务');
              del.style.marginLeft = 'auto';
              row.appendChild(del);
            }
          });
          if (!subSec.dataset.bound) {
            subSec.dataset.bound = '1';
            subSec.addEventListener('click', (e) => {
              const row = e.target.closest('.subtask'); if (!row || row.dataset.index == null) return;
              const i = Number(row.dataset.index);
              const cur = activeDraft(); if (!cur || !cur.subtasks || !cur.subtasks[i]) return;
              if (e.target.closest('.del')) {
                cur.subtasks.splice(i, 1); render(); toast('已删除子任务'); return;
              }
              cur.subtasks[i].done = !cur.subtasks[i].done;
              render();
            });
          }
        }
      }
    }
    // Repeating item: route delete through the scope picker.
    const ref = activeEditRef() || state.drawer;
    const item = ref ? detailSource(ref) : null;
    if (item && item.repeat) {
      qa('[data-action="delete"]', root).forEach((b) => { b.dataset.protoAction = 'delete-scope'; });
    }
  });

  registerAction('open-full-page', () => {
    const ref = state.drawer; if (!ref) return;
    const screen = ref.type === 'event' ? 'detail-event' : 'detail-todo';
    state.drawer = ref;
    P.baseGo(screen);
    state.variant = 'page';
    state.drawerEdit = true;
    render();
    P.syncHash(true);
  });

  /* ---------------- composer: extra fields, real pickers, dirty guard ---------------- */
  function draft() {
    if (!P.data.newDraft) {
      P.data.newDraft = {
        cal: state.defaultCal || 'personal', date: TODAY, start: '11:00', end: '12:00',
        allDay: false, endDate: '', loc: '', repeat: '', repeatEnd: '永不结束',
        remind: state.screen === 'new-event' ? '15 分钟前' : '不提醒',
        priority: '中', due: '', dueTime: '', plan: null, plans: [], tags: [], reminders: [], note: '',
        repeatUntil: '', repeatCount: 0,
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
  function paintField(label, value) {
    const row = fieldRow(label);
    const v = row && q('.v', row);
    if (v) v.textContent = value;
  }

  registerEnhancer((root) => {
    if (state.screen !== 'new-todo' && state.screen !== 'new-event') return;
    const d = draft();
    const titleEl = q('#new-title', root) || q('.new-page .form-input', root) || q('.m-detail-scroll .m-form-input', root);
    if (titleEl) {
      if (d.title && titleEl.value !== d.title) titleEl.value = d.title;
      if (!titleEl.dataset.v2) {
        titleEl.dataset.v2 = '1';
        titleEl.addEventListener('input', () => { d.title = titleEl.value; });
      }
    }
    // New todos need the same repeat fact the detail editor has.
    if (state.screen === 'new-todo' && !fieldRow('重复')) {
      const fields = q('.new-page .new-fields, .m-detail-scroll .new-fields', root);
      if (fields) {
        const row = document.createElement('div');
        row.className = 'cp-field';
        row.innerHTML = '<span class="k">重复</span><span class="v">不重复</span>';
        const remind = fieldRow('提醒');
        fields.insertBefore(row, remind || null);
      }
    }
    if (state.screen === 'new-todo' && !fieldRow('标签')) {
      const fields = q('.new-page .new-fields, .m-detail-scroll .new-fields', root);
      if (fields) {
        const row = document.createElement('div');
        row.className = 'cp-field';
        row.innerHTML = '<span class="k">标签</span><span class="v">无标签</span>';
        fields.appendChild(row);
      }
    }
    qa('.new-page .cp-field', root).forEach((row) => {
      const k = q('.k', row);
      if (!k) return;
      const label = (k.textContent || '').trim();
      row.style.cursor = 'pointer';
      row.dataset.protoAction = 'new-field';
      row.dataset.field = label;
    });
    paintField('截止', d.due ? (d.due === TODAY ? '今天' : short(d.due)) + (d.dueTime ? ' ' + d.dueTime : '') : '无截止');
    const draftPlans = (Array.isArray(d.plans) ? d.plans : []).filter((p) => p && (!p.state || p.state === 'active'));
    const firstDraftPlan = draftPlans.slice().sort((a, b) => String(a.date + a.start).localeCompare(String(b.date + b.start)))[0];
    paintField('计划执行', firstDraftPlan ? short(firstDraftPlan.date) + ' ' + firstDraftPlan.start + '–' + firstDraftPlan.end + (draftPlans.length > 1 ? ' · 共 ' + draftPlans.length + ' 段' : '') : '未安排');
    paintField('重复', d.repeat || '不重复');
    paintField('标签', (d.tags && d.tags.length) ? d.tags.join('、') : '无标签');
    const draftReminders = [d.remind].concat(d.reminders || []).filter((r) => r && r !== '不提醒');
    paintField('提醒', draftReminders.length ? Array.from(new Set(draftReminders)).join(' · ') : '不提醒');
    paintField('优先级', d.priority || '中');
  });

  registerAction('new-field', (el) => {
    const label = el.dataset.field || '';
    const d = draft();
    const ev = state.screen === 'new-event';

    if (label === '截止') {
      const body = document.createElement('div');
      body.innerHTML = `<div class="proto-seg" data-due-mode><button type="button" class="${!d.dueTime ? 'is-on' : ''}" data-mode="date">只写日期</button><button type="button" class="${d.dueTime ? 'is-on' : ''}" data-mode="time">日期 + 时间</button></div>
        <div class="proto-field" style="margin-top:8px"><label>日期</label><button type="button" class="proto-input" data-proto-action="composer-date" style="text-align:left">${esc(d.due || '选择日期')}</button></div>
        <div class="proto-field" data-time-wrap style="${d.dueTime ? '' : 'display:none'}"><label>时间</label><input type="time" class="proto-input" id="nf-due-time" value="${esc(d.dueTime || '18:00')}"></div>
        <div class="proto-note">截止不是时间占用；它只表示这件事什么时候必须完成。</div>`;
      const scrim = modal({ title: '截止', body, actions: [
        { label: '取消' },
        { label: '清除', onClick: () => { d.due = ''; d.dueTime = ''; render(); } },
        { label: '应用', primary: true, onClick: () => { d.dueTime = q('#nf-due-time', body).value || ''; if (!d.due) d.due = TODAY; render(); toast('截止已更新'); } },
      ] });
      let mode = d.dueTime ? 'time' : 'date';
      body.addEventListener('click', (e) => {
        const b = e.target.closest('[data-mode]');
        if (b) { mode = b.dataset.mode; qa('[data-mode]', body).forEach((x) => x.classList.toggle('is-on', x === b)); q('[data-time-wrap]', body).style.display = mode === 'time' ? '' : 'none'; }
        if (e.target.closest('[data-proto-action="composer-date"]')) {
          P.openDatePicker({ value: d.due || TODAY, allowClear: true, onPick: (v) => {
            d.due = v; const btn = q('[data-proto-action="composer-date"]', body); if (btn) btn.textContent = v || '选择日期';
          } });
        }
      });
      return;
    }

    if (label === '计划执行') {
      const plans = (d.plans = Array.isArray(d.plans) ? d.plans : []);
      const activePlans = () => plans.filter((p) => p && (!p.state || p.state === 'active'));
      const first = activePlans().slice().sort((a, b) => String(a.date + a.start).localeCompare(String(b.date + b.start)))[0];
      let date = first ? first.date : (d.date || TODAY);
      let start = first ? first.start : '15:00';
      let end = first ? first.end : '16:00';
      let occ = d.repeat ? ((first && first.occurrenceDate) || d.date || TODAY) : null;
      const body = document.createElement('div');
      function paint() {
        body.innerHTML = `<div class="proto-field"><label>日期</label><button type="button" class="proto-input" data-proto-action="composer-plan-date" style="text-align:left">${esc(date)}</button></div>
          ${d.repeat ? `<div class="proto-field"><label>这一次实例</label><button type="button" class="proto-input" data-proto-action="composer-plan-occ" style="text-align:left">${esc(occ || '选择这一次实例')}</button></div>` : ''}
          <div class="proto-inline-row" style="margin-top:6px"><div class="proto-field" style="flex:1"><label>开始</label><input type="time" class="proto-input" id="nf-plan-start" value="${esc(start)}"></div><div class="proto-field" style="flex:1"><label>结束</label><input type="time" class="proto-input" id="nf-plan-end" value="${esc(end)}"></div></div>
          <div class="proto-note">计划执行会占用日历时间；和截止是两件事。每次“加入”都是新增一段，不覆盖已有计划。${d.repeat ? ' 重复待办必须绑定选中的这一次实例。' : ''}</div>`;
      }
      function read() {
        const s = q('#nf-plan-start', body), e2 = q('#nf-plan-end', body);
        if (s) start = s.value || start;
        if (e2) end = e2.value || end;
      }
      paint();
      const scrim = modal({ title: '计划执行', body, actions: [
        { label: '取消' },
        { label: '清除全部', onClick: () => { d.plans = []; d.plan = null; render(); toast('已清除计划草稿'); } },
        { label: '加入草稿', primary: true, onClick: () => {
          read();
          if (end <= start) { toast('结束必须晚于开始'); return true; }
          if (d.repeat) {
            if (!occ) { toast('重复待办要先选这一次实例'); return true; }
            const anchor = d.repeatAnchor || d.date || TODAY;
            if (P.repeatMath && !P.repeatMath.repeatMatch(anchor, occ, d.repeat, { repeatUntil: d.repeatUntil, repeatCount: d.repeatCount })) {
              toast('选中的日期不是这个重复系列的实例'); return true;
            }
          }
          plans.push({
            id: 'draft-alloc-' + Date.now() + '-' + Math.floor(Math.random() * 1000),
            date, start, end, state: 'active',
            occurrenceDate: d.repeat ? occ : null, createdAt: Date.now(),
          });
          const sorted = activePlans().slice().sort((a, b) => String(a.date + a.start).localeCompare(String(b.date + b.start)));
          d.plan = sorted[0] || null;
          render();
          toast('已加入计划草稿 · 共 ' + activePlans().length + ' 段（保存后生效）');
        } },
      ] });
      body.addEventListener('click', (e) => {
        if (e.target.closest('[data-proto-action="composer-plan-date"]')) {
          read();
          P.openDatePicker({ value: date, onPick: (v) => { date = v || TODAY; paint(); } });
        }
        if (e.target.closest('[data-proto-action="composer-plan-occ"]')) {
          read();
          P.openDatePicker({ value: occ || d.date || TODAY, onPick: (v) => { if (!v) return; occ = v; date = v; paint(); } });
        }
      });
      return;
    }

    if (label === '时间') {
      const body = document.createElement('div');
      body.innerHTML = `<div class="proto-check"><input type="checkbox" id="nf-allday" ${d.allDay ? 'checked' : ''}><label for="nf-allday">全天（可跨日）</label></div>
        <div class="proto-field"><label>开始日期</label><button type="button" class="proto-input" data-proto-action="composer-start-date" style="text-align:left">${esc(d.date)}</button></div>
        <div class="proto-field" data-end-date style="${d.allDay && d.endDate ? '' : 'display:none'}"><label>结束日期</label><button type="button" class="proto-input" data-proto-action="composer-end-date" style="text-align:left">${esc(d.endDate || d.date)}</button></div>
        <div class="proto-inline-row" data-time-row style="${d.allDay ? 'display:none' : ''}"><div class="proto-field" style="flex:1"><label>开始</label><input type="time" class="proto-input" id="nf-start" value="${esc(d.start)}"></div><div class="proto-field" style="flex:1"><label>结束</label><input type="time" class="proto-input" id="nf-end" value="${esc(d.end)}"></div></div>
        <div class="proto-note">全天条目不写具体时刻；跨日时结束日期必须晚于开始日期。</div>`;
      const scrim = modal({ title: '时间', body, actions: [
        { label: '取消' },
        { label: '应用', primary: true, onClick: () => {
          d.allDay = q('#nf-allday', body).checked;
          d.start = q('#nf-start', body).value || '11:00';
          d.end = q('#nf-end', body).value || '12:00';
          if (!d.allDay && d.end <= d.start) { toast('结束必须晚于开始'); return true; }
          if (d.allDay && d.endDate && d.endDate < d.date) { toast('结束日期不能早于开始'); return true; }
          render(); toast('时间已更新');
        } },
      ] });
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
      return;
    }

    if (label === '全天') {
      d.allDay = !d.allDay; render(); toast(d.allDay ? '已设为全天' : '已取消全天'); return;
    }
    if (label === '地点') {
      P.prompt({ title: '地点', label: '地点', value: d.loc, placeholder: '例如：会议室 B', onConfirm: (v) => { d.loc = v; render(); toast(v ? '地点已更新' : '已清除地点'); } });
      return;
    }
    if (label === '日历') {
      P.openCalendarPicker({ value: d.cal, onPick: (id) => { d.cal = id; render(); toast('日历 · ' + calOf(id).name); } });
      return;
    }
    if (label === '重复') {
      P.openRepeatPicker({ repeat: d.repeat, repeatEnd: d.repeatEnd, repeatUntil: d.repeatUntil, repeatCount: d.repeatCount, onPick: (r, end, extra) => { d.repeat = r; d.repeatEnd = end; d.repeatUntil = extra && extra.until || ''; d.repeatCount = extra && extra.count || 0; render(); toast(r ? '重复 · ' + r : '不重复'); } });
      return;
    }
    if (label === '提醒') {
      P.openReminderPicker({ value: d.remind, onPick: (r) => { d.remind = r || '不提醒'; render(); toast(d.remind === '不提醒' ? '已关闭提醒' : '提醒 · ' + d.remind); } });
      return;
    }
    if (label === '优先级') {
      P.openPriorityPicker({ onPick: (v) => { d.priority = v === 0 ? '无' : v === 1 ? '低' : v === 9 ? '高' : '中'; render(); toast('优先级 · ' + d.priority); } });
      return;
    }
    if (label === '标签') {
      P.openTagPicker(d.tags || [], (tags) => { d.tags = tags; render(); toast(tags.length ? '标签已更新' : '已清除标签'); });
    }
  });

  registerAction('new-cancel', () => {
    const d = P.data.newDraft;
    const title = (q('#new-title') || q('.new-page .form-input') || {}).value || '';
    const dirty = !!title.trim() || !!(d && (d.due || d.plan || (d.plans || []).length || d.repeat || d.loc || d.allDay || (d.tags || []).length || (d.reminders || []).length || d.cal !== (state.defaultCal || 'personal') || d.priority !== '中' || d.remind !== (state.screen === 'new-event' ? '15 分钟前' : '不提醒')));
    if (!dirty) { goBackFromNew(); return; }
    modal({
      title: '离开这张表单？',
      body: '<div class="proto-note">标题和已填的字段还没有保存；离开会丢弃这次输入。</div>',
      actions: [
        { label: '留下', primary: true },
        { label: '丢弃', danger: true, onClick: () => { P.data.newDraft = null; goBackFromNew(); } },
      ],
    });
  });
  function goBackFromNew() {
    const ev = state.screen === 'new-event';
    P.baseGo(ev ? 'cal-week' : 'today');
    P.syncHash(true);
  }

  // new-save is owned by flows-v3-capture.js (delegated through v3-data).

  /* expose date format helpers */
  P.dateShort = short;
  P.dateMD = md;
})();
