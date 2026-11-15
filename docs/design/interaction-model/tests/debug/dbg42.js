const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', (e) => console.log('PAGEERROR', e.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true);

  // F4
  const id = await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => x.recurrence && !x.deletedAt);
    window.App.openComposer('todo', { mode: 'edit', id: t.id });
    return t.id;
  });
  await page.waitForTimeout(320);
  console.log('before', await page.evaluate(() => window.Store.state.allocations.length));
  await page.click('[data-testid="composer-schedule"]');
  await page.waitForTimeout(250);
  console.log('occ sel?', await page.evaluate(() => {
    const s = document.querySelector('[data-testid="schedule-occurrence"]');
    return s ? { n: s.options.length, first: s.value } : null;
  }));
  await page.evaluate(() => document.querySelector('[data-testid="schedule-apply"]').click());
  await page.waitForTimeout(250);
  console.log('after apply', await page.evaluate(() => ({
    n: window.Store.state.allocations.length,
    composer: JSON.stringify(window.Store.state.composer),
  })));
  const draft = await page.evaluate(() => JSON.stringify(window.__composer.draftFromRoute()));
  console.log('draft', draft);
  await page.evaluate(() => { const b = document.querySelector('[data-testid="composer-save"]'); if (b && !b.disabled) b.click(); });
  await page.waitForTimeout(350);
  console.log('after save', await page.evaluate(() => window.Store.state.allocations.length));
  await browser.close();
})();
