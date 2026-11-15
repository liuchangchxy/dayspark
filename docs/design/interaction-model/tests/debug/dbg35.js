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
    const d = new Date();
    d.setDate(d.getDate() - 12);
    window.Store.createTodo({
      summary: '漏掉的重复任务测试',
      recurrence: { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' },
      dueDate: new Date(d.getFullYear(), d.getMonth(), d.getDate(), 9),
    });
    window.App.go('action');
  });
  await page.waitForTimeout(300);
  const before = await page.evaluate(() => ({
    more: (document.querySelector('[data-testid="overdue-more"]') || {}).textContent,
    missedRows: document.querySelectorAll('[data-testid="action-instance"]').length,
    head: Array.from(document.querySelectorAll('#view .section-head')).map((n) => n.textContent.trim()),
  }));
  console.log('collapsed:', JSON.stringify(before));
  await page.click('[data-testid="overdue-more"]');
  await page.waitForTimeout(250);
  const after = await page.evaluate(() => ({
    more: !!document.querySelector('[data-testid="overdue-more"]'),
    less: !!document.querySelector('[data-testid="overdue-less"]'),
    missedRows: document.querySelectorAll('[data-testid="action-instance"]').length,
  }));
  console.log('expanded:', JSON.stringify(after));
  await page.click('[data-testid="overdue-less"]');
  await page.waitForTimeout(250);
  const back = await page.evaluate(() => ({
    more: !!document.querySelector('[data-testid="overdue-more"]'),
    missedRows: document.querySelectorAll('[data-testid="action-instance"]').length,
  }));
  console.log('collapsed again:', JSON.stringify(back));
  await page.screenshot({ path: '/tmp/overdue-expand.png' });
  await browser.close();
})();
