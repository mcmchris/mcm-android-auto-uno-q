#!/bin/bash
# /usr/local/bin/start_aa_final.sh
# V9.1: Disable IPv6 (Fixes "Duplicate Address" crashes) + UART Soft Reset + 5GHz Unlock

# ==========================================
# 1. MASTER VARIABLES
# ==========================================
MY_SSID="AAWirelessDongle"
MY_PASS="12345678"
MY_IP="10.0.0.1"

export AAWG_WIFI_SSID="$MY_SSID"
export AAWG_WIFI_PASSWORD="$MY_PASS"
export AAWG_CONNECTION_STRATEGY="1"
export AAWG_COUNTRY_CODE="US"

WLAN_IF="wlan0"
GADGET_ROOT="/sys/kernel/config/usb_gadget"
AAWGD_BIN="/usr/local/bin/aawgd"
UMTPRD_BIN="/usr/sbin/umtprd"

# ==========================================
# 2. FUNCTIONS
# ==========================================

cleanup() {
    echo ">>> [STOP] Stopping processes..."
    kill $(jobs -p) 2>/dev/null
    for gadget in $GADGET_ROOT/*; do
        if [ -d "$gadget" ]; then echo "" | sudo tee "$gadget/UDC" >/dev/null 2>&1; fi
    done
    sudo killall -q aawgd umtprd bt-agent hostapd dnsmasq wpa_supplicant
    exit 0
}
trap cleanup SIGTERM SIGINT

wait_for_interface() {
    local iface=$1
    local max_retries=60
    local count=0
    echo ">>> Waiting for interface $iface..."
    while ! ip link show "$iface" >/dev/null 2>&1; do
        sleep 1
        count=$((count+1))
        if [ $count -ge $max_retries ]; then return 1; fi
    done
    return 0
}

# ==========================================
# 3. INITIALIZATION
# ==========================================
echo "=== [1/7] Cleanup ==="
sudo killall -9 aawgd umtprd bt-agent hostapd dnsmasq wpa_supplicant 2>/dev/null
sudo nmcli device set $WLAN_IF managed no 2>/dev/null

# Fix Bluetooth (Soft reset instead of restarting the service)
echo ">>> Soft resetting Bluetooth adapter..."
sudo rfkill unblock bluetooth
sudo hciconfig hci0 down
sleep 1
sudo hciconfig hci0 up
sleep 1

# Force "No Audio" Class (Service Class: None, Major Device Class: Uncategorized)
sudo hciconfig hci0 class 0x000000

# ==========================================
# 4. NETWORK (5GHz UNLOCK & SETUP)
# ==========================================
echo "=== [2/7] Network Configuration ==="
if ! wait_for_interface "$WLAN_IF"; then
    echo ">>> FATAL ERROR: WiFi interface did not appear. Attempting driver reload..."
    sudo modprobe -r ath10k_sdio ath10k_core
    sleep 1
    sudo modprobe ath10k_sdio
    sleep 1
fi

# --- START 5GHZ UNLOCK PROCEDURE ---
echo ">>> [UNLOCK] Starting scan to unlock 5GHz..."
sudo ip link set $WLAN_IF down
sudo iw dev $WLAN_IF set type managed
sudo ip link set $WLAN_IF up

# CRITICAL FIX: Wait for link to settle before scanning
sleep 2

# Scan 3 times WITH TIMEOUT.
for i in {1..3}; do
    echo ">>> [UNLOCK] Scan attempt $i..."
    sudo timeout 3s iw dev $WLAN_IF scan > /dev/null 2>&1 || true
    sleep 0.5
done
echo ">>> [UNLOCK] Scan completed. Applying safety delay..."

# Increase wait time to 5s so the Kernel can process "COUNTRY_UPDATE"
sleep 1

# Force US region just in case
sudo iw reg set US
sleep 1
# --- END 5GHZ UNLOCK PROCEDURE ---

# FIX V9: DISABLE IPV6 TO PREVENT DUPLICATE ADDRESS CRASHES
echo ">>> [FIX] Disabling IPv6 on $WLAN_IF..."
sudo sysctl -w net.ipv6.conf.$WLAN_IF.disable_ipv6=1 > /dev/null

# Final IP Configuration
sudo ip addr flush dev $WLAN_IF
sudo ip addr add $MY_IP/24 dev $WLAN_IF

# Hostapd configured for 5GHz (HT20/AC)
cat <<EOF > /tmp/hostapd.conf
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
interface=$WLAN_IF
ssid=$MY_SSID
country_code=US
# 5GHz Settings
hw_mode=a
channel=149
ieee80211n=1
ieee80211ac=1
wmm_enabled=1
# Use HT20 to avoid secondary channel conflicts
ht_capab=[HT20][SHORT-GI-20]
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$MY_PASS
EOF

echo ">>> Starting Hostapd (5GHz)..."
sudo hostapd -B /tmp/hostapd.conf

# Check if Hostapd actually lived
sleep 2
if ! pgrep -x "hostapd" > /dev/null; then
    echo ">>> FATAL ERROR: Hostapd failed to start. Check logs."
    exit 1
fi

cat <<EOF > /tmp/dnsmasq.conf
interface=$WLAN_IF
dhcp-range=10.0.0.2,10.0.0.20,12h
dhcp-authoritative
dhcp-option=3
dhcp-option=6
EOF
sudo rm -f /var/lib/misc/dnsmasq.leases
sudo dnsmasq -C /tmp/dnsmasq.conf

echo "=== [3/7] AAWGD Configuration ==="
if [ -f "/sys/class/net/$WLAN_IF/address" ]; then
    REAL_MAC=$(cat /sys/class/net/$WLAN_IF/address | tr -d '\n')
else
    REAL_MAC=$(ip link show $WLAN_IF | awk '/ether/ {print $2}')
fi
echo ">>> MAC: $REAL_MAC"

cat <<EOF > /etc/aawgd.conf
AAWG_CONNECTION_STRATEGY=1
ssid=$MY_SSID
password=$MY_PASS
bssid=$REAL_MAC
ip_address=$MY_IP
EOF

echo "=== [4/7] USB Configuration ==="
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
mkdir -p "$GADGET_ROOT/default/strings/0x409"
echo "0x18D1" > "$GADGET_ROOT/default/idVendor"
echo "0x4EE1" > "$GADGET_ROOT/default/idProduct"
echo "My Own" > "$GADGET_ROOT/default/strings/0x409/manufacturer"
echo "AA Wireless Dongle" > "$GADGET_ROOT/default/strings/0x409/product"
mkdir -p "$GADGET_ROOT/default/functions/ffs.mtp"
mkdir -p "$GADGET_ROOT/default/configs/c.1/strings/0x409"
ln -s "$GADGET_ROOT/default/functions/ffs.mtp" "$GADGET_ROOT/default/configs/c.1/"

mkdir -p "$GADGET_ROOT/accessory/strings/0x409"
echo "0x18D1" > "$GADGET_ROOT/accessory/idVendor"
echo "0x2D00" > "$GADGET_ROOT/accessory/idProduct"
echo "Google, Inc." > "$GADGET_ROOT/accessory/strings/0x409/manufacturer"
echo "Android Open Accessory device" > "$GADGET_ROOT/accessory/strings/0x409/product"
mkdir -p "$GADGET_ROOT/accessory/functions/accessory.usb0"
mkdir -p "$GADGET_ROOT/accessory/configs/c.1/strings/0x409"
ln -s "$GADGET_ROOT/accessory/functions/accessory.usb0" "$GADGET_ROOT/accessory/configs/c.1/"

mkdir -p /dev/ffs-mtp
mount -t functionfs mtp /dev/ffs-mtp 2>/dev/null
sudo $UMTPRD_BIN &

echo "=== [5/7] Firewall Setup ==="
sudo iptables -I INPUT -p tcp --dport 5288 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 5288 -j ACCEPT

echo "=== [6/7] Bluetooth Agent Setup ==="
# NoInputNoOutput helps prevent PIN prompts and keyboard impersonation
sudo /usr/bin/bt-agent --capability=NoInputNoOutput --daemon &

auto_trust_daemon() {
    while true; do
        devices=$(bluetoothctl devices | cut -f2 -d' ')
        for mac in $devices; do
            if [ ! -z "$mac" ]; then bluetoothctl trust "$mac" >/dev/null 2>&1; fi
        done
        sleep 1
    done
}
auto_trust_daemon &

echo "=== [7/7] LAUNCHING SERVICES ==="
# Attempt to disable voice profiles one more time via command
sudo bluetoothctl <<EOF
power on
discoverable on
pairable on
EOF

echo ">>> Executing aawgd..."
sudo -E chrt -r 20 $AAWGD_BIN &
wait $!