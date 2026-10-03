#!/usr/bin/env python3
"""App Store スクリーンショット(2026年10月版)を作る。

検索結果では最初の3枚が小さく並ぶため、
- 1枚目は空玉そのもの(アプリと同じ描画で書き出した玉)を大きく見せる
- 見出しを大きく短くする
- 2枚目以降は本物の Simulator 画面を端末の枠に入れる
出力は 1284 x 2778 の RGB PNG(App Store Connect の 6.5/6.7 インチ枠で使える)。

入力:
  --orbs     StoreArtRenderTests が書き出した空玉 PNG のフォルダ
  --captures StoreScreenshotTests が撮った画面(ja-home.png など)のフォルダ
  --legacy   以前のポスター(02-home-widget.png, 04-forecast-radar.png)のフォルダ。枠の中だけ再利用する
"""

from __future__ import annotations

import argparse
import glob
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CANVAS = (1284, 2778)
HEADLINE_SIZE = 112
PHONE_OUTER = (162, 700, 1122, 2778 + 120)  # 下端は画面外まで伸ばし、端末を大きく見せる
LEGACY_INNER_ORIGIN = (197, 675)
LEGACY_INNER_SIZE = (890, 1925)

COPY = {
    "ja": {
        "hero": ("その日の空が", "ころんと玉になる"),
        "hero_caption": "空を集める天気アプリ「空玉」",
        "collection": ("ひと月つづけると", "こんなカレンダーに"),
        "home": ("傘いる？いらない？", "開いてすぐわかる"),
        "month": ("月末には", "ひと月の空をふりかえり"),
        "widget": ("ホーム画面に", "今日の空玉を置いておく"),
        "radar": ("雨雲が近づいたら", "地図でたしかめる"),
    },
    "en": {
        "hero": ("Today's sky,", "in a little glass orb"),
        "hero_caption": "Soradama — collect your skies",
        "collection": ("A month of days,", "one orb at a time"),
        "home": ("Need an umbrella?", "Know in a second"),
        "month": ("Look back on", "the month you had"),
    },
}


def font(size: int) -> ImageFont.FreeTypeFont:
    candidates = glob.glob("/System/Library/Fonts/*W8.ttc") or ["/System/Library/Fonts/Hiragino Sans GB.ttc"]
    return ImageFont.truetype(candidates[0], size)


def background() -> Image.Image:
    width, height = CANVAS
    top, bottom = (10, 18, 58), (44, 32, 104)
    strip = Image.new("RGB", (1, height))
    strip.putdata([tuple(round(a + (b - a) * y / (height - 1)) for a, b in zip(top, bottom)) for y in range(height)])
    canvas = strip.resize(CANVAS).convert("RGBA")
    glow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-200, 700, 1484, 2500), fill=(110, 120, 255, 70))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(220)))
    return canvas


def headline(canvas: Image.Image, lines: tuple[str, str], top: int = 120) -> None:
    draw = ImageDraw.Draw(canvas)
    # 2行とも横幅に収まる最大の大きさにそろえる(英語は日本語より長くなりやすい)。
    size = HEADLINE_SIZE
    while size > 60 and any(
        draw.textbbox((0, 0), text, font=font(size))[2] > CANVAS[0] - 96 for text in lines
    ):
        size -= 4
    face = font(size)
    for index, (text, color) in enumerate(zip(lines, ("#FFFFFF", "#9FD0FF"))):
        box = draw.textbbox((0, 0), text, font=face)
        width = box[2] - box[0]
        if width > CANVAS[0] - 80:
            raise ValueError(f"見出しが横に収まらない: {text}")
        draw.text(((CANVAS[0] - width) / 2, top + index * round(size * 1.4)), text, font=face, fill=color)


def orb(folder: Path, name: str, size: int) -> Image.Image:
    image = Image.open(folder / f"{name}.png").convert("RGBA").resize((size, size), Image.LANCZOS)
    # 書き出し範囲の四隅に薄い影が残るため、玉と光の部分だけを円で切り抜く。
    mask = Image.new("L", image.size, 0)
    inset = size * 0.08
    ImageDraw.Draw(mask).ellipse((inset, inset, size - inset, size - inset), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(size * 0.02))
    alpha = Image.composite(image.getchannel("A"), Image.new("L", image.size, 0), mask)
    image.putalpha(alpha)
    return image


def hero(orbs: Path, copy: dict, output: Path) -> None:
    canvas = background()
    headline(canvas, copy["hero"])
    # 玉の描画範囲は書き出し画像の中央 75% 程度。重ならないよう中心と大きさを決める。
    layout = [
        ("full-moon-night", 600, (330, 760)),
        ("clear-day", 560, (970, 880)),
        ("sunset", 820, (640, 1400)),
        ("dawn", 520, (300, 1960)),
        ("rain", 520, (990, 2000)),
        ("crystal", 420, (650, 2330)),
    ]
    for name, size, (cx, cy) in layout:
        image = orb(orbs, name, size)
        canvas.alpha_composite(image, (cx - size // 2, cy - size // 2))
    draw = ImageDraw.Draw(canvas)
    face = font(60)
    text = copy["hero_caption"]
    box = draw.textbbox((0, 0), text, font=face)
    if box[2] - box[0] > CANVAS[0] - 96:
        raise ValueError(f"下の一文が横に収まらない: {text}")
    draw.text(((CANVAS[0] - (box[2] - box[0])) / 2, 2620), text, font=face, fill=(255, 255, 255, 200))
    canvas.convert("RGB").save(output, format="PNG", optimize=True)


def phone(canvas: Image.Image, screen: Image.Image) -> None:
    x0, y0, x1, y1 = PHONE_OUTER
    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x0 - 20, y0 - 10, x1 + 20, y1), radius=120, fill=(0, 0, 0, 150))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(36)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x0, y0, x1, y1), radius=112, fill="#030612")
    bezel = 18
    inner_w = x1 - x0 - bezel * 2
    inner_h = round(inner_w * screen.height / screen.width)
    resized = screen.convert("RGB").resize((inner_w, inner_h), Image.LANCZOS)
    mask = Image.new("L", resized.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner_w, inner_h), radius=96, fill=255)
    canvas.paste(resized, (x0 + bezel, y0 + bezel), mask)


def framed(screen: Image.Image, lines: tuple[str, str], output: Path) -> None:
    canvas = background()
    headline(canvas, lines)
    phone(canvas, screen)
    canvas.convert("RGB").crop((0, 0, *CANVAS)).save(output, format="PNG", optimize=True)


def legacy_screen(poster: Path) -> Image.Image:
    x, y = LEGACY_INNER_ORIGIN
    w, h = LEGACY_INNER_SIZE
    return Image.open(poster).convert("RGB").crop((x, y, x + w, y + h))


def contact_sheet(paths: list[Path], output: Path) -> None:
    thumb_w = 240
    thumb_h = round(thumb_w * CANVAS[1] / CANVAS[0])
    gap = 18
    sheet = Image.new("RGB", (gap + len(paths) * (thumb_w + gap), thumb_h + gap * 2), "#071438")
    for index, path in enumerate(paths):
        sheet.paste(Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.LANCZOS),
                    (gap + index * (thumb_w + gap), gap))
    sheet.save(output, format="JPEG", quality=92, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--orbs", type=Path, required=True)
    parser.add_argument("--captures", type=Path, required=True)
    parser.add_argument("--legacy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    for language, copy in COPY.items():
        folder = args.output / language
        folder.mkdir(parents=True, exist_ok=True)
        outputs = [folder / "01-hero-orbs.png"]
        hero(args.orbs, copy, outputs[0])
        for index, key in enumerate(["collection", "home", "month"], start=2):
            path = folder / f"{index:02d}-{key}.png"
            framed(Image.open(args.captures / f"{language}-{key}.png"), copy[key], path)
            outputs.append(path)
        if language == "ja":
            for index, (key, poster) in enumerate([("widget", "02-home-widget.png"),
                                                   ("radar", "04-forecast-radar.png")], start=5):
                path = folder / f"{index:02d}-{key}.png"
                framed(legacy_screen(args.legacy / poster), copy[key], path)
                outputs.append(path)
        contact_sheet(outputs, folder / "preview-contact-sheet.jpg")
        print(language, [p.name for p in outputs])


if __name__ == "__main__":
    main()
