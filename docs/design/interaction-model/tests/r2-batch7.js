const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP } = L;

const results = [];
async function run(name, fn) {
  try { await fn(); results.push([name, 'PASS', '']); console.log('PASS', name); }
  catch (e) { results.push([name, 'FAIL', e.message]); console.log('FAIL', name + ':', e.message); }
}

async function main() {
  const browser = await launch();
  try {
    await run('A1 deleted todo detail must use the error card', async () => {
      const page = await newPage(browser, DESKTOP);
      const deleted = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.deletedAt);
        return { id: t.id, summary: t.summary };
      });
      await L.go(page, 'detail', { type: 'todo', id: deleted.id });
      await settle(page, 350);
      await shot(page, 'A1-deleted-todo-detail');
      const txt = await L.text(page, '#view');
      console.log('A1 deleted todo detail text:', txt.slice(0, 220));
      assert(/出错了/.test(txt) && /数据没有被改动/.test(txt), 'deleted todo opens the recoverable error card (BEHAVIORS H)');
      await page.close();
    });

    await run('A2 batch complete on a recurring to-do must not silently no-op', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await L.clickText(page, '.chip-btn', '全部');
      await settle(page, 300);
      // enter selection mode via chip
      await L.clickText(page, '.toolbar .chip-btn, .todo-toolbar .chip-btn', '选择');
      await settle(page, 300);
      const tile = page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).first();
      await tile.locator('.selbox, [role="checkbox"]').first().click();
      await settle(page, 250);
      await shot(page, 'A2-01-selection');
      const before = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
        return JSON.parse(JSON.stringify(t.occurrenceStates));
      });
      await L.clickText(page, '.selectbar button', '完成');
      await settle(page, 450);
      await shot(page, 'A2-02-after-batch-complete');
      const after = await page.evaluate(() => {
        const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
        return { states: JSON.parse(JSON.stringify(t.occurrenceStates)), status: t.status, toast: document.querySelector('.toast') && document.querySelector('.toast').textContent };
      });
      console.log('A2 before/after:', before, after);
      assert(Object.keys(after.states).length > 0 || after.status === 'COMPLETED', `batch complete wrote nothing yet reported success: ${JSON.stringify(after)}`);
      await page.close();
    });

    await run('A3 default tab setting takes effect on restart', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'settings');
      await settle(page, 300);
      await page.click('[data-testid="default-tab-todos"]');
      await settle(page, 300);
      const saved = await page.evaluate(() => window.Store.state.defaultTab);
      console.log('A3 defaultTab saved:', saved);
      await page.reload();
      await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
      await settle(page, 300);
      const opened = await page.evaluate(() => ({ route: window.Store.state.route.name, tab: window.Store.state.tab }));
      console.log('A3 after reload:', opened);
      await shot(page, 'A3-default-tab-after-reload');
      assertEq(opened.route, 'todos', 'default tab setting should open that page on next launch');
      await page.close();
    });

    await run('A4 all-day event creation renders', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'calendar');
      await page.click('[data-testid="calendar-create"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '全天演示');
      await page.click('[data-testid="composer-allday-on"]');
      await settle(page, 250);
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      await shot(page, 'A4-01-after-all-day-create');
      const chips = await L.texts(page, '.all-day-row .month-event');
      console.log('A4 all-day chips:', chips);
      assert(chips.some((x) => /全天演示/.test(x)), 'created all-day event renders in all-day row');
      await page.close();
    });

    await run('A5 documented six-things / week-start settings', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'settings');
      await settle(page, 350);
      const settingsText = await L.text(page, '#view');
      await L.go(page, 'todos');
      await settle(page, 300);
      const chips = await L.texts(page, '.todo-toolbar .chip-btn');
      console.log('A5 settings text:', settingsText.slice(0, 260));
      console.log('A5 todos chips:', chips);
      // BEHAVIORS F and COVERAGE 6.1 still list both settings; the current build removed them.
      assert(/六件事|Six things/i.test(settingsText) && /每周起始日|Week starts/i.test(settingsText), 'docs promise six-things and week-start settings that the build no longer exposes');
      await page.close();
    });

    await run('A6 search scope control', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'search');
      await settle(page, 300);
      await page.fill('#view input', '工作');
      await settle(page, 400);
      await shot(page, 'A6-01-search');
      const buttons = await L.texts(page, '#view .segmented button, #view .chip-btn');
      console.log('A6 search controls:', buttons);
      assert(buttons.some((x) => /全部|All/.test(x)) && buttons.some((x) => /待办|To-dos/.test(x)) && buttons.some((x) => /日程|Events/.test(x)), 'search exposes the all/todos/events scope switch promised by COVERAGE 6.1');
      await page.close();
    });

    await run('A7 English AI config custom provider label', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'settings');
      await settle(page, 300);
      await page.click('[data-testid="lang-en"]');
      await settle(page, 400);
      // open AI config if collapsed
      const opened = await page.evaluate(() => {
        const n = Array.from(document.querySelectorAll('button, .setting-row')).find((x) => /AI configuration|AI 配置/.test(x.textContent));
        if (n) { n.click(); return true; }
        return false;
      });
      await settle(page, 350);
      await shot(page, 'A7-01-english-ai-settings');
      const options = await L.texts(page, 'select option');
      console.log('A7 options:', options);
      const overlayTxt = await L.text(page, '#overlay');
      const txt = overlayTxt || await L.text(page, '#view');
      console.log('A7 has Chinese custom provider?', /自定义/.test(txt), 'has Custom?', /Custom/.test(txt), 'overlay:', overlayTxt && overlayTxt.slice(0, 160));
      assert(!/自定义/.test(txt) || /Custom/.test(txt), 'English mode must not show the untranslated provider 自定义');
      await page.close();
    });

    await run('A8 composer validation / type switch / edit lock', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 300);
      // empty title save disabled + error on attempt
      assert(await page.locator('[data-testid="composer-save"]').isDisabled(), 'save disabled for empty title');
      await page.click('[data-testid="composer-save"]').catch(() => {});
      await settle(page, 250);
      assert(/标题|title/i.test(await L.text(page, '.hint-box.error')), 'inline title error');
      // event validation
      await page.click('[data-testid="composer-type-event"]');
      await settle(page, 300);
      await page.fill('[data-testid="composer-title"]', '时间校验');
      const t1 = page.locator('[data-testid="composer-start-time"]');
      const t2 = page.locator('[data-testid="composer-end-time"]');
      await t1.fill('12:00');
      await t2.fill('11:00');
      await settle(page, 300);
      await shot(page, 'A8-01-time-invalid');
      assert(await page.locator('[data-testid="composer-save"]').isDisabled(), 'save disabled when end <= start');
      assert(/结束|end|时间/i.test(await L.text(page, '.hint-box.error')), 'time error shown');
      // valid then save
      await t2.fill('13:00');
      await settle(page, 250);
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      // edit the new event: type must be locked
      const ev = await page.evaluate(() => window.Store.state.events.find((e) => e.summary === '时间校验'));
      await L.go(page, 'detail', { type: 'event', id: ev.id });
      await settle(page, 300);
      await page.click('#view button[aria-label="编辑"]');
      await settle(page, 300);
      const beforeCount = await page.evaluate(() => window.Store.state.events.length);
      await page.click('[data-testid="composer-type-todo"]');
      await settle(page, 350);
      const typeLocked = await page.evaluate(() => !!document.querySelector('[data-testid="composer-start-date"]'));
      console.log('A8 edit type locked:', typeLocked);
      assert(typeLocked, 'editing an event cannot switch it to a to-do');
      await page.keyboard.press('Escape');
      await settle(page, 300);
      if (await L.exists(page, '.modal.confirm')) await L.clickText(page, '.modal button', '放弃');
      await settle(page, 300);
      await page.close();
    });

    await run('A9 keyboard shortcuts', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'action');
      await settle(page, 250);
      await page.keyboard.press('n');
      await settle(page, 300);
      assert(await L.exists(page, '[data-testid="composer"]'), 'N opens composer');
      await page.keyboard.press('Escape');
      await settle(page, 250);
      // empty composer is clean, so Esc leaves
      const modal = await L.exists(page, '.modal.confirm');
      if (modal) await L.clickText(page, '.modal button', '放弃');
      await settle(page, 250);
      await page.keyboard.press('/');
      await settle(page, 300);
      assertEq((await state(page)).route.name, 'search', '/ opens search');
      await L.go(page, 'action');
      await settle(page, 300);
      await page.keyboard.press('?');
      await settle(page, 300);
      // '?' is a shifted key, may need shift
      if (!(await L.exists(page, '.modal'))) {
        await page.keyboard.press('Shift+/');
        await settle(page, 300);
      }
      const txt = await L.text(page, '.modal');
      console.log('A9 shortcuts modal:', txt && txt.slice(0, 80));
      assert(/快捷键|shortcuts/i.test(txt || ''), '? opens shortcuts help');
      await page.close();
    });

    await run('A10 long titles do not break layout', async () => {
      const page = await newPage(browser, { width: 320, height: 800 });
      await L.go(page, 'todos');
      await settle(page, 300);
      await page.click('[data-testid="todo-quick-add"]');
      const long = '这是一条非常非常长的待办标题用来检查单行截断是否工作不会把布局撑破或者把别的元素挤出屏幕外'.repeat(2);
      await page.keyboard.type(long);
      await page.keyboard.press('Enter');
      await settle(page, 400);
      const ov = await page.evaluate(() => ({
        doc: document.documentElement.scrollWidth, win: innerWidth,
        titleOverflow: (() => { const t = document.querySelector('[data-testid="todo-tile"] .row-title'); return t ? { sw: t.scrollWidth, cw: t.clientWidth, h: t.clientHeight } : null; })(),
      }));
      console.log('A10 long title:', ov);
      await shot(page, 'A10-01-long-title-320');
      assert(ov.doc <= ov.win + 1, 'no horizontal overflow with long title');
      assert(ov.titleOverflow && ov.titleOverflow.h < 30, 'title stays single line');
      await page.close();
    });
  } finally {
    await browser.close();
  }
  console.log('\n=== SUMMARY ===');
  results.forEach(([n, s, m]) => console.log(`${s} ${n}${m ? ': ' + m : ''}`));
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
