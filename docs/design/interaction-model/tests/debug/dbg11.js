const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(250);
  const info = await p.evaluate(() => {
    const out = [];
    const warm = 'rgb(194, 65, 12)';
    document.querySelectorAll('*').forEach((n) => {
      for (const pe of ['::before', '::after']) {
        const c = getComputedStyle(n, pe);
        if (c.content === 'none') continue;
        if (c.backgroundColor === warm || c.borderTopColor === warm) {
          const r = n.getBoundingClientRect();
          out.push({ sel: n.tagName + '.' + String(n.className).slice(0,30), pe, bg: c.backgroundColor, h: c.height, pos: c.position, rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)], top: c.top, display: c.display });
        }
      }
    });
    return out;
  });
  console.log(JSON.stringify(info, null, 1));
  await b.close();
})();
