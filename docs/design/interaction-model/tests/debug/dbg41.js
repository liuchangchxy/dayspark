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

  // F2: composer inputs after occurrence edit
  const info = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const occ = new Date(e.startDt.getTime());
    window.App.go('detail', { type: 'event', id: e.id, occurrence: occ.getTime() });
    return { id: e.id };
  });
  await page.waitForTimeout(300);
  await page.evaluate(() => {
    Array.from(document.querySelectorAll('#view button')).find((x) => x.textContent.trim() === '编辑').click();
  });
  await page.waitForTimeout(250);
  console.log('scope sheet', await page.evaluate(() => document.querySelectorAll('.sheet').length));
  await page.evaluate(() => document.querySelector('.sheet [data-testid="scope-this"]').click());
  await page.waitForTimeout(300);
  const inputs = await page.evaluate(() => Array.from(document.querySelectorAll('#view input, #view select')).map((n) => ({ type: n.type, testid: n.dataset.testid, value: n.value })));
  console.log('composer inputs', JSON.stringify(inputs, null, 1));
  console.log('composer state', await page.evaluate(() => JSON.stringify(window.Store.state.composer)));

  // F6: mobile cancel
  const p2 = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p2.goto(URL);
  await p2.waitForFunction(() => window.__READY__ === true);
  const a = await p2.evaluate(() => {
    const al = window.Store.state.allocations.find((x) => window.Store.isAllocationLive(x));
    window.App.go('detail', { type: 'todo', id: al.todoId });
    return { id: al.id, todoId: al.todoId };
  });
  await p2.waitForTimeout(300);
  console.log('cancel btn?', await p2.evaluate(() => document.querySelectorAll('[data-testid="cancel-allocation"]').length));
  await p2.click('[data-testid="cancel-allocation"]');
  await p2.waitForTimeout(250);
  console.log('modal btns', await p2.$$eval('.modal button', (ns) => ns.map((n) => n.textContent.trim())));
  await p2.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('.modal button'));
    const ok = btns[btns.length - 1];
    ok.click();
  });
  await p2.waitForTimeout(300);
  console.log('state', await p2.evaluate((id) => { const al = window.Store.state.allocations.find((x) => x.id === id); return al && al.state; }, a.id));
  await browser.close();
})();
