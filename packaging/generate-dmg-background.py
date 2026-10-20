#!/usr/bin/env python3
"""
Generates multi-resolution Retina (1x and 2x) background images for the DropDial macOS DMG.
Combined using tiffutil for razor-sharp HiDPI display on Mac Retina screens.

Window Dimensions: 680x440 points
- DropDial.app:                center at (160, 105)
- Applications symlink:        center at (520, 105)
- Bottom: Gentle First-Launch tips for standard macOS Gatekeeper approval (System Settings & Right-Click)
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
    def get_font(size_pt):
        scaled_size = int(size_pt * scale)
        font_paths = [
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/SFPro-Regular.ttf",
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

    font_pill = get_font(12)
    font_badge = get_font(10)
    font_h2 = get_font(11.5)
    font_w_title = get_font(12)
    font_w_desc = get_font(11)
    font_tip = get_font(10.5)

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
    # BOTTOM ZONE: Gentle First-Launch Guidance Card (y: 205 to 424)
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

    # 1. Card Header: Gentle Badge + Subtitle (Not mandatory)
    badge_text = "FIRST LAUNCH TIP"
    bb = draw.textbbox((0, 0), badge_text, font=font_badge)
    bw = bb[2] - bb[0]
    bx, by = S(48), S(219)
    draw.rounded_rectangle(
        [bx, by, bx + bw + S(16), by + S(22)],
        radius=S(6),
        fill=(30, 58, 138), # Subtle deep blue
        outline=(96, 165, 250), # Soft sky blue
        width=max(1, S(1))
    )
    draw.text((bx + S(8), by + S(4)), badge_text, fill=(255, 255, 255), font=font_badge)

    h1_text = "If macOS displays a verification alert on first open:"
    draw.text((bx + bw + S(26), by + S(4)), h1_text, fill=(226, 232, 240), font=font_h2)

    # 2. Way 1: System Settings Box
    box1_y1, box1_y2 = S(252), S(314)
    draw.rounded_rectangle(
        [S(48), box1_y1, S(632), box1_y2],
        radius=S(8),
        fill=(15, 23, 42),
        outline=(51, 65, 85),
        width=max(1, S(1))
    )
    draw.text((S(62), box1_y1 + S(8)), "1. In System Settings → Privacy & Security:", fill=(56, 189, 248), font=font_w_title)
    draw.text((S(62), box1_y1 + S(32)), "Scroll down to the Security section and click “Open Anyway”.", fill=(203, 213, 225), font=font_w_desc)

    # 3. Way 2: Applications Right-Click Box
    box2_y1, box2_y2 = S(324), S(386)
    draw.rounded_rectangle(
        [S(48), box2_y1, S(632), box2_y2],
        radius=S(8),
        fill=(15, 23, 42),
        outline=(51, 65, 85),
        width=max(1, S(1))
    )
    draw.text((S(62), box2_y1 + S(8)), "2. Or Right-Click DropDial in Applications:", fill=(251, 191, 36), font=font_w_title)
    draw.text((S(62), box2_y1 + S(32)), "Hold Control (or Right-Click) DropDial in Applications and click “Open” → “Open”.", fill=(203, 213, 225), font=font_w_desc)

    # 4. Footer Note
    tip_text = "• DropDial is 100% offline & safe. This is only needed if prompted on first launch."
    draw.text((S(52), S(398)), tip_text, fill=(148, 163, 184), font=font_tip)

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
