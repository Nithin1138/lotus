"""Write packaging/store-listing-fields.md: every Partner Center listing field, ready to paste.

Usage: python packaging/make-listing-fields.py
The script also checks the Store's limits and fails if one is exceeded. Update the text below for each release.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent / 'store-listing-fields.md'
VERSION = '1.0.0'

L = {}
L['en'] = dict(
    heading='English (United States)',
    name='DropDial',
    short=("Convert files without opening an app. Hold Shift while you drag any file, and a format wheel opens under your "
           "cursor. Release on the format you want. Images, video, audio, PDF, Office and archives, all processed on your PC."),
    whatsnew="""The first full release: DropDial grows from a converter into a small toolbox.

• About twenty new tools: rotate by any angle, resize, watermark, make icons, text recognition (OCR) for pictures and scanned PDFs, GIF and slideshow makers, video fade/reverse/loop, subtitles and soundtrack tools, audio volume, noise reduction, join and phone ringtone, PDF passwords, page numbers and image extraction, and password-protected ZIP and 7z.
• Related tools now share one window with tabs, so the wheel stays at eight entries. Apply changes step by step and undo the last one.
• Presets and flows remember your settings and chain tools, such as resize, watermark, compress.
• Watched folders process new files automatically.
• Choose where results are saved, process a copied screenshot or files from the tray menu, and optionally start with Windows.
• Cropping with a draggable frame, and a new look for the wheel.

Fixes: photos keep their EXIF in the Metadata tool, removing metadata from HEIC photos now removes EXIF and XMP, and a failed job shows the engine's real reason.""",
    description="""DropDial turns the drag you already make into a file converter and a small toolbox.

Select files on the desktop or in File Explorer and start dragging. Press Shift and a format wheel appears under your cursor; release on the format you want. Press Ctrl+Shift instead for tools such as compress, resize, rotate, crop, watermark or redact. For pictures and videos, related tools share one window so the wheel stays simple. The new file is saved next to the original, which is never overwritten.

WHAT IT HANDLES
• Images: JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, SVG. Convert, resize, rotate by any angle, crop with a draggable frame, compress to a target size, watermark with text or a logo, pixelate or blur areas, adjust exposure and colour, add a background, edit or strip metadata, make icons, recognise text (OCR), or combine pictures into a PDF, collage, GIF or slideshow.
• Video: MP4, MOV, MKV, WebM, AVI, WMV, GIF. Convert, make GIFs, trim and split, join, change speed, rotate, change resolution and frame rate, fade, reverse or loop, burn in subtitles, replace or mix the soundtrack, watermark, redact regions over time, save frames or a contact sheet.
• Audio: MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA. Convert, compress, normalize loudness, change volume, add fades, reduce noise, trim, join, adjust channels, bleep out sections, make a phone ringtone or a waveform video.
• PDF and text: PDF to Word, images or text; text to PDF; merge, split, reorder and rotate pages; add or remove a password; page numbers, headers and footers; extract images; watermark; text recognition for scanned PDFs; subtitles between SRT, VTT and text.
• Office: export Word, Excel and PowerPoint files to PDF or images with the exact layout (uses your installed Microsoft Office), and switch between Office and OpenDocument formats.
• Archives: pack and extract ZIP, TAR, GZIP and RAR, or make ZIP and 7z files with an AES-256 password and split volumes.

WORKS THE WAY YOU DO
• Presets remember your settings. Flows chain several tools, such as resize, watermark, compress.
• Watched folders process new files automatically.
• Save next to the original or in one folder you choose, and process a copied screenshot or files from the tray menu.
• Each job gets a progress card with Pause, Cancel and Hide. Run several at once.
• Lives in the system tray, with no main window. Optionally starts with Windows.
• English interface.

PRIVATE BY DESIGN
• Everything runs on your PC with the engines included in the app (FFmpeg, 7-Zip, Python). Nothing is uploaded, and it works offline.
• Text recognition uses the recogniser built into Windows.
• No account, ads, analytics or telemetry.

Free and open source under the MIT License.""",
    features=[
        'Hold Shift while dragging a file to pick a new format from a wheel under your cursor',
        'Ctrl+Shift opens tools: compress, resize, rotate, crop, watermark, redact and more',
        'Images, video, audio, PDF, Office documents and archives',
        'Everything is processed locally: nothing is uploaded',
        'Text recognition (OCR) for pictures and scanned PDFs, using the recogniser built into Windows',
        'Presets and flows: save your settings and chain tools such as resize, watermark, compress',
        'Watched folders process new files automatically',
        'Pause, resume, cancel or hide any job; run several at once',
        'Originals are never overwritten; save next to the original or in a folder you choose',
        'Password-protected ZIP and 7z (AES-256), split volumes, PDF passwords',
        'Built-in player with draggable trim handles for audio and video',
        'Optional start with Windows',
        'Clean English interface',
        'Free and open source',
    ],
    keywords=['file converter', 'video converter', 'image converter', 'audio converter', 'PDF converter', 'compress video', 'drag and drop'],
    copyright='© 2026 DropDial',
    license=("DropDial is licensed under the MIT License. It includes third-party components under their own licenses, including "
             "FFmpeg (GPLv3), 7-Zip (LGPL) and PyMuPDF (AGPLv3). See \"Third-party notices\" in the tray menu."),
    developer='DropDial',
    captions=[
        'Hold Shift while dragging a file and a format wheel opens under your cursor. Release on JPG, PDF, MP3 or any other format.',
        'Press Ctrl+Shift for tools. Related tools share one wheel entry, so the wheel stays simple.',
        'Related tools share one window with tabs, a live preview and draggable trim handles.',
        'Every job gets a progress card with Pause, Cancel and Hide. Run several at once.',
    ],
    shots='en',
)

# Limits from Partner Center and Microsoft's docs.
for code, d in L.items():
    assert len(d['short']) <= 270, (code, 'short description', len(d['short']))
    assert len(d['description']) <= 10000, (code, 'description')
    assert len(d['whatsnew']) <= 1500, (code, "what's new", len(d['whatsnew']))
    assert 'http' not in d['description'] and 'http' not in d['whatsnew'], (code, 'no URLs in the description or what\'s new')
    assert len(d['features']) <= 20 and all(len(f) <= 200 for f in d['features']), (code, 'features')
    assert len(d['keywords']) <= 7 and all(len(k) <= 40 for k in d['keywords']), (code, 'keywords')
    assert sum(len(k.split()) for k in d['keywords']) <= 21, (code, 'keyword words')
    assert all(len(c) <= 200 for c in d['captions']), (code, 'captions')


def block(text):
    return '```text\n' + text + '\n```\n'


lines = [f'# Store listing fields for DropDial {VERSION}: ready to paste',
         '',
         'Fill in each language on its own listing page (Store listings > click the language). Leave every field that is not listed here empty.',
         'Images are in `packaging/store-art/` (logos, hero) and `packaging/screenshots/` (screenshots). Regenerate with `make-store-art.py`, `make-screenshots.py` and this script.',
         '']
for code, d in L.items():
    n = d['shots']
    lines += [f"## {d['heading']}", '',
              '| Field on the page | What to enter |', '|---|---|',
              f"| Product name | {d['name']} (pick it in the drop-down) |",
              "| What's new in this version | the text under \"What's new\" below |",
              '| Short title, Voice title | **leave empty** (Xbox only) |',
              f"| Copyright and trademark info | {d['copyright']} |",
              f"| Developed by | {d['developer']} |",
              f"| Screenshots > Desktop | `screenshots/{n}-1.png` … `{n}-4.png`, in that order, with the captions below |",
              f"| Store logos > Poster art (720 x 1080) | `store-art/poster-720x1080-{n}.png` |",
              f"| Store logos > Box art (1080 x 1080) | `store-art/box-art-1080-{n}.png` |",
              '| Store display images > App tile icon 300 x 300 / 150 x 150 / 71 x 71 | `store-art/tile-300.png`, `tile-150.png`, `tile-71.png` |',
              '| Windows and Xbox image > Super hero art (1920 x 1080) | `store-art/hero-1920x1080.png` |',
              '| Xbox images, Trailers | **leave empty** (Windows only) |',
              '', f"### What's new in this version ({len(d['whatsnew'])} of 1,500 characters)", '', block(d['whatsnew']),
              f"### Description ({len(d['description'])} of 10,000 characters)", '', block(d['description']),
              f"### Short description ({len(d['short'])} of 270 recommended)", '', block(d['short']),
              f"### Product features (one per box, {len(d['features'])} of 20; press \"Add more\" for each)", '']
    lines += [f'{i}. `{f}`' for i, f in enumerate(d['features'], 1)]
    lines += ['', '### Keywords (press Enter after each; ' + f"{len(d['keywords'])} of 7, {sum(len(k.split()) for k in d['keywords'])} of 21 words)", '']
    lines += [f'- `{k}`' for k in d['keywords']]
    lines += ['', '### Additional license terms', '', block(d['license']), '### Screenshot captions (200 characters or fewer)', '']
    lines += [f'{i}. {c}' for i, c in enumerate(d['captions'], 1)]
    lines += ['', '---', '']
OUT.write_text('\n'.join(lines), encoding='utf8')
print('wrote', OUT.name, '| short descriptions:', {c: len(d['short']) for c, d in L.items()},
      '| descriptions:', {c: len(d['description']) for c, d in L.items()},
      "| what's new:", {c: len(d['whatsnew']) for c, d in L.items()})
