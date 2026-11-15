const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
const WIDTHS = [320, 360, 390, 768, 900, 1024, 1180, 1440, 1920];
const ROUTES = ['action', 'calendar', 'todos', 'search', 'chat', 'tags', 'calendars', 'trash', 'settings', 'about', 'feedback', 'states'];

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  let bad = 0;
  for (const w of WIDTHS) {
    const page = await browser.newPage({ viewport: { width: w, height: 900 } });
    const errs = [];
    page.on('pageerror', (e) => errs.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
    await page.goto(URL);
    await page.waitForFunction(() => window.__READY__ === true);
    for (const r of ROUTES) {
      await page.evaluate((n) => window.App.go(n), r);
      await page.waitForTimeout(130);
      const ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      if (ov > 0) { console.log(`OVERFLOW ${w}px ${r}: ${ov}px`); bad++; }
    }
    for (const v of ['month', 'week', 'day']) {
      await page.evaluate((vv) => { window.Store.state.calendarView = vv; window.App.go('calendar'); }, v);
      await page.waitForTimeout(150);
      const ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      if (ov > 0) { console.log(`OVERFLOW ${w}px calendar-${v}: ${ov}px`); bad++; }
    }
    // occurrence detail + composer at this width
    await page.evaluate(() => {
      const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
      window.App.go('detail', { type: 'event', id: e.id, occurrence: e.startDt.getTime() });
    });
    await page.waitForTimeout(180);
    let ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    if (ov > 0) { console.log(`OVERFLOW ${w}px occurrence-detail: ${ov}px`); bad++; }
    await page.evaluate(() => window.App.openComposer('todo'));
    await page.waitForTimeout(200);
    ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    if (ov > 0) { console.log(`OVERFLOW ${w}px composer: ${ov}px`); bad++; }
    if (errs.length) { console.log(`ERRORS ${w}px:`, errs.slice(0, 2)); bad++; }
    await page.close();
  }

  // English locale sweep on the new/changed surfaces
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true);
  await page.evaluate(() => { window.Store.state.lang = 'en'; I18N.setLang('en'); window.App.render(); });
  await page.waitForTimeout(200);
  const seeds = await page.evaluate(() => {
    const s = window.Store.state;
    return [
      ...s.todos.map((t) => t.summary), ...s.events.map((e) => e.summary),
      ...s.tags.map((t) => t.name), ...s.calendars.map((c) => c.name),
    ];
  });
  const cjk = [];
  const surfaces = [];
  const scan = async (label) => {
    const texts = await page.evaluate(() => {
      const out = [];
      document.querySelectorAll('#view *, .rail-item, .capture-hint, .section-head, .sheet *, .modal *, .menu *').forEach((n) => {
        if (n.children.length) return;
        const s = (n.textContent || '').trim();
        if (s) out.push(s);
      });
      return out;
    });
    texts.forEach((s) => {
      if (/[一-鿿]/.test(s) && !seeds.some((seed) => s.includes(seed)) && !/^(灵|完成|删除)$/.test(s)) {
        cjk.push(`${label}: ${s.slice(0, 40)}`);
      }
    });
    surfaces.push(label);
  };
  for (const r of ['action', 'calendar', 'todos', 'settings', 'trash']) {
    await page.evaluate((n) => window.App.go(n), r);
    await page.waitForTimeout(180);
    await scan(r);
  }
  // occurrence detail + scope sheets in English
  await page.evaluate(() => {
    const e = window.Store.state.events.find((x) => x.rrule && !x.deletedAt);
    window.App.go('detail', { type: 'event', id: e.id, occurrence: e.startDt.getTime() });
  });
  await page.waitForTimeout(220);
  await scan('occurrence-detail');
  await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('#view button')).find((x) => x.textContent.trim() === 'Edit');
    if (b) b.click();
  });
  await page.waitForTimeout(220);
  await scan('scope-sheet');
  console.log('EN scans:', surfaces.join(', '));
  console.log('EN leftover CJK:', cjk.length ? cjk.slice(0, 12) : 'none');
  await browser.close();
  console.log(bad === 0 ? 'LAYOUT+EN OK' : `ISSUES: ${bad}`);
  if (bad) process.exit(1);
})();
