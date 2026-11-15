const L = require('./r2-lib');
const { launch, newPage, settle, shot, DESKTOP } = L;
async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    await L.go(page, 'chat');
    await settle(page, 300);
    const budgetBefore = await page.evaluate(() => {
      const t = window.Store.state.todos.find((x) => x.summary === 'Q4 预算表');
      return { id: t.id, allocs: window.Store.state.allocations.filter((a) => a.todoId === t.id).map((a) => ({ id: a.id, s: a.startAt, e: a.endAt, state: a.state })) };
    });
    await page.fill('[data-testid="chat-input"]', '把「Q4 预算表」安排到明天上午');
    await page.keyboard.press('Enter');
    await settle(page, 900);
    const chat = await L.text(page, '.chat-scroll');
    console.log('chat:', chat.replace(/\s+/g, ' ').slice(0, 500));
    const applyBtn = page.locator('#view button').filter({ hasText: /应用|Apply/ }).last();
    await applyBtn.click();
    await settle(page, 500);
    const info = await page.evaluate(() => {
      const todos = window.Store.state.todos;
      const allocs = window.Store.state.allocations;
      return {
        all: allocs.map((a) => ({ id: a.id, todo: (todos.find((t) => t.id === a.todoId) || {}).summary, s: a.startAt, e: a.endAt, occ: a.occurrenceId, state: a.state })),
        budget: (() => { const t = todos.find((x) => x.summary === 'Q4 预算表'); return { id: t.id, allocs: allocs.filter((a) => a.todoId === t.id).map((a) => ({ id: a.id, s: a.startAt, e: a.endAt, state: a.state })) }; })(),
      };
    });
    console.log('before budget:', budgetBefore);
    console.log('all allocs:', JSON.stringify(info.all, null, 1));
    await shot(page, 'AI-01-after-apply');
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
