const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const widths = [360, 390, 768, 900, 1024, 1180, 1440, 1920];
  const routes = ['action', 'calendar', 'todos', 'search', 'chat', 'tags', 'calendars', 'trash', 'settings', 'about', 'feedback', 'states'];
  for (const w of widths) {
    const p = await b.newPage({ viewport: { width: w, height: 860 } });
    await p.goto(URL);
    await p.waitForFunction(() => window.__READY__);
    const bad = [];
    for (const r of routes) {
      await p.evaluate((x) => window.App.go(x), r);
      await p.waitForTimeout(120);
      const ov = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      if (ov > 0) bad.push(`${r}:${ov}`);
    }
    for (const v of ['month', 'week', 'day']) {
      await p.evaluate((x) => { window.Store.state.calendarView = x; window.App.go('calendar'); }, v);
      await p.waitForTimeout(180);
      const ov = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      if (ov > 0) bad.push(`calendar-${v}:${ov}`);
    }
    await p.evaluate(() => window.Store.navigate('detail', { type: 'todo', id: 1 }));
    await p.waitForTimeout(150);
    const ovd = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    if (ovd > 0) bad.push(`detail:${ovd}`);
    console.log(w, bad.length ? bad.join(' ') : 'ok');
    await p.close();
  }
  await b.close();
})();
