const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => { window.Store.state.calendarView = 'day'; window.App.go('calendar'); });
  await p.waitForTimeout(300);
  console.log(await p.evaluate(() => {
    const rail = document.querySelector('.lane-rail');
    const lane = document.querySelector('[data-testid="deadline-lane"]');
    return { railW: rail ? Math.round(rail.getBoundingClientRect().width) : null, railScrollW: rail ? rail.scrollWidth : null, laneH: Math.round(lane.getBoundingClientRect().height), gridTop: Math.round(document.querySelector('.time-wrap').getBoundingClientRect().top) };
  }));
  // composer at 320
  const q = await b.newPage({ viewport: { width: 320, height: 700 } });
  await q.goto(URL);
  await q.waitForFunction(() => window.__READY__);
  await q.evaluate(() => window.App.openComposer('todo', {}));
  await q.waitForTimeout(250);
  console.log('320 overflow', await q.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth));
  await q.screenshot({ path: '/tmp/g0-320-composer.png' });
  await b.close();
})();
