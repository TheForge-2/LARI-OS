; Copyright © 2024-2025 TheForge-2
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LINCENSE.txt' in the project root for full terms.




; Developer's notes:
; - currently nothing.




; DESCRIPTION:

; This is a 16-bit real mode shell, which allows basic input and output operations via commands:
; disk read and write, display printing, input prompting, filesystem operations.
; It runs in BIOS text mode 0x03: 80*25, 4-bit colour, 8 pages.
; Text output is currently white on black due to TTY printing.

; It is structured in a monolithic way, so that all the necessary functions are contained in the code.
; This shell is executed by the bootloader, which is also expected to pass three values via the stack.
; See 'information.txt' for more information.

; END OF DESCRIPTION.




; DIRECTIVES:

; Directives to the assembler, not actual code.
org 0x0000 ; The code is loaded at offset 0x0000.
bits 16 ; Emit 16-bit code.

; Define macros for semplifying some things.
%define ENDL 0x0D, 0x0A ; Endline macro, a carriage return (CR) and a line feed (LF).

; END OF DIRECTIVES.




; ########################################




; ENTRY CODE:

; Entry point of the shell, executed after the bootloader's far jump.
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

	; Print the welcome message.
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
	call printd
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


; MEMORY DETECTION:

; Detect how many kB of memory are usable before the EBDA.
lower_memory_detect:

	; Use BIOS INT 0x12 to try to detect memory.
	clc
	int 0x12
	jc .failed

	; Exclude segments 0x1000 and 0x2000 (128kB in total), used by the IVT, BDA, stack, bootlaoder, FAT, root directory and this shell.
	sub ax, 128
	mov [free_kb], ax

	; Then proceed to the main loop.
	jmp shell_main_loop

; Handle a failure in detecting memory: ask whether to continue with limited functionalities (Y or N).
.failed:

	; Print memory detection error message.
	mov si, err_memory_detect_failed
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

; If yes, continue on memory detection fail with limited functionalities.
.continue:

	; Set the system status to 2.
	mov byte [system_status], 2

	; Print the continue on memory detection failure message.
	mov si, msg_continue_memory_detect_failed
	call prints

; END OF MEMORY DETECTION.

; END OF ENTRY CODE.




; ########################################




; MAIN CODE:

; Main loop of the shell, repeats after every command.
shell_main_loop:

	; Print the prompt for a command.
	mov si, msg_enter_command
	call prints

	; Set up the buffer and the lenght tracker.
	mov di, cmd_input_buffer
	mov byte [cmd_input_lenght], 0

; Loop to read all the characters inserted.
.read_command:

	; Get the character typed by the user.
	xor ah, ah
	int 0x16

	; Check for page up, page down or home (PGUP, PGDN or HOME).
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

	; Check for enter, backspace or the null character (CR, BS or NULL).
	cmp al, 0x0D
	je .enter_pressed
	cmp al, 0x08
	je .backspace_pressed
	cmp al, 0x00
	je .read_command

	; Check the lenght of the command so far, not to overflow the buffer.
	cmp byte [cmd_input_lenght], 31
	jnb .read_command

	; Print the character, store it in the buffer and increment the input lenght.
	call printc
	cld
	stosb
	inc byte [cmd_input_lenght]

	jmp .read_command


; SPECIAL HANDLERS:

; Handle backspace.
.backspace_pressed:

	; Ignore it if the buffer is empty.
	cmp byte [cmd_input_lenght], 0
	je .read_command

	; Else, move the cursor back, print a space and move it back again.
	call printc
	mov al, 0x20
	call printc
	mov al, 0x08
	call printc

	; Decrement the position of the last byte in the buffer and the input lenght.
	dec di
	dec byte [cmd_input_lenght]
	jmp .read_command

; Handle enter.
.enter_pressed:

	; Go to a new line.
	mov si, msg_newline
	call prints

	; Store 0x00 in the buffer, signaling the end of the input, and increment the input lenght.
	xor al, al
	stosb
	inc byte [cmd_input_lenght]

	; Set up the counter (BX) and the offset (DX).
	mov bx, 0
	mov dx, 0
	jmp .parse_table

; Handle page up.
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

; Handle page down.
.page_down_pressed:

	; Ignore it if the displayed page is the active one.
	mov al, [displayed_page]
	cmp al, [active_page]
	je .read_command

	; Increment the displayed page number in modulo 8.
	inc al
	and al, 7
	jmp .change_page

; Handle home.
.home_pressed:

	; Display the active page.
	mov al, [active_page]

; Change the page.
.change_page:

	; Display the requested page, then go back to the main loop.
	call change_page
	jmp .read_command

; END OF SPECIAL HANDLERS.


; ####################


; COMMAND VALIDATION:

; Parse the command table to see if the entered command exists.
.parse_table:

	; Set up the lenght (CX), the source (SI) and the destination (DI).
	xor ch, ch
	mov cl, [cmd_input_lenght]
	mov si, cmd_input_buffer
	mov di, cmd_table

	; Add the entry's offset to the table address.
	add di, dx

	; Compare the entered command with the table entry: the zero flag stays set if they are the same.
	cld
	repe cmpsb
	je .valid_command

	; Check if all entries were compared and increment the counter and the offset (by 16).
	add dx, 16
	inc bx
	cmp bx, [cmd_entries_count]

	; If not, check the next entry; if yes, the command was invalid.
	jb .parse_table
	jmp .invalid_command

; Execute a valid command.
.valid_command:

	; Go to a new line.
	mov si, msg_newline
	call prints

	; Call to the address after the command name (12 bytes, 0x00 include), then go back to the main loop.
	add dx, cmd_table + 12
	mov bx, dx
	call bx
	jmp shell_main_loop

; Handle an invalid command.
.invalid_command:

	; Print the invalid command message, then go back to the main loop.
	mov si, msg_invalid_command
	call prints
	jmp shell_main_loop

; END OF COMMAND VALIDATION.

; END OF MAIN CODE.




; ########################################




; KERNEL'S FUNCTIONS:


; PRINTS:

; 'prints': print a string in TTY mode.

; Inputs:
; - DS:SI = address to the NULL-terminated string to print.

; Outputs nothing, all registers are preserved.

prints:

	; Save the registers and clear the direction flag.
	pusha
	cld

; Loop for printing the ASCII of the byte pointed at by SI.
.putc:

	; Load the byte at SI in AL and break for 0x00.
	lodsb
	or al, al
	jz .done

	; Print it, then repeat.
	call printc
	jmp .putc

; Restore the registers and return.
.done:

	popa
	ret

; END OF PRINTS.


; ####################


; PRINTD:

; 'printd': print a number into its decimal ASCII representation.

; Inputs:
; - AX = number to print.

; Outputs nothing, all registers are preserved.

printd:

	; Set up the divisor (BX) and the counter (CX).	
	pusha
	mov bx, 10
	xor cx, cx

; Store each digit in the stack.
.store_digit:

	; Separate the digit in DX and push it.
	xor dx, dx
	div bx
	push dx

	; Check if all digits were acquired and increment the counter
	inc cx
	cmp ax, 0
	jnz .store_digit

; Convert and print each digit.
.putd:

	; Convert each digit in ASCII and print it.
	pop ax
	add al, 48
	call printc

	; If CX is not 0, print the next digit.
	loop .putd

; Restore the registers and return.
.done:

	popa
	ret

; END OF PRINTD.


; ####################


; PRINTC:

; 'printc': print a character in TTY mode on the active page.

; Inputs:
; - AL = ASCII code of the character to print.

; Outputs nothing, all registers are preserved.

printc:

	; Save the registers.
	pusha

; Check the print control byte for exeptions.
.check_print_control:

	mov ah, [print_control]

	; Check for normal status (0), auto newline (>2) and new page (>4) limitations.
	cmp ah, 0
	je .check_cursor
	cmp ah, 2
	jae .auto_newline_control
	cmp ah, 4
	jae .new_page_control

; Check the cursor postion.
.check_cursor:

	; Handle it separately if the character is a carriage return (CR) or a backspace (BS), as they can always be printed.
	cmp al, 0x08
	je .handle_cursor_backspace
	cmp al, 0x0D
	je .handle_cursor_carriage_return

	; Check if the cursor is at the last row.
	cmp byte [cursor_row], 24
	je .handle_last_row

	; If not, and the character is a line feed (LF), handle it separately.
	cmp al, 0x0A
	je .handle_cursor_line_feed

	; Check if the cursor is at the last column (last row excluded).
	cmp byte [cursor_column], 79
	je .handle_last_column

	; Else, increment the column in the cursor tracker and print directly.
	inc byte [cursor_column]
	jmp .print_tty

; Handle backspace.
.handle_cursor_backspace:

	; Decrement the column in the cursor tracker.
	dec byte [cursor_column]
	jmp .print_tty

; Handle carriage return.
.handle_cursor_carriage_return:

	; Set the column in the cursor tracker to 0.
	mov byte [cursor_column], 0
	jmp .print_tty

; Handle line feed.
.handle_cursor_line_feed:

	; Increment the row in the cursor tracker and preserve the column.
	inc byte [cursor_row]

; Print the character in teletype mode.
.print_tty:

	; Print the character in Al.
	mov ah, 0x0E
	mov bh, [active_page]
	xor bl, bl
	int 0x10

; Restore the registers and return.
.done:

	popa
	ret


; CONTROLS AND EXCEPTIONS:

; Handle exeptions for an auto newline.
.auto_newline_control:

	; Block one line feed (to avoid an extra newline) feed and let carriage returns.
	cmp al, 0x0A
	je .block_line_feed
	cmp al, 0x0D
	je .print_tty

	; Else, print the character and disable print control. 
	mov byte [print_control], 0
	jmp .print_tty

; Ignore one line feed and disable print control.
.block_line_feed:

	mov byte [print_control], 0
	jmp .done

; Handle exeptions for a new page.
.new_page_control:

	; Ignore line feeds (to avoid blank lines at the top of the page) and let carriage returns.
	cmp al, 0x0A
	je .done
	cmp al, 0x0D
	je .print_tty

	; Else, print the character and disable print control.
	mov byte [print_control], 0
	jmp .print_tty


; Handle the cursor position if it is in the last row.
.handle_last_row:

	; Trigger a page change on a line feed attempt.
	cmp al, 0x0A
	je .next_page

	; Else, if not in the last column, print the character.
	cmp byte [cursor_column], 79
	jb .print_tty

	; Print to 24,79 with INT 0x10,0x0A so the cursor doesn't advance (to avoid auto scrolling).
	mov ah, 0x0A
	mov bh, [active_page]
	mov cx, 1
	int 0x10

	; Set the column in the cursor tracker to 0 (skipped on line feed).
	mov byte [cursor_column], 0

; Switch to the next page.
.next_page:

	; Increment the active page modulo 8.
	mov al, [active_page]
	inc al
	and al, 0x07
	mov [active_page], al 
	call change_page

	; Also increment the last page modulo 8.
	inc al
	and al, 0x07
	mov [last_page], al

; Clear the new page.
.clear_page:

	; Set the row in the cursor tracker to 0.
	mov byte [cursor_row], 0

	; Set cursor at 00,00 (or 00,xx for a line feed).
	mov ah, 0x02
	mov bh, [active_page]
	mov dh, 0
	mov dl, [cursor_column]
	int 0x10

	; Blank the page by scrolling all of it.
	mov ah, 0x06
	xor al, al
	mov bh, 0x07
	xor cx, cx ; Upper-left is 0,0.
	mov dx, 0x184F ; Lower-right is 24,79.
	int 0x10

	; Set the print control to 4, to avoid blank lines at the beginning of the page.
	mov byte [print_control], 4
	jmp .done

; Handle the cursor position if it is in the last column (but not the last row). 
.handle_last_column:

	; Set the column in the cursor tracker to 0 and incement the row.
	mov byte [cursor_column], 0
	inc byte [cursor_row]

	; Set print control to 2, to avoid a possible extra unwanted line feed.
	mov byte [print_control], 2

	; Print the character.
	jmp .print_tty

; END OF CONTROLS AND EXCEPTIONS.

; END OF PRINTC.


; ####################


; CHANGE_PAGE:

; 'change_page': change the currently displayed page.

; Inputs:
; - AL = new page number.

; Outputs nothing, all registers are preserved.

change_page:

	; Save the registers.
	pusha

	; Change the page to the one in AL.
	mov ah, 0x05
	int 0x10

	; Update the displayed page number.
	mov [displayed_page], al

	; Restore the registers and return.
	popa
	ret

; END OF CHANGE_PAGE.

; END OF KERNEL'S FUNCTIONS.




; ########################################




; IMPORTANT VALUES:

; This section contains values that are used to keep track of the system status and to manage display and disk operations.

; Values passed by the bootloader for disk operations, so they don't have to be recalculated:

offs_fat: dw 0x0000 ; Offset of the FAT in memory (segment is 0x0000).
offs_root_dir: dw 0x0000 ; Offset of the root directory in memory (segment is 0x0000).

lba_data_region: dw 0x0000 ; LBA of the data region on the disk.


; Values used by the code to handle various functionalities.

free_kb: dw 0x0000 ; Number of free kB of memory, from 0x2000:0x0000 (0x20000, after this shell) to the beginning of the EBDA.

; Cursor position tracker (0,0 to 255,255), accessible together as a word.
cursor_row: db 00 ; Cursor row (in normal text modes from 0 to 24).
cursor_column: db 00 ; Cursor column (in normal text modes from 0 to 79).

; Page trackers for managing printing and scrollback.
active_page: db 0 ; The active page, where the prompt is situated; printing and entering are only allowed here, PGDN and HOME have no effect.
last_page: db 1 ; The last page in scrollback; PGUP has no effect.
displayed_page: db 0 ; The currently displayed page; PGUP, PGDN and HOME can work or not based on the page number.

; System status.
system_status: db 00 ; Contains a value describing the current system's status and what functionalities should be restricted (to be revised).
					 ; - 00: normal status, everything is allowed.
					 ; - 02: memory detection failed, files can't be opened and other programs can't be launched (currently has no effect).

; Printing status.
print_control: db 00 ; Contains a value describing how printing should be restricted (expandable for more values and purposes).
					 ; - 00: normal printing, everything is allowed.
					 ; - 02: auto newline control, one line feed (LF) gets blocked, then it is disabled;
					 ;		 done to prevent an extra newline after an automatic one happened.
					 ; - 04: new page control, all line feeds (LF) get blocked, only disabled by a printing character except carriage return (CR);
					 ;		 done to avoid blank lines at the beginning of pages (to save space) after a page change happened. 

; END OF IMPORTANT VALUES.




; ########################################




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
			  "We are currently running in 16 bit real-mode.", ENDL, \
			  "The video mode is 80*25 4-bit colour text mode, but the output is monochrome.", ENDL, \
			  "Type 'help' for general help; type 'sysinfo' for more information.", ENDL, \
			  "Use the 'PgUp' and 'PgDn' buttons to scroll through the 8 pages.", ENDL, 0

; Blank page messages, printed in any empty page at the beginning; after the first one, the number of the page is printed.
msg_page_empty_1: db "Page ", 0
msg_page_empty_2: db " is currently empty...", 0

; Continue on memory detection failure message, printed when the user chooses to continue even though memory detection failed.
msg_continue_memory_detect_failed: db ENDL, "Continuing with limited functionalities.", ENDL, 0

; Success message, used for testing purposes.
msg_success: db "Success!", ENDL, 0

; Prompt message, which prompts for a command.
msg_enter_command: db ENDL, "shell@lari-os > ", 0

; Invalid command message, printed when the entered command is not in the command table.
msg_invalid_command: db "The command is not present in the command table!", ENDL, 0

; Stub command message, printed when the entered command is valid but not yet available or fully implemented.
msg_command_stub: db "This command is still a stub and therefore is currently not available.", ENDL, \
					 "Check the 'todo.txt' file to track the development progress.", ENDL, 0

; Help message, printed by the 'help' command, contains more detailed instructions and information.
msg_help_1: db "Welcome to LARI-OS!", ENDL, \
			 "This is a CLI (Command Line Interface) environment, so everything is executed v-ia commands.", ENDL, \
			 "The following list includes all available commands, with which you will be able to control the system:", ENDL, \
			 "display information, read and write data on a disk, launch more advanced progra-ms and control the computer.", ENDL, 0

; Help list messages, printed in sequence to build a list of all commands present in the command table.
msg_help_list_1: db ENDL, "There are ", 0
msg_help_list_2: db " available commands:", 0
msg_help_list_3: db ENDL, "- ", 0

msg_help_2: db ENDL, ENDL, "When typing commands, use 'Backspace' to delete the last character;", ENDL, \
			   "To navigate between pages, use 'PgUp' to scroll up and 'PgDn' to scroll down;", ENDL, \
			   "Use 'Home' to return to the active page, where the last output was printed.", ENDL, 0


; Poweroff message, printed by the 'poweroff' command, prompts the user to press the power button to turn off the computer.
msg_poweroff: db "Press the power button to turn off the computer.", ENDL, 0

; END OF NORMAL MESSAGES.


; ####################


; ERROR MESSAGES:

; Define strings for error messages.

; Memory detection failure error message, printed if memory detection failed, prompts the user to choose whether to continue or not.
err_memory_detect_failed: db "Low-memory (<1MiB) detection via BIOS interrupt INT 0x12 has failed!", ENDL, ENDL, \
							 "You can choose whether continue using the OS but with limited functionalities:", ENDL, \
							 "disk data R/W operations and memory allocation will be disabled;", ENDL, \
							 "no programs outside of the default internal commands will be able to run.", ENDL, \
							 "Do you want to continue (y/n)? >  ", 0

; END OF ERROR MESSAGES.

; END OF TEXT MESSAGES.




; ########################################




; COMMAND HANDLING:

; Buffers, counters and tables for managing commands and user inputs.

; Entered command buffer, for holding the typed characters (31 bytes and 1 NULL character).
cmd_input_buffer: times 32 db 0

; Entered command lenght, for comparing and matching the input with the table.
cmd_input_lenght: db 0


; COMMAND TABLE:

; Define a table for known and valid commands.

; Entry structure (offset and lenght in decimal):
; - NULL-terminated name, padded with zeros (offs 00, len 12),
; - call to the command executor (offs 12, len 3),
; - return instruction to the main code (offs 15, len 1).

; Number of available commands.
cmd_entries_count: dw (exe_hello - cmd_table) / 16

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

; END OF COMMAND TABLE.

; END OF COMMAND HANDLING.




; ########################################




; COMMAND EXECUTERS:

; This command executers, which get called from the command table, handle the command on their own.
; They return to the table's entry's return, which gives back control to the main loop.


; HELLO COMMAND:

; Execute the 'hello' command: print the welcome message.
exe_hello:

	; Print the welcome message.
	mov si, msg_hello
	call prints
	ret

; END OF HELLO COMMAND.


; ####################


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
	call printd
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


; ####################


; SYSINFO COMMAND:

; Execute the 'sysinfo' command: stub, work in progress.
exe_sysinfo:

	; Print the stub command message.
	mov si, msg_command_stub
	call prints

	; Return.
	ret

; END OF SYSINFPO COMMAND.


; ####################


; POWEROFF COMMAND:

; Execute the 'poweroff' command: print the poweroff message and halt the processor.
exe_poweroff:

	; Print the poweroff message.
	mov si, msg_poweroff
	call prints

	; Disable maskable interrupts and halt the process; it should never return.
	cli
	hlt
	ret

; END OF POWEROFF COMMAND.

; END OF COMMAND EXECUTERS.
