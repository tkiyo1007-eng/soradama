#!/usr/bin/env python3
"""App Store のアプリ内イベント「冬のはじまりの空玉」「クリスマスの空玉」「冬至から大寒の空玉」の画像を作る。

アプリと同じ描画で書き出した空玉(EventArtRenderTests.renderWinterOrbs / renderMidwinterOrbs が出力)を、
アプリ内と近い配色の空に重ねる。文字は入れない(App Store 側がイベント名を重ねて表示するため)。
天気の演出と見間違えないよう、雪や雨は描かない。

出力(各フォルダ):
  event-card-1920x1080.png   イベントカード(16:9)
  event-detail-1080x1920.png イベント詳細(9:16)
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def gradient(size, stops):
    """stops: [(位置0〜1, (r,g,b)), ...] の縦グラデーション。"""
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / (height - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                k = (t - p0) / (p1 - p0)
                color = tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
                break
        draw.line([(0, y), (width, y)], fill=color)
    return image.convert("RGBA")


def add_stars(image, count, seed, top=0.6):
    rng = random.Random(seed)
    draw = ImageDraw.Draw(image)
    width, height = image.size
    for _ in range(count):
        x, y = rng.randrange(width), rng.randrange(int(height * top))
        r = rng.choice([1, 1, 2])
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 250, 240, rng.randrange(110, 220)))


def sparkle(cx, cy, r):
    points = []
    for i in range(8):
        angle = i * math.pi / 4 - math.pi / 2
        radius = r if i % 2 == 0 else r * 0.22
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def add_big_star(image, center, radius, color):
    cx, cy = center
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color + (120,))
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(radius * 0.5)))
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(sparkle(cx, cy, radius), fill=(255, 250, 230, 255))
    image.alpha_composite(layer)


def add_lights(image, count, seed):
    """クリスマスの金色の光の粒(アプリの ChristmasSkyGlow と同じ考え方。雪には見せない)。"""
    rng = random.Random(seed)
    width, height = image.size
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for _ in range(count):
        x, y = rng.randrange(width), rng.randrange(int(height * 0.25), height)
        r = rng.randrange(6, 14)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 214, 120, rng.randrange(90, 170)))
    image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(5)))


def add_orb(image, orb_path, center, size, halo):
    orb = Image.open(orb_path).convert("RGBA").resize((size, size), Image.LANCZOS)
    cx, cy = center
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    hr = size * 0.42
    ImageDraw.Draw(glow).ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=halo + (70,))
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(hr * 0.35)))
    image.alpha_composite(orb, (round(cx - size / 2), round(cy - size / 2)))


# 冬のはじまり: 夜の紺から、立冬の朝の淡い桃色へ
WINTER_SKY = [(0.0, (14, 24, 62)), (0.55, (44, 62, 120)), (0.85, (150, 140, 180)), (1.0, (232, 188, 176))]
# クリスマス: アプリの ChristmasPalette.night から常緑・金色へ
CHRISTMAS_SKY = [(0.0, (12, 22, 60)), (0.6, (20, 40, 82)), (0.85, (24, 70, 66)), (1.0, (120, 104, 56))]


def winter(orbs: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    card = gradient((1920, 1080), WINTER_SKY)
    add_stars(card, 260, seed=3)
    add_orb(card, orbs / "orb-ritto.png", (620, 560), 1150, (255, 200, 190))
    add_orb(card, orbs / "orb-fullmoon.png", (1300, 500), 1150, (255, 240, 200))
    card.convert("RGB").save(output / "event-card-1920x1080.png")

    detail = gradient((1080, 1920), WINTER_SKY)
    add_stars(detail, 260, seed=5)
    # 詳細ページは下側に App Store の文字が重なるため、玉を上半分に置く。
    add_orb(detail, orbs / "orb-fullmoon.png", (680, 480), 1100, (255, 240, 200))
    add_orb(detail, orbs / "orb-ritto.png", (400, 1000), 1100, (255, 200, 190))
    detail.convert("RGB").save(output / "event-detail-1080x1920.png")


def christmas(orbs: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    card = gradient((1920, 1080), CHRISTMAS_SKY)
    add_stars(card, 220, seed=9)
    add_big_star(card, (1580, 220), 70, (255, 214, 120))
    add_lights(card, 40, seed=4)
    add_orb(card, orbs / "orb-christmas.png", (960, 520), 1250, (255, 210, 120))
    card.convert("RGB").save(output / "event-card-1920x1080.png")

    detail = gradient((1080, 1920), CHRISTMAS_SKY)
    add_stars(detail, 220, seed=12)
    add_big_star(detail, (850, 220), 70, (255, 214, 120))
    add_lights(detail, 50, seed=8)
    add_orb(detail, orbs / "orb-christmas.png", (540, 760), 1500, (255, 210, 120))
    detail.convert("RGB").save(output / "event-detail-1080x1920.png")


# 冬至から大寒: 夜の紺から、冬至の夕暮れの淡い橙へ
MIDWINTER_SKY = [(0.0, (10, 18, 52)), (0.55, (36, 50, 104)), (0.85, (120, 110, 150)), (1.0, (226, 160, 128))]


def midwinter(orbs: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    card = gradient((1920, 1080), MIDWINTER_SKY)
    add_stars(card, 260, seed=21)
    add_orb(card, orbs / "orb-toji.png", (420, 590), 940, (255, 190, 160))
    add_orb(card, orbs / "orb-fullmoon-dec.png", (960, 470), 940, (255, 240, 200))
    add_orb(card, orbs / "orb-daikan.png", (1500, 590), 940, (255, 205, 190))
    card.convert("RGB").save(output / "event-card-1920x1080.png")

    detail = gradient((1080, 1920), MIDWINTER_SKY)
    add_stars(detail, 260, seed=23)
    # 詳細ページは下側に App Store の文字が重なるため、玉を上半分に置く。
    add_orb(detail, orbs / "orb-fullmoon-dec.png", (540, 400), 950, (255, 240, 200))
    add_orb(detail, orbs / "orb-toji.png", (300, 860), 950, (255, 190, 160))
    add_orb(detail, orbs / "orb-daikan.png", (780, 860), 950, (255, 205, 190))
    detail.convert("RGB").save(output / "event-detail-1080x1920.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--orbs", type=Path,
                        help="Folder written by EventArtRenderTests (SORADAMA_RENDER_WINTER_ORBS)")
    parser.add_argument("--winter-output", type=Path)
    parser.add_argument("--christmas-output", type=Path)
    parser.add_argument("--midwinter-orbs", type=Path,
                        help="Folder written by EventArtRenderTests (SORADAMA_RENDER_MIDWINTER_ORBS)")
    parser.add_argument("--midwinter-output", type=Path)
    args = parser.parse_args()
    if args.orbs and args.winter_output:
        winter(args.orbs, args.winter_output)
    if args.orbs and args.christmas_output:
        christmas(args.orbs, args.christmas_output)
    if args.midwinter_orbs and args.midwinter_output:
        midwinter(args.midwinter_orbs, args.midwinter_output)


if __name__ == "__main__":
    main()
