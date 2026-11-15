const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  p.on('pageerror', (e) => console.log('PAGEERROR', e.message));
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);

  // Escape path
  await p.evaluate(() => App.go('todos'));
  await p.waitForTimeout(150);
  await p.click('[data-testid="todos-create"]');
  await p.waitForTimeout(200);
  console.log('active', await p.evaluate(() => document.activeElement.tagName + ':' + (document.activeElement.dataset.testid || '')));
  await p.keyboard.press('Escape');
  await p.waitForTimeout(250);
  console.log('confirm?', await p.evaluate(() => !!document.querySelector('.modal.confirm')), 'composer?', await p.evaluate(() => !!document.querySelector('[data-testid="composer"]')));

  // reschedule
  await p.evaluate(() => App.go('calendar'));
  await p.waitForTimeout(200);
  await p.evaluate(() => document.querySelector('[data-testid="cal-view-day"]').click());
  await p.waitForTimeout(250);
  await p.evaluate(() => {
    const block = document.querySelector('[data-testid="alloc-block"]');
    block.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 600, clientY: 500 }));
  });
  await p.waitForTimeout(150);
  console.log('menu', await p.evaluate(() => document.querySelector('.menu') ? document.querySelector('.menu').textContent : null));
  await p.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('.menu button')).find((b) => b.textContent.includes('改期'));
    btn.click();
  });
  await p.waitForTimeout(200);
  console.log('modal inputs', await p.evaluate(() => Array.from(document.querySelectorAll('.modal input')).map((i) => i.type + '=' + i.value)));
  console.log('modal buttons', await p.evaluate(() => Array.from(document.querySelectorAll('.modal .btn')).map((i) => i.className + '=' + i.textContent)));
  await b.close();
})();
