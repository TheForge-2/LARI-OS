ASM=nasm
CC=gcc

.PHONY: all floppy_image shell bootloader clean always tools_fat


# Execute everything.
all: floppy_image tools_fat

# Create the floppy FAT12 image.
# The bootloader is put in the VBR, the shell and the other files in the data region.
floppy_image: build/main_floppy.img
build/main_floppy.img: bootloader shell
	dd if=/dev/zero of=build/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 -n "LARI OS" -s 1 -f 2 -r 224 -S 512 build/main_floppy.img
	dd if=build/bootloader.bin of=build/main_floppy.img conv=notrunc
	mcopy -i build/main_floppy.img build/shell.bin "::shell.bin"
	mcopy -i build/main_floppy.img data/test.txt "::test.txt"
	cp -p build/main_floppy.img build/copy_floppy.img

# Assemble the bootloader into a pure binary.
bootloader: build/bootloader.bin
build/bootloader.bin: always
	$(ASM) src/bootloader/boot.asm -f bin -o build/bootloader.bin

# Assemble the shell into a pure binary.
shell: build/shell.bin
build/shell.bin: always
	$(ASM) src/shell/shell.asm -f bin -o build/shell.bin



# Compile the FAT12 plain text reader.
tools_fat: build/tools/fat12_reader
build/tools/fat12_reader: always tools/fat/fat12_reader.c
	mkdir -p build/tools
	$(CC) -g -o build/tools/fat12_reader tools/fat/fat12_reader.c



# Create the 'build' directory if absent.
always:
	mkdir -p build

# Clear the 'build' directory.
clean:
	rm -rf build/*
