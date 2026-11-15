const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true);
  const out = await page.evaluate(() => {
    const proj = window.Store.projection ? window.Store.projection(new Date()) : null;
    return { hasProj: !!proj, missed: proj ? proj.missedTaskInstances.length : null };
  });
  console.log('projection', out);
  const rows = await page.$$eval('[data-testid="overdue-more"]', (n) => n.map((x) => x.textContent.trim()));
  console.log('more control:', rows);
  if (rows.length) {
    await page.click('[data-testid="overdue-more"]');
    await page.waitForTimeout(200);
    const after = await page.evaluate(() => ({
      more: !!document.querySelector('[data-testid="overdue-more"]'),
      less: !!document.querySelector('[data-testid="overdue-less"]'),
      missedRows: document.querySelectorAll('[data-testid="action-row"], .row').length,
    }));
    console.log('after expand:', after);
    await page.click('[data-testid="overdue-less"]');
    await page.waitForTimeout(200);
    const back = await page.evaluate(() => ({
      more: !!document.querySelector('[data-testid="overdue-more"]'),
      less: !!document.querySelector('[data-testid="overdue-less"]'),
    }));
    console.log('after collapse:', back);
  }
  await browser.close();
})();
