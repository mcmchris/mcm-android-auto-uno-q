# mcm-android-auto-uno-q

Despues que la UNO Q tiene el Kernel correcto sigue los pasos siguientes:

```bash
sudo apt update
sudo apt install -y build-essential cmake git pkg-config \
    libprotobuf-dev protobuf-compiler \
    libsigc++-2.0-dev \
    libglib2.0-dev libdbus-1-dev

cd ~
# Descargar código fuente versión 2.5.2
wget https://github.com/dbus-cxx/dbus-cxx/archive/refs/tags/2.5.2.tar.gz
tar -xvf 2.5.2.tar.gz
cd dbus-cxx-2.5.2

# Configurar y compilar
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_GLIB_SUPPORT=ON
make -j$(nproc)

# Instalar en el sistema
sudo make install
sudo ldconfig # Actualizar caché de librerías
```

```powershell
# Ajusta la ruta y la IP
scp -r WirelessAndroidAutoDongle/aa_wireless_dongle/package/aawg/src arduino@10.0.0.251:/home/arduino/aawg_src
```

```bash
cd ~/aawg_src

# El Makefile [cite: 2] espera encontrar dbus-cxx-2.0. 
# Si pkg-config no lo encuentra como 'dbus-cxx-2.0', quizás se instaló como 'dbus-cxx-2.5'.
# Verificamos:
pkg-config --list-all | grep dbus-cxx
```


```bash
# MODIFICA el MAKEFILE con esto:
nano Makefile

.PHONY: clean
.SECONDARY:

# CAMBIO 1: Cambia 'protobuf-lite' por 'protobuf' para evitar errores de símbolos faltantes
EXTRA_CXXFLAGS += $(shell $(PKG_CONFIG) --cflags --libs dbus-cxx-2.0 protobuf)

PROTO_FILES = $(wildcard proto/*.proto)
PROTO_HEADERS = $(PROTO_FILES:proto=pb.h)

ALL_HEADERS = $(wildcard *.h) $(PROTO_HEADERS)

aawgd: aawgd.o bluetoothHandler.o bluetoothProfiles.o bluetoothAdvertisement.o proxyHandler.o uevent.o usb.o common.o proto/WifiInfoResponse.pb.o proto/WifiStartRequest.pb.o
	# CAMBIO 2: Mueve $(EXTRA_CXXFLAGS) al FINAL de la línea
	$(CXX) $(CXXFLAGS) -o '$@' $^ $(EXTRA_CXXFLAGS)

%.o: %.cpp
%.o: %.cpp $(ALL_HEADERS)
	$(CXX) $(CXXFLAGS) $(EXTRA_CXXFLAGS) -c -o '$@' '$<'

%.pb.o: %.pb.cc %.pb.h
	$(CXX) $(CXXFLAGS) $(EXTRA_CXXFLAGS) -c -o '$@' '$<'

proto/%.pb.cc proto/%.pb.h: proto/%.proto
	cd $(<D) && $(PROTOC) --cpp_out=. $*.proto

clean:
	-rm aawgd

```

```bash
# Compilamos
make PROTOC=protoc PKG_CONFIG=pkg-config
```



--------------------------------------------------------------------------

Con Prepare_gadgets.sh:

Hay que hacer esto antes:

```bash
# 1. Asegurar que nada esté conectado al puerto
echo "" | sudo tee /sys/class/udc/4e00000.usb/UDC

# 2. Matar cualquier proceso que esté usando el driver
sudo killall aawgd
sudo fuser -k /dev/usb_accessory

# 3. Desmontar el gadget "g_accessory" (EL CULPABLE)
# Primero rompemos el enlace simbólico
sudo rm /sys/kernel/config/usb_gadget/g_accessory/configs/c.1/accessory.acc0
# Luego borramos la configuración
sudo rmdir /sys/kernel/config/usb_gadget/g_accessory/configs/c.1/strings/0x409
sudo rmdir /sys/kernel/config/usb_gadget/g_accessory/configs/c.1
# AHORA sí podemos borrar la función (aquí es donde fallaba)
sudo rmdir /sys/kernel/config/usb_gadget/g_accessory/functions/accessory.acc0
# Y finalmente el gadget
sudo rmdir /sys/kernel/config/usb_gadget/g_accessory/strings/0x409
sudo rmdir /sys/kernel/config/usb_gadget/g_accessory

# 4. Desmontar el gadget "g_default" (Por si acaso)
sudo rmdir /sys/kernel/config/usb_gadget/g_default/configs/c.1/strings/0x409
sudo rmdir /sys/kernel/config/usb_gadget/g_default/configs/c.1
sudo rmdir /sys/kernel/config/usb_gadget/g_default/strings/0x409
sudo rmdir /sys/kernel/config/usb_gadget/g_default
```