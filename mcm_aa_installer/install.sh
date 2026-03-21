#!/bin/bash
# install.sh - Automatic Installer V7.4 (LED Status, Safe Boot, USB-Drop Proof & BT DBus-Reset)

trap "" HUP
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./install.sh)"
    exit 1
fi

echo ">>> Unlocking file system (Forcing RW)..."
mount -o remount,rw / || true

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export DEBIAN_PRIORITY=critical

# === CONTROL DE LED: ENCENDIDO (Instalación en proceso) ===
LED_PATH="/sys/class/leds/blue:user/brightness"
echo 1 > "$LED_PATH" 2>/dev/null || true
echo ">>> Visual Status: Blue LED turned ON."

echo "=== [0/6] INSTALLING CUSTOM KERNEL ==="
if [ -d "kernel" ]; then
    cd kernel || exit 1
    dpkg --force-confdef --force-confold -i *.deb
    apt-get install -f -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    cd ..
else
    echo "ERROR: 'kernel' folder not found. Aborting."
    echo 0 > "$LED_PATH" 2>/dev/null || true
    exit 1
fi

echo "=== [1/6] Updating and installing dependencies ==="
apt-get update -q || true
apt-get install -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    hostapd dnsmasq bluetooth bluez bluez-tools iw libusb-1.0-0 libssl-dev libprotobuf-dev protobuf-compiler iptables python3-evdev || echo "WARNING: apt-get failed."

echo "=== [2/6] Installing libraries and USB configurations ==="
if [ -d "libs" ]; then
    cp -d libs/* /usr/lib/
    chmod 755 /usr/lib/libdbus-cxx.so*
    ldconfig
fi

if [ -d "conf" ]; then
    mkdir -p /etc/umtprd
    cp conf/umtprd.conf /etc/umtprd/
    chmod 644 /etc/umtprd/umtprd.conf
fi

if [ -f "conf/main.conf" ]; then
    mv /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak 2>/dev/null || true
    cp conf/main.conf /etc/bluetooth/main.conf
    chmod 644 /etc/bluetooth/main.conf
fi

echo "=== [3/6] NEUTRALIZING SERVICES (SAFE TURBO MODE) ==="
echo "⚠️  WARNING: USB and Network services will be disabled."
echo "⚠️  If you are installing via ADB or SSH over USB, YOUR CONNECTION WILL BE CLOSED NOW."
echo "⚠️  The script will move to the background, finish the installation, and the board will reboot automatically."
echo "⚠️  Starting autonomous phase in 5 seconds..."
sleep 5

# Redirecting stdout and stderr to a log file so the script survives USB disconnection
exec > /var/log/mcm_installer.log 2>&1

# FSCK is kept intact for disk safety
SERVICES_TO_KILL="fwupd fwupd-refresh fwupd-refresh.timer networking arduino-burn-bootloader adbd android-tools-adbd usb-gadget serial-getty@ttyGS0 serial-getty@ttyUSB0 dnsmasq avahi-daemon systemd-resolved pulseaudio pipewire wireplumber ModemManager NetworkManager-wait-online cups cups-browsed unattended-upgrades snapd docker containerd user@1000 user@103 lightdm display-manager man-db man-db.timer arduino-router blueman-mechanism udisks2 accounts-daemon polkit debos-grow-rootfs"

for SERVICE in $SERVICES_TO_KILL; do
    echo ">>> Neutralizing: $SERVICE"
    systemctl stop --no-block $SERVICE 2>/dev/null || true
    systemctl disable $SERVICE 2>/dev/null || true
    ln -sf /dev/null /etc/systemd/system/$SERVICE 2>/dev/null || true
    systemctl mask $SERVICE 2>/dev/null || true
done

systemctl --global disable pulseaudio.socket 2>/dev/null || true
systemctl --global disable pipewire.socket 2>/dev/null || true
systemctl --global disable snapd.socket 2>/dev/null || true
systemctl --global disable docker.socket 2>/dev/null || true

rm -rf /var/lib/bluetooth/*
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

mkdir -p /etc/systemd/journald.conf.d
echo -e "[Journal]\nStorage=volatile\nCompress=no" > /etc/systemd/journald.conf.d/00-volatile.conf

echo "=== [4/6] INSTALLING BLUETOOTH RESET SYSTEM (PHYSICAL BUTTON) ==="
sed -i 's/.*HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf || echo "HandlePowerKey=ignore" >> /etc/systemd/logind.conf

cat << 'EOF' > /usr/local/bin/bt_reset_monitor.py
#!/usr/bin/env python3
import time
import subprocess
import evdev

LED_PATH = '/sys/class/leds/blue:user/brightness'
CLICK_WINDOW = 2.0
REQUIRED_CLICKS = 3

def get_button_device():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if "pm8941_pwrkey" in device.name.lower():
            return device
    return evdev.InputDevice('/dev/input/event1')

def blink_led(times):
    try:
        for _ in range(times):
            with open(LED_PATH, 'w') as f:
                f.write('1')
            time.sleep(0.08)
            with open(LED_PATH, 'w') as f:
                f.write('0')
            time.sleep(0.08)
    except Exception:
        pass

def reset_bluetooth():
    blink_led(5)
    
    subprocess.run(['systemctl', 'stop', 'aa-dongle'], shell=False)
    time.sleep(1)
    
    try:
        result = subprocess.run(['bluetoothctl', 'devices'], capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if line.startswith('Device '):
                mac = line.split(' ')[1]
                subprocess.run(f"echo 'remove {mac}' | bluetoothctl", shell=True)
    except Exception:
        pass
        
    subprocess.run(['rm', '-rf', '/var/lib/bluetooth/*'], shell=True)
    subprocess.run(['systemctl', 'restart', 'bluetooth'], shell=False)
    time.sleep(1)
    subprocess.run(['systemctl', 'start', 'aa-dongle'], shell=False)

def main():
    try:
        device = get_button_device()
        device.grab()
    except Exception:
        return

    clicks = []
    try:
        for event in device.read_loop():
            if event.type == evdev.ecodes.EV_KEY:
                key_event = evdev.categorize(event)
                if key_event.keycode == 'KEY_POWER' and key_event.keystate == 1:
                    now = time.time()
                    clicks.append(now)
                    clicks = [t for t in clicks if now - t <= CLICK_WINDOW]

                    if len(clicks) >= REQUIRED_CLICKS:
                        reset_bluetooth()
                        clicks = []
    except Exception:
        pass

if __name__ == '__main__':
    main()
EOF

chmod +x /usr/local/bin/bt_reset_monitor.py

cat << 'EOF' > /etc/systemd/system/bt-reset.service
[Unit]
Description=Bluetooth Hardware Reset Button Monitor
After=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/bt_reset_monitor.py
Restart=always
RestartSec=2
User=root
Nice=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bt-reset.service

echo "=== [5/6] Installing binaries and scripts ==="
chmod +x bin/*
cp bin/aawgd /usr/local/bin/
cp bin/umtprd /usr/sbin/
cp bin/start_aa_final.sh /usr/local/bin/

if [ -f "/sys/class/net/wlan0/address" ]; then
    REAL_MAC=$(cat /sys/class/net/wlan0/address | tr -d '\n')
    cat <<EOF > /etc/aawgd.conf
AAWG_CONNECTION_STRATEGY=1
ssid=AAWirelessDongle
password=12345678
bssid=$REAL_MAC
ip_address=10.0.0.1
EOF
    chmod 644 /etc/aawgd.conf
fi

if ! grep -q "unmanaged-devices=interface-name:wlan0" /etc/NetworkManager/NetworkManager.conf; then
    cat <<EOF >> /etc/NetworkManager/NetworkManager.conf

[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
fi

systemctl stop wpa_supplicant || true
systemctl disable wpa_supplicant || true
systemctl mask wpa_supplicant || true

echo "=== [6/6] Installing Systemd Service (TURBO) ==="
cat <<EOF > /etc/systemd/system/aa-dongle.service
[Unit]
Description=Android Auto Wireless Dongle Service
DefaultDependencies=no
After=local-fs.target sys-kernel-config.mount bluetooth.service
Wants=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/local/bin/start_aa_final.sh
KillSignal=SIGTERM
TimeoutStopSec=5
Restart=always
RestartSec=1
LimitRTPRIO=99
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=10
User=root
Group=root
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=sysinit.target
EOF

systemctl daemon-reload
systemctl enable aa-dongle.service

if [ -f "/boot/efi/loader/loader.conf" ]; then
    sed -i 's/^timeout.*/timeout 0/' /boot/efi/loader/loader.conf || echo "timeout 0" >> /boot/efi/loader/loader.conf
fi

systemctl set-default multi-user.target 2>/dev/null || true

# === CONTROL DE LED: APAGADO (Instalación finalizada) ===
echo "======================================================="
echo "   V7.4 INSTALLATION COMPLETED! REBOOTING..."
echo "======================================================="
echo 0 > "$LED_PATH" 2>/dev/null || true
sync
sleep 2
reboot