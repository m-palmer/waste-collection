"""
HTML parsing and date formatting utilities for the West Berkshire
Waste Collection e-ink display script.

Responsibility:
This module is responsible for converting messy council HTML into
clean, predictable, human-readable bin collection data.

Non-responsibility (deliberate):
- It does not scrape the website.
- It does not display anything.
- It simply translates chaos into structure.
"""
from bs4 import BeautifulSoup, Tag
from datetime import datetime

import re
from typing import Dict



"""
Converts a raw date string from the council website into the display format
used by the application.

Input format:
    "Tuesday 6 January"

Output format:
    "Tuesday, 6th JAN"

Process:
- Extract weekday, day number, and month name using regex.
- Apply correct ordinal suffix (st, nd, rd, th).
- Shorten month to three letters and convert to uppercase.
- If the input does not match the expected format, return it unchanged.

"""
def format_collection_date(raw: str) -> str:
    m = re.match(
        r"^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s+(\d{1,2})\s+(\w+)$",
        raw,
    )
    if not m:
        return raw

    weekday, day_str, month = m.groups()
    day = int(day_str)

    if 11 <= day <= 13:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(day % 10, "th")

    return f"{weekday}, {day}{suffix} {month[:3].upper()}"



"""
Parses the HTML block returned by the West Berkshire website and extracts
waste collection dates into a structured dictionary.

Process:
1. Load the HTML into BeautifulSoup.
2. Locate all result blocks using the '.rubbish_date_wrap' selector.
3. For each block:
   - Identify the waste type from its CSS class.
   - Extract the associated date text.
   - Convert the date into display format using format_collection_date().
4. Map each result into a dictionary using keys: Rubbish, Recycling, Food.

Returns:
- dict with formatted collection dates on success.
  Example: {"Rubbish": "Tuesday, 6th JAN", "Recycling": "Tuesday, 6th JAN", "Food": "Tuesday, 6th JAN"}
  
- If parsing fails or expected elements are not found, return an error dic
- Example: {"error": "Exception"}
"""
def parse_to_json(html: str) -> dict:
    """
    Parses HTML and returns JSON
    """
    try:
        soup = BeautifulSoup(html, "html.parser")
        result: Dict[str, str] = {}

        mapping = {
            "rubbish_collection_difs_black": "Rubbish",
            "rubbish_collection_difs_green": "Recycling",
            "rubbish_collection_difs_purple": "Food",
        }

        blocks = soup.select(".rubbish_date_wrap")
        if not blocks:
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: No blocks found with selector '.rubbish_date_wrap'.")
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: --- HTML START ---")
            print(html[:5000])
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: --- HTML END ---")
            
            return {"Error": "Invalid HTML"}

        for block in blocks:
            header: Tag | None = block.select_one("[class*=rubbish_collection_difs_]")
            date_el: Tag | None = block.select_one(".rubbish_date_container_left_datetext")

            if not header or not date_el:
                continue

            # Get classes safely as a string for substring searching
            classes = header.get("class", [])
            class_str = " ".join(classes) if isinstance(classes, list) else str(classes)

            for css_class, key in mapping.items():
                if css_class in class_str:
                    raw_date = date_el.get_text(strip=True)
                    result[key] = format_collection_date(raw_date)

        # Ensure we actually found data before returning
        if not result:
            
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] DEBUG: Found containers, but mapping failed.")
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: --- HTML START ---")
            print(html[:5000])
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: --- HTML END ---")
            for i, block in enumerate(blocks):
                # Print the classes found on the header to see why mapping failed
                header = block.select_one("[class*=rubbish_collection_difs_]")
                found_classes = header.get("class") if header else "No Header Found"
                print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Block {i} classes: {found_classes}")
                
            return {"Error": "JSON Mapping"}

        return result

    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: {e}")
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: --- HTML START ---")
        print(html[:5000])
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: --- HTML END ---")
        return {"Error": "Exception"}
