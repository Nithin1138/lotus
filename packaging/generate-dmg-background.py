#!/usr/bin/env python3
"""
Generates multi-resolution Retina (1x and 2x) background images for the DropDial macOS DMG.
Combined using tiffutil for razor-sharp HiDPI display on Mac Retina screens.

Window Dimensions: 680x440 points
- DropDial.app:                center at (160, 105)
- Applications symlink:        center at (520, 105)
- Bottom: Clean, unified First-Launch approval guide with 1-line terminal command
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

    # Helper font loader with scaling
    def get_font(size_pt, bold=False, mono=False):
        scaled_size = int(size_pt * scale)
        if mono:
            mono_paths = [
                "/System/Library/Fonts/Menlo.ttc",
                "/System/Library/Fonts/Courier.dfont",
                "/Library/Fonts/Courier New.ttf"
            ]
            for p in mono_paths:
                if os.path.exists(p):
                    try:
                        return ImageFont.truetype(p, scaled_size)
                    except Exception:
                        continue

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

    def S(val):
        return int(val * scale)

    font_pill = get_font(12, bold=True)
    font_badge = get_font(10, bold=True)
    font_h1 = get_font(13.5, bold=True)
    font_h2 = get_font(11, bold=False)
    font_opt_title = get_font(11.5, bold=True)
    font_opt_desc = get_font(11, bold=False)
    font_cmd = get_font(11, mono=True)
    font_tip = get_font(10, bold=False)

    # -------------------------------------------------------------
    # TOP ZONE: Drag & Drop Area (y: 0 to 195)
    # -------------------------------------------------------------
    arrow_y = S(105)
    arrow_color = (56, 189, 248) # Cyan #38bdf8
    draw.line([(S(245), arrow_y), (S(430), arrow_y)], fill=arrow_color, width=max(2, S(3)))
    # Arrowhead
    draw.polygon([
        (S(445), arrow_y),
        (S(430), arrow_y - S(8)),
        (S(430), arrow_y + S(8))
    ], fill=arrow_color)

    # Drag Instruction Pill Badge above the arrow
    pill_text = "Drag DropDial to Applications"
    pb = draw.textbbox((0, 0), pill_text, font=font_pill)
    pw = pb[2] - pb[0]
    px = S(340) - (pw / 2)
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
    draw.rounded_rectangle([S(115), S(150), S(205), S(172)], radius=S(6), fill=(248, 250, 252), outline=(203, 213, 225), width=max(1, S(1)))
    draw.rounded_rectangle([S(465), S(150), S(575), S(172)], radius=S(6), fill=(248, 250, 252), outline=(203, 213, 225), width=max(1, S(1)))

    # -------------------------------------------------------------
    # DIVIDER LINE (y: 195)
    # -------------------------------------------------------------
    draw.line([(S(30), S(195)), (S(650), S(195))], fill=(30, 41, 59), width=max(1, S(1)))

    # -------------------------------------------------------------
    # BOTTOM ZONE: Unified Instructions Card (y: 205 to 424)
    # -------------------------------------------------------------
    card_x1, card_y1 = S(30), S(205)
    card_x2, card_y2 = S(650), S(424)
    draw.rounded_rectangle(
        [card_x1, card_y1, card_x2, card_y2],
        radius=S(12),
        fill=(11, 17, 32),
        outline=(30, 41, 59),
        width=max(1, S(1.5))
    )

    # 1. Card Header: Badge + Title
    badge_text = "FIRST-TIME LAUNCH APPROVAL"
    bb = draw.textbbox((0, 0), badge_text, font=font_badge)
    bw = bb[2] - bb[0]
    bx = S(48)
    by = S(217)
    draw.rounded_rectangle(
        [bx, by, bx + bw + S(16), by + S(20)],
        radius=S(6),
        fill=(2, 132, 199), # Sky Blue
        outline=(56, 189, 248),
        width=max(1, S(1))
    )
    draw.text((bx + S(8), by + S(3)), badge_text, fill=(255, 255, 255), font=font_badge)

    h1_text = "DropDial is 100% offline & safe. Gatekeeper needs a one-time launch approval:"
    draw.text((bx + bw + S(28), by + S(3)), h1_text, fill=(226, 232, 240), font=font_h2)

    # 2. Option A: 1-Line Terminal Command (Recommended)
    opt1_title = "Option A (Fastest · Instant Launch) — Run in Terminal:"
    draw.text((S(48), S(248)), opt1_title, fill=(56, 189, 248), font=font_opt_title)

    # Terminal box
    cmd_box_y1 = S(268)
    cmd_box_y2 = S(304)
    draw.rounded_rectangle(
        [S(48), cmd_box_y1, S(632), cmd_box_y2],
        radius=S(7),
        fill=(3, 7, 18),
        outline=(51, 65, 85),
        width=max(1, S(1))
    )
    # Terminal prompt & command
    draw.text((S(58), cmd_box_y1 + S(8)), "$", fill=(34, 197, 94), font=font_cmd) # Green $
    cmd_text = "xattr -cr /Applications/DropDial.app && open /Applications/DropDial.app"
    draw.text((S(76), cmd_box_y1 + S(8)), cmd_text, fill=(241, 245, 249), font=font_cmd)

    # 3. Option B: Finder Right-Click (No Terminal)
    opt2_title = "Option B (No Terminal) — Right-Click in Applications:"
    draw.text((S(48), S(318)), opt2_title, fill=(251, 191, 36), font=font_opt_title)

    opt2_desc = "1. Drag DropDial to Applications   2. Right-Click DropDial → click “Open” → click “Open”"
    draw.text((S(48), S(338)), opt2_desc, fill=(203, 213, 225), font=font_opt_desc)

    opt2_sub = "(Or in System Settings → Privacy & Security, scroll down and click “Open Anyway”)"
    draw.text((S(48), S(358)), opt2_sub, fill=(148, 163, 184), font=font_tip)

    # 4. Footer Tip
    tip_text = "✓ Required only once for direct indie apps. DropDial will launch normally forever after."
    draw.text((S(48), S(394)), tip_text, fill=(100, 116, 139), font=font_tip)

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
