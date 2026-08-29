"""Rasterise the vector brand assets to PNG with headless Chrome.

Only two masters are produced. Every launcher density is generated from them by
flutter_launcher_icons, so there is one place to change if the icon changes.

    python brand/src/export_png.py
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SRC = Path(__file__).resolve().parent
OUT = SRC.parent / "png"

CHROME_CANDIDATES = [
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
    Path(r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"),
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
]

TARGETS = [
    # (svg, output, size, transparent)
    ("app_icon.svg", "app_icon_1024.png", 1024, False),
    ("app_icon.svg", "app_icon_512.png", 512, False),
    ("app_icon_foreground.svg", "app_icon_foreground_1024.png", 1024, True),
    ("logo_mark.svg", "logo_mark_1024.png", 1024, True),
    ("logo_lockup_horizontal.svg", "logo_lockup_horizontal_2048.png", 2048, True),
    ("logo_lockup_stacked.svg", "logo_lockup_stacked_2048.png", 2048, False),
]


def find_browser():
    for p in CHROME_CANDIDATES:
        if p.exists():
            return p
    sys.exit("No Chrome or Edge found — install one, or rasterise the SVGs by hand.")


def page(svg_text, width, height, transparent):
    """Wrap an SVG in a page that is exactly the shot size, with no scrollbars or margin."""
    svg_text = re.sub(r'\swidth="[\d.]+"\sheight="[\d.]+"', "", svg_text, count=1)
    svg_text = svg_text.replace(
        "<svg ", f'<svg width="{width}" height="{height}" ', 1)
    bg = "transparent" if transparent else "#F5EBE2"
    return (
        "<!doctype html><meta charset='utf-8'>"
        f"<style>html,body{{margin:0;padding:0;background:{bg};overflow:hidden}}"
        "svg{display:block}</style>" + svg_text
    )


def main():
    browser = find_browser()
    OUT.mkdir(exist_ok=True)
    print(f"rasterising with {browser.name} -> {OUT}\n")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for name, out_name, size, transparent in TARGETS:
            svg_text = (SRC.parent / name).read_text(encoding="utf-8")
            vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg_text)
            vw, vh = float(vb.group(1)), float(vb.group(2))
            w = size
            h = round(size * vh / vw)

            html = tmp / f"{out_name}.html"
            html.write_text(page(svg_text, w, h, transparent), encoding="utf-8")
            shot = tmp / out_name

            cmd = [
                str(browser), "--headless", "--disable-gpu", "--hide-scrollbars",
                f"--screenshot={shot}", f"--window-size={w},{h}",
                f"--user-data-dir={tmp / 'profile'}",
            ]
            if transparent:
                cmd.append("--default-background-color=00000000")
            cmd.append(html.as_uri())

            subprocess.run(cmd, capture_output=True, timeout=120)
            if not shot.exists():
                sys.exit(f"failed to render {name}")
            shutil.move(str(shot), OUT / out_name)
            print(f"  {out_name:<36} {w}x{h}  {(OUT / out_name).stat().st_size:>9,} bytes")


if __name__ == "__main__":
    main()
