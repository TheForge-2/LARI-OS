
#!/bin/bash
set -e

ISO=build/eltorito_disc.iso

if [ $# -ne 1 ]; then
	echo "Usage: $0 <optical drive node>"
	echo "Example: $0 /dev/sr0"
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

if ! lsblk -d -n -o TYPE "$DEVICE" | grep -q "^rom$" ; then
    echo "[x] Error: $DEVICE is not an optical drive!"
    echo
    echo "Available block devices:"
    lsblk
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
	echo "Please run as root (e.g. with sudo)."
	exit 1
fi

sudo umount "$DEVICE" 2>/dev/null | true
sleep 1s

if ! wodim dev="$DEVICE" -checkdrive 2>&1 | grep -q -e "DVD-RW" -e "DVD+RW" -e "DVD-R" -e "DVD+R" -e "CD-R" -e "CD+R" ; then
    echo "[x] Error: $DEVICE does not support writing!"
    echo
    echo "Available block devices:"
    lsblk
    exit 1
fi

echo
echo "[!] WARNING: This will burn $ISO on $DEVICE."
echo "             ALL DATA on the disc will be lost."
echo "[!] WARNING: The disc will be finalized, becoming read-only permanently."
echo "             Non-rewritable media cannot be blanked, please be sure."
lsblk "$DEVICE"
echo
read -p "The action cannot be undone, are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
	echo "Aborted."
	exit 2
fi

echo
echo "[*] Starting real writing in 5 seconds."
echo "    Last chance to cancel with 'Ctrl' + 'C'."
sleep 5s
echo
echo "[*] Burning $ISO to $DEVICE..."
sudo wodim dev=$DEVICE -v -data -sao "$ISO"
echo
echo "[*] Done, the ISO image was burnt onto the disc."
