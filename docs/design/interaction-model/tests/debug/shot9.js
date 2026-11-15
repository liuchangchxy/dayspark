const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve('/Users/chang/Desktop/Code/dayspark-g0/docs/design/interaction-model/index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => { window.Store.state.theme = 'dark'; window.Store.applyTheme(); window.Store.state.calendarView = 'week'; window.App.go('calendar'); });
  await p.waitForTimeout(400);
  await p.screenshot({ path: '/tmp/g0-1920-dark-cal.png' });
  await p.evaluate(() => window.App.go('action'));
  await p.waitForTimeout(300);
  await p.screenshot({ path: '/tmp/g0-1920-dark-action.png' });
  await b.close();
})();
