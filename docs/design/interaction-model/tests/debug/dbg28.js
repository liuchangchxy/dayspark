const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(URL);
  await p.waitForFunction(() => window.__READY__);
  await p.evaluate(() => window.Store.setLang('en'));
  const routes = ['action', 'calendar', 'todos', 'search', 'chat', 'tags', 'calendars', 'trash', 'settings', 'about', 'feedback', 'states'];
  for (const r of routes) {
    await p.evaluate((x) => window.App.go(x), r);
    await p.waitForTimeout(160);
    const cjk = await p.evaluate(() => {
      const out = new Set();
      const walk = document.createTreeWalker(document.querySelector('#view'), NodeFilter.SHOW_TEXT);
      let n;
      while ((n = walk.nextNode())) {
        const s = n.textContent.trim();
        if (/[一-鿿]/.test(s) && s.length < 40) out.add(s);
      }
      document.querySelectorAll('#view [aria-label], #view [title], #view [placeholder]').forEach((e) => {
        ['aria-label', 'title', 'placeholder'].forEach((a) => {
          const v = e.getAttribute(a);
          if (v && /[一-鿿]/.test(v) && v.length < 40) out.add(a + '=' + v);
        });
      });
      return Array.from(out);
    });
    if (cjk.length) console.log(r, JSON.stringify(cjk));
  }
  // composer in English
  await p.evaluate(() => window.App.openComposer('todo', {}));
  await p.waitForTimeout(250);
  const c = await p.evaluate(() => {
    const out = new Set();
    const walk = document.createTreeWalker(document.querySelector('#view'), NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walk.nextNode())) { const s = n.textContent.trim(); if (/[一-鿿]/.test(s)) out.add(s); }
    return Array.from(out);
  });
  if (c.length) console.log('composer', JSON.stringify(c));
  await b.close();
})();
