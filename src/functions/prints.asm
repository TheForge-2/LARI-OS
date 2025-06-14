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
