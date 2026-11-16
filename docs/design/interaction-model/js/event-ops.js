/* Event operations shared by every surface: delete and edit always ask about
   recurrence scope in one place, so the calendar grid, the block menu and the
   detail page can never disagree about what deleting an occurrence means. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function isSeriesOccurrence(e) {
    return !!(e && e.isOccurrence && e.occurrenceAnchor);
  }

  function scopeSheet(opts) {
    const o = opts || {};
    let picked = false;
    UI.sheet({
      title: t('repeatScopeTitle'),
      subtitle: t('repeatScopeBody'),
      onClose: () => { if (!picked && o.onCancel) o.onCancel(); },
      body(host, close) {
        (o.options || []).forEach((opt) => {
          const b = U.el('button', { class: 'slot-sheet-option' });
          b.dataset.testid = 'scope-' + opt.mode;
          b.innerHTML = `<span class="ico">${ICON('repeat', 16)}</span><span><span class="t">${U.esc(opt.label)}</span><br><span class="s">${U.esc(opt.desc)}</span></span>`;
          b.addEventListener('click', () => { picked = true; close(null); o.onPick(opt.mode); });
          host.appendChild(b);
        });
      },
    });
  }

  function deleteEvent(e) {
    const series = isSeriesOccurrence(e);
    const run = (mode) => {
      const base = S.eventById(e.id);
      let undo = null;
      if (mode === 'this' && series) {
        const anchor = e.occurrenceAnchor;
        base.exdates = (base.exdates || []).concat([anchor]);
        S.emit('event:update');
        undo = () => {
          const cur = S.eventById(e.id);
          if (cur) cur.exdates = (cur.exdates || []).filter((x) => x.getTime() !== anchor.getTime());
          S.emit('event:update');
        };
      } else {
        S.softDeleteEvent(e.id);
        undo = () => { S.restoreEvent(e.id); };
      }
      // A deleted record must not stay on screen behind its own toast.
      if (S.state.route.name === 'detail') App.back();
      App.render();
      UI.toast(t('deletedToast', { t: e.summary }), { undo: () => { undo(); App.render(); } });
    };

    if (!series) {
      UI.confirm({ title: t('delete'), message: t('eventDeleteBody'), danger: true, confirmText: t('moveToTrash') })
        .then((ok) => { if (ok) run('all'); });
      return;
    }
    UI.confirm({
      title: t('delete'),
      message: t('deleteOccurrenceBody'),
      danger: true,
      confirmText: t('moveToTrash'),
    }).then((ok) => {
      if (!ok) return;
      scopeSheet({
        options: [
          { mode: 'this', label: t('scopeThis'), desc: t('deleteScopeThisDesc') },
          { mode: 'future', label: t('scopeFuture'), desc: t('deleteScopeFutureDesc') },
          { mode: 'all', label: t('scopeAll'), desc: t('deleteScopeAllDesc') },
        ],
        onPick: (mode) => {
          if (mode === 'this') { run('this'); return; }
          if (mode === 'future') {
            const base = S.eventById(e.id);
            const prevUntil = base.rrule ? base.rrule.until : null;
            base.rrule = Object.assign({}, base.rrule, { until: U.addDays(U.startOfDay(e.occurrenceAnchor), -1) });
            S.emit('event:update');
            if (S.state.route.name === 'detail') App.back();
            App.render();
            UI.toast(t('deletedToast', { t: e.summary }), {
              undo: () => {
                const cur = S.eventById(e.id);
                if (cur) cur.rrule = Object.assign({}, cur.rrule, { until: prevUntil });
                S.emit('event:update');
                App.render();
              },
            });
            return;
          }
          run('all');
        },
      });
    });
  }

  function editEvent(e) {
    if (!isSeriesOccurrence(e)) {
      App.openComposer('event', { mode: 'edit', id: e.id });
      return;
    }
    scopeSheet({
      options: [
        { mode: 'this', label: t('scopeThis'), desc: t('editScopeThisDesc') },
        { mode: 'future', label: t('scopeFuture'), desc: t('editScopeFutureDesc') },
        { mode: 'all', label: t('scopeAll'), desc: t('editScopeAllDesc') },
      ],
      onPick: (mode) => {
        if (mode === 'this') {
          // The composer must open on the occurrence's real start time, not the
          // midnight anchor used for exdate bookkeeping.
          App.openComposer('event', {
            mode: 'edit', id: e.id, occurrence: e.startDt.getTime(),
          });
        } else if (mode === 'future') {
          // Editing "this and following" truncates the old series only when the
          // edit is saved; cancelling the composer must write nothing.
          App.openComposer('event', {
            mode: 'edit', id: e.id, occurrence: e.startDt.getTime(), scope: 'future',
          });
        } else {
          App.openComposer('event', { mode: 'edit', id: e.id });
        }
      },
    });
  }

  window.EventOps = { deleteEvent, editEvent, scopeSheet, isSeriesOccurrence };
})();
