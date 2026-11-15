const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true);
  const heads = await page.$$eval('#view .section-head, #view .section-head *', (n) => n.slice(0, 12).map((x) => x.textContent.trim().slice(0, 40)));
  console.log('heads:', heads);
  const more = await page.evaluate(() => {
    const n = document.querySelector('[data-testid="overdue-more"]');
    return n ? n.textContent.trim() : null;
  });
  console.log('overdue-more:', more);
  const rows = await page.evaluate(() => document.querySelectorAll('#view .row').length);
  console.log('rows:', rows);
  await browser.close();
})();
