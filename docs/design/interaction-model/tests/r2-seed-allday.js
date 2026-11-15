const L = require('./r2-lib');
const { launch, newPage, settle, shot, DESKTOP } = L;
async function main() {
  const browser = await launch();
  try {
    const page = await newPage(browser, DESKTOP);
    await L.go(page, 'calendar');
    await settle(page, 350);
    const allDay = await L.texts(page, '.all-day-row *, .allday-row *, .month-allday *').catch(() => []);
    console.log('allday texts:', allDay.slice(0, 20));
    const ev = await page.evaluate(() => {
      const e = window.Store.state.events.find((x) => x.isAllDay);
      return e ? { id: e.id, s: e.summary, start: e.startDt, end: e.endDt, startValid: !isNaN(e.startDt), endValid: !isNaN(e.endDt) } : null;
    });
    console.log('all-day seed:', ev);
    await L.go(page, 'detail', { type: 'event', id: ev.id });
    await settle(page, 350);
    await shot(page, 'SEED-01-allday-detail');
    console.log('detail:', (await L.text(page, '#view')).slice(0, 240));
    await page.close();
  } finally { await browser.close(); }
}
main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
