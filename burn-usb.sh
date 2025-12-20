#!/bin/bash
set -e

IMAGE=build/main_floppy.img

if [ $# -ne 1 ]; then
	echo "Usage: $0 <device node>"
	echo "Example: $0 /dev/sdc"
	echo
	echo "Available block devices:"
	lsblk
	exit 1
fi

DEVICE="$1"

if [ ! -b "$DEVICE" ]; then
	echo "[x] Error: $DEVICE is not a valid block device!"
	echo
	echo "Available block devices:"
	lsblk
	exit 1
fi

if [ -f "IMAGE" ]; then
	echo "[x] Error: The main image ($IMAGE) was not found!"
	echo "           Please recompile the OS or acquire a copy of the image."
	exit 1
fi

if [ "$EUID" -ne 0 ]; then
	echo "Please run as root (e.g. with sudo)."
	exit 1
fi

echo "[!] WARNING: This will overwrite $DEVICE with $IMAGE."
echo "             ALL DATA on the device will be lost."
lsblk "$DEVICE"
echo
read -p "The action cannot be undone, are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
	echo "Aborted."
	exit 2
fi

TRANSPORT=$(lsblk -ndo TRAN "$DEVICE")

if [ "$TRANSPORT" != "usb" ]; then
	echo
	echo "[!] WARNING: $DEVICE is not a USB device (TRAN=$TRANSPORT)!"
	echo
	read -p "Please be absolutely sure about this action (CONFIRM/no): " confirm

	if [ "$confirm" != "CONFIRM" ]; then
		echo "Aborted."
		exit 2
	fi
	echo
	echo "[*] Starting real write on non-USB device in 5 seconds."
	echo "    Last chance to cancel with 'Ctrl' + 'C'."
	sleep 5s
fi

echo
sudo umount ${DEVICE}* 2>/dev/null || true
sleep 1s
echo "[*] Writing $IMAGE to $DEVICE..."
sudo dd if="$IMAGE" of="$DEVICE" bs=512 conv=fsync status=progress
echo
echo "[*] Done, safely remove the USB device."
