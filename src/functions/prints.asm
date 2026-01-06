; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; PRINTS:

; Print a string in TTY mode.

; Inputs:
; - DS:SI = address of the NULL-terminated string to print.

; Outputs nothing, all registers are preserved.

prints:

	; Save the registers and clear the direction flag.
	pusha
	cld

; Loop for printing the ASCII of the byte pointed at by SI.
.putc:

	; Load the byte at SI in AL and break for 0x00.
	lodsb
	test al, al
	jz .done

	; Print it, then repeat.
	call printc
	jmp .putc

; Restore the registers and return.
.done:

	popa
	ret

; END OF PRINTS.
