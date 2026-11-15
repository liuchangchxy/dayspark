/* Search across todos and events. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  function renderSearch() {
    let scope = 'all';
    let query = S.state.searchQuery || '';

    const page = UI.page({
      title: t('pageSearch'),
      onBack: () => App.back(),
      build(content) {
        const box = U.el('div', { class: 'search-box' });
        box.innerHTML = ICON('search', 16);
        const input = U.el('input', {
          placeholder: t('searchPlaceholder'), value: query,
          'aria-label': t('searchPlaceholder'), 'data-testid': 'search-input',
        });
        box.appendChild(input);
        const clearBtn = U.el('button', { class: 'icon-btn sm', 'aria-label': t('searchClear'), html: ICON('x', 14) });
        clearBtn.hidden = !query;
        clearBtn.addEventListener('click', () => { input.value = ''; query = ''; clearBtn.hidden = true; draw(); input.focus(); });
        box.appendChild(clearBtn);
        content.appendChild(box);

        const seg = U.el('div', { class: 'segmented', style: 'margin-top:10px' });
        [['all', t('searchAll')], ['todos', t('searchTodos')], ['events', t('searchEvents')]].forEach(([k, label]) => {
          const b = U.el('button', { class: k === scope ? 'on' : '', text: label });
          b.dataset.testid = 'search-scope-' + k;
          b.addEventListener('click', () => {
            scope = k;
            seg.querySelectorAll('button').forEach((x) => x.classList.remove('on'));
            b.classList.add('on');
            draw();
          });
          seg.appendChild(b);
        });
        content.appendChild(seg);

        const results = U.el('div', { class: 'search-results', 'data-testid': 'search-results' });
        content.appendChild(results);

        function draw() {
          results.innerHTML = '';
          if (!query.trim()) {
            results.appendChild(UI.emptyState('search', t('searchEmpty'), t('searchPlaceholder')));
            return;
          }
          const r = S.searchAll(query);
          const todos = scope === 'events' ? [] : r.todos;
          const events = scope === 'todos' ? [] : r.events;
          if (!todos.length && !events.length) {
            results.appendChild(UI.emptyState('search', t('searchNoResults', { q: query }), S.state.lang === 'zh' ? '换个关键词，或检查拼写。' : 'Try another keyword.'));
            return;
          }
          if (todos.length) {
            results.appendChild(UI.sectionHead(t('searchTodos'), todos.length));
            todos.forEach((todo) => {
              const b = U.el('button', { class: 'search-hit' });
              b.dataset.testid = 'search-hit-todo';
              b.innerHTML = `<span class="t">${U.hl(todo.summary, query)}</span><span class="m">${U.esc(todo.dueDate ? t('deadlinePrefix', { d: U.fmtDeadline(todo.dueDate) }) : t('inbox'))}${todo.description ? ' · ' + U.hl(todo.description.slice(0, 60), query) : ''}</span>`;
              b.addEventListener('click', () => S.navigate('detail', { type: 'todo', id: todo.id }));
              results.appendChild(b);
            });
          }
          if (events.length) {
            results.appendChild(UI.sectionHead(t('searchEvents'), events.length));
            events.forEach((e) => {
              const b = U.el('button', { class: 'search-hit' });
              b.dataset.testid = 'search-hit-event';
              b.innerHTML = `<span class="t">${U.hl(e.summary, query)}</span><span class="m">${U.esc(U.fmtMonthDayTime(e.startDt))}${e.location ? ' · ' + U.hl(e.location, query) : ''}</span>`;
              b.addEventListener('click', () => S.navigate('detail', { type: 'event', id: e.id }));
              results.appendChild(b);
            });
          }
        }
        input.addEventListener('input', U.debounce(() => { query = input.value; S.state.searchQuery = query; clearBtn.hidden = !query; draw(); }, 120));
        draw();
        setTimeout(() => input.focus(), 30);
      },
    });
    return page;
  }

  App.defineView('search', renderSearch);
})();
