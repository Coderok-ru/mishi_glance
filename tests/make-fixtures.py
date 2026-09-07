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
    return basic, sortd

if __name__ == "__main__":
    b, s = build(sys.argv[1])
    print("наборы готовы:", b, s)
