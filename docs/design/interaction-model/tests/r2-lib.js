const path = require('path');
const { chromium } = require('playwright-core');

const CHROME = '/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL = 'file://' + path.resolve(__dirname, '..', 'index.html');
const OUT = '/tmp/review2-g0';
const DESKTOP = { width: 1440, height: 900 };
const MOBILE = { width: 390, height: 844 };

function launch(opts) {
  return chromium.launch({ executablePath: CHROME, headless: !(opts && opts.headed) });
}

async function newPage(browser, viewport) {
  const page = await browser.newPage({ viewport: viewport || DESKTOP });
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.__READY__ === true, { timeout: 8000 });
  page.__errors = errors;
  return page;
}

const settle = (page, ms) => page.waitForTimeout(ms === undefined ? 180 : ms);

async function go(page, name, params) {
  await page.evaluate(([n, p]) => window.App.go(n, p), [name, params || null]);
  await settle(page, 220);
}

const exists = (page, sel) => page.evaluate((s) => !!document.querySelector(s), sel);
const count = (page, sel) => page.evaluate((s) => document.querySelectorAll(s).length, sel);
const text = (page, sel) => page.evaluate((s) => { const n = document.querySelector(s); return n ? n.textContent.replace(/\s+/g, ' ').trim() : null; }, sel);
const texts = (page, sel) => page.evaluate((s) => Array.from(document.querySelectorAll(s)).map((n) => n.textContent.replace(/\s+/g, ' ').trim()), sel);

async function shot(page, name) {
  await page.screenshot({ path: path.join(OUT, name + '.png') });
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}
function assertEq(actual, expected, msg) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${msg}: expected ${b}, got ${a}`);
}

async function clickText(page, selector, re) {
  const idx = await page.evaluate(([sel, pat]) => {
    const rx = new RegExp(pat);
    const ns = Array.from(document.querySelectorAll(sel));
    return ns.findIndex((n) => rx.test(n.textContent));
  }, [selector, typeof re === 'string' ? re : re.source]);
  if (idx < 0) throw new Error(`no ${selector} matching ${re}`);
  await page.locator(selector).nth(idx).click();
  await settle(page, 200);
}

async function state(page) {
  return page.evaluate(() => {
    const s = window.Store.state;
    const iso = (x) => {
      if (!x) return null;
      const d = new Date(x);
      return isNaN(d.getTime()) ? 'INVALID_DATE' : d.toISOString();
    };
    return {
      route: JSON.parse(JSON.stringify(s.route)),
      todos: s.todos.map((t) => ({
        id: t.id, summary: t.summary, status: t.status, parentId: t.parentId,
        dueDate: iso(t.dueDate), deletedAt: iso(t.deletedAt), completedAt: iso(t.completedAt),
        recurrence: t.recurrence, occurrenceStates: Object.keys(t.occurrenceStates || {}),
      })),
      events: s.events.map((e) => ({
        id: e.id, summary: e.summary, startDt: iso(e.startDt), endDt: iso(e.endDt),
        deletedAt: iso(e.deletedAt), rrule: e.rrule,
        exdates: (e.exdates || []).map((d) => new Date(d).toISOString()),
      })),
      allocations: s.allocations.map((a) => ({
        id: a.id, todoId: a.todoId, occurrenceId: a.occurrenceId, state: a.state,
        startAt: iso(a.startAt), endAt: iso(a.endAt),
      })),
      composer: s.composer,
      calendarView: s.calendarView,
      todosView: { kind: s.todosView.kind, day: iso(s.todosView.day) },
      highlight: s.highlight,
    };
  });
}

module.exports = {
  launch, newPage, settle, go, exists, count, text, texts, shot,
  assert, assertEq, clickText, state, DESKTOP, MOBILE, OUT,
};
