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
    await L.clickText(page, '.toolbar .chip-btn, .todo-toolbar .chip-btn', '选择');
    await settle(page, 300);
    const tile = page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).first();
    await tile.locator('.selbox, [role="checkbox"]').first().click();
    await settle(page, 300);
    await shot(page, 'BATCH-01-selected');
    console.log('toast after select:', await page.evaluate(() => { const t = document.querySelector('.toast'); return t && t.textContent; }));
    console.log('selectbar:', await L.text(page, '.selectbar'));
    const before = await page.evaluate(() => { const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》'); return JSON.parse(JSON.stringify(t.occurrenceStates)); });
    await L.clickText(page, '.selectbar button', '完成');
    await settle(page, 500);
    await shot(page, 'BATCH-02-after-complete');
    const after = await page.evaluate(() => {
      const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
      return { states: JSON.parse(JSON.stringify(t.occurrenceStates)), status: t.status, toast: document.querySelector('.toast') && document.querySelector('.toast').textContent, selectbar: (document.querySelector('.selectbar') || {}).textContent };
    });
    console.log('before:', before);
    console.log('after:', after);
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
