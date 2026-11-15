const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  const shots = [
    ['chat', () => window.App.go('chat')],
    ['trash', () => window.App.go('trash')],
    ['states', () => window.App.go('states')],
    ['tags', () => window.App.go('tags')],
    ['calendars', () => window.App.go('calendars')],
    ['search', () => { window.App.go('search'); }],
  ];
  for (const [name, fn] of shots) {
    await p.evaluate(fn);
    await p.waitForTimeout(350);
    await p.screenshot({ path: `/tmp/g0d-${name}.png` });
  }
  await p.evaluate(() => { window.App.go('search'); });
  await p.waitForTimeout(200);
  await p.evaluate(() => { const i = document.querySelector('input[type="search"], .search-input, input'); if (i) { i.value = '预算'; i.dispatchEvent(new Event('input', { bubbles: true })); } });
  await p.waitForTimeout(300);
  await p.screenshot({ path: '/tmp/g0d-search-results.png' });
  await b.close();
})();
