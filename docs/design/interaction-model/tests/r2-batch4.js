const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP } = L;

const results = [];
async function run(name, fn) {
  try { await fn(); results.push([name, 'PASS', '']); console.log(name, 'PASS'); }
  catch (e) { results.push([name, 'FAIL', e.message]); console.log(name, 'FAIL:', e.message); }
}

async function openTodayDay(page) {
  await L.go(page, 'calendar');
  await page.click('[data-testid="cal-view-day"]');
  await settle(page, 300);
}

async function main() {
  const browser = await launch();
  try {
    // F13 value click-to-edit
    await run('F13 value click-to-edit', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await page.locator('[data-testid="todo-tile"]', { hasText: '写 v0.29 发布说明' }).first().click();
      await settle(page, 300);
      // deadline value click
      await page.locator('.fact.amber .v').click();
      await settle(page, 250);
      assert(await L.exists(page, '[data-testid="edit-deadline-date"]'), 'deadline value opens editor');
      await page.keyboard.press('Escape');
      await settle(page, 200);
      // priority value click
      await page.locator('.fact', { hasText: '优先级' }).locator('.v').click();
      await settle(page, 250);
      assert(/优先级|Priority/.test(await L.text(page, '.sheet h2')), 'priority value opens priority sheet');
      await page.keyboard.press('Escape');
      await settle(page, 200);
      // tags value click
      await page.locator('.fact', { hasText: '标签' }).locator('.v').click();
      await settle(page, 250);
      assert(/标签|Tags/.test(await L.text(page, '.sheet h2')), 'tags value opens tag sheet');
      await page.keyboard.press('Escape');
      await settle(page, 200);
      // schedule value click
      await page.locator('.fact.violet .v').click();
      await settle(page, 250);
      assert(await L.exists(page, '[data-testid="allocate-apply"]'), 'schedule value opens schedule sheet');
      await page.keyboard.press('Escape');
      await settle(page, 200);
      // keyboard: focus priority value and Enter
      await page.evaluate(() => {
        const fact = Array.from(document.querySelectorAll('.fact')).find((f) => /优先级/.test(f.textContent));
        fact.querySelector('.v').focus();
      });
      await page.keyboard.press('Enter');
      await settle(page, 250);
      assert(/优先级/.test(await L.text(page, '.sheet h2')), 'Enter on value opens editor');
      await shot(page, 'F13-01-keyboard-value-editor');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    // F14 overlapping allocation warns
    await run('F14 overlap warning', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await page.locator('[data-testid="todo-tile"]', { hasText: '整理评审纪要' }).first().click();
      await settle(page, 300);
      await page.click('[data-testid="detail-schedule"]');
      await settle(page, 250);
      const start = await page.evaluate(() => {
        const d = new Date();
        return window.U.toInputDateTime(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 15, 30));
      });
      await page.fill('.sheet input[type="datetime-local"]', start);
      await page.click('[data-testid="allocate-apply"]');
      await settle(page, 400);
      await shot(page, 'F14-01-overlap-toast');
      const toast = await L.text(page, '.toast');
      console.log('F14 toast:', toast);
      assert(toast && /重叠/.test(toast), 'toast warns about overlap');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    // F15 resize event: end moves, start fixed, toast + undo
    await run('F15 resize block undo', async () => {
      const page = await newPage(browser, DESKTOP);
      await openTodayDay(page);
      const before = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime() };
      });
      const block = page.locator('[data-testid="event-block"]', { hasText: '与设计师午餐' }).first();
      const bb = await block.boundingBox();
      const handle = block.locator('.resize');
      const hb = await handle.boundingBox();
      console.log('F15 block:', bb, 'handle:', hb);
      await page.mouse.move(hb.x + hb.width / 2, hb.y + hb.height / 2);
      await page.mouse.down();
      await page.mouse.move(hb.x + hb.width / 2, hb.y + hb.height / 2 + 24, { steps: 8 });
      await page.mouse.up();
      await settle(page, 450);
      await shot(page, 'F15-01-after-resize');
      const mid = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime(), toast: document.querySelector('.toast') ? document.querySelector('.toast').textContent : null };
      });
      console.log('F15 after resize:', mid, 'before:', before);
      assertEq(mid.s, before.s, 'resize keeps start');
      assert(mid.e !== before.e, 'resize changes end');
      assert(mid.toast && /已移动到/.test(mid.toast), 'resize shows toast');
      await L.clickText(page, '.toast button', '撤销');
      await settle(page, 400);
      const after = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '与设计师午餐');
        return { s: e.startDt.getTime(), e: e.endDt.getTime() };
      });
      console.log('F15 after undo:', after);
      assertEq(after, before, 'undo restores exact times');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    // F16 quick chip preview matches saved time and is in the future
    await run('F16 schedule quick chip (normal hour)', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '快捷时段检查');
      await page.click('[data-testid="composer-schedule"]');
      await settle(page, 250);
      await L.clickText(page, '.sheet .quick .chip-btn', '今天');
      await settle(page, 250);
      const info = await page.evaluate(() => {
        const input = document.querySelector('[data-testid="schedule-start"]');
        const preview = document.querySelector('.sheet .preview').textContent.replace(/\s+/g, ' ').trim();
        return { input: input.value, preview, now: window.U.now().toISOString() };
      });
      console.log('F16 quick today:', info);
      const s = new Date(info.input).getTime();
      assert(s > new Date(info.now).getTime(), 'quick chip offers a future time');
      await shot(page, 'F16-01-quick-preview');
      await page.click('[data-testid="schedule-apply"]');
      await settle(page, 250);
      const pill = await L.text(page, '[data-testid="composer-schedule"]');
      console.log('F16 pill:', pill, 'preview:', info.preview);
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      const st = await state(page);
      const todo = st.todos.find((t) => t.summary === '快捷时段检查');
      const alloc = st.allocations.find((a) => a.todoId === todo.id);
      console.log('F16 saved allocation:', alloc);
      const savedStart = new Date(alloc.startAt);
      const hhmm = String(savedStart.getHours()).padStart(2, '0') + ':' + String(savedStart.getMinutes()).padStart(2, '0');
      assert(info.preview.includes(hhmm), `preview ${info.preview} matches saved ${hhmm}`);
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('F16b schedule quick chip at 23:40 (future guarantee)', async () => {
      const page = await newPage(browser, DESKTOP);
      await page.evaluate(() => {
        const now = window.U.now();
        const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 40);
        window.U.setClockOffset(target.getTime() - Date.now());
        window.App.render();
      });
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '深夜快捷时段');
      await page.click('[data-testid="composer-schedule"]');
      await settle(page, 250);
      await L.clickText(page, '.sheet .quick .chip-btn', '今天');
      await settle(page, 250);
      const info = await page.evaluate(() => {
        const input = document.querySelector('[data-testid="schedule-start"]');
        const preview = document.querySelector('.sheet .preview').textContent.replace(/\s+/g, ' ').trim();
        return { input: input.value, preview, now: window.U.now().toISOString() };
      });
      console.log('F16b quick today at 23:40:', info);
      await shot(page, 'F16b-01-quick-at-2340');
      const s = new Date(info.input).getTime();
      assert(s > new Date(info.now).getTime(), `quick chip offered ${info.input} which is not after now ${info.now}`);
      await page.close();
    });

    // F17 missing event record
    await run('F17 missing event error card', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'detail', { type: 'event', id: 9999 });
      await settle(page, 350);
      await shot(page, 'F17-01-missing-event');
      const txt = await L.text(page, '#view');
      console.log('F17 text:', txt);
      assert(/出错了/.test(txt) && /数据没有被改动/.test(txt), 'recoverable error card shown');
      assert(txt.length > 0, 'not a blank page');
      await L.go(page, 'detail', { type: 'todo', id: 9999 });
      await settle(page, 300);
      assert(/出错了/.test(await L.text(page, '#view')), 'missing todo gets same card');
      // deleted record too
      const deletedId = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.deletedAt);
        return e ? e.id : null;
      });
      await L.go(page, 'detail', { type: 'event', id: deletedId });
      await settle(page, 300);
      await shot(page, 'F17-02-deleted-event');
      assert(/出错了/.test(await L.text(page, '#view')), 'deleted event gets error card');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    // F18 shortcuts inert behind overlay
    await run('F18 T inert with overlay', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'calendar');
      await settle(page, 300);
      // move to next week so T would visibly change the anchor
      await page.click('button[aria-label="下一段"]');
      await settle(page, 300);
      const anchorBefore = await page.evaluate(() => window.Store.state.calendarAnchor.getTime());
      const titleBefore = await L.text(page, '.page-title');
      // open a slot sheet
      await page.evaluate(() => {
        const day = window.Store.state.calendarAnchor;
        window.__calendarHelpers.openSlotSheet(day, 10, 11);
      });
      await settle(page, 250);
      assert(await L.exists(page, '.sheet'), 'sheet open');
      await page.keyboard.press('t');
      await settle(page, 350);
      const anchorAfter = await page.evaluate(() => window.Store.state.calendarAnchor.getTime());
      const titleAfter = await L.text(page, '.page-title');
      console.log('F18 anchor/title before/after:', anchorBefore, anchorAfter, titleBefore, titleAfter);
      assert(await L.exists(page, '.sheet'), 'sheet stays open');
      assertEq(anchorAfter, anchorBefore, 'T did not change the viewed day');
      assertEq(titleAfter, titleBefore, 'title unchanged');
      await shot(page, 'F18-01-T-with-sheet');
      // N and / also inert
      await page.keyboard.press('n');
      await settle(page, 250);
      assert(!(await L.exists(page, '[data-testid="composer"]')), 'N inert behind sheet');
      await page.keyboard.press('/');
      await settle(page, 250);
      assertEq((await state(page)).route.name, 'calendar', '/ inert behind sheet');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    // F19 new-row highlight (todo, then event)
    await run('F19 new row highlight (todo)', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '高亮检查任务');
      await page.click('[data-testid="composer-save"]');
      await page.waitForTimeout(120);
      await shot(page, 'F19-01-highlight-120ms');
      const info = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '高亮检查任务');
        const hl = document.querySelectorAll('.hl');
        const target = document.querySelector(`[data-testid="todo-tile"][data-id="${t.id}"]`);
        return {
          id: t.id,
          hlCount: hl.length,
          hlIds: Array.from(hl).map((n) => n.dataset.id),
          targetHasHl: target ? target.classList.contains('hl') : false,
          bg: target ? getComputedStyle(target).backgroundColor : null,
          rect: target ? target.getBoundingClientRect().height : null,
        };
      });
      console.log('F19 todo highlight:', info);
      assertEq(info.hlIds, [String(info.id)], 'highlight targets exactly the new row');
      assert(info.targetHasHl, 'new row carries .hl');
      assert(info.rect > 0, 'new row visible');
      await page.waitForTimeout(500);
      await shot(page, 'F19-02-highlight-600ms');
      await page.close();
    });

    await run('F19b new event highlight', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'calendar');
      await page.click('[data-testid="calendar-create"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '高亮检查日程');
      await page.click('[data-testid="composer-save"]');
      await page.waitForTimeout(150);
      await shot(page, 'F19b-01-event-highlight');
      const info = await page.evaluate(() => {
        const e = window.Store.state.events.find((x) => x.summary === '高亮检查日程');
        return {
          id: e.id,
          hlCount: document.querySelectorAll('.hl').length,
          hlIds: Array.from(document.querySelectorAll('.hl')).map((n) => n.dataset.id || n.className),
          highlightState: window.Store.state.highlight,
          route: window.Store.state.route,
        };
      });
      console.log('F19b event highlight:', info);
      assert(info.hlCount > 0, 'new event row/block highlighted after save');
      await page.close();
    });
  } finally {
    await browser.close();
  }
  console.log('\n=== SUMMARY ===');
  results.forEach(([n, s, m]) => console.log(`${s} ${n}${m ? ': ' + m : ''}`));
  if (results.some(([, s]) => s === 'FAIL')) process.exit(1);
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
