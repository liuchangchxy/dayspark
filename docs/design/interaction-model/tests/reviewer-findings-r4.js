/* Round-4 reviewer regression suite. Each scenario reproduces one finding from
   REVIEW_ROUND4.md using the reviewer's own steps, then asserts the frozen
   contract in CORE_UX_SPEC.md / BEHAVIORS.md. */
const path = require('path');
const { chromium } = require('playwright-core');

const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', 'index.html');
const DESKTOP = { width: 1440, height: 900 };
const MID = { width: 1000, height: 860 };
const MOBILE = { width: 390, height: 844 };

const scenarios = [];
function scenario(name, fn) { scenarios.push({ name, fn }); }
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function assertEq(actual, expected, msg) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}
async function newPage(browser, viewport) {
  const page = await browser.newPage({ viewport: viewport || DESKTOP });
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  page.__errors = errors;
  return page;
}
const settle = (page, ms) => page.waitForTimeout(ms === undefined ? 200 : ms);
async function go(page, name, params) {
  await page.evaluate(([n, p]) => window.App.go(n, p), [name, params || null]);
  await settle(page);
}
const exists = (page, sel) => page.evaluate((s) => !!document.querySelector(s), sel);
async function clickTestId(page, id) {
  await page.click(`[data-testid="${id}"]`);
  await settle(page, 160);
}
async function clickText(page, selector, text) {
  const ok = await page.evaluate(([s, t]) => {
    const b = Array.from(document.querySelectorAll(s)).find((x) => x.textContent.trim().includes(t));
    if (!b) return false;
    b.click();
    return true;
  }, [selector, text]);
  assert(ok, `no ${selector} containing ${text}`);
  await settle(page, 180);
}
function assertNoErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}

/* D1 — a re-render must not wipe the draft or its guard */
scenario('D1 composer draft survives a breakpoint resize and keeps the discard guard', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '我的草稿标题');
  await clickTestId(page, 'composer-more');
  await page.fill('[data-testid="composer-notes"]', '草稿备注：不要在缩放后消失');
  await settle(page, 120);
  await page.setViewportSize(MID);
  await settle(page, 320);
  assertEq(await page.inputValue('[data-testid="composer-title"]'), '我的草稿标题', 'title after resize');
  assertEq(await page.inputValue('[data-testid="composer-notes"]'), '草稿备注：不要在缩放后消失', 'notes after resize');
  await clickTestId(page, 'composer-close');
  assert(await exists(page, '.modal.confirm, .modal'), 'closing a dirty draft must ask first');
  await clickText(page, '.modal-foot button', '放弃');
  await settle(page, 200);
  assert((await page.evaluate(() => window.Store.state.route.name)) !== 'composer', 'composer should close after discarding');
  assertNoErrors(page);
  await page.close();
});

/* D2 — creating a calendar mid-compose keeps the draft and selects the calendar */
scenario('D2 creating a calendar inside the composer selects it without losing the draft', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '属于新日历的草稿');
  await clickTestId(page, 'composer-deadline');
  await page.fill('[data-testid="deadline-date"]', await page.evaluate(() => window.U.toInputDate(window.U.now())));
  await page.fill('[data-testid="deadline-time"]', '18:00');
  await clickTestId(page, 'deadline-apply');
  await clickTestId(page, 'calendar-picker');
  await clickTestId(page, 'calendar-new');
  await page.fill('[data-testid="calendar-name"]', '新日历Q');
  await clickTestId(page, 'calendar-create');
  await settle(page, 320);
  assertEq(await page.inputValue('[data-testid="composer-title"]'), '属于新日历的草稿', 'title survived calendar creation');
  const calId = await page.evaluate(() => window.Store.state.calendars.find((c) => c.name === '新日历Q').id);
  const selected = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="calendar-option"][aria-pressed="true"]');
    return b ? Number(b.dataset.id) : null;
  });
  assertEq(selected, calId, 'the new calendar must be selected in the reopened picker');
  await page.keyboard.press('Escape');
  await settle(page, 160);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 280);
  const saved = await page.evaluate((name) => window.Store.liveTodos().find((t) => t.summary === name), '属于新日历的草稿');
  assert(saved, 'todo was not saved');
  assertEq(saved.calendarId, calId, 'saved todo must belong to the new calendar');
  assertNoErrors(page);
  await page.close();
});

/* D3 — deleting the pane's record clears the selection and writes stop */
scenario('D3 deleting the selected record clears the pane and never leaves a dead detail', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const target = await page.evaluate(() => {
    const id = Number(document.querySelector('[data-testid="todo-tile"]').dataset.id);
    return id;
  });
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 220);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'pane did not open');
  await clickText(page, '[data-testid="detail-pane-body"] .detail-actions button', '移到回收站');
  await settle(page, 200);
  await clickText(page, '.modal-foot button', '移到回收站');
  await settle(page, 300);
  assertEq(await page.evaluate(() => window.Store.state.paneSelection), null, 'pane selection must clear on delete');
  assertEq(await page.evaluate(() => window.Store.state.route.name), 'todos', 'deleting in the pane must stay on Todo');
  assert(!(await exists(page, '[data-testid="detail-complete"]')), 'a trashed record must not offer completion');
  const alive = await page.evaluate((id) => {
    window.Store.purgeTodo(id);
    window.App.render();
    return document.querySelector('#view').children.length;
  }, target);
  assert(alive > 0, 'purging the selected record must not blank the view');
  assertNoErrors(page);
  await page.close();
});

/* D4 — a tick completes the browsed day's occurrence, not today's */
scenario('D4 ticking a recurring row on a browsed day completes that day occurrence', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const info = await page.evaluate(() => {
    const tomorrow = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    window.__todoHelpers.setView({ kind: 'day', day: tomorrow });
    const todo = window.Store.liveTodos().find((t) => t.recurrence && window.Store.matchesRule(t, tomorrow));
    return todo ? { id: todo.id, tomorrow: tomorrow.getTime() } : null;
  });
  assert(info, 'seed should have a recurring to-do due tomorrow');
  await settle(page, 220);
  const toggled = await page.evaluate((id) => {
    const row = document.querySelector(`[data-testid="todo-tile"][data-id="${id}"] .checkbox`);
    if (!row) return false;
    row.click();
    return true;
  }, info.id);
  assert(toggled, 'recurring row not found on the browsed day');
  await settle(page, 220);
  const res = await page.evaluate(([id, ms]) => {
    const todo = window.Store.todoById(id);
    const day = new Date(ms);
    const today = window.U.startOfDay(window.U.now());
    return {
      browsed: window.Store.isOccurrenceDone(todo, window.Store.occurrenceIdFor(todo, day)),
      today: window.Store.isOccurrenceDone(todo, window.Store.occurrenceIdFor(todo, today)),
    };
  }, [info.id, info.tomorrow]);
  assertEq(res.browsed, true, 'the browsed day occurrence must be completed');
  assertEq(res.today, false, 'today occurrence must be untouched');
  assertNoErrors(page);
  await page.close();
});

/* D5 — a recurring planned-and-due task is one row on Today */
scenario('D5 a recurring planned-and-due todo appears once, allocation primary', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  const info = await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    const alloc = window.Store.state.allocations.find((a) => {
      const t = window.Store.todoById(a.todoId);
      return t && t.recurrence && t.dueDate && window.U.sameDay(t.dueDate, today) && a.state === 'active';
    });
    return alloc ? { id: alloc.todoId } : null;
  });
  assert(info, 'seed should contain a recurring planned-and-due todo');
  const rows = await page.evaluate((id) => ({
    allocation: document.querySelectorAll(`[data-testid="action-allocation"][data-id="${id}"]`).length,
    instance: document.querySelectorAll(`[data-testid="action-instance"][data-id="${id}"]`).length,
  }), info.id);
  assertEq(rows.allocation, 1, 'the allocation row must be present');
  assertEq(rows.instance, 0, 'the same obligation must not also appear as an instance row');
  assertNoErrors(page);
  await page.close();
});

/* D6 — every phone control the review measured is at least 48px tall */
scenario('D6 phone controls measured by the review are at least 48px', async (browser) => {
  const page = await newPage(browser, MOBILE);
  const sizes = {};
  async function record(name, selector) {
    const box = await page.evaluate((sel) => {
      const n = document.querySelector(sel);
      if (!n) return null;
      const r = n.getBoundingClientRect();
      return { w: Math.round(r.width), h: Math.round(r.height), visible: r.width > 0 && r.height > 0 };
    }, selector);
    if (box) sizes[name] = box;
  }
  await go(page, 'action');
  await record('plan-bar', '[data-testid="plan-day"]');
  await go(page, 'todos');
  await record('plan-bar', '[data-testid="plan-day"]');
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .actions button').click());
  await settle(page, 160);
  await record('row-menu-item', '.menu button');
  await page.keyboard.press('Escape');
  await settle(page, 120);
  await clickTestId(page, 'todos-filter');
  await record('filter-chip', '[data-testid="filter-apply"]');
  await page.keyboard.press('Escape');
  await go(page, 'calendar');
  await page.evaluate(() => { window.Store.state.calendarView = 'day'; window.App.render(); });
  await settle(page, 260);
  await record('all-day-chip', '.all-day-row .month-event');
  await record('calendar-block', '.timegrid .block');
  await go(page, 'settings');
  await record('swatch', '.swatch');
  await record('switch', '.switch');
  await record('segmented', '.segmented button');
  await go(page, 'search');
  await record('search-input', '[data-testid="search-input"]');
  await go(page, 'chat');
  await record('chat-input', '[data-testid="chat-input"]');
  await go(page, 'todos');
  await page.evaluate(() => {
    const t = window.Store.liveTodos()[0];
    window.Store.softDeleteTodo(t.id);
    window.App.render();
  });
  await settle(page, 220);
  await record('toast-undo', '.toast .undo');
  await record('toast-close', '.toast .x');
  const bad = Object.entries(sizes).filter(([, b]) => b.visible && b.h < 48);
  assertEq(bad, [], 'controls below 48px: ' + JSON.stringify(bad));
  assertNoErrors(page);
  await page.close();
});

/* D7 — the form never completes a whole series */
scenario('D7 a repeating todo offers no series-level completion control', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const id = await page.evaluate(() => window.Store.liveTodos().find((t) => t.recurrence).id);
  await page.evaluate((todoId) => window.App.openComposer('todo', { mode: 'edit', id: todoId }), id);
  await settle(page, 260);
  assert(!(await exists(page, '[data-testid="composer-status-done"]')), 'a series must not offer a completed state');
  const before = await page.evaluate((todoId) => window.Store.todoById(todoId).occurrenceStates, id);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 260);
  const after = await page.evaluate((todoId) => {
    const t = window.Store.todoById(todoId);
    return { status: t.status, states: t.occurrenceStates };
  }, id);
  assertEq(after.status, 'NEEDS-ACTION', 'saving the series form must not complete it');
  assertEq(after.states, before, 'saving must not touch occurrence state');
  assertNoErrors(page);
  await page.close();
});

/* D8 — a routed detail has a visible back control at 900–1179 */
scenario('D8 a routed detail offers a pointer exit at mid width', async (browser) => {
  const page = await newPage(browser, MID);
  await go(page, 'todos');
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 240);
  assert(await exists(page, '[data-testid="todo-detail"]'), 'detail did not open');
  assert(await exists(page, '[data-testid="todo-detail"] .back-btn, .detail-head .back-btn'), 'no visible back control');
  assertNoErrors(page);
  await page.close();
});

/* D10 — browser Back closes the pane and re-renders it */
scenario('D10 browser Back closes the pane immediately', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 220);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'pane did not open');
  await page.goBack();
  await settle(page, 260);
  assert(!(await exists(page, '[data-testid="detail-pane-body"]')), 'pane must be gone after Back');
  assert(await exists(page, '.md-empty'), 'the pane area should show its empty state');
  assertNoErrors(page);
  await page.close();
});

/* D11 — filtering the selected record out clears the pane */
scenario('D11 filtering the selected record out clears the pane', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((t) => t.calendarId === 1);
    window.__todoHelpers.setView({ kind: 'all', day: null });
    window.Store.selectPane('todo', todo.id);
  });
  await settle(page, 220);
  const otherCal = await page.evaluate(() => window.Store.state.calendars.find((c) => c.id !== 1).id);
  await clickTestId(page, 'todos-filter');
  await clickTestId(page, 'filter-calendar-' + otherCal);
  await clickTestId(page, 'filter-apply');
  await settle(page, 240);
  assertEq(await page.evaluate(() => window.Store.state.paneSelection), null, 'pane selection must clear when filtered out');
  assertNoErrors(page);
  await page.close();
});

/* D13 — a subtask's completion state is saved */
scenario('D13 subtask completion state is saved from the form', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.liveTodos().find((t) => t.parentId).id);
  await page.evaluate((todoId) => window.App.openComposer('todo', { mode: 'edit', id: todoId }), id);
  await settle(page, 260);
  await clickTestId(page, 'composer-status-done');
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 280);
  assertEq(await page.evaluate((todoId) => window.Store.todoById(todoId).status, id), 'COMPLETED', 'subtask status must be written');
  assertNoErrors(page);
  await page.close();
});

/* D14 — a repeat without a deadline must not invent one */
scenario('D14 repeating an undated todo does not fabricate a deadline', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '无截止的重复任务');
  // Clear the deadline the day-view create control inherited, then repeat.
  await clickTestId(page, 'composer-deadline');
  await clickText(page, '.sheet button', '无截止');
  await clickTestId(page, 'composer-more');
  await clickTestId(page, 'composer-repeat');
  await clickText(page, '.sheet .slot-sheet-option', '每天');
  await settle(page, 200);
  const due = await page.evaluate(() => {
    const text = document.querySelector('[data-testid="composer-deadline"]').textContent;
    return text;
  });
  assert(!/11月16日|11月17日/.test(due), 'repeat must not set a deadline: ' + due);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 280);
  const saved = await page.evaluate(() => window.Store.liveTodos().find((t) => t.summary === '无截止的重复任务'));
  assert(saved && !saved.dueDate, 'saved todo must have no deadline');
  assert(saved.startDate, 'the series should be anchored by startDate instead');
  assertNoErrors(page);
  await page.close();
});

/* D15 — the date subtitle names the year when it differs */
scenario('D15 the date header includes a different year', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const nextYear = await page.evaluate(() => {
    const now = new Date();
    const d = new Date(now.getFullYear() + 1, 10, 1);
    window.__todoHelpers.setView({ kind: 'day', day: d });
    return d.getFullYear();
  });
  await settle(page, 240);
  const sub = await page.textContent('[data-testid="todos-date-picker"]');
  assert(sub.includes(String(nextYear)), 'date header should include the year: ' + sub);
  assertNoErrors(page);
  await page.close();
});

/* D16 — the padded containers forward taps to their fields */
scenario('D16 search and chat containers focus their fields on tap', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'search');
  await page.evaluate(() => document.querySelector('.search-box').click());
  await settle(page, 120);
  assertEq(await page.evaluate(() => document.activeElement.dataset.testid), 'search-input', 'search container must focus the field');
  await go(page, 'chat');
  await page.evaluate(() => document.querySelector('.chat-input').click());
  await settle(page, 120);
  assertEq(await page.evaluate(() => document.activeElement.dataset.testid), 'chat-input', 'chat container must focus the field');
  assertNoErrors(page);
  await page.close();
});

/* D17 — a tool destination retires the pane */
scenario('D17 a tool destination clears the pane selection', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 220);
  await go(page, 'settings');
  await go(page, 'todos');
  assertEq(await page.evaluate(() => window.Store.state.paneSelection), null, 'pane selection must not survive Settings');
  assert(!(await exists(page, '[data-testid="detail-pane-body"]')), 'no stale pane on return');
  assertNoErrors(page);
  await page.close();
});

/* D18 — quick add's preview never prints [object Object] */
scenario('D18 quick add preview renders human text', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'quickadd');
  await page.fill('[data-testid="quickadd-input"]', '明天下午三点 开会');
  await settle(page, 200);
  const preview = await page.textContent('[data-testid="quickadd-preview"]');
  assert(!preview.includes('[object Object]'), 'preview leaked an object: ' + preview);
  assert(/15:00/.test(preview), 'preview should name the parsed time: ' + preview);
  assertNoErrors(page);
  await page.close();
});

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  let passed = 0;
  const failures = [];
  for (const s of scenarios) {
    const t0 = Date.now();
    try {
      await s.fn(browser);
      passed += 1;
      console.log(`PASS ${s.name} (${Date.now() - t0}ms)`);
    } catch (err) {
      failures.push({ name: s.name, err });
      console.log(`FAIL ${s.name}\n     ${err.message.split('\n')[0]}`);
    }
  }
  await browser.close();
  console.log(`\n${passed}/${scenarios.length} round-4 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.err.message.split('\n')[0]));
    process.exit(1);
  }
})();
