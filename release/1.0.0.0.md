# DropDial 1.0.0.0

DropDial version 1.0.0.0 for macOS and Windows — Universal offline desktop file converter and multi-tool suite.

---

### 🪟 Windows Installation

#### Option 1: Quick Terminal Install (Recommended)
Open **PowerShell** (press `Win + X` then choose **Terminal** or **PowerShell**) and paste:
```powershell
irm https://dropdial.app/install.ps1 | iex
```
*DropDial will automatically download, install to your user programs folder, create Desktop and Start Menu shortcuts, and launch immediately with zero admin rights required.*

#### Option 2: Standalone Setup Executable (.exe)
Download and run **`DropDial-Setup.exe`** from the release assets.
- Zero zip extraction required.
- Self-contained offline engines included.

#### Option 3: Portable ZIP
Download **`DropDial-Windows-x64.zip`**, extract anywhere, and launch `DropDial.exe`.

---

### 🍏 macOS Installation

#### Option 1: One-Line Terminal Install
Open **Terminal** and run:
```bash
curl -fsSL https://dropdial.app/install.sh | bash
```

#### Option 2: Apple Disk Image (.dmg)
Download **`DropDial.dmg`**, double-click to open, and drag **DropDial.app** into your **Applications** folder.

#### Option 3: ZIP Archive
Download **`DropDial-macOS.zip`**, unzip, and move to `/Applications`.

*Built as a Universal Mach-O binary natively supporting Apple Silicon (M-Series and onwards) and Intel x86_64.*

---

### 🚀 Highlights & Features in 1.0.0.0

- **333+ Offline Media Conversions**: Zero cloud uploads. Images, videos, audio, PDF, documents, and archives process completely locally on your hardware.
- **40+ Advanced File Manipulation Tools**:
  - **Images**: Crop & aspect ratio presets, custom rotation, flip, format conversion, resize, text recognition (OCR), metadata inspector/stripper, background removal, watermarks, redaction, ICO/favicon creator, and animated GIF/slideshow builder.
  - **Videos**: Frame trimming, clip splitting, speed changer, reverse/loop, audio replacement, soundtrack extractor, subtitling, resolution scaling, frame-rate adjustment, contact sheet generator, and GIF export.
  - **Audio**: Format encoding, volume normalization, fades, vocal/noise reduction, audio concatenation, and phone ringtone export (.m4r).
  - **Documents & PDFs**: Searchable OCR, password protect/remove, page numbering, headers/footers, and image extraction.
  - **Archives**: Encrypted ZIP and 7z archives with AES-256 and multi-volume splits.
- **Hardware Acceleration**: Optimized for Apple Silicon (M-Series and onwards) and Windows GPU/DirectShow engines.
- **Private Release Delivery**: Built-in auto-update engine powered by `https://dropdial.app/api/releases/latest`.

---

### 📦 Included Release Assets:
- `DropDial-Setup.exe` — Windows standalone installer executable
- `DropDial.exe` — Windows standalone application binary
- `DropDial-Windows-x64.zip` — Windows portable standalone package
- `DropDial.dmg` — macOS Universal Apple disk image
- `DropDial-macOS.zip` — macOS Universal application package
