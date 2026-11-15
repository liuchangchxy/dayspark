const L = require('./r2-lib');
const { launch, newPage, settle, shot, state, DESKTOP } = L;

async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    await L.go(page, 'todos');
    await settle(page, 300);
    await L.clickText(page, '.chip-btn', '全部');
    await settle(page, 300);
    const before = await page.evaluate(() => {
      const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
      return { id: t.id, states: JSON.parse(JSON.stringify(t.occurrenceStates)) };
    });
    const tile = page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).first();
    console.log('tile before:', (await tile.textContent()).replace(/\s+/g, ' ').slice(0, 140));
    await tile.locator('[role="checkbox"]').first().click();
    await settle(page, 450);
    await shot(page, 'F3b-01-complete-recurring-from-list');
    const after = await page.evaluate(() => {
      const t = window.Store.state.todos.find((x) => x.summary === '读 20 页《设计中的设计》');
      return {
        states: JSON.parse(JSON.stringify(t.occurrenceStates)),
        status: t.status,
        toast: document.querySelector('.toast') && document.querySelector('.toast').textContent,
        route: window.Store.state.route.name,
      };
    });
    const tileAfter = page.locator('[data-testid="todo-tile"]', { hasText: '读 20 页' }).first();
    const visible = await tileAfter.isVisible().catch(() => false);
    console.log('after:', after);
    console.log('tile still on page?', visible, visible ? (await tileAfter.textContent()).replace(/\s+/g, ' ').slice(0, 140) : '');
    console.log('checkbox class:', visible ? await tileAfter.locator('[role="checkbox"]').first().getAttribute('class').catch(() => null) : null);
    // detail completion of another recurring todo
    await L.go(page, 'todos');
    await settle(page, 250);
    const tile2 = page.locator('[data-testid="todo-tile"]', { hasText: '晨间回顾' }).first();
    await tile2.click();
    await settle(page, 350);
    console.log('detail buttons:', await L.texts(page, '#view button'));
    await L.clickText(page, '#view button', '完成');
    await settle(page, 400);
    await shot(page, 'F3b-02-complete-recurring-detail');
    const after2 = await page.evaluate(() => {
      const t = window.Store.state.todos.find((x) => x.summary === '晨间回顾：今天最重要的一件事');
      return { states: JSON.parse(JSON.stringify(t.occurrenceStates)), status: t.status, toast: document.querySelector('.toast') && document.querySelector('.toast').textContent };
    });
    console.log('detail after:', after2);
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
