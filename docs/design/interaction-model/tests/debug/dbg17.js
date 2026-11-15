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

  // six things
  await p.evaluate(() => App.go('todos'));
  await p.waitForTimeout(200);
  for (const title of ['补充一', '补充二', '补充三']) {
    await p.fill('[data-testid="todo-quick-add"]', title);
    await p.press('[data-testid="todo-quick-add"]', 'Enter');
    await p.waitForTimeout(180);
  }
  console.log('dated today', await p.evaluate(() => {
    const today = window.U.startOfDay(window.U.now());
    return window.Store.state.todos.filter((t) => !t.deletedAt && t.status === 'NEEDS-ACTION' && t.dueDate && window.U.sameDay(t.dueDate, today) && !t.recurrence && !t.parentId).map((t) => t.summary);
  }));
  await p.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.chip-btn')).find((x) => x.textContent.trim() === '六件事');
    b.click();
  });
  await p.waitForTimeout(250);
  console.log('sixThings', await p.evaluate(() => window.Store.state.sixThings));
  console.log('buttons with 更多', await p.evaluate(() => Array.from(document.querySelectorAll('button')).map((b) => b.textContent.trim()).filter((x) => /更多|收起/.test(x))));

  // recurring
  await p.evaluate(() => App.go('action'));
  await p.waitForTimeout(250);
  console.log('instance rows', await p.evaluate(() => Array.from(document.querySelectorAll('[data-testid="action-instance"]')).map((r) => ({ text: r.textContent.slice(0, 30), hasBox: !!r.querySelector('.checkbox') }))));
  await p.evaluate(() => {
    const row = Array.from(document.querySelectorAll('[data-testid="action-instance"]')).find((r) => !r.textContent.includes('遗漏'));
    const box = row.querySelector('.checkbox');
    box.click();
  });
  await p.waitForTimeout(300);
  console.log('states', await p.evaluate(() => window.Store.state.todos.filter((t) => t.recurrence).map((t) => ({ s: t.summary, st: t.occurrenceStates }))));
  await b.close();
})();
