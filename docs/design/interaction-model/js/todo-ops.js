/* To-do completion shared by every surface. A repeating to-do is completed per
   occurrence, so a surface that has no occurrence in hand must say so instead of
   writing nothing and reporting success. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function todayOccurrenceId(todo) {
    const today = U.startOfDay(U.now());
    if (!S.matchesRule(todo, today)) return null;
    return S.occurrenceIdFor(todo, today);
  }

  // Returns true when a write happened.
  function complete(todo, occurrenceId) {
    if (!todo) return false;
    if (todo.recurrence && !occurrenceId) {
      const occ = todayOccurrenceId(todo);
      if (!occ) {
        UI.toast(t('recurrenceNeedsOccurrence'), { warn: true });
        return false;
      }
      occurrenceId = occ;
    }
    const wasDone = todo.recurrence ? S.isOccurrenceDone(todo, occurrenceId) : S.isDone(todo);
    const result = S.completeTodo(todo.id, occurrenceId ? { occurrenceId } : undefined);
    if (!result) {
      UI.toast(t('recurrenceNeedsOccurrence'), { warn: true });
      return false;
    }
    App.render();
    UI.toast(wasDone ? t('uncompletedToast', { t: todo.summary }) : t('completedToast', { t: todo.summary }), {
      undo: () => { S.completeTodo(todo.id, occurrenceId ? { occurrenceId } : undefined); App.render(); },
    });
    return true;
  }

  window.TodoOps = { complete, todayOccurrenceId };
})();
