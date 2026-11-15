const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  // recurring event present?
  console.log('recurring events', await p.evaluate(() => window.Store.state.events.filter((e) => e.rrule).map((e) => e.summary)));
  await p.evaluate(() => { window.Store.state.calendarView = 'day'; window.App.go('calendar'); });
  await p.waitForTimeout(400);
  const blocks = await p.$$eval('[data-testid="event-block"]', (ns) => ns.map((n) => ({ id: n.dataset.id, t: n.textContent })));
  console.log('blocks', blocks);
  // drag first block down 2 hours
  const box = await p.evaluate(() => { const r = document.querySelector('[data-testid="event-block"]').getBoundingClientRect(); return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + 6) }; });
  await p.mouse.move(box.x, box.y);
  await p.mouse.down();
  await p.mouse.move(box.x, box.y + 60, { steps: 8 });
  await p.mouse.move(box.x, box.y + 100, { steps: 8 });
  await p.mouse.up();
  await p.waitForTimeout(300);
  console.log('sheet?', await p.evaluate(() => !!document.querySelector('.sheet')));
  console.log('toast', await p.evaluate(() => (document.querySelector('#toast .toast') || {}).textContent));
  await p.screenshot({ path: '/tmp/g0-drag.png' });
  await b.close();
})();
