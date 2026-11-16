/* Round-7 independent reviewer regression suite. */
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

/* P1-1 — a 40-minute allocation can be re-applied without corruption */
scenario('R7-1 an unlisted duration is preserved and saved', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const info = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary.includes('回复客户邮件'));
    const alloc = window.Store.allocationsForTodo(todo.id).find((a) => a.state === window.Store.ALLOC.ACTIVE);
    window.App.openRecord('todo', todo.id);
    return { id: todo.id, a: alloc.id };
  });
  await settle(page, 260);
  await clickTestId(page, 'detail-edit');
  await settle(page, 220);
  await clickTestId(page, 'composer-schedule');
  const dur = await page.evaluate(() => {
    const sel = document.querySelector('.sheet select');
    return { value: sel.value, options: Array.from(sel.options).map((o) => o.value) };
  });
  assertEq(dur.value, '40', 'the existing 40-minute duration must be selected');
  assert(dur.options.includes('40'), '40 must be an option: ' + dur.options.join(','));
  await clickTestId(page, 'schedule-apply');
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 300);
  const after = await page.evaluate((a) => {
    const x = window.Store.state.allocations.find((y) => y.id === a);
    const s = new Date(x.startAt.__date !== undefined ? x.startAt.__date : x.startAt);
    const e = new Date(x.endAt.__date !== undefined ? x.endAt.__date : x.endAt);
    return { valid: !Number.isNaN(e.getTime()), minutes: Math.round((e - s) / 60000) };
  }, info.a);
  assert(after.valid, 'the saved end must be a valid date');
  assertEq(after.minutes, 40, 'the saved duration must stay 40 minutes');
  assertNoErrors(page);
  await page.close();
});

/* P1-2 — discarding an all-day toggle leaves the event untouched */
scenario('R7-2 cancelling an all-day edit does not mutate the stored event', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
    const s = new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt);
    const en = new Date(e.endDt.__date !== undefined ? e.endDt.__date : e.endDt);
    window.App.openComposer('event', { mode: 'edit', id: e.id });
    return { id: e.id, before: { sh: s.getHours(), sm: s.getMinutes(), eh: en.getHours(), em: en.getMinutes(), allDay: e.isAllDay } };
  });
  await settle(page, 260);
  await clickTestId(page, 'composer-allday-on');
  await clickTestId(page, 'composer-close');
  await clickText(page, '.modal-foot button', '放弃');
  await settle(page, 260);
  const after = await page.evaluate((id) => {
    const e = window.Store.eventById(id);
    const s = new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt);
    const en = new Date(e.endDt.__date !== undefined ? e.endDt.__date : e.endDt);
    return { sh: s.getHours(), sm: s.getMinutes(), eh: en.getHours(), em: en.getMinutes(), allDay: e.isAllDay };
  }, info.id);
  assertEq(after, info.before, 'discarding must not touch the event');
  assertNoErrors(page);
  await page.close();
});

/* P1-3 — opening on To-dos initializes the desktop tab */
scenario('R7-3 default To-dos boot opens rows into the master-detail pane', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const raw = JSON.parse(localStorage.getItem('dayspark.g0.prefs') || '{}');
    raw.defaultTab = 'todos';
    localStorage.setItem('dayspark.g0.prefs', JSON.stringify(raw));
  });
  await page.reload();
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  await settle(page, 220);
  assertEq(await page.evaluate(() => window.Store.state.tab), 'todos', 'the tab must start on todos');
  const railOn = await page.evaluate(() => document.querySelector('[data-testid="nav-todos"]').getAttribute('aria-current'));
  assertEq(railOn, 'page', 'the rail must mark To-dos');
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 240);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'a row click must open the pane');
  assertNoErrors(page);
  await page.close();
});

/* P1-4 — one Back after saving a split occurrence returns to the origin */
scenario('R7-4 saving a split occurrence does not leave a stale detail in Back', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const series = window.Store.state.events.find((x) => x.summary === '周会');
    const day = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    window.App.go('calendar');
    const occ = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 10, 0).getTime();
    window.App.openRecord('event', series.id, occ);
    return { id: series.id };
  });
  await settle(page, 280);
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
  await page.fill('[data-testid="composer-title"]', '周会（单次改名）');
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 320);
  await page.evaluate(() => window.App.back());
  await settle(page, 280);
  assertEq(await page.evaluate(() => window.Store.state.route.name), 'calendar', 'one Back must return to the calendar');
  assertNoErrors(page);
  await page.close();
});

/* P1-5 — scroll is per destination */
scenario('R7-5 scroll belongs to the destination, not the window', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 240);
  const top = await page.evaluate(() => {
    const sc = Array.from(document.querySelectorAll('#view *')).filter((n) => n.scrollHeight > n.clientHeight + 20)
      .sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
    sc.scrollTop = Math.min(500, sc.scrollHeight - sc.clientHeight - 4);
    return sc.scrollTop;
  });
  assert(top > 300, 'the list must scroll first');
  await go(page, 'action');
  const todayTop = await page.evaluate(() => {
    const sc = Array.from(document.querySelectorAll('#view *')).filter((n) => n.scrollHeight > n.clientHeight + 20)
      .sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
    return sc.scrollTop;
  });
  assertEq(todayTop, 0, 'Today must open at its own top');
  await go(page, 'todos');
  const restored = await page.evaluate(() => {
    const sc = Array.from(document.querySelectorAll('#view *')).filter((n) => n.scrollHeight > n.clientHeight + 20)
      .sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
    return sc.scrollTop;
  });
  assert(restored > 300, 'returning to Todos must restore its scroll, got ' + restored);
  assertNoErrors(page);
  await page.close();
});

/* P1-6 — a cancelled reorder changes nothing */
scenario('R7-6 pointercancel aborts a Todo reorder', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'todos');
  // A manual order exists only in the inventory list; day views group by date.
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 240);
  const before = await page.evaluate(() => window.Store.liveTodos().slice().sort((a, b) => a.sortOrder - b.sortOrder).map((x) => x.id).join(','));
  const box = await page.evaluate(() => {
    const row = document.querySelector('.todo-row');
    const grab = row.querySelector('.grab').getBoundingClientRect();
    return { x: grab.left + grab.width / 2, y: grab.top + grab.height / 2 };
  });
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 60, { steps: 5 });
  await page.evaluate(() => {
    document.dispatchEvent(new PointerEvent('pointercancel', { bubbles: true }));
  });
  await page.mouse.up();
  await settle(page, 300);
  const after = await page.evaluate(() => window.Store.liveTodos().slice().sort((a, b) => a.sortOrder - b.sortOrder).map((x) => x.id).join(','));
  assertEq(after, before, 'a cancelled reorder must keep the order');
  assert(!(await exists(page, '.toast')), 'a cancelled reorder must not report success');
  assertNoErrors(page);
  await page.close();
});

/* P2-2 — a completed occurrence detail reads completed */
scenario('R7-10 a completed occurrence detail offers reopen, not mark complete', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    const day = window.U.startOfDay(window.U.now());
    const occ = window.Store.occurrenceIdFor(todo, day);
    window.Store.completeTodo(todo.id, { occurrenceId: occ });
    window.App.openRecord('todo', todo.id, null, day.getTime());
    return { id: todo.id, occ };
  });
  await settle(page, 280);
  const label = await page.textContent('[data-testid="detail-complete"]');
  assert(/撤销|取消完成|重新打开|Reopen|Undo/.test(label), 'a completed occurrence must offer reopen: ' + label);
  await clickTestId(page, 'detail-complete');
  await settle(page, 260);
  const open = await page.evaluate(([id, occ]) => !window.Store.isOccurrenceDone(window.Store.todoById(id), occ), [info.id, info.occ]);
  assert(open, 'clicking the control must reopen the occurrence');
  assertNoErrors(page);
  await page.close();
});

/* P2-3 — focus returns to the row after closing the pane */
scenario('R7-11 row focus survives opening and closing the pane', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => {
    const row = document.querySelector('.todo-row');
    row.focus();
  });
  const id = await page.evaluate(() => document.activeElement.dataset.id);
  await page.keyboard.press('Enter');
  await settle(page, 260);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'Enter should open the pane');
  await page.keyboard.press('Escape');
  await settle(page, 280);
  const focus = await page.evaluate(() => ({ testid: document.activeElement.dataset.testid, id: document.activeElement.dataset.id }));
  assertEq(focus, { testid: 'todo-row', id }, 'focus must return to the same row');
  assertNoErrors(page);
  await page.close();
});

/* P2-4 — saving a subtask does not leave the composer in Back */
scenario('R7-12 saving a subtask returns to the parent detail with no blank composer in Back', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const parent = window.Store.liveTodos().find((x) => x.summary === '准备季度评审');
    window.App.go('todos');
    window.App.openRecord('todo', parent.id);
    return { id: parent.id };
  });
  await settle(page, 280);
  await page.evaluate((id) => window.App.openComposer('todo', { parentId: id }), info.id);
  await settle(page, 240);
  await page.fill('[data-testid="composer-title"]', '新的子任务');
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 280);
  await page.evaluate(() => window.App.back());
  await settle(page, 260);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assert(route !== 'composer', 'Back must not land on an empty new-todo composer');
  assertNoErrors(page);
  await page.close();
});

/* P2-5 — logged-in sync still names the server */
scenario('R7-13 logged-in sync shows the server URL', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    window.Store.state.account = { signedIn: true, email: 'chang@example.com', server: 'https://nas.local:8080', lastSync: window.U.now(), phase: 'idle', rejected: [] };
    window.App.go('settings', { section: 'account' });
  });
  await settle(page, 260);
  const text = await page.textContent('.settings-pane');
  assert(text.includes('https://nas.local:8080'), 'the logged-in sync section must show the server URL');
  assertNoErrors(page);
  await page.close();
});

/* P2-6 — the capture shortcut opens the deadline picker */
scenario('R7-14 the add-deadline capture shortcut opens its picker', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await page.fill('[data-testid="action-capture"]', '从捕获加截止');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.capture button')).find((x) => /加截止|Add deadline/.test(x.textContent));
    b.click();
  });
  await settle(page, 300);
  assert(await exists(page, '[data-testid="deadline-apply"]'), 'the deadline picker must open');
  assertNoErrors(page);
  await page.close();
});

/* P2-7 — Today puts unplanned before completed/history */
scenario('R7-15 Today keeps 未安排 before completed sections', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  const order = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.page-content .section-head')).map((n) => n.textContent.trim()));
  const unplanned = order.findIndex((x) => /未安排|Unplanned/.test(x));
  const completed = order.findIndex((x) => /今天完成|Completed today/.test(x));
  const earlier = order.findIndex((x) => /今天早些时候|Earlier today/.test(x));
  assert(unplanned >= 0, 'unplanned section missing: ' + order.join('|'));
  if (completed >= 0) assert(unplanned < completed, '未安排 must precede completed: ' + order.join('|'));
  if (earlier >= 0) assert(unplanned < earlier, '未安排 must precede earlier history: ' + order.join('|'));
  assertNoErrors(page);
  await page.close();
});

/* P2-8 — Settings groups are separators, not cards */
scenario('R7-16 Settings groups are not bordered cards', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'appearance' });
  const style = await page.evaluate(() => {
    const g = document.querySelector('.settings-group');
    const s = getComputedStyle(g);
    return { radius: s.borderTopLeftRadius, left: s.borderLeftWidth, bg: s.backgroundColor };
  });
  assert(style.radius === '0px' && style.left === '0px', 'Settings groups must not be rounded cards: ' + JSON.stringify(style));
  assertNoErrors(page);
  await page.close();
});

/* P3 — quick add keeps its confirmation; AI preview names the schedule */
scenario('R7-17 quick add and AI parse do not contradict what they wrote', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'quickadd');
  await page.fill('[data-testid="quickadd-input"]', '明天下午三点 开会');
  await settle(page, 200);
  await clickTestId(page, 'quickadd-save');
  await settle(page, 300);
  assert(await exists(page, '.toast'), 'saving quick add must leave a confirmation toast');
  const iso = await page.evaluate(() => window.QuickParse.parse('Meeting on 2026-11-20', new Date(2026, 10, 15, 10, 0)).title);
  assert(!/\bon\b/i.test(iso), 'an ISO date must not leave "on" in the title: ' + iso);
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 240);
  await page.fill('[data-testid="composer-title"]', '明天下午三点 评审');
  await clickTestId(page, 'composer-ai-parse');
  await settle(page, 220);
  const kind = await page.evaluate(() => {
    const n = document.querySelector('.sheet .quick-kind');
    return n ? n.textContent.trim() : '';
  });
  assert(/计划执行|Schedule/.test(kind), 'a todo schedule must not be previewed as an event: ' + kind);
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
  console.log(`\n${passed}/${scenarios.length} round-7 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.err.message.split('\n')[0]));
    process.exit(1);
  }
})();
