#!/bin/bash
# bin/enable_debug.sh
# Enables USB Debug (ADB/Serial) temporarily until the next reboot.

# Color Mapping: Cyan (Green+Blue)
# Adjust these paths if they differ on your board
LED_G="/sys/class/leds/green:user/brightness"
LED_B="/sys/class/leds/blue:user/brightness"
LED_R="/sys/class/leds/red:user/brightness"

echo ">>> [DEBUG MODE] Autonomous phase starting..."

echo ">>> [DEBUG MODE] Wiping dynamic USB configuration..."
# Clean up any generic gadget
for gadget in /sys/kernel/config/usb_gadget/*; do
    if [ -d "$gadget" ]; then
        echo "" | tee "$gadget/UDC" >/dev/null 2>&1
    fi
done

echo ">>> [DEBUG MODE] Stopping Android Auto Dongle Service..."
systemctl stop aa-dongle
sleep 2

# Force original USB periphs
echo ">>> [DEBUG MODE] Unmasking ADB/Gadget services..."
systemctl unmask adbd usb-gadget serial-getty@ttyGS0 2>/dev/null

echo ">>> [DEBUG MODE] Activating ADB and serial console..."
systemctl start usb-gadget
systemctl start adbd
systemctl start serial-getty@ttyGS0

# Setting Dynamic Recovery Indicator (Cyan)
echo 0 > "$LED_R"
echo 1 > "$LED_G"
echo 1 > "$LED_B"

echo "=================================================="
echo " [DEBUG MODE ACTIVE] Connect your USB cable."
echo " Power cycle or run 'reboot' to restore Dongle mode."
echo "=================================================="