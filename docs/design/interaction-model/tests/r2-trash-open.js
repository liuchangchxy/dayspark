const L = require('./r2-lib');
const { launch, newPage, settle, shot, DESKTOP } = L;
async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    await L.go(page, 'trash');
    await settle(page, 350);
    const row = page.locator('[data-testid="trash-row"]').first();
    console.log('row:', (await row.textContent()).replace(/\s+/g, ' '));
    const title = row.locator('.row-title, .title, [data-testid="trash-title"]').first();
    if (await title.count()) await title.click(); else await row.click({ position: { x: 120, y: 10 } });
    await settle(page, 400);
    await shot(page, 'TRASH-01-row-click');
    console.log('route:', await page.evaluate(() => window.Store.state.route));
    console.log('view:', (await L.text(page, '#view')).slice(0, 200));
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
