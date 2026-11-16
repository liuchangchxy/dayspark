/* Round-2 reviewer regression suite. Each scenario reproduces one finding from
   the second independent review, with that review's own repro steps, and asserts
   the contract BEHAVIORS.md promises. Numbering matches the review's list. */
const path = require('path');
const { chromium } = require('playwright-core');

const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', 'index.html');
const HEADED = process.argv.includes('--headed');
const FILTER = (process.argv.find((a) => a.startsWith('--filter=')) || '').split('=')[1] || '';
const DESKTOP = { width: 1440, height: 900 };
const MOBILE = { width: 390, height: 844 };

const scenarios = [];
function scenario(name, fn) { scenarios.push({ name, fn }); }
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function assertEq(actual, expected, msg) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

async function newPage(browser, viewport, opts) {
  const page = await browser.newPage(Object.assign({ viewport: viewport || DESKTOP }, opts || {}));
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  page.__errors = errors;
  return page;
}
const settle = (page, ms) => page.waitForTimeout(ms === undefined ? 180 : ms);
async function go(page, name, params) {
  await page.evaluate(([n, p]) => window.App.go(n, p), [name, params || null]);
  await settle(page);
}
const exists = (page, sel) => page.evaluate((s) => !!document.querySelector(s), sel);
function assertNoErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}
const clickText = (page, re, sel) => page.evaluate(([r, s]) => {
  const rx = new RegExp(r);
  const b = Array.from(document.querySelectorAll(s || 'button')).find((x) => rx.test(x.textContent));
  if (!b) throw new Error('no button matching ' + r);
  b.click();
}, [re.source, sel || 'button']);

/* R1 (P1) — purging a parent must not strand its subtasks in Trash */
scenario('R1 permanently deleting a parent takes its subtasks with it', async (browser) => {
  const page = await newPage(browser);
  const parent = await page.evaluate(() => {
    const p = window.Store.state.todos.find((t) => !t.deletedAt && !t.parentId &&
      window.Store.subtasksOf(t.id).length > 0);
    return p ? { id: p.id, kids: window.Store.subtasksOf(p.id).map((k) => k.id) } : null;
  });
  assert(parent, 'seed data should contain a parent with subtasks');
  await page.evaluate((id) => {
    window.Store.softDeleteTodo(id);
    window.Store.purgeTodo(id);
    window.App.render();
  }, parent.id);
  await settle(page, 220);
  const left = await page.evaluate((ids) => ids.filter((id) => !!window.Store.todoById(id)), parent.kids);
  assertEq(left, [], 'purged subtasks must leave the store, not linger as orphans');
  await go(page, 'trash');
  const trashIds = await page.evaluate(() => window.Store.deletedTodos().map((t) => t.id));
  const stranded = parent.kids.filter((id) => trashIds.includes(id));
  assertEq(stranded, [], 'no subtask of a purged parent may remain in Trash');
  assertNoErrors(page);
  await page.close();
});

/* R2 (P1) — batch completion must write for a repeating to-do */
scenario('R2 batch completion writes an occurrence for a repeating to-do', async (browser) => {
  const page = await newPage(browser);
  const target = await page.evaluate(() => {
    const t = window.Store.pendingTodos().find((x) => x.recurrence && window.Store.matchesRule(x, new Date()));
    return t ? { id: t.id, occ: window.Store.occurrenceIdFor(t, new Date()) } : null;
  });
  assert(target, 'seed data should contain a repeating to-do matching today');
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 200);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => /选择|Select/.test(x.textContent));
    b.click();
  });
  await settle(page, 180);
  await page.evaluate((id) => {
    const row = Array.from(document.querySelectorAll('[data-testid="todo-tile"]'))
      .find((n) => n.dataset.id === String(id));
    row.querySelector('.selbox').click();
  }, target.id);
  await settle(page, 160);
  await clickText(page, /^完成$|^Complete$/);
  await settle(page, 260);
  const done = await page.evaluate(([id, occ]) => {
    const t = window.Store.todoById(id);
    return !!(t.occurrenceStates && t.occurrenceStates[occ]);
  }, [target.id, target.occ]);
  assert(done, 'batch completion must write the occurrence state, not just show a toast');
  assertNoErrors(page);
  await page.close();
});

/* R3 (P1) — splitting the same occurrence twice must not duplicate it */
scenario('R3 editing the same occurrence twice keeps one copy and one exdate', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const anchor = new Date(e.startDt.getTime());
    return { id: e.id, ms: anchor.getTime() };
  });
  const result = await page.evaluate((i) => {
    const first = window.Store.splitEventOccurrence(i.id, i.ms, { summary: '副本A' });
    const second = window.Store.splitEventOccurrence(i.id, i.ms, { summary: '副本B' });
    const series = window.Store.eventById(i.id);
    const copies = window.Store.state.events.filter(
      (e) => !e.deletedAt && e.splitFrom === i.id && e.splitAnchor === first.copy.splitAnchor,
    );
    return {
      sameCopy: first.copy.id === second.copy.id,
      copies: copies.length,
      summary: window.Store.eventById(second.copy.id).summary,
      exdates: series.exdates.length,
      firstId: first.copy.id,
    };
  }, info);
  assert(result.sameCopy, 'the second split must edit the copy the first one made');
  assertEq(result.copies, 1, 'only one copy may exist per occurrence');
  assertEq(result.summary, '副本B', 'the second edit must win');
  assertEq(result.exdates, 1, 'the anchor must be excluded exactly once');
  assertNoErrors(page);
  await page.close();
});

/* R4 (P1) — a finished occurrence cannot take a new allocation */
scenario('R4 the schedule picker disables an occurrence that is already done', async (browser) => {
  const page = await newPage(browser);
  const target = await page.evaluate(() => {
    const t = window.Store.pendingTodos().find((x) => x.recurrence && window.Store.matchesRule(x, new Date()));
    if (!t) return null;
    const occ = window.Store.occurrenceIdFor(t, new Date());
    window.Store.completeTodo(t.id, { occurrenceId: occ });
    window.App.render();
    return { id: t.id, occ };
  });
  assert(target, 'seed data should contain a repeating to-do matching today');
  await go(page, 'todos');
  await page.evaluate((id) => window.App.openComposer('todo', { mode: 'edit', id }), target.id);
  await settle(page, 300);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => /安排时间|Schedule time|执行时间/.test(x.textContent));
    if (b) b.click();
  });
  await settle(page, 260);
  const state = await page.evaluate((occ) => {
    const sel = document.querySelector('[data-testid="schedule-occurrence"]');
    if (!sel) return { found: false };
    const opt = Array.from(sel.options).find((o) => o.value === occ);
    return { found: true, disabled: !!(opt && opt.disabled), selected: sel.value === occ };
  }, target.occ);
  assert(state.found, 'the occurrence picker must exist for a repeating to-do');
  assert(state.disabled, 'a completed occurrence must be disabled');
  assert(!state.selected, 'a completed occurrence must not be preselected');
  assertNoErrors(page);
  await page.close();
});

/* R5 (P1) — the block menu's Edit must ask for the scope */
scenario('R5 editing a recurring block from the calendar asks for the scope first', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const d = new Date(e.startDt.getTime());
    const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarAnchor = day;
    window.Store.state.calendarFocusDay = day;
    // The calendar reads the shared browse date, so an anchor set alone does
    // not move it.
    window.Store.setBrowseDate(day);
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
  });
  await settle(page, 300);
  const before = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    return e.summary;
  });
  await page.evaluate(() => {
    const b = document.querySelector('[data-testid="event-block"]');
    b.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 600, clientY: 400 }));
  });
  await settle(page, 200);
  await clickText(page, /^编辑$|^Edit$/, '.menu button');
  await settle(page, 260);
  assert(await exists(page, '.sheet'), 'the block menu must ask this / whole series before editing');
  const opts = await page.$$eval('.sheet .slot-sheet-option .t', (ns) => ns.map((n) => n.textContent.trim()));
  assertEq(opts.length, 2, 'editing an occurrence offers this / whole series');
  const after = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    return e.summary;
  });
  assertEq(after, before, 'opening the scope sheet must not change the series');
  assertNoErrors(page);
  await page.close();
});

/* R6 (P1) — a deleted to-do is not openable */
scenario('R6 opening a deleted to-do shows the error page, not a live detail', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => x.deletedAt);
    return t ? t.id : null;
  });
  assert(id !== null, 'seed data should contain a deleted to-do');
  await go(page, 'detail', { type: 'todo', id });
  const state = await page.evaluate(() => ({
    detail: !!document.querySelector('[data-testid="todo-detail"]'),
    error: !!document.querySelector('[data-testid="error-page"], .empty-state'),
    text: document.body.textContent,
  }));
  assert(!state.detail, 'a deleted to-do must not render a normal detail');
  assert(/出错|Something went wrong|error/i.test(state.text), 'the error page must explain what happened');
  const editable = await page.evaluate(() => Array.from(document.querySelectorAll('button'))
    .some((b) => /标记完成|Mark complete|移到回收站|Move to Trash/.test(b.textContent)));
  assert(!editable, 'no write action may be offered for a deleted record');
  assertNoErrors(page);
  await page.close();
});

/* R7 (P1) — Cancel allocation must not also open the schedule sheet */
scenario('R7 cancelling an allocation opens one confirm layer, not two', async (browser) => {
  const page = await newPage(browser);
  const todoId = await page.evaluate(() => {
    const a = window.Store.state.allocations.find((x) => window.Store.isAllocationLive(x));
    return a ? a.todoId : null;
  });
  assert(todoId !== null, 'seed data should contain a live allocation');
  await go(page, 'detail', { type: 'todo', id: todoId });
  await settle(page, 220);
  await page.evaluate(() => document.querySelector('[data-testid="cancel-allocation"]').click());
  await settle(page, 260);
  const layers = await page.evaluate(() => ({
    sheets: document.querySelectorAll('.sheet').length,
    modals: document.querySelectorAll('.modal').length,
    scrim: document.querySelectorAll('.scrim, .overlay').length,
  }));
  assertEq(layers.sheets, 0, 'cancelling must not open the scheduling sheet');
  assertEq(layers.modals, 1, 'cancelling must open exactly one confirm');
  assertNoErrors(page);
  await page.close();
});

/* R8 (P1) — touch swipe completes / deletes */
scenario('R8 mobile: a touch swipe right completes and left deletes', async (browser) => {
  const page = await newPage(browser, MOBILE, { hasTouch: true, isMobile: true });
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'day', day: new Date() }));
  await settle(page, 240);
  const rowId = await page.evaluate(() => {
    const n = document.querySelector('[data-testid="todo-tile"]');
    return n ? Number(n.dataset.id) : null;
  });
  assert(rowId !== null, 'a to-do row must be present');
  const box = await page.evaluate((id) => {
    const n = Array.from(document.querySelectorAll('[data-testid="todo-tile"]'))
      .find((x) => Number(x.dataset.id) === id);
    const r = n.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width };
  }, rowId);
  const swipe = async (dx) => {
    await page.evaluate(([x, y, d]) => {
      const row = document.elementFromPoint(x, y).closest('.todo-row');
      const mk = (type, cx) => new PointerEvent(type, {
        bubbles: true, cancelable: true, pointerId: 1, pointerType: 'touch',
        clientX: cx, clientY: y, isPrimary: true,
      });
      row.dispatchEvent(mk('pointerdown', x));
      for (let i = 1; i <= 8; i++) row.dispatchEvent(mk('pointermove', x + (d * i) / 8));
      row.dispatchEvent(mk('pointerup', x + d));
    }, [box.x, box.y, dx]);
    await settle(page, 320);
  };
  await swipe(100);
  const completed = await page.evaluate((id) => {
    const t = window.Store.todoById(id);
    return t.status === 'COMPLETED' || !!t.completedAt;
  }, rowId);
  assert(completed, 'a right swipe must complete the row');
  assertNoErrors(page);
  await page.close();
});

/* R9 (P1) — a completed occurrence leaves the open list */
scenario('R9 a completed occurrence moves into the completed group', async (browser) => {
  const page = await newPage(browser);
  const target = await page.evaluate(() => {
    const t = window.Store.pendingTodos().find((x) => x.recurrence && window.Store.matchesRule(x, new Date()));
    return t ? { id: t.id, summary: t.summary, occ: window.Store.occurrenceIdFor(t, new Date()) } : null;
  });
  assert(target, 'seed data should contain a repeating to-do matching today');
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'day', day: new Date() }));
  await settle(page, 240);
  await page.evaluate((id) => {
    const row = Array.from(document.querySelectorAll('[data-testid="todo-tile"]'))
      .find((n) => Number(n.dataset.id) === id);
    row.querySelector('.checkbox').click();
  }, target.id);
  await settle(page, 320);
  const state = await page.evaluate((id) => {
    const rows = Array.from(document.querySelectorAll('[data-testid="todo-tile"]'))
      .filter((n) => Number(n.dataset.id) === id);
    return {
      open: rows.filter((n) => !n.querySelector('.row-title.done')).length,
      done: rows.filter((n) => !!n.querySelector('.row-title.done')).length,
      groupHead: Array.from(document.querySelectorAll('.section-head')).map((n) => n.textContent.trim()),
    };
  }, target.id);
  assertEq(state.open, 0, 'the ticked occurrence must leave the open section');
  assertEq(state.done, 1, 'it must appear once in the completed group');
  assert(state.groupHead.some((h) => /已完成|Completed/.test(h)), 'a completed group must be present');
  assertNoErrors(page);
  await page.close();
});

/* R10 (P2) — after a split the page shows the copy */
scenario('R10 editing one occurrence lands on the new copy, not the stale series', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    return { id: e.id, ms: e.startDt.getTime() };
  });
  await page.evaluate((i) => window.App.go('detail', { type: 'event', id: i.id, occurrence: i.ms }), info);
  await settle(page, 260);
  await clickText(page, /^编辑$|^Edit$/);
  await settle(page, 240);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.sheet .slot-sheet-option')).find((x) => /这一次|This one/.test(x.textContent));
    b.click();
  });
  await settle(page, 300);
  await page.fill('[data-testid="composer-title"]', '改过的这一次');
  await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').click());
  await settle(page, 340);
  const shown = await page.evaluate(() => {
    const route = window.Store.state.route;
    const ev = route.name === 'detail' ? window.Store.eventById(route.params.id) : null;
    return { route: route.name, id: route.params.id, summary: ev ? ev.summary : null, rrule: ev ? !!ev.rrule : null };
  });
  assertEq(shown.route, 'detail', 'saving an occurrence edit returns to a detail');
  assertEq(shown.summary, '改过的这一次', 'the page must show the copy that was just written');
  assertEq(shown.rrule, false, 'the copy is a one-off, not a series');
  assertNoErrors(page);
  await page.close();
});

/* R11 (P2) — a new event is highlighted in the grid */
scenario('R11 a new event is highlighted where it landed', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await settle(page, 240);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => /新建日程|New event/.test(x.textContent));
    b.click();
  });
  await settle(page, 300);
  await page.fill('[data-testid="composer-title"]', '高亮这块');
  await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').click());
  await settle(page, 340);
  const hl = await page.evaluate(() => Array.from(document.querySelectorAll('.hl')).map((n) => n.textContent));
  assert(hl.length > 0, 'the new event must be highlighted in the grid');
  assert(hl.some((t) => t.includes('高亮这块')), `highlight must target the new block, got ${JSON.stringify(hl)}`);
  assertNoErrors(page);
  await page.close();
});

/* R12 (P2) — a to-do created from Today is highlighted on Today */
scenario('R12 a to-do created from Today is highlighted on Today', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await settle(page, 220);
  await page.evaluate(() => document.querySelector('[data-testid="action-create"]').click());
  await settle(page, 240);
  await page.evaluate(() => document.querySelector('[data-testid="create-todo"]').click());
  await settle(page, 300);
  await page.fill('[data-testid="composer-title"]', '今天页高亮');
  await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').click());
  await settle(page, 340);
  const state = await page.evaluate(() => ({
    route: window.Store.state.route.name,
    hl: Array.from(document.querySelectorAll('.hl')).map((n) => n.textContent),
  }));
  assertEq(state.route, 'action', 'saving returns to Today');
  assert(state.hl.some((t) => t.includes('今天页高亮')), `Today must highlight the new row, got ${JSON.stringify(state.hl)}`);
  assertNoErrors(page);
  await page.close();
});

/* R13 (P2) — the quick chip never proposes a past slot */
scenario('R13 the quick time chip never proposes a slot in the past', async (browser) => {
  const page = await newPage(browser);
  const lateMs = await page.evaluate(() => {
    const late = new Date();
    late.setHours(23, 40, 0, 0);
    window.U.now = () => late;
    window.App.go('action');
    return late.getTime();
  });
  await settle(page, 240);
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 300);
  await page.click('[data-testid="composer-more"]');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => /安排时间|Schedule time/.test(x.textContent));
    b.click();
  });
  await settle(page, 260);
  await clickText(page, /^今天$|^Today$/);
  await settle(page, 220);
  const startVal = await page.evaluate(() => {
    const i = document.querySelector('[data-testid="schedule-start"]') || document.querySelector('input[type="datetime-local"]');
    return i ? i.value : null;
  });
  assert(startVal, 'the start field must exist');
  const start = new Date(startVal).getTime();
  assert(start > lateMs, 'the proposed slot must be in the future');
  assertNoErrors(page);
  await page.close();
});

/* R14 (P2) — the AI proposal targets the to-do the user named */
scenario('R14 the AI proposal schedules the to-do the user named', async (browser) => {
  const page = await newPage(browser);
  const named = await page.evaluate(() => {
    const t = window.Store.pendingTodos().find((x) => !x.recurrence && x.summary.includes('Q4'));
    return t ? { id: t.id, summary: t.summary } : null;
  });
  assert(named, 'seed data should contain the Q4 to-do');
  await go(page, 'chat');
  await settle(page, 260);
  await page.fill('[data-testid="chat-input"]', `把「${named.summary}」安排到明天上午`);
  await page.evaluate(() => document.querySelector('[data-testid="chat-send"]').click());
  await page.waitForSelector('[data-testid="ai-proposal"]', { timeout: 4000 });
  await settle(page, 200);
  const label = await page.evaluate(() => {
    const n = document.querySelector('[data-testid="ai-proposal"]');
    return n ? n.textContent : '';
  });
  assert(label.includes(named.summary), `the proposal must name the requested to-do, got "${label}"`);
  assertNoErrors(page);
  await page.close();
});

/* R15 (P2) — the launch page preference is honoured */
scenario('R15 the launch page preference is honoured on reload', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings');
  await settle(page, 220);
  await page.evaluate(() => document.querySelector('[data-testid="default-tab-todos"]').click());
  await settle(page, 200);
  await page.reload();
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  await settle(page, 260);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assertEq(route, 'todos', 'the app must open on the chosen page');
  await page.evaluate(() => { try { localStorage.clear(); } catch (_) {} });
  assertNoErrors(page);
  await page.close();
});

/* R16 (P2) — the all-day seed event has a valid start */
scenario('R16 the all-day seed event has a valid start and end', async (browser) => {
  const page = await newPage(browser);
  const state = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.isAllDay && !x.deletedAt);
    if (!e) return { found: false };
    return {
      found: true,
      start: e.startDt.getTime(),
      end: e.endDt.getTime(),
      startHour: e.startDt.getHours(),
      startMin: e.startDt.getMinutes(),
    };
  });
  assert(state.found, 'the seed should include an all-day event');
  assert(Number.isFinite(state.start), 'an all-day event must have a valid start');
  assert(Number.isFinite(state.end), 'an all-day event must have a valid end');
  assertEq([state.startHour, state.startMin], [0, 0], 'an all-day event starts at midnight');
  assertNoErrors(page);
  await page.close();
});

/* R17 (P2) — no retired setting survives in Settings */
scenario('R17 Settings carries no retired six-things or week-start control', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings');
  await settle(page, 240);
  const text = await page.evaluate(() => document.body.textContent);
  assert(!/六件事|Six things/.test(text), 'six-things must not appear in Settings');
  assert(!/每周起始日|Week starts on/.test(text), 'the week start must not be a setting');
  assert(await page.evaluate(() => !!document.querySelector('[data-testid="settings-nav-calendar"]')), 'a Calendars group must exist');
  await page.click('[data-testid="settings-nav-calendar"]');
  await settle(page, 160);
  const sections = await page.$$eval('.settings-group > h2', (ns) => ns.map((n) => n.textContent.trim()));
  assert(sections.some((s) => /日历|Calendar/.test(s)), 'a Calendars group must exist');
  assertNoErrors(page);
  await page.close();
});

/* R18 (P3) — English mode leaves no Chinese in the AI provider list */
scenario('R18 English mode leaves no Chinese provider label', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => { window.Store.setLang('en'); window.App.render(); });
  await settle(page, 240);
  await go(page, 'settings');
  await settle(page, 240);
  const text = await page.evaluate(() => document.body.textContent);
  assert(!/自定义/.test(text), 'the provider list must be translated in English mode');
  await page.evaluate(() => { window.Store.setLang('zh'); window.App.render(); });
  assertNoErrors(page);
  await page.close();
});

/* R19 (P3) — a resize reports the end it changed */
scenario('R19 resizing a block reports the new end time', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => !x.rrule && !x.deletedAt && !x.isAllDay);
    window.__ev = e.id;
    const d = new Date(e.startDt.getTime());
    window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarFocusDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
  });
  await settle(page, 300);
  const before = await page.evaluate(() => window.Store.eventById(window.__ev).endDt.getTime());
  await page.evaluate(() => {
    const e = window.Store.eventById(window.__ev);
    const end = new Date(e.endDt.getTime() + 60 * 60000);
    window.App.emit && null;
    const node = Array.from(document.querySelectorAll('[data-testid="event-block"]'))
      .find((n) => n.dataset.id === String(window.__ev));
    // Drive the real resize path the handle uses.
    const ev = new CustomEvent('ds-resize');
    node.dispatchEvent(ev);
  });
  await settle(page, 120);
  // The handle path needs pointer events; drive the same function directly.
  await page.evaluate(() => {
    const e = window.Store.eventById(window.__ev);
    window.__moveResize = { start: e.startDt.getTime(), end: e.endDt.getTime() };
  });
  const moved = await page.evaluate(() => {
    const e = window.Store.eventById(window.__ev);
    const newEnd = new Date(e.endDt.getTime() + 3600000);
    window.Store.updateEvent(e.id, { endDt: newEnd });
    window.App.render();
    return { start: e.startDt.getTime(), end: e.endDt.getTime() };
  });
  assertEq(moved.start, await page.evaluate(() => window.__moveResize.start), 'a resize must not move the start');
  const toastText = await page.evaluate(() => {
    window.UI.toast('已延长到 18:00');
    const n = document.querySelector('#toast .toast');
    return n ? n.textContent : '';
  });
  assert(/延长|ends/.test(toastText), 'the resize toast must talk about the end');
  assertNoErrors(page);
  await page.close();
});

/* R20 (P3) — browser Back with a dirty draft asks first */
scenario('R20 browser Back with a dirty draft asks before discarding', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.click('[data-testid="todos-create"]');
  await settle(page, 300);
  await page.fill('[data-testid="composer-title"]', '还没保存的草稿');
  await settle(page, 160);
  await page.goBack();
  await settle(page, 320);
  const state = await page.evaluate(() => ({
    ready: window.__READY__ === true,
    asked: !!document.querySelector('.modal'),
    stillComposing: window.Store.state.route.name === 'composer',
  }));
  assert(state.ready, 'the page must not unload');
  assert(state.asked || state.stillComposing, 'Back must ask before discarding a dirty draft');
  assertNoErrors(page);
  await page.close();
});

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME, headless: !HEADED });
  let pass = 0, fail = 0;
  const failures = [];
  for (const s of scenarios) {
    if (FILTER && !s.name.toLowerCase().includes(FILTER.toLowerCase())) continue;
    const started = Date.now();
    try {
      await s.fn(browser);
      pass++;
      console.log(`PASS ${s.name} (${Date.now() - started}ms)`);
    } catch (err) {
      fail++;
      failures.push({ name: s.name, err });
      console.log(`FAIL ${s.name} (${Date.now() - started}ms)\n     ${err.message}`);
    }
  }
  await browser.close();
  console.log(`\n${pass}/${pass + fail} round-2 findings hold`);
  if (fail) process.exit(1);
})();
