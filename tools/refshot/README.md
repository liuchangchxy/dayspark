# refshot — public-page screenshot capture

Small, dependency-free capture tool for collecting real product UI screenshots
from public pages (currently Mobbin screen pages) into
`docs/design/visual-direction/refs/`.

It reuses the `playwright-core` install from the g0 interaction-model tests, so
there is no `package.json` and no `npm install` here.

## Requirements

- Node 18+ on macOS
- `playwright-core@1.56.1` from
  `$HOME/Desktop/Code/dayspark-g0/docs/design/interaction-model/tests/node_modules`
- Chromium for Testing under
  `$HOME/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`
- Clash proxy on `127.0.0.1:7897` (Chromium is launched with
  `--proxy-server=http://127.0.0.1:7897`)

Environment overrides:

```bash
export NODE_PATH="$HOME/Desktop/Code/dayspark-g0/docs/design/interaction-model/tests/node_modules"
export CHROMIUM_PATH="/path/to/Google Chrome for Testing"   # optional
```

## Run

From the repository root:

```bash
NODE_PATH="$HOME/Desktop/Code/dayspark-g0/docs/design/interaction-model/tests/node_modules" \
  node tools/refshot/capture.js
```

Options:

- `--dry-run` — open each page and print candidate images only, save nothing
- `--only=<id>` — capture a single target from the targets file
- `--retries=N` — retry a failed target N times (default 1)
- `--delay=MS` — pause between targets (default 1600)
- `--allow-existing` — permit a targets file that reuses an id already in
  `refs/manifest.json` (off by default, so the original board cannot be
  overwritten by accident)
- first positional argument — alternate targets file

Each successful capture prints `id | app | screen | output size (source size) | KB`.
Failures (login wall, no candidate image, too-small screenshot) are printed and
skipped; the run continues with the next target. Requests are spaced ~1.6 s
apart.

## targets.json

Array of objects:

```json
{
  "id": "todoist-today",
  "app": "Todoist",
  "screen": "Today task list",
  "category": "today",
  "url": "https://mobbin.com/explore/screens/342de899-b7f1-4753-90b8-636764b9554d"
}
```

- `id` — output filename stem (`refs/<id>.png`)
- `category` — one of `today` / `calendar` / `detail` / `composer` /
  `search` / `empty`
- `platform` — `phone` or `web` (used to rank the right screenshot)
- optional `theme` — recorded in the manifest separately from the pixels
- optional `style` — array of style tags, recorded in the manifest
- optional `selectorHint` — CSS selector to screenshot instead of auto-pick
- optional `imgAltContains` — restrict candidates to images whose `alt` contains
  this string (useful on flow pages)

`targets.json` holds the original twelve-reference set;
`targets-expand.json`, `targets-expand-2.json` and `targets-expand-3.json`
hold the later expansion rounds.

Adding a target: find a public Mobbin screen page (`https://mobbin.com/explore/screens/<uuid>`)
via `searx-search -n 10 "site:mobbin.com <app> iOS <screen>"`, open it without
logging in, then add the entry.

## How the image is chosen

0. Prefer the page's `og:image` metadata. Mobbin embeds the original screen asset
   in its `screenUrl` query parameter, so the tool downloads that PNG directly
   through the browser context (respecting the proxy) instead of screenshotting
   a rendered element. This yields the full-resolution screenshot with no
   page chrome, canvas padding or lazy-load gaps.
1. If there is no `og:image`, wait for DOM, images and 3.5 s settling, scroll to
   trigger lazy loading.
2. Enumerate `document.images`, keep `naturalWidth >= 300 && naturalHeight >= 500`.
3. Prefer the first image whose `alt` contains the page `h1` (this is the
   screen's primary screenshot; related-screen thumbnails further down the page
   also have large images, so raw area alone is unreliable).
4. Otherwise fall back to the largest image weighted by viewport position
   (centred / visible images score higher).
5. Hide the fixed "See similar" overlay, clear text selection, then take an
   element screenshot at `deviceScaleFactor: 2`.
6. Reject the capture if the PNG is narrower than 300 px or shorter than 500 px.
   Outputs longer than 1800 px on either side are downscaled with `sips`.

Login/subscription overlays are detected with a small phrase list
("sign in to continue", "subscribe to view", …); the page is skipped when one is
found. Pages that are public but only show a marketing page produce no large
in-app screenshot and fail the candidate check.

## Outputs

- `docs/design/visual-direction/refs/<id>.png`
- `docs/design/visual-direction/refs/_last-run.json` — machine-readable result log
  (overwritten on every run; ignored by git)

## Boundary

Public pages only. No sign-in, no paywall bypass, no crawling beyond the listed
targets. Reference images are for internal design study only.
