"""Generate Luqma's logo assets.

Two things are baked here rather than left to runtime:

1. The wordmark is shaped once with HarfBuzz and written out as outlines, so the lockup is
   identical everywhere and the app ships no display font.
2. The mark is boolean-flattened into a single filled path. A mask-based mark collides on
   its mask id when two copies land on one page, and Android vector drawables have no mask
   at all; one path renders the same in SVG, in a drawable, and in print.

    python brand/src/build_logo.py
"""
from pathlib import Path

import uharfbuzz as hb
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

import flatten as F

SRC = Path(__file__).resolve().parent
OUT = SRC.parent
FONT = SRC / "Lemonada.ttf"
WORD = "لُقْمَة"
WEIGHT = 700

# Brand tokens — docs/14-design-system.md
BURGUNDY = "#761812"
CREAM = "#F5EBE2"
ORANGE = "#D67F2B"
ORANGE_LIGHT = "#E69B4A"

# Mark geometry on a 120-unit grid.
# The bite sits upper-LEFT because the ل's tall stem rises on the right; a bite there clips
# the stem and the letter stops reading. A smaller right-hand bite and a bottom-left bite
# were both tried and weaken the bite instead. This is the only placement where the letter
# and the bite both stay unambiguous at 32px.
DISC = (60, 60, 46)
BITE = (23, 24, 22)
CRUMB = (12, 49, 4.4)
LAM_HEIGHT = 54.0
LAM_NUDGE = (2.0, 3.0)      # away from the bite, so the bowl keeps its counter


# --------------------------------------------------------------------------- text
def _shape(text):
    face = hb.Face(FONT.read_bytes())
    font = hb.Font(face)
    font.scale = (1000, 1000)
    font.set_variations({"wght": WEIGHT})
    buf = hb.Buffer()
    buf.add_str(text)
    buf.direction = "rtl"
    buf.script = "Arab"
    buf.language = "ar"
    hb.shape(font, buf, {"kern": True, "liga": True, "mark": True, "mkmk": True})
    return buf.glyph_infos, buf.glyph_positions


def outlines(text):
    """Shaped text as an SVG path, y-down, ink starting at (0, 0). Returns (d, w, h)."""
    static = instancer.instantiateVariableFont(TTFont(FONT), {"wght": WEIGHT})
    glyphs, order = static.getGlyphSet(), static.getGlyphOrder()
    infos, positions = _shape(text)

    placed, cursor = [], 0
    for info, pos in zip(infos, positions):
        placed.append((order[info.codepoint], cursor + pos.x_offset, pos.y_offset))
        cursor += pos.x_advance

    box = BoundsPen(glyphs)
    for name, dx, dy in placed:
        glyphs[name].draw(TransformPen(box, (1, 0, 0, 1, dx, dy)))
    x_min, y_min, x_max, y_max = box.bounds

    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}")
    flip = TransformPen(pen, (1, 0, 0, -1, -x_min, y_max))
    for name, dx, dy in placed:
        glyphs[name].draw(TransformPen(flip, (1, 0, 0, 1, dx, dy)))
    return pen.getCommands(), x_max - x_min, y_max - y_min


# --------------------------------------------------------------------------- mark
def mark_path(lam_d, lam_w, lam_h):
    """disc minus bite minus ل, as one path on the 120 grid."""
    scale = LAM_HEIGHT / lam_h
    lam = F.from_d(lam_d, (
        scale, 0, 0, scale,
        DISC[0] - lam_w * scale / 2 + LAM_NUDGE[0],
        DISC[1] - LAM_HEIGHT / 2 + LAM_NUDGE[1],
    ))
    return F.to_d(F.subtract(F.circle(*DISC), [F.circle(*BITE), lam]))


MARK_D = ""  # filled by main()


def mark(fill, crumb=None, size=120.0, x=0.0, y=0.0):
    body = f'<path d="{MARK_D}" fill="{fill}"/>'
    if crumb:
        body += f'<circle cx="{CRUMB[0]}" cy="{CRUMB[1]}" r="{CRUMB[2]}" fill="{crumb}"/>'
    if (size, x, y) == (120.0, 0.0, 0.0):
        return body
    return f'<g transform="translate({x:.1f} {y:.1f}) scale({size / 120:.5f})">{body}</g>'


def svg(w, h, body, title):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.0f} {h:.0f}" '
        f'width="{w:.0f}" height="{h:.0f}" role="img" aria-label="{title}">'
        f'<title>{title}</title>{body}</svg>\n'
    )


def write(name, content):
    (OUT / name).write_text(content, encoding="utf-8")
    print(f"  {name:<32} {len(content):>7,} bytes")


def main():
    global MARK_D
    lam_d, lam_w, lam_h = outlines("ل")
    MARK_D = mark_path(lam_d, lam_w, lam_h)
    word_d, ww, wh = outlines(WORD)
    print(f"  lam {lam_w:.0f}x{lam_h:.0f} · wordmark {ww:.0f}x{wh:.0f} · "
          f"mark path {len(MARK_D)} chars\n")

    # wordmark ---------------------------------------------------------------
    write("logo_wordmark.svg", svg(ww, wh, f'<path d="{word_d}" fill="{BURGUNDY}"/>', "لقمة"))

    # mark -------------------------------------------------------------------
    write("logo_mark.svg", svg(120, 120, mark(BURGUNDY, ORANGE), "علامة لقمة"))
    write("logo_mark_small.svg", svg(120, 120, mark(BURGUNDY), "علامة لقمة"))
    write("logo_mark_mono.svg", svg(120, 120, mark("currentColor"), "علامة لقمة"))

    # app icon: the same mark, inverted, inset on a burgundy square -----------
    inset = 37 / 46
    icon = (
        f'<rect width="120" height="120" rx="27" fill="{BURGUNDY}"/>'
        f'<g transform="translate(58 61) scale({inset:.5f}) translate(-60 -60)">'
        f'<path d="{MARK_D}" fill="{CREAM}"/>'
        f'<circle cx="{CRUMB[0]}" cy="{CRUMB[1]}" r="{CRUMB[2]}" fill="{ORANGE_LIGHT}"/></g>'
    )
    write("app_icon.svg", svg(120, 120, icon, "أيقونة تطبيق لقمة"))

    # adaptive icon foreground on the 108dp grid; the 66dp safe zone holds the mark
    fg_scale = 62 / 120
    off = (108 - 120 * fg_scale) / 2
    fg = (
        f'<g transform="translate({off:.1f} {off:.1f}) scale({fg_scale:.5f})">'
        f'<path d="{MARK_D}" fill="{CREAM}"/>'
        f'<circle cx="{CRUMB[0]}" cy="{CRUMB[1]}" r="{CRUMB[2]}" fill="{ORANGE_LIGHT}"/></g>'
    )
    write("app_icon_foreground.svg", svg(108, 108, fg, "أيقونة لقمة — الطبقة الأمامية"))

    # lockups ----------------------------------------------------------------
    def lockup(mark_h, fill, crumb, wm_ratio, gap_ratio):
        s = (mark_h * wm_ratio) / wh
        w, h = ww * s, wh * s
        gap = mark_h * gap_ratio
        body = (
            f'<g transform="translate(0 {(mark_h - h) / 2:.1f}) scale({s:.5f})">'
            f'<path d="{word_d}" fill="{fill}"/></g>'
            + mark(fill, crumb, size=mark_h, x=w + gap, y=0)
        )
        return svg(w + gap + mark_h, mark_h, body, "لقمة")

    write("logo_lockup_horizontal.svg", lockup(100, BURGUNDY, ORANGE, 0.62, 1 / 3))
    write("logo_lockup_appbar.svg", lockup(21, CREAM, None, 0.72, 1 / 3))

    # stacked lockup on the brand ground — the splash form -------------------
    ms = 104.0
    s = (ms * 0.60) / wh
    w, h = ww * s, wh * s
    pad, gap = 44.0, 26.0
    box_w, box_h = max(w, ms) + pad * 2, ms + gap + h + pad * 2
    body = (
        f'<rect width="{box_w:.0f}" height="{box_h:.0f}" fill="{BURGUNDY}"/>'
        + mark(CREAM, size=ms, x=(box_w - ms) / 2, y=pad)
        + f'<g transform="translate({(box_w - w) / 2:.1f} {pad + ms + gap:.1f}) '
          f'scale({s:.5f})"><path d="{word_d}" fill="{CREAM}"/></g>'
    )
    write("logo_lockup_stacked.svg", svg(box_w, box_h, body, "لقمة"))


if __name__ == "__main__":
    print(f"building brand assets -> {OUT}\n")
    main()
