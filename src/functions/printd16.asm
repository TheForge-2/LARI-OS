; PRINTD16:

; 'printd16': print a 16-bit number into its decimal ASCII representation.

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
