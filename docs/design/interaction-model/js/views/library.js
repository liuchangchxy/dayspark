/* Library surfaces: Tags, Calendars, Trash, About, Feedback. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  // ---------- tags ----------
  function renderTags() {
    const page = UI.page({
      title: t('pageTags'),
      onBack: () => App.back(),
      narrow: true,
      actions: [(() => {
        const b = U.el('button', { class: 'btn primary', 'data-testid': 'tags-create' });
        b.innerHTML = ICON('plus', 14) + `<span>${U.esc(t('newTag'))}</span>`;
        b.addEventListener('click', () => editTag(null));
        return b;
      })()],
      build(content) {
        if (!S.state.tags.length) {
          content.appendChild(UI.emptyState('tag', t('noTags'), t('tagEmptyHint'), [
            { label: t('newTag'), primary: true, action: () => editTag(null) },
          ]));
          return;
        }
        const list = U.el('div');
        S.state.tags.forEach((tag) => {
          const count = S.liveTodos().filter((x) => x.tagIds.includes(tag.id)).length;
          const row = U.el('div', { class: 'list-row' });
          row.dataset.testid = 'tag-row';
          row.innerHTML = `<span class="dot" style="background:${tag.color}"></span><span class="main"><span class="t">${U.esc(tag.name)}</span><span class="s">${count} ${U.esc(t('todosLabel'))}</span></span>`;
          const edit = UI.iconButton('edit', t('edit'), () => editTag(tag), { sm: true, size: 14 });
          const del = UI.iconButton('trash', t('deleteTag'), () => deleteTagFlow(tag), { sm: true, size: 14 });
          row.appendChild(edit); row.appendChild(del);
          list.appendChild(row);
        });
        content.appendChild(list);
      },
    });
    return page;
  }

  function editTag(tag) {
    UI.modal({
      title: tag ? t('edit') : t('newTag'),
      body(host, close) {
        const field = U.el('div', { class: 'field' });
        field.innerHTML = `<label>${U.esc(t('tagName'))}</label>`;
        const input = U.el('input', { class: 'input', value: tag ? tag.name : '', 'data-autofocus': '', maxlength: '50' });
        field.appendChild(input);
        const err = U.el('div', { class: 'field-error' });
        field.appendChild(err);
        host.appendChild(field);
        const colors = ['#2457d6', '#2f7d5a', '#c2410c', '#6d4aa0', '#b4375a', '#b98a00', '#4d5461'];
        let chosen = tag ? tag.color : colors[0];
        const sw = U.el('div', { class: 'swatches', style: 'margin-top:4px' });
        colors.forEach((c) => {
          const b = U.el('button', { class: 'swatch' + (c === chosen ? ' on' : ''), 'aria-label': c });
          b.style.background = c;
          b.addEventListener('click', () => {
            chosen = c;
            sw.querySelectorAll('.swatch').forEach((x) => x.classList.remove('on'));
            b.classList.add('on');
          });
          sw.appendChild(b);
        });
        host.appendChild(U.el('div', { class: 'field-label', text: S.state.lang === 'zh' ? '颜色' : 'Color' }));
        host.appendChild(sw);
        const foot = U.el('div', { class: 'input-row', style: 'justify-content:flex-end;margin-top:10px' });
        const cancel = U.el('button', { class: 'btn ghost', text: t('cancel') });
        cancel.addEventListener('click', () => close(null));
        const save = U.el('button', { class: 'btn primary', text: tag ? t('save') : t('create'), 'data-testid': 'tag-save' });
        save.addEventListener('click', () => {
          const name = input.value.trim();
          if (!name) { err.textContent = t('tagRequired'); input.classList.add('invalid'); return; }
          if (S.state.tags.some((x) => x.name === name && (!tag || x.id !== tag.id))) { err.textContent = t('tagDuplicate'); return; }
          if (tag) S.updateTag(tag.id, { name, color: chosen });
          else S.createTag(name, chosen);
          close(null); App.render();
          UI.toast(tag ? t('updatedToast', { t: name }) : t('createdToast', { t: name }));
        });
        foot.appendChild(cancel); foot.appendChild(save);
        host.appendChild(foot);
        host.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && e.target === input) { e.preventDefault(); save.click(); }
        });
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') save.click(); });
      },
    });
  }

  function deleteTagFlow(tag) {
    UI.confirm({ title: t('deleteTag'), message: t('deleteTagBody', { t: tag.name }), danger: true, confirmText: t('delete') }).then((ok) => {
      if (!ok) return;
      S.deleteTag(tag.id);
      App.render();
      UI.toast(t('deletedToast', { t: tag.name }));
    });
  }

  // ---------- calendars ----------
  function renderCalendars() {
    const page = UI.page({
      title: t('pageCalendars'),
      onBack: () => App.back(),
      narrow: true,
      actions: [(() => {
        const b = U.el('button', { class: 'btn primary', 'data-testid': 'calendars-create' });
        b.setAttribute('aria-label', t('newCalendar'));
        b.innerHTML = ICON('plus', 14) + `<span class="label">${U.esc(t('newCalendar'))}</span>`;
        b.addEventListener('click', () => editCalendar(null));
        return b;
      })()],
      build(content) {
        if (!S.state.calendars.length) {
          content.appendChild(UI.emptyState('layers', t('noCalendar'), '', [{ label: t('newCalendar'), primary: true, action: () => editCalendar(null) }]));
          return;
        }
        const list = U.el('div');
        S.state.calendars.forEach((cal) => {
          const events = S.liveEvents().filter((x) => x.calendarId === cal.id).length;
          const todos = S.liveTodos().filter((x) => x.calendarId === cal.id).length;
          const row = U.el('div', { class: 'list-row' });
          row.dataset.testid = 'calendar-row';
          row.innerHTML = `<span class="dot" style="background:${cal.color}"></span><span class="main"><span class="t">${U.esc(cal.name)}</span><span class="s">${events} ${U.esc(t('eventsLabel'))} · ${todos} ${U.esc(t('todosLabel'))} · ${U.esc(cal.timezone)}</span></span>`;
          const edit = UI.iconButton('edit', t('edit'), () => editCalendar(cal), { sm: true, size: 14 });
          row.appendChild(edit);
          if (S.state.calendars.length > 1) {
            const del = UI.iconButton('trash', t('deleteCalendar'), () => deleteCalendarFlow(cal), { sm: true, size: 14 });
            row.appendChild(del);
          }
          list.appendChild(row);
        });
        content.appendChild(list);
        content.appendChild(U.el('div', { class: 'field-hint', style: 'margin-top:10px', text: t('cannotDeleteOnlyCalendar') }));
      },
    });
    return page;
  }

  function editCalendar(cal) {
    UI.modal({
      title: cal ? t('editCalendar') : t('newCalendar'),
      body(host, close) {
        const field = U.el('div', { class: 'field' });
        field.innerHTML = `<label>${U.esc(t('calendarName'))}</label>`;
        const input = U.el('input', { class: 'input', value: cal ? cal.name : '', 'data-autofocus': '', 'data-testid': 'calendar-name' });
        field.appendChild(input);
        const err = U.el('div', { class: 'field-error' });
        field.appendChild(err);
        host.appendChild(field);
        const colors = ['#2457d6', '#2f7d5a', '#c2410c', '#6d4aa0', '#b4375a', '#b98a00', '#4d5461'];
        let chosen = cal ? cal.color : colors[0];
        const sw = U.el('div', { class: 'swatches', style: 'margin-top:8px' });
        colors.forEach((c) => {
          const b = U.el('button', { class: 'swatch' + (c === chosen ? ' on' : ''), 'aria-label': c });
          b.style.background = c;
          b.addEventListener('click', () => {
            chosen = c;
            sw.querySelectorAll('.swatch').forEach((x) => x.classList.remove('on'));
            b.classList.add('on');
          });
          sw.appendChild(b);
        });
        host.appendChild(U.el('div', { class: 'field-label', text: S.state.lang === 'zh' ? '颜色' : 'Color' }));
        host.appendChild(sw);
        const foot = U.el('div', { class: 'input-row', style: 'justify-content:flex-end;margin-top:10px' });
        const cancel = U.el('button', { class: 'btn ghost', text: t('cancel') });
        cancel.addEventListener('click', () => close(null));
        const save = U.el('button', { class: 'btn primary', text: cal ? t('save') : t('create'), 'data-testid': 'calendar-create' });
        save.addEventListener('click', () => {
          const name = input.value.trim();
          if (!name) { err.textContent = t('calendarNameRequired'); input.classList.add('invalid'); input.focus(); return; }
          if (cal) S.updateCalendar(cal.id, { name, color: chosen });
          else S.createCalendar(name, chosen);
          close(null); App.render();
        });
        foot.appendChild(cancel); foot.appendChild(save);
        host.appendChild(foot);
        host.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && e.target === input) { e.preventDefault(); save.click(); }
        });
      },
    });
  }

  function deleteCalendarFlow(cal) {
    const events = S.liveEvents().filter((x) => x.calendarId === cal.id).length;
    const todos = S.liveTodos().filter((x) => x.calendarId === cal.id).length;
    if (!events && !todos) {
      UI.confirm({ title: t('deleteCalendar'), message: S.state.lang === 'zh' ? `删除「${cal.name}」？` : `Delete “${cal.name}”?`, danger: true, confirmText: t('delete') }).then((ok) => {
        if (!ok) return;
        S.deleteCalendar(cal.id, { move: false });
        App.render();
      });
      return;
    }
    UI.sheet({
      title: t('deleteCalendar'),
      subtitle: t('calendarHasContents', { e: events, t: todos }),
      body(host, close) {
        const mk = (icon, label, sub, action, danger) => {
          const b = U.el('button', { class: 'slot-sheet-option' });
          b.innerHTML = `<span class="ico" style="${danger ? 'color:var(--red)' : ''}">${ICON(icon, 17)}</span><span><span class="t" style="${danger ? 'color:var(--red)' : ''}">${U.esc(label)}</span><br><span class="s">${U.esc(sub)}</span></span>`;
          b.addEventListener('click', () => { close(null); action(); });
          host.appendChild(b);
        };
        mk('move', t('moveContentsTo'), S.state.lang === 'zh' ? '内容转到第一个其他日历' : 'Move items to the first other calendar', () => {
          S.deleteCalendar(cal.id, { move: true });
          App.render();
          UI.toast(S.state.lang === 'zh' ? '已移动并删除日历' : 'Moved and deleted');
        });
        mk('trash', t('deleteCalendarAndContents'), S.state.lang === 'zh' ? '内容一并删除，无法从回收站恢复' : 'Contents are deleted with it', () => {
          S.deleteCalendar(cal.id, { move: false });
          App.render();
        }, true);
      },
    });
  }

  // ---------- trash ----------
  function renderTrash() {
    const todos = S.deletedTodos();
    const events = S.deletedEvents();
    const total = todos.length + events.length;
    const actions = [];
    if (total) {
      const empty = UI.iconButton('trash', t('emptyTrash'), () => {
        UI.confirm({
          title: t('emptyTrash'), message: t('emptyTrashBody', { n: total }),
          danger: true, confirmText: t('emptyTrash'),
        }).then((ok) => {
          if (!ok) return;
          S.emptyTrash();
          App.render();
          UI.toast(t('emptyTrash'));
        });
      });
      empty.dataset.testid = 'trash-empty';
      actions.push(empty);
    }
    const page = UI.page({
      title: t('pageTrash'),
      onBack: () => App.back(),
      narrow: true,
      actions,
      build(content) {
        if (!total) {
          content.appendChild(UI.emptyState('trash', t('trashEmpty'), t('trashEmptyHint'), [
            { label: t('trashEmptyAction'), primary: true, action: () => { S.state.todosView = { kind: 'all', day: null }; App.go('todos'); } },
          ]));
          return;
        }
        if (todos.length) {
          content.appendChild(UI.sectionHead(t('todosLabel'), todos.length));
          todos.forEach((todo) => content.appendChild(trashRow(todo, 'todo')));
        }
        if (events.length) {
          content.appendChild(UI.sectionHead(t('eventsLabel'), events.length));
          events.forEach((e) => content.appendChild(trashRow(e, 'event')));
        }
      },
    });
    return page;
  }

  function trashRow(item, kind) {
    const row = U.el('div', { class: 'list-row' });
    row.dataset.testid = 'trash-row';
    const icon = kind === 'todo' ? 'checkSquare' : 'calendar';
    row.innerHTML = `<span class="icon" style="color:var(--ink-3)">${ICON(icon, 16)}</span><span class="main"><span class="t" style="text-decoration:line-through;color:var(--ink-2)">${U.esc(item.summary)}</span><span class="s">${U.esc(t('deletedAtLabel', { t: U.fmtMonthDayTime(item.deletedAt) }))}</span></span>`;
    const restore = U.el('button', { class: 'btn ghost sm', text: t('restore') });
    restore.dataset.testid = 'trash-restore';
    restore.addEventListener('click', () => {
      const ok = kind === 'todo' ? S.restoreTodo(item.id) : S.restoreEvent(item.id);
      App.render();
      // restoreTodo refuses an orphaned subtask instead of clearing its flag.
      if (ok) UI.toast(t('restoredToast', { t: item.summary }));
      else UI.toast(t('restoreOrphaned'), { warn: true });
    });
    const purge = UI.iconButton('x', t('deleteForever'), () => {
      UI.confirm({
        title: t('deleteForever'), message: t('deleteForeverBody', { t: item.summary }),
        danger: true, confirmText: t('deleteForever'),
      }).then((ok) => {
        if (!ok) return;
        if (kind === 'todo') S.purgeTodo(item.id); else S.purgeEvent(item.id);
        App.render();
        UI.toast(t('deleteForever'));
      });
    }, { sm: true, size: 14 });
    purge.dataset.testid = 'trash-purge';
    row.appendChild(restore);
    row.appendChild(purge);
    return row;
  }

  function openChangelog() {
    UI.sheet({
      title: t('changelogTitle'),
      subtitle: 'v0.34.0+34',
      body(host) {
        const zh = S.state.lang === 'zh';
        const items = zh
          ? ['桌面双栏：列表常驻，右侧查看详情', '统一创建入口：待办 / 日程 / 一句话快速添加', '待办筛选：日历、标签、优先级', '今天分区：逾期、遗漏、更早、今天完成']
          : ['Desktop split view keeps the list and opens details beside it', 'One create entry: to-do, event, or one-line quick add', 'To-do filters: calendar, tag and priority', 'Today separates overdue, missed, earlier and completed'];
        const list = U.el('ul', { class: 'changelog-list' });
        items.forEach((x) => list.appendChild(U.el('li', { text: x })));
        host.appendChild(list);
      },
    });
  }

  // ---------- about ----------
  function renderAbout() {
    const page = UI.page({
      title: t('pageAbout'),
      onBack: () => App.back(),
      narrow: true,
      build(content) {
        const card = U.el('div', { class: 'pagecard' });
        card.innerHTML = `<h2>${U.esc(t('appName'))}</h2><p>${U.esc(S.state.lang === 'zh' ? '自托管的开源日历与待办。数据留在你自己的设备与 NAS 上。' : 'A self-hosted open-source calendar and to-do app. Your data stays on your devices and your NAS.')}</p>`;
        content.appendChild(card);
        const version = U.el('div', { class: 'settings-group', style: 'margin-top:14px' });
        const row = U.el('div', { class: 'setting-row' });
        row.innerHTML = `<span class="body"><span class="t">${U.esc(t('version'))}</span><span class="s">0.34.0+34</span></span>`;
        const check = U.el('button', { class: 'btn ghost sm', text: t('checkUpdate') });
        check.addEventListener('click', () => {
          check.disabled = true;
          check.textContent = t('loading');
          setTimeout(() => {
            check.disabled = false;
            check.textContent = t('checkUpdate');
            UI.toast(t('upToDate'));
          }, 900);
        });
        row.appendChild(check);
        version.appendChild(row);
        content.appendChild(version);
        const links = U.el('div', { class: 'settings-group' });
        [
          { icon: 'note', label: t('changelog'), action: () => openChangelog() },
          { icon: 'star', label: S.state.lang === 'zh' ? '在 GitHub 上加星' : 'Star on GitHub', action: () => UI.toast('github.com/liuchangchxy/dayspark') },
          { icon: 'external', label: S.state.lang === 'zh' ? '报告问题' : 'Report an issue', action: () => UI.toast('github.com/liuchangchxy/dayspark/issues') },
          { icon: 'key', label: t('openSource'), action: () => UI.toast(S.state.lang === 'zh' ? '开源许可（原型未包含全文）' : 'Licenses (not in prototype)') },
        ].forEach((l) => {
          const r = U.el('button', { class: 'setting-row' });
          r.innerHTML = `<span class="icon">${ICON(l.icon, 16)}</span><span class="body"><span class="t">${U.esc(l.label)}</span></span><span class="value">${ICON('chevronRight', 13)}</span>`;
          r.addEventListener('click', l.action);
          links.appendChild(r);
        });
        content.appendChild(links);
      },
    });
    return page;
  }

  // ---------- feedback ----------
  // A clipboard write can be refused. Saying "copied" without looking is a
  // false claim the user only discovers when the paste is empty.
  function copyText(text, note) {
    const done = () => UI.toast((S.state.lang === 'zh' ? '已复制' : 'Copied') + (note ? '。' + note : ''));
    const fail = () => UI.toast(S.state.lang === 'zh' ? '复制失败，请手动选中文本' : 'Copy failed — select the text and copy manually', { warn: true });
    if (!navigator.clipboard || !navigator.clipboard.writeText) { fail(); return; }
    navigator.clipboard.writeText(text).then(done, fail);
  }

  function renderFeedback() {
    const page = UI.page({
      title: t('pageFeedback'),
      onBack: () => App.back(),
      narrow: true,
      build(content) {
        // Feedback leaves the app as text: copy it, or open the GitHub issue
        // page with it. There is no in-app ticketing backend to pretend about.
        const ta = U.el('textarea', { class: 'textarea', rows: '7', placeholder: t('feedbackPlaceholder'), 'aria-label': t('feedbackPlaceholder') });
        ta.dataset.testid = 'feedback-text';
        content.appendChild(ta);
        const row = U.el('div', { class: 'input-row', style: 'margin-top:12px' });
        const copy = U.el('button', { class: 'btn ghost lg', text: S.state.lang === 'zh' ? '复制' : 'Copy', 'data-testid': 'feedback-copy' });
        copy.addEventListener('click', () => {
          if (!ta.value.trim()) { ta.classList.add('invalid'); ta.focus(); return; }
          copyText(ta.value);
        });
        const send = U.el('button', { class: 'btn primary lg', text: S.state.lang === 'zh' ? '在 GitHub 提交' : 'Submit on GitHub', 'data-testid': 'feedback-submit' });
        send.addEventListener('click', () => {
          if (!ta.value.trim()) { ta.classList.add('invalid'); ta.focus(); return; }
          copyText(ta.value, S.state.lang === 'zh' ? '网页版会打开 GitHub 新建 issue。' : 'The web build opens a new GitHub issue.');
        });
        row.appendChild(copy); row.appendChild(send);
        content.appendChild(row);
      },
    });
    return page;
  }

  App.defineView('tags', renderTags);
  App.defineView('calendars', renderCalendars);
  App.defineView('trash', renderTrash);
  App.defineView('about', renderAbout);
  App.defineView('feedback', renderFeedback);
})();
