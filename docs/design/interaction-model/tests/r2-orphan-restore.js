const L = require('./r2-lib');
const { launch, newPage, settle, shot, DESKTOP } = L;
async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    await page.evaluate(() => {
      const S = window.Store;
      S.softDeleteTodo(19);
      window.Store.purgeTodo(19);
    });
    await settle(page, 300);
    await L.go(page, 'trash');
    await settle(page, 300);
    const row = page.locator('[data-testid="trash-row"]', { hasText: '收集各组数据' }).first();
    await row.locator('[data-testid="trash-restore"]').click();
    await settle(page, 400);
    await shot(page, 'ORPH-01-after-restore-child');
    await L.go(page, 'todos');
    await settle(page, 350);
    await L.clickText(page, '.chip-btn', '全部');
    await settle(page, 350);
    const tiles = await L.texts(page, '[data-testid="todo-tile"]');
    const child = await page.evaluate(() => {
      const S = window.Store;
      const c = S.state.todos.find((t) => t.id === 20);
      return { id: c.id, parentId: c.parentId, deleted: c.deletedAt, parentExists: !!S.state.todos.find((t) => t.id === c.parentId) };
    });
    console.log('restored child:', child);
    console.log('visible in All?', tiles.some((x) => /收集各组数据/.test(x)));
    await shot(page, 'ORPH-02-child-not-visible');
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
