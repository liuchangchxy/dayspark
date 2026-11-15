const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  const html = await p.evaluate(() => {
    const rows = document.querySelectorAll('#view .row');
    return Array.from(rows).slice(1, 4).map(r => r.outerHTML.slice(0, 700));
  });
  console.log(html.join('\n\n'));
  const metaStyles = await p.evaluate(() => {
    const m = document.querySelector('#view .row-meta');
    if (!m) return 'no .row-meta';
    const cs = getComputedStyle(m);
    return { html: m.innerHTML, display: cs.display, color: cs.color, height: m.getBoundingClientRect().height, fs: cs.fontSize };
  });
  console.log(JSON.stringify(metaStyles, null, 2));
  await b.close();
})();
