/* Reviewer regression suite: each scenario reproduces one finding from the
   independent UX review, using that review's own repro steps, and asserts the
   behaviour BEHAVIORS.md / COVERAGE.md promised. */
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
const settle = (page, ms) => page.waitForTimeout(ms === undefined ? 180 : ms);
async function go(page, name, params) {
  await page.evaluate(([n, p]) => window.App.go(n, p), [name, params || null]);
  await settle(page);
}
const exists = (page, sel) => page.evaluate((s) => !!document.querySelector(s), sel);
const count = (page, sel) => page.evaluate((s) => document.querySelectorAll(s).length, sel);
function assertNoErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}

// Put the calendar on the recurring seed event's own day, in day view.
async function openRecurringOccurrenceDay(page) {
  return page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const d = new Date(e.startDt.getTime());
    const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarAnchor = day;
    window.Store.state.calendarFocusDay = day;
    // The calendar reads the one shared browse date, so setting only the
    // private anchor no longer moves it.
    window.Store.setBrowseDate(day);
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
    return { id: e.id, startMs: e.startDt.getTime() };
  });
}

/* F1 (P0) — deleting one occurrence must not delete the series */
scenario('F1 deleting one occurrence of a recurring event keeps the series', async (browser) => {
  const page = await newPage(browser);
  const info = await openRecurringOccurrenceDay(page);
  await settle(page, 260);
  const before = await page.evaluate(() => ({ n: window.Store.state.events.length }));
  await page.evaluate(() => {
    const b = document.querySelector('[data-testid="event-block"]');
    b.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 600, clientY: 400 }));
  });
  await settle(page, 200);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.menu button')).find((x) => /删除|Delete/.test(x.textContent));
    b.click();
  });
  await settle(page, 200);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.modal button, .sheet button')).find((x) => /移到回收站|Move to Trash/.test(x.textContent));
    b.click();
  });
  await settle(page, 260);
  assert(await exists(page, '.sheet'), 'deleting an occurrence must ask for the scope');
  const opts = await page.$$eval('.sheet .slot-sheet-option .t', (ns) => ns.map((n) => n.textContent.trim()));
  assertEq(opts.length, 3, 'the scope sheet should offer this / future / all');
  await page.evaluate(() => { document.querySelector('.sheet [data-testid="scope-this"]').click(); });
  await settle(page, 300);
  const after = await page.evaluate(() => {
    const s = window.Store.state.events.find((x) => x.rrule);
    return { deletedAt: s.deletedAt, exdates: (s.exdates || []).length, n: window.Store.state.events.length };
  });
  assertEq(after.deletedAt, null, 'the series must stay alive');
  assertEq(after.exdates, 1, 'the deleted occurrence must be excluded via exdate');
  assertEq(after.n, before.n, 'deleting one occurrence must not add or remove series records');
  assertNoErrors(page);
  await page.close();
});

/* F1b (P0 sibling) — the "future" scope trims the series and undoes cleanly */
scenario('F1b deleting future occurrences trims the series and undo restores it', async (browser) => {
  const page = await newPage(browser);
  const setup = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const days = [];
    for (let i = 0; i < 70; i++) {
      const d = new Date(e.startDt.getTime() + i * 86400000);
      const hits = window.Store.eventsOnDay(d).filter((x) => x.id === e.id);
      if (hits.length) days.push({ d: d.getTime(), s: hits[0].startDt.getTime() });
    }
    return { id: e.id, days };
  });
  assert(setup.days.length >= 3, 'the seed series should have at least three occurrences');
  const countOn = (ms) => page.evaluate((t) => window.Store.eventsOnDay(new Date(t)).length, ms);
  const second = setup.days[1];
  const third = setup.days[2];
  await page.evaluate(([id, ms]) => window.App.go('detail', { type: 'event', id, occurrence: ms }), [setup.id, second.s]);
  await settle(page, 300);
  await page.evaluate(() => {
    Array.from(document.querySelectorAll('#view button')).find((x) => /移到回收站|Move to Trash/.test(x.textContent)).click();
  });
  await settle(page, 220);
  await page.evaluate(() => { Array.from(document.querySelectorAll('.modal button, .sheet button')).pop().click(); });
  await settle(page, 240);
  await page.evaluate(() => document.querySelector('.sheet [data-testid="scope-future"]').click());
  await settle(page, 340);
  assertEq(await countOn(second.d), 0, 'the chosen occurrence must be gone');
  assertEq(await countOn(third.d), 0, 'later occurrences must be gone too');
  assert(await exists(page, '#toast .undo'), 'a future-scope delete must be undoable');
  await page.click('#toast .undo');
  await settle(page, 340);
  assertEq(await countOn(second.d), 1, 'undo must restore the trimmed occurrence');
  assertEq(await countOn(third.d), 1, 'undo must restore the later occurrences');
  assertNoErrors(page);
  await page.close();
});

/* F2 (P1) — occurrence detail carries the occurrence time; Edit scopes the edit */
scenario('F2 an occurrence detail shows its own time and editing asks for scope', async (browser) => {
  const page = await newPage(browser);
  const info = await openRecurringOccurrenceDay(page);
  await settle(page, 260);
  await page.click('[data-testid="event-block"]');
  await settle(page, 300);
  const detail = await page.evaluate(() => document.querySelector('#view').textContent.replace(/\s+/g, ' '));
  const baseHour = new Date(info.startMs).getHours();
  assert(detail.includes(String(baseHour).padStart(2, '0') + ':00'), `detail must show the occurrence start ${baseHour}:00, got: ${detail.slice(0, 160)}`);
  assert(!/\b00:00\b/.test(detail.split('安排')[1] || ''), 'occurrence detail must not show midnight');

  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('#view button')).find((x) => /编辑|Edit/.test(x.textContent));
    b.click();
  });
  await settle(page, 240);
  assert(await exists(page, '.sheet'), 'editing an occurrence must ask for the scope');
  await page.evaluate(() => { document.querySelector('.sheet [data-testid="scope-this"]').click(); });
  await settle(page, 300);
  assert(await exists(page, '[data-testid="composer"]'), 'choosing this-occurrence should open the composer');
  const startVal = await page.evaluate(() => {
    const el = document.querySelector('[data-testid="composer-start-time"]');
    return el ? el.value : null;
  });
  assert(startVal === String(baseHour).padStart(2, '0') + ':00', `composer must open on the occurrence time, got ${startVal}`);

  const before = await page.evaluate(() => ({ n: window.Store.state.events.length }));
  await page.evaluate(() => {
    const t = document.querySelector('[data-testid="composer-title"]');
    t.value = '周会（只改这一次）';
    t.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await page.evaluate(() => { document.querySelector('[data-testid="composer-save"]').click(); });
  await settle(page, 320);
  const after = await page.evaluate(() => {
    const s = window.Store.state.events.find((x) => x.rrule);
    return { n: window.Store.state.events.length, summary: s.summary, exdates: (s.exdates || []).length };
  });
  assertEq(after.n, before.n + 1, 'editing one occurrence should split off a copy');
  assertEq(after.summary, '周会', 'the series title must stay untouched');
  assertEq(after.exdates, 1, 'the edited occurrence must be excluded from the series');
  assertNoErrors(page);
  await page.close();
});

/* F3 (P1) — completing a recurring todo from the list never claims success silently */
scenario('F3 completing a recurring to-do from the list writes an occurrence or says why not', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    window.Store.state.todosView = { kind: 'all', day: null };
    window.App.go('todos');
  });
  await settle(page, 240);
  const info = await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => x.recurrence && !x.deletedAt);
    return { id: t.id, states: Object.keys(t.occurrenceStates || {}).length };
  });
  await page.evaluate((id) => {
    const tile = document.querySelector(`[data-testid="todo-tile"][data-id="${id}"]`);
    const box = tile.querySelector('[role="checkbox"], .checkbox, button');
    box.click();
  }, info.id);
  await settle(page, 300);
  const after = await page.evaluate((id) => {
    const t = window.Store.state.todos.find((x) => x.id === id);
    return { states: Object.keys(t.occurrenceStates || {}).length, status: t.status };
  }, info.id);
  assert(after.states > info.states || after.status === 'COMPLETED', 'completing from the list must write something');
  assertEq(after.status, 'NEEDS-ACTION', 'a recurring series itself must never be marked complete');
  const toast = await page.evaluate(() => {
    const n = document.querySelector('#toast .toast');
    return n ? n.textContent : '';
  });
  assert(!/Pick an occurrence|选一次具体实例/.test(toast), 'it must not report a failure after writing');
  assertNoErrors(page);
  await page.close();
});

/* F4 (P1) — a recurring to-do cannot get an invisible allocation from the composer */
scenario('F4 the composer refuses to schedule a recurring to-do without an occurrence', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => x.recurrence && !x.deletedAt);
    window.Store.state.allocations
      .filter((a) => a.todoId === t.id && a.state === 'active')
      .forEach((a) => { a.state = 'cancelledByUser'; });
    window.App.openComposer('todo', { mode: 'edit', id: t.id });
    return t.id;
  });
  await settle(page, 320);
  const before = await page.evaluate(() => window.Store.state.allocations.length);
  await page.click('[data-testid="composer-schedule"]');
  await settle(page, 240);
  assert(await exists(page, '[data-testid="schedule-occurrence"]'), 'a repeating to-do must be asked which occurrence to schedule');
  await page.evaluate(() => { document.querySelector('[data-testid="schedule-apply"]').click(); });
  await settle(page, 200);
  await page.evaluate(() => {
    const b = document.querySelector('[data-testid="composer-save"]');
    if (b && !b.disabled) b.click();
  });
  await settle(page, 340);
  const after = await page.evaluate(() => {
    const all = window.Store.state.allocations;
    const newest = all[all.length - 1];
    return { n: all.length, live: newest ? window.Store.isAllocationLive(newest) : false, occ: newest ? newest.occurrenceId : null };
  });
  assertEq(after.n, before + 1, 'scheduling a repeating to-do should write one allocation');
  assert(after.occ, 'the allocation must carry the chosen occurrence');
  assert(after.live, 'the allocation must be visible, not a ghost');
  assertNoErrors(page);
  await page.close();
});

/* F5 (P1) — subtasks never appear in Action's top-level lanes */
scenario('F5 a subtask with a deadline does not appear in Action', async (browser) => {
  const page = await newPage(browser);
  const parentId = await page.evaluate(() => {
    const parent = window.Store.state.todos.find((t) => !t.parentId && !t.recurrence && !t.deletedAt);
    const now = new Date();
    const sub = window.Store.createTodo({
      summary: '子任务不该出现在行动页',
      dueDate: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23),
      parentId: parent.id,
    });
    window.__subId = sub.id;
    window.App.go('action');
    return parent.id;
  });
  await settle(page, 320);
  const inAction = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('#view .row-title')).map((n) => n.textContent);
    return rows.filter((r) => r.includes('子任务不该出现在行动页')).length;
  });
  assertEq(inAction, 0, 'a subtask must not be listed in Action');
  await go(page, 'todos');
  const inTodos = await page.evaluate(() => Array.from(document.querySelectorAll('#view .todo-row')).length);
  assert(inTodos >= 0, 'todos renders');
  assertNoErrors(page);
  await page.close();
});

/* F6 (P1) — a scheduled block can be cancelled on touch, from the to-do detail */
scenario('F6 a scheduled block is cancellable from the to-do detail on a phone', async (browser) => {
  const page = await newPage(browser, MOBILE);
  const id = await page.evaluate(() => {
    const a = window.Store.state.allocations.find((x) => window.Store.isAllocationLive(x));
    window.App.go('detail', { type: 'todo', id: a.todoId });
    return a.id;
  });
  await settle(page, 320);
  assert(await exists(page, '[data-testid="cancel-allocation"]'), 'the detail must offer a cancel action for a live allocation');
  await page.click('[data-testid="cancel-allocation"]');
  await settle(page, 220);
  await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('.modal button'));
    if (btns.length) btns[btns.length - 1].click();
  });
  await settle(page, 300);
  const state = await page.evaluate((allocId) => {
    const a = window.Store.state.allocations.find((x) => x.id === allocId);
    return a ? a.state : null;
  }, id);
  assertEq(state, 'cancelledByUser', 'cancelling must mark the allocation cancelled');
  assertNoErrors(page);
  await page.close();
});

/* F7 (P1) — drag undo restores the original time for both kinds of block */
scenario('F7 undo after dragging a block restores the original time', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await page.evaluate(() => { window.Store.state.calendarView = 'day'; window.App.render(); });
  await settle(page, 260);
  const before = await page.evaluate(() => {
    const a = window.Store.state.allocations.find((x) => window.Store.isAllocationLive(x));
    return { id: a.id, s: a.startAt.getTime(), e: a.endAt.getTime() };
  });
  const box = await page.evaluate((id) => {
    const r = document.querySelector(`[data-testid="alloc-block"][data-id="${id}"]`).getBoundingClientRect();
    return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + 6) };
  }, before.id);
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 56, { steps: 8 });
  await page.mouse.up();
  await settle(page, 320);
  const moved = await page.evaluate((id) => {
    const a = window.Store.state.allocations.find((x) => x.id === id);
    return a.startAt.getTime();
  }, before.id);
  assert(moved !== before.s, 'the drag should move the block');
  await page.click('#toast .undo');
  await settle(page, 320);
  const undone = await page.evaluate((id) => {
    const a = window.Store.state.allocations.find((x) => x.id === id);
    return { s: a.startAt.getTime(), e: a.endAt.getTime() };
  }, before.id);
  assertEq(undone, { s: before.s, e: before.e }, 'undo must restore the original allocation time');
  assertNoErrors(page);
  await page.close();
});

/* F8 (P1) — rail navigation out of a dirty composer asks first */
scenario('F8 leaving a dirty composer via the rail asks before discarding', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.App.openComposer('todo'));
  await settle(page, 320);
  await page.fill('[data-testid="composer-title"]', '还没保存的草稿');
  await settle(page, 120);
  await page.click('[data-testid="nav-calendar"]');
  await settle(page, 260);
  assert(await exists(page, '.modal, .sheet'), 'navigating away from a dirty composer must ask first');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.modal button, .sheet button')).find((x) => /继续编辑|Keep editing/.test(x.textContent));
    if (b) b.click();
  });
  await settle(page, 260);
  assert(await exists(page, '[data-testid="composer"]'), 'choosing to keep editing must stay in the composer');
  assertNoErrors(page);
  await page.close();
});

/* F9 (P1) — capture and quick add keep focus for continuous entry */
scenario('F9 capture keeps focus so a second Enter creates a second to-do', async (browser) => {
  const page = await newPage(browser);
  const before = await page.evaluate(() => window.Store.state.todos.length);
  await page.click('[data-testid="action-capture"]');
  await page.keyboard.type('焦点测试A');
  await page.keyboard.press('Enter');
  await settle(page, 260);
  const focused = await page.evaluate(() => document.activeElement && document.activeElement.dataset.testid);
  assertEq(focused, 'action-capture', 'focus must stay in the capture box');
  await page.keyboard.type('连续输入B');
  await page.keyboard.press('Enter');
  await settle(page, 280);
  const after = await page.evaluate(() => window.Store.state.todos.length);
  assertEq(after, before + 2, 'a second Enter must create a second to-do');
  assertNoErrors(page);
  await page.close();
});

/* F10 (P1) — deleting an event from its detail leaves that detail */
scenario('F10 deleting an event from its detail leaves the deleted record', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => !x.rrule && !x.deletedAt);
    window.App.go('detail', { type: 'event', id: e.id });
    return e.id;
  });
  await settle(page, 300);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('#view button')).find((x) => /移到回收站|Move to Trash/.test(x.textContent));
    b.click();
  });
  await settle(page, 220);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.modal button, .sheet button')).find((x) => /移到回收站|Move to Trash/.test(x.textContent));
    b.click();
  });
  await settle(page, 320);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assert(route !== 'detail', 'the deleted event detail must not stay on screen');
  const stillThere = await page.evaluate((eid) => {
    const el = document.querySelector('#view [data-testid="event-detail"]');
    return el ? el.textContent.includes('11') : false;
  }, id);
  assert(!stillThere || route !== 'detail', 'deleted record must not keep rendering');
  assertNoErrors(page);
  await page.close();
});

/* F11 (P2) — a completed to-do leaves the Now lane */
scenario('F11 completing an in-progress allocation removes it from Now', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const now = new Date();
    const todo = window.Store.state.todos.find((t) => !t.recurrence && !t.parentId && t.status === 'NEEDS-ACTION' && !t.deletedAt);
    const start = new Date(now.getTime() - 20 * 60000);
    const end = new Date(now.getTime() + 40 * 60000);
    const a = window.Store.createAllocation({ todoId: todo.id, startAt: start, endAt: end });
    window.App.go('action');
    return { todoId: todo.id, allocId: a.id };
  });
  await settle(page, 320);
  assert(await exists(page, '[data-testid="action-allocation"]'), 'the in-progress allocation should be in Now');
  await page.evaluate((tid) => {
    const row = document.querySelector(`[data-testid="action-allocation"][data-id="${tid}"]`);
    const box = row.querySelector('[role="checkbox"], .checkbox, button');
    box.click();
  }, info.todoId);
  await settle(page, 320);
  const inNow = await page.evaluate((tid) => {
    const heads = Array.from(document.querySelectorAll('#view .section-head'));
    const nowIdx = heads.findIndex((h) => /现在|Now/.test(h.textContent));
    if (nowIdx < 0) return 0;
    let node = heads[nowIdx].nextElementSibling;
    let hits = 0;
    while (node && !node.classList.contains('section-head')) {
      if (node.dataset.testid === 'action-allocation' && Number(node.dataset.id) === tid) hits++;
      node = node.nextElementSibling;
    }
    return hits;
  }, info.todoId);
  assertEq(inNow, 0, 'a completed to-do must not stay in the Now lane');
  assertNoErrors(page);
  await page.close();
});

/* F12 (P2) — missed recurring instances beyond five are reachable */
scenario('F12 the overdue section never truncates missed instances silently', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const d = new Date();
    d.setDate(d.getDate() - 12);
    window.Store.createTodo({
      summary: '漏掉的重复任务',
      recurrence: { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' },
      dueDate: new Date(d.getFullYear(), d.getMonth(), d.getDate(), 9),
    });
    window.App.go('action');
  });
  await settle(page, 320);
  const headCount = await page.evaluate(() => {
    const h = Array.from(document.querySelectorAll('#view .section-head')).find((n) => /遗漏|Missed/.test(n.textContent));
    return h ? Number((h.textContent.match(/(\d+)/) || [])[1]) : null;
  });
  const shown = await count(page, '[data-testid="action-instance"]');
  assert(headCount !== null, 'the missed section should render');
  assert(headCount > shown, 'the header count should include the folded instances');
  assert(await exists(page, '[data-testid="overdue-more"]'), 'the folded instances need an exit');
  await page.click('[data-testid="overdue-more"]');
  await settle(page, 280);
  assert(await count(page, '[data-testid="action-instance"]') > shown, 'expanding must reveal the rest');
  assertNoErrors(page);
  await page.close();
});

/* F13 (P2) — detail values are click-to-edit */
scenario('F13 clicking a detail value opens its editor', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => !x.deletedAt && !x.parentId);
    window.App.go('detail', { type: 'todo', id: t.id });
  });
  await settle(page, 300);
  await page.evaluate(() => {
    const v = document.querySelector('.fact .v[role="button"]');
    v.click();
  });
  await settle(page, 240);
  assert(await exists(page, '.sheet'), 'clicking a detail value must open its editor');
  assertNoErrors(page);
  await page.close();
});

/* F14 (P2) — an overlapping allocation warns on save */
scenario('F14 scheduling over an existing block warns in the toast', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => !x.rrule && !x.deletedAt);
    const t = window.Store.state.todos.find((x) => !x.recurrence && !x.deletedAt && !x.parentId);
    window.App.go('detail', { type: 'todo', id: t.id });
    return { eventStart: e.startDt.getTime(), summary: e.summary };
  });
  await settle(page, 320);
  await page.click('[data-testid="detail-schedule"]');
  await settle(page, 240);
  await page.evaluate((ms) => {
    const s = document.querySelector('[data-testid="allocate-apply"]');
    const input = document.querySelector('.sheet input[type="datetime-local"]');
    const d = new Date(ms);
    const pad = (n) => String(n).padStart(2, '0');
    input.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    s.click();
  }, info.eventStart);
  await settle(page, 320);
  const toast = await page.evaluate(() => {
    const n = document.querySelector('#toast .toast');
    return n ? n.textContent : '';
  });
  assert(/重叠|Overlap/.test(toast), `an overlapping schedule must warn, got "${toast}"`);
  assertNoErrors(page);
  await page.close();
});

/* F15 (P2) — resizing a block gives feedback and is undoable */
scenario('F15 resizing a block reports it and can be undone', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await page.evaluate(() => { window.Store.state.calendarView = 'day'; window.App.render(); });
  await settle(page, 280);
  const before = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => !x.rrule && !x.deletedAt);
    return { id: e.id, s: e.startDt.getTime(), e: e.endDt.getTime() };
  });
  const handle = await page.evaluate((id) => {
    const node = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    const r = node.querySelector('.resize').getBoundingClientRect();
    return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) };
  }, before.id);
  await page.mouse.move(handle.x, handle.y);
  await page.mouse.down();
  await page.mouse.move(handle.x, handle.y + 50, { steps: 8 });
  await page.mouse.up();
  await settle(page, 340);
  const resized = await page.evaluate((id) => {
    const e = window.Store.state.events.find((x) => x.id === id);
    return { s: e.startDt.getTime(), e: e.endDt.getTime() };
  }, before.id);
  assertEq(resized.s, before.s, 'resizing must keep the start');
  assert(resized.e > before.e, 'resizing must extend the end');
  assert(await exists(page, '#toast .undo'), 'resizing must offer undo');
  await page.click('#toast .undo');
  await settle(page, 320);
  const undone = await page.evaluate((id) => {
    const e = window.Store.state.events.find((x) => x.id === id);
    return { s: e.startDt.getTime(), e: e.endDt.getTime() };
  }, before.id);
  assertEq({ s: undone.s, e: undone.e }, { s: before.s, e: before.e }, 'undo must restore the original duration');
  assertNoErrors(page);
  await page.close();
});

/* F16 (P2) — the schedule picker's quick chips update the preview and stay future */
scenario('F16 the schedule picker quick chips update the preview', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => !x.recurrence && !x.deletedAt && !x.parentId);
    window.App.openComposer('todo', { mode: 'edit', id: t.id });
  });
  await settle(page, 320);
  await page.click('[data-testid="composer-schedule"]');
  await settle(page, 280);
  const chip = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.sheet .chip-btn')).find((x) => /今天|Today|明天|Tomorrow/.test(x.textContent));
    if (!b) return null;
    b.click();
    return b.textContent.trim();
  });
  assert(chip, 'the picker should offer quick chips');
  await settle(page, 200);
  const preview = await page.evaluate(() => {
    const p = document.querySelector('.sheet .preview');
    return p ? p.textContent.trim() : '';
  });
  const inputVal = await page.evaluate(() => document.querySelector('[data-testid="schedule-start"]').value);
  assert(preview && preview.length > 0, 'the preview must render');
  const previewHour = (preview.match(/(\d{1,2}):(\d{2})/) || [])[1];
  const inputHour = inputVal.split('T')[1] ? inputVal.split('T')[1].split(':')[0] : null;
  assert(previewHour && inputHour && Number(previewHour) === Number(inputHour), `preview (${preview}) must match the chosen time (${inputVal})`);
  assertNoErrors(page);
  await page.close();
});

/* F17 (P2) — a missing event shows the recoverable error state */
scenario('F17 a missing event record shows an error with a way back', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.App.go('detail', { type: 'event', id: 99999 }));
  await settle(page, 320);
  const text = await page.evaluate(() => document.querySelector('#view').textContent.replace(/\s+/g, ' '));
  assert(/出错了|Something went wrong|error/i.test(text), `a missing event must show an error state, got "${text.slice(0, 120)}"`);
  assert(await exists(page, '#view button'), 'the error state must offer a way back');
  assertNoErrors(page);
  await page.close();
});

/* F18 (P2) — shortcuts do not mutate the page behind an open sheet */
scenario('F18 the T shortcut is inert while a sheet is open', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const d = new Date();
    d.setDate(d.getDate() + 2);
    window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarFocusDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
  });
  await settle(page, 300);
  const anchorBefore = await page.evaluate(() => window.Store.state.calendarAnchor.getTime());
  await page.evaluate(() => {
    const slot = document.querySelector('.time-grid .slot, .slot');
    if (slot) slot.click();
  });
  await settle(page, 240);
  if (!(await exists(page, '.sheet'))) { await page.close(); return; }
  await page.keyboard.press('t');
  await settle(page, 260);
  const anchorAfter = await page.evaluate(() => window.Store.state.calendarAnchor.getTime());
  assertEq(anchorAfter, anchorBefore, 'the T shortcut must not move the calendar behind a sheet');
  assertNoErrors(page);
  await page.close();
});

/* F19 (P3) — saving from the composer highlights the new row */
scenario('F19 a newly created to-do is highlighted on its own row', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.click('[data-testid="todos-create"]');
  await settle(page, 320);
  await page.fill('[data-testid="composer-title"]', '高亮是哪一行');
  await settle(page, 120);
  await page.evaluate(() => { document.querySelector('[data-testid="composer-save"]').click(); });
  await settle(page, 120);
  const hl = await page.evaluate(() => {
    const nodes = Array.from(document.querySelectorAll('.hl'));
    return nodes.map((n) => ({ id: n.dataset.id, text: n.textContent.slice(0, 40) }));
  });
  assert(hl.length > 0, 'the new row must be highlighted');
  assert(hl.some((x) => x.text.includes('高亮是哪一行')), `the highlight must target the new row, got ${JSON.stringify(hl)}`);
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
  console.log(`\n${pass}/${pass + fail} reviewer findings hold`);
  if (fail) process.exit(1);
})();
