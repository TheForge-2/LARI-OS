; PRINTD32:

; 'printd32': print a 32-bit number into its decimal ASCII representation.

; Inputs:
; - EAX = number to print.

; Outputs nothing, all registers are preserved.

printd32:

	; Set up the divisor (EBX) and the counter (CX).	
	pushad
	mov ebx, 10
	xor cx, cx

; Store each digit in the stack.
.store_digit:

	; Separate the digit in DX and push it.
	xor edx, edx
	div ebx
	push dx

	; Check if all digits were acquired and increment the counter
	inc cx
	cmp eax, 0
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

	popad
	ret

; END OF PRINTD32.
