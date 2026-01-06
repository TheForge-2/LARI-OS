#!/bin/bash
set -e

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
	echo "Error: $DEVICE is not a valid block device!"
	echo
	echo "Available block devices:"
	lsblk
	exit 1
fi

if [ "$EUID" -ne 0 ]; then
	echo "Please run as root (e.g. with sudo)."
	exit 1
fi

TRANSPORT=$(lsblk -ndo TRAN "$DEVICE")

if [ "$TRANSPORT" != "usb" ]; then
	echo
	echo "[x] ERROR: $DEVICE is not a USB device (TRAN=$TRANSPORT)!"
	echo "           This tool is only for small USB drives, proceed manually."
	echo "           Aborted."
	exit 2
fi

echo "[!] WARNING: This will format $DEVICE to FAT32."
echo "             ALL DATA on the device will be lost."
echo "             A failure in the process might leave the device in an unusable state."
lsblk "$DEVICE"
echo
read -p "The action cannot be undone, are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
	echo "Aborted."
	exit 2
fi

echo
sudo umount ${DEVICE}* 2>/dev/null || true
sleep 1s
echo "[*] Removing filesystem signatures..."
sudo wipefs -a "$DEVICE"
echo
echo "[*] Creating new MBR partition table..."
sudo parted "$DEVICE" mklabel msdos
echo "[*] Creating a new partition..."
sudo parted "$DEVICE" mkpart primary fat32 1MiB 100%
echo "[*] Making FAT32 filesystem..."
sudo mkfs.vfat -F32 "${DEVICE}1"
echo
echo "[*] Done, safely remove the USB device."
