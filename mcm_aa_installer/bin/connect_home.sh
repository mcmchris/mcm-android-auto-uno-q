#!/bin/bash
# connect_home.sh - Disables Dongle mode and connects to Home Wi-Fi

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./connect_home.sh <SSID> <PASSWORD>)"
  exit 1
fi

# Check if both arguments (SSID and Password) are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: sudo ./connect_home.sh <SSID> <PASSWORD>"
  echo "Example: sudo ./connect_home.sh MyWiFiNetwork MySecretPassword123"
  exit 1
fi

TARGET_SSID="$1"
TARGET_PASS="$2"

echo ">>> [1/6] Stopping Android Auto services..."
systemctl stop aa-dongle
# Killing all aggressive services to free the WiFi chip
killall -9 aawgd umtprd bt-agent hostapd dnsmasq wpa_supplicant 2>/dev/null

echo ">>> [2/6] Preparing environment for NetworkManager..."
# IMPORTANT: DO NOT start wpa_supplicant manually. 
# NetworkManager will start it itself if needed.
systemctl stop wpa_supplicant
systemctl disable wpa_supplicant
systemctl unmask wpa_supplicant # Just unmask it, but don't start it

echo ">>> [3/6] Releasing NetworkManager configuration..."
# Enable wlan0 in NM config (comment out the exclusion line)
sed -i 's/^unmanaged-devices=/#unmanaged-devices=/' /etc/NetworkManager/NetworkManager.conf

# Physical interface cleanup
ip addr flush dev wlan0
ip link set wlan0 down
ip link set wlan0 up

echo ">>> [4/6] Restarting NetworkManager..."
systemctl restart NetworkManager
sleep 4 # Waiting for the service to load

echo ">>> [5/6] Forcing management and Scanning..."
# Ensure the radio is on
nmcli radio wifi on
# Explicitly tell NM to manage wlan0
nmcli device set wlan0 managed yes
sleep 2

# Force a scan to find the target network
echo ">>> Scanning nearby networks..."
nmcli device wifi rescan
# Allow time for scan results to arrive (CRITICAL)
sleep 5 

echo ">>> [6/6] Connecting to $TARGET_SSID..."
# Delete previous attempts to clean up
nmcli connection delete "$TARGET_SSID" 2>/dev/null
nmcli connection delete "AAWirelessDongle" 2>/dev/null

# Attempting to connect using the provided arguments
nmcli dev wifi connect "$TARGET_SSID" password "$TARGET_PASS"

echo "========================================"
echo " FINAL STATUS:"
echo "========================================"
nmcli dev status
ip addr show wlan0 | grep inet