/* Round-8 independent reviewer regression suite. */
const path = require('path');
const { chromium } = require('playwright-core');

const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', 'index.html');
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
function assertNoErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}

/* P1-1 — Today opens a recurring event's real start */
scenario('R8-1 a recurring event opened from Today shows its real time', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const now = window.U.now();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 14, 0);
    const e = window.Store.createEvent({
      summary: '每天复盘', startDt: start, endDt: window.U.addMinutes(start, 60), calendarId: 1,
      rrule: { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai' },
    });
    window.App.go('action');
    return { id: e.id };
  });
  await settle(page, 300);
  const row = await page.evaluate(() => {
    const r = Array.from(document.querySelectorAll('[data-testid="action-event"]')).find((x) => x.textContent.includes('每天复盘'));
    return r ? r.textContent : null;
  });
  assert(row && /14:00/.test(row), 'Today row must show 14:00: ' + row);
  await page.evaluate(() => {
    const r = Array.from(document.querySelectorAll('[data-testid="action-event"]')).find((x) => x.textContent.includes('每天复盘'));
    r.click();
  });
  await settle(page, 300);
  const detail = await page.textContent('[data-testid="event-detail"]');
  assert(/14:00/.test(detail) && !/00:00/.test(detail), 'the detail must show the real occurrence time: ' + detail);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('[data-testid="event-detail"] button'))
      .find((x) => /编辑|Edit/.test(x.getAttribute('aria-label') || ''));
    b.click();
  });
  await settle(page, 240);
  if (await exists(page, '[data-testid="scope-this"]')) {
    await clickTestId(page, 'scope-this');
    await settle(page, 240);
  }
  const startHour = await page.evaluate(() => {
    const d = window.Store.state.composerDraft.startDt;
    const x = new Date(d.__date !== undefined ? d.__date : d);
    return x.getHours();
  });
  assertEq(startHour, 14, 'editing the occurrence must start at 14:00, not midnight');
  assertNoErrors(page);
  await page.close();
});

/* P1-2 — a date-only deadline due today is not overdue */
scenario('R8-2 a date-only deadline due today is not painted overdue', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    window.Store.createTodo({ summary: '今天买菜', dueDate: today });
  });
  await go(page, 'todos');
  const todosText = await page.evaluate(() => {
    const tile = Array.from(document.querySelectorAll('[data-testid="todo-tile"]')).find((x) => x.textContent.includes('今天买菜'));
    return tile ? tile.textContent : '';
  });
  assert(todosText.includes('今天买菜'), 'the todo row is missing');
  assert(!/逾期/.test(todosText), 'Todos must not call a today deadline overdue: ' + todosText);
  const inOverdue = await page.evaluate(() => {
    const head = Array.from(document.querySelectorAll('.section-head')).find((n) => /已逾期/.test(n.textContent));
    if (!head) return false;
    let n = head.nextElementSibling;
    while (n && !n.classList.contains('section-head')) {
      if (n.textContent.includes('今天买菜')) return true;
      n = n.nextElementSibling;
    }
    return false;
  });
  assert(!inOverdue, 'a today deadline must not sit in the overdue section');
  await go(page, 'action');
  const todayRow = await page.evaluate(() => {
    const r = Array.from(document.querySelectorAll('[data-testid="action-todo"]')).find((x) => x.textContent.includes('今天买菜'));
    return r ? { cls: r.className, text: r.textContent } : null;
  });
  assert(todayRow, 'the todo is missing from Today');
  assert(!/逾期/.test(todayRow.text) && !/overdue/.test(todayRow.cls), 'Today must not paint a today deadline overdue: ' + JSON.stringify(todayRow));
  await go(page, 'calendar');
  const lane = await page.evaluate(() => {
    const chip = Array.from(document.querySelectorAll('.deadline-chip')).find((x) => x.textContent.includes('今天买菜'));
    if (!chip) return null;
    const date = chip.querySelector('.date');
    return date ? getComputedStyle(date).color : null;
  });
  assert(lane && !/rgb\(19[0-9]|var\(--red\)/.test(lane), 'the deadline lane must not paint it red: ' + lane);
  assertNoErrors(page);
  await page.close();
});

/* P2-1 — inner buttons keep their own keyboard activation */
scenario('R8-3 row inner controls are not hijacked by the row', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 240);
  const before = await page.evaluate(() => {
    const row = document.querySelector('.todo-row');
    const box = row.querySelector('.hit[role="checkbox"]');
    box.focus();
    return { id: row.dataset.id, done: box.getAttribute('aria-checked') };
  });
  await page.keyboard.press('Space');
  await settle(page, 280);
  assert(!(await exists(page, '[data-testid="detail-pane-body"]')), 'Space on the checkbox must not open the pane');
  const after = await page.evaluate((id) => {
    const t = window.Store.todoById(Number(id));
    return window.Store.isDone(t);
  }, before.id);
  assert(after !== (before.done === 'true'), 'Space on the checkbox must toggle completion');
  assertNoErrors(page);
  await page.close();
});

/* P2-2 — a subtask saved from a routed detail leaves no dead Back stop */
scenario('R8-4 subtask save does not leave the parent detail twice in Back', async (browser) => {
  const page = await newPage(browser, MOBILE);
  const info = await page.evaluate(() => {
    const parent = window.Store.liveTodos().find((x) => x.summary === '准备季度评审');
    window.App.go('todos');
    window.App.openRecord('todo', parent.id);
    return { id: parent.id };
  });
  await settle(page, 300);
  await page.evaluate((id) => window.App.openComposer('todo', { parentId: id }), info.id);
  await settle(page, 240);
  await page.fill('[data-testid="composer-title"]', '移动端子任务');
  await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').click());
  await settle(page, 300);
  await page.evaluate(() => window.App.back());
  await settle(page, 280);
  const after = await page.evaluate(() => ({
    route: window.Store.state.route.name,
    detail: !!document.querySelector('[data-testid="todo-detail"]'),
  }));
  assert(after.route !== 'detail', 'one Back must leave the parent detail, got ' + JSON.stringify(after));
  assertNoErrors(page);
  await page.close();
});

/* P2-3 — real touch commits a drag and a reorder */
scenario('R8-5 real touch drag and reorder commit', async (browser) => {
  const ctx = await browser.newContext({ viewport: MOBILE, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  const info = await page.evaluate(() => {
    const now = window.U.now();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 11, 0);
    const e = window.Store.createEvent({ summary: '触摸拖动', startDt: start, endDt: window.U.addMinutes(start, 60), calendarId: 1 });
    window.__calendarHelpers.setView('day');
    return { id: e.id };
  });
  await go(page, 'calendar');
  const box = await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }, info.id);
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x, y: box.y }] });
  for (let i = 1; i <= 6; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: box.x, y: box.y + i * 16 }] });
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await settle(page, 500);
  const moved = await page.evaluate((id) => {
    const e = window.Store.eventById(id);
    const d = new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt);
    return d.getHours() * 60 + d.getMinutes();
  }, info.id);
  assertEq(moved, 11 * 60 + 30, 'a real touch drag must move the block');

  await go(page, 'todos');
  // Manual order lives in the inventory list, not the date-grouped day view.
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 240);
  const order0 = await page.evaluate(() => window.Store.liveTodos().slice().sort((a, b) => a.sortOrder - b.sortOrder).map((t) => t.id).join(','));
  const grab = await page.evaluate(() => {
    const g = document.querySelector('.todo-row .grab').getBoundingClientRect();
    return { x: g.left + g.width / 2, y: g.top + g.height / 2 };
  });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: grab.x, y: grab.y }] });
  for (let i = 1; i <= 12; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: grab.x, y: grab.y + i * 22 }] });
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await settle(page, 500);
  const order1 = await page.evaluate(() => window.Store.liveTodos().slice().sort((a, b) => a.sortOrder - b.sortOrder).map((t) => t.id).join(','));
  assert(order0 !== order1, 'a real touch reorder must change the order');
  assert(errors.length === 0, 'touch path errors: ' + errors.slice(0, 2).join(' | '));
  await ctx.close();
});

/* P2-4 — a refused clipboard write is not reported as copied */
scenario('R8-6 a refused clipboard write says so', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: () => Promise.reject(new Error('denied')) },
    });
  });
  await go(page, 'feedback');
  await page.fill('[data-testid="feedback-text"]', '无法复制的内容');
  await clickTestId(page, 'feedback-copy');
  await settle(page, 260);
  const toast = await page.evaluate(() => (document.querySelector('.toast') || {}).textContent || '');
  assert(!/^已复制$/.test(toast.trim()), 'a refused write must not claim success: ' + toast);
  assert(/失败|failed/i.test(toast), 'the toast must say the copy failed: ' + toast);
  assertNoErrors(page);
  await page.close();
});

/* P3-1 — search labels planned work as scheduled, not 未安排 */
scenario('R8-7 search does not call a planned todo 未安排', async (browser) => {
  const page = await newPage(browser);
  const name = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary.includes('回复客户邮件'));
    return todo.summary;
  });
  await go(page, 'search');
  await page.fill('[data-testid="search-input"]', name);
  await settle(page, 500);
  const label = await page.evaluate((n) => {
    const hit = Array.from(document.querySelectorAll('[data-testid="search-hit-todo"]')).find((x) => x.textContent.includes(n));
    if (!hit) return null;
    const m = hit.querySelector('.m');
    return m ? m.textContent : '';
  }, name);
  assert(label !== null, 'the planned todo should be found');
  assert(!/未安排/.test(label), 'a planned todo must not be labelled 未安排: ' + label);
  assertNoErrors(page);
  await page.close();
});

/* P3-2 — closing the pane returns focus to its row */
scenario('R8-8 pane close returns focus to the row', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => {
    const row = document.querySelector('.todo-row');
    row.focus();
  });
  const id = await page.evaluate(() => document.activeElement.dataset.id);
  await page.keyboard.press('Enter');
  await settle(page, 260);
  await clickTestId(page, 'pane-close');
  await settle(page, 240);
  const focus = await page.evaluate(() => ({ testid: document.activeElement.dataset.testid, id: document.activeElement.dataset.id }));
  assertEq(focus, { testid: 'todo-row', id }, 'closing the pane must return focus to the row');
  assertNoErrors(page);
  await page.close();
});

/* P3-3 — hiding completed on an all-done day shows an empty state */
scenario('R8-9 hiding completed on an all-done day shows an empty state', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const info = await page.evaluate(() => {
    // Isolate the day: the seed's repeating series matches every day, so it has
    // to be removed for this to be a day whose only item is a completed one.
    window.Store.state.todos.filter((t) => t.recurrence).forEach((t) => window.Store.purgeTodo(t.id));
    window.Store.state.hideCompleted = true;
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 12);
    const todo = window.Store.createTodo({ summary: '当天已完成的唯一事项', dueDate: d });
    window.Store.completeTodo(todo.id);
    window.__todoHelpers.setView({ kind: 'day', day: d });
    return { day: d.toDateString() };
  });
  await settle(page, 300);
  const list = await page.textContent('[data-testid="todo-list"]');
  assert(list.trim().length > 0, 'the list must say something, got an empty surface');
  assert(/没有|Nothing|No /.test(list), 'a day whose only item is hidden needs an empty state: ' + list.slice(0, 80));
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
  console.log(`\n${passed}/${scenarios.length} round-8 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.err.message.split('\n')[0]));
    process.exit(1);
  }
})();
