/* States and edge surfaces: loading, error, offline, permission, empty. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  // Demonstrates every non-happy state in one reachable place, so reviewers can
  // judge them without waiting for a real failure.
  function renderStates() {
    const page = UI.page({
      title: S.state.lang === 'zh' ? '状态与边界' : 'States & edge cases',
      onBack: () => App.back(),
      narrow: true,
      build(content) {
        const note = U.el('div', { class: 'hint-box', text: S.state.lang === 'zh'
          ? '这一页是原型内的状态检查台：把难以自然触发的界面状态摆在一起，供评审逐项核对。'
          : 'A state bench inside the prototype: the hard-to-trigger states in one place for review.' });
        content.appendChild(note);

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '加载中' : 'Loading'));
        content.appendChild(UI.skeletonRows(3));

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '空状态' : 'Empty'));
        content.appendChild(UI.emptyState('bolt', t('actionNothingNow'), t('actionNothingNowHint'), [
          { label: t('newTodo'), primary: true, action: () => App.openComposer('todo', {}) },
        ]));

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '错误' : 'Error'));
        const errCard = U.el('div', { class: 'card warn' });
        errCard.innerHTML = `<div class="ct">${U.esc(t('errorTitle'))}</div><div class="cs">${U.esc(t('errorBody'))}</div>`;
        const retry = U.el('button', { class: 'btn ghost sm', text: t('retry'), style: 'margin-top:8px' });
        retry.addEventListener('click', () => UI.toast(S.state.lang === 'zh' ? '已重试' : 'Retried'));
        errCard.appendChild(retry);
        content.appendChild(errCard);

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '离线与同步' : 'Offline & sync'));
        const banner = U.el('div', { class: 'banner' });
        banner.innerHTML = ICON('cloud', 13) + `<span>${U.esc(t('offlineBanner'))}</span><span class="spacer"></span>`;
        const toggle = U.el('button', { text: S.state.offline ? (S.state.lang === 'zh' ? '恢复在线' : 'Go online') : (S.state.lang === 'zh' ? '模拟离线' : 'Simulate offline') });
        toggle.addEventListener('click', () => { S.state.offline = !S.state.offline; App.render(); });
        banner.appendChild(toggle);
        content.appendChild(banner);

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '权限' : 'Permission'));
        const perm = U.el('div', { class: 'card' });
        perm.innerHTML = `<div class="ct">${U.esc(t('notificationPermission'))}</div><div class="cs">${U.esc(t('permissionDenied'))}</div>`;
        const req = U.el('button', { class: 'btn ghost sm', text: t('requestPermission'), style: 'margin-top:8px' });
        req.addEventListener('click', () => UI.toast(t('notificationPermissionAsked')));
        perm.appendChild(req);
        content.appendChild(perm);

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '禁用' : 'Disabled'));
        const dis = U.el('div', { class: 'chip-row' });
        const b1 = U.el('button', { class: 'btn primary', text: t('save') });
        b1.disabled = true;
        const b2 = U.el('button', { class: 'btn ghost', text: t('disabledOffline') });
        b2.disabled = true;
        dis.appendChild(b1); dis.appendChild(b2);
        content.appendChild(dis);

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '长内容' : 'Long content'));
        const long = '这是一条非常长的标题，用来检查截断与换行是否按设计工作：' +
          (S.state.lang === 'zh' ? '把季度预算、客户排期、设计走查和发布说明全部塞进一行，看它是否会撑破布局。' : '');
        const row = U.el('div', { class: 'row' });
        row.innerHTML = `<span class="row-time">09:30</span><span class="row-leading">${ICON('flag', 14)}</span><span class="row-main"><span class="row-title">${U.esc(long)}</span><span class="row-meta">${U.esc(t('deadline'))} · ${U.esc(t('overdue'))}</span></span><span class="row-tail">${ICON('chevronForward', 13)}</span>`;
        content.appendChild(row);

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '写入失败与重试' : 'Failed writes & retry'));
        const failRow = U.el('div', { class: 'chip-row' });
        [
          ['save-fail', S.state.lang === 'zh' ? '下一次保存失败' : 'Fail next save', () => { S.state.simulateSaveFailure = true; UI.toast(S.state.lang === 'zh' ? '已布置：打开任一编辑器保存一次' : 'Armed: save once in any editor'); }],
          ['detail-fail', S.state.lang === 'zh' ? '下一次详情写入失败' : 'Fail next inline edit', () => { S.state.simulateDetailFailure = true; UI.toast(S.state.lang === 'zh' ? '已布置：在待办详情里改一次' : 'Armed: change one field in a to-do detail'); }],
          ['slot-fail', S.state.lang === 'zh' ? '可安排列表加载失败' : 'Fail schedulable list', () => { S.state.simulateSlotFailure = true; UI.toast(S.state.lang === 'zh' ? '已布置：在日历空白时段点「安排待办」' : 'Armed: choose Schedule to-do from a calendar slot'); }],
          ['account-fail', S.state.lang === 'zh' ? '账户加载失败' : 'Fail account load', () => {
            S.state.account = { signedIn: true, email: 'you@example.com', server: 'https://nas.local:8080', lastSync: U.now(), phase: 'idle', rejected: [], loadError: true };
            App.go('settings', { section: 'account' });
          }],
        ].forEach(([id, label, action]) => {
          const b = U.el('button', { class: 'chip-btn', text: label, 'data-testid': 'arm-' + id });
          b.addEventListener('click', action);
          failRow.appendChild(b);
        });
        content.appendChild(failRow);
        content.appendChild(U.el('div', { class: 'field-hint', text: S.state.lang === 'zh' ? '重试按钮就在失败发生的位置；没有假装保存成功。' : 'The retry sits where the failure happened; nothing pretends the write landed.' }));

        content.appendChild(UI.sectionHead(t('notifySim')));
        const due = S.pendingTodos().find((x) => x.dueDate);
        const note2 = U.el('div', { class: 'card' });
        note2.innerHTML = `<div class="ct">${ICON('bell', 13)} ${U.esc(due ? due.summary : t('nothingHere'))}</div><div class="cs">${U.esc(S.state.lang === 'zh' ? '通知栏上的两个操作，行为与 App 内一致。' : 'The two notification actions behave exactly as they do in-app.')}</div>`;
        const acts = U.el('div', { class: 'chip-row', style: 'margin-top:8px' });
        const mark = U.el('button', { class: 'chip-btn on', text: t('notifyMarkDone'), 'data-testid': 'notify-complete' });
        mark.addEventListener('click', () => {
          if (!due) { UI.toast(t('nothingHere'), { warn: true }); return; }
          window.TodoOps.complete(due);
          UI.toast(t('completedToast', { t: due.summary }));
        });
        const snooze = U.el('button', { class: 'chip-btn', text: t('notifySnooze'), 'data-testid': 'notify-snooze' });
        snooze.addEventListener('click', () => UI.toast(t('notifySnooze')));
        acts.appendChild(mark); acts.appendChild(snooze);
        note2.appendChild(acts);
        content.appendChild(note2);

        content.appendChild(UI.sectionHead(S.state.lang === 'zh' ? '提示条' : 'Toasts'));
        const btns = U.el('div', { class: 'chip-row' });
        const b3 = U.el('button', { class: 'chip-btn', text: S.state.lang === 'zh' ? '带撤销' : 'With undo' });
        b3.addEventListener('click', () => UI.toast(t('deletedToast', { t: 'Q4 预算表' }), { undo: () => UI.toast(S.state.lang === 'zh' ? '已撤销' : 'Undone') }));
        const b4 = U.el('button', { class: 'chip-btn', text: S.state.lang === 'zh' ? '警告' : 'Warning' });
        b4.addEventListener('click', () => UI.toast(t('offlineBanner'), { warn: true }));
        btns.appendChild(b3); btns.appendChild(b4);
        content.appendChild(btns);
      },
    });
    return page;
  }

  App.defineView('states', renderStates);
  window.__states = renderStates;
})();
