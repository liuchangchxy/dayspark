const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 320, height: 720 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  for (const r of ['action', 'todos', 'calendar', 'settings', 'chat']) {
    await p.evaluate((x) => window.App.go(x), r);
    await p.waitForTimeout(180);
    const ov = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    console.log(r, 'overflow', ov);
  }
  // tab order sanity: first Tab focuses something visible
  await p.evaluate(() => window.App.go('todos'));
  await p.waitForTimeout(150);
  await p.keyboard.press('Tab');
  console.log('first tab focus', await p.evaluate(() => { const a = document.activeElement; return a ? a.tagName + ':' + (a.getAttribute('aria-label') || a.textContent.trim().slice(0, 20)) : null; }));
  await b.close();
})();
