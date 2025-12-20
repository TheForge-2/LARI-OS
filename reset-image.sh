#!/bin/bash

IMAGE=build/main_floppy.img
COPY=build/copy_floppy.img

echo "[!] WARNING: The copy image ($COPY) will be reset to match $IMAGE, all modifications will be lost."
echo "             If the main image was also modified, you will need to recompile the program (see instructions.txt)."
echo
read -p "Do you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
	echo "Aborted."
	exit 2
fi

echo
if [ -f "IMAGE" ]; then
	echo "[x] Error: The main image ($IMAGE) was not found!"
	echo "           Please recompile the OS or acquire a copy of the image."
	exit 1
fi

echo "[*] Restoring the copy image..."
if [ -f "$COPY" ]; then
	rm "$COPY"
fi

cp "$IMAGE" "$COPY"
echo
echo "[*] Done."
