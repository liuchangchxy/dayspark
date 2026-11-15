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
  await page.evaluate(() => { window.Store.state.todosView = { kind: 'day', day: window.Store.state.actionDate }; window.App.go('todos'); });
  await page.waitForTimeout(250);
  await page.evaluate(() => window.App.openComposer('todo'));
  await page.waitForTimeout(320);
  await page.fill('[data-testid="composer-title"]', '高亮是哪一行');
  await page.waitForTimeout(150);
  await page.evaluate(() => document.querySelector('[data-testid="composer-save"]').click());
  for (const ms of [60, 150, 400]) {
    await page.waitForTimeout(ms);
    console.log(ms, await page.evaluate(() => ({
      route: window.Store.state.route.name,
      hl: window.Store.state.highlight,
      hlNodes: Array.from(document.querySelectorAll('.hl')).map((n) => ({ tag: n.className, id: n.dataset.id, text: n.textContent.slice(0, 20) })),
      tiles: Array.from(document.querySelectorAll('[data-testid="todo-tile"]')).map((n) => ({ id: n.dataset.id, text: n.textContent.slice(0, 18) })),
    })));
  }
  await browser.close();
})();
