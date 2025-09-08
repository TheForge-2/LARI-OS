; Copyright © 2024-2025 TheForge-2
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LINCENSE.txt' in the project root for full terms.




; Developer's notes:
; - revise comments and structure;
; - currently nothing.




; LEGACY BOOT INFORMATION:

; The bootloader's job is to load the kernel, a shell or another binary into memory.

; The BIOS loads the first sector (512 bytes) of MBR-formatted disks into memory, at address 0x07C00.
; The bootloader therefore needs to be located at the first sector of the disk:
; - The MBR (Master Boot Record) for hard drives and other MBR-formatted drives,
; - The VBR (Volume Boot Record) for floppy disks, as partitions don't exist on them.

; A bootloader should include:
; - Headers for the used filesystem and for disk geometry,
; - Code and functions to do its duties,
; - Boot signature (0x55AA) at the last two bytes, compulsory to indicate a valid bootable MBR/VBR.

; For retrocompatibility reasons, the CPU starts in 16-bit real mode, with 20-bit segment:offset addressing scheme.
; This limits the memory access to a maximum of 0x100000 bytes, exactly 1MiB or 1024KiB, called the low memory.
; Being in real mode though gives the advantage of being able to use BIOS functions, called via the INT instruction.
; This avoids needing to write an I/O driver and allows to access basic functions to interact with the hardware.

; Once everything is set up, the bootloader (or some other real mode code) could switch to protected mode.
; Protected mode allows executing 32-bit instructions and accessing high memory, from 0x00100000 and above.
; The disadvantage is that access to BIOS functions is lost and any interrupt will cause a triple fault.
; This makes the creation of custom drivers and direct hardware programming necessary.

; END OF LEGACY BOOT INFORMATION.




; BOOTLOADER INFORMATION:

; The bootloader should include basic functions for its needs.
; Those are the functions included in this bootloader:
; - puts:					prints a string of ASCII characters to the screen in TTY mode;
; - wait_key_and_reboot:	reboots the system at a keypress;
; - disk_read:				reads continuous sectors from a disk to memory given their LBA;
; - disk_reset:				resets the disk to retry a failed read operation;
; - floppy_error:			handles a disk error;
; - lba_to_chs:				converts an LBA address into a CHS one.

; The maximum program size is 512 bytes, headers and signature included.
; It starts at 0x0000 of the VBR, finishes at 0x01FF (last byte of the sector).
; The VBR CHS address is Cylinder 0, Head 0, Sector 1.

; Defined and standardised values or sections of the code are preceeded by:
; Offset from the beginning of the file (in hexadecimal), size of that section (in decimal).

; END OF BOOTLOADER'S INFORMATION.




; DISK INFORMATION:

; Sector:		where data is stored.
; Track:		full circlular portion of a disk, sectors in sequence.
; Cylinder:		vertical stack of the same tracks on multiple surfaces.
; Platter:		physical disk.
; Surface:		side of a platter.
; Head:			read-write physical head.

; For 1.44MiB floppy disks, the most common disk geometry values are:
; - 1 platter per media,
; - 2 surfaces or heads per platter,
; - 80 cylinders per media,
; - 80 tracks per surface,
; - 18 sectors per track,
; - 36 sectors per cylinder,
; - 1440 sectors per head,
; - 2880 sectors per platter,
; - 512 bytes per sector.

; END OF DISK INFORMATION.




; ABBREVIATIONS:

; General terms:
; - BIOS:	Basic Input Output System,
; - CPU:	Central Processing Unit,
; - OS:		Operating System,
; - MBR:	Master Boot Record,
; - VBR:	Volume Boot Record,
; - OEM:	Original Equipment Manufacturer,
; - INT: 	Interrupt,
; - TTY:	TeleTYpe.

; Disk related:
; - BPB:	BIOS Parameter Block,
; - EBPB:	Extended BIOS Parameter Block,
; - EBR:	Extended Boot Record,
; - FAT:	File Allocation Table,
; - RD:		Root Directory,
; - LBA: 	Logical Block Addressing,
; - CHS:	Cylinder Head Sector.

; Memory and registers related:
; - Addr:	Address,
; - Seg:	Segment,
; - Offs:	Offset,
; - xLb:	"x lower bits from start",
; - xHb:	"x higher bits from half".

; END OF ABBREVIATIONS.




; DIRECTIVES:

; Directives to the assembler, not actual code.
org 0x7C00 ; Define where the code is expected to be loaded in memory. Used for jumps and calls.
bits 16 ; Emit 16 bit code.

; Deifne macros for semplifying some things.
%define ENDL 0x0D, 0x0A ; Endline macro, a carriage return (CR) and a line feed (LF).

; Define two values for the address of 'shell.bin', so they don't take up any space in the program.
SHELL_SEG equ 0x1000 ; Segment of the shell.
SHELL_OFFS equ 0x0000 ; Offset of the shell.

; END OF DIRECTIVES.






; ================================================================================
; ================================================================================






; NECESSARY HEADERS:


; BIOS PARAMETER BLOCK:

; BPB (BIOS Parameter Block), contains the necessary headers for the FAT12 filesystem.
; 0x00, 36.

; To skip over the BPB and EBPB. EB 3C 90. Jump at least 0x3C forward, to 0x3E.
; Done to avoid executing non-code data.
; 0x00, 3.
jmp short start
nop ; No-opernad intruction, might be needed for alligned by old BIOSes.

; OEM identifier, Not necessary, but MSWIN4.1 is recommended.
; 0x03, 8.
bpb_oem: db "MSWIN4.1"

; Number of bytes per sector.
; NOTE!: It is hardcoded throughout the program.
; 0x0B, 2.
bpb_bytes_per_sector: dw 512

; Number of sectors per cluster. A file occupies an entire cluster.
; NOTE!: It is hardcoded throughout the program.
; 0x0D, 1.
bpb_sectors_per_cluster: db 1

; Number of reserved sectors, MBR included.
; NOTE!: It is hardcoded throughout the program.
; 0x0E, 2.
bpb_reserved_sectors: dw 1

; Number of FATs (File Allocation Tables) on the media.
; FATs contain information about the stored data.
; NOTE!: It is hardcoded throughout the program.
; 0x10, 1.
bpb_fat_count: db 2

; Number of root directory entries. 224 or 0x0E0 for FAT12.
; 0x11, 2.
bpb_dir_entries_count: dw 224

; Total number of sectors on the logical volume. 18*80*2*512B = 1.44MiB.
; 0x13, 2.
bpb_total_sectors: dw 2880

; Media descriptor type. 0xF0 for standard 1.44MB floppy disk, described at the beginning.
; 0x15, 1.
bpb_media_descriptor_type: db 0xF0

; Number of sectors per FAT (dimension of the allocation table).
; 0x16, 2.
bpb_sectors_per_fat: dw 9

; Number of sectors per track (physical full circle on a disk).
; 0x18, 2.
bpb_sectors_per_track: dw 18

; Number of total heads.
; 0x1A, 2.
bpb_heads: dw 2

; Number of hidden sectors, like MBR or MRP.
; 0x1C, 4.
bpb_hidden_sectors: dd 0

; Large sector count. To be set if there are more than 65535
; 0x20, 4.
bpb_large_sector_count: dd 0

; END OF BIOS PARAMETER BLOCK.


; ================================================================================


; EXTENDED BIOS PARAMETER BLOCK:

; EBPB (Extended BIOS Parameter Block), also known as EBR (Extended Boot Record), necessary headers for FAT12.
; 0x024, 26.

; Drive number, value returned by BIOS interrupt 0x13.
; 0x00 and 0x01 for floppy 1 and 2, 0x80 and 0x80 for HDD 1 and 2.
; 0x024, 1.
ebr_drive_number: db 0

; Flags for Windows NT, otherwise reserved.
; 0x025, 1.
ebr_nt_flags_reserved: db 0

; Signature of filesystem. Either 0x29 (most used) or 0x28.
; 0x026, 1.
ebr_signature: db 0x29

; VolumeID "serial" number, used to track volume between computers. Ignorable.
; 0x027, 4.
ebr_volume_id: dd 0x27182818

; Volume label string, padded with spaces.
; 0x02B, 11.
ebr_volume_label: db "LARI-OS mbr"

; System identifier string (i.e. "FAT12", "FAT16"), padded with spaces. Not to trust.
; 0x036, 8.
ebr_system_id: db "FAT12   "

; END OF EXTENDED BIOS PARAMETER BLOCK.

; END OF NECESSARY HEADERS.






; ================================================================================
; ================================================================================






; BOOTLOADER'S CODE:

; Beginning of the code for the bootloader.
; 0x03E, 448 (if less, to be filled with 0x00).


; ENTRY CODE:

; Entry point of the bootloader, main code section.
start:

	cli ; Clear the interrupt flag, to disable interrupts, so the process doesn't get interrupted.

	; We can't write directly to segement registers, so we need to copy the values from another register.
	; Set up to 0x0000 segment registers that will be used.
	xor ax, ax ; Clear AX.
	mov ds, ax ; Set up the data segment register, used to reference data already in memory.
	mov es, ax ; Set up the extra segment register, usually used for file operations.

	; Set up the stack (grows downwards) at the start of the OS, not to overwrite the bootloader and to give it a finite space.
	mov ss, ax ; Set up the stack segment register.
	mov sp, 0x7C00 ; Set up the stack pointer, which decreases as data pushed.

	; Some BIOSes load the MBR at 07C0:0000 instead of 0000:7C00.
	; Even though it resolves to the same address, the bootloader expects the latter.
	push es ; Contains 0x0000, will be popped to CS.
	push word .aligned ; Replaced at assembly time with the offset of .aligned (from the org at the beginning).
	retf ; Pop .after to IP and ES to CS using a far return.

; After the realignment, CS will be 0x0000 and IP 0x7Cxx (whatever the offset of .aligned is).
.aligned:

	; For safety, overwrite the drive number with the one given by the BIOS in DL.
	mov [ebr_drive_number], dl ; In this case it should be 0x00, for floppy 1.

	; For safety, reset the disk's hardware so that it doesn't do misaligned operations.
	call disk_reset  ; Call the disk_reset function.

	; Some BIOSes report different disk geometry, so it is best to use the values from INT 0x13,8.
	push es ; Will be returned by INT 0x13 for the Disk Base Table, best to save.
	mov ah, 0x08 ; Set up AH for INT 0x13.
	int 0x13 ; Call Diskette BIOS Services.
	jc floppy_error ; Give an error if the operation fails.

	; Overwirte the disk geometry values.
	pop es ; Restore ES.
	and cx, 0x3F ; Clear the top 10 bits of CX, as we don't care about the number of cylinders.
	mov [bpb_sectors_per_track], cx ; Overwrite the number of sectors per track.
	inc dh ; The number of heads is 0-based, so it needs to be incremented by one.
	; Overwrite the number of heads.
	; NOTE!: It only overwrites the low byte, since floppies don't use the high byte.
	mov [bpb_heads], dh

; END OF ENTRY CODE.




; ========================================
; ========================================




; FAT AND ROOT DIRECTORY LOAD:

; Read and load the file allocation table and the root directory into memory, one after the other.

; NOTE!: This section of code is specifically designed to work with FAT12, as many values are hardcoded.
; 		 The root directory needs not to have many entries, otherwise it might overflow the segment.

; Load the file allocation table into memory, after the bootloader.
fat_read:

	; Set up the registers for the disk_read function.
	mov ax, 1 ; AX contains the number of reserved sectors.
			  ; NOTE!: reserved_sectors is hardcoded to 1.
	mov dh, byte [bpb_sectors_per_fat] ; DH contains the sector size of the FAT.
	mov dl, [ebr_drive_number] ; DL contains the drive number.
	mov bx, 0x7E00 ; BX points to the next free byte in memory (segment is 0x0000).
				   ; NOTE!: This code is not intended for use with second stage bootloaders.
				   ;		The FAT will be collocated right after the bootloader.
	call disk_read ; Call the disk_read function.

; Calculate the lenght in sectors of the root directory (dir_entries_count * 32 / bytes_per_sector).
root_dir_sectors:

	; Get the number of full sectors the root directory takes up.
	xor dx, dx ; Clear DX.
	mov ax, [bpb_dir_entries_count] ; AX contains the total number of entries in the root directory.
	mov bx, 16
	div bx ; The same as doing * 32 / 512.
		   ; NOTE!: bytes_per_sector is hardocoded to 512.

	; In case the number isn't whole, increment it by 1.
	test dx, dx ; Check if there is a remainder?
	jz root_dir_read ; If not, jump directly.
	inc ax ; Else, increment the number of sectors by one not to truuncate the root directory.

; Load the root directory into memory, after the FAT.
root_dir_read:

	; Set up the registers for the disk_read function.
	mov dh, al ; Move the sector size into DH.
	mov ax, [bpb_sectors_per_fat] ; Load the number of sectors per FAT in AX.
	shl ax, 1 ; Multiply AX by 2, the fat count.
			  ; NOTE!: fat_count is hardocoded to 2.
	inc ax ; Increment AX, adding the number of reserved sectors, obtaining the root directory LBA.
		   ; NOTE!: reserved_sectors is hardcoded to 1.
	mov dl, [ebr_drive_number] ; Load the drive number in DL.
	mov bx, [free_offs] ; BX points to the next free byte in memory (segment is 0x0000).
	mov [addr_root_dir], bx ; Save the address of the root directory for later use.
	call disk_read ; Call the disk_read function.

; Obtain the data region LBA and save it for later use.
lba_data:

	add al, dh ; Add the root directory sector size in DX to its LBA in AX, obtaining the data region LBA.
	mov [lba_data_region], ax ; Save the data region LBA for later use.

; END OF FAT AND ROOT DIRECTORY LOAD.




; ========================================
; ========================================




; SHELL LOAD:

; Search for the shell, load it from the data region into memory and pass control to it.
; The source disk should only be this drive.

; NOTE!!: The file must be less than 64KiB and, for integrity, it should never overflow the segment.
;		 Segments are not incremented automatically and the offset loops back to 0, thus overwriting the read data.

; Note: free_offs will lose meaning in case the selected segment is not 0x0000.
;		In that case, free_offs will lose meaning after the load operation is complete.
;		The user can still preserve its meaning by keeping track of the segments separatly.

; Set up the registers and call the needed functions to start the shell loading process.
.shell_load:

	; Set up the registers to search the shell.
	xor bx, bx ; Clear BX.
	mov si, shell_filename ; SI contains the offset (DS is 0x0000) to the shell filename string, in the 8.3 standard.
	mov di, [addr_root_dir] ; DI contains the address of the root directory.
	
; Compare the filename with all the root directory entries to check for its existance.
.shell_search:

	; Compare the filename and a root directory entry.
	mov cx, 11 ; Set up a counter for the 11 bytes of the FAT12 filename, decreased automatically by REPE.
	push si ; Save the pointer to the filename string for the next comparisons.
	push di ; Save the pointer to the first character of the directory entry for the next comparisons.
	cld ; Clear the direction flag, assuring that SI and DI are incremented.
	repe cmpsb ; Compare the bytes pointed at by SI and DI, set the flags accordingly and increment the pointer.
			   ; Repeat the comparison until the 2 bytes are not equal or CX is 0.
			   ; The zero flag will only stay set if the two strings are all equal.
	pop di ; Restore the pointer to the filename entry in the root directory.
	pop si ; Restore the pointer to the filename string at the first byte.
	je .shell_found ; If all the values in the strings are equal, we found the file.

	; Check if all entries where compared: if not we continue the search.
	add di, 32 ; Go to the next entry filename.
	inc bx ; Increment BX, a counter for the number of entries checked.
	cmp bx, [bpb_dir_entries_count] ; Compare BX to the total number of entries.
	jb .shell_search ; If the file wasn't found and not all entries are checked, we proceed with the next entry.
					 ; If all entries were checked, we continue directly to handle the missing shell.

; If the shell wasn't found, we print an error message and start a reboot sequence.
.shell_not_found:

	; Move the string address to SI and call the puts function.
	mov si, msg_shell_not_found
	call puts 

	; Start a reboot sequence.
	jmp wait_key_and_reboot

; If the shell was found, we start loading it in memory, cluster by cluster.
.shell_found:

	; Identify the first cluster from the data in the directory entry.
	mov ax, [di + 26] ; Go to the low 16 bits of the entries first cluster (for FAT12 only the low 16 bits are used).
	mov [current_cluster], ax ; Save the current cluster value for later use.

	; Set up the registers for the memory location where to load the shell.
	mov bx, SHELL_SEG
	mov es, bx ; ES contains the memory segment where to load the shell.
	mov word [free_offs], SHELL_OFFS ; free_offs is set to the memory offset where to load the shell.
									 ; free_offs will be incremented automatically by disk_read.

; Loop until all clusters are read, following the FAT chain.
.fat_chain:

	; Calculate the LBA of the sector/s of the current cluster.
	; LBA = lba_data_region + ((current_cluster - 2) * sectors_per_cluster)
	sub ax, 2
	add ax, [lba_data_region] ; AX contains the LBA of the cluster.
							  ; NOTE!: sectors_per_cluster is hardcoded to 1.

	; Set up the registers for the disk_read function.
	mov dl, [ebr_drive_number]
	mov dh, 1 ; DH contains the number of sectors per cluster, so how many sectors to read.
			  ; NOTE!: sectors_per_cluster is hardcoded to 1.
	mov bx, [free_offs] ; BX contains the offset of the next free byte in memory.
	call disk_read ; Call the disk_read function.	

	; Calculate the next byte to look at in the FAT table.
	; index = current_cluster * 3 / 2
	mov ax, [current_cluster] ; Restore the current cluster value.
	mov bx, 3
	mul bx
	mov bx, 2
	div bx ; Perform the division instead of SHR AX, 1 so that DX contains the remainder.

	; Load the word in AX and check if the entry is even or odd.
	mov si, 0x7E00 ; The source index now points to the FAT in memory.
				   ; NOTE!: The FAT address is hardcoded to 0x7E00.
	add si, ax ; Add the FAT address to the offset of the byte to get its address.
	mov ax, word [si] ; Read the byte and the next one to AX.
	or dx, dx ; Check if there was a remainder?
	jz .even ; If not, then the entry was even.

; Decode the value for an odd entry: remove the last 4 bits and divide by 16.
.odd:

	shr ax, 4 ; It can be all done with one instruction.
	jmp .end_check ; Jump to the final check.

; Decode the value for an even entry: remove the first 4 bits.
.even:

	and ax, 0x0FFF ; Set the first 4 bits to 0.

; Check whether to continue following the chain or stop.
.end_check:

	cmp ax, 0x0FF8 ; If the value is 0x0FF8 or larger, the file is totally read.
				   ; It doesn't check for bad clusters (0x0FF7).
	mov [current_cluster], ax ; Save the decoded value for later use (in case we continue in the chain).
	jb .fat_chain ; If the file wasn't over, we go back to reading the chain
				  ; If the file was over, we continue directly to then pass the control to the shell.

; After the shell was all read, we pass some important values via the stack and adjust the segment registers.
; Then we finally jump to the newloaded code.
.shell_init:

	; Move the string address to SI and call the puts function.
	mov si, msg_loading_shell
	call puts

	; Pass via the stack some important values for reading the disk, so they don't need to be computed again.
	push word [lba_data_region] ; Pass the LBA of the data region.
	push 0x7E00 ; Pass the memory offset (segment is 0x0000) of the FAT.
				; NOTE!: The FAT address is hardcoded to 0x7E00.
	push word [addr_root_dir] ; Pass the memory offset (segment is 0x0000) of the root directory.

	; Adjust the segment registers for the new code segment.
	mov ax, SHELL_SEG
	mov ds, ax ; Set up the data segment register.
	mov es, ax ; Set up the extra segment register.

	; Finally jump to the shell code, modifying CS and IP.
	jmp SHELL_SEG:SHELL_OFFS

; END OF SHELL LOAD.




; ========================================
; ========================================




; BOOTLOADER'S FUNCTIONS:


; PUTS:

; Print a string contained at a spacific address.

; Inputs:
; - SI = memory offset where the string is (actually DS:SI, but DS should be 0).

; Outputs:
; All general purpose registers and segment registers are preserved.

puts:

	pusha ; Save all the registers (more byte efficient).
	cld ; Clear the direction flag, so that SI gets incremented.

	; Loop for printing characters.
.loop:

	lodsb ; Loads character at DS:SI into AL.
	or al, al ; Check if AL is NULL?
	jz .done ; If NULL, then escape the loop.

	mov ah, 0x0E ; Service for TTY (TeleTYpe) Mode.
	xor bx, bx ; Page number for text modes.
	int 0x10 ; Call Video BIOS Services.
	jmp .loop ; Jump back to the beginning of the loop.

; Restore all the registers (more byte efficient).
.done:

	popa
	ret

; END OF PUTS.




; ========================================




; WAIT_KEY_AND_REBOOT:

; In case of an error or boot failure, it waits for a key press and reboots the system.
wait_key_and_reboot:

	sti ; Set the interrupt flag, enabling interrupts from the keyboard.
	mov ah, 0 ; Set up AH for Wait for Keypress and Read Character.
	int 0x16 ; Call Keyboard BIOS Services.

	jmp 0xFFFF:0x0000 ; Jump to were the BIOS reset vector is located. This should reboot the system.
					  ; This jump will only be executed after a keypress is detected.

; END OF WAIT_KEY_AND_REBOOT.




; ========================================




; LBA AND CHS EXPLANATION:

; LBA (Logical Block Addressing) is a logical way of addressing sectors.
; CHS (Cylinder-Head-Sector) is a "physical" way of doing so: it takes into account the geometry of the disk.
; LBA to CHS conversion is needed when working with legacy booting.

; To go from CHS to LBA knowing 5 values is needed:
; - Cylinder of the media,
; - Head of the cylinder (the surface the track is located on),
; - Sector of the track,
; - Heads per cylinder,
; - Sectors per track.
; Formula for CHS to LBA conversion:
; LBA = (Cylinder * sectors_per_track * heads_per_cylinder) + (Head*sector_per_track) + Sector

; To go from LBA to CHS knowing 3 values is needed:
; - LBA value of the sector,
; - Heads per cylinder,
; - Sectors per track.
; Formula for LBA to CHS conversion:
; Cylinder = LBA / (sectors_per_track * heads_per_cylinder)
; Head = (LBA / sectors_per_track) % heads_per_cylinder
; Sector = (LBA % sectors_per_track) + 1
; CHS = (Cylinder, Head, Sector)

; END OF LBA AND CHS EXPLANATION.




; ========================================




; DISK_READ:

; Read sectors from a disk to memory, at the specified address.

; At the same time it updates the memory offset of the next free byte.
; If the passed adderess is not the same as the address of the next free byte, that free memory region will get lost.
; In that case, it is recommended to save next_offs.

; NOTE!: The function doesn't automatically update the memory segment, as it should only be used by the bootloader.
;		 If the loaded data overflows the segment, it is the user's duty to handle it.

; NOTE!: The function might never return if it encounters a disk error when calling INT 0x10.

; Inputs:
; - AX = LBA address;
; - ES:BX = memory address where to store the read data;
; - DH = number of sectors to read (maximum of 128);
; - DL = drive number.

; Outputs:
; All general purpose registers and segment registers are preserved.

disk_read:

	pusha ; Save all the registers.
	call lba_to_chs ; Call the function to convert LBA in CHS. AX is passed.

	mov ah, 0x02 ; Set up AH for Read Disk Sectors.
	mov di, 3 ; Set up a counter to retry the read operation.

	; Floppy disks can be unreliable with the reading operations.
	; It is recommended to try at least 3 times each read operation.
	; If the operation succeedes before all the tries are made, we jump out of the loop.
	.retry:

		pusha ; Push all registers on the stack, preventive measure.
		stc ; STC (Set Carry Flag) sets the carry flag (CF=1), preventive measure (some BIOSes don't set it).
		int 0x13 ; Call Diskette BIOS Services.
		popa ; Pop all the registers from the stack.

		jnc .next_offs ; Jump to .next_addr if CF is cleared (the operation succeeded, see BIOS INT Table).
		call disk_reset ; Function to reset the drive to attempt another disk operation.
		dec di ; Decrements the counter.
		test di, di ; DI is 0?
		jnz .retry ; Jump back to retry again.

	; If 3 tries were made and the read operation still didn't succeed, then we enter the fail section.
	.fail:

		jmp floppy_error

	; If the read operation succeeded, we calculate the address of the next available byte in memory.
	.next_offs:

		; Calculate how many bytes where occupied in memory.
		; AL is restored after the INT, but if less sectors are read the CF is automatically set.
		shl ax, 9 ; AH doesn't need to be cleared, as we are shifting left more than 7 places.
				  ; NOTE!: bytes_per_sector is hardcoded to 512.
		add bx, ax ; Calculate the offset of the next free byte.

		; NOTE!: We don't account for overflows, as the root directory and FAT are not enough to fully fill the segment.
		; This cannot be said FAT16 and FAT32.
		mov [free_offs], bx ; Save the new adjusted offset.

	.done:

		popa ; Restore all the registers saved at the beginning of the function.
		ret

; END OF DISK_READ.




; ========================================




; DISK_RESET:

; Reset the disk C, H and S to attempt another disk operation.
disk_reset:

	pusha ; Push all registers on the stack, preventive measure.
	mov ah, 0 ; Set up AH for Reset Disk System.
	stc	; STC (Set Carry Flag) sets the carry flag (CF=1), preventive measure (some BIOSes don't set it).
	int 0x13 ; Call Diskette BIOS Services.
	jc floppy_error ; If the disk can't be reset, the disk operations automatically fail.
					; It disregards how many retries were left in DI.

	popa ; Pop all registers from the stack.
	ret ; Return to the .retry section in case the disk did reset.

; END OF DISK_RESET.




; ========================================




; FLOPPY_ERROR:

; In case INT 0x13,2 fails 3 times at reading from the floppy or the disk can't be reset, we end up here.
; Print an error message and halt the CPU.
floppy_error:

	; Move the string address to SI and call the puts function.
	mov si, msg_read_error
	call puts

	; Start a reboot sequence.
	jmp wait_key_and_reboot

; END OF FLOPPY_ERROR.




; ========================================




; LBA_TO_CHS:

; Convert an LBA address to a CHS one.

; Inputs:
; AX: LBA address.

; Outputs (already set up for INT 0x13):
; - CX (bits 6-15) = cylinder (bits 6 and 7 are the highest bits, lowest is 7);
; - CX (bits 0-5) = sector;
; - DH = head;
; - DL = drive number.

lba_to_chs:

	; Save the registers that will be modified.
	push dx

	; Calculate the Sector:
	xor dx, dx ; Clear DX, AX contains LBA.
	div word [bpb_sectors_per_track] ; AX = LBA / sectors_per_track.
									 ; DX = LBA % sectors_per_track.
	inc dx ; DX = (LBA % sectors_per_track) + 1 = Sector.
	mov cx, dx ; Store the value in CX.
	; CX = [#-#-#-#-#-#-#-#-#-#-5-4-3-2-1-0]
	;						   |   6b S    |

	; Calculate the Cylinder and the Head:
	xor dx, dx ; Clear DX, AX contains LBA/sectors_per_track.
	div word [bpb_heads] ; AX = LBA / (sectors_per_track * heads_per_cylinder) = Cylinder.
						 ; DX = (LBA / sectors_per_track) % heads_per_cylinder = Head.
	; AX = [#-#-#-#-#-#-9-8-7-6-5-4-3-2-1-0]	DX = [#-#-#-#-#-#-#-#-7-6-5-4-3-2-1-0]
	;				   |       10b C       |						 |     8b H      |

	mov dh, dl ; The Head number was in DL, now moved 8 bits up.
	; DX = [7-6-5-4-3-2-1-0-7-6-5-4-3-2-1-0]
	;	   |     8b H      |     8b H      |

	mov ch, al ; CH = Cylinder (lower 8 bits).
	; CX = [7-6-5-4-3-2-1-0-#-#-5-4-3-2-1-0]
	;	   |     8Lb C     |   |   6b S    |

	shl ah, 6 ; Move the 2Hb of C in AH 6 bits to the left (they become the first 2 bits of AX).
	; AX = [9-8-#-#-#-#-#-#-7-6-5-4-3-2-1-0]
	;	   | ^ |           |     8Lb C     |
	; 	  [2Hb C]

	or cl, ah ; OR the 2Hb of C (shifted to the left by 6) to the content in CL. A sort of insertion.
	;					   [9-8-#-#-#-#-#-#]
	;						V V V V V V V V  (V for OR)
	; CX = [7-6-5-4-3-2-1-0-#-#-5-4-3-2-1-0] ORs the bits: those marked with # should be 0.
	;	   |     8Lb C     |   |   6b S    | Since the two value fit perfectly, each operation will OR a 0 and a 0 or a 1.
	; CX = [7-6-5-4-3-2-1-0-9-8-5-4-3-2-1-0] This preserves the highest value of the two, thus inserting 2Hb C into CL.
	;	   |     8Lb C     | ^ |   6b S    |
	;					  [2Hb C]

	; Restore the modified registers and return.
	pop ax
	mov dl, al ; Need to move to DL only (no POP DL) since DH is set up for INT 0x13.
	shr ax, 8
	ret

; END OF LBA_TO_CHS.

; END OF BOOTLOADER'S FUNCTIONS.

; END OF BOOTLOADER'S CODE.






; ================================================================================
; ================================================================================






; TEXT MESSAGES:

; In this section we define strings for messages.
; ENDL is a macro, 0 is the NULL terminator.

msg_read_error: db "Disk read failed!", ENDL, 0
msg_shell_not_found: db "SHELL.BIN not found!", ENDL, 0
msg_loading_shell: db "Loading SHELL...", ENDL, 0

; END OF TEXT MESSAGES.




; ================================================================================




; IMPORTANT VALUES:

; In this section we reserve space for important variables and addresses.

addr_root_dir: dw 0 ; Reserve 16 bits for the address of the root directory (only the offset, temporary).
lba_data_region: dw 0 ; Reserve 16 bits for the LBA of the data region.

; Reserve 16 bits for the offset of the next free byte in memory.
; This value is only used by the bootloader, so the segment is not saved (we are not supposed to exceed it in FAT12).
free_offs: dw 0x7E00

; Reserve 16 bits for the current cluster value, used while looking in the FAT chain.
current_cluster: dw 0

; Define a string containing the "shell.bin" filename in the 8.3 standard.
shell_filename: db "SHELL   BIN"

; END OF IMPORTANT VALUES.




; ================================================================================




; REMAINING BYTES:

; Boot-sector size is 512 bytes. $ is current position. $$ is initial offset. The last two bytes are reserved.
; $-$$ is the program size so far. 510-($-$$) is the remaining empty part before the reerved bytes. It is filled with 0.
; ($-$$)+1, 510-($-$$).
times 510-($-$$) db 0

; Bootable partition signature 0x55AA. Last two bytes of the MBR.
; 0x1FE, 2.
dw 0xAA55 ; Reversed since it is in little-endian.

; END OF REMAINING BYTES.






; ================================================================================
; ================================================================================






; BIOS INTERRUPTS REFERENCE TABLE (USED INTs ONLY, INCOMPLETE!):


; INT 0x10, Video BIOS Services.

; AH: 0x0E, Write Text in Teletype Mode.
; Inputs:
; - AH = Service for INT 0x10, in this case 0x0E.
; - AL = ASCII character to write.
; - BH = Page number (text modes), default 0x00.
; - BL = Foreground pixel colour (graphics modes), ignorable in non-graphics mode.
; Outputs:
; - None




; ================================================================================




; INT 0x13, Diskette BIOS Services.

; AH: 0x02, Read Disk Sectors.
; Inputs:
; - AH = Service for INT 0x13, in this case 0x02.
; - AL = Number of sectors to read (1-128 dec).
; - CH = Track/Cylinder number (0-1023 dec, see below).
; - CL = Sector number (1-17 dec, see below).
; - DH = Head number (0-15 dec).
; - DL = Drive number (0=1st_floppy, 1=2nd_floppy, 0x80=drive_0, 0x81=drive_1).
; - ES:BX = Pointer to buffer in memory, where to store read sectors.
; Outputs:
; - AH = Status of operation (0=fine, !0=error, more detailed than CF).
; - AL = Number of sectors actually read.
; - CF = Simplified status (0=successful, 1=error).
; CX = [7-6-5-4-3-2-1-0-9-8-5-4-3-2-1-0] CX bits at input.
;	   |     8Lb C     | ^ |   6b S    |
;					  [2Hb C]

; AH: 0x00, Reset Disk System,
; Inputs:
; - AH = Service for INT 0x13, in this case 0x00.
; - DL = Drive number (0=1st_floppy, 1=2nd_floppy, 0x80=drive_0, 0x81=drive_1).
; Outputs:
; - AH = Status of operation (0=fine, !0=error, more detailed than CF).
; - CF = Simplified status (0=successful, 1=error).

; END OF BIOS INTERRUPTS REFERENCE TABLE.
