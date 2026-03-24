# 🚗 Android Auto Wireless Dongle for Arduino UNO Q

This project turns an **Arduino UNO Q** (2GB/4GB) running Linux into a *Plug & Play* Wireless Android Auto Dongle. It allows you to connect your phone to your vehicle's infotainment system without cables, using an ultra-fast 5GHz WiFi and Bluetooth connection.

![](/readme_assets/aa-wireless-tb.jpg)

## ✨ Main Features (V7.4)

* **100% Autonomous Installation (`install.sh`):** Automatically configures networks, USB Gadgets, Bluetooth, and dependencies.
* **USB-Drop Proof:** The installation survives and completes even if the ADB/SSH connection over USB drops during the process.
* **Safe Turbo Boot:** Disables unnecessary Linux services for a fast and optimized boot sequence.
* **Stable Wireless Network:** Hostapd forced to 5GHz (HT20) with IPv6 disabled to prevent crashes due to duplicate IP addresses.
* **Hardware Controls:** Integration with the board's physical user button for Bluetooth cache wiping (3 clicks) or Emergency USB Recovery (5+ clicks).
* **LED Indicators:** Visual feedback during the installation process via the blue user LED.
* **Network Switching:** Built-in scripts to easily toggle between Dongle mode and your Home Wi-Fi network for maintenance or SSH access.
---

## 📁 Repository Structure

* `/mcm_aa_installer` - Main installer folder.
  * `/aawg_src` - Original source code of the Android Auto Wireless daemon.
  * `/bin` - Precompiled binaries and execution scripts (`aawgd`, `umtprd`, `start_aa_final.sh`).
  * `/conf` - Master configuration files (`main.conf`, `umtprd.conf`).
  * `/kernel` - Custom Kernel `.deb` packages to enable USB Gadget and MTP modules.
  * `/libs` - Dynamic libraries required for execution.
  * `aa-dongle.service` - Original Systemd service configuration file.
  * `install.sh` - The master automated installer script.

---

## 🛠️ Prerequisites

1. An **Arduino UNO Q** board powered on and running its default Linux distribution.
2. Connection to the board via **SSH** or **ADB shell** (via WiFi, Ethernet, or USB cable).
3. **Internet connection** on the board (required to download packages via `apt-get` during installation).

---

## 🚀 Installation Guide

**Step 1:** Clone this repository or transfer the `mcm_aa_installer` folder to your board (e.g., to the `/home/arduino/` or `~` directory).

**Step 2:** Enter the installer folder in your board's terminal:
```bash
cd mcm_aa_installer
```

**Step 3:** Grant execution permissions to all scripts:
```bash
chmod +x install.sh bin/*.sh
```

**Step 4:** Run the installer with superuser privileges:
```bash
sudo ./install.sh
```

### ⚠️ IMPORTANT DURING INSTALLATION!
* Upon starting, the board's **blue LED will turn ON**, indicating the process is active.
* The script will disable the board's network and USB services to optimize boot time. **If you are connected via USB cable (ADB) or SSH, your terminal connection will abruptly close.** This is completely normal!
* **DO NOT DISCONNECT POWER TO THE BOARD.** The process will continue running flawlessly in the background.
* You will know the installation finished successfully when the **blue LED turns OFF** and the board reboots itself (takes approximately 1-2 minutes).

---

## 🔘 Hardware Button Controls (The Magic Button)

The physical user button on the board is programmed to handle troubleshooting and debugging without needing external tools.

### 1. Bluetooth Hard Reset (3 Clicks)
If you change phones, the device enters a connection loop, or Android Auto fails to start:
1. Go to your phone's Bluetooth settings and select **"Forget"** for the dongle's network.
2. On the Arduino board, press the physical user button **3 quick times**.
3. The LED will **blink Yellow (Red+Green)** 5 times.
4. The system will purge all saved devices directly from RAM (via DBus), restart the Bluetooth antenna, and be ready for a clean pairing process.

### 2. USB Debug / Recovery Mode (5+ Clicks)
Since the USB port is repurposed for Android Auto and network services are disabled for speed, you might need a way to access the board's console (ADB/SSH) for debugging.
1. While the board is running, press the user button **5 or more quick times**.
2. The LED will blink very fast and then turn **Solid Cyan (Green+Blue)**.
3. The Android Auto services will stop, and the original USB Gadget (ADB/Serial) will be re-enabled.
4. Connect the board to your PC via USB to access the serial console or ADB shell.
5. **To exit Debug Mode:** Simply power cycle the board (unplug and replug) or run `reboot` in the terminal. It will boot back into normal Dongle mode.

---

## 🌐 Network Management (Home Wi-Fi vs. Dongle Mode)

If you need to connect the board to the internet (e.g., to run `apt-get` updates, transfer files, or modify code), you can temporarily disable the Android Auto Hotspot and connect to your local Wi-Fi router.

### Connect to your Home Network
Run the following script, replacing `<SSID>` and `<PASSWORD>` with your home Wi-Fi details:
```bash
cd ~/mcm_aa_installer
sudo bin/connect_home.sh "YourWiFiName" "YourWiFiPassword"
```
*The board will kill the Dongle services, unmask the NetworkManager, and connect to your router. You can now access it via SSH over your local network.*

### Restore Dongle Mode
Once you are done with your maintenance, you must revert the board to Dongle mode before plugging it back into your car:
```bash
cd ~/mcm_aa_installer
sudo bin/modo_dongle.sh
```
*The script will wipe the saved Wi-Fi networks for security, mask the network services again, and automatically reboot the board into a clean Android Auto state.*

---

## 📜 Acknowledgments
Adapted and ported from this [repository](https://github.com/nisargjhaveri/WirelessAndroidAutoDongle).