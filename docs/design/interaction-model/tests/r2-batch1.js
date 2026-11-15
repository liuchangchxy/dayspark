const L = require('./r2-lib');
const { launch, newPage, settle, shot, assert, assertEq, state, DESKTOP } = L;

async function openTomorrowDay(page) {
  await L.go(page, 'calendar');
  await page.click('[data-testid="cal-view-day"]');
  await settle(page, 220);
  await page.click('button[aria-label="下一段"]');
  await settle(page, 300);
}

async function main() {
  const browser = await launch();
  try {
    // ---------------- F1 ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await openTomorrowDay(page);
      await shot(page, 'F1-01-tomorrow-day');
      const before = await state(page);
      const series0 = before.events.find((e) => e.rrule);
      assert(series0, 'seed recurring event exists');
      assert(series0.exdates.length === 0, 'seed series has no exdates');
      const blocks = await L.texts(page, '[data-testid="event-block"]');
      console.log('F1 blocks before:', blocks);
      // right click the recurring block (周会)
      const idx = await page.evaluate(() => Array.from(document.querySelectorAll('[data-testid="event-block"]')).findIndex((n) => /周会/.test(n.textContent)));
      assert(idx >= 0, 'found recurring event block');
      await page.locator('[data-testid="event-block"]').nth(idx).click({ button: 'right' });
      await settle(page, 220);
      await shot(page, 'F1-02-context-menu');
      await L.clickText(page, '.menu button', '删除');
      await settle(page, 200);
      assert(await L.exists(page, '.modal.confirm'), 'confirm dialog shown');
      await shot(page, 'F1-03-confirm');
      await L.clickText(page, '.modal button', '移到回收站');
      await settle(page, 300);
      assert(await L.exists(page, '.sheet'), 'scope sheet shown after confirm');
      await shot(page, 'F1-04-scope-sheet');
      const scopeLabels = await L.texts(page, '.sheet .slot-sheet-option .t');
      console.log('F1 scope labels:', scopeLabels);
      assertEq(scopeLabels.length, 3, 'three scope choices');
      await page.click('[data-testid="scope-this"]');
      await settle(page, 400);
      await shot(page, 'F1-05-after-delete-this');
      const after = await state(page);
      const series = after.events.find((e) => e.rrule);
      console.log('F1 series after:', series.deletedAt, series.exdates);
      assertEq(series.deletedAt, null, 'series must survive');
      assertEq(series.exdates.length, 1, 'one exdate added');
      const toast = await L.text(page, '.toast');
      console.log('F1 toast:', toast);
      assert(toast && /已删除/.test(toast), 'deletion toast');
      // other occurrences still intact: tomorrow next week
      const occ = await page.evaluate(() => {
        const S = window.Store;
        const e = S.state.events.find((x) => x.rrule);
        const anchor = S.state.calendarAnchor;
        const next = new Date(anchor.getTime() + 7 * 86400000);
        return { anchor: S.eventsOnDay(anchor).filter((x) => x.id === e.id).length, next: S.eventsOnDay(next).filter((x) => x.id === e.id).length };
      });
      console.log('F1 occurrences anchor/next-week:', occ);
      assertEq(occ.anchor, 0, 'deleted occurrence gone from its day');
      assertEq(occ.next, 1, 'next week occurrence still present');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F1 PASS');
    }

    // ---------------- F2 ----------------
    {
      const page = await newPage(browser, DESKTOP);
      await openTomorrowDay(page);
      const before = await state(page);
      const series0 = before.events.find((e) => e.rrule);
      const baseStart = new Date(series0.startDt);
      const expectedTime = String(baseStart.getHours()).padStart(2, '0') + ':' + String(baseStart.getMinutes()).padStart(2, '0');
      const idx = await page.evaluate(() => Array.from(document.querySelectorAll('[data-testid="event-block"]')).findIndex((n) => /周会/.test(n.textContent)));
      await page.locator('[data-testid="event-block"]').nth(idx).click();
      await settle(page, 350);
      await shot(page, 'F2-01-occurrence-detail');
      const detail = await L.text(page, '#view');
      console.log('F2 detail:', detail.slice(0, 300));
      assert(detail.includes(expectedTime), `detail shows occurrence time ${expectedTime}`);
      assert(!/00:00/.test(detail), 'detail must not show 00:00');
      // click Edit (header pencil has aria-label 编辑)
      await page.click('#view button[aria-label="编辑"]');
      await settle(page, 250);
      assert(await L.exists(page, '.sheet'), 'edit scope sheet shown');
      await shot(page, 'F2-02-edit-scope');
      await page.click('[data-testid="scope-this"]');
      await settle(page, 350);
      assert(await L.exists(page, '[data-testid="composer"]'), 'composer opened');
      await shot(page, 'F2-03-composer-this-occurrence');
      const timeVal = await page.inputValue('[data-testid="composer-start-time"]');
      const dateVal = await page.inputValue('[data-testid="composer-start-date"]');
      const cs = await state(page);
      console.log('F2 composer date/time:', dateVal, timeVal, 'composer route:', cs.route);
      assertEq(timeVal, expectedTime, 'composer opens at occurrence time');
      // change the title and save
      await page.fill('[data-testid="composer-title"]', '周会（本次改期）');
      await page.click('[data-testid="composer-save"]');
      await settle(page, 450);
      await shot(page, 'F2-04-after-save');
      const after = await state(page);
      const series = after.events.find((e) => e.id === series0.id);
      console.log('F2 series after save:', { start: series.startDt, end: series.endDt, exdates: series.exdates, deleted: series.deletedAt });
      assertEq(series.startDt, series0.startDt, 'series base start untouched');
      assertEq(series.endDt, series0.endDt, 'series base end untouched');
      assertEq(series.exdates.length, 1, 'one exdate added to series');
      const copies = after.events.filter((e) => e.id !== series0.id && !e.rrule && e.summary.includes('本次改期'));
      console.log('F2 copies:', copies);
      assertEq(copies.length, 1, 'one standalone copy created');
      assertEq(new Date(copies[0].startDt).getTime(), baseStart.getTime(), 'copy keeps occurrence start');
      console.log('F2 route after save:', after.route, 'detail text:', await L.text(page, '#view'));
      assertEq(after.route.name === 'calendar' || after.route.name === 'detail', true, 'left composer');
      assertEq(page.__errors, [], 'no console errors');
      await page.close();
      console.log('F2 PASS');
    }
  } finally {
    await browser.close();
  }
}
main().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
