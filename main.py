"""
-----------------------------------------------
Waste Collection E Ink Display – West Berkshire
-----------------------------------------------

Why this exists:
Because West Berkshire’s bin collection schedule is a rotating, postcode-based,
holiday-adjusted puzzle designed to test human patience.

Purpose:
To answer one nightly question with confidence:
"Do I put a bin out tonight, and if so, which one?"

What it does:
This program scrapes the official council website, extracts the current
collection dates, converts them into something a human can understand,
and displays the result on an e-ink screen.

Target platform:
- Raspberry Pi Zero 2
- Waveshare 2.13" Touch ePaper HAT (250x122) using TP_lib driver (epd2in13_V4)

Reality check:
- You still have to look at the screen.
- You can still put the wrong bin out.
- This script my go wrong.
- If that happens, the software accepts no responsibility.

Known failure modes:
- The council redesigns their website.
- No internet.
- A bug escapes into the wild.

When it works, it saves time.
When it doesn’t, it builds character.
"""
from __future__ import annotations

from datetime import datetime
from typing import Dict, Union

from website_scraper import scrape_url_get_html
from html_to_json import parse_to_json
from beautify_json import beautify
from output import show_result

VERSION = "1-0"
URL = "https://www.westberks.gov.uk/article/35776/Find-your-next-collection-day"
POSTCODE = "RG7 "
ADDRESS_VALUE = ""  # Not the house number: it's the <option value="...">

ResultType = Union[str, Dict[str, str]]

def main() -> None:
    
    updated = datetime.now()

    # 1) Scrape URL
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] [1/4] Scraping URL")
    html_or_error: ResultType = scrape_url_get_html(
        url=URL,
        postcode=POSTCODE,
        address_value=ADDRESS_VALUE,
    )

    # 2) If scraper returned an error, display it, and stop
    if isinstance(html_or_error, dict):
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] [2/4] Scraping Failed!")
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: URL = {URL}")
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: POSTCODE = {POSTCODE}")
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: ADDRESS_VALUE = {ADDRESS_VALUE}")
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] [4/4] Updating E Ink Display")
        show_result(result=html_or_error, postcode=POSTCODE, version=VERSION, updated=updated, )
        return

    # 3) Parse HTML into JSON
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] [2/4] Parsing HTML to JSON")
    parsed = parse_to_json(html_or_error)

    # 4) Beautify JSON
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] [2/4] Beautifying JSON")
    parsed = beautify(parsed)

    # 5) Display result, and stop
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] [2/4] Updating E Ink Display")
    show_result(result=parsed, postcode=POSTCODE, version=VERSION, updated=updated, )


if __name__ == "__main__":
    main()
