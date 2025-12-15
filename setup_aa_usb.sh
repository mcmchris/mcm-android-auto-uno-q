#!/bin/bash
set -e

# Configuración
UDC_NAME="4e00000.usb" # Verifica con ls /sys/class/udc
GADGET_BASE="/sys/kernel/config/usb_gadget"
GADGET_DIR="$GADGET_BASE/g_aa"

echo "=== Iniciando Configuración USB Android Auto (Modo Accesorio) ==="

# --- FASE 1: Limpieza Previa ---
# Desactivar cualquier gadget activo
if [ -f /sys/class/udc/$UDC_NAME/state ]; then
     echo "" > /sys/class/udc/$UDC_NAME/device/gadget/UDC 2>/dev/null || true
fi

# Borrar gadget g_aa si existe
if [ -d "$GADGET_DIR" ]; then
    echo "Limpiando g_aa previo..."
    echo "" > "$GADGET_DIR/UDC" 2>/dev/null || true
    rm "$GADGET_DIR/configs/c.1/accessory.acc0" 2>/dev/null || true
    rmdir "$GADGET_DIR/configs/c.1/strings/0x409" 2>/dev/null || true
    rmdir "$GADGET_DIR/configs/c.1" 2>/dev/null || true
    rmdir "$GADGET_DIR/functions/accessory.acc0" 2>/dev/null || true
    rmdir "$GADGET_DIR/strings/0x409" 2>/dev/null || true
    rmdir "$GADGET_DIR" 2>/dev/null || true
fi

# --- FASE 2: Creación del Gadget ---
echo "Creando estructura g_aa..."
mkdir -p "$GADGET_DIR"
cd "$GADGET_DIR"

# IDs Oficiales para Accesorio
# VID Google: 0x18D1
# PID Accesorio: 0x2D00 (o 0x2D01 si activas ADB también)
echo "0x18D1" > idVendor
echo "0x2D01" > idProduct
echo "0x0200" > bcdUSB
echo "0xEF" > bDeviceClass
echo "0x02" > bDeviceSubClass
echo "0x01" > bDeviceProtocol

# Metadatos (Strings)
mkdir -p strings/0x409
echo "0123456789" > strings/0x409/serialnumber
echo "Arduino" > strings/0x409/manufacturer
echo "Wireless Dongle" > strings/0x409/product

# --- FASE 3: Configuración de la Función Accesorio ---
# AQUÍ ESTÁ EL CAMBIO CLAVE: Usamos 'accessory', no 'ffs'
mkdir -p functions/accessory.acc0

# Crear Configuración
mkdir -p configs/c.1
mkdir -p configs/c.1/strings/0x409
echo "Android Auto Config" > configs/c.1/strings/0x409/configuration
echo 500 > configs/c.1/MaxPower

# Enlazar la función al config
ln -s functions/accessory.acc0 configs/c.1/

# --- FASE 4: Activación ---
# Esperar un momento para asegurar estabilidad
sleep 0.5

# Activar en el controlador USB
echo "Activando en $UDC_NAME..."
echo "$UDC_NAME" > UDC

# Dar permisos al dispositivo creado (IMPORTANTE para que aawgd lo lea)
# El driver crea /dev/usb_accessory
sleep 1
if [ -c /dev/usb_accessory ]; then
    chmod 666 /dev/usb_accessory
    echo "Dispositivo /dev/usb_accessory creado correctamente."
else
    echo "ADVERTENCIA: /dev/usb_accessory no apareció."
fi

echo "¡Gadget USB Configurado!"