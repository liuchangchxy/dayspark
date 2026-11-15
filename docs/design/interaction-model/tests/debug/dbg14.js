const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  p.on('pageerror', e => console.log('PAGEERROR', e.message, '\n', e.stack));
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => {
    try { App.openComposer('todo', { dueDate: new Date() }); } catch (e) { console.log('THROWN', e.stack); }
  });
  await p.waitForTimeout(300);
  await b.close();
})();
