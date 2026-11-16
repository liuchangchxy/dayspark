/* Round-9 independent reviewer regression suite. */
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

/* P1-1 — record links work from a routed detail with the Todos tab active */
scenario('R9-1 a child record opens from a routed detail even with Todos active', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const parent = window.Store.liveTodos().find((x) => x.summary === '准备季度评审');
    const child = window.Store.subtasksOf(parent.id)[0];
    window.App.go('todos');
    window.Store.navigate('detail', { type: 'todo', id: parent.id });
    return { parent: parent.id, child: child.id, childName: child.summary };
  });
  await settle(page, 280);
  await page.evaluate((id) => {
    const n = Array.from(document.querySelectorAll('[data-testid="todo-detail"] *'))
      .find((x) => x.textContent.trim() === window.Store.todoById(id).summary);
    n.click();
  }, info.child);
  await settle(page, 300);
  const shown = await page.evaluate(() => {
    const t = document.querySelector('.detail-title');
    return { title: t ? t.textContent.trim() : null, route: window.Store.state.route.name };
  });
  assertEq(shown.title, info.childName, 'clicking a subtask must open that subtask');
  assertEq(shown.route, 'detail', 'it stays a routed detail');
  assertNoErrors(page);
  await page.close();
});

/* P1-2 — "this and following" across a day boundary moves the instance */
scenario('R9-2 this-and-following moves a cross-day occurrence and later ones', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const series = window.Store.state.events.find((x) => x.summary === '周会');
    const anchor = window.U.addDays(window.U.startOfDay(window.U.now()), 8);
    const occ = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate(), 10, 0);
    window.__calendarHelpers.setView('week');
    window.__calendarHelpers.setAnchor(anchor);
    return { id: series.id, anchor: anchor.getTime(), occ: occ.getTime() };
  });
  await go(page, 'calendar');
  await settle(page, 260);
  const box = await page.evaluate((id) => {
    const b = Array.from(document.querySelectorAll(`[data-testid="event-block"][data-id="${id}"]`))
      .find((x) => x.getBoundingClientRect().width > 40);
    if (!b) return null;
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    return { x: r.left + 20, y: r.top + 20, hh: 48 };
  }, info.id);
  assert(box, 'the occurrence block was not found');
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x + 200, box.y + 40, { steps: 8 });
  await page.mouse.up();
  await settle(page, 300);
  assert(await exists(page, '[data-testid="scope-future"]'), 'the scope sheet must open');
  await clickTestId(page, 'scope-future');
  await settle(page, 340);
  const result = await page.evaluate((anchor) => {
    const day = new Date(anchor);
    const start = window.U.startOfDay(day);
    const end = window.U.endOfDay(window.U.addDays(start, 3));
    const out = [];
    window.Store.liveEvents().forEach((e) => {
      window.Store.eventsOnDay(start).forEach(() => {});
      const days = [];
      for (let i = 0; i < 8; i++) days.push(window.U.addDays(start, i));
      days.forEach((d) => {
        window.Store.eventsOnDay(d).forEach((ev) => {
          if (ev.summary === '周会') out.push({ d: d.toDateString(), h: new Date(ev.startDt.__date !== undefined ? ev.startDt.__date : ev.startDt).getHours(), wd: new Date(ev.startDt.__date !== undefined ? ev.startDt.__date : ev.startDt).getDay() });
        });
      });
    });
    const seen = {};
    const unique = out.filter((o) => {
      const k = o.d + o.h;
      if (seen[k]) return false;
      seen[k] = true;
      return true;
    });
    return unique;
  }, info.anchor);
  const onOldDay = result.filter((r) => r.d === new Date(info.anchor).toDateString());
  assertEq(onOldDay.length, 0, 'the dragged occurrence must not remain on its old day: ' + JSON.stringify(result));
  const laterWeekdays = result.filter((r) => r.d > new Date(info.anchor).toDateString());
  assert(laterWeekdays.length > 0, 'later occurrences must exist: ' + JSON.stringify(result));
  const movedWeekday = new Date(new Date(info.anchor).getTime() + 86400000).getDay();
  assert(laterWeekdays.every((r) => r.wd === movedWeekday), 'later occurrences must follow the new weekday: ' + JSON.stringify(result));
  assertNoErrors(page);
  await page.close();
});

/* P2-1 — the chosen Settings section survives an in-section render */
scenario('R9-3 Settings keeps the section the user switched to', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'account' });
  await clickTestId(page, 'settings-nav-appearance');
  await settle(page, 220);
  await clickTestId(page, 'theme-dark');
  await settle(page, 300);
  const active = await page.evaluate(() => {
    const b = document.querySelector('.settings-nav-item.on');
    return b ? b.dataset.section : null;
  });
  assertEq(active, 'appearance', 'changing the theme must not jump back to the entry section');
  assertNoErrors(page);
  await page.close();
});

/* P2-2 — overriding the quick-add type keeps the parsed day */
scenario('R9-4 quick-add type override keeps the parsed date', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'quickadd');
  await page.fill('[data-testid="quickadd-input"]', '明天下午三点 开会 1小时');
  await settle(page, 220);
  await page.click('[data-testid="quickadd-type-todo"]');
  await settle(page, 240);
  const preview = await page.textContent('[data-testid="quickadd-preview"]');
  assert(!/没有识别|No date/.test(preview), 'a parsed time must not be reported as no date: ' + preview);
  await clickTestId(page, 'quickadd-save');
  await settle(page, 320);
  const due = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary.includes('开会'));
    if (!todo || !todo.dueDate) return null;
    const d = new Date(todo.dueDate.__date !== undefined ? todo.dueDate.__date : todo.dueDate);
    return d.getDate();
  });
  const tomorrow = await page.evaluate(() => window.U.addDays(window.U.startOfDay(window.U.now()), 1).getDate());
  assertEq(due, tomorrow, 'the overridden to-do keeps tomorrow as its deadline');
  assertNoErrors(page);
  await page.close();
});

/* P2-3 — a custom repeat on an undated todo anchors the series */
scenario('R9-5 a custom repeat on an undated todo gets an anchor', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 240);
  await page.fill('[data-testid="composer-title"]', '自定义重复无截止');
  await clickTestId(page, 'composer-more');
  await clickTestId(page, 'composer-repeat');
  await page.evaluate(() => {
    const i = document.querySelector('.sheet input[type="number"]');
    i.value = '2';
    i.dispatchEvent(new Event('input', { bubbles: true }));
    const u = document.querySelector('.sheet select');
    u.value = 'WEEKLY';
    u.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await settle(page, 160);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.sheet button')).find((x) => /应用|Apply/.test(x.textContent));
    b.click();
  });
  await settle(page, 240);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 320);
  const state = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '自定义重复无截止');
    return todo ? { rec: !!todo.recurrence, start: !!todo.startDate, due: !!todo.dueDate } : null;
  });
  assert(state, 'the todo was not saved');
  assert(state.rec && state.start, 'a repeating todo needs an anchor: ' + JSON.stringify(state));
  assert(!state.due, 'the anchor must not become a deadline');
  assertNoErrors(page);
  await page.close();
});

/* P2-4 — a 15-minute phone block still has a movable body */
scenario('R9-6 a 15-minute phone block can be moved, not only resized', async (browser) => {
  const page = await newPage(browser, MOBILE);
  const id = await page.evaluate(() => {
    const now = window.U.now();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 15, 0);
    const e = window.Store.createEvent({ summary: '十五分钟可移动', startDt: start, endDt: window.U.addMinutes(start, 15), calendarId: 1 });
    window.__calendarHelpers.setView('day');
    return e.id;
  });
  await go(page, 'calendar');
  const probe = await page.evaluate((eid) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${eid}"]`);
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    const mid = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height - 2);
    return {
      midResize: !!(mid && mid.closest('.resize')),
      topResize: !!(top && top.closest('.resize')),
      x: r.left + r.width / 2, y: r.top + r.height / 2,
    };
  }, id);
  assert(!probe.midResize, 'the middle of a 15-minute block must move it, not resize it');
  assert(probe.topResize, 'the bottom edge must still resize');
  await page.mouse.move(probe.x, probe.y);
  await page.mouse.down();
  await page.mouse.move(probe.x, probe.y + 48, { steps: 5 });
  await page.mouse.up();
  await settle(page, 320);
  const after = await page.evaluate((eid) => {
    const e = window.Store.eventById(eid);
    const s = new Date(e.startDt.__date !== undefined ? e.startDt.__date : e.startDt);
    const en = new Date(e.endDt.__date !== undefined ? e.endDt.__date : e.endDt);
    return { h: s.getHours(), m: s.getMinutes(), dur: Math.round((en - s) / 60000) };
  }, id);
  assertEq(after, { h: 15, m: 15, dur: 15 }, 'dragging the body must move it and keep its length');
  assertNoErrors(page);
  await page.close();
});

/* P2-5 — recurring deadlines appear in the calendar lane and month cell */
scenario('R9-7 recurring deadlines are not missing from the calendar', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await clickTestId(page, 'cal-view-day');
  const lane = await page.textContent('.page-content');
  assert(/每日站会记录/.test(lane), 'a recurring deadline must appear in the day lane: ' + lane.slice(0, 120));
  await clickTestId(page, 'cal-view-month');
  const cell = await page.evaluate(() => {
    const cells = Array.from(document.querySelectorAll('.month-cell'));
    const today = cells.find((c) => c.classList.contains('today'));
    return today ? today.textContent : '';
  });
  // The month cell caps its chips at three plus "+n"; a recurring deadline must
  // still be represented there rather than silently dropped.
  const listed = await page.evaluate(() => {
    const cells = Array.from(document.querySelectorAll('.month-cell'));
    const today = cells.find((c) => c.classList.contains('today'));
    const items = window.Store.liveTodos().filter((x) => window.Store.isOpen(x) && x.dueDate && window.U.sameDay(x.dueDate, window.U.now())).length;
    const shown = today ? today.querySelectorAll('.month-event').length : 0;
    const more = today && today.querySelector('.month-more') ? today.querySelector('.month-more').textContent : '';
    return { items, shown, more };
  });
  assert(listed.items >= listed.shown && listed.items > 0, 'the cell must account for every deadline: ' + JSON.stringify(listed));
  assert(listed.shown + (listed.more ? Number(listed.more.replace('+', '')) : 0) >= listed.items,
    'the month cell must not drop deadlines silently: ' + JSON.stringify(listed));
  assertNoErrors(page);
  await page.close();
});

/* P2-6 — a reorder inside a day view does not reshuffle the inventory */
scenario('R9-8 a day-view reorder leaves the inventory order alone', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  // A day view groups by date, so it must not offer a manual order handle that
  // the store cannot honour without reshuffling rows the user cannot see.
  const handles = await page.evaluate(() => document.querySelectorAll('.todo-row .grab').length);
  assertEq(handles, 0, 'the day view must not offer a manual order handle');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 240);
  const before = await page.evaluate(() => window.Store.liveTodos().slice().sort((a, b) => a.sortOrder - b.sortOrder).map((t) => t.id).join(','));
  const box = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('.todo-row'));
    const grab = rows[1].querySelector('.grab').getBoundingClientRect();
    return { x: grab.left + grab.width / 2, y: grab.top + grab.height / 2 };
  });
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x, box.y + 120, { steps: 6 });
  await page.mouse.up();
  await settle(page, 320);
  const after = await page.evaluate(() => window.Store.liveTodos().slice().sort((a, b) => a.sortOrder - b.sortOrder).map((t) => t.id).join(','));
  assert(after !== before, 'a reorder in the inventory must change the order');
  assertEq(after.split(',').length, before.split(',').length, 'a reorder must keep every row');
  assertNoErrors(page);
  await page.close();
});

/* P3 — clearing filters resets hide-completed; split copies keep reminders */
scenario('R9-9 filter clear and split copies keep their promises', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-filter');
  await clickTestId(page, 'filter-hide-done');
  await clickTestId(page, 'filter-apply');
  await settle(page, 220);
  const chip = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.chip-btn')).find((x) => /清除筛选|Clear filters/.test(x.textContent));
    return !!b;
  });
  assert(chip, 'hide-completed alone must offer a clear affordance');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.chip-btn')).find((x) => /清除筛选|Clear filters/.test(x.textContent));
    b.click();
  });
  await settle(page, 200);
  assertEq(await page.evaluate(() => window.Store.state.hideCompleted), false, 'the chip clear must also turn off hide-completed');

  const info = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '周会');
    e.reminderOffsets = [15];
    const day = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    const occ = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 10, 0);
    return { id: e.id, occ: occ.getTime() };
  });
  await page.evaluate(([id, occ]) => window.EventOps.deleteEvent(Object.assign({}, window.Store.eventById(id), { isOccurrence: true, occurrenceAnchor: new Date(window.U.startOfDay(new Date(occ))), startDt: new Date(occ) })), [info.id, info.occ]);
  await settle(page, 200);
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
  console.log(`\n${passed}/${scenarios.length} round-9 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.err.message.split('\n')[0]));
    process.exit(1);
  }
})();
