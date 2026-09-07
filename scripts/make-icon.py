#!/usr/bin/env python3
"""Собирает AppIcon.appiconset из исходной картинки, вписывая её в
скруглённый квадрат macOS с полями и мягкой тенью."""
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "assets", "app-icon-source.jpg")
OUT = os.path.join(HERE, "..", "Mishi Glance", "Assets.xcassets", "AppIcon.appiconset")

CANVAS, SS = 1024, 4
INSET, RADIUS = 100, 185          # сетка иконок macOS: арт-бокс 824×824

def build(src=SRC, out=OUT):
    os.makedirs(out, exist_ok=True)
    mask = Image.new("L", (CANVAS * SS, CANVAS * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [INSET * SS, INSET * SS, (CANVAS - INSET) * SS - 1, (CANVAS - INSET) * SS - 1],
        radius=RADIUS * SS, fill=255)
    mask = mask.resize((CANVAS, CANVAS), Image.LANCZOS)

    art = Image.open(src).convert("RGB").resize(
        (CANVAS - 2 * INSET, CANVAS - 2 * INSET), Image.LANCZOS)
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    layer.paste(art, (INSET, INSET))
    layer.putalpha(mask)

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.putalpha(mask.point(lambda v: int(v * 0.30)))
    shadow = shadow.transform((CANVAS, CANVAS), Image.AFFINE,
                              (1, 0, 0, 0, 1, -10)).filter(ImageFilter.GaussianBlur(14))
    icon = Image.alpha_composite(shadow, layer)

    images = []
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            icon.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
            images.append({"size": f"{base}x{base}", "idiom": "mac",
                           "filename": name, "scale": f"{scale}x"})
    json.dump({"images": images, "info": {"version": 1, "author": "xcode"}},
              open(os.path.join(out, "Contents.json"), "w"), indent=2)
    return len(images)

if __name__ == "__main__":
    print("размеров записано:", build(*(sys.argv[1:3] or [])))
