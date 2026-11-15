const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  for (const w of [1024, 768]) {
    const p = await b.newPage({ viewport: { width: w, height: 800 }, deviceScaleFactor: 2 });
    await p.goto(URL);
    await p.waitForFunction(() => window.__READY__);
    await p.evaluate(() => { window.Store.state.calendarView = 'week'; window.App.go('calendar'); });
    await p.waitForTimeout(400);
    await p.screenshot({ path: `/tmp/g0-w${w}-calendar.png` });
    await p.evaluate(() => window.App.go('todos'));
    await p.waitForTimeout(300);
    await p.screenshot({ path: `/tmp/g0-w${w}-todos.png` });
    await p.close();
  }
  await b.close();
})();
