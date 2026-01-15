# Waste Collection E Ink Display - West Berkshire

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

## Installation

Clone or copy this repository into your home directory so it lives at:

/home/<your-user>/waste-collection

Then run:

cd waste-collection
sudo ./install.sh

Important:
You must run the installer using sudo from a normal user account (not as root directly).
This ensures cron jobs, Playwright, and browser files are installed for the correct user.

After installation, reboot:

sudo reboot

Before the first run, open main.py and set your postcode and address:

nano main.py

Look for variables such as POSTCODE and ADDRESS_VALUE.

------------------------------------------------------------------------

## What the Installer Does

The install.sh script configures the system so the display can run unattended:
-   Enables SPI and I2C for the e-ink display
-   Forces console-only boot (no desktop GUI)
-   Installs system and Python dependencies
-   Installs Playwright and Chromium correctly for the target user
-   Ensures cron is enabled and running
-   Installs scheduled cron jobs and a boot job for run.sh
-   Fixes line endings and permissions on run.sh
-   Ensures files are owned by the correct user
-   Logs all output to /var/log/waste-collection-install.log

It does not clone the repository for you.
You are expected to place the project in your home directory first.

After installation, the script will run automatically:
-   On boot 
-   Multiple times per day via cron: 00:01 / 06:00 / 09:00 / 12:00 / 15:00 / 18:00

This keeps the display up to date without manual intervention or human supervision.

------------------------------------------------------------------------

## Installer Warning

When running install.sh over an SSH session, the connection may occasionally hang during
the Playwright Chromium installation step.

This is a known behaviour on some Raspberry Pi OS builds and is not usually a failure of
the script itself.

If the SSH session freezes:

-   Close the SSH connection
-   Reconnect to the Pi
-   Re-run: sudo ./install.sh

The installer is safe to run multiple times.

When run directly on the Pi’s local console, the installer is typically stable.

In short: if SSH freezes, just run it again.

------------------------------------------------------------------------

## Disclaimer

This software provides information only.
It does not guarantee bin correctness, council compliance, or domestic harmony.

