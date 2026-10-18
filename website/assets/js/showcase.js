// File-type showcase: tabs, key caps and two live wheels per file type.
// The option lists mirror Catalog.cs for one sample file per type (the same rules the hero demo uses).
(() => {
  "use strict";
  const root = document.querySelector("#showcase");
  if (!root || !window.ZD || !window.ZD_SHOW) return;
  const $ = (sel, scope = root) => scope.querySelector(sel);
  const $$ = (sel, scope = root) => [...scope.querySelectorAll(sel)];
  const SVG = "http://www.w3.org/2000/svg";
  const wheelUI = window.ZD_WHEEL, C = wheelUI.CENTER;

  const CATS = {
    images:    { formats: ["png", "webp", "heic", "tiff", "avif", "bmp", "pdf", "docx"], tools: ["compress", "removeMetadata", "editImage", "frameImage", "cropImage", "redactImage"] },
    video:     { formats: ["mov", "mkv", "webm", "avi", "wmv", "gif", "mp3"], tools: ["compress", "removeMetadata", "muteVideo", "trimVideo", "cropVideo", "changeVideoSpeed", "videoSnapshots", "splitVideo", "redactVideo"] },
    audio:     { formats: ["mp3", "m4a", "flac", "ogg", "opus", "aiff", "wma"], tools: ["compress", "removeMetadata", "normalizeAudio", "audioToVideo", "trimAudio", "audioChannels", "redactAudio"] },
    documents: { formats: ["docx", "jpg", "png", "txt"], tools: ["compress", "removeMetadata", "splitPDF", "organizePDF"] },
    // A folder can only be packed; a ZIP archive offers Extract.
    archives:  { formats: ["zip", "tar", "gz", "rar"], pack: true, tools: ["extractArchive"] }
  };
  const order = Object.keys(CATS);
  // /?tab=video opens the Video tab, so a direct link to a file type works.
  const requested = new URLSearchParams(location.search).get("tab");
  let cat = order.includes(requested) ? requested : "images";

  const fmtName = f => f === "gz" ? "GZIP" : f.toUpperCase();
  const polar = wheelUI.polar;
  function node(name, attrs, parent) {
    const el = document.createElementNS(SVG, name);
    for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
    parent.appendChild(el);
    return el;
  }
  // Draws a wheel and makes it respond to hover, tap and arrow keys. `caption(i)` gives the text under the wheel.
  function wheel(svg, labels, hubTitle, caption, captionEl, ariaLabel) {
    const layers = wheelUI.base(svg);
    svg.setAttribute("aria-label", ariaLabel);
    const n = labels.length, petals = [];
    labels.forEach((text, i) => {
      petals.push(wheelUI.petal(layers, i, n).face);
      const [lx, ly] = polar(119, -Math.PI / 2 + i * 2 * Math.PI / n);
      const label = node("text", { class: "label" + (n > 7 ? " small" : ""), x: lx, y: ly }, svg);
      const words = text.split(" ");
      if (words.length > 1 && text.length > 9) {
        const cut = Math.ceil(words.length / 2);
        node("tspan", { x: lx, dy: "-0.55em" }, label).textContent = words.slice(0, cut).join(" ");
        node("tspan", { x: lx, dy: "1.15em" }, label).textContent = words.slice(cut).join(" ");
      } else label.textContent = text;
    });
    wheelUI.hub(svg);
    node("text", { class: "hub-title", x: C, y: C - 2 }, svg).textContent = hubTitle;
    const hint = node("text", { class: "hub-hint", x: C, y: C + 20 }, svg);

    let current = -1;
    const set = i => {
      if (i === current) return;
      current = i;
      wheelUI.select(svg, i);
      hint.textContent = labels[i];
      captionEl.textContent = caption(i);
    };
    petals.forEach((p, i) => {
      p.addEventListener("pointerenter", () => set(i));
      p.addEventListener("click", () => set(i));
    });
    svg.onkeydown = e => {
      if (e.key === "ArrowRight" || e.key === "ArrowDown") { e.preventDefault(); set((current + 1) % n); }
      else if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); set((current - 1 + n) % n); }
    };
    set(0);
  }

  function render() {
    const lang = window.ZD.lang, t = window.ZD_SHOW[lang], d = window.ZD_DEMO[lang], c = CATS[cat];
    for (const tab of $$(".tab")) {
      const k = tab.dataset.cat, selected = k === cat;
      $("span", tab).textContent = t.cats[k].tab;
      tab.setAttribute("aria-selected", String(selected));
      tab.tabIndex = selected ? 0 : -1;
    }
    $("#show-panel").setAttribute("aria-labelledby", "tab-" + cat);
    $("#show-title").textContent = t.cats[cat].title;
    $("#show-desc").textContent = t.cats[cat].desc;
    $("#show-fmt-label").textContent = c.pack ? t.pack : t.convert;
    $("#show-tools-label").textContent = t.tools;

    const fmtLabels = c.formats.map(f => c.pack ? d.pack(fmtName(f)) : fmtName(f));
    wheel($("#show-wheel-fmt"), fmtLabels, t.file, i => c.pack ? t.packAs(fmtName(c.formats[i])) : t.convertTo(fmtName(c.formats[i])), $("#show-fmt-cap"), t.fmtAria(t.sources[cat], fmtLabels.join(", ")));
    const toolLabels = c.tools.map(id => d.tools[id]);
    wheel($("#show-wheel-tools"), toolLabels, t.file, i => toolLabels[i], $("#show-tools-cap"), t.toolsAria(t.toolsSources[cat] || t.sources[cat], toolLabels.join(", ")));
  }

  function select(next, focus) {
    if (next === cat) return;
    cat = next;
    render();
    if (focus) $("#tab-" + cat).focus();
  }
  $$(".tab").forEach(tab => {
    tab.addEventListener("click", () => select(tab.dataset.cat));
    tab.addEventListener("keydown", e => {
      const i = order.indexOf(cat);
      const target = e.key === "ArrowRight" ? order[(i + 1) % order.length]
        : e.key === "ArrowLeft" ? order[(i - 1 + order.length) % order.length]
        : e.key === "Home" ? order[0] : e.key === "End" ? order[order.length - 1] : null;
      if (target) { e.preventDefault(); select(target, true); }
    });
  });

  window.ZD.onLanguage(render);
})();
