#!/usr/bin/env python3
"""App Store のアプリ内イベント「ハロウィンの空玉」用の画像を作る。

アプリと同じ描画で書き出したジャックオランタン付きの空玉(EventArtRenderTests が出力)を、
アプリ内と同じ配色の空(夜の紫→夕焼けのオレンジ)・月・こうもりに重ねる。
文字は入れない(App Store 側がイベント名を重ねて表示するため)。

出力:
  event-card-1920x1080.png   イベントカード(16:9)
  event-detail-1080x1920.png イベント詳細(9:16)
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

NIGHT = (40, 16, 76)
DUSK = (88, 34, 96)
SUNSET = (214, 104, 46)


def sky(size: tuple[int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / (height - 1)
        if t < 0.55:
            k = t / 0.55
            color = tuple(round(a + (b - a) * k) for a, b in zip(NIGHT, DUSK))
        else:
            k = (t - 0.55) / 0.45
            color = tuple(round(a + (b - a) * k) for a, b in zip(DUSK, SUNSET))
        draw.line([(0, y), (width, y)], fill=color)
    return image


def add_stars(image: Image.Image, count: int, seed: int) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(image)
    width, height = image.size
    for _ in range(count):
        x, y = rng.randrange(width), rng.randrange(int(height * 0.5))
        r = rng.choice([1, 1, 2])
        alpha = rng.randrange(120, 220)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 245, 230, alpha))


def add_moon(image: Image.Image, center: tuple[int, int], radius: int) -> None:
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    cx, cy = center
    gdraw.ellipse([cx - radius * 1.6, cy - radius * 1.6, cx + radius * 1.6, cy + radius * 1.6],
                  fill=(255, 200, 110, 110))
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.45))
    image.alpha_composite(glow)
    moon = Image.new("RGBA", image.size, (0, 0, 0, 0))
    mdraw = ImageDraw.Draw(moon)
    for i in range(radius, 0, -1):
        k = i / radius
        color = (255, round(248 - 36 * k), round(214 - 84 * k), 255)
        off = (1 - k) * radius * 0.18
        mdraw.ellipse([cx - i - off, cy - i - off, cx + i - off, cy + i - off], fill=color)
    mdraw.ellipse([cx + radius * 0.15, cy + radius * 0.1, cx + radius * 0.45, cy + radius * 0.4],
                  fill=(236, 186, 110, 110))
    image.alpha_composite(moon)


def bat_polygon(cx: float, cy: float, w: float) -> list[tuple[float, float]]:
    h = w * 0.6
    pts = [(0.5, 0.3), (0.46, 0.14), (0.43, 0.3), (0.22, 0.05), (0.0, 0.18), (0.06, 0.42),
           (0.12, 0.62), (0.25, 0.56), (0.36, 0.68), (0.5, 0.82), (0.64, 0.68), (0.75, 0.56),
           (0.88, 0.62), (0.94, 0.42), (1.0, 0.18), (0.78, 0.05), (0.57, 0.3), (0.54, 0.14)]
    return [(cx - w / 2 + x * w, cy - h / 2 + y * h) for x, y in pts]


def add_bats(image: Image.Image, bats: list[tuple[float, float, float]]) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for x, y, w in bats:
        draw.polygon(bat_polygon(x, y, w), fill=(22, 8, 32, 235))
    image.alpha_composite(layer)


def load_orb(source: Path, size: int) -> Image.Image:
    """アプリと同じ描画で書き出したハロウィンの空玉(背景透明)を読み込む。"""
    return Image.open(source).convert("RGBA").resize((size, size), Image.LANCZOS)


def compose(size, orb, orb_center, moon, bats, stars_seed) -> Image.Image:
    image = sky(size).convert("RGBA")
    add_stars(image, count=size[0] * size[1] // 9000, seed=stars_seed)
    add_moon(image, *moon)
    add_bats(image, bats)
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    hx, hy = orb_center
    hr = orb.width * 0.55
    ImageDraw.Draw(halo).ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(255, 140, 50, 70))
    image.alpha_composite(halo.filter(ImageFilter.GaussianBlur(hr * 0.35)))
    image.alpha_composite(orb, (round(hx - orb.width / 2), round(hy - orb.height / 2)))
    return image.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--orb", type=Path, required=True,
                        help="Transparent PNG written by EventArtRenderTests (SORADAMA_RENDER_EVENT_ORB)")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    card = compose(
        (1920, 1080),
        load_orb(args.orb, 900),
        orb_center=(960, 520),
        moon=((1560, 230), 110),
        bats=[(330, 210, 120), (520, 360, 80), (1250, 150, 70), (1700, 520, 95), (240, 560, 70)],
        stars_seed=7,
    )
    card.save(args.output / "event-card-1920x1080.png")

    detail = compose(
        (1080, 1920),
        # 詳細ページは下側に App Store の文字が重なるため、玉を上半分に置く。
        load_orb(args.orb, 900),
        orb_center=(540, 700),
        moon=((830, 230), 105),
        bats=[(220, 200, 120), (430, 120, 70), (900, 470, 85), (170, 900, 80), (880, 1030, 70)],
        stars_seed=11,
    )
    detail.save(args.output / "event-detail-1080x1920.png")
    print("wrote", sorted(p.name for p in args.output.glob("*.png")))


if __name__ == "__main__":
    main()
