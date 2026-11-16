/* Overlay primitives (toast, confirm, modal, sheet, menu) + shared row builders. */
(function () {
  const U = window.U;
  const S = window.Store;
  const t = (k, v) => I18N.t(k, v);

  // ---------- focus trap ----------
  const traps = [];
  function trap(node, onEscape) {
    const prev = document.activeElement;
    const selector = 'a[href],button:not([disabled]),input:not([disabled]),textarea:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';
    function keydown(e) {
      if (e.key === 'Escape' && onEscape) { e.stopPropagation(); onEscape(); return; }
      if (e.key !== 'Tab') return;
      const items = Array.from(node.querySelectorAll(selector)).filter((x) => x.offsetParent !== null);
      if (!items.length) return;
      const first = items[0], last = items[items.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
    document.addEventListener('keydown', keydown, true);
    const caret = prev && typeof prev.selectionStart === 'number'
      ? { s: prev.selectionStart, e: prev.selectionEnd } : null;
    traps.push({ node, keydown, prev, caret });
    const focusTarget = node.querySelector('[data-autofocus]') || node.querySelector(selector);
    if (focusTarget) setTimeout(() => focusTarget.focus(), 0);
  }
  function release(node) {
    const idx = traps.findIndex((x) => x.node === node);
    if (idx < 0) return;
    const entry = traps[idx];
    document.removeEventListener('keydown', entry.keydown, true);
    traps.splice(idx, 1);
    // A re-render may have replaced the control that opened the layer. Focus
    // the live node with the same identity instead of a detached one.
    let back = entry.prev;
    if (back && !back.isConnected && back.dataset && back.dataset.testid) {
      const id = back.dataset.id ? `[data-id="${back.dataset.id}"]` : '';
      back = document.querySelector(`[data-testid="${back.dataset.testid}"]${id}`) || null;
    }
    if (back && back.focus) {
      back.focus();
      if (entry.caret && typeof back.setSelectionRange === 'function') {
        try { back.setSelectionRange(entry.caret.s, entry.caret.e); } catch (_) {}
      }
    }
  }
  function releaseAll() {
    traps.slice().forEach((x) => release(x.node));
  }

  // ---------- toast ----------
  let toastTimer = null;
  function toast(message, opts) {
    const root = U.qs('#toast');
    root.innerHTML = '';
    const node = U.el('div', { class: 'toast' + (opts && opts.warn ? ' warn' : '') });
    const text = U.el('span', { text: message });
    node.appendChild(text);
    if (opts && opts.undo) {
      const b = U.el('button', { class: 'undo', text: t('undo') });
      b.addEventListener('click', () => { hide(); opts.undo(); });
      node.appendChild(b);
    }
    const x = U.el('button', { class: 'x', 'aria-label': t('close'), html: ICON('x', 14) });
    x.addEventListener('click', hide);
    node.appendChild(x);
    root.appendChild(node);
    function hide() { clearTimeout(toastTimer); root.innerHTML = ''; }
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hide, opts && opts.duration ? opts.duration : 4200);
    return { hide };
  }
  function hideToast() { U.qs('#toast').innerHTML = ''; }

  // ---------- modal / sheet ----------
  let openLayers = [];
  function closeTop() {
    const layer = openLayers[openLayers.length - 1];
    if (!layer) return false;
    layer.close();
    return true;
  }
  function closeAll() { openLayers.slice().forEach((l) => l.close()); }
  function hasOpenLayer() { return openLayers.length > 0; }
  function openLayer(build) {
    const host = U.qs('#overlay');
    const scrim = U.el('div', { class: build.kind === 'sheet' ? 'sheet-scrim' : 'modal-scrim' });
    const panel = U.el('div', { class: build.kind === 'sheet' ? 'sheet' : 'modal' + (build.cls ? ' ' + build.cls : '') });
    if (build.kind === 'sheet') panel.appendChild(U.el('div', { class: 'sheet-grip' }));
    if (build.kind !== 'sheet' && build.cls && build.cls.includes('confirm')) panel.classList.add('confirm');
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-modal', 'true');
    if (build.labelledBy) panel.setAttribute('aria-labelledby', build.labelledBy);
    scrim.appendChild(panel);
    host.appendChild(scrim);
    let closed = false;
    const layer = {
      panel, scrim,
      close(result) {
        if (closed) return;
        closed = true;
        release(panel);
        scrim.remove();
        openLayers = openLayers.filter((x) => x !== layer);
        if (build.onClose) build.onClose(result);
      },
    };
    openLayers.push(layer);
    build.render(panel, layer.close);
    scrim.addEventListener('mousedown', (e) => {
      if (e.target === scrim) layer.close(null);
    });
    trap(panel, () => layer.close(null));
    return layer;
  }

  function confirm(opts) {
    return new Promise((resolve) => {
      let done = false;
      openLayer({
        kind: 'modal', cls: 'confirm',
        onClose: () => { if (!done) { done = true; resolve(false); } },
        render(panel, close) {
          const head = U.el('div', { class: 'modal-head' });
          head.appendChild(U.el('h2', { text: opts.title }));
          panel.appendChild(head);
          const body = U.el('div', { class: 'modal-body' });
          body.appendChild(U.el('p', { class: 'msg', text: opts.message }));
          panel.appendChild(body);
          const foot = U.el('div', { class: 'modal-foot' });
          const cancel = U.el('button', { class: 'btn ghost', text: opts.cancelText || t('cancel') });
          cancel.addEventListener('click', () => close(null));
          foot.appendChild(cancel);
          const ok = U.el('button', { class: 'btn ' + (opts.danger ? 'danger' : 'primary'), text: opts.confirmText || t('confirm') });
          ok.dataset.autofocus = '';
          ok.addEventListener('click', () => { done = true; resolve(true); close(true); });
          foot.appendChild(ok);
          panel.appendChild(foot);
        },
      });
    });
  }

  function modal(opts) {
    return openLayer({
      kind: 'modal',
      onClose: opts.onClose,
      render(panel, close) {
        const head = U.el('div', { class: 'modal-head' });
        head.appendChild(U.el('h2', { text: opts.title }));
        const x = U.el('button', { class: 'icon-btn sm', 'aria-label': t('close'), html: ICON('x', 15) });
        x.addEventListener('click', () => close(null));
        head.appendChild(x);
        panel.appendChild(head);
        const body = U.el('div', { class: 'modal-body' });
        panel.appendChild(body);
        opts.body(body, close);
        if (opts.footer) {
          const foot = U.el('div', { class: 'modal-foot' });
          panel.appendChild(foot);
          opts.footer(foot, close);
        }
      },
    });
  }

  function sheet(opts) {
    return openLayer({
      kind: 'sheet',
      onClose: opts.onClose,
      render(panel, close) {
        if (opts.title) panel.appendChild(U.el('h2', { text: opts.title }));
        if (opts.subtitle) panel.appendChild(U.el('div', { class: 'sheet-sub', text: opts.subtitle }));
        const body = U.el('div');
        panel.appendChild(body);
        opts.body(body, close);
      },
    });
  }

  // ---------- menu ----------
  let menuNode = null;
  function menu(anchor, items, opts) {
    closeMenu();
    const node = U.el('div', { class: 'menu', role: 'menu' });
    items.forEach((it) => {
      if (it.sep) { node.appendChild(U.el('div', { class: 'sep' })); return; }
      if (it.label && !it.text) { node.appendChild(U.el('div', { class: 'label', text: it.label })); return; }
      const b = U.el('button', { class: it.danger ? 'danger' : '', role: 'menuitem' });
      if (it.icon) b.innerHTML = ICON(it.icon, 15);
      b.appendChild(U.el('span', { text: it.text }));
      if (it.disabled) { b.disabled = true; b.style.opacity = '.45'; }
      b.addEventListener('click', () => { closeMenu(); if (!it.disabled) it.action(); });
      node.appendChild(b);
    });
    document.body.appendChild(node);
    const r = anchor.getBoundingClientRect();
    const mw = node.offsetWidth, mh = node.offsetHeight;
    let left = (opts && opts.align === 'left') ? r.left : r.right - mw;
    let top = r.bottom + 4;
    if (top + mh > window.innerHeight - 8) top = Math.max(8, r.top - mh - 4);
    left = U.clamp(left, 8, window.innerWidth - mw - 8);
    node.style.left = left + 'px';
    node.style.top = top + 'px';
    menuNode = node;
    setTimeout(() => {
      const onDoc = (e) => {
        if (menuNode && !menuNode.contains(e.target)) { closeMenu(); document.removeEventListener('mousedown', onDoc, true); }
      };
      document.addEventListener('mousedown', onDoc, true);
    }, 0);
    const first = node.querySelector('button:not([disabled])');
    if (first) first.focus();
    return node;
  }
  function closeMenu() {
    if (menuNode) { menuNode.remove(); menuNode = null; }
  }

  // ---------- rows ----------
  function checkbox(done, onToggle, label) {
    const b = U.el('button', {
      class: 'hit', role: 'checkbox', 'aria-checked': done ? 'true' : 'false',
      'aria-label': label || (done ? t('markIncomplete') : t('markComplete')),
    });
    b.innerHTML = `<span class="checkbox${done ? ' on' : ''}">${ICON('check', 13)}</span>`;
    b.addEventListener('click', (e) => { e.stopPropagation(); onToggle(); });
    return b;
  }

  function priorityDot(priority) {
    if (!priority) return '';
    const map = { 9: ['var(--red)', t('high')], 5: ['var(--amber)', t('medium')], 1: ['var(--ink-3)', t('low')] };
    const p = map[priority] || map[5];
    return `<span class="chip outline" title="${U.esc(p[1])}" style="padding:0 5px;height:16px;gap:3px"><span class="dot" style="background:${p[0]}"></span>${U.esc(p[1])}</span>`;
  }

  function tagChips(tagIds, max) {
    if (!tagIds || !tagIds.length) return '';
    const shown = max ? tagIds.slice(0, max) : tagIds;
    const rest = tagIds.length - shown.length;
    return shown.map((id) => {
      const tag = S.tagById(id);
      if (!tag) return '';
      return `<span class="chip outline" style="padding:0 5px;height:16px"><span class="dot" style="background:${tag.color}"></span>${U.esc(tag.name)}</span>`;
    }).join('') + (rest > 0 ? `<span class="chip outline" style="height:16px">+${rest}</span>` : '');
  }

  function deadlineMeta(todo, now, dueOverride) {
    const due = dueOverride || todo.dueDate;
    if (!due) return '';
    // 逾期 means the deadline's day has passed. A date-only deadline is due at
    // the start of its day, so comparing instants would call today overdue.
    // A repeating row overrides the date with the occurrence it stands for.
    const overdue = S.isOpen(todo) && U.startOfDay(due) < U.startOfDay(now || U.now());
    // Say 截止. On a row that already shows a time block, a bare time reads as a
    // second schedule; the word is what distinguishes a deadline from an
    // execution slot.
    const label = U.fmtDeadline(due);
    return `<span class="row-deadline${overdue ? ' over' : ''}">${ICON('flag', 11)}<span>${overdue ? t('overdue') + ' · ' : ''}${U.esc(t('deadlinePrefix', { d: label }))}</span></span>`;
  }

  function allocMeta(todo, occurrenceId) {
    let allocs = S.allocationsForTodo(todo.id).filter(S.isAllocationLive);
    if (occurrenceId !== undefined) allocs = allocs.filter((a) => a.occurrenceId === occurrenceId);
    if (!allocs.length) return '';
    const a = allocs[0];
    return `<span class="row-alloc">${ICON('clock', 11)}<span>${U.esc(U.fmtTimeRange(a.startAt, a.endAt))}</span></span>`;
  }

  function repeatMeta(todo) {
    if (!todo.recurrence) return '';
    return `<span class="chip outline" style="height:16px;padding:0 5px">${ICON('repeat', 10)}${U.esc(ruleSummary(todo.recurrence))}</span>`;
  }

  function ruleSummary(rec) {
    if (!rec) return t('never');
    const unit = { DAILY: t('dayUnit'), WEEKLY: t('weekUnit'), MONTHLY: t('monthUnit'), YEARLY: t('yearUnit') }[rec.freq] || '';
    if (rec.freq === 'WEEKLY' && rec.byday && rec.byday.length === 5 && [1, 2, 3, 4, 5].every((d) => rec.byday.includes(d))) {
      return t('repeatWeekdays');
    }
    if (rec.interval === 1) return t('every') + unit;
    return t('every') + ' ' + rec.interval + ' ' + unit;
  }

  function busyBar(day, container) {
    // rhythm bar for Action: 06:00 - 24:00
    const from = 6, to = 24;
    const track = U.el('div', { class: 'rhythm-track' });
    const now = U.now();
    const proj = S.actionProjection(day);
    const items = [];
    proj.events.forEach((e) => items.push({ s: e.startDt, e: e.endDt, kind: 'evt', c: S.calendarColor(e.calendarId) }));
    proj.allocations.forEach((x) => items.push({ s: x.allocation.startAt, e: x.allocation.endAt, kind: 'alloc' }));
    items.forEach((it) => {
      const base = U.startOfDay(day);
      const s = Math.max(from, (it.s - base) / U.MS_HOUR);
      const e = Math.min(to, (it.e - base) / U.MS_HOUR);
      if (e <= s) return;
      const b = U.el('div', { class: 'rhythm-block' + (it.kind === 'alloc' ? ' alloc' : '') });
      if (it.c) b.style.setProperty('--c', it.c);
      b.style.left = ((s - from) / (to - from)) * 100 + '%';
      b.style.width = ((e - s) / (to - from)) * 100 + '%';
      track.appendChild(b);
    });
    if (U.sameDay(day, now)) {
      const h = now.getHours() + now.getMinutes() / 60;
      if (h >= from && h <= to) {
        const n = U.el('div', { class: 'rhythm-now' });
        n.style.left = ((h - from) / (to - from)) * 100 + '%';
        track.appendChild(n);
      }
    }
    const wrap = U.el('div', { class: 'rhythm' });
    wrap.appendChild(track);
    const times = U.el('div', { class: 'rhythm-times' });
    times.innerHTML = `<span>06:00</span><span>15:00</span><span>24:00</span>`;
    wrap.appendChild(times);
    container.appendChild(wrap);
    return wrap;
  }

  function skeletonRows(n) {
    const wrap = U.el('div');
    for (let i = 0; i < (n || 4); i++) {
      wrap.innerHTML += `<div class="sk-row"><div class="skeleton l1" style="max-width:${180 + i * 22}px"></div><div class="skeleton l2"></div></div>`;
    }
    return wrap;
  }

  function emptyState(icon, title, hint, actions) {
    const wrap = U.el('div', { class: 'empty' });
    wrap.innerHTML = ICON(icon, 34) + `<div class="empty-title">${U.esc(title)}</div>` + (hint ? `<div class="empty-hint">${U.esc(hint)}</div>` : '');
    if (actions && actions.length) {
      const box = U.el('div', { class: 'empty-actions' });
      actions.forEach((a) => {
        const b = U.el('button', { class: 'btn ' + (a.primary ? 'primary' : 'ghost'), text: a.label });
        b.addEventListener('click', a.action);
        box.appendChild(b);
      });
      wrap.appendChild(box);
    }
    return wrap;
  }

  function sectionHead(title, count, opts) {
    const o = opts || {};
    const node = U.el('div', { class: 'section-head' + (o.tone ? ' ' + o.tone : '') });
    node.appendChild(U.el('span', { text: title }));
    if (count !== undefined && count !== null) node.appendChild(U.el('span', { class: 'count', text: String(count) }));
    if (o.right) {
      const r = U.el('span', { class: 'right' });
      if (o.right.text) {
        const b = U.el('button', { class: 'link-btn' });
        b.innerHTML = `<span>${U.esc(o.right.text)}</span>` + (o.right.icon ? ICON(o.right.icon, 12) : '');
        b.addEventListener('click', o.right.action);
        r.appendChild(b);
      }
      node.appendChild(r);
    }
    return node;
  }

  function announce(text) {
    const live = U.qs('#live');
    live.textContent = '';
    setTimeout(() => { live.textContent = text; }, 20);
  }

  function iconButton(name, label, onClick, opts) {
    const b = U.el('button', {
      class: 'icon-btn' + (opts && opts.sm ? ' sm' : '') + (opts && opts.active ? ' active' : '') + (opts && opts.cls ? ' ' + opts.cls : ''),
      'aria-label': label, title: label,
    });
    b.innerHTML = ICON(name, opts && opts.size ? opts.size : 17);
    if (opts && opts.testid) b.dataset.testid = opts.testid;
    if (onClick) b.addEventListener('click', onClick);
    return b;
  }

  function keyHint(text) { return `<kbd>${U.esc(text)}</kbd>`; }

  // ---------- page frame ----------
  function page(opts) {
    const mobile = U.isNarrow();
    const root = U.el('div', { class: 'page' });
    const head = U.el('div', { class: 'page-head' + (mobile ? ' mobile' : '') });
    if (opts.onBack) {
      const back = iconButton('chevronLeft', t('back'), opts.onBack, { cls: 'back-btn', size: 18 });
      head.appendChild(back);
    }
    const wrap = U.el('div', { class: 'page-title-wrap' });
    if (opts.eyebrow) wrap.appendChild(U.el('div', { class: 'eyebrow', text: opts.eyebrow }));
    const titleRow = U.el('div', { style: 'display:flex;align-items:baseline;gap:10px;min-width:0' });
    titleRow.appendChild(U.el('h1', { class: 'page-title', text: opts.title }));
    wrap.appendChild(titleRow);
    if (opts.subtitle) {
      if (typeof opts.subtitle === 'string') wrap.appendChild(U.el('div', { class: 'page-sub', html: opts.subtitle }));
      else wrap.appendChild(opts.subtitle);
    }
    head.appendChild(wrap);
    if (opts.actions && opts.actions.length) {
      const acts = U.el('div', { class: 'page-actions' });
      opts.actions.forEach((a) => acts.appendChild(a));
      head.appendChild(acts);
    }
    root.appendChild(head);
    if (opts.banner) root.appendChild(opts.banner);
    const scroll = U.el('div', { class: 'page-scroll' });
    const content = U.el('div', { class: 'page-content' + (mobile ? ' tight' : '') + (opts.narrow ? ' narrow' : '') });
    if (opts.build) opts.build(content);
    scroll.appendChild(content);
    if (opts.mdScroll) {
      // The master-detail page owns the viewport: the list and the pane scroll
      // independently, so a scrolled list can never push the pane head above
      // the fold.
      scroll.classList.add('md-scroll');
      content.classList.add('md-content');
    }
    root.appendChild(scroll);
    return root;
  }

  // The calendar field. A native <select> hides the one thing a calendar is:
  // its colour. CORE_UX_SPEC 5 also requires the picker to open even when
  // there is only one calendar, and to offer creating another inline.
  function calendarPicker(currentId, onPick) {
    const cal = window.Store.calendarById(currentId) || window.Store.state.calendars[0];
    const b = U.el('button', { class: 'cal-picker', 'data-testid': 'calendar-picker' });
    b.innerHTML = `<span class="dot" style="background:${cal ? cal.color : 'var(--accent)'}"></span><span class="nm">${U.esc(cal ? cal.name : '')}</span>` + ICON('chevronDown', 12);
    b.addEventListener('click', (ev) => {
      ev.stopPropagation();
      openCalendarSheet(currentId, onPick);
    });
    return b;
  }

  function openCalendarSheet(currentId, onPick) {
    const S = window.Store;
    sheet({
      title: t('ownCalendar'),
      body(host, close) {
        const list = U.el('div', { class: 'cal-list' });
        host.appendChild(list);
        function draw() {
          list.innerHTML = '';
          S.state.calendars.forEach((cal) => {
            const on = cal.id === currentId;
            const item = U.el('button', { class: 'cal-option' + (on ? ' on' : '') });
            item.dataset.testid = 'calendar-option';
            item.dataset.id = String(cal.id);
            item.setAttribute('aria-pressed', on ? 'true' : 'false');
            item.innerHTML = `<span class="dot" style="background:${cal.color}"></span><span class="nm">${U.esc(cal.name)}</span>` + (on ? ICON('check', 14) : '');
            item.addEventListener('click', () => { close(null); onPick(cal.id); });
            list.appendChild(item);
          });
        }
        draw();
        const add = U.el('button', { class: 'btn ghost sm cal-new', 'data-testid': 'calendar-new' });
        add.innerHTML = ICON('plus', 13) + `<span>${U.esc(t('newCalendar'))}</span>`;
        add.addEventListener('click', () => {
          close(null);
          createCalendarFlow((created) => {
            if (!created) return;
            onPick(created.id);
            // Re-open with the new calendar selected, so the user sees where
            // they landed instead of being dropped back on a bare field.
            openCalendarSheet(created.id, onPick);
          });
        });
        host.appendChild(add);
      },
    });
  }

  function createCalendarFlow(done) {
    const S = window.Store;
    let name = '';
    let color = '#2457d6';
    sheet({
      title: t('newCalendar'),
      body(host, close) {
        const input = U.el('input', { class: 'input', placeholder: t('calendarName'), 'aria-label': t('calendarName'), 'data-testid': 'calendar-name' });
        input.addEventListener('input', () => { name = input.value; });
        host.appendChild(input);
        const err = U.el('div', { class: 'field-error' });
        host.appendChild(err);
        host.appendChild(colorSwatches((c) => { color = c; }));
        const save = U.el('button', { class: 'btn primary', 'data-testid': 'calendar-create' });
        save.textContent = t('create');
        save.addEventListener('click', () => {
          if (!name.trim()) {
            err.textContent = t('calendarNameRequired');
            input.classList.add('invalid');
            input.focus();
            return;
          }
          const created = S.createCalendar(name, color);
          close(null);
          if (done) done(created);
        });
        host.appendChild(save);
      },
    });
  }

  function colorSwatches(onPick) {
    const wrap = U.el('div', { class: 'swatches', style: 'margin:10px 0' });
    ['#2457d6', '#0f9d6e', '#d97706', '#9333ea', '#dc2626'].forEach((c) => {
      const s = U.el('button', { class: 'swatch', 'aria-label': c });
      s.style.background = c;
      s.addEventListener('click', () => onPick(c));
      wrap.appendChild(s);
    });
    return wrap;
  }

  window.UI = {
    page,
    toast, hideToast, confirm, modal, sheet, menu, closeMenu, closeTop, closeAll, hasOpenLayer, releaseAll,
    checkbox, priorityDot, tagChips, deadlineMeta, allocMeta, repeatMeta, ruleSummary, busyBar,
    skeletonRows, emptyState, sectionHead, announce, iconButton, keyHint, trap, release,
    calendarPicker, openCalendarSheet, createCalendarFlow, colorSwatches,
  };
})();
