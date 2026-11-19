import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { launchBrowser } from './pw.mjs';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const url = (file, q) => pathToFileURL(join(root, file)).href + (q ? '?' + q : '');
const VARIANTS = ['A', 'B', 'C'];
const SCREENS = ['today', 'todo', 'calendar'];

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok: !!ok, detail: detail || '' });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

const browser = await launchBrowser();

async function openApp(variant, platform, screen, width, height) {
  const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const errors = [];
  const external = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('request', (r) => {
    const u = r.url();
    if (!u.startsWith('file:') && !u.startsWith('data:')) external.push(u);
  });
  await page.goto(url('app.html', `variant=${variant}&platform=${platform}&screen=${screen}`));
  await page.waitForFunction('window.__READY__ === true', null, { timeout: 20000 });
  await page.waitForTimeout(120);
  return { ctx, page, errors, external };
}

/* 1. same DOM / data / layout across variants */
for (const platform of ['desktop', 'phone']) {
  for (const screen of SCREENS) {
    const vw = platform === 'phone' ? 390 : 1280;
    const vh = platform === 'phone' ? 844 : 800;
    const snaps = {};
    for (const variant of VARIANTS) {
      const { ctx, page, errors, external } = await openApp(variant, platform, screen, vw, vh);
      snaps[variant] = await page.evaluate(() => {
        const sel = ['.row', '.side-item', '.todo-row', '.cal-event', '.due-chip', '.group-title', '.group-count', '.rail-item', '.tab', '.chip'];
        const rects = [];
        for (const s of sel) {
          for (const el of document.querySelectorAll(s)) {
            const r = el.getBoundingClientRect();
            rects.push([s, Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]);
          }
        }
        return {
          html: document.body.innerHTML,
          text: document.body.innerText,
          rects: JSON.stringify(rects),
          rows: document.querySelectorAll('.row').length,
          todos: document.querySelectorAll('.todo-row').length,
          events: document.querySelectorAll('.cal-event').length,
        };
      });
      if (errors.length) check(`no pageerror ${variant} ${platform} ${screen}`, false, errors.join(' | '));
      if (external.length) check(`no external request ${variant} ${platform} ${screen}`, false, external.join(' | '));
      await ctx.close();
    }
    const sameHtml = snaps.A.html === snaps.B.html && snaps.A.html === snaps.C.html;
    const sameRects = snaps.A.rects === snaps.B.rects && snaps.A.rects === snaps.C.rects;
    const sameText = snaps.A.text === snaps.B.text && snaps.A.text === snaps.C.text;
    check(`same DOM ${platform} ${screen}`, sameHtml, sameHtml ? '' : 'body innerHTML differs');
    check(`same layout ${platform} ${screen}`, sameRects, sameRects ? '' : 'element rects differ');
    check(`same visible text ${platform} ${screen}`, sameText, `rows=${snaps.A.rows} todos=${snaps.A.todos} events=${snaps.A.events}`);
  }
}

/* 2. overflow at 1440 / 1280 / 390 / 320 */
for (const [platform, width] of [['desktop', 1440], ['desktop', 1280], ['phone', 390], ['phone', 320]]) {
  for (const screen of SCREENS) {
    const { ctx, page } = await openApp('A', platform, screen, width, platform === 'phone' ? 844 : 800);
    const over = await page.evaluate(() => {
      const de = document.documentElement;
      const docOver = de.scrollWidth - de.clientWidth;
      const screenEl = document.querySelector('.screen[data-screen="' + document.documentElement.getAttribute('data-screen') + '"]');
      const screenOver = screenEl ? screenEl.scrollWidth - screenEl.clientWidth : 0;
      const bad = [];
      if (docOver > 1) {
        document.querySelectorAll('.app *').forEach((el) => {
          const r = el.getBoundingClientRect();
          if (r.width > 0 && (r.right > de.clientWidth + 1 || r.left < -1)) {
            bad.push((el.className || el.tagName) + ':' + Math.round(r.left) + '..' + Math.round(r.right));
          }
        });
      }
      return { docOver, screenOver, bad: bad.slice(0, 6) };
    });
    check(
      `no horizontal overflow ${platform} ${width} ${screen}`,
      over.docOver <= 1 && over.screenOver <= 1,
      over.docOver > 1 || over.screenOver > 1 ? JSON.stringify(over) : '',
    );
    await ctx.close();
  }
}

/* 3. phone touch targets >= 48 (elementFromPoint probe, including hit-area pseudo elements) */
for (const screen of SCREENS) {
  const { ctx, page } = await openApp('A', 'phone', screen, 390, 844);
  const targets = await page.evaluate(() => {
    const sels = ['.tab', '.capture-btn', '.todo-row', '.chip', '.tb-today', '.tb-search', '.tb-new', '.side-item', '.icon-btn', '.cal-today', '.detail-back', '.detail-toggle'];
    const out = [];
    for (const sel of sels) {
      for (const el of document.querySelectorAll(sel)) {
        if (el.offsetParent === null && getComputedStyle(el).position !== 'fixed') continue;
        el.scrollIntoView({ block: 'center', inline: 'nearest' });
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height) continue;
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;
        const dy = Math.max(0, (48 - r.height) / 2);
        const dx = Math.max(0, (48 - r.width) / 2);
        const pts = [
          [cx, cy],
          [cx, cy - dy],
          [cx, cy + dy],
          [cx - dx, cy],
          [cx + dx, cy],
        ];
        const ok = pts.every(([x, y]) => {
          if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) return false;
          const hit = document.elementFromPoint(x, y);
          return !!hit && (hit === el || el.contains(hit));
        });
        out.push({ sel, w: Math.round(r.width), h: Math.round(r.height), ok });
      }
    }
    return out;
  });
  const bad = targets.filter((t) => !t.ok);
  check(`phone touch >= 48 ${screen}`, bad.length === 0, bad.length ? JSON.stringify(bad.slice(0, 8)) : `probed ${targets.length} targets`);
  await ctx.close();
}

/* 4. contrast — body text >= 4.5, secondary >= 3 */
for (const variant of VARIANTS) {
  const { ctx, page } = await openApp(variant, 'desktop', 'today', 1280, 800);
  const samples = await page.evaluate(() => {
    const checks = [
      ['.rail-item', 4.5],
      ['.row-title', 4.5],
      ['.row-time .t-start', 4.5],
      ['.row-meta', 3],
      ['.group-title', 4.5],
      ['.group-meta', 3],
      ['.tag', 3],
      ['.side-item-title', 4.5],
      ['.side-item-meta', 4.5],
      ['.todo-title', 4.5],
      ['.todo-meta', 3],
      ['.chip', 4.5],
      ['.chip.is-active', 4.5],
      ['.detail-title', 4.5],
      ['.field dt', 3],
      ['.field dd', 4.5],
      ['.cal-daycell', 4.5],
      ['.cal-hour span', 3],
      ['.cal-event-title', 4.5],
      ['.cal-event-time', 3],
      ['.due-chip', 4.5],
      ['.tab', 4.5],
    ];

    function parse(str) {
      const m = str.match(/rgba?\(([^)]+)\)/);
      if (!m) return { r: 0, g: 0, b: 0, a: 0 };
      const p = m[1].split(',').map((x) => parseFloat(x));
      return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
    }
    function lum(c) {
      const f = (v) => {
        v /= 255;
        return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
      };
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function bgOf(el) {
      const stack = [];
      let node = el;
      while (node) {
        const c = parse(getComputedStyle(node).backgroundColor);
        if (c.a > 0) {
          stack.push(c);
          if (c.a >= 0.999) break;
        }
        node = node.parentElement;
      }
      let base = { r: 255, g: 255, b: 255 };
      for (let i = stack.length - 1; i >= 0; i--) {
        const c = stack[i];
        base = {
          r: c.r * c.a + base.r * (1 - c.a),
          g: c.g * c.a + base.g * (1 - c.a),
          b: c.b * c.a + base.b * (1 - c.a),
        };
      }
      return base;
    }
    function ratio(a, b) {
      const la = lum(a);
      const lb = lum(b);
      const hi = Math.max(la, lb);
      const lo = Math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    const out = [];
    for (const [sel, min] of checks) {
      let worst = null;
      for (const el of document.querySelectorAll(sel)) {
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height) continue;
        if (el.closest('.is-done')) continue;
        const fg = parse(getComputedStyle(el).color);
        const bg = bgOf(el);
        const value = ratio(fg, bg);
        if (!worst || value < worst.value) {
          worst = { value: Math.round(value * 100) / 100, text: (el.textContent || '').trim().slice(0, 12), fg: getComputedStyle(el).color, bg: Math.round(bg.r) + ',' + Math.round(bg.g) + ',' + Math.round(bg.b) };
        }
      }
      if (worst) out.push({ sel, min, ...worst });
    }
    return out;
  });
  const fails = samples.filter((s) => s.value < s.min);
  check(`contrast ${variant}`, fails.length === 0, fails.length ? JSON.stringify(fails) : `min ${Math.min(...samples.map((s) => s.value))}`);
  await ctx.close();
}

/* 5. blind page */
{
  const ctx = await browser.newContext({ viewport: { width: 1500, height: 1200 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(url('blind.html'));
  await page.waitForFunction('window.__READY__ === true');
  await page.evaluate(() => localStorage.removeItem('ds-blind-v1'));
  await page.reload();
  await page.waitForFunction('window.__READY__ === true');

  const boards = await page.evaluate(() => window.__BLIND__.boards.length);
  check('blind has 6 boards', boards === 6, 'found ' + boards);

  await page.waitForFunction(() => document.querySelectorAll('.blind-thumb iframe').length === 3);
  const thumbText = await page.evaluate(() => document.getElementById('blind-thumbs').innerText.trim());
  check('blind hides variant names', !/[ABC]/.test(thumbText), JSON.stringify(thumbText));

  await page.keyboard.press('2');
  await page.waitForTimeout(350);
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('ds-blind-v1') || 'null'));
  const picked = saved && Object.keys(saved.picks).length;
  check('blind key 2 records a pick', picked === 1, JSON.stringify(saved && saved.picks));
  const progress = await page.locator('#blind-progress').innerText();
  check('blind progress counter', progress.trim() === '1 / 6', progress);

  for (let i = 0; i < 5; i++) {
    await page.keyboard.press('1');
    await page.waitForTimeout(300);
  }
  const finalProgress = await page.locator('#blind-progress').innerText();
  check('blind completes 6 / 6', finalProgress.trim() === '6 / 6', finalProgress);

  await page.click('#btn-export');
  await page.waitForTimeout(200);
  const jsonText = await page.locator('#blind-json').innerText();
  let data = null;
  try { data = JSON.parse(jsonText); } catch (e) {}
  check('blind export parses', !!data, data ? 'boards=' + data.boards.length : 'invalid JSON');
  if (data) {
    const ok = data.boards.length === 6 && data.boards.every((b) => b.order.length === 3 && b.order.slice().sort().join('') === 'ABC' && b.selectedSlot >= 1 && b.selectedSlot <= 3 && b.selectedVariant === b.order[b.selectedSlot - 1]);
    check('blind export maps picks to variants', ok, JSON.stringify(data.boards[0]));
    const orders = data.boards.map((b) => b.order.join(''));
    await page.reload();
    await page.waitForFunction('window.__READY__ === true');
    await page.click('#btn-export');
    await page.waitForTimeout(200);
    const again = JSON.parse(await page.locator('#blind-json').innerText());
    check('blind order reproducible after reload', again.boards.map((b) => b.order.join('')).join('|') === orders.join('|'), orders.join('|'));
    check('blind picks persist after reload', again.boards.every((b) => b.selectedSlot !== null), '');
  }
  if (errors.length) check('blind no pageerror', false, errors.join(' | '));
  await ctx.close();
}

/* 6. index + compare load cleanly */
for (const [file, q, expectFrames] of [['index.html', 'variant=C&platform=phone&screen=todo', 1], ['compare.html', 'platform=desktop&screen=today', 3], ['compare.html', 'platform=desktop&screen=all', 9]]) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(url(file, q));
  await page.waitForTimeout(1200);
  const frames = await page.evaluate(() => document.querySelectorAll('iframe').length);
  check(`${file} ?${q} frames`, frames === expectFrames, 'frames=' + frames);
  if (errors.length) check(`${file} no pageerror`, false, errors.join(' | '));
  await ctx.close();
}

await browser.close();

const failed = results.filter((r) => !r.ok);
console.log('\n' + (failed.length ? `FAILED ${failed.length} / ${results.length}` : `ALL PASS ${results.length} checks`));
process.exit(failed.length ? 1 : 0);
