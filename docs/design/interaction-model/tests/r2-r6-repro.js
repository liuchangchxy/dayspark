const L = require('./r2-lib');
const { launch, newPage, settle, shot, assertEq, state, DESKTOP } = L;

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
    const page = await newPage(browser, DESKTOP);
    await openTomorrowDay(page);
    const seriesId = await page.evaluate(() => window.Store.state.events.find((e) => e.rrule).id);
    const block = page.locator('[data-testid="event-block"]', { hasText: '周会' }).first();
    await block.click();
    await settle(page, 300);
    console.log('route', await page.evaluate(() => window.Store.state.route));
    console.log('detail text', (await L.text(page, '#view')).slice(0, 180));
    await page.click('#view button[aria-label="编辑"]');
    await settle(page, 250);
    await page.click('[data-testid="scope-this"]');
    await settle(page, 300);
    await page.fill('[data-testid="composer-title"]', '周会 副本A');
    await page.click('[data-testid="composer-save"]');
    await settle(page, 450);
    await shot(page, 'DUP-01-after-first-split');
    const route1 = await page.evaluate(() => window.Store.state.route);
    const series1 = (await state(page)).events.find((e) => e.id === seriesId);
    const copies1 = (await state(page)).events.filter((e) => !e.rrule && /周会/.test(e.summary));
    console.log('after first split route', route1);
    console.log('series exdates', series1.exdates);
    console.log('non-recurring 周会 copies', copies1.map((c) => ({ id: c.id, summary: c.summary, start: c.startDt, deleted: c.deletedAt })));
    await page.click('#view button[aria-label="编辑"]');
    await settle(page, 250);
    const scopeShown = await L.exists(page, '[data-testid="scope-this"]');
    const composerTitle = await page.inputValue('[data-testid="composer-title"]').catch(() => null);
    console.log('second edit scope sheet?', scopeShown, 'composer title?', composerTitle);
    if (scopeShown) await page.click('[data-testid="scope-this"]');
    await settle(page, 300);
    await page.fill('[data-testid="composer-title"]', '周会 副本B');
    await page.click('[data-testid="composer-save"]');
    await settle(page, 450);
    await shot(page, 'DUP-02-after-second-split');
    const series2 = (await state(page)).events.find((e) => e.id === seriesId);
    const copies2 = (await state(page)).events.filter((e) => !e.rrule && /周会/.test(e.summary));
    console.log('after second split route', (await state(page)).route);
    console.log('series exdates', series2.exdates);
    console.log('copies', copies2.map((c) => ({ id: c.id, summary: c.summary, start: c.startDt, deleted: c.deletedAt })));
    await L.go(page, 'calendar');
    await settle(page, 300);
    await page.click('[data-testid="cal-view-day"]');
    await settle(page, 250);
    await page.click('button[aria-label="下一段"]');
    await settle(page, 350);
    const shown = await L.texts(page, '[data-testid="event-block"]');
    console.log('tomorrow blocks', shown);
    await shot(page, 'DUP-03-tomorrow-blocks');
    await page.close();
  } finally {
    await browser.close();
  }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
