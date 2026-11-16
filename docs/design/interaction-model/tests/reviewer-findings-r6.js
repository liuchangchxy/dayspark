/* Round-6 independent reviewer regression suite. Each scenario reproduces a
   finding from the round-6 verdict with real pointer/keyboard input. */
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
async function makeEvent(page, summary, h, m, durMin) {
  return page.evaluate(([name, hour, minute, dur]) => {
    const now = window.U.now();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute);
    return window.Store.createEvent({ summary: name, startDt: start, endDt: window.U.addMinutes(start, dur), calendarId: 1 }).id;
  }, [summary, h, m, durMin]);
}

/* P1-1 — Settings keeps the section the user is working in */
scenario('R6-1 Settings stays in the active section after an in-section action', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'advanced' });
  await clickTestId(page, 'setting-ai-enabled');
  await settle(page, 240);
  assert(await exists(page, '[data-testid="setting-ai-enabled"]'), 'AI switch disappeared after toggling');
  const active = await page.evaluate(() => {
    const b = document.querySelector('.settings-nav-item.on');
    return b ? b.dataset.section : null;
  });
  assertEq(active, 'advanced', 'settings must stay on AI after toggling');

  await go(page, 'settings', { section: 'account' });
  await page.fill('[data-testid="auth-server"]', 'https://nas.local:8080');
  await page.fill('[data-testid="auth-email"]', 'chang@example.com');
  await page.fill('[data-testid="auth-password"]', '12345678');
  await page.press('[data-testid="auth-password"]', 'Enter');
  await settle(page, 1100);
  const active2 = await page.evaluate(() => {
    const b = document.querySelector('.settings-nav-item.on');
    return b ? b.dataset.section : null;
  });
  assertEq(active2, 'account', 'settings must stay on sync after signing in');
  assertNoErrors(page);
  await page.close();
});

/* P1-2 — re-render keeps scroll position */
scenario('R6-2 selecting and dragging do not jump a scrolled surface to the top', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 240);
  const before = await page.evaluate(() => {
    const all = Array.from(document.querySelectorAll('#view *'));
    const sc = all.filter((n) => n.scrollHeight > n.clientHeight + 20).sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
    sc.scrollTop = Math.min(400, sc.scrollHeight - sc.clientHeight - 4);
    const rows = Array.from(document.querySelectorAll('.todo-row'));
    const visible = rows.find((r) => { const x = r.getBoundingClientRect(); return x.top > 120 && x.bottom < window.innerHeight - 80; });
    return { top: sc.scrollTop, cls: sc.className, x: visible.getBoundingClientRect().left + 100, y: visible.getBoundingClientRect().top + 20 };
  });
  assert(before.top > 50, 'the list should scroll before the click');
  await page.mouse.click(before.x, before.y);
  await settle(page, 260);
  const after = await page.evaluate((cls) => {
    const sc = Array.from(document.querySelectorAll('#view *')).find((n) => n.className === cls);
    return { top: sc ? sc.scrollTop : -1, pane: !!document.querySelector('[data-testid="detail-pane-body"]') };
  }, before.cls);
  assert(after.pane, 'the click should open the pane');
  assert(after.top > 40, 'selecting must keep the list scroll position, got ' + after.top);

  await page.setViewportSize(MOBILE);
  await settle(page, 260);
  await page.evaluate(() => window.__calendarHelpers.setView('day'));
  await go(page, 'calendar');
  const drag = await page.evaluate(() => {
    const sc = document.querySelector('[data-testid="time-scroll"]');
    sc.scrollTop = 600;
    const b = document.querySelector('.block.alloc');
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    return { x: r.left + 20, y: r.top + r.height / 2, top: sc.scrollTop };
  });
  await page.mouse.move(drag.x, drag.y);
  await page.mouse.down();
  await page.mouse.move(drag.x, drag.y + 30, { steps: 4 });
  await page.mouse.up();
  await settle(page, 320);
  const calTop = await page.evaluate(() => document.querySelector('[data-testid="time-scroll"]').scrollTop);
  assert(calTop > 200, 'a calendar drag must keep the grid scroll position, got ' + calTop);
  assertNoErrors(page);
  await page.close();
});

/* P1-3 — header create uses the viewed date */
scenario('R6-3 calendar create opens in the viewed week/month', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => /下一段|Next/.test(x.getAttribute('aria-label') || ''));
    b.click();
  });
  await settle(page, 260);
  await clickTestId(page, 'calendar-create');
  const week = await page.evaluate(() => {
    const d = window.Store.state.composer.startDt;
    return { date: new Date(d.__date !== undefined ? d.__date : d).toDateString(), hour: new Date(d.__date !== undefined ? d.__date : d).getHours() };
  });
  const brow = await page.evaluate(() => new Date(window.Store.state.calendarAnchor.__date !== undefined ? window.Store.state.calendarAnchor.__date : window.Store.state.calendarAnchor).toDateString());
  assertEq(week.date, brow, 'week create must use the browsed week');
  assertEq(week.hour, 9, 'a non-today date starts at 09:00');
  await page.evaluate(() => window.App.back());
  await settle(page, 220);
  await clickTestId(page, 'cal-view-month');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('button')).find((x) => /下一段|Next/.test(x.getAttribute('aria-label') || ''));
    b.click();
  });
  await settle(page, 260);
  await clickTestId(page, 'calendar-create');
  const month = await page.evaluate(() => {
    const d = window.Store.state.composer.startDt;
    const x = new Date(d.__date !== undefined ? d.__date : d);
    return { day: x.getDate(), month: x.getMonth(), hour: x.getHours() };
  });
  // The calendar has one browsed date (D-calendar D1). Month create lands on the
  // day being browsed, not on the 1st: a second focus value was the bug D-R2-2 found.
  assertEq(month, { day: new Date(brow).getDate(), month: 11, hour: 9 }, 'month create must land on the browsed day');
  assertNoErrors(page);
  await page.close();
});

/* P1-4 — an allocation block resolves its own day */
scenario('R6-4 clicking an allocation on another day completes that day', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    let day = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    for (let i = 0; i < 7 && !window.Store.matchesRule(todo, day); i++) day = window.U.addDays(day, 1);
    const at = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 12, 0);
    const a = window.Store.createAllocation({
      todoId: todo.id, occurrenceId: window.Store.occurrenceIdFor(todo, day),
      startAt: at, endAt: window.U.addMinutes(at, 60),
    });
    return { alloc: a.id, occ: a.occurrenceId };
  });
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-week');
  await settle(page, 220);
  await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="alloc-block"][data-id="${id}"]`);
    b.scrollIntoView({ block: 'center' });
    b.click();
  }, info.alloc);
  await settle(page, 280);
  assert(await exists(page, '[data-testid="todo-detail"]'), 'the block should open its todo detail');
  await clickTestId(page, 'detail-complete');
  await settle(page, 260);
  const states = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    return todo.occurrenceStates;
  });
  assert(states[info.occ] && states[info.occ].completedAt, 'the clicked block day must be completed');
  assertNoErrors(page);
  await page.close();
});

/* P1-5 — pointercancel aborts a drag */
scenario('R6-5 a cancelled pointer never rewrites a calendar time', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const e = window.Store.liveTodos() && window.Store.state.events.find((x) => x.summary === '与设计师午餐');
    window.__calendarHelpers.setView('day');
    return { id: e.id, start: new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt).getTime() };
  });
  await go(page, 'calendar');
  const box = await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    return { x: r.left + 20, y: r.top + 10, top: b.style.top, h: b.style.height };
  }, info.id);
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 40, { steps: 4 });
  await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    b.dispatchEvent(new PointerEvent('pointercancel', { bubbles: true }));
  }, info.id);
  const after = await page.evaluate((id) => {
    const e = window.Store.eventById(id);
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    return { start: new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt).getTime(), top: b.style.top, moved: b.dataset.moved };
  }, info.id);
  await page.mouse.up();
  await settle(page, 200);
  assertEq(after.start, info.start, 'a cancelled pointer must not move the event');
  assertEq(after.top, box.top, 'a cancelled pointer must restore the visual position');
  assertEq(after.moved, '0', 'the next click must not be swallowed');
  assertNoErrors(page);
  await page.close();
});

/* P1-6 — 15-minute blocks do not overlap */
scenario('R6-6 phone 15-minute blocks are separate and open themselves', async (browser) => {
  const page = await newPage(browser, MOBILE);
  const ids = {};
  ids.a = await makeEvent(page, '十五分钟A', 10, 0, 15);
  ids.b = await makeEvent(page, '十五分钟B', 10, 15, 15);
  ids.c = await makeEvent(page, '十五分钟C', 10, 30, 15);
  await page.evaluate(() => window.__calendarHelpers.setView('day'));
  await go(page, 'calendar');
  const rects = await page.evaluate((ids) => {
    const out = {};
    const first = document.querySelector(`[data-testid="event-block"][data-id="${ids.a}"]`);
    first.scrollIntoView({ block: 'center' });
    [ids.a, ids.b, ids.c].forEach((id) => {
      const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
      const r = b.getBoundingClientRect();
      out[id] = { top: r.top, bottom: r.bottom, left: r.left, width: r.width };
    });
    return out;
  }, ids);
  assert(rects[ids.a].bottom <= rects[ids.b].top + 1, 'A and B overlap');
  assert(rects[ids.b].bottom <= rects[ids.c].top + 1, 'B and C overlap');
  const hit = await page.evaluate((id) => {
    const r = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`).getBoundingClientRect();
    const x = r.left + r.width / 2, y = r.top + r.height / 2;
    const el = document.elementFromPoint(x, y);
    return { x, y, id: el && el.closest('[data-testid="event-block"]') ? el.closest('[data-testid="event-block"]').dataset.id : null };
  }, ids.b);
  assertEq(hit.id, String(ids.b), 'the center of B must hit B');
  await page.mouse.click(hit.x, hit.y);
  await settle(page, 280);
  const title = await page.textContent('[data-testid="event-detail"]');
  assert(title.includes('十五分钟B'), 'tapping B must open B, got ' + title);
  assertNoErrors(page);
  await page.close();
});

/* P1-7 — back-to-now does not cover the bottom nav */
scenario('R6-7 phone back-to-now and the More tab are both reachable', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'calendar');
  const probe = await page.evaluate(() => {
    const more = document.querySelector('[data-testid="tab-more"]').getBoundingClientRect();
    const back = document.querySelector('[data-testid="back-to-now"]').getBoundingClientRect();
    const el = document.elementFromPoint(more.left + more.width / 2, more.top + more.height / 2);
    return {
      centerHitsMore: !!(el && el.closest('[data-testid="tab-more"]')),
      overlap: !(back.right <= more.left || back.left >= more.right || back.bottom <= more.top || back.top >= more.bottom),
    };
  });
  assert(probe.centerHitsMore, 'the More tab center must be the More tab, not the floating pill');
  assert(!probe.overlap, 'the floating pill must not overlap the bottom nav');
  await page.evaluate(() => document.querySelector('[data-testid="tab-more"]').click());
  await settle(page, 220);
  assert(await exists(page, '.menu'), 'tapping More must open its menu');
  assertNoErrors(page);
  await page.close();
});

/* P1-8 — phone header create actions say what they create */
scenario('R6-8 phone create actions carry labels and names', async (browser) => {
  const page = await newPage(browser, MOBILE);
  const grab = async (route, sel) => {
    await go(page, route);
    return page.evaluate((s) => {
      const b = document.querySelector(s);
      if (!b) return null;
      return { text: b.textContent.trim(), aria: b.getAttribute('aria-label') || '' };
    }, sel);
  };
  const today = await grab('action', '.page-actions .btn.primary');
  const calendar = await grab('calendar', '[data-testid="calendar-create"]');
  const todos = await grab('todos', '[data-testid="todos-create"]');
  [['today', today], ['calendar', calendar], ['todos', todos]].forEach(([name, b]) => {
    assert(b && b.text.length > 0, name + ' create action needs visible text');
    assert(b && b.aria.length > 0, name + ' create action needs an accessible name');
  });
  assert(calendar.text !== todos.text, 'calendar and todos creates must not read identically');
  assertNoErrors(page);
  await page.close();
});

/* P1-9 — cancelling the recurrence scope restores the block */
scenario('R6-9 cancelling the scope sheet restores the dragged block', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '周会');
    const day = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    window.__calendarHelpers.setView('day');
    window.__calendarHelpers.setAnchor(day);
    return { id: e.id, start: new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt).getTime() };
  });
  await go(page, 'calendar');
  const box = await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    return { x: r.left + 30, y: r.top + 20, top: b.style.top, h: b.style.height };
  }, info.id);
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 50, { steps: 5 });
  await page.mouse.up();
  await settle(page, 280);
  assert(await exists(page, '.sheet'), 'dragging a repeating occurrence should ask its scope');
  await page.keyboard.press('Escape');
  await settle(page, 280);
  const after = await page.evaluate((id) => {
    const e = window.Store.eventById(id);
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    return { start: new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt).getTime(), top: b.style.top, moved: b.dataset.moved };
  }, info.id);
  assertEq(after.start, info.start, 'cancelling must not move the event');
  assertEq(after.top, box.top, 'cancelling must restore the visual position');
  assertEq(after.moved, '0', 'the next click must not be swallowed');
  await page.evaluate((id) => document.querySelector(`[data-testid="event-block"][data-id="${id}"]`).click(), info.id);
  await settle(page, 240);
  assert(await exists(page, '[data-testid="event-detail"]'), 'the block should still open after cancelling');
  assertNoErrors(page);
  await page.close();
});

/* P2-10 — completing in the pane keeps the pane */
scenario('R6-10 completing a recurring todo in the pane keeps its detail', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.todo-row')).find((r) => r.textContent.includes('每日站会记录'));
    row.click();
  });
  await settle(page, 240);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'pane should open');
  await clickTestId(page, 'detail-complete');
  await settle(page, 300);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'completing the selected recurring todo must not empty the pane');
  const text = await page.textContent('[data-testid="detail-pane-body"]');
  assert(text.includes('每日站会记录'), 'the pane must still show the record');
  assertNoErrors(page);
  await page.close();
});

/* P2-11 — Todo rows are keyboard focusable */
scenario('R6-11 a Todo row can take focus and open with Enter', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 220);
  const focus = await page.evaluate(() => {
    const row = document.querySelector('.todo-row');
    row.focus();
    return { tag: document.activeElement.tagName, tab: row.tabIndex };
  });
  assertEq(focus.tab, 0, 'rows must be in the tab order');
  assert(focus.tag === 'DIV', 'the row should receive focus');
  await page.keyboard.press('Enter');
  await settle(page, 260);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'Enter on a focused row must open its detail');
  assertNoErrors(page);
  await page.close();
});

/* P2-13/P2-14 — Today labels all-day and overdue date-only rows honestly */
scenario('R6-13 Today does not print a clock range for all-day or 今天 for an old date', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const now = window.U.now();
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    window.Store.createEvent({ summary: '全天测试', startDt: day, endDt: new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59), isAllDay: true, calendarId: 1 });
    window.Store.createTodo({ summary: '过期日期测试', dueDate: window.U.addDays(day, -3) });
  });
  await go(page, 'action');
  const allDay = await page.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.row')).find((r) => r.textContent.includes('全天测试'));
    return row ? { time: (row.querySelector('.row-time') || {}).textContent || '', text: row.textContent } : null;
  });
  assert(allDay, 'all-day row missing');
  assert(/全天/.test(allDay.time) && !/00:00|23:59/.test(allDay.text), 'all-day row must not print a clock range: ' + JSON.stringify(allDay));
  const overdue = await page.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.row')).find((r) => r.textContent.includes('过期日期测试'));
    return row ? { time: (row.querySelector('.row-time') || {}).textContent || '' } : null;
  });
  assert(overdue, 'overdue date-only row missing');
  assert(!/今天|Today/.test(overdue.time), 'a date-only overdue row must not claim 今天: ' + overdue.time);
  assertNoErrors(page);
  await page.close();
});

/* P2-15 — deleting a filtered calendar clears the filter */
scenario('R6-15 deleting the filtered calendar does not leave a false empty list', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const cal = window.Store.state.calendars.find((c) => c.name === '家庭');
    window.Store.state.filterCalendarId = cal.id;
    window.Store.deleteCalendar(cal.id, { move: true });
    window.App.go('todos');
    return cal.id;
  });
  await settle(page, 260);
  assertEq(await page.evaluate(() => window.Store.state.filterCalendarId), null, 'the deleted calendar filter must clear');
  const text = await page.textContent('.page-content');
  assert(!/所有事情都处理完了|All caught up/.test(text), 'the list must not claim everything is done');
  assert(await exists(page, '[data-testid="todo-tile"]'), 'remaining todos must still render');
  assertNoErrors(page);
  await page.close();
});

/* P2-16 — English quick add parses English dates and times */
scenario('R6-16 English quick add understands its own example', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.Store.setLang('en'));
  await go(page, 'quickadd');
  await page.fill('[data-testid="quickadd-input"]', 'Meet the designer tomorrow at 3pm for 1 hour');
  await settle(page, 240);
  const preview = await page.textContent('[data-testid="quickadd-preview"]');
  assert(/15:00/.test(preview), 'English 3pm must become 15:00: ' + preview);
  assert(/Meet the designer/i.test(preview), 'the date/time words must leave a clean title: ' + preview);
  assert(/event/i.test(preview), 'a clock time must create an Event: ' + preview);
  const monday = await page.evaluate(() => {
    const p = window.QuickParse.parse('next Monday 10:00 meeting', new Date(2026, 10, 15, 10, 0));
    return new Date(p.start).toDateString();
  });
  assertEq(monday, new Date(2026, 10, 16).toDateString(), 'next Monday from Sunday is tomorrow');
  assertNoErrors(page);
  await page.close();
});

/* P2-17 — an Event can repeat */
scenario('R6-17 the Event form exposes repeat and saves it', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'calendar-create');
  await page.fill('[data-testid="composer-title"]', '每周重复日程');
  assert(await exists(page, '[data-testid="composer-repeat"]'), 'Event form needs a repeat control');
  await clickTestId(page, 'composer-repeat');
  await clickText(page, '.sheet .slot-sheet-option', '每天');
  await settle(page, 200);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 280);
  const rrule = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '每周重复日程');
    return e && e.rrule ? e.rrule.freq : null;
  });
  assertEq(rrule, 'DAILY', 'the Event repeat rule must be saved');
  assertNoErrors(page);
  await page.close();
});

/* P2-19 — no invisible selected row below the split breakpoint */
scenario('R6-19 a selected row is not highlighted when no pane exists', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 220);
  assert(await exists(page, '.md-selected'), 'desktop pane should mark the selected row');
  await page.setViewportSize(MID);
  await settle(page, 320);
  assert(!(await exists(page, '.md-selected')), 'below 1180 there is no pane, so no row may look selected');
  await page.setViewportSize(DESKTOP);
  await settle(page, 320);
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'widening back should restore the pane');
  assertNoErrors(page);
  await page.close();
});

/* P3-21/P3-22 — shell and week-strip names */
scenario('R6-21 phone bottom nav marks More for tools; week arrows are named', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'settings');
  const on = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="tab-more"]');
    return b.classList.contains('on');
  });
  assert(on, 'a tool destination must mark More as the active tab');
  await go(page, 'todos');
  const labels = await page.evaluate(() => Array.from(document.querySelectorAll('.ws-arrow')).map((b) => b.getAttribute('aria-label')));
  assert(labels.length === 2, 'week strip arrows missing');
  assert(/上一周|Previous week/.test(labels[0]), 'previous arrow label: ' + labels[0]);
  assert(!/更多|More/.test(labels[0]), 'previous arrow must not say More');
  assertNoErrors(page);
  await page.close();
});

/* P3-23 — resizing an allocation reports the end, not a fake move */
scenario('R6-23 allocation resize toast reports the resize', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.__calendarHelpers.setView('day'));
  await go(page, 'calendar');
  const box = await page.evaluate(() => {
    const b = document.querySelector('.block.alloc');
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    const handle = b.querySelector('.resize').getBoundingClientRect();
    return { x: r.left + 20, y: handle.top + handle.height / 2, id: b.dataset.id };
  });
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 24, { steps: 4 });
  await page.mouse.up();
  await settle(page, 320);
  const toast = await page.textContent('.toast');
  assert(/调整|Resized/.test(toast), 'resize toast must say it resized: ' + toast);
  assertNoErrors(page);
  await page.close();
});

/* P3-24 — empty calendar name is explained */
scenario('R6-24 creating a calendar with no name explains the problem', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendars');
  await clickTestId(page, 'calendars-create');
  await page.fill('[data-testid="calendar-name"]', '');
  await clickTestId(page, 'calendar-create');
  await settle(page, 200);
  assert(await exists(page, '.modal'), 'the sheet must stay open');
  const err = await page.evaluate(() => {
    const n = document.querySelector('.modal .field-error');
    return n ? n.textContent.trim() : '';
  });
  assert(err.length > 0, 'an empty name must produce an error message');
  assertNoErrors(page);
  await page.close();
});

/* P3-26 — cancelling an edit from the pane returns to the same pane */
scenario('R6-26 cancelling an edit keeps the pane selection', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 240);
  const id = await page.evaluate(() => window.Store.state.paneSelection.id);
  await clickTestId(page, 'detail-edit');
  await settle(page, 240);
  assert(await exists(page, '[data-testid="composer"]'), 'edit composer should open');
  await page.keyboard.press('Escape');
  await settle(page, 280);
  const sel = await page.evaluate(() => window.Store.state.paneSelection);
  assert(sel && Number(sel.id) === Number(id), 'cancelling must keep the pane selection');
  assert(await exists(page, '[data-testid="detail-pane-body"]'), 'cancelling must return to the pane');
  assertNoErrors(page);
  await page.close();
});

/* P3-27 — occurrence checkboxes toast and can undo */
scenario('R6-27 completing an occurrence from the list toasts with undo', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    window.App.openRecord('todo', todo.id);
  });
  await settle(page, 280);
  const clicked = await page.evaluate(() => {
    const row = document.querySelector('[data-testid="detail-occurrence"]');
    if (!row) return false;
    row.querySelector('.hit').click();
    return true;
  });
  assert(clicked, 'occurrence list missing');
  await settle(page, 260);
  assert(await exists(page, '.toast .undo'), 'completing an occurrence must offer undo');
  await page.click('.toast .undo');
  await settle(page, 260);
  const openAgain = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    return todo.occurrenceStates && Object.keys(todo.occurrenceStates).length === 0;
  });
  assert(openAgain, 'undo must reopen the occurrence');
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
  console.log(`\n${passed}/${scenarios.length} round-6 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.err.message.split('\n')[0]));
    process.exit(1);
  }
})();
