const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(250);
  const rr = await p.evaluate(() => { const r = document.querySelector('.todo-row').getBoundingClientRect(); return [r.x, r.y, r.width, r.height]; });
  await p.screenshot({ path: '/tmp/g0-row.png', clip: { x: rr[0], y: rr[1] - 4, width: rr[2], height: rr[3] + 8 } });
  const px = await p.evaluate(() => {
    const all = [];
    document.querySelectorAll('*').forEach((n) => {
      const c = getComputedStyle(n);
      const r = n.getBoundingClientRect();
      if (r.height > 0 && r.height < 4 && r.width > 500) {
        all.push({ tag: n.tagName, cls: String(n.className).slice(0, 60), h: r.height, y: r.y, bg: c.backgroundColor, bb: c.borderBottomColor, bt: c.borderTopColor, bw: c.borderTopWidth });
      }
    });
    return all.slice(0, 20);
  });
  console.log(JSON.stringify(px, null, 2));
  await b.close();
})();
