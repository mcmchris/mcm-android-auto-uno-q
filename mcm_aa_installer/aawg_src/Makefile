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