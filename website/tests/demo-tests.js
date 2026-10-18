// Automated checks for the drag-to-convert demo on index.html.
// Run: open the site (http://localhost:8765/?lang=en), then paste this file into the browser console.
// It drives the demo with pointer and keyboard events and prints PASS/FAIL per check.
// Synthetic events can't reproduce every browser quirk, so also try a few drags with a real mouse.
(async () => {
  const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const files = () => $$("#desk .file").map(b => b.dataset.name);
  const btn = name => $$("#desk .file").find(b => b.dataset.name === name);
  const isOpen = () => !$("#wheel-wrap").hidden;
  const labels = () => $$("#wheel .petal").map(p => p.getAttribute("aria-label"));
  const center = el => { const r = el.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; };
  function petal(index) {
    const box = $("#wheel-wrap").getBoundingClientRect(), scale = parseFloat(getComputedStyle($("#wheel")).width) / 380;
    const a = -Math.PI / 2 + index * 2 * Math.PI / labels().length;
    return [box.left + box.width / 2 + 126 * scale * Math.cos(a), box.top + box.height / 2 + 126 * scale * Math.sin(a)];
  }
  const hub = () => { const box = $("#wheel-wrap").getBoundingClientRect(); return [box.left + box.width / 2, box.top + box.height / 2]; };
  function pe(type, target, [x, y], init = {}) {
    target.dispatchEvent(new PointerEvent(type, { pointerId: 7, pointerType: "mouse", isPrimary: true, bubbles: true, cancelable: true, clientX: x, clientY: y, button: type === "pointermove" ? -1 : 0, buttons: type === "pointerup" ? 0 : 1, ...init }));
  }
  function start(name, keys) { const b = btn(name), c = center(b); pe("pointerdown", b, c, keys); pe("pointermove", b, [c[0] + 12, c[1] + 12], keys); return b; }
  function release(b, point) { pe("pointermove", b, point); pe("pointerup", b, point); }
  const idx = label => labels().indexOf(label);
  const esc = () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  // Quiet = no job running for a full second (covers the pause between queued jobs).
  async function idle() { let quiet = 0; while (quiet < 1000) { await wait(100); quiet = !$("#toast").hidden && $("#toast-bar").classList.contains("indeterminate") ? 0 : quiet + 100; } }
  const results = [];
  const expect = (cond, msg) => { if (!cond) throw new Error(msg); };
  async function test(name, fn) {
    try { await fn(); results.push("PASS " + name); } catch (e) { results.push("FAIL " + name + " :: " + e.message); }
    if (isOpen()) esc();
    pe("pointerup", document.body, [0, 0]);
  }
  if (document.documentElement.lang !== "en" && $("#lang-toggle")) $("#lang-toggle").click();
  $("#stage").dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })); // stop the automatic run
  await idle();

  await test("basic drag converts photo.png to JPG", async () => {
    const b = start("photo.png"); expect(isOpen(), "wheel did not open");
    expect(labels().join() === "JPG,WEBP,HEIC,TIFF,AVIF,BMP,PDF,DOCX", "formats " + labels());
    release(b, petal(idx("JPG"))); expect(!isOpen(), "wheel stayed open");
    await idle(); expect(files().includes("photo-converted.jpg"), "no output: " + files());
  });
  await test("drop during the opening animation hits the right petal", async () => {
    const b = start("song.wav"); release(b, petal(idx("FLAC"))); await idle(); expect(files().includes("song-converted.flac"), "got " + files());
  });
  await test("three quick drops all produce files (queue)", async () => {
    let b = start("trip.mp4"); release(b, petal(idx("MOV")));
    b = start("report.pdf"); release(b, petal(idx("TXT")));
    b = start("song.wav"); release(b, petal(idx("OGG")));
    expect(/2 more queued/.test($("#toast-time").textContent), "queue not shown: " + $("#toast-time").textContent);
    await idle();
    expect(["trip-converted.mov", "report-converted.txt", "song-converted.ogg"].every(n => files().includes(n)), "got " + files());
  });
  await test("releasing on the hub does nothing and explains why", async () => {
    const before = files().join(); const b = start("photo.png"); release(b, hub());
    await wait(1600); expect(files().join() === before, "file added"); expect(/outside the wheel/.test($("#demo-help").textContent), "help: " + $("#demo-help").textContent);
  });
  await test("releasing outside the wheel does nothing", async () => {
    const before = files().join(); const b = start("photo.png"); const s = $("#stage").getBoundingClientRect(); release(b, [s.left + 4, s.bottom - 4]);
    await wait(1600); expect(files().join() === before, "file added");
  });
  await test("pointer capture loss alone does not cancel (browsers send it before pointerup)", async () => {
    const b = start("photo.png"); const p = petal(idx("WEBP")); pe("pointermove", b, p);
    pe("lostpointercapture", b, p); expect(isOpen(), "closed on capture loss"); pe("pointerup", b, p);
    await idle(); expect(files().includes("photo-converted.webp"), "release after capture loss ignored: " + files());
  });
  await test("pointercancel closes the wheel and the next drag still works", async () => {
    const b = start("photo.png"); pe("pointercancel", b, center(b)); expect(!isOpen(), "still open");
    start("trip.mp4"); expect(isOpen() && labels()[0] === "MOV", "next drag broken");
  });
  await test("a release outside the page (move with no buttons) cancels", async () => {
    const b = start("photo.png"); pe("pointermove", b, petal(0), { buttons: 0 }); expect(!isOpen(), "still open");
  });
  await test("a new press always recovers from a drag whose release went missing", async () => {
    start("photo.png"); expect(isOpen(), "did not open");
    const b = start("trip.mp4"); expect(isOpen() && labels()[0] === "MOV", "new drag blocked by the old one");
    release(b, hub());
  });
  await test("Escape cancels the whole drag: moving and releasing afterwards does nothing", async () => {
    const before = files().join(); const b = start("photo.png"); const p = petal(0);
    pe("pointermove", b, p); esc(); expect(!isOpen(), "still open");
    pe("pointermove", b, [p[0] + 3, p[1]]); expect(!isOpen(), "reopened after Escape");
    pe("pointerup", b, p); await wait(1600); expect(files().join() === before, "converted after Escape");
    start("photo.png"); expect(isOpen(), "next drag after Escape does not open");
  });
  await test("alt-tab (window blur) cancels the drag, and the next drag works", async () => {
    const before = files().join(); const b = start("photo.png"); const p = petal(0);
    window.dispatchEvent(new Event("blur")); expect(!isOpen(), "still open");
    pe("pointermove", b, p); expect(!isOpen(), "reopened after blur"); pe("pointerup", b, p);
    await wait(1600); expect(files().join() === before, "converted after blur");
    start("photo.png"); expect(isOpen(), "cannot drag after blur");
  });
  await test("Ctrl+Shift opens tools; Shift pressed afresh returns to formats; adding Ctrl switches back", async () => {
    const b = start("trip.mp4", { shiftKey: true, ctrlKey: true }); expect(labels()[0] === "Compress", "not tools: " + labels());
    pe("pointermove", b, [500, 300]); pe("pointermove", b, [505, 300], { shiftKey: true }); expect(labels()[0] === "MOV", "did not switch back");
    pe("pointermove", b, [510, 300], { shiftKey: true, ctrlKey: true }); expect(labels()[0] === "Compress", "Ctrl did not switch to tools");
  });
  await test("a chord only affects that drag; the next plain drag uses the toggle", async () => {
    start("photo.png"); expect(labels()[0] === "JPG", "mode stuck: " + labels());
  });
  await test("tool drop explains the tool window and creates no file", async () => {
    const before = files().join(); const b = start("trip.mp4", { shiftKey: true, ctrlKey: true }); release(b, petal(idx("Trim")));
    await wait(1600); expect(files().join() === before, "file added"); expect(/Trim opens a tool window/.test($("#demo-help").textContent), "help: " + $("#demo-help").textContent);
  });
  await test("new output files can be dragged, with their own menu", async () => {
    const b = start("trip.mp4"); release(b, petal(idx("MOV"))); await idle();
    const name = files().filter(n => /^trip-converted(-\d+)?\.mov$/.test(n)).pop();
    expect(name, "no fresh .mov output: " + files());
    start(name); expect(isOpen(), "output not draggable");
    expect(labels().includes("MP4") && !labels().includes("MOV") && labels().includes("GIF"), "menu " + labels());
  });
  await test("extract → folder; folders can only be packed; tools show No actions", async () => {
    $("#mode-tools").click();
    let b = start("photos.zip"); expect(labels().join() === "Extract", "tools " + labels()); release(b, petal(0)); await idle();
    const folder = files().find(n => /^photos-extracted(-\d+)?$/.test(n)); expect(folder, "no folder " + files());
    $("#mode-formats").click();
    b = start(folder); expect(labels().join() === "Pack ZIP,Pack TAR,Pack GZIP,Pack RAR", "pack menu " + labels()); release(b, petal(idx("Pack ZIP"))); await idle();
    expect(files().some(n => n.startsWith(folder + "-packed") && n.endsWith(".zip")), "no packed zip " + files());
    if (btn(folder)) {
      b = start(folder); pe("pointermove", b, [500, 300], { shiftKey: true, ctrlKey: true });
      expect(labels().length === 0 && /No actions/.test($("#wheel").textContent), "expected No actions");
      release(b, hub()); expect(/No conversions/.test($("#demo-help").textContent), "help " + $("#demo-help").textContent);
    }
  });
  await test("desk never grows past 3 outputs", async () => { expect(files().length <= 8, "files: " + files().length); });
  await test("keyboard: Enter opens without choosing, arrows move, Enter converts", async () => {
    const b = btn("report.pdf"); b.focus();
    b.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })); expect(isOpen(), "did not open");
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })); expect($("#hub-hint").textContent === "JPG", "hint " + $("#hub-hint").textContent);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })); expect(!isOpen(), "still open");
    await idle(); expect(files().some(n => /^report-converted(-\d+)?\.jpg$/.test(n)), "got " + files());
  });
  await test("wheel labels mid-drag match English options", async () => {
    start("trip.mp4", { shiftKey: true, ctrlKey: true });
    if ($("#lang-toggle")) $("#lang-toggle").click();
    const l1 = labels()[0];
    if ($("#lang-toggle")) $("#lang-toggle").click();
    expect(l1 === "Compress" && labels()[0] === "Compress", "labels " + l1 + " / " + labels()[0]);
  });
  await test("layout: wheel above the progress card; only files block touch scrolling", async () => {
    expect(+getComputedStyle($("#wheel-wrap")).zIndex > +getComputedStyle($("#toast")).zIndex, "z-order");
    expect(getComputedStyle($("#stage")).touchAction === "auto" && getComputedStyle($(".file")).touchAction === "none", "touch-action");
  });
  await test("the demo still works at the end", async () => { start("song.wav"); expect(isOpen() && labels()[0] === "MP3", "final drag failed"); });

  const failed = results.filter(r => !r.startsWith("PASS"));
  console.log(results.join("\n"));
  console.log(`${results.length - failed.length}/${results.length} passed`);
  window.__demoTestResults = { passed: results.length - failed.length, total: results.length, failures: failed };
  return window.__demoTestResults;
})();
