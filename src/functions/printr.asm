; Copyright © 2024-2025 TheForge-2
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; PRINTR:

; Repeatedly print a character via 'printc'.

; Inputs:
; - AL = ASCII code of the character to print.
; - CL = number of times to print the character.

; Outputs nothing, all registers are preserved.

printr:

	; Save the registers.
	pusha

	; Clear the high byte of the counter.
	xor ch, ch

; Loop for calling 'printc' CL times.
.printc_loop:

	call printc
	loop .printc_loop

; Restore the registers and return.
.done:

	popa
	ret
