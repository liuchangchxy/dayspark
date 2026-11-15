const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const m = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  await m.goto(URL);
  await m.waitForFunction(() => window.__READY__);
  const shots = [
    ['action', () => window.App.go('action')],
    ['todos', () => window.App.go('todos')],
    ['month', () => { window.Store.state.calendarView = 'month'; window.App.go('calendar'); }],
    ['day', () => { window.Store.state.calendarView = 'day'; window.App.go('calendar'); }],
    ['detail', () => window.Store.navigate('detail', { type: 'todo', id: 1 })],
    ['settings', () => window.App.go('settings')],
    ['search', () => window.App.go('search')],
    ['trash', () => window.App.go('trash')],
  ];
  for (const [name, fn] of shots) {
    await m.evaluate(fn);
    await m.waitForTimeout(400);
    await m.screenshot({ path: `/tmp/g0m-${name}.png` });
  }
  await b.close();
})();
