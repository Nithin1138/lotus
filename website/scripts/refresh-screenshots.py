"""Refresh website images from the app's own debug render modes, without changing the app repo.

Requires Pillow. Run with --app <DropDial.exe> --video <sample.mp4> --image <sample.png/jpg>
--render-dir <scratch folder>. Screenshot previews briefly open and close tool windows.
"""
import argparse
import os
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--video', type=Path, required=True)
parser.add_argument('--image', type=Path, required=True)
parser.add_argument('--render-dir', type=Path, required=True)
args = parser.parse_args()
for path in (args.app, args.video, args.image):
    if not path.is_file():
        parser.error(f'Missing input: {path}')
args.render_dir.mkdir(parents=True, exist_ok=True)
out = Path(__file__).resolve().parents[1] / 'assets' / 'img'
# The format wheel depends on the extension: use a PNG for the 8-option screenshot.
photo = args.render_dir / 'holiday.png'
Image.open(args.image).convert('RGB').save(photo)


def render(lang, arguments):
    env = {**os.environ, 'DROPDIAL_LANG': lang}
    subprocess.run([str(args.app.resolve()), *map(str, arguments)],
                   cwd=args.app.resolve().parent, env=env, check=True, timeout=60)


def backdrop(size):
    # Neutral desktop-like backdrop; the wheel itself is the unmodified app render.
    w, h = size
    image = Image.new('RGBA', size)
    draw = ImageDraw.Draw(image)
    for y in range(h):
        shade = int(235 - 31 * y / max(1, h - 1))
        draw.line((0, y, w, y), fill=(shade, shade + 1, shade, 255))
    light = Image.new('RGBA', size)
    ImageDraw.Draw(light).ellipse((-w // 2, -h // 2, w, h // 2), fill=(255, 255, 255, 100))
    image.alpha_composite(light.filter(ImageFilter.GaussianBlur(w // 8)))
    return image


def compose_wheel(path):
    image = Image.open(path).convert('RGBA').resize((720, 720), Image.Resampling.LANCZOS)
    canvas = backdrop(image.size)
    canvas.alpha_composite(image)
    return canvas.convert('RGB')


def compose_jobs(path):
    image = Image.open(path).convert('RGBA')
    # Debug stack has a solid grey backdrop. Replace it with the same neutral backdrop as the wheels.
    pixels = image.load()
    bg = pixels[0, 0]
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) < 4:
                pixels[x, y] = (0, 0, 0, 0)
    image.thumbnail((512, 768), Image.Resampling.LANCZOS)
    canvas = backdrop((536, 792))
    canvas.alpha_composite(image, ((536 - image.width) // 2, (792 - image.height) // 2))
    return canvas.convert('RGB')


for lang in ('en',):
    fmt = args.render_dir / f'wheel-formats-{lang}.png'
    tools = args.render_dir / f'wheel-tools-{lang}.png'
    tool = args.render_dir / f'tool-trim-{lang}.png'
    jobs = args.render_dir / f'jobs-{lang}'
    render(lang, ['--debug-wheel-render', 'formats', photo, 'convert:jpg', fmt])
    render(lang, ['--debug-wheel-render', 'tools', args.video.resolve(), 'trimVideo', tools])
    render(lang, ['--debug-tool-render', 'trimVideo', args.video.resolve(), tool])
    render(lang, ['--debug-indicator', jobs])
    for name, image in (
        (f'wheel-formats-{lang}', compose_wheel(fmt)),
        (f'wheel-tools-{lang}', compose_wheel(tools)),
        (f'tool-trim-{lang}', Image.open(tool).convert('RGB')),
        (f'jobs-{lang}', compose_jobs(Path(str(jobs) + '-expanded.png'))),
    ):
        image.save(out / f'{name}.webp', quality=90, method=6)
        print(f'{name}.webp: {image.size}')

# Share preview: same product copy and composition, but with the current app wheel.
canvas = Image.new('RGBA', (1200, 630), '#FAF8F5')
draw = ImageDraw.Draw(canvas)
fonts = Path(os.environ.get('WINDIR', 'C:/Windows')) / 'Fonts'
bold = ImageFont.truetype(str(fonts / 'segoeuib.ttf'), 76)
regular = ImageFont.truetype(str(fonts / 'segoeui.ttf'), 30)
semibold = ImageFont.truetype(str(fonts / 'seguisb.ttf'), 34)
logo = Image.open(out / 'logo.png').convert('RGBA').resize((72, 72), Image.Resampling.LANCZOS)
canvas.alpha_composite(logo, (72, 70))
draw.text((160, 76), 'DropDial', font=semibold, fill='#1F2226')
draw.text((72, 200), 'Drag. Drop.', font=bold, fill='#1F2226')
draw.text((72, 290), 'Convert.', font=bold, fill='#D55418')
draw.text((72, 410), 'Free file converter for Windows.', font=regular, fill='#5F656D')
draw.text((72, 452), 'Hold Shift while dragging any file.', font=regular, fill='#5F656D')
draw.text((72, 540), 'dropdial.org', font=semibold, fill='#D55418')
shot = Image.open(out / 'wheel-formats-en.webp').convert('RGBA').resize((520, 520), Image.Resampling.LANCZOS)
mask = Image.new('L', shot.size)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 519, 519), radius=28, fill=255)
shadow = Image.new('RGBA', canvas.size)
ImageDraw.Draw(shadow).rounded_rectangle((630, 69, 1150, 589), radius=28, fill=(40, 30, 20, 55))
canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
canvas.paste(shot, (624, 55), mask)
canvas.convert('RGB').save(out / 'og-image.png', optimize=True)
print('og-image.png: (1200, 630)')
