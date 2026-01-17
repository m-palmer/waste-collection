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

------------------------------------------------------------------------

## Known Failure Modes

-   Council website layout changes
-   No internet
-   Python environment issues
-   The Raspberry Pi running out of memory

------------------------------------------------------------------------

## How It Works

1.  Scrapes the council website using Playwright
2.  Parses and reformats the collection dates
3.  Outputs to terminal and e-ink display
4.  Sleeps until the next run

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

Important: You must run the installer using sudo from a normal user account (not as root directly).

When the installer starts, it will display a summary of all changes it will make and
will require you to enter "Yes" before any changes are applied.If anything else is entered, the 
installer exits without modifying the system.

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
-   Sets the system hostname to waste-collection
-   Updates /etc/hosts safely
-   Installs system and Python dependencies
-   Installs Playwright and Chromium (Chromium is installed for the target non-root user)
-   Enables cron and installs scheduled jobs for run.sh
-   Disables optional background services to reduce resource usage
-   Removes unused default home folders only if they are empty
-   Logs all output to waste-collection-install.log (in the same folder as install.sh)
  
It does not clone the repository for you. You are expected to place the project in your home directory first.

After installation, the script will run automatically via cron:
-   On boot (@reboot)
-   Multiple times per day: 00:01 / 06:00 / 09:00 / 12:00 / 15:00 / 18:00

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

