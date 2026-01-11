# Waste Collection E Ink Display -- West Berkshire

A Raspberry Pi project that answers one daily question:

Which bin do I put out tonight?

This script scrapes West Berkshire Council's bin collection website,
converts the rotating and holiday-adjusted schedule into human-readable
output, and displays it on a Waveshare 2.13" e-ink screen.

It is designed to run unattended on a Raspberry Pi Zero 2.

------------------------------------------------------------------------

## Features

-   Scrapes official council data
-   Handles rotating and holiday schedules
-   Converts dates into clear, friendly output
-   Displays on 250×122 e-ink screen
-   Terminal fallback when display is unavailable
-   Timestamped footer
-   Designed for cron or systemd automation
-   Fails gracefully (most of the time)

------------------------------------------------------------------------

## Target Hardware

-   Raspberry Pi Zero 2
-   Waveshare 2.13" Touch ePaper HAT (V4, TP_lib / epd2in13_V4)

------------------------------------------------------------------------

## What This Is Not

-   A guaranteed source of truth
-   A replacement for common sense
-   A legally binding waste authority

If it says the wrong bin, the blame remains entirely yours.

------------------------------------------------------------------------

## Known Failure Modes

-   Council website layout changes
-   No internet
-   Python environment issues
-   Display driver issues
-   Bugs escaping into production like startled spiders

------------------------------------------------------------------------

## How It Works

1.  Scrapes the council website using Playwright
2.  Parses and reformats the collection dates
3.  Outputs to terminal and e-ink display
4.  Sleeps peacefully until the next run

------------------------------------------------------------------------

## Typical Output

    Waste Collection

    Rubbish:   13 Days (Fri 23rd)
    Recycling: 7 Days (Sat 17th)
    Food:      2 Days (Mon 12th)

    Updated: 10 Jan 2026 10:00

------------------------------------------------------------------------

## Automation

Designed to run:

-   On boot
-   On a schedule via cron
-   Or via systemd service

------------------------------------------------------------------------

## Disclaimer

This software provides information only.
It does not guarantee bin correctness, council compliance, or domestic
harmony.

