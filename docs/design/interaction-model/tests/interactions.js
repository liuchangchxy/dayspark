/* Real interaction tests: drive the prototype with a browser the way a person
   would (type, click, drag), then assert the resulting data and the surfaces
   that must agree with it. Every scenario starts from a fresh page.
   Usage: node tests/interactions.js [--headed] [--filter=<substring>] */
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

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}
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

async function go(page, name, params) {
  await page.evaluate(([n, p]) => window.App.go(n, p), [name, params || null]);
  await settle(page);
}
async function settle(page, ms) {
  await page.waitForTimeout(ms === undefined ? 140 : ms);
}
async function state(page) {
  return page.evaluate(() => {
    const clone = (v) => {
      if (v instanceof Date) return { __date: v.getTime() };
      if (Array.isArray(v)) return v.map(clone);
      if (v && typeof v === 'object') {
        const out = {};
        Object.keys(v).forEach((k) => { out[k] = clone(v[k]); });
        return out;
      }
      return v;
    };
    return clone({
      todos: window.Store.state.todos,
      events: window.Store.state.events,
      allocations: window.Store.state.allocations,
      tags: window.Store.state.tags,
      calendars: window.Store.state.calendars,
      route: window.Store.state.route,
      todosView: window.Store.state.todosView,
      actionDate: window.Store.state.actionDate,
      calendarView: window.Store.state.calendarView,
      composer: window.Store.state.composer,
    });
  });
}
function textOf(page, sel) {
  return page.evaluate((s) => {
    const n = document.querySelector(s);
    return n ? n.textContent.trim() : null;
  }, sel);
}
async function toastText(page) {
  return textOf(page, '#toast .toast');
}
async function clickTestId(page, id) {
  await page.click(`[data-testid="${id}"]`);
  await settle(page);
}
async function exists(page, sel) {
  return page.evaluate((s) => !!document.querySelector(s), sel);
}
async function count(page, sel) {
  return page.evaluate((s) => document.querySelectorAll(s).length, sel);
}
async function noOverflow(page) {
  const ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  assert(ov <= 0, `horizontal overflow ${ov}px`);
}
async function noErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}

/* ---------- Action: capture -> inbox ---------- */
scenario('action capture creates an unplanned todo and inbox entry counts it', async (browser) => {
  const page = await newPage(browser);
  // Unplanned means "no effective planned execution", not "no deadline": a
  // to-do with a deadline but no active allocation still belongs here.
  const unplannedOn = () => page.evaluate(() => window.Store.inboxTodos().length);
  const inboxBefore = await unplannedOn();
  assert((await textOf(page, '[data-testid="inbox-entry"]')).includes(String(inboxBefore)), 'inbox entry should show the current unplanned count');

  await page.fill('[data-testid="action-capture"]', '从捕获框新建的待办');
  await page.press('[data-testid="action-capture"]', 'Enter');
  await settle(page, 260);

  const after = await state(page);
  const created = after.todos.find((t) => t.summary === '从捕获框新建的待办');
  assert(created, 'todo was not created');
  assertEq(created.dueDate, null, 'captured todo must have no deadline');
  assertEq(created.status, 'NEEDS-ACTION', 'captured todo status');
  assert((await page.inputValue('[data-testid="action-capture"]')) === '', 'capture field must clear');
  assertEq(await unplannedOn(), inboxBefore + 1, 'the capture must join the unplanned bucket');
  assert((await textOf(page, '[data-testid="inbox-entry"]')).includes(String(inboxBefore + 1)), 'inbox count did not update');

  await clickTestId(page, 'inbox-entry');
  assert((await state(page)).todosView.kind === 'inbox', 'inbox entry must open the inbox view');
  const rowText = await textOf(page, '[data-testid="todo-list"]');
  assert(rowText.includes('从捕获框新建的待办'), 'created todo is missing from the inbox list');
  await noOverflow(page);
  await noErrors(page);
  await page.close();
});

/* ---------- Unplanned excludes to-dos that already have a live allocation ---------- */
scenario('a to-do leaves the unplanned bucket once it is scheduled and returns when cancelled', async (browser) => {
  const page = await newPage(browser);
  const target = await page.evaluate(() => {
    const todo = window.Store.inboxTodos().find((t) => !t.recurrence);
    return todo ? { id: todo.id, summary: todo.summary } : null;
  });
  assert(target, 'seed data should contain an unplanned to-do');
  const before = await page.evaluate(() => window.Store.inboxTodos().length);

  await page.evaluate((id) => {
    const start = new Date();
    start.setHours(start.getHours() + 3, 0, 0, 0);
    window.Store.createAllocation({ todoId: id, startAt: start, endAt: new Date(start.getTime() + 3600000) });
    window.App.render();
  }, target.id);
  await settle(page, 240);
  const scheduled = await page.evaluate(() => window.Store.inboxTodos().length);
  assertEq(scheduled, before - 1, 'a scheduled to-do must leave Unplanned even though its deadline is untouched');

  await page.evaluate((id) => {
    const alloc = window.Store.state.allocations.find((a) => a.todoId === id && window.Store.isAllocationLive(a));
    window.Store.cancelAllocation(alloc.id);
    window.App.render();
  }, target.id);
  await settle(page, 240);
  const restored = await page.evaluate(() => window.Store.inboxTodos().length);
  assertEq(restored, before, 'cancelling the allocation must return the to-do to Unplanned');
  await noErrors(page);
  await page.close();
});

/* ---------- Todos: quick add, day context ---------- */
scenario('todos quick add inherits the browsed day as deadline', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const s0 = await state(page);
  const day = new Date(s0.todosView.day.__date);

  await page.fill('[data-testid="todo-quick-add"]', '当天快速添加');
  await page.press('[data-testid="todo-quick-add"]', 'Enter');
  await settle(page, 260);

  const created = (await state(page)).todos.find((t) => t.summary === '当天快速添加');
  assert(created, 'quick add did not create');
  const due = new Date(created.dueDate.__date);
  assertEq([due.getFullYear(), due.getMonth(), due.getDate()], [day.getFullYear(), day.getMonth(), day.getDate()], 'quick add must inherit the browsed day');
  assertEq(due.getHours(), 0, 'quick add deadline must be date-only');
  const list = await textOf(page, '[data-testid="todo-list"]');
  assert(list.includes('当天快速添加'), 'created todo not visible in the day list');
  await noErrors(page);
  await page.close();
});

/* ---------- Week strip changes the browsed day, not "today" ---------- */
scenario('browsing another day in Todos does not move the Action day', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const s0 = await state(page);
  const actionBefore = s0.actionDate.__date;

  const days = await page.$$('.ws-day');
  assert(days.length === 7, 'week strip should show 7 days');
  await days[3].click();
  await settle(page, 200);

  const s1 = await state(page);
  assert(s1.todosView.day.__date !== s0.todosView.day.__date, 'week strip did not change the browsed day');
  assertEq(s1.actionDate.__date, actionBefore, 'Action day must not follow the Todos browse day');

  await go(page, 'action');
  const subtitle = await textOf(page, '.page-sub');
  assert(subtitle, 'Action subtitle missing');
  await noErrors(page);
  await page.close();
});

/* ---------- Composer: create with deadline, appears in Today ---------- */
scenario('composer creates a todo with a deadline that shows in Todos and Action', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  assert(await exists(page, '[data-testid="composer"]'), 'composer did not open');

  await page.fill('[data-testid="composer-title"]', '带截止时间的完整待办');
  await clickTestId(page, 'composer-deadline');
  assert(await exists(page, '.sheet'), 'deadline sheet did not open');
  await page.fill('[data-testid="deadline-date"]', await page.evaluate(() => window.U.toInputDate(window.U.now())));
  await page.fill('[data-testid="deadline-time"]', '17:30');
  await clickTestId(page, 'deadline-apply');
  await settle(page, 160);

  const dueLabel = await textOf(page, '[data-testid="composer-deadline"]');
  assert(dueLabel.includes('17:30'), 'deadline pill should show the chosen time, got ' + dueLabel);

  await clickTestId(page, 'composer-save');
  await settle(page, 260);

  const s = await state(page);
  const created = s.todos.find((t) => t.summary === '带截止时间的完整待办');
  assert(created, 'composer did not create the todo');
  const due = new Date(created.dueDate.__date);
  assertEq([due.getHours(), due.getMinutes()], [17, 30], 'deadline time');
  assert(s.route.name !== 'composer', 'composer must close after save');
  const list = await textOf(page, '[data-testid="todo-list"]');
  assert(list.includes('带截止时间的完整待办'), 'created todo missing from the day list');
  assert(list.includes('17:30'), 'deadline not rendered on the row');

  await go(page, 'action');
  const actionText = await textOf(page, '.page-content');
  assert(actionText.includes('带截止时间的完整待办'), 'created todo missing from Action');
  await noErrors(page);
  await page.close();
});

/* ---------- Composer: type switch is explicit and blocked on edit ---------- */
scenario('composer type switch works on create and is locked on edit', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '类型切换测试');
  assert(await exists(page, '[data-testid="composer-deadline"]'), 'todo composer should show a deadline field');
  await clickTestId(page, 'composer-type-event');
  assert(await exists(page, '[data-testid="composer-location"]'), 'switching to event should show the location field');
  assert(!(await exists(page, '[data-testid="composer-deadline"]')), 'event composer must not show a deadline field');
  await clickTestId(page, 'composer-type-todo');
  assert(await exists(page, '[data-testid="composer-deadline"]'), 'switching back should restore the deadline field');

  await page.fill('[data-testid="composer-title"]', '类型锁定测试');
  await clickTestId(page, 'composer-save');
  await settle(page, 240);
  const created = (await state(page)).todos.find((t) => t.summary === '类型锁定测试');
  assert(created, 'todo not created');

  await page.evaluate((id) => window.Store.navigate('detail', { type: 'todo', id }), created.id);
  await settle(page);
  await clickTestId(page, 'detail-edit');
  assert(await exists(page, '[data-testid="composer"]'), 'edit composer did not open');
  const before = await state(page);
  await clickTestId(page, 'composer-type-event');
  const after = await state(page);
  assertEq(after.composer ? after.composer.kind : null, before.composer ? before.composer.kind : null, 'type must not change while editing');
  assert(await exists(page, '[data-testid="composer-deadline"]'), 'edit composer for a todo must keep the deadline field');
  await noErrors(page);
  await page.close();
});

/* ---------- Composer: validation blocks empty title ---------- */
scenario('composer blocks saving an empty title and explains why', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  const disabled = await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').disabled);
  assert(disabled, 'save must be disabled with an empty title');
  // An untouched form is not a mistake: the rule is enforced silently, and the
  // red explanation waits until the user has actually typed something.
  const premature = await page.evaluate(() => {
    const n = document.querySelector('.hint-box.error');
    return !!n && !n.hidden && n.textContent.trim().length > 0;
  });
  assert(!premature, 'an empty new form must not accuse the user before they type');
  await page.fill('[data-testid="composer-title"]', 'x');
  await page.fill('[data-testid="composer-title"]', '');
  await settle(page, 140);
  const err = await textOf(page, '.hint-box.error');
  assert(err && err.length > 0, 'after the title is cleared the inline error should explain why');
  const countBefore = (await state(page)).todos.length;
  await page.click('[data-testid="composer-save"]', { force: true }).catch(() => {});
  await settle(page, 150);
  assertEq((await state(page)).todos.length, countBefore, 'no todo may be created without a title');
  await noErrors(page);
  await page.close();
});

/* ---------- Composer: cancel with unsaved changes asks first ---------- */
scenario('leaving a dirty composer asks before discarding and can be undone by cancelling', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const routeBefore = (await state(page)).route.name;
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '还没保存的草稿');
  await clickTestId(page, 'composer-close');
  assert(await exists(page, '.modal.confirm'), 'a discard confirmation should appear');
  await page.click('.modal.confirm .btn.ghost');
  await settle(page, 160);
  assert(await exists(page, '[data-testid="composer"]'), 'cancelling the confirmation must keep the composer open');
  assertEq(await page.inputValue('[data-testid="composer-title"]'), '还没保存的草稿', 'draft text must survive');

  await clickTestId(page, 'composer-close');
  await page.click('.modal.confirm .btn.danger');
  await settle(page, 220);
  assert(!(await exists(page, '[data-testid="composer"]')), 'discarding must close the composer');
  assertEq((await state(page)).route.name, routeBefore, 'discarding must return to where the user came from');
  assert(!(await state(page)).todos.some((t) => t.summary === '还没保存的草稿'), 'discarded draft must not be saved');
  await noErrors(page);
  await page.close();
});

/* ---------- Detail: read-only, edit is explicit, edits sync ---------- */
scenario('todo detail is read-only until Edit, and an edit propagates to every surface', async (browser) => {
  const page = await newPage(browser);
  const s0 = await state(page);
  const target = s0.todos.find((t) => t.summary === '回复客户邮件：北岸项目排期');
  assert(target, 'seed todo missing');

  await page.evaluate((id) => window.Store.navigate('detail', { type: 'todo', id }), target.id);
  await settle(page, 180);
  assert(await exists(page, '[data-testid="todo-detail"]'), 'todo detail did not render');
  assert(!(await exists(page, '[data-testid="composer"]')), 'detail must not be an editor');
  const titleText = await textOf(page, '.detail-title');
  assertEq(titleText, target.summary, 'detail title');

  await clickTestId(page, 'detail-edit');
  await page.fill('[data-testid="composer-title"]', '回复客户邮件：北岸项目排期（已改）');
  await clickTestId(page, 'composer-save');
  await settle(page, 260);

  const s1 = await state(page);
  assert(s1.todos.some((t) => t.summary === '回复客户邮件：北岸项目排期（已改）'), 'edit did not persist');
  assert(!s1.todos.some((t) => t.summary === '回复客户邮件：北岸项目排期'), 'old title still present');

  await go(page, 'todos');
  const list = await textOf(page, '[data-testid="todo-list"]');
  assert(list.includes('（已改）'), 'Todos list did not pick up the edit');
  await go(page, 'action');
  const action = await textOf(page, '.page-content');
  assert(action.includes('（已改）'), 'Action did not pick up the edit');
  await noErrors(page);
  await page.close();
});

/* ---------- Complete / undo, and cross-surface agreement ---------- */
scenario('completing a todo moves it to the completed section and to Action earlier-today, and undo restores it', async (browser) => {
  const page = await newPage(browser);
  // Completion only invalidates slots that are still ahead. Pin the clock before
  // the seeded 16:30 slot so the assertion does not depend on the wall clock.
  await page.evaluate(() => {
    const d = new Date();
    d.setHours(9, 0, 0, 0);
    window.U.setClockOffset(d.getTime() - Date.now());
    window.App.render();
  });
  await settle(page, 220);
  await go(page, 'todos');
  const s0 = await state(page);
  const target = s0.todos.find((t) => t.summary === 'Q4 预算表');
  assert(target, 'seed todo missing');

  const row = await page.$(`[data-testid="todo-tile"][data-id="${target.id}"] .checkbox`);
  assert(row, 'checkbox not found for the target row');
  await row.click();
  await settle(page, 240);

  const s1 = await state(page);
  const done = s1.todos.find((t) => t.id === target.id);
  assertEq(done.status, 'COMPLETED', 'todo status after completing');
  assert(done.completedAt, 'completedAt must be set');
  const liveAllocs = s1.allocations.filter((a) => a.todoId === target.id && a.state === 'active');
  assertEq(liveAllocs.length, 0, 'future allocations must be invalidated on completion');
  const toast = await toastText(page);
  assert(toast && toast.includes('Q4 预算表'), 'completion toast missing the title');
  assert(await exists(page, '#toast .undo'), 'completion must offer undo');

  const listText = await textOf(page, '[data-testid="todo-list"]');
  const doneSection = await page.evaluate(() => {
    const heads = Array.from(document.querySelectorAll('.section-head'));
    return heads.map((h) => h.textContent);
  });
  assert(doneSection.some((h) => h.includes('已完成')), 'completed section missing');
  assert(listText.includes('Q4 预算表'), 'completed todo should stay visible in its completed section');

  await go(page, 'action');
  const action = await textOf(page, '.page-content');
  assert(action.includes('Q4 预算表'), 'completed todo missing from Action earlier-today');
  assert(action.includes('今天早些时候') || action.includes('Earlier'), 'earlier-today section missing');

  await go(page, 'todos');
  await page.click('#toast .undo');
  await settle(page, 220);
  const s2 = await state(page);
  assertEq(s2.todos.find((t) => t.id === target.id).status, 'NEEDS-ACTION', 'undo must restore the open state');
  await noErrors(page);
  await page.close();
});

/* ---------- Delete -> Trash -> restore ---------- */
scenario('deleting a todo moves it to Trash and restore brings it back with its data', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const s0 = await state(page);
  const target = s0.todos.find((t) => t.summary === '整理评审纪要');
  assert(target, 'seed todo missing');

  await page.evaluate((id) => {
    const row = document.querySelector(`[data-testid="todo-tile"][data-id="${id}"] .todo-row`);
    row.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 400, clientY: 300 }));
  }, target.id);
  await settle(page, 150);
  assert(await exists(page, '.menu'), 'row menu did not open on right click');
  const menuText = await textOf(page, '.menu');
  assert(menuText.includes('移到回收站'), 'row menu missing the trash action');
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('.menu button')).find((b) => b.textContent.includes('移到回收站'));
    btn.click();
  });
  await settle(page, 220);

  const s1 = await state(page);
  assert(s1.todos.find((t) => t.id === target.id).deletedAt, 'todo was not soft-deleted');
  const listText = await textOf(page, '[data-testid="todo-list"]');
  assert(!listText.includes('整理评审纪要'), 'deleted todo still visible in the list');
  assert(await exists(page, '#toast .undo'), 'delete must offer undo');

  await go(page, 'trash');
  const trashText = await textOf(page, '.page-content');
  assert(trashText.includes('整理评审纪要'), 'deleted todo missing from Trash');
  await page.click('[data-testid="trash-restore"]');
  await settle(page, 240);

  const s2 = await state(page);
  const restored = s2.todos.find((t) => t.id === target.id);
  assertEq(restored.deletedAt, null, 'restore must clear deletedAt');
  assertEq(restored.dueDate.__date, target.dueDate.__date, 'restore must keep the deadline');
  await go(page, 'todos');
  assert((await textOf(page, '[data-testid="todo-list"]')).includes('整理评审纪要'), 'restored todo missing from the list');
  await noErrors(page);
  await page.close();
});

/* ---------- Event create from calendar slot, appears in grid + Action ---------- */
scenario('creating an event from a calendar slot fills the grid and Action', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  const slots = await page.$$('.slot-hit');
  // Dawn is folded by default; the fold must expose the hours it hides.
  assert(slots.length === 18, `day view should fold 00:00-06:00 by default (got ${slots.length})`);
  await page.evaluate(() => document.querySelector('[data-testid="dawn-fold"]').click());
  await settle(page, 160);
  assertEq((await page.$$('.slot-hit')).length, 24, 'expanding dawn must expose all 24 hours');
  await page.evaluate(() => {
    const slot = Array.from(document.querySelectorAll('.slot-hit')).find((s) => s.dataset.hour === '10');
    slot.click();
  });
  await settle(page, 200);
  assert(await exists(page, '.sheet'), 'slot sheet did not open');
  await clickTestId(page, 'slot-new-event');
  assert(await exists(page, '[data-testid="composer"]'), 'event composer did not open');
  const start = await page.inputValue('[data-testid="composer-start-time"]');
  assertEq(start, '10:00', 'composer should prefill the slot start');

  await page.fill('[data-testid="composer-title"]', '从时间格创建的日程');
  await page.fill('[data-testid="composer-location"]', '会议室 B');
  await clickTestId(page, 'composer-save');
  await settle(page, 280);

  const s = await state(page);
  const created = s.events.find((e) => e.summary === '从时间格创建的日程');
  assert(created, 'event was not created');
  assertEq(created.location, '会议室 B', 'event location');
  assert(s.route.name !== 'composer', 'composer must close');

  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  const blocks = await page.$$eval('[data-testid="event-block"]', (ns) => ns.map((n) => n.textContent));
  assert(blocks.some((b) => b.includes('从时间格创建的日程')), 'new event missing from the day grid');

  await go(page, 'action');
  const action = await textOf(page, '.page-content');
  assert(action.includes('从时间格创建的日程'), 'new event missing from Action');
  await noErrors(page);
  await page.close();
});

/* ---------- Schedule a todo into a slot; reschedule it ---------- */
scenario('scheduling a todo from a slot creates an allocation that can be rescheduled', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  await page.evaluate(() => {
    const slot = Array.from(document.querySelectorAll('.slot-hit')).find((s) => s.dataset.hour === '15');
    slot.click();
  });
  await settle(page, 200);
  await clickTestId(page, 'slot-schedule-todo');
  assert(await exists(page, '.sheet'), 'schedulable picker did not open');
  const picks = await page.$$('[data-testid="schedulable-todo"]');
  assert(picks.length > 0, 'no schedulable to-dos listed');
  const chosen = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('[data-testid="schedulable-todo"]'));
    const row = rows.find((r) => !r.textContent.includes('重复')) || rows[0];
    return row.querySelector('.row-title').textContent.trim();
  });
  await page.evaluate((name) => {
    const row = Array.from(document.querySelectorAll('[data-testid="schedulable-todo"]'))
      .find((r) => r.querySelector('.row-title').textContent.trim() === name);
    row.click();
  }, chosen);
  await settle(page, 300);

  const s1 = await state(page);
  const todo = s1.todos.find((t) => t.summary === chosen);
  const before = new Set((await state(page)).allocations.map((a) => a.id));
  const created = s1.allocations.filter((a) => a.todoId === todo.id && a.state === 'active').sort((a, b) => b.id - a.id)[0];
  assert(created, 'allocation was not created');
  const alloc = created;
  const start = new Date(alloc.startAt.__date);
  assertEq(start.getHours(), 15, 'allocation should start at the slot hour');
  assertEq(start.getMinutes(), 0, 'allocation should start on the hour');

  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  assert(await exists(page, '[data-testid="alloc-block"]'), 'allocation block missing from the grid');

  await page.evaluate((id) => {
    const block = document.querySelector(`[data-testid="alloc-block"][data-id="${id}"]`);
    block.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 600, clientY: 500 }));
  }, alloc.id);
  await settle(page, 150);
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('.menu button')).find((b) => b.textContent.includes('改期'));
    btn.click();
  });
  await settle(page, 160);
  assert(await exists(page, '.modal'), 'reschedule dialog did not open');
  const newStart = await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    d.setHours(11, 0, 0, 0);
    return window.U.toInputDateTime(d);
  });
  const newEnd = await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    d.setHours(12, 30, 0, 0);
    return window.U.toInputDateTime(d);
  });
  const inputs = await page.$$('.modal input[type="datetime-local"]');
  await inputs[0].fill(newStart);
  await inputs[1].fill(newEnd);
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('.modal .btn.primary')).pop();
    btn.click();
  });
  await settle(page, 300);

  const s2 = await state(page);
  const moved = s2.allocations.find((a) => a.id === alloc.id);
  const movedStart = new Date(moved.startAt.__date);
  assertEq([movedStart.getHours(), movedStart.getMinutes()], [11, 0], 'allocation start after reschedule');
  const movedEnd = new Date(moved.endAt.__date);
  assertEq([movedEnd.getHours(), movedEnd.getMinutes()], [12, 30], 'allocation end after reschedule');
  await noErrors(page);
  await page.close();
});

/* ---------- Allocation survives on its todo detail ---------- */
scenario('a scheduled todo shows its allocated time on the row and in its detail', async (browser) => {
  const page = await newPage(browser);
  const s0 = await state(page);
  const withAlloc = s0.allocations.find((a) => a.state === 'active' && !a.occurrenceId);
  assert(withAlloc, 'seed has no simple allocation');
  const todo = s0.todos.find((t) => t.id === withAlloc.todoId);

  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 200);
  const rowText = await page.evaluate((id) => {
    const row = document.querySelector(`[data-testid="todo-tile"][data-id="${id}"]`);
    return row ? row.textContent : null;
  }, todo.id);
  assert(rowText && /\d{2}:\d{2}/.test(rowText), 'row should show the allocated time range');

  await page.evaluate((id) => window.Store.navigate('detail', { type: 'todo', id }), todo.id);
  await settle(page, 200);
  const detail = await textOf(page, '[data-testid="todo-detail"]');
  assert(detail.includes('安排') || detail.includes('执行'), 'detail should have a scheduled-time fact');
  assert(/\d{2}:\d{2}/.test(detail), 'detail should show the allocated time');
  await noErrors(page);
  await page.close();
});

/* ---------- Recurring: completing one occurrence only ---------- */
scenario('completing one occurrence of a recurring todo leaves the series and other days intact', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  const s0 = await state(page);
  const rec = s0.todos.find((t) => t.recurrence && t.summary === '每日站会记录');
  assert(rec, 'seed recurring todo missing');

  const before = Object.keys(rec.occurrenceStates || {}).length;
  const rows = await page.$$('[data-testid="action-instance"]');
  assert(rows.length > 0, 'no recurring instance rows on Action');
  await page.evaluate((name) => {
    const row = Array.from(document.querySelectorAll('[data-testid="action-instance"]'))
      .find((r) => r.textContent.includes(name));
    row.querySelector('.checkbox').click();
  }, rec.summary);
  await settle(page, 260);

  const s1 = await state(page);
  const rec1 = s1.todos.find((t) => t.id === rec.id);
  const after = Object.keys(rec1.occurrenceStates || {}).length;
  assertEq(after, before + 1, 'exactly one occurrence should be marked complete');
  assertEq(rec1.status, 'NEEDS-ACTION', 'the series itself must stay open');
  const doneRows = await page.$$eval('[data-testid="action-instance"]', (ns) => ns.map((n) => n.textContent));
  assert(doneRows.some((t) => t.includes('每日站会记录')), 'series row should still be listed');
  await noErrors(page);
  await page.close();
});

/* ---------- Search finds new and edited items ---------- */
scenario('search finds a newly created item and opens its detail', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await page.fill('[data-testid="action-capture"]', '搜索用的独特标题');
  await page.press('[data-testid="action-capture"]', 'Enter');
  await settle(page, 240);

  await go(page, 'search');
  await page.fill('[data-testid="search-input"]', '独特标题');
  await settle(page, 320);
  const results = await textOf(page, '[data-testid="search-results"]');
  assert(results.includes('搜索用的独特标题'), 'search did not find the created todo');
  await page.click('[data-testid="search-hit-todo"]');
  await settle(page, 220);
  assert(await exists(page, '[data-testid="todo-detail"]'), 'search result did not open the detail');
  await noErrors(page);
  await page.close();
});

/* ---------- Empty search and empty inbox states ---------- */
scenario('search and lists explain empty results instead of showing blank space', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'search');
  await page.fill('[data-testid="search-input"]', 'zzzz-not-a-real-thing');
  await settle(page, 320);
  const empty = await textOf(page, '.empty');
  assert(empty && empty.length > 0, 'search should render an empty state with copy');

  await go(page, 'todos');
  // Seed data carries repeating series, so a fixed offset is not reliably empty.
  // Ask the data which day has nothing on it rather than assuming one.
  await page.evaluate(() => {
    const base = window.U.startOfDay(window.U.now());
    let day = window.U.addDays(base, -30);
    for (let i = 0; i < 800; i += 1) {
      const d = window.U.addDays(base, -400 + i);
      const r = window.Store.todosForDay(d);
      if (!r.dated.length && !r.overdue.length && !r.done.length && !r.doneInstances.length) { day = d; break; }
    }
    window.__todoHelpers.setView({ kind: 'day', day });
  });
  await settle(page, 200);
  assert(await exists(page, '.empty'), 'an empty day should render an empty state');
  await noErrors(page);
  await page.close();
});

/* ---------- Six-things is retired: the day list never truncates ---------- */
scenario('the day list shows every row and offers no six-things cap', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  for (const title of ['补充一', '补充二', '补充三', '补充四', '补充五']) {
    await page.fill('[data-testid="todo-quick-add"]', title);
    await page.press('[data-testid="todo-quick-add"]', 'Enter');
    await settle(page, 160);
  }
  const chip = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.chip-btn')).some((x) => /六件事|Six things/.test(x.textContent)));
  assert(!chip, 'the six-things chip must be gone from the to-do toolbar');
  const state = await page.evaluate(() => {
    const day = window.Store.todosForDay(new Date());
    return {
      total: day.dated.length + day.overdue.length + day.done.length,
      shown: document.querySelectorAll('.todo-list [data-testid="todo-tile"]').length,
    };
  });
  assert(state.total > 6, `seed plus five captures should exceed six rows, got ${state.total}`);
  assertEq(state.shown, state.total, 'every dated, overdue and completed row must be rendered, with no cap to fold');
  const fold = await page.evaluate(() =>
    Array.from(document.querySelectorAll('button')).some((x) => /展开其余|Show \d+ more/.test(x.textContent)));
  assert(!fold, 'no truncation control should exist');
  await noErrors(page);
  await page.close();
});

/* ---------- Overdue missed instances are never silently truncated ---------- */
scenario('missed recurring instances beyond five are reachable from the overdue section', async (browser) => {
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
  await settle(page, 300);
  const collapsed = await count(page, '[data-testid="action-instance"]');
  assert(await exists(page, '[data-testid="overdue-more"]'), 'a truncated overdue section must offer a way to see the rest');
  await page.click('[data-testid="overdue-more"]');
  await settle(page, 260);
  const expanded = await count(page, '[data-testid="action-instance"]');
  assert(expanded > collapsed, `expanding must reveal the hidden missed instances (${collapsed} -> ${expanded})`);
  assert(await exists(page, '[data-testid="overdue-less"]'), 'expanded overdue should offer collapse');
  await page.click('[data-testid="overdue-less"]');
  await settle(page, 260);
  assertEq(await count(page, '[data-testid="action-instance"]'), collapsed, 'collapsing must return to the capped list');
  await noErrors(page);
  await page.close();
});

/* ---------- Long title does not break layout ---------- */
scenario('a very long title wraps without breaking the row or the page', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const long = '这是一个非常非常长的待办标题'.repeat(8);
  await page.fill('[data-testid="todo-quick-add"]', long);
  await page.press('[data-testid="todo-quick-add"]', 'Enter');
  await settle(page, 260);
  await noOverflow(page);
  const row = await page.evaluate((text) => {
    const r = Array.from(document.querySelectorAll('[data-testid="todo-tile"]')).find((x) => x.textContent.includes(text.slice(0, 12)));
    if (!r) return null;
    const b = r.getBoundingClientRect();
    return { w: Math.round(b.width), right: Math.round(b.right), vw: window.innerWidth };
  }, long);
  assert(row, 'long-titled row not found');
  assert(row.right <= row.vw + 1, 'row extends past the viewport');
  await noErrors(page);
  await page.close();
});

/* ---------- Missing record shows an error page with a way out ---------- */
scenario('opening a record that does not exist shows an error state with a way back', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.Store.navigate('detail', { type: 'todo', id: 999999 }));
  await settle(page, 200);
  const text = await textOf(page, '.page-content');
  assert(text && text.length > 0, 'missing record should render an error state');
  const back = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => /返回|Back/.test(x.textContent));
    return !!b;
  });
  assert(back, 'error state must offer a way back');
  await noErrors(page);
  await page.close();
});

/* ---------- Escape closes overlays before leaving the page ---------- */
scenario('Escape closes the top overlay first and only then leaves the page', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', 'Esc 测试草稿');
  const route = (await state(page)).route.name;
  await page.keyboard.press('Escape');
  await settle(page, 200);
  assert(await exists(page, '.modal.confirm'), 'Escape with unsaved changes should ask before discarding');
  await page.keyboard.press('Escape');
  await settle(page, 180);
  assert(!(await exists(page, '.modal.confirm')), 'a second Escape should close the confirmation');
  assert(await exists(page, '[data-testid="composer"]'), 'closing the confirmation must not close the composer');
  assertEq((await state(page)).route.name, route, 'still in the composer');
  await noErrors(page);
  await page.close();
});

/* ---------- Keyboard: N opens a new to-do ---------- */
scenario('keyboard N opens a new to-do and / opens search', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.keyboard.press('n');
  await settle(page, 200);
  assert(await exists(page, '[data-testid="composer"]'), 'N should open the composer');
  await page.evaluate(() => window.App.back());
  await settle(page, 160);
  await page.keyboard.press('/');
  await settle(page, 200);
  assertEq((await state(page)).route.name, 'search', '/ should open search');
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  await page.keyboard.press('?');
  await settle(page, 180);
  assert(await exists(page, '.modal'), '? should open the shortcut list');
  await noErrors(page);
  await page.close();
});

/* ---------- Tag filter narrows the list and clears ---------- */
scenario('tag filter narrows the list and clearing it restores every row', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 180);
  const all = await count(page, '[data-testid="todo-tile"]');
  const tagId = await page.evaluate(() => window.Store.state.tags.find((t) => t.name === '健康').id);
  await clickTestId(page, 'todos-filter');
  await clickTestId(page, 'filter-tag-' + tagId);
  await clickTestId(page, 'filter-apply');
  await settle(page, 220);
  const filtered = await count(page, '[data-testid="todo-tile"]');
  assert(filtered > 0 && filtered < all, `tag filter should narrow the list (all=${all}, filtered=${filtered})`);
  await clickTestId(page, 'todos-filter');
  await clickTestId(page, 'filter-clear');
  await settle(page, 220);
  assertEq(await count(page, '[data-testid="todo-tile"]'), all, 'clearing the filter must restore the list');
  await noErrors(page);
  await page.close();
});

/* ---------- Calendar month cell drills into the day ---------- */
scenario('month view drills into a day and week view shows the same events', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-month');
  assert(await exists(page, '[data-testid="month-grid"]'), 'month grid missing');
  const cells = await page.$$('.month-cell');
  assert(cells.length >= 28, 'month grid should have at least 28 cells');
  await page.evaluate(() => {
    const cell = Array.from(document.querySelectorAll('.month-cell')).find((c) => c.textContent.includes('设计走查'));
    (cell || document.querySelector('.month-cell')).click();
  });
  await settle(page, 240);
  assertEq((await state(page)).calendarView, 'day', 'tapping a month cell must open that day');
  await clickTestId(page, 'cal-view-week');
  assert(await exists(page, '[data-testid="time-scroll"]'), 'week view should render the time grid');
  const week = await page.$$eval('[data-testid="event-block"]', (ns) => ns.map((n) => n.textContent));
  assert(week.length > 0, 'week view should show the seeded events');
  await noErrors(page);
  await page.close();
});

/* ---------- Calendar: deadline lane never occupies the grid ---------- */
scenario('deadlines are listed in their own lane and never drawn as time blocks', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  const lane = await textOf(page, '[data-testid="deadline-lane"]');
  assert(lane && lane.length > 0, 'deadline lane missing');
  const blockTitles = await page.$$eval('[data-testid="event-block"], [data-testid="alloc-block"]', (ns) => ns.map((n) => n.textContent));
  const s = await state(page);
  const allocated = new Set(s.allocations.filter((a) => a.state === 'active').map((a) => a.todoId));
  const deadlineOnly = s.todos.filter((t) => !t.recurrence && t.status === 'NEEDS-ACTION' && t.dueDate && !allocated.has(t.id));
  assert(deadlineOnly.length > 0, 'the seed should contain at least one deadline without a scheduled time');
  const leaked = deadlineOnly.filter((t) => blockTitles.some((b) => b.includes(t.summary)));
  assertEq(leaked.map((t) => t.summary), [], 'deadline-only todos must not appear as timed blocks');
  await noErrors(page);
  await page.close();
});

/* ---------- Deadline lane never silently hides the rest ---------- */
scenario('a crowded deadline lane expands and collapses instead of showing "+n"', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const base = new Date();
    for (let i = 0; i < 12; i++) {
      window.Store.createTodo({
        summary: '截止测试 ' + (i + 1),
        dueDate: new Date(base.getFullYear(), base.getMonth(), base.getDate() + i, 17),
      });
    }
    window.Store.state.calendarView = 'week';
    window.App.go('calendar');
  });
  await settle(page, 300);
  const chips = () => count(page, '.deadline-lane .deadline-chip:not(.more)');
  assertEq(await chips(), 8, 'the lane should show eight chips before expanding');
  assert(await exists(page, '[data-testid="deadline-more"]'), 'a crowded lane must offer a way to see the rest');
  await page.click('[data-testid="deadline-more"]');
  await settle(page, 260);
  assert(await chips() > 8, 'expanding must reveal the remaining deadlines');
  assert(await exists(page, '[data-testid="deadline-less"]'), 'expanded lane should offer collapse');
  await noOverflow(page);
  await page.click('[data-testid="deadline-less"]');
  await settle(page, 260);
  assertEq(await chips(), 8, 'collapsing must return to eight chips');
  await noErrors(page);
  await page.close();
});

/* ---------- Cancelling an allocation keeps the todo ---------- */
scenario('cancelling a scheduled block removes the block but keeps the to-do', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  assert(await exists(page, '[data-testid="alloc-block"]'), 'no allocation block to cancel');
  const info = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="alloc-block"]');
    return { id: Number(b.dataset.id), text: b.textContent };
  });
  await page.evaluate(() => {
    const block = document.querySelector('[data-testid="alloc-block"]');
    block.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 600, clientY: 500 }));
  });
  await settle(page, 150);
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('.menu button')).find((b) => b.textContent.includes('取消安排'));
    btn.click();
  });
  await settle(page, 160);
  assert(await exists(page, '.modal.confirm'), 'cancelling an allocation should confirm first');
  await page.click('.modal.confirm .btn.danger');
  await settle(page, 260);

  const s = await state(page);
  const alloc = s.allocations.find((a) => a.id === info.id);
  assertEq(alloc.state, 'cancelledByUser', 'allocation state after cancel');
  assert(s.todos.some((t) => !t.deletedAt && info.text.includes(t.summary)), 'the to-do itself must survive');
  await go(page, 'todos');
  await noErrors(page);
  await page.close();
});

/* ---------- Subtasks ---------- */
scenario('adding a subtask from a parent detail keeps it out of the top-level lists', async (browser) => {
  const page = await newPage(browser);
  const s0 = await state(page);
  const parent = s0.todos.find((t) => t.summary === '准备季度评审');
  assert(parent, 'seed parent missing');
  await page.evaluate((id) => window.Store.navigate('detail', { type: 'todo', id }), parent.id);
  await settle(page, 200);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => x.textContent.includes('添加子任务'));
    b.click();
  });
  await settle(page, 220);
  await page.fill('[data-testid="composer-title"]', '新子任务：补齐数据');
  await clickTestId(page, 'composer-save');
  await settle(page, 300);

  const s1 = await state(page);
  const sub = s1.todos.find((t) => t.summary === '新子任务：补齐数据');
  assert(sub, 'subtask not created');
  assertEq(sub.parentId, parent.id, 'subtask parentId');
  assertEq(s1.route.name, 'detail', 'saving a subtask should return to the parent detail');
  assertEq(s1.route.params.id, parent.id, 'should return to the parent, not elsewhere');
  const detail = await textOf(page, '[data-testid="todo-detail"]');
  assert(detail.includes('新子任务：补齐数据'), 'subtask missing from the parent detail');

  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 200);
  const list = await textOf(page, '[data-testid="todo-list"]');
  assert(!list.includes('新子任务：补齐数据'), 'subtasks must not appear as top-level rows in All');
  await noErrors(page);
  await page.close();
});

/* ---------- Settings: language and theme switch immediately ---------- */
scenario('switching language and theme updates the shell immediately and persists across pages', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings');
  await clickTestId(page, 'lang-en');
  await settle(page, 220);
  assertEq(await page.evaluate(() => document.documentElement.lang), 'en', 'html lang after switching to English');
  const nav = await textOf(page, '#rail');
  assert(nav.includes('Today') && nav.includes('Settings'), 'rail should be in English after the switch');

  await clickTestId(page, 'theme-dark');
  await settle(page, 180);
  assertEq(await page.evaluate(() => document.documentElement.dataset.theme), 'dark', 'theme attribute');
  const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  assert(bg !== 'rgb(255, 255, 255)', 'dark theme should not leave a white body');

  await go(page, 'todos');
  assertEq(await page.evaluate(() => document.documentElement.dataset.theme), 'dark', 'theme must survive navigation');
  assert((await textOf(page, '.page-title')).length > 0, 'page title missing in English');
  await noErrors(page);
  await page.close();
});

/* ---------- AI: proposal is not written until confirmed ---------- */
scenario('an AI proposal does not change data until the user applies it', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'chat');
  const before = (await state(page)).allocations.length;
  await page.fill('[data-testid="chat-input"]', '把 Q4 预算表安排到明天上午');
  await page.press('[data-testid="chat-input"]', 'Enter');
  await settle(page, 1100);
  assert(await exists(page, '[data-testid="ai-proposal"]'), 'assistant should propose an action');
  assertEq((await state(page)).allocations.length, before, 'nothing may be written before confirmation');

  await clickTestId(page, 'ai-apply');
  await settle(page, 300);
  assertEq((await state(page)).allocations.length, before + 1, 'applying the proposal should create exactly one allocation');
  assert(!(await exists(page, '[data-testid="ai-apply"]')), 'the apply control should disappear once applied');
  await noErrors(page);
  await page.close();
});

/* ---------- Mobile: bottom nav, create, detail, back ---------- */
scenario('mobile: bottom nav reaches every primary tab and a created item opens and returns', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await noOverflow(page);
  const tabs = await page.$$('[data-testid^="tab-"]');
  assertEq(tabs.length, 4, 'mobile bottom nav should be the three destinations plus More');
  // Every tool that lives in the desktop rail has to be reachable on a phone
  // too, or Settings/Search/AI/Calendars are dead ends there.
  await clickTestId(page, 'tab-more');
  await settle(page, 220);
  const menuLabels = await page.$$eval('.menu button', (ns) => ns.map((n) => n.textContent.trim()));
  ['搜索', 'AI 助手', '标签', '日历管理', '回收站', '设置'].forEach((label) => {
    assert(menuLabels.some((x) => x.includes(label)), `mobile More menu must expose ${label}, got ${JSON.stringify(menuLabels)}`);
  });
  await clickTestId(page, 'tab-todos');
  await settle(page, 160);
  assert((await state(page)).route.name === 'todos', 'bottom nav should open Todos');
  await clickTestId(page, 'todos-create');
  assert(await exists(page, '[data-testid="composer"]'), 'mobile create button should open the composer');
  await page.fill('[data-testid="composer-title"]', '手机端创建的待办');
  await clickTestId(page, 'composer-save');
  await settle(page, 300);
  await noOverflow(page);

  const created = (await state(page)).todos.find((t) => t.summary === '手机端创建的待办');
  assert(created, 'mobile composer did not save');
  await page.evaluate((id) => {
    const row = document.querySelector(`[data-testid="todo-tile"][data-id="${id}"] .todo-row`);
    row.click();
  }, created.id);
  await settle(page, 240);
  assert(await exists(page, '[data-testid="todo-detail"]'), 'mobile row tap should open the detail');
  await noOverflow(page);

  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.detail-head button')).find((x) => x.getAttribute('aria-label') === '返回' || x.getAttribute('aria-label') === 'Back');
    b.click();
  });
  await settle(page, 240);
  assertEq((await state(page)).route.name, 'todos', 'back from the detail should return to Todos');
  await noErrors(page);
  await page.close();
});

/* ---------- Mobile calendar slot -> create ---------- */
scenario('mobile: tapping a calendar slot can create an event without leaving the calendar', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await clickTestId(page, 'tab-calendar');
  await clickTestId(page, 'cal-view-day');
  await page.evaluate(() => {
    const slot = Array.from(document.querySelectorAll('.slot-hit')).find((s) => s.dataset.hour === '14');
    slot.click();
  });
  await settle(page, 220);
  assert(await exists(page, '.sheet'), 'mobile slot sheet did not open');
  await clickTestId(page, 'slot-new-event');
  await page.fill('[data-testid="composer-title"]', '手机端日程');
  await clickTestId(page, 'composer-save');
  await settle(page, 300);
  const created = (await state(page)).events.find((e) => e.summary === '手机端日程');
  assert(created, 'mobile event not created');
  await noOverflow(page);
  await noErrors(page);
  await page.close();
});

/* ---------- Drag an event: moves, and undo puts it back ---------- */
scenario('dragging an event block moves it and the toast undo puts it back', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  const before = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
    return { id: e.id, s: e.startDt.getTime(), e: e.endDt.getTime() };
  });
  const box = await page.evaluate((id) => {
    const r = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`).getBoundingClientRect();
    return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + 6) };
  }, before.id);
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 60, { steps: 8 });
  await page.mouse.move(box.x, box.y + 100, { steps: 8 });
  await page.mouse.up();
  await settle(page, 320);
  const after = await page.evaluate((id) => {
    const e = window.Store.state.events.find((x) => x.id === id);
    return { s: e.startDt.getTime(), e: e.endDt.getTime() };
  }, before.id);
  assert(after.s - before.s >= 60 * 60000, `dragging should move the event by at least an hour, moved ${(after.s - before.s) / 60000}min`);
  assertEq(after.e - after.s, before.e - before.s, 'dragging must keep the duration');

  assert(await exists(page, '#toast .undo'), 'moving an event must offer undo');
  await page.click('#toast .undo');
  await settle(page, 300);
  const undone = await page.evaluate((id) => {
    const e = window.Store.state.events.find((x) => x.id === id);
    return { s: e.startDt.getTime(), e: e.endDt.getTime() };
  }, before.id);
  assertEq(undone, { s: before.s, e: before.e }, 'undo must restore the original time');
  await noErrors(page);
  await page.close();
});

/* ---------- Recurring event drag asks scope and can be undone ---------- */
scenario('dragging one occurrence of a repeating event asks the scope, and undo reverses it', async (browser) => {
  const page = await newPage(browser);
  const seriesId = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule);
    const d = new Date(e.startDt.getFullYear(), e.startDt.getMonth(), e.startDt.getDate());
    window.Store.state.calendarAnchor = d;
    window.Store.state.calendarFocusDay = d;
    window.Store.setBrowseDate(d);
    window.Store.state.calendarView = 'day';
    return e.id;
  });
  await go(page, 'calendar');
  const selector = `[data-testid="event-block"][data-id="${seriesId}"]`;
  assert(await exists(page, selector), 'the repeating instance should appear on its own day');
  const before = await page.evaluate(() => ({ n: window.Store.state.events.length }));

  const box = await page.evaluate((sel) => {
    const r = document.querySelector(sel).getBoundingClientRect();
    return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + 6) };
  }, selector);
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 60, { steps: 8 });
  await page.mouse.up();
  await settle(page, 320);
  assert(await exists(page, '.sheet'), 'moving a repeating occurrence must ask which occurrences to change');
  await page.evaluate(() => { document.querySelectorAll('.sheet .slot-sheet-option')[0].click(); });
  await settle(page, 320);

  const split = await page.evaluate(() => ({
    n: window.Store.state.events.length,
    exdates: window.Store.state.events.filter((e) => (e.exdates || []).length).length,
  }));
  assertEq(split.n, before.n + 1, 'choosing "this one" should add a one-off event');
  assertEq(split.exdates, 1, 'the series should exclude the moved occurrence');

  assert(await exists(page, '#toast .undo'), 'the split must be undoable');
  await page.click('#toast .undo');
  await settle(page, 320);
  const restored = await page.evaluate(() => ({
    n: window.Store.state.events.length,
    exdates: window.Store.state.events.filter((e) => (e.exdates || []).length).length,
  }));
  assertEq(restored, { n: before.n, exdates: 0 }, 'undo must merge the split back into the series');
  await noErrors(page);
  await page.close();
});

/* ---------- Every visible control in every route responds ---------- */
scenario('every route renders, and clicking its visible controls raises no errors', async (browser) => {
  const page = await newPage(browser);
  const routes = ['action', 'calendar', 'todos', 'search', 'chat', 'tags', 'calendars', 'trash', 'settings', 'about', 'feedback', 'states'];
  for (const route of routes) {
    await go(page, route);
    assert(await exists(page, '#view .page, #view .detail, #view .composer, #view .chat'), `${route} rendered nothing`);
    const buttons = await page.$$('#view button');
    for (let i = 0; i < buttons.length; i++) {
      const fresh = (await page.$$('#view button'))[i];
      if (!fresh) continue;
      const visible = await fresh.evaluate((n) => n.offsetParent !== null && !n.disabled);
      if (!visible) continue;
      await fresh.click({ timeout: 1500 }).catch(() => {});
      await page.waitForTimeout(30);
      if (await exists(page, '.modal-scrim, .sheet-scrim')) {
        await page.keyboard.press('Escape');
        await settle(page, 60);
      }
      if (await exists(page, '.menu')) await page.keyboard.press('Escape');
      if ((await state(page)).route.name !== route && !['composer', 'detail', 'search'].includes((await state(page)).route.name)) {
        await go(page, route);
      }
    }
    assert(page.__errors.length === 0, `${route}: ${page.__errors.slice(0, 2).join(' | ')}`);
  }
  await noErrors(page);
  await page.close();
});

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME, headless: !HEADED });
  const picked = scenarios.filter((s) => !FILTER || s.name.includes(FILTER));
  const results = [];
  for (const s of picked) {
    const started = Date.now();
    try {
      await s.fn(browser);
      results.push({ name: s.name, ok: true, ms: Date.now() - started });
      console.log(`PASS ${s.name} (${Date.now() - started}ms)`);
    } catch (e) {
      results.push({ name: s.name, ok: false, err: e.message, ms: Date.now() - started });
      console.log(`FAIL ${s.name}\n     ${e.message}`);
    }
  }
  await browser.close();
  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} interaction scenarios passed`);
  if (failed.length) {
    console.log('\nFailures:');
    failed.forEach((f) => console.log(` - ${f.name}: ${f.err}`));
    process.exit(1);
  }
})().catch((e) => { console.error(e); process.exit(1); });
