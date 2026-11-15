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

  const id = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    return e.id;
  });
  // Split an occurrence, then delete the copy, then undo the delete.
  const r = await page.evaluate((eid) => {
    const e = window.Store.state.events.find((x) => x.id === eid);
    const anchor = new Date(e.startDt.getTime());
    const split = window.Store.splitEventOccurrence(eid, anchor.getTime(), { summary: '拆分副本' });
    const series = window.Store.eventById(eid);
    return {
      seriesEx: (series.exdates || []).length,
      copyId: split.copy.id,
      n: window.Store.state.events.length,
    };
  }, id);
  console.log('after split', r);
  // delete the copy via EventOps (single event path)
  const d = await page.evaluate((copyId) => {
    window.App.go('detail', { type: 'event', id: copyId });
    return copyId;
  }, r.copyId);
  await page.waitForTimeout(300);
  await page.evaluate(() => {
    Array.from(document.querySelectorAll('#view button')).find((x) => /移到回收站|Move to Trash/.test(x.textContent)).click();
  });
  await page.waitForTimeout(220);
  await page.evaluate(() => { Array.from(document.querySelectorAll('.modal button')).pop().click(); });
  await page.waitForTimeout(320);
  console.log('after copy delete', await page.evaluate((cid) => {
    const c = window.Store.state.events.find((x) => x.id === cid);
    return { deleted: !!(c && c.deletedAt), route: window.Store.state.route.name, n: window.Store.state.events.length };
  }, d));
  const hasUndo = await page.evaluate(() => !!document.querySelector('#toast .undo'));
  if (hasUndo) {
    await page.click('#toast .undo');
    await page.waitForTimeout(300);
  }
  console.log('after undo', await page.evaluate((cid) => {
    const c = window.Store.state.events.find((x) => x.id === cid);
    return { deleted: !!(c && c.deletedAt), n: window.Store.state.events.length };
  }, d));

  // rapid capture
  await page.evaluate(() => window.App.go('action'));
  await page.waitForTimeout(250);
  const before = await page.evaluate(() => window.Store.state.todos.length);
  await page.click('[data-testid="action-capture"]');
  for (const s of ['快一', '快二', '快三']) {
    await page.keyboard.type(s);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(120);
  }
  console.log('rapid capture', before, '->', await page.evaluate(() => window.Store.state.todos.length), 'focus', await page.evaluate(() => document.activeElement.dataset.testid));
  // duplicates?
  console.log('dupes', await page.evaluate(() => {
    const names = window.Store.state.todos.map((t) => t.summary);
    return names.filter((n) => ['快一', '快二', '快三'].includes(n)).length;
  }));
  await browser.close();
})();
