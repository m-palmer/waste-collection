"""
Generic message display for the Waveshare 2.13" Touch ePaper (250x122).

Responsibility:
- Accept a plain-text message via command-line arguments and present it on:
  1) The terminal (debugging / SSH use)
  2) A Waveshare 2.13" Touch ePaper display (250x122) when the driver is available

Non-responsibility (deliberate):
- Does not generate or decide the message content.
- It simply draws pixels and prints text.

Driver behaviour:
- Attempts to import the Waveshare driver from ./lib/TP_lib/epd2in13_V4.py.
- If the driver import fails, the script continues in terminal-only mode.

Display behaviour:
- Centres the supplied message on the ePaper panel.
- Uses a full refresh to ensure a clean draw.

Input:
- One or more command-line arguments, joined with spaces to form the message.
- Example: python display_message.py "Connect Me To The Internet Please"

Cleanup:
- Registers an atexit handler to put the display into sleep mode on exit.
"""

from __future__ import annotations

import atexit
import datetime
import os
import sys

from PIL import Image, ImageDraw, ImageFont

# -------------------- Waveshare (TP_lib) --------------------

EPD_AVAILABLE = False
epd2in13_V4 = None

# Attempt to load the Waveshare driver shipped in ./lib.
# If this fails, we fall back to terminal-only output.
try:
    libdir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib")
    if os.path.isdir(libdir):
        sys.path.append(libdir)

    from TP_lib import epd2in13_V4 as _epd2in13_V4  # type: ignore

    epd2in13_V4 = _epd2in13_V4
    EPD_AVAILABLE = True
except Exception as e:
    print(f"[{datetime.datetime.now():%Y-%m-%d %H:%M:%S}] DEBUG: Waveshare import failed: {type(e).__name__}: {e}")

# -------------------- Display constants --------------------

WIDTH = 250
HEIGHT = 122


def _load_font(size: int):
    for path in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    ]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def show_message(message: str) -> None:
    # ---------- Terminal ----------
    print(f"\n{message}\n")

    if not EPD_AVAILABLE or epd2in13_V4 is None:
        return

    # ---------- ePaper ----------
    font = _load_font(14)
    image = Image.new("1", (WIDTH, HEIGHT), 1)
    draw = ImageDraw.Draw(image)

    bbox = draw.textbbox((0, 0), message, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (WIDTH - text_w) // 2
    y = (HEIGHT - text_h) // 2
    draw.text((x, y), message, font=font, fill=0)

    try:
        epd = epd2in13_V4.EPD()
        if hasattr(epd, "FULL_UPDATE"):
            epd.init(epd.FULL_UPDATE)
        else:
            epd.init()
        epd.display(epd.getbuffer(image))
        epd.sleep()
    except Exception as e:
        print(f"[{datetime.datetime.now():%Y-%m-%d %H:%M:%S}] DEBUG: ePaper update failed: {e!r}")


@atexit.register
def _cleanup() -> None:
    try:
        if EPD_AVAILABLE and epd2in13_V4 is not None:
            epd = epd2in13_V4.EPD()
            epd.sleep()
    except Exception:
        pass


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python display_message.py <message>")
        sys.exit(1)
    message = " ".join(sys.argv[1:])
    show_message(message)
