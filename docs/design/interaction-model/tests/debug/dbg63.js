const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
  p.on('pageerror', (e) => console.log('PAGEERROR', e.message));
  await p.goto('file://' + path.resolve(__dirname, '..', '..', 'index.html'));
  await p.waitForFunction(() => window.__READY__ === true);
  await p.evaluate(() => document.querySelector('[data-testid="tab-more"]').click());
  await p.waitForTimeout(250);
  console.log('menu items:', await p.evaluate(() => Array.from(document.querySelectorAll('.menu button, .menu .mi')).map((n) => n.textContent.trim())));
  const items = await p.$$('.menu button');
  if (items.length) await items[items.length - 1].click();
  await p.waitForTimeout(300);
  console.log('after settings:', await p.evaluate(() => ({
    route: window.Store.state.route.name,
    hasManage: !!Array.from(document.querySelectorAll('.setting-row .t')).find((n) => /日历管理|Calendars/.test(n.textContent)),
    rawKey: document.body.textContent.includes('manageCalendars'),
  })));
  await b.close();
})();
