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
    const wrap = document.querySelector('.swipe-wrap');
    const row = wrap.querySelector('.todo-row');
    const rr = row.getBoundingClientRect();
    const probes = [];
    for (let dy = -2; dy <= 6; dy++) {
      const el = document.elementFromPoint(700, rr.y + dy);
      probes.push({ dy, el: el ? el.tagName + '.' + el.className : null });
    }
    const left = wrap.querySelector('.swipe-bg .left');
    const right = wrap.querySelector('.swipe-bg .right');
    const cs = (n) => { const c = getComputedStyle(n); const r = n.getBoundingClientRect(); return {color:c.color, pos:c.position, rect:[r.x,r.y,r.width,r.height], z:c.zIndex, op:c.opacity}; };
    return { probes, left: cs(left), right: cs(right), rowBg: getComputedStyle(row).backgroundColor, wrapBg: getComputedStyle(wrap).backgroundColor };
  });
  console.log(JSON.stringify(info, null, 2));
  await b.close();
})();
