#!/bin/bash

# 1. Define your interface name (Verify if it is wlan0 or something else)
IFACE="wlan0"

# 2. Stop conflicting services that might grab the wifi card
echo "Stopping NetworkManager and wpa_supplicant..."
sudo systemctl stop NetworkManager
sudo systemctl stop wpa_supplicant
# (Optional: kill them manually if they persist)
sudo killall wpa_supplicant 2> /dev/null

# 3. Create a minimal hostapd config file for 5GHz (Mode A) on Channel 149
cat <<EOF > hostapd_test.conf
interface=$IFACE
driver=nl80211
ssid=MCM_TEST_5GHZ
hw_mode=a
channel=149
ieee80211n=1
ieee80211ac=1
wmm_enabled=1
auth_algs=1
EOF

# 4. Set the interface IP (Required for hostapd to start properly)
echo "Setting IP address for $IFACE..."
sudo ip link set $IFACE up
sudo ip addr add 192.168.50.1/24 dev $IFACE

# 5. Start Hostapd
echo "Starting Access Point on Channel 149..."
echo "Look for WiFi Name: MCM_TEST_5GHZ"
echo "Press CTRL+C to stop."
echo "-----------------------------------"
sudo hostapd -d hostapd_test.conf
