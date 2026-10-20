#!/usr/bin/env python3
"""
Generates multi-resolution Retina (1x and 2x) background images for the DropDial macOS DMG.
Combined using tiffutil for razor-sharp HiDPI display on Mac Retina screens.

Window Dimensions: 680x440 points
- DropDial.app:                center at (160, 105)
- Applications symlink:        center at (500, 105)
- Open DropDial.command:       center at (120, 325)
"""
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

def draw_canvas(scale=1):
    width = 680 * scale
    height = 440 * scale
    
    # Base dark background matching website theme (#090d16 to #0f172a)
    im = Image.new("RGB", (width, height), (9, 13, 22))
    draw = ImageDraw.Draw(im)
    
    for y in range(height):
        ratio = y / height
        r = int(9 + (15 - 9) * ratio)
        g = int(13 + (23 - 13) * ratio)
        b = int(22 + (42 - 22) * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Helper font loader with 2x scaling
    def get_font(size_pt, bold=False):
        scaled_size = int(size_pt * scale)
        font_paths = [
            "/System/Library/Fonts/SFPro-Bold.ttf" if bold else "/System/Library/Fonts/SFPro-Regular.ttf",
            "/System/Library/Fonts/SFCompact-Bold.ttf" if bold else "/System/Library/Fonts/SFCompact-Regular.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
            "/Library/Fonts/Arial.ttf"
        ]
        for p in font_paths:
            if os.path.exists(p):
                try:
                    return ImageFont.truetype(p, scaled_size)
                except Exception:
                    continue
        return ImageFont.load_default()

    font_pill = get_font(12, bold=True)
    font_h1 = get_font(14.5, bold=True)
    font_h2 = get_font(11.5, bold=False)
    font_m_title = get_font(12, bold=True)
    font_m_desc = get_font(11, bold=False)
    font_badge = get_font(10.5, bold=True)
    font_tip = get_font(10.5, bold=False)

    def S(val):
        return int(val * scale)

    # -------------------------------------------------------------
    # TOP ZONE: Drag & Drop Area (y: 0 to 200)
    # -------------------------------------------------------------
    arrow_y = S(105)
    arrow_color = (56, 189, 248) # Cyan #38bdf8
    draw.line([(S(235), arrow_y), (S(410), arrow_y)], fill=arrow_color, width=max(2, S(3)))
    # Arrowhead
    draw.polygon([
        (S(425), arrow_y),
        (S(410), arrow_y - S(8)),
        (S(410), arrow_y + S(8))
    ], fill=arrow_color)

    # Drag Instruction Pill Badge above the arrow
    pill_text = "Drag DropDial to Applications"
    pb = draw.textbbox((0, 0), pill_text, font=font_pill)
    pw = pb[2] - pb[0]
    px = S(330) - (pw / 2)
    py = S(66)
    draw.rounded_rectangle(
        [px - S(14), py - S(4), px + pw + S(14), py + S(22)],
        radius=S(10),
        fill=(15, 23, 42),
        outline=(56, 189, 248),
        width=max(1, S(1))
    )
    draw.text((px, py), pill_text, fill=(56, 189, 248), font=font_pill)

    # Frosted high-contrast label plates under DropDial.app and Applications icon labels
    draw.rounded_rectangle([S(115), S(148), S(205), S(170)], radius=S(6), fill=(248, 250, 252), outline=(203, 213, 225), width=max(1, S(1)))
    draw.rounded_rectangle([S(445), S(148), S(555), S(170)], radius=S(6), fill=(248, 250, 252), outline=(203, 213, 225), width=max(1, S(1)))

    # -------------------------------------------------------------
    # DIVIDER LINE (y: 205)
    # -------------------------------------------------------------
    draw.line([(S(30), S(205)), (S(650), S(205))], fill=(30, 41, 59), width=max(1, S(1)))

    # -------------------------------------------------------------
    # BOTTOM ZONE: Left Launcher Card & Right Instructions Card
    # -------------------------------------------------------------
    
    # 1. Left Card: 1-Click Launcher Frame (x=30 to x=210, y=218 to y=422)
    draw.rounded_rectangle(
        [S(30), S(218), S(210), S(422)],
        radius=S(12),
        fill=(15, 23, 42),
        outline=(249, 115, 22), # Orange border matching RECOMMENDED badge
        width=max(1, S(1.5))
    )
    
    # VIBRANT ORANGE RECOMMENDED BADGE requested by user
    badge_text = "RECOMMENDED"
    bb = draw.textbbox((0, 0), badge_text, font=font_badge)
    bw = bb[2] - bb[0]
    badge_x = S(120) - bw/2
    draw.rounded_rectangle(
        [badge_x - S(10), S(226), badge_x + bw + S(10), S(248)],
        radius=S(6),
        fill=(234, 88, 12), # Vibrant Orange #ea580c
        outline=(251, 146, 60), # Bright orange border #fb923c
        width=max(1, S(1))
    )
    draw.text((badge_x, S(230)), badge_text, fill=(255, 255, 255), font=font_badge)

    # White title baked into background directly above the launcher icon
    launcher_white_title = "Open DropDial"
    lt_b = draw.textbbox((0, 0), launcher_white_title, font=font_pill)
    lt_w = lt_b[2] - lt_b[0]
    draw.text((S(120) - lt_w/2, S(256)), launcher_white_title, fill=(255, 255, 255), font=font_pill)

    # Frosted high-contrast pill plate under the Finder filename label (y=360 to y=398)
    # This guarantees the forced black Finder label is 100% razor-sharp and legible
    draw.rounded_rectangle(
        [S(40), S(360), S(200), S(400)],
        radius=S(8),
        fill=(248, 250, 252), # Pure frosted white-silver #f8fafc
        outline=(203, 213, 225), # #cbd5e1
        width=max(1, S(1))
    )

    # 2. Right Card: Approval Guide (x=225 to x=650, y=218 to y=422)
    draw.rounded_rectangle(
        [S(225), S(218), S(650), S(422)],
        radius=S(12),
        fill=(15, 23, 42),
        outline=(51, 65, 85),
        width=max(1, S(1))
    )

    # Text content on the right card (clean, crisp, zero corrupt unicode boxes)
    tx = S(245)
    # Header
    h1 = "DropDial is 100% offline and safe."
    draw.text((tx, S(228)), h1, fill=(255, 255, 255), font=font_h1)

    h2 = "Because it's direct indie software, macOS asks for a one-time launch approval:"
    draw.text((tx, S(252)), h2, fill=(148, 163, 184), font=font_h2)

    # Method 1
    m1_title = "1. Open DropDial (First Time).command instantly"
    draw.text((tx, S(282)), m1_title, fill=(56, 189, 248), font=font_m_title)
    m1_desc = "   Double-click the launcher on the left to bypass Gatekeeper instantly."
    draw.text((tx, S(302)), m1_desc, fill=(203, 213, 225), font=font_m_desc)

    # Method 2
    m2_title = "2. In System Settings -> Privacy & Security, click “Open Anyway”"
    draw.text((tx, S(330)), m2_title, fill=(251, 191, 36), font=font_m_title)
    m2_desc = "   Or right-click DropDial in Applications and click Open."
    draw.text((tx, S(350)), m2_desc, fill=(203, 213, 225), font=font_m_desc)

    # Tip at bottom of card
    tip = "• Once approved on first launch, DropDial opens normally anytime."
    draw.text((tx, S(390)), tip, fill=(100, 116, 139), font=font_tip)

    return im

def build_retina_dmg_background(output_dir):
    os.makedirs(output_dir, exist_ok=True)
    img_1x = os.path.join(output_dir, "background.png")
    img_2x = os.path.join(output_dir, "background@2x.png")
    tiff_out = os.path.join(output_dir, "background.tiff")

    # Render 1x and 2x Retina
    im1 = draw_canvas(scale=1)
    im1.save(img_1x, "PNG")

    im2 = draw_canvas(scale=2)
    im2.save(img_2x, "PNG")

    # Merge into multi-resolution HiDPI TIFF
    cmd = ["tiffutil", "-cathidpicheck", img_1x, img_2x, "-out", tiff_out]
    try:
        subprocess.check_call(cmd)
        print(f"Created HiDPI Retina TIFF: {tiff_out}")
    except Exception as e:
        print(f"tiffutil failed ({e}), falling back to PNG")
        tiff_out = img_1x

    return tiff_out

if __name__ == "__main__":
    import sys
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "outputs"
    build_retina_dmg_background(out_dir)
