const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP, MOBILE } = L;

async function todayKey(page, text) {
  return page.evaluate((summary) => {
    const S = window.Store;
    const t = S.state.todos.find((x) => x.summary === summary);
    return S.occurrenceIdFor(t, new Date());
  }, text);
}

async function main() {
  const browser = await launch();
  try {
    // ---------------- F3 ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      await settle(page, 250);
      await shot(page, 'F3-01-todos-all');
      const reading = page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).first();
      console.log('F3 recurring row count:', await page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).count());
      const occId = await todayKey(page, '读 20 页《设计中的设计》');
      console.log('F3 today occurrence id:', occId);
      const before = await page.evaluate((id) => {
        const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
        return { status: t.status, states: JSON.parse(JSON.stringify(t.occurrenceStates)) };
      }, occId);
      console.log('F3 before:', before);
      await reading.locator('.checkbox, [role="checkbox"]').first().click();
      await settle(page, 350);
      await shot(page, 'F3-02-after-complete-from-list');
      const after = await page.evaluate((id) => {
        const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
        return { status: t.status, states: JSON.parse(JSON.stringify(t.occurrenceStates)), toast: document.querySelector('.toast') ? document.querySelector('.toast').textContent : null };
      }, occId);
      console.log('F3 after list complete:', after);
      assert(after.states[occId] && after.states[occId].completedAt, 'today occurrence got completedAt');
      assertEq(after.status, 'NEEDS-ACTION', 'series stays NEEDS-ACTION');
      assert(after.toast && /已完成/.test(after.toast), 'success toast');
      // row feedback check
      const rowText = await reading.evaluate((n) => ({ cls: n.className, titleCls: n.querySelector('.row-title').className, aria: n.querySelector('[role="checkbox"]') && n.querySelector('[role="checkbox"]').getAttribute('aria-checked') }));
      console.log('F3 row visual after completing today:', rowText);

      // detail button path
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      await page.locator('[data-testid="todo-tile"]', { hasText: '每日站会记录' }).first().click();
      await settle(page, 300);
      await page.click('[data-testid="detail-complete"]');
      await settle(page, 300);
      await shot(page, 'F3-03-detail-complete-standup');
      const standup = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '每日站会记录');
        return { status: t.status, states: JSON.parse(JSON.stringify(t.occurrenceStates)), toast: document.querySelector('.toast') ? document.querySelector('.toast').textContent : null };
      });
      console.log('F3 standup after detail complete:', standup);
      assert(standup.states && Object.keys(standup.states).length === 1, 'standup today completed');
      assertEq(standup.status, 'NEEDS-ACTION', 'standup series stays open');

      // weekly review (Friday only) — today Monday, refusing path
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      const wrBefore = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '每周复盘');
        return JSON.parse(JSON.stringify(t.occurrenceStates));
      });
      await page.locator('[data-testid="todo-tile"]', { hasText: '每周复盘' }).first().click();
      await settle(page, 300);
      await page.click('[data-testid="detail-complete"]');
      await settle(page, 400);
      await shot(page, 'F3-04-nonmatching-occurrence-warning');
      const wr = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '每周复盘');
        return { states: JSON.parse(JSON.stringify(t.occurrenceStates)), toast: document.querySelector('.toast') ? document.querySelector('.toast').textContent : null };
      });
      console.log('F3 weekly review refusal:', wr);
      assertEq(wr.states, wrBefore, 'no write when no occurrence today');
      assert(wr.toast && /重复任务要选一次具体实例/.test(wr.toast), 'warning toast');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F3 PASS');
    }

    // ---------------- F4 ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      const tile = page.locator('[data-testid="todo-tile"]', { hasText: '每日站会记录' }).first();
      await tile.click({ button: 'right' });
      await settle(page, 200);
      await L.clickText(page, '.menu button', '编辑');
      await settle(page, 350);
      assert(await L.exists(page, '[data-testid="composer"]'), 'composer opened');
      await page.click('[data-testid="composer-schedule"]');
      await settle(page, 250);
      await shot(page, 'F4-01-schedule-picker-recurring');
      assert(await L.exists(page, '[data-testid="schedule-occurrence"]'), 'occurrence dropdown present for repeating todo');
      const options = await L.texts(page, '[data-testid="schedule-occurrence"] option');
      console.log('F4 occurrence options:', options.slice(0, 5), 'count', options.length);
      const selVal = await page.inputValue('[data-testid="schedule-occurrence"]');
      console.log('F4 default selected occurrence:', selVal);
      assert(selVal, 'an occurrence is required/selected');
      const preview = await L.text(page, '.sheet .preview');
      console.log('F4 preview:', preview);
      await page.click('[data-testid="schedule-apply"]');
      await settle(page, 250);
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      await shot(page, 'F4-02-after-save');
      const st = await state(page);
      const standup = st.todos.find((t) => t.summary === '每日站会记录');
      const alloc = st.allocations.filter((a) => a.todoId === standup.id);
      console.log('F4 allocations for standup:', alloc);
      assertEq(alloc.length, 1, 'allocation written');
      assert(alloc[0].occurrenceId, 'allocation carries occurrenceId');
      assertEq(alloc[0].state, 'active', 'allocation live/visible');
      // calendar shows it on the allocation day
      const allocDay = alloc[0].startAt.slice(0, 10);
      await page.evaluate((dayIso) => {
        const d = new Date(dayIso);
        window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        window.Store.state.calendarFocusDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        window.Store.state.calendarView = 'day';
        window.App.go('calendar');
      }, alloc[0].startAt);
      await settle(page, 350);
      await shot(page, 'F4-03-calendar-block');
      const blockLabels = await L.texts(page, '[data-testid="alloc-block"]');
      console.log('F4 calendar alloc blocks:', blockLabels);
      assert(blockLabels.some((x) => /每日站会记录/.test(x)), 'allocation visible on calendar');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F4 PASS');
    }

    // ---------------- F5 ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'action');
      await settle(page, 300);
      const actionText = await L.text(page, '#view');
      console.log('F5 action text has subtask?', /收集各组数据|写一页结论/.test(actionText));
      assert(!/收集各组数据|写一页结论/.test(actionText), 'Action has no subtasks');
      const inboxCountText = await L.text(page, '[data-testid="inbox-entry"]');
      console.log('F5 inbox entry:', inboxCountText);
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      await settle(page, 250);
      const allText = await L.text(page, '[data-testid="todo-list"]');
      console.log('F5 all list has subtask?', /收集各组数据|写一页结论/.test(allText));
      assert(!/收集各组数据|写一页结论/.test(allText), 'Todos all has no subtasks');
      await shot(page, 'F5-01-todos-all');
      await L.clickText(page, '.chip-btn', '收件箱');
      await settle(page, 250);
      const inboxText = await L.text(page, '[data-testid="todo-list"]');
      console.log('F5 inbox includes subtasks?', /收集各组数据|写一页结论/.test(inboxText));
      assert(!/收集各组数据|写一页结论/.test(inboxText), 'Inbox has no subtasks');
      // parent detail lists them
      await L.clickText(page, '.chip-btn', '全部');
      await page.locator('[data-testid="todo-tile"]', { hasText: '准备季度评审' }).first().click();
      await settle(page, 300);
      const parentText = await L.text(page, '#view');
      assert(/收集各组数据/.test(parentText) && /写一页结论/.test(parentText), 'parent detail lists subtasks');
      await shot(page, 'F5-02-parent-detail-subtasks');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F5 PASS');
    }

    // ---------------- F6 ----------------
    {
      const page = await newPage(browser, MOBILE);
      await L.go(page, 'todos');
      await settle(page, 350);
      await shot(page, 'F6-01-mobile-todos');
      // open 写 v0.29 发布说明 (has live allocation 09:30-10:30)
      await page.locator('[data-testid="todo-tile"]', { hasText: '写 v0.29 发布说明' }).first().click();
      await settle(page, 350);
      await shot(page, 'F6-02-mobile-detail');
      console.log('F6 detail has cancel control:', await L.exists(page, '[data-testid="cancel-allocation"]'));
      assert(await L.exists(page, '[data-testid="cancel-allocation"]'), 'cancel allocation reachable on phone detail');
      await page.click('[data-testid="cancel-allocation"]');
      await settle(page, 300);
      const layers = await page.evaluate(() => Array.from(document.querySelectorAll('#overlay .modal, #overlay .sheet')).map((n) => ({ cls: n.className, title: (n.querySelector('h2') || {}).textContent })));
      console.log('F6 overlay stack after tapping cancel:', layers);
      await shot(page, 'F6-03-cancel-confirm');
      // A real user sees the schedule sheet on top; Escape closes BOTH layers, so
      // the only way to reach the confirm is tapping the dimmed scrim.
      await page.mouse.click(10, 10);
      await settle(page, 300);
      await shot(page, 'F6-03b-after-scrim-tap');
      await L.clickText(page, '.modal button', '取消安排');
      await settle(page, 400);
      await shot(page, 'F6-04-after-cancel');
      const st = await state(page);
      const rel = st.todos.find((t) => t.summary === '写 v0.29 发布说明');
      const allocs = st.allocations.filter((a) => a.todoId === rel.id);
      console.log('F6 allocations after cancel:', allocs);
      assertEq(allocs[0].state, 'cancelledByUser', 'allocation cancelled');
      const detailText = await L.text(page, '#view');
      console.log('F6 history visible:', /历史安排|Past schedules/.test(detailText));
      assert(/历史安排|Past schedules/.test(detailText), 'past schedules section appears');
      assert(/已取消|Cancelled/.test(detailText), 'cancelled state shown');
      // calendar block gone
      await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '写 v0.29 发布说明');
        window.Store.state.calendarAnchor = new Date();
        window.Store.state.calendarView = 'day';
        window.App.go('calendar');
      });
      await settle(page, 400);
      const blocks = await L.texts(page, '[data-testid="alloc-block"]');
      console.log('F6 alloc blocks after cancel:', blocks);
      assert(!blocks.some((x) => /v0\.29/.test(x)), 'cancelled block gone from calendar');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F6 PASS');
    }
  } finally {
    await browser.close();
  }
}
main().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
