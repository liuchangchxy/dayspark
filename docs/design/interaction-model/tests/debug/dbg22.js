const path = require('path');
const { chromium } = require('playwright-core');
const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', '..', 'index.html');
(async () => {
  const b = await chromium.launch({ executablePath: CHROME });
  for (const vp of [{ width: 1440, height: 900 }, { width: 1200, height: 860 }]) {
    const p = await b.newPage({ viewport: vp });
    await p.goto(URL);
    await p.waitForFunction(() => window.__READY__);
    await p.evaluate(() => window.Store.navigate('detail', { type: 'todo', id: 1 }));
    await p.waitForTimeout(250);
    await p.evaluate(() => {
      const btns = Array.from(document.querySelectorAll('.detail-foot button, .detail-actions button, button'));
      const del = btns.find((x) => x.textContent.includes('移到回收站') || x.textContent.includes('Move to trash'));
      del.click();
    });
    await p.waitForTimeout(200);
    await p.evaluate(() => {
      const ok = document.querySelector('.modal.confirm .btn.danger');
      ok.click();
    });
    await p.waitForTimeout(350);
    console.log(vp.width, await p.evaluate(() => ({ route: window.Store.state.route.name, params: window.Store.state.route.params, hasDetail: !!document.querySelector('[data-testid="todo-detail"]'), text: (document.querySelector('#view .detail-title') || {}).textContent })));
    await p.screenshot({ path: `/tmp/g0-del-${vp.width}.png` });
    await p.close();
  }
  await b.close();
})();
