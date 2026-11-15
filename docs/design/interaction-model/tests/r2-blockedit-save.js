const L = require('./r2-lib');
const { launch, newPage, settle, shot, DESKTOP } = L;
async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    await L.go(page, 'calendar');
    await settle(page, 300);
    await page.click('[data-testid="cal-view-day"]');
    await settle(page, 250);
    await page.click('button[aria-label="下一段"]');
    await settle(page, 300);
    const block = page.locator('[data-testid="event-block"]', { hasText: '周会' }).first();
    await block.click({ button: 'right' });
    await settle(page, 250);
    await L.clickText(page, '.menu button', '编辑');
    await settle(page, 350);
    console.log('scope?', await L.exists(page, '[data-testid="scope-this"]'), 'composer?', await L.exists(page, '[data-testid="composer"]'));
    console.log('composer title:', await page.inputValue('[data-testid="composer-title"]'));
    await page.fill('[data-testid="composer-title"]', '周会 全系列改名');
    await page.click('[data-testid="composer-save"]');
    await settle(page, 500);
    await shot(page, 'B1b-01-after-blockedit-save');
    const info = await page.evaluate(() => {
      const S = window.Store;
      const e = S.state.events.find((x) => x.rrule);
      return { series: { id: e.id, summary: e.summary }, standalone: S.state.events.filter((x) => !x.rrule && /周会/.test(x.summary)).map((x) => x.summary), route: S.state.route };
    });
    console.log(info);
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
