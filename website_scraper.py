"""
Website scraping utilities for the West Berkshire Waste Collection e-ink 
display script.

Responsibility:
Uses Playwright to automate Chromium and retrieve the raw HTML block
containing the waste collection dates from the West Berkshire Council website.

Non-responsibility (deliberate):
- It does not interpret the data.
- It does not format the data.
- It simply fetches it.

Process:
1. Launch a headless Chromium browser.
2. Navigate to the West Berkshire waste collection lookup page.
3. Enter the supplied postcode into the postcode field.
4. Submit the postcode and wait for the address dropdown to populate.
5. Select the supplied ADDRESS_VALUE (this is the <option value>, not the house number).
6. Wait for the results section to load.
7. Extract and return the inner HTML of the results container.

Returns:
- str : HTML content on success.
- dict: {"error": "..."} if any step fails or times out.

Example HTML:
<div class="rubbish_date_wrap">     <div class="rubbish_date_container">         <div class="rubbish_date_container_left rubbish_collection_difs_black" style="">             Your next rubbish collection day is             <br>             <div class="rubbish_date_container_left_datetext">Friday 23 January</div>         </div>         <div class="rubbish_date_container_right rubbish_date_container_right_black">             Collection calendar <b>5</b>             <div class="rubbish_date_schedule_desc" style="padding: 15px 25px;">                 <span style="font-size: 22px!important; font-weight: normal;"> Friday every 3 weeks </span>                 <a href="https://www.westberks.gov.uk/media/64437/3-weekly-week-5-calendar/pdf/16320__Calendar_Schedule_5_AW_LR.pdf" target="_blank" title="Download 3 week collection calendar 5" class="media-link media-link--pdf">
          <span class="media-link__text">Collection calendar 5</span>
          <span class="media-link__bracket"> (</span>
          <span class="media-link__type">PDF</span>)</a>             </div>         </div>     </div>
</div>
<div class="rubbish_date_wrap">     <div class="rubbish_date_container">         <div class="rubbish_date_container_left rubbish_collection_difs_green" style="">             Your next recycling collection day is             <br>             <div class="rubbish_date_container_left_datetext">Saturday 17 January</div>         </div>         <div class="rubbish_date_container_right rubbish_date_container_right_green">             Collection calendar <b>5</b>             <br>             <div class="rubbish_date_schedule_desc">                 Friday every other week             </div>         </div>     </div>
</div>
<div class="rubbish_date_wrap">     <div class="rubbish_date_container">         <div class="rubbish_date_container_left rubbish_collection_difs_purple" style="">             Your next weekly food waste collection day is             <br>             <div class="rubbish_date_container_left_datetext">Monday 12 January</div>         </div>         <div class="rubbish_date_container_right rubbish_date_container_right_purple">             Collection calendar <b>5</b>             <br>             <div class="rubbish_date_schedule_desc">                 Friday every week             </div>         </div>     </div>
</div>

"""
from __future__ import annotations

from datetime import datetime
from typing import Union, Dict
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError

ResultType = Union[str, Dict[str, str]]

def scrape_url_get_html(url: str, postcode: str, address_value: str, ) -> ResultType:
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=[
                "--disable-gpu",
                "--disable-dev-shm-usage",
                "--no-sandbox",
                "--disable-software-rasterizer",
            ])
            context = browser.new_context()
            page = context.new_page()

            page.goto(url, wait_until="domcontentloaded", timeout=60000)

            page.locator("#FINDYOURBINDAYS3WEEKLY_ADDRESSLOOKUPPOSTCODE").fill(postcode)
            page.locator("#FINDYOURBINDAYS3WEEKLY_ADDRESSLOOKUPSEARCH").click()

            dropdown = page.locator("#FINDYOURBINDAYS3WEEKLY_ADDRESSLOOKUPADDRESS")
            handle = dropdown.element_handle()

            page.wait_for_function("el => el.options.length > 1", arg=handle, timeout=20000)

            page.select_option("#FINDYOURBINDAYS3WEEKLY_ADDRESSLOOKUPADDRESS",value=address_value,)

            result_selector = "#FINDYOURBINDAYS3WEEKLY_RUBBISHRECYCLEFOODDATE"
            page.wait_for_selector(f"{result_selector} .rubbish_date_wrap", timeout=20000)

            html = page.inner_html(result_selector)

            context.close()
            browser.close()

            return html

    except PlaywrightTimeoutError as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: {e}")
        return {"Error": "Browser"}

    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Debug: {e}")
        return {"Error": "Unknown"}

