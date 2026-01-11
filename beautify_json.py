"""
Date normalisation and human-friendly formatting utilities for the West
Berkshire Waste Collection e-ink display script.

Responsibility:
This module converts council date strings into relative, readable formats.

Non-responsibility (deliberate):
- It assumes the data is already structured.
- It assumes the data is already correct.
- It simply makes the output easier to read.

Accepts:
- A dictionary of bin collection types and their collection date strings.

Expected input format:
    "Tuesday, 6th JAN"

Output formats:
    "Today"
    "Tomorrow"
    "X Days (Mon 6th)"

Process:
1. For each entry:
   - Ignore non-string values.
   - Detect and preserve already formatted values.
   - Extract weekday, day number, suffix, and month.
   - Build a date using the current year.
   - Adjust for year rollover when needed.
   - Calculate the day difference from today.
2. Replace each value with a relative display string.

Returns:
- Reformatted dictionary on success.
- Original input unchanged if parsing fails.
"""
import re
from datetime import datetime

def beautify(input_data) -> dict:

    original_input = input_data

    try:

        if not isinstance(input_data, dict):
            return original_input

        now = datetime.now()
        current_year = now.year
        output = {}

        for key, value in input_data.items():
            if not isinstance(value, str):
                output[key] = value
                continue

            text = value.strip()

            # Handle Today
            if text.lower() == "today":
                output[key] = "Today"
                continue

            # Match council format
            m = re.search(r"(\w+),\s+(\d{1,2})(st|nd|rd|th)\s+(\w+)", text)
            if not m:
                output[key] = value
                continue

            weekday_full, day, suffix, month_str = m.groups()
            month_norm = month_str.title()

            target_date = None
            for fmt in ("%d %b %Y", "%d %B %Y"):
                try:
                    target_date = datetime.strptime(f"{day} {month_norm} {current_year}", fmt)
                    break
                except ValueError:
                    pass

            if not target_date:
                output[key] = value
                continue

            # Year rollover
            if (target_date.date() - now.date()).days < -30:
                target_date = target_date.replace(year=current_year + 1)

            diff = (target_date.date() - now.date()).days
            weekday_short = weekday_full[:3]

            if diff == 0:
                output[key] = "Today"
            elif diff == 1:
                output[key] = "Tomorrow"
            else:
                output[key] = f"{diff} Days ({weekday_short} {day}{suffix})"

        return output

    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: {e}")
        return original_input
