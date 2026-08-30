#!/usr/bin/env python3
"""Compose Japanese App Store screenshots from genuine Simulator captures.

The output is the 6.7-inch portrait size accepted by App Store Connect:
1284 x 2778 pixels, RGB PNG without an alpha channel.
"""

from __future__ import annotations

import argparse
import glob
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


CANVAS_SIZE = (1284, 2778)
PHONE_INNER_SIZE = (890, 1925)
PHONE_INNER_ORIGIN = (197, 675)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", required=True, type=Path)
    parser.add_argument("--widget", required=True, type=Path)
    parser.add_argument("--collection", required=True, type=Path)
    parser.add_argument("--radar", required=True, type=Path)
    parser.add_argument("--month", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def font_path() -> str:
    candidates = glob.glob("/System/Library/Fonts/*W8.ttc")
    if candidates:
        return candidates[0]
    return "/System/Library/Fonts/Hiragino Sans GB.ttc"


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    colors: list[tuple[int, int, int]] = []
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = tuple(round(a + (b - a) * ratio) for a, b in zip(top, bottom))
        colors.append(color)
    strip = Image.new("RGB", (1, height))
    strip.putdata(colors)
    return strip.resize((width, height))


def add_glow(canvas: Image.Image, color: tuple[int, int, int]) -> None:
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((-220, 360, 1504, 2320), fill=(*color, 74))
    glow = glow.filter(ImageFilter.GaussianBlur(190))
    canvas.paste(glow, (0, 0), glow)


def add_centered_text(draw: ImageDraw.ImageDraw, text: str, y: int, font: ImageFont.FreeTypeFont, fill: str) -> None:
    box = draw.textbbox((0, 0), text, font=font)
    width = box[2] - box[0]
    draw.text(((CANVAS_SIZE[0] - width) / 2, y), text, font=font, fill=fill)


def add_phone(canvas: Image.Image, source_path: Path) -> None:
    source = Image.open(source_path).convert("RGB")
    if source.size != CANVAS_SIZE:
        raise ValueError(f"{source_path} is {source.size}; expected {CANVAS_SIZE}")

    inner_x, inner_y = PHONE_INNER_ORIGIN
    inner_w, inner_h = PHONE_INNER_SIZE
    outer_box = (178, 656, 1106, 2618)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((157, 646, 1127, 2651), radius=96, fill=(0, 0, 0, 155))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas.paste(shadow, (0, 0), shadow)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(outer_box, radius=88, fill="#030612")

    resized = source.resize(PHONE_INNER_SIZE, Image.Resampling.LANCZOS)
    mask = Image.new("L", PHONE_INNER_SIZE, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner_w, inner_h), radius=70, fill=255)
    canvas.paste(resized, PHONE_INNER_ORIGIN, mask)

    # A neutral device cutout keeps the presentation consistent across captures.
    draw.rounded_rectangle((522, inner_y + 24, 762, inner_y + 92), radius=34, fill="#000000")


def compose(source: Path, first_line: str, second_line: str, output: Path, glow: tuple[int, int, int]) -> None:
    canvas = gradient(CANVAS_SIZE, (8, 20, 56), (22, 43, 103))
    add_glow(canvas, glow)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(font_path(), 88)
    add_centered_text(draw, first_line, 118, font, "#FFFFFF")
    add_centered_text(draw, second_line, 262, font, "#95C9FF")
    add_phone(canvas, source)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output, format="PNG", optimize=True)


def contact_sheet(paths: list[Path], output: Path) -> None:
    thumb_width = 240
    thumb_height = round(thumb_width * CANVAS_SIZE[1] / CANVAS_SIZE[0])
    gap = 18
    sheet = Image.new("RGB", (gap + len(paths) * (thumb_width + gap), thumb_height + gap * 2), "#071438")
    for index, path in enumerate(paths):
        thumb = Image.open(path).convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (gap + index * (thumb_width + gap), gap))
    sheet.save(output, format="JPEG", quality=92, optimize=True)


def main() -> None:
    args = parse_args()
    specs = [
        (args.home, "今日の天気が、", "ひとつの空玉に", "01-daily-orb.png", (50, 139, 255)),
        (args.widget, "毎日の天気を、", "ホーム画面にも", "02-home-widget.png", (80, 170, 255)),
        (args.collection, "集めた空が、", "自分だけのカレンダーに", "03-collection.png", (126, 106, 255)),
        (args.radar, "予報も雨雲も、", "ひと目で", "04-forecast-radar.png", (20, 190, 225)),
        (args.month, "ひと月の空を、", "1枚で振り返る", "05-month-review.png", (137, 102, 255)),
    ]

    outputs: list[Path] = []
    for source, first, second, filename, glow in specs:
        destination = args.output / filename
        compose(source, first, second, destination, glow)
        outputs.append(destination)
    contact_sheet(outputs, args.output / "preview-contact-sheet.jpg")


if __name__ == "__main__":
    main()
