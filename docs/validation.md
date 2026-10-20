# Five-Category File Support Validation Results

Date: 2026-10-04.

- 188 standalone offline conversion directions verified (expanding to 333+ with Microsoft Office); 25 advanced tools covered with actual file processing (out of 40+ total built-in tools).
- 387 automated checks passed: 220 conversion/tool/original file integrity checks, 45 advanced branch and preview tests, 5 C# main application dispatch checks, 1 long-GOP video frame-by-frame regression check, 45 Office checks, 23 F9 image/media processing regressions, 30 parameter validation checks, and 18 progress reporting/reading/component lifecycle tests.
- Added PPT/PPTX, Word, Excel document conversions. Main test suite covers PDF, page-by-page images, text, legacy formats, ODF, HTML, CSV/TSV/JSON, selected-page PDF, mixed Office merge, and metadata stripping; native Microsoft Office export functional.
- Crop window dragging updates pixel coordinates dynamically; user confirm and save produces a new file with verified dimensions matching UI inputs.
- Simplified interface: Video frame cropping cleanly focuses on visual geometry; tool windows keep only relevant controls.
- Additional verification: Mosaic uses average pixel blocks preserving outside areas; HEIC primary image and selected frames, MPO/JPEG, multi-page TIFF editable; custom aspect ratio preview matches export; video crop preserves duration and audio tracks.
- Progress indication covers file loading, preview generation, playback preparation, analysis, saving, and background conversion. Batch progress tracks completed tasks; single items show animations and elapsed time without fake percentage estimates. Component tests cover task completion, concurrency, late callbacks, and invalid progress files.
- Verified using real 4K test images; progress card styling previews clearly separated from real batch execution.

Test details in DropDial/validation/. Test inputs generated from synthetic images, audio/video, PDF, text, and archives; outputs verified by re-reading or unpacking and checking original file hashes.
Manual verification across every multi-monitor DPI, encrypted file, and custom encoding can be supplemented with integration passes. PDF to Word preserves text content, and RAR output utilizes store mode.
