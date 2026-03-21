#!/bin/bash
# modo_dongle.sh - Converts the board back to AA Dongle and Reboots

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./modo_dongle.sh)"
  exit 1
fi

echo ">>> [1/4] Restoring NetworkManager block..."
# Remove the comment (#) to ignore wlan0 again
sed -i 's/^#unmanaged-devices=/unmanaged-devices=/' /etc/NetworkManager/NetworkManager.conf

echo ">>> [2/4] Disabling Wi-Fi client (wpa_supplicant)..."
# Masking the supplicant again
systemctl stop wpa_supplicant
systemctl disable wpa_supplicant
systemctl mask wpa_supplicant

echo ">>> [3/4] Cleaning connections and conflicts..."
# Deleting all saved networks dynamically for security
for uuid in $(nmcli -g UUID connection 2>/dev/null); do
    nmcli connection delete uuid "$uuid" >/dev/null 2>&1
done

# Ensuring no one occupies port 53 (DNS)
systemctl stop dnsmasq avahi-daemon systemd-resolved
systemctl disable dnsmasq avahi-daemon systemd-resolved
systemctl mask dnsmasq avahi-daemon systemd-resolved

echo ">>> [4/4] Restoring generic DNS..."
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "=================================================="
echo " DONE! The board is in DONGLE MODE."
echo " Rebooting in 5 seconds..."
echo "=================================================="
sleep 5
reboot