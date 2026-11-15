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
  await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule);
    const d = new Date(e.startDt.getTime());
    window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarFocusDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
  });
  await page.waitForTimeout(300);
  const info = await page.evaluate(() => {
    const b = document.querySelector('[data-testid="event-block"]');
    return { id: b && b.dataset.id, text: b && b.textContent };
  });
  console.log('block', info);
  await page.evaluate(() => {
    const b = document.querySelector('[data-testid="event-block"]');
    b.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 600, clientY: 400 }));
  });
  await page.waitForTimeout(200);
  const menu = await page.$$eval('.menu button', (ns) => ns.map((n) => n.textContent.trim()));
  console.log('menu', menu);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.menu button')).find((x) => x.textContent.includes('删除'));
    b.click();
  });
  await page.waitForTimeout(200);
  const confirmText = await page.evaluate(() => {
    const m = document.querySelector('.modal, .sheet');
    return m ? m.textContent.replace(/\s+/g, ' ').slice(0, 200) : null;
  });
  console.log('confirm', confirmText);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.modal button')).find((x) => /移到回收站|Move to Trash/.test(x.textContent));
    if (b) b.click();
  });
  await page.waitForTimeout(300);
  const after = await page.evaluate(() => {
    const series = window.Store.state.events.find((x) => x.rrule);
    return { deletedAt: series.deletedAt, exdates: (series.exdates || []).length, events: window.Store.state.events.length };
  });
  console.log('after delete from block menu', after);

  // occurrence detail time
  await page.evaluate(() => {
    window.Store.state.events.forEach((e) => { e.deletedAt = null; });
    const e = window.Store.state.events.find((x) => x.rrule);
    const d = new Date(e.startDt.getTime());
    window.Store.state.calendarAnchor = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarFocusDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    window.Store.state.calendarView = 'day';
    window.App.go('calendar');
  });
  await page.waitForTimeout(300);
  await page.click('[data-testid="event-block"]');
  await page.waitForTimeout(300);
  console.log('detail', await page.evaluate(() => document.querySelector('#view').textContent.replace(/\s+/g, ' ').slice(0, 220)));
  await browser.close();
})();
