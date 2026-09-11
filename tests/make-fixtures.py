#!/usr/bin/env python3
"""Готовит наборы изображений, на которых работают оба харнесса."""
import os, sys, time
from PIL import Image, ImageDraw

def build(root):
    basic = os.path.join(root, "basic")
    sortd = os.path.join(root, "sort")
    for d in (basic, sortd):
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))

    # Набор для модельных тестов: разные размеры и веса.
    spec = [("img1.jpg", (4032, 3024)), ("img2.jpg", (800, 600)),
            ("img10.jpg", (1920, 1080)), ("photo.png", (300, 200)),
            ("shot.png", (2560, 1440))]
    colours = [(200, 80, 80), (80, 160, 200), (120, 200, 120),
               (230, 200, 90), (160, 120, 220)]
    for (name, size), colour in zip(spec, colours):
        im = Image.new("RGB", size, colour)
        ImageDraw.Draw(im).text((size[0] // 2 - 40, size[1] // 2),
                                f"{name}\n{size[0]}x{size[1]}", fill=(255, 255, 255))
        im.save(os.path.join(basic, name))

    # Набор для проверки порядка: каверзные имена и крайние пропорции.
    names = ["10.jpg", "2.jpg", "1.jpg", "Foto 2.jpg", "foto 10.jpg",
             "IMG_001.jpg", "img_2.jpg", "Апельсин.jpg", "банан.jpg", "zebra.png"]
    for i, name in enumerate(names):
        Image.new("RGB", (40 + i * 5, 40), (i * 20 % 255, 100, 150)).save(
            os.path.join(sortd, name))
        time.sleep(0.02)
    Image.new("RGB", (1600, 200), (200, 90, 90)).save(os.path.join(sortd, "wide.jpg"))
    Image.new("RGB", (200, 1600), (90, 200, 90)).save(os.path.join(sortd, "tall.jpg"))
    Image.new("RGB", (400, 400), (90, 90, 200)).save(os.path.join(sortd, "square.jpg"))
    # Анимированный GIF: 6 кадров по 80 мс, чтобы проверить разбор задержек.
    frames = [Image.new("RGB", (120, 90), (i * 40 % 256, 90, 200 - i * 20)) for i in range(6)]
    frames[0].save(os.path.join(sortd, "anim.gif"), save_all=True,
                   append_images=frames[1:], duration=80, loop=0)
    # Однотонный кадр с известным средним — эталон для гистограммы.
    Image.new("RGB", (200, 200), (64, 128, 192)).save(os.path.join(sortd, "flat.png"))
    # С альфа-каналом и 16 битами на канал.
    Image.new("RGBA", (80, 80), (10, 20, 30, 128)).save(os.path.join(sortd, "alpha.png"))
    # Набор для поиска повторов: оригинал, точная копия, пережатая
    # и уменьшенная версии плюс заведомо другой кадр.
    dup = os.path.join(root, "dup")
    os.makedirs(dup, exist_ok=True)
    for f in os.listdir(dup):
        os.remove(os.path.join(dup, f))
    src = Image.new("RGB", (600, 400))
    d = ImageDraw.Draw(src)
    for x in range(0, 600, 30):
        d.rectangle([x, 0, x + 15, 400], fill=(x % 255, 120, 200 - x % 200))
    d.ellipse([200, 100, 400, 300], fill=(250, 240, 60))
    src.save(os.path.join(dup, "original.png"))
    src.save(os.path.join(dup, "copy.png"))
    src.save(os.path.join(dup, "recompressed.jpg"), quality=35)
    src.resize((300, 200)).save(os.path.join(dup, "small.jpg"), quality=80)
    other = Image.new("RGB", (600, 400), (20, 30, 40))
    ImageDraw.Draw(other).ellipse([50, 50, 550, 350], fill=(240, 240, 240))
    other.save(os.path.join(dup, "different.png"))
    # Векторный файл: ImageIO его не читает, растрирует AppKit.
    svg = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" width="400" height="300">
  <rect width="400" height="300" fill="#212428"/>
  <circle cx="200" cy="150" r="90" fill="#a656ff"/>
  <rect x="60" y="40" width="80" height="80" fill="#ffffff"/>
</svg>
"""
    with open(os.path.join(sortd, "vector.svg"), "w", encoding="utf-8") as f:
        f.write(svg)
    return basic, sortd

if __name__ == "__main__":
    b, s = build(sys.argv[1])
    print("наборы готовы:", b, s)
