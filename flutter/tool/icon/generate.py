#!/usr/bin/env python3
"""Regenerates the app icons of every platform from the SVG sources here.

Direction B of the design ("balão de pontos"): a dot-matrix bubble on a
graphite plate, a solid bubble below 48 px; Windows uses the glyph without the
plate. Needs Google Chrome (renders the SVG) and Pillow (scales and packs).

    python3 tool/icon/generate.py        # from flutter/
"""

import os
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER = os.path.dirname(os.path.dirname(HERE))
CHROME = os.environ.get(
    "CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
)
MASTER = 1024

# Below this size the dots blur together: the solid bubble is used instead.
SOLID_BELOW = 48


def render(svg, out_dir):
    """Renders `svg` at MASTER×MASTER with a transparent background."""
    png = os.path.join(out_dir, svg.replace(".svg", ".png"))
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--default-background-color=00000000",
            f"--window-size={MASTER},{MASTER}",
            f"--screenshot={png}",
            "file://" + os.path.join(HERE, svg),
        ],
        check=True,
        capture_output=True,
    )
    image = Image.open(png).convert("RGBA")
    if image.size != (MASTER, MASTER):
        sys.exit(f"{svg}: rendered {image.size}, expected {MASTER}x{MASTER}")
    return image


def scaled(image, size):
    return image.resize((size, size), Image.LANCZOS)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        masters = {
            name: render(f"{name}.svg", tmp)
            for name in (
                "macos_dots",
                "macos_solid",
                "linux_dots",
                "windows_dots",
                "windows_solid",
            )
        }

    # macOS: the file name is the pixel size; a 32 pt icon at 2x (64 px) is
    # still a small icon, so 16, 32 and 64 use the solid bubble.
    mac = os.path.join(FLUTTER, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    for size in (16, 32, 64, 128, 256, 512, 1024):
        source = masters["macos_solid" if size <= 64 else "macos_dots"]
        scaled(source, size).save(os.path.join(mac, f"app_icon_{size}.png"))

    # Windows: one .ico with every size Explorer and the taskbar ask for.
    sizes = (16, 20, 24, 32, 40, 48, 64, 128, 256)
    frames = [
        scaled(
            masters["windows_solid" if size < SOLID_BELOW else "windows_dots"],
            size,
        )
        for size in sizes
    ]
    frames[-1].save(
        os.path.join(FLUTTER, "windows/runner/resources/app_icon.ico"),
        format="ICO",
        sizes=[(size, size) for size in sizes],
        append_images=frames[:-1],
    )

    # Linux: round plate, installed next to the executable (window icon).
    scaled(masters["linux_dots"], 512).save(
        os.path.join(FLUTTER, "linux/runner/resources/app_icon.png")
    )


if __name__ == "__main__":
    main()
