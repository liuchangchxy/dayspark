const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  const info = await p.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule);
    const d = new Date(e.startDt.getFullYear(), e.startDt.getMonth(), e.startDt.getDate());
    window.Store.state.calendarAnchor = d;
    window.Store.state.calendarFocusDay = d;
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
    return { eStart: e.startDt.toString(), anchor: d.toString(), onDay: window.Store.eventsOnDay(d).map((x) => x.summary), view: window.Store.state.calendarView, anchorAfter: window.Store.state.calendarAnchor.toString() };
  });
  console.log(info);
  await p.waitForTimeout(500);
  console.log('title', await p.evaluate(() => document.querySelector('.page-title').textContent));
  console.log('blocks', await p.$$eval('[data-testid="event-block"]', (ns) => ns.map((n) => n.textContent.slice(0, 20))));
  await b.close();
})();
