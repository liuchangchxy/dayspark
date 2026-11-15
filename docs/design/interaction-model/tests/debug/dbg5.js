const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(250);
  const info = await p.evaluate(() => {
    const row = document.querySelector('.todo-row');
    const out = [];
    row.querySelectorAll('*').forEach((n) => {
      const c = getComputedStyle(n);
      const r = n.getBoundingClientRect();
      if (r.width > 300) out.push({ tag: n.tagName, cls: String(n.className).slice(0,40), w: Math.round(r.width), h: Math.round(r.height), y: Math.round(r.y), td: c.textDecorationLine, border: c.borderTopWidth + ' ' + c.borderTopColor, bg: c.backgroundColor });
    });
    return out;
  });
  console.log(JSON.stringify(info, null, 2));
  // hide bg and shoot
  await p.evaluate(() => document.querySelectorAll('.swipe-bg').forEach(n => n.style.display = 'none'));
  const rr = await p.evaluate(() => { const r = document.querySelector('.todo-row').getBoundingClientRect(); return [r.x, r.y, r.width, r.height]; });
  await p.screenshot({ path: '/tmp/g0-row-nobg.png', clip: { x: rr[0], y: rr[1] - 4, width: rr[2], height: rr[3] + 8 } });
  await b.close();
})();
