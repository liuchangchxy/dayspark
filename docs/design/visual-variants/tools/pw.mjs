import { readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';

export async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch (err) {
    // fall through to local caches
  }
  const candidates = [];
  if (process.env.PLAYWRIGHT_MODULE) candidates.push(process.env.PLAYWRIGHT_MODULE);
  const npx = join(homedir(), '.npm', '_npx');
  if (existsSync(npx)) {
    for (const dir of readdirSync(npx)) {
      candidates.push(join(npx, dir, 'node_modules', 'playwright', 'index.mjs'));
    }
  }
  for (const candidate of candidates) {
    if (existsSync(candidate)) return import(pathToFileURL(candidate).href);
  }
  throw new Error('playwright not found. Run `npm i -D playwright` or `npx playwright install chromium`.');
}

function findBrowser() {
  const cache = join(homedir(), 'Library', 'Caches', 'ms-playwright');
  if (!existsSync(cache)) return null;
  const dirs = readdirSync(cache).filter((d) => d.startsWith('chromium_headless_shell-'));
  for (const d of dirs.sort().reverse()) {
    const bin = join(cache, d, 'chrome-headless-shell-mac-arm64', 'chrome-headless-shell');
    if (existsSync(bin)) return bin;
  }
  return null;
}

export async function launchBrowser() {
  const pw = await loadPlaywright();
  try {
    return await pw.chromium.launch();
  } catch (err) {
    const bin = findBrowser();
    if (!bin) throw err;
    return pw.chromium.launch({ executablePath: bin });
  }
}
