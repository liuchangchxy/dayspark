const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = [];
  p.on('pageerror', (e) => errs.push(e.message));
  p.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => window.App.go('settings'));
  await p.waitForTimeout(200);
  await p.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.setting-row')).find((r) => r.textContent.includes('状态与边界'));
    row.click();
  });
  await p.waitForTimeout(250);
  console.log('route', await p.evaluate(() => window.Store.state.route.name), 'errs', errs);
  await p.evaluate(() => window.App.back());
  await p.waitForTimeout(200);
  console.log('back route', await p.evaluate(() => window.Store.state.route.name));
  await b.close();
})();
