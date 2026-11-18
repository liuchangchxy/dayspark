#!/usr/bin/env node
// Captures real product screenshots from public pages (Mobbin / App Store)
// into docs/design/visual-direction/refs/<id>.png
//
// Usage:
//   node tools/refshot/capture.js [targets.json] [--dry-run] [--only=<id>]
//
// Reuses playwright-core from the g0 interaction-model test folder:
//   NODE_PATH="$HOME/Desktop/Code/dayspark-g0/docs/design/interaction-model/tests/node_modules"

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright-core');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT_DIR = path.join(ROOT, 'docs', 'design', 'visual-direction', 'refs');
const CHROMIUM_DEFAULT = path.join(
  os.homedir(),
  'Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
);
const PROXY = 'http://127.0.0.1:7897';
const MIN_WIDTH = 300;
const MIN_HEIGHT = 500;
const VIEWPORT = { width: 1440, height: 1600 };
const MAX_OUTPUT_DIM = 1800;

const LOGIN_MARKERS = [
  'sign in to continue',
  'log in to continue',
  'log in to view',
  'subscribe to view',
  'subscribe to continue',
  'upgrade to view',
  'create your account to',
  'this content is for members',
  'start your free trial to',
];

function parseArgs(argv) {
  const opts = { targets: path.join(__dirname, 'targets.json'), dryRun: false, only: null };
  for (const arg of argv.slice(2)) {
    if (arg === '--dry-run') opts.dryRun = true;
    else if (arg.startsWith('--only=')) opts.only = arg.slice('--only='.length);
    else if (!arg.startsWith('--')) opts.targets = path.resolve(arg);
  }
  return opts;
}

function readPngSize(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 24 || buf.readUInt32BE(0) !== 0x89504e47) return { width: 0, height: 0 };
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

function shrinkIfNeeded(file) {
  const { width, height } = readPngSize(file);
  const max = Math.max(width, height);
  if (max > MAX_OUTPUT_DIM) {
    execFileSync('sips', ['-Z', String(MAX_OUTPUT_DIM), file, '--out', file], { stdio: 'ignore' });
  }
}

async function hideOverlays(page) {
  await page.evaluate(() => {
    const nodes = Array.from(document.querySelectorAll('div, button, a, aside'));
    for (const el of nodes) {
      const text = (el.innerText || '').trim();
      if (!text || text.length > 40 || !/see similar/i.test(text)) continue;
      const style = window.getComputedStyle(el);
      if (style.position === 'fixed' || style.position === 'sticky' || style.position === 'absolute') {
        el.style.visibility = 'hidden';
      }
    }
  });
}

async function waitForImages(page, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const pending = await page.evaluate(() =>
      Array.from(document.images).filter((im) => im.src && !im.complete).length,
    );
    if (pending === 0) return;
    await page.waitForTimeout(400);
  }
}

async function detectLoginWall(page) {
  const text = (await page.evaluate(() => document.body.innerText || '')).toLowerCase();
  for (const marker of LOGIN_MARKERS) {
    if (text.includes(marker)) return marker;
  }
  return null;
}

async function collectCandidates(page) {
  return page.evaluate((min) => {
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const title = (document.querySelector('h1') && document.querySelector('h1').innerText
      ? document.querySelector('h1').innerText
      : document.title || ''
    ).toLowerCase();
    const images = Array.from(document.images);
    return images
      .map((im, index) => {
        const nw = im.naturalWidth;
        const nh = im.naturalHeight;
        const rect = im.getBoundingClientRect();
        const style = window.getComputedStyle(im);
        const visible = style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
        const inViewport = rect.bottom > 0 && rect.top < vh && rect.right > 0 && rect.left < vw;
        const visibleH = Math.max(0, Math.min(rect.bottom, vh) - Math.max(rect.top, 0));
        const visibleW = Math.max(0, Math.min(rect.right, vw) - Math.max(rect.left, 0));
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;
        const dist = Math.hypot((centerX - vw / 2) / vw, (centerY - vh / 2) / vh);
        const alt = (im.alt || '').toLowerCase();
        const titleNorm = title.replace(/\s+/g, ' ').trim();
        const altNorm = alt.replace(/\s+/g, ' ').trim();
        const altMatchesTitle = titleNorm.length > 0 && altNorm.includes(titleNorm);
        const area = nw * nh;
        let score = area;
        if (altMatchesTitle) score *= 6;
        if (inViewport) score *= 2;
        if (visible) score *= 1.5;
        score *= 1 / (1 + dist);
        return {
          index,
          alt: im.alt || '',
          naturalWidth: nw,
          naturalHeight: nh,
          eligible: visible && nw >= min.w && nh >= min.h,
          inViewport,
          visibleW,
          visibleH,
          altMatchesTitle,
          score,
        };
      })
      .filter((c) => c.eligible)
      .sort((a, b) => {
        if (a.altMatchesTitle !== b.altMatchesTitle) return b.altMatchesTitle - a.altMatchesTitle;
        if (a.altMatchesTitle) return a.index - b.index;
        return b.score - a.score;
      });
  }, { w: MIN_WIDTH, h: MIN_HEIGHT });
}

async function captureTarget(browser, target, opts) {
  const context = await browser.newContext({
    viewport: VIEWPORT,
    deviceScaleFactor: 2,
    locale: 'en-US',
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  });
  const page = await context.newPage();
  const result = { id: target.id, app: target.app, screen: target.screen, status: 'failed', reason: null };
  try {
    await page.goto(target.url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(3500);
    await waitForImages(page, 12000);
    for (let i = 0; i < 4; i += 1) {
      await page.mouse.wheel(0, 700);
      await page.waitForTimeout(600);
    }
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(1500);
    await waitForImages(page, 8000);

    const loginMarker = await detectLoginWall(page);
    if (loginMarker) {
      result.reason = `login/subscription wall detected (${loginMarker})`;
      return result;
    }

    let candidates = await collectCandidates(page);
    if (target.imgAltContains) {
      const needle = String(target.imgAltContains).toLowerCase();
      candidates = candidates.filter((c) => (c.alt || '').toLowerCase().includes(needle));
    }

    if (opts.dryRun) {
      result.status = candidates.length ? 'dry-run' : 'failed';
      result.candidates = candidates.slice(0, 8);
      if (!candidates.length) result.reason = 'no candidate image found';
      return result;
    }

    if (!candidates.length) {
      result.reason = 'no candidate image found';
      return result;
    }

    let locator;
    let chosen;
    if (target.selectorHint) {
      locator = page.locator(target.selectorHint).first();
      const box = await locator.boundingBox().catch(() => null);
      if (!box) {
        result.reason = `selectorHint not found: ${target.selectorHint}`;
        return result;
      }
      chosen = candidates[0];
    } else {
      chosen = candidates[0];
      locator = page.locator('img').nth(chosen.index);
    }

    await locator.scrollIntoViewIfNeeded({ timeout: 10000 }).catch(() => {});
    await page.waitForTimeout(800);
    await hideOverlays(page);
    await page.evaluate(() => {
      const sel = window.getSelection();
      if (sel) sel.removeAllRanges();
    });
    const box = await locator.boundingBox();
    if (!box) {
      result.reason = 'image element has no layout box';
      return result;
    }

    fs.mkdirSync(OUT_DIR, { recursive: true });
    const outPath = path.join(OUT_DIR, `${target.id}.png`);
    await locator.screenshot({ path: outPath, type: 'png' });
    shrinkIfNeeded(outPath);
    const dims = readPngSize(outPath);
    const stat = fs.statSync(outPath);

    if (dims.width < MIN_WIDTH || dims.height < MIN_HEIGHT) {
      fs.unlinkSync(outPath);
      result.reason = `screenshot too small (${dims.width}x${dims.height})`;
      return result;
    }

    result.status = 'ok';
    result.width = dims.width;
    result.height = dims.height;
    result.sourceNatural = `${chosen.naturalWidth}x${chosen.naturalHeight}`;
    result.bytes = stat.size;
    result.file = path.relative(ROOT, outPath);
    result.alt = chosen.alt;
    return result;
  } catch (err) {
    result.reason = err && err.message ? err.message : String(err);
    return result;
  } finally {
    await context.close().catch(() => {});
  }
}

async function main() {
  const opts = parseArgs(process.argv);
  if (!fs.existsSync(opts.targets)) {
    console.error(`targets file not found: ${opts.targets}`);
    process.exit(1);
  }
  const targets = JSON.parse(fs.readFileSync(opts.targets, 'utf8'));
  const list = opts.only ? targets.filter((t) => t.id === opts.only) : targets;
  if (!list.length) {
    console.error(`no targets matched (--only=${opts.only})`);
    process.exit(1);
  }

  const executablePath = process.env.CHROMIUM_PATH || CHROMIUM_DEFAULT;
  const browser = await chromium.launch({
    executablePath,
    headless: true,
    args: [`--proxy-server=${PROXY}`],
  });

  const results = [];
  try {
    for (let i = 0; i < list.length; i += 1) {
      const target = list[i];
      if (i > 0) await new Promise((r) => setTimeout(r, 1600));
      const result = await captureTarget(browser, target, opts);
      results.push(result);
      if (opts.dryRun) {
        console.log(`[dry-run] ${result.id} | ${target.app} | ${target.screen} | ${result.status}`);
        if (result.candidates) {
          for (const c of result.candidates) {
            console.log(
              `    #${c.index} ${c.naturalWidth}x${c.naturalHeight} score=${Math.round(c.score)} titleMatch=${c.altMatchesTitle} alt="${c.alt}"`,
            );
          }
        }
        if (result.reason) console.log(`    reason: ${result.reason}`);
      } else if (result.status === 'ok') {
        console.log(
          `${result.id} | ${result.app} | ${result.screen} | ${result.width}x${result.height} (source ${result.sourceNatural}) | ${(
            result.bytes / 1024
          ).toFixed(0)} KB`,
        );
      } else {
        console.log(`${result.id} | ${result.app} | ${result.screen} | FAILED: ${result.reason}`);
      }
    }
  } finally {
    await browser.close();
  }

  const ok = results.filter((r) => r.status === 'ok');
  console.log(`\nSummary: ${ok.length}/${results.length} captured`);
  if (!opts.dryRun) {
    const reportPath = path.join(OUT_DIR, '_last-run.json');
    fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
