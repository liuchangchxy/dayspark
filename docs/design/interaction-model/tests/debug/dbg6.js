const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  await p.goto(URL); await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => App.go('todos')); await p.waitForTimeout(250);
  const info = await p.evaluate(() => {
    const row = document.querySelector('.todo-row');
    const m = row.querySelector('.row-meta');
    const title = row.querySelector('.row-title');
    return {
      rowHTML: row.outerHTML.slice(0, 1600),
      titleCS: (() => { const c = getComputedStyle(title); return { td: c.textDecoration, bs: c.boxShadow, outline: c.outline, border: c.borderTop, bg: c.backgroundImage, before: getComputedStyle(title, '::before').content, beforeBg: getComputedStyle(title, '::before').backgroundColor }; })(),
      metaCS: (() => { const c = getComputedStyle(m); return { bs: c.boxShadow, border: c.borderTop, bg: c.backgroundImage, before: getComputedStyle(m, '::before').content, beforeBg: getComputedStyle(m, '::before').backgroundColor, beforeH: getComputedStyle(m, '::before').height }; })(),
    };
  });
  console.log(JSON.stringify(info, null, 2));
  await b.close();
})();
