const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(path.resolve(__dirname, '..'), 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(250);
  const info = await p.evaluate(() => {
    const bad = [];
    const isRed = (c) => {
      const m = /rgba?\((\d+), (\d+), (\d+)/.exec(c || '');
      if (!m) return false;
      const [r, g, bl] = [+m[1], +m[2], +m[3]];
      return r > 120 && r > g + 40 && r > bl + 40;
    };
    document.querySelectorAll('*').forEach((n) => {
      const c = getComputedStyle(n);
      const r = n.getBoundingClientRect();
      if (r.width < 200) return;
      if (isRed(c.borderBottomColor) && parseFloat(c.borderBottomWidth) > 0) bad.push(['borderBottom', n.tagName, String(n.className).slice(0,40), c.borderBottomWidth, c.borderBottomColor, Math.round(r.y + r.height)]);
      if (isRed(c.borderTopColor) && parseFloat(c.borderTopWidth) > 0) bad.push(['borderTop', n.tagName, String(n.className).slice(0,40), c.borderTopWidth, c.borderTopColor, Math.round(r.y)]);
      if (isRed(c.backgroundColor)) bad.push(['bg', n.tagName, String(n.className).slice(0,40), c.backgroundColor, Math.round(r.y), Math.round(r.height)]);
      if (isRed(c.outlineColor) && parseFloat(c.outlineWidth) > 0 && c.outlineStyle !== 'none') bad.push(['outline', n.tagName, String(n.className).slice(0,40), c.outlineWidth, c.outlineColor, Math.round(r.y)]);
    });
    return bad;
  });
  console.log(JSON.stringify(info, null, 1));
  await b.close();
})();
