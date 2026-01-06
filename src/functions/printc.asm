; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; PRINTC:

; Print a character in TTY mode on the active page.

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

	; Print the character in AL.
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
