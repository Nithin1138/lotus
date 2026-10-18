# DropDial - File Tool & Conversion Guide

Version 1.0.0. Lightweight desktop file conversion and utility tool that resides in the system menu bar / tray with no unnecessary main window.

## Usage

1. Select files on the desktop or in the file explorer, then start dragging with the left mouse button held down.
2. Press **Shift** while dragging: a floating radial menu appears showing available format conversions. Move over the desired format and release.
3. Press **Ctrl+Shift** while dragging to choose advanced tools. Tools requiring settings open a dedicated tool window. Adjust the parameters and click **"Save New File"**.
4. Once the menu appears, you can release the keyboard keys while continuing to hold the mouse button. Pressing **Ctrl** while **Shift** is held switches the menu to tools. While dragging, **F8** (formats) and **F9** (tools) open the menu as well.
5. Conversions and non-interactive tools display progress cards in the corner of your screen. Batch tasks display actual processed counts. When complete, the card dismisses automatically without disruptive popups.

### Progress Cards

Each background job displays its own card stacked in order:
- **Pause / Resume**: Suspends the entire job (including background processes) and continues exactly where it left off.
- **Cancel**: Stops the job and removes unfinished temporary files.
- **Hide**: Hides the card while the job continues in the background.

Up to 2 tasks run in parallel; others wait in the queue. A paused task gives up its slot to the next waiting task.

## Supported Categories & Features

| Category | Conversions & Tools |
| --- | --- |
| **Images** | JPG, PNG, WebP, HEIC, TIFF, SVG, AVIF, BMP, PDF, DOCX. Tools: Compression, metadata removal, GPS location modification, exposure/color/clarity adjustments, background/shadow/corners, crop, rotate/flip, resize, watermark, icon set (ICO/ICNS), OCR text recognition, animation maker, pixelate/blur redaction, PDF merging, collage maker. |
| **Videos** | MP4, MOV, MKV, WebM, AVI, WMV, GIF, MP3 extraction. Tools: Compression, metadata, GPS location, mute, trim range, crop frame, rotate/flip, resolution and FPS, video-to-GIF, speed adjustments, subtitle burn-in, audio track mixing, watermark, frame extraction, video joining, segmented redaction. |
| **Audio** | MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA. Tools: Compression, metadata, loudness normalization, trim/silence removal, mono/stereo channels, volume adjustments, audio joining, ringtone generator (.m4r), visualizer generator, audio bleep redaction. |
| **Documents** | PDF → DOCX / JPG / PNG / TXT; TXT → PDF / JPG / PNG / SRT / VTT; SRT/VTT/TXT conversions. Tools: PDF compression, metadata, merge, split, page reorder/rotate/delete, password encryption, page numbers, image extraction, watermark, redaction (permanent text removal), OCR scanned PDF. |
| **Archives** | ZIP, TAR, GZIP, RAR extract and unpack; Pack files/folders to ZIP, TAR, GZ, 7z with optional AES-256 password and volume splitting. |

## Additional Capabilities

- **Combined Tools**: Related tools share a unified window for multi-step adjustments (e.g. Crop & Rotate, Resize & Compress, Watermark & Redact).
- **Location & Privacy**: View and remove GPS tags from photos and videos, or set coordinates without re-encoding media.
- **Customizable Wheel**: Customize the order of items and prioritize frequently used operations.
- **Appearance**: Seamlessly matches System appearance, Light, or Dark mode.
- **Remember Settings**: Saves previous values as reusable presets.
- **Smart Output Naming**: New files are named clearly (e.g., `photo-rotated.jpg`, `clip-compressed.mp4`).
- **Offline OCR**: Powered by local neural/system text recognition with zero cloud dependency.

## Office Documents

- PPT / PPTX / PPTM / PPS / PPSX / ODP: PDF, per-page images, TXT.
- DOC / DOCX / DOCM / RTF / ODT: PDF, per-page images, TXT, HTML.
- XLS / XLSX / XLSM / XLSB / ODS / CSV / TSV: PDF, per-page images, CSV, TSV, JSON, TXT.
- Office files are opened in read-only mode without executing macros.

## Limitations

- Processing is done entirely locally on your device.
- Large image limit: 80 megapixels.
- PDF to Word preserves text and layout using native converters; scanned documents can be OCR'd first.
- Output files never overwrite existing source files; automatic numeric suffixes are applied.
