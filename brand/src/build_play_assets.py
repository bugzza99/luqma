"""Build the Google Play store assets from the brand sources.

    python brand/src/build_play_assets.py

Outputs, all in marketing/play/:

- app_icon_512.png      512x512 RGBA, full-bleed (Play applies its own mask)
- feature-customer.png  1024x500 RGB, no alpha
- feature-merchant.png  1024x500 RGB, no alpha

The Arabic taglines are shaped with HarfBuzz and rendered with FreeType, not with
Pillow's text API: Pillow has no Arabic shaping, and Lemonada has no precomposed
presentation forms, so `draw.text` would draw a row of question marks.
"""
from __future__ import annotations

from pathlib import Path

import freetype
import uharfbuzz as hb
from PIL import Image, ImageDraw

SRC = Path(__file__).resolve().parent
BRAND = SRC.parent
ROOT = BRAND.parent
OUT = ROOT / "marketing" / "play"
FONT = SRC / "Lemonada.ttf"

BURGUNDY = (118, 24, 18)
CREAM = (245, 235, 226)
ORANGE = (214, 127, 43)
ORANGE_LIGHT = (230, 155, 74)


def _load_lockup() -> Image.Image:
    image = Image.open(BRAND / "png" / "logo_lockup_horizontal_2048.png").convert("RGBA")
    bbox = image.getbbox()
    assert bbox is not None
    return image.crop(bbox)


def _recolor_lockup(image: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    """Keep the orange crumb; turn every other inked pixel into `color`."""
    out = image.copy()
    pixels = out.load()
    assert pixels is not None
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            if r > 180 and g > 70 and b < 100:
                continue
            pixels[x, y] = (*color, a)
    return out


def _shaped_text(
    text: str, size: int, color: tuple[int, int, int]
) -> Image.Image:
    """Return a tightly cropped RGBA image of shaped Arabic text."""
    face = freetype.Face(str(FONT))
    face.set_pixel_sizes(0, size)
    hb_face = hb.Face(FONT.read_bytes())
    hb_font = hb.Font(hb_face)
    hb_font.scale = (size * 64, size * 64)

    buf = hb.Buffer()
    buf.add_str(text)
    buf.direction = "rtl"
    buf.script = "Arab"
    buf.language = "ar"
    hb.shape(
        hb_font,
        buf,
        {"kern": True, "liga": True, "mark": True, "mkmk": True},
    )

    # A generous canvas; the result is cropped to the ink afterwards.
    canvas = Image.new("RGBA", (size * max(len(text), 4), size * 3), (0, 0, 0, 0))
    x = size
    baseline = size * 2
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        face.load_glyph(
            info.codepoint, freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_NORMAL
        )
        glyph = face.glyph
        bitmap = glyph.bitmap
        width, height = bitmap.width, bitmap.rows
        if width and height:
            pitch = bitmap.pitch
            raw = bytes(bitmap.buffer)
            if pitch < 0:
                rows = [
                    raw[i * abs(pitch) : (i + 1) * abs(pitch)]
                    for i in range(height)
                ]
                raw = b"".join(rows[::-1])
            alpha = Image.frombytes(
                "L", (width, height), raw[: abs(pitch) * height]
            )
            ink = Image.new("RGBA", (width, height), (*color, 255))
            ink.putalpha(alpha)
            gx = int(round(x + pos.x_offset / 64.0 + glyph.bitmap_left))
            gy = int(round(baseline - glyph.bitmap_top - pos.y_offset / 64.0))
            canvas.alpha_composite(ink, (gx, gy))
        x += pos.x_advance / 64.0

    bbox = canvas.getbbox()
    assert bbox is not None, text
    return canvas.crop(bbox)


def _full_bleed_icon() -> Image.Image:
    """Replace the cream surround with a full burgundy square.

    Play applies its own corner mask, so an icon with baked-in rounded corners and a
    cream surround reads as a small rounded sticker on a cream tile. The mark — the
    plate, its bite, the cut-out ل, and the orange crumb — fits inside a circle of
    radius 195. Paste that disk onto a burgundy square: the maroon edge of the disk
    disappears into the square, and the cream surround never reaches the output.
    """
    image = Image.open(BRAND / "png" / "app_icon_512.png").convert("RGBA")
    width, height = image.size
    canvas = Image.new("RGBA", (width, height), (*BURGUNDY, 255))
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((61, 61, width - 61, height - 61), fill=255)
    canvas.paste(image, (0, 0), mask)
    return canvas


def _decorate(
    background: tuple[int, int, int],
    circles: list[tuple[int, int, int, tuple[int, int, int, int]]],
) -> Image.Image:
    canvas = Image.new("RGBA", (1024, 500), (*background, 255))
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for cx, cy, radius, color in circles:
        draw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius), fill=color
        )
    return Image.alpha_composite(canvas, overlay)


def _feature(
    background: tuple[int, int, int],
    lockup: Image.Image,
    lockup_width: int,
    lockup_top: int,
    tagline: str,
    tagline_size: int,
    tagline_top: int,
    tagline_color: tuple[int, int, int],
    subline: str | None,
    subline_size: int,
    subline_top: int,
    subline_color: tuple[int, int, int],
    circles: list[tuple[int, int, int, tuple[int, int, int, int]]],
    out: Path,
) -> None:
    canvas = _decorate(background, circles)

    ratio = lockup_width / lockup.width
    scaled = lockup.resize(
        (lockup_width, round(lockup.height * ratio)), Image.LANCZOS
    )
    canvas.alpha_composite(scaled, ((1024 - scaled.width) // 2, lockup_top))

    line = _shaped_text(tagline, tagline_size, tagline_color)
    canvas.alpha_composite(line, ((1024 - line.width) // 2, tagline_top))

    if subline:
        sub = _shaped_text(subline, subline_size, subline_color)
        canvas.alpha_composite(sub, ((1024 - sub.width) // 2, subline_top))

    canvas.convert("RGB").save(out, "PNG", optimize=True)
    print(f"wrote {out.relative_to(ROOT)}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    icon = _full_bleed_icon()
    icon.save(OUT / "app_icon_512.png", "PNG", optimize=True)
    print(f"wrote {(OUT / 'app_icon_512.png').relative_to(ROOT)}")

    lockup = _load_lockup()
    _feature(
        background=CREAM,
        lockup=lockup,
        lockup_width=720,
        lockup_top=58,
        tagline="أكل البلد وأكل البيت",
        tagline_size=42,
        tagline_top=338,
        tagline_color=BURGUNDY,
        subline="مطاعم ومطابخ إدكو",
        subline_size=25,
        subline_top=405,
        subline_color=ORANGE,
        circles=[
            (-90, -120, 270, (*ORANGE_LIGHT, 22)),
            (1110, 560, 340, (*BURGUNDY, 10)),
        ],
        out=OUT / "feature-customer.png",
    )

    merchant_lockup = _recolor_lockup(lockup, CREAM)
    _feature(
        background=BURGUNDY,
        lockup=merchant_lockup,
        lockup_width=610,
        lockup_top=54,
        tagline="شريك المطاعم والمطابخ",
        tagline_size=40,
        tagline_top=315,
        tagline_color=CREAM,
        subline="طلبات، منيو، تحصيل — في مكان واحد",
        subline_size=23,
        subline_top=382,
        subline_color=ORANGE_LIGHT,
        circles=[
            (-80, -110, 280, (*CREAM, 18)),
            (1090, 540, 300, (*ORANGE, 34)),
        ],
        out=OUT / "feature-merchant.png",
    )


if __name__ == "__main__":
    main()
