/* G0-v2 round-1 independent review regression suite (R1-1 … R9-1).
   One scenario per P1 in REVIEW_ROUNDS_G0V2.md. Every scenario drives the real
   UI and asserts visible state or written data, never only element existence. */
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

/* R1-1 — Back on 今天 does not walk into stale history */
scenario('R11-01 browser Back at 今天 stays on 今天', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'search');
  await go(page, 'action');
  await page.goBack();
  await settle(page, 300);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assertEq(route, 'action', 'Back at the root must not leave 今天');
  assertNoErrors(page);
  await page.close();
});

/* R1-2 — browser Back closes the top overlay before navigating */
scenario('R11-02 browser Back closes the filter sheet first', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickTestId(page, 'todos-filter');
  assert(await exists(page, '[data-testid="filter-sheet"]'), 'filter sheet must be open');
  await page.goBack();
  await settle(page, 300);
  const state = await page.evaluate(() => ({
    route: window.Store.state.route.name,
    sheet: !!document.querySelector('[data-testid="filter-sheet"]'),
  }));
  assertEq(state.route, 'todos', 'Back must not navigate while an overlay is open');
  assertEq(state.sheet, false, 'Back must close the overlay');
  assertNoErrors(page);
  await page.close();
});

/* R1-3 — N asks before replacing a dirty draft */
scenario('R11-03 N on a dirty composer asks before discarding', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.App.openComposer('todo'));
  await settle(page, 250);
  await page.fill('[data-testid="composer-title"]', '写到一半的待办');
  await clickTestId(page, 'composer-more');
  await page.keyboard.press('n');
  await settle(page, 250);
  assert(await exists(page, '.modal.confirm'), 'a dirty draft must ask before being replaced');
  await clickText(page, '.modal.confirm button', '继续编辑');
  const still = await page.evaluate(() => {
    const el = document.querySelector('[data-testid="composer-title"]');
    return el && el.value;
  });
  assertEq(still, '写到一半的待办', 'cancelling the question must keep the draft');
  assertNoErrors(page);
  await page.close();
});

/* R1-4 — shortcuts are inert while the 更多 menu is open */
scenario('R11-04 shortcuts are inert while the More menu is open', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'todos');
  await clickTestId(page, 'tab-more');
  await page.keyboard.press('n');
  await settle(page, 250);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assertEq(route, 'todos', 'N must not open the composer behind an open menu');
  assertNoErrors(page);
  await page.close();
});

/* R2-1 — the composer delegates completion to the one routine */
scenario('R11-05 editing status through the form invalidates and restores blocks', async (browser) => {
  const page = await newPage(browser);
  await setClock(page, 15, 45);
  const budget = await page.evaluate(() => window.Store.liveTodos().find((x) => x.summary === 'Q4 预算表').id);
  await page.evaluate((id) => window.App.openComposer('todo', { mode: 'edit', id }), budget);
  await settle(page, 300);
  await clickTestId(page, 'composer-status-done');
  await clickTestId(page, 'composer-save');
  await settle(page, 300);
  const afterDone = await page.evaluate((id) => {
    const t = window.Store.todoById(id);
    return { done: t.status, inv: window.Store.state.allocations.filter((a) => a.todoId === id && a.state === window.Store.ALLOC.INVALIDATED).length };
  }, budget);
  assertEq(afterDone.done, 'COMPLETED', 'the form must write the completion state');
  assertEq(afterDone.inv, 1, 'completion through the form must invalidate the later block');
  await page.evaluate((id) => window.App.openComposer('todo', { mode: 'edit', id }), budget);
  await settle(page, 300);
  await clickTestId(page, 'composer-status-open');
  await clickTestId(page, 'composer-save');
  await settle(page, 300);
  const afterOpen = await page.evaluate((id) => ({
    done: window.Store.todoById(id).status,
    active: window.Store.state.allocations.filter((a) => a.todoId === id && a.state === 'active').length,
  }), budget);
  assertEq(afterOpen.done, 'NEEDS-ACTION', 'reopening must restore the record');
  assertEq(afterOpen.active, 1, 'reopening must give the block back');
  assertNoErrors(page);
  await page.close();
});

/* R2-2 — a recurring subtask completes through the shared routine */
scenario('R11-06 a recurring subtask checkbox resolves its occurrence', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const parent = window.Store.liveTodos().find((x) => x.summary === '准备季度评审');
    const sub = window.Store.subtasksOf(parent.id)[0];
    sub.recurrence = { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' };
    sub.dueDate = window.U.startOfDay(window.U.now());
    window.Store.emit('todo:update');
    return { parent: parent.id, sub: sub.id };
  });
  await page.evaluate((id) => window.Store.navigate('detail', { type: 'todo', id }), info.parent);
  await settle(page, 300);
  await page.evaluate(() => document.querySelector('.subtask button.hit').click());
  await settle(page, 300);
  const states = await page.evaluate((id) => Object.keys(window.Store.todoById(id).occurrenceStates).length, info.sub);
  assert(states > 0, 'a recurring subtask must write its occurrence state, not do nothing');
  assertNoErrors(page);
  await page.close();
});

/* R2-3 — a completed Todo cannot be scheduled */
scenario('R11-07 a completed todo offers no scheduling action', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.liveTodos().find((x) => x.summary === '提交上周的工时').id);
  await page.evaluate((tid) => window.Store.navigate('detail', { type: 'todo', id: tid }), id);
  await settle(page, 300);
  assertEq(await exists(page, '[data-testid="detail-schedule"]'), false, 'no schedule control on a finished todo');
  const text = await bodyText(page);
  assert(/取消完成/.test(text), 'the reason must be visible on the surface');
  assertNoErrors(page);
  await page.close();
});

/* R2-4 — completing a missed occurrence shows it in 今天完成 with undo */
scenario('R11-08 a missed occurrence completed today lands in 今天完成 with undo', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const t = window.Store.createTodo({
      summary: '补做的每日回顾',
      recurrence: { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'start', valueType: 'date' },
      startDate: window.U.addDays(window.U.startOfDay(window.U.now()), -4),
    });
    return t.id;
  });
  await go(page, 'action');
  const row = `[data-testid="action-instance"][data-id="${id}"]`;
  assert(await exists(page, row), 'the missed occurrence must be listed');
  await page.evaluate((sel) => document.querySelector(sel + ' button.hit').click(), row);
  await settle(page, 350);
  const state = await page.evaluate(() => {
    const heads = Array.from(document.querySelectorAll('.section-head')).map((h) => h.textContent);
    const doneIdx = heads.findIndex((h) => /今天完成/.test(h));
    const body = document.body.innerText;
    return { heads, hasRow: /补做的每日回顾/.test(body), undo: !!document.querySelector('[data-testid="action-undo"]'), doneIdx };
  });
  assert(state.doneIdx >= 0, '今天完成 section must exist');
  assert(state.hasRow, 'the completed occurrence must be visible');
  assert(state.undo, 'the completed occurrence must offer inline undo');
  assertNoErrors(page);
  await page.close();
});

/* R3-1 — detail opened for a day is about that occurrence */
scenario('R11-09 a recurring detail shows the occurrence it was opened for', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const t = window.Store.liveTodos().find((x) => x.summary.includes('读 20 页'));
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    window.Store.navigate('detail', { type: 'todo', id: t.id, day: d.getTime() });
    return { id: t.id, day: d.getTime(), label: window.U.fmtMonthDay(d) };
  });
  await settle(page, 320);
  const facts = await page.evaluate(() => (document.querySelector('.detail-facts') || {}).innerText || '');
  assert(facts.includes(info.label), 'deadline must be the occurrence day, got: ' + facts.slice(0, 160));
  assert(/22:00/.test(facts), 'the occurrence keeps the series time of day');
  assert(/未安排/.test(facts), 'the other day\'s block must not be listed here');
  assertNoErrors(page);
  await page.close();
});

/* R3-2 — a recurring todo with no deadline gets no invented deadline */
scenario('R11-10 a recurring allocation without a deadline shows no 截止', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    const t = window.Store.createTodo({
      summary: '重复训练无日期',
      recurrence: { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'start', valueType: 'date' },
      startDate: today,
    });
    const s = new Date(today); s.setHours(23, 0, 0, 0);
    const e = new Date(s.getTime() + 30 * 60000);
    window.Store.createAllocation({ todoId: t.id, startAt: s, endAt: e, occurrenceId: window.Store.occurrenceIdFor(t, today) });
    return t.id;
  });
  await go(page, 'action');
  const meta = await page.evaluate((tid) => {
    const row = document.querySelector(`[data-testid="action-allocation"][data-id="${tid}"]`);
    const m = row && row.querySelector('.row-meta');
    return m ? m.innerText : '';
  }, id);
  assert(meta.length > 0, 'the allocation row must render');
  assert(!/截止/.test(meta), 'an undated series must not gain a deadline: ' + meta);
  assertNoErrors(page);
  await page.close();
});

/* R3-3 — editing a recurring occurrence offers three scopes */
scenario('R11-11 editing an occurrence offers this / future / all', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const e = window.Store.liveEvents().find((x) => x.summary === '周会');
    const day = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    const occ = new Date(day); occ.setHours(10, 0, 0, 0);
    window.EventOps.editEvent(Object.assign({}, e, {
      isOccurrence: true, occurrenceAnchor: window.U.startOfDay(occ), startDt: occ,
    }));
  });
  await settle(page, 300);
  const opts = await page.evaluate(() => Array.from(document.querySelectorAll('[data-testid^="scope-"]')).map((x) => x.dataset.testid));
  assertEq(opts.sort(), ['scope-all', 'scope-future', 'scope-this'], 'edit must offer the same three scopes as delete');
  assertNoErrors(page);
  await page.close();
});

/* R3-4 — completed subtasks never enter top-level lists */
scenario('R11-12 a completed subtask stays out of 全部待办 and 今天完成', async (browser) => {
  const page = await newPage(browser);
  const name = await page.evaluate(() => {
    const parent = window.Store.liveTodos().find((x) => x.summary === '准备季度评审');
    const sub = window.Store.subtasksOf(parent.id)[0];
    window.Store.completeTodo(sub.id);
    return sub.summary;
  });
  await go(page, 'todos');
  await clickText(page, '.chip-btn', '全部待办');
  assert(!(await bodyText(page)).includes(name), 'a subtask must not be a row in 全部待办');
  await go(page, 'action');
  const today = await page.evaluate(() => {
    const done = document.querySelector('.section-head');
    return document.body.innerText;
  });
  assert(!today.includes(name), 'a subtask must not appear in any 今天 section');
  assertNoErrors(page);
  await page.close();
});

/* R3-5 — an occurrence's deadline keeps its time */
scenario('R11-13 a recurring row keeps the occurrence deadline time', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const meta = await page.evaluate(() => {
    const t = window.Store.liveTodos().find((x) => x.summary.includes('读 20 页'));
    const row = document.querySelector(`[data-testid="todo-row"][data-id="${t.id}"]`);
    return row ? row.innerText : '';
  });
  assert(/22:00/.test(meta), 'the dated row must show 22:00, got: ' + meta);
  assertNoErrors(page);
  await page.close();
});

/* R4-1 — the dated body is the day projection */
scenario('R11-14 the dated body lists planned work and events', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    const t = window.Store.liveTodos().find((x) => x.summary === '查一下 NAS 备份策略');
    const today = window.U.startOfDay(window.U.now());
    const s = new Date(today); s.setHours(23, 0, 0, 0);
    window.Store.createAllocation({ todoId: t.id, startAt: s, endAt: new Date(s.getTime() + 3600000) });
  });
  await go(page, 'todos');
  const state = await page.evaluate(() => ({
    heads: Array.from(document.querySelectorAll('.section-head')).map((h) => h.textContent),
    events: document.querySelectorAll('[data-testid="todo-event-row"]').length,
    planned: /计划执行/.test(document.body.innerText) && /查一下 NAS 备份策略/.test(document.body.innerText),
  }));
  assert(state.heads.some((h) => /计划执行/.test(h)), 'planned executions need their own section');
  assert(state.planned, 'the planned todo must be listed in the dated body');
  assert(state.events > 0, 'the day\'s events must be listed');
  assertNoErrors(page);
  await page.close();
});

/* R4-2 — 全部待办 is grouped by due relation */
scenario('R11-15 全部待办 groups today / overdue / later / undated', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await clickText(page, '.chip-btn', '全部待办');
  const heads = await page.evaluate(() => Array.from(document.querySelectorAll('.section-head')).map((h) => h.textContent));
  ['今天', '已逾期', '之后', '无截止'].forEach((label) => {
    assert(heads.some((h) => h.startsWith(label)), `missing ${label} group, got ${heads.join(' | ')}`);
  });
  assertNoErrors(page);
  await page.close();
});

/* R4-3 — 未安排's completed half uses planned execution, not dueDate */
scenario('R11-16 a dated, unplanned todo that is done appears in 未安排', async (browser) => {
  const page = await newPage(browser);
  const name = await page.evaluate(() => {
    const t = window.Store.createTodo({
      summary: '有截止已完成无安排',
      dueDate: window.U.addDays(window.U.startOfDay(window.U.now()), 2),
    });
    window.Store.completeTodo(t.id);
    return t.summary;
  });
  await go(page, 'todos');
  await clickText(page, '.chip-btn', '未安排');
  assert((await bodyText(page)).includes(name), '未安排 is decided by planned execution, not by dueDate');
  assertNoErrors(page);
  await page.close();
});

/* R4-4 — switching mode keeps browseDate */
scenario('R11-17 switching to 未安排 and back keeps browseDate', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  const target = await page.evaluate(() => {
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 2);
    window.Store.setBrowseDate(d);
    window.App.render();
    return d.getTime();
  });
  await settle(page, 200);
  await clickText(page, '.chip-btn', '未安排');
  await clickText(page, '.chip-btn', '今天');
  const after = await page.evaluate(() => window.Store.state.browseDate.getTime());
  assertEq(after, target, 'a mode switch must not move the shared browsed date');
  assertNoErrors(page);
  await page.close();
});

/* R5-1 — deadline chips write a future time */
scenario('R11-18 deadline chips never write the past', async (browser) => {
  const page = await newPage(browser);
  await setClock(page, 22, 30);
  await page.evaluate(() => window.App.openComposer('todo'));
  await settle(page, 250);
  await clickTestId(page, 'composer-deadline');
  await page.evaluate(() => document.querySelectorAll('[data-testid="deadline-quick"]')[0].click());
  await settle(page, 250);
  const due = await page.evaluate(() => window.Store.state.composerDraft.dueDate.getTime());
  const now = await page.evaluate(() => window.U.now().getTime());
  assert(due > now, 'a quick chip must write a future deadline');
  assertNoErrors(page);
  await page.close();
});

/* R5-2 — the type is a fact when editing */
scenario('R11-19 an edit form shows the type as a fact', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.liveTodos()[0].id);
  await page.evaluate((tid) => window.App.openComposer('todo', { mode: 'edit', id: tid }), id);
  await settle(page, 280);
  assertEq(await exists(page, '[data-testid="composer-type-todo"]'), false, 'no enabled type switch on an existing record');
  assert(await exists(page, '[data-testid="composer-type-fact"]'), 'the type must be shown as a fact');
  assertNoErrors(page);
  await page.close();
});

/* R5-3 — a cross-midnight event stays editable */
scenario('R11-20 a cross-midnight event keeps its end date', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    const s = new Date(today); s.setHours(23, 0, 0, 0);
    const e = new Date(today.getTime() + 24 * 3600000); e.setHours(1, 0, 0, 0);
    const ev = window.Store.createEvent({ summary: '跨午夜直播', startDt: s, endDt: e, calendarId: 1 });
    return ev.id;
  });
  await page.evaluate((eid) => window.App.openComposer('event', { mode: 'edit', id: eid }), id);
  await settle(page, 300);
  await page.fill('[data-testid="composer-start-time"]', '22:30');
  await settle(page, 200);
  const state = await page.evaluate(() => {
    const d = window.Store.state.composerDraft;
    return {
      error: (document.querySelector('.field-error') || {}).textContent || '',
      endDay: d.endDt.getDate(),
      startDay: d.startDt.getDate(),
      endHour: d.endDt.getHours(),
    };
  });
  assert(state.endDay !== state.startDay, 'the end must stay on the next day');
  assertEq(state.endHour, 1, 'the end time must survive the edit');
  assertEq(state.error, '', 'a valid cross-midnight record must not show an error');
  assertNoErrors(page);
  await page.close();
});

/* R5-4 — the planned occurrence follows the planned day */
scenario('R11-21 moving the planned day re-derives the occurrence', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const t = window.Store.liveTodos().find((x) => x.summary === '每日站会记录');
    window.App.openComposer('todo', { mode: 'edit', id: t.id });
    return { id: t.id };
  });
  await settle(page, 300);
  await clickTestId(page, 'composer-schedule');
  const day = await page.evaluate(() => {
    let d = window.U.addDays(window.U.startOfDay(window.U.now()), 1);
    while (d.getDay() === 0 || d.getDay() === 6) d = window.U.addDays(d, 1);
    return d.getTime();
  });
  const value = await page.evaluate((ms) => {
    const d = new Date(ms); d.setHours(9, 0, 0, 0);
    return window.U.toInputDateTime(d);
  }, day);
  await page.fill('[data-testid="schedule-start"]', value);
  await page.evaluate(() => {
    const el = document.querySelector('[data-testid="schedule-start"]');
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await settle(page, 200);
  await clickTestId(page, 'schedule-apply');
  const got = await page.evaluate((ms) => {
    const d = window.Store.state.composerDraft;
    return {
      occ: d.scheduleOccurrence,
      expected: window.Store.occurrenceIdFor(window.Store.todoById(window.Store.state.composerDraft.id), new Date(ms)),
      mismatch: /不一致/.test(document.body.innerText),
    };
  }, day);
  assertEq(got.occ, got.expected, 'the occurrence must be derived from the planned day');
  assertEq(got.mismatch, false, 'a valid occurrence day must not be refused');
  assertNoErrors(page);
  await page.close();
});

/* R5-5 — create from the list lands where the record lives */
scenario('R11-22 a created todo lands on a view that contains it', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.App.openComposer('todo', { dueDate: window.U.startOfDay(window.U.now()) }));
  await settle(page, 300);
  await page.fill('[data-testid="composer-title"]', '落地可见性测试');
  await clickTestId(page, 'composer-deadline');
  await clickText(page, '.sheet button', '无截止');
  await clickTestId(page, 'composer-save');
  await settle(page, 350);
  const state = await page.evaluate(() => ({
    view: window.Store.state.todosView.kind,
    hl: !!document.querySelector('.hl'),
    text: document.body.innerText,
  }));
  assertEq(state.view, 'inbox', 'an undated record belongs to 未安排');
  assert(state.text.includes('落地可见性测试'), 'the new row must be visible');
  assert(state.hl, 'the new row must be highlighted');
  assertNoErrors(page);
  await page.close();
});

/* R5-6 — 重复开始 never becomes a plain start date */
scenario('R11-23 dismissing the repeat sheet writes no start date', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.App.openComposer('todo'));
  await settle(page, 300);
  await page.fill('[data-testid="composer-title"]', '不重复测试');
  await clickTestId(page, 'composer-more');
  await clickTestId(page, 'composer-repeat');
  await page.evaluate(() => {
    const el = document.querySelector('[data-testid="repeat-start"]');
    const d = window.U.addDays(window.U.startOfDay(window.U.now()), 7);
    el.value = window.U.toInputDate(d);
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await settle(page, 150);
  await page.keyboard.press('Escape');
  await settle(page, 250);
  await clickTestId(page, 'composer-save');
  await settle(page, 300);
  const saved = await page.evaluate(() => {
    const t = window.Store.liveTodos().find((x) => x.summary === '不重复测试');
    return t ? { start: t.startDate, rec: t.recurrence } : null;
  });
  assert(saved, 'the todo must be created');
  assertEq(saved.rec, null, 'no rule was applied');
  assertEq(saved.start, null, 'a dismissed 重复开始 must not be written');
  assertNoErrors(page);
  await page.close();
});

/* R5-7 — 计划这一天 never prefills a past slot */
scenario('R11-24 planning a past day prefills no slot', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => {
    window.Store.setBrowseDate(window.U.addDays(window.U.startOfDay(window.U.now()), -3));
    window.App.render();
  });
  await settle(page, 250);
  await clickTestId(page, 'plan-day');
  const start = await page.evaluate(() => window.Store.state.composerDraft.scheduleStart);
  assertEq(start, null, 'a past day has no future slot to prefill');
  assertNoErrors(page);
  await page.close();
});

/* R6-1 — month paging keeps the day and clamps */
scenario('R11-25 month paging keeps the day of month', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    window.Store.setLang('en');
    const d = new Date(2027, 0, 31);
    window.Store.state.calendarAnchor = d;
    window.Store.state.browseDate = d;
    window.Store.state.calendarView = 'month';
    window.App.go('calendar');
  });
  await settle(page, 300);
  await page.click('button[aria-label="Next"]');
  await settle(page, 250);
  const anchor = await page.evaluate(() => {
    const d = window.Store.state.calendarAnchor;
    return [d.getFullYear(), d.getMonth() + 1, d.getDate()];
  });
  assertEq(anchor, [2027, 2, 28], 'January 31 → February 28');
  assertNoErrors(page);
  await page.close();
});

/* R6-2 — a refused drop does not navigate */
scenario('R11-26 a refused allocation drop keeps the calendar and says why', async (browser) => {
  const page = await newPage(browser);
  const info = await page.evaluate(() => {
    const t = window.Store.liveTodos().find((x) => x.summary === '每周复盘');
    const today = window.U.startOfDay(window.U.now());
    // next Friday
    let d = today;
    while (d.getDay() !== 5) d = window.U.addDays(d, 1);
    if (d.getTime() === today.getTime()) d = window.U.addDays(d, 7);
    const s = new Date(d); s.setHours(12, 0, 0, 0);
    const e = new Date(s.getTime() + 3600000);
    const a = window.Store.createAllocation({ todoId: t.id, startAt: s, endAt: e, occurrenceId: window.Store.occurrenceIdFor(t, new Date(d)) });
    window.Store.state.calendarAnchor = new Date(d);
    window.Store.state.browseDate = new Date(d);
    window.Store.state.calendarView = 'week';
    window.App.go('calendar');
    return { alloc: a.id, todo: t.id, day: d.getTime() };
  });
  await settle(page, 400);
  const box = await page.evaluate((id) => {
    const b = document.querySelector(`[data-testid="alloc-block"][data-id="${id}"]`);
    if (!b) return null;
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    const col = document.querySelector('.time-body .daycol').getBoundingClientRect();
    return { x: r.left + 14, y: r.top + r.height / 2, colW: col.width };
  }, info.alloc);
  assert(box, 'the weekly block must be drawn on its Friday');
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x - box.colW, box.y, { steps: 6 });
  await page.mouse.up();
  await settle(page, 400);
  const after = await page.evaluate(() => ({
    route: window.Store.state.route.name,
    toast: (document.querySelector('#toast') || {}).innerText || '',
    start: window.Store.state.allocations.find((a) => a.todoId === window.Store.liveTodos().find((x) => x.summary === '每周复盘').id && a.state === 'active').startAt,
  }));
  assertEq(after.route, 'calendar', 'a refused drop must not open the record');
  assert(/实例日/.test(after.toast), 'the refusal must stay on screen, got: ' + after.toast);
  assertNoErrors(page);
  await page.close();
});

/* R7-1 — settings deep links land every time */
scenario('R11-27 a settings section link lands and then follows the user', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'sync' });
  assertEq(await page.evaluate(() => window.Store.state.settingsSection), 'account', 'sync must map to the sync section');
  await clickTestId(page, 'settings-nav-data');
  await page.evaluate(() => window.App.render());
  await settle(page, 250);
  assertEq(await page.evaluate(() => window.Store.state.settingsSection), 'data', 'a re-render must keep the chosen section');
  await go(page, 'action');
  await go(page, 'settings', { section: 'data' });
  assertEq(await page.evaluate(() => window.Store.state.settingsSection), 'data', 're-entering must apply the requested section again');
  assertNoErrors(page);
  await page.close();
});

/* R7-2 — the data section carries the frozen rows */
scenario('R11-28 the data section has every row and count', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'data' });
  const text = await bodyText(page);
  ['导出 .ics', '合并备份', '导出完整备份', '标签', '回收站'].forEach((s) => {
    assert(text.includes(s), `data section is missing ${s}`);
  });
  assert(/标签\s*\d+/.test(text) || /标签\s*4/.test(text), 'the tag count must be shown');
  assertNoErrors(page);
  await page.close();
});

/* R7-3 — import refuses an empty file choice */
scenario('R11-29 importing with no file claims nothing', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings', { section: 'data' });
  await clickText(page, '.setting-row', '导入日历');
  await clickText(page, '.sheet button.btn.primary', '导入');
  await settle(page, 400);
  const state = await page.evaluate(() => ({
    toast: (document.querySelector('#toast') || {}).innerText || '',
    hint: document.body.innerText,
  }));
  assert(!/已导入/.test(state.toast), 'no success claim without a file');
  assert(/请先选择/.test(state.hint), 'the refusal must say why');
  assertNoErrors(page);
  await page.close();
});

/* R7-4 — connected devices has loading, list, empty */
scenario('R11-30 connected devices has loading and empty states', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    window.Store.state.account = { signedIn: true, email: 'you@example.com', server: 'https://nas.local:8080', lastSync: window.U.now(), phase: 'idle', rejected: [] };
    window.App.go('settings', { section: 'sync' });
  });
  await settle(page, 250);
  await clickText(page, '.setting-row', '已连接设备');
  const loading = await exists(page, '.skeleton');
  assert(loading, 'the list must load, not appear instantly');
  await settle(page, 700);
  assert((await page.evaluate(() => document.querySelectorAll('[data-testid="device-row"]').length)) >= 2, 'devices must list after loading');
  while (await exists(page, '[data-testid="device-remove"]')) {
    await clickTestId(page, 'device-remove');
  }
  assert(/没有其他已连接的设备/.test(await bodyText(page)), 'the empty state must explain itself');
  assert((await page.evaluate(() => document.querySelectorAll('[data-testid="device-row"]').length)) >= 1,
    'this device stays listed and is not removable');
  assertNoErrors(page);
  await page.close();
});

/* R7-5 — deleting a calendar with content soft-deletes it */
scenario('R11-31 deleting a calendar with content moves items to Trash', async (browser) => {
  const page = await newPage(browser);
  const before = await page.evaluate(() => {
    const cal = window.Store.state.calendars.find((c) => c.name === '工作');
    const ids = window.Store.liveTodos().filter((t) => t.calendarId === cal.id).map((t) => t.id);
    const eventIds = window.Store.liveEvents().filter((e) => e.calendarId === cal.id).map((e) => e.id);
    return { cal: cal.id, ids, eventIds };
  });
  assert(before.ids.length + before.eventIds.length > 0, 'the seed calendar must have content');
  await go(page, 'calendars');
  await page.evaluate((id) => {
    const row = Array.from(document.querySelectorAll('[data-testid="calendar-row"]')).find((r) => r.textContent.includes('工作'));
    const buttons = row.querySelectorAll('button');
    buttons[buttons.length - 1].click();
  }, before.cal);
  await settle(page, 250);
  await clickText(page, '.sheet button', '删除日历和内容');
  await settle(page, 350);
  const after = await page.evaluate((ids) => ({
    trashedTodos: ids.ids.filter((id) => window.Store.deletedTodos().some((t) => t.id === id)).length,
    trashedEvents: ids.eventIds.filter((id) => window.Store.deletedEvents().some((e) => e.id === id)).length,
  }), before);
  assertEq(after.trashedTodos, before.ids.length, 'every affected todo must be in Trash');
  assertEq(after.trashedEvents, before.eventIds.length, 'every affected event must be in Trash');
  assertNoErrors(page);
  await page.close();
});

/* R7-6 — feedback opens GitHub or says it could not */
scenario('R11-32 feedback submit opens the issue URL', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => {
    window.__opened = [];
    window.open = (url) => { window.__opened.push(url); return { closed: false }; };
  });
  await go(page, 'feedback');
  await page.fill('[data-testid="feedback-text"]', '搜索在中文输入法下会丢字');
  await clickTestId(page, 'feedback-submit');
  const opened = await page.evaluate(() => window.__opened);
  assert(opened.length === 1 && /^https:\/\/github\.com\/liuchangchxy\/dayspark\/issues\/new/.test(opened[0]), 'submit must open the prefilled issue');
  assert(/GitHub/.test(await page.evaluate(() => (document.querySelector('#toast') || {}).innerText || '')), 'the result must be reported');
  assertNoErrors(page);
  await page.close();
});

/* R7-7 — the AI field closes while a reply is pending */
scenario('R11-33 the AI input is disabled while waiting', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'chat');
  await page.fill('[data-testid="chat-input"]', '今天还剩多少空闲时间');
  await clickTestId(page, 'chat-send');
  await settle(page, 200);
  assertEq(await page.evaluate(() => document.querySelector('[data-testid="chat-input"]').disabled), true, 'the field must be closed while pending');
  await settle(page, 900);
  assertEq(await page.evaluate(() => document.querySelector('[data-testid="chat-input"]').disabled), false, 'the field must reopen');
  assertNoErrors(page);
  await page.close();
});

/* R7-8 — a trashed record opens with its banner */
scenario('R11-34 a trashed todo opens with the deleted banner and restore', async (browser) => {
  const page = await newPage(browser);
  const id = await page.evaluate(() => window.Store.deletedTodos()[0].id);
  await page.evaluate((tid) => window.Store.navigate('detail', { type: 'todo', id: tid }), id);
  await settle(page, 320);
  assert(await exists(page, '[data-testid="detail-deleted"]'), 'the deleted banner must render');
  assert(await exists(page, '[data-testid="detail-restore"]'), 'restore must be offered');
  assertEq(await exists(page, '[data-testid="detail-edit"]'), false, 'a trashed record cannot be edited');
  assertNoErrors(page);
  await page.close();
});

/* R8-1 — English mode shows no Chinese sample text */
scenario('R11-35 English mode localizes seed records', async (browser) => {
  const page = await newPage(browser);
  await page.evaluate(() => window.Store.setLang('en'));
  await settle(page, 250);
  const data = await page.evaluate(() => ({
    todos: window.Store.liveTodos().map((t) => t.summary),
    tags: window.Store.state.tags.map((t) => t.name),
    cals: window.Store.state.calendars.map((c) => c.name),
  }));
  const cjk = /[一-鿿]/;
  const bad = data.todos.filter((s) => cjk.test(s));
  assertEq(bad, [], 'English mode must not show Chinese sample records');
  assertEq(data.tags.filter((s) => cjk.test(s)), [], 'tags must localize');
  assertEq(data.cals.filter((s) => cjk.test(s)), [], 'calendar names must localize');
  assert(data.tags.includes('Work'), 'the sample tag must read Work');
  await go(page, 'todos');
  assert(!cjk.test(await bodyText(page)), 'no Chinese may remain on the English Todos page');
  assertNoErrors(page);
  await page.close();
});

/* R9-1 — no phone resize control under 48px */
scenario('R11-36 every phone resize handle is a real 48px target', async (browser) => {
  const page = await newPage(browser, MOBILE);
  await go(page, 'calendar');
  await page.evaluate(() => { window.__calendarHelpers.setView('day'); window.App.render(); });
  await settle(page, 350);
  const handles = await page.evaluate(() => Array.from(document.querySelectorAll('.block .resize'))
    .filter((n) => n.offsetParent !== null)
    .map((n) => Math.round(n.getBoundingClientRect().height)));
  handles.forEach((h) => assert(h >= 48, 'a visible resize handle must be at least 48px, got ' + h));
  const shortNoHandle = await page.evaluate(() => Array.from(document.querySelectorAll('.block.no-resize'))
    .every((b) => !b.querySelector('.resize') || b.querySelector('.resize').offsetParent === null || getComputedStyle(b.querySelector('.resize')).display === 'none'));
  assert(shortNoHandle, 'a block too short for a 48px handle must not show one');
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
  console.log(`\n${passed}/${scenarios.length} round-11 scenarios passed`);
  if (failures.length) {
    console.log('\nFailures:');
    failures.forEach((f) => console.log(' - ' + f.name + ': ' + f.err.message.split('\n')[0]));
    process.exit(1);
  }
})();
