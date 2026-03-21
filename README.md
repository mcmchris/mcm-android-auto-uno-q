# 🚗 MCM Android Auto Wireless Dongle for Arduino UNO Q

This project turns an **Arduino UNO Q** (2GB/4GB) running Linux into a *Plug & Play* Wireless Android Auto Dongle. It allows you to connect your phone to your vehicle's infotainment system without cables, using an ultra-fast 5GHz WiFi and Bluetooth connection.

## ✨ Main Features (V7.4)

* **100% Autonomous Installation (`install.sh`):** Automatically configures networks, USB Gadgets, Bluetooth, and dependencies.
* **Safe Turbo Boot:** Disables unnecessary Linux services for a fast and optimized boot sequence.
* **Stable Wireless Network:** Hostapd forced to 5GHz (HT20) with IPv6 disabled to prevent crashes due to duplicate IP addresses.
* **USB-Drop Proof:** The installation survives and completes even if the ADB/SSH connection over USB drops during the process.
* **Hardware Hard Reset:** Integration with the board's physical user button to clear the Bluetooth device cache with 3 quick clicks (via DBus).
* **LED Indicators:** Visual feedback during the installation process via the blue user LED.

---

## 📁 Repository Structure

* `/mcm_aa_installer` - Main installer folder.
  * `/aawg_src` - Original source code of the Android Auto Wireless daemon (if applicable).
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

## 🔄 Bluetooth Usage and Hard Reset

Once installed, the board will automatically create a hidden WiFi network and broadcast a Bluetooth signal.
* **Pairing:** Search for Bluetooth devices from your Android phone and connect to the board. Android Auto will launch automatically on your car's screen.

### Troubleshooting (The Magic Button)
If you change phones, the device enters a connection loop, or Android Auto fails to start:
1. Go to your phone's Bluetooth settings and select **"Forget"** for the dongle's network.
2. On the Arduino board, press the physical **user button 3 quick times**.
3. The blue LED will blink 5 times.
4. The system will purge all saved devices directly from RAM (via DBus), restart the Bluetooth antenna, and be good as new, ready for a clean pairing process.

---

## 📜 License and Acknowledgments
*(Add your desired license here, e.g., MIT, GPLv3, and any additional credits you want to include).*