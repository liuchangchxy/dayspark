const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(250);
  const buf = await p.screenshot({ clip: { x: 700, y: 294, width: 1, height: 12 } });
  require('fs').writeFileSync('/tmp/col.png', buf);
  // decode with zlib via pngjs-less approach: use sharp? try canvas in page
  const colors = await p.evaluate(async () => {
    const out = [];
    for (const y of [294,295,296,297,298,299,300,301,302,303]) {
      out.push({ y });
    }
    return out;
  });
  console.log('wrote /tmp/col.png');
  await b.close();
})();
