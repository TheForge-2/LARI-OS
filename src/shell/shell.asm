; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; Developer's notes:
; - currently nothing.




; DESCRIPTION:

; This is a 16-bit real mode shell, which allows basic input and output operations via commands:
; disk read and write, display printing, input prompting, filesystem operations.
; It runs in BIOS text mode 0x03: 80*25, 4-bit colour, 8 pages.
; Text output is currently white on black due to TTY printing.

; It is structured in a monolithic way, so that all the necessary functions are included in the code.
; This shell is executed by the bootloader, which is also expected to pass some values via the stack.
; See 'README.md' for more information.

; END OF DESCRIPTION.




; DIRECTIVES:

; Directives to the assembler, not actual code.
org 0x0000 ; The code is loaded at offset 0x0000.
bits 16 ; Emit 16-bit code.

; Define macros for simplifying some sequences.
%define ENDL 0x0D, 0x0A ; Endline macro, a carriage return (CR) and a line feed (LF).

; END OF DIRECTIVES.





; ================================================================================
; ================================================================================






; ENTRY CODE:

; Entry point of the shell, executed after the far jump from the bootloader.
entry:

	; Save useful data passed by the bootloader for FS operations.
	sti
	pop word [offs_root_dir]
	pop word [offs_fat]
	pop word [lba_data_region]

	; Set video mode to text 80*25 4-bit colour.
	mov al, 0x03
	mov ah, 0x00
	int 0x10




; ========================================
; ========================================




; ARCHITECTURE DETECTION (Intel):

; Identify early Intel architectures using Intel's algorithm.
arch_id:

	pushf ; Save FLAGS.

; Identify the 8086/8088 architecture.
.8086_8088_id:

	; On 8086/8088 bits 12-15 (IOPL, NT and MD) are all set and can't be changed.
	pushf ; Get the original FLAGS.
	pop ax ; Pop them to AX.
	mov cx, ax ; Save them in CX.
	and ax, 0x0FFF ; Clear bits 12-15.
	push ax ; Push the modified FLAGS
	popf ; Pop and try to change FLAGS.
	pushf ; Get the new FLAGS.
	pop ax ; Pop them to AX. 
	and ax, 0xF000 ; Keep only bits 12-15.
	cmp ax, 0xF000 ; Check if they are all still set.
	mov byte [cpu_type], 0 ; Set the CPU type to 8086/8088.
	je .arch_unsupported ; If yes, the processor is 8086/8088.

; Identify the 80286 architecture.
.80286_id:

	; On 80286 bits 12-15 (IOPL, NT and MD) are all cleared and can't be changed.
	or cx, 0xF000 ; Set bits 12-15.
	push cx ; Push the modified FLAGS.
	popf ; Pop and try to change FLAGS.
	pushf ; Get the new FLAGS.
	pop ax ; Pop them to AX.
	and ax, 0xF000 ; Check and keep only bits 12-15.
	mov byte [cpu_type], 2 ; Set the CPU type to 80286.
	jz .arch_id_done_80286 ; If still no bits are set, the processor is 80286.

; Identify the 80386 architecture.
.80386_id:

	; On 80386, bit 18 (AC) can't be changed.
	pushfd ; Get the original EFLAGS.
	pop eax ; Pop them to EAX.
	mov ecx, eax ; Save them to ECX.
	xor eax, 0x40000 ; Flip bit 18.
	push eax ; Push the modified EFLAGS.
	popfd ; Pop and try to change EFLAGS.
	pushfd ; Get the new EFLAGS.
	pop eax ; Pop them to EAX.
	xor eax, ecx ; Check if bit 18 was flipped.
	mov byte [cpu_type], 3 ; Set the CPU type to 80386.
	jz .arch_id_done ; If bit 18 didn't change, the processor is 80306.
	push ecx ; Push the original EFLAGS
	popfd ; Restore bit 18.

; Identify the 80486 architecture.
.80486_id:

	; On 80486, bit 21 (ID, for CPUID support) can't be changed.
	mov byte [cpu_type], 4 ; Set the CPU type to at least 80486.
	mov eax, ecx ; Get the orginal EFLAGS.
	xor eax, 0x200000 ; Flip bit 21.
	push eax ; Push the modified EFLAGS.
	popfd ; Pop and try to change EFLAGS.
	pushfd ; Get the new EFLAGS.
	pop eax ; Pop them to AX.
	xor eax, ecx ; Check if bit 21 was flipped.
	jz .arch_id_done ; If bit 21 didn't change, the processor is 80486.
	; NOTE: some late 80486 processors can still execute CPUID.

; Confirm the architecture is 80586+.
.80586_plus_id:

	; If bit 21 was changed, the processor is 80586+.
	mov byte [cpu_type], 5 ; Set the CPU type to 80586+ and end identification algorithm.

; End of early architecture identification.
.arch_id_done:

	; Clear the 32-bit registers, not to create issues.
	xor eax, eax
	xor ecx, ecx

; 80286 CPUs can't work with 32-bit registers, so the previous operations are skipped.
.arch_id_done_80286:

	popf ; Restore FLAGS.

; Complete the brand string, which will be overwritten if it can be acquired via extended CPUID.
.fill_brand_string:

	; Insert the "architecture number" (2 to 5) in the brand string.
	mov al, [cpu_type]
	add al, 48 ; Convert the number into its ASCII encoding.
	mov [cpu_brand_string + 10], al

	; Proceed to basic CPUID check.
	jmp cpuid_basic

; Handle the detection of an 8086/8088 CPU.
.arch_unsupported:

	popf ; Restore FLAGS.

	; Print the unsupported architecture error message.
	mov si, err_arch_unsupported
	cld

; Loop to print one character at a time (PUSHA/POPA are not available).
.puts_loop:

	; Load the character and check for NULL.
	lodsb
	test al, al
	jz .halt

	; Print the character using INT 0x10, 0x0E.
	mov ah, 0x0E
	xor bx, bx
	int 0x10
	jmp .puts_loop

; Halt the processor.
.halt:

	; Disable maskable interrupts and halt the processor in a loop.
	cli
	hlt
	jmp .halt

; END OF ARCHITECTURE DETECTION.




; ========================================
; ========================================




; CPU IDENTIFICATION:

; Acquire information about the CPU: features, topology, vendor and model.


; CPUID BASIC:

; Check CPUID support and acquire some information.
cpuid_basic:

	; Check the CPU architecture for CPUID support (80586+).
	cmp byte [cpu_type], 5
	jb initialise_pages

; Get the vendor ID and the maximum basic calling parameter.
.get_vendor_id:

	xor eax, eax
	cpuid ; EAX = maximum basic calling parameter;
		  ; EBX:EDX:ECX = vendor ID.
	mov [cpuid_max_basic_leaf], al
	mov [cpu_vendor_id], ebx
	mov [cpu_vendor_id + 4], edx
	mov [cpu_vendor_id + 8], ecx

; Get version information, the number of logical cores and the feature bits.
.get_processor_info:

	; Get the values via CPUID.
	mov eax, 1
	cpuid ; EAX = processor version information;
		  ; EBX = additional information;
		  ; EDX,ECX = feature bits.

	; Save them in memory.
	mov [cpu_version_info], eax
	mov [cpu_feature_bits_edx], edx
	mov [cpu_feature_bits_ecx], ecx
	mov [cpu_additional_info], ebx

; Check for extended CPUID support.
.extended_support:

	; Save the maximum calling leaf if it exists.
	mov eax, 0x80000000
	cpuid ; EAX = maximum extended calling parameter;
		  ; EBX:EDX:ECX = vendor ID (AMD and AMD clones only).
	cmp eax, 0x80000001
	jb core_enumeration ; For no extended CPUID support, keep the default.
	mov [cpuid_max_ext_leaf], al

; END OF CPUID BASIC.




; ====================
; ====================




; CORE ENUMERATION:

; Acquire information about CPU cores and topology.
core_enumeration:

	; Check if bit 28 of the EDX feature bits is set (SMT/HTT support).
	test byte [cpu_feature_bits_edx + 3], 0x10
	jnz .check_vendor_id ; If yes, continue with core enumeration.
	jmp cpuid_extended ; If no, keep the defaults.

	; Check if the bit was set falsely (it could still be, but it's more rare).
	cmp byte [cpu_additional_info + 2], 1
	je cpuid_extended ; If yes, keep the defaults and skip.

; Look for the vendor ID in the reference table to determine the preferred algorithm.
.check_vendor_id:

	; From here, use 2 threads per core as a default and overwrite if possible.
	mov byte [cpu_threads_per_core], 2

	; Set up the address of the vendor ID (SI), of the table (DI) and the counter (CX).
	mov si, cpu_vendor_id
	mov di, vendor_table
	movzx cx, byte [vendor_entries_count]

; Check all the entries until a match is found or there are no more.
.parse_table:

	; Compare all the characters until 0x00.
	mov bx, 13
	call strcmp

	; If the ZF is set, the vendor ID was mathced.
	je .match_found

	; Otherwise, go to the next table entry and loop again.
	add di, 14
	loop .parse_table

	; If the vendor is unknown, use the fallback legacy method.
	jmp .legacy_method

; If a match was found, get the preferred procedure from the table and continue accordingly.
.match_found:

	; Check byte 13 of the entry, DI still points to it.
	cmp byte [di + 13], 1
	jb .intel_method ; 0 = Intel method.
	je .amd_method ; 1 = AMD method.
	or byte [system_status], 0x04 ; Set bit 2 of the system status.
	jmp .legacy_method ; 2 = unknown or custom method.


; ====================


; INTEL METHOD:

; For Intel processors, clones and compatibles, use the dedicated CPUID leaf.
.intel_method:

	; Check if the method might be supported, false positives are detected later.
	; A leaf greater than 0x0B might be reported, but 0x0B could be unavailable, especially on previous generations.
	cmp byte [cpuid_max_basic_leaf], 0x0B
	jb .legacy_method

; Check the SMT level, which reports the number of threads per core.
.check_smt_level:

	; Try the sub-leaf 0, for the SMT level.
	mov eax, 0x0B
	xor ecx, ecx
	cpuid ; BX = number of threads per core;
		  ; CH = domain type, should be 1.

	; If the domain type is not 1 (logical processor), then the 0x0B leaf is unsupported or the values aren't valid.
	cmp ch, 1
	jne .legacy_method ; If not 1, use the fallback legacy method.

	; If valid, save the reported value.
	mov [cpu_threads_per_core], bl

; Check the core level, which reports the number of logical cores in the die.
.check_core_level:

	; Try the sub-leaf 1, for the core level.
	mov eax, 0x0B
	mov ecx, 1
	cpuid ; BX = number of logical cores across all physical cores of the die;
		  ; CH = domain type, should be 2.

	; If the domain type is not 2 (core), then the level is not present and there might be only one physical core.
	cmp ch, 2
	jne .legacy_method ; If not 2, use the legacy method with the previously reported threads per core.

	; If valid, save the reported value.
	mov [cpu_logical_cores], bx

; Check the die level (if present), which reports the number of logical cores in the package (likely).
; It's rare but can be present on some multi-die CPUs. Further domain won't be checked, even though the spec says to.
.check_die_level:

	; Try the sub-leaf 2 for the die level.
	mov eax, 0x0B
	mov ecx, 2
	cpuid ; BX = number of logical processors across all dies in the next higher domain (likely the package/socket);
		  ; CH = domain type, undefined for the die level, must not be 0.

	; If the domain type is 0 (invalid), then the level is not present.
	cmp ch, 0
	je .core_enumeration_done ; If 0, no die level is present.

	; If valid, save the reported value.
	mov [cpu_logical_cores], bx
	jmp .core_enumeration_done

; END OF INTEL METHOD.


; ====================


; AMD METHOD:

; For AMD processors, clones and compatibles, use the dedicated CPUID leaves.
.amd_method:

	; Check if the required leaf for CmpLegacy is present.
	cmp byte [cpuid_max_ext_leaf], 1
	jb .cmp_legacy_set

	; Get the bit with AMD's dedicated leaves (0x80000000+).
	mov eax, 0x80000001
	cpuid ; EDX,ECX = extended feature bits.

	; Save the extended feature bits, most of which are the same as leaf 0x01.
	mov [cpu_feature_bits_ext_edx], edx
	mov [cpu_feature_bits_ext_ecx], ecx

	; Check if bit 1 (CmpLegacy, SMT/HTT bit not valid) is set.
	test ecx, 0x00000002
	jnz .cmp_legacy_set

; If not, the value from leaf 0x01 in EBX represents the logical cores.
.cmp_legacy_clear:

	; Check if the required leaf for NC (number of physical cores) is present.
	cmp byte [cpuid_max_ext_leaf], 8
	jb .legacy_method

	mov eax, 0x80000008
	cpuid ; CL = number of physical cores minus 1.

	; Save both the number of physical and logical cores.
	mov al, [cpu_additional_info + 2]
	mov [cpu_logical_cores], al
	inc cl
	mov [cpu_physical_cores], cl

	; Get the number of threads per core and save it.
	xor edx, edx
	div cx
	mov [cpu_threads_per_core], al

	; Proceed directly.
	jmp cpuid_extended	

; If CmpLegacy is set, then the value from leaf 0x01 in EBX represents the physical cores.
.cmp_legacy_set:

	; The SMT/HTT bit is also invalid, so threads per core gets reduced to 1.
	mov byte [cpu_threads_per_core], 1
	jmp .legacy_method

; END OF AMD METHOD.


; ====================


; If the vendor wasn't matched or has an unknown custom procedure, or the other procedures failed or couldn't be completed, fallback to the legacy method.
.legacy_method:

	; Use the logical cores value from leaf 0x01 in EBX.
	mov al, [cpu_additional_info + 2]
	mov [cpu_logical_cores], al

; Executed after getting the number of threads per core and total logical core, this is in common to all procedures.
.core_enumeration_done:

	; Divide by the number of threads per core to get the physical cores.
	mov ax, [cpu_logical_cores]
	xor dx, dx
	movzx bx, byte [cpu_threads_per_core]
	div bx
	mov [cpu_physical_cores], al

	; Check if the result is 0 (could happen on emulators and VMs).
	cmp al, 0
	ja cpuid_extended ; Skip if more than 0.

	; Increment the physical core count to 1.
	inc byte [cpu_physical_cores]
	jmp cpuid_extended

; END OF CORE ENUMERATION.




; ====================
; ====================




; CPUID EXTENDED:

; Acquire some infomration via extended CPUID if possible.
cpuid_extended:

	; Check for leaves greater than 0x80000002-4 (for brand string).
	cmp byte [cpuid_max_ext_leaf], 0x04 ; Must be greater or equal, as partial support doesn't exist.
	jb .cpuid_extended_done ; Use the default if not.

	; Set up the leaf (EAX) and the destination (DI).
	mov eax, 0x80000002
	mov di, cpu_brand_string

; Get the brand string via three CPUID calls (leaves 0x80000002-4).
.get_brand_string:

	; Save EAX before calling.
	push eax
	cpuid ; EAX:EBX:ECX:EDX = a third of the brand string.

	; Insert a double-word of characters, then increment the index by 4.
	mov [di], eax
	add di, 4
	mov [di], ebx
	add di, 4
	mov [di], ecx
	add di, 4
	mov [di], edx
	add di, 4

	; Restore the leaf and increment it, the check whether to loop again.
	pop eax
	inc ax
	cmp al, 0x4
	jbe .get_brand_string

; End of the CPU information collection. 
.cpuid_extended_done:

	; Clear the 32-bit registers, not to create issues.
	xor eax, eax
	xor ebx, ebx
	xor ecx, ecx
	xor edx, edx

; END OF CPUID EXTENDED.

; END OF CPU IDENTIFICATION.




; ========================================
; ========================================




; PAGE INITIALIZATION:

; Print the initial messages to all pages.
initialise_pages:

	; Print the welcome message on page 0.
	mov si, msg_hello
	call prints

	; Save the cursor postion at page 0 and set up a counter (CX).
	push word [cursor_row]
	mov cx, 1

; Print the empty page message in all the the blank pages (1 to 7).
.fill_blank_pages:

	; Change the page by the counter.
	mov ax, cx
	call change_page

	; Set the cursor at 00,00 to start printing.
	mov word [cursor_row], 0x0000
	mov si, msg_page_empty_1
	call prints
	call printd16
	mov si, msg_page_empty_2
	call prints

	; Check if the message was printed on all pages.
	inc cx
	cmp cx, 8
	jb .fill_blank_pages

	; If yes, reset the page and the cursor position.
	mov al, 0
	call change_page
	pop word [cursor_row]

; END OF PAGE INITIALIZATION.




; ========================================
; ========================================




; MEMORY DETECTION:

; Acquire information about installed RAM and space free for use.


; LOW MEMORY DETECTION:

; Detect how many KiB of memory are usable before the EBDA.
low_memory_detect:

	; Use BIOS INT 0x12 to try to detect memory.
	clc
	int 0x12
	jc .failed

	; Exclude segments 0x1000 and partially 0x2000 (64KiB minimum), used by the IVT, BDA, stack, bootlaoder, FAT, root directory and this shell.
	push ax
	sub ax, 64 + SHELL_TOTAL_KIB ; A system with at least 64KiB of memory is assumed.
	mov [mem_free_kib], ax
	mov [mem_usable_kib], ax
	pop ax

; Check the presence of the EBDA to confirm with higher probability a standard memory configuration.
.ebda_check:

	; Get the EBDA base segment from the BDA entry.
	xor bx, bx
	push ds
	mov ds, bx
	mov cx, ds:[0x40E]

	; Restore DS and save the segment.
	pop ds
	mov [ebda_seg], cx

	; Get the base 1KiB segment and compare it to the value reported by INT 0x12.
	shr cx, 6
	cmp ax, cx
	je .ebda_present

; If they are not the same, the EBDA is not present.
.ebda_not_present:

	; Set bit 1 of the system status and the total memory as the reported value.
	or byte [system_status], 0x02
	mov [mem_total_kib], ax

	; Check if there is any free memory and handle it.
	cmp ax, 64 + SHELL_TOTAL_KIB
	je .no_free_memory

	; If yes, proceed to the main shell loop (systems without EBDAs didn't have extended memory yet).
	jmp shell_main_loop

; If they are the same, that means the EBDA is present and a standard memory configuration can be assumed.
.ebda_present:

	; Check if there is any free memory and handle it.
	mov word [mem_total_kib], 128
	cmp ax, 64 + SHELL_TOTAL_KIB
	je .no_free_memory

	; If there are less than 128KiB, assume 128KiB of total memory, then proceed with the main shell loop.
	cmp ax, 128
	jb shell_main_loop

	; Same for 256KiB.
	mov word [mem_total_kib], 256
	cmp ax, 256
	jb shell_main_loop

	; Same for 384KiB.
	mov word [mem_total_kib], 384
	cmp ax, 384
	jb shell_main_loop

	; Same for 512KiB.
	mov word [mem_total_kib], 512
	cmp ax, 512
	jb shell_main_loop

	; If 512KiB or more are reported, proceed with the extended memory detection.
	mov word [mem_total_kib], 640
	jmp ext_memory_detect


; ====================


; ERROR HANDLERS:

; Handle errors and warnings while detecting low memory.


; Handle zero free memory: ask whether to continue with limited functionalities (Y or N).
.no_free_memory:

	; Print the no free memory error message.
	mov si, err_no_free_memory
	call prints
	jmp .ask_to_continue

; Handle a failure in detecting low memory: ask whether to continue with limited functionalities (Y or N).
.failed:

	; Print the memory detection error message.
	mov si, err_memory_detect_failed
	call prints

.ask_to_continue:

	mov si, err_limited_mem_function
	call prints
	
	; Set default option to no.
	push "n"

; Loop to detect the user's choice.
.read_yn:

	; Get the character inserted.
	xor ah, ah
	int 0x16
	xor ah, ah

	; Check its validity (Y or N).
	cmp al, "y"
	je .valid
	cmp al, "n"
	je .valid

	; Check for enter (CR).
	cmp al, 0x0D
	je .enter_pressed

	; Else read again.
	jmp .read_yn

; Display the choice and save it.
.valid:

	; Save the choice and discard the previous.
	pop bx
	push ax
	mov ah, al

	; Overwrite the previous one on the screen.
	mov al, 0x08
	call printc
	mov al, ah
	call printc

	; Read again.
	jmp .read_yn

; Handle enter.
.enter_pressed:

	; Go to a new line.
	mov si, msg_newline
	call prints

	; Check whether to continue.
	pop ax
	cmp al, "y"
	je .continue

; If not, execute the 'poweroff' command.
.stop:

	call exe_poweroff

; If yes, continue with limited functionalities.
.continue:

	; Set bit 0 of the system status.
	or byte [system_status], 0x01

	; Print the continue with limited functionalities message.
	mov si, msg_continue_limited_function
	call prints
	jmp shell_main_loop

; END OF ERROR HANDLERS.

; END LOW OF MEMORY DETECTION.




; ========================================
; ========================================




; EXTENDED MEMORY DETECTION:

; Detect how much contiguous memory is install on the system (no full map).
ext_memory_detect:

	; The INT 0x15, 0xE801 subroutine is only available on 80386+ systems.
	cmp byte [cpu_type], 2
	je .88h_subfunction

; Acquire extended memory over 1MiB.
.E801h_subfunction:

	; Get the result in AX (for 1MiB to 16MiB) and in BX (from 16MiB and above).
	mov ax, 0xE801
	int 0x15
	jc .88h_subfunction ; If it fails, use the 0x88 subfunction.

	; If AX is zero, use the pair the registers CX and DX.
	cmp ax, 0
	je .E801h_use_cx_dx

	; Save the value in KiB.
	mov word [mem_total_kib], 1024 ; If AX was not zero, then there is at least 1MiB of installed memory.
	add [mem_total_kib], ax
	push bx
	xor ebx, ebx ; For safety, clear the high 16 bits of EBX.
	pop bx
	shl ebx, 6 ; Multiply the number by 64, as expressed in 64KiB blocks.
	add [mem_total_kib], ebx ; Add it to the total.

	jmp .E801h_total_mib

; If AX was zero, try using CX and DX.
.E801h_use_cx_dx:

	; If even CX is zero, proceed to the shell main loop.
	cmp cx, 0
	je shell_main_loop

	; Replicate the procedure used on AX and BX.
	mov word [mem_total_kib], 1024
	add [mem_total_kib], cx
	push dx
	xor edx, edx
	pop dx
	shl edx, 6
	add [mem_total_kib], edx

	jmp .E801h_total_mib

; Store the result also in MiB
.E801h_total_mib:

	; Divide the value by 1024, to go from KiB to MiB; some digits might be lost.
	mov eax, [mem_total_kib]
	shr eax, 10
	mov [mem_total_mib], eax

	jmp .memory_detect_done

; If the processor is an 80286 or the other subroutine failed, try with 0x88.
.88h_subfunction:

	; Get the result in AX (for 1MiB and over).
	mov ax, 0x88
	int 0x15
	; Continue to the shell main loop if even 0x88 doesn't work or reports 0.
	jc shell_main_loop
	cmp ax, 0
	je shell_main_loop

	; Save the value in KiB.
	mov word [mem_total_kib], 1024
	add [mem_total_kib], ax

	; Save the value in MiB.
	shr ax, 10
	mov word [mem_total_mib], 1
	add [mem_total_mib], ax

	jmp shell_main_loop

; End the memory detection process.
.memory_detect_done:

	; Clea the 32-bit registers, not to create issues.
	xor eax, eax
	xor ebx, ebx
	xor ecx, ecx
	xor edx, edx

; END OF EXTENDED MEMORY DETECTION.

; END OF MEMORY DETECTION.

; END OF ENTRY CODE.






; ================================================================================
; ================================================================================






; MAIN CODE:

; Main loop of the shell, repeats after every command.
shell_main_loop:

	; Print the prompt for a command.
	mov si, msg_enter_command
	call prints

	; Set up the buffer and the length tracker.
	mov di, cmd_input_buffer
	mov byte [cmd_input_length], 0

; Loop to read all the characters inserted.
.read_command:

	; Get the character typed by the user.
	xor ah, ah
	int 0x16

	; Check for page up, page down and home (PgUp, PgDn or Home).
	cmp ah, 0x49
	je .page_up_pressed
	cmp ah, 0x51
	je .page_down_pressed
	cmp ah, 0x47
	je .home_pressed

	; Block any input from a non-active page.
	mov bl, [displayed_page]
	cmp bl, [active_page]
	jne .read_command

	; Check for enter, backspace and the null character (CR, BS or NULL).
	cmp al, 0x0D
	je .enter_pressed
	cmp al, 0x08
	je .backspace_pressed
	cmp al, 0x00
	je .read_command

	; Check the length of the command so far, not to overflow the buffer.
	cmp byte [cmd_input_length], 31
	jnb .read_command

	; Print the character, store it in the buffer and increment the input length.
	call printc
	cld
	stosb
	inc byte [cmd_input_length]

	jmp .read_command




; ========================================
; ========================================




; SPECIAL HANDLERS:

; Handle special characters that have different effects on the buffer or on the displayed string.


; Handle backspace (0x08).
.backspace_pressed:

	; Ignore it if the buffer is empty.
	cmp byte [cmd_input_length], 0
	je .read_command

	; Else, move the cursor back, print a space and move it back again.
	call printc
	mov al, 0x20
	call printc
	mov al, 0x08
	call printc

	; Decrement the position of the last byte in the buffer and the input length.
	dec di
	dec byte [cmd_input_length]
	jmp .read_command


; ====================


; Handle enter (0x0D).
.enter_pressed:

	; Prompt again if the command was empty.
	cmp byte [cmd_input_length], 0
	je shell_main_loop

	; Go to a new line.
	mov si, msg_newline
	call prints

	; If the command wasn't empty, print another newline.
	call prints

	; Store 0x00 in the buffer, signalling the end of the input, and increment the input length.
	xor al, al
	stosb
	inc byte [cmd_input_length]

	; Set up the counter (BX) and the offset (DX).
	mov bx, 0
	mov dx, 0
	jmp .parse_table


; ====================


; Handle page up (scan code 0x49).
.page_up_pressed:

	; Ignore it if the displayed page is the last one.
	mov al, [displayed_page]
	cmp al, [last_page]
	je .read_command

	; If the displayed page is 0, wraparound.
	cmp al, 0
	je .page_up_wraparound

	; Else, display the previous page.
	dec al
	jmp .change_page

; Wraparound the displayed page.
.page_up_wraparound:

	; Change to displayed page 7.
	mov al, 7
	jmp .change_page


; ====================


; Handle page down (scan code 0x51).
.page_down_pressed:

	; Ignore it if the displayed page is the active one.
	mov al, [displayed_page]
	cmp al, [active_page]
	je .read_command

	; Increment the displayed page number in modulo 8.
	inc al
	and al, 7
	jmp .change_page


; ====================


; Handle home (scan code 0x47).
.home_pressed:

	; Display the active page.
	mov al, [active_page]

; Change the page.
.change_page:

	; Display the requested page, then go back to the main loop.
	call change_page
	jmp .read_command

; END OF SPECIAL HANDLERS.




; ========================================
; ========================================




; COMMAND VALIDATION:

; Check whether the command entered by the user exists or not (no argument support).

; Parse the command table to see if the entered command exists.
.parse_table:

	; Set up the counter (CX), the length (BX), the source (SI) and the destination (DI).
	mov cx, [cmd_entries_count]
	xor bh, bh
	mov bl, [cmd_input_length]
	mov si, cmd_input_buffer
	mov di, cmd_table

; Compare the entered command with the table entry.
.compare_entries:

	; Compare the two strings: the zero flag is set if they are the same.
	call strcmp
	je .valid_command

	; Increment the table index by 16.
	add di, 16

	; If not all entries were checked, loop again.
	loop .compare_entries
	; Else the command was invalid, proceed.

; Handle an invalid command.
.invalid_command:

	; Print the invalid command message, then go back to the main loop.
	mov si, msg_invalid_command
	call prints
	jmp shell_main_loop

; Execute a valid command.
.valid_command:

	; Call to the address after the command name (12 bytes, 0x00 include), then go back to the main loop.
	add di, 12
	mov bx, di
	call bx
	jmp shell_main_loop

; END OF COMMAND VALIDATION.

; END OF MAIN CODE.






; ================================================================================
; ================================================================================






; KERNEL'S FUNCTIONS:

; These functions are included as standalone assembly files from 'src/functions/'.
; They offer the functionalities that a kernel should provide.
; Their number and complexity increases as the OS grows.


; PRINTS:

; 'prints': print a string in TTY mode.

; Inputs:
; - DS:SI = address to the NULL-terminated string to print.

; Outputs nothing, all registers are preserved.

%include "src/functions/prints.asm" ; 'prints' function.


; ====================


; PRINTD16:

; 'printd16': print a 16-bit number into its decimal ASCII representation.

; Inputs:
; - AX = number to print.

; Outputs nothing, all registers are preserved.

%include "src/functions/printd16.asm" ; 'printd16' function.


; ====================


; PRINTD32:

; 'printd32': print a 32-bit number into its decimal ASCII representation (80386+ only).

; Inputs:
; - EAX = number to print.

; Outputs nothing, all registers are preserved.

%include "src/functions/printd32.asm" ; 'printd32' function.


; ====================


; PRINTR:

; 'printr': repeatedly print a character via 'printc'.

; Inputs:
; - AL = ASCII code of the character to print.
; - CL = number of times to print the character.

; Outputs nothing, all registers are preserved.

%include "src/functions/printr.asm" ; 'printr' function.


; ====================


; PRINTC:

; 'printc': print a character in TTY mode on the active page.

; Inputs:
; - AL = ASCII code of the character to print.

; Outputs nothing, all registers are preserved.

%include "src/functions/printc.asm" ; 'printc' function.


; ====================


; STRCMP:

; 'strcmp': compare two NULL-terminated strings.

; Inputs:
; - SI = address of the first string;
; - DI = address of the second string;
; - BX = number of characters to compare (0xFFFF if all).

; Outputs nothing, all registers are preserved.

%include "src/functions/strcmp.asm" ; 'strcmp' function.


; ====================


; CHANGE_PAGE:

; 'change_page': change the currently displayed page.

; Inputs:
; - AL = new page number.

; Outputs nothing, all registers are preserved.

%include "src/functions/change_page.asm" ; 'change_page' function.


; END OF KERNEL'S FUNCTIONS.






; ================================================================================
; ================================================================================






; IMPORTANT VALUES:

; This section contains values that are used to keep track of the system status and information.



; DISK DATA:

; Values passed by the bootloader for disk operations, so they don't have to be recalculated:

; Addresses of useful filesystem data structures already loaded in memory.
offs_fat: dw 0x0000 ; Offset of the FAT (segment is 0x0000).
offs_root_dir: dw 0x0000 ; Offset of the root directory (segment is 0x0000).

; LBA addresses of useful filesystem locations on the disk.
lba_data_region: dw 0x0000 ; LBA of the data region.

; END OF DISK DATA.




; ========================================
; ========================================




; DISPLAY DATA:

; Cursor position tracker (0,0 to 255,255), accessible together as a word.
cursor_row: db 00 ; Cursor row (in normal text modes from 0 to 24).
cursor_column: db 00 ; Cursor column (in normal text modes from 0 to 79).

; Page trackers for managing printing and scrollback.
active_page: db 0 ; The active page, where the prompt is situated; printing and entering are only allowed here, PGDN and HOME have no effect.
last_page: db 1 ; The last page in scrollback; PGUP has no effect.
displayed_page: db 0 ; The currently displayed page; PGUP, PGDN and HOME can work or not based on the page number.

; END OF DISPLAY DATA.




; ========================================
; ========================================




; CPU INFORMATION:

; Various information about the CPU; everything defaults to no CPUID support.

; CPU architecture (defaults to zero, so 8086/8088).
cpu_type: db 00 ; Contains a value describing the system's architecture, only when differences matter.
				; - 0: 8086/8088, which is currently not supported.
				; - 2: 80286, PUSHA/POPA are supported.
				; - 3: 80386, protected mode is supported.
				; - 4: 80486.
				; - 5: 80586+, CPUID is supported.

; Maximum leaves for basic and extended CPUID calls (defaults to zero, no support).
cpuid_max_basic_leaf: db 0x00
cpuid_max_ext_leaf: db 0x00 ; Only the least significant byte is reported, bit 31 set is implied.

; Vendor ID from CPUID leaf 0.
cpu_vendor_id: db "Unknown     ", 0

; Processor brand string from CPUID leaves 0x80000002-4.
cpu_brand_string: db "Generic 80x86 CPU: can't acquire model via CPUID", 0

; Number of physical cores from various CPUID sources (defaults to 1).
cpu_physical_cores: db 01

; Number of logical cores from various CPUID sources (defaults to 1).
cpu_logical_cores: dw 01

; Number of logical cores per physical core from various CPUID sources (defaults to 1, no SMT/HTT).
cpu_threads_per_core: db 01

; Version information (family, model, stepping) from CPUID leaf 1.
cpu_version_info: dd 0x00000000

; Additional information from CPUID leaf 1.
cpu_additional_info: dd 0x00000000

; Feature bits from CPUID leaf 1 (they remain all zero if CPUID is unsupported).
cpu_feature_bits_edx: dd 0x00000000
cpu_feature_bits_ecx: dd 0x00000000

; Feature bits from CPUID leaf 0x80000001 (they remain all zero if CPUID is unsupported).
cpu_feature_bits_ext_edx: dd 0x00000000
cpu_feature_bits_ext_ecx: dd 0x00000000

; END OF CPU INFORMATION.




; ========================================
; ========================================




; MEMORY INFORMATION:

; Various information about memory; everything defaults to zero.

; Total installed memory, including low and high memory and reserved regions.
mem_total_kib: dd 0 ; Number in KiB.
mem_total_mib: dd 0 ; Number in MiB (0 if no extended memory is detected).

; Total usable memory, from after this shell to the beginning of the EBDA.
mem_usable_kib: dw 0 ; Number in KiB.

; Currently free memory, from after this shell to the beginning of the EBDA.
mem_free_kib: dw 0 ; Number in KiB.

; Segment where the EBDA is located (if present).
ebda_seg: dw 0 ; Multiply by 16 for the address.

; END OF MEMORY INFORMATION.




; ========================================
; ========================================




; Status and control values, to allow or block certain features or operations; everything defaults to no restrictions.

; System status.
system_status: db 00 ; Contains a value describing the current system's status and what functionalities should be restricted (to be revised):
					 ; - 00: normal status, everything is allowed;
					 ; - bit 0: memory detection failed, files can't be opened and other programs can't be launched (currently has no effect);
					 ; - bit 1: EBDA not present;
					 ; - bit 2: couldn't properly detect SMT/HTT support, so the physical cores count might not be correct.

; Printing status.
print_control: db 00 ; Contains a value describing how printing should be restricted (expandable for more values and purposes):
					 ; - 00: normal printing, everything is allowed;
					 ; - 02: auto newline control, one line feed (LF) gets blocked, then it is disabled;
					 ;		 done to prevent an extra newline after an automatic one happened.
					 ; - 04: new page control, all line feeds (LF) get blocked, only disabled by printing a character except carriage return (CR);
					 ;		 done to avoid blank lines at the beginning of pages (to save space) after a page change happened. 

; END OF IMPORTANT VALUES.






; ================================================================================
; ================================================================================






; TEXT MESSAGES:

; Strings for messages, warnings, errors and prompts used by this shell.
; All strings should be NULL-terminated; ENDL is a macro for 0x0D (CR) and 0x0A (LF).

; How long are 80 characters for reference: 12345678901234567890123456789012345678901234567890123456789012345678901234567890



; NORMAL MESSAGES:

; Define strings for normal messages, logs and prompts.

; Contains 0x0D and 0x0A, used for going to a new line more efficiently.
msg_newline: db ENDL, 0

; Welcome message, also used in the 'hello' command, contains basic information.
msg_hello: db "Welcome to LARI-OS! This is a command-line shell!", ENDL, \
			  "We are currently running in 16-bit real-mode.", ENDL, \
			  "The video mode is 80*25 4-bit colour text, but the output is monochrome.", ENDL, \
			  "Type 'help' for general help; type 'sysinfo' for more information.", ENDL, \
			  "Use the 'PgUp' and 'PgDn' buttons to scroll through the 8 pages.", ENDL, 0

; Blank page messages, printed in any empty page at the beginning; after the first one, the number of the page is printed.
msg_page_empty_1: db "Page ", 0
msg_page_empty_2: db " is currently empty...", 0

; Continue with limited functionalities message, printed when the user chooses to continue even though a critical detection process failed.
msg_continue_limited_function: db ENDL, "Continuing with limited functionalities.", ENDL, 0

; Success message, used for testing purposes.
msg_success: db "Success!", ENDL, 0

; Prompt message, which prompts for a command at the beginning of every shell loop.
msg_enter_command: db ENDL, "shell@lari-os > ", 0

; Invalid command message, printed when the entered command is not in the command table.
msg_invalid_command: db "The command is not present in the command table!", ENDL, 0

; Stub command message, printed when the entered command is valid but not yet available or fully implemented.
msg_command_stub: db "This command is still a stub and therefore is currently not available.", ENDL, \
					 "Check the 'todo.txt' file to track the development progress.", ENDL, 0




; ========================================
; ========================================




; HELP COMMAND STRINGS:

; Strings and messages printed by the 'help' command.

; Contains more detailed information.
msg_help_1: db "Welcome to LARI-OS!", ENDL, \
			 "This is a CLI (Command Line Interface) environment, so everything is executed v-ia commands.", ENDL, \
			 "The following list includes all available commands, with which you will be able to control the system:", ENDL, \
			 "display information, read and write data on a disk, launch more advanced progra-ms and manage the computer.", ENDL, 0

; Command list messages, printed in sequence to build a list of all commands present in the command table.
msg_help_list_1: db ENDL, "There are ", 0
msg_help_list_2: db " available commands:", 0
msg_help_list_3: db ENDL, "- ", 0

; Contains more detailed instructions.
msg_help_2: db ENDL, ENDL, "When typing commands, use 'Backspace' to delete the last character;", ENDL, \
			   "To navigate between pages, use 'PgUp' to scroll up and 'PgDn' to scroll down;", ENDL, \
			   "Use 'Home' to return to the active page, where the last output was printed.", ENDL, 0

; END OF HELP COMMAND STRINGS.




; ========================================
; ========================================




; SYSINFO COMMAND STRINGS:

; Strings and messages printed by the 'sysinfo' command.

; CPU information list messages, printed in sequence to list various information about the processor.
msg_cpu_info: db "CPU information", ENDL, 0
msg_vendor_id: db "Vendor: ", 0
msg_brand_string: db ENDL, "Model: ", 0
msg_physical_cores: db ENDL, "Physical cores: ", 0
msg_physical_cores_uncertain: db " (couldn't confirm SMT/HTT support, might be incorrect)", 0
msg_logical_cores: db ENDL, "Logical cores: ", 0

; Memory information list messages, printed in sequence to list various information about memory utilization and availability.
msg_memory_info: db ENDL, ENDL, "Memory (RAM) information", ENDL, 0
msg_total_memory_kib: db "Total available memory (KiB): ", 0
msg_total_memory_mib: db                        "(MiB): ", 0
msg_usable_memory: db ENDL, "Total currently usable memory (KiB): ", 0
msg_free_memory: db ENDL, "Free memory (KiB): ", 0

; END OF SYSINFO COMMAND STRINGS.




; ========================================
; ========================================




; POWEROFF COMMAND STRINGS:

; Poweroff message, printed by the 'poweroff' command, prompts the user to press the power button to turn off the computer.
msg_poweroff: db "Press the power button to turn off the computer.", ENDL, 0

; END OF POWEROFF COMMAND STRINGS.

; END OF NORMAL MESSAGES.




; ========================================
; ========================================




; ERROR MESSAGES:

; Define strings for error messages.

; Unsupported architecture error message, printed if Collins' algorithm detects an 8086/8088 CPU.
err_arch_unsupported: db "An 8086/8088 CPU was detected, which is not supported: 80286+ is required!", 0 

; Memory detection failure error message, printed if memory detection failed.
err_memory_detect_failed: db "Low-memory (<640KiB) detection via BIOS interrupt INT 0x12 has failed!", ENDL, 0

; No free memory error message, printed if memory detection reported zero usable memory.
err_no_free_memory: db "No free memory was found!", ENDL, 0

; Limited memory capabilities error message, printed if memory detection failed or reported zero usable memory.
err_limited_mem_function: db ENDL, "You can choose whether continue using the OS but with limited functionalities:", ENDL, \
								   "disk data R/W operations and memory allocation will be disabled;", ENDL, \
								   "no programs outside of the default internal commands will be able to run.", ENDL, \
								   "Do you want to continue (y/n)? >  ", 0

; END OF ERROR MESSAGES.

; END OF TEXT MESSAGES.






; ================================================================================
; ================================================================================






; REFERENCE TABLES:

; Table and small databases used by the code to check, sort and validate certain values.



; VENDOR ID TABLE:

; A reference table for all possible vendor IDs and their preferred algorithm for core enumeration.

; Entry structure (offset and length in decimal):
; - NULL-terminated vendor ID, padded with spaces (offs 00, len 13);
; - preferred core enumeration algorithm (offs 13, len 14):
;	  - 0: Intel's algorithm, the most used;
;	  - 1: AMD's algorithm, less used;
;	  - 2: requires custom algorithm or is unknown, not handled specifically.

; Total known vendor IDs.
vendor_entries_count: db (vendor_table_end - vendor_table) / 14

; Address of the vendor ID table.
vendor_table:

db "AMD ISBETTER", 0, 1 ; AMD early K5 engineering samples.

db "AuthenticAMD", 0, 1 ; - AMD modern and legacy processors;
						; - Microsoft WOW64 x86 on ARM64 emulator.

db "CentaurHauls", 0, 0 ; VIA, Centaur, IDT and Zhaoxin processors.

db "Compaq FX!32", 0, 2 ; Compaq FX!32 emulator, x86 on DEC Alpha.

db "ConnectixCPU", 0, 0 ; Connectix Virtual PC before Microsoft acquisition, x86 on PowerPC.

db "CyrixInstead", 0, 2 ; Cyrix, STMicroelectronics and IBM early x86 clones.

db "E2K MACHINE ", 0, 2 ; MCST Elbrus Russian processors, x86 on VLIW.

db "GenuineAO486", 0, 0 ; ao486 soft CPU core from MiSTer for FPGAs, older release.

db "GenuineIntel", 0, 0 ; - Intel standard processors;
						; - Apple Rosetta 2, x86-64 on ARM64 emulator;
						; - v586 soft CPU core.

db "GenuineIotel", 0, 0 ; Intel typo variant.

db "Genuine RDC ", 0, 0 ; RDC Semiconductor embedded x86 compatibles.

db "Geode by NSC", 0, 0 ; AMD Geode core line by National Semiconductor.

db "HygonGenuine", 0, 1 ; Chinese venture with AMD based on Zen.

db "Insignia 586", 0, 0 ; Insignia SoftWindows and RealPC legacy, x86 on PowerPC emulator.

db "MiSTer AO486", 0, 0 ; ao486 soft CPU core from MiSTer for FPGAs, newer releases.

db "Neko Project", 0, 0 ; Neko Project II, x86 on Japanese PC-98 emulator.

db "NexGenDriven", 0, 2 ; NexGen processors, before AMD aquisition.

db "PowerVM Lx86", 0, 0 ; IBM PowerVM Lx86, x86 on IBM POWER5/6 emulator.

db "RiseRiseRise", 0, 2 ; Rise Technology x86 clones.

db "  Shanghai  ", 0, 0 ; Zhaoxin modern processors.

db "SiS SiS SiS ", 0, 2 ; SiS few x86 processors.

db "TransmetaCPU", 0, 0 ; Transmeta processors, x86 on VLIW.

db "UMC UMC UMC ", 0, 2 ; UMC legacy processors.

db "VIA VIA VIA ", 0, 0 ; VIA modern Intel-mimic processors.

db "Virtual CPU ", 0, 0 ; Microsoft Virtual PC 7, x86 on PowerPC.

db "Vortex86 SoC", 0, 0 ; DM&P Electronics embedded SoCs.

; Address of the end of the vendor ID table.
vendor_table_end:

; END OF VENDOR ID TABLE.




; ========================================
; ========================================




; COMMAND TABLE:

; Define a table for known and valid commands.

; Entry structure (offset and length in decimal):
; - NULL-terminated command name, padded with zeros (offs 00, len 12);
; - call to the command executor (offs 12, len 3);
; - return instruction to the main code (offs 15, len 1).

; Total available commands.
cmd_entries_count: dw (cmd_table_end - cmd_table) / 16

; Address of the command table.
cmd_table:

; 'hello' command, display the welcome message.
cmd_hello:

	db "hello", 0
	times 12-($-cmd_hello) db 0
	call exe_hello
	ret

; 'help' command, display the help message.
cmd_help:

	db "help", 0
	times 12-($-cmd_help) db 0
	call exe_help
	ret

; 'sysinfo' command, display various system information.
cmd_sysinfo:

	db "sysinfo", 0
	times 12-($-cmd_sysinfo) db 0
	call exe_sysinfo
	ret

; 'poweroff' command, display a poweroff message and halt (expandable for unsaved data checking and freeing memory).
cmd_poweroff:

	db "poweroff", 0
	times 12-($-cmd_poweroff) db 0
	call exe_poweroff
	ret

; Address of the end of the command table.
cmd_table_end:

; END OF COMMAND TABLE.

; END OF REFERENCE TABLES.






; ================================================================================
; ================================================================================






; COMMAND HANDLING:

; Buffers, counters and values for managing commands and user inputs.
; The command table is found amongst the other reference tables.

; Entered command buffer, for holding the typed characters (31 bytes and 1 NULL character).
cmd_input_buffer: times 32 db 0

; Entered command length, for comparing and matching the input with the table.
cmd_input_length: db 0






; ================================================================================
; ================================================================================






; COMMAND EXECUTORS:

; This command executors, which get called from the command table, handle the command on their own.
; They return to the table's entry's return, which gives back control to the main loop.


; HELLO COMMAND:

; Execute the 'hello' command: print the welcome message.
exe_hello:

	; Print the welcome message.
	mov si, msg_hello
	call prints
	ret

; END OF HELLO COMMAND.




; ========================================
; ========================================




; HELP COMMAND:

; Execute the 'help' command: print the help message.
exe_help:

	; Print the help message.
	mov si, msg_help_1
	call prints

	; Print the help list message and the number available commands.
	mov si, msg_help_list_1
	call prints
	mov ax, [cmd_entries_count]
	call printd16
	mov si, msg_help_list_2
	call prints

	; Set up a counter (CX) and push the command table address.
	push cmd_table
	mov cx, [cmd_entries_count]

; Print all the available command in a list.
.list_commands:

	; Print '- ' for the list.
	mov si, msg_help_list_3
	call prints

	; Print the command name and go to the next one in the table.
	pop si
	call prints
	add si, 16
	push si

	; Loop bak until all commands have been listed.
	loop .list_commands

	mov si, msg_help_2
	call prints

; Clear the stack and return.
.done:

	pop si
	ret

; END OF HELP COMMAND.




; ========================================
; ========================================




; SYSINFO COMMAND:

; Execute the 'sysinfo' command: display system information.
exe_sysinfo:

	; Print the CPU information message.
	mov si, msg_cpu_info
	call prints

; Print the vendor ID.
.vendor_id:

	mov si, msg_vendor_id
	call prints
	mov si, cpu_vendor_id
	call prints

; Print the brand string.
.brand_string:

	mov si, msg_brand_string
	call prints
	mov si, cpu_brand_string
	call prints

; Print the number of physical cores.
.physical_cores:

	mov si, msg_physical_cores
	call prints
	xor ax, ax
	mov al, [cpu_physical_cores]
	call printd16

	; Check if SMT/HTT was confirmed, skip if yes.
	test byte [system_status], 0x04
	jz .logical_cores

	; If it couldn't be confirmed, print a warning message.
	mov si, msg_physical_cores_uncertain
	call prints

; Print the number of logical cores.
.logical_cores:

	mov si, msg_logical_cores
	call prints
	mov ax, [cpu_logical_cores]
	call printd16

; Display information about installed and available memory.
.memory_info:

	; Print the memory information message.
	mov si, msg_memory_info
	call prints

; Print the total available memory in KiB.
.total_memory_kib:

	mov si, msg_total_memory_kib
	call prints

	; Check if 'printd32' is usable (80386+).
	cmp byte [cpu_type], 2
	je .use_printd16_kib

	; Print the amount in KiB.
	mov eax, [mem_total_kib]
	call printd32
	jmp .total_memory_mib

; Use 'printd16' for 80286 processors.
.use_printd16_kib:

	mov ax, [mem_total_kib]
	call printd16

; Print the total available memory in MiB.
.total_memory_mib:

	mov si, msg_newline
	call prints

	; Align with the other unit specifier by prtinting spaces.
	mov al, " "
	mov cl, 23
	call printr
	mov si, msg_total_memory_mib
	call prints

	; Check if 'printd32' is usable (80386+).
	cmp byte [cpu_type], 2
	je .use_printd16_mib

	; Print the amount in MiB.
	mov eax, [mem_total_mib]
	call printd32
	jmp .usable_memory

; Use 'printd16' for 80286 processors.
.use_printd16_mib:

	mov ax, [mem_total_mib]
	call printd16

; Print the total usable memory in KiB.
.usable_memory:

	mov si, msg_usable_memory
	call prints
	mov ax, [mem_usable_kib]
	call printd16

; Print the amount of free memory available at the time of executing the command.
.free_memory:

	mov si, msg_free_memory
	call prints
	mov ax, [mem_free_kib]
	call printd16
	mov si, msg_newline
	call prints

; Return.
.done:

	ret

; END OF SYSINFO COMMAND.




; ========================================
; ========================================




; POWEROFF COMMAND:

; Execute the 'poweroff' command: print the poweroff message and halt the processor.
exe_poweroff:

	; Print the poweroff message.
	mov si, msg_poweroff
	call prints

; Disable maskable interrupts and halt the processor in a loop; it should never return.
.halt:

	cli
	hlt

	; For safety, to avoid executing undefined memory.
	jmp .halt
	ret

; END OF POWEROFF COMMAND.

; END OF COMMAND EXECUTORS.






; Define a value for the shell size in KiB.
SHELL_TOTAL_KIB equ ($ - $$) / 1024
