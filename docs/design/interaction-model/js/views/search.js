/* Search across todos and events. */
(function () {
  const U = window.U;
  const S = window.Store;
  const UI = window.UI;
  const t = (k, v) => I18N.t(k, v);

  const PAGE = 8;

  function renderSearch() {
    let query = S.state.searchQuery || '';
    let todos = [];
    let events = [];
    let shownTodos = PAGE;
    let shownEvents = PAGE;
    let active = -1;
    let hits = [];

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
        const clearBtn = U.el('button', { class: 'icon-btn sm', 'aria-label': t('searchClear'), html: ICON('x', 14), 'data-testid': 'search-clear' });
        clearBtn.hidden = !query;
        clearBtn.addEventListener('click', () => {
          input.value = ''; query = ''; clearBtn.hidden = true; draw(); input.focus();
        });
        box.appendChild(clearBtn);
        box.addEventListener('click', (e) => { if (!e.target.closest('button')) input.focus(); });
        content.appendChild(box);

        const hint = U.el('div', { class: 'field-hint', style: 'margin-top:6px', text: t('searchKeyboardHint') });
        content.appendChild(hint);

        const results = U.el('div', { class: 'search-results', 'data-testid': 'search-results' });
        content.appendChild(results);

        function hitNode(html, testid, open) {
          const b = U.el('button', { class: 'search-hit' });
          b.dataset.testid = testid;
          b.innerHTML = html;
          b.addEventListener('click', open);
          return b;
        }

        function suggestions() {
          const box = U.el('div');
          const items = S.inboxTodos().filter((x) => !x.dueDate).slice(0, 5);
          box.appendChild(UI.sectionHead(t('searchSuggestions'), items.length));
          if (!items.length) {
            box.appendChild(UI.emptyState('search', t('searchEmpty'), t('searchPlaceholder')));
            return box;
          }
          items.forEach((todo) => {
            const b = U.el('button', { class: 'search-hit', 'data-testid': 'search-suggestion' });
            b.innerHTML = `<span class="t">${U.esc(todo.summary)}</span><span class="m">${U.esc(t('inbox'))}</span>`;
            b.addEventListener('click', () => {
              input.value = todo.summary;
              query = todo.summary;
              S.state.searchQuery = query;
              clearBtn.hidden = false;
              draw();
            });
            box.appendChild(b);
          });
          return box;
        }

        function draw() {
          results.innerHTML = '';
          hits = [];
          active = -1;
          results.appendChild(U.el('div', { class: 'field-hint', text: t('searchKeyboardHint') }));
          if (!query.trim()) {
            results.appendChild(suggestions());
            return;
          }
          const r = S.searchAll(query);
          todos = r.todos;
          events = r.events;
          if (!todos.length && !events.length) {
            results.appendChild(UI.emptyState('search', t('searchNoResults', { q: query }), S.state.lang === 'zh' ? '换个关键词，或检查拼写。' : 'Try another keyword.'));
            return;
          }
          results.appendChild(U.el('div', { class: 'field-hint', text: t('searchResultsCount', { n: todos.length + events.length }) }));
          if (todos.length) {
            results.appendChild(UI.sectionHead(t('searchTodos'), todos.length));
            todos.slice(0, shownTodos).forEach((todo) => {
              const b = hitNode(
                `<span class="t">${U.hl(todo.summary, query)}</span><span class="m">${U.esc(todo.dueDate ? t('deadlinePrefix', { d: U.fmtDeadline(todo.dueDate) }) : t('inbox'))}${todo.description ? ' · ' + U.hl(todo.description.slice(0, 60), query) : ''}</span>`,
                'search-hit-todo',
                () => S.navigate('detail', { type: 'todo', id: todo.id }),
              );
              hits.push(b);
              results.appendChild(b);
            });
            if (todos.length > shownTodos) {
              const more = U.el('button', { class: 'btn ghost sm', text: t('searchLoadMore'), 'data-testid': 'search-more' });
              more.addEventListener('click', () => { shownTodos += PAGE; draw(); });
              results.appendChild(more);
            }
          }
          if (events.length) {
            results.appendChild(UI.sectionHead(t('searchEvents'), events.length));
            events.slice(0, shownEvents).forEach((e) => {
              const b = hitNode(
                `<span class="t">${U.hl(e.summary, query)}</span><span class="m">${U.esc(U.fmtMonthDayTime(e.startDt))}${e.location ? ' · ' + U.hl(e.location, query) : ''}</span>`,
                'search-hit-event',
                () => S.navigate('detail', { type: 'event', id: e.id }),
              );
              hits.push(b);
              results.appendChild(b);
            });
            if (events.length > shownEvents) {
              const more = U.el('button', { class: 'btn ghost sm', text: t('searchLoadMore'), 'data-testid': 'search-more-event' });
              more.addEventListener('click', () => { shownEvents += PAGE; draw(); });
              results.appendChild(more);
            }
          }
        }

        function focusHit(next) {
          if (!hits.length) return;
          hits.forEach((h) => h.classList.remove('active'));
          active = Math.max(0, Math.min(hits.length - 1, next));
          hits[active].classList.add('active');
          hits[active].scrollIntoView({ block: 'nearest' });
        }

        input.addEventListener('input', U.debounce(() => {
          query = input.value;
          S.state.searchQuery = query;
          clearBtn.hidden = !query;
          shownTodos = PAGE;
          shownEvents = PAGE;
          draw();
        }, 300));
        input.addEventListener('keydown', (e) => {
          if (e.key === 'ArrowDown') { e.preventDefault(); focusHit(active + 1); }
          else if (e.key === 'ArrowUp') { e.preventDefault(); focusHit(active - 1); }
          else if (e.key === 'Enter') {
            if (!hits.length) return;
            e.preventDefault();
            hits[active >= 0 ? active : 0].click();
          } else if (e.key === 'Escape') {
            if (query) {
              e.preventDefault(); e.stopPropagation();
              input.value = ''; query = ''; S.state.searchQuery = ''; clearBtn.hidden = true; draw();
            }
          }
        });
        draw();
        setTimeout(() => input.focus(), 30);
      },
    });
    return page;
  }

  App.defineView('search', renderSearch);
})();
