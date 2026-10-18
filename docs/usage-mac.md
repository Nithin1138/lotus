# Lotus for macOS - User Guide

Version 1.0.0 (macOS Native). Runs in the macOS Menu Bar (Status Item) with a lightweight, clean, and modern interface. No bulky main window needed.

## Shortcuts & Controls

| Shortcut / Trigger | Action |
| --- | --- |
| **F8** (or `Fn+F8` / `⌘8`) | **Summon Formats Wheel** directly under your mouse cursor |
| **F9** (or `Fn+F9` / `⌘9`) | **Summon Tools Wheel** directly under your mouse cursor |
| **Drag files + Shift** | Summons the Formats Wheel while dragging files from Finder |
| **Drag files + Cmd+Shift** | Summons the Tools Wheel while dragging files from Finder |
| **Option + Space** / **⌘⇧L** | Global hotkey to toggle the Lotus Wheel |
| **Escape (Esc)** | Dismiss the Wheel immediately |
| **Tab** | Switch between Formats and Tools mode on the Wheel |
| **Arrow Keys (← / → / ↑ / ↓)** | Rotate slice selection on the Wheel |
| **Return / Space** | Activate highlighted slice or click center Hub |
| **1 – 9** | Instant quick-jump to slice 1 through 9 |

---

## Key Features

1. **Menu Bar Resident & Quick Drag-and-Drop**:
   - Lotus stays in the top-right menu bar.
   - **Click the menu bar icon** to toggle the wheel or right-click to open options.
   - **Drag and drop files directly onto the menu bar icon** from Finder to immediately open format conversion and tool menus.

2. **Desktop Floating Drop Wheel**:
   - A floating circular radial dial with responsive petal slices.
   - Automatically detects file category (Image, Video, Audio, Document, Office, Archive) and shows target formats and tools.
   - Click any target format to start background conversion instantly; click any tool to open interactive controls.

3. **Interactive Tool Window**:
   - Live inspection and preview for images, video frames, audio waveforms, and PDF documents.
   - Sliders and inputs for crop ratios, angles, dimensions, quality compression, watermarks, speed, etc.
   - Instant "Save New File" exporting.

4. **Desktop Progress Card HUD**:
   - Non-intrusive floating status cards in the bottom-right corner of the desktop.
   - Real-time progress indicators, elapsed time, and processed file counts.
   - **Pause / Resume**, **Cancel**, and **Show in Finder** buttons.

5. **Apple Vision Neural OCR**:
   - Powered by Apple's native Vision framework (`VNRecognizeTextRequest`). Completely offline, lightning fast, and supports English and multilingual recognition.

---

## Build & Run

### Building the Application

```bash
./build-mac.sh
```

This compiles the native Swift application, bundles the backend engines, and produces:
`outputs/Lotus-macOS/Lotus.app`

### Running the Application

```bash
open outputs/Lotus-macOS/Lotus.app
```
