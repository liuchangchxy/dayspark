const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(200);
  const info = await p.evaluate(() => {
    const wrap = document.querySelector('.swipe-wrap');
    const row = wrap.querySelector('.todo-row');
    const bg = wrap.querySelector('.swipe-bg');
    const r = (n) => { const x = n.getBoundingClientRect(); return {x:x.x,y:x.y,w:x.width,h:x.height}; };
    const out = { wrap: r(wrap), row: r(row), bg: r(bg), bgHtml: bg.innerHTML };
    // element at the red line point
    const el = document.elementFromPoint(700, row.getBoundingClientRect().y + row.getBoundingClientRect().height/2);
    out.atPoint = el ? el.tagName + '.' + el.className : null;
    return out;
  });
  console.log(JSON.stringify(info, null, 2));
  await b.close();
})();
