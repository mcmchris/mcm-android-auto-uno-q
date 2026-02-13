#!/bin/bash
set -e # Stop on first error

# 1. Setup Environment
GADGET="/sys/kernel/config/usb_gadget/g_android"
UDC_NAME=$(ls /sys/class/udc | head -n 1)

echo "--- Status Report ---"
echo "UDC Hardware: $UDC_NAME"

# 2. Mount ConfigFS (if not already mounted)
if ! mountpoint -q /sys/kernel/config; then
    echo "Mounting ConfigFS..."
    sudo mount -t configfs none /sys/kernel/config
fi

# 3. Clean up any previous attempts (Just in case)
if [ -d "$GADGET" ]; then
    echo "Cleaning old gadget..."
    echo "" | sudo tee $GADGET/UDC 2>/dev/null || true
    sudo rm -f $GADGET/configs/c.1/ffs.android 2>/dev/null || true
    sudo rmdir $GADGET/functions/ffs.android 2>/dev/null || true
    sudo rmdir $GADGET/configs/c.1/strings/0x409 2>/dev/null || true
    sudo rmdir $GADGET/configs/c.1 2>/dev/null || true
    sudo rmdir $GADGET/strings/0x409 2>/dev/null || true
    sudo rmdir $GADGET 2>/dev/null || true
fi

# 4. Create the Structure
echo "Creating Gadget Structure..."
sudo mkdir -p $GADGET
sudo mkdir -p $GADGET/strings/0x409
sudo mkdir -p $GADGET/configs/c.1/strings/0x409
sudo mkdir -p $GADGET/functions/ffs.android  # <--- This failed before. Should work now.

# 5. Configure IDs (AAWireless / Android Auto)
echo "0x1d6b" | sudo tee $GADGET/idVendor
echo "0x0104" | sudo tee $GADGET/idProduct
echo "mcmchris" | sudo tee $GADGET/strings/0x409/manufacturer
echo "AAWireless" | sudo tee $GADGET/strings/0x409/product
echo "123456789" | sudo tee $GADGET/strings/0x409/serialnumber
echo "Android Auto" | sudo tee $GADGET/configs/c.1/strings/0x409/configuration
echo 500 | sudo tee $GADGET/configs/c.1/MaxPower

# 6. Link Function
echo "Linking..."
sudo ln -s $GADGET/functions/ffs.android $GADGET/configs/c.1/

# 7. Mount FunctionFS
echo "Mounting FunctionFS..."
sudo mkdir -p /dev/ffs
if ! mountpoint -q /dev/ffs; then
    sudo mount -t functionfs android /dev/ffs
fi

echo "SUCCESS! Gadget is live and bound to $UDC_NAME"

sudo /usr/local/bin/aawgd