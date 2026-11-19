import { mkdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { launchBrowser } from './pw.mjs';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const shotsDir = join(root, 'shots');
mkdirSync(shotsDir, { recursive: true });

const VARIANTS = ['A', 'B', 'C'];
const SCREENS = ['today', 'todo', 'calendar'];

const browser = await launchBrowser();

function pngSize(file) {
  const buf = readFileSync(file);
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20), bytes: statSync(file).size };
}

async function waitFrames(page) {
  const frames = page.frames().filter((f) => f !== page.mainFrame());
  await Promise.all(frames.map((f) => f.waitForFunction('window.__READY__ === true', null, { timeout: 20000 }).catch(() => {})));
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(350);
}

async function shootApp(variant, platform, screen) {
  const phone = platform === 'phone';
  const ctx = await browser.newContext({
    viewport: { width: phone ? 390 : 1280, height: phone ? 844 : 800 },
    deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  const url = pathToFileURL(join(root, 'app.html')).href + `?variant=${variant}&platform=${platform}&screen=${screen}`;
  await page.goto(url);
  await page.waitForFunction('window.__READY__ === true', null, { timeout: 20000 });
  await waitFrames(page);
  const file = join(shotsDir, `${variant.toLowerCase()}-${screen}-${platform}.png`);
  await page.screenshot({ path: file });
  const size = pngSize(file);
  console.log(`shot ${file.replace(root + '/', '')} ${size.width}x${size.height} ${errors.length ? 'ERRORS: ' + errors.join(' | ') : ''}`);
  await ctx.close();
  return size;
}

async function shootCompare(name, params, width, height) {
  const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  const url = pathToFileURL(join(root, 'compare.html')).href + '?' + params;
  await page.goto(url);
  await page.waitForFunction('window.__COMPARE_RENDERED__ === true', null, { timeout: 20000 });
  await waitFrames(page);
  const file = join(root, name);
  await page.screenshot({ path: file, fullPage: true });
  const size = pngSize(file);
  console.log(`shot ${name} ${size.width}x${size.height} ${errors.length ? 'ERRORS: ' + errors.join(' | ') : ''}`);
  await ctx.close();
}

for (const variant of VARIANTS) {
  for (const screen of SCREENS) {
    await shootApp(variant, 'desktop', screen);
    await shootApp(variant, 'phone', screen);
  }
}

await shootCompare('compare-desktop.png', 'platform=desktop&screen=today', 1720, 640);
await shootCompare('compare-phone.png', 'platform=phone&screen=today', 1500, 1100);
await shootCompare('compare-all.png', 'platform=desktop&screen=all', 2000, 1400);

await browser.close();
console.log('done');
