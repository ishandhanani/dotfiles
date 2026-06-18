---
name: browser-snapshot
description: Capture real browser UI screenshots and visual evidence for webpages, local web apps, dashboards, Perfetto traces, and other browser-rendered artifacts. Use when the user asks to use the browser, inspect a visual UI state, verify layout/rendering, produce screenshots, or attach browser/Perfetto snapshots as evidence.
---

# Browser Snapshot

Use a real browser when visual state matters. Do not replace browser evidence with synthetic plots, text summaries, or screenshots of intermediate loading pages.

## Default Stack

- Browser: `google-chrome` or `google-chrome-stable`.
- Control: Chrome DevTools Protocol over `--remote-debugging-port`.
- Driver: Python `websockets` + `urllib.request` when Playwright is unavailable.
- Local files: serve from `/tmp` with `ThreadingHTTPServer`; add CORS and `Access-Control-Allow-Private-Network` headers when loading from web UIs.
- Image check: open the captured PNG with `view_image` before reporting it.

## Workflow

1. Create or identify the artifact to view.
2. If the UI must fetch a local file, start a temporary HTTP server from the file directory.
3. Launch Chrome with a fresh `--user-data-dir`, `--remote-debugging-port`, and a fixed `--window-size`.
4. Use DevTools Protocol to poll `document.body.innerText` or a task-specific DOM condition until the real content appears.
5. Capture with `Page.captureScreenshot`; save under `/tmp/<descriptive-name>.png`.
6. Inspect the PNG with `view_image`. If it shows a loading page, cookie banner, collapsed sidebar, or wrong viewport, interact with the UI through CDP and recapture.
7. Stop Chrome and any temporary HTTP server before finishing.

## Perfetto

For Perfetto traces and screenshots, read [references/perfetto.md](references/perfetto.md). Use that recipe when the user asks for a Perfetto snapshot, trace visual, `ui.perfetto.dev`, or an example screenshot for a PR.
