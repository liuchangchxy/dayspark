const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true);
  const id = await page.evaluate(() => {
    const a = window.Store.state.allocations.find((x) => window.Store.isAllocationLive(x));
    window.App.go('detail', { type: 'todo', id: a.todoId });
    return a.todoId;
  });
  await page.waitForTimeout(300);
  const sizes = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('#view button, .sheet button, .modal button').forEach((n) => {
      if (n.offsetParent === null) return;
      const r = n.getBoundingClientRect();
      if (!r.width || !r.height) return;
      out.push({ t: (n.textContent || n.getAttribute('aria-label') || '').trim().slice(0, 16), w: Math.round(r.width), h: Math.round(r.height) });
    });
    return out;
  });
  console.log('detail buttons under 44:', sizes.filter((s) => s.w < 44 || s.h < 44));
  // value rows
  const vals = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('#view .fact .v[role="button"]').forEach((n) => {
      const r = n.getBoundingClientRect();
      out.push({ t: n.textContent.trim().slice(0, 14), w: Math.round(r.width), h: Math.round(r.height) });
    });
    return out;
  });
  console.log('value targets:', vals);
  await browser.close();
})();
