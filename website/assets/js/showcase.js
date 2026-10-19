// File-type showcase: tabs, key caps, interactive live wheels with spring rotation, and category cards.
// Supports all 10 categories: Images, Video, Audio, PDF, Documents, Slides, Spreadsheets, EPUB, Subtitles, Archives.
(() => {
  "use strict";
  const root = document.querySelector("#showcase");
  if (!root || !window.ZD || !window.ZD_SHOW) return;
  const $ = (sel, scope = root) => scope.querySelector(sel);
  const $$ = (sel, scope = root) => [...scope.querySelectorAll(sel)];
  const SVG = "http://www.w3.org/2000/svg";
  const wheelUI = window.ZD_WHEEL, C = wheelUI.CENTER;

  function iconSvg(name) {
    const paths = {
      shrink: `<path d="M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7"/>`,
      frame: `<rect x="3" y="3" width="18" height="18" rx="3"/><rect x="7" y="7" width="10" height="10" rx="1.5"/>`,
      shield: `<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>`,
      sliders: `<line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/>`,
      eye: `<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>`,
      refresh: `<polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>`,
      scissors: `<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><line x1="20" y1="4" x2="8.12" y2="15.88"/><line x1="14.47" y1="14.48" x2="20" y2="20"/><line x1="8.12" y1="8.12" x2="12" y2="12"/>`,
      crop: `<path d="M6.13 1L6 16a2 2 0 0 0 2 2h15"/><path d="M1 6.13L16 6a2 2 0 0 1 2 2v15"/>`,
      volume: `<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>`,
      gauge: `<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>`,
      music: `<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>`,
      video: `<polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/>`,
      headphones: `<path d="M3 18v-6a9 9 0 0 1 18 0v6"/><path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/>`,
      files: `<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/>`,
      split: `<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="12" y1="3" x2="12" y2="21"/>`,
      stack: `<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>`,
      image: `<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/>`,
      doc: `<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/>`,
      share: `<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/>`,
      edit: `<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>`,
      slides: `<rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>`,
      table: `<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="3" x2="9" y2="21"/><line x1="15" y1="3" x2="15" y2="21"/>`,
      sheet: `<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="8" y1="13" x2="16" y2="13"/><line x1="8" y1="17" x2="16" y2="17"/><line x1="12" y1="11" x2="12" y2="19"/>`,
      book: `<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>`,
      subtitles: `<rect x="2" y="4" width="20" height="16" rx="3"/><line x1="6" y1="14" x2="10" y2="14"/><line x1="14" y1="14" x2="18" y2="14"/><line x1="6" y1="10" x2="18" y2="10"/>`,
      clean: `<path d="M12 2l2.4 7.2L21.6 12l-7.2 2.4L12 21.6l-2.4-7.2L2.4 12l7.2-2.4z"/>`,
      globe: `<circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>`,
      archive: `<polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/>`,
      unarchive: `<polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="12" y1="17" x2="12" y2="11"/><polyline points="9 14 12 11 15 14"/>`
    };
    return `<svg viewBox="0 0 24 24">${paths[name] || paths.doc}</svg>`;
  }

  const CATS = {
    images: {
      duo: true,
      hub: "photo.jpg",
      formats: ["png", "webp", "heic", "tiff", "avif", "bmp", "pdf", "docx", "ico"],
      initialFmt: "png",
      tools: ["compress", "removeMetadata", "editImage", "frameImage", "cropImage", "redactImage", "watermark", "rotateImage", "resizeImage", "ocrImage"],
      initialTool: "compress",
      cards: [
        { title: "Convert & compress images", desc: "Compress JPG, PNG, and WebP images to exact target file sizes without noticeable visual degradation.", icon: "shrink" },
        { title: "Smart crop & frame", desc: "Add rounded mockups, colored backdrops, drop shadows, and standard aspect ratios for social sharing.", icon: "frame" },
        { title: "Redact sensitive data", desc: "Permanently blur or black out phone numbers, addresses, faces, and private text in documents or photos.", icon: "shield" },
        { title: "Adjust colour & tone", desc: "Fine-tune exposure, contrast, saturation, and color temperature on device in real time.", icon: "sliders" },
        { title: "Strip EXIF metadata", desc: "Remove GPS location coordinates, camera models, serial numbers, and creator tags before uploading.", icon: "eye" },
        { title: "Format conversion", desc: "Convert between modern AVIF, HEIC, WebP, PNG, JPG, TIFF, and Windows BMP formats instantly.", icon: "refresh" }
      ]
    },
    video: {
      duo: true,
      hub: "sample.mov",
      formats: ["mp4", "mkv", "webm", "avi", "wmv", "gif", "mp3", "m4a", "wav"],
      initialFmt: "mp4",
      tools: ["compress", "removeMetadata", "muteVideo", "trimVideo", "cropVideo", "changeVideoSpeed", "videoSnapshots", "splitVideo", "redactVideo", "watermark", "videoEffects", "videoToGif", "rotateVideo"],
      initialTool: "compress",
      cards: [
        { title: "Video compressor", desc: "Shrink large 4K and 1080p recordings into compact MP4 or WebM files optimized for email, Discord, or web.", icon: "shrink" },
        { title: "Trim & cut clips", desc: "Losslessly slice video clips with millisecond precision and instant keyframe seek previews.", icon: "scissors" },
        { title: "Crop aspect ratios", desc: "Crop video to 16:9 widescreen, 9:16 vertical reels, 1:1 square, or custom pixel boundaries.", icon: "crop" },
        { title: "Mute & extract audio", desc: "Strip unwanted background noise and audio tracks, or extract high-fidelity MP3/M4A sound files.", icon: "volume" },
        { title: "Change speed", desc: "Speed up lectures to 2× or slow down action clips to 0.5× with clean pitch correction.", icon: "gauge" },
        { title: "Redact video", desc: "Anonymize video with moving blur, mosaic, or solid black bars over faces and credentials.", icon: "shield" }
      ]
    },
    audio: {
      duo: true,
      hub: "recording.mp3",
      formats: ["m4a", "wav", "flac", "ogg", "opus", "aiff", "wma", "aac", "mp3"],
      initialFmt: "m4a",
      tools: ["compress", "removeMetadata", "normalizeAudio", "audioToVideo", "trimAudio", "audioChannels", "redactAudio", "ringtone", "audioEffects"],
      initialTool: "compress",
      cards: [
        { title: "Lossless & lossy audio", desc: "Convert between bit-perfect FLAC, studio WAV, Apple AIFF, high-clarity Opus, AAC, and MP3.", icon: "music" },
        { title: "Volume normalization", desc: "Normalize uneven podcast and voice recordings to broadcast EBU R128 standards (-14 to -23 LUFS).", icon: "sliders" },
        { title: "Trim & ringtones", desc: "Cut recordings with live waveform scrub and export custom iPhone M4R and Android ringtones.", icon: "scissors" },
        { title: "Waveform video", desc: "Generate an animated soundwave video with custom backgrounds ready to publish to YouTube or Instagram.", icon: "video" },
        { title: "Channel downmix", desc: "Convert stereo recordings to centered mono or isolate left/right audio channels.", icon: "headphones" },
        { title: "Strip tags", desc: "Purge embedded ID3 artist tags, comments, album artwork, and metadata.", icon: "eye" }
      ]
    },
    pdf: {
      duo: true,
      hub: "report.pdf",
      fmtLabel: "Convert PDF",
      toolsLabel: "PDF tools",
      formats: ["docx", "pages", "pptx", "xlsx", "jpg", "png", "epub", "txt", "md"],
      initialFmt: "xlsx",
      fmtCaptions: {
        xlsx: "XLSX: Convert PDF tables into formatted Microsoft Excel worksheets",
        docx: "DOCX: Convert PDF documents into editable Microsoft Word files",
        pptx: "PPTX: Convert PDF slides into editable Microsoft PowerPoint presentations",
        pages: "PAGES: Convert PDF into native Apple Pages documents",
        epub: "EPUB: Convert PDFs into reflowable electronic publications",
        txt: "TXT: Extract clean text without layout codes",
        md: "MD: Extract structured Markdown with headings and tables",
        jpg: "JPG: Save pages as compressed JPEG images",
        png: "PNG: Save pages as crisp lossless PNG images"
      },
      tools: ["compress", "removeMetadata", "splitPDF", "organizePDF"],
      initialTool: "splitPDF",
      toolCaptions: {
        splitPDF: "Split: Extract selected page ranges or burst all pages into separate PDFs",
        compress: "Compress: Reduce PDF size to web or email threshold without vector degradation",
        removeMetadata: "Metadata: Strip author tags, revision history, and GPS metadata",
        organizePDF: "Organize: Reorder, rotate, reverse, or delete individual pages"
      },
      cards: [
        { title: "Compress PDFs", desc: "Reduce oversized PDF files to a target megabyte threshold or lightweight web-ready resolution without corrupting vector line art.", icon: "shrink" },
        { title: "Merge PDFs", desc: "Combine multiple PDF documents, reports, or chapters into a single unified binder with customizable page order.", icon: "files" },
        { title: "Split pages", desc: "Extract specific page intervals, separate even and odd pages, or burst an entire publication into single-page documents.", icon: "split" },
        { title: "Organize pages", desc: "Rotate crooked scans, reorder pages, reverse order, or delete unwanted cover and blank pages in seconds.", icon: "stack" },
        { title: "Save pages as images", desc: "Export every page or selected spreads as crisp high-resolution PNG, JPG, or TIFF images.", icon: "image" },
        { title: "Extract text and Markdown", desc: "Extract text layers, headers, and structured tables directly into formatted Markdown or clean UTF-8 text.", icon: "doc" }
      ]
    },
    documents: {
      duo: false,
      hub: "document.docx",
      formats: ["pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"],
      initialFmt: "pages",
      fmtCaptions: {
        pages: "PAGES: Convert Microsoft Word or RTF files directly into native Apple Pages documents",
        pdf: "PDF: Export documents into printable vector PDF files",
        txt: "TXT: Extract plain text without styles or layout",
        md: "MD: Convert document formatting into clean Markdown",
        html: "HTML: Export rich documents as clean, semantic HTML5",
        epub: "EPUB: Turn document manuscripts into standard digital books",
        png: "PNG: Render pages as high-resolution raster images",
        jpg: "JPG: Render document pages as compressed JPEG previews"
      },
      cards: [
        { title: "Convert Word and Pages", desc: "Convert Word DOCX to native Apple Pages documents and vice versa with preserved typography and layouts.", icon: "doc" },
        { title: "Export documents", desc: "Export rich documents to PDF, clean web HTML, or publication-ready EPUB files in one gesture.", icon: "share" },
        { title: "Import rich text", desc: "Turn plain Markdown or raw text into beautifully styled documents or portable PDFs instantly.", icon: "edit" }
      ]
    },
    slides: {
      duo: false,
      hub: "deck.pptx",
      formats: ["pdf", "jpg", "png"],
      initialFmt: "pdf",
      fmtCaptions: {
        pdf: "PDF: Export slides to high-resolution vector PDF presentations",
        jpg: "JPG: Export presentation slides as high-resolution JPEG images",
        png: "PNG: Export presentation slides as transparent PNG images"
      },
      cards: [
        { title: "Export slides", desc: "Save presentations as high-resolution PNG or JPG slides ready for social decks and web sharing.", icon: "image" },
        { title: "PDF to PowerPoint", desc: "Convert vector PDF slide decks back into editable Microsoft PowerPoint presentations.", icon: "slides" }
      ]
    },
    spreadsheets: {
      duo: false,
      hub: "sheet.xlsx",
      formats: ["ods", "csv", "tsv", "pdf"],
      initialFmt: "ods",
      fmtCaptions: {
        ods: "ODS: Convert Excel spreadsheets to OpenDocument Spreadsheet format",
        csv: "CSV: Export tabular data as comma-separated values",
        tsv: "TSV: Export tabular data as tab-separated values",
        pdf: "PDF: Render paginated printable spreadsheet tables in vector PDF"
      },
      cards: [
        { title: "Convert spreadsheets", desc: "Switch freely between XLSX, OpenDocument Spreadsheet (ODS), and comma-delimited CSV formats.", icon: "table" },
        { title: "Export as PDF", desc: "Render crisp paginated financial reports and tabular sheets into printable PDF documents.", icon: "doc" },
        { title: "PDF to Excel", desc: "Parse tabular data and financial statements from PDF files directly into structured Excel worksheets.", icon: "sheet" }
      ]
    },
    epub: {
      duo: false,
      hub: "book.epub",
      formats: ["pdf", "docx", "pages", "txt", "md", "html"],
      initialFmt: "pdf",
      fmtCaptions: {
        pdf: "PDF: Convert e-books to printable, paginated PDF documents",
        docx: "DOCX: Extract EPUB chapters into formatted Word documents",
        pages: "PAGES: Extract EPUB into native Apple Pages documents",
        txt: "TXT: Extract clean e-book manuscript text",
        md: "MD: Convert e-book chapters into formatted Markdown",
        html: "HTML: Extract e-book chapters as clean web HTML pages"
      },
      cards: [
        { title: "Convert an EPUB", desc: "Extract EPUB chapters into formatted Word documents, Markdown manuscripts, or clean HTML.", icon: "book" },
        { title: "PDF to EPUB", desc: "Convert document PDFs and manuscripts into standard EPUB files for Apple Books and Kindle.", icon: "doc" }
      ]
    },
    subtitles: {
      duo: false,
      hub: "captions.srt",
      formats: ["vtt", "txt"],
      initialFmt: "vtt",
      fmtCaptions: {
        vtt: "Convert to VTT",
        txt: "Extract subtitle text"
      },
      cards: [
        { title: "Convert subtitles", desc: "Switch between SRT and VTT while keeping the cue timing.", icon: "subtitles" },
        { title: "Extract subtitle text", desc: "Save the subtitle words as a plain TXT file.", icon: "doc" }
      ]
    },
    archives: {
      duo: true,
      hub: "archive.zip",
      fmtLabel: "Convert formats",
      toolsLabel: "File tools",
      formats: ["tar", "gz"],
      initialFmt: "tar",
      fmtCaptions: {
        tar: "Convert to TAR",
        gz: "Convert to GZIP"
      },
      tools: ["extractArchive"],
      initialTool: "extractArchive",
      toolCaptions: {
        extractArchive: "Extract Archive"
      },
      cards: [
        { title: "Extract archives", desc: "Unpack ZIP, TAR, GZIP, and RAR files into a folder beside the original.", icon: "unarchive" },
        { title: "Convert archives", desc: "Convert archives to ZIP, TAR, or GZIP. RAR files can be imported.", icon: "archive" }
      ]
    }
  };

  const order = Object.keys(CATS);
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

  // Interactive wheel with rotary physics and paging when full (> 8 items).
  function wheel(svg, rotateBarEl, allLabels, hubDefault, captionFn, captionEl, ariaLabel, options = {}) {
    svg.setAttribute("aria-label", ariaLabel);

    const totalCount = allLabels.length;
    const isFull = totalCount > 8;
    const pageSize = 8;
    const totalSides = Math.ceil(totalCount / pageSize);

    let initialIdx = options.initialIndex != null ? options.initialIndex : 0;
    if (initialIdx < 0 || initialIdx >= totalCount) initialIdx = 0;

    let currentSide = Math.floor(initialIdx / pageSize);
    let currentLocal = initialIdx % pageSize;

    function renderCurrentSide(fromAngle = 0) {
      const layers = wheelUI.base(svg);
      const start = currentSide * pageSize;
      const end = Math.min(start + pageSize, totalCount);
      const pageLabels = allLabels.slice(start, end);
      const n = pageLabels.length;

      const petals = [];
      pageLabels.forEach((text, i) => {
        petals.push(wheelUI.petal(layers, i, n).face);
        const [lx, ly] = polar(119, -Math.PI / 2 + i * 2 * Math.PI / n);
        if (n === 1 && text === "EXTRACT") {
          const iconG = node("g", { transform: `translate(${lx - 10} ${ly - 22})`, fill: "none", stroke: "currentColor", "stroke-width": "2", class: "petal-icon", "pointer-events": "none" }, layers.rotator);
          iconG.innerHTML = `<polyline points="16 7 16 16 4 16 4 7"/><rect x="2" y="3" width="16" height="4" rx="1"/><line x1="10" y1="13" x2="10" y2="7"/><polyline points="7 9 10 6 13 9"/>`;
          const label = node("text", { class: "label", x: lx, y: ly + 14 }, layers.rotator);
          label.textContent = text;
        } else {
          const label = node("text", { class: "label" + (n > 7 ? " small" : ""), x: lx, y: ly }, layers.rotator);
          const words = text.split(" ");
          if (words.length > 1 && text.length >= 8) {
            const cut = Math.ceil(words.length / 2);
            node("tspan", { x: lx, dy: "-0.55em" }, label).textContent = words.slice(0, cut).join(" ");
            node("tspan", { x: lx, dy: "1.15em" }, label).textContent = words.slice(cut).join(" ");
          } else {
            label.textContent = text;
          }
        }
      });

      wheelUI.hub(svg);
      const hubTitleEl = node("text", { class: "hub-title", x: C, y: C + 5 }, svg);

      function setItem(localIdx) {
        currentLocal = localIdx;
        wheelUI.select(svg, localIdx);
        const globalIdx = currentSide * pageSize + localIdx;
        const activeLabel = pageLabels[localIdx];
        hubTitleEl.textContent = activeLabel;
        if (captionEl) {
          captionEl.textContent = captionFn(globalIdx);
        }
      }

      petals.forEach((p, i) => {
        p.addEventListener("pointerenter", () => setItem(i));
        p.addEventListener("click", () => setItem(i));
      });

      svg.onkeydown = e => {
        if (e.key === "ArrowRight" || e.key === "ArrowDown") {
          e.preventDefault();
          if (currentLocal + 1 < n) {
            setItem(currentLocal + 1);
          } else if (isFull) {
            rotateSide(true);
          } else {
            setItem(0);
          }
        } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
          e.preventDefault();
          if (currentLocal - 1 >= 0) {
            setItem(currentLocal - 1);
          } else if (isFull) {
            rotateSide(false);
          } else {
            setItem(n - 1);
          }
        } else if (e.key === "PageDown" && isFull) {
          e.preventDefault();
          rotateSide(true);
        } else if (e.key === "PageUp" && isFull) {
          e.preventDefault();
          rotateSide(false);
        }
      };

      if (fromAngle !== 0) {
        wheelUI.spin(layers.rotator, fromAngle, 0);
      }

      if (currentLocal >= n) currentLocal = 0;
      setItem(currentLocal);

      // Side rotation control bar - visible only when full (> 8 items)
      if (rotateBarEl) {
        if (isFull) {
          rotateBarEl.style.display = "inline-flex";
          rotateBarEl.innerHTML = `
            <button type="button" class="wheel-rotate-btn prev" aria-label="Previous side">‹</button>
            <span><span class="wheel-rotate-icon">↻</span> Side ${currentSide + 1} of ${totalSides} · scroll to rotate</span>
            <button type="button" class="wheel-rotate-btn next" aria-label="Next side">›</button>
          `;
          const prevBtn = rotateBarEl.querySelector(".prev");
          const nextBtn = rotateBarEl.querySelector(".next");
          if (prevBtn) prevBtn.onclick = () => rotateSide(false);
          if (nextBtn) nextBtn.onclick = () => rotateSide(true);
        } else {
          rotateBarEl.style.display = "none";
          rotateBarEl.innerHTML = "";
        }
      }

      // Wheel mouse & trackpad scroll listener: spins and rotates sides ONLY when full (> 8 items)
      let scrollAccumulator = 0;
      svg.onwheel = e => {
        if (!isFull) return; // Only rotate when wheel is full (> 8 items)!
        e.preventDefault();
        const delta = e.deltaX !== 0 ? e.deltaX : -e.deltaY;
        scrollAccumulator += delta;
        const step = 20;
        if (Math.abs(scrollAccumulator) >= step) {
          const forward = scrollAccumulator > 0;
          scrollAccumulator = 0;
          rotateSide(forward);
        }
      };

      // Pointer drag rotation ONLY when full (> 8 items)
      let isDragging = false;
      let startAngle = 0;
      let dragDelta = 0;
      svg.onpointerdown = e => {
        if (!isFull) return; // Only drag-rotate when wheel is full (> 8 items)!
        if (e.button !== 0) return;
        const rect = svg.getBoundingClientRect();
        const cx = rect.left + rect.width / 2;
        const cy = rect.top + rect.height / 2;
        const r = Math.hypot(e.clientX - cx, e.clientY - cy);
        if (r < 50 * (rect.width / 380) || r > 185 * (rect.width / 380)) return;
        isDragging = true;
        startAngle = Math.atan2(e.clientY - cy, e.clientX - cx);
        dragDelta = 0;
        svg.setPointerCapture(e.pointerId);
      };
      svg.onpointermove = e => {
        if (!isDragging || !isFull) return;
        const rect = svg.getBoundingClientRect();
        const cx = rect.left + rect.width / 2;
        const cy = rect.top + rect.height / 2;
        const curAngle = Math.atan2(e.clientY - cy, e.clientX - cx);
        let diff = curAngle - startAngle;
        while (diff > Math.PI) diff -= Math.PI * 2;
        while (diff < -Math.PI) diff += Math.PI * 2;
        dragDelta += diff;
        startAngle = curAngle;
        if (Math.abs(dragDelta) >= 0.45) { // ~26 deg rotation gesture
          const forward = dragDelta > 0;
          dragDelta = 0;
          rotateSide(forward);
        }
      };
      svg.onpointerup = svg.onpointercancel = e => {
        if (isDragging) {
          isDragging = false;
          try { svg.releasePointerCapture(e.pointerId); } catch (_) {}
        }
      };
    }

    function rotateSide(forward) {
      currentSide = forward ? (currentSide + 1) % totalSides : (currentSide - 1 + totalSides) % totalSides;
      currentLocal = 0;
      renderCurrentSide(forward ? 120 : -120);
    }

    renderCurrentSide(0);
  }

  const ACTIONS = [
    { label: "AIRDROP", title: "AirDrop", desc: "Share files through native Apple AirDrop or recipient picker" },
    { label: "FLOAT", title: "Float", desc: "Keep files in a floating shelf at screen edge to batch and drop across apps" },
    { label: "COPY", title: "Copy", desc: "Copy files directly to your clipboard, ready to paste in Finder or Explorer" },
    { label: "MOVE", title: "Move", desc: "Choose a destination folder and move originals without extra open windows" },
    { label: "COPY PATH", title: "Copy Path", desc: "Copy clean absolute file paths or POSIX terminal paths to your clipboard" },
    { label: "TERMINAL", title: "Terminal", desc: "Open Terminal, iTerm2, or PowerShell at the file's current directory" },
    { label: "STRIP EXIF", title: "Strip EXIF", desc: "Remove camera settings, GPS location, and privacy metadata" },
    { label: "REVEAL", title: "Reveal", desc: "Highlight and reveal the file in Finder or Windows Explorer" }
  ];

  function renderActionsWheel() {
    const actionsSvg = document.querySelector("#actions-wheel");
    const actionsCap = document.querySelector("#actions-cap");
    if (!actionsSvg || !actionsCap) return;
    const actionLabels = ACTIONS.map(a => a.label);
    wheel(
      actionsSvg,
      null,
      actionLabels,
      "1 file",
      i => `${ACTIONS[i].title}: ${ACTIONS[i].desc}`,
      actionsCap,
      "Universal file actions wheel",
      { initialIndex: 0 }
    );
  }

  function render() {
    const lang = window.ZD.lang, t = window.ZD_SHOW[lang], d = window.ZD_DEMO[lang], c = CATS[cat];

    // Tabs
    for (const tab of $$(".tab")) {
      const k = tab.dataset.cat, selected = k === cat;
      const span = $("span", tab);
      if (span && t.cats[k]) span.textContent = t.cats[k].tab;
      tab.setAttribute("aria-selected", String(selected));
      tab.tabIndex = selected ? 0 : -1;
    }

    // Panel title & description
    $("#show-panel").setAttribute("aria-labelledby", "tab-" + cat);
    $("#show-title").textContent = t.cats[cat] ? t.cats[cat].title : "Conversions";
    $("#show-desc").textContent = t.cats[cat] ? t.cats[cat].desc : "";

    // Duo mode vs Single mode
    const isSingle = !c.duo;
    const duoEl = $("#show-duo");
    if (duoEl) {
      duoEl.classList.toggle("is-single", isSingle);
    }

    // Labels above wheels
    const fmtLabelEl = $("#show-fmt-label");
    if (fmtLabelEl) {
      fmtLabelEl.textContent = c.fmtLabel || (c.pack ? t.pack : t.convert);
    }
    const toolsLabelEl = $("#show-tools-label");
    if (toolsLabelEl) {
      toolsLabelEl.textContent = c.toolsLabel || t.tools;
    }

    const hubName = c.hub || t.file;

    // Formats wheel
    const fmtLabels = c.formats.map(f => c.pack ? d.pack(fmtName(f)) : fmtName(f));
    let initialFmtIdx = 0;
    if (c.initialFmt) {
      const targetFmt = c.initialFmt.toLowerCase();
      const found = c.formats.findIndex(f => f.toLowerCase() === targetFmt);
      if (found !== -1) initialFmtIdx = found;
    }

    wheel(
      $("#show-wheel-fmt"),
      $("#show-fmt-rotate"),
      fmtLabels,
      hubName,
      i => {
        const fmtKey = c.formats[i];
        if (c.fmtCaptions && c.fmtCaptions[fmtKey]) return c.fmtCaptions[fmtKey];
        const f = fmtName(fmtKey);
        return d.fmtDescs && d.fmtDescs[f] ? `${f}: ${d.fmtDescs[f]}` : (c.pack ? t.packAs(f) : t.convertTo(f));
      },
      $("#show-fmt-cap"),
      t.fmtAria(t.sources[cat] || t.sources.documents, fmtLabels.join(", ")),
      { initialIndex: initialFmtIdx }
    );

    // Tools wheel (if dual mode)
    if (!isSingle && c.tools) {
      const toolLabels = c.tools.map(id => (d.tools && d.tools[id]) || id.toUpperCase());
      let initialToolIdx = 0;
      if (c.initialTool) {
        const targetTool = c.initialTool.toLowerCase();
        const found = c.tools.findIndex(t => t.toLowerCase() === targetTool);
        if (found !== -1) initialToolIdx = found;
      }

      wheel(
        $("#show-wheel-tools"),
        $("#show-tools-rotate"),
        toolLabels,
        hubName,
        i => {
          const id = c.tools[i];
          if (c.toolCaptions && c.toolCaptions[id]) return c.toolCaptions[id];
          const label = toolLabels[i];
          const desc = d.toolDescs && d.toolDescs[id];
          return desc ? `${label.charAt(0) + label.slice(1).toLowerCase()}: ${desc}` : label;
        },
        $("#show-tools-cap"),
        t.toolsAria(t.toolsSources[cat] || t.sources[cat] || t.sources.documents, toolLabels.join(", ")),
        { initialIndex: initialToolIdx }
      );
    }

    // Category feature cards grid
    const cardsEl = $("#show-cards");
    if (cardsEl && c.cards) {
      cardsEl.className = "showcase-cards-grid" + (c.cards.length === 2 ? " cols-2" : "");
      cardsEl.innerHTML = c.cards.map(card => `
        <div class="showcase-card">
          <div class="showcase-card-icon">${iconSvg(card.icon)}</div>
          <h4 class="showcase-card-title">${card.title}</h4>
          <p class="showcase-card-desc">${card.desc}</p>
        </div>
      `).join("");
    }

    renderActionsWheel();
  }

  function select(next, focus) {
    if (next === cat) return;
    cat = next;
    render();
    if (focus) {
      const tabEl = $("#tab-" + cat);
      if (tabEl) tabEl.focus();
    }
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
