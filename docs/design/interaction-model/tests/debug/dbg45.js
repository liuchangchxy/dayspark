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

  // Pick the second occurrence of the weekly series, delete "future", count before/after.
  const setup = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    const days = [];
    for (let i = 0; i < 70; i++) {
      const d = new Date(e.startDt.getTime() + i * 86400000);
      const hits = window.Store.eventsOnDay(d).filter((x) => x.id === e.id);
      if (hits.length) days.push({ d: d.getTime(), s: hits[0].startDt.getTime() });
    }
    return { id: e.id, days };
  });
  console.log('occurrences found:', setup.days.length);

  const countIn = async (ms) => page.evaluate((t) => {
    const d = new Date(t);
    return window.Store.eventsOnDay(d).length;
  }, ms);

  const second = setup.days[1];
  const third = setup.days[2];
  const before = { second: await countIn(second.d), third: await countIn(third.d) };
  await page.evaluate(([id, ms]) => {
    window.App.go('detail', { type: 'event', id, occurrence: ms });
  }, [setup.id, second.s]);
  await page.waitForTimeout(280);
  await page.evaluate(() => {
    Array.from(document.querySelectorAll('#view button')).find((x) => /移到回收站|Move to Trash/.test(x.textContent)).click();
  });
  await page.waitForTimeout(200);
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.modal button, .sheet button')).pop();
    b.click();
  });
  await page.waitForTimeout(220);
  await page.evaluate(() => document.querySelector('.sheet [data-testid="scope-future"]').click());
  await page.waitForTimeout(320);
  const after = { second: await countIn(second.d), third: await countIn(third.d) };
  const until = await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule);
    return e && e.rrule.until ? e.rrule.until.getTime() : null;
  });
  console.log('future delete:', JSON.stringify({ before, after, until }));
  const undoBtn = await page.evaluate(() => !!document.querySelector('#toast .undo'));
  console.log('undo offered:', undoBtn);
  if (undoBtn) {
    await page.click('#toast .undo');
    await page.waitForTimeout(320);
    const restored = { second: await countIn(second.d), third: await countIn(third.d) };
    console.log('after undo:', JSON.stringify(restored), 'until:', await page.evaluate(() => {
      const e = window.Store.state.events.find((x) => x.rrule);
      return e && e.rrule.until ? e.rrule.until.getTime() : null;
    }));
  }

  // route after delete from detail
  console.log('route:', await page.evaluate(() => window.Store.state.route.name));
  await browser.close();
})();
