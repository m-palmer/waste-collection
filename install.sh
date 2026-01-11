#!/bin/bash


if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo!"
  echo "  → sudo ./install.sh"
  exit 1
fi


echo "[1/3] Enabling hardware interfaces..."
echo " → Enabling SPI (required for e-ink display)"
raspi-config nonint do_spi 0
echo " → Enabling I2C (safe to enable, commonly used)"
raspi-config nonint do_i2c 0


echo "[2/3] Configuring boot behaviour..."
echo " → Disabling desktop GUI"
echo " → Setting console-only boot"
raspi-config nonint do_boot_behaviour B1å


echo "[3/3] Configuring Python..."
echo " → Updating system package lists"
apt-get update
echo " → Installing Python package manager (pip)"
apt-get install -y python3-pip
echo " → Installing Python Imaging Library (PIL / Pillow)"
apt-get install python3-pil
echo " → Installing Python NumPy (provides fast numerical operations)"
apt-get install python3-numpy
echo " → Installing spidev (SPI interface for Python communication with for e-ink display)"
pip3 install spidev --break-system-packages
echo " → Installing GPIO Zero (simplified GPIO access for Raspberry Pi hardware)"
apt install python3-gpiozero
echo " → Installing playwright (a browser automation framework that supports Chromium)"
python -m pip install playwright --break-system-packages
echo " → Installing chromium (browser)"
python -m playwright install chromium



echo "Install complete"
echo "Note: A reboot is required for all changes to take effect!"