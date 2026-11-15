const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true);
  await page.evaluate(() => {
    const base = new Date();
    for (let i = 0; i < 12; i++) {
      const d = new Date(base.getFullYear(), base.getMonth(), base.getDate() + i, 17);
      window.Store.createTodo({ summary: '截止测试 ' + (i + 1), dueDate: d });
    }
    window.Store.state.calendarView = 'week';
    window.App.go('calendar');
  });
  await page.waitForTimeout(300);
  const collapsed = await page.evaluate(() => ({
    chips: document.querySelectorAll('.deadline-lane .deadline-chip:not(.more)').length,
    more: (document.querySelector('[data-testid="deadline-more"]') || {}).textContent,
  }));
  console.log('collapsed:', JSON.stringify(collapsed));
  await page.click('[data-testid="deadline-more"]');
  await page.waitForTimeout(250);
  const expanded = await page.evaluate(() => ({
    chips: document.querySelectorAll('.deadline-lane .deadline-chip:not(.more)').length,
    less: (document.querySelector('[data-testid="deadline-less"]') || {}).textContent,
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
  }));
  console.log('expanded:', JSON.stringify(expanded));
  await page.click('[data-testid="deadline-less"]');
  await page.waitForTimeout(250);
  console.log('collapsed again:', await page.evaluate(() => document.querySelectorAll('.deadline-lane .deadline-chip:not(.more)').length));
  await page.screenshot({ path: '/tmp/deadline-expand.png', fullPage: false });
  await browser.close();
})();
