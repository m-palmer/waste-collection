"""
Display/output layer for the West Berkshire Waste Collection e-ink project.

Responsibility:
- Take the final, human-friendly result (already scraped, parsed, and formatted)
  and present it clearly on:
  1) The terminal (debugging / SSH use)
  2) A Waveshare 2.13" Touch ePaper display (250x122) when the driver is available

Non-responsibility (deliberate):
- Does not scrape the website.
- Does not parse HTML.
- Does not interpret schedules.
- It simply draws pixels and prints text.

Driver behaviour:
- Attempts to import the Waveshare driver from ./lib/TP_lib/epd2in13_V4.py.
- If the driver import fails, the script continues in terminal-only mode.

Display behaviour:
- Renders a fixed layout: header, three rows (Rubbish/Recycling/Food), and a footer.
- Truncates long values with "..." to preserve alignment.

Refresh behaviour:
- Uses partial refresh most of the time.
- Forces periodic full refresh to reduce ghosting.
- Rate-limits updates to protect the panel.

Input:
- result: dict of collection values OR error dict.
- postcode/version/updated: used to build a footer for visibility/debugging.

Cleanup:
- Registers an atexit handler to put the display into sleep mode on exit.
"""

from __future__ import annotations

import atexit
import datetime
import os
import socket
import sys
import time
from typing import Dict, Optional, Union

from PIL import Image, ImageDraw, ImageFont

ResultType = Union[Dict[str, str], str]

# -------------------- Waveshare (TP_lib) --------------------

# Attempt to load the Waveshare driver shipped in ./lib.
# If this fails, we fall back to terminal-only output.
EPD_AVAILABLE = False
epd2in13_V4 = None

try:
    libdir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib")
    if os.path.isdir(libdir):
        sys.path.append(libdir)

    from TP_lib import epd2in13_V4 as _epd2in13_V4  # type: ignore

    epd2in13_V4 = _epd2in13_V4
    EPD_AVAILABLE = True
except Exception as e:
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] DEBUG: Waveshare import failed: {type(e).__name__}: {e}")
    EPD_AVAILABLE = False
    epd2in13_V4 = None

# -------------------- Display constants --------------------

WIDTH = 250
HEIGHT = 122

LEFT_MARGIN = 6
RIGHT_MARGIN = 6
TOP_MARGIN = 4
BOTTOM_MARGIN = 4

HEADER_SIZE = 17
ROW_SIZE = 14
FOOTER_SIZE = 10

ROW_GAP = 10
HEADER_GAP = 12

LABEL_COL_X = LEFT_MARGIN
DATE_COL_X = 92  # fixed alignment for values

# ePaper refresh control
FULL_REFRESH_INTERVAL_SECONDS = 30 * 60
PARTIAL_REFRESH_LIMIT = 50
MIN_REFRESH_SECONDS = 2

_last_full_refresh: Optional[float] = None
_partial_count: int = 0
_last_refresh_time: Optional[float] = None


def _ttf(path: str, size: int) -> Optional[ImageFont.FreeTypeFont]:
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return None


def _load_fonts() -> tuple[ImageFont.ImageFont, ImageFont.ImageFont, ImageFont.ImageFont]:
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            header = _ttf(p, HEADER_SIZE)
            row = _ttf(p, ROW_SIZE)
            footer = _ttf(p, FOOTER_SIZE)
            if header and row and footer:
                return header, row, footer

    f = ImageFont.load_default()
    return f, f, f


HEADER_FONT, ROW_FONT, FOOTER_FONT = _load_fonts()


def _get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "0.0.0.0"


def _truncate(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_width: int) -> str:
    ellipsis = "..."
    if draw.textlength(text, font=font) <= max_width:
        return text

    out = ""
    for ch in text:
        if draw.textlength(out + ch + ellipsis, font=font) > max_width:
            break
        out += ch
    return out + ellipsis


def show_result(
    result: ResultType,
    postcode: str,
    version: str,
    updated: Optional[datetime.datetime] = None,
) -> None:
    """
    Displays the current waste collection status to terminal and ePaper.
    """

    global _last_full_refresh, _partial_count, _last_refresh_time

    # Rate limit refreshes
    now = time.time()
    if _last_refresh_time and (now - _last_refresh_time) < MIN_REFRESH_SECONDS:
        return
    _last_refresh_time = now

    if updated is None:
        updated = datetime.datetime.now()

    pc = postcode.strip().upper() if postcode else "N/A"
    ip = _get_local_ip()
    updated_str = updated.strftime("%d %b     %H:%M")
    footer = f"{version}     {ip}     {pc}     {updated_str}"

    # ---------- Terminal output ----------

    print("\nWaste Collection\n")

    is_error = False
    error_text = ""

    if isinstance(result, dict) and ("Error" in result or "error" in result):
        is_error = True
        error_text = result.get("Error") or result.get("error") or "Unknown error"

    if isinstance(result, dict) and not is_error:

        def _get(k1: str, k2: str) -> str:
            return str(result.get(k1) or result.get(k2) or "-")

        print(f"Rubbish:   {_get('Rubbish', 'rubbish')}")
        print(f"Recycling: {_get('Recycling', 'recycling')}")
        print(f"Food:      {_get('Food', 'food')}")

    elif is_error:
        print(f"Error: {error_text}")

    else:
        print("Error: Failed to fetch/parse")

    print("\n" + footer + "\n")

    if not EPD_AVAILABLE or epd2in13_V4 is None:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] DEBUG: EPD_AVAILABLE={EPD_AVAILABLE}, epd2in13_V4 is None? {epd2in13_V4 is None}")
        return

    # ---------- ePaper rendering ----------

    image = Image.new("1", (WIDTH, HEIGHT), 1)
    draw = ImageDraw.Draw(image)

    # Header
    y = TOP_MARGIN
    draw.text((LEFT_MARGIN, y), "Waste Collection", font=HEADER_FONT, fill=0)
    y += HEADER_SIZE + HEADER_GAP

    # Body rows
    if not is_error and isinstance(result, dict):
        rows = [
            ("Rubbish:", result.get("Rubbish") or result.get("rubbish") or "-"),
            ("Recycling:", result.get("Recycling") or result.get("recycling") or "-"),
            ("Food:", result.get("Food") or result.get("food") or "-"),
        ]
    else:
        rows = [
            ("Error:", error_text or "No data"),
            ("", ""),
            ("", ""),
        ]

    max_value_width = WIDTH - RIGHT_MARGIN - DATE_COL_X
    for label, value in rows:
        draw.text((LABEL_COL_X, y), label, font=ROW_FONT, fill=0)
        safe_value = _truncate(draw, str(value), ROW_FONT, max_value_width)
        draw.text((DATE_COL_X, y), safe_value, font=ROW_FONT, fill=0)
        y += ROW_SIZE + ROW_GAP

    # Footer
    max_footer_width = WIDTH - LEFT_MARGIN - RIGHT_MARGIN
    footer_draw = _truncate(draw, footer, FOOTER_FONT, max_footer_width)
    footer_y = HEIGHT - BOTTOM_MARGIN - FOOTER_SIZE - 1
    draw.text((LEFT_MARGIN, footer_y), footer_draw, font=FOOTER_FONT, fill=0)

    # ---------- Push to panel ----------

    try:
        epd = epd2in13_V4.EPD()

        do_full = (
            _last_full_refresh is None
            or (now - _last_full_refresh) >= FULL_REFRESH_INTERVAL_SECONDS
            or _partial_count >= PARTIAL_REFRESH_LIMIT
        )

        if do_full:
            if hasattr(epd, "FULL_UPDATE"):
                epd.init(epd.FULL_UPDATE)
            else:
                epd.init()
            epd.display(epd.getbuffer(image))
            _last_full_refresh = now
            _partial_count = 0
        else:
            if hasattr(epd, "PART_UPDATE"):
                epd.init(epd.PART_UPDATE)
            elif hasattr(epd, "PARTIAL_UPDATE"):
                epd.init(epd.PARTIAL_UPDATE)
            else:
                epd.init()

            if hasattr(epd, "displayPartial"):
                epd.displayPartial(epd.getbuffer(image))
            else:
                epd.display(epd.getbuffer(image))
            _partial_count += 1

        epd.sleep()

    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] DEBUG: ePaper update failed:", repr(e))


@atexit.register
def _cleanup() -> None:
    try:
        if EPD_AVAILABLE and epd2in13_V4 is not None:
            epd = epd2in13_V4.EPD()
            epd.sleep()
    except Exception:
        pass
