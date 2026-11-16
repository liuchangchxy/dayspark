/* Round-5 reviewer regression suite. Every scenario reproduces a finding from
   REVIEW_ROUND5.md with real pointer input and asserts the frozen contract in
   CORE_UX_SPEC.md, not the prototype's own claims. */
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
async function fillTestId(page, id, value) {
  await page.fill(`[data-testid="${id}"]`, value);
  await settle(page, 120);
}
function assertNoErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}
async function completeViaRow(page, title) {
  const ok = await page.evaluate((name) => {
    const row = Array.from(document.querySelectorAll('.todo-row'))
      .find((r) => r.textContent.includes(name));
    const hit = row && row.querySelector('.hit[role="checkbox"]');
    if (!hit) return false;
    hit.click();
    return true;
  }, title);
  assert(ok, 'row checkbox not found for ' + title);
  await settle(page, 240);
}

/* P1-1 — batch complete on a browsed day resolves that occurrence */
scenario('P1-1 batch complete writes the browsed day occurrence', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const info = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    let day = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    for (let i = 0; i < 7 && !window.Store.matchesRule(todo, day); i++) day = window.U.addDays(day, 1);
    window.__todoHelpers.setView({ kind: 'day', day });
    return { id: todo.id, day: day.getTime(), occ: window.Store.occurrenceIdFor(todo, day) };
  });
  await settle(page, 260);
  await clickText(page, 'button', '选择');
  await page.evaluate((name) => {
    const row = Array.from(document.querySelectorAll('.todo-row')).find((r) => r.textContent.includes(name));
    row.click();
  }, '每日站会记录');
  await settle(page, 180);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.selectbar button')).find((x) => /完成/.test(x.textContent));
    b.click();
  });
  await settle(page, 280);
  const states = await page.evaluate((id) => window.Store.todoById(id).occurrenceStates, info.id);
  assert(states[info.occ] && states[info.occ].completedAt, 'the browsed day occurrence must be completed');
  const todayOcc = await page.evaluate((id) => {
    const todo = window.Store.todoById(id);
    return window.Store.occurrenceIdFor(todo, window.U.startOfDay(window.U.now()));
  }, info.id);
  assert(!states[todayOcc] || !states[todayOcc].completedAt, 'today occurrence must not be written');
  assertNoErrors(page);
  await page.close();
});

/* P1-2 — detail completion on a browsed day resolves that occurrence */
scenario('P1-2 detail complete writes the day it was opened for', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const info = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    let day = window.U.addDays(window.U.startOfDay(window.U.now()), 2);
    for (let i = 0; i < 7 && !window.Store.matchesRule(todo, day); i++) day = window.U.addDays(day, 1);
    window.__todoHelpers.setView({ kind: 'day', day });
    return { id: todo.id, day: day.getTime(), occ: window.Store.occurrenceIdFor(todo, day) };
  });
  await settle(page, 260);
  await page.evaluate((name) => {
    const row = Array.from(document.querySelectorAll('.todo-row')).find((r) => r.textContent.includes(name));
    row.click();
  }, '每日站会记录');
  await settle(page, 260);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'desktop list must open the detail pane');
  await clickTestId(page, 'detail-complete');
  await settle(page, 260);
  const states = await page.evaluate((id) => window.Store.todoById(id).occurrenceStates, info.id);
  assert(states[info.occ] && states[info.occ].completedAt, 'detail must complete the occurrence for the browsed day');
  assertNoErrors(page);
  await page.close();
});

/* P1-3 — phone touch targets and their effective hit areas */
scenario('P1-3 phone controls keep a 48px effective hit area', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'tags');
  const tagProbe = await page.evaluate(() => {
    const row = document.querySelector('.list-row');
    const btn = row && row.querySelector('button.icon-btn');
    if (!btn) return null;
    const r = btn.getBoundingClientRect();
    const hit = document.elementFromPoint(r.right - 2, r.top + r.height / 2);
    return { w: Math.round(r.width), h: Math.round(r.height), onEdit: !!(hit && hit.closest('button') === btn) };
  });
  assert(tagProbe, 'tag edit button missing');
  assert(tagProbe.w >= 48 && tagProbe.h >= 48, 'tag edit painted box must be 48: ' + JSON.stringify(tagProbe));
  assert(tagProbe.onEdit, 'the right edge of 编辑 must not be covered by 删除');

  await go(page, 'calendars');
  const calProbe = await page.evaluate(() => {
    const row = document.querySelector('[data-testid="calendar-row"]');
    const btn = row && row.querySelector('button.icon-btn');
    if (!btn) return null;
    const r = btn.getBoundingClientRect();
    const hit = document.elementFromPoint(r.right - 2, r.top + r.height / 2);
    return { w: Math.round(r.width), h: Math.round(r.height), onEdit: !!(hit && hit.closest('button') === btn) };
  });
  assert(calProbe && calProbe.w >= 48 && calProbe.h >= 48 && calProbe.onEdit, 'calendar edit target: ' + JSON.stringify(calProbe));

  await go(page, 'action');
  const headProbe = await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('button')).find((b) => /完整日程|Full schedule/.test(b.textContent));
    if (!btn) return null;
    const r = btn.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.bottom - 2);
    return { h: Math.round(r.height), inside: !!(hit && hit.closest('button') === btn) };
  });
  assert(headProbe && headProbe.h >= 48 && headProbe.inside, 'Today section header control: ' + JSON.stringify(headProbe));

  await go(page, 'todos');
  await completeViaRow(page, '整理评审纪要');
  const toast = await page.evaluate(() => {
    const b = document.querySelector('.toast .undo');
    if (!b) return null;
    const r = b.getBoundingClientRect();
    return { w: Math.round(r.width), h: Math.round(r.height) };
  });
  assert(toast && toast.w >= 48 && toast.h >= 48, 'toast undo target: ' + JSON.stringify(toast));

  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 240);
  await clickTestId(page, 'composer-more');
  const scheduleProbe = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="composer-schedule"]');
    if (!b) return null;
    const r = b.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.bottom - 2);
    return { h: Math.round(r.height), inside: !!(hit && hit.closest('button') === b) };
  });
  assert(scheduleProbe && scheduleProbe.h >= 48 && scheduleProbe.inside, 'composer schedule target: ' + JSON.stringify(scheduleProbe));

  const eventId = await page.evaluate(() => {
    const now = window.U.now();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 10, 0);
    return window.Store.createEvent({ summary: '十五分钟事件', startDt: start, endDt: window.U.addMinutes(start, 15), calendarId: 1 }).id;
  });
  await page.evaluate(() => window.__calendarHelpers.setView('day'));
  await go(page, 'calendar');
  const block = await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    if (!b) return null;
    const r = b.getBoundingClientRect();
    return { h: Math.round(r.height) };
  }, eventId);
  assert(block && block.h >= 48, 'a 15-minute block must be at least 48px tall: ' + JSON.stringify(block));
  assertNoErrors(page);
  await page.close();
});

/* P1-4 — planned blocks sit at their data time on a phone */
scenario('P1-4 phone calendar draws allocations at their real time', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await page.evaluate(() => window.__calendarHelpers.setView('day'));
  await go(page, 'calendar');
  const rows = await page.evaluate(() => {
    const col = document.querySelector('.time-body .daycol');
    if (!col) return null;
    const top = col.getBoundingClientRect().top;
    return Array.from(col.querySelectorAll('.block.alloc')).map((b) => {
      const a = window.Store.state.allocations.find((x) => String(x.id) === b.dataset.id);
      const start = new Date(a.startAt.__date !== undefined ? a.startAt.__date : a.startAt);
      return {
        id: a.id,
        rendered: Math.round(b.getBoundingClientRect().top - top),
        expected: Math.round(((start.getHours() * 60 + start.getMinutes()) / 60 - 6) * 192),
      };
    });
  });
  assert(rows && rows.length > 0, 'no allocations rendered');
  rows.forEach((r) => assert(Math.abs(r.rendered - r.expected) <= 3,
    `allocation ${r.id} drawn at ${r.rendered}px, data says ${r.expected}px`));
  assertNoErrors(page);
  await page.close();
});

/* P1-5 — the dawn fold hides early blocks and drag moves by the delta */
scenario('P1-5 folded dawn hides early blocks and never rewrites their time', async (browser) => {
  const page = await newPage(browser);
  const ids = await page.evaluate(() => {
    const now = window.U.now();
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const early = window.Store.createEvent({
      summary: '凌晨三点事件',
      startDt: new Date(day.getFullYear(), day.getMonth(), day.getDate(), 3, 0),
      endDt: new Date(day.getFullYear(), day.getMonth(), day.getDate(), 4, 0), calendarId: 1,
    });
    const spanning = window.Store.createEvent({
      summary: '跨折叠事件',
      startDt: new Date(day.getFullYear(), day.getMonth(), day.getDate(), 5, 30),
      endDt: new Date(day.getFullYear(), day.getMonth(), day.getDate(), 7, 0), calendarId: 1,
    });
    window.__calendarHelpers.setView('day');
    return { early: early.id, spanning: spanning.id };
  });
  await go(page, 'calendar');
  assert(!(await exists(page, `[data-testid="event-block"][data-id="${ids.early}"]`)),
    'a fully folded early event must not be drawn at 06:00');
  const box = await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    const col = document.querySelector('.time-body .daycol').getBoundingClientRect();
    return {
      x: r.left + 20, y: r.top + r.height / 2,
      top: Math.round(r.top - col.top), h: Math.round(r.height),
    };
  }, ids.spanning);
  assert(box.top <= 2, 'a 05:30 block is clipped to the 06:00 fold, got ' + box.top);
  assert(Math.abs(box.h - 48) <= 3, 'only the visible hour is drawn, got ' + box.h);
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 12, { steps: 4 });
  await page.mouse.up();
  await settle(page, 260);
  const minutes = await page.evaluate((id) => {
    const e = window.Store.eventById(id);
    return e.startDt.getHours() * 60 + e.startDt.getMinutes();
  }, ids.spanning);
  assertEq(minutes, 5 * 60 + 45, 'drag must move the real start by the delta, not snap it to 06:15');
  assertNoErrors(page);
  await page.close();
});

/* P1-6 — a resize with a composer sheet open keeps the visible form live */
scenario('P1-6 composer sheets write into the visible form after a resize', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '跨断点草稿保存');
  await clickTestId(page, 'composer-deadline');
  await page.setViewportSize(MID);
  await settle(page, 320);
  await page.fill('[data-testid="deadline-date"]', await page.evaluate(() => window.U.toInputDate(window.U.now())));
  await page.fill('[data-testid="deadline-time"]', '18:00');
  await clickTestId(page, 'deadline-apply');
  await settle(page, 200);
  const label = await page.textContent('[data-testid="composer-deadline"]');
  assert(/18:00/.test(label), 'visible deadline chip must show 18:00 after the resize, got ' + label);
  const saveLabel = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="composer-save-foot"]');
    return b ? b.textContent : '';
  });
  assert(/18:00/.test(saveLabel), 'save label must include the chosen deadline: ' + saveLabel);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 280);
  const saved = await page.evaluate(() => window.Store.liveTodos().find((x) => x.summary === '跨断点草稿保存'));
  assert(saved, 'todo not saved');
  const due = new Date(saved.dueDate.__date !== undefined ? saved.dueDate.__date : saved.dueDate);
  assertEq([due.getHours(), due.getMinutes()], [18, 0], 'the visible value is what must be saved');

  // AI parse sheet: the same live-form contract.
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 240);
  await page.fill('[data-testid="composer-title"]', '明天下午三点 开会');
  await clickTestId(page, 'composer-ai-parse');
  await page.setViewportSize(DESKTOP);
  await settle(page, 320);
  await clickTestId(page, 'ai-parse-apply');
  await settle(page, 220);
  assertEq(await page.inputValue('[data-testid="composer-title"]'), '开会', 'AI parse must update the visible title');
  const sch = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="composer-schedule"]');
    return b ? b.textContent : '';
  });
  assert(/15:00/.test(sch), 'AI parse must show the parsed schedule in the live form: ' + sch);
  assertNoErrors(page);
  await page.close();
});

/* P1-7 — chat scheduling names a real occurrence of a repeating todo */
scenario('P1-7 chat never writes an occurrence-less allocation for a repeating todo', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'chat');
  await page.fill('[data-testid="chat-input"]', '安排每日站会记录明天上午');
  await page.evaluate(() => document.querySelector('[data-testid="chat-send"]').click());
  await page.waitForSelector('[data-testid="ai-proposal"]', { timeout: 4000 });
  await settle(page, 200);
  await page.evaluate(() => {
    const card = document.querySelector('[data-testid="ai-proposal"]');
    const b = Array.from(card.querySelectorAll('button')).find((x) => !/忽略|Dismiss/.test(x.textContent) && !/应用/.test(x.textContent));
    const apply = b || card.querySelector('button');
    apply.click();
  });
  await settle(page, 260);
  const check = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    const alloc = window.Store.state.allocations.filter((a) => a.todoId === todo.id).pop();
    return { id: alloc && alloc.id, occ: alloc && alloc.occurrenceId, live: alloc ? window.Store.isAllocationLive(alloc) : false };
  });
  assert(check.occ, 'the proposal must write an occurrence for a repeating todo: ' + JSON.stringify(check));
  assert(check.live, 'the written allocation must be visible: ' + JSON.stringify(check));
  assertNoErrors(page);
  await page.close();
});

/* P1-8 — desktop month double-click creates an event */
scenario('P1-8 desktop month double-click opens the event composer', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-month');
  const cell = await page.evaluate(() => {
    const now = window.U.now();
    const cells = Array.from(document.querySelectorAll('.month-cell'));
    const target = cells.find((c) => !c.classList.contains('other') && c.querySelectorAll('.month-event').length === 0
      && Number(c.querySelector('.mday') ? c.querySelector('.mday').textContent : 0) > 20);
    if (!target) return null;
    const r = target.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  });
  assert(cell, 'no empty late-month cell found');
  await page.mouse.dblclick(cell.x, cell.y);
  await settle(page, 320);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assertEq(route, 'composer', 'double-click must open the composer, not drill into the day');
  assertEq(await page.evaluate(() => window.Store.state.composer.kind), 'event', 'double-click creates an event');
  assertNoErrors(page);
  await page.close();
});

/* P2-1 — the save label and the write agree about a planned slot */
scenario('P2-1 a plan set before the repeat is still written to a named occurrence', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '先排时间再设重复');
  await clickTestId(page, 'composer-more');
  await clickTestId(page, 'composer-schedule');
  const today = await page.evaluate(() => window.U.toInputDate(window.U.now()));
  await page.fill('[data-testid="schedule-start"]', today + 'T10:30');
  await clickTestId(page, 'schedule-apply');
  await clickTestId(page, 'composer-repeat');
  await clickText(page, '.sheet .slot-sheet-option', '每天');
  await settle(page, 200);
  const saveLabel = await page.evaluate(() => document.querySelector('[data-testid="composer-save-foot"]').textContent);
  assert(/10:30/.test(saveLabel), 'label must promise the slot it will write: ' + saveLabel);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 300);
  const result = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '先排时间再设重复');
    const alloc = window.Store.state.allocations.filter((a) => a.todoId === todo.id).pop();
    return { occ: alloc && alloc.occurrenceId, live: alloc ? window.Store.isAllocationLive(alloc) : false };
  });
  assert(result.occ && result.live, 'the promised slot must be written and visible: ' + JSON.stringify(result));
  assertNoErrors(page);
  await page.close();
});

/* P2-2 — plan-day never reserves a past slot */
scenario('P2-2 plan this day starts in the future after 09:00', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const late = new Date();
    late.setHours(19, 31, 0, 0);
    window.U.setClockOffset(late.getTime() - Date.now());
    window.App.go('todos');
  });
  await settle(page, 280);
  await clickTestId(page, 'plan-day');
  await settle(page, 260);
  const start = await page.evaluate(() => {
    const s = window.Store.state.composerDraft.scheduleStart;
    return s ? new Date(s.__date !== undefined ? s.__date : s).getTime() : null;
  });
  assert(start, 'plan mode must reserve a slot');
  assert(start > await page.evaluate(() => window.U.now().getTime()), 'the plan slot must be in the future');
  const chip = await page.textContent('[data-testid="composer-schedule"]');
  assert(/20:00/.test(chip), 'plan slot should be 20:00, got ' + chip);
  assertNoErrors(page);
  await page.close();
});

/* P2-3 — completed rows keep an inline undo on every list */
scenario('P2-3 completing in the Todo list leaves a pinned undo there and on Today', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 220);
  await completeViaRow(page, '整理评审纪要');
  assert(await exists(page, '[data-testid="todo-undo"]'), 'the completed Todo row must offer undo');
  const restored = await page.evaluate(() => {
    document.querySelector('[data-testid="todo-undo"]').click();
    const t = window.Store.liveTodos().find((x) => x.summary === '整理评审纪要');
    return !window.Store.isDone(t);
  });
  assert(restored, 'inline undo must reopen the todo');
  await settle(page, 200);
  await completeViaRow(page, '整理评审纪要');
  await go(page, 'action');
  assert(await exists(page, '[data-testid="action-undo"]'), 'Today must show the pinned undo for a completion made in the list');
  assertNoErrors(page);
  await page.close();
});

/* P2-4 — parser week math and midnight */
scenario('P2-4 quick parse resolves 本周/下周 and 晚上12点 correctly', async (browser) => {
  const page = await newPage(browser);
  const result = await page.evaluate(() => {
    const sunday = new Date(2026, 10, 15, 10, 0);
    const pick = (text) => {
      const p = window.QuickParse.parse(text, sunday);
      return p;
    };
    const d = (p) => p.dueDate ? new Date(p.dueDate).toDateString() : (p.start ? new Date(p.start).toDateString() : null);
    const h = (p) => p.start ? new Date(p.start).getHours() : null;
    return {
      thisMonday: d(pick('本周一 开会')),
      nextMonday: d(pick('下周一 开会')),
      midnightHour: h(pick('晚上12点 开会')),
    };
  });
  assertEq(result.thisMonday, new Date(2026, 10, 9).toDateString(), '本周一 from Sunday is the past Monday');
  assertEq(result.nextMonday, new Date(2026, 10, 16).toDateString(), '下周一 from Sunday is tomorrow');
  assertEq(result.midnightHour, 0, '晚上12点 is midnight, not noon');
  assertNoErrors(page);
  await page.close();
});

/* P2-5 — Enter submits the named desktop forms */
scenario('P2-5 Enter submits sync, calendar and AI forms', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'account' });
  await fillTestId(page, 'auth-server', 'https://nas.local:8080');
  await fillTestId(page, 'auth-email', 'chang@example.com');
  await fillTestId(page, 'auth-password', '12345678');
  await page.press('[data-testid="auth-password"]', 'Enter');
  await settle(page, 1100);
  assert(await page.evaluate(() => window.Store.state.account.signedIn), 'Enter must sign in');

  await go(page, 'calendars');
  await clickTestId(page, 'calendars-create');
  await fillTestId(page, 'calendar-name', '回车新建日历');
  await page.press('[data-testid="calendar-name"]', 'Enter');
  await settle(page, 260);
  assert(await page.evaluate(() => !!window.Store.state.calendars.find((c) => c.name === '回车新建日历')), 'Enter must create the calendar');

  await go(page, 'settings', { section: 'advanced' });
  await clickText(page, '.setting-row', 'AI 配置');
  await settle(page, 220);
  assert(await exists(page, '[data-testid="ai-model"]'), 'AI config sheet did not open');
  await page.press('[data-testid="ai-model"]', 'Enter');
  await settle(page, 240);
  assert(!(await exists(page, '[data-testid="ai-model"]')), 'Enter must save and close AI config');
  assertNoErrors(page);
  await page.close();
});

/* P2-6 — the field is 所属日历 */
scenario('P2-6 the calendar field is labelled 所属日历 everywhere', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await clickTestId(page, 'composer-more');
  const form = await page.textContent('[data-testid="composer"]');
  assert(form.includes('所属日历'), 'composer must say 所属日历');
  await clickTestId(page, 'composer-close');
  await settle(page, 200);
  await page.evaluate(() => window.App.openRecord('todo', window.Store.pendingTodos()[0].id));
  await settle(page, 240);
  const detail = await page.textContent('[data-testid="todo-detail"]');
  assert(detail.includes('所属日历'), 'detail must say 所属日历');
  await clickTestId(page, 'detail-calendar-edit');
  await settle(page, 200).catch(() => {});
  const picker = await page.textContent('.sheet');
  assert(picker.includes('所属日历'), 'picker title must say 所属日历');
  assertNoErrors(page);
  await page.close();
});

/* P2-7 — follow-system language is re-resolved on boot */
scenario('P2-7 follow-system language follows the browser on reload', async (browser) => {
  const ctx = await browser.newContext({ viewport: DESKTOP, locale: 'en-US' });
  const page = await ctx.newPage();
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  await page.evaluate(() => {
    localStorage.setItem('dayspark.g0.prefs', JSON.stringify({ lang: 'zh', langPref: 'system' }));
  });
  await page.reload();
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  const resolved = await page.evaluate(() => ({ lang: window.Store.state.lang, pref: window.Store.state.langPref }));
  assertEq(resolved, { lang: 'en', pref: 'system' }, 'a system-language session must boot in the browser language');
  await ctx.close();
});

/* P2-8 — Windows and Linux are not told notifications do not exist */
scenario('P2-8 Windows and Linux notification settings do not claim web-only support', async (browser) => {
  for (const ua of [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  ]) {
    const ctx = await browser.newContext({ viewport: DESKTOP, userAgent: ua });
    const page = await ctx.newPage();
    await page.goto(URL);
    await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
    await page.evaluate(() => window.App.go('settings', { section: 'notifications' }));
    await page.waitForTimeout(240);
    const text = await page.textContent('.page-content');
    assert(!text.includes('网页版不支持此功能'), 'native target must not be told notifications are web-unsupported: ' + ua);
    assert(text.includes('通知权限'), 'the permission row must exist on this platform: ' + ua);
    await ctx.close();
  }
});

/* P2-9 — the 本周六 chip applies the date it names */
scenario('P2-9 the this-week chip and its value are the same day', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const monday = new Date(2026, 10, 16, 10, 0);
    window.U.setClockOffset(monday.getTime() - Date.now());
    window.App.go('todos');
  });
  await settle(page, 280);
  await clickTestId(page, 'todos-create');
  await clickTestId(page, 'composer-deadline');
  const label = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('[data-testid="deadline-quick"]')).find((x) => /本周/.test(x.textContent));
    return b ? b.textContent : null;
  });
  assert(label && /六/.test(label), 'the this-week chip should name Saturday: ' + label);
  await clickText(page, '[data-testid="deadline-quick"]', '本周');
  const due = await page.evaluate(() => {
    const d = window.Store.state.composerDraft.dueDate;
    const x = new Date(d.__date !== undefined ? d.__date : d);
    return { day: x.getDate(), weekday: x.getDay() };
  });
  assertEq(due, { day: 21, weekday: 6 }, '本周六 from Monday 2026-11-16 is 11-21');
  assertNoErrors(page);
  await page.close();
});

/* P2-10 — English calendars fit a phone */
scenario('P2-10 English calendars page has no horizontal overflow at 390', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await page.evaluate(() => window.Store.setLang('en'));
  await go(page, 'calendars');
  const width = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  assert(width.sw <= width.cw, 'calendars overflows: ' + JSON.stringify(width));
  assertNoErrors(page);
  await page.close();
});

/* P2-11 — + 待办 is Quick Create, with 更多 for the full form */
scenario('P2-11 new Todo opens Quick Create and 更多 reveals the full form', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  assert(await exists(page, '[data-testid="composer-deadline"]'), 'Quick Create shows the deadline chip');
  assert(await exists(page, '[data-testid="composer-more"]'), 'Quick Create shows 更多');
  assert(!(await exists(page, '[data-testid="composer-notes"]')), 'notes belong behind 更多');
  const quickSections = await page.evaluate(() => document.querySelectorAll('.form-section-title').length);
  assertEq(quickSections, 1, 'Quick Create shows only the task group');
  await clickTestId(page, 'composer-more');
  const fullSections = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.form-section-title')).map((n) => n.textContent.trim()));
  assertEq(fullSections, ['任务', '时间', '提醒', '整理', '内容'], '更多 must reveal the five sections');
  assert(await exists(page, '[data-testid="composer-notes"]'), '更多 must reveal notes');
  assertNoErrors(page);
  await page.close();
});

/* P3-1 — the search magnifier focuses the field */
scenario('P3-1 tapping the search magnifier focuses the search field', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'search');
  await page.evaluate(() => document.querySelector('.search-box svg').dispatchEvent(new MouseEvent('click', { bubbles: true })));
  await settle(page, 120);
  assertEq(await page.evaluate(() => document.activeElement.dataset.testid), 'search-input', 'magnifier must forward focus');
  assertNoErrors(page);
  await page.close();
});

/* P3-2 — removing AI config says what it removes */
scenario('P3-2 remove-config confirmation describes removal, not absence', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'advanced' });
  await clickText(page, '.setting-row', 'AI 配置');
  await settle(page, 220);
  await clickTestId(page, 'ai-remove');
  await settle(page, 200);
  const text = await page.textContent('.modal');
  assert(!text.includes('还没有配置 AI'), 'a configured provider must not be called unconfigured');
  assert(/移除后|stops working/.test(text), 'the dialog must describe the removal: ' + text);
  assertNoErrors(page);
  await page.close();
});

/* P3-3 — inline day-view quick add names the deadline */
scenario('P3-3 the day-view inline field labels its write as a deadline', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const chip = await page.textContent('.todo-quick .context-chip');
  assert(/截止/.test(chip), 'inline quick add must say it writes a deadline: ' + chip);
  assertNoErrors(page);
  await page.close();
});

/* P3-4 — repeat setup exposes its start */
scenario('P3-4 repeat setup carries 重复开始', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-create');
  await page.fill('[data-testid="composer-title"]', '自定义重复开始');
  await clickTestId(page, 'composer-deadline');
  await clickText(page, '.sheet button', '无截止');
  await clickTestId(page, 'composer-more');
  await clickTestId(page, 'composer-repeat');
  assert(await exists(page, '[data-testid="repeat-start"]'), '重复开始 must exist in repeat setup');
  await page.fill('[data-testid="repeat-start"]', '2026-12-01');
  await settle(page, 160);
  await clickText(page, '.sheet .slot-sheet-option', '每天');
  await settle(page, 200);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 280);
  const saved = await page.evaluate(() => {
    const t = window.Store.liveTodos().find((x) => x.summary === '自定义重复开始');
    const d = t.startDate ? new Date(t.startDate.__date !== undefined ? t.startDate.__date : t.startDate) : null;
    return d ? d.getDate() : null;
  });
  assertEq(saved, 1, 'the chosen repeat start must anchor the series');
  assertNoErrors(page);
  await page.close();
});

/* P3-5 — a far date can be chosen directly */
scenario('P3-5 the date picker reaches a far date in one field', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-date-picker');
  assert(await exists(page, '[data-testid="picker-jump-date"]'), 'the picker needs a direct date field');
  await page.fill('[data-testid="picker-jump-date"]', '2029-06-01');
  await settle(page, 300);
  const day = await page.evaluate(() => {
    const d = window.Store.state.todosView.day;
    return new Date(d.__date !== undefined ? d.__date : d).toDateString();
  });
  assertEq(day, new Date(2029, 5, 1).toDateString(), 'the direct field must land on the chosen date');
  assertNoErrors(page);
  await page.close();
});

/* P3-7 — the resize handle is hittable on a phone */
scenario('P3-7 phone calendar resize handle is larger than 7px', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await getResizeHandle(page);
  async function getResizeHandle(p) {
    await p.evaluate(() => {
      const now = window.U.now();
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 11, 0);
      window.Store.createEvent({ summary: '可调整事件', startDt: start, endDt: window.U.addMinutes(start, 60), calendarId: 1 });
      window.__calendarHelpers.setView('day');
    });
    await go(p, 'calendar');
  }
  const h = await page.evaluate(() => {
    const r = document.querySelector('.time-body .block .resize');
    return r ? Math.round(r.getBoundingClientRect().height) : 0;
  });
  assert(h >= 16, 'the resize handle must be at least 16px tall, got ' + h);
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
  console.log(`\n${passed}/${scenarios.length} round-5 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.err.message.split('\n')[0]));
    process.exit(1);
  }
})();
