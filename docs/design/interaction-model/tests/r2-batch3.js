const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP, MOBILE } = L;

async function openTodayDay(page) {
  await L.go(page, 'calendar');
  await page.click('[data-testid="cal-view-day"]');
  await settle(page, 300);
}

async function main() {
  const browser = await launch();
  try {
    // ---------------- F7 drag undo ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await openTodayDay(page);
      const before = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime() };
      });
      const block = page.locator('[data-testid="event-block"]', { hasText: '与设计师午餐' }).first();
      const bb = await block.boundingBox();
      console.log('F7 block box:', bb, 'before:', before);
      await page.mouse.move(bb.x + bb.width / 2, bb.y + 12);
      await page.mouse.down();
      await page.mouse.move(bb.x + bb.width / 2, bb.y + 12 + 48, { steps: 8 });
      await page.mouse.up();
      await settle(page, 500);
      await shot(page, 'F7-01-after-drag');
      const mid = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime(), toast: document.querySelector('.toast') ? document.querySelector('.toast').textContent : null };
      });
      console.log('F7 after drag:', mid);
      assert(mid.s !== before.s, 'drag changed the event start');
      assert(mid.toast && /已移动到/.test(mid.toast), 'drag shows toast');
      // click undo
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      await shot(page, 'F7-02-after-undo');
      const after = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime() };
      });
      console.log('F7 after undo:', after);
      assertEq(after, before, 'undo restores exact original times');

      // reschedule via context menu -> undo
      await block.click({ button: 'right' });
      await settle(page, 200);
      await L.clickText(page, '.menu button', '改期');
      await settle(page, 250);
      const inputs = page.locator('.modal input[type="datetime-local"]');
      console.log('F7 reschedule inputs:', await inputs.count());
      const oldVals = [await inputs.nth(0).inputValue(), await inputs.nth(1).inputValue()];
      const newStart = await page.evaluate((v) => {
        const d = window.U.fromInputDateTime(v);
        d.setMinutes(d.getMinutes() + 30);
        return window.U.toInputDateTime(d);
      }, oldVals[0]);
      const newEnd = await page.evaluate((v) => {
        const d = window.U.fromInputDateTime(v);
        d.setMinutes(d.getMinutes() + 30);
        return window.U.toInputDateTime(d);
      }, oldVals[1]);
      await inputs.nth(0).fill(newStart);
      await inputs.nth(1).fill(newEnd);
      await L.clickText(page, '.modal button', '保存');
      await settle(page, 400);
      await shot(page, 'F7-03-after-reschedule');
      const moved = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime(), toast: document.querySelector('.toast') ? document.querySelector('.toast').textContent : null };
      });
      console.log('F7 after reschedule:', moved);
      assert(moved.s !== before.s, 'reschedule changed event');
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      const restored = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime() };
      });
      console.log('F7 after reschedule undo:', restored);
      assertEq(restored, before, 'reschedule undo restores exact original times');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F7 PASS');
    }

    // ---------------- F8 dirty composer navigation ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '未保存的草稿');
      await page.click('[data-testid="nav-todos"]');
      await settle(page, 300);
      await shot(page, 'F8-01-rail-discard-prompt');
      assert(await L.exists(page, '.modal.confirm'), 'rail navigation asks about dirty draft');
      const prompt = await L.text(page, '.modal');
      console.log('F8 prompt:', prompt);
      assert(/放弃这些修改/.test(prompt), 'discard prompt shown');
      await L.clickText(page, '.modal button', '继续编辑');
      await settle(page, 300);
      await shot(page, 'F8-02-kept-editing');
      assert(await L.exists(page, '[data-testid="composer"]'), 'still in composer after keep editing');
      assertEq(await page.inputValue('[data-testid="composer-title"]'), '未保存的草稿', 'draft text preserved');
      // now discard
      await page.click('[data-testid="nav-todos"]');
      await settle(page, 250);
      await L.clickText(page, '.modal button', '放弃');
      await settle(page, 350);
      assert(!(await L.exists(page, '[data-testid="composer"]')), 'left composer after discard');
      assertEq(await L.text(page, '.page-title'), '待办', 'landed on todos');
      // Esc path
      await page.click('[data-testid="todos-create"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', 'Esc 草稿');
      await page.keyboard.press('Escape');
      await settle(page, 300);
      assert(await L.exists(page, '.modal.confirm'), 'Esc asks about dirty draft');
      await L.clickText(page, '.modal button', '继续编辑');
      await settle(page, 250);
      assertEq(await page.inputValue('[data-testid="composer-title"]'), 'Esc 草稿', 'Esc keep-editing preserves text');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();

      // mobile bottom nav
      const m = await newPage(browser, MOBILE);
      await L.go(m, 'todos');
      await settle(m, 300);
      await m.click('[data-testid="todos-create"]');
      await settle(m, 300);
      await m.fill('[data-testid="composer-title"]', '手机草稿');
      await m.click('[data-testid="tab-calendar"]');
      await settle(m, 300);
      await shot(m, 'F8-03-mobile-discard-prompt');
      assert(await L.exists(m, '.modal.confirm'), 'bottom nav asks about dirty draft');
      await L.clickText(m, '.modal button', '继续编辑');
      await settle(m, 250);
      assertEq(await m.inputValue('[data-testid="composer-title"]'), '手机草稿', 'mobile draft preserved');
      assertEq(m.__errors, [], 'no console errors');
      await m.close();
      console.log('F8 PASS');
    }

    // ---------------- F9 focus / continuous entry ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'action');
      await settle(page, 250);
      await page.click('[data-testid="action-capture"]');
      await page.keyboard.type('连续捕获甲');
      await page.keyboard.press('Enter');
      await settle(page, 250);
      await page.keyboard.type('连续捕获乙');
      await page.keyboard.press('Enter');
      await settle(page, 300);
      await shot(page, 'F9-01-two-captures');
      const cap = await page.evaluate(() => ({
        active: document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.testid : null,
        value: document.querySelector('[data-testid="action-capture"]') ? document.querySelector('[data-testid="action-capture"]').value : null,
        found: window.Store.state.todos.filter((t) => t.summary === '连续捕获甲' || t.summary === '连续捕获乙').map((t) => t.summary),
      }));
      console.log('F9 capture:', cap);
      assertEq(cap.found.sort(), ['连续捕获甲', '连续捕获乙'].sort(), 'two separate captures created');
      assertEq(cap.active, 'action-capture', 'focus stays in capture');
      assertEq(cap.value, '', 'capture input cleared');

      // quick add
      await L.go(page, 'todos');
      await settle(page, 250);
      await page.click('[data-testid="todo-quick-add"]');
      await page.keyboard.type('快速甲');
      await page.keyboard.press('Enter');
      await settle(page, 250);
      await page.keyboard.type('快速乙');
      await page.keyboard.press('Enter');
      await settle(page, 300);
      await shot(page, 'F9-02-two-quick-adds');
      const quick = await page.evaluate(() => ({
        active: document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.testid : null,
        value: document.querySelector('[data-testid="todo-quick-add"]') ? document.querySelector('[data-testid="todo-quick-add"]').value : null,
        found: window.Store.state.todos.filter((t) => t.summary === '快速甲' || t.summary === '快速乙').map((t) => t.summary),
      }));
      console.log('F9 quick add:', quick);
      assertEq(quick.found.sort(), ['快速甲', '快速乙'].sort(), 'two quick-add items created');
      assertEq(quick.active, 'todo-quick-add', 'focus stays in quick add');
      assertEq(quick.value, '', 'quick add cleared');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F9 PASS');
    }

    // ---------------- F10 delete event from detail ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await openTodayDay(page);
      await page.locator('[data-testid="event-block"]', { hasText: '与设计师午餐' }).first().click();
      await settle(page, 350);
      assert(await L.exists(page, '[data-testid="event-detail"]'), 'on event detail');
      await shot(page, 'F10-01-event-detail');
      await page.click('#view button[aria-label="移到回收站"]');
      await settle(page, 250);
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 450);
      await shot(page, 'F10-02-after-delete');
      const st = await state(page);
      console.log('F10 route after delete:', st.route, 'deleted event:', st.events.find((e) => e.summary === '与设计师午餐').deletedAt);
      assert(st.route.name !== 'detail', 'left the deleted event detail');
      assert(!(await L.exists(page, '#view [data-testid="event-detail"]')), 'no deleted event detail on screen');
      const viewText = await L.text(page, '#view');
      assert(!/与设计师午餐/.test(viewText), 'deleted event no longer displayed');
      // undo restores
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      const restored = await state(page);
      assertEq(restored.events.find((e) => e.summary === '与设计师午餐').deletedAt || null, null, 'undo restores event');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F10 PASS');
    }

    // ---------------- F11 completed leaves Now ----------------
    {
      const page = await newPage(browser, DESKTOP);
      // move the clock into the release-notes allocation (09:30-10:30)
      await page.evaluate(() => {
        const now = window.U.now();
        const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 9, 45);
        window.U.setClockOffset(target.getTime() - Date.now());
      });
      await L.go(page, 'action');
      await settle(page, 300);
      await shot(page, 'F11-01-now-lane');
      const nowSection = await L.text(page, '#view');
      console.log('F11 action now has allocation?', /此刻/.test(nowSection), /写 v0\.29/.test(nowSection));
      const nowRows = await L.texts(page, '[data-testid="action-allocation"]');
      console.log('F11 allocation rows:', nowRows);
      assert(nowRows.some((x) => /写 v0\.29/.test(x)), 'allocation is in Now');
      // complete it from the Now row checkbox
      const row = page.locator('[data-testid="action-allocation"]', { hasText: '写 v0.29 发布说明' }).first();
      await row.locator('[role="checkbox"]').click();
      await settle(page, 450);
      await shot(page, 'F11-02-after-complete');
      const after = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '写 v0.29 发布说明');
        const proj = window.Store.actionProjection();
        return {
          done: t.status === 'COMPLETED',
          now: proj.allocations.filter((x) => x.todo.id === t.id).length,
          completedToday: proj.completedTodayTodos.some((x) => x.id === t.id),
          view: document.querySelector('#view').textContent,
        };
      });
      console.log('F11 after complete:', { done: after.done, nowAllocCount: after.now, completedToday: after.completedToday });
      assert(after.done, 'todo completed');
      assertEq(after.now, 1, 'allocation record remains live for history');
      assert(after.completedToday, 'completed todo counted in earlier today');
      const viewAfter = after.view;
      const nowBlock = viewAfter.split('今天早些时候')[0];
      assert(!/写 v0\.29/.test(nowBlock), 'completed todo left Now/Later');
      assert(/今天早些时候[\s\S]*写 v0\.29/.test(viewAfter), 'completed todo under earlier today');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F11 PASS');
    }

    // ---------------- F12 missed instances expansion ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'action');
      await settle(page, 300);
      await shot(page, 'F12-01-overdue-collapsed');
      const data = await page.evaluate(() => {
        const proj = window.Store.actionProjection();
        const heads = Array.from(document.querySelectorAll('.section-head')).map((n) => n.textContent.replace(/\s+/g, ' ').trim());
        return { missed: proj.missedTaskInstances.length, overdue: proj.overdueTodos.length, heads };
      });
      console.log('F12 projection:', data);
      const total = data.missed + data.overdue;
      const head = data.heads.find((h) => /逾期/.test(h));
      console.log('F12 overdue header:', head, 'expected total:', total);
      assert(head && head.includes('逾期') && head.includes(String(total)), 'header shows true total');
      const collapsedRows = await L.count(page, '[data-testid="action-instance"]');
      const moreLabel = await L.text(page, '[data-testid="overdue-more"]');
      console.log('F12 collapsed rows:', collapsedRows, 'more:', moreLabel);
      assertEq(collapsedRows, 5, 'only 5 missed instances shown initially');
      assert(moreLabel && /展开其余/.test(moreLabel), 'expand control present');
      await page.click('[data-testid="overdue-more"]');
      await settle(page, 350);
      await shot(page, 'F12-02-overdue-expanded');
      const expandedRows = await L.count(page, '[data-testid="action-instance"]');
      const lessLabel = await L.text(page, '[data-testid="overdue-less"]');
      console.log('F12 expanded rows:', expandedRows, 'less:', lessLabel);
      assertEq(expandedRows, data.missed, 'all missed instances shown after expand');
      assert(lessLabel && /收起/.test(lessLabel), 'collapse control present');
      await page.click('[data-testid="overdue-less"]');
      await settle(page, 300);
      assertEq(await L.count(page, '[data-testid="action-instance"]'), 5, 'collapse returns to 5');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F12 PASS');
    }
  } finally {
    await browser.close();
  }
}
main().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
