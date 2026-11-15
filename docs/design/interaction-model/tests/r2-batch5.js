const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP, MOBILE } = L;

const results = [];
async function run(name, fn) {
  try { await fn(); results.push([name, 'PASS', '']); console.log('PASS', name); }
  catch (e) { results.push([name, 'FAIL', e.message]); console.log('FAIL', name + ':', e.message); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function openTomorrowDay(page) {
  await L.go(page, 'calendar');
  await page.click('[data-testid="cal-view-day"]');
  await settle(page, 250);
  await page.click('button[aria-label="下一段"]');
  await settle(page, 300);
}
async function clickRecurringBlock(page) {
  const idx = await page.evaluate(() => Array.from(document.querySelectorAll('[data-testid="event-block"]')).findIndex((n) => /周会/.test(n.textContent)));
  assert(idx >= 0, 'recurring block found');
  await page.locator('[data-testid="event-block"]').nth(idx).click();
  await settle(page, 350);
}

async function main() {
  const browser = await launch();
  try {
    await run('R1 complete / undo / re-complete non-recurring', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await settle(page, 300);
      const tile = page.locator('[data-testid="todo-tile"]', { hasText: '买牛奶和咖啡豆' }).first();
      await tile.locator('[role="checkbox"]').click();
      await settle(page, 350);
      let st = await state(page);
      let t = st.todos.find((x) => x.summary === '买牛奶和咖啡豆');
      console.log('R1 after complete:', t.status, t.completedAt);
      assertEq(t.status, 'COMPLETED', 'completed');
      const inDone = await L.text(page, '[data-testid="todo-list"]');
      assert(/已完成/.test(inDone) && /买牛奶和咖啡豆/.test(inDone), 'shows under completed');
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 350);
      st = await state(page);
      t = st.todos.find((x) => x.summary === '买牛奶和咖啡豆');
      assertEq(t.status, 'NEEDS-ACTION', 'uncompleted by undo');
      assertEq(t.completedAt, null, 'completedAt cleared');
      // re-complete
      const tile2 = page.locator('[data-testid="todo-tile"]', { hasText: '买牛奶和咖啡豆' }).first();
      await tile2.locator('[role="checkbox"]').click();
      await settle(page, 350);
      st = await state(page);
      t = st.todos.find((x) => x.summary === '买牛奶和咖啡豆');
      assertEq(t.status, 'COMPLETED', 're-completed');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R2 complete / undo recurring occurrence from Action', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'action');
      await settle(page, 400);
      const rows = await L.texts(page, '[data-testid="action-instance"]');
      console.log('R2 recurring instance rows:', rows.slice(0, 4));
      const row = page.locator('[data-testid="action-instance"]', { hasText: '读 20 页' }).first();
      await row.locator('[role="checkbox"]').click();
      await settle(page, 400);
      let st = await state(page);
      let t = st.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
      let occ = Object.keys(t.occurrenceStates);
      console.log('R2 after complete:', occ);
      assertEq(occ.length, 1, 'one occurrence completed');
      assertEq(t.status, 'NEEDS-ACTION', 'series still open');
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      st = await state(page);
      t = st.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
      assertEq(Object.keys(t.occurrenceStates).length, 0, 'undo removes occurrence completion');
      // re-complete
      await page.locator('[data-testid="action-instance"]', { hasText: '读 20 页' }).first().locator('[role="checkbox"]').click();
      await settle(page, 350);
      st = await state(page);
      t = st.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
      assertEq(Object.keys(t.occurrenceStates).length, 1, 're-complete occurrence');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R3 delete todo, restore, fields preserved', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await settle(page, 300);
      await page.locator('[data-testid="todo-tile"]', { hasText: '写 v0.29 发布说明' }).first().click();
      await settle(page, 300);
      const before = await state(page);
      const t0 = before.todos.find((x) => x.summary === '写 v0.29 发布说明');
      const a0 = before.allocations.filter((a) => a.todoId === t0.id);
      await L.clickText(page, '.detail-actions button', '移到回收站');
      await settle(page, 250);
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 450);
      let st = await state(page);
      assert(st.todos.find((x) => x.id === t0.id).deletedAt, 'todo soft deleted');
      assertEq(st.route.name, 'todos', 'left detail after delete');
      await L.go(page, 'trash');
      await settle(page, 300);
      assert(/写 v0\.29 发布说明/.test(await L.text(page, '#view')), 'appears in trash');
      const trashRow = page.locator('[data-testid="trash-row"]', { hasText: '写 v0.29 发布说明' }).first();
      await trashRow.locator('[data-testid="trash-restore"]').click();
      await settle(page, 350);
      st = await state(page);
      const t1 = st.todos.find((x) => x.id === t0.id);
      const a1 = st.allocations.filter((a) => a.todoId === t0.id);
      console.log('R3 restored fields:', { deletedAt: t1.deletedAt, due: t1.dueDate, allocs: a1 });
      assertEq(t1.deletedAt, null, 'restored');
      assertEq(t1.dueDate, t0.dueDate, 'due date preserved');
      assertEq(a1.length, a0.length, 'allocations preserved');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R4 parent delete/restore + purge keeps subtasks consistent', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      await page.locator('[data-testid="todo-tile"]', { hasText: '准备季度评审' }).first().click();
      await settle(page, 300);
      const parentId = (await state(page)).route.params.id;
      const subs = await page.evaluate((pid) => window.Store.subtasksOf(pid).map((s) => ({ id: s.id, summary: s.summary })), parentId);
      console.log('R4 subtasks:', subs);
      await L.clickText(page, '.detail-actions button', '移到回收站');
      await settle(page, 250);
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 400);
      let st = await state(page);
      console.log('R4 after parent delete:', st.todos.filter((t) => t.id === parentId || subs.some((s) => s.id === t.id)).map((t) => ({ id: t.id, del: t.deletedAt })));
      assert(st.todos.find((t) => t.id === parentId).deletedAt, 'parent deleted');
      assert(st.todos.filter((t) => subs.some((s) => s.id === t.id)).every((t) => t.deletedAt), 'subtasks cascaded');
      // restore parent from trash and observe children
      await L.go(page, 'trash');
      await settle(page, 300);
      await shot(page, 'R4-01-trash-parent-and-children');
      const restoreBtns = await L.texts(page, '#view button');
      console.log('R4 trash buttons sample:', restoreBtns.slice(0, 12));
      await page.evaluate((pid) => {
        const btns = Array.from(document.querySelectorAll('#view button'));
        const row = btns.find((b) => b.parentElement && /准备季度评审/.test(b.parentElement.textContent));
        if (row) row.click();
      }, parentId);
      await settle(page, 400);
      st = await state(page);
      const parentAfter = st.todos.find((t) => t.id === parentId);
      const subsAfter = st.todos.filter((t) => subs.some((s) => s.id === t.id));
      console.log('R4 after restoring parent:', { parentDeleted: parentAfter.deletedAt, subs: subsAfter.map((s) => ({ summary: s.summary, del: s.deletedAt })) });
      const subsRestored = subsAfter.every((s) => !s.deletedAt);
      assert(parentAfter.deletedAt === null, 'parent restored');
      assert(subsRestored, 'restoring a parent should bring its cascaded subtasks back (currently stays deleted)');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R5 event delete / undo / trash restore', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'calendar');
      await page.click('[data-testid="cal-view-day"]');
      await settle(page, 300);
      const idx = await page.evaluate(() => Array.from(document.querySelectorAll('[data-testid="event-block"]')).findIndex((n) => /与设计师午餐/.test(n.textContent)));
      await page.locator('[data-testid="event-block"]').nth(idx).click();
      await settle(page, 350);
      await page.click('#view button[aria-label="移到回收站"]');
      await settle(page, 250);
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 400);
      let st = await state(page);
      const e = st.events.find((x) => x.summary === '与设计师午餐');
      assert(e.deletedAt, 'event deleted');
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 350);
      st = await state(page);
      assertEq(st.events.find((x) => x.id === e.id).deletedAt, null, 'undo restored');
      // delete again, restore from trash
      await L.go(page, 'calendar');
      await page.click('[data-testid="cal-view-day"]');
      await settle(page, 250);
      await page.locator('[data-testid="event-block"]', { hasText: '与设计师午餐' }).first().click();
      await settle(page, 250);
      await page.click('#view button[aria-label="移到回收站"]');
      await settle(page, 200);
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 350);
      await L.go(page, 'trash');
      await settle(page, 300);
      assert(/与设计师午餐/.test(await L.text(page, '#view')), 'event in trash');
      await page.locator('[data-testid="trash-row"]', { hasText: '与设计师午餐' }).first().locator('[data-testid="trash-restore"]').click();
      await settle(page, 350);
      st = await state(page);
      assertEq(st.events.find((x) => x.id === e.id).deletedAt, null, 'trash restore works');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R6 edit the same occurrence twice (no duplicate copies)', async () => {
      const page = await newPage(browser, DESKTOP);
      await openTomorrowDay(page);
      const seriesId = await page.evaluate(() => window.Store.state.events.find((e) => e.rrule).id);
      await clickRecurringBlock(page);
      await page.click('#view button[aria-label="编辑"]');
      await settle(page, 250);
      await page.click('[data-testid="scope-this"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '周会 副本A');
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      await shot(page, 'R6-01-after-first-split');
      console.log('R6 route after first split:', (await state(page)).route);
      // still on the (now stale) occurrence detail; Edit again -> this -> save
      await page.click('#view button[aria-label="编辑"]');
      await settle(page, 250);
      const hasScope = await L.exists(page, '.sheet');
      if (hasScope) await page.click('[data-testid="scope-this"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '周会 副本B');
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      await shot(page, 'R6-02-after-second-split');
      const st = await state(page);
      const series = st.events.find((e) => e.id === seriesId);
      const copies = st.events.filter((e) => !e.rrule && /周会 副本/.test(e.summary));
      console.log('R6 series exdates:', series.exdates, 'copies:', copies.map((c) => ({ id: c.id, s: c.startDt, t: c.summary })));
      assertEq(copies.length, 1, 'editing the same occurrence twice must not create two standalone copies');
      assertEq(new Set(series.exdates).size, series.exdates.length, 'no duplicate exdates');
      await page.close();
    });

    await run('R7 split occurrence, delete copy, undo', async () => {
      const page = await newPage(browser, DESKTOP);
      await openTomorrowDay(page);
      await clickRecurringBlock(page);
      await page.click('#view button[aria-label="编辑"]');
      await settle(page, 200);
      await page.click('[data-testid="scope-this"]');
      await settle(page, 250);
      await page.fill('[data-testid="composer-title"]', '周会 单次');
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      const st0 = await state(page);
      const copy = st0.events.find((e) => e.summary === '周会 单次');
      assert(copy, 'copy exists');
      // delete copy from calendar
      await L.go(page, 'calendar');
      await settle(page, 300);
      const idx = await page.evaluate(() => Array.from(document.querySelectorAll('[data-testid="event-block"]')).findIndex((n) => /周会 单次/.test(n.textContent)));
      console.log('R7 copy block index:', idx);
      assert(idx >= 0, 'copy block visible');
      await page.locator('[data-testid="event-block"]').nth(idx).click();
      await settle(page, 300);
      await page.click('#view button[aria-label="移到回收站"]');
      await settle(page, 200);
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 400);
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      const st1 = await state(page);
      assertEq(st1.events.find((e) => e.id === copy.id).deletedAt, null, 'undo restores the copy');
      assertEq(st1.events.find((e) => e.rrule).exdates.length, 1, 'series exdate untouched');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R8 delete future scope keeps earlier occurrences', async () => {
      const page = await newPage(browser, DESKTOP);
      // anchor a week after the first occurrence (2nd occurrence)
      await L.go(page, 'calendar');
      await page.click('[data-testid="cal-view-day"]');
      await settle(page, 250);
      await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.rrule);
        const d = new Date(e.startDt);
        d.setDate(d.getDate() + 7);
        window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        window.Store.state.calendarFocusDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        window.Store.state.calendarView = 'day';
        window.App.go('calendar');
      });
      await settle(page, 400);
      const before = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.rrule);
        const a = window.Store.state.calendarAnchor;
        const d0 = new Date(a.getTime() - 7 * 86400000);
        return { id: e.id, first: window.Store.eventsOnDay(d0).filter((x) => x.id === e.id).length, current: window.Store.eventsOnDay(a).filter((x) => x.id === e.id).length };
      });
      console.log('R8 before:', before);
      await clickRecurringBlock(page);
      await page.click('#view button[aria-label="移到回收站"]');
      await settle(page, 200);
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 250);
      await page.click('[data-testid="scope-future"]');
      await settle(page, 400);
      await shot(page, 'R8-01-after-future-delete');
      const after = await page.evaluate(() => {
        const S = window.Store;
        const e = S.state.events.find((x) => x.rrule);
        const a = S.state.calendarAnchor;
        const d0 = new Date(a.getTime() - 7 * 86400000);
        return {
          deletedAt: e.deletedAt, until: e.rrule.until,
          first: S.eventsOnDay(d0).filter((x) => x.id === e.id).length,
          current: S.eventsOnDay(a).filter((x) => x.id === e.id).length,
          weekLater: S.eventsOnDay(new Date(a.getTime() + 7 * 86400000)).filter((x) => x.id === e.id).length,
        };
      });
      console.log('R8 after future delete:', after);
      assertEq(after.deletedAt, null, 'series alive');
      assertEq(after.first, 1, 'earlier occurrence stays');
      assertEq(after.current, 0, 'selected occurrence gone');
      assertEq(after.weekLater, 0, 'later occurrences gone');
      // undo
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      const undo = await page.evaluate(() => {
        const S = window.Store;
        const e = S.state.events.find((x) => x.rrule);
        const a = S.state.calendarAnchor;
        return { until: e.rrule.until, current: S.eventsOnDay(a).filter((x) => x.id === e.id).length };
      });
      console.log('R8 after undo:', undo);
      assertEq(undo.current, 1, 'undo restores future occurrences');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R9 rapid consecutive capture / quick add', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'action');
      await settle(page, 250);
      await page.click('[data-testid="action-capture"]');
      for (let i = 1; i <= 5; i++) {
        await page.keyboard.type('极速捕获' + i);
        await page.keyboard.press('Enter');
        await sleep(25);
      }
      await settle(page, 500);
      await shot(page, 'R9-01-rapid-captures');
      let st = await state(page);
      const caps = st.todos.filter((t) => /^极速捕获/.test(t.summary)).map((t) => t.summary);
      console.log('R9 captures:', caps);
      assertEq(caps.sort(), [1, 2, 3, 4, 5].map((i) => '极速捕获' + i).sort(), 'all five captures created once');
      await L.go(page, 'todos');
      await settle(page, 250);
      await page.click('[data-testid="todo-quick-add"]');
      for (let i = 1; i <= 5; i++) {
        await page.keyboard.type('极速添加' + i);
        await page.keyboard.press('Enter');
        await sleep(25);
      }
      await settle(page, 500);
      await shot(page, 'R9-02-rapid-quick-adds');
      st = await state(page);
      const quicks = st.todos.filter((t) => /^极速添加/.test(t.summary)).map((t) => t.summary);
      console.log('R9 quick adds:', quicks);
      assertEq(quicks.sort(), [1, 2, 3, 4, 5].map((i) => '极速添加' + i).sort(), 'all five quick-adds created once');
      // no duplicate rows in DOM
      const domCount = await L.count(page, '[data-testid="todo-tile"]');
      const expected = await page.evaluate(() => window.Store.liveTodos().filter((t) => !t.parentId).length);
      console.log('R9 dom tiles vs live todos:', domCount, expected);
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R10 navigate away mid-flow (browser back, Esc layers)', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 250);
      await page.fill('[data-testid="composer-title"]', '浏览器返回草稿');
      await page.goBack();
      await settle(page, 500);
      const afterBack = await page.evaluate(() => ({ url: location.href, ready: !!window.__READY__, composer: !!(document.querySelector('[data-testid="composer"]')), route: window.Store ? window.Store.state.route : null }));
      console.log('R10 after browser back:', afterBack);
      await shot(page, 'R10-01-browser-back');
      // No SPA history entries exist, so browser Back leaves the prototype entirely.
      // This is informational: README documents Esc as the back affordance.
      console.log('R10 informational: browser Back unloads the static prototype (no popstate handling)');
      await page.close();
    });

    await run('R11 phone paths (row menu, event detail, month drill)', async () => {
      const page = await newPage(browser, MOBILE);
      await L.go(page, 'todos');
      await settle(page, 300);
      // row more button
      const tile = page.locator('[data-testid="todo-tile"]', { hasText: '写 v0.29 发布说明' }).first();
      const more = tile.locator('button[aria-label="更多"]').first();
      console.log('R11 more buttons:', await page.locator('button[aria-label="更多"]').count());
      assert(await more.count() === 1, 'row more button present on phone');
      await more.click();
      await settle(page, 250);
      await shot(page, 'R11-01-phone-row-menu');
      const menuItems = await L.texts(page, '.menu button');
      console.log('R11 phone menu:', menuItems);
      assert(menuItems.some((x) => /编辑/.test(x)) && menuItems.some((x) => /安排时间/.test(x)) && menuItems.some((x) => /移到回收站/.test(x)), 'row menu has edit/schedule/delete');
      await page.keyboard.press('Escape');
      await settle(page, 200);
      // event detail on phone: edit and delete in header
      await L.go(page, 'calendar');
      await settle(page, 300);
      await page.evaluate(() => { window.Store.state.calendarView = 'day'; window.App.render(); });
      await settle(page, 350);
      const meal = page.locator('[data-testid="event-block"]', { hasText: '与设计师午餐' }).first();
      await meal.click();
      await settle(page, 350);
      await shot(page, 'R11-02-phone-event-detail');
      const headerBtns = await page.evaluate(() => Array.from(document.querySelectorAll('#view .detail-head button')).map((b) => b.getAttribute('aria-label')));
      console.log('R11 event detail header buttons:', headerBtns);
      assert(headerBtns.includes('编辑') && headerBtns.includes('移到回收站'), 'event edit/delete reachable');
      // month drill
      await L.go(page, 'calendar');
      await settle(page, 300);
      await page.click('[data-testid="cal-view-month"]');
      await settle(page, 300);
      await shot(page, 'R11-03-phone-month');
      const beforeView = await page.evaluate(() => window.Store.state.calendarView);
      await page.locator('.month-cell').nth(12).click();
      await settle(page, 350);
      const afterView = await page.evaluate(() => window.Store.state.calendarView);
      console.log('R11 month drill view:', beforeView, '->', afterView);
      assertEq(afterView, 'day', 'month cell drills into day on phone');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('R12 phone swipe delete with undo', async () => {
      const ctx = await browser.newContext({ viewport: MOBILE, hasTouch: true, isMobile: true });
      const page = await ctx.newPage();
      const errors = [];
      page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
      page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
      await page.goto('file:///Users/chang/Desktop/Code/dayspark-g0/docs/design/interaction-model/index.html');
      await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
      page.__errors = errors;
      await L.go(page, 'todos');
      await settle(page, 350);
      const tile = page.locator('[data-testid="todo-tile"]', { hasText: '买牛奶和咖啡豆' }).first();
      const bb = await tile.boundingBox();
      console.log('R12 tile box:', bb);
      const cdp = await page.context().newCDPSession(page);
      const cx = bb.x + bb.width / 2, cy = bb.y + bb.height / 2;
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: cx, y: cy, id: 1 }] });
      for (let i = 1; i <= 8; i++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: cx - i * 14, y: cy, id: 1 }] });
      }
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      await settle(page, 600);
      await shot(page, 'R12-01-after-swipe');
      const st = await state(page);
      const milk = st.todos.find((t) => t.summary === '买牛奶和咖啡豆');
      console.log('R12 after swipe deletedAt:', milk.deletedAt);
      assert(milk.deletedAt, 'swipe left deletes');
      assert(await L.exists(page, '.toast button.undo'), 'undo available');
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      const st2 = await state(page);
      assertEq(st2.todos.find((t) => t.summary === '买牛奶和咖啡豆').deletedAt, null, 'undo restores');
      assertEq(page.__errors, [], 'no console errors');
      await ctx.close();
    });
  } finally {
    await browser.close();
  }
  console.log('\n=== SUMMARY ===');
  results.forEach(([n, s, m]) => console.log(`${s} ${n}${m ? ': ' + m : ''}`));
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
