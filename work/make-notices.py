"""Write THIRD-PARTY-NOTICES.txt for the app bundle from docs/dependencies.json.

Usage: python work/make-notices.py <output-file>
build.ps1 and build-mac.sh run this so every bundle ships the notices file.
"""
from pathlib import Path
import json, re, sys

ROOT = Path(__file__).resolve().parent.parent
deps = json.loads((ROOT / 'docs' / 'dependencies.json').read_text(encoding='utf8'))
ffmpeg = re.search(r'version (\d+(?:\.\d+)+)', deps['ffmpeg']).group(1)
python = deps['python'].split()[0]
dotnet = deps['dotnet_runtime'].split()[0]

lines = [
    'DropDial - Third-Party Notices & Licenses',
    '=' * 45,
    '',
    'DropDial is proprietary commercial software.',
    'Copyright (c) 2026 DropDial (https://dropdial.com). All rights reserved.',
    '',
    'DropDial incorporates and is built upon open-source software components.',
    'Each third-party component retains its respective license as set forth below.',
    'This document satisfies all third-party license and copyright notice requirements.',
    '',
    '1. DropDial Base Core Framework',
    '   Portions Copyright (c) 2026 Max Chen (https://github.com/Maxaccurate/DropDial)',
    '   Licensed under the MIT License:',
    '   Permission is hereby granted, free of charge, to any person obtaining a copy',
    '   of this software and associated documentation files (the "Software"), to deal',
    '   in the Software without restriction, including without limitation the rights',
    '   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell',
    '   copies of the Software, and to permit persons to whom the Software is',
    '   furnished to do so, subject to the following conditions:',
    '   The above copyright notice and this permission notice shall be included in all',
    '   copies or substantial portions of the Software.',
    '   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR',
    '   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,',
    '   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE',
    '   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER',
    '   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,',
    '   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE',
    '   SOFTWARE.',
    '',
    f'2. FFmpeg {ffmpeg} (ffmpeg.exe, ffprobe.exe) - GNU General Public License v3',
    '   DropDial executes FFmpeg as an independent, standalone external program;',
    '   it is not linked into the DropDial binary.',
    '   Binary build: https://www.gyan.dev/ffmpeg/builds/',
    f'   Source code: https://ffmpeg.org/releases/ffmpeg-{ffmpeg}.tar.xz',
    '',
    '3. 7-Zip 25.01 (7z.exe, 7z.dll) - GNU LGPL 2.1, BSD 3-clause',
    '   DropDial executes 7-Zip as an independent standalone external program.',
    '   Source code: https://www.7-zip.org/a/7z2501-src.7z',
    '',
    f'4. Python {python} (embedded) - Python Software Foundation License',
    '   License: https://docs.python.org/3/license.html',
    '   Source code: https://www.python.org/downloads/source/',
    '',
    f'5. .NET {dotnet} Runtime & WPF - MIT License',
    '   Copyright (c) .NET Foundation and Contributors',
    '   https://github.com/dotnet/runtime  https://github.com/dotnet/wpf',
    '',
    '6. Source Han Sans CN Medium 2.005 - SIL Open Font License 1.1',
    '   Copyright (c) 2014-2025 Adobe (http://www.adobe.com/)',
    '   https://github.com/adobe-fonts/source-han-sans',
    '',
    '7. Bundled Python Packages & Runtime Libraries:',
]

for package in sorted(deps.get('python_packages', []), key=lambda p: p['name'].lower()):
    lines.append(f"   • {package['name']} {package['version']} ({package['license']})")

lines += [
    '',
    'Python package sources: https://pypi.org/ (each package page links its source repository).',
    '',
    '=' * 45,
    'End of Third-Party Notices',
]

out = Path(sys.argv[1])
out.write_text('\n'.join(lines), encoding='utf-8')
print(f'wrote {out} ({len(lines)} lines)')
