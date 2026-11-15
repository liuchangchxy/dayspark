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

  console.log('EventOps?', await page.evaluate(() => typeof window.EventOps, ));
  const r = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const d = new Date(e.startDt.getTime());
    const occ = new Date(d.getFullYear(), d.getMonth(), d.getDate(), e.startDt.getHours(), e.startDt.getMinutes());
    window.App.go('detail', { type: 'event', id: e.id, occurrence: occ.getTime() });
    return { id: e.id, occ: occ.getTime(), start: e.startDt.getTime() };
  });
  await page.waitForTimeout(300);
  console.log('detail text', await page.evaluate(() => document.querySelector('#view').textContent.replace(/\s+/g, ' ').slice(0, 200)));
  const res = await page.evaluate(() => {
    try {
      const btns = Array.from(document.querySelectorAll('#view button'));
      const edit = btns.find((x) => x.textContent.trim() === '编辑');
      edit.click();
      return { clicked: true, sheets: document.querySelectorAll('.sheet').length };
    } catch (e) { return { err: String(e) }; }
  });
  console.log('edit click', res);
  await page.waitForTimeout(300);
  console.log('sheet after', await page.evaluate(() => ({ sheets: document.querySelectorAll('.sheet').length, opts: Array.from(document.querySelectorAll('.sheet .slot-sheet-option .t')).map((n) => n.textContent) })));

  // tiles in todos
  await page.evaluate(() => { window.UI.closeAll(); window.App.go('todos'); });
  await page.waitForTimeout(300);
  const tiles = await page.evaluate(() => ({
    view: JSON.stringify(window.Store.state.todosView),
    ids: Array.from(document.querySelectorAll('[data-testid="todo-tile"]')).map((n) => n.dataset.id),
    rows: Array.from(document.querySelectorAll('.todo-row')).map((n) => n.dataset.id),
    titles: Array.from(document.querySelectorAll('.todo-row')).slice(0, 12).map((n) => n.textContent.slice(0, 24)),
  }));
  console.log('TILES', JSON.stringify(tiles, null, 1));
  await browser.close();
})();
