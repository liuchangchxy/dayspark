const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP } = L;

const results = [];
async function run(name, fn) {
  try { await fn(); results.push([name, 'PASS', '']); console.log('PASS', name); }
  catch (e) { results.push([name, 'FAIL', e.message]); console.log('FAIL', name + ':', e.message); }
}

async function setEnglish(page) {
  await L.go(page, 'settings');
  await settle(page, 300);
  await page.click('[data-testid="lang-en"]');
  await settle(page, 350);
}

async function main() {
  const browser = await launch();
  try {
    await run('E1 English chrome sweep', async () => {
      const page = await newPage(browser, DESKTOP);
      await setEnglish(page);
      const routes = [
        ['action', null], ['calendar', null], ['todos', null], ['search', null],
        ['tags', null], ['calendars', null], ['trash', null], ['settings', null],
        ['about', null], ['feedback', null], ['states', null], ['chat', null],
      ];
      const offenders = [];
      for (const [route] of routes) {
        await L.go(page, route);
        await settle(page, 350);
        const found = await page.evaluate(() => {
          const seedSel = ['.row-title', '.detail-title', '.detail-note', '.month-event', '.block', '.bt', '.deadline-chip', '.occ-row', '.chat-bubble', '.bubble', '.chip', '.v', '.summary', '[data-testid="todo-tile"] .main', '[data-testid="event-block"]', '.month-cell', '.lunar'];
          const nodes = [];
          const walker = document.createTreeWalker(document.querySelector('#view'), NodeFilter.SHOW_TEXT);
          let n;
          while ((n = walker.nextNode())) {
            const txt = n.textContent.trim();
            if (!txt || !/[一-鿿]/.test(txt)) continue;
            const p = n.parentElement;
            if (!p) continue;
            if (seedSel.some((s) => p.closest(s))) continue;
            if (p.closest('.brand')) continue;
            nodes.push({ tag: p.tagName, cls: p.className, text: txt.slice(0, 80) });
          }
          return nodes;
        });
        found.forEach((f) => offenders.push({ route, ...f }));
        await shot(page, 'E1-' + route);
      }
      // calendar month + composer + detail pages too
      await L.go(page, 'calendar');
      await settle(page, 300);
      await page.click('[data-testid="cal-view-month"]');
      await settle(page, 350);
      const monthFound = await page.evaluate(() => {
        const out = [];
        const walker = document.createTreeWalker(document.querySelector('#view'), NodeFilter.SHOW_TEXT);
        let n;
        while ((n = walker.nextNode())) {
          const txt = n.textContent.trim();
          if (!txt || !/[一-鿿]/.test(txt)) continue;
          const p = n.parentElement;
          if (!p) continue;
          if (p.closest('.month-cell') || p.closest('.deadline-chip')) continue;
          out.push({ tag: p.tagName, cls: p.className, text: txt.slice(0, 80) });
        }
        return out;
      });
      monthFound.forEach((f) => offenders.push({ route: 'calendar-month', ...f }));
      await shot(page, 'E1-calendar-month');
      await L.go(page, 'settings', { section: 'account' });
      await settle(page, 300);
      await page.evaluate(() => {
        const btn = Array.from(document.querySelectorAll('button')).find((b) => /Account|账户/.test(b.textContent));
        if (btn) btn.click();
      });
      await settle(page, 300);
      await shot(page, 'E1-settings-account');
      console.log('E1 CJK offenders on chrome:');
      const uniq = {};
      offenders.forEach((o) => { const k = o.route + '|' + o.tag + '.' + o.cls + '|' + o.text; uniq[k] = o; });
      Object.values(uniq).forEach((o) => console.log('  ', o.route, o.tag + '.' + o.cls, '=>', o.text));
      // Custom provider option is hardcoded Chinese
      await L.go(page, 'settings', { section: 'ai' });
      await settle(page, 350);
      const provs = await L.texts(page, 'select option');
      console.log('E1 AI provider options:', provs);
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('E2 320px and 1920px widths', async () => {
      const small = await newPage(browser, { width: 320, height: 800 });
      const routes = ['action', 'todos', 'calendar', 'settings', 'tags', 'trash'];
      for (const r of routes) {
        await L.go(small, r);
        await settle(small, 350);
        const ov = await small.evaluate(() => ({
          doc: document.documentElement.scrollWidth, win: window.innerWidth,
          body: document.body.scrollWidth,
          view: document.querySelector('#view').scrollWidth,
        }));
        console.log('E2 320', r, ov);
        assert(ov.doc <= ov.win + 1, `${r} overflows at 320: ${JSON.stringify(ov)}`);
        await shot(small, 'E2-320-' + r);
      }
      // calendar month at 320
      await L.go(small, 'calendar');
      await small.click('[data-testid="cal-view-month"]');
      await settle(small, 350);
      const ovm = await small.evaluate(() => ({ doc: document.documentElement.scrollWidth, win: innerWidth }));
      console.log('E2 320 calendar-month', ovm);
      assert(ovm.doc <= ovm.win + 1, 'month overflows at 320');
      await shot(small, 'E2-320-calendar-month');
      // detail + composer at 320
      await L.go(small, 'todos');
      await small.locator('[data-testid="todo-tile"]').first().click();
      await settle(small, 350);
      const ovd = await small.evaluate(() => ({ doc: document.documentElement.scrollWidth, win: innerWidth }));
      console.log('E2 320 detail', ovd);
      assert(ovd.doc <= ovd.win + 1, 'detail overflows at 320');
      await shot(small, 'E2-320-detail');
      await small.close();

      const big = await newPage(browser, { width: 1920, height: 1080 });
      for (const r of ['action', 'todos', 'calendar']) {
        await L.go(big, r);
        await settle(big, 350);
        const ov = await big.evaluate(() => ({ doc: document.documentElement.scrollWidth, win: innerWidth }));
        console.log('E2 1920', r, ov);
        assert(ov.doc <= ov.win + 1, `${r} overflows at 1920`);
        await shot(big, 'E2-1920-' + r);
      }
      assertEq(big.__errors, [], 'no console errors');
      await big.close();
    });

    await run('E3 console errors on every route', async () => {
      const page = await newPage(browser, DESKTOP);
      const routes = [
        ['action'], ['calendar'], ['todos'], ['search'], ['chat'], ['tags'],
        ['calendars'], ['trash'], ['settings'], ['about'], ['feedback'], ['states'],
        ['composer'], ['detail', { type: 'todo', id: 1 }], ['detail', { type: 'event', id: 1 }],
        ['detail', { type: 'event', id: 9999 }], ['detail', { type: 'todo', id: 9999 }],
      ];
      for (const [r, p] of routes) {
        await L.go(page, r, p);
        await settle(page, 250);
      }
      // calendar views
      await L.go(page, 'calendar');
      for (const v of ['month', 'week', 'day']) {
        await page.click('[data-testid="cal-view-' + v + '"]');
        await settle(page, 250);
      }
      console.log('E3 errors:', page.__errors);
      assertEq(page.__errors, [], 'no console errors across routes');
      await page.close();
    });

    await run('E4 settings promises (six things / week start)', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'settings');
      await settle(page, 350);
      const settingsText = await L.text(page, '#view');
      console.log('E4 settings text:', settingsText.slice(0, 400));
      await shot(page, 'E4-01-settings');
      // BEHAVIORS F says both rows exist; COVERAGE 6.1 item 7 says they are all present.
      assert(/六件事|Six things/i.test(settingsText), 'Settings exposes the six-things setting (BEHAVIORS F / COVERAGE 6.1)');
      assert(/每周起始日|Week starts/i.test(settingsText), 'Settings exposes week start (BEHAVIORS F / COVERAGE 6.1)');
      await page.close();
    });

    await run('E5 search', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'search');
      await settle(page, 300);
      const input = page.locator('#view input').first();
      await input.fill('预算');
      await settle(page, 400);
      await shot(page, 'E5-01-search-results');
      const txt = await L.text(page, '#view');
      console.log('E5 results:', txt.slice(0, 250));
      assert(/Q4 预算表/.test(txt), 'todo result shown');
      const marks = await L.count(page, '#view mark');
      assert(marks > 0, 'query highlighted');
      // click result
      await page.locator('#view .row, #view [data-testid]').filter({ hasText: 'Q4 预算表' }).first().click().catch(async () => {
        await page.evaluate(() => {
          const n = Array.from(document.querySelectorAll('#view button, #view [role="button"]')).find((x) => /Q4 预算表/.test(x.textContent));
          if (n) n.click();
        });
      });
      await settle(page, 350);
      assertEq((await state(page)).route.name, 'detail', 'search result opens detail');
      await L.go(page, 'search');
      await input.fill('不存在的词xyz');
      await settle(page, 350);
      await shot(page, 'E5-02-search-empty');
      assert(/没有找到|No results/i.test(await L.text(page, '#view')), 'no-results empty state');
      await page.close();
    });

    await run('E6 tags validation', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'tags');
      await settle(page, 300);
      await page.click('[data-testid="tags-create"]');
      await settle(page, 250);
      await page.click('[data-testid="tag-save"]');
      await settle(page, 250);
      let err = await L.text(page, '.field-error');
      console.log('E6 empty name error:', err);
      assert(/必填|required|名称/i.test(err || ''), 'empty tag name inline error');
      await page.locator('.modal input').fill('工作');
      await page.click('[data-testid="tag-save"]');
      await settle(page, 250);
      err = await L.text(page, '.field-error');
      console.log('E6 duplicate error:', err);
      assert(/重复|already|duplicate/i.test(err || ''), 'duplicate tag inline error');
      await shot(page, 'E6-01-tag-duplicate');
      await page.keyboard.press('Escape');
      await settle(page, 200);
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('E7 trash purge / empty confirm', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'trash');
      await settle(page, 300);
      await shot(page, 'E7-01-trash');
      const total0 = await page.evaluate(() => window.Store.state.todos.filter((t) => t.deletedAt).length + window.Store.state.events.filter((e) => e.deletedAt).length);
      assert(total0 > 0, 'seed trash non-empty');
      await page.click('[data-testid="trash-empty"]');
      await settle(page, 250);
      assert(await L.exists(page, '.modal.confirm'), 'empty trash asks confirmation');
      await L.clickText(page, '.modal button', '取消');
      await settle(page, 250);
      const total1 = await page.evaluate(() => window.Store.state.todos.filter((t) => t.deletedAt).length + window.Store.state.events.filter((e) => e.deletedAt).length);
      assertEq(total1, total0, 'cancel writes nothing');
      await page.click('[data-testid="trash-empty"]');
      await settle(page, 250);
      await L.clickText(page, '.modal button', '清空回收站');
      await settle(page, 400);
      await shot(page, 'E7-02-trash-empty-state');
      const total2 = await page.evaluate(() => window.Store.state.todos.filter((t) => t.deletedAt).length + window.Store.state.events.filter((e) => e.deletedAt).length);
      assertEq(total2, 0, 'trash emptied');
      assert(/回收站是空的|Trash is empty/i.test(await L.text(page, '#view')), 'empty state');
      await page.close();
    });

    await run('E8 date-only deadline and all-day event', async () => {
      const page = await newPage(browser, DESKTOP);
      // create a date-only todo via composer
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 250);
      await page.fill('[data-testid="composer-title"]', '只有日期的截止');
      await page.click('[data-testid="composer-deadline"]');
      await settle(page, 250);
      await page.fill('[data-testid="deadline-time"]', '');
      await page.click('[data-testid="deadline-apply"]');
      await settle(page, 250);
      await page.click('[data-testid="composer-save"]');
      await settle(page, 400);
      const rowText = await L.text(page, '[data-testid="todo-list"]');
      console.log('E8 date-only row:', rowText.slice(0, 200));
      assert(!/00:00/.test(rowText), 'date-only deadline does not show 00:00');
      // all-day seed event should be visible in the calendar
      await L.go(page, 'calendar');
      await page.click('[data-testid="cal-view-day"]');
      await settle(page, 300);
      await page.evaluate(() => {
        const d = new Date(); d.setDate(d.getDate() + 2);
        window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        window.Store.state.calendarView = 'day';
        window.App.go('calendar');
      });
      await settle(page, 400);
      await shot(page, 'E8-01-all-day-day');
      const allDayChips = await L.texts(page, '.all-day-row .month-event');
      console.log('E8 all-day chips:', allDayChips);
      assert(allDayChips.some((x) => /国庆假期/.test(x)), 'seed all-day event 国庆假期 must render in the all-day row');
      await page.close();
    });

    await run('E9 month/week/day consistency after move', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'calendar');
      await page.click('[data-testid="cal-view-week"]');
      await settle(page, 300);
      // move lunch to tomorrow via reschedule dialog
      await page.locator('[data-testid="event-block"]', { hasText: '与设计师午餐' }).first().click({ button: 'right' });
      await settle(page, 200);
      await L.clickText(page, '.menu button', '改期');
      await settle(page, 250);
      const inputs = page.locator('.modal input[type="datetime-local"]');
      const shifted = await page.evaluate(([s, e]) => {
        const ds = window.U.fromInputDateTime(s); const de = window.U.fromInputDateTime(e);
        ds.setDate(ds.getDate() + 1); de.setDate(de.getDate() + 1);
        return [window.U.toInputDateTime(ds), window.U.toInputDateTime(de)];
      }, [await inputs.nth(0).inputValue(), await inputs.nth(1).inputValue()]);
      await inputs.nth(0).fill(shifted[0]);
      await inputs.nth(1).fill(shifted[1]);
      await L.clickText(page, '.modal button', '保存');
      await settle(page, 400);
      const counts = await page.evaluate(() => {
        const S = window.Store;
        const today = window.U.startOfDay(window.U.now());
        const tomorrow = window.U.addDays(today, 1);
        return {
          today: S.eventsOnDay(today).filter((e) => e.summary === '与设计师午餐').length,
          tomorrow: S.eventsOnDay(tomorrow).filter((e) => e.summary === '与设计师午餐').length,
        };
      });
      console.log('E9 day counts:', counts);
      assertEq(counts.today, 0, 'event left today');
      assertEq(counts.tomorrow, 1, 'event appears tomorrow');
      // month view chip on tomorrow cell
      await page.click('[data-testid="cal-view-month"]');
      await settle(page, 350);
      const monthText = await L.text(page, '#view');
      console.log('E9 month includes moved lunch?', /与设计师午餐/.test(monthText));
      assert(/与设计师午餐/.test(monthText), 'month view shows moved event');
      await shot(page, 'E9-01-month-after-move');
      await page.close();
    });

    await run('E10 keyboard access / focus trap', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'todos');
      await settle(page, 300);
      // rows are focusable buttons via keyboard
      const firstTile = page.locator('[data-testid="todo-tile"]').first();
      await firstTile.locator('.row-title').click();
      await settle(page, 300);
      // go back, then focus a row and press Enter
      await L.go(page, 'todos');
      await settle(page, 300);
      const focusInfo = await page.evaluate(() => {
        const row = document.querySelector('[data-testid="todo-tile"] .todo-row');
        row.focus();
        return { tabindex: row.getAttribute('tabindex'), role: row.getAttribute('role'), active: document.activeElement === row };
      });
      console.log('E10 row focusability:', focusInfo);
      assert(focusInfo.active, 'row is focusable');
      await page.keyboard.press('Enter');
      await settle(page, 350);
      assertEq((await state(page)).route.name, 'detail', 'Enter opens focused row');
      // focus trap in modal
      await L.go(page, 'todos');
      await page.click('[data-testid="todos-create"]');
      await settle(page, 250);
      await page.fill('[data-testid="composer-title"]', '焦点陷阱');
      await page.keyboard.press('Escape');
      await settle(page, 300);
      assert(await L.exists(page, '.modal.confirm'), 'confirm open');
      const trapped = await page.evaluate(() => {
        const panel = document.querySelector('.modal.confirm');
        const items = Array.from(panel.querySelectorAll('button'));
        const first = items[0], last = items[items.length - 1];
        last.focus();
        return { first: first.textContent, last: last.textContent };
      });
      await page.keyboard.press('Tab');
      const afterTab = await page.evaluate(() => document.activeElement.textContent);
      console.log('E10 focus trap last->first:', trapped, 'active after Tab:', afterTab);
      assertEq(afterTab, trapped.first, 'Tab from last wraps to first');
      await page.close();
    });

    await run('E11 AI proposal apply / reject', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'chat');
      await settle(page, 300);
      await page.fill('[data-testid="chat-input"]', '把「Q4 预算表」安排到明天上午');
      await page.keyboard.press('Enter');
      await settle(page, 900);
      await shot(page, 'E11-01-proposal');
      const before = await page.evaluate(() => window.Store.state.allocations.length);
      const proposal = page.locator('.proposal, .msg.assistant').filter({ hasText: 'Q4 预算表' }).last();
      console.log('E11 proposal text:', await L.text(page, '.chat-scroll'));
      const applyBtn = page.locator('#view button').filter({ hasText: /应用|Apply/ }).last();
      assert(await applyBtn.count() > 0, 'proposal Apply button present');
      await applyBtn.click();
      await settle(page, 500);
      const after = await page.evaluate(() => ({ n: window.Store.state.allocations.length, applied: document.body.textContent.includes('已应用') || document.body.textContent.includes('Applied') }));
      console.log('E11 apply:', { before, after });
      assertEq(after.n, before + 1, 'apply writes exactly one allocation');
      assert(after.applied, 'card shows applied');
      await shot(page, 'E11-02-applied');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
    });

    await run('E12 offline sync does not fake success', async () => {
      const page = await newPage(browser, DESKTOP);
      await L.go(page, 'settings', { section: 'account' });
      await settle(page, 300);
      // sign in via evaluate to reach the sync row
      const signed = await page.evaluate(() => {
        const S = window.Store;
        S.state.account = { signedIn: true, email: 'me@example.com', server: 'https://nas.local', lastSync: null, phase: 'idle', rejected: [] };
        S.state.offline = true;
        window.App.render();
        return true;
      });
      await settle(page, 350);
      await shot(page, 'E12-01-offline-account');
      const txt = await L.text(page, '#view');
      console.log('E12 account text:', txt.slice(0, 350));
      // click sync now
      const syncBtn = page.locator('[data-testid="settings-sync"]');
      if (await syncBtn.count()) {
        await syncBtn.click();
        await settle(page, 600);
        const st = await page.evaluate(() => ({ lastSync: window.Store.state.account.lastSync, toast: document.querySelector('.toast') && document.querySelector('.toast').textContent }));
        console.log('E12 sync offline:', st);
        assertEq(st.lastSync, null, 'offline sync must not write lastSync');
        assert(/离线|Offline|无法|failed/i.test(st.toast || ''), 'offline sync warns');
      } else {
        console.log('E12 sync row not found; content:', txt);
      }
      await page.close();
    });
  } finally {
    await browser.close();
  }
  console.log('\n=== SUMMARY ===');
  results.forEach(([n, s, m]) => console.log(`${s} ${n}${m ? ': ' + m : ''}`));
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
