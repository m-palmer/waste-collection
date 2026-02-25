# Waste Collection E Ink Display - West Berkshire

A Raspberry Pi project that answers a weekly question:

    Which bin do I put out tonight?

This script scrapes West Berkshire Council's bin collection website,
converts the rotating and holiday-adjusting schedule into human-readable
output, and displays it on a Waveshare 2.13" e-ink screen.

It is designed to run unattended on a Raspberry Pi Zero 2 with Waveshare
2.13" Touch ePaper HAT.

------------------------------------------------------------------------

## Features

-   Scrapes official council data
-   Handles rotating and holiday schedules
-   Converts dates into clear, friendly output (e.g. "Tomorrow", "5 Days (Tue 6th)")
-   Displays on 250x122 e-ink screen with partial/full refresh management
-   Terminal fallback when display is unavailable
-   Timestamped footer with version, IP address, and postcode
-   WiFi provisioning via comitup (headless setup from a phone)
-   Network connectivity detection with automatic hotspot fallback
-   Designed for cron automation
-   Fails gracefully (most of the time)

------------------------------------------------------------------------

## Target Hardware

-   Raspberry Pi Zero 2
-   Waveshare 2.13" Touch ePaper HAT (V4, TP_lib / epd2in13_V4)

------------------------------------------------------------------------

## What This Is Not

-   A guaranteed source of truth
-   A replacement for common sense

------------------------------------------------------------------------

## Known Failure Modes

-   Council website layout changes
-   No internet (falls back to comitup hotspot for WiFi provisioning)
-   Python environment issues
-   The Raspberry Pi running out of memory

------------------------------------------------------------------------

## How It Works

1.  run.sh is called by cron (on boot and multiple times per day)
2.  Checks for network connectivity (waits up to 60 seconds)
3.  If no network: starts a comitup WiFi provisioning hotspot
4.  If network ready: runs main.py
5.  main.py scrapes the council website using Playwright
6.  Parses and reformats the collection dates
7.  Outputs to terminal and e-ink display
8.  Sleeps until the next cron run

------------------------------------------------------------------------

## WiFi Provisioning (comitup)

On first boot (or if WiFi is unavailable), the device creates a temporary
WiFi hotspot for configuration:

1.  The e-ink screen shows: `SSID: waste-collection-setup`
2.  Connect to that network from a phone or laptop
3.  A captive portal page appears automatically
4.  Select your home WiFi network and enter the password
5.  The device reboots and connects to your network
6.  From then on it runs automatically

This means the device can be set up without a keyboard, monitor, or SSH
session. Just plug it in and connect from your phone.

------------------------------------------------------------------------

## Typical Output

    Waste Collection

    Rubbish:   13 Days (Fri 23rd)
    Recycling: 7 Days (Sat 17th)
    Food:      2 Days (Mon 12th)

    1-1   192.168.1.42   RG7 3HX   10 Jan   10:00

------------------------------------------------------------------------

## Installation

Clone or copy this repository into your home directory so it lives at:

    /home/<your-user>/waste-collection

Then run:

    cd waste-collection
    chmod +x install.sh
    sudo ./install.sh

Important: You must run the installer using sudo from a normal user account (not as root directly).

When the installer starts, it will display a summary of all changes it will make and
will require you to enter "Yes" before any changes are applied. If anything else is entered, the
installer exits without modifying the system.

Before the first run, open main.py and set your postcode and address:

    nano main.py

Look for variables such as POSTCODE and ADDRESS_VALUE.

After installation, reboot:

    sudo reboot

------------------------------------------------------------------------

## What the Installer Does

The install.sh script configures the system so the display can run unattended:

-   Creates a temporary 512MB swap file (removed after install completes)
-   Enables SPI and I2C for the e-ink display
-   Forces console-only boot (no desktop GUI)
-   Sets the system hostname to waste-collection
-   Updates /etc/hosts safely
-   Installs system and Python dependencies
-   Installs Playwright and Chromium (custom wget-based downloader with retry)
-   Installs and configures comitup for WiFi provisioning (disabled by default)
-   Grants passwordless sudo for reboot and comitup start (required by run.sh)
-   Enables cron and installs scheduled jobs for run.sh
-   Normalises run.sh and comitup_reboot.sh (line endings and permissions)
-   Disables optional background services to reduce resource usage
-   Removes unused default home folders only if they are empty
-   Logs all output to waste-collection-install.log (in the same folder as install.sh)

It does not clone the repository for you. You are expected to place the project in your home directory first.

After installation, the script will run automatically via cron:

-   On boot (@reboot)
-   Multiple times per day: 00:01 / 06:00 / 09:00 / 12:00 / 15:00 / 18:00

This keeps the display up to date without manual intervention or human supervision.

------------------------------------------------------------------------

## File Overview

| File | Purpose |
|------|---------|
| main.py | Orchestrates scrape, parse, beautify, display |
| website_scraper.py | Fetches HTML from council website via Playwright |
| html_to_json.py | Parses council HTML into structured data |
| beautify_json.py | Converts dates to relative format (Today, Tomorrow, X Days) |
| output.py | Renders result to terminal and e-ink display |
| print_text_to_screen.py | Displays a single message on the e-ink (used by run.sh) |
| run.sh | Runtime wrapper called by cron (network check, comitup fallback) |
| install.sh | System installer and configurator |
| comitup_reboot.sh | Callback script triggered by comitup on WiFi connection |
| user_quick_start_guide.txt | End-user quick start instructions |
| lib/TP_lib/ | Waveshare e-ink display drivers |

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

When run directly on the Pi's local console, the installer is typically stable.

In short: if SSH freezes, just run it again.

------------------------------------------------------------------------

## Disclaimer

This software provides information only.
It does not guarantee bin correctness, council compliance, or domestic harmony.
