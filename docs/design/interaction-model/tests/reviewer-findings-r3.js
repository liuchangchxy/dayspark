/* Round-3 reviewer regression suite. Each scenario reproduces one finding from
   the third independent review, with that review's own repro steps, and asserts
   the contract CORE_UX_SPEC.md and BEHAVIORS.md promise.
   Numbering matches the review's list (P1-1 … P1-12, then P2/P3 notes). */
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

async function newPage(browser, viewport, opts) {
  const page = await browser.newPage(Object.assign({ viewport: viewport || DESKTOP }, opts || {}));
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
function assertNoErrors(page) {
  assert(page.__errors.length === 0, 'console errors: ' + page.__errors.slice(0, 3).join(' | '));
}

/* P1-1 — undo after completion must give the reservation back */
scenario('P1-1 undo after completion restores the invalidated allocation', async (browser) => {
  const page = await newPage(browser);
  const target = await page.evaluate(() => {
    const now = window.U.now();
    const alloc = window.Store.state.allocations.find((a) =>
      a.state === 'active' && a.startAt > now && !a.occurrenceId &&
      !window.Store.todoById(a.todoId).recurrence);
    return alloc ? { todoId: alloc.todoId, allocId: alloc.id } : null;
  });
  assert(target, 'seed data should contain a future single todo allocation');
  await go(page, 'action');
  const done = await page.evaluate(([todoId, allocId]) => {
    window.Store.completeTodo(todoId);
    const invalidated = window.Store.state.allocations.find((a) => a.id === allocId).state;
    window.Store.completeTodo(todoId);
    const restored = window.Store.state.allocations.find((a) => a.id === allocId).state;
    window.App.render();
    return { invalidated, restored };
  }, [target.todoId, target.allocId]);
  assertEq(done.invalidated, 'invalidatedByCompletion', 'completing must invalidate the future block');
  assertEq(done.restored, 'active', 'undo must reactivate the block it invalidated, not just reopen the todo');
  await settle(page, 200);
  const visible = await page.evaluate(
    (id) => !!document.querySelector(`[data-testid="action-allocation"][data-id="${id}"]`),
    target.todoId,
  );
  assert(visible, 'the restored block must be back on Today');
  assertNoErrors(page);
  await page.close();
});

/* P1-1b — the same for a recurring occurrence */
scenario('P1-1b undo of a completed occurrence restores its block', async (browser) => {
  const page = await newPage(browser);
  const target = await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    const todo = window.Store.liveTodos().find((t) => t.recurrence && window.Store.matchesRule(t, today));
    if (!todo) return null;
    const occ = window.Store.occurrenceIdFor(todo, today);
    const alloc = window.Store.state.allocations.find((a) =>
      a.todoId === todo.id && a.occurrenceId === occ && a.state === 'active');
    return alloc ? { todoId: todo.id, occ, allocId: alloc.id } : null;
  });
  assert(target, 'seed data should contain a repeating occurrence with a live block');
  const res = await page.evaluate(([id, occ, allocId]) => {
    window.Store.completeTodo(id, { occurrenceId: occ });
    const invalidated = window.Store.state.allocations.find((a) => a.id === allocId).state;
    window.Store.completeTodo(id, { occurrenceId: occ });
    const restored = window.Store.state.allocations.find((a) => a.id === allocId).state;
    window.App.render();
    return { invalidated, restored };
  }, [target.todoId, target.occ, target.allocId]);
  assertEq(res.invalidated, 'invalidatedByCompletion', 'completing the occurrence must invalidate its block');
  assertEq(res.restored, 'active', 'undo must reactivate that occurrence block');
  assertNoErrors(page);
  await page.close();
});

/* P1-2 — batch 完成 must never un-complete a finished occurrence */
scenario('P1-2 batch completion skips an occurrence that is already done', async (browser) => {
  const page = await newPage(browser);
  const target = await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    const todo = window.Store.liveTodos().find((t) => t.recurrence && window.Store.matchesRule(t, today));
    if (!todo) return null;
    const occ = window.Store.occurrenceIdFor(todo, today);
    window.Store.completeTodo(todo.id, { occurrenceId: occ });
    window.App.render();
    return { id: todo.id, occ };
  });
  assert(target, 'seed data should contain a repeating to-do matching today');
  await go(page, 'todos');
  await page.evaluate(() => window.__todoHelpers.setView({ kind: 'all', day: null }));
  await settle(page, 200);
  await page.evaluate(() => {
    Array.from(document.querySelectorAll('button')).find((x) => /选择|Select/.test(x.textContent)).click();
  });
  await settle(page, 180);
  await page.evaluate((id) => {
    const row = Array.from(document.querySelectorAll('[data-testid="todo-tile"]'))
      .find((n) => n.dataset.id === String(id));
    row.querySelector('.selbox').click();
  }, target.id);
  await settle(page, 160);
  await page.evaluate(() => {
    Array.from(document.querySelectorAll('button')).find((x) => /^完成$|^Complete$/.test(x.textContent.trim())).click();
  });
  await settle(page, 260);
  const still = await page.evaluate(([id, occ]) => {
    const t = window.Store.todoById(id);
    return !!(t.occurrenceStates && t.occurrenceStates[occ] && t.occurrenceStates[occ].completedAt);
  }, [target.id, target.occ]);
  assert(still, 'batch 完成 must not flip an already-completed occurrence back open');
  assertNoErrors(page);
  await page.close();
});

/* P1-3 — the Todo detail 更多 button must open its menu */
scenario('P1-3 the Todo detail More button opens a menu', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => {
    const id = window.Store.pendingTodos()[0].id;
    window.App.openRecord('todo', id);
  });
  await settle(page, 260);
  assert(await exists(page, '[data-testid="todo-detail"]'), 'todo detail should have opened');
  const opened = await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('.detail-head button')).find((b) =>
      /更多|More/.test(b.getAttribute('aria-label') || ''));
    if (!btn) return { found: false };
    btn.click();
    return { found: true, items: Array.from(document.querySelectorAll('.menu button')).map((n) => n.textContent.trim()) };
  });
  assert(opened.found, 'detail head should carry a More button');
  assert(opened.items.length >= 4, `More must open a menu with its actions, got ${JSON.stringify(opened.items)}`);
  assertNoErrors(page);
  await page.close();
});

/* P1-4 — every tool must be reachable by touch */
scenario('P1-4 mobile reaches Settings, Search, AI and Calendars by touch', async (browser) => {
  const page = await newPage(browser, MOBILE, { hasTouch: true, isMobile: true });
  await go(page, 'action');
  const reach = await page.evaluate(() => {
    const btn = document.querySelector('[data-testid="tab-more"]');
    if (!btn) return { more: false, labels: [] };
    btn.click();
    const labels = Array.from(document.querySelectorAll('.menu button')).map((n) => n.textContent.trim());
    return { more: true, labels };
  });
  assert(reach.more, 'the mobile shell needs a More entry');
  ['搜索', 'AI 助手', '标签', '日历管理', '回收站', '设置'].forEach((label) => {
    assert(reach.labels.some((x) => x.includes(label)), `${label} must be reachable on mobile, got ${JSON.stringify(reach.labels)}`);
  });
  // And it must actually navigate, not just render a label.
  await page.evaluate(() => {
    Array.from(document.querySelectorAll('.menu button')).find((n) => /设置/.test(n.textContent)).click();
  });
  await settle(page, 260);
  assertEq(await page.evaluate(() => window.Store.state.route.name), 'settings', 'More → 设置 must land on Settings');
  assertNoErrors(page);
  await page.close();
});

/* P1-5 — no touch target below 48dp on the primary surfaces */
scenario('P1-5 every touch target on a phone is at least 48dp tall', async (browser) => {
  const page = await newPage(browser, MOBILE, { hasTouch: true, isMobile: true });
  // What counts is the area a finger can land on, which for time-scaled
  // calendar blocks is the expanded ::after box rather than the painted block.
  await page.addScriptTag({
    content: `
      window.__hitTester = function () {
        const out = [];
        document.querySelectorAll('button, [role="button"], [role="checkbox"], input, select, textarea')
          .forEach((n) => {
            const r = n.getBoundingClientRect();
            if (r.width === 0 || r.height === 0) return;
            const cs = getComputedStyle(n);
            if (cs.visibility === 'hidden' || cs.display === 'none') return;
            if (n.closest('[hidden]')) return;
            let w = r.width, h = r.height;
            const after = getComputedStyle(n, '::after');
            if (after && after.content && after.content !== 'none' && after.content !== 'normal') {
              const ah = parseFloat(after.height);
              const aw = parseFloat(after.width);
              if (!Number.isNaN(ah) && ah > h) h = ah;
              if (!Number.isNaN(aw) && aw > w) w = aw;
            }
            if (Math.min(w, h) < 48) {
              out.push({
                surface: window.Store.state.route.name,
                cls: String(n.className).slice(0, 36),
                w: Math.round(w), h: Math.round(h),
                paintedH: Math.round(r.height),
                text: (n.textContent || '').trim().slice(0, 14),
              });
            }
          });
        return out;
      };
    `,
  });
  const report = [];
  for (const surface of ['action', 'todos', 'calendar']) {
    await go(page, surface);
    await settle(page, 220);
    report.push(...await page.evaluate(() => window.__hitTester()));
  }
  const detail = await (async () => {
    await go(page, 'todos');
    await page.evaluate(() => window.App.openRecord('todo', window.Store.pendingTodos()[0].id));
    await settle(page, 240);
    return page.evaluate(() => window.__hitTester());
  })();
  report.push(...detail);
  assertEq(report, [], `every phone touch target must be >= 48dp; ${report.length} are smaller: ${JSON.stringify(report.slice(0, 8))}`);
  assertNoErrors(page);
  await page.close();
});

/* P1-6 — desktop keeps the list beside the detail (CORE_UX_SPEC 4) */
scenario('P1-6 desktop master-detail keeps the list visible beside the detail', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await settle(page, 240);
  const before = await page.evaluate(() => ({
    rows: document.querySelectorAll('[data-testid="todo-tile"]').length,
    md: !!document.querySelector('[data-testid="todos-masterdetail"]'),
  }));
  assert(before.md, 'at 1440 the Todo destination must render a master-detail layout');
  assert(before.rows > 0, 'seed data should list rows');
  await page.evaluate(() => {
    document.querySelector('[data-testid="todo-tile"] .todo-row').click();
  });
  await settle(page, 280);
  const after = await page.evaluate(() => ({
    rows: document.querySelectorAll('[data-testid="todo-tile"]').length,
    pane: !!document.querySelector('[data-testid="detail-pane-body"]'),
    route: window.Store.state.route.name,
    selected: document.querySelectorAll('.md-selected').length,
    close: !!document.querySelector('[data-testid="pane-close"]'),
  }));
  assertEq(after.route, 'todos', 'opening a record in the pane must not leave the Todo destination');
  assert(after.pane, 'the detail pane must render the selected record');
  assertEq(after.rows, before.rows, 'the list must stay visible while the detail is open');
  assert(after.selected > 0, 'the selected row must read as selected');
  assert(after.close, 'the pane needs a visible close affordance, not only Escape');

  // Closing puts the user back exactly where they were.
  await page.evaluate(() => document.querySelector('[data-testid="pane-close"]').click());
  await settle(page, 240);
  const closed = await page.evaluate(() => ({
    pane: !!document.querySelector('[data-testid="detail-pane-body"]'),
    rows: document.querySelectorAll('[data-testid="todo-tile"]').length,
    route: window.Store.state.route.name,
  }));
  assert(!closed.pane, 'close must dismiss the pane');
  assertEq(closed.rows, before.rows, 'closing must not disturb the list');
  assertEq(closed.route, 'todos', 'closing must not navigate away');

  // Escape closes the pane before it leaves the page.
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 220);
  await page.keyboard.press('Escape');
  await settle(page, 240);
  const esc = await page.evaluate(() => ({
    pane: !!document.querySelector('[data-testid="detail-pane-body"]'),
    route: window.Store.state.route.name,
    tab: window.Store.state.tab,
  }));
  assert(!esc.pane, 'Escape must close the pane');
  assertEq(esc.route, 'todos', 'Escape closes the pane, it does not leave the page');

  // Changing destination clears the selection.
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 200);
  await go(page, 'calendar');
  await go(page, 'todos');
  const back = await page.evaluate(() => !!document.querySelector('[data-testid="detail-pane-body"]'));
  assert(!back, 'changing destination must clear the pane selection');
  assertNoErrors(page);
  await page.close();
});

/* P1-6b — mobile still uses a full-page detail */
scenario('P1-6b mobile opens a full detail page, not a pane', async (browser) => {
  const page = await newPage(browser, MOBILE, { hasTouch: true, isMobile: true });
  await go(page, 'todos');
  await settle(page, 220);
  await page.evaluate(() => document.querySelector('[data-testid="todo-tile"] .todo-row').click());
  await settle(page, 260);
  const res = await page.evaluate(() => ({
    md: !!document.querySelector('[data-testid="todos-masterdetail"]'),
    detail: !!document.querySelector('[data-testid="todo-detail"]'),
    route: window.Store.state.route.name,
    back: !!Array.from(document.querySelectorAll('.detail-head button')).find((b) => /返回|Back/.test(b.getAttribute('aria-label') || '')),
  }));
  assert(!res.md, 'a phone has no room for a pane; it must not render one');
  assert(res.detail, 'the phone must show the full detail');
  assertEq(res.route, 'detail', 'the phone navigates to the detail route');
  assert(res.back, 'the phone detail needs a visible back control');
  assertNoErrors(page);
  await page.close();
});

/* P1-7 — a planned-and-due todo appears once on Today */
scenario('P1-7 Today shows a planned-and-due todo exactly once', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await settle(page, 240);
  const res = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('[data-testid="action-allocation"], [data-testid="action-todo"]'));
    const counts = {};
    rows.forEach((r) => {
      const title = r.querySelector('.row-title');
      const key = title ? title.textContent.trim() : '';
      counts[key] = (counts[key] || 0) + 1;
    });
    return Object.entries(counts).filter(([, n]) => n > 1);
  });
  assertEq(res, [], `Today must not render the same obligation twice, duplicated: ${JSON.stringify(res)}`);
  // And the surviving row for a planned+due todo is the allocation, with the
  // deadline attached as metadata.
  const meta = await page.evaluate(() => {
    const alloc = document.querySelector('[data-testid="action-allocation"]');
    return alloc ? alloc.querySelector('.row-meta').textContent : '';
  });
  assert(/截止|Due/.test(meta), `a planned row must carry its deadline as metadata, got "${meta}"`);
  assertNoErrors(page);
  await page.close();
});

/* P1-8 — one browsed date shared by Todo and Calendar */
scenario('P1-8 Todo and Calendar share one browsed date', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await settle(page, 240);
  const picked = await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    const day = window.U.addDays(today, 2);
    window.__todoHelpers.setView({ kind: 'day', day });
    return day.getTime();
  });
  await settle(page, 220);
  await go(page, 'calendar');
  const calMs = await page.evaluate(() => window.Store.browseDate().getTime());
  assertEq(calMs, picked, 'picking a day in Todo must move the calendar to the same day');

  // …and the other direction.
  const calPicked = await page.evaluate(() => {
    const day = window.U.addDays(window.U.startOfDay(window.U.now()), 5);
    window.Store.setBrowseDate(day);
    window.App.render();
    return day.getTime();
  });
  await settle(page, 200);
  await go(page, 'todos');
  const todoMs = await page.evaluate(() => window.Store.state.todosView.day.getTime());
  assertEq(todoMs, calPicked, 'picking a day in the calendar must move the Todo day list');

  // Today is not part of the browse date.
  const todayUnaffected = await page.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    window.Store.setBrowseDate(window.U.addDays(today, 9));
    return window.U.sameDay(window.Store.actionProjection().day, today);
  });
  assert(todayUnaffected, 'browsing must never move Today off the real today');
  assertNoErrors(page);
  await page.close();
});

/* P1-9 — a far date is reachable without a dozen taps */
scenario('P1-9 the Todo date header opens a month picker', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await settle(page, 240);
  assert(await exists(page, '[data-testid="todos-date-picker"]'), 'the date subtitle must be an actionable control');
  await page.click('[data-testid="todos-date-picker"]');
  await settle(page, 240);
  assert(await exists(page, '.sheet'), 'the date header must open a picker sheet');
  const moved = await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('button')).find((b) => /»/.test(b.textContent));
    if (!btn) return { ok: false };
    btn.click();
    const days = Array.from(document.querySelectorAll('[data-testid="picker-day"]'));
    if (!days.length) return { ok: false };
    const target = days.find((d) => !d.classList.contains('out'));
    target.click();
    return { ok: true };
  });
  assert(moved.ok, 'the picker must offer year navigation and day cells');
  await settle(page, 240);
  const res = await page.evaluate(() => ({
    sheet: !!document.querySelector('.sheet'),
    day: window.Store.state.todosView.day.getFullYear(),
  }));
  assert(!res.sheet, 'picking a day must close the picker');
  assert(res.day > new Date().getFullYear(), `the year step must actually reach next year, got ${res.day}`);
  assertNoErrors(page);
  await page.close();
});

/* P1-10 — 所属日历 is a picker with colour, selection and + 新建日历 */
scenario('P1-10 the calendar field is a picker that can create a calendar', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 300);
  assert(await exists(page, '[data-testid="calendar-picker"]'), 'the composer must render the calendar picker');
  await page.click('[data-testid="calendar-picker"]');
  await settle(page, 240);
  const sheet = await page.evaluate(() => ({
    options: document.querySelectorAll('[data-testid="calendar-option"]').length,
    colored: Array.from(document.querySelectorAll('[data-testid="calendar-option"] .dot'))
      .every((d) => !!d.style.background),
    selected: document.querySelectorAll('[data-testid="calendar-option"][aria-pressed="true"]').length,
    create: !!document.querySelector('[data-testid="calendar-new"]'),
  }));
  assert(sheet.options >= 1, 'the picker must list calendars even when there is only one');
  assert(sheet.colored, 'each calendar option must show its colour');
  assertEq(sheet.selected, 1, 'exactly the current calendar must read as selected');
  assert(sheet.create, 'the picker must always offer + 新建日历');

  await page.click('[data-testid="calendar-new"]');
  await settle(page, 240);
  assert(await exists(page, '[data-testid="calendar-name"]'), 'creating a calendar must ask for a name');
  await page.fill('[data-testid="calendar-name"]', '原型新日历');
  await page.click('[data-testid="calendar-create"]');
  await settle(page, 320);
  const after = await page.evaluate(() => ({
    exists: window.Store.state.calendars.some((c) => c.name === '原型新日历'),
  }));
  assert(after.exists, 'the new calendar must be created');
  assertNoErrors(page);
  await page.close();
});

/* P1-11 — Settings renders no raw i18n key */
scenario('P1-11 Settings shows no raw i18n keys', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings');
  await settle(page, 260);
  const leaks = await page.evaluate(() => {
    const dict = {};
    // A missing key renders as the key itself: ASCII camelCase in Chinese copy.
    const text = document.body.textContent;
    const found = new Set();
    (text.match(/\b[a-z][a-zA-Z0-9]{5,}\b/g) || []).forEach((w) => {
      if (/^[a-z]+([A-Z][a-z]+)+$/.test(w)) found.add(w);
    });
    return Array.from(found);
  });
  assertEq(leaks, [], `Settings must not leak raw i18n keys, got ${JSON.stringify(leaks)}`);
  const manage = await page.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.setting-row, .group-label, .list-row'))
      .find((n) => /日历管理|Calendars/.test(n.textContent));
    return !!row;
  });
  assert(manage, 'Settings must carry the 日历管理 entry');
  assertNoErrors(page);
  await page.close();
});

/* P1-12 — the form follows the frozen five-section order */
scenario('P1-12 the Todo form uses the 任务/时间/提醒/整理/内容 sections', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 320);
  const order = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.form-section-title')).map((n) => n.textContent.trim()));
  assertEq(order, ['任务', '时间', '提醒', '整理', '内容'], 'the form must present the five sections in order');

  // 重复 belongs to 时间, not to a collapsed extra panel.
  const repeatInTime = await page.evaluate(() => {
    const titles = Array.from(document.querySelectorAll('.form-section-title'));
    const timeSec = titles.find((n) => n.textContent.trim() === '时间');
    if (!timeSec) return false;
    let node = timeSec.nextElementSibling;
    while (node) {
      if (node.querySelector('[data-testid="composer-repeat"]')) return true;
      node = node.nextElementSibling;
    }
    return false;
  });
  assert(repeatInTime, '重复 must live inside 时间');

  // The detail reads in the same order.
  await page.evaluate(() => window.App.back());
  await settle(page, 220);
  await page.evaluate(() => window.App.openRecord('todo', window.Store.pendingTodos()[0].id));
  await settle(page, 300);
  const detailOrder = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.detail-facts .form-section-title')).map((n) => n.textContent.trim()));
  assertEq(detailOrder, ['时间', '提醒', '整理', '内容'], 'the detail must use the same section order as the editor');
  assertNoErrors(page);
  await page.close();
});

/* P2-1 — mobile create stays a stable top-right action, not a FAB */
scenario('P2-1 mobile create is a header action, not a floating button', async (browser) => {
  const page = await newPage(browser, MOBILE, { hasTouch: true, isMobile: true });
  for (const surface of ['action', 'todos']) {
    await go(page, surface);
    await settle(page, 220);
    const res = await page.evaluate(() => {
      const btn = document.querySelector('[data-testid="action-create"], [data-testid="todos-create"]');
      if (!btn) return { found: false };
      const cs = getComputedStyle(btn);
      const r = btn.getBoundingClientRect();
      return {
        found: true,
        fixed: cs.position === 'fixed',
        inHead: !!btn.closest('.page-head'),
        bottom: Math.round(window.innerHeight - r.bottom),
      };
    });
    assert(res.found, `${surface}: mobile needs a create action`);
    assert(!res.fixed, `${surface}: create must not float (CORE_UX_SPEC 1.2 says no FAB)`);
    assert(res.inHead, `${surface}: create belongs in the page header`);
  }
  assertNoErrors(page);
  await page.close();
});

/* P2-2 — TaskAllocation is called 计划执行 */
scenario('P2-2 the planned-execution noun is 计划执行', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 300);
  const bodyText = await page.evaluate(() => document.querySelector('[data-testid="composer"]').textContent);
  assert(!bodyText.includes('安排执行'), 'the noun is 计划执行, not 安排执行');
  assert(bodyText.includes('计划执行'), 'the composer must name the field 计划执行');
  assertNoErrors(page);
  await page.close();
});

/* P2-3/P2-4 — sync explains itself; backup merge is 合并备份 */
scenario('P2-3 sync explains itself and backup says 合并备份', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings');
  await settle(page, 300);
  const desc = await page.evaluate(() => {
    const n = document.querySelector('.group-desc');
    return n ? n.textContent.trim() : '';
  });
  assert(/多台设备|多设备|multiple devices|multi-device/i.test(desc),
    `the sync group must explain what sync is for, got "${desc}"`);
  assert(/备份/.test(await page.evaluate(() => document.body.textContent)), 'settings must expose backup');

  // 合并备份 is the label inside the backup sheet, so open it and read it there.
  const merge = await page.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.setting-row, .list-row'))
      .find((n) => /完整备份|Full backup/.test(n.textContent));
    if (!row) return '';
    row.click();
    const btn = Array.from(document.querySelectorAll('.slot-sheet-option .t, .sheet button'))
      .map((n) => n.textContent.trim()).find((t) => /合并/.test(t));
    return btn || '';
  });
  assert(merge.startsWith('合并备份'), `backup merge must read 合并备份, got "${merge}"`);
  assert(!/恢复/.test(merge), `backup merge must not say 恢复 (it merges, it does not replace): "${merge}"`);
  assertNoErrors(page);
  await page.close();
});

/* P2-5 — no raw keys in user-visible toasts */
scenario('P2-5 export and permission toasts are localized', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'settings');
  await settle(page, 260);
  const msg = await page.evaluate(() => {
    window.UI.toast(window.I18N.t('exportedTo', { p: 'dayspark.ics' }));
    const n = document.querySelector('.toast');
    return n ? n.textContent : '';
  });
  assert(!/exportedTo/.test(msg), `export toast must be localized, got "${msg}"`);
  assert(/dayspark\.ics/.test(msg), 'the export toast must name the file');
  assertNoErrors(page);
  await page.close();
});

/* P2-6 — the composer does not accuse the user before they type */
scenario('P2-6 the composer shows no error before any interaction', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'todos');
  await page.evaluate(() => window.App.openComposer('todo', {}));
  await settle(page, 320);
  const res = await page.evaluate(() => {
    // A hidden node still answers querySelector; ask what is actually painted.
    const visible = (n) => {
      if (!n) return false;
      const r = n.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) return false;
      const cs = getComputedStyle(n);
      return cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
    };
    const errs = Array.from(document.querySelectorAll('.hint-box.error, [role="alert"]'));
    return {
      visibleErrors: errs.filter(visible).map((n) => n.textContent.trim()).filter(Boolean),
      invalidField: !!document.querySelector('.invalid'),
      saveDisabled: (() => {
        const b = document.querySelector('[data-testid="composer-save"], [data-testid="composer-save-foot"]');
        return b ? b.disabled : null;
      })(),
    };
  });
  assertEq(res.visibleErrors, [], 'an empty new form must not show a validation error before the user acts');
  assert(!res.invalidField, 'no field may be marked invalid before the user types');
  assert(res.saveDisabled === true, 'saving an empty title must still be disabled');
  assertNoErrors(page);
  await page.close();
});

/* P3-1 — a fourth capture is still visible in the unplanned preview */
scenario('P3-1 the item just captured is visible even past the preview cap', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await settle(page, 240);
  await page.evaluate(() => {
    // Push past the three-row preview, then capture one more via the real box.
    for (let i = 0; i < 4; i += 1) window.Store.createTodo({ summary: '填满预览 ' + i });
    window.App.render();
  });
  await settle(page, 220);
  await page.fill('[data-testid="action-capture"]', '第四条之后的捕获');
  await page.press('[data-testid="action-capture"]', 'Enter');
  await settle(page, 320);
  const found = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('[data-testid="action-todo"]'));
    return rows.some((r) => r.textContent.includes('第四条之后的捕获'));
  });
  assert(found, 'the item just captured must be visible where it landed, not only counted');
  assertNoErrors(page);
  await page.close();
});

/* P3-2 — Escape in the search input leaves the page */
scenario('P3-2 Escape in the search input returns', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'search');
  await settle(page, 240);
  await page.fill('[data-testid="search-input"]', 'abc');
  await page.focus('[data-testid="search-input"]');
  await page.keyboard.press('Escape');
  await settle(page, 260);
  const route = await page.evaluate(() => window.Store.state.route.name);
  assert(route !== 'search', 'Escape must leave Search even with the input focused');
  assertNoErrors(page);
  await page.close();
});

/* P3-3 — section and group names follow the spec */
scenario('P3-3 Today and Settings use the frozen section names', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'action');
  await settle(page, 260);
  const heads = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.section-head span')).map((n) => n.textContent.trim()));
  ['稍后今天', '今天要完成'].forEach((bad) => {
    assert(!heads.includes(bad), `Today must not use the retired name ${bad}, got ${JSON.stringify(heads)}`);
  });
  const overdue = heads.some((h) => /已逾期/.test(h)) || heads.length === 0;
  assert(overdue || !heads.some((h) => /^逾期$/.test(h)), 'the overdue heading reads 已逾期, not 逾期');
  await go(page, 'settings');
  await settle(page, 260);
  const groups = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.group-label, .setting-group .t, .section-title')).map((n) => n.textContent.trim()));
  assert(!groups.includes('外观'), `Settings group is 通用, not 外观; got ${JSON.stringify(groups)}`);
  assertNoErrors(page);
  await page.close();
});

/* P3-4 — the slot sheet offers exactly the two named jobs */
scenario('P3-4 the calendar slot sheet offers the two named jobs', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'calendar');
  await settle(page, 300);
  const labels = await page.evaluate(() => {
    window.__calendarHelpers.openSlotSheet(new Date(), 9, 10);
    const nodes = Array.from(document.querySelectorAll('.slot-sheet-option .t'));
    return nodes.map((n) => n.textContent.trim());
  });
  assertEq(labels, ['新建日程', '安排待办'], `the slot sheet names exactly the two real jobs, got ${JSON.stringify(labels)}`);
  assertNoErrors(page);
  await page.close();
});

/* P3-5 — applying a proposal twice writes once */
scenario('P3-5 applying an AI proposal twice writes one allocation', async (browser) => {
  const page = await newPage(browser);
  await go(page, 'chat');
  await settle(page, 280);
  const before = await page.evaluate(() => window.Store.state.allocations.length);
  await page.fill('[data-testid="chat-input"]', '把「Q4 预算表」安排到明天上午');
  await page.evaluate(() => document.querySelector('[data-testid="chat-send"]').click());
  await page.waitForSelector('[data-testid="ai-apply"]', { timeout: 4000 });
  const after = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="ai-apply"]');
    b.click();
    b.click();
    return window.Store.state.allocations.length;
  });
  await settle(page, 260);
  assertEq(after - before, 1, 'applying a proposal twice must still write exactly one allocation');
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
  console.log(`\n${pass}/${pass + fail} round-3 findings hold`);
  if (fail) process.exit(1);
})();
