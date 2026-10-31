#!/bin/sh
# Build a USB NCM network gadget via configfs: this is how Linux makes a phone
# appear to the PC as a USB network card (Android's adb uses the same API).
G=/sys/kernel/config/usb_gadget/g1
mkdir -p $G && cd $G || exit 1
echo 0x18d1 > idVendor      # Google
echo 0xd001 > idProduct
mkdir -p strings/0x409
echo bullhead-learn > strings/0x409/serialnumber
echo "Linux Foundation" > strings/0x409/manufacturer
echo "Nexus 5X mainline" > strings/0x409/product
mkdir -p configs/c.1/strings/0x409 functions/ncm.usb0
echo NCM > configs/c.1/strings/0x409/configuration
ln -s functions/ncm.usb0 configs/c.1/
echo "$1" > UDC
