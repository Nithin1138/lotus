import os
from PIL import Image

def generate_icons():
    source_path = "website/assets/img/icon-512.png"
    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found")
        return

    img = Image.open(source_path).convert("RGBA")
    print(f"Loaded source image {source_path}: {img.size}")

    # 1. In-app asset
    os.makedirs("mobile/dropdial_flutter/assets/icons", exist_ok=True)
    img.save("mobile/dropdial_flutter/assets/icons/app_logo.png", "PNG")
    print("Saved mobile/dropdial_flutter/assets/icons/app_logo.png")

    # 2. Android mipmap icons
    android_base = "mobile/dropdial_flutter/android/app/src/main/res"
    android_sizes = {
        "mipmap-mdpi": (48, 48),
        "mipmap-hdpi": (72, 72),
        "mipmap-xhdpi": (96, 96),
        "mipmap-xxhdpi": (144, 144),
        "mipmap-xxxhdpi": (192, 192),
    }

    for folder, size in android_sizes.items():
        dir_path = os.path.join(android_base, folder)
        os.makedirs(dir_path, exist_ok=True)
        out_file = os.path.join(dir_path, "ic_launcher.png")
        resized = img.resize(size, Image.Resampling.LANCZOS)
        resized.save(out_file, "PNG")
        print(f"Saved {out_file} ({size[0]}x{size[1]})")

    # 3. iOS AppIcon
    ios_base = "mobile/dropdial_flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_sizes = {
        "Icon-App-20x20@1x.png": (20, 20),
        "Icon-App-20x20@2x.png": (40, 40),
        "Icon-App-20x20@3x.png": (60, 60),
        "Icon-App-29x29@1x.png": (29, 29),
        "Icon-App-29x29@2x.png": (58, 58),
        "Icon-App-29x29@3x.png": (87, 87),
        "Icon-App-40x40@1x.png": (40, 40),
        "Icon-App-40x40@2x.png": (80, 80),
        "Icon-App-40x40@3x.png": (120, 120),
        "Icon-App-60x60@2x.png": (120, 120),
        "Icon-App-60x60@3x.png": (180, 180),
        "Icon-App-76x76@1x.png": (76, 76),
        "Icon-App-76x76@2x.png": (152, 152),
        "Icon-App-83.5x83.5@2x.png": (167, 167),
        "Icon-App-1024x1024@1x.png": (1024, 1024),
    }

    if os.path.exists(ios_base):
        for filename, size in ios_sizes.items():
            out_file = os.path.join(ios_base, filename)
            resized = img.resize(size, Image.Resampling.LANCZOS)
            resized.save(out_file, "PNG")
            print(f"Saved {out_file} ({size[0]}x{size[1]})")

    print("All app icons successfully generated!")

if __name__ == "__main__":
    generate_icons()
