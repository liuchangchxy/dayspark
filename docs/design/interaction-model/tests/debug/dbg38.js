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

  // F2: occurrence detail buttons
  await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const d = new Date(e.startDt.getTime());
    window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarFocusDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
  });
  await page.waitForTimeout(250);
  await page.click('[data-testid="event-block"]');
  await page.waitForTimeout(300);
  const btns = await page.$$eval('#view button', (ns) => ns.map((n) => ({ text: n.textContent.trim().slice(0, 20), label: n.getAttribute('aria-label'), cls: n.className })));
  console.log('DETAIL BUTTONS', JSON.stringify(btns, null, 1));
  console.log('ROUTE', await page.evaluate(() => JSON.stringify(window.Store.state.route)));

  // F3: todo tile structure
  await page.evaluate(() => window.App.go('todos'));
  await page.waitForTimeout(250);
  const tile = await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => x.recurrence && !x.deletedAt);
    const n = document.querySelector(`[data-testid="todo-tile"][data-id="${t.id}"]`);
    return { id: t.id, html: n ? n.innerHTML.slice(0, 400) : null, found: !!n };
  });
  console.log('TILE', JSON.stringify(tile, null, 1));

  // F16: schedule picker chips
  await page.evaluate(() => {
    const t = window.Store.state.todos.find((x) => !x.recurrence && !x.deletedAt && !x.parentId);
    window.App.go('detail', { type: 'todo', id: t.id });
  });
  await page.waitForTimeout(280);
  const detailBtns = await page.$$eval('#view button', (ns) => ns.map((n) => ({ text: n.textContent.trim().slice(0, 14), label: n.getAttribute('aria-label') })));
  console.log('TODO DETAIL BUTTONS', JSON.stringify(detailBtns));
  await page.evaluate(() => {
    const el = Array.from(document.querySelectorAll('#view button')).find((x) => /安排|Schedule/.test(x.textContent) || /安排|Schedule/.test(x.getAttribute('aria-label') || ''));
    if (el) el.click();
  });
  await page.waitForTimeout(250);
  console.log('SHEET?', await page.evaluate(() => document.querySelectorAll('.sheet').length));
  console.log('CHIPS', await page.$$eval('.sheet button', (ns) => ns.map((n) => n.textContent.trim().slice(0, 20))));
  await browser.close();
})();
