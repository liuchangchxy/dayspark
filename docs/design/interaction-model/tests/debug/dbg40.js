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

  const r = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const d = new Date(e.startDt.getTime());
    const occ = new Date(d.getFullYear(), d.getMonth(), d.getDate(), e.startDt.getHours(), e.startDt.getMinutes());
    window.App.go('detail', { type: 'event', id: e.id, occurrence: occ.getTime() });
    return { id: e.id };
  });
  await page.waitForTimeout(300);
  const probe = await page.evaluate(() => {
    try {
      window.EventOps.editEvent({ id: 5, isOccurrence: true, occurrenceAnchor: new Date() });
      return { sheets: document.querySelectorAll('.sheet').length };
    } catch (e) { return { err: String(e), stack: e.stack }; }
  });
  console.log('direct editEvent', probe);

  // F11 check
  await page.evaluate(() => { window.UI.closeAll(); });
  const f11 = await page.evaluate(() => {
    const now = new Date();
    const todo = window.Store.state.todos.find((t) => !t.recurrence && !t.parentId && t.status === 'NEEDS-ACTION' && !t.deletedAt);
    const a = window.Store.createAllocation({ todoId: todo.id, startAt: new Date(now.getTime() - 20 * 60000), endAt: new Date(now.getTime() + 40 * 60000) });
    window.App.go('action');
    return { todoId: todo.id, allocId: a.id };
  });
  await page.waitForTimeout(300);
  console.log('now alloc before', await page.evaluate(() => document.querySelectorAll('[data-testid="action-allocation"]').length));
  const proj = await page.evaluate(() => {
    const p = window.Store.actionProjection();
    return { allocs: p.allocations.length, kinds: p.allocations.map((x) => x.allocation.id) };
  });
  console.log('projection', proj);
  await browser.close();
})();
