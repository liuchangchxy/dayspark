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

  // repeat options
  await p.evaluate(() => App.go('todos'));
  await p.waitForTimeout(150);
  await p.click('[data-testid="todos-create"]');
  await p.waitForTimeout(200);
  await p.click('[data-testid="composer-more"]');
  await p.waitForTimeout(150);
  await p.click('[data-testid="composer-repeat"]');
  await p.waitForTimeout(250);
  console.log('repeat options', await p.evaluate(() => Array.from(document.querySelectorAll('[data-testid="repeat-option"]')).map((b) => b.textContent.trim())));

  // selection bar
  await p.evaluate(() => { window.App.back(); });
  await p.waitForTimeout(200);
  await p.evaluate(() => { window.App.go('todos'); window.__todoHelpers.setView({ kind: 'all', day: null }); });
  await p.waitForTimeout(250);
  await p.evaluate(() => { const b = Array.from(document.querySelectorAll('button')).find((x) => x.textContent.trim() === '选择'); b.click(); });
  await p.waitForTimeout(250);
  console.log('selectbar', await p.evaluate(() => document.querySelector('.selectbar') ? document.querySelector('.selectbar').textContent : null));
  console.log('selectbar buttons', await p.evaluate(() => Array.from(document.querySelectorAll('.selectbar button')).map((b) => b.textContent + '|' + b.disabled)));

  // hide completed
  await p.evaluate(() => App.go('settings'));
  await p.waitForTimeout(250);
  console.log('hide done switch', await p.evaluate(() => { const s = document.querySelector('[data-testid="setting-hide-done"]'); return s ? s.getAttribute('aria-checked') : null; }));
  await p.click('[data-testid="setting-hide-done"]');
  await p.waitForTimeout(200);
  console.log('after toggle', await p.evaluate(() => window.Store.state.hideCompleted));
  await p.evaluate(() => { window.Store.state.hideCompleted = false; window.App.render(); });
  await p.waitForTimeout(200);
  console.log('after direct reset', await p.evaluate(() => window.Store.state.hideCompleted));
  await b.close();
})();
