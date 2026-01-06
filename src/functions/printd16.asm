; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; PRINTD16:

; Print a 16-bit number into its decimal ASCII representation.

; Inputs:
; - AX = number to print.

; Outputs nothing, all registers are preserved.

printd16:

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

; END OF PRINTD16.
