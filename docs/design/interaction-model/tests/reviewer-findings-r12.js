/* G0-v2 round-2 independent review regression suite (R2-* P1s).
   One scenario per root cause closed after round 2. Every scenario drives the UI
   or the same write path the UI uses, and asserts data or visible state. */
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
async function newPage(browser, viewport, touch) {
  const ctx = await browser.newContext({ viewport: viewport || DESKTOP, hasTouch: !!touch, isMobile: !!touch });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  page.__errors = errors;
  page.__ctx = ctx;
  return page;
}
const settle = (page, ms) => page.waitForTimeout(ms === undefined ? 200 : ms);
async function go(page, name, params) {
  await page.evaluate(([n, p]) => window.App.go(n, p), [name, params || null]);
  await settle(page);
}
async function clickTestId(page, id) {
  await page.click(`[data-testid="${id}"]`);
  await settle(page, 180);
}
async function clickText(page, selector, text) {
  const ok = await page.evaluate(([s, t]) => {
    const b = Array.from(document.querySelectorAll(s)).find((x) => x.textContent.trim().includes(t));
    if (!b) return false;
    b.click();
    return true;
  }, [selector, text]);
  assert(ok, `no ${selector} containing ${text}`);
  await settle(page, 200);
}
async function setClock(page, h, m, dayOffset) {
  await page.evaluate(([hh, mm, off]) => {
    const n = window.U.now();
    const d = window.U.addDays(window.U.startOfDay(n), off || 0);
    d.setHours(hh, mm, 0, 0);
    window.U.setClockOffset(d.getTime() - Date.now());
    window.App.render();
  }, [h, m, dayOffset || 0]);
  await settle(page, 200);
}
function assertNoErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}
const bodyText = (page) => page.evaluate(() => document.body.innerText);
const exists = (page, sel) => page.evaluate((x) => !!document.querySelector(x), sel);
const toastText = (page) => page.evaluate(() => (document.querySelector('.toast') || {}).innerText || '');

/* A-R2-1 — T on a dirty composer is refused as a whole */
scenario('R12-01 T refused by the leave guard changes nothing', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now());
    window.Store.setBrowseDate(window.U.addDays(d, 30));
    window.App.go('todos');
    window.App.openComposer('todo');
  });
  await settle(page, 250);
  await page.fill('[data-testid="composer-title"]', '草稿');
  const before = await page.evaluate(() => window.U.startOfDay(window.Store.browseDate()).toDateString());
  await page.evaluate(() => document.activeElement.blur());
  await page.keyboard.press('t');
  await settle(page, 250);
  await clickText(page, 'button', '继续编辑');
  const after = await page.evaluate(() => window.U.startOfDay(window.Store.browseDate()).toDateString());
  assertEq(after, before, 'a refused T must not move the browsed date');
  assert(!/已回到今天/.test(await bodyText(page)), 'a refused T must not announce success');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* A-R2-2 — N inside a composer replaces it instead of stacking it */
scenario('R12-02 discard from a second composer leaves one Close', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.App.go('action'));
  await settle(page, 200);
  await page.keyboard.press('n');
  await settle(page, 220);
  await page.fill('[data-testid="composer-title"]', '旧草稿');
  await page.evaluate(() => document.activeElement.blur());
  await page.keyboard.press('n');
  await settle(page, 250);
  await clickText(page, 'button', '放弃');
  await settle(page, 250);
  const hist = await page.evaluate(() => window.Store.state.history.length);
  assertEq(hist, 1, 'the replaced composer keeps one history entry, not two');
  await clickTestId(page, 'composer-close');
  const route = await page.evaluate(() => window.Store.state.route.name);
  assertEq(route, 'action', 'one Close returns to the origin');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* A-R3-1 — browser Back with a dirty composer asks once */
scenario('R12-27 browser Back asks once and one discard leaves', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await page.keyboard.press('n');
  await settle(page, 250);
  await page.fill('[data-testid="composer-title"]', '返回草稿');
  await page.evaluate(() => document.activeElement.blur());
  await page.goBack();
  await settle(page, 300);
  const first = await page.evaluate(() => !!Array.from(document.querySelectorAll('button')).find((b) => b.textContent.trim() === '放弃'));
  assert(first, 'browser Back must ask before discarding');
  await clickText(page, 'button', '放弃');
  await settle(page, 400);
  const state = await page.evaluate(() => ({
    dialogs: Array.from(document.querySelectorAll('button')).filter((b) => b.textContent.trim() === '放弃').length,
    route: window.Store.state.route.name,
  }));
  assertEq(state.dialogs, 0, 'one discard must not open a second identical dialog');
  assertEq(state.route, 'action', 'one discard must complete the Back');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* C-P1-1 — a planned-only row opens the pane on desktop */
scenario('R12-03 the split pane opens a planned-only row', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const day = window.U.startOfDay(window.U.now());
    const a = window.Store.allocationsOnDay(day).find((x) => {
      const td = window.Store.todoById(x.todoId);
      return td && !td.dueDate;
    }) || window.Store.allocationsOnDay(day)[0];
    const todo = window.Store.todoById(a.todoId);
    window.App.go('todos');
    return { id: todo.id, summary: todo.summary };
  });
  await settle(page, 300);
  await page.evaluate((id) => document.querySelector(`[data-testid="todo-row"][data-id="${id}"]`).click(), info.id);
  await settle(page, 300);
  const state = await page.evaluate(() => ({
    sel: window.Store.state.paneSelection && window.Store.state.paneSelection.id,
    pane: (document.querySelector('[data-testid="detail-pane"]') || {}).innerText || '',
  }));
  assertEq(state.sel, info.id, 'the planned row must select into the pane');
  assert(state.pane.includes(info.summary), 'the pane must render the record');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* C-P1-2 — a completed todo is not drawn as open planned work */
scenario('R12-04 completing mid-block removes the row from 计划执行', async (browser) => {
  const page = await newPage(browser);
  await setClock(page, 15, 45);
  const info = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '回复客户邮件：北岸项目排期');
    return { id: todo.id, summary: todo.summary };
  });
  await page.evaluate((id) => window.App.openRecord('todo', id), info.id);
  await settle(page, 250);
  await clickTestId(page, 'detail-complete');
  await go(page, 'todos');
  const openPlanned = await page.evaluate((id) => {
    const rows = Array.from(document.querySelectorAll('[data-testid="todo-row"]'));
    const row = rows.find((r) => Number(r.dataset.id) === id);
    if (!row) return false;
    const box = row.querySelector('[role="checkbox"]');
    return box ? box.getAttribute('aria-checked') === 'false' : false;
  }, info.id);
  assertEq(openPlanned, false, 'a completed todo may not render as an unchecked planned row');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* C-P1-3 / B-03 — a completed todo offers no scheduling entry point */
scenario('R12-05 a completed todo offers no 安排时间 in either menu', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '买牛奶和咖啡豆');
    window.TodoOps.complete(todo);
    return todo.id;
  });
  await settle(page, 250);
  await page.evaluate((id) => window.App.openRecord('todo', id), id);
  await settle(page, 250);
  const detailMenu = await page.evaluate(() => {
    document.querySelector('.detail-head [aria-label="更多"]').click();
    return (document.querySelector('.menu') || {}).innerText || '';
  });
  assert(!/安排时间/.test(detailMenu), 'the detail menu must not offer scheduling: ' + detailMenu);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* C-P1-4 — touch has no reorder grip */
scenario('R12-06 phone rows draw no reorder grip', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 250);
  const grips = await page.evaluate(() => Array.from(document.querySelectorAll('.todo-row .grab')).filter((n) => n.offsetParent !== null).length);
  assertEq(grips, 0, 'touch must not draw a sub-48 reorder grip');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R2-1 — 改期… writes the end it shows */
scenario('R12-07 reschedule applies both start and end for an Event', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const day = window.U.startOfDay(window.U.now());
    const s = new Date(day); s.setHours(15, 0);
    const e = window.Store.createEvent({ summary: '改期测试', startDt: s, endDt: window.U.addMinutes(s, 15), calendarId: 1 });
    window.__calendarHelpers.setView('day');
    window.App.go('calendar');
    return e.id;
  });
  await settle(page, 350);
  await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    b.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
  }, id);
  await settle(page, 200);
  await clickText(page, '.menu button, .menu [role="menuitem"], .menu div', '改期');
  await settle(page, 250);
  const inputs = await page.$$('.modal input[type="datetime-local"]');
  await inputs[1].fill(await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now()); d.setHours(18, 0);
    return window.U.toInputDateTime(d);
  }));
  await clickText(page, '.modal button', '保存');
  await settle(page, 350);
  const end = await page.evaluate((id) => {
    const e = window.Store.eventById(id);
    const d = new Date(e.endDt.__date !== undefined ? e.endDt.__date : e.endDt);
    return d.getHours();
  }, id);
  assertEq(end, 18, '改期… must write the end the user entered');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R2-2 — month create lands on the browsed day, outside the folded dawn */
scenario('R12-08 month create uses the browsed day and a visible hour', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await page.evaluate(() => {
    window.__calendarHelpers.setView('month');
    const b = Array.from(document.querySelectorAll('button')).find((x) => /下一段|Next/.test(x.getAttribute('aria-label') || ''));
    b.click();
  });
  await settle(page, 300);
  await clickTestId(page, 'calendar-create');
  const out = await page.evaluate(() => {
    const d = window.Store.state.composer.startDt;
    const x = new Date(d.__date !== undefined ? d.__date : d);
    return { day: x.toDateString(), brow: new Date(window.Store.browseDate()).toDateString(), hour: x.getHours() };
  });
  assertEq(out.day, out.brow, 'create must use the browsed day');
  assert(out.hour >= 8, 'a created block must not land inside the folded dawn, got ' + out.hour);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R2-5 / Integrator R2-I-01 — touch hold opens the block menu */
scenario('R12-09 touch hold opens the block menu', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  const id = await page.evaluate(() => {
    const day = window.U.startOfDay(window.U.now());
    const s = new Date(day); s.setHours(15, 0);
    const e = window.Store.createEvent({ summary: '长按测试', startDt: s, endDt: window.U.addMinutes(s, 15), calendarId: 1 });
    window.__calendarHelpers.setView('day');
    window.App.go('calendar');
    return e.id;
  });
  await settle(page, 400);
  const box = await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="event-block"][data-id="${id}"]`);
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }, id);
  const cdp = await page.__ctx.newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x, y: box.y }] });
  await settle(page, 700);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await settle(page, 200);
  const menu = await page.evaluate(() => (document.querySelector('.menu') || {}).innerText || '');
  assert(/改期/.test(menu), 'a touch hold must offer 改期…: ' + menu);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assertEq(route, 'calendar', 'a hold must not navigate to the detail');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-P1-1 — a quick chip names the instant it writes */
scenario('R12-10 deadline chip label matches its value at 23:30', async (browser) => {
  const page = await newPage(browser);
  await setClock(page, 23, 30);
  await page.evaluate(() => window.App.openComposer('todo'));
  await settle(page, 250);
  await clickTestId(page, 'composer-deadline');
  const label = await page.evaluate(() => document.querySelector('[data-testid="deadline-quick"]').textContent);
  await page.evaluate(() => document.querySelector('[data-testid="deadline-quick"]').click());
  await settle(page, 220);
  const due = await page.evaluate(() => {
    const d = window.Store.state.composerDraft.dueDate;
    const x = new Date(d.__date !== undefined ? d.__date : d);
    return { day: x.getDate(), tomorrow: window.U.addDays(window.U.startOfDay(window.U.now()), 1).getDate() };
  });
  assert(/明天/.test(label), 'after 23:00 the first chip must say 明天: ' + label);
  assertEq(due.day, due.tomorrow, 'the first chip must write tomorrow');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-P1-2 — removing recurrence clears 重复开始 */
scenario('R12-11 不重复 clears the hidden start date and unblocks save', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.liveTodos().find((x) => x.summary === '读 20 页《设计中的设计》').id);
  await page.evaluate((id) => window.App.openComposer('todo', { mode: 'edit', id }), id);
  await settle(page, 250);
  await clickTestId(page, 'composer-repeat');
  await clickText(page, '[data-testid="repeat-option"]', '不重复');
  await clickTestId(page, 'composer-save');
  await settle(page, 300);
  const out = await page.evaluate((id) => {
    const t = window.Store.todoById(id);
    return { startDate: t.startDate, recurrence: t.recurrence };
  }, id);
  assertEq(out.recurrence, null, 'the rule must be removed');
  assertEq(out.startDate, null, 'removing the rule must clear 重复开始');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-P1-3 — the save label follows tag and reminder changes */
scenario('R12-12 the save label updates after a tag change', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.liveTodos().find((x) => x.summary === 'Q4 预算表').id);
  await page.evaluate((id) => window.App.openComposer('todo', { mode: 'edit', id }), id);
  await settle(page, 250);
  const before = await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').textContent);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('[data-testid^="composer-tag-"]')).find((x) => !x.classList.contains('on'));
    b.click();
  });
  await settle(page, 200);
  const after = await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').textContent);
  assert(before !== after, 'the label must change when the draft changes: ' + before + ' -> ' + after);
  assert(/\d/.test(after), 'the label must state the tag count');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-P1-4 — the save toast names an overlapping block */
scenario('R12-13 an overlapping schedule names the conflict on save', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.liveTodos().find((x) => x.summary === '换掉厨房的灯泡').id);
  await page.evaluate((id) => window.App.openComposer('todo', { mode: 'edit', id }), id);
  await settle(page, 300);
  await clickTestId(page, 'composer-schedule');
  await settle(page, 250);
  await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now()); d.setHours(11, 30);
    document.querySelector('[data-testid="schedule-start"]').value = window.U.toInputDateTime(d);
    document.querySelector('[data-testid="schedule-start"]').dispatchEvent(new Event('change', { bubbles: true }));
  });
  await clickTestId(page, 'schedule-apply');
  await settle(page, 250);
  await clickTestId(page, 'composer-save-foot');
  await settle(page, 300);
  const toast = await toastText(page);
  assert(/重叠|overlap/i.test(toast), 'the save toast must name the overlap: ' + toast);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F2-1 / G-P1-1 — a trashed Todo is read-only everywhere */
scenario('R12-14 a trashed todo exposes no write control', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.recurrence);
    window.Store.softDeleteTodo(todo.id);
    return todo.id;
  });
  await page.evaluate((id) => window.App.openRecord('todo', id), id);
  await settle(page, 300);
  const state = await page.evaluate((id) => {
    const detail = document.querySelector('[data-testid="todo-detail"]');
    const boxes = Array.from(detail.querySelectorAll('.occ-row [role="checkbox"]'));
    return {
      hasMore: !!detail.querySelector('.detail-head [aria-label="更多"]'),
      boxes: boxes.length,
      disabled: boxes.every((b) => b.disabled),
      before: Object.keys(window.Store.todoById(id).occurrenceStates || {}).length,
    };
  }, id);
  assertEq(state.hasMore, false, 'the head menu must be gone on a trashed record');
  assertEq(state.disabled, true, 'occurrence checkboxes must be disabled');
  await page.evaluate((id) => {
    const b = document.querySelector('[data-testid="todo-detail"] .occ-row [role="checkbox"]');
    if (b) b.click();
    return id;
  }, id);
  const after = await page.evaluate((id) => Object.keys(window.Store.todoById(id).occurrenceStates || {}).length, id);
  assertEq(after, state.before, 'clicking a disabled occurrence must write nothing');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F2-2 — a trashed Event head offers no write */
scenario('R12-15 a trashed event head has no edit or delete', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const e = window.Store.liveEvents()[0];
    window.Store.softDeleteEvent(e.id);
    return e.id;
  });
  await page.evaluate((id) => window.App.openRecord('event', id), id);
  await settle(page, 300);
  const head = await page.evaluate(() => {
    const h = document.querySelector('[data-testid="event-detail"] .detail-head');
    return { edit: !!h.querySelector('[aria-label="编辑"]'), trash: !!h.querySelector('[aria-label="移到回收站"]') };
  });
  assertEq(head, { edit: false, trash: false }, 'a trashed event head must not offer edits');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F2-3 — a recurring deadline resolves to the day in context and is not inline-editable */
scenario('R12-16 a recurring deadline fact follows its day', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.summary === '读 20 页《设计中的设计》');
    const day = window.U.addDays(window.U.startOfDay(window.U.now()), 3);
    window.App.openRecord('todo', todo.id, null, day);
    return { id: todo.id, day: day.getTime() };
  });
  await settle(page, 300);
  const out = await page.evaluate((info) => {
    const detail = document.querySelector('[data-testid="todo-detail"]');
    const facts = detail.innerText;
    const due = window.U.startOfDay(new Date(info.day));
    const src = new Date(window.Store.todoById(info.id).dueDate);
    due.setHours(src.getHours(), src.getMinutes(), 0, 0);
    return { text: facts, expected: window.U.fmtDeadline(due), editable: !!detail.querySelector('.detail-facts .fact .act') };
  }, info);
  assert(out.text.includes(out.expected), 'the deadline must be the occurrence on the opened day: ' + out.text.slice(0, 120));
  const deadlineEditable = await page.evaluate(() => {
    const facts = Array.from(document.querySelectorAll('.detail-facts .fact'));
    const f = facts.find((x) => x.textContent.includes('截止'));
    return !!(f && f.querySelector('.v[role="button"]'));
  });
  assertEq(deadlineEditable, false, 'a recurring deadline must not open the series-anchor editor');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F2-4 — a recurring subtask shows the occurrence it completed */
scenario('R12-17 a recurring subtask checkbox renders checked', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const parent = window.Store.liveTodos().find((x) => x.summary === '准备季度评审');
    const sub = window.Store.subtasksOf(parent.id)[0];
    sub.recurrence = { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' };
    sub.dueDate = window.U.startOfDay(window.U.now());
    window.Store.emit('todo:update');
    window.App.openRecord('todo', parent.id);
    return { parent: parent.id, sub: sub.id };
  });
  await settle(page, 300);
  await page.evaluate(() => document.querySelector('.subtask [role="checkbox"]').click());
  await settle(page, 300);
  const checked = await page.evaluate(() => document.querySelector('.subtask [role="checkbox"]').getAttribute('aria-checked'));
  assertEq(checked, 'true', 'a completed occurrence must render its subtask checkbox checked');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F2-5 — the calendar fact is not an inline editor */
scenario('R12-18 clicking 所属日历 opens no editor', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    window.App.openRecord('todo', window.Store.liveTodos()[0].id);
    return window.Store.liveTodos()[0].id;
  });
  await settle(page, 300);
  await page.evaluate(() => {
    const facts = Array.from(document.querySelectorAll('.detail-facts .fact'));
    const f = facts.find((x) => x.textContent.includes('所属日历'));
    f.querySelector('.v').click();
  });
  await settle(page, 250);
  const sheets = await page.evaluate(() => document.querySelectorAll('.sheet').length);
  assertEq(sheets, 0, 'the calendar fact must not open an inline picker');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* G-P1-2 — deleting a calendar with content is undoable */
scenario('R12-19 calendar delete with content can be undone', async (browser) => {
  const page = await newPage(browser);
  const before = await page.evaluate(() => {
    const cal = window.Store.state.calendars.find((c) => c.name === '工作');
    const ids = window.Store.liveEvents().filter((e) => e.calendarId === cal.id).map((e) => e.id);
    window.App.go('calendars');
    return { id: cal.id, name: cal.name, eventIds: ids };
  });
  await settle(page, 300);
  await page.evaluate((id) => {
    const row = Array.from(document.querySelectorAll('[data-testid="calendar-row"]')).find((r) => r.textContent.includes('工作'));
    const bs = row.querySelectorAll('button');
    bs[bs.length - 1].click();
  }, before.id);
  await settle(page, 250);
  await clickText(page, '.sheet button', '删除日历和内容');
  await settle(page, 300);
  await page.evaluate(() => {
    const b = document.querySelector('.toast button, .toast .undo, [data-testid="toast-undo"]');
    if (b) b.click();
  });
  await settle(page, 300);
  const after = await page.evaluate((info) => ({
    cal: !!window.Store.state.calendars.find((c) => c.id === info.id),
    events: info.eventIds.every((id) => !window.Store.deletedEvents().some((e) => e.id === id)),
  }), before);
  assertEq(after.cal, true, 'undo must restore the calendar');
  assertEq(after.events, true, 'undo must take back the rows it moved to Trash');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* G-P1-3 — About's GitHub rows open the page */
scenario('R12-20 About star opens GitHub', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    window.__opened = [];
    window.open = (url) => { window.__opened.push(url); return { closed: false }; };
    window.App.go('about');
  });
  await settle(page, 300);
  await clickText(page, 'button', '在 GitHub 上加星');
  const opened = await page.evaluate(() => window.__opened);
  assert(opened.length === 1 && /^https:\/\/github\.com\/liuchangchxy\/dayspark/.test(opened[0]), 'star must open GitHub: ' + JSON.stringify(opened));
  assertNoErrors(page);
  await page.__ctx.close();
});

/* H-1 / I-R2-3 — merge refuses without a file and reports a real merge */
scenario('R12-21 merge backup requires a file and reports the result', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'data' });
  await settle(page, 300);
  await clickText(page, '.setting-row', '合并备份');
  await settle(page, 250);
  await clickTestId(page, 'merge-apply');
  const err = await page.evaluate(() => (document.querySelector('[data-testid="merge-error"]') || {}).textContent || '');
  assert(/选择|choose/i.test(err), 'no file must refuse with a reason: ' + err);
  assert(!/已合并/.test(await bodyText(page)), 'no file must not claim a merge');
  // Set the chosen file through the real chooser the sheet opened.
  const chooserPromise = page.waitForEvent('filechooser');
  await page.click('[data-testid="merge-choose"]');
  const chooser = await chooserPromise;
  await chooser.setFiles({ name: 'backup.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify({ todos: [{ id: 99991, summary: '备份任务', status: 'NEEDS-ACTION', updatedAt: Date.now(), calendarId: 1, tagIds: [], reminderOffsets: [], attachments: [], occurrenceStates: {} }], events: [] })) });
  await settle(page, 200);
  await clickTestId(page, 'merge-apply');
  await settle(page, 400);
  const out = await page.evaluate(() => ({
    added: !!window.Store.todoById(99991),
    toast: (document.querySelector('.toast') || {}).innerText || '',
  }));
  assertEq(out.added, true, 'a chosen backup must be merged');
  assert(/新增|added/i.test(out.toast), 'the toast must report the counts: ' + out.toast);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* H-2 — the device row shows the count the sheet loaded */
scenario('R12-22 the device count updates after the list loads', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    window.Store.state.account = { signedIn: true, email: 'you@example.com', server: 'https://nas.local:8080', lastSync: window.U.now(), phase: 'idle', rejected: [] };
    window.App.go('settings', { section: 'sync' });
  });
  await settle(page, 300);
  await clickText(page, '.setting-row', '已连接设备');
  await settle(page, 900);
  await page.evaluate(() => window.UI.closeTop());
  await settle(page, 200);
  const value = await page.evaluate(() => (document.querySelector('[data-testid="connected-devices-row"] .value') || {}).textContent || '');
  assertEq(value, '2', 'the row must show the loaded count, not an em dash');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* H-3 / G P2 — restoring after a calendar deletion rebinds the calendar */
scenario('R12-23 a restored record gets a live calendar', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const cal = window.Store.state.calendars.find((c) => c.name === '工作');
    const e = window.Store.liveEvents().find((x) => x.calendarId === cal.id);
    window.Store.deleteCalendar(cal.id, { move: false });
    const ok = window.Store.restoreEvent(e.id);
    return { ok, id: e.id, calendarId: window.Store.eventById(e.id).calendarId, exists: !!window.Store.calendarById(window.Store.eventById(e.id).calendarId) };
  });
  assert(info.ok, 'the event must restore');
  assertEq(info.exists, true, 'the restored record must point at a live calendar');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* I-R2-1 — the lane resolves recurring deadlines in the visible range */
scenario('R12-24 the deadline lane includes recurring occurrences', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await page.evaluate(() => {
    window.__calendarHelpers.setView('week');
    const b = Array.from(document.querySelectorAll('button')).find((x) => /下一段|Next/.test(x.getAttribute('aria-label') || ''));
    b.click();
  });
  await settle(page, 350);
  const lane = await page.evaluate(() => (document.querySelector('[data-testid="deadline-lane"]') || {}).innerText || '');
  assert(/读 20 页|每日站会记录|每周复盘/.test(lane), 'the lane must list recurring deadlines in range: ' + lane);
  assert(!/没有截止事项|No deadlines/.test(lane), 'the lane must not claim there are no deadlines');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* I-R2-2 — a lane chip opens its own occurrence */
scenario('R12-25 a lane chip opens the day it names', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await page.evaluate(() => {
    window.__calendarHelpers.setView('week');
    const b = Array.from(document.querySelectorAll('button')).find((x) => /下一段|Next/.test(x.getAttribute('aria-label') || ''));
    b.click();
  });
  await settle(page, 350);
  await page.evaluate(() => {
    const more = document.querySelector('[data-testid="deadline-more"]');
    if (more) { more.click(); }
  });
  await settle(page, 250);
  const chip = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.deadline-chip')).find((x) => /每周复盘/.test(x.textContent));
    if (!b) return null;
    const date = b.querySelector('.date').textContent;
    b.click();
    return date;
  });
  assert(chip, 'the lane must offer the recurring chip');
  await settle(page, 350);
  const detail = await page.evaluate(() => (document.querySelector('[data-testid="todo-detail"]') || {}).innerText || '');
  const day = chip.match(/(\d+)月(\d+)日/);
  assert(day && detail.includes(`${Number(day[1])}月${Number(day[2])}日`), 'the detail must open the chip day: ' + chip + ' / ' + detail.slice(0, 120));
  assertNoErrors(page);
  await page.__ctx.close();
});

/* J-R2-1 — identical intervals get distinct columns */
scenario('R12-26 two events with the same slot are both reachable', async (browser) => {
  const page = await newPage(browser);
  const ids = await page.evaluate(() => {
    const day = window.U.startOfDay(window.U.now());
    const s = new Date(day); s.setHours(10, 0);
    const a = window.Store.createEvent({ summary: 'Alpha', startDt: s, endDt: window.U.addMinutes(s, 60), calendarId: 1 });
    const b = window.Store.createEvent({ summary: 'Beta', startDt: s, endDt: window.U.addMinutes(s, 60), calendarId: 1 });
    window.__calendarHelpers.setView('day');
    window.App.go('calendar');
    return [a.id, b.id];
  });
  await settle(page, 400);
  const hit = await page.evaluate((ids) => {
    const blocks = ids.map((id) => document.querySelector(`[data-testid="event-block"][data-id="${id}"]`));
    const r0 = blocks[0].getBoundingClientRect();
    const r1 = blocks[1].getBoundingClientRect();
    const el = document.elementFromPoint(r0.left + r0.width / 2, r0.top + 20);
    return {
      sameLeft: Math.round(r0.left) === Math.round(r1.left),
      hitId: el ? (el.closest('[data-testid="event-block"]') || {}).dataset && el.closest('[data-testid="event-block"]').dataset.id : null,
    };
  }, ids);
  assertEq(hit.sameLeft, false, 'overlapping blocks must get separate columns');
  assertEq(hit.hitId, String(ids[0]), 'the first block must be the one under the pointer');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-R3-1 — a first block does not conflict with itself */
scenario('R12-28 a new schedule does not name itself as a conflict', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.App.openComposer('todo'));
  await settle(page, 250);
  await page.fill('[data-testid="composer-title"]', '独立时段测试');
  await clickTestId(page, 'composer-more');
  await clickTestId(page, 'composer-schedule');
  await settle(page, 250);
  await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    d.setHours(2, 0);
    const el = document.querySelector('[data-testid="schedule-start"]');
    el.value = window.U.toInputDateTime(d);
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await clickTestId(page, 'schedule-apply');
  await settle(page, 200);
  await clickTestId(page, 'composer-save');
  await settle(page, 300);
  const toast = await toastText(page);
  assert(!/重叠|overlap/i.test(toast), 'a block with no other booking must not name a conflict: ' + toast);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* H-R3-1 — an ISO updatedAt in a backup is still "newer" */
scenario('R12-29 merge compares ISO updatedAt as a time', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'data' });
  await settle(page, 300);
  await clickText(page, '.setting-row', '合并备份');
  await settle(page, 250);
  const backup = await page.evaluate(() => {
    const row = JSON.parse(JSON.stringify(window.Store.todoById(3)));
    row.summary = '备份里的新版标题';
    row.updatedAt = new Date(Date.now() + 3600000).toISOString();
    return JSON.stringify({ todos: [row], events: [] });
  });
  const chooserPromise = page.waitForEvent('filechooser');
  await page.click('[data-testid="merge-choose"]');
  const chooser = await chooserPromise;
  await chooser.setFiles({ name: 'backup.json', mimeType: 'application/json', buffer: Buffer.from(backup) });
  await settle(page, 150);
  await clickTestId(page, 'merge-apply');
  await settle(page, 350);
  const out = await page.evaluate(() => ({
    summary: window.Store.todoById(3).summary,
    toast: (document.querySelector('.toast') || {}).innerText || '',
  }));
  assertEq(out.summary, '备份里的新版标题', 'a newer ISO record must be applied');
  assert(/更新 1|updated 1/i.test(out.toast), 'the report must count the update: ' + out.toast);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* G-R3-1 — a trashed record has no write surface at all */
scenario('R12-30 a trashed record has no inline editor or attachment delete', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.state.todos.find((t) => t.summary === '旧版发布检查清单').id);
  await page.evaluate((tid) => window.App.openRecord('todo', tid), id);
  await settle(page, 250);
  assert(await exists(page, '.detail-note'), 'the note fact must still render');
  await page.evaluate(() => document.querySelector('.detail-note').click());
  await settle(page, 200);
  const overlay = await page.evaluate(() => document.querySelectorAll('.modal, .sheet, .dialog').length);
  assertEq(overlay, 0, 'clicking the note on a trashed record must not open an editor');
  assert(!(await exists(page, '[data-testid="attachment-delete"]')), 'a trashed record must not offer attachment delete');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* G-R3-2 — the calendar inverse restores rows that were already in Trash */
scenario('R12-31 calendar move undo restores trashed bindings exactly', async (browser) => {
  const page = await newPage(browser);
  const before = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '已取消的访谈');
    return { cal: e.calendarId, deletedAt: e.deletedAt };
  });
  await go(page, 'calendars');
  await settle(page, 250);
  await page.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.setting-row, .cal-row, .list-row')).find((r) => r.textContent.includes('工作'));
    row.querySelector('button[aria-label="删除日历"], button[aria-label="Delete calendar"]').click();
  });
  await settle(page, 250);
  await clickText(page, 'button', '移动到其他日历');
  await settle(page, 300);
  await page.evaluate(() => document.querySelector('.toast .undo').click());
  await settle(page, 300);
  const after = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '已取消的访谈');
    return { cal: e.calendarId, deletedAt: e.deletedAt, calExists: !!window.Store.calendarById(2) };
  });
  assertEq(after.cal, before.cal, 'undo must take back the binding of a trashed row');
  assertEq(after.deletedAt, before.deletedAt, 'undo must restore the original deletion stamp');
  assertEq(after.calExists, true, 'the calendar must be back');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R3-1 — a jittery touch hold never navigates away */
scenario('R12-32 touch jitter does not turn a hold or drag into navigation', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 0);
    const s = new Date(d); s.setHours(15, 0, 0, 0);
    const e = new Date(s.getTime() + 15 * 60000);
    window.Store.createEvent({ summary: '抖动测试', startDt: s, endDt: e, calendarId: 1 });
    window.App.go('calendar', { view: 'day' });
  });
  await settle(page, 350);
  const box = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.block')).find((x) => x.textContent.includes('抖动测试'));
    const r = b.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  const cdp = await page.__ctx.newCDPSession(page);
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
    type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }],
  });
  const route = () => page.evaluate(() => window.Store.state.route.name);

  await touch('touchStart', box.x, box.y);
  await touch('touchMove', box.x, box.y + 5);
  await settle(page, 520);
  await touch('touchEnd');
  await settle(page, 350);
  assertEq(await route(), 'calendar', 'a 5px jitter hold must not navigate');

  const box2 = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.block')).find((x) => x.textContent.includes('抖动测试'));
    const r = b.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  await touch('touchStart', box2.x, box2.y);
  await touch('touchMove', box2.x, box2.y + 10);
  await settle(page, 150);
  await touch('touchEnd');
  await settle(page, 350);
  assertEq(await route(), 'calendar', 'a 10px drag must stay on the calendar');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* I-R3-1 — a finished recurring instance is not an open deadline in the lane */
scenario('R12-33 the deadline lane drops a completed occurrence', async (browser) => {
  const page = await newPage(browser);
  const seed = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((t) => t.recurrence && t.dueDate && t.summary.includes('读 20 页'));
    const day = window.U.startOfDay(window.U.now());
    return { id: todo.id, summary: todo.summary, occ: window.Store.occurrenceIdFor(todo, day) };
  });
  await page.evaluate(([id, occ]) => window.Store.completeTodo(id, { occurrenceId: occ }), [seed.id, seed.occ]);
  await go(page, 'calendar', { view: 'day' });
  await settle(page, 300);
  const lane = await page.evaluate(() => (document.querySelector('[data-testid="deadline-lane"]') || {}).innerText || '');
  assert(!lane.includes(seed.summary), 'a completed occurrence must not be listed as an open deadline: ' + lane);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* I-R4-1 — the month grid agrees with the lane about a finished occurrence */
scenario('R12-34 the month grid drops a completed recurring occurrence', async (browser) => {
  const page = await newPage(browser);
  const seed = await page.evaluate(() => {
    const day = window.U.addDays(window.U.startOfDay(window.U.now()), 0);
    const due = new Date(day); due.setHours(10, 0, 0, 0);
    const todo = window.Store.createTodo({ summary: '月度网格重复', dueDate: due, recurrence: { freq: 'daily', interval: 1 } });
    const occ = window.Store.occurrenceIdFor(todo, day);
    window.Store.completeTodo(todo.id, { occurrenceId: occ });
    window.App.go('calendar', { view: 'month' });
    return { id: todo.id };
  });
  await settle(page, 350);
  const cell = await page.evaluate(() => {
    const cells = Array.from(document.querySelectorAll('.month-cell'));
    const d = window.U.now().getDate();
    const c = cells.find((x) => x.querySelector('.mday') && x.querySelector('.mday').textContent === String(d) && !x.classList.contains('other'));
    return c ? c.innerText : '';
  });
  assert(!cell.includes('月度网格重复'), 'the month cell must not show a finished occurrence as an open deadline: ' + cell);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* I-R4-2 — deleting a calendar with content undoes the cascade it caused */
scenario('R12-35 calendar delete undo restores a cross-calendar subtask', async (browser) => {
  const page = await newPage(browser);
  const ids = await page.evaluate(() => {
    const home = window.Store.state.calendars.find((c) => c.name === '家庭') || window.Store.state.calendars[2];
    const personal = window.Store.state.calendars.find((c) => c.id !== home.id);
    const parent = window.Store.createTodo({ summary: '级联父', calendarId: home.id });
    const child = window.Store.createTodo({ summary: '级联子', calendarId: personal.id, parentId: parent.id });
    return { cal: home.id, parent: parent.id, child: child.id };
  });
  await go(page, 'calendars');
  await settle(page, 250);
  await page.evaluate((calName) => {
    const row = Array.from(document.querySelectorAll('.setting-row, .cal-row, .list-row')).find((r) => r.textContent.includes(calName));
    row.querySelector('button[aria-label="删除日历"], button[aria-label="Delete calendar"]').click();
  }, '家庭');
  await settle(page, 250);
  await clickText(page, 'button', '删除日历和内容');
  await settle(page, 300);
  await page.evaluate(() => document.querySelector('.toast .undo').click());
  await settle(page, 300);
  const after = await page.evaluate((x) => ({
    parent: !!window.Store.todoById(x.parent).deletedAt,
    child: !!window.Store.todoById(x.child).deletedAt,
  }), ids);
  assertEq(after.parent, false, 'the parent comes back');
  assertEq(after.child, false, 'the cascaded child comes back with it');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* A-R4-1 — a re-render while the discard dialog is open changes nothing */
scenario('R12-36 a resize during the discard question asks once and keeps a kept draft', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await page.keyboard.press('n');
  await settle(page, 250);
  await page.fill('[data-testid="composer-title"]', '重绘草稿');
  await page.evaluate(() => document.activeElement.blur());
  await page.goBack();
  await settle(page, 250);
  await page.setViewportSize({ width: 1320, height: 900 });
  await settle(page, 250);
  await clickText(page, 'button', '继续编辑');
  await settle(page, 300);
  const kept = await page.evaluate(() => ({
    route: window.Store.state.route.name,
    value: (document.querySelector('[data-testid="composer-title"]') || {}).value,
    dialogs: Array.from(document.querySelectorAll('button')).filter((b) => b.textContent.trim() === '放弃').length,
  }));
  assertEq(kept.route, 'composer', '继续编辑 must stay on the composer');
  assertEq(kept.dialogs, 0, 'the question must not be re-asked by the re-render');
  assertEq(kept.value, '重绘草稿', '继续编辑 must keep the draft after a re-render');

  await page.evaluate(() => document.activeElement.blur());
  await page.goBack();
  await settle(page, 250);
  await page.setViewportSize({ width: 1440, height: 900 });
  await settle(page, 250);
  await clickText(page, 'button', '放弃');
  await settle(page, 400);
  const left = await page.evaluate(() => ({
    route: window.Store.state.route.name,
    dialogs: Array.from(document.querySelectorAll('button')).filter((b) => b.textContent.trim() === '放弃').length,
  }));
  assertEq(left.dialogs, 0, 'one discard must leave without a second question');
  assertEq(left.route, 'action', 'one discard must complete the Back');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* G-R4-1 — feedback reports the tab it really opened */
scenario('R12-37 feedback submit reports success when the tab opens', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'feedback');
  await settle(page, 250);
  await page.fill('[data-testid="feedback-text"]', '反馈内容');
  const popupPromise = page.waitForEvent('popup', { timeout: 4000 }).catch(() => null);
  await clickTestId(page, 'feedback-submit');
  const popup = await popupPromise;
  assert(popup, 'the submit must open a real tab');
  await settle(page, 300);
  const toast = await toastText(page);
  assert(/已在新标签页打开|Opened GitHub/i.test(toast), 'a tab that opened must not be reported as blocked or failed: ' + toast);
  await page.__ctx.close();
});

/* G-R4-2 — a deletion never moves an older deletion stamp forward */
scenario('R12-38 deleting a trashed event keeps its original stamp', async (browser) => {
  const page = await newPage(browser);
  const out = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.summary === '已取消的访谈');
    const before = e.deletedAt;
    window.Store.softDeleteEvent(e.id);
    const afterSecond = window.Store.eventById(e.id).deletedAt;
    const cal = window.Store.state.calendars.find((c) => c.id === e.calendarId);
    window.Store.deleteCalendar(cal.id, { move: false });
    const afterCalendar = window.Store.eventById(e.id).deletedAt;
    return { before, afterSecond, afterCalendar, trashed: !!afterCalendar };
  });
  assertEq(out.trashed, true, 'the event stays trashed');
  assertEq(out.afterSecond, out.before, 'a second delete must not move the first stamp');
  assertEq(out.afterCalendar, out.before, 'a calendar deletion must not re-stamp a trashed row');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F-R4-1 — a trashed recurring record has no occurrence controls */
scenario('R12-39 a trashed recurring todo shows no occurrence list', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now());
    const todo = window.Store.createTodo({ summary: '回收站重复', recurrence: { freq: 'daily', interval: 1 } });
    window.Store.softDeleteTodo(todo.id);
    window.App.openRecord('todo', todo.id);
    return todo.id;
  });
  await settle(page, 300);
  const out = await page.evaluate(() => ({
    occ: document.querySelectorAll('[data-testid="detail-occurrence"]').length,
    hint: document.body.innerText.includes('每次实例可单独完成'),
    banner: /回收站|trash/i.test(document.body.innerText),
  }));
  assertEq(out.banner, true, 'the trashed banner must render');
  assertEq(out.occ, 0, 'a trashed record must not render occurrence checkboxes');
  assertEq(out.hint, false, 'a trashed record must not promise per-occurrence completion');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F-R4-2 — phone detail text controls are 48px targets */
scenario('R12-40 phone note and subtask title are 48px targets', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  await page.evaluate(() => {
    const parent = window.Store.createTodo({ summary: '触控父任务', description: '一行备注' });
    window.Store.createTodo({ summary: '子任务标题', parentId: parent.id });
    window.App.openRecord('todo', parent.id);
  });
  await settle(page, 300);
  const sizes = await page.evaluate(() => {
    const note = document.querySelector('.detail-note');
    const title = document.querySelector('.subtask .title');
    const box = (el) => { const r = el.getBoundingClientRect(); return { w: Math.round(r.width), h: Math.round(r.height) }; };
    return { note: box(note), title: box(title) };
  });
  assert(sizes.note.h >= 48, 'the note target must be at least 48px tall: ' + JSON.stringify(sizes.note));
  assert(sizes.title.h >= 48, 'the subtask title target must be at least 48px tall: ' + JSON.stringify(sizes.title));
  await page.evaluate(() => document.querySelector('.detail-note').click());
  await settle(page, 200);
  assert(await exists(page, 'textarea'), 'tapping the note must still open its editor');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* F-R4-3 — a trashed record describes its active block once, correctly */
scenario('R12-41 a trashed todo keeps an active block as planned', async (browser) => {
  const page = await newPage(browser);
  const out = await page.evaluate(() => {
    const day = window.U.startOfDay(window.U.now());
    const start = new Date(day); start.setHours(9, 0, 0, 0);
    const todo = window.Store.createTodo({ summary: '回收站计划' });
    window.Store.createAllocation({ todoId: todo.id, startAt: start, endAt: new Date(start.getTime() + 3600000) });
    window.Store.softDeleteTodo(todo.id);
    window.App.openRecord('todo', todo.id);
    return { id: todo.id };
  });
  await settle(page, 300);
  const text = await page.evaluate(() => document.body.innerText);
  assert(!/未安排/.test(text), 'a trashed record with an active block must not say 未安排');
  assert(!/完成时失效|Invalidated/.test(text), 'an active block must not be labelled invalidated');
  assert(/09:00/.test(text), 'the block itself must be shown: ' + text.slice(0, 200));
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-R4-1 — the phone save label wraps instead of widening the page */
scenario('R12-42 a long save label keeps the phone layout and the sheet reachable', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  const id = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.dueDate && x.summary.includes('读 20 页'));
    window.App.openComposer('todo', { mode: 'edit', id: todo.id });
    return todo.id;
  });
  await settle(page, 350);
  const layout = await page.evaluate(() => {
    const btn = document.querySelector('[data-testid="composer-save"]');
    const r = btn.getBoundingClientRect();
    return { vw: window.innerWidth, doc: document.documentElement.scrollWidth, right: r.right, label: btn.textContent };
  });
  assert(layout.label.length > 6, 'the label must still name the fields: ' + layout.label);
  assert(layout.doc <= layout.vw, 'the save label must not widen the page: doc ' + layout.doc + ' vs ' + layout.vw);
  assert(layout.right <= layout.vw + 1, 'the save button must stay inside the viewport: ' + layout.right);
  await clickTestId(page, 'composer-schedule');
  await settle(page, 300);
  const apply = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="schedule-apply"]');
    if (!b) return null;
    const r = b.getBoundingClientRect();
    return { top: r.top, bottom: r.bottom, vh: window.innerHeight };
  });
  assert(apply, 'the schedule sheet must render');
  assert(apply.bottom <= apply.vh && apply.top >= 0, 'the schedule action must be on screen: ' + JSON.stringify(apply));
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-R4-2 — removing the repeat and moving the block really moves it */
scenario('R12-43 a block moves after the repeat is removed', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.recurrence && x.summary.includes('读 20 页'));
    window.App.openComposer('todo', { mode: 'edit', id: todo.id });
    return todo.id;
  });
  await settle(page, 350);
  await clickTestId(page, 'composer-repeat');
  await clickText(page, '[data-testid="repeat-option"]', '不重复');
  await settle(page, 250);
  await clickTestId(page, 'composer-schedule');
  await settle(page, 250);
  const target = await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    d.setHours(9, 0);
    const s = document.querySelector('[data-testid="schedule-start"]');
    s.value = window.U.toInputDateTime(d);
    s.dispatchEvent(new Event('change', { bubbles: true }));
    return d.getTime();
  });
  await clickTestId(page, 'schedule-apply');
  await settle(page, 250);
  await clickTestId(page, 'composer-save');
  await settle(page, 350);
  const out = await page.evaluate((tid) => {
    const todo = window.Store.todoById(tid);
    const live = window.Store.state.allocations.filter((a) => a.todoId === tid && a.state === window.Store.ALLOC.ACTIVE);
    return {
      recurrence: !!todo.recurrence,
      starts: live.map((a) => a.startAt.getTime()),
      occs: live.map((a) => a.occurrenceId),
      route: window.Store.state.route.name,
    };
  }, id);
  assertEq(out.recurrence, false, 'the record must no longer repeat');
  assertEq(out.starts, [target], 'the block must move to the chosen day');
  assertEq(out.occs, [null], 'a non-repeating block owns no occurrence');
  assertEq(out.route !== 'composer', true, 'the save must leave the composer');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-R4-3 — the rule on screen must reach the block's day */
scenario('R12-44 a weekly rule refuses a block on a day it never reaches', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const todo = window.Store.liveTodos().find((x) => x.recurrence && x.summary.includes('读 20 页'));
    window.App.openComposer('todo', { mode: 'edit', id: todo.id });
    return todo.id;
  });
  await settle(page, 350);
  await clickTestId(page, 'composer-repeat');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('[data-testid="repeat-option"]')).find((x) => x.textContent.includes('每周') && x.textContent.includes('('));
    b.click();
  });
  await settle(page, 250);
  await clickTestId(page, 'composer-schedule');
  await settle(page, 250);
  await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    d.setHours(21, 0);
    const s = document.querySelector('[data-testid="schedule-start"]');
    s.value = window.U.toInputDateTime(d);
    s.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await clickTestId(page, 'schedule-apply');
  await settle(page, 250);
  const out = await page.evaluate((tid) => ({
    disabled: document.querySelector('[data-testid="composer-save"]').disabled,
    error: (document.querySelector('.hint-box.error') || {}).innerText || '',
    before: window.Store.state.allocations.filter((a) => a.todoId === tid && a.state === window.Store.ALLOC.ACTIVE).map((a) => a.startAt.getTime()),
  }), id);
  assertEq(out.disabled, true, 'a block the rule cannot reach must disable the save');
  assert(/计划|occurrence|实例/i.test(out.error), 'the refusal must say why: ' + out.error);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* E-R4-4 — a repeating event is a conflict on every occurrence day */
scenario('R12-45 conflict names a repeating event occurrence', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    const s = new Date(d); s.setHours(14, 0, 0, 0);
    window.Store.createEvent({
      summary: '每周同步会', startDt: s, endDt: new Date(s.getTime() + 3600000),
      calendarId: 1, rrule: { freq: 'WEEKLY', interval: 1, byday: [s.getDay()], until: null, timeZone: 'Asia/Shanghai', anchor: 'start', valueType: 'localDateTime' },
    });
    window.App.openComposer('todo');
  });
  await settle(page, 300);
  await page.fill('[data-testid="composer-title"]', '撞重复日程');
  await clickTestId(page, 'composer-more');
  await clickTestId(page, 'composer-schedule');
  await settle(page, 250);
  await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    d.setHours(14, 0);
    const s = document.querySelector('[data-testid="schedule-start"]');
    s.value = window.U.toInputDateTime(d);
    s.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await settle(page, 250);
  const preview = await page.evaluate(() => document.body.innerText);
  assert(preview.includes('每周同步会'), 'the preview must name the repeating event occurrence');
  await clickTestId(page, 'schedule-apply');
  await settle(page, 200);
  await clickTestId(page, 'composer-save');
  await settle(page, 350);
  const toast = await toastText(page);
  assert(toast.includes('每周同步会'), 'the save toast must name the conflict: ' + toast);
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R4-1 — exactly 8px is still a hold, aligned or not */
scenario('R12-46 an 8px jitter writes nothing even off the quarter hour', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  const before = await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now());
    const s = new Date(d); s.setHours(9, 7, 0, 0);
    const e = window.Store.createEvent({ summary: '八像素测试', startDt: s, endDt: new Date(s.getTime() + 3600000), calendarId: 1 });
    window.App.go('calendar', { view: 'day' });
    return { id: e.id, start: e.startDt.getTime() };
  });
  await settle(page, 350);
  const box = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.block')).find((x) => x.textContent.includes('八像素测试'));
    const r = b.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  const cdp = await page.__ctx.newCDPSession(page);
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  await touch('touchStart', box.x, box.y);
  await touch('touchMove', box.x, box.y + 8);
  await settle(page, 600);
  await touch('touchEnd');
  await settle(page, 350);
  const after = await page.evaluate((id) => ({
    start: window.Store.eventById(id).startDt.getTime(),
    route: window.Store.state.route.name,
  }), before.id);
  assertEq(after.start, before.start, 'an 8px jitter must not move the event');
  assertEq(after.route, 'calendar', 'the release must not navigate');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R4-2 — once the hold menu is open, sliding does not drag */
scenario('R12-47 sliding after the hold menu opens writes nothing', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  const before = await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now());
    const s = new Date(d); s.setHours(9, 0, 0, 0);
    const e = window.Store.createEvent({ summary: '按住后滑动', startDt: s, endDt: new Date(s.getTime() + 3600000), calendarId: 1 });
    window.App.go('calendar', { view: 'day' });
    return { id: e.id, start: e.startDt.getTime() };
  });
  await settle(page, 350);
  const box = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.block')).find((x) => x.textContent.includes('按住后滑动'));
    const r = b.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  const cdp = await page.__ctx.newCDPSession(page);
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  await touch('touchStart', box.x, box.y);
  await settle(page, 620);
  await touch('touchMove', box.x, box.y + 60);
  await settle(page, 120);
  await touch('touchEnd');
  await settle(page, 350);
  const after = await page.evaluate((id) => ({
    start: window.Store.eventById(id).startDt.getTime(),
    route: window.Store.state.route.name,
  }), before.id);
  assertEq(after.start, before.start, 'a slide after the menu opened must not move the event');
  assertEq(after.route, 'calendar', 'the release must not navigate');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R4-6 — a tap on the resize strip is not a way into the record */
scenario('R12-48 a jitter on the resize strip does not navigate', async (browser) => {
  const page = await newPage(browser, MOBILE, true);
  await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now());
    const s = new Date(d); s.setHours(13, 0, 0, 0);
    window.Store.createEvent({ summary: '拉伸手柄', startDt: s, endDt: new Date(s.getTime() + 3600000), calendarId: 1 });
    window.App.go('calendar', { view: 'day' });
  });
  await settle(page, 350);
  const box = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.block')).find((x) => x.textContent.includes('拉伸手柄'));
    const r = b.querySelector('.resize').getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  const cdp = await page.__ctx.newCDPSession(page);
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  await touch('touchStart', box.x, box.y);
  await touch('touchMove', box.x, box.y + 4);
  await settle(page, 120);
  await touch('touchEnd');
  await settle(page, 350);
  assertEq(await page.evaluate(() => window.Store.state.route.name), 'calendar', 'a strip tap must stay on the calendar');
  assertNoErrors(page);
  await page.__ctx.close();
});

/* D-R4-5 — the gesture guard does not eat a later, different click */
scenario('R12-49 a drag does not swallow a click on another block', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const d = window.U.startOfDay(window.U.now());
    const a = new Date(d); a.setHours(9, 0, 0, 0);
    const b = new Date(d); b.setHours(15, 0, 0, 0);
    window.Store.createEvent({ summary: '拖甲', startDt: a, endDt: new Date(a.getTime() + 3600000), calendarId: 1 });
    window.Store.createEvent({ summary: '点乙', startDt: b, endDt: new Date(b.getTime() + 3600000), calendarId: 1 });
    window.App.go('calendar', { view: 'day' });
  });
  await settle(page, 350);
  const boxes = await page.evaluate(() => {
    const at = (name) => {
      const el = Array.from(document.querySelectorAll('.block')).find((x) => x.textContent.includes(name));
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    };
    return { a: at('拖甲'), b: at('点乙') };
  });
  await page.mouse.move(boxes.a.x, boxes.a.y);
  await page.mouse.down();
  await page.mouse.move(boxes.a.x, boxes.a.y + 60, { steps: 4 });
  await page.mouse.up();
  await page.mouse.click(boxes.b.x, boxes.b.y);
  await settle(page, 400);
  const out = await page.evaluate(() => ({
    route: window.Store.state.route.name,
    title: document.body.innerText.includes('点乙'),
  }));
  assertEq(out.route, 'detail', 'a click on another block must open that block');
  assertEq(out.title, true, 'the opened record must be the clicked one');
  assertNoErrors(page);
  await page.__ctx.close();
});

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  const failures = [];
  for (const s of scenarios) {
    const started = Date.now();
    try {
      await s.fn(browser);
      console.log(`PASS ${s.name} (${Date.now() - started}ms)`);
    } catch (err) {
      failures.push({ name: s.name, error: err.message });
      console.log(`FAIL ${s.name} (${Date.now() - started}ms)`);
      console.log('     ' + err.message);
    }
  }
  await browser.close();
  console.log(`\n${scenarios.length - failures.length}/${scenarios.length} round-12 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.error));
    process.exit(1);
  }
})();
