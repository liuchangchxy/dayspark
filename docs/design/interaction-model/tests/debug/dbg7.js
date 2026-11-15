const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(250);
  const buf = await p.screenshot({ clip: { x: 400, y: 290, width: 4, height: 20 } });
  // decode PNG roughly via sharp? not available. Instead use element probing with document.elementsFromPoint
  const probes = await p.evaluate(() => {
    const out = [];
    for (let y = 296; y <= 310; y++) {
      const els = document.elementsFromPoint(700, y).map(e => e.tagName + '.' + String(e.className).slice(0, 30));
      out.push({ y, els });
    }
    return out;
  });
  console.log(JSON.stringify(probes, null, 1));
  await b.close();
})();
