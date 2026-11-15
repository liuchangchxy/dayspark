const L = require('./r2-lib');
const { launch, newPage, settle, shot, DESKTOP } = L;
async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    await L.go(page, 'todos');
    await settle(page, 300);
    await L.clickText(page, '.chip-btn', '全部');
    await settle(page, 300);
    await page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).first().click();
    await settle(page, 350);
    console.log('detail:', (await L.text(page, '#view')).slice(0, 180));
    await L.clickText(page, '#view button', '标记完成');
    await settle(page, 450);
    await shot(page, 'RECD-01-detail-after-complete');
    const info = await page.evaluate(() => {
      const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
      return { states: JSON.parse(JSON.stringify(t.occurrenceStates)), status: t.status, toast: document.querySelector('.toast') && document.querySelector('.toast').textContent, route: window.Store.state.route };
    });
    console.log('after:', info);
    await L.go(page, 'todos');
    await settle(page, 300);
    await L.clickText(page, '.chip-btn', '全部');
    await settle(page, 350);
    await shot(page, 'RECD-02-list-after-detail-complete');
    const tiles = await L.texts(page, '[data-testid="todo-tile"]');
    console.log('reading tile still listed?', tiles.filter((x) => /读 20 页/.test(x)));
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
