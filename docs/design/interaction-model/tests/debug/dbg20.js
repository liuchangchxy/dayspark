const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => window.Store.navigate('detail', { type: 'todo', id: 1 }));
  await p.waitForTimeout(250);
  console.log('facts', await p.evaluate(() => Array.from(document.querySelectorAll('.fact')).map((f) => f.querySelector('.k').textContent + ' / ' + f.querySelector('.v').textContent.slice(0, 24))));
  await p.screenshot({ path: '/tmp/g0-detail2.png' });
  await b.close();
})();
