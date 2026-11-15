const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => window.App.go('todos'));
  await p.waitForTimeout(200);
  // Are the last row and the FAB overlapping?
  const info = await p.evaluate(() => {
    const fab = document.querySelector('[data-testid="todos-create"]');
    const rows = Array.from(document.querySelectorAll('[data-testid="todo-tile"]'));
    const last = rows[rows.length - 1].getBoundingClientRect();
    const f = fab.getBoundingClientRect();
    const content = document.querySelector('.page-scroll');
    return { fab: { t: Math.round(f.top), b: Math.round(f.bottom), l: Math.round(f.left) }, last: { t: Math.round(last.top), b: Math.round(last.bottom) }, scrollBottom: content.scrollTop + content.clientHeight, scrollH: content.scrollHeight, canScroll: content.scrollHeight > content.clientHeight };
  });
  console.log(info);
  await p.evaluate(() => { const c = document.querySelector('.page-scroll'); c.scrollTop = c.scrollHeight; });
  await p.waitForTimeout(200);
  await p.screenshot({ path: '/tmp/g0m-todos-bottom.png' });
  const info2 = await p.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('[data-testid="todo-tile"]'));
    const last = rows[rows.length - 1].getBoundingClientRect();
    const fab = document.querySelector('[data-testid="todos-create"]').getBoundingClientRect();
    return { lastBottom: Math.round(last.bottom), fabTop: Math.round(fab.top), navTop: Math.round(document.querySelector('#bottomnav').getBoundingClientRect().top) };
  });
  console.log(info2);
  await b.close();
})();
