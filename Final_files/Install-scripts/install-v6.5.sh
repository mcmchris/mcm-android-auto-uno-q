#!/bin/bash
# install.sh - Instalador Automático V6.5 (Silent & Turbo)

# 1. PROTECCIÓN DE SESIÓN:
trap "" HUP
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta como root (sudo ./install.sh)"
  exit 1
fi

# === MODO SILENCIOSO (NO INTERACTIVE) ===
# Esto evita que aparezcan ventanas azules pidiendo OK
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export DEBIAN_PRIORITY=critical

echo "=== [0/5] INSTALANDO KERNEL PERSONALIZADO ==="
if [ -d "kernel" ]; then
    cd kernel || exit 1
    echo ">>> Instalando paquetes del Kernel..."
    # Usamos force-confdef para que no pregunte por archivos de config
    dpkg --force-confdef --force-confold -i *.deb
    apt-get install -f -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    cd ..
else
    echo "ERROR: No se encontró la carpeta 'kernel'. Abortando."
    exit 1
fi

echo "=== [1/5] Actualizando e instalando dependencias ==="
# Intentamos instalar, si falla apt-get update (común sin internet), seguimos.
apt-get update -q || true
# Instalación silenciosa con flags para aceptar todo
apt-get install -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    hostapd dnsmasq bluetooth bluez bluez-tools iw libusb-1.0-0 libssl-dev libprotobuf-dev protobuf-compiler iptables || echo "ADVERTENCIA: Falló apt-get. Asumiendo dependencias preinstaladas..."

echo "=== [1.5/5] Instalando librerías y configuraciones USB ==="
# A) Librerías
if [ -d "libs" ]; then
    echo ">>> Copiando librerías personalizadas..."
    cp -d libs/* /usr/lib/
    ldconfig
fi

# B) Configuración UMTPrd
if [ -d "conf" ]; then
    echo ">>> Copiando configuración USB (umtprd)..."
    mkdir -p /etc/umtprd
    cp conf/umtprd.conf /etc/umtprd/
    chmod 644 /etc/umtprd/umtprd.conf
fi

echo "=== [1.6/5] CONFIGURANDO BLUETOOTH (CRÍTICO) ==="
if [ -f "conf/main.conf" ]; then
    echo ">>> Aplicando configuración especial de Bluetooth (Micrófono Fix)..."
    mv /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak 2>/dev/null || true
    cp conf/main.conf /etc/bluetooth/main.conf
    chmod 644 /etc/bluetooth/main.conf
else
    echo "ADVERTENCIA: No se encontró conf/main.conf."
fi

echo "=== [1.8/5] NEUTRALIZANDO SERVICIOS (MODO TURBO) ==="
# Lista ampliada con lo solicitado (fwupd, timers, udisks2) + los originales de V6
SERVICES_TO_KILL="fwupd fwupd-refresh fwupd-refresh.timer udisks2 adbd android-tools-adbd usb-gadget serial-getty@ttyGS0 serial-getty@ttyUSB0 dnsmasq avahi-daemon systemd-resolved pulseaudio pipewire wireplumber ModemManager NetworkManager-wait-online cups cups-browsed unattended-upgrades snapd docker containerd user@1000 man-db man-db.timer arduino-router blueman-mechanism accounts-daemon polkit debos-grow-rootfs"

for SERVICE in $SERVICES_TO_KILL; do
    echo ">>> Neutralizando: $SERVICE"
    systemctl stop $SERVICE 2>/dev/null || true
    systemctl disable $SERVICE 2>/dev/null || true
    systemctl mask $SERVICE 2>/dev/null || true
done

# Desactivar sockets globales
systemctl --global disable pulseaudio.socket 2>/dev/null || true
systemctl --global disable pipewire.socket 2>/dev/null || true
systemctl --global disable snapd.socket 2>/dev/null || true
systemctl --global disable docker.socket 2>/dev/null || true

echo ">>> Limpiando memoria Bluetooth antigua..."
rm -rf /var/lib/bluetooth/*

echo "=== [1.9/5] CORRIGIENDO DNS DEL SISTEMA ==="
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "=== [2/5] Instalando binarios y scripts ==="
chmod +x bin/*
cp bin/aawgd /usr/local/bin/
cp bin/umtprd /usr/sbin/
cp bin/start_aa_final.sh /usr/local/bin/

echo "=== [2.5/5] Generando configuración de respaldo ==="
# (El script V13 genera esto al vuelo, pero dejamos esto como backup de seguridad)
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

echo "=== [3/5] Configurando NetworkManager ==="
if ! grep -q "unmanaged-devices=interface-name:wlan0" /etc/NetworkManager/NetworkManager.conf; then
    cat <<EOF >> /etc/NetworkManager/NetworkManager.conf

[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
fi

systemctl stop wpa_supplicant || true
systemctl disable wpa_supplicant || true
systemctl mask wpa_supplicant || true

echo "=== [4/5] Instalando Servicio Systemd (TURBO) ==="
# Escribimos el servicio OPTIMIZADO directamente aquí
cat <<EOF > /etc/systemd/system/aa-dongle.service
[Unit]
Description=Android Auto Wireless Dongle Service (Turbo)
# ARRANQUE ULTRA-RAPIDO
DefaultDependencies=no
After=local-fs.target sys-kernel-config.mount bluetooth.service
Wants=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/local/bin/start_aa_final.sh
KillSignal=SIGTERM
TimeoutStopSec=5
# Reinicio inmediato si falla
Restart=always
RestartSec=1

# Prioridad para Audio en tiempo real (Mic Fix)
LimitRTPRIO=99
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=10

User=root
Group=root
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
# Arrancar antes del login
WantedBy=sysinit.target
EOF

systemctl daemon-reload
systemctl enable aa-dongle.service

echo "=== [4.5/5] HACKEANDO BOOTLOADER (VELOCIDAD MÁXIMA) ==="
# 1. Quitar Timeout del Bootloader (Estilo V6)
if [ -f "/boot/efi/loader/loader.conf" ]; then
    sed -i 's/^timeout.*/timeout 0/' /boot/efi/loader/loader.conf || echo "timeout 0" >> /boot/efi/loader/loader.conf
    echo ">>> Timeout del Bootloader eliminado."
fi

# 2. Silenciar Kernel y Saltar FSCK (Estilo V6)
# Buscamos el archivo .conf que termine en -dirty.conf (el que usa tu sistema)
BOOT_CONF=$(ls /boot/efi/loader/entries/*-dirty.conf 2>/dev/null | head -n 1)

if [ -f "$BOOT_CONF" ]; then
    echo ">>> Optimizando Kernel en: $BOOT_CONF"
    # Si ya existe la optimización, no la duplicamos
    if ! grep -q "fsck.mode=skip" "$BOOT_CONF"; then
        sed -i '/^options/ s/$/ quiet loglevel=0 systemd.show_status=false fsck.mode=skip/' "$BOOT_CONF"
        echo ">>> Kernel silenciado y acelerado."
    fi
else
    echo "ADVERTENCIA: No se pudo encontrar el archivo .conf del bootloader."
fi

echo "======================================================="
echo "   ¡INSTALACIÓN TURBO COMPLETADA! REINICIANDO..."
echo "======================================================="
sync
sleep 2
reboot