#!/bin/bash
set -e

BOOTIMG=main_floppy.img
IMAGE=build/main_floppy.img
ISO=build/eltorito_disc.iso

if [ -f "IMAGE" ]; then
	echo "[x] Error: The main image ($IMAGE) was not found!"
	echo "           Please recompile the OS or acquire a copy of the image."
	exit 1
fi

echo "[*] Generating ISO 9660 image from $IMAGE..."
genisoimage -udf -V "LARI OS" -o $ISO -b $BOOTIMG -c boot.cat $IMAGE
echo
echo "[*] Done, the ISO image has been created in the build directory."
