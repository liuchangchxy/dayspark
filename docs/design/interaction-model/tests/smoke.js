/* Boot the prototype in a real browser, click through the primary surfaces,
   and report console errors, layout overflow, and dead controls.
   Usage: node tests/smoke.js [--headed] */
const path = require('path');
const { chromium } = require('playwright-core');

const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', 'index.html');

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME, headless: !process.argv.includes('--headed') });
  const results = [];
  const fail = (msg) => results.push({ ok: false, msg });
  const ok = (msg) => results.push({ ok: true, msg });

  for (const viewport of [{ name: 'desktop', width: 1440, height: 900 }, { name: 'mobile', width: 390, height: 844 }]) {
    const page = await browser.newPage({ viewport: { width: viewport.width, height: viewport.height } });
    const errors = [];
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    await page.goto(URL);
    await page.waitForFunction(() => window.__READY__ === true, { timeout: 5000 });
    ok(`${viewport.name}: booted`);

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    if (overflow > 0) fail(`${viewport.name}: horizontal overflow ${overflow}px`); else ok(`${viewport.name}: no horizontal overflow`);

    // every visible button must have a non-empty accessible name
    const unnamed = await page.evaluate(() => {
      const bad = [];
      document.querySelectorAll('button').forEach((b) => {
        if (b.offsetParent === null) return;
        const name = (b.getAttribute('aria-label') || b.textContent || '').trim();
        if (!name) bad.push(b.outerHTML.slice(0, 120));
      });
      return bad;
    });
    if (unnamed.length) fail(`${viewport.name}: ${unnamed.length} unnamed buttons: ${unnamed.slice(0, 3).join(' | ')}`);
    else ok(`${viewport.name}: all buttons named`);

    // touch targets on mobile
    if (viewport.name === 'mobile') {
      const small = await page.evaluate(() => {
        const bad = [];
        document.querySelectorAll('button, a[href], input, select, textarea').forEach((n) => {
          if (n.offsetParent === null) return;
          const r = n.getBoundingClientRect();
          if (r.width === 0 || r.height === 0) return;
          if (r.width < 24 || r.height < 24) bad.push(`${n.tagName}.${n.className} ${Math.round(r.width)}x${Math.round(r.height)}`);
        });
        return bad;
      });
      if (small.length) fail(`mobile: ${small.length} targets under 24px: ${small.slice(0, 4).join(' | ')}`);
      else ok('mobile: targets >= 24px');
    }

    // navigate every route
    const routes = ['action', 'calendar', 'todos', 'search', 'chat', 'tags', 'calendars', 'trash', 'settings'];
    for (const r of routes) {
      await page.evaluate((name) => window.App.go(name), r);
      await page.waitForTimeout(120);
      const rendered = await page.evaluate(() => !!document.querySelector('#view .page, #view .detail, #view .composer, #view .chat'));
      if (!rendered) fail(`${viewport.name}: ${r} rendered nothing`);
      const ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      if (ov > 0) fail(`${viewport.name}: ${r} overflows ${ov}px`);
    }
    ok(`${viewport.name}: ${routes.length} routes reachable`);

    if (errors.length) fail(`${viewport.name}: console errors: ${errors.slice(0, 4).join(' | ')}`);
    else ok(`${viewport.name}: no console errors`);
    await page.close();
  }

  await browser.close();
  let failed = 0;
  results.forEach((r) => {
    console.log((r.ok ? 'PASS ' : 'FAIL ') + r.msg);
    if (!r.ok) failed++;
  });
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
