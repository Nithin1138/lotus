# dropdial.org

Static website for [DropDial](https://github.com/Nithin1138/lotus). No build step: plain HTML, CSS and JavaScript.

- `index.html` holds the English copy.
- `assets/js/i18n.js` holds the UI copy and demo strings.
- `assets/js/site.js` runs the demo, reads the latest release from the GitHub API, and powers the drag-to-convert demo.
- `assets/js/wheel-ui.js` draws the shared rounded faces, raised sidewalls and hub for both the demo and showcase. Its geometry mirrors `DropWheel.Keycap` in the app's `FloatingWheel.cs` (outer radius 172, inner dead zone 65). Keep it in sync when the app's wheel changes; hit testing uses the actual rounded face, not an approximate wedge.

Preview locally with `python -m http.server 9876` in this folder, then open http://localhost:9876.

When you change a CSS or JS file, bump its `?v=` number in `index.html` (and `404.html` for the stylesheet) so visitors don't get a stale cached copy.

## Testing the demo

`tests/demo-tests.js` drives the drag-to-convert demo with pointer and keyboard events (21 checks: conversions, the job queue, cancelling with Esc, alt-tab or a missed release, keyboard use, and layout). With the site running locally, open http://localhost:9876/?lang=en, paste the file into the browser console, and wait about 40 seconds for the summary. Synthetic events can't reproduce every browser quirk, so also try a few drags with a real mouse.

## File-type showcase and the two numbers

The Features section has two stat cards and a tabbed showcase (`assets/js/showcase.js`), whose wheels are drawn live from option lists that mirror the app's `Catalog.cs`. `/?tab=video` opens a given tab (images, video, audio, documents, archives).

The numbers are counted, not estimated, so recount them when the catalog changes:

- **333 conversion options** = input-to-output format pairs across the app's 49 input formats, 145 of them Office conversions that need desktop Office. Non-Office pairs were checked against the app's own `--capabilities` output.
- **40+ advanced file tools** = the tool definitions in `Catalog.cs` and `Models.swift`.

`tests/showcase-tests.js` (10 checks) covers this section; run it the same way as `tests/demo-tests.js`.

`tests/wheel-ui-tests.js` (6 checks) covers the rounded geometry for 0, 1, 4, 6, 7, 8, 9 and 10 options: face/sidewall pairing, correct petal centres, the hub dead zone, gaps, rounded-off corners and selection styling. Also test native mouse drags on a face and in a gap, and touch taps in the showcase.

## Refreshing screenshots

The website images are real renders of the app, not recreated UI. `scripts/refresh-screenshots.py` captures the format wheel, tool wheel, trim window and progress cards in English, and rebuilds the social-share preview. It requires Pillow and a current portable app build. Pass `--app <DropDial.exe>`, `--video <sample.mp4>`, `--image <sample.png/jpg>` and `--render-dir <scratch folder>`. It opens and closes preview windows, writes intermediates only to the supplied scratch folder, and updates `assets/img`; it does not change the app repository.

After refreshing, bump image query versions in `index.html` as well as CSS/JS versions so visitors fetch the new assets.
