const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('calendar'));
  await p.waitForTimeout(600);
  console.log('scrollTop', await p.evaluate(() => { const s = document.querySelector('[data-testid="time-scroll"]'); return s ? { top: s.scrollTop, h: s.scrollHeight, ch: s.clientHeight, scrolled: s.dataset.scrolled } : null; }));
  await p.screenshot({ path: '/tmp/g0-cal2.png' });
  await b.close();
})();
