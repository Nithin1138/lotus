"""Prepare the portable Windows runtimes without changing system installations."""
from pathlib import Path
from html.parser import HTMLParser
from concurrent.futures import ThreadPoolExecutor
import argparse, gzip, os, re, shutil, ssl, subprocess, sys, urllib.request, urllib.parse, zipfile

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'work/downloads'
BASE = ROOT / 'outputs/DropDial/runtime'

def get_ssl_context():
    try:
        return ssl.create_default_context()
    except Exception:
        return ssl._create_unverified_context()

def fetch(url, path):
    if path.exists() and path.stat().st_size > 0:
        return
    print('Downloading', url, flush=True)
    temp = path.with_suffix(path.suffix + '.download')
    ctx = get_ssl_context()
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    try:
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=120) as response, temp.open('wb') as target:
                shutil.copyfileobj(response, target)
        except Exception:
            # Fallback to unverified SSL if default verification fails
            unverified_ctx = ssl._create_unverified_context()
            with urllib.request.urlopen(req, context=unverified_ctx, timeout=120) as response, temp.open('wb') as target:
                shutil.copyfileobj(response, target)
        temp.replace(path)
    finally:
        if temp.exists():
            temp.unlink()

def python_runtime():
    # Direct official release URLs for Python embeddable x64
    candidates = [
        'https://www.python.org/ftp/python/3.13.2/python-3.13.2-embed-amd64.zip',
        'https://www.python.org/ftp/python/3.13.1/python-3.13.1-embed-amd64.zip',
        'https://www.python.org/ftp/python/3.12.8/python-3.12.8-embed-amd64.zip'
    ]
    package = None
    py_ver = "3.13"
    for url in candidates:
        try:
            pkg_name = CACHE / Path(urllib.parse.urlparse(url).path).name
            fetch(url, pkg_name)
            if pkg_name.exists() and pkg_name.stat().st_size > 5_000_000:
                package = pkg_name
                py_ver = "3.13" if "3.13" in url else "3.12"
                break
        except Exception as e:
            print(f'Failed to fetch {url}: {e}', flush=True)

    if not package or not package.exists():
        raise RuntimeError('Python x64 embedded download failed from python.org.')

    location = BASE / 'python'
    location.mkdir(exist_ok=True, parents=True)
    with zipfile.ZipFile(package) as archive:
        archive.extractall(location)

    # Enable site-packages loading in embedded python
    pth_files = list(location.glob('python*._pth'))
    if pth_files:
        pth_file = pth_files[0]
        stem = pth_file.stem
        pth_file.write_text(f'{stem}.zip\n.\nLib/site-packages\nimport site\n', encoding='utf8')

    site_packages = location / 'Lib/site-packages'
    site_packages.mkdir(exist_ok=True, parents=True)

    # Preinstall all runtime dependencies including pymupdf, pillow, pypdfium2, etc.
    subprocess.run([
        sys.executable, '-m', 'pip', 'install',
        '--disable-pip-version-check',
        '--only-binary=:all:',
        '--python-version', py_ver,
        '--platform', 'win_amd64',
        '--implementation', 'cp',
        '--abi', f'cp{py_ver.replace(".", "")}',
        '--target', str(site_packages),
        '-r', str(ROOT / 'requirements-runtime.txt')
    ], check=True)

    prune_python(site_packages)
    print('Portable Python ready (with pymupdf and runtime libraries)', flush=True)

# Files that are only needed to build against or test a package, never to run it.
PRUNE_DIRS = {'tests', 'test', 'mupdf-devel', 'f2py', '_pyinstaller'}
PRUNE_FILES = ('*.pyi', '*.c', '*.h', '*.lib', '*.pxd', '*.pyx', 'cv2/opencv_videoio_ffmpeg*.dll')

def prune_python(site):
    freed = 0
    for path in sorted(site.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if path.is_dir() and path.name in PRUNE_DIRS:
            freed += sum(f.stat().st_size for f in path.rglob('*') if f.is_file())
            shutil.rmtree(path)
    if (site / 'bin').is_dir():
        freed += sum(f.stat().st_size for f in (site / 'bin').iterdir())
        shutil.rmtree(site / 'bin')
    for pattern in PRUNE_FILES:
        for path in list(site.rglob(pattern)):
            if path.is_file():
                freed += path.stat().st_size
                path.unlink()
    print(f'Pruned {freed/2**20:.1f} MB of build-only files from Python packages', flush=True)

def ffmpeg_runtime():
    folder = BASE / 'ffmpeg'
    folder.mkdir(exist_ok=True, parents=True)
    if (folder / 'ffmpeg.exe').exists() and (folder / 'ffprobe.exe').exists():
        return
    candidates = [
        'https://github.com/GyanD/codexffmpeg/releases/download/7.1/ffmpeg-7.1-essentials_build.zip',
        'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip',
        'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
    ]
    package = None
    for url in candidates:
        try:
            pkg_name = CACHE / Path(urllib.parse.urlparse(url).path).name
            fetch(url, pkg_name)
            if pkg_name.exists() and pkg_name.stat().st_size > 10_000_000:
                package = pkg_name
                break
        except Exception as e:
            print(f'Failed to fetch FFmpeg from {url}: {e}', flush=True)

    if not package or not package.exists():
        raise RuntimeError('FFmpeg download failed from all candidate sources.')

    with zipfile.ZipFile(package) as archive:
        for name in archive.namelist():
            leaf = Path(name).name
            if leaf in ('ffmpeg.exe', 'ffprobe.exe') or 'LICENSE' in leaf.upper() or 'README' in leaf.upper():
                (folder / leaf).write_bytes(archive.read(name))
    if not ((folder / 'ffmpeg.exe').is_file() and (folder / 'ffprobe.exe').is_file()):
        raise RuntimeError('FFmpeg archive did not contain the expected tools.')
    (folder / 'SOURCE.txt').write_text(f'Binary source: {package.name}\nOfficial source and license: https://ffmpeg.org/\nBuild configuration: run ffmpeg.exe -version\n', encoding='utf8')
    print('FFmpeg ready', flush=True)

def sevenzip_runtime(directory):
    target = BASE / '7zip'
    target.mkdir(exist_ok=True, parents=True)
    if (target / '7z.exe').is_file():
        return

    possible_sources = [
        Path(directory) if directory else None,
        Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / '7-Zip',
        Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / '7-Zip'
    ]
    source = next((p for p in possible_sources if p and (p / '7z.exe').is_file()), None)
    if source:
        for name in ('7z.exe', '7z.dll'):
            src_file = source / name
            if src_file.is_file():
                shutil.copy2(src_file, target / name)
        license_file = source / 'License.txt'
        if license_file.is_file():
            shutil.copy2(license_file, target / 'License.txt')
        else:
            (target / 'License.txt').write_text('7-Zip is licensed under GNU LGPL.\nSource: https://www.7-zip.org/\n', encoding='utf8')
        print('7-Zip ready', flush=True)
        return

    # If local 7-zip is missing, fetch standalone 7z console tool
    url = 'https://www.7-zip.org/a/7zr.exe'
    pkg = CACHE / '7zr.exe'
    fetch(url, pkg)
    shutil.copy2(pkg, target / '7z.exe')
    (target / 'License.txt').write_text('7-Zip is licensed under GNU LGPL.\nSource: https://www.7-zip.org/\n', encoding='utf8')
    print('7-Zip ready (standalone)', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sevenzip-dir', help='Directory containing 7z.exe, 7z.dll and License.txt')
    parser.add_argument('--prune-only', action='store_true', help='Only remove build-only files from the existing Python packages')
    args = parser.parse_args()
    if args.prune_only:
        prune_python(BASE / 'python/Lib/site-packages')
        sys.exit()
    if os.name != 'nt':
        parser.error('The application and portable runtime preparation require Windows.')
    CACHE.mkdir(parents=True, exist_ok=True)
    BASE.mkdir(parents=True, exist_ok=True)
    sevenzip_runtime(args.sevenzip_dir)
    with ThreadPoolExecutor(max_workers=2) as executor:
        list(executor.map(lambda fn: fn(), (python_runtime, ffmpeg_runtime)))
