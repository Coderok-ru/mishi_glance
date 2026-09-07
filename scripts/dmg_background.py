#!/usr/bin/env python3
"""
Renders the DMG installer background in the Coderok brand style.

Palette and typography are taken from coderok.ru:
  surface  #212428   panel #1e2024   deep #16181c
  accent   #a656ff   heading #ffffff  body #878e99
  Poppins (Latin headings) + Montserrat (Cyrillic — Poppins has no Cyrillic)
"""

import os
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")

WINDOW = (660, 420)          # points; the DMG window size
SCALE = 2                    # render @2x for Retina
W, H = WINDOW[0] * SCALE, WINDOW[1] * SCALE

SURFACE = (33, 36, 40)       # #212428
DEEP = (22, 24, 28)          # #16181c
ACCENT = (166, 86, 255)      # #a656ff
HEADING = (255, 255, 255)
BODY = (135, 142, 153)       # #878e99

# Icon centres in window points, matching dmg_settings.py.
APP_ICON = (170, 205)
APPLICATIONS_ICON = (490, 205)


def font(name, size, weight=None):
    path = os.path.join(ASSETS, name)
    if not os.path.exists(path):
        return ImageFont.load_default(int(size * SCALE))
    face = ImageFont.truetype(path, int(size * SCALE))
    if weight:
        # Montserrat ships as a variable font; pick a named instance.
        try:
            face.set_variation_by_name(weight)
        except Exception:
            pass
    return face


def assert_covered(face, text):
    """Guards against tofu: Poppins carries no Cyrillic, Montserrat does."""
    try:
        from fontTools.ttLib import TTFont
        cmap = TTFont(face.path).getBestCmap()
        missing = {c for c in text if c not in " \u00a0" and ord(c) not in cmap}
        if missing:
            raise SystemExit("шрифт %s не покрывает: %s"
                             % (os.path.basename(face.path), "".join(sorted(missing))))
    except ImportError:
        pass


def render_logo(side):
    """Rasterises the brand SVG through AppKit, which reads SVG natively."""
    svg = os.path.join(ASSETS, "coderok-logo.svg")
    png = os.path.join(ASSETS, ".logo-cache-%d.png" % side)
    if not os.path.exists(png):
        helper = os.path.join(ASSETS, "svg2png")
        if not os.path.exists(helper):
            src = os.path.join(ASSETS, "svg2png.swift")
            if not os.path.exists(src):
                return None
            subprocess.run(["xcrun", "swiftc", "-O", src, "-o", helper], check=True)
        subprocess.run([helper, svg, png, str(side)], check=True,
                       stdout=subprocess.DEVNULL)
    return Image.open(png).convert("RGBA")


def vertical_gradient(size, top, bottom):
    gradient = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        gradient.putpixel((0, y), tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ))
    return gradient.resize(size, Image.BILINEAR)


def accent_glow(size, centre, radius, colour, strength):
    """Soft radial brand glow, the same treatment the site uses behind cards."""
    layer = Image.new("L", size, 0)
    draw = ImageDraw.Draw(layer)
    draw.ellipse(
        [centre[0] - radius, centre[1] - radius,
         centre[0] + radius, centre[1] + radius],
        fill=int(255 * strength),
    )
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    tint = Image.new("RGB", size, colour)
    return tint, layer


def draw_arrow(draw, start, end, y, colour):
    """Thin shaft with a solid head, pointing at the Applications folder."""
    thickness = 3 * SCALE
    head = 13 * SCALE
    draw.line([(start, y), (end - head, y)], fill=colour, width=thickness)
    draw.polygon(
        [(end, y), (end - head, y - head * 0.55), (end - head, y + head * 0.55)],
        fill=colour,
    )


def build(destination):
    image = vertical_gradient((W, H), SURFACE, DEEP).convert("RGB")

    tint, mask = accent_glow((W, H), (W // 2, int(H * 0.52)),
                             int(W * 0.30), ACCENT, 0.16)
    image = Image.composite(tint, image, mask)
    image = image.convert("RGBA")

    draw = ImageDraw.Draw(image)

    logo = render_logo(120)
    if logo is not None:
        logo = logo.resize((36 * SCALE, 36 * SCALE), Image.LANCZOS)
        image.alpha_composite(logo, (int(W / 2 - 18 * SCALE), 34 * SCALE))

    # Latin wordmark keeps Poppins; every Cyrillic string uses Montserrat.
    title_font = font("Poppins-SemiBold.ttf", 25)
    subtitle_font = font("Montserrat.ttf", 12, "Medium")
    hint_font = font("Montserrat.ttf", 11.5, "SemiBold")
    footer_font = font("Montserrat.ttf", 10, "Regular")

    def centred(text, y, fnt, fill):
        assert_covered(fnt, text)
        width = draw.textlength(text, font=fnt)
        draw.text((W / 2 - width / 2, y * SCALE), text, font=fnt, fill=fill)

    centred("Mishi Glance", 84, title_font, HEADING)
    centred("Просмотрщик изображений для macOS", 122, subtitle_font, BODY)

    draw_arrow(draw,
               (APP_ICON[0] + 58) * SCALE,
               (APPLICATIONS_ICON[0] - 58) * SCALE,
               APP_ICON[1] * SCALE,
               ACCENT)

    centred("Перетащите Mishi Glance в папку «Программы»", 300, hint_font, BODY)
    centred("coderok.ru · Андрей Любиченко", 372, footer_font, (95, 101, 111))

    image.convert("RGB").save(destination, "PNG")

    at1x = image.resize(WINDOW, Image.LANCZOS).convert("RGB")
    at1x.save(destination.replace(".png", "-1x.png"), "PNG")
    return destination


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "dmg-background.png")
    print("написано:", build(out))
