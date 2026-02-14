; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; PRINTD16:

; Print a 16-bit number into its decimal ASCII representation.

; Inputs:
; - AX = number to print;
; - DL = exact number of digits to print (0 if standard).

; Outputs nothing, all registers are preserved.

printd16:

	; Save the registers.
	pusha
	xor dh, dh ; Clear DH (as only DL is used for input).
	mov di, dx ; Save the DX register (which contains the function input), as it will be used.

	; Set up the divisor (BX) and the counter (CX).
	mov bx, 10
	xor cx, cx

; Store each digit in the stack.
.store_digit:

	; Separate the digit in DX and push it.
	xor dx, dx
	div bx
	push dx

	; Check if all digits were acquired and increment the counter.
	inc cx
	cmp ax, 0
	jnz .store_digit

.check_input:

	; If yes, check whether the caller specified a number of digits.
	cmp di, 0
	je .putd ; If not, then proceed normally.

	; Check whether the requested digits (DI) are more, less or the same as the number digits (CX).
	mov bx, di ; Save the input in BX.
	cmp di, cx
	je .putd
	ja .add_zeros
	jb .discard_digits

; Add zeros to the number.
.add_zeros:

	; Get the difference of digits in CX.
	xchg cx, di
	sub cx, di

; Push zeros to the stack in a loop.
.add_zeros_loop:

	; Loop CX times.
	push 0
	loop .add_zeros_loop

	; Restore the input digits and continue.
	mov cx, bx
	jmp .putd

; Remove initial digits from the number.
.discard_digits:

	; Get the difference of digits in CX.
	sub cx, di

; Discard digits by popping them from the stack.
.discard_digits_loop:

	; Loop CX times.
	pop ax
	loop .discard_digits_loop

	; Restore the input digits and continue.
	mov cx, bx

; Convert and print each digit.
.putd:

	; Convert each digit to ASCII and print it.
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
