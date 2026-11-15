const L = require('./r2-lib');
const { launch, newPage, settle, shot, state, DESKTOP } = L;
async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    const info = await page.evaluate(() => {
      const S = window.Store;
      const parent = S.state.todos.find((t) => S.state.todos.some((c) => c.parentId === t.id) && !t.deletedAt && t.parentId == null);
      const kids = S.state.todos.filter((c) => c.parentId === parent.id);
      return { parent: { id: parent.id, s: parent.summary }, kids: kids.map((k) => ({ id: k.id, s: k.summary, deleted: k.deletedAt })) };
    });
    console.log('parent+children:', info);
    // soft-delete parent through store
    await page.evaluate((pid) => { window.Store.softDeleteTodo(pid); }, info.parent.id);
    await settle(page, 300);
    const afterDel = await page.evaluate((pid) => {
      const S = window.Store;
      const p = S.state.todos.find((t) => t.id === pid);
      const kids = S.state.todos.filter((c) => c.parentId === pid);
      return { parentDeleted: !!p.deletedAt, kids: kids.map((k) => ({ id: k.id, deleted: !!k.deletedAt })) };
    }, info.parent.id);
    console.log('after soft delete parent:', afterDel);
    await L.go(page, 'trash');
    await settle(page, 300);
    await shot(page, 'ST-01-trash-parent-and-kids');
    const rows = await L.texts(page, '[data-testid="trash-row"]');
    console.log('trash rows:', rows.map((r) => r.replace(/\s+/g, ' ').slice(0, 80)));
    // purge parent via UI
    const prow = page.locator('[data-testid="trash-row"]', { hasText: info.parent.s }).first();
    await prow.locator('[data-testid="trash-purge"]').click();
    await settle(page, 250);
    await L.clickText(page, '.modal button', '永久删除');
    await settle(page, 400);
    await shot(page, 'ST-02-after-purge-parent');
    const afterPurge = await page.evaluate((pid) => {
      const S = window.Store;
      const p = S.state.todos.find((t) => t.id === pid);
      const kids = S.state.todos.filter((c) => c.parentId === pid);
      return { parent: p ? { id: p.id, deleted: !!p.deletedAt } : null, kids: kids.map((k) => ({ id: k.id, s: k.summary, deleted: !!k.deletedAt })) };
    }, info.parent.id);
    console.log('after purge parent:', afterPurge);
    const rows2 = await L.texts(page, '[data-testid="trash-row"]');
    console.log('trash rows after:', rows2.map((r) => r.replace(/\s+/g, ' ').slice(0, 80)));
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
