const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  p.on('pageerror', (e) => console.log('ERR', e.message));
  await p.goto('file://' + path.resolve(__dirname, '..', '..', 'index.html'));
  await p.waitForFunction(() => window.__READY__ === true);
  await p.evaluate(() => window.App.go('settings'));
  await p.waitForTimeout(400);
  console.log(await p.evaluate(() => ({
    desc: !!document.querySelector('.group-desc'),
    descText: (document.querySelector('.group-desc') || {}).textContent,
    groups: Array.from(document.querySelectorAll('h2')).map((n) => n.textContent),
    mergeRow: Array.from(document.querySelectorAll('.setting-row, .list-row')).map((n) => n.textContent.trim()).filter((t) => /备份|合并|Backup/.test(t)),
  })));
  await b.close();
})();
