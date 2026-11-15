const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP } = L;

const results = [];
async function run(name, fn) {
  try { await fn(); results.push([name, 'PASS', '']); console.log('PASS', name); }
  catch (e) { results.push([name, 'FAIL', e.message]); console.log('FAIL', name + ':', e.message); }
}
async function openTomorrowDay(page) {
  await L.go(page, 'calendar');
  await page.click('[data-testid="cal-view-day"]');
  await settle(page, 250);
  await page.click('button[aria-label="下一段"]');
  await settle(page, 300);
}

async function main() {
  const browser = await launch();
  try {
    await run('B1 block-menu edit on a recurring occurrence must ask scope', async () => {
      const page = await newPage(browser, DESKTOP);
      await openTomorrowDay(page);
      const block = page.locator('[data-testid="event-block"]', { hasText: '周会' }).first();
      await block.click({ button: 'right' });
      await settle(page, 220);
      await L.clickText(page, '.menu button', '编辑');
      await settle(page, 350);
      const scope = await L.exists(page, '.sheet [data-testid="scope-this"]');
      console.log('B1 scope sheet shown after block-menu edit?', scope, 'composer?', await L.exists(page, '[data-testid="composer"]'));
      await shot(page, 'B1-01-block-menu-edit');
      assert(scope, 'editing a recurring occurrence must ask this/all (BEHAVIORS C4, COVERAGE 4.7)');
      await page.close();
    });

    await run('B2 ghost allocation when scheduling a completed occurrence', async () => {
      const page = await newPage(browser, DESKTOP);
      // complete today's reading occurrence
      await L.go(page, 'action');
      await settle(page, 400);
      await page.locator('[data-testid="action-instance"]', { hasText: '读 20 页' }).first().locator('[role="checkbox"]').click();
      await settle(page, 400);
      // edit reading from Todos All
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      await settle(page, 300);
      await page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).first().click({ button: 'right' });
      await settle(page, 250);
      await L.clickText(page, '.menu button', '编辑');
      await settle(page, 350);
      await page.click('[data-testid="composer-schedule"]');
      await settle(page, 300);
      const opts = await page.evaluate(() => {
        const sel = document.querySelector('[data-testid="schedule-occurrence"]');
        return sel ? Array.from(sel.options).map((o) => ({ v: o.value, t: o.textContent, sel: o.selected })) : [];
      });
      console.log('B2 occurrence options (first 3):', opts.slice(0, 3));
      const completed = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
        const today = new Date();
        return window.Store.occurrenceIdFor(t, today);
      });
      // choose the completed occurrence explicitly
      await page.selectOption('[data-testid="schedule-occurrence"]', completed).catch(() => {});
      await settle(page, 200);
      await page.click('[data-testid="schedule-apply"]');
      await settle(page, 250);
      await page.click('[data-testid="composer-save"]');
      await settle(page, 500);
      await shot(page, 'B2-01-after-save');
      const info = await page.evaluate((occId) => {
        const S = window.Store;
        const t = S.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
        const allocs = S.state.allocations.filter((a) => a.todoId === t.id && a.occurrenceId === occId);
        return {
          occId,
          allocs: allocs.map((a) => ({ state: a.state, live: S.isAllocationLive(a), start: a.startAt })),
          toast: document.querySelector('.toast') && document.querySelector('.toast').textContent,
          view: document.querySelector('#view').textContent.slice(0, 160),
        };
      }, completed);
      console.log('B2 result:', info);
      assert(!info.allocs.some((a) => a.state === 'active' && !a.live), 'must not write an active allocation that is invisible (ghost)');
      await page.close();
    });

    await run('B3 converting a scheduled to-do to recurring keeps schedule visible or explains', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await settle(page, 300);
      await page.locator('[data-testid="todo-tile"]', { hasText: '写 v0.29 发布说明' }).first().click({ button: 'right' });
      await settle(page, 250);
      await L.clickText(page, '.menu button', '编辑');
      await settle(page, 350);
      await page.click('[data-testid="composer-more"]');
      await settle(page, 200);
      await page.click('[data-testid="composer-repeat"]');
      await settle(page, 250);
      await L.clickText(page, '.sheet .slot-sheet-option', '每天');
      await settle(page, 250);
      await page.click('[data-testid="composer-save"]');
      await settle(page, 500);
      await shot(page, 'B3-01-after-convert');
      const info = await page.evaluate(() => {
        const S = window.Store;
        const t = S.state.todos.find((x) => x.summary === '写 v0.29 发布说明');
        const allocs = S.state.allocations.filter((a) => a.todoId === t.id);
        return { recurrence: !!t.recurrence, allocs: allocs.map((a) => ({ state: a.state, occ: a.occurrenceId, live: S.isAllocationLive(a) })), toast: document.querySelector('.toast') && document.querySelector('.toast').textContent };
      });
      console.log('B3 result:', info);
      assert(info.allocs.every((a) => a.live) || /选|choose|occurrence/i.test(info.toast || ''), 'existing schedule is not silently made invisible: ' + JSON.stringify(info));
      await page.close();
    });

    await run('B4 create from Action returns with a visible target', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'action');
      await settle(page, 300);
      await page.click('[data-testid="action-create"]');
      await settle(page, 250);
      await shot(page, 'B4-01-create-chooser');
      await page.click('[data-testid="create-todo"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '从今天页新建');
      await page.click('[data-testid="composer-save"]');
      await page.waitForTimeout(250);
      await shot(page, 'B4-02-after-create');
      const info = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '从今天页新建');
        return {
          id: t.id, route: window.Store.state.route,
          highlight: window.Store.state.highlight,
          hl: Array.from(document.querySelectorAll('.hl')).map((n) => n.dataset.testid + ':' + n.dataset.id),
          inboxEntry: (document.querySelector('[data-testid="inbox-entry"]') || {}).textContent,
        };
      });
      console.log('B4 result:', info);
      assert(info.hl.length > 0, 'some created-item target is visibly highlighted (BEHAVIORS A1)');
      await page.close();
    });
  } finally {
    await browser.close();
  }
  console.log('\n=== SUMMARY ===');
  results.forEach(([n, s, m]) => console.log(`${s} ${n}${m ? ': ' + m : ''}`));
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
