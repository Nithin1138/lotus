(() => {
  "use strict";
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const store = {
    get(key) { try { return localStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { localStorage.setItem(key, value); } catch { /* storage unavailable */ } }
  };

  /* ---------- Language ---------- */
  const EN = {};
  $$("[data-i18n]").forEach(el => { EN[el.dataset.i18n] = el.innerHTML; });
  $$("[data-i18n-alt]").forEach(el => { EN[el.dataset.i18nAlt] = el.alt; });
  EN["doc.title"] = document.title;
  const metaDescription = $('meta[name="description"]');
  EN["doc.description"] = metaDescription.content;

  const params = new URLSearchParams(location.search);
  const text = key => (window.ZD_EN ? window.ZD_EN[key] : undefined) ?? EN[key];
  const demoText = () => window.ZD_DEMO["en"];
  // Lets showcase.js re-render when the language changes.
  const languageListeners = [];
  window.ZD = { get lang() { return "en"; }, onLanguage(fn) { languageListeners.push(fn); fn(); } };
  window.DD = window.ZD;

  function applyLanguage() {
    document.documentElement.lang = "en";
    $$("[data-i18n]").forEach(el => { const value = text(el.dataset.i18n); if (value != null) el.innerHTML = value; });
    $$("[data-i18n-alt]").forEach(el => { const value = text(el.dataset.i18nAlt); if (value != null) el.alt = value; });
    $$("img[data-src-en]").forEach(img => { const src = img.dataset.srcEn; if (src && !img.src.endsWith(src)) img.src = src; });
    document.title = text("doc.title");
    metaDescription.content = text("doc.description");
    const toggle = $("#lang-toggle");
    if (toggle) toggle.style.display = "none";
    $("#desk").setAttribute("aria-label", demoText().desk);
    $("#wheel").setAttribute("aria-label", demoText().wheel);
    $(".mode").setAttribute("aria-label", demoText().mode);
    renderRelease();
    demo.relabel();
    languageListeners.forEach(fn => fn());
  }

  /* ---------- Navigation ---------- */
  const nav = $(".nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 8);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---------- Theme Management & Impressive View Transition ---------- */
  const themeToggle = $("#theme-toggle");

  function getPreferredTheme() {
    try {
      const stored = localStorage.getItem("dropdial_theme");
      if (stored === "light" || stored === "dark") return stored;
    } catch (e) {}
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function applyTheme(theme, updateStorage = true) {
    document.documentElement.setAttribute("data-theme", theme);
    if (updateStorage) {
      try {
        localStorage.setItem("dropdial_theme", theme);
      } catch (e) {}
    }
    if (themeToggle) {
      const isDark = theme === "dark";
      themeToggle.setAttribute("aria-label", isDark ? "Switch to light theme" : "Switch to dark theme");
      themeToggle.setAttribute("title", isDark ? "Switch to light theme (T)" : "Switch to dark theme (T)");
    }
  }

  function triggerThemeTransition(e) {
    const currentTheme = document.documentElement.getAttribute("data-theme") || getPreferredTheme();
    const nextTheme = currentTheme === "dark" ? "light" : "dark";

    // Extract origin point for the expanding circular ripple
    let x = window.innerWidth / 2;
    let y = 0;
    if (e && e.clientX !== undefined && e.clientX > 0) {
      x = e.clientX;
      y = e.clientY;
    } else if (themeToggle) {
      const rect = themeToggle.getBoundingClientRect();
      x = rect.left + rect.width / 2;
      y = rect.top + rect.height / 2;
    }

    const endRadius = Math.hypot(
      Math.max(x, window.innerWidth - x),
      Math.max(y, window.innerHeight - y)
    );

    const isReducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (document.startViewTransition && !isReducedMotion) {
      const transition = document.startViewTransition(() => {
        applyTheme(nextTheme);
      });

      transition.ready.then(() => {
        document.documentElement.animate(
          {
            clipPath: [
              `circle(0px at ${x}px ${y}px)`,
              `circle(${endRadius}px at ${x}px ${y}px)`
            ]
          },
          {
            duration: 520,
            easing: "cubic-bezier(0.16, 1, 0.3, 1)",
            pseudoElement: "::view-transition-new(root)"
          }
        );
      });
    } else {
      // Graceful fallback with smooth CSS class
      document.documentElement.classList.add("theme-transitioning");
      applyTheme(nextTheme);
      setTimeout(() => {
        document.documentElement.classList.remove("theme-transitioning");
      }, 400);
    }
  }

  if (themeToggle) {
    themeToggle.addEventListener("click", triggerThemeTransition);
    const initialTheme = document.documentElement.getAttribute("data-theme") || getPreferredTheme();
    applyTheme(initialTheme, false);
  }

  // Keyboard shortcut: Press 'T' (when not focused in inputs) to toggle theme
  window.addEventListener("keydown", (e) => {
    if (e.key === "t" || e.key === "T") {
      const tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : "";
      if (tag !== "input" && tag !== "textarea" && tag !== "select" && !e.metaKey && !e.ctrlKey && !e.altKey) {
        e.preventDefault();
        triggerThemeTransition();
      }
    }
  });

  // Listen to OS theme changes if user has not explicitly chosen
  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
      try {
        if (!localStorage.getItem("dropdial_theme")) {
          applyTheme(e.matches ? "dark" : "light", false);
        }
      } catch (err) {}
    });
  }

  /* ---------- Platform & Latest Releases ---------- */
  const urlParams = new URLSearchParams(window.location.search);
  const forcePlatform = urlParams.get("os") || urlParams.get("platform");
  const isMac = forcePlatform ? forcePlatform.toLowerCase().startsWith("mac") : /Macintosh|Mac OS X|iPhone|iPad|iPod/i.test(navigator.userAgent);

  // Highlight detected platform card
  const cardMac = $("#download-mac");
  const cardWin = $("#download-win");
  if (isMac && cardMac) cardMac.classList.add("is-detected");
  if (!isMac && cardWin) cardWin.classList.add("is-detected");

  // Terminal Install Command (Auto-Identified Device, Single Command)
  const cmdCode = $("#install-cmd-text");
  const deviceTag = $("#cli-device-tag");
  const platformLabel = $("#cli-platform-label");
  const platformIcon = $("#cli-platform-icon");
  const switchBtn = $("#cli-switch-btn");
  const copyBtn = $("#copy-install-cmd");

  const cmdMac = "curl -fsSL https://dropdial.app/install.sh | bash";
  const cmdWin = "irm https://dropdial.app/install.ps1 | iex";

  const macIconSvg = '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.62-.75 1.04-1.8 0.92-2.85-.9.04-1.98.6-2.62 1.35-.57.65-1.06 1.72-.93 2.74 1 .08 2.02-.49 2.63-1.24z"/></svg>';
  const winIconSvg = '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M3 5.5 10.4 4.5v7H3zm0 13 7.4 1v-7.1H3zm8.3 1.1L21 21v-8.6h-9.7zm0-15.2v7.1H21V3z"/></svg>';

  const heroMacIconSvg = '<svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.62-.75 1.04-1.8 0.92-2.85-.9.04-1.98.6-2.62 1.35-.57.65-1.06 1.72-.93 2.74 1 .08 2.02-.49 2.63-1.24z"/></svg>';
  const heroWinIconSvg = '<svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true"><path d="M3 5.5 10.4 4.5v7H3zm0 13 7.4 1v-7.1H3zm8.3 1.1L21 21v-8.6h-9.7zm0-15.2v7.1H21V3z"/></svg>';

  function updateHeroDownloadBtn(platform) {
    const isM = platform === "mac";
    $$("[data-download]").forEach(a => {
      a.href = isM ? "/download" : "#download-win";
      const span = a.querySelector("span");
      if (span) span.textContent = isM ? "Download for macOS" : "Download for Windows";
      const svg = a.querySelector("svg");
      if (svg) svg.outerHTML = isM ? heroMacIconSvg : heroWinIconSvg;
    });
  }

  let currentPlatform = isMac ? "mac" : "win";

  const cliDesc = $("#cli-desc-text");
  const cliPrompt = $("#cli-prompt-symbol");
  const descMac = '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>One command in Terminal: automatically installs DropDial into Applications, clears the quarantine flag, and launches it instantly.</span>';
  const descWin = '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>Run in Windows PowerShell: automatically installs DropDial and creates desktop shortcuts.</span>';

  function setCliPlatform(platform) {
    currentPlatform = platform;
    const isM = platform === "mac";
    if (cmdCode) cmdCode.textContent = isM ? cmdMac : cmdWin;
    if (cliPrompt) cliPrompt.textContent = isM ? "$" : "PS>";
    if (deviceTag) {
      deviceTag.className = `dl-cli-device-tag ${isM ? "mac" : "win"}`;
    }
    if (platformLabel) {
      platformLabel.textContent = isM ? "macOS" : "Windows";
    }
    if (platformIcon) {
      platformIcon.innerHTML = isM ? macIconSvg : winIconSvg;
    }
    if (switchBtn) {
      switchBtn.textContent = isM ? "Switch to Windows" : "Switch to macOS";
    }
    if (cliDesc) {
      cliDesc.innerHTML = isM ? descMac : descWin;
    }
    const vtLink = $("#cli-vt-link");
    const scriptLink = $("#cli-script-inspect-link");
    if (vtLink) {
      vtLink.href = isM
        ? "https://www.virustotal.com/gui/file/5a99b6c08f629f50f549f2e3a9056e64a0297e9399e0f3c5f1710e1a0fa6fda8"
        : "https://www.virustotal.com/gui/file/6c2329bdcac58bc724ede6449f6513c06adcf789f6dc70fda48716bfeaf820a9";
    }
    if (scriptLink) {
      scriptLink.href = isM ? "https://dropdial.app/install.sh" : "https://dropdial.app/install.ps1";
      scriptLink.textContent = isM ? "Inspect Shell Script" : "Inspect PowerShell Script";
    }
    updateHeroDownloadBtn(platform);
  }

  setCliPlatform(isMac ? "mac" : "win");



  if (switchBtn) {
    switchBtn.addEventListener("click", () => {
      setCliPlatform(currentPlatform === "mac" ? "win" : "mac");
    });
  }

  if (cardMac) cardMac.addEventListener("click", (e) => {
    if (!e.target.closest("a, button")) setCliPlatform("mac");
  });
  if (cardWin) cardWin.addEventListener("click", (e) => {
    if (!e.target.closest("a, button, code, .win-cli-container")) setCliPlatform("win");
  });

  // In-Card Command Line Install Tab Switching & Copying
  const cliTabs = $$(".card-cli-tab, .win-cli-tab");
  const cliPanels = $$(".card-cli-panel, .win-cli-panel");
  cliTabs.forEach(tab => {
    tab.addEventListener("click", (e) => {
      e.stopPropagation();
      const target = tab.getAttribute("data-target");
      cliTabs.forEach(t => {
        const isActive = t === tab;
        t.classList.toggle("active", isActive);
        t.setAttribute("aria-selected", isActive ? "true" : "false");
      });
      cliPanels.forEach(p => {
        p.classList.toggle("active", p.id === `panel-win-${target}`);
      });
    });
  });

  $$(".card-cli-copy, .win-cli-copy").forEach(btn => {
    btn.addEventListener("click", async (e) => {
      e.stopPropagation();
      const targetId = btn.getAttribute("data-copy-target");
      const codeEl = document.getElementById(targetId);
      if (!codeEl) return;
      const text = codeEl.textContent.trim();
      try {
        await navigator.clipboard.writeText(text);
        const originalHTML = btn.innerHTML;
        btn.innerHTML = `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>Copied!</span>`;
        setTimeout(() => { btn.innerHTML = originalHTML; }, 2000);
      } catch (err) {
        window.prompt("Copy command:", text);
      }
    });
  });

  if (copyBtn) {
    copyBtn.addEventListener("click", async () => {
      const activeCmd = cmdCode ? cmdCode.textContent : (isMac ? cmdMac : cmdWin);
      try {
        await navigator.clipboard.writeText(activeCmd);
        const originalText = copyBtn.innerHTML;
        copyBtn.innerHTML = "<svg viewBox='0 0 24 24' width='14' height='14' fill='none' stroke='currentColor' stroke-width='2.5' style='margin-right:4px;vertical-align:middle;'><polyline points='20 6 9 17 4 12'></polyline></svg><span>Copied!</span>";
        setTimeout(() => { copyBtn.innerHTML = originalText; }, 2000);
      } catch (err) {
        window.prompt("Copy install command:", activeCmd);
      }
    });
  }

  // Native Releases for macOS and Windows
  const releaseWin = {
    tag: "v1.0.1",
    size: "204 KB",
    url: "/api/releases?download=DropDial-Setup.exe"
  };
  const releaseMac = {
    tag: "v1.0.1",
    size: "4.4 MB",
    url: "/api/releases?download=DropDial.dmg"
  };

  // Zero-PII Anonymous Telemetry Ping for Admin Dashboard
  try {
    fetch('/api/admin?action=track&event=pageview', { method: 'POST', keepalive: true }).catch(() => {});
  } catch (_) {}

  $$("[data-download-mac]").forEach(a => { a.href = releaseMac.url; });
  $$("[data-release-meta-mac]").forEach(el => { el.textContent = `${releaseMac.tag} · ${releaseMac.size} · Universal Mach-O DMG`; });

  // Ensure hero download button matches detected platform
  updateHeroDownloadBtn(currentPlatform);

  // Dynamically update download links and universal version badge from releases proxy
  fetch("/api/releases")
    .then(res => res.ok ? res.json() : null)
    .then(data => {
      if (!data) return;

      const latestTag = data.tag_name || data.version || data.latest_version;
      let displayTag = "v1.0.1";
      if (latestTag) {
        let cleanTag = String(latestTag).trim();
        displayTag = cleanTag.toLowerCase().startsWith('v') ? cleanTag : `v${cleanTag}`;
        if (displayTag.endsWith('.0') && displayTag.split('.').length === 4) {
          displayTag = displayTag.slice(0, -2);
        }

        // Dynamically update the version badge above download section
        $$("[data-latest-version-badge], #dl-version-text").forEach(el => {
          el.textContent = `${displayTag} Universal`;
        });

        // Keep release objects updated
        releaseWin.tag = displayTag;
        releaseMac.tag = displayTag;

        // Update JSON-LD schema
        const schemaEl = document.querySelector('script[type="application/ld+json"]');
        if (schemaEl) {
          try {
            const schema = JSON.parse(schemaEl.textContent);
            schema.softwareVersion = displayTag.replace(/^v/i, '');
            schemaEl.textContent = JSON.stringify(schema, null, 2);
          } catch (_) {}
        }
      }

      if (!data.assets || !Array.isArray(data.assets)) return;
      const winExe = data.assets.find(a => a.name.toLowerCase().endsWith(".exe"));
      const winZip = data.assets.find(a => a.name.toLowerCase().endsWith(".zip") && (a.name.toLowerCase().includes("win") || a.name.toLowerCase().includes("windows")));
      const winAsset = winExe || winZip;

      const macDmg = data.assets.find(a => a.name.toLowerCase().endsWith(".dmg"));
      const macZip = data.assets.find(a => a.name.toLowerCase().endsWith(".zip") && a.name.toLowerCase().includes("mac"));
      const macAsset = macDmg || macZip;

      const activeTag = displayTag || "v1.0.1";

      const formatSize = (bytes) => {
        if (!bytes || isNaN(bytes)) return "";
        if (bytes < 1048576) return `${Math.round(bytes / 1024)} KB`;
        const mb = bytes / (1024 * 1024);
        return mb < 10 ? `${mb.toFixed(1)} MB` : `${Math.round(mb)} MB`;
      };

      if (winAsset) {
        releaseWin.url = winAsset.browser_download_url;
        releaseWin.tag = activeTag;
        const winSizeFormatted = formatSize(winAsset.size);
        $$("[data-download-win]").forEach(a => { a.href = releaseWin.url; });
        $$("[data-release-meta-win]").forEach(el => { el.textContent = `(${releaseWin.tag} · ${winSizeFormatted || '69 MB'})`; });
      } else if (latestTag) {
        $$("[data-release-meta-win]").forEach(el => { el.textContent = `(${releaseWin.tag} · 69 MB)`; });
      }

      if (macAsset) {
        releaseMac.url = macAsset.browser_download_url;
        releaseMac.tag = activeTag;
        const macSizeFormatted = formatSize(macAsset.size);
        $$("[data-download-mac]").forEach(a => { a.href = releaseMac.url; });
        $$("[data-release-meta-mac]").forEach(el => { el.textContent = `(${releaseMac.tag} · ${macSizeFormatted || '4.2 MB'})`; });
      } else if (latestTag) {
        $$("[data-release-meta-mac]").forEach(el => { el.textContent = `(${releaseMac.tag} · ${releaseMac.size})`; });
      }
    })
    .catch(() => {});

  /* ---------- FAQ Exclusive Accordion ---------- */
  const faqList = $$(".faq details");
  faqList.forEach((targetDetail) => {
    // When a user clicks an FAQ item summary
    const summary = targetDetail.querySelector("summary");
    if (summary) {
      summary.addEventListener("click", () => {
        // If clicking to open this detail, close all other open details immediately
        if (!targetDetail.open) {
          faqList.forEach((otherDetail) => {
            if (otherDetail !== targetDetail && otherDetail.open) {
              otherDetail.open = false;
            }
          });
        }
      });
    }

    // Also monitor native toggle event (handles keyboard Space/Enter and external triggers)
    targetDetail.addEventListener("toggle", () => {
      if (targetDetail.open) {
        faqList.forEach((otherDetail) => {
          if (otherDetail !== targetDetail && otherDetail.open) {
            otherDetail.open = false;
          }
        });
      }
    });
  });

  /* ---------- Interactive demo ---------- */
  // Menus follow the app's Catalog.cs: what each extension converts to, and which tools it offers for a single file.
  const IMAGES = ["jpg", "png", "webp", "heic", "tiff", "svg", "avif", "bmp"];
  const AUDIO = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"];
  const VIDEO = ["mp4", "mov", "mkv", "webm", "avi", "wmv"];
  const ARCHIVES = ["zip", "tar", "gz", "rar"];
  const IMAGE_TARGETS = ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "pdf"];
  const kindOf = e => IMAGES.includes(e) ? "image" : AUDIO.includes(e) ? "audio" : VIDEO.includes(e) || e === "gif" ? "video" : e === "pdf" ? "pdf" : e === "docx" ? "office" : ["txt", "srt", "vtt"].includes(e) ? "text" : ARCHIVES.includes(e) ? "archive" : "file";
  function targets(e) {
    if (e === "docx") return ["pdf", "png", "jpg", "txt", "docx", "doc", "rtf", "odt", "html"]; // with Microsoft Word installed
    if (e === "jpg" || e === "png") return [...IMAGE_TARGETS, "docx"];
    if (IMAGES.includes(e)) return IMAGE_TARGETS;
    if (AUDIO.includes(e)) return AUDIO;
    if (VIDEO.includes(e)) return [...VIDEO, "gif", "mp3"];
    if (e === "gif") return VIDEO;
    if (e === "pdf") return ["docx", "jpg", "png", "txt"];
    if (e === "txt") return ["pdf", "jpg", "png", "srt", "vtt"];
    if (e === "srt" || e === "vtt") return ["srt", "vtt", "txt"];
    return ARCHIVES;
  }
  function tools(e) {
    switch (kindOf(e)) {
      case "image": return e === "svg" ? [] : e === "bmp" ? ["compress", "editImage", "frameImage", "cropImage", "redactImage"] : ["compress", "removeMetadata", "editImage", "frameImage", "cropImage", "redactImage"];
      case "audio": return ["compress", "removeMetadata", "normalizeAudio", "audioToVideo", "trimAudio", "audioChannels", "redactAudio"];
      case "video": return e === "gif" ? ["removeMetadata"] : ["compress", "removeMetadata", "muteVideo", "trimVideo", "cropVideo", "changeVideoSpeed", "videoSnapshots", "splitVideo", "redactVideo"];
      case "pdf": return ["compress", "removeMetadata", "splitPDF", "organizePDF"];
      case "office": return ["officePdf", "removeMetadata"];
      case "archive": return ["extractArchive"];
      default: return [];
    }
  }
  const extOf = name => /\.tar\.gz$/i.test(name) ? "gz" : name.includes(".") ? name.split(".").pop().toLowerCase() : "";
  const stemOf = name => name.replace(/(\.tar\.gz|\.[^.]+)$/i, "");
  // A folder can only be packed, matching the app's PackingOnly rule.
  function menu(file, mode) {
    if (file.folder) return mode === "formats" ? ARCHIVES.map(t => "pack:" + t) : [];
    if (mode === "tools") return tools(file.ext).map(t => "tool:" + t);
    return targets(file.ext).filter(t => t !== file.ext).map(t => "convert:" + t);
  }
  const fmtName = t => t === "gz" ? "GZIP" : t.toUpperCase();
  function label(option) {
    const [kind, value] = option.split(":");
    return kind === "convert" ? fmtName(value) : kind === "pack" ? demoText().pack(fmtName(value)) : demoText().tools[value];
  }
  const iconTag = file => file.folder ? "DIR" : /\.tar\.gz$/i.test(file.name) ? "TGZ" : file.ext.toUpperCase();
  const iconHtml = file => `<span class="file-icon t-${file.folder ? "folder" : kindOf(file.ext)}"><b>${iconTag(file)}</b></span>`;

  const stage = $("#stage"), desk = $("#desk"), wheelWrap = $("#wheel-wrap"), wheel = $("#wheel"), ghost = $("#ghost"), help = $("#demo-help");
  const toast = $("#toast"), toastTitle = $("#toast-title"), toastDetail = $("#toast-detail"), toastBar = $("#toast-bar"), toastTime = $("#toast-time");
  const modeButtons = { formats: $("#mode-formats"), tools: $("#mode-tools") };
  const SVG = "http://www.w3.org/2000/svg";
  const wheelUI = window.ZD_WHEEL;
  const C = wheelUI.CENTER, MAX_OUTPUTS = 3;
  const names = new Set();
  const outputs = [];
  let defaultMode = "formats";   // set by the toggle under the stage
  let session = null;            // the open wheel: { file, button, source: "pointer" | "keyboard" | "auto", mode, options, highlighted, pointerId }
  let helpTimer = 0, interacted = false;
  let suppressed = null;          // pointer whose drag was cancelled; ignored until the button is released, like the app's Escape

  /* Files on the demo desktop */
  function addFile(name, { folder = false, fresh = false } = {}) {
    const file = { name, folder, ext: folder ? "" : extOf(name) };
    names.add(name);
    const li = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "file" + (fresh ? " fresh" : "");
    // Allow a line break before the extension so long names never split mid-word.
    button.innerHTML = `${iconHtml(file)}<span class="file-name">${name.replace(/\.(?=[^.]+$)/, "<wbr>.")}</span>`;
    button.dataset.name = name;
    li.appendChild(button);
    desk.appendChild(li);
    bindFile(button, file);
    return li;
  }
  ["photo.png", "trip.mp4", "song.wav", "report.pdf", "photos.zip"].forEach(name => addFile(name));

  function uniqueName(base, extension) {
    let name = base + extension, i = 0;
    while (names.has(name)) name = `${base}-${++i}${extension}`;
    return name;
  }
  function addOutput(name, folder) {
    outputs.push(addFile(name, { folder, fresh: true }));
    // Keep the desk tidy, but never remove the file someone is dragging.
    while (outputs.length > MAX_OUTPUTS) {
      const index = outputs.findIndex(li => !session || !li.contains(session.button));
      const [old] = outputs.splice(index, 1);
      names.delete(old.querySelector("button").dataset.name);
      old.remove();
    }
  }

  /* Help line under the stage */
  function say(message, ms) {
    clearTimeout(helpTimer);
    help.textContent = message;
    if (ms) helpTimer = setTimeout(() => { help.textContent = session ? demoText().helpDrag : demoText().help; }, ms);
  }

  /* Wheel */
  function svg(name, attrs, parent) {
    const node = document.createElementNS(SVG, name);
    for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
    parent.appendChild(node);
    return node;
  }
  const polar = wheelUI.polar;
  function showMode(mode) {
    for (const [key, button] of Object.entries(modeButtons)) button.setAttribute("aria-pressed", String(key === mode));
  }
  function render() {
    const s = session;
    s.options = menu(s.file, s.mode);
    s.highlighted = -1;
    showMode(s.mode);
    const layers = wheelUI.base(wheel);
    const n = s.options.length;
    s.options.forEach((option, i) => {
      const angle = -Math.PI / 2 + i * 2 * Math.PI / n;
      wheelUI.petal(layers, i, n, { "data-i": i, role: "option", "aria-label": label(option) });
      const [lx, ly] = polar(119, angle), text = label(option), words = text.split(" ");
      const node = svg("text", { class: "label" + (n > 7 ? " small" : ""), x: lx, y: ly, "data-i": i }, wheel);
      if (words.length > 1 && text.length > 9) {
        const cut = Math.ceil(words.length / 2);
        svg("tspan", { x: lx, dy: "-0.55em" }, node).textContent = words.slice(0, cut).join(" ");
        svg("tspan", { x: lx, dy: "1.15em" }, node).textContent = words.slice(cut).join(" ");
      } else node.textContent = text;
    });
    wheelUI.hub(wheel);
    svg("text", { class: "hub-title", x: C, y: C - 2 }, wheel).textContent = n ? demoText().files(1) : demoText().none;
    svg("text", { class: "hub-hint", x: C, y: C + 20, id: "hub-hint" }, wheel).textContent = n ? demoText().release : demoText().escHint;
  }
  function highlight(index) {
    const s = session;
    if (!s || index === s.highlighted) return;
    s.highlighted = index;
    wheelUI.select(wheel, index);
    const hint = $("#hub-hint", wheel);
    if (hint && s.options.length) hint.textContent = index >= 0 ? label(s.options[index]) : demoText().release;
    const badge = $(".badge", ghost);
    if (badge) { badge.textContent = index >= 0 ? "→ " + label(s.options[index]) : ""; badge.hidden = index < 0; }
  }
  // Uses the wheel's layout size rather than its on-screen box, so the opening animation never skews hits.
  function geometry() {
    const box = wheelWrap.getBoundingClientRect(), size = parseFloat(getComputedStyle(wheel).width) || 0;
    return { cx: box.left + box.width / 2, cy: box.top + box.height / 2, scale: size / 380 };
  }
  function hitTest(x, y) {
    const s = session;
    if (!s || !s.options.length) return -1;
    const g = geometry();
    if (!g.scale) return -1;
    return wheelUI.hit(wheel, C + (x - g.cx) / g.scale, C + (y - g.cy) / g.scale);
  }
  function petalPoint(index) {
    const g = geometry(), angle = -Math.PI / 2 + index * 2 * Math.PI / session.options.length;
    return [g.cx + 126 * Math.cos(angle) * g.scale, g.cy + 126 * Math.sin(angle) * g.scale];
  }
  function moveGhost(x, y) {
    const box = stage.getBoundingClientRect();
    ghost.style.left = x - box.left + "px";
    ghost.style.top = y - box.top + "px";
  }

  /* One wheel at a time; every way out goes through end(). */
  function begin(file, button, source, chord) {
    if (session) end();
    clearTimeout(helpTimer);
    session = { file, button, source, mode: chord === 2 ? "tools" : chord === 1 ? "formats" : defaultMode, options: [], highlighted: -1, pointerId: null };
    button.classList.add("dragging");
    render();
    wheelWrap.hidden = false;
    stage.classList.add("open");
    wheel.style.animation = "none"; void wheel.offsetWidth; wheel.style.animation = "";
    if (source !== "keyboard") {
      ghost.innerHTML = `${iconHtml(file)}<span class="badge" hidden></span>`;
      ghost.hidden = false;
    }
    if (source !== "auto") say(demoText().helpDrag);
  }
  function end(suppress) {
    const s = session;
    if (!s) return null;
    session = null;
    if (suppress && s.pointerId != null) suppressed = s.pointerId;
    s.button.classList.remove("dragging");
    if (s.pointerId != null) {
      try { if (s.button.hasPointerCapture(s.pointerId)) s.button.releasePointerCapture(s.pointerId); } catch { /* already released */ }
    }
    wheelWrap.hidden = true;
    ghost.hidden = true;
    stage.classList.remove("open");
    showMode(defaultMode);
    if (help.textContent === demoText().helpDrag) help.textContent = demoText().help;
    return s;
  }
  function drop(index) {
    const s = end();
    if (!s) return;
    if (!s.options.length) { say(demoText().nothing, 4000); return; }
    if (index < 0) { if (s.source !== "auto") say(demoText().outside, 4000); return; }
    const option = s.options[index], [kind, value] = option.split(":");
    if (kind === "tool" && value !== "extractArchive") { say(demoText().toolInfo(label(option)), 6000); return; }
    enqueue(s.file, kind, value);
  }

  function setMode(next, fromToggle) {
    if (fromToggle) defaultMode = next;
    if (session) { if (session.mode !== next) { session.mode = next; render(); } }
    else showMode(defaultMode);
  }
  modeButtons.formats.addEventListener("click", () => setMode("formats", true));
  modeButtons.tools.addEventListener("click", () => setMode("tools", true));

  // Same chords as the app: Shift → formats, Ctrl+Shift → tools; adding Ctrl later switches to tools.
  let previousChord = 0;
  const chordOf = e => e.shiftKey && !e.altKey ? (e.ctrlKey || e.metaKey ? 2 : 1) : 0;
  function applyChord(e) {
    const chord = chordOf(e);
    if (chord === 2) setMode("tools");
    else if (chord === 1 && previousChord === 0) setMode("formats");
    previousChord = chord;
  }

  /* Conversion queue: one job at a time, like the app's worker queue. */
  const queue = [];
  let running = null, toastHide = 0;
  function enqueue(file, kind, value) {
    queue.push({ file, kind, value });
    if (running) updateClock(); else next();
  }
  function updateClock() {
    if (!running || running.finishing) return;
    const seconds = Math.floor((performance.now() - running.started) / 1000);
    toastTime.textContent = demoText().elapsed(seconds) + (queue.length ? " · " + demoText().queued(queue.length) : "");
  }
  function showToast(title, detail, busy) {
    clearTimeout(toastHide);
    toast.hidden = false;
    toastTitle.textContent = title;
    toastDetail.textContent = detail;
    toastBar.classList.toggle("indeterminate", busy);
    $("i", toastBar).style.width = busy ? "" : "100%";
  }
  function next() {
    const job = queue.shift();
    running = null;
    if (!job) { toastHide = setTimeout(() => { toast.hidden = true; }, 2600); return; }
    const wasHidden = toast.hidden;
    running = { ...job, started: performance.now() };
    showToast(job.kind === "convert" ? demoText().converting : demoText().processing, job.file.name, true);
    if (wasHidden) { toast.style.animation = "none"; void toast.offsetWidth; toast.style.animation = ""; }
    updateClock();
    const current = running;
    current.clock = setInterval(updateClock, 250);
    current.timer = setTimeout(() => finish(current), reducedMotion ? 300 : 1300);
  }
  function finish(job) {
    clearInterval(job.clock);
    const base = stemOf(job.file.name), extension = job.value === "gz" ? ".tar.gz" : "." + job.value;
    const name = job.kind === "tool" ? uniqueName(base + "-extracted", "")
      : uniqueName(base + (job.kind === "pack" ? "-packed" : "-converted"), extension);
    addOutput(name, job.kind === "tool");
    showToast(demoText().done, demoText().saved(name), false);
    toastTime.textContent = demoText().elapsed(Math.max(1, Math.round((performance.now() - job.started) / 1000))) + (queue.length ? " · " + demoText().queued(queue.length) : "");
    running = { finishing: true, started: job.started };
    setTimeout(next, queue.length ? 700 : 0);
  }

  /* Pointer and keyboard input.
     A press starts on a file; the rest of the drag is followed at the window level, so the release is seen
     no matter which element ends up receiving it (browsers may drop pointer capture before pointerup). */
  let press = null;   // { id, x, y, chord, button, file }
  function bindFile(button, file) {
    button.addEventListener("pointerdown", e => {
      if (e.button !== 0) return;
      stopAutoplay();
      // A new press always starts fresh, so an earlier drag whose release went missing can never block the demo.
      if (session) end();
      suppressed = null;
      press = { id: e.pointerId, x: e.clientX, y: e.clientY, chord: chordOf(e), button, file };
      // Capture keeps touch drags flowing to us; it is optional, so failures are harmless.
      try { button.setPointerCapture(e.pointerId); } catch { /* pointer already gone */ }
      e.preventDefault();
    });
    button.addEventListener("contextmenu", e => { if (session) e.preventDefault(); });
    button.addEventListener("keydown", e => {
      if ((e.key === "Enter" || e.key === " ") && !session) {
        // Stop here so the same keypress doesn't reach the document handler and pick an option at once.
        e.preventDefault(); e.stopPropagation(); stopAutoplay();
        begin(file, button, "keyboard", 0);
        highlight(session.options.length ? 0 : -1);
      }
    });
  }
  const ownsPress = e => press && e.pointerId === press.id;
  const dragging = () => session && press && session.button === press.button && session.source === "pointer";
  addEventListener("pointermove", e => {
    if (!ownsPress(e) || e.pointerId === suppressed) return;
    // A mouse with no buttons held means the release happened outside the page: treat it as cancelled.
    if (e.pointerType === "mouse" && e.buttons === 0) { if (dragging()) end(); press = null; return; }
    if (!dragging()) {
      if (Math.hypot(e.clientX - press.x, e.clientY - press.y) < 6) return;
      previousChord = press.chord;
      begin(press.file, press.button, "pointer", chordOf(e) || press.chord);
      session.pointerId = e.pointerId;
    }
    applyChord(e);
    moveGhost(e.clientX, e.clientY);
    highlight(hitTest(e.clientX, e.clientY));
  });
  addEventListener("pointerup", e => {
    if (!ownsPress(e)) return;
    const wasDragging = dragging();
    press = null;
    if (wasDragging) drop(hitTest(e.clientX, e.clientY));
  });
  addEventListener("pointercancel", e => {
    if (!ownsPress(e)) return;
    if (dragging()) end();
    press = null;
  });
  document.addEventListener("keydown", e => {
    if (!session) return;
    if (session.source === "auto") { stopAutoplay(); return; }
    applyChord(e);
    if (e.key === "Escape") { e.preventDefault(); end(true); return; }
    if (session.source !== "keyboard") return;
    const n = session.options.length;
    if (n && (e.key === "ArrowRight" || e.key === "ArrowDown")) { e.preventDefault(); highlight((session.highlighted + 1) % n); }
    else if (n && (e.key === "ArrowLeft" || e.key === "ArrowUp")) { e.preventDefault(); highlight((session.highlighted - 1 + n) % n); }
    else if (e.key === "Enter" || e.key === " ") { e.preventDefault(); const button = session.button; drop(session.highlighted); button.focus(); }
    else if (e.key === "Tab") end();
  });
  document.addEventListener("keyup", e => { if (session) previousChord = chordOf(e); });
  addEventListener("blur", () => { if (session && session.source !== "auto") end(true); });
  // Only the automatic run stops when the page is hidden; a real drag is ended by its release, blur, or a missed release.
  document.addEventListener("visibilitychange", () => { if (document.hidden) stopAutoplay(); });

  /* One automatic run when the demo first scrolls into view, so visitors see what to do. */
  let autoFrame = 0, autoTimer = 0;
  function stopAutoplay() {
    interacted = true;
    cancelAnimationFrame(autoFrame);
    clearTimeout(autoTimer);
    if (session && session.source === "auto") end();
  }
  function autoplay() {
    if (interacted || reducedMotion || session || document.hidden) return;
    const button = $(".file", desk), file = { name: "photo.png", folder: false, ext: "png" };
    const from = button.getBoundingClientRect();
    begin(file, button, "auto", 1);
    const start = [from.left + from.width / 2, from.top + from.height / 2], target = petalPoint(0);
    const t0 = performance.now(), duration = 1100;
    const step = now => {
      if (!session || session.source !== "auto") return;
      const t = Math.min(1, (now - t0) / duration), k = t < .5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      const x = start[0] + (target[0] - start[0]) * k, y = start[1] + (target[1] - start[1]) * k - Math.sin(Math.PI * k) * 40;
      moveGhost(x, y);
      highlight(hitTest(x, y));
      if (t < 1) autoFrame = requestAnimationFrame(step);
      else autoTimer = setTimeout(() => { if (session && session.source === "auto") drop(session.highlighted); }, 550);
    };
    autoFrame = requestAnimationFrame(step);
  }
  stage.addEventListener("pointerdown", () => { if (!interacted) stopAutoplay(); }, true);
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) { observer.disconnect(); autoTimer = setTimeout(autoplay, 900); }
    }, { threshold: .6 });
    observer.observe(stage);
  }

  const demo = {
    relabel() {
      if (session) render();
      if (!running) toast.hidden = true;
      clearTimeout(helpTimer);
      help.textContent = session && session.source !== "auto" ? demoText().helpDrag : demoText().help;
    }
  };

  applyLanguage();
})();
