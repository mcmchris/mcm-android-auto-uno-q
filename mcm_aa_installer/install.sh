#!/bin/bash
# install.sh - Automatic Installer V7.5 (RGB LED Status, Safe Boot, USB-Drop Proof & BT DBus-Reset)

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

# === RGB LED STATUS (Autonomous Phase Start: Orange R+G) ===
# Adjust paths if needed (e.g., usb instead of user)
LED_R_PATH="/sys/class/leds/red:user/brightness"
LED_G_PATH="/sys/class/leds/green:user/brightness"
LED_B_PATH="/sys/class/leds/blue:user/brightness"

# Turn on Orange (Rojo + Verde)
echo 1 > "$LED_R_PATH" 2>/dev/null || true
echo 1 > "$LED_G_PATH" 2>/dev/null || true
echo 0 > "$LED_B_PATH" 2>/dev/null || true
echo ">>> Visual Status: RGB LED turned ORANGE (Installation in progress)."

echo "=== [0/6] INSTALLING CUSTOM KERNEL ==="
if [ -d "kernel" ]; then
    cd kernel || exit 1
    dpkg --force-confdef --force-confold -i *.deb
    apt-get install -f -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    cd ..
else
    echo "ERROR: 'kernel' folder not found. Aborting."
    # Turn off LED on fatal error
    echo 0 > "$LED_R_PATH" 2>/dev/null || true
    echo 0 > "$LED_G_PATH" 2>/dev/null || true
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
import threading

# Dynamic RGB Mapping
# Adjust paths if needed
LED_PATHS = {
    'red':   '/sys/class/leds/red:user/brightness',
    'green': '/sys/class/leds/green:user/brightness',
    'blue':  '/sys/class/leds/blue:user/brightness'
}
CLICK_TIMEOUT = 0.8  # Seconds to wait after the last click before evaluating

click_count = 0
timer = None

def get_button_device():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if "pm8941_pwrkey" in device.name.lower():
            return device
    return evdev.InputDevice('/dev/input/event1')

def set_color(r, g, b):
    # Set RGB state, ensure all other LEDs are off
    cmd_r = 0 if r == 0 else 1
    cmd_g = 0 if g == 0 else 1
    cmd_b = 0 if b == 0 else 1
    try:
        with open(LED_PATHS['red'], 'w') as f: f.write(str(cmd_r))
        with open(LED_PATHS['green'], 'w') as f: f.write(str(cmd_g))
        with open(LED_PATHS['blue'], 'w') as f: f.write(str(cmd_b))
    except Exception:
        pass

def turn_off():
    try:
        for p in LED_PATHS.values():
            with open(p, 'w') as f: f.write('0')
    except Exception:
        pass

def blink_color(times, r, g, b, delay=0.08):
    turn_off()
    for _ in range(times):
        set_color(r, g, b)
        time.sleep(delay)
        turn_off()
        time.sleep(delay)

def reset_bluetooth():
    # Fast Yellow Blinking (R+G)
    blink_color(times=5, r=1, g=1, b=0, delay=0.06)
    
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

def activate_debug_mode():
    # Very Fast Cyan Blinking (G+B)
    blink_color(times=10, r=0, g=1, b=1, delay=0.04)
    # Exiting script, dynamic indicators are set in enable_debug.sh
    subprocess.run(['/usr/local/bin/enable_debug.sh'], shell=False)

def evaluate_clicks():
    global click_count, timer
    count = click_count
    click_count = 0  # Reset for the next sequence
    timer = None
    
    if count == 3 or count == 4:
        reset_bluetooth()
    elif count >= 5:
        activate_debug_mode()

def main():
    global click_count, timer
    # Ensure LEDs start OFF
    turn_off()
    
    try:
        device = get_button_device()
        device.grab()
    except Exception:
        return

    try:
        for event in device.read_loop():
            if event.type == evdev.ecodes.EV_KEY:
                key_event = evdev.categorize(event)
                # Count only when the button is pressed down (keystate == 1)
                if key_event.keycode == 'KEY_POWER' and key_event.keystate == 1:
                    click_count += 1
                    
                    # Reset the timer with every new click
                    if timer is not None:
                        timer.cancel()
                    
                    timer = threading.Timer(CLICK_TIMEOUT, evaluate_clicks)
                    timer.start()
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
cp bin/enable_debug.sh /usr/local/bin/

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

# === RGB LED STATUS (Autonomous Phase Stop: Solid GREEN -> Turn Off) ===
echo "======================================================="
echo "   V7.5 INSTALLATION COMPLETED! REBOOTING..."
echo "======================================================="
# Flash Solid Green (Verde Puro) for final confirmation
echo 0 > "$LED_R_PATH"
echo 1 > "$LED_G_PATH"
echo 0 > "$LED_B_PATH"
sync
sleep 2

# Turn OFF all before rebooting
echo 0 > "$LED_R_PATH"
echo 0 > "$LED_G_PATH"
echo 0 > "$LED_B_PATH"

reboot