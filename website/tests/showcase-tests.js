// Automated checks for the file-type showcase (stats, tabs and the two wheels) on index.html.
// Run: open the site (http://localhost:8765/?lang=en), paste this file into the browser console.
// It prints PASS/FAIL per check and leaves the summary in window.__showcaseTestResults.
(async () => {
  const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];
  const results = [];
  const expect = (cond, msg) => { if (!cond) throw new Error(msg); };
  async function test(name, fn) {
    try { await fn(); results.push("PASS " + name); } catch (e) { results.push("FAIL " + name + " :: " + e.message); }
  }
  const tab = k => $("#tab-" + k);
  // Two-line labels are split into tspans, so join their lines with a space.
  const labels = id => $$(id + " .label").map(l => l.querySelector("tspan") ? [...l.querySelectorAll("tspan")].map(t => t.textContent).join(" ") : l.textContent.trim());
  const petals = id => $$(id + " .petal");
  const FMT = "#show-wheel-fmt", TOOLS = "#show-wheel-tools";
  const key = (el, k) => el.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true }));
  const hover = el => el.dispatchEvent(new PointerEvent("pointerenter", { bubbles: false }));
  const lang = () => document.documentElement.lang;
  if (lang() !== "en" && $("#lang-toggle")) $("#lang-toggle").click();
  tab("images").click();

  await test("stats show the counted numbers", () => {
    expect($$(".stat b").map(b => b.textContent).join() === "333,27", "got " + $$(".stat b").map(b => b.textContent));
  });
  await test("default tab is Images with 8 formats and 6 tools", () => {
    expect(tab("images").getAttribute("aria-selected") === "true", "Images not selected");
    expect($("#show-title").textContent === "Image tools", "title " + $("#show-title").textContent);
    expect(labels(FMT).join() === "PNG,WEBP,HEIC,TIFF,AVIF,BMP,PDF,DOCX", "formats " + labels(FMT));
    expect(labels(TOOLS).join() === "Compress,Metadata,Edit image,Add background,Crop,Redact", "tools " + labels(TOOLS));
    expect($("#show-fmt-cap").textContent === "Convert to PNG" && $("#show-tools-cap").textContent === "Compress", "captions");
  });
  await test("petal counts for every tab match the catalog", () => {
    const want = { images: [8, 6], video: [7, 9], audio: [7, 7], documents: [4, 4], archives: [4, 1] };
    for (const [k, [f, t]] of Object.entries(want)) {
      tab(k).click();
      expect(petals(FMT).length === f && petals(TOOLS).length === t, `${k}: ${petals(FMT).length}/${petals(TOOLS).length}, expected ${f}/${t}`);
    }
  });
  await test("only the selected tab is in the tab order, and the panel follows it", () => {
    tab("video").click();
    expect($$(".tab").filter(t => t.tabIndex === 0).map(t => t.id).join() === "tab-video", "tab order");
    expect($("#show-panel").getAttribute("aria-labelledby") === "tab-video", "panel label");
    expect($("#show-title").textContent === "Video tools", "title");
  });
  await test("archives: pack wheel for a folder, single-option Extract ring for an archive", () => {
    tab("archives").click();
    expect($("#show-fmt-label").textContent === "Pack files", "label " + $("#show-fmt-label").textContent);
    expect(labels(FMT).join() === "Pack ZIP,Pack TAR,Pack GZIP,Pack RAR", "pack " + labels(FMT));
    expect($("#show-fmt-cap").textContent === "Pack as ZIP", "pack caption");
    expect(labels(TOOLS).join() === "Extract" && $("#show-tools-cap").textContent === "Extract", "extract");
    const path = petals(TOOLS)[0];
    expect(path.getAttribute("d").includes("Q") && path.getAttribute("d").includes("A172 172 0 1 1"), "rounded single-option path");
    expect(path.isPointInFill(new DOMPoint(190, 71)) && !path.isPointInFill(new DOMPoint(190, 190)), "single-option fill and centre hole");
    tab("images").click();
    expect($("#show-fmt-label").textContent === "Convert formats", "label did not return");
  });
  await test("hovering and tapping a petal updates highlight, hub and caption", () => {
    tab("video").click();
    hover(petals(FMT)[1]);
    expect(petals(FMT)[1].classList.contains("on") && !petals(FMT)[0].classList.contains("on"), "highlight");
    expect($(FMT + " .hub-hint").textContent === "MKV" && $("#show-fmt-cap").textContent === "Convert to MKV", "hub/caption");
    petals(TOOLS)[3].dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect($("#show-tools-cap").textContent === "Trim", "tool caption " + $("#show-tools-cap").textContent);
    expect($$(TOOLS + " .petal.on").length === 1, "more than one highlighted");
  });
  await test("wheel arrow keys cycle the highlight and wrap around", () => {
    tab("audio").click();
    const w = $(FMT);
    key(w, "ArrowLeft"); expect($("#show-fmt-cap").textContent === "Convert to WMA", "left from first -> " + $("#show-fmt-cap").textContent);
    key(w, "ArrowRight"); expect($("#show-fmt-cap").textContent === "Convert to MP3", "right wraps -> " + $("#show-fmt-cap").textContent);
    key(w, "ArrowDown"); expect($("#show-fmt-cap").textContent === "Convert to M4A", "down");
  });
  await test("tab keyboard: arrows move and select, Home and End jump", () => {
    tab("images").click(); tab("images").focus();
    key(tab("images"), "ArrowRight"); expect(tab("video").getAttribute("aria-selected") === "true" && document.activeElement === tab("video"), "right");
    key(tab("video"), "ArrowLeft"); key(tab("images"), "ArrowLeft");
    expect(tab("archives").getAttribute("aria-selected") === "true", "left wraps to Archives");
    key(tab("archives"), "Home"); expect(tab("images").getAttribute("aria-selected") === "true", "Home");
    key(tab("images"), "End"); expect(tab("archives").getAttribute("aria-selected") === "true", "End");
    tab("images").click();
  });
  await test("tabs, wheels, captions and aria text in English", () => {
    tab("video").click();
    if ($("#lang-toggle")) $("#lang-toggle").click();
    expect($$(".tab span").map(s => s.textContent).join() === "Images,Video,Audio,Documents,Archives", "tabs " + $$(".tab span").map(s => s.textContent));
    expect($("#show-title").textContent === "Video tools" && $("#show-fmt-cap").textContent === "Convert to MOV", "title/caption");
    expect(labels(TOOLS)[0] === "Compress" && labels(FMT)[0] === "MOV", "wheel labels");
    expect($(TOOLS).getAttribute("aria-label").startsWith("Tool menu for an MP4 video"), "aria " + $(TOOLS).getAttribute("aria-label"));
    expect($$(".stat h3").map(h => h.textContent).includes("Conversion options") && $$(".stat h3").map(h => h.textContent).includes("Advanced file tools"), "stat labels");
    if ($("#lang-toggle")) $("#lang-toggle").click();
    expect(lang() === "en" && $("#show-title").textContent === "Video tools" && labels(TOOLS)[0] === "Compress", "did not return to English");
    tab("images").click();
  });
  await test("the page does not scroll sideways", () => {
    expect(document.documentElement.scrollWidth <= innerWidth + 1, `${document.documentElement.scrollWidth} > ${innerWidth}`);
  });

  const failed = results.filter(r => !r.startsWith("PASS"));
  console.log(results.join("\n"));
  console.log(`${results.length - failed.length}/${results.length} passed`);
  window.__showcaseTestResults = { passed: results.length - failed.length, total: results.length, failures: failed };
  return window.__showcaseTestResults;
})();
